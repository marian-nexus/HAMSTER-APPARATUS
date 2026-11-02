class_name Plant extends Node3D
enum PlantHealth {HEALTHY, NEEDS_WATER, WILTING, DEAD}

const textures = "res://scene/room/textures/"
var health_attributes := {
	PlantHealth.HEALTHY: {"material": preload(textures + "leaf_healthy.tres")},
	PlantHealth.NEEDS_WATER: {"material": preload(textures + "leaf_needs_water.tres"), "rot": .2},
	PlantHealth.WILTING: {"material": preload(textures + "leaf_dying.tres"), "rot": .4},
	PlantHealth.DEAD: {"material": preload(textures + "leaf_dead.tres"), "rot": .6, "pos": 0.1}
}

var wilt_progress := 0
var health := PlantHealth.HEALTHY:
	set(value):
		health = value
		wilt_progress = 0
		_display_health()

@onready var zone: Zone = Chuuni.get_zone(self)
var leaves : Array
@onready var wilt_timer: Timer = get_tree().current_scene.get_node("Scripts/LivingRoomActions/WiltTimer")
var dumping_ground: Node3D

var is_being_watered := false
var wilting_enabled := true
signal finished_unpacking

func _ready() -> void:
	if zone.objects.has_node("DumpingGround"):
		dumping_ground = zone.objects.get_node("DumpingGround/Dishes")
	elif zone.objects.has_node("Kitchen"):
		dumping_ground = zone.objects.get_node("Kitchen/DumpingGround/Dishes")
	
	wilt_timer.timeout.connect(_add_wilt_progress)
	if randi_range(0, 12) == 1: health = PlantHealth.NEEDS_WATER
	else: wilt_progress = randi_range(0, 50)

func unpack_leaves() -> void:
	var leaf_data: Dictionary = get_meta("leaves")
	var mesh_scene := preload("res://scene/room/objects/plant/leaf.tscn")
	
	for leaf: Marker3D in get_node("Leaves").get_children():
		if leaf_data[leaf.name].offshoot: continue
		var mesh = mesh_scene.instantiate()
		leaf.add_child(mesh)
		mesh.position = Vector3(-0.048, -0.645, 0.041)
		mesh.get_child(0).bending_angle = leaf_data[leaf.name].angle
		await get_tree().process_frame
	
	finished_unpacking.emit()
	leaves = _get_leaf_meshes()
	if health != PlantHealth.HEALTHY: _display_health()

func _display_health() -> void:
	if leaves.is_empty(): return
	var attributes = health_attributes[health]
	for leaf: Node3D in leaves:
		var temp_mesh = leaf.duplicate()
		var temp_deform = leaf.get_child(0).duplicate()
		
		var root: Node3D = leaf.get_parent()
		root.add_child(temp_mesh)
		temp_mesh.add_child(temp_deform)
		temp_mesh.set_surface_override_material(0, attributes.material.duplicate())
		var material: StandardMaterial3D = temp_mesh.get_surface_override_material(0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0
		
		var rot = attributes.rot if "rot" in attributes else 0
		var ran_time := randi_range(4, 6)
		if not root.has_meta("default_rot"): root.set_meta("default_rot", root.rotation.x)
		
		var target_rot = root.get_meta("default_rot") + rot
		if rot == 0: target_rot = root.get_meta("default_rot")
		var tween := get_tree().create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(material, "albedo_color:a", 1, ran_time)
		if target_rot != root.rotation.x and not root.has_meta("no_rot"):
			tween.tween_property(root, "rotation:x", target_rot, ran_time)
		
		if "pos" in attributes and not root.has_meta("no_rot"):
			tween.tween_property(root, "position:y", root.position.y - attributes.pos, ran_time)
		
		tween.finished.connect(func():
			leaf.set_surface_override_material(0, attributes.material)
			temp_mesh.queue_free()
		)
	
	if health == PlantHealth.DEAD: $DeadParticles.emitting = true

func _get_leaf_meshes() -> Array:
	var _leaves := []
	for child: Node3D in $Leaves.get_children():
		if child.get_child_count() == 0: continue
		_leaves.append(child.get_child(0))
	return _leaves

func _add_wilt_progress() -> void:
	if is_being_watered or not wilting_enabled: return
	if health == PlantHealth.DEAD: # rest in fucking peace d(^_^)b
		return
	
	var dirty_dishes := dumping_ground.get_child_count()
	wilt_progress += dirty_dishes + 1
	if wilt_progress >= 100:
		wilt_progress = 0
		health += 1 # very misleading as this actually decreases its health T_T
