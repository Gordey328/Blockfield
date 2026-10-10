# ADR 0002: Local testing authority

Date: 2026-10-10. Status: accepted for iteration 1 testing mode.

OpenSpades supplies a network client, not a standalone match server. The test
lab therefore runs `LocalSession` in-process without creating a server or asking
for connection settings. Input, presentation and voxel geometry remain separate.

Source weapon constants and timings are copied from the pinned client. Damage
authority, respawn and objective rules absent from the client are explicitly
authored offline policy: 3-second respawn, melee 100 damage, grenade quadratic
falloff inside 16 blocks with voxel cover, CTF pickup/resupply within 2 blocks,
TC progress from local occupants. These are not claimed as extracted server rules.

Session signals own grenade creation and fuse expiration. The world presentation
updates grenade positions and resolves terrain destruction/cover at detonation.
This prevents separate input and visual timers from producing duplicate grenades
or missing immediate/forced/death releases.

Unlimited stocks and invulnerability are test options, initially enabled. Two
team-colored soldiers and spectator reflect the original roster. Static and
moving targets expose source hit zones and player poses; they are not multiplayer
AI. Iteration 2 will reuse the simulation contract behind remote authority.
