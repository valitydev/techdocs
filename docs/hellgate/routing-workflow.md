# Роутинг. Как это работает?

## Назначение

Роутинг нужен для определения подходящего провайдера и терминала для 
проведения платежа. Неполный список параметров, участвующих в рассчетах:
доступность провайдера, лимиты, валюта, условия по трафику и т.п.

Данный модуль помогает повысить конверсию платежей, что положительно сказывается на балансе компании.

## Реализация в HG (process_routing)

1. Получение входных данных о платеже и установка локальных переменных.

    1.1. `Opts` - опциональные данные платежа (options)

    1.2. `Revision` - актуальня [ревизия](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L299)

    1.3. `Payment` - контекст платежа

    1.4. `PaymentTool` (`VS1`) - берется из (`dmsl_domain_thrift:'PaymentTool'`, `#{payment_tool := PaymentTool} = VS1 = get_varset(St, #{risk_score => get_risk_score(St)})`)

    1.5. `risk_score` (`VS1`) - получение рассчитанного ранее [уровня риска](risc_scoring_workflow.md)

    1.6. `CreatedAt` - дата создания платежа

    1.7. `PaymentInstitutionRef` - достается из `Opts` (структура описана в [damsel.domain](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1032))

2. Получение условий обслуживания мерчанта `MerchantTerms`

    2.1. Из данных о магазине (`Shop`) достается `ContractID`

    2.2. Из списка [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766) 
    по полученному ранее `ContractID` достается `Contract`

    2.3. Проверка на то активен ли контракт
   
    2.4. Получение условий контракта [PartyManagement.ComputeContractTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2580) (`TermSet.payments`)

3. Получение из `MerchantTerms` условий по возвратам (`refund`) для мерчанта (`collect_refund_varset`)

    3.1. Получение списка платежных методов из [PaymentsServiceTerms.refunds](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1198)

    3.2. Если в полученном `PaymentsServiceTerms.refunds` есть платежный метод платежа
    `PaymentTool`, то формируется объект с лимитами по возвратам для мерчанта
 
4. Получение из `MerchantTerms` условий по чарджбэкам (`chargeback`) для мерчанта (`collect_chargeback_varset`)

    4.1. реализации нет

5. Получение `PaymentInstitution` ([PartyManagement.ComputePaymentInstitution](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2766))

6. Из объекта `St()` достается `Payer` ([InvoicePayment.Payer](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L301))

7. Проверка на присутствие ранее определенных путей (актуально для рекуррентов). 
   Если такая информация есть, то она и берется для проведения платежа, иначе 
   алгоритм идет дальше

8. Определение пути проведения платежа (`gather_routes`).

    8.1. Задание базовых переменных:

    8.1.1. `Payment`, `PartyID`, `Payer`, `PaymentTool` - аналогично ранее заданным

    8.1.2. `ClientIP` - достается из `Payer`

    8.1.3. `Currency` - достается из `Payment`

    8.1.3. `Predestination` - из `Payment` достается информация о предыдущем платеже (`choose_routing_predestination`)

    8.2. Из ранее полученного [PaymentInstitution](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2776)
    достается: 
    - [RoutingRules](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2800)
    - [Policies](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2801) 
    - [Prohibitions](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2802)

    8.3. Получение списка кандидатов

    8.3.1. Получение списка кандидатов ([PartyManagement.ComputeRoutingRuleset](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2749))

    8.3.2. Если в полученном [RoutingRuleset](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2807)
    отсутствуют [candidates](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2815)
    , то выбрасывается ошибка `misconfiguration`
    
    8.3.3. Валидация кандидатов (пустой ли список кандидатов и т.п.)

9. Получение всех возможных вариантов роутинга из списка кандидатов (`collect_routes`)
    
    9.1. Получение данных терминала `hg_domain:get` // TODO: уточнить

    9.2. Получение особенностей данного роута из объекта [RoutingPin](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2831)
    (сет из значений: `currency`, `payment_tool`, `party_id`, `client_ip`)

    9.3. Проверка на применимость терминала ([PartyManagement.ComputeProviderTerminalTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2710))

    9.4 Результат вызова функции `ComputeProviderTerminalTerms` [ProvisionTermSet](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2386)
    проверяется на предмет ошибки и если она была, то выбрасывается исключение `rejected`
    иначе происходит проверка применимости условий полученных от `PartyManagement` и 
    контекста текущего платежа (acceptable_payment_terms):
    - можно ли использовать полученный TermSet
    - тестовая проверка условий для `currency`, `category`, `payment_tool`, `cost`.
      (Например: `try_accept_term(ParentName, currency, getv(currency, VS), CurrenciesSelector)` 
      и далее `test_term(currency, V, Vs) -> ordsets:is_element(V, Vs);`)
    - проверка допустимых условий удержания ([PaymentHoldsProvisionTerms](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2416)). 
      В рамках данной проверки сравнивается срок необходимого холдирования для
      платежа и дозволенного в рамках условий работы с провайдером
    - проверка допустимых условий возврата (разрешены ли возвраты, разрешены ли 
      частичные возвраты, лимит на возвраты)
    - допустимый риск (сравнивается вычисленный ранее `RiscScore` с `RiskCoverage` 
      провайдера и если `RiscScore` превышает допустимый уровень `RiskCoverage` провайдер/терминал 
      отклоняется)

    9.5. Если все проверки прошли успешно, то такой путь добавляется в список 
    возможных. В противном случае либо обрабатывается исключение `rejected`, либо 
    ошибка `misconfiguration`

