## Обработка шага `processing_capture`

### Реализация

1. `HG` получает сигнал от `MG` и [начинает его обработку](../../machinegun/machinegun-signal-processing-workflow.md) (`process_signal`)

2. Получение из контекста [St()](docs/hellgate/meta/st.md) Opts и данных платежа, 
   а из Opts данных инвойса

3. Проверка лимитов захолдированных средств (`hold_payment_limits`)

    3.1. Получение из [St()](docs/hellgate/meta/st.md) данных по роутингу ([Route](docs/hellgate/meta/route-record.md))

    3.2. Получение лимитов по обороту (`get_turnover_limits`)

    3.2.1. Получение из контекста платежа данных Route, Opts, Party, Shop, RiskScore, а так же Payment
    (из него Cost, Payer, Revision). Из Payer достается PaymentTool. 

    3.2.2. Получение [ProviderTerms](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2387) из [PartyManagement](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2710).
    Из данных `ProviderTerms` получается [TurnoverLimitSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1705)
    и из него достаются лимиты (если отсутствуют возвращается пустой список, если есть 
    несколько значений в списке выбрасывается ошибка конфигурации)

4. Холдирование денежных средств (`hg_limiter:hold_payment_limits`). 
   Возвращается результат об успешном (или нет) резервировании денежных средств

    4.1. На основании полей Invoice, Payment и Route создается ChangeID (`construct_payment_change_id`)

    4.2. Получение изменений лимитов (`gen_limit_changes`) - создание из объекта
    [TurnoverLimit](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1695) объект 
    [LimitChange](https://github.com/valitydev/limiter-proto/blob/master/proto/limiter.thrift#L47)

    4.3. Создание объекта [LimitContext](https://github.com/valitydev/limiter-proto/blob/master/proto/limiter.thrift#L18)
    
    4.3.1. Создание [PaymentCtx](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L618)
    
    4.3.1.1. Создание [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293) 
    для `PaymentCtx`. Для данного объекта создается [InvoicePaymentStatus](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L380) 
    со статусом `captured` и подтвержденной суммой платежа `CapturedCash` 

    4.3.1.2. Конвертация [domain.PaymentRoute](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L492)
    в [base.Route](https://github.com/valitydev/limiter-proto/blob/31de59b17ad20e426b158ace6097e35330926bea/proto/limiter_base.thrift#L16)

    4.3.1.3. На основании созданных ранее объектов создается [LimitContext](https://github.com/valitydev/limiter-proto/blob/master/proto/limiter.thrift#L18),
    где:
    - в качестве op указывается объект OperationInvoicePayment
    - в качестве invoice создается объект payproc.Invoice (invoice = Invoice, payment = PaymentCtx)

    4.4. Холдирование денежных средств. На основании полученных на этапе `4.2` и `4.3`
    данных в сервисе [Limiter]() происходит [Hold]() денежных средств

5. Холдирование `CashFlow` (`hold_payment_cashflow`)

    5.1. На основании `invoice_id + payment_id` формируется идентификатор плана `PlanID`

    5.2. Из контекста платежа [St()](docs/hellgate/meta/st.md) получается финальная версия `CashFlow`

    5.3. Согласно идентификатору плана проводок и `CashFlow` из шага `5.2` формируется
    операция [Hold]() в сервисе [Accounter]()([Shumway]())

6. В рамках сессии создаются два события с Target = captured, reason = Timeout, Cost берется из 
   Payment, полученного ранее из контекста [St()](docs/hellgate/meta/st.md), а так же

    6.1. Для первого события [SessionEvent]() устанавливается `session_started` ([SessionStarted](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L252))

    6.2. Для второго события [SessionEvent]() устанавливается `session_finished(succeeded)` 
    (`session_finished` - [SessionFinished](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L254), `succeeded` - [SessionSucceeded](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L270))

7. Возврата списка событий из `п.6`, а так же инструкции для сохранения в `MG` с таймером 0.
   В качестве метаинформации для дальнейшего перехода устанавливается флаг `next`