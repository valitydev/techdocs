# Работа с платежами. Реализация

## Немного о платеже

Платеж - это перевод денежных средств со счета одного участника 
товарно-денежных отношений на счет другого. Способ проведения платежа
(при помощи карты, банковского перевода, qr-кода и т.п.) не имеет значения.

В процессинге Vality платеж условно можно разделить на 2 части: `invoice` и `payment`.
`Invoice` выступает в роли корзины и может содеражть в себе несколько платежей 
объединенных общими данными о клиенте, деталях платежа, различных дополнительных условиях.
`Payment` в свою очередь минимально делимая единица товарно-денежных отношений в системе 
и хранит в себе информацию о сумме и валюте платежа, данные о плательщике, идентификатор платежа 
и прочая метаинформация. В дальнейшем говоря о платеже будет иметься в виду связка
`invoice + payment`.

## Алгоритм проведения платежа

Работа с платежами является основной задачей `HellGate`. Он должен обеспечивать как высокую скорость работы, 
так и надежность выполнения. Стандартный подход к проведению платежа выглядит следующим образом:
1. Инициируется платеж. Он может быть начат как на checkout странице разработанной vality.dev, так и через API 
(API прописано в [swag-payments](https://github.com/valitydev/swag-payments))
2. После этого платеж в зависимости от необходимости работы с карточными данными попадает либо в 
[CAPI](https://github.com/valitydev/capi-v2), либо в [CAPI-PCIDSS](https://github.com/valitydev/capi-pcidss-v2)). 
Сервис выполняет роль едтиной точки входа через API (маппит данные и использует определенный исполнитель). 
В случае платежа с использованием [интерфейса, описанного в damsel](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1040), 
`CAPI` вызывает `HellGate` и платеж начинает обрабатываться.
3. `Hellgate` обогащает входные данные дополнительной информацией, проводит проверки и обрабатывает платеж. 
4. Страница, инициирующая платеж, получает данные о статусе платежа

Краткая иллюстрация алгоритма проведения платежа представлена на рисунке ниже
![](images/abstract-payment-flow.png)

Самым важным в данной схеме является этап обработки в `HG`, который далее и будет рассмотрен.


## Абстрактный алгоритм прохождения платежа в HG

Последовательность действий после получения данных платежа от `CAPI` следующая:
1. Старт платежа в `HG`. Сначала внешняя система при помощи API описанного в damsel
   [создает инвойс](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1042).
   В него передается следующая структура:
```plantuml
struct InvoiceParams {
    1: required PartyID party_id
    2: required ShopID shop_id
    3: required domain.InvoiceDetails details
    4: required base.Timestamp due
    5: required domain.Cash cost
    6: required domain.InvoiceContext context
    7: required domain.InvoiceID id
    8: optional string external_id
    9: optional domain.InvoiceClientInfo client_info
    10: optional domain.AllocationPrototype allocation
}
```
Затем [создается платеж](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1134).
В метод `StartPayment` передается ID ранее созданного инвойса и следующая структура:
```plantuml
struct InvoicePaymentParams {
    1: required PayerParams payer
    8: optional domain.PayerSessionInfo payer_session_info
    2: required InvoicePaymentParamsFlow flow
    3: optional bool make_recurrent
    4: optional domain.InvoicePaymentID id
    5: optional string external_id
    6: optional domain.InvoicePaymentContext context
    7: optional base.Timestamp processing_deadline
}
```
2. Получив входный данные `Hellgate` преобразует их и [создает новую машину](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L416) 
в сервисе `machinegun` (интерфейс создания - [machinegun_proto.state_processing.Automation.Start](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L416)).
Структура [машины](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L82) выглядит следующим образом:
```plantuml
/**
 * Машина — конечный автомат, обрабатываемый State Processor'ом.
 */
struct Machine {
    /** Пространство имён, в котором работает машина */
    1: required base.Namespace ns;

    /** Основной идентификатор машины */
    2: required base.ID  id;

    /**
     * Сложное состояние, выраженное в виде упорядоченного набора событий
     * процессора.
     * Список событий упорядочен по моменту фиксирования его в
     * системе: в начале списка располагаются события, произошедшие
     * раньше тех, которые располагаются в конце.
     */
    3: required History history;

    /**
     * Диапазон с которым была запрошена история машины.
     */
    4: required HistoryRange history_range;

    /**
     * Упрощенный статус машины
     */
    8: optional MachineStatus status;

    /**
     * Вспомогательное состояние — это некоторый набор данных, характеризующий состояние,
     * и в отличие от событий не сохраняется в историю, а каждый раз перезаписывается.
     * Бывает полезен, чтобы сохранить данные между запросами, не добавляя их в историю.
     */
    7: optional AuxState aux_state;

    /**
     * Текущий активный таймер (точнее, дата и время когда таймер сработает).
     */
    6: optional base.Timestamp timer;

    // deallocated / reserved
    // 5: optional AuxStateLegacy aux_state_legacy

}
```

3. Далее `HG` дозапрашивает метаинформацию из сервиса `dominant` ([интерфейс работы с dominant](https://github.com/valitydev/damsel/blob/master/proto/domain_config.thrift#L171)) (todo: какую?)
4. Получение дополнительной информации о пати-шопу из сервиса `party-management` ([интерфейс работы с party-management](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2532)) (по необходимости)
5. Проверка платежа в антифрод системе ([интерфейс работы с антифродом](https://github.com/valitydev/damsel/blob/master/proto/proxy_inspector.thrift#L54))
6. [Роутинг](routing-workflow.md). Один из важнейших этапов при проведении платежа.
Здесь определяется через какого провайдера и какой терминал будет осуществлен платеж. 
Выбор зависит от многих параметров, но основные это доступность провайдера, лимиты, результат проверки антифродом.
7. После того как провайдер, через которого будет проведен платеж, был определен, 
происходит холдирование денежных средств в сервисе `shumway`
([интерфейс для работы с shumway](https://github.com/valitydev/damsel/blob/master/proto/accounter.thrift#L120))
8. После этапов описанных выше `HG` формирует [PaymentContext](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L265)
и с использованием данных полученных после роутинга взаимодействует с [адаптером к провайдеру](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L341)
9. Адаптер реализует базнес логику по взаимодействию с конкретным провайдером. Первый этап для любого платежа
PROCESSED. В зависимости от внутренней логики адаптера вернуться в HG может несколько варианов: Sleep, Suspend, Finish.
Финализирует этап возврат Finish состояния (может быть Success и Failed)
10. Если получен Failed состояние, то платеж завершается (машина переводится в состояние Failed), 
если Success, то переходим к следующему этапу.
11. Дальнейшие действия зависят от того какие настройки были заданы для провайдера.
Если это одностадийный платеж, то HG мгновенно переходит к этапу CAPTURE.
Если двухстайдийный, то HG ожидает от мерчанта (через связку линый кабинет ->
API -> HG) перевода платежа в финальный статус (CAPTURED или CANCELLED). 
CAPTURED/CANCELLED так же обрабатываются в адаптере и при получении Finish 
состояния платеж можно считать оконченным.

Примерный алгоритм работы `HG` с платежом представлен на схеме ниже
![](images/abstract-hg-payment-processing.png)

## Детальный алгоритм проведения платежа в HG

1. Создание нового инвойса ([Invoicing.Create](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1042))

    1.1. Получение дополнительных данных и проверок для создания инвойса:

    1.1.1. Получение последней версии `DomainRevision` (`dmt_client:get_last_version()`)

    1.1.2. Добавление [InvoiceID](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L522) в структуру `Meta`(`#{key() => value()}`)

    1.1.3. По `PartyID` получается актуальная ревизия для пати ([PartyManagement.GetRevision](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2535)),
    а затем выполняется [PartyManagement.Checkout](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2538) и получаются
    данные по [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766);

    1.1.4. По полученной структуре [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766) проверяеется 
    существование магазина по `ShopID` и если он есть, то получаются данные по [Shop](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L798)

    1.1.5. Происходит проверка, что `Party` и `Shop` не заблокированы и активны

    1.1.6. Получение условий обслуживания для мерчанта `MerchantTerms` ([PartyManagement.ComputeContractTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2580))

    1.1.7. Проверка параметров инвойса (сумма присутствует и больше нуля, поле валюты 
    присутствует и соответствует валюте магазина (`Shop`), лимиты для магазина не были 
    достигнуты)

    1.1.8. Получение данных по [аллокациям](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L525)
    и проверка необходимости выполнения платежа по разным магазинам (TODO: на данный момент не тестировалось и будет расписано КТТС)

    1.2. Старт новой машины в `MG` (`ensure_started`) 

    1.2.1. Из полученных ранее данных создается новый объект [Invoice](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L134)
    (дополнительно задается `status = unpaid`, `created_at = now()`)

    1.2.2. Выполняется запуск новой машины ([Automaton.Start](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L416))

    1.3. Получение состояния созданной машины (`get_invoice_state`)

    1.3.1. Получение данных о машине из MG ([Automaton.GetMachine](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L448))

    1.3.2. "Свертывание" истории (`collapse_history`). Для списка событий производится
    операция [merge](meta/invoice-merge-change.md), чтобы получить актуальное состояние.
    В данном случае будет обработано состояние `invoice_created`

    1.3.3. Из полученного ранее состояния машины получается состояние [инвойса](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L612) (`get_invoice_state`)

    1.4. Полученное состояние [инвойса](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L612) возвращается вызываемому сервису

2. Создание нового платежа (этап `new`) [Invoicing.StartPayment](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1134)

    2.0. Восстановление локального контекста платежа `St` (из данных ранее созданного инвойса)
    
    2.1. Получение дополнительных данных и проверока целостности данных для создания инвойса

    2.1.1. По `PartyID` из локального контекста платежа `St` получается актуальная ревизия для пати ([PartyManagement.GetRevision](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2535)),
    а затем выполняется [PartyManagement.Checkout](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2538) и получаются
    данные по [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766);
 
    2.1.2. Проверка, что по `Party`/`Shop` можно проводить операции (`operable`) (`assert_invoice`)

    2.1.3. Проверка финализированности всех корректировок (`adjustment`) (`assert_all_adjustments_finalised`)

    2.2. Старт обработки данных платежа (`start_payment`)

    2.2.1. Получение `PaymentID` (получение из контекста `St` списка платежей, далее берется размер
    массива и увеличивается на 1)

    2.2.2. Проверка состояния инвойса (status = unpaid)

    2.2.3. Проверка состояния инвойса (не должно находится каких-либо других платежей
    в статусе pending)

    2.2.4. `Opts = #{timestamp := OccurredAt} = get_payment_opts(St),` (TODO: уточнить у erlangteam)

    2.2.5. Инициализация объекта платежа [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293)
    
    2.2.5.1. Из PaymentParams (InvoicePaymentParams) достается payer, flow, payer_session_info, make_recurrent, context, 
    external_id, processing_deadline

    2.2.5.2. получается последняя Revision из данных клиенте доминанты

    2.2.5.3. из объекта `Opts` (тоже часть контекста платежа) достается информация (объекты)
      Party, Shop, Invoice

    2.2.5.4. Получение условий обслуживания мерчанта [MerchantTerms](meta/get-merchant-terms.md) и формирование 
    из него [TermSet](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1163), где
    `payments = PaymentTerms`, `recurrent_paytools = RecurrentTerms`
    
    2.2.5.5. из поля Payer достается PaymentTool
    
    2.2.5.6. проверка вхождения текущего платежного метода в список разрешенных для мерчанта
    
    2.2.5.7. проверка суммы платежа на вхождение в лимит для мерчанта
    
    2.2.5.8. [создание payment_flow](meta/create-payment-flow.md) в зависимости от того это instant или hold операция
    
    2.2.5.9. поиск родительского платежа и [валидация с учетом возможного рекуррента](meta/validate-recurrent-intention.md)
    
    2.2.5.10. Создание объекта [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293)
    , где status = pending, registration_origin = merchant
    
    2.2.5.11. создание события `payment_started` (`payment_started(Payment)`)
    
    2.2.5.12. слияние изменений (`merge_change`); так как платеж только был создан, то он
    попадает на этап new. Сначала происходит проверка корректности перехода на данный
    этап для платежа (`validate_transition`). Если метаданные платежа корректны, то 
    происходит заполнение текущего состояния `St` метаинформацией:
    - `target` - текущий глобальный этап выполнения платежа (устанавливается в processed)
    - `payment` - данные о платежа (присваивается сформированный ранее объект Payment)
    - `activity` - следующий шаг выполнения (устанавливается `{payment, risk_scoring}`, 
    то есть следующий этап будет подсчет риска)
    - `timings` - установка таймингов `hg_timings:mark(started, define_event_timestamp(Opts))` TODO: расшифровать у erlangteam

    2.2.5.13. возврат параметров
    - `PaymentSession` - результат слияния изменений (`merge_change`)
    - `Changes` - объект Events (событие `payment_started` из пункта 2.2.5.11)
    - `Action` - желаемое действие, продукт перехода в новое состояние (`hg_machine_action:instant()`)
    
    2.2.6. Формирование ответа (мапа ключ-значение):
    - `response` - полученный из PaymentSession объект [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L618)
    - `changes` - созданный на основании параметров `PaymentID`, `Changes`, `OccurredAt` объект [InvoicePaymentChange](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L118)
    - `action` - желаемое действие, продукт перехода в новое состояние (объект `Action` из предыдущего пункта)
    - `state` - объект `St`

    2.3. Сохранение данных в `MG`

3. Обработка этапа [risk_scoring](meta/risc-scoring-workflow.md) платежа 

4. Обработка этапа [routing](meta/routing-workflow.md) платежа

5. Обработка этапа [cash_flow_building](meta/cash-flow-building.md) платежа

6. Обработка этапа [processing_session](meta/process-session.md) платежа. 
   Данный этап может исполняться несколько раз до момента, когда:
   - сессия завершилась успешно - статус сессии равен `finished`, а результат 
   `session_succeeded`;
   - получено событие `payment_rollback_started` (будет переход на этап 
   `processing_failure`) 

7. Обработка этапа [processing_accounter](meta/), а так же генерация 
   нового события payment_status_changed

8. Обработка этапа [flow_waiting](meta/) платежа

9. Обработка этапа [processing_capture](meta/) платежа

10. Обработка этапа [updating_accounter](meta/) платежа

11. Обработка этапа [finalizing_session](meta/) платежа (данный этап может исполняться несколько раз)

12. Обработка этапа [finalizing_accounter](meta/) платежа














