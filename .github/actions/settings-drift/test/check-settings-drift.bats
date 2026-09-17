#!/usr/bin/env bats
# bats の shebang は shellcheck が方言を判別できないため明示する
# shellcheck shell=bash
#
# check-settings-drift.sh のテスト。
#
# ドキュメントとスキーマの取得は curl のスタブで置き換え、
# 「どんな入力のときに何を問題として報告し、どの終了コードで終わるか」を検証する。

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../check-settings-drift.sh"
  setup_stubs
  install_curl_stub
}

# どのテストからも出発点にできる、問題のない状態を作る
default_docs() {
  write_docs \
    $'cleanupPeriodDays\tAny file' \
    $'permissions\tAny file' \
    $'permissions.allow\tAny file' \
    $'permissions.defaultMode\tAny file'
}

default_schema() {
  write_schema '{
    "cleanupPeriodDays": { "type": "integer" },
    "permissions": {
      "type": "object",
      "properties": {
        "defaultMode": { "enum": ["default", "acceptEdits", "plan"] },
        "allow": { "type": "array", "items": { "type": "string" } }
      },
      "additionalProperties": false
    }
  }'
}

default_settings() {
  write_settings <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "cleanupPeriodDays": 14,
  "permissions": {
    "defaultMode": "default",
    "allow": ["Bash(ls:*)"]
  }
}
JSON
}

# ---- 正常系 ---------------------------------------------------------------------------------

@test "索引・スコープ・スキーマがすべて揃っていれば問題なしで終わる" {
  default_docs
  default_schema
  settings="$(default_settings)"

  run -0 "$SCRIPT" "$settings"

  assert_contains "$output" "問題なし"
  # $schema はキーとして数えない。残る4キーだけを見ている
  assert_prefix "${lines[0]}" "確認したキー: 4 件（設定索引 "
  assert_not_contains "$output" "### 問題"
}

@test "設定が空でも0件を確認したものとして問題なしで終わる" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{}')"

  run -0 "$SCRIPT" "$settings"

  assert_prefix "${lines[0]}" "確認したキー: 0 件（設定索引 "
  assert_contains "$output" "問題なし"
}

@test "配列の要素はキーとして検査しない" {
  # permissions.allow の中身まで索引と照合し始めると、必ず「索引に載っていない」になる
  write_docs $'permissions\tAny file' $'permissions.allow\tAny file'
  write_schema '{
    "permissions": {
      "type": "object",
      "properties": { "allow": { "type": "array", "items": { "type": "string" } } }
    }
  }'
  settings="$(write_settings <<<'{"permissions":{"allow":["Bash(ls:*)","Bash(cat:*)"]}}')"

  run -0 "$SCRIPT" "$settings"

  assert_prefix "${lines[0]}" "確認したキー: 2 件（設定索引 "
}

@test "索引がその階層を列挙していなければ、親が載っているだけで許容する" {
  # credentials.files[].path のように、索引が中身まで列挙していない設定がある
  write_docs $'outer\tAny file'
  write_schema '{ "outer": { "type": "object" } }'
  settings="$(write_settings <<<'{"outer":{"mid":"x"}}')"

  run -0 "$SCRIPT" "$settings"

  assert_contains "$output" "問題なし"
}

@test "引数を省略すると .claude/settings.json を見る" {
  default_docs
  default_schema
  mkdir -p "$BATS_TEST_TMPDIR/proj/.claude"
  default_settings > /dev/null
  cp "$BATS_TEST_TMPDIR/settings.json" "$BATS_TEST_TMPDIR/proj/.claude/settings.json"
  cd "$BATS_TEST_TMPDIR/proj"

  run -0 "$SCRIPT"

  assert_contains "$output" "問題なし"
}

# ---- 索引との照合 ---------------------------------------------------------------------------

