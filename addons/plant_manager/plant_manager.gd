@tool
extends EditorPlugin

var dock: EditorDock
const TOOL_MENU_ITEMS := {
	"open": "Open Plant Manager",
	"close": "Close Plant Manager"
}

#region plugin
func _disable_plugin() -> void:
	hide_dock()
	remove_tool_menu_item(TOOL_MENU_ITEMS.close)

func _enter_tree() -> void:
	add_tool_menu_item(TOOL_MENU_ITEMS.open, show_dock)

func show_dock() -> void:
	var dock_scene := preload("res://addons/plant_manager/plant_dock.tscn").instantiate()
	dock = EditorDock.new()
	dock.add_child(dock_scene)
	dock.title = "Plant Manager"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	add_dock(dock)
	remove_tool_menu_item(TOOL_MENU_ITEMS.open)
	add_tool_menu_item(TOOL_MENU_ITEMS.close, hide_dock)
	
	_change_options_visible()
	EditorInterface.get_inspector().edited_object_changed.connect(_change_options_visible)
	dock_scene.get_node("%Pack").pressed.connect(_pack_plant)
	dock_scene.get_node("%Unpack").pressed.connect(_unpack_plant)
	dock_scene.get_node("%Stem").pressed.connect(_generate_stem)

func _change_options_visible() -> void:
	var editing := EditorInterface.get_inspector().get_edited_object()
	dock.get_child(0).get_node("Options").visible = editing is Plant
	dock.get_child(0).get_node("SelectHint").visible = not editing is Plant

func hide_dock() -> void:
	remove_dock(dock)
	dock.queue_free()
	add_tool_menu_item(TOOL_MENU_ITEMS.open, show_dock)
	remove_tool_menu_item(TOOL_MENU_ITEMS.close)

func _exit_tree() -> void:
	hide_dock()
#endregion

func _pack_plant() -> void:
	var plant = EditorInterface.get_inspector().get_edited_object()
	if plant.has_meta("leaves"):
		if not plant.has_meta("attempted"):
			printerr("Plant has already been packed. Press again to confirm.")
			plant.set_meta("attempted", true)
			return
		else:
			plant.remove_meta("attempted")
	
	var leaf_data := {}
	for leaf: Marker3D in plant.get_node("Leaves").get_children():
		leaf_data[leaf.name] = {"offshoot": leaf.get_child_count() == 0}
		if leaf.get_child_count() > 0:
			leaf_data[leaf.name].angle = leaf.get_child(0).get_child(0).bending_angle
			leaf.get_child(0).queue_free()
	
	plant.set_meta("leaves", leaf_data)

func _unpack_plant() -> void:
	var plant = EditorInterface.get_inspector().get_edited_object()
	var mesh_scene = preload("res://scene/room/objects/plant/leaf.tscn")
	
	if not plant.has_meta("leaves"):
		#printerr("Plant has not been packed."); return
		for leaf: Marker3D in plant.get_node("Leaves").get_children():
			if leaf.get_child_count() > 0: leaf.get_child(0).queue_free()
			var leaf_mesh = mesh_scene.instantiate()
			leaf.add_child(leaf_mesh)
			leaf_mesh.position = Vector3(-0.048, -0.645, 0.041)
			leaf_mesh.owner = get_editor_interface().get_edited_scene_root()
			leaf_mesh.get_child(0).owner = get_editor_interface().get_edited_scene_root()
			await get_tree().create_timer(0.1).timeout
		return
	
	var leaf_data: Dictionary = plant.get_meta("leaves")
	for leaf_name: String in leaf_data.keys():
		if leaf_data[leaf_name].offshoot: continue
		var destination = plant.get_node("Leaves/" + leaf_name)
		if destination.get_child_count() > 0: destination.get_child(0).queue_free()
		var leaf_mesh = mesh_scene.instantiate()
		destination.add_child(leaf_mesh)
		leaf_mesh.position = Vector3(-0.048, -0.645, 0.041)
		leaf_mesh.owner = get_editor_interface().get_edited_scene_root()
		leaf_mesh.get_child(0).owner = get_editor_interface().get_edited_scene_root()
		leaf_mesh.get_child(0).bending_angle = leaf_data[leaf_name].angle
		await get_tree().create_timer(0.1).timeout
	
	#plant.remove_meta("leaves")

