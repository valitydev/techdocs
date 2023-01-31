Получение лучшего терминала вне зависимости от данных полученных от 
fault-detector (availability и conversion)

```erlang
select_better_route_ideal(Left, Right) ->
    IdealLeft = set_ideal_score(Left),
    IdealRight = set_ideal_score(Right),
    case select_better_route(IdealLeft, IdealRight) of
        IdealLeft -> Left;
        IdealRight -> Right
    end.

set_ideal_score({RouteScores, PT}) ->
  {
    RouteScores#route_scores{
      availability_condition = 1,
      availability = 1.0,
      conversion_condition = 1,
      conversion = 1.0
    },
    PT
  }.

select_better_route(Left, Right) ->
  max(Left, Right).

-record(route_scores, {
  availability_condition :: condition_score(),
  conversion_condition :: condition_score(),
  priority_rating :: terminal_priority_rating(),
  pin :: integer(),
  random_condition :: integer(),
  availability :: float(),
  conversion :: float()
}).
```
