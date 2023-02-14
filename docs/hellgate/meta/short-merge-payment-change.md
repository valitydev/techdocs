## Этапы переходов для платежа в HG

0. Список переходов Activity успешного платежа в HG
```
(processed)
new -> risc_scoring
risc_scoring -> routing
routing -> cash_flow_building
cash_flow_building -> processing_session
processing_session -> processing_session (some time)
processing_session -> processing_accounter
processing_accounter -> flow_waiting
(captured)
flow_waiting -> processing_capture
processing_capture -> updating_accounter
updating_accounter -> finalizing_session
finalizing_session -> finalizing_accounter
finalizing_accounter -> idle
```

---

1. Если состояние не определено, но переход на этап new, а далее 
если Change = payment_started и переход был для new, то установить значение
target = processed, activity = {payment, risk_scoring}
```
Activity: new -> risc_scoring
Target: processed
```
---

2. Если пришедший change = risk_score_changed, то происходит
перевод activity в {payment, routing}
```
Activity: risc_scoring -> routing
Target: processed
```
---
3. Если пришедший change = route_changed, то происходит
   перевод activity в {payment, cash_flow_building}
```
Activity: routing -> cash_flow_building
Target: processed
```
---
4. Если пришедший change = payment_capture_started, то происходит
   перевод activity в {payment, processing_capture}
```
Activity: flow_waiting -> processing_capture
Target: captured
```
---
5. Первоначально проверяется, что change = cash_flow_changed.
   Далее анализируется валидность присутствующего Activity (должно быть 
   или cash_flow_building, или processing_capture) и если пришедший
   Activity = cash_flow_building, то происходит переход на шаг processing_session,
   а если Activity = processing_capture, то устанавливается updating_accounter.

```
Activity: cash_flow_building -> processing_session
Target: processed
```

или

```
Activity: processing_capture -> updating_accounter
Target: captured
```

---
6. Если пришедший change = payment_status_changed(status = captured).

    6.1. проверка шага из Activity. Корректные шаги для функции: finalizing_accounter

    6.2. activity устанавливается в idle

    6.3. в payment обновляется cost и status 

```
Activity: finalizing_accounter -> idle
Target: captured
```

---
7. Если пришедший change = payment_status_changed(status = processed).

    7.1. проверка шага из Activity. Корректные шаги для функции: processing_accounter

    7.2. activity устанавливается в flow_waiting, у payment обновляется статус на processed
```
Activity: processing_accounter -> flow_waiting
Target: processed
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

```
Activity: processing_session -> processing_session
Target: processed | captured
```

```
Activity: flow_waiting -> finalizing_session
Target: processed | captured
```

```
Activity: processing_capture -> finalizing_session
Target: captured
```

```
Activity: updating_accounter -> finalizing_session
Target: processed | captured
```

```
Activity: finalizing_session -> finalizing_session
Target: processed | captured
```

---
9. Если произошло изменение сессии session_ev(InvoicePaymentSessionChange)

    9.1. проверка шага из Activity. Корректные шаги для функции: processing_session, finalizing_session

    9.2. обработка события и получение нового экземпляра сессии

    9.3. статус полученной сессии = finished, а результат session_succeeded ?
    - текущая Activity = processing_session -> processing_accounter
    - текущая Activity = finalizing_session -> finalizing_accounter
    - в противном случае возвращается текущая Activity

```
Activity: processing_session -> processing_accounter
Target: processed | captured
```
или
```
Activity: finalizing_session -> finalizing_accounter
Target: processed | captured
```
---
10. Если пришедший change = payment_status_changed(Status = failed).

   10.1. проверка шага из Activity. Корректные шаги для функции:
   risk_scoring, routing, routing_failure, processing_failure.

   10.2. activity устанавливается в idle, failure = undefined,
   а для payment устанавливается пришедший статус

```
Activity: risk_scoring, routing, routing_failure, processing_failure -> idle
Target: Target
Status: failed
```
---
11. Если пришедший change = payment_status_changed(status = cancelled).

   11.1. проверка шага из Activity. Корректные шаги для функции: finalizing_accounter

   11.2. activity устанавливается в idle, а для payment устанавливается пришедший статус

```
Activity: finalizing_accounter -> idle
Target: cancelled
```
---
12. Если пришедший change = payment_status_changed(status = refunded).

    12.1. Установка нового статуса для Payment - refunded
```
Activity: ? -> idle
Target: refunded
```
---
13. Если пришедший change = payment_status_changed(status = charged_back).

    13.1. Установка нового статуса для Payment - charged_back
```
Activity: ? -> idle
Target: charged_back
```
14. Если пришедший change = refund_ev. Анализ события и если:

    14.1.1. Event = refund_created -> Activity: refund_new

    14.1.2. Event = ?session_ev(?refunded(), ?session_started()) -> Activity: refund_session

    14.1.3. Event = ?session_ev(?refunded(), ?session_finished(?session_succeeded())) -> Activity: refund_accounter

    14.1.4. Event = ?refund_status_changed(?refund_succeeded()) -> Activity: idle

    14.1.5. Event = ?refund_rollback_started(_) -> Activity: refund_failure

    14.1.6. Event = ?refund_status_changed(?refund_failed(_)) -> Activity: refund_failure

    14.1.7. _ -> refund_session

    14.2. Если по итогу merge у возврата статус failed или succeeded, то Activity устанавливается 
    в idle

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

    15.1. ?adjustment_created(_) -> adjustment_new

    15.2. ?adjustment_status_changed(?adjustment_processed()) -> adjustment_pending

    15.3. ?adjustment_status_changed(_) -> idle
```
adjustment_new -> adjustment_pending -> idle
```
---
16. Если пришедший change = rec_token_acquired. Сначала происходит
   валидация корректности Activity (может быть или processing_session,
   или finalizing_session) и если все корректно, то в структуре состояния
   [St()](meta/st.md) устанавливается значение токена для оплаты.
```
Activity: processing_session -> processing_session
```
или
```
Activity: finalizing_session -> finalizing_session
```
---
17. Если пришедший change = payment_rollback_started.

   17.1. проверка корректности шага в Activity (cash_flow_building, processing_session)

   17.2. Если в структуре [St()](meta/st.md) cash_flow не указан, то устанавливается шаг
   routing_failure, иначе - processing_failure

```
Activity: cash_flow_building, processing_session
->
CashFlow exists -> processing_failure
CashFlow doesn't exist -> routing_failure
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