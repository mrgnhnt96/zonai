import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The wire contract for a declined sign-up.
///
/// [SignUpDeclinedException] is thrown in the extensions **worker** and read
/// in the **host**, and nothing typed survives that trip: the worker sends
/// `MessageErrorResponse(message:, error:)`, both `String`, and the host
/// rebuilds a `MessageHandlerFailedException` from them. So `toString` and
/// `tryParse` are two halves of a protocol, and these tests are what make
/// them one — a change to either that is not mirrored in the other fails
/// here rather than in production, where the symptom is a 500 for a sign-up
/// the app deliberately refused.
void main() {
  group('round-trips through the worker boundary', () {
    test('a reason survives toString -> tryParse unchanged', () {
      const original = SignUpDeclinedException('Invite only');

      final recovered = SignUpDeclinedException.tryParse('$original');

      expect(recovered, isNotNull);
      expect(recovered!.reason, 'Invite only');
    });

    test('survives the framing the host wraps the cause in', () {
      // `MessageHandlerFailedException.toString()` is `'$message: $cause'`,
      // and `_runSignUpGate` reads `cause` — but a caller that logs the whole
      // exception, or a future change that passes `message` instead, must not
      // silently turn a 403 into a 500. Parsing is unanchored for exactly
      // this reason.
      const original = SignUpDeclinedException('Domain not eligible');

      final recovered = SignUpDeclinedException.tryParse(
        'Error handling request: $original',
      );

      expect(recovered?.reason, 'Domain not eligible');
    });

    test('keeps a multi-line reason whole', () {
      const original = SignUpDeclinedException('No.\nSeriously, no.');

      expect(
        SignUpDeclinedException.tryParse('$original')?.reason,
        'No.\nSeriously, no.',
      );
    });

    test('falls back to the default reason when the app supplied none', () {
      const original = SignUpDeclinedException();

      expect(SignUpDeclinedException.tryParse('$original')?.reason, isNotEmpty);
    });
  });

  group('refuses to claim failures that are not declines', () {
    test('an unrelated worker error is not a decline', () {
      // The distinction is load-bearing: a hook that crashed is a 500, and
      // reporting it as a 403 would tell the caller the app refused them when
      // the truth is that the app is broken.
      expect(
        SignUpDeclinedException.tryParse(
          'Error handling request: Bad state: No element',
        ),
        isNull,
      );
    });

    test('the phrase alone, without the marker, is not a decline', () {
      expect(SignUpDeclinedException.tryParse('sign-up declined'), isNull);
    });
  });
}
