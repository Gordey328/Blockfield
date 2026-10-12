# 0028 — Static death models on the optimization branch

Date: 2026-10-12, Europe/Moscow. Status: accepted by the user.

The target device is iPhone12 mini using Chrome. The quality-preserving Web pass
finds corpse simulation to be a large sustained-combat CPU cost, while other
render, player/authority and UI costs remain. The user explicitly permits removing
corpse physics entirely after the coordinator explains the measured cost and a
possible restricted-body profile. This approval covers static death presentation;
it does not authorize lower render resolution or unrelated graphical reductions.

Production Main creates the existing original Player/Dead model through a new
explicit static setup path. Its pose is captured at death with one bounded floor
projection, retaining team tint and resource reload support. Main performs no
per-frame corpse solver calls. Bodies do not move from impacts and do not fall
when their supporting terrain is later removed. Existing body limits and visibility
retention remain; authoritative death, hit, respawn and voxel rules are unchanged.
The existing physics implementation remains available for source differential
fixtures, but production chooses the static path.

The graphics preference's stored key remains compatible; its visible caption
becomes Bodies after death, describing whether death models are shown. The branch
has an explicit source-parity deviation in presentation, with no full-row status
promotion. Native fixtures and an exported actual-Main browser run must verify
static appearance, no solver dispatch, teardown and death/respawn behavior. FPS
and physical-phone acceptance remain evidence-driven; removing this component
does not prove the rest of the browser workload meets30fps.
