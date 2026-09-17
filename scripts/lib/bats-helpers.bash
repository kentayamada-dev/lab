#!/usr/bin/env bash
# bats は各 @test を subshell で実行するため、テスト間で変数を引き継ぐ書き方が SC2030/SC2031 として、
# bats 本体（BATS_TEST_DIRNAME など）と load 先が設定する変数が SC2154 として指摘される。
# 期待値の文字列に含まれる $ は展開させたくないので SC2016 も、コマンドの失敗は run で受けるので
# SC2312 も外す。いずれも bats の書き方に由来するもので、コードの不備ではない。
# shellcheck disable=SC2030,SC2031,SC2016,SC2154,SC2312
#
# bats テスト共通のヘルパ。
#
# scripts/test と .github/actions/*/test の各 helper.bash から load して読む。
# テスト専用だが scripts/test/ ではなく scripts/lib/ に置いている。scripts/test/ は
# apply-repo-settings.sh のテストそのものの置き場で、そこに共通の道具を混ぜると
# 「.github/actions/* のテストが apply-repo-settings.sh のテストに依存している」ように見えるため。
# load のパスは .bats のあるディレクトリ基準で解決されるため、実行時のカレントディレクトリや
# bats に渡した引数の書き方（相対・絶対）に依存しない（bats 1.14.0 で実測）。
#
# ここに置くのは、検査対象が違っても同じ意味で使える道具だけ。
# gh・curl・lychee といった対象ごとのスタブとフィクスチャは、各 helper.bash に残している。
#
# テストで使う `run -N` は 1.5.0 以降の構文。下の宣言が無いと旧版との互換のため警告 BW02 が出る。
# CI が導入する bats の版は .github/workflows/ci.yml の scripts-test ジョブに書いてある。
# https://bats-core.readthedocs.io/en/stable/warnings/BW02.html
bats_require_minimum_version 1.5.0

# ---- スタブの置き場 ---------------------------------------------------------------------------

# スタブを置くディレクトリを PATH の先頭に差し込む。
# フィクスチャ（外部が返したことにするデータ）の置き場もここに作る。
setup_stubs() {
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  STUB_FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "${STUB_BIN}" "${STUB_FIXTURES}"
  PATH="${STUB_BIN}:${PATH}"
  export PATH STUB_BIN STUB_FIXTURES
}

# 指定したコマンドだけが見つかる PATH 用ディレクトリを作り、そのパスを出力する。
# 「前提のコマンドが無いときに、検査対象が前提チェックで落ちるか」の検証に使う。
#
# env と bash は常に含める。検査対象のスクリプトは #!/usr/bin/env bash で起動するため、
# これを外すとスクリプトが実行されず、前提チェックの結果ではなく 127 を見ることになる。
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

# 出力の照合には [[ ]] を使わない。
# bash 3.2 の set -e は [[ ]] の偽を検知せず、bats もテスト失敗として扱わないため、
# 偽の判定が黙って通り過ぎてしまう（テストが何も検証しない状態になる）。
# 関数の return 1 なら bats が失敗として拾う。

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
