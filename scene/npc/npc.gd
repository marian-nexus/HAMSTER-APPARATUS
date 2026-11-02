class_name CharacterModel extends CharacterBody3D
@export var character: Character
@export var state_machine: StateMachine
@export var hollow := false
@onready var sprite_default_y: float = $SpriteFront.position.y

const HAND_Y := {"stand": 0.409, "sit": 0.143}

# for the check in npc ^_^
@export var chr_appearance_name: String
var character_appearance: Character:
	set(value):
		character_appearance = value
		var id = Chuuni.characters.find_key(value)
		for sprite in [$SpriteFront, $SpriteBack]:
			sprite.play(id + "_stand")

var movement_speed: float = 1.5
var pathfinding_target: Node3D
var is_jumping := false
var is_sitting := false
var _mid_jump := false
var _existed_for_more_than_one_second := false
var fall_acceleration = 4
var jump_speed = 3
var target_velocity = Vector3.ZERO
var position_target := Vector3.ZERO # target with no pathfinding
var look_at_target := Vector3.ZERO
var is_eating := false
var hold_position := false

var posture_state := "stand"
var emotional_state := ""

signal reached_target
signal clicked
signal finished_eating
signal thought_bubble_hidden

var animation := "stand_there":
	set(value):
		animation = value
		$AnimationPlayer.play(animation)

const _BUSY_ENERGY_DECAY := 3
var busy_decay_timer := Timer.new()

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

func _ready():
	if chr_appearance_name: character_appearance = Chuuni.characters[chr_appearance_name]
	if hollow:
		_existed_for_more_than_one_second = true
	
	$NavigationAgent3D.velocity_computed.connect(_on_velocity_computed)
	if hollow: look_at_target = global_basis.z * -2
	if not character: return
	set_anim("stand")
	clicked.connect(_on_clicked)
	MainUI.cook_action_selected.connect(func(chr: Character, _a):
		if chr == character: hide_thought_bubble()
	)
	character.state_machine.action_started.connect(func(action: Action):
		if _is_treating_hunger(): hide_thought_bubble()
		)
	
	add_child(busy_decay_timer)
	busy_decay_timer.wait_time = _BUSY_ENERGY_DECAY
	busy_decay_timer.timeout.connect(_busy_energy_decay)
	character.state_machine.state_changed.connect(func():
		if character.state_machine.state == StateMachine.State.BUSY: busy_decay_timer.start()
		else: busy_decay_timer.stop()
	)
	character.started_socialising.connect(_while_socialising)
	get_tree().create_timer(1, false).timeout.connect(func():
		_existed_for_more_than_one_second = true)

func set_anim(posture: String, emotion := "") -> void:
	var code_name: String = Chuuni.characters.find_key(character)
	if not posture: posture = posture_state
	emotional_state = emotion
	var anim_name = code_name + "_" + posture
	
	match posture:
		"sleep": $SpriteBack.play(code_name + "_sit")
		"talk": $SpriteBack.play(code_name + "_stand")
		_: $SpriteBack.play(anim_name)
	
	if not posture in ["sleep", "talk"]:
		$SpriteBack.play(code_name + "_" + posture)
	else: $SpriteBack.play(code_name + "_stand")
	
	if emotion: anim_name += "_" + emotion
	$SpriteFront.play(anim_name)
	
	if posture == "talk":
		var _on_frame_changed := func():
			if $SpriteFront.frame == 1: $Talk.play()
		
		$SpriteFront.frame_changed.connect(_on_frame_changed)
		$SpriteFront.animation_changed.connect(func():
			$SpriteFront.frame_changed.disconnect(_on_frame_changed),
			CONNECT_ONE_SHOT)

func start_decay() -> void:
	for stat: String in ["hunger", "social", "energy", "happiness"]:
		get_tree().create_timer(character.personality[stat + "_decay"], false).timeout.connect(_stat_decay.bind(stat))

func _busy_energy_decay() -> void:
	if is_eating: return
	character.personality.energy -= 1

func _stat_decay(stat_name: String) -> void:
	var will_decay := true
	if stat_name == "hunger" and _is_treating_hunger(): will_decay = false
	if stat_name == "social" and character.is_socialising: will_decay = false
	if stat_name == "energy" and is_eating: will_decay = false
	if character.state_machine.state == StateMachine.State.SLEEPING: will_decay = false
	if character.state_machine.state == StateMachine.State.PHOTOSYNTHESIS: will_decay = false
	if will_decay:
		character.personality[stat_name] -= 1
		if stat_name == "hunger" and character.personality.hunger <= 30:
			character.personality.energy -= 1
	get_tree().create_timer(character.personality[stat_name + "_decay"], false)\
	.timeout.connect(_stat_decay.bind(stat_name))
	
	if stat_name == "hunger" and character.personality.hunger <=\
	character.personality.hunger_threshold:
		if _is_treating_hunger(): return
		#show_thought_bubble()
	
	if stat_name == "social" and character.personality.social <= 15 and not character.is_socialising:
		character.personality.happiness -= 2

