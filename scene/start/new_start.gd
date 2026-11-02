extends Node3D

var current_menu: Control
var current_character: Character
var model: CharacterModel
var is_fading := false
var character_count := 0
const ROOM_SCENE_PATH := "res://scene/room/room.tscn"
const DEFAULT_NAMES := ["olive", "ivy"]
const NAME_INSTRUCTIONS := [
	"give this hamster a name",
	"give this OTHER hamster a name"
]

func _ready() -> void:
	$CanvasLayer/Black.modulate.a = 1
	$Music/Soul.pitch_scale = 0.1
	$Music/Soul.volume_db = -50
	var music_tween := get_tree().create_tween().set_ease(Tween.EASE_OUT).set_parallel()
	music_tween.set_trans(Tween.TRANS_QUAD)
	music_tween.tween_property($Music/Soul, "volume_db", -16, 0.3).set_delay(1)
	music_tween.tween_property($Music/Soul, "pitch_scale", 0.8, 3)
	await get_tree().create_timer(0.2).timeout
	get_tree().create_tween().tween_property($CanvasLayer/Black, "modulate:a", 0, 2).set_delay(1)
	
	%NameEntry.text_changed.connect(_set_enter_hint)
	%NameEntry.text_changed.connect(func(_text): MainUI.play_sound("mugshot_release"))
	for button: Button in %Traits.get_children(): button.pressed.connect(_select_trait.bind(button))
	for button: Button in %Stats.get_children(): button.pressed.connect(_select_stat.bind(button))
	%StartButton.pressed.connect(_start_game)
	
	for button: Button in find_children("*", "Button"):
		button.mouse_entered.connect(MainUI.play_sound.bind("hover"))
	
	_set_up_title_screen()

func _set_up_title_screen() -> void:
	%CharacterCreation.hide()
	%Title.show()
	
	var title_tween := get_tree().create_tween().set_loops().set_trans(Tween.TRANS_BACK)
	title_tween.tween_property(%TitlePlaceholder, "offset_transform_scale:x", 1.5, 4)
	title_tween.tween_property(%TitlePlaceholder, "offset_transform_scale:x", 1, 2)
	title_tween.tween_property(%TitlePlaceholder, "offset_transform_scale", Vector2(1.5, 0.8), 2)
	title_tween.tween_property(%TitlePlaceholder, "offset_transform_scale", Vector2(2, 0.1), 3)
	title_tween.tween_property(%TitlePlaceholder, "offset_transform_scale", Vector2(1.3, 1), 1)
	
	for _model in $TitleScreen.find_children("*", "CharacterModel"):
		_title_screen_tween(_model)

func _title_screen_tween(_model: CharacterModel) -> void:
	if not _model.has_meta("o_O"):
		_model.hide()
		_model.set_meta("o_O", "E")
		await get_tree().create_timer(randf_range(8, 16)).timeout
		_model.show()
	if not $TitleScreen.visible: return
	_model.position = Vector3(randf_range(-3, 3), 6, randf_range(0, 4))
	_model.rotation = Vector3(0, 0, 0)
	for sprite in _model.find_children("*", "AnimatedSprite3D"): sprite.modulate.a = 0
	var tween := get_tree().create_tween().set_parallel().set_trans(Tween.TRANS_QUAD)
	var duration := randi_range(9, 12)
	tween.tween_property(_model, "position",
		Vector3(randf_range(-5, 5), -6, randf_range(-4, 6)), duration)
	tween.tween_property(_model, "rotation",
		Vector3(randf_range(-20, 20), randf_range(-35, 20), randf_range(-20, 20)), duration)
	
	for sprite in _model.find_children("*", "AnimatedSprite3D"):
		tween.tween_property(sprite, "modulate:a", 1, 0.5)
		tween.tween_property(sprite, "modulate:a", 0, 0.5).set_delay(duration - 0.5)
	
	tween.finished.connect(_title_screen_tween.bind(_model))

func _random_pitch() -> void:
	if is_fading: return
	var default: float = $Music/Soul.pitch_scale
	var new := randf_range(default - 0.1, default + 0.05)
	var tween := get_tree().create_tween()
	tween.tween_property($Music/Soul, "pitch_scale", new, randf_range(1, 3))
	tween.tween_property($Music/Soul, "pitch_scale", default, randf_range(0.4, 1))
	get_tree().create_timer(randi_range(4, 10)).timeout.connect(_random_pitch)

