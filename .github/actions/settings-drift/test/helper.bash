#!/usr/bin/env bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# check-settings-drift.sh の bats テスト用ヘルパ。
#
# テストは実ネットワークに触れない。外部へ出る curl は PATH の先頭に置いたスタブへ差し替え、
# 応答はフィクスチャで固定する。
#
# スタブの置き場（setup_stubs / only_commands）と判定（assert_*）は他のテストと同じものを使うため、
# scripts/lib/bats-helpers.bash に置いている。ここに残すのはこの action 固有のスタブと判定だけ。
load ../../../../scripts/lib/bats-helpers

# ---- スタブとフィクスチャ -------------------------------------------------------------------

# curl のスタブ。URL に応じてフィクスチャを -o の出力先へコピーする。
# STUB_CURL_FAIL_DOCS / STUB_CURL_FAIL_SCHEMA を立てると取得失敗を再現する。
install_curl_stub() {
  cat > "${STUB_BIN}/curl" <<'STUB'
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
  chmod +x "${STUB_BIN}/curl"
}

# 設定索引のドキュメントを作る。引数は "キー<TAB>スコープ" の並び。
#
# スクリプトは索引が MIN_INDEX_ROWS(100) 行未満だと「表形式が変わった」と見なして
# 終了コード2で落ちるため、既定では埋め草の行で水増しする。
# 行数を意図的に減らす検証では DOCS_FILLER_ROWS=0 を指定する。
write_docs() {
  local out="${STUB_FIXTURES}/docs.md"
  local filler="${DOCS_FILLER_ROWS-120}"
  local entry key scope i

  {
    printf '# Settings reference\n\n## Settings index\n\n'
    printf '| Setting | Description | Topic | Scope |\n'
    printf '|---|---|---|---|\n'
    for entry in "$@"; do
      IFS=$'\t' read -r key scope <<<"${entry}"
      printf '| [`%s`](#%s) | 説明 | topic | %s |\n' "${key}" "${key}" "${scope}"
    done
    i=0
    while [[ "${i}" -lt "${filler}" ]]; do
      printf '| [`filler%s`](#filler%s) | 説明 | topic | Any file |\n' "${i}" "${i}"
      i=$((i + 1))
    done
  } > "${out}"
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

  [[ -n "${props}" ]] || props='{}'
  [[ -n "${defs}" ]] || defs='{}'

  jq -n \
    --argjson props "${props}" \
    --argjson defs "${defs}" \
    --argjson n "${filler}" '
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
  ' > "${STUB_FIXTURES}/schema.json"
}

# 検査対象の settings.json を書き、そのパスを出力する
write_settings() {
  local path="${BATS_TEST_TMPDIR}/settings.json"
  cat > "${path}"
  printf '%s' "${path}"
}
