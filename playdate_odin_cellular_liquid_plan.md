# Playdate Odin Grid-Flux Liquid Solver — Stepped Implementation Plan

**Reader:** An engineer replacing the prototype fluid simulation.

**Post-read action:** Implement the solver in order, verifying exact mass conservation and solid containment at every stage before adding presentation or gameplay.

**Current state:** Steps 0–1 and the solid geometry helpers are implemented and tested. The originally implemented transfer rule (cellular-automata "push up to a cap into the gravity neighbor") is **replaced** by the flux model in §4. `next_mass`, `liquid_stage`/`liquid_commit`, `liquid_try_transfer`, `Gravity_Step`/`liquid_gravity_step`, and `MAX_FORWARD_TRANSFER` are deleted. The framebuffer module, solid rasterization, seeding, and steps 7–10 carry over unchanged (seeding gains the §2 type changes).

## 1. Decision and non-goals

A conservative grid/flux ("virtual pipes") liquid solver on an 80 × 48 grid. Each cell stores an amount of liquid; adjacent cells are connected by persistent per-edge flows. Gravity from the accelerometer and local pressure differences drive those flows. Fluid appearance comes directly from the mass field.

The goals are stable volume, reliable settling, accelerometer-driven flow with momentum (sloshing, overshoot, surface waves), static obstacle containment, and a sustained 30 FPS on device. Physical splashes, vortices, per-particle motion, and exact Navier–Stokes behavior are explicitly out of scope.

The solver deliberately simulates "convincing Playdate liquid" rather than water physics: the constants in §6 are artistic tuning parameters, and the mass field plus edge flows are the entire authoritative state.

## 2. Fixed model

Use grid coordinates; one cell maps to 5 × 5 display pixels.

| Item | Value |
|---|---:|
| Simulation grid | 80 × 48 |
| Cell capacity (CAP) | 65535 mass units (1.0) |
| Compression ceiling | 72088 (1.10 × CAP) |
| Total liquid | Fixed after level load/reset |
| Simulation tick | 1/30 second |
| Update style | Two-pass, in-place mass |
| Solid capacity | 0 |
| Gravity | Filtered accelerometer, Q15 i16 (32767 = 1 g) |

Mass is stored in `i32` so the transient compression range (up to 1.10 × CAP = 72088) fits; `i16` cannot hold it. Per-edge flow is `i16`, clamped to `FLOW_CAP`.

Only interior edges carry flow; the border ring is solid and every edge touching it is dead.

```
H_EDGES :: (GRID_W - 1) * GRID_H   // 79 x 48 = 3792, edge (x,y) -> (x+1,y)
V_EDGES :: GRID_W * (GRID_H - 1)   // 80 x 47 = 3760, edge (x,y) -> (x,y+1)
```

Direction convention: positive `flow_x` is left-to-right, positive `flow_y` is top-to-bottom. Edge indices: `flow_x[y * (GRID_W - 1) + x]`, `flow_y[y * GRID_W + x]`.

Fixed-capacity, allocation-free storage:

```odin
Cell_Kind :: enum u8 { Air, Solid }

Liquid_State :: struct {
    mass:       [CELL_COUNT]i32,
    flow_x:     [H_EDGES]i16,
    flow_y:     [V_EDGES]i16,
    kind:       [CELL_COUNT]Cell_Kind,
    total_mass: i32,
}
```

`mass` is authoritative. Rendering, target queries, debug views, and effects derive from `mass` and the flows and must never modify them. There is no second mass buffer: pass 1 reads `mass` only, pass 2 applies paired debit/credit in place.

## 3. Invariants

Assert these in debug builds after every simulation tick:

1. Every mass value is within [0, CAP_CEILING].
2. Every solid cell contains zero mass.
3. `sum(mass)` equals the level's initial `total_mass` exactly.
4. No transfer targets an out-of-bounds or solid cell.
5. A settled state (all flows zero, no mass change) under zero gravity changes no cell and keeps all flows zero.

Do not compensate a failed invariant by adding or deleting mass. Stop, log the edge and its two cells, and fix the flow transaction.

## 4. Two-pass update rule

Each tick has two passes.

**Pass 1 — flow integration (order-independent).** For every edge whose two endpoints are air cells, with direction `dir` (Q15; axis 32767, diagonal 23170) from A to B:

