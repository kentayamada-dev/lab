#!/usr/bin/env bash
#
# batsテスト共通のヘルパ。
#
# テストは実ネットワークにも実GitHubにも触れない。外部へ出るコマンド（curl / gh）は
# PATH の先頭に置いたスタブへ差し替え、応答は環境変数で固定する。
#
# テストで使う `run -N` は 1.5.0 以降の構文。下の宣言が無いと旧版との互換のため警告 BW02 が出る。
# CI が導入する bats の版は .github/workflows/ci.yml の scripts-test ジョブに書いてある。
# https://bats-core.readthedocs.io/en/stable/warnings/BW02.html
bats_require_minimum_version 1.5.0

# スタブを置くディレクトリを PATH の先頭に差し込む。
# フィクスチャ（取得したことにするドキュメント・スキーマ）の置き場もここに作る。
setup_stubs() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$STUB_BIN" "$STUB_FIXTURES"
  PATH="$STUB_BIN:$PATH"
  export PATH STUB_BIN STUB_FIXTURES
}

# 指定したコマンドだけが見つかる PATH 用ディレクトリを作り、そのパスを出力する。
# 「jq が無いときに前提チェックで落ちるか」の検証に使う。
#
# env と bash は常に含める。検査対象のスクリプトは #!/usr/bin/env bash で起動するため、
# これを外すとスクリプトが実行されず、前提チェックの結果ではなく 127 を見ることになる。
only_commands() {
  local dir="$BATS_TEST_TMPDIR/only-bin"
  rm -rf "$dir"
  mkdir -p "$dir"

  local cmd src
  for cmd in env bash "$@"; do
    if [ -x "$STUB_BIN/$cmd" ]; then
      cp "$STUB_BIN/$cmd" "$dir/$cmd"
    else
      src="$(command -v "$cmd")" || return 1
      ln -s "$src" "$dir/$cmd"
    fi
  done

  printf '%s' "$dir"
}

# ---- check-settings-drift.sh 用 -------------------------------------------------------------

# curl のスタブ。URL に応じてフィクスチャを -o の出力先へコピーする。
# STUB_CURL_FAIL_DOCS / STUB_CURL_FAIL_SCHEMA を立てると取得失敗を再現する。
install_curl_stub() {
  cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

url=""
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done

case "$url" in
  *settings-reference*) src="$STUB_FIXTURES/docs.md"; fail="${STUB_CURL_FAIL_DOCS:-}" ;;
  *claude-code-settings*) src="$STUB_FIXTURES/schema.json"; fail="${STUB_CURL_FAIL_SCHEMA:-}" ;;
  *) printf 'curl stub: 想定外のURL: %s\n' "$url" >&2; exit 6 ;;
esac

[ -z "$fail" ] || exit 22
cp "$src" "$out"
STUB
  chmod +x "$STUB_BIN/curl"
}

# 設定索引のドキュメントを作る。引数は "キー<TAB>スコープ" の並び。
#
# スクリプトは索引が MIN_INDEX_ROWS(100) 行未満だと「表形式が変わった」と見なして
# 終了コード2で落ちるため、既定では埋め草の行で水増しする。
# 行数を意図的に減らす検証では DOCS_FILLER_ROWS=0 を指定する。
write_docs() {
  local out="$STUB_FIXTURES/docs.md"
  local filler="${DOCS_FILLER_ROWS-120}"
  local entry key scope i

  {
    printf '# Settings reference\n\n## Settings index\n\n'
    printf '| Setting | Description | Topic | Scope |\n'
    printf '|---|---|---|---|\n'
    for entry in "$@"; do
      IFS=$'\t' read -r key scope <<<"$entry"
      printf '| [`%s`](#%s) | 説明 | topic | %s |\n' "$key" "$key" "$scope"
    done
    i=0
    while [ "$i" -lt "$filler" ]; do
      printf '| [`filler%s`](#filler%s) | 説明 | topic | Any file |\n' "$i" "$i"
      i=$((i + 1))
    done
  } > "$out"
}

# 公開JSONスキーマを作る。
#   $1: properties に足すJSONオブジェクト（省略時は空）
#   $2: $defs に足すJSONオブジェクト（省略時は空）
#
# トップレベル定義が MIN_SCHEMA_PROPS(50) 件未満だと取得内容が壊れていると見なされるため、
# こちらも既定で水増しする。件数を減らす検証では SCHEMA_FILLER_PROPS=0 を指定する。
write_schema() {
  local props="${1:-}"
  local defs="${2:-}"
  local filler="${SCHEMA_FILLER_PROPS-60}"

  [ -n "$props" ] || props='{}'
  [ -n "$defs" ] || defs='{}'

  jq -n \
    --argjson props "$props" \
    --argjson defs "$defs" \
    --argjson n "$filler" '
    {
      "$schema": "http://json-schema.org/draft-07/schema#",
      "$defs": $defs,
      type: "object",
      properties: (
        { "$schema": { type: "string" } }
        + ([range($n) | { key: "filler\(.)", value: { type: "string" } }] | from_entries)
        + $props
      ),
      additionalProperties: false
    }
  ' > "$STUB_FIXTURES/schema.json"
}

# 検査対象の settings.json を書き、そのパスを出力する
write_settings() {
  local path="$BATS_TEST_TMPDIR/settings.json"
  cat > "$path"
  printf '%s' "$path"
}

# ---- apply-repo-settings.sh 用 --------------------------------------------------------------

# gh のスタブ。
#
# 呼び出しの引数をそのまま GH_LOG へ、--input - で渡された本文を
# "エンドポイント<TAB>JSON" の形で GH_BODY_LOG へ記録する。
# 応答が必要なエンドポイントだけ環境変数の値を返す。
install_gh_stub() {
  GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  GH_BODY_LOG="$BATS_TEST_TMPDIR/gh-body.log"
  : > "$GH_LOG"
  : > "$GH_BODY_LOG"
  export GH_LOG GH_BODY_LOG

  cat > "$STUB_BIN/gh" <<'STUB'
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
  chmod +x "$STUB_BIN/gh"
}

# スクリプトが動く先のgitリポジトリを作り、そのパスを出力する
make_repo() {
  local dir="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$dir/.github/rulesets"
  git -C "$dir" init --quiet
  printf '%s' "$dir"
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

# ---- 判定 -----------------------------------------------------------------------------------

# 出力の照合には [[ ]] を使わない。
# bash 3.2 の set -e は [[ ]] の偽を検知せず、bats もテスト失敗として扱わないため、
# 偽の判定が黙って通り過ぎてしまう（テストが何も検証しない状態になる）。
# 関数の return 1 なら bats が失敗として拾う。

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf '含まれているべき文字列がない: %s\n--- 実際の出力 ---\n%s\n' "$2" "$1" >&2
  return 1
}

assert_not_contains() {
  case "$1" in
    *"$2"*)
      printf '含まれていてはいけない文字列がある: %s\n--- 実際の出力 ---\n%s\n' "$2" "$1" >&2
      return 1
      ;;
  esac
  return 0
}

assert_prefix() {
  case "$1" in
    "$2"*) return 0 ;;
  esac
  printf 'この文字列で始まっていない: %s\n--- 実際 ---\n%s\n' "$2" "$1" >&2
  return 1
}
