# 0022 — Modern combat UI

2026-10-11. User requests researching current shooter HUDs and replacing the
boxy combat interface with a modern visual style.

Adopt edge islands with translucent rounded backing, large tabular ammunition
digits, a slim health bar, small line icons, subdued secondary text and clear
cyan/amber/red states. TDM has a centered team-colored score/timer capsule.
Touch action controls are circles; tool selection uses rounded tiles, icons,
short labels and a selected-tool accent. Labels accompany the icons.

CombatTheme supplies authored procedural line art and Inter4.1, OFL1.1, with
the existing multilingual fallback chain. This is a deliberate user-authorized
presentation replacement. Original tool/model/rule/input/map behavior remains
owned by the existing adapters; it makes no full-port/parity claim.

CombatReadout reads LocalSession (including NetworkSession/OfflineTDMSession),
renders identical calculated state exposed through get_display_state, and only
redraws on displayed state/layout changes. Its local get_panel_rects contract
supports checks across logical canvas sizes. Legacy semantic labels remain
transparent for current compatibility checks; bullet-strip drawing is disabled.
Health/resource islands hide in dead/spectator states; match score stays visible.

Combat styling belongs only to HUD/touch presentation. Touch hit regions,
minimum CSS sizes, pointer claims and input gestures retain their prior contract.
The block-color palette moves beside the minimap to clear the new ammo island.
Source sight/hit/hurt/TC feedback and imported map textures retain their paths.

References reviewed on2026-10-11:
- [Call of Duty Black Ops Royale HUD guide](https://www.callofduty.com/blog/2026/03/black-ops-7-black-ops-royale-battle-royale-deep-dive), March2,2026: edge status/ammo groups and numeric health.
- [THE FINALS gameplay capture](https://www.gamespark.jp/article/2023/12/13/136804.html): visual reference for thin health marks, small equipment and clear center.
- [Riot UI process](https://playvalorant.com/en-us/news/game-updates/preview-the-future-of-valorant-s-interface/), October10,2022: contrast/readability and simplified shape language; this article concerns its menus, not evidence of its combat HUD.
- [Inter authors](https://github.com/rsms/inter/tree/v4.1): font source/license.

No proprietary game artwork is copied into Blockfield. Verification and exported
browser screenshots are recorded in docs/ui.md and docs/status.md.
