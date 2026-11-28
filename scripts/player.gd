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
signal hit_landed
signal took_damage

## The real hero model (Vinish.dev "Soldier", CC BY 4.0 — downloaded by
## CI into res://assets/models/player/). An adult soldier in woodland
## camo with Idle/Walk/Run clips, 1.824 m in raw units, scaled to the
## 1.8 m the capsule/gameplay assume.
## The model faces +Z; everything in this project faces -Z.
const HERO_PATH := "res://assets/models/player/soldier.glb"
const HERO_SCALE := 0.987
const MODEL_YAW := PI
## The soldier carries no built-in hand props; nothing to hide.
const PROP_MESHES: Array[String] = []
## Where the gun mount sits inside the right hand (Hand_R) bone. Tuned
## against render captures of the real model holding each gun.
const GUN_MOUNT_POSITION := Vector3(0.0, 0.0, 0.0)
# Solved numerically against the soldier's Hand_R bone in the Idle
# pose and verified top-down + numerically: with this rotation the
# barrel points exactly along the hero's forward (0, 0, -1) while the
# grip sits in his right hand (identity left it sideways).
const GUN_MOUNT_ROTATION := Vector3(-0.0647, 3.0508, 0.6645)

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
var _flash_left: float = 0.0
var _shot_player: AudioStreamPlayer3D
var _reload_player: AudioStreamPlayer3D
var _wdata: Dictionary = {} # weapon id -> stats with lobby upgrades applied
var _anim: AnimationPlayer
var _shot_age: float = 99.0 # seconds since the last shot (drives the aim pose)

@onready var _body: Node3D = $Body
@onready var _flash: OmniLight3D = $Body/GunMount/MuzzleFlash
@onready var _guns: Dictionary = {
	"pistol": $Body/GunMount/PistolModel,
	"rifle": $Body/GunMount/RifleModel,
	"shotgun": $Body/GunMount/ShotgunModel,
}
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _muzzle: Marker3D = $Muzzle

func _ready() -> void:
	add_to_group("player")
	# Camera angle is set in code on purpose: the fixed follow camera must
	# pitch DOWN ~51 degrees at the player. (A transposed basis in the scene
	# file once pitched it up at the sky and shipped an empty screen.)
	var cam := _camera_pivot.get_node("Camera3D") as Camera3D
	cam.rotation_degrees = Vector3(-51, 0, 0)
	cam.current = true
	health = max_health
	for id in Weapons.ORDER:
		_wdata[id] = Weapons.get_upgraded(id)
		_mag_ammo[id] = _wdata[id]["magazine"]
		_reserve_ammo[id] = _wdata[id]["reserve"]
	# Procedural sound effects (generated in code — no audio files).
	_shot_player = AudioStreamPlayer3D.new()
	_shot_player.bus = &"SFX"
	_shot_player.stream = SfxGen.gunshot()
	add_child(_shot_player)
	_reload_player = AudioStreamPlayer3D.new()
	_reload_player.bus = &"SFX"
	_reload_player.stream = SfxGen.reload_click()
	add_child(_reload_player)
	_load_settings()
	_load_hero()
	_update_gun_visibility()
	_emit_weapon_signals()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		_sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))
		# The gun picked in the lobby is the gun the run starts with.
		var wid := str(cfg.get_value("settings", "starting_weapon", ""))
		var idx := Weapons.ORDER.find(wid)
		if idx >= 0:
			_weapon_index = idx
		# The lobby's Sound toggle mutes the Master bus; apply it here too
		# so the choice holds even if the game scene is entered directly.
		AudioServer.set_bus_mute(0, not bool(cfg.get_value("settings", "sound", true)))

# --- called by the HUD -------------------------------------------------

func set_move_input(v: Vector2) -> void:
	move_input = v

func set_firing(on: bool) -> void:
	_firing = on

func reload() -> void:
	var id := _current_id()
	var data: Dictionary = _wdata[id]
	if _reload_left > 0.0:
		return
	if _mag_ammo[id] >= int(data["magazine"]) or _reserve_ammo[id] <= 0:
		return
	_reload_left = float(data["reload_time"])

func switch_weapon() -> void:
	_weapon_index = (_weapon_index + 1) % Weapons.ORDER.size()
	_reload_left = 0.0
	_update_gun_visibility()
	_emit_weapon_signals()

func _update_gun_visibility() -> void:
	var current := _current_id()
	for key in _guns.keys():
		var gun: Node3D = _guns[key]
		gun.visible = str(key) == current

# --- combat ------------------------------------------------------------

