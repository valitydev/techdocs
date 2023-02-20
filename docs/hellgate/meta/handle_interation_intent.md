```erlang
-spec handle_interaction_intent(proxy_intent(), _Session) ->
    [change()].

handle_interaction_intent(
    {sleep, #proxy_provider_SleepIntent{
        user_interaction = UserInteraction,
        user_interaction_completion = Completion
    }},
    Session
) ->
    handle_interaction_intent(UserInteraction, Completion, Session);

handle_interaction_intent(
    {suspend, #proxy_provider_SuspendIntent{
        user_interaction = UserInteraction,
        user_interaction_completion = Completion
    }},
    Session
) ->
    handle_interaction_intent(UserInteraction, Completion, Session);

handle_interaction_intent(_Intent, _Session) ->
    [].

handle_interaction_intent(UserInteraction, Completion, Session) ->
    try_complete_interaction(Completion, Session) ++ try_request_interaction(UserInteraction).

try_complete_interaction(undefined, _Session) ->
    [];

try_complete_interaction(#user_interaction_Completed{}, #{interaction := InteractionPrev}) ->
    [?interaction_changed(InteractionPrev, ?interaction_completed)];

try_complete_interaction(#user_interaction_Completed{}, Session) ->
    _ = logger:warning("Received unexpected user interaction completion, session: ~p", [Session]),
    [].

try_request_interaction(undefined) ->
    [];

try_request_interaction(UserInteraction) ->
    [?interaction_changed(UserInteraction, ?interaction_requested)].

```