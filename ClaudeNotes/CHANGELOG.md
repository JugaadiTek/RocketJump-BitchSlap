# Changelog

Running log of changes made to RocketJump BitchSlap. Newest first.

All entries verified against Godot 4.7.1 running headless, via the probe scenes
in [`tests/`](../tests) — see **Test harness** at the bottom.

---

## 2026-08-13 — Session 13: fixed the four Session 12 bugs, applied three recommended optimizations, towers now always full circumference

Follow-through on Session 12's audit: fixes for all four reported bugs,
the three recommended optimizations, and a requested tuning change (tower
height). Verified against the same real binary, same method (probe suite,
not read-off-the-source).

### Bug fix: ladder climbs stalling on tall towers
Root cause confirmed: `Player._update_planet_frame()` releases the current
planet frame once altitude exceeds `planet_frame_height * planet_frame_release_ratio`
(36.4m) - correct for open-air flight, but climbing is locked, planet-carried
motion for the ladder's WHOLE length regardless of height (see
`_apply_ladder_movement`). Past that altitude the player's transform stopped
being carried by the host planet's spin/orbit while the ladder itself (a
child of that same planet) kept moving, so the two silently drifted apart
until the player fell out of the ladder's own narrow trigger volume.
`_update_planet_frame()` now stays locked to the current frame body for the
whole climb whenever `_is_on_ladder()` is true. Verified with structural
collisions suppressed for the test window (see below): a 226m climb now
proceeds cleanly and monotonically past the old ~36m stall point (1→12→24→35→46→57→69m,
`on_ladder=true` throughout) instead of stopping at 8-32% of the tower's height.
[scripts/player/Player.gd](../scripts/player/Player.gd)

**Test-only finding surfaced while verifying this**: with every tower now at
a large, constant `structure_reach` (see the tower-height change below),
`GravityManager`'s real, unforced structural-collision contact distance grew
enough that a long climb on the arena's single furthest-out body could get
its own tower demolished mid-test by an ordinary, unrelated orbital
collision - correctly reproducible, and confirmed via `Building.is_demolished()`/`OrbitalBody.is_shattered`,
not a ladder defect. `WorldProbe`'s tower-height test now detects this
distinctly (so it never gets misread as a climb failure again), suppresses
it via `collision_cooldown` for its own verification window, and runs before
`_test_structural_collision()` instead of after.
[tests/WorldProbe.gd](../tests/WorldProbe.gd)

### Bug fix: spawn point no longer inside the live boundary
`Spawner.SPAWN_RADIUS` was a constant (505m) chosen once, "clear of Halcyon
(476)" - it never adapted once `GravityManager.arena_half_extent()` started
flexing with live structure_reach. Replaced with `Spawner._spawn_radius()`
(static), computed fresh each spawn as `arena_half_extent() - SPAWN_BOUNDARY_MARGIN`
(30m, clamped to a 100m floor) - spawns now stay a fixed margin inside
whatever the boundary currently is, however far a tower pushes it out.
[scripts/player/Spawner.gd](../scripts/player/Spawner.gd)

### Bug fix: slugs no longer go inert against building walls
`Slug._process_flying()` only recognised a hit as "landed" (`orbital_body`
meta) or "hit a player" (`apply_damage`) - a Tower/Bunker/Turret wall matched
neither, so the slug just sat there, still `FLYING`, for the rest of its
lifetime. Added a fallback: any other solid hit now expires the slug, the
same way a shot that misses everything already does. Verified: a slug fired
straight at a tower wall now shows `freed` within 2 seconds instead of
sitting there alive with near-zero residual speed.
[scripts/weapons/Slug.gd](../scripts/weapons/Slug.gd)

### Bug fix: grapple-triggered Bitchslap actually lands now
Two compounding issues, both fixed:
- `Melee.try_activate()` now takes an optional `forced_target`. Reeling a
  player to point-blank range and then re-running `_find_target()`'s own
  range/cone scan could (and in testing, reliably did) reject the very
  target the pull just delivered, since a pulled target approaches along the
  line TOWARD the shooter, not necessarily inside whatever direction the
  shooter's camera currently happens to face. `GrapplingHook._do_pull()` now
  passes `_pull_target` directly, skipping the redundant re-scan for this
  one caller (manual melee still goes through `_find_target()` unchanged).
- While verifying this, found and fixed the *test's* aim: `Weapon.fire()`'s
  `aim_direction` is the camera's forward vector used as-is from the
  MUZZLE's own (offset) origin - the two rays are parallel, not converging,
  so aiming the crosshair exactly at a close target can still send the
  muzzle's ray past it. Not a gameplay bug (a real player's crosshair is
  typically close enough to the muzzle for this offset to be negligible past
  a couple of metres), but it made the probe itself whiff until corrected.
- Verified end to end: hook reels target to point-blank range, auto-slap
  fires, target dies.
[scripts/melee/Melee.gd](../scripts/melee/Melee.gd),
[scripts/weapons/GrapplingHook.gd](../scripts/weapons/GrapplingHook.gd),
[tests/WeaponProbe.gd](../tests/WeaponProbe.gd)

### Bug fix: melee keybind now documented correctly
`InputSetup.gd`'s `"melee"` InputMap action bound **F**; `Player._wants_melee()`
has only ever hardcoded **V** and never read that action - purely a stale,
misleading binding for anything that might surface it. Changed to **V** to
match reality.
[scripts/autoload/InputSetup.gd](../scripts/autoload/InputSetup.gd)

### Optimization: bot line-of-sight raycasts spread across frames
Every bot's `_retarget_timer` started at 0.0, so all of them re-ran
`_find_enemy()`'s O(bots) line-of-sight raycast sweep on the exact same
physics frame every 0.25s, then went quiet - a periodic burst instead of a
steady cost. `Bot._ready()` now seeds `_retarget_timer` with a random offset
in `[0, retarget_interval)`, so the same total work lands spread across the
interval instead of spiking once per quarter-second. Total cost is
unchanged (~3ms/s of play, unavoidable given the raycast count) - this
smooths frame-time variance, which is what a player actually feels.
[scripts/ai/Bot.gd](../scripts/ai/Bot.gd)

### Optimization: death-effect skull texture cached
`DeathEffect._skull_texture()` baked a fresh 96x96 image (~3ms, measured)
on every single death, unlike every other generated texture in the project
(`OrbitalBody`'s bump map, `Asteroid`'s shared mesh), which are cached once.
Split into a cached `_skull_texture()` wrapper over a `static func _build_skull_texture()`.
Measured: 3.375ms → 0.003ms per call after the first; an 8-death burst went
from 24.1ms total to 0.004ms.
[scripts/world/DeathEffect.gd](../scripts/world/DeathEffect.gd)

### Optimization: scoreboard sort no longer runs every physics tick unconditionally
`MatchState.get_all_scores()` rebuilt and `sort_custom()`'d its whole list on
every call, and `Player._physics_process()` calls it unconditionally every
physics tick for the local human's own HUD regardless of whether any score
actually changed. Added a `_scores_dirty` flag, set on `register_player()`/
`unregister_player()`/a real score change, and cleared once the list is
rebuilt; `get_all_scores()` now returns the cached list on every unchanged
call. Measured: 128.3us/call (63 players) → 0.191us/call, a 670x drop on
the common case.
[scripts/autoload/MatchState.gd](../scripts/autoload/MatchState.gd)

### Change: tower height now always the full circumference
Per request: was randomised between a planet's radius (min) and circumference
(max); now always the circumference (`TAU * radius`), consistently, subject
to the same existing safety trim for permanently-fixed-separation pairs
(the central binary, a moon and its own parent). Real, measured cost of
always taking the top of the old range rather than sometimes: worst-case
single-tower build time unchanged in isolation (~192ms, same ceiling as
before), but arena load time rose from ~295-320ms to 497ms (every
tower-bearing body now pays it, not just whichever ones randomly rolled
tall), and `PerfProbe --sustained` reads 9.07ms mean / 97 of 2400 frames
over 20ms - both broadly in line with Session 12's already-flagged tower-height
cost, not a new regression. The three optimizations above measurably helped
here too: spike count is down from Session 12's own 169/2400 despite every
tower now costing the maximum instead of a random draw.
[scripts/world/Arena.gd](../scripts/world/Arena.gd)

---

## 2026-08-13 — Session 12: full performance + feature audit (no fixes applied)

