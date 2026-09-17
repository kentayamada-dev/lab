#!/usr/bin/env bash
#
# composite action の run: に書いたシェルスクリプトを shellcheck で検査する。
#
#   usage: scripts/check-action-shell.sh [action.yml ...]
#
# 引数を省略すると .github/actions/*/action.yml を対象にする。
#
# ci.yml の shellcheck は git ls-files で集めた *.sh / *.bash / *.bats を検査するため、
# action.yml の run: に直接書いたシェルは対象外になる。actionlint も run: の中身を
# 検査に回すが、対象は .github/workflows のワークフローだけで action.yml は見ない
# （引数なしの actionlint がワークフローを探すことは ci.yml のコメントのとおり。
# action.yml を対象にしないことは公式ドキュメントで明言を確認できていない＝未確認）。
# その結果、条件分岐や終了コードの処理を含む run: が誰にも検査されていなかったため、ここで埋める。
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

  # -o all は ci.yml の shellcheck と同じ（optional チェックを全て有効にする）。
  # SC2154（未代入の変数を参照）だけは外す。run: が読む変数はステップの env: と
  # ランナーが与える環境変数（GITHUB_OUTPUT など）で、どちらも切り出したシェルからは見えないため。
  shellcheck -s "${shell}" -o all -e SC2154 "${snippet}" || status=1
done <"${mapping}"

if [[ "${status}" -eq 0 ]]; then
  printf 'composite action の run: に指摘はありません（%s件を検査）\n' "${extracted}"
fi

exit "${status}"