func _is_treating_hunger() -> bool:
	var hunger_actions := ["cook", "eat"]
	for string in hunger_actions:
		if string in character.state_machine.current_action.action_name: return true
		for action: Action in character.state_machine.action_queue:
			if string in action.action_name: return true
	return false

func _while_socialising() -> void:
	if not character.is_socialising: return
	character.personality.social += 1
	get_tree().create_timer(3, false).timeout.connect(_while_socialising)

func start_eating() -> void:
	if is_eating: return
	is_eating = true
	print("eating until hunger is at " + str(character.get_meta("hunger_target")))
	_eat(character.personality.hunger)

func stop_eating() -> void:
	character.remove_meta("hunger_target")
	is_eating = false
	finished_eating.emit()

func _eat(starting_hunger: int) -> void:
	if not is_eating: return
	# for now we'll just replenish this shit up to a point
	character.personality.hunger += 1
	if character.personality.hunger >= character.get_meta("hunger_target"): stop_eating()
	if is_eating: get_tree().create_timer(character.personality.eat_time, false).timeout.connect(
		_eat.bind(starting_hunger))

func show_thought_bubble() -> void:
	$ThoughtBubble.show()
	$CollisionThought.disabled = false

func hide_thought_bubble() -> void:
	$ThoughtBubble.hide()
	$CollisionThought.disabled = true
	thought_bubble_hidden.emit()

func _on_clicked() -> void:
	if not $ThoughtBubble.visible: return
	MainUI.show_thought_bubble(character)

func jump():
	is_jumping = true

func sit(savour := false):
	if is_sitting: return
	is_sitting = true
	set_anim("sit", "savour" if savour else "")
	$Hand.position.y = HAND_Y.sit

func stand():
	is_sitting = false
	set_anim("stand")
	$Hand.position.y = HAND_Y.stand

func sleep():
	set_anim("sleep")
	get_tree().create_tween().tween_property(
		$AnimationPlayer, "speed_scale", 0.5, 0.5)

func wake_up():
	get_tree().create_tween().tween_property(
		$AnimationPlayer, "speed_scale", 1, 0.5)
	$SpriteFront.play_backwards($SpriteFront.animation)
	await $SpriteFront.animation_finished
	sit()

func show_emotion(emotion_name: String) -> void:
	var previous_anim_name: String = $SpriteFront.animation
	var new_animation_name: String = Chuuni.characters.find_key(character) + "_sit_" + emotion_name
	$SpriteFront.play(new_animation_name)
	get_tree().create_timer(2, false).timeout.connect(func():
		if $SpriteFront.animation != new_animation_name: return
		$SpriteFront.play(previous_anim_name))

func set_movement_target(movement_target):
	if movement_target is Node3D:
		pathfinding_target = movement_target
		movement_target = movement_target.position
	else: pathfinding_target = null
	navigation_agent.set_target_position(movement_target)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if hold_position: return
	if position_target == Vector3.ZERO and not hollow: velocity = safe_velocity
	else: velocity = target_velocity
	move_and_slide()

func _physics_process(delta):
	for prop in ["position", "scale"]:
		$SpriteBack[prop] = $SpriteFront[prop]
	$SpriteBack.rotation.z = $SpriteFront.rotation.z
	
	for child: Node3D in $Hand.get_children():
		child.rotation.z = $SpriteFront.rotation.z
		child.position.y = $SpriteFront.position.y - sprite_default_y
	
	if hold_position: return
	
	if navigation_agent.is_navigation_finished():
		pathfinding_target = null
	
	if pathfinding_target: navigation_agent.set_target_position(pathfinding_target.position)
	var current_agent_position: Vector3 = global_position
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	
	target_velocity.x = current_agent_position.direction_to(next_path_position).x * movement_speed
	target_velocity.z = current_agent_position.direction_to(next_path_position).z * movement_speed
	
	if position_target != Vector3.ZERO:
		target_velocity.x = global_position.direction_to(position_target).x * movement_speed
		target_velocity.z = global_position.direction_to(position_target).z * movement_speed
		if floor(Chuuni.get_difference(global_position.x, position_target.x) * 1000) < 2:
			reached_target.emit()
	
	if not is_on_floor():
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
		_mid_jump = true
	elif is_jumping:
		$Jump.play()
		target_velocity.y = jump_speed
		_mid_jump = true
		is_jumping = false
	elif is_on_floor() and _mid_jump:
		_mid_jump = false
		if _existed_for_more_than_one_second: $Land.play()
	
	$NavigationAgent3D.velocity = target_velocity
	
	if velocity != Vector3.ZERO or look_at_target != Vector3.ZERO:
		var target_pos = position + velocity if look_at_target == Vector3.ZERO else look_at_target
		var rot = global_transform.basis.get_rotation_quaternion()
		look_at(target_pos)
		var target_rot = global_transform.basis.get_rotation_quaternion()
		target_rot.x = 0; target_rot.z = 0
		rotation = rot.slerp(target_rot.normalized(), 0.07).get_euler()
	
	if velocity != Vector3.ZERO:
		if not is_on_floor(): animation = "stand_there"
		else: animation = "bounce"
	else:
		animation = "stand_there"
