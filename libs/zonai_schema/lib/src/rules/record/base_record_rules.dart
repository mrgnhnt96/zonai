part of rules;

class BaseRecordRules<S extends Schema<R>, R> {
  const BaseRecordRules(this.schema);

  final S schema;

  Table<S, R> get table => Table.getFor(schema);

  Future<bool> canView(Jwt? jwt, R record) async {
    return true;
  }

  Future<bool> canUpdate(Jwt? jwt, R record) async {
    return true;
  }

  Future<bool> canDelete(Jwt? jwt, R record) async {
    return true;
  }

  Future<bool> canCreate(Jwt? jwt, R record) async {
    return true;
  }
}
