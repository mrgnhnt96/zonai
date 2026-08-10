import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/target_os.dart';

import '../deps/fs.dart';

/// Sidecar marker recording which zonai release, and which target, a shared
/// library sitting in `.zonai/lib/` came from.
///
/// A compiled zonai normally self-extracts its own embedded copy of each
/// native library on first FFI use. That copy is only correct when the binary
/// was compiled on the platform it now runs on: `dart compile exe
/// --target-os` cross-compiles the executable format but not the library
/// bytes baked in as Dart constants (see resqlite_native.dart's
/// `_requestFromSpawner`). So `zonai build` can place the *target's* real
/// libraries next to a cross-compiled binary -- and self-extraction has to
/// know not to overwrite them with its own wrong-platform bytes.
///
/// The stamp is what distinguishes "placed deliberately for this target" from
/// "left over". Without it, an existence check alone would also preserve a
/// stale library from an older build, which is worse than re-extracting: it
/// would pin a deployment to a library nobody chose.
String nativeLibraryStampPathFor(String libraryPath) => '$libraryPath.stamp';

/// Records that [libraryPath] holds the [targetOs]/[targetArch] library from
/// zonai [version].
void writeNativeLibraryStamp(
  String libraryPath, {
  required String version,
  required TargetOs targetOs,
  required Arch targetArch,
}) {
  final file = fs.file(nativeLibraryStampPathFor(libraryPath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$version ${targetOs.name} ${targetArch.name}');
}

/// Whether [libraryPath] is a library this exact binary should keep rather
/// than overwrite with its own embedded bytes.
///
/// True only when the file exists *and* carries a stamp naming this zonai
/// version and the platform actually running. Anything else -- no stamp, a
/// stamp from another release, a stamp for a different target -- is treated
/// as unknown, and self-extraction wins. Erring that way keeps the failure
/// mode "extracted a library that was already correct" rather than "ran
/// against a library nothing vouches for".
bool hasCurrentNativeLibraryStamp(String libraryPath) {
  if (!fs.file(libraryPath).existsSync()) return false;

  final stamp = fs.file(nativeLibraryStampPathFor(libraryPath));
  if (!stamp.existsSync()) return false;

  return stamp.readAsStringSync().trim() ==
      '$kVersion ${TargetOs.current().name} ${Arch.current().name}';
}
