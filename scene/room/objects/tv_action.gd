extends Node3D

@onready var seats := [get_node("../Seat1"), get_node("../Seat2")]
@onready var screen_material: StandardMaterial3D = %Screen.get_surface_override_material(0)
var replenishment_threshold := 10
var boredom_threshold := [7, 18]
var current_channel := "":
	set(value): current_channel = value; channel_changed.emit()
var tv_on := true:
	set(value):
		tv_on = value
		screen_material.emission_enabled = tv_on
		%Screen/SpotLight3D.visible = tv_on
		if not tv_on:
			current_channel = ""
			screen_material.albedo_color = tv_colours.off
			%Sounds/Buzz.stop()
			for sound in %Sounds.get_children():
				if sound.name.to_lower() in tv_colours.keys() and sound.playing: sound.stop()
		else:
			%Sounds/Buzz.play()

var tv_colours := {
	"off": Color.from_rgba8(109, 140, 115, 255),
	"anger": Color.from_rgba8(255, 0, 0, 255),
	"melancholy": Color.from_rgba8(0, 64, 255, 255),
	"whimsy": Color.from_rgba8(255, 0, 225, 255)
}

signal channel_changed

func _ready():
	tv_on = false
	GlobalActions.register_action(watch_tv, [get_parent()], ["energy", "social"], _watch_tv_requirements, "watch tv")

