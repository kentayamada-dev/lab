#!/usr/bin/env bash
#
# Applies the GitHub Repository Rulesets in .github/rulesets/*.json together with the
# repository settings. For the list of what is applied see "Setup" in the README; for
# what the rulesets contain see "What branch protection enforces".
#
# It also rewrites OWNER/REPO inside .github/ISSUE_TEMPLATE/config.yml to the actual
# repository name. That only changes the working tree, so a separate commit is needed
# (a reminder is printed after the run).
#
# Only public repositories are supported (rulesets / branch protection may be
# unavailable on private ones).
#
# Usage:
#   ./scripts/sync-repo-config.sh            # apply (updates a ruleset of the same name)
#   ./scripts/sync-repo-config.sh --dry-run  # only print what would be sent (changes nothing)
#   ./scripts/sync-repo-config.sh --check    # only check whether the current settings match
#                                            # (lists the differences and exits 1 on drift)
#
# Environment variables:
#   REPO           target repository (default: derived from the origin remote)
#   RULESET_FILE   apply only one ruleset JSON (default: apply all of .github/rulesets/*.json)
#   REPO_SETTINGS  set to false to skip changing repository settings (default: true)
#
set -euo pipefail

DRY_RUN=false
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) CHECK=true ;;
    -h | --help)
      awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/, ""); print}' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ "$DRY_RUN" == true && "$CHECK" == true ]]; then
  echo "--dry-run and --check cannot be given together" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULESET_DIR="${repo_root}/.github/rulesets"
REPO_SETTINGS="${REPO_SETTINGS:-true}"
ISSUE_CONFIG="${repo_root}/.github/ISSUE_TEMPLATE/config.yml"
ISSUE_CONFIG_REL="${ISSUE_CONFIG#"${repo_root}"/}"

REPO_SETTINGS_EXPECTED=(
  "allow_auto_merge          autoMergeAllowed         true"
  "delete_branch_on_merge    deleteBranchOnMerge      true"
  "allow_update_branch       allowUpdateBranch        true"
  "allow_squash_merge        squashMergeAllowed       true"
  "allow_merge_commit        mergeCommitAllowed       false"
  "allow_rebase_merge        rebaseMergeAllowed       false"
  "squash_merge_commit_title squashMergeCommitTitle   PR_TITLE"
  "has_issues                hasIssuesEnabled         true"
  "has_discussions           hasDiscussionsEnabled    true"
  "has_projects              hasProjectsEnabled       true"
  "has_wiki                  hasWikiEnabled           false"
)

REPO_SETTINGS_ENDPOINTS=(
  immutable-releases
  private-vulnerability-reporting
  # Dependabot alerts. Unlike the two above, its GET returns no body (204 enabled /
  # 404 disabled), so the check reads the status code instead of .enabled.
  vulnerability-alerts
)

# Nested under security_and_analysis in the repository object, so it is neither a flat
# setting nor an endpoint of its own. Secret scanning itself is enabled by default on
# public repositories; if it has been turned off, enabling push protection fails.
SECURITY_ANALYSIS_EXPECTED=(
  "secret_scanning_push_protection enabled"
)

ACTIONS_WORKFLOW_EXPECTED=(
  "default_workflow_permissions     read"
  "can_approve_pull_request_reviews false"
)

LABELS_EXPECTED=(
  "bug          d73a4a Something isn't working"
  "dependencies 0366d6 Dependency updates"
  "enhancement  a2eeef New feature or request"
  "maintenance  fef2c0 Repository maintenance (failed scheduled checks, etc.)"
)

