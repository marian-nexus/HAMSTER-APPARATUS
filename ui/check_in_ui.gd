extends Control

var character: Character
@onready var tabs := {"basic": %BasicInfo, "attachments": %Attachments, "object": %Object}
@onready var setup := {%BasicInfo: _set_basic_info, %Attachments: _set_attachments}
var sprites := {}
var current_tab
var mugshot_volatility := 0:
	set(value): mugshot_volatility = value; if value <= 1: _volatility_depleted.emit()
var mugshot_hovered := 0
var mugshot_timer: SceneTreeTimer
var is_hovering_mugshot := false:
	set(value): is_hovering_mugshot = value; _hovering_changed.emit(value)
var stat_tooltips: Dictionary
var thought_cycle_state := 1
var thought_auto_cycle_info := {}

signal _hovering_changed(value: bool)
signal _volatility_depleted
signal _mugshot_tween_started

func _ready() -> void:
	Chuuni.entering_check_in.connect(_show)
	%CheckInExit.pressed.connect(_exit)
	_set_button_sounds(find_children("*", "Button"))
	
	for i in range(%Tabs.get_child_count()):
		var button: Button = %Tabs.get_child(i)
		button.pressed.connect(_set_tab.bind(tabs.values()[i]))
		button.mouse_entered.connect(_tab_hover.bind(button, true))
		button.mouse_exited.connect(_tab_hover.bind(button, false))
	
	var sprite_path := "res://scene/npc/sprites/%s/%s_stand_%s.png"
	for chr_name: String in Chuuni.characters.keys():
		var chr_sprites := []
		for i in range(1, 4):
			chr_sprites.append(load(sprite_path % [chr_name, chr_name, str(i)]))
		sprites[chr_name] = chr_sprites
	
	%MugshotHover.mouse_entered.connect(_mugshot_hover.bind(true))
	%MugshotHover.mouse_exited.connect(_mugshot_hover.bind(false))
	%StatsContainer.mouse_entered.connect(_stats_container_hover.bind(true))
	%StatsContainer.mouse_exited.connect(_stats_container_hover.bind(false))
	
	for button: Button in [%CheckInExit, %PrevThought, %NextThought]:
		button.mouse_entered.connect(_tab_hover.bind(button, true))
		button.mouse_exited.connect(_tab_hover.bind(button, false))
	
	var timer := Timer.new(); add_child(timer)
	timer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	timer.start(2)
	timer.timeout.connect(func(): if randi() % 50 == 1: _blink())
	
	var tooltips_json := FileAccess.get_file_as_string("res://data/tooltips.json")
	stat_tooltips = JSON.parse_string(tooltips_json).stats

func _set_button_sounds(buttons: Array) -> void:
	for button: Button in buttons:
		button.pressed.connect(func(): MainUI.play_sound("press"))
		button.mouse_entered.connect(func(): MainUI.play_sound("hover"))

func _show(chr: Character) -> void:
	character = chr
	var chr_sprites: Array = sprites[Chuuni.characters.find_key(chr)]
	var new_sprite = chr_sprites[0]
	if randi() % 30 == 1: new_sprite = chr_sprites[2]
	%MugshotSprite.texture.atlas = new_sprite
	_mugshot_hover(true, true)
	
	_set_tab(tabs.basic, false)
	show()

func _exit() -> void:
	_disable_thought_cycle()
	for button: Button in %AttachmentsList.get_children(): button.queue_free()
	
	Chuuni.leave_check_in_menu()
	hide()
	current_tab = null
	for meta in get_meta_list():
		remove_meta(meta)

