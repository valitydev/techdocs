```erlang
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