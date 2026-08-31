#!/usr/bin/env bats

# The paths below are rooted at the project directory the helper exports, since
# that is what the hook measures a path against.
setup() {
  load helper
}

# assert_reminder <"reminder", empty for silence> <file path>
assert_reminder() {
  assert_answer remind-bilingual-pair.sh "$(tool_call file_path "$2")" \
    'if .hookSpecificOutput.additionalContext then "reminder" else empty end' "$1"
}

@test "answers with a PostToolUse context" {
  output="$(answer remind-bilingual-pair.sh "$(tool_call file_path /project/README.md)")"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${output}")" = PostToolUse ]
  [ -n "$(jq -r '.hookSpecificOutput.additionalContext' <<<"${output}")" ]
}

@test "reminds on both sides of the README pair" {
  assert_reminder reminder /project/README.md
  assert_reminder reminder /project/README.ja.md
}

@test "reminds on both sides of a docs pair" {
  assert_reminder reminder /project/docs/ci-jobs.md
  assert_reminder reminder /project/docs/ci-jobs.ja.md
}

@test "reminds for a page nested deeper under docs" {
  assert_reminder reminder /project/docs/adr/0001-record-decisions.md
}

@test "stays silent for an English-only document" {
  assert_reminder '' /project/CLAUDE.md
  assert_reminder '' /project/CONTRIBUTING.md
}

@test "stays silent for a file that is not a document" {
  assert_reminder '' /project/scripts/sync-repo-config.sh
  assert_reminder '' /project/docs/diagram.svg
}

@test "stays silent for a README-like name that is not the README" {
  assert_reminder '' /project/READMEs.md
  assert_reminder '' /project/OLD_README.md
}

@test "stays silent for a README that belongs to a subdirectory" {
  assert_reminder '' /project/scripts/README.md
}

@test "stays silent for a file outside the project" {
  assert_reminder '' /elsewhere/README.md
  assert_reminder '' /elsewhere/docs/ci-jobs.md
}

# The README at the filesystem root is the trap here: with no root to trim, a
# bare leading slash must not be mistaken for the project prefix.
@test "stays silent when the project directory is unknown" {
  unset CLAUDE_PROJECT_DIR
  assert_reminder '' /project/README.md
  assert_reminder '' /README.md
}

@test "stays silent when the tool call carries no file path" {
  assert_answer remind-bilingual-pair.sh '{}' .hookSpecificOutput.additionalContext ''
}

@test "stays silent when the file path is not text" {
  assert_answer remind-bilingual-pair.sh '{"tool_input": {"file_path": 123}}' \
    .hookSpecificOutput.additionalContext ''
}

# The hook runs after the edit, so nothing is left to block; what it must not
# do is fail the tool call it can say nothing about.
@test "does not fail the call when the tool call is not JSON" {
  run --separate-stderr run_hook remind-bilingual-pair.sh 'not json'
  [ -z "${output}" ]
  [ "${status}" -ne 2 ]
}
