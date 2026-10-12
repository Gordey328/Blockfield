# 0029 — Local Teardown voxel map conversion

Date: 2026-10-12. Status: implementation direction for the requested local Dust2
conversion; final fidelity and passage clearance require measured evidence.

The user supplies `C:/Users/Gordey/Desktop/dust2csgo` and requests adapting the
map to Blockfield block sizes. Its actual source is a Teardown XML scene with
MagicaVoxel150 resources and a Lua-generated heightmap ground. Use the current
`de_dust2.xml`, rather than the menu scene or legacy alternative.

Convert source occupancy and palette colors directly to the existing BFM1
package. Blender and mesh reconstruction are unnecessary for already voxelized
inputs. Compose XML parent/prefab transforms and named VOX model transforms
before resampling; apply the same uniform scale/translation to geometry and
source spawn markers. Retain air and an explicit occupied bit for solid black.
Do not change the one-unit game block, player dimensions or runtime map contract.

Choose a measured uniform meters-per-block scale that fits the64-block height
limit and standing player clearance. Report the sampling rule, counts, bounds,
safe spawn correction and every omitted entity/layer. Interpret only the actual
supplied ground generator's known height/material operations; never execute Lua
or claim arbitrary Teardown scripts are supported. Vehicles and props can become
static terrain; their physics/material/script behaviors are separate omissions.

Raw/source resources stay outside Git. The source author is CleverGrief and
info.txt explicitly contains `[noupload]`; preserve that provenance. The initial
conversion was local. The user subsequently explicitly requested immediate
publication ("да не нужно столько проверок заливай"). Bundle the single compiled
Dust2 package under assets/maps and publish the current approved dev runtime.
Local alternatives and provided sources remain excluded. No original port-parity
rows are promoted. Commands, exact versions/hashes, visual evidence and limits belong in
`docs/teardown-dust2-conversion.md` and `docs/status.md`.

Ownership: `teardown_format` owns the new converter modules only;
`teardown_tests` owns its independent Python test only. Root owns engine/browser
validation, local-map integration, shared configuration and evidence documents.
No runtime gameplay changes are currently necessary because Main already accepts
native packages and enumerates ignored local maps.
