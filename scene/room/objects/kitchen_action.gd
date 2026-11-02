extends Node3D

func _ready() -> void:
	MainUI.cook_action_selected.connect(func(character: Character, option: String):
		character.state_machine.queue_action(self["cook_" + option].call(character))
	)
	_setup.call_deferred()
	
	# register actions
	GlobalActions.register_action(cook_counter, [$Fridge, $Counter], ["hunger"], \
		_counter_req, "cook (counter)")
	GlobalActions.register_action(cook_microwave, [$Fridge, $Microwave], ["hunger"], \
		_microwave_req, "cook (microwave)")
	GlobalActions.register_action(cook_fridge, [$Fridge], ["hunger"], \
		_fridge_req, "cook (fridge)")
	GlobalActions.register_action(wash_main_dishes, [$Sink, $DumpingGround], ["happiness"], \
		_wash_main_dishes_req, "wash dirty dishes in kitchen")
	GlobalActions.register_action(wash_bedroom_dishes, [$Sink], ["happiness"], \
		_wash_bedroom_dishes_req, "wash dirty dishes in bedroom")

func _fridge_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.char_personality = character.personality
	req.applicable_stat = "hunger"
	req.all_false()
	req.mood = true
	req.possible = character.personality.hunger <= 20 and character.personality.happiness <= 10 \
		or character.personality.hunger <= 30 and character.personality.energy <= 12
	return req

func _microwave_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.char_personality = character.personality
	req.applicable_stat = "hunger"
	req.all_false()
	req.context = character.personality.hunger < 35
	req.mood = true
	req.possible = character.personality.hunger <= 25 and character.personality.energy <= 30 \
		and character.personality.happiness > 10 and character.personality.energy > 12
	return req

func _counter_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.char_personality = character.personality
	req.applicable_stat = "hunger"
	req.all_false()
	req.possible = character.personality.hunger <= 25 and character.personality.energy > 35 \
		and character.personality.happiness > 20
	return req

func _setup() -> void:
	for character: Character in Chuuni.characters.values():
		character.model.finished_eating.connect(_decide_dishes_fate.bind(character))

func _set_state(action: Action, state: StateMachine.State):
	action.character.state_machine.state = state

func _decide_eating_location(character: Character) -> void:
	var tv_available := true
	var stereo: Stereo = get_tree().current_scene.get_node("MainRoom/Objects/Stereo")
	if stereo.music_on: tv_available = false
	
	if randi() % 2 == 1 or not tv_available:
		character.eat_in_bed.emit() # handled in bedroom_objects_action.gd
		return
	
	character.state_machine.queue_action(GlobalActions.eat_at_tv(character), true)

func _decide_dishes_fate(character: Character) -> void:
	var will_leave_dishes := false
	if character.personality.energy < character.personality.energy_constraint / 2: will_leave_dishes = true
	if character.personality.happiness < character.personality.happiness_constraint / 2.5: will_leave_dishes = true
	if character.personality.anger >= 10 and character.personality.activeness >= 5 and \
	Chuuni.relationship <= 0: will_leave_dishes = true
	
	if not will_leave_dishes: character.state_machine.queue_action(wash_dishes(character), true)
	else:
		if "Bedroom" in character.current_zone.name:
			character.state_machine.queue_action(abandon_dishes_in_room(character), true)
		else: character.state_machine.queue_action(abandon_dishes(character), true)

