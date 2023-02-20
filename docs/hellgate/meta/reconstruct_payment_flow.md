```erlang
reconstruct_payment_flow(?invoice_payment_flow_instant(), _CreatedAt, VS) ->
    VS#{flow => instant};
reconstruct_payment_flow(?invoice_payment_flow_hold(_OnHoldExpiration, HeldUntil), CreatedAt, VS) ->
    Seconds = hg_datetime:parse_ts(HeldUntil) - hg_datetime:parse_ts(CreatedAt),
    VS#{flow => {hold, ?hold_lifetime(Seconds)}}.

```