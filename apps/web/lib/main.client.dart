/// Client entry: hydrates `@client` components from server-rendered markup.
library;

import 'package:jaspr/client.dart';
import 'package:universal_web/web.dart' as web;

import 'main.client.options.dart';
import 'providers/table_filter_provider.dart';

void main() {
  // Capture before router redirects can modify window.location.
  captureInitialFilterSearch(web.window.location.search);
  Jaspr.initializeApp(options: defaultClientOptions);
  runApp(const ClientApp());
}
