# syntax=docker/dockerfile:1

ARG GO_IMAGE=golang:1.25.12

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS awg-go-build
ARG TARGETOS
ARG TARGETARCH
ARG AWG_GO_TAG=v3.1.20261116

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${AWG_GO_TAG}" \
    https://github.com/amnezia-vpn/amneziawg-go.git amneziawg-go

WORKDIR /src/amneziawg-go
RUN set -eux; \
    go mod download; \
    go mod verify; \
    tag="$(git describe --tags)"; \
    printf 'package main\n\nconst Version = "%s"\n' "$tag" > version.go; \
    mkdir -p /out; \
    CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}" \
        go build -trimpath -ldflags="-s -w" -o /out/amneziawg-go .

FROM alpine:3.24 AS awg-tools-build
ARG AWG_TOOLS_TAG=v3.1.20260812

RUN apk add --no-cache build-base git linux-headers
WORKDIR /src
RUN git clone --depth 1 --branch "${AWG_TOOLS_TAG}" \
    https://github.com/amnezia-vpn/amneziawg-tools.git amneziawg-tools \
    && cd /src/amneziawg-tools/src \
    && make \
    && mkdir -p /out/usr/bin \
    && cp wg /out/usr/bin/awg \
    && cp wg-quick/linux.bash /out/usr/bin/awg-quick \
    && chmod 0755 /out/usr/bin/awg /out/usr/bin/awg-quick

FROM alpine:3.24
ARG OCI_SOURCE_URL="https://github.com/OWNER/REPOSITORY"

LABEL org.opencontainers.image.title="AmneziaWG low-overhead server" \
      org.opencontainers.image.source="${OCI_SOURCE_URL}" \
      org.opencontainers.image.description="Minimal AmneziaWG 3.1 runtime built from upstream source"

RUN apk add --no-cache bash iproute2 iptables tini \
    && mkdir -p /etc/amnezia/amneziawg \
        /usr/share/licenses/amneziawg-go \
        /usr/share/licenses/amneziawg-tools

COPY --from=awg-go-build /out/amneziawg-go /usr/bin/amneziawg-go
COPY --from=awg-tools-build /out/usr/bin/awg /usr/bin/awg
COPY --from=awg-tools-build /out/usr/bin/awg-quick /usr/bin/awg-quick
COPY LICENSES/amneziawg-go-MIT.txt /usr/share/licenses/amneziawg-go/LICENSE
COPY LICENSES/amneziawg-tools-GPL-2.0.txt /usr/share/licenses/amneziawg-tools/COPYING
COPY entrypoint.sh /usr/local/sbin/awg-entrypoint

RUN chmod 0755 /usr/local/sbin/awg-entrypoint /usr/bin/awg-quick \
    && ln -s /usr/bin/awg /usr/bin/wg \
    && ln -s /usr/bin/awg-quick /usr/bin/wg-quick

ENTRYPOINT ["/sbin/tini", "-g", "--", "/usr/local/sbin/awg-entrypoint"]
