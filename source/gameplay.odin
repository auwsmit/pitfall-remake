// EXPLANATION:
// This is the primary code for Pitfall's gameplay
//
// See game.odin for the primary application loop

package pitfall

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"

Gameplay_State :: struct {
	time_accumulator : f32, // used for fixed timestep
	camera_zoom      : f32,
	camera_target    : Vec2,

	current_seed     : u8,
	current_level    : Level_Flags,
	screen_number    : u8,

	entities         : [16]Entity,
	entity_count     : int,

	ladder, pit,
	scorpion         : ^Entity,

	// player and vine are not part of the entities array
	player          : Player,
	vine            : Vine,

	lives           : int,
	score           : int,
	time_remaining  : f32,
	death_timer     : f32,
	respawn_point   : Vec2,

	treasures_found : [TOTAL_TREASURES]u8,
	treasures_remaining : int,

	croc_timer      : f32,
	crocs_open      : bool,

	pit_timer,
	pit_shift_timer : f32,
	pit_shrunk,
	pit_is_shifting : bool,

	is_debug        : bool,
	is_paused       : bool,
	is_gameover     : bool,

	// used to render the vine and pit at lower resolution, so they match the rest of the art
	lowres_vine,
	lowres_pit,
	lowres_pit_cover : rl.RenderTexture,

	// assets
	texture_atlas    : rl.Texture,

	sprites: struct {
		background, foreground_a, foreground_b,

		canopy,
		canopy_a, canopy_b, canopy_c, canopy_d,

		trees,
		trees_a, trees_b, trees_c, trees_d,

		player_run,
		player_jump,
		player_hang,
		player_climb,
		player_stand,

		log_static,
		log_roll,

		ladder,
		wall,

		money, silver, gold, ring,

		fire,
		snake,
		scorpion,

		croc_open,
		croc_close: Sprite,
	},

	sounds: struct {
		jump,
		fell,
		swing,
		death,
		treasure: rl.Sound,

		// damage needs to be Music because Sound doesn't have a seamless loop
		damage: rl.Music,
	},
}

gameplay_init :: proc() {
	game = &g_mem.game

	game^ = {}
	game.is_debug = false

	game.current_seed = INITIAL_SEED
	game.screen_number = 1
	game.treasures_remaining = TOTAL_TREASURES

	game.vine.start = {GAME_WIDTH/2, 5}

	game.vine.angle = 90
	game.vine.swing_speed = VINE_SPEED
	game.vine.swing_inc = VINE_DECAY
	game.vine.direction = .LEFT

	game.pit_timer = PIT_WAIT_TIME
	game.pit_shift_timer = PIT_SHIFT_TIME

	game.lowres_pit = rl.LoadRenderTexture(GAME_WIDTH, GAME_HEIGHT)
	game.lowres_vine = rl.LoadRenderTexture(GAME_WIDTH, GAME_HEIGHT)

	game.lives = 5
	game.score = 2000
	game.time_remaining = 20 * 60
	game.respawn_point = {GAME_WIDTH/8, GROUND_UPPER_Y - PLAYER_HEIGHT}
	game.player.rec = {
		game.respawn_point.x, game.respawn_point.y,
		PLAYER_WIDTH, PLAYER_HEIGHT,
	}
	game.player.direction = .RIGHT
	game.player.sprite = &game.sprites.player_stand

	// assets
	game.texture_atlas   = rl.LoadTexture("assets/atlas.png")
	game.sounds.jump     = rl.LoadSound("assets/jump.wav")
	game.sounds.fell     = rl.LoadSound("assets/fell.wav")
	game.sounds.swing    = rl.LoadSound("assets/swing.wav")
	game.sounds.death    = rl.LoadSound("assets/death.wav")
	game.sounds.treasure = rl.LoadSound("assets/treasure.wav")
	game.sounds.damage   = rl.LoadMusicStream("assets/damage.wav")

	// map sprites to texture atlas
	init_spritesheet()

	generate_level(game.current_seed)
}

