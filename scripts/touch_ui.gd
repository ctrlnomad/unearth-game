extends Control
## On-screen controls for touch devices: a FIRE button bottom right and a
## thumbstick that appears where the left thumb lands. scripts/main.gd reads the
## touches and sets the fields below; this only draws them.

const AMBER := Color(1.0, 0.7, 0.28)

var playing := false
var stick_on := false
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var fire_on := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func fire_center() -> Vector2:
	return size - Vector2(size.y * 0.15, size.y * 0.17)


func fire_radius() -> float:
	return size.y * 0.085


func stick_radius() -> float:
	return size.y * 0.09


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not playing:
		return
	var c := fire_center()
	var r := fire_radius()
	draw_circle(c, r, Color(AMBER, 0.35 if fire_on else 0.1))
	draw_arc(c, r, 0.0, TAU, 40, AMBER, maxf(2.0, size.y * 0.004))
	var font := ThemeDB.fallback_font
	var fs := int(size.y * 0.032)
	var w := font.get_string_size("FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), "FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, AMBER)
	if stick_on:
		draw_arc(stick_origin, stick_radius(), 0.0, TAU, 40, Color(0.81, 0.91, 0.92, 0.35), maxf(2.0, size.y * 0.004))
		draw_circle(stick_pos, stick_radius() * 0.42, Color(0.81, 0.91, 0.92, 0.3))
