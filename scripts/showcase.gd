extends Node3D

## Lobby character showcase. Lives inside the main menu's SubViewport.
## The soldier stands on a small ground patch and slowly sways left/right
## so his front — and the gun he is holding — stays in view. The menu
## calls set_weapon() whenever the Guns selection changes.
## Camera and sun angles are set in code (a hand-written basis in a scene
## file once shipped a camera staring at the sky — not again).

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
	set_weapon("pistol")

func _process(delta: float) -> void:
	_time += delta
	_character.rotation.y = sin(_time * 0.45) * 0.55

func set_weapon(id: String) -> void:
	for key in _guns.keys():
		(_guns[key] as Node3D).visible = str(key) == id
