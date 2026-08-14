// dart format width=100
import 'dart:io';

import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';

/// Env escape hatch: keep Mailman workers even when registries are linked.
const kForceWorkersEnv = 'ZONAI_FORCE_WORKERS';

/// In-process worker registries for project-linked binaries.
///
/// When set (by generated [project_main]), [ZonaiDb] calls `dispatch` directly
/// instead of Mailman IPC for ops/rules/extensions — unless [forceWorkers].
abstract final class HostWorkerRegistries {
  static DbOperations? operations;
  static DbRules? rules;
  static DbExtensions? extensions;

  static void clear() {
    operations = null;
    rules = null;
    extensions = null;
  }

  static bool get forceWorkers {
    final value = Platform.environment[kForceWorkersEnv];
    return value == '1' || value == 'true';
  }

  static bool get useInProcessOperations => !forceWorkers && operations != null;
  static bool get useInProcessRules => !forceWorkers && rules != null;
  static bool get useInProcessExtensions => !forceWorkers && extensions != null;

  static bool get hasOperations => operations != null;
  static bool get hasRules => rules != null;
  static bool get hasExtensions => extensions != null;
}
