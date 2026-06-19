// EXPLANATION:
// Related to the player character
//
// `player_update` is where player control is handled

package pitfall

import rl "vendor:raylib"
import "core:math"

Player_State :: enum {
	FALLING,
	STANDING,
	RUNNING,
	JUMPING,
	CLIMBING,
	SWINGING,
}

Player :: struct {
	using entity: Entity,
	velocity: Vec2,

	state: Player_State,

	dir_to_climb: enum { UP, DOWN },

	is_dead,
	did_fall,
	did_sink,
	log_hit,
	can_climb,
	should_climb,
	can_dismount,
	vine_dismounted,
	climb_animate: bool,
}

player_update :: proc(entities: []Entity) {
	dt : f32 = TICK_RATE
	p := &game.player
	prev_direction := p.direction
	prev_state := p.state

	climb_up, climb_down,
	did_run, did_climb,
	on_ground,
	did_dismount_ladder,
	direction_changed: bool

	// Input Start
	// ----------------------------------------------------------------------------

	// walk / horizontal movement
	player_stuck := p.log_hit && .LOG_ROLLING in game.current_level
	if (p.state == .STANDING || p.state == .RUNNING || p.can_dismount) && !player_stuck {
		if input.move_left {
			p.velocity.x = -PLAYER_SPEED*dt
			p.direction = .LEFT
		}
		if input.move_right {
			p.velocity.x = +PLAYER_SPEED*dt
			p.direction = .RIGHT
		}
	}
	did_run = input.move_left || input.move_right

	// restart run animation if turning around
	direction_changed = p.direction != prev_direction
	if prev_state == .RUNNING && did_run && direction_changed {
		set_entity_sprite(p, &game.sprites.player_run)
	}

	// start running
	if did_run && p.state == .STANDING {
		p.state = .RUNNING
	}

	// stop running
	if !did_run && p.state == .RUNNING {
		p.state = .STANDING
	}

	if p.state == .STANDING || p.state == .RUNNING {

		// mount ladder
		if (input.move_up || input.move_down) && check_ladder_climbable() {
			can_climb_up := input.move_up && p.y < GROUND_LOWER_Y && p.y > GROUND_UPPER_Y
			can_climb_down := input.move_down && p.y < GROUND_UPPER_Y
			if can_climb_up || can_climb_down {
				p.can_dismount = false
				p.state = .CLIMBING
				p.velocity = 0
				p.x = game.ladder.x + game.ladder.width/2 - p.width/2

				if p.y < game.ladder.y {
					p.y = game.ladder.y - p.height/2 + CLIMB_INCREMENT
				} else {
					p.y = game.ladder.y + game.ladder.height - game.player.height - CLIMB_INCREMENT
				}
			}
		}

		// jump
		if input.jump && p.state != .CLIMBING && !p.log_hit {
			p.state = .JUMPING
			p.velocity.y = -JUMP_FORCE*dt
		}
	} else if p.state == .CLIMBING {
		// dismount ladder
		if p.can_dismount && (input.move_left || input.move_right) {
			did_dismount_ladder = true
			p.y = game.ladder.y - p.height
			p.state = .JUMPING
			p.velocity.y = -JUMP_FORCE*dt
			p.can_dismount = false
			p.climb_animate = false
		}

		// climb up/down ladder
		if !did_dismount_ladder {
			p.velocity.x = 0

			if input.move_up {
				p.climb_animate = !p.can_dismount
				climb_up = true
			} else if input.move_down {
				p.climb_animate = true
				climb_down = true
			} else {
				p.climb_animate = false
				p.anim_timer = ANIMATE_CLIMB_RATE
			}
		}
	} else if p.state == .SWINGING && input.move_down {
		// dismount vine
		p.state = .JUMPING
		p.vine_dismounted = true
		p.velocity.x = PLAYER_SPEED*f32(p.direction)*dt
		p.velocity.y = 0
	}

	// Input End ------------------------------------------------------------------

	// grab vine
	if !p.vine_dismounted && p.state == .JUMPING && .VINE in game.current_level {
		if rl.CheckCollisionPointRec(game.vine.end, player_extended_hitbox(HITBOX_EXTEND_VINE)) {
			p.state = .SWINGING

			rl.PlaySound(game.sounds.swing)
		}
	}

	// vine swing
	if p.state == .SWINGING {
		p.x = game.vine.end.x - p.width/2 - p.width*2.3*f32(p.direction)
		p.y = game.vine.end.y - p.height/4 + 1
	} else {
		// gravity
		#partial switch (p.state) {
		case: // gravity is applied by default to check collision below the player
			p.velocity.y = GRAVITY*dt

		case .JUMPING:
			p.velocity.y += JUMP_DECAY*dt
			if p.velocity.y > GRAVITY*dt {
				p.velocity.y = GRAVITY*dt
				p.state = .FALLING
			}

		case .SWINGING: // no gravity
		case .CLIMBING:
		}

		// horizontal collision
		p.x += p.velocity.x
		p.log_hit = false
		should_fall_through := player_should_fall_through_ground(entities)

		for &e in entities {
			if did_dismount_ladder { break }
			if e.rec == {} || (e.flags & {.LADDER, .GROUND} != {}) { continue }
			if !rl.CheckCollisionRecs(p, e) { continue }

			// pick up treasure
			if .TREASURE in e.flags {
				e.rec = {}
				e.sprite = nil
				treasure_idx := TOTAL_TREASURES - game.treasures_remaining
				game.treasures_found[treasure_idx] = game.current_seed
				game.treasures_remaining -= 1
				game.score += e.points

				rl.PlaySound(game.sounds.treasure)

				// true winner
				if game.treasures_remaining == 0 {
					game.is_gameover = true
				}
			}

			if .LOG in e.flags { p.log_hit = true }

			if .SOLID in e.flags && !should_fall_through {
				if p.x < e.x {
					p.x = e.x - p.width
				} else {
					p.x = e.x + e.width
				}
			}

			if .KILL in e.flags {
				player_kill()
			}
		}

		// vertical collision
		p.y += p.velocity.y
		should_fall_through |= player_should_fall_through_ground(entities)

		for e in entities {
			if e.rec == {} || (e.flags & {.LADDER, .WALL} != {}) { continue }
			if !rl.CheckCollisionRecs(p, e) { continue }

			if .LOG in e.flags { p.log_hit = true }

			if .CROC in e.flags { should_fall_through = false }

			if .SOLID in e.flags && !should_fall_through {
				if p.y < e.y {
					p.y = e.y - p.height
					on_ground = true
				} else {
					p.y = e.y + e.height
					p.state = .FALLING
				}

				continue
			}

			if .SINK in e.flags {
				if .CROCS not_in game.current_level {
					p.y -= p.velocity.y*0.7 // slow sink in tar & quicksand
				}
				p.did_sink = true
			}
		}

		// post-collision state management
		if p.did_sink && p.y > GROUND_UPPER_Y && p.state != .CLIMBING {
			player_kill()
			p.sprite = nil
		}

		if p.log_hit {
			game.score -= 1
		}

		if should_fall_through {
			p.velocity.x = 0
			if !p.did_fall && !p.did_sink && p.state != .CLIMBING {
				game.score -= 100
				rl.PlaySound(game.sounds.fell)
			}
			p.did_fall = true
		}

		if on_ground {
			p.did_fall = false
			p.did_sink = false
			p.climb_animate = false
			p.vine_dismounted = false
			if input.move_left || input.move_right {
				p.state = .RUNNING
			} else {
				p.state = .STANDING
			}
		} else if p.state == .STANDING || p.state == .RUNNING {
			p.state = .FALLING
		}
		if p.state != .JUMPING { // reset velocity for next frame
			p.velocity = {}
		}

	}

	// hit by log on ladder
	if p.state == .CLIMBING && p.log_hit {
		p.y += CLIMB_INCREMENT
		p.can_dismount = false
		p.log_hit = false
	}

	// set sprite
	did_land := on_ground && (prev_state == .FALLING || prev_state == .JUMPING)
	if p.state != prev_state {
		#partial switch (p.state) {
		case .STANDING: set_entity_sprite(p, &game.sprites.player_stand)
		case .RUNNING:  set_entity_sprite(p, &game.sprites.player_run)
						if did_land do p.current_frame += 1
		case .CLIMBING: set_entity_sprite(p, &game.sprites.player_climb)
						// case .FALLING:  set_entity_sprite(p, &game.sprites.player_jump)
		case .JUMPING:  set_entity_sprite(p, &game.sprites.player_jump)
		case .SWINGING: set_entity_sprite(p, &game.sprites.player_hang)
		}
	}

	if p.state == .RUNNING || p.climb_animate {
		update_entity_animation(p)
		if p.climb_animate && p.sprite_transition {
			if climb_up {
				p.y -= 4
			}
			if climb_down {
				p.y += 4
				p.can_dismount = false
			}
			if climb_up || climb_down { did_climb = true }
		}
	}

	if p.state == .CLIMBING && did_climb {
		// player can dismount at ladder peak
		ladder_overlap := rl.GetCollisionRec(p, game.ladder)
		if ladder_overlap.height <= p.height/2 {
			p.y = game.ladder.y - p.height/2
			p.can_dismount = true
			p.climb_animate = false
			p.anim_timer = ANIMATE_CLIMB_RATE
		}

		at_ladder_bottom := (p.y + p.height == game.ladder.y + game.ladder.height)
		if at_ladder_bottom {
			p.state = .STANDING
			set_entity_sprite(p, &game.sprites.player_stand)
		}
	}

	// jump sound effect
	if (p.state == .JUMPING &&
		prev_state != .JUMPING &&
		prev_state != .SWINGING) {
		rl.PlaySound(game.sounds.jump)
	}

	// log damage sound effect
	sound_playing := rl.IsMusicStreamPlaying(game.sounds.damage)
	if p.log_hit && !sound_playing {
		rl.PlayMusicStream(game.sounds.damage)
	} else if !p.log_hit && sound_playing {
		rl.StopMusicStream(game.sounds.damage)
	}
	if rl.IsMusicStreamPlaying(game.sounds.damage) {
		rl.UpdateMusicStream(game.sounds.damage)
	}

	// screen transition at screen edges
	if p.x < 0 {
		if p.y < GROUND_UPPER_Y {
			to_west_screen()
		} else {
			to_west_screen(3)
		}

		p.x = GAME_WIDTH - p.width - 8
	} else if p.x + p.width > GAME_WIDTH {
		if p.y < GROUND_UPPER_Y {
			to_east_screen()
		} else {
			to_east_screen(3)
		}

		p.x = 0 + p.width + 8
	}
}

