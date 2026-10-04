#!/usr/bin/env bash
#
# composite action の run: に書いたシェルスクリプトを shellcheck で検査する。
#
#   usage: .github/scripts/check-action-shell.sh [action.yml ...]
#
# 引数を省略すると .github/actions/*/action.yml を対象にする。
#
# ci.yml の shellcheck は git 管理下の *.sh / *.bash / *.bats だけを、actionlint は引数なしだとワークフローだけを
# 検査する（action.yml を見ないことは未検証）。そのため composite action の run: はここで検査する。
# https://github.com/rhysd/actionlint/blob/main/docs/usage.md
#
# run: に ${{ }} を直接書くと shellcheck がパースに失敗してこの検査が落ちる。
# 値は env: 経由で渡すというリポジトリの方針（各 action.yml のコメント）と同じ向きなので、そのままにしている。
#
# 終了コード: 0 = 指摘なし / 1 = 指摘あり / 2 = 検査自体が実行できなかった
#
set -euo pipefail

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 2
}

for cmd in yq shellcheck; do
  command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} が見つからない"
done

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  # 対象が1つも無いまま成功すると、検査したつもりで何も見ていない状態になるため失敗にする
  files=(.github/actions/*/action.yml)
  [[ -f "${files[0]}" ]] || die ".github/actions/*/action.yml が1つも無い"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/action-shell.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# 抽出したシェルと元の場所の対応。shellcheck は一時ファイルのパスで指摘を出すので、
# その対応をあらかじめ表示しておく
mapping="${work}/mapping.txt"
: >"${mapping}"

extracted=0

for file in "${files[@]}"; do
  [[ -f "${file}" ]] || die "${file} が存在しない"

  using="$(yq -r '.runs.using // ""' "${file}")"
  if [[ "${using}" != "composite" ]]; then
    printf '%s: runs.using が composite ではないため対象外（%s）\n' "${file}" "${using:-未設定}"
    continue
  fi

  count="$(yq -r '.runs.steps | length' "${file}")"
  [[ "${count}" =~ ^[0-9]+$ ]] || die "${file} の runs.steps を読み取れない"

  for ((i = 0; i < count; i++)); do
    run="$(yq -r ".runs.steps[${i}].run // \"\"" "${file}")"
    [[ -n "${run}" ]] || continue

    shell="$(yq -r ".runs.steps[${i}].shell // \"\"" "${file}")"
    case "${shell}" in
      bash | sh) ;;
      "") die "${file} の steps[${i}] に shell が無い" ;;
      # shell: python などを足したらこのスクリプトを広げる。黙って検査対象から外さない
      *) die "${file} の steps[${i}] の shell '${shell}' は未対応" ;;
    esac

    dir="${work}/$(basename "$(dirname "${file}")")"
    mkdir -p "${dir}"
    snippet="${dir}/step-${i}.${shell}"

    # shebang は付けない。付けると行番号が run: の中身と1行ずれるため、方言は shellcheck の -s で伝える
    printf '%s\n' "${run}" >"${snippet}"
    printf '%s <- %s の runs.steps[%s]\n' "${snippet}" "${file}" "${i}" >>"${mapping}"

    extracted=$((extracted + 1))
  done
done

if [[ "${extracted}" -eq 0 ]]; then
  die "run: を持つステップが1つも見つからない"
fi

printf '検査対象:\n'
sed 's/^/  /' "${mapping}"
printf '\n'

status=0
while IFS= read -r line; do
  snippet="${line%% <- *}"
  shell="${snippet##*.}"

  # -o all は ci.yml の shellcheck に揃える。SC2154 を外すのは、run: が読む env: やランナーの環境変数
  # （GITHUB_OUTPUT など）が切り出したシェルからは見えず、正しい run: まで落ちるため。
  shellcheck -s "${shell}" -o all -e SC2154 "${snippet}" || status=1
done <"${mapping}"

if [[ "${status}" -eq 0 ]]; then
  printf 'composite action の run: に指摘はありません（%s件を検査）\n' "${extracted}"
fi

exit "${status}"
