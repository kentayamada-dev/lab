#!/usr/bin/env bats

setup() {
  load helper
  setup_repo
  stub_gh
}

@test "prints its usage with --help" {
  run -0 run_sync --help
  [ -n "${output}" ]
}

@test "refuses an unknown option, and --dry-run together with --check" {
  run -2 run_sync --wat
  run -2 run_sync --dry-run --check
}

@test "fails before reaching the API when gh is not logged in" {
  GH_AUTH_FAILS=true run -1 run_sync --check
  assert_gh_not_called 'api'
}

@test "refuses when the ruleset file is missing, and applies nothing" {
  RULESET_FILE="${BATS_TEST_TMPDIR}/absent.json" run -1 run_sync
  assert_gh_not_called '--method'
}

@test "refuses broken ruleset JSON, and applies nothing" {
  echo '{' >"${REPO_COPY}/.github/rulesets/main.json"
  run -1 run_sync
  assert_gh_not_called '--method'
}

@test "refuses a ruleset that has no name, and applies nothing" {
  edit_ruleset 'del(.name)'
  run -1 run_sync
  assert_gh_not_called '--method'
}

@test "refuses a repository that is not public, and applies nothing" {
  edit_fixture repos/owner/repo '.visibility = "private"'
  run -1 run_sync
  [[ "${output}" == *private* ]]
  assert_gh_not_called '--method'
}

@test "--check reports no drift when everything matches, and writes nothing" {
  run -0 run_sync --check
  [[ "${output}" == *'no drift'* ]]
  assert_gh_not_called '--method'
}

@test "--check reports a repository setting that differs as DRIFT" {
  edit_fixture graphql '.data.repository.hasWikiEnabled |= not'
  run -1 run_sync --check
  [[ "${output}" == *'DRIFT   has_wiki'* ]]
}

@test "--check reports settings it cannot read as UNKNOWN and points at SETTINGS_TOKEN" {
  fail_endpoint graphql 1
  run -1 run_sync --check
  [[ "${output}" == *'UNKNOWN allow_auto_merge'* ]]
  [[ "${output}" == *SETTINGS_TOKEN* ]]
}

# Why a 404 splits into DRIFT and UNKNOWN: docs/drift-check.md#トークンについて
@test "a 404 on vulnerability-alerts is DRIFT with admin access, UNKNOWN without" {
  fail_endpoint repos/owner/repo/vulnerability-alerts 1 'HTTP 404: Not Found'
  run -1 run_sync --check
  [[ "${output}" == *'DRIFT   vulnerability-alerts = false'* ]]
  edit_fixture repos/owner/repo '.permissions.admin = false'
  run -1 run_sync --check
  [[ "${output}" == *'UNKNOWN vulnerability-alerts'* ]]
}

@test "--check reports a ruleset that is gone as DRIFT" {
  edit_fixture 'repos/owner/repo/rulesets?includes_parents=false' '[]'
  run -1 run_sync --check
  [[ "${output}" == *'DRIFT   ruleset main = (missing)'* ]]
}

@test "--check pinpoints the ruleset parameter that differs" {
  edit_fixture repos/owner/repo/rulesets/1 \
    '(.rules[] | select(.type == "pull_request") | .parameters.required_review_thread_resolution) |= not'
  run -1 run_sync --check
  [[ "${output}" == *'rule pull_request parameter required_review_thread_resolution'* ]]
}

@test "--check reports a ruleset whose enforcement, target or bypass actors differ" {
  edit_fixture repos/owner/repo/rulesets/1 \
    '.enforcement = "evaluate" | .target = "tag" | .bypass_actors = [{actor_id: 1}]'
  run -1 run_sync --check
  [[ "${output}" == *'ruleset main: enforcement = evaluate'* ]]
  [[ "${output}" == *'ruleset main: target = tag'* ]]
  [[ "${output}" == *'ruleset main: bypass_actors = 1 entries'* ]]
}

@test "--check reports a ruleset that covers different branches" {
  edit_fixture repos/owner/repo/rulesets/1 \
    '.conditions.ref_name = {include: ["refs/heads/other"], exclude: ["refs/heads/tmp"]}'
  run -1 run_sync --check
  [[ "${output}" == *'conditions.ref_name.include'* ]]
  [[ "${output}" == *'conditions.ref_name.exclude'* ]]
}

@test "--check reports rules that are missing and rules that are not in the definition" {
  edit_fixture repos/owner/repo/rulesets/1 \
    '.rules |= map(select(.type != "code_scanning")) + [{type: "creation"}]'
  run -1 run_sync --check
  [[ "${output}" == *'rule code_scanning is missing'* ]]
  [[ "${output}" == *'unexpected rule creation'* ]]
}

# The API promises no order for rules, so a reordering must not read as drift.
@test "--check is indifferent to the order the API returns rules in" {
  edit_fixture repos/owner/repo/rulesets/1 '.rules |= reverse'
  run -0 run_sync --check
  [[ "${output}" == *'no drift'* ]]
}

@test "--check reports a deleted label as DRIFT" {
  edit_fixture repos/owner/repo/labels 'map(select(.name != "maintenance"))'
  run -1 run_sync --check
  [[ "${output}" == *'DRIFT   label maintenance = (missing)'* ]]
}

@test "REPO_SETTINGS=false limits the check to the rulesets" {
  fail_endpoint graphql 1
  REPO_SETTINGS=false run -0 run_sync --check
  [[ "${output}" == *'no drift'* ]]
}

