// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:isolate';

import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/ddl.dart';

export 'package:zonai_schema/gen/raindrop/raindrop/ddl.dart';

export 'src/sqlite_ddl.dart';
export 'src/sqlite_schema_inspector.dart';

/// The CLI's DDL entrypoint: serves this driver's [DdlGenerator] over the
/// isolate command protocol, and its [SchemaInspector] alongside it.
///
/// SQLite can stand a scratch database up in memory, so it can answer "what
/// do these migrations actually produce" as well as "what SQL expresses this
/// change".
void main(List<String> args, SendPort sendPort) => serveDdlGenerator(
      const SQLiteDdlGenerator(),
      sendPort,
      inspector: const SQLiteSchemaInspector(),
    );
