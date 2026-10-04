#!/usr/bin/env bash
# bats の書き方に由来する指摘を外す（各コードの理由は scripts/lib/bats-helpers.bash 冒頭）
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# check-links.sh のテスト用スタブ。リンク検査をしないよう lychee を差し替え、レポートと終了コードを固定する。
load ../../../../scripts/lib/bats-helpers

# ---- スタブとフィクスチャ -------------------------------------------------------------------

# --output 先にフィクスチャのレポートを書き STUB_LYCHEE_EXIT（既定0）で終わる。引数は args.txt に記録する。
# 本物の lychee と同じく、終了コードによらずレポートを書く（0.24.2 で実測）。
install_lychee_stub() {
  cat >"${STUB_BIN}/lychee" <<'STUB'
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
  chmod +x "${STUB_BIN}/lychee"
}

# lychee が書いたことにするレポートを標準入力から作る
write_report() {
  cat >"${STUB_FIXTURES}/report.md"
}

# 設定ファイルを書き、そのパスを出力する。中身はスタブが読まないので空でよいが、
# スクリプトの存在チェックを通すために実ファイルとして置く。
write_config() {
  local path="${1:-${BATS_TEST_TMPDIR}/lychee.toml}"
  mkdir -p "$(dirname "${path}")"
  printf 'extensions = ["md"]\n' >"${path}"
  printf '%s' "${path}"
}

# lychee のスタブが受け取った引数を1行ずつ出力する
lychee_args() {
  cat "${STUB_FIXTURES}/args.txt"
}

# 引数は1行1つで記録されるので行単位で完全一致させる（部分一致だと "." が他の引数に紛れて通る）
assert_arg() {
  local line
  while IFS= read -r line; do
    if [[ "${line}" = "$1" ]]; then
      return 0
    fi
  done <"${STUB_FIXTURES}/args.txt"

  printf '引数として渡されていない: %s\n--- 実際の引数 ---\n%s\n' "$1" "$(lychee_args)" >&2
  return 1
}
