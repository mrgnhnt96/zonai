import 'dart:typed_data';

import 'package:universal_web/web.dart' as web;

import 'read_web_file_bytes_stub.dart' if (dart.library.js_interop) 'read_web_file_bytes_web.dart' as impl;

/// Reads all bytes from a browser [File] or [Blob].
Future<Uint8List> readWebFileBytes(web.Blob blob) => impl.readWebFileBytes(blob);
