import 'package:zonai_schema/src/types/email_address.dart';

class EmailConfig {
  const EmailConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.from,
    this.ssl = false,
  });

  factory EmailConfig.fromJson(Map<String, dynamic> json) => EmailConfig(
    host: json['host'] as String,
    port: json['port'] as int,
    username: json['username'] as String,
    password: json['password'] as String,
    from: EmailAddress.fromJson(json['from'] as Map<String, dynamic>),
    ssl: json['ssl'] as bool,
  );

  /// The SMTP server host name or IP address.
  final String host;

  /// The SMTP server port.
  final int port;

  /// The SMTP server username.
  final String username;
  final String password;

  final bool ssl;

  /// The default email address to use for the sender
  final EmailAddress from;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'from': from.toJson(),
    'ssl': ssl,
  };
}
