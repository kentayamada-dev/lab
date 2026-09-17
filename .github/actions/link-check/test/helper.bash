#!/usr/bin/env bash
#
# check-links.sh の bats テスト用ヘルパ。
#
# テストは実際のリンク検査をしない。外部へ出る lychee は PATH の先頭に置いたスタブへ差し替え、
# レポートと終了コードをテスト側から固定する。
#
# スタブの置き場（setup_stubs / only_commands）と判定（assert_*）は他のテストと同じものを使うため、
# scripts/lib/bats-helpers.bash に置いている。ここに残すのはこの action 固有のスタブと判定だけ。
load ../../../../scripts/lib/bats-helpers

# ---- スタブとフィクスチャ -------------------------------------------------------------------

# lychee のスタブ。--output で指定されたパスにフィクスチャのレポートを書き、
# STUB_LYCHEE_EXIT（既定 0）で終了する。渡された引数は args.txt に記録し、テストから照合する。
#
# 本物の lychee はリンク切れの有無にかかわらずレポートを書くため（0.24.2 で実測）、
# スタブも終了コードによらず書く。
install_lychee_stub() {
  cat > "$STUB_BIN/lychee" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

printf '%s\n' "$@" > "$STUB_FIXTURES/args.txt"

output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$output" ] || cat "$STUB_FIXTURES/report.md" > "$output"

exit "${STUB_LYCHEE_EXIT:-0}"
STUB
  chmod +x "$STUB_BIN/lychee"
}

# lychee が書いたことにするレポートを標準入力から作る
write_report() {
  cat > "$STUB_FIXTURES/report.md"
}

# 設定ファイルを書き、そのパスを出力する。中身はスタブが読まないので空でよいが、
# スクリプトの存在チェックを通すために実ファイルとして置く。
write_config() {
  local path="${1:-$BATS_TEST_TMPDIR/lychee.toml}"
  mkdir -p "$(dirname "$path")"
  printf 'extensions = ["md"]\n' > "$path"
  printf '%s' "$path"
}

# lychee のスタブが受け取った引数を1行ずつ出力する
lychee_args() {
  cat "$STUB_FIXTURES/args.txt"
}

# 指定した値が、lychee の引数の1つとしてそのまま渡されたかを判定する。
# 引数は1行に1つ記録されるため行単位で照合する（部分一致だと "." のような値が
# 他の引数の一部に紛れて通ってしまう）。
assert_arg() {
  local line
  while IFS= read -r line; do
    if [ "$line" = "$1" ]; then
      return 0
    fi
  done < "$STUB_FIXTURES/args.txt"

  printf '引数として渡されていない: %s\n--- 実際の引数 ---\n%s\n' "$1" "$(lychee_args)" >&2
  return 1
}