func take_damage(amount: int) -> void:
	if _dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	took_damage.emit()
	if health <= 0:
		_dead = true
		player_died.emit()

func heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)

## Ammo pickup: a refill for every weapon's reserve.
func add_ammo_pickup() -> void:
	_reserve_ammo["pistol"] = int(_reserve_ammo["pistol"]) + 24
	_reserve_ammo["rifle"] = int(_reserve_ammo["rifle"]) + 60
	_reserve_ammo["shotgun"] = int(_reserve_ammo["shotgun"]) + 12
	var id := _current_id()
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])

func _current_id() -> String:
	return Weapons.ORDER[_weapon_index]

func _emit_weapon_signals() -> void:
	var id := _current_id()
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])
	weapon_changed.emit(_wdata[id]["name"])
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
		# The model is built facing -Z, so yaw must map -Z onto the move dir.
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * _sensitivity * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	# Muzzle flash timer.
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false

	# Weapon timers.
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	var wants_fire := _firing or Input.is_physical_key_pressed(KEY_SPACE)
	if wants_fire:
		_try_fire()

	# Hero animation: run while moving, aim pose just after a shot,
	# idle otherwise.
	_shot_age += delta
	if _anim != null:
		var clip := "Idle"
		if Vector2(velocity.x, velocity.z).length() > 0.4:
			clip = "Run"
		elif _shot_age < 0.35:
			clip = "Idle"
		_play_clip(clip)

func _try_fire() -> void:
	var id := _current_id()
	var data: Dictionary = _wdata[id]
	if _fire_cooldown > 0.0 or _reload_left > 0.0:
		return
	if _mag_ammo[id] <= 0:
		reload()
		return
	_fire_cooldown = 1.0 / float(data["fire_rate"])
	_mag_ammo[id] -= 1
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])
	_flash.visible = true
	_flash_left = 0.05
	_shot_player.play()
	_shot_age = 0.0

	var target := _find_target(float(data["range"]))
	if target == null:
		return
	# One raycast per pellet, from chest height toward the target's chest.
	var from := _muzzle.global_position
	var target_pos: Vector3 = target.global_position + Vector3.UP * 1.2
	var any_hit := false
	for i in int(data["pellets"]):
		var spread := Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4)) if int(data["pellets"]) > 1 else Vector3.ZERO
		var query := PhysicsRayQueryParameters3D.create(from, target_pos + spread)
		query.collision_mask = 0b0101 # World (1) + Zombie layer (bit 3 = 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == target:
			any_hit = true
			target.take_damage(int(data["damage"]))
	if any_hit:
		hit_landed.emit()

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
	var data: Dictionary = _wdata[id]
	var need: int = int(data["magazine"]) - int(_mag_ammo[id])
	var take: int = mini(need, int(_reserve_ammo[id]))
	_mag_ammo[id] += take
	_reserve_ammo[id] -= take
	ammo_changed.emit(_mag_ammo[id], _reserve_ammo[id])
	_reload_player.play()

# --- hero model ----------------------------------------------------------

## Instances the soldier hero under Body, hides the placeholder body
## parts, and moves the gun mount into the hero's right hand bone so
## the gun follows the hand animation.
## If the model file is missing, the placeholder body stays and the
## game plays exactly as before.
func _load_hero() -> void:
	var inst := ModelUtil.load_model(HERO_PATH)
	if inst == null:
		return
	var holder := Node3D.new()
	holder.name = "ModelRoot"
	holder.scale = Vector3.ONE * HERO_SCALE
	holder.rotation.y = MODEL_YAW
	_body.add_child(holder)
	holder.add_child(inst)
	for prop in PROP_MESHES:
		var n := inst.find_child(prop, true, false)
		if n is Node3D:
			(n as Node3D).visible = false
	for child in _body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	_anim = ModelUtil.find_animation_player(inst)
	if _anim != null:
		ModelUtil.set_looping(_anim, ["Idle", "Run", "Walk"])
		_play_clip("Idle")
	_attach_gun_to_hand(inst)

func _attach_gun_to_hand(inst: Node) -> void:
	var skel := ModelUtil.find_skeleton(inst)
	if skel == null or skel.find_bone("Hand_R") < 0:
		return
	var mount := (_guns["pistol"] as Node3D).get_parent() as Node3D
	if mount == null:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Hand_R"
	skel.add_child(attach)
	mount.get_parent().remove_child(mount)
	attach.add_child(mount)
	mount.position = GUN_MOUNT_POSITION
	mount.rotation = GUN_MOUNT_ROTATION

func _play_clip(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip)
