import 'package:file/file.dart';

import '../deps/fs.dart';

/// [path] rewritten in the filesystem's own spelling, absolute, with every
/// symlink followed.
///
/// This exists because a path that names the right file is not necessarily a
/// path that COMPARES equal to another one naming the same file, and code that
/// decides "is this file inside that directory" with a string compare needs
/// both sides spelled the same way. Two hosts make that bite:
///
/// - macOS puts the system temp directory at `/var/folders/...`, a symlink to
///   `/private/var/folders/...`.
/// - Windows hands out 8.3 short names — a GitHub runner's `TEMP` is
///   `C:\Users\RUNNER~1\...` for a directory whose real name is
///   `C:\Users\runneradmin\...`.
///
/// Unlike `resolveSymbolicLinksSync`, [path] does not have to exist: this
/// walks up to the deepest ancestor that does, resolves THAT, and re-joins the
/// rest. A file about to be created therefore gets the same spelling as the
/// directory it will be created in, which is the whole point — resolving only
/// the paths that happen to exist yet is how the two sides drift apart.
String canonicalPath(String path) {
  final absolute = fs.path.absolute(path);

  final tail = <String>[];
  var current = absolute;
  while (true) {
    if (_resolveOrNull(current) case final resolved?) {
      return fs.path.normalize(fs.path.joinAll([resolved, ...tail.reversed]));
    }

    final parent = fs.path.dirname(current);
    // The root itself did not resolve: nothing here can be canonicalised, so
    // hand back the absolute form rather than an empty string.
    if (parent == current) return fs.path.normalize(absolute);

    tail.add(fs.path.basename(current));
    current = parent;
  }
}

String? _resolveOrNull(String path) {
  try {
    return switch (fs.typeSync(path)) {
      FileSystemEntityType.directory => fs
          .directory(path)
          .resolveSymbolicLinksSync(),
      FileSystemEntityType.file => fs.file(path).resolveSymbolicLinksSync(),
      _ => null,
    };
  } on FileSystemException {
    return null;
  }
}
