FROM golang:1.26.6-trixie AS base

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

FROM golang:1.26.6-trixie AS gopls

ARG GOPLS_VERSION=latest

RUN GOBIN=/out go install golang.org/x/tools/gopls@${GOPLS_VERSION}

FROM base AS dev

COPY --from=gopls /out/gopls /usr/local/bin/gopls
