extends Node3D

## Mission manager for the Dead City level.
## - A MISSION is the full set of waves. Clearing every wave wins the
##   mission; dying fails it. Both endings show the HUD result panel and
##   wait for the player's choice (next / retry / lobby) — no auto reload.
## - Missions scale ("bilkul tuff"): mission M adds (M-1)*2 zombies to
##   every wave, and zombies get tougher via setup_mission() (health,
##   speed, damage). The final wave of every mission has a boss.
## - The mission number comes from user://settings.cfg
##   (progress/selected_mission, falling back to progress/highest_mission)
##   — the lobby's mission selector writes it. Winning unlocks M+1.

const SETTINGS_PATH := "user://settings.cfg"
const MENU_SCENE := "res://scenes/main_menu.tscn"

@export var zombie_scene: PackedScene
@export var total_waves: int = 5
@export var first_wave_count: int = 3
@export var count_growth: int = 2
@export var spawn_interval: float = 1.2
@export var intermission: float = 4.0
@export var mission: int = 1

var _wave: int = 0
var _alive: int = 0
var _spawning: bool = false
var _run_over: bool = false
var _spawn_points: Array[Node3D] = []
var _run_coins: int = 0
var _boss: Node = null

func _ready() -> void:
	add_to_group("game_manager")
	mission = _read_mission_from_settings()
	for p in get_tree().get_nodes_in_group("spawn_point"):
		_spawn_points.append(p)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)
	get_tree().call_group("hud", "set_coins", Wallet.get_coins())
	_start_next_wave.call_deferred()

func _read_mission_from_settings() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		if cfg.has_section_key("progress", "selected_mission"):
			return maxi(1, int(cfg.get_value("progress", "selected_mission")))
		if cfg.has_section_key("progress", "highest_mission"):
			return maxi(1, int(cfg.get_value("progress", "highest_mission")))
	return maxi(1, mission)

func _wave_count(w: int) -> int:
	# Mission scaling: every mission up adds 2 zombies to EVERY wave,
	# on top of the normal +count_growth between waves.
	return first_wave_count + (mission - 1) * 2 + (w - 1) * count_growth

func _start_next_wave() -> void:
	if _run_over:
		return
	_wave += 1
	if _wave > total_waves:
		_mission_complete()
		return
	var is_final := _wave == total_waves
	var msg := "FINAL WAVE — BOSS!" if is_final else "WAVE %d" % _wave
	if _wave == 1 and not is_final:
		msg = "MISSION %d — WAVE 1" % mission
	get_tree().call_group("hud", "show_message", msg, 2.5)
	await get_tree().create_timer(intermission).timeout
	_spawn_wave(is_final)

func _spawn_wave(is_final: bool) -> void:
	_spawning = true
	var count := _wave_count(_wave)
	for i in count:
		_spawn_zombie(false)
		await get_tree().create_timer(spawn_interval).timeout
	if is_final:
		_spawn_zombie(true)
	_spawning = false
	_update_hud()

## Zombie type mix per wave: wave 1 is walkers only; runners join from
## wave 2; crawlers from wave 3. The final wave's boss is always a brute.
func _pick_type() -> String:
	if _wave <= 1:
		return "walker"
	var r := randf()
	if _wave == 2:
		return "runner" if r < 0.25 else "walker"
	if r < 0.20:
		return "crawler"
	if r < 0.45:
		return "runner"
	return "walker"

func _spawn_zombie(boss: bool) -> void:
	if zombie_scene == null or _spawn_points.is_empty():
		return
	var z := zombie_scene.instantiate()
	if z.has_method("setup"):
		z.setup(boss)
	if z.has_method("setup_type"):
		z.setup_type("brute" if boss else _pick_type())
	if z.has_method("setup_mission"):
		z.setup_mission(mission)
	var point := _spawn_points[randi() % _spawn_points.size()]
	add_child(z)
	z.global_position = point.global_position + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.5, 1.5))
	z.died.connect(_on_zombie_died)
	_alive += 1
	if boss:
		_boss = z
		if z.has_signal("health_changed"):
			z.health_changed.connect(_on_boss_health_changed)
		get_tree().call_group("hud", "show_boss_bar", "BRUTE — BOSS")
		if z.has_method("get_health") and z.has_method("get_max_health"):
			get_tree().call_group("hud", "set_boss_health", z.get_health(), z.get_max_health())
	_update_hud()

func _on_boss_health_changed(current: int, maximum: int) -> void:
	get_tree().call_group("hud", "set_boss_health", current, maximum)

func _on_zombie_died(zombie: Node) -> void:
	_alive = maxi(0, _alive - 1)
	# Every kill pays its coin value into the wallet, exactly once —
	# this handler is the only place kill coins are awarded.
	var value := int(zombie.get("coin_value")) if zombie.get("coin_value") != null else 0
	if value > 0:
		Wallet.add_coins(value)
		_run_coins += value
		get_tree().call_group("hud", "set_coins", Wallet.get_coins())
	if zombie == _boss:
		_boss = null
		get_tree().call_group("hud", "hide_boss_bar")
	_update_hud()
	if _alive == 0 and not _spawning and not _run_over:
		_start_next_wave()

func _on_player_died() -> void:
	if _run_over:
		return
	_run_over = true
	get_tree().call_group("hud", "show_result", false, mission, _run_coins)
	get_tree().paused = true

# --- mission results (win / death panels wait for the player) ------------

func _mission_complete() -> void:
	if _run_over:
		return
	_run_over = true
	# Winning unlocks the next mission.
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var highest := int(cfg.get_value("progress", "highest_mission", 1))
	cfg.set_value("progress", "highest_mission", maxi(highest, mission + 1))
	cfg.save(SETTINGS_PATH)
	# …and pays a mission bonus into the wallet.
	var bonus := 50 + 25 * (mission - 1)
	Wallet.add_coins(bonus)
	_run_coins += bonus
	get_tree().call_group("hud", "set_coins", Wallet.get_coins())
	get_tree().call_group("hud", "show_result", true, mission, _run_coins)
	get_tree().paused = true

func next_mission() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("progress", "selected_mission", mission + 1)
	cfg.save(SETTINGS_PATH)
	get_tree().paused = false
	get_tree().reload_current_scene()

func retry_mission() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func back_to_lobby() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _update_hud() -> void:
	get_tree().call_group("hud", "set_wave_text", _wave, total_waves, _alive)
