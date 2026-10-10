# Dedicated build and deployment preparation

The public client remains at https://gordey328.github.io/Blockfield/. A native host/domain has not been selected. No account, VPS, certificate, payment setting or public authoritative service has been created.

Local native authority (Windows engine; no visual scene):

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --server --bind=127.0.0.1 --game-port=8765 --map-port=8766 --mode=ctf --profile=0.75
```

Options use `--name=value`; unknown/duplicate options fail. `map=lab` is the default shared arena; `--map=/absolute/path/map.vxl` loads a validated local map with a64MiB file budget. The dedicated export includes the original map `res://assets/openspades/maps/Title.vxl`; set `BLOCKFIELD_MAP` to that path in compose to select it. Custom maps need an explicit read-only mount and an absolute container path. Modes: sandbox/ctf/tc. Profiles:0.75/0.76. Ports0 choose ephemeral ports for tests. Bind to loopback for a same-host proxy; bind0.0.0.0 inside the isolated compose network. `--round-restart=10` restores pristine terrain ten seconds after CTF/TC victory (allowed1..3600). Connected players cross a fresh epoch/map barrier. The client Connection menu accepts separate public game/map endpoints; no public host is preconfigured.

```text
python tools/build_server.py
docker compose --env-file deploy/.env -f deploy/compose.yaml up --build -d
```

The build script installs only the matching Linux release template, performs native launcher smoke and exports `build/server/blockfield.x86_64` with its PCK, notices and SHA256 build metadata. It then loads that exported PCK with the matching Windows host engine and the included Title.vxl: this checks packaged script/map availability, not execution of the Linux binary. The Linux Dedicated Server preset exports only the entry/server scenes and their dependencies, stripping presentation resources. Build output is ignored; source and reproducible scripts are versioned.

Copy deploy/.env.example to deploy/.env and set a public DNS domain pointed to the selected host. Ports80/443 must reach Caddy for HTTPS/WSS. Caddy routes `/play` and `/map` to internal8765/8766 and permits the Pages origin `https://gordey328.github.io`; other routes return404. WSS URL paths are public configuration, not secrets. Native local clients connect directly to loopback ports; the proxy deliberately restricts its public routes to the Pages browser origin. This Origin check is an access policy, not account authentication.

The game container runs an unprivileged user with a read-only filesystem, transient writable home/tmp and internal listeners. No external server port is published directly. Docker is unavailable in the current Windows environment, so image construction, Linux execution, certificate issuance and public WSS behavior have **not** been verified here. Compose pins Caddy2.11.7-alpine's registry manifest digest `sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f`, read from the official Docker registry. No container uptime/capacity claim is made.

Native Caddy2.11.7 `adapt --config deploy/Caddyfile --adapter caddyfile` passed locally. The downloaded Windows archive SHA256 was `0a1edc0b799512051c57071ce0e798d3f2cf67dc98171366f1d2b326072e3b06`; its official release SHA512 was checked before execution. Parsed JSON contains exactly three exclusive routes with the expected `/play` and `/map` paths, Pages Origin, internal ports and final404 fallback. The fallback must be inside `handle`: a bare `respond` sorts before `reverse_proxy` and would intercept all requests. [Caddy handle routing](https://caddyserver.com/docs/caddyfile/directives/handle), [directive order](https://caddyserver.com/docs/caddyfile/directives).

Current local development export passed server import, native60-frame launcher smoke, Linux release export and the exported-PCK original-map launcher. The filtered preset explicitly selects authoritative scripts: selecting only entry scenes included dependencies but exported an empty global-class registry, and the exported-PCK check correctly rejected startup. Explicit selection restores server class registration without client presentation resources. Its current build-info records an uncommitted workspace; a new frozen export/publication follows. The user explicitly selected Docker/configuration preparation while keeping the host choice open.

The networking/rendered-client iteration is unfinished even when native export passes. See server-runtime.md, multiplayer-plan.md and parity.md for remaining acceptance.

For a distributable server tied to the exact same clean source as the browser:

```text
python tools/release_checkpoint.py --revision HEAD --server
python tools/package_server.py --source .cache/release-COMMIT12
python tools/publish_server_release.py --package build/packages/blockfield-server-COMMIT12.zip
```

Replace COMMIT12 with the first twelve characters of the frozen commit. Packaging
checks both binary hashes against clean build metadata and includes the matching
deployment files, notices and START-HERE.txt. Publication creates a development
prerelease and verifies the public ZIP download's SHA256. Neither packaging nor
publication establishes that a Linux container or a public server is running.
