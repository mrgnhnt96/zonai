import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `Logger._includeStackTrace` reads `bool.fromEnvironment('__ZONAI_COMPILED__')`,
/// a **compile-time** constant: inside a normal `dart test` process it is
/// always `false`, so the branch that a released `zonai` binary actually takes
/// is unreachable from an in-process test. These run a probe in a child VM
/// with the define set, which is the only way to observe it.
///
/// The behaviour under test comes from a Picto report: a 500 out of a compiled
/// `zonai serve` printed an error line and a message line with no file, frame
/// or line anywhere — the compiled build discarded the trace at *every* level,
/// so `--log=debug` and `-L` bought nothing.
void main() {
  final probe = p.join('test', 'support', 'stack_trace_probe.dart');

  Future<String> runProbe(String level, {required bool compiled}) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      if (compiled) '-D__ZONAI_COMPILED__=true',
      probe,
      level,
    ], workingDirectory: _packageRoot);

    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    return '${result.stdout}${result.stderr}';
  }

  group('error stack traces in a compiled binary', () {
    test(
      'are omitted at the default level',
      () async {
        final output = await runProbe('info', compiled: true);

        expect(output, contains('probe-message'));
        expect(output, contains('probe-error'));
        expect(
          output,
          isNot(contains('probeFrame')),
          reason:
              'a Dart frame stack is noise on a CLI error line at the default '
              'level',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'are printed once the operator asks for detail',
      () async {
        for (final level in const ['debug', 'verbose', 'trace', 'request']) {
          final output = await runProbe(level, compiled: true);

          expect(
            output,
            contains('probeFrame'),
            reason:
                'at --log=$level the operator has explicitly asked for detail; '
                'discarding the trace there is what left a 500 with nothing to '
                'locate it by',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'are always printed when not compiled',
      () async {
        final output = await runProbe('info', compiled: false);

        expect(output, contains('probeFrame'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

/// Tests run with the package root as the working directory, but be explicit
/// so the probe path resolves the same way under a runner that does not.
String get _packageRoot {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return dir.path;
}
