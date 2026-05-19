part of rules;

sealed class BaseCollectionRules<S extends Schema<R>, R> {
  const BaseCollectionRules(this.schema);

  final S schema;

  Table<S, R> get table => Table.getFor(schema);

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
}
