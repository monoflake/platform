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

# Static, against musl, so the image needs nothing but the binary. The target follows the platform
# being built, so one Dockerfile serves an arm64 node and an x86 one.
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
	&& cargo build --profile container --locked --target "$target" -p geo \
	&& cp "target/$target/container/geo" /geo \
	&& if [ -n "${RUSTC_WRAPPER:-}" ]; then sccache --show-stats || true; fi

# GeoNames, fetched as the image is built, as GeoLite2 is below, so the data is as new as the
# build. `ADD` of a URL is cached by the server's ETag, so an unchanged file is not fetched again
# and a changed one is. web's `mise run geo` exports the data stage for local work, so these
# addresses are the only copy.
FROM debian:trixie-slim AS fetch
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends unzip \
	&& rm -rf /var/lib/apt/lists/*
ADD https://download.geonames.org/export/dump/cities500.zip /fetch/
ADD https://download.geonames.org/export/zip/allCountries.zip /fetch/
ADD https://download.geonames.org/export/dump/admin1CodesASCII.txt /geo/
ADD https://download.geonames.org/export/dump/admin2Codes.txt /geo/
ADD https://download.geonames.org/export/dump/countryInfo.txt /geo/
# A URL's file arrives mode 600, and the service reads it as 65532.
RUN unzip -q /fetch/cities500.zip -d /geo \
	&& unzip -q -p /fetch/allCountries.zip allCountries.txt > /geo/postal.txt \
	&& chmod 0644 /geo/*

FROM scratch AS data
COPY --from=fetch /geo /

# The text turned into the place index geo maps, by geo itself; the text stays behind. See
# spec/architecture/geo.md, "Both lookups are files laid out for asking, and the page cache keeps
# them".
FROM debian:trixie-slim AS index
COPY --from=build /geo /geo
RUN --mount=type=bind,from=data,target=/source /geo index /source /index

FROM scratch
COPY --from=build /geo /geo
# Read-only data traveling with the binary, so every copy of the service is whole.
COPY --from=index /index /data
# GeoLite2 beside it, as a mirror republishes MaxMind's files without a license key, so geo asks
# the network for nothing while it runs. A URL's file arrives mode 600, and the service reads it as
# 65532. See spec/architecture/geo.md, "GeoLite2 is fetched as the image is built".
ADD --chmod=0644 \
	https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb \
	https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-ASN.mmdb \
	/data/
# Not root: nothing here needs to be, and scratch has no user table, so it is named by number.
USER 65532:65532
ENTRYPOINT ["/geo"]
