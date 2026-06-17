import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';

final fsProvider = create<FileSystem>(LocalFileSystem.new);

FileSystem get fs => read(fsProvider);

extension FileSystemEnsure on FileSystem {
  /// Creates [path] when missing so [DirectoryWatcher] can subscribe before
  /// the first file is written.
  Directory ensureDirectory(String path) {
    final dir = directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