func _set_tab(tab: Control, fade := true) -> void:
	_disable_thought_cycle()
	var fading := false
	if current_tab == tab: return
	if current_tab and fade: %TabFade.play("fade_out"); fading = true
	if current_tab == tabs.object:
		if fade: get_tree().create_timer(0.4).timeout.connect(func():
			%ObjectSubViewport.get_node("AnimationPlayer").stop())
		else: %ObjectSubViewport.get_node("AnimationPlayer").stop()
	
	current_tab = tab
	if tab == tabs.attachments and has_meta("Attachments") and %AttachmentsList.get_child_count() > 0:
		%AttachmentsList.get_child(0).reappeared.emit()
	
	if not has_meta(tab.name) and tab in setup:
		setup[tab].call()
		set_meta(tab.name, true)
	
	var sort_tabs := func():
		for _tab: Control in tabs.values(): _tab.visible = _tab == tab
	
	if tab == tabs.basic:
		%StatsContainer.offset_transform_rotation = 0
		%StatsContainer.set_meta("no", true)
		var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(%StatsContainer, "offset_transform_rotation", 0.05, 1.5)
		get_tree().create_timer(1.6).timeout.connect(func(): %StatsContainer.remove_meta("no"))
	
	if fading: get_tree().create_timer(0.4).timeout.connect(func():
		%TabFade.play("fade_in"); sort_tabs.call())
	else:
		sort_tabs.call()

func _set_basic_info() -> void:
	for child in %InfoTable.get_children(): child.queue_free()
	for child in %Stats.get_children(): child.queue_free()
	
	var info := {
		"name": character.npc_name,
		"birthday": character.birthday,
		"serial number": character.serial_number,
		"age": character.age
	}
	
	var ti_scene := preload("res://ui/check_in/table_item.tscn")
	for key: String in info.keys():
		var item: TableItem = ti_scene.instantiate()
		%InfoTable.add_child(item)
		item.set_text(key, info[key])
	
	var stats: Array = character.personality.health_traits \
		+ ["activeness"] \
		+ character.personality.personality_traits \
		+ character.personality.reactive_traits
	
	for stat: String in stats:
		var stat_label := _create_stat_label(stat)
		%Stats.add_child(stat_label)
		
		var stat_number: int = character.personality[stat]
		var stat_constraint := 30
		if stat + "_constraint" in character.personality:
			stat_constraint = character.personality[stat + "_constraint"]
		elif stat in character.personality.health_traits:
			stat_constraint = character.personality.stat_constraints[0]
		elif stat == "fear": stat_constraint = 10
		
		stat_label.tooltip_text = stat_tooltips[stat]
		stat_label.mouse_default_cursor_shape = Control.CURSOR_HELP
		stat_label.mouse_filter = Control.MOUSE_FILTER_STOP
		
		var bar_scene := preload("res://ui/check_in/stat_visualiser.tscn")
		var bar = bar_scene.instantiate()
		%Stats.add_child(bar)
		bar = bar.get_child(0)
		bar.max_value = stat_constraint
		
		var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_QUINT)
		tween.tween_property(bar, "value", stat_number, 2)
		
		var stat_num_label := _create_stat_label(str(stat_number), HORIZONTAL_ALIGNMENT_LEFT)
		%Stats.add_child(stat_num_label)

