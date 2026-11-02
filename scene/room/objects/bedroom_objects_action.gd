extends Node

func _ready() -> void:
	# queue eat in bed action when triggered
	for character: Character in Chuuni.characters.values():
		character.eat_in_bed.connect(func():
			character.state_machine.queue_action(eat_in_bed(character), true))
	
	_setup.call_deferred()

func _setup() -> void:
	# create intangible objects for memory associations
	for chr: Character in Chuuni.characters.values():
		var bedroom_objects: Node3D = chr.bedroom.get_node("Objects")
		var extra_objects := ["Diary", "Marker"]
		for object_name in extra_objects:
			var object := Node.new()
			object.name = object_name
			bedroom_objects.add_child(object)
	
	GlobalActions.register_action(write_in_diary, ["Diary"], ["happiness"], _diary_req, "write in diary")
	GlobalActions.register_action(cry_in_bed, ["Bed"], ["happiness"], _cry_requirements, "cry in bed")
	GlobalActions.register_action(sleep, ["Bed"], ["energy"], _sleep_req, "sleep")
	GlobalActions.register_action(depression_nap, ["Bed"], ["energy"], _depression_nap_req, "depression nap")

func _get_objects(character: Character) -> Dictionary:
	var objects := {}
	for object in character.bedroom.get_node("Objects").get_children():
		if not object is Node3D: objects[object.name.to_snake_case()] = object; continue
		objects[object.name.to_snake_case()] = {"object": object}
		for child in object.get_children():
			if child is Marker3D: objects[object.name.to_snake_case()][child.name.to_snake_case()] = child
	return objects

#region diary
func write_in_diary(character: Character) -> Action:
	var room_objects := _get_objects(character)
	var walk_to_shelf: Callable = GlobalActions._walk_to.bind(room_objects.shelf.front.global_position)
	
	var subactions: Array[Callable] = [walk_to_shelf, _grab_diary,
	GlobalActions._walk_to.bind(room_objects.bed.side.global_position), _get_on_bed,
	_write_in_diary, _get_off_bed, walk_to_shelf, _put_diary_away]
	return Chuuni.create_action(character, subactions, "write in diary", Chuuni.get_zone(character.bedroom))

func _diary_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.personality = character.personality.melancholy >= 10
	req.mood = character.personality.energy <= 45 and character.personality.energy > 5
	req.possible = character.personality.melancholy >= 0
	
	if character.personality.happiness <= 10:
		req.personality = character.personality.melancholy >= 0
		req.mood = true
	if Chuuni.relationship > 0 and randi() % 3 == 1: req.context = false
	
	return req

func _grab_diary(action: Action) -> void:
	action.character.state_machine.state = StateMachine.State.BUSY
	action.character.model.look_at_target = _get_objects(action.character).shelf.object.global_position
	var diary_res := preload("res://scene/room/objects/diary.tscn")
	var diary := diary_res.instantiate()
	Chuuni.give_character_item(action.character, diary)
	diary.get_node("Sounds/Grab").play()
	action.character.set_meta("social_decay", action.character.personality.social_decay)
	action.character.personality.social_decay = action.character.personality.social_decay * 2
	_toggle_diary_visible(action.character, false)
	await get_tree().create_timer(0.5, false).timeout
	action.character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()

func _toggle_diary_visible(chr: Character, visible: bool) -> void:
	var diary: Node3D = _get_objects(chr).shelf.object.get_node("Items/Diary")
	diary.visible = visible

func _write_in_diary(action: Action) -> void:
	action.character.state_machine.state = StateMachine.State.BUSY
	
	var diary: Node3D = action.character.model.get_node("Hand").get_child(0)
	diary.get_node("AnimationPlayer").play("open")
	get_tree().create_timer(0.5, false).timeout.connect(func():
		diary.get_node("Sounds/Write").play())
	
	for i in range(10):
		action.character.personality.happiness += randi_range(1, 2)
		action.character.personality.energy += randi_range(0, 2)
		await get_tree().create_timer(2, false).timeout
	action.character.personality.social_decay = action.character.get_meta("social_decay")
	action.character.remove_meta("social_decay")
	
	diary.get_node("AnimationPlayer").play("despawn_marker")
	diary.get_node("Sounds/Write").stop()
	
	var sentiments := ["joy"] if action.character.personality.melancholy >= 13 else ["boredom"]
	action.character.create_memory(_get_objects(action.character).diary, sentiments)
	action.subaction_finished.emit()

func _put_diary_away(action: Action) -> void: # it makes sense to abstract this to "put item away" eventually
	action.character.model.look_at_target = _get_objects(action.character).shelf.object.global_position
	action.character.model.get_node("Hand").get_child(0).queue_free()
	_toggle_diary_visible(action.character, true)
	await get_tree().create_timer(0.5, false).timeout
	action.character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()