```
pressure(m) = m + K_STIFF * max(0, m - CAP)

drive  = (pressure(A) - pressure(B)) * K_PRESSURE
       + dot(gravity, dir) * K_GRAVITY        // gravity in Q15

flow   = (flow + drive) * DRAG
flow   = clamp(flow, -FLOW_CAP, FLOW_CAP)
```

Edges with a solid endpoint carry no flow; zero them.

The pressure term levels the liquid and propagates pressure through completely full regions via the small allowed compression (2–10% is invisible). The gravity term drives flow along the tilt. Because flows are persistent and only damped, a gravity reversal leaves the old flow in place for several ticks: it decays, reverses, and produces a wave. That is the sloshing.

**Pass 2 — clamped application (fixed edge order).** For each edge in a fixed canonical order (row-major, horizontal edges then vertical edges):

```
if flow > 0:
    moved = min(flow, mass[A], CAP_CEILING - mass[B])
    mass[A] -= moved;  mass[B] += moved
if flow < 0:
    moved = min(-flow, mass[B], CAP_CEILING - mass[A])
    mass[B] -= moved;  mass[A] += moved
```

Every application is a paired debit/credit, so `sum(mass)` is exact by construction. The running-mass clamp means a cell can never send more water than it actually contains; the fixed order makes the result deterministic (order affects only the transient distribution of clamping, never conservation).

Transfers always obey:

```
0 <= moved <= source mass
0 <= destination mass after <= CAP_CEILING
sum(debits) == sum(credits)
```

## 5. Flow behavior

Implement flow incrementally; do not add all rules at once.

### Step 0 — Baseline (done)

- Cellular-liquid modules, screen/grid constants, fixed arrays, solid rasterization, full reset.
- Render solid borders and an empty field through the existing direct framebuffer module.

**Verify:** Build for Simulator and device. Assert the array sizes, border solids, and zero total mass.

### Step 1 — Mass field and debug patterns (done, type changes)

- Seed a rectangular reservoir with a configured total mass, filling cells to capacity before partially filling the final cell.
- Add all-empty, all-full, single-cell, checkerboard, and known-total debug seeds.
- Add a raw 5 × 5 block mass renderer; no dither or flow yet.
- Level totals rescale to the new mass units (old 255-unit scale × 256).

**Verify:** Reset is deterministic. Every pattern's measured sum equals its configured total. A CAP-mass cell renders fully covered and zero renders empty.

### Step 2 — Static solids and edge application (partially done)

- Solid rectangle helpers and the five test geometries (borders, shelf, channel, inner corner, target chamber) exist; keep them.
- Implement the pass-2 clamped edge application as one helper that owns edge validity, solid blocking, and the debit/credit, per §4.
- Delete `liquid_try_transfer`, `liquid_stage`, `liquid_commit`, and `next_mass`.

**Verify:** Attempted transfers into solids/outside move zero mass. Mass remains exact through thousands of no-op and forced transactions on every geometry.

### Step 3 — Flux core, gravity-only drive

- Implement pass 1 with the gravity term only (no pressure term yet) plus pass 2.
- A column of liquid falls as a body bounded by `FLOW_CAP` per tick instead of teleporting; the floor plug compresses toward `CAP_CEILING` and blocks further inflow.

**Verify:** A reservoir falls and settles at the bottom with exactly the initial mass. Fall speed stays bounded by `FLOW_CAP`. Holding zero gravity after settling produces no changes.

### Step 4 — Q15 directional gravity

- Convert filtered accelerometer input to a Q15 i16 grid-space gravity vector once per tick (f32 stays at the sensor boundary only).
- Delete the quantized `Gravity_Step`/`liquid_gravity_step`; arbitrary tilt angles work through `dot(gravity, dir)`.
- Preserve deterministic gravity overrides for test scenes.

**Verify:** Constant left, right, up, down, 45-degree, and off-axis inputs move mass in the intended direction without loss through any wall.

### Step 5 — Pressure and compression

- Add the pressure term from §4 pass 1.
- Sideways equalization is now the pressure term on horizontal edges; the old "alternate left/right tie-breaking" rule is not needed.

**Verify:** An uneven reservoir settles into a level surface (within one cell) and remains unchanged at rest. A full column under sustained gravity stays at or below `CAP_CEILING`, and flow into its top decays to zero (pressure opposes inflow). A settled column shows the small mass gradient that balances gravity.

