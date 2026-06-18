// EXPLANATION:
// See game.odin for the primary application loop
// Level generator: Uses an 8 bit seed with the LSFR (linear-feedback shift register)
// method in order to procedurally generate 255 levels. This method is identical to
// the original Atari 2600 Pitfall, so all levels in this remake have the same layout as the original.

package pitfall

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/rand"

Entity_Flag :: enum {
	SOLID, HOLE,
	GROUND, WALL,
	KILL, SINK,
	LADDER, LOG,
	CROC, TREASURE,
	SCORPION,
}
Entity_Flags :: bit_set[Entity_Flag; u16] // attributes for an entity

Entity :: struct { // basic entity
	using rec : rl.Rectangle,

	sprite            : ^Sprite,
	sprite_transition : bool,
	current_frame     : int,
	draw_layer        : int,
	anim_timer        : f32,

	direction : enum { LEFT = -1, RIGHT = 1 },
	speed     : f32,

	points    : int, // for treasure
	croc_head,
	croc_full : rl.Rectangle,

	color     : rl.Color,
	flags     : Entity_Flags,
}

Vine :: struct {
	start, end : Vec2,
	direction  : enum { LEFT = 1, RIGHT = -1 },

	swing_speed,
	swing_inc,
	angle, timer : f32,
}

Level_Flag :: enum {
	HOLE_LADDER, HOLE_SIDES, VINE,
	PIT_TAR, PIT_SAND, PIT_SHIFTING, CROCS,
	LOG_ONE, LOG_TWO_CLOSE, LOG_TWO_FAR, LOG_THREE, LOG_ROLLING,
	TREASURE, FIRE, SNAKE,
}
Level_Flags :: bit_set[Level_Flag; u32] // contents of a single screen/level

// calculate the next level with an lsfr operation
next_level_bits :: proc(n: u8) -> u8 {
	// parity of bits 3, 4, 5, 7
	fb := (n >> 3 ~ n >> 4 ~ n >> 5 ~ n >> 7) & 1

	game.screen_number += 1
	if game.screen_number == 0 { game.screen_number = 1 }

	return (n << 1) | fb
}

// calculate the previous level with an lsfr operation
prev_level_bits :: proc(n: u8) -> u8 {
	// parity of bits 0, 4, 5, 6
	fb := (n >> 0 ~ n >> 4 ~ n >> 5 ~ n >> 6) & 1

	game.screen_number -= 1
	if game.screen_number == 0 { game.screen_number = 255 }

	return (n >> 1) | (fb << 7)
}

