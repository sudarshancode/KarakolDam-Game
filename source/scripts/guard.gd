extends CharacterBody3D
## Mercenary guard. State machine: PATROL -> SUSPICIOUS -> SEARCH -> COMBAT.
## Perception: vision cone + line of sight, hearing (noise events), corpses.

enum State { PATROL, SUSPICIOUS, SEARCH, COMBAT, DEAD }

const PATROL_SPEED := 1.9
const SEARCH_SPEED := 3.2
const COMBAT_SPEED := 4.6
const VIEW_RANGE := 42.0
const CONE_COS := 0.62 # about 52 degrees either side of forward
const GRAVITY := 20.0
const DAMAGE := 5.0

# Set by the spawner before the guard enters the tree.
var route: Array = []
var route_loop := true
var route_wait := 2.0
var uniform_color := Color(0.25, 0.3, 0.22)
var start_state := State.PATROL
var start_target := Vector3.ZERO

var state := State.PATROL
var health := 100.0
var awareness := 0.0
var seeing_player := false
var has_alerted := false

var _wp := 0
var _wp_dir := 1
var _wait := 0.0
var _state_time := 0.0
var _search_phase := 0
var _investigate := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _lose_sight := 0.0
var _fire_cd := 1.0
var _burst_left := 0
var _burst_cd := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _repath := 0.0
var _desired_vel := Vector3.ZERO
var _look_dir := Vector3.FORWARD
var _corpse_timer := 0.0
var _seen_corpses := {}
var _t := 0.0

var _nav: NavigationAgent3D
var _muzzle: Marker3D
var _indicator: Label3D


func _ready() -> void:
	add_to_group("guards")
	collision_layer = 4
	collision_mask = 1 | 8
	floor_snap_length = 0.5
	_t = randf() * 10.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_model()

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.7
	_nav.target_desired_distance = 1.0
	_nav.radius = 0.4
	_nav.height = 1.8
	_nav.avoidance_enabled = false
	add_child(_nav)

	_indicator = Label3D.new()
	_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_indicator.pixel_size = 0.012
	_indicator.font_size = 72
	_indicator.outline_size = 14
	_indicator.position.y = 2.25
	_indicator.no_depth_test = true
	_indicator.visible = false
	add_child(_indicator)

	if route.size() > 0:
		_look_dir = (route[mini(1, route.size() - 1)] - route[0])
		_look_dir.y = 0.0
		if _look_dir.length() < 0.1:
			_look_dir = Vector3.FORWARD
	rotation.y = atan2(-_look_dir.x, -_look_dir.z)

	if start_state == State.SEARCH:
		awareness = 0.8
		_enter_search(start_target)
	elif start_state == State.COMBAT:
		_last_seen = start_target
		_enter_combat()


