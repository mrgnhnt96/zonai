import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/payloads.dart';

/// Ensures GET `/img/...` responses display inline in the browser.
void applyPhotoViewHeaders(Context context, Response response) {
  if (context.request.method != 'GET' && context.request.method != 'HEAD') {
    return;
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    return;
  }

  final path = context.request.uri.path;
  if (path != '/img' && !path.startsWith('/img/')) {
    return;
  }

  response.headers.set(HttpHeaders.contentDisposition, 'inline');

  final segment = path.split('/').where((part) => part.isNotEmpty).lastOrNull;
  if (segment == null || !segment.contains('.')) {
    return;
  }

  final extension = segment.split('.').last;
  final mime = ImageMimeType.fromFileExtension(extension)?.mimeType;
  if (mime != null) {
    response.headers.mimeType = mime;
  }
}
