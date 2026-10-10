# Network menu and HUD routing

`game/ui/network_menu.gd` provides the connection form inside `LabHUD`'s existing menu. `Main.network_mode` selects this branch; offline mode retains the arsenal, soldiers, world, checks and settings tabs and adds a Multiplayer scene action. Network mode exposes Connection, saved Servers and the same input/display/audio/graphics settings. It has no local map editor, target controls, profile switch, restock or invulnerability toggles.

The form starts with empty game/map addresses. `wss://host/play` and `wss://host/map` are placeholders, not configured public servers. The user supplies both addresses, a name and an optional spectator request. URL validation, browser HTTPS/WSS requirements, socket ownership and reconnect capabilities belong to Main. The UI forwards a trimmed request and displays Main's concise rejection. It reads only client `get_stats()` status/error/map phase and the safe `network_can_resume()` boolean; it neither reads nor displays tokens.

## Integration contract

`BlockfieldNetworkMenu.setup(hud, main, session, player)` builds controls under the existing margin; `refresh()` updates their availability and status. The menu delegates these methods:

- `Main.network_connect(game_url, map_url, name, spectator, resume=false) -> Dictionary` with `ok` and optional `error`.
- `Main.network_disconnect()`, `network_can_resume() -> bool`, `open_offline_lab()` and `open_network_game()`.
- `LabHUD.set_menu_visible(false)` for Enter. The existing input/mouse transition remains in HUD.
- `LocalSession.select_team(0..2)` and `select_weapon(0..2)`; NetworkSession implementations queue server intents. Changing class does not grant ammunition or replace authoritative state, and takes effect at respawn.
- `player.block_color` for the controller's color intent.

Only client status `live` enables Enter, team, class and color controls. Connecting, joining, loading and synchronizing freeze join fields while preserving Disconnect. Map download/verification uses an indeterminate progress bar and human status text because the current transfer stats do not publish a total progress denominator. A successful map transfer alone does not permit entering before the matching owner-state barrier.

Labels, tabs and buttons refresh English/Russian through the existing HUD translation helpers. Dynamic status text refreshes separately. Network HUD and scoreboard titles identify multiplayer; remote scoreboard rows display server score (including flag captures), falling back to legacy kills only for offline rows without score.

Kill feed keeps explicit melee/grenade/fall/team-change causes. A gun kill without a confirmed shot reference uses the generic Weapon label; it never defaults to Rifle when `weapon_known=false`. Offline events without this privacy/attribution flag retain their existing known weapon mapping.

## Saved server book

The Servers tab adds named guest endpoint favorites, case-insensitive name filtering and stable name sorting. Selecting an entry fills game/map addresses and the spectator choice on Connection, preserving the player's name. Selection never connects automatically. Add stores the current form under a new name; Update changes the selected identity; Delete removes only that entry. Filtering out a selected entry clears the edit identity. Connected or joining clients cannot change saved endpoints through these controls, including direct callback invocation.

`BlockfieldServerBook` (`game/ui/server_book.gd`) is a pure `RefCounted` with `load(path="user://servers.cfg")`, `set_storage_path(path)`, `list(filter="")`, `get_entry(id)`, `upsert(record)`, `remove(id)` and `save()`. Mutations return `ok/error` and add/update also return `id`. Records contain exactly `id`, `name`, `game_url`, `map_url`, `spectator`; insert requests omit `id`. IDs are positive, monotonic u32 values. Read methods return owned copies. Memory changes do not persist until an explicit `save()`; menu construction, load, filter and select perform no writes.

`user://servers.cfg` is separate from application preferences and begins empty. It contains version1, the next ID and at most64 entries. Load is limited to512KiB and validates types, section/field allowlists, identity/count bounds and URLs before replacing the previous valid book. Failed loads preserve its memory and previously chosen path. Server names are printable, trimmed UTF-8 of at most64 bytes; spectator defaults are strict booleans. Endpoints allow `ws://` and `wss://`, DNS/IPv4 or bracketed IPv6, and optional ports1–65535, up to2048 UTF-8 bytes. Userinfo, query strings, fragments, whitespace and controls are rejected. This guest endpoint policy intentionally excludes saved URL bearer capabilities; no resume/bulk tokens, passwords or arbitrary fields can enter the book. HTTPS browser WSS enforcement remains Main's connection validation.

