extends CanvasLayer

## In-game HUD: health bar, ammo, current weapon, wave label,
## centre message, virtual joystick + FIRE / RELOAD / SWITCH buttons.
## Binds to the player in group "player" and forwards touch input to it.
## The game manager updates wave info via set_wave_text() / show_message()
## (called with call_group("hud", ...)).
##
## Modern styling (look-fix round 2) is applied in code: pill panels for
## health / wave / coins / ammo and icon buttons whose icons are drawn
## at runtime by the IconPainter below — vector-drawn, no image files.

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
var _hp_label: Label
var _health_fill: StyleBoxFlat

# --- runtime-drawn icons ---------------------------------------------------
## A Control that paints one clean vector icon in its rect. Kinds:
## "rifle" (FIRE), "reload" (circular arrow), "switch" (swap arrows),
## "coin", "cross" (health). White line-work on transparent background,
## so it sits crisply on the buttons' dark glass style at any size.

class IconPainter extends Control:
	var kind := ""
	var tint := Color.WHITE

	func _init(p_kind := "", p_tint := Color.WHITE) -> void:
		kind = p_kind
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		match kind:
			"rifle":
				_draw_rifle()
			"reload":
				_draw_reload()
			"switch":
				_draw_switch()
			"coin":
				_draw_coin()
			"cross":
				_draw_cross()

	# Virtual 100x64 canvas mapped onto the control rect.
	func _pt(x: float, y: float) -> Vector2:
		return Vector2(size.x * x / 100.0, size.y * y / 64.0)

	func _poly(pts: Array, col: Color) -> void:
		var v := PackedVector2Array()
		for p in pts:
			v.append(_pt(p[0], p[1]))
		draw_colored_polygon(v, col)

	func _draw_rifle() -> void:
		# Rifle silhouette facing right (stock, receiver, barrel, mag, grip).
		_poly([[34, 17], [46, 17], [46, 25], [34, 25]], tint) # sight
		_poly([[15, 25], [63, 25], [63, 38], [15, 38]], tint) # receiver
		_poly([[1, 31], [15, 27], [15, 40], [3, 45]], tint) # stock
		_poly([[63, 28.5], [93, 28.5], [93, 34], [63, 34]], tint) # barrel
		_poly([[67, 34], [88, 34], [88, 39], [67, 39]], tint) # handguard
		_poly([[44, 38], [52, 38], [50, 54], [42, 52]], tint) # magazine
		_poly([[23, 38], [30, 38], [33, 51], [26, 52]], tint) # grip
		# Muzzle flash: small 4-point star at the barrel tip.
		var c := _pt(96, 31)
		var star := PackedVector2Array()
		for i in 8:
			var ang := float(i) * PI / 4.0
			var r := (7.0 if i % 2 == 0 else 2.6) * size.x / 100.0
			star.append(c + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(star, Color(1.0, 0.62, 0.25))

	func _draw_reload() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := 0.33 * s
		var a0 := -0.42 * PI
		var a1 := a0 + 1.5 * PI
		draw_arc(c, r, a0, a1, 48, tint, 0.085 * s, true)
		# Arrowhead at the arc's end, pointing along the motion.
		var p := c + Vector2(cos(a1), sin(a1)) * r
		var vel := Vector2(-sin(a1), cos(a1))
		var radial := Vector2(cos(a1), sin(a1))
		var tip := p + vel * 0.21 * s
		var b1 := p + radial * 0.115 * s - vel * 0.03 * s
		var b2 := p - radial * 0.115 * s - vel * 0.03 * s
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), tint)

	func _draw_switch() -> void:
		var w := 0.085 * minf(size.x, size.y)
		var y1 := size.y * 0.36
		var y2 := size.y * 0.64
		# Top arrow points right, bottom arrow points left.
		draw_line(Vector2(size.x * 0.22, y1), Vector2(size.x * 0.68, y1), tint, w, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(size.x * 0.66, y1 - size.y * 0.11),
			Vector2(size.x * 0.66, y1 + size.y * 0.11),
			Vector2(size.x * 0.82, y1)]), tint)
		draw_line(Vector2(size.x * 0.78, y2), Vector2(size.x * 0.32, y2), tint, w, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(size.x * 0.34, y2 - size.y * 0.11),
			Vector2(size.x * 0.34, y2 + size.y * 0.11),
			Vector2(size.x * 0.18, y2)]), tint)

	func _draw_coin() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := 0.42 * s
		draw_circle(c, r, Color(0.98, 0.78, 0.28))
		draw_arc(c, r * 0.76, 0.0, TAU, 40, Color(0.78, 0.56, 0.15), r * 0.15, true)
		draw_circle(c, r * 0.36, Color(0.93, 0.70, 0.22))
		var star := PackedVector2Array()
		for i in 8:
			var ang := float(i) * PI / 4.0 - PI / 2.0
			var rr := (r * 0.30 if i % 2 == 0 else r * 0.13)
			star.append(c + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(star, Color(1.0, 0.9, 0.5))

	func _draw_cross() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		draw_circle(c, 0.44 * s, Color(0.88, 0.28, 0.24))
		var col := Color(0.97, 0.97, 0.97)
		draw_rect(Rect2(c - Vector2(0.09, 0.27) * s, Vector2(0.18, 0.54) * s), col)
		draw_rect(Rect2(c - Vector2(0.27, 0.09) * s, Vector2(0.54, 0.18) * s), col)

# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	add_to_group("hud")
	_message_label.visible = false
	_style_scene_controls()
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

# --- modern styling ----------------------------------------------------------
## Wraps the scene's plain controls in dark-glass pill panels and turns
## the three text buttons into rounded icon buttons. Runs before the
## result panel / feedback UI are built, so those still draw on top.

func _glass_style(bg: Color, border: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb

func _style_scene_controls() -> void:
	var glass := Color(0.06, 0.07, 0.06, 0.66)
	var edge := Color(1, 1, 1, 0.16)
	var ink := Color(0.93, 0.95, 0.92)

	# Health: cross icon + rounded bar + numeric HP inside a pill.
	var hp_panel := PanelContainer.new()
	hp_panel.name = "HealthPanel"
	hp_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_panel.offset_left = 12.0
	hp_panel.offset_top = 12.0
	hp_panel.offset_right = 330.0
	hp_panel.offset_bottom = 58.0
	hp_panel.add_theme_stylebox_override("panel", _glass_style(glass, edge, 16))
	add_child(hp_panel)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 9)
	hp_panel.add_child(hp_row)
	var cross := IconPainter.new("cross")
	cross.custom_minimum_size = Vector2(28, 28)
	cross.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(cross)
	remove_child(_health_bar)
	_health_bar.custom_minimum_size = Vector2(196, 20)
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.04, 0.05, 0.04, 0.9)
	hp_bg.border_color = Color(1, 1, 1, 0.14)
	hp_bg.set_border_width_all(1)
	hp_bg.set_corner_radius_all(10)
	_health_bar.add_theme_stylebox_override("background", hp_bg)
	_health_fill = StyleBoxFlat.new()
	_health_fill.bg_color = Color(0.45, 0.85, 0.3)
	_health_fill.set_corner_radius_all(10)
	_health_bar.add_theme_stylebox_override("fill", _health_fill)
	hp_row.add_child(_health_bar)
	_hp_label = Label.new()
	_hp_label.name = "HealthValue"
	_hp_label.text = "100"
	_hp_label.add_theme_font_size_override("font_size", 19)
	_hp_label.add_theme_color_override("font_color", ink)
	_hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_label)

	# Wave banner: the scene label inside a centred pill.
	var wave_panel := PanelContainer.new()
	wave_panel.name = "WavePanel"
	wave_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_panel.offset_left = -185.0
	wave_panel.offset_top = 12.0
	wave_panel.offset_right = 185.0
	wave_panel.offset_bottom = 56.0
	wave_panel.add_theme_stylebox_override("panel", _glass_style(glass, edge, 22))
	add_child(wave_panel)
	remove_child(_wave_label)
	_wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 20)
	_wave_label.add_theme_color_override("font_color", ink)
	wave_panel.add_child(_wave_label)

	# Ammo cluster: weapon name + big ammo count in a panel above the
	# action buttons (bottom-right).
	var ammo_panel := PanelContainer.new()
	ammo_panel.name = "AmmoPanel"
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.offset_left = -292.0
	ammo_panel.offset_top = -404.0
	ammo_panel.offset_right = -28.0
	ammo_panel.offset_bottom = -316.0
	ammo_panel.add_theme_stylebox_override("panel", _glass_style(glass, edge, 16))
	add_child(ammo_panel)
	var ammo_box := VBoxContainer.new()
	ammo_box.add_theme_constant_override("separation", 0)
	ammo_panel.add_child(ammo_box)
	remove_child(_weapon_label)
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.add_theme_font_size_override("font_size", 18)
	_weapon_label.add_theme_color_override("font_color", Color(0.65, 0.91, 0.2))
	ammo_box.add_child(_weapon_label)
	remove_child(_ammo_label)
	_ammo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 38)
	_ammo_label.add_theme_color_override("font_color", Color(0.97, 0.98, 0.96))
	ammo_box.add_child(_ammo_label)

	# Centre message: outline so it reads over bright ground.
	_message_label.add_theme_constant_override("outline_size", 14)
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_message_label.add_theme_color_override("font_color", ink)

	# Action buttons: rounded dark glass, icon + small caption.
	_style_action_button(_fire_button, "rifle", "FIRE", Color(1.0, 0.45, 0.25, 0.85), Rect2(-164, -192, 136, 136), 28)
	_style_action_button(_reload_button, "reload", "RELOAD", Color(1, 1, 1, 0.35), Rect2(-292, -180, 112, 112), 24)
	_style_action_button(_switch_button, "switch", "SWITCH", Color(1, 1, 1, 0.35), Rect2(-292, -304, 112, 112), 24)

