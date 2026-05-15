part of rules;

sealed class BaseCollectionRules<S extends Schema<R>, R> {
  const BaseCollectionRules(this.schema);

  final S schema;

  Table<S, R> get table => Table.getFor(schema);

  Future<bool> canCreate(Jwt? jwt) async {
    return false;
  }

  Future<bool> canUpdate(Jwt? jwt) async {
    return false;
  }

  Future<bool> canDelete(Jwt? jwt) async {
    return false;
  }

  Future<bool> canView(Jwt? jwt) async {
    return false;
  }

  Future<bool> canList(Jwt? jwt) async {
    return false;
  }
}
