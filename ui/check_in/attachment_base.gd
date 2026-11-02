class_name AttachmentButton extends Button

static var _pressed := false
signal reappeared

func _ready() -> void:
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	pressed.connect(_hover.bind(false, true))
	reappeared.connect(func(): _pressed = false)

func _exit_tree() -> void: _pressed = false

func _create_tween() -> Tween:
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween

func set_object(object_name: String, chr_code_name: String = "") -> void:
	if not %Object.get_child(0).has_node(object_name.to_pascal_case()):
		printerr("no such object exists (%s)" % object_name.to_pascal_case())
		return
	
	if chr_code_name:
		for sprite: AnimatedSprite3D in %Object.get_node("%Npc").get_children():
			sprite.play(chr_code_name + "_stand")
	
	for object: Node3D in %Object.get_child(0).get_children():
		object.visible = object.name == object_name.to_pascal_case()
		if object.name != object_name.to_pascal_case(): object.queue_free()

func _hover(hovering: bool, was_pressed := false) -> void:
	if was_pressed:
		MainUI.play_sound("press")
		_pressed = true
	elif not was_pressed and _pressed: return
	if hovering: MainUI.play_sound("hover")
	else: MainUI.play_sound("boing")
	
	var length := 0.4 if hovering else 0.2
	var target_scale = 1.0 if not hovering else 1.15
	var self_target_scale = 1.0 if not hovering else 1.05
	target_scale = Vector3(target_scale, target_scale, target_scale)
	self_target_scale = Vector2(self_target_scale, self_target_scale)
	if not hovering:
		target_scale.y = 0.7
		self_target_scale.y = 0.8
	var tween := _create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(%Object.get_child(0), "scale", target_scale, length)
	tween.parallel().tween_property(self, "offset_transform_scale", self_target_scale, length)
	if not hovering:
		tween.tween_property(%Object.get_child(0), "scale", Vector3(1, 1, 1), length)
		tween.parallel().tween_property(self, "offset_transform_scale", Vector2(1, 1), length)
