import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group('formatSchemaCell', () {
    test('null and secrets', () {
      expect(formatSchemaCell(null, null), '—');
      const secret = ColumnShape(
        name: 'password',
        kind: ColumnShapeKind.password,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        isSecret: true,
      );
      expect(formatSchemaCell('hash', secret), '••••••••');
      expect(formatSchemaCell('hash', secret, revealSecrets: true), 'hash');
    });

    test('booleans and verified flags', () {
      const shape = ColumnShape(
        name: 'active',
        kind: ColumnShapeKind.boolean,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
      );
      expect(formatSchemaCell(1, shape), 'Yes');
      expect(formatSchemaCell(0, shape), 'No');
      expect(formatSchemaCell(true, shape), 'Yes');
    });

    test('datetime from epoch milliseconds', () {
      const shape = ColumnShape(
        name: 'created_at',
        kind: ColumnShapeKind.createdAt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'INTEGER',
        isReadOnly: true,
      );
      final ms = DateTime.utc(2024, 6, 15, 12, 30, 45).millisecondsSinceEpoch;
      expect(formatSchemaCell(ms, shape), '2024-06-15 12:30:45 UTC');
    });

    test('enum and structured values', () {
      const enumShape = ColumnShape(
        name: 'status',
        kind: ColumnShapeKind.enum_,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
        enumValues: ['draft', 'published'],
      );
      expect(formatSchemaCell('published', enumShape), 'published');

      const mapShape = ColumnShape(
        name: 'meta',
        kind: ColumnShapeKind.map,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      expect(
        formatSchemaCell('{"a":1}', mapShape),
        '{\n  "a": 1\n}',
      );
    });

    test('photos', () {
      const shape = ColumnShape(
        name: 'gallery',
        kind: ColumnShapeKind.photos,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      expect(
        formatSchemaCell(
          ['https://example.com/img/a.jpg', 'https://example.com/img/b.jpg'],
          shape,
        ),
        '2 photos',
      );
    });

    test('bigInt from binary-digit blob and decimal string', () {
      const shape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.bigInt,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );
      const expected = '9007199254740991';
      final blob = BigInt.parse(expected).toRadixString(2).split('').map(int.parse).toList();
      expect(formatSchemaCell(blob, shape), expected);
      expect(formatSchemaCell(expected, shape), expected);
      expect(formatSchemaCell(9007199254740991, shape), expected);
    });

    test('misclassified blob shape still formats binary-digit bigInt blobs', () {
      const blobShape = ColumnShape(
        name: 'big_count',
        kind: ColumnShapeKind.blob,
        isNullable: false,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'BLOB',
      );
      final blob = BigInt.parse('9007199254740991').toRadixString(2).split('').map(int.parse).toList();
      expect(formatSchemaCell(blob, blobShape), '9007199254740991');
    });

    test('photo and blob truncation', () {
      const photoShape = ColumnShape(
        name: 'avatar',
        kind: ColumnShapeKind.photo,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      final longUrl = 'https://example.com/${'x' * 80}/photo.jpg';
      expect(formatSchemaCell(longUrl, photoShape).endsWith('…'), isTrue);
      expect(formatSchemaCell(longUrl, photoShape, truncate: false), longUrl);

      const blobShape = ColumnShape(
        name: 'payload',
        kind: ColumnShapeKind.blob,
        isNullable: true,
        isPrimaryKey: false,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      final longBlob = 'a' * 100;
      expect(formatSchemaCell(longBlob, blobShape).length, lessThan(100));
      expect(formatSchemaCell(longBlob, blobShape, truncate: false), longBlob);
    });
  });
}
