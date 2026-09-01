import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/services/external_idp_provisioning_gate.dart';
import 'package:zonai_schema/zonai_schema.dart';

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

/// HTTP-aware impl that rate-limits provisioning per (table, IP) via
/// the existing rate-limit framework. Policy is tunable per auth
/// table through `AuthTableRateLimits.externalIdpProvisioningPolicy`.
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
    final check = await rateLimiter.check(
      table: table,
      ipAddress: ipAddress,
      operation: RateLimitOperation.externalIdpProvisioning,
    );
    return check.allowed;
  }
}
