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

/// The hidden preheader block, prepended to every built-in template.
///
/// Mail clients build the inbox snippet from the first text they find in the
/// body, so without this they show the greeting. The block is hidden every way
/// a client might respect -- `display:none` and `max-height:0` for most,
/// `mso-hide:all` for Outlook, `opacity`/`color:transparent` for anything that
/// strips the first two -- so it feeds the snippet and never paints.
///
/// The trailing run of zero-width joiners and non-breaking spaces is padding:
/// it fills out the rest of the snippet so the client stops there instead of
/// continuing into the visible body and tacking a button label onto the end of
/// the preview line. The `{{#preheader}}` section renders nothing at all when
/// no preheader was set.
const _preheader =
    '{{#preheader}}<div style="display:none;max-height:0;overflow:hidden;'
    'mso-hide:all;font-size:1px;line-height:1px;color:transparent;opacity:0">'
    '{{preheader}}'
    '&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;'
    '&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;'
    '&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;'
    '&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;'
    '&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;&#847;&zwnj;&nbsp;&#8203;'
    '</div>{{/preheader}}';

const _verifyEmail =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Confirm <strong>{{email}}</strong> for {{appName}}:</p>
<p><a href="{{verificationUrl}}">{{verificationUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _otpCode =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Your {{appName}} sign-in code is <strong>{{otp}}</strong>.</p>
<p>It expires in {{expiresIn}}.</p>
</body></html>
''';

const _magicLink =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Sign in to {{appName}}:</p>
<p><a href="{{magicLinkUrl}}">{{magicLinkUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _passwordReset =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Reset your {{appName}} password:</p>
<p><a href="{{passwordResetUrl}}">{{passwordResetUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _confirmChangeEmail =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Confirm changing {{currentEmail}} to {{newEmail}} on {{appName}}:</p>
<p><a href="{{confirmChangeEmailUrl}}">{{confirmChangeEmailUrl}}</a></p>
<p>This link expires in {{expiresIn}}.</p>
</body></html>
''';

const _loginNotice =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>A new sign-in to {{appName}} was detected for {{email}} at {{signedInAt}}.</p>
</body></html>
''';

const _adminInvite =
    '''
<!doctype html>
<html lang="en"><body style="font-family:sans-serif;color:#0f172a">
$_preheader
<p>{{#invitedByEmail}}{{invitedByEmail}} has invited you{{/invitedByEmail}}{{^invitedByEmail}}You've been invited{{/invitedByEmail}} to become an admin for {{appName}}, using <strong>{{email}}</strong>.</p>
<p><a href="{{inviteUrl}}">Accept invite</a></p>
<p>This link expires in {{expiresIn}}. If you weren't expecting this, you can safely ignore this email -- the invite will expire on its own.</p>
</body></html>
''';
