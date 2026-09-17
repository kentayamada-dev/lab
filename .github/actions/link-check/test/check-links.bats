#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
#
# check-links.sh のテスト。
#
# リンク検査そのものは lychee のスタブで置き換え、
# 「lychee にどう渡し、どの終了コードのときに何を報告し、自身はどの終了コードで終わるか」を検証する。

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../check-links.sh"
  setup_stubs
  install_lychee_stub
  export STUB_LYCHEE_EXIT=0
}

# どのテストからも出発点にできる、リンク切れの無い状態を作る
default_report() {
  write_report <<'MD'
# Summary

| Status         | Count |
|----------------|-------|
| 🔍 Total       | 1     |
| 🚫 Errors      | 0     |
MD
}

# リンク切れが1件ある状態
broken_report() {
  write_report <<'MD'
# Summary

| Status         | Count |
|----------------|-------|
| 🔍 Total       | 1     |
| 🚫 Errors      | 1     |

## Errors per input

### Errors in ./README.md

* [ERROR] <https://example.test/gone> | Failed: Network error
MD
}

# ---- 正常系 ---------------------------------------------------------------------------------

@test "リンク切れが無ければ終了コード0でレポートを標準出力に出す" {
  default_report
  config="$(write_config)"

  run -0 "$SCRIPT" "$config"

  assert_contains "$output" "🚫 Errors      | 0"
}

@test "リンク切れがあれば終了コード1でレポートを標準出力に出す" {
  broken_report
  config="$(write_config)"
  export STUB_LYCHEE_EXIT=2

  run -1 "$SCRIPT" "$config"

  assert_contains "$output" "https://example.test/gone"
}

@test "設定ファイルを省略すると action 同梱の lychee.toml を使う" {
  # 実行ディレクトリに依存しないことも併せて確かめるため、無関係な場所から起動する。
  # 同梱の設定が実在しないと存在チェックで落ちるので、置き場所を変えたらこのテストが気づく
  default_report
  cd "$BATS_TEST_TMPDIR"

  run -0 "$SCRIPT"

  assert_arg "$BATS_TEST_DIRNAME/../lychee.toml"
}

@test "設定ファイルに空文字を渡しても action 同梱の lychee.toml を使う" {
  # action.yml は入力 config-file が未指定のとき空文字を渡す。
  # 空文字をそのまま設定ファイルのパスとして扱うと、存在チェックで落ちて検査ができない
  default_report
  cd "$BATS_TEST_TMPDIR"

  run -0 "$SCRIPT" ""

  assert_arg "$BATS_TEST_DIRNAME/../lychee.toml"
}

@test "引数で渡した設定ファイルを lychee に渡す" {
  default_report
  config="$(write_config "$BATS_TEST_TMPDIR/other.toml")"

  run -0 "$SCRIPT" "$config"

  assert_arg "$config"
}

@test "検査対象としてカレントディレクトリを渡す" {
  default_report
  config="$(write_config)"

  run -0 "$SCRIPT" "$config"

  assert_arg "."
}

@test "GITHUB_TOKEN はコマンドライン引数に載せない" {
  # lychee は環境変数 GITHUB_TOKEN を自動で読む。引数で渡すと ps やログに秘密が露出する
  default_report
  config="$(write_config)"
  export GITHUB_TOKEN="secret-token-value"

  run -0 "$SCRIPT" "$config"

  assert_not_contains "$(lychee_args)" "secret-token-value"
}

@test "レポートをカレントディレクトリに残さない" {
  # レポートは一時ディレクトリに書いてから標準出力へ流す。
  # 作業ディレクトリを汚すと、リポジトリ直下で実行したときに未追跡ファイルが増える
  default_report
  config="$(write_config)"
  cd "$BATS_TEST_TMPDIR"

  run -0 "$SCRIPT" "$config"

  if [ -e "$BATS_TEST_TMPDIR/report.md" ]; then
    printf 'カレントディレクトリにレポートが残っている\n' >&2
    return 1
  fi
}

# ---- 異常系 ---------------------------------------------------------------------------------

@test "設定ファイルが存在しなければ終了コード2" {
  default_report

  run -2 "$SCRIPT" "$BATS_TEST_TMPDIR/no-such.toml"

  assert_contains "$output" "が存在しない"
}

@test "lychee が見つからなければ終了コード2" {
  default_report
  config="$(write_config)"
  only_bin="$(only_commands mktemp cat rm)"

  PATH="$only_bin" run -2 "$SCRIPT" "$config"

  assert_contains "$output" "lychee が見つからない"
}

@test "lychee が入力や実行時の失敗（終了コード1）で終われば終了コード2" {
  # リンク切れ（2）以外の失敗は drift として通知せず、ジョブを落として気づけるようにする
  default_report
  config="$(write_config)"
  export STUB_LYCHEE_EXIT=1

  run -2 "$SCRIPT" "$config"

  assert_contains "$output" "終了コード 1"
}

@test "lychee が設定ファイルの誤り（終了コード3）で終われば終了コード2" {
  default_report
  config="$(write_config)"
  export STUB_LYCHEE_EXIT=3

  run -2 "$SCRIPT" "$config"

  assert_contains "$output" "終了コード 3"
}

@test "リンク切れ以外の失敗ではレポートを標準出力に流さない" {
  # 呼び出し側は標準出力を issue 本文に使う。失敗時の中身を流すと、
  # 検査できていないのにリンク切れの報告があったように見える
  broken_report
  config="$(write_config)"
  export STUB_LYCHEE_EXIT=1

  run -2 --separate-stderr "$SCRIPT" "$config"

  assert_not_contains "$output" "https://example.test/gone"
  assert_contains "$stderr" "終了コード 1"
}
