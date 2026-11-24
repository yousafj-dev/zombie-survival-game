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

func _ready() -> void:
	add_to_group("hud")
	_message_label.visible = false
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
