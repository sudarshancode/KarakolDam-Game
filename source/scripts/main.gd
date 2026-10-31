extends Node3D
## Entry point: builds the level, spawns the player and guards, wires events.
##
## Developer flags (after "--" on the command line):
##   --selftest            run a short automatic check and quit
##   --shot=PATH           save a screenshot after a moment and quit
##   --teleport=x,y,z,yaw,pitch   place the player (degrees) before the screenshot
##   --frames=N            number of physics frames to run in test modes

const LevelScript = preload("res://scripts/level.gd")
const PlayerScript = preload("res://scripts/player.gd")
const GuardScript = preload("res://scripts/guard.gd")
const HudScript = preload("res://scripts/hud.gd")

var level
var player
var hud
var guards_root: Node3D
var _siren: AudioStreamPlayer
var _hint_timer := 0.0
var _args := {}
var _frames := 0
var _test_frames := 360
var _start_positions := {}
var _built := false


func _ready() -> void:
	Game.reset()
	_parse_args()
	if _args.has("flowtest"):
		process_mode = Node.PROCESS_MODE_ALWAYS # keep counting frames even when the end screen pauses the game
	hud = HudScript.new()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	_build_world()
	_built = true
	var testing := _args.has("selftest") or _args.has("shot") or _args.has("flowtest")
	var skip := Game.skip_menu or (testing and not _args.has("title"))
	Game.skip_menu = false
	if skip:
		hud.begin_play()
		if testing:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _args.has("map"):
			hud._set_map(true)
	else:
		hud.show_title()
		if _args.has("shot"):
			await get_tree().create_timer(1.5, true).timeout
			get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
			print("[shot] title saved")
			get_tree().quit(0)
	if _args.has("teleport"):
		var v: PackedStringArray = String(_args["teleport"]).split(",")
		if v.size() >= 5:
			player.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			player.set_yaw(deg_to_rad(float(v[3])))
			player._pitch = deg_to_rad(float(v[4]))


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else true
	if _args.has("frames"):
		_test_frames = int(_args["frames"])


func _build_world() -> void:
	level = LevelScript.new()
	add_child(level)
	level.build()

	guards_root = Node3D.new()
	guards_root.name = "Guards"
	add_child(guards_root)

	player = PlayerScript.new()
	add_child(player)
	player.global_position = level.spawn_pos
	player.set_yaw(level.spawn_yaw)
	Game.player = player

	for p in level.patrols:
		var g := _spawn_guard(p, p["route"][0])
		_start_positions[g] = g.global_position

	hud.level = level
	hud.bind_player(player)

	Game.alarm_changed.connect(_on_alarm_changed)
	Game.reinforcements_requested.connect(_on_reinforcements)
	Game.mission_ended.connect(_on_mission_ended)
	print("[main] world ready: %d guards" % guards_root.get_child_count())


func _spawn_guard(data: Dictionary, pos: Vector3, state := 0, target := Vector3.ZERO) -> Node3D:
	var g = GuardScript.new()
	g.route = data["route"]
	g.route_loop = data["loop"]
	g.route_wait = data["wait"]
	g.uniform_color = data["color"]
	g.start_state = state
	g.start_target = target
	g.position = pos
	guards_root.add_child(g)
	return g


func _on_reinforcements(_origin: Vector3) -> void:
	var yard: Array = [Vector3(0, 0.1, 40), Vector3(0, 0.1, 10), Vector3(0, 0.1, -20), Vector3(0, 0.1, 10)]
	var data := {"route": yard, "loop": true, "wait": 1.0, "color": Color(0.38, 0.18, 0.16)}
	for pt in level.reinforcement_points:
		_spawn_guard(data, pt, GuardScript.State.SEARCH, player.global_position)


func _on_alarm_changed(active: bool) -> void:
	if active:
		if _siren == null:
			_siren = AudioStreamPlayer.new()
			_siren.stream = Game.sounds["siren"]
			_siren.volume_db = -9.0
			add_child(_siren)
		_siren.play()
	elif _siren != null:
		_siren.stop()


