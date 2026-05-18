/// Server entry: pre-renders [Document] and [App] for each request.
library;

import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';
import 'server/sqlite_table_names.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      title: 'Zonai — Sign in',
      body: AsyncBuilder(
        builder: (context) async {
          final tables = loadZonaiSqliteTableNames();
          return App(
            initialTables: tables.names,
            tablesLoadError: tables.error,
          );
        },
      ),
    ),
  );
}
