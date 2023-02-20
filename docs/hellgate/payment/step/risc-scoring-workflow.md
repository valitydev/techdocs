# Подсчет рисков (`risc_scoring`)

## Немного о подсчете рисков и работе с антифродом

Так как процессинг работает с платежами и множеством платежей из различных 
источников, то существует высокая вероятность столкнуться с мошенниками.
Анализ платежа на потенциальную опасность выполняет система антифрода,
которая отсылает процессингу (или любому другому потребителю) информацию 
об уровне риска платежа (низкий, средний, высокий) и в зависимости от этого
процессинг решает что делать с таким платежом.

## Предварительный этап обработки шага (получение сигнала от `MG`)

0. В `MG` машина достигает таймаута и вызывает `HG` на обработку. В контексте машины 
   `Activity = risc_scoring`

1. `HG` получает сигнал от `MG` и [начинает его обработку](../../machinegun/machinegun-signal-processing-workflow.md) (`process_signal`)

2. Пройдя стандартные шаги из пункта 2 сигнал на исполнение доходит до начала обработки этапа
   роутинга `process_timeout({payment, risk_scoring}, Action, St)`


## Обработка этапа подсчета риска (`process_risk_score`)

1. Получение входных данных о платеже и установка локальных переменных.

   1.1. `Opts`, `Revision`, `Payment` - получаются из переменной состояния [St](../../meta/st.md), объявленной и заполненной ранее

   1.2. `PaymentFlow` ([InvoicePaymentFlow](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L604)) - воссоздается из данных платежа ([reconstruct_payment_flow](../../meta/create-payment-flow.md))

   1.3. `PaymentTool` - достается из `Payment` ([Payer часть] (https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L301))

   1.4. [PaymentInstitutionRef](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1032) - 
   достается из [Opts](../../meta/opts.md) (объявляется и заполняется на этапе восстановления контекста из данных машины (сигнала))

2. Получение информации о `PaymentInstitution` ([PartyManagement.ComputePaymentInstitution](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2766))

3. Проверка на то является ли текущий процесс восстановлением машины (repair).
   Если да, то возвращается предыдущее состояние скоринга и переход к п.6, иначе к п.4

4. Из полученного ранее `PaymentInstitution` получется 
   [ссылка на инспектор](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2770) 
   `InspectorRef`. При помощи нее `HG` получает данные самого инспектора (`hg_domain:get`)

5. Вызов [InspectorProxy.InspectPayment](https://github.com/valitydev/damsel/blob/master/proto/proxy_inspector.thrift#L54) 
   и получение значения риска платежа (`RiskScore`)

6. Добавление в список событий инфойса нового события `InvoicePaymentRiskScoreChanged` 
   (`Events = [?risk_score_changed(RiskScore)]`)

7. Проверка полученного от испектора уровня риска платежа. Если он слишком высок (фатален),
   то выбрасывается ошибка `risk_score_is_too_high`. В противном случае происходит обновление 
   машины, связанной с инвойсом, новым событием оценки риска и переход на следующий этап обработки 
   входящего инвойса.

8. Формирование успешного ответа (признак перехода к следующему шагу (next), 
   список событий для обработки (Events), для взаимодействия с MG (сохранить 
   машину с таймаутом 0))

---

Далее:
- [Обработка шага "routing_workflow"](routing-workflow.md)

Назад:
- [Обработка шага "new"](new-payment.md)

В начало:
- [Детальный алгоритм проведения платежей в HG](../hg-payment-workflow.md)