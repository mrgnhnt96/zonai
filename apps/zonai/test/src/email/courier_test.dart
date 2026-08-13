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
      fsProvider.overrideWith(MemoryFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
    },
  );

  return sink.text;
}

void main() {
  group('Courier.send', () {
    // known-issues.md #10: a project with no `AppConfig.email` skips the send,
    // and `docs/email.md` promises a warning for it. Every caller is
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
}
