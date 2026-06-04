import 'package:universal_web/web.dart' as web;

import 'dom_event_values_stub.dart' if (dart.library.js_interop) 'dom_event_values_web.dart' as impl;

double? eventClientX(web.Event event) => impl.eventClientX(event);

double? eventClientY(web.Event event) => impl.eventClientY(event);

String? eventPointerType(web.Event event) => impl.eventPointerType(event);

double jsNumProperty(Object object, String property) => impl.jsNumProperty(object, property);
