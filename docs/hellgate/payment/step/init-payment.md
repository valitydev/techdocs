## Инициализация данных для проведения платежа

1. Получение дополнительных данных и проверок для создания инвойса:

    1.1. Получение последней версии `DomainRevision` (`dmt_client:get_last_version()`)

    1.2. Добавление [InvoiceID](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L522) в структуру `Meta`(`#{key() => value()}`)

    1.3. По `PartyID` получается актуальная ревизия для пати ([PartyManagement.GetRevision](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2535)),
    а затем выполняется [PartyManagement.Checkout](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2538) и получаются
    данные по [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766);

    1.4. По полученной структуре [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766) проверяеется 
    существование магазина по `ShopID` и если он есть, то получаются данные по [Shop](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L798)

    1.5. Происходит проверка, что `Party` и `Shop` не заблокированы и активны

    1.6. Получение условий обслуживания для мерчанта `MerchantTerms` ([PartyManagement.ComputeContractTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2580))

    1.7. Проверка параметров инвойса (сумма присутствует и больше нуля, поле валюты 
    присутствует и соответствует валюте магазина (`Shop`), лимиты для магазина не были 
    достигнуты)

    1.8. Получение данных по [аллокациям](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L525)
    и проверка необходимости выполнения платежа по разным магазинам (TODO: на данный момент не тестировалось и будет расписано КТТС)

2. Старт новой машины в `MG` (`ensure_started`) 

    2.1. Из полученных ранее данных создается новый объект [Invoice](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L134)
    (дополнительно задается `status = unpaid`, `created_at = now()`)

    2.2. Выполняется запуск новой машины ([Automaton.Start](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L416))

3. Получение состояния созданной машины (`get_invoice_state`)

    3.1. Получение данных о машине из MG ([Automaton.GetMachine](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L448))

    3.2. "Свертывание" истории (`collapse_history`). Для списка событий производится
    операция [merge](meta/invoice-merge-change.md), чтобы получить актуальное состояние.
    В данном случае будет обработано состояние `invoice_created`

    3.3. Из полученного ранее состояния машины получается состояние [инвойса](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L612) (`get_invoice_state`)

4. Полученное состояние [инвойса](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L612) возвращается вызываемому сервису

---

Далее:
- [Обработка шага "new"](new-payment.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)
