extends CanvasLayer
## All 2D UI: HUD, tactical map, title / pause / mission-end screens.

signal start_pressed

const MAP_PX := 640.0

var player = null
var level = null

var _root: Control
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _health_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _reload_label: Label
var _obj_labels: Array = []
var _prompt_box: VBoxContainer
var _prompt_label: Label
var _prompt_bar: ProgressBar
var _msg_label: Label
var _msg_time := 0.0
var _msg_total := 1.0
var _alarm_label: Label
var _count_label: Label
var _vis_box: VBoxContainer
var _vis_bar: ProgressBar
var _vis_label: Label
var _vignette: TextureRect
var _flash: ColorRect
var _crosshair: Control
var _damage := 0.0
var _screen := "loading"

var _loading: Control
var _title: Control
var _pause: Control
var _end: Control
var _end_title: Label
var _end_reason: Label
var _end_stats: Label
var _map: Control
var _map_vp: SubViewport
var _map_cam: Camera3D
var _map_draw: Control
var _map_open := false
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_hud()
	_build_map()
	_build_screens()
	Game.message_posted.connect(_on_message)
	Game.objectives_changed.connect(_refresh_objectives)
	Game.mission_ended.connect(_on_mission_ended)
	Game.player_hit.connect(func(_p): _damage = minf(1.0, _damage + 0.55))
	Game.detonation.connect(_on_detonation)
	_refresh_objectives()
	show_loading()


# --------------------------------------------------------------------------------
# Construction helpers
# --------------------------------------------------------------------------------

func _label(text: String, size: int, color := Color.WHITE, parent: Node = null, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _root).add_child(l)
	return l


func _style(bg := Color(0.04, 0.06, 0.09, 0.86), margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color(1.0, 0.62, 0.24, 0.45)
	s.set_content_margin_all(margin)
	return s


func _bar(w: float, h: float, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _button(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _fullrect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


# --------------------------------------------------------------------------------
# HUD
# --------------------------------------------------------------------------------

func _build_hud() -> void:
	# damage vignette
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.9, 0, 0, 0), Color(0.9, 0, 0, 0), Color(0.75, 0, 0, 0.95)])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullrect(_vignette)
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	# crosshair
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullrect(_crosshair)
	_crosshair.draw.connect(_draw_crosshair)
	_root.add_child(_crosshair)

	# objectives (top-left)
	var obj_panel := PanelContainer.new()
	obj_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.08, 0.62), 12))
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.position = Vector2(16, 16)
	_root.add_child(obj_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 4)
	obj_panel.add_child(ov)
	_label("OBJECTIVES", 15, Color(1.0, 0.7, 0.3), ov, 2)
	for i in 4:
		var l := _label("", 16, Color.WHITE, ov, 3)
		_obj_labels.append(l)

	# health (bottom-left)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 3)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hv)
	hv.anchor_top = 1.0
	hv.anchor_bottom = 1.0
	hv.offset_left = 20
	hv.offset_bottom = -20
	hv.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_health_label = _label("HEALTH 100", 16, Color.WHITE, hv, 3)
	_health_bar = _bar(280, 16, Color(0.3, 0.85, 0.4))
	_health_bar.value = 1.0
	_health_fill = _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	hv.add_child(_health_bar)

	# ammo (bottom-right)
	var av := VBoxContainer.new()
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(av)
	av.anchor_left = 1.0
	av.anchor_right = 1.0
	av.anchor_top = 1.0
	av.anchor_bottom = 1.0
	av.offset_right = -20
	av.offset_bottom = -20
	av.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	av.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapon_label = _label("", 15, Color(1.0, 0.7, 0.3), av, 3)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label = _label("", 40, Color.WHITE, av, 5)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reload_label = _label("", 16, Color(1.0, 0.85, 0.3), av, 3)
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# interaction prompt
	_prompt_box = VBoxContainer.new()
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.anchor_left = 0.5
	_prompt_box.anchor_right = 0.5
	_prompt_box.anchor_top = 0.62
	_prompt_box.anchor_bottom = 0.62
	_prompt_box.offset_left = -300
	_prompt_box.offset_right = 300
	_prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_prompt_box)
	_prompt_label = _label("", 20, Color(1, 1, 1), _prompt_box, 4)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_bar = _bar(260, 10, Color(1.0, 0.7, 0.25))
	_prompt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt_box.add_child(_prompt_bar)
	_prompt_box.visible = false

	# messages / alarm / countdown (top-centre)
	_alarm_label = _label("", 26, Color(1.0, 0.25, 0.2), _root, 6)
	_alarm_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alarm_label.offset_top = 14
	_alarm_label.offset_left = -400
	_alarm_label.offset_right = 400
	_alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alarm_label.visible = false
	_count_label = _label("", 34, Color(1.0, 0.85, 0.3), _root, 6)
	_count_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_count_label.offset_top = 48
	_count_label.offset_left = -400
	_count_label.offset_right = 400
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.visible = false
	_msg_label = _label("", 22, Color(1, 1, 1), _root, 5)
	_msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_label.offset_top = 190
	_msg_label.offset_left = -450
	_msg_label.offset_right = 450
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# detection meter (bottom-centre)
	_vis_box = VBoxContainer.new()
	_vis_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vis_box)
	_vis_box.anchor_left = 0.5
	_vis_box.anchor_right = 0.5
	_vis_box.anchor_top = 1.0
	_vis_box.anchor_bottom = 1.0
	_vis_box.offset_left = -120
	_vis_box.offset_right = 120
	_vis_box.offset_bottom = -28
	_vis_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vis_label = _label("DETECTION", 13, Color(1.0, 0.9, 0.5), _vis_box, 3)
	_vis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vis_bar = _bar(240, 8, Color(1.0, 0.75, 0.2))
	_vis_box.add_child(_vis_bar)
	_vis_box.visible = false

	# white flash (detonation)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullrect(_flash)
	_root.add_child(_flash)


