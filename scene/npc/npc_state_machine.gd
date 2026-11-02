class_name StateMachine extends Resource
enum State {IDLE, WALKING, TALKING, WAITING, BUSY, SLEEPING, PHOTOSYNTHESIS}
const IDLE_ACTIONS := ["wander"]
var current_action: Action
var action_queue: Array[Action] = []
var state := State.IDLE:
	set(value):
		state = value
		state_changed.emit()
		character.is_socialising = state == State.TALKING
var character: Character
var using_object: String:
	set(value):
		using_object = value
		using_object_changed.emit(value)
		print(character.npc_name + " is using " + using_object)

var action_history := []
const HISTORY_LENGTH := 5

signal action_finished
signal state_changed
signal using_object_changed
signal action_started

func _init() -> void:
	action_finished.connect(_start_next_action)
	_decide_next_action.call_deferred()

func queue_action(action: Action, priority: bool = false) -> void:
	if action.action_name not in IDLE_ACTIONS:
		var new_queue: Array[Action] = []
		for _action: Action in action_queue:
			if _action.action_name not in IDLE_ACTIONS: new_queue.append(_action)
			action_queue = new_queue
	
	if priority: action_queue.insert(0, action)
	else: action_queue.append(action)
	_start_next_action()

func remove_from_queue(action_name: String) -> void:
	if action_queue.is_empty(): return
	var to_remove := []
	for action: Action in action_queue:
		if action_name in action.action_name:
			to_remove.append(action)
	for action: Action in to_remove: action_queue.erase(action)

func _start_next_action() -> void:
	character.is_socialising = false
	if current_action:
		if not current_action.action_name in IDLE_ACTIONS and current_action.is_running: return
		if current_action.action_name in IDLE_ACTIONS and current_action.is_running: _stop_current_action()
	state = State.IDLE
	if action_queue.is_empty(): _decide_next_action(); return
	current_action = action_queue.pop_at(0)
	if not current_action.action_name in IDLE_ACTIONS: _append_history(current_action)
	current_action.start()
	action_started.emit(current_action)

func _decide_next_action() -> void:
	var available_actions := get_possible_actions()
	if available_actions.is_empty(): _wander()
	else:
		var random_index := 2 # randomly pick an action from the top 3
		if available_actions.size() - 1 < random_index: random_index = available_actions.size() - 1
		for i in range(random_index - 1, -1, -1): # but only if the top 3 have similar enough scores
			if Chuuni.get_difference(
				GlobalActions.get_action_score(available_actions[i - 1], character),
				GlobalActions.get_action_score(available_actions[i], character)
			) >= 3: random_index -= 1
		
		if available_actions.size() > 1:
			var to_remove := []
			for action in available_actions:
				if GlobalActions.is_queued_or_doing(Chuuni.get_other_character(character), action.name):
					to_remove.append(action)
			
			if available_actions.size() - to_remove.size() >= 1:
				for action in to_remove:
					if not "social" in action.needs:
						available_actions.erase(action)
						random_index -= 1
		
		var chosen_action := available_actions[randi_range(0, random_index)]
		print("chosen action: ", chosen_action.name, " (selected from the top ", random_index + 1, ")")
		
		queue_action(chosen_action.create.call(character))

func get_possible_actions() -> Array[Dictionary]:
	var available_actions := GlobalActions.get_available_actions(character)
	if available_actions.is_empty(): return []
	
	available_actions.sort_custom(GlobalActions.sort_actions_by_score.bind(character))
	available_actions = GlobalActions.remove_irrelevant_actions(available_actions, character)
	var action_names := []
	for action: Dictionary in available_actions:
		var string: String = action.name
		var score := GlobalActions.get_action_score(action, character)
		string += " (" + str(score) + ")"
		action_names.append(string)
	if not action_names.is_empty(): print(character.npc_name + "'s available actions: ", action_names)
	return available_actions

func _wander() -> void:
	var is_reclusive := false
	var other := Chuuni.get_other_character(character)
	if character.personality.fear >= 5 and other.current_zone.name == "MainArea": is_reclusive = true
	elif Chuuni.is_enemies() and character.personality.activeness <= 5: is_reclusive = true
	elif character.personality.happiness <= 15: is_reclusive = true
	elif character.personality.melancholy >= 10 and randi() % 3 == 1: is_reclusive = true
	
	if is_reclusive: queue_action(GlobalActions.lay_on_ground(character))
	else: queue_action(GlobalActions.wander(character))

func is_being_accosted() -> bool: # check if a "respond" action is next in the queue
	if action_queue.is_empty(): return false
	if "respond" in action_queue[0].action_name: return true
	return false

func _stop_current_action() -> void:
	current_action.cancel()
	var nav_agent: NavigationAgent3D = character.model.get_node("NavigationAgent3D")
	nav_agent.target_position = character.model.position

func _append_history(action: Action) -> void:
	if "(respond)" in action.action_name:
		action.action_name = action.action_name.substr(0, action.action_name.length() - 10)
	
	if action_history.size() >= HISTORY_LENGTH: action_history.pop_front()
	action_history.append(action.action_name)
