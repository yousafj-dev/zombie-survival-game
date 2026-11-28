extends Node3D

## Dead City dressing. The plain box buildings and cars in game.tscn
## stay as the collision (and as the fallback look); this script hides
## their visible meshes and fits real KayKit City Builder Bits models
## (CC0 — downloaded by CI into res://assets/models/city/) in their
## place: a building model inside each building's footprint with its
## street face flush to the collision face, a car model inside each
## wrecked-car body, plus dumpsters by the walls.
## If the pack is absent, nothing is hidden and nothing changes.

const CITY_DIR := "res://assets/models/city/"
const BUILDING_FILES: Array[String] = [
	"building_A_withoutBase.gltf", "building_B_withoutBase.gltf",
	"building_C_withoutBase.gltf", "building_D_withoutBase.gltf",
	"building_E_withoutBase.gltf", "building_F_withoutBase.gltf",
	"building_G_withoutBase.gltf", "building_H_withoutBase.gltf",
]
const CAR_FILES: Array[String] = [
	"car_sedan.gltf", "car_taxi.gltf", "car_police.gltf",
	"car_hatchback.gltf", "car_stationwagon.gltf",
]

func _ready() -> void:
	_dress_buildings()
	_dress_cars()
	_place_dumpsters()
	_place_lamp_glow()
	_place_roadside_props()

func _dress_buildings() -> void:
	var parent := get_node_or_null("Buildings")
	if parent == null:
		return
	var idx := 0
	for body in parent.get_children():
		if not (body is StaticBody3D):
			continue
		var shape_node: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_node = c
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var box := (shape_node.shape as BoxShape3D).size
		var inst := ModelUtil.load_model(CITY_DIR + BUILDING_FILES[idx % BUILDING_FILES.size()])
		idx += 1
		if inst == null:
			continue
		# Face the model's front (+Z) toward the map centre, in the
		# nearest 90-degree step.
		var to_centre := Vector2(-body.global_position.x, -body.global_position.z)
		var yaw := 0.0
		if absf(to_centre.x) > absf(to_centre.y):
			yaw = PI / 2.0 if to_centre.x > 0.0 else -PI / 2.0
		elif to_centre.y < 0.0:
			yaw = PI
		var aabb := ModelUtil.model_aabb(inst)
		var rotated := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * aabb
		# Fit inside the footprint; never grow past the collision box.
		var s := minf(box.y / aabb.size.y, minf(box.x / rotated.size.x, box.z / rotated.size.z))
		var holder := Node3D.new()
		holder.name = "ModelHolder"
		holder.scale = Vector3.ONE * s
		# Sit on the ground (the body's origin is at box-centre height)
		# and push flush toward the centre-facing sides. The offsets are
		# in body space, so they are NOT divided by the holder's scale.
		holder.position = Vector3(
			-signf(body.global_position.x) * maxf(0.0, (box.x - rotated.size.x * s) * 0.5),
			-box.y * 0.5,
			-signf(body.global_position.z) * maxf(0.0, (box.z - rotated.size.z * s) * 0.5))
		body.add_child(holder)
		holder.add_child(inst)
		inst.rotation.y = yaw
		var centre := rotated.get_center()
		inst.position = Vector3(-centre.x, -rotated.position.y, -centre.z)
		# Only now retire the box visuals — the model is in place.
		for c in body.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false

func _dress_cars() -> void:
	var parent := get_node_or_null("Props")
	if parent == null:
		return
	var idx := 0
	for body in parent.get_children():
		if not (body is StaticBody3D) or not body.name.begins_with("Car"):
			continue
		var inst := ModelUtil.load_model(CITY_DIR + CAR_FILES[idx % CAR_FILES.size()])
		idx += 1
		if inst == null:
			continue
		var aabb := ModelUtil.model_aabb(inst)
		# KayKit cars are modelled length-along-Z; the box cars are
		# length-along-X, so the model turns 90 degrees inside the body.
		var yaw := PI / 2.0
		var rotated := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * aabb
		var holder := Node3D.new()
		holder.name = "ModelHolder"
		holder.scale = Vector3.ONE * (4.2 / rotated.size.x)
		body.add_child(holder)
		holder.add_child(inst)
		inst.rotation.y = yaw
		var centre := rotated.get_center()
		inst.position = Vector3(-centre.x, -rotated.position.y, -centre.z)
		for c in body.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false

