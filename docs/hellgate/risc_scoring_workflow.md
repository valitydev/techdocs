# Подсчет рисков

## Немного о подсчете рисков и работе с антифродом

Так как процессинг работает с платежами и множеством платежей из различных 
источников, то существует высокая вероятность столкнуться с мошенниками.
Анализ платежа на потенциальную опасность выполняет система антифрода,
которая отсылает процессингу (или любому другому потребителю) информацию 
об уровне риска платежа (низкий, средний, высокий) и в зависимости от этого
процессинг решает что делать с таким платежом.

# Взаимодействие HG и системы антифрода

Данный этап в рамках `HG` называется `risc_scoring` и выполняется первым 
этапом при создании инвойса.


1. Получение входных данных о платеже и установка локальных переменных.

   1.1. `Opts` - опциональные данные платежа (options)

   1.2. `Revision` - актуальня [ревизия](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L299)

   1.3. `Payment` - контекст платежа

   1.4. `PaymentTool` (`VS1`) - берется из (`dmsl_domain_thrift:'PaymentTool'`, `#{payment_tool := PaymentTool} = VS1 = get_varset(St, #{risk_score => get_risk_score(St)})`)

   1.5. `PaymentInstitutionRef` - достается из `Opts` (структура описана в [damsel.domain](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L1032))

2. Получение информации о `PaymentInstitution` ([PartyManagement.ComputePaymentInstitution](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift#L2766))

3. Проверка на то является ли данный текущий процесс восстановлением машины (repair).
   Если да, то возвращается предыдущее состояние скоринга и переход к п.6, иначе к п.4

4. Из полученного ранее `PaymentInstitution` получется 
   [ссылка на инспектор](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift#L2770) 
   `InspectorRef`. При помощи нее `HG` получает данные самого инспектора (`hg_domain:get`)

5. Вызов [InspectorProxy.InspectPayment](https://github.com/valitydev/damsel/blob/master/proto/proxy_inspector.thrift#L54) 
   и получение значения риска платежа (`RiskScore`)

6. Добавление в список событий инфойса нового события 'InvoicePaymentRiskScoreChanged' 
   (`Events = [?risk_score_changed(RiskScore)]`)

7. Проверка полученного от испектора уровня риска платежа. Если он слишком высок (фатален),
   то выбрасывается ошибка `risk_score_is_too_high`. В противном случае происходит обновление 
   машины, связанной с инвойсом, новым событием оценки риска и переход на следующий этап обработки 
   входящего инвойса.