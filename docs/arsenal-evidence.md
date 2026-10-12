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

## Local ordinary Web pass before final mobile layout repair

Source c12506de8acc999e30a191f9f3a13b7a9e45c632 passes import,23 selected fixtures,
smoke and the ordinary single-thread Compatibility export. Actual new counts:
authority197/0, terrain812/0, view/audio131/0, panel188/0, records47/0,
Rush scene115/0, lab50/0. Combined unchanged first-freeze63 and second-freeze47
(nine repeated) give evidence for all101 registered fixtures. The exact current
log is .cache/logs/arsenal-frozen-c12506d.log. The roof still completes145 ticks;
this concurrent-browser native run measures41.098ms maximum, which must be kept
alongside earlier9.119–13.012ms observations rather than discarded.

Local desktop interaction at1280×720 uses the ordinary293/c125 engine/PCK.
The c125 pass additionally observes X13 gravity warning, X14 multicolor lure,
X15 three deployed banana models, X16 four-second warning and real crater,
X17 confirmed narrow hole, X18 confirmed line cuts and X19 supported turret.
The long original lab menu pause leaves the sun warning at3.6s when resumed.
The game-exported crater PNG is .cache/previews/arsenal-web/c125-pocket-sun-crater.png.
Only the IAB pointer-lock restriction appears in browser error logs; the original
drag fallback is used for desktop looking.

The ignored local arsenal-touch.html copies ordinary HTML and includes a bounded
DOM TouchEvent WebMCP driver. It changes no engine/PCK, authority, resources or
hidden game state; it reports isTrusted=false. Both helper files must be excluded
from publication. Synthetic DOM touch is explicitly not a physical phone test.
Touch mode is enabled using the original Settings UI and lab unlimited resources
are explicitly turned off for each new LocalSession. At844×390 real touch
selection/scroll/Fire/Aim observes: X01 magazine3→2, X02 4→3, X03 8→7,
X04 fuel240→193 with simultaneous joystick, X05 24→17, X06 1→0,
X08 battery180→139, X09 4→3 and actual pink cover, X10 held windup/cuts;
X11 stock3→2 and Aim-button remote crater, X12 2→1, X13 1→0 with pull field,
X14 2→1, X15 3→0 deploying its three mines, X16 1→0 plus X20 escape thrust,
X17/X18/X19 each2→1 after aim/confirm. X20 consumes both calls and physically
lifts the player with simultaneous joystick; thrust time is displayed. X07's
valid living-target lock and3→1 (two salvos) are observed by touch at1280×720;
invalid aim preserves stock. All twenty receive actual touch application, though
real zombie lure behavior in the exported Rush is still pending. The original
manual Respawn button restores life inventory and preserves the large crater.

Actual mobile inspection finds two UI defects missed by earlier native tests:
an immediate stale wrapped-height minimum before cards settle at390×844, and the
two-row bank covering the center aim at844×390. Width-derived card sizing and a
single-row bank with explicit actions drawer/confirmation are under repair;
this pre-repair pass does not accept the final mobile layout or publication.

## Frozen mobile repair and actual Web load results

Frozen78c8b9193105a0b461a9b3442b31ab7627488dbc passes all17 selected fixtures,
import, smoke and ordinary Compatibility export. Panel286/0 and new actual
benchmark node171/0 pass; the other six arsenal counts remain197/812/131/47/
115/50 as applicable. Composed evidence now covers102 registered fixtures.
Log: .cache/logs/arsenal-frozen-78c8b91.log. The ordinary export has clean source
metadata; only game/ui/arsenal_panel.gd differs from c125 in the production tree.
The final serial native terrain run measures9.798ms maximum/145 ticks; native
diagnostic driver helper total731.648ms/max10.332ms,179callbacks including8paused.
Draft PR5 is attached: https://github.com/Gordey328/Blockfield/pull/5. Dev remains
the finished Rush base until final ordinary/public acceptance.

Private diagnostic reproduction:

```text
python tools/export_arsenal_benchmark.py --revision 78c8b9193105a0b461a9b3442b31ab7627488dbc --import-cache game/.godot
python tools/serve.py --port 8128 --directory .cache/arsenal-benchmark-78c8b9193105/build/web
```

