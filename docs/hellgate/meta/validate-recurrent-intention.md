```erlang
-spec validate_recurrent_intention(
    payer(),
    recurrent_paytool_service_terms(),
    payment_tool(),
    shop(),
    payment(),
    make_recurrent()
) -> ok | no_return().
validate_recurrent_intention(
    ?recurrent_payer() = Payer,
    RecurrentTerms,
    PaymentTool,
    Shop,
    ParentPayment,
    MakeRecurrent
) ->
    ok = validate_recurrent_terms(RecurrentTerms, PaymentTool),
    ok = validate_recurrent_payer(Payer, MakeRecurrent),
    ok = validate_recurrent_parent(Shop, ParentPayment);
validate_recurrent_intention(Payer, RecurrentTerms, PaymentTool, _Shop, _ParentPayment, true = MakeRecurrent) ->
    ok = validate_recurrent_terms(RecurrentTerms, PaymentTool),
    ok = validate_recurrent_payer(Payer, MakeRecurrent);
validate_recurrent_intention(_Payer, _RecurrentTerms, _PaymentTool, _Shop, _ParentPayment, false = _MakeRecurrent) ->
    ok.
```