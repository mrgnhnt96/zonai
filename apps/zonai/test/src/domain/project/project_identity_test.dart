import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/project/project_identity.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';

/// Settings that actually carry a `basePath` — which takes three scopes.
///
/// Worth spelling out, because the shape of it *is* the bug. Overriding
/// `settingsProvider` is not enough on its own:
///
/// * `Settings.load` reads `args` to honour `--config`, so without
///   `argsProvider` the override throws — a CLI-only dependency inherited by
///   every caller that never asked for one. That is the regression.
/// * `basePath` is only populated when a `zonai.yml` genuinely exists at the
///   path (`settings.dart:143`); with no file, `Settings.load` returns the
///   defaults, whose `basePath` is null. So the fixture needs a real file on
///   a memory filesystem, or the "resolves" test passes for the wrong reason
///   by falling back to the working directory.
Set<ScopedRef<dynamic>> _resolvableSettings(String basePath) {
  final memoryFs = MemoryFileSystem();
  memoryFs.file(memoryFs.path.join(basePath, 'zonai.yml'))
    ..createSync(recursive: true)
    // A mapping, not an empty file: `loadYaml('')` returns null and the
    // very next line indexes it, so an empty zonai.yml throws rather than
    // yielding defaults.
    ..writeAsStringSync('port: 8080\n');
  return {
    fsProvider.overrideWith(() => memoryFs),
    argsProvider.overrideWith(() => const Args()),
    settingsProvider.overrideWith(() => Settings.load(basePath)),
  };
}

void main() {
  group('projectRootForIdentity', () {
    test('uses the project root when settings resolve', () {
      runScoped(
        () => expect(projectRootForIdentity(), '/projects/my_app'),
        values: _resolvableSettings('/projects/my_app'),
      );
    });

    test('falls back to the working directory when the args scope is absent, '
        'rather than throwing', () {
      // THE REGRESSION. `settings` is `read(settingsProvider)`, and
      // `Settings.load` reads the `args` scope to honour `--config`, so
      // asking for the project root pulled a CLI-only dependency into every
      // worker spawn. Any embedder driving Mailman outside the CLI died with
      // `read(ScopedRef<Args>) was called in a scope which does not contain a
      // corresponding value` -- caught by the native-library e2e test, which
      // spawns a real worker with no args scope.
      //
      // Asserted with a control, so the test cannot pass for the wrong
      // reason: reading `settings` here really does throw, and
      // `projectRootForIdentity` really does survive it.
      expect(() => settings, throwsA(isA<StateError>()));
      expect(projectRootForIdentity(), io.Directory.current.path);
    });

    test('a label must never break the thing it labels', () {
      // Same guarantee stated as the invariant rather than the incident: no
      // scope at all, and this still answers. Nothing reads the value back, so
      // a less precise `ps` line is always the better failure than a worker
      // that will not spawn.
      expect(projectIdentityArgs, returnsNormally);
      expect(() => runScoped(projectIdentityArgs), returnsNormally);
    });
  });

  group('projectIdentityArgs', () {
    test('names the project, and the worker role when there is one', () {
      runScoped(() {
        expect(projectIdentityArgs(), ['--zonai-project=/projects/my_app']);
        expect(projectIdentityArgs(worker: 'CONFIG'), [
          '--zonai-project=/projects/my_app',
          '--zonai-worker=CONFIG',
        ]);
      }, values: _resolvableSettings('/projects/my_app'));
    });

    test('every flag is --key=value, so Args.parse leaves it inert', () {
      // The flags are appended to a caller's own argv. `Args.parse` stops
      // treating bare words as the command path at the first `-`-prefixed
      // token, so a `--key=value` shape can never be mistaken for part of
      // `serve --port 7717`. A bare word or a space-separated pair could.
      for (final arg in projectIdentityArgs(worker: 'CRON')) {
        expect(arg, startsWith('--'));
        expect(arg, contains('='));
        expect(arg, isNot(contains(' ')));
      }
    });
  });
}
