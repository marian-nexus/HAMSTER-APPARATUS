extends MarginContainer
var debug_enabled := false

func _ready() -> void:
	if not debug_enabled: queue_free()
	hide()
	MainUI.debug_raycast.connect(_on_debug_raycast)
	%DebugHUDText.visible = debug_enabled
	if debug_enabled: $Timer.timeout.connect(_update_hud)

func _hide() -> void:
	_disconnect_connections()
	hide()

func _disconnect_connections() -> void:
	for connection in $Timer.timeout.get_connections():
		if connection.callable == _update_hud: continue
		$Timer.timeout.disconnect(connection.callable)

func _on_debug_raycast(collider: Node3D = null):
	if not collider or collider.name == "Floor": _hide(); return
	_disconnect_connections()
	if "character" in collider:
		_update_character_info(collider.character)
		show()
		$Timer.timeout.connect(_update_character_info.bind(collider.character))
	elif collider is RadioObject:
		_update_object_info(collider)
		show()
		#$Timer.timeout.connect(_update_object_info.bind(collider))

func _update_character_info(character: Character) -> void:
	var info := "--- personality ---"
	for prop in character.personality.get_property_list():
		if prop.usage != 4096: continue
		info += "\n" + prop.name + ": " + str(character.personality[prop.name])
	
	info += "\n\n--- state machine ---"
	var state_machine: StateMachine = character.state_machine
	info += "\ncurrent state: " + StateMachine.State.keys()[character.state_machine.state]
	info += "\ncurrent action: " + state_machine.current_action.action_name
	info += "\naction queue: ["
	for action: Action in state_machine.action_queue:
		info += action.action_name + ", "
	if not state_machine.action_queue.is_empty(): info = info.substr(0, info.length() - 2)
	info += "]"
	info += "\naction history: ["
	for action: String in state_machine.action_history:
		info += action + ", "
	if not state_machine.action_history.is_empty(): info = info.substr(0, info.length() -2)
	info += "]"
	
	info += "\n\n--- metadata ---"
	for meta: StringName in character.get_meta_list():
		info += "\n" + str(meta) + ": " + str(character.get_meta(meta))
	
	%DebugItemName.text = character.npc_name
	%DebugItemInfo.text = info

func _update_object_info(object: RadioObject) -> void:
	var info = "--- radio waves ---"
	var effects := object.get_stat_effects()
	for stat: String in effects.keys():
		info += "\n" + stat + ": " + str(effects[stat])
	
	%DebugItemName.text = object.name
	%DebugItemInfo.text = info

func _update_hud() -> void:
	var hud_text := "relationship: " + str(Chuuni.relationship) + " (" + Chuuni.relationship_label + ")"
	
	var wins := "0/0"
	var powerful := "none"
	if not Chuuni.win_count.is_empty():
		wins = str(Chuuni.win_count.values()[0]) + "/" + str(Chuuni.win_count.values()[1])
	if Chuuni.the_powerful: powerful = Chuuni.the_powerful.npc_name
	
	hud_text += " | wins: " + wins + " | powerful: " + powerful + " | diff: " + str(Chuuni.power_difference)
	
	%DebugHUDText.text = hud_text
