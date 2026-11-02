extends Node

var topic: String
var intention: int
var yell_reason := ""

@onready var kitchen = get_tree().current_scene.get_node("MainRoom/Objects/Kitchen")
@onready var kitchen_actions: Dictionary[String, Callable] = {
	"fridge_nav": kitchen._navigate_to.bind(kitchen.get_node("Fridge")),
	"grab_action": kitchen._grab_from_fridge.bind(false),
	"decide_eating_location": kitchen._decide_eating_location,
	"hunger_target": kitchen._set_hunger_target
}

func _ready() -> void:
	GlobalActions.register_action(debate, [], ["social"], _debate_req, "debate")
	GlobalActions.register_action(yell_at, [], ["social"], _yell_req, "yell at")
	GlobalActions.register_action(bring_food, [], ["social"], _bring_food_req, "bring food")

func bring_food(character: Character) -> Action:
	var subactions: Array[Callable] = [kitchen_actions.fridge_nav, kitchen_actions.grab_action,
		_chase_down.bind(_on_bring_cancelled.bind(character)), _give_food]
	var action := Chuuni.create_action(character, subactions, "bring food")
	action.response_callable = bring_food_respond
	return action

func bring_food_respond(character: Character) -> Action:
	var subactions: Array[Callable] = [_prepare_responder, _accept_food]
	return Chuuni.create_action(character, subactions, "bring food (respond)")

func _bring_food_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	req.possible = not GlobalActions.is_leaving_zone(other) and other.personality.hunger <= 20
	if req.possible: req.possible = Chuuni.is_close() or Chuuni.the_powerful == other
	if not req.possible: return req
	
	req.context = other.personality.hunger <= 10
	if GlobalActions.is_queued_or_doing(other, "eat"): req.possible = false; return req
	
	return req

func _give_food(action: Action) -> void:
	action.character.state_machine.using_object = ""
	var other := Chuuni.get_other_character(action.character)
	for chr: Character in Chuuni.characters.values(): chr.is_socialising = true
	await get_tree().create_timer(0.5, false).timeout
	var plate = action.character.model.get_node("Hand").get_child(0)
	plate.reparent(other.model.get_node("Hand"), false)
	plate.changed_parent.emit()
	kitchen_actions.hunger_target.call(other, 5)
	kitchen_actions.decide_eating_location.call(other)
	await get_tree().create_timer(1, false).timeout
	
	Chuuni.relationship += 5
	Chuuni.tally_winner(other)
	other.create_memory(action.character, ["satisfaction"], "bring_food")
	
	var associations = ["joy"]
	if Chuuni.the_powerful == other: associations = ["fear"]
	action.character.create_memory(other, associations, "bring_food")
	
	action.subaction_finished.emit()

