import 'dart:io' as io;

class Process {
  Future<io.ProcessResult> run(String command, List<String> arguments) async {
    final result = await io.Process.run(command, arguments);
    return result;
  }

  Future<io.Process> start(String command, List<String> arguments) async {
    final process = await io.Process.start(command, arguments);
    return process;
  }
}