func _on_mission_ended(success: bool, _reason: String) -> void:
	if _siren != null:
		_siren.stop()
	if success:
		await get_tree().create_timer(1.0).timeout
		Game.play_sound("explosion", null, -2.0)
		Game.detonation.emit()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	_frames += 1
	if not Game.mission_over and Game.playing and player != null and level.extraction_area.overlaps_body(player):
		if Game.charges_planted >= Game.CHARGES_REQUIRED:
			Game.end_mission(true, "You made the helicopter with seconds to spare. Behind you, Karakol Dam is finished.")
		else:
			_hint_timer -= delta
			if _hint_timer <= 0.0:
				_hint_timer = 7.0
				Game.post_message("The helicopter is waiting, but the dam has not been sabotaged yet.", 3.5)
	if _args.has("flowtest"):
		_run_flow_test()
	elif _args.has("selftest") or _args.has("shot"):
		_run_test_hooks()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN


# --------------------------------------------------------------------------------
# Developer test hooks
# --------------------------------------------------------------------------------

## Scripted run through the mission rules. Modes: win, lose (timer), combat (guards shoot), die.
func _run_flow_test() -> void:
	var mode := String(_args["flowtest"])
	var nodes := {}
	var valves: Array = []
	for m in level.map_markers:
		if m["node"] == null:
			continue
		match m["label"]:
			"1": nodes["comms"] = m["node"]
			"2": nodes["term"] = m["node"]
			"3": valves.append(m["node"])
	match _frames:
		5:
			if mode == "combat":
				# stand in the open in front of the gate guards, no cover
				player.global_position = Vector3(-7, 0.3, 36)
				player.set_yaw(0.0)
			elif mode == "die":
				player.take_damage(150.0)
		10:
			if mode in ["win", "lose"]:
				print("[flow] valve locked before terminal: ", not valves[0].can_use())
				nodes["comms"].complete()
				print("[flow] comms_disabled=", Game.comms_disabled)
				nodes["term"].complete()
				print("[flow] valve unlocked after terminal: ", valves[0].can_use())
				valves[0].complete()
				print("[flow] charges after 1st=", Game.charges_planted, " countdown=", Game.countdown)
				valves[1].complete()
				print("[flow] charges after 2nd=", Game.charges_planted, " countdown=", snappedf(Game.countdown, 0.1))
		12:
			if mode == "win":
				player.global_position = level.extraction_pos + Vector3(0, 0.5, 0)
			elif mode == "lose":
				Game.countdown = 0.4
	if _frames == 120 + (400 if mode == "combat" else 0):
		print("[flow] mode=%s mission_over=%s success=%s alarm=%s health=%d kills=%d" % [mode, Game.mission_over, Game.mission_success, Game.alarm, int(player.health), Game.stats["kills"]])
		var states := []
		for g in guards_root.get_children():
			states.append(g.state)
		print("[flow] guard states: ", states)
		print("[flow] DONE")
		get_tree().quit(0)

func _run_test_hooks() -> void:
	if _frames == 20 and _args.has("selftest"):
		var map: RID = level.nav_region.get_navigation_map()
		var pairs := [
			["spawn -> extraction", level.spawn_pos, level.extraction_pos],
			["spawn -> south gate -> hall (valve A)", level.spawn_pos, Vector3(-12, 0.1, -62)],
			["spawn -> west gap -> comms shed", level.spawn_pos, Vector3(-40, 0.1, 23)],
			["gate -> control tower terminal", Vector3(0, 0.1, 58), Vector3(33, 0.1, 20)],
			["valve B -> extraction", Vector3(12, 0.1, -62), level.extraction_pos],
		]
		for p in pairs:
			var path := NavigationServer3D.map_get_path(map, p[1], p[2], true)
			var end := path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
			print("[selftest] path %-40s points=%3d  end=%s  gap_to_goal=%.1f" % [p[0], path.size(), str(end), end.distance_to(p[2]) if path.size() > 0 else -1.0])
	if _frames == _test_frames:
		if _args.has("selftest"):
			var moved := 0
			for g in _start_positions:
				if is_instance_valid(g) and g.global_position.distance_to(_start_positions[g]) > 1.0:
					moved += 1
			print("[selftest] guards: %d, moved >1m: %d" % [_start_positions.size(), moved])
			for g in guards_root.get_children():
				print("[selftest]   guard state=%d awareness=%.2f pos=%s" % [g.state, g.awareness, str(g.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
			print("[selftest] player pos=%s health=%d" % [str(player.global_position), int(player.health)])
			print("[selftest] DONE")
			get_tree().quit(0)
		elif _args.has("shot"):
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(_args["shot"]))
			print("[shot] saved ", _args["shot"], " ", img.get_size())
			get_tree().quit(0)
