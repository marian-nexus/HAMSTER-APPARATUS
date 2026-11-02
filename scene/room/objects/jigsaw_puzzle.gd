extends Node3D

var is_set_up := false
var reclusive := false
var initiating_chr: Character

var puzzle_meshes := []
var puzzle_textures := []
var keyframes := []

@onready var box := $Box
@onready var lr = get_tree().current_scene.get_node("Scripts/LivingRoomActions")
@onready var global: Dictionary[String, Callable] = {
	"grab": lr._grab_tv_item.bind(box),
	"put_away": lr._put_away_tv_item.bind(box)
}

func _ready() -> void:
	var mesh_path := "res://scene/room/objects/puzzle/puzzle_"
	var tex_path := "res://scene/room/textures/puzzle_"
	for i in range(1, 13):
		puzzle_meshes.append(load(mesh_path + str(i) + ".tres"))
		puzzle_textures.append(load(tex_path + str(i) + ".png"))
		await get_tree().process_frame
	
	GlobalActions.register_action(do_jigsaw_puzzle, [self], ["happiness", "social"], \
		_puzzle_req, "do jigsaw puzzle")

func do_jigsaw_puzzle(character: Character) -> Action:
	var alone_subactions: Array[Callable] = [_decide_if_reclusive, global.grab, \
		_set_up_puzzle, _do_puzzle, _finish_puzzle, _reset_puzzle, global.put_away]
	var together_subactions: Array[Callable] = [_go_to_puzzle, _do_puzzle, _finish_puzzle]
	
	var action := Chuuni.create_action(character, alone_subactions, "do jigsaw puzzle")
	if is_set_up: action.subactions = together_subactions
	return action

func _puzzle_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	var other := Chuuni.get_other_character(character)
	if GlobalActions.is_queued_or_doing(other, "do jigsaw puzzle") and not is_set_up \
	or is_set_up and reclusive:
		req.possible = false; return req
	
	if not is_set_up:
		req.personality = character.personality.whimsy >= 10
		req.relationship = not Chuuni.is_enemies()
		if not req.relationship: req.context = character.personality.activeness >= 5
	else:
		req.relationship = not Chuuni.is_enemies()
		req.mood = character.personality.social <= 40 and character.personality.energy >= 15
		req.context = character.get_feelings_toward(other).fear < 3
		
		if character.get_feelings_toward(other).fear >= 8 and Chuuni.the_powerful == other:
			req.possible = false
	
	return req

func _get_puzzle_positions(character: Character) -> Dictionary[String, Vector3]:
	var markers: Node3D
	var dict: Dictionary[String, Vector3] = {}
	if not reclusive: markers = get_node("../PuzzlePositions")
	else: markers = character.bedroom.get_node("Objects/PuzzlePositions")
	
	for marker: Marker3D in markers.get_children():
		dict[marker.name.to_lower()] = marker.global_position
	dict.puzzle_rotation = markers.get_node("Puzzle").rotation
	
	return dict

func _decide_if_reclusive(action: Action) -> void:
	var chr := action.character
	var other := Chuuni.get_other_character(chr)
	initiating_chr = chr
	
	assert(not GlobalActions.is_queued_or_doing(other, "do jigsaw puzzle") and not is_set_up)
	var can_be_reclusive := false
	if Chuuni.is_enemies():
		if chr.personality.activeness <= 0 or chr.personality.fear >= 5: can_be_reclusive = true
	if Chuuni.the_powerful == chr: can_be_reclusive = false
	reclusive = can_be_reclusive
	
	if reclusive: action.zone = Chuuni.get_zone(chr.bedroom)
	
	action.subaction_finished.emit()

func _go_to_puzzle(action: Action) -> void:
	assert(is_set_up)
	var positions := _get_puzzle_positions(action.character)
	await GlobalActions.walk_to(action.character, positions.character2, true)
	action.subaction_finished.emit()

func _set_up_puzzle(action: Action) -> void:
	var positions := _get_puzzle_positions(action.character)
	await GlobalActions.walk_to(action.character, positions.character1, true)
	action.character.model.look_at_target = positions.puzzle
	action.character.state_machine.state = StateMachine.State.BUSY
	await get_tree().create_timer(0.3, false).timeout
	
	box.get_node("Sounds/Drop").play()
	_set_puzzle_mesh(0)
	$Puzzle.global_position = positions.puzzle
	$Puzzle.rotation = positions.puzzle_rotation
	$Puzzle.show()
	await get_tree().create_timer(0.2, false).timeout
	
	box.hide()
	action.character.set_meta("social_decay", action.character.personality.social_decay)
	action.character.personality.social_decay /= 2
	
	is_set_up = true
	action.subaction_finished.emit()

