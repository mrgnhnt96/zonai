import 'package:test/test.dart';
import 'package:zonai/src/utils/limit_stream_bytes.dart';

void main() {
  group('limitStreamBytes', () {
    test('passes through chunks under the limit', () async {
      final chunks = [
        [1, 2, 3],
        [4, 5],
      ];

      final result = await limitStreamBytes(
        Stream.fromIterable(chunks),
        10,
      ).toList();

      expect(result, chunks);
    });

    test('throws when total size exceeds the limit', () async {
      final stream = limitStreamBytes(
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

      final result = await limitStreamBytes(
        Stream.fromIterable(chunks),
        5,
      ).toList();

      expect(result, chunks);
    });
  });
}
