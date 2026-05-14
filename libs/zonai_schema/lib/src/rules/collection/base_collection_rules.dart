part of rules;

sealed class BaseCollectionRules<T extends Schema<T>> {
  const BaseCollectionRules(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);

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
