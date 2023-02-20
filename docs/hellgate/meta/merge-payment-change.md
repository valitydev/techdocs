## Этапы переходов для платежа в HG

---

1. Если состояние не определено, но переход на этап new, а далее 
если Change = payment_started и переход был для new, то установить значение
target = processed, activity = {payment, risk_scoring}

```erlang
-spec merge_change(change(), st() | undefined, change_opts()) -> st().
merge_change(Change, undefined, Opts) ->
    merge_change(Change, #st{activity = {payment, new}}, Opts);

merge_change(Change = ?payment_started(Payment), #st{} = St, Opts) ->
    _ = validate_transition({payment, new}, Change, St, Opts),
    St#st{
        target = ?processed(),
        payment = Payment,
        activity = {payment, risk_scoring},
        timings = hg_timings:mark(started, define_event_timestamp(Opts))
    };

-define(payment_started(Payment),
  {invoice_payment_started, #payproc_InvoicePaymentStarted{
    payment = Payment,
    risk_score = undefined,
    route = undefined,
    cash_flow = undefined
  }}
).

-define(processed(),
  {processed, #domain_InvoicePaymentProcessed{}}
).
```
---

2. Если пришедший change = risk_score_changed, то происходит
перевод activity в {payment, routing}

```erlang
merge_change(Change = ?risk_score_changed(RiskScore), #st{} = St, Opts) ->
    _ = validate_transition({payment, risk_scoring}, Change, St, Opts),
    St#st{
        risk_score = RiskScore,
        activity = {payment, routing}
    };

-define(risk_score_changed(RiskScore),
  {invoice_payment_risk_score_changed, #payproc_InvoicePaymentRiskScoreChanged{risk_score = RiskScore}}
).
```
---
3. Если пришедший change = route_changed, то происходит
   перевод activity в {payment, cash_flow_building}

```erlang
merge_change(Change = ?route_changed(Route, Candidates), St, Opts) ->
    _ = validate_transition({payment, routing}, Change, St, Opts),
    St#st{
        route = Route,
        candidate_routes = ordsets:to_list(Candidates),
        activity = {payment, cash_flow_building}
    };

-define(route_changed(Route),
  {invoice_payment_route_changed, #payproc_InvoicePaymentRouteChanged{route = Route}}
).
```
---
4. Если пришедший change = payment_capture_started, то происходит
   перевод activity в {payment, processing_capture}

```erlang
merge_change(Change = ?payment_capture_started(Data), #st{} = St, Opts) ->
    _ = validate_transition([{payment, S} || S <- [flow_waiting]], Change, St, Opts),
    St#st{
        capture_data = Data,
        activity = {payment, processing_capture},
        allocation = Data#payproc_InvoicePaymentCaptureData.allocation
    };

-define(payment_capture_started(Data),
  {invoice_payment_capture_started, #payproc_InvoicePaymentCaptureStarted{
    data = Data
  }}
).
```
---
5. Первоначально проверяется, что change = cash_flow_changed.
   Далее анализируется валидность присутствующего Activity (должно быть 
   или cash_flow_building, или processing_capture) и если пришедший
   Activity = cash_flow_building, то происходит переход на шаг processing_session,
   а если Activity = processing_capture, то устанавливается updating_accounter.

```erlang
merge_change(Change = ?cash_flow_changed(CashFlow), #st{activity = Activity} = St0, Opts) ->
    _ = validate_transition(
        [
            {payment, S}
         || S <- [
                cash_flow_building,
                processing_capture
            ]
        ],
        Change,
        St0,
        Opts
    ),
    St = St0#st{
        final_cash_flow = CashFlow
    },
    case Activity of
        {payment, cash_flow_building} ->
            St#st{
                cash_flow = CashFlow,
                activity = {payment, processing_session}
            };
        {payment, processing_capture} ->
            St#st{
                partial_cash_flow = CashFlow,
                activity = {payment, updating_accounter}
            };
        _ ->
            St
    end;

-define(cash_flow_changed(CashFlow),
  {invoice_payment_cash_flow_changed, #payproc_InvoicePaymentCashFlowChanged{
    cash_flow = CashFlow
  }}
).
```
---
6. Если пришедший change = payment_status_changed(status = captured).

    6.1. проверка шага из Activity. Корректные шаги для функции: finalizing_accounter

    6.2. activity устанавливается в idle

    6.3. в payment обновляется cost и status

