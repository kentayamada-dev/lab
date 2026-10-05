# タグは中身が変わりうるため digest で固定する（タグは読みやすさのため残す）。https://docs.renovatebot.com/docker/
# digest は amd64・arm64 を含む manifest list のもの。アーキテクチャ別の digest だと片方でしか動かない。
FROM node:26.10.0-trixie@sha256:a723b54c35a76e947095a20a67d39585bb09c862e6b1adeb8a9f518f95e34fb0

# 名前の理由は api-container の Dockerfile と同じ（hadolint DL3064）
ARG DEV_USER=dev

# 公式イメージには UID/GID 1000 の node ユーザーがあり同じ UID で dev を作れないため、改名して api と揃える。
# UID/GID が 1000 から変わるとマウントしたファイルの所有者がずれるため、そのときはビルドを止める。
# https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md#non-root-user
RUN test "$(id -u node):$(id -g node)" = "1000:1000" \
  && groupmod --new-name $DEV_USER node \
  && usermod --login $DEV_USER --home /home/$DEV_USER --move-home node

# compose が node_modules にマウントする空の named volume は、イメージに無いパスだと root 所有になり dev が書き込めない。
# パスは compose の volumes と揃える
RUN mkdir -p /workspace/web/node_modules \
  && chown $DEV_USER:$DEV_USER /workspace/web/node_modules

# Docker Desktop for Mac ではマウント直下の /workspace が一時的に root 所有に見え、git が dubious ownership で止まる。
# https://github.com/docker/desktop-feedback/issues/628
# ~/.gitconfig は Dev Containers がホストから持ち込むため system に書く。
# https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials
RUN git config --system --add safe.directory /workspace

USER $DEV_USER

# 版は customManagers:dockerfileVersions が次行の注記で追う。<名前>_VERSION の形から変数名を変えない。
# renovate: datasource=npm depName=get-pnpm
ARG GET_PNPM_VERSION=0.0.5
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION=12.8.2

# pnpm setup は PATH を .bashrc にしか書かず、非対話シェル（docker compose exec など）で pnpm が見つからないため ENV でも通す
ENV PNPM_HOME=/home/$DEV_USER/.local/share/pnpm
ENV PATH=$PNPM_HOME/bin:$PATH

# 公式の npm 経由の手順。get-pnpm は npm の署名でダウンロードを検証してから pnpm setup に渡す。
# SHELL が無いと pnpm setup が ERR_PNPM_UNKNOWN_SHELL で止まる。https://pnpm.io/installation#using-npm
RUN SHELL=/bin/bash npx --yes "get-pnpm@${GET_PNPM_VERSION}" "${PNPM_VERSION}" \
  && rm -rf ~/.npm

# 明示しないと、ホームとファイルシステムが違う /workspace の直下にストア（.pnpm-store）が作られる。https://pnpm.io/settings/store#storedir
# 先に作っておくのは、compose がマウントする空の named volume にこのディレクトリの所有者（dev）を引き継がせるため
RUN mkdir -p "$PNPM_HOME/store" \
  && pnpm config set --location=global storeDir "$PNPM_HOME/store"
