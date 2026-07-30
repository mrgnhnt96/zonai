import 'dart:ffi';

enum Arch {
  x64,
  arm,
  arm64
  // riscv64,
  ;

  const Arch();

  static Arch current() {
    return switch (Abi.current()) {
      .macosX64 => x64,
      .macosArm64 => arm64,

      // .windowsArm64 => arm64,
      .windowsX64 => x64,

      .linuxArm64 => arm64,
      // .linuxArm => arm,
      // .linuxRiscv64 => riscv64,
      .linuxX64 => x64,
      _ => throw UnsupportedError('Unsupported architecture: ${Abi.current()}'),
    };
  }
}
