#!/usr/bin/env bats

# Pins every copy of the Conventional Commits type list to the PATTERN the
# pr-title job enforces (docs/ci-jobs.md#hooks).
#
# Each extractor is anchored to the current wording of its source. When a
# rewording empties one, the comparison against the non-empty PATTERN list
# fails, which is the cue to update the extractor rather than a real drift.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  CI_YML="${REPO_ROOT}/.github/workflows/ci.yml"
  SETTINGS_FILE="${BATS_TEST_DIRNAME}/../settings.json"
}

# enforced_types -> the space-separated list inside PATTERN's first group
enforced_types() {
  local line
  line="$(grep -m1 "PATTERN: '" "${CI_YML}")"
  line="${line#*"("}"
  printf '%s' "${line%%")"*}" | tr '|' ' '
}

# message_types -> the list on the "type   :" line of the failure message
message_types() {
  local line
  line="$(grep -m1 -E '^[[:space:]]+type[[:space:]]+: ' "${CI_YML}")"
  printf '%s' "${line#*: }"
}

# table_types <readme> -> the backticked words in the third cell of the type row
table_types() {
  grep -m1 '^| `type` |' "$1" | cut -d'|' -f4 | grep -o '`[a-z]*`' | tr -d '`' | xargs
}

# prompt_types -> the "one of ..." list in the prompt hook, commas dropped
prompt_types() {
  local prompt
  prompt="$(jq -r '.hooks.PreToolUse[].hooks[] | select(.type == "prompt") | .prompt' "${SETTINGS_FILE}")"
  prompt="${prompt#*"one of "}"
  printf '%s' "${prompt%%" ("*}" | tr -d ','
}

@test "the PATTERN yields a non-empty type list to pin the copies to" {
  [ -n "$(enforced_types)" ]
}

@test "the failure message lists the enforced types" {
  [ "$(message_types)" = "$(enforced_types)" ]
}

@test "the prompt hook lists the enforced types" {
  [ "$(prompt_types)" = "$(enforced_types)" ]
}

@test "the README tables list the enforced types" {
  [ "$(table_types "${REPO_ROOT}/README.md")" = "$(enforced_types)" ]
  [ "$(table_types "${REPO_ROOT}/README.ja.md")" = "$(enforced_types)" ]
}
