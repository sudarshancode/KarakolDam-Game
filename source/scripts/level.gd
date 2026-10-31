extends Node3D
## Builds the whole "Karakol Dam" level from code: terrain, dam, fences,
## buildings, props, objectives, pickups, patrol routes and the navigation mesh.
##
## Layout (top-down, north = -Z):
##   dam wall along the north edge, turbine hall in front of it,
##   control tower east, comms relay west, fenced compound in the middle,
##   player starts south-west, extraction on a ridge to the east.

const InteractableScript = preload("res://scripts/interactable.gd")
const PickupScript = preload("res://scripts/pickup.gd")

const MAP_HALF := 115.0
const L_WORLD := 1
const L_FENCE := 8

var nav_region: NavigationRegion3D
var spawn_pos := Vector3(-70.0, 0.3, 88.0)
var spawn_yaw := deg_to_rad(-25.0)
var extraction_pos := Vector3(104.0, 9.0, -20.0)
var extraction_area: Area3D
var patrols: Array = []
var reinforcement_points: Array = []
var map_markers: Array = []
var nav_ready := false

var _mats := {}
var _rng := RandomNumberGenerator.new()
var _tex_ground: NoiseTexture2D
var _tex_concrete: NoiseTexture2D
var _blinkers: Array = []
var _comms_light: Node3D
var _beam_mat: StandardMaterial3D
var _beam_light: OmniLight3D
var _extract_label: Label3D
var _t := 0.0
var _valves: Array = []


func build() -> void:
	_rng.seed = 7
	_tex_ground = _noise_tex(0.03, 11)
	_tex_concrete = _noise_tex(0.12, 5)
	_build_environment()
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	_build_ground_and_bounds()
	_build_dam()
	_build_fences()
	_build_buildings()
	_build_props()
	_build_trees_and_rocks()
	_build_ramp_and_extraction()
	_build_interactables()
	_build_pickups()
	_define_patrols()
	_build_mountains()
	_bake_navigation()
	Game.objectives_changed.connect(_on_objectives_changed)
	_on_objectives_changed()


func _process(delta: float) -> void:
	_t += delta
	var on := fmod(_t, 1.2) < 0.18
	if is_instance_valid(_comms_light) and not Game.comms_disabled:
		_comms_light.visible = on
	for b in _blinkers:
		if is_instance_valid(b):
			b.visible = fmod(_t * 2.0, 1.0) < 0.5


# ---------------------------------------------------------------------------------
# Materials and primitive helpers
# ---------------------------------------------------------------------------------

func _noise_tex(freq: float, seed_value: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.seed = seed_value
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.62, 0.62, 0.62), Color(1, 1, 1)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	return t


func _m(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	var tex: Texture2D = null
	match key:
		"ground":
			m.albedo_color = Color(0.45, 0.43, 0.34)
			tex = _tex_ground
		"concrete":
			m.albedo_color = Color(0.68, 0.68, 0.66)
			tex = _tex_concrete
		"concrete_dark":
			m.albedo_color = Color(0.46, 0.47, 0.5)
			tex = _tex_concrete
		"roof":
			m.albedo_color = Color(0.32, 0.34, 0.37)
		"metal":
			m.albedo_color = Color(0.38, 0.43, 0.5)
			m.metallic = 0.5
			m.roughness = 0.5
		"rust":
			m.albedo_color = Color(0.52, 0.28, 0.2)
		"wood":
			m.albedo_color = Color(0.52, 0.38, 0.23)
		"green":
			m.albedo_color = Color(0.27, 0.36, 0.24)
		"rock":
			m.albedo_color = Color(0.5, 0.48, 0.45)
			tex = _tex_concrete
		"fence":
			m.albedo_color = Color(0.55, 0.57, 0.6, 0.3)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"post":
			m.albedo_color = Color(0.22, 0.24, 0.27)
			m.metallic = 0.3
		"pipe":
			m.albedo_color = Color(0.14, 0.32, 0.5)
			m.metallic = 0.6
			m.roughness = 0.4
		"yellow":
			m.albedo_color = Color(0.9, 0.72, 0.12)
		"trunk":
			m.albedo_color = Color(0.3, 0.2, 0.12)
		"leaf":
			m.albedo_color = Color(0.14, 0.27, 0.16)
		"glass":
			m.albedo_color = Color(1.0, 0.85, 0.5)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.4)
			m.emission_energy_multiplier = 1.4
		"mountain":
			m.albedo_color = Color(0.22, 0.26, 0.33)
		"lamp":
			m.albedo_color = Color(1.0, 0.9, 0.6)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.5)
			m.emission_energy_multiplier = 2.0
		"strip":
			m.albedo_color = Color(1.0, 0.97, 0.9)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.9)
			m.emission_energy_multiplier = 1.6
		_:
			m.albedo_color = Color(0.6, 0.6, 0.6)
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	_mats[key] = m
	return m


