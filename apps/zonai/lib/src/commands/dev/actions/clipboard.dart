import 'dart:convert';
import 'dart:io';

Future<bool> copyToSystemClipboard(String text) async {
  if (text.isEmpty) return false;

  try {
    if (Platform.isMacOS) {
      // osascript avoids piping to pbcopy, which can hang inside raw-mode TUIs.
      final result = await Process.run('osascript', [
        '-e',
        'set the clipboard to ${jsonEncode(text)}',
      ]).timeout(const Duration(seconds: 2));
      return result.exitCode == 0;
    }

    if (Platform.isLinux) {
      for (final command in [
        ['wl-copy'],
        ['xclip', '-selection', 'clipboard'],
      ]) {
        try {
          final process = await Process.start(
            command.first,
            command.skip(1).toList(),
          );
          process.stdin.write(text);
          await process.stdin.close();
          if (await process.exitCode.timeout(const Duration(seconds: 2)) == 0) {
            return true;
          }
        } on ProcessException {
          continue;
        }
      }
      return false;
    }

    if (Platform.isWindows) {
      final process = await Process.start('cmd', [
        '/c',
        'clip',
      ], runInShell: true);
      process.stdin.write(text);
      await process.stdin.close();
      return await process.exitCode.timeout(const Duration(seconds: 2)) == 0;
    }
  } catch (_) {
    return false;
  }

  return false;
}
