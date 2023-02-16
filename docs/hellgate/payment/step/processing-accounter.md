## Процедура работы со счетами

### Назначение

В результате работы с платежами нужно поникать кому, куда и когда были переведены 
денежные средства, понимать балансы и лимиты. Для учета такой информации в
рамках процессинга реализован сервис shumway (по терминологии HG Accounter),
который обладает всем необходимым функционалом для работы с проводками.

Во время проведения платежа HG формирует проводки (CashFlow) и передает их
в shumway и в зависимости от этапа денежные средства холдируются и потом могут 
быть переведены на соответствующие счета (если платеж завершился успешно) или нет.

### Реализация шага `processing_accounter` в HG

1. `HG` получает сигнал от `MG` и [начинает его обработку](../../machinegun/machinegun-signal-processing-workflow.md) (`process_signal`)

2. Получение из контекста [St()](docs/hellgate/meta/st.md) Activity и Target

3. Установка таймаута для машины

    3.1. Если target = processed

    3.1.1. Если payment_flow = instant, то таймаут устанавливается в 0

    3.1.2. Если payment_flow = hold, то устанавливается дедлайн для операции (ненулевой таймаут)

    3.2. При любом другом target возвращется исходный [Action]()

4. Создание нового события payment_status_changed от полученного Target (иными словами 
   создание нового объекта [InvoicePaymentStatusChanged](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L226))

   ```erlang
   -define(payment_status_changed(Status),
     {
       invoice_payment_status_changed, 
       #payproc_InvoicePaymentStatusChanged{status = Status}
     }
   ).
   ```
5. Завершение шага `processing_accounter` 
   (Возврат нового события для сохранения в `MG`, `activity` устанавливается в `flow_waiting`)


