package game

import pd "../packages/playdate-api"
import cl "cellular_liquid"
import "base:runtime"
import "core:fmt"
import "core:math"
import str "core:strings"

// Explicitly selected update path: when true, the new cellular liquid
// solver owns the frame and the legacy bouncing-logo template is
// skipped entirely.
use_cellular_liquid :: true

pd_api: ^pd.Api
global_ctx: runtime.Context
logo: ^pd.Sprite
logo_w :: 105
logo_h :: 31
logo_x: f32 = 195
logo_y: f32 = 120

liquid: cl.Liquid_State
liquid_frame_count: i32

// Step 1 level: a central reservoir with a fixed total mass.
// (Rescaled from the old 255-unit scale x256 to the Q16 mass model.)
LEVEL_RESERVOIR_TOTAL :: i32(1280000)

// Tuning (step 6 consolidates these into the solver config block).
ACC_ALPHA :: 0.15 // accelerometer low-pass coefficient
ACC_DEAD_ZONE :: 0.03 // accelerometer dead zone

// The simulator does not report a tilt, so a zero accelerometer would
// leave the liquid floating. Fall back to this constant gravity when
// the filtered input is zero; real tilt always overrides it.
DEV_GRAVITY_X :: 0.0
DEV_GRAVITY_Y :: 1.0

// Filtered accelerometer state (device space).
acc_x: f32
acc_y: f32

// read_gravity converts the filtered accelerometer into a grid-space
// gravity vector. Device +x maps to grid +x (right) and device +y to
// grid +y (down); flip a sign here if the device convention differs.
read_gravity :: proc() -> cl.Gravity {
	ax: f32
	ay: f32
	az: f32
	pd_api.system.get_accelerometer(&ax, &ay, &az)

	acc_x += ACC_ALPHA * (ax - acc_x)
	acc_y += ACC_ALPHA * (ay - acc_y)
	if math.abs(acc_x) < ACC_DEAD_ZONE {
		acc_x = 0
	}
	if math.abs(acc_y) < ACC_DEAD_ZONE {
		acc_y = 0
	}

	gx, gy := acc_x, acc_y
	if gx == 0 && gy == 0 {
		gx, gy = DEV_GRAVITY_X, DEV_GRAVITY_Y
	}
	return cl.gravity_from_f32(gx, gy)
}

@(export)
eventHandler :: proc "c" (api: ^pd.Api, event: pd.System_Event, arg: u32) -> i32 {
	#partial switch event {
	case .Init:
		pd_api = api
		global_ctx = pd.playdate_context_create(api)
		context = global_ctx
		game_init()
		api.system.set_update_callback(update_callback, api)
	}
	return 0
}

update_callback :: proc "c" (userdata: rawptr) -> pd.Update_Result {
	context = global_ctx
	game_update()
	return .Update_Display
}

game_init :: proc() {
	pd_api.graphics.set_background_color(.Black)

	if use_cellular_liquid {
		cl.liquid_reset(&liquid)
		cl.liquid_init_solid_borders(&liquid)
		cl.liquid_seed_reservoir(&liquid, 20, 12, 59, 35, LEVEL_RESERVOIR_TOTAL)
		return
	}

	logo = pd_api.sprite.new_sprite()
	bounds_x := logo_x - (logo_w / 2)
	bounds_y := logo_y - (logo_h / 2)

	pd_api.sprite.set_bounds(logo, pd.PDRect{bounds_x, bounds_y, logo_w, logo_h})
	out_err: cstring
	image := pd_api.graphics.load_bitmap("assets/bitmaps/logo.png", &out_err)
	if out_err != nil {
		message := str.clone_to_cstring(fmt.tprintf("error: %s", out_err))
		pd_api.system.log_to_console(message)
	}

	pd_api.sprite.set_image(logo, image, .Unflipped)
	pd_api.sprite.add_sprite(logo)
}

game_update :: proc() {
	if use_cellular_liquid {
		cl.liquid_tick(&liquid, read_gravity())
		cl.liquid_render(pd_api, &liquid)

		liquid_frame_count += 1
		if liquid_frame_count == 30 {
			frame := cl.frame_buffer_acquire(pd_api)
			raw_ax: f32
			raw_ay: f32
			raw_az: f32
			pd_api.system.get_accelerometer(&raw_ax, &raw_ay, &raw_az)
			g := read_gravity()
			msg := str.clone_to_cstring(fmt.tprintf(
				"cellular_liquid: frame 30 total_mass=%d measured=%d white_px=%d acc=(%.2f,%.2f,%.2f) gravity=(%.2f,%.2f)",
				liquid.total_mass, cl.liquid_sum_mass(&liquid), cl.frame_buffer_count_white(frame),
				raw_ax, raw_ay, raw_az, g.x, g.y,
			))
			pd_api.system.log_to_console(msg)
		}
		return
	}

	pd_api.graphics.clear(pd.color_solid(pd.Solid_Color.Black))

	t := pd_api.system.get_elapsed_time()
	offset := math.sin(t * 2.0) * 60.0
	pd_api.sprite.move_to(logo, logo_x, logo_y + offset)
	pd_api.sprite.update_and_draw_sprites()
}