Audit only, requested end-to-end: rank every system's real runtime cost and
exercise weapons/navigation for bugs. Everything below is a fresh measurement
from this session, not a re-statement of Session 11's numbers, taken with the
same real binary (`x:\Godot_v4.7-stable_win64.exe`) - headless for the
gameplay probes, real D3D12/RTX 3060 renderer for `PerfProbe`/`LoadProbe`.
Deliberately **no gameplay code was changed** - only `tests/` gained
permanent new coverage (`AIProbe.gd`, new checks in `WeaponProbe.gd` and
`WorldProbe.gd`, a worst-case tower timing in `LoadProbe.gd`,
`ProbeLocalPlayer.gd`) so these numbers and checks can be re-run and diffed
by whoever picks up the findings next. Full tables (performance, ranked
descending, with recommendations; bugs, with repro) are in the published
audit artifact rather than duplicated here in full - see the two
highest-value findings below.

### Confirmed: Session 11's tower-height change is the dominant cost, independently reproduced
`PerfProbe -- sustained` today: mean 8.80ms (114fps), p95 21.62ms, 169/2400
frames over 20ms - matches Session 11's own "~9-10ms, spikes far more
variable" note, not a fluke. `LoadProbe` extended with a worst-case sample
(a tower built at the new ceiling, `TAU * radius`, on the biggest live
planet): **187ms for one tower vs 8.9-10.4ms for the old fixed 30m sample -
an 18x cost per tower that happens to roll near the top of the range.**
[tests/PerfProbe.gd](../tests/PerfProbe.gd), [tests/LoadProbe.gd](../tests/LoadProbe.gd)

### Bug: climbing a very tall tower's ladder stalls partway up
Built `WorldProbe._test_tower_height_range()` to specifically climb the
TALLEST tower generated (137m on a 36m-radius planet, this run) rather than
"the first tower found" (which prior tower/ladder checks always picked, and
which is normally short). Result: the climb reaches 43.6m and stops for
good - `_is_on_ladder()` goes false at that height and never recovers, even
with 2380 frames (10x the original 420-frame budget) of held climb input.
The stall height lines up closely with `Player.planet_frame_height` (26m)
times its own release hysteresis (1.4x = 36.4m) - climbing back out past the
altitude where the planet stops being the movement reference frame is the
leading theory, not confirmed by a code fix. A 21m tower in the same run
climbs cleanly to its top with no issue, so this is specific to the new
height range, not a pre-existing ladder bug. Not fixed here - flagged for
whoever picks this up, with the repro now a permanent regression check.
[tests/WorldProbe.gd](../tests/WorldProbe.gd)

### Also new in `tests/`, not yet a bug fix
- `BOUNDARYSPAWN`: `GravityManager.arena_half_extent()` now measures
  656-658m against a live tall tower, past the fixed `Spawner.SPAWN_RADIUS`
  (505m, chosen "clear of Halcyon" back when nothing reached that far) -
  spawns can now land inside the actual flexing play boundary instead of at
  its edge.
- `SLUGTOWER`: a slug fired straight at a Tower wall goes inert (stays
  `FLYING`, alive, near-zero speed) instead of landing, hitting, or expiring
  - `Slug._process_flying()` only recognises a hit tagged `orbital_body` or a
    damageable collider; plain building geometry is neither.
- `HIGHLIGHT`, `LADDERDEATH`, `PLANETSHADER`: all verified working correctly
  (scope enemy-highlight on/off/holster/local-gating; ladder-death
  collision-mask restore; shattered-planet fragment colouring) - included in
  the artifact as clean passes, not just failures.
- `AUTOSLAP`: the grapple-triggered Bitchslap's own trigger condition
  (`GrapplingHook`'s `<3.0m` check) fired every time across several
  point-blank pulls in a controlled grounded test, but `Melee`'s own
  range/cone re-check whiffed every single one (`melee._cooldown_remaining`
  stayed 0.00s throughout) - the code's own comment already accepts an
  out-of-cone no-op as possible, so this isn't necessarily a bug, but a 100%
  whiff rate across repeated clean pulls is worth a human playtest to see if
  it feels broken.
[tests/AIProbe.gd](../tests/AIProbe.gd) (new),
[tests/ProbeLocalPlayer.gd](../tests/ProbeLocalPlayer.gd) (new),
[tests/WeaponProbe.gd](../tests/WeaponProbe.gd),
[tests/WorldProbe.gd](../tests/WorldProbe.gd),
[tests/LoadProbe.gd](../tests/LoadProbe.gd)

---

## 2026-08-12 — Session 11: planet shader rework, tower height overhaul, railgun scope polish, auto-slap

Verified against the same real Godot 4.7 binary Session 10 found
(`D:\Godot_v4.7-stable_win64.exe`) - headless for the gameplay probes,
real D3D12/RTX 3060 renderer for LoadProbe/PerfProbe.

### Improvement: planet material rewritten as a custom shader
Two asks that a plain `StandardMaterial3D` genuinely can't do together: halve
the bump-map strength (easy, just a scalar), and make the triangle edges a
**hue rotation** of each planet's own colour (not easy - every planet has a
different base colour, and multiplying by a baked tint can't rotate hue
relative to a colour it doesn't know in advance; that needs real HSV math).
Planets now use `scenes/world/planet_surface.gdshader`: samples the same
shared triangular-lattice texture as before, but the texture's ALPHA channel
(unused by a plain normal map) now carries the raw edge-distance value, which
the shader converts the planet's `albedo_color` to HSV, rotates by up to
`hue_shift_degrees` (default 45) scaled by that edge value, and converts
back - full strength right on a triangle edge, none at a cell's centre.
`normal_scale` halved (0.75 -> 0.375) per request. `OrbitalBody.gd`,
`Arena.gd`'s per-planet colour assignment, and the atmosphere-tint lookup all
updated from `StandardMaterial3D` property access to `ShaderMaterial`
`set_shader_parameter`/`get_shader_parameter` calls.
[scenes/world/planet_surface.gdshader](../scenes/world/planet_surface.gdshader) (new),
[scenes/world/OrbitalBody.tscn](../scenes/world/OrbitalBody.tscn),
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd),
[scripts/world/Arena.gd](../scripts/world/Arena.gd)

### Improvement: tower height now radius-to-circumference
Was capped AT the planet's radius; now randomised between the radius
(minimum) and the full circumference (`TAU * radius`, maximum) - towers can
end up several times taller than the planet they stand on. Kept the existing
safety trim intact for the specific pairs `_solve_structure_heights()` exists
to protect (the phase-locked central binary, and a moon against its own
parent - permanently fixed separations where two full-height towers could
grind forever): those bodies' `height_budget` is still respected as a hard
cap even when it comes out below the planet's radius; every other body gets
the full new range. **Performance tradeoff, not hidden**: `PerfProbe
--sustained` after this change measured noticeably heavier than Session 10's
verified baseline (mean ~9-10ms vs. ~4-5ms, spike counts far more variable
run to run) - a large fraction of that is very likely the straightforward
cost of towers that can now be 5-6x taller (proportionally more floors,
walls, windows, and collision shapes per tower). That's the direct, expected
consequence of the requested range, not a bug snuck in alongside it, so it
wasn't scaled back - flagging it here rather than deciding unilaterally that
the request was too expensive.
[scripts/world/Arena.gd](../scripts/world/Arena.gd)

### Test-run finding, not a bug: WorldProbe's CRATERHIT number swung wildly
While verifying the above, `_test_crater_collider()`'s reported "surface
dropped Xm" jumped from a stable ~1.00m to ~12m and back depending on
whether the new tower-height randomisation was active - alarming at first
glance. Root cause: `WorldProbe.gd` runs `_test_structural_collision()`
(which deliberately forces two bodies into a full artificial overlap to
exercise the crater-scaling code) immediately before
`_test_crater_collider()` measures its own separate crater on one of the
SAME bodies - crater vertices accumulate rather than reset, so the second
test's measurement was never fully isolated from the first's. Adding a new
`randf_range()` call per tower during Arena setup (for the new height range)
shifts every subsequent draw from the same seeded RNG stream, changing
exactly which bots do what and when throughout the rest of the run and, by
extension, whether the two tests' craters happen to land near enough to
compound. The underlying mechanism was already safety-clamped (max
displacement 0.6x radius, so a 28m-radius planet never loses more than
16.8m, always leaving a non-degenerate positive remainder) both before and
after - this is test-ordering sensitivity surfaced by adding a new source of
randomness, not a new defect in `apply_crater()` or `structural_collision()`.
Not changed; noted for whoever next sees this number jump around.