func _create_stat_label(text: String, alignment := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings = load("res://ui/theme/stats_label_settings.tres")
	label.visible = true
	
	return label

func _set_attachments() -> void:
	var objects := character.get_memory_objects()
	if not %NoAttachments.has_meta("default"): %NoAttachments.set_meta("default", %NoAttachments.text)
	%NoAttachments.text = %NoAttachments.get_meta("default") % character.npc_name
	%AttachmentsScroll.scroll_vertical = 0
	
	for button in %AttachmentsList.get_children():
		button.queue_free()
	
	var button_scene := preload("res://ui/check_in/attachment_base.tscn")
	var buttons_created := 0
	for object in objects:
		if character.get_memory_texts(object).is_empty(): continue
		var button: AttachmentButton = button_scene.instantiate()
		var object_name: String = str(object.name)
		if object is Character:
			object_name = object.npc_name
			button.set_object("NPC", Chuuni.characters.find_key(object))
		else: button.set_object(object_name.to_snake_case())
		object_name = object_name.to_snake_case()
		object_name = object_name.replacen("_", " ")
		button.text = object_name
		button.show()
		%AttachmentsList.add_child(button)
		buttons_created += 1
		button.pressed.connect(_set_object_info.bind(object, object_name))
		#button.pressed.connect(func(): print(character.get_memory_texts(object)))
	
	%NoAttachments.visible = buttons_created == 0

func _set_object_info(object, object_name: String) -> void:
	%ObjectName.text = object_name
	if character.npc_name.length() > 8: %FeelingsHeader.label_settings.font.spacing_glyph = -2
	if character.npc_name.length() > 11: %FeelingsHeader.label_settings.font.spacing_glyph = -3
	%FeelingsHeader.text = "%s's feelings" % character.npc_name
	object_name = object.name
	if object is Character:
		object_name = "Npc"
		var code_name: String = Chuuni.characters.find_key(object)
		for sprite: AnimatedSprite3D in %ObjectSubViewport.get_node("%Npc").get_children():
			sprite.play(code_name + "_stand")
	
	for _object: Node3D in %ObjectSubViewport.get_child(0).get_children():
		_object.visible = _object.name == object_name.to_pascal_case()
	
	var _tooltip_name: String
	if object is Character: _tooltip_name = object.npc_name
	else: _tooltip_name = "the " + object_name.to_lower()
	%FeelingsHeader.tooltip_text = %FeelingsHeader.get_meta("tooltip") % \
		[character.npc_name, _tooltip_name]
	%FeelingsSummary.tooltip_text = %FeelingsSummary.get_meta("tooltip") % _tooltip_name
	
	# feelings graph
	var feelings := character.get_feelings_toward(object)
	var associations_by_sentiment: Array
	var _sentiments := Memory.ass_sen.values().duplicate()
	_sentiments.sort()
	for i in _sentiments:
		for string: String in Memory.ass_sen.keys():
			if not string in associations_by_sentiment and Memory.ass_sen[string] == i:
				associations_by_sentiment.append(string); continue
	
	var multiplier := 100
	var max_value := 0
	for sentiment: int in feelings.values():
		if sentiment > max_value: max_value = sentiment
	
	for bar: ObjectSentimentsBar in %FeelingsGraph.get_node("XAxis").get_children():
		var association: String = associations_by_sentiment.pop_back()
		var value: int = feelings[association]
		bar.set_value(
			association,
			value * multiplier,
			Memory.ass_sen[association],
			max_value * multiplier
		)
	
	var sentiment: int = character.get_sentiment_toward(object)
	%FeelingsSummary.text = "sentiment: " + str(sentiment)
	var colours := ObjectSentimentsBar.colours.duplicate()
	var sentiment_colour: Color
	if sentiment < 0: sentiment_colour = colours.negative
	elif sentiment <= 3: sentiment_colour = colours.neutral
	else: sentiment_colour = colours.positive
	%FeelingsSummary.label_settings.font_color = sentiment_colour
	
	%FeelingsYAxis.get_child(0).text = str(max_value)
	if max_value == 1: %FeelingsYAxis.get_child(1).modulate.a = 0
	else:
		var half = float(max_value) / 2
		if Chuuni.get_difference(half, round(half)) > 0: half = snappedf(half, 0.5)
		else: half = int(half)
		%FeelingsYAxis.get_child(1).text = str(half)
		%FeelingsYAxis.get_child(1).modulate.a = 1
	
	# thoughts
	var thoughts := character.get_memory_texts(object)
	%ThoughtsHeader.text = "%s's thoughts (%s)" % [character.npc_name, str(thoughts.size())]
	%ThoughtText.text = '"%s"' % thoughts.back()
	for button: Button in [%PrevThought, %NextThought]:
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		
		if thoughts.size() > 1:
			var direction: int = -1 if button.get_index() == 0 else 1
			button.pressed.connect(_cycle_thoughts.bind(direction, thoughts))
		
		button.mouse_filter = MOUSE_FILTER_IGNORE if thoughts.size() == 1 else MOUSE_FILTER_STOP
		button.modulate.a = 0 if thoughts.size() == 1 else 1
		button.disabled = button.get_index() != 0
		if button.disabled: button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_set_tab(%Object)
	%ObjectSubViewport.get_node("AnimationPlayer").play("spin_slow")
	_reset_thought_cycle()
	thought_auto_cycle_info.thoughts = thoughts

func _reset_thought_cycle() -> void:
	thought_cycle_state = 1
	%ThoughtText.offset_transform_position_ratio.x = 0
	%ThoughtText.show()
	%ThoughtText2.offset_transform_position_ratio.x = -1
	%ThoughtText2.hide()
	var interval := 10
	var id := randi() % 1000
	
	thought_auto_cycle_info = {
		"id": id,
		"last_cycle": Time.get_ticks_msec(),
		"last_direction": -1,
		"interval": interval,
		"active": true
	}
	
	get_tree().create_timer(interval).timeout.connect(_auto_cycle_thoughts.bind(id))

func _disable_thought_cycle() -> void:
	if "active" in thought_auto_cycle_info:
		thought_auto_cycle_info.active = false

func _auto_cycle_thoughts(id: int) -> void:
	if id != thought_auto_cycle_info.id or not thought_auto_cycle_info.active: return
	if thought_auto_cycle_info.thoughts.size() == 1: return
	
	var interval: int = thought_auto_cycle_info.interval
	var time_since: int = Chuuni.get_difference(Time.get_ticks_msec(),
		thought_auto_cycle_info.last_cycle)
	
	if time_since >= interval * 1000 - 80: _cycle_thoughts(
		thought_auto_cycle_info.last_direction,
		thought_auto_cycle_info.thoughts, false)
	
	get_tree().create_timer(interval).timeout.connect(_auto_cycle_thoughts.bind(id))

func _cycle_thoughts(direction: int, thoughts: Array, user_initiated := true) -> void:
	var labels := [0, %ThoughtText, %ThoughtText2]
	var old_label: Label = labels[thought_cycle_state]
	var new_label: Label = labels[1 if thought_cycle_state == 2 else 2]
	var index: int = thoughts.find(old_label.text.substr(1, old_label.text.length() - 2))
	
	if not user_initiated: # check if direction is valid first
		if index == 0 and direction == -1: direction = 1
		elif index == thoughts.size() - 1 and direction == 1: direction = -1
	
	index += direction
	%PrevThought.disabled = index == 0
	%NextThought.disabled = index == thoughts.size() - 1
	var anim_name := "cycle_" + str(thought_cycle_state)
	if direction == -1: anim_name += "_back"
	%ThoughtCycle.play(anim_name)
	
	for button: Button in [%PrevThought, %NextThought]:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	old_label.show(); new_label.show()
	new_label.text = '"%s"' % thoughts[index]
	thought_cycle_state = 1 if thought_cycle_state == 2 else 2
	MainUI.play_sound("woosh")
	if user_initiated: MainUI.play_sound("press")
	
	%ThoughtCycle.animation_finished.connect(func(_name):
		old_label.hide()
		for button: Button in [%PrevThought, %NextThought]:
			if not button.disabled: button.mouse_filter = Control.MOUSE_FILTER_STOP
	, CONNECT_ONE_SHOT)
	
	thought_auto_cycle_info.last_cycle = Time.get_ticks_msec()
	thought_auto_cycle_info.last_direction = direction

func _tab_hover(tab: Button, hovering: bool) -> void:
	var target_rot: float = [0.03, -0.03][randi() % 2] if hovering else 0.0
	var target_scale: Vector2 = tab.offset_transform_scale * 1.05 if hovering else Vector2(1, 1)
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUAD).set_parallel()
	tween.tween_property(tab, "offset_transform_rotation", target_rot, 0.3)
	tween.tween_property(tab, "offset_transform_scale", target_scale, 0.3)

