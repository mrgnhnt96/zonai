import 'dart:convert';

import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

/// Triggers a browser download of [content] as [filename].
void downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain;charset=utf-8',
}) {
  final blob = web.Blob([utf8.encode(content).toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