func _box(pos: Vector3, size: Vector3, color: Color, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	mi.material_override = m
	add_child(mi)
	mi.position = pos
	return mi


func _build_model() -> void:
	var skin := Color(0.76, 0.58, 0.46)
	var pants := Color(0.16, 0.17, 0.15)
	var dark := Color(0.1, 0.1, 0.11)
	_box(Vector3(-0.12, 0.42, 0), Vector3(0.2, 0.84, 0.24), pants)
	_box(Vector3(0.12, 0.42, 0), Vector3(0.2, 0.84, 0.24), pants)
	_box(Vector3(0, 1.17, 0), Vector3(0.5, 0.66, 0.3), uniform_color)
	_box(Vector3(0, 1.12, 0.17), Vector3(0.38, 0.4, 0.1), uniform_color.darkened(0.3))
	_box(Vector3(-0.32, 1.2, -0.05), Vector3(0.13, 0.55, 0.15), uniform_color)
	_box(Vector3(0.32, 1.28, -0.2), Vector3(0.13, 0.15, 0.5), uniform_color)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	head.mesh = sm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = skin
	head.material_override = hm
	add_child(head)
	head.position = Vector3(0, 1.66, 0)
	var helmet := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 0.16
	hsm.height = 0.2
	helmet.mesh = hsm
	var hlm := StandardMaterial3D.new()
	hlm.albedo_color = uniform_color.darkened(0.35)
	helmet.material_override = hlm
	add_child(helmet)
	helmet.position = Vector3(0, 1.74, 0)
	_box(Vector3(0.28, 1.27, -0.42), Vector3(0.06, 0.09, 0.62), dark, 0.5)
	_muzzle = Marker3D.new()
	add_child(_muzzle)
	_muzzle.position = Vector3(0.28, 1.28, -0.76)


# --- Main loop --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_t += delta
	_update_perception(delta)
	match state:
		State.PATROL:
			_do_patrol(delta)
		State.SUSPICIOUS:
			_do_suspicious(delta)
		State.SEARCH:
			_do_search(delta)
		State.COMBAT:
			_do_combat(delta)
	_apply_movement(delta)
	_update_indicator()


func _apply_movement(delta: float) -> void:
	if _look_dir.length() > 0.05:
		var target_yaw := atan2(-_look_dir.x, -_look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 8.0 * delta))
	velocity.x = move_toward(velocity.x, _desired_vel.x, 28.0 * delta)
	velocity.z = move_toward(velocity.z, _desired_vel.z, 28.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


## Walk towards `target` using the navigation mesh. Returns true when arrived.
func _move_to(target: Vector3, speed: float, face_move := true) -> bool:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 0.9:
		_desired_vel = Vector3.ZERO
		return true
	_repath -= get_physics_process_delta_time()
	if _repath <= 0.0 or _nav.target_position.distance_to(target) > 1.5:
		_nav.target_position = target
		_repath = 0.35
	var next := _nav.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if _nav.is_navigation_finished() or d.length() < 0.05:
		d = flat
	_desired_vel = d.normalized() * speed
	if face_move:
		_look_dir = d
	return false


# --- Perception ------------------------------------------------------------------------

func _line_of_sight(p: Node3D) -> float:
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3(0, 1.6, 0)
	var score := 0.0
	for h in [0.88, 0.45]:
		var tgt: Vector3 = p.global_position + Vector3(0, p.current_height * h, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, tgt, 1 | 2)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] == p:
			score += 0.5
	return score


func _update_perception(delta: float) -> void:
	var p: Node3D = Game.player
	seeing_player = false
	if p == null or not p.alive:
		awareness = maxf(0.0, awareness - 0.3 * delta)
		return
	var to_p := p.global_position - global_position
	var dist := to_p.length()
	var max_range := VIEW_RANGE * (0.6 if p.crouching else 1.0)
	var vis := 0.0
	if dist < max_range:
		var flat := Vector3(to_p.x, 0.0, to_p.z)
		var fwd := -global_transform.basis.z
		var in_cone := flat.length() < 3.0 or fwd.dot(flat.normalized()) > CONE_COS
		if in_cone:
			vis = _line_of_sight(p)
	if vis > 0.0:
		seeing_player = true
		_last_seen = p.global_position
		_lose_sight = 0.0
		var closeness := 1.0 - clampf(dist / max_range, 0.0, 1.0)
		var gain := (0.35 + 1.4 * closeness) * vis * (1.35 if p.sprinting else 1.0)
		if state == State.COMBAT:
			awareness = 1.0
		else:
			awareness = minf(1.0, awareness + gain * delta)
	else:
		_lose_sight += delta
		if state != State.COMBAT:
			awareness = maxf(0.0, awareness - 0.22 * delta)

	if state != State.COMBAT and awareness >= 1.0:
		_enter_combat()
	elif seeing_player and state == State.PATROL and awareness >= 0.3:
		_enter_suspicious(_last_seen)
	elif seeing_player and (state == State.SUSPICIOUS or state == State.SEARCH):
		_investigate = _last_seen

	_corpse_timer -= delta
	if _corpse_timer <= 0.0:
		_corpse_timer = 0.3
		_check_corpses()


