---
name: blockfield-port-parity
description: Audit, implement and verify the OpenSpades v0.1.3 to Godot port in Blockfield. Use for feature migration, parity review and iteration acceptance.
---

Read docs/iterations.md for accepted scope and docs/parity.md for affected features. Source reference is .cache/openspades pinned in docs/status.md. Audit missing behavior from actual source; distinguish client prediction/presentation from server-authored rules that the local session must implement.

For each feature retain source evidence, Godot implementation location and behavioral verification. Use NOT_STARTED, IMPLEMENTED, VERIFIED or DEFERRED_ITERATION_2. Asset import, a passing parser and a successful export do not establish feature parity.

Original roster: three weapons, four tool selections, two team-colored soldier appearances and spectator. Do not invent additional heroes as original content. Local test controls may expose extra states/resources, clearly identified as test options.

Update docs/status.md with exact commands/results and next action at milestones. Record architecture choices in docs/decisions/. Never label iteration 1 complete while original client features remain unaccounted for.
