class_name ObjectSentimentsBar extends VBoxContainer

const colours := {
	"positive": Color("cee879"),
	"neutral": Color("cfd1b8ff"),
	"negative": Color("d16666")
}

func _ready() -> void:
	$Label.label_settings = $Label.label_settings.duplicate()

func set_value(association: String, value: int, sentiment: int, max_value: int) -> void:
	var tween := get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUINT)
	var duration := 2
	
	$Bar.value = 0
	$Bar.max_value = max_value
	var _sentiments := [1, 0, -1]; sentiment = _sentiments.find(sentiment)
	$Bar.tint_progress = colours.values()[sentiment]
	$Label.label_settings.font_color = colours.values()[sentiment]
	$Label.text = association[0].to_upper()
	
	var _tooltip_text = association + " (%s)" % str(value / 100)
	
	$Label.tooltip_text = _tooltip_text
	$Bar.tooltip_text = _tooltip_text
	$Bar.mouse_filter = MOUSE_FILTER_IGNORE if value == 0 else MOUSE_FILTER_STOP
	
	tween.tween_property($Bar, "value", value, duration)