func _watch_tv_requirements(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	req.relationship = false
	req.mood = false
	if tv_on: # requirements to watch together
		req.mood = character.personality.energy > 10 # always true unless energy is critically low
		if Chuuni.relationship >= 0: req.relationship = true # always true if relationship is above zero
		elif Chuuni.relationship < 0:
			# can watch together with low relationship IF character has resentment and high activeness
			var feelings := character.get_feelings_toward(other)
			if "resentment" in feelings and feelings.resentment > 0: req.relationship = true
			if req.relationship and character.personality.activeness < 10: req.relationship = false
	
	else: # requirements to watch alone
		req.mood = character.personality.energy <= character.personality.energy_constraint / 1.5 and \
			character.personality.energy > 10 and character.personality.fear < 25
		# loneliness makes watching tv more alluring even if you have enough energy to do other shit ^_^
		if character.personality.social <= 25 and character.personality.fear < 25 and \
		not req.mood: req.mood = true
		
		if Chuuni.relationship >= 0: req.relationship = true
		# can watch alone if relationship is low but the other character isn't in the room
		elif Chuuni.relationship < 0 and other.current_zone.name != "MainArea": req.relationship = true
		# if high activeness, she dgaf if she's spotted in a common area no matter the relationship
		elif character.personality.activeness >= 10: req.relationship = true
	
	var stereo: Stereo = get_tree().current_scene.get_node("MainRoom/Objects/Stereo")
	if stereo.music_on: req.possible = false # holy shit have mercy on my ears
	
	return req

func watch_tv(character: Character) -> Action:
	var subactions: Array[Callable] = [
		GlobalActions._walk_to.bind(_find_empty_seat(character)\
		.get_node("Front/CollisionShape3D").global_position),
		_sit.bind(character), _watch.bind(character),
		_leave_seat.bind(character)
	]
	return Chuuni.create_action(character, subactions, "watch tv")

func eat_at_tv(character: Character) -> Action:
	return Chuuni.create_action(character, watch_tv(character).subactions, "eat at tv")

func _find_empty_seat(character: Character) -> Node3D:
	print("finding empty seat for " + character.npc_name)
	if character.has_meta("seat"): character.remove_meta("seat")
	for seat: Node3D in seats:
		if seat.has_meta("sitter"): continue
		character.set_meta("seat", seat)
		seat.set_meta("sitter", character)
		# ^ might have to write a cleanup function if this action ever gets cancelled during this sequence ^_^
		# maybe i should add a "can_interrupt" property to the state machine to avoid objects breaking if needed?
		return seat
	return

func _sit(action: Action, character: Character) -> void:
	if character.has_meta("tv_memories_added"): # debug
		printerr(character.npc_name + " still has tv_memories_added metadata")
	
	character.state_machine.state = StateMachine.State.BUSY
	var seat = character.get_meta("seat")
	seat.set_meta("sitter", character)
	character.model.look_at_target = %Screen.global_position
	character.model.jump()
	character.model.sit()
	character.model.position_target = seat.get_node("Top").global_position
	await character.model.reached_target
	print("finished waiting for the fucking donut to SIT. DOWN.")
	
	character.set_meta("is_sitting", true)
	_decide_channel(character)
	action.subaction_finished.emit()

func _decide_channel(character: Character) -> void:
	if current_channel != "" and character.personality.activeness < 5 and \
	not _is_alone(): return
	
	var personality := character.personality
	var highest_trait: String
	for _trait: String in personality.personality_traits:
		if not highest_trait: highest_trait = _trait; continue
		if personality[_trait] > personality[highest_trait]: highest_trait = _trait
	if current_channel == highest_trait: return
	if _is_alone(): _set_channel(highest_trait); return
	if current_channel == "": await channel_changed
	
	var other := Chuuni.get_other_character(character)
	if Chuuni.the_powerful == other: return
	if character.personality[current_channel] >= replenishment_threshold: return
	var more_active := character.personality.activeness > other.personality.activeness
	if more_active and character.personality.activeness > 0: _set_channel(highest_trait)

func _set_channel(channel: String) -> void:
	%Sounds/Click.play()
	for sound: AudioStreamPlayer3D in %Sounds.get_children():
		if sound.playing and sound.name.to_lower() in tv_colours.keys(): sound.stop()
	var sound_name: String = channel.to_pascal_case()
	if %Sounds.has_node(sound_name):
		var sound: AudioStreamPlayer3D = %Sounds.get_node(sound_name)
		sound.play(randf_range(0, sound.stream.get_length()))
	
	current_channel = channel
	screen_material.albedo_color = tv_colours[current_channel]
	screen_material.emission = tv_colours[current_channel]
	%Screen/SpotLight3D.light_color = tv_colours[current_channel]
	if not tv_on: tv_on = true

func _watch(action: Action, character: Character) -> void:
	var action_is_eat := "eat" in action.action_name
	if not character.has_meta("boredom") and not action_is_eat:
		character.set_meta("boredom", 0)
		character.set_meta("boredom_threshold",
		randi_range(boredom_threshold[0], boredom_threshold[1]))
	elif not "eat" in action.action_name:
		character.set_meta("boredom", character.get_meta("boredom") + 1)
	
	if action_is_eat and not character.has_meta("started_eating"):
		character.model.start_eating()
		character.set_meta("started_eating", true)
	
	character.is_socialising = not _is_alone()
	if character.is_socialising:
		character.personality.social += 1
		# random chance of increasing relationship if they both like the channel
		var other := Chuuni.get_other_character(character)
		if current_channel in character.personality:
			if character.personality[current_channel] >= replenishment_threshold and \
			other.personality[current_channel] >= replenishment_threshold:
				if randi() % 10 == 1: Chuuni.relationship += 1
	
	if current_channel in character.personality and \
	character.personality[current_channel] >= replenishment_threshold:
		character.personality.energy += randi_range(0, 2)
	elif _is_alone():
		#_decide_channel(character)
		character.personality.energy -= randi_range(0, 1)
	elif character.has_meta("is_sitting") and \
	Chuuni.get_other_character(character).has_meta("is_sitting"):
		character.personality.energy -= randi_range(0, 1)
		character.personality.happiness -= randi_range(0, 1)
		if randi() % 10 == 1: Chuuni.relationship -= 1
		if Chuuni.relationship <= 5: character.personality.happiness -= 1
		if randi() % 10 == 1: character.personality.anger += 1
	
	var will_leave_early = false
	var reason := 0 # 0 = leaving because of relationship, 1 = leaving because of needs
	if Chuuni.relationship <= 30 and character.personality.happiness <= 15:
		if randi() % 20 == 1: will_leave_early = true
	if character.personality[current_channel] >= replenishment_threshold\
	and Chuuni.relationship >= 0: will_leave_early = false
	if character.personality.energy <= 5: will_leave_early = true; reason = 1
	if character.model.is_eating: will_leave_early = false
	if _is_alone(): will_leave_early = false
	if will_leave_early:
		print(character.npc_name + " is leaving early")
		character.set_meta("leave_early_reason", reason)
	
	var leave_conditions_met
	if character.has_meta("boredom"):
		leave_conditions_met = character.get_meta("boredom") >= character.get_meta("boredom_threshold")
	else: leave_conditions_met = not character.model.is_eating
	
	if not action_is_eat and not character.state_machine.action_queue.is_empty():
		if "respond" in character.state_machine.action_queue[0].action_name: leave_conditions_met = true
	
	if leave_conditions_met or will_leave_early:
		var alone := _is_alone()
		character.remove_meta("is_sitting")
		if alone:
			tv_on = false
			%Sounds/Click.play()
		else: _decide_channel(Chuuni.get_other_character(character))
		character.remove_meta("boredom")
		character.remove_meta("boredom_threshold")
		character.remove_meta("started_eating")
		_add_tv_memories(character, not alone)
		action.subaction_finished.emit()
		return
	
	get_tree().create_timer(2, false).timeout.connect(_watch.bind(action, character))

func _is_alone() -> bool:
	for character: Character in Chuuni.characters.values():
		if not character.has_meta("is_sitting"): return true
	return false

# runs when a character leaves their seat after watching tv
# if they were both watching, it also adds the memories for the remaining party
func _add_tv_memories(character: Character, is_together: bool) -> void:
	# don't add new memories if memories were already added when other character left
	if character.has_meta("tv_memories_added"):
		character.remove_meta("tv_memories_added")
		return
	
	# add memories if they're watching tv together
	if is_together:
		var other := Chuuni.get_other_character(character)
		other.set_meta("tv_memories_added", true)
		var chr_enjoyment: int = character.personality[current_channel]
		var other_enjoyment: int = other.personality[current_channel]
		
		# special case for if character left early due to negative relationship
		if character.get_meta("leave_early_reason", -1) == 0:
			Chuuni.tally_winner(character)
			Chuuni.relationship -= 3
			print("other character is betrayed because mf left early")
			var associations := {character: ["resentment"], other: ["betrayal", "resentment"]}
			for chr: Character in Chuuni.characters.values():
				chr.create_memory(get_parent(), associations[chr])
				chr.create_memory(Chuuni.get_other_character(chr), associations[chr], "tv")
			return
		
		# figure out who chose the channel
		var chooser: Character
		var sucker: Character
		if chr_enjoyment > other_enjoyment: chooser = character; sucker = other
		else: chooser = other; sucker = character
		
		# TODO: add priority case for if both of them dislike the channel for.. some reason
		# they both like the channel
		if chr_enjoyment >= replenishment_threshold and other_enjoyment >= replenishment_threshold:
			print("they both liked the channel")
			Chuuni.relationship += 5
			for chr: Character in Chuuni.characters.values():
				chr.create_memory(Chuuni.get_other_character(chr), ["joy"], "tv")
				chr.create_memory(get_parent(), ["joy"], "together")
				Chuuni.tally_winner(chr)
			
		# one likes the channel and the other is neutral
		elif sucker.personality[current_channel] > 4:
			print("one liked it, other was neutral")
			Chuuni.tally_winner(chooser)
			Chuuni.relationship += 3
			var associations := {chooser: ["satisfaction"], sucker: ["respect"]}
			for chr: Character in associations.keys():
				chr.create_memory(get_parent(), associations[chr], "together")
				chr.create_memory(Chuuni.get_other_character(chr), associations[chr], "tv")
			
		# one likes the channel and the other hates it
		elif sucker.personality[current_channel] <= 4:
			# high respect or high relationship results in a positive memory even though sucker hated every second
			if Chuuni.is_friends() or sucker.get_feelings_toward(chooser).respect >= 5:
				print("one hated the channel but good memory anyway")
				Chuuni.relationship += 1
				var associations := {chooser: ["satisfaction"], sucker: ["respect", "resentment", "boredom"]}
				for chr: Character in associations.keys():
					chr.create_memory(get_parent(), associations[chr], "together")
					chr.create_memory(Chuuni.get_other_character(chr), associations[chr], "tv")
				
			# otherwise sucker is appropriately unhappy
			else:
				print("the one who hated that channel is upset now")
				Chuuni.relationship -= 5
				var associations := {chooser: ["satisfaction"], sucker: ["resentment"]}
				for chr: Character in associations.keys():
					chr.create_memory(get_parent(), associations[chr], "together")
					chr.create_memory(Chuuni.get_other_character(chr), associations[chr], "tv")
				
			Chuuni.tally_winner(chooser)
		
	else: # add memories for watching tv alone
		var context = "" if not Chuuni.is_enemies() else "alone"
		character.create_memory(get_parent(), ["joy"], context)

func _leave_seat(action: Action, character: Character) -> void:
	character.is_socialising = false
	character.model.stand()
	var seat = character.get_meta("seat")
	character.remove_meta("seat")
	seat.remove_meta("sitter")
	character.remove_meta("leave_early_reason")
	character.model.position_target = Vector3.ZERO
	character.model.look_at_target = Vector3.ZERO
	var pos: Vector3 = seat.get_node("Front/CollisionShape3D").global_position
	pos.z -= 0.9
	GlobalActions.walk_to(character, pos, true)
	await get_tree().create_timer(1.4, false).timeout
	action.subaction_finished.emit()
