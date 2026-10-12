# Blockfield

OpenSpades v0.1.3 port to Godot. **Development: full offline-port acceptance remains open.**

Start from Home, choose a map and rifle/SMG/shotgun, then enter the game. Crossroads
supports offline3×3: one human and five bots. The lab, Title, Mirage and Dust2 are
training maps. The lab exposes both team appearances, spade/block/grenade, targets,
local CTF/TC rules and terrain editing. Selection and preferences are saved locally.

Home → Zombie waves opens finite survival on Crossroads: choose duration, wave
interval, up-to quota and growth with active game time. Waves overlap; survive the
timer and clear the remaining zombies. They compare detours with breaking cover.
Building remains available, with finite inventory and a safe supply point. See
[mode rules and verification](docs/zombie-survival.md).

The user cancelled multiplayer; all game transport, server, prediction, replication,
reconnect and networking menus are removed. Shared local simulation remains for
bots and combat. See [scope decision](docs/decisions/0031-offline-only-game.md).

The Godot project is in `game/`, with pinned Godot4.7.2 standard, typed GDScript
and Compatibility. [Original asset provenance](docs/assets.md) and notices under
`game/assets/openspades/licenses/` remain. Code is GPL-3.0-or-later; third-party
assets retain their own rights and notices, including [bundled maps](game/assets/maps/README.md).

## Run and build

```sh
python tools/bootstrap.py
python tools/build.py --export
python tools/serve.py
```

Open http://127.0.0.1:8060. On Windows without Python on PATH, use the bundled
runtime recorded in [status](docs/status.md). Desktop development opens
`game/project.godot` in the pinned engine. Exports include source/version/hash
metadata in `build-info.json`. See [release evidence](docs/offline-only-release.md).

The [public development game](https://gordey328.github.io/Blockfield/) is served by
GitHub Pages. A checked browser build does not establish full OpenSpades parity or
physical-phone performance. Historical sibling builds and old server packages
describe their original source revisions; they are not current multiplayer support.

Phones use the existing movement/look/fire/aim/reload/jump/crouch/tool controls.
Settings → Mobile controls offers Auto/On/Off; On previews them with a desktop
mouse. The new Home/setup supports portrait and landscape. Physical-phone comfort
and FPS remain open; [mobile evidence](docs/mobile-controls.md) records the limits.

Local checked exports can be published with `tools/publish_pages.py`; the
[publication decision](docs/decisions/0003-pages-publication.md) describes hosting.

## Durable project context

Start with [AGENTS.md](AGENTS.md) and [current status](docs/status.md), then
[accepted scope](docs/iterations.md), [parity](docs/parity.md),
[architecture](docs/architecture.md) and [skills](docs/skills.md).
