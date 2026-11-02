extends MeshInstance3D
# shoutout to nick maltbie for making the tutorial that fucking carries this script

var st := SurfaceTool.new()
var material = preload("res://scene/room/textures/plant_stem.tres")
@onready var leaves := get_node("../Leaves").get_children()
var width := 0.01
var offshoot_width := 0.02
var to_erase := []

func _ready() -> void:
	var origin_point := Vector3.ZERO
	leaves.sort_custom(_sort_y_axis)
	var offshoots := _separate_offshoots(leaves)
	width *= (leaves.size() / 1.5)
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for leaf: Node3D in leaves:
		var pos = _get_position(leaf)
		_create_box(origin_point, pos)
		origin_point = pos
		_assess_offshoots(leaf, offshoots)
	
	st.generate_normals()
	mesh = st.commit()
	set_surface_override_material(0, material)
	
	if offshoots.size() > 0:
		var string := ""
		for off in offshoots:
			string += off.name + ", "
		string = string.substr(0, string.length() - 2)
		printerr(get_node("..").name + " has leftover offshoots: " + string)

func _reduce_width(offshoot = false) -> float:
	var new_width
	if not offshoot:
		width -= 0.005
		new_width = width
	else:
		new_width = offshoot_width - 0.005
	return new_width

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

func _get_position(leaf: Node3D) -> Vector3:
	return Vector3(leaf.position.x - 0.1, leaf.position.y + 0.1, leaf.position.z - 0.1)

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

func _separate_offshoots(arr: Array) -> Array:
	var offshoots := []
	
	for child: Node3D in arr:
		var pos = child.position
		pos.y = 0
		if pos.distance_to(Vector3.ZERO) >= 0.5:
			offshoots.append(child)
	
	for off in offshoots: arr.erase(off)
	return offshoots

func _sort_y_axis(item_1: Node3D, item_2: Node3D) -> bool:
	return item_1.position.y < item_2.position.y #and \
	#item_1.position.distance_to(Vector3.ZERO) < item_2.position.distance_to(Vector3.ZERO)
