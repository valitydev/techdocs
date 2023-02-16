## Выполнение возврата (refund)

Возврат происходит следующим образом:

1. Вызывается функция [Invoicing.RefundPayment](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L1406)
2. Инициализация первичных данных
3. Создание возврата на стороне HG (обработка шага [refund_new]())
4. Обработка шага [refund_session]()

Если процедура возврата идет по успешному сценарию:

5. Обработка шага [refund_accounter]()
6. Завершение возврата (`idle`)

Если в результате проведения возврата произошла ошибка:

5. Обработка шага [refund_failure]()
