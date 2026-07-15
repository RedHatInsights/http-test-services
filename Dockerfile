FROM registry.access.redhat.com/hi/go:1.26.5-fips-builder AS builder
WORKDIR /app
USER root
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /tmp/http-test-services .

FROM registry.access.redhat.com/hi/core-runtime:2.43-openssl-fips-builder
COPY --from=builder /tmp/http-test-services /http-test-services
COPY docs/ /docs/

# Activate Go's FIPS 140 cryptography module at runtime
ENV GODEBUG=fips140=on

# Run as non-root; core-runtime is distroless and does not set a default user
USER 1001

ENTRYPOINT ["/http-test-services"]
