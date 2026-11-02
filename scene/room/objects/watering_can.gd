class_name WateringCan extends Node3D

func _ready() -> void:
	$Grab.play()

func pour() -> void:
	$Sound.play()
