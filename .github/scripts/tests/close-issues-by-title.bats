#!/usr/bin/env bats

setup() {
  load helper
  stub_gh
}

@test "prints its usage with --help" {
  run -0 run_script close-issues-by-title.sh --help
  [ -n "${output}" ]
}

@test "refuses a call without both a title and a comment" {
  run -2 run_script close-issues-by-title.sh
  run -2 run_script close-issues-by-title.sh 'Only a title'
  run -2 run_script close-issues-by-title.sh 'A title' 'A comment' extra
}

@test "closes the issue with the given title, leaving the comment on it" {
  open_issue 12 'External links are broken'
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_called 'issue close 12 --comment the check passed'
}

@test "closes nothing when no issue carries the title" {
  open_issue 12 'Something else entirely'
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_not_called 'issue close'
}

@test "closes nothing when no issue is open at all" {
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_not_called 'issue close'
}

@test "closes every issue that carries the title" {
  open_issue 12 'External links are broken' 13 'External links are broken'
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_called 'issue close 12'
  assert_gh_called 'issue close 13'
}

# The title reaches jq as a value, not as part of the filter, so what it is made of
# does not matter. A title that only starts the same is a different title.
@test "matches the title in full and literally" {
  open_issue 12 'External links are broken (again)' 13 '"quoted" $(and) unquoted'
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_not_called 'issue close'
  run -0 run_script close-issues-by-title.sh '"quoted" $(and) unquoted' 'the check passed'
  assert_gh_called 'issue close 13'
}

# The counterpart of the same test in upsert-issue.bats: an issue somebody else opened
# under this title must not be closed with "the check passed".
@test "looks only at issues github-actions[bot] opened" {
  open_issue 12 'External links are broken'
  run -0 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
  assert_gh_called "issue list --state open --limit 100 --author github-actions[bot]"
}

@test "fails when gh does" {
  mkdir -p "${BATS_TEST_TMPDIR}/broken"
  printf '#!/bin/sh\nexit 1\n' >"${BATS_TEST_TMPDIR}/broken/gh"
  chmod +x "${BATS_TEST_TMPDIR}/broken/gh"
  PATH="${BATS_TEST_TMPDIR}/broken:${PATH}"
  run -1 run_script close-issues-by-title.sh 'External links are broken' 'the check passed'
}
