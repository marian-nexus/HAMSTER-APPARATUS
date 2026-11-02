extends Node3D

@onready var box := $Box
@onready var lr = get_tree().current_scene.get_node("Scripts/LivingRoomActions")
@onready var talking_script = get_tree().current_scene.get_node("Scripts/Talking")
@onready var global: Dictionary[String, Callable] = {
	"grab": lr._grab_tv_item.bind(box),
	"put_away": lr._put_away_tv_item.bind(box)
}
@onready var talking: Dictionary[String, Callable] = {
	"chase": talking_script._chase_down,
	"prepare": talking_script._prepare_responder,
	"yell": talking_script.yell_at
}

var initiating_chr: Character
var game_variables: Dictionary[Character, Dictionary]
const DEFAULT_ATMOSPHERE := 2
var atmosphere := DEFAULT_ATMOSPHERE
var round_number := 0
var winners: Array[Character] = []
signal round_ended

func _ready() -> void:
	# I'M SO SICK OF THEM TRYING TO PLAY CARDS FIRST THING EVERY FUCKING TIME T_T
	get_tree().create_timer(20, false).timeout.connect(_register)
	
	$AtmosphereTimer.timeout.connect(_react_to_atmosphere)

func _register() -> void:
	GlobalActions.register_action(play_card_game, [self], ["social", "happiness"],
		_card_game_req, "play card game")

func _react_to_atmosphere() -> void:
	for chr: Character in Chuuni.characters.values():
		chr.personality.happiness += atmosphere

func play_card_game(character: Character) -> Action:
	var subactions: Array[Callable] = [global.grab,
		talking.chase.bind(_on_cancelled.bind(character)), _set_game_variables,
		GlobalActions._grab_item.bind("cards"), _play, _end_game, global.put_away]
	var action := Chuuni.create_action(character, subactions, "play card game")
	action.response_callable = card_game_respond
	return action

func put_away_cards(character: Character) -> Action:
	var subactions: Array[Callable] = [global.put_away]
	return Chuuni.create_action(character, subactions, "put away cards")

# triggered if "play cards" action is cancelled during the chase down stage
func _on_cancelled(character: Character) -> void:
	character.state_machine.queue_action(put_away_cards(character), true)

func card_game_respond(character: Character) -> Action:
	var subactions: Array[Callable] = [talking.prepare, GlobalActions._grab_item.bind("cards"), _play_respond]
	return Chuuni.create_action(character, subactions, "play card game (respond)")

func _card_game_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	
	req.possible = not GlobalActions.is_leaving_zone(other) and \
		not GlobalActions.is_queued_or_doing(other, "play card game")
	
	if req.possible:
		if Chuuni.is_enemies():
			if character.get_feelings_toward(other).fear > 0: req.possible = false
			if character.personality.melancholy >= 10: req.possible = false
			if character.personality.activeness < 8: req.possible = false
	if not req.possible: return req
	
	var other_is_busy := false
	if other.has_meta("boredom_threshold"):
		other_is_busy = Chuuni.get_difference(other.get_meta("boredom_threshold"), \
			other.get_meta("boredom", 0)) <= 5
	other_is_busy = GlobalActions.is_queued_or_doing(other, "eat")
	if other_is_busy: req.possible = false; return req
	
	req.personality = character.personality.anger <= 10 and character.personality.melancholy <= 8
	req.mood = character.personality.energy >= character.personality.energy_constraint / 2 \
		and character.personality.melancholy <= 8
	req.relationship = not Chuuni.is_enemies() and Chuuni.the_powerful != other
	if req.relationship: req.relationship = character.get_feelings_toward(other).fear < 5
	
	return req

func _set_game_variables(action: Action) -> void:
	$AtmosphereTimer.start()
	initiating_chr = action.character
	atmosphere = DEFAULT_ATMOSPHERE
	game_variables = {}
	round_number = 0
	winners = []
	for chr: Character in Chuuni.characters.values():
		chr.is_socialising = true
		chr.state_machine.state = StateMachine.State.BUSY
		var variables := {}
		variables.sore_loser = chr.personality.anger >= 10
		variables.natural_talent = chr.personality.melancholy >= 10 and randi() % 2 == 1
		if Chuuni.get_other_character(chr) in game_variables.keys():
			if game_variables[Chuuni.get_other_character(chr)].natural_talent:
				variables.natural_talent = false
		
		game_variables[chr] = variables
	
	print(game_variables)
	box.hide()
	box.reparent(self, false)
	var other := Chuuni.get_other_character(action.character)
	action.character.model.look_at_target = other.model.global_position
	action.subaction_finished.emit()