### Step 6 — Tunable viscosity and cohesion

- Add `FLOW_DEADBAND`: flows with |flow| below it are zeroed, so a settled state reaches exactly zero flow.
- Add a viscosity scalar realized through `DRAG` presets (water, syrup, low-cohesion).
- Keep all parameters in one configuration block with deterministic defaults.

**Verify:** Compare the presets. Every preset has identical total mass and solid containment, and every preset reaches an exactly-static rest state.

### Step 7 — Direct 1-bit density rendering

- Treat `mass[cell] / CAP` as coverage directly; there is no reconstruction stage.
- Reuse the validated framebuffer owner, screen-anchored Bayer dither, and solid rendering conventions.
- Render raw blocks and dithered mass as debug-selectable views.

**Verify:** Coverage increases monotonically from mass 0 to CAP, static images do not shimmer, and rendering never writes padding bytes except during the framebuffer module's deliberate full clear.

### Step 8 — Integer upscaling and surface treatment

- Bilinearly upscale the 80 × 48 mass grid with integer intermediates.
- Clamp sampling at boundaries and prevent interpolation across solids.
- Optionally add a one-cell edge darkening or ordered-dither contrast adjustment; it must be presentation-only.

**Verify:** No seams occur at the last row/column or along shelf edges. The same mass state yields the same frame every time.

### Step 9 — Fill-target puzzle

- Define a target rectangle and measure its contained mass directly.
- Success is a mass fraction held above a threshold for a short duration.
- Reset restores both mass and target state exactly.
- Add a minimal direct-framebuffer target outline and completion indicator.

**Verify:** Empty, partial, full, and reset target measurements are exact. The player can reliably fill the chamber with moderate tilt.

### Step 10 — Hardware tuning gate

- Measure simulation, framebuffer, input, and whole-frame rolling averages on the actual Playdate.
- Tune only: `K_PRESSURE`, `K_GRAVITY`, `DRAG`, `FLOW_CAP`, `FLOW_DEADBAND`, `K_STIFF`, accelerometer filter, and dither mode.
- Keep the first configuration that is stable for ten minutes and stays comfortably below 33.3 ms/frame.

**Verify:** Run all gravity directions, repeated reversals, shelf/channel scenes, and target play for ten minutes each. Log no mass mismatch, solid mass, or frame-budget failure.

## 6. Recommended starting parameters

```text
CAP:                65535      (i32 storage; 1.0 in Q16)
CAP_CEILING:        72088      (1.10 x CAP; absolute maximum mass)
K_STIFF:            4          (compression pressure per unit excess mass)
K_PRESSURE:         1/64       (drive per unit pressure difference)
K_GRAVITY:          1/16       (drive per unit Q15 gravity projection)
DRAG:               250/256    (flow retention per tick)
FLOW_CAP:           24000      (max |flow| per edge per tick; ~0.37 cells/tick)
FLOW_DEADBAND:      4          (zero flows below this magnitude; step 6)
gravity:            Q15 i16, 32767 = 1 g
accelerometer:      low-pass alpha 0.15, dead zone 0.03, converted to Q15 once per tick
```

These are tuning defaults, not physical constants. Change one parameter at a time and retain the mass-conservation tests for every change.

## 7. Diagnostics

Log at a low cadence:

- current and expected total mass;
- max |flow| and count of edges pinned at `FLOW_CAP`;
- count of compressed cells (mass > CAP);
- flow energy `sum(flow^2)`;
- mass found in solid cells;
- nonzero-cell count;
- target mass/fraction;
- simulation and render timing.

Add debug views for raw mass, dithered mass, solid geometry, flow magnitude/direction, and target occupancy. A mass mismatch is a hard debug failure, not a visual diagnostic.

## 8. Exit criteria

The replacement is ready for game work when it meets all of the following:

- A closed scene conserves mass exactly for ten minutes.
- Liquid settles into a stable arrangement at rest with all flows exactly zero.
- No mass enters borders, shelves, or target walls.
- Tilt produces clear directional flow with momentum (reversal overshoots, then damps) and no persistent wall adhesion.
- The target puzzle is winnable and reset is deterministic.
- Device frame time remains below the 30 FPS budget with gameplay headroom.
