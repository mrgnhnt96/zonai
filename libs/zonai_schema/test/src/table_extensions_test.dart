import 'package:raindrop/raindrop.dart' as rd;
import 'package:test/test.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _SecretRowId implements Id {
  const _SecretRowId(this.value);

  @override
  final String value;
}

class _SecretRow {
  const _SecretRow({required this.id, required this.note});

  final _SecretRowId id;
  final String note;
}

final class _SecretRowTable extends Table<_SecretRow> {
  _SecretRowTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _SecretRowId.new,
        generate: () => const _SecretRowId('id-1'),
      ),
      note = $.password('secret_note', (s) => s.note);

  @override
  _SecretRow fromRow(RowReader read) =>
      _SecretRow(id: read(id), note: read(note));

  final IdColumn<_SecretRowId> id;
  final PasswordColumn note;
}

void main() {
  late _SecretRowTable schema;
  late rd.Table<_SecretRowTable, _SecretRow> rows;

  setUp(() {
    schema = table('secret_rows', _SecretRowTable.new);
    rows = rd.Table.getFor(schema);
  });

  test(
    'safeCreate fills absent required secret columns for rules hydration',
    () {
      final row = rows.safeCreate({'id': 'id-1', 'secret_note': 'stored'});

      expect(row.note, 'stored');
    },
  );

  test('safeCreate uses empty string when required secret key is missing', () {
    final row = rows.safeCreate({'id': 'id-1'});

    expect(row.note, '');
  });
}
