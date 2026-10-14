import 'package:test/test.dart';
import 'package:zonai_schema/src/exceptions/hook_refused_exception.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The wire contract for a `before*` hook's refusal.
///
/// [HookRefusedException] is thrown in the extensions worker and read in the
/// host, and only its `toString` makes the trip. So `toString` and `tryParse`
/// are two halves of one protocol, and these tests hold them together. A
/// drift between them shows up in production as a 500 for a write the app
/// deliberately refused.
void main() {
  group('round-trips through the worker boundary', () {
    test('status, code, message and details survive unchanged', () {
      const original = HookRefusedException(
        HttpError.forbidden(
          code: 'not_conversation_owner',
          message: 'Only the owner may post as the owner',
          details: {'field': 'ownerId', 'retry': false},
        ),
      );

      final error = HookRefusedException.tryParse('$original')?.error;

      expect(error, isNotNull);
      expect(error!.statusCode, 403);
      expect(error.code, 'not_conversation_owner');
      expect(error.message, 'Only the owner may post as the owner');
      expect(error.details, {'field': 'ownerId', 'retry': false});
    });

    test('survives the framing the worker wraps the cause in', () {
      const original = HookRefusedException(
        HttpError.badRequest(code: 'empty_title', message: 'Title is empty'),
      );

      final error = HookRefusedException.tryParse(
        'Error handling request: $original',
      )?.error;

      expect(error?.statusCode, 400);
      expect(error?.details, isEmpty);
    });

    test('keeps a message with newlines and quotes whole', () {
      const original = HookRefusedException(
        HttpError.conflict(code: 'taken', message: 'No.\n"Really" no.'),
      );

      expect(
        HookRefusedException.tryParse('$original')?.error.message,
        'No.\n"Really" no.',
      );
    });

    test('a details value that is not JSON degrades to its text', () {
      final original = HookRefusedException(
        HttpError.forbidden(
          code: 'x',
          message: 'y',
          details: {'at': DateTime.utc(2026, 10, 14)},
        ),
      );

      expect(
        HookRefusedException.tryParse('$original')?.error.details['at'],
        '2026-10-14 00:00:00.000Z',
      );
    });
  });

  group('refuses to claim failures that are not refusals', () {
    test('an unrelated worker error is not a refusal', () {
      // A hook that crashed is a 500. Reporting it as a 4xx would tell the
      // caller the app refused them when the app is broken.
      expect(
        HookRefusedException.tryParse(
          'Error handling request: Bad state: No element',
        ),
        isNull,
      );
    });

    test('a marker followed by something other than the fields is not', () {
      expect(
        HookRefusedException.tryParse('zonai:hook-refused: not json'),
        isNull,
      );
      expect(
        HookRefusedException.tryParse('zonai:hook-refused: {"code": "x"}'),
        isNull,
      );
    });

    test('a status outside 4xx is not a refusal, even with the marker', () {
      const original = HookRefusedException(
        HttpError.internal(code: 'x', message: 'y'),
      );

      expect(HookRefusedException.tryParse('$original'), isNull);
    });
  });

  test('only 4xx counts as a refusal', () {
    bool refuses(int status) => HookRefusedException.refuses(
      HttpError(statusCode: status, code: 'x', message: 'y'),
    );

    expect(refuses(400), isTrue);
    expect(refuses(403), isTrue);
    expect(refuses(499), isTrue);
    expect(refuses(200), isFalse);
    expect(refuses(399), isFalse);
    expect(refuses(500), isFalse);
    expect(refuses(503), isFalse);
  });
}
