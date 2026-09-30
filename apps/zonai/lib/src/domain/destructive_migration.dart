import 'package:raindrop_cli/src/core/differ.dart';
import 'package:raindrop_cli/src/core/snapshot.dart';

/// What a migration from [from] to [to] would destroy, one line per loss,
/// described for a person deciding whether to allow it. Empty when nothing is
/// lost.
///
/// raindrop's generator emits a `DROP TABLE` for a table that left the schema,
/// and rebuilds a table without a column that left it -- the column's data
/// goes with it. Both happen for edits that do not read as destructive: a
/// table renamed in its schema file is a new, empty table plus a dropped old
/// one, and `serve`/`dev` generate and apply on every schema save. The docs
/// used to promise that neither was ever generated.
///
/// Computed with raindrop's own [SchemaDiffer], so it agrees with the SQL that
/// was generated rather than with a second opinion about it -- a column
/// raindrop recognises as RENAMED keeps its data and is not reported.
/// Operations are read through `toMap()`, their wire form, so this needs no
/// dependency on raindrop's DDL types.
List<String> destructiveChanges(SchemaSnapshot? from, SchemaSnapshot to) {
  final losses = <String>[];
  for (final operation in SchemaDiffer().diff(from, to)) {
    final map = operation.toMap();
    switch (map['type']) {
      case 'dropTable':
        losses.add('drops table "${map['tableName']}" and every row in it');
      case 'alterTable':
        final oldTable = map['oldTable'] as Map<String, dynamic>;
        final newTable = map['newTable'] as Map<String, dynamic>;
        final renamed = (map['renamedColumns'] as Map?)?.keys.toSet() ?? {};
        final kept = _columnNames(newTable);
        for (final column in _columnNames(oldTable)) {
          if (kept.contains(column) || renamed.contains(column)) continue;
          losses.add(
            'drops column "${oldTable['name']}"."$column" and its data',
          );
        }
    }
  }
  return losses;
}

Set<String> _columnNames(Map<String, dynamic> table) => {
  for (final column in table['columns'] as List<dynamic>)
    (column as Map<String, dynamic>)['name'] as String,
};