func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO, layer := L_WORLD, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var p: Node = parent if parent != null else nav_region
	p.add_child(body)
	body.position = pos
	body.rotation_degrees = rot_deg
	return body


func _vis_box(pos: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p: Node = parent if parent != null else self
	p.add_child(mesh)
	mesh.position = pos
	mesh.rotation_degrees = rot_deg
	return mesh


func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material, collide := true, parent: Node = null, top_radius := -1.0) -> Node3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 14
	mesh.mesh = cm
	mesh.material_override = mat
	var p: Node = parent if parent != null else (nav_region if collide else self)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = L_WORLD
		body.collision_mask = 0
		body.add_child(mesh)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		p.add_child(body)
		body.position = pos
		return body
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mesh)
	mesh.position = pos
	return mesh


func _omni(pos: Vector3, color: Color, energy: float, rng_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	add_child(l)
	l.position = pos
	return l


## Wall from a to b (XZ plane) with optional door gaps (Vector2: start, end distance along the wall).
func _wall(a: Vector3, b: Vector3, height: float, thick: float, mat: Material, gaps: Array = [], door_h := 2.6, layer := L_WORLD) -> void:
	var d := b - a
	d.y = 0.0
	var length := d.length()
	var dir := d / length
	var yaw := atan2(-dir.z, dir.x)
	var cuts: Array = gaps.duplicate()
	cuts.sort_custom(func(x, y): return x.x < y.x)
	var cursor := 0.0
	for g in cuts:
		if g.x > cursor + 0.01:
			_wall_seg(a, dir, yaw, cursor, g.x, 0.0, height, thick, mat, layer)
		if height > door_h + 0.05:
			_wall_seg(a, dir, yaw, g.x, g.y, door_h, height, thick, mat, layer)
		cursor = g.y
	if cursor < length - 0.01:
		_wall_seg(a, dir, yaw, cursor, length, 0.0, height, thick, mat, layer)


func _wall_seg(a: Vector3, dir: Vector3, yaw: float, s0: float, s1: float, y0: float, y1: float, thick: float, mat: Material, layer: int) -> void:
	var mid := a + dir * ((s0 + s1) * 0.5)
	var pos := Vector3(mid.x, (y0 + y1) * 0.5, mid.z)
	_add_box(pos, Vector3(s1 - s0, y1 - y0, thick), mat, Vector3(0, rad_to_deg(yaw), 0), layer)


## Rectangular building. doors: {"N"/"S"/"E"/"W": [Vector2(offset_from_center, width), ...]}
func _building(center: Vector2, size: Vector2, height: float, wall_mat: Material, doors := {}, door_h := 2.6, roof_mat: Material = null) -> void:
	var x0 := center.x - size.x * 0.5
	var x1 := center.x + size.x * 0.5
	var z0 := center.y - size.y * 0.5
	var z1 := center.y + size.y * 0.5
	var t := 0.4
	_wall(Vector3(x0, 0, z0), Vector3(x1, 0, z0), height, t, wall_mat, _gaps(doors.get("N", []), size.x), door_h)
	_wall(Vector3(x0, 0, z1), Vector3(x1, 0, z1), height, t, wall_mat, _gaps(doors.get("S", []), size.x), door_h)
	_wall(Vector3(x0, 0, z0), Vector3(x0, 0, z1), height, t, wall_mat, _gaps(doors.get("W", []), size.y), door_h)
	_wall(Vector3(x1, 0, z0), Vector3(x1, 0, z1), height, t, wall_mat, _gaps(doors.get("E", []), size.y), door_h)
	var rm: Material = roof_mat if roof_mat != null else _m("roof")
	_add_box(Vector3(center.x, height + 0.2, center.y), Vector3(size.x + 0.8, 0.4, size.y + 0.8), rm)


func _gaps(door_list: Array, wall_len: float) -> Array:
	var out: Array = []
	for dd in door_list:
		var c: float = wall_len * 0.5 + dd.x
		out.append(Vector2(c - dd.y * 0.5, c + dd.y * 0.5))
	return out


# ---------------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.31, 0.55)
	sky_mat.sky_horizon_color = Color(0.93, 0.68, 0.52)
	sky_mat.ground_horizon_color = Color(0.72, 0.58, 0.5)
	sky_mat.ground_bottom_color = Color(0.25, 0.24, 0.26)
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.58, 0.55)
	env.fog_density = 0.0021
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26.0, 52.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.62)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


