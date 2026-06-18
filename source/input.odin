// EXPLANATION:
// Simple input actions system

package pitfall

import rl "vendor:raylib"

Input_State :: struct {
	// actions
	move_up, move_down,
	move_left, move_right,
	jump, jumping,
	shift,
	space,
	menu_left, menu_right,
	menu_up, menu_down,
	menu_ok,
	pause: bool,

	// mouse
	mouse_pos_game,
	mouse_pos_ui,
	mouse_delta: Vec2,
	mouse_wheel_move: f32,
}

input: Input_State

get_input :: proc(old_input: Input_State) -> Input_State {
	updated_input := old_input // keep previous input for next tick

	// keyboard
	updated_input.jump       ||= rl.IsKeyPressed(.UP)      || rl.IsKeyPressed(.W) || rl.IsKeyPressed(.SPACE)
	updated_input.move_up    ||= rl.IsKeyDown(.UP)         || rl.IsKeyDown(.W)
	updated_input.move_down  ||= rl.IsKeyDown(.DOWN)       || rl.IsKeyDown(.S)
	updated_input.move_left  ||= rl.IsKeyDown(.LEFT)       || rl.IsKeyDown(.A)
	updated_input.move_right ||= rl.IsKeyDown(.RIGHT)      || rl.IsKeyDown(.D)
	updated_input.shift      ||= rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	updated_input.pause      ||= rl.IsKeyPressed(.ESCAPE)  || rl.IsKeyPressed(.P)

	updated_input.menu_up    ||= rl.IsKeyPressed(.UP)      || rl.IsKeyPressed(.W)
	updated_input.menu_down  ||= rl.IsKeyPressed(.DOWN)    || rl.IsKeyPressed(.S)
	updated_input.menu_left  ||= rl.IsKeyPressed(.LEFT)    || rl.IsKeyPressed(.A)
	updated_input.menu_right ||= rl.IsKeyPressed(.RIGHT)   || rl.IsKeyPressed(.D)
	updated_input.menu_ok    ||= rl.IsKeyPressed(.ENTER)   || rl.IsKeyPressed(.SPACE)

	// gamepad
	gid: i32 = 0
	STICK_DEADZONE :: 0.2
	if rl.IsGamepadAvailable(gid) {
		updated_input.jump       ||= rl.IsGamepadButtonPressed(gid, .RIGHT_FACE_DOWN)
		updated_input.move_up    ||= rl.IsGamepadButtonDown(gid,    .LEFT_FACE_UP)
		updated_input.move_down  ||= rl.IsGamepadButtonDown(gid,    .LEFT_FACE_DOWN)
		updated_input.move_left  ||= rl.IsGamepadButtonDown(gid,    .LEFT_FACE_LEFT)
		updated_input.move_right ||= rl.IsGamepadButtonDown(gid,    .LEFT_FACE_RIGHT)
		updated_input.move_up    ||= rl.GetGamepadAxisMovement(gid, .LEFT_Y) < -STICK_DEADZONE
		updated_input.move_down  ||= rl.GetGamepadAxisMovement(gid, .LEFT_Y) > STICK_DEADZONE
		updated_input.move_left  ||= rl.GetGamepadAxisMovement(gid, .LEFT_X) < -STICK_DEADZONE
		updated_input.move_right ||= rl.GetGamepadAxisMovement(gid, .LEFT_X) > STICK_DEADZONE
		updated_input.pause      ||= rl.IsGamepadButtonPressed(gid, .MIDDLE_RIGHT)

		updated_input.menu_up    ||= rl.IsGamepadButtonPressed(gid, .LEFT_FACE_UP)
		updated_input.menu_down  ||= rl.IsGamepadButtonPressed(gid, .LEFT_FACE_DOWN)
		updated_input.menu_left  ||= rl.IsGamepadButtonPressed(gid, .LEFT_FACE_LEFT)
		updated_input.menu_right ||= rl.IsGamepadButtonPressed(gid, .LEFT_FACE_RIGHT)
		updated_input.menu_ok    ||= rl.IsGamepadButtonPressed(gid, .RIGHT_FACE_DOWN)
	}

	// mouse
	updated_input.mouse_pos_game   = rl.GetScreenToWorld2D(rl.GetMousePosition(), g_mem.camera)
	// updated_input.mouse_pos_ui     = rl.GetScreenToWorld2D(rl.GetMousePosition(), g_mem.camera_ui)
	updated_input.mouse_delta      +=  rl.GetMouseDelta()
	updated_input.mouse_wheel_move +=  rl.GetMouseWheelMove()

	return updated_input
}

