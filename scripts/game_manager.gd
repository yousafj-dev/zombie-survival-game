extends Node3D

## Wave manager for the Dead City level (Phase 1 skeleton).
## - Spawns zombies at the Marker3D nodes in group "spawn_point".
## - Each wave has more zombies than the last; the final wave adds a boss.
## - Between waves there is a short intermission. Clearing the final wave
##   wins the run; player death restarts the scene.

@export var zombie_scene: PackedScene
@export var total_waves: int = 5
@export var first_wave_count: int = 3
@export var count_growth: int = 2
@export var spawn_interval: float = 1.2
@export var intermission: float = 4.0

var _wave: int = 0
var _alive: int = 0
var _spawning: bool = false
var _run_over: bool = false
var _spawn_points: Array[Node3D] = []

func _ready() -> void:
	add_to_group("game_manager")
	for p in get_tree().get_nodes_in_group("spawn_point"):
		_spawn_points.append(p)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)
	_start_next_wave.call_deferred()

func _start_next_wave() -> void:
	if _run_over:
		return
	_wave += 1
	if _wave > total_waves:
		_run_over = true
		get_tree().call_group("hud", "show_message", "YOU SURVIVED ALL WAVES!", 6.0)
		return
	var is_final := _wave == total_waves
	get_tree().call_group("hud", "show_message", "FINAL WAVE — BOSS!" if is_final else "WAVE %d" % _wave, 2.5)
	await get_tree().create_timer(intermission).timeout
	_spawn_wave(is_final)

func _spawn_wave(is_final: bool) -> void:
	_spawning = true
	var count := first_wave_count + (_wave - 1) * count_growth
	for i in count:
		_spawn_zombie(false)
		await get_tree().create_timer(spawn_interval).timeout
	if is_final:
		_spawn_zombie(true)
	_spawning = false
	_update_hud()

func _spawn_zombie(boss: bool) -> void:
	if zombie_scene == null or _spawn_points.is_empty():
		return
	var z := zombie_scene.instantiate()
	if z.has_method("setup"):
		z.setup(boss)
	var point := _spawn_points[randi() % _spawn_points.size()]
	add_child(z)
	z.global_position = point.global_position + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.5, 1.5))
	z.died.connect(_on_zombie_died)
	_alive += 1
	_update_hud()

func _on_zombie_died(_zombie: Node) -> void:
	_alive = maxi(0, _alive - 1)
	_update_hud()
	if _alive == 0 and not _spawning and not _run_over:
		_start_next_wave()

func _on_player_died() -> void:
	_run_over = true
	get_tree().call_group("hud", "show_message", "YOU DIED", 3.0)
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()

func _update_hud() -> void:
	get_tree().call_group("hud", "set_wave_text", _wave, total_waves, _alive)
