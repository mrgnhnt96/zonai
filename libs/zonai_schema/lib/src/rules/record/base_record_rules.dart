part of rules;

class BaseRecordRules<T extends Schema<T>> {
  const BaseRecordRules(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);

  Future<bool> canView(Request request, T record) async {
    return true;
  }

  Future<bool> canUpdate(Request request, T record) async {
    return true;
  }

  Future<bool> canDelete(Request request, T record) async {
    return true;
  }

  Future<bool> canCreate(Request request, T record) async {
    return true;
  }
}
