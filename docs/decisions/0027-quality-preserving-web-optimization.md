# 0027 — Quality-preserving Web optimization

Date: 2026-10-12, Europe/Moscow. Status: accepted for the optimization branch.

The user requests maximum practical browser optimization in a separate branch.
Any reduction in graphical quality requires the user's approval after explaining
the expected benefit. This pass changes computation, retaining existing quality,
simulation rate, five-bot roster, input, effects limits and map/rule contracts.

CharacterView accepts optional nested begin/end pose transactions. Standalone
setters remain immediate; Main/LabSoldier use the transaction only when a skin
supports both methods. Final visible transforms, articulated animation and world-space
corpse updates are identical. Hottracking caches one exact validated pose, hit mask
and color; current eligibility/rays remain live. Palette content is per instance,
and minimap drawing tests each canonical actor once using its unchanged predicate.

Live multi-pellet shots lazily prepare source hit transforms once per eligible
actor/unchanged exact pose and life. Cache lifetime is one shot. Every pellet still
reads alive/team/order and current terrain; synchronous damage callbacks can
invalidate poses and generations. Single-ray and historical rewind paths retain
their existing interfaces and behavior.

AI clip-size decisions and per-tick weapon reload/fire gates use typed immutable
scalar accessors. Public `get_info` remains an independently mutable owned copy;
all six source profile/weapon combinations retain their existing values.

Collapse traverses sparse linear cell indices, preserving direction/DFS ordering,
support in both protected bottom layers, ordered changes/colors/groups and one
atomic transaction. Scratch containers are reused within the call and released
afterward; no second full-map mark array is retained. A completely empty chunk
halo can skip geometry/collision stages after its full data copy; final publication,
cache ownership, invalidation and cancellation retain existing behavior.

Main samples the sun terrain ray only while lens flare is enabled and clears
sources on disable. Network Main removes only its same-callback duplicate adapter
update; render/physics transport polls and Player command freshness stay intact.
Offline scenes never construct the network client. Removing networking code is
therefore not selected as an offline FPS optimization.

Actual Web3×3 profiling also exposes growing render-side physics cost in sustained
combat. Corpses retain their nine-point source solver, all four-or-more240Hz
substeps, line/point collisions, spring arithmetic, trajectories and existing16-body
cap. The plain production World uses a bounded256-cell occupancy cache inside one
synchronous step, cleared afterward; generic/subclass worlds retain their overrides.
Identical damping powers for the same dt are calculated once. A preserved original
corpse script in tests verifies every packed physics state and rendered matrix.

Validation uses independent old-algorithm/differential behavior fixtures, identical
paired CPU workloads and instrumented actual Main browser scenes. Browser frame
intervals and component CPU costs are distinct. Desktop IAB measurements cannot
certify every browser, phone, thermal behavior or full-port acceptance. Evidence
and reproducible commands live in [the branch report](../web-max-optimization.md).
