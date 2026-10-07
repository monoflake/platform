# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom,SecretsUsedInArgOrEnv
# Built from the repository root by `mise run host`. RUST_VERSION has no default on purpose, which
# is the check skipped above: the task reads it from the workspace's rust-toolchain.toml.
# The second skip is WALG_LIBSODIUM_KEY_TRANSFORM, named like a secret and not one.
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

# WAL-G for Postgres from its release, built against Ubuntu 24.04's glibc, which trixie's is newer
# than; checked against the sum the release publishes, in a stage for each architecture.
FROM scratch AS walg-arm64
ADD --checksum=sha256:cb37c5f8391bd8ef2efceeb9c6995059c0abf2fa74b9b717b42a16a7c93cfde1 \
	https://github.com/wal-g/wal-g/releases/download/v3.0.9/wal-g-pg-24.04-aarch64.tar.gz /wal-g.tar.gz
FROM scratch AS walg-amd64
ADD --checksum=sha256:444ce216230c254edef803e098a59a1746806da3e0d55671d7b0f0082db14ef4 \
	https://github.com/wal-g/wal-g/releases/download/v3.0.9/wal-g-pg-24.04-amd64.tar.gz /wal-g.tar.gz
FROM walg-${TARGETARCH} AS walg

# The keeper, static, against musl, as meter and geo are.
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
	&& cargo build --profile container --locked --target "$target" -p database \
	&& cp "target/$target/container/database" /database \
	&& if [ -n "${RUSTC_WRAPPER:-}" ]; then sccache --show-stats || true; fi

# The official image at a pinned major and digest, Debian's, since WAL-G's binaries are glibc's. A
# new major is a dump and restore, never this line alone. See spec/architecture/databases.md.
FROM postgres:18-trixie@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336
# Fails the build here, not a node later, if the binary cannot load on this image's libraries.
RUN --mount=from=walg,target=/walg \
	tar -xzf /walg/wal-g.tar.gz -C /usr/local/bin --no-same-owner --transform 's|.*|wal-g|' \
	&& wal-g --version
COPY --from=build /database /usr/local/bin/database
# The socket and the configuration each start writes go to the scratch tmpfs, which psql and WAL-G
# then find on their own; the key is the 64 hex digits `mise run database env` makes.
ENV PGDATA=/var/lib/postgresql/data \
	PGHOST=/tmp \
	PGUSER=postgres \
	PGDATABASE=postgres \
	WALG_LIBSODIUM_KEY_TRANSFORM=hex \
	AWS_S3_FORCE_PATH_STYLE=true
# The image's `postgres`, by number; host gives the app's directory to this user.
USER 999:999
ENTRYPOINT ["/usr/local/bin/database"]
