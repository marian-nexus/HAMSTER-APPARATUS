extends Node3D

var tween_time := 30
@onready var material: StandardMaterial3D = $Walls/Floor/MeshInstance3D.get_active_material(0)
@onready var next_pass: StandardMaterial3D = material.next_pass

func _ready() -> void:
	Chuuni.entering_check_in.connect(_enter_check_in)
	Chuuni.exiting_check_in.connect(_leave)
	_loop_tween()

func _loop_tween() -> void:
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel()
	var offset := Vector3()
	var  offset_2 := next_pass.uv1_offset.x - 1
	for a in ["x", "y", "z"]: offset[a] = material.uv1_offset[a] - 1
	tween.tween_property(material, "uv1_offset", offset, tween_time)
	tween.tween_property(next_pass, "uv1_offset", Vector3(offset_2, offset_2, offset_2), tween_time)
	tween.finished.connect(_loop_tween)

func _enter_check_in(character: Character) -> void:
	var bus := AudioServer.get_bus_index("CheckIn")
	AudioServer.set_bus_mute(bus, true)
	get_tree().create_timer(0.01).timeout.connect(AudioServer.set_bus_mute.bind(bus, false))
	var sound_tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel()
	for donut: Donut in $Donuts.find_children("*", "Donut"):
		var sound: AudioStreamPlayer3D = donut.get_node("Blip")
		var sound_volume: float = sound.volume_db
		sound.volume_db = -100
		sound_tween.tween_property(sound, "volume_db", sound_volume, 0.5)
	
	$NPC.character_appearance = character
	$CheckInCamera.make_current()
	$CheckInMusic.play()
	
	PhysicsServer3D.set_active(true)

func _leave() -> void:
	$CheckInMusic.stop()
