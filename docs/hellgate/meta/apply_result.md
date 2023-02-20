## Применение события 

```erlang
apply_result(Result = {Events, _Action}, T) ->
    {Result, update_state_with(Events, T)}.


-spec update_state_with(events(), t()) -> t().
update_state_with(Events, T) ->
  Context = #{
    timestamp => erlang:system_time(millisecond),
    target => target(T)
  },
  lists:foldl(
    fun(Ev, State) -> apply_event(Ev, State, Context) end,
    T,
    Events
  ).

-spec apply_event(event(), t() | undefined, event_context()) -> t().

apply_event(?session_started(), undefined, Context) ->
  Session0 = create_session(Context),
  mark_timing_event(started, Context, Session0);

apply_event(?session_finished(Result), Session, Context) ->
  Session2 = Session#{status => finished, result => Result},
  accrue_timing(finished, started, Context, Session2);

apply_event(?session_activated(), Session, Context) ->
  Session2 = Session#{status => active},
  accrue_timing(suspended, suspended, Context, Session2);

apply_event(?session_suspended(Tag, TimeoutBehaviour), Session, Context) ->
  Session2 = set_tag(Tag, Session),
  Session3 = set_timeout_behaviour(TimeoutBehaviour, Session2),
  Session4 = mark_timing_event(suspended, Context, Session3),
  Session4#{status => suspended};

apply_event(?trx_bound(Trx), Session, _Context) ->
  Session#{trx => Trx};

apply_event(?proxy_st_changed(ProxyState), Session, _Context) ->
  Session#{proxy_state => ProxyState};

apply_event(?interaction_changed(UserInteraction, Status), Session, _Context) ->
  case genlib:define(Status, ?interaction_requested) of
    ?interaction_requested ->
      Session#{interaction => UserInteraction};
    ?interaction_completed ->
      {UserInteraction, Session1} = maps:take(interaction, Session),
      Session1
  end;

%% Ignore ?rec_token_acquired event cause it's easiest way to handle this
%% TODO maybe add this token to session state and remove it from payment state?
apply_event(?rec_token_acquired(_Token), Session, _Context) ->
  Session.

```