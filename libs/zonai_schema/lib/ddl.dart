/// raindrop_cli's DDL entrypoint for this package.
///
/// `DdlRunner` resolves the driver package's DDL entrypoint by path --
/// `<driver package root>/lib/ddl.dart` -- and, unlike the introspection
/// entrypoint, has no `--driver-import` equivalent to redirect it. zonai passes
/// `--driver zonai_schema` (raindrop_sqlite is vendored under
/// `lib/gen/raindrop/`, so there is no `raindrop_sqlite` package for the CLI to
/// resolve), which makes this file the path it looks for.
///
/// It cannot simply `export` the vendored entrypoint: `Isolate.spawnUri` needs
/// `main` declared in the library it spawns, so this re-declares it.
///
/// Deliberately does not import the `raindrop_sqlite.dart` barrel -- that
/// exports `sqlite_delegate.dart`, which needs `package:sqlite3`, and this
/// entrypoint is spawned inside the *user's* project, which has zonai_schema
/// but not necessarily sqlite3 (issue #24). The vendored `ddl.dart` reaches
/// only `sqlite_ddl.dart`/`sqlite_dialect.dart`, both sqlite3-free.
library;

import 'dart:isolate';

import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/ddl.dart';

void main(List<String> args, SendPort sendPort) =>
    serveDdlGenerator(const SQLiteDdlGenerator(), sendPort);