player_draw :: proc() {
	if game.player.sprite == nil { return }

	player_rec := game.player.rec
	if game.player.log_hit { player_rec.y += PLAYER_HEIGHT/4 }
	if game.player.current_frame >= len(game.player.sprite.frames) {
		game.player.current_frame = 0
	}

	player_sprite := game.player.sprite.frames[game.player.current_frame]
	if game.player.log_hit {
		player_sprite = game.sprites.player_jump.frames[0]
	}

	rl.DrawTexturePro(
		game.texture_atlas,
		{
			player_sprite.x, player_sprite.y,
			f32(player_sprite.width)*f32(game.player.direction),
			f32(player_sprite.height),
		},
		{
			player_rec.x + game.player.width/2,
			player_rec.y + game.player.height/2 + 2,
			f32(player_sprite.width),
			f32(player_sprite.height),
		},
		{ f32(player_sprite.width)/2, f32(player_sprite.width)/2 }, 0, rl.WHITE,
	)

	if game.is_debug == true {
		if game.player.state == .JUMPING {
			rl.DrawRectangleRec(player_extended_hitbox(HITBOX_EXTEND_VINE), rl.ColorAlpha(rl.ORANGE, 0.3))
		} else {
			rl.DrawRectangleRec(player_extended_hitbox(HITBOX_EXTEND_LADDER), rl.ColorAlpha(rl.ORANGE, 0.3))
		}
		rl.DrawRectangleRec(player_rec, rl.ColorAlpha(rl.RED, 0.3))
	}
}

