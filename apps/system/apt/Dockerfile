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

# Static, against musl, as meter and geo are.
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
	&& cargo build --profile container --locked --target "$target" -p apt \
	&& cp "target/$target/container/apt" /apt \
	&& if [ -n "${RUSTC_WRAPPER:-}" ]; then sccache --show-stats || true; fi

FROM scratch
COPY --from=build /apt /apt
ENV APT_DATA=/data
# scratch has no /var/run -> /run symlink, so zbus's default system-bus lookup is pointed at the
# path the machine's socket is mounted to. See spec/architecture/apt.md, "The door".
ENV DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
# Root, and only for systemd's sake: the bus lets a unit be started only from there. No other
# capability is asked for, and the root filesystem stays host's to make read-only. See
# spec/architecture/apt.md, "The door".
ENTRYPOINT ["/apt"]
