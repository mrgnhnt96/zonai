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
set -euo pipefail

schema_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d)"
trap 'rm -rf "$scratch_dir"' EXIT

mkdir -p "$scratch_dir/lib/src/schemas" "$scratch_dir/bin"

cat > "$scratch_dir/pubspec.yaml" << EOF
name: zonai_schema_client_safe_check
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${schema_dir}
  # Simulates Drift (drift_flutter >=0.3.0 depends on sqlite3 ^3.0.0) -- the
  # exact conflict from issue #24. If zonai_schema ever regains a regular
  # (non-dev) dependency on 'sqlite3: <3.0.0', this line alone makes pub's
  # version solver fail before the compile check below even runs.
  sqlite3: ^3.0.0
EOF

cat > "$scratch_dir/lib/src/schemas/users.dart" << 'EOF'
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
EOF

cat > "$scratch_dir/bin/run.dart" << 'EOF'
import 'package:zonai_schema_client_safe_check/src/schemas/users.dart' as r0;

void main() {
  print(r0.users);
}
EOF

cd "$scratch_dir"
if ! dart pub get > pub_get.log 2>&1; then
  echo "zonai_schema failed to resolve for a client with NO sqlite3 dependency" >&2
  echo "(e.g. a Flutter app also using Drift -- see issue #24). Output:" >&2
  cat pub_get.log >&2
  exit 1
fi

if ! dart run bin/run.dart > run.log 2>&1; then
  echo "zonai_schema resolved but a schema file importing zonai_schema.dart" >&2
  echo "failed to run for a client with NO sqlite3 dependency (see issue #24)." >&2
  echo "Output:" >&2
  cat run.log >&2
  exit 1
fi

echo "zonai_schema resolves and runs cleanly for a client with no sqlite3 dependency at all"
