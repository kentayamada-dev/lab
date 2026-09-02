FROM golang:1.27.1-trixie@sha256:137ca8442e368f5f5bb4d4f84d8cc1f6c2d898edf8a380459eb407f89d149b0d AS base

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

FROM golang:1.27.1-trixie@sha256:137ca8442e368f5f5bb4d4f84d8cc1f6c2d898edf8a380459eb407f89d149b0d AS gopls

# renovate: datasource=go depName=golang.org/x/tools/gopls
ARG GOPLS_VERSION=v0.23.0

RUN GOBIN=/out go install golang.org/x/tools/gopls@${GOPLS_VERSION}

FROM base AS dev

COPY --from=gopls /out/gopls /usr/local/bin/gopls
