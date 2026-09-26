package cellular_liquid

import pd "../../packages/playdate-api"

// =================================================================
// Direct framebuffer owner
//
// The Playdate LCD is 400 x 240, 1 bit per pixel. Rows have a stride
// of LCD_ROWSIZE = 52 bytes (50 data bytes + 2 padding), bit 7 of
// each byte is the leftmost pixel. This module is the only code that
// writes the raw frame; everything else goes through it.
// =================================================================

FB_ROW_BYTES :: 52
FB_SIZE :: SCREEN_H * FB_ROW_BYTES

// Compile-time checks (negative array count fails the build).
FB_ROW_BYTES_CHECK :: [FB_ROW_BYTES - 52]byte
FB_SIZE_CHECK :: [FB_SIZE - 12480]byte

// frame_buffer_acquire returns the raw 12000-byte frame. Call once
// per frame and pass the result to the write helpers below.
frame_buffer_acquire :: proc(pd_api: ^pd.Api) -> [^]u8 {
	return pd_api.graphics.get_frame()
}

// frame_buffer_clear writes the whole frame to a solid color. This
// is the only place that may write padding bytes.
frame_buffer_clear :: proc(frame: [^]u8, color: pd.Solid_Color) {
	if color == .White {
		for i in 0..<FB_SIZE {
			frame[i] = 0xFF
		}
	} else {
		for i in 0..<FB_SIZE {
			frame[i] = 0x00
		}
	}
}

frame_buffer_set_pixel :: #force_inline proc(frame: [^]u8, x, y: i32, on: bool) {
	if x < 0 || y < 0 || x >= SCREEN_W || y >= SCREEN_H {
		return
	}
	idx := y * FB_ROW_BYTES + (x >> 3)
	mask := u8(0x80) >> (u32(x) & 7)
	if on {
		frame[idx] |= mask
	} else {
		frame[idx] &= ~mask
	}
}

// frame_buffer_count_white counts set bits in the frame.
frame_buffer_count_white :: proc(frame: [^]u8) -> i32 {
	count: i32 = 0
	for i in 0..<FB_SIZE {
		b := frame[i]
		for bit in 0..<8 {
			count += i32((b >> u8(bit)) & 1)
		}
	}
	return count
}

// frame_buffer_draw_cell fills the 5 x 5 pixel block for one grid cell.
frame_buffer_draw_cell :: #force_inline proc(frame: [^]u8, cx, cy: i32, on: bool) {
	x0 := cx * CELL_PX
	y0 := cy * CELL_PX
	for dy in 0..<CELL_PX {
		for dx in 0..<CELL_PX {
			frame_buffer_set_pixel(frame, x0 + dx, y0 + dy, on)
		}
	}
}
