#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# check-ruleset-drift.sh のテスト。
#
# GitHub API の取得は gh のスタブで置き換え、
# 「どんな応答のときに何を報告し、どの終了コードで終わるか」を検証する。

load helper

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-ruleset-drift.sh"
  setup_stubs
  install_gh_stub
  export GITHUB_REPOSITORY="kentayamada-dev/lab"
  export GH_TOKEN="dummy-token"
}

# どのテストからも出発点にできる、差分のない状態を作る
default_file() {
  write_ruleset_file <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
}

default_remote() {
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
}

# ---- 正常系 ---------------------------------------------------------------------------------

@test "定義ファイルとGitHub上の設定が一致していれば終了コード0" {
  default_remote
  file="$(default_file)"

  run -0 "${SCRIPT}" "${file}"

  assert_contains "${output}" "一致しています"
}

@test "APIが付ける読み取り専用フィールドは差分にしない" {
  # write_ruleset_detail は id / source / _links などを必ず足す。
  # 比較対象のキーを絞れていなければ、ここで差分として報告されてしまう
  default_remote
  file="$(default_file)"

  run -0 "${SCRIPT}" "${file}"

  assert_not_contains "${output}" "_links"
  assert_not_contains "${output}" "source"
}

@test "キーの並び順が違うだけなら差分にしない" {
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "rules": [{ "type": "deletion" }],
  "conditions": { "ref_name": { "exclude": [], "include": ["refs/heads/main"] } },
  "bypass_actors": [],
  "enforcement": "active",
  "target": "branch",
  "name": "main"
}
JSON
  file="$(default_file)"

  run -0 "${SCRIPT}" "${file}"
}

# ---- 差分の検知 -----------------------------------------------------------------------------

@test "設定値が違えば終了コード1でunified diffを出す" {
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "disabled",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
  file="$(default_file)"

  run -1 "${SCRIPT}" "${file}"

  assert_contains "${output}" '-  "enforcement": "active"'
  assert_contains "${output}" '+  "enforcement": "disabled"'
}

@test "bypass_actors に要素が増えていれば差分として検知する" {
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
  file="$(default_file)"

  run -1 "${SCRIPT}" "${file}"

  assert_contains "${output}" "bypass_mode"
}

@test "GitHub上に同名のルールセットが無ければ終了コード1でその旨を出す" {
  write_ruleset_list $'1\tother'
  write_ruleset_detail <<<'{}'
  file="$(default_file)"

  run -1 "${SCRIPT}" "${file}"

  assert_contains "${output}" "GitHub上に name=main のルールセットが存在しません"
}

@test "差分の出力は実行ごとに変わらない" {
  # 呼び出し側（notify-drift-issue）は本文のハッシュで「前回と同じ差分か」を判定するため、
  # 同じ入力から毎回同じ出力が出ないと、差分が変わっていなくてもコメントが追記され続ける
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "disabled",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
  file="$(default_file)"

  run -1 "${SCRIPT}" "${file}"
  first="${output}"
  run -1 "${SCRIPT}" "${file}"

  [[ "${first}" = "${output}" ]]
}

# ---- 権限不足の切り分け（#11 の回帰テスト）--------------------------------------------------

@test "応答に bypass_actors が無ければ差分ではなく検査失敗として終了コード2" {
  # bypass_actors はルールセットへの write 権限が無い要求元には返らない。
  # これを差分として扱うと、実際は一致していても通知され続ける（#11）
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
  file="$(default_file)"

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "bypass_actors がない"
  assert_not_contains "${output}" "null"
}

@test "応答の bypass_actors が null なら差分として検知する" {
  # キーが無い（権限不足）場合と違い、値として null が入っているのは実際の設定の差なので
  # 検査失敗ではなく差分として扱う
  write_ruleset_list $'1\tmain'
  write_ruleset_detail <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": null,
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [{ "type": "deletion" }]
}
JSON
  file="$(default_file)"

  run -1 "${SCRIPT}" "${file}"

  assert_contains "${output}" "bypass_actors"
}

# ---- 前提チェック ---------------------------------------------------------------------------

@test "GH_TOKEN が未設定なら終了コード2で止まり、APIを呼ばない" {
  default_remote
  file="$(default_file)"
  unset GH_TOKEN

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "GH_TOKEN が未設定"
  assert_contains "${output}" "RULESET_READ_TOKEN"
}

@test "GH_TOKEN が空文字でも終了コード2で止まる" {
  default_remote
  file="$(default_file)"
  export GH_TOKEN=""

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "GH_TOKEN が未設定"
}

@test "GITHUB_REPOSITORY が未設定なら終了コード2" {
  default_remote
  file="$(default_file)"
  unset GITHUB_REPOSITORY

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "GITHUB_REPOSITORY が未設定"
}

@test "定義ファイルが存在しなければ終了コード2" {
  default_remote

  run -2 "${SCRIPT}" "${BATS_TEST_TMPDIR}/missing.json"

  assert_contains "${output}" "が存在しない"
}

@test "定義ファイルがJSONとして不正なら終了コード2" {
  default_remote
  file="$(write_ruleset_file <<<'{ "name": ')"

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "JSON として不正"
}

@test "定義ファイルに name が無ければ終了コード2" {
  default_remote
  file="$(write_ruleset_file <<<'{ "target": "branch" }')"

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "name がない"
}

@test "jq が無ければ終了コード2" {
  default_remote
  file="$(default_file)"
  only_bin="$(only_commands gh diff)"

  PATH="${only_bin}" run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "jq が見つからない"
}

@test "ルールセット一覧の取得に失敗したら終了コード2" {
  default_remote
  file="$(default_file)"
  export STUB_GH_FAIL_LIST=1

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "ルールセット一覧を取得できない"
}

@test "ルールセット詳細の取得に失敗したら終了コード2" {
  default_remote
  file="$(default_file)"
  export STUB_GH_FAIL_GET=1

  run -2 "${SCRIPT}" "${file}"

  assert_contains "${output}" "を取得できない"
}
