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
/// The "not linux" cases are named explicitly rather than derived from the
/// host, so every runner checks the same truth table. Deriving them from the
/// host meant macOS only ever exercised macos, Windows only windows, and Linux
/// exercised a case that does not exist (see the arch tests below).
void main() {
  final hostOs = TargetOs.current();
  final hostArch = Arch.current();
  const nonLinux = [TargetOs.macos, TargetOs.windows];

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
      //
      // Spelled with an explicit non-Linux OS rather than `hostOs`, because on
      // a Linux host `hostOs` IS linux, where returning true is the *correct*
      // answer (Dart cross-compiles to linux at any arch). Written as
      // `hostOs.canCompile(hostOs, ...)` this asserted "linux refuses linux at
      // another arch", which is false, so it failed on CI's ubuntu runner
      // while passing on the macOS laptop it was written on.
      final otherArch = Arch.values.firstWhere((a) => a != hostArch);

      for (final os in nonLinux) {
        expect(
          os.canCompile(os, otherArch),
          isFalse,
          reason:
              '${os.name}/${otherArch.name} is a different platform to Dart, '
              'not a variant of ${os.name}/${hostArch.name}',
        );
      }
    });

    test('is architecture-blind only for Linux', () {
      final otherArch = Arch.values.firstWhere((a) => a != hostArch);

      expect(hostOs.canCompile(TargetOs.linux, otherArch), isTrue);

      for (final os in nonLinux) {
        expect(
          os.canCompile(os, otherArch),
          isFalse,
          reason: 'only linux ignores the target arch, ${os.name} must not',
        );
      }
    });

    // The whole truth table, with each OS standing in as the host. This is
    // what makes the suite mean the same thing on the macOS laptop it was
    // written on and on CI's ubuntu and windows runners: the only host input
    // `canCompile` reads is `Arch.current()`, and every case below pins the
    // arch as either "the host's" or "not the host's", so the table is fully
    // determined without knowing which machine is running it.
    test('holds the same truth table with any OS as the host', () {
      final otherArch = Arch.values.firstWhere((a) => a != hostArch);

      for (final host in TargetOs.values) {
        expect(
          host.canCompile(TargetOs.linux, hostArch),
          isTrue,
          reason: 'linux is cross-compilable from $host',
        );
        expect(
          host.canCompile(TargetOs.linux, otherArch),
          isTrue,
          reason: 'linux is cross-compilable from $host at any arch',
        );
        expect(
          host.canCompile(host, hostArch),
          isTrue,
          reason: '$host can always target itself at its own arch',
        );

        for (final os in nonLinux) {
          expect(
            host.canCompile(os, otherArch),
            isFalse,
            reason: '$host must refuse ${os.name} at a foreign arch',
          );

          if (os != host) {
            expect(
              host.canCompile(os, hostArch),
              isFalse,
              reason: '$host must refuse ${os.name}, arch match or not',
            );
          }
        }
      }
    });
  });
}