func _check_corpses() -> void:
	if state == State.COMBAT:
		return
	var eye := global_position + Vector3(0, 1.6, 0)
	var fwd := -global_transform.basis.z
	for c in get_tree().get_nodes_in_group("corpses"):
		if _seen_corpses.has(c):
			continue
		var to_c: Vector3 = c.global_position - global_position
		to_c.y = 0.0
		var d := to_c.length()
		if d > 24.0 or d < 0.1:
			continue
		if fwd.dot(to_c.normalized()) < CONE_COS and d > 3.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, c.global_position + Vector3(0, 0.4, 0), 1)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		_seen_corpses[c] = true
		awareness = maxf(awareness, 0.7)
		Game.alert_area(c.global_position, 28.0, self)
		_enter_search(c.global_position)
		return


func hear(pos: Vector3, radius: float) -> void:
	if state == State.DEAD or state == State.COMBAT:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	if radius >= 30.0:
		awareness = maxf(awareness, 0.75)
		_enter_search(pos)
	else:
		awareness = maxf(awareness, 0.4)
		if state == State.PATROL:
			_enter_suspicious(pos)
		else:
			_investigate = pos
			_state_time = 0.0
			_search_phase = 0


func alert_to(pos: Vector3) -> void:
	if state == State.DEAD or state == State.COMBAT:
		return
	awareness = maxf(awareness, 0.7)
	_enter_search(pos)


func take_damage(amount: float, from_pos: Vector3, headshot := false) -> void:
	if state == State.DEAD:
		return
	health -= amount
	Game.play_sound("hit", global_position)
	if health <= 0.0:
		_die(headshot)
		return
	awareness = maxf(awareness, 0.85)
	if state == State.COMBAT:
		return
	if seeing_player:
		awareness = 1.0
		_enter_combat()
	else:
		_enter_search(from_pos)


func _die(headshot: bool) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 1
	_indicator.visible = false
	remove_from_group("guards")
	add_to_group("corpses")
	Game.stats["kills"] += 1
	if headshot:
		Game.stats["headshots"] += 1
	Game.play_sound("death", global_position)
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# --- States ---------------------------------------------------------------------------------

func _enter_suspicious(pos: Vector3) -> void:
	state = State.SUSPICIOUS
	_state_time = 0.0
	_investigate = pos


func _enter_search(pos: Vector3) -> void:
	state = State.SEARCH
	_state_time = 0.0
	_search_phase = 0
	_investigate = pos
	_wait = 0.0


func _enter_combat() -> void:
	state = State.COMBAT
	_state_time = 0.0
	awareness = 1.0
	_fire_cd = 0.7
	_burst_left = 0
	if not has_alerted:
		has_alerted = true
		Game.guard_entered_combat(self)


func _return_to_patrol() -> void:
	state = State.PATROL
	_state_time = 0.0
	awareness = minf(awareness, 0.2)
	if route.size() > 0:
		var best := 0
		var best_d := INF
		for i in route.size():
			var d := global_position.distance_to(route[i])
			if d < best_d:
				best_d = d
				best = i
		_wp = best


func _advance_wp() -> void:
	if route.size() < 2:
		return
	if route_loop:
		_wp = (_wp + 1) % route.size()
	else:
		if _wp + _wp_dir >= route.size() or _wp + _wp_dir < 0:
			_wp_dir = -_wp_dir
		_wp += _wp_dir


func _do_patrol(delta: float) -> void:
	if route.is_empty():
		_desired_vel = Vector3.ZERO
		return
	if _wait > 0.0:
		_wait -= delta
		_desired_vel = Vector3.ZERO
		# glance around while waiting
		var base: Vector3 = route[_wp] - global_position
		base.y = 0.0
		if base.length() > 0.1:
			_look_dir = base.normalized().rotated(Vector3.UP, sin(_t * 0.9) * 0.9)
		return
	if _move_to(route[_wp], PATROL_SPEED):
		_wait = route_wait
		_advance_wp()