# When config.yml was rewritten, the reminder should appear after the settings output
# (= at the very bottom of the screen). The rewrite also survives an early error exit,
# so print it unconditionally from an EXIT trap.
issue_config_rewritten=false
notify_issue_config() {
  [[ "$issue_config_rewritten" == true ]] || return 0
  cat <<MSG

============================================================
 Action required: commit ${ISSUE_CONFIG_REL}
============================================================
 The Discussions link shown on the issue creation page was rewritten:
   OWNER/REPO -> ${REPO}
 So far this change exists only in your local working tree.

 GitHub reads the config.yml on main, so until you commit it and get it
 onto main, this link keeps pointing at the template's own repository.

   git switch -c fix/discussions-link
   git add ${ISSUE_CONFIG_REL}
   git commit -m "Fix Discussions link in issue template"
   git push -u origin HEAD && gh pr create

 This script has just protected main, so you cannot push to it directly.
 Create a branch as above and land the change through a PR.
============================================================
MSG
}
trap notify_issue_config EXIT

# Makes it clear where application stopped when something fails midway. The error
# message alone does not tell you that the repository settings were not applied.
#
# This hooks ERR rather than EXIT because notify_issue_config above already uses the
# EXIT trap (a later trap replaces the earlier one). ERR does not fire on an exit, so
# it never duplicates the places that print their own message and then exit.
notify_partial() {
  # --dry-run and --check change nothing, so this reminder is not needed.
  if [[ "$DRY_RUN" == true || "$CHECK" == true ]]; then
    return 0
  fi
  cat >&2 <<'MSG'

------------------------------------------------------------
 Aborted. Only part of the configuration was applied.
 Use --check to see what is applied and what is not.

   ./scripts/sync-repo-config.sh --check
------------------------------------------------------------
MSG
}
trap notify_partial ERR

