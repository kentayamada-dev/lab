#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
#
# scripts/apply-repo-settings.sh のテスト。
#
# このスクリプトの振る舞いは、ほぼすべてがGitHubへの呼び出しそのもの。
# そこで gh をスタブに差し替え、「実際に何を送るか」「何を送らないか」を観測する。
# 実リポジトリの設定は一切変更しない。

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../apply-repo-settings.sh"
  setup_stubs
  install_gh_stub

  REPO="kentayamada/lab"
  REPO_DIR="$(make_repo)"

  export GH_REPO_JSON='{"nameWithOwner":"kentayamada/lab","visibility":"PUBLIC","viewerPermission":"ADMIN"}'
  export GH_RULESETS_TSV=""
  export GH_CODEQL_STATE="not-configured"
  export GH_LABELS=""

  cd "$REPO_DIR"
}

write_ruleset() {
  printf '%s\n' "$2" > "$REPO_DIR/.github/rulesets/$1"
}

# gh api 呼び出しの総数
api_call_count() {
  grep -c '^api ' "$GH_LOG" || true
}

# --input - で送られた本文のうち、指定文字列を含む最初のものを出力する
body_containing() {
  grep -m1 -F "$1" "$GH_BODY_LOG" | cut -f2-
}

# ---- 前提チェック -----------------------------------------------------------------------------

@test "gh が無ければ導入を促して終わる" {
  run -1 env PATH="$(only_commands git jq)" "$SCRIPT"

  assert_contains "$output" "gh が見つからない"
}

@test "jq が無ければ導入を促して終わる" {
  run -1 env PATH="$(only_commands git gh)" "$SCRIPT"

  assert_contains "$output" "jq が見つからない"
}

@test "gh が未認証なら gh auth login を促して終わる" {
  export GH_AUTH_EXIT=1

  run -1 "$SCRIPT"

  assert_contains "$output" "gh auth login"
}

@test "リポジトリを特定できなければ終わる" {
  export GH_REPO_VIEW_EXIT=1

  run -1 "$SCRIPT"

  assert_contains "$output" "リポジトリを特定できない"
}

@test "プライベートリポジトリでは何も変更せずに終わる" {
  # 有償のGitHub Secret Protectionが必要な設定を含むため、対象はパブリック限定
  export GH_REPO_JSON='{"nameWithOwner":"kentayamada/lab","visibility":"PRIVATE","viewerPermission":"ADMIN"}'

  run -1 "$SCRIPT"

  assert_contains "$output" "パブリックリポジトリ専用"
  # 中途半端に適用されないこと
  [ "$(api_call_count)" -eq 0 ]
}

@test "ADMIN でなければ何も変更せずに終わる" {
  export GH_REPO_JSON='{"nameWithOwner":"kentayamada/lab","visibility":"PUBLIC","viewerPermission":"WRITE"}'

  run -1 "$SCRIPT"

  assert_contains "$output" "ADMIN が必要"
  [ "$(api_call_count)" -eq 0 ]
}

# ---- ルールセット -----------------------------------------------------------------------------

@test "同名のルールセットが無ければ作成する" {
  write_ruleset "main.json" '{"name":"main","target":"branch"}'

  run -0 "$SCRIPT"

  assert_contains "$output" "作成: main"
  [ "$(gh_calls_matching "--method POST" "repos/$REPO/rulesets" "main.json")" -eq 1 ]
}

@test "同名のルールセットがあれば そのidを更新する" {
  write_ruleset "main.json" '{"name":"main","target":"branch"}'
  export GH_RULESETS_TSV=$'42\tmain'

  run -0 "$SCRIPT"

  assert_contains "$output" "更新: main (id=42)"
  [ "$(gh_calls_matching "--method PUT" "repos/$REPO/rulesets/42")" -eq 1 ]
  [ "$(gh_calls_matching "--method POST" "repos/$REPO/rulesets")" -eq 0 ]
}

@test "別名のルールセットだけがあるときは作成する" {
  write_ruleset "main.json" '{"name":"main","target":"branch"}'
  export GH_RULESETS_TSV=$'42\tother'

  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method POST" "repos/$REPO/rulesets")" -eq 1 ]
  [ "$(gh_calls_matching "repos/$REPO/rulesets/42")" -eq 0 ]
}

@test "ルールセットの定義が無ければ一覧も取得せずスキップする" {
  run -0 "$SCRIPT"

  assert_contains "$output" "定義なし。スキップ"
  [ "$(gh_calls_matching "rulesets")" -eq 0 ]
}

@test "ルールセットに name が無ければ終わる" {
  write_ruleset "main.json" '{"target":"branch"}'

  run -1 "$SCRIPT"

  assert_contains "$output" ".github/rulesets/main.json に name がない"
}

# ---- リポジトリ設定 ---------------------------------------------------------------------------

@test "マージ方法はsquashだけを許可して送る" {
  run -0 "$SCRIPT"

  body="$(body_containing allow_squash_merge)"
  [ "$(jq -r '.allow_squash_merge' <<<"$body")" = "true" ]
  [ "$(jq -r '.allow_merge_commit' <<<"$body")" = "false" ]
  [ "$(jq -r '.allow_rebase_merge' <<<"$body")" = "false" ]
  [ "$(jq -r '.allow_auto_merge' <<<"$body")" = "true" ]
  [ "$(jq -r '.delete_branch_on_merge' <<<"$body")" = "true" ]
}

@test "GITHUB_TOKEN の既定権限は読み取りのみで、レビュー承認を許可しない" {
  run -0 "$SCRIPT"

  body="$(body_containing default_workflow_permissions)"
  [ "$(jq -r '.default_workflow_permissions' <<<"$body")" = "read" ]
  [ "$(jq -r '.can_approve_pull_request_reviews' <<<"$body")" = "false" ]
}

