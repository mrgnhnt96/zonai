part of rules;

class BaseRecordRules<S extends rd.Schema<R>, R> {
  const BaseRecordRules(this.schema);

  final S schema;

  rd.Table<S, R> get table => rd.Table.getFor(schema);

  Future<bool> canView(Jwt? jwt, R record) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    return false;
  }

  Future<bool> canUpdate(Jwt? jwt, R record) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    return false;
  }

  Future<bool> canDelete(Jwt? jwt, R record) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    return false;
  }

  Future<bool> canCreate(Jwt? jwt, R record) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    return false;
  }
}
