FROM rust:latest AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:latest
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    iptables \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/backend /usr/local/bin/
WORKDIR /var/lib/backend
EXPOSE 3000
CMD ["/usr/local/bin/backend"]
