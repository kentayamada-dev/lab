# shellcheck shell=bash
#
# Shared by the .bats files next to this one. A Claude Code hook receives the
# tool call as JSON on stdin and answers with JSON on stdout, so a test is one
# stdin/stdout round trip.

# `run` accepts flags only from 1.5.0 on, and bats warns until a test file
# declares that it counts on them.
bats_require_minimum_version 1.5.0

HOOKS_DIR="${BATS_TEST_DIRNAME}/../hooks"

# The hooks read the project directory out of the environment, as they do under
# Claude Code, so the paths a test hands them are rooted here.
export CLAUDE_PROJECT_DIR=/project

# run_hook <script-name> <stdin-json>
#
# The bare round trip; the tests reach it through answer, which adds the
# status check.
run_hook() {
  printf '%s' "$2" | bash "${HOOKS_DIR}/$1"
}

# answer <script-name> <stdin-json> -> whatever the hook wrote to stdout
#
# The status is asserted here rather than left to the caller: a hook whose jq
# filter breaks writes nothing and exits non-zero, and an unchecked status
# would let every assertion of silence read that crash as silence.
answer() {
  local output status=0
  output="$(run_hook "$1" "$2")" || status=$?
  if [ "${status}" -ne 0 ]; then
    echo "hook $1 exited with ${status}" >&2
    return 1
  fi
  printf '%s' "${output}"
}

# assert_answer <script-name> <stdin-json> <jq expression> <expected, empty for silence>
#
# The round trip is a statement of its own because inside [ "$(...)" = x ] the
# hook's exit status would be the substitution's, and lost. A silent hook
# writes nothing, so an expression that finds nothing is silence.
assert_answer() {
  local output actual
  output="$(answer "$1" "$2")" || return 1
  actual="$(jq -r "$3 // empty" <<<"${output}")"
  [ "${actual}" = "$4" ]
}

# tool_call <field> <value> -> {"tool_input": {<field>: <value>}}
tool_call() {
  jq -nc --arg field "$1" --arg value "$2" '{tool_input: {($field): $value}}'
}
