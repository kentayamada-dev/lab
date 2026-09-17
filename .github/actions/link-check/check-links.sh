#!/usr/bin/env bash
#
# リポジトリ内のURLに到達できるか lychee で検査する。
#
#   usage: .github/actions/link-check/check-links.sh [ci.lychee.toml]
#
# 検査対象と除外は設定ファイル（既定は .github/ci.lychee.toml）に置き、
# ここではCI・手元のどちらでも変わらない引数だけを渡す。
# 検査対象は設定ファイルの位置ではなく実行ディレクトリ基準で決まるため、リポジトリ直下から実行する。
#
# github.com へのリクエストは、環境変数 GITHUB_TOKEN があれば lychee が自動で読んでAPI経由にする
# （引数で渡す必要はない）。未設定でも検査自体はでき、レート制限で落ちやすくなるだけ。
# https://github.com/lycheeverse/lychee#github-token
#
# 終了コード: 0 = リンク切れなし / 1 = リンク切れあり / 2 = 検査自体が実行できなかった
# 結果は Markdown で標準出力に書く（ワークフローがそのまま issue 本文に使う）。
#
set -euo pipefail

# 既定値は実行ディレクトリからの相対パスにせず、スクリプトの位置から辿る。
# 設定は ci.yml の --offline の検査とも共有するため .github/ 直下に移したが（そのファイルのコメント）、
# どこから起動しても対になる設定を読める性質は変えていない。
# ${1:-...} は引数が空文字のときも既定値を使う。action.yml は入力が未指定のとき空文字を渡すため、
# この挙動で既定の設定にフォールバックしている。
CONFIG_FILE="${1:-"$(dirname "$0")/../../ci.lychee.toml"}"

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

command -v lychee >/dev/null 2>&1 || die "lychee が見つからない"

[[ -f "${CONFIG_FILE}" ]] || die "${CONFIG_FILE} が存在しない"

# 作業ディレクトリは TMPDIR 配下に明示して作る（既定の一時領域に書けない実行環境があるため）。
# lychee のレポートは --output でファイルにしか書けないため、ここに書いてから標準出力へ流す。
work="$(mktemp -d "${TMPDIR:-/tmp}/link-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# lychee の終了コードは 0=全て成功 / 2=リンク切れあり / 1=入力や実行時の失敗 / 3=設定ファイルの誤り。
# リンク切れはこのスクリプトの 1 に、それ以外の失敗は 2 に写す。
# https://github.com/lycheeverse/lychee#exit-codes
#
# set -e の下でも終了コードを受け取れるよう、|| で拾う
status=0
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
