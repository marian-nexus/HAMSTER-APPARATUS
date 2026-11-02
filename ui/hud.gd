extends Control

@onready var context_y: float = $ContextMenu.position.y
var heart_broken := false
var date_time := {}
var time_update := Timer.new()
@onready var hover_items := [%Heart, %PrevCamera, %NextCamera]
const HOVER_SCALE := 1.05
const HOVER_TIME := 0.2
signal context_menu_shown

func _ready() -> void:
	Chuuni.characters_set_up.connect(_set_up_chr_info)
	Chuuni.entering_check_in.connect(_on_entered_check_in)
	Chuuni.exiting_check_in.connect(_on_exited_check_in)
	MainUI.camera_changed.connect(_update_camera_text)
	Chuuni.relationship_changed.connect(_update_relationship)
	
	MainUI.start_following.connect(func(chr: Character):
		if MainUI.following_character: MainUI.stop_following.emit(MainUI.following_character)
		MainUI.following_character = chr
		)
	
	var context_dismiss_buttons := [%PrevCamera, %NextCamera]
	for button: Button in context_dismiss_buttons:
		button.pressed.connect(_hide_context_menu)
	
	for button: Button in $ContextMenu/VBoxContainer.get_children():
		button.pressed.connect(func(): MainUI.play_sound("press"))
	
	_apply_settings(Chuuni.settings)
	Chuuni.settings_changed.connect(_apply_settings)
	
	add_child(time_update)
	_update_relationship(0, 0)
	_set_random_time()
	time_update.start(1)
	time_update.timeout.connect(_update_time)

func _apply_settings(settings: Dictionary) -> void:
	%CameraControls.get_node("Room").visible = settings.lock_room

func _set_up_chr_info() -> void:
	var characters := Chuuni.characters.values()
	for child in $CharacterInfo.get_children():
		if not child is CharInfoBox: continue
		child.setup(characters.pop_front())
		child.find_child("Button").pressed.connect(_show_context_menu.bind(child))
		for desc in child.get_node("Stats").get_children():
			hover_items.append(desc.get_child(0))
	
	_set_up_hover()

func _set_up_hover() -> void:
	for item: Control in hover_items:
		var hover_scale = 1.06
		if item.size.y < 50: hover_scale = 1.15
		hover_scale = Vector2(hover_scale, hover_scale)
		
		item.offset_transform_enabled = true
		item.mouse_entered.connect(func():
			var tween := get_tree().create_tween()
			tween.tween_property(item, "offset_transform_scale", \
			hover_scale, HOVER_TIME)
			MainUI.play_sound("hover")
			
			if item != %Heart: return
			tween.parallel().tween_property(%RelationshipValue, "offset_transform_scale",
			hover_scale * 1.05, HOVER_TIME))
		
		item.mouse_exited.connect(func():
			var tween := get_tree().create_tween()
			tween.tween_property(item, "offset_transform_scale", Vector2(1, 1), HOVER_TIME)
			if item != %Heart: return
			tween.parallel().tween_property(%RelationshipValue, "offset_transform_scale",
			Vector2(1, 1), HOVER_TIME))

func _show_context_menu(info_box: CharInfoBox) -> void:
	context_menu_shown.emit()
	MainUI.context_menu_visible = true
	MainUI.play_sound("press")
	var button: Button = info_box.find_child("Button")
	if $ContextMenu.visible: _hide_context_menu(true)
	$ContextMenu.position = Vector2(
		button.global_position.x + (Chuuni.get_difference(button.size.x, $ContextMenu.size.x) / 2),
		context_y - button.size.y - 30)
	
	$ContextMenu.offset_transform_scale.y = 0
	get_tree().create_tween().set_trans(Tween.TRANS_BACK).tween_property(
		$ContextMenu, "offset_transform_scale:y", 1, 0.15)
	
	$ContextMenu.show()
	%CheckIn.pressed.connect(Chuuni.enter_check_in_menu.bind(info_box.character))
	%CheckIn.pressed.connect(_hide_context_menu)
	%Follow.pressed.connect(_hide_context_menu)
	
	var chr := info_box.character
	if MainUI.following_character == chr:
		%Follow.text = "stop following"
		%Follow.pressed.connect(MainUI.stop_following.emit.bind(chr))
	else:
		%Follow.text = "follow with camera"
		%Follow.pressed.connect(MainUI.start_following.emit.bind(chr))

func _set_random_time() -> void:
	var year := randi_range(2000, 2099)
	var month := randi_range(1, 12)
	var _31_days := [1, 3, 5, 7, 8, 10, 12]
	var day: int
	if month in _31_days: day = randi_range(1, 31)
	elif month == 2:
		if _is_leap_year(year): day = randi_range(1, 29)
		else: day = randi_range(1, 28)
	else: day = randi_range(1, 30)
	
	date_time.year = year
	date_time.month = month
	date_time.day = day
	date_time.hour = randi_range(0, 23)
	date_time.minute = randi_range(0, 59)
	date_time.second = randi_range(0, 59)
	
	_set_timestamp()

func _update_time() -> void:
	date_time.second += 1
	if date_time.second > 59:
		date_time.second = 0; date_time.minute += 1
		
		if date_time.minute > 59:
			date_time.minute = 0; date_time.hour += 1
			
			if date_time.hour > 23:
				date_time.hour = 0; date_time.day += 1
				
				if _is_new_month():
					date_time.day = 1; date_time.month += 1
					
					if date_time.month > 12:
						date_time.month = 1; date_time.year += 1
	
	_set_timestamp()

