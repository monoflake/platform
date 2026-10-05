# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# grok2api and a seed copy of the Grok CLI. The CLI that runs is the one on the /data volume, which
# grok2api keeps up to date itself; the seed is only for a volume that has none yet. Built from the
# repository root by `mise run host`, which reads RUST_VERSION from the workspace's
# rust-toolchain.toml. See spec/architecture/grok/deployment.md.
ARG RUST_VERSION

FROM rust:${RUST_VERSION}-slim-trixie AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY apps apps
COPY libs libs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	cargo build --profile container --locked -p grok \
	&& cp target/container/grok2api /grok2api

# Whichever version the stable channel names when the image is built, for the platform it is
# built for. Run once here so a binary that does not start fails the build, not the first boot.
FROM debian:trixie-slim AS seed
ARG TARGETARCH
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/*
RUN case "$TARGETARCH" in \
		arm64) platform=linux-aarch64 ;; \
		amd64) platform=linux-x86_64 ;; \
		*) echo "no Grok CLI is published for $TARGETARCH" >&2; exit 1 ;; \
	esac \
	&& version="$(curl -fsSL https://x.ai/cli/stable | head -n1 | tr -d '[:space:]')" \
	&& curl -fsSL "https://x.ai/cli/grok-${version}-${platform}" -o /grok \
	&& chmod 755 /grok \
	&& /grok --version

# Debian rather than scratch: the CLI is a binary of xAI's, and grok2api's own HTTPS, fetching newer
# CLIs, verifies against the system's certificates.
FROM debian:trixie-slim
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir /data \
	&& chown 65532:65532 /data
COPY --from=seed /grok /usr/local/lib/grok2api/grok
COPY --from=build /grok2api /usr/local/bin/grok2api
ENV GROK2API_DATA_DIR=/data GROK2API_PORT=20840 HOME=/data
# Not root: nothing here needs to be, and host gives /data to the user the image names.
USER 65532:65532
ENTRYPOINT ["grok2api"]
