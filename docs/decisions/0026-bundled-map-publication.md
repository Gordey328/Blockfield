# 0026 — Bundled Mirage map in the combined development release

Date: 2026-10-11. Status: accepted by the user's explicit publication request.

## Context

After reviewing the successful local Mirage conversion, the user requests waiting
for the concurrent effects task to finish, combining both changes and publishing
them on GitHub Pages. This extends ADR0024's local-only experiment scope.

## Decision

Commit only the validated327,461-byte compiled map and its provenance notice under
`game/assets/maps`. Keep raw source assets, the Blender scene and unreviewed local
maps outside the public release. Retain the default export exclusion for
`assets/local_maps/*`; explicit bundled maps export normally.

Main enumerates bundled maps before local maps and deduplicates filenames. The
existing offline menu shortcut loads only enumerated paths through the same native
validator/baseline/reset lifecycle. Network and authored TDM maps keep their own
selection and authority. Starting the game still enters the existing lab.

Web export publishes an identical downloadable map/notice under `maps/` and records
its SHA256 in build metadata. Release checks run against a frozen committed source
containing the finished effects task and map integration; publication follows
ADR0003 and verifies both public hashes and normal browser map/tool behavior.

## Limits

The user-supplied map archive does not identify a separate redistribution license
or a complete author list. Preserve that provenance uncertainty rather than claiming
ownership or applying the code license to the map. Static conversion limitations
in `docs/mirage-conversion.md` remain; publication does not establish complete-port
acceptance, Counter-Strike behavior or verified Mirage bot routing.
