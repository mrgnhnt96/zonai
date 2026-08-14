import 'package:zonai_crud_matrix/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A table whose only purpose is to be gated by a rule that reads *another*
/// table with an `In`. See `gate_row_rules.dart` -- the row is visible only if
/// the worker could serialize that clause, which is the one code path a CLI
/// release cannot reach (02cfcef).
final class Gate {
  Gate({required this.id, required this.label, required this.createdAt});

  final GatesId id;
  final String label;
  final DateTime createdAt;
}

final class GateTable extends Table<Gate> {
  GateTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: GatesId.new,
        generate: GatesId.generate,
      ),
      label = $.text('label', (s) => s.label),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  Gate fromRow(RowReader read) {
    return Gate(id: read(id), label: read(label), createdAt: read(createdAt));
  }

  final IdColumn<GatesId> id;
  final TextColumn label;
  final DateTimeColumn createdAt;
}

final gates = table('gates', GateTable.new);
