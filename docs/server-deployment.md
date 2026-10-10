# Dedicated build and deployment preparation

The public client remains at https://gordey328.github.io/Blockfield/. A native host/domain has not been selected. No account, VPS, certificate, payment setting or public authoritative service has been created.

Local native authority (Windows engine; no visual scene):

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --server --bind=127.0.0.1 --game-port=8765 --map-port=8766 --mode=ctf --profile=0.75
```

Options use `--name=value`; unknown/duplicate options fail. `map=lab` is the default shared arena; `--map=/absolute/path/map.vxl` loads a validated local map with a64MiB file budget. Modes: sandbox/ctf/tc. Profiles:0.75/0.76. Ports0 choose ephemeral ports for tests. Bind to loopback for a same-host proxy; bind0.0.0.0 inside the isolated compose network. Restart/reset administration and public client endpoint configuration remain upcoming integration.

```text
python tools/build_server.py
docker compose --env-file deploy/.env -f deploy/compose.yaml up --build -d
```

The build script installs only the matching Linux release template, performs native launcher smoke and exports `build/server/blockfield.x86_64` with its PCK, notices and SHA256 build metadata. The Linux Dedicated Server preset exports only the entry/server scenes and their dependencies, stripping presentation resources. Build output is ignored; source and reproducible scripts are versioned.

Copy deploy/.env.example to deploy/.env and set a public DNS domain pointed to the selected host. Ports80/443 must reach Caddy for HTTPS/WSS. Caddy routes `/play` and `/map` to internal8765/8766 and permits the Pages origin `https://gordey328.github.io`; other routes return404. WSS URL paths are public configuration, not secrets. Native local clients connect directly to loopback ports; the proxy deliberately restricts its public routes to the Pages browser origin. This Origin check is an access policy, not account authentication.

The game container runs an unprivileged user with a read-only filesystem, transient writable home/tmp and internal listeners. No external server port is published directly. Docker is unavailable in the current Windows environment, so image construction, Linux execution, certificate issuance and public WSS behavior have **not** been verified here. The Caddy image currently follows its2-alpine tag; resolve/pin an image digest on the selected deployment host before treating this as a reproducible production deployment. No container uptime/capacity claim is made.

Current local development export passed server import, native60-frame launcher smoke and Linux release export. Its build-info currently records an uncommitted workspace; it is a packaging check, not a frozen/published server release. The user explicitly selected Docker/configuration preparation while keeping the host choice open.

The networking/rendered-client iteration is unfinished even when native export passes. See server-runtime.md, multiplayer-plan.md and parity.md for remaining acceptance.
