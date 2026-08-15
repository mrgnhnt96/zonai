import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/target_os.dart';

import '../../support/package_roots.dart';
import '../../support/temp_directory.dart';

/// End-to-end over the stamp guard in `_extractCompiledLibrary`, for both
/// libraries that have one.
///
/// A cross-compiled zonai embeds native-library bytes for whatever platform
/// *built* it, not the one it runs on, so `zonai build` places the target's real
/// libraries next to the binary and stamps them. The guard is what stops
/// self-extraction from overwriting those with its own wrong-platform copy. Get
/// it wrong in the "keep" direction and a deployment pins itself to a library
/// nothing vouches for; wrong in the "overwrite" direction and every
/// cross-target build breaks on first FFI use.
///
/// `native_library_stamp_test.dart` covers the predicate. It cannot cover the
/// guard: `kIsCompiled` is `bool.fromEnvironment('__ZONAI_COMPILED__')`, a
/// compile-time constant `false` under `dart test`, so the branch holding it is
/// not in the test binary at all. This compiles one where it is. The gap it
/// closes was declared in .game_loop/verify.yaml.
void main() {
  late Directory workspace;
  late String probePath;

  setUpAll(() async {
    if (!_runningOnDartVm) return;

    workspace = Directory.systemTemp.createTempSync('zonai_native_extract_');
    probePath = p.join(
      workspace.path,
      Platform.isWindows ? 'probe.exe' : 'probe',
    );

    final compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-D__ZONAI_COMPILED__=true',
      p.join('test', 'support', 'native_library_probe.dart'),
      '-o',
      probePath,
    ], workingDirectory: zonaiPackageRootFromConfig());
    if (compile.exitCode != 0) {
      throw StateError(
        'dart compile exe failed:\n${compile.stderr}\n${compile.stdout}',
      );
    }
  });

  tearDownAll(() {
    if (!_runningOnDartVm) return;
    deleteTempDirectory(workspace);
  });

  for (final library in const ['resqlite', 'argon2']) {
    group('compiled $library extraction', () {
      late String libraryFileName;

      setUpAll(() async {
        if (!_runningOnDartVm) return;

        // Learn the platform's library file name from the binary itself rather
        // than restating the switch in gen/native/. A test that planted its
        // file under a name the binary never looks at would pass every
        // "overwrites" case and fail only the one that matters, for a reason
        // having nothing to do with the guard.
        final scratch = Directory(p.join(workspace.path, '$library-discover'))
          ..createSync(recursive: true);
        final discovered = await Process.run(probePath, [
          library,
        ], workingDirectory: scratch.path);
        expect(
          discovered.exitCode,
          0,
          reason: '${discovered.stderr}\n${discovered.stdout}',
        );
        libraryFileName = p.basename('${discovered.stdout}'.trim());
        expect(libraryFileName, isNotEmpty);
      });

      /// Plants a recognisable non-library at the extraction path, optionally
      /// stamped, runs the probe there, and reports what the guard did.
      ///
      /// Planting a marker rather than a real library is safe because
      /// `provide*NativeLibraryPath` only resolves and returns a path -- it
      /// never dlopens the result. It is also the only way to tell "kept" from
      /// "re-extracted": on this platform the embedded bytes are identical to a
      /// correct library, so comparing against them would distinguish nothing.
      Future<_Outcome> plantAndRun({String? stamp}) async {
        final project = Directory(
          p.join(workspace.path, '$library-case-${_caseCounter++}'),
        )..createSync(recursive: true);
        final planted = File(
          p.join(project.path, '.zonai', 'lib', libraryFileName),
        )..parent.createSync(recursive: true);
        planted.writeAsStringSync(_marker);
        if (stamp != null) {
          File('${planted.path}.stamp').writeAsStringSync(stamp);
        }

        final result = await Process.run(probePath, [
          library,
        ], workingDirectory: project.path);
        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );

        return _Outcome(
          // Resolved on both sides: on macOS the system temp directory is
          // /var/..., a symlink to /private/var/..., and the child reports
          // whichever spelling it resolved. Raw strings would differ for paths
          // that name the same file.
          reportedPath: _resolve('${result.stdout}'.trim()),
          expectedPath: _resolve(planted.path),
          // Bytes, not text: in every case but the kept one this file is a real
          // shared library, and decoding that as UTF-8 throws before the
          // comparison can report what actually happened.
          kept: _bytesEqual(planted.readAsBytesSync(), utf8.encode(_marker)),
        );
      }

      test('keeps a library stamped for this release and platform', () async {
        if (!_runningOnDartVm) return;

        final outcome = await plantAndRun(stamp: _currentStamp);

        expect(
          outcome.kept,
          isTrue,
          reason:
              'a stamped library is the one `zonai build` placed for this '
              'target -- overwriting it re-embeds bytes for the build host',
        );
        expect(outcome.reportedPath, outcome.expectedPath);
      });

      test('overwrites an unstamped library', () async {
        if (!_runningOnDartVm) return;

        // Every build from before stamping existed left a bare library here,
        // and so does anything a user happened to drop in the directory.
        final outcome = await plantAndRun();

        expect(outcome.kept, isFalse);
        expect(outcome.reportedPath, outcome.expectedPath);
      });

      test('overwrites a library stamped by a different release', () async {
        if (!_runningOnDartVm) return;

        final outcome = await plantAndRun(
          stamp:
              '0.0.0-not-this-release '
              '${TargetOs.current().name} ${Arch.current().name}',
        );

        expect(outcome.kept, isFalse);
      });

      test('overwrites a library stamped for a different OS', () async {
        if (!_runningOnDartVm) return;

        final otherOs = TargetOs.values.firstWhere(
          (os) => os != TargetOs.current(),
        );
        final outcome = await plantAndRun(
          stamp: '$kVersion ${otherOs.name} ${Arch.current().name}',
        );

        expect(outcome.kept, isFalse);
      });

      test(
        'overwrites a library stamped for a different architecture',
        () async {
          if (!_runningOnDartVm) return;

          final otherArch = Arch.values.firstWhere((a) => a != Arch.current());
          final outcome = await plantAndRun(
            stamp: '$kVersion ${TargetOs.current().name} ${otherArch.name}',
          );

          expect(outcome.kept, isFalse);
        },
      );

      test('extracts into an empty .zonai/lib and reports that path', () async {
        if (!_runningOnDartVm) return;

        final project = Directory(p.join(workspace.path, '$library-empty'))
          ..createSync(recursive: true);

        final result = await Process.run(probePath, [
          library,
        ], workingDirectory: project.path);

        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );
        final extracted = File(
          p.join(project.path, '.zonai', 'lib', libraryFileName),
        );
        expect(extracted.existsSync(), isTrue);
        expect(extracted.lengthSync(), greaterThan(_marker.length));
        expect(_resolve('${result.stdout}'.trim()), _resolve(extracted.path));
      });
    });
  }
}

/// Content the guard has no reason to produce, so finding it afterwards means
/// the file was left alone and finding anything else means it was rewritten.
const _marker = 'planted by native_library_extraction_compiled_e2e_test';

String get _currentStamp =>
    '$kVersion ${TargetOs.current().name} ${Arch.current().name}';

int _caseCounter = 0;

/// What the guard did with a planted library.
class _Outcome {
  const _Outcome({
    required this.reportedPath,
    required this.expectedPath,
    required this.kept,
  });

  /// The path the binary reported, so a guard that silently resolved somewhere
  /// else cannot read as a pass.
  final String reportedPath;
  final String expectedPath;

  /// Whether the planted marker is still there.
  final bool kept;
}

String _resolve(String path) => File(path).resolveSymbolicLinksSync();

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The suite compiles a binary, so it only runs under a real Dart VM -- mirrors
/// migrate_compiled_e2e_test.dart's guard.
bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');
