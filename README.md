# Blockfield

OpenSpades v0.1.3 port to Godot. **Work in progress: iteration 1 is not complete.**

Iteration 1: offline client and testing lab, all three original weapons, spade/block/grenade tools, both team appearances, local rules and browser export. Iteration 2: dedicated multiplayer.

The Godot project is in `game/`. It uses Godot 4.7.2 standard, GDScript and Compatibility. Original assets are converted reproducibly; licensing/provenance is in [docs/assets.md](docs/assets.md) and `game/assets/openspades/licenses/`. Source code is GPL-3.0-or-later; third-party assets retain their individual licenses.

## Run and build

```sh
python tools/bootstrap.py
python tools/build.py --export
python tools/serve.py
```

Open http://127.0.0.1:8060. On Windows without Python on PATH, use the bundled runtime documented in [docs/status.md](docs/status.md). For desktop development open `game/project.godot` in the pinned engine.

The [development build](https://gordey328.github.io/Blockfield/) runs on GitHub Pages. Current deployments remain development builds until the iteration acceptance gate is passed.

GitHub Actions is currently blocked by an account billing condition before any build steps start. Checked local exports are published with `python tools/publish_pages.py` to the `gh-pages` branch. See [publication decision](docs/decisions/0003-pages-publication.md). Each export includes its source revision in `build-info.json`.

## Durable project context

Start with [AGENTS.md](AGENTS.md) and [docs/status.md](docs/status.md). Scope: [iterations](docs/iterations.md). Feature ledger: [parity](docs/parity.md). Architecture: [architecture](docs/architecture.md). Skills and context recovery: [skills](docs/skills.md).
