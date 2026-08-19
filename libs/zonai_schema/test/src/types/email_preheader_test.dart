import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('Email.preheader', () {
    test('round-trips through JSON', () {
      final email = Email(
        to: EmailAddress(address: 'user@example.com'),
        subject: 'Subject',
        template: 'verify_email',
        preheader: 'Confirm your address to finish signing up.',
      );

      final decoded = Email.fromJson(email.toJson());

      expect(decoded.preheader, 'Confirm your address to finish signing up.');
    });

    test('is omitted from JSON when unset', () {
      final email = Email(
        to: EmailAddress(address: 'user@example.com'),
        subject: 'Subject',
        template: 'verify_email',
      );

      expect(email.toJson().containsKey('preheader'), isFalse);
      expect(Email.fromJson(email.toJson()).preheader, isNull);
    });
  });

  group('built-in emails carry a default preheader', () {
    final to = EmailAddress(address: 'user@example.com');

    test('SendOtpEmail states the expiry and never the code', () {
      final email = SendOtpEmail(
        to: to,
        table: 'users',
        code: '123456',
        expiresIn: const Duration(minutes: 10),
      );

      expect(email.preheader, 'Your sign-in code expires in 10 minutes.');
      // The preheader is what shows on a locked phone. The code must not.
      expect(email.preheader, isNot(contains('123456')));
    });

    test('SendMagicLinkEmail states the expiry', () {
      final email = SendMagicLinkEmail(
        to: to,
        table: 'users',
        expiresIn: const Duration(minutes: 15),
        magicLinkUrl: 'https://example.com/magic',
      );

      expect(email.preheader, 'Your sign-in link expires in 15 minutes.');
    });

    test('SendVerifyEmailEmail names the address being confirmed', () {
      final email = SendVerifyEmailEmail(
        to: to,
        table: 'users',
        verificationUrl: 'https://example.com/verify',
        expiresIn: const Duration(hours: 1),
      );

      expect(email.preheader, contains('user@example.com'));
    });

    test('SendResetPasswordEmail states the expiry', () {
      final email = SendResetPasswordEmail(
        to: to,
        table: 'users',
        passwordResetUrl: 'https://example.com/reset',
        expiresIn: const Duration(minutes: 30),
      );

      expect(email.preheader, 'Your reset link expires in 30 minutes.');
    });

    test('SendAdminInviteEmail states the expiry', () {
      final email = SendAdminInviteEmail(
        to: to,
        table: 'users',
        inviteUrl: 'https://example.com/invite',
        expiresIn: const Duration(days: 3),
      );

      expect(email.preheader, 'Your invite expires in 3 days.');
    });

    test('an explicit preheader overrides the default', () {
      final email = SendOtpEmail(
        to: to,
        table: 'users',
        code: '123456',
        expiresIn: const Duration(minutes: 10),
        preheader: 'Custom preview line.',
      );

      expect(email.preheader, 'Custom preview line.');
    });
  });
}
