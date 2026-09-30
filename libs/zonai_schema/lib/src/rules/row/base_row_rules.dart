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

  rd.TableMeta<S, R> get table => schema.$ as rd.TableMeta<S, R>;

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

  /// The rows [jwt] may see at all, as a filter the server adds to every read.
  ///
  /// A read -- `GET /db`, `/db/list`, `/db/count` and the three streams -- is
  /// answered as if the caller's `where` also said `AND <this>`. A row outside
  /// it is **invisible**: it is not returned, not counted, and never causes a
  /// 403. [canView] still runs on every row inside it, so a scope narrows what
  /// is checked and never replaces the check.
  ///
  /// Without one, a list whose page holds a single row [canView] refuses
  /// fails as a whole with 403, so a caller has to know to filter to their own
  /// rows. With one, the server filters:
  ///
  /// ```dart no-analyze
  /// @override
  /// Future<Where?> viewScope(Jwt? jwt) async {
  ///   // No scope for these two: canView decides, and admins see every row.
  ///   if (jwt == null || jwt.admin.isAdmin) return null;
  ///   return Eq('owner_id', jwt.userId.value);
  /// }
  /// ```
  ///
  /// Keep it consistent with [canView]: a row the scope admits and [canView]
  /// refuses still fails a list with 403. Writes are not scoped; an update or
  /// delete is keyed to the rows its own rules authorized.
  ///
  /// `null`, the default, means no scope, which is the behaviour before this
  /// existed.
  Future<Where?> viewScope(Jwt? jwt) async => null;

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
