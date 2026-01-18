FROM docker.io/library/alpine:3.23.2 AS builder
RUN apk update && \
    apk add --no-cache --update-cache cargo rust musl-dev upx
WORKDIR /app
COPY . /app
RUN RUSTFLAGS='-C target-feature=+crt-static' cargo build --release && \
    upx --best --lzma ./target/release/detect-changed-files

FROM scratch
LABEL org.opencontainers.image.title="detect-changed-files"
LABEL org.opencontainers.image.description="Fast tool to analyze changed files and categorize them based on pattern matching"
LABEL org.opencontainers.image.source="https://github.com/borisfaure/detect-changed-files"
LABEL org.opencontainers.image.authors="Boris Faure"
LABEL maintainer="Boris Faure"
LABEL io.containers.capabilities="network=none"
COPY --from=builder /app/target/release/detect-changed-files /detect-changed-files
CMD ["/detect-changed-files"]
