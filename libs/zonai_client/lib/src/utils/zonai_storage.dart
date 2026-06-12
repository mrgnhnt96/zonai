import 'dart:convert';

import 'package:revali_client/revali_client.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

/// Persistent storage for Zonai client credentials.
///
/// Implements `revali_client.Storage` so it can be passed directly to [Server].
/// Data is serialized as JSON and written to `zonai_storage.json` inside the
/// provided [directory].
///
/// Three factory variants cover common use cases:
/// - `ZonaiStorage({directory})` — file-backed, survives process restarts
/// - `ZonaiStorage.memory()` — in-memory, suitable for tests or short-lived tools
/// - `ZonaiStorage.none()` — no-op, when token management is handled externally
class ZonaiStorage implements Storage {
  /// Creates a file-backed storage that reads and writes
  /// `<directory>/zonai_storage.json`.
  const ZonaiStorage({required this.directory, FileSystem? fs})
    : fs = fs ?? const LocalFileSystem();

  /// In-memory storage. Values are lost when the process exits.
  ///
  /// Suitable for tests or processes that authenticate on every run.
  factory ZonaiStorage.memory() = _MemoryStorage;

  /// No-op storage. Values are never saved or retrieved.
  ///
  /// Use when token management is handled entirely by the caller, or when
  /// requests are unauthenticated.
  factory ZonaiStorage.none() = _NoStorage;

  final FileSystem fs;

  /// The directory to store the file in.
  final String directory;

  File get _file => fs.file(fs.path.join(directory, 'zonai_storage.json'));

  Map<String, Object?> get _data {
    if (!_file.existsSync()) {
      return {};
    }

    final content = _file.readAsStringSync();
    if (content.isEmpty) {
      return {};
    }

    return {...jsonDecode(content)};
  }

  @override
  Future<Object?> operator [](String key) async {
    return _data[key];
  }

  @override
  Future<void> clear() async {
    _file.deleteSync();
  }

  @override
  Future<void> remove(String key) async {
    final data = _data;
    data.remove(key);
    _file.writeAsStringSync(jsonEncode(data));
  }

  @override
  Future<void> save(String key, Object? value) async {
    final data = _data;
    data[key] = value;
    _file.writeAsStringSync(jsonEncode(data));
  }

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    final data = _data;
    data.addAll(values);
    _file.writeAsStringSync(jsonEncode(data));
  }
}

class _MemoryStorage extends ZonaiStorage {
  _MemoryStorage() : super(directory: '.memory');

  final Map<String, Object?> _data = {};

  @override
  Future<Object?> operator [](String key) async {
    return _data[key];
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> save(String key, Object? value) async {
    _data[key] = value;
  }

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    _data.addAll(values);
  }
}

class _NoStorage extends ZonaiStorage {
  _NoStorage() : super(directory: '.none');

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
