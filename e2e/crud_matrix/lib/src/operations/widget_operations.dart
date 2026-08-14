import 'package:zonai_crud_matrix/src/schemas/widgets.dart';
// The narrow `show`, not raindrop_sqlite.dart's barrel: that barrel
// unconditionally exports sqlite_delegate.dart (needs package:sqlite3), and a
// `show` clause only filters NAMES -- see issue #24 and table_operations.dart's
// own comment on the same import.
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/builders/returning.dart'
    show SQLiteUpdateReturning;
import 'package:zonai_schema/zonai_schema.dart';

/// One file per table: the generator loads exactly one [TableOperations] from
/// each operations file's `main()` (see `operation_generator.dart`), so a
/// second class in this file would never be registered.
final class WidgetOperations extends TableOperations<WidgetTable, Widget> {
  WidgetOperations() : super(widgets);

  /// `PATCH /db/custom/:operation` exists so the SERVER can own a mutation's
  /// logic instead of the client dictating it -- the base [TableOperations]
  /// throws [UnimplementedError] for every operation name, and every e2e
  /// fixture until this one left it unimplemented, so the route had no
  /// coverage at all. `restock` is deliberately NOT a passthrough of
  /// [updates]: the caller supplies only `where` and an operation name, and
  /// the delta/status transition are server-decided -- that asymmetry (client
  /// updates ignored, server logic applied) is exactly what distinguishes
  /// this code path from a plain PATCH.
  @override
  ToQuery<Schema<Widget>, Widget> custom(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) {
    return switch (operation) {
      'restock' when where != null => update(const [
        ColumnUpdate('quantity', Add(restockAmount)),
        ColumnUpdate('status', Literal('open')),
      ], where: where).returning(),
      _ => super.custom(operation, where: where, updates: updates),
    };
  }
}

/// Fixed server-side business amount `restock` adds -- not client-supplied,
/// so drive.dart can assert the exact quantity without echoing a client value
/// back at itself.
const restockAmount = 10;

WidgetOperations main() => WidgetOperations();
