#!/usr/bin/env bash
#
# check-ruleset-drift.sh の bats テスト用ヘルパ。
#
# テストは実GitHubに触れない。外部へ出る gh は PATH の先頭に置いたスタブへ差し替え、
# 応答はフィクスチャで固定する。jq と diff は実物を使う。
#
# scripts/test/helper.bash と setup_stubs / only_commands / assert_* が重複している。
# この action は scripts/ から独立して動かしたいため、共有せずそれぞれに持たせている
# （.github/actions/settings-drift/test/helper.bash と同じ方針）。
#
# テストで使う `run -N` は 1.5.0 以降の構文。下の宣言が無いと旧版との互換のため警告 BW02 が出る。
# CI が導入する bats の版は .github/workflows/ci.yml の scripts-test ジョブに書いてある。
# https://bats-core.readthedocs.io/en/stable/warnings/BW02.html
bats_require_minimum_version 1.5.0

# スタブを置くディレクトリを PATH の先頭に差し込む。
# フィクスチャ（APIが返したことにするJSON）の置き場もここに作る。
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
