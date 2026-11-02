class_name Action extends Node
@export var subactions: Array[Callable] = []
var current_subaction: Callable
var response_callable: Callable
var is_running := false
var is_cancelled := false
var action_name: String
var character: Character
var zone: Area3D
signal subaction_finished
signal cancelled

func _init() -> void:
	subaction_finished.connect(_on_subaction_finished)

func set_subactions(array: Array[Callable]) -> void:
	for callable: Callable in array: subactions.append(callable)

func start() -> void:
	is_running = true
	_start_next_sub_action()

func cancel() -> void:
	is_cancelled = true
	cancelled.emit()
	_finish()

func _finish() -> void:
	is_running = false
	character.state_machine.action_finished.emit()

func _start_next_sub_action() -> void:
	if is_cancelled: return
	if subactions.is_empty(): _finish(); return
	current_subaction = subactions.pop_at(0)
	current_subaction.call(self)

func _on_subaction_finished() -> void:
	#print(character.npc_name + ": subaction finished " + str(current_subaction))
	if cancelled.has_connections():
		for connection in cancelled.get_connections():
			cancelled.disconnect(connection.callable)
	_start_next_sub_action()
