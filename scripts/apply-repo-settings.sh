#!/usr/bin/env bash
#
# Git管理された定義から、GitHubリポジトリの設定を再現する。
#
#   usage: scripts/apply-repo-settings.sh
#
# 対象リポジトリはカレントのgitリモートから解決する。
# 何度実行しても同じ状態になる（冪等）。
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
RULESET_DIR="${ROOT}/.github/rulesets"

log() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 1
}

# パスセグメントとして安全な形にエスケープする（"good first issue" など空白を含むラベル名用）
uri_escape() { jq -rn --arg s "$1" '$s | @uri'; }

# 途中で権限不足に気づいて中途半端に適用されるのを避けるため、
# 変更を始める前にすべて確認する。
log "前提チェック"

command -v gh >/dev/null 2>&1 || die "gh が見つからない。https://cli.github.com/ から導入する"
command -v jq >/dev/null 2>&1 || die "jq が見つからない。brew install jq などで導入する"
gh auth status >/dev/null 2>&1 || die "gh が未認証。gh auth login を実行する"

repo_json="$(gh repo view --json nameWithOwner,visibility,viewerPermission)" ||
  die "リポジトリを特定できない。gitリモートを確認する"

REPO="$(jq -r '.nameWithOwner' <<<"${repo_json}")"
visibility="$(jq -r '.visibility' <<<"${repo_json}")"
permission="$(jq -r '.viewerPermission' <<<"${repo_json}")"

# プライベートだと有償のGitHub Secret Protectionが必要な設定が含まれるため、
# パブリック限定にする
# https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning
[[ "${visibility}" = "PUBLIC" ]] || die "${REPO} は ${visibility}。このスクリプトはパブリックリポジトリ専用"
[[ "${permission}" = "ADMIN" ]] || die "${REPO} への権限が ${permission}。設定変更には ADMIN が必要"

info "対象: ${REPO} (${visibility} / ${permission})"

log "ルールセットを同期"

