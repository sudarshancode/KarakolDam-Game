extends CharacterBody3D
## First-person player: movement, crouch, aim, two weapons, interaction.

signal health_changed(hp: float)
signal ammo_changed
signal weapon_changed

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 16.0
const MOUSE_SENS := 0.0022
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const MAX_HEALTH := 100.0

var health := MAX_HEALTH
var alive := true
var crouching := false
var sprinting := false
var aiming := false
var current_height := STAND_HEIGHT
var weapons: Array = []
var weapon_index := 0
var cooldown := 0.0
var reload_left := 0.0
var interact_target = null
var interact_progress := 0.0
var spread_now := 1.0

var camera: Camera3D
var head: Node3D
var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var _view: Node3D
var _guns: Array = []
var _muzzles: Array = []
var _flash: Node3D
var _flash_light: OmniLight3D
var _flash_time := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _kick := 0.0
var _bob := 0.0
var _step_dist := 0.0
var _view_kick := 0.0
var _last_deny := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.38
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_HEIGHT * 0.5
	add_child(_shape)

	head = Node3D.new()
	head.position.y = STAND_HEIGHT - 0.15
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 600.0
	head.add_child(camera)
	camera.make_current()

	_view = Node3D.new()
	_view.position = Vector3(0.22, -0.2, -0.45)
	camera.add_child(_view)
	_init_weapons()
	_build_viewmodels()
	_switch_weapon(0, true)


func _init_weapons() -> void:
	weapons = [
		{"name": "SILENCED PISTOL", "damage": 34.0, "mag_size": 12, "mag": 12, "reserve": 48, "reserve_max": 96,
		"rate": 0.26, "auto": false, "spread": 0.45, "noise": 7.0, "reload": 1.5, "recoil": 2.4, "sound": "pistol", "vol": -4.0},
		{"name": "ASSAULT RIFLE", "damage": 22.0, "mag_size": 30, "mag": 30, "reserve": 90, "reserve_max": 180,
		"rate": 0.095, "auto": true, "spread": 1.2, "noise": 75.0, "reload": 2.3, "recoil": 1.3, "sound": "rifle", "vol": 0.0},
	]


# --- Viewmodel ---------------------------------------------------------------

func _vm_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	m.metallic = 0.35
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	return mi


func _vm_cyl(parent: Node3D, pos: Vector3, radius: float, length: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 10
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.metallic = 0.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)


func _build_viewmodels() -> void:
	var dark := Color(0.12, 0.12, 0.14)
	var mid := Color(0.22, 0.23, 0.26)
	var sleeve := Color(0.2, 0.28, 0.2)
	var skin := Color(0.12, 0.12, 0.13) # tactical gloves

	# Pistol with suppressor
	var pistol := Node3D.new()
	_view.add_child(pistol)
	_vm_box(pistol, Vector3(0, 0.02, -0.05), Vector3(0.055, 0.07, 0.26), mid)
	_vm_box(pistol, Vector3(0, -0.06, 0.05), Vector3(0.045, 0.12, 0.06), dark, Vector3(12, 0, 0))
	_vm_cyl(pistol, Vector3(0, 0.03, -0.32), 0.02, 0.24, dark)
	_vm_box(pistol, Vector3(0, -0.09, 0.2), Vector3(0.08, 0.09, 0.3), sleeve)
	_vm_box(pistol, Vector3(0, -0.035, 0.07), Vector3(0.07, 0.06, 0.08), skin)
	var pm := Marker3D.new()
	pm.position = Vector3(0, 0.03, -0.46)
	pistol.add_child(pm)
	_guns.append(pistol)
	_muzzles.append(pm)

	# Assault rifle
	var rifle := Node3D.new()
	_view.add_child(rifle)
	_vm_box(rifle, Vector3(0, 0.0, -0.08), Vector3(0.07, 0.1, 0.5), mid)
	_vm_cyl(rifle, Vector3(0, 0.02, -0.5), 0.016, 0.38, dark)
	_vm_box(rifle, Vector3(0, -0.01, 0.26), Vector3(0.06, 0.11, 0.24), dark)
	_vm_box(rifle, Vector3(0.0, -0.13, -0.02), Vector3(0.05, 0.17, 0.07), dark, Vector3(-10, 0, 0))
	_vm_box(rifle, Vector3(0, 0.075, -0.15), Vector3(0.03, 0.04, 0.14), dark)
	_vm_box(rifle, Vector3(0, -0.07, 0.12), Vector3(0.06, 0.12, 0.05), dark, Vector3(15, 0, 0))
	_vm_box(rifle, Vector3(0, -0.1, 0.34), Vector3(0.09, 0.09, 0.3), sleeve)
	_vm_box(rifle, Vector3(0, -0.05, -0.28), Vector3(0.07, 0.06, 0.12), skin)
	var rm := Marker3D.new()
	rm.position = Vector3(0, 0.02, -0.72)
	rifle.add_child(rm)
	_guns.append(rifle)
	_muzzles.append(rm)

	_flash = Node3D.new()
	var fm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	fm.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	fm.material_override = mat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.add_child(fm)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.8, 0.5)
	_flash_light.omni_range = 9.0
	_flash_light.light_energy = 2.0
	_flash.add_child(_flash_light)
	_flash.visible = false


