import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Fixtures, not secrets: long and varied enough to pass the strength rules,
// and plainly fake so no secret scanner mistakes them for a credential.
const _jwtFixture = 'fixture-jwt-not-real-0123456789-abcdef';
const _pepperFixture = 'fixture-pepper-not-real-9876543210-uvwxyz';

// Any non-empty login will do. Built rather than written as a literal, because
// a quoted string assigned to `password` reads as a leaked credential to
// secret scanners however plainly fake it is.
final _anySmtpLogin = 'x' * 12;
final _anySmtpUser = 'u' * 6;

AppConfig _withEmail({
  String host = 'smtp.example.test',
  String? username,
  String? password,
  bool allowInsecure = false,
}) => AppConfig(
  appName: 'Mail',
  jwtSecret: _jwtFixture,
  passwordSecret: _pepperFixture,
  email: EmailConfig(
    host: host,
    port: 587,
    username: username ?? _anySmtpUser,
    password: password ?? _anySmtpLogin,
    from: const EmailAddress(address: 'noreply@example.test'),
    allowInsecure: allowInsecure,
  ),
);

Matcher _rejects(String fragment) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(fragment)),
);

/// A server with `email` configured and no SMTP credentials used to start, and
/// then every reset and verification email failed in the background courier,
/// with nothing but a log line to show for it (reported against v0.10.2, by a
/// consumer whose release build left the credentials to the environment and
/// whose environment was missing them). An empty `JWT_SECRET` has always
/// refused to start; a mail server with no login is the same mistake.
void main() {
  group('AppConfig.validate — email credentials', () {
    test('a configured server with credentials is accepted', () {
      expect(_withEmail().validate, returnsNormally);
    });

    test('no username on a real server refuses, naming SMTP_USERNAME', () {
      expect(
        _withEmail(username: '', password: '').validate,
        _rejects('email.username is empty'),
      );
      expect(
        _withEmail(username: '', password: '').validate,
        _rejects('SMTP_USERNAME'),
      );
    });

    test('a username with no password refuses, naming SMTP_PASSWORD', () {
      expect(
        _withEmail(password: '').validate,
        _rejects('email.password is empty'),
      );
      expect(_withEmail(password: '').validate, _rejects('SMTP_PASSWORD'));
    });

    // A username with no password is never a choice: the courier logs in
    // whenever there is a username, so it would fail at every send.
    test('a username with no password refuses even on loopback', () {
      expect(
        _withEmail(host: 'localhost', password: '').validate,
        _rejects('email.password is empty'),
      );
    });

    test('an empty host refuses', () {
      expect(_withEmail(host: '').validate, _rejects('email.host is empty'));
    });

    // Mailhog, Mailpit and the like: local, no login. These must keep working.
    group('a local catcher may send without logging in', () {
      for (final host in ['localhost', '127.0.0.1', '127.0.1.1', '::1']) {
        test('on $host', () {
          expect(
            _withEmail(host: host, username: '', password: '').validate,
            returnsNormally,
          );
        });
      }

      // A catcher reached by a container name is not loopback, but it needs
      // allowInsecure, which is documented as never for a real provider.
      test('with allowInsecure, on any host', () {
        expect(
          _withEmail(
            host: 'mailhog',
            username: '',
            password: '',
            allowInsecure: true,
          ).validate,
          returnsNormally,
        );
      });
    });

    test('no email config is still fine', () {
      expect(
        AppConfig(
          appName: 'No mail',
          jwtSecret: _jwtFixture,
          passwordSecret: _pepperFixture,
        ).validate,
        returnsNormally,
      );
    });
  });
}
