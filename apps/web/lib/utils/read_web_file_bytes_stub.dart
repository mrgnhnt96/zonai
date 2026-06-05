import 'dart:typed_data';

import 'package:universal_web/web.dart' as web;

/// Stub for VM/SSR builds; file reads only run in the browser.
Future<Uint8List> readWebFileBytes(web.Blob blob) {
  throw UnsupportedError('readWebFileBytes is only available in the browser');
}
