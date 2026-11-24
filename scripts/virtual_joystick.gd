class_name VirtualJoystick
extends Control

## Simple touch/mouse virtual joystick.
## Read `value` (Vector2, length 0..1) from the player or HUD each frame.
## Screen up = -Y, which the player maps to forward (-Z in 3D).

signal value_changed(value: Vector2)

var value: Vector2 = Vector2.ZERO
var _touch_index: int = -1

func _ready() -> void:
	custom_minimum_size = Vector2(160, 160)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_update_value(event.position)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_set_value(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_value(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_index = 0
			_update_value(event.position)
		else:
			_touch_index = -1
			_set_value(Vector2.ZERO)
	elif event is InputEventMouseMotion and _touch_index == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_value(event.position)

func _update_value(local_pos: Vector2) -> void:
	var radius := size.x * 0.5
	var offset := local_pos - size * 0.5
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_set_value(offset / radius)

func _set_value(v: Vector2) -> void:
	if v == value:
		return
	value = v
	value_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.5
	draw_circle(center, radius, Color(1, 1, 1, 0.12))
	draw_arc(center, radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(center + value * radius * 0.55, radius * 0.38, Color(1, 1, 1, 0.35))
