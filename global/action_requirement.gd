class_name ActionReq extends Node
var mood = true
var personality = true
var relationship = true
var context = true
var possible = true
var applicable_stat: String
var char_personality: Personality

func all_false() -> void:
	mood = false
	personality = false
	relationship = false
	context = false

func get_score() -> int:
	var score := 0
	for req in ["mood", "personality", "relationship", "context"]:
		score += _bool_to_int(self[req])
	
	if applicable_stat:
		var extra_points := 0
		for i in [20, 15, 10, 5, 3, 2, 1]:
			if char_personality[applicable_stat] < i: extra_points += 1
		score += extra_points
	return score

func _bool_to_int(value: bool) -> int:
	if value == false: return -1
	else: return 1
