class_name FoodPlate extends Node3D

var parent: CharacterModel
signal abandoned
signal changed_parent

func _ready() -> void:
	abandoned.connect(_on_abandoned)
	
	if get_node("../..") is CharacterModel:
		$Sounds/Grab.play()
		parent = get_node("../..")
		parent.finished_eating.connect(_on_finished_eating, CONNECT_ONE_SHOT)

func _on_finished_eating() -> void:
	$StrangeGoop.hide()
	$StrangeParticles.emitting = false

func _on_abandoned() -> void:
	$Sounds/Place.play()
	$Particles.amount_ratio = 0
	$Particles.emitting = true
	get_tree().create_tween().tween_property($Particles, "amount_ratio", 1, 5)

func _on_changed_parent() -> void:
	parent.finished_eating.disconnect(_on_finished_eating)
	parent = get_node("../..")
	parent.finished_eating.connect(_on_finished_eating, CONNECT_ONE_SHOT)
