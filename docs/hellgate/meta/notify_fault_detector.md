

```erlang
maybe_notify_fault_detector({processed, _}, Status, Session) ->
    #domain_PaymentRoute{provider = ProviderRef} = route(Session),
    ProviderID = ProviderRef#domain_ProviderRef.id,
    #{payment_id := PaymentID, invoice_id := InvoiceID} = tag_context(Session),
    ServiceType = provider_conversion,
    OperationID = hg_fault_detector_client:build_operation_id(ServiceType, [InvoiceID, PaymentID]),
    ServiceID = hg_fault_detector_client:build_service_id(ServiceType, ProviderID),
    hg_fault_detector_client:register_transaction(ServiceType, Status, ServiceID, OperationID);

maybe_notify_fault_detector(_TargetType, _Status, _St) ->
    ok.
```

```erlang
notify_fault_detector(Status, Route, CallID) ->
    ServiceType = adapter_availability,
    ProviderRef = get_route_provider(Route),
    ProviderID = ProviderRef#domain_ProviderRef.id,
    ServiceID = hg_fault_detector_client:build_service_id(ServiceType, ProviderID),
    OperationID = hg_fault_detector_client:build_operation_id(ServiceType, [CallID]),
    hg_fault_detector_client:register_transaction(ServiceType, Status, ServiceID, OperationID).

```