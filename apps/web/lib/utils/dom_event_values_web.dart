import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:universal_web/web.dart' as web;

double? _eventClientCoord(web.Event event, String property) {
  final value = (event as JSObject)[property]?.dartify();
  if (value is num) return value.toDouble();
  return null;
}

double? eventClientX(web.Event event) => _eventClientCoord(event, 'clientX');

double? eventClientY(web.Event event) => _eventClientCoord(event, 'clientY');

String? eventPointerType(web.Event event) {
  final value = (event as JSObject)['pointerType']?.dartify();
  return value is String ? value : null;
}

double jsNumProperty(Object object, String property) {
  final value = (object as JSObject)[property]?.dartify();
  if (value is num) return value.toDouble();
  return 0;
}