@test "--dry-run prints the plan and changes nothing" {
  run -0 run_sync --dry-run
  [[ "${output}" == *'PATCH repos/owner/repo'* ]]
  [[ "${output}" == *'EDIT  .github/ISSUE_TEMPLATE/config.yml'* ]]
  assert_gh_not_called '--method'
  grep -q 'github\.com/OWNER/REPO/' "${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml"
}

@test "applies the settings and updates the ruleset of the same name in place" {
  run -0 run_sync
  assert_gh_called '--method PUT repos/owner/repo/rulesets/1'
  assert_gh_not_called '--method POST repos/owner/repo/rulesets'
  assert_gh_called '--method PATCH repos/owner/repo'
  assert_gh_called '--method PUT repos/owner/repo/immutable-releases'
  assert_gh_called '--method PUT repos/owner/repo/actions/permissions/workflow'
}

# The call log says which endpoint was hit; these are the payloads themselves.
@test "sends the ruleset definition and the settings values unchanged" {
  run -0 run_sync
  [ "$(gh_sent repos/owner/repo/rulesets/1)" = "$(cat "${REPO_COPY}/.github/rulesets/main.json")" ]
  [ "$(gh_sent repos/owner/repo | jq -r '.security_and_analysis.secret_scanning_push_protection.status')" = enabled ]
  assert_gh_called '-F allow_auto_merge=true'
  assert_gh_called '-F has_wiki=false'
  assert_gh_called '-F squash_merge_commit_title=PR_TITLE'
  assert_gh_called '-F default_workflow_permissions=read'
}

@test "REPO_SETTINGS=false applies the rulesets and touches nothing else" {
  REPO_SETTINGS=false run -0 run_sync
  assert_gh_called '--method PUT repos/owner/repo/rulesets/1'
  assert_gh_not_called '--method PATCH repos/owner/repo'
  assert_gh_not_called '--method PUT repos/owner/repo/actions/permissions/workflow'
  grep -q 'github\.com/OWNER/REPO/' "${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml"
}

@test "every definition in the directory is applied, RULESET_FILE narrows it to one" {
  jq '.name = "tags"' "${REPO_COPY}/.github/rulesets/main.json" >"${REPO_COPY}/.github/rulesets/tags.json"
  run -0 run_sync
  assert_gh_called '--method PUT repos/owner/repo/rulesets/1'
  assert_gh_called '--method POST repos/owner/repo/rulesets'
  : >"${GH_LOG}"
  RULESET_FILE="${REPO_COPY}/.github/rulesets/main.json" run -0 run_sync
  assert_gh_called '--method PUT repos/owner/repo/rulesets/1'
  assert_gh_not_called '--method POST repos/owner/repo/rulesets'
}

@test "stops when the existing rulesets cannot be listed, instead of creating a duplicate" {
  fail_endpoint 'repos/owner/repo/rulesets?includes_parents=false' 1
  run -1 run_sync
  assert_gh_not_called '--method POST repos/owner/repo/rulesets'
  assert_gh_not_called '--method PUT repos/owner/repo/rulesets/1'
}

@test "creates the ruleset when none of that name exists" {
  edit_fixture 'repos/owner/repo/rulesets?includes_parents=false' '[]'
  run -0 run_sync
  assert_gh_called '--method POST repos/owner/repo/rulesets'
  assert_gh_not_called '--method PUT repos/owner/repo/rulesets/1'
}

@test "rewrites config.yml to the repository name and demands a commit" {
  run -0 run_sync
  grep -q 'github\.com/owner/repo/' "${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml"
  [[ "${output}" == *'Action required: commit .github/ISSUE_TEMPLATE/config.yml'* ]]
}

@test "leaves a config.yml that carries no placeholder alone" {
  sed 's#OWNER/REPO#owner/repo#' "${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml" >"${BATS_TEST_TMPDIR}/config.yml"
  cp "${BATS_TEST_TMPDIR}/config.yml" "${REPO_COPY}/.github/ISSUE_TEMPLATE/config.yml"
  run -0 run_sync
  [[ "${output}" != *'Action required'* ]]
}

@test "creates only the labels that are missing" {
  edit_fixture repos/owner/repo/labels 'map(select(.name != "maintenance"))'
  run -0 run_sync
  assert_gh_called '--method POST repos/owner/repo/labels -f name=maintenance'
  assert_gh_not_called '-f name=bug'
}

@test "warns when classic branch protection is still on main" {
  pass_endpoint repos/owner/repo/branches/main/protection
  run -0 run_sync
  [[ "${output}" == *'classic branch protection'* ]]
}

# The two traps: a run that dies midway must say the application is partial, and
# must still demand the commit for the config.yml it already rewrote.
@test "a failure midway reports the partial application and the pending rewrite" {
  fail_endpoint repos/owner/repo/immutable-releases 1
  run -1 run_sync
  [[ "${output}" == *'Only part of the configuration was applied'* ]]
  [[ "${output}" == *'Action required: commit'* ]]
}

# The other side of that trap: nothing has been written yet while the script is still
# reading, so a failure there must not send the reader looking for half-applied settings.
@test "a failure before the first write is not called a partial application" {
  fail_endpoint repos/owner/repo 1
  run -1 run_sync
  assert_gh_not_called '--method'
  [[ "${output}" != *'Only part of the configuration'* ]]
}
