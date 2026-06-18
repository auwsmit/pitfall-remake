// EXPLANATION:
// Related to sprites and animations

package pitfall

import rl "vendor:raylib"

frames_player_run:   []rl.Rectangle = {
	{1, 50, 16, 16},
	{18, 50, 16, 16},
	{35, 50, 16, 16},
	{52, 50, 16, 16},
	{69, 50, 16, 16},
}
frames_player_climb: []rl.Rectangle = {{62,  1,   16,  16}, {79,  1,  16, 16}}
frames_player_jump:  []rl.Rectangle = {{86,  50,  16,  16}}
frames_player_hang:  []rl.Rectangle = {{96,  1,   16,  16}}
frames_player_stand: []rl.Rectangle = {{103, 50,  16,  16}}
frames_ladder:       []rl.Rectangle = {{1,   1,   8,   48}}
frames_wall:         []rl.Rectangle = {{10,  18,  8,   20}}
frames_croc:         []rl.Rectangle = {{27,  1,   16,  16}, {10,  1,   16,  16}}
frames_log:          []rl.Rectangle = {{44,  1,   8,   16}, {53,  1,  8,  16}}
frames_scorpion:     []rl.Rectangle = {{1,   67,  8,   16}, {10,  67, 8,  16}}
frames_fire:         []rl.Rectangle = {{19,  67,  8,   16}, {37,  67, 8,  16}, {28, 67, 8, 16}}
frames_snake:        []rl.Rectangle = {{46,  67,  8,   16}, {55,  67, 8,  16}}
frames_money:        []rl.Rectangle = {{64,  67,  8,   16}}
frames_ring:         []rl.Rectangle = {{109, 67,  8,   16}}
frames_silver:       []rl.Rectangle = {{73,  67,  8,   16}, {82,  67, 8,  16}}
frames_gold:         []rl.Rectangle = {{91,  67,  8,   16}, {100, 67, 8,  16}}
frames_background:   []rl.Rectangle = {{1,   84,  256, 144}}
frames_foreground_a: []rl.Rectangle = {{258, 84,  256, 144}}
frames_foreground_b: []rl.Rectangle = {{515, 84,  256, 144}}
frames_canopy_a:     []rl.Rectangle = {{1,   229, 256, 144}}
frames_canopy_b:     []rl.Rectangle = {{258, 229, 256, 144}}
frames_canopy_c:     []rl.Rectangle = {{515, 229, 256, 144}}
frames_canopy_d:     []rl.Rectangle = {{772, 229, 256, 144}}
frames_trees_a:      []rl.Rectangle = {{1,   374, 256, 144}}
frames_trees_b:      []rl.Rectangle = {{258, 374, 256, 144}}
frames_trees_c:      []rl.Rectangle = {{515, 374, 256, 144}}
frames_trees_d:      []rl.Rectangle = {{772, 374, 256, 144}}

Sprite :: struct {
	frames: []rl.Rectangle, // slice of recs of the texture atlas
	rate: f32,
	offset: Vec2, // for positioning a potential hitbox
	active: bool,
}

