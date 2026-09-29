# ================================
# Build image
# ================================
FROM swift:6.0.3-jammy AS build

# Install OS updates
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy the entire repo (the server package depends on the root EncoreMomentCore package via a path).
COPY . .

# Build the server product in release mode with a statically linked stdlib so the
# runtime image only needs libc/libcurl.
WORKDIR /build/Server
RUN swift build -c release --product EncoreMomentServer --static-swift-stdlib

# Stage the built binary and resources.
WORKDIR /staging
RUN cp "$(swift build --package-path /build/Server -c release --show-bin-path)/EncoreMomentServer" ./
RUN [ -d /build/Server/Public ] && { mv /build/Server/Public ./Public && chmod -R a-w ./Public; } || true

# ================================
# Run image
# ================================
FROM ubuntu:jammy

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
        libjemalloc2 \
        ca-certificates \
        tzdata \
        libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user.
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

# Provide the runtime location of the Swift runtime libraries.
ENV SWIFT_BACKTRACE=enable=no
USER vapor:vapor

EXPOSE 8080

ENTRYPOINT ["./EncoreMomentServer"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