This is the manual-endpoint/favorites adaptation defined by [ADR0006](decisions/0006-multiplayer-lobby.md). It does not query an AoS master server or invent public hosts. A standalone hosted Blockfield server remains required for Internet play; Pages hosts only the client.

## Chat

Online ordinary messages call the bound client's `send_chat(text, team_only)`. They receive no optimistic echo or local beep; Main delivers the validated, deduplicated confirmed chat event to the chat widget and sound path. Failed submission adds a local message. Slash commands stay local: read/display settings and team requests use the existing console, while `/restock`, `/mode` and argument-free `/reset` are denied before console dispatch. `/reset name|all` remains a display/input preference operation. Online `/help` does not advertise offline authority commands. NetworkSession and Main retain independent authority guards.

## Evidence and remaining acceptance

Godot `4.7.2.stable.official.ed1daf0bf` isolated actual menu/settings/chat controls, no Main load or preference writes:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://../tests/ui/test_network_menu.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://../tests/ui/test_network_menu.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://../tests/ui/test_server_book.gd
```

Results: actual menu **70 assertions / 0 failures**, pure server book **163 / 0**, exit0 and clean stderr. Menu checks cover empty endpoints, join-field trimming, every readiness phase, premature callback gates, team/class/color intents without local resource mutation, safe reconnect delegation, visible failures, Russian/English refresh, online chat/console routing, authoritative remote score and offline branch preservation. Favorite checks use the actual controls and persisted config: sorting/filtering, read-only selection, exact addresses/roles, explicit add/update/delete, no auto-connect, rejected credential URLs, frozen active endpoints and fresh-menu restoration. Application settings and the original server config are restored byte-for-byte. Pure checks add64-entry capacity, UTF-8/name/URL/type bounds, exhausted u32 IDs, hostile config allowlists, atomic rejected loads and owned-copy isolation. Whole-scene integration and actual exported-browser connection/input/layout remain separate acceptance evidence; these isolated checks do not establish deployed WSS/TLS or a public server.

The same suite can run with a real Compatibility graphics context:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --script res://../tests/ui/test_network_menu.gd -- --render-menu
```

Observed Intel UHD/OpenGL3.3 result: **93 assertions / 0 failures**, clean stderr and no resource leaks. Captures under `.cache/previews/network-menu/` show English/Russian connection and Servers tabs and the scrolled team/class/color controls at1280×720. The footer remains inside the rendered viewport; selected addresses, role, name and all favorite buttons fit without scrolling. Images were inspected and are excluded from source. This is native GPU layout evidence, not browser/network acceptance.

## Owner-state weapon presentation

Native `WeaponView.set_simulation_state(values: Dictionary) -> bool` optionally consumes a complete scalar owner mirror: `desired_tool`, `displayed_tool`, `weapon` (desired), `displayed_weapon`, `tool_raise`, `sprint_state`, `aim_down_state`. Selection values are bounded integer enums and the last three fields are finite raw0..1 counters. Unknown, missing, invalid or out-of-range fields fail atomically. The copied mirror applies before source skin formulas; variable render delta cannot advance tool/raise/sprint/ADS readiness a second time. Existing `set_selection` is a compatibility no-op while the mirror is active. Confirmed displayed swaps rebuild original models without emitting `tool_raised` and repeating local audio. `clear_simulation_state()` restores the original offline clocks from the current pose.

Controller invokes this optional method through `has_method`; trusted custom skins retain their current cosmetic fallback if they omit it. Authority never depends on a custom view getter. Source raise mapping remains `1 - min((1-raw)^2*1.5,1)` and the native use-tool gate compares raw raise against0.999. Disabling aim animation cannot overwrite mirrored raw values.

`tests/presentation/test_weapon_simulation.gd`: **74/0** including variable delta up to100s, atomic validation, desired/displayed distinctions, native threshold, original SMG assembly, resource reload and restoration of offline source clocks/signals. Existing `test_weapon_native.gd` remains **69/0**. Both ran headless without Main, with clean stderr; they establish state/transform behavior, not exported rendering.
