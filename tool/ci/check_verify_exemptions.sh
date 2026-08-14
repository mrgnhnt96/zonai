#!/usr/bin/env bash
# Re-ask every exemption in .game_loop/verify.yaml, on a clock.
#
# THE FAILURE THIS PREVENTS, measured 2026-08-13 on 02cfcef: verify.yaml downgraded five rules from
# `dart test` to `dart analyze` because the tests "currently fail locally for pre-existing reasons".
# That was true when written. Nothing ever re-asked. All five had since started passing -- so a real
# check had been silently replaced by one that cannot fail for the reason that matters, and the prose
# above them still asserted a failure that no longer happened. A sixth (`dart analyze` on apps/server
# being "not usable ... tracked separately") had gone the same way. That is not a bug in six entries.
# It is what an exemption with no expiry date does, given time.
#
# WHAT THIS IS: a rule that is EXEMPT -- because every command it runs is analyze-only, or because
# its justification rests on a time-bound claim -- must carry a marker in its comment block:
#
#     # RECHECK 2026-11-11 -- <the real check to re-run, and what to do if it now passes>
#     # RECHECK never -- <why this is structural, not a temporary downgrade>
#
# A dated marker fails once the date passes. `never` never fails, but it is COUNTED and PRINTED on
# every run, so a permanent exemption stays visible instead of dissolving into the file. The date is
# capped at 180 days out, so "RECHECK 2099-01-01" is not an available dodge.
#
# WHAT RUNS IT: every marker-carrying rule also lists this script as one of its commands, and this
# script fails if one does not. So the exemptions police each other -- touching any exempted file
# re-asks all of them -- and the mechanism cannot be added once and then quietly orphaned.
#
# WHAT IT CANNOT CHECK, stated out loud: whether the reason an exemption gives is TRUE. It only
# forces somebody to look again on a schedule. It also cannot see a brand-new exemption added with
# neither a marker nor this command until some OTHER exempt rule fires -- which any commit touching
# any exempted file does. And it says nothing about rules that are wrong while being well-dated.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

# VERIFY_MAP points this at a different manifest. It exists so the negative controls in
# tool/ci/test_check_verify_exemptions.sh can feed it deliberately-broken copies and confirm this
# script FAILS on each -- a checker never observed failing is indistinguishable from one that cannot.
export VERIFY_MAP="${VERIFY_MAP:-.game_loop/verify.yaml}"

python3 - <<'PY'
import datetime
import os
import re
import sys

MAP = os.environ["VERIFY_MAP"]
SELF = "bash tool/ci/check_verify_exemptions.sh"
MAX_HORIZON_DAYS = 180

# A command that actually EXERCISES something. Anything outside this set is analyze-only: it proves
# the file parses and type-checks, which is not why the rule exists. Deliberately generous -- a false
# "real" is a missed nag, a false "exempt" is noise on a rule that is fine, and noise is what gets a
# check ignored. `.sh` is in here because every shell entry point in tool/ci/ runs a real check or is
# already documented as syntax-only in its own header.
#
# `pub get` added 2026-08-14 -- and it is the broad form on purpose, so `flutter pub get` counts
# too. It resolves a real dependency graph and really fails when that graph is broken, which is
# not a type-check: it is the entire content of the stress/fixture regression (transitive
# `raindrop ^0.0.1`, satisfiable only inside the root workspace, invisible for months behind a
# stale .dart_tool). Calling it analyze-only demanded a RECHECK marker on a rule that is not a
# downgrade at all -- and a "RECHECK never" written to silence a false positive is exactly the
# boilerplate that makes real markers stop being read. This is the "false exempt is noise" case
# the paragraph above is about.
#
# Two agents hit this independently within the hour and wrote the same fix, which is worth more
# than either reading alone: the misclassification blocked every commit to every gated path
# tree-wide, so it was found from two unrelated directions at once.
REAL = ["dart test", "flutter test", "dart run", "sip run", ".sh", "grep", "pub get"]

