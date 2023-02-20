```erlang
-record(route, {
    provider_ref :: dmsl_domain_thrift:'ProviderRef'(),
    terminal_ref :: dmsl_domain_thrift:'TerminalRef'(),
    weight :: integer(),
    priority :: integer(),
    pin :: pin()
}).
```