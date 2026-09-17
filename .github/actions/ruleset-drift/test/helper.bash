#!/usr/bin/env bash
#
# check-ruleset-drift.sh の bats テスト用ヘルパ。
#
# テストは実GitHubに触れない。外部へ出る gh は PATH の先頭に置いたスタブへ差し替え、
# 応答はフィクスチャで固定する。jq と diff は実物を使う。
#
# スタブの置き場（setup_stubs / only_commands）と判定（assert_*）は他のテストと同じものを使うため、
# scripts/lib/bats-helpers.bash に置いている。ここに残すのはこの action 固有のスタブと判定だけ。
load ../../../../scripts/lib/bats-helpers

# ---- スタブとフィクスチャ -------------------------------------------------------------------

# gh のスタブ。エンドポイントに応じてフィクスチャを標準出力へ流す。
# STUB_GH_FAIL_LIST / STUB_GH_FAIL_GET を立てると取得失敗を再現する。
install_gh_stub() {
  cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

# api 以降でフラグでもフラグの値でもない最初の引数がエンドポイント
shift
endpoint=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --method|--jq|--input|-f|-F|-H|--field|--raw-field) shift 2 ;;
    -*) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done

case "$endpoint" in
  */rulesets)
    [ -z "${STUB_GH_FAIL_LIST:-}" ] || exit 1
    cat "$STUB_FIXTURES/list.json"
    ;;
  */rulesets/*)
    [ -z "${STUB_GH_FAIL_GET:-}" ] || exit 1
    cat "$STUB_FIXTURES/detail.json"
    ;;
  *)
    printf 'gh stub: 想定外のエンドポイント: %s\n' "$endpoint" >&2
    exit 6
    ;;
esac
STUB
  chmod +x "$STUB_BIN/gh"
}

# ルールセット一覧の応答を作る。引数は "id<TAB>name" の並び。
write_ruleset_list() {
  local entry id name
  {
    printf '['
    local first=1
    for entry in "$@"; do
      IFS=$'\t' read -r id name <<<"$entry"
      [ "$first" -eq 1 ] || printf ','
      first=0
      jq -nc --argjson id "$id" --arg name "$name" '{id: $id, name: $name}'
    done
    printf ']'
  } > "$STUB_FIXTURES/list.json"
}

# ルールセット詳細の応答を作る。標準入力のJSONに、APIが必ず付ける読み取り専用の
# フィールド（id / source / _links など）を足したものを応答とする。
write_ruleset_detail() {
  jq '. + {
    id: 1,
    node_id: "RRS_abc",
    source: "kentayamada-dev/lab",
    source_type: "Repository",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
    current_user_can_bypass: "always",
    _links: { self: { href: "https://api.github.com/x" } }
  }' > "$STUB_FIXTURES/detail.json"
}

# 定義ファイルを書き、そのパスを出力する
write_ruleset_file() {
  local path="$BATS_TEST_TMPDIR/main.json"
  cat > "$path"
  printf '%s' "$path"
}
