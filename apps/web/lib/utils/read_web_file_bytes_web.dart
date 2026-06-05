import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:universal_web/web.dart' as web;

/// Reads all bytes from a browser [File] or [Blob].
Future<Uint8List> readWebFileBytes(web.Blob blob) async {
  final reader = web.FileReader();
  final completer = Completer<Uint8List>();

  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result == null) {
      completer.completeError(StateError('Failed to read file'));
      return;
    }
    final buffer = (result as JSArrayBuffer).toDart;
    completer.complete(Uint8List.view(buffer));
  });

  reader.readAsArrayBuffer(blob);
  return completer.future;
}
