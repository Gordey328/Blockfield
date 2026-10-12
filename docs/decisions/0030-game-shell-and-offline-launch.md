# 0030 — Game shell and offline launch

2026-10-12. User requests the first delivery of the proposed game UI: Home,
map/loadout selection and game start, styled like the existing combat HUD and
adapted for phones.

The ordinary entry scene creates GameShell without a voxel world, player,
effects or simulation. Dedicated-server selection keeps its existing route.
GameShell uses CombatTheme/Inter, baked real-game map and original weapon PNGs,
responsive containers and CSS-sized targets. It does not run a live 3D preview.
While GameShell owns the window it uses a CSS-sized logical viewport with EXPAND
aspect, so the original16:9 KEEP viewport cannot letterbox portrait menus. It
restores the prior window scale/aspect on teardown before Main creates its HUD.

GameMapCatalog is an authored whitelist. Launch configuration has exactly three
bounded values: mode (`tdm` or `training`), map_id and weapon index0–2.
Crossroads is the only3×3 choice. Lab/Title/Mirage are training choices; the UI
does not claim bot navigation or a new team assignment on imported maps.
The separate settings.cfg `play_selection` section preserves all existing
profile/input/audio/graphics/resource sections. Invalid saved selections revert
to a supported default; malformed settings files are not overwritten.

Entry validates a request, stores a one-shot `blockfield_launch` SceneTree
metadata handoff and changes to the existing Main/OfflineTDMSession scene.
Main consumes that handoff, keeps HUD/control gates closed, loads only a
catalog-authored resource through the existing atomic map pipeline, and selects
the weapon through its session adapter before opening gameplay. Double start
and retry requests are guarded. A launch overlay reports actual preparation or
measured VXL progress, with recovery/return Home on failure. It never synthesizes
an authoritative inventory or modifies network transport.

Legacy training/settings/network tools remain reachable. Their menu gains a
return Home action; scene teardown preserves the existing mobile/input cleanup.
This delivery does not redesign death/results/settings or add economy,
attachments, matchmaking or arbitrary-map bot support. It does not accept the
full OpenSpades port. Evidence belongs in game-ui-first-delivery.md and status.md.