```erlang
merge_change(Change = ?payment_status_changed({captured, Captured} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition({payment, finalizing_accounter}, Change, St, Opts),
    St#st{
        payment = Payment#domain_InvoicePayment{
            status = Status,
            cost = get_captured_cost(Captured, Payment)
        },
        activity = idle,
        timings = accrue_status_timing(captured, Opts, St),
        allocation = get_captured_allocation(Captured)
    };

-define(payment_status_changed(Status),
  {invoice_payment_status_changed, #payproc_InvoicePaymentStatusChanged{status = Status}}
).
```
---
7. Если пришедший change = payment_status_changed(status = processed).

    7.1. проверка шага из Activity. Корректные шаги для функции: processing_accounter

    7.2. activity устанавливается в flow_waiting, у payment обновляется статус на processed

```erlang
merge_change(Change = ?payment_status_changed({processed, _} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition({payment, processing_accounter}, Change, St, Opts),
    St#st{
        payment = Payment#domain_InvoicePayment{status = Status},
        activity = {payment, flow_waiting},
        timings = accrue_status_timing(processed, Opts, St)
    };
```
--- 
8. Если для некоторого Target пришел change = session_started.

    8.1. проверка шага из Activity. Корректные шаги для функции:
    processing_session, flow_waiting, processing_capture, updating_accounter, finalizing_session

    8.2. Если activity
    - processing_session -> processing_session
    - flow_waiting -> finalizing_session
    - processing_capture -> finalizing_session
    - updating_accounter -> finalizing_session
    - finalizing_session -> finalizing_session

```erlang
merge_change(
    Change = ?session_ev(Target, Event = ?session_started()),
    #st{activity = Activity} = St,
    Opts
) ->
    _ = validate_transition(
        [
            {payment, S}
         || S <- [
                processing_session,
                flow_waiting,
                processing_capture,
                updating_accounter,
                finalizing_session
            ]
        ],
        Change,
        St,
        Opts
    ),
    % FIXME why the hell dedicated handling
    Session0 = hg_session:apply_event(Event, undefined, create_session_event_context(Target, St, Opts)),
    %% We need to pass processed trx_info to captured/cancelled session due to provider requirements
    Session1 = hg_session:set_trx_info(get_trx(St), Session0),
    St1 = add_session(Target, Session1, St#st{target = Target}),
    St2 = save_retry_attempt(Target, St1),
    case Activity of
        {payment, processing_session} ->
            %% session retrying
            St2#st{activity = {payment, processing_session}};
        {payment, PaymentActivity} when PaymentActivity == flow_waiting; PaymentActivity == processing_capture ->
            %% session flow
            St2#st{
                activity = {payment, finalizing_session},
                timings = try_accrue_waiting_timing(Opts, St2)
            };
        {payment, updating_accounter} ->
            %% session flow
            St2#st{activity = {payment, finalizing_session}};
        {payment, finalizing_session} ->
            %% session retrying
            St2#st{activity = {payment, finalizing_session}};
        _ ->
            St2
    end;

-define(session_ev(Target, Payload),
  {invoice_payment_session_change, #payproc_InvoicePaymentSessionChange{
    target = Target,
    payload = Payload
  }}
).

-define(session_started(),
  {session_started, #payproc_SessionStarted{}}
).
```
---
9. Если произошло изменение сессии session_ev(InvoicePaymentSessionChange)

    9.1. проверка шага из Activity. Корректные шаги для функции: processing_session, finalizing_session

    9.2. обработка события и получение нового экземпляра сессии

    9.3. статус полученной сессии = finished, а результат session_succeeded ?
    - текущая Activity = processing_session -> processing_accounter
    - текущая Activity = finalizing_session -> finalizing_accounter
    - в противном случае возвращается текущая Activity

