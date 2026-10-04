#!/usr/bin/env bash
# bats の書き方に由来する指摘を外す（各コードの理由は scripts/lib/bats-helpers.bash 冒頭）
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# check-settings-drift.sh のテスト用スタブ。実ネットワークに触れないよう curl を差し替え、応答をフィクスチャで固定する。
load ../../../../scripts/lib/bats-helpers

# ---- スタブとフィクスチャ -------------------------------------------------------------------

# curl のスタブ。URL に応じてフィクスチャを -o の出力先へコピーする。
# STUB_CURL_FAIL_DOCS / STUB_CURL_FAIL_SCHEMA を立てると取得失敗を再現する。
install_curl_stub() {
  cat >"${STUB_BIN}/curl" <<'STUB'
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

# 引数は "キー<TAB>スコープ" の並び。索引が MIN_INDEX_ROWS 行未満だと終了コード2で落ちるため埋め草で水増しする
# （行数不足を検証するときは DOCS_FILLER_ROWS=0）。
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
  } >"${out}"
}

# $1: properties、$2: $defs に足すJSON（省略時は空）。MIN_SCHEMA_PROPS 件未満だと取得失敗扱いになるため
# 既定で水増しする（件数不足の検証は SCHEMA_FILLER_PROPS=0）。
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
  ' >"${STUB_FIXTURES}/schema.json"
}

# 検査対象の settings.json を書き、そのパスを出力する
write_settings() {
  local path="${BATS_TEST_TMPDIR}/settings.json"
  cat >"${path}"
  printf '%s' "${path}"
}
