extends Node3D
const RAY_LENGTH := 1000.0
const DISHES_MOOD_COOLDOWN := 30
const LONER_TIMER_LENGTH := 60
@export var current_camera: Camera3D:
	set(value):
		current_camera = value
		for cam: Camera3D in $Cameras.get_children():
			cam.current = cam == value
var dishes_timer := Timer.new()
var loner_timers: Dictionary[Character, SceneTreeTimer] = {}

var current_room := "":
	set(value):
		if current_room == value: return
		current_room = value
		room_changed.emit(value)
var cameras := {}
@onready var all_cameras := $Cameras.get_children()
var change_camera_cooldown := 3

signal room_changed(room_name: String)

func get_zones() -> Dictionary[String, Zone]:
	var zones := {}
	for zone: Zone in $Zones.get_children():
		zones[zone.name.to_snake_case()] = zone
	return zones

func _ready() -> void:
	MainUI.get_node("FadeIn").show()
	for child in $NPCs.get_children(): child.free()
	Chuuni.set_up_npcs()
	Chuuni.exiting_check_in.connect(_leave_check_in_menu)
	
	for zone: Area3D in $Zones.get_children():
		zone.body_entered.connect(func(body: Node3D):
			if not "character" in body: return
			_set_zone(body.character, zone)
		)
	
	for child: Camera3D in $Cameras.get_children():
		if current_camera == child: change_camera(child)
		else: child.current = false
	
	for cam: Camera3D in $Cameras.get_children():
		var room_name := cam.name.substr(0, cam.name.length() - 1)
		if not room_name in cameras.keys(): cameras[room_name] = [cam]
		else: cameras[room_name].append(cam)
	current_room = cameras.keys()[0]
	
	MainUI.next_room.connect(_cycle_room.bind(1))
	MainUI.prev_room.connect(_cycle_room.bind(-1))
	MainUI.next_camera.connect(_cycle_camera.bind(1))
	MainUI.prev_camera.connect(_cycle_camera.bind(-1))
	MainUI.start_following.connect(_start_following)
	MainUI.stop_following.connect(_stop_following)
	
	dishes_timer.wait_time = DISHES_MOOD_COOLDOWN
	dishes_timer.timeout.connect(_dishes_mood_decay)
	dishes_timer.autostart = true
	add_child(dishes_timer)
	
	for plant: Plant in $MainRoom/Objects/Plants.get_children():
		plant.unpack_leaves()
		await plant.finished_unpacking
	MainUI.fade_in()

func _start_following(character: Character) -> void:
	_check_nearest_camera(character, false)
	character.zone_changed.connect(func(_zone): _check_nearest_camera(character))

func _check_nearest_camera(character: Character, one_off := true) -> void:
	if MainUI.following_character != character: return
	if not one_off:
		get_tree().create_timer(change_camera_cooldown, false).timeout.connect(
			_check_nearest_camera.bind(character, false))
	
	var room_cameras: Array = cameras[character.current_zone.name]
	var direction_scene := preload("res://scene/npc/direction.tscn")
	var direction: Node3D
	if not character.has_meta("direction"):
		direction = direction_scene.instantiate()
		add_child(direction)
		character.set_meta("direction", direction)
	else: direction = character.get_meta("direction")
	direction.global_position = character.model.get_node("MidPoint").global_position
	direction.global_rotation = character.model.global_rotation
	
	var results := await _get_raycast_results(character, room_cameras)
	
	if current_camera in results.hits_front: return
	
	if current_camera in results.hits_back and not results.hits_front.is_empty():
		var distance: float = results.hits_front[0].global_position.distance_to(character.model.global_position)
		if distance < 5 and character.current_zone.name == "MainArea": return
	
	if not results.hits_front.is_empty():
		change_camera(_get_closest_camera(results.hits_front, character))
	elif not results.hits_back.is_empty():
		change_camera(_get_closest_camera(results.hits_back, character))

