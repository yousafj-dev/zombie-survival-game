extends CharacterBody3D

## Zombie AI (Phase 1 skeleton).
## Chases the player using NavigationAgent3D on the game's NavigationRegion3D,
## attacks on contact range with a cooldown, takes damage and dies.
## Boss variant: bigger, slower, much tougher (set is_boss before adding
## to the tree, or call setup(true) right after instantiate()).

signal died(zombie: Node)

@export var speed: float = 2.2
@export var max_health: int = 30
@export var attack_damage: int = 8
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.0

var is_boss: bool = false

var _health: int
var _attack_left: float = 0.0
var _dead: bool = false
var _player: Node3D
var _part_mats: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _flash_left: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _strafe_left: float = 0.0
var _strafe_sign: float = 1.0
var _hit_player: AudioStreamPlayer3D

@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _body: Node3D = $Body

func setup(boss: bool) -> void:
	is_boss = boss

func _ready() -> void:
	add_to_group("zombie")
	# Procedural hit thud (generated in code — no audio files).
	_hit_player = AudioStreamPlayer3D.new()
	_hit_player.bus = &"SFX"
	_hit_player.stream = SfxGen.zombie_hit()
	add_child(_hit_player)
	_health = max_health
	if is_boss:
		_health = max_health * 10
		speed *= 0.7
		attack_damage *= 2
		scale = Vector3.ONE * 1.8
	_player = get_tree().get_first_node_in_group("player")
	# Give every body part its own material copy so hit flashes and the
	# boss tint only affect THIS zombie, not every instance sharing the scene.
	for child in _body.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.get_surface_override_material(0) is StandardMaterial3D:
				var m := (mi.get_surface_override_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(0, m)
				_part_mats.append(m)
				_base_colors.append(m.albedo_color)
	if is_boss:
		# Boss reads clearly: noticeably bigger (scale set above) and red-tinted.
		for i in _part_mats.size():
			var tinted: Color = _base_colors[i].lerp(Color(0.85, 0.12, 0.12), 0.5)
			_part_mats[i].albedo_color = tinted
			_base_colors[i] = tinted
	_last_pos = global_position
	_strafe_sign = 1.0 if randf() > 0.5 else -1.0
	# Navigation maps are ready after the first physics frame.
	await get_tree().physics_frame

func take_damage(amount: int) -> void:
	if _dead:
		return
	_health -= amount
	if _hit_player != null:
		_hit_player.play()
	# Hit feedback: red flash on every body part + a quick squash.
	for m in _part_mats:
		m.albedo_color = Color(1.0, 0.35, 0.3)
	_flash_left = 0.09
	_body.scale = Vector3(1.15, 0.85, 1.15)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
	if _health <= 0:
		_die()

func _die() -> void:
	_dead = true
	died.emit(self)
	queue_free()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	_attack_left = maxf(0.0, _attack_left - delta)

	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			for i in _part_mats.size():
				_part_mats[i].albedo_color = _base_colors[i]

	var dist := global_position.distance_to(_player.global_position)

	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_left <= 0.0 and _player.has_method("take_damage"):
			_attack_left = attack_cooldown
			_player.take_damage(attack_damage)
	else:
		_nav.target_position = _player.global_position
		var next := _nav.get_next_path_position()
		var dir := (next - global_position)
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			# Model faces -Z; map -Z onto the travel direction.
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)
			# Stuck on a wall corner? Strafe sideways briefly to slide free.
			_stuck_time += delta
			if _stuck_time >= 0.5:
				if global_position.distance_to(_last_pos) < 0.25:
					_strafe_left = 0.7
					_strafe_sign = -_strafe_sign
				_last_pos = global_position
				_stuck_time = 0.0
			if _strafe_left > 0.0:
				_strafe_left -= delta
				var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
				velocity.x += side.x * speed * 0.9
				velocity.z += side.z * speed * 0.9

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = -0.1
	move_and_slide()
