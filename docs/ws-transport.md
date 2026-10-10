# WebSocket transport slice

`game/network/ws_transport.gd` is a poll-driven `RefCounted` transport using real Godot `WebSocketPeer` instances and the existing [binary codec](network-protocol.md). It sends decoded packet events to a future coordinator. This slice does **not** implement player authentication, match authority, client prediction, map assembly, a server entry point, or a deployed multiplayer game.

## API

| Method | Result / behavior |
|---|---|
| `configure(options: Dictionary)` | `{ok,error,code}`; atomically validates known integer options while idle. |
| `start_client(url: String)` | `{ok,error,code,connection_id?}`; starts one asynchronous `ws://` or `wss://` connection. A successful return is not a completed handshake. |
| `start_server(port=0, bind_address="127.0.0.1")` | `{ok,error,code,port?}`; native TCP listener. `0` selects an ephemeral port, measured in loopback tests. Web exports reject this method. |
| `send(connection_id, packet: BlockfieldProtocol.Packet)` | `{ok,error,code}`; codec-validates and queues one binary message for an open connection. Success means accepted into the queue, not remote acknowledgement. |
| `request_ping(connection_id)` | `{ok,error,code}`; queues one application PING. A second outstanding request fails. |
| `poll()` | Accepts, advances handshakes and close states, reads bounded messages, services heartbeat, flushes queues. Caller must invoke regularly. |
| `drain_events(max_count=64)` | Ordered `Array[Dictionary]`, count clamped to `0..256`. Caller must drain it regularly. |
| `close(connection_id, code=1000, reason="closed")` | `{ok,error,code,close_code?}`; validates status/reason, drops unsent local messages, initiates close. `close_code` reports the effective wire status. Continue polling. |
| `stop(force=false)` | Stops listener immediately; initiates peer close, or force-aborts with `force=true`. Continue polling after graceful stop. |
| `get_stats()` | Mode, listener port, connection/event counts, queued/buffered byte counts, frame totals, timeout/backpressure/error totals and per-peer RTT. No URL, token, name or packet payload. |

Each instance assigns increasing positive **connection** IDs. IDs are never recycled on reconnect within that instance. A client and a server can both have local ID `1` while referring to different endpoints. Stable actor IDs, spawn generations and ownership must be maintained by the coordinator; a `CHAT.sender_id` is only a decoded claim here. There is no automatic reconnect or broadcast method.

URL prechecks accept only `ws://`/`wss://`, at most 2048 characters, nonempty authority, no userinfo, control characters or fragment. Godot handles the remaining URL parsing and asynchronous connection failure. URLs are not stored in transport stats/events. Resume/bulk tokens belong in bounded HELLO packets, not URLs.

## Events

Every event has `type` and local `connection_id`.

| Type | Additional fields | Meaning |
|---|---|---|
| `listening` | `port` | Listener started; connection ID `0`. |
| `connected` | — | HTTP/WebSocket handshake completed; one event per connection. No game-level HELLO/WELCOME implied. |
| `packet` | `packet: BlockfieldProtocol.Packet` | Binary message passed the codec. Preserve connection attribution when passing to runtime. |
| `rtt` | `rtt_ms` | PONG matched the one outstanding nonce after its PING was actually flushed. |
| `protocol_error` | `reason` | Text frame or malformed codec packet; only that peer is closed. |
| `timeout` | `reason` | Handshake, idle, unanswered ping or heartbeat backpressure deadline. |
| `closed` | `code,reason,clean` | Peer removed. `clean` describes close handshake only; forced or abnormal closure has `clean=false`. Remote reason is untrusted text. |
| `overflow` | `reason` | Terminal event-queue overflow; connection ID `0`, all peers and listener aborted. |

PING/PONG are transport maintenance and do not reach `packet` events. PING is answered with a codec PONG; unmatched PONG increments a counter and cannot complete a pending nonce. No handshake, actor identity or gameplay permission follows from heartbeat success. Transport timestamps use local monotonic milliseconds modulo `2^32`; RTT uses local microseconds and is not a clock-offset estimate.

Malformed messages close native peers with `1002`; timeouts/stop use `1001`; send failure uses `1011`. Accepted explicit statuses are `1000..1014` excluding reserved `1004/1005/1006`, or `3000..4999`. Reasons are valid printable UTF-8 of at most **122 bytes**, satisfying Godot's documented smaller-than-123 limit. Browser-initiated standard codes other than `1000` map to `4000 + (code - 1000)`, e.g. `1001→4001`, `1002→4002`, `1011→4011`; native servers preserve standard codes. This avoids forbidden JavaScript close statuses under the [WebSockets Standard](https://websockets.spec.whatwg.org/#dom-websocket-close).

## Bounds and backpressure

