import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  const to = EmailAddress(address: 'client@example.com');

  group('Email reply fields', () {
    test('round-trip through JSON', () {
      final email = Email(
        to: to,
        subject: 'Re: Your booking',
        template: 'reply',
        replyTo: const EmailAddress(address: 'inbox@app.test', name: 'App'),
        messageId: '<ours@app.test>',
        inReplyTo: '<theirs@mail.example.com>',
        references: const ['<first@app.test>', '<theirs@mail.example.com>'],
        text: 'Thanks, see you Thursday.',
      );

      final decoded = Email.fromJson(email.toJson());

      expect(decoded.replyTo?.address, 'inbox@app.test');
      expect(decoded.replyTo?.name, 'App');
      expect(decoded.messageId, '<ours@app.test>');
      expect(decoded.inReplyTo, '<theirs@mail.example.com>');
      expect(decoded.references, [
        '<first@app.test>',
        '<theirs@mail.example.com>',
      ]);
      expect(decoded.text, 'Thanks, see you Thursday.');
    });

    test('are omitted from JSON when unset', () {
      final json = Email(to: to, subject: 'S', template: 't').toJson();

      for (final key in [
        'replyTo',
        'messageId',
        'inReplyTo',
        'references',
        'text',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(Email.fromJson(json).references, isEmpty);
    });

    // `Email` is also the body of the client's `email.send` route, and an id
    // that is written into a header must not be able to start a new one.
    test('fromJson refuses a message-id that could break the header', () {
      final json = {
        ...Email(to: to, subject: 'S', template: 't').toJson(),
        'inReplyTo': '<a@b>\r\nBcc: victim@example.com',
      };

      expect(() => Email.fromJson(json), throwsA(isA<InvalidBodyException>()));
    });
  });

  group('Email.messageIdHeader', () {
    test('adds angle brackets when they are left off', () {
      expect(Email.messageIdHeader('abc@example.com'), '<abc@example.com>');
      expect(Email.messageIdHeader('<abc@example.com>'), '<abc@example.com>');
    });

    for (final bad in [
      'no-at-sign',
      '@example.com',
      'abc@',
      'a b@example.com',
      'abc@example.com\r\nX-Evil: 1',
      '<abc@example.com',
      '<<abc@example.com>>',
    ]) {
      test('refuses ${bad.replaceAll('\r\n', r'\r\n')}', () {
        expect(() => Email.messageIdHeader(bad), throwsArgumentError);
      });
    }
  });

  group('Email.createMessageId', () {
    test('is on the domain of the address it is given', () {
      expect(
        Email.createMessageId('hello@lovehaymay.com'),
        matches(RegExp(r'^<[^@<>\s]+@lovehaymay\.com>$')),
      );
    });

    test('takes a bare domain', () {
      expect(Email.createMessageId('example.com'), endsWith('@example.com>'));
    });

    test('is a valid header value and unique per call', () {
      final ids = {for (var i = 0; i < 100; i++) Email.createMessageId('x.io')};

      expect(ids, hasLength(100));
      for (final id in ids) {
        expect(Email.messageIdHeader(id), id);
      }
    });

    test('refuses something that is not an address or a domain', () {
      expect(() => Email.createMessageId('a@'), throwsArgumentError);
      expect(() => Email.createMessageId('a b'), throwsArgumentError);
    });
  });
}
