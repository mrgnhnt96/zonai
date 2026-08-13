// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// {@template unixepoch}
/// SQLite `unixepoch()`, seconds since the epoch, evaluated by the database.
/// {@endtemplate}
class Unixepoch extends Expression<int> {
  /// {@macro unixepoch}
  const Unixepoch();

  @override
  SQL build() => SQL.function('unixepoch', const []);
}

/// {@macro unixepoch}
Unixepoch unixepoch() => const Unixepoch();

/// {@template current_timestamp}
/// SQLite `CURRENT_TIMESTAMP`, `YYYY-MM-DD HH:MM:SS` in UTC.
/// {@endtemplate}
class CurrentTimestamp extends Expression<String> {
  /// {@macro current_timestamp}
  const CurrentTimestamp();

  @override
  SQL build() => SQL([const RawSQL('CURRENT_TIMESTAMP')]);
}

/// {@macro current_timestamp}
CurrentTimestamp currentTimestamp() => const CurrentTimestamp();
