// A `Server` built with a caller-supplied `Storage`. `MyCustomStorage` is the
// reader's own class in the doc, so it is stubbed here -- the point of the
// example is the wiring, and the stub is what makes the wiring checkable.
import 'package:revali_client/revali_client.dart' show Storage;
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

class MyCustomStorage implements Storage {
  @override
  Future<Object?> operator [](String key) async => null;

  @override
  Future<void> save(String key, Object? value) async {}

  @override
  Future<void> saveAll(Map<String, Object?> values) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> remove(String key) async {}
}

Future<void> example() async {
  // <<body>>
}