10. Получение списка запретов (`get_table_prohibitions`). 

    10.1. На основовии полученных ранее `Prohibitions` получается список 
    правил [PartyManagement.ComputeRoutingRuleset](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2749)

    10.2. Получение списка терминалов на запрет платежа

    10.3. Проверка структуры `RoutingRuleset` на наличие поля `Candidates` (иначе будет выброшена ошибка конфигурации)
    и валидируется правильность заполнения данных кандидата.

11. Фильтрация полученных вариантов роутинга (`filter_routes`). 
    Среди списка разрешенных провайдеров и их терминалов и запрещенных 
    происходит поиск наиболее подходящего дял проведения платежа.
    Возвращается разрешенный, а так же отклоненные пути. Если не было найдено ни 1 пути
    для проведения платежа, то ошбика залогируется как `no_route_found`. Если пути для
    проведения платежа найдены, но есть и отклоненные, то отклоненные так же будут залогированы
    как `rejected_route_found`. В случае `misconfiguration` выбросится ошибка.

```erlang
filter_routes({Routes, Rejected}, Prohibitions) ->
    lists:foldr(
        fun(Route, {AccIn, RejectedIn}) ->
            TRef = terminal_ref(Route),
            case maps:find(TRef, Prohibitions) of
                error ->
                    {[Route | AccIn], RejectedIn};
                {ok, Description} ->
                    PRef = provider_ref(Route),
                    RejectedOut = [{PRef, TRef, {'RoutingRule', Description}} | RejectedIn],
                    {AccIn, RejectedOut}
            end
        end,
        {[], Rejected},
        Routes
    ).

-spec provider_ref(route()) -> provider_ref().
provider_ref(#route{provider_ref = Ref}) ->
  Ref.

-spec terminal_ref(route()) -> terminal_ref().
terminal_ref(#route{terminal_ref = Ref}) ->
  Ref.

-record(route, {
  provider_ref :: dmsl_domain_thrift:'ProviderRef'(),
  terminal_ref :: dmsl_domain_thrift:'TerminalRef'(),
  weight :: integer(),
  priority :: integer(),
  pin :: pin()
}).
```

