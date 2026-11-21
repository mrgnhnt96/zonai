#!/usr/bin/env bash
# Keeps a copy of a running e2e log OUTSIDE the runner, in a check run on the
# commit, so a job that stalls still leaves a record of how far it got.
#
# Why a check run and not the job log: when the windows e2e job stalls, the
# runner's worker goes dark. All 10 stalls from 2026-08-15 to 2026-11-12
# (31875317878 ... 43325800047) look the same through the API: the job has
# zero recorded steps, its log blob does not exist (BlobNotFound), and it ends
# exactly 5m00s past its ceiling -- the server force-completing a job whose
# runner never acknowledged the cancel. A windows job that times out on a
# healthy runner (cli, e.g. 36789396290) keeps its steps and its log. So the
# step's `timeout-minutes` (enforced by the worker) and the in-script GNU
# `timeout` (whose output only reaches GitHub through the worker) never had a
# way to report, whether or not they fired. This script talks to the GitHub
# API directly, so it reports for as long as the machine and its network do.
#
# Usage (from a job step; never fails the step):
#   e2e_live_log.sh start                       prints the check run's id
#   e2e_live_log.sh watch <id> <log> <overdue>  pushes the log's tail every
#                                               minute until <log>.done exists;
#                                               after <overdue> seconds it also
#                                               marks the check run failed
#   e2e_live_log.sh finish <id> <log> <status>  final copy, concluded from the
#                                               run's exit <status>
#
# Needs GH_TOKEN with `checks: write`, LIVE_LOG_NAME (the check run's name),
# LIVE_LOG_SHA (the commit it attaches to), and GITHUB_REPOSITORY,
# GITHUB_SERVER_URL and GITHUB_RUN_ID, which every Actions job has.
set -uo pipefail

repo="${GITHUB_REPOSITORY:?}"
tail_lines=200
max_bytes=60000
summary="A copy of this e2e log, pushed every minute from the runner straight \
to the GitHub API. The job's own log only reaches GitHub through the runner, \
and when the windows runner stalls it never arrives, so this is the record of \
how far the run got and when it last answered."

# Every call bounded: this runs beside the tests and must never become the
# thing that hangs.
api() {
  local bound=() candidate
  for candidate in timeout gtimeout; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      bound=("${candidate}" --kill-after=10 30s)
      break
    fi
  done
  ${bound[@]+"${bound[@]}"} gh api "$@"
}

# <id> <log> <title> [extra gh api fields...]
#
# The text file sits next to the log under a RELATIVE path: gh on windows is
# a native program and cannot open a Git Bash path like /tmp/x.
push() {
  local id="$1" log="$2" title="$3"
  shift 3
  local text="${log}.live.md" status
  {
    printf '```\n'
    tail -n "${tail_lines}" "${log}" 2>/dev/null | tail -c "${max_bytes}"
    printf '\n```\n'
  } > "${text}"
  api -X PATCH "repos/${repo}/check-runs/${id}" \
    -f "output[title]=${title}" \
    -f "output[summary]=${summary}" \
    -F "output[text]=@${text}" \
    "$@" >/dev/null
  status=$?
  rm -f "${text}"
  return "${status}"
}

stamp() { date -u +%H:%M:%S; }

case "${1:-}" in
  start)
    api -X POST "repos/${repo}/check-runs" \
      -f "name=${LIVE_LOG_NAME:?}" \
      -f "head_sha=${LIVE_LOG_SHA:?}" \
      -f status=in_progress \
      -f "details_url=${GITHUB_SERVER_URL}/${repo}/actions/runs/${GITHUB_RUN_ID}" \
      -f "output[title]=E2E tests started at $(stamp) UTC" \
      -f "output[summary]=${summary}" \
      --jq .id
    ;;

  watch)
    id="$2" log="$3" overdue="$4"
    started=$(date +%s)
    next=$(( started + 60 ))
    while [ ! -e "${log}.done" ]; do
      sleep 5
      now=$(date +%s)
      [ "${now}" -ge "${next}" ] || continue
      next=$(( now + 60 ))
      minutes=$(( (now - started) / 60 ))
      if [ $(( now - started )) -gt "${overdue}" ]; then
        push "${id}" "${log}" \
          "E2E tests still running after ${minutes}m, past their time bound (last update $(stamp) UTC)" \
          -f status=completed -f conclusion=failure ||
          echo "$(stamp) push failed"
      else
        push "${id}" "${log}" \
          "E2E tests running, ${minutes}m in (last update $(stamp) UTC)" ||
          echo "$(stamp) push failed"
      fi
    done
    ;;

  finish)
    id="$2" log="$3" status="$4"
    case "${status}" in
      0) title="E2E tests passed" conclusion=success ;;
      124 | 137) title="E2E tests stopped at their time bound" conclusion=failure ;;
      *) title="E2E tests failed (exit ${status})" conclusion=failure ;;
    esac
    push "${id}" "${log}" "${title} at $(stamp) UTC" \
      -f status=completed -f "conclusion=${conclusion}"
    ;;

  *)
    echo "usage: $0 start | watch <id> <log> <overdue-seconds> | finish <id> <log> <status>" >&2
    exit 64
    ;;
esac