```erlang
merge_change(Change = ?session_ev(Target, Event), St = #st{activity = Activity}, Opts) ->
    _ = validate_transition([{payment, S} || S <- [processing_session, finalizing_session]], Change, St, Opts),
    Session = hg_session:apply_event(
        Event,
        get_session(Target, St),
        create_session_event_context(Target, St, Opts)
    ),
    St1 = update_session(Target, Session, St),
    % FIXME leaky transactions
    St2 = set_trx(hg_session:trx_info(Session), St1),
    case Session of
        #{status := finished, result := ?session_succeeded()} ->
            NextActivity =
                case Activity of
                    {payment, processing_session} ->
                        {payment, processing_accounter};
                    {payment, finalizing_session} ->
                        {payment, finalizing_accounter};
                    _ ->
                        Activity
                end,
            St2#st{activity = NextActivity};
        _ ->
            St2
    end.

-define(session_ev(Target, Payload),
  {invoice_payment_session_change, #payproc_InvoicePaymentSessionChange{
    target = Target,
    payload = Payload
  }}
).

-define(session_succeeded(),
  {succeeded, #payproc_SessionSucceeded{}}
).

```
---
10. Если пришедший change = payment_status_changed(Status = failed).

   10.1. проверка шага из Activity. Корректные шаги для функции:
   risk_scoring, routing, routing_failure, processing_failure.

   10.2. activity устанавливается в idle, failure = undefined,
   а для payment устанавливается пришедший статус

```erlang
merge_change(Change = ?payment_status_changed({failed, _} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition(
        [
            {payment, S}
         || S <- [
                risk_scoring,
                routing,
                routing_failure,
                processing_failure
            ]
        ],
        Change,
        St,
        Opts
    ),
    St#st{
        payment = Payment#domain_InvoicePayment{status = Status},
        activity = idle,
        failure = undefined,
        timings = accrue_status_timing(failed, Opts, St)
    };

-define(payment_status_changed(Status),
  {invoice_payment_status_changed, #payproc_InvoicePaymentStatusChanged{status = Status}}
).
```
---
11. Если пришедший change = payment_status_changed(status = cancelled).

   11.1. проверка шага из Activity. Корректные шаги для функции: finalizing_accounter

   11.2. activity устанавливается в idle, а для payment устанавливается пришедший статус

```erlang
merge_change(Change = ?payment_status_changed({cancelled, _} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition({payment, finalizing_accounter}, Change, St, Opts),
    St#st{
        payment = Payment#domain_InvoicePayment{status = Status},
        activity = idle,
        timings = accrue_status_timing(cancelled, Opts, St)
    };

-define(payment_status_changed(Status),
  {invoice_payment_status_changed, #payproc_InvoicePaymentStatusChanged{status = Status}}
).
```
---

12. Если пришедший change = payment_status_changed(status = refunded).

    12.1. Установка нового статуса для Payment - refunded

```erlang
merge_change(Change = ?payment_status_changed({refunded, _} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition(idle, Change, St, Opts),
    St#st{
        payment = Payment#domain_InvoicePayment{status = Status}
    };
```
---
13. Если пришедший change = payment_status_changed(status = charged_back).

    13.1. Установка нового статуса для Payment - charged_back

```erlang
merge_change(Change = ?payment_status_changed({charged_back, _} = Status), #st{payment = Payment} = St, Opts) ->
    _ = validate_transition(idle, Change, St, Opts),
    St#st{
        payment = Payment#domain_InvoicePayment{status = Status}
    };
```
---
14. Если пришедший change = refund_ev. Анализ собития и если оно рано:

    14.1. refund_created

    14.2. ?session_ev(?refunded(), ?session_started())

    14.3. ?session_ev(?refunded(), ?session_finished(?session_succeeded()))

    14.4. ?refund_status_changed(?refund_succeeded())

    14.5. ?refund_rollback_started(_)

    14.6. ?refund_status_changed(?refund_failed(_))

    14.7. _