12. Фильтрация полученного списка провайдеров по лимитам (`filter_limit_overflow_routes`). 
    Для каждого полученного ранее пути (связки провайдера и его терминала) выполняется следующая 
    последовательность действий, которые в конечном итоге образуют корректный 
    с точки зрения лимитов по терминалам список путей для проведения платежа
    
    12.1. Фиксация лимитов для провайдеров (холдирование). (`hold_limit_routes`)
    
    12.1.1. Формируется [route record](meta/route-record.md)(providerRef, terminalRef)

    12.1.2. Получаются условия для провайдера и терминала из party-management 
    ([PartyManagement.ComputeProviderTerminalTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2710))

    12.1.3. По полученным ProviderTerms получаются лимиты оборота из 
    [селектора TurnoverLimitSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2403)

    12.1.4. Холдирование [Limiter.hold](https://github.com/valitydev/limiter-proto/blob/master/proto/limiter.thrift#L66) 

    12.2. Получение списка терминалов без переполнения лимита (`get_limit_overflow_routes`)

    12.2.1. Формируется пара [route record](meta/route-record.md)(providerRef, terminalRef)

    12.2.2. Получаются условия для провайдера и терминала из party-management 
    ([PartyManagement.ComputeProviderTerminalTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2710))

    12.2.3. По полученным ProviderTerms получаются лимиты оборота из 
    [селектора TurnoverLimitSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2403)

    12.2.4. Проверка лимитов

    12.2.4.1. Получение(создание) контекста платежа

    12.2.4.2. Если лимита не был установлен, то считается, что проведение платежа по 
    такому терминалу возможно. В противном случае из объекта TurnoverLimitSelector
    достается `TurnoverLimitID` и при помощи него происходит вызов [Limiter.Get](https://github.com/valitydev/limiter-proto/blob/master/proto/limiter.thrift#L61)/
    Если лимит еще не достигнут, то такой терминал считается корректным. Иначе пишется
    ошибка `limit_overflow`. ВАЖНО: TurnoverLimit в структуре TurnoverLimitSelector 
    является объектом типа Set, который может собирать в себе несколько значений и проверить их нужно все

    12.3. Возврат подходящего списка путей

13. Обработка найденных результатов выполнения (`handle_gathered_route_result`).

    13.1. Выбор конкретного пути (`choose_route`)

    13.1.1. Сбор показателей отказа (`gather_fail_rates` & `score_routes_with_fault_detector`)

    13.1.1.1. Сформировать список ID провайдеров для поиска

    13.1.1.2. Выполняется поиск в сервисе `fault-detector` ([FaultDetector.GetStatistics](https://github.com/valitydev/fault-detector-proto/blob/master/proto/fault_detector.thrift#L68))

    13.1.1.3. Для каждого провайдера из найденных определяется:
    - доступность и конверсия провайдера
    - доступность и конверсия статуса

    13.1.2. Выбор конкретного пути (`choose_rated_route`)

    13.1.2.1. Балансировка маршрутов (`balance_routes`)

    13.1.2.1.1. Фильтрация по приоритету (`group_routes_by_priority`)

    13.1.2.1.1.1. Получение приоритета для терминала

    13.1.2.1.1.2. Получение всех терминалов с заданным приоритетом

    13.1.2.1.1.3. Сортировка полученного массива

    13.1.2.1.2. Балансировка полученного в результате фильтрации по приоритету 
    массива (`balance_route_groups`)

    13.1.2.1.2.1. Установка случайного состояния (`set_routes_random_condition`). 
    Сначала подсчитывается суммарный вес всех терминалов. Затем он умножается на 
    случайное число и получается некоторое random значение. 

    13.1.2.1.2.2. Для каждого элемента из списка путей 
    [рассчитывается случайное значение веса](meta/calc_random_condition.md) (`calc_random_condition`)

    13.1.2.2. Подсчет условных баллов для полученных в результате балансировки путей (терминалов) (`score_route`)

    13.1.2.2.1. Из объекта [Route](meta/route-record.md) достается приоритет, вес и [pin](meta/pin.md) терминала

    13.1.2.2.2. Создается объект [route_scores](meta/route_scores.md) куда записываются:
    - `availability_condition` - записывается состояние пути по показателю доступности 
    (`dead`/`alive` в зависимости от `fail_rate`) 
    - `conversion_condition` - записывается состояние пути по показателю конверсии
      (`dead`/`alive` в зависимости от `fail_rate`)
    - `priority_rating` - приоритет, полученный из [Route](meta/route-record.md)
    - `pin` - записывается хэш для объекта `pin`
    - `random_condition` - вес, полученный из [Route](meta/route-record.md)
    - `availability` - числовой показатель доступности (`fail_rate`)
    - `conversion` - числовой показатель конверсии (`fail_rate`)

    13.1.2.3. Нахождение лучшего пути (по полученным ранее `route_scores`) (`find_best_routes`)

    13.1.2.3.1. По списку ScoredRoutes:

    13.1.2.3.1.1. Задаются стартовые `IdealRoute` и `ChosenRoute`

    13.1.2.3.1.2. Текущий элемент сравнивается с `IdealRoute` через функцию [select_better_route_ideal](meta/select_better_route_ideal.md).
    Значение, которое возвращает эта функция, становится новым `IdealRoute`

    13.1.2.3.1.3. Текущий элемент сравнивается с `ChosenRoute` через функцию [select_better_route](meta/select_better_route.md).
    Значение, которое возвращает эта функция, становится новым `ChosenRoute`

    13.1.2.3.2. После прохода по всему массиву возвращается пара `{ChosenScoredRoute, IdealRoute}`

    13.1.2.4. Формирование контекста для выбора (`get_route_choice_context`).
    Формируется объект RouteChoiceContext, куда записываются поля:
    - `chosen_route` - `ChosenRoute`
    - `preferable_route` - `IdealRoute`
    - `reject_reason` - заполняется при помощи функции [map_route_switch_reason](meta/map_route_switch_reason.md)

    13.1.2.5. RouteChoiceContext возвращается выше по контексту

    13.1.3.  RouteChoiceContext возвращается выше по контексту

    13.2. Логирование выбора и смена статуса на `route_changed`

    13.2. `ChoosenRoute` используется в качестве финального выбора роута. 
    Если роут не был найден выбрасывается ошибка
    
    ```erlang
        Failure = {failure,
            payproc_errors:construct(
                'PaymentFailure',
                {no_route_found, {forbidden, #payproc_error_GeneralFailure{}}}
            )},
    ```



