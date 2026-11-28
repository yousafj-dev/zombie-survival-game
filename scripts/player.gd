extends CharacterBody3D

## Player controller — FIRST PERSON (look-fix round 3).
## - The camera sits at eye height (1.62 m) inside the player: yaw is
##   the player body's rotation, pitch is the CameraPivot's rotation.
##   You see what the soldier sees — no camera above the head.
## - Movement comes from the HUD virtual joystick via set_move_input()
##   and is relative to the look direction (keyboard WASD works too,
##   arrow keys turn/pitch the view, for desktop testing).
## - Look comes from the HUD: dragging on the right half of the screen
##   calls add_look_input() with the drag delta in pixels.
## - The equipped gun is a viewmodel attached to the camera (bottom
##   right); the soldier body itself is hidden during gameplay so it
##   can never block the view. The lobby showcase is a separate scene
##   and still shows the full body.
## - Firing is a hitscan ray from the camera centre (the crosshair),
##   with a small aim-assist cone that snaps a near-miss onto a zombie.

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

## First-person tuning.
const EYE_HEIGHT := 1.62 # metres — matches the CameraPivot in the scene
const LOOK_SPEED := 0.0026 # radians of turn per pixel of drag (x sensitivity)
const PITCH_LIMIT := 1.047 # ±60 degrees
const ASSIST_CONE := 0.061 # ~3.5 degrees of aim assist around the crosshair
## The gun viewmodel hangs off the camera here — right of centre,
## angled in toward the crosshair, clear of the HUD button cluster
## (which owns the bottom-right corner on mobile).
const VM_POSITION := Vector3(0.22, -0.20, -0.62)
const VM_SCALE := 0.55
## Muzzle-flash light position inside each gun model's local space
## (just past the barrel tip).
const VM_FLASH_POS := {
	"pistol": Vector3(0, 0.07, -0.42),
	"rifle": Vector3(0, 0.05, -0.95),
	"shotgun": Vector3(0, 0.06, -0.9),
}

@export var max_health: int = 100
@export var move_speed: float = 5.0
@export var turn_speed: float = 10.0

var health: int
var move_input: Vector2 = Vector2.ZERO

## View direction in radians. Yaw turns the whole body; pitch tilts
## only the camera pivot. Public so the HUD/tests can drive them.
var look_yaw: float = 0.0
var look_pitch: float = 0.0

var _weapon_index: int = 0
var _mag_ammo: Dictionary = {}     # weapon id -> rounds in magazine
var _reserve_ammo: Dictionary = {} # weapon id -> spare rounds
var _fire_cooldown: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 1.0
var _firing: bool = false
var _dead: bool = false
var _sensitivity: float = 1.0
var _flash_left: float = 0.0
var _flash: OmniLight3D = null # the CURRENT gun's viewmodel flash
var _shot_player: AudioStreamPlayer3D
var _reload_player: AudioStreamPlayer3D
var _wdata: Dictionary = {} # weapon id -> stats with lobby upgrades applied
var _anim: AnimationPlayer
var _shot_age: float = 99.0 # seconds since the last shot (drives the aim pose)
var _vm_root: Node3D
var _vm_guns: Dictionary = {}    # weapon id -> viewmodel gun node
var _vm_flashes: Dictionary = {} # weapon id -> viewmodel flash light
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0

@onready var _body: Node3D = $Body
@onready var _guns: Dictionary = {
	"pistol": $Body/GunMount/PistolModel,
	"rifle": $Body/GunMount/RifleModel,
	"shotgun": $Body/GunMount/ShotgunModel,
}
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D

func _ready() -> void:
	add_to_group("player")
	# First person: the camera is a child at eye height and starts
	# looking straight ahead along the body's facing.
	_camera.current = true
	look_yaw = rotation.y
	_apply_look()
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
	_build_viewmodel()
	_load_hero()
	# The soldier's own body must never block the eye-level view, so
	# the whole Body (hero model + in-hand gun) stays hidden in play.
	# The lobby showcase is a different scene and is unaffected.
	_body.visible = false
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

