---
name: blockfield-web-release
description: Build, check and publish the Blockfield Godot browser game on GitHub Pages. Use for web export, release readiness and deployment.
---

Read docs/iterations.md and docs/status.md first. Use pinned engine/export templates, Compatibility and browser-supported GDScript/native builds. Never substitute a hand-built JavaScript game for the Godot export.

Run import/parser and behavioral checks, export from game/, serve the resulting build and test start/input/audio/settings/map/tool behavior in a real browser. Single-threaded output is the initial Pages baseline; verify thread/extension requirements if they change.

Keep paths relative so project Pages URLs work. Use .github/workflows/pages.yml when Actions is available, or the documented branch-publication path in docs/decisions/0003-pages-publication.md and tools/publish_pages.py. Verify the actual deployed URL. Credentials stay outside source and logs. Record build commit, engine version, test results, URL and remaining deviations.

The user has already authorized creating the GitHub repository and publishing. Release completion still requires the parity gate; early exports must be identified as development builds.