func _build_ground_and_bounds() -> void:
	_add_box(Vector3(0, -1.0, 0), Vector3(240, 2, 240), _m("ground"))
	# Invisible boundary walls
	for data in [
		[Vector3(MAP_HALF + 1.0, 30, 0), Vector3(2, 60, 260)],
		[Vector3(-MAP_HALF - 1.0, 30, 0), Vector3(2, 60, 260)],
		[Vector3(0, 30, MAP_HALF + 1.0), Vector3(260, 60, 2)],
		[Vector3(0, 30, -MAP_HALF - 1.0), Vector3(260, 60, 2)],
	]:
		var body := StaticBody3D.new()
		body.collision_layer = L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = data[1]
		cs.shape = bs
		body.add_child(cs)
		nav_region.add_child(body)
		body.position = data[0]


func _build_dam() -> void:
	_add_box(Vector3(0, 14, -98), Vector3(236, 28, 14), _m("concrete"))
	_vis_box(Vector3(0, 28.3, -96), Vector3(236, 0.6, 10), _m("concrete_dark"))
	for i in range(-5, 6):
		_add_box(Vector3(i * 21.0, 14, -89.5), Vector3(3.0, 28, 3.0), _m("concrete_dark"))
	for i in range(-4, 5):
		if i == 0:
			continue
		_vis_box(Vector3(i * 21.0 + 10.5, 9.0, -90.9), Vector3(8.0, 14.0, 0.3), _m("metal"))
	var sign_label := Label3D.new()
	sign_label.text = "KARAKOL HYDROELECTRIC STATION"
	sign_label.font_size = 160
	sign_label.pixel_size = 0.045
	sign_label.modulate = Color(0.9, 0.9, 0.85)
	sign_label.outline_size = 0
	add_child(sign_label)
	sign_label.position = Vector3(0, 22.0, -90.8)
	# A tail-race channel in front of the dam foot (decor)
	_vis_box(Vector3(0, 0.03, -84.0), Vector3(150, 0.06, 4.0), _water_mat())