gameplay_shutdown :: proc() {
	rl.UnloadTexture(game.texture_atlas)
	rl.UnloadSound(game.sounds.jump)
	rl.UnloadSound(game.sounds.swing)
	rl.UnloadMusicStream(game.sounds.damage)
	game^ = {}
}

gameplay_update :: proc() {
	// debug: reset
	if rl.IsKeyPressed(.R) {
		gameplay_shutdown()
		gameplay_init()
	}

	// debug: random level
	if rl.IsKeyDown(.LEFT_SHIFT) && rl.IsKeyPressed(.SLASH) {
		to_east_screen(int(rand.int32_range(1, 254)))
	}

	// debug: transition level
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		to_east_screen()
	}
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		to_west_screen()
	}

	// debug: kill player
	if rl.IsKeyPressed(.K) {
		player_kill()
	}

	if did_tick {
		input = {} // clear previous tick input
		did_tick = false
	}
	input = get_input(input) // accumulates input for next tick

	if input.pause {
		input = {}
		game.is_paused = !game.is_paused
		menu_selected_id = 0
	}

	if !game.is_paused {

		game.time_accumulator += frame_time
		tick_rate: f32 = TICK_RATE

		// debug: speed up and slow down
		if rl.IsKeyDown(.COMMA) { tick_rate *= 2 }
		if rl.IsKeyDown(.PERIOD) { tick_rate /= 2 }

		for game.time_accumulator >= tick_rate {
			tick(game.entities[:game.entity_count])
			game.time_accumulator -= tick_rate
		}
	}
}


did_tick: bool

