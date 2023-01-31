```erlang
map_route_switch_reason(RealScores, IdealScores) when
    is_record(RealScores, route_scores); is_record(IdealScores, route_scores)
->
    Zipped = lists:zip(tuple_to_list(RealScores), tuple_to_list(IdealScores)),
    DifferenceIdx = find_idx_of_difference(Zipped),
    lists:nth(DifferenceIdx, record_info(fields, route_scores)).
```