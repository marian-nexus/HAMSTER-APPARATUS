extends CanvasLayer
signal debug_raycast
signal cook_action_selected
signal prev_camera
signal next_camera
signal next_room
signal prev_room
signal camera_changed(camera: Camera3D)
signal start_following(character: Character)
signal stop_following(character: Character)
var thought_bubble_owner: Character
var following_character
var context_menu_visible := false

const KEYBIND_SIGNALS := ["prev_camera", "next_camera", "next_room", "prev_room"]

func _ready() -> void:
	visible = get_tree().current_scene.name == "Room"
	$CheckIn.hide()
	$HUD.show()
	$ThoughtBubble.hide()
	get_tree().scene_changed.connect(func():
		visible = get_tree().current_scene.name == "Room")
	
	for button: Button in %FoodOptions.get_children():
		button.pressed.connect(hide_thought_bubble)
	
	%PrevCamera.pressed.connect(prev_camera.emit)
	%NextCamera.pressed.connect(next_camera.emit)
	%PrevRoom.pressed.connect(prev_room.emit)
	%NextRoom.pressed.connect(next_room.emit)

func fade_in() -> void:
	$FadeIn.texture.gradient.set_color(0, Color(0, 0, 0, 0))
	$FadeIn.show()
	var _set_offset = func(_offset, idx): $FadeIn.texture.gradient.set_offset(idx, _offset)
	var _set_color = func(_color, idx): $FadeIn.texture.gradient.set_color(idx, _color)
	var tween := get_tree().create_tween().set_parallel()
	var duration := 1
	
	tween.tween_method(_set_offset.bind(1), 0.025, 0.45, duration)
	tween.tween_method(_set_color.bind(1), Color(0, 0, 0, 1), Color(0, 0, 0, 0), duration)
	tween.tween_method(_set_offset.bind(2), 0.433, 1, duration).set_delay(0.35)
	tween.tween_method(_set_color.bind(2), Color(0, 0, 0, 1), Color(0, 0, 0, 0), duration).set_delay(0.35)
	tween.chain().tween_method(_set_color.bind(3), Color(0, 0, 0, 1), Color(0, 0, 0, 0), duration)
	await tween.finished
	$FadeIn.hide()

func play_sound(sound_name: String) -> void:
	var sound = get_node_or_null("Sounds/" + sound_name.to_pascal_case())
	if not sound: printerr(sound_name + " not found in sounds."); return
	sound.play()

func show_thought_bubble(character: Character) -> void:
	if thought_bubble_owner and thought_bubble_owner != character: _disconnect_hidden_signal()
	if $ThoughtBubble.visible: hide_thought_bubble()
	thought_bubble_owner = character
	_position_thought_bubble()
	$ThoughtBubble.show()
	character.model.thought_bubble_hidden.connect(hide_thought_bubble)
	
	for button: Button in %FoodOptions.get_children():
		button.pressed.connect(cook_action_selected.emit.bind(thought_bubble_owner, button.text.to_lower()))

func hide_thought_bubble() -> void:
	if not $ThoughtBubble.visible: return
	$ThoughtBubble.hide()
	for button: Button in %FoodOptions.get_children():
		button.pressed.disconnect(cook_action_selected.emit)
	_disconnect_hidden_signal()

func _position_thought_bubble() -> void:
	var camera: Camera3D = get_tree().current_scene.current_camera
	var bubble_position: Vector3 = thought_bubble_owner.model.get_node("ThoughtBubble").global_position
	var char_position := camera.unproject_position(bubble_position)
	$ThoughtBubble.position = Vector2(
		char_position.x - ($ThoughtBubble.size.y),
		char_position.y - ($ThoughtBubble.size.y - 30)
	)

func _disconnect_hidden_signal() -> void:
	var hidden_signal: Signal = thought_bubble_owner.model.thought_bubble_hidden
	if not hidden_signal.is_connected(hide_thought_bubble): return
	hidden_signal.disconnect(hide_thought_bubble)

func _physics_process(delta: float) -> void:
	if $ThoughtBubble.visible: _position_thought_bubble()

func _unhandled_input(event: InputEvent) -> void:
	for sig: String in KEYBIND_SIGNALS:
		if event.is_action_pressed(sig): self[sig].emit()
