FROM node:26.8.1-trixie@sha256:f5d1cc40abc10c2843339a2134d07817cf33c405cb16bfd052b0ed790254c3a3

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

# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION=11.25.0

RUN npm install -g pnpm@${PNPM_VERSION}

RUN mkdir -p /workspace/web/node_modules \
  && chown -R ${USER_NAME}:${USER_NAME} /workspace \
  && mkdir -p ${PNPM_HOME}/store \
  && chown -R ${USER_NAME}:${USER_NAME} ${PNPM_HOME}

USER ${USER_NAME}

RUN pnpm config set --global store-dir "${PNPM_HOME}/store"
