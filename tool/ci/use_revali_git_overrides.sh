#!/usr/bin/env bash
# Updates pubspec_overrides.yaml to pull revali packages from GitHub instead of local paths.
#
# Environment:
#   REVALI_GIT_URL  — repository URL (default: https://github.com/mrgnhnt96/revali.git)
#   REVALI_GIT_REF  — branch, tag, or commit (default: feat/wrap-request)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC_OVERRIDES="${ROOT}/pubspec_overrides.yaml"
REVALI_GIT_URL="${REVALI_GIT_URL:-https://github.com/mrgnhnt96/revali.git}"
REVALI_GIT_REF="${REVALI_GIT_REF:-feat/wrap-request}"

write_git_override() {
  local package="$1"
  local path="$2"
  cat <<EOF
  ${package}:
    git:
      url: ${REVALI_GIT_URL}
      ref: ${REVALI_GIT_REF}
      path: ${path}
EOF
}

{
  cat <<EOF
# Revali overrides — use local paths for development, or run tool/ci/use_revali_git_overrides.sh for CI.
dependency_overrides:
EOF
  write_git_override revali_router revali_router/revali_router
  write_git_override revali_router_annotations revali_router/revali_router_annotations
  write_git_override revali_router_core revali_router/revali_router_core
  write_git_override revali packages/revali
  write_git_override revali_client constructs/revali_client/revali_client
  write_git_override revali_client_gen constructs/revali_client/revali_client_gen
  write_git_override revali_server constructs/revali_server
  write_git_override revali_swagger constructs/revali_swagger/revali_swagger
  write_git_override revali_swagger_annotations constructs/revali_swagger/revali_swagger_annotations
  write_git_override revali_construct packages/revali_construct
  write_git_override revali_core packages/revali_core
} > "${PUBSPEC_OVERRIDES}"

echo "Wrote ${PUBSPEC_OVERRIDES} (url: ${REVALI_GIT_URL}, ref: ${REVALI_GIT_REF})"
