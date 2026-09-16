#!/usr/bin/env bash
#
# drift 検査の結果をジョブサマリーに書き、GitHub issue で通知する。
#
#   usage: .github/actions/notify-drift-issue/notify-drift-issue.sh
#
# 入力はすべて環境変数で受け取る（action.yml が inputs を写す）。
#   必須: DRIFT（true / false）/ REPORT_FILE / ISSUE_TITLE / ISSUE_LABEL / RUN_URL
#   任意: REPORT_FORMAT（markdown | diff、既定 markdown）/ DIGEST_SKIP_LINES（既定 0）
#         SUMMARY_DRIFT / SUMMARY_OK / CLOSE_COMMENT / COMMENT_INTRO / REPORT_HEADING / REPORT_NOTE
#         ISSUE_DESCRIPTION / ISSUE_EXTRA_SECTIONS / COMPLETION_CRITERIA
#         GITHUB_STEP_SUMMARY（設定されていればジョブサマリーにも書く）
#
# 振る舞い:
#   DRIFT=false: 同じタイトルの open issue があれば、経緯のコメントを残して close する
#   DRIFT=true : open issue が無ければ作成する。あれば、検査結果が前回の通知から変わったときだけコメントで追記する
#
# 「前回の通知」は本文・コメントに埋め込んだ検査結果ハッシュの HTML コメント（GitHub 上では表示されない）で判定する。
#
# 終了コード: 0 = 通知処理が完了 / 2 = 入力や前提の不備。gh や jq が失敗したときはその終了コードで落ちる。
# drift があるときにジョブを失敗させるかどうかは、このスクリプトではなく呼び出し側（action.yml）が決める。
set -euo pipefail

die() { printf 'エラー: %s\n' "$*" >&2; exit 2; }

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd が見つからない"
done
# sha256sum は coreutils のコマンドで macOS には無い。手元でも同じ結果を再現できるよう shasum に切り替える
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 | cut -d' ' -f1; }
else
  die "sha256sum も shasum も見つからない"
fi

for v in DRIFT REPORT_FILE ISSUE_TITLE ISSUE_LABEL RUN_URL; do
  [ -n "${!v:-}" ] || die "$v が空"
done
case "$DRIFT" in
  true | false) ;;
  *) die "DRIFT は true か false でなければならない（実際: ${DRIFT}）" ;;
esac
[ -f "$REPORT_FILE" ] || die "$REPORT_FILE が存在しない"

REPORT_FORMAT="${REPORT_FORMAT:-markdown}"
case "$REPORT_FORMAT" in
  markdown | diff) ;;
  *) die "REPORT_FORMAT は markdown か diff でなければならない（実際: ${REPORT_FORMAT}）" ;;
esac
DIGEST_SKIP_LINES="${DIGEST_SKIP_LINES:-0}"
case "$DIGEST_SKIP_LINES" in
  '' | *[!0-9]*) die "DIGEST_SKIP_LINES は 0 以上の整数でなければならない（実際: ${DIGEST_SKIP_LINES}）" ;;
esac

# 作業ディレクトリは TMPDIR 配下に明示して作る（既定の一時領域に書けない実行環境があるため）
work="$(mktemp -d "${TMPDIR:-/tmp}/notify-drift.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# レポートを Markdown に貼れる形で出力する。unified diff はコードフェンスで囲まないと崩れる
print_report() {
  if [ "$REPORT_FORMAT" = "diff" ]; then
    echo '```diff'
    cat "$REPORT_FILE"
    echo '```'
  else
    cat "$REPORT_FILE"
  fi
}

# 同じタイトルの open issue のうち最初の1件の番号を出力する（無ければ空）。
# タイトル検索は日本語やコロンの扱いが不安定なので、一覧を取得して完全一致で判定する
find_issue() {
  gh issue list --state open --label "$ISSUE_LABEL" --limit 100 --json number,title \
    | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.title == $t) | .number] | first // empty'
}

