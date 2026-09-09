FROM golang:1.27.1-trixie@sha256:9baa6b4187bbb98d240372a8a235ac0bb6b5ddd52bba1431dc2f7c0705862728 AS base

ARG USER_NAME
ARG USER_UID
ARG USER_GID

COPY common/create-user.sh /tmp/
RUN sh /tmp/create-user.sh "${USER_NAME}" "${USER_UID}" "${USER_GID}" \
  && rm -f /tmp/*.sh

ENV GOCACHE=/go/cache

RUN mkdir -p /go/pkg/mod /go/cache \
  && chown -R ${USER_NAME}:${USER_NAME} /go

USER ${USER_NAME}

FROM golang:1.27.1-trixie@sha256:9baa6b4187bbb98d240372a8a235ac0bb6b5ddd52bba1431dc2f7c0705862728 AS gopls

# renovate: datasource=go depName=golang.org/x/tools/gopls
ARG GOPLS_VERSION=v0.23.0

RUN GOBIN=/out go install golang.org/x/tools/gopls@${GOPLS_VERSION}

FROM base AS dev

ARG USER_NAME

COPY --from=gopls /out/gopls /usr/local/bin/gopls

# Docker Desktop leaves the /workspace mount point itself owned by root while
# the repository under it belongs to ${USER_NAME}, so git reads the worktree as
# someone else's and refuses to run ("detected dubious ownership", exit 128),
# which in turn breaks go's VCS stamping. Only the bind mount from a macOS host
# does this, so the exception stays in this stage instead of base.
USER root
RUN git config --system --add safe.directory /workspace
USER ${USER_NAME}
