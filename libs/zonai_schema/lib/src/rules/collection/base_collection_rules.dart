part of rules;

sealed class BaseCollectionRules<T extends Schema<T>> {
  const BaseCollectionRules(this.schema);

  final T schema;

  Future<bool> canCreate(Request request) async {
    return request.user.isSuperUser;
  }

  Future<bool> canUpdate(Request request) async {
    return request.user.isSuperUser;
  }

  Future<bool> canDelete(Request request) async {
    return request.user.isSuperUser;
  }

  Future<bool> canView(Request request) async {
    return request.user.isSuperUser;
  }

  Future<bool> canList(Request request) async {
    return request.user.isSuperUser;
  }
}
