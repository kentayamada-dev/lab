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

USER $DEV_USER