# Phrases that make a justification TIME-BOUND: each asserts something is broken on THIS MACHINE
# RIGHT NOW. A claim in the present tense expires. Kept to the idiom this file actually uses for a
# downgrade -- a bare "currently fails" also appears where a comment is boasting that a test is
# falsifiable ("it currently fails against the pre-fix doc text"), which is a virtue, not an
# exemption. NOT here on purpose: "too slow for a local sweep", "exercised in CI" -- structural, they
# do not rot on a clock, though a rule resting on them still owes a `RECHECK never`.
TRIGGERS = ["fails locally", "fail locally", "failing locally", "failed locally",
            "broken locally", "fails on this machine", "fail on this machine",
            "pre-existing", "tracked separately", "cannot currently serve"]

# RECHECK  -- this rule is exempt; re-ask by this date (or `never`, declared permanent and counted).
# RESOLVED -- this block QUOTES a former exemption in order to correct it. Rewriting the prose is the
#             point (prose asserting a failure that no longer happens is worse than none), but the
#             quote would otherwise re-trip the trigger above forever. The date says when the quoted
#             claim was re-asked and found false, so the correction carries evidence, not just tone.
MARKER = re.compile(r"RECHECK\s+(never|\d{4}-\d{2}-\d{2})")
RESOLVED = re.compile(r"RESOLVED\s+(\d{4}-\d{2}-\d{2})")

try:
    lines = open(MAP).read().splitlines()
except OSError as e:
    sys.exit(f"check_verify_exemptions: cannot read {MAP} ({e}) -- nothing was checked, not a pass.")

# Parsed with verify's own grammar (bin/verify load_map): a top-level `<glob>:` opens a rule, indented
# `- <cmd>` lines are its commands. A comment block attaches to the rule that follows it AND to every
# later rule with no comment block in between -- which is how one block above four consecutive globs
# reads to a human, and how this file is actually written.
rules, dupes, block, cur = [], {}, [], None
for n, raw in enumerate(lines, 1):
    s = raw.rstrip()
    if not s.strip():
        continue
    if s.lstrip().startswith("#"):
        # Only a COLUMN-0 comment starts a block. An indented one annotates the entry it sits next to
        # inside a rule's own list (unchecked-ok is written that way throughout) -- treating those as
        # block starts leaked their text into whichever rule came next, which read as a phantom
        # exemption on three innocent rules.
        if s.startswith(" "):
            continue
        if cur is not None:                     # a fresh block ends the previous block's reach
            block, cur = [], None
        block.append(s.lstrip("#").strip())
        continue
    if not s.startswith(" ") and s.endswith(":"):
        key = s[:-1].strip().strip('"')
        cur = {"key": key, "line": n, "block": list(block), "cmds": []}
        rules.append(cur)
        dupes.setdefault(key, []).append(n)
    elif cur is not None and s.lstrip().startswith("- "):
        cur["cmds"].append(s.lstrip()[2:].strip().strip('"'))

today = datetime.date.today()
problems, dated, forever, corrected = [], 0, 0, 0

# 1. A key listed twice is not two rules. verify.yaml is parsed into a dict, so the LAST entry wins
#    and the earlier one is dropped with no error -- comment, commands and all. Same rot as a stale
#    exemption but quieter: the check reads as present in the file and never runs. Two were live on
#    2026-08-13, one of which silently disabled ai_templates_test.dart.
rule_keys = {r["key"] for r in rules if r["key"] != "unchecked-ok"}
for r in rules:
    if r["key"] != "unchecked-ok":
        continue
    # An `unchecked-ok` glob that is ALSO a rule key is inert: coverage() tests the rules first, so
    # the path counts as checked and the exclusion never applies. It still reads as a live decision
    # ("this needs no check") sitting directly under a rule that says the opposite.
    for g in r["cmds"]:
        if g in rule_keys:
            problems.append(
                f'{MAP}:{r["line"]}: "{g}" is excluded as unchecked-ok AND claimed by a rule.\n'
                "    The rule wins and the exclusion is dead, but it still reads as a live decision\n"
                "    contradicting it. Drop whichever one is no longer meant.")