func _accept_food(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	await other.state_machine.action_finished
	action.subaction_finished.emit()

func put_food_away(character: Character) -> Action:
	var subactions: Array[Callable] = [kitchen_actions.fridge_nav, _explode_food]
	return Chuuni.create_action(character, subactions, "put food away")

func _on_bring_cancelled(character: Character) -> void:
	character.state_machine.queue_action(put_food_away(character), true)

func _explode_food(action: Action) -> void:
	var plate = action.character.model.get_node("Hand").get_child(0)
	plate.queue_free()
	await get_tree().create_timer(0.5, false).timeout
	action.character.state_machine.using_object = ""
	action.subaction_finished.emit()

func yell_at(character: Character, reason := "") -> Action:
	yell_reason = reason
	var subactions: Array[Callable] = [_chase_down, _yell]
	var action := Chuuni.create_action(character, subactions, "yell at")
	action.response_callable = yell_respond
	action.zone = Chuuni.get_other_character(character).current_zone
	return action

func yell_respond(character: Character) -> Action:
	var subactions: Array[Callable] = [_prepare_responder, _get_yelled_at]
	var action := Chuuni.create_action(character, subactions, "yell at (respond)")
	action.zone = character.current_zone
	return action

func debate(character: Character) -> Action:
	var subactions: Array[Callable] = [_chase_down, _decide_topic_and_intention, _talk_placeholder,
	_decide_winner, _end_debate]
	var action := Chuuni.create_action(character, subactions, "debate")
	action.response_callable = debate_respond
	action.zone = Chuuni.get_other_character(character).current_zone
	return action

func debate_respond(character: Character) -> Action:
	var subactions: Array[Callable] = [_prepare_responder, _listen, _end_debate]
	var action := Chuuni.create_action(character, subactions, "debate (respond)")
	action.zone = character.current_zone
	return action

func _yell_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	var feelings_req_met: bool = character.get_feelings_toward(other).resentment > 0 or \
		character.get_feelings_toward(other).betrayal > 0
	
	var other_is_leaving := false
	if not other.state_machine.current_action: req.possible = false; return req
	if other.state_machine.current_action.zone.name != "MainArea": other_is_leaving = true
	if other.current_zone.name != "MainArea": other_is_leaving = true
	req.possible = not other_is_leaving
	if not req.possible: return req
	
	req.possible = Chuuni.the_powerful == character and \
		character.personality.anger >= 5 and feelings_req_met
	if req.possible: req.possible = character.personality.social <= 40
	return req

func _debate_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	req.personality = character.personality.activeness >= 5 and character.personality.anger >= 10 and \
		character.personality.melancholy < 10
	req.mood = character.personality.energy >= 30 and character.personality.social <= 35
	req.context = true
	req.possible = character.personality.social < 40 and \
		not GlobalActions.is_queued_or_doing(other, "cook")
	if not req.possible: return req
	
	# lower requirements if lonely enough
	if character.personality.social <= 10:
		req.mood = character.personality.energy >= 10
		req.personality = character.personality.activeness >= 5 and character.personality.anger >= 0 \
			and character.personality.melancholy < 10
	
	# other character is in the living area and is not actively leaving
	req.possible = not GlobalActions.is_leaving_zone(other)
	
	if req.possible: req.possible = not GlobalActions.is_queued_or_doing(other, "cook")
	
	return req

func _chase_down(action: Action, cancelled_func = null) -> void:
	var nav_agent: NavigationAgent3D = action.character.model.get_node("NavigationAgent3D")
	var other := Chuuni.get_other_character(action.character)
	
	if cancelled_func:
		action.cancelled.connect(cancelled_func)
	action.cancelled.connect(func():
		action.character.model.look_at_target = Vector3.ZERO
		print("fucking cancelled"))
	
	other.state_machine.queue_action(action.response_callable.call(other))
	var started := Time.get_ticks_msec()
	
	while true:
		if GlobalActions.is_queued_or_doing(other, "cook") or \
		GlobalActions.is_queued_or_doing(other, "eat") or \
		other.state_machine.current_action.zone != action.zone or \
		action.character.state_machine.is_being_accosted() or \
		Time.get_ticks_msec() - started > 10 * 1000:
			print(action.character.npc_name)
			print(action.zone.name, other.state_machine.current_action.zone)
			action.cancel()
			other.state_machine.remove_from_queue("respond")
			action.subaction_finished.emit()
			return
		
		var position := other.model.global_position
		position.x -= 1; position.z -= 1
		nav_agent.target_position = position
		if action.action_name in other.state_machine.current_action.action_name and \
		other.has_meta("waiting"): # checking the state would soft-lock sometimes and idk why T_T
			print("AAAHHHH")
			if nav_agent.target_position == Vector3.ZERO: break
			#if action.character.model.global_position.distance_to(position) <= 0.01: break
			else: await nav_agent.navigation_finished; break
		await get_tree().create_timer(0.05, false).timeout
	
	#nav_agent.target_desired_distance = distance
	action.subaction_finished.emit()

func _yell(action: Action) -> void:
	action.character.state_machine.state = StateMachine.State.TALKING
	print(action.character.npc_name + " is YELLING")
	await get_tree().create_timer(5, false).timeout
	action.character.state_machine.state = StateMachine.State.IDLE
	
	var other := Chuuni.get_other_character(action.character)
	var context = "yell" if not yell_reason else "yell_" + yell_reason
	action.character.create_memory(other, ["satisfaction"], context)
	var penalty := 5 if Chuuni.is_enemies() else 10
	Chuuni.relationship -= penalty
	Chuuni.tally_winner(action.character)
	
	action.subaction_finished.emit()

func _get_yelled_at(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	while other.state_machine.state != StateMachine.State.TALKING:
		await other.state_machine.state_changed
	await other.state_machine.state_changed
	
	action.character.personality.fear += 1
	var context = "yell" if not yell_reason else "yell_" + yell_reason
	action.character.create_memory(other, ["fear", "betrayal"], context)
	
	action.subaction_finished.emit()

func _decide_topic_and_intention(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	topic = ["anger", "melancholy", "whimsy"][randi_range(0, 2)]
	intention = action.character.get_sentiment_toward(other)
	action.character.model.look_at_target = other.model.global_position
	other.model.look_at_target = action.character.model.global_position
	
	var feelings := action.character.get_feelings_toward(other) # satisfaction doesn't factor into intention
	if "satisfaction" in feelings: intention -= feelings.satisfaction
	
	print("topic: " + topic)
	print("intention: ", intention)
	action.subaction_finished.emit()

func _prepare_responder(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	action.character.state_machine.state = StateMachine.State.WAITING
	action.character.set_meta("waiting", true)
	action.character.model.look_at_target = other.model.global_position
	print("????")
	await other.state_machine.current_action.subaction_finished
	action.character.remove_meta("waiting")
	action.subaction_finished.emit()

func _talk_placeholder(action: Action) -> void:
	action.character.is_socialising = true
	var other := Chuuni.get_other_character(action.character)
	action.character.state_machine.state = StateMachine.State.TALKING
	action.character.model.set_anim("talk")
	await get_tree().create_timer(randi_range(4, 6), false).timeout
	action.subaction_finished.emit()

# will mark this subaction completed in partner's _decide_winner function
func _listen(action: Action) -> void:
	action.character.set_meta("listening", true)
	action.subaction_finished.connect(action.character.remove_meta.bind("listening"))

func _decide_winner(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	var winner = action.character if action.character.personality[topic] \
		>= other.personality[topic] else other
	var disagreement: int = Chuuni.get_difference(action.character.personality[topic], other.personality[topic])
	var disagreement_threshold := 8
	var other_sentiment := other.get_sentiment_toward(action.character)
	var relationship_effect := 0
	action.character.model.set_anim("stand")
	
	if intention >= -2:
		# they agree and there is no tension
		if disagreement < disagreement_threshold:
			print("they agree <3")
			winner = "both"
			action.character.create_memory(other, ["satisfaction", "joy"], "debate")
			other.create_memory(action.character, ["satisfaction", "joy"], "debate")
			relationship_effect += 2
			other.model.set_anim("talk")
		# melancholic characters hate debate and don't respond nicely
		elif disagreement >= disagreement_threshold and other.personality.melancholy >= 10:
			print(other.npc_name + " hates debate and doesn't play along")
			# if passive, let instigator win
			if winner == other and other.personality.activeness < 0: winner = action.character
			other.create_memory(action.character, ["boredom", "resentment"], "debate")
			relationship_effect -= 3
			var associations: Array[String] = ["resentment"]
			if winner != action.character: associations.append("betrayal"); relationship_effect -= 1
			action.character.create_memory(other, associations, "debate")
			other.personality.happiness -= 2
			other.model.set_anim("stand", "unimpressed")
			await get_tree().create_timer(1, false).timeout
			other.model.set_anim("talk", "unimpressed")
		# passive character lets instigator win no matter what if they disagree
		elif other.personality.activeness <= 0 and Chuuni.relationship >= 0 and \
		disagreement >= disagreement_threshold:
			print(other.npc_name + " let " + action.character.npc_name + " win out of passivity and respect")
			winner = action.character
			action.character.create_memory(other, ["satisfaction"], "debate")
			other.create_memory(action.character, ["fear", "respect"], "debate")
			other.personality.happiness -= 2
			action.character.personality.happiness += 1
			await get_tree().create_timer(1, false).timeout
			other.model.set_anim("talk")
		elif disagreement >= disagreement_threshold and other_sentiment >= 0 and \
		other.personality.activeness >= 10:
			print("they disagree but had a passionate, respectful debate")
			winner = "both"
			action.character.create_memory(other, ["joy", "respect"], "debate")
			other.create_memory(action.character, ["joy", "respect"], "debate")
			relationship_effect += 2
			other.model.set_anim("talk")
		elif disagreement >= disagreement_threshold and other_sentiment < 0:
			print(other.npc_name + " feels attacked")
			var associations = ["satisfaction"] if winner == action.character else ["resentment"]
			action.character.create_memory(other, associations, "debate")
			other.create_memory(action.character, ["fear", "resentment"], "debate")
			relationship_effect -= 2
			other.personality.happiness -= 2
			other.model.set_anim("talk", "angry")
		else:
			print("they disagree but it's not even fun -_-")
			relationship_effect -= 1
			action.character.create_memory(other, ["boredom"], "debate")
			other.create_memory(action.character, ["boredom"], "debate")
			other.model.set_anim("talk", "angry")
	else:
		print("bad intentions, " + other.npc_name + " feels attacked and betrayed")
		var associations = ["satisfaction"] if winner == action.character else ["resentment"]
		action.character.create_memory(other, associations, "debate_evil")
		other.create_memory(action.character, ["fear", "betrayal"], "debate_evil")
		other.personality.happiness -= 5
		relationship_effect -= 4
		other.model.set_anim("talk", "angry")
	
	await get_tree().create_timer(randi_range(3, 6)).timeout
	other.model.set_anim("stand", other.model.emotional_state)
	if other.model.emotional_state != "":
		get_tree().create_timer(3, false).timeout.connect(other.model.set_anim.bind("stand"))
	
	var winner_name: String = winner.npc_name if winner is Character else winner
	print("winner: " + winner_name)
	print("disagreement: ", disagreement)
	await get_tree().create_timer(randi_range(1, 3), false).timeout
	action.subaction_finished.emit()
	other.state_machine.current_action.subaction_finished.emit()
	
	if not winner is Character and winner == "both":
		Chuuni.tally_winner(action.character)
		Chuuni.tally_winner(other)
	else: Chuuni.tally_winner(winner)
	
	Chuuni.relationship += relationship_effect
	if relationship_effect > 0:
		for chr: Character in Chuuni.characters.values(): chr.personality.happiness += relationship_effect

func _end_debate(action: Action) -> void:
	action.character.model.look_at_target = Vector3.ZERO
	action.character.is_socialising = false
	#action.character.personality.social += 20
	action.subaction_finished.emit()
