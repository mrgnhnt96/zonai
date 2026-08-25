import 'dart:async';
import 'dart:convert';

import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/mailer.dart';
// `hide logger`: the barrel re-exports the worker-side `logger` from
// `message_handler.dart`, which falls back to a no-op outside a worker scope.
// Picking it up here made the missing-config warning below silent on the host.
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:mailer/smtp_server.dart';

import '../deps/logger.dart';
import '../utils/email_template_render.dart';

class Courier {
  Courier({String? emailTemplatesPath})
    : emailTemplatesPath = emailTemplatesPath ?? settings.emailTemplatesPath,
      send = _Send();

  final String emailTemplatesPath;

  final _Send send;

  /// Sends [email] without waiting for it, and without letting a failure
  /// escape to the ambient zone.
  ///
  /// Every auth flow that mails a code or a link fires the send off rather
  /// than awaiting it -- the operator's signal is the log line the failure
  /// writes, never the future -- and each one used to call [send] bare. A
  /// bare fire-and-forget future has nothing listening when it completes
  /// with an error, and Dart delivers that to the ambient zone: an
  /// unhandled async error in production, and under `package:test` a
  /// failure charged to whichever test happens to be running.
  ///
  /// That is how this was found. [send] resolves the app config through the
  /// CONFIG worker before it can reach SMTP, so a host disposed while a send
  /// is still in flight kills that worker out from under it
  /// (`WorkerProcessFailedException: CONFIG worker failed / Process
  /// killed`). On 2026-08-25 that failed two Windows `cli` e2e tests --
  /// `signup_gate_e2e` and `admin_invite_runtime_e2e` -- which had already
  /// made and passed every assertion they own. The slower the host, the
  /// wider the window, which is why only the Windows leg saw it.
  ///
  /// Callers that want to know whether the mail actually went out must
  /// `await send` instead; this is only for the paths that deliberately do
  /// not.
  void sendInBackground(Email email) {
    unawaited(
      send(email).catchError((Object error, StackTrace stack) {
        logger.error('Failed to send a ${email.runtimeType}', error, stack);
      }),
    );
  }
}

class _Send {
  const _Send();

  Future<void> call(Email email) => _send(email);

  Future<void> _send(Email email) async {
    final config = await configResolver.resolve();

    final emailConfig = config.email;
    if (emailConfig == null) {
      logger.warn('Cannot send email because email configuration is missing');
      return;
    }

    final message = Message()
      ..from = Address(
        email.from?.address ?? emailConfig.from.address,
        email.from?.name ?? emailConfig.from.name ?? config.appName,
      )
      ..recipients.add(Address(email.to.address, email.to.name))
      ..subject = email.subject
      // HTML only -- no `..text`, so this is not multipart/alternative. If a
      // plaintext alternative is ever added, `Email.preheader` must stay OUT of
      // it: it is already the inbox snippet via the hidden block in the HTML,
      // and clients that prefer the text part would then show it twice.
      ..html = _EmailContent(email, config).html();

    final fromAddress = email.from?.address ?? emailConfig.from.address;
    _applyThreadHeaders(message, email, fromAddress);

    final smtp = SmtpServer(
      emailConfig.host,
      port: emailConfig.port,
      username: emailConfig.username,
      password: emailConfig.password,
      ssl: emailConfig.ssl,
    );

    await mailer.send(message, smtp);
  }

  void _applyThreadHeaders(Message message, Email email, String fromAddress) {
    final thread = email.thread;
    if (thread == null) return;

    final continues = thread.endsWith(Email.continueThreadSuffix);
    final threadId = continues
        ? thread.substring(0, thread.length - Email.continueThreadSuffix.length)
        : thread;
    final root = _threadRootMessageId(
      thread: threadId,
      fromAddress: fromAddress,
    );

    if (continues) {
      message.headers['Message-ID'] = _sendMessageId(fromAddress);
      message.headers['In-Reply-To'] = root;
      message.headers['References'] = root;
    } else {
      message.headers['Message-ID'] = root;
    }
  }

  String _threadRootMessageId({
    required String thread,
    required String fromAddress,
  }) {
    final domain = _emailDomain(fromAddress);
    final tag = base64Url.encode(utf8.encode(thread)).replaceAll('=', '');
    return '<thread.$tag@$domain>';
  }

  String _sendMessageId(String fromAddress) {
    final domain = _emailDomain(fromAddress);
    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '<thread.send.$unique@$domain>';
  }

  String _emailDomain(String address) {
    final at = address.lastIndexOf('@');
    if (at < 0 || at == address.length - 1) {
      throw ArgumentError.value(
        address,
        'fromAddress',
        'must be a valid email',
      );
    }
    return address.substring(at + 1);
  }
}

class _EmailContent {
  const _EmailContent(this.email, this.config);
  final Email email;
  final AppConfig config;

  String html() => renderEmailTemplate(
    templateName: email.template,
    variables: email.variables,
    appName: config.appName,
    emailTemplatesPath: settings.emailTemplatesPath,
    preheader: email.preheader,
  );
}
