extends Control

## Lobby main menu. Everything lives on this one screen — no hidden
## menus, no popups: the soldier on his showcase patch (3D SubViewport),
## the map cards (only Dead City is unlocked), the gun cards (real stats
## from weapons.gd; the pick is shown in the showcase AND used as the
## starting weapon in game), the settings (sound on/off + sensitivity),
## and the big PLAY button.
## The Z emblem is NOT here — it stays only as the app icon.
## Choices persist to user://settings.cfg (keys: settings/starting_weapon,
## settings/sound, settings/sensitivity — the same file player.gd reads).

const GAME_SCENE := "res://scenes/game.tscn"
const SHOWCASE_SCENE := "res://scenes/showcase.tscn"
const SETTINGS_PATH := "user://settings.cfg"

const MAPS: Array = [
	{"id": "dead_city", "name": "Dead City", "locked": false},
	{"id": "dark_forest", "name": "Dark Forest", "locked": true},
	{"id": "military_base", "name": "Military Base", "locked": true},
	{"id": "dead_village", "name": "Dead Village", "locked": true},
]

const COL_GREEN := Color(0.65, 0.91, 0.2)
const COL_TEXT := Color(0.92, 0.94, 0.9)
const COL_DIM := Color(0.6, 0.63, 0.58)
const COL_PANEL := Color(0.08, 0.1, 0.07, 0.94)
const COL_CARD := Color(0.13, 0.15, 0.12)
const COL_CARD_HOVER := Color(0.17, 0.2, 0.15)
const COL_CARD_SELECTED := Color(0.22, 0.32, 0.12)
const COL_CARD_DISABLED := Color(0.07, 0.07, 0.07)

var _selected_weapon: String = "pistol"
var _selected_map: String = "dead_city"
var _selected_mission: int = 1
var _highest_mission: int = 1
var _mission_label: Label
var _coins_label: Label
var _gun_buttons: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _map_buttons: Dictionary = {}
var _showcase: Node = null
var _sound_check: CheckButton
var _sens_slider: HSlider
var _sens_value: Label
var _click_player: AudioStreamPlayer

func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.bus = &"SFX"
	_click_player.stream = SfxGen.ui_click()
	add_child(_click_player)
	_build_ui()
	_load_settings()

# --- layout --------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "ZOMBIE SURVIVAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COL_GREEN)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "- LAST DAY -"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", COL_TEXT)
	root.add_child(subtitle)

	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.text = "COINS: 0"
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins_label.add_theme_font_size_override("font_size", 22)
	_coins_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	root.add_child(_coins_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	columns.add_child(_build_character_column())
	columns.add_child(_build_maps_column())
	columns.add_child(_build_guns_settings_column())

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = Color(0.3, 0.38, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p

func _column(panel: PanelContainer) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return v

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", COL_GREEN)
	return l

func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_card(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _card_style(COL_CARD, Color(0.28, 0.3, 0.25)))
	b.add_theme_stylebox_override("hover", _card_style(COL_CARD_HOVER, Color(0.4, 0.45, 0.35)))
	b.add_theme_stylebox_override("pressed", _card_style(COL_CARD_SELECTED, COL_GREEN))
	b.add_theme_stylebox_override("disabled", _card_style(COL_CARD_DISABLED, Color(0.16, 0.16, 0.16)))
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_TEXT)
	b.add_theme_color_override("font_pressed_color", COL_TEXT)
	b.add_theme_color_override("font_disabled_color", COL_DIM)

func _build_character_column() -> PanelContainer:
	var panel := _panel()
	var v := _column(panel)
	v.add_child(_header("CHARACTER"))

	var svc := SubViewportContainer.new()
	svc.name = "ShowcaseView"
	svc.custom_minimum_size = Vector2(380, 300)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.stretch = true
	var sv := SubViewport.new()
	sv.name = "ShowcaseViewport"
	sv.size = Vector2i(380, 300)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	_showcase = load(SHOWCASE_SCENE).instantiate()
	sv.add_child(_showcase)
	v.add_child(svc)

	var play := Button.new()
	play.name = "PlayButton"
	play.text = "▶  PLAY"
	play.custom_minimum_size = Vector2(0, 72)
	play.add_theme_font_size_override("font_size", 32)
	play.add_theme_stylebox_override("normal", _card_style(Color(0.25, 0.38, 0.1), COL_GREEN))
	play.add_theme_stylebox_override("hover", _card_style(Color(0.32, 0.48, 0.13), COL_GREEN))
	play.add_theme_stylebox_override("pressed", _card_style(Color(0.18, 0.27, 0.07), COL_GREEN))
	play.add_theme_color_override("font_color", COL_TEXT)
	play.add_theme_color_override("font_hover_color", COL_TEXT)
	play.add_theme_color_override("font_pressed_color", COL_TEXT)
	play.pressed.connect(_on_play_pressed)
	v.add_child(play)

	var credits := Label.new()
	credits.name = "CreditsLabel"
	credits.text = "Zombie models: Vinish.dev (CC BY 4.0)\nHero & city models: KayKit (CC0)"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", 13)
	credits.add_theme_color_override("font_color", COL_DIM)
	v.add_child(credits)
	return panel

func _build_maps_column() -> PanelContainer:
	var panel := _panel()
	var v := _column(panel)
	v.add_child(_header("MAPS"))
	for m in MAPS:
		var id := str(m["id"])
		var b := Button.new()
		b.name = "MapButton_" + id
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 68)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 21)
		if bool(m["locked"]):
			b.text = str(m["name"]) + "\nLOCKED — Phase 2"
			b.disabled = true
		else:
			b.text = str(m["name"]) + "\nReady — tap to select"
		_style_card(b)
		b.pressed.connect(_on_map_pressed.bind(id))
		_map_buttons[id] = b
		v.add_child(b)
		if id == "dead_city":
			v.add_child(_build_mission_row())
	return panel

