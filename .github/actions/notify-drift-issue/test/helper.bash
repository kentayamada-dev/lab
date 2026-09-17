#!/usr/bin/env bash
#
# notify-drift-issue.sh の bats テスト用ヘルパ。
#
# テストは実GitHubに触れない。gh は PATH の先頭に置いたスタブへ差し替え、
# 「何を送ったか」「何を送らなかったか」を記録から観測する。
#
# スタブの置き場（setup_stubs / only_commands）と判定（assert_*）は他のテストと同じものを使うため、
# scripts/lib/bats-helpers.bash に置いている。ここに残すのはこの action 固有のスタブと判定だけ。
load ../../../../scripts/lib/bats-helpers

# ---- gh のスタブ ----------------------------------------------------------------------------

# 呼び出しの引数を1呼び出し1行で GH_LOG へ記録し、--body-file で渡された本文は
# GH_BODY_DIR/<サブコマンド>.md に保存する（gh_body で読む）。
#
# --comment の本文のように引数に改行が含まれると1呼び出しが複数行に割れ、
# 行単位で照合する gh_calls_matching が同じ呼び出しの引数を別々の行として見てしまう。
# そのため改行は \n の2文字に置き換えて記録する。
#
# 応答は環境変数で固定する:
#   GH_ISSUE_LIST_JSON  : gh issue list の応答（既定 []）
#   GH_ISSUE_VIEW_JSON  : gh issue view の応答（既定は本文もコメントも空）
#   GH_FAIL_SUBCOMMAND  : このサブコマンド（create など）を終了コード1で失敗させる
install_gh_stub() {
  GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  GH_BODY_DIR="$BATS_TEST_TMPDIR/gh-bodies"
  : > "$GH_LOG"
  rm -rf "$GH_BODY_DIR"
  mkdir -p "$GH_BODY_DIR"
  export GH_LOG GH_BODY_DIR

  cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

args="$*"
printf '%s\n' "${args//$'\n'/\\n}" >> "$GH_LOG"

if [ "${1:-}" != "issue" ]; then
  printf 'gh stub: 想定外のサブコマンド: %s\n' "$*" >&2
  exit 1
fi
sub="${2:-}"
shift 2

if [ -n "${GH_FAIL_SUBCOMMAND:-}" ] && [ "$sub" = "$GH_FAIL_SUBCOMMAND" ]; then
  exit 1
fi

while [ "$#" -gt 0 ]; do
  if [ "$1" = "--body-file" ]; then
    cp "$2" "$GH_BODY_DIR/$sub.md"
    shift 2
  else
    shift
  fi
done

case "$sub" in
  list)
    printf '%s\n' "${GH_ISSUE_LIST_JSON:-[]}"
    ;;
  view)
    view_json="${GH_ISSUE_VIEW_JSON:-}"
    [ -n "$view_json" ] || view_json='{"body":"","comments":[]}'
    printf '%s\n' "$view_json"
    ;;
esac

exit 0
STUB
  chmod +x "$STUB_BIN/gh"
}

# GH_LOG に記録された呼び出しのうち、引数に指定文字列をすべて含む行数を出力する
gh_calls_matching() {
  local pattern
  local count=0
  local line
  while IFS= read -r line; do
    local ok=1
    for pattern in "$@"; do
      case "$line" in
        *"$pattern"*) ;;
        *) ok=0; break ;;
      esac
    done
    [ "$ok" -eq 0 ] || count=$((count + 1))
  done < "$GH_LOG"
  printf '%s' "$count"
}

# --body-file で送られた本文を出力する（$1: create / comment）
gh_body() { cat "$GH_BODY_DIR/$1.md"; }

# gh issue list の応答を作る。引数は "番号<TAB>タイトル" の並び
issue_list_json() {
  local entry number title
  {
    for entry in "$@"; do
      IFS=$'\t' read -r number title <<<"$entry"
      jq -cn --argjson n "$number" --arg t "$title" '{number: $n, title: $t}'
    done
  } | jq -cs .
}

# gh issue view の応答を作る。$1 が本文（"<null>" なら null）、以降の引数がコメント本文
issue_view_json() {
  local body="$1"
  shift
  jq -cn --arg body "$body" '
    { body: (if $body == "<null>" then null else $body end),
      comments: [$ARGS.positional[] | { body: . }] }
  ' --args "$@"
}

# 検査対象のレポートを書く。引数を1行ずつ書き、パスは REPORT_FILE に従う
write_report() {
  printf '%s\n' "$@" > "$REPORT_FILE"
}

# ---- 判定 -----------------------------------------------------------------------------------

# assert_equal だけはこの action でしか使わないため共有していない。
# [[ ]] を避けている理由は共有ヘルパのコメント。

assert_equal() {
  [ "$1" = "$2" ] && return 0
  printf '一致しない\n--- 期待 ---\n%s\n--- 実際 ---\n%s\n' "$2" "$1" >&2
  return 1
}
