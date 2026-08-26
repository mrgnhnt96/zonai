import 'package:zonai_schema/payloads.dart';

import '../providers/sqlite_tables_provider.dart';

/// One collection a dashboard session `user_id` might be a row in.
final class SessionUserLookupCandidate {
  const SessionUserLookupCandidate({required this.sqliteName, required this.idColumn});

  /// The SQLite table name — also the segment the table route is built from.
  final String sqliteName;

  /// The column a `_jwt.user_id` is compared against: the primary key.
  final String idColumn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionUserLookupCandidate && other.sqliteName == sqliteName && other.idColumn == idColumn;

  @override
  int get hashCode => Object.hash(sqliteName, idColumn);

  @override
  String toString() => 'SessionUserLookupCandidate($sqliteName.$idColumn)';
}

/// The collections a session `user_id` could name, in probe order.
///
/// **Why this is a search and not a lookup.** `_jwt` is `id`, `user_id` and
/// `expires_at` — there is no column saying which collection the user is in,
/// so the dashboard's metrics cannot carry one either. The id has to be tried
/// against the collections that can hold one.
///
/// An auth collection is keyed on [ColumnShapeKind.isVerified], the same test
/// the row-detail panel makes: `isVerified` comes from `HasEmail`, which
/// `PasswordAuth`, `OtpAuth`, `MagicLinkAuth` and `OAuth` all implement, so it
/// is on every auth collection and on no ordinary one.
///
/// What this does NOT find, and the caller must report rather than paper over:
/// a collection that is an auth table with no auth mixin at all — an id and
/// nothing else, signed in to with `zonai db token create --as`. Such a table
/// is indistinguishable from an ordinary one here, and probing every table in
/// the database to catch it would spend a request per table on every click.
///
/// [tables] is the sidebar snapshot, and is a filter rather than decoration:
/// the row-detail panel only exists on the table route, and a table with no
/// sidebar entry has no route to open it on. Order follows [tables] so the
/// probe order is the operator's own list order, not map iteration order.
List<SessionUserLookupCandidate> sessionUserLookupCandidates({
  required Map<String, TableSchemaShape> schemas,
  required List<SqliteTableRef> tables,
}) {
  final candidates = <SessionUserLookupCandidate>[];

  for (final table in tables) {
    if (table.isView) continue;

    final schema = schemas[table.sqliteName];
    if (schema == null || schema.isView) continue;
    if (!schema.columns.any((column) => column.kind == ColumnShapeKind.isVerified)) continue;

    final idColumn = _primaryKeyColumn(schema);
    if (idColumn == null) continue;

    candidates.add(SessionUserLookupCandidate(sqliteName: table.sqliteName, idColumn: idColumn));
  }

  return candidates;
}

/// The single-column primary key, or null when the table has none or a
/// composite one.
///
/// A composite key cannot be matched against a lone `user_id`, so such a
/// collection is dropped rather than probed on its first key column — a probe
/// on half a key can match the wrong row.
String? _primaryKeyColumn(TableSchemaShape schema) {
  String? found;
  for (final column in schema.columns) {
    if (!column.isPrimaryKey) continue;
    if (found != null) return null;
    found = column.name;
  }
  return found;
}
