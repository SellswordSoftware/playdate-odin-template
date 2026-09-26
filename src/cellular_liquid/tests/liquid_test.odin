package cellular_liquid_tests

import liquid ".."
import pd "../../../packages/playdate-api"
import "core:testing"

// =================================================================
// Step 2 test geometries
// =================================================================

geo_borders :: proc(state: ^liquid.Liquid_State) {
	liquid.liquid_reset(state)
	liquid.liquid_init_solid_borders(state)
}

geo_shelf :: proc(state: ^liquid.Liquid_State) {
	geo_borders(state)
	liquid.liquid_mark_solid_rect(state, 20, 24, 59, 25)
}

geo_channel :: proc(state: ^liquid.Liquid_State) {
	geo_borders(state)
	liquid.liquid_mark_solid_rect(state, 10, 15, 69, 16)
	liquid.liquid_mark_solid_rect(state, 10, 31, 69, 32)
}

geo_inner_corner :: proc(state: ^liquid.Liquid_State) {
	geo_borders(state)
	liquid.liquid_mark_solid_rect(state, 30, 20, 31, 30)
	liquid.liquid_mark_solid_rect(state, 30, 29, 45, 30)
}

geo_target_chamber :: proc(state: ^liquid.Liquid_State) {
	geo_borders(state)
	liquid.liquid_mark_solid_rect(state, 50, 15, 65, 15)
	liquid.liquid_mark_solid_rect(state, 50, 32, 65, 32)
	liquid.liquid_mark_solid_rect(state, 65, 15, 65, 32)
	liquid.liquid_mark_solid_rect(state, 50, 15, 50, 22)
	liquid.liquid_mark_solid_rect(state, 50, 30, 50, 32)
}

// =================================================================
// Host-side fake for the direct framebuffer module
//
// Each framebuffer test gets its own frame: the test runner executes
// tests in parallel, and a shared frame would race.
// =================================================================

FB_FAKE_SLOTS :: 5

// Seeding test constant (package-level: nested procs cannot capture
// locals in Odin).
FILL_ORDER_TOTAL :: 2 * liquid.CAP + 90

fake_fbs:      [FB_FAKE_SLOTS][liquid.FB_SIZE]u8
fake_graphics: [FB_FAKE_SLOTS]pd.Api_Graphics_Procs

fake_get_frame_0 :: proc "c" () -> [^]u8 { return &fake_fbs[0][0] }
fake_get_frame_1 :: proc "c" () -> [^]u8 { return &fake_fbs[1][0] }
fake_get_frame_2 :: proc "c" () -> [^]u8 { return &fake_fbs[2][0] }
fake_get_frame_3 :: proc "c" () -> [^]u8 { return &fake_fbs[3][0] }
fake_get_frame_4 :: proc "c" () -> [^]u8 { return &fake_fbs[4][0] }

make_fake_api :: proc(slot: i32) -> pd.Api {
	get_frames: [FB_FAKE_SLOTS]proc "c" () -> [^]u8 = {
		fake_get_frame_0, fake_get_frame_1, fake_get_frame_2,
		fake_get_frame_3, fake_get_frame_4,
	}
	fake_graphics[slot].get_frame = get_frames[slot]
	api: pd.Api
	api.graphics = &fake_graphics[slot]
	return api
}

// =================================================================
// Framebuffer tests
// =================================================================

@(test)
t_framebuffer_clear :: proc(t: ^testing.T) {
	api := make_fake_api(0)
	fb: [^]u8 = &fake_fbs[0][0]

	liquid.frame_buffer_clear(liquid.frame_buffer_acquire(&api), .White)
	for i in 0..<liquid.FB_SIZE {
		assert(fb[i] == 0xFF)
	}

	liquid.frame_buffer_clear(liquid.frame_buffer_acquire(&api), .Black)
	for i in 0..<liquid.FB_SIZE {
		assert(fb[i] == 0x00)
	}
}

