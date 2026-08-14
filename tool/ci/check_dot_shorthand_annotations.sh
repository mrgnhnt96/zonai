#!/usr/bin/env bash
# Refuse a Dart dot-shorthand as an annotation argument in the sources revali
# generates from.
#
# WHY THIS EXISTS, and why the failure it prevents is invisible locally:
# revali's generator resolves annotation arguments through the analyzer.
# `revali_client`/`revali` 3.2.0's
# lib/server/utils/annotation_argument.dart:35-41 reads `expression.staticType`
# off an AST it does not always get resolved, and throws when that is null. A
# dot-shorthand -- `@QueryRateLimit<GetBody>(.get)` -- is the one argument form
# whose entire meaning lives in resolution, so it is the first thing to turn
# that latent fragility into a hard failure.
#
# MEASURED 2026-08-14: this took down `e2e (macos)` on runs 31839671048 and
# 31842392052 with
#
#   Invalid argument(s): The argument expression has not been resolved yet
#     (`.get` (DotShorthandPropertyAccessImpl) in @QueryRateLimit<GetBody>(.get))
#
# and then an AOT cascade on the server artifacts that were never written. It
# did NOT reproduce on a dev machine across seven configurations (pub.dev
# revali, CI's exact git pin, two SDK patches, warm and cold trees, the full
# vendor sequence) -- see docs/revali-dot-shorthand-codegen.md. So nothing a
# developer can run locally catches a reintroduction; only this grep does.
#
# The 18 occurrences were rewritten to the explicit `RateLimitOperation.x`
# spelling that the rate-limit components' own doc comments already prescribe.
# Without this check, a reviewer "simplifying" that back to `.get` breaks a
# release target's e2e job and every local signal stays green.
#
# WHAT THIS MISSES, out loud:
#   - It is a REGEX over source, not a parse. An annotation argument split
#     across lines, or reached through a constant, is invisible to it.
#   - It only covers apps/server, because that is what revali generates from.
#     A dot-shorthand in an annotation anywhere else is not this script's
#     business and is not checked.
#   - It says nothing about whether the UPSTREAM defect is fixed. When revali
#     resolves these correctly, this check becomes unnecessary rather than
#     wrong -- delete it then, and say so in the commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
target="${root}/apps/server"

# @Name(.member  /  @Name<Type>(.member
pattern='@[A-Za-z_][A-Za-z0-9_]*(<[^>]*>)?\(\.[a-zA-Z]'

if hits="$(grep -rnE "${pattern}" "${target}" --include='*.dart' 2>/dev/null)"; then
  echo "check_dot_shorthand_annotations: dot-shorthand used as an annotation argument" >&2
  echo >&2
  echo "${hits}" >&2
  echo >&2
  echo "revali's generator cannot resolve these and aborts during server codegen," >&2
  echo "which fails the e2e job on CI while every local check stays green." >&2
  echo "Spell the enum out, e.g. RateLimitOperation.get rather than .get." >&2
  echo "Background: docs/revali-dot-shorthand-codegen.md" >&2
  exit 1
fi

echo "ok: no dot-shorthand annotation arguments in apps/server"
