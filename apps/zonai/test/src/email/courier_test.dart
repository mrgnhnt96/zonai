import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/deps/courier.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/email/courier.dart' show Courier;
import 'package:zonai_logger/zonai_logger.dart';
// `hide logger`: the zonai_schema barrel re-exports a worker-side `logger`
// whose unscoped read is a silent no-op. Picking it up by accident here is
// the exact defect these tests cover -- see `courier.dart`.
import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

const _config = AppConfig(
  appName: 'Test App',
  passwordSecret: 'password-secret',
  jwtSecret: 'jwt-secret',
);

const _configuredConfig = AppConfig(
  appName: 'Test App',
  passwordSecret: 'password-secret',
  jwtSecret: 'jwt-secret',
  email: EmailConfig(
    host: 'smtp.example.com',
    port: 587,
    username: 'user',
    password: 'pass',
    from: EmailAddress(address: 'noreply@example.com'),
  ),
);

const _email = Email(
  to: EmailAddress(address: 'user@example.com'),
  subject: 'Reset your password',
  template: 'reset_password',
);

const _missingConfigWarning =
    'Cannot send email because email configuration is missing';

/// Runs [body] with a real [Logger] whose sinks are captured, plus the
/// providers `Courier` reads. Returns everything the logger wrote.
Future<String> _capturingLog(
  Future<void> Function() body, {
  required AppConfig config,
  MemoryFileSystem Function() fs = MemoryFileSystem.new,
}) async {
  final sink = _CapturingSink();

  await runScoped(
    body,
    values: {
      courierProvider.overrideWith(
        () => Courier(emailTemplatesPath: 'lib/src/email_templates'),
      ),
      configResolverProvider.overrideWith(() => ConfigResolver.fixed(config)),
      settingsProvider.overrideWith(() => fakeSettings),
      fsProvider.overrideWith(fs),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
    },
  );

  return sink.text;
}