@(test)
t_framebuffer_set_pixel_bits :: proc(t: ^testing.T) {
	api := make_fake_api(1)
	fb: [^]u8 = &fake_fbs[1][0]
	frame := liquid.frame_buffer_acquire(&api)
	liquid.frame_buffer_clear(frame, .Black)

	// First pixel of the frame is bit 7 of byte 0.
	liquid.frame_buffer_set_pixel(frame, 0, 0, true)
	assert(fb[0] == 0x80)

	// Last pixel of the first byte group is bit 0 of byte 0.
	liquid.frame_buffer_set_pixel(frame, 7, 0, true)
	assert(fb[0] == 0x81)

	// First pixel of row 1 starts at byte 50.
	liquid.frame_buffer_set_pixel(frame, 8, 1, true)
	assert(fb[liquid.FB_ROW_BYTES + 1] == 0x80)

	// Out-of-bounds pixels are ignored.
	liquid.frame_buffer_set_pixel(frame, -1, 0, true)
	liquid.frame_buffer_set_pixel(frame, 0, -1, true)
	liquid.frame_buffer_set_pixel(frame, liquid.SCREEN_W, 0, true)
	liquid.frame_buffer_set_pixel(frame, 0, liquid.SCREEN_H, true)
	assert(fb[0] == 0x81)
	assert(fb[liquid.FB_SIZE - 1] == 0x00)

	// Clearing a pixel unsets exactly its bit.
	liquid.frame_buffer_set_pixel(frame, 0, 0, false)
	assert(fb[0] == 0x01)

	// Padding bytes of a row are never written by pixel ops.
	assert(fb[50] == 0x00)
	assert(fb[51] == 0x00)
}

// =================================================================
// Invariant tests
// =================================================================

@(test)
t_invariant_fires_on_solid_mass :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	state.mass[0] = 1 // cell (0,0) is solid

	testing.expect_assert_message(t, "cellular liquid: mass found in solid cell")
	liquid.liquid_assert_invariants(&state)
}

@(test)
t_invariant_fires_on_total_mismatch :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	state.total_mass = 5 // no mass was seeded anywhere

	testing.expect_assert_message(t, "cellular liquid: total mass mismatch")
	liquid.liquid_assert_invariants(&state)
}

// =================================================================
// Seeding tests
// =================================================================

@(test)
t_seed_reservoir_fill_order :: proc(t: ^testing.T) {
	fresh :: proc() -> liquid.Liquid_State {
		s: liquid.Liquid_State
		liquid.liquid_reset(&s)
		liquid.liquid_init_solid_borders(&s)
		liquid.liquid_seed_reservoir(&s, 10, 10, 11, 11, FILL_ORDER_TOTAL)
		return s
	}

	a := fresh()
	// Row-major: two cells to capacity, the third partial, the fourth empty.
	assert(a.mass[liquid.cell_index(10, 10)] == liquid.CAP)
	assert(a.mass[liquid.cell_index(11, 10)] == liquid.CAP)
	assert(a.mass[liquid.cell_index(10, 11)] == 90)
	assert(a.mass[liquid.cell_index(11, 11)] == 0)
	assert(a.total_mass == FILL_ORDER_TOTAL)
	assert(liquid.liquid_sum_mass(&a) == FILL_ORDER_TOTAL)

	// Reset + reseed is deterministic.
	b := fresh()
	for i in 0..<liquid.CELL_COUNT {
		assert(a.mass[i] == b.mass[i])
		assert(a.kind[i] == b.kind[i])
	}
	assert(a.total_mass == b.total_mass)
}

@(test)
t_seed_pattern_totals :: proc(t: ^testing.T) {
	base :: proc() -> liquid.Liquid_State {
		s: liquid.Liquid_State
		liquid.liquid_reset(&s)
		liquid.liquid_init_solid_borders(&s)
		return s
	}

	// Expected totals computed from the geometry.
	ref := base()
	air_count: i32 = 0
	even_count: i32 = 0
	for y in 0..<liquid.GRID_H {
		for x in 0..<liquid.GRID_W {
			i := liquid.cell_index(x, y)
			if ref.kind[i] == .Air {
				air_count += 1
				if (x + y) % 2 == 0 {
					even_count += 1
				}
			}
		}
	}

	s := base()
	liquid.liquid_seed_all_empty(&s)
	assert(liquid.liquid_sum_mass(&s) == 0 && s.total_mass == 0)

	s = base()
	liquid.liquid_seed_all_full(&s)
	assert(liquid.liquid_sum_mass(&s) == air_count * liquid.CAP)
	assert(s.total_mass == liquid.liquid_sum_mass(&s))

	s = base()
	liquid.liquid_seed_single_cell(&s, 10, 10, 77)
	assert(liquid.liquid_sum_mass(&s) == 77 && s.total_mass == 77)

	s = base()
	liquid.liquid_seed_checkerboard(&s)
	assert(liquid.liquid_sum_mass(&s) == even_count * liquid.CAP)
	assert(s.total_mass == liquid.liquid_sum_mass(&s))

	s = base()
	liquid.liquid_seed_known_total(&s, 12345)
	assert(liquid.liquid_sum_mass(&s) == 12345 && s.total_mass == 12345)
}

