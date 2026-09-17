#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# notify-drift-issue.sh のテスト。
#
# このスクリプトの振る舞いは、ほぼすべてが gh への呼び出しそのもの。
# gh をスタブに差し替え、「どの issue 操作を、どんな本文で行うか（行わないか）」を観測する。

load helper

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../notify-drift-issue.sh"
  setup_stubs
  install_gh_stub

  export REPORT_FILE="${BATS_TEST_TMPDIR}/report.md"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary.md"
  : > "${GITHUB_STEP_SUMMARY}"

  export DRIFT=true
  export ISSUE_TITLE="chore: 設定が一致していない"
  export ISSUE_LABEL=maintenance
  export RUN_URL="https://example.test/actions/runs/1"
  export SUMMARY_DRIFT="設定に drift があります"
  export SUMMARY_OK="設定は一致しています"
  export CLOSE_COMMENT="定期チェックで一致を確認したため、自動でcloseしました。"
  export COMMENT_INTRO="検査結果が前回の通知から変わりました。"
  export REPORT_HEADING="検査結果"
  export REPORT_NOTE="検査結果が変わった場合はコメントで追記されます。"
  export ISSUE_DESCRIPTION="定期チェックで一致しない箇所が見つかりました。"
  export ISSUE_EXTRA_SECTIONS=$'## 参照\n\n- https://example.test/docs'
  export COMPLETION_CRITERIA=$'- [ ] 原因を特定した\n- [ ] 修正した'
  unset REPORT_FORMAT DIGEST_SKIP_LINES GH_ISSUE_LIST_JSON GH_ISSUE_VIEW_JSON GH_FAIL_SUBCOMMAND

  # 実行日時が入る1行目と、指摘内容の2行。時刻は固定値
  write_report "確認したキー: 3 件（2026-01-01T00:00:00Z）" "### 問題" '- `goneKey`: 設定索引に載っていない'
}

# 作成された issue 本文からハッシュを取り出す
created_hash() { grep -oE '[0-9a-f]{64}' "${GH_BODY_DIR}/create.md"; }

# ---- drift なし -----------------------------------------------------------------------------

@test "drift がなく open issue も無ければ、何も操作せず正常終了する" {
  export DRIFT=false

  run -0 "${SCRIPT}"

  assert_contains "${output}" "closeすべき通知issueはありません"
  assert_equal "$(gh_calls_matching "issue close")" 0
  assert_equal "$(gh_calls_matching "issue create")" 0
  assert_equal "$(gh_calls_matching "issue comment")" 0
}

@test "drift がなければジョブサマリーに一致の見出しを書き、レポートがあれば添える" {
  export DRIFT=false
  write_report "確認したキー: 3 件" "### 情報（対応不要）" '- `newKey`: スキーマ側の遅れ'

  run -0 "${SCRIPT}"

  summary="$(cat "${GITHUB_STEP_SUMMARY}")"
  assert_contains "${summary}" "## :white_check_mark: 設定は一致しています"
  assert_contains "${summary}" '`newKey`: スキーマ側の遅れ'
  assert_not_contains "${summary}" ":warning:"
}

@test "drift がなくレポートが空なら、サマリーは見出しだけで空のコードフェンスを載せない" {
  export DRIFT=false
  export REPORT_FORMAT=diff
  : > "${REPORT_FILE}"

  run -0 "${SCRIPT}"

  summary="$(cat "${GITHUB_STEP_SUMMARY}")"
  assert_contains "${summary}" "## :white_check_mark: 設定は一致しています"
  assert_not_contains "${summary}" '```'
}

@test "drift がなく同じタイトルの open issue があれば、経緯コメントを付けて close する" {
  export DRIFT=false
  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON

  run -0 "${SCRIPT}"

  assert_contains "${output}" "issue #42 をcloseしました"
  assert_equal "$(gh_calls_matching "issue close 42" "--reason completed" "${CLOSE_COMMENT}" "${RUN_URL}")" 1
  assert_equal "$(gh_calls_matching "issue create")" 0
}

