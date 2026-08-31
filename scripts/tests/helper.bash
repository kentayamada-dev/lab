# shellcheck shell=bash
#
# Shared by the .bats files next to this one. sync-repo-config.sh does all its work
# through gh, so a test replaces gh with a stub: what gh answers comes from fixture
# files keyed by endpoint, the arguments it was called with land in a log the
# assertions read, and a --jq filter is applied to the fixture with the real jq, so
# the script's own jq programs run unchanged. Nothing reaches GitHub.
#
# The script is run from a throwaway copy of the repository (setup_repo), so the
# config.yml rewrite the apply path performs never touches the real working tree.

bats_require_minimum_version 1.5.0

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# setup_repo
#
# Copies the script and the ruleset it reads into a throwaway repository root, kept
# in REPO_COPY. config.yml is written rather than copied: in a repository created
# from the template the real one has already been rewritten, and the rewrite is one
# of the things under test.
setup_repo() {
  REPO_COPY="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO_COPY}/scripts" "${REPO_COPY}/.github/rulesets" "${REPO_COPY}/.github/ISSUE_TEMPLATE"
  cp "${REPO_ROOT}/scripts/sync-repo-config.sh" "${REPO_COPY}/scripts/"
  cp "${REPO_ROOT}/.github/rulesets/main.json" "${REPO_COPY}/.github/rulesets/"
  cat >"${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml" <<'EOF'
blank_issues_enabled: false
contact_links:
  - name: Ask in Discussions
    url: https://github.com/OWNER/REPO/discussions/new/choose
    about: For questions.
EOF
}

# run_sync [<argument> ...]
#
# Reached through bats `run`, so that the exit status the script answers with is part
# of what a test asserts. REPO is pinned so the stub never has to answer
# `gh repo view` and the endpoint paths the fixtures are keyed by stay stable.
run_sync() {
  REPO=owner/repo bash "${REPO_COPY}/scripts/sync-repo-config.sh" "$@"
}

# fixture_path <endpoint> -> the fixture base path for that endpoint
#
# Everything outside [A-Za-z0-9._-] becomes _, so an endpoint such as
# "repos/owner/repo/rulesets?includes_parents=false" maps to one flat file name.
fixture_path() {
  printf '%s/%s' "${GH_FIXTURES}" "${1//[^A-Za-z0-9._-]/_}"
}

# stub_gh
#
# Puts the stub first on PATH, starts an empty call log, and lays down fixtures that
# answer every read the script performs with exactly what it expects, so --check
# reports no drift until a test states a deviation with edit_fixture or
# fail_endpoint. Call setup_repo first: the ruleset fixtures are derived from the
# copied definition, so the two sides of the comparison start in agreement.
stub_gh() {
  export GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
  export GH_FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  : >"${GH_LOG}"
  mkdir -p "${GH_FIXTURES}"

  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Quoted heredoc: the stub reads the variables when it runs, not when it is written.
  cat >"${BATS_TEST_TMPDIR}/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_LOG}"

case "${1:-}" in
  auth)
    if [[ "${GH_AUTH_FAILS:-false}" == true ]]; then
      exit 1
    fi
    exit 0
    ;;
  api)
    shift
    ;;
  *)
    exit 0
    ;;
esac

endpoint='' jq_filter='' method=GET silent=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq)
      jq_filter="$2"
      shift 2
      ;;
    --method)
      method="$2"
      shift 2
      ;;
    --silent)
      silent=true
      shift
      ;;
    --input | -F | -f)
      shift 2
      ;;
    --paginate)
      shift
      ;;
    *)
      if [[ -z "${endpoint}" ]]; then
        endpoint="$1"
      fi
      shift
      ;;
  esac
done

fixture="${GH_FIXTURES}/${endpoint//[^A-Za-z0-9._-]/_}"
if [[ -f "${fixture}.exit" ]]; then
  if [[ -f "${fixture}.err" ]]; then
    cat "${fixture}.err" >&2
  fi
  exit "$(cat "${fixture}.exit")"
fi
if [[ "${method}" != GET ]]; then
  exit 0
fi
if [[ "${silent}" == true ]]; then
  exit 0
fi
if [[ ! -f "${fixture}.json" ]]; then
  echo "gh stub: no fixture for ${endpoint}" >&2
  exit 1
fi
if [[ -n "${jq_filter}" ]]; then
  jq -r "${jq_filter}" "${fixture}.json"
