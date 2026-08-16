/// Built-in Mustache email templates created during project initialization.
const initEmailTemplates = <String, String>{
  'verify_email': _verifyEmail,
  'otp_code': _otpCode,
  'magic_link': _magicLink,
  'password_reset': _passwordReset,
  'confirm_change_email': _confirmChangeEmail,
  'login_notice': _loginNotice,
  'admin_invite': _adminInvite,
};

const _verifyEmail = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Confirm <strong>{{email}}</strong> for {{appName}}:</p>
<p><a href="{{verificationUrl}}">{{verificationUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _otpCode = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Your {{appName}} sign-in code is <strong>{{otp}}</strong>.</p>
<p>It expires in {{expiresIn}}.</p>
</body></html>
''';

const _magicLink = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Sign in to {{appName}}:</p>
<p><a href="{{magicLinkUrl}}">{{magicLinkUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _passwordReset = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Reset your {{appName}} password:</p>
<p><a href="{{passwordResetUrl}}">{{passwordResetUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _confirmChangeEmail = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Confirm changing {{currentEmail}} to {{newEmail}} on {{appName}}:</p>
<p><a href="{{confirmChangeEmailUrl}}">{{confirmChangeEmailUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _loginNotice = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>A new sign-in to {{appName}} was detected for {{email}} at {{signedInAt}}.</p>
</body></html>
''';

const _adminInvite = '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
<p>{{#invitedByEmail}}{{invitedByEmail}} has invited you{{/invitedByEmail}}{{^invitedByEmail}}You've been invited{{/invitedByEmail}} to become an admin for {{appName}}, using <strong>{{email}}</strong>.</p>
<p><a href="{{inviteUrl}}">Accept invite</a></p>
<p>This link expires in {{expiresIn}}. If you weren't expecting this, you can safely ignore this email -- the invite will expire on its own.</p>
</body></html>
''';
