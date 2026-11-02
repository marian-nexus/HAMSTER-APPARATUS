class_name TableItem extends HBoxContainer

const CORNER_RADIUS := 2
static var items: Array[TableItem]
static var key_width: float:
	set(value):
		key_width = value
		for i in range(items.size() - 1): items[i].update_key_width()

func _ready() -> void:
	items.append(self)
	_add_corners.call_deferred()

func _exit_tree() -> void: items.erase(self)

func set_text(key: String, value: String) -> void:
	%Key.text = key
	%Value.text = value
	update_key_width.call_deferred()
	_check_key_width.call_deferred()

func update_key_width() -> void:
	var parent: MarginContainer = %Key.get_parent()
	parent.custom_minimum_size.x = key_width + 10

func _check_key_width() -> void:
	if %Key.size.x > key_width: key_width = %Key.size.x

func _add_corners() -> void:
	var sides := ["left", "right"]
	var to_add: String
	if items[0] == self: to_add = "top"
	elif items.back() == self: to_add = "bottom"
	else: return
	
	for panel: PanelContainer in get_children():
		panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel").duplicate())
		var stylebox: StyleBoxFlat = panel.get_theme_stylebox("panel")
		stylebox["corner_radius_%s_%s" % [to_add, sides[panel.get_index()]]] = CORNER_RADIUS
