# Twenty-item arsenal evidence

Updated 2026-10-13, Europe/Moscow. Status: IMPLEMENTED; exported browser and
publication acceptance remain pending. This is user addition A04, separate from
original OpenSpades parity. Base Rush is 3a39e6445e942855ac202714bbdc8a42cddd3921.
Engine: Godot 4.7.2.stable.official.ed1daf0bf, Compatibility, fixed 60 Hz.
Upstream: dcf449c845d509bbde9d79239b32d201c1389961.

The [design and primary game references](arsenal-plan.md) define twenty original
mechanisms. [ADR0036](decisions/0036-authored-arsenal.md) defines authority, loadout,
world and lifecycle boundaries. Every row below has actual damage/world/state
assertions in `tests/gameplay/test_arsenal_runtime.gd`, with canonical terrain
and scene coverage rather than a catalog-only assertion.

| ID | Native mechanism evidence | Ordinary Web evidence |
|---|---|---|
| X01 Штопор | Charge, eight-cell span, two actors, cover before cuts, bedrock, cancellation | Pending |
| X02 Кирпичемёт | Swept gravity projectile, damage and collision-aware impulse | Pending |
| X03 Скрепка | Four visible chained targets, falloff and slow, cover between links | Pending |
| X04 Утюг | Finite sustained fuel/heat, sticky burn, fire removes cold, self risk | Pending |
| X05 Морозилка | Accumulated slow/freeze, timed thaw, life identity and heavy shatter | Pending |
| X06 Бумеранг мясника | Returning swept saw, ricochet cap and one live saw admission | Pending |
| X07 Улей | Visible target lock, generation validation, three swept homing projectiles | Pending |
| X08 Пылесос проблем | Pull under held input, release push, cancellation never pushes | Pending |
| X09 Пеноплюй | Supported placement, actor clearance, ownership/expiry, bounded 36 cells | Pending |
| X10 Гравимолот | Windup, local impulse/cuts and frozen-target shatter | Pending |
| X11 Снос по расписанию | Three sticky charges, support/version guards, remote detonation/finite timeout | Pending |
| X12 Попкорн | Five bounded bouncing descendants, staggered explosions, capacity reservation | Pending |
| X13 Чёрная дырочка | Finite pull field, collision-aware motion and one final blast | Pending |
| X14 Дискотека | Reachable visible lure changes real zombie AI; existing bite keeps its target | Pending |
| X15 Банановая республика | Three finite armed mines, launch and capped chain reaction | Pending |
| X16 Карманное солнце | Four-second warning, real crater and owner death, one stock, deferred work retained | Pending |
| X17 Небесный перфоратор | Warning preserves terrain; narrow finite roof penetration, cover/bedrock | Pending |
| X18 Рояль в кустах | Five warned falling impacts, line placement, finite support and five notes | Pending |
| X19 Турель в чемодане | Destructible visible target helper, sixty rounds/expiry, occlusion | Pending |
| X20 Пинок небес | Finite thrust and stock, native collision/ceiling, pause/fuel and reset | Pending |

`test_arsenal_terrain.gd` checks concurrent replacement/support, receipt
backpressure, bounded work, ownership, cancellation and observer disposal. A
24,576-cell detached roof completes in 145 fixed ticks. Native maximum step
observations of 9.119–13.012 ms are CPU measurements, not browser FPS guarantees.

`test_arsenal_scene.gd` uses actual Main, shared Rush, canonical map, real mouse
and ScreenTouch Fire, AI lure and freezing, kill credit/cards, field-kit stock,
loading/pause/countdown, support confirmation, terminal death, records and replay.
`test_arsenal_lab.gd` uses actual training Main with rendering suspended to prove
independent fixed ticks, and covers source controls, focus cancellation, death,
ordinary respawn preserving the map and explicit same-epoch generation reset.
`test_arsenal_records.gd` uses isolated storage to check full gameplay identity,
source backup class, map/version separation, malformed values and source buckets.

View/UI/audio fixtures check twenty distinct cached silhouettes and PCM clips,
64 authority-state meshes, 12 one-frame beam/impact meshes, warning priority,
four reusable audio voices, and real desktop/touch catalog behavior. New geometry
does not emit particles; the existing total 50 decorative-particle cap is retained.
New held geometry is first-person only. Third-person source soldier held models
remain their original class; this does not claim new third-person weapon animation.

An early 38/1 actual lab run revealed a dead-owner host clock stopping committed
foam cleanup. The clock is now life-independent; damage/input admission still
rejects death. Survival finish also cancels per-life effects itself because a bite
can occur after the arsenal step. Initial audio fixture shutdown reported 18
WAV/playback references: a 1.25-second asynchronous completion wait now proves
four captured WeakRef playbacks release, without filtering diagnostics.

The pre-existing 120-frame Entry smoke reports 11 zero-reference RefCounted
instances at shutdown. The same count is present in the finished Rush baseline's
`runtime-smoke.log`; new verbose evidence is `.cache/logs/arsenal-smoke-verbose.log`.
This inherited diagnostic is retained explicitly and is not described as a clean
shutdown. The new arsenal fixtures have no corresponding warnings.

First freeze 3e882480428c584b428556f7f95473619686a301 fails at Home UI after
passing original source and TDM/Rush authority. Arsenal added a third row of
secondary buttons at 568×320. The fix uses three compact columns and short text;
expanded Home/Rush UI now checks the Arsenal action too (298/0 mutable run).
The failed freeze is retained; no export from it is published.

Final frozen source, reproducible commands/counts, browser captures, performance
limits and public SHA256 comparison will be appended after their actual runs.
Physical phone acceptance and full OpenSpades port completion are separate.