func _wash_main_dishes_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.all_false()
	req.mood = character.personality.energy >= 15
	req.personality = _wash_personality_req(character)
	var dishes := _get_dishes($DumpingGround)
	
	req.possible = dishes.total > 1
	if not req.possible: return req
	
	# unavailable if other character is washing dishes
	var other_state_machine := Chuuni.get_other_character(character).state_machine
	if other_state_machine.current_action:
		if "wash dirty dishes" in other_state_machine.current_action.action_name: req.possible = false
	for action: Action in other_state_machine.action_queue:
		if "wash dirty dishes" in action.action_name: req.possible = false
	if not req.possible: return req
	
	# passive characters will always wash the dishes
	if character.personality.activeness <= 0: req.context = true
	elif character.personality.fear >= 5: req.context = true
	# active characters will choose to clean if at least half of the dishes are theirs
	elif character.personality.activeness >= 10 and Chuuni.get_difference(
		dishes.total, dishes[character.npc_name]) <= dishes.total / 2: req.context = true
	# characters with above zero activeness will wash dishes if it's a desperate situation
	elif character.personality.activeness >= 0 and dishes.total >= 8: req.context = true
	
	if character.personality.activeness < 5:
		req.applicable_stat = "happiness"
		req.char_personality = character.personality
	
	return req

func _wash_bedroom_dishes_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.all_false()
	req.mood = character.personality.energy >= 25
	req.personality = _wash_personality_req(character)
	var dishes := _get_dishes(character.bedroom.get_node("Objects/DumpingGround"))
	
	req.possible = dishes.total > 3
	if not req.possible: return req
	var other_state_machine := Chuuni.get_other_character(character).state_machine
	if other_state_machine.current_action:
		if "wash dirty dishes" in other_state_machine.current_action.action_name: req.possible = false
	for action: Action in other_state_machine.action_queue:
		if "wash dirty dishes" in action.action_name: req.possible = false
	if not req.possible: return req
	
	if character.personality.activeness >= 0: req.context = true
	elif dishes.total >= 8: req.context = true
	
	return req

# whimsical characters might just be like nah don't wanna
func _wash_personality_req(character: Character) -> bool:
	var req := true
	if character.personality.whimsy >= 15:
		if randi() % 5 == 1: req = false
	return req

func _get_dishes(ground: Area3D) -> Dictionary:
	var dishes := {"total": ground.get_node("Dishes").get_child_count()}
	for chr: Character in Chuuni.characters.values():
		dishes[chr.npc_name] = ground.get_meta(chr.npc_name, 0)
	return dishes

func wash_main_dishes(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to.bind($Sink), _start_washing.bind($DumpingGround),
	_finish_cooking]
	return Chuuni.create_action(character, subactions, "wash dirty dishes in kitchen")

func wash_bedroom_dishes(character: Character) -> Action:
	var dumping_ground = character.bedroom.get_node("Objects/DumpingGround")
	var subactions: Array[Callable] = [_start_washing.bind(dumping_ground), _finish_cooking]
	return Chuuni.create_action(character, subactions, "wash dirty dishes in bedroom")

func _decide_pettiness(character: Character, dumping_ground: Area3D) -> void:
	var petty := false
	if dumping_ground == $DumpingGround: # can only be petty when washing the kitchen's dishes
		var feelings := character.get_feelings_toward(Chuuni.get_other_character(character))
		if character.personality.activeness >= 10:
			if "resentment" in feelings and feelings.resentment > 0: petty = true
			if Chuuni.relationship < 0: petty = true
		if _get_dishes(dumping_ground)[character.npc_name] == 0: petty = false
	character.set_meta("petty", petty)

func _start_washing(action: Action, dumping_ground: Area3D) -> void:
	action.character.state_machine.state = StateMachine.State.BUSY
	_decide_pettiness(action.character, dumping_ground)
	action.character.set_meta("starting_dishes", _get_dishes(dumping_ground))
	var petty: bool = action.character.get_meta("petty")
	var in_bedroom := Chuuni.get_zone(dumping_ground).name != "MainArea"
	var ground_front: Marker3D
	if in_bedroom: ground_front = dumping_ground.get_node("Front")
	
	while not petty and _get_dishes(dumping_ground).total > 0 or petty and \
	_get_dishes(dumping_ground)[action.character.npc_name] > 0:
		if in_bedroom:
			action.zone = Chuuni.get_zone(action.character.bedroom)
			await GlobalActions.walk_to(action.character, ground_front.global_position)
		_grab_dishes(action.character, dumping_ground)
		await get_tree().create_timer(0.5, false).timeout
		if in_bedroom:
			action.zone = Chuuni.get_zone(self)
			await GlobalActions.walk_to(action.character, $Sink/Front.global_position)
		await _wash_dirty_dish(action.character)
		var dishes_left: int
		if petty: dishes_left = _get_dishes(dumping_ground)[action.character.npc_name]
		else: dishes_left = _get_dishes(dumping_ground).total
		print("dishes left: ", dishes_left)
	
	_set_dishes_memories(action.character, dumping_ground)
	action.subaction_finished.emit()

