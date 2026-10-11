# ADR 0018 — primary-button camera look for every item

Accepted 2026-10-11 after the user requested camera rotation while holding fire
for every weapon type. The three firearms already shared this gesture; the
remaining restriction was `current_tool == WEAPON` in MobileControls.

Allow a primary-button DOWN to claim free look for every selected item: rifle,
SMG, shotgun, spade, block and grenade. Retain the living player, own first/third
person camera, enabled controls and fire-drag preference gates. Existing LOOK
ownership, same-ID motion, action reference counts and lifecycle cancellation
remain unchanged.

Dragging outside the button keeps primary held and rotates yaw/pitch. UP releases
primary through the existing HUD/controller bridge, including grenade throw.
Item cadence, block placement, grenade timing, authority and transport remain
owned by their existing modules. This extends ADR0008's input adaptation; it
does not claim original touch support or full parity acceptance.

Verify all six selections through the production overlay and actual Main/HUD/
Player camera bridge, plus exported DOM touch events and ordinary browser input.
Record exact native/browser results in `docs/mobile-controls.md` and status.
