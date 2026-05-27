import 'package:test/test.dart';
import 'package:zonai/src/utils/photo_stream_utils.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('PhotoStreamUtils.limitBytes', () {
    test('passes through chunks under the limit', () async {
      final chunks = [
        [1, 2, 3],
        [4, 5],
      ];

      final result = await PhotoStreamUtils.limitBytes(
        Stream.fromIterable(chunks),
        10,
      ).toList();

      expect(result, chunks);
    });

    test('throws when total size exceeds the limit', () async {
      final stream = PhotoStreamUtils.limitBytes(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
        5,
      );

      await expectLater(stream.toList(), throwsStateError);
    });

    test('allows uploads exactly at the limit', () async {
      final chunks = [
        [1, 2],
        [3, 4, 5],
      ];

      final result = await PhotoStreamUtils.limitBytes(
        Stream.fromIterable(chunks),
        5,
      ).toList();

      expect(result, chunks);
    });
  });

  group('PhotoStreamUtils.detectMimeType', () {
    test('detects jpeg from split chunks', () async {
      final (detected, stream) = await PhotoStreamUtils.detectMimeType(
        Stream.fromIterable([
          [0xFF],
          [0xD8, 0xFF, 0xD9],
        ]),
      );

      expect(detected, ImageMimeType.jpeg);
      expect(
        await stream.expand((chunk) => chunk).toList(),
        [0xFF, 0xD8, 0xFF, 0xD9],
      );
    });

    test('returns null for empty stream', () async {
      final (detected, stream) = await PhotoStreamUtils.detectMimeType(
        const Stream.empty(),
      );

      expect(detected, isNull);
      expect(await stream.toList(), isEmpty);
    });
  });

  group('PhotoStreamUtils.verifyExpectedType', () {
    test('returns replay stream when bytes match', () async {
      final chunks = [
        [0xFF, 0xD8, 0xFF],
        [0xD9],
      ];

      final stream = await PhotoStreamUtils.verifyExpectedType(
        Stream.fromIterable(chunks),
        ImageMimeType.jpeg,
      );

      expect(await stream.toList(), chunks);
    });

    test('throws when bytes do not match expected type', () async {
      expect(
        PhotoStreamUtils.verifyExpectedType(
          Stream.value([
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
          ]),
          ImageMimeType.jpeg,
        ),
        throwsStateError,
      );
    });

    test('throws on empty stream', () async {
      expect(
        PhotoStreamUtils.verifyExpectedType(
          const Stream.empty(),
          ImageMimeType.jpeg,
        ),
        throwsStateError,
      );
    });
  });

  group('PhotoStreamUtils.verifyMimeType', () {
    test('passes through matching bytes', () async {
      final chunks = [
        [0xFF, 0xD8, 0xFF],
        [0xD9],
      ];

      final result = await PhotoStreamUtils.verifyMimeType(
        Stream.fromIterable(chunks),
        ImageMimeType.jpeg,
      ).toList();

      expect(result, chunks);
    });

    test('throws when declared type does not match bytes', () async {
      final stream = PhotoStreamUtils.verifyMimeType(
        Stream.value([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
        ImageMimeType.jpeg,
      );

      await expectLater(stream.toList(), throwsStateError);
    });

    test('throws on empty stream', () async {
      final stream = PhotoStreamUtils.verifyMimeType(
        const Stream.empty(),
        ImageMimeType.jpeg,
      );

      await expectLater(stream.toList(), throwsStateError);
    });

    test('verifies bytes split across chunks', () async {
      final result = await PhotoStreamUtils.verifyMimeType(
        Stream.fromIterable([
          [0xFF],
          [0xD8, 0xFF, 0xD9],
        ]),
        ImageMimeType.jpeg,
      ).expand((chunk) => chunk).toList();

      expect(result, [0xFF, 0xD8, 0xFF, 0xD9]);
    });
  });
}
