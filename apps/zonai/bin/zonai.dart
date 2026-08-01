// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:zonai/src/bootstrap.dart';
import 'package:zonai/src/utils/zonai_entrypoint.dart';

void main(List<String> arguments) async {
  final reexecCode = await reexecFromSourceIfNeeded(arguments);
  if (reexecCode >= 0) {
    exit(reexecCode);
  }

  await runZonai(arguments);
}
