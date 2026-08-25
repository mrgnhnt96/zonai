#!/usr/bin/env bash
# A jaspr component that returns `Component.fragment(...)` cannot be REMOVED once mounted:
# the teardown throws
#
#   Assertion failed: "Cannot remove fragment from a different parent."
#     at DomRenderFragment.removeChildren$1 <- _FragmentElement.detachRenderObject$0
#
# which aborts the rebuild half-done and LEAVES THE COMPONENT ON SCREEN. It presents as
# "the close button does nothing" -- the handler fires every time, the teardown is what
# fails. Invisible to `dart analyze` and to component tests; it only appears in a browser
# console. It cost a full debugging cycle on MintBoundTokenDialog (2026-08-24).
#
# A fragment root is only dangerous when something REMOVES it, so this pairs the two:
# a fragment-rooted build() AND at least one call site behind an `if`. A component that is
# always mounted and hides itself internally (HomeSettingsOverlay) is fine and is not
# flagged.
#
# Fix: give it ONE root element. A plain wrapper div with no z-index and no transform
# creates no stacking context, so `position: fixed` children still resolve against the
# viewport.
#
# WHAT THIS DOES NOT CATCH:
#   * a conditional render written some other way -- a ternary, a `?:`, a list built
#     elsewhere, or a parent that swaps children without a literal `if (`;
#   * a call site outside apps/web/lib;
#   * a fragment root in a component that is removed by its PARENT being removed.
# It checks a shape, not the property. Absence of a hit is not proof of safety.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail=0
files=$(git ls-files 'apps/web/lib/*.dart' 'apps/web/lib/**/*.dart')

for file in $files; do
  names=$(grep -oE 'class (_?[A-Za-z0-9]+) extends (StatelessComponent|StatefulComponent)' "$file" \
          | awk '{print $2}' || true)
  [ -z "$names" ] && continue
  for name in $names; do
    body=$(awk -v n="$name" '
      $0 ~ ("^class " n "( |$)") || $0 ~ ("^class " n "State ") { inclass=1 }
      inclass && /Component build\(/ { inbuild=1 }
      inbuild { print; if ($0 ~ /^  }$/) { inbuild=0; inclass=0 } }
    ' "$file")
    printf '%s' "$body" | grep -q 'return Component\.fragment' || continue

    # is it ever rendered conditionally?
    conditional=$(grep -rn -B1 -E "^\s+(const )?${name}\(" $files 2>/dev/null \
                  | grep -E "if \(|\? " | head -3 || true)
    [ -z "$conditional" ] && continue

    echo "ERROR: $file: ${name}.build() returns Component.fragment AND is rendered conditionally:"
    printf '%s\n' "$conditional" | sed 's/^/         /'
    echo "       Give it ONE root element. See the header of $0."
    fail=1
  done
done

[ "$fail" -ne 0 ] && exit 1
echo "ok: no conditionally-rendered component roots a Component.fragment"
