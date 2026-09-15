# lab

## Renovate の事前準備

依存関係の更新は [.github/workflows/renovate.yml](.github/workflows/renovate.yml) で
Renovate を自前運用している。認証に使う Personal Access Token（PAT）は GitHub の UI で用意する。
このリポジトリのスクリプトでは管理していない。

1. fine-grained PAT を発行する。アクセス対象はこのリポジトリだけに限定し、Repository permissions を次のとおりにする。
   https://docs.renovatebot.com/modules/platform/github/#authentication

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
