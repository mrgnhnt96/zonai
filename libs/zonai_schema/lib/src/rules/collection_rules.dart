part of 'rules.dart';

class CollectionRules<T extends Schema<T>> extends Rules<T> {
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

  Future<bool> canListOrSearch(Request request) async {
    return request.user.isSuperUser;
  }
}
