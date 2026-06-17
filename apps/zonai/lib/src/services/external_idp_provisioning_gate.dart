/// Gate consulted before `onExternalAuthFirstSeen` provisions a new
/// row for an external-IdP-authenticated user.
///
/// Returning `false` rejects provisioning and the auth flow throws
/// [ExternalIdpProvisioningRejectedException]. Returning `true` (the
/// default no-op behavior) lets provisioning proceed.
///
/// The interface lives in `zonai` so the call site in
/// `_provisionExternalAuthUser` stays transport-agnostic. HTTP servers
/// register an impl that consults rate-limits, abuse signals, or any
/// other per-request context; non-HTTP consumers (CLI tools, tests)
/// inherit the default [AllowAllExternalIdpProvisioningGate] and pay
/// no overhead.
abstract interface class ExternalIdpProvisioningGate {
  Future<bool> canProvision({
    required String table,
    required String issuer,
    required String sub,
  });
}

/// Default impl that always allows provisioning. Registered as the
/// default value of `externalIdpProvisioningGateProvider`.
final class AllowAllExternalIdpProvisioningGate
    implements ExternalIdpProvisioningGate {
  const AllowAllExternalIdpProvisioningGate();

  @override
  Future<bool> canProvision({
    required String table,
    required String issuer,
    required String sub,
  }) async => true;
}
