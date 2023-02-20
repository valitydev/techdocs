## Обработка состояния платежа (`intent`)

```erlang
handle_proxy_intent(#proxy_provider_FinishIntent{status = {success, Success}}, Action, _Session) ->
    Events0 = [?session_finished(?session_succeeded())],
    Events1 =
        case Success of
            #proxy_provider_Success{token = undefined} ->
                Events0;
            #proxy_provider_Success{token = Token} ->
                [?rec_token_acquired(Token) | Events0]
        end,
    {Events1, Action};

handle_proxy_intent(#proxy_provider_FinishIntent{status = {failure, Failure}}, Action, _Session) ->
    Events = [?session_finished(?session_failed({failure, Failure}))],
    {Events, Action};

handle_proxy_intent(#proxy_provider_SleepIntent{timer = Timer}, Action0, _Session) ->
    Action1 = hg_machine_action:set_timer(Timer, Action0),
    {[], Action1};

handle_proxy_intent(
    #proxy_provider_SuspendIntent{tag = Tag, timeout = Timer, timeout_behaviour = TimeoutBehaviour},
    Action0,
    Session
) ->
    #{payment_id := PaymentID, invoice_id := InvoiceID} = tag_context(Session),
    ok = hg_machine_tag:create_binding(hg_invoice:namespace(), Tag, PaymentID, InvoiceID),
    Action1 = hg_machine_action:set_timer(Timer, Action0),
    Events = [?session_suspended(Tag, TimeoutBehaviour)],
    {Events, Action1}.

```