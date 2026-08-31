#!/usr/bin/env bats

# A hook is only ever reached through .claude/settings.json, so these tests
# pin the wiring (docs/ci-jobs.md#hooks).
setup() {
  load helper
  SETTINGS_FILE="${BATS_TEST_DIRNAME}/../settings.json"
}

# registrations -> "<event> <script name>" for every registered hook command
registrations() {
  jq -r '.hooks | to_entries[] | .key as $event
    | .value[].hooks[] | select(.type == "command") | .command
    | capture("(?<script>[^/]+\\.sh)").script
    | "\($event) \(.)"' "${SETTINGS_FILE}"
}

# script_names -> the file name of every hook script present
script_names() {
  local path
  for path in "${HOOKS_DIR}"/*.sh; do
    basename "${path}"
  done
}

@test "registers exactly the hook scripts that are present" {
  [ "$(registrations | cut -d' ' -f2 | sort -u)" = "$(script_names | sort)" ]
}

@test "registers each hook under the event it answers with" {
  local event script
  while read -r event script; do
    grep -qE "hookEventName\"?: \"${event}\"" "${HOOKS_DIR}/${script}" || return 1
  done < <(registrations)
}

@test "keeps a test file for every hook script" {
  local name
  while read -r name; do
    [ -f "${BATS_TEST_DIRNAME}/${name%.sh}.bats" ] || return 1
  done < <(script_names)
}
