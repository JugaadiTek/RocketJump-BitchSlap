# Changelog

Running log of changes made to RocketJump BitchSlap. Newest first.

All entries verified against Godot 4.7.1 running headless, via the probe scenes
in [`tests/`](../tests) — see **Test harness** at the bottom.

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

Three probe scenes drive the real code paths headless and print measurements
rather than pass/fail, so regressions show up as changed numbers.

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/MovementProbe.tscn   # bounce / slide / invisible wall
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/WeaponProbe.tscn     # hook, board, buster, scope, slugs, menu option
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/WorldProbe.tscn      # layout, buildings, ladders, spawn, craters, health, spin, impacts
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/CombatProbe.tscn     # boundary, tower walls, headshots, death/gore, slime, asteroids, audio, announcements
```

Results are also written to `/tmp/rjbs_*.log`, flushed per line — a run that has
to be killed for hanging would otherwise lose everything to stdout buffering.

Note: after adding or renaming any `class_name`, run
`Godot --headless --path . --import` once to refresh the global class cache, or
scripts will fail to resolve their base classes.
