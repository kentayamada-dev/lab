# Renovate

[English](renovate.md) | **日本語**

[renovate.yml](../.github/workflows/renovate.yml) が [Renovate](https://docs.renovatebot.com/) を週 1 回（月曜 09:00 JST）実行し、依存に新しいバージョンが出ていれば更新 PR を作ります。[Docker Hub の renovate/renovate](https://hub.docker.com/r/renovate/renovate) をそのまま動かすセルフホスト方式で、Mend のホスト版 GitHub App は使いません。更新できる依存があるときは `Dependency updates are available` という issue が立ちます（[更新の一覧の issue](#更新の一覧の-issue)）。

実行のきっかけはワークフロー側の cron なので、関わる時刻はすべて UTC です（Renovate 自身の日時の判定も既定の UTC のままです）。将来 [renovate.json5](../.github/renovate.json5) に `schedule` を書くときは、時刻が UTC で解釈されないよう `timezone` を一緒に設定してください。

イメージはジョブの `container:` に指定してあり、ステップはその中で走ります（ラッパーの action は挟みません）。ジョブコンテナ特有の注意点 2 つは、ワークフロー側で対処してあります。1 つはコンテナを `--user root` で動かしていることです。イメージの非 root ユーザーでは runner が作るファイルに書けず、拾った内容を後続のジョブへ渡す `$GITHUB_OUTPUT` も、runner が `HOME` に向ける `/github/home` も書けません。もう 1 つはステップに `shell: bash` を指定していることです。ジョブコンテナでは `run:` の既定シェルが `sh` になります。

手動で走らせるには次を実行します（`--field log_level=debug` でログを詳細にできます）。

```bash
gh workflow run renovate.yml
```

## トークンの登録

**secret に `RENOVATE_TOKEN` を登録するまで動きません**（未登録ならジョブがその旨を出して落ちます）。発行するのは fine-grained PAT です。作成は [`SETTINGS_TOKEN` と同じ手順](drift-check.ja.md#settings_token-の作成)でブラウザから行い（Token name は `renovate (OWNER/REPO)` など）、Repository permissions は代わりに以下を与えます（表にない権限は不要です）。

| 権限 | 用途 |
| --- | --- |
| Contents: Read and write | ブランチの作成と push |
| Pull requests: Read and write | PR の作成・更新 |
| Workflows: Read and write | `.github/workflows/` 配下の更新 |
| Issues: Read and write | 設定に問題があるときの警告 issue の作成 |
| Dependabot alerts: Read-only | [セットアップ](../README.ja.md#セットアップ)で有効化した alerts の読み取り。既知の脆弱性がある依存には、次の実行時にまとめ PR とは別の単独の修正 PR が立ちます（Renovate の `vulnerabilityAlerts`。既定で有効）。権限が無いとき Renovate 自身は警告を出して飛ばすだけなので、実行は成功したままになります |

トークンを secret に登録し、実際に動かして確認します（更新があれば PR が作られます）。

```bash
gh secret set RENOVATE_TOKEN
gh workflow run renovate.yml
gh run watch
```

権限の過不足は実行するまで分かりません。足りなければ Actions のログに、どの権限が必要かが出ます。

**既定の `GITHUB_TOKEN` では代用できません。** ワークフローファイルを書き換える権限が無く（このリポジトリの更新対象はほぼワークフローです）、さらに `GITHUB_TOKEN` が作った PR では他のワークフローが起動しないため、必須チェックの `ci` が報告されずマージできない PR ができます。

## 実行が失敗したとき

**実行が失敗すると issue が立ちます**（[renovate.yml](../.github/workflows/renovate.yml) の `notify` ジョブ）。定期実行の失敗は見逃すと「更新 PR が来ない」だけの静かな状態になるためです。よくある原因は `RENOVATE_TOKEN` の失効・未登録・権限不足です（[トークンの登録](#トークンの登録)）。

issue は `Renovate runs are failing` というタイトルで `maintenance` ラベル付きで立ち（[ラベル](../README.ja.md#ラベル)）、本文に実行ログの URL と直し方が入ります。すでに同じ issue が open の間は何もせず（毎週同じ issue が積み上がらないように）、実行が成功すれば自動的に閉じます。

issue の作成と close はワークフローの `GITHUB_TOKEN`（`issues: write`）で行います。`RENOVATE_TOKEN` が失効していても通知が出るように、通知には使いません。

**schedule の自動停止はこの通知では拾えません。** [リポジトリの活動が 60 日間無いと GitHub が schedule を止めます](ci-jobs.ja.md#定期実行が止まるとき)が、実行自体が起きないため issue も立ちません。GitHub からの停止通知メールが唯一の手掛かりです（[renovate.yml](../.github/workflows/renovate.yml) のコメントを参照）。

## 依存を解決できなかったとき

**一部の依存の最新版を取得できなかったときは `Some dependencies cannot be resolved` という issue が立ちます**（[renovate.yml](../.github/workflows/renovate.yml) の `lookup` ジョブ）。この失敗は静かです。Renovate 自体は成功し、引けた依存の更新 PR は普通に作られ、引けなかった依存だけが「更新が来ない」状態になります。

issue は `maintenance` ラベル付きで立ち、本文に Renovate が出した警告と実行ログの URL が入ります。すでに同じ issue が open の間は本文を書き換え（引けなかった依存は実行ごとに変わるため）、すべて引けるようになれば自動的に閉じます。

よくある原因は `RENOVATE_TOKEN` の権限不足・失効（[トークンの登録](#トークンの登録)）と、配布元の一時的な不調です。後者なら次の実行で勝手に直ります。

仕組みは実行ログの拾い読みです。Renovate はこの警告をログに `Package lookup failures` と出すだけで、終了コードにも PR 本文にも出しません（`warnings` を外したためです。[本文](#本文)）。`renovate` ジョブがログを保存してこの行に続く警告を job の output に載せ、`lookup` ジョブが issue にします。判定はこの文字列だけに依存しているため、ログの書式が変わると警告の中身は取り出せなくなりますが、そのときも issue は立ちます（本文が「実行ログを見てください」になります）。

## 更新の一覧の issue

**更新できる依存があるときは `Dependency updates are available` という issue が立ちます**（[renovate.yml](../.github/workflows/renovate.yml) の `dashboard` ジョブ）。定期実行は週 1 回で、更新 PR が来たことに気づく入り口が別に必要なためです。

issue は `dependencies` ラベル付きで立ち（[ラベル](../README.ja.md#ラベル)）、本文に PR の一覧と実行ログの URL が入ります。すでに同じ issue が open の間は本文を書き換え、更新 PR が無くなれば自動的に閉じます。

つまり **issue 一覧に出ているときだけ、対応すべき更新があります**。この判定は実行時にしか行われないため、ワークフローは cron のほかに Renovate 自身の更新 PR のマージでも実行されます。全 PR をマージすればその実行で issue が閉じます。

一覧に入るのは、open な PR のうちブランチ名が `renovate/` で始まるものです（`branchPrefix` は既定のまま。`dependencies` ラベルは人でも付けられるので目印にしていません）。issue の操作はワークフローの `GITHUB_TOKEN` で行い、`RENOVATE_TOKEN` は使いません。実行が失敗したときはこのジョブは走らず、一覧は前回のまま残ります。

### 標準の Dependency Dashboard を使わない理由

Renovate には更新状況を issue にまとめる [Dependency Dashboard](https://docs.renovatebot.com/configuration-options/#dependencydashboard) がありますが、`dependencyDashboard: false` で切っています。体裁を他の自動 issue に揃えられないためです（設定で変えられるのはタイトルと本文の前後だけです）。

代わりに 2 つ失います。標準のダッシュボードが必要になったら、`dependencyDashboard: false` を消して `dashboard` ジョブを外せば元に戻ります。

| 失うもの | 代わりの手段 |
| --- | --- |
| チェックボックスによる操作（保留中の PR を今すぐ作る / rebase・retry / 手動実行） | 保留は `prConcurrentLimit: 0` と `prHourlyLimit: 0` により起きません。rebase は PR 画面の Update branch、再実行は `gh workflow run renovate.yml` |
| Detected Dependencies（更新対象として拾った依存の一覧） | `gh workflow run renovate.yml --field log_level=debug` の実行ログ |

## PR の文面

**更新 PR のタイトルと本文は自前で書いています**（[renovate.json5](../.github/renovate.json5)）。Renovate が生成する既定の文面のままでは、他の自動 issue と体裁が揃わないためです。

### タイトル

文面をまるごと `commitMessageTopic` に持たせ、`commitMessageAction` と `commitMessageExtra` は空にしてあります。Renovate はタイトルを `接頭辞 + action + topic + extra` の順に連結するため、文面を分けて持たせると言い回しを制御しにくいからです。

| 更新の種類 | タイトルの例 |
| --- | --- |
| まとめた更新（`non-major` のグループ） | `chore(deps): update non-major dependencies` |
| major | `chore(deps): update actions/checkout to v8` |
| ダイジェストのみ | `chore(deps): update renovate/renovate digest to e49d149` |
| バージョンの固定（`pinDigests: true` の初回など） | `chore(deps): pin dependency versions` |
| 置き換え（`replacements:all` が拾ったとき） | `chore(deps): replace old with new` |

`chore(deps):` の接頭辞は `semanticCommits: 'enabled'` が付けます（`config:recommended` に含まれるプリセットにより、アプリ本体の依存では `fix(deps):` になります）。接頭辞が付く形は変えていないので、CI の [`pr-title`](../README.ja.md#pr-タイトルの書式) は通ります。

`packageRules` には `groupSlug` を明示しています。グループ名の言い回しに関係なくブランチ名を固定するためです。グループ名はブランチ名にも使われ（`renovate/non-major`）、ここが崩れると[更新の一覧の issue](#更新の一覧の-issue) の絞り込み（`renovate/` で始まるブランチ）にも響きます。

### 本文

`prBodyTemplate` を `{{{header}}}{{{table}}}{{{footer}}}` にして、Renovate が生成する部分のうち更新の表だけを残し、それ以外を外しました。表の前後の文面は `prHeader`（この PR をどうするか、`{{#if isReplacement}}` で出し分ける置き換えの PR にだけ出る注記）と `prFooter`（遅れた PR の追いつかせ方、閉じたらどうなるか、Renovate が作った PR であること、設定とこの文書の場所）に書いたものだけになります。

外したものは次の 5 つです。戻すときは `prBodyTemplate` に書き足すだけです。

| 外したもの | 何だったか | 代わり |
| --- | --- | --- |
| `notes` | rebase の案内などの注記 | 必要なものを `prFooter` に書く |
| `warnings` | 設定の警告と「一部の依存を解決できなかった」の通知 | 専用の issue（[依存を解決できなかったとき](#依存を解決できなかったとき)） |
| `configDescription` | schedule / automerge / rebase / ignore の説明 | `prFooter` の注記 |
| `controls` | rebase・retry のチェックボックス | PR 画面の Update branch |
| `changelogs` | Release Notes の折りたたみ | 表のパッケージ名のリンク先で読む |

設定そのものの警告は、Renovate 自身が立てる警告 issue（`RENOVATE_TOKEN` の `issues` 権限で作られます）と、PR の時点で落ちる CI の [`renovate-config`](#設定の検証) で拾えます。

`changelogs` を外したので、リリースノートの取得も止めています（`fetchChangeLogs: 'off'`）。表示しないものを PR のたびに取りに行かないためです。`{{{changelogs}}}` を戻すときは、この行も一緒に戻してください（`'pr'` が既定です）。

### 表

更新の一覧の表は Renovate の `table` で、列を `prBodyColumns` と `prBodyDefinitions` で調整しています。`table` は直前に `This PR contains the following updates:` という 1 文を必ず付け、そこだけを消す手段はありません。以前はこの 1 文を避けるために `prHeader` の中で表を自前で組んでいましたが、その重複排除は `upgrades` の並び順に依存していました。`table` は並び順によらず同じ更新の出現を 1 行にまとめるため、`table` を使い、決まった 1 文は受け入れることにしました。

```text
| Package | Update | Change |
| --- | --- | --- |
| [actions/checkout](https://github.com/actions/checkout) | digest | `a1b2c3d` → `3d3c42e` |
| [jdx/mise](https://github.com/jdx/mise) | patch | `2026.8.8` → `2026.9.1` |
```

- `Update` は `updateType` のうち pin 系の 2 値だけを平易な語に置き換えます（`pin` → `pin version`、`pinDigest` → `pin digest`）。それ以外の値（`major` / `minor` / `patch` / `digest` など）はもともと平易な語なのでそのまま出します。
- Renovate の既定の表にある `Type` と `Pending` の列は落としました。`Type`（`depType`）は値がマネージャ側の識別子で、それだけ見てもほとんど意味がないためです。`Pending` は更新を遅らせるオプション（`minimumReleaseAge` など）を使うときにだけ値が入り、この設定では使っていないためです。
- `Change` は更新前が空のとき（バージョンの固定など）に更新後だけを出します。

**文面の間違いは[設定の検証](#設定の検証)では捕まりません。** validator が見るのはキーと値の書式で、テンプレートを展開した結果までは見ないためです。変えたときは `gh workflow run renovate.yml` で実際に PR を作って確認してください。

## PR と issue に付くラベル

更新 PR には `dependencies` が付きます（[renovate.json5](../.github/renovate.json5) の `labels`）。[更新の一覧の issue](#更新の一覧の-issue) にも同じラベルを付けます。ラベルを誰が作り、変えるときに何を合わせて直すかは[ラベル](../README.ja.md#ラベル)にあります。

セルフホストでは PR の作成者が `RENOVATE_TOKEN` の持ち主（多くの場合あなた自身）になり、ホスト版のような `author:app/renovate` では絞れないため、このラベルが唯一の目印です。

## コミットの author

Renovate が作るコミットの author は、[renovate.yml](../.github/workflows/renovate.yml) の `RENOVATE_GIT_AUTHOR` で明示しています（既定は `github-actions[bot]`）。fine-grained PAT ではトークン所有者のメールアドレスを読めず、Renovate 側の自動判定が効かないためです。

変えたい場合はリポジトリ変数を `Name <email>` の形式で設定します（未設定なら既定値が使われます）。

```bash
gh variable set RENOVATE_GIT_AUTHOR --body 'Renovate Bot <bot@example.com>'
```

## 設定の検証

[renovate.json5](../.github/renovate.json5) は [ci.yml](../.github/workflows/ci.yml) の `renovate-config` ジョブが PR ごとに検査します。Renovate に同梱されている `renovate-config-validator` を、[renovate.yml](../.github/workflows/renovate.yml) と同じイメージをジョブコンテナにして走らせています。

設定のミスは他の検査では捕まらず、CI は緑のまま「更新 PR が来ない」という静かな失敗になります。このジョブはそれを PR の時点で落とします。`--strict` を付けているので、廃止された設定などの警告でも落ちます。ただし「意図した依存を拾えているか」は検査しません。バージョンの書き方を変えたときは、詳細ログ（`gh workflow run renovate.yml --field log_level=debug`）で別途確認してください。

実装上の注意点:

- コンテナは `--user root` で動かしています。理由は [renovate.yml](../.github/workflows/renovate.yml) と同じで、イメージの非 root ユーザーでは runner が持つものに書けないためです。こちらで落ちるのは `actions/checkout` で、作業ディレクトリにファイルを作れません。
- validator にファイル名を渡していません。渡すと「bot 側の全体設定」として検査するモードになり、リポジトリ設定には書けないオプション（`token` など）を通してしまいます。代わりに、設定ファイルを別の名前に変えたときに検査対象 0 件のまま緑にならないよう、ジョブ側で存在確認を先に行っています。

手元で走らせるには、CI と同じイメージを使います（タグは最新で構いません。CI 側はダイジェストまで固定してあり、更新は Renovate 自身が提案します）。

```bash
docker run --rm -v "$PWD:/repo:ro" -w /repo \
  --entrypoint renovate-config-validator \
  renovate/renovate --strict
```

## このリポジトリに合わせてある設定

[renovate.json5](../.github/renovate.json5) の既定値から変えてある点です。どれを外しても Renovate は動きますが、手作業が増えるかこの構成の意図から外れます。

| 設定 | 理由 | 外すと |
| --- | --- | --- |
| `semanticCommits: 'enabled'` | PR タイトルを `chore(deps): ...` にして [`pr-title`](../README.ja.md#pr-タイトルの書式) を通す | 既定の `auto`（履歴からの自動判定）になり、判定が外れると `pr-title` が落ちてマージできない |
| `rebaseWhen: 'behind-base-branch'` | マージ前の最新化が必須のため、base が進んだら追随させる | base が進んだ PR の最新化が手作業（Update branch）になる |
| `prHourlyLimit: 0` | 実行が週 1 回なので、1 時間あたり 2 本の既定上限で持ち越さない | 3 本目以降が次週の実行まで持ち越される |
| `prConcurrentLimit: 0` | 更新を必ず PR にして、[更新の一覧の issue](#更新の一覧の-issue) を完全な一覧にする | open が 10 本を超えると以降が保留され、その分が一覧に出ない |
| `dependencyDashboard: false` | 標準のダッシュボードを止め、一覧を自前の issue にする（[理由](#標準の-dependency-dashboard-を使わない理由)） | `Dependency Dashboard` issue が立ち、自前の issue と二重になる |
| `pinDigests: true` | タグは差し替え可能なので、ダイジェストまで固定する（[ダイジェストの固定](#ダイジェストの固定)） | タグ指定だけになり、中身の差し替えを追えなくなる |
| `extends` の `helpers:pinGitHubActionDigestsToSemver` | 固定した SHA に添えるコメントを `# v7.0.1` のような厳密なバージョンに保つ（[ダイジェストの固定](#ダイジェストの固定)） | `# v7` のような可動する major タグが書かれ、上流がタグを付け替えるとコメントが固定した commit を指さなくなり、[`zizmor`](ci-jobs.ja.md#zizmor) が `ref-version-mismatch` として報告する |
| `packageRules` の `non-major` | major 以外は 1 本の PR にまとめる | 更新ごとに PR が立ち、本数が増える |
| `commitMessage*` / `pr*` の文面 | 更新 PR のタイトルと本文を自前で書く（[PR の文面](#pr-の文面)） | 自動生成の既定の文面に戻り、自動 issue と体裁が揃わない |
| `fetchChangeLogs: 'off'` | リリースノートを PR に出さないので取得しない（[本文](#本文)） | 表示しないリリースノートを実行ごとに取りに行く |

## 何が更新対象になるか

| 書き方 | 拾う仕組み |
| --- | --- |
| `uses: actions/checkout@<commit sha> # v7.0.1` | github-actions マネージャ（自動） |
| `uses: <owner>/<repo>/.github/workflows/<name>.yml@<commit sha> # v2.5.1` | 同上（自動） |
| `uses: docker://<イメージ>:<タグ>@sha256:...` | 同上（自動） |
| ジョブの `container:` — `image: <イメージ>:<タグ>@sha256:...` | 同上（自動） |
| [mise.toml](../mise.toml) の `[tools]` | mise マネージャ（自動） |
| `jdx/mise-action` の `version` 入力 | github-actions マネージャ（自動） |

すべて Renovate が標準で読む書き方に揃えてあり、`customManagers` は使っていません。Docker イメージは `uses: docker://` かジョブの `container:` で指定してください。`run:` の中に直接書いたイメージ名は誰も見てくれません。

アプリコードを入れた後の `package.json` や `go.mod` なども、プリセット（`config:recommended`）が自動で検出するので設定の追加は不要です。

## ダイジェストの固定

`pinDigests: true` により、action と Docker イメージはタグに加えてダイジェストまで固定されます。タグは後から中身を差し替えられるため、タグだけの指定では CI が何を実行しているか確定しません。固定しておけば、中身が変わるのは Renovate の PR をマージしたときだけになります。

| 対象 | 更新 |
| --- | --- |
| action、再利用可能ワークフロー | Renovate が SHA と末尾コメントの両方を維持 |
| `docker://` のイメージ、ジョブの `container:` | Renovate がタグとダイジェストの両方を更新 |

ジョブを追加するときも同じ形（[何が更新対象になるか](#何が更新対象になるか)）で書いてください。最初の 1 回もダイジェストを手で付ける必要はありません（Renovate が固定します）。手で付けるときは次のように取得します。

```bash
gh api repos/actions/checkout/commits/v7.0.1 --jq .sha    # action の commit SHA
docker buildx imagetools inspect <イメージ>:<タグ> --format '{{.Manifest.Digest}}'
```

[mise.toml](../mise.toml) に書くツールにダイジェストはありません。代わりに mise が取得物をチェックサム・署名で検証します（[ツールの導入と検証](ci-jobs.ja.md#ツールの導入と検証)）。

## 自動マージ

初期状態では PR は自動マージされません。`ci` が通れば十分と判断できる更新（パッチなど）は、[renovate.json5](../.github/renovate.json5) の `packageRules` に `automerge: true` を足すと、リポジトリの auto-merge 機能を使ってそのままマージされます。
