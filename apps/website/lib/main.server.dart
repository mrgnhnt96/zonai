/// The entrypoint for the **server** environment (static pre-rendering).
library;

import 'package:jaspr/server.dart';

import 'main.server.options.dart';
import 'src/app.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(const ZonaiSite());
}
