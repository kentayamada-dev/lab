#!/usr/bin/env bash
# bats の書き方由来の誤検出を外す: SC2030/SC2031（@test ごとの subshell）、SC2154（bats・load 先が設定する変数）、
# SC2016（期待値の $ を展開しない）、SC2312（失敗は run で受ける）
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# bats テスト共通のヘルパ。
#
# テスト専用だが scripts/lib/ に置く。scripts/test/ は apply-repo-settings.sh のテストの置き場で、
# そこに混ぜると他のテストが apply-repo-settings.sh のテストに依存しているように見えるため。
#
# load の相対パスは .bats のあるディレクトリ基準で解決され、実行時のカレントディレクトリに依存しない。
# https://bats-core.readthedocs.io/en/stable/writing-tests.html
#
# ここに置くのは、検査対象が違っても同じ意味で使える道具だけ。
# gh・curl・lychee といった対象ごとのスタブとフィクスチャは、各 helper.bash に残している。
#
# テストで使う `run -N` は 1.5.0 以降の構文。下の宣言が無いと旧版との互換のため警告 BW02 が出る。
# CI が導入する bats の版は .github/workflows/ci.yml の scripts-test ジョブに書いてある。
# https://bats-core.readthedocs.io/en/stable/warnings/BW02.html
bats_require_minimum_version 1.5.0

# ---- スタブの置き場 ---------------------------------------------------------------------------

setup_stubs() {
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  STUB_FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "${STUB_BIN}" "${STUB_FIXTURES}"
  PATH="${STUB_BIN}:${PATH}"
  export PATH STUB_BIN STUB_FIXTURES
}

# 指定したコマンドだけが見える PATH 用ディレクトリを作る。env と bash は常に含める。
# 検査対象は #!/usr/bin/env bash で起動するため、外すと前提チェックではなく 127 で落ちる。
only_commands() {
  local dir="${BATS_TEST_TMPDIR}/only-bin"
  rm -rf "${dir}"
  mkdir -p "${dir}"

  local cmd src
  for cmd in env bash "$@"; do
    if [[ -x "${STUB_BIN}/${cmd}" ]]; then
      cp "${STUB_BIN}/${cmd}" "${dir}/${cmd}"
    else
      src="$(command -v "${cmd}")" || return 1
      ln -s "${src}" "${dir}/${cmd}"
    fi
  done

  printf '%s' "${dir}"
}

# ---- 判定 -----------------------------------------------------------------------------------

# 照合は関数の return 1 か `[[ ]] || false` で失敗させる。bash 4.1 未満（macOS の 3.2）では
# テストの途中の [[ ]] 単独が偽でも止まらず、照合が黙って素通りするため。
# [ ] は shellcheck の SC2292（-o all）に掛かるので使わない。
# https://bats-core.readthedocs.io/en/stable/gotchas.html

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) ;;
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
    *) ;;
  esac
  return 0
}

assert_prefix() {
  case "$1" in
    "$2"*) return 0 ;;
    *) ;;
  esac
  printf 'この文字列で始まっていない: %s\n--- 実際 ---\n%s\n' "$2" "$1" >&2
  return 1
}
