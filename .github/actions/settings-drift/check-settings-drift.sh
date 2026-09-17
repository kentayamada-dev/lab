#!/usr/bin/env bash
#
# .claude/settings.json のキーが公式ドキュメントから乖離（drift）していないか検査する。
#
#   usage: .github/actions/settings-drift/check-settings-drift.sh [settings.json]
#
# 検査内容:
#   1. 使っている各キーが settings-reference の設定索引に載っているか
#   2. そのキーのスコープが "Any file" のままか（それ以外はプロジェクトの settings.json から効かない）
#   3. 公開JSONスキーマで型・enum・書式が妥当か
#
# 終了コード: 0 = 問題なし / 1 = drift あり / 2 = 検査自体が実行できなかった
# 結果は Markdown で標準出力に書く（ワークフローがそのまま issue 本文に使う）。
#
set -euo pipefail

SETTINGS_FILE="${1:-.claude/settings.json}"

# .md を付けると Markdown 版が返る。索引表の形式は https://code.claude.com/docs/en/settings-reference#settings-index
DOCS_URL="https://code.claude.com/docs/en/settings-reference.md"
# settings.json の $schema が指しているものと同じ
SCHEMA_URL="https://json.schemastore.org/claude-code-settings.json"
# 索引表がこの行数を下回ったら、パースが壊れている（ドキュメントの形式変更）と判断して drift ではなく失敗にする
MIN_INDEX_ROWS=100
# スキーマのトップレベル定義がこの件数を下回ったら、取得内容が壊れていると判断して同様に失敗にする
MIN_SCHEMA_PROPS=50

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

for cmd in curl jq; do
  command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} が見つからない"
done
[[ -f "${SETTINGS_FILE}" ]] || die "${SETTINGS_FILE} が存在しない"
jq empty "${SETTINGS_FILE}" 2>/dev/null || die "${SETTINGS_FILE} が JSON として不正"

# 作業ディレクトリは TMPDIR 配下に明示して作る（既定の一時領域に書けない実行環境があるため）
work="$(mktemp -d "${TMPDIR:-/tmp}/settings-drift.XXXXXX")"
trap 'rm -rf "$work"' EXIT

curl -fsSL "${DOCS_URL}" -o "${work}/docs.md" || die "ドキュメントを取得できない: ${DOCS_URL}"
curl -fsSL "${SCHEMA_URL}" -o "${work}/schema.json" || die "スキーマを取得できない: ${SCHEMA_URL}"

