# Флоу обработки запросов в machinegun

## Start

Запрос начинается в mg_woody_api_automaton, вызывается handle_function/4. Достается таймаут по дефолту из конфига, путь: namespaces.<namespace>.default_processing_timeout. Либо же достается из woody_context, но туда он может попасть либо в тестах, либо через header (http не реализован).

|
v

Вызывается mg_core_events_machine:start/5

|
v

Вызывается mg_core_machine:start/5. Каждый вызов мы делаем через менеджер воркеров.

|
v

Вызывается mg_core_workers_manager:call/5. Проверяем достигли ли мы Deadline (ошибка `{transient, worker_call_deadline_reached}`), но так как мы не проходим ни через одну очередь, то скорее всего этой ошибки мы никогда не получаем. Если ловим ошибку при вызове mg_core_worker:call/7, делаем ретрай в зависимости от ошибки (mg_core_workers_manager:handle_worker_exit/7), запускаем воркер для конкретно этого ID машины. Ретрай происходит только 1 раз.

|
v

Происходит вызов mg_core_procreg:call/4 через mg_core_worker:call/7. Модуль для procreg берется из конфига и добавляется туда скриптом конфигуратора автоматически на основе добавления конфига консуэлы.

|
v

Скорее всего вызывается mg_core_procreg_consuela:call/4, так как используем его на проде. Создается процесс для этой машины (так как она новая, то существующего нет). Используется process registry консуэлы через `{via, consuela, ViaName}`
(https://www.erlang.org/doc/man/gen_server.html#type-server_ref).

|
v

<!-- TODO расписать что происходит -->
Обрабатывается вызов на создание в mg_core_machine:handle_call/5.