part of rules;

class BaseRecordRules<T extends Schema<T>> {
  const BaseRecordRules(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);

  Future<bool> canView(Jwt? jwt, T record) async {
    return true;
  }

  Future<bool> canUpdate(Jwt? jwt, T record) async {
    return true;
  }

  Future<bool> canDelete(Jwt? jwt, T record) async {
    return true;
  }

  Future<bool> canCreate(Jwt? jwt, T record) async {
    return true;
  }
}
