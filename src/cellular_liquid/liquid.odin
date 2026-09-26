package cellular_liquid

// =================================================================
// Model
// =================================================================

Cell_Kind :: enum u8 { Air, Solid }

// Fixed-capacity, allocation-free simulation state.
//
// `mass` is authoritative: every cell holds an amount of liquid in
// [0, CAP_CEILING]. Adjacent cells are connected by persistent
// per-edge flows (`flow_x`, `flow_y`); positive flow is in the +x /
// +y direction. Rendering, target queries, debug views, and effects
// derive from mass and flows and must never modify them.
//
// There is no second mass buffer: pass 1 reads mass only, pass 2
// applies paired debit/credit in place, so sum(mass) is exact by
// construction.
Liquid_State :: struct {
	mass:       [CELL_COUNT]i32,
	flow_x:     [H_EDGES]i16,
	flow_y:     [V_EDGES]i16,
	kind:       [CELL_COUNT]Cell_Kind,
	total_mass: i32,
}

// Compile-time shape check: mass, two flow fields, kind, one total.
LIQUID_STATE_SHAPE :: [size_of(Liquid_State) -
	(5*CELL_COUNT + 2*H_EDGES + 2*V_EDGES + size_of(i32))]byte

cell_index :: #force_inline proc "contextless" (x, y: i32) -> i32 {
	return y * GRID_W + x
}

cell_in_bounds :: #force_inline proc "contextless" (x, y: i32) -> bool {
	return x >= 0 && y >= 0 && x < GRID_W && y < GRID_H
}

// Edge indices.
edge_x_index :: #force_inline proc "contextless" (x, y: i32) -> i32 {
	return y * (GRID_W - 1) + x
}

edge_y_index :: #force_inline proc "contextless" (x, y: i32) -> i32 {
	return y * GRID_W + x
}

// =================================================================
// Reset and solid rasterization
// =================================================================

// liquid_reset zeroes the entire state: no mass, no flows, no solids.
liquid_reset :: proc(state: ^Liquid_State) {
	state^ = {}
}

// liquid_mark_solid_rect marks the inclusive cell rectangle
// [x0..x1] x [y0..y1] as solid, clamped to the grid.
liquid_mark_solid_rect :: proc(state: ^Liquid_State, x0, y0, x1, y1: i32) {
	min_x, max_x := x0, x1
	min_y, max_y := y0, y1
	if min_x > max_x {
		min_x, max_x = max_x, min_x
	}
	if min_y > max_y {
		min_y, max_y = max_y, min_y
	}
	if min_x < 0 {
		min_x = 0
	}
	if min_y < 0 {
		min_y = 0
	}
	if max_x >= GRID_W {
		max_x = GRID_W - 1
	}
	if max_y >= GRID_H {
		max_y = GRID_H - 1
	}
	if min_x > max_x || min_y > max_y {
		return
	}
	for y in min_y..=max_y {
		for x in min_x..=max_x {
			state.kind[cell_index(x, y)] = .Solid
		}
	}
}

// liquid_init_solid_borders marks the outer ring of cells solid so
// the playfield is fully enclosed.
liquid_init_solid_borders :: proc(state: ^Liquid_State) {
	liquid_mark_solid_rect(state, 0, 0, GRID_W - 1, 0)
	liquid_mark_solid_rect(state, 0, GRID_H - 1, GRID_W - 1, GRID_H - 1)
	liquid_mark_solid_rect(state, 0, 0, 0, GRID_H - 1)
	liquid_mark_solid_rect(state, GRID_W - 1, 0, GRID_W - 1, GRID_H - 1)
}

// =================================================================
// Mass seeding (level load)
// =================================================================

// liquid_zero_flows clears every edge flow. Level-load operations
// call it so a fresh level starts with no momentum.
liquid_zero_flows :: proc(state: ^Liquid_State) {
	for i in 0..<H_EDGES {
		state.flow_x[i] = 0
	}
	for i in 0..<V_EDGES {
		state.flow_y[i] = 0
	}
}

