import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show AuthOperation;
import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../utils/email_template_render.dart';

/// The template a magic link to an address with no account uses, when the
/// app has one.
const kMagicLinkSignUpTemplate = 'magic_link_sign_up';

/// The magic-link email for [operation].
///
/// A sign-up -- a link to an address with no account yet -- uses
/// [kMagicLinkSignUpTemplate] with a "Create your account" subject, so a new
/// user is not told to sign in to an account they do not have. The template
/// is optional: an app that has not added `magic_link_sign_up.html` gets the
/// sign-in email exactly as before, rather than a send that fails on a
/// missing file. A sign-in always gets the sign-in email.
///
/// Both carry the same variables and thread, so a resend threads onto the
/// first email whichever template it used, and both carry a plain-text part
/// (see [magicLinkPlainText]).
Email magicLinkEmail({
  required AuthOperation operation,
  required String appName,
  required EmailAddress to,
  required String table,
  required bool isResend,
  required String magicLinkUrl,
  required Duration expiresIn,
  Map<String, dynamic>? variables,
  String? emailTemplatesPath,
}) {
  final signIn = MagicLinkSignInEmail(
    appName: appName,
    to: to,
    table: table,
    isResend: isResend,
    magicLinkUrl: magicLinkUrl,
    expiresIn: expiresIn,
    variables: variables,
  );

  if (operation != AuthOperation.signUp) return signIn;

  final hasSignUpTemplate = emailTemplateExists(
    kMagicLinkSignUpTemplate,
    emailTemplatesPath: emailTemplatesPath,
  );
  if (!hasSignUpTemplate) return signIn;

  return MagicLinkSignUpEmail.from(
    signIn,
    appName: appName,
    magicLinkUrl: magicLinkUrl,
    expiresIn: expiresIn,
  );
}

/// The plain-text part of a magic-link email: the greeting, [action] (such as
/// "Sign in to Picto"), the link written out, and when it expires.
///
/// It mirrors the built-in HTML templates. Without it the mail goes out
/// text/html only, which spam filters score against it (`MIME_HTML_ONLY`,
/// and with a short body plus a tracking pixel `HTML_IMAGE_ONLY_08`). The
/// preheader is left out on purpose -- see [Email.text].
String magicLinkPlainText({
  required String action,
  required String magicLinkUrl,
  required Duration expiresIn,
  Map<String, dynamic>? variables,
}) {
  final greeting = switch (variables?['name']) {
    final String name when name.trim().isNotEmpty => 'Hi ${name.trim()},',
    _ => 'Hi,',
  };

  return '$greeting\n'
      '\n'
      '$action:\n'
      '$magicLinkUrl\n'
      '\n'
      'This link expires in ${expiresIn.inMinutes} minutes.\n';
}

/// The sign-in magic-link email, with a plain-text part.
///
/// Still a [SendMagicLinkEmail] -- same template, subject, preheader, thread
/// and variables -- so code that looks for one finds it.
class MagicLinkSignInEmail extends SendMagicLinkEmail {
  MagicLinkSignInEmail({
    required String appName,
    required super.to,
    required super.table,
    required super.isResend,
    required super.magicLinkUrl,
    required super.expiresIn,
    super.variables,
  }) : _text = magicLinkPlainText(
         action: 'Sign in to $appName',
         magicLinkUrl: magicLinkUrl,
         expiresIn: expiresIn,
         variables: variables,
       );

  final String _text;

  // `SendMagicLinkEmail` takes no `text`, so the plain-text part is supplied
  // by overriding the getter.
  @override
  String get text => _text;
}

/// A magic link to an address with no account: "Create your account".
class MagicLinkSignUpEmail extends Email {
  /// Takes [signIn]'s recipient, thread and variables, and swaps the
  /// template, subject, preheader and plain-text part.
  MagicLinkSignUpEmail.from(
    SendMagicLinkEmail signIn, {
    required String appName,
    required String magicLinkUrl,
    required Duration expiresIn,
  }) : super(
         to: signIn.to,
         from: signIn.from,
         subject: 'Create your $appName account',
         template: kMagicLinkSignUpTemplate,
         preheader:
             'Your link to create your account expires in '
             '${expiresIn.inMinutes} minutes.',
         thread: signIn.thread,
         variables: signIn.variables,
         text: magicLinkPlainText(
           action: 'Create your $appName account',
           magicLinkUrl: magicLinkUrl,
           expiresIn: expiresIn,
           variables: signIn.variables,
         ),
       );
}
