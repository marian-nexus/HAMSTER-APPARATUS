extends Node

var rooms: Array[String] = []
var volume := [0, -7]
var current_room := "MainArea"

const RAND_SOUND_INTERVAL := [20, 200]

func _ready() -> void:
	get_node("../..").room_changed.connect(_room_changed)
	_start_sound_timer()
	
	for zone: Zone in get_node("../../Zones").get_children():
		rooms.append(zone.name)
		if zone.door: zone.door.door_triggering.connect(_door)

func _door(door: Door) -> void:
	var bus := current_room
	if current_room != "MainArea" and door.zone.name != current_room: bus = "MainArea"
	for sound: AudioStreamPlayer3D in door.get_node("Sounds").get_children(): sound.bus = bus

func _room_changed(room_name: String) -> void:
	current_room = room_name
	for room in rooms:
		var bus := AudioServer.get_bus_index(room)
		for i in AudioServer.get_bus_effect_count(bus):
			AudioServer.set_bus_effect_enabled(bus, i, room != room_name)
		AudioServer.set_bus_volume_db(bus, volume[int(room != room_name)])

func _play_random_sound() -> void:
	var all := get_node("../../RandomCreepySounds").get_children()
	var player: AudioStreamPlayer3D = all[randi() % all.size()]
	player.play()
	_start_sound_timer()

func _start_sound_timer() -> void:
	var interval := randi_range(RAND_SOUND_INTERVAL[0], RAND_SOUND_INTERVAL[1])
	get_tree().create_timer(interval, false).timeout.connect(_play_random_sound)