@test "スコープが Any file でないキーは問題として報告する" {
  write_docs $'managedOnlyKey\tManaged settings only'
  write_schema '{ "managedOnlyKey": { "type": "string" } }'
  settings="$(write_settings <<<'{"managedOnlyKey":"x"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" "### 問題"
  assert_contains "$output" '`managedOnlyKey`: スコープが「Managed settings only」になっている'
}

@test "索引に無いトップレベルキーは削除・改名の可能性として報告する" {
  write_docs $'knownKey\tAny file'
  write_schema '{ "knownKey": { "type": "string" }, "goneKey": { "type": "string" } }'
  settings="$(write_settings <<<'{"knownKey":"x","goneKey":"y"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`goneKey`: 設定索引に載っていない'
  assert_not_contains "$output" '`knownKey`: 設定索引に載っていない'
}

@test "索引が兄弟キーを列挙している階層で自分だけ載っていなければ報告する" {
  write_docs $'permissions\tAny file' $'permissions.allow\tAny file'
  write_schema '{
    "permissions": {
      "type": "object",
      "properties": {
        "allow": { "type": "array", "items": { "type": "string" } },
        "deny": { "type": "array", "items": { "type": "string" } }
      }
    }
  }'
  settings="$(write_settings <<<'{"permissions":{"allow":[],"deny":[]}}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`permissions.deny`: 設定索引に載っていない'
}

@test "索引が列挙していない階層でも、親自体が索引に無ければ報告する" {
  # outer だけが索引にある状態で outer.mid.leaf を見ると、親 outer.mid が根拠を持たない
  write_docs $'outer\tAny file'
  write_schema '{ "outer": { "type": "object" } }'
  settings="$(write_settings <<<'{"outer":{"mid":{"leaf":"x"}}}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`outer.mid.leaf`: 親キー `outer.mid` が設定索引に載っていない'
}

# ---- スキーマ検証 ---------------------------------------------------------------------------

@test "型が合わないとスキーマ検証エラーになる" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{"cleanupPeriodDays":"14"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`cleanupPeriodDays`: スキーマ検証エラー（type）: integer のはずが string'
}

@test "整数を期待する箇所に小数を書くと型エラーになる" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{"cleanupPeriodDays":14.5}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`cleanupPeriodDays`: スキーマ検証エラー（type）'
}

@test "null も型エラーとして報告する" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{"cleanupPeriodDays":null}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" 'integer のはずが null'
}

@test "enum にない値は候補付きで報告する" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{"permissions":{"defaultMode":"bogus"}}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`permissions.defaultMode`: スキーマ検証エラー（enum）'
  assert_contains "$output" "default, acceptEdits, plan"
}

@test "pattern に合わない文字列は書式不正として報告する" {
  write_docs $'model\tAny file'
  write_schema '{ "model": { "type": "string", "pattern": "^claude-" } }'
  settings="$(write_settings <<<'{"model":"gpt"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`model`: スキーマ検証エラー（pattern）: 書式が不正: gpt'
}

@test "配列の要素も添字付きで検証する" {
  default_docs
  default_schema
  settings="$(write_settings <<<'{"permissions":{"allow":[123]}}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`permissions.allow[0]`: スキーマ検証エラー（type）: string のはずが number'
}

@test "\$ref は \$defs を1段たどって検証する" {
  write_docs $'mode\tAny file'
  write_schema \
    '{ "mode": { "$ref": "#/$defs/mode" } }' \
    '{ "mode": { "enum": ["a", "b"] } }'
  settings="$(write_settings <<<'{"mode":"c"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`mode`: スキーマ検証エラー（enum）'
}

@test "anyOf を含む定義は誤検知を避けて検査しない" {
  write_docs $'flexible\tAny file'
  write_schema '{ "flexible": { "anyOf": [{ "type": "string" }, { "type": "boolean" }] } }'
  settings="$(write_settings <<<'{"flexible":123}')"

  run -0 "$SCRIPT" "$settings"

  assert_contains "$output" "問題なし"
}

