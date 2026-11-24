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

@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D

func setup(boss: bool) -> void:
	is_boss = boss

func _ready() -> void:
	add_to_group("zombie")
	_health = max_health
	if is_boss:
		_health = max_health * 10
		speed *= 0.7
		attack_damage *= 2
		scale = Vector3.ONE * 1.8
	_player = get_tree().get_first_node_in_group("player")
	# Navigation maps are ready after the first physics frame.
	await get_tree().physics_frame

func take_damage(amount: int) -> void:
	if _dead:
		return
	_health -= amount
	# Simple hit feedback: quick squash. Real animation comes with models.
	_mesh.scale = Vector3(1.15, 0.85, 1.15)
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.12)
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
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)

	if not is_on_floor():
		velocity.y -= get_gravity().y * delta
	else:
		velocity.y = -0.1
	move_and_slide()