func _switch_weapon(i: int, force := false) -> void:
	if i == weapon_index and not force:
		return
	weapon_index = i
	reload_left = 0.0
	cooldown = 0.35
	for k in _guns.size():
		_guns[k].visible = (k == i)
	if _flash.get_parent():
		_flash.get_parent().remove_child(_flash)
	_muzzles[i].add_child(_flash)
	_flash.visible = false
	weapon_changed.emit()
	ammo_changed.emit()


# --- Input -------------------------------------------------------------------

func set_yaw(yaw: float) -> void:
	_yaw = yaw
	rotation.y = yaw


func _unhandled_input(event: InputEvent) -> void:
	if not alive or Game.mission_over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * (0.55 if aiming else 1.0)
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_switch_weapon((weapon_index + 1) % weapons.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_switch_weapon((weapon_index + weapons.size() - 1) % weapons.size())


# --- Update -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	rotation.y = _yaw
	head.rotation.x = _pitch
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.mission_over

	# Crouch / stand (stay crouched if there is no headroom)
	var want_crouch := captured and Input.is_action_pressed("crouch")
	if not want_crouch and crouching:
		var blocked := test_move(global_transform, Vector3(0, STAND_HEIGHT - CROUCH_HEIGHT + 0.05, 0))
		want_crouch = blocked
	crouching = want_crouch
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	current_height = lerpf(current_height, target_h, minf(1.0, 12.0 * delta))
	_capsule.height = current_height
	_shape.position.y = current_height * 0.5
	head.position.y = current_height - 0.15

	aiming = captured and Input.is_action_pressed("aim") and reload_left <= 0.0
	var input_dir := Vector2.ZERO
	if captured:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprinting = captured and Input.is_action_pressed("sprint") and input_dir.y < -0.1 and not crouching and not aiming
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if aiming:
		speed *= 0.6
	var wish := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var accel := 32.0 if is_on_floor() else 5.0
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	if is_on_floor():
		if captured and Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	_update_footsteps(delta, hspeed)
	_update_camera(delta, hspeed)
	if captured:
		_update_weapon(delta, hspeed)
		_update_interaction(delta)
	else:
		interact_target = null
		interact_progress = 0.0

	# Spread estimate (used by the crosshair too)
	spread_now = (1.0 + hspeed * 0.15) * (0.4 if aiming else 1.0) * (0.7 if crouching else 1.0)


func _update_footsteps(delta: float, hspeed: float) -> void:
	if not is_on_floor() or hspeed < 1.0:
		return
	_step_dist += hspeed * delta
	if _step_dist >= 2.1:
		_step_dist = 0.0
		if crouching:
			Game.play_sound("step", null, -22.0, 0.85)
		elif sprinting:
			Game.play_sound("step", null, -8.0, 1.1)
			Game.make_noise(global_position, 16.0)
		else:
			Game.play_sound("step", null, -14.0)
			Game.make_noise(global_position, 6.0)


func _update_camera(delta: float, hspeed: float) -> void:
	var tfov := 52.0 if aiming else (82.0 if sprinting else 75.0)
	camera.fov = lerpf(camera.fov, tfov, minf(1.0, 10.0 * delta))
	if is_on_floor() and hspeed > 0.5:
		_bob += hspeed * delta * 1.7
	var amp := 0.035 * minf(1.0, hspeed / SPRINT_SPEED) * (0.3 if aiming else 1.0)
	camera.position = Vector3(cos(_bob * 0.5) * amp * 0.6, sin(_bob) * amp, 0.0)
	_kick = lerpf(_kick, 0.0, minf(1.0, 9.0 * delta))
	camera.rotation.x = deg_to_rad(_kick)

	var rest := Vector3(0.22, -0.2, -0.45)
	if aiming:
		rest = Vector3(0.0, -0.115, -0.36)
	elif sprinting:
		rest = Vector3(0.3, -0.3, -0.4)
	rest.z += _view_kick
	_view_kick = lerpf(_view_kick, 0.0, minf(1.0, 14.0 * delta))
	_view.position = _view.position.lerp(rest, minf(1.0, 14.0 * delta))
	var tilt := 22.0 if sprinting else 0.0
	_view.rotation_degrees.y = lerpf(_view.rotation_degrees.y, tilt, minf(1.0, 10.0 * delta))

	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.visible = false


func _update_weapon(delta: float, hspeed: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if Input.is_action_just_pressed("weapon_1"):
		_switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_switch_weapon(1)
	var w: Dictionary = weapons[weapon_index]
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			var need: int = w["mag_size"] - w["mag"]
			var take: int = mini(need, w["reserve"])
			w["mag"] += take
			w["reserve"] -= take
			ammo_changed.emit()
		return
	if Input.is_action_just_pressed("reload"):
		start_reload()
		return
	var wants: bool = Input.is_action_pressed("fire") if w["auto"] else Input.is_action_just_pressed("fire")
	if wants and cooldown <= 0.0:
		if w["mag"] > 0:
			_shoot(w, hspeed)
		else:
			cooldown = 0.3
			Game.play_sound("click", null, -6.0)
			if w["reserve"] > 0:
				start_reload()


func start_reload() -> void:
	var w: Dictionary = weapons[weapon_index]
	if reload_left > 0.0 or w["mag"] >= w["mag_size"] or w["reserve"] <= 0:
		return
	reload_left = w["reload"]
	Game.play_sound("reload", null, -4.0)


func _shoot(w: Dictionary, hspeed: float) -> void:
	w["mag"] -= 1
	cooldown = w["rate"]
	Game.stats["shots"] += 1
	var spread_deg: float = w["spread"] * spread_now
	var basis := camera.global_transform.basis
	var dir := -basis.z
	dir = dir.rotated(basis.x, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	dir = dir.rotated(basis.y, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var origin := camera.global_position
	var to := origin + dir * 250.0
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		if col != null and col.has_method("take_damage"):
			var head_shot: bool = (hit["position"].y - col.global_position.y) > 1.45
			var dmg: float = w["damage"] * (3.0 if head_shot else 1.0)
			col.take_damage(dmg, global_position, head_shot)
			Game.spawn_impact(hit["position"], hit["normal"], Color(0.8, 0.1, 0.1))
		else:
			Game.spawn_impact(hit["position"], hit["normal"])
	var muzzle: Node3D = _muzzles[weapon_index]
	Game.spawn_tracer(muzzle.global_position, end)
	Game.play_sound(w["sound"], null, w["vol"])
	Game.make_noise(global_position, w["noise"])
	_flash.visible = true
	_flash_time = 0.045
	_kick += w["recoil"] * (0.5 if aiming else 1.0)
	_pitch = minf(deg_to_rad(85.0), _pitch + deg_to_rad(w["recoil"] * 0.18))
	_view_kick = 0.06 if weapon_index == 1 else 0.09
	ammo_changed.emit()
	if w["mag"] == 0 and w["reserve"] > 0:
		start_reload()


func _update_interaction(delta: float) -> void:
	var origin := camera.global_position
	var to := origin - camera.global_transform.basis.z * 2.7
	var q := PhysicsRayQueryParameters3D.create(origin, to, 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target = null
	if not hit.is_empty() and hit["collider"].has_method("get_prompt"):
		target = hit["collider"]
	if target != interact_target:
		interact_target = target
		interact_progress = 0.0
	if target == null:
		return
	if Input.is_action_pressed("interact"):
		if target.can_use():
			interact_progress += delta
			if interact_progress >= target.hold_time:
				interact_progress = 0.0
				target.complete()
		elif not target.done and Input.is_action_just_pressed("interact"):
			Game.post_message(target.locked_message, 3.0)
	else:
		interact_progress = maxf(0.0, interact_progress - delta * 2.0)


# --- Health / ammo -----------------------------------------------------------------

func take_damage(amount: float, from_pos := Vector3.ZERO) -> void:
	if not alive or Game.mission_over:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	Game.player_hit.emit(from_pos)
	Game.play_sound("hurt", null, -3.0)
	if health <= 0.0:
		alive = false
		var tw := create_tween()
		tw.tween_property(head, "position:y", 0.3, 0.6)
		tw.parallel().tween_property(camera, "rotation:z", deg_to_rad(40.0), 0.6)
		Game.end_mission(false, "You were killed in action.")


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + amount)
	health_changed.emit(health)


func add_ammo() -> bool:
	var added := false
	for w in weapons:
		if w["reserve"] < w["reserve_max"]:
			w["reserve"] = mini(w["reserve_max"], w["reserve"] + w["mag_size"] * 2)
			added = true
	if added:
		ammo_changed.emit()
	return added
