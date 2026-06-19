// EXPLANATION:
// Simple input actions system

package pitfall

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"

ODIN_BUILD_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

Vec2 :: rl.Vector2 // lazy shorthand

// Draw debug text in the upper left corner, using odin formatting
debug_text_y: i32
print_debug :: proc(text: string, args: ..any, first_line: bool = false) {
	if first_line { debug_text_y = 0 }
	// temporary formatted cstring
	cstr := strings.clone_to_cstring(
			  fmt.aprintf(text, ..args, allocator = context.temp_allocator),
			  allocator = context.temp_allocator)

	debug_text_y += 10
	rl.DrawText(cstr, 10, debug_text_y, 10, rl.WHITE)
}

// updates a timer,
// returns true when timer runs out
timer_countdown :: proc(timer: ^f32, reset: f32 = 0, dt: f32 = 0) -> bool {
	if timer^ > 0 {
		dt := dt
		if dt == 0 { dt = rl.GetFrameTime() }
		timer^ -= dt
		return false
	} else {
		timer^ = reset
		return true
	}
}

get_rectangle_center :: proc(r: rl.Rectangle) -> Vec2 {
	return {r.x + r.width/2, r.y + r.height/2}
}

draw_texture_flipped :: proc(t: rl.Texture) {
	rl.DrawTexturePro(
		t,
		{0, 0, f32(t.width), f32(-t.height)},
		{0, 0, f32(t.width), f32(t.height)},
		{}, 0, rl.WHITE,
	)
}
