class_name ModelUtil
extends RefCounted

## Shared helpers for the runtime-loaded 3D models. The model packs are
## downloaded by CI into res://assets/models/ (they are binaries, so they
## can never be pushed through the repo's text-only route) — scenes and
## scripts therefore load them by path at runtime. If a file is missing
## (e.g. a build made before the workflow gained the download step) every
## helper degrades quietly and the caller keeps its placeholder look.

static func load_model(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()

static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var r := find_animation_player(c)
		if r != null:
			return r
	return null

static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var r := find_skeleton(c)
		if r != null:
			return r
	return null

## Bind-pose AABB of every mesh under root, in root-local space.
static func model_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var t: Transform3D = pair[1]
		if n is Node3D:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var b: AABB = t * mi.get_aabb()
				if first:
					result = b
					first = false
				else:
					result = result.merge(b)
		for c in n.get_children():
			stack.append([c, t])
	return result

## glTF clips import as one-shot; the locomotion/idle clips must loop.
static func set_looping(anim_player: AnimationPlayer, clip_names: Array) -> void:
	for clip_name in clip_names:
		if anim_player.has_animation(clip_name):
			anim_player.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
