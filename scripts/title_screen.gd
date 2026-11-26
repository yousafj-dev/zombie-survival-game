extends Control

## Opening title screen (black, game name in bold white — same look as the
## boot splash, so the opening reads as one continuous sequence).
## The name fades in with a slight cinematic zoom and one subtle glitch
## flicker, then the screen holds for a full 5 seconds before the main
## menu opens. There is deliberately NO input handling here: taps during
## the 5 seconds do nothing and cannot skip the sequence.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const HOLD_SECONDS := 5.0

@onready var _block: Control = $TitleBlock

func _ready() -> void:
	_block.modulate.a = 0.0
	_block.scale = Vector2(0.92, 0.92)
	# The 5-second hold runs from scene start, whatever happens.
	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_open_menu)
	await get_tree().process_frame
	_block.pivot_offset = _block.size * 0.5
	_play_intro()

func _play_intro() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_block, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_block, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.25)
	# One brief horror glitch: quick x jitter + alpha flicker, then still.
	var base_x := _block.position.x
	tw.tween_property(_block, "position:x", base_x + 6.0, 0.04)
	tw.tween_property(_block, "modulate:a", 0.35, 0.03)
	tw.tween_property(_block, "position:x", base_x - 5.0, 0.04)
	tw.tween_property(_block, "modulate:a", 1.0, 0.03)
	tw.tween_property(_block, "position:x", base_x + 3.0, 0.04)
	tw.tween_property(_block, "position:x", base_x, 0.05)
	# Gentle fade-out completing right as the 5-second hold ends.
	tw.tween_interval(HOLD_SECONDS - 2.05)
	tw.tween_property(_block, "modulate:a", 0.0, 0.3)

func _open_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