func _draw_crosshair() -> void:
	if player == null or not player.alive or _screen != "playing":
		return
	var c := _crosshair.size * 0.5
	var col := Color(1, 1, 1, 0.9)
	var gap: float = 5.0 + player.spread_now * 6.0
	if player.aiming:
		_crosshair.draw_circle(c, 1.6, col)
		return
	var l := 8.0
	_crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(gap + l, 0), col, 2.0)
	_crosshair.draw_line(c - Vector2(gap, 0), c - Vector2(gap + l, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + l), col, 2.0)
	_crosshair.draw_line(c - Vector2(0, gap), c - Vector2(0, gap + l), col, 2.0)
	_crosshair.draw_circle(c, 1.4, col)


func bind_player(p) -> void:
	player = p
	p.health_changed.connect(func(_h): _refresh_player())
	p.ammo_changed.connect(_refresh_player)
	p.weapon_changed.connect(_refresh_player)
	_refresh_player()


func _refresh_player() -> void:
	if player == null:
		return
	var hp: float = player.health
	_health_bar.value = hp / player.MAX_HEALTH
	_health_label.text = "HEALTH  %d" % int(ceil(hp))
	var f: float = hp / player.MAX_HEALTH
	_health_fill.bg_color = Color(0.3, 0.85, 0.4).lerp(Color(0.95, 0.2, 0.15), 1.0 - clampf(f * 1.6, 0.0, 1.0))
	var w: Dictionary = player.weapons[player.weapon_index]
	_weapon_label.text = w["name"]
	_ammo_label.text = "%d / %d" % [w["mag"], w["reserve"]]


func _refresh_objectives() -> void:
	var items := [
		["Destroy the comms relay", Game.comms_disabled],
		["Download sabotage plans (tower)", Game.terminal_done],
		["Plant charges on both valves (%d/%d)" % [Game.charges_planted, Game.CHARGES_REQUIRED], Game.charges_planted >= Game.CHARGES_REQUIRED],
		["Reach extraction on the ridge", Game.mission_success],
	]
	var active_found := false
	for i in items.size():
		var done: bool = items[i][1]
		var l: Label = _obj_labels[i]
		if done:
			l.text = "[x] " + items[i][0]
			l.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
		elif not active_found and i != 0:
			active_found = true
			l.text = "[>] " + items[i][0]
			l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		else:
			l.text = "[ ] " + items[i][0]
			l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			if i == 0:
				l.text += "  (optional)"