func _set_keyframes(threshold: int) -> void:
	keyframes = []
	var part := float(threshold - 2) / float(puzzle_meshes.size() - 1)
	for i in range(1, puzzle_meshes.size()):
		keyframes.append(int(round(part * i)))
	_set_puzzle_mesh(0)

func _set_puzzle_mesh(id: int) -> void:
	var override: BaseMaterial3D = %Completed.get_surface_override_material(0)
	%Completed.mesh = puzzle_meshes[id]
	override.albedo_texture = puzzle_textures[id]

func _do_puzzle(action: Action) -> void:
	var chr := action.character
	var other := Chuuni.get_other_character(chr)
	chr.model.look_at_target = _get_puzzle_positions(chr).puzzle
	action.character.model.sit()
	chr.state_machine.state = StateMachine.State.BUSY
	chr.is_socialising = other.has_meta("doing_puzzle") or initiating_chr != chr
	
	chr.set_meta("doing_puzzle", true)
	if not chr.has_meta("boredom_threshold") and initiating_chr == chr:
		var threshold := randi_range(25, 35)
		chr.set_meta("boredom_threshold", threshold)
		_set_keyframes(threshold)
	
	# prevent boredom from accumulating if the other character is coming to join
	if GlobalActions.is_queued_or_doing(other, "do jigsaw puzzle") and \
	not other.has_meta("doing_puzzle") and initiating_chr == chr:
		chr.set_meta("boredom", 0)
		if chr.get_meta("boredom_threshold") > 25:
			chr.set_meta("boredom_threshold", randi_range(15, 25))
		if %Completed.mesh != puzzle_meshes[0]: _set_keyframes(chr.get_meta("boredom_threshold"))
	elif initiating_chr == chr:
		chr.set_meta("boredom", chr.get_meta("boredom", 0) + 1)
		
		if chr.get_meta("boredom") > chr.get_meta("boredom_threshold"):
			is_set_up = false
			action.subaction_finished.emit()
			return
	elif initiating_chr != chr and not initiating_chr.has_meta("doing_puzzle"):
		action.subaction_finished.emit()
		return
	
	# update mask
	var boredom: int = initiating_chr.get_meta("boredom")
	if boredom in keyframes:
		_set_puzzle_mesh(keyframes.find(boredom) + 1)
		if not boredom > keyframes.back():
			$Puzzle/Place.play()
			if boredom == keyframes.back(): $Puzzle/Yay.play()
	
	# effects
	var is_together: bool = other.has_meta("doing_puzzle")
	if is_together and randi() % 5 == 1 or randi() % 20 == 1: chr.personality.happiness += 1
	if is_together and randi() % 20 == 1: Chuuni.relationship += 1
	get_tree().create_timer(1, false).timeout.connect(_do_puzzle.bind(action), CONNECT_ONE_SHOT)

func _finish_puzzle(action: Action) -> void:
	var chr := action.character
	var other := Chuuni.get_other_character(chr)
	
	var memory_context = ""
	if reclusive: memory_context = "reclusive"
	elif chr.get_sentiment_toward(self) > 3: memory_context = "fan"
	
	if chr.is_socialising:
		print("creating memory <3")
		chr.create_memory(other, ["joy"])
		Chuuni.tally_winner(chr)
	chr.create_memory(self, ["joy"], memory_context)
	
	for meta in ["boredom", "boredom_threshold", "doing_puzzle"]:
		chr.remove_meta(meta)
	
	chr.is_socialising = false
	if chr.has_meta("social_decay"):
		chr.personality.social_decay = chr.get_meta("social_decay")
		chr.remove_meta("social_decay")
	
	chr.model.look_at_target = Vector3.ZERO
	chr.model.stand()
	chr.state_machine.state = StateMachine.State.IDLE
	action.subaction_finished.emit()

func _reset_puzzle(action: Action) -> void:
	await get_tree().create_timer(0.2, false).timeout
	$Puzzle.hide()
	$Puzzle.position = Vector3.ZERO
	$Puzzle.rotation = Vector3.ZERO
	box.show()
	box.get_node("Sounds/Grab").play()
	action.subaction_finished.emit()
