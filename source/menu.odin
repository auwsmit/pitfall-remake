// EXPLANATION:
// immediate-mode UI for drawing menus

package pitfall

import rl "vendor:raylib"
import "core:math"

MENU_WIDTH     :: 100
MENU_HEIGHT    :: 10
MENU_COLOR     :: rl.GRAY
MENU_HIGHLIGHT :: rl.WHITE
MENU_SPACE     :: 5
MENU_BORDER    :: 1

menu_pos_y: f32
menu_current_id: int
menu_selected_id: int

menu_pause: rl.Rectangle = {
	GAME_WIDTH/2-MENU_WIDTH/2,
	GAME_HEIGHT/3,
	MENU_WIDTH, MENU_HEIGHT,
}

Text_Align :: enum {
	LEFT   = 0, TOP    = 0,
	CENTER = 1,
	RIGHT  = 2, BOTTOM = 2,
}

menu_update :: proc() {
	if input.menu_down {
		if menu_selected_id == menu_current_id - 1 {
			menu_selected_id = 0
		} else {
			menu_selected_id += 1
		}
	}
	if input.menu_up {
		if menu_selected_id == 0 {
			menu_selected_id = menu_current_id - 1
		} else {
			menu_selected_id -= 1
		}
	}
}

// Draws text aligned within a rectangle
draw_text_aligned :: proc(
	text   : cstring,
	rec    := rl.Rectangle{0, 0, GAME_WIDTH, GAME_HEIGHT},
	halign := Text_Align.CENTER,
	valign := Text_Align.CENTER,
	offset := Vec2{0, 0},
	size   : f32,
	color  := rl.WHITE
) {
	text_width := f32(rl.MeasureText(text, i32(size)))
	aligned_x  := rec.x + (rec.width - text_width)*(f32(halign)/2)
	aligned_y  := rec.y + (rec.height - size)*(f32(valign)/2)
	text_pos   := rl.Vector2{aligned_x, aligned_y} + offset
	rl.DrawText(text, i32(text_pos.x), i32(text_pos.y), i32(size), color)
}

draw_slider :: proc(
	text: cstring,
	x, y, width, height: f32,
	value: ^f32,
	min, max: f32,
	increment: f32,
	color := MENU_COLOR,
) -> bool {

	slider_rect := rl.Rectangle{x, y + height, width, height}
	is_mouse_within_slider := rl.CheckCollisionPointRec(input.mouse_pos_game, slider_rect)
	is_selected := menu_selected_id == menu_current_id
	is_clicked  := is_mouse_within_slider && rl.IsMouseButtonDown(.LEFT)
	border      := f32(MENU_BORDER) + (is_mouse_within_slider ? MENU_BORDER : 0)
	inner_x     := x + border
	inner_width := width - (border*2)
	min_visible_width := rl.Remap(min, min, max, 0, inner_width)
	fill_draw_width   := rl.Remap(value^, min, max, 0, inner_width)

	draw_text_aligned(text, {x, y, width, height}, size = height)
	rl.DrawRectangleRec(slider_rect, color)

	rl.DrawRectangleV(
		{inner_x, y + height + border},
		{fill_draw_width, height - (border*2)},
		MENU_HIGHLIGHT,
	)

	if is_mouse_within_slider || is_selected {
		menu_selected_id = menu_current_id
		rl.DrawRectangleLinesEx(slider_rect, MENU_BORDER, MENU_HIGHLIGHT)
	}

	if is_clicked {
		click_x := math.clamp(input.mouse_pos_game.x, inner_x + min_visible_width, inner_x + inner_width)
		value^ = rl.Remap(click_x, inner_x + min_visible_width, inner_x + inner_width, min, max)
	}

	if is_selected && input.menu_left {
		value^ = math.clamp(value^ - increment, min, max)
	}
	if is_selected && input.menu_right {
		value^ = math.clamp(value^ + increment, min, max)
	}

	return is_clicked || is_selected && (input.menu_ok || input.menu_left || input.menu_right)
}

draw_menu_slider :: proc(
	text       : cstring,
	menu       : rl.Rectangle,
	value      : ^f32,
	min, max   : f32,
	increment  : f32,
	color      := MENU_COLOR,
	first_item := false,
) -> bool {

	if first_item {
		menu_pos_y = menu.y
		menu_current_id = 0
	}

	is_clicked := draw_slider(text, menu.x, menu_pos_y, menu.width, menu.height, value, min, max, increment)
	menu_pos_y += menu.height*2 + MENU_SPACE
	menu_current_id += 1

	return is_clicked
}

draw_button :: proc(
	text: cstring,
	x, y, width, height: f32,
	color := MENU_COLOR
) -> bool {

	is_mouse_within_button := rl.CheckCollisionPointRec(input.mouse_pos_game, {x, y, width, height})

	rl.DrawRectangleV({x, y}, {width, height}, color)
	draw_text_aligned(text, {x, y, width, height}, size = height)

	if is_mouse_within_button || menu_selected_id == menu_current_id {
		menu_selected_id = menu_current_id
		rl.DrawRectangleLinesEx({x, y, width, height}, MENU_BORDER, MENU_HIGHLIGHT)
	}

	clicked := is_mouse_within_button && rl.IsMouseButtonPressed(.LEFT)
	selected := menu_selected_id == menu_current_id && input.menu_ok
	return clicked || selected
}

draw_menu_button :: proc(text: cstring, menu: rl.Rectangle, first_item := false) -> bool {
	if first_item {
		menu_pos_y = menu.y
		menu_current_id = 0
	}

	clicked := draw_button(text, menu.x, menu_pos_y, menu.width, menu.height)
	menu_pos_y += menu.height + MENU_SPACE
	menu_current_id += 1

	return clicked
}

