import 'package:revali_client/revali_client.dart';

/// Browser-safe [Storage] factories for the Zonai client.
///
/// For file-backed persistence (CLI / server-side), import
/// `package:zonai_client/storage.dart` and use [ZonaiFileStorage].
abstract final class ZonaiStorage {
  ZonaiStorage._();

  /// In-memory storage. Values are lost when the process exits.
  static Storage memory() => ZonaiMemoryStorage();

  /// No-op storage. Values are never saved or retrieved.
  static Storage none() => ZonaiNoStorage();
}

final class ZonaiMemoryStorage implements Storage {
  final Map<String, Object?> _data = {};

  @override
  Future<Object?> operator [](String key) async => _data[key];

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> save(String key, Object? value) async => _data[key] = value;

  @override
  Future<void> saveAll(Map<String, Object?> values) async =>
      _data.addAll(values);
}

final class ZonaiNoStorage implements Storage {
  @override
  Future<Object?> operator [](String key) async {
    assert(false, 'Cannot read from no-op storage');
    return null;
  }

  @override
  Future<void> clear() async {
    assert(false, 'Cannot clear no-op storage');
  }

  @override
  Future<void> remove(String key) async {
    assert(false, 'Cannot remove from no-op storage');
  }

  @override
  Future<void> save(String key, Object? value) async {
    assert(false, 'Cannot save to no-op storage');
  }

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    assert(false, 'Cannot save all to no-op storage');
  }
}
