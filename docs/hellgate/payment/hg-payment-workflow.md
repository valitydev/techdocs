## Детальный алгоритм проведения платежей в HG

### Проведение успешного платежа

1. Создание нового инвойса ([Invoicing.Create](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1042)). 
   [Инициализация данных](step/init-payment.md) платежа

2. Создание нового платежа [Invoicing.StartPayment](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1134). 
   Обработка этапа [new](step/new-payment.md)

3. Обработка шага [risk_scoring](step/risc-scoring-workflow.md) 

4. Обработка шага [routing](step/routing-workflow.md)

5. Обработка шага [cash_flow_building](step/cash-flow-building.md)

6. Обработка шага [processing_session](step/process-session.md). 
   Данный этап может исполняться несколько раз (пока находится в состоянии 
   [InvoicePaymentSessionChange -> SessionStarted](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L243)) до момента, когда:
   - сессия завершилась успешно - статус сессии равен `finished`, а результат 
   `session_succeeded`;
   - получено событие `payment_rollback_started` (будет переход на этап 
   `processing_failure`) 
   - 

7. Обработка шага [processing_accounter](step/processing-accounter.md), а так же генерация 
   нового события payment_status_changed

8. Обработка шага [flow_waiting](step/flow-waiting.md). Операция может быть несколько 
   интераций на данном шаге. Чтобы перейти далее необходимо:
   - если событие находится на этапе session_started, то будет переход на этап finalizing_session
   - если событие находится на этапе payment_capture_started, то будет переход на этап processing_capture

9. Обработка шага [processing_capture](step/processing-capture.md) платежа

10. Обработка шага [updating_accounter](step/updating-accounter.md) платежа

11. Обработка шага [finalizing_session](step/finalizing-session.md) 

12. Обработка шага [finalizing_accounter](step/finalizing-accounter.md) 

13. Завершение платежа (idle)

---

### Выполнение отмены (cancel) платежа

После путкта 8 "[flow_waiting](step/flow-waiting.md)" приходит `Target = cancelled`

9. Обработка шага [finalizing_session](step/finalizing-session.md)

10. Обработка шага [finalizing_accounter](step/finalizing-accounter.md)

11. Завершение платежа (idle)

---

### Выполнение отката (rollback) платежа

Внутренний откат платежа может происходить на двух этапах:

1. Когда `CashFlow` еще не был создан. Тогда будет обработан шаг [routing_failure]()

2. Когда `CashFlow` уже создан. Тогда обрабатывается шаг [processing_failure]()

### Обработка ошибок при проведении платежа

Этап Target=failed может прийти в результате работы нескольких шагов:
- risk_scoring;
- routing;
- routing_failure; 
- processing_failure.

Если такой этап был получен для обработки, то платеж переводится в статус Failed,
a activity переводится в idle.

---

### Выполнение возврата (refund) 

Возврат происходит следующим образом:

1. Вызывается функция []() 
2. Инициализация первичных данных
3. Создание возврата на стороне HG (обработка шага refund_new)
4. Обработка шага refund_session

Если процедура возврата идет по успешному сценарию:

5. Обработка шага refund_accounter
6. Завершение возврата (idle)

Если в результате проведения возврата произошла ошибка

5. Обработка шага refund_failure

---

### Выполнение корректировки (adjustment) платежа

1. Вызывается функция []()
2. Инициализация первичных данных
3. Обработка шага adjustment_new
4. Обработка шага adjustment_pending
5. Завершение обработки корректировки

---

### Выполнение процедуры чарджбэка (chargeback)

1. Вызывается функция []()
2. Инициализация первичных данных
3. // TODO

---