func _place_dumpsters() -> void:
	var parent := get_node_or_null("Props")
	if parent == null:
		return
	var spots: Array = [
		[Vector3(-36.5, 0.0, -8.0), PI / 2.0],
		[Vector3(36.5, 0.0, 8.0), -PI / 2.0],
		[Vector3(-8.0, 0.0, 36.5), PI],
		[Vector3(8.0, 0.0, -36.5), 0.0],
	]
	for spot in spots:
		var inst := ModelUtil.load_model(CITY_DIR + "dumpster.gltf")
		if inst == null:
			return
		var aabb := ModelUtil.model_aabb(inst)
		var s := 2.0 / aabb.size.x
		inst.scale = Vector3.ONE * s
		var pos: Vector3 = spot[0]
		inst.position = Vector3(pos.x, -aabb.position.y * s, pos.z)
		inst.rotation.y = float(spot[1])
		parent.add_child(inst)

## Dusk dressing: every street lamp gets a fake glow sprite (billboarded
## radial gradient — no light cost), and the two lamps nearest the plaza
## also get a real OmniLight so the road under them pools warm light.
## Sprites + 2 lights is the whole mobile budget for this.
func _place_lamp_glow() -> void:
	var parent := get_node_or_null("Props")
	if parent == null:
		return
	var tex := _glow_texture()
	var lit := 0
	for lamp in parent.get_children():
		if not lamp.name.begins_with("Lamp"):
			continue
		var head := lamp.get_node_or_null("Head") as Node3D
		if head == null:
			continue
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.modulate = Color(1.0, 0.72, 0.42, 0.5)
		spr.pixel_size = 0.017
		head.add_child(spr)
		if lit < 2:
			var omni := OmniLight3D.new()
			omni.light_color = Color(1.0, 0.72, 0.45)
			omni.light_energy = 0.7
			omni.omni_range = 9.0
			omni.position = Vector3(0.0, -0.4, 0.0)
			head.add_child(omni)
			lit += 1

func _glow_texture() -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)

## Extra ground-level dressing where the follow camera actually looks:
## crate boxes on the sidewalks and plaza corners, benches, hydrants and
## bushes along the roads. Visual only (no collision) and hugged to the
## road edges / walls, off the zombies' main paths across the plaza.
const ROADSIDE_PROPS: Array = [
	[Vector3(-17.0, 0.0, -10.0), "box_A.gltf", 1.1, 0.3],
	[Vector3(-16.9, 0.0, -8.8), "box_B.gltf", 0.9, 1.1],
	[Vector3(17.0, 0.0, -18.0), "box_A.gltf", 1.1, 2.2],
	[Vector3(-8.2, 0.0, -15.8), "box_B.gltf", 1.0, 0.8],
	[Vector3(8.2, 0.0, 15.8), "box_A.gltf", 1.1, 2.6],
	[Vector3(17.0, 0.0, 8.0), "firehydrant.gltf", 0.55, 0.0],
	[Vector3(-17.0, 0.0, 22.0), "firehydrant.gltf", 0.55, 1.9],
	[Vector3(17.0, 0.0, 24.0), "bush.gltf", 1.4, 0.7],
	[Vector3(-24.0, 0.0, 5.5), "bush.gltf", 1.6, 2.4],
	[Vector3(-17.0, 0.0, 2.0), "bench.gltf", 1.9, PI / 2.0],
]

func _place_roadside_props() -> void:
	var parent := get_node_or_null("Props")
	if parent == null:
		return
	for spot in ROADSIDE_PROPS:
		var inst := ModelUtil.load_model(CITY_DIR + str(spot[1]))
		if inst == null:
			continue
		var aabb := ModelUtil.model_aabb(inst)
		var footprint := maxf(aabb.size.x, aabb.size.z)
		if footprint <= 0.0:
			continue
		var s := float(spot[2]) / footprint
		inst.scale = Vector3.ONE * s
		var pos: Vector3 = spot[0]
		inst.position = Vector3(pos.x, -aabb.position.y * s, pos.z)
		inst.rotation.y = float(spot[3])
		parent.add_child(inst)