func _get_raycast_results(character: Character, room: Array) -> Dictionary:
	await get_tree().create_timer(0.01, false).timeout
	var hits := {"hits_front": [], "hits_back": [], "no_hits": []}
	
	for cam: Camera3D in room:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			cam.global_transform.origin, character.model.get_node("MidPoint").global_position)
		query.exclude = [character.model.get_rid()]
		
		var results := space.intersect_ray(query)
		if results:
			if $CameraAreas.has_node(str(cam.name)):
				var area: Area3D = $CameraAreas.get_node(str(cam.name))
				if not area.overlaps_body(character.model): continue
			
			match results.collider.name:
				"Front": hits.hits_front.append(cam)
				"Back": hits.hits_back.append(cam)
				_: hits.no_hits.append(cam)
	
	var all = hits.hits_front.duplicate()
	all.append_array(hits.hits_back); all.append_array(hits.no_hits)
	for cam: Camera3D in all:
		var distance: float = cam.global_position.distance_to(character.model.global_position)
		if distance < 4.8 and "MainArea" in cam.name and not "2" in cam.name:
			for cat in hits.values(): if cam in cat: cat.erase(cam)
	
	return hits

func _get_closest_camera(array: Array, chr: Character) -> Camera3D:
	var arr := array.duplicate()
	arr.sort_custom(func(cam_1, cam_2):
		return cam_1.global_position.distance_to(chr.model.global_position) < \
		cam_2.global_position.distance_to(chr.model.global_position))
	return arr[0]

func _stop_following(character: Character) -> void:
	if MainUI.following_character == character:
		MainUI.following_character = null
	for conn in character.zone_changed.get_connections():
		if "anonymous" in str(conn.callable):
			character.zone_changed.disconnect(conn.callable)
	if character.has_meta("direction"):
		character.get_meta("direction").queue_free()
		character.remove_meta("direction")

func _leave_check_in_menu() -> void:
	current_camera.make_current()

func _random_debug_properties() -> void:
	var characters: Array[Character] = Chuuni.characters.values()
	characters[0].state_machine.queue_action(GlobalActions.lay_on_ground(characters[0]))
	
	if false: # testing the "get caught drawing on others wall" scenario
		characters[0].personality.activeness = -15
		characters[1].personality.activeness = -15
		characters[0].personality.happiness = 10
		characters[0].personality.anger = 12
		characters[1].personality.anger = -10
		for i in range(6): characters[0].create_memory(characters[1], ["resentment"])
		for i in range(6): characters[1].create_memory(characters[0], ["resentment"])
		Chuuni.relationship = -20
		for room in [$MainRoom, characters[0].bedroom]:
			for wall: WallSpace in room.get_node("Objects/WallSpaces").get_children():
				for i in range(wall.DRAWING_CAPACITY): wall.add_drawing()
		
		characters[0].state_machine.queue_action(
			Chuuni.create_action(characters[0], [func(action: Action):
				while characters[1].state_machine.current_action.action_name != "wait :3":
					await characters[1].state_machine.action_started
				action.subaction_finished.emit()
				], "!!!")
		)
		characters[0].state_machine.queue_action($Scripts/WallActions.draw_on_wall(characters[0]))
		characters[1].state_machine.queue_action(
			Chuuni.create_action(characters[1], [func(action: Action): 
				await characters[0].state_machine.action_started
				await get_tree().create_timer(10, false).timeout
				action.subaction_finished.emit()
				], "wait :3")
		)
		characters[1].state_machine.queue_action($Scripts/BedroomActions.sleep(characters[1]))
		characters[1].personality.energy = 20

func _on_character_changed_zone(character: Character) -> void:
	if character.current_zone == Chuuni.get_zone(character.bedroom):
		_start_loner_timer(character)
		$Scripts/WallActions.vandalism_mood_drain(character)
	elif character.current_zone.name == "MainArea":
		if character in loner_timers.keys() and loner_timers[character]:
			print("removed " + character.npc_name + "'s loner timer")
			loner_timers[character].disconnect("timeout", _loner_timer_expired)
			loner_timers[character] = null

func _start_loner_timer(character: Character) -> void:
	print("started " + character.npc_name + "'s loner timer")
	var timer := get_tree().create_timer(LONER_TIMER_LENGTH, false)
	timer.timeout.connect(_loner_timer_expired.bind(character))
	loner_timers[character] = timer