# --- look ------------------------------------------------------------------

## Called by the HUD with a screen-drag delta in pixels (and by tests).
## Dragging right turns right; dragging up looks up. Sensitivity is the
## player's Settings value.
func add_look_input(delta_px: Vector2) -> void:
	if _dead:
		return
	look_yaw -= delta_px.x * LOOK_SPEED * _sensitivity
	look_pitch = clampf(look_pitch - delta_px.y * LOOK_SPEED * _sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	_apply_look()

func _apply_look() -> void:
	rotation.y = look_yaw
	if _camera_pivot != null:
		_camera_pivot.rotation.x = look_pitch

# --- gun viewmodel -----------------------------------------------------------
## Duplicates of the three gun models hang off the camera, bottom-right,
## barrels forward (-Z is the camera's forward). Each carries its own
## muzzle-flash light at the barrel tip. Switching weapons swaps which
## viewmodel is visible; _flash always points at the current one.

func _build_viewmodel() -> void:
	_vm_root = Node3D.new()
	_vm_root.name = "ViewModel"
	_vm_root.position = VM_POSITION
	_vm_root.scale = Vector3.ONE * VM_SCALE
	_camera.add_child(_vm_root)
	for id in Weapons.ORDER:
		var dup := (_guns[id] as Node3D).duplicate() as Node3D
		dup.name = str(id) + "ViewModel"
		dup.visible = false
		# The dusk scene light leaves the dark gunmetal nearly black;
		# the viewmodel gets brightened copies of the gun materials so
		# the gun reads clearly in the player's hands.
		_brighten_viewmodel(dup)
		_vm_root.add_child(dup)
		_vm_guns[id] = dup
		var flash := OmniLight3D.new()
		flash.name = "ViewMuzzleFlash"
		flash.position = VM_FLASH_POS[id]
		flash.light_color = Color(1, 0.62, 0.25, 1)
		flash.light_energy = 3.0
		flash.omni_range = 3.5
		flash.visible = false
		dup.add_child(flash)
		_vm_flashes[id] = flash

## Gives every mesh in a viewmodel gun a brightened duplicate of its
## material (the originals stay untouched for the hidden body guns).
func _brighten_viewmodel(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var active := mi.get_active_material(s)
					if active is StandardMaterial3D:
						var m := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
						var c := m.albedo_color
						m.albedo_color = Color(minf(1.0, c.r * 1.8), minf(1.0, c.g * 1.8), minf(1.0, c.b * 1.8), c.a)
						mi.set_surface_override_material(s, m)
		for c in n.get_children():
			stack.append(c)

## Gentle life for the viewmodel: a soft bob while moving and a quick
## dip-and-return while a reload runs. Purely cosmetic.
func _process(delta: float) -> void:
	if _vm_root == null:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.4 and is_on_floor() and not _dead
	_bob_amount = move_toward(_bob_amount, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_bob_phase += delta * 9.0
	var dip := 0.0
	if _reload_left > 0.0 and _reload_total > 0.0:
		dip = sin((1.0 - _reload_left / _reload_total) * PI)
	_vm_root.position = VM_POSITION + Vector3(
		cos(_bob_phase) * 0.007 * _bob_amount,
		sin(_bob_phase * 2.0) * 0.011 * _bob_amount - dip * 0.16,
		0.0)
	_vm_root.rotation.x = -dip * 0.45

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
	_reload_total = _reload_left

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
	for key in _vm_guns.keys():
		(_vm_guns[key] as Node3D).visible = str(key) == current
	if _vm_flashes.has(current):
		_flash = _vm_flashes[current]

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

	_apply_look()

	# Desktop testing: arrow keys turn / tilt the view.
	if Input.is_physical_key_pressed(KEY_LEFT):
		look_yaw += 2.0 * delta
	if Input.is_physical_key_pressed(KEY_RIGHT):
		look_yaw -= 2.0 * delta
	if Input.is_physical_key_pressed(KEY_UP):
		look_pitch = clampf(look_pitch + 1.2 * delta, -PITCH_LIMIT, PITCH_LIMIT)
	if Input.is_physical_key_pressed(KEY_DOWN):
		look_pitch = clampf(look_pitch - 1.2 * delta, -PITCH_LIMIT, PITCH_LIMIT)
	_apply_look()

	# Input: joystick first, keyboard fallback for editor testing.
	var input_vec := move_input
	if input_vec == Vector2.ZERO:
		var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
		var kz := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
		input_vec = Vector2(kx, kz).limit_length(1.0)
	if Input.is_physical_key_pressed(KEY_R):
		reload()

	# Movement is relative to where the player is looking: joystick up
	# walks toward the crosshair, sideways strafes. (The basis carries
	# yaw only — pitch lives on the camera pivot.)
	var direction := transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)
	direction.y = 0.0
	if direction.length() > 0.05:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
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
		if _flash_left <= 0.0 and _flash != null:
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

	# Hero animation: run while moving, idle otherwise. (The body is
	# hidden in first person, but the state stays correct — and the
	# lobby/tests can still read it.)
	_shot_age += delta
	if _anim != null:
		var clip := "Idle"
		if Vector2(velocity.x, velocity.z).length() > 0.4:
			clip = "Run"
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
	if _flash != null:
		_flash.visible = true
	_flash_left = 0.05
	_shot_player.play()
	_shot_age = 0.0

	# Hitscan from the camera centre — what the crosshair touches is
	# what gets shot. Walls block the ray (World is in the mask).
	var from := _camera.global_position
	var basis := _camera.global_transform.basis
	var fwd := -basis.z
	var range := float(data["range"])
	var pellets := int(data["pellets"])
	var space := get_world_3d().direct_space_state
	var any_hit := false
	for i in pellets:
		var dir := fwd
		if pellets > 1:
			# Shotgun spread: a small random cone around the crosshair.
			dir = (fwd + basis.x * randf_range(-0.05, 0.05) + basis.y * randf_range(-0.05, 0.05)).normalized()
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * range)
		query.collision_mask = 0b0101 # World (1) + Zombie layer (bit 3 = 4)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit.collider as Node).is_in_group("zombie"):
			(hit.collider as Node).take_damage(int(data["damage"]))
			any_hit = true
	if not any_hit and pellets == 1:
		# Aim assist: a zombie whose chest sits inside a small cone
		# around the crosshair (and is actually visible from here)
		# takes the hit — thumb aiming needs the help.
		var assisted := _aim_assist(from, fwd, range, space)
		if assisted != null:
			assisted.take_damage(int(data["damage"]))
			any_hit = true
	if any_hit:
		hit_landed.emit()

## The nearest-to-crosshair zombie inside the assist cone, with a
## clear line of sight from the camera. Null when there is none.
func _aim_assist(from: Vector3, fwd: Vector3, range: float, space: PhysicsDirectSpaceState3D) -> Node:
	var best: Node = null
	var best_ang := ASSIST_CONE
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z) or bool(z.get("_dead")):
			continue
		# Aim point: the spot on the zombie's body axis level with the
		# camera (bounded to the body) — the cone measures how close
		# the crosshair ray passes to the zombie itself, so plain
		# eye-height drop over distance never eats the whole cone.
		var aim_y := clampf(EYE_HEIGHT, 0.5, 1.6)
		var chest: Vector3 = (z as Node3D).global_position + Vector3(0.0, aim_y, 0.0)
		var to := chest - from
		var dist := to.length()
		if dist > range or dist < 0.01:
			continue
		var ang := fwd.angle_to(to / dist)
		if ang >= best_ang:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, chest)
		query.collision_mask = 0b0101
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit.collider == z:
			best_ang = ang
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

## Instances the soldier hero under Body and moves the gun mount into
## the hero's right hand bone. The body is hidden during first-person
## play (see _ready), but the model + animation state stay loaded so
## nothing else changes. If the model file is missing, the game plays
## exactly as before (in first person the body is never seen anyway).
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
