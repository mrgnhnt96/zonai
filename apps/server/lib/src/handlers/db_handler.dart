import 'package:zonai/src/deps/zonai_db.dart';

class DbHandler {
  const DbHandler();

  void get() {}

  Future<List<Map<String, Object?>>> search() async {
    return await zonaiDB.search('items', {});
  }

  Future<List<Map<String, Object?>>> list() async {
    return await zonaiDB.list('items', {});
  }

  void create() {}

  void update() {}

  void updateMany() {}

  void delete() {}
}
