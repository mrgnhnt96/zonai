import 'dart:convert';

import 'package:zonai_schema/src/types/email_address.dart';

class Email {
  const Email({
    required this.to,
    required this.subject,
    required this.template,
    this.variables = const {},
    this.from,
  });

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    to: EmailAddress.fromJson(json['to'] as Map<String, dynamic>),
    from: json['from'] != null
        ? EmailAddress.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    subject: json['subject'] as String,
    template: json['template'] as String,
    variables: json['variables'] as Map<String, dynamic>,
  );

  final EmailAddress to;
  final EmailAddress? from;
  final String subject;

  /// The name of the template file (without the .html extension)
  final String template;
  final Map<String, dynamic> variables;

  Map<String, dynamic> toJson() => {
    'to': to.toJson(),
    'from': from?.toJson(),
    'subject': subject,
    'template': template,
    'variables': jsonDecode(jsonEncode(variables)),
  };
}
