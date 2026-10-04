# lab

## 開発環境（devcontainer）

api の開発は VS Code の dev container で行う。コンテナの定義は
[docker-compose.yml](docker-compose.yml) と [.devcontainer/api-container/](.devcontainer/api-container/) にある。

```bash
make dev-api
```

[Makefile](Makefile) の `dev-api` が [vscli](https://github.com/michidk/vscli) を呼び、
`.devcontainer/api-container/devcontainer.json` を指定して VS Code を開く。
コンテナの起動と接続は Dev Containers 拡張が行うため、`docker compose` を直接叩く必要はない。

- 前提: Docker が動いていること、VS Code に Dev Containers 拡張が入っていること、`vscli` が PATH にあること
  （`brew install michidk/tools/vscli`）
- リポジトリ全体が `/workspace` にマウントされ、`/workspace/api` が作業ディレクトリになる
- コンテナの中では `go run .` で HTTP サーバーが起動する（既定のポートは 8080、環境変数 `PORT` で変更できる）。
  `GET /healthz` が `{"status":"ok"}` を返す。テストは `go test ./...`
- コンテナは `dev` ユーザー（UID/GID 1000）で動く。root では動かさない
- Go の language server（gopls）はイメージに同梱している。整形（gofumpt）と静的解析（staticcheck）は
  gopls が内蔵しているものを使い、`devcontainer.json` の `gopls` 設定で有効にしている。
  gopls の版は [.devcontainer/api-container/Dockerfile](.devcontainer/api-container/Dockerfile) の
  `ARG` に固定してあり、Renovate が更新を追う
- VS Code を閉じてもコンテナは止まらない（`shutdownAction` が `none`）。止めるときは `docker compose down`

web（Node.js）の開発用コンテナも同じ compose ファイルに `web` サービスとして定義している。
定義は [.devcontainer/web-container/](.devcontainer/web-container/) にある。

```bash
make dev-web
```

- 前提・マウント・ユーザー（`dev`、UID/GID 1000）・`shutdownAction` は api と同じ。作業ディレクトリは `/workspace/web`
- 上のマウントに加えて、pnpm のストアと `web/node_modules` を named volume（`pnpm-store`、`web-node-modules`）に置く。
  ホストの `web/node_modules` は空のまま。`pnpm install` はコンテナの中で実行する。
  `docker compose down -v` を使うと、この2つの volume も消える
- `web/` ディレクトリはまだリポジトリに無い。中身は別途追加する
- Node.js は公式イメージ `node:26.10.0-trixie` を digest で固定して使う。npm はイメージ同梱のもの。
  公式イメージにある `node` ユーザー（UID/GID 1000）を `dev` に改名して、api と同じユーザー名にしている

## リポジトリ設定の適用

リポジトリの説明文・ルールセット・マージ方式・セキュリティ機能・Actions の実行許可・ラベルは、GitHub の UI ではなく
[scripts/apply-repo-settings.sh](scripts/apply-repo-settings.sh) と
[.github/rulesets/](.github/rulesets/) の定義ファイルで管理している。
Renovate の自動マージや CI の前提になる設定も含むため、下の Renovate の準備より先に実行する。

```bash
scripts/apply-repo-settings.sh
```

- 前提: `gh` が認証済み（`gh auth login`）で、対象がパブリックリポジトリ、実行者が ADMIN 権限を持つこと。
  満たさない場合は設定を変更する前に前提チェックで止まる
- 冪等なので、何度実行しても同じ状態になる。迷ったら実行してよい
- 次のタイミングで再実行する
  - `.github/rulesets/*.json` またはスクリプト自体を変更したとき
  - ruleset-drift の通知 issue で、定義ファイル側が正だと判断したとき

## ruleset-drift の事前準備

[.github/workflows/ruleset-drift.yml](.github/workflows/ruleset-drift.yml) は、
[.github/rulesets/](.github/rulesets/) の定義ファイルと GitHub 上のルールセットを毎日比較する。
この比較には専用の Personal Access Token（PAT）が要る。Renovate の PAT と同じく GitHub の UI で用意する。

`GITHUB_TOKEN` では足りない。ルールセット取得APIの `bypass_actors` は、
ルールセットへの write 権限を持つ要求元にだけ返され、権限が無いとキーごとレスポンスから消える
（<https://docs.github.com/en/rest/repos/rules>）。
`GITHUB_TOKEN` の `permissions:` に `administration` スコープは無いため、この権限は与えられない
（<https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions>）。

1. fine-grained PAT を発行する。アクセス対象はこのリポジトリだけに限定し、Repository permissions を次のとおりにする。

   | 権限 | レベル |
   | --- | --- |
   | Administration | Read-only |
   | Metadata | Read-only |

2. リポジトリの Secrets に `RULESET_READ_TOKEN` として登録する
3. PAT に有効期限を付けた場合は、期限切れ前に再発行して Secrets を更新する
   （期限切れになるとワークフローが落ちるだけで、リポジトリ側に影響はない）

## Renovate の事前準備

依存関係の更新は [.github/workflows/renovate.yml](.github/workflows/renovate.yml) で
Renovate を自前運用している。認証に使う Personal Access Token（PAT）は GitHub の UI で用意する。
このリポジトリのスクリプトでは管理していない。

1. fine-grained PAT を発行する。アクセス対象はこのリポジトリだけに限定し、Repository permissions を次のとおりにする。
   <https://docs.renovatebot.com/modules/platform/github/#authentication>

   | 権限 | レベル |
   | --- | --- |
   | Contents | Read and write |
   | Pull requests | Read and write |
   | Issues | Read and write |
   | Workflows | Read and write |
   | Commit statuses | Read and write |
   | Dependabot alerts | Read-only |
   | Metadata | Read-only |

2. リポジトリの Secrets に `RENOVATE_TOKEN` として登録する
3. PAT に有効期限を付けた場合は、期限切れ前に再発行して Secrets を更新する
   （期限切れになるとワークフローが認証エラーで落ちるだけで、リポジトリ側に影響はない）
