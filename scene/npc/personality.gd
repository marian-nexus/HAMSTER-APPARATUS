class_name Personality extends Node
var anger: int = 0
var melancholy: int = 0
var activeness: int = 0
var whimsy: int = 0
var fear: int = 0

var energy: int = stat_constraints[0]:
	set(value):
		energy = _clamp_stat(value, energy_constraint)
		health_stat_changed.emit("energy", energy)
var happiness: int = stat_constraints[0]:
	set(value):
		happiness = _clamp_stat(value, happiness_constraint)
		health_stat_changed.emit("happiness", happiness)
var social: int = stat_constraints[0]:
	set(value):
		social = _clamp_stat(value, stat_constraints[0])
		health_stat_changed.emit("social", social)
var hunger: int = stat_constraints[0]:
	set(value):
		hunger = _clamp_stat(value, stat_constraints[0])
		health_stat_changed.emit("hunger", hunger)

const personality_traits := ["melancholy", "anger", "whimsy"]
const health_traits := ["energy", "happiness", "social", "hunger"]
const reactive_traits := ["fear"]
const disagreement_threshold := 20
const power_threshold := 5
const stat_constraints := [50, 100]

var randomised := false
var happiness_constraint := stat_constraints[0]
var energy_constraint := stat_constraints[0]
var social_decay := 8
var hunger_decay := 5
var energy_decay := 8
var happiness_decay := 8
var hunger_threshold := 15
var eat_time := 1

signal health_stat_changed(stat: String, value: int)

func randomise() -> void:
	randomised = true
	for stat in personality_traits:
		if self[stat] == 0: self[stat] = randi_range(-3, 13)
	for stat in health_traits:
		var constraint = stat_constraints[0]
		if stat + "_constraint" in self: constraint = self[stat + "_constraint"]
		#if stat == "social": self[stat] = randi_range(constraint - 25, constraint - 10)
		self[stat] = randi_range(constraint / 2 + 5, constraint)

func _clamp_stat(stat: int, maximum: int) -> int:
	var result := stat
	if result < 0: result = 0
	if result > maximum: result = maximum
	return result
