# Создание схемы проведения денежной операции

## Немного о алгоритме перемещения денежных средств между счетами

В Cash-Flow отображается перемещение денежных средств между счетами в системе.
Обычно у одного платежа есть несколько получателей. Основная часть уходит мерчанту, 
но определенный процент перечистляется провайдеру, платежной системе и т.п.

## Создание Cash-Flow в HG

1. Получение входных данных о платеже и установка локальных переменных.

   1.1. `Opts` - опциональные данные платежа (options)

   1.2. `Route` - данные выбранного на этапе роутинга терминала и провайдера

   1.3. `Revision` - актуальня [ревизия](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L299)

   1.4. `Invoice` - контекст инвойса (берется из `Opts`)

   1.5. `Payment` - контекст платежа (берется из `St`)

   1.6. `Timestamp` - дата создания платежа

   1.7. `Allocation` - данные аллоцированных платежей

2. Получение условий обслуживания провайдера `ProviderTerms`. Достается из
   [PartyManagement.ComputeProviderTerminalTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2710)

3. Реконструкция платежного флоу (`reconstruct_payment_flow`)

    3.1. Получение из [InvoicePayment](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L293) 
    данных `Flow` и `CreatedAt`

    3.2. Непосредственная реконструкция флоу при помощи функции [reconstruct_payment_flow(Flow, CreatedAt, VS)](../../meta/reconstruct_payment_flow.md)

4. Создание набора для валидации:
   - `party_id` 
   - `shop_id`  
   - `category`  
   - `currency`  
   - `cost` 
   - `payment_tool` - достается из `PaymentResource`

5. Создание `FinalCashflow` (`calculate_cashflow` -> `collect_cashflow`)

    5.1. Получение `PaymentInstitution` ([PartyManagement.ComputePaymentInstitution](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2766))

    5.2. Сборка флоу движения денежных средств (`collect_cashflow`)

    5.2.1. Получение `Amount`, `PaymentInstitution`

    5.2.2. Создание флоу для транзакции (construct_transaction_cashflow)
    
    5.2.2.1. Проверка MerchantPaymentsTerms. 
    Если значение не задано, то вызывается [PartyManagement.ComputeContractTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2580)

    5.2.2.2. Получение [MerchantCashflowSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1196)

    5.2.2.3. Получение `MerchantCashflow`
    ```erlang
        MerchantCashflow = get_selector_value(merchant_payment_fees, MerchantCashflowSelector),
    ```

    5.2.2.4. Получение `AccountMap` (`collect_account_map`)

    5.2.2.4.1. Сбор данных о счетах мерчанта (`collect_merchant_account_map`)

    5.2.2.4.1.1. Сбор данных движения денежных средств для мерчанта (`PartyID`, `ShopID`). 
    
    5.2.2.4.1.2. Из объекта [Shop](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L806) 
    достаются данные по [аккаунту мерчанта](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L806)

    5.2.2.4.1.3. Создается итоговый объект с данными settlement и guarantee из [ShopAccount](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L806)

    5.2.2.4.2. Сбор данных о счетах провайдера (`collect_provider_account_map`)

    5.2.2.4.2.1. Получение данных о счетах провайдера из объекта [Provider](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2340)

    5.2.2.4.2.2. Создание объекта с данными о провайдере (берется ранее полученный Route) и его [settlement](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2473)

    5.2.2.4.3. Сбор данных о счетах системы (`collect_system_account_map`)

    5.2.2.4.3.1. Получение данных о [счетах системы](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2714)

    5.2.2.4.3.2. Создание объекта с данными о счетах системы [settlement и subagent](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2720)

    5.2.2.4.4. Сбор данных о внешних счетах (`collect_external_account_map`)

    5.2.2.4.4.1. Получение данных о внешних системах ([PartyManagement.ComputeGlobals](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2739))

    5.2.2.4.4.2. Получение данных [внешних счетов](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2850)

    5.2.2.4.4.3. На основании `Revision` из `ExternalAccountSetSelector` получается `ExternalAccountSet`

    5.2.2.4.4.4. Создание объекта с полями внешнего счета [income & outcome](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2745)

    5.2.2.5. Добавление в контекст `operation_amount => Amount`

    5.2.2.6. Финализация Cashflow (`construct_final_cashflow`)

    5.2.2.6.1. Cоздание [FinalCashFlowAccount](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2213) 
    для `Source` и `Destination`. Так как это инициализирующий флоу, то и значения `AccountMap` для них идентичны.
    Так же [задаются](https://github.com/valitydev/hellgate/blob/edfb7be342e50b4c7cb57bef045924e2cfb71680/apps/hellgate/src/hg_cashflow.erl#L69) `Volume` и `Details`

    5.2.3. Получение [ProviderCashflowSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2398) из `ProvisionTerms`

    5.2.4. Создание `ProviderCashflow` (`construct_provider_cashflow`)

    5.2.4.1. Из [ProviderCashflowSelector](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2398) 
    получается `ProviderCashflow`

    5.2.4.2. Получение контекста для cash flow

    5.2.4.3. Создание `AccountMap`. Аналогично тому как было сделано в п.5.2.2.4. (`collect_account_map`)

    5.2.4.4. Создание итогового CashFlow c данными `ProviderCashflow` и получившейся
   `AccountMap`. 

    5.2.5. Сложение объектов `MerchantCashFlow ++ ProviderCashflow`

6. Откат неиспользуемых платежных лимитов (`rollback_unused_payment_limits`)

7. Холдирование денежных средств в `shumway` ([Accounter.Hold](https://github.com/valitydev/damsel/blob/master/proto/accounter.thrift#L120)).
   Процедура выполняется на основе ID плана, к которому применяется данное 
   изменение (`invoiceID` + `paymentID`) и набора проводок, который нужно 
   добавить в план (получившийся в результате `cashFlow`)

8. В список событий на запись в `MG` добавляется `cash_flow_changed` c 
   данными о флоу

9. Переход к следующему этапу выполнения


## Обновление Cash-Flow

//TODO: дописать




---

Далее:
- [Обработка шага "process_session"](process-session.md)

Назад:
- [Обработка шага "routing"](routing-workflow.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)
