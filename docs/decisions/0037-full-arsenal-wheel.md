# ADR0037 — Optional full inventory and mouse wheel

Status: IMPLEMENTED pending verification/publication, 2026-10-13.

The user requests a menu option to carry all weapons and switch with the mouse
wheel. The Arsenal catalogue gains “Все 20 / All 20”. This grants all twenty
authored X01–X20 items in Lab, Survival and Rush. The fixed wheel is X01…X20,
then source (the current original class/tools backup), wrapping in both
directions. Source class indices remain 0…2; no new index reaches source arrays.
Ordinary TDM continues the existing original path. Wheel direction/disabled
preferences continue to apply. The wheel works with the optional touch HUD on;
GUI catalogue/menu scrolling retains its events.

Canonical loadouts include all_items only for strict boolean true. Disabled or
invalid flags are omitted, preserving old defaults and fingerprint bytes. Full
records use arsenal_all_v1 rather than arsenal_v1, with map, source class and
the four favourite slots still part of the key. Existing record sections and
old three class buckets are retained. Four slots and G/Z/C remain favourites.

Selection changes never refill inventory, consume stock or automatically invoke
support. Pending charge, vacuum and touch confirmation are cancelled safely.
Gameplay focus, pause, cards, catalogue, loading/readiness, death and wheel-zero
settings gate selection. Ammo, charges, cooldowns, life/epoch and world limits
remain the existing authority contracts. Lab changes take effect immediately;
Survival/Rush freeze the live mode and save catalogue edits for next attempt,
including Replay. Home “Classic kit” clears full mode and opts out; selecting
source during the full wheel preserves the enabled full preference.

Verification and release evidence will be recorded with source SHA, exact engine
and commands in docs/full-arsenal-evidence.md. Desktop viewport and synthetic
touch checks do not accept a physical phone or the complete OpenSpades port.