// liquid_sum_mass measures the current total mass in the field.
liquid_sum_mass :: proc(state: ^Liquid_State) -> i32 {
	sum: i32 = 0
	for i in 0..<CELL_COUNT {
		sum += state.mass[i]
	}
	return sum
}

// liquid_seed_reservoir fills the inclusive cell rectangle with exactly
// `total` mass units, filling cells to capacity before partially filling
// the final cell (row-major order). It zeros the rectangle and all
// flows, then refreshes total_mass from the field, so it is a
// level-load operation.
liquid_seed_reservoir :: proc(state: ^Liquid_State, x0, y0, x1, y1: i32, total: i32) {
	min_x, max_x := x0, x1
	min_y, max_y := y0, y1
	if min_x > max_x {
		min_x, max_x = max_x, min_x
	}
	if min_y > max_y {
		min_y, max_y = max_y, min_y
	}
	if min_x < 0 {
		min_x = 0
	}
	if min_y < 0 {
		min_y = 0
	}
	if max_x >= GRID_W {
		max_x = GRID_W - 1
	}
	if max_y >= GRID_H {
		max_y = GRID_H - 1
	}
	if min_x > max_x || min_y > max_y {
		assert(false, "cellular liquid: reservoir rectangle is empty")
		return
	}

	placed: i32 = 0
	for y in min_y..=max_y {
		for x in min_x..=max_x {
			i := cell_index(x, y)
			assert(state.kind[i] != .Solid, "cellular liquid: seeding into solid cell")
			state.mass[i] = 0
			if placed < total {
				fill := min(total - placed, CAP)
				state.mass[i] = fill
				placed += fill
			}
		}
	}
	assert(placed == total, "cellular liquid: reservoir too small for total mass")
	liquid_zero_flows(state)
	state.total_mass = liquid_sum_mass(state)
}

// =================================================================
// Debug seed patterns (diagnostics only)
// =================================================================

// all-empty: zero mass everywhere, solids untouched.
liquid_seed_all_empty :: proc(state: ^Liquid_State) {
	for i in 0..<CELL_COUNT {
		state.mass[i] = 0
	}
	liquid_zero_flows(state)
	state.total_mass = 0
}

// all-full: every non-solid cell at capacity.
liquid_seed_all_full :: proc(state: ^Liquid_State) {
	for i in 0..<CELL_COUNT {
		if state.kind[i] == .Solid {
			state.mass[i] = 0
		} else {
			state.mass[i] = CAP
		}
	}
	liquid_zero_flows(state)
	state.total_mass = liquid_sum_mass(state)
}

// single-cell: one air cell carrying the configured mass.
liquid_seed_single_cell :: proc(state: ^Liquid_State, x, y: i32, mass: i32) {
	liquid_seed_all_empty(state)
	assert(cell_in_bounds(x, y), "cellular liquid: single cell out of bounds")
	assert(state.kind[cell_index(x, y)] != .Solid, "cellular liquid: single cell is solid")
	assert(mass >= 0 && mass <= CAP, "cellular liquid: single cell mass out of range")
	state.mass[cell_index(x, y)] = mass
	state.total_mass = mass
}

// checkerboard: air cells with even (x + y) at capacity, the rest empty.
liquid_seed_checkerboard :: proc(state: ^Liquid_State) {
	for i in 0..<CELL_COUNT {
		x := i % GRID_W
		y := i / GRID_W
		if state.kind[i] == .Solid || (x + y) % 2 != 0 {
			state.mass[i] = 0
		} else {
			state.mass[i] = CAP
		}
	}
	liquid_zero_flows(state)
	state.total_mass = liquid_sum_mass(state)
}

// known-total: a fixed central reservoir carrying exactly `total` mass.
liquid_seed_known_total :: proc(state: ^Liquid_State, total: i32) {
	liquid_seed_all_empty(state)
	liquid_seed_reservoir(state, 20, 12, 59, 35, total)
}

