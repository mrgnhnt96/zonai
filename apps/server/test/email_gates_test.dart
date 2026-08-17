import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zonai/src/utils/email_template_render.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';

/// `POST /email` carried only `@BlackList()` -- an IP ban check that passes
/// everyone not already recorded as an abuser. No token, no throttle, and the
/// caller chose the recipient, the subject and the template. That is an open
/// relay sending from the product's own domain.
///
/// What this does *not* cover: the admin-token check itself, which runs
/// through `zonaiDB.parseJwt` and so needs a live database. These are the
/// gates that can be stated as functions of their inputs.
void main() {
  setUp(EmailHandler.resetRateLimits);

  group('the throttle', () {
    test('allows a normal burst and then refuses', () {
      for (var i = 0; i < 10; i++) {
        expect(
          EmailHandler.withinRateLimit('10.0.0.1'),
          isTrue,
          reason: 'request ${i + 1} is inside the limit',
        );
      }

      expect(
        EmailHandler.withinRateLimit('10.0.0.1'),
        isFalse,
        reason: 'a leaked admin token must not become a bulk sender',
      );
    });

    test('counts each client separately', () {
      for (var i = 0; i < 10; i++) {
        EmailHandler.withinRateLimit('10.0.0.1');
      }

      expect(
        EmailHandler.withinRateLimit('10.0.0.2'),
        isTrue,
        reason: 'one noisy client must not lock everyone else out',
      );
    });

    test('lets the window roll over', () {
      final start = DateTime.utc(2026, 1, 1, 12);

      withClock(Clock.fixed(start), () {
        for (var i = 0; i < 10; i++) {
          EmailHandler.withinRateLimit('10.0.0.1');
        }
        expect(EmailHandler.withinRateLimit('10.0.0.1'), isFalse);
      });

      withClock(
        Clock.fixed(start.add(const Duration(minutes: 1, seconds: 1))),
        () {
          expect(EmailHandler.withinRateLimit('10.0.0.1'), isTrue);
        },
      );
    });
  });

  group('the recipient allow-list', () {
    test('is empty when unset, meaning the admin token is the control', () {
      expect(EmailHandler.parseAllowedRecipients(null), isEmpty);
      expect(EmailHandler.parseAllowedRecipients('   '), isEmpty);
    });

    test('parses a comma-separated list, case-insensitively', () {
      expect(
        EmailHandler.parseAllowedRecipients(
          'Ops@example.com, alerts@example.com',
        ),
        {'ops@example.com', 'alerts@example.com'},
      );
    });
  });

  group('the template gate', () {
    test('refuses a traversing template name before any mail is sent', () {
      // The same check renderEmailTemplate makes, applied early so a hostile
      // name never reaches an SMTP connection.
      expect(isValidEmailTemplateName('../../../../etc/hosts'), isFalse);
      expect(isValidEmailTemplateName('otp_code'), isTrue);
    });
  });
}
