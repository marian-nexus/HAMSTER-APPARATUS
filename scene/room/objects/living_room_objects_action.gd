extends Node
@onready var objects: Node3D = get_node("../../MainRoom/Objects")
var _plants_being_watered := false

const PHOTOSYNTHESIS_COOLDOWN = 60 * 10
var cooldowns: Dictionary[Character, SceneTreeTimer] = {}
var using_plants: Dictionary[Character, Plant] = {}

func _ready() -> void:
	GlobalActions.register_action(water_plants, [objects.get_node("Plants")],
		["happiness", "energy", "social"], _water_plants_req, "water plants")
	GlobalActions.register_action(photosynthesise, [], ["happiness", "energy", "social", "hunger"],
		_photosynthesis_req, "photosynthesise")
	
	$MoodDecayTimer.timeout.connect(_dead_plants_mood_decay)

#region global
func _get_item_position(item: Node3D) -> Vector3:
	var parent = item.get_meta("original_parent", item.get_parent())
	var position := Chuuni.get_nearest_lr_position(parent)
	position.z += 1.3
	return position

func _grab_tv_item(action: Action, item: Node3D) -> void:
	await GlobalActions.walk_to(action.character, _get_item_position(item), true)
	action.character.model.look_at_target = item.get_parent().global_position
	await get_tree().create_timer(0.5, false).timeout
	if not item.has_meta("original_parent"): item.set_meta("original_parent", item.get_parent())
	Chuuni.give_character_item(action.character, item)
	action.character.model.look_at_target = Vector3.ZERO
	
	if item.has_node("Sounds/Grab"): item.get_node("Sounds/Grab").play()
	
	action.subaction_finished.emit()

func _put_away_tv_item(action: Action, item: Node3D) -> void:
	action.zone = Chuuni.get_zone(item.get_meta("original_parent"))
	await GlobalActions.walk_to(action.character, _get_item_position(item), true)
	action.character.model.look_at_target = item.get_meta("original_parent").global_position
	await get_tree().create_timer(0.3, false).timeout
	item.reparent(item.get_meta("original_parent"), false)
	await get_tree().create_timer(0.2, false).timeout
	if item.has_node("Sounds/Grab"): item.get_node("Sounds/Grab").play()
	action.character.model.look_at_target = Vector3.ZERO
	action.subaction_finished.emit()
#endregion
#region plants
func water_plants(character: Character) -> Action:
	var subactions: Array[Callable] = [GlobalActions._grab_item.bind("watering_can"),
	_water_all_plants, GlobalActions._put_away_item]
	return Chuuni.create_action(character, subactions, "water plants")

func _water_plants_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	if GlobalActions.is_queued_or_doing(Chuuni.get_other_character(character), "water plants"):
		req.possible = false; return req
	req.mood = character.personality.happiness >= 30
	req.personality = character.personality.melancholy >= 10
	if req.personality: req.mood = true
	if not req.personality and _get_plants_to_water(character).size() > 2:
		req.personality = character.personality.anger < 10
	req.possible = not _get_plants_to_water(character).is_empty()
	
	if character.personality.melancholy >= 10:
		req.applicable_stat = "happiness"
		req.char_personality = character.personality
	
	return req

func _get_plants_to_water(character: Character, zone_name := "MainArea") -> Array[Plant]:
	# unobservant characters will only water plants that are obviously wilting
	var observant := character.personality.melancholy >= 10
	var plants: Array
	var to_water: Array[Plant] = []
	if zone_name == "MainArea": plants = objects.get_node("Plants").get_children()
	for plant: Plant in plants:
		if plant.health == Plant.PlantHealth.WILTING: to_water.append(plant)
		elif plant.health == Plant.PlantHealth.NEEDS_WATER and observant: to_water.append(plant)
	return to_water

