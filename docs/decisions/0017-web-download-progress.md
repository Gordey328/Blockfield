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
