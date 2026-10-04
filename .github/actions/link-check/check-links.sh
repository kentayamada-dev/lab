#!/usr/bin/env bash
# リポジトリ内のURLを lychee で検査する。対象パスは実行ディレクトリ基準なのでリポジトリ直下から実行する。
# 終了コード: 0 = リンク切れなし / 1 = あり / 2 = 検査不能。stdout の Markdown はワークフローが issue 本文に使う。
set -euo pipefail

# action.yml は未指定の入力を空文字で渡すため、:- で空文字も既定値にする。
# 既定値はスクリプトの位置から辿り、起動ディレクトリに依存させない。
CONFIG_FILE="${1:-"$(dirname "$0")/../../ci.lychee.toml"}"

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

command -v lychee >/dev/null 2>&1 || die "lychee が見つからない"

[[ -f "${CONFIG_FILE}" ]] || die "${CONFIG_FILE} が存在しない"

# 作業ディレクトリは TMPDIR 配下に明示して作る（既定の一時領域に書けない実行環境への対処。推測）。
# lychee のレポートは --output でファイルにしか書けないため、ここに書いてから標準出力へ流す。
work="$(mktemp -d "${TMPDIR:-/tmp}/link-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# lychee の 2（リンク切れ）は 1 に、それ以外の失敗（1=入力・実行時 / 3=設定誤り）は 2 に写す。
# https://github.com/lycheeverse/lychee#exit-codes
status=0
# GITHUB_TOKEN は lychee が環境変数から自動で読むため引数で渡さない（未設定でもレート制限に掛かりやすいだけ）
# https://github.com/lycheeverse/lychee#github-token
lychee --config "${CONFIG_FILE}" --no-progress --format markdown --output "${work}/report.md" . || status=$?

# レポートはリンク切れの有無にかかわらず書かれる（0.24.2 で実測）。
# リンク切れ以外で失敗したときの中身は信用できないため流さない。
case "${status}" in
  0) cat "${work}/report.md" ;;
  2)
    cat "${work}/report.md"
    exit 1
    ;;
  *) die "lychee がリンク切れ以外の理由で失敗した（終了コード ${status}）" ;;
esac
