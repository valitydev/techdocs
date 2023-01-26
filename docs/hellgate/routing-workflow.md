# Роутинг. Как это работает?

## Назначение

Роутинг нужен для определения подходящего провайдера и терминала для 
проведения платежа. Неполный список параметров, участвующих в рассчетах:
доступность провайдера, лимиты, валюта, условия по трафику и т.п.

Данный модуль помогает повысить конверсию платежей, что положительно сказывается на балансе компании.

## Реализация в HG

1. Получение входных данных о платеже и установка локальных переменных.
- `Revision`, `CreatedAt`, `Payment` - берутся из контекста
- `PaymentTool` берется из (`dmsl_domain_thrift:'PaymentTool'`, `#{payment_tool := PaymentTool} = VS1 = get_varset(St, #{risk_score => get_risk_score(St)})`)
- `PaymentInstitutionRef` - берется из Opts

2. a) `MerchantTerms` - договоренности обслуживания с мерчантом. Информация по данному 
объекту получается следующим образом. Из контекста инвойса достаются данные по 
`Party` и `Shop`. Из объекта `Shop` достается `ContractID` и из сервиса
`party-management` достается информация по контракту. 
   
   b) Проверка на то активен ли контракт
   
   c) Преобразование условий контракта (`ContractTerms`) в новый датасет c полями
   (amount, shop_id, payout_method, payment_tool, wallet_id, bin_data)
   
   d) Получение клиента пати и его контекста
```erlang
get_party_client() ->
    HgContext = hg_context:load(),
    Client = hg_context:get_party_client(HgContext),
    Context = hg_context:get_party_client_context(HgContext),
    {Client, Context}.
```
---

   e) рассчет условий контракта `PartyManagement.ComputeContractTerms`. 
   
   f) из исходного `MerchantTerms` берутся условия по возвратам и чарджбэкам 
   
3. Из options?(`Opts`) достается `Contract`, а из него достается `PaymentInstitutionRef` 
4. По ранее полученному `PaymentInstitutionRef` из `party-management` достается
   `PaymentInstitution`
5. Из объекта `St()` достается `Payer` (`InvoicePayment.Payer`)
6. Проверка уже объявленных "путей" для плательщика и если такой есть, то из этих
   данных задается новая пара `ProviderRef` и `TerminalRef` и алгоритм переходит 
   к пункту ХХХ. В противном случае далее идет пункт 7.
7. Определение пути. В первую очередь задаются базовые переменные: 
   `Payment`, `PartyID`, `Payer`, `PaymentTool`, `ClientIP`, `Currency`. 
   Особое место занимает переменная `Predestination`, которая отображает 
   в себе роутинг для ранее проведенного рекуррентного платежа.
8. из domain модели вычитываются правила роутинга: политики (`Policies`) 
   и запреты (`Prohibitions`)