// =================================================================
// Render tests (raw 5 x 5 block view)
// =================================================================

@(test)
t_render_solid_borders :: proc(t: ^testing.T) {
	api := make_fake_api(2)
	fb: [^]u8 = &fake_fbs[2][0]
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)

	liquid.liquid_render(&api, &state)

	// Every border pixel is white, every interior pixel is black.
	white_count: i32 = 0
	for y in 0..<liquid.SCREEN_H {
		for x in 0..<liquid.SCREEN_W {
			byte_idx := y * liquid.FB_ROW_BYTES + (x >> 3)
			bit := u8(0x80) >> (u32(x) & 7)
			on := fb[byte_idx] & bit != 0
			in_border := x < liquid.CELL_PX || y < liquid.CELL_PX ||
				x >= liquid.SCREEN_W - liquid.CELL_PX ||
				y >= liquid.SCREEN_H - liquid.CELL_PX
			if in_border {
				assert(on, "border pixel not drawn")
				white_count += 1
			} else {
				assert(!on, "interior pixel drawn")
			}
		}
	}

	// Border ring is exactly two 5px strips on each side.
	interior := (liquid.SCREEN_W - 2 * liquid.CELL_PX) * (liquid.SCREEN_H - 2 * liquid.CELL_PX)
	assert(white_count == liquid.SCREEN_W * liquid.SCREEN_H - interior)
}

@(test)
t_render_mass_blocks :: proc(t: ^testing.T) {
	api := make_fake_api(3)
	fb: [^]u8 = &fake_fbs[3][0]

	// A full-mass cell renders as a fully covered 5 x 5 block.
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	liquid.liquid_seed_single_cell(&state, 10, 10, liquid.CAP)
	liquid.liquid_render(&api, &state)

	for dy in 0..<liquid.CELL_PX {
		for dx in 0..<liquid.CELL_PX {
			x := 10 * liquid.CELL_PX + dx
			y := 10 * liquid.CELL_PX + dy
			byte_idx := y * liquid.FB_ROW_BYTES + (x >> 3)
			bit := u8(0x80) >> (u32(x) & 7)
			assert(fb[byte_idx] & bit != 0, "mass cell pixel not drawn")
		}
	}
	// Border ring plus exactly one 25-pixel mass block.
	assert(liquid.frame_buffer_count_white(liquid.frame_buffer_acquire(&api)) == 6300 + 25)

	// Zero mass renders empty.
	liquid.liquid_seed_single_cell(&state, 10, 10, 0)
	liquid.liquid_render(&api, &state)
	assert(liquid.frame_buffer_count_white(liquid.frame_buffer_acquire(&api)) == 6300)
}

@(test)
t_render_empty_field :: proc(t: ^testing.T) {
	api := make_fake_api(4)
	fb: [^]u8 = &fake_fbs[4][0]
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)

	liquid.liquid_render(&api, &state)

	for i in 0..<liquid.FB_SIZE {
		assert(fb[i] == 0x00)
	}
}

// =================================================================
// Solid rasterization tests
// =================================================================

@(test)
t_mark_solid_rect_clamps_to_grid :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_mark_solid_rect(&state, -5, -5, liquid.GRID_W + 5, liquid.GRID_H + 5)
	for i in 0..<liquid.CELL_COUNT {
		assert(state.kind[i] == .Solid)
	}
}

@(test)
t_mark_solid_rect_inner :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_mark_solid_rect(&state, 10, 10, 19, 19)

	solid_count: i32 = 0
	for y in 0..<liquid.GRID_H {
		for x in 0..<liquid.GRID_W {
			in_rect := x >= 10 && x <= 19 && y >= 10 && y <= 19
			if in_rect {
				assert(state.kind[liquid.cell_index(x, y)] == .Solid)
				solid_count += 1
			} else {
				assert(state.kind[liquid.cell_index(x, y)] == .Air)
			}
		}
	}
	assert(solid_count == 100)
}

// =================================================================
// Reset and shape tests
// =================================================================

