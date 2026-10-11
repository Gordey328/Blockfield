# Combined Mirage and fixed-pool effects release — 2026-10-11

The user requested waiting for the other chat, combining its finished effects work
with Mirage, and publishing GitHub Pages. The effects chat completed before this
integration: runtime1b02c64 and evidence b7d7496 were committed/pushed. The user then
requested immediate publication followed by public verification; the link was
supplied during upload and again when Pages reported built.

## Published source and artifacts

- Frozen game source: `4530632b7eb7ff9bca2bd2ca97cb4bcdbefdb385`.
- Publication helper: `0e39997` adds an explicit bundle directory and remote
  gh-pages tracking ref for isolated publication with preserved sibling paths.
- Pages bundle: `ac2fff4caabdb9c881c596c10aeaecc33076344e`; API status `built`.
- URL: https://gordey328.github.io/Blockfield/?v=4530632
- Godot4.7.2.stable.official.ed1daf0bf; Compatibility; single-threaded Web.
- OpenSpades reference: `dcf449c845d509bbde9d79239b32d201c1389961`.
- Reduced template SHA256:
  `a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.

Mirage's327,461-byte map is unchanged from local verification:171×61×165,
298,384 occupied cells,40 supported source spawns; SHA256
`08b69203a2dde4d276053647312dbcdd5bf20f0730203ee24c4c293934e35d3a`.
It is committed under `game/assets/maps`, available through the offline World/modes
menu and downloadable at `maps/csgo_mirage.bfmap`. Bundled filenames precede same-name
ignored local maps. Specialist read-only review found no package/catalog/export
blockers or absolute host paths/credential fields in map metadata. Raw source and
Blender stay local. Provenance/static limits remain in the bundled notice,
[Mirage evidence](mirage-conversion.md) and [ADR0026](decisions/0026-bundled-map-publication.md).
Exported PCK24,676,616 bytes; WASM31,835,587 bytes. Outstanding parity is not promoted.

## Commands and checks

From the project root with bundled Python or Python3:

```powershell
python tools/release_checkpoint.py --revision 4530632 --import-cache game/.godot
python tools/serve.py --directory .cache/release-4530632b7eb7/build/web --port 8095
git fetch origin gh-pages
git worktree add --detach .cache/combined-pages-4530632 origin/gh-pages
git -C .cache/combined-pages-4530632 rebase origin/gh-pages
```

Copy the complete checked `.cache/release-4530632b7eb7/build/web` contents into this
Pages checkout without deleting existing sibling paths, then:

```powershell
git push origin main
python tools/publish_pages.py --directory .cache/combined-pages-4530632
python .cache/verify_combined_pages.py --source .cache/release-4530632b7eb7/build/web --bundle-commit ac2fff4caabdb9c881c596c10aeaecc33076344e
```

Full frozen validation passes96 test runs (95 Godot fixtures plus latency458/0),
parser/import, client/server smokes and Web export. Selected checks: native format
93/0, actual Main25/0 including bundled Mirage/catalog guards, VXLMain15/0,
Effects20928/0 with three explicit Dummy-renderer skips, falling43/0, fragment43/0,
UI284/0, combat HUD680/0, mobile controls10128/0, aim79/0 and TDM scene62/0.
Logs: `.cache/release-4530632b7eb7/.cache/logs`. Normal local Web starts, selects
Mirage, walks the spawn lane and presents rifle input; publication follows without
additional local exploration after the immediate-publication steering.

Eight public hashes match: metadata, HTML/JS/WASM/PCK, map, map notice and Inter
notice. Metadata identifies the exact source/map; Pages identifies the exact bundle.
Evidence: `.cache/combined-mirage-release/hashes.json`, `publication.json`,
`public-verification.json`. The existing reduced sibling metadata is retained.

Actual public Web starts with persisted touch/UI preferences, opens Mirage and
installs its spawn/map; keyboard movement and touch Fire work. Spade removes a floor
cell, a held block action places a gray cube after a valid preview, and current-map
reset restores the clean baseline/source spawn/level view. Unlimited resources keep
their existing preference, so ammo/stock counts are not shot/placement evidence.
Final warning/error console is empty; no preferences changed. Captures:
`.cache/previews/combined-mirage/public-menu.png`, `public-destruction.png`,
`public-block-edits.png`, `public-mirage.png`. Public game tab retained; temporary
combined local tab/HTTP helper closed. Earlier local conversion preview is retained.

Source main and publication evidence are pushed. Unrelated Steam investigation and
optimization-plan files remain unstaged. Map fidelity/routes and Mirage bot
navigation retain the earlier explicit limitations.
