# vscli が devcontainer.json から URI を組み立てて VS Code を開き、起動は Dev Containers 拡張が行うので compose は直接叩かない。
# https://github.com/michidk/vscli

.PHONY: dev-api dev-web

# 各ターゲットで --config を絶対パスにするのは、vscli 1.3.3 が相対パスだと先頭ディレクトリを URI の authority に取り込んで壊すため
# （--dry-run で実測。上流の issue は未検証）。
# 第1引数も CURDIR にして、-C を含めどこから呼んでも同じリポジトリを開く。
dev-api:
	vscli open "$(CURDIR)" --config "$(CURDIR)/.devcontainer/api-container/devcontainer.json"

dev-web:
	vscli open "$(CURDIR)" --config "$(CURDIR)/.devcontainer/web-container/devcontainer.json"