#endregion
#region bed
func cry_in_bed(character: Character) -> Action:
	var bedside: Vector3 = _get_objects(character).bed.side.global_position
	var subactions: Array[Callable] = [GlobalActions._walk_to.bind(bedside), _get_on_bed, _loop_cry, _get_off_bed]
	return Chuuni.create_action(character, subactions, "cry in bed", Chuuni.get_zone(character.bedroom))

func _cry_requirements(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.all_false()
	req.mood = character.personality.happiness <= 10
	# melancholic characters have a lower threshold to start crying in bed
	if not req.mood and character.personality.melancholy >= 10:
		req.mood = character.personality.happiness <= 20
	req.possible = req.mood
	return req

func eat_in_bed(character: Character) -> Action:
	var bedside: Vector3 = _get_objects(character).bed.side.global_position
	var subactions: Array[Callable] = [GlobalActions._walk_to.bind(bedside),
	_get_on_bed, _eat, _get_off_bed]
	return Chuuni.create_action(character, subactions, "eat in bed", Chuuni.get_zone(character.bedroom))

func _get_on_bed(action: Action) -> void:
	action.character.state_machine.state = StateMachine.State.BUSY
	var model: CharacterBody3D = action.character.model
	var bed = _get_objects(action.character).bed
	model.look_at_target = bed.side.global_position
	model.jump()
	model.sit()
	model.position_target = bed.top.global_position
	await model.reached_target
	action.subaction_finished.emit()

func _get_inside_bed(action: Action) -> void:
	var model := action.character.model
	var bed = _get_objects(action.character).bed
	model.position_target = bed.top_2.global_position
	await model.reached_target
	model.look_at_target = bed.top.global_position
	await get_tree().create_timer(0.2, false).timeout
	
	var tween := get_tree().create_tween().set_parallel()
	var duration := 0.4
	var marker: Marker3D = bed.inside
	
	model.hold_position = true
	tween.tween_property(model, "global_position:y", model.global_position.y + 0.14, 0.1)
	tween.tween_property(model, "global_position:z", model.global_position.z - 0.2, 0.1)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_property(model, "global_position", marker.global_position, duration)
	tween.tween_property(model, "rotation", marker.rotation, duration)
	tween.tween_callback(bed.object.get_node("AnimationPlayer").play.bind("squish_pillow")).set_delay(0.2)
	
	action.subaction_finished.emit()

func _assume_nap_position(action: Action) -> void:
	var model := action.character.model
	var bed = _get_objects(action.character).bed
	var look_position: Vector3 = bed.nap_space.global_position
	look_position.x -= 1
	model.look_at_target = look_position
	model.position_target = bed.nap_space.global_position
	await model.reached_target
	await get_tree().create_timer(0.2).timeout
	
	var tween := get_tree().create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK)
	var duration := 1
	
	model.hold_position = true
	tween.tween_property(model, "rotation", bed.nap_space.rotation, duration)
	get_tree().create_timer(0.8, false).timeout.connect(model.get_node("Land").play)
	await tween.finished
	action.subaction_finished.emit()

func _loop_cry(action: Action) -> void:
	var target: int = action.character.personality.happiness + 10
	print(action.character.npc_name + " is crying until her sadness is at ", target)
	while true:
		var finished = await _cry(action.character, target)
		if finished: break
	
	var associations := ["resentment"] if action.character.personality.melancholy < 10 \
		else ["respect"]
	action.character.create_memory(_get_objects(action.character).bed.object, associations, "cry")
	action.subaction_finished.emit()

func _cry(character: Character, target: int) -> bool:
	character.personality.happiness += 1
	await get_tree().create_timer(1, false).timeout
	return character.personality.happiness >= target

func _eat(action: Action) -> void:
	action.character.model.start_eating()
	await action.character.model.finished_eating
	action.subaction_finished.emit()

func _get_off_bed(action: Action) -> void:
	var model: CharacterBody3D = action.character.model
	model.stand()
	model.look_at_target = Vector3.ZERO
	model.position_target = _get_objects(action.character).bed.side.global_position
	await get_tree().create_timer(1, false).timeout
	model.position_target = Vector3.ZERO
	action.character.state_machine.state = StateMachine.State.IDLE
	action.subaction_finished.emit()
#endregion
#region sleep
func sleep(character: Character) -> Action:
	var bed: Dictionary = _get_objects(character).bed
	var subactions: Array[Callable] = [_check_music.bind(sleep),
		GlobalActions._walk_to.bind(bed.side.global_position), _get_on_bed,
		_get_inside_bed, _start_sleep, _wake_from_sleep, _get_off_bed]
	return Chuuni.create_action(character, subactions, "sleep", Chuuni.get_zone(character.bedroom))

