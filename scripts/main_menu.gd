extends Control

## Main menu (Phase 1 skeleton).
## Play and Offline both start the offline Dead City level — online mode is
## Phase 2, so its button is disabled. Settings adjust the Music/SFX audio
## buses for real and persist sensitivity + graphics choice to
## user://settings.cfg. Profile is a placeholder panel for now.

const GAME_SCENE := "res://scenes/game.tscn"
const SETTINGS_PATH := "user://settings.cfg"

@onready var _settings_overlay: Control = $SettingsOverlay
@onready var _profile_overlay: Control = $ProfileOverlay
@onready var _music_slider: HSlider = $SettingsOverlay/Panel/VBox/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $SettingsOverlay/Panel/VBox/SfxRow/SfxSlider
@onready var _sensitivity_slider: HSlider = $SettingsOverlay/Panel/VBox/SensitivityRow/SensitivitySlider
@onready var _graphics_option: OptionButton = $SettingsOverlay/Panel/VBox/GraphicsRow/GraphicsOption

func _ready() -> void:
	$Center/VBox/PlayButton.pressed.connect(_start_game)
	$Center/VBox/OfflineButton.pressed.connect(_start_game)
	$Center/VBox/SettingsButton.pressed.connect(func() -> void: _settings_overlay.visible = true)
	$Center/VBox/ProfileButton.pressed.connect(func() -> void: _profile_overlay.visible = true)
	$SettingsOverlay/Panel/VBox/SettingsBackButton.pressed.connect(_close_settings)
	$ProfileOverlay/Panel/VBox/ProfileBackButton.pressed.connect(func() -> void: _profile_overlay.visible = false)

	_music_slider.value_changed.connect(func(v: float) -> void: _set_bus_volume("Music", v))
	_sfx_slider.value_changed.connect(func(v: float) -> void: _set_bus_volume("SFX", v))
	_sensitivity_slider.value_changed.connect(func(_v: float) -> void: _save_settings())
	_graphics_option.item_selected.connect(func(_i: int) -> void: _apply_graphics(); _save_settings())

	_load_settings()

func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _close_settings() -> void:
	_save_settings()
	_settings_overlay.visible = false

# --- settings ------------------------------------------------------------

func _set_bus_volume(bus_name: String, value_0_1: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# Slider 0..1 -> decibels; mute at the very bottom.
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value_0_1, 0.001)))
	AudioServer.set_bus_mute(idx, value_0_1 <= 0.01)

func _apply_graphics() -> void:
	# Low = render at 70% resolution (real mobile performance gain),
	# High = full resolution. More toggles arrive with real art assets.
	get_tree().root.scaling_3d_scale = 0.7 if _graphics_option.selected == 0 else 1.0

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "music", _music_slider.value)
	cfg.set_value("settings", "sfx", _sfx_slider.value)
	cfg.set_value("settings", "sensitivity", _sensitivity_slider.value)
	cfg.set_value("settings", "graphics", _graphics_option.selected)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_music_slider.value = float(cfg.get_value("settings", "music", 0.8))
	_sfx_slider.value = float(cfg.get_value("settings", "sfx", 0.8))
	_sensitivity_slider.value = float(cfg.get_value("settings", "sensitivity", 1.0))
	_graphics_option.selected = int(cfg.get_value("settings", "graphics", 1))
	_set_bus_volume("Music", _music_slider.value)
	_set_bus_volume("SFX", _sfx_slider.value)
	_apply_graphics()
