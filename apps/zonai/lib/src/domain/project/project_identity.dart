/// Argv that says which zonai project a spawned process belongs to.
///
/// Every worker executable is spawned from a path that is identical across
/// every zonai project on a machine (`.zonai/executables/db_config.exe`), and
/// the re-exec'd server is no better (`.zonai/zonai`, `dart run
/// .dart_tool/zonai/project_main.dart`). `ps` and Activity Monitor therefore
/// show nothing that attributes a PID to a project, and the only way to ask
/// is `lsof -a -p <pid> -d cwd`, one PID at a time — which is exactly the
/// tool you do not want to need when something is already stuck and you are
/// deciding whether it is safe to kill.
///
/// Argv is the channel because it is the one an outside observer already
/// sees, with no cooperation from the running program and no zonai CLI.
library;

import 'dart:io' as io;

import '../../deps/settings.dart';

/// The project root to advertise, resolved so that it can never fail.
///
/// [settings] is not a field read: it is `read(settingsProvider)`, and
/// `Settings.load` in turn reads the `args` scope to honour `--config`. So
/// asking for the project root pulls in a CLI argument scope that only the
/// CLI provides. Any embedder driving these spawn paths directly — the
/// native-library e2e test was the first — otherwise dies with
/// `read(ScopedRef<Args>) was called in a scope which does not contain a
/// corresponding value`.
///
/// This value exists only so a human can attribute a PID to a project.
/// **A label must never be able to break the thing it labels**, so an absent
/// or unloadable scope degrades to the working directory — which is what the
/// fallback already meant — rather than throwing. Nothing reads it back:
/// being wrong costs a less precise `ps` line, which is strictly better than
/// a process that will not start.
String projectRootForIdentity() {
  try {
    return settings.basePath ?? io.Directory.current.path;
  } on Object {
    return io.Directory.current.path;
  }
}

/// The identity flags to append to a spawn's argv.
///
/// Appended, never prepended: `Args.parse` treats leading bare words as the
/// command path and stops at the first `-`-prefixed token, so trailing the
/// caller's own arguments keeps this from being read as part of, say,
/// `serve --port 7717`. It is inert to the spawned program either way —
/// generated worker `main()`s take no parameters, and `Args` only surfaces
/// keys something reads by name.
List<String> projectIdentityArgs({String? worker}) => [
  '--zonai-project=${projectRootForIdentity()}',
  if (worker != null) '--zonai-worker=$worker',
];
