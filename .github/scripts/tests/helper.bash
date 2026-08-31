# shellcheck shell=bash
#
# Shared by the .bats files next to this one. The scripts in the directory above do all
# their work through gh, so a test replaces gh with a stub: what gh answers comes from
# the environment, and the arguments it was called with land in a log the assertions
# read. Nothing reaches GitHub.

# `run` accepts flags only from 1.5.0 on, and bats warns until a test file declares
# that it counts on them.
bats_require_minimum_version 1.5.0

SCRIPTS_DIR="${BATS_TEST_DIRNAME}/.."

# run_script <script-name> [<argument> ...]
#
# Reached through bats `run`, so that the exit status a script answers with is part of
# what a test asserts.
run_script() {
  local script="$1"
  shift
  bash "${SCRIPTS_DIR}/${script}" "$@"
}

# stub_gh
#
# Puts the stub first on PATH and starts an empty call log. Until a test calls
# open_issue, `gh issue list` answers with no issues at all.
stub_gh() {
  export GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
  export GH_ISSUES="${BATS_TEST_TMPDIR}/issues.json"
  : >"${GH_LOG}"
  echo '[]' >"${GH_ISSUES}"

  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Quoted heredoc: the stub reads the variables when it runs, not when it is written.
  cat >"${BATS_TEST_TMPDIR}/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_LOG}"
case "${1:-} ${2:-}" in
  "issue list") cat "${GH_ISSUES}" ;;
  "issue create") echo "https://github.com/owner/repo/issues/7" ;;
  "issue edit")
    # A label that no longer exists is the one gh failure the scripts handle.
    if [[ "$*" == *--add-label* && "${GH_ADD_LABEL_FAILS:-false}" == true ]]; then
      echo "could not add label" >&2
      exit 1
    fi
    ;;
esac
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# open_issue <number> <title> [<number> <title> ...]
#
# What `gh issue list` answers with from here on. Replaces whatever a previous call
# set, so a test states the whole list it wants.
open_issue() {
  local args=() n=0
  while [[ $# -gt 0 ]]; do
    args+=(--argjson "n${n}" "$1" --arg "t${n}" "$2")
    n=$((n + 1))
    shift 2
  done
  local filter='['
  for ((i = 0; i < n; i++)); do
    filter="${filter}{number: \$n${i}, title: \$t${i}},"
  done
  jq -nc "${args[@]}" "${filter%,}]" >"${GH_ISSUES}"
}

# write_file <name> <text> -> the path it was written to
#
# The issue bodies the scripts are handed. The name is echoed back so a test can
# assert on the path the stub logged.
write_file() {
  printf '%s\n' "$2" >"${BATS_TEST_TMPDIR}/$1"
  printf '%s' "${BATS_TEST_TMPDIR}/$1"
}

# assert_gh_called <pattern>, assert_gh_not_called <pattern>
#
# One line of the log is one gh call, so a pattern matched against a whole line says
# both which subcommand ran and what it was given.
assert_gh_called() {
  grep -qF -- "$1" "${GH_LOG}"
}

assert_gh_not_called() {
  ! grep -qF -- "$1" "${GH_LOG}"
}
