part of '../message_handler.dart';

typedef _SendEmailFn = void Function(Email email);
typedef _SendBuiltInEmailFn =
    void Function(
      BuiltInEmails email,
      EmailAddress to,
      String collection,
      Map<String, dynamic>? variables,
    );

final _emailProvider = create<_Email>(_Email._);

_Email get email => read(_emailProvider);

class _Email {
  _Email._() {
    send = _SendEmail((_) {}, (_, _, _, _) {});
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

  void confirmEmailChange(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.confirmEmailChange, to, collection, variables);
  }

  void verifyEmail(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.verifyEmail, to, collection, variables);
  }

  void passwordReset(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.passwordReset, to, collection, variables);
  }

  void optCode(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.otp, to, collection, variables);
  }

  void magicLink(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.magicLink, to, collection, variables);
  }

  void loginNotice(
    EmailAddress to, {
    required String collection,
    Map<String, dynamic>? variables,
  }) {
    _sendBuiltIn(.loginNotice, to, collection, variables);
  }
}
