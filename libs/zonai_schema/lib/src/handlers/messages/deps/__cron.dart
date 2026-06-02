part of '../message_handler.dart';

final _cronProvider = create<_Cron>(_Cron._);

_Cron get cron => read(_cronProvider);

class _Cron {
  _Cron._() {
    start = (_) {};
  }
  _Cron(this.start);

  late final void Function(String name) start;
}
