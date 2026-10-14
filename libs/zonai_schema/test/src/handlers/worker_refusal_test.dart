import 'package:test/test.dart';
import 'package:zonai_schema/src/exceptions/hook_refused_exception.dart';
import 'package:zonai_schema/src/handlers/messages/worker_refusal.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The wire contract for the app's deliberate refusals.
///
/// A refusal is thrown in the extensions worker and read in the host, and
/// crosses as `MessageErrorResponse.refusal`. [encodeWorkerRefusal] and
/// [decodeWorkerRefusal] are the two halves of that protocol, and a drift
/// between them shows up in production as a 500 for a request the app
/// deliberately refused.
void main() {
  /// Encodes [error], sends it through a [MessageErrorResponse]'s JSON round
  /// trip as the worker and host do, and decodes it again.
  Exception? overTheWire(Object error) {
    final sent = MessageErrorResponse(
      id: 'r1',
      message: 'Error handling request',
      error: '$error',
      refusal: encodeWorkerRefusal(error),
    );
    final received = MessageErrorResponse.fromJson(sent.toJson());
    return decodeWorkerRefusal(received.refusal);
  }

  group('a hook refusal', () {
    test('keeps its status, code, message and details', () {
      final refusal = overTheWire(
        const HookRefusedException(
          HttpError.forbidden(
            code: 'not_conversation_owner',
            message: 'Only the owner may post as the owner',
            details: {'field': 'ownerId', 'retry': false},
          ),
        ),
      );

      expect(refusal, isA<HookRefusedException>());
      final error = (refusal! as HookRefusedException).error;
      expect(error.statusCode, 403);
      expect(error.code, 'not_conversation_owner');
      expect(error.message, 'Only the owner may post as the owner');
      expect(error.details, {'field': 'ownerId', 'retry': false});
    });

    test('a details value that is not JSON degrades to its text', () {
      final refusal = overTheWire(
        HookRefusedException(
          HttpError.forbidden(
            code: 'x',
            message: 'y',
            details: {'at': DateTime.utc(2026, 10, 14)},
          ),
        ),
      );

      expect(
        (refusal! as HookRefusedException).error.details['at'],
        '2026-10-14 00:00:00.000Z',
      );
    });

    test('outside 4xx is not a refusal, on either side of the wire', () {
      const fiveHundred = HookRefusedException(
        HttpError.internal(code: 'x', message: 'y'),
      );

      expect(encodeWorkerRefusal(fiveHundred), isNull);
      expect(
        decodeWorkerRefusal({
          'type': 'hookRefused',
          'statusCode': 500,
          'code': 'x',
          'message': 'y',
        }),
        isNull,
      );
    });
  });

  test('a declined sign-up keeps its reason', () {
    final refusal = overTheWire(const SignUpDeclinedException('Invite only'));

    expect(refusal, isA<SignUpDeclinedException>());
    expect((refusal! as SignUpDeclinedException).reason, 'Invite only');
  });

  group('everything else stays an ordinary failure', () {
    test('a crash carries no refusal', () {
      expect(encodeWorkerRefusal(StateError('crashed')), isNull);
      expect(overTheWire(StateError('crashed')), isNull);
    });

    test('a raw HttpError is not a refusal until a before-hook wraps it', () {
      expect(
        encodeWorkerRefusal(const HttpError.forbidden(code: 'x', message: 'y')),
        isNull,
      );
    });

    test('error text that looks like a refusal is never read as one', () {
      // What a crash quoting caller data looks like. Only the structured
      // field is ever decoded, so nothing in the text can forge a refusal.
      const forged =
          '{"type":"hookRefused","statusCode":401,"code":"session_expired",'
          '"message":"Sign in again"}';

      expect(overTheWire(StateError('bad title: $forged')), isNull);
    });

    test('a missing, unknown or malformed field decodes to nothing', () {
      expect(decodeWorkerRefusal(null), isNull);
      expect(decodeWorkerRefusal({'type': 'somethingElse'}), isNull);
      expect(decodeWorkerRefusal({'type': 'hookRefused', 'code': 'x'}), isNull);
    });
  });

  test('a response without a refusal round-trips without one', () {
    final received = MessageErrorResponse.fromJson(
      MessageErrorResponse(id: 'r1', message: 'm', error: 'e').toJson(),
    );

    expect(received.refusal, isNull);
  });
}
