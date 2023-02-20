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
3. Затем [создается платеж](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1134).
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
4. Проверка данных платежа в системе антифрода
5. Определение терминала для проведения платежа ([Роутинг](step/routing-workflow.md))
6. После того как провайдер, через которого будет проведен платеж, был определен,
   происходит холдирование денежных средств в сервисе `shumway`
   ([интерфейс для работы с shumway](https://github.com/valitydev/damsel/blob/master/proto/accounter.thrift#L120))
7. После этапов описанных выше `HG` формирует [PaymentContext](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L265)
и с использованием данных полученных после роутинга взаимодействует с [адаптером к провайдеру](https://github.com/valitydev/damsel/blob/master/proto/proxy_provider.thrift#L341)
8. Адаптер реализует базнес логику по взаимодействию с конкретным провайдером. Первый этап для любого платежа
PROCESSED. В зависимости от внутренней логики адаптера вернуться в HG может несколько варианов: Sleep, Suspend, Finish.
Финализирует этап возврат Finish состояния (может быть Success и Failed)
9. Если получен Failed состояние, то платеж завершается (машина переводится в состояние Failed), 
если Success, то переходим к следующему этапу.
10. Дальнейшие действия зависят от того какие настройки были заданы для провайдера.
Если это одностадийный платеж, то HG мгновенно переходит к этапу CAPTURE.
Если двухстайдийный, то HG ожидает от мерчанта (через связку линый кабинет ->
API -> HG) перевода платежа в финальный статус (CAPTURED или CANCELLED). 
CAPTURED/CANCELLED так же обрабатываются в адаптере и при получении Finish 
состояния платеж можно считать оконченным.

Примерный алгоритм работы `HG` с платежом представлен на схеме ниже
![](images/abstract-hg-payment-processing.png)

---

Далее:
- [подробный алгоритм проведения платежа в Hellgate](hg-payment-workflow.md)