func _on_message(text: String, seconds: float) -> void:
	_msg_label.text = text
	_msg_time = seconds
	_msg_total = maxf(0.5, seconds)


func _on_detonation() -> void:
	var tw := create_tween()
	_flash.color = Color(1, 0.95, 0.85, 1)
	tw.tween_property(_flash, "color:a", 0.0, 2.5)


# --------------------------------------------------------------------------------
# Tactical map
# --------------------------------------------------------------------------------

func _build_map() -> void:
	_map = Control.new()
	_fullrect(_map)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.visible = false
	_root.add_child(_map)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullrect(bg)
	_map.add_child(bg)

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	holder.size = Vector2(MAP_PX, MAP_PX)
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.offset_left = -MAP_PX * 0.5
	holder.offset_right = MAP_PX * 0.5
	holder.offset_top = -MAP_PX * 0.5 + 10.0
	holder.offset_bottom = MAP_PX * 0.5 + 10.0
	_map.add_child(holder)

	_map_vp = SubViewport.new()
	_map_vp.size = Vector2i(768, 768)
	_map_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_map_vp.msaa_3d = Viewport.MSAA_DISABLED
	holder.add_child(_map_vp)
	_map_cam = Camera3D.new()
	_map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_cam.size = 230.0
	_map_cam.near = 1.0
	_map_cam.far = 400.0
	_map_cam.cull_mask = 1
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	_map_cam.environment = env
	_map_vp.add_child(_map_cam)
	_map_cam.position = Vector3(0, 150, 0)
	_map_cam.rotation_degrees = Vector3(-90, 0, 0)

	var tr := TextureRect.new()
	tr.texture = _map_vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(tr)

	_map_draw = Control.new()
	_map_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_draw.draw.connect(_draw_map)
	holder.add_child(_map_draw)

	var title := _label("TACTICAL MAP", 22, Color(1.0, 0.7, 0.3), _map, 3)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 14
	title.offset_left = -200
	title.offset_right = 200
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _label("Press M to close.   1 = comms relay   2 = control tower   3 = coolant valves   4 = extraction   (north is up)", 15, Color(0.85, 0.85, 0.85), _map, 3)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -40
	hint.offset_left = -500
	hint.offset_right = 500
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _w2m(p: Vector3) -> Vector2:
	var half := 115.0
	var s: Vector2 = _map_draw.size
	return Vector2((p.x + half) / (half * 2.0) * s.x, (p.z + half) / (half * 2.0) * s.y)


func _draw_map() -> void:
	var s: Vector2 = _map_draw.size
	_map_draw.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0.7, 0.3, 0.8), false, 2.0)
	var font := ThemeDB.fallback_font
	if level != null:
		for m in level.map_markers:
			var p := _w2m(m["pos"])
			var node = m["node"]
			var done := false
			var locked := false
			if node == null:
				done = Game.mission_success
				locked = Game.charges_planted < Game.CHARGES_REQUIRED
			else:
				done = node.done
				locked = not node.is_unlocked()
			var col := Color(1.0, 0.8, 0.2)
			if done:
				col = Color(0.4, 0.9, 0.5)
			elif locked:
				col = Color(0.6, 0.6, 0.65)
			var r := 10.0
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			_map_draw.draw_colored_polygon(pts, col)
			_map_draw.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.9), 2.0)
			_map_draw.draw_string(font, p + Vector2(-5, 6), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0))
	if player != null:
		var pp := _w2m(player.global_position)
		var fwd: Vector3 = -player.global_transform.basis.z
		var d := Vector2(fwd.x, fwd.z).normalized()
		var n := Vector2(-d.y, d.x)
		var tri := PackedVector2Array([pp + d * 14.0, pp - d * 8.0 + n * 8.0, pp - d * 8.0 - n * 8.0])
		_map_draw.draw_colored_polygon(tri, Color(0.3, 0.8, 1.0))
		_map_draw.draw_string(font, pp + Vector2(12, -10), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.95, 1.0))


