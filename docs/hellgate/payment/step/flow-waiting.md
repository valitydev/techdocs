## Ожидание продолжения операции

### Что это и для чего нужно?

Платеж имеет несколько способов прохождения:
- одностадийно;
- двухстадийно.

Одностадийный платеж - это платеж, который происходит без холдирования денежных средств 
и после того как пользователь введет необходимые данные денежные средства с его
банковского счета моментально перечислятся на счет мерчанта.

Двухстадийных платеж - это платеж, который происходит с этапом холдирования денежных 
средств. Холдирование это процедура резервирования денежных средств без фактического 
перечисления. В определенный момент мерчант через личный кабинет сам запускает процедуру 
списания и средства со счета плательщика поступают на счет мерчанта. Это выгодно, когда
у мерчанта может быть достаточное количество возвратов и во избежание уплаты комиссий 
проще и дешевле отменить холд.

Этап `flow_waiting` фактически ожидает получение сигнала `captured` или `cancelled` для
завершения платежа.

### Реализация этапа `flow_waiting` в `HG`

1. `HG` получает сигнал от `MG` и [начинает его обработку](../../machinegun/machinegun-signal-processing-workflow.md) (`process_signal`)

2. Получение из контекста [St()](docs/hellgate/meta/st.md) Activity, Action и Target

3. Определение Target 

    3.1. Если `payment_flow` = `instant`, то создается новое событие [captured](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L314)
    с `reason` = `Timeout` и `Cost` на основе платежа

    3.2. Если `payment_flow` = `hold`, то задается поведение на случай дедлайна

    3.2.1. cancel - в этом случае будет установлен Target = cancelled

    3.2.2. capture - в этом случае будет установлен Target = [captured](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L314) 
    с `reason` = `Timeout` и `Cost` на основе платежа

4. Анализ полученного Target

    4.1. Если Target = captured, то выполняется запуск процедуры capture

    4.1.1. Создание события `payment_capture_started`([InvoicePaymentCaptureStarted](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L481))

    4.1.2. Создание нового Target `captured` + [InvoicePaymentCaptured](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L314)) 
    и на основе этого Target создается событие `session_ev`

    4.2. В противном случае запускается новая сессия

    4.2.1. Создание нового Target `session_started` (`invoice_payment_session_change`)

    4.2.2. Создание события `session_ev` для полученного `Target` 
    и сессии из пункта 4.2.1.

5. Установка таймаута для машины в 0

6. Завершение шага `flow_waiting` (возврат сгенерированных событий и метаданных для 
   машины MG)