package cellular_liquid_tests

import liquid ".."
import "core:fmt"
import "core:testing"

@(test)
t_scratch_dynamics :: proc(t: ^testing.T) {
	state3: liquid.Liquid_State
	liquid.liquid_reset(&state3)
	liquid.liquid_init_solid_borders(&state3)
	liquid.liquid_seed_reservoir(&state3, 35, 21, 44, 26, 1280000)
	com_x :: proc(s: ^liquid.Liquid_State) -> f32 {
		sum: i64 = 0
		mass: i64 = 0
		for y in 0..<liquid.GRID_H {
			for x in 0..<liquid.GRID_W {
				m := s.mass[liquid.cell_index(x, y)]
				if m != 0 {
					sum += i64(m) * i64(x)
					mass += i64(m)
				}
			}
		}
		return f32(sum) / f32(mass)
	}
	bbox :: proc(s: ^liquid.Liquid_State) {
		minx, maxx: i32 = 999, -1
		miny, maxy: i32 = 999, -1
		for y in 0..<liquid.GRID_H {
			for x in 0..<liquid.GRID_W {
				if s.mass[liquid.cell_index(x, y)] > 0 {
					if x < minx { minx = x }
					if x > maxx { maxx = x }
					if y < miny { miny = y }
					if y > maxy { maxy = y }
				}
			}
		}
		fmt.println("  bbox x:", minx, "..", maxx, " y:", miny, "..", maxy)
	}
	gr := liquid.Gravity{liquid.G_Q15, 0}
	gl := liquid.Gravity{-liquid.G_Q15, 0}
	for i in 0..=39 {
		if i%10 == 0 {
			fmt.println("tick", i, "com_x=", com_x(&state3))
			bbox(&state3)
		}
		liquid.liquid_tick(&state3, gr)
	}
	x0 := com_x(&state3)
	fmt.println("x0:", x0)
	for i in 0..=25 {
		liquid.liquid_tick(&state3, gl)
		if i%5 == 0 {
			fmt.println("post", i, "com_x=", com_x(&state3))
			bbox(&state3)
		}
	}
}