### Bug: Railgun scope had an unwanted inner ring
`scenes/ui/scope.gdshader` drew a bright ring tracing the lens edge, inside
the blur/darken border - removed per request; the blur-to-dark falloff alone
still reads clearly as the edge of the optic. Crosshair reticle unaffected.
Orphaned `ring_thickness` uniform (and its `.tscn` override) removed too.
[scenes/ui/scope.gdshader](../scenes/ui/scope.gdshader),
[scenes/ui/HUD.tscn](../scenes/ui/HUD.tscn)

### Improvement: Railgun scope highlights other players, pans 30% faster
`scope_sensitivity_multiplier` raised from 0.18 to `0.18 * 1.3` - still much
slower than hipfire (a mouse-sensitivity cut is what keeps a narrow FOV from
feeling frantic), just less sluggish than before. Separately, scoping in now
gives every other player's model a bright unshaded red overlay for as long as
the scope stays active (restored on holster/un-scope), so a low-poly
silhouette is actually easy to spot at range. This is purely a local
rendering decision - each client renders its own independent copy of every
Player node (only position/state replicates over the network, not material
overrides), so highlighting a remote player's model here never appears on
their screen or anyone else's. Gated to `is_first_person_view()` specifically:
bots carry and can scope this same weapon, and without that check a bot
scoping in offline would highlight everyone from the one shared screen with
no human having asked to look through a scope.
[scripts/weapons/Railgun.gd](../scripts/weapons/Railgun.gd),
[scripts/player/Player.gd](../scripts/player/Player.gd)

### New: grapple into an automatic Bitchslap
Reeling a hooked player all the way in (within 3m, the same range the pull
already used to detach) now calls `Melee.try_activate()` on the shooter
before releasing the hook, instead of leaving the follow-up to a separate
button press. Reuses Melee's own target-finding (range + look-cone) rather
than force-feeding it the grappled player directly, so this only actually
lands if they're still roughly in front of the shooter when the pull
finishes - the same condition a manually-timed slap would need to meet.
[scripts/weapons/GrapplingHook.gd](../scripts/weapons/GrapplingHook.gd)

---

## 2026-08-12 — Session 10: single flexing boundary, deck rework, turret, real perf regression caught and fixed

First session this environment had a real Godot binary
(`D:\Godot_v4.7-stable_win64.exe`, 4.7.stable) - every claim below is from an
actual run, headless for the gameplay probes and with the real D3D12/RTX 3060
renderer for LoadProbe/PerfProbe, not the "not yet run" caveat the last two
entries had to carry.

### Correction: one single boundary box, not one per planet
Session 9's per-planet box (each planet got its own 50m box, "in bounds" if
near ANY of them) was a misread of the ask. Replaced with what was actually
requested: **one** box for the whole arena, centred on the arena origin,
sized to whichever planet currently reaches furthest out plus a margin
(`GravityManager.arena_half_extent()`) - it flexes as orbits drift and
planets are destroyed, but there's only ever the one wall, and it never shows
up out in open space between two worlds the way a per-planet box could.
`ArenaBoundary.gd` no longer tracks the local viewer's nearest planet either -
it's just the one box, resized every frame. Projectiles (`Projectile.gd`,
`Slug.gd`) check the same single box instead of the old fixed-radius sphere,
so a shot that misses everything now actually gets cleaned up at the edge
instead of living out its full lifetime timer in the void.
[scripts/autoload/GravityManager.gd](../scripts/autoload/GravityManager.gd),
[scripts/world/ArenaBoundary.gd](../scripts/world/ArenaBoundary.gd),
[scripts/weapons/Projectile.gd](../scripts/weapons/Projectile.gd),
[scripts/weapons/Slug.gd](../scripts/weapons/Slug.gd)

### Performance regression caught and fixed by actually testing
`PerfProbe --sustained` on real hardware told a very different story than
reasoning about the code did: mean frame time roughly doubled and frames
over 20ms went from a baseline **4/2400 to 219-398/2400** depending on run -
a chaotic 31-bot match would have stuttered hard maybe 1 frame in 10.
Bisected with `git stash` against the pre-session commit to get a true
baseline, then piece by piece: reverting the OrbitalBody.gd changes alone
made it *worse*, ruling that file out; reverting the whole boundary system
(GravityManager/Player/Projectile/Slug/ArenaBoundary) dropped it straight
back to baseline (6/2400). Cause: `arena_half_extent()` is an O(bodies) scan,
and unlike the local-viewer lookup fixed the same way in Session 8, it
wasn't cached - every one of 31 players plus every active projectile was
redoing that scan from scratch every physics tick, and the boundary shell
redid it again every render frame. Cached per physics frame (nothing it
reads changes except during a physics step, so the cached value is never
stale), the same pattern `find_local_viewer()` already used. Re-verified
twice after the fix: 4.02ms/1 spike and 4.68ms/1 spike - at or better than
the pre-session baseline. `PerfProbe.gd` now also logs live body count, and
its old spot-check nature is worth restating: this only surfaced because the
probe was actually run with a real renderer, not inferred from the code.
[scripts/autoload/GravityManager.gd](../scripts/autoload/GravityManager.gd),
[tests/PerfProbe.gd](../tests/PerfProbe.gd)

### Test fix: WorldProbe's foundation check was silently measuring the wrong thing
While running the suite, `_test_foundations()` reported a Tower floating
+7.57m above its planet - alarming, until tracing it back to Session 6's
mesh-merge optimization: `Building._commit_shell()` welds every wall/box
into ONE `MeshInstance3D` with a single `ArrayMesh`, so the per-piece
`BoxMesh` scan this test relied on stopped finding walls or foundations
years (well, sessions) ago - the only individual `BoxMesh` children left on
a building are the roof flag and light bulbs, deliberately elevated
fixtures. The test had been quietly reporting "how high is the flag" instead
of "does the building touch the ground" ever since, with nothing to flag
that it had gone stale. Now reads the merged shell's actual mesh vertices
(`get_faces()`) when there's no BoxMesh to inspect. Re-run: worst case is
now -0.95m (embedded into the surface, the intended foundation sink), not
floating.
[tests/WorldProbe.gd](../tests/WorldProbe.gd)

### Improvement: planet-to-planet collisions actually resolve now
Root cause of "planets squishing together and dragging": `GravityManager`
triggers a structural collision once the two bodies' BUILDINGS come into
reach, which is usually well before their bare rock touches - so the
deformation added last session almost always computed zero overlap on the
opening hit. With a 3-second cooldown between corrections, a slow sustained
approach got one small nudge and one small crater every three seconds while
the rock kept sinking into itself in between. Two changes: the orbital kick
now scales up sharply (up to 6x) once there's genuine rock overlap rather
than just a mass-ratio nudge regardless of depth, and the cooldown dropped
from 3.0s to 0.5s, so sustained contact keeps getting corrected every few
tenths of a second instead of every three.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