func _build_mission_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MissionRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var prev := Button.new()
	prev.name = "MissionPrev"
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(56, 48)
	prev.add_theme_font_size_override("font_size", 22)
	prev.add_theme_color_override("font_color", COL_TEXT)
	_style_card(prev)
	prev.pressed.connect(func() -> void:
		_set_mission(_selected_mission - 1)
		_click_player.play())
	row.add_child(prev)
	_mission_label = Label.new()
	_mission_label.name = "MissionLabel"
	_mission_label.text = "MISSION 1"
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_label.custom_minimum_size = Vector2(160, 0)
	_mission_label.add_theme_font_size_override("font_size", 22)
	_mission_label.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(_mission_label)
	var next := Button.new()
	next.name = "MissionNext"
	next.text = "▶"
	next.custom_minimum_size = Vector2(56, 48)
	next.add_theme_font_size_override("font_size", 22)
	next.add_theme_color_override("font_color", COL_TEXT)
	_style_card(next)
	next.pressed.connect(func() -> void:
		_set_mission(_selected_mission + 1)
		_click_player.play())
	row.add_child(next)
	return row

func _set_mission(n: int) -> void:
	_selected_mission = clampi(n, 1, maxi(1, _highest_mission))
	_refresh_mission_label()
	_save_settings()

func _refresh_mission_label() -> void:
	if _mission_label != null:
		_mission_label.text = "MISSION %d" % _selected_mission

func _build_guns_settings_column() -> PanelContainer:
	var panel := _panel()
	var v := _column(panel)
	v.add_child(_header("GUNS"))
	for id in Weapons.ORDER:
		var b := Button.new()
		b.name = "GunButton_" + id
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 20)
		_style_card(b)
		b.pressed.connect(_on_gun_pressed.bind(id))
		_gun_buttons[id] = b
		v.add_child(b)
		v.add_child(_build_upgrade_row(id))
	_refresh_gun_cards()

	v.add_child(_header("SETTINGS"))

	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 10)
	var sound_label := Label.new()
	sound_label.text = "Sound"
	sound_label.custom_minimum_size = Vector2(120, 0)
	sound_label.add_theme_font_size_override("font_size", 20)
	sound_label.add_theme_color_override("font_color", COL_TEXT)
	sound_row.add_child(sound_label)
	_sound_check = CheckButton.new()
	_sound_check.name = "SoundCheck"
	_sound_check.text = "ON"
	_sound_check.add_theme_font_size_override("font_size", 20)
	_sound_check.add_theme_color_override("font_color", COL_TEXT)
	_sound_check.toggled.connect(_on_sound_toggled)
	sound_row.add_child(_sound_check)
	v.add_child(sound_row)

	var sens_label := Label.new()
	sens_label.text = "Sensitivity"
	sens_label.add_theme_font_size_override("font_size", 20)
	sens_label.add_theme_color_override("font_color", COL_TEXT)
	v.add_child(sens_label)

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 10)
	_sens_slider = HSlider.new()
	_sens_slider.name = "SensitivitySlider"
	_sens_slider.min_value = 0.5
	_sens_slider.max_value = 2.0
	_sens_slider.step = 0.05
	_sens_slider.value = 1.0
	_sens_slider.custom_minimum_size = Vector2(240, 44)
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.value_changed.connect(_on_sensitivity_changed)
	sens_row.add_child(_sens_slider)
	_sens_value = Label.new()
	_sens_value.name = "SensitivityValue"
	_sens_value.text = "1.00"
	_sens_value.custom_minimum_size = Vector2(56, 0)
	_sens_value.add_theme_font_size_override("font_size", 20)
	_sens_value.add_theme_color_override("font_color", COL_TEXT)
	sens_row.add_child(_sens_value)
	v.add_child(sens_row)
	return panel

# --- coins & upgrades ------------------------------------------------------

func _build_upgrade_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UpgradeRow_" + id
	row.add_theme_constant_override("separation", 8)
	for stat in ["damage", "fire_rate"]:
		var b := Button.new()
		b.name = "Upgrade_" + id + "_" + stat
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		_style_card(b)
		b.pressed.connect(_on_upgrade_pressed.bind(id, stat))
		_upgrade_buttons[id + "_" + stat] = b
		row.add_child(b)
	return row

