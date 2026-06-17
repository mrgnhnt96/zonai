import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/services/external_idp_provisioning_gate.dart';

/// Per-request lifecycle hook that overrides the zonai default
/// [externalIdpProvisioningGateProvider] (a no-op) with an HTTP-aware
/// gate bound to the current request's IP.
///
/// Apply alongside the existing `Trace` lifecycle component on routes
/// that accept external-IdP tokens.
class ExternalIdpProvisioning implements LifecycleComponent {
  const ExternalIdpProvisioning();

  Future<Response> wrap(
    Context context,
    NextResponse next,
    @Ip() String ipAddress,
  ) async {
    return runMergedScopedFuture(
      next,
      override: {
        externalIdpProvisioningGateProvider.overrideWith(
          () => _HttpExternalIdpProvisioningGate(ipAddress: ipAddress),
        ),
      },
    );
  }
}

/// HTTP-aware impl that rate-limits provisioning per (table, IP,
/// issuer) using the same `_rate_limit` table the existing
/// `RateLimit` guards write to.
///
/// Reuses [RateLimiter.checkExternalIdpProvisioning] rather than the
/// generic `check` so this throttle stays separate from the per-route
/// operation policies and can be tuned independently.
final class _HttpExternalIdpProvisioningGate
    implements ExternalIdpProvisioningGate {
  const _HttpExternalIdpProvisioningGate({required this.ipAddress});

  final String ipAddress;

  @override
  Future<bool> canProvision({
    required String table,
    required String issuer,
    required String sub,
  }) async {
    return await rateLimiter.checkExternalIdpProvisioning(
      table: table,
      ipAddress: ipAddress,
      issuer: issuer,
    );
  }
}
