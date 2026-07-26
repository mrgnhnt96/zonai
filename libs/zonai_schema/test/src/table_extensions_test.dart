import 'package:raindrop/raindrop.dart' as rd;
import 'package:test/test.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
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

class _GeneratedRowId implements Id {
  const _GeneratedRowId(this.value);

  @override
  final String value;
}

class _GeneratedRow {
  const _GeneratedRow({required this.id, required this.apiKey});

  final _GeneratedRowId id;
  final String apiKey;
}

final class _GeneratedRowTable extends Table<_GeneratedRow> {
  _GeneratedRowTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _GeneratedRowId.new,
        generate: () => const _GeneratedRowId('id-1'),
      ),
      apiKey = $.serverGenerated('api_key', (s) => s.apiKey);

  @override
  _GeneratedRow fromRow(RowReader read) =>
      _GeneratedRow(id: read(id), apiKey: read(apiKey));

  final IdColumn<_GeneratedRowId> id;
  final ColumnType<String> apiKey;
}

void main() {
  group('secret columns', () {
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
  });

  group('server-generated columns', () {
    late _GeneratedRowTable schema;
    late rd.Table<_GeneratedRowTable, _GeneratedRow> rows;

    setUp(() {
      schema = table('generated_rows', _GeneratedRowTable.new);
      rows = rd.Table.getFor(schema);
    });

    test(
      'safeCreate fills an absent required serverGenerated column so rules '
      'can still build the row before an operations override supplies the '
      'real value',
      () {
        final row = rows.safeCreate({'id': 'id-1'});

        expect(row.apiKey, '');
      },
    );

    test('safeCreate preserves a value if one is actually present', () {
      final row = rows.safeCreate({'id': 'id-1', 'api_key': 'oc_real_key'});

      expect(row.apiKey, 'oc_real_key');
    });

    test(
      'unlike a secret column, a serverGenerated column is not a '
      'SecretTransformer — sanitization (which type-checks specifically '
      'for SecretTransformer, see apps/zonai db_operations._sanitize) '
      'leaves it in place',
      () {
        final column = rows.columns.firstWhere((c) => c.name == 'api_key');
        expect(column.transformer, isNot(isA<SecretTransformer>()));
      },
    );
  });
}
