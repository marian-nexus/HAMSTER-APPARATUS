extends Node

@onready var living_room := get_node("../../MainRoom")
var chosen_walls: Dictionary[Character, WallSpace] = {}

func _ready() -> void:
	GlobalActions.register_action(draw_on_wall, ["Marker"], ["happiness"], _draw_on_wall_req, "draw on wall")

func draw_on_wall(character: Character) -> Action:
	var subactions: Array[Callable] = [_check_for_space, GlobalActions._grab_item.bind("marker"),
		_decide_wall, _draw, GlobalActions._put_away_item]
	return Chuuni.create_action(character, subactions, "draw on wall")

func catch_vandalism(character: Character) -> Action:
	var subactions: Array[Callable] = [_balk_at_vandal]
	return Chuuni.create_action(character, subactions, "catch vandalism", Chuuni.get_zone(character.bedroom))

func get_caught_vandalising(character: Character) -> Action:
	var other_room := Chuuni.get_other_character(character).bedroom
	var subactions: Array[Callable] = [_get_caught]
	return Chuuni.create_action(character, subactions, "get caught vandalising", Chuuni.get_zone(other_room))

func _draw_on_wall_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var bedroom := character.bedroom
	var happiness_constraint := character.personality.happiness_constraint
	var bedroom_has_space := _has_wall_space(character.bedroom)
	
	req.possible = not _get_potential_rooms(character).is_empty()
	if req.possible: req.possible = character.personality.happiness < happiness_constraint / 2
	if not req.possible: return req
	
	req.personality = character.personality.anger >= 8
	req.mood = character.personality.happiness <= happiness_constraint / 3
	
	return req

func _has_wall_space(room := living_room) -> bool:
	for space: WallSpace in room.get_node("Objects/WallSpaces").get_children():
		if space.has_room(): return true
	return false

func _check_for_space(action: Action) -> void:
	if _get_potential_rooms(action.character).is_empty():
		action.cancel()
	action.subaction_finished.emit()

func _get_potential_rooms(character: Character) -> Array:
	var potential_rooms := []
	var other := Chuuni.get_other_character(character)
	
	for room in [living_room, character.bedroom, other.bedroom]:
		if _has_wall_space(room): potential_rooms.append(room)
	
	if living_room in potential_rooms and character.personality.activeness < 5:
		potential_rooms.erase(living_room)
	
	if other.bedroom in potential_rooms:
		var can_vandalise: bool = character.personality.anger >= 10 and Chuuni.is_enemies() and \
			character.get_feelings_toward(other).resentment >= 5
		if can_vandalise and Chuuni.the_powerful:
			if Chuuni.the_powerful != character: can_vandalise = false
		if not can_vandalise or other.current_zone == Chuuni.get_zone(other.bedroom):
			potential_rooms.erase(other.bedroom)
	
	return potential_rooms

func _get_random_wall(room := living_room) -> WallSpace:
	var available_walls := []
	var walls: Node3D = room.get_node("Objects/WallSpaces")
	for wall: WallSpace in walls.get_children():
		if wall in chosen_walls.values(): continue
		if wall.has_room(): available_walls.append(wall)
	return available_walls[randi_range(0, available_walls.size() - 1)]

func _decide_wall(action: Action) -> void:
	action.cancelled.connect(func():
		action.character.state_machine.queue_action(_cancel_drawing(action.character), true)
		chosen_walls[action.character] = null)
	var chosen_wall: WallSpace
	var character := action.character
	
	var potential_rooms := _get_potential_rooms(character)
	var chosen_room = potential_rooms[randi_range(0, potential_rooms.size() - 1)]
	
	chosen_wall = _get_random_wall(chosen_room)
	chosen_walls[character] = chosen_wall
	action.zone = Chuuni.get_zone(chosen_room)
	var other := Chuuni.get_other_character(character)
	var is_vandalising: bool = action.zone.room == other.bedroom
	
	GlobalActions.walk_to(character, chosen_wall.get_node("Front").global_position, true)
	
	if is_vandalising:
		if other.state_machine.current_action.zone.room == other.bedroom:
			action.cancel(); return
		other.state_machine.action_started.connect(_victim_action_changed.bind(action))
	
	var _finished_navigation := func():
		if action.is_cancelled: return
		if is_vandalising: other.state_machine.action_started.disconnect(_victim_action_changed)
		action.character.model.look_at_target = chosen_wall.get_node("Drawings").global_position
		action.subaction_finished.emit()
	
	var nav_agent: NavigationAgent3D = action.character.model.get_node("NavigationAgent3D")
	nav_agent.navigation_finished.connect(_finished_navigation, CONNECT_ONE_SHOT)

func _cancel_drawing(character: Character) -> Action:
	var subactions: Array[Callable] = [GlobalActions._put_away_item]
	var action := Chuuni.create_action(character, subactions, "cancel")
	action.zone = character.current_zone
	return action

func _victim_action_changed(action: Action, vandalism_action: Action) -> void:
	if action.zone.room == action.character.bedroom:
		print("oh no")
		vandalism_action.cancel()
		action.character.state_machine.action_started.disconnect(_victim_action_changed)

