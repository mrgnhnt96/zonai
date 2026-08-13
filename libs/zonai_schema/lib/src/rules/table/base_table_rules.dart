part of rules;

/// Table-level authorization for one named custom operation
/// (`TableOperations.custom`). Receives the same `jwt` as `canCreate`/
/// `canUpdate`/etc. — there's no row to inspect at this level.
typedef CustomTableOperationRule = Future<bool> Function(Jwt? jwt);

sealed class BaseTableRules<S extends rd.Schema<R>, R> {
  const BaseTableRules(this.schema);

  final S schema;

  rd.TableMeta<S, R> get table => schema.$ as rd.TableMeta<S, R>;

  Future<bool> canCreate(Jwt? jwt) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }
    return false;
  }

  Future<bool> canUpdate(Jwt? jwt) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }
    return false;
  }

  Future<bool> canDelete(Jwt? jwt) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }
    return false;
  }

  Future<bool> canView(Jwt? jwt) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }
    return false;
  }

  Future<bool> canList(Jwt? jwt) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }
    return false;
  }

  /// Table-level authorization for named custom operations
  /// (`TableOperations.custom`), keyed by operation name. An operation name
  /// not present here is denied — same fail-closed default as every method
  /// above.
  Map<String, CustomTableOperationRule> get customOperations => const {};
}