// accurately creates the same 255 levels as pitfall
// credit to this blogpost for very helpful info:
// --> https://evoniuk.github.io/posts/pitfall.html
generate_level :: proc(seed: u8) {
	// clear previous level
	game.entity_count = 0
	game.ladder = nil
	game.pit = nil
	game.scorpion = nil

	config: Level_Flags
	treasure_flag: enum {NONE, MONEY, SILVER, GOLD, RING}

	item_bits := seed & 7                  // Bits 0-2 (0000 0111)
	pit_bits  := (seed >> 3) & 7           // Bits 3-5 (0011 1000)
	tree_bits := (seed >> 6) & 3           // Bits 6-7 (1100 0000)
	wall_side : enum {LEFT = 0, RIGHT = 1} // Bit 7    (1000 0000)

	wall_side = (seed & 128 == 0) ? .LEFT : .RIGHT
	has_crocs := (pit_bits == 4)
	has_treasure := (pit_bits == 5)

	fmt.printfln("\nScreen: %v", game.screen_number)
	fmt.printfln("Seed: %8b", seed)

	if has_crocs {
		switch item_bits {
		case 2, 3, 6, 7:
			config += {.VINE}
		}
	}

	if has_treasure {
		switch item_bits {
		case 0, 4:
			config += {.TREASURE}
			treasure_flag = .MONEY
		case 1, 5:
			config += {.TREASURE}
			treasure_flag = .SILVER
		case 2, 6:
			config += {.TREASURE}
			treasure_flag = .GOLD
		case 3, 7:
			config += {.TREASURE}
			treasure_flag = .RING
		}
		fmt.printfln("Treasure: %v", treasure_flag)
	}

	if !has_crocs && !has_treasure {
		switch item_bits {
		case 0: config += {.LOG_ONE, .LOG_ROLLING}
				fmt.printfln("One log rolling")

		case 1: config += {.LOG_TWO_CLOSE, .LOG_ROLLING}
				fmt.printfln("Two logs (close) rolling")

		case 2: config += {.LOG_TWO_FAR, .LOG_ROLLING}
				fmt.printfln("Two logs (far) rolling")

		case 3: config += {.LOG_THREE, .LOG_ROLLING}
				fmt.printfln("Three logs rolling")

		case 4: config += {.LOG_ONE}
				fmt.printfln("One log still")

		case 5: config += {.LOG_THREE}
				fmt.printfln("Three logs still")

		case 6: config += {.FIRE}
				fmt.printfln("Fire")

		case 7: config += {.SNAKE}
				fmt.printfln("Snake")
		}
	}

	switch pit_bits {
	case 0: config += {.HOLE_LADDER}
			fmt.printfln("One hole")

	case 1: config += {.HOLE_LADDER, .HOLE_SIDES}
			fmt.printfln("Three holes")

	case 2: config += {.PIT_TAR, .VINE}
			fmt.printfln("Tar pit")

	case 3: config += {.PIT_SAND, .VINE}
			fmt.printfln("Quicksand")

	case 4: config += {.CROCS}
			fmt.printfln("Crocs")

	case 5: config += {.PIT_TAR, .PIT_SHIFTING}
			fmt.printfln("Shifting tar pit")

	case 6: config += {.PIT_SAND, .PIT_SHIFTING, .VINE}
			fmt.printfln("Shifting quicksand pit")

	case 7: config += {.PIT_SAND, .PIT_SHIFTING}
			fmt.printfln("Shifting quicksand")
	}

	switch tree_bits {
	case 0: game.sprites.trees  = game.sprites.trees_a
			game.sprites.canopy = game.sprites.canopy_a
	case 1: game.sprites.trees  = game.sprites.trees_b
			game.sprites.canopy = game.sprites.canopy_b
	case 2: game.sprites.trees  = game.sprites.trees_c
			game.sprites.canopy = game.sprites.canopy_c
	case 3: game.sprites.trees  = game.sprites.trees_d
			game.sprites.canopy = game.sprites.canopy_d
	}
	fmt.printfln("Tree pattern: %i", tree_bits)

	if .VINE in config {
		fmt.printfln("Vine")
	}
	if config & {.HOLE_SIDES, .HOLE_LADDER} == {} {
		fmt.printfln("Scorpion")
	}
	if .HOLE_LADDER in config {
		fmt.printfln("Wall %s side", bool(wall_side)? "right" : "left")
	}

	fmt.printfln("")

	game.current_level = config

	// ground
	ground_upper := create_entity({.SOLID, .GROUND})
	ground_upper.rec = {0, GROUND_UPPER_Y, GAME_WIDTH, GROUND_HEIGHT}
	// ground_upper.color = rl.LIME

	ground_lower := create_entity({.SOLID, .GROUND})
	ground_lower.rec = {0, GROUND_LOWER_Y, GAME_WIDTH, GROUND_HEIGHT}
	// ground_lower.color = rl.GREEN

	// side holes
	if .HOLE_SIDES in config {
		hole_left := create_entity({.HOLE})
		hole_right := create_entity({.HOLE})
		hole_left.rec = {
			GAME_WIDTH/3.2 - HOLE_WIDTH/2, GROUND_UPPER_Y,
			HOLE_WIDTH, HOLE_HEIGHT,
		}
		hole_right.rec = {
			GAME_WIDTH - GAME_WIDTH/3.2 - HOLE_WIDTH/2, GROUND_UPPER_Y,
			HOLE_WIDTH, HOLE_HEIGHT,
		}
		hole_left.color = rl.BLACK
		hole_right.color = rl.BLACK
	}

	// center hole with ladder
	if .HOLE_LADDER in config {
		CENTER_HOLE_WIDTH :: LADDER_WIDTH+6
		hole_center := create_entity({.HOLE})
		hole_center.rec = {
			GAME_WIDTH/2 - CENTER_HOLE_WIDTH/2, GROUND_UPPER_Y,
			CENTER_HOLE_WIDTH, HOLE_HEIGHT,
		}
		hole_center.color = rl.BLACK

		ladder := create_entity({.LADDER})
		ladder.rec = {
			GAME_WIDTH/2 - LADDER_WIDTH/2, GROUND_UPPER_Y,
			LADDER_WIDTH, LADDER_HEIGHT,
		}
		ladder.sprite = &game.sprites.ladder
		game.ladder = ladder

		wall := create_entity({.SOLID, .WALL})
		wall.rec = {
			(GAME_WIDTH - WALL_WIDTH*5)*f32(wall_side)+WALL_WIDTH*2,
			GROUND_LOWER_Y - WALL_HEIGHT,
			WALL_WIDTH, WALL_HEIGHT,
		}
		wall.sprite = &game.sprites.wall
		wall.color = rl.MAROON
	}

	// scorpion
	if config & {.HOLE_SIDES, .HOLE_LADDER} == {} {
		scorpion := create_entity({.KILL})
		scorpion.rec = {
			(GAME_WIDTH - SCORPION_SIZE)/2,
			GROUND_LOWER_Y - 9,
			SCORPION_SIZE, SCORPION_SIZE,
		}
		scorpion.sprite = &game.sprites.scorpion
		game.scorpion = scorpion
	}

	// pits
	if config & {.PIT_TAR, .PIT_SAND} != {} {
		pit := create_entity({.SINK})
		pit.rec = {
			GAME_WIDTH/2 - PIT_WIDTH/2, GROUND_UPPER_Y,
			PIT_WIDTH, GROUND_HEIGHT,
		}
		if .PIT_TAR in config { pit.color = rl.BLACK }
		if .PIT_SAND in config { pit.color = rl.ColorBrightness(rl.BROWN, 0) }
		game.pit = pit
	}
	if .PIT_SHIFTING in config {
		if game.pit_shrunk {
			game.pit.width = PIT_WIDTH*(PIT_SHIFT_TIME - game.pit_shift_timer)/PIT_SHIFT_TIME
		} else {
			game.pit.width = PIT_WIDTH*game.pit_shift_timer/PIT_SHIFT_TIME
		}
		game.pit.x = GAME_WIDTH/2 - game.pit.width/2
	}


	if .CROCS in config {
		water := create_entity({.SINK})
		water.rec = {
			GAME_WIDTH/2 - PIT_WIDTH/2, GROUND_UPPER_Y,
			PIT_WIDTH, GROUND_HEIGHT,
		}
		water.color = rl.BLUE
		game.pit = water

		// crocs
		croc_sprite := game.crocs_open ? &game.sprites.croc_open : &game.sprites.croc_close

		croc_left := create_entity({.CROC, .SOLID})
		croc_left.croc_full = {
			GAME_WIDTH/2 - CROC_WIDTH*2.5, GROUND_UPPER_Y,
			CROC_WIDTH, GROUND_HEIGHT/2,
		}
		croc_left.croc_head = get_croc_head_rec(croc_left.croc_full)
		croc_left.rec = game.crocs_open ? croc_left.croc_head : croc_left.croc_full
		croc_left.sprite = croc_sprite

		croc_middle := create_entity({.CROC, .SOLID})
		croc_middle.croc_full = {
			GAME_WIDTH/2 - CROC_WIDTH/2, GROUND_UPPER_Y,
			CROC_WIDTH, GROUND_HEIGHT/2,
		}
		croc_middle.croc_head = get_croc_head_rec(croc_middle.croc_full)
		croc_middle.rec = game.crocs_open ? croc_middle.croc_head : croc_middle.croc_full
		croc_middle.sprite = croc_sprite

		croc_right := create_entity({.CROC, .SOLID})
		croc_right.croc_full = {
			GAME_WIDTH/2 + CROC_WIDTH*1.5, GROUND_UPPER_Y,
			CROC_WIDTH, GROUND_HEIGHT/2,
		}
		croc_right.croc_head = get_croc_head_rec(croc_right.croc_full)
		croc_right.rec = game.crocs_open ? croc_right.croc_head : croc_right.croc_full
		croc_right.sprite = croc_sprite
	}

	// near right edge of screen
	spawn_start_x: f32 = GAME_WIDTH - GAME_WIDTH/7

	// logs
	if config & {.LOG_ONE, .LOG_TWO_CLOSE, .LOG_TWO_FAR, .LOG_THREE} != {} {
		log_amount: int
		if .LOG_ONE in config {
			log_amount = 1
		} else if config & {.LOG_TWO_CLOSE, .LOG_TWO_FAR} != {} {
			log_amount = 2
		} else {
			log_amount = 3
		}

		spacing: f32
		if config & {.LOG_TWO_FAR, .LOG_THREE} != {} {
			spacing = 50
		} else {
			spacing = 20
		}

		log_x: f32 = spawn_start_x - LOG_SIZE/2
		offset_x: [3]f32
		if .LOG_THREE in config && .LOG_ROLLING not_in config {
			offset_x = {35, 45, -65}
		}
		speed: f32 = (.LOG_ROLLING in config) ? PLAYER_SPEED : 0
		for i in 1..=log_amount {
			log := create_entity({.LOG})
			log.rec = {
				log_x + offset_x[i-1], GROUND_UPPER_Y - 5,
				LOG_SIZE, LOG_SIZE,
			}
			if .LOG_ROLLING in config {
				log.sprite = &game.sprites.log_roll
			} else {
				log.sprite = &game.sprites.log_static
			}
			log.draw_layer = 1
			log_x -= LOG_SIZE+spacing
			log.speed = speed
		}
	}

	if .FIRE in config {
		fire := create_entity({.KILL})
		fire.rec = {
			spawn_start_x - TREASURE_SIZE/2,
			GROUND_UPPER_Y - FIRE_SIZE/2,
			FIRE_SIZE, FIRE_SIZE,
		}
		fire.sprite = &game.sprites.fire
	}

	if .SNAKE in config {
		snake := create_entity({.KILL})
		snake.rec = {
			spawn_start_x - TREASURE_SIZE/2,
			GROUND_UPPER_Y - SNAKE_SIZE/2,
			SNAKE_SIZE, SNAKE_SIZE,
		}
		snake.sprite = &game.sprites.snake
	}

	if .TREASURE in config {
		for tr in game.treasures_found {
			if tr == seed { treasure_flag = .NONE }
		}
		treasure := create_entity({.TREASURE})
		treasure.rec = {
			spawn_start_x - TREASURE_SIZE/2,
			GROUND_UPPER_Y - TREASURE_SIZE/2,
			TREASURE_SIZE, TREASURE_SIZE,
		}
		switch treasure_flag {
		case .NONE: treasure.rec = {}
		case .MONEY: treasure.sprite = &game.sprites.money
					 treasure.points = 2000
		case .SILVER: treasure.sprite = &game.sprites.silver
					  treasure.points = 3000
		case .GOLD: treasure.sprite = &game.sprites.gold
					treasure.points = 4000
		case .RING: treasure.sprite = &game.sprites.ring
					treasure.points = 5000
		}
	}
}

to_east_screen :: proc(num_screens := 1) {
	for _ in 1..=num_screens {
		game.current_seed = next_level_bits(game.current_seed)
	}
	generate_level(game.current_seed)
}

to_west_screen :: proc(num_screens := 1) {
	for _ in 1..=num_screens {
		game.current_seed = prev_level_bits(game.current_seed)
	}
	generate_level(game.current_seed)
}

create_entity :: proc(new_flags: Entity_Flags) -> ^Entity {
	e := &game.entities[game.entity_count]
	e^ = {flags = new_flags}
	e.direction = .RIGHT
	game.entity_count += 1

	return e
}

// Gets the head hitbox when the croc's mouth is open
get_croc_head_rec :: proc(croc: rl.Rectangle) -> rl.Rectangle {
	return {
		croc.x + CROC_WIDTH - CROC_WIDTH/4, croc.y,
		CROC_WIDTH/4, GROUND_HEIGHT/2,
	}
}