@test "実行できるアクションはGitHub公式と検証済みに限り、パターン追加はしない" {
  run -0 "$SCRIPT"

  body="$(body_containing github_owned_allowed)"
  [ "$(jq -r '.github_owned_allowed' <<<"$body")" = "true" ]
  [ "$(jq -r '.verified_allowed' <<<"$body")" = "true" ]
  [ "$(jq -r '.patterns_allowed | length' <<<"$body")" -eq 0 ]
}

@test "シークレットスキャンをプッシュ保護より先に送る" {
  # スクリプトがGitHubのUI手順に合わせて意図している順序
  run -0 "$SCRIPT"

  secret_line="$(grep -n '"secret_scanning":' "$GH_BODY_LOG" | head -1 | cut -d: -f1)"
  push_line="$(grep -n '"secret_scanning_push_protection":' "$GH_BODY_LOG" | head -1 | cut -d: -f1)"
  [ -n "$secret_line" ]
  [ -n "$push_line" ]
  [ "$secret_line" -lt "$push_line" ]
}

@test "Dependabotと脆弱性報告とリリース不変化を有効にする" {
  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method PUT" "repos/$REPO/vulnerability-alerts")" -eq 1 ]
  [ "$(gh_calls_matching "--method PUT" "repos/$REPO/automated-security-fixes")" -eq 1 ]
  [ "$(gh_calls_matching "--method PUT" "repos/$REPO/private-vulnerability-reporting")" -eq 1 ]
  [ "$(gh_calls_matching "--method PUT" "repos/$REPO/immutable-releases")" -eq 1 ]
}

# ---- CodeQL -----------------------------------------------------------------------------------

@test "CodeQLが未設定なら actions を対象に有効化する" {
  export GH_CODEQL_STATE="not-configured"

  run -0 "$SCRIPT"

  assert_contains "$output" "CodeQL: 有効化"
  body="$(body_containing query_suite)"
  [ "$(jq -r '.state' <<<"$body")" = "configured" ]
  [ "$(jq -r '.languages | join(",")' <<<"$body")" = "actions" ]
}

@test "CodeQLが既に有効なら変更を送らない" {
  # 解析中に PATCH すると409になりうるため、現在の状態を見てから変更する設計
  export GH_CODEQL_STATE="configured"

  run -0 "$SCRIPT"

  assert_contains "$output" "CodeQL: 既に有効"
  [ "$(gh_calls_matching "--method PATCH" "code-scanning/default-setup")" -eq 0 ]
}

# ---- ラベル -----------------------------------------------------------------------------------

@test "使わない既定ラベルは削除する" {
  export GH_LABELS=$'documentation\nquestion\nwontfix'

  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/documentation")" -eq 1 ]
  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/question")" -eq 1 ]
  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/wontfix")" -eq 1 ]
}

@test "空白を含むラベル名はURIエスケープして削除する" {
  export GH_LABELS=$'good first issue'

  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/good%20first%20issue")" -eq 1 ]
}

@test "存在しない既定ラベルは削除しようとしない" {
  export GH_LABELS=""

  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method DELETE" "labels/")" -eq 0 ]
}

@test "bug と enhancement は既定ラベルでも削除せず上書きする" {
  export GH_LABELS=$'bug\nenhancement'

  run -0 "$SCRIPT"

  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/bug")" -eq 0 ]
  [ "$(gh_calls_matching "--method DELETE" "repos/$REPO/labels/enhancement")" -eq 0 ]
  [ "$(gh_calls_matching "--method PATCH" "repos/$REPO/labels/bug")" -eq 1 ]
  [ "$(gh_calls_matching "--method PATCH" "repos/$REPO/labels/enhancement")" -eq 1 ]
}

@test "管理ラベルが無ければ作成する" {
  export GH_LABELS=""

  run -0 "$SCRIPT"

  for name in bug dependencies enhancement maintenance; do
    [ "$(gh_calls_matching "--method POST" "repos/$REPO/labels" "name=$name")" -eq 1 ]
  done
}

@test "管理ラベルの説明は空でなく100文字以内にする" {
  # GitHubのラベル説明は100文字まで
  # https://docs.github.com/en/rest/issues/labels
  run -0 "$SCRIPT"

  grep -o 'description=[^ ]*' "$GH_LOG" | sed 's/^description=//' > "$BATS_TEST_TMPDIR/descriptions"

  # 取り出せていないのに通ってしまわないよう、管理ラベル4件ぶん揃っていることを先に確かめる
  [ "$(wc -l < "$BATS_TEST_TMPDIR/descriptions" | tr -d " ")" -eq 4 ]

  while IFS= read -r description; do
    [ -n "$description" ]
    [ "${#description}" -le 100 ]
  done < "$BATS_TEST_TMPDIR/descriptions"
}

# ---- 冪等性 -----------------------------------------------------------------------------------

@test "同じ状態で2回実行しても送る内容が変わらない" {
  write_ruleset "main.json" '{"name":"main","target":"branch"}'
  export GH_RULESETS_TSV=$'42\tmain'
  export GH_CODEQL_STATE="configured"
  export GH_LABELS=$'bug\ndependencies\nenhancement\nmaintenance'

  run -0 "$SCRIPT"
  cp "$GH_LOG" "$BATS_TEST_TMPDIR/first.log"

  : > "$GH_LOG"
  run -0 "$SCRIPT"

  diff "$BATS_TEST_TMPDIR/first.log" "$GH_LOG"
}

@test "完了したことを対象リポジトリ名付きで報告する" {
  run -0 "$SCRIPT"

  assert_contains "$output" "対象: $REPO (PUBLIC / ADMIN)"
  assert_contains "$output" "完了: $REPO"
}
