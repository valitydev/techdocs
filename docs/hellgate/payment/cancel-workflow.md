# Работа с отменами денежных средств. Реализация

## Немного об отменах

Процедура отмены это операция снятия резервиврования денежных средств 
во время 2 стадийного платежа.

Работает только с двухстадийными платежами

## Алгоритм работы

После того как завершился этап PROCESSED платежа система при двухстадийном 
платеже ожидает перевода платежа к какой-то дальнейший статус. Он может быть:
- `CAPTURED`, если платеж подтвержден (его может подтвердить как мерчант, так и 
сам HG, если терминал к провайдеру имеет соответствующую настройку);
- `FAILED`, если во время ожидания что-то пошло не так (какие-то проблемы 
с мерчантом и т.п.);
- `CANCELLED` - если мерчант решил отменить платеж и вернуть покупателю деньги.

После того как было сгенерировано событие `CANCELLED` `HG` создает соответствующий 
контекст отправляет в адаптер, через который было проведено резервирование 
денежных средств, данные на отмены холдирования. 

После получения ответа от адаптера `HG` переводит машину (и соответственно операцию)
в статус `CANCELLED`.