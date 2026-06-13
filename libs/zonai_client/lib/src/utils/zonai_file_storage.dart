import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:revali_client/revali_client.dart';

/// File-backed [Storage] for CLI and server-side Zonai clients.
///
/// Import `package:zonai_client/storage.dart` — not the main `zonai_client.dart`
/// library — so browser apps do not pull `package:file` into the client graph.
class ZonaiFileStorage implements Storage {
  const ZonaiFileStorage({required this.directory, FileSystem? fs})
    : fs = fs ?? const LocalFileSystem();

  final FileSystem fs;
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
  Future<Object?> operator [](String key) async => _data[key];

  @override
  Future<void> clear() async => _file.deleteSync();

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