func _grab_dishes(character: Character, dumping_ground: Area3D) -> void:
	var petty: bool = character.get_meta("petty")
	var other := Chuuni.get_other_character(character)
	var holding_capacity := 1
	if character.personality.energy >= 70: holding_capacity = 3
	elif character.personality.energy >= 30: holding_capacity = 2
	
	var holding := holding_capacity
	var dishes := _get_dishes(dumping_ground)
	if petty and dishes[character.npc_name] < holding: holding = dishes[character.npc_name]
	elif dishes.total < holding: holding = dishes.total
	
	var grabbed_dish: Node3D = dumping_ground.get_node("Dishes").get_child(0)
	grabbed_dish.reparent(character.model.get_node("Hand"))
	grabbed_dish.position = Vector3.ZERO
	if holding > 1:
		for i in range(holding - 1): dumping_ground.get_node("Dishes").get_child(0).queue_free()
	
	# prioritise own dishes first ^_^
	if dumping_ground.get_meta(character.npc_name, 0) < holding:
		var leftover = holding - dumping_ground.get_meta(character.npc_name, 0)
		dumping_ground.set_meta(character.npc_name, 0)
		dumping_ground.set_meta(other.npc_name, dumping_ground.get_meta(other.npc_name, 0) - leftover)
		if dumping_ground.get_meta(other.npc_name, 0) < 0: dumping_ground.set_meta(other.npc_name, 0)
	else:
		dumping_ground.set_meta(character.npc_name, dumping_ground.get_meta(character.npc_name, 0) - holding)

func _wash_dirty_dish(character: Character) -> void:
	$Sounds/Water.play()
	$Sounds/Dishes.play()
	character.model.get_node("Hand").get_child(0).queue_free()
	character.personality.energy -= randi_range(2, 4)
	await get_tree().create_timer(5, false).timeout

func _set_dishes_memories(character: Character, dumping_ground: Area3D) -> void:
	var starting_dishes: Dictionary = character.get_meta("starting_dishes")
	var petty: bool = character.get_meta("petty")
	var other := Chuuni.get_other_character(character)
	
	if petty:
		character.create_memory(dumping_ground, ["satisfaction"])
		character.create_memory(other, ["satisfaction"])
	elif dumping_ground == $DumpingGround:
		var total_dishes: float = floor(float(starting_dishes.total))
		var chr_dishes: float = floor(float(starting_dishes[character.npc_name]))
		var other_dishes: float = floor(float(starting_dishes[other.npc_name]))
		var own := (chr_dishes * 100) / total_dishes # percentage of dishes that belonged to character
		if own >= 0.75:
			character.create_memory(dumping_ground, ["boredom", "satisfaction"])
		elif own >= 0.5: # they resent the other if half the dishes are hers
			character.create_memory(dumping_ground, ["boredom", "satisfaction"])
			character.create_memory(other, ["resentment"])
		else: # they resent doing the dishes if it's mostly the other guy's dishes
			character.create_memory(dumping_ground, ["boredom", "resentment"])
			character.create_memory(other, ["resentment"])
		print(starting_dishes)
		print("percentage of dishes that were hers: ", own)
	else: # dishes in character's own room
		character.create_memory($Sink, ["boredom", "satisfaction"])
	
	character.remove_meta("petty")
	character.remove_meta("starting_dishes")

func cook_microwave(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to.bind($Fridge),
		_grab_from_fridge, _navigate_to.bind($Microwave),
		_microwave, _finish_cooking]
	return Chuuni.create_action(character, subactions, "cook (microwave)")