```erlang
merge_change(Change = ?refund_ev(ID, Event), St, Opts) ->
    St1 =
        case Event of
            ?refund_created(_, _, _) ->
                _ = validate_transition(idle, Change, St, Opts),
                St#st{activity = {refund_new, ID}};
            ?session_ev(?refunded(), ?session_started()) ->
                _ = validate_transition([{refund_new, ID}, {refund_session, ID}], Change, St, Opts),
                St#st{activity = {refund_session, ID}};
            ?session_ev(?refunded(), ?session_finished(?session_succeeded())) ->
                _ = validate_transition({refund_session, ID}, Change, St, Opts),
                St#st{activity = {refund_accounter, ID}};
            ?refund_status_changed(?refund_succeeded()) ->
                _ = validate_transition([{refund_accounter, ID}], Change, St, Opts),
                RefundSt0 = merge_refund_change(Event, try_get_refund_state(ID, St), St, Opts),
                Allocation = get_allocation(St),
                FinalAllocation = hg_maybe:apply(
                    fun(A) ->
                        #domain_InvoicePaymentRefund{allocation = RefundAllocation} = get_refund(
                            RefundSt0
                        ),
                        {ok, FA} = hg_allocation:sub(A, RefundAllocation),
                        FA
                    end,
                    Allocation
                ),
                St#st{allocation = FinalAllocation};
            ?refund_rollback_started(_) ->
                _ = validate_transition([{refund_session, ID}, {refund_new, ID}], Change, St, Opts),
                St#st{activity = {refund_failure, ID}};
            ?refund_status_changed(?refund_failed(_)) ->
                _ = validate_transition([{refund_failure, ID}], Change, St, Opts),
                St;
            _ ->
                _ = validate_transition([{refund_session, ID}], Change, St, Opts),
                St
        end,
    RefundSt1 = merge_refund_change(Event, try_get_refund_state(ID, St1), St1, Opts),
    St2 = set_refund_state(ID, RefundSt1, St1),
    case get_refund_status(get_refund(RefundSt1)) of
        {S, _} when S == succeeded; S == failed ->
            St2#st{activity = idle};
        _ ->
            St2
    end;
```
---
15. Если пришедший change = adjustment_ev. Анализ собития и если оно рано:

    15.1. ?adjustment_created(_)

    15.2. ?adjustment_status_changed(?adjustment_processed())

    15.3. ?adjustment_status_changed(_)

```erlang
merge_change(Change = ?adjustment_ev(ID, Event), St, Opts) ->
    St1 =
        case Event of
            ?adjustment_created(_) ->
                _ = validate_transition(idle, Change, St, Opts),
                St#st{activity = {adjustment_new, ID}};
            ?adjustment_status_changed(?adjustment_processed()) ->
                _ = validate_transition({adjustment_new, ID}, Change, St, Opts),
                St#st{activity = {adjustment_pending, ID}};
            ?adjustment_status_changed(_) ->
                _ = validate_transition({adjustment_pending, ID}, Change, St, Opts),
                St#st{activity = idle}
        end,
    Adjustment = merge_adjustment_change(Event, try_get_adjustment(ID, St1)),
    St2 = set_adjustment(ID, Adjustment, St1),
    % TODO new cashflow imposed implicitly on the payment state? rough
    case get_adjustment_status(Adjustment) of
        ?adjustment_captured(_) ->
            apply_adjustment_effects(Adjustment, St2);
        _ ->
            St2
    end;
```
---

16. Если пришедший change = rec_token_acquired. Сначала происходит 
   валидация корректности Activity (может быть или processing_session, 
   или finalizing_session) и если все корректно, то в структуре состояния 
   [St()](meta/st.md) устанавливается значение токена для оплаты.

