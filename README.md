---
# Cartouche v1
title: "ruby-holons — Ruby SDK for Organic Programming"
author:
  name: "B. ALTER"
created: 2026-02-12
access:
  humans: true
  agents: false
status: draft
---
# ruby-holons

**Ruby SDK for Organic Programming** — transport, serve, and identity
utilities for building holons in Ruby.

## Test

```bash
ruby test/holons_test.rb
```

## API surface

| Module | Description |
|--------|-------------|
| `Holons::Transport` | `parse_uri(uri)`, `listen(uri)`, `scheme(uri)` |
| `Holons::Serve` | `parse_flags(args)` |
| `Holons::Identity` | `parse_holon(path)` |

## Transport support

| Scheme | Support |
|--------|---------|
| `tcp://<host>:<port>` | Bound socket (`Listener::Tcp`) |
| `unix://<path>` | Bound UNIX socket (`Listener::Unix`) |
| `stdio://` | Listener marker (`Listener::Stdio`) |
| `mem://` | Listener marker (`Listener::Mem`) |
| `ws://<host>:<port>` | Listener metadata (`Listener::WS`) |
| `wss://<host>:<port>` | Listener metadata (`Listener::WS`) |
