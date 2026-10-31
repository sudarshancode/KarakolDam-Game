extends Area3D
## Health kit or ammo crate. Collected by walking over it (only when useful).

var kind := "health"
var amount := 50.0
var _visual: Node3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.1
	cs.shape = sh
	cs.position.y = 0.8
	add_child(cs)

	_visual = Node3D.new()
	add_child(_visual)
	_visual.position.y = 0.6
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.38, 0.38)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.roughness = 0.7
	if kind == "health":
		m.albedo_color = Color(0.92, 0.92, 0.92)
	else:
		m.albedo_color = Color(0.28, 0.4, 0.22)
	box.material_override = m
	_visual.add_child(box)
	if kind == "health":
		_add_stripe(Vector3(0.34, 0.1, 0.4))
		_add_stripe(Vector3(0.1, 0.34, 0.4), Color(0.85, 0.1, 0.1))
	else:
		_add_stripe(Vector3(0.4, 0.06, 0.4), Color(0.9, 0.75, 0.2))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 1.0, 0.5) if kind == "health" else Color(1.0, 0.85, 0.4)
	glow.omni_range = 4.0
	glow.light_energy = 0.6
	glow.position.y = 0.9
	add_child(glow)


func _add_stripe(size: Vector3, color := Color(0.85, 0.1, 0.1)) -> void:
	var s := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	s.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color * 0.4
	s.material_override = m
	_visual.add_child(s)


func _physics_process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * 1.6
	_visual.position.y = 0.65 + sin(_t * 2.4) * 0.07
	for b in get_overlapping_bodies():
		if b == Game.player and b.has_method("heal"):
			if kind == "health":
				if b.health < b.MAX_HEALTH:
					b.heal(amount)
					Game.play_sound("pickup")
					Game.post_message("Picked up a medkit.", 1.6)
					queue_free()
			else:
				if b.add_ammo():
					Game.play_sound("pickup")
					Game.post_message("Picked up ammo.", 1.6)
					queue_free()
