class_name Donut extends RigidBody3D

var resolution: Vector2i
var speed = 3
var max_velocity := Vector3(0.5, 0.5, 0.5)
var previous_position: Vector3
var random_colours := [
	Color.from_rgba8(180, 173, 255, 255),
	Color.from_rgba8(161, 255, 197, 255),
	Color.from_rgba8(255, 179, 198, 255),
	Color.from_rgba8(255, 244, 179, 255),
	Color.from_rgba8(209, 209, 209, 255),
	Color.from_rgba8(179, 252, 255, 255),
	Color.from_rgba8(255, 145, 239, 255),
]

func _ready() -> void:
	if get_parent().has_node("Marker3D"):
		var marker_1: Marker3D = get_node("../Marker3D")
		var marker_2: Marker3D = get_node("../Marker3D2")
		var random_position := Vector3(
			randf_range(marker_1.global_position.x, marker_2.global_position.x),
			randf_range(marker_1.global_position.y, marker_2.global_position.y),
			randf_range(marker_1.global_position.z, marker_2.global_position.z)
		)
		global_position = random_position
	
	var colour: Color = random_colours[randi() % random_colours.size()]
	$TestNPC.set_surface_override_material(0, $TestNPC.mesh.material.duplicate())
	$TestNPC.get_surface_override_material(0).albedo_color = colour
	
	body_entered.connect(_on_body_entered)
	_apply_random_impulse()

func _apply_random_impulse() -> void:
	var random_impulse := Vector3()
	for a in ["x", "y", "z"]:
		random_impulse[a] = randf_range(max_velocity[a] * -1, max_velocity[a])
	
	apply_impulse(random_impulse)
	apply_torque_impulse(random_impulse)

func _on_body_entered(body: Node3D) -> void:
	if not get_tree().paused: return
	apply_impulse(Basis.looking_at(body.global_position).get_euler() * speed * -20)
	apply_torque_impulse(Basis.looking_at(body.global_position).get_euler() * speed * -20)
	$Blip.play()

func _physics_process(delta: float) -> void:
	apply_central_force(global_basis.z * speed * delta)
	
	_clamp_velocity("linear_velocity")
	_clamp_velocity("angular_velocity")
	if position.distance_to(previous_position) < 0.01: _apply_random_impulse()
	previous_position = position

func _clamp_velocity(prop: String) -> void:
	var velocity: Vector3 = self[prop]
	for a in ["x", "y", "z"]:
		if velocity[a] > max_velocity[a]: velocity[a] = max_velocity[a]
		elif velocity[a] < max_velocity[a] * -1: velocity[a] = max_velocity[a] * -1
	self[prop] = velocity