@test "同じラベルでもタイトルが完全一致しない issue は close しない" {
  export DRIFT=false
  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない (2)' $'43\tchore: 別の課題')"
  export GH_ISSUE_LIST_JSON

  run -0 "${SCRIPT}"

  assert_contains "${output}" "closeすべき通知issueはありません"
  assert_equal "$(gh_calls_matching "issue close")" 0
}

@test "同じタイトルの open issue が複数あっても、最初の1件だけ close する" {
  export DRIFT=false
  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない' $'57\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON

  run -0 "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue close 42")" 1
  assert_equal "$(gh_calls_matching "issue close")" 1
}

# ---- drift あり: issue の作成 ---------------------------------------------------------------

@test "drift があり open issue が無ければ、タイトルとラベルを付けて issue を作成する" {
  run -0 "${SCRIPT}"

  assert_contains "${output}" "issueを作成しました"
  assert_equal "$(gh_calls_matching "issue create" "--title ${ISSUE_TITLE}" "--label ${ISSUE_LABEL}")" 1
  assert_equal "$(gh_calls_matching "issue comment")" 0
  assert_equal "$(gh_calls_matching "issue close")" 0
}

@test "issue 本文には課題・実行ログ・検査結果・追加の節・完了条件・ハッシュが順に入る" {
  run -0 "${SCRIPT}"

  body="$(gh_body create)"
  assert_contains "${body}" $'## 課題\n\n定期チェックで一致しない箇所が見つかりました。'
  assert_contains "${body}" "実行ログ: ${RUN_URL}"
  assert_contains "${body}" $'## 検査結果\n\n検査結果が変わった場合はコメントで追記されます。\n\n確認したキー: 3 件'
  assert_contains "${body}" '- `goneKey`: 設定索引に載っていない'
  assert_contains "${body}" $'## 参照\n\n- https://example.test/docs'
  assert_contains "${body}" $'## 完了条件\n\n- [ ] 原因を特定した\n- [ ] 修正した'
  # ハッシュは本文の最後に置く（GitHub 上では表示されない HTML コメント）
  last_line="$(tail -n 1 "${GH_BODY_DIR}/create.md")"
  case "${last_line}" in
    "<!-- drift-hash: "[0-9a-f]*" -->") ;;
    *) printf 'ハッシュ行が末尾に無い: %s\n' "${last_line}" >&2; return 1 ;;
  esac
  assert_equal "$(created_hash | wc -c | tr -d ' ')" 65
}

@test "drift があればジョブサマリーに警告の見出しとレポートを書く" {
  run -0 "${SCRIPT}"

  summary="$(cat "${GITHUB_STEP_SUMMARY}")"
  assert_contains "${summary}" "## :warning: 設定に drift があります"
  assert_contains "${summary}" '- `goneKey`: 設定索引に載っていない'
}

@test "report-format が diff なら、レポートをコードフェンスで囲む" {
  export REPORT_FORMAT=diff
  write_report "--- local" "+++ remote" "-  \"a\": 1" "+  \"a\": 2"

  run -0 "${SCRIPT}"

  body="$(gh_body create)"
  assert_contains "${body}" $'```diff\n--- local\n+++ remote\n-  "a": 1\n+  "a": 2\n```'
  assert_contains "$(cat "${GITHUB_STEP_SUMMARY}")" $'```diff\n--- local'
}

@test "report-format が markdown なら、レポートをコードフェンスで囲まない" {
  run -0 "${SCRIPT}"

  assert_not_contains "$(gh_body create)" '```'
}

@test "digest-skip-lines で除いた先頭行が変わっても、ハッシュは変わらない" {
  export DIGEST_SKIP_LINES=1

  write_report "確認したキー: 3 件（2026-01-01T00:00:00Z）" "### 問題" '- `goneKey`: 設定索引に載っていない'
  run -0 "${SCRIPT}"
  first="$(created_hash)"

  write_report "確認したキー: 3 件（2026-01-02T00:00:00Z）" "### 問題" '- `goneKey`: 設定索引に載っていない'
  run -0 "${SCRIPT}"
  second="$(created_hash)"

  assert_equal "${second}" "${first}"
}

