## Получение условий обслуживания мерчанта `MerchantTerms`

1. Из данных о магазине (`Shop`) достается `ContractID`

2. Из списка [Party](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L766) 
    по полученному ранее `ContractID` достается `Contract`

3. Проверка на то активен ли контракт
   
4. Получение условий контракта [PartyManagement.ComputeContractTerms](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2580) (`TermSet.payments`)
