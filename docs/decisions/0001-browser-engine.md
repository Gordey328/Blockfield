# ADR 0001: Godot browser baseline

Date: 2026-10-10. Status: accepted implementation baseline.

Use Godot 4.7.2 standard (GDScript), Compatibility rendering, single-threaded
Web export. The Windows executable was executed and reports
`4.7.2.stable.official.ed1daf0bf`. Matching web templates are pinned by bootstrap.

GitHub Pages is the client host. Single-threaded export works without configurable
cross-origin isolation headers. Assets and relative paths must work under
`/Blockfield/`. Multiplayer authority cannot run on Pages and needs a separate
service in iteration 2. Transport selection remains open until networking work.

The source baseline is OpenSpades v0.1.3, commit
`dcf449c845d509bbde9d79239b32d201c1389961`. Imported resource provenance is in
`docs/assets.md` and `game/assets/openspades/manifest.json`.

Platform-specific rendering features require explicit documented adaptations;
this decision does not silently waive their acceptance rows in `docs/parity.md`.
