```erlang
construct_payment_flow({instant, _}, _CreatedAt, _Terms, _PaymentTool) ->
    ?invoice_payment_flow_instant();
construct_payment_flow({hold, Params}, CreatedAt, Terms, PaymentTool) ->
    OnHoldExpiration = Params#payproc_InvoicePaymentParamsFlowHold.on_hold_expiration,
    ?hold_lifetime(Seconds) = validate_hold_lifetime(Terms, PaymentTool),
    HeldUntil = hg_datetime:format_ts(hg_datetime:parse_ts(CreatedAt) + Seconds),
    ?invoice_payment_flow_hold(OnHoldExpiration, HeldUntil).

validate_hold_lifetime(
    #domain_PaymentHoldsServiceTerms{
      payment_methods = PMs,
      lifetime = LifetimeSelector
    },
    PaymentTool
) ->
  ok = validate_payment_tool(PaymentTool, PMs),
  get_selector_value(hold_lifetime, LifetimeSelector);
validate_hold_lifetime(undefined, _PaymentTool) ->
  throw_invalid_request(<<"Holds are not available">>).

validate_payment_tool(PaymentTool, PaymentMethodSelector) ->
  PMs = get_selector_value(payment_methods, PaymentMethodSelector),
  _ =
    case hg_payment_tool:has_any_payment_method(PaymentTool, PMs) of
      false ->
        throw_invalid_request(<<"Invalid payment method">>);
      true ->
        ok
    end,
  ok.

-define(invoice_payment_flow_instant(),
  {instant, #domain_InvoicePaymentFlowInstant{}}
).

-define(hold_lifetime(HoldLifetime), #domain_HoldLifetime{seconds = HoldLifetime}).

-define(invoice_payment_flow_hold(OnHoldExpiration, HeldUntil),
  {hold, #domain_InvoicePaymentFlowHold{on_hold_expiration = OnHoldExpiration, held_until = HeldUntil}}
).

```