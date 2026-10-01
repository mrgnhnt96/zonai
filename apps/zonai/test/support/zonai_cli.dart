import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs the zonai CLI from source, compiled once and shared by every suite.
///
/// The e2e suites used to run `dart run bin/zonai.dart` for each command, and
/// `dart run` on a file caches nothing: every call compiled the whole CLI to
/// kernel before doing any work. That cost ~14s per call on a dev machine and
/// more on a CI runner, at three or more calls per suite across 25 suites.
/// It was most of the `cli` job's wall-clock and the reason the Windows leg
/// hit its 45-minute ceiling.
///
/// Here the CLI is compiled once to `.dart_tool/zonai_test_cli-<sdk>.dill`
/// and the result is reused until any file it was compiled from changes. The
/// compiler's depfile lists those files, so an edit to zonai, a workspace
/// library, or `lib/gen` triggers a fresh compile, the same as `dart run`.
/// The SDK version is in the name because a kernel only loads on the SDK
/// that built it, and an SDK upgrade touches none of those files.
///
/// The kernel sits directly under `apps/zonai/.dart_tool` on purpose: the
/// native loaders look for `lib/gen/native` next to [Platform.script]'s parent
/// (see `resqlite_native.dart`), and `.dart_tool/../lib` is where it is for
/// `bin/zonai.dart` too. Its name must not end in `.snapshot`, which zonai
/// reads as a `dart run zonai` snapshot and re-execs from source.
Future<ProcessResult> runZonaiCli(
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
}) async {
  final kernel = await _kernel;
  return Process.run(
    Platform.resolvedExecutable,
    [kernel, ...args],
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// Once per test isolate. Suites run as separate isolates, so sharing across
/// them goes through the file on disk.
final Future<String> _kernel = _compileIfStale();

Future<String> _compileIfStale() async {
  // Suites run with apps/zonai as the working directory.
  final packageRoot = Directory.current.path;
  final sdk = Platform.version.split(' ').first;
  final kernel = p.join(packageRoot, '.dart_tool', 'zonai_test_cli-$sdk.dill');
  final depfile = '$kernel.d';
  if (_isFresh(kernel, depfile)) return kernel;

  // One compile at a time. Without the lock, two suites starting together
  // both compiled, and on Windows the later rename failed with "Access is
  // denied": the first suite was already running a CLI from that kernel, and
  // Windows will not replace a file another process has open (cli windows
  // shard 3 on run 36885995810). Closing the file releases the lock.
  //
  // POSIX locks belong to the process, so suites in one test runner are not
  // serialized by this there. They do not need to be: a rename over an open
  // file is fine on POSIX, and two identical compiles cost only time.
  final lock = await File('$kernel.lock').open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    // Another suite may have compiled it while this one waited.
    if (_isFresh(kernel, depfile)) return kernel;
    return await _compile(packageRoot, kernel: kernel, depfile: depfile);
  } finally {
    await lock.close();
  }
}

Future<String> _compile(
  String packageRoot, {
  required String kernel,
  required String depfile,
}) async {
  // Compile beside the target and rename into place, so a suite running
  // concurrently never loads a half-written kernel.
  final tag = '$pid-${Object().hashCode.toRadixString(36)}';
  final tempKernel = '$kernel.$tag.tmp';
  final tempDepfile = '$depfile.$tag.tmp';
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'kernel',
    p.join(packageRoot, 'bin', 'zonai.dart'),
    '--output',
    tempKernel,
    '--depfile',
    tempDepfile,
  ], workingDirectory: packageRoot);
  if (result.exitCode != 0) {
    throw StateError(
      'Could not compile the zonai CLI for the e2e suites:\n'
      '${result.stderr}\n${result.stdout}',
    );
  }

  // Kernel first: a reader that sees the new kernel with the old depfile
  // compares old inputs against a newer kernel, which can only say fresh
  // for a kernel that is.
  try {
    File(tempKernel).renameSync(kernel);
  } on FileSystemException {
    // Windows, with a stale kernel still loaded by a CLI some other suite is
    // running. Its replacement waits for a later compile; this suite runs
    // from its own copy.
    File(tempDepfile).deleteSync();
    return tempKernel;
  }
  File(tempDepfile).renameSync(depfile);
  return kernel;
}

bool _isFresh(String kernel, String depfile) {
  final kernelFile = File(kernel);
  final depFile = File(depfile);
  if (!kernelFile.existsSync() || !depFile.existsSync()) return false;

  final builtAt = kernelFile.lastModifiedSync();
  final inputs = _depfileInputs(depFile.readAsStringSync());
  if (inputs.isEmpty) return false;
  for (final input in inputs) {
    final file = File(input);
    // A deleted input means the sources moved on from this kernel.
    if (!file.existsSync()) return false;
    if (!file.lastModifiedSync().isBefore(builtAt)) return false;
  }
  return true;
}

/// The inputs of a `dart compile --depfile` file: `output: in1 in2 ...`,
/// where a space inside a path is written `\ ` and a backslash `\\`. A lone
/// backslash before anything else is a Windows separator, kept as written.
List<String> _depfileInputs(String contents) {
  final colon = contents.indexOf(': ');
  if (colon == -1) return const [];

  final inputs = <String>[];
  final current = StringBuffer();
  final body = contents.substring(colon + 2);
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    final next = i + 1 < body.length ? body[i + 1] : null;
    if (char == r'\' && (next == ' ' || next == r'\')) {
      current.write(body[++i]);
    } else if (char == ' ' || char == '\n' || char == '\r') {
      if (current.isNotEmpty) inputs.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) inputs.add(current.toString());
  return inputs;
}
