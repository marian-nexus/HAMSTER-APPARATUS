class_name Door extends Node3D
@export var zone: Zone

var is_open := false
var in_area: Dictionary[Character, Array] = {}

signal door_triggering(door)

func _ready() -> void:
	if not zone: printerr(name + " door doesn't have a zone attached")
	_setup.call_deferred()

func _setup() -> void:
	%NameText.mesh = %NameText.mesh.duplicate()
	%NameText.mesh.text = get_parent().get_meta("owner", "FUCK")
	
	var mesh: Mesh = %NameText.mesh
	if mesh.get_aabb().size[1] > %NameText.custom_aabb.size[1]:
		%NameText.scale.y = 0.6

func _on_body_entered(body: Node3D) -> void:
	if is_open: return
	var character := _get_body_character(body)
	if not character: return
	var action_zone: Area3D = character.state_machine.current_action.zone
	
	if character in in_area.keys():
		in_area[character].append(body)
		return
	in_area[character] = [body]
	
	var will_open := false
	if character.current_zone != zone and action_zone == zone: will_open = true
	if character.current_zone == zone and action_zone != zone: will_open = true
	
	if will_open:
		door_triggering.emit(self)
		is_open = true
		$AnimationPlayer.play("open", -1, 0.8)
		$Sounds/Open.play()

func _on_body_exited(body: Node3D) -> void:
	var character := _get_body_character(body)
	if character in in_area:
		in_area[character].erase(body)
		if in_area[character].is_empty(): in_area.erase(character)
	if not in_area.is_empty(): return
	
	if is_open:
		door_triggering.emit(self)
		is_open = false
		$AnimationPlayer.play("close", -1, -0.8, true)
		await get_tree().create_timer(0.1, false).timeout
		$Sounds/Close.play()

func _get_body_character(body: Node3D) -> Character:
	if "character" in body: return body.character
	elif "character" in body.get_node("../.."): return body.get_node("../..").character
	return