func _style_action_button(btn: Button, kind: String, caption: String, accent: Color, rect: Rect2, radius: int) -> void:
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.offset_left = rect.position.x
	btn.offset_top = rect.position.y
	btn.offset_right = rect.position.x + rect.size.x
	btn.offset_bottom = rect.position.y + rect.size.y
	var normal := _glass_style(Color(0.07, 0.08, 0.07, 0.68), accent, radius, 2)
	var hover := _glass_style(Color(0.12, 0.13, 0.11, 0.78), accent, radius, 2)
	var pressed := _glass_style(Color(0.16, 0.17, 0.14, 0.88), accent.lightened(0.25), radius, 2)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon := IconPainter.new(kind)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12.0
	icon.offset_top = 9.0
	icon.offset_right = -12.0
	icon.offset_bottom = -37.0
	btn.add_child(icon)
	var cap := Label.new()
	cap.text = caption
	cap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_top = -35.0
	cap.offset_bottom = -9.0
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", Color(0.93, 0.95, 0.92))
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	cap.add_theme_constant_override("shadow_offset_x", 1)
	cap.add_theme_constant_override("shadow_offset_y", 1)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cap)

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
	# Coins: gold coin icon + count inside a top-right pill.
	var coin_pill := PanelContainer.new()
	coin_pill.name = "CoinsPanel"
	coin_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	coin_pill.offset_left = -196.0
	coin_pill.offset_top = 12.0
	coin_pill.offset_right = -12.0
	coin_pill.offset_bottom = 58.0
	coin_pill.add_theme_stylebox_override("panel", _glass_style(Color(0.06, 0.07, 0.06, 0.66), Color(1, 1, 1, 0.16), 16))
	add_child(coin_pill)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 8)
	coin_pill.add_child(coin_row)
	var coin_icon := IconPainter.new("coin")
	coin_icon.custom_minimum_size = Vector2(27, 27)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(coin_icon)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.add_theme_font_size_override("font_size", 22)
	_coins_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_label.text = "0"
	coin_row.add_child(_coins_label)

	_boss_label = Label.new()
	_boss_label.name = "BossLabel"
	_boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_label.offset_left = -250.0
	_boss_label.offset_top = 64.0
	_boss_label.offset_right = 250.0
	_boss_label.offset_bottom = 92.0
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 20)
	_boss_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	_boss_label.add_theme_constant_override("outline_size", 8)
	_boss_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_boss_label.text = "BOSS"
	_boss_label.visible = false
	add_child(_boss_label)

	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.offset_left = -250.0
	_boss_bar.offset_top = 94.0
	_boss_bar.offset_right = 250.0
	_boss_bar.offset_bottom = 112.0
	_boss_bar.max_value = 100.0
	_boss_bar.value = 100.0
	_boss_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.05, 0.05, 0.85)
	bg.set_corner_radius_all(6)
	_boss_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.15, 0.15)
	fill.set_corner_radius_all(6)
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
		_coins_label.text = "%d" % coins

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
	if _hp_label != null:
		_hp_label.text = str(current)
	if _health_fill != null:
		var frac := float(current) / float(maxi(1, maximum))
		if frac > 0.5:
			_health_fill.bg_color = Color(0.45, 0.85, 0.3)
		elif frac > 0.25:
			_health_fill.bg_color = Color(0.95, 0.65, 0.25)
		else:
			_health_fill.bg_color = Color(0.9, 0.3, 0.25)

func _on_ammo_changed(magazine: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [magazine, reserve]

func _on_weapon_changed(weapon_name: String) -> void:
	_weapon_label.text = weapon_name