@test "digest-skip-lines が 0 なら、先頭行の違いもハッシュに反映される" {
  export DIGEST_SKIP_LINES=0

  write_report "確認したキー: 3 件（2026-01-01T00:00:00Z）" "### 問題"
  run -0 "${SCRIPT}"
  first="$(created_hash)"

  write_report "確認したキー: 3 件（2026-01-02T00:00:00Z）" "### 問題"
  run -0 "${SCRIPT}"
  second="$(created_hash)"

  [[ "${second}" != "${first}" ]] || { echo "先頭行が違うのにハッシュが同じ: ${first}" >&2; return 1; }
}

@test "指摘内容が変われば、digest-skip-lines を指定していてもハッシュは変わる" {
  export DIGEST_SKIP_LINES=1

  write_report "確認したキー: 3 件" "### 問題" '- `goneKey`: 設定索引に載っていない'
  run -0 "${SCRIPT}"
  first="$(created_hash)"

  write_report "確認したキー: 3 件" "### 問題" '- `otherKey`: 設定索引に載っていない'
  run -0 "${SCRIPT}"
  second="$(created_hash)"

  [[ "${second}" != "${first}" ]] || { echo "指摘内容が違うのにハッシュが同じ: ${first}" >&2; return 1; }
}

@test "任意の文言を渡さなくても、既定の文言で issue 本文を組める" {
  unset SUMMARY_DRIFT SUMMARY_OK CLOSE_COMMENT COMMENT_INTRO REPORT_HEADING REPORT_NOTE
  unset ISSUE_DESCRIPTION ISSUE_EXTRA_SECTIONS COMPLETION_CRITERIA

  run -0 "${SCRIPT}"

  body="$(gh_body create)"
  assert_contains "${body}" "## 課題"
  assert_contains "${body}" "## 検査結果"
  assert_contains "${body}" "## 完了条件"
  assert_contains "${body}" "<!-- drift-hash: "
  assert_contains "$(cat "${GITHUB_STEP_SUMMARY}")" "## :warning: "
}

@test "レポートが空でも drift があれば issue を作成する" {
  : > "${REPORT_FILE}"

  run -0 "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue create")" 1
  assert_contains "$(gh_body create)" "<!-- drift-hash: "
}

@test "GITHUB_STEP_SUMMARY が無い環境でも通知は行う" {
  unset GITHUB_STEP_SUMMARY

  run -0 "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue create")" 1
}

# ---- drift あり: 既存 issue への追記 --------------------------------------------------------

@test "既存 issue の本文に同じハッシュがあれば、追記も作成もしない" {
  run -0 "${SCRIPT}"
  hash="$(created_hash)"
  : > "${GH_LOG}"

  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON
  GH_ISSUE_VIEW_JSON="$(issue_view_json "本文 <!-- drift-hash: ${hash} -->")"
  export GH_ISSUE_VIEW_JSON

  run -0 "${SCRIPT}"

  assert_contains "${output}" "既存のissue #42 に同じ検査結果が記録済みのため追記をスキップ"
  assert_equal "$(gh_calls_matching "issue comment")" 0
  assert_equal "$(gh_calls_matching "issue create")" 0
}

@test "既存 issue にハッシュが無ければ、コメントで追記する（作成はしない）" {
  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON
  GH_ISSUE_VIEW_JSON="$(issue_view_json "ハッシュの無い本文" "ハッシュの無いコメント")"
  export GH_ISSUE_VIEW_JSON

  run -0 "${SCRIPT}"

  assert_contains "${output}" "issue #42 に追記しました"
  assert_equal "$(gh_calls_matching "issue comment 42" "--body-file")" 1
  assert_equal "$(gh_calls_matching "issue create")" 0

  body="$(gh_body comment)"
  assert_contains "${body}" "検査結果が前回の通知から変わりました。"
  assert_contains "${body}" "実行ログ: ${RUN_URL}"
  assert_contains "${body}" '- `goneKey`: 設定索引に載っていない'
  assert_contains "${body}" "<!-- drift-hash: "
}