@(test)
t_reset_is_zero :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)

	// Array sizes / struct shape.
	assert(liquid.CELL_COUNT == liquid.GRID_W * liquid.GRID_H)
	assert(liquid.H_EDGES == (liquid.GRID_W - 1) * liquid.GRID_H)
	assert(liquid.V_EDGES == liquid.GRID_W * (liquid.GRID_H - 1))
	assert(size_of(liquid.Liquid_State) ==
		5*liquid.CELL_COUNT + 2*liquid.H_EDGES + 2*liquid.V_EDGES + size_of(i32))

	// Zero total mass, zero fields.
	assert(state.total_mass == 0)
	for i in 0..<liquid.CELL_COUNT {
		assert(state.mass[i] == 0)
	}
	for i in 0..<liquid.H_EDGES {
		assert(state.flow_x[i] == 0)
	}
	for i in 0..<liquid.V_EDGES {
		assert(state.flow_y[i] == 0)
	}

	// Border ring is solid, interior is air.
	border_solid_count: i32 = 0
	for y in 0..<liquid.GRID_H {
		for x in 0..<liquid.GRID_W {
			on_border := x == 0 || y == 0 || x == liquid.GRID_W - 1 || y == liquid.GRID_H - 1
			if on_border {
				assert(state.kind[liquid.cell_index(x, y)] == .Solid)
				border_solid_count += 1
			} else {
				assert(state.kind[liquid.cell_index(x, y)] == .Air)
			}
		}
	}
	assert(border_solid_count == 2 * liquid.GRID_W + 2 * (liquid.GRID_H - 2))

	// Invariants hold on the fresh state.
	liquid.liquid_assert_invariants(&state)
}

// =================================================================
// Gravity conversion tests
// =================================================================

@(test)
t_gravity_from_f32 :: proc(t: ^testing.T) {
	assert(liquid.gravity_from_f32(0, 1) == liquid.Gravity{0, 32767})
	assert(liquid.gravity_from_f32(1, 0) == liquid.Gravity{32767, 0})
	assert(liquid.gravity_from_f32(-1, -1) == liquid.Gravity{-32767, -32767})
	assert(liquid.gravity_from_f32(0, 0) == liquid.Gravity{0, 0})

	// A 45-degree tilt maps to equal positive components.
	d := liquid.gravity_from_f32(0.5, 0.5)
	assert(d.x == d.y && d.x > 0)

	// Out-of-range sensor input clamps to +/-1 g.
	assert(liquid.gravity_from_f32(5, -5) == liquid.Gravity{32767, -32767})
}

// =================================================================
// Pass-2 clamped application tests
// =================================================================

@(test)
t_apply_flows_clamps :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	geo_borders(&state)
	liquid.liquid_seed_reservoir(&state, 10, 10, 11, 10, 1000)
	// (10,10) holds 1000, (11,10) is empty, all flows are zero.

	// Source-limited: a flow larger than the source mass moves only
	// what the source holds.
	state.flow_x[liquid.edge_x_index(10, 10)] = 5000
	liquid.liquid_apply_flows(&state)
	assert(state.mass[liquid.cell_index(10, 10)] == 0)
	assert(state.mass[liquid.cell_index(11, 10)] == 1000)
	assert(liquid.liquid_sum_mass(&state) == 1000)

	// Destination-limited: a destination at the compression ceiling
	// accepts nothing.
	state.mass[liquid.cell_index(12, 10)] = liquid.CAP_CEILING
	state.flow_x[liquid.edge_x_index(11, 10)] = 500
	liquid.liquid_apply_flows(&state)
	assert(state.mass[liquid.cell_index(11, 10)] == 1000)
	assert(state.mass[liquid.cell_index(12, 10)] == liquid.CAP_CEILING)
	assert(liquid.liquid_sum_mass(&state) == 1000 + liquid.CAP_CEILING)

	// Negative flow moves mass in the opposite direction.
	state.flow_x[liquid.edge_x_index(10, 10)] = -300
	liquid.liquid_apply_flows(&state)
	assert(state.mass[liquid.cell_index(10, 10)] == 300)
	assert(state.mass[liquid.cell_index(11, 10)] == 700)
	assert(liquid.liquid_sum_mass(&state) == 1000 + liquid.CAP_CEILING)

	// Solid-adjacent edges are skipped: no transfer touches a solid.
	state.mass[liquid.cell_index(1, 5)] = 500
	state.flow_x[liquid.edge_x_index(0, 5)] = 1000
	liquid.liquid_apply_flows(&state)
	assert(state.mass[liquid.cell_index(0, 5)] == 0)
	assert(state.mass[liquid.cell_index(1, 5)] == 500)
	assert(liquid.liquid_sum_mass(&state) == 1000 + liquid.CAP_CEILING + 500)
}

