import 'package:zonai_crud_matrix/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// One column per storage class SQLite has, because the operator matrix in
/// tool/ci/e2e/bin/drive.dart crosses every `Where` against every one of them.
///
/// [code] is TEXT and every seeded value is digits, deliberately: issue #21
/// was a leading-zero `Eq` that a SQL-builder unit test passed. `'007'` and
/// `'7'` are distinct rows here, so any path that coerces a TEXT comparison
/// to a number returns the wrong row rather than no row -- a failure mode a
/// count-only assertion can miss but a value assertion cannot.
final class Widget {
  Widget({
    required this.id,
    required this.code,
    required this.status,
    required this.quantity,
    required this.weight,
    required this.active,
    required this.createdAt,
    this.note,
    this.updatedAt,
  });

  final WidgetsId id;
  final String code;
  final String status;
  final int quantity;
  final double weight;
  final bool active;
  final DateTime createdAt;

  /// Nullable on purpose: `is_null` / `not_null` have no other subject.
  final String? note;
  final DateTime? updatedAt;
}

final class WidgetTable extends Table<Widget> {
  WidgetTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: WidgetsId.new,
        generate: WidgetsId.generate,
      ),
      code = $.text('code', (s) => s.code),
      status = $.text('status', (s) => s.status),
      quantity = $.integer('quantity', (s) => s.quantity),
      weight = $.real('weight', (s) => s.weight),
      active = $.boolean('active', (s) => s.active),
      note = $.text('note', (s) => s.note),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Widget fromRow(RowReader read) {
    return Widget(
      id: read(id),
      code: read(code),
      status: read(status),
      quantity: read(quantity),
      weight: read(weight),
      active: read(active),
      note: read(note),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<WidgetsId> id;
  final TextColumn code;
  final TextColumn status;
  final IntColumn quantity;
  final RealColumn weight;
  final BooleanColumn active;
  final ColumnType<String?> note;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final widgets = table('widgets', WidgetTable.new);