# Prints the differences between a ruleset definition ($1, a path) and what the API
# returned for it ($2, JSON), one per line, and prints nothing when they agree. Only
# what the definition names is compared, arrays sorted first (docs/drift-check.md).
ruleset_diff() {
  jq -r -n --slurpfile want "$1" --argjson got "$2" '
    def canon: walk(if type == "array" then sort_by(tojson) else . end);
    def rules_by_type: (.rules // []) | map({ key: .type, value: ((.parameters // {}) | canon) }) | from_entries;

    ($want[0]) as $w
    | ($w | rules_by_type) as $wr
    | ($got | rules_by_type) as $gr
    | [
        (["enforcement", "target"][] as $k
          | select(($w[$k] // null) != null and $w[$k] != $got[$k])
          | "\($k) = \($got[$k] // "(missing)") (expected: \($w[$k]))"),

        ((($w.bypass_actors // []) | length) as $wn
          | (($got.bypass_actors // []) | length) as $gn
          | select($wn != $gn)
          | "bypass_actors = \($gn) entries (expected: \($wn))"),

        (["include", "exclude"][] as $k
          | ((($w.conditions.ref_name[$k]) // []) | canon) as $wv
          | ((($got.conditions.ref_name[$k]) // []) | canon) as $gv
          | select($wv != $gv)
          | "conditions.ref_name.\($k) = \($gv | tojson) (expected: \($wv | tojson))"),

        ($wr | keys_unsorted[] as $t | select(($gr | has($t)) | not) | "rule \($t) is missing"),
        ($gr | keys_unsorted[] as $t | select(($wr | has($t)) | not) | "unexpected rule \($t)"),

        ($wr | to_entries[] as $rule
          | select($gr | has($rule.key))
          | $rule.value | to_entries[] as $param
          | ($gr[$rule.key][$param.key]) as $gv
          | select(($gv | tojson) != ($param.value | tojson))
          | "rule \($rule.key) parameter \($param.key) = \(if $gv == null then "(missing)" else ($gv | tojson) end) (expected: \($param.value | tojson))")
      ][]
  '
}

CHECK_DRIFT=false
CHECK_UNREADABLE=false
check_settings() {
  local current key gql want got err name kv endpoint fields i id ruleset_now diff_lines line

  if [[ "$REPO_SETTINGS" == true ]]; then
    fields=""
    for kv in "${REPO_SETTINGS_EXPECTED[@]}"; do
      read -r key gql want <<<"$kv"
      fields="${fields} ${gql}"
    done
    # owner and name are passed as variables (not embedded in the query). Field names
    # cannot be variables so they are assembled, but they come from the definition
    # above, so nothing external can slip in.
    if ! current="$(gh api graphql -F owner="${REPO%%/*}" -F name="${REPO#*/}" \
      -f query="query(\$owner: String!, \$name: String!) {
        repository(owner: \$owner, name: \$name) {${fields} }
      }" 2>/dev/null)"; then
      current='{}'
    fi
    for kv in "${REPO_SETTINGS_EXPECTED[@]}"; do
      read -r key gql want <<<"$kv"
      got="$(jq -r --arg k "$gql" 'if (.data.repository // {}) | has($k) then (.data.repository[$k] | tostring) else empty end' <<<"$current")"
      if [[ -z "$got" ]]; then
        echo "  UNKNOWN ${key} (not present in the response)"
        CHECK_UNREADABLE=true
      elif [[ "$got" == "$want" ]]; then
        echo "  OK      ${key} = ${got}"
      else
        echo "  DRIFT   ${key} = ${got} (expected: ${want})"
        CHECK_DRIFT=true
      fi
    done

    for endpoint in "${REPO_SETTINGS_ENDPOINTS[@]}"; do
      if [[ "$endpoint" == vulnerability-alerts ]]; then
        # No body to read .enabled from (see the definition above). A user token without
        # admin read also gets 404 (only app tokens get 403), indistinguishable from
        # "disabled" — hence the admin check (docs/drift-check.md "About the token").
        if err="$(gh api --silent "repos/${REPO}/${endpoint}" 2>&1)"; then
          echo "  OK      ${endpoint} = true"
        elif grep -q 'HTTP 404' <<<"$err"; then
          if [[ "$(gh api "repos/${REPO}" --jq '.permissions.admin' 2>/dev/null)" == true ]]; then
            echo "  DRIFT   ${endpoint} = false (expected: true)"
            CHECK_DRIFT=true
          else
            echo "  UNKNOWN ${endpoint} (404 without admin access; cannot tell disabled from unreadable)"
            CHECK_UNREADABLE=true
          fi
        else
          echo "  UNKNOWN ${endpoint} (cannot be fetched)"
          CHECK_UNREADABLE=true
        fi
        continue
      fi
      # The point is not to assign to got on failure. gh prints the error body to
      # stdout, so catching it with || would mix that body into the value.
      if ! got="$(gh api "repos/${REPO}/${endpoint}" --jq '.enabled | tostring' 2>/dev/null)"; then
        echo "  UNKNOWN ${endpoint} (cannot be fetched)"
        CHECK_UNREADABLE=true
      elif [[ "$got" == true ]]; then
        echo "  OK      ${endpoint} = ${got}"
      else
        echo "  DRIFT   ${endpoint} = ${got} (expected: true)"
        CHECK_DRIFT=true
      fi
    done

    if ! current="$(gh api "repos/${REPO}" 2>/dev/null)"; then
      echo "  UNKNOWN security_and_analysis (cannot be fetched)"
      CHECK_UNREADABLE=true
    else
      for kv in "${SECURITY_ANALYSIS_EXPECTED[@]}"; do
        read -r key want <<<"$kv"
        got="$(jq -r --arg k "$key" '.security_and_analysis[$k].status // empty' <<<"$current")"
        if [[ -z "$got" ]]; then
          echo "  UNKNOWN ${key} (not present in the response)"
          CHECK_UNREADABLE=true
        elif [[ "$got" == "$want" ]]; then
          echo "  OK      ${key} = ${got}"
        else
          echo "  DRIFT   ${key} = ${got} (expected: ${want})"
          CHECK_DRIFT=true
        fi
      done
    fi

    if ! current="$(gh api "repos/${REPO}/actions/permissions/workflow" 2>/dev/null)"; then
      echo "  UNKNOWN actions/permissions/workflow (cannot be fetched)"
      CHECK_UNREADABLE=true
    else
      for kv in "${ACTIONS_WORKFLOW_EXPECTED[@]}"; do
        read -r key want <<<"$kv"
        got="$(jq -r --arg k "$key" '.[$k] | tostring' <<<"$current")"
        if [[ "$got" == "$want" ]]; then
          echo "  OK      ${key} = ${got}"
        else
          echo "  DRIFT   ${key} = ${got} (expected: ${want})"
          CHECK_DRIFT=true
        fi
      done
    fi

    if ! current="$(gh api --paginate "repos/${REPO}/labels" --jq '.[].name' 2>/dev/null)"; then
      echo "  UNKNOWN cannot fetch the list of labels"
      CHECK_UNREADABLE=true
    else
      for kv in "${LABELS_EXPECTED[@]}"; do
        read -r name _ <<<"$kv"
        if grep -Fxq "$name" <<<"$current"; then
          echo "  OK      label ${name} = present"
        else
          echo "  DRIFT   label ${name} = (missing) (expected: present)"
          CHECK_DRIFT=true
        fi
      done
    fi
  else
    echo "  skipping the repository settings check because REPO_SETTINGS=false"
  fi

  # includes_parents=false: with the default (true), organization / enterprise rulesets
  # are mixed into the listing. If one shares a name, which one a name lookup hits is
  # undefined, and an active parent would report OK even when the repository itself has
  # none. Only this repository's own rulesets are of interest, so it is turned off (the
  # two places on the apply side below set it for the same reason).
  if ! current="$(gh api "repos/${REPO}/rulesets?includes_parents=false" 2>/dev/null)"; then
    echo "  UNKNOWN cannot fetch the list of rulesets"
    CHECK_UNREADABLE=true
  else
    for i in "${!RULESET_FILES[@]}"; do
      name="${RULESET_NAMES[$i]}"
      # The listing carries no rules, so the ruleset itself has to be fetched by id.
      id="$(jq -r --arg name "$name" 'map(select(.name == $name)) | .[0].id // empty' <<<"$current")"
      if [[ -z "$id" ]]; then
        echo "  DRIFT   ruleset ${name} = (missing) (expected: active)"
        CHECK_DRIFT=true
        continue
      fi
      if ! ruleset_now="$(gh api "repos/${REPO}/rulesets/${id}" 2>/dev/null)"; then
        echo "  UNKNOWN ruleset ${name} (cannot be fetched)"
        CHECK_UNREADABLE=true
        continue
      fi
      diff_lines="$(ruleset_diff "${RULESET_FILES[$i]}" "$ruleset_now")"
      if [[ -z "$diff_lines" ]]; then
        echo "  OK      ruleset ${name} = $(jq -r .enforcement <<<"$ruleset_now") (contents match the definition)"
      else
        while IFS= read -r line; do
          echo "  DRIFT   ruleset ${name}: ${line}"
        done <<<"$diff_lines"
        CHECK_DRIFT=true
      fi
    done
  fi

  if [[ "$CHECK_DRIFT" == true || "$CHECK_UNREADABLE" == true ]]; then
    return 1
  fi
  return 0
}

command -v gh >/dev/null || {
  echo "the gh CLI is required: https://cli.github.com/" >&2
  exit 1
}
command -v jq >/dev/null || {
  echo "jq is required: https://jqlang.github.io/jq/" >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "run gh auth login first" >&2
  exit 1
}

if [[ -n "${RULESET_FILE:-}" ]]; then
  RULESET_FILES=("$RULESET_FILE")
else
  shopt -s nullglob
  RULESET_FILES=("$RULESET_DIR"/*.json)
  shopt -u nullglob
fi
[[ ${#RULESET_FILES[@]} -gt 0 ]] || {
  echo "no ruleset found: ${RULESET_DIR}/*.json" >&2
  exit 1
}

# If even one is broken, exit without applying anything (never leave a half-applied
# state).
RULESET_NAMES=()
for f in "${RULESET_FILES[@]}"; do
  [[ -f "$f" ]] || {
    echo "ruleset not found: ${f}" >&2
    exit 1
  }
  jq empty "$f" || {
    echo "the ruleset JSON is invalid: ${f}" >&2
    exit 1
  }
  ruleset_name="$(jq -r '.name // empty' "$f")"
  [[ -n "$ruleset_name" ]] || {
    echo "the ruleset has no name: ${f}" >&2
    exit 1
  }
  RULESET_NAMES+=("$ruleset_name")
done

if [[ -z "${REPO:-}" ]]; then
  # Resolve it from the repository root so the result does not depend on cwd.
  REPO="$(cd "$repo_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

visibility="$(gh api "repos/${REPO}" --jq .visibility)"
if [[ "$visibility" != public ]]; then
  cat >&2 <<MSG
error: ${REPO} is a ${visibility} repository. This script only supports public ones.
  Rulesets / branch protection may be unavailable on private repositories.
MSG
  exit 1
fi

echo "target: ${REPO} (${visibility})"
for i in "${!RULESET_FILES[@]}"; do
  echo "ruleset: ${RULESET_NAMES[$i]} <- ${RULESET_FILES[$i]#"${repo_root}"/}"
done

if [[ "$CHECK" == true ]]; then
  echo "checking the current settings (nothing is changed)"
  if check_settings; then
    echo "no drift"
    exit 0
  fi
  if [[ "$CHECK_DRIFT" == true ]]; then
    echo "the settings have drifted from this script's definitions. Run it without arguments to apply them." >&2
  fi
  if [[ "$CHECK_UNREADABLE" == true ]]; then
    cat >&2 <<'MSG'
Some items could not be checked because the token lacks permissions.
The default GITHUB_TOKEN in GitHub Actions cannot read immutable releases,
Dependabot alerts, secret scanning push protection, or the default permissions of
the Actions GITHUB_TOKEN. Register a PAT with Administration read access as the
SETTINGS_TOKEN secret (see docs/drift-check.md).
MSG
  fi
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  for f in "${RULESET_FILES[@]}"; do
    cat "$f"
  done
  if [[ "$REPO_SETTINGS" == true ]]; then
    echo "PATCH repos/${REPO}"
    for kv in "${REPO_SETTINGS_EXPECTED[@]}"; do
      read -r rest_key _ want <<<"$kv"
      echo "        ${rest_key} = ${want}"
    done
    echo "PATCH repos/${REPO}"
    for kv in "${SECURITY_ANALYSIS_EXPECTED[@]}"; do
      read -r key want <<<"$kv"
      echo "        security_and_analysis.${key}.status = ${want}"
    done
    for endpoint in "${REPO_SETTINGS_ENDPOINTS[@]}"; do
      echo "PUT   repos/${REPO}/${endpoint}"
    done
    echo "PUT   repos/${REPO}/actions/permissions/workflow"
    for kv in "${ACTIONS_WORKFLOW_EXPECTED[@]}"; do
      read -r key want <<<"$kv"
      echo "        ${key} = ${want}"
    done
    echo "POST  repos/${REPO}/labels (creates only the missing ones)"
    for kv in "${LABELS_EXPECTED[@]}"; do
      read -r name color description <<<"$kv"
      echo "        ${name} (color: ${color} / description: ${description})"
    done
    if grep -q 'github\.com/OWNER/REPO/' "$ISSUE_CONFIG" 2>/dev/null; then
      echo "EDIT  ${ISSUE_CONFIG_REL} (OWNER/REPO -> ${REPO})"
      echo "      ^ only changes the working tree, so a separate commit is needed afterwards"
    fi
  fi
  exit 0
fi

while read -r ref; do
  case "$ref" in
    refs/heads/*) branch="${ref#refs/heads/}" ;;
    *) continue ;; # meta refs such as ~DEFAULT_BRANCH are out of scope
  esac
  if gh api "repos/${REPO}/branches/${branch}/protection" >/dev/null 2>&1; then
    echo "warning: classic branch protection is set on ${branch}. It applies alongside the ruleset." >&2
  fi
done < <(jq -r '.conditions.ref_name.include[]?' "${RULESET_FILES[@]}" | sort -u)

# See the comment in check_settings for why includes_parents=false. The jq below prints
# every id whose name matches, so a parent ruleset slipping in would yield two lines and
# turn the target of the following PUT into a broken string.
existing_rulesets="$(gh api "repos/${REPO}/rulesets?includes_parents=false" 2>/dev/null || echo '[]')"

for i in "${!RULESET_FILES[@]}"; do
  ruleset_file="${RULESET_FILES[$i]}"
  ruleset_name="${RULESET_NAMES[$i]}"
  existing_id="$(jq -r --arg name "$ruleset_name" '.[] | select(.name == $name) | .id' <<<"$existing_rulesets")"

  if [[ -n "$existing_id" ]]; then
    echo "updating the existing ruleset #${existing_id} (${ruleset_name})"
    gh api --method PUT "repos/${REPO}/rulesets/${existing_id}" --input "$ruleset_file" >/dev/null
  else
    echo "creating the ruleset ${ruleset_name}"
    gh api --method POST "repos/${REPO}/rulesets" --input "$ruleset_file" >/dev/null
  fi
done

if [[ "$REPO_SETTINGS" == true ]]; then
  echo "updating the repository settings (auto-merge / delete branch on merge / update branch / squash only / squash title)"
  patch_args=()
  for kv in "${REPO_SETTINGS_EXPECTED[@]}"; do
    read -r rest_key _ want <<<"$kv"
    patch_args+=(-F "${rest_key}=${want}")
  done
  gh api --method PATCH "repos/${REPO}" "${patch_args[@]}" >/dev/null

  echo "enabling secret scanning push protection"
  # A nested object, so it cannot be expressed with -F. It is sent as a separate PATCH
  # rather than merged into the one above so that a failure here (secret scanning turned
  # off, for instance) does not hide whether the flat settings were applied.
  security_body='{}'
  for kv in "${SECURITY_ANALYSIS_EXPECTED[@]}"; do
    read -r key want <<<"$kv"
    security_body="$(jq --arg k "$key" --arg v "$want" '.security_and_analysis[$k] = { status: $v }' <<<"$security_body")"
  done
  gh api --method PATCH "repos/${REPO}" --input - <<<"$security_body" >/dev/null

  if grep -q 'github\.com/OWNER/REPO/' "$ISSUE_CONFIG" 2>/dev/null; then
    # sed -i is avoided because its arguments differ between BSD and GNU. The write-back
    # uses cp rather than mv so the temporary file's permissions do not overwrite the
    # original file's.
    tmp="${ISSUE_CONFIG}.tmp"
    sed "s#github\.com/OWNER/REPO/#github.com/${REPO}/#g" "$ISSUE_CONFIG" >"$tmp"
    cp "$tmp" "$ISSUE_CONFIG"
    rm -f "$tmp"
    echo "rewrote: ${ISSUE_CONFIG_REL} (OWNER/REPO -> ${REPO}) ... needs a commit (see the note at the end)"
    issue_config_rewritten=true
  fi

  for endpoint in "${REPO_SETTINGS_ENDPOINTS[@]}"; do
    echo "enabling ${endpoint}"
    gh api --method PUT "repos/${REPO}/${endpoint}" >/dev/null
  done

  echo "setting the default permissions of the Actions GITHUB_TOKEN (read only / creating and approving PRs forbidden)"
  workflow_args=()
  for kv in "${ACTIONS_WORKFLOW_EXPECTED[@]}"; do
    read -r key want <<<"$kv"
    workflow_args+=(-F "${key}=${want}")
  done
  gh api --method PUT "repos/${REPO}/actions/permissions/workflow" "${workflow_args[@]}" >/dev/null

  existing_labels="$(gh api --paginate "repos/${REPO}/labels" --jq '.[].name')"
  for kv in "${LABELS_EXPECTED[@]}"; do
    read -r name color description <<<"$kv"
    if grep -Fxq "$name" <<<"$existing_labels"; then
      echo "label ${name} already exists"
    else
      echo "creating label ${name}"
      gh api --method POST "repos/${REPO}/labels" \
        -f name="$name" -f color="$color" -f description="$description" >/dev/null
    fi
  done
fi

echo "done. current settings:"
rulesets_now="$(gh api "repos/${REPO}/rulesets?includes_parents=false")"
for ruleset_name in "${RULESET_NAMES[@]}"; do
  id="$(jq -r --arg name "$ruleset_name" '.[] | select(.name == $name) | .id' <<<"$rulesets_now")"
  [[ -n "$id" ]] || {
    echo "  ${ruleset_name}: could not be fetched after applying" >&2
    continue
  }
  # Omit the whole line for rules a ruleset does not have. Rule sets can differ in which
  # rules they configure, so printing every line unconditionally would show misleading
  # lines such as "direct push: allowed" for a ruleset that has no such rule.
  gh api "repos/${REPO}/rulesets/${id}" --jq '
    "  name            : \(.name) (\(.enforcement))",
    "  targets         : \(.conditions.ref_name.include | join(", "))\(if ((.conditions.ref_name.exclude // []) | length) > 0 then " (excluded: \(.conditions.ref_name.exclude | join(", ")))" else "" end)",
    (if any(.rules[]; .type == "pull_request") then (
      "  direct push     : forbidden (PR required)",
      "  approvals       : \([.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | first)"
    ) else empty end),
    (if any(.rules[]; .type == "required_status_checks") then (
      "  required CI     : \([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | "\(.context)\(if .integration_id then " (app \(.integration_id) only)" else "" end)"] | join(", "))",
      "  up to date      : \(if any(.rules[]; .type == "required_status_checks" and .parameters.strict_required_status_checks_policy) then "required" else "not required" end)"
    ) else empty end),
    (if any(.rules[]; .type == "non_fast_forward") then "  force-push      : forbidden" else empty end),
    (if any(.rules[]; .type == "deletion") then "  branch deletion : forbidden" else empty end),
    (if any(.rules[]; .type == "required_linear_history") then "  linear history  : required" else empty end)
  '
done

gh api "repos/${REPO}" --jq '
  "  auto-merge      : \(if .allow_auto_merge then "enabled" else "disabled" end)",
  "  delete on merge : \(if .delete_branch_on_merge then "enabled" else "disabled" end)",
  "  update branch   : \(if .allow_update_branch then "enabled" else "disabled" end)",
  "  Issues          : \(if .has_issues then "enabled" else "disabled" end)",
  "  Discussions     : \(if .has_discussions then "enabled" else "disabled" end)",
  "  Projects        : \(if .has_projects then "enabled" else "disabled" end)",
  "  Wiki            : \(if .has_wiki then "enabled" else "disabled" end)",
  "  merge methods   : \([if .allow_squash_merge then "squash" else empty end, if .allow_merge_commit then "merge" else empty end, if .allow_rebase_merge then "rebase" else empty end] | join(", "))",
  "  squash title    : \(.squash_merge_commit_title)",
  "  push protection : \(.security_and_analysis.secret_scanning_push_protection.status // "unknown")"
'
gh api "repos/${REPO}/immutable-releases" --jq '
  "  immutable rel.  : \(if .enabled then "enabled" else "disabled" end)"
'
gh api "repos/${REPO}/private-vulnerability-reporting" --jq '
  "  private reports : \(if .enabled then "enabled" else "disabled" end)"
'
# 204 / 404 with no body (see REPO_SETTINGS_ENDPOINTS), so no --jq here.
if gh api --silent "repos/${REPO}/vulnerability-alerts" 2>/dev/null; then
  echo "  vuln alerts     : enabled"
else
  echo "  vuln alerts     : disabled"
fi
gh api "repos/${REPO}/actions/permissions/workflow" --jq '
  "  Actions perms   : GITHUB_TOKEN is \(.default_workflow_permissions) / creating and approving PRs is \(if .can_approve_pull_request_reviews then "allowed" else "forbidden" end)"
'