func _start_game() -> void:
	var path := "environment:volumetric_fog_length"
	get_tree().create_tween().set_trans(Tween.TRANS_QUAD).tween_property(
		$WorldEnvironment, path, 0, 2.5)
	
	
	var tween := get_tree().create_tween().set_parallel().set_trans(Tween.TRANS_BACK)
	tween.tween_property($TitleScreen, "global_position:z", -20, 2)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property($TitleScreen/Donut, "rotation_degrees:y", 360, 2)
	tween.tween_property(%Title, "modulate:a", 0, 1)
	
	
	get_tree().create_timer(1).timeout.connect(func():
		%Title.hide()
		$TitleScreen.hide())
	
	_spawn_character()

func _spawn_character() -> void:
	#if character_count == 1:
		#await get_tree().create_timer(0.3).timeout
		#for child in %CharacterCreation.get_children():
			#child.visible = child == %OminousText
		#%OminousText.get_child(0).show()
		#%MenuFade.play("fade_in_character")
		#var tween := get_tree().create_tween()
		#tween.tween_property(%OminousText, "visible_ratio", 1, 2)
		#tween.parallel().tween_property(%Black, "modulate:a", 0.4, 1)
		#tween.tween_property(%OminousText, "modulate:a", 0, 0.4).set_delay(1.5)
		#tween.parallel().tween_property(%Black, "modulate:a", 0, 0.4).set_delay(1.5)
		#await tween.finished
		#%Instruction.show()
	
	if character_count == 0:
		%CharacterCreation.hide()
		var tween := get_tree().create_tween()
		tween.tween_property($Music/Soul, "pitch_scale", 0.2, 0.3)
		tween.tween_property($Music/Soul, "pitch_scale", 0.8, 2.5)
		await get_tree().create_timer(1.5).timeout
		%CharacterCreation.show()
		get_tree().create_timer(3).timeout.connect(_random_pitch)
	
	character_count += 1
	current_character = Chuuni.characters.values()[character_count - 1]
	var chr_model := preload("res://scene/npc/npc.tscn")
	model = chr_model.instantiate()
	model.hollow = true
	add_child(model)
	model.character_appearance = current_character
	model.global_position = $Positions/Spawn.global_position
	_show_name_entry()
	
	model.get_node("SpriteFront").modulate.a = 0
	var _tween := get_tree().create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(model.get_node("SpriteFront"), "modulate:a", 1, 0.6)
	_tween.parallel().tween_property(model, "rotation:y", 5, 0.6)

func _set_menu(menu: Control) -> void:
	var fading = current_menu != null
	if menu == %NameContainer: fading = false
	if fading:
		%MenuFade.play("fade_out_character")
		await get_tree().create_timer(0.4).timeout
	else: %CharacterCreation.modulate.a = 0
	
	%MenuFade.play("fade_in_character")
	for container: Control in %CharacterCreation.find_children("*", "MarginContainer", false):
		container.visible = container == menu

func _set_instruction(instruction_text: String) -> void:
	var tween := get_tree().create_tween().set_ease(Tween.EASE_OUT)
	if has_meta("inst_tween") and get_meta("inst_tween").is_running(): get_meta("inst_tween").kill()
	set_meta("inst_tween", tween)
	var duration := 0.8
	%Instruction.text = instruction_text
	%Instruction.visible_ratio = 0
	tween.tween_property(%Instruction, "visible_ratio", 1, duration * 2)

func _show_name_entry() -> void:
	%NameEntry.placeholder_text = DEFAULT_NAMES[character_count - 1]
	remove_meta("O_O")
	_set_enter_hint("")
	%NameEntry.text = ""
	_set_menu(%NameContainer)
	_set_instruction(NAME_INSTRUCTIONS[character_count - 1])
	
	if %NameEntry.has_connections("text_submitted"):
		for connection in %NameEntry.text_submitted.get_connections():
			%NameEntry.text_submitted.disconnect(connection.callable)
	
	%NameEntry.text_submitted.connect(_submit_name)

func _set_enter_hint(new_text: String) -> void:
	if not has_meta("O_O"):
		set_meta("O_O", "^_^")
		%PressEnter.modulate.a = 0
		return
	
	var opacity := 1 if new_text else 0
	if %PressEnter.modulate.a == opacity: return
	var tween := get_tree().create_tween()
	tween.tween_property(%PressEnter, "modulate:a", opacity, 0.2)