# ---- ジョブサマリー -------------------------------------------------------------------------
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    if [ "$DRIFT" = "true" ]; then
      echo "## :warning: ${SUMMARY_DRIFT:-drift があります}"
      echo
      print_report
    else
      echo "## :white_check_mark: ${SUMMARY_OK:-drift はありません}"
      # drift が無くても検査スクリプトが情報を残すことがある（対応不要の注記など）。
      # 何も無ければ空のコードフェンスだけが載るのを避けて、見出しで止める
      if [ -s "$REPORT_FILE" ]; then
        echo
        print_report
      fi
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

number="$(find_issue)"

# ---- drift なし: 通知 issue を close ------------------------------------------------------
# 定義側を直す PR の "Closes #N" で先に close されていれば、open issue が見つからず何もしない
if [ "$DRIFT" = "false" ]; then
  if [ -z "$number" ]; then
    echo "closeすべき通知issueはありません"
    exit 0
  fi

  comment="$(printf '%s\n\n実行ログ: %s\n' \
    "${CLOSE_COMMENT:-定期チェックで drift が解消したことを確認したため、自動でcloseしました。}" \
    "$RUN_URL")"
  gh issue close "$number" --reason completed --comment "$comment"
  printf 'issue #%s をcloseしました\n' "$number"
  exit 0
fi

# ---- drift あり: issue を作成、または既存 issue に追記 ------------------------------------
# 先頭の DIGEST_SKIP_LINES 行（実行日時など毎回変わる行）を除いてハッシュを取る。指摘内容が同じなら同じハッシュになる
digest="$(tail -n +"$((DIGEST_SKIP_LINES + 1))" "$REPORT_FILE" | sha256)"
marker="<!-- drift-hash: ${digest} -->"

if [ -n "$number" ]; then
  # 本文とコメントのうち最後に記録されたハッシュが、前回通知した検査結果。
  # 本文が無い issue では body が null になるため、文字列だけを対象にする
  last="$(gh issue view "$number" --json body,comments \
    | jq -r '
      [.body, .comments[].body]
      | map(select(type == "string") | capture("<!-- drift-hash: (?<h>[0-9a-f]{64}) -->").h)
      | last // empty
    ')"

  if [ "$last" = "$digest" ]; then
    printf '既存のissue #%s に同じ検査結果が記録済みのため追記をスキップ\n' "$number"
    exit 0
  fi

  {
    printf '%s\n' "${COMMENT_INTRO:-検査結果が前回の通知から変わりました。}"
    echo
    echo "実行ログ: ${RUN_URL}"
    echo
    print_report
    echo
    echo "$marker"
  } > "$work/comment_body.md"

  gh issue comment "$number" --body-file "$work/comment_body.md"
  printf 'issue #%s に追記しました\n' "$number"
  exit 0
fi

{
  echo "## 課題"
  echo
  printf '%s\n' "${ISSUE_DESCRIPTION:-定期チェックで drift が見つかりました。}"
  echo
  echo "実行ログ: ${RUN_URL}"
  echo
  echo "## ${REPORT_HEADING:-検査結果}"
  echo
  if [ -n "${REPORT_NOTE:-}" ]; then
    printf '%s\n' "$REPORT_NOTE"
    echo
  fi
  print_report
  if [ -n "${ISSUE_EXTRA_SECTIONS:-}" ]; then
    echo
    printf '%s\n' "$ISSUE_EXTRA_SECTIONS"
  fi
  echo
  echo "## 完了条件"
  echo
  printf '%s\n' "${COMPLETION_CRITERIA:-- [ ] drift を解消した}"
  echo
  echo "$marker"
} > "$work/issue_body.md"

gh issue create --title "$ISSUE_TITLE" --body-file "$work/issue_body.md" --label "$ISSUE_LABEL"
echo "issueを作成しました"
