```erlang
-record(st, {
    activity :: undefined | activity(),
    invoice :: undefined | invoice(),
    payments = [] :: [{payment_id(), payment_st()}],
    adjustments = [] :: [adjustment()],
    party :: undefined | party()
}).

-type activity() ::
invoice
| {payment, payment_id()}
| {adjustment_new, adjustment_id()}
| {adjustment_pending, adjustment_id()}.

-type invoice() :: dmsl_domain_thrift:'Invoice'().
-type party() :: dmsl_domain_thrift:'Party'().

-type adjustment() :: dmsl_payproc_thrift:'InvoiceAdjustment'().

-type payment_id() :: dmsl_domain_thrift:'InvoicePaymentID'().
-type payment_st() :: hg_invoice_payment:st().

-type st() :: #st{}.

```