func _submit_name(text: String) -> void:
	var accepted := Chuuni.get_other_character(current_character).npc_name != text
	if not text: accepted = false
	
	if accepted:
		%NameEntry.release_focus()
		current_character.npc_name = text
		_show_trait_select()

func _insane_tween() -> Tween:
	return get_tree().create_tween().set_parallel().set_trans(Tween.TRANS_QUAD)

func _show_trait_select() -> void:
	for button: Button in %Traits.get_children(): button.disabled = false
	%Traits.get_child(0).offset_transform_position_ratio.x = 0
	%Traits.get_child(1).offset_transform_position_ratio.x = 0.15
	
	_set_menu(%TraitContainer)
	_set_instruction("what is her predominant trait?")
	
	# incredible!
	var tween_time := 0.6
	var marker := $Positions/Trait
	model.jump()
	await get_tree().create_timer(0.15).timeout
	var tween := _insane_tween()
	tween.tween_property(model, "global_position", marker.global_position, tween_time)
	tween.tween_property(model, "rotation", Vector3(0, 0, 20), tween_time)

func _select_trait(button: Button) -> void:
	MainUI.play_sound("press")
	var trait_name := button.text
	for _button: Button in %Traits.get_children(): _button.disabled = true
	get_tree().create_timer(1).timeout.connect(button.queue_free)
	
	current_character.personality[trait_name] = 20
	current_character.personality.randomise()
	if character_count == 1: _show_stat_select()
	else: _send_off()

func _show_stat_select() -> void:
	_set_menu(%StatContainer)
	_set_instruction("which is more important to her?")
	
	var tween_time := 0.6
	var marker := $Positions/Stat
	model.jump()
	await get_tree().create_timer(0.15).timeout
	var tween := _insane_tween()
	tween.tween_property(model, "global_position", marker.global_position, tween_time)
	tween.tween_property(model, "rotation", Vector3(0, 20, 0), tween_time)

func _select_stat(button: Button) -> void:
	MainUI.play_sound("press")
	var stat_name := button.text
	var other_stat := "happiness" if stat_name != "happiness" else "energy"
	var other := Chuuni.get_other_character(current_character)
	current_character.personality[stat_name + "_constraint"] = Personality.stat_constraints[1]
	other.personality[other_stat + "_constraint"] = Personality.stat_constraints[1]
	_send_off()

func _send_off() -> void:
	%MenuFade.play("fade_out_character")
	
	var tween_time := 0.8
	var marker := $Positions/TheVoid
	model.jump()
	await get_tree().create_timer(0.15).timeout
	var tween := _insane_tween()
	tween.tween_property(model, "global_position", marker.global_position, tween_time)
	tween.tween_property(model, "rotation", Vector3(50, 0, 0), tween_time)
	await get_tree().create_timer(tween_time + 0.1).timeout
	
	for i in range(1, 6):
		get_tree().create_tween().tween_property(model, "rotation", Vector3(0, 10 * i, 0), tween_time / 2)
		await get_tree().create_timer(tween_time / 2).timeout
	
	model.queue_free()
	if character_count == 1: get_tree().create_timer(1).timeout.connect(_spawn_character)
	else: _slow_fade_out()

func _slow_fade_out() -> void:
	is_fading = true
	await get_tree().create_timer(0.7).timeout
	var tween := get_tree().create_tween().set_parallel()
	var duration := 8
	tween.tween_property($CanvasLayer/Black, "modulate:a", 1, duration)
	tween.tween_property($Music/Soul, "pitch_scale", 0.2, duration)
	tween.tween_property($Music/Soul, "volume_linear", 0, duration + 3)
	tween.set_trans(Tween.TRANS_QUAD)
	var set_offset := func(offset, idx): %Vignette.texture.gradient.set_offset(idx, offset)
	var set_color := func(color, idx): %Vignette.texture.gradient.set_color(idx, color)
	tween.tween_method(set_offset.bind(1), 0.654, 0, duration)
	tween.tween_method(set_color.bind(1), Color("00000000"), Color("000000ff"), duration)
	tween.tween_property($WorldEnvironment, "environment:sky_custom_fov", 180, duration + 3)
	await tween.finished
	await get_tree().create_timer(0.5).timeout
	
	var scene := preload(ROOM_SCENE_PATH).instantiate()
	get_tree().change_scene_to_node(scene)