func _water_mat() -> StandardMaterial3D:
	if _mats.has("water"):
		return _mats["water"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.3, 0.42, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.metallic = 0.3
	_mats["water"] = m
	return m


func _build_mountains() -> void:
	var count := 18
	for i in count:
		var ang := TAU * float(i) / count + _rng.randf_range(-0.12, 0.12)
		var r := _rng.randf_range(165.0, 195.0)
		var h := _rng.randf_range(45.0, 95.0)
		var rad := _rng.randf_range(38.0, 70.0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rad
		cm.height = h
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = _m("mountain")
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = Vector3(cos(ang) * r, h * 0.5 - 6.0, sin(ang) * r)
		mi.rotation.y = _rng.randf() * TAU


# ---------------------------------------------------------------------------------
# Fences, buildings
# ---------------------------------------------------------------------------------

func _fence(a: Vector2, b: Vector2, gaps: Array = []) -> void:
	var va := Vector3(a.x, 0, a.y)
	var vb := Vector3(b.x, 0, b.y)
	_wall(va, vb, 3.2, 0.15, _m("fence"), gaps, 99.0, L_FENCE)
	var length := va.distance_to(vb)
	var dir := (vb - va).normalized()
	var s := 0.0
	while s <= length + 0.01:
		var skip := false
		for g in gaps:
			if s > g.x - 0.2 and s < g.y + 0.2:
				skip = true
		if not skip:
			var p := va + dir * s
			_vis_box(Vector3(p.x, 1.8, p.z), Vector3(0.22, 3.6, 0.22), _m("post"))
		s += 5.0


func _build_fences() -> void:
	# compound: x -60..50, z -78..60
	_fence(Vector2(-60, 60), Vector2(50, 60), [Vector2(55, 65)])  # south, main gate
	_fence(Vector2(-60, 60), Vector2(-60, -78), [Vector2(49, 52)])  # west, service gap
	_fence(Vector2(-60, -78), Vector2(50, -78))  # north
	_fence(Vector2(50, -78), Vector2(50, 60), [Vector2(54, 62)])  # east, vehicle exit
	# Main gate posts and barriers
	for sx in [-5.6, 5.6]:
		_add_box(Vector3(sx, 2.0, 60), Vector3(1.0, 4.0, 1.0), _m("concrete_dark"))
	_vis_box(Vector3(0, 4.3, 60), Vector3(12.2, 0.6, 0.8), _m("yellow"))
	for bx in [-10.0, 10.0]:
		_add_box(Vector3(bx, 0.5, 57.0), Vector3(4.0, 1.0, 0.7), _m("concrete_dark"), Vector3(0, 12.0 * signf(bx), 0))
	# Watchtower (decor) in the north-east corner
	var tx := 44.0
	var tz := -72.0
	for dx in [-2.0, 2.0]:
		for dz in [-2.0, 2.0]:
			_add_box(Vector3(tx + dx, 3.5, tz + dz), Vector3(0.35, 7.0, 0.35), _m("post"))
	_add_box(Vector3(tx, 7.15, tz), Vector3(5.4, 0.3, 5.4), _m("metal"))
	_vis_box(Vector3(tx, 8.4, tz), Vector3(4.6, 2.2, 4.6), _m("green"))
	_vis_box(Vector3(tx, 9.7, tz), Vector3(5.6, 0.3, 5.6), _m("roof"))
	_vis_box(Vector3(tx, 8.6, tz + 2.35), Vector3(3.6, 0.9, 0.1), _m("glass"))


func _build_buildings() -> void:
	var concrete := _m("concrete")
	# Comms shed (objective 1) ---------------------------------------------
	_building(Vector2(-40, 22), Vector2(9, 7), 3.5, concrete, {"S": [Vector2(0, 2.2)]})
	_omni(Vector3(-40, 3.0, 22), Color(1.0, 0.95, 0.8), 1.0, 9.0)
	# Mast
	_add_cyl(Vector3(-26, 9.0, 15), 0.45, 18.0, _m("metal"), true, null, 0.22)
	for hy in [6.0, 11.0, 15.0]:
		_vis_box(Vector3(-26, hy, 15), Vector3(3.2, 0.12, 0.12), _m("metal"))
		_vis_box(Vector3(-26, hy, 15), Vector3(0.12, 0.12, 3.2), _m("metal"))
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 0.1, 0.1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1, 0.1, 0.1)
	lamp_mat.emission_energy_multiplier = 3.0
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	lamp.mesh = sm
	lamp.material_override = lamp_mat
	add_child(lamp)
	lamp.position = Vector3(-26, 18.3, 15)
	var lamp_light := OmniLight3D.new()
	lamp_light.light_color = Color(1, 0.2, 0.15)
	lamp_light.omni_range = 14.0
	lamp.add_child(lamp_light)
	_comms_light = lamp

	# Control tower (objective 2) -------------------------------------------
	_building(Vector2(28, 20), Vector2(16, 12), 5.0, concrete, {"W": [Vector2(0, 2.4)], "S": [Vector2(4, 2.4)]})
	_add_box(Vector3(30, 11.0, 17), Vector3(6, 12, 6), _m("concrete_dark"))
	_vis_box(Vector3(30, 15.5, 17), Vector3(6.3, 1.5, 6.3), _m("glass"))
	_vis_box(Vector3(30, 17.3, 17), Vector3(7.2, 0.5, 7.2), _m("roof"))
	_add_cyl(Vector3(30, 19.5, 17), 0.12, 4.0, _m("metal"), false)
	_omni(Vector3(28, 4.0, 20), Color(1.0, 0.95, 0.8), 1.1, 11.0)

	# Turbine hall (objective 3) ------------------------------------------------
	_building(Vector2(0, -52), Vector2(46, 26), 12.0, _m("concrete_dark"),
		{"S": [Vector2(-8, 3.5), Vector2(8, 3.5)], "E": [Vector2(0, 3.0)], "W": [Vector2(0, 3.0)]}, 4.2)
	for lx in [-15.0, 0.0, 15.0]:
		for lz in [-46.0, -58.0]:
			_omni(Vector3(lx, 9.0, lz), Color(1.0, 0.95, 0.85), 1.2, 17.0)
		_vis_box(Vector3(lx, 11.7, -52), Vector3(0.7, 0.12, 22), _m("strip"))
	for tx in [-14.0, 0.0, 14.0]:
		_add_cyl(Vector3(tx, 2.25, -52), 3.2, 4.5, _m("metal"))
		_add_cyl(Vector3(tx, 4.7, -52), 1.2, 1.0, _m("rust"), false)
		_vis_box(Vector3(tx, 5.5, -52), Vector3(1.0, 1.0, 1.0), _m("yellow"))
	# Coolant pipe along the north wall
	var pipe := _add_cyl(Vector3(0, 3.0, -63.7), 0.55, 44.0, _m("pipe"), false)
	pipe.rotation_degrees = Vector3(0, 0, 90)
	# crane rail beams (decor)
	for bz in [-60.0, -52.0, -44.0]:
		_vis_box(Vector3(0, 10.6, bz), Vector3(44, 0.5, 0.6), _m("metal"))

	# Barracks, warehouse, guard booth ---------------------------------------------
	_building(Vector2(-38, -10), Vector2(14, 8), 4.0, concrete, {"E": [Vector2(0, 2.2)]})
	_omni(Vector3(-38, 3.2, -10), Color(1.0, 0.9, 0.7), 0.9, 9.0)
	for bz in [-12.5, -9.5, -7.5]:
		_add_box(Vector3(-43.0, 0.4, bz), Vector3(1.8, 0.8, 0.9), _m("green"))
	_building(Vector2(-40, -40), Vector2(18, 12), 6.0, _m("rust"), {"E": [Vector2(0, 4.0)], "S": [Vector2(-4, 3.5)]}, 3.4)
	_omni(Vector3(-40, 5.0, -40), Color(1.0, 0.92, 0.75), 1.0, 13.0)
	_building(Vector2(11, 55), Vector2(3.5, 3.0), 2.8, concrete, {"W": [Vector2(0, 1.2)]})
	# Fuel tanks
	for tz in [-42.0, -54.0]:
		_add_cyl(Vector3(35, 4.0, tz), 4.5, 8.0, _m("metal"))
		_add_cyl(Vector3(35, 8.3, tz), 3.2, 0.6, _m("rust"), false)


# ---------------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------------

func _crates(cx: float, cz: float, count: int) -> void:
	for i in count:
		var s := _rng.randf_range(1.0, 1.6)
		var ox := _rng.randf_range(-2.2, 2.2)
		var oz := _rng.randf_range(-2.2, 2.2)
		var key := "wood" if _rng.randf() < 0.5 else "green"
		var yaw := _rng.randf_range(0.0, 90.0)
		_add_box(Vector3(cx + ox, s * 0.5, cz + oz), Vector3(s, s, s), _m(key), Vector3(0, yaw, 0))
		if _rng.randf() < 0.3:
			var s2 := s * 0.8
			_add_box(Vector3(cx + ox, s + s2 * 0.5, cz + oz), Vector3(s2, s2, s2), _m(key), Vector3(0, yaw + 20.0, 0))


func _barrels(cx: float, cz: float, count: int) -> void:
	for i in count:
		var key := "rust" if _rng.randf() < 0.6 else "pipe"
		_add_cyl(Vector3(cx + _rng.randf_range(-1.2, 1.2), 0.5, cz + _rng.randf_range(-1.2, 1.2)), 0.35, 1.0, _m(key))


func _truck(x: float, z: float, yaw: float) -> void:
	var t := Node3D.new()
	nav_region.add_child(t)
	t.position = Vector3(x, 0, z)
	t.rotation_degrees.y = yaw
	_add_box(Vector3(0, 1.8, 0.6), Vector3(2.6, 2.7, 5.4), _m("green"), Vector3.ZERO, L_WORLD, t)
	_add_box(Vector3(0, 1.15, -3.1), Vector3(2.5, 1.9, 1.9), _m("rust"), Vector3.ZERO, L_WORLD, t)
	_add_box(Vector3(0, 0.55, 0.0), Vector3(2.3, 0.5, 8.4), _m("post"), Vector3.ZERO, L_WORLD, t)
	_vis_box(Vector3(0, 1.6, -3.95), Vector3(2.1, 0.8, 0.1), _m("glass"), Vector3.ZERO, t)
	for wz in [-3.1, 0.2, 2.4]:
		for wx in [-1.25, 1.25]:
			var w := _add_cyl(Vector3(wx, 0.55, wz), 0.55, 0.4, _m("post"), false, t)
			w.rotation_degrees = Vector3(0, 0, 90)


func _lamp(x: float, z: float) -> void:
	_vis_box(Vector3(x, 3.5, z), Vector3(0.18, 7.0, 0.18), _m("post"))
	_vis_box(Vector3(x, 7.05, z), Vector3(0.9, 0.18, 0.5), _m("lamp"))
	_omni(Vector3(x, 6.5, z), Color(1.0, 0.85, 0.55), 1.2, 15.0)


func _build_props() -> void:
	for c in [Vector3(-24, 0, 48), Vector3(22, 0, 46), Vector3(-20, 0, 28), Vector3(-50, 0, -24), Vector3(40, 0, 0),
			Vector3(-8, 0, -30), Vector3(18, 0, -30), Vector3(40, 0, -66), Vector3(-52, 0, -62), Vector3(-30, 0, 4),
			Vector3(38, 0, 36), Vector3(-52, 0, 40)]:
		_crates(c.x, c.z, 4)
	_barrels(-52.0, 22.0, 4)
	_barrels(46.0, 20.0, 3)
	_barrels(-16.0, -44.0, 3)
	_barrels(20.0, 56.0, 3)
	_truck(-27.0, 34.0, 90.0)
	_truck(36.0, 46.0, 20.0)
	_truck(43.0, -34.0, 90.0)
	# Interior cover
	_add_box(Vector3(24, 0.9, 15.2), Vector3(3.0, 1.8, 1.2), _m("wood"))
	_add_box(Vector3(31, 0.45, 24.8), Vector3(4.0, 0.9, 1.2), _m("wood"))
	_add_box(Vector3(-37, 0.6, 24.3), Vector3(1.4, 1.2, 1.4), _m("green"))
	_add_box(Vector3(-17, 0.6, -44.0), Vector3(1.6, 1.2, 1.6), _m("green"))
	_add_box(Vector3(18, 0.6, -58.0), Vector3(1.6, 1.2, 1.6), _m("wood"))
	_crates(-44.0, -40.0, 3)
	_crates(-36.0, -43.0, 3)
	for l in [Vector2(-14, 40), Vector2(14, 40), Vector2(-14, 5), Vector2(14, 5), Vector2(-30, -22), Vector2(14, -22), Vector2(30, 2), Vector2(-48, 40)]:
		_lamp(l.x, l.y)


func _tree_allowed(x: float, z: float) -> bool:
	if x > -66.0 and x < 56.0 and z > -84.0 and z < 66.0:
		return false
	if x > 54.0 and z > -42.0 and z < 2.0:
		return false
	if z > 64.0 and z < 78.0 and x > -60.0 and x < 62.0:
		return false
	if Vector2(x, z).distance_to(Vector2(-70, 88)) < 10.0:
		return false
	if x > -78.0 and x < -56.0 and z > 0.0 and z < 20.0:
		return false
	if z < -86.0:
		return false
	return true


func _build_trees_and_rocks() -> void:
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 800:
		tries += 1
		var x := _rng.randf_range(-108.0, 108.0)
		var z := _rng.randf_range(-86.0, 108.0)
		if not _tree_allowed(x, z):
			continue
		placed += 1
		var s := _rng.randf_range(0.8, 1.4)
		_add_cyl(Vector3(x, 1.5 * s, z), 0.3 * s, 3.0 * s, _m("trunk"))
		_add_cyl(Vector3(x, 3.0 * s + 2.2 * s, z), 2.3 * s, 4.6 * s, _m("leaf"), false, null, 0.0)
		_add_cyl(Vector3(x, 3.0 * s + 4.4 * s, z), 1.7 * s, 3.6 * s, _m("leaf"), false, null, 0.0)
	# Rocks around the start area and along the west service gap
	for r in [Vector3(-66, 0, 80), Vector3(-76, 0, 82), Vector3(-62, 0, 90), Vector3(-80, 0, 94), Vector3(-72, 0, 70),
			Vector3(-66, 0, 54), Vector3(-72, 0, 40), Vector3(-68, 0, 26), Vector3(-64, 0, 4), Vector3(-64, 0, 17),
			Vector3(-30, 0, 78), Vector3(-10, 0, 84), Vector3(20, 0, 80), Vector3(60, 0, 62), Vector3(70, 0, 30),
			Vector3(72, 0, -52), Vector3(84, 0, 10), Vector3(-90, 0, 0), Vector3(-80, 0, -40)]:
		_rock(r.x, r.z, _rng.randf_range(1.6, 3.2))


func _rock(x: float, z: float, s: float) -> void:
	var sz := Vector3(s * _rng.randf_range(1.0, 1.7), s * _rng.randf_range(0.7, 1.3), s * _rng.randf_range(1.0, 1.6))
	_add_box(Vector3(x, sz.y * 0.3, z), sz, _m("rock"),
		Vector3(_rng.randf_range(-12, 12), _rng.randf_range(0, 360), _rng.randf_range(-12, 12)))


# ---------------------------------------------------------------------------------
# Ridge, extraction
# ---------------------------------------------------------------------------------

func _build_ramp_and_extraction() -> void:
	# Ramp: ground (x=60,y=0) up to the plateau edge (x=95,y=9)
	var theta := atan2(9.0, 35.0)
	var dir2 := Vector2(cos(theta), sin(theta))
	var s_start := Vector2(60, 0) - dir2 * 2.0
	var e_end := Vector2(95.5, 9.0)
	var top_center := (s_start + e_end) * 0.5
	var normal2 := Vector2(-sin(theta), cos(theta))
	var thick := 2.0
	var center := top_center - normal2 * (thick * 0.5)
	var length := s_start.distance_to(e_end)
	_add_box(Vector3(center.x, center.y, -20), Vector3(length, thick, 30), _m("rock"), Vector3(0, 0, rad_to_deg(theta)))
	# Plateau
	_add_box(Vector3(105, 4.0, -20), Vector3(22, 10, 30), _m("rock"))
	# Boulders for cover on the plateau
	for b in [Vector3(98, 9.0, -33), Vector3(100, 9.0, -7), Vector3(112, 9.0, -30), Vector3(112, 9.0, -10)]:
		_add_box(Vector3(b.x, b.y + 0.6, b.z), Vector3(2.6, 1.6, 2.2), _m("rock"), Vector3(0, _rng.randf_range(0, 90), 0))

	# Helipad
	_vis_box(extraction_pos + Vector3(0, 0.06, 0), Vector3(12, 0.12, 12), _m("concrete_dark"))
	var h := Label3D.new()
	h.text = "H"
	h.font_size = 400
	h.pixel_size = 0.014
	h.modulate = Color(0.95, 0.95, 0.9)
	h.outline_size = 0
	h.rotation_degrees = Vector3(-90, 0, 0)
	add_child(h)
	h.position = extraction_pos + Vector3(0, 0.15, 0)

	# Beam
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.6, 0.6, 0.6, 0.12)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.5
	cm.bottom_radius = 4.5
	cm.height = 45.0
	cm.radial_segments = 20
	beam.mesh = cm
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.position = extraction_pos + Vector3(0, 22.5, 0)
	_beam_light = _omni(extraction_pos + Vector3(0, 3.0, 0), Color(0.6, 0.6, 0.6), 1.5, 16.0)

	var label := Label3D.new()
	label.text = "EXTRACTION"
	label.font_size = 96
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.6, 1.0, 0.7)
	add_child(label)
	label.position = extraction_pos + Vector3(0, 7.0, 0)
	label.visible = false
	_extract_label = label

	extraction_area = Area3D.new()
	extraction_area.collision_layer = 0
	extraction_area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = 6.0
	shp.height = 8.0
	cs.shape = shp
	extraction_area.add_child(cs)
	add_child(extraction_area)
	extraction_area.position = extraction_pos + Vector3(0, 3.0, 0)
	map_markers.append({"pos": extraction_pos, "label": "4", "node": null})


