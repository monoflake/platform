# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# Built from the repository root by `mise run host`. RUST_VERSION has no default on purpose, which
# is the check skipped above: the task reads it from the workspace's rust-toolchain.toml.
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

# rclone from its release, a static binary, checked against the sum the release publishes, in a
# stage for each architecture; unpacked below with the CA bundle it verifies the backup store by.
FROM scratch AS rclone-arm64
ADD --checksum=sha256:03f2504174034b6d004152ed7369251c9a9ec1f7e0836eda420f5c7a5ec0dff9 \
	https://github.com/rclone/rclone/releases/download/v1.75.1/rclone-v1.75.1-linux-arm64.zip /rclone.zip
FROM scratch AS rclone-amd64
ADD --checksum=sha256:982b5aa772841168f8e380f139e9e787b2a105403e32b94da8676a0e1c0a13ab \
	https://github.com/rclone/rclone/releases/download/v1.75.1/rclone-v1.75.1-linux-amd64.zip /rclone.zip
FROM rclone-${TARGETARCH} AS rclone-zip
FROM debian:trixie-slim AS rclone
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends unzip ca-certificates \
	&& rm -rf /var/lib/apt/lists/*
RUN --mount=from=rclone-zip,target=/zip \
	unzip -j /zip/rclone.zip '*/rclone' -d /usr/local/bin \
	&& /usr/local/bin/rclone version

# The store, static, against musl, as meter and geo are.
FROM rust:${RUST_VERSION}-slim-trixie AS build
ARG TARGETARCH
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends musl-tools \
	&& rm -rf /var/lib/apt/lists/*
RUN --mount=from=sccache,target=/sccache \
	tar -xzf /sccache/sccache.tar.gz -C /usr/local/bin --strip-components=1 --no-same-owner \
		--wildcards '*/sccache'
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY apps apps
COPY libs libs
# CFLAGS compiles mimalloc with transparent huge pages off; see infra's
# spec/architecture/host.md, "An image is built for speed, and for any node of its architecture".
# sccache's backend comes in as the secret `sccache` from .mise/tasks/image, else it is the cache
# mount, and rustc runs alone when its server cannot start; the same section covers sccache.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	--mount=type=cache,target=/var/cache/sccache,sharing=locked \
	--mount=type=secret,id=sccache \
	case "$TARGETARCH" in arm64) arch=aarch64 ;; amd64) arch=x86_64 ;; *) exit 1 ;; esac \
	&& target="$arch-unknown-linux-musl" \
	&& rustup target add "$target" \
	&& export "CC_${arch}_unknown_linux_musl=musl-gcc" \
	&& export "CFLAGS_${arch}_unknown_linux_musl=-DMI_DEFAULT_ALLOW_THP=0" \
	&& export SCCACHE_DIR=/var/cache/sccache SCCACHE_IDLE_TIMEOUT=0 \
	&& if [ -f /run/secrets/sccache ]; then . /run/secrets/sccache; fi \
	&& if sccache --start-server; then export RUSTC_WRAPPER=sccache; fi \
	&& cargo build --profile container --locked --target "$target" -p store \
	&& cp "target/$target/container/store" /store \
	&& if [ -n "${RUSTC_WRAPPER:-}" ]; then sccache --show-stats || true; fi

FROM scratch
COPY --from=rclone /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=build /store /store
ENV STORE_DATA=/data
# Nobody in particular, by number; host gives the app's directory to this user.
USER 65532:65532
ENTRYPOINT ["/store"]
