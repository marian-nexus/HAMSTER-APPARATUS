class_name Stereo extends Node3D

var music_on := false:
	set(value):
		music_on = value
		print("Music ", music_on)
		$GPUParticles3D.emitting = value
		if value:
			$MoodTimer.start()
			on_time = 0
		else: $MoodTimer.stop()
var on_time := 0
var toggled_character: Character

@onready var yell_action: Callable = get_tree().current_scene.get_node("Scripts/Talking").yell_at

func _ready() -> void:
	await get_tree().create_timer(1, false).timeout
	GlobalActions.register_action(turn_on_music, [self], ["happiness"], _on_req, "turn on music")
	GlobalActions.register_action(listen_to_music, [self], ["happiness"], _listen_req, "listen to music")
	
	$MoodTimer.timeout.connect(_music_passive_mood)

func turn_on_music(character: Character) -> Action:
	var subactions: Array[Callable] = [GlobalActions._grab_item.bind("remote"), _point_remote.bind(true),
		GlobalActions._put_away_item, _check_for_rage]
	return Chuuni.create_action(character, subactions, "turn on music")

# passively affect the mood of every character in the room while music is on
func _music_passive_mood() -> void:
	on_time += 1
	for chr: Character in Chuuni.characters.values():
		var effect := 1
		var personality := chr.personality
		if chr.current_zone.name != "MainArea":
			if personality.melancholy < 10: continue
			if personality.energy >= personality.energy_constraint / 2: continue
			effect *= -1
		else:
			var mood_is_perfect := personality.happiness >= personality.happiness_constraint - 10 \
				and personality.energy >= personality.energy_constraint - 10
			if personality.melancholy >= 10 and not mood_is_perfect: effect *= -1
			if personality.whimsy > 15: effect += 1
			if chr.has_meta("listening_to_music"): effect += 2
			if personality.energy < personality.energy_constraint / 3: effect -= 1
			if personality.energy < 10: effect -= 1
		
		personality.happiness += effect
		var pissed_off := personality.energy < personality.energy_constraint / 3 and effect < 0
		if personality.melancholy >= 10 and not pissed_off:
			pissed_off = personality.energy < personality.energy_constraint / 2
		
		if pissed_off and randi() % 10 == 1 and _off_req(chr):
			var incompatible_actions := ["draw on wall", "turn off music"]
			for _action in incompatible_actions:
				if GlobalActions.is_queued_or_doing(chr, _action): return
			chr.state_machine.queue_action(turn_off_music(chr))

func listen_to_music(character: Character) -> Action:
	var subactions: Array[Callable] = [GlobalActions._walk_to.bind(Chuuni.get_random_position()),
		_sit_and_listen, _get_up_idiot]
	return Chuuni.create_action(character, subactions, "listen to music")

func turn_off_music(character: Character) -> Action:
	var subactions: Array[Callable] = [GlobalActions._grab_item.bind("remote"), _point_remote.bind(false),
		GlobalActions._put_away_item, _check_for_rage]
	if character.current_zone.name != "MainArea":
		subactions.insert(0, GlobalActions._walk_to.bind(Chuuni.get_nearest_lr_position(character.model)))
	return Chuuni.create_action(character, subactions, "turn off music")

func _on_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var personality := character.personality
	var other := Chuuni.get_other_character(character)
	var other_is_sleeping: bool = other.state_machine.state == StateMachine.State.SLEEPING
	
	req.possible = not GlobalActions.is_queued_or_doing(other, "music")
	if req.possible:
		if personality.happiness <= personality.happiness_constraint - 10 and \
			personality.melancholy >= 10: req.possible = false
	if not req.possible: return req
	
	req.personality = personality.whimsy > 0 and personality.melancholy < 10
	req.mood = personality.energy > 10 and personality.happiness < personality.happiness_constraint - 10
	req.possible = not music_on and character.current_zone.name == "MainArea"
	if req.possible and not Chuuni.is_enemies(): req.possible = not other_is_sleeping
	elif req.possible and Chuuni.is_enemies():
		req.context = character.get_feelings_toward(other).resentment >= 5
	if character.get_feelings_toward(other).fear >= 5: req.context = false
	if req.possible: req.possible = not GlobalActions.is_queued_or_doing(other, "watch tv") \
		and not GlobalActions.is_queued_or_doing(other, "eat at tv")
	
	return req

func _listen_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var personality := character.personality
	req.possible = music_on and not get_node("../TV/CRT").tv_on and personality.energy > 10
	if not req.possible: return req
	
	req.personality = personality.melancholy > 0
	req.context = character.current_zone.name == "MainArea"
	
	return req

