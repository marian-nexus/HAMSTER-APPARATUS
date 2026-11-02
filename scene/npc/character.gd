class_name Character extends Node
var npc_name: String
var serial_number: String
var birthday: String
var age: String
var model: CharacterModel
var state_machine: StateMachine
var personality := Personality.new()
var current_zone: Zone
var bedroom: Node3D
var memories: Array[Memory] = []
var sentiments := {}
var sleep_interrupted := false
var is_socialising := false:
	set(value):
		is_socialising = value
		if is_socialising: started_socialising.emit()
		# increases social stat every second while socialising (handled in npc.gd)

const MEMORY_CAP := 100 # completely arbitrary

signal eat_in_bed
signal started_socialising
signal zone_changed

func _init() -> void:
	_generate_birthday()
	_generate_serial_number()

func _generate_serial_number() -> void:
	var ran_characters := "1234567890QWERTYUIOPASDFGHJKLZXCVBNM?"
	var num := ""
	for i in range(12):
		num += ran_characters[randi() % ran_characters.length()]
	serial_number = num

func _generate_birthday() -> void:
	var has_31_days := [1, 3, 5, 7, 8, 10, 12]
	var month := randi() % 12 + 1
	var max_day := 30
	if month in has_31_days: max_day = 31
	elif month == 2: max_day = 28
	var day := randi() % max_day + 1
	
	var day_string := str(day)
	if day < 10: day_string = "0" + day_string
	var bday_string := str(month) + "/" + day_string
	if month < 10: bday_string = "0" + bday_string
	birthday = bday_string
	
	var age_options := [" days", " months", " years"]
	var age_1: String = age_options[randi() % age_options.size()]
	var age_max := [30, 8, 2]
	var age_2 := str(randi_range(1, age_max[age_options.find(age_1)]))
	if age_2 == "1": age_1 = age_1.substr(0, age_1.length() - 1)
	age = age_2 + age_1

func get_feelings_toward(target: Variant) -> Dictionary:
	var feelings: Dictionary[String, int] = {}
	# populate the dictionary with default values to avoid null references
	for string in Memory.ass_sen.keys(): feelings[string] = 0
	
	for memory: Memory in memories:
		if memory.target != target: continue
		for feeling: String in memory.associations:
			feelings[feeling] += 1
	return feelings

func get_sentiment_toward(target: Variant) -> int:
	var sentiment := 0
	for memory: Memory in memories:
		if memory.target != target: continue
		sentiment += memory.sentiment
	return sentiment

func create_memory(target: Variant, associations: Array, context := "") -> void:
	var memory := Memory.new()
	memory.target = target
	memory.context = context
	memory.associations = associations
	memories.append(memory)
	if memories.size() > MEMORY_CAP: memories.remove_at(0)
	
	if "fear" in memory.associations:
		personality.fear += 1
		personality.happiness_constraint -= 2
		if personality.happiness > personality.happiness_constraint:
			personality.happiness = personality.happiness_constraint
	personality.happiness += memory.sentiment
	
	for sen in memory.ass_sen.keys():
		if not sen in sentiments: sentiments[sen] = 0
		if sen in associations: sentiments[sen] += 1
	
	_process_associations(associations)

func get_memory_objects() -> Array:
	var objects := []
	for memory: Memory in memories:
		if not memory.target in objects: objects.append(memory.target)
	objects.sort_custom(_sort_by_most_memories)
	return objects

func get_memories_with_context(target, context: String) -> Array[Memory]:
	var mem: Array[Memory] = []
	for memory in memories:
		if memory.target != target: continue
		if memory.context != context: continue
		mem.append(memory)
	return mem

func _compile_sentiments(mem_list: Array[Memory]) -> Dictionary:
	var sents := {}
	for ass in Memory.new().ass_sen.keys(): sents[ass] = 0
	for memory: Memory in mem_list:
		for ass in memory.associations: sents[ass] += 1
	return sents

func _get_highest_associations(dict: Dictionary) -> Array:
	var keys: Array = dict.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return dict[x] > dict[y])
	
	for key in dict.keys():
		if dict[key] == 0: keys.erase(key)
	
	return keys

func get_memory_texts(target) -> Array:
	var target_name := str(target.name).to_snake_case()
	if target is Character: target_name = "other"
	if not target_name in Chuuni.memory_text: return []
	
	var text_dict: Dictionary = Chuuni.memory_text[target_name]
	var texts := []
	var sorted_contexts := []
	for memory: Memory in memories:
		if memory.target != target: continue
		if memory.context and not memory.context in sorted_contexts:
			sorted_contexts.append(memory.context)
			if not memory.context in text_dict: continue
			if text_dict[memory.context] is String:
				var text: String = text_dict[memory.context]
				if "%" in text: text = text % Chuuni.get_other_character(self).npc_name
				texts.append(text)
				continue
			
			# disgusting vv
			# this gets an array with the names of memory associations
			# sorted by most common to least common, within the provided context
			# so we can assign the most relevant text. yes. it works splendid.
			var associations := _get_highest_associations(
				_compile_sentiments(get_memories_with_context(target, memory.context)))
			for association in associations:
				if association in text_dict[memory.context]:
					var text: String = text_dict[memory.context][association]
					if "%" in text: text = text % Chuuni.get_other_character(self).npc_name
					texts.append(text)
					break
			
	return texts

func _get_memory_count(object) -> int:
	var count := 0
	for memory: Memory in memories:
		if memory.target == object: count += 1
	return count

func _sort_by_most_memories(object1, object2) -> bool:
	return _get_memory_count(object1) > _get_memory_count(object2)

func _process_associations(associations: Array) -> void:
	var changes := {
		"betrayal": ["anger", 1, "whimsy"], "fear": ["whimsy", -1, "anger"],
		"joy": ["whimsy", 1, "melancholy"], "respect": ["melancholy", -1, "whimsy"],
		"boredom": ["melancholy", 1, "whimsy"], "satisfaction": ["anger", -1, "melancholy"],
		"resentment": ["melancholy", 1, "anger"]
	}
	
	for association: String in associations:
		if sentiments[association] % 3 == 0:
			var change = changes[association]
			var maximum := 25
			var minimum := -15
			personality[change[0]] += change[1] * 2
			personality[change[2]] -= change[1]
			print("adding ", change[1] * 2, " to ", change[0], " for ", npc_name, " (adding ",
				change[1] * -1, " to ", change[2], ")")
			for cat in [change[0], change[2]]:
				if personality[cat] < minimum: personality[cat] = minimum
				elif personality[cat] > maximum: personality[cat] = maximum
