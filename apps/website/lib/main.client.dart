/// The entrypoint for the **client** environment.
///
/// Only hydrates components annotated with `@client`; everything else on the
/// page is static HTML produced at build time.
library;

import 'package:jaspr/client.dart';

import 'main.client.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);

  runApp(const ClientApp());
}
