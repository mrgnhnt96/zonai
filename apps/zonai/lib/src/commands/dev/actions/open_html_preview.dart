import 'dart:io';

/// Writes [html] to a temp file and opens it in the default browser.
///
/// Returns the file path on success, or `null` if the platform is unsupported
/// or the open command failed.
Future<String?> openHtmlPreview(String html, {String? filename}) async {
  if (html.isEmpty) return null;

  final safeName = (filename ?? 'preview').replaceAll(RegExp(r'[^\w.-]+'), '_');
  final dir = Directory.systemTemp.createTempSync('zonai-email-preview-');
  final file = File('${dir.path}/$safeName.html');
  file.writeAsStringSync(html);

  final opened = await _openFile(file.path);
  return opened ? file.path : null;
}

Future<bool> _openFile(String path) async {
  try {
    if (Platform.isMacOS) {
      final result = await Process.run('open', [path]);
      return result.exitCode == 0;
    }

    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    }

    if (Platform.isWindows) {
      final result = await Process.run('cmd', [
        '/c',
        'start',
        '',
        path,
      ], runInShell: true);
      return result.exitCode == 0;
    }
  } catch (_) {
    return false;
  }

  return false;
}