func _decide_winner() -> void:
	var winner: Character = Chuuni.characters.values()[randi() % 2]
	for chr: Character in Chuuni.characters.values():
		if game_variables[chr].natural_talent and randi() % 2 == 1: winner = chr
	winners.append(winner)
	Chuuni.tally_winner(winner)
	_react_to_winner(winner)

func _play(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	action.character.model.sit()
	action.character.model.look_at_target = other.model.global_position
	round_number += 1
	print("playing round ", round_number)
	await get_tree().create_timer(5, false).timeout
	_decide_winner()
	
	var will_continue := true
	if round_number >= 5: will_continue = false
	#elif atmosphere <= 0 and randi() % 5 == 1: will_continue = false
	round_ended.emit(will_continue)
	
	if will_continue: _play(action)
	else: action.subaction_finished.emit()

func _play_respond(action: Action) -> void:
	action.character.model.sit()
	var response_func := func(will_continue: bool):
		if will_continue: _play_respond(action)
		#else: action.subaction_finished.emit() # put this in _end_game instead
	
	round_ended.connect(response_func, CONNECT_ONE_SHOT)

func _react_to_winner(winner: Character) -> void:
	var loser := Chuuni.get_other_character(winner)
	loser.model.get_node("Hand").get_child(0).get_taken()
	var relationship_gain := 1
	if game_variables[loser].sore_loser:
		loser.model.show_emotion("angry")
		atmosphere -= 1
		relationship_gain = 0
		if game_variables[loser].natural_talent:
			loser.create_memory(winner, ["betrayal", "resentment"], "card_game")
		else:
			loser.create_memory(winner, ["resentment"], "card_game")
			if game_variables[winner].natural_talent: relationship_gain = -1
	
	if game_variables[winner].natural_talent:
		winner.model.show_emotion("unimpressed")
	
	print("winner: ", winner.npc_name, ", atmosphere: ", atmosphere)
	Chuuni.relationship += relationship_gain

func _end_game(action: Action) -> void:
	var other := Chuuni.get_other_character(action.character)
	action.character.model.look_at_target = Vector3.ZERO
	other.model.look_at_target = Vector3.ZERO
	other.model.stand()
	action.character.model.stand()
	action.character.model.get_node("Hand").get_child(0).queue_free()
	other.model.get_node("Hand").get_child(0).queue_free()
	box.reparent.call_deferred(action.character.model.get_node("Hand"), false)
	box.show()
	
	$AtmosphereTimer.stop()
	var sentiment: Array
	if atmosphere > 0: sentiment = ["joy"]
	elif atmosphere == 0: sentiment = ["boredom"]
	else: sentiment = ["resentment"]
	
	for chr: Character in Chuuni.characters.values():
		chr.create_memory(self, sentiment, "card_game")
		chr.create_memory(Chuuni.get_other_character(chr), sentiment, "card_game")
		chr.is_socialising = false
	
	var most_frequent_loser: Character
	var loss_count := {}
	for chr: Character in winners:
		var _other := Chuuni.get_other_character(chr)
		if not _other in loss_count.keys(): loss_count[_other] = 1
		else: loss_count[_other] += 1
	
	if loss_count.keys().size() == 1:
		most_frequent_loser = loss_count.keys()[0]
	else:
		most_frequent_loser = loss_count.keys()[0]
		if loss_count[Chuuni.get_other_character(most_frequent_loser)] > \
		loss_count[most_frequent_loser]: most_frequent_loser = loss_count.keys()[1]
	
	var loss_diff: int = Chuuni.get_difference(loss_count[most_frequent_loser], round_number)
	if loss_diff <= round_number / 3:
		var _other := Chuuni.get_other_character(most_frequent_loser)
		var can_yell: bool = game_variables[most_frequent_loser].sore_loser
		if Chuuni.the_powerful == _other: can_yell = false
		elif most_frequent_loser.personality.activeness < 0: can_yell = false
		if can_yell:
			print(most_frequent_loser.npc_name + " is going to yell >:|")
			most_frequent_loser.state_machine.queue_action(
				talking.yell.call(most_frequent_loser, "cards"), true
			)
	
	await get_tree().process_frame
	other.state_machine.current_action.subaction_finished.emit()
	action.subaction_finished.emit()
