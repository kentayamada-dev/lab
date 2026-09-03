# 設定のずれの検査

[セットアップ](../README.md#セットアップ)のスクリプトが入れる設定は、GitHub の画面からいつでも変えられます。変えられても、スクリプトに設定を足したまま再実行を忘れても、`ci` は緑のままです。そこで [repo-settings.yml](../.github/workflows/repo-settings.yml) が毎日（07:00 JST）と main への push 時に `--check` を実行し、現在の設定が定義とずれていれば落ちます。

```bash
./scripts/sync-repo-config.sh --check
```

| 見るもの | 判定 |
| --- | --- |
| リポジトリ設定（auto-merge / マージ方式 / squash タイトル / Issues など） | 値が定義と一致するか |
| immutable releases / 脆弱性の非公開報告 / Dependabot alerts | 有効になっているか |
| secret scanning の push protection | 有効になっているか |
| Actions の `GITHUB_TOKEN` の既定権限（read 固定 / PR の作成・承認の禁止） | 値が定義と一致するか |
| ラベル（[ラベル](../README.md#ラベル)の 4 つ） | **同じ名前のものが存在するか** |
| ruleset（`.github/rulesets/*.json` の各ファイル） | enforcement・対象・bypass actor の数・全ルールの中身が定義と一致するか |

ruleset で突き合わせるのは定義に書いた項目だけです。API は `id` や `created_at`、後から GitHub が増やすパラメータを自分で足してくるので、それらをずれとして扱うと GitHub 側の追加のたびに落ちてしまいます。配列は比較前に整列させます。送った順序で返る保証がないためです。定義に無いルールは `unexpected rule` として報告するので、UI で足されたルールも捕まえられます。

**ラベルは今も存在までしか見ません。** UI で色や説明を書き換えられても検出しません（名前の変更・削除は「存在しない」として検出します）。

期待値は[スクリプト](../scripts/sync-repo-config.sh)の `REPO_SETTINGS_EXPECTED` / `REPO_SETTINGS_ENDPOINTS` / `SECURITY_ANALYSIS_EXPECTED` / `ACTIONS_WORKFLOW_EXPECTED` / `LABELS_EXPECTED` にあり、適用と確認の両方がそこを読むため、片方だけ直って食い違うことは起きません。設定を増やすときもここに 1 行足すだけで、`--check` と `--dry-run` の対象に自動的に入ります。

ずれていたら、引数なしで実行すれば適用されます（オプションと環境変数は `--help` にあります）。

```bash
./scripts/sync-repo-config.sh
```

## 落ちたときの通知

**検査が落ちると issue が立ちます。** 定期実行の失敗は Actions の画面か通知メールでしか分からず、見落とすとずれたまま運用が続いてしまうためです。

issue は `Repository settings have drifted` というタイトルで `maintenance` ラベル付きで立ち（[ラベル](../README.md#ラベル)）、本文に検査の出力と実行ログの URL、直し方が入ります。検査が通れば自動的に閉じます。すでに同じ issue が open の間は作り直しません。そのときの扱い（放置 / コメント追記 / 本文の書き換え）はワークフローごとに `--on-existing` で選んでおり、選択肢の意味は [upsert-issue.sh](../.github/scripts/upsert-issue.sh) の `--help` にあります。この検査はコメント追記です。

issue の作成・コメント・close はワークフローの `GITHUB_TOKEN`（`issues: write`）で行います。`SETTINGS_TOKEN` は読み取り専用のままで構いません。

他の定期実行（[link-check](ci-jobs.md#外部リンクの定期検査) / [claude-settings](ci-jobs.md#claude-code-設定の定期検査) / [osv-scanner](ci-jobs.md#osv-scanner) / [Scorecard](ci-jobs.md#scorecard) / [Renovate](renovate.md#実行が失敗したとき)）も同じ形で通知し、どれも定期実行なので[活動が無いと止まります](ci-jobs.md#定期実行が止まるとき)。ワークフロー側の書き方は 2 通りあり、条件の理由は共通です。検査と同じジョブで通知するもの（repo-settings / link-check / claude-settings）は、issue を立てる step の `if` に `steps.check.outcome == 'failure'` を含めます。`failure()` だけだと checkout など別の step の失敗でも「検査が落ちた」issue が立つためです。検査の出力を `tee` で控えて issue 本文に載せるので、tee の終了コードが検査の失敗を隠さないよう `pipefail` も要ります。検査が別ジョブのもの（osv-scanner / scorecard / renovate）は、通知ジョブに `if: ${{ !cancelled() }}` を付けます。既定では前のジョブが落ちると後続がスキップされ、issue が立たないためです。cancelled のように success でも failure でもない結果では issue を開きも閉じもしません。通知ジョブはリポジトリ内のスクリプトを呼ぶので checkout も要ります。

## トークンについて

**既定の `GITHUB_TOKEN` では読めない項目があり、`UNKNOWN` になります**（下の表で Administration が要るもの）。Actions から実行するには、Administration の read を持つ fine-grained PAT を secret `SETTINGS_TOKEN` に登録してください（[作成手順](#settings_token-の作成)）。登録があればワークフローはそちらを使います。

**マージ関連の設定は GraphQL で読んでいます。** REST の `GET /repos/{owner}/{repo}` は、`allow_*` と `squash_merge_commit_title` を書き込み権限が無いと応答に含めません（エラーではなく、フィールドが黙って消えます）。読み取りだけのトークンで確認するため、リポジトリ設定の項目はすべて GraphQL の `Repository` から取っています。

| 項目 | 読み取り方 | 必要な権限 |
| --- | --- | --- |
| リポジトリ設定（マージ関連など） | GraphQL の `Repository` | read で足りる |
| ruleset（一覧と、id ごとの中身） | REST | read で足りる |
| 脆弱性の非公開報告 | REST | read で足りる |
| immutable releases | REST | **Administration: Read-only** |
| Dependabot alerts | REST（本文の無いステータスコード: 204 が有効 / 404 が無効） | **Administration: Read-only** |
| secret scanning の push protection | REST（`security_and_analysis`） | **Administration: Read-only** |
| Actions の `GITHUB_TOKEN` の既定権限 | REST | **Administration: Read-only** |

Dependabot alerts の `404` は admin 権限の無いトークンでも返り（`403` になるのは GitHub App のトークンだけです）、「無効」と区別できません。そのため「無効」と判定するのは呼び出し元に admin 権限があるときだけで、無いときは `UNKNOWN` として報告します。

適用側（引数なしの実行）は REST の `PATCH` を使います。こちらは admin 権限のある本人が手元から動かすため問題になりません。

**「定義とずれている」と「権限が足りなくて確認できない」は分けて報告します。** 直し方が違うためです。前者はスクリプトを引数なしで実行し、後者はトークンを変えます。

```text
  OK      allow_auto_merge = true
  DRIFT   squash_merge_commit_title = COMMIT_OR_PR_TITLE (expected: PR_TITLE)
  DRIFT   ruleset main: rule required_linear_history is missing
  UNKNOWN immutable-releases (cannot be fetched)
```

### `SETTINGS_TOKEN` の作成

発行するのは fine-grained PAT です。PAT を発行する API は無いので、作成はブラウザで行います。

1. [Settings > Developer settings > Personal access tokens > Fine-grained tokens](https://github.com/settings/personal-access-tokens/new) を開く
2. 次の内容で作成する

    | 項目 | 値 |
    | --- | --- |
    | Token name | `repo-settings (OWNER/REPO)` など、用途が分かる名前 |
    | Resource owner | リポジトリの所有者（Organization の場合は組織側の承認が必要なことがあります） |
    | Expiration | 運用に合わせて。切れると検査が `UNKNOWN` で落ち、issue が立ちます |
    | Repository access | Only select repositories → 対象のリポジトリ |

3. Repository permissions で `Administration: Read-only` だけを与える（`Metadata: Read-only` は自動で付きます）。**書き込み権限は 1 つも要りません。** このワークフローは読み取りしかせず、設定の適用は手元からスクリプトを実行して行います。

4. 表示されたトークンをコピーし、secret に登録する（値はプロンプトに貼り付けます）

    ```bash
    gh secret set SETTINGS_TOKEN
    ```

5. 実際に動かして確認する

    ```bash
    gh workflow run repo-settings.yml
    gh run watch
    ```

GitHub の権限と応答フィールドの対応は文書化されていないため、`UNKNOWN` が残る場合はこの権限を見直してください（何が読めていないかは検査の出力に出ます）。
