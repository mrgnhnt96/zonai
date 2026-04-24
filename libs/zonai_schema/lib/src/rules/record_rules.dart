part of 'rules.dart';

class RecordRules<T extends Schema<T>> extends Rules<T> {
  RecordRules(super.schema);

  Future<Filter?> canView(Request request) async {
    return null;
  }

  Future<Filter?> canUpdate(Request request) async {
    return null;
  }

  Future<Filter?> canDelete(Request request) async {
    return null;
  }

  Future<Filter?> canCreate(Request request) async {
    return null;
  }
}
