#!/usr/bin/env bash
# bats の書き方由来の誤検出を外す: SC2030/SC2031（@test ごとの subshell）、SC2154（bats・load 先が設定する変数）、
# SC2016（期待値の $ を展開しない）、SC2312（失敗は run で受ける）
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

# gh のスタブ。引数を GH_LOG に、--input - の本文を "エンドポイント<TAB>JSON" で GH_BODY_LOG に記録し、
# 応答が要るエンドポイントだけ環境変数の値を返す。
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

reads_stdin=0
prev=""
for a in "${args[@]}"; do
  if [ "$prev" = "--input" ] && [ "$a" = "-" ]; then
    reads_stdin=1
  fi
  prev="$a"
done

# エンドポイントは api 以降でフラグでもフラグの値でもない引数。複数あれば最後のものになる
shift
endpoint=""
jq_filter=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jq) jq_filter="$2"; shift 2 ;;
    --method|--input|-f|-F|-H|--field|--raw-field) shift 2 ;;
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
    # スクリプトが --jq で並べ替え・整形するため、JSON に --jq を適用して返す。
    # gh の --jq が文字列を引用符なしで出す（jq -r 相当）ことは公式に明記が無く未検証
    # https://cli.github.com/manual/gh_api
    jq -n --arg state "${GH_CODEQL_STATE:-not-configured}" --arg languages "${GH_CODEQL_LANGUAGES:-}" \
      '{state: $state, languages: (if $languages == "" then null else ($languages | split(",")) end)}' |
      jq -r "${jq_filter:-.}" || exit 1
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
