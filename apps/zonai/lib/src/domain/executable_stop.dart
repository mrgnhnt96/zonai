import '../deps/fs.dart';
import 'constants.dart';

/// Dev-only stop markers that signal worker processes to restart on the next request.
class ExecutableStop {
  ExecutableStop();

  String _stopFilePath(String executablePath) {
    final name = fs.path.basenameWithoutExtension(executablePath);
    return fs.path.join(fs.path.dirname(executablePath), '$name.stop');
  }

  /// Signals the running worker to exit on the next request.
  void request(String executablePath) {
    if (kIsCompiled) return;

    final stopFile = fs.file(_stopFilePath(executablePath));
    stopFile.parent.createSync(recursive: true);
    stopFile.createSync(recursive: false);
  }

  bool isRequested(String executablePath) {
    if (kIsCompiled) return false;
    return fs.file(_stopFilePath(executablePath)).existsSync();
  }

  void clear(String executablePath) {
    if (kIsCompiled) return;

    final stopFile = fs.file(_stopFilePath(executablePath));
    if (stopFile.existsSync()) {
      stopFile.deleteSync();
    }
  }
}
