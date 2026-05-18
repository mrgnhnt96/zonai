/// Server entry: pre-renders [Document] and [App] for each request.
library;

import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(Document(title: 'Zonai — Sign in', body: const App()));
}
