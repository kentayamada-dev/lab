# トラブルシューティング

CI のジョブが落ちた場合は、[CI の検査ジョブ](ci-jobs.md#ci-の検査ジョブ)の表から該当する節を引いてください。

## PR が「必須チェック待ち」で止まる

`ci` という名前のチェックが、期待した報告元から届いていません。ワークフローに `paths` フィルタが付いていないか、ジョブ名が `ci` から変わっていないかを確認します。

Actions は緑なのに待ち続ける場合は、[main.json](../.github/rulesets/main.json) の `integration_id` が実際の報告元と食い違っています。次のコマンドで `ci` の行の `app.id` を確認し、JSON に反映してスクリプトを再実行してください。

```bash
gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[] | "\(.name)\t\(.app.id)\t\(.app.slug)"'
```

## CI は緑なのにマージできない

必須チェック以外に、マージを止める保護が 2 つあります（[ブランチ保護の内容](../README.md#ブランチ保護の内容)）。

- 未解決のレビューコメント。Files changed タブで、自分の PR に自分で付けたものも含めてすべて resolve してください。
- Code scanning のアラート。Security タブの Code scanning を開き、直すか dismiss してください（どの重大度で止まるかは [CodeQL](ci-jobs.md#codeql)）。

## Renovate の PR が作られない

Actions タブの `renovate` ワークフローの実行ログを見ます。`RENOVATE_TOKEN` の未設定・期限切れ・権限不足がほとんどです。ログだけで分からない場合は詳細ログを出します（[Renovate](renovate.md#renovate)）。

実行は成功しているのに PR が来ないときは、`Dependency updates are available` の issue を見ます（[更新の一覧の issue](renovate.md#更新の一覧の-issue)）。立っていなければ、前回の実行の時点で更新が無かったということです（並列 PR 上限は外してあるので、保留されているだけということはありません）。

## osv-scanner の定期実行が動かない

Actions タブで `osv-scanner` ワークフローが無効化されていないか確認してください（[定期実行が止まるとき](ci-jobs.md#定期実行が止まるとき)）。

実行はされているのに何も検出されない場合は、run ログでどの lockfile が読まれたかを確認します。1 件も読めていなければジョブ自体が落ちる設定です（[詳細](ci-jobs.md#検査対象の-lockfile)）。

## PR に灰色の `osv-scanner` が出る

`1 configuration not found` という警告です。正常な状態で、マージも止まりません。理由と、消さずに残している理由は [PR に出る「1 configuration not found」](ci-jobs.md#pr-に出る1-configuration-not-found)にあります。

## CI が壊れて main を直せない

[main.json](../.github/rulesets/main.json) の `enforcement` を `disabled` にしてスクリプトを再実行すれば一時的に保護を外せます。復旧後に `active` へ戻してください。
