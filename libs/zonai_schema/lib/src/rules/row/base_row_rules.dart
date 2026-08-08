part of rules;

/// Row-level authorization for one named custom operation
/// (`TableOperations.custom`). [before] is the row as it exists prior to the
/// write; [after] is simulated from the operation's `updates` exactly like
/// [BaseRowRules.canUpdate]'s — see `TableUpdateSimulation.simulateUpdate`.
typedef CustomRowOperationRule<R> =
    Future<bool> Function(Jwt? jwt, R before, R after);

class BaseRowRules<S extends rd.Schema<R>, R> {
  const BaseRowRules(this.schema);

  final S schema;

  rd.TableMeta<S, R> get table => rd.TableMeta.getFor(schema);

  Future<bool> canView(Jwt? jwt, R row) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    return false;
  }

  /// [before] is the row as it exists prior to the write; [after] is the row
  /// [Update]s would produce, simulated ahead of the write (exact for every
  /// [UpdateValue] variant — see `TableUpdateSimulation.simulateUpdate`).
  Future<bool> canUpdate(Jwt? jwt, R before, R after) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    return false;
  }

  Future<bool> canDelete(Jwt? jwt, R row) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    return false;
  }

  Future<bool> canCreate(Jwt? jwt, R row) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    return false;
  }

  /// When `false`, the host may skip per-row IPC after table access succeeds
  /// (public tables whose row rules always allow). Defaults to `true` so
  /// row-level ACL stays fail-closed unless authors opt out.
  bool get requiresPerRowCheck => true;

  /// Row-level authorization for named custom operations
  /// (`TableOperations.custom`), keyed by operation name. An operation name
  /// not present here is denied — same fail-closed default as every method
  /// above.
  Map<String, CustomRowOperationRule<R>> get customOperations => const {};

  /// [customOperations].keys, resolved from within this class (see
  /// [customOperationCheck]) so a host holding an unparameterized
  /// [BaseRowRules] reference can list registered names without tripping
  /// the same runtime type mismatch — a bare `Set<String>` has no
  /// dependency on [R] to erase.
  Set<String> get customOperationNames => customOperations.keys.toSet();

  /// Dispatches [operation] through [customOperations] — `null` when it
  /// isn't registered (the host treats that as deny).
  ///
  /// The host holds rules through an unparameterized [BaseRowRules]
  /// reference (rules for different tables have different [R]s, so there's
  /// no single parameterized type to hold them all). Unlike [canUpdate],
  /// [customOperations] returns a container of functions rather than being
  /// a plain method — Dart's covariant-override machinery only widens a
  /// method's own parameter types at the call boundary, not a generic
  /// value nested inside a returned container, so the host can't safely
  /// pull a `CustomRowOperationRule<R>` out of that map itself once [R] is
  /// erased. Resolving and invoking it here, where [R] is still concretely
  /// bound, keeps that resolution on the safe (method-call) side of the
  /// boundary.
  Future<bool>? customOperationCheck(
    String operation,
    Jwt? jwt,
    R before,
    R after,
  ) {
    return customOperations[operation]?.call(jwt, before, after);
  }
}
