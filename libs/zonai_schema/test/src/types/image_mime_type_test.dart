import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('ImageMimeType', () {
    test('fromContentType normalizes parameters', () {
      expect(
        ImageMimeType.fromContentType('image/jpeg; charset=binary'),
        ImageMimeType.jpeg,
      );
    });

    test('fromFileExtension resolves stored extensions', () {
      expect(ImageMimeType.fromFileExtension('jpg'), ImageMimeType.jpeg);
    });

    test('detect identifies each supported format', () {
      expect(
        ImageMimeType.detect([0xFF, 0xD8, 0xFF, 0xD9]),
        ImageMimeType.jpeg,
      );
      expect(
        ImageMimeType.detect([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ImageMimeType.png,
      );
      expect(
        ImageMimeType.detect([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
        ImageMimeType.gif,
      );
      expect(
        ImageMimeType.detect([
          0x52,
          0x49,
          0x46,
          0x46,
          0x00,
          0x00,
          0x00,
          0x00,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
        ImageMimeType.webp,
      );
    });

    test('detect returns null for unknown bytes', () {
      expect(ImageMimeType.detect([0x00, 0x01, 0x02]), isNull);
    });
  });
}
