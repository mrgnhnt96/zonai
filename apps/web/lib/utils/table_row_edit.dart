import 'package:zonai_schema/payloads.dart';

import 'sqlite_table_utils.dart';
import 'table_cell_edit.dart';
import 'table_row_key.dart';

bool _rulesResolved(Map<String, TableCollectionActions>? allActions) {
  return allActions != null && allActions.isNotEmpty;
}

/// Whether the admin UI should allow updating rows in this table.
///
/// Combines rule-derived [actions] with schema constraints. When [row] is
/// provided, also checks that the row can be targeted by primary key.
///
/// If [allActions] is empty (rules were not resolved), falls back to the
/// previous admin UI behavior using [sessionCanEdit].
bool canUpdateTableRows({
  required Map<String, TableCollectionActions>? allActions,
  required TableCollectionActions? actions,
  required bool sessionCanEdit,
  required String sqliteName,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
  List<Object?>? row,
}) {
  if (_rulesResolved(allActions)) {
    if (actions?.canUpdate != true) return false;
  } else {
    if (sessionCanEdit != true || isSystemSqliteTable(sqliteName)) return false;
  }

  if (!hasEditableColumns(columnShapes)) return false;

  if (row != null) {
    return tableRowWhere(row: row, columns: columns, columnShapes: columnShapes) != null;
  }

  return columnShapes.any((s) => s.isPrimaryKey);
}

/// Whether the admin UI should allow deleting rows in this table.
bool canDeleteTableRows({
  required Map<String, TableCollectionActions>? allActions,
  required TableCollectionActions? actions,
  required bool sessionCanEdit,
  required String sqliteName,
  required List<ColumnShape> columnShapes,
}) {
  if (_rulesResolved(allActions)) {
    if (actions?.canDelete != true) return false;
  } else {
    if (sessionCanEdit != true || isSystemSqliteTable(sqliteName)) return false;
  }

  return columnShapes.any((s) => s.isPrimaryKey);
}
