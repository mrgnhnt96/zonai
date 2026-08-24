import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';

import '../routes/components/exception_catcher.dart';

/// The 403 body is the ONE structured envelope zonai emits.
///
/// Every other auth failure answers `{"error": "<sentence>"}`, which a client
/// can only match on by wording. This one carries a ticket, so it has to be
/// machine-readable -- and the moment it is machine-readable its shape is API.
/// A client branches on `error.code` and reads `error.details.resetToken`;
/// renaming either is a silent break that no route-drift check would report,
/// because the route did not change. This pins the shape key-for-key so a
/// refactor of the catcher has to come here and say so.
///
/// What this does *not* cover: that the route actually reaches this catcher.
/// That is the e2e fixture's job (prq-e2e) -- this pins the mapping, not the
/// wiring.
void main() {
  const catcher = Exceptions();

  group('a forced password reset', () {
    test('renders the structured envelope on 403', () {
      final handled = catcher
          .onAuthException(
            const PasswordResetRequiredException(
              token: 'dGhlLXNlY3JldDp1c2VyQGV4YW1wbGUuY29t',
              expiresIn: Duration(minutes: 15),
              reason: PasswordResetReason.temporaryPassword,
            ),
          )
          .asHandled;

      expect(handled.statusCode, 403);
      expect(handled.body, {
        'error': {
          'code': 'password_reset_required',
          'message': 'This account must set a new password before signing in',
          'details': {
            'resetToken': 'dGhlLXNlY3JldDp1c2VyQGV4YW1wbGUuY29t',
            'expiresIn': 900,
            'reason': 'temporaryPassword',
          },
        },
      });
    });

    test('reports expiresIn in seconds, not milliseconds', () {
      // `Duration` renders as milliseconds by default, and a client that
      // waited 900_000 seconds would simply never retry.
      final handled = catcher
          .onAuthException(
            const PasswordResetRequiredException(
              token: 'tok',
              expiresIn: Duration(minutes: 5),
              reason: PasswordResetReason.adminForced,
            ),
          )
          .asHandled;

      final body = handled.body! as Map<String, Object?>;
      final error = body['error']! as Map<String, Object?>;
      final details = error['details']! as Map<String, Object?>;

      expect(details['expiresIn'], 300);
    });

    test('carries the reason so a client can say something truer', () {
      for (final reason in PasswordResetReason.values) {
        final handled = catcher
            .onAuthException(
              PasswordResetRequiredException(
                token: 'tok',
                expiresIn: const Duration(minutes: 15),
                reason: reason,
              ),
            )
            .asHandled;

        final body = handled.body! as Map<String, Object?>;
        final error = body['error']! as Map<String, Object?>;
        final details = error['details']! as Map<String, Object?>;

        expect(details['reason'], reason.name);
      }
    });

    test('does not answer 401 -- the credentials were correct', () {
      // The sign-in oracle contract rests on 401 meaning "these credentials
      // are not valid", rendered identically for a wrong password and an
      // unknown address. This response says the opposite. Sharing the status
      // would make the two indistinguishable to a client and would put a
      // ticket on a body that documents itself as carrying only a sentence.
      final refused = catcher
          .onAuthException(const InvalidPasswordOrEmailException())
          .asHandled;

      expect(refused.statusCode, 401);
      expect(refused.body, {
        'error': '${const InvalidPasswordOrEmailException()}',
      });
    });
  });
}