tick :: proc(entities: []Entity) {
	dt : f32 = TICK_RATE
	did_tick = true

	if game.lives == 0 {
		game.is_gameover = true
	}

	if game.is_gameover {
		if !rl.IsSoundPlaying(game.sounds.death) && input.menu_ok {
			gameplay_shutdown()
			gameplay_init()
		}
		return
	}

	if game.player.is_dead {
		if timer_countdown(&game.death_timer, 0, dt) {
			player_respawn()
		}

		return
	}

	timer_countdown(&game.time_remaining, 0, dt)

	// shifting pit
	if !game.pit_is_shifting && timer_countdown(&game.pit_timer, PIT_WAIT_TIME, dt) {
		game.pit_is_shifting = true
	}

	if game.pit_is_shifting {
		if timer_countdown(&game.pit_shift_timer, PIT_SHIFT_TIME, dt) {
			game.pit_is_shifting = false
			game.pit_shrunk = !game.pit_shrunk
		}

		// grow or shrink pit
		if .PIT_SHIFTING in game.current_level {
			collision := rl.GetCollisionRec(game.player, game.pit)
			player_sunk := math.abs(collision.width - game.player.width) <= math.F16_EPSILON
			if player_sunk {
				game.pit_shift_timer += dt
			}

			if game.pit_shrunk {
				game.pit.width = PIT_WIDTH*(PIT_SHIFT_TIME - game.pit_shift_timer)/PIT_SHIFT_TIME
				game.pit.height = GROUND_HEIGHT*(PIT_SHIFT_TIME - game.pit_shift_timer)/PIT_SHIFT_TIME
			} else {
				game.pit.width = PIT_WIDTH*game.pit_shift_timer/PIT_SHIFT_TIME
				game.pit.height = GROUND_HEIGHT*game.pit_shift_timer/PIT_SHIFT_TIME
			}
			game.pit.x = GAME_WIDTH/2 - game.pit.width/2
		}
	}

	// update animations
	for &e in entities {
		if e.sprite == nil { continue }
		if e.sprite.active == false { continue }
		if .CROC in e.flags { continue } // crocs have a global animation timer

		update_entity_animation(&e)
	}

	// update crocs
	if timer_countdown(&game.croc_timer, ANIMATE_CROC_RATE, dt) {
		game.crocs_open = !game.crocs_open
		for &e in entities {
			if .CROC in e.flags {
				if game.crocs_open {
					set_entity_sprite(&e, &game.sprites.croc_open)
					e.rec = e.croc_head
				} else {
					set_entity_sprite(&e, &game.sprites.croc_close)
					e.rec = e.croc_full
				}
			}
		}
	}

	// update logs
	for &e in entities {
		if .LOG in e.flags {
			e.x -= e.speed*dt
			if e.x < -LOG_SIZE { e.x = GAME_WIDTH }
		}
	}

	// update scorpion
	if game.scorpion != nil {
		distance_from_player := abs((game.player.x + game.player.width/2) -
								  (game.scorpion.x + game.scorpion.width/2))
		if distance_from_player <= game.player.width*2 {
			// stop animating scorpion by adding to the timer
			game.scorpion.anim_timer += dt
		} else if game.scorpion.sprite_transition {
			// stepping movement
			if game.player.x < game.scorpion.x {
				game.scorpion.direction = .LEFT
				game.scorpion.x -= 1
			} else {
				game.scorpion.direction = .RIGHT
				game.scorpion.x += 1
			}
		}
	}

	// update vine
	vine := &game.vine
	vine.angle += vine.swing_speed*f32(vine.direction)*dt

	vine.swing_speed -= vine.swing_inc*f32(vine.direction)
	if vine.swing_speed <= 0 {
		vine.direction = -vine.direction
	}

	if vine.swing_speed >= VINE_SPEED {
		vine.swing_inc = -vine.swing_inc
	}
	vine.angle = math.mod(vine.angle, 360)
	r := vine.angle*rl.DEG2RAD
	vine.end = {
		vine.start.x + math.cos(r)*VINE_LENGTH,
		vine.start.y + math.sin(r)*VINE_LENGTH*0.20 + 57,
	}

	// player input, movement, and collision
	player_update(entities)

	if game.score < 0 { game.score = 0 }

	// update lowres vine texture
	if .VINE in game.current_level {
		rl.BeginTextureMode(game.lowres_vine)
		rl.ClearBackground(rl.BLANK)
		rl.DrawLineEx(game.vine.start, game.vine.end, 2, rl.LIME)
		rl.EndTextureMode()
	}

	// update lowres pit texture
	if game.pit != nil {
		center := get_rectangle_center(game.pit.rec)
		rl.BeginTextureMode(game.lowres_pit)
		rl.ClearBackground(rl.BLANK)
		rl.DrawEllipse(
			i32(center.x), i32(center.y - (GROUND_HEIGHT/2 + game.pit.height/2 - 5)),
			game.pit.width/2, game.pit.height + 1, game.pit.color,
		)
		rl.EndTextureMode()
	}

	// // camera controls
	// if (input.mouse_wheel_move != 0) {
	// 	game.camera_zoom += input.mouse_wheel_move*0.1
	// 	game.camera_zoom = math.clamp(game.camera_zoom, -0.9, 2)
	// }
	// if (rl.Vector2Length(input.mouse_delta) > 0) && rl.IsMouseButtonDown(.RIGHT) {
	// 	game.camera_target += input.mouse_delta/(g_mem.viewport.scale*g_mem.camera_game.zoom)
	// }
}