| Bound | Value |
|---|---:|
| Simultaneous accepted/handshaking/closing peers | 32 maximum; configurable lower |
| New TCP admissions per `poll()` | 4 |
| Outgoing application queue per peer | 32 messages |
| Queued encoded bytes + reported socket buffered bytes per peer | 131072 bytes admission budget |
| Godot inbound/outbound buffer setting per peer | 262144 bytes each |
| Godot packet queue setting per peer | 64 |
| Application reads per peer / total per `poll()` | 16 / 64, rotating start peer |
| Pending event count / retained encoded message bytes | 256 / 524288 |
| Ordinary / bulk codec message | 32768 / 16384 bytes |

Admission rejects excess TCP streams before creating `WebSocketPeer`. `send()` rejects capacity before appending and leaves previously accepted messages intact. Flushing retains a message if Godot reports busy/out-of-memory. Accepted messages retain order; the coordinator must handle a failed send explicitly rather than silently assuming delivery. Kernel buffers, WebSocket framing and decoded GDScript container overhead are not exact components of the encoded-byte counters. Decoded event memory is additionally bounded by event count and codec record/string limits. Engine buffer properties are configured; native loopback tests are not proof of browser engine memory limits under hostile traffic.

An undrained event queue cannot represent a complete stream after loss. On overflow, the implementation clears queued events, releases the listener, aborts all peers and emits one terminal `overflow` event. The coordinator must invalidate every connection, then explicitly create/start a fresh transport or reconnect; it must not reuse old map/handshake state. Incoming oversized messages are rejected by the codec after Godot supplies the bounded native packet buffer.

## Configuration and lifecycle

| Option | Default ms / count | Allowed range |
|---|---:|---:|
| `connection_limit` | 32 | 1..32 |
| `handshake_timeout_ms` | 5000 | 100..60000 |
| `idle_timeout_ms` | 10000 | 50..120000 |
| `close_timeout_ms` | 500 | 50..5000 |
| `ping_interval_ms` | 2000 | 0..60000; `0` disables automatic requests |
| `ping_timeout_ms` | 5000 | 50..60000 |

Handshake deadline includes TCP connect. Idle means no valid incoming codec message. Ping deadline begins when accepted into the application queue, so a blocked queue cannot retain a pending request forever. RTT starts on socket flush. Only one nonce is outstanding per connection. A close deadline force-releases a peer that does not complete the handshake. All deadlines advance only when `poll()` runs; background tabs and stalled processes need a coordinator reconnect/resync policy.

The object has no thread, timer, hidden process, scene dependency or preference writes. Explicit `stop()` is normal cleanup; destruction also stops the TCP listener and force-closes remaining sockets. Keep polling until connection count is zero after a graceful stop. Force cleanup is available when the process exits or aborts a test.

## Godot/browser constraints and remaining integration

The implementation follows Godot's native [TCPServer acceptance](https://docs.godotengine.org/en/4.7/classes/class_tcpserver.html) and [WebSocket client/server polling example](https://docs.godotengine.org/en/4.7/tutorials/networking/websocket.html). Port `0` behavior is tested, rather than inferred from the example.

Godot requires regular polling through connect and close. Web exports cannot accept TCP streams or attach custom handshake headers; automatic WebSocket control-frame heartbeat has no Web effect, so this transport uses protocol PING/PONG. WSS uses Godot's default certificate/hostname verification; no unsafe TLS option is supplied. Pages over HTTPS needs a matching-hostname WSS endpoint. Buffered-byte queries use browser `bufferedAmount` in Web exports. These constraints are documented in [Godot 4.7 WebSocketPeer](https://docs.godotengine.org/en/4.7/classes/class_websocketpeer.html).

The included native listener accepts plaintext WS on loopback by default. Public WSS needs an independently hosted native authority and TLS reverse proxy or a later TLS listener; no service, account, certificate or public endpoint was created. Allowed HTTP Origin/path checks and rate limits must be enforced by that proxy/runtime before public exposure; this transport has no Origin authentication. Client packet direction, pre-HELLO restrictions, version/build/rules agreement, connection-to-actor owner binding, command sequencing, dual-socket tokens and transfer barriers remain runtime work. TCP head-of-line stalls and bulk/state queue scheduling still require latency tests. These files alone do not change N-row acceptance status.

## Verification

Run independently from main and saved settings:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_ws_transport.gd
```

`tests/network/test_ws_transport.gd` exercises a native ephemeral listener and two actual clients in one headless process: addressed responses, connection-owner routing, ordered 32-message streams, full 16KiB bulk messages, count/byte backpressure, excess TCP admission, codec-invalid output, reconnect/stale IDs, close status/UTF-8 reason validation, nonce-bound RTT, automatic heartbeat, malformed binary/text/oversized input, handshake/idle/ping deadlines, terminal event count/byte overflow and listener port reuse. Raw frames are injected only through directly constructed test `WebSocketPeer`, not a production escape hatch. Native checks do not prove a WSS browser connection or multiplayer gameplay.

Godot 4.7.2 `ed1daf0bf`: **602 assertions, 0 failures**, `.cache/logs/ws-transport-tests.log`. Standalone transport parser check also passes. Verbose native Godot may print low-level wslay read diagnostics when overflow deliberately aborts a socket; the normal suite output has no Godot error/warning or leaked-object reports.
