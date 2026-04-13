import 'dart:io' as io;

class Process {
  Future<io.ProcessResult> run(String command, List<String> arguments) async {
    final result = await io.Process.run(command, arguments);
    return result;
  }
}