# ---- 1. ドキュメントの設定索引を key<TAB>scope の形に落とす ---------------------------------
# 索引表の各行は  | [`key`](#anchor) | 説明 | トピック | スコープ |  の形
awk -F'|' '
  /^\| \[`[^`]+`\]\(#/ {
    key = $2; sub(/^ *\[`/, "", key); sub(/`\].*/, "", key)
    scope = $5; gsub(/^ +| +$/, "", scope)
    print key "\t" scope
  }
' "${work}/docs.md" >"${work}/index.tsv"

rows=$(wc -l <"${work}/index.tsv" | tr -d " ")
[[ "${rows}" -ge "${MIN_INDEX_ROWS}" ]] ||
  die "設定索引を ${rows} 行しか読み取れなかった（${MIN_INDEX_ROWS} 行未満）。ドキュメントの表形式が変わった可能性がある"

index_scope() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "${work}/index.tsv"; }
# 索引がその親の直下のキーを列挙しているか（1件でもあれば、その階層は索引が網羅していると見なす）
index_has_children() {
  awk -F'\t' -v p="$1." 'index($1, p) == 1 { found = 1; exit } END { exit !found }' "${work}/index.tsv"
}

# ---- 2. settings.json のキーをドット区切りで列挙し、索引と照合する --------------------------
# 配列の中（permissions.deny の要素など）はキーではないので、パス要素がすべて文字列のものだけ拾う
jq -r '
  [ paths | select(all(.[]; type == "string")) | join(".") ]
  | map(select(. != "$schema"))
  | unique[]
' "${SETTINGS_FILE}" >"${work}/keys.txt"

problems=()
notes=()

while IFS= read -r key; do
  scope="$(index_scope "${key}")"
  if [[ -n "${scope}" ]]; then
    # プロジェクトの settings.json から設定できるのは "Any file" だけ
    if [[ "${scope}" != "Any file" ]]; then
      problems+=("\`${key}\`: スコープが「${scope}」になっている。プロジェクトの settings.json からは効かない")
    fi
    continue
  fi

  parent="${key%.*}"
  # index_has_children は awk の終了コードで真偽を返す関数なので、if 条件で呼ぶのが正しい使い方。
  # set -e が効かないという指摘は、失敗をエラーとして扱いたい呼び出しに向けたもの。
  # shellcheck disable=SC2310
  if [[ "${parent}" = "${key}" ]] || index_has_children "${parent}"; then
    # トップレベル、または索引が兄弟キーを列挙している階層なのに載っていない → 削除・改名された可能性
    problems+=("\`${key}\`: 設定索引に載っていない（削除・改名された可能性）")
  else
    # 索引がその階層を列挙していない（例: credentials.files の中身）ので、親が載っていれば良しとする
    parent_scope="$(index_scope "${parent}")"
    [[ -n "${parent_scope}" ]] ||
      problems+=("\`${key}\`: 親キー \`${parent}\` が設定索引に載っていない")
  fi
done <"${work}/keys.txt"

# ---- 3. JSONスキーマで型・enum・書式を検証する --------------------------------------------
# 以前は ajv-cli を npx で取得して使っていたが、npx の失敗（レジストリ障害・キャッシュ権限など）と
# 「エラー0件」がどちらも終了コード1で返り、検査が空振りしても「問題なし」になっていたためやめた。
# jq だけで検証すれば、失敗は jq の終了コードとしてそのまま扱える。
#
# 検証できるのは type / enum / pattern / additionalProperties に限られる。
# anyOf・oneOf・allOf はどの枝を適用すべきか決められないため、誤検知を避けて検査しない。
cat >"${work}/validate.jq" <<'JQ'
# パイプや条件式の縦位置を揃えるため、インデント幅が .editorconfig の indent_size(2) の倍数にならない。
# jq では # がコメントなので、この行は editorconfig-checker への指示としてだけ働き、実行には影響しない。
# https://github.com/editorconfig-checker/editorconfig-checker#excluding-blocks
# editorconfig-checker-disable
# このスキーマの $ref は "#/$defs/x" 形式しかないので、1段だけ解決すれば足りる
def deref($root):
  if (type == "object" and has("$ref"))
  then (.["$ref"] | ltrimstr("#/") | split("/")) as $p | ($root | getpath($p))
  else . end;

def type_ok($t):
  . as $v
  | if $t == "integer" then (($v | type) == "number" and ($v | floor) == $v)
    elif $t == "number" then ($v | type) == "number"
    else ($v | type) == $t end;

def check($schema; $path; $root):
  . as $v
  | ($schema | deref($root)) as $s
  | if ($s | type) != "object" then empty
    elif (($s | has("anyOf")) or ($s | has("oneOf")) or ($s | has("allOf"))) then empty
    else
      (if ($s | has("type"))
       then (($s.type | if type == "array" then . else [.] end) as $ts
             | if any($ts[]; . as $t | $v | type_ok($t)) then empty
               else ["type", $path, (($ts | join("|")) + " のはずが " + ($v | type))] end)
       else empty end),

      (if ($s | has("enum"))
       then (if any($s.enum[]; . == $v) then empty
             else ["enum", $path, ("次のいずれかであるべき: " + ($s.enum | map(tostring) | join(", ")))] end)
       else empty end),

      # 正規表現の方言差で落ちたときは検査不能として黙って飛ばす（誤検知にしない）
      (if (($s | has("pattern")) and ($v | type) == "string")
       then (try (if ($v | test($s.pattern)) then empty
                  else ["pattern", $path, ("書式が不正: " + $v)] end)
             catch empty)
       else empty end),

      (if ($v | type) == "object"
       then ($v | to_entries[] as $e
             | (if $path == "" then $e.key else $path + "." + $e.key end) as $child
             | if (($s.properties // {}) | has($e.key))
               then ($e.value | check($s.properties[$e.key]; $child; $root))
               elif $s.additionalProperties == false
               then ["additionalProperties", $child, "スキーマに定義されていないキー"]
               elif ($s.additionalProperties | type) == "object"
               then ($e.value | check($s.additionalProperties; $child; $root))
               else empty end)
       elif ($v | type) == "array"
       then (if ($s | has("items"))
             then (range($v | length) as $i
                   | $v[$i] | check($s.items; $path + "[" + ($i | tostring) + "]"; $root))
             else empty end)
       else empty end)
    end;

$schema[0] as $root | check($root; ""; $root) | @tsv
# editorconfig-checker-enable
JQ

# 取得したスキーマが壊れていないか（空・HTMLが返ってきた等）を先に弾く。
# ここを通さないと、検証は空振りするのに「問題なし」に見えてしまう。
schema_props="$(jq -r '.properties | length' "${work}/schema.json" 2>/dev/null || echo 0)"
case "${schema_props}" in
  '' | *[!0-9]*) schema_props=0 ;;
  *) ;;
esac
[[ "${schema_props}" -ge "${MIN_SCHEMA_PROPS}" ]] ||
  die "スキーマのトップレベル定義を ${schema_props} 件しか読み取れなかった（${MIN_SCHEMA_PROPS} 件未満）。取得先の内容が変わった可能性がある"

# 失敗を握りつぶさない。jq が落ちたら drift なしではなく検査自体の失敗として扱う
jq -r --slurpfile schema "${work}/schema.json" -f "${work}/validate.jq" "${SETTINGS_FILE}" \
  >"${work}/schema-errors.tsv" || die "スキーマ検証を実行できなかった"

while IFS=$'\t' read -r keyword path message; do
  [[ -n "${keyword}" ]] || continue
  path_scope="$(index_scope "${path}")"
  if [[ "${keyword}" = "additionalProperties" ]] && [[ -n "${path_scope}" ]]; then
    # スキーマは CLI より遅れることがあり、公式もそれを認めている
    # https://code.claude.com/docs/en/settings#edit-a-settings-file
    notes+=("\`${path}\`: 公開スキーマにはまだ無いが、設定索引には載っている（スキーマ側の遅れ）")
  else
    problems+=("\`${path}\`: スキーマ検証エラー（${keyword}）: ${message}")
  fi
done <"${work}/schema-errors.tsv"

# ---- 結果 ---------------------------------------------------------------------------------
key_count="$(wc -l <"${work}/keys.txt" | tr -d " ")"
checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '確認したキー: %s 件（設定索引 %s 行、%s）\n\n' "${key_count}" "${rows}" "${checked_at}"

if [[ "${#notes[@]}" -gt 0 ]]; then
  echo "### 情報（対応不要）"
  echo
  printf -- '- %s\n' "${notes[@]}"
  echo
fi

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo "### 問題"
  echo
  printf -- '- %s\n' "${problems[@]}"
  exit 1
fi

echo "問題なし"
