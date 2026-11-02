extends Node

var all_actions: Array[Dictionary] = []
var items: Dictionary[String, Resource] = {
	"watering_can": preload("res://scene/room/objects/watering_can.tscn"),
	"marker": preload("res://scene/room/objects/marker.tscn"),
	"remote": preload("res://scene/room/objects/remote.tscn"),
	"cards": preload("res://scene/room/objects/cards.tscn")
}

func register_action(create_callable: Callable, associated_objects: Array,
associated_needs: Array, requirements_callable: Callable, action_name: String):
	var new_action := {}
	new_action.create = create_callable
	new_action.objects = associated_objects
	new_action.needs = associated_needs
	new_action.requirements_callable = requirements_callable
	new_action.name = action_name
	all_actions.append(new_action)

# actions that can be performed even if they're in the character's recent action history
const UNLIMITED_ACTION_NAMES := ["sleep"]

# returns all actions that the character currently meets the requirements for
func get_available_actions(character: Character) -> Array[Dictionary]:
	var available_actions: Array[Dictionary] = []
	for action: Dictionary in all_actions:
		# test: actions are impossible on low energy
		if character.personality.energy <= 5:
			if not "sleep" in action.name and not "nap" in action.name: continue
		# test: actions that take place in the main area are unavailable with low happiness
		if not action.objects.is_empty():
			var in_main_area := false
			if not action.objects[0] is String and Chuuni.get_zone(action.objects[0]).name == "MainArea":
				in_main_area = true
			if in_main_area and character.personality.happiness < 10 \
			and not "hunger" in action.needs: continue
		
		if action.name in character.state_machine.action_history and \
		not action.name in UNLIMITED_ACTION_NAMES: continue
		
		var requirements: ActionReq = action.requirements_callable.call(character)
		if requirements.possible:
			action.requirements = requirements
			# replace abstract item names with actual objects
			var new_objects_array := []
			var has_abstract_items := false
			for object in action.objects:
				if object is String:
					has_abstract_items = true
					if not character.bedroom.has_node("Objects/" + object):
						printerr(object + " does not exist in " + character.npc_name + "'s room")
					else:
						new_objects_array.append(character.bedroom.get_node("Objects/" + object))
				else: new_objects_array.append(object)
			
			if has_abstract_items:
				var action_copy := action.duplicate_deep()
				action_copy.objects = new_objects_array
				available_actions.append(action_copy)
			else:
				available_actions.append(action)
	return available_actions

#region action sorting
func sort_by_sentiment(action_1: Dictionary, action_2: Dictionary, chr: Character) -> bool:
	var total_sentiments := []
	for action in [action_1, action_2]:
		var sentiments := 0
		for object in action.objects:
			sentiments += chr.get_sentiment_toward(object)
		total_sentiments.append(sentiments)
	return total_sentiments[0] > total_sentiments[1]

func get_action_score(action: Dictionary, chr: Character) -> int:
	var score := 0
	var personality := chr.personality
	for object in action.objects:
		score += chr.get_sentiment_toward(object)
	score += action.requirements.get_score()
	
	for need: String in action.needs:
		var constraint: int = personality.stat_constraints[0]
		if need + "_constraint" in personality: constraint = personality[need + "_constraint"]
		var relevant: bool = personality[need] < constraint / 1.5
		if not relevant:
			score -= 2; continue
		if personality[need] <= constraint / 10: score += 5
		elif personality[need] <= constraint / 5: score += 3
		elif personality[need] <= constraint / 3: score += 2
		else: score += 1
	return score

func sort_actions_by_score(action_1: Dictionary, action_2: Dictionary, chr: Character) -> bool:
	var total_scores := []
	for action in [action_1, action_2]:
		total_scores.append(get_action_score(action, chr))
	return total_scores[0] > total_scores [1]

func remove_irrelevant_actions(available_actions: Array[Dictionary], chr: Character) -> Array[Dictionary]:
	var last_relevant_index := 0
	var cutoff := -5
	for action in available_actions:
		if get_action_score(action, chr) > cutoff: last_relevant_index = available_actions.find(action)
		else: break
	available_actions.resize(last_relevant_index + 1)
	if available_actions.size() == 1 and get_action_score(available_actions[0], chr) <= cutoff: return []
	return available_actions
#endregion

func is_queued_or_doing(character: Character, action_name: String) -> bool:
	if character.state_machine.current_action:
		if action_name in character.state_machine.current_action.action_name: return true
		for action: Action in character.state_machine.action_queue:
			if action_name in action.action_name: return true
	return false

