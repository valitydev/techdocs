## Обработка шага `new` проведения платежа

0. Восстановление локального контекста платежа [St](../../meta/st.md) (из данных ранее созданного инвойса)
    
1. Получение дополнительных данных и проверока целостности данных для создания инвойса

    1.1. По `PartyID` из локального контекста платежа [St](docs/hellgate/meta/st.md) получается актуальная ревизия для пати 
    ([PartyManagement.GetRevision](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2535)),
    а затем выполняется [PartyManagement.Checkout](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2538) 
    и получаются данные по [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766);
 
    1.2. Проверка, что по `Party`/`Shop` можно проводить операции (`operable`) (`assert_invoice`)

    1.3. Проверка финализированности всех корректировок (`adjustment`) (`assert_all_adjustments_finalised`)

2. Старт обработки данных платежа (`start_payment`)

    2.1. Получение `PaymentID` (получение из контекста [St](docs/hellgate/meta/st.md) списка платежей, далее берется размер
    массива и увеличивается на 1)

    2.2. Проверка состояния инвойса (`status = unpaid`)

    2.3. Проверка состояния инвойса (не должно находится каких-либо других платежей
    в статусе `pending`)

    2.4. Из контекста [St](docs/hellgate/meta/st.md) получается структура [Opts](docs/hellgate/meta/opts.md), а из нее
    время события `OccurredAt`
    (`Opts = #{timestamp := OccurredAt} = get_payment_opts(St),` (TODO: уточнить у erlangteam))

    2.5. Инициализация объекта платежа [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293)
    
    2.5.1. Из PaymentParams ([InvoicePaymentParams](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L557)) 
    достаются: `payer`, `flow`, `payer_session_info`, `make_recurrent`, `context`, `external_id`, `processing_deadline`

    2.5.2. Из клинета доминанты (метаданных) получается последняя ревизия (`Revision`) 

    2.5.3. из объекта [Opts](docs/hellgate/meta/opts.md) (тоже часть контекста платежа) достается информация (объекты)
    `Party`, `Shop`, `Invoice`

    2.5.4. Получение условий обслуживания мерчанта [MerchantTerms](meta/get-merchant-terms.md) и формирование 
    из него [TermSet](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1163), где
    `payments = PaymentTerms`, `recurrent_paytools = RecurrentTerms`
    
    2.5.5. На основании [PayerParams](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L581) 
    и [Shop](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L798) создается объект [Payer](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L445) (далее из него достается `PaymentTool`)
    
    2.5.6. Проверка вхождения текущего платежного метода в список разрешенных для мерчанта
    
    2.5.7. Проверка суммы платежа на вхождение в лимит для мерчанта
    
    2.5.8. [Создание payment_flow](docs/hellgate/meta/create-payment-flow.md) в зависимости от типа операции (`instant` или `hold`)
    
    2.5.9. Поиск родительского платежа и [валидация с учетом возможного рекуррента](docs/hellgate/meta/validate-recurrent-intention.md)
    
    2.5.10. Создание объекта [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293)
    , где `status = pending`, `registration_origin = merchant`
    
    2.5.11. Создание события `payment_started` ([payment_started(Payment)](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L177))
    
    2.5.12. Слияние изменений (`merge_change`); так как платеж только был создан, то он
    попадает на этап `new`. Сначала происходит проверка корректности перехода на данный
    этап для платежа (`validate_transition`). Если метаданные платежа корректны, то 
    происходит заполнение текущего состояния `St` метаинформацией:
    - `target` - текущий глобальный этап выполнения платежа (устанавливается в processed)
    - `payment` - данные о платежа (присваивается сформированный ранее объект Payment)
    - `activity` - следующий шаг выполнения (устанавливается `{payment, risk_scoring}`, 
    то есть следующий этап будет подсчет риска)
    - `timings` - установка таймингов `hg_timings:mark(started, define_event_timestamp(Opts))` TODO: расшифровать у erlangteam

    2.5.13. возврат параметров
    - `PaymentSession` - результат слияния изменений (`merge_change`)
    - `Changes` - объект Events (событие `payment_started` из пункта 2.2.5.11)
    - `Action` - желаемое действие, продукт перехода в новое состояние (`hg_machine_action:instant()`)
    
    2.6. Формирование ответа (мапа ключ-значение):
    - `response` - полученный из PaymentSession объект [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L618)
    - `changes` - созданный на основании параметров `PaymentID`, `Changes`, `OccurredAt` объект [InvoicePaymentChange](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L118)
    - `action` - желаемое действие, продукт перехода в новое состояние (объект `Action` из предыдущего пункта)
    - `state` - объект [St](docs/hellgate/meta/st.md)

3. Сохранение данных в `MG`


---

Далее:
- [Обработка шага "risc_scoring"](risc-scoring-workflow.md)

Назад:
- [Инициализация данных платежа](init-payment.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)
