#!/usr/bin/env bash
#
# 定義ファイルと GitHub 上のルールセットが一致しているか検査する。
#
#   usage: .github/actions/ruleset-drift/check-ruleset-drift.sh [ruleset.json]
#
# 対象リポジトリは GITHUB_REPOSITORY から、認証は GH_TOKEN（gh が読む）から取る。
#
# 終了コード: 0 = 一致 / 1 = 差分あり / 2 = 検査自体が実行できなかった
# 結果は unified diff で標準出力に書く（ワークフローがそのまま issue 本文に使う）。
#
set -euo pipefail

RULESET_FILE="${1:-.github/rulesets/main.json}"

die() { printf 'エラー: %s\n' "$*" >&2; exit 2; }

for cmd in gh jq diff; do
  command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} が見つからない"
done

[[ -n "${GITHUB_REPOSITORY:-}" ]] || die "GITHUB_REPOSITORY が未設定"

# GITHUB_TOKEN には bypass_actors を読む権限を与えられないため、専用のトークンを必須にする。
# 未設定のまま動かしても gh は公開リポジトリなら応答を返してしまい、差分の誤検知になる。
# 発行と登録の手順は README の「ruleset-drift の事前準備」。
[[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN が未設定。secret RULESET_READ_TOKEN を設定する（手順は README）"

[[ -f "${RULESET_FILE}" ]] || die "${RULESET_FILE} が存在しない"
jq empty "${RULESET_FILE}" 2>/dev/null || die "${RULESET_FILE} が JSON として不正"

# 作業ディレクトリは TMPDIR 配下に明示して作る（既定の一時領域に書けない実行環境があるため）
work="$(mktemp -d "${TMPDIR:-/tmp}/ruleset-drift.XXXXXX")"
trap 'rm -rf "$work"' EXIT

name="$(jq -r '.name // empty' "${RULESET_FILE}")"
[[ -n "${name}" ]] || die "${RULESET_FILE} に name がない"

# ルールセットIDはUIで再作成すると変わるので、ファイルの name で検索する
gh api "repos/${GITHUB_REPOSITORY}/rulesets" > "${work}/list.json" || die "ルールセット一覧を取得できない"
id="$(jq -r --arg n "${name}" 'map(select(.name == $n)) | .[0].id // empty' "${work}/list.json")"

if [[ -z "${id}" ]]; then
  printf 'GitHub上に name=%s のルールセットが存在しません\n' "${name}"
  exit 1
fi

gh api "repos/${GITHUB_REPOSITORY}/rulesets/${id}" > "${work}/raw.json" || die "ルールセット(id=${id})を取得できない"

# bypass_actors は「ルールセットへの write 権限がある要求元にだけ返す」仕様で、権限が無いと
# キーごとレスポンスから消える。APIはエラーを返さないため、そのまま比較すると権限不足が
# 「差分あり」として通知され続ける（#11）。drift ではなく検査自体の失敗として切り分ける。
# https://docs.github.com/en/rest/repos/rules
jq -e 'has("bypass_actors")' "${work}/raw.json" > /dev/null \
  || die "APIレスポンスに bypass_actors がない。GH_TOKEN の権限不足または期限切れの可能性がある"

# APIレスポンスには id / source / _links など定義ファイルに含めない読み取り専用の
# フィールドが混ざるため、ファイルと同じキーだけを取り出してから比較する
jq -S '{name, target, enforcement, bypass_actors, conditions, rules}' "${work}/raw.json" > "${work}/remote.json"
jq -S . "${RULESET_FILE}" > "${work}/local.json"

# diff -u に --label を渡すとヘッダに更新日時が入らないため、内容が同じなら出力も同じになる
# （呼び出し側は本文のハッシュで「前回と同じ差分か」を判定している）
status=0
diff -u --label "${RULESET_FILE}" --label "github:${name}" \
  "${work}/local.json" "${work}/remote.json" > "${work}/diff.txt" || status=$?

case "${status}" in
  0) echo "一致しています" ;;
  1) cat "${work}/diff.txt"; exit 1 ;;
  *) die "diff を実行できなかった" ;;
esac
