extends CharacterBody3D

## Zombie AI.
## Chases the player using NavigationAgent3D on the game's
## NavigationRegion3D, attacks on contact range with a cooldown, takes
## damage and dies.
##
## Four types (setup_type() before add_child): walker, runner, crawler,
## brute. Each loads its real animated model (Vinish.dev, CC BY 4.0 —
## downloaded by CI into res://assets/models/zombies/) and plays its
## walk/run/crawl, attack, hit and death clips. If the model file is
## missing the placeholder body in the scene stays visible instead.
## The brute is the boss: setup(true) makes it the final-wave boss of
## every mission (much more health, bigger, double damage), and the game
## manager shows its health bar via the health_changed signal.

signal died(zombie: Node)
signal health_changed(current: int, maximum: int)

const MODEL_PATHS := {
	"walker": "res://assets/models/zombies/zombie-walker.glb",
	"runner": "res://assets/models/zombies/zombie-runner.glb",
	"brute": "res://assets/models/zombies/zombie-brute.glb",
	"crawler": "res://assets/models/zombies/zombie-crawler.glb",
}

## Base stats per type (before mission scaling and boss multipliers).
## height = the height the model is normalised to, in metres.
## coins  = wallet reward for the kill.
const TYPE_STATS := {
	"walker": {"speed": 2.2, "health": 30, "damage": 8, "range": 1.7, "height": 1.8, "coins": 5, "move_clip": "Walk"},
	"runner": {"speed": 3.7, "health": 20, "damage": 8, "range": 1.7, "height": 1.8, "coins": 8, "move_clip": "Run"},
	"crawler": {"speed": 2.7, "health": 18, "damage": 6, "range": 1.5, "height": 1.05, "coins": 6, "move_clip": "Crawl"},
	"brute": {"speed": 1.7, "health": 120, "damage": 16, "range": 2.6, "height": 2.6, "coins": 100, "move_clip": "Walk"},
}

## The Vinish models face +Z; everything in this project faces -Z.
const MODEL_YAW := PI

@export var speed: float = 2.2
@export var max_health: int = 30
@export var attack_damage: int = 8
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.0

var zombie_type: String = "walker"
var coin_value: int = 5
var is_boss: bool = false
var _mission: int = 1

var _health: int
var _full_health: int
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
var _anim: AnimationPlayer
var _move_clip: String = "Walk"
var _clip_lock: float = 0.0

@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _body: Node3D = $Body

func setup(boss: bool) -> void:
	is_boss = boss

## Called by the game manager (before add_child) with the zombie type.
func setup_type(t: String) -> void:
	if TYPE_STATS.has(t):
		zombie_type = t

## Called by the game manager (before add_child) with the mission number.
## Stats are scaled from it in _ready.
func setup_mission(m: int) -> void:
	_mission = maxi(1, m)

func get_health() -> int:
	return _health

func get_max_health() -> int:
	return _full_health

func _ready() -> void:
	add_to_group("zombie")
	# Procedural hit thud (generated in code — no audio files).
	_hit_player = AudioStreamPlayer3D.new()
	_hit_player.bus = &"SFX"
	_hit_player.stream = SfxGen.zombie_hit()
	add_child(_hit_player)
	# Type stats first…
	var stats: Dictionary = TYPE_STATS[zombie_type]
	speed = float(stats["speed"])
	max_health = int(stats["health"])
	attack_damage = int(stats["damage"])
	attack_range = float(stats["range"])
	coin_value = int(stats["coins"])
	_move_clip = str(stats["move_clip"])
	# …then mission scaling ("bilkul tuff"): +30% health per mission
	# (compounding), +5% speed per mission (hard cap 1.6x base),
	# +1 attack damage per mission. Boss multipliers stack on top.
	var steps := float(_mission - 1)
	max_health = int(round(float(max_health) * pow(1.3, steps)))
	speed = speed * minf(1.0 + 0.05 * steps, 1.6)
	attack_damage = attack_damage + (_mission - 1)
	_health = max_health
	if is_boss:
		_health = max_health * 10
		speed *= 0.7
		attack_damage *= 2
		scale = Vector3.ONE * (1.35 if zombie_type == "brute" else 1.8)
	_full_health = _health
	# The real model (or the placeholder body, if the file is absent).
	var model := _load_model(stats)
	_collect_flash_materials(model if model != null else _body)
	if is_boss:
		# Boss reads clearly: noticeably bigger (scale set above) and
		# red-tinted.
		for i in _part_mats.size():
			var tinted: Color = _base_colors[i].lerp(Color(0.85, 0.12, 0.12), 0.5)
			_part_mats[i].albedo_color = tinted
			_base_colors[i] = tinted
	_player = get_tree().get_first_node_in_group("player")
	health_changed.emit(_health, _full_health)
	_last_pos = global_position
	_strafe_sign = 1.0 if randf() > 0.5 else -1.0
	# Navigation maps are ready after the first physics frame.
	await get_tree().physics_frame