func _on_objectives_changed() -> void:
	if _beam_mat == null:
		return
	var ready_to_leave := Game.charges_planted >= Game.CHARGES_REQUIRED
	var c := Color(0.25, 1.0, 0.45) if ready_to_leave else Color(0.6, 0.6, 0.6)
	_beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.22 if ready_to_leave else 0.1)
	_beam_light.light_color = c
	_extract_label.visible = ready_to_leave
	if Game.comms_disabled and is_instance_valid(_comms_light):
		_comms_light.visible = false


# ---------------------------------------------------------------------------------
# Objectives
# ---------------------------------------------------------------------------------

func _make_terminal(pos: Vector3, yaw_deg: float, prompt: String, hold: float, size: Vector3, screen_color: Color) -> StaticBody3D:
	var it = InteractableScript.new()
	it.collision_layer = L_WORLD | 16
	it.collision_mask = 0
	it.prompt = prompt
	it.hold_time = hold
	nav_region.add_child(it)
	it.position = pos
	it.rotation_degrees = Vector3(0, yaw_deg, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	it.add_child(cs)
	_vis_box(Vector3.ZERO, size, _m("post"), Vector3.ZERO, it)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = screen_color
	sm.emission_enabled = true
	sm.emission = screen_color
	sm.emission_energy_multiplier = 2.0
	_vis_box(Vector3(0, size.y * 0.12, size.z * 0.5 + 0.02), Vector3(size.x * 0.78, size.y * 0.45, 0.05), sm, Vector3.ZERO, it)
	var glow := OmniLight3D.new()
	glow.light_color = screen_color
	glow.omni_range = 5.0
	glow.light_energy = 0.8
	it.add_child(glow)
	glow.position = Vector3(0, size.y * 0.3, size.z * 0.5 + 0.6)
	return it


func _build_interactables() -> void:
	# 1. Comms relay terminal (inside the shed, back wall)
	var comms = _make_terminal(Vector3(-40, 0.6, 19.2), 0.0, "Hold [E] to destroy the comms relay", 4.0, Vector3(1.6, 1.2, 0.6), Color(1.0, 0.6, 0.2))
	comms.completed.connect(func(_i): Game.disable_comms())
	map_markers.append({"pos": Vector3(-40, 0, 22), "label": "1", "node": comms})

	# 2. Control tower terminal (east wall)
	var term = _make_terminal(Vector3(35.2, 0.6, 20), -90.0, "Hold [E] to download the sabotage plans", 6.0, Vector3(1.6, 1.2, 0.6), Color(0.3, 0.9, 1.0))
	term.completed.connect(func(_i): Game.terminal_downloaded())
	map_markers.append({"pos": Vector3(35, 0, 20), "label": "2", "node": term})

	# 3. Coolant valve panels
	for vx in [-12.0, 12.0]:
		var v = _make_terminal(Vector3(vx, 0.9, -64.3), 0.0, "Hold [E] to plant a charge", 4.0, Vector3(1.8, 1.8, 0.5), Color(1.0, 0.25, 0.2))
		v.locked_message = "Valve locked. Download the access codes from the control tower first."
		v.unlock_check = func(): return Game.terminal_done
		v.completed.connect(_on_valve_done)
		_valves.append(v)
		map_markers.append({"pos": Vector3(vx, 0, -62), "label": "3", "node": v})


func _on_valve_done(it: Node3D) -> void:
	# visible charge on the valve
	var pos := it.global_position + it.global_transform.basis.z * 0.55 + Vector3(0, -0.3, 0)
	var body := _vis_box(pos, Vector3(0.7, 0.45, 0.3), _m("green"))
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(1, 0.1, 0.1)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1, 0.1, 0.1)
	led_mat.emission_energy_multiplier = 3.0
	var led := _vis_box(Vector3(0, 0.1, 0.17), Vector3(0.12, 0.12, 0.05), led_mat, Vector3.ZERO, body)
	_blinkers.append(led)
	Game.charge_planted()


