part of rules;

class CollectionRules<T extends Collection<T>> extends Rules<T> {
  CollectionRules(super.schema);

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
