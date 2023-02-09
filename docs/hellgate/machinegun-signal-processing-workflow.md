## Обработка сигнала от MG 
#### (`hg_invoice_payment`.`-spec process_signal(hg_machine:signal(), hg_machine:machine()) -> hg_machine:result().`)

`HG` получает сигнал от `MG` и начинает его обработку (`process_signal`):

1. Из полученных данных заполняется метаинформация по процессу платежа (`collapse_history`):
    - [St](meta/st.md)

2. Из объекта [St](meta/st.md) получается `PaymentID`

3. На основании `PaymentID` из мапы [St](meta/st.md) достается `PaymentSession` (`get_payment_session`)

4. Из `PaymentSession` получается `Revision`(`party_revision`) и `Timestamp`(`created_at`)

5. На соновании `Revision`, `Timestamp` и [St](meta/st.md) формируется объект [Opts](meta/opts.md), где
   Party результат вызова [PartyManagement.Checkout](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2538)

6. Процессинг сигнала (`process_invoice_payment_signal`). Из PaymentSession получается [Registration Origin](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L309)
   и анализируется его значение

   6.1. Если оно не определено или платеж совершен мерчантом ([InvoicePaymentMerchantRegistration](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L328)),
   то вызывается "Invoice payment submachine" (`hg_invoice_payment.process_signal`)

   6.1.1. Для платежа добавляется скоуп по данным `Payment` и метаданным [St](meta/st.md)

   6.1.2. В зависимости от входных данных выполняется процедура `process_timeout`,
   которая запускает обработку конкретного шага (например, `process_risk_score`)

   6.2. Если платеж совершен провайдером ([InvoicePaymentProviderRegistration](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L330)),  
   то вызывется "Invoice registered payment submachine"

   6.2.1. Для платежа добавляется скоуп по данным `Payment` и метаданным [St](meta/st.md)

   6.2.2. В зависимости от входных данных выполняется процедура `process_timeout`,
   которая запускает обработку конкретного шага (например, `processing_capture`)

7. Обработка результата (`handle_payment_result`)

   7.1. Получение из объекта [Opts](meta/opts.md) `OccurredAt`(`timestamp`)

   7.2. Создание структуры с полями (`wrap_payment_changes(PaymentID, Changes, OccurredAt)`):
    - `changes` - `InvoicePaymentChange(PaymentID, Changes, OccurredAt)`
    - `action` - `Action`
    - `state` - данные объекта [St](meta/st.md)

   7.3. Возвращение созданной структуры

8. Отправка ответа с данными (обновленной машины в MG) (TODO: этот момент уточнить)