// =================================================================
// Conservation under long random-gravity runs
// =================================================================

@(test)
t_random_gravity_conserve :: proc(t: ^testing.T) {
	geos: [5]proc(^liquid.Liquid_State) = {
		geo_borders, geo_shelf, geo_channel, geo_inner_corner, geo_target_chamber,
	}
	for gi in 0..<5 {
		state: liquid.Liquid_State
		geos[gi](&state)
		// Seed a corner reservoir that no geometry overlaps.
		liquid.liquid_seed_reservoir(&state, 5, 5, 9, 9, 256000)
		expected := state.total_mass

		for i in 0..=1999 {
			// Deterministic pseudo-random Q15 gravity, all directions
			// and magnitudes.
			g := liquid.Gravity{
				i16(((i * 37) % 65535) - 32767),
				i16(((i * 91) % 65535) - 32767),
			}
			liquid.liquid_tick(&state, g)
			assert(liquid.liquid_sum_mass(&state) == expected)
		}
		liquid.liquid_assert_invariants(&state)
	}
}

// =================================================================
// Settling and rest-state tests
// =================================================================

// tick_until_settled runs ticks until the mass field is unchanged for
// `stable_needed` consecutive ticks. It returns whether that happened
// within the budget.
tick_until_settled :: proc(state: ^liquid.Liquid_State, g: liquid.Gravity, budget: i32, stable_needed: i32) -> bool {
	stable: i32 = 0
	for tick in 0..=budget {
		prev := state.mass
		liquid.liquid_tick(state, g)
		same := true
		for i in 0..<liquid.CELL_COUNT {
			if state.mass[i] != prev[i] {
				same = false
				break
			}
		}
		if same {
			stable += 1
		} else {
			stable = 0
		}
		if stable >= stable_needed {
			return true
		}
	}
	return false
}

all_flows_zero :: proc(state: ^liquid.Liquid_State) -> bool {
	for i in 0..<liquid.H_EDGES {
		if state.flow_x[i] != 0 {
			return false
		}
	}
	for i in 0..<liquid.V_EDGES {
		if state.flow_y[i] != 0 {
			return false
		}
	}
	return true
}

@(test)
t_settle_down_converges :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	liquid.liquid_seed_reservoir(&state, 20, 12, 59, 13, 5120000)
	expected := state.total_mass

	g := liquid.Gravity{0, liquid.G_Q15}
	settled := tick_until_settled(&state, g, 1800, 30)
	assert(settled, "reservoir did not settle within 1800 ticks")

	// Exact mass through the fall.
	assert(liquid.liquid_sum_mass(&state) == expected)
	liquid.liquid_assert_invariants(&state)

	// At rest the liquid reached the floor and all flows are exactly
	// zero.
	reached_floor := false
	for x in 0..<liquid.GRID_W {
		if state.mass[liquid.cell_index(x, liquid.GRID_H - 2)] > 0 {
			reached_floor = true
		}
	}
	assert(reached_floor, "liquid did not reach the floor")
	assert(all_flows_zero(&state), "nonzero flow at rest")

	// One more tick changes nothing.
	prev := state.mass
	liquid.liquid_tick(&state, g)
	for i in 0..<liquid.CELL_COUNT {
		assert(state.mass[i] == prev[i])
	}
}

@(test)
t_zero_gravity_rest :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	liquid.liquid_seed_reservoir(&state, 20, 20, 29, 23, 100000)
	expected := state.total_mass

	// Zero gravity: the liquid spreads by pressure alone and must
	// reach an exactly static rest state (invariant 5).
	settled := tick_until_settled(&state, liquid.Gravity{}, 1800, 30)
	assert(settled, "zero-gravity spread did not settle within 1800 ticks")
	assert(all_flows_zero(&state), "nonzero flow at rest")
	assert(liquid.liquid_sum_mass(&state) == expected)
	liquid.liquid_assert_invariants(&state)
}

// =================================================================
// Leveling (step 5): the pressure term flattens uneven liquid
// =================================================================

