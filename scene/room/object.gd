class_name RadioObject extends StaticBody3D
@export var radio_wave: RadioWave

func get_stat_effects() -> Dictionary:
	if not radio_wave: radio_wave = RadioWave.new()
	var effects := {}
	var personality_stats := []
	for prop in Personality.new().get_property_list():
		if prop.usage == 4096: personality_stats.append(prop.name)
	for stat in radio_wave.get_property_list():
		if stat.name in personality_stats:
			effects[stat.name] = radio_wave[stat.name]
	return effects