func _do_suspicious(_delta: float) -> void:
	_desired_vel = Vector3.ZERO
	var d := _investigate - global_position
	d.y = 0.0
	if d.length() > 0.1:
		_look_dir = d
	if _state_time > 1.6:
		_enter_search(_investigate)


func _do_search(_delta: float) -> void:
	if _search_phase == 0:
		if _move_to(_investigate, SEARCH_SPEED):
			_search_phase = 1
			_state_time = 0.0
		elif _state_time > 18.0:
			_return_to_patrol()
	else:
		_desired_vel = Vector3.ZERO
		_look_dir = Vector3.FORWARD.rotated(Vector3.UP, _t * 1.3)
		if _state_time > 5.5:
			_return_to_patrol()


func _do_combat(delta: float) -> void:
	var p: Node3D = Game.player
	if p == null or not p.alive:
		_desired_vel = Vector3.ZERO
		return
	if seeing_player:
		var flat := p.global_position - global_position
		flat.y = 0.0
		var dist := flat.length()
		_look_dir = flat
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(1.2, 2.8)
			_strafe = -_strafe
		if dist > 18.0:
			_move_to(p.global_position, COMBAT_SPEED, false)
		elif dist < 7.0:
			_desired_vel = -flat.normalized() * 2.2
		else:
			_desired_vel = flat.normalized().rotated(Vector3.UP, PI * 0.5) * _strafe * 1.8
		_shoot_logic(delta, dist)
	else:
		_burst_left = 0
		if _lose_sight > 6.0:
			_enter_search(_last_seen)
		else:
			_move_to(_last_seen, COMBAT_SPEED)


func _shoot_logic(delta: float, dist: float) -> void:
	_fire_cd -= delta
	if _burst_left > 0:
		_burst_cd -= delta
		if _burst_cd <= 0.0:
			_fire_once(dist)
			_burst_left -= 1
			_burst_cd = 0.11
	elif _fire_cd <= 0.0:
		_burst_left = 3
		_burst_cd = 0.0
		_fire_cd = randf_range(1.2, 2.0)


func _fire_once(dist: float) -> void:
	var p: Node3D = Game.player
	var from := _muzzle.global_position
	var target := p.global_position + Vector3(0, p.current_height * 0.6, 0)
	var chance := clampf(1.0 - dist / 38.0, 0.1, 0.65)
	if p.crouching:
		chance *= 0.8
	if p.velocity.length() > 5.0:
		chance *= 0.7
	var hit := randf() < chance
	var end := target
	if not hit:
		end = target + Vector3(randf_range(-1.3, 1.3), randf_range(-0.9, 0.9), randf_range(-1.3, 1.3))
	var q := PhysicsRayQueryParameters3D.create(from, end, 1)
	q.exclude = [get_rid()]
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		end = wall["position"]
		hit = false
		Game.spawn_impact(wall["position"], wall["normal"])
	Game.spawn_tracer(from, end, Color(1.0, 0.55, 0.25))
	Game.play_sound("rifle", from, -3.0, 0.9)
	if hit:
		p.take_damage(DAMAGE, global_position)


func _update_indicator() -> void:
	var show_it := state == State.COMBAT or state == State.SUSPICIOUS or state == State.SEARCH or awareness > 0.15
	_indicator.visible = show_it
	if not show_it:
		return
	if state == State.COMBAT:
		_indicator.text = "!"
		_indicator.modulate = Color(1.0, 0.2, 0.15)
	else:
		_indicator.text = "?"
		var a := clampf(awareness, 0.35, 1.0)
		_indicator.modulate = Color(1.0, lerpf(0.9, 0.55, awareness), 0.15, a)
