import 'package:zonai_schema/src/types/email_address.dart';

class EmailConfig {
  const EmailConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.from,
    this.ssl = false,
    this.allowInsecure = false,
  });

  factory EmailConfig.fromJson(Map<String, dynamic> json) => EmailConfig(
    host: json['host'] as String,
    port: json['port'] as int,
    username: json['username'] as String,
    password: json['password'] as String,
    from: EmailAddress.fromJson(json['from'] as Map<String, dynamic>),
    ssl: json['ssl'] as bool,
    allowInsecure: json['allowInsecure'] as bool? ?? false,
  );

  /// The SMTP server host name or IP address.
  final String host;

  /// The SMTP server port.
  final int port;

  /// The SMTP server username.
  final String username;
  final String password;

  final bool ssl;

  /// Sends even when the connection is not encrypted.
  ///
  /// Off by default, and meant only for a local catcher such as Mailhog:
  /// those speak plain SMTP, with neither implicit TLS ([ssl]) nor STARTTLS.
  /// Without this the mail library refuses them before sending anything,
  /// credentials or not, and every auth email fails with "connection is not
  /// secure".
  ///
  /// Never turn it on for a real provider. With it on, a server that stops
  /// offering STARTTLS gets the credentials and the mail in plain text.
  final bool allowInsecure;

  /// The default email address to use for the sender
  final EmailAddress from;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'from': from.toJson(),
    'ssl': ssl,
    'allowInsecure': allowInsecure,
  };
}
