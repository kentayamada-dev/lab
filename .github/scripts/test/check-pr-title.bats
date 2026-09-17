#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# .github/scripts/check-pr-title.sh のテスト。
#
# 外部には触れず、引数として渡したタイトルに対する判定だけを観測する。
# 見ているのは「どのタイトルを通し、どのタイトルをどんな理由で落とすか」。

load ../../../scripts/lib/bats-helpers

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-pr-title.sh"
  setup_stubs
}

# ---- 通すもの -------------------------------------------------------------------------------

@test "型と日本語の説明だけのタイトルを通す" {
  run -0 "${SCRIPT}" "ci: 各lintを最も厳しい設定に揃える"

  assert_contains "${output}" "規約に沿っています"
}

@test "スコープ付きのタイトルを通す" {
  run -0 "${SCRIPT}" "fix(link-check): リンク切れを直す"
}

@test "破壊的変更の ! が付いたタイトルを通す" {
  run -0 "${SCRIPT}" "feat!: 設定ファイルの場所を変える"
}

@test "スコープと ! の両方が付いたタイトルを通す" {
  run -0 "${SCRIPT}" "feat(ci)!: 必須チェックを入れ替える"
}

@test "説明に英数字が混ざっていても日本語があれば通す" {
  # Renovate が作るタイトル（.github/renovate.json5 の commitMessage* 参照）がこの形
  run -0 "${SCRIPT}" "chore(deps): koalaman/shellcheck を v0.12.0 に更新"
}

@test "長いタイトルでも通す（長さの上限は設けていない）" {
  run -0 "${SCRIPT}" "refactor(link-check): 検査対象の集め方をgit管理下のファイルに寄せて設定ファイルの重複を無くす"
}

# ---- 落とすもの -----------------------------------------------------------------------------

@test "Conventional Commits 形式でなければ落とす" {
  run -1 "${SCRIPT}" "リンク切れを直す"

  assert_contains "${output}" "Conventional Commits 形式ではない"
}

@test "コロンの後に空白が無ければ落とす" {
  run -1 "${SCRIPT}" "fix:リンク切れを直す"

  assert_contains "${output}" "Conventional Commits 形式ではない"
}

@test "コロンの後の空白が2つ以上なら落とす" {
  run -1 "${SCRIPT}" "fix:  リンク切れを直す"

  assert_contains "${output}" "コロンの後の空白が2つ以上ある"
}

@test "一覧に無い型は落とす" {
  run -1 "${SCRIPT}" "wip: 作業中"

  assert_contains "${output}" "型 'wip' は使えない"
}

@test "スコープの括弧が空なら落とす" {
  run -1 "${SCRIPT}" "feat(): 機能を足す"

  assert_contains "${output}" "スコープの括弧が空"
}

@test "説明が空なら落とす" {
  run -1 "${SCRIPT}" "fix: "

  assert_contains "${output}" "説明が空"
}

@test "説明がASCII文字だけなら落とす" {
  # CLAUDE.md の「内容は日本語で書く」に対応する。これが落ちないと英語のタイトルが素通りする
  run -1 "${SCRIPT}" "fix: fix the broken link"

  assert_contains "${output}" "説明に日本語が含まれていない"
}

@test "説明が句点で終わっていれば落とす" {
  run -1 "${SCRIPT}" "docs: 手順を書き足す。"

  assert_contains "${output}" "句点・ピリオドで終わっている"
}

@test "説明がピリオドで終わっていれば落とす" {
  run -1 "${SCRIPT}" "docs: 手順を書き足す."

  assert_contains "${output}" "句点・ピリオドで終わっている"
}

@test "先頭に空白があれば落とす" {
  run -1 "${SCRIPT}" " ci: 検査を足す"

  assert_contains "${output}" "先頭に空白がある"
}

@test "末尾に空白があれば落とす" {
  # squash 後のコミット件名に残るため。形式としては通ってしまうので個別に見ている
  run -1 "${SCRIPT}" "ci: 検査を足す "

  assert_contains "${output}" "末尾に空白がある"
}

@test "タイトルが空なら落とす" {
  run -1 "${SCRIPT}" ""

  assert_contains "${output}" "タイトルが空"
}

@test "問題が複数あればまとめて出す" {
  # 1件直すたびにCIを回し直さずに済むようにしている。1件しか出さない実装だとここが落ちる
  run -1 "${SCRIPT}" "wip: work in progress."

  assert_contains "${output}" "型 'wip' は使えない"
  assert_contains "${output}" "説明に日本語が含まれていない"
  assert_contains "${output}" "句点・ピリオドで終わっている"
}

# ---- 検査自体が実行できない場合 ---------------------------------------------------------------

@test "引数が無ければ終了コード2" {
  run -2 "${SCRIPT}"

  assert_contains "${output}" "引数はPRのタイトル1つ"
}

@test "引数が2つ以上あれば終了コード2" {
  # タイトルを引用符で囲み忘れて単語ごとに分かれた状態。先頭の単語だけを検査して通さない
  run -2 "${SCRIPT}" "ci:" "検査を足す"

  assert_contains "${output}" "引数はPRのタイトル1つ"
}

@test "grep が無ければ検査せず終了コード2" {
  PATH="$(only_commands)" run -2 "${SCRIPT}" "ci: 検査を足す"

  assert_contains "${output}" "grep が見つからない"
}