func _water_all_plants(action: Action) -> void:
	var to_water := _get_plants_to_water(action.character)
	# the plants could hypothetically die in the half second it takes to equip the watering can so...
	if to_water.is_empty(): action.subaction_finished.emit(); return
	
	_plants_being_watered = true
	var personality := action.character.personality
	var plants_watered := 0
	var gave_up := false
	var interrupted := false
	var wilting_amount := 0
	var watering_can: WateringCan = action.character.model.get_node("Hand").get_child(0)
	
	var _plant_is_dead := func(plant: Plant):
		if plant.health == Plant.PlantHealth.DEAD: # it fucking died before she could get to it
			print("plant fucking died in the middle of watering")
			action.character.create_memory(objects.get_node("Plants"), ["fear"], "water")
		return plant.health == Plant.PlantHealth.DEAD
	
	for plant: Plant in to_water:
		# stop action if the other character wants to talk, then start it again ^_^
		if action.character.state_machine.is_being_accosted():
			interrupted = true
			action.character.state_machine.queue_action(water_plants(action.character))
			break
		
		if _plant_is_dead.call(plant): continue
		elif plant.health == Plant.PlantHealth.WILTING: wilting_amount += 1
		
		if personality.happiness <= 15 and personality.melancholy < 10: # chance to give up early
			if plants_watered > 0 and randi() % 4 == 1: gave_up = true; break
		elif personality.energy <= 10: gave_up = true; break
		
		await GlobalActions.walk_to(action.character, plant.get_node("Front").global_position, true)
		if _plant_is_dead.call(plant): continue
		plant.is_being_watered = true
		watering_can.pour()
		if personality.melancholy >= 10: action.character.is_socialising = true
		action.character.state_machine.state = StateMachine.State.BUSY
		var watering_time: float = randi_range(250, 450) * 0.01
		get_tree().create_tween().tween_property(personality, "happiness", personality.happiness + 3, watering_time)
		await get_tree().create_timer(watering_time / 2, false).timeout
		plants_watered += 1
		plant.health -= 1
		await get_tree().create_timer(watering_time / 2, false).timeout
		plant.is_being_watered = false
		action.character.is_socialising = false
	
	if wilting_amount >= plants_watered / 2 and plants_watered > 2: # plants were dying
		print(action.character.npc_name + " is mad nobody has been caring for these damn plants")
		action.character.create_memory(Chuuni.get_other_character(action.character), ["resentment"], "water")
		Chuuni.relationship -= 2
	
	if not gave_up and not interrupted:
		print(action.character.npc_name + " finished watering the plants <3")
		if personality.melancholy >= 10:
			action.character.create_memory(objects.get_node("Plants"), ["joy"], "water")
		else:
			action.character.create_memory(objects.get_node("Plants"), ["boredom"], "water")
	elif not interrupted: # fuck these fucking plants making me feel like a failure
		action.character.create_memory(objects.get_node("Plants"), ["resentment"], "water")
	
	_plants_being_watered = false
	action.character.is_socialising = false
	action.subaction_finished.emit()

func _dead_plants_mood_decay() -> void:
	for chr: Character in Chuuni.characters.values():
		if not chr.current_zone.objects.has_node("Plants"): continue
		var dead_plants := 0
		for plant: Plant in chr.current_zone.objects.get_node("Plants").get_children():
			if plant.health == Plant.PlantHealth.DEAD: dead_plants += 1
		
		var decay := 1 if chr.personality.melancholy < 10 else 2
		chr.personality.happiness -= decay * dead_plants
		if decay * dead_plants > 0:
			print(chr.npc_name + "'s mood went down by " + str(decay * dead_plants) + " because of the dead plants.")
#endregion
#region photosynthesis
func photosynthesise(character: Character) -> Action:
	var subactions: Array[Callable] = [_navigate_to_plant, _radioactive_glow]
	return Chuuni.create_action(character, subactions, "photosynthesise")

func _photosynthesis_req(character: Character) -> ActionReq:
	var req := ActionReq.new()
	req.possible = character.personality.melancholy >= 18
	var healthy_plant := false
	for plant: Plant in _get_all_plants():
		if plant.health == Plant.PlantHealth.HEALTHY:
			healthy_plant = true; break
	
	var needs_critically_low := 0
	for need in character.personality.health_traits:
		if character.personality[need] <= 10: needs_critically_low += 1
	
	req.possible = req.possible and healthy_plant and needs_critically_low >= 2
	if not req.possible: return req
	
	if character in cooldowns.keys():
		req.possible = cooldowns[character].time_left == 0
	
	return req

