#!/usr/bin/env bats

TITLE='Repository settings have drifted'

setup() {
  load helper
  stub_gh
  BODY="$(write_file body.md 'the check failed')"
  COMMENT="$(write_file comment.md 'the check failed again')"
}

# upsert <on-existing> [<extra argument> ...]
upsert() {
  local mode="$1"
  shift
  run_script upsert-issue.sh --title "${TITLE}" --body-file "${BODY}" \
    --label maintenance --on-existing "${mode}" "$@"
}

@test "prints its usage with --help" {
  run -0 run_script upsert-issue.sh --help
  [ -n "${output}" ]
}

@test "refuses a call that leaves out one of the required options" {
  run -2 run_script upsert-issue.sh --body-file "${BODY}" --label maintenance --on-existing skip
  run -2 run_script upsert-issue.sh --title "${TITLE}" --label maintenance --on-existing skip
  run -2 run_script upsert-issue.sh --title "${TITLE}" --body-file "${BODY}" --on-existing skip
  run -2 run_script upsert-issue.sh --title "${TITLE}" --body-file "${BODY}" --label maintenance
}

@test "refuses an unknown option and an unknown --on-existing value" {
  run -2 run_script upsert-issue.sh --title "${TITLE}" --body-file "${BODY}" \
    --label maintenance --on-existing skip --wat
  run -2 upsert replace
}

# The two are one option short of each other, and getting it wrong either way would
# only show up as a comment that never arrives.
@test "refuses comment without a comment file, and a comment file without comment" {
  run -2 upsert comment
  run -2 upsert skip --comment-file "${COMMENT}"
  run -2 upsert edit --comment-file "${COMMENT}"
}

@test "refuses a body file that is not there" {
  run -2 run_script upsert-issue.sh --title "${TITLE}" --body-file "${BATS_TEST_TMPDIR}/absent.md" \
    --label maintenance --on-existing skip
  run -2 upsert comment --comment-file "${BATS_TEST_TMPDIR}/absent.md"
  assert_gh_not_called 'issue create'
}

@test "opens the issue with the body and the label when none is open" {
  run -0 upsert skip
  assert_gh_called "issue create --title ${TITLE} --body-file ${BODY}"
  assert_gh_called 'issue edit https://github.com/owner/repo/issues/7 --add-label maintenance'
}

# The issue matters more than the label, so a label that has been deleted since is
# reported and left at that.
@test "warns instead of failing when the label cannot be added" {
  GH_ADD_LABEL_FAILS=true run -0 upsert skip
  [[ "${output}" == *"::warning::"*"maintenance label"* ]]
  assert_gh_called 'issue create'
}

@test "skip leaves an issue that is already open untouched" {
  open_issue 42 "${TITLE}"
  run -0 upsert skip
  [[ "${output}" == *"#42"* ]]
  assert_gh_not_called 'issue create'
  assert_gh_not_called 'issue edit'
  assert_gh_not_called 'issue comment'
}

@test "comment adds the comment file to an issue that is already open" {
  open_issue 42 "${TITLE}"
  run -0 upsert comment --comment-file "${COMMENT}"
  assert_gh_called "issue comment 42 --body-file ${COMMENT}"
  assert_gh_not_called 'issue create'
}

@test "edit replaces the body of an issue that is already open" {
  open_issue 42 "${TITLE}"
  run -0 upsert edit
  assert_gh_called "issue edit 42 --body-file ${BODY}"
  assert_gh_not_called 'issue create'
  assert_gh_not_called '--add-label'
}

@test "opens the issue when another title only starts the same" {
  open_issue 42 "${TITLE} again"
  run -0 upsert skip
  assert_gh_called 'issue create'
}

# Two issues under one title is not what this aims for, but a race between runs can
# leave that behind. Acting on the first keeps the run from adding a third.
@test "acts on one issue when the title carries more than one" {
  open_issue 42 "${TITLE}" 43 "${TITLE}"
  run -0 upsert edit
  assert_gh_called 'issue edit 42'
  assert_gh_not_called 'issue edit 43'
}

@test "fails when gh does" {
  mkdir -p "${BATS_TEST_TMPDIR}/broken"
  printf '#!/bin/sh\nexit 1\n' >"${BATS_TEST_TMPDIR}/broken/gh"
  chmod +x "${BATS_TEST_TMPDIR}/broken/gh"
  PATH="${BATS_TEST_TMPDIR}/broken:${PATH}"
  run -1 upsert skip
}
