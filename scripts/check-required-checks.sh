#!/usr/bin/env bash
#
# ルールセットが必須にしているステータスチェックの名前と、CI のジョブ名が一致しているか検査する。
#
#   usage: scripts/check-required-checks.sh [ruleset.json] [workflow.yml]
#
# ステータスチェックの名前はジョブIDではなくジョブの name になる（.github/workflows/ci.yml のコメント）。
# そのため ci.yml の name を変えてルールセットを直し忘れると、要求された名前のチェックが永久に現れず、
# PR がマージできなくなる。逆に ci.yml へジョブを足してルールセットに書き忘れると、
# そのジョブは落ちてもマージを止めない。どちらも CI は緑のまま進むので、ここで突き合わせる。
#
# .github/workflows/ruleset-drift.yml が見ているのは「定義ファイルと GitHub 上のルールセット」で、
# こちらが見るのは「定義ファイルとワークフロー」。同じファイルを起点にした別方向の検査になる。
#
# 終了コード: 0 = 一致 / 1 = 不一致 / 2 = 検査自体が実行できなかった
#
set -euo pipefail

RULESET_FILE="${1:-.github/rulesets/main.json}"
WORKFLOW_FILE="${2:-.github/workflows/ci.yml}"

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

for cmd in jq yq; do
  command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} が見つからない"
done

[[ -f "${RULESET_FILE}" ]] || die "${RULESET_FILE} が存在しない"
[[ -f "${WORKFLOW_FILE}" ]] || die "${WORKFLOW_FILE} が存在しない"
jq empty "${RULESET_FILE}" 2>/dev/null || die "${RULESET_FILE} が JSON として不正"

work="$(mktemp -d "${TMPDIR:-/tmp}/required-checks.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# ルールセットが必須にしているチェックの名前。
# required_status_checks ルール自体が無ければ空になり、下の比較でジョブ側が余分として報告される
jq -r '
  .rules[]?
  | select(.type == "required_status_checks")
  | .parameters.required_status_checks[]?
  | .context
' "${RULESET_FILE}" | LC_ALL=C sort -u >"${work}/required.txt"

# ワークフローのジョブが報告するチェックの名前。
# name があればそれ、無ければジョブID がそのまま名前になる。
# strategy.matrix を使うジョブは "name (値)" という形に展開されるが、このリポジトリには無いので扱わない
yq -r '.jobs | to_entries[] | .value.name // .key' "${WORKFLOW_FILE}" |
  LC_ALL=C sort -u >"${work}/jobs.txt"

# ジョブが1つも取れないのは、ワークフローの構造が変わったか yq の読み違い。
# 「全ジョブが必須から漏れている」と報告するより、検査自体の失敗として止める
[[ -s "${work}/jobs.txt" ]] || die "${WORKFLOW_FILE} からジョブを読み取れない"

LC_ALL=C comm -23 "${work}/required.txt" "${work}/jobs.txt" >"${work}/missing.txt"
LC_ALL=C comm -13 "${work}/required.txt" "${work}/jobs.txt" >"${work}/extra.txt"

if [[ ! -s "${work}/missing.txt" && ! -s "${work}/extra.txt" ]]; then
  printf '必須チェックとジョブ名は一致しています\n'
  exit 0
fi

if [[ -s "${work}/missing.txt" ]]; then
  printf '%s が必須にしているが %s に同名のジョブが無い:\n' "${RULESET_FILE}" "${WORKFLOW_FILE}" >&2
  sed 's/^/  - /' "${work}/missing.txt" >&2
  printf 'この名前のチェックは永久に報告されないため、PR がマージできなくなる\n' >&2
fi

if [[ -s "${work}/extra.txt" ]]; then
  printf '%s にあるが %s が必須にしていないジョブ:\n' "${WORKFLOW_FILE}" "${RULESET_FILE}" >&2
  sed 's/^/  - /' "${work}/extra.txt" >&2
  printf 'このジョブは失敗してもマージを止めない\n' >&2
fi

printf 'どちらかを直したあと scripts/apply-repo-settings.sh を再実行する（README 参照）\n' >&2
exit 1
