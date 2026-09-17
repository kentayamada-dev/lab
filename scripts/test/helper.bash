#!/usr/bin/env bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# apply-repo-settings.sh の bats テスト用ヘルパ。
#
# テストは実GitHubに触れない。外部へ出る gh は PATH の先頭に置いたスタブへ差し替え、
# 応答は環境変数で固定する。
#
# スタブの置き場（setup_stubs / only_commands）と判定（assert_*）は他のテストと同じものを使うため、
# scripts/lib/bats-helpers.bash に置いている。ここに残すのは apply-repo-settings.sh 固有のスタブと判定だけ。
load ../lib/bats-helpers

# ---- apply-repo-settings.sh 用 --------------------------------------------------------------

# gh のスタブ。
#
# 呼び出しの引数をそのまま GH_LOG へ、--input - で渡された本文を
# "エンドポイント<TAB>JSON" の形で GH_BODY_LOG へ記録する。
# 応答が必要なエンドポイントだけ環境変数の値を返す。
install_gh_stub() {
  GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
  GH_BODY_LOG="${BATS_TEST_TMPDIR}/gh-body.log"
  : >"${GH_LOG}"
  : >"${GH_BODY_LOG}"
  export GH_LOG GH_BODY_LOG

  cat >"${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

printf '%s\n' "$*" >> "$GH_LOG"

case "${1:-}" in
  auth)
    exit "${GH_AUTH_EXIT:-0}"
    ;;
  repo)
    [ "${GH_REPO_VIEW_EXIT:-0}" -eq 0 ] || exit "${GH_REPO_VIEW_EXIT}"
    repo_json="${GH_REPO_JSON:-}"
    [ -n "$repo_json" ] || repo_json='{}'
    printf '%s\n' "$repo_json"
    exit 0
    ;;
  api) ;;
  *) exit 0 ;;
esac

args=("$@")

# 本文を標準入力から受け取る呼び出しかどうかを先に判定する
reads_stdin=0
prev=""
for a in "${args[@]}"; do
  if [ "$prev" = "--input" ] && [ "$a" = "-" ]; then
    reads_stdin=1
  fi
  prev="$a"
done

# エンドポイントは api 以降でフラグでもフラグの値でもない最初の引数
shift
endpoint=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --method|--jq|--input|-f|-F|-H|--field|--raw-field) shift 2 ;;
    -*) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done

if [ "$reads_stdin" -eq 1 ]; then
  body="$(cat)"
  printf '%s\t%s\n' "$endpoint" "$(jq -c . <<<"$body")" >> "$GH_BODY_LOG"
fi

case "$endpoint" in
  */rulesets)
    [ -z "${GH_RULESETS_TSV:-}" ] || printf '%s\n' "$GH_RULESETS_TSV"
    ;;
  */code-scanning/default-setup)
    printf '%s\n' "${GH_CODEQL_STATE:-not-configured}"
    ;;
  */labels)
    [ -z "${GH_LABELS:-}" ] || printf '%s\n' "$GH_LABELS"
    ;;
esac

exit 0
STUB
  chmod +x "${STUB_BIN}/gh"
}

# スクリプトが動く先のgitリポジトリを作り、そのパスを出力する
make_repo() {
  local dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${dir}/.github/rulesets"
  git -C "${dir}" init --quiet
  printf '%s' "${dir}"
}

# GH_LOG に記録された呼び出しのうち、引数に指定文字列をすべて含む行数を出力する
gh_calls_matching() {
  local pattern
  local count=0
  local line
  while IFS= read -r line; do
    local ok=1
    for pattern in "$@"; do
      case "${line}" in
        *"${pattern}"*) ;;
        *)
          ok=0
          break
          ;;
      esac
    done
    [[ "${ok}" -eq 0 ]] || count=$((count + 1))
  done <"${GH_LOG}"
  printf '%s' "${count}"
}
