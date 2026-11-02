extends Control

const room_scene_path := "res://scene/room/room.tscn"
const name_defaults := {"ia": "olive", "ui": "ivy"}
var ia_predominant: String
var ia_priority: String
var ui_priority: String

func _ready() -> void:
	_show_name_entry(Chuuni.characters.ia)
	%NameField.text_changed.connect(func(_text):
		%NameEntry/Done.disabled = %NameField.text.length() == 0)
	%NameField.editing_toggled.connect(func(toggle: bool):
		if toggle: %NameField.text = "")
	
	%Happiness.pressed.connect(_press_priority_button.bind(%Happiness))
	%Energy.pressed.connect(_press_priority_button.bind(%Energy))
	%TraitBack.pressed.connect(_cycle_trait_select.bind(-1))
	%TraitForward.pressed.connect(_cycle_trait_select.bind(1))

func _reset_tabs() -> void:
	for tab in %Tabs.get_children(): tab.hide()

func _show_name_entry(character: Character) -> void:
	_reset_tabs()
	%NameField.text = name_defaults[Chuuni.characters.find_key(character)]
	%NameEntry.show()
	%NameEntry/Done.pressed.connect(_submit_name.bind(character))
	%NameField.text_submitted.connect(_submit_name.bind(character))

func _submit_name(character: Character) -> void:
	if %NameField.text.length() == 0: return
	if character == Chuuni.characters.ui and \
	%NameField.text == Chuuni.characters.ia.npc_name: return
	
	character.npc_name = %NameField.text
	%NameEntry/Done.pressed.disconnect(_submit_name)
	%NameField.text_submitted.disconnect(_submit_name)
	_show_trait_select(character)

func _show_trait_select(character: Character) -> void:
	_reset_tabs()
	if character == Chuuni.characters.ui: %Priority.hide()
	_cycle_trait_select()
	%TraitSelect.show()
	%TraitSelect/Done.pressed.connect(_submit_traits.bind(character), CONNECT_ONE_SHOT)
	
func _press_priority_button(button: Button) -> void:
	for _button: Button in button.get_parent().get_children():
		_button.disabled = not _button.disabled

func _cycle_trait_select(direction: int = 0) -> void:
	var traits := Personality.personality_traits.duplicate()
	if ia_predominant: traits.erase(ia_predominant)
	if direction == 0: %Trait.text = traits[0]; return
	var current_index := traits.find(%Trait.text)
	if current_index + direction == -1:
		%Trait.text = traits[traits.size() - 1]
	elif current_index + direction > traits.size() - 1:
		%Trait.text = traits[0]
	else:
		%Trait.text = traits[current_index + direction]

func _submit_traits(character: Character) -> void:
	character.personality[%Trait.text] = 20
	
	var priority: String
	if character == Chuuni.characters.ia:
		ia_predominant = %Trait.text
		for button: Button in %PriorityButtons.get_children():
			if button.disabled: ia_priority = button.text.to_lower()
			else: ui_priority = button.text.to_lower()
		priority = ia_priority
	else: priority = ui_priority
	
	character.personality[priority + "_constraint"] = Personality.stat_constraints[1]
	#character.personality[priority] = Personality.stat_constraints[1]
	character.personality.randomise()
	
	if character == Chuuni.characters.ia: _show_name_entry(Chuuni.characters.ui)
	else: _start_game()

func _start_game() -> void:
	hide()
	get_tree().change_scene_to_file(room_scene_path)
