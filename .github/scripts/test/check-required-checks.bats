#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# .github/scripts/check-required-checks.sh のテスト。
#
# 外部には触れない。ルールセットの定義ファイルとワークフローを一時ディレクトリに作り、
# 「どの組み合わせを一致と見なし、どの食い違いをどちら向きの指摘として出すか」を観測する。

load ../../../scripts/lib/bats-helpers

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-required-checks.sh"
  setup_stubs
}

# 必須チェックの名前を並べたルールセットを書き、そのパスを出力する
write_ruleset() {
  local path="${BATS_TEST_TMPDIR}/ruleset.json"
  local contexts=""
  local name
  for name in "$@"; do
    contexts="${contexts}${contexts:+,}$(printf '{"context":"%s"}' "${name}")"
  done

  printf '{
    "name": "main",
    "rules": [
      { "type": "deletion" },
      {
        "type": "required_status_checks",
        "parameters": { "required_status_checks": [%s] }
      }
    ]
  }\n' "${contexts}" >"${path}"

  printf '%s' "${path}"
}

# required_status_checks ルールを持たないルールセットを書き、そのパスを出力する
write_ruleset_without_checks() {
  local path="${BATS_TEST_TMPDIR}/ruleset.json"
  printf '{ "name": "main", "rules": [ { "type": "deletion" } ] }\n' >"${path}"
  printf '%s' "${path}"
}

# name を付けたジョブだけを持つワークフローを書き、そのパスを出力する
write_workflow() {
  local path="${BATS_TEST_TMPDIR}/ci.yml"
  local i=0
  local name

  {
    printf 'name: CI\non:\n  pull_request:\njobs:\n'
    for name in "$@"; do
      i=$((i + 1))
      printf '  job%s:\n    name: %s\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' "${i}" "${name}"
    done
  } >"${path}"

  printf '%s' "${path}"
}

# ---- 一致 -----------------------------------------------------------------------------------

@test "必須チェックとジョブ名が揃っていれば終了コード0" {
  ruleset="$(write_ruleset "Lint" "Scripts test")"
  workflow="$(write_workflow "Lint" "Scripts test")"

  run -0 "${SCRIPT}" "${ruleset}" "${workflow}"

  assert_contains "${output}" "一致しています"
}

@test "定義ファイルの並び順に依存せず一致と見なす" {
  # comm は整列済みの入力を前提にするため、比較の前に両方をソートしている。
  # どちらか一方でもソートを外すと、名前が揃っているのに不一致として報告される
  ruleset="$(write_ruleset "Scripts test" "Lint")"
  workflow="$(write_workflow "Scripts test" "Lint")"

  run -0 "${SCRIPT}" "${ruleset}" "${workflow}"
}

@test "引数を省略するとこのリポジトリの定義ファイルとCIを比較して一致する" {
  # 既定の対象が実在のファイルを指していることと、現状が一致していることの両方を見る。
  # ci.yml のジョブ名を変えてルールセットを直し忘れると、この検査が落ちる
  cd "${BATS_TEST_DIRNAME}/../../.." || exit

  run -0 "${SCRIPT}"
}

# ---- 不一致 ---------------------------------------------------------------------------------

@test "必須にした名前のジョブが無ければ落とし、マージできなくなることを伝える" {
  ruleset="$(write_ruleset "Lint")"
  workflow="$(write_workflow "Lint renamed")"

  run -1 "${SCRIPT}" "${ruleset}" "${workflow}"

  assert_contains "${output}" "- Lint"
  assert_contains "${output}" "マージできなくなる"
}

@test "必須になっていないジョブがあれば落とし、マージを止めないことを伝える" {
  ruleset="$(write_ruleset "Lint")"
  workflow="$(write_workflow "Lint" "Extra")"

  run -1 "${SCRIPT}" "${ruleset}" "${workflow}"

  assert_contains "${output}" "- Extra"
  assert_contains "${output}" "マージを止めない"
}

@test "required_status_checks ルールが無ければ全ジョブを余分として落とす" {
  ruleset="$(write_ruleset_without_checks)"
  workflow="$(write_workflow "Lint")"

  run -1 "${SCRIPT}" "${ruleset}" "${workflow}"

  assert_contains "${output}" "- Lint"
}

@test "name の無いジョブはジョブIDが名前として扱われる" {
  # ステータスチェックの名前は name があればそれ、無ければジョブID になる。
  # ジョブIDを見ない実装だと、name の無いジョブが常に「必須に無い」と誤検出される
  ruleset="$(write_ruleset "build")"
  path="${BATS_TEST_TMPDIR}/ci.yml"
  {
    printf 'name: CI\non:\n  pull_request:\njobs:\n'
    printf '  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n'
  } >"${path}"

  run -0 "${SCRIPT}" "${ruleset}" "${path}"
}

# ---- 検査自体が実行できない場合 ---------------------------------------------------------------

@test "ルールセットのファイルが無ければ終了コード2" {
  workflow="$(write_workflow "Lint")"

  run -2 "${SCRIPT}" "${BATS_TEST_TMPDIR}/missing.json" "${workflow}"

  assert_contains "${output}" "が存在しない"
}

@test "ワークフローのファイルが無ければ終了コード2" {
  ruleset="$(write_ruleset "Lint")"

  run -2 "${SCRIPT}" "${ruleset}" "${BATS_TEST_TMPDIR}/missing.yml"

  assert_contains "${output}" "が存在しない"
}

@test "ルールセットがJSONとして不正なら終了コード2" {
  path="${BATS_TEST_TMPDIR}/broken.json"
  printf '{ "rules": }' >"${path}"
  workflow="$(write_workflow "Lint")"

  run -2 "${SCRIPT}" "${path}" "${workflow}"

  assert_contains "${output}" "JSON として不正"
}

@test "ジョブが1つも読み取れなければ drift ではなく検査失敗にする" {
  # 検査対象が黙って0件になるより落ちるほうを選んでいる。
  # ここを 0 件のまま比較すると「必須の名前が全て見つからない」という誤った指摘になる
  ruleset="$(write_ruleset "Lint")"
  path="${BATS_TEST_TMPDIR}/empty.yml"
  printf 'name: CI\non:\n  pull_request:\njobs: {}\n' >"${path}"

  run -2 "${SCRIPT}" "${ruleset}" "${path}"

  assert_contains "${output}" "ジョブを読み取れない"
}

@test "jq が無ければ検査せず終了コード2" {
  PATH="$(only_commands)" run -2 "${SCRIPT}"

  assert_contains "${output}" "jq が見つからない"
}

@test "yq が無ければ検査せず終了コード2" {
  PATH="$(only_commands jq)" run -2 "${SCRIPT}"

  assert_contains "${output}" "yq が見つからない"
}
