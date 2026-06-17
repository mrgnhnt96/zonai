import 'dart:io' as io;

import 'package:zonai/src/utils/dart_sdk.dart';

class Process {
  Future<io.ProcessResult> runDart(List<String> arguments) async {
    return run(await resolveDartExecutable(), arguments);
  }

  Future<io.ProcessResult> run(String command, List<String> arguments) async {
    final result = await io.Process.run(command, arguments);
    return result;
  }

  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async {
    final process = await io.Process.start(
      command,
      arguments,
      workingDirectory: workingDirectory,
      mode: mode,
    );
    return process;
  }

  bool kill(int pid) => io.Process.killPid(pid);
}
