# ruby-holons

**Ruby SDK for Organic Programming** — transport primitives,
serve-flag parsing, identity parsing, discovery, and a Holon-RPC
client.

## Test

```bash
ruby test/holons_test.rb
```

## API surface

| Module | Description |
|--------|-------------|
| `Holons::Transport` | `parse_uri(uri)`, `listen(uri)`, `accept(listener)`, `mem_dial(listener)`, `conn_read(conn)`, `conn_write(conn)`, `close_connection(conn)`, `scheme(uri)` |
| `Holons::Serve` | `parse_flags(args)` |
| `Holons::Identity` | `parse_holon(path)` |
| `Holons::Discover` | `discover(root)`, `discover_local`, `discover_all`, `find_by_slug(slug)`, `find_by_uuid(prefix)` |
| `Holons::HolonRPCClient` | `connect(url)`, `invoke(method, params)`, `register(method, &handler)`, `close` |

## Current scope

- Runtime transports: `tcp://`, `unix://`, `stdio://`, `mem://`
- `ws://` and `wss://` are metadata-only at the transport layer
- Discovery scans local, `$OPBIN`, and cache roots

## Current gaps vs Go

- No generic slug-based `connect()` helper yet.
- No full gRPC `serve` lifecycle helper yet.
- No Holon-RPC server module yet.
