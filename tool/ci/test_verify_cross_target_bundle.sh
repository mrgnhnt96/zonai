#!/usr/bin/env bash
# Controls for step 3 of verify_cross_target_bundle.sh.
#
# That step was narrowed after v0.8.1 (run 32312355513) went red for a bundle
# that was behaving correctly. A narrowed check is worth exactly as much as the
# proof that it still fails where it should, so this drives the real script --
# not a copy of its logic -- against a synthetic bundle whose `zonai` is a shell
# shim reproducing the one behaviour under test: a host binary keeps a library
# stamped with its OWN version and overwrites one stamped with any other, which
# is what `hasCurrentNativeLibraryStamp` does.
#
# Three cases, and the middle one is the regression:
#   1. versions agree, library untouched  -> pass, identity asserted
#   2. versions differ, library replaced  -> pass, identity SKIPPED and said so
#   3. versions agree, library replaced   -> FAIL (the bug the step exists for)
#
# Case 3 is why this file exists: without it, "we stopped failing" and "we
# stopped checking" are the same observation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNDER_TEST="${ROOT}/tool/ci/verify_cross_target_bundle.sh"

case "$(uname -s)" in
  Darwin) suffix=.dylib ;;
  Linux) suffix=.so ;;
  *) echo "unsupported host for this harness" >&2; exit 1 ;;
esac

# The harness needs to produce real object files. Everywhere this is meant to
# run has a compiler; if one ever does not, say so in the shape this repo uses
# for an unrun check rather than turning `static` red over the toolchain.
if ! command -v cc >/dev/null 2>&1; then
  echo "  NOT CHECKED: no C compiler, so step 3's controls did not run. That is" >&2
  echo "  not a pass -- nothing here verified that the narrowed check still" >&2
  echo "  fails a real replacement." >&2
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A genuine object file for THIS platform, so the step's platform assertion --
# which is not what is being tested and must keep passing -- reads something
# real rather than a text file.
printf 'int zonai_probe(void) { return 1; }\n' > "$work/a.c"
printf 'int zonai_probe(void) { return 2; }\n' > "$work/b.c"
cc -shared -fPIC -o "$work/libA${suffix}" "$work/a.c" 2>/dev/null \
  || cc -dynamiclib -o "$work/libA${suffix}" "$work/a.c"
cc -shared -fPIC -o "$work/libB${suffix}" "$work/b.c" 2>/dev/null \
  || cc -dynamiclib -o "$work/libB${suffix}" "$work/b.c"

# build a bundle: $1 dir, $2 host binary version, $3 stamp version
make_bundle() {
  local dir="$1" host_version="$2" stamp_version="$3" force_replace="${4:-0}"
  rm -rf "$dir"
  mkdir -p "$dir/.zonai/executables" "$dir/.zonai/lib" "$dir/.zonai/data"
  cp "$work/libA${suffix}" "$dir/.zonai/lib/libresqlite${suffix}"
  printf '%s macos arm64\n' "$stamp_version" \
    > "$dir/.zonai/lib/libresqlite${suffix}.stamp"
  printf 'snapshot\n' > "$dir/.zonai/executables/db_rules.aot"
  printf '%s\n' "$host_version" > "$dir/VERSION"
  # Case 3 needs a host that clobbers the library even though the stamp says it
  # should not -- i.e. the actual defect, rather than the version skew.
  [[ "$force_replace" == "1" ]] && : > "$dir/.zonai/FORCE_REPLACE"

  # The shim. `keeps` decides whether this host installs its own copy, which is
  # the real binary's rule: keep only a library stamped for MY version.
  cat > "$dir/zonai" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
here="\$(cd "\$(dirname "\$0")" && pwd)"
case "\${1:-}" in
  version)
    echo "Zonai: v${host_version}"
    echo "Ops/rules: worker IPC"
    ;;
  db)
    stamp="\$(awk '{print \$1; exit}' "\$here/.zonai/lib/libresqlite${suffix}.stamp" 2>/dev/null || true)"
    if [[ "\$stamp" != "${host_version}" || -f "\$here/.zonai/FORCE_REPLACE" ]]; then
      cp "${work}/libB${suffix}" "\$here/.zonai/lib/libresqlite${suffix}"
    fi
    : > "\$here/.zonai/data/app.sqlite"
    echo "Applied pending SQL migrations"
    ;;
  ping)
    if grep -q 'not a snapshot' "\$here/.zonai/executables/db_rules.aot" 2>/dev/null; then
      echo "db_rules.aot would not spawn"
    fi
    echo "Ping rules succeeded"
    echo "Ping operation succeeded"
    ;;
esac
SHIM
  chmod +x "$dir/zonai"
}

# $1 label, $2 host version, $3 stamp version, $4 expected exit, $5 grep or -
run_case() {
  local label="$1" host="$2" stamp="$3" want_exit="$4" want_text="$5" force="${6:-0}"
  local dir="$work/bundle"
  make_bundle "$dir" "$host" "$stamp" "$force"

  local log="$work/out.txt" got=0
  bash "$UNDER_TEST" "$dir" - "$dir/VERSION" > "$log" 2>&1 || got=$?

  if [[ "$got" != "$want_exit" ]]; then
    echo "FAIL  ${label}: exit ${got}, wanted ${want_exit}" >&2
    sed 's/^/      /' "$log" >&2
    return 1
  fi
  if [[ "$want_text" != "-" ]] && ! grep -q "$want_text" "$log"; then
    echo "FAIL  ${label}: output did not contain '${want_text}'" >&2
    sed 's/^/      /' "$log" >&2
    return 1
  fi
  echo "ok    ${label}"
}

failed=0
run_case "versions agree and nothing moved -> identity asserted" \
  0.8.2 0.8.2 0 "byte-identical to what shipped" || failed=1

run_case "versions differ -> identity skipped, and it says so" \
  0.7.1 0.8.2 0 "SKIPPED" || failed=1

# The one that matters. Same shape as case 1, but the host replaces the library
# anyway -- which is the real defect this step guards. If narrowing the check
# ever swallows this, the step is decoration.
run_case "versions agree but the library was replaced -> still FAILS" \
  0.8.2 0.8.2 1 "changed while the bundle ran" 1 || failed=1

if [[ "$failed" != "0" ]]; then
  echo "" >&2
  echo "step 3's controls did not hold." >&2
  exit 1
fi
echo "  ok: step 3 skips only version-skew, and still fails a real replacement"
