import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:universal_web/web.dart' as web;

double? eventClientX(web.Event event) {
  final value = (event as JSObject)['clientX']?.dartify();
  if (value is num) return value.toDouble();
  return null;
}

double jsNumProperty(Object object, String property) {
  final value = (object as JSObject)[property]?.dartify();
  if (value is num) return value.toDouble();
  return 0;
}
