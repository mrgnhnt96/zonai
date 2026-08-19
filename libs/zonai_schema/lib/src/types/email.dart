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
    this.preheader,
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
    preheader: json['preheader'] as String?,
  );

  final EmailAddress to;
  final EmailAddress? from;
  final String subject;

  /// The name of the template file (without the .html extension)
  final String template;
  final Map<String, dynamic> variables;

  /// The inbox preview line, shown by mail clients next to the subject.
  ///
  /// Rendered into the template as `{{preheader}}` inside a hidden block, so it
  /// never paints in the message body. Without it the client scrapes whatever
  /// visible text comes first -- usually the greeting -- which says nothing.
  final String? preheader;

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
    'preheader': ?preheader,
  };
}

class SendOtpEmail extends Email {
  SendOtpEmail({
    required super.to,
    required String table,
    super.from,
    bool isResend = false,
    String subject = 'Your confirmation code',
    required String code,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
    String? preheader,
  }) : super(
         subject: subject,
         template: 'otp_code',
         // Deliberately excludes the code itself: the preheader is what shows
         // on a locked phone, and a sign-in code does not belong there.
         preheader:
             preheader ??
             'Your sign-in code expires in ${expiresIn.inMinutes} minutes.',
         thread: Email.createThread(
           'otp:$table:${to.address.toLowerCase()}',
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
    required String table,
    super.from,
    String subject = 'Sign in',
    bool isResend = false,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
    required String magicLinkUrl,
    String? preheader,
  }) : super(
         subject: subject,
         template: 'magic_link',
         preheader:
             preheader ??
             'Your sign-in link expires in ${expiresIn.inMinutes} minutes.',
         thread: Email.createThread(
           'magic-link:$table:${to.address.toLowerCase()}',
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
    required String table,
    super.from,
    required String verificationUrl,
    required Duration expiresIn,
    Map<String, dynamic>? variables,
    String subject = 'Verify your email',
    String? preheader,
  }) : super(
         subject: subject,
         template: 'verify_email',
         preheader:
             preheader ??
             'Confirm ${to.address} to finish setting up your account.',
         thread: Email.createThread(
           'verify-email:$table:${to.address.toLowerCase()}',
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

class SendAdminInviteEmail extends Email {
  SendAdminInviteEmail({
    required super.to,
    required String table,
    super.from,
    bool isResend = false,
    required String inviteUrl,
    required Duration expiresIn,
    String? invitedByEmail,
    Map<String, dynamic>? variables,
    String subject = "You've been invited as an admin",
    String? preheader,
  }) : super(
         subject: subject,
         template: 'admin_invite',
         preheader:
             preheader ??
             'Your invite expires in ${_formatExpiresIn(expiresIn)}.',
         thread: Email.createThread(
           'admin-invite:$table:${to.address.toLowerCase()}',
           continueThread: isResend,
         ),
         variables: {
           ...?variables,
           'inviteUrl': inviteUrl,
           'email': to.address,
           'expiresIn': _formatExpiresIn(expiresIn),
           if (invitedByEmail != null) 'invitedByEmail': invitedByEmail,
         },
       );

  static String _formatExpiresIn(Duration expiresIn) {
    if (expiresIn.inDays >= 1 && expiresIn.inHours % 24 == 0) {
      final days = expiresIn.inDays;
      return days == 1 ? '1 day' : '$days days';
    }
    final hours = expiresIn.inHours;
    return hours == 1 ? '1 hour' : '$hours hours';
  }
}

class SendResetPasswordEmail extends Email {
  SendResetPasswordEmail({
    required super.to,
    required String table,
    super.from,
    required String passwordResetUrl,
    required Duration expiresIn,
    String? name,
    Map<String, dynamic>? variables,
    String subject = 'Reset Password',
    String? preheader,
  }) : super(
         subject: subject,
         template: 'password_reset',
         preheader:
             preheader ??
             'Your reset link expires in ${expiresIn.inMinutes} minutes.',
         thread: Email.createThread(
           'reset-password:$table:${to.address.toLowerCase()}',
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