@(test)
t_leveling :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	// A 2-wide container (walls at x=19 and x=22) so the liquid
	// cannot spread sideways out of the test region.
	liquid.liquid_mark_solid_rect(&state, 19, 1, 19, 46)
	liquid.liquid_mark_solid_rect(&state, 22, 1, 22, 46)
	// Two adjacent columns of different heights: 3 cells vs 1 cell.
	liquid.liquid_seed_reservoir(&state, 20, 44, 20, 46, 3 * liquid.CAP)
	liquid.liquid_seed_reservoir(&state, 21, 46, 21, 46, 1 * liquid.CAP)
	expected := state.total_mass

	g := liquid.Gravity{0, liquid.G_Q15}
	settled := tick_until_settled(&state, g, 1800, 30)
	assert(settled, "uneven columns did not settle within 1800 ticks")
	assert(liquid.liquid_sum_mass(&state) == expected)
	liquid.liquid_assert_invariants(&state)

	// The 4 cells of mass level into two equal 2-cell columns and
	// the surface is level. At rest the horizontal pressure term is
	// zero, so adjacent cells differ only by integer rounding
	// (press = (pA - pB) / 16 must land in {-1, 0, 1}).
	close_enough :: proc(a, b: i32) {
		d := a - b
		assert(d >= -32 && d <= 32, "adjacent cells not level")
	}
	close_enough(state.mass[liquid.cell_index(20, 46)], state.mass[liquid.cell_index(21, 46)])
	close_enough(state.mass[liquid.cell_index(20, 45)], state.mass[liquid.cell_index(21, 45)])
	assert(state.mass[liquid.cell_index(20, 45)] > 0)
	assert(state.mass[liquid.cell_index(20, 44)] == 0)
	assert(state.mass[liquid.cell_index(21, 44)] == 0)
	assert(all_flows_zero(&state), "nonzero flow at rest")
}

// =================================================================
// Compression (step 5): full regions compress, never overflow
// =================================================================

@(test)
t_compression_ceiling :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	// A 1-wide channel (walls at x=19 and x=21) so the column cannot
	// spread sideways: the only place the liquid can go under gravity
	// is into compression at the floor.
	liquid.liquid_mark_solid_rect(&state, 19, 1, 19, 46)
	liquid.liquid_mark_solid_rect(&state, 21, 1, 21, 46)
	// A full 1 x 40 column under gravity: the bottom cells compress
	// but must never exceed CAP_CEILING.
	liquid.liquid_seed_reservoir(&state, 20, 7, 20, 46, 40 * liquid.CAP)
	expected := state.total_mass

	g := liquid.Gravity{0, liquid.G_Q15}
	settled := tick_until_settled(&state, g, 1800, 30)
	assert(settled, "full column did not settle within 1800 ticks")
	assert(liquid.liquid_sum_mass(&state) == expected)
	liquid.liquid_assert_invariants(&state)
	assert(all_flows_zero(&state), "nonzero flow at rest")

	// The bottom cell is compressed (at or above CAP) and at or
	// below the ceiling; the top of the column is at or below CAP.
	bottom := state.mass[liquid.cell_index(20, 46)]
	top := state.mass[liquid.cell_index(20, 7)]
	assert(bottom >= liquid.CAP, "bottom cell not compressed")
	assert(bottom <= liquid.CAP_CEILING, "bottom cell over ceiling")
	assert(top <= liquid.CAP, "top cell over capacity")
}

// =================================================================
// Momentum (step 3): flows persist through a gravity reversal
// =================================================================