gameplay_draw :: proc() {
	has_holes := game.current_level & {.HOLE_SIDES, .HOLE_LADDER} != {}
	rl.ClearBackground(rl.DARKGREEN)

	// background layer (ground/sky, trees)
	draw_sprite(game.sprites.background)
	draw_sprite(game.sprites.trees)

	// draw entities (excluding logs and crocs)
	for &e in game.entities[:game.entity_count] {
		if .LOG not_in e.flags && .CROC not_in e.flags {
			draw_entity_sprite(&e)
		}
	}

	// draw player beneath foreground
	if (game.player.state == .CLIMBING ||
		game.player.state == .FALLING ||
		game.player.state == .JUMPING) {
		player_draw()
	}

	// foreground layers
	draw_sprite(game.sprites.foreground_a)
	if game.pit != nil {
		rl.DrawTextureRec(game.lowres_pit.texture, {0, 42, 256, -8}, {0, 94}, rl.WHITE)
		draw_sprite(game.sprites.foreground_b)
	}

	// draw logs and crocs
	for &e in game.entities[:game.entity_count] {
		if .LOG in e.flags || .CROC in e.flags {
			draw_entity_sprite(&e)
		}
	}

	// draw player above foreground
	if (game.player.state != .CLIMBING &&
		game.player.state != .FALLING &&
		game.player.state != .JUMPING) {
		player_draw()
	}

	// draw vine and forest canopy
	if .VINE in game.current_level {
		draw_texture_flipped(game.lowres_vine.texture)
	}
	draw_sprite(game.sprites.canopy)

	// draw UI
	// ----------------------------------------------------------------------------
	if game.is_gameover {
		if game.treasures_remaining == 0 {
			draw_text_aligned("YOU WIN", size = 10)
		} else {
			draw_text_aligned("GAME OVER", size = 10)
		}
	}

	life_x: f32 = 15
	life_size :: 5
	for _ in 0..<game.lives {
		rl.DrawRectangleRec({life_x, 5, life_size, life_size}, rl.WHITE)
		life_x += life_size + 3
	}
	draw_text_aligned(rl.TextFormat("Score %i", game.score),
		halign = .LEFT, valign = .TOP, offset = {8, 15}, size = 10)
	draw_text_aligned(rl.TextFormat("Screen #%i", game.screen_number),
		valign = .TOP, offset = {0, 3}, size = 10)
	draw_text_aligned(rl.TextFormat("Treasure %i/%i", TOTAL_TREASURES - game.treasures_remaining, TOTAL_TREASURES),
		valign = .TOP, offset = {0, 15}, size = 10)
	draw_text_aligned(rl.TextFormat("Time %i:%2i", int(game.time_remaining / 60), int(game.time_remaining) % 60),
		halign = .RIGHT, valign = .TOP, offset = {-8, 15}, size = 10)

	// draw pause menu
	// ----------------------------------------------------------------------------
	if game.is_paused {
		// transparent overlay
		rl.DrawRectangleRec({0, 0, GAME_WIDTH, GAME_HEIGHT}, rl.Color{0, 0, 0, 100})

		draw_text_aligned("PAUSED", offset = {0, -45}, size = 20)

		// pause menu
		if draw_menu_button("Resume", menu_pause, first_item = true) {
			game.is_paused = !game.is_paused
		}
		if draw_menu_button("Restart", menu_pause) {
			gameplay_shutdown()
			gameplay_init()
		}
		if draw_menu_button("Fullscreen", menu_pause) {
			rl.ToggleBorderlessWindowed()
		}

		volume := rl.GetMasterVolume()
		if draw_menu_slider("Volume", menu_pause, &volume, min = 0.1, max = 1, increment = 0.05) {
			if !rl.IsSoundPlaying(game.sounds.jump) {
				rl.PlaySound(game.sounds.jump)
			}
		}
		rl.SetMasterVolume(volume)

		when !ODIN_BUILD_WEB {
			if draw_menu_button("Exit", menu_pause) {
				g_mem.should_close = true
			}
		}

		input = {}
	}

	draw_debug_text()
}

// menu_slider_timer: f32

draw_debug_text :: proc() {
	// Debug
	if game.is_debug {
		print_debug("FPS: %v", rl.GetFPS(), first_line = true)
		print_debug("state: %v", game.player.state)
		// print_debug("can climb: %v", game.player.can_climb)
		// print_debug("can dismount: %v", game.player.can_dismount)
		// print_debug("climb animate: %v", game.player.climb_animate)
		print_debug("render res: %v, %v", g_mem.viewport.render.texture.width, g_mem.viewport.render.texture.height)
		print_debug("render scale: %v", g_mem.viewport.render_scale)
		print_debug("state: %v", game.player.state)
		// print_debug("velocity: %v", game.player.velocity)
		// print_debug("animate t: %v", game.player.animate_timer)
		// print_debug("level_seed: %b", game.current_seed)
		// print_debug("player y: %v", game.player.y)
		// for _,i in 0..<4 {
		// 	print_debug("controller available: %v", rl.IsGamepadAvailable(i32(i)))
		// }
	}
}
