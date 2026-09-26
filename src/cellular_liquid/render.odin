package cellular_liquid

import pd "../../packages/playdate-api"

// liquid_render draws the current state directly into the framebuffer.
//
// Step 1: solid geometry and every cell with mass > 0 render as filled
// 5 x 5 blocks (raw mass view, no dither yet). Coverage scaling and
// dithering arrive in step 7.
liquid_render :: proc(pd_api: ^pd.Api, state: ^Liquid_State) {
	frame := frame_buffer_acquire(pd_api)
	frame_buffer_clear(frame, .Black)
	for y in 0..<GRID_H {
		for x in 0..<GRID_W {
			i := cell_index(x, y)
			if state.kind[i] == .Solid || state.mass[i] > 0 {
				frame_buffer_draw_cell(frame, x, y, true)
			}
		}
	}
}
