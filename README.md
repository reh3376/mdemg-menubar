# MDEMG Menu Bar

macOS menu bar companion app for the [MDEMG](https://github.com/reh3376/mdemg) cognitive memory server.

## Features

- **Multi-instance support** — register and monitor multiple MDEMG instances from a single menubar icon; switch between them via a dropdown picker
- **Status icon** — programmatic green/yellow/red/gray circle in the menu bar showing the selected instance's health
- **6-tab popover dashboard** — Status, Memory, Learning, Neo4j, Config, and Logs
- **Status tab** — comprehensive subsystem health (Neo4j, server, embedding, plugins, circuit breakers, CMS), model inventory (embedding/naming/summary/reranker), service uptimes, and lifecycle controls (Start/Stop/Restart)
- **Memory tab** — graph composition by layer (L0-L5), temporal activity (24h/7d/30d), connectivity metrics, learning edge stats
- **Learning tab** — Hebbian learning phase and trend, edge breakdown (strong/surprising/below threshold), configuration, freeze state
- **Neo4j tab** — database health, per-space node counts, connection pool, Go runtime metrics
- **Config tab** — server configuration viewer, database backup/migrate, version display
- **Logs tab** — live log viewer with search/filter and open-in-editor
- **Auto-discovery** — scans `~/*/` for `.mdemg/config.yaml` directories every 60s; reads `.mdemg.port` and `.mdemg/mdemg.pid` to find running servers
- **CLI auto-registration** — `mdemg init` automatically registers the project with the menubar instance registry
- **Instance management** — add/remove instances manually via Preferences, view per-instance health status dots
- **Configurable polling** — 10s health checks with `/healthz` + `/readyz`, 30s stats refresh, 30s background health for non-selected instances, exponential backoff on failure
- **Launch at Login** — optional auto-start via macOS Login Items

## Requirements

- macOS 13.0+
- [MDEMG](https://github.com/reh3376/mdemg) installed (`brew install reh3376/mdemg/mdemg`)
- Xcode 15+ (for building from source)

## Quick Start

```bash
# Install via Homebrew Cask (when available)
brew install --cask reh3376/mdemg/mdemg-menubar

# Or build from source
make setup   # installs xcodegen + generates project
make build   # builds the app
make run     # launches the app
```

## Build from Source

```bash
# Prerequisites
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme MdemgMenuBar -configuration Debug build

# Run tests
xcodebuild -scheme MdemgMenuBarTests -configuration Debug test
```

## Architecture

The app communicates with the MDEMG server exclusively via:

1. **HTTP REST** — monitoring endpoints (`/healthz`, `/readyz`, `/v1/neo4j/overview`, `/v1/embedding/health`, `/v1/memory/stats`, `/v1/learning/stats`, `/v1/memory/distribution`, `/v1/system/pool-metrics`)
2. **CLI subprocess** — lifecycle commands (`mdemg start/stop/restart`) and config (`mdemg config show --json`)
3. **Docker inspect** — Neo4j container uptime via `docker inspect`
4. **File reads** — PID file, port file, log file

No Go packages are linked. The app is a thin monitoring shell around the existing REST API endpoints.

## Multi-Instance Architecture

Instances are persisted as JSON at `~/Library/Application Support/com.reh3376.mdemg-menubar/instances.json`. This file is shared between:

- **Swift app** — reads/writes via `InstanceStore`, watches for changes via `DispatchSource`
- **Go CLI** — `mdemg init` appends new entries via `registerWithMenubar()`
- **Auto-discovery** — `InstanceScanner` scans `~/*/` for `.mdemg/config.yaml` every 60s

Each instance has its own `ServerDiscovery`, `MdemgClient`, and `CLIExecutor` (with `workingDirectory`). The selected instance gets full health + stats polling; non-selected instances get lightweight `/healthz` checks at 30s intervals.

## Server Discovery

```
1. Read .mdemg.port → get port number
2. Hit GET http://localhost:{port}/healthz → confirm alive
3. If .mdemg.port missing → check .mdemg/mdemg.pid → process alive?
4. Fallback → http://localhost:9999
5. Override → per-instance serverURL in instance registry
```

## License

MIT
