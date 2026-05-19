import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:mustache_template/mustache_template.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/mailer.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:mailer/smtp_server.dart';

class Courier {
  Courier({String? emailTemplatesPath})
    : emailTemplatesPath = emailTemplatesPath ?? settings.emailTemplatesPath;

  final String emailTemplatesPath;

  Future<void> send(Email email) async {
    final config = await configResolver.resolve();

    final emailConfig = config.email;
    if (emailConfig == null) {
      throw Exception('Missing email configuration with $AppConfig');
    }

    final message = Message()
      ..from = Address(
        email.from?.address ?? emailConfig.from.address,
        email.from?.name ?? emailConfig.from.name ?? config.appName,
      )
      ..recipients.add(Address(email.to.address, email.to.name))
      ..subject = email.subject
      ..html = _EmailContent(email, config).html;

    final smtp = SmtpServer(
      emailConfig.host,
      port: emailConfig.port,
      username: emailConfig.username,
      password: emailConfig.password,
      ssl: emailConfig.ssl,
    );

    await mailer.send(message, smtp);
  }
}

class _EmailContent {
  const _EmailContent(this.email, this.config);
  final Email email;
  final AppConfig config;

  String get html {
    final file = fs.file(
      fs.path.join(settings.emailTemplatesPath, '${email.template}.html'),
    );

    if (!file.existsSync()) {
      throw Exception('Eamil template file not found: ${file.path}');
    }

    final source = file.readAsStringSync();
    return Template(
      source,
      name: email.template,
    ).renderString({...email.variables, 'appName': config.appName});
  }
}
