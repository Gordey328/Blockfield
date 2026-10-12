# Game UI first delivery

User scope2026-10-12: implement Home, map/loadout preparation and start in the
current combat HUD style, with phone adaptation. Proposed flow:
[UI plan](ui-ux-plan.md). Contract: [ADR0030](decisions/0030-game-shell-and-offline-launch.md).

## Source and ownership

Branch `codex/game-ui-first-delivery` starts from dev
`dee5603618ae237172b19a1156ff00543157986c` in the attached isolated worktree
`C:/Users/Gordey/.codex/worktrees/game-ui-first-delivery/Blockfield`.
Engine `4.7.2.stable.official.ed1daf0bf`; upstream OpenSpades
`dcf449c845d509bbde9d79239b32d201c1389961`; Compatibility/single-thread Web and
the accepted reduced template remain pinned.

Root owns entry/Main/LabHUD launch integration, loading lifecycle, shared build
registration/docs and serial engine/browser/release checks. `ui_flow_audit` owns
GameShell/new scene only. `hud_ux_audit` owns catalog, baked preview resources and
their reproducible renderer. `ui_launch_checks` owns the two new UI/integration
fixtures only. Contracts were agreed before parallel edits. The other chat's
local Dust2 conversion and unrelated optimization/Steam files stay outside this
worktree and public source.

## Development validation

Initial clean-cache editor/import invocation exits unsuccessfully during font
reimport without a SCRIPT ERROR/Parse Error diagnostic. Its output is retained
in `.cache/logs/ui-import.log`; it does not establish a parser pass. A retry seeds
only the unchanged Inter/unifont imported font/texture artifacts from the original
project cache, then repeats editor/import. Source fonts remain unchanged.
The subsequent diagnostic editor/import passes with native returncode0 and no
rejected engine diagnostics. The first affected gate passes all13 suites and two
client/server smokes: shell345/0, actual launch38/0, UI284/0, combat680/0,
mobile10128/0, mobile-look225/0, source-input35/0, lab119/0, TDM81/0, TDM scene62/0,
native Main25/0, VXL Main15/0 and network menu72/0.

Real Compatibility preview generation records7 outputs/0failures. Visual QA finds
weapon images incorrectly narrowed to341×192 by inherited viewport aspect; the
renderer now owns an exact512×192 viewport, asserts capture dimensions, frames
with22% margin and adds bake-only light. Rerender7/0 preserves original runtime
models/materials. Map images are640×360. Provenance and reproduction are in
game/assets/ui/menu.

Actual ordinary Web at1280×720 and375×812 reveals that local canvas scaling alone
cannot remove the project's16:9 KEEP letterbox. Shell now adopts CSS logical
dimensions/EXPAND while active. A new aspect-ratio check passes at six sizes
(390×844,844×390,1280×720,375×812,812×375,568×320). Scene detachment initially
prevented get_window-based restoration; the added regression fails before the
fix and passes415/0 with a cached Window and guarded teardown. Real Main launch
remains38/0. Compact landscape merges navigation into the header and presents
all three56px weapon cards; selected equipment has a textual check mark.

A repeated native Main fixture passes its25 assertions but leaks a stopped
Vorbis stream at exit. A verbose repeat passes; the fixture now drains200ms real
mixer time, consistent with existing mobile cleanup, and25/0 repeats cleanly.
This is test teardown only. The failed log is retained as
`.cache/logs/ui-gate-native-map-main-rejected.log`.

The real filtered dedicated export catches Entry's client global
LabInputBindings reference, although the ordinary server smoke passed. Entry now
resolves client-only helpers only on its client route. Repeated server export and
exported-PCK Title smoke pass. Linux execution/hosting is not claimed.

Local ordinary Web checks show readable Home/setup in portrait and landscape,
map/weapon selection, fixed start/footer, rotation retention, actual Crossroads
with selected shotgun6/48 and five bots, finished-match Home return, and
Mirage/SMG30/120 through the new training route. These are browser-sized desktop
checks; physical-phone ergonomics/performance remain open. The IAB mouse-capture
Chromium error uses the existing drag-look fallback. Captures are retained under
`.cache/previews/game-ui-browser`, including the rejected portrait. Frozen full
gate, final ordinary-browser checks and publication remain pending.
