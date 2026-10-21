# wasmtime, the WebAssembly component runtime the machine driver runs in a container, RFC vr5lw.
ARG WASMTIME_VERSION=49.0.4
ARG WASMTIME_SHA256_AMD64=6561abd54bdf941b6519cce883e0857cc9bce94d92c65287ed838d895a27f5a9
ARG WASMTIME_SHA256_ARM64=9c1a6298dfb0df3b1249b531375dfb9d0d3eb0f1e1959982e3bc767251eb705d

FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@sha256:42a9ff19af33811ee466b24c66384461d37c32dcc28d1d27d49b8aca816bd5ee AS fetch-amd64
ARG WASMTIME_VERSION
ARG WASMTIME_SHA256_AMD64
ADD --checksum=sha256:${WASMTIME_SHA256_AMD64} https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/wasmtime-v${WASMTIME_VERSION}-x86_64-linux.tar.xz /wasmtime.tar.xz

FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@sha256:42a9ff19af33811ee466b24c66384461d37c32dcc28d1d27d49b8aca816bd5ee AS fetch-arm64
ARG WASMTIME_VERSION
ARG WASMTIME_SHA256_ARM64
ADD --checksum=sha256:${WASMTIME_SHA256_ARM64} https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/wasmtime-v${WASMTIME_VERSION}-aarch64-linux.tar.xz /wasmtime.tar.xz

FROM fetch-${TARGETARCH} AS fetch
RUN mkdir /out && tar -xJf /wasmtime.tar.xz -C /out && mv /out/*/wasmtime /wasmtime

FROM gcr.io/distroless/cc-debian13:nonroot@sha256:b7e81cb1af38d9345680e68bcf564d388f96304e25222030fc8c051faf8565b3
ARG WASMTIME_VERSION
LABEL org.opencontainers.image.version=${WASMTIME_VERSION}
COPY --from=fetch --chmod=0755 /wasmtime /usr/local/bin/wasmtime
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/wasmtime"]
