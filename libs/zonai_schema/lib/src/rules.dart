import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/request.dart';

class Rules<T extends Schema<T>> {
  Rules(this.schema);

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

  Future<bool> canListOrSearch(Request request) async {
    return request.user.isSuperUser;
  }
}

extension RetrieveTableX<T extends Schema<T>> on Rules<T> {
  Table<T> get table => Table.getFor(schema);
}
