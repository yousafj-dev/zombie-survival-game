extends Node3D

## Lobby character showcase. Lives inside the main menu's SubViewport.
## The hero stands on a small ground patch and slowly sways left/right
## so his front — and the gun he is holding — stays in view. The menu
## calls set_weapon() whenever the Guns selection changes.
## The hero is the real Vinish soldier model (same one as in game; its
## gun sits in the right hand bone). If the model file is missing, the
## placeholder soldier in the scene is used instead.
## Camera and sun angles are set in code (a hand-written basis in a scene
## file once shipped a camera staring at the sky — not again).

const HERO_PATH := "res://assets/models/player/soldier.glb"
const HERO_SCALE := 0.987 # Vinish soldier is 1.824 m raw; 1.8 m is the game's unit.
const MODEL_YAW := PI # The model faces +Z; the showcase front is -Z.
const PROP_MESHES: Array[String] = [] # The soldier has no built-in hand props.
const GUN_MOUNT_POSITION := Vector3(0.0, 0.0, 0.0)
# Same mount tuning as scripts/player.gd (render-verified).
const GUN_MOUNT_ROTATION := Vector3(-0.0647, 3.0508, 0.6645) # Same solved mount as player.gd.

var _time: float = 0.0

@onready var _character: Node3D = $Character
@onready var _guns: Dictionary = {
	"pistol": $Character/Body/GunMount/PistolModel,
	"rifle": $Character/Body/GunMount/RifleModel,
	"shotgun": $Character/Body/GunMount/ShotgunModel,
}

func _ready() -> void:
	# The model is built facing -Z, so the camera sits on -Z to see his
	# front (and the gun, which is mounted toward -Z).
	var cam := $Camera3D as Camera3D
	cam.position = Vector3(0.0, 1.5, -3.9)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.fov = 42.0
	($Sun as DirectionalLight3D).rotation_degrees = Vector3(-42.0, -24.0, 0.0)
	_load_hero()
	set_weapon("pistol")

func _load_hero() -> void:
	var inst := ModelUtil.load_model(HERO_PATH)
	if inst == null:
		return
	var holder := Node3D.new()
	holder.name = "ModelRoot"
	holder.scale = Vector3.ONE * HERO_SCALE
	holder.rotation.y = MODEL_YAW
	_character.add_child(holder)
	holder.add_child(inst)
	for prop in PROP_MESHES:
		var n := inst.find_child(prop, true, false)
		if n is Node3D:
			(n as Node3D).visible = false
	var body := _character.get_node("Body") as Node3D
	for child in body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	var anim := ModelUtil.find_animation_player(inst)
	if anim != null:
		ModelUtil.set_looping(anim, ["Idle"])
		anim.play("Idle")
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

func _process(delta: float) -> void:
	_time += delta
	_character.rotation.y = sin(_time * 0.45) * 0.55

func set_weapon(id: String) -> void:
	for key in _guns.keys():
		(_guns[key] as Node3D).visible = str(key) == id