player_kill :: proc() {
	game.player.is_dead = true
	game.lives -= 1
	game.death_timer = 3.0

	if rl.IsSoundPlaying(game.sounds.swing) {
		rl.StopSound(game.sounds.swing)
	}
	rl.PlaySound(game.sounds.death)
}

player_respawn :: proc() {
	// spawn position
	if game.player.y < GROUND_UPPER_Y + game.player.height {
		game.player.y = game.respawn_point.y
	} else {
		game.player.y = GROUND_LOWER_Y - game.player.height
	}
	game.player.x = game.respawn_point.x

	// set sprite
	game.player.state = .STANDING
	set_entity_sprite(&game.player, &game.sprites.player_stand)

	// reset state
	game.player.is_dead = false
	game.player.did_fall = false
	game.player.did_sink = false
	if game.scorpion != nil {
		game.scorpion.x = (GAME_WIDTH - SCORPION_SIZE)/2
	}
}

check_ladder_climbable :: proc() -> bool {
	if game.ladder == nil { return false }
	return rl.CheckCollisionRecs(player_extended_hitbox(HITBOX_EXTEND_LADDER), game.ladder)
}

player_extended_hitbox :: proc(extend: f32) -> rl.Rectangle {
	return {
		game.player.x - extend,
		game.player.y,
		game.player.width + extend*2,
		game.player.height + 1,
	}
}

player_should_fall_through_ground :: proc(entities: []Entity) -> bool {
	for e in entities {
		if e.flags & {.HOLE, .SINK} != {} {
			collision := rl.GetCollisionRec(game.player, e)
			if math.abs(collision.width - game.player.width) <= math.F16_EPSILON {
				return true
			}
		}
	}

	return false
}
