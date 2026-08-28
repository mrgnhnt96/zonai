#!/usr/bin/env bash
# Copies submodule working trees into a linked git worktree so pub can resolve.
#
# WHY THIS EXISTS
# `git worktree add` provisions the outer repo only, so a fresh worktree has an
# empty libs/raindrop and libs/resqlite. `dart pub get` then fails outright --
# "zonai depends on resqlite from path which doesn't exist" -- and every
# showrunner check (`sip run test static`, `sip run test unit`) is unrunnable,
# so no Crawler can close a leaf with a real artifact.
#
# WHY A COPY AND NOT `git submodule update --init`
# .git/modules/<name> is SHARED across every worktree of the parent. Running
# submodule update in a worktree moves HEAD for the primary checkout too, and
# can discard uncommitted work sitting in the main checkout's submodule tree.
# That is not hypothetical: libs/raindrop was carrying 20+ modified files when
# this script was written. A copy touches no shared git state at all.
#
# The copies deliberately omit .git, so they are inert directories rather than
# repositories: nothing in a worktree can commit into them, and the outer repo
# still sees the path as a gitlink and ignores the contents. That also means
# tool/check_worktree_submodules.sh still reports them as unmaterialised (it
# tests for .git) -- correct for its purpose, which is to refuse a worktree
# where submodule EDITS would be lost. Do not edit these copies; they exist so
# resolution succeeds for work that lives elsewhere in the tree.
#
# THE SAME PROBLEM, A SECOND TIME
# apps/zonai/lib/gen/ is gitignored and produced by `zonai compile`, so a fresh
# worktree does not have it either and `sip run test static` fails its
# server-mirror check before it reaches analysis. Same remedy, same reasoning:
# it is generated output, not authored source, so copying it is exact.
# zonai_entrypoint.dart's _generatedSources list is the authority on what lives
# under there; if that list grows, this copy still carries it, because it takes
# the whole directory.
#
# usage: tool/provision_worktree_submodules.sh [worktree-path]
#        (defaults to the worktree you are standing in, so a Crawler can
#         provision its own tree as its first step)
set -euo pipefail

# The PRIMARY checkout, which is the only place the submodules and the
# gitignored gen/ tree actually exist -- never `dirname $0/..`, because this
# script is tracked and therefore also present inside every worktree, where
# that would resolve to the empty tree we are trying to fill and every copy
# would silently SKIP. --git-common-dir points at the primary .git from
# anywhere, including from inside a linked worktree.
ROOT="$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
WT="${1:-$(git rev-parse --show-toplevel)}"
[[ -d "$WT" ]] || { echo "no such worktree: $WT" >&2; exit 1; }
WT="$(cd "$WT" && pwd)"
[[ "$WT" != "$ROOT" ]] || { echo "refusing to provision the primary checkout" >&2; exit 1; }

paths=$(git -C "$ROOT" config -f "$ROOT/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

for p in $paths; do
  src="$ROOT/$p"
  dst="$WT/$p"
  if [[ ! -e "$src/.git" ]]; then
    echo "SKIP $p — not materialised in the primary checkout either" >&2
    continue
  fi
  rm -rf "$dst"
  mkdir -p "$dst"
  # .dart_tool holds absolute paths from the source checkout; copying it makes
  # pub resolve against the wrong root. Let it regenerate.
  rsync -a --exclude '.git' --exclude '.dart_tool' --exclude 'build' \
        "$src/" "$dst/"
  echo "provisioned $p"
done

# Gitignored generated sources, same reasoning as above.
for g in apps/zonai/lib/gen; do
  src="$ROOT/$g"
  dst="$WT/$g"
  if [[ ! -d "$src" ]]; then
    echo "SKIP $g — absent from the primary checkout; run `zonai compile` there first" >&2
    continue
  fi
  rm -rf "$dst"
  mkdir -p "$dst"
  rsync -a --exclude '.dart_tool' "$src/" "$dst/"
  echo "provisioned $g"
done
