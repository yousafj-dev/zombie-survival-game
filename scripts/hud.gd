extends CanvasLayer

## In-game HUD (Phase 1): health bar, ammo, current weapon, wave label,
## centre message, virtual joystick + FIRE / RELOAD / SWITCH buttons.
## Binds to the player in group "player" and forwards touch input to it.
## The game manager updates wave info via set_wave_text() / show_message()
## (called with call_group("hud", ...)).

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _ammo_label: Label = $AmmoLabel
@onready var _weapon_label: Label = $WeaponLabel
@onready var _wave_label: Label = $WaveLabel
@onready var _message_label: Label = $MessageLabel
@onready var _joystick: VirtualJoystick = $VirtualJoystick
@onready var _fire_button: Button = $FireButton
@onready var _reload_button: Button = $ReloadButton
@onready var _switch_button: Button = $SwitchButton

var _player: Node
var _result_backdrop: ColorRect
var _result_panel: CenterContainer
var _result_title: Label
var _result_subtitle: Label
var _result_primary: Button
var _result_win: bool = false

func _ready() -> void:
	add_to_group("hud")
	_message_label.visible = false
	_build_result_panel()
	call_deferred("_bind_player")

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	_player.health_changed.connect(_on_health_changed)
	_player.ammo_changed.connect(_on_ammo_changed)
	_player.weapon_changed.connect(_on_weapon_changed)
	# Push the player's current state once so labels are not blank.
	_player._emit_weapon_signals()

	_fire_button.button_down.connect(func() -> void: _player.set_firing(true))
	_fire_button.button_up.connect(func() -> void: _player.set_firing(false))
	_reload_button.pressed.connect(func() -> void: _player.reload())
	_switch_button.pressed.connect(func() -> void: _player.switch_weapon())

func _process(_delta: float) -> void:
	if is_instance_valid(_player):
		_player.set_move_input(_joystick.value)

# --- mission result panel ------------------------------------------------
## Built in code. The tree is PAUSED while this is up, so the panel and its
## backdrop run with process_mode = ALWAYS and the buttons stay tappable.
## The game waits here — no auto reload, no auto anything.

func _result_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _build_result_panel() -> void:
	_result_backdrop = ColorRect.new()
	_result_backdrop.name = "ResultBackdrop"
	_result_backdrop.color = Color(0, 0, 0, 0.55)
	_result_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_result_backdrop.visible = false
	add_child(_result_backdrop)

	_result_panel = CenterContainer.new()
	_result_panel.name = "ResultPanel"
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_result_panel.visible = false
	add_child(_result_panel)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _result_style(Color(0.07, 0.09, 0.06, 0.97), Color(0.65, 0.91, 0.2)))
	_result_panel.add_child(box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	_result_title = Label.new()
	_result_title.name = "ResultTitle"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 34)
	_result_title.add_theme_color_override("font_color", Color(0.65, 0.91, 0.2))
	v.add_child(_result_title)

	_result_subtitle = Label.new()
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_subtitle.add_theme_font_size_override("font_size", 20)
	_result_subtitle.add_theme_color_override("font_color", Color(0.92, 0.94, 0.9))
	v.add_child(_result_subtitle)

	_result_primary = Button.new()
	_result_primary.name = "ResultPrimaryButton"
	_result_primary.custom_minimum_size = Vector2(280, 58)
	_result_primary.add_theme_font_size_override("font_size", 24)
	_result_primary.add_theme_stylebox_override("normal", _result_style(Color(0.25, 0.38, 0.1), Color(0.65, 0.91, 0.2)))
	_result_primary.add_theme_stylebox_override("hover", _result_style(Color(0.32, 0.48, 0.13), Color(0.65, 0.91, 0.2)))
	_result_primary.add_theme_stylebox_override("pressed", _result_style(Color(0.18, 0.27, 0.07), Color(0.65, 0.91, 0.2)))
	_result_primary.add_theme_color_override("font_color", Color(0.92, 0.94, 0.9))
	_result_primary.pressed.connect(_on_result_primary)
	v.add_child(_result_primary)

	var lobby_btn := Button.new()
	lobby_btn.name = "ResultLobbyButton"
	lobby_btn.text = "LOBBY"
	lobby_btn.custom_minimum_size = Vector2(280, 52)
	lobby_btn.add_theme_font_size_override("font_size", 22)
	lobby_btn.add_theme_stylebox_override("normal", _result_style(Color(0.13, 0.15, 0.12), Color(0.4, 0.45, 0.35)))
	lobby_btn.add_theme_stylebox_override("hover", _result_style(Color(0.17, 0.2, 0.15), Color(0.4, 0.45, 0.35)))
	lobby_btn.add_theme_stylebox_override("pressed", _result_style(Color(0.09, 0.1, 0.08), Color(0.4, 0.45, 0.35)))
	lobby_btn.add_theme_color_override("font_color", Color(0.92, 0.94, 0.9))
	lobby_btn.pressed.connect(_on_result_lobby)
	v.add_child(lobby_btn)

func show_result(win: bool, mission: int) -> void:
	_result_win = win
	if win:
		_result_title.text = "MISSION COMPLETE"
		_result_title.add_theme_color_override("font_color", Color(0.65, 0.91, 0.2))
		_result_subtitle.text = "Mission %d cleared — Mission %d unlocked!" % [mission, mission + 1]
		_result_primary.text = "NEXT MISSION"
	else:
		_result_title.text = "YOU DIED — MISSION FAILED"
		_result_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
		_result_subtitle.text = "Mission %d" % mission
		_result_primary.text = "RETRY"
	_result_backdrop.visible = true
	_result_panel.visible = true

func _on_result_primary() -> void:
	if _result_win:
		get_tree().call_group("game_manager", "next_mission")
	else:
		get_tree().call_group("game_manager", "retry_mission")

func _on_result_lobby() -> void:
	get_tree().call_group("game_manager", "back_to_lobby")

# --- called by the game manager ----------------------------------------

func set_wave_text(wave: int, total: int, alive: int) -> void:
	_wave_label.text = "Wave %d / %d   ·   Zombies: %d" % [wave, total, alive]

func show_message(text: String, seconds: float = 2.5) -> void:
	_message_label.text = text
	_message_label.visible = true
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void: _message_label.visible = false)

# --- player signals ------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current

func _on_ammo_changed(magazine: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [magazine, reserve]

func _on_weapon_changed(weapon_name: String) -> void:
	_weapon_label.text = weapon_name
