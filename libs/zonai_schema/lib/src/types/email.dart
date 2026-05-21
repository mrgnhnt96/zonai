import 'dart:convert';

import 'package:zonai_schema/src/types/email_address.dart';

class Email {
  const Email({
    required this.to,
    required this.subject,
    required this.template,
    this.variables = const {},
    this.from,
    this.thread,
  });

  /// Builds a [Email.thread] id. Pass [continueThread] when sending another message
  /// in the same conversation.
  static String createThread(String id, {bool continueThread = false}) =>
      continueThread ? '$id$continueThreadSuffix' : id;

  static const String continueThreadSuffix = ':continue';

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    to: EmailAddress.fromJson(json['to'] as Map<String, dynamic>),
    from: json['from'] != null
        ? EmailAddress.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    subject: json['subject'] as String,
    template: json['template'] as String,
    variables: json['variables'] as Map<String, dynamic>,
    thread: json['thread'] as String?,
  );

  final EmailAddress to;
  final EmailAddress? from;
  final String subject;

  /// The name of the template file (without the .html extension)
  final String template;
  final Map<String, dynamic> variables;

  /// Groups this message with earlier mail that used the same thread id.
  ///
  /// Use [createThread] to build the value. Append a continuation for follow-ups
  /// (e.g. another OTP) by passing `continueThread: true`.
  final String? thread;

  Map<String, dynamic> toJson() => {
    'to': to.toJson(),
    'from': from?.toJson(),
    'subject': subject,
    'template': template,
    'variables': jsonDecode(jsonEncode(variables)),
    'thread': ?thread,
  };
}

class SendOtpEmail extends Email {
  SendOtpEmail({
    required super.to,
    required String collection,
    super.from,
    bool isResend = false,
    required String code,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
  }) : super(
         subject: 'Otp Code',
         template: 'otp_code',
         thread: Email.createThread(
           'otp:$collection:${to.address.toLowerCase()}',
           continueThread: isResend,
         ),
         variables: {
           ...?variables,
           'otp': code,
           'email': to.address,
           'expiresIn': '${expiresIn.inMinutes} minutes',
         },
       );
}

class SendMagicLinkEmail extends Email {
  SendMagicLinkEmail({
    required super.to,
    required String collection,
    super.from,
    bool isResend = false,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
    required String magicLinkUrl,
  }) : super(
         subject: 'Sign in',
         template: 'magic_link',
         thread: Email.createThread(
           'magic-link:$collection:${to.address.toLowerCase()}',
           continueThread: isResend,
         ),
         variables: {
           ...?variables,
           'magicLinkUrl': magicLinkUrl,
           'email': to.address,
           'expiresIn': '${expiresIn.inMinutes} minutes',
         },
       );
}

class SendVerifyEmailEmail extends Email {
  SendVerifyEmailEmail({
    required super.to,
    required String collection,
    super.from,
    required String verificationUrl,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
  }) : super(
         subject: 'Verify your email',
         template: 'verify_email',
         thread: Email.createThread(
           'verify-email:$collection:${to.address.toLowerCase()}',
         ),
         variables: {
           ...?variables,
           'verificationUrl': verificationUrl,
           'email': to.address,
           'expiresIn': _formatExpiresIn(expiresIn),
         },
       );

  static String _formatExpiresIn(Duration expiresIn) {
    if (expiresIn.inHours >= 1 && expiresIn.inMinutes % 60 == 0) {
      final hours = expiresIn.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final minutes = expiresIn.inMinutes;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }
}

class SendResetPasswordEmail extends Email {
  SendResetPasswordEmail({
    required super.to,
    required String collection,
    super.from,
    required String passwordResetUrl,
    required Duration expiresIn,
    String? name,
    Map<String, dynamic>? variables,
  }) : super(
         subject: 'Reset Password',
         template: 'password_reset',
         thread: Email.createThread(
           'reset-password:$collection:${to.address.toLowerCase()}',
         ),
         variables: {
           ...?variables,
           'name': name,
           'passwordResetUrl': passwordResetUrl,
           'email': to.address,
           'expiresIn': '${expiresIn.inMinutes} minutes',
         },
       );
}
