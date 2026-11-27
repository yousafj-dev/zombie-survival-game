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
var _coins_label: Label
var _boss_label: Label
var _boss_bar: ProgressBar
var _hit_marker: Label
var _hit_left: float = 0.0
var _damage_flash: ColorRect
var _flash_tween: Tween

func _ready() -> void:
	add_to_group("hud")
	_message_label.visible = false
	_build_result_panel()
	_build_feedback_ui()
	call_deferred("_bind_player")

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	_player.health_changed.connect(_on_health_changed)
	_player.ammo_changed.connect(_on_ammo_changed)
	_player.weapon_changed.connect(_on_weapon_changed)
	if _player.has_signal("hit_landed"):
		_player.hit_landed.connect(_on_hit_landed)
	if _player.has_signal("took_damage"):
		_player.took_damage.connect(_on_took_damage)
	# Push the player's current state once so labels are not blank.
	_player._emit_weapon_signals()

	_fire_button.button_down.connect(func() -> void: _player.set_firing(true))
	_fire_button.button_up.connect(func() -> void: _player.set_firing(false))
	_reload_button.pressed.connect(func() -> void: _player.reload())
	_switch_button.pressed.connect(func() -> void: _player.switch_weapon())

func _process(_delta: float) -> void:
	if is_instance_valid(_player):
		_player.set_move_input(_joystick.value)
	if _hit_left > 0.0:
		_hit_left -= _delta
		if _hit_left <= 0.0 and _hit_marker != null:
			_hit_marker.visible = false

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

func show_result(win: bool, mission: int, coins_earned: int = 0) -> void:
	_result_win = win
	if win:
		_result_title.text = "MISSION COMPLETE"
		_result_title.add_theme_color_override("font_color", Color(0.65, 0.91, 0.2))
		_result_subtitle.text = "Mission %d cleared — Mission %d unlocked!\nCoins earned: +%d" % [mission, mission + 1, coins_earned]
		_result_primary.text = "NEXT MISSION"
	else:
		_result_title.text = "YOU DIED — MISSION FAILED"
		_result_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
		_result_subtitle.text = "Mission %d\nCoins earned: +%d" % [mission, coins_earned]
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

# --- feedback UI (coins, boss bar, hit marker, damage flash) -------------
## Built in code like the result panel, so hud.tscn stays untouched.

func _build_feedback_ui() -> void:
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coins_label.offset_left = -260.0
	_coins_label.offset_top = 12.0
	_coins_label.offset_right = -16.0
	_coins_label.offset_bottom = 44.0
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.add_theme_font_size_override("font_size", 22)
	_coins_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_coins_label.text = "COINS: 0"
	add_child(_coins_label)

	_boss_label = Label.new()
	_boss_label.name = "BossLabel"
	_boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_label.offset_left = -250.0
	_boss_label.offset_top = 50.0
	_boss_label.offset_right = 250.0
	_boss_label.offset_bottom = 78.0
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 20)
	_boss_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	_boss_label.text = "BOSS"
	_boss_label.visible = false
	add_child(_boss_label)

	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.offset_left = -250.0
	_boss_bar.offset_top = 80.0
	_boss_bar.offset_right = 250.0
	_boss_bar.offset_bottom = 98.0
	_boss_bar.max_value = 100.0
	_boss_bar.value = 100.0
	_boss_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.05, 0.05, 0.85)
	bg.set_corner_radius_all(4)
	_boss_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.15, 0.15)
	fill.set_corner_radius_all(4)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	_boss_bar.visible = false
	add_child(_boss_bar)

	_hit_marker = Label.new()
	_hit_marker.name = "HitMarker"
	_hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	_hit_marker.offset_left = -30.0
	_hit_marker.offset_top = -34.0
	_hit_marker.offset_right = 30.0
	_hit_marker.offset_bottom = 34.0
	_hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hit_marker.add_theme_font_size_override("font_size", 44)
	_hit_marker.add_theme_color_override("font_color", Color(1, 1, 1))
	_hit_marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hit_marker.add_theme_constant_override("shadow_offset_x", 2)
	_hit_marker.add_theme_constant_override("shadow_offset_y", 2)
	_hit_marker.text = "×"
	_hit_marker.visible = false
	add_child(_hit_marker)

	_damage_flash = ColorRect.new()
	_damage_flash.name = "DamageFlash"
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(0.85, 0.1, 0.1, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

func _on_hit_landed() -> void:
	_hit_marker.visible = true
	_hit_left = 0.09

func _on_took_damage() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_damage_flash.color = Color(0.85, 0.1, 0.1, 0.3)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.4)

# --- called by the game manager ----------------------------------------

func set_wave_text(wave: int, total: int, alive: int) -> void:
	_wave_label.text = "Wave %d / %d   ·   Zombies: %d" % [wave, total, alive]

func set_coins(coins: int) -> void:
	if _coins_label != null:
		_coins_label.text = "COINS: %d" % coins

func show_boss_bar(title: String) -> void:
	_boss_label.text = title
	_boss_label.visible = true
	_boss_bar.visible = true

func set_boss_health(current: int, maximum: int) -> void:
	_boss_bar.max_value = maxi(1, maximum)
	_boss_bar.value = clampi(current, 0, maxi(1, maximum))

func hide_boss_bar() -> void:
	_boss_label.visible = false
	_boss_bar.visible = false

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
