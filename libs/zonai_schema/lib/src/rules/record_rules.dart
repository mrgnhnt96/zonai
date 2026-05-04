part of 'rules.dart';

class RecordRules<T extends Schema<T>> extends Rules<T> {
  RecordRules(super.schema);

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
