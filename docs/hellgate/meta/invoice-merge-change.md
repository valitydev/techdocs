```erlang
merge_change(?invoice_created(Invoice), St, _Opts) ->
    St#st{activity = invoice, invoice = Invoice};

merge_change(?invoice_status_changed(Status), St = #st{invoice = I}, _Opts) ->
    St#st{invoice = I#domain_Invoice{status = Status}};

merge_change(?invoice_adjustment_ev(ID, Event), St, _Opts) ->
    St1 =
        case Event of
            ?invoice_adjustment_created(_Adjustment) ->
                St#st{activity = {adjustment_new, ID}};
            ?invoice_adjustment_status_changed({processed, _}) ->
                St#st{activity = {adjustment_pending, ID}};
            ?invoice_adjustment_status_changed(_Status) ->
                St#st{activity = invoice}
        end,
    Adjustment = merge_adjustment_change(Event, try_get_adjustment(ID, St1)),
    St2 = set_adjustment(ID, Adjustment, St1),
    case get_adjustment_status(Adjustment) of
        {captured, _} ->
            apply_adjustment_status(Adjustment, St2);
        _ ->
            St2
    end;

merge_change(?payment_ev(PaymentID, Change), St = #st{invoice = #domain_Invoice{id = InvoiceID}}, Opts) ->
    PaymentSession = try_get_payment_session(PaymentID, St),
    PaymentSession1 = merge_payment_change(Change, PaymentSession, Opts#{invoice_id => InvoiceID}),
    St1 = set_payment_session(PaymentID, PaymentSession1, St),
    case hg_invoice_payment:get_activity(PaymentSession1) of
        A when A =/= idle ->
            % TODO Shouldn't we have here some kind of stack instead?
            St1#st{activity = {payment, PaymentID}};
        idle ->
            check_non_idle_payments(St1)
    end.
```