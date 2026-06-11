import 'package:raindrop/raindrop.dart' as rd show Table;
import 'package:test/test.dart';
import 'package:zonai_schema/src/tables/table.dart' as zs;
import 'package:zonai_schema/zonai_schema.dart' hide table;

void main() {
  group('tableSchemaShapeFromTable', () {
    test('maps zonai column transformers to semantic kinds', () {
      final shape = tableSchemaShapeFromTable(
        rd.Table.getFor(_DemoTable.schemaTable),
      );

      expect(shape.table, 'demo_rows');
      expect(shape.columnNamed('id')?.kind, ColumnShapeKind.id);
      expect(shape.columnNamed('email')?.kind, ColumnShapeKind.email);
      expect(
        shape.columnNamed('is_verified')?.kind,
        ColumnShapeKind.isVerified,
      );
      expect(shape.columnNamed('password')?.isSecret, isTrue);
      expect(shape.columnNamed('status')?.enumValues, ['draft', 'published']);
      expect(shape.columnNamed('created_at')?.isReadOnly, isTrue);
    });

    test('maps photo transformer runtime type to photo kind', () {
      final shape = tableSchemaShapeFromTable(
        rd.Table.getFor(_PhotoDemoTable.schemaTable),
      );

      expect(shape.columnNamed('image')?.kind, ColumnShapeKind.photo);
    });

    test('maps BigIntTransfomer columns to bigInt kind', () {
      final shape = tableSchemaShapeFromTable(
        rd.Table.getFor(_BigIntDemoTable.schemaTable),
      );

      expect(shape.columnNamed('big_count')?.kind, ColumnShapeKind.bigInt);
      expect(shape.columnNamed('payload')?.kind, ColumnShapeKind.blob);
    });

    test('round-trips through json', () {
      final shape = tableSchemaShapeFromTable(
        rd.Table.getFor(_DemoTable.schemaTable),
      );
      final restored = TableSchemaShape.fromJson(shape.toJson());
      expect(restored, shape);
    });
  });
}

final class _DemoRow {
  _DemoRow({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.password,
    required this.status,
    required this.createdAt,
  });

  final UnknownId id;
  final String email;
  final bool isVerified;
  final String password;
  final _Status status;
  final DateTime createdAt;
}

enum _Status { draft, published }

final class _DemoTable extends Table<_DemoRow> {
  _DemoTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate()),
      ),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      password = $.password('password', (s) => s.password),
      status = $.enumerator('status', _Status.values, (s) => s.status),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  static final schemaTable = zs.table('demo_rows', _DemoTable.new);

  @override
  _DemoRow fromRow(RowReader read) => _DemoRow(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
    password: read(password),
    status: read(status),
    createdAt: read(createdAt),
  );

  final IdColumn<UnknownId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn password;
  final EnumColumn<_Status> status;
  final DateTimeColumn createdAt;
}

final class _PhotoRow {
  _PhotoRow({required this.id, this.image});

  final UnknownId id;
  final PhotoId? image;
}

final class _PhotoDemoTable extends Table<_PhotoRow> {
  _PhotoDemoTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate()),
      ),
      image = $.photo('image', (s) => s.image);

  static final schemaTable = zs.table('photo_demo', _PhotoDemoTable.new);

  @override
  _PhotoRow fromRow(RowReader read) =>
      _PhotoRow(id: read(id), image: read(image));

  final IdColumn<UnknownId> id;
  final PhotoColumn? image;
}

final class _BigIntRow {
  _BigIntRow({required this.id, required this.bigCount, this.payload});

  final UnknownId id;
  final BigInt bigCount;
  final List<int>? payload;
}

final class _BigIntDemoTable extends Table<_BigIntRow> {
  _BigIntDemoTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UnknownId.new,
        generate: () => UnknownId(Id.generate()),
      ),
      bigCount = $.bigInt('big_count', (s) => s.bigCount),
      payload = $.blob('payload', (s) => s.payload);

  static final schemaTable = zs.table('bigint_demo', _BigIntDemoTable.new);

  @override
  _BigIntRow fromRow(RowReader read) => _BigIntRow(
    id: read(id),
    bigCount: read(bigCount),
    payload: read(payload),
  );

  final IdColumn<UnknownId> id;
  final BigIntColumn bigCount;
  final BlobColumn? payload;
}
