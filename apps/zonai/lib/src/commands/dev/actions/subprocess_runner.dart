import 'dart:convert';
import 'dart:io';

import 'package:zonai/src/utils/zonai_entrypoint.dart';

typedef OutputSink = void Function(String line);

/// Resolve the command to invoke the zonai CLI as a subprocess.
(String, List<String>) resolveZonaiCommand(List<String> subArgs) {
  final exe = Platform.resolvedExecutable;
  final exeName = exe.split(Platform.pathSeparator).last;

  if (exeName.startsWith('dart')) {
    return (exe, ['run', dartRunEntrypoint(), ...subArgs]);
  }
  return (exe, subArgs);
}

/// Run a zonai subcommand as a subprocess and pipe its output to [onOutput].
/// Returns the process exit code.
Future<int> runZonaiCommand(List<String> subArgs, OutputSink onOutput) async {
  final (exe, args) = resolveZonaiCommand(subArgs);
  onOutput(
    '> ${[exe.split(Platform.pathSeparator).last, ...subArgs].join(' ')}',
  );

  late final Process process;
  try {
    process = await Process.start(exe, args);
  } catch (e) {
    onOutput('[error] Failed to start process: $e');
    return 1;
  }

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onOutput);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => onOutput('[err] $line'));

  return process.exitCode;
}
