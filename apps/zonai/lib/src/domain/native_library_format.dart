import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/native_library_stamp.dart';
import 'package:zonai/src/domain/target_os.dart';

/// Reads the platform a shared library's bytes were built for straight out of
/// its object-file header.
///
/// A compiled zonai self-extracts the native library bytes baked into it as
/// Dart constants (see resqlite_native.dart). Those bytes are whatever the
/// machine that ran `dart compile exe` had: `--target-os`/`--target-arch`
/// cross-compile the executable format, not data embedded in it. So a worker
/// cross-compiled on macOS arm64 for linux/x64 carries Mach-O arm64 library
/// bytes, and extracting them on the target writes a library nothing there
/// can load.
///
/// That write lands on the *shared* install path (`.zonai/lib/`), the same
/// one the host binary extracts its own -- correct -- copy to. So the damage
/// isn't confined to the process that got it wrong: it replaces a working
/// library for every process on the machine. Reading the header first is what
/// turns that into a refusal.
///
/// Deliberately header-only. Nothing here validates that the library is
/// complete or loadable -- an ELF header says "built for linux/x64", not
/// "this file works". It answers one question, the one that distinguishes a
/// cross-compilation mistake from every other reason a `dlopen` can fail.
typedef LibraryPlatform = ({TargetOs os, Arch arch});

/// The platform [bytes] were built for, or `null` when the header isn't one
/// of the three formats zonai ships for -- or names a machine outside
/// [Arch].
///
/// Unrecognised is `null` rather than an error on purpose: this is a guard in
/// front of a write that used to be unconditional, and a format it cannot
/// read is not evidence of a mismatch. Callers treat `null` as "no reason to
/// object" so a future target can't be blocked by this file not knowing about
/// it yet.
LibraryPlatform? nativeLibraryPlatform(List<int> bytes) {
  return _elfPlatform(bytes) ?? _machOPlatform(bytes) ?? _pePlatform(bytes);
}

/// Why [bytes] must not be installed on the platform this process is running
/// on, or `null` when there's no objection.
///
/// [name] names the library in the message ('resqlite'), since the two
/// callers are otherwise indistinguishable in a log.
String? nativeLibraryPlatformMismatch(List<int> bytes, {required String name}) {
  final embedded = nativeLibraryPlatform(bytes);
  if (embedded == null) return null;

  final current = (os: TargetOs.current(), arch: Arch.current());
  if (embedded == current) return null;

  return 'the embedded $name library is '
      '${embedded.os.name}/${embedded.arch.name}, but this process is running '
      'on ${current.os.name}/${current.arch.name}';
}

/// Throws unless [bytes] can be installed at [destination] on the platform
/// this process is running on.
///
/// Called on the self-extraction path only. The alternative -- writing the
/// bytes and letting `dlopen` reject them -- reports the failure at the wrong
/// place: by then the shared library every process on the machine loads has
/// already been replaced with an unloadable one, and the error names an FFI
/// symbol rather than the cross-compilation that caused it.
void checkNativeLibraryPlatform(
  List<int> bytes, {
  required String name,
  required String destination,
}) {
  final mismatch = nativeLibraryPlatformMismatch(bytes, name: name);
  if (mismatch == null) return;

  throw StateError(
    'Refusing to install the $name native library at $destination: $mismatch.\n'
    '\n'
    'This binary was cross-compiled. `dart compile exe --target-os` produces '
    'an executable for the target, but the native library bytes embedded in '
    'it as Dart constants are the build machine\'s -- so extracting them here '
    'would overwrite a working library with one this platform cannot load, '
    'for every process that shares $destination.\n'
    '\n'
    '`zonai build` is what supplies the target\'s real libraries: it fetches '
    'them into the bundle and writes '
    '${nativeLibraryStampPathFor(destination)} naming zonai $kVersion and '
    'this target. Nothing is stamped there, so either the bundle was built '
    'without them (the fetch failed, or the build predates it), or it is '
    'being run against a different zonai release than the one that built it.',
  );
}

/// ELF (linux): `\x7fELF`, then a 64-bit/little-endian class, then `e_machine`
/// at offset 18.
///
/// Only 64-bit little-endian is read. Every target zonai publishes is one, and
/// a big-endian or 32-bit ELF is something this cannot have produced -- so it
/// returns `null` (unknown) rather than guessing an [Arch] for it.
LibraryPlatform? _elfPlatform(List<int> bytes) {
  if (bytes.length < 20) return null;
  if (bytes[0] != 0x7F ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4C ||
      bytes[3] != 0x46) {
    return null;
  }
  if (bytes[4] != 2 || bytes[5] != 1) return null;

  return switch (bytes[18] | (bytes[19] << 8)) {
    0x3E => (os: TargetOs.linux, arch: Arch.x64),
    0xB7 => (os: TargetOs.linux, arch: Arch.arm64),
    0x28 => (os: TargetOs.linux, arch: Arch.arm),
    _ => null,
  };
}

/// Mach-O (macOS): the 64-bit little-endian magic `0xFEEDFACF`, then
/// `cputype` at offset 4.
///
/// A universal ("fat", `0xCAFEBABE`) binary is intentionally not decoded: it
/// carries several architectures and answering with one of them would be a
/// guess. It also cannot be wrong in the way this guard exists to catch --
/// the loader picks the slice it needs -- so `null` is the honest answer.
LibraryPlatform? _machOPlatform(List<int> bytes) {
  if (bytes.length < 8) return null;
  if (bytes[0] != 0xCF ||
      bytes[1] != 0xFA ||
      bytes[2] != 0xED ||
      bytes[3] != 0xFE) {
    return null;
  }

  final cpuType =
      bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);

  return switch (cpuType) {
    0x0100000C => (os: TargetOs.macos, arch: Arch.arm64),
    0x01000007 => (os: TargetOs.macos, arch: Arch.x64),
    _ => null,
  };
}

/// PE (windows): an `MZ` DOS stub whose `e_lfanew` (offset 0x3C) points at the
/// `PE\0\0` signature, with the COFF machine type right after it.
LibraryPlatform? _pePlatform(List<int> bytes) {
  if (bytes.length < 0x40) return null;
  if (bytes[0] != 0x4D || bytes[1] != 0x5A) return null;

  final peOffset =
      bytes[0x3C] |
      (bytes[0x3D] << 8) |
      (bytes[0x3E] << 16) |
      (bytes[0x3F] << 24);
  if (peOffset < 0 || bytes.length < peOffset + 6) return null;

  if (bytes[peOffset] != 0x50 ||
      bytes[peOffset + 1] != 0x45 ||
      bytes[peOffset + 2] != 0 ||
      bytes[peOffset + 3] != 0) {
    return null;
  }

  return switch (bytes[peOffset + 4] | (bytes[peOffset + 5] << 8)) {
    0x8664 => (os: TargetOs.windows, arch: Arch.x64),
    0xAA64 => (os: TargetOs.windows, arch: Arch.arm64),
    _ => null,
  };
}
