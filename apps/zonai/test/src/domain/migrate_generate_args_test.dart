import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/migrate.dart';
import 'package:zonai/src/domain/settings.dart';

import '../../support/temp_directory.dart';

/// The value of the option named [flag] in [args].
String _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  expect(index, isNot(-1), reason: '$flag is not in $args');
  return args[index + 1];
}

void main() {
  late io.Directory projectRoot;

  setUp(() {
    // `systemTemp` is deliberate rather than incidental: on macOS it is
    // `/var/folders/...`, a symlink to `/private/var/folders/...`, and on a
    // Windows runner it is an 8.3 short name for a longer real one. Both are
    // hosts where a path and its resolved form are different strings for the
    // same directory, which is the condition this test is about.
    projectRoot = io.Directory.systemTemp.createTempSync('zonai_gen_args_');
    io.File(
      p.join(projectRoot.path, 'zonai.yaml'),
    ).writeAsStringSync('name: test\n');
    io.Directory(
      p.join(projectRoot.path, 'lib', 'src', 'schemas'),
    ).createSync(recursive: true);
  });

  tearDown(() {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  Future<List<String>> generateArgs() async {
    final settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
    return runScoped(
      () => Migrate().generateArgs(name: 'initialize', dryRun: false),
      values: {
        fsProvider.overrideWith(LocalFileSystem.new),
        settingsProvider.overrideWith(() => settings),
      },
    );
  }

  // raindrop_cli's `SnapshotRunner.packageUri` asks `p.isWithin(<package
  // root>/lib, <schema file>)` -- a pure string compare -- and it finds that
  // package root by walking UP from the `--config` directory to
  // `package_config.json`. So the two paths zonai hands it have to be
  // spelled the same way. Resolving one and not the other is what produced
  // `Schema file "..." is not inside a package's lib/ directory` for ten
  // tests in the `cli (windows-latest)` job, and the same message on macOS
  // before that.
  test('--config and --schemas are expressed against one real root', () async {
    final args = await generateArgs();
    final realRoot = projectRoot.resolveSymbolicLinksSync();

    expect(
      p.isWithin(realRoot, _valueOf(args, '--config')),
      isTrue,
      reason:
          '--config is spelled differently from the project root raindrop '
          'will resolve packages against',
    );
    expect(
      p.isWithin(realRoot, _valueOf(args, '--schemas')),
      isTrue,
      reason:
          '--schemas is spelled differently from the project root raindrop '
          'will resolve packages against',
    );
  });

  test('--config keeps naming a file that cannot exist', () async {
    final config = _valueOf(await generateArgs(), '--config');

    expect(p.basename(config), '.raindrop-config-disabled.yaml');
    expect(
      io.File(config).existsSync(),
      isFalse,
      reason:
          'the point of this path is that raindrop_cli finds no config there '
          'and falls back to nothing, rather than to a stray raindrop.yaml in '
          'the working directory',
    );
  });

  test('--schemas names the schemas directory', () async {
    final schemas = _valueOf(await generateArgs(), '--schemas');

    expect(p.split(schemas).skip(p.split(schemas).length - 3), [
      'lib',
      'src',
      'schemas',
    ]);
    expect(io.Directory(schemas).existsSync(), isTrue);
  });
}
