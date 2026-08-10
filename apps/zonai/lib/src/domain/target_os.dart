import 'dart:io';

import 'package:zonai/src/domain/arch.dart';

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

  /// Whether this (host) platform can `dart compile exe` for
  /// [targetOs]/[targetArch].
  ///
  /// Dart cross-compiles to Linux from any host, but every other target must
  /// match the host *exactly* -- architecture included. Verified against Dart
  /// 3.12 on macOS arm64: `--target-os linux` succeeds for both x64 and
  /// arm64, while `--target-os macos --target-arch x64` reports
  ///
  ///   Unsupported target platform macos_x64.
  ///   Supported target platforms: linux_arm, linux_arm64, linux_riscv64,
  ///   linux_x64
  ///
  /// The architecture half matters: checking only the OS let
  /// `--target-arch x64` on an Apple Silicon Mac past this guard, so the
  /// build failed later inside `dart compile exe` instead of here.
  bool canCompile(TargetOs targetOs, Arch targetArch) {
    if (targetOs == linux) return true;

    return targetOs == this && targetArch == Arch.current();
  }
}