## Instances the type's GLB under Body, normalised to the type height.
## Returns the model instance, or null when the file is missing (the
## placeholder body then stays visible and the game plays as before).
func _load_model(stats: Dictionary) -> Node:
	var path := str(MODEL_PATHS.get(zombie_type, ""))
	if path.is_empty():
		return null
	var inst := ModelUtil.load_model(path)
	if inst == null:
		return null
	var holder := Node3D.new()
	holder.name = "ModelRoot"
	holder.rotation.y = MODEL_YAW
	_body.add_child(holder)
	holder.add_child(inst)
	var aabb := ModelUtil.model_aabb(inst)
	if aabb.size.y > 0.01:
		var s := float(stats["height"]) / aabb.size.y
		holder.scale = Vector3.ONE * s
		holder.position.y = -aabb.position.y * s
	# The placeholder body parts retire; only the model shows.
	for child in _body.get_children():
		if child != holder and child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	_anim = ModelUtil.find_animation_player(inst)
	if _anim != null:
		ModelUtil.set_looping(_anim, ["Idle", "Walk", "Run", "Crawl"])
		_play_clip(_move_clip, 0.0)
	return inst

## Give every visible mesh surface its own material copy so hit flashes
## and the boss tint only affect THIS zombie, not every instance that
## shares the model resource. Remembers each surface's base tint.
func _collect_flash_materials(from: Node) -> void:
	_part_mats.clear()
	_base_colors.clear()
	var stack: Array = [from]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var active := mi.get_active_material(s)
					if active is StandardMaterial3D:
						var m := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(s, m)
						_part_mats.append(m)
						_base_colors.append(m.albedo_color)
		for c in n.get_children():
			stack.append(c)

func _play_clip(clip: String, lock: float) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if _anim.current_animation != clip:
		_anim.play(clip)
	_clip_lock = lock

func take_damage(amount: int) -> void:
	if _dead:
		return
	_health -= amount
	health_changed.emit(maxi(0, _health), _full_health)
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
	elif _clip_lock <= 0.0:
		_play_clip("Hit", 0.3)

func _die() -> void:
	_dead = true
	died.emit(self)
	health_changed.emit(0, _full_health)
	velocity = Vector3.ZERO
	# The corpse must not block the player, other zombies or shots.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)
	# Death clip plays, then the body is cleaned up. The timer also runs
	# while the tree is paused (mission result panel), and the validity
	# check keeps it harmless if the scene changed first.
	_play_clip("Death", 999.0)
	var timer := get_tree().create_timer(1.4, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	_attack_left = maxf(0.0, _attack_left - delta)
	_clip_lock = maxf(0.0, _clip_lock - delta)

	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			for i in _part_mats.size():
				_part_mats[i].albedo_color = _base_colors[i]

	var dist := global_position.distance_to(_player.global_position)

	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _clip_lock <= 0.0:
			_play_clip("Idle", 0.0)
		if _attack_left <= 0.0 and _player.has_method("take_damage"):
			_attack_left = attack_cooldown
			_player.take_damage(attack_damage)
			if _anim != null and _anim.has_animation("Attack"):
				_play_clip("Attack", minf(_anim.get_animation("Attack").length, 1.0))
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
			if _clip_lock <= 0.0:
				_play_clip(_move_clip, 0.0)
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