void main() {
  group('Courier.send', () {
    // Fixed in 71114f43: a project with no `AppConfig.email` skips the send,
    // and `apps/docs/content/email/smtp-setup.md` promises a warning for it. Every caller is
    // fire-and-forget, so the log line is the *only* signal an operator gets.
    // Asserting "does not throw" would pass against a no-op logger, which is
    // how this went unnoticed from 2026-07-31 (when `9054cf0` gave the
    // wrongly-resolved worker logger a no-op fallback) to 2026-08-12.
    test('logs a warning naming the missing configuration', () async {
      final output = await _capturingLog(
        () => courier.send(_email),
        config: _config,
      );

      expect(output, contains(_missingConfigWarning));
    });

    // The import change in `courier.dart` is file-wide even though only the
    // skip branch reads a logger, so pin the configured branch too.
    test('does not warn when email is configured', () async {
      Object? error;

      final output = await _capturingLog(config: _configuredConfig, () async {
        // The configured branch renders the template before it opens an SMTP
        // connection, and the in-memory file system holds no templates -- so
        // this throws without any network I/O, which is all this test needs
        // to show the skip branch was not taken.
        try {
          await courier.send(_email);
        } on Object catch (e) {
          error = e;
        }
      });

      expect(error, isA<Exception>());
      expect('$error', contains('Email template not found'));
      expect(output, isNot(contains(_missingConfigWarning)));
    });
  });

  group('Courier.sendInBackground', () {
    // The defect that failed two Windows `cli` e2e tests on 2026-08-25 --
    // `signup_gate_e2e` and `admin_invite_runtime_e2e`, both reporting
    // `CONFIG worker failed / Process killed` against a test that had already
    // made every assertion it owns.
    //
    // Every auth flow that mails a code or a link fires the send off without
    // awaiting it, and each one used to call `send` bare. A bare future has
    // nothing listening when it completes with an error, so Dart hands that
    // error to the ambient zone -- an unhandled async error in production,
    // and under `package:test` a failure charged to whichever test is running
    // at the time.
    //
    // `runZonedGuarded` is the load-bearing part of this test. Without it the
    // escape has nowhere visible to land and a bare `send` would pass here
    // too; `escaped` is what tells the two apart.
    test('logs a failure instead of letting it escape to the zone', () async {
      final escaped = <Object>[];
      final done = Completer<void>();
      var output = '';

      runZonedGuarded(
        () async {
          // The configured branch renders the template before it opens an
          // SMTP connection, and the in-memory file system holds no
          // templates -- so the send fails with no network I/O.
          output = await _capturingLog(config: _configuredConfig, () async {
            courier.sendInBackground(_email);
            // `ConfigResolver.fixed` answers on a microtask and the render
            // throws synchronously after it, so the `catchError` is reached
            // within a couple of turns. Pumping more than that costs nothing
            // and keeps a slower host from reading as a pass-by-silence.
            for (var i = 0; i < 20; i++) {
              await Future<void>.delayed(Duration.zero);
            }
          });
          done.complete();
        },
        (error, stack) {
          escaped.add(error);
          if (!done.isCompleted) done.complete();
        },
      );

      await done.future;

      expect(
        escaped,
        isEmpty,
        reason: 'a fire-and-forget send must own its own failure',
      );
      expect(output, contains('Failed to send a'));
      // Owning the error is not the same as hiding it: the operator's only
      // signal is this line, so it has to carry the cause.
      expect(output, contains('Email template not found'));
    });
  });

  // mailer refuses a connection that is neither implicit TLS nor upgraded by
  // STARTTLS unless told otherwise -- with or without credentials. Local
  // catchers (Mailhog, the one the docs point at) offer neither, so before
  // `allowInsecure` every auth email to one failed with "connection is not
  // secure" and the docs' local setup could not deliver anything.
  group('plain SMTP', () {
    Future<({bool delivered, Object? error})> sendTo({
      required bool allowInsecure,
    }) async {
      final catcher = await _PlainSmtpCatcher.start();
      Object? error;
      try {
        await _capturingLog(
          config: AppConfig(
            appName: 'Test App',
            passwordSecret: 'password-secret',
            jwtSecret: 'jwt-secret',
            email: EmailConfig(
              host: InternetAddress.loopbackIPv4.address,
              port: catcher.port,
              username: '',
              password: '',
              from: const EmailAddress(address: 'noreply@example.com'),
              allowInsecure: allowInsecure,
            ),
          ),
          fs: () => MemoryFileSystem()
            ..directory('lib/src/email_templates').createSync(recursive: true)
            ..file(
              'lib/src/email_templates/reset_password.html',
            ).writeAsStringSync('<p>{{appName}}</p>'),
          () async {
            try {
              await courier.send(_email);
            } on Object catch (e) {
              error = e;
            }
          },
        );
      } finally {
        await catcher.close();
      }
      return (delivered: catcher.delivered, error: error);
    }

    test('delivers to a plain catcher when allowInsecure is set', () async {
      final result = await sendTo(allowInsecure: true);
      expect(result.error, isNull);
      expect(result.delivered, isTrue);
    });

    // The control: the same catcher, the default config. Without it the test
    // above would also pass against a catcher that accepts nothing at all.
    test('refuses the same catcher by default', () async {
      final result = await sendTo(allowInsecure: false);
      expect('${result.error}', contains('not secure'));
      expect(result.delivered, false);
    });
  });
}

/// Just enough SMTP to take one message: no TLS, no AUTH.
class _PlainSmtpCatcher {
  _PlainSmtpCatcher._(this._server);

  static Future<_PlainSmtpCatcher> start() async {
    final catcher = _PlainSmtpCatcher._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    catcher._server.listen(catcher._session);
    return catcher;
  }

  final ServerSocket _server;
  var delivered = false;

  int get port => _server.port;

  Future<void> _session(Socket socket) async {
    unawaited(socket.done.catchError((Object _) {}));
    void reply(String line) => socket.write('$line\r\n');
    reply('220 catcher');
    var inData = false;
    try {
      await for (final line
          in utf8.decoder.bind(socket).transform(const LineSplitter())) {
        if (inData) {
          if (line == '.') {
            inData = false;
            delivered = true;
            reply('250 OK');
          }
          continue;
        }
        switch (line.split(' ').first.toUpperCase()) {
          case 'EHLO' || 'HELO':
            reply('250 catcher');
          case 'DATA':
            inData = true;
            reply('354 go ahead');
          case 'QUIT':
            reply('221 bye');
            await socket.close();
            return;
          default:
            reply('250 OK');
        }
      }
    } on SocketException {
      // The refused case hangs up mid-conversation; that is the point.
    }
  }

  Future<void> close() => _server.close();
}
