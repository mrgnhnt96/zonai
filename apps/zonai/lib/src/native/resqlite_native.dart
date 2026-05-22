import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:zonai/src/domain/constants.dart';

import '../../gen/native/resqlite_native.g.dart';
import '../deps/fs.dart';
import '../domain/settings.dart';

/// Ensures the resqlite native library is loaded before any FFI use.
Future<void> ensureResqliteNativeInstalled() async {
  if (isInstalled) return;

  final path = switch (kIsCompiled) {
    true => await _extractCompiledLibrary(),
    false => _developmentLibraryPath(),
  };

  install(path);
}

Future<String> _extractCompiledLibrary() async {
  final libDir = fs.directory(
    fs.path.join(Settings.defaultZonaiDirectory, 'lib'),
  );
  if (!libDir.existsSync()) {
    libDir.createSync(recursive: true);
  }

  final dest = fs.file(
    fs.path.join(libDir.path, defaultLibraryFileName),
  );
  if (!dest.existsSync()) {
    await dest.writeAsBytes(resqliteNativeLibraryBytes, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', dest.path]);
    }
  }

  return dest.absolute.path;
}

String _developmentLibraryPath() {
  final candidates = _developmentLibraryCandidates();

  for (final path in candidates) {
    final file = fs.file(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  throw StateError(
    'Resqlite native library not found.\n'
    'Searched:\n${candidates.map((path) => '  - $path').join('\n')}\n'
    'Run: scripts resqlite gen',
  );
}

List<String> _developmentLibraryCandidates() {
  final libName = defaultLibraryFileName;
  final candidates = <String>[];

  if (Platform.script.scheme == 'file') {
    candidates.add(
      fs.path.normalize(
        fs.path.join(
          fs.file(Platform.script.toFilePath()).parent.path,
          '..',
          'lib',
          'gen',
          'native',
          libName,
        ),
      ),
    );
  }

  var dir = fs.directory(fs.currentDirectory.path);
  while (true) {
    candidates.addAll([
      fs.path.join(dir.path, 'apps', 'zonai', 'lib', 'gen', 'native', libName),
      fs.path.join(dir.path, 'lib', 'gen', 'native', libName),
    ]);

    if (dir.path == dir.parent.path) {
      break;
    }
    dir = dir.parent;
  }

  return candidates;
}
