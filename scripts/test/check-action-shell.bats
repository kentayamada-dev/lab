#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# scripts/check-action-shell.sh のテスト。
#
# 外部には触れない。action.yml を一時ディレクトリに作り、
# 「run: の中身を shellcheck に届けているか」「届けられないときに黙って成功しないか」を観測する。
# 検査そのものには実物の shellcheck を使う
# （何を指摘するかはツールの仕事で、ここで固定したいのは渡し方のほう）。

load ../lib/bats-helpers

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-action-shell.sh"
  setup_stubs
}

# 標準入力の内容を action.yml として書き、そのパスを出力する
write_action() {
  local path="${BATS_TEST_TMPDIR}/${1:-sample}/action.yml"
  mkdir -p "$(dirname "${path}")"
  cat >"${path}"
  printf '%s' "${path}"
}

# ---- 検査が届いている ------------------------------------------------------------------------

@test "指摘の無い run: なら終了コード0" {
  action="$(
    write_action ok <<'YAML'
name: ok
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        set -euo pipefail
        echo "ok"
YAML
  )"

  run -0 "${SCRIPT}" "${action}"

  assert_contains "${output}" "指摘はありません"
}

@test "run: の中身に問題があれば shellcheck の指摘とともに落とす" {
  # このテストが無いと、抽出に失敗して1件も検査していない状態でも成功してしまう
  action="$(
    write_action ng <<'YAML'
name: ng
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        name="世界"
        echo "こんにちは $name"
YAML
  )"

  run -1 "${SCRIPT}" "${action}"

  # 波括弧を勧める SC2250。ci.yml の shellcheck と同じく -o all で optional チェックまで有効にしている
  assert_contains "${output}" "SC2250"
}

@test "指摘の行番号が run: の中身の行番号と一致する" {
  # 抽出時に shebang を足すと1行ずれる。ずれると action.yml のどこが問題か追えなくなる
  action="$(
    write_action lineno <<'YAML'
name: lineno
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        set -euo pipefail
        name="世界"
        echo "こんにちは $name"
YAML
  )"

  run -1 "${SCRIPT}" "${action}"

  # 波括弧を勧める SC2250 が出るのは3行目だけ
  assert_contains "${output}" "line 3"
}

@test "env で渡す前提の変数は未代入として指摘しない" {
  # run: が読む変数はステップの env: とランナーが与える環境変数で、切り出したシェルからは見えない。
  # SC2154 を外していないと、正しく書かれた run: が軒並み落ちる
  action="$(
    write_action env <<'YAML'
name: env
runs:
  using: composite
  steps:
    - shell: bash
      env:
        REPORT_FILE: from-input
      run: |
        set -euo pipefail
        cat "${REPORT_FILE}" >> "${GITHUB_OUTPUT}"
YAML
  )"

  run -0 "${SCRIPT}" "${action}"
}

@test "shell: sh のステップも検査する" {
  action="$(
    write_action posix <<'YAML'
name: posix
runs:
  using: composite
  steps:
    - shell: sh
      run: |
        echo "ok"
YAML
  )"

  run -0 "${SCRIPT}" "${action}"
}

@test "複数のステップと複数のファイルをまとめて検査する" {
  first="$(
    write_action multi-a <<'YAML'
name: multi-a
runs:
  using: composite
  steps:
    - shell: bash
      run: echo "1つめ"
    - shell: bash
      run: echo "2つめ"
YAML
  )"
  second="$(
    write_action multi-b <<'YAML'
name: multi-b
runs:
  using: composite
  steps:
    - shell: bash
      run: echo "3つめ"
YAML
  )"

  run -0 "${SCRIPT}" "${first}" "${second}"

  assert_contains "${output}" "3件を検査"
}

@test "引数を省略するとこのリポジトリの composite action を検査して通る" {
  cd "${BATS_TEST_DIRNAME}/../.." || exit

  run -0 "${SCRIPT}"
}

# ---- 検査自体が実行できない場合 ---------------------------------------------------------------

@test "shell の指定が無いステップは終了コード2" {
  # 既定のシェルを勝手に決めて検査すると、実際とは違う方言で見ることになる
  action="$(
    write_action noshell <<'YAML'
name: noshell
runs:
  using: composite
  steps:
    - run: echo "ok"
YAML
  )"

  run -2 "${SCRIPT}" "${action}"

  assert_contains "${output}" "shell が無い"
}

@test "未対応の shell なら黙って飛ばさず終了コード2" {
  action="$(
    write_action python <<'YAML'
name: python
runs:
  using: composite
  steps:
    - shell: python
      run: print("ok")
YAML
  )"

  run -2 "${SCRIPT}" "${action}"

  assert_contains "${output}" "未対応"
}

@test "composite でない action は対象外と表示する" {
  action="$(
    write_action node <<'YAML'
name: node
runs:
  using: node20
  main: index.js
YAML
  )"

  run -2 "${SCRIPT}" "${action}"

  assert_contains "${output}" "composite ではないため対象外"
}

@test "run: を持つステップが1つも無ければ終了コード2" {
  # 検査対象が黙って0件になるより落ちるほうを選んでいる
  action="$(
    write_action uses-only <<'YAML'
name: uses-only
runs:
  using: composite
  steps:
    - uses: actions/checkout@v5
YAML
  )"

  run -2 "${SCRIPT}" "${action}"

  assert_contains "${output}" "run: を持つステップが1つも見つからない"
}

@test "存在しないファイルを渡せば終了コード2" {
  run -2 "${SCRIPT}" "${BATS_TEST_TMPDIR}/missing/action.yml"

  assert_contains "${output}" "が存在しない"
}

@test "yq が無ければ検査せず終了コード2" {
  PATH="$(only_commands)" run -2 "${SCRIPT}"

  assert_contains "${output}" "yq が見つからない"
}

@test "shellcheck が無ければ検査せず終了コード2" {
  PATH="$(only_commands yq)" run -2 "${SCRIPT}"

  assert_contains "${output}" "shellcheck が見つからない"
}