func _off_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	req.possible = character.personality.energy < 25
	if Chuuni.the_powerful == character and toggled_character != character:
		req.possible = character.personality.energy <= character.personality.energy_constraint / 2
	
	if character.personality.melancholy >= 10 and on_time > 3:
		req.possible = true
		req.mood = Chuuni.is_enemies()
		req.relationship = character.get_feelings_toward(other).resentment > 0
		req.context = req.mood and req.relationship
	
	if req.possible and character.has_meta("sleep_deprived"): req.possible = false
	if req.possible: req.possible = not GlobalActions.is_queued_or_doing(other, "music")
	
	return req

func _point_remote(action: Action, target: bool) -> void:
	var other := Chuuni.get_other_character(action.character)
	if music_on != target:
		if music_on: print(action.character.npc_name + " has had ENOUGH")
		action.character.model.look_at_target = self.global_position
		await get_tree().create_timer(0.4, false).timeout
		var remote = action.character.model.get_node("Hand").get_child(0)
		remote.get_node("Sound").play()
		music_on = not music_on
		await get_tree().create_timer(0.1, false).timeout
		action.character.model.look_at_target = Vector3.ZERO
		
		if not music_on: $Music.stop()
		
		if music_on:
			toggled_character = action.character
			$Music.play()
			# check if the other character is asleep
			if other.state_machine.state == StateMachine.State.SLEEPING:
				print("WAKE UP IDIOT")
				other.sleep_interrupted = true
				other.personality.happiness -= 5
				other.create_memory(action.character, ["resentment", "betrayal"])
				
				if Chuuni.is_enemies() or Chuuni.the_powerful == action.character:
					action.character.create_memory(other, ["satisfaction"])
				
				if other.personality.activeness >= 0 and Chuuni.the_powerful != action.character:
					other.state_machine.queue_action(yell_action.call(other), true)
			
		elif not music_on and toggled_character != action.character and not \
		other.has_meta("listening_to_music"):
			var ruined := other.current_zone.name == "MainArea" and other.personality.energy > \
				other.personality.energy_constraint / 3
			
			if not Chuuni.is_friends() and ruined:
				Chuuni.tally_winner(action.character)
				Chuuni.relationship -= 2
				other.create_memory(action.character, ["betrayal"], "off")
			
			action.character.create_memory(self, ["boredom"], "off")
		elif not music_on and other.has_meta("listening_to_music"):
			other.state_machine.current_action.cancel()
			other.create_memory(action.character, ["betrayal"], "off")
			if Chuuni.is_enemies(): action.character.create_memory(other, ["satisfaction"], "off")
			if other.personality.activeness > 0 and Chuuni.the_powerful != action.character:
				other.state_machine.queue_action(
					get_tree().current_scene.get_node("Scripts/Talking").yell_at(other, "music"), true)
				#action.character.state_machine.action_queue.resize(0)
				if not action.character.state_machine.action_queue.is_empty():
					var to_erase := []
					for _action: Action in action.character.state_machine.action_queue:
						if not "respond" in _action.action_name: to_erase.append(_action)
					for _action in to_erase:
						action.character.state_machine.action_queue.erase(_action)
	
	for chr: Character in [action.character, other]:
		chr.remove_meta("sleep_deprived")
	
	action.subaction_finished.emit()

# prevent character from doing something else if they pissed off roommate by
# turning off the music while they were listening
func _check_for_rage(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	if GlobalActions.is_queued_or_doing(other, "yell at"):
		#if not "yell at" in other.state_machine.current_action.action_name:
			#await other.state_machine.action_started
		
		while not action.character.state_machine.is_being_accosted():
			await get_tree().create_timer(0.1, false).timeout
			if not GlobalActions.is_queued_or_doing(other, "yell at"): break
	action.subaction_finished.emit()

func _sit_and_listen(action: Action) -> void:
	if not music_on:
		action.cancel()
		return
	
	print(action.character.npc_name + " is listening to the music ^_^")
	action.character.set_meta("listening_to_music", true)
	action.character.model.sit(true)
	
	var other := Chuuni.get_other_character(action.character)
	var together := false
	for i in range(randi_range(8, 20)):
		if action.is_cancelled:
			action.character.remove_meta("listening_to_music")
			return
		action.character.is_socialising = other.has_meta("listening_to_music")
		if not together and other.has_meta("listening_to_music"): together = true
		if action.character.state_machine.is_being_accosted(): break
		
		await get_tree().create_timer(1, false).timeout
	
	action.character.remove_meta("listening_to_music")
	action.character.create_memory(self, ["joy"], "listen")
	if together: action.character.create_memory(other, ["joy"])
	
	action.subaction_finished.emit()

func _get_up_idiot(action: Action) -> void:
	action.character.model.stand()
	await get_tree().create_timer(0.5, false).timeout
	action.subaction_finished.emit()