func cook_counter(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to.bind($Fridge),
	_grab_from_fridge, _navigate_to.bind($Counter),
	_prepare_at_counter, _finish_cooking]
	return Chuuni.create_action(character, subactions, "cook (counter)")

func cook_fridge(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to.bind($Fridge),
	_grab_from_fridge, _finish_cooking]
	return Chuuni.create_action(character, subactions, "cook (fridge)")

func wash_dishes(character: Character) -> Action:
	var subactions: Array[Callable] = [
		_navigate_to.bind($Sink), _wash, _finish_cooking]
	return Chuuni.create_action(character, subactions, "wash dishes")

func abandon_dishes(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to.bind($Counter),
	_abandon_dishes.bind($DumpingGround), _finish_cooking]
	return Chuuni.create_action(character, subactions, "abandon dishes")

func abandon_dishes_in_room(character: Character) -> Action:
	var dumping_ground: Area3D = character.bedroom.get_node("Objects/DumpingGround")
	var front: Marker3D = dumping_ground.get_node("Front")
	
	var subactions: Array[Callable] = [
		GlobalActions._walk_to.bind(front.global_position), _abandon_dishes.bind(dumping_ground)]
	return Chuuni.create_action(character, subactions, "abandon dishes in room")

func _navigate_to(action: Action, object: Node3D) -> void:
	var other := Chuuni.get_other_character(action.character)
	var front_point: Vector3 = object.get_node("Front").global_position
	var nearest_waiting_point: Vector3
	for marker: Marker3D in $WaitingAreas.get_children():
		if not nearest_waiting_point: nearest_waiting_point = marker.global_position; continue
		if front_point.distance_to(marker.global_position) < front_point.distance_to(nearest_waiting_point):
			nearest_waiting_point = marker.global_position
	
	if $KitchenArea.overlaps_body(action.character.model):
		if other.state_machine.using_object == object.name.to_lower():
			GlobalActions.walk_to(action.character, nearest_waiting_point)
			action.character.state_machine.state = StateMachine.State.WAITING
			await other.state_machine.using_object_changed
		
		action.character.state_machine.using_object = object.name.to_lower()
		await GlobalActions.walk_to(action.character, object.get_node("Front").global_position)
		
	else:
		GlobalActions.walk_to(action.character, object.get_node("Front").global_position)
		while true: # if it ever becomes possible to cancel this action i need to change this while loop
			await get_tree().create_timer(0.1, false).timeout
			if $KitchenArea.overlaps_body(action.character.model): break
		
		if other.state_machine.using_object == object.name.to_lower():
			GlobalActions.walk_to(action.character, nearest_waiting_point)
			action.character.state_machine.state = StateMachine.State.WAITING
			await other.state_machine.using_object_changed
		
		action.character.state_machine.using_object = object.name.to_lower()
		await GlobalActions.walk_to(action.character, object.get_node("Front").global_position)
	
	action.character.state_machine.state = StateMachine.State.BUSY
	action.subaction_finished.emit()

# this function runs in every cooking action so im putting a bunch of misc shit in here too
func _grab_from_fridge(action: Action, for_self := true) -> void:
	_set_state(action, StateMachine.State.BUSY)
	if for_self:
		_set_hunger_target(action.character, 10)
	get_tree().create_timer(1, false).timeout.connect(action.subaction_finished.emit)
	
	# load plate
	var plate_scene := preload("res://scene/room/objects/food_plate.tscn")
	var plate := plate_scene.instantiate()
	Chuuni.give_character_item(action.character, plate)

