import 'package:zonai_schema/payloads.dart';

import 'sqlite_table_utils.dart';
import 'table_cell_edit.dart';
import 'table_row_key.dart';

/// Whether the admin UI should allow editing or deleting rows in this table.
///
/// When [row] is provided, also checks that the row can be targeted by primary key.
bool canEditTableRows({
  required String sqliteName,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
  List<Object?>? row,
}) {
  if (isSystemSqliteTable(sqliteName)) return false;
  if (!hasEditableColumns(columnShapes)) return false;

  if (row != null) {
    return tableRowWhere(row: row, columns: columns, columnShapes: columnShapes) != null;
  }

  return columnShapes.any((s) => s.isPrimaryKey);
}