else
  cat "${fixture}.json"
fi
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  # What --check reads over GraphQL, mirroring REPO_SETTINGS_EXPECTED in the script.
  jq -n '{data: {repository: {
    autoMergeAllowed: true,
    deleteBranchOnMerge: true,
    allowUpdateBranch: true,
    squashMergeAllowed: true,
    mergeCommitAllowed: false,
    rebaseMergeAllowed: false,
    squashMergeCommitTitle: "PR_TITLE",
    hasIssuesEnabled: true,
    hasDiscussionsEnabled: true,
    hasProjectsEnabled: true,
    hasWikiEnabled: false
  }}}' >"$(fixture_path graphql).json"

  # The repository object: visibility and admin gate the run, security_and_analysis
  # feeds --check, and the flat REST fields feed the summary the apply path prints.
  jq -n '{
    visibility: "public",
    permissions: {admin: true},
    security_and_analysis: {secret_scanning_push_protection: {status: "enabled"}},
    allow_auto_merge: true,
    delete_branch_on_merge: true,
    allow_update_branch: true,
    has_issues: true,
    has_discussions: true,
    has_projects: true,
    has_wiki: false,
    allow_squash_merge: true,
    allow_merge_commit: false,
    allow_rebase_merge: false,
    squash_merge_commit_title: "PR_TITLE"
  }' >"$(fixture_path repos/owner/repo).json"

  echo '{"enabled": true}' >"$(fixture_path repos/owner/repo/immutable-releases).json"
  echo '{"enabled": true}' >"$(fixture_path repos/owner/repo/private-vulnerability-reporting).json"
  # vulnerability-alerts answers 204 with no body; the stub models that as a silent
  # success, so an enabled state needs no fixture at all.
  jq -n '{default_workflow_permissions: "read", can_approve_pull_request_reviews: false}' \
    >"$(fixture_path repos/owner/repo/actions/permissions/workflow).json"
  jq -n '[{name: "bug"}, {name: "dependencies"}, {name: "enhancement"}, {name: "maintenance"}]' \
    >"$(fixture_path repos/owner/repo/labels).json"
  jq '[{id: 1, name: .name}]' "${REPO_COPY}/.github/rulesets/main.json" \
    >"$(fixture_path 'repos/owner/repo/rulesets?includes_parents=false').json"
  jq '. + {id: 1}' "${REPO_COPY}/.github/rulesets/main.json" \
    >"$(fixture_path repos/owner/repo/rulesets/1).json"
  # No classic branch protection: the probe on the apply path fails like the real 404.
  fail_endpoint repos/owner/repo/branches/main/protection 1
}

# edit_fixture <endpoint> <jq-program>
#
# Rewrites one fixture in place. This is how a test states "GitHub answers
# differently": the program skews the canned response, not the definition.
edit_fixture() {
  local file
  file="$(fixture_path "$1").json"
  jq "$2" "${file}" >"${file}.tmp"
  mv "${file}.tmp" "${file}"
}

# edit_ruleset <jq-program>
#
# Rewrites the copied ruleset definition — the "want" side of the comparison.
edit_ruleset() {
  local file="${REPO_COPY}/.github/rulesets/main.json"
  jq "$1" "${file}" >"${file}.tmp"
  mv "${file}.tmp" "${file}"
}

# fail_endpoint <endpoint> <exit-code> [<stderr-text>]
#
# From here on, every call to the endpoint fails with the code, write methods too.
fail_endpoint() {
  local file
  file="$(fixture_path "$1")"
  echo "$2" >"${file}.exit"
  if [[ $# -gt 2 ]]; then
    printf '%s\n' "$3" >"${file}.err"
  fi
}

# pass_endpoint <endpoint>
#
# The opposite: the endpoint answers with an empty object. What the classic branch
# protection probe needs in order to see one.
pass_endpoint() {
  local file
  file="$(fixture_path "$1")"
  rm -f "${file}.exit" "${file}.err"
  echo '{}' >"${file}.json"
}

# assert_gh_called <pattern>, assert_gh_not_called <pattern>
#
# One line of the log is one gh call, so a pattern matched against a whole line says
# both which method and endpoint were hit and what they were given.
assert_gh_called() {
  grep -qF -- "$1" "${GH_LOG}"
}

assert_gh_not_called() {
  ! grep -qF -- "$1" "${GH_LOG}"
}
