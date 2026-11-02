class_name CharInfoBox extends HBoxContainer

var critical_tint := {
	"progress": Color.from_rgba8(255, 84, 84, 255),
	"under": Color.from_rgba8(166, 80, 80, 255),
	"over": Color.from_rgba8(255, 255, 255, 255)
}
const CRITICAL_LEVEL := 15
const CRITICAL_TWEEN_TIME := 10
var critical_bars := []

var character: Character

func setup(chr: Character) -> void:
	character = chr
	chr.personality.health_stat_changed.connect(_set_progress)
	for stat: String in chr.personality.health_traits:
		var maximum: int = chr.personality.stat_constraints[0]
		if stat + "_constraint" in chr.personality: maximum = chr.personality[stat + "_constraint"]
		_set_max(stat, maximum)
		_set_progress(stat, chr.personality[stat])
	
	if chr == Chuuni.characters.values()[1]:
		$Button.move_to_front()
		for container: MarginContainer in $Stats.get_children():
			container.add_theme_constant_override("margin_left",
			container.get_theme_constant("margin_left") * -1)
			if container == $Stats.get_child(0): container.add_theme_constant_override("margin_left", 100)
		add_theme_constant_override("separation", -70)
	
	%CharacterName.text = character.npc_name + " (click)"
	$Button.mouse_entered.connect(_set_character_name_visible.bind(true))
	$Button.mouse_exited.connect(_set_character_name_visible.bind(false))
	MainUI.get_node("HUD").context_menu_shown.connect(_set_character_name_visible.bind(false))

func _set_character_name_visible(_visible: bool) -> void:
	if MainUI.context_menu_visible and _visible: return
	var tween := get_tree().create_tween().set_trans(Tween.TRANS_BACK).set_parallel()
	var duration := 0.15
	
	if _visible:
		%CharacterName.offset_transform_scale.x = 0.5
		tween.tween_property(%CharacterName, "offset_transform_scale:x", 1, duration)
	else: tween.tween_property(%CharacterName, "offset_transform_scale:x", 0.8, duration)
	tween.tween_property(%CharacterName, "modulate:a", 0 if not _visible else 1, duration)
	%CharacterName.show()

func _set_progress(stat: String, value: int) -> void:
	if not has_node("%" + stat.to_pascal_case()): return
	var bar: TextureProgressBar = get_node("%" + stat.to_pascal_case())
	
	var tween := get_tree().create_tween()
	tween.tween_property(bar, "value", float(value), 1)
	
	if value < CRITICAL_LEVEL and not bar in critical_bars or \
	value > CRITICAL_LEVEL and bar in critical_bars:
		var critical_tween := get_tree().create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD)
		var colours: Dictionary
		if not bar in critical_bars:
			colours = critical_tint; critical_bars.append(bar)
		else:
			colours = critical_tint.duplicate()
			for key in colours.keys(): colours[key] = Color.from_rgba8(255, 255, 255)
			critical_bars.erase(bar)
		
		critical_tween.tween_property(bar, "tint_under", colours.under, CRITICAL_TWEEN_TIME)
		critical_tween.tween_property(bar, "tint_progress", colours.progress, CRITICAL_TWEEN_TIME)
		critical_tween.tween_property(bar, "tint_over", colours.over, CRITICAL_TWEEN_TIME)
	
	bar.tooltip_text = (stat + ": " + str(value) + "/" + str(int(bar.max_value))).to_lower()

func _set_max(stat: String, maximum: int) -> void:
	if not has_node("%" + stat.to_pascal_case()): return
	var bar: TextureProgressBar = get_node("%" + stat.to_pascal_case())
	bar.max_value = maximum
