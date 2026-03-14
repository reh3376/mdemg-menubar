# MDEMG Menu Bar

macOS menu bar companion app for the [MDEMG](https://github.com/reh3376/mdemg) cognitive memory server.

## Features

- **Status icon** — green/yellow/red/gray circle in the menu bar showing server health
- **Popover dashboard** — click the icon to see status, port, uptime, node count, Neo4j and embedding status
- **Lifecycle controls** — Start, Stop, Restart the MDEMG server directly from the menu bar
- **Auto-discovery** — reads `.mdemg.port` and `.mdemg/mdemg.pid` to find the running server
- **Configurable polling** — 10s health checks, 30s stats refresh, exponential backoff on failure
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

1. **HTTP REST** — all monitoring endpoints (`/healthz`, `/v1/neo4j/overview`, `/v1/embedding/health`, etc.)
2. **CLI subprocess** — lifecycle commands only (`mdemg start/stop/restart`)
3. **File reads** — PID file, port file, log file

No Go packages are linked. The app is a thin monitoring shell around the existing 97+ REST API endpoints.

## Server Discovery

```
1. Read .mdemg.port → get port number
2. Hit GET http://localhost:{port}/healthz → confirm alive
3. If .mdemg.port missing → check .mdemg/mdemg.pid → process alive?
4. Fallback → http://localhost:9999
5. Override → user-configured URL in Preferences
```

## License

MIT