func _set_map(open: bool) -> void:
	_map_open = open
	_map.visible = open
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if open:
		_map_draw.queue_redraw()


# --------------------------------------------------------------------------------
# Screens
# --------------------------------------------------------------------------------

func _centered_panel(width: float) -> Array:
	var screen := Control.new()
	_fullrect(screen)
	_root.add_child(screen)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.82)
	_fullrect(dim)
	screen.add_child(dim)
	var cc := CenterContainer.new()
	_fullrect(cc)
	screen.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	pc.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.1, 0.94), 24))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return [screen, vb]


func _build_screens() -> void:
	# Loading
	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.02, 0.03, 0.04, 1.0)
	_fullrect(_loading)
	_root.add_child(_loading)
	var ll := _label("PREPARING MISSION...", 28, Color(1.0, 0.7, 0.3), _loading, 3)
	ll.set_anchors_preset(Control.PRESET_CENTER)
	ll.offset_left = -300
	ll.offset_right = 300
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Title / briefing
	var t := _centered_panel(820)
	_title = t[0]
	var tv: VBoxContainer = t[1]
	var tt := _label("BLACKOUT AT KARAKOL DAM", 40, Color(1.0, 0.7, 0.3), tv, 4)
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("A tactical stealth shooter", 16, Color(0.8, 0.85, 0.9), tv, 2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var brief := _label("MISSION BRIEFING\nA mercenary crew holds the Karakol hydroelectric dam. You are alone and the extraction helicopter will wait on the ridge to the east. Get in, download the sabotage plans from the control tower, plant charges on both coolant valves in the turbine hall, then reach the ridge before they blow.\nDestroying the comms relay (west shed) stops the guards from calling reinforcements. Two ways in: the main gate (south) or the service gap in the west fence.", 16, Color(0.92, 0.92, 0.92), tv, 2)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ctrl := _label("CONTROLS\nWASD move    Shift sprint    Ctrl / C crouch    Space jump    Mouse look\nLeft mouse fire    Right mouse aim    R reload    1 / 2 or wheel switch weapon\nE (hold) use / plant    M tactical map    Esc pause", 15, Color(0.7, 0.85, 1.0), tv, 2)
	ctrl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tip := _label("TIP: the silenced pistol is quiet and a headshot is an instant kill. The rifle is loud and will wake up the whole base. Crouching halves how far guards can see you.", 14, Color(0.75, 0.75, 0.75), tv, 2)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 16)
	tv.add_child(bh)
	_button("START MISSION", _on_start, bh)
	_button("QUIT", func(): get_tree().quit(), bh)
	_title.visible = false

	# Pause
	var p := _centered_panel(420)
	_pause = p[0]
	var pv: VBoxContainer = p[1]
	var pt := _label("PAUSED", 34, Color(1.0, 0.7, 0.3), pv, 3)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pb := VBoxContainer.new()
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	pb.add_theme_constant_override("separation", 10)
	pv.add_child(pb)
	_button("RESUME", func(): _set_paused(false), pb).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button("RESTART MISSION", _restart, pb).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button("QUIT", func(): get_tree().quit(), pb).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause.visible = false

	# End screen
	var e := _centered_panel(560)
	_end = e[0]
	var ev: VBoxContainer = e[1]
	_end_title = _label("", 38, Color.WHITE, ev, 4)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_reason = _label("", 17, Color(0.9, 0.9, 0.9), ev, 2)
	_end_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_stats = _label("", 16, Color(0.75, 0.85, 1.0), ev, 2)
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var eb := VBoxContainer.new()
	eb.alignment = BoxContainer.ALIGNMENT_CENTER
	eb.add_theme_constant_override("separation", 10)
	ev.add_child(eb)
	_button("TRY AGAIN", _restart, eb).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button("QUIT", func(): get_tree().quit(), eb).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_end.visible = false


func show_loading() -> void:
	_screen = "loading"
	_loading.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_title() -> void:
	_screen = "title"
	_loading.visible = false
	_title.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func begin_play() -> void:
	_loading.visible = false
	_title.visible = false
	_screen = "playing"
	Game.playing = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_start() -> void:
	begin_play()
	start_pressed.emit()


