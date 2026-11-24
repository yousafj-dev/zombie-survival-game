extends CharacterBody3D

## Player controller (Phase 1 skeleton).
## - Movement comes from the HUD virtual joystick via set_move_input()
##   (keyboard WASD works too, for desktop testing in the editor).
## - The camera rig is top-level: it follows the player from a fixed
##   south/above angle and does NOT rotate with the player mesh.
## - Firing is auto-aim: the nearest zombie inside weapon range is hit,
##   with a physics raycast so walls block shots.
## - Touch look / free camera is a later step.

signal health_changed(current: int, maximum: int)
signal ammo_changed(magazine: int, reserve: int)
signal weapon_changed(weapon_name: String)
signal player_died

@export var max_health: int = 100
@export var move_speed: float = 5.0
@export var turn_speed: float = 10.0

var health: int
var move_input: Vector2 = Vector2.ZERO

var _weapon_index: int = 0
var _mag_ammo: Dictionary = {}     # weapon id -> rounds in magazine
var _reserve_ammo: Dictionary = {} # weapon id -> spare rounds
var _fire_cooldown: float = 0.0
var _reload_left: float = 0.0
var _firing: bool = false
var _dead: bool = false
var _sensitivity: float = 1.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _muzzle: Marker3D = $Muzzle

func _ready() -> void:
	add_to_group("player")
	health = max_health
	for id in Weapons.ORDER:
		_mag_ammo[id] = Weapons.get_weapon(id)["magazine"]
		_reserve_ammo[id] = Weapons.get_weapon(id)["reserve"]
	_load_settings()
	_emit_weapon_signals()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		_sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))

# --- called by the HUD -------------------------------------------------

func set_move_input(v: Vector2) -> void:
	move_input = v

func set_firing(on: bool) -> void:
	_firing = on

func reload() -> void:
	var id := _current_id()
	var data := Weapons.get_weapon(id)
	if _reload_left > 0.0:
		return
	if _mag_ammo[id] >= int(data["magazine"]) or _reserve_ammo[id] <= 0:
		return
	_reload_left = float(data["reload_time"])

func switch_weapon() -> void:
	_weapon_index = (_weapon_index + 1) % Weapons.ORDER.size()
	_reload_left = 0.0
	_emit_weapon_signals()

# --- combat ------------------------------------------------------------

func take_damage(amount: int) -> void:
	if _dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		_dead = true
		player_died.emit()

func heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)

func _current_id() -> String:
	return Weapons.ORDER[_weapon_index]

func _emit_weapon_signals() -> void:
	var id := _current_id()
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])
	weapon_changed.emit(Weapons.get_weapon(id)["name"])
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Camera rig follows from a fixed angle (twin-stick style).
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(global_position, 1.0 - pow(0.0001, delta))

	# Input: joystick first, keyboard fallback for editor testing.
	var input_vec := move_input
	if input_vec == Vector2.ZERO:
		var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
		var kz := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
		input_vec = Vector2(kx, kz).limit_length(1.0)
	if Input.is_physical_key_pressed(KEY_R):
		reload()

	var direction := Vector3(input_vec.x, 0.0, input_vec.y)
	if direction.length() > 0.05:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		var target_yaw := atan2(direction.x, direction.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_yaw, turn_speed * _sensitivity * delta)
		rotation.y = _mesh.rotation.y
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	if not is_on_floor():
		velocity.y -= get_gravity().y * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	# Weapon timers.
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	var wants_fire := _firing or Input.is_physical_key_pressed(KEY_SPACE)
	if wants_fire:
		_try_fire()

func _try_fire() -> void:
	var id := _current_id()
	var data := Weapons.get_weapon(id)
	if _fire_cooldown > 0.0 or _reload_left > 0.0:
		return
	if _mag_ammo[id] <= 0:
		reload()
		return
	_fire_cooldown = 1.0 / float(data["fire_rate"])
	_mag_ammo[id] -= 1
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])

	var target := _find_target(float(data["range"]))
	if target == null:
		return
	# One raycast per pellet, from chest height toward the target's chest.
	var from := _muzzle.global_position
	var target_pos: Vector3 = target.global_position + Vector3.UP * 1.2
	for i in int(data["pellets"]):
		var spread := Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4)) if int(data["pellets"]) > 1 else Vector3.ZERO
		var query := PhysicsRayQueryParameters3D.create(from, target_pos + spread)
		query.collision_mask = 0b0101 # World (1) + Zombie layer (bit 3 = 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == target:
			target.take_damage(int(data["damage"]))

func _find_target(max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_range
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z):
			continue
		var d := global_position.distance_to(z.global_position)
		if d < best_dist:
			best_dist = d
			best = z
	return best

func _finish_reload() -> void:
	var id := _current_id()
	var data := Weapons.get_weapon(id)
	var need := int(data["magazine"]) - _mag_ammo[id]
	var take := mini(need, _reserve_ammo[id])
	_mag_ammo[id] += take
	_reserve_ammo[id] -= take
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])
