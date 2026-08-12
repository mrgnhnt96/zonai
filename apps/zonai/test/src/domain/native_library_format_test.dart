import 'package:test/test.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/native_library_format.dart';
import 'package:zonai/src/domain/target_os.dart';

/// Headers are built here rather than read from a fixture binary: the whole
/// point is to cover targets this test cannot be running on, and a checked-in
/// .so/.dylib/.dll per architecture would be megabytes of binary to assert a
/// handful of bytes.
List<int> _elf({required int machine, int elfClass = 2, int endian = 1}) {
  final bytes = List.filled(64, 0);
  bytes.setRange(0, 4, [0x7F, 0x45, 0x4C, 0x46]);
  bytes[4] = elfClass;
  bytes[5] = endian;
  bytes[18] = machine & 0xFF;
  bytes[19] = (machine >> 8) & 0xFF;
  return bytes;
}

List<int> _machO(int cpuType) {
  final bytes = List.filled(32, 0);
  bytes.setRange(0, 4, [0xCF, 0xFA, 0xED, 0xFE]);
  bytes[4] = cpuType & 0xFF;
  bytes[5] = (cpuType >> 8) & 0xFF;
  bytes[6] = (cpuType >> 16) & 0xFF;
  bytes[7] = (cpuType >> 24) & 0xFF;
  return bytes;
}

List<int> _pe(int machine, {int peOffset = 0x80}) {
  final bytes = List.filled(peOffset + 16, 0);
  bytes.setRange(0, 2, [0x4D, 0x5A]);
  bytes[0x3C] = peOffset & 0xFF;
  bytes[0x3D] = (peOffset >> 8) & 0xFF;
  bytes.setRange(peOffset, peOffset + 4, [0x50, 0x45, 0x00, 0x00]);
  bytes[peOffset + 4] = machine & 0xFF;
  bytes[peOffset + 5] = (machine >> 8) & 0xFF;
  return bytes;
}

void main() {
  group('nativeLibraryPlatform', () {
    test('reads 64-bit little-endian ELF machines', () {
      expect(nativeLibraryPlatform(_elf(machine: 0x3E)), (
        os: TargetOs.linux,
        arch: Arch.x64,
      ));
      expect(nativeLibraryPlatform(_elf(machine: 0xB7)), (
        os: TargetOs.linux,
        arch: Arch.arm64,
      ));
    });

    test('reads 64-bit little-endian Mach-O cpu types', () {
      expect(nativeLibraryPlatform(_machO(0x0100000C)), (
        os: TargetOs.macos,
        arch: Arch.arm64,
      ));
      expect(nativeLibraryPlatform(_machO(0x01000007)), (
        os: TargetOs.macos,
        arch: Arch.x64,
      ));
    });

    test('reads PE machine types through the DOS stub', () {
      expect(nativeLibraryPlatform(_pe(0x8664)), (
        os: TargetOs.windows,
        arch: Arch.x64,
      ));
      expect(nativeLibraryPlatform(_pe(0xAA64)), (
        os: TargetOs.windows,
        arch: Arch.arm64,
      ));
    });

    test('returns null for anything it cannot positively identify', () {
      // Each of these is a shape the guard must not turn into a refusal: a
      // wrong answer here blocks an install that was fine.
      expect(nativeLibraryPlatform(const []), isNull);
      expect(
        nativeLibraryPlatform(const [0x7F, 0x45]),
        isNull,
        reason: 'truncated ELF',
      );
      expect(
        nativeLibraryPlatform(_elf(machine: 0xF3)),
        isNull,
        reason: 'riscv',
      );
      expect(
        nativeLibraryPlatform(_elf(machine: 0x3E, elfClass: 1)),
        isNull,
        reason: '32-bit',
      );
      expect(
        nativeLibraryPlatform(_elf(machine: 0x3E, endian: 2)),
        isNull,
        reason: 'big-endian',
      );
      expect(
        nativeLibraryPlatform(_machO(0x01000099)),
        isNull,
        reason: 'unknown cpu type',
      );
      expect(
        nativeLibraryPlatform(const [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2]),
        isNull,
        reason:
            'a universal binary carries several architectures; picking '
            'one would be a guess, and the loader picks correctly anyway',
      );
      expect(
        nativeLibraryPlatform(_pe(0x0000)),
        isNull,
        reason: 'unknown PE machine',
      );
    });
  });

  group('nativeLibraryPlatformMismatch', () {
    test('accepts bytes built for the platform running this test', () {
      expect(
        nativeLibraryPlatformMismatch(
          _headerForCurrentPlatform(),
          name: 'resqlite',
        ),
        isNull,
      );
    });

    test('names both platforms when they differ', () {
      // The cross-compilation that shipped broken bundles: macOS arm64 host,
      // linux/x64 target. Asserted from whichever side this test runs on.
      final foreign = switch (TargetOs.current()) {
        TargetOs.linux => _machO(0x0100000C),
        _ => _elf(machine: 0x3E),
      };

      expect(
        nativeLibraryPlatformMismatch(foreign, name: 'resqlite'),
        allOf(
          contains('resqlite'),
          contains(TargetOs.current().name),
          contains(Arch.current().name),
        ),
      );
    });

    test('does not object to bytes it cannot read', () {
      expect(
        nativeLibraryPlatformMismatch(const [1, 2, 3], name: 'argon2'),
        isNull,
      );
    });
  });

  group('checkNativeLibraryPlatform', () {
    test(
      'throws for a foreign library, naming the file it would overwrite',
      () {
        final foreign = switch (TargetOs.current()) {
          TargetOs.linux => _machO(0x0100000C),
          _ => _elf(machine: 0x3E),
        };

        expect(
          () => checkNativeLibraryPlatform(
            foreign,
            name: 'resqlite',
            destination: '.zonai/lib/libresqlite.so',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('.zonai/lib/libresqlite.so'),
                contains('.zonai/lib/libresqlite.so.stamp'),
                contains('cross-compiled'),
              ),
            ),
          ),
        );
      },
    );

    test('passes through for a library built for this platform', () {
      expect(
        () => checkNativeLibraryPlatform(
          _headerForCurrentPlatform(),
          name: 'resqlite',
          destination: '.zonai/lib/libresqlite.so',
        ),
        returnsNormally,
      );
    });
  });
}

List<int> _headerForCurrentPlatform() {
  return switch ((TargetOs.current(), Arch.current())) {
    (TargetOs.linux, Arch.x64) => _elf(machine: 0x3E),
    (TargetOs.linux, Arch.arm64) => _elf(machine: 0xB7),
    (TargetOs.macos, Arch.arm64) => _machO(0x0100000C),
    (TargetOs.macos, Arch.x64) => _machO(0x01000007),
    (TargetOs.windows, Arch.x64) => _pe(0x8664),
    (TargetOs.windows, Arch.arm64) => _pe(0xAA64),
    final target => throw UnsupportedError('No header builder for $target'),
  };
}