func _stats_container_hover(hovering: bool) -> void:
	if %StatsContainer.has_meta("no"): return
	var target_rot = 0.05 if not hovering else 0.04
	var length := 0.6 if hovering else 1.0
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_BACK if not hovering else Tween.TRANS_QUAD)
	tween.tween_property(%StatsContainer, "offset_transform_rotation", target_rot, length)

func _mugshot_hover(hovering: bool, automatic := false) -> void:
	is_hovering_mugshot = hovering
	if hovering: _add_volatility()
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_parallel()
	var panel: PanelContainer = %Mugshot.get_child(0)
	if not panel.has_meta("default_rot"): panel.set_meta("default_rot", panel.offset_transform_rotation)
	var target_rot: float = panel.get_meta("default_rot")
	if hovering: target_rot -= 0.02
	if automatic and hovering: target_rot -= 0.02
	if mugshot_volatility > 1:
		if not hovering: target_rot += 0.02
		else: target_rot -= 0.01
		target_rot *= mugshot_volatility
	
	var shadow_offset := "theme_override_styles/panel:shadow_offset"
	if not panel.has_meta("default_offset"): panel.set_meta("default_offset", \
		panel.get_theme_stylebox("panel").shadow_offset)
	
	var tween_length := 0.4 if not automatic else 0.6
	if automatic: tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	var offset_target: Vector2 = panel.get_meta("default_offset")
	if hovering: offset_target = Vector2(-2, 4.05)
	if mugshot_volatility > 1:
		if not hovering: offset_target = Vector2(0.2, 4.05)
		offset_target *= mugshot_volatility
		if mugshot_volatility > 2 and hovering: MainUI.play_sound("mugshot_release")
	
	if not automatic: MainUI.play_sound("hover")
	tween.tween_property(panel, "offset_transform_rotation", target_rot, tween_length)
	tween.tween_property(panel, shadow_offset, offset_target, tween_length)
	_mugshot_tween_started.emit()
	
	if not hovering and not automatic: _mugshot_timer(panel, target_rot, shadow_offset)
	elif hovering and automatic:
		get_tree().create_timer(tween_length).timeout.connect(_mugshot_hover.bind(false, true))

