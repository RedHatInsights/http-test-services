# Migration Summary: apicast-test-services to http-test-services

## Overview

| | Old | New |
|---|---|---|
| **Repository** | `apicast-test-services` | `http-test-services` |
| **Language** | Ruby 3.3 | Go 1.25 |
| **HTTP Framework** | Sinatra + Thin | Go `net/http` stdlib |
| **WebSocket** | faye-websocket | nhooyr.io/websocket |
| **gRPC** | grpc (Ruby gem) | google.golang.org/grpc |
| **SSE** | Custom Sinatra streaming | Custom `http.Flusher` streaming |

## Language & Runtime

The old service ran on Ruby 3.3 using the Sinatra web framework with a Thin server. The new service is a statically compiled Go binary using the standard library `net/http` router.

Go's native concurrency model (goroutines) replaces Ruby's threaded/evented I/O, and the compiled binary eliminates the need for a language runtime in the container image.

## API Prefix Change

| Old Prefixes | New Prefix |
|---|---|
| `/api/apicast-tests/` | `/api/http-test-services/` |
| `/r/insights/platform/apicast-tests/` | *(removed)* |

The new service also registers every endpoint at three path variants:

1. Root: `/endpoint`
2. Prefixed: `/api/http-test-services/endpoint`
3. Prefixed & Versioned: `/api/http-test-services/v{version}/endpoint`

The prefix `(/api/http-test-services/)` is configurable via the `API_PREFIX` environment variable.

## Endpoint Comparison

| Endpoint | Old (`apicast-test-services`) | New (`http-test-services`) | Notes |
|---|---|---|---|
| `GET /` | Redirect to `/request` | Redirect to `{prefix}/request` | Same behavior |
| `GET /request` | Request introspection (Rack env + headers) | Request introspection (env + sorted headers) | Response structure preserved |
| `GET /headers` | HTTP headers as JSON | HTTP headers as sorted JSON (lowercase keys) | Same behavior |
| `GET /redirect` | 302 redirect via `redirect_to` param | 302 redirect via `redirect_to` param | Same behavior |
| `GET /ping` | `{"status":"available"}` | `{"status":"available"}` | Same behavior |
| `GET /private/ping` | `{"status":"available"}` | `{"status":"available"}` | Same behavior |
| `POST /upload` | File upload with byte size | File upload with byte size | Same behavior |
| `GET /identity` | Decode `X-Rh-Identity` header | Decode `X-Rh-Identity` header | Same behavior |
| `GET /wss` | WebSocket echo | WebSocket echo (JSON fallback for non-upgrade) | Enhanced with fallback |
| `GET /sse` | SSE ping stream | SSE ping stream (3s interval, random float) | Same behavior |
| `GET /env` | Environment variables as JSON | **Removed** | Security concern |
| `GET /{version}/openapi.json` | N/A | **Added** — serves OpenAPI 3.0 spec | New |
| `?sleep=N` | Delay response by N seconds | Delay response by N seconds (integers only) | Floats now ignored |
| `?status=N` | Override response status code | Override response status code | Same behavior |

## New Features

- **OpenAPI spec endpoint** — `GET /{version}/openapi.json` serves a bundled OpenAPI 3.0 specification from `/docs/openapi.json`.
- **WebSocket JSON fallback** — Non-upgrade requests to `/wss` return a JSON response instead of failing.
- **Versioned routes** — All endpoints accept an optional `/v{version}/` segment in the path. This is to future proof if we implement versioned routes for any of the endpoints.
- **Custom ordered JSON marshaling** — The `/request` endpoint returns JSON with deterministically ordered keys.

## Removed Features

- **`/env` endpoint** — Exposed environment variables; removed for security reasons.
- **`EnvironmentService` route restrictions** — The old service restricted certain routes based on the deployment host (production vs. staging). This logic has been removed; all endpoints are available in all environments.
- **`/r/insights/platform/apicast-tests/` prefix** — The secondary Insights-platform prefix is no longer supported.

## Architecture Differences

| Aspect | Old | New |
|---|---|---|
| **Server model** | Sinatra app mounted on Thin (EventMachine) | Go `net/http.Server` with goroutines |
| **Binary** | Interpreted Ruby scripts | Single static binary (`CGO_ENABLED=0`) |
| **Docker build** | Single-stage (Ruby base image) | Multi-stage (UBI9 go-toolset builder → UBI9 minimal) |
| **gRPC server** | Ruby gRPC gem, same process | Go gRPC, separate goroutine on port 50051 |
| **JSON output** | Ruby hash serialization | Custom ordered JSON marshaling for deterministic output |
| **Routing** | Sinatra DSL (`get '/' do ... end`) | `http.NewServeMux` with `HandleFunc` |

## Deployment

Both versions deploy via Clowder/ClowdApp on the same platform:

| Setting | Old | New |
|---|---|---|
| **HTTP port** | 9092 (via Clowder `webPort`) | 9092 (via Clowder `webPort`) |
| **gRPC port** | 50051 | 50051 |
| **Container base** | UBI9 | UBI9 minimal |
| **Min replicas** | 2 | 2 |
| **Health checks** | `GET /ping` | `GET /ping` (liveness + readiness) |
| **Image registry** | quay.io/cloudservices | quay.io/hcc-accessmanagement-tenant |

## Configuration

| Environment Variable | Purpose | Default | Changed? |
|---|---|---|---|
| `ACG_CONFIG` | Path to Clowder config JSON (provides `webPort`) | *(none)* | No |
| `API_PREFIX` | Route prefix for all endpoints | `/api/http-test-services` | New default value |
| `HTTP_TIMEOUT` | HTTP read/write/idle timeout (seconds) | `30` | No |

## Dependencies

### Old (Ruby gems)

- `sinatra` — HTTP framework
- `thin` — Web server (EventMachine-based)
- `faye-websocket` — WebSocket support
- `grpc` — gRPC framework
- `clowder-common-ruby` — Clowder configuration

### New (Go modules)

- `google.golang.org/grpc` — gRPC framework
- `google.golang.org/protobuf` — Protocol Buffers
- `nhooyr.io/websocket` — WebSocket support

No external HTTP framework or Clowder client library is needed — the Go service reads Clowder's `ACG_CONFIG` JSON directly.

## Testing

| Aspect | Old | New |
|---|---|---|
| **Framework** | RSpec | Go `testing` + `httptest` |
| **Server required** | Yes (Thin must boot) | No (uses `httptest.NewRecorder`) |
| **Test count** | ~10 specs | 14 test functions |
| **Coverage** | Route responses, redirects | Routes, redirects, uploads, identity, sleep, status override, WebSocket fallback, versioned routes |

## Performance Benefits

- **No runtime interpreter** — compiled static binary starts in milliseconds.
- **Lower memory footprint** — no Ruby VM, no gem loading overhead.
- **Native concurrency** — goroutines handle concurrent requests without EventMachine or thread pools.
- **Smaller container image** — UBI9 minimal base with a single binary, no language runtime installed.
- **Faster builds** — `go build` produces a ready-to-run binary; no `bundle install` step at deploy time.