func _restart() -> void:
	Game.skip_menu = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _set_paused(p: bool) -> void:
	if p:
		_screen = "paused"
		_pause.visible = true
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_screen = "playing"
		_pause.visible = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_mission_ended(success: bool, reason: String) -> void:
	await get_tree().create_timer(1.4 if not success else 0.6, true).timeout
	_set_map(false)
	_screen = "ended"
	_end.visible = true
	_end_title.text = "MISSION COMPLETE" if success else "MISSION FAILED"
	_end_title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55) if success else Color(1.0, 0.35, 0.3))
	_end_reason.text = reason
	var secs := int(Game.stats["time"])
	_end_stats.text = "Time %02d:%02d      Guards down %d (headshots %d)      Alarms raised %d      Shots fired %d" % [
		secs / 60, secs % 60, Game.stats["kills"], Game.stats["headshots"], Game.stats["alarms"], Game.stats["shots"]]
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --------------------------------------------------------------------------------
# Per-frame
# --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _screen == "playing":
		if event.is_action_pressed("pause"):
			if _map_open:
				_set_map(false)
			else:
				_set_paused(true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("map"):
			_set_map(not _map_open)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.mission_over:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif _screen == "paused":
		if event.is_action_pressed("pause"):
			_set_paused(false)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	_crosshair.queue_redraw()

	# damage vignette
	_damage = maxf(0.0, _damage - delta * 0.9)
	var low := 0.0
	if player != null and player.alive:
		low = clampf(1.0 - player.health / 40.0, 0.0, 1.0) * (0.35 + 0.15 * sin(_t * 5.0))
	_vignette.modulate.a = clampf(maxf(_damage, low), 0.0, 1.0)

	# messages
	if _msg_time > 0.0:
		_msg_time -= delta
		_msg_label.modulate.a = clampf(_msg_time / minf(1.0, _msg_total), 0.0, 1.0)
		if _msg_time <= 0.0:
			_msg_label.text = ""

	# alarm + countdown
	_alarm_label.visible = Game.alarm and not Game.mission_over
	if _alarm_label.visible:
		_alarm_label.text = "ALARM  -  REINFORCEMENTS INBOUND"
		_alarm_label.modulate.a = 0.6 + 0.4 * sin(_t * 8.0)
	_count_label.visible = Game.countdown > 0.0 and not Game.mission_over
	if _count_label.visible:
		var c := int(ceil(Game.countdown))
		_count_label.text = "DETONATION IN  %02d:%02d" % [c / 60, c % 60]
		var urgent := Game.countdown < 30.0
		_count_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if urgent else Color(1.0, 0.85, 0.3))
		_count_label.modulate.a = 1.0 if not urgent else (0.65 + 0.35 * sin(_t * 10.0))

	if player == null:
		return

	# reload text
	_reload_label.text = "RELOADING..." if player.reload_left > 0.0 else ""
	var w: Dictionary = player.weapons[player.weapon_index]
	_ammo_label.text = "%d / %d" % [w["mag"], w["reserve"]]

	# interaction prompt
	var it = player.interact_target
	if it != null and not it.done and _screen == "playing" and not _map_open:
		_prompt_box.visible = true
		if it.can_use():
			_prompt_label.text = it.get_prompt()
			_prompt_bar.visible = true
			_prompt_bar.value = clampf(player.interact_progress / it.hold_time, 0.0, 1.0)
		else:
			_prompt_label.text = "[LOCKED]  " + it.locked_message
			_prompt_bar.visible = false
	else:
		_prompt_box.visible = false

	# detection meter
	var peak := 0.0
	var combat := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.state == 3:
			combat = true
		elif g.seeing_player:
			peak = maxf(peak, g.awareness)
	if combat:
		peak = 1.0
	_vis_box.visible = peak > 0.03 and not Game.mission_over
	if _vis_box.visible:
		_vis_bar.value = peak
		_vis_label.text = "SPOTTED" if combat else "DETECTION"
		_vis_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if combat else Color(1.0, 0.9, 0.5))

	if _map_open:
		_map_draw.queue_redraw()
