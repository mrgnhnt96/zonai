#!/usr/bin/env bash
# Regression check for issue #24: a client that only builds queries and
# schemas (Where, Eq, Update, Table, column builders, etc.) must be able to
# depend on zonai_schema WITHOUT sqlite3 anywhere in its own dependency tree.
#
# `pub get` succeeding is not enough on its own -- it only proves version
# solving, not that the code actually compiles. `export 'foo.dart' show X;`
# only filters which NAMES get re-exported; the compiler (dart run/dart
# compile, not dart analyze) still has to fully resolve every file in an
# unrestricted `export` chain reachable from an entrypoint. A first pass of
# this fix moved sqlite3 to a dev_dependency and stopped there -- `pub get`
# for a scratch client passed, but actually importing zonai_schema.dart and
# using Table/table() still failed to compile, because several internal
# files (false_delegate.dart, schema_shape_from_table.dart, db_operations.dart,
# db_rules.dart) imported the WHOLE raindrop_sqlite.dart barrel -- which
# unconditionally exports sqlite_delegate.dart -- when they only needed
# SQLiteDialect or a couple of pure-Dart transformer classes. So this script
# does not just resolve dependencies: it writes a real schema file and runs
# a script that imports it, the same way an end-user project would.
#
# TWO scenarios, because they fail differently and one does not imply the
# other:
#
#   drift  -- client depends on sqlite3 ^3.0.0. Catches a regained regular
#             (non-dev) 'sqlite3: <3.0.0' dep at version-solve time.
#   bare   -- client depends on NO sqlite3 at all. Catches an internal file
#             importing a barrel whose export chain reaches sqlite_delegate.dart,
#             or the vendored ddl.dart entrypoint reaching sqlite3 at all.
#
# The 'drift' scenario alone reported success while three internal files
# (tables/table.dart, tables/auth_table.dart, operations/table_operations.dart)
# imported the wide raindrop_sqlite.dart barrel, because sqlite3 WAS resolvable
# in that client -- just a different major. It takes the 'bare' scenario to
# make an unresolvable import actually fail.
set -euo pipefail

schema_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# $1 = scenario name, $2 = extra dependency lines (may be empty)
run_scenario() {
  local scenario="$1"
  local extra_deps="$2"
  local scratch_dir
  scratch_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$scratch_dir'" RETURN

  mkdir -p "$scratch_dir/lib/src/schemas" "$scratch_dir/bin"

  cat > "$scratch_dir/pubspec.yaml" << EOF
name: zonai_schema_client_safe_check
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${schema_dir}
${extra_deps}
EOF

  cat > "$scratch_dir/lib/src/schemas/users.dart" << 'DART'
import 'package:zonai_schema/zonai_schema.dart';

class User {
  const User({required this.name, this.id});

  final int? id;
  final String name;
}

class UserSchema extends Table<User> {
  UserSchema(super.$)
      : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
        name = $.text('name', (s) => s.name);

  @override
  User fromRow(RowReader read) => User(id: read(id), name: read(name));

  final ColumnType<int?> id;
  final ColumnType<String> name;
}

final users = table('users', UserSchema.new);
DART

  # Imports BOTH entrypoints an end-user project actually loads:
  #
  #   zonai_schema.dart -- what the user's schema files import.
  #   ddl.dart          -- what raindrop_cli's DdlRunner spawns with
  #                        Isolate.spawnUri during `zonai migrate`. It resolves
  #                        the driver package root's own lib/ddl.dart, and
  #                        zonai passes `--driver zonai_schema`, so this file
  #                        is loaded inside the user's project too.
  #
  # ddl.dart is here because it regressed while only the barrel was covered:
  # re-vendoring raindrop picked up an unrestricted export of the vendored
  # sqlite_schema_inspector.dart, which imports package:sqlite3. Nothing
  # called the inspector and this script stayed green, because the barrel's
  # chain never reaches ddl.dart -- but the compiler resolves every file in
  # an unrestricted export chain, so every `zonai migrate` died with
  # `IsolateSpawnException: ... Couldn't resolve the package 'sqlite3'`.
  # Importing it is enough to catch that: the failure is at compile time,
  # not at call time.
  cat > "$scratch_dir/bin/run.dart" << 'DART'
import 'package:zonai_schema/ddl.dart' as ddl;
import 'package:zonai_schema_client_safe_check/src/schemas/users.dart' as r0;

void main() {
  print(r0.users);
  // Referenced, never called: `main` starts a ReceivePort server that never
  // returns. Resolving the import is the whole check.
  print(ddl.main is Function);
}
DART

  cd "$scratch_dir"
  if ! dart pub get > pub_get.log 2>&1; then
    echo "[$scenario] zonai_schema failed to RESOLVE (see issue #24). Output:" >&2
    cat pub_get.log >&2
    return 1
  fi

  if ! dart run bin/run.dart > run.log 2>&1; then
    echo "[$scenario] zonai_schema resolved but a client importing" >&2
    echo "zonai_schema.dart and ddl.dart failed to RUN (see issue #24). Output:" >&2
    cat run.log >&2
    return 1
  fi

  echo "[$scenario] ok"
}

# Simulates Drift (drift_flutter >=0.3.0 depends on sqlite3 ^3.0.0) -- the exact
# conflict from issue #24. If zonai_schema ever regains a regular (non-dev)
# dependency on 'sqlite3: <3.0.0', this makes pub's version solver fail.
run_scenario drift '  sqlite3: ^3.0.0'

# No sqlite3 anywhere in the client's tree. This is the scenario that actually
# proves the export chains are clean: with sqlite3 unresolvable, any internal
# file reaching sqlite_delegate.dart fails to compile.
run_scenario bare ''

echo "zonai_schema resolves and runs cleanly both alongside sqlite3 3.x and with no sqlite3 at all"
