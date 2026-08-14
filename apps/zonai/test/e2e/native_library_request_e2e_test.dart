import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

/// End-to-end proof of the "ask your spawner for the native library"
/// protocol added to fix cross-compiled workers embedding a wrong-platform
/// copy of resqlite/Argon2 (see resqlite_native.dart, argon2_native.dart,
/// and mailman.dart's `_provideNativeLibrary`).
///
/// No production worker calls into that protocol today -- see the design
/// notes on argon2_native.dart/resqlite_native.dart -- so this test spawns
/// a tiny standalone fixture worker (test/e2e/fixtures/
/// native_library_probe_worker.dart) whose only job is to ask its spawner
/// to resolve a native library and report the result, with **no**
/// self-extraction fallback of its own. That makes a successful reply an
/// unambiguous proof that:
///   1. the worker-side `nativeLibraryHost`/`NativeLibraryRequest` plumbing
///      wired into `MessageHandler.listen` actually sends the request, and
///   2. the real, production `Mailman._provideNativeLibrary` handler
///      answers it correctly against the spawner's own copy of the
///      library -- including recovering after the shared on-disk copy the
///      worker would otherwise reuse has been deleted first.
void main() {
  group('native library request protocol e2e', () {
    late String workerExePath;
    late Directory tempDir;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      tempDir = Directory.systemTemp.createTempSync(
        'zonai_native_library_probe_',
      );
      workerExePath = p.join(tempDir.path, 'native_library_probe');

      final zonaiPackageDir = Directory.current;
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        '-D__ZONAI_COMPILED__=true',
        p.join('test', 'e2e', 'fixtures', 'native_library_probe_worker.dart'),
        '-o',
        workerExePath,
      ], workingDirectory: zonaiPackageDir.path);
      if (compile.exitCode != 0) {
        throw StateError(
          'dart compile exe failed:\n${compile.stderr}\n${compile.stdout}',
        );
      }
    });

    tearDownAll(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final library in NativeLibraryKind.values) {
      test('a worker with no self-extraction fallback of its own resolves '
          '${library.name} by asking its spawner, even after the shared '
          'on-disk copy is deleted first', () async {
        if (!_runningOnDartVm) return;

        await runMergedScopedFuture(() async {
          // The dev-mode "shared install path" this test's own process
          // (acting as the spawner, uncompiled -- kIsCompiled is false
          // for `dart test`) resolves to for this library. Deleting it
          // first proves recovery: if the worker silently trusted a
          // stale/missing copy instead of asking, there would be nothing
          // to recover from.
          final sharedFile = File(
            p.join(
              Directory.current.path,
              '.dart_tool',
              'lib',
              _devLibraryFileName(library),
            ),
          );
          if (sharedFile.existsSync()) {
            sharedFile.deleteSync();
          }

          final mailman = _ProbeMailman(workerExePath);
          try {
            final response = await mailman.send<NativeLibraryResponse>(
              UnknownRequest(
                path: 'request/.native_library_probe/${library.name}',
                id: 'probe-${library.name}',
                payload: const {},
              ),
            );

            final resolvedFile = File(response.libraryPath);
            expect(
              resolvedFile.existsSync(),
              isTrue,
              reason:
                  'spawner reported ${response.libraryPath}, which should '
                  'have been (re-)extracted on disk',
            );
            expect(
              resolvedFile.lengthSync(),
              greaterThan(0),
              reason: 'recovered native library file must not be empty',
            );

            // The spawner's own answer must have (re-)populated the
            // shared path we deleted above -- proving real recovery, not
            // just an isolated extraction to some other throwaway
            // location.
            expect(
              sharedFile.existsSync(),
              isTrue,
              reason:
                  'answering the request should (re-)populate the shared '
                  'install path the deleted file used to occupy',
            );
          } finally {
            await mailman.kill();
          }
        }, override: _scopeOverrides);
      }, timeout: const Timeout(Duration(minutes: 1)));
    }
  });
}

/// Mirrors resqlite_native.dart / argon2_ffi.dart's platform-specific
/// shared-library file naming for the dev-mode ("uncompiled") sync target.
String _devLibraryFileName(NativeLibraryKind library) {
  final base = switch (library) {
    NativeLibraryKind.resqlite => 'resqlite',
    NativeLibraryKind.argon2 => 'argon2sodium',
  };
  return switch (Platform.operatingSystem) {
    'macos' => 'lib$base.dylib',
    'linux' => 'lib$base.so',
    'windows' => '$base.dll',
    final os => throw UnsupportedError('Unsupported platform: $os'),
  };
}

class _ProbeMailman extends Mailman<Request, Response> {
  _ProbeMailman(String executablePath)
    : super(
        debugName: 'NATIVE_LIBRARY_PROBE',
        executablePath: executablePath,
        fromJson: (json) => Response(
          path: json['path'] as String,
          id: json['id'] as String,
          payload: json,
        ),
      );
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Set<ScopedRef<dynamic>> get _scopeOverrides => {
  fsProvider.overrideWith(LocalFileSystem.new),
  loggerProvider.overrideWith(() => Logger(level: .error)),
  settingsProvider,
  processProvider,
  mutationsProvider,
  cleanUpProvider,
  executableStopProvider,
};