# can't sleep if music is playing ^_^
func _check_music(action: Action, action_callable: Callable) -> void:
	var stereo = get_tree().current_scene.get_node("MainRoom/Objects/Stereo")
	if stereo.music_on:
		if action.character.personality.activeness > 0 or Chuuni.the_powerful == action.character or \
		stereo.toggled_character == action.character:
			print(action.character.npc_name + " is turning off music because she wants to SLEEP")
			action.character.state_machine.queue_action(stereo.turn_off_music(action.character))
			action.character.state_machine.queue_action(action_callable.call(action.character))
			action.cancel()
		elif action.character.personality.energy > 2:
			print(action.character.npc_name + " can't sleep because she doesn't have the courage to turn off the music")
			action.character.create_memory(Chuuni.get_other_character(action.character), ["resentment"])
			action.character.create_memory(stereo, ["resentment"], "sleep")
			action.character.set_meta("sleep_deprived", true)
			action.cancel()
	action.subaction_finished.emit()

func depression_nap(character: Character) -> Action:
	var bed: Dictionary = _get_objects(character).bed
	var subactions: Array[Callable] = [GlobalActions._walk_to.bind(bed.side.global_position),
	_get_on_bed, _assume_nap_position, _start_sleep.bind(character.personality.energy + 20),
	_wake_from_nap, _get_off_bed]
	return Chuuni.create_action(character, subactions, "depression nap", Chuuni.get_zone(character.bedroom))

func _depression_nap_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.all_false()
	req.possible = character.personality.happiness <= character.personality.happiness_constraint / 3 and \
		character.personality.energy <= character.personality.energy_constraint / 2
	req.mood = req.possible
	return req

func _sleep_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.all_false()
	req.possible = character.personality.energy < 20
	if character.has_meta("sleep_deprived"):
		req.possible = false
	req.mood = character.personality.energy <= 8
	return req

func _decide_sleep_quality(character: Character, max_target: int) -> int:
	var personality := character.personality
	var target := randi_range(max_target - 15, max_target)
	var minimum := personality.energy + 10
	
	if personality.happiness <= personality.happiness_constraint / 2:
		target -= Chuuni.get_difference(personality.happiness, personality.happiness_constraint / 2)
	if personality.fear > 0: target -= personality.fear
	if target < minimum or character.has_meta("sleep_deprived"): target = minimum
	character.remove_meta("sleep_deprived")
	return target

func _start_sleep(action: Action, max_target: int = 0) -> void:
	if max_target == 0: max_target = action.character.personality.energy_constraint
	var energy_target := _decide_sleep_quality(action.character, max_target)
	action.character.state_machine.state = StateMachine.State.SLEEPING
	print(action.character.npc_name + " is sleeping until energy is at ", energy_target)
	var model := action.character.model
	model.sleep()
	var snore_tween := get_tree().create_tween().set_loops()
	snore_tween.tween_callback(model.get_node("Snore").play).set_delay(6)
	
	while action.character.personality.energy < energy_target:
		if action.character.sleep_interrupted:
			action.character.sleep_interrupted = false
			break
		action.character.personality.energy += 1
		await get_tree().create_timer(1, false).timeout
	snore_tween.kill()
	action.subaction_finished.emit()

func _wake_from_sleep(action: Action) -> void:
	var model := action.character.model
	model.wake_up()
	await get_tree().create_timer(1, false).timeout
	var bed = _get_objects(action.character).bed
	var tween := get_tree().create_tween().set_parallel()
	var duration := 0.4
	model.get_node("Jump").play()
	tween.tween_property(model, "global_position", bed.top_2.global_position, duration)
	tween.tween_property(model, "rotation:x", bed.top_2.rotation.x, duration)
	bed.object.get_node("AnimationPlayer").play_backwards("squish_pillow")
	await tween.finished
	
	model.hold_position = false
	model.position_target = bed.top.global_position
	await model.reached_target
	model.look_at_target = bed.side.global_position
	action.subaction_finished.emit()

func _wake_from_nap(action: Action) -> void:
	var model := action.character.model
	model.look_at_target = Vector3.ZERO
	model.wake_up()
	var bed = _get_objects(action.character).bed
	var tween := get_tree().create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK)
	var duration := 1
	
	tween.tween_property(model, "rotation:x", 0, duration)
	tween.tween_property(model, "rotation:z", 0, duration)
	await tween.finished
	await get_tree().create_timer(0.2).timeout
	model.hold_position = false
	model.position_target = bed.top.global_position
	await model.reached_target
	model.look_at_target = bed.side.global_position
	action.subaction_finished.emit()
#endregion