Use the bundled Python recorded in status.md. Import/export passes in
.cache/logs/arsenal-private-web-78c8b91.log. The private archive changes its copied
entry scene only and declares source_dirty=true/private diagnostic. Browser engine
reports4.7.2-stable(custom_build), full source hash
ed1daf0bf001b61586d9930840f2f1394092c079, templateSHA256a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922.

At1280×720 in the IAB, actual rendered roof/floor are inspected before/after.
Real Start/Pause/Resume freezes at tick10 across42seconds of wall time, then
finishes145ticks with24,576roof/24,580total canonical removals and real mesh drain.
That long pause truncates the bounded1200frame sample array; its average callback
rate is not an active-performance result. Saturated Pause freezes at tick39 with
50/64/12 caps across a further long pause; Reset disposes the incomplete job,
clears effects and restores a supported new-epoch roof. Its retained report
honestly remains incomplete. Fresh no-pause measurements below have no truncated
samples or failures, and finish with zero jobs/guards/foam:

| Actual private Web measurement | Plain collapse | Collapse + decorative saturation |
|---|---:|---:|
| Canonical removals / fixed ticks | 24,580 / 145 | 24,580 / 145 |
| Wall time through actual mesh drain | 3.0998s | 3.1817s |
| Render callbacks / observed callbacks per second | 166 / 53.55 | 120 / 37.72 |
| Helper CPU total / mean / max | 907.6 / 6.259 / 18.3ms | 855.7 / 5.901 / 17.3ms |
| Receipt/presentation CPU total / max | 514.3 / 9.0ms | 450.0 / 7.0ms |
| Median / maximum callback interval | 17.8 / 37.2ms | 24.4 / 222.4ms |
| Maximum draw calls | 63 | 189 |
| Actual particle/state/event peaks | 0 / 0 / 0 | 50 / 64 / 12 |

The saturation fixture requests96states and32events per burst to test admission;
it does not pretend these are extra live weapon/AI authority. Native runtime197
and actual scenes cover that authority separately. These measurements include
startup/warm effects and real rendering; the222.4ms worst saturated frame and
37.72callback/s mean explicitly do not establish stable60FPS or phone performance.
Raw game-button downloads and summary are in .cache/previews/arsenal-web/
78c-benchmark-{paused,pause-completed,plain,saturated-aborted,saturated,summary}.json.
The actual ordinary repaired UI, Rush/AI and public URL still need their final
checks. Neither diagnostic helper is part of the ordinary release folder.

## Late Web canvas cache repair

Ordinary78c Rush exposes a separate actual Web regression: Main initially reads
the1280×720 canvas, then frequent coordinator HUD refreshes reset the layout clock
before its .25s CSS polling deadline. The844×390 bank never adopts the correct
compact size. Home/native OS-size tests did not exercise this cache starvation.
A separate CSS polling clock fixes it without changing gameplay or touch claims.
The production-cache fixture uses read-only CSS-reader seams and retains the
unchanged1280×720 native window: before fix302 checks/5 failures/zero CSS reads;
after fix302/0, four reads/s, late landscape/portrait/desktop changes all pass.
Logs: .cache/logs/test-arsenal-panel-web-cache-{before,final}.log and
arsenal-panel-web-cache-import.log. Parser/import is clean on pinned4.7.2.
Final ordinary export/browser validation follows; no publication is inferred.

Frozen c4e5693f55bb999dfbfa412fec071dee227c88fa passes import,12 selected
source/mobile/UI/scene fixtures, smoke and ordinary export. Actual844×390 Rush
adopts the corrected single-row4+More bank; the center aim is clear and More
opens the actions drawer. A further read-only audit finds that repeated HUD
readouts erase earlier changes when composing a multi-category next-attempt kit.
Separate pending catalogue/live bank data and actual four-choice/replay regression
are being added. The catalogue copy now states the next-attempt boundary. The
568×320 closed/targeting aim area is also added to the measured UI fixture.
Final mutable Panel334/0 and real Main/Rush scene136/0 pass with clean import.
Actual four catalogue choices separated by18fixed/render frames each preserve
all pending fields, keep live stock/selection/equipment frozen, and Replay adopts
the full x03/x14/[x18,x19] kit with separate record identity. At568×320 both
closed and support-targeting banks measure y74–147, before the24px aim area
y148–172; all five targets remain56CSS and stock stays visible. Logs:
.cache/logs/test-arsenal-panel-pending-final.log,
test-arsenal-scene-pending-final.log and arsenal-panel-pending-import.log.
