extends Area3D

## Ground pickup. A medkit heals the player; an ammo box refills every
## weapon's reserve. Walking over one applies it (a medkit is only
## consumed when the player is actually hurt), plays a chime, hides the
## item, and respawns it after a delay. The visuals are small primitive
## builds with a glowing disc, so they read clearly from the high
## gameplay camera and need no downloaded model.

@export var kind: String = "medkit" # "medkit" or "ammo"
@export var respawn_time: float = 20.0
@export var heal_amount: int = 40

var _active := true
var _visual: Node3D
var _timer: Timer
var _spin: float = 0.0
var _sfx: AudioStreamPlayer3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # the Player layer
	_build_visual()
	_sfx = AudioStreamPlayer3D.new()
	_sfx.bus = &"SFX"
	_sfx.stream = SfxGen.pickup()
	add_child(_sfx)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = respawn_time
	_timer.timeout.connect(_reactivate)
	add_child(_timer)
	body_entered.connect(_on_body_entered)

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, 0.55, 0.0)
	add_child(_visual)
	if kind == "ammo":
		_add_box(Vector3(0.62, 0.34, 0.44), Vector3.ZERO, Color(0.32, 0.36, 0.18))
		_add_box(Vector3(0.64, 0.1, 0.46), Vector3(0.0, 0.2, 0.0), Color(0.55, 0.5, 0.2))
	else:
		_add_box(Vector3(0.56, 0.36, 0.56), Vector3.ZERO, Color(0.92, 0.92, 0.9))
		_add_box(Vector3(0.34, 0.1, 0.12), Vector3(0.0, 0.2, 0.0), Color(0.85, 0.15, 0.15))
		_add_box(Vector3(0.12, 0.1, 0.34), Vector3(0.0, 0.2, 0.0), Color(0.85, 0.15, 0.15))
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 0.04
	disc.mesh = cyl
	disc.position = Vector3(0.0, -0.5, 0.0)
	var m := StandardMaterial3D.new()
	var glow := Color(0.3, 0.9, 0.4) if kind == "medkit" else Color(0.95, 0.8, 0.25)
	m.albedo_color = Color(glow, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = glow
	disc.material_override = m
	_visual.add_child(disc)

func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	_visual.add_child(mi)

func _process(delta: float) -> void:
	if _visual != null and _active:
		_spin += delta
		_visual.rotation.y = _spin * 1.6
		_visual.position.y = 0.55 + sin(_spin * 2.4) * 0.08

func _on_body_entered(body: Node3D) -> void:
	if not _active or not body.is_in_group("player"):
		return
	if kind == "medkit":
		if not body.has_method("heal"):
			return
		if int(body.get("health")) >= int(body.get("max_health")):
			return # full health — leave the medkit for later
		body.heal(heal_amount)
	else:
		if not body.has_method("add_ammo_pickup"):
			return
		body.add_ammo_pickup()
	_sfx.play()
	_deactivate()

func _deactivate() -> void:
	_active = false
	_visual.visible = false
	set_deferred("monitoring", false)
	_timer.start()

func _reactivate() -> void:
	_active = true
	_visual.visible = true
	monitoring = true