// =================================================================
// Gravity
// =================================================================

// Gravity in grid space: +x is right, +y is down. Q15 fixed point:
// 32767 = 1 g. A zero vector means no flow. Tests pass constant
// vectors directly (the deterministic override); the game converts
// filtered accelerometer input with gravity_from_f32.
Gravity :: struct {
	x: i16,
	y: i16,
}

// gravity_from_f32 converts a filtered device-space gravity vector
// (in g, roughly -1..1) to Q15 grid space. Input is clamped to
// [-1, 1] so a noisy sensor cannot overflow the Q15 range.
gravity_from_f32 :: proc(gx, gy: f32) -> Gravity {
	x := gx
	y := gy
	if x > 1 {
		x = 1
	} else if x < -1 {
		x = -1
	}
	if y > 1 {
		y = 1
	} else if y < -1 {
		y = -1
	}
	return Gravity{i16(x * 32767), i16(y * 32767)}
}

// =================================================================
// Flow update (two-pass, plan section 4)
// =================================================================

// cell_pressure is the pressure a cell exerts on its neighbors:
// zero below the cohesion threshold (surface cells do not push),
// linear above it, and stiffer still above CAP (compression).
cell_pressure :: proc(m: i32) -> i32 {
	p := m - COHESION
	if p < 0 {
		p = 0
	}
	if m > CAP {
		p += K_STIFF * (m - CAP)
	}
	return p
}

// edge_new_flow returns the new clamped flow for one edge from cell A
// (mass ma) to cell B (mass mb). `gproj` is the Q15 gravity
// projection along the edge direction (positive A->B).
//
//   drive  = (pressure(A) - pressure(B)) / K_PRESSURE_DEN
//          + gproj / K_GRAVITY_DEN
//   flow   = (flow + drive) * DRAG_NUM / DRAG_DEN, clamped to
//            +/-FLOW_CAP
//
// Residual flows inside FLOW_DEADBAND are zeroed before integration
// so a settled state reaches exactly zero flow.
edge_new_flow :: proc(old: i16, ma, mb: i32, gproj: i16) -> i16 {
	press := (cell_pressure(ma) - cell_pressure(mb)) / K_PRESSURE_DEN
	gdrive := i32(gproj) / K_GRAVITY_DEN

	o := i32(old)
	if o > -i32(FLOW_DEADBAND) && o < i32(FLOW_DEADBAND) {
		o = 0
	}
	f := (o + press + gdrive) * DRAG_NUM / DRAG_DEN
	if f > i32(FLOW_CAP) {
		f = i32(FLOW_CAP)
	} else if f < -i32(FLOW_CAP) {
		f = -i32(FLOW_CAP)
	}
	return i16(f)
}

// liquid_integrate_flows is pass 1: update every edge flow from the
// mass snapshot and the gravity vector. Each edge's new flow depends
// only on its own old flow and the two endpoint masses, so the pass
// is order-independent. Edges with a solid endpoint carry no flow.
liquid_integrate_flows :: proc(state: ^Liquid_State, g: Gravity) {
	for y in 0..<GRID_H {
		for x in 0..<GRID_W {
			i := cell_index(x, y)
			ki := state.kind[i]
			// Horizontal edge (x,y) -> (x+1,y); direction +x.
			if x + 1 < GRID_W {
				e := edge_x_index(x, y)
				j := cell_index(x + 1, y)
				if ki == .Solid || state.kind[j] == .Solid {
					state.flow_x[e] = 0
				} else {
					state.flow_x[e] = edge_new_flow(state.flow_x[e], state.mass[i], state.mass[j], g.x)
				}
			}
			// Vertical edge (x,y) -> (x,y+1); direction +y.
			if y + 1 < GRID_H {
				e := edge_y_index(x, y)
				j := cell_index(x, y + 1)
				if ki == .Solid || state.kind[j] == .Solid {
					state.flow_y[e] = 0
				} else {
					state.flow_y[e] = edge_new_flow(state.flow_y[e], state.mass[i], state.mass[j], g.y)
				}
			}
		}
	}
}

