import 'package:test/test.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/target_os.dart';

/// [TargetOs.canCompile] is the guard `zonai build` uses to refuse a target
/// before spending several minutes on it, so its truth table has to match what
/// `dart compile exe` will actually accept. Probed directly against Dart 3.12
/// on macOS arm64:
///
///   --target-os linux  --target-arch x64    Generated
///   --target-os linux  --target-arch arm64  Generated
///   --target-os macos  --target-arch arm64  Generated  (the host)
///   --target-os macos  --target-arch x64    Unsupported target platform macos_x64.
///                                           Supported target platforms:
///                                           linux_arm, linux_arm64,
///                                           linux_riscv64, linux_x64
///   --target-os windows --target-arch x64   Unsupported target platform windows_x64.
///
/// i.e. Linux from anywhere, otherwise an exact host match -- architecture
/// included. The architecture half is the part that was missing: checking only
/// the OS let `--target-arch x64` on an Apple Silicon Mac past this guard and
/// fail minutes later inside dart compile exe.
void main() {
  final hostOs = TargetOs.current();
  final hostArch = Arch.current();

  group('TargetOs.canCompile', () {
    test('allows Linux targets from any host', () {
      for (final arch in [Arch.x64, Arch.arm64]) {
        expect(
          hostOs.canCompile(TargetOs.linux, arch),
          isTrue,
          reason: 'linux/${arch.name} is cross-compilable from every host',
        );
      }
    });

    test('allows the host itself', () {
      expect(hostOs.canCompile(hostOs, hostArch), isTrue);
    });

    test('refuses a non-Linux OS that is not the host', () {
      for (final os in TargetOs.values) {
        if (os == TargetOs.linux || os == hostOs) continue;

        expect(
          hostOs.canCompile(os, hostArch),
          isFalse,
          reason: 'dart compile exe cannot target ${os.name} from $hostOs',
        );
      }
    });

    test('refuses a non-Linux host OS at a different architecture', () {
      // The regression this test exists for: macos/x64 requested from
      // macos/arm64 is a different platform to Dart, not a variant of the
      // host, and it must not pass just because the OS matches.
      final otherArch = Arch.values.firstWhere((a) => a != hostArch);

      expect(hostOs.canCompile(hostOs, otherArch), isFalse);
    });

    test('is architecture-blind only for Linux', () {
      final otherArch = Arch.values.firstWhere((a) => a != hostArch);

      expect(hostOs.canCompile(TargetOs.linux, otherArch), isTrue);
      expect(hostOs.canCompile(hostOs, otherArch), isFalse);
    });
  });
}
