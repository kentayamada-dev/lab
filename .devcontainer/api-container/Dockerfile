# タグは中身が変わりうるため digest で固定する（タグは読みやすさのため残す）。https://docs.renovatebot.com/docker/
# digest は amd64・arm64 を含む manifest list のもの。アーキテクチャ別の digest だと片方でしか動かない。
FROM golang:1.27.1-trixie@sha256:3b77fc618ec235a1ab412de7737f120dd507c57e8d87de4cbb7994fb94275ed5

# USERNAME にしないのは、hadolint DL3064 が username を機密値の疑いとして検出し CI が落ちるため。
# https://github.com/hadolint/hadolint/blob/master/src/Hadolint/Rule/DL3064.hs
ARG DEV_USER=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# --shell を省くとログインシェルが dash になり、VS Code のターミナルで .bashrc が読まれないため明示する（trixie で実測）。
# https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
RUN groupadd --gid $USER_GID $DEV_USER \
  && useradd --uid $USER_UID --gid $USER_GID --shell /bin/bash -m $DEV_USER

# gopls が無いと Go 拡張は legacy mode に落ち、拡張が自分で入れても再ビルドで消えるためイメージに入れる。
# gofumpt・staticcheck は gopls 内蔵のものを使う（devcontainer.json）。
# https://github.com/golang/vscode-go/blob/master/docs/tools.md
#
# 版は customManagers:dockerfileVersions が次行の注記で追う。<名前>_VERSION の形から変数名を変えない。
# renovate: datasource=go depName=golang.org/x/tools/gopls
ARG GOPLS_VERSION=v0.23.0

# /go/bin は PATH 上で権限が 1777 かつ home の外なので、dev ユーザーから使え、/home へのマウントでも隠れない。
# go clean はツール導入時だけのキャッシュを消してイメージを小さくするため。
RUN go install "golang.org/x/tools/gopls@${GOPLS_VERSION}" \
  && go clean -cache -modcache

# 理由は web-container の Dockerfile と同じ（compose で同じく /workspace にマウントする）
RUN git config --system --add safe.directory /workspace

USER $DEV_USER
