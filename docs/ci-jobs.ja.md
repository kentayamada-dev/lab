# CI の検査ジョブ

[English](ci-jobs.md) | **日本語**

[ci.yml](../.github/workflows/ci.yml) に初期状態で入っている検査ジョブの一覧です。検査が落ちたときや設定を変えるときに、該当する節だけ読んでください。

| ジョブ | 見るもの | 解説 |
| --- | --- | --- |
| `codeql` | コードの静的解析（初期状態はワークフローファイルのみ） | [CodeQL](#codeql) |
| `pr-title` | PR タイトルが Conventional Commits 形式か | [PR タイトルの書式](../README.ja.md#pr-タイトルの書式) |
| `format` | インデント・改行コード・行末空白 | [書式の統一](../README.ja.md#書式の統一) |
| `actionlint` | ワークフロー定義の構文・式の誤り | [actionlint](#actionlint) |
| `shellcheck` | シェルスクリプトの、黙って誤動作する書き方 | [shellcheck](#shellcheck) |
| `hadolint` | Dockerfile の再現性・サイズ・権限で損をする書き方 | [hadolint](#hadolint) |
| `typos` | 誤字 | [typos](#typos) |
| `lychee` | Markdown のリンク切れ・アンカー切れ | [lychee](#lychee) |
| `markdownlint` | Markdown の書式 | [markdownlint-cli2](#markdownlint-cli2) |
| `ghalint` | ワークフローのセキュリティ（書き方の作法） | [ghalint](#ghalint) |
| `zizmor` | ワークフローのセキュリティ（攻撃経路） | [zizmor](#zizmor) |
| `gitleaks` | コミット履歴に混ざった秘密情報 | [gitleaks](#gitleaks) |
| `setup-script` | 一度だけ実行するスクリプトの実行確認 | [setup-script](#setup-script) |
| `hooks` | Claude Code のフックが CLAUDE.md どおりに許可・拒否するか | [hooks](#hooks) |
| `script-tests` | ワークフローが呼ぶスクリプトの判断が変わっていないか | [script-tests](#script-tests) |
| `issue-forms` | issue フォームがスキーマに沿っているか | [issue のテンプレート](../README.ja.md#issue-のテンプレート) |
| `renovate-config` | Renovate 設定の検証 | [設定の検証](renovate.ja.md#設定の検証) |
| `osv-scanner-diff` | PR が新たに持ち込む依存の脆弱性 | [osv-scanner](#osv-scanner) |

コードを変えなくても結果が変わる検査（[設定のずれの検査](drift-check.ja.md#設定のずれの検査)、[osv-scanner](#osv-scanner) の全体検査、[外部リンクの検査](#外部リンクの定期検査)、[Scorecard](#scorecard)）は、`ci` に入れると無関係な PR まで止めるため、別ワークフローの定期実行にしてあります。

## CI にジョブを追加する

[ci.yml](../.github/workflows/ci.yml) の `ci` ジョブは、他の全ジョブの結果を集約するゲートジョブです。必須ステータスチェックはこの `ci` 1 つだけなので、**ジョブを追加したら `ci` の `needs` に足すだけ**で、ブランチ保護側の設定変更は不要です。

```yaml
jobs:
  lint:   # 追加したジョブ
    ...
  test:   # 追加したジョブ
    ...
  ci:
    needs: [lint, test]   # ここに足す
```

`needs` への足し忘れは `ci` ジョブ自身が検査し（ci.yml のジョブ一覧と `needs` を突き合わせます）、足し忘れた PR 自体を落とします。なぜ危険かはエラーメッセージが説明します。

なお `ci` は `skipped` のジョブを成功として扱います。ジョブ側の `if` でスキップしても PR は止まりませんが、裏返しに、`if` でのスキップは前回の失敗を緑で上書きし得ます。

注意点:

- ジョブには `permissions` と `timeout-minutes` を必ず書き、`actions/checkout` には `persist-credentials: false` を付けてください。[`ghalint`](#ghalint) が強制します。例外は再利用可能ワークフローを `uses` で呼ぶジョブで、そこには `timeout-minutes` を書けません（[`osv-scanner-diff`](#osv-scanner) が該当します）。
- 可能なら、ジョブのコマンドは [mise.toml](../mise.toml) の `check:<ジョブ名>` タスクに置き、ジョブはそれを呼ぶ形にしてください。検査を手元で再現できる状態が保たれます（[検査を手元で再現する](#検査を手元で再現する)）。
- ワークフロー全体に `paths` フィルタを付けないこと。対象外の PR で `ci` が報告されず、必須チェック待ちのままマージ不能になります。絞るならジョブ側の `if` を使います。
- `ci` ジョブの名前を変えるときは、[main.json](../.github/rulesets/main.json) の `context` も合わせて変更してください。
- **CI を GitHub Actions 以外から報告するようにしないこと。** `context` と一緒に `integration_id`（GitHub Actions の App ID）を指定してあり、他の App やトークンが報告した同名のチェックは無視されます。外部 CI へ移行する場合はこの値も移行先の App ID に変えないと、必須チェック待ちで止まります（[確認方法](troubleshooting.ja.md#トラブルシューティング)）。
- CI は 1 つの変更につき 2 回走ります（PR 上と、マージ後の main）。base を最新化するたびに PR 側はさらに走ります。実行時間の長いジョブを追加するときはこのコストを見込んでください。main 側の run は、CodeQL がアラートの基準として使う「デフォルトブランチの解析結果」を作ります。
- 同じ PR への連続 push では古い実行を打ち切りますが、**main への push では打ち切りません**（`concurrency` の `cancel-in-progress` を `github.event_name == 'pull_request'` にしてあります）。連続マージで前のコミットの実行がキャンセルされると、そのコミットに `cancelled` が残り、[CodeQL](#codeql) の解析も欠けるためです。

## アプリコードを追加したら

lint / test / build のジョブを `ci` の `needs` に足す（[CI にジョブを追加する](#ci-にジョブを追加する)）のにあわせて、「アプリコードがまだ無い」前提の次の 3 つを見直してください。

- [CodeQL](#codeql) の `matrix.language` に言語を足す
- [CodeQL](#codeql) のアラートの閾値を見直す。どちらも `all` なので note 級の品質アラートでもマージが止まります。対象がワークフローファイルだけなら許容できますが、実際の言語を解析すると煩わしくなります
- [osv-scanner](#osv-scanner) の `--allow-no-lockfiles` を外す（[検査対象が無いときは黙って通ります](#検査対象が無いときは黙って通ります)）

lockfile（`package-lock.json` や `go.mod` など）は、置いた時点で osv-scanner と [Renovate](renovate.ja.md#renovate) が設定なしで検出します。

## ツールの導入と検証

検査に使う CLI ツールは、本体を [mise](https://mise.jdx.dev/) で入れて実行しています。公式の action や Docker イメージがあるツールでも使いません。バージョンの情報源を [mise.toml](../mise.toml) 1 つにまとめるためです。更新は [Renovate](renovate.ja.md#renovate) が PR で提案します（mise マネージャが標準で対応）。

例外は 3 つあり、理由は各節にあります。[osv-scanner](#osv-scanner) は公式の再利用可能ワークフローを呼び、[renovate-config](renovate.ja.md#設定の検証) は Renovate のイメージに同梱の validator を使い、[markdownlint-cli2](#markdownlint-cli2) は公式の action を使います。

取得元は mise が [aqua](https://aquaproj.github.io/) のレジストリから解決し、落としたものは配布元が用意しているチェックサムや署名で検証してから使います。[ダイジェストの固定](renovate.ja.md#ダイジェストの固定)と同じ役割で、差し替えや改竄があればインストールの時点で落ちます。検証の強さは配布元次第です。

| ツール | 検証 |
| --- | --- |
| ghalint | SLSA provenance（リリースワークフローが署名した証明）とチェックサム |
| actionlint / hadolint / zizmor | GitHub Artifact Attestations（リリースに付く署名付きの証明）とチェックサム |
| editorconfig-checker / gitleaks | チェックサムのみ（リリースに provenance も attestations も付かない） |
| shellcheck / shfmt / typos | なし（リリースにチェックサムも署名も付かない。固定できるのはバージョンだけ） |
| bats | なし（タグから GitHub が生成するソースアーカイブを導入する。リリースにアセットが無く、バージョン以外に固定するものが無い） |
| lychee | なし（リリースに `.sha256` は付くが、aqua レジストリ側に設定が無く検証が走らない） |
| check-jsonschema | PyPI が返すファイルのハッシュのみ（aqua を経由しない。下記） |

`check-jsonschema` は Python 製で aqua に無いため、[mise.toml](../mise.toml) では `"pipx:check-jsonschema"` とバックエンドを明示し、PyPI から入れています。PyPI は公開済みファイルの差し替えを許さないため、バージョンを固定すれば中身は確定します。実体は runner のイメージに入っている Python と pipx で、`mise.toml` に `python` を足す必要はありません。ただし **check-jsonschema は Python 3.10 以上を要求します**（macOS 標準の Python は 3.9）。古い Python しか無い環境では、このツールだけが入りません。

mise 本体のバージョンは [mise-action](https://github.com/jdx/mise-action) の `version` 入力で固定しています（Renovate がこの入力を標準で見ます）。action 自体は他と同じく commit SHA 固定です。`mise.lock` は置いていません（理由は [mise.toml](../mise.toml) のコメントを参照）。

キャッシュの書き込みは `cache_save: ${{ github.event_name == 'push' }}` として main への push のときだけに限っています。キャッシュはブランチスコープで、PR ブランチに保存したものはマージ後は誰も使わないまま 7 日間残るためです。main のキャッシュは全ブランチから読めるので、[mise.toml](../mise.toml) を変えない PR ではヒットし、速度は落ちません。

### 検査を手元で再現する

検査ジョブが実行するコマンドは、ジョブと同名のタスクとして [mise.toml](../mise.toml) に一度だけ定義してあり、各ジョブの `run:` は `mise run --skip-tools check:<ジョブ名>` でそれを呼びます（このフラグは mise が mise.toml の全ツールを入れようとするのを止めます。ジョブが必要とする分は mise-action のステップが入れ終わっています）。同じタスクで CI を手元で再現できます。前提は [mise](https://mise.jdx.dev/) だけです。

```bash
mise run check              # 手元のチェックアウトで動く検査すべて
mise run check:shellcheck   # 1 つのジョブの検査だけ
```

初回の実行で固定版のツールが入ります。コマンドもバージョンも両側が同じファイルを読むため、結果は CI と一致します。注意は 2 つ。[zizmor](#zizmor) は環境変数 `GITHUB_TOKEN` が無いとオフラインで動き、オンラインの監査は警告付きでスキップされます。[gitleaks](#gitleaks) は shallow clone には無い全履歴を必要とします。

タスクが無いジョブは、手元のチェックアウトだけでは動かないものです。[CodeQL](#codeql) と `pr-title` は GitHub 側を必要とし、[setup-script](#setup-script) はトークンと API を必要とし、[markdownlint-cli2](#markdownlint-cli2)・[renovate-config](renovate.ja.md#設定の検証)・[osv-scanner](#osv-scanner) は前述の、mise を通さない 3 つの例外です。

## CodeQL

[ci.yml](../.github/workflows/ci.yml) の `codeql` ジョブが静的解析を行い、結果は Security タブの Code scanning に出ます。`ci` の `needs` に入っているので、解析に失敗すると PR がマージできません。ただし**アラートの検出そのものではジョブは落ちません**（`analyze` は結果をアップロードするだけです）。マージを止めるのはブランチ保護側の役目で、[main.json](../.github/rulesets/main.json) の `code_scanning` ルールが、重大度を問わずアラートが 1 件でもあればマージを止めます（`alerts_threshold` と `security_alerts_threshold` をどちらも `all` にしてあります）。厳しさを変えるときは同じ場所のこの 2 つを書き換えてください。問題ないと判断したアラートは Security タブの Code scanning で dismiss すれば、マージは止まらなくなります。

初期状態の解析対象は `actions`（ワークフローファイル自体）だけです。アプリコードを入れたら `matrix.language` に足してください。

```yaml
    strategy:
      matrix:
        language: [actions, javascript-typescript]
```

指定できる言語と、追加で `build-mode` が必要な言語は [CodeQL のサポート言語](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/) にあります。

注意点:

- **default setup と併用できません。** 本テンプレートはワークフローを自分で持つ advanced setup 方式です。リポジトリ側で default setup が有効なら先に切ります。

  ```bash
  gh api repos/OWNER/REPO/code-scanning/default-setup --jq .state
  gh api --method PATCH repos/OWNER/REPO/code-scanning/default-setup -f state=not-configured
  ```

- fork からの PR では `security-events: write` が付与されず、解析結果のアップロードに失敗する可能性があります（未検証）。外部からの PR を受けるようになってから確認し、失敗するならジョブに `if` を付けて fork の PR ではスキップしてください（`skipped` は `ci` で成功扱いになります）。その場合、fork からの変更はマージ後の main の run で初めて解析されます。スキップすると [main.json](../.github/rulesets/main.json) の `code_scanning` ルールが判定する CodeQL の結果も無くなるので、マージできるかを確認し、できなければこのルールも外してください。

## actionlint

[ci.yml](../.github/workflows/ci.yml) の `actionlint` ジョブが、ワークフロー定義そのものを検査します。存在しないコンテキストの参照、式の型の誤り、action の入力名の間違いなど、実行してみるまで気付けない不備を PR の時点で落とします。対象は `.github/workflows/` 配下すべてで、引数での指定は不要です。

シェルの検査の分担: **ワークフロー内の `run:` は actionlint（が呼ぶ shellcheck）、リポジトリ内の `*.sh` / `*.bash` は [shellcheck](#shellcheck) ジョブ、Dockerfile の `RUN` は [hadolint](#hadolint)（に同梱の ShellCheck）** が見ます。

**このジョブでは actionlint と一緒に shellcheck も入れています。** actionlint は shellcheck が PATH に無いと `run:` の検査を黙って飛ばすためです。同様に、`run:` に Python を書くようになったら pyflakes を [mise.toml](../mise.toml) と `install_args` に足してください。

## shellcheck

[ci.yml](../.github/workflows/ci.yml) の `shellcheck` ジョブが、git 管理下の `*.sh` / `*.bash` を検査します。未クォートの変数展開、意図しない単語分割、常に真になる比較など、実行してもエラーにならず黙って誤動作する類の不備が対象です。整形（インデントなど）は見ません。そちらは [`format`](../README.ja.md#書式の統一) ジョブの shfmt が担当します。

```bash
git ls-files -z '*.sh' '*.bash' \
  | xargs -0 -r shellcheck --color=always --external-sources
```

| 指定 | 理由 |
| --- | --- |
| `git ls-files` | 追跡外のファイル（手元の一時スクリプトなど）は検査しない |
| `-z` / `-0` | ファイル名を NUL 区切りで渡し、空白を含む名前でも壊れないようにする |
| `-r` | 対象が 1 件も無いときに shellcheck を起動しない |
| `--external-sources` | `source` で読み込む先のファイルも追跡する |

拡張子を持たないスクリプト（shebang だけのファイル）は対象外です。追加したら `git ls-files` のパターンを足してください。

## hadolint

[ci.yml](../.github/workflows/ci.yml) の `hadolint` ジョブが、git 管理下の Dockerfile を検査します。ベースイメージのタグ未固定（`FROM node:latest`）、バージョン指定の無い `apt-get install`、最後の `USER` が root のままなど、**`docker build` は通るが再現性・サイズ・権限で損をする書き方**が対象です。`RUN` に書いたシェルも、同梱の ShellCheck が [shellcheck](#shellcheck) ジョブと同じ観点で見ます。

```bash
git ls-files -z '*Dockerfile' '*Dockerfile.*' '*.dockerfile' \
  | xargs -0 -r hadolint
```

`git ls-files` / `-z` / `-0` の理由は [shellcheck](#shellcheck) と同じです。`-r` は、hadolint がファイル名を渡されないと標準入力を Dockerfile として読むため、空の実行をさせないために付けています。

**hadolint はディレクトリを辿らず、検査対象はファイル名で渡す必要があります。** 上のパターンで `Dockerfile` / `Dockerfile.dev` / `api.Dockerfile` / `web.dockerfile` などを、サブディレクトリも含めて拾います。`Containerfile` のような別の名前を使う場合はパターンを足してください。

色の指定が無いのは、hadolint に色を強制するオプションが無いためです（tty でない CI のログには色が付きません）。

ルールの一覧、落ちる基準（`-t`。既定は `info` 以上）、指摘の抑止の書き方は [hadolint の Rules](https://github.com/hadolint/hadolint#rules) にあります。`.hadolint.yaml` は初期状態では置いていません。

### Dockerfile が無い間は黙って通ります

このテンプレートにはまだ Dockerfile が無いため、このジョブは何も検査せずに成功します（`xargs -r` が hadolint を起動せず、ログには何も出ません）。Dockerfile を追加すればその時点から自動で対象になります。「対象が 0 件」と「検査して問題が無かった」がログ上は区別しにくい点に注意してください（[osv-scanner](#osv-scanner) と同じです）。

## typos

[ci.yml](../.github/workflows/ci.yml) の `typos` ジョブが、リポジトリ全体の誤字を検査します。コード・コメント・ドキュメント・ファイル名が対象で、`recieve` → `receive` のような**よくある綴り間違いの辞書**に載っている語だけを指摘します。辞書に無い語（固有名詞や略語）は黙って通るので、誤検出だらけにはなりません。日本語は対象外です。

設定は [.typos.toml](../.typos.toml) に書きます。初期状態で入れてあるのは 2 つです。

```toml
[files]
ignore-hidden = false
```

**typos は既定で `.` 始まりのファイルとディレクトリを飛ばします。** 外さないと `.github/` 配下がまるごと検査対象から外れます。`.git` 自体は [.gitignore](../.gitignore) に書いてあるため、gitignore を尊重する既定の動作で除外されます。

もう 1 つは `extend-ignore-re` で、この節の綴り間違いの例を除外しています（外すと typos 自身がこのファイルを誤字として弾きます）。

誤検出の抑止も同じファイルに足します（[全項目](https://github.com/crate-ci/typos/blob/master/docs/reference.md)）。

## lychee

[ci.yml](../.github/workflows/ci.yml) の `lychee` ジョブが、Markdown のリンク切れを検査します。このリポジトリのリンクの大半は見出しへのアンカーとリポジトリ内ファイルへの相対パスで、見出しの改名やファイルの移動で静かに切れます。このジョブはそれを PR で落とします。

```bash
lychee --offline --include-fragments --no-progress .
```

| 指定 | 理由 |
| --- | --- |
| `--offline` | `file` スキーム以外を検査対象から外す（= 通信しない） |
| `--include-fragments` | リンク先ファイルの中の `#アンカー` まで照合する |
| `--no-progress` | 非対話シェル向けにプログレスバーを消す |
| `.` | リポジトリのルートを再帰的にたどる（[.gitignore](../.gitignore) のものは除外） |

**このジョブは外部 URL を検査しません。** `--offline` を外すと相手先の一時的な不調やレート制限で CI が落ち、コードと無関係に赤くなるためです。外部 URL は別ワークフローの定期実行で見ます（[外部リンクの定期検査](#外部リンクの定期検査)）。

アンカーの照合は、lychee が見出しから生成する ID で行います。生成規則は GitHub の描画と一致し、日本語の見出しもそのまま ID になります（`#### Two exceptions` → `#two-exceptions`、`#### 2 つの例外` → `#2-つの例外`。同じ文言の見出しには 2 つ目以降に `-1`、`-2` が付きます）。

### 外部リンクの定期検査

外部 URL は [link-check.yml](../.github/workflows/link-check.yml) が毎日（08:00 JST）と main への push 時、および手動実行（`workflow_dispatch`）で確認します。同じ lychee ですが、役割が違います。

| | `ci` の `lychee` ジョブ | `link-check` ワークフロー |
| --- | --- | --- |
| 見るもの | リポジトリ内の相対パスと見出しへのアンカー | 外部 URL |
| 通信 | しない（`--offline`） | する |
| アンカーの照合 | する | しない |
| 必須チェック | はい（`ci` の一部） | いいえ（別ワークフロー） |
| 落ちたとき | PR がマージできない | issue が立つ |

```bash
lychee --no-progress --exclude 'OWNER/REPO' .
```

CI ではこれに `--mode plain` を足し、出力を `tee` で控えます（ANSI エスケープを混ぜずに issue 本文へそのまま載せるため）。

`ci` に入れていないのは、リンク先はこちらが何もしなくても消え、一時的な不調でも落ちる（= コードを変えなくても結果が変わる）ためです。必須チェックにすると、リンク先が落ちている間は無関係な PR まで止まります。

**アンカーは見ません**（`--include-fragments` を付けていません）。外部ページの見出し ID は描画側の都合で決まり（GitHub は README の見出しに `user-content-` を付けます）、誤検出にしかならないためです。リポジトリ内のアンカーは `ci` 側が見ています。

`--exclude 'OWNER/REPO'`（正規表現）は、ドキュメントに説明用として載せている実在しない URL の除外です。パターンに URL そのものを書かないのは、lychee がワークフローファイル自身も走査するため、`https://...` と書くとそれがリンクとして拾われるからです。恒久的に検査できない URL が出たら同じようにここへ足してください。一時的な不調は `--max-retries` の既定（3 回）が吸収します。

`GITHUB_TOKEN` を渡しています。lychee は github.com のリンクを GitHub API 経由で確認するため、渡さないと未認証のレート制限に当たり、実在するリンクが落ちます。

落ちたときの通知は[設定のずれの検査と同じ仕組み](drift-check.ja.md#落ちたときの通知)です。`External links are broken` という issue が `maintenance` ラベル付きで立ち、直れば次の実行で自動的に閉じます。定期実行なので[活動が無いと止まる](#定期実行が止まるとき)点も同じです。

## markdownlint-cli2

[ci.yml](../.github/workflows/ci.yml) の `markdownlint` ジョブが、Markdown の書式を検査します。見出しの階層の飛び、言語指定の無いコードブロックなど、表示はできてしまうが揃っていない書き方を落とします（誤字は [typos](#typos)、リンク切れは [lychee](#lychee) の担当です）。

適用する規則は [.markdownlint-cli2.jsonc](../.markdownlint-cli2.jsonc) に書きます（[規則の一覧](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)）。**検査対象はこのファイルではなく、ジョブが渡す `globs` で決まります。** action の既定はルート直下しか見ないため `**/*.md` を明示しています。渡し忘れると `.github/` 配下が黙って漏れます。

既定から変えているのは 4 つです。

| 規則 | 変更 | 理由 |
| --- | --- | --- |
| `MD009`（行末の空白） | `strict` | 強制改行（行末の半角スペース 2 つ）を使わないため |
| `MD013`（行の長さ） | 本文 1000 文字（見出しと表も同じ上限を継承）、コードブロック 120 文字 | 本文は折り返さず 1 段落 1 行で書くため（すぐ下）。コードブロックは折り返せず、長いと横スクロールになる |
| `MD041`（先頭行が h1） | 無効 | [pull_request_template.md](../.github/pull_request_template.md) は PR 本文の一部として貼られるもので、h1 から始まらないのが正しい |
| 記法のスタイル（`MD003` `MD004` `MD029` `MD046` `MD048` `MD049` `MD050`） | `consistent` から具体値に固定 | `consistent` は 1 ファイルの中でしか揃わないため |

**本文は途中で改行せず、1 段落を 1 行で書きます。** Markdown は段落内の改行を半角スペースに変換して表示するため、日本語の文を途中で折り返すと、表示された文の途中に空白が入ります。折り返しはソース側ではなく表示側で決めることでもあり、1 段落 1 行にしておけば差分が段落単位になって、語句を直しただけで以降の折り返し位置がずれる、といったことも起きません。`MD013` の本文の上限を 1000 文字まで上げているのはこのためです。

行末の空白は `MD009` が見ます。[.editorconfig](../.editorconfig) が `*.md` を検査から外している分（[例外](../README.ja.md#2-つの例外)）はここで埋まります。

**このジョブだけは公式の [action](https://github.com/DavidAnson/markdownlint-cli2-action) を使い、mise を経由しません。** markdownlint-cli2 は npm でしか配布されておらず、mise で入れると実行用の node も別に要るためです。検査に使われるバージョンは action に同梱されたもので、action は commit SHA で固定してあります。

## ghalint

[ci.yml](../.github/workflows/ci.yml) の `ghalint` ジョブが、ワークフロー定義を**セキュリティの観点**で検査します。権限の与えすぎやトークンの残留といった、動いてしまうけれども危ない書き方を落とします。同じセキュリティ観点でも [zizmor](#zizmor) とは拾う範囲が違うため、両方入れてあります。

ポリシーの一覧は [ghalint のドキュメント](https://github.com/suzuki-shunsuke/ghalint#policies)にあります。ジョブを追加するときに引っかかるもの — 全ジョブへの `permissions` と `timeout-minutes`、`actions/checkout` への `persist-credentials: false` — は [CI にジョブを追加する](#ci-にジョブを追加する)で説明済みです。ほかに、action の参照は 40 桁の commit SHA であることが求められ、`secrets: inherit` とワークフロー / ジョブの env への secret の設定は禁じられます。

`persist-credentials: false` は、checkout が `.git/config` に残すトークンを消す指定です。残すと後続のすべてのステップ（そこで動く Docker イメージも含む）から読めてしまいます。push が必要なジョブを足す場合は、そのジョブだけ `ghalint.yaml` で例外にしてください。

```yaml
excludes:
  - policy_name: checkout_persist_credentials_should_be_false
    workflow_file_path: .github/workflows/ci.yml
    job_name: format
```

検査対象は `.github/workflows/` 配下です。composite action（`action.yaml`）を置いたら `ghalint run-action` も実行するようにしてください（`run` だけでは検査されません）。

## zizmor

[ci.yml](../.github/workflows/ci.yml) の `zizmor` ジョブが、ワークフロー定義を**攻撃者の視点** で検査します。[ghalint](#ghalint) が書き方の作法を見るのに対し、こちらは式や trigger の組み合わせから生まれる攻撃経路そのものを見ます。

監査項目の一覧は [zizmor のドキュメント](https://docs.zizmor.sh/audits/)にあります。`run:` への `${{ }}` の直接埋め込み（template injection）、`pull_request_target` のような危険な trigger、必要以上の `permissions`、ダイジェストで固定されていない action / イメージ、などです。

固定した SHA や使用中の action を GitHub API と照合する 2 つの監査（`impostor-commit`、`known-vulnerable-actions`）は、トークンが無いと黙ってスキップされます。ジョブでは `GITHUB_TOKEN` に `github.token` を渡して有効にしています（公開情報しか参照しないので `contents: read` で足ります）。

検査対象はリポジトリのルート（`.`）で、composite action や Dependabot の設定も自動で集めます。`--strict-collection` を付けてあるので、解析できないファイルがあれば警告で流さず失敗します。

指摘の抑止の書き方と、既定で報告される実害のある指摘に書き方の改善提案を加える pedantic persona は、[zizmor のドキュメント](https://docs.zizmor.sh/)にあります。

## gitleaks

[ci.yml](../.github/workflows/ci.yml) の `gitleaks` ジョブが、コミット履歴に混ざった秘密情報（API キー、アクセストークン、秘密鍵など）を探します。一度 push した秘密情報は、後のコミットで消しても履歴から取り出せるため、**入る前に止めるしかありません**。1 枚目の防御はセットアップスクリプトが有効にする secret scanning の push protection で（[セットアップ](../README.ja.md#セットアップ)）、そもそも push が拒否されます。このジョブは 2 枚目で、push protection が知らないパターンと、それ以前から履歴にあるものを、マージ前に止めます。`ci` の `needs` に入っているので、検出されると PR がマージできません。

検出は本体に組み込まれた 200 以上のルール（プロバイダごとの正規表現と、値のエントロピー判定）で行います（[既定の設定](https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml)）。

走査対象は履歴全体です。`gitleaks git` は内部で `git log -p` を使うため、`actions/checkout` に `fetch-depth: 0` を付けて浅いクローンを避けています（既定の深さ 1 では過去のコミットに入った値を見落とします）。

```bash
gitleaks git --redact --verbose --no-banner
```

`--redact` は検出した値そのものをログに出さないための指定です。public リポジトリでは実行ログも公開されるため、これが無いと検査自体が漏洩経路になります。`--verbose` は検出箇所（コミット / ファイル / 行 / ルール ID / fingerprint）を出します。

### 検出されたとき

まず**その値を失効させます**（キーの再発行、トークンの revoke）。push した時点で他者が取得できたものとして扱い、履歴の書き換えは後回しで構いません。そのうえでリポジトリから値を消し、環境変数や GitHub Secrets 経由で渡す形に直してください。

誤検知（テスト用のダミー値など）を外すには `# gitleaks:allow` コメント、`.gitleaksignore`、`.gitleaks.toml` の 3 通りがあり、いずれも [gitleaks のドキュメント](https://github.com/gitleaks/gitleaks)にあります。

## setup-script

[ci.yml](../.github/workflows/ci.yml) の `setup-script` ジョブが、[セットアップ](../README.ja.md#セットアップ)のスクリプトを `--dry-run` で実際に実行します。[shellcheck](#shellcheck) は静的な検査なので、変数名の取り違えなどは通ってしまいます。動かすのはリポジトリを作った直後の 1 回だけで、壊れていても気づくのはテンプレートからリポジトリを作った人です。唯一の実行経路を CI で通しておきます。

`--dry-run` は読み取りだけで完結し、何も変更しません。スクリプトは送信内容を表示するだけです。`.github/rulesets/*.json` が壊れていればここで落ちるため、ruleset の JSON の構文ミスも PR で捕まります。あわせて `--help` の出力が空でないことも確かめています（ヘルプはスクリプト冒頭のコメントを awk で切り出しているため、コメントを消すと黙って空になります）。

`gh` と `jq` は GitHub ホストの runner に最初から入っているため、[mise.toml](../mise.toml) には足していません。認証はワークフローの `GITHUB_TOKEN` で足ります。

private リポジトリではこのジョブを走らせません（セットアップスクリプトが public 以外を拒否するため、回せば必ず落ちます）。スキップは `ci` 側で成功扱いになるので、private でも PR は止まりません。

## hooks

[ci.yml](../.github/workflows/ci.yml) の `hooks` ジョブが、[.claude/tests/](../.claude/tests) にある [bats](https://bats-core.readthedocs.io/) のテストで、隣の [.claude/hooks/](../.claude/hooks) にあるフックスクリプトを検査します。フックは標準入力に JSON でツール呼び出しを受け取り、標準出力に JSON で判定を返すフィルタなので、テストはコマンドを 1 つ流し込んで判定を読むだけです。

```bash
git ls-files -z '.claude/tests/*.bats' \
  | xargs -0 -r bats --print-output-on-failure
```

テストが押さえるのは当たり前の場合ではなく境目です。先にブランチを作るコミットは通し、ブランチを作らない同じコミットは拒否する。`git log | grep push` は push ではない。この境目はシェルを解析せず文字列で判定しているので、その代償である誤検知（引用しただけの `echo "git commit"` も拒否される）もあわせて固定してあります。そこが落ちたときは、挙動が良くなったのではなく変わったということです。

結線もテストの対象です。フックは [.claude/settings.json](../.claude/settings.json) を通してしか呼ばれないため、設定を直さずにスクリプトの名前を変えた場合、答えるイベントと違うイベントに登録した場合、テストファイルのないフックスクリプトを足した場合は、いずれもこのジョブが落ちます。スクリプトだけを見るテストでは、どれも素通りします。

prompt フックは中身も対象です。Conventional Commits の type 一覧は [ci.yml](../.github/workflows/ci.yml)（`PATTERN` とその隣の失敗メッセージ）、両 README の表、prompt フックに書き出されていて、どのコピーも他から導出されないため、テストが各コピーを `PATTERN`（`pr-title` ジョブが実際に強制するもの）と突き合わせます。

ブランチ規則のテストは bats の一時ディレクトリに使い捨てのリポジトリを作るため、判定が runner のいるブランチに左右されることはありません。`jq` は GitHub ホストの runner に最初から入っていて、そもそも呼ぶのはフック自身なので、[mise.toml](../mise.toml) に足すのは bats だけです。

テストを独立した `tests/` ではなく `.claude/` の下に置いてあるのは、フックを削除すればテストも一緒に消えるようにするためと、テンプレートから作ったリポジトリが自分のテストに一番自然な置き場を空けておくためです。その後もこのジョブが緑のままなのは `-r` のおかげで、`.bats` が 1 つも残らなければ bats は起動しません。フックを手放すなら、ジョブ自体もフックと一緒に削除してください。

## script-tests

[ci.yml](../.github/workflows/ci.yml) の `script-tests` ジョブが、2 つの置き場にある [bats](https://bats-core.readthedocs.io/) のテストで、それぞれ隣にあるスクリプトを検査します。[.github/scripts/tests/](../.github/scripts/tests) は 1 つ上の [.github/scripts/](../.github/scripts) を検査します。定期実行のワークフローが、落ちた検査を issue として報告し、通ったら取り下げるために呼ぶ 2 つです。[scripts/tests/](../scripts/tests) は [scripts/](../scripts) にある [sync-repo-config.sh](../scripts/sync-repo-config.sh) を検査します。[設定のずれの検査](drift-check.ja.md#設定のずれの検査)が OK / DRIFT / UNKNOWN の判定を頼っているスクリプトです。

```bash
git ls-files -z '.github/scripts/tests/*.bats' 'scripts/tests/*.bats' \
  | xargs -0 -r bats --print-output-on-failure
```

テストは `gh` をスタブに差し替えるので（仕組みは隣の `helper.bash` にあります）、GitHub には何も届かずトークンも要りません。だからこそ、その呼び出しの周りにある判断（各スクリプトの `--help` が説明している内容）をそもそも検査できます。このジョブが動かすのは [setup-script](#setup-script) が届かない部分です。dry run は判定にも書き込みにも進まないため、`--check` の OK / DRIFT / UNKNOWN の判定と適用の経路が動くのはここだけです。

このロジックをワークフローに直接書かず `.github/scripts/` に置いてあるのは、テストから触れるようにするためです。`run:` の中身は囲んでいるワークフローを起動しないと動かせず、この 2 つの場合それは定期実行の検査が落ちるのを待つことを意味します。

[hooks](#hooks) と同じく、[mise.toml](../mise.toml) に足すのは bats だけです。[shellcheck](#shellcheck) と [format](../README.ja.md#書式の統一) はどちらも `git ls-files` で `*.sh` と `*.bash` を辿るため、何もしなくてもこのスクリプトを拾います。

## osv-scanner

**依存パッケージの既知の脆弱性**を osv-scanner で検査します。lockfile に書かれたパッケージとバージョンを [OSV](https://osv.dev)（脆弱性データベース）に問い合わせます。[CodeQL](#codeql) が自分で書いたコードの欠陥を見るのに対し、こちらは他人が書いた依存の既知の欠陥を見ます。

同じツールを、役割の違う 2 層に分けてあります。

| | 何を見るか | どこで | 検出したら |
| --- | --- | --- | --- |
| 差分検査 | **その PR が新たに持ち込む**脆弱性だけ | [ci.yml](../.github/workflows/ci.yml) の `osv-scanner-diff` ジョブ（PR ごと） | ジョブが落ちる（`ci` の `needs` にあるのでマージ不可） |
| 全体検査 | 依存全体の既知の脆弱性 | [osv-scanner.yml](../.github/workflows/osv-scanner.yml)（毎日 + main への push + 手動） | Security タブの Code scanning にアラート（ジョブは落ちない） |

分ける理由は、この検査が「コードを変えていなくても結果が変わる」ことです。脆弱性は後から公開されるので、全体は定期実行で追いかけます。それを PR の必須チェックにすると既に main にある脆弱性で無関係な PR まで止まるため、PR 側は差分だけを見て落とします。この 2 本立ては [公式](https://github.com/google/osv-scanner-action)が推奨している構成です。

### 他の CLI ツールと扱いが違います

どちらの層も、公式が配布している再利用可能ワークフローをそのまま呼んでいます。本体を mise で入れる形にはしておらず、[mise.toml](../mise.toml) にも書いていません。差分の突き合わせは osv-scanner 本体ではなく別のツール（osv-reporter）が行うため、本体だけを入れる形では組めず、片方だけ公式に寄せるとバージョンが 2 系統になって「PR で通ったものが定期実行で引っかかる」ことになるためです。

受け入れている代償は 2 つです。

- バージョンをこのリポジトリで固定していません。追随は `@<commit sha>` の更新として [Renovate](renovate.ja.md#renovate) が拾います。
- 手元で同じ検査を再現できません。

### 全体検査（定期実行）

[osv-scanner.yml](../.github/workflows/osv-scanner.yml) の実行のきっかけは 3 つです。

| | 実行のきっかけ | 用途 |
| --- | --- | --- |
| `schedule` | 毎日 06:00 JST | 新しく公開された脆弱性に気付く |
| `push`（main） | 依存を触った PR のマージ | 次の定期実行を待たずに結果を出す。Code scanning のアラートの基準となる「デフォルトブランチの解析結果」を作る |
| `workflow_dispatch` | 手動 | 設定を変えた直後の確認 |

```yaml
  osv-scanner:
    permissions:
      contents: read
      actions: read
      security-events: write
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@<commit sha> # v<タグ>
    with:
      scan-args: |-
        -r
        --allow-no-lockfiles
        ./
      fail-on-vuln: false
```

`fail-on-vuln: false` にしてあります（既定は `true`）。検出は Code scanning にアラートとして出るので、ジョブは落としません。落とすと同じ脆弱性で毎日赤くなり、「対応済み」「様子見」を個別に記録できないためです。アラートは毎回の実行で更新され、直った脆弱性のアラートは自動で閉じます。通知を受け取るにはリポジトリを watch して Code scanning のアラート通知を有効にしておきます。

実行そのものが落ちたとき（脆弱性が見つかったときではなく）は、`notify` ジョブが[設定のずれの検査と同じ仕組み](drift-check.ja.md#落ちたときの通知)で `osv-scanner runs are failing` という issue を `maintenance` ラベル付きで立て、実行が通れば自動的に閉じます。issue なしではこの失敗は見えません。何も見つからなかった走査と走らなかった走査は、Security タブからは同じに見えます。

### 差分検査（PR 側）

[ci.yml](../.github/workflows/ci.yml) の `osv-scanner-diff` ジョブが、base と PR の両方を走査して差分を取り、PR 側にだけある脆弱性で落とします（`fail-on-vuln: true`）。既に main にある脆弱性では落ちません。検出は実行ログの注釈と Code scanning の両方に出ます。直し方は [全体検査と同じ](#直し方と例外の書き方)です。

注意点:

- **`timeout-minutes` を書けません**（[CI にジョブを追加する](#ci-にジョブを追加する)で説明した例外です）。上限は GitHub 既定の 6 時間になり、全体検査も同じです。
- fork からの PR では `security-events: write` が付与されず、SARIF のアップロードに失敗する可能性があります（[CodeQL](#codeql) と同じ話です）。外部からの PR を受けるようになったら `upload-sarif: false` を渡してください（差分の判定とジョブの成否はそのまま働きます）。
- `push`（= マージ）では比較対象の base が無いのでスキップされます（`skipped` は `ci` で成功扱いです）。

### PR に出る「1 configuration not found」

PR のチェック一覧に **`osv-scanner`（GitHub Advanced Security）** という項目が並び、`1 configuration not found` の警告とともに灰色（`neutral`）になります。**この状態が正常で、マージも止まりません**（必須チェックはゲートジョブ `ci` だけです）。

Code scanning は「その PR が新たに持ち込んだアラート」を出すために、base に存在する configuration（識別は「ワークフローファイル : ジョブ名」）ごとに base 側と head 側の解析結果を突き合わせます。全体検査（`osv-scanner.yml:osv-scan`）は PR では走らないため head 側に結果が無く、「この configuration については判定できない」と言われます。2 層に分けた構成の当然の帰結で、lockfile を置いても消えません。

消すには [osv-scanner.yml](../.github/workflows/osv-scanner.yml) の `on` に `pull_request` を足すことになりますが、入れていません。得られるのは灰色の項目が緑になることだけで、代わりに毎 PR で依存全体を二重に走査し、[2 層に分ける理由](#osv-scanner)を崩すためです。SARIF の category を揃えて 1 つの configuration に見せる手も、公式の再利用可能ワークフローに category の入力が無いため取れません。

なお、この警告文そのものを説明した GitHub の公式ドキュメントは見当たりません。上記はチェックの実際の判定（`neutral`）と 2 つの configuration の実行条件から確かめた内容です。判定は次で確認できます。

```bash
gh api repos/OWNER/REPO/commits/<sha>/check-runs \
  --jq '.check_runs[] | select(.name == "osv-scanner") | {conclusion, title: .output.title}'
```

### 直し方と例外の書き方

**まず修正版のバージョンへ上げます。** 報告には修正が入ったバージョンが出るので、そこまで上げれば消えます（[Renovate](renovate.ja.md#renovate) の更新 PR を待つより手で上げる方が速いことがあります）。

すぐに上げられない場合や誤検知の場合は、`osv-scanner.toml` を置いて個別に外します（[設定の書式](https://google.github.io/osv-scanner/configuration/)）。**例外には必ず期限を切ってください**（`ignoreUntil`。パッケージ単位で外すなら `effectiveUntil`）。省略すると無期限の例外になり、修正版が出ても誰も気付きません。

設定ファイルは検査対象ファイルと同じディレクトリに置いたものだけが効き、サブディレクトリには伝播しません。サブディレクトリへ lockfile を置く構成でルートの 1 つを全体に効かせたい場合は、`scan-args` に `--config=osv-scanner.toml` を足してください。

### 検査対象が無いときは黙って通ります

見るのはリポジトリにコミットされた lockfile / マニフェストです（[対応形式の一覧](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)）。`-r` を付けてあるのでサブディレクトリも辿ります。

このテンプレートには読める lockfile が 1 件も無いため、現時点ではまだ何も検査していません。lockfile を置いた時点で、設定を足さずに検査が始まります。

osv-scanner は検査対象が 1 件も無いとき、「スキャンしたつもりで何もスキャンしていない」状態を黙って成功にしないよう終了コード 128 で失敗します。そのため両方の呼び出しに **`--allow-no-lockfiles`** を渡してこの状態を明示的に許可しています（付けないと呼び出し先が deprecation warning を出し、いずれ CI が赤くなります）。

代償として、何も検査していないことが警告として出なくなります。**依存を入れたらこのフラグを外してください。** 外せば「読める lockfile が 1 件も無い」状態がジョブの失敗になり、lockfile を `.gitignore` に入れてしまったといった取りこぼしをその場で捕まえられます。

### 定期実行が止まるとき

schedule はリポジトリの活動が 60 日間無いと GitHub 側で自動的に止まります（オーナーに通知が来ます）。止まったら Actions タブから有効化し直してください。動きの無いリポジトリでは黙って検査が止まる、という性質は覚えておいてください。

### 問い合わせ先

既定ではパッケージ名とバージョンを [api.osv.dev](https://osv.dev) へ送って照合します（ソースコードは送りません）。外部へ何も出したくない場合は、脆弱性データベースを runner に落として照合する `--offline-vulnerabilities`（初回の取得は `--download-offline-databases`）を `scan-args` に足します。

## Scorecard

[OpenSSF Scorecard](https://github.com/ossf/scorecard) は、ブランチ保護・トークンの権限・依存の固定・危険なワークフローの書き方などの公開された検査項目に照らして、**リポジトリのセキュリティ体制全体**を 0〜10 で採点します。他の検査はそれぞれ 1 種類の対象を守りますが、Scorecard は組み合わせを採点するので、どの個別検査の持ち場でもない後退にも気付けます。

[scorecard.yml](../.github/workflows/scorecard.yml) の実行のきっかけは [osv-scanner の全体検査](#全体検査定期実行)と同じ 3 つで、schedule だけが毎週（火曜 05:00 JST）です。点数が追うのは設定とワークフロー定義で、脆弱性の公開よりずっと変化が遅いためです。検出は Security タブの Code scanning に `Scorecard` ツールとして出ます。

**検出はマージを止めません。**[main.json](../.github/rulesets/main.json) の `code_scanning` ルールが挙げているのは CodeQL だけです。Scorecard の検出は目の前の変更の欠陥ではなく体制への段階評価付きの助言なので、PR ごとに強制するのではなく、Security タブから確認して取捨選択します。

### 公開スコアとワークフローの制約

`publish_results: true` により点数は公開の [Scorecard API](https://scorecard.dev) へ送られ、誰でも `https://scorecard.dev/viewer/?uri=github.com/OWNER/REPO` で見られます。README に出すにはバッジを足します。

```markdown
[![OpenSSF Scorecard](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.scorecard.dev%2Fprojects%2Fgithub.com%2FOWNER%2FREPO&query=%24.score&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/OWNER/REPO)
```

バッジが shields.io の dynamic JSON バッジで API からスコアを直接読んでいるのは、素のバッジエンドポイント（`https://api.scorecard.dev/projects/github.com/OWNER/REPO/badge`）が、廃止された API ホストを参照し続けるバッジへリダイレクトされ、スコアではなくエラーを表示するためです。代償として、スコアの値による色分けはされません。

引き換えに、API は[結果を作るワークフローの書き方を制約します](https://github.com/ossf/scorecard-action#workflow-restrictions)。`analysis` ジョブの step は承認されたアクションの一覧に限られ、ジョブに `env`・コンテナ・サービスを持てません。**このジョブに step を足すと — たとえば mise でツールを入れると — 公開が失敗します**（下の issue で表面化します）。追加のものは別ジョブに置きます。`notify` がまさにそれです。

### 満点にならない 2 つの検査項目

- **Branch-Protection** — 保護設定の全体を読むには admin 権限が要りますが、ワークフローは admin を持たない既定の `GITHUB_TOKEN` で動きます。Scorecard は公開されている範囲だけを採点し、そこで止まります。この差のためにもう 1 つ admin の長命トークンを登録する価値はありません。設定そのものは[設定のずれの検査](drift-check.ja.md#設定のずれの検査)が毎日確認しています。
- **CII-Best-Practices** — [OpenSSF Best Practices バッジ](https://www.bestpractices.dev/)の保有を採点します。外部プログラムへの申請であって、リポジトリの設定ではありません。

### 実行が落ちたとき

実行そのものが落ちたとき — Scorecard API の障害や、上の制約を破る編集をしたとき — は、`notify` ジョブが[設定のずれの検査と同じ仕組み](drift-check.ja.md#落ちたときの通知)で `scorecard runs are failing` という issue を `maintenance` ラベル付きで立て、実行が通れば自動的に閉じます。