```erlang
merge_change(Change = ?rec_token_acquired(Token), #st{} = St, Opts) ->
    _ = validate_transition([{payment, processing_session}, {payment, finalizing_session}], Change, St, Opts),
    St#st{recurrent_token = Token};

-define(rec_token_acquired(Token),
  {invoice_payment_rec_token_acquired, #payproc_InvoicePaymentRecTokenAcquired{token = Token}}
).
```
---
17. Если пришедший change = payment_rollback_started.
   
   17.1. проверка корректности шага в Activity (cash_flow_building, processing_session)

   17.2. Если в структуре [St()](meta/st.md) cash_flow не указан, то устанавливается шаг
   routing_failure, иначе - processing_failure

```erlang
merge_change(Change = ?payment_rollback_started(Failure), St, Opts) ->
    _ = validate_transition(
        [{payment, cash_flow_building}, {payment, processing_session}],
        Change,
        St,
        Opts
    ),
    Activity =
        case St#st.cash_flow of
            undefined ->
                {payment, routing_failure};
            _ ->
                {payment, processing_failure}
        end,
    St#st{
        failure = Failure,
        activity = Activity,
        timings = accrue_status_timing(failed, Opts, St)
    };

-define(payment_rollback_started(Failure),
  {invoice_payment_rollback_started, #payproc_InvoicePaymentRollbackStarted{reason = Failure}}
).
```
---

18. Если пришедший change = chargeback_ev, то идет проверка события и выполнение 
    конктретного шага

```erlang
merge_change(Change = ?chargeback_ev(ID, Event), St, Opts) ->
    St1 =
        case Event of
            ?chargeback_created(_) ->
                _ = validate_transition(idle, Change, St, Opts),
                St#st{activity = {chargeback, ID, preparing_initial_cash_flow}};
            ?chargeback_stage_changed(_) ->
                _ = validate_transition(idle, Change, St, Opts),
                St;
            ?chargeback_levy_changed(_) ->
                _ = validate_transition([idle, {chargeback, ID, updating_chargeback}], Change, St, Opts),
                St#st{activity = {chargeback, ID, updating_chargeback}};
            ?chargeback_body_changed(_) ->
                _ = validate_transition([idle, {chargeback, ID, updating_chargeback}], Change, St, Opts),
                St#st{activity = {chargeback, ID, updating_chargeback}};
            ?chargeback_cash_flow_changed(_) ->
                Valid = [{chargeback, ID, Activity} || Activity <- [preparing_initial_cash_flow, updating_cash_flow]],
                _ = validate_transition(Valid, Change, St, Opts),
                case St of
                    #st{activity = {chargeback, ID, preparing_initial_cash_flow}} ->
                        St#st{activity = idle};
                    #st{activity = {chargeback, ID, updating_cash_flow}} ->
                        St#st{activity = {chargeback, ID, finalising_accounter}}
                end;
            ?chargeback_target_status_changed(?chargeback_status_accepted()) ->
                _ = validate_transition([idle, {chargeback, ID, updating_chargeback}], Change, St, Opts),
                case St of
                    #st{activity = idle} ->
                        St#st{activity = {chargeback, ID, finalising_accounter}};
                    #st{activity = {chargeback, ID, updating_chargeback}} ->
                        St#st{activity = {chargeback, ID, updating_cash_flow}}
                end;
            ?chargeback_target_status_changed(_) ->
                _ = validate_transition([idle, {chargeback, ID, updating_chargeback}], Change, St, Opts),
                St#st{activity = {chargeback, ID, updating_cash_flow}};
            ?chargeback_status_changed(_) ->
                _ = validate_transition([idle, {chargeback, ID, finalising_accounter}], Change, St, Opts),
                St#st{activity = idle}
        end,
    ChargebackSt = merge_chargeback_change(Event, try_get_chargeback_state(ID, St1)),
    set_chargeback_state(ID, ChargebackSt, St1);

-define(chargeback_ev(ChargebackID, Payload),
  {invoice_payment_chargeback_change, #payproc_InvoicePaymentChargebackChange{
    id = ChargebackID,
    payload = Payload
  }}
).
```
---


