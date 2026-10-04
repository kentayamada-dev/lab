#!/usr/bin/env bash
#
# PRのタイトルが CLAUDE.md の規約（Conventional Commits 形式・内容は日本語）に沿っているか検査する。
#
#   usage: .github/scripts/check-pr-title.sh "<title>"
#
# コミットではなくPRタイトルを検査する。.github/rulesets/main.json がマージを squash に限っており、
# GitHub の既定では squash の件名がPRタイトルになるため（コミットが1つのPRだけはそのコミットの件名）。
# editorconfig-checker-disable-next-line
# https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/configuring-commit-squashing-for-pull-requests
#
# 終了コード: 0 = 適合 / 1 = 不適合 / 2 = 検査自体が実行できなかった
#
set -euo pipefail

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

command -v grep >/dev/null 2>&1 || die "grep が見つからない"

[[ $# -eq 1 ]] || die "引数はPRのタイトル1つ。usage: $0 \"<title>\""

TITLE="$1"

# 指摘は1回でまとめて出す（1件直すたびにCIを回し直させない）。配列でなく文字列に溜めるのは、
# 手元 macOS の既定の bash 3.2 では set -u で空配列の ${arr[@]} が unbound variable になるため（4.4 で解消）。
# https://lists.gnu.org/archive/html/bug-bash/2019-05/msg00024.html
problems=""
note() { problems="${problems}  - $1
"; }

# Conventional Commits の型に、Angular 規約でよく使われる型を足した一覧。
# https://www.conventionalcommits.org/ja/v1.0.0/
TYPES="build chore ci docs feat fix perf refactor revert style test"

if [[ -z "${TITLE}" ]]; then
  note "タイトルが空"
else
  # 前後の空白は、squash 後のコミット件名にそのまま残る（未検証）ため不適合として扱う
  if [[ "${TITLE}" != "${TITLE#[[:space:]]}" ]]; then
    note "先頭に空白がある"
  fi
  if [[ "${TITLE}" != "${TITLE%[[:space:]]}" ]]; then
    note "末尾に空白がある"
  fi

  # "<type>(<scope>)!: <description>" を型・スコープ・説明に分解する。
  # 分解できない時点で形式が違うので、以降の個別の検査はしない
  if [[ ! "${TITLE}" =~ ^([a-zA-Z]+)(\(([^()]*)\))?(!)?:[[:space:]](.*)$ ]]; then
    note "Conventional Commits 形式ではない（例: fix(link-check): リンク切れを直す）"
  else
    type="${BASH_REMATCH[1]}"
    has_scope="${BASH_REMATCH[2]}"
    scope="${BASH_REMATCH[3]}"
    description="${BASH_REMATCH[5]}"

    case " ${TYPES} " in
      *" ${type} "*) ;;
      *) note "型 '${type}' は使えない（使えるのは: ${TYPES}）" ;;
    esac

    # "feat(): ..." のように括弧だけ書かれている状態を弾く。括弧ごと無ければスコープ無しで適合
    if [[ -n "${has_scope}" && -z "${scope}" ]]; then
      note "スコープの括弧が空"
    fi

    # コロンの後の空白は上の正規表現が1つだけ要求している。2つ以上なら説明が空白で始まる
    if [[ "${description}" != "${description#[[:space:]]}" ]]; then
      note "コロンの後の空白が2つ以上ある"
    fi

    if [[ -z "${description}" ]]; then
      note "説明が空"
    else
      case "${description}" in
        *. | *。) note "説明が句点・ピリオドで終わっている" ;;
        *) ;;
      esac

      # 「内容は日本語」は判定できないので、非ASCII文字を含むかで近似する。C ロケールでは
      # UTF-8 の多バイト文字のバイトが [:print:] に入らないため、非ASCII文字が1つでもあれば一致する。
      if ! printf '%s' "${description}" | LC_ALL=C grep -q '[^[:print:]]'; then
        note "説明に日本語が含まれていない（ASCII文字だけで書かれている）"
      fi
    fi
  fi
fi

if [[ -z "${problems}" ]]; then
  printf 'PRタイトルは規約に沿っています: %s\n' "${TITLE}"
  exit 0
fi

printf 'PRタイトルが規約に沿っていません: %s\n' "${TITLE}" >&2
printf '%s' "${problems}" >&2
printf '規約は CLAUDE.md の「リポジトリ運用」を参照\n' >&2
exit 1
