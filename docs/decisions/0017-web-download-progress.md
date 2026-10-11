# 0017 — Web download size on the startup screen

Date: 2026-10-11. User asks to show downloaded megabytes while loading the game.

Use `game/web/loading.html` as the Web preset's custom shell, based on the pinned
Godot4.7.2 template `godot.html`. Retain its engine startup, feature detection,
error notices, splash, relative export paths and overlay removal. Godot's existing
`onProgress(current, total)` supplies bytes; no second fetch or polling is added.

Show `Загрузка игры: 12,4 / 63,3 МБ` beneath the progress bar, using decimal
megabytes (1MB=1,000,000bytes) with one decimal. The denominator comes from the
exported `fileSizes` for WASM/game pack, so it is available before both downloads
start. A reported larger total is retained; unknown totals show only downloaded
MB and an indeterminate bar. After all bytes arrive, show `Запуск игры…` until
Godot finishes starting, then remove the overlay through the original lifecycle.
This measures the downloaded engine/pack body, including cached reads, rather
than network wire compression, map decoding, or multiplayer synchronization.

The shell stays inside the existing export pipeline so later exports preserve it.
Its numeric line uses tabular digits, responsive width and the bottom safe area.
Godot template license is retained in `licenses/godot/LICENSE.txt` and published
notices. Official contract: [custom HTML shell](https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html)
and [onProgress](https://docs.godotengine.org/en/stable/tutorials/platform/web/html5_shell_classref.html).

## Evidence

Frozen source `4a522ceca4edb7b007397331403915a24e689bc6`, Godot
`4.7.2.stable.official.ed1daf0bf`, upstream
`dcf449c845d509bbde9d79239b32d201c1389961`. Only HTML/preset production files
change versus the19c4d51 game; this does not claim a new89-gameplay-check run.
Import/parser, runtime smoke and normal Web export pass. Archive/logs are in
`.cache/release-loading-4a522ceca4ed`; root log `.cache/logs/loading-frozen-release.log`.
Reproducible engine commands against that archived clean project:

```powershell
./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path .cache/release-loading-4a522ceca4ed/game --editor --import --quit
./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path .cache/release-loading-4a522ceca4ed/game --quit-after 120
$loadingWebPath = Join-Path (Resolve-Path .cache/release-loading-4a522ceca4ed/build/web).Path index.html
./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path .cache/release-loading-4a522ceca4ed/game --export-release Web $loadingWebPath
python tools/publish_pages.py
```

The archive comes from `git archive --format=zip` at the above SHA, seeded with
the local `.godot` import cache; import still runs. Local throttled actual engine/
pack download shows1.2/63.3MB then enters the rendered lab; console
`.cache/logs/loading-local-console.json` retains the host pointer-lock error.
Pages bundle `56bbc6f09724a5e51b3d732b5a9a08df16c4141e` reports built/no error;
metadata has source_dirty=false. Independently downloaded metadata/HTML/JS/WASM/
PCK/both worklets match the frozen export; report
`.cache/benchmarks/loading-public-verification.json`, publication stdout
`.cache/logs/loading-pages-publication.log`. Original public load shows0.0/63.3MB;
a reload shows12.3MB in the accessibility tree and53.7MB in the next screenshot,
confirming live progress, followed by overlay removal/menu/offline lab entry.
Public console `.cache/logs/loading-public-console.json` contains startup messages
only, no warnings/errors. Screenshots `.cache/previews/loading-public-{progress,startup,game}.png`.
The startup screenshot is the resulting menu; the brief completed-byte caption
is implemented but was not separately captured. Both temporary loading-test
HTTP servers are stopped. No thread/PWA/authority, physical-device, Linux CI or
full-port acceptance is inferred from this UI change.