@test "本文のハッシュが一致しても、より後のコメントに別のハッシュがあれば追記する" {
  run -0 "${SCRIPT}"
  hash="$(created_hash)"
  : > "${GH_LOG}"

  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON
  other="$(printf '%064d' 0)"
  GH_ISSUE_VIEW_JSON="$(issue_view_json "<!-- drift-hash: ${hash} -->" "<!-- drift-hash: ${other} -->")"
  export GH_ISSUE_VIEW_JSON

  run -0 "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue comment 42")" 1
}

@test "本文のハッシュが違っても、最後のコメントのハッシュが一致すればスキップする" {
  run -0 "${SCRIPT}"
  hash="$(created_hash)"
  : > "${GH_LOG}"

  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON
  other="$(printf '%064d' 0)"
  GH_ISSUE_VIEW_JSON="$(issue_view_json "<!-- drift-hash: ${other} -->" "ハッシュ無し" "<!-- drift-hash: ${hash} -->")"
  export GH_ISSUE_VIEW_JSON

  run -0 "${SCRIPT}"

  assert_contains "${output}" "追記をスキップ"
  assert_equal "$(gh_calls_matching "issue comment")" 0
}

@test "既存 issue の本文が null でもエラーにせず追記する" {
  GH_ISSUE_LIST_JSON="$(issue_list_json $'42\tchore: 設定が一致していない')"
  export GH_ISSUE_LIST_JSON
  GH_ISSUE_VIEW_JSON="$(issue_view_json "<null>")"
  export GH_ISSUE_VIEW_JSON

  run -0 "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue comment 42")" 1
}

# ---- 入力や前提の不備（終了コード2） --------------------------------------------------------

@test "DRIFT が true / false 以外なら、gh を呼ばずに終了コード2" {
  export DRIFT=yes

  run -2 "${SCRIPT}"

  assert_contains "${output}" "DRIFT は true か false"
  [[ ! -s "${GH_LOG}" ]]
}

@test "DRIFT が空なら終了コード2" {
  export DRIFT=""

  run -2 "${SCRIPT}"

  assert_contains "${output}" "DRIFT が空"
}

@test "ISSUE_TITLE が空なら終了コード2" {
  export ISSUE_TITLE=""

  run -2 "${SCRIPT}"

  assert_contains "${output}" "ISSUE_TITLE が空"
  [[ ! -s "${GH_LOG}" ]]
}

@test "レポートファイルが無ければ終了コード2" {
  rm "${REPORT_FILE}"

  run -2 "${SCRIPT}"

  assert_contains "${output}" "が存在しない"
}

@test "REPORT_FORMAT が markdown / diff 以外なら終了コード2" {
  export REPORT_FORMAT=html

  run -2 "${SCRIPT}"

  assert_contains "${output}" "REPORT_FORMAT は markdown か diff"
}

@test "DIGEST_SKIP_LINES が整数でなければ終了コード2" {
  export DIGEST_SKIP_LINES=one

  run -2 "${SCRIPT}"

  assert_contains "${output}" "DIGEST_SKIP_LINES は 0 以上の整数"
}

@test "gh が無ければ終了コード2" {
  run -2 env PATH="$(only_commands jq)" "${SCRIPT}"

  assert_contains "${output}" "gh が見つからない"
}

@test "jq が無ければ終了コード2" {
  run -2 env PATH="$(only_commands gh)" "${SCRIPT}"

  assert_contains "${output}" "jq が見つからない"
}

@test "sha256sum も shasum も無ければ終了コード2" {
  run -2 env PATH="$(only_commands gh jq)" "${SCRIPT}"

  assert_contains "${output}" "sha256sum も shasum も見つからない"
}

# ---- gh の失敗を握りつぶさない --------------------------------------------------------------

@test "issue の作成に失敗したら、成功として終わらない" {
  export GH_FAIL_SUBCOMMAND=create

  run ! "${SCRIPT}"

  assert_not_contains "${output}" "issueを作成しました"
}

@test "issue の一覧取得に失敗したら、成功として終わらない" {
  export GH_FAIL_SUBCOMMAND=list

  run ! "${SCRIPT}"

  assert_equal "$(gh_calls_matching "issue create")" 0
}
