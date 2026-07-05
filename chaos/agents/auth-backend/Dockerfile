FROM rust:latest AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:latest
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/auth-backend /usr/local/bin/
EXPOSE 8080
CMD ["/usr/local/bin/auth-backend"]
