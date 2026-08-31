# repo-baseline

[English](README.md) | **日本語**

[![ci](https://github.com/kentayamada-dev/repo-baseline/actions/workflows/ci.yml/badge.svg)](https://github.com/kentayamada-dev/repo-baseline/actions/workflows/ci.yml) [![OpenSSF Scorecard](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.scorecard.dev%2Fprojects%2Fgithub.com%2Fkentayamada-dev%2Frepo-baseline&query=%24.score&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/kentayamada-dev/repo-baseline)

リポジトリ運用の土台（ブランチ保護と、拡張前提の CI ワークフロー）を収めたテンプレートリポジトリ。

**アプリケーションコードは含まれていません。** アプリの実装はこのテンプレートから作ったリポジトリで進めます（[アプリコードを追加したら](docs/ci-jobs.ja.md#アプリコードを追加したら)）。**public リポジトリ専用です**（private では ruleset や Code scanning の利用条件が異なるため）。

## 読み方

最初に読むのは次の 2 つだけです。

- [セットアップ](#セットアップ) — テンプレートからリポジトリを作った直後の一度きりの作業
- [開発フロー](#開発フロー) — 普段の PR の回し方

残りは、必要になったときに引くリファレンスです。

- [収録内容](#収録内容) — 入っているファイルの一覧
- [設定のずれの検査](docs/drift-check.ja.md#設定のずれの検査) — リポジトリ設定が定義からずれていないかの毎日の検査
- [リリース](#リリース) — immutable releases による制約
- [CI の検査ジョブ](docs/ci-jobs.ja.md#ci-の検査ジョブ) — 検査が落ちたとき・ジョブを足すときに該当の節を引く
- [Renovate](docs/renovate.ja.md#renovate) — 依存更新の自動化
- [トラブルシューティング](docs/troubleshooting.ja.md#トラブルシューティング) — 症状から引く

## 収録内容

| パス | 内容 |
| --- | --- |
| [.github/rulesets/main.json](.github/rulesets/main.json) | main のブランチ保護（GitHub Repository Ruleset）の定義 |
| [scripts/sync-repo-config.sh](scripts/sync-repo-config.sh) | 上記 ruleset とリポジトリ設定をまとめて適用・検査するスクリプト |
| [scripts/tests/](scripts/tests) | 上記スクリプトのテスト。CI で実行される（[script-tests](docs/ci-jobs.ja.md#script-tests)） |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | CI。必須チェックとなるゲートジョブ `ci` と検査ジョブ（[一覧](docs/ci-jobs.ja.md#ci-の検査ジョブ)） |
| [.github/workflows/osv-scanner.yml](.github/workflows/osv-scanner.yml) | 依存パッケージの既知の脆弱性の定期検査（毎日 / [osv-scanner](docs/ci-jobs.ja.md#osv-scanner)） |
| [.github/workflows/scorecard.yml](.github/workflows/scorecard.yml) | OpenSSF Scorecard によるリポジトリのセキュリティ体制の定期採点（毎週 / [Scorecard](docs/ci-jobs.ja.md#scorecard)） |
| [.github/workflows/repo-settings.yml](.github/workflows/repo-settings.yml) | リポジトリ設定と ruleset のずれの定期検査（毎日 / [設定のずれの検査](docs/drift-check.ja.md#設定のずれの検査)） |
| [.github/workflows/link-check.yml](.github/workflows/link-check.yml) | ドキュメントの外部リンクの定期検査（毎日 / [外部リンクの定期検査](docs/ci-jobs.ja.md#外部リンクの定期検査)） |
| [.github/workflows/renovate.yml](.github/workflows/renovate.yml) | Renovate の実行（[更新の一覧の issue](docs/renovate.ja.md#更新の一覧の-issue)） |
| [.github/scripts/](.github/scripts) | 上記の定期実行ワークフローが、落ちた検査を issue として報告し、取り下げるために呼ぶスクリプト |
| [.github/scripts/tests/](.github/scripts/tests) | 上記スクリプトのテスト。CI で実行される（[script-tests](docs/ci-jobs.ja.md#script-tests)） |
| [.github/renovate.json5](.github/renovate.json5) | Renovate の設定 |
| [.github/pull_request_template.md](.github/pull_request_template.md) | PR の本文テンプレート |
| [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE) | issue のテンプレート（Bug report / Task） |
| [CLAUDE.md](CLAUDE.md) | Claude Code が読み込む指示書。自分のリポジトリの指示書で置き換える |
| [.claude/settings.json](.claude/settings.json) | Claude Code の設定。下のフックスクリプトをここで配線する |
| [.claude/hooks/](.claude/hooks) | CLAUDE.md の規則を強制するフックスクリプト |
| [.claude/skills/docs-check/SKILL.md](.claude/skills/docs-check/SKILL.md) | 重複・ドキュメント陳腐化チェックの手順（`/docs-check` で実行） |
| [.claude/tests/](.claude/tests) | フックスクリプトと、それを呼び出す設定のテスト。CI で実行される（[hooks](docs/ci-jobs.ja.md#hooks)） |
| [mise.toml](mise.toml) | CI で使う検査ツールのバージョンと、同じ検査を手元で回すタスク（`mise run check`） |
| [.markdownlint-cli2.jsonc](.markdownlint-cli2.jsonc) | Markdown の書式検査 markdownlint-cli2 の設定 |
| [.typos.toml](.typos.toml) | 誤字検査 typos の設定 |
| [.editorconfig](.editorconfig) | エディタ側の書式設定（インデント / 改行 / 文字コード） |
| [.gitattributes](.gitattributes) | 改行コードを LF に固定する git の設定 |
| [.gitignore](.gitignore) | git の追跡から外すもの（typos の除外にも効きます） |
| [docs/drift-check.ja.md](docs/drift-check.ja.md) | リファレンス: 設定のずれの検査と `SETTINGS_TOKEN` |
| [docs/ci-jobs.ja.md](docs/ci-jobs.ja.md) | リファレンス: CI の検査ジョブ |
| [docs/renovate.ja.md](docs/renovate.ja.md) | リファレンス: Renovate |
| [docs/troubleshooting.ja.md](docs/troubleshooting.ja.md) | リファレンス: トラブルシューティング |
| [SECURITY.md](SECURITY.md) | 脆弱性の報告先と対象の範囲 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 貢献の手引き（GitHub が issue / PR の作成画面に表示します） |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | 行動規範（Contributor Covenant v2.1 ベース） |
| [LICENSE](LICENSE) | MIT ライセンス（[ライセンス](#ライセンス)） |
| `*.ja.md` | 日本語版。[README.ja.md](README.ja.md) と `docs/` の 4 ファイルにあり、拡張子を除いた同名の `.md` が英語版です |

**正となるのは英語版です**（[Bilingual documentation](CONTRIBUTING.md#bilingual-documentation)）。ツールが出力・照合するものは英語のみなので、`DRIFT` や `UNKNOWN` などのマーカーはこの文書でも英語のまま引用しています。

## セットアップ

テンプレートから自分のリポジトリを作った直後に行う、一度きりの作業です。

1. **セットアップスクリプトを実行する**（このすぐ下）
2. **スクリプトが書き換えた [config.yml](.github/ISSUE_TEMPLATE/config.yml) をコミットする**（[issue のテンプレート](#issue-のテンプレート)）
3. **secret `SETTINGS_TOKEN` を登録する**（[作成手順](docs/drift-check.ja.md#settings_token-の作成)） — 未登録だと[設定のずれの検査](docs/drift-check.ja.md#設定のずれの検査)が `UNKNOWN` で落ちて issue が立ちます
4. **[Renovate](docs/renovate.ja.md#renovate) を使うなら secret `RENOVATE_TOKEN` を登録する**（[作成手順](docs/renovate.ja.md#トークンの登録)） — 未登録だと月曜の定期実行が落ちて issue が立ちます

前提: [gh](https://cli.github.com/) と [jq](https://jqlang.github.io/jq/)、および `gh auth login` 済みであること。

```bash
./scripts/sync-repo-config.sh
```

これで以下が有効になります。送信内容だけ確認したい場合は `--dry-run` を付けてください。他のオプションと環境変数は `--help` にあります。

- main のブランチ保護（[ブランチ保護の内容](#ブランチ保護の内容)）
- auto-merge とマージ後のブランチ自動削除
- base に遅れた PR での「Update branch」の提案（マージ前の最新化が必須のため）
- マージ方式を squash のみに限定（merge commit / rebase は無効）
- squash 時のコミットタイトルを常に PR タイトルにする（[PR タイトルの書式](#pr-タイトルの書式)）
- Discussions・Issues・Projects の有効化（GitHub の既定値に依存させず明示します）
- issue と PR のラベルを無いものだけ作成（[ラベル](#ラベル)）
- Wiki の無効化（main の保護も CI も掛からず、テンプレートからも複製されないため使いません）
- immutable releases（[リリース](#リリース)）
- 脆弱性の非公開報告（public issue ではなく非公開の窓口で受け取る）
- Dependabot alerts（依存に既知の脆弱性が公表された時点で GitHub が通知します。毎日の [osv-scanner](docs/ci-jobs.ja.md#osv-scanner) と違い、60 日間更新が無く scheduled workflow が止まった後も動き続けます）
- secret scanning の push protection（資格情報を含む push を、入る前に拒否します。[gitleaks](docs/ci-jobs.ja.md#gitleaks) は既に履歴に入ったものを見つけるだけです）
- Actions の `GITHUB_TOKEN` の既定権限を read に固定し、`GITHUB_TOKEN` による PR の作成・承認を禁止（各ワークフローが `permissions` を書き忘れたときの上限を既定値に依存させません）

> スクリプトは public 以外のリポジトリを拒否します。

既存のリポジトリに適用する場合、main に旧来の branch protection（classic）が残っていると ruleset と併用され、挙動が追いにくくなります。スクリプトは警告を出すだけで続行するので（`--dry-run` と `--check` ではこの確認を行いません）、残っているなら消してください。

```bash
gh api --method DELETE repos/OWNER/REPO/branches/main/protection
```

### ブランチ保護の内容

| 項目 | 設定 |
| --- | --- |
| main への直接 push | 禁止 |
| PR | 必須 |
| 承認 | 0 人（セルフマージ可） |
| レビューコメント | すべて解決しないとマージ不可 |
| CI (`ci`) | 必須（GitHub Actions が報告したものだけを有効とする） |
| Code scanning のアラート | 重大度を問わず、アラートが 1 件でもあればマージを止める（[CodeQL](docs/ci-jobs.ja.md#codeql)） |
| マージ前の最新化 | 必須（base が進んだら Update branch） |
| マージ方式 | squash のみ |
| 履歴 | 一直線を強制（merge commit 不可） |
| main の削除 / force-push | 禁止 |

ruleset は [main.json](.github/rulesets/main.json) の 1 つで、対象は `main` だけです。main 以外のブランチには何も掛からず、管理者にも例外（bypass）を与えていません。設定を変えるときは JSON を編集してスクリプトを再実行してください。

コミットの署名は必須にしていません。ルールが見るのはマージ時に GitHub が作って署名する squash コミットだけでなく PR に含まれるすべてのコミットなので、必須にすると未署名のコミットで作られる Renovate の更新 PR がマージできなくなるためです。

承認 0 人は、管理者が 1 人であることを前提にした設定です。2 人以上で開発するようになったら JSON の `pull_request` ルールを変えてください。`required_approving_review_count` を 1 に、`dismiss_stale_reviews_on_push` と `require_last_push_approval` を `true` にします。変更箇所の担当者のレビューを必須にするなら、`CODEOWNERS` を置いて `require_code_owner_review` も有効にします。

## 開発フロー

main は保護されており直接 push できません。すべての変更を PR 経由で入れます。

```bash
git switch -c feat/xxx
# 変更してコミット
git push -u origin HEAD
gh pr create
gh pr merge --auto --squash
```

承認は 0 人でよいのでセルフマージできますが、CI が通らない限りマージはされません。`gh pr merge --auto --squash` を付けておくと、CI が通った時点で自動的にマージされます（マージ方式は squash のみ有効ですが、非対話の実行では方式を明示しないとエラーになります）。

CI の検査は push する前に手元で再現できます。[mise](https://mise.jdx.dev/) が入っていれば、下のコマンドが手元のチェックアウトで動く検査すべてを、CI と同じコマンド・同じツールバージョンで実行します（[検査を手元で再現する](docs/ci-jobs.ja.md#検査を手元で再現する)）。

```bash
mise run check
```

main が進んだ PR は、最新化するまでマージできません。PR 画面の「Update branch」を押すか、`git merge origin/main` して push してください。CI が再実行され、通ればマージできます。

### PR タイトルの書式

PR タイトルは [Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/) 形式に強制しています。

```text
<type>(<scope>)!: <説明>
```

| 要素 | 必須 | 内容 |
| --- | --- | --- |
| `type` | 必須 | `feat` `fix` `docs` `refactor` `test` `build` `ci` `perf` `chore` `revert` のいずれか |
| `(scope)` | 任意 | 変更箇所。`fix(cli):` のように書く |
| `!` | 任意 | 後方互換を壊す変更に付ける。`feat!:` |
| `説明` | 必須 | 1 文字以上 |

```text
feat: ユーザー検索エンドポイントを追加
fix(cli): config.yml のコミットが必要なことを目立たせる
feat!: 設定ファイルの形式を TOML に変更
```

タイトルを縛るのは、squash 時のコミットタイトルを常に PR タイトルにする設定（`squash_merge_commit_title=PR_TITLE`）により、**main に残るコミットのタイトルが PR タイトル**になるためです。縛るのはタイトルだけで、本文は検査しません。ローカルで積んだコミットメッセージは squash コミットの本文に連結されて main に残ります。

検証は CI の `pr-title` ジョブが行い、必須チェック `ci` に含まれるため回避できません。落ちた場合は PR タイトルを直せば自動で再検証されます（再 push は不要）。type を増減する場合は [ci.yml](.github/workflows/ci.yml) の `PATTERN` と上の表、[.claude/settings.json](.claude/settings.json) の prompt フックの type 一覧を合わせて直してください。各コピー（ci.yml 内の失敗メッセージも含む）が `PATTERN` と一致することは [hooks](docs/ci-jobs.ja.md#hooks) ジョブが検査するため、直し漏れは CI で落ちます。

再検証が効くのは、`pull_request` の `types` に `edited` を足してあるためです。既定のままだとタイトルを直してもワークフローが起動せず、落ちたままになります。代償としてタイトルの編集ごとに [CodeQL](docs/ci-jobs.ja.md#codeql) まで回りますが、`codeql` だけ `if` でスキップすると、`skipped` を成功として扱うゲートジョブ `ci` が前回の失敗を緑で上書きしてしまうため、そうしていません。

GitHub の既定（`COMMIT_OR_PR_TITLE`）はコミットが 1 つだけの PR だとそのコミットのタイトルを使うため、`PR_TITLE` を外すと `pr-title` で検証したタイトルが main に載らないことがあります。このずれは `pr-title` では検出できず（見ているのは PR タイトルで、実際に main に載るものではないため）、[設定のずれの検査](docs/drift-check.ja.md#設定のずれの検査)が拾います。手元で確認するには次を実行します。

```bash
gh api repos/OWNER/REPO --jq .squash_merge_commit_title   # PR_TITLE であること
./scripts/sync-repo-config.sh --check              # 他の設定と ruleset もまとめて確認
```

### 書式の統一

インデント・改行コード・行末空白を、強制力の違う 3 段構えで揃えています。

| 仕組み | 強制力 | 役割 |
| --- | --- | --- |
| [.editorconfig](.editorconfig) | なし（ヒント） | 入力時点で揃える。プラグイン未導入のエディタでは黙って無視される |
| [.gitattributes](.gitattributes) | git が正規化 | 改行コードを LF に固定。エディタ設定や OS に依存しない |
| `ci` の `format` ジョブ | 必須チェック | 違反を PR で弾く（editorconfig-checker と shfmt の 2 つ） |

`format` ジョブは [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) で `.editorconfig` の全項目を検査します。設定の情報源は `.editorconfig` 1 つだけで、CI 側に検査項目を書き写してはいません。

タブの検査（`indent_style`）には実害の防止という意味もあります。YAML は仕様上インデントにタブを使えないため、エディタの既定がタブの環境で `ci.yml` を編集するとワークフローが壊れます。

同じジョブで [shfmt](https://github.com/mvdan/sh) がシェルスクリプトの整形を検査します。

```bash
git ls-files -z '*.sh' '*.bash' \
  | xargs -0 -r shfmt -d -i 2 -ci
```

| 指定 | 理由 |
| --- | --- |
| `-d` | 整形前後の差分を出し、差分があれば終了コードを 1 にする（`-w` のように書き換えない） |
| `-i 2` | インデントは半角 2 |
| `-ci` | `case` の中身を字下げする（このリポジトリの既存の書き方） |

shfmt の注意点:

- **フラグを 1 つでも渡すと shfmt は `.editorconfig` を読みません。** シェルスクリプトの書式はこの指定だけで決まります。redirect の前後に空白を入れる `-sr` などは既存の書き方に合わせて付けていません。変えるならこのフラグに足します。
- **`;` で区切って 1 行に並べた複数の文は、行に分けて書き直されます。** `cmd || { echo "..." >&2; exit 1; }` のような 1 行ガードも展開されます。無効にするフラグは無いので、リポジトリ内のシェルスクリプトはこの形に揃えてあります。

editorconfig-checker と shfmt は、他の検査ツールと同じく本体を mise で入れて実行しています（[ツールの導入と検証](docs/ci-jobs.ja.md#ツールの導入と検証)、バージョンは [mise.toml](mise.toml)）。**editorconfig-checker のコマンド名は `ec` です**（[mise.toml](mise.toml) に書く `editorconfig-checker` は [aqua](https://aquaproj.github.io/) レジストリでのパッケージ名で、バイナリの名前とは違います）。

#### 2 つの例外

シェルスクリプトを `indent_size` の検査から外しています（[.editorconfig](.editorconfig) 参照）。heredoc の中は CLI に出力する表示用テキストで、幅を 2 の倍数に揃える意味がありませんが、editorconfig-checker は heredoc を区別できないためです。外した分は同じ `format` ジョブの shfmt が見ます（shfmt は heredoc の中身を整形の対象にしないので、除外を作らずに検査できます）。シェルスクリプトのインデントの情報源は、`.editorconfig` ではなく shfmt のフラグです。

`*.md` を行末空白の検査から外しているのは、Markdown では行末の半角スペース 2 つが強制改行を意味するためです。一律に削除すると表示が変わります。外した分は markdownlint-cli2 の `MD009` が見ます（[markdownlint-cli2](docs/ci-jobs.ja.md#markdownlint-cli2)）。

### issue のテンプレート

[.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE) に 2 種類あります。どちらも YAML の issue フォーム形式です。ラベルは自動で付きます（[ラベル](#ラベル)）。

| テンプレート | 用途 | 自動で付くラベル |
| --- | --- | --- |
| [Bug report](.github/ISSUE_TEMPLATE/bug_report.yml)（バグ報告） | 動作がおかしい、エラーが出る | `bug` |
| [Task](.github/ISSUE_TEMPLATE/task.yml)（作業項目） | 追加したい機能、やるべき作業 | `enhancement` |

**どちらにも当てはまらないものは Discussions へ。** issue 作成画面に「Ask in Discussions」というリンクを出してあります。話が固まったら、Discussion ページの「Create issue from discussion」で issue に変換できます。

白紙の issue は [config.yml](.github/ISSUE_TEMPLATE/config.yml) の `blank_issues_enabled: false` で禁止してあり、必ずどちらかのテンプレートを通ります。ただしこれは issue 作成画面から白紙の選択肢を消すだけの設定で、API 経由（`gh issue create` にタイトルと本文を渡した場合も含む）は素通りします。

**セキュリティ上の問題は issue に書かないでください。** 脆弱性の非公開報告を有効にしているので、Security タブから非公開で報告できます（[SECURITY.md](SECURITY.md)）。

`config.yml` の `contact_links` には絶対 URL しか書けないため、テンプレートには `https://github.com/OWNER/REPO/discussions/new/choose` と置いてあり、[セットアップ](#セットアップ)のスクリプトが実際のリポジトリ名へ書き換えます。**書き換わった `config.yml` はコミットが必要です。** 手で直しても構いません。その場合スクリプトは何もしません。

書式は `ci` の `issue-forms` ジョブが [check-jsonschema](https://github.com/python-jsonschema/check-jsonschema) で検査します。`type` の綴り違いや `validations` の位置違いは GitHub 側では実行時にしか分からず、**issue の作成画面からテンプレートが消える**という形で現れるためです。当てるスキーマは [SchemaStore](https://www.schemastore.org/) のものがツール本体に同梱されていて、GitHub 側の変更への追随はツールのバージョン更新に含まれます。

ジョブは次を実行します。`config.yml` はフォームではなくフォームの選択画面の設定で、スキーマが別なので分けて検査します。拡張子は GitHub が `.yml` と `.yaml` のどちらも受け付けるため、両方を対象にしています。

```bash
git ls-files -z '.github/ISSUE_TEMPLATE/*.yml' '.github/ISSUE_TEMPLATE/*.yaml' \
  ':!:.github/ISSUE_TEMPLATE/config.yml' ':!:.github/ISSUE_TEMPLATE/config.yaml' \
  | xargs -0 -r check-jsonschema --builtin-schema vendor.github-issue-forms
git ls-files -z '.github/ISSUE_TEMPLATE/config.yml' '.github/ISSUE_TEMPLATE/config.yaml' \
  | xargs -0 -r check-jsonschema --builtin-schema vendor.github-issue-config
```

テンプレートを 1 つも置かない選択は正当なので、対象が 0 件のときは検査せず通します。裏返しに、`.github/ISSUE_TEMPLATE/` から置き場所を動かすと検査対象が無いまま緑になります。

### ラベル

[セットアップ](#セットアップ)のスクリプトが作るラベルは 4 つです。手で付けるものはありません。

| ラベル | 付くもの | 付ける場所 |
| --- | --- | --- |
| `bug` | Bug report issue | [bug_report.yml](.github/ISSUE_TEMPLATE/bug_report.yml) の `labels` |
| `enhancement` | Task issue | [task.yml](.github/ISSUE_TEMPLATE/task.yml) の `labels` |
| `dependencies` | Renovate の更新 PR / 更新の一覧 issue | [renovate.json5](.github/renovate.json5) の `labels` / [renovate.yml](.github/workflows/renovate.yml) の `--label dependencies` |
| `maintenance` | 定期検査の失敗で立つ通知 issue | 各ワークフローの `--label maintenance` |

`maintenance` は、人が報告したバグと自動検査が見つけた保守作業を一覧で分けるためのラベルです。「誰が作ったか」ではなく内容の種類を表します（通知 issue は `author:app/github-actions` で絞れます）。

通知 issue へのラベル付けは [upsert-issue.sh](.github/scripts/upsert-issue.sh) が行います。作成時ではなく作成後に付ける理由と、ラベルが消えていても警告で済む理由は、スクリプトの `--help` に書いてあります。

ラベルが消されていないかは[設定のずれの検査](docs/drift-check.ja.md#設定のずれの検査)が毎日確かめます（issue テンプレートの側は、存在しないラベルを GitHub が黙って無視するため、消えても気づけません）。テンプレートや `renovate.json5` の `labels` を変えるときは、スクリプトの `LABELS_EXPECTED` も合わせて直してください（検査が見るのはスクリプト側の定義だけです）。

## リリース

immutable releases を有効にしているため、有効化後に公開したリリースは後から変更できません。アセットもタグも固定され、修正は新しいバージョンとして出し直します（詳細は [GitHub のドキュメント](https://docs.github.com/ja/repositories/releasing-projects-on-github/about-releases)）。

「同じタグの中身が入れ替わらない」ことが保証されるため、サプライチェーン対策になります。無効化するには `gh api --method DELETE repos/OWNER/REPO/immutable-releases` を実行します。

## ライセンス

MIT（[LICENSE](LICENSE)）。テンプレートから作ったリポジトリは、このファイルを差し替えてかまいません。