func is_leaving_zone(character: Character, zone: Zone = null) -> bool:
	if not zone: zone = get_tree().current_scene.get_zones().main_area
	var leaving := false
	leaving = character.current_zone != zone
	if character.state_machine.current_action and not leaving:
		leaving = character.state_machine.current_action.zone != zone
	return leaving

func lay_on_ground(character: Character) -> Action:
	var floor_area: Area3D = character.bedroom.get_node("EmptyArea")
	var subactions: Array[Callable] = [_walk_to.bind(_ran_position_within_area(floor_area)), _lay_down]
	return Chuuni.create_action(character, subactions, "lay on ground", Chuuni.get_zone(character.bedroom))

func stand_in_corner(character: Character) -> Action:
	var corner: Vector3 = get_tree().current_scene.get_node("MainRoom/Corner").global_position
	var subactions: Array[Callable] = [_walk_to.bind(corner), _stand_there_motionless]
	return Chuuni.create_action(character, subactions, "stand in corner")

func _stand_there_motionless(action: Action) -> void:
	var corner_look_at: Vector3 = get_tree().current_scene.get_node("MainRoom/Corner2").global_position
	action.character.model.look_at_target = corner_look_at
	await get_tree().create_timer(5, false).timeout
	action.character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()

func _ran_position_within_area(area: Area3D) -> Vector3:
	var position := Vector3(0, 0.1, 0)
	var coll: CollisionShape3D = area.get_node("CollisionShape3D")
	for axis in ["x", "z"]:
		position[axis] = randi_range(
			coll.global_position[axis] - coll.shape.size[axis] / 2,
			coll.global_position[axis] + coll.shape.size[axis] / 2
		)
	return position

func _lay_down(action: Action) -> void:
	print(action.character.npc_name + " is laying on the ground...")
	var model := action.character.model
	await get_tree().create_timer(0.5).timeout
	model.hold_position = true
	var tween := get_tree().create_tween().set_trans(Tween.TRANS_QUAD)
	tween.tween_property(model, "rotation_degrees:x", 90, 1)
	tween.tween_callback(model.get_node("Land").play)
	
	await get_tree().create_timer(3, false).timeout
	while action.character.state_machine.get_possible_actions().is_empty() and \
	action.character.state_machine.action_queue.is_empty():
		await get_tree().create_timer(1, false).timeout
	
	# girl get up
	get_tree().create_tween().tween_property(model, "rotation_degrees:x", 0, 0.5)
	model.hold_position = false
	model.jump()
	await get_tree().create_timer(1.5, false).timeout
	action.subaction_finished.emit()

func _grab_item(action: Action, item_name: String) -> void:
	var chr_hand: Node3D = action.character.model.get_node("Hand")
	if chr_hand.get_child_count() != 0:
		printerr(action.character.npc_name + " is already holding something."); return
	
	var item = items[item_name].instantiate()
	Chuuni.give_character_item(action.character, item)
	get_tree().create_timer(0.5, false).timeout.connect(action.subaction_finished.emit)

func _put_away_item(action: Action) -> void:
	var chr_hand: Node3D = action.character.model.get_node("Hand")
	if chr_hand.get_child_count() == 0:
		printerr(action.character.npc_name + " isn't holding anything!!!"); return
	
	chr_hand.get_child(0).queue_free()
	get_tree().create_timer(0.5, false).timeout.connect(action.subaction_finished.emit)

func wander(npc: Character) -> Action:
	return Chuuni.create_action(npc, [_walk_to.bind(Chuuni.get_random_position())], "wander")

func eat_at_tv(character: Character) -> Action:
	var tv = get_tree().current_scene.get_node("%Objects/TV/CRT")
	return tv.eat_at_tv(character)
	# this is... how i avoid making the kitchen script reliant on the tv script
	# pro coder? or weird amateur? who knows! life is a dream

# walk_to but it's not a subaction
func walk_to(character: Character, point: Vector3, change_state: bool = false) -> void:
	if change_state: character.state_machine.state = StateMachine.State.WALKING
	var nav_agent: NavigationAgent3D = character.model.get_node("NavigationAgent3D")
	nav_agent.set_target_position(point)
	await nav_agent.navigation_finished

func _walk_to(action: Action, point: Vector3) -> void:
	action.character.state_machine.state = StateMachine.State.WALKING
	var nav_agent: NavigationAgent3D = action.character.model.get_node("NavigationAgent3D")
	nav_agent.set_target_position(point)
	nav_agent.navigation_finished.connect(func():
		action.subaction_finished.emit(), CONNECT_ONE_SHOT)
