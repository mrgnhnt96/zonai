import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/photo_edit_value.dart';

void main() {
  group('parsePhotoIdFromCell', () {
    test('parses id from image URL', () {
      expect(
        parsePhotoIdFromCell('http://localhost:8080/img/0123456789abcde_ph.png'),
        '0123456789abcde_ph',
      );
    });

    test('accepts raw photo id', () {
      expect(parsePhotoIdFromCell('0123456789abcde_ph'), '0123456789abcde_ph');
    });

    test('returns null for empty', () {
      expect(parsePhotoIdFromCell(''), isNull);
    });

    test('returns null for image URL without photo id suffix', () {
      expect(parsePhotoIdFromCell('http://localhost:8080/img/\$id.png'), isNull);
    });
  });

  group('photoEditValuesEqual', () {
    test('detects pending bytes change', () {
      final a = PhotoEditValue.single(
        PhotoEditItem.pending(bytes: Uint8List.fromList([1, 2]), mimeType: 'image/png'),
      );
      final b = PhotoEditValue.single(
        PhotoEditItem.pending(bytes: Uint8List.fromList([3, 4]), mimeType: 'image/png'),
      );
      expect(photoEditValuesEqual(a, b), isFalse);
    });

    test('treats same existing ids as equal', () {
      const id = '0123456789abcde_ph';
      final a = PhotoEditValue.single(PhotoEditItem.existing(id: id));
      final b = PhotoEditValue.single(PhotoEditItem.existing(id: id));
      expect(photoEditValuesEqual(a, b), isTrue);
    });
  });

  group('cellLooksLikePhoto', () {
    test('detects resolved image URL', () {
      expect(
        cellLooksLikePhoto('http://localhost:8080/img/0123456789abcde_ph.png'),
        isTrue,
      );
    });

    test('detects raw photo id', () {
      expect(cellLooksLikePhoto('0123456789abcde_ph'), isTrue);
    });

    test('rejects plain text', () {
      expect(cellLooksLikePhoto('hello'), isFalse);
    });
  });

  group('photoShapeForCell', () {
    const textShape = ColumnShape(
      name: 'photo',
      kind: ColumnShapeKind.text,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );

    test('upgrades text shape when value is a photo URL', () {
      final shape = photoShapeForCell(
        shape: textShape,
        rawValue: 'http://localhost:8080/img/0123456789abcde_ph.png',
      );
      expect(shape?.kind, ColumnShapeKind.photo);
    });

    test('does not upgrade id columns with photo id values', () {
      const idShape = ColumnShape(
        name: 'id',
        kind: ColumnShapeKind.id,
        isNullable: false,
        isPrimaryKey: true,
        autoIncrement: false,
        sqlType: 'TEXT',
      );
      expect(
        photoShapeForCell(shape: idShape, rawValue: '0123456789abcde_ph'),
        isNull,
      );
    });
  });

  group('photoUrlsFromCell', () {
    const baseUrl = 'http://localhost:8080';

    final photoShape = ColumnShape(
      name: 'image',
      kind: ColumnShapeKind.photo,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );

    final photosShape = ColumnShape(
      name: 'images',
      kind: ColumnShapeKind.photos,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );

    test('resolves id to image URL', () {
      expect(
        photoUrlsFromCell('0123456789abcde_ph', photoShape, imageBaseUrl: baseUrl),
        ['$baseUrl/img/0123456789abcde_ph'],
      );
    });

    test('keeps full image URL', () {
      const url = 'http://localhost:8080/img/0123456789abcde_ph.png';
      expect(
        photoUrlsFromCell(url, photoShape, imageBaseUrl: baseUrl),
        [url],
      );
    });

    test('resolves multiple photos', () {
      expect(
        photoUrlsFromCell(
          [
            '0123456789abcde_ph',
            'http://localhost:8080/img/0123456789abcdf_ph.png',
          ],
          photosShape,
          imageBaseUrl: baseUrl,
        ),
        [
          '$baseUrl/img/0123456789abcde_ph',
          'http://localhost:8080/img/0123456789abcdf_ph.png',
        ],
      );
    });
  });

  group('removedPhotoIds', () {
    final shape = ColumnShape(
      name: 'image',
      kind: ColumnShapeKind.photo,
      isNullable: true,
      isPrimaryKey: false,
      autoIncrement: false,
      sqlType: 'TEXT',
    );

    test('detects removed single photo', () {
      const id = '0123456789abcde_ph';
      final removed = removedPhotoIds(
        originalCell: 'http://localhost:8080/img/$id.png',
        draft: const PhotoEditValue.single(null),
        shape: shape,
      );
      expect(removed, {id});
    });

    test('resolved wire id is not treated as removed when replacing image', () {
      const id = '0123456789abcde_ph';
      final before = photoIdsFromCell(
        'http://localhost:8080/img/$id.png',
        shape,
      ).toSet();
      final after = photoIdsFromCell(id, shape).toSet();
      expect(before.difference(after), isEmpty);
    });

    test('detects removed photo from multi list', () {
      const idA = '0123456789abcde_ph';
      const idB = '0123456789abcdf_ph';
      final removed = removedPhotoIds(
        originalCell: [
          'http://localhost:8080/img/$idA.png',
          'http://localhost:8080/img/$idB.png',
        ],
        draft: PhotoEditValue.multi([
          PhotoEditItem.existing(id: idA),
        ]),
        shape: ColumnShape(
          name: 'images',
          kind: ColumnShapeKind.photos,
          isNullable: true,
          isPrimaryKey: false,
          autoIncrement: false,
          sqlType: 'TEXT',
        ),
      );
      expect(removed, {idB});
    });
  });
}