for key, at in dupes.items():
    if len(at) > 1:
        problems.append(
            f'{MAP}:{at[-1]}: DUPLICATE KEY "{key}" (also at line {", ".join(map(str, at[:-1]))}).\n'
            "    The last entry wins; the earlier one is silently dropped. Merge them into one rule\n"
            "    with both commands, or delete the dead one.")

for r in rules:
    if r["key"] == "unchecked-ok" or not r["cmds"]:
        continue
    prose = " ".join(r["block"])
    # THIS SCRIPT DOES NOT COUNT AS A REAL CHECK OF THE RULE. It ends in `.sh`, so without excluding
    # it here, the act of enrolling a rule would make that rule stop looking analyze-only -- and the
    # marker requirement would silently switch itself off for every rule that complied with it.
    graded = [c for c in r["cmds"] if c != SELF]
    downgraded = bool(graded) and not any(m in c for c in graded for m in REAL)
    trigger = next((t for t in TRIGGERS if t in prose.lower()), None)
    found = MARKER.search(prose)

    # A block that quotes a former exemption in order to correct it is history, not an exemption --
    # provided a real check now runs. If the rule is STILL analyze-only, RESOLVED does not excuse it.
    if trigger and not downgraded and RESOLVED.search(prose):
        corrected += 1
        continue

    if not (downgraded or trigger):
        continue

    why = ("every command it runs is analyze-only" if downgraded
           else f"its justification rests on a time-bound claim ({trigger!r})")

    # 2. An exemption with no expiry date is precisely the thing that went stale six times over.
    if not found:
        problems.append(
            f'{MAP}:{r["line"]}: "{r["key"]}" is EXEMPT ({why}) and carries no RECHECK marker.\n'
            "    Add one to its comment block:\n"
            f"        # RECHECK {today + datetime.timedelta(days=90)} -- <the real check to re-run>\n"
            "        # RECHECK never -- <why this is structural, not a temporary downgrade>\n"
            "    ...and add this to the rule's commands, so something actually re-asks:\n"
            f'        - "{SELF}"')
        continue

    if found.group(1) == "never":
        forever += 1
    else:
        dated += 1
        # 3. The date must parse, must not have passed, and must not be parked past the horizon.
        try:
            due = datetime.date.fromisoformat(found.group(1))
        except ValueError:
            problems.append(f'{MAP}:{r["line"]}: "{r["key"]}" has an unparseable RECHECK date '
                            f"{found.group(1)!r} -- expected YYYY-MM-DD or 'never'.")
            due = None
        if due and due < today:
            problems.append(
                f'{MAP}:{r["line"]}: "{r["key"]}" came due {(today - due).days} day(s) ago '
                f"(RECHECK {due}).\n"
                f"    It is exempt because {why}. RE-RUN THE REAL CHECK NOW.\n"
                "    If it passes, delete the exemption AND the prose above it -- prose asserting a\n"
                "    failure that no longer happens is worse than no prose. If it still fails, say so\n"
                "    and move the date. Do not move the date without re-running it.")
        elif due and (due - today).days > MAX_HORIZON_DAYS:
            problems.append(
                f'{MAP}:{r["line"]}: "{r["key"]}" has RECHECK {due}, {(due - today).days} days out '
                f"(cap {MAX_HORIZON_DAYS}).\n    A date far enough away is the same as no date.")

    # 4. A marker nothing runs is a note, not a check. Every exempt rule re-asks every other one.
    if SELF not in r["cmds"]:
        problems.append(
            f'{MAP}:{r["line"]}: "{r["key"]}" carries a RECHECK marker but never runs the check that\n'
            f'    enforces it. Add to its commands:\n        - "{SELF}"')

if problems:
    print(f"check_verify_exemptions: {len(problems)} problem(s) in {MAP}\n")
    for p in problems:
        print(f"  {p}\n")
    sys.exit(1)

print(f"check_verify_exemptions: {len(rules)} rule(s) · {dated} dated exemption(s), none overdue · "
      f"{forever} declared permanent (RECHECK never) · {corrected} corrected (RESOLVED). "
      f"today {today}")
print("  This proves somebody was made to LOOK AGAIN -- never that the reason an exemption gives "
      "is true.")
PY
