# devcontainer を開くためのターゲット。vscli が devcontainer.json を読んで VS Code の dev container 用の
# URI を組み立て、`code --folder-uri <URI>` を呼ぶ。コンテナの起動と VS Code の接続はその先の
# Dev Containers 拡張が行うため、ここで docker compose を直接叩く必要はない。
# https://github.com/michidk/vscli

# 同名のファイルが出来てもターゲットが動かなくならないよう、実体を持たないターゲットとして宣言する
.PHONY: dev-api

# api コンテナ（.devcontainer/api-container）を VS Code で開く。
#
# --config を絶対パスにしているのは、vscli 1.3.3 が相対パスを正しく URI に載せられないため。
# `--config .devcontainer/api-container/devcontainer.json` を渡すと、URI の中の configFile が
# authority ".devcontainer" と path "/api-container/devcontainer.json" に分解され、
# 先頭のディレクトリ名が authority に吸われてパスが壊れる（--dry-run で実測。絶対パスを渡した場合は
# scheme "file" と完全なパスになることも同じく実測）。
#
# 開く対象のパス（第1引数）も CURDIR で渡す。相対パスでも vscli が絶対パスに直すが、
# make をどのディレクトリから呼んでも同じリポジトリを開くようにするため揃えている。
# CURDIR は make がカレントディレクトリの絶対パスを入れる変数で、-C で呼んだ場合も
# 移動後のディレクトリを指す（GNU Make 3.81 で実測）。
dev-api:
	vscli open "$(CURDIR)" --config "$(CURDIR)/.devcontainer/api-container/devcontainer.json"
