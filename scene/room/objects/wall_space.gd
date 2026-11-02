class_name WallSpace extends StaticBody3D
const DRAWING_CAPACITY := 10
var drawings_count := 0
var is_vandalising := false
var available_positions := []

const V_START := 3
const DRAWINGS: Array[Array] = [
	["vertex", "domino", "hamster", "3d", "4d"],
	["birth", "jail", "home", "symbols", "names"],
	["scribble", "smiley", "bo", "left", "creature"],
	["anti_ia", "anti_ui", "nice_message", "dick", "cool_s"]
]
static var all_drawings: Dictionary[String, int] = {}

func _ready() -> void:
	available_positions = $DrawingSpots.get_children()
	available_positions.sort_custom(_sort_by_distance)

func add_drawing(character = null) -> void:
	drawings_count += 1
	var drawing: Sprite3D = $DrawingBase.duplicate()
	_assign_drawing(drawing, character)
	$Drawings.add_child(drawing)
	
	var position_marker: Node3D = available_positions.pop_back()
	drawing.position = position_marker.position
	drawing.rotation = position_marker.rotation
	
	drawing.modulate.a = 0
	get_tree().create_tween().tween_property(drawing, "modulate:a", 1, randi_range(2, 5))
	drawing.show()

func _assign_drawing(sprite: Sprite3D, character) -> void:
	var rows := DRAWINGS.size() if is_vandalising else V_START
	var available := []
	for i in range(rows): available.append_array(DRAWINGS[i])
	if character: available.erase("anti_" + Chuuni.characters.find_key(character))
	available.sort_custom(_sort_by_least_used)
	var lowest: int = _get_amount(available[0])
	for i in range(1, available.size()):
		if _get_amount(available[i]) > lowest:
			available.resize(i); break
	
	var chosen: String = available[randi() % available.size()]
	if not chosen in all_drawings: all_drawings[chosen] = 1
	else: all_drawings[chosen] += 1
	
	var frames := []
	for arr: Array in DRAWINGS: frames.append_array(arr)
	sprite.frame = frames.find(chosen)

func _sort_by_least_used(item_1, item_2) -> bool:
	var result := []
	for i in [item_1, item_2]:
		if not i in all_drawings.keys(): result.append(0)
		else: result.append(all_drawings[i])
	return result[0] < result[1]

func _sort_by_distance(item_1: Node3D, item_2: Node3D) -> bool:
	return item_1.global_position.distance_to($Front.global_position) > \
		item_2.global_position.distance_to($Front.global_position)

func _get_amount(drawing_name: String) -> int:
	if not drawing_name in all_drawings: return 0
	return all_drawings[drawing_name]

func has_room() -> bool:
	return drawings_count < DRAWING_CAPACITY
