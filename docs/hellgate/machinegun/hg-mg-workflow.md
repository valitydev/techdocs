# Взаимодействие HG и MG

## Введение

[Machinegun](docs/machinegun/overview.md) придуман для обслуживания _активных_ 
бизнес-процессов и является ядром для работы Hellgate. В своем взаимодействии
HG инициирует создание машины, а дальнейшую работу уже инициирует MG реагируя
на таймауты внутренних таймеров (устанавливаемых при взаимодействии)

## Реализация и особенности

Работа между HG и MG происходит по протоколу [machinegun-proto](https://github.com/valitydev/machinegun-proto).
Основной единицей взаимодействия выступает объект [машина](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L82).
В рамках протолока реализуется несколько сервисов:
- [Processor](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L310) - процессор 
переходов состояния ограниченного конечного автомата (В результате вызова каждого из методов сервиса должны появиться новое
состояние и новые действия, приводящие к дальнейшему прогрессу автомата).
- [Automaton](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L410) - сервис 
управления процессами автоматов, отвечающий за реализацию желаемых действий и поддержку состояния процессоров.
- [EventSink](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L497) - сервис 
получения истории событий сразу всех машин.
- [Modernizer](https://github.com/valitydev/machinegun-proto/blob/master/proto/state_processing.thrift#L347) - cервис 
обновления устаревших представлений данных машины.

Несколько основных моментов взаимодействия HG и MG:

- [Обработка сигнала на взаимодействие от MG](machinegun-signal-processing-workflow.md)