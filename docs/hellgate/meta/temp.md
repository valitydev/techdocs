## Этапы переходов для платежа в HG

0. Список переходов Activity успешного платежа в HG
```
(processed)
new -> risc_scoring
risc_scoring -> routing
routing -> cash_flow_building
cash_flow_building -> processing_session
processing_session -> processing_session (some time)
processing_session -> processing_accounter
processing_accounter -> flow_waiting
(captured)
flow_waiting -> processing_capture
processing_capture -> updating_accounter
updating_accounter -> finalizing_session
finalizing_session -> finalizing_accounter
finalizing_accounter -> idle
```

---
```
Activity: new -> risc_scoring
Target: processed
```
---
```
Activity: risc_scoring -> routing
Target: processed
```
---
```
Activity: routing -> cash_flow_building
Target: processed
```
---
```
Activity: flow_waiting -> processing_capture
Target: captured
```
---
```
Activity: cash_flow_building -> processing_session
Target: processed
```

```
Activity: processing_capture -> updating_accounter
Target: captured
```
---
```
Activity: finalizing_accounter -> idle
Target: captured
```
---
```
Activity: processing_accounter -> flow_waiting
Target: processed
```
---
```
Activity: processing_session -> processing_session
Target: processed | captured
```
```
Activity: flow_waiting -> finalizing_session
Target: processed | captured
```
```
Activity: processing_capture -> finalizing_session
Target: captured
```
```
Activity: updating_accounter -> finalizing_session
Target: processed | captured
```
```
Activity: finalizing_session -> finalizing_session
Target: processed | captured
```
---
```
Activity: processing_session -> processing_accounter
Target: processed | captured
```
```
Activity: finalizing_session -> finalizing_accounter
Target: processed | captured
```
---
```
Activity: risk_scoring, routing, routing_failure, processing_failure -> idle
Target: Target
Status: failed
```
---
```
Activity: finalizing_accounter -> idle
Target: cancelled
```
---
```
Activity: ? -> idle
Target: refunded
```
---
```
Activity: ? -> idle
Target: charged_back
```
---
```
refund_new -> refund_session -> refund_accounter -> idle
refund_new -> refund_session -> refund_failure
```
---
```
adjustment_new -> adjustment_pending -> idle
```
---
```
Activity: processing_session -> processing_session
```
или
```
Activity: finalizing_session -> finalizing_session
```
---
```
Activity: cash_flow_building, processing_session
->
CashFlow exists -> processing_failure
CashFlow doesn't exist -> routing_failure
```
---
```
created | stage_changed -> idle
updating_chargeback -> updating_chargeback
preparing_initial_cash_flow -> idle
updating_cash_flow -> finalising_accounter
idle -> finalising_accounter
idle (status_accepted) -> finalising_accounter
updating_chargeback -> updating_cash_flow
updating_chargeback -> updating_cash_flow
finalising_accounter -> idle
```
---