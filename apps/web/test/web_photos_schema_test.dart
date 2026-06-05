import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/web_photos_schema.dart';

void main() {
  const baseUrl = 'http://localhost:8080';
  const id = '0123456789abcde_ph';

  group('photoImageUrlFromId', () {
    test('builds domain image URL with png suffix by default', () {
      expect(
        photoImageUrlFromId(id, imageBaseUrl: baseUrl, extension: null),
        '$baseUrl/img/$id.png',
      );
    });

    test('uses row extension when provided', () {
      expect(
        photoImageUrlFromId(id, imageBaseUrl: baseUrl, extension: 'webp'),
        '$baseUrl/img/$id.webp',
      );
    });

    test('returns null for empty id', () {
      expect(photoImageUrlFromId('', imageBaseUrl: baseUrl, extension: null), isNull);
      expect(photoImageUrlFromId(null, imageBaseUrl: baseUrl, extension: null), isNull);
    });
  });

  group('augmentPhotosTableSchema', () {
    const photosSchema = TableSchemaShape(
      table: photosTableSqliteName,
      columns: [
        ColumnShape(
          name: 'id',
          kind: ColumnShapeKind.id,
          isNullable: false,
          isPrimaryKey: true,
          autoIncrement: false,
          sqlType: 'TEXT',
        ),
        ColumnShape(
          name: 'path',
          kind: ColumnShapeKind.text,
          isNullable: false,
          isPrimaryKey: false,
          autoIncrement: false,
          sqlType: 'TEXT',
        ),
      ],
    );

    test('adds read-only image column after id', () {
      final augmented = augmentPhotosTableSchema(photosSchema);
      expect(augmented.columns.map((c) => c.name), ['id', photosImageColumnName, 'path']);
      expect(augmented.columnNamed(photosImageColumnName)?.kind, ColumnShapeKind.photo);
      expect(augmented.columnNamed(photosImageColumnName)?.isReadOnly, isTrue);
    });

    test('leaves other tables unchanged', () {
      const authors = TableSchemaShape(
        table: 'authors',
        columns: [
          ColumnShape(
            name: 'id',
            kind: ColumnShapeKind.id,
            isNullable: false,
            isPrimaryKey: true,
            autoIncrement: false,
            sqlType: 'TEXT',
          ),
        ],
      );
      expect(augmentPhotosTableSchema(authors), authors);
    });
  });

  group('augmentPhotosRowItems', () {
    test('injects image URL for _photos rows using extension column', () {
      final items = augmentPhotosRowItems(
        sqliteName: photosTableSqliteName,
        items: [
          {'id': id, 'path': 'foo.png', 'extension': 'webp'},
        ],
        imageBaseUrl: baseUrl,
      );
      expect(items.single[photosImageColumnName], '$baseUrl/img/$id.webp');
    });

    test('defaults to png when extension is missing', () {
      final items = augmentPhotosRowItems(
        sqliteName: photosTableSqliteName,
        items: [
          {'id': id, 'path': 'foo.png'},
        ],
        imageBaseUrl: baseUrl,
      );
      expect(items.single[photosImageColumnName], '$baseUrl/img/$id.png');
    });

    test('skips non-photos tables', () {
      const items = [
        {'id': id, 'path': 'foo.png'},
      ];
      expect(
        augmentPhotosRowItems(
          sqliteName: 'authors',
          items: items,
          imageBaseUrl: baseUrl,
        ),
        items,
      );
    });
  });
}