### Fix: Railgun scope - the barrel was still blocking the view
The tube/lens fix from two sessions ago wasn't the whole story. Scoping in
slides the WHOLE viewmodel so the scope lands on the camera axis - and the
barrel (`Body`) was authored only ~5mm off the scope's own X/Y offset to
begin with (they're meant to look roughly coaxial at rest), close enough
that the slide dragged the barrel onto the camera axis too. Same complaint,
different piece of geometry. Now everything but the scope assembly (barrel,
stock) hides for the duration of the scope.
[scripts/weapons/Railgun.gd](../scripts/weapons/Railgun.gd)

### Bug: ladder climbing snagged on tower geometry
The shaft is a tight fit, and a real structural corner sits right where it
meets the tower's outer walls - the walls run the tower's full width, and
only the floor slabs get a hole cut for the shaft, so a standing player's
capsule brushing that corner mid-climb caught on it constantly. Climbing is
already a locked, directed motion (gravity suspended, velocity driven
straight from input along the ladder's axis) rather than free physics, so
there's nothing for world collision to usefully do during a climb except
snag on geometry the Ladder trigger volume already keeps you inside of.
World collision (layer 1 only, not the whole mask) now drops for the
duration of a climb and restores on exit.
[scripts/player/Player.gd](../scripts/player/Player.gd)

### Tower observation deck: three rounds of revision
1. First pass: wider deck, roof on inset corner pillars instead of full
   walls, low parapet, bigger windows on the enclosed floors below.
2. Correction: parapet lowered further, roof height increased, deck widened
   more.
3. Final correction, mid-session: parapet **removed entirely** (nothing
   between a defender and the drop - the whole point is an unobstructed look
   straight down), open headroom doubled again (now 3.8m), deck widened to
   2.4x the tower's own width (was 1.6x, then increased once more).

`Building._add_slab_with_hole()` always cuts its hole at the slab's own
corner, which only matches the tower's own (narrower) floors - a new
`Tower._add_deck_slab()` cuts the hole at the ladder's actual shaft position
instead, so the shaft stays aligned through the wider deck the same way it
does through every floor below it. `footprint_radius()`/`structure_height()`
updated to measure the deck (now both the widest and the tallest part)
rather than the old roof cap.
[scripts/world/Tower.gd](../scripts/world/Tower.gd)

### New: Turret, a third building silhouette
`Bunker` was the only other pairing Tower ever had, so "increase the
variety" meant an actual new type rather than retuning existing ones: a
small firing platform on four stilt legs, reached by a stepped climb (this
system only ever authors axis-aligned boxes, so a smooth ramp isn't
representable - same constraint `_add_deck_slab`'s corner braces already
worked within). No interior, no ladder; short and exposed rather than tall
and towering (Tower) or squat and sealed (Bunker). `Arena._pick_building_scene()`
now coin-flips between Bunker and Turret for non-tower plots instead of
defaulting to Bunker alone. `WorldProbe.gd`'s foundation check exempts
Turret from its worst-case report (deliberately stilted, not a floating-
building regression) and its building-count log now reports turrets too.
[scripts/world/Turret.gd](../scripts/world/Turret.gd) (new),
[scenes/world/Turret.tscn](../scenes/world/Turret.tscn) (new),
[scripts/world/Arena.gd](../scripts/world/Arena.gd),
[tests/WorldProbe.gd](../tests/WorldProbe.gd)

### Fix: planet material - actually equilateral triangles this time, referencing concept art
Session 9's rework fixed the tiling seam but not the shape: it summed three
triangle waves along `(u, v, u+v)`, which are 90 and 45 degrees apart in
plain pixel space, not the 60 degrees an equilateral lattice needs - so the
"triangles" were really right-angled ones. Rebuilt properly this time: the
bump tile is a non-square rectangle (`height = width * sqrt(3)`, the actual
fundamental domain of a triangular/hex tiling) with three line families at
real 0/60/120-degree normals, which tiles seamlessly AND is genuinely
equilateral. Also made much bigger (16 apparent triangles around a planet,
was 156) per the second correction, and the base material moved toward the
concept art's cut-gem look - lower roughness, a touch of metallic - since
the reference art's facets catch hard, distinct specular glints rather than
reading as flat matte rock.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

---

## 2026-08-12 — Session 9: adaptive boundary, observation decks, ladder curvature, bump map rework

Not yet run through the headless probes in this environment (no Godot binary
available here) - review before trusting the "verified" bar the rest of this
log holds itself to.

### Improvement: the arena boundary is now a box around the nearest planet
Replaced the single fixed sphere (`ARENA_BOUNDARY_RADIUS`, centred on the
arena origin) with `GravityManager.is_within_boundary()`: a point counts as
in-bounds if it's within `BOUNDARY_MARGIN` (50m) of *any* body's own extents
(radius + however far its structures reach) on every axis - a box around
whichever planet is nearest, not a sphere around the whole arena. A player
only gets pushed back once they've drifted clear of every planet's box, which
closes off the dead space between worlds that let people camp there waiting
out the old, much larger sphere. `Player._apply_arena_bounds()` now checks
this instead of `global_position.length() <= ARENA_BOUNDARY_RADIUS`.
`ArenaBoundary.gd`'s shell is no longer a static sphere either - it's a
`BoxMesh` that resizes and repositions every frame to wrap whichever planet
the LOCAL viewer is nearest to (`GravityManager.find_local_viewer()`, the
same local-only pattern Session 8 used for the atmosphere glow fix - see
below). `ARENA_BOUNDARY_RADIUS` itself is unchanged and still used exactly
where it always was: ejecting a planet whose own orbit has drifted past the
whole arena's edge.
[scripts/autoload/GravityManager.gd](../scripts/autoload/GravityManager.gd),
[scripts/player/Player.gd](../scripts/player/Player.gd),
[scripts/world/ArenaBoundary.gd](../scripts/world/ArenaBoundary.gd),
[scenes/world/ArenaBoundary.tscn](../scenes/world/ArenaBoundary.tscn)

### Improvement: projectiles are destroyed at the boundary
A shot that missed everything used to just sail on until its own `lifetime`
timer ran out (up to 12s later) for no gameplay reason. `Projectile.gd`
(and `Slug.gd`, which overrides `_physics_process` and needed the same
check) now destroys itself once past `ARENA_BOUNDARY_RADIUS`.

Deliberately the WHOLE-arena sphere, not the new tighter per-planet box
above: a Planet Buster shell is *supposed* to cross open space between two
planets that can be hundreds of metres apart, well outside either one's 50m
box, for most of its flight - the box would have destroyed every long-range
shot on the way to its target. Since real shots are fired from one in-bounds
position toward another, and a sphere is convex, a shot between two legal
points never leaves the big sphere either, so this only ever actually
catches a shot that misses everything and flies off into true dead space.
Trimmed `WeaponProbe._test_buster_shell()`'s synthetic 400-unit offset to
150 - the old value could place its (deliberately off-course, for testing
steering) spawn point past 535 from the arena centre depending on direction,
which would now destroy the test shell on its own first frame.
[scripts/weapons/Projectile.gd](../scripts/weapons/Projectile.gd),
[scripts/weapons/Slug.gd](../scripts/weapons/Slug.gd),
[tests/WeaponProbe.gd](../tests/WeaponProbe.gd)

### New: tower observation decks
The top storey used to be just another same-width floor with windows on all
four sides - you could only ever shoot outward, never down, because the
tower's own walls were always directly underfoot. `Tower.gd` now caps each
tower with a deck 1.6x wider than the tower below, ringed by a waist-high
parapet (`PARAPET_HEIGHT`, shoot-over height) instead of full walls, with no
roof overhead - standing at the wider edge clears a firing lane straight down
past the tower's own base to the planet surface. Corner posts under the
deck's own corners keep the overhang from reading as floating.
`footprint_radius()`/`structure_height()` updated to measure the deck (the
wider, and now topmost, part) rather than the old roof cap.
`Building._add_slab_with_hole()` always cuts its ladder hole at the slab's
own corner, which is only correct for the tower's own (narrower) floors - a
new `_add_deck_slab()` cuts the hole at the ladder's actual shaft position
instead, so the shaft lines up through the wider deck the same way it does
through every floor below it.
[scripts/world/Tower.gd](../scripts/world/Tower.gd)

### Bug: ladder rails drifting from their own rungs
`Building._surface_transform()` scales the angle-per-metre of horizontal
offset down as height increases (`arc / height_radius`), which is what keeps
every storey the same physical width instead of fanning wider near the top -
see Session 6. Every OTHER tall element gets this correction per-segment
because it's rebuilt per floor, but a ladder's rails were each authored as
ONE tall box spanning the full climb in a single `_add_box()` call, computed
from one `_surface_transform()` at the box's own midpoint - so the entire
rail rendered dead straight at a single angle while the individually-placed
rungs (each getting their own correctly height-scaled angle) subtly bowed
away from it, worse the taller the tower. Rails are now built from the same
short segments as the rungs (`RUNG_SPACING`), so both go through the
identical per-height transform and stay aligned all the way up.
[scripts/world/Building.gd](../scripts/world/Building.gd)

### Fix: planet surface material - actually triangular, bigger, embossed
The bump-map pattern added last session summed three overlapping triangle
waves into a smooth height field - continuous by construction, so it had no
actual edges anywhere and read as a moire-ish wobble rather than triangles.
Rebuilt around distance-to-nearest-grid-line instead: for each pixel, the
distance to the nearest of three line families (running along u, v, and
u+v - still the same exactly-tileable triangular lattice construction) is
turned into a thin raised ridge via `smoothstep`, leaving each triangular
cell's interior flat - an embossed border rather than a smooth dome. Also
turned the repeat rate down hard (`BUMP_TILE_FREQ` x `BUMP_TILE_REPEAT` was
6 x 26 = 156 triangle-periods around a planet, now 3 x 9 = 27) so individual
triangles are actually large enough to read as triangles up close instead of
blurring into fine noise, and raised `normal_scale` from 0.35 to 0.75 since
an embossed edge needs to actually look raised.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

---

## 2026-08-12 — Session 8: bug/feature sweep #2 (gravity, asteroid batching, orbit ring spin, buster self-hit, bump map, atmosphere scope, sound gain)

Not yet run through the headless probes in this environment (no Godot binary
available here) - review before trusting the "verified" bar the rest of this
log holds itself to.

### Improvement: slugs pulled harder by gravity in open space
`space_gravity_multiplier` (extra gravity felt above `space_altitude`, so a
slug fired across open space arcs into whichever planet it passes rather than
flying a straight line past it) raised from 3.4 to 6.5 - at the old value a
slug still crossed most of a planet's influence radius on a nearly flat path.
[scripts/weapons/Slug.gd](../scripts/weapons/Slug.gd)

### Improvement: Asteroid draw calls
Same failure mode Session 6 found and fixed in buildings: every one of the
~110 rocks in the debris field baked its own SphereMesh (SurfaceTool +
deindex + generate_normals, at spawn) *and* got its own unique
StandardMaterial3D, so nothing the renderer draws could batch even though the
rocks are visually near-identical. Both are now built once (a shared
unit-radius mesh, sized per-rock via node scale; a small fixed pool of 5
materials for shade variety) and reused - draw calls no longer scale with
`rock_count`, and 110 redundant SurfaceTool bakes at DebrisField spawn become
1. Same treatment applied to the comet-trail puff mesh/material an incoming
rock ignites, since a busy match can have several lit at once.
[scripts/world/Asteroid.gd](../scripts/world/Asteroid.gd)

### Bug: orbit rings detaching from spinning parents
Root cause of the still-broken ring from Session 7's partial fix: a moon's
ring is parented to its parent planet (orbit_pivot) so its *position* tracks
the parent for free - but plain node parenting also inherits the parent's
*rotation*, and every planet spins on its own axis (`spin_speed`). The ring's
drawn orientation was only ever set on an infrequent radius/axis-change
refresh, so between refreshes it silently tumbled along with its parent's
spin, drifting away from the moon's actual orbital plane within seconds -
reads as the ring "detaching." Added `_orient_orbit_ring()`, which
counter-rotates the ring's local transform by the pivot's current spin every
single physics frame (cheap: one Basis inverse-multiply), so its *world*
orientation stays locked to `orbit_axis` regardless of what the pivot is
doing. `_refresh_orbit_ring()` now only resizes the torus and records the
target axis; orientation is entirely this function's job.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

### Bug: Planet Buster shell exploding on its own shooter
The shell leaves the barrel at a deliberately slow 7 m/s and (unlike other
projectiles) doesn't inherit the shooter's velocity. A player moving forward
at even a modest clip in open space - Space Board flight, boundary-launch
momentum, a recent rocket-jump - easily outpaces that and drifts back into
the shell within the first frame or two. `Projectile._on_hit()` has no owner
check, so that self-touch read as a stray hit: harmless splash, `queue_free()`
- the shell vanished having never reached the locked planet, with no
indication of what happened. `PlanetBusterProjectile.launch()` now calls
`add_collision_exception_with(shooter)` so the shell can't collide with its
own shooter for its whole flight, not just the first few frames the way other
weapons get away with via muzzle clearance alone.
[scripts/weapons/PlanetBusterProjectile.gd](../scripts/weapons/PlanetBusterProjectile.gd)

### New: triangular bump-map pattern on planet surfaces
Procedurally generated, not an asset - a 96x96 normal map baked once (three
periodic triangle-wave bands along u, v, and u+v summed into a tileable
triangular lattice height field, then differentiated into a normal via
central-difference gradients, the same technique any terrain normal map
uses) and shared across every planet's material, tiled ~26x across each
body's UV via `uv1_scale`. `normal_scale` kept low (0.35) so it reads as a
subtle engraved hull-plating texture on top of the existing low-poly facets,
not a rock texture fighting the faceted silhouette. Applied to both the
default per-planet material and to spawned moon-fragment materials (which
replace, and so need to reapply the pattern onto, whatever `_ready()` set up
before the fragment's own color was known).
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

### Bug: atmosphere glow flickering with no relation to the viewer
Session 7 scoped the atmosphere-hide check to "any player" (`get_frame_body()
== self` checked against every node in the `players` group). With bots
scattered across a dozen planets, a given world's glow flickered on and off
as whichever bots happened to be near it wandered in and out of range - from
the person actually watching, that reads as "shows up inconsistently
regardless of what planet you're near," since it had nothing to do with their
own position. Every `OrbitalBody` exists independently in each client's own
scene tree, so there's no correctness reason this needs to be shared state -
rescoped to the single local viewer (`Player.is_first_person_view()`), found
once per physics frame and cached statically so a dozen-plus planets share
one group scan instead of each repeating it.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

### Quality control pass: sound effect gain staging
`_pack()` already soft-clips each sound's own synthesised waveform before it
ever becomes an `AudioStreamWAV`, but that happens *before* the per-play
`volume_db` boost several call sites ask for - a soft-clipped signal already
sitting near 0.7-0.8 full scale, boosted several dB more at playback, clips
hard at the output stage regardless. Worst offender was `planet_shatter` at
+10 dB (~3.16x linear) on what should be the single loudest, most important
sound in the game - almost guaranteed to distort into noise instead of
landing as a clean boom. Trimmed the outliers (planet_shatter +10→+3,
explosion +6→+3, collapse +6→+2.5, buster_fire +4→+3, railgun_fire's
charge-scaled ceiling +2→+1, land's impact-scaled ceiling +2→0), keeping the
same relative loudness ordering (biggest moments still loudest) with actual
headroom underneath it. Also added an `AudioEffectLimiter` (ceiling -0.3 dB)
to the Master bus as a standing safety net - catches overlapping loud voices
in a firefight and any future sound whose gain wasn't hand-checked against
this same math, rather than relying on getting every volume_db exactly right
by feel.
[scripts/autoload/Sfx.gd](../scripts/autoload/Sfx.gd),
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd),
[scripts/weapons/Rocket.gd](../scripts/weapons/Rocket.gd),
[scripts/world/Building.gd](../scripts/world/Building.gd),
[scripts/weapons/PlanetBuster.gd](../scripts/weapons/PlanetBuster.gd),
[scripts/weapons/Railgun.gd](../scripts/weapons/Railgun.gd),
[scripts/player/Player.gd](../scripts/player/Player.gd)

---

## 2026-08-12 — Session 7: bug/feature sweep (scope, atmosphere, sound, kill credit, planet collision, orbit rings)

Not yet run through the headless probes in this environment (no Godot binary
available here) - review before trusting the "verified" bar the rest of this
log holds itself to.

### Bug: railgun scope blocked vision
`ScopeTube` was a fully-capped `CylinderMesh` (Godot's default) sitting
directly on the camera axis once scoped in - aiming down the sights meant
staring at the inside of a solid tube, not looking through it. Removed both
caps (`cap_top`/`cap_bottom = false`) so the barrel is actually hollow, and
gave `ScopeLens` a translucent glass material instead of the opaque default so
the objective lens doesn't itself paint over the view.
[scenes/weapons/Railgun.tscn](../scenes/weapons/Railgun.tscn)

### Improvement: atmosphere glow hides while you're on that planet
`OrbitalBody._add_atmosphere_shell()`'s rim glow reads fine from orbit but is
just a bright haze once you're standing on the surface looking through it.
`_update_atmosphere_visibility()` now hides a body's shell while any player's
movement frame is riding it (`Player.get_frame_body() == self` - reusing the
existing hysteresis-guarded planet-frame check rather than adding a second,
possibly-mismatched distance threshold). Added `Player.get_frame_body()` as
the public accessor for `_frame_body`.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd),
[scripts/player/Player.gd](../scripts/player/Player.gd)

### Restored: sound effects
Session 6 reverted a big, eager sound system (Sfx + Ambience + Announcer, 21
effects plus four 8-second ambience beds synthesised synchronously in
`_ready()`) that cost Arena load 2+ seconds. That elaborate version has no
git history - it only ever existed as uncommitted work - so it hasn't been
rebuilt here. What's restored is the earlier, much smaller `Sfx` autoload
(16 short one-shot weapon/world sounds, procedurally synthesised, no audio
assets) that a separate, prior commit (`aa0ae64`) had dropped, plus its 16
call sites across melee, movement, every weapon, health packs, jump pads,
building collapse, planet shatter, and the main menu.

Per the session-6 postmortem's own suggestion, synthesis is now **lazy**:
each sound is built the first time it's actually played and cached from then
on, instead of the whole library being built up front in `_ready()`. Startup
pays nothing; the (much smaller, ~17s of audio total across 16 short one-shot
sounds vs. the reverted system's ambience beds) cost lands on whatever the
first jump/shot/pickup happens to be.
[scripts/autoload/Sfx.gd](../scripts/autoload/Sfx.gd) (recreated),
registered in [project.godot](../project.godot).

### Bug: Planet Buster kills didn't credit the shooter
`OrbitalBody.shatter()` passed `self` (the planet) as the damage instigator,
so anyone killed by a planet's destruction got attributed to the environment
rather than to whoever fired the buster - no scoreboard credit for what's
supposed to be the biggest kill in the game. `shatter()` now takes an
`instigator` (and `weapon_name`) parameter; `PlanetBusterProjectile._on_hit()`
passes `owner_player`. Boundary-ejection shatters (no shooter) keep passing
null, same as before. Also skips damaging the instigator themselves, matching
the pattern already used for splash damage elsewhere.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd),
[scripts/weapons/PlanetBusterProjectile.gd](../scripts/weapons/PlanetBusterProjectile.gd)

### Improvement: colliding planets actually deform to clear each other
`structural_collision()`'s impact crater used to be a small fixed size
regardless of how hard the two bodies were actually overlapping, so a deep
graze still read as one planet visibly poking through the other while their
orbits took several seconds to drift apart. The crater depth and radius now
scale with the real penetration (`(radius + other.radius) - separation`), so
each body carves away enough of its own facing hemisphere that, combined with
the other body doing the same on its own call, the surfaces clear each other
on the frame of impact instead of over time.
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

### Bug: orbit rings not always updating
Two separate causes:
- The ring refresh in `_physics_process` only ever checked `orbit_radius`
  drift, not `orbit_axis`. A structural collision tilts the orbital plane
  (`orbit_axis`) without necessarily moving `orbit_radius` enough to cross
  the refresh threshold, so a tilted orbit could keep its ring drawn on the
  old, stale plane indefinitely. Now refreshes on either radius drift or an
  axis change.
- Moon fragments (`_spawn_moon_fragments()`) get `orbit_pivot`/`orbit_radius`
  assigned *after* `add_child()`, i.e. after `_ready()` already ran and found
  both unset - so `_add_orbit_ring()`'s guard clause bailed and the fragment
  never got a ring at all, ever. `orbit_pivot` and `orbit_radius` are now
  properties with setters that call `_ensure_orbit_ring()`, which creates the
  ring the moment both are actually valid (and keeps it live afterward, since
  every later `orbit_radius` write - `perturb_orbit()`,
  `structural_collision()` - now refreshes it immediately too, rather than
  waiting for the next physics tick's threshold check).
[scripts/world/OrbitalBody.gd](../scripts/world/OrbitalBody.gd)

---

## 2026-08-11 — Session 6: sound reverted, slime removed, performance pass

### Reverted: all sound
Removed on request — the `Sfx`, `Ambience` and `Announcer` autoloads, every
`play_3d`/`play_ui`/`announce` call site, the HUD announcement banner, and the
three autoload registrations. The game launches clean again (MainMenu 3.3 s,
Arena 5.0 s wall clock, no errors).

Worth recording for whenever sound is attempted again: **that system synthesised
every sample on the main thread during autoload `_ready()`**, before the first
frame could be drawn. Roughly 30M GDScript loop iterations of oscillator, filter
and reverb maths — 21 effects plus four 8-second ambience beds at 44.1 kHz.
Arena launch measured 7.1 s with it and 5.0 s without. Any future version needs
to synthesise off the startup path (a background thread, lazily on first play, or
baked to files at build time).

Also removed: **slug slime trails**.

### Performance
Measured with a real renderer (headless reports no draw calls), camera placed on
a planet surface looking along it, cost attributed by toggling systems off.

**Found and fixed:** buildings were **570 of 757 draw calls — 75% of the frame**.
Wrapping a building onto the sphere splits each authored piece into up to 25
sub-boxes, and each sub-box was getting its own `MeshInstance3D` *and* its own
`StandardMaterial3D`, so 13 buildings became ~1000 nodes with ~1000
un-shareable materials and nothing could batch.

Every building's geometry is now welded into a single mesh with one material via
`SurfaceTool`, with per-piece colour carried as vertex colour so it looks
identical. Faces are still emitted individually to keep the flat shading that
matches the faceted planets. Ladder rails and rungs fold into the same mesh.

| | before | after |
|---|---|---|
| draw calls (on a planet) | 757 | **217** |
| ...from buildings | 570 | **33** |
| scene nodes | 3780 | **2828** |

Asteroids also stopped calling `GravityManager.get_nearest_body()` twice per
frame each — the result is cached and refreshed a few times a second, since a
rock barely moves relative to a planet between frames.

**Not reproduced: any actual slowdown.** Sustained 20 s sample with all 31 bots
fighting, dying and respawning:

```
mean 8.33ms (120 fps)   p95 9.09ms   worst 16.24ms   spikes >20ms: 0 / 2400 frames
```

That is the 120 Hz display cap with headroom to spare, and stripping the scene to
nothing still measures ~8.4 ms — so scene content is not the limiter. Load is
171 ms total (127 ms building the arena). A crater costs 1.9 ms to deform plus
1.2 ms to rebuild the collider, coalesced on a 0.6 s timer.

If the game feels slow in play, it is not the steady-state frame on this machine
— the likely candidates are running from inside the editor (much slower than a
standalone run) or something specific to a viewpoint, and either needs a report
of what is actually being seen.

### Test harness
`tests/PerfProbe.tscn` (draw calls, frame spikes, cost attribution by mode) and
`tests/LoadProbe.tscn` (scene build breakdown). **Both must run with a real
renderer — no `--headless`**:

```
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/PerfProbe.tscn -- sustained
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/LoadProbe.tscn
```

Modes: `all`, `sustained`, `no-asteroids`, `no-buildings`, `no-lights`,
`no-packs`, `sphere-colliders`, `no-players`, `bare`.

---

## 2026-08-11 — Session 5: combat feel, gore, physical asteroids, adaptive audio

### Bugs
- **Stuck on the arena boundary.** The bounds code steered velocity and returned
  early, while the movement code ALSO returned early because a boundary target
  was set — so nothing ever called `move_and_slide()` and a player who touched
  the edge froze there permanently. Crossing the edge now hands straight to the
  Spawner, which flings them at a randomly chosen planet on the same trailed
  launch a respawn uses, with no aim window. Measured: **moving 0.02 s after
  contact**, landing on a planet surface.
- **Tower walls split open as they rose.** The wrap onto the sphere divided the
  arc by the *surface* radius, so every storey subtended the same angle and got
  physically wider with height. Dividing by the radius *at that height* keeps
  each storey the same width. Measured top/base width ratio **1.006, against
  1.756 under the old mapping**.

### Players
- **Head sphere** on the character (collider + mesh), and **headshots do 300%**.
  Verified: 10 → 30 damage. The test is by hit height along the player's own up
  axis, not by which collider was struck — the body is one `CharacterBody3D` with
  two shapes, and Godot's hit results don't report which shape was hit.
- **Comic-book death effects**: a ragged action burst with a random word
  ("POW!", "SPLAT!"…), a speech bubble carrying the victim's name and a skull.
  The skull is *drawn into an ImageTexture*, not typed as an emoji — the bundled
  font has no glyph for one and it would render as a hollow box.
- **Gore**: blood spray, 6–10 giblets on their own ballistic arcs, and ground
  splatter parented to the planet so it rides the surface and outlives the burst.
- **Slug slime trails** — patches dropped every 1.8 m of crawling, parented to the
  planet, fading out over 30 s. Measured 28 patches from a 5 s crawl.

### Asteroids
No longer one decorative MultiMesh. They are real bodies: **110 spawned (down
from 900)**, falling under `GravityManager` (measured **6.6 m/s gained in one
second** inside a well), colliding with planets and structures, lighting up as
**comets when impact is under 2 s away**, and on impact cratering the surface and
shoving the orbit. Verified end to end: comet lit on approach, impact at 1.42 s,
mesh deformed, orbit moved.

The field settles to ~66 rocks in the first few seconds as those that spawned
inside gravity wells rain in — an opening meteor shower. Raise `orbit_clearance`
in `DebrisField` if you'd rather they all start in true vacuum.

### Audio — quality pass
Rebuilt on composable primitives instead of three fixed generators:
- **44.1 kHz**, up from 22.05 kHz. Everything above 11 kHz was previously gone,
  which is why the railgun crack and metallic pings sounded dull.
- `_osc()` with detuned unison stacks and per-sample pitch envelopes
- `_noise()` through a state-variable filter, so a hiss can become a rumble, a
  whoosh or a metallic ring
- `_env()` proper ADSR per *layer*, with a curve on the release
- `_body()` short feedback comb — this is what gives an impact physical *size*,
  the difference between a click and a boom in a room
- `_reverb()` Schroeder tail (allpass into three prime-length combs)
- Output is normalised then soft-clipped, so loud sounds no longer distort and
  quiet ones are audible

**21 sounds.** Sound design is now layered per weapon: the rocket has ignition
crack + throaty roar + tail; the explosion has crack + body-resonant boom +
debris; the railgun has a resonant charge whine and an electrical crack with a
metallic ring after it.

### Audio — adaptive ambience
New `Ambience` autoload with four seamless synthesised loops cross-faded by
what's actually happening:
- **space** (cold sparse drone) vs **surface** (warmer, wind over rock), blended
  by altitude above the nearest planet
- **tension** (held minor third) and **combat** (driving pulse), driven by
  **intensity = hostile projectiles within 45 m**, full at 5. That's a far better
  proxy for how hot a fight is than kill counts: it rises the instant you're
  being shot at and falls the moment you break away.

Fades run in level-space over 2.5 s, not dB-space — a linear dB ramp sounds like
it jumps at the end.

### Announcements
New `Announcer` autoload with all six requested triggers wired and verified:
headshot, killing spree (**fires on kill #3**), bitchslap, planet slayer, match
start, and grappling another player. Each gets a big UT-style on-screen callout
and its own synthesised stinger, with priority so a big line isn't trampled.

**The spoken voice-over needs real audio files.** Everything else here is
synthesised from oscillators and noise, which works for impacts and weapons but
cannot produce intelligible speech. Drop `headshot.ogg`, `spree.ogg`,
`bitchslap.ogg`, `planet_slayer.ogg`, `match_start.ogg`, `get_over_here.ogg` into
`res://audio/vo/` and they play automatically — no further wiring. Until then the
triggers, callouts and stingers all work on their own.

---

## 2026-08-11 — Session 4: physicality and presentation

### World look
- **Brightness landed between the two previous passes.** Nebula intensity
  0.85 → 1.35 and recoloured to the concept art's violet/blue/magenta, space
  colour lifted off pure black to a deep indigo, ambient 0.3 → 0.5, exposure
  1.05 → 1.15, contrast 1.35 → 1.2, saturation 1.18 → 1.32.
- **Faceted low-poly planets**, matching the concept art. The surface is rebuilt
  as a deindexed, flat-shaded ArrayMesh — with no shared vertices every triangle
  gets its own normal instead of a smoothed average. Tessellation (36×18) is a
  deliberate balance: coarse enough to read as facets, fine enough that a crater
  still has vertices to displace.
- **Atmospheric rim glow** per planet: an emissive shell just above the surface
  with front faces culled, so what shows through the limb is the shell's far side.
- **Orbit rings** tracing every body's path, parented to the *pivot* so a moon's
  ring travels with its parent planet. Refreshed when an orbit is perturbed
  enough to matter.
- **Asteroid debris field** — 900 rocks in one MultiMesh draw call, flattened
  toward the orbital plane and nudged clear of every planet's track.
- **Flags on tower roofs**, the silhouette detail that makes a skyline read as
  occupied from orbit.

### Craters are now real terrain
`apply_crater()` rebuilds the collider as a `ConcavePolygonShape3D` from the
deformed vertices, so you can walk down into one. Measured: **surface under the
impact dropped 1.05 m** in the collision world, not just visually. Rebuilds are
coalesced on a 0.6 s timer — a respawn wave cratering one planet several times
pays for one rebuild, not five.

### Buildings
- **Wrapped onto the sphere.** A building is authored flat, then every piece is
  remapped onto the surface and tilted to the local normal
  (`Building._surface_transform`); pieces wide enough to sag past 0.25 m are split
  into segments first. **548 of 848 pieces are tilted, up to 33.4°** — the
  untilted remainder are the ones on the centre line, which correctly need none.
  Collision follows the same mapping, so the curve is physical too.
  Verified no building floats: deepest geometry sits **0.95 m below** the surface.
- **Interior lights** — one warm lamp per tower floor, two per bunker, each with a
  small emissive panel so windows glow from outside. 24 across the arena.
- **Towers break on impact.** A planet-on-planet structural collision now shears
  off the buildings caught in it, with a debris burst and a rubble footprint left
  as cover. Only the ones facing the contact point: measured **2 demolished, 1
  still standing** on the far side. The body's `structure_reach` is recomputed
  afterwards so a flattened planet stops registering contacts it can no longer
  physically make.

### Audio
New `Sfx` autoload: **16 sounds, synthesised at startup** rather than loaded, so
the project still ships no audio assets. Each is built from noise bursts, pitch
sweeps and FM tones packed into 16-bit PCM, with soft clipping and short fades
(a buffer starting mid-waveform clicks on every play).

Variation is applied at *playback*, not baked as multiple takes — `play_3d()`
jitters pitch and volume per shot, so full-auto fire never sounds like one click
stamped out repeatedly. Genuinely dynamic cases: the railgun's charge whine rises
in pitch with charge and its shot deepens and loudens with it; the planet-shatter
boom pitches down with planet radius; the landing thump scales with impact speed.
32 pooled `AudioStreamPlayer3D` voices give distance attenuation and panning, and
recycle round-robin so a firefight degrades instead of allocating without bound.

### Controls
- **The Bitchslap moved from `F` to `V`.**

### Note
A shutdown warning about ~20 leaked ObjectDB instances is 23 orphan `StringName`
entries for the audio bus name `Master` — an engine-side artifact of initialising
the audio server, not leaked nodes.

---

## 2026-08-11 — Session 3: world detail pass

### Spawning
- **Smoke trail no longer blocks the flight view.** The trail emitter now trails
  `TRAIL_TRAIL_DISTANCE` (14 m) behind the player and is repositioned every frame
  along the current flight vector. Emitting at the player's own origin filled the
  camera and made the 130 m/s approach effectively blind.
- **Thicker, hotter smoke.** Emission moved from a point to a 3.2 m sphere, amount
  220 → 420, and each puff now ages along a red → orange → grey → transparent
  gradient with a growth curve, instead of being flat red.

### Buildings
- **No more floating buildings.** A flat base on a curved planet leaves its outer
  corners hanging by the sagitta. Every building now generates a two-tier plinth
  (`Building._add_foundation`) that reaches exactly that far below the base, so it
  meets the surface at the corners and is buried elsewhere. Measured remaining
  corner gap across all buildings: **0.00 m**.
- **Cross-planet structural collisions now perturb both orbits.**
  `OrbitalBody.structural_collision()` flings the outer body further out and slows
  it, drags the inner one in and speeds it up, scaled by relative mass (radius³),
  tilts both orbital planes, and craters both at the contact point.
  `GravityManager._physics_process` runs the pair scan.
- **Structure height solver** (`Arena._solve_structure_heights`). Towers target
  their planet's radius, but a radius-tall tower doubles a planet's footprint.
  Transient tower-on-tower contact is fine — that *is* the collision feature — but
  a *permanently* overlapping pair would re-trigger forever and walk both orbits
  apart. So the solver constrains only fixed-separation pairs (the phase-locked
  central binary, and a moon against its own parent) and leaves everything else
  free. Collisions additionally require a real closing rate, so float jitter at a
  constant separation can't retrigger them.
- Moon orbits raised (Cinder 28 → 32, Verdant 60 → 66, Umbra 40 → 48) to the most
  their neighbours allow, which frees their parents to carry real towers.

### Planets
- **Random tumble axis per planet** — previously all spin was polar.
- **Health packs** (`scripts/world/HealthPack.gd`), `1 + radius/9` per body capped
  at 6, so a 44 m world gets 5 and a 5 m pebble gets 1. Only consumed if they
  actually heal, so a full-health player leaves them for someone who needs them.
  28 packs across the arena.

### Visuals
- **Darker, less pink sky.** Nebula recoloured from magenta/hot-red to deep
  indigo/blue/rust, intensity 2.0 → 0.85, space colour to near-black. Post
  saturation 1.45 → 1.18, which was re-pinking the result.
- **Bigger, brighter stars.** New `star_size` uniform (lower = bigger), brightness
  4.6 → 8.0, and each star gained a soft halo so the bright ones show glare
  instead of being hard specks.

### Fixes
- **Third-person weapon no longer visible in first person.** `WeaponModel` hides
  itself when its player is the local view, leaving only the first-person
  viewmodel.
- `Area3D.monitoring` is now set deferred in `HealthPack` and `PlanetBusterPickup`.
  Writing it directly from inside a `body_entered` handler is refused by Godot —
  this was a live error in `HealthPack` and a latent one in the existing pickup.

### Known trade-off
Radius-tall towers only fit where nothing permanently orbits overhead. In the
current (tightened) arena that means **Halcyon gets its full 36 m tower**, while
Alpha (21/28), Beta (10/13), Umbra (15/27), Verdant (12/44) and Cinder (9/18) are
trimmed by their moon or their binary partner. Removing a moon, or spreading the
orbits back out, would restore full height on that planet.

---

## 2026-08-11 — Session 2: arena, bots, weapons

### Arena
- Play area shrunk 30% then grouped a further 20% closer:
  `ARENA_BOUNDARY_RADIUS` 950 → 665 → **535**, with orbits and the spawn shell
  scaled to match.
- **Wider planet size range**: 5 m pebbles up to a 44 m world (was 9–33 m). Added
  Cinder and Halcyon; renamed/retuned the rest.
- Documented the spacing rule: gap between orbit radii must exceed the sum of the
  two radii, a moon adds `orbit_radius + radius` to its parent's reach, and
  `orbit_radius` must stay above `radius * 1.5` because `perturb_orbit()` floors
  it there on every spawn landing.

### Buildings
- **Towers rebuilt as genuinely navigable.** They previously had a single
  tower-sized collision box, which sealed the interior solid. Every wall panel now
  carries its own collision (`Building._add_box`), so interiors are enterable:
  ground-floor doorway, per-floor firing windows, a ladder up the corner shaft,
  and a top floor with windows on all four sides.
- **Ladder climbing** (`Ladder.gd` + `Player._apply_ladder_movement`).
- **Bunkers** as a second building type for close-quarters cover.
- **Fixed: towers ignored their configured height.** `Arena` set `tower_height`
  *after* `add_child()`, which runs `_ready()` synchronously, so every tower came
  out a fixed 30 m regardless of planet.

### Players and bots
- **Bots run the same spawn flow as players** — boundary shell, planet choice,
  launch, landing crater — instead of being teleported to a spawn point. They pick
  in 0.5–2.5 s so 31 of them don't idle out the full human aim window.
- **Landing craters** deform the planet mesh (`OrbitalBody.apply_crater`). The
  SphereMesh primitive is baked to an ArrayMesh on first impact, then edited in
  place with a cosine bowl and raised rim. Visual only — collision stays a perfect
  sphere.
- **Bots use the whole arsenal.** Weapon choice by range, including Space Board to
  cross open space and the grappling hook to close distance. Fire is now *pulsed*,
  which also fixes bots never firing the railgun at all — it fires on release, and
  a held trigger just charged forever.
- **Third-person weapon models** so you can see what everyone is carrying;
  `current_weapon_index` is replicated since `handle_input()` only runs on the
  authority.
- **Smoother gravity-well entry.** Both the target "up" and the body's re-levelling
  are now exponentially eased rather than snapped/constant-rate.

### Weapons
- **Railgun scope**: viewmodel slides until the lens sits on the camera axis
  (measured offset: 0.000, 0.000), FOV 88 → 18, and a full-screen shader blurs and
  darkens everything outside the lens.
- **Slug launcher**: 3.4× gravity above 15 m altitude so shots fired from space
  curve into wells; aggro range 45 → 140 m, slither 7 → 11 m/s.
- **Planet buster**: massive purple smoke trail as it travels.
- Main menu **"Start with all weapons (testing)"** checkbox.

### Removed
- `scripts/player/_Player.gd` — a tracked but unreferenced 448-line stale copy that
  also declared `class_name Player`, shadowing the real 756-line one. `Bot extends
  Player` was resolving to the *old* class and losing methods.
  Restore with `git checkout HEAD~ -- scripts/player/_Player.gd` if ever needed.

---

## 2026-08-11 — Session 1: movement bugs and weapon behaviour

### The three surface bugs had one root cause
Planets orbit at up to ~12 m/s — faster than the 9 m/s run speed — and spin, but a
`StaticBody3D` that is teleported each frame gives `CharacterBody3D` no platform
velocity. The ground slid away, the leading hemisphere shoved into the player like
a moving wall, and repeated depenetration read as bouncing.

**Fix**: within `planet_frame_height` of a surface, that planet becomes the
player's reference frame — the transform is carried by the planet's rigid motion
and `velocity` is stored relative to it (`Player._update_planet_frame`).
Supporting fixes: "up" now comes from the planet's radial direction rather than
summed gravity (a tilted up made the sphere classify as a *wall* past
`floor_max_angle`), `wish_dir` is flattened into the tangent plane, and outward
velocity is discarded while grounded.

Measured on an identical seeded world:

| Metric (10 s run) | Before | After |
|---|---|---|
| Bounce take-offs | 33 | **0** |
| Airborne frames while running | 568/600 | **0/600** |
| Drift standing still (5 s) | 17.6 m | **0.08 m** |
| Ground covered per heading (8 × 3 s) | 3.9–21.8 m | **26.7 m, all eight identical** |

### Weapons
- **Grappling hook** shoots a hook head that pays out a visible cable at 3.7
  m/frame, bites, reels you in, and retracts on release. The cable lives on the
  Player (not the viewmodel, which is hidden for non-local views) and is
  replicated, so everyone sees everyone's grapples.
- **Space Board** gives full 6-axis freedom while selected, rather than being
  airborne-only forward thrust.
- **Planet buster** cannot fire without a lock (and isn't consumed if you try);
  the shell leaves the barrel at 7 m/s and accelerates linearly at 24 m/s²,
  recomputing its heading exactly once a second.

---

## Test harness

Probe scenes drive the real code paths headless and print measurements
rather than pass/fail, so regressions show up as changed numbers.

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/MovementProbe.tscn   # bounce / slide / invisible wall
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/WeaponProbe.tscn     # hook, board, buster, scope, slugs, menu option, scope highlight, auto-slap, slug vs. building
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/WorldProbe.tscn      # layout, buildings, ladders, spawn, craters, health, spin, impacts, tower height range, planet shader, boundary vs. spawn, ladder death
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/CombatProbe.tscn     # boundary, tower walls, headshots, death/gore, slime, asteroids, audio, announcements
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/AIProbe.tscn          # bot AI raycast cost, GravityManager call cost, uncoalesced deform, skull texture, scoreboard sort (Session 12)
```

`PerfProbe.tscn` and `LoadProbe.tscn` (see Session 6/12 above) need a real
renderer, not `--headless`.

Results are also written to `/tmp/rjbs_*.log`, flushed per line — a run that has
to be killed for hanging would otherwise lose everything to stdout buffering.

Note: after adding or renaming any `class_name`, run
`Godot --headless --path . --import` once to refresh the global class cache, or
scripts will fail to resolve their base classes.
