// EXPLANATION:
// Creates the game window, manages the primary game loop,
// and defines the memory pool for hot-reloading
//
// See gameplay.odin for Pitfall game code

package pitfall

import rl "vendor:raylib"

Game_Memory :: struct {
	// global
	should_close: bool,

	viewport: Viewport_Rectangle,
	// camera_ui: rl.Camera2D,
	camera: rl.Camera2D,
	ui_zoom_mult: f32,

	// pitfall
	game: Gameplay_State,
}

g_mem: ^Game_Memory
render_texture: ^rl.Texture2D
game: ^Gameplay_State

refresh_globals :: proc() {
	game = &g_mem.game
	render_texture = &g_mem.viewport.render.texture
}

frame_time: f32

update :: proc() {
	frame_time = rl.GetFrameTime()

	update_aspect_ratio()
	g_mem.camera = update_camera()

	// Global key bindings
	// ----------------------------------------------------------------------------
	
	// quit program
	if !ODIN_BUILD_WEB && rl.IsKeyPressed(.Q) {
		g_mem.should_close = true
	}

	// debug toggle
	if rl.IsKeyPressed(.F3) {
		game.is_debug = !game.is_debug
	}

	// fullscreen toggle
	pressed_alt_enter := (rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)) && rl.IsKeyPressed(.ENTER)
	if pressed_alt_enter || rl.IsKeyPressed(.F11) {
		rl.ToggleBorderlessWindowed()
	}

	gameplay_update()

	if game.is_paused {
		menu_update()
	}
}

update_camera :: proc() -> rl.Camera2D {
	c: rl.Camera2D = {
		target = {GAME_WIDTH/2, GAME_HEIGHT/2},
		offset = {
			f32(render_texture.width)/2,
			f32(render_texture.height)/2,
		},
	}
	base_zoom := f32(render_texture.height)/GAME_HEIGHT

	// Uses `game.camera_zoom` and `game.camera_target`
	// to properly scale with render texture and window proportions
	c.zoom = base_zoom + base_zoom*game.camera_zoom
	c.target -= game.camera_target

	return c
}

draw :: proc() {
	rl.BeginTextureMode(g_mem.viewport.render)
		rl.BeginMode2D(g_mem.camera)

		gameplay_draw()

		rl.EndMode2D()
	rl.EndTextureMode()

	rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Draw render texture to screen
		rl.DrawTexturePro(render_texture^,
			{0, 0, f32(render_texture.width), f32(-render_texture.height)},
			{g_mem.viewport.x, g_mem.viewport.y, g_mem.viewport.width, g_mem.viewport.height},
			{0, 0}, 0, rl.WHITE)

	rl.EndDrawing()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT, .WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_NAME)
	rl.InitAudioDevice()
	rl.SetMasterVolume(DEFAULT_VOLUME)
	rl.SetWindowMinSize(GAME_WIDTH, GAME_HEIGHT)
	rl.SetTargetFPS(300)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		viewport = { render_scale = 4 }, // render resolution is render scale * game resolution
		ui_zoom_mult = 1,
	}

	gameplay_init()
	init_viewport_render_texture()

	game_hot_reloaded(g_mem)
}

@(export)
game_update :: proc() {
	update()
	draw()
	free_all(context.temp_allocator)
}

@(export)
game_should_close :: proc() -> bool {
	return rl.WindowShouldClose() || g_mem.should_close
}

@(export)
game_shutdown :: proc() {
	gameplay_shutdown()
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseAudioDevice()
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)

	refresh_globals()
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