# ---------------------------------------------------------------------------------
# Pickups
# ---------------------------------------------------------------------------------

func _pickup(kind: String, pos: Vector2) -> void:
	var p = PickupScript.new()
	p.kind = kind
	p.amount = 50.0
	add_child(p)
	p.position = Vector3(pos.x, 0.0, pos.y)


func _build_pickups() -> void:
	for p in [Vector2(-42, 24), Vector2(34, 17), Vector2(-10, -61), Vector2(-57, 30), Vector2(47, -32), Vector2(0, 50)]:
		_pickup("health", p)
	for p in [Vector2(-34, -8), Vector2(24, 23), Vector2(18, -42), Vector2(-64, 12), Vector2(62, -24), Vector2(-45, -36)]:
		_pickup("ammo", p)


# ---------------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------------

func _route(points: Array, loop: bool, wait: float, color: Color) -> void:
	var r: Array = []
	for v in points:
		r.append(Vector3(v.x, 0.1, v.y))
	patrols.append({"route": r, "loop": loop, "wait": wait, "color": color})


func _define_patrols() -> void:
	var green := Color(0.22, 0.3, 0.2)
	var tan := Color(0.36, 0.3, 0.2)
	var slate := Color(0.2, 0.24, 0.3)
	var black := Color(0.15, 0.15, 0.17)
	var gray := Color(0.32, 0.32, 0.34)
	var brown := Color(0.3, 0.22, 0.17)
	_route([Vector2(-7, 54), Vector2(-7, 47)], false, 3.5, green)
	_route([Vector2(7, 54), Vector2(7, 47)], false, 3.5, green)
	_route([Vector2(-54, 54), Vector2(-54, 10), Vector2(-54, -40), Vector2(-54, -70)], false, 2.5, tan)
	_route([Vector2(44, 54), Vector2(44, 10), Vector2(44, -40), Vector2(44, -70)], false, 2.5, tan)
	_route([Vector2(-48, 29), Vector2(-32, 29), Vector2(-32, 15), Vector2(-48, 15)], true, 1.5, slate)
	_route([Vector2(24, 18), Vector2(32, 21), Vector2(32, 23), Vector2(24, 23)], true, 2.5, black)
	_route([Vector2(14, 31), Vector2(41, 31), Vector2(41, 9), Vector2(14, 9)], true, 1.0, black)
	_route([Vector2(-18, -44), Vector2(18, -44)], false, 3.0, gray)
	_route([Vector2(-18, -59), Vector2(18, -59)], false, 3.0, gray)
	_route([Vector2(-27, -35), Vector2(27, -35), Vector2(27, -70), Vector2(-27, -70)], true, 1.0, gray)
	_route([Vector2(-10, 35), Vector2(10, 35), Vector2(10, -20), Vector2(-10, -20)], true, 1.0, brown)
	_route([Vector2(-25, 0), Vector2(-25, -25), Vector2(5, -25), Vector2(5, 0)], true, 1.5, brown)
	_route([Vector2(66, -28), Vector2(66, -12)], false, 4.0, green)
	_route([Vector2(-50, 70), Vector2(50, 70)], false, 2.5, green)
	reinforcement_points = [Vector3(-6, 0.1, 72), Vector3(-2, 0.1, 74), Vector3(2, 0.1, 72), Vector3(6, 0.1, 74)]


# ---------------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------------

func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25 # must match the default navigation map settings
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_region.navigation_mesh = nm
	var t0 := Time.get_ticks_msec()
	nav_region.bake_navigation_mesh(false)
	var polys := nav_region.navigation_mesh.get_polygon_count()
	nav_ready = polys > 0
	print("[level] navmesh baked: %d polygons in %d ms" % [polys, Time.get_ticks_msec() - t0])