func _navigate_to_plant(action: Action) -> void:
	var plant := _get_healthy_plant()
	if not plant:
		action.cancel()
		return
	plant.wilting_enabled = false
	plant.wilt_progress = 0
	using_plants[action.character] = plant
	action.zone = Chuuni.get_zone(plant.get_parent())
	await GlobalActions.walk_to(action.character, plant.get_node("Front").global_position, true)
	action.subaction_finished.emit()

func _radioactive_glow(action: Action) -> void:
	var chr := action.character
	var personality := chr.personality
	var glow: OmniLight3D = chr.model.get_node("Glow")
	glow.omni_range = 0
	glow.show()
	get_tree().create_tween().tween_property(glow, "omni_range", 5, 5)
	chr.state_machine.state = StateMachine.State.PHOTOSYNTHESIS
	
	for need in personality.health_traits:
		if not need + "_decay" in personality: continue
		chr.set_meta(need + "_decay_ps", personality[need + "_decay"])
		personality[need + "_decay"] = 0
	
	chr.is_socialising = true
	var satisfied_stats := []
	for i in range(100):
		for need in personality.health_traits:
			personality[need] += 1
			var constraint: int = personality.stat_constraints[0]
			if personality[need] >= constraint and not need in satisfied_stats:
				satisfied_stats.append(need)
				print(satisfied_stats)
		
		if satisfied_stats.size() == personality.health_traits.size(): break
		await get_tree().create_timer(0.3, false).timeout
	
	for need in personality.health_traits:
		if not chr.has_meta(need + "_decay_ps"): continue
		personality[need + "_decay"] = chr.get_meta(need + "_decay_ps") * 1.5
	
	chr.is_socialising = false
	
	var glow_2: OmniLight3D = chr.model.get_node("GlowAmbient")
	var light_properties := ["omni_range", "light_energy", "light_specular", "shadow_enabled"]
	var light_tween := get_tree().create_tween().set_parallel(true)
	for prop in light_properties:
		var end_prop = glow_2[prop]
		glow_2[prop] = glow[prop]
		light_tween.tween_property(glow_2, prop, end_prop, 8)
	glow.hide()
	glow_2.show()
	
	get_tree().create_timer(60, false).timeout.connect(_reset_photosynthesis_effects.bind(chr))
	cooldowns[chr] = get_tree().create_timer(PHOTOSYNTHESIS_COOLDOWN, false)
	
	chr.state_machine.state = StateMachine.State.IDLE
	using_plants[chr].wilting_enabled = true
	using_plants.erase(chr)
	chr.create_memory(objects.get_node("Plants"), ["respect", "satisfaction", "joy"], "photo")
	action.subaction_finished.emit()

func _reset_photosynthesis_effects(character: Character) -> void:
	var personality := character.personality
	var glow: OmniLight3D = character.model.get_node("GlowAmbient")
	get_tree().create_tween().tween_property(glow, "omni_range", 0, 5)
	
	for need in personality.health_traits:
		if not character.has_meta(need + "_decay_ps"): continue
		personality[need + "_decay"] = character.get_meta(need + "_decay_ps")
		character.remove_meta(need + "_decay_ps")
	
	get_tree().create_timer(5, false).timeout.connect(func(): glow.hide())

func _get_healthy_plant() -> Plant:
	var plant: Plant
	for _plant: Plant in _get_all_plants():
		if _plant.health == Plant.PlantHealth.HEALTHY and not _plant in using_plants.values():
			plant = _plant
			break
	return plant

# TODO: give melancholic characters their own plant and count it here
func _get_all_plants() -> Array[Plant]:
	var plants: Array[Plant] = []
	for plant: Plant in objects.get_node("Plants").get_children():
		plants.append(plant)
	return plants
#endregion
