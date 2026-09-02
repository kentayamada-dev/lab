# セキュリティポリシー

## 報告先

**脆弱性を公開の issue や Discussions に書かないでください。** 修正が無い状態で詳細が出ると、攻撃の手順書を配ることになります。

報告は GitHub の**プライベート脆弱性報告**で受け付けます。リポジトリの **Security** タブにある **Report a vulnerability** から、フォームに記入して送信してください。やり取りは報告者とメンテナだけが見られる非公開のアドバイザリ上で行い、修正が出た時点でアドバイザリを公開します。

**Report a vulnerability が見つからない場合**、プライベート報告が有効になっていません（[セットアップ](README.md#セットアップ)のスクリプトが有効化します）。詳細は書かず、セキュリティの件で連絡したい旨だけを書いた issue を立ててください。

参考: [プライベートに脆弱性を報告する](https://docs.github.com/ja/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)

## 報告に書くこと

分かっている範囲で構いません。再現手順があると調査が早くなります。

- 対象の箇所（ワークフロー、スクリプト、設定ファイルなど）
- 再現手順、または攻撃が成立する条件
- 想定される影響（何が読める / 書ける / 実行できるようになるか）
- 確認した環境（OS、ツールのバージョン、コミット SHA）
- 把握している回避策や修正案（あれば）

## 対象の範囲

範囲は**このリポジトリに入っているもの**です（[収録内容](README.md#収録内容)の一覧がそのまま範囲です）。

| 区分 | 内容 |
| --- | --- |
| 対象 | アプリコード（api/ web/ proto/ db/）の脆弱性、ワークフローの権限の与えすぎ、`run` へのインジェクション、secret の漏洩、スクリプトの危険な挙動 |
| 対象外 | 依存するライブラリ・ツール・action の脆弱性（上流へ報告してください。修正はバージョン更新で取り込みます） |
| 対象外 | Security タブに既にアラートとして出ているもの |

## サポート対象のバージョン

**main の最新コミットのみ**です。過去のコミットやリリースへの修正の取り込みは行いません。

返信時期の約束はできません。2 週間返信が無い場合は、同じ経路で催促してください。

## 自動の検査

報告の前に、既に検出済みかどうかをここで確認できます。検出結果は Security タブの Code scanning に出ます。セキュリティ関連の検査は [CodeQL](docs/ci-jobs.md#codeql)、[ghalint](docs/ci-jobs.md#ghalint)、[zizmor](docs/ci-jobs.md#zizmor)、[gitleaks](docs/ci-jobs.md#gitleaks)、[osv-scanner](docs/ci-jobs.md#osv-scanner)、[Scorecard](docs/ci-jobs.md#scorecard) で、それぞれが何を見るかは [CI の検査ジョブ](docs/ci-jobs.md#ci-の検査ジョブ)にあります。

これらの検査が拾うのは既知のパターンと既知の脆弱性だけです。設計上の欠陥や運用上の穴はそのまま通り抜けるので、気づいた場合は上記の経路で知らせてください。
