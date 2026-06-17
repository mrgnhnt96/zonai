import 'dart:io';

import '../../../deps/fs.dart';
import '../../../deps/logger.dart';
import '../../../utils/ci_environment.dart';
import 'init_actions.dart';

bool projectConfigExists() =>
    fs.file('zonai.yml').existsSync() || fs.file('zonai.yaml').existsSync();

/// Prompts for Y/n using a single keypress (stdin may be in raw mode).
bool promptProjectInit() {
  stdout.write('No zonai.yaml found. Initialize project? [Y/n]: ');
  final byte = stdin.readByteSync();
  final char = byte >= 0 ? String.fromCharCode(byte).toLowerCase() : '';
  stdout.writeln(char == 'n' ? 'n' : 'y');
  return char != 'n';
}

/// Returns an exit code when the caller should stop, or null to continue.
Future<int?> ensureProjectInitialized() async {
  if (projectConfigExists()) {
    return null;
  }

  final shouldInit = isCiEnvironment || !stdin.hasTerminal
      ? true
      : promptProjectInit();

  if (!shouldInit) {
    logger.info('Aborted. Run `zonai dev` to initialize the project.');
    return 0;
  }

  stdout.writeln();
  await initProject();
  stdout.writeln();
  return null;
}
