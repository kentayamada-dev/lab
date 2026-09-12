FROM node:26.8.2-trixie@sha256:fb192b8ad31841aadc4bb79c44ae0f59d193a798ffbc9fdce37ba6ecb20c2236

ARG USER_NAME
ARG USER_UID
ARG USER_GID

COPY common/create-user.sh /tmp/
RUN sh /tmp/create-user.sh "${USER_NAME}" "${USER_UID}" "${USER_GID}" \
  && rm -f /tmp/*.sh

# pnpm resolves its global bin directory to ${PNPM_HOME}/bin and refuses
# global operations (including `pnpm config set --global`) when it is not in
# PATH, so both directories go in.
ENV PNPM_HOME=/pnpm \
  PATH=/pnpm/bin:/pnpm:$PATH

# The standalone build from the official pnpm image; a digest-pinned image is
# the only pnpm install that Scorecard's Pinned-Dependencies accepts (npm install
# has no hash to pin to). The executable loads dist/ relative to itself, so the
# whole directory comes along and only the symlink goes in PATH.
COPY --from=ghcr.io/pnpm/pnpm:12.4.1@sha256:f37ab4b175b5b3bcd8f7334287f908959b09a849b73d5e13678d9fa70ffdb246 /opt/pnpm /opt/pnpm
RUN ln -s /opt/pnpm/pnpm /usr/local/bin/pnpm

RUN mkdir -p /workspace/web/node_modules \
  && chown -R ${USER_NAME}:${USER_NAME} /workspace \
  && mkdir -p ${PNPM_HOME}/store \
  && chown -R ${USER_NAME}:${USER_NAME} ${PNPM_HOME}

# Why git needs this for the bind-mounted worktree: the same setting in
# ../api-container/Dockerfile
RUN git config --system --add safe.directory /workspace

USER ${USER_NAME}

RUN pnpm config set --global store-dir "${PNPM_HOME}/store"
