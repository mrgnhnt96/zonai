import 'dart:convert';
import 'dart:math';

import 'package:zonai_schema/src/types/email_address.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';

class Email {
  const Email({
    required this.to,
    required this.subject,
    required this.template,
    this.variables = const {},
    this.from,
    this.thread,
    this.preheader,
    this.replyTo,
    this.messageId,
    this.inReplyTo,
    this.references = const [],
    this.text,
  });

  /// Builds a [Email.thread] id. Pass [continueThread] when sending another message
  /// in the same conversation.
  static String createThread(String id, {bool continueThread = false}) =>
      continueThread ? '$id$continueThreadSuffix' : id;

  static const String continueThreadSuffix = ':continue';

  /// Builds a fresh [Email.messageId] on [from]'s domain.
  ///
  /// [from] is the address the mail goes out from (`hello@example.com`) or
  /// just its domain (`example.com`). Generate the id before sending and store
  /// it: `email.send` does not report back, and a reply to this message will
  /// name it in its own `In-Reply-To`.
  static String createMessageId(String from) {
    final at = from.lastIndexOf('@');
    final domain = at < 0 ? from : from.substring(at + 1);
    if (domain.isEmpty || !_messageIdPart.hasMatch(domain)) {
      throw ArgumentError.value(from, 'from', 'must be an email or a domain');
    }
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '<$time.$random@$domain>';
  }

  /// [id] as it goes in a `Message-ID`, `In-Reply-To` or `References` header:
  /// wrapped in angle brackets, which a caller may leave off.
  ///
  /// Throws when [id] is not `local@domain`. The ids an app passes here often
  /// come from someone else's mail (an inbound `Message-ID`), so anything
  /// that could break out of the header -- whitespace, a line break, a stray
  /// bracket -- is refused rather than written.
  static String messageIdHeader(String id) {
    final bare = id.startsWith('<') && id.endsWith('>')
        ? id.substring(1, id.length - 1)
        : id;
    final at = bare.lastIndexOf('@');
    if (at <= 0 ||
        !_messageIdPart.hasMatch(bare.substring(0, at)) ||
        !_messageIdPart.hasMatch(bare.substring(at + 1))) {
      throw ArgumentError.value(id, 'messageId', 'must be <local@domain>');
    }
    return '<$bare>';
  }

  static final _messageIdPart = RegExp(r'^[^\s<>@]+$');
  static final _random = Random.secure();

  factory Email.fromJson(Map<String, dynamic> json) =>
      parseBody('Email', () => Email._fromJson(json));

  factory Email._fromJson(Map<String, dynamic> json) => Email(
    to: EmailAddress.fromJson(json['to'] as Map<String, dynamic>),
    from: json['from'] != null
        ? EmailAddress.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    subject: json['subject'] as String,
    template: json['template'] as String,
    variables: json['variables'] as Map<String, dynamic>,
    thread: json['thread'] as String?,
    preheader: json['preheader'] as String?,
    replyTo: json['replyTo'] != null
        ? EmailAddress.fromJson(json['replyTo'] as Map<String, dynamic>)
        : null,
    // Checked here as well as at send time, so a bad id from an HTTP client
    // is a 400 rather than a send that fails in the background.
    messageId: _checkedMessageId(json['messageId'] as String?),
    inReplyTo: _checkedMessageId(json['inReplyTo'] as String?),
    references: [
      for (final id in json['references'] as List? ?? const [])
        _checkedMessageId(id as String)!,
    ],
    text: json['text'] as String?,
  );

  static String? _checkedMessageId(String? id) {
    if (id != null) messageIdHeader(id);
    return id;
  }

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

  /// Where replies go, when that is not [from].
  final EmailAddress? replyTo;

  /// This message's own `Message-ID`, so the app can store it and recognise
  /// a later reply by its `In-Reply-To`.
  ///
  /// Build one with [createMessageId]. Left unset, Zonai picks it: the
  /// [thread] header when there is a thread, otherwise the mail library's.
  final String? messageId;

  /// The `Message-ID` of the message this one answers -- any message, such as
  /// one a client sent the app.
  ///
  /// Setting this or [references] replaces the `In-Reply-To` and
  /// `References` that [thread] would set. Angle brackets are optional.
  final String? inReplyTo;

  /// The `Message-ID`s of the conversation so far, oldest first.
  ///
  /// When empty and [inReplyTo] is set, `References` is just [inReplyTo].
  /// When set without [inReplyTo], `In-Reply-To` is the last one.
  final List<String> references;

  /// A plain-text alternative to the HTML [template], sent as-is.
  ///
  /// It is not rendered against [variables] and [preheader] is not added to
  /// it: the preheader is already the inbox snippet through the HTML, and a
  /// client that prefers the text part would show it twice.
  final String? text;

  Map<String, dynamic> toJson() => {
    'to': to.toJson(),
    'from': from?.toJson(),
    'subject': subject,
    'template': template,
    'variables': jsonDecode(jsonEncode(variables)),
    'thread': ?thread,
    'preheader': ?preheader,
    'replyTo': ?replyTo?.toJson(),
    'messageId': ?messageId,
    'inReplyTo': ?inReplyTo,
    if (references.isNotEmpty) 'references': references,
    'text': ?text,
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