func _is_new_month() -> bool:
	var _31_days := [1, 3, 5, 7, 8, 10, 12]
	if date_time.month == 2:
		if _is_leap_year(date_time.year) and date_time.day == 30: return true
		elif not _is_leap_year(date_time.year) and date_time.day == 29: return true
	
	if date_time.month in _31_days and date_time.day == 32: return true
	if date_time.day == 31: return true
	return false

func _is_leap_year(year: int) -> bool:
	return year % 4 == 0

func _set_timestamp() -> void:
	var month_str := str(date_time.month)
	if month_str.length() == 1: month_str = "0" + month_str
	var day_str := str(date_time.day)
	if day_str.length() == 1: day_str = "0" + day_str
	var date := str(date_time.year) + "/" + month_str + "/" + day_str
	
	var separator := ":"
	#if ":" in %Timestamp.text: separator = " "
	var time := ""
	for i in [date_time.hour, date_time.minute, date_time.second]:
		if not time.is_empty(): time += separator
		var string: String = str(i)
		if string.length() == 1: string = "0" + string
		time += string
	
	%Timestamp.text = date + " " + time

func _update_camera_text(camera: Camera3D) -> void:
	var text := "cam_"
	for i in range(2):
		if ["Bedroom1", "Bedroom2"][i] in camera.name:
			var npc_name: String = Chuuni.characters.values()[i].npc_name
			npc_name = npc_name.replace_chars(" -,./", "_".unicode_at(0))
			text += npc_name + "_"
	
	if not camera.has_meta("custom_name"):
		if text.length() == 4: text += "main_"
		text += "0" + camera.name.substr(camera.name.length() - 1, -1)
	else: text += camera.get_meta("custom_name")
	%CameraName.text = text

func _update_relationship(previous: int, current: int) -> void:
	var rel_label := Chuuni.relationship_label
	var diff := str(Chuuni.get_difference(previous, current))
	diff = "-" + diff if previous > current else "+" + diff
	
	var no_tween := rel_label == ""
	if no_tween: rel_label = %RelationshipValue.text
	%Heart.tooltip_text = "relationship: " + rel_label + " (" + str(current) + "/100)"
	if no_tween: return
	
	if current > previous:
		if %RelationshipValue.text != rel_label: %RelAnimationPlayer.play("beat_change")
		else: %RelAnimationPlayer.play("beat_no_change")
	else:
		if %RelationshipValue.text != rel_label: %RelAnimationPlayer.play("shake_change")
		else: %RelAnimationPlayer.play("shake_no_change")
	%RelationshipValue.text = rel_label
	
	var diff_label: Label = %RelDiff.duplicate()
	diff_label.text = diff
	%RelDiff.get_parent().add_child(diff_label)
	var diff_tween := get_tree().create_tween().set_parallel()
	var diff_tween_2 := get_tree().create_tween().set_trans(Tween.TRANS_QUAD)
	diff_label.modulate.a = 0
	diff_label.show()
	diff_tween.tween_property(diff_label, "modulate:a", 1, 0.2)
	diff_tween.tween_property(diff_label, "offset_transform_position:y", -120, 1)
	diff_tween_2.tween_property(diff_label, "offset_transform_position_ratio:x", -0.05, 0.5)
	diff_tween_2.tween_property(diff_label, "offset_transform_position_ratio:x", 0.05, 0.5)
	
	get_tree().create_timer(0.8, false).timeout.connect(func():
		var diff_tween_3 := get_tree().create_tween()
		diff_tween_3.tween_property(diff_label, "modulate:a", 0, 0.2))
	
	get_tree().create_timer(1, false).timeout.connect(func(): diff_label.queue_free())
	
	if Chuuni.is_enemies() and not heart_broken: _break_heart()
	elif not Chuuni.is_enemies() and heart_broken: _unbreak_heart()

func _break_heart() -> void:
	heart_broken = true
	%Heart.texture.region.position.x = 143
	await get_tree().create_timer(0.2, false).timeout
	%Heart.texture.region.position.x = 143 * 2

func _unbreak_heart() -> void:
	heart_broken = false
	%Heart.texture.region.position.x = 143
	await get_tree().create_timer(0.2, false).timeout
	%Heart.texture.region.position.x = 0

func _on_entered_check_in(_character) -> void:
	hide()

func _on_exited_check_in() -> void:
	show()

func _hide_context_menu(immediate := false) -> void:
	if not $ContextMenu.visible: return
	if not immediate: MainUI.context_menu_visible = false
	
	if not immediate:
		get_tree().create_tween().set_trans(Tween.TRANS_BACK).tween_property(
			$ContextMenu, "offset_transform_scale:y", 0, 0.15)
		await get_tree().create_timer(0.15).timeout
	$ContextMenu.hide()
	
	for button: Button in $ContextMenu.get_child(0).get_children():
		for connection: Dictionary in button.pressed.get_connections():
			if "anonymous" in str(connection.callable): continue
			button.pressed.disconnect(connection.callable)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("click"): return
	if $ContextMenu.visible: _hide_context_menu()
