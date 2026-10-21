# workerd, the V8 isolate runtime the machine driver runs in a container, RFC vr5lw.
ARG WORKERD_VERSION=1.20261019.1
ARG WORKERD_SHA256_AMD64=fa610c47dc53a09eae0082c81a8f03a5d224d474a5b407bfe5603f6d0087201d
ARG WORKERD_SHA256_ARM64=2a5550cec11f79a5393d87b65887bdf27f35e7fcba485a76e2bc7b3720d5c637

FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@sha256:42a9ff19af33811ee466b24c66384461d37c32dcc28d1d27d49b8aca816bd5ee AS fetch-amd64
ARG WORKERD_VERSION
ARG WORKERD_SHA256_AMD64
ADD --checksum=sha256:${WORKERD_SHA256_AMD64} https://registry.npmjs.org/@cloudflare/workerd-linux-64/-/workerd-linux-64-${WORKERD_VERSION}.tgz /workerd.tgz

FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@sha256:42a9ff19af33811ee466b24c66384461d37c32dcc28d1d27d49b8aca816bd5ee AS fetch-arm64
ARG WORKERD_VERSION
ARG WORKERD_SHA256_ARM64
ADD --checksum=sha256:${WORKERD_SHA256_ARM64} https://registry.npmjs.org/@cloudflare/workerd-linux-arm64/-/workerd-linux-arm64-${WORKERD_VERSION}.tgz /workerd.tgz

FROM fetch-${TARGETARCH} AS fetch
RUN tar -xzf /workerd.tgz -C / package/bin/workerd

FROM gcr.io/distroless/base-nossl-debian13:nonroot@sha256:83df5862465415c1d5f3ade85adc4d58a922db94e0b4d26c83a1bf96d5adf72d
ARG WORKERD_VERSION
LABEL org.opencontainers.image.version=${WORKERD_VERSION}
COPY --from=fetch --chmod=0755 /package/bin/workerd /usr/local/bin/workerd
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/workerd"]
