#!/usr/bin/env bash
# Two cheap guards on the stress harness, both from things that actually broke.
#
# 1. The fixture's AppConfig secrets. The harness could not BOOT on main until
#    2026-08-18: AppConfig.validate grew a 32-character minimum for HS256 keys
#    and this fixture still carried a 22- and a 23-character secret, so every
#    run died in the config worker with "AppConfig has missing required
#    fields". A length assertion, not a real boot -- a boot is a minute of
#    build. So it does NOT check that the fixture is otherwise valid.
#
# 2. thresholds.json. If it stops parsing or loses its cells, the error-rate
#    gate silently checks nothing.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}/stress"

python3 - <<'PY'
import io
import json
import re
import sys

failed = False

config = io.open("fixture/lib/src/config/app_config.dart").read()
secrets = re.findall(r"(passwordSecret|jwtSecret):\s*'([^']*)'", config)
if not secrets:
    print("no secrets matched in fixture app_config.dart -- did the shape change?")
    failed = True
for name, value in secrets:
    if len(value) < 32:
        print(f"  {name} is {len(value)} chars; AppConfig.validate requires 32 (HS256)")
        failed = True
    else:
        print(f"  ok: {name} is {len(value)} chars")

doc = json.load(io.open("thresholds.json"))
if not doc.get("cells"):
    print("thresholds.json has no cells -- the gate would check nothing")
    failed = True
elif doc["policy"]["p99Gated"] is not False:
    print("thresholds.json now gates p99. Recalibrate first; see README 'Thresholds'.")
    failed = True
else:
    print(f"  ok: thresholds.json parses, {len(doc['cells'])} cell(s), p99 not gated")

sys.exit(1 if failed else 0)
PY
