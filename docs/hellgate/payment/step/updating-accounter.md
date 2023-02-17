## Обработка шага `updating_accounter`

### Реализация (`process_accounter_update`)

1. `HG` получает сигнал от `MG` и [начинает его обработку](../../machinegun/machinegun-signal-processing-workflow.md) (`process_signal`)

2. Получение из контекста [St()](docs/hellgate/meta/st.md) FinalCashflow(partial_cash_flow), CaptureData(capture_data), 
   Opts, Payment. Из [Opts]() достаются данные инвойса

3. Получение из CaptureData([InvoicePaymentCaptureData](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L805))
   полей Reason, Cost, Cart, Allocation

4. Обновление в `Payment`([InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293)) 
   поля `Cost` на полученный из `CaptureData` в `п.3`

5. Создание на основе `payment_id` и `invoice_id` идентификатора плана `PlanId` (`construct_payment_plan_id`)

6. Cоздание событий для обновления плана в [Accounter/Shumway](https://github.com/valitydev/shumway)

    6.1. Отмена первичного CashFlow, созданного на этапе processing

    6.1.1. В объекте `CashFlow`([FinalCashFlowPosting](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2206)) 
    `Destination` и `Source` меняются местами, а `details` оборачивается в `"revert(%s)"`

    6.2. Добавляется объект `FinalCashflow`

7. Выполнение операции [Hold](https://github.com/valitydev/damsel/blob/master/proto/accounter.thrift#L120) 
   для событий из `п.6` в сервисе [Accounter/Shumway](https://github.com/valitydev/shumway)

8. Создание `Target` = `captured` ([InvoicePaymentCaptured](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L314))

9. На основании `Target` из `п.8` создание сессии `session_started` ([SessionStarted](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L252)).
   ПОлученная сессия оборачивается в событие [InvoicePaymentSessionChange](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L234)

11. Возврата списка событий из `п.9`, а так же инструкции для сохранения в `MG` с таймером 0.
    В качестве метаинформации для дальнейшего перехода устанавливается флаг `next`

---

Далее:
- [Обработка шага "finalizing_session"](finalizing-session.md)

Назад:
- [Обработка шага "processing_capture"](processing-capture.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)