init_spritesheet :: proc() {
	game.sprites.player_run = set_sprite_animated(frames_player_run[:], ANIMATE_RUN_RATE)
	game.sprites.player_climb = set_sprite_animated(frames_player_climb[:], ANIMATE_CLIMB_RATE)
	game.sprites.player_jump   = set_sprite(frames_player_jump[:])
	game.sprites.player_hang   = set_sprite(frames_player_hang[:])
	game.sprites.player_stand  = set_sprite(frames_player_stand[:])

	game.sprites.ladder        = set_sprite(frames_ladder[:])
	game.sprites.wall          = set_sprite(frames_wall[:])

	game.sprites.croc_open     = set_sprite(frames_croc[:1], {12, 9}) // offsets for changed hitbox size
	game.sprites.croc_close    = set_sprite(frames_croc[1:], {0, 9})

	game.sprites.log_static    = set_sprite(frames_log[:1])
	game.sprites.log_roll      = set_sprite_animated(frames_log[:], ANIMATE_LOG_ROLL_RATE)

	// when sprite is taller than entity (so the hitbox is at the bottom of the sprite)
	tall_offset               := Vec2{0, 8}
	game.sprites.scorpion      = set_sprite_animated(frames_scorpion[:], ANIMATE_SCORPION_RATE, {0, 6})
	game.sprites.fire          = set_sprite_animated(frames_fire[:], ANIMATE_HAZARD_RATE, tall_offset)
	game.sprites.snake         = set_sprite_animated(frames_snake[:], ANIMATE_HAZARD_RATE, tall_offset)

	game.sprites.money         = set_sprite(frames_money[:], tall_offset)
	game.sprites.ring          = set_sprite(frames_ring[:], tall_offset)
	game.sprites.silver        = set_sprite_animated(frames_silver[:], ANIMATE_TREASURE_RATE, tall_offset)
	game.sprites.gold          = set_sprite_animated(frames_gold[:], ANIMATE_TREASURE_RATE, tall_offset)

	game.sprites.background    = set_sprite(frames_background[:])
	game.sprites.foreground_a  = set_sprite(frames_foreground_a[:])
	game.sprites.foreground_b  = set_sprite(frames_foreground_b[:])
	game.sprites.canopy_a      = set_sprite(frames_canopy_a[:])
	game.sprites.canopy_b      = set_sprite(frames_canopy_b[:])
	game.sprites.canopy_c      = set_sprite(frames_canopy_c[:])
	game.sprites.canopy_d      = set_sprite(frames_canopy_d[:])
	game.sprites.trees_a       = set_sprite(frames_trees_a[:])
	game.sprites.trees_b       = set_sprite(frames_trees_b[:])
	game.sprites.trees_c       = set_sprite(frames_trees_c[:])
	game.sprites.trees_d       = set_sprite(frames_trees_d[:])
}

set_sprite :: proc(
	sprite: []rl.Rectangle,
	offset: Vec2 = {0, 0},
) -> Sprite {
	return {sprite, 0, offset, false}
}

set_sprite_animated :: proc(
	sprites: []rl.Rectangle,
	rate: f32,
	offset: Vec2 = {0, 0},
	animated := true,
) -> Sprite {
	return {sprites, rate, offset, animated}
}

set_entity_sprite :: proc(e: ^Entity, a: ^Sprite, frame := 0) {
	e.sprite = a
	e.current_frame = frame
	e.anim_timer = a.rate
}

update_entity_animation :: proc(e: ^Entity) {
	if len(e.sprite.frames) < 2 { return }

	if timer_countdown(&e.anim_timer, e.sprite.rate, TICK_RATE) {
		e.current_frame += 1

		if e.current_frame >= len(e.sprite.frames) {
			e.current_frame = 0
		}

		e.sprite_transition = true
		return
	}

	e.sprite_transition = false
}

draw_sprite :: proc(sprite: Sprite) {
	rl.DrawTextureRec(game.texture_atlas, sprite.frames[0], {}, rl.WHITE)
}

draw_entity_sprite :: proc(e: ^Entity) {
	if e.sprite != nil {
		s := e.sprite.frames[e.current_frame]
		rl.DrawTexturePro(
			game.texture_atlas,
			{s.x, s.y, f32(s.width)*f32(e.direction), f32(s.height)},
			{e.x, e.y, f32(s.width), f32(s.height)},
			e.sprite.offset, 0, rl.WHITE,
		)
	} else { // no sprite
		if e == game.pit {
			draw_texture_flipped(game.lowres_pit.texture)
		} else {
			rl.DrawRectangleRec(e.rec, e.color)
		}
	}

	if game.is_debug {
		rl.DrawRectangleRec(e.rec, rl.ColorAlpha(rl.WHITE, 0.3))
	}
}
