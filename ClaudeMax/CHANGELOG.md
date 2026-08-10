# Changelog

Running log of changes made to RocketJump BitchSlap. Newest first.

All entries verified against Godot 4.7.1 running headless, via the probe scenes
in [`tests/`](../tests) — see **Test harness** at the bottom.

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
```

Results are also written to `/tmp/rjbs_*.log`, flushed per line — a run that has
to be killed for hanging would otherwise lose everything to stdout buffering.

Note: after adding or renaming any `class_name`, run
`Godot --headless --path . --import` once to refresh the global class cache, or
scripts will fail to resolve their base classes.
