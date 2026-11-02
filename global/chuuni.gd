extends Node
var characters: Dictionary[String, Character] = {
	"ia": Character.new(), "ui": Character.new()}

var relationship: int = 0:
	set(value):
		if value == relationship: return
		var constraints := [-100, 100]
		if value < constraints[0]: value = constraints[0]
		if value > constraints[1]: value = constraints[1]
		var previous := relationship
		relationship = value
		
		for level: int in LABELS.keys():
			if value >= level: relationship_label = LABELS[level]
		if value < LABELS.keys()[0]: relationship_label = LABELS[LABELS.keys()[0]]
		relationship_changed.emit(previous, value)

var relationship_label: String
const LABELS: Dictionary[int, String] = {
	-50: "archnemeses", -20: "vindictive", -10: "unpleasant", -5: "at odds",
	0: "neutral",
	5: "pleasant", 13: "friends", 25: "close", 40: "very close",
	50: "stupid close", 90: "soulmates"
}

var random_positions: Array[Vector3] = []
var win_count: Dictionary[String, int] = {}
var power_difference := 0
var the_powerful: Character

signal settings_changed(new_settings: Dictionary)
var settings := {
	"lock_room": false
}:
	set(value):
		settings = value
		settings_changed.emit(value)

var memory_text: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/memory.json")
)

signal characters_set_up
signal room_loaded
signal entering_check_in
signal exiting_check_in
signal relationship_changed(previous: int, current: int)

# ok we'll ask Chuuni if they're friends or enemies or whatever
func is_friends() -> bool: return relationship >= LABELS.find_key("friends")
func is_close() -> bool: return relationship >= LABELS.find_key("close")
func is_enemies() -> bool: return relationship <= LABELS.find_key("unpleasant")

func _ready() -> void:
	if get_tree().current_scene.name == "Room": room_loaded.emit()

func get_difference(num1, num2 = 0) -> Variant:
	var result
	if num1 is Array: result = num1[0] - num1[1]
	else: result = num1 - num2
	if result < 0: result *= -1
	return result

func set_up_npcs() -> void:
	_get_navmesh_vertices()
	var current_scene := get_tree().current_scene
	var npc_res := preload("res://scene/npc/npc.tscn")
	var the_active: Character = characters.values()[randi() % 2]
	var traits := ["melancholy", "anger", "whimsy"]
	
	for npc: Character in characters.values():
		var npc_node: CharacterModel = npc_res.instantiate()
		if not npc.npc_name: npc.npc_name = characters.find_key(npc)
		npc_node.name = npc.npc_name
		npc_node.character = npc
		npc.model = npc_node
		npc.state_machine = StateMachine.new()
		npc_node.state_machine = npc.state_machine
		npc.state_machine.character = npc
		npc.current_zone = get_tree().current_scene.get_zones().main_area
		current_scene.get_node("NPCs").add_child(npc_node)
		npc_node.position = get_random_position()
		npc.model.start_decay()
		
		if not npc.personality.randomised:
			var predominant_trait = traits.pop_at(randi() % traits.size())
			npc.personality[predominant_trait] = 20
			npc.personality.randomise()
		npc.personality.activeness = randi_range(10, 20) if npc == the_active else randi_range(-5, 5)
		
		for zone: Zone in get_tree().current_scene.get_zones().values():
			if zone.room.get_parent().name != "Bedrooms": continue
			if not zone.room.has_meta("owner"):
				zone.room.set_meta("owner", npc.npc_name)
				npc.bedroom = zone.room
				break
	
	characters_set_up.emit()

func get_other_character(character: Character) -> Character:
	for chr in characters.values(): if chr != character: return chr
	return

func create_action(character: Character, subactions: Array[Callable], action_name := "no name", zone: Zone = null) -> Action:
	var action := Action.new()
	action.character = character
	action.set_subactions(subactions)
	action.action_name = action_name
	action.zone = zone if zone else get_tree().current_scene.get_zones().main_area
	return action

func get_zone(object: Node) -> Zone:
	var zones: Dictionary = get_tree().current_scene.get_zones()
	for zone: Zone in zones.values():
		if object.get_parent() in [zone.objects, zone.room]: return zone
		if object in [zone.objects, zone.room]: return zone
		if object.find_parent("Objects"):
			if object.find_parent("Objects") == zone.objects: return zone
	
	printerr("couldn't find the zone oops you fucked it up (" + object.name + ")")
	return zones.main_area

# get random position in living room from the nav mesh's vertices ^_^
func _get_navmesh_vertices() -> void:
	var living_room_bounds := {"z": 3.2}
	var vertices: PackedVector3Array = \
		get_tree().current_scene.get_node("NavigationRegion3D").navigation_mesh.get_vertices()
	
	for pos: Vector3 in vertices:
		var disqualified = false
		if pos.z > living_room_bounds.z: disqualified = true
		if not disqualified: random_positions.append(pos)

func get_random_position() -> Vector3:
	return random_positions[randi_range(0, random_positions.size() - 1)]

func get_nearest_lr_position(object: Node3D) -> Vector3:
	random_positions.sort_custom(func(a: Vector3, b: Vector3):
		return object.global_position.distance_to(a) < \
		object.global_position.distance_to(b))
	return random_positions[0]

func give_character_item(character: Character, item: Node3D) -> void:
	var hand: Node3D = character.model.get_node("Hand")
	if item.get_parent(): item.reparent(hand, false)
	else: hand.add_child(item)
	item.position = Vector3.ZERO

func tally_winner(winner: Character) -> void:
	if win_count.is_empty():
		for character: Character in characters.values(): win_count[character.npc_name] = 0
	win_count[winner.npc_name] += 1
	print(win_count)
	
	var win_difference = get_difference(win_count.values())
	if get_difference(win_difference) > Personality.power_threshold:
		var above_neutral = LABELS.find_key("neutral")
		above_neutral = LABELS.keys().find(above_neutral) + 1
		above_neutral = LABELS.keys()[above_neutral]
		if relationship >= above_neutral: win_difference /= 2
		power_difference = win_difference
		printerr("power difference is ", power_difference)
		
		var powerful: Character = characters.values()[0]
		if win_count[powerful.npc_name] < win_count[get_other_character(powerful).npc_name]:
			powerful = get_other_character(powerful)
		the_powerful = powerful
	else: power_difference = 0

func enter_check_in_menu(character: Character) -> void:
	get_tree().paused = true
	entering_check_in.emit(character)

func leave_check_in_menu() -> void:
	assert(get_tree().paused)
	get_tree().paused = false
	exiting_check_in.emit()

# debug: test power dynamics
func _set_wins(num1: int, num2: int) -> void:
	win_count[characters.values()[0].npc_name] = num1 - 1
	win_count[characters.values()[1].npc_name] = num2
	tally_winner(characters.values()[0])

func _set_personalities(p1: Personality, p2: Personality) -> void:
	characters.ia.personality = p1
	characters.ui.personality = p2
