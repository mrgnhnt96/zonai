import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/native_library_stamp.dart';
import 'package:zonai/src/domain/target_os.dart';

/// The stamp decides whether a compiled binary keeps the library sitting in
/// `.zonai/lib/` or overwrites it with its own embedded copy. Answering
/// "keep" wrongly means running against a library nothing vouches for, so
/// every way a stamp can fail to apply gets a case here.
void main() {
  const libraryPath = '/app/.zonai/lib/libresqlite.so';

  group('hasCurrentNativeLibraryStamp', () {
    test('accepts a library stamped for this version and platform', () {
      final fs = MemoryFileSystem();
      _writeLibrary(fs);

      _run(fs, () {
        writeNativeLibraryStamp(
          libraryPath,
          version: kVersion,
          targetOs: TargetOs.current(),
          targetArch: Arch.current(),
        );
      });

      expect(_run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)), isTrue);
    });

    test('rejects an unstamped library', () {
      // The pre-existing case: every build before stamping wrote a bare
      // library here. Self-extraction has to stay authoritative for those.
      final fs = MemoryFileSystem();
      _writeLibrary(fs);

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });

    test('rejects a stamp whose library is gone', () {
      final fs = MemoryFileSystem();
      fs.directory('/app/.zonai/lib').createSync(recursive: true);
      fs
          .file('$libraryPath.stamp')
          .writeAsStringSync(
            '$kVersion ${TargetOs.current().name} ${Arch.current().name}',
          );

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });

    test('rejects a stamp from another release', () {
      // Upgrading the CLI must not inherit the previous release's libraries:
      // the wire between binary and library is not versioned separately.
      final fs = MemoryFileSystem();
      _writeLibrary(fs);
      _writeStamp(
        fs,
        '0.0.0-not-this-one ${TargetOs.current().name} ${Arch.current().name}',
      );

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });

    test('rejects a stamp for a different target', () {
      // The bundle was built for another platform and then run here; its
      // libraries are exactly as wrong as the embedded ones would be.
      final fs = MemoryFileSystem();
      _writeLibrary(fs);
      final otherOs = TargetOs.values.firstWhere(
        (os) => os != TargetOs.current(),
      );
      _writeStamp(fs, '$kVersion ${otherOs.name} ${Arch.current().name}');

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });

    test('rejects a stamp for a different architecture', () {
      final fs = MemoryFileSystem();
      _writeLibrary(fs);
      final otherArch = Arch.values.firstWhere((a) => a != Arch.current());
      _writeStamp(fs, '$kVersion ${TargetOs.current().name} ${otherArch.name}');

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });

    test('rejects a truncated stamp instead of matching loosely', () {
      final fs = MemoryFileSystem();
      _writeLibrary(fs);
      _writeStamp(fs, kVersion);

      expect(
        _run(fs, () => hasCurrentNativeLibraryStamp(libraryPath)),
        isFalse,
      );
    });
  });

  group('writeNativeLibraryStamp', () {
    test('creates the directory and names the sidecar after the library', () {
      final fs = MemoryFileSystem();

      _run(fs, () {
        writeNativeLibraryStamp(
          libraryPath,
          version: '1.2.3',
          targetOs: TargetOs.linux,
          targetArch: Arch.arm64,
        );
      });

      expect(nativeLibraryStampPathFor(libraryPath), '$libraryPath.stamp');
      expect(
        fs.file('$libraryPath.stamp').readAsStringSync(),
        '1.2.3 linux arm64',
      );
    });
  });
}

T _run<T>(MemoryFileSystem fs, T Function() body) {
  return runScoped(body, values: {fsProvider.overrideWith(() => fs)});
}

void _writeLibrary(MemoryFileSystem fs) {
  fs.directory('/app/.zonai/lib').createSync(recursive: true);
  fs.file('/app/.zonai/lib/libresqlite.so').writeAsStringSync('ELF');
}

void _writeStamp(MemoryFileSystem fs, String contents) {
  fs.file('/app/.zonai/lib/libresqlite.so.stamp').writeAsStringSync(contents);
}