@(test)
t_momentum_overshoot :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)
	liquid.liquid_seed_reservoir(&state, 35, 21, 44, 26, 1280000)

	com_x :: proc(state: ^liquid.Liquid_State) -> f32 {
		sum: i64 = 0
		mass: i64 = 0
		for y in 0..<liquid.GRID_H {
			for x in 0..<liquid.GRID_W {
				m := state.mass[liquid.cell_index(x, y)]
				if m != 0 {
					sum += i64(m) * i64(x)
					mass += i64(m)
				}
			}
		}
		return f32(sum) / f32(mass)
	}

	g_right := liquid.Gravity{liquid.G_Q15, 0}
	g_left := liquid.Gravity{-liquid.G_Q15, 0}

	// Build a rightward flow in free flight: the reservoir starts at
	// x=35..44 and the right wall is at x=77, so 40 ticks (~15 cells
	// of travel) keeps the pile clear of the wall while the flow is
	// near FLOW_CAP.
	for i in 0..=39 {
		liquid.liquid_tick(&state, g_right)
	}
	x0 := com_x(&state)

	// Reverse gravity: the center of mass must keep moving right for
	// several ticks (the flow keeps its old direction), then reverse.
	kept_moving: i32 = 0
	turned := false
	for i in 0..=119 {
		liquid.liquid_tick(&state, g_left)
		if !turned {
			if com_x(&state) > x0 {
				kept_moving += 1
			} else {
				turned = true
			}
		}
	}
	assert(kept_moving >= 3, "no momentum: center of mass reversed immediately")
	assert(turned, "center of mass never reversed after 120 ticks")
	assert(liquid.liquid_sum_mass(&state) == state.total_mass)
}

// =================================================================
// Directional gravity (step 4): all directions, continuous angles
// =================================================================

@(test)
t_gravity_moves_mass_to_walls :: proc(t: ^testing.T) {
	cases: [8]liquid.Gravity = {
		{0, liquid.G_Q15}, {liquid.G_Q15, 0}, {0, -liquid.G_Q15}, {-liquid.G_Q15, 0},
		{23170, 23170}, {23170, -23170}, {-23170, 23170}, {-23170, -23170},
	}
	for d in 0..<8 {
		state: liquid.Liquid_State
		liquid.liquid_reset(&state)
		liquid.liquid_init_solid_borders(&state)
		liquid.liquid_seed_reservoir(&state, 35, 21, 44, 26, 1280000)
		expected := state.total_mass

		g := cases[d]
		for i in 0..=599 {
			liquid.liquid_tick(&state, g)
		}

		// No loss through the walls: mass is exact.
		assert(liquid.liquid_sum_mass(&state) == expected)
		liquid.liquid_assert_invariants(&state)

		// Mass reaches the primary wall and diagonal inputs bias the
		// pile along the secondary axis.
		minx, miny, maxx, maxy: i32 = 999, 999, -1, -1
		cx_sum: i64 = 0
		y_sum: i64 = 0
		for y in 0..<liquid.GRID_H {
			for x in 0..<liquid.GRID_W {
				m := state.mass[liquid.cell_index(x, y)]
				if m == 0 {
					continue
				}
				if x < minx { minx = x }
				if x > maxx { maxx = x }
				if y < miny { miny = y }
				if y > maxy { maxy = y }
				cx_sum += i64(m) * i64(x)
				y_sum += i64(m) * i64(y)
			}
		}
		switch d {
		case 0: // down
			assert(maxy == liquid.GRID_H - 2, "mass did not reach bottom wall")
		case 1: // right
			assert(maxx == liquid.GRID_W - 2, "mass did not reach right wall")
		case 2: // up
			assert(miny == 1, "mass did not reach top wall")
		case 3: // left
			assert(minx == 1, "mass did not reach left wall")
		case 4: // down-right
			assert(maxy == liquid.GRID_H - 2, "mass did not reach bottom wall")
			assert(f32(cx_sum)/f32(expected) > 39.5, "diagonal bias not right")
		case 5: // up-right
			assert(maxx == liquid.GRID_W - 2, "mass did not reach right wall")
			assert(f32(y_sum)/f32(expected) < 23.5, "diagonal bias not up")
		case 6: // down-left
			assert(maxy == liquid.GRID_H - 2, "mass did not reach bottom wall")
			assert(f32(cx_sum)/f32(expected) < 39.5, "diagonal bias not left")
		case 7: // up-left
			assert(miny == 1, "mass did not reach top wall")
			assert(f32(cx_sum)/f32(expected) < 39.5, "diagonal bias not left")
		}
	}
}

// =================================================================
// No-op tick
// =================================================================

@(test)
t_tick_noop_preserves_state :: proc(t: ^testing.T) {
	state: liquid.Liquid_State
	liquid.liquid_reset(&state)
	liquid.liquid_init_solid_borders(&state)

	for i in 0..=10 {
		liquid.liquid_tick(&state, liquid.Gravity{}) // zero gravity: no flow
	}

	for i in 0..<liquid.CELL_COUNT {
		assert(state.mass[i] == 0)
	}
	assert(all_flows_zero(&state))
	assert(state.total_mass == 0)
}