#region stem
var width := 0.01
var offshoot_width := 0.02
var st: SurfaceTool
var to_erase := []

func _generate_stem() -> void:
	var plant = EditorInterface.get_inspector().get_edited_object()
	st = SurfaceTool.new()
	to_erase = []
	var origin_point := Vector3.ZERO
	var material := preload("res://scene/room/textures/plant_stem.tres")
	var leaves = plant.get_node("Leaves").get_children()
	leaves.sort_custom(_sort_y_axis)
	var offshoots := _separate_offshoots(plant, leaves)
	var stem: MeshInstance3D = plant.get_node("Stem")
	
	width = 0.01 * (leaves.size() / 1.5)
	stem.mesh = ArrayMesh.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for leaf: Node3D in leaves:
		var pos = _get_position(leaf)
		_create_box(origin_point, pos)
		origin_point = pos
		_assess_offshoots(leaf, offshoots)
	
	st.generate_normals()
	stem.mesh = st.commit()
	stem.set_surface_override_material(0, material)
	
	if offshoots.size() > 0:
		var string := ""
		for off in offshoots:
			string += off.name + ", "
		string = string.substr(0, string.length() - 2)
		printerr(get_node("..").name + " has leftover offshoots: " + string)

func _get_position(leaf: Node3D) -> Vector3:
	return Vector3(leaf.position.x - 0.1, leaf.position.y + 0.1, leaf.position.z - 0.1)

func _assess_offshoots(root: Node3D, offshoots: Array, mid = false) -> void:
	for off in offshoots:
		if off in to_erase: continue
		if off.position.distance_to(_get_position(root)) <= 0.53:
			to_erase.append(off)
			_create_box(_get_position(root), _get_position(off), true, mid)
			
			if off.get_child_count() == 0:
				_assess_offshoots(off, offshoots, true)
	
	for off in to_erase:
		if off in offshoots: offshoots.erase(off)

func _separate_offshoots(plant, arr: Array) -> Array:
	var offshoots := []
	
	for child: Node3D in arr:
		var pos = child.global_position
		pos.y = plant.get_node("Stem").global_position.y
		if pos.distance_to(plant.get_node("Stem").global_position) >= 0.5:
			offshoots.append(child)
	
	for off in offshoots: arr.erase(off)
	return offshoots

func _create_box(sp: Vector3, ep: Vector3, offshoot = false, mid = false) -> void:
	var points := []
	var box_width := width
	if offshoot: box_width = offshoot_width
	
	for p: Vector3 in [sp, ep]:
		if p == ep and not mid: box_width = _reduce_width(offshoot)
		points.append(Vector3(p.x - box_width, p.y, p.z - box_width))
		points.append(Vector3(p.x + box_width, p.y, p.z - box_width))
		points.append(Vector3(p.x - box_width, p.y + box_width, p.z + box_width))
		points.append(Vector3(p.x + box_width, p.y + box_width, p.z + box_width))
	
	_add_face(points[0], points[1], points[2], points[3])
	_add_face(points[4], points[6], points[5], points[7])
	_add_face(points[0], points[2], points[4], points[6])
	_add_face(points[1], points[5], points[3], points[7])
	_add_face(points[2], points[3], points[6], points[7])
	_add_face(points[0], points[4], points[1], points[5])

func _add_face(v1, v2, v3, v4) -> void:
	st.add_vertex(v1)
	st.add_vertex(v3)
	st.add_vertex(v2)
	st.add_vertex(v2)
	st.add_vertex(v3)
	st.add_vertex(v4)

func _reduce_width(offshoot = false) -> float:
	var new_width
	if not offshoot:
		width -= 0.005
		new_width = width
	else:
		new_width = offshoot_width - 0.005
	return new_width

func _sort_y_axis(item_1: Node3D, item_2: Node3D) -> bool:
	return item_1.position.y < item_2.position.y
#endregion