// liquid_apply_flows is pass 2: apply every edge flow as a clamped
// paired debit/credit. A cell can never send more mass than it
// holds, and a destination can never exceed CAP_CEILING. Edges are
// visited in a fixed canonical order (row-major, horizontal then
// vertical); the order affects only the transient distribution of
// clamping, never conservation. Edges with a solid endpoint are
// skipped so no transfer can ever target a solid cell.
//
// A flow that is clamped (its demand cannot be fully met this tick)
// is zeroed: the unmet demand is dropped and rebuilt next tick from
// the updated masses, where compression pressure opposes the blocked
// direction. This guarantees that a mass fixed point implies zero
// flow, so rest states are exactly static.
liquid_apply_flows :: proc(state: ^Liquid_State) {
	for y in 0..<GRID_H {
		for x in 0..<(GRID_W - 1) {
			e := edge_x_index(x, y)
			f := state.flow_x[e]
			if f == 0 {
				continue
			}
			i := cell_index(x, y)
			j := cell_index(x + 1, y)
			if state.kind[i] == .Solid || state.kind[j] == .Solid {
				continue
			}
			if f > 0 {
				moved := min(i32(f), state.mass[i], CAP_CEILING - state.mass[j])
				state.mass[i] -= moved
				state.mass[j] += moved
				if moved < i32(f) {
					state.flow_x[e] = 0
				}
			} else {
				moved := min(-i32(f), state.mass[j], CAP_CEILING - state.mass[i])
				state.mass[j] -= moved
				state.mass[i] += moved
				if moved < -i32(f) {
					state.flow_x[e] = 0
				}
			}
		}
	}
	for y in 0..<(GRID_H - 1) {
		for x in 0..<GRID_W {
			e := edge_y_index(x, y)
			f := state.flow_y[e]
			if f == 0 {
				continue
			}
			i := cell_index(x, y)
			j := cell_index(x, y + 1)
			if state.kind[i] == .Solid || state.kind[j] == .Solid {
				continue
			}
			if f > 0 {
				moved := min(i32(f), state.mass[i], CAP_CEILING - state.mass[j])
				state.mass[i] -= moved
				state.mass[j] += moved
				if moved < i32(f) {
					state.flow_y[e] = 0
				}
			} else {
				moved := min(-i32(f), state.mass[j], CAP_CEILING - state.mass[i])
				state.mass[j] -= moved
				state.mass[i] += moved
				if moved < -i32(f) {
					state.flow_y[e] = 0
				}
			}
		}
	}
}

// =================================================================
// Simulation tick
// =================================================================

// liquid_tick advances the simulation by one 1/30 second step under
// the given Q15 grid-space gravity: pass 1 integrates the edge flows,
// pass 2 applies them to the mass field.
liquid_tick :: proc(state: ^Liquid_State, g: Gravity) {
	liquid_integrate_flows(state, g)
	liquid_apply_flows(state)

	when ODIN_DEBUG {
		liquid_assert_invariants(state)
	}
}

// =================================================================
// Invariants (debug builds)
// =================================================================

// liquid_assert_invariants checks the conservation and containment
// invariants after a tick. A failure is a hard stop: the solver must
// never compensate a mismatch by adding or deleting mass.
liquid_assert_invariants :: proc(state: ^Liquid_State) {
	sum: i32 = 0
	for i in 0..<CELL_COUNT {
		m := state.mass[i]
		if state.kind[i] == .Solid {
			assert(m == 0, "cellular liquid: mass found in solid cell")
		}
		assert(m >= 0 && m <= CAP_CEILING, "cellular liquid: mass out of range")
		sum += m
	}
	assert(sum == state.total_mass, "cellular liquid: total mass mismatch")
}
