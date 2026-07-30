# http-test-services

A stateless HTTP/gRPC mock and echo service used for testing API gateway routing on [console.redhat.com](https://console.redhat.com).

> Forked from [apicast-test-services](https://github.com/RedHatInsights/apicast-test-services) and rewritten in Go.

## Endpoints

All HTTP endpoints are available at both `/` and `/api/http-test-services/` (configurable via `API_PREFIX` env var), with optional version prefix (e.g. `/api/http-test-services/v1/...`).

| Route | Method | Description |
|-------|--------|-------------|
| `/` | GET | 302 redirect to `/api/http-test-services/request` |
| `/request` | GET | JSON with request env and headers |
| `/headers` | GET | JSON with sorted HTTP headers |
| `/redirect?redirect_to=<path>` | GET | 302 redirect to the given path (400 if missing) |
| `/ping` | GET | `{"status":"available"}` |
| `/private/ping` | GET | `{"status":"available"}` |
| `/upload` | POST | Accepts multipart file upload, returns `{"status":"posted","upload_byte_size":N}` |
| `/identity` | GET | Decodes base64 `x-rh-identity` header (400 if missing) |
| `/wss` | GET | WebSocket echo server |
| `/sse` | GET | Server-Sent Events stream (ping every 3s) |
| `/{version}/openapi.json` | GET | OpenAPI spec |

All endpoints support `?sleep=N` (delay in seconds) and `?status=N` (override response status code) query parameters.

A gRPC `PingService` runs on port 50051 with a single `Ping` RPC that echoes the message back.

## Configuration

| Env var | Description | Default |
|---------|-------------|---------|
| `ACG_CONFIG` | Path to Clowder JSON config file (reads `webPort`) | `9092` |
| `API_PREFIX` | Path prefix for all routes | `/api/http-test-services` |
| `HTTP_TIMEOUT` | HTTP server read/write/idle timeout in seconds | `30` |

## Build and run

```sh
go build -o http-test-services .
./http-test-services
```

The HTTP server starts on `:9092` (or the port from `ACG_CONFIG`) and the gRPC server on `:50051`.

## Run tests

```sh
go test ./...
```

## Docker

```sh
podman build -t http-test-services .
podman run -p 9092:9092 -p 50051:50051 http-test-services
```

## Testing endpoints

Start the service locally or via Docker, then use the examples below. All HTTP endpoints default to port `9092`.

### HTTP

```sh
# Ping
curl http://localhost:9092/api/http-test-services/ping

# Request introspection (returns env and headers)
curl http://localhost:9092/api/http-test-services/request

# Headers
curl http://localhost:9092/api/http-test-services/headers

# Redirect
curl -v http://localhost:9092/api/http-test-services/redirect?redirect_to=/api/http-test-services/ping

# Identity (base64-encoded x-rh-identity header)
curl -H "x-rh-identity: $(echo '{"identity":{"account_number":"123"}}' | base64)" http://localhost:9092/api/http-test-services/identity

# File upload
curl -F file=@README.md http://localhost:9092/api/http-test-services/upload

# OpenAPI spec
curl http://localhost:9092/api/http-test-services/v1/openapi.json

# Sleep (delay response by N seconds)
curl http://localhost:9092/api/http-test-services/ping?sleep=2

# Status override
curl -v http://localhost:9092/api/http-test-services/ping?status=418
```

### SSE

```sh
curl -N http://localhost:9092/api/http-test-services/sse
```

### WebSocket

```sh
websocat ws://localhost:9092/api/http-test-services/wss
```

### gRPC

```sh
grpcurl -plaintext -proto api/test_service.proto -d '{"message": "hello"}' localhost:50051 test_service.PingService/Ping
```
