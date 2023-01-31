```erlang
-type pin() :: #{
    currency => currency(),
    payment_tool => payment_tool(),
    party_id => party_id(),
    client_ip => client_ip() | undefined
}.
```