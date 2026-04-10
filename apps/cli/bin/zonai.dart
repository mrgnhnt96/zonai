// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/utils/args.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/zonai_runner.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main(List<String> arguments) async {
  await _run(arguments);
}

Future<void> _run(List<String> arguments) async {
  final parsed = Args.parse(arguments);

  final log = Logger(
    level: switch ((parsed['quiet'], parsed['loud'])) {
      (true, _) => Level.error,
      (_, true) => Level.verbose,
      (_, _) => Level.info,
    },
  );

  await overrideAnsiOutput(true, () async {
    await runScoped(
      () async {
        try {
          exitCode = await run();
        } catch (e) {
          logger.error('Error: $e');
          exitCode = 1;
        }
      },
      values: {
        argsProvider.overrideWith(() => parsed),
        fsProvider,
        loggerProvider.overrideWith(() => log),
      },
    );
  });
}
