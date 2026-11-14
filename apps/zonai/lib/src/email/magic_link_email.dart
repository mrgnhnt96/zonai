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
/// first email whichever template it used.
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
  final signIn = SendMagicLinkEmail(
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
    expiresIn: expiresIn,
  );
}

/// A magic link to an address with no account: "Create your account".
class MagicLinkSignUpEmail extends Email {
  /// Takes [signIn]'s recipient, thread and variables, and swaps the
  /// template, subject and preheader.
  MagicLinkSignUpEmail.from(
    SendMagicLinkEmail signIn, {
    required String appName,
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
       );
}
