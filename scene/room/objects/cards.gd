extends Node3D

func get_taken() -> void:
	$AnimationPlayer.play("get_taken")
	$AnimationPlayer.animation_finished.connect(func(_anim_name):
		await get_tree().create_timer(0.3, false).timeout
		$AnimationPlayer.play("RESET")
		_tween_transparency(0), CONNECT_ONE_SHOT)

func _fade_out() -> void:
	_tween_transparency(1)

func _tween_transparency(transparency: float) -> void:
	var tween := get_tree().create_tween().set_parallel()
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D"):
		tween.tween_property(mesh, "transparency", transparency, 0.3)