shopt -s nullglob
ruleset_files=("${RULESET_DIR}"/*.json)
shopt -u nullglob

if [[ "${#ruleset_files[@]}" -eq 0 ]]; then
  info "${RULESET_DIR} に定義なし。スキップ"
else
  # ループのたびにAPIを叩かないよう、id と name の対応表を先にまとめて取得する
  existing_rulesets="$(gh api --paginate "repos/${REPO}/rulesets" --jq '.[] | [.id, .name] | @tsv')"

  for file in "${ruleset_files[@]}"; do
    name="$(jq -r '.name // empty' "${file}")"
    [[ -n "${name}" ]] || die "${file#"${ROOT}"/} に name がない"

    id="$(awk -F'\t' -v n="${name}" '$2 == n { print $1; exit }' <<<"${existing_rulesets}")"

    if [[ -n "${id}" ]]; then
      gh api --silent --method PUT "repos/${REPO}/rulesets/${id}" --input "${file}"
      info "更新: ${name} (id=${id})"
    else
      gh api --silent --method POST "repos/${REPO}/rulesets" --input "${file}"
      info "作成: ${name}"
    fi
  done
fi

log "リポジトリ設定を適用"

gh api --silent --method PATCH "repos/${REPO}" --input - <<'JSON'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "has_wiki": false,
  "has_projects": false,
  "has_discussions": false
}
JSON

info "マージ方法: squashのみ / 自動マージ: 有効 / マージ後にブランチ削除: 有効"
info "Wiki・Projects・Discussions: 無効"

# シークレットスキャンを先に、プッシュ保護を後に適用する。
# APIレベルでの依存関係は公式ドキュメントで確認できていない（未検証）が、
# GitHubのUI手順がこの順序のため合わせている。
log "セキュリティ機能を有効化"

gh api --silent --method PATCH "repos/${REPO}" --input - <<'JSON'
{ "security_and_analysis": { "secret_scanning": { "status": "enabled" } } }
JSON
info "シークレットスキャン"

gh api --silent --method PATCH "repos/${REPO}" --input - <<'JSON'
{ "security_and_analysis": { "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
info "プッシュ保護"

gh api --silent --method PUT "repos/${REPO}/vulnerability-alerts"
info "Dependabotアラート"

gh api --silent --method PUT "repos/${REPO}/automated-security-fixes"
info "Dependabotセキュリティアップデート"

gh api --silent --method PUT "repos/${REPO}/private-vulnerability-reporting"
info "脆弱性の非公開報告"

gh api --silent --method PUT "repos/${REPO}/immutable-releases"
info "リリースの不変化"

# CodeQLのデフォルトセットアップ。ルールセットの code_scanning ルールが
# CodeQLの結果を要求するため、これが未設定だとmainへのマージがブロックされる。
#
# 解析中にPATCHすると409になりうるので、現在の状態を見てから変更する。
# languages を明示しているのは、このリポジトリにCodeQL対応言語のコードがなく、
# 解析対象がワークフロー（actions）だけのため。対応言語のコードを置いたらここに足す。
codeql_state="$(gh api "repos/${REPO}/code-scanning/default-setup" --jq '.state')"

if [[ "${codeql_state}" = "configured" ]]; then
  info "CodeQL: 既に有効"
else
  gh api --silent --method PATCH "repos/${REPO}/code-scanning/default-setup" --input - <<'JSON'
{
  "state": "configured",
  "query_suite": "default",
  "languages": [
    "actions"
  ]
}
JSON
  info "CodeQL: 有効化（初回の解析が終わるまでマージはブロックされる）"
fi

# allowed_actions を selected にしてから、許可する範囲を指定する順序で呼ぶ。
# https://docs.github.com/en/rest/actions/permissions
log "GitHub Actions を設定"

gh api --silent --method PUT "repos/${REPO}/actions/permissions/workflow" --input - <<'JSON'
{
  "default_workflow_permissions": "read",
  "can_approve_pull_request_reviews": false
}
JSON
info "GITHUB_TOKEN の既定権限: 読み取りのみ"

gh api --silent --method PUT "repos/${REPO}/actions/permissions" --input - <<'JSON'
{ "enabled": true, "allowed_actions": "selected" }
JSON

gh api --silent --method PUT "repos/${REPO}/actions/permissions/selected-actions" --input - <<'JSON'
{
  "github_owned_allowed": true,
  "verified_allowed": true,
  "patterns_allowed": []
}
JSON
info "実行可能なアクション: GitHub公式と検証済みのみ"

log "ラベルを整理"

existing_labels="$(gh api --paginate "repos/${REPO}/labels" --jq '.[].name')"
label_exists() { grep -Fxq "$1" <<<"${existing_labels}"; }

# GitHubが新規リポジトリに作る既定ラベルのうち、このリポジトリで使わないもの。
# bug と enhancement は既定にもあるが下で上書きするため、ここには含めない。
unused_default_labels=(
  "accessibility"
  "documentation"
  "duplicate"
  "good first issue"
  "help wanted"
  "invalid"
  "question"
  "wontfix"
)

for name in "${unused_default_labels[@]}"; do
  # label_exists は gh の終了コードで真偽を返す関数なので、if 条件で呼ぶのが正しい使い方
  # shellcheck disable=SC2310
  if label_exists "${name}"; then
    escaped="$(uri_escape "${name}")"
    gh api --silent --method DELETE "repos/${REPO}/labels/${escaped}"
    info "削除: ${name}"
  fi
done

# 使うラベル。書式は "名前<TAB>色<TAB>説明"
# 説明は100文字まで: https://docs.github.com/en/rest/issues/labels
managed_labels=(
  $'bug\td73a4a\tバグ・不具合の報告'
  $'dependencies\t0366d6\t依存関係の更新'
  $'enhancement\ta2eeef\t新機能・改善の提案'
  $'maintenance\tfbca04\tリファクタリング・設定変更などの保守作業'
)

for entry in "${managed_labels[@]}"; do
  IFS=$'\t' read -r name color description <<<"${entry}"
  # label_exists は gh の終了コードで真偽を返す関数なので、if 条件で呼ぶのが正しい使い方
  # shellcheck disable=SC2310
  if label_exists "${name}"; then
    escaped="$(uri_escape "${name}")"
    gh api --silent --method PATCH "repos/${REPO}/labels/${escaped}" \
      -f "new_name=${name}" -f "color=${color}" -f "description=${description}"
    info "更新: ${name}"
  else
    gh api --silent --method POST "repos/${REPO}/labels" \
      -f "name=${name}" -f "color=${color}" -f "description=${description}"
    info "作成: ${name}"
  fi
done

log "完了: ${REPO}"
