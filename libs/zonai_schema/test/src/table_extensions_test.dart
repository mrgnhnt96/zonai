import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
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

class _Recording {
  const _Recording({
    required this.id,
    required this.apiKey,
    required this.size,
    this.note,
  });

  final String id;
  final String apiKey;
  final int size;
  final String? note;
}

final class _RecordingTable extends Table<_Recording> {
  _RecordingTable(super.$)
    : id = $.text('id', (s) => s.id),
      apiKey = $.text('api_key', (s) => s.apiKey),
      size = $.integer('size', (s) => s.size),
      note = $.text('note', (s) => s.note);

  @override
  _Recording fromRow(RowReader read) => _Recording(
    id: read(id),
    apiKey: read(apiKey),
    size: read(size),
    note: read(note),
  );

  final TextColumn id;
  final TextColumn apiKey;
  final ColumnType<int> size;
  final ColumnType<String?> note;
}

void main() {
  group('a value from the caller its column cannot hold', () {
    late rd.TableMeta<_RecordingTable, _Recording> rows;

    setUp(() {
      final schema = table('recordings', _RecordingTable.new);
      rows = schema.$ as TableMeta<_RecordingTable, _Recording>;
    });

    Matcher refusedWith(String message) => throwsA(
      isA<InvalidBodyException>().having((e) => e.message, 'message', message),
    );

    test('a required column left out is refused, naming it', () {
      expect(
        () => rows.safeCreate({'id': 'r1', 'size': 1}),
        refusedWith('Column "api_key" on "recordings" is required'),
      );
    });

    test('a required column sent as null is refused, naming it', () {
      expect(
        () => rows.safeCreate({'id': 'r1', 'api_key': null, 'size': 1}),
        refusedWith('Column "api_key" on "recordings" cannot be null'),
      );
    });

    test('a value of the wrong type is refused by its type, not its '
        'value', () {
      expect(
        () => rows.safeCreate({'id': 'r1', 'api_key': 'k', 'size': 'big'}),
        refusedWith('Column "size" on "recordings" cannot hold a String'),
      );
    });

    test('a correct row, with or without its nullable column, builds', () {
      final row = rows.safeCreate({'id': 'r1', 'api_key': 'k', 'size': 2});
      expect(row.apiKey, 'k');
      expect(row.size, 2);
      expect(row.note, isNull);

      expect(
        rows.safeCreate({
          'id': 'r1',
          'api_key': 'k',
          'size': 2,
          'note': 'hi',
        }).note,
        'hi',
      );
    });

    test('a stored row that cannot be built stays a server fault', () {
      expect(
        () => rows.safeCreate({'id': 'r1', 'size': 1}, stored: true),
        throwsA(isA<TypeError>()),
      );
    });

    test('a stored row with the caller\'s changes applied is the '
        'caller\'s', () {
      expect(
        () => rows.safeCreate(
          {'id': 'r1', 'api_key': null, 'size': 1},
          stored: true,
          fromCaller: true,
        ),
        refusedWith('Column "api_key" on "recordings" cannot be null'),
      );
    });
  });

  group('secret columns', () {
    late _SecretRowTable schema;
    late rd.TableMeta<_SecretRowTable, _SecretRow> rows;

    setUp(() {
      schema = table('secret_rows', _SecretRowTable.new);
      rows = schema.$ as TableMeta<_SecretRowTable, _SecretRow>;
    });

    test(
      'safeCreate fills absent required secret columns for rules hydration',
      () {
        final row = rows.safeCreate({'id': 'id-1', 'secret_note': 'stored'});

        expect(row.note, 'stored');
      },
    );

    test(
      'safeCreate uses empty string when required secret key is missing',
      () {
        final row = rows.safeCreate({'id': 'id-1'});

        expect(row.note, '');
      },
    );
  });

  group('server-generated columns', () {
    late _GeneratedRowTable schema;
    late rd.TableMeta<_GeneratedRowTable, _GeneratedRow> rows;

    setUp(() {
      schema = table('generated_rows', _GeneratedRowTable.new);
      rows = schema.$ as TableMeta<_GeneratedRowTable, _GeneratedRow>;
    });

    test('safeCreate fills an absent required serverGenerated column so rules '
        'can still build the row before an operations override supplies the '
        'real value', () {
      final row = rows.safeCreate({'id': 'id-1'});

      expect(row.apiKey, '');
    });

    test('safeCreate preserves a value if one is actually present', () {
      final row = rows.safeCreate({'id': 'id-1', 'api_key': 'oc_real_key'});

      expect(row.apiKey, 'oc_real_key');
    });

    test('unlike a secret column, a serverGenerated column is not a '
        'SecretTransformer — sanitization (which type-checks specifically '
        'for SecretTransformer, see apps/zonai db_operations._sanitize) '
        'leaves it in place', () {
      final column = rows.columns.firstWhere((c) => c.name == 'api_key');
      expect(column.transformer, isNot(isA<SecretTransformer>()));
    });
  });
}