func _loner_timer_expired(character: Character) -> void:
	print(character.npc_name + "'s loner timer expired")
	loner_timers[character] = null
	var other := Chuuni.get_other_character(character)
	
	if other.state_machine.state != StateMachine.State.SLEEPING:
		var kitchen_dishes_count := $MainRoom/Objects/Kitchen/DumpingGround/Dishes.get_child_count()
		var plants_health = _get_main_plants_health()
		if kitchen_dishes_count >= 5 or plants_health.wilting >= plants_health.total / 2 or \
		other.personality.social <= 15:
			print(other.npc_name + " resents " + character.npc_name + " for staying in her room so long >:(")
			other.personality.happiness -= 5
			other.personality.social -= 5
			other.create_memory(character, ["resentment"])
	
	_start_loner_timer(character)

func _get_main_plants_health() -> Dictionary:
	var health := {}
	for category in ["total", "healthy", "needs_water", "wilting", "dead"]: health[category] = 0
	for plant: Plant in $MainRoom/Objects/Plants.get_children():
		health[Plant.PlantHealth.find_key(plant.health).to_lower()] += 1
		if plant.health != Plant.PlantHealth.DEAD: health.total += 1 # dead plants don't factor into total
	return health

func _cycle_camera(direction: int) -> void:
	if get_tree().paused: return
	MainUI.play_sound("navigate")
	if Chuuni.settings.lock_room:
		change_camera(
			cameras[current_room][_cycle_array(cameras[current_room],
			current_camera, direction)], true)
	else:
		change_camera(all_cameras[_cycle_array(all_cameras, current_camera, direction)], true)

func _cycle_array(array: Array, anchor, direction: int) -> int:
	var index: int = array.find(anchor) + direction
	if index < 0: index = array.size() - 1
	elif index >= array.size(): index = 0
	return index

func _cycle_room(direction: int) -> void:
	if get_tree().paused: return
	MainUI.play_sound("navigate")
	var next_room: String = cameras.keys()[_cycle_array(cameras.keys(), current_room, direction)]
	change_camera(cameras[next_room][0])

func change_camera(camera: Camera3D, player_initiated := false) -> void:
	if player_initiated and MainUI.following_character:
		MainUI.stop_following.emit(MainUI.following_character)
	current_camera = camera
	current_room = camera.name.substr(0, camera.name.length() - 1)
	MainUI.camera_changed.emit(current_camera)

func _dishes_mood_decay() -> void:
	for character: Character in Chuuni.characters.values():
		var decay := _get_dishes_in_dumping_ground(character.current_zone)
		if decay <= 0: continue
		if character.state_machine.state == StateMachine.State.SLEEPING: continue
		character.personality.happiness -= decay
		print(character.npc_name + "'s mood went down by " + str(decay))

func _get_dishes_in_dumping_ground(zone: Zone) -> int:
	var dumping_ground
	if zone.objects.has_node("DumpingGround"):
		dumping_ground = zone.objects.get_node("DumpingGround/Dishes")
	else: dumping_ground = %Objects/Kitchen/DumpingGround.get_node("Dishes")
	return dumping_ground.get_child_count()

func _set_zone(character: Character, zone: Area3D) -> void:
	character.current_zone = zone
	character.zone_changed.emit(zone)
	_on_character_changed_zone(character)
	
	# slightly tank mood when entering room with dirty dishes
	# (unless the full decay is about to happen)
	if dishes_timer.time_left <= 8: return
	character.personality.happiness -= _get_dishes_in_dumping_ground(character.current_zone) / 2
	if _get_dishes_in_dumping_ground(character.current_zone) / 2 > 0:
		print(character.npc_name + "'s mood went down from entering a room with dirty dishes")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("click") and not event.is_action_pressed("rightclick"): return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_length := 1000
	var from = current_camera.project_ray_origin(mouse_pos)
	var to = from + current_camera.project_ray_normal(mouse_pos) * ray_length
	var space = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(ray_query)
	if "collider" in result and not result.collider.input_ray_pickable: result = {}
	
	if event.is_action_pressed("rightclick"):
		if result.is_empty(): MainUI.debug_raycast.emit()
		else: MainUI.debug_raycast.emit(result.collider)
