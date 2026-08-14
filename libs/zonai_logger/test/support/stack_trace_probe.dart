import 'dart:io';

import 'package:zonai_logger/zonai_logger.dart';

/// Prints one `logger.error(...)` carrying a stack trace, at the [Level] named
/// by `args[0]`.
///
/// Run under `-D__ZONAI_COMPILED__=true` by
/// `test/stack_trace_compiled_e2e_test.dart`: `bool.fromEnvironment` is
/// resolved at compile time, so the compiled-binary branch of
/// `Logger._includeStackTrace` cannot be reached from a normal test process.
void main(List<String> args) {
  final level = Level.fromString(args.isEmpty ? null : args.first);
  if (level == null) {
    stderr.writeln('usage: stack_trace_probe.dart <level>');
    exitCode = 64;
    return;
  }

  Logger(level: level).error(
    'probe-message',
    'probe-error',
    StackTrace.fromString('#0      probeFrame (package:probe/probe.dart:1)'),
  );
}