func _refresh_coins() -> void:
	if _coins_label != null:
		_coins_label.text = "COINS: %d" % Wallet.get_coins()

func _refresh_gun_cards() -> void:
	for id in Weapons.ORDER:
		if not _gun_buttons.has(id):
			continue
		var data := Weapons.get_upgraded(id)
		var dmg := str(int(data["damage"]))
		if int(data["pellets"]) > 1:
			dmg += "×" + str(int(data["pellets"]))
		(_gun_buttons[id] as Button).text = "%s\nDamage %s · Fire rate %.1f/s · Mag %d" % [
			str(data["name"]), dmg, float(data["fire_rate"]), int(data["magazine"])]

func _refresh_upgrade_buttons() -> void:
	var coins := Wallet.get_coins()
	for id in Weapons.ORDER:
		for stat in ["damage", "fire_rate"]:
			var key: String = id + "_" + stat
			if not _upgrade_buttons.has(key):
				continue
			var b := _upgrade_buttons[key] as Button
			var short := "DMG" if stat == "damage" else "SPD"
			var level := Weapons.get_upgrade_level(id, stat)
			if level >= Weapons.MAX_UPGRADE_LEVEL:
				b.text = "%s MAX" % short
				b.disabled = true
			else:
				var price := Weapons.upgrade_price(level)
				b.text = "%s Lv%d · %d coins" % [short, level, price]
				b.disabled = coins < price

func _on_upgrade_pressed(id: String, stat: String) -> void:
	var level := Weapons.get_upgrade_level(id, stat)
	if level >= Weapons.MAX_UPGRADE_LEVEL:
		return
	# spend_coins checks the balance and deducts in one step — a failed
	# or repeated tap can never charge twice or go negative.
	if not Wallet.spend_coins(Weapons.upgrade_price(level)):
		_click_player.play()
		return
	Weapons.set_upgrade_level(id, stat, level + 1)
	_refresh_coins()
	_refresh_gun_cards()
	_refresh_upgrade_buttons()
	_click_player.play()

# --- selection -----------------------------------------------------------

func _on_map_pressed(id: String) -> void:
	_select_map(id)
	_click_player.play()

func _select_map(id: String) -> void:
	_selected_map = id
	for key in _map_buttons.keys():
		(_map_buttons[key] as Button).set_pressed_no_signal(str(key) == id)

func _on_gun_pressed(id: String) -> void:
	_select_weapon(id)
	_save_settings()
	_click_player.play()

func _select_weapon(id: String) -> void:
	_selected_weapon = id
	for key in _gun_buttons.keys():
		(_gun_buttons[key] as Button).set_pressed_no_signal(str(key) == id)
	if _showcase != null and _showcase.has_method("set_weapon"):
		_showcase.set_weapon(id)

func _on_sound_toggled(on: bool) -> void:
	_sound_check.text = "ON" if on else "OFF"
	AudioServer.set_bus_mute(0, not on)
	_save_settings()

func _on_sensitivity_changed(v: float) -> void:
	_sens_value.text = "%.2f" % v
	_save_settings()

func _on_play_pressed() -> void:
	_click_player.play()
	_save_settings()
	get_tree().change_scene_to_file(GAME_SCENE)

# --- persistence -----------------------------------------------------------

func _save_settings() -> void:
	if _sens_slider == null or _sound_check == null:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep any keys written by other screens
	cfg.set_value("settings", "sensitivity", _sens_slider.value)
	cfg.set_value("settings", "sound", _sound_check.button_pressed)
	cfg.set_value("settings", "starting_weapon", _selected_weapon)
	cfg.set_value("progress", "highest_mission", _highest_mission)
	cfg.set_value("progress", "selected_mission", _selected_mission)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	_refresh_coins()
	_refresh_upgrade_buttons()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# First run ever: sound is ON by default — make the toggle say so.
		_sound_check.set_pressed_no_signal(true)
		_sound_check.text = "ON"
		_refresh_mission_label()
		_select_map(_selected_map)
		_select_weapon(_selected_weapon)
		return
	_highest_mission = maxi(1, int(cfg.get_value("progress", "highest_mission", 1)))
	_selected_mission = clampi(int(cfg.get_value("progress", "selected_mission", _highest_mission)), 1, _highest_mission)
	_refresh_mission_label()
	var sens := clampf(float(cfg.get_value("settings", "sensitivity", 1.0)), 0.5, 2.0)
	_sens_slider.set_value_no_signal(sens)
	_sens_value.text = "%.2f" % sens
	var sound_on := bool(cfg.get_value("settings", "sound", true))
	_sound_check.set_pressed_no_signal(sound_on)
	_sound_check.text = "ON" if sound_on else "OFF"
	AudioServer.set_bus_mute(0, not sound_on)
	_select_map(_selected_map)
	var wid := str(cfg.get_value("settings", "starting_weapon", "pistol"))
	if not Weapons.ORDER.has(wid):
		wid = "pistol"
	_select_weapon(wid)
