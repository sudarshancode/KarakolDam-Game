extends Node
## Global mission state (autoload "Game"): objectives, alarm, noise events,
## sound playback and a few effect helpers shared by every other script.

const Sfx = preload("res://scripts/sfx.gd")

signal alarm_changed(active: bool)
signal objectives_changed
signal message_posted(text: String, seconds: float)
signal mission_ended(success: bool, reason: String)
signal player_hit(from_pos: Vector3)
signal reinforcements_requested(origin: Vector3)
signal detonation

const CHARGES_REQUIRED := 2
const COUNTDOWN_SECONDS := 150.0

var comms_disabled := false
var terminal_done := false
var charges_planted := 0
var alarm := false
var countdown := -1.0
var mission_over := false
var mission_success := false
var playing := false
var skip_menu := false
var player: CharacterBody3D = null
var stats := {"kills": 0, "headshots": 0, "shots": 0, "alarms": 0, "time": 0.0}
var sounds := {}
var _last_tick := -1
var _local_alert_told := false


func _ready() -> void:
	_register_inputs()
	sounds = Sfx.build_all()


func reset() -> void:
	comms_disabled = false
	terminal_done = false
	charges_planted = 0
	alarm = false
	countdown = -1.0
	mission_over = false
	mission_success = false
	playing = false
	player = null
	stats = {"kills": 0, "headshots": 0, "shots": 0, "alarms": 0, "time": 0.0}
	_last_tick = -1
	_local_alert_told = false


func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E],
		"reload": [KEY_R],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"map": [KEY_M, KEY_TAB],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k as Key
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = mouse[action] as MouseButton
		InputMap.action_add_event(action, ev)


func _process(delta: float) -> void:
	if not playing or mission_over:
		return
	stats["time"] += delta
	if countdown > 0.0:
		countdown -= delta
		var whole := int(ceil(countdown))
		if whole != _last_tick:
			_last_tick = whole
			if whole <= 30 or whole % 10 == 0:
				play_sound("tick", null, -6.0)
		if countdown <= 0.0:
			countdown = 0.0
			detonation.emit()
			play_sound("explosion", null, 2.0)
			end_mission(false, "The charges detonated while you were still inside the complex.")


# --- Mission events -------------------------------------------------------

func post_message(text: String, seconds := 4.0) -> void:
	message_posted.emit(text, seconds)


func disable_comms() -> void:
	if comms_disabled:
		return
	comms_disabled = true
	play_sound("done")
	if alarm:
		alarm = false
		alarm_changed.emit(false)
		post_message("Comms relay destroyed. The alarm has been cut and no more reinforcements can be called.", 6.0)
	else:
		post_message("Comms relay disabled. Guards can no longer call for reinforcements.", 5.0)
	objectives_changed.emit()


func terminal_downloaded() -> void:
	terminal_done = true
	play_sound("done")
	post_message("Sabotage plans downloaded. The coolant valves in the turbine hall are now unlocked.", 6.0)
	objectives_changed.emit()


func charge_planted() -> void:
	charges_planted += 1
	play_sound("done")
	if charges_planted >= CHARGES_REQUIRED:
		countdown = COUNTDOWN_SECONDS
		post_message("Both charges armed. Detonation in %d seconds. Get to the extraction point on the ridge!" % int(COUNTDOWN_SECONDS), 7.0)
	else:
		post_message("Charge armed (%d/%d)." % [charges_planted, CHARGES_REQUIRED], 3.0)
	objectives_changed.emit()


func end_mission(success: bool, reason: String) -> void:
	if mission_over:
		return
	mission_over = true
	mission_success = success
	objectives_changed.emit()
	mission_ended.emit(success, reason)


# --- Alerts, noise ---------------------------------------------------------

func make_noise(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	for g in get_tree().get_nodes_in_group("guards"):
		g.hear(pos, radius)


func alert_area(pos: Vector3, radius: float, except: Node = null) -> void:
	for g in get_tree().get_nodes_in_group("guards"):
		if g == except:
			continue
		if g.global_position.distance_to(pos) <= radius:
			g.alert_to(pos)


func guard_entered_combat(guard: Node3D) -> void:
	if alarm:
		return
	if comms_disabled:
		alert_area(guard.global_position, 40.0, guard)
		if not _local_alert_told:
			_local_alert_told = true
			post_message("You were spotted! Comms are down, so only nearby guards are alerted.", 5.0)
		return
	alarm = true
	stats["alarms"] += 1
	alarm_changed.emit(true)
	reinforcements_requested.emit(guard.global_position)
	alert_area(guard.global_position, 60.0, guard)
	post_message("ALARM! Reinforcements are on the way. Destroy the comms relay to stop them.", 6.0)


# --- Audio / effects helpers ------------------------------------------------

func play_sound(sound_name: String, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var root := get_tree().current_scene
	if root == null:
		return
	if pos is Vector3:
		var p := AudioStreamPlayer3D.new()
		p.stream = sounds[sound_name]
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.unit_size = 14.0
		p.max_distance = 220.0
		root.add_child(p)
		p.global_position = pos
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = sounds[sound_name]
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		root.add_child(p2)
		p2.finished.connect(p2.queue_free)
		p2.play()


func spawn_tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.9, 0.5)) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, dist)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	mi.look_at(to, up)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func spawn_impact(pos: Vector3, normal: Vector3, color := Color(0.8, 0.75, 0.6)) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 50.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.8, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 4
	sm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	sm.material = mat
	p.mesh = sm
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
