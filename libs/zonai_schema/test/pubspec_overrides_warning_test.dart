// dart format width=100
import 'dart:io';

import 'package:test/test.dart';

/// Issue #25 (SupposedlySam's review): a repo-root `pubspec_overrides.yaml`
/// is gitignored (`.gitignore` line 4), so `git status` never shows one --
/// including a local path override used to test an unpublished change, or
/// one left behind by any tooling that writes overrides. In one observed
/// case that silently pinned the whole
/// revali family to a stale branch and dropped 3 tests from this exact
/// suite with no red anywhere: 230 passing with the file present, 233
/// without it.
///
/// This test never fails the build -- it only makes the file's presence
/// loud in every local `dart test` run of this package, instead of silent.
void main() {
  test('warn if a stale pubspec_overrides.yaml is present (informational)', () {
    final overrides = _repoRootOverridesFile();
    if (overrides == null || !overrides.existsSync()) {
      return;
    }

    // ignore: avoid_print
    print('''

================================================================================
WARNING: ${overrides.path} exists.

That file is gitignored, so `git status` will never flag it, and it can
silently change which package versions this test suite (and any other local
command) resolves against -- e.g. a local path override left over from
testing an unpublished change elsewhere, or a branch someone pinned by hand.

If you didn't put it there on purpose for what you're doing right now,
delete it and re-resolve:

  rm ${overrides.path}
  dart pub get
================================================================================
''');
  });
}

/// Walks up from the current working directory looking for the repo root
/// (identified by `scripts.yaml`, which only exists there) and returns the
/// `pubspec_overrides.yaml` File that would sit next to it, whether or not
/// it currently exists. Returns null if the repo root can't be found within
/// a reasonable number of parent directories.
File? _repoRootOverridesFile() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}${Platform.pathSeparator}scripts.yaml').existsSync()) {
      return File('${dir.path}${Platform.pathSeparator}pubspec_overrides.yaml');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}
