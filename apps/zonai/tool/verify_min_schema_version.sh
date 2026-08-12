#!/usr/bin/env bash
# The CLI declares a floor for zonai_schema (kMinSchemaVersion) and the `zonai
# init` scaffold writes `zonai_schema: ^<floor>` into new projects. If the CLI
# ships ahead of the schema release it names, that scaffold hands people a
# pubspec pub cannot resolve -- and there is nothing in a test suite that would
# notice, because every checkout in this monorepo resolves zonai_schema by
# path.
#
# That is not hypothetical: the floor used to be kVersion itself, so the
# scaffold asked for ^0.6.2 while pub.dev's newest zonai_schema was 0.1.1.
# Nothing failed here; it failed in consumers' projects.
#
# So this asks pub.dev directly: is the version we point people at actually
# published? It does NOT check that the floor is high enough -- a floor left
# too low still fails at the consumer, and no script here can see that.
set -euo pipefail

zonai_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
const_file="$zonai_dir/lib/src/domain/schema_version/min_schema_version.dart"

if [[ ! -f "$const_file" ]]; then
  echo "FAIL: $const_file is missing -- did kMinSchemaVersion move?" >&2
  exit 1
fi

floor="$(sed -n "s/^const kMinSchemaVersion = '\([^']*\)';.*/\1/p" "$const_file")"

if [[ -z "$floor" ]]; then
  echo "FAIL: could not read kMinSchemaVersion out of $const_file." >&2
  echo "      Expected a line like: const kMinSchemaVersion = '0.2.0';" >&2
  exit 1
fi

echo "Declared zonai_schema floor: $floor"

# The scaffold's constraint is `^$floor`, so the floor itself must exist.
published="$(curl -sSL --fail "https://pub.dev/api/packages/zonai_schema" \
  | python3 -c 'import json,sys; print("\n".join(v["version"] for v in json.load(sys.stdin)["versions"]))')"

if [[ -z "$published" ]]; then
  echo "FAIL: could not read published zonai_schema versions from pub.dev." >&2
  exit 1
fi

if ! grep -qxF "$floor" <<<"$published"; then
  echo "FAIL: kMinSchemaVersion is $floor, which is NOT published on pub.dev." >&2
  echo "      \`zonai init\` writes 'zonai_schema: ^$floor', so a new project" >&2
  echo "      would fail to resolve. Publish zonai_schema $floor first, then" >&2
  echo "      release the CLI." >&2
  echo "      Published: $(tr '\n' ' ' <<<"$published")" >&2
  exit 1
fi

echo "OK: zonai_schema $floor is published."