@test "スキーマに無いが索引にはあるキーは、対応不要の情報として扱う" {
  write_docs $'newKey\tAny file'
  write_schema '{}'
  settings="$(write_settings <<<'{"newKey":"x"}')"

  run -0 "$SCRIPT" "$settings"

  assert_contains "$output" "### 情報（対応不要）"
  assert_contains "$output" '`newKey`: 公開スキーマにはまだ無いが、設定索引には載っている'
  assert_not_contains "$output" "### 問題"
}

@test "スキーマにも索引にも無いキーは問題として扱う" {
  write_docs $'knownKey\tAny file'
  write_schema '{ "knownKey": { "type": "string" } }'
  settings="$(write_settings <<<'{"knownKey":"x","unknownKey":"y"}')"

  run -1 "$SCRIPT" "$settings"

  assert_contains "$output" '`unknownKey`: スキーマ検証エラー（additionalProperties）'
  assert_not_contains "$output" "### 情報（対応不要）"
}

# ---- 検査自体が成立しないとき（終了コード2） -------------------------------------------------

@test "設定ファイルが無ければ終了コード2" {
  default_docs
  default_schema

  run -2 "$SCRIPT" "$BATS_TEST_TMPDIR/missing.json"

  assert_contains "$output" "が存在しない"
}

@test "設定ファイルがJSONとして不正なら終了コード2" {
  default_docs
  default_schema
  path="$BATS_TEST_TMPDIR/broken.json"
  printf '{ "a": }' > "$path"

  run -2 "$SCRIPT" "$path"

  assert_contains "$output" "JSON として不正"
}

@test "jq が無ければ検査せず終了コード2" {
  default_docs
  default_schema
  settings="$(default_settings)"

  # PATH をテスト側で壊すと bats 自身の後処理も道具を失うため、実行時だけ差し替える
  run -2 env PATH="$(only_commands curl)" "$SCRIPT" "$settings"

  assert_contains "$output" "jq が見つからない"
}

@test "curl が無ければ検査せず終了コード2" {
  default_docs
  default_schema
  settings="$(default_settings)"

  run -2 env PATH="$(only_commands jq)" "$SCRIPT" "$settings"

  assert_contains "$output" "curl が見つからない"
}

@test "ドキュメントを取得できなければ終了コード2" {
  default_docs
  default_schema
  settings="$(default_settings)"
  export STUB_CURL_FAIL_DOCS=1

  run -2 "$SCRIPT" "$settings"

  assert_contains "$output" "ドキュメントを取得できない"
}

@test "スキーマを取得できなければ終了コード2" {
  default_docs
  default_schema
  settings="$(default_settings)"
  export STUB_CURL_FAIL_SCHEMA=1

  run -2 "$SCRIPT" "$settings"

  assert_contains "$output" "スキーマを取得できない"
}

@test "索引の行数が閾値を下回ったら drift ではなく検査失敗にする" {
  # ドキュメントの表形式が変わったのに「問題なし」と報告してしまうのを防ぐ
  DOCS_FILLER_ROWS=0 write_docs $'cleanupPeriodDays\tAny file'
  default_schema
  settings="$(default_settings)"

  run -2 "$SCRIPT" "$settings"

  assert_contains "$output" "設定索引を 1 行しか読み取れなかった"
}

@test "スキーマの定義件数が閾値を下回ったら検査失敗にする" {
  default_docs
  SCHEMA_FILLER_PROPS=0 write_schema '{ "cleanupPeriodDays": { "type": "integer" } }'
  settings="$(default_settings)"

  run -2 "$SCRIPT" "$settings"

  assert_contains "$output" "スキーマのトップレベル定義を 2 件しか読み取れなかった"
}

@test "スキーマの取得先がJSONを返さなければ検査失敗にする" {
  # 取得先がHTMLのエラーページを返したときに空振りしないことを確かめる
  default_docs
  printf '<!doctype html><title>404</title>' > "$STUB_FIXTURES/schema.json"
  settings="$(default_settings)"

  run -2 "$SCRIPT" "$settings"

  assert_contains "$output" "スキーマのトップレベル定義を 0 件しか読み取れなかった"
}
