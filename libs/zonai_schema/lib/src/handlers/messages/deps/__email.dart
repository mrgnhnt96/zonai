part of '../message_handler.dart';

typedef _SendEmailFn = void Function(Email email);
typedef _SendBuiltInEmailFn =
    void Function(
      BuiltInEmails email,
      EmailAddress to,
      Map<String, dynamic>? variables,
    );

final _emailProvider = create<_Email>(_Email._);

_Email get email => read(_emailProvider);

class _Email {
  _Email._() {
    send = _SendEmail((_) {}, (_, _, _) {});
  }
  _Email(_SendEmailFn send, _SendBuiltInEmailFn sendBuiltIn)
    : send = _SendEmail(send, sendBuiltIn);

  late final _SendEmail send;
}

class _SendEmail {
  const _SendEmail(this._fn, this._sendBuiltIn);

  final _SendEmailFn _fn;
  final _SendBuiltInEmailFn _sendBuiltIn;

  void call(Email email) => _fn(email);

  void confirmEmailChange(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.confirmEmailChange, to, variables);
  }

  void verifyEmail(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.verifyEmail, to, variables);
  }

  void passwordReset(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.passwordReset, to, variables);
  }

  void optCode(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.optCode, to, variables);
  }

  void magicLink(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.magicLink, to, variables);
  }

  void loginNotice(EmailAddress to, {Map<String, dynamic>? variables}) {
    _sendBuiltIn(.loginNotice, to, variables);
  }
}
