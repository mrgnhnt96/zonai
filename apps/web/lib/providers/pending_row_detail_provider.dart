import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

/// A row already loaded, waiting for its table's route to be on screen.
///
/// The row-detail panel is mounted by the table route alone, and
/// [TableRowDetailNotifier] resets on every table focus change — that reset is
/// what closes the panel when the operator switches tables. So a caller that
/// is somewhere else entirely (the dashboard, say) cannot open the panel by
/// calling `open()` and then navigating: the navigation it just started is the
/// thing that would throw the row away.
///
/// This carries the row across that navigation instead. It is deliberately
/// held in a provider that does NOT watch table focus, so a route change
/// leaves it standing, and [TableRowDetailNotifier] picks it up on the rebuild
/// that focus change causes.
final class PendingRowDetail {
  const PendingRowDetail({
    required this.sqliteName,
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
  });

  final String sqliteName;
  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
}

final pendingRowDetailProvider = NotifierProvider<PendingRowDetailNotifier, PendingRowDetail?>(
  PendingRowDetailNotifier.new,
);

class PendingRowDetailNotifier extends Notifier<PendingRowDetail?> {
  @override
  PendingRowDetail? build() => null;

  void set(PendingRowDetail pending) => state = pending;

  void clear() => state = null;

  /// Clears only [pending] itself.
  ///
  /// The consumer clears from a microtask, one turn after it read the value.
  /// A blind `clear()` there would throw away a row queued in between —
  /// a second dashboard click while the first was still navigating.
  void clearIf(PendingRowDetail pending) {
    if (identical(state, pending)) state = null;
  }
}
