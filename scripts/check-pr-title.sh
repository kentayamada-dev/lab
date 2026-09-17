#!/usr/bin/env bash
#
# PRのタイトルが CLAUDE.md の規約（Conventional Commits 形式・内容は日本語）に沿っているか検査する。
#
#   usage: scripts/check-pr-title.sh "<title>"
#
# 検査するのはコミットメッセージではなくPRのタイトル。
# .github/rulesets/main.json の pull_request ルールがマージ方式を squash だけに限っているため、
# main に残るコミットの件名になるのはPRのタイトルであって、ブランチ上の個々のコミットではない。
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

# 指摘はまとめて出す。1件直すたびにCIを回し直さずに済むようにするため。
# 配列ではなく文字列に溜めているのは、空配列への ${arr[@]} が bash 3.2 の set -u で
# unbound variable になるため（CI は bash 5 だが、手元の macOS の既定は 3.2）。
problems=""
note() { problems="${problems}  - $1
"; }

# Conventional Commits が定める型に、Angular の規約でよく使われるものを足した一覧。
# このリポジトリの過去のコミットは feat / fix / docs / ci / chore を使っている（git log で確認）。
# https://www.conventionalcommits.org/ja/v1.0.0/
TYPES="build chore ci docs feat fix perf refactor revert style test"

if [[ -z "${TITLE}" ]]; then
  note "タイトルが空"
else
  # 前後の空白は、squash 後のコミット件名にそのまま残るため不適合として扱う
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

      # CLAUDE.md の「内容は日本語で書く」を機械的に確かめる。
      # 「日本語かどうか」は判定できないので、非ASCII文字を含むことで代用している（近似であることを明示する）。
      # C ロケールでは UTF-8 の多バイト文字を構成するバイトが [:print:] に含まれないため、
      # 非ASCII文字が1つでもあれば一致する。
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
