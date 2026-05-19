part of '../message_handler.dart';

typedef _SendEmailFn = Future<void> Function(Email email);

final _emailProvider = create<_Email>(_Email._);

_Email get email => read(_emailProvider);

class _Email {
  _Email._() {
    send = (Email email) async {};
  }
  _Email(this.send);

  late final _SendEmailFn send;
}
