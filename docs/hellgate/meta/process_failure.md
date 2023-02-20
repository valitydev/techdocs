## Обработка бизнес ошибок во время проведения платежа

### На этапе подсчета уровня риска или роутинга

Если произошла ошибка на этапе подсчета уровня риска или роутинга, то создается 
новое событие `payment_status_changed` и платеж переводится в статус `failed`.

```erlang
process_failure({payment, Step}, Events, Action, Failure, _St, _RefundSt) when
    Step =:= risk_scoring orelse
        Step =:= routing
->
    {done, {Events ++ [?payment_status_changed(?failed(Failure))], Action}};
```

### На этапе обработки или финализации сессии

Если ошибка произошла на этапе обработки сессии или ее завершения, то 
сначала проверяется возможность повтора операции. Если возможность повтора есть,
то через заданный таймаут HG пытается повторить зафейленную операцию. Если такой 
возможности нет, то сначала определяется статус зафейленной операции для отправки в 
`fault-detector` и по необходимости обновить информацию о операции.

```erlang
process_failure({payment, Step} = Activity, Events, Action, Failure, St, _RefundSt) when
    Step =:= processing_session orelse
        Step =:= finalizing_session
->
    Target = get_target(St),
    case check_retry_possibility(Target, Failure, St) of
        {retry, Timeout} ->
            _ = logger:info("Retry session after transient failure, wait ~p", [Timeout]),
            {SessionEvents, SessionAction} = retry_session(Action, Target, Timeout),
            {next, {Events ++ SessionEvents, SessionAction}};
        fatal ->
            TargetType = get_target_type(Target),
            OperationStatus = choose_fd_operation_status_for_failure(Failure),
            _ = maybe_notify_fault_detector(Activity, TargetType, OperationStatus, St),
            process_fatal_payment_failure(Target, Events, Action, Failure, St)
    end;

do_choose_fd_operation_status_for_failure({authorization_failed, {FailType, _}}) ->
  DefaultBenignFailures = [
    insufficient_funds,
    rejected_by_issuer,
    processing_deadline_reached
  ],
  FDConfig = genlib_app:env(hellgate, fault_detector, #{}),
  Config = genlib_map:get(conversion, FDConfig, #{}),
  BenignFailures = genlib_map:get(benign_failures, Config, DefaultBenignFailures),
  case lists:member(FailType, BenignFailures) of
    false -> error;
    true -> finish
  end;
```

В зависимости от статуса происходит обработка ошибки 
```erlang
process_fatal_payment_failure(?cancelled(), _Events, _Action, Failure, _St) ->
    error({invalid_cancel_failure, Failure});
process_fatal_payment_failure(?captured(), _Events, _Action, Failure, _St) ->
    error({invalid_capture_failure, Failure});
process_fatal_payment_failure(?processed(), Events, Action, Failure, _St) ->
    RollbackStarted = [?payment_rollback_started(Failure)],
    {next, {Events ++ RollbackStarted, hg_machine_action:set_timeout(0, Action)}}.

```

### На этапе создания возврата

Если произошла ошибка на этапе создания возврата, то создается
новое событие `refund_rollback_started` и платеж переводится в статус `failed` 
с определенным на этапе исполнения `failure`.


```erlang
process_failure({refund_new, ID}, [], Action, Failure, _St, _RefundSt) ->
    {next, {[?refund_ev(ID, ?refund_rollback_started(Failure))], hg_machine_action:set_timeout(0, Action)}};
```

### На этапе обработки сессии возврата

Если ошибка произошла на этапе обработки сессии или ее завершения, то
сначала проверяется возможность повтора операции. Если возможность повтора есть,
то через заданный таймаут HG пытается повторить зафейленную операцию.

```erlang
process_failure({refund_session, ID}, Events, Action, Failure, St, _RefundSt) ->
    Target = ?refunded(),
    case check_retry_possibility(Target, Failure, St) of
        {retry, Timeout} ->
            _ = logger:info("Retry session after transient failure, wait ~p", [Timeout]),
            {SessionEvents, SessionAction} = retry_session(Action, Target, Timeout),
            Events1 = [?refund_ev(ID, E) || E <- SessionEvents],
            {next, {Events ++ Events1, SessionAction}};
        fatal ->
            RollbackStarted = [?refund_ev(ID, ?refund_rollback_started(Failure))],
            {next, {Events ++ RollbackStarted, hg_machine_action:set_timeout(0, Action)}}
    end.
```

