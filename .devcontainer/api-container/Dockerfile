FROM golang:1.26.6-trixie@sha256:b75d466dd608587fd66cca705a307ba65b889827d06ad61d6a75f0482b51b7c7 AS base

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

FROM golang:1.26.6-trixie@sha256:b75d466dd608587fd66cca705a307ba65b889827d06ad61d6a75f0482b51b7c7 AS gopls

ARG GOPLS_VERSION=latest

RUN GOBIN=/out go install golang.org/x/tools/gopls@${GOPLS_VERSION}

FROM base AS dev

COPY --from=gopls /out/gopls /usr/local/bin/gopls