func _draw(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	var hand_marker = action.character.model.get_node("Hand").get_child(0)
	action.cancelled.connect(func():
		hand_marker.get_node("Sounds").stop()
		action.character.state_machine.queue_action(get_caught_vandalising(action.character), true)
		other.state_machine.queue_action(catch_vandalism(other), true)
		other.state_machine.current_action.cancel())
	
	print(action.character.npc_name + " is drawing on the wall ^_^")
	action.character.state_machine.state = StateMachine.State.BUSY
	hand_marker.get_node("Sounds").play()
	var wall := chosen_walls[action.character]
	var personality := action.character.personality
	var happiness_target := personality.happiness + 20
	if happiness_target > personality.happiness_constraint:
		happiness_target = personality.happiness_constraint
	
	var other_room := other.bedroom
	var is_vandalising := wall in other_room.get_node("Objects/WallSpaces").get_children()
	wall.is_vandalising = is_vandalising
	
	var happiness_tween := get_tree().create_tween()
	happiness_tween.tween_property(personality, "happiness", happiness_target, 20)
	while true:
		await get_tree().create_timer(randi_range(2, 5), false).timeout
		if action.is_cancelled:
			var current_happiness := personality.happiness
			happiness_tween.kill()
			personality.happiness = current_happiness
			return
		wall.add_drawing(action.character)
		if is_vandalising:
			wall.set_meta("vandalised", wall.get_meta("vandalised", 0) + 1)
			wall.remove_meta("vandalism_noticed")
		if personality.happiness >= happiness_target: break
		if not wall.has_room():
			var current_happiness := personality.happiness
			happiness_tween.kill()
			personality.happiness = current_happiness
			break
	
	hand_marker.get_node("Sounds").stop()
	var marker: Node = action.character.bedroom.get_node("Objects/Marker")
	action.character.create_memory(marker, ["satisfaction"])
	if is_vandalising:
		action.character.create_memory(Chuuni.get_other_character(action.character), ["satisfaction"], "vandalism")
		Chuuni.tally_winner(action.character)
	
	chosen_walls[action.character] = null
	action.character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()

func _get_caught(action: Action) -> void:
	var character := action.character
	var other := Chuuni.get_other_character(character)
	character.model.look_at_target = other.model.global_position
	await get_tree().create_timer(2, false).timeout
	character.state_machine.queue_action(_cancel_drawing(character), true)
	character.model.look_at_target = Vector3.ZERO
	chosen_walls[character] = null
	
	var marker := character.bedroom.get_node("Objects/Marker")
	character.create_memory(marker, ["fear", "resentment"])
	character.create_memory(other, ["fear", "resentment"], "vandalism")
	action.subaction_finished.emit()

func stare(character: Character) -> Action:
	var subactions: Array[Callable] = [_stare]
	return Chuuni.create_action(character, subactions, "stare", character.current_zone)

func _stare(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	await other.state_machine.action_finished
	await get_tree().create_timer(3, false).timeout
	action.subaction_finished.emit()

func _balk_at_vandal(action: Action) -> void:
	var character := action.character
	var other := Chuuni.get_other_character(character)
	character.model.position_target = character.model.global_position
	character.model.position_target.z += 0.3
	character.model.look_at_target = other.model.global_position
	await get_tree().create_timer(0.2, false).timeout
	character.model.position_target = character.model.global_position
	character.model.navigation_agent.target_position = character.model.global_position
	print("hooooooooooooly shit")
	character.create_memory(other, ["betrayal", "resentment"], "vandalism")
	Chuuni.relationship -= 10
	
	await other.state_machine.action_finished
	character.model.position_target = Vector3.ZERO
	
	var will_yell := true
	var yell_action: Callable = get_node("../Talking").yell_at
	if Chuuni.the_powerful == other: will_yell = false
	if character.personality.activeness < 5: will_yell = false
	if character.get_feelings_toward(other).fear > 2 and \
		character.personality.activeness < 10: will_yell = false
	
	if will_yell:
		character.state_machine.queue_action(yell_action.call(character, "vandalism_v"), true)
	else:
		var other_will_yell := true
		if not Chuuni.the_powerful and other.personality.activeness < 10: other_will_yell = false
		if other_will_yell:
			other.state_machine.queue_action(yell_action.call(other, "vandalism_p"))
			while true:
				await other.state_machine.action_finished
				if other.state_machine.current_action.action_name == "yell at": break
		else:
			other.state_machine.queue_action(stare(other))
			action.zone = Chuuni.get_zone(get_node("../../MainRoom/Objects"))
			var back := character.model.global_position
			back.z -= 2
			character.model.navigation_agent.target_position = back
			await character.model.navigation_agent.navigation_finished
			character.current_zone = action.zone
			await get_tree().create_timer(1, false).timeout
			character.state_machine.queue_action(GlobalActions.stand_in_corner(character))
	
	character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()

# called every time a character enters their room
func vandalism_mood_drain(character: Character) -> void:
	# check if the vandalism is ongoing
	var other := Chuuni.get_other_character(character)
	if other.state_machine.current_action.action_name == "draw on wall" and \
	other.current_zone == Chuuni.get_zone(character.bedroom):
		other.state_machine.current_action.cancel()
	
	var drain := 0
	var new_vandalism := false
	
	for wall: WallSpace in character.bedroom.get_node("Objects/WallSpaces").get_children():
		drain += wall.get_meta("vandalised", 0)
		if wall.has_meta("vandalised") and not wall.has_meta("vandalism_noticed"):
			wall.set_meta("vandalism_noticed", true)
			new_vandalism = true
			drain += 3
			Chuuni.relationship -= 5
	
	if new_vandalism:
		character.create_memory(other, ["resentment", "betrayal"])
		if character.personality.activeness >= 10 and other.current_zone.name == "MainArea":
			print("they could go yell now but e")
	
	if drain > 0:
		character.personality.happiness -= drain
		print(character.npc_name + "'s mood went down by " + str(drain) + " because of the vandalism.")
