# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# grok2api and a seed copy of the Grok CLI. The CLI that runs is the one on the /data volume, which
# grok2api keeps up to date itself; the seed is only for a volume that has none yet. Built from the
# repository root by `mise run host`, which reads RUST_VERSION from the workspace's
# rust-toolchain.toml. See spec/architecture/grok/deployment.md.
ARG RUST_VERSION

# sccache, the compiler cache the build runs rustc through: the static binary from its release,
# checked against the sum the release publishes, in a stage for each architecture.
FROM scratch AS sccache-arm64
ADD --checksum=sha256:2b3284d5da3b46a47dc4229e75bb7b88ac4aa99c8d754fb7d2f84997e5a4354a \
	https://github.com/mozilla/sccache/releases/download/v0.18.0/sccache-v0.18.0-aarch64-unknown-linux-musl.tar.gz /sccache.tar.gz
FROM scratch AS sccache-amd64
ADD --checksum=sha256:45f1447fbe231e3037bde351ef70677dd212216c8d62ae7ca409fecc4d6acc89 \
	https://github.com/mozilla/sccache/releases/download/v0.18.0/sccache-v0.18.0-x86_64-unknown-linux-musl.tar.gz /sccache.tar.gz
FROM sccache-${TARGETARCH} AS sccache

FROM rust:${RUST_VERSION}-slim-trixie AS build
RUN --mount=from=sccache,target=/sccache \
	tar -xzf /sccache/sccache.tar.gz -C /usr/local/bin --strip-components=1 --no-same-owner \
		--wildcards '*/sccache'
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY apps apps
COPY libs libs
# sccache's backend comes in as the secret `sccache` from .mise/tasks/image, else it is the cache
# mount, and rustc runs alone when its server cannot start; see infra's spec/architecture/host.md,
# "An image is built for speed, and for any node of its architecture".
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	--mount=type=cache,target=/var/cache/sccache,sharing=locked \
	--mount=type=secret,id=sccache \
	export SCCACHE_DIR=/var/cache/sccache SCCACHE_IDLE_TIMEOUT=0 \
	&& if [ -f /run/secrets/sccache ]; then . /run/secrets/sccache; fi \
	&& if sccache --start-server; then export RUSTC_WRAPPER=sccache; fi \
	&& cargo build --profile container --locked -p grok \
	&& cp target/container/grok2api /grok2api \
	&& if [ -n "${RUSTC_WRAPPER:-}" ]; then sccache --show-stats || true; fi

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
