# 設定のずれの検査

[English](drift-check.md) | **日本語**

[セットアップ](../README.ja.md#セットアップ)のスクリプトが入れる設定は、GitHub の画面からいつでも変えられます。変えられても、スクリプトに設定を足したまま再実行を忘れても、`ci` は緑のままです。そこで [repo-settings.yml](../.github/workflows/repo-settings.yml) が毎日（07:00 JST）と main への push 時に `--check` を実行し、現在の設定が定義とずれていれば落ちます。

```bash
./scripts/sync-repo-config.sh --check
```

| 見るもの | 判定 |
| --- | --- |
| リポジトリ設定（auto-merge / マージ方式 / squash タイトル / Issues など） | 値が定義と一致するか |
| immutable releases / 脆弱性の非公開報告 / Dependabot alerts | 有効になっているか |
| secret scanning の push protection | 有効になっているか |
| Actions の `GITHUB_TOKEN` の既定権限（read 固定 / PR の作成・承認の禁止） | 値が定義と一致するか |
| ラベル（[ラベル](../README.ja.md#ラベル)の 4 つ） | **同じ名前のものが存在するか** |
| ruleset（`.github/rulesets/*.json` の各ファイル） | enforcement・対象・bypass actor の数・全ルールの中身が定義と一致するか |

ruleset で突き合わせるのは定義に書いた項目だけです。API は `id` や `created_at`、後から GitHub が増やすパラメータを自分で足してくるので、それらをずれとして扱うと GitHub 側の追加のたびに落ちてしまいます。配列は比較前に整列させます。送った順序で返る保証がないためです。定義に無いルールは `unexpected rule` として報告するので、UI で足されたルールも捕まえられます。

**ラベルは今も存在までしか見ません。** UI で色や説明を書き換えられても検出しません（名前の変更・削除は「存在しない」として検出します）。

期待値は[スクリプト](../scripts/sync-repo-config.sh)の `REPO_SETTINGS_EXPECTED` / `REPO_SETTINGS_ENDPOINTS` / `SECURITY_ANALYSIS_EXPECTED` / `ACTIONS_WORKFLOW_EXPECTED` / `LABELS_EXPECTED` にあり、適用と確認の両方がそこを読むため、片方だけ直って食い違うことは起きません。設定を増やすときもここに 1 行足すだけで、`--check` と `--dry-run` の対象に自動的に入ります。

`REPO_SETTINGS=false` を付けた場合、リポジトリ設定の確認は飛ばして ruleset だけを見ます。ずれていたら、引数なしで実行すれば適用されます。

```bash
./scripts/sync-repo-config.sh
```

## 落ちたときの通知

**検査が落ちると issue が立ちます。** 定期実行の失敗は Actions の画面か通知メールでしか分からず、見落とすとずれたまま運用が続いてしまうためです。

issue は `Repository settings have drifted` というタイトルで `maintenance` ラベル付きで立ち（[ラベル](../README.ja.md#ラベル)）、本文に検査の出力と実行ログの URL、直し方が入ります。すでに同じ issue が open の間は作り直さずに最新の検査の出力をコメントで追記し、検査が通れば自動的に閉じます。

issue の作成・コメント・close はワークフローの `GITHUB_TOKEN`（`issues: write`）で行います。`SETTINGS_TOKEN` は読み取り専用のままで構いません。

## ci.yml と分けている理由

この検査は「コードを変えていなくても結果が変わる」ため、`ci` の必須チェックには入れていません。必須にすると、誰かが設定を触った時点で無関係な PR まで止まります。[osv-scanner](ci-jobs.ja.md#osv-scanner) を 2 層に分けているのと同じ考え方です。

## トークンについて

**既定の `GITHUB_TOKEN` では immutable releases と Dependabot alerts、secret scanning の push protection、Actions の既定権限を読めず、`UNKNOWN` になります**。Actions から実行するには、Administration の read を持つ fine-grained PAT を secret `SETTINGS_TOKEN` に登録してください。登録があればワークフローはそちらを使います。

```bash
gh secret set SETTINGS_TOKEN
```

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

Dependabot alerts の `404` は admin 権限の無いトークンでも返り、「無効」と区別できません。そのため「無効」と判定するのは呼び出し元に admin 権限があるときだけで、無いときは `UNKNOWN` として報告します。

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