func _mugshot_timer(panel, target_rot, shadow_offset) -> void:
	if mugshot_timer and mugshot_timer.time_left > 0:
		mugshot_timer.timeout.disconnect(mugshot_timer.timeout.get_connections()[0].callable)
	
	mugshot_timer = get_tree().create_timer(0.04)
	mugshot_timer.timeout.connect(func():
		var timer := mugshot_timer
		if is_hovering_mugshot: await _hovering_changed
		if mugshot_volatility > 1: await _volatility_depleted
		if mugshot_timer != timer or is_hovering_mugshot: return
		if target_rot != panel.get_meta("default_rot"):
			var _tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			
			_mugshot_tween_started.connect(func():
				_tween.kill(), CONNECT_ONE_SHOT)
			
			var length := 2
			_tween.set_trans(Tween.TRANS_ELASTIC).set_parallel().set_ease(Tween.EASE_OUT)
			_tween.tween_property(panel, "offset_transform_rotation", panel.get_meta("default_rot"), length)
			_tween.tween_property(panel, shadow_offset, panel.get_meta("default_offset"), length))

func _add_volatility() -> void:
	mugshot_hovered += 1
	mugshot_volatility += 1
	get_tree().create_timer(0.5).timeout.connect(func(): mugshot_volatility -= 1)

func _blink() -> void:
	var _sprites: Array = sprites[Chuuni.characters.find_key(character)]
	var frame_time := 0.07
	var frames: Array
	if %MugshotSprite.texture.atlas == _sprites[2]: frames = [1, [0, 2], 1, 2]
	else: frames = [1, [2, frame_time * 3], 1, 0]
	for i in frames:
		if i is Array:
			%MugshotSprite.texture.atlas = _sprites[i[0]]
			await get_tree().create_timer(i[1]).timeout
		else:
			%MugshotSprite.texture.atlas = _sprites[i]
			if i != frames.size() - 1: await get_tree().create_timer(frame_time).timeout
