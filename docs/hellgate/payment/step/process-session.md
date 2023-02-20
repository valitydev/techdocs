# Обработка сессии

### Немного о том что такое сессия

Сессия - это...

### Работа HG с сессией при инициализации (`process_session`)

1. Из поля состояния (`St`) достается поле `Activity`

2. Из `Activity` достается сессия (`get_activity_session`)

    2.1. Из поля состояния (`St`) достается поле `Target`

    2.2. Из поля `Target` достается сессия (`get_session`)

    2.2.1. Из поля `Target` получается `TargetType` (`get_target_type`).
    Тип может быть: `processed`, `captured`, `cancelled`, `refunded`

    2.2.2. Из состояния машины `St` достается список (`map`) сессийи по
    полученному `TargetType` достается актуальная сессия

3. Сессия для `TargetType` была найдена?

    3.а. Сессия не найдена, поэтому создается новая

    3.а.1. Получение из контекста (`St`) поля `Target`, а из него `TargetType` (`processed` | `captured` | `cancelled` | `refunded`)

    3.а.2. Создание нового объекта `Action` ([hg_machine_action:new()](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L320))

    3.а.3. Валидация этапа `processing` на дедлайн (`validate_processing_deadline`)
    и если он был достигнут выбрасывается ошибка ([process_failure](../../meta/process_failure.md))

    3.а.4. Создается новое событие сессии `Events = start_session(Target)`

    3.а.5. `Result = {Events, hg_machine_action:set_timeout(0, Action)}` (todo: )

    3.а.6. Переход на следующий этап исполнения

    3.b. Сессия была найдена (`process_session(Session0, St = #st{repair_scenario = Scenario})`)

    3.b.1. Проверка на то является ли текущая операция операцией восстановления.
    Если является, то подтягивается информация из [InvoiceRepairComplex](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L876).
    В противном случае используется найденная сессия.

    3.b.2. Создается [платежная информация](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L189) (`construct_payment_info`)

    3.b.3. В актуальную сессию устанавливается значение `payment_info`

    3.b.4. Вывод `Activity` (может быть active, suspended, finished, repair) из `session`. 

    3.b.5. Обработка сессии (`process`) в зависимости от `Activity`.

    3.b.5.a. Обработка этапа `active` (`process_active_session`). 

    3.b.5.a.1. Создание контекста прокси (`session`, `payment_info`, `options`)

    3.b.5.a.2. Получение из сессии данных о пути (`Route`)

    3.b.5.a.3. Вызов адаптера к выбранному провайдеру ([ProviderProxy.ProcessPayment](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L341)).
    В случае получения ошибки выбрасывается исключение `result_unexpected`, а так же 
    в `fault-detector` [отправляется запись об ошибке](../../meta/notify_fault_detector.md) при работе с провайдером

    3.b.5.b. Обработка этапа `suspended` (`process_callback_timeout`). 
    Анализ объекта `timeout_behaviour` указанного в полученной сессии

    3.b.5.b.1. В `timeout_behaviour` указан `callback` 

    3.b.5.b.1.1. Обработка полученного `Payload` (`process_session_callback`)

    3.b.5.b.1.1.1. Получение из данных сессии `Proxy`(`Payment`) `context` (session, payment_info, options),
    а так же получение данных о роутинге (`Route`)
    
    3.b.5.b.1.1.2. Вызов обработчика callback'a на стороне адатпреа 
    ([ProviderProxy.HandlePaymentCallback](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L346))
    В случае получения ошибки выбрасывается исключение `result_unexpected`, а так же
    в `fault-detector` [отправляется запись об ошибке](../../meta/notify_fault_detector.md) при работе с провайдером

    3.b.5.b.1.2. Обработка ответа от провайдера (`handle_callback_result`). Полученный
    от адаптера [ответ](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L297)

    3.b.5.b.1.2.1. Выполнение связки с внешним `ID` транзакции если такой `ID` был получен в `TransactionInfo` (`bind_transaction`)

    3.b.5.b.1.2.2. Обновление состояния операции (Изменился статус или если да, то смена на новую) 
    (`update_proxy_state`). 
    
    3.b.5.b.1.3. Обработка состояния взаимодействия ([handle_interaction_intent](../../meta/handle_interation_intent.md))
    
    3.b.5.b.1.4. Обработка состояния прокси ([handle_proxy_intent]())
    
    3.b.5.b.1.5. Применение изменений ([apply_result](../../meta/apply_result.md))

    3.b.5.b.2. В `timeout_behaviour` указан `operation_failure`

    3.b.5.b.2.1. Для такого платежа устанавливаются флаги session_finished и session_failed

    3.b.5.b.2.2. Выполняется операция mg_stateproc_ComplexAction

    3.b.5.b.2.3. Применение изменений ([apply_result](../../meta/apply_result.md))

    3.b.5.c. Обработка этапа `repair`. Данный этап аналогичен пункту 3.b.5.b., 
    кроме смены статуса сессии на session_activated, а затем Применение 
    изменений ([apply_result](../../meta/apply_result.md))

    3.b.5.d. Обработка этапа `finished`. Остается все как есть

    3.b.5.c. Обработка этапа `finished` . 

    3.b.5.d. Обработка этапа `repair` (`repair`). 
    
    3.b.6. Завершение обработки сессии (`finish_session_processing`)

    3.b.1. Оборачивание событий (`Events0 = hg_session:wrap_events(Events, Session)`)

    3.b.2. Сравнение на присутствие сессии возврата
    ```erlang
    Events1 =
        case Activity of
            {refund_session, ID} ->
                [?refund_ev(ID, Ev) || Ev <- Events0];
            _ ->
                Events0
        end,
    ```
 
    3.b.3. Получение статуса (`active` | `suspended` | `finished`) 
    и результата (`Finished`(`Success` | `Failure`) | `Processed`) из полученной сессии
 
    3.b.3.1. Если `status = finished`, а `result = session_succeeded`, то происходит обработка
    успешной сессии

    3.b.3.1.1. Из сессии достается `TargetType` (`processed` | `captured` | `cancelled` | `refunded`)

    3.b.3.1.2. По необходимости оповещается `fault-detector` 
    (посылается событие `finish` для платежа) (`maybe_notify_fault_detector`)

    3.b.3.1.3. Создается новое действие для машины (todo: уточнить у Артема)
    ```erlang
    NewAction = hg_machine_action:set_timeout(0, Action)
    ```

    3.b.3.2. Если `status = finished`, а `result = session_failed`, то происходит обработка
    ошибки ([process_failure](../../meta/process_failure.md))

    3.b.3.3. Если ни одно из условий не выполняется, то происходит переход к следующему шагу


---

Далее:
- [Обработка шага "processing_accounter"](processing-accounter.md)

Назад:
- [Обработка шага "cash_flow_building"](cash-flow-building.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)
 