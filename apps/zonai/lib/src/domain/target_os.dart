import 'dart:io';

enum TargetOs {
  linux,
  macos,
  windows;

  static TargetOs current() {
    return switch (Platform.operatingSystem) {
      'linux' => linux,
      'macos' => macos,
      'windows' => windows,
      _ => throw UnsupportedError(
        'Unsupported platform: ${Platform.operatingSystem}',
      ),
    };
  }

  bool canCompile(TargetOs targetOs) {
    return switch ((targetOs, this)) {
      (linux, _) => true,
      (macos, macos) => true,
      (windows, windows) => true,
      _ => false,
    };
  }
}
