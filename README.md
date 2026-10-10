# Blockfield

OpenSpades v0.1.3 port to Godot. **Development: neither iteration has passed full acceptance.**

The offline lab starts without a server and exposes rifle, SMG, shotgun, spade/block/grenade, both team appearances, targets and local CTF/TC rules. The Multiplayer menu joins the new dedicated server using separate game/map WebSocket addresses. Its Servers tab keeps named local favorites with search and sorting; selecting one fills the form and connecting remains a separate action. The initial list is empty.

The Godot project is in `game/`. It uses Godot 4.7.2 standard, GDScript and Compatibility. Original assets are converted reproducibly; licensing/provenance is in [docs/assets.md](docs/assets.md) and `game/assets/openspades/licenses/`. Source code is GPL-3.0-or-later; third-party assets retain their individual licenses.

## Run and build

```sh
python tools/bootstrap.py
python tools/build.py --export
python tools/serve.py
```

Open http://127.0.0.1:8060. On Windows without Python on PATH, use the bundled runtime documented in [docs/status.md](docs/status.md). For desktop development open `game/project.godot` in the pinned engine.

The [public development build](https://gordey328.github.io/Blockfield/) currently contains source [`c4f808990b84d068242dde47b8fe4f2951e322fe`](https://github.com/Gordey328/Blockfield/tree/c4f808990b84d068242dde47b8fe4f2951e322fe), Pages bundle `d3ee96ad9451cd79f94123595bb22bee6b7f3bba`, with clean-source build metadata. Newer HDR normalization and integrated network/favorites changes are not yet that public release. Publication does not complete either iteration.

GitHub Actions is currently blocked by an account billing condition before any build steps start. Checked local exports are published with `python tools/publish_pages.py` to the `gh-pages` branch. See [publication decision](docs/decisions/0003-pages-publication.md). Each export includes its source revision in `build-info.json`.

## Multiplayer development and server preparation

Native local authority:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --server --bind=127.0.0.1 --game-port=8765 --map-port=8766 --mode=ctf --profile=0.75
```

Use `ws://127.0.0.1:8765/play` and `ws://127.0.0.1:8766/map` in a native or local HTTP client. Public HTTPS clients require WSS. Original Ace of Spades ENet servers cannot join this replacement protocol; the0.75/0.76 weapon profiles are retained separately.

For the prepared Linux server/container configuration, copy `deploy/.env.example` to `deploy/.env` and set the DNS domain and match options for your host:

```sh
python tools/build_server.py
docker compose --env-file deploy/.env -f deploy/compose.yaml up --build -d
```

Pages hosts the client; the authority needs a separate host. No public multiplayer endpoint is configured or running. Native export/configuration checks passed, but Docker/Linux execution, public TLS/WSS, sustained capacity and full browser multiplayer play remain unverified. See [server deployment](docs/server-deployment.md), [multiplayer decision](docs/decisions/0005-authoritative-multiplayer.md) and [acceptance gaps](docs/acceptance-gaps.md).

## Durable project context

Start with [AGENTS.md](AGENTS.md) and [docs/status.md](docs/status.md). Scope: [iterations](docs/iterations.md). Feature ledger: [parity](docs/parity.md). Architecture: [architecture](docs/architecture.md). Skills and context recovery: [skills](docs/skills.md).