func _microwave(action: Action) -> void:
	_set_state(action, StateMachine.State.BUSY)
	_set_hunger_target(action.character, 30)
	action.character.personality.energy -= 1
	
	action.character.model.look_at_target = $Microwave.global_position
	var plate = action.character.model.get_node("Hand").get_child(0)
	plate.hide()
	
	var on := $Microwave/On
	var off := $Microwave/Off
	off.hide(); on.show()
	$Microwave/Sounds/Hum.play()
	$Microwave/AreaLight3D.show()
	$Microwave/AreaLight3D2.show()
	
	get_tree().create_timer(10, false).timeout.connect(func():
		$Microwave/Sounds/Hum.stop()
		$Microwave/Sounds/Close.play()
		off.show(); on.hide()
		plate.show()
		$Microwave/AreaLight3D.hide()
		$Microwave/AreaLight3D2.hide()
		action.character.model.look_at_target = Vector3.ZERO
		
		action.subaction_finished.emit())

func _prepare_at_counter(action: Action) -> void:
	_set_state(action, StateMachine.State.BUSY)
	_set_hunger_target(action.character, 50)
	var personality := action.character.personality
	if $DumpingGround/Dishes.get_child_count() >= 5:
		action.character.create_memory($Counter, ["resentment"])
	elif personality.happiness <= personality.happiness_constraint / 2:
		action.character.create_memory($Counter, ["boredom"])
	else: action.character.create_memory($Counter, ["satisfaction"])
	
	action.character.model.look_at_target = $Counter.global_position
	$Sounds/Cutting.play()
	get_tree().create_timer(15, false).timeout.connect(func():
		$Sounds/Cutting.stop()
		action.character.model.look_at_target = Vector3.ZERO
		action.subaction_finished.emit())

func _wash(action: Action) -> void:
	_set_state(action, StateMachine.State.BUSY)
	action.character.model.get_node("Hand").get_child(0).queue_free()
	action.character.personality.energy -= 2
	get_tree().create_timer(5, false).timeout.connect(action.subaction_finished.emit)

func _abandon_dishes(action: Action, dumping_ground: Area3D) -> void:
	var plate: Node3D = action.character.model.get_node("Hand").get_child(0)
	plate.reparent(dumping_ground.get_node("Dishes"))
	if dumping_ground == $DumpingGround:
		plate.position = Vector3(randi_range(-80, 80) * 0.01, 0, randi_range(-35, 35) * 0.01)
	else:
		plate.position = Vector3(randi_range(0, 90) * 0.01, 0, randi_range(0, 90) * 0.01)
	plate.abandoned.emit()
	print(action.character.npc_name + " abandoned her dishes. what a terrible person.")
	
	dumping_ground.set_meta(action.character.npc_name,
		dumping_ground.get_meta(action.character.npc_name, 0) + 1)
	
	action.subaction_finished.emit()

func _finish_cooking(action: Action) -> void:
	# add memory if sharing the kitchen
	var other := Chuuni.get_other_character(action.character)
	var associations := []
	if action.character.get_feelings_toward(other).fear >= 5: associations.append("fear")
	if Chuuni.is_enemies(): associations.append("resentment")
	var memory_objects := [other, $Sink, $Counter]
	# this is going to inflate really quick but maybe it'll be fine
	
	if $KitchenArea.overlaps_body(other.model):
		if associations.is_empty() and Chuuni.is_friends():
			for object in memory_objects:
				action.character.create_memory(object, ["joy"])
		elif not associations.is_empty():
			for object in memory_objects:
				action.character.create_memory(object, associations)
		
	# bad memory gets added as long as the other character is in the same room ^_^
	elif other.current_zone.name == "MainArea" and not associations.is_empty():
		for object in memory_objects:
			action.character.create_memory(object, associations)
	# if their relationship is neutral they get no memory ^_^b
	
	var hand: Node3D = action.character.model.get_node("Hand")
	if hand.get_child_count() == 1 and hand.get_child(0) is FoodPlate:
		_decide_eating_location(action.character)
	
	action.character.state_machine.using_object = ""
	action.subaction_finished.emit()

func _set_hunger_target(character: Character, add: int) -> void:
	var target := character.personality.hunger + add
	var constraint := character.personality.stat_constraints[0]
	if target > constraint: target = constraint
	character.set_meta("hunger_target", target)
