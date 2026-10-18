class_name CasinoWorld
extends Node3D
## 3D 呈現層:地板、牆、機台、顧客、放置預覽、攝影機。
## 這裡只「讀」模擬狀態、「呼叫」state.try_*,不自己改規則。

signal selection_changed(machine_id: int)
signal placing_changed()

var sim: Simulation
var camera: Camera3D
var machine_views: Dictionary = {}    # id -> {"root","body","seat","label"}
var customer_views: Dictionary = {}   # id -> MeshInstance3D
var selected_id: int = -1
var placing_type: String = ""
var placing_move_id: int = -1
var placing_rot: int = 0
var hover_cell: Vector2i = Vector2i(-1, -1)

var _ghost_machine: MeshInstance3D
var _ghost_seat: MeshInstance3D
var _sel_a: MeshInstance3D
var _sel_b: MeshInstance3D
var _cam_target: Vector3 = Vector3(Config.GRID_W * 0.5, 0.0, Config.GRID_H * 0.5)
var _cam_dist: float = 17.0


func setup(p_sim: Simulation) -> void:
	sim = p_sim
	_build_environment()
	_build_floor()
	_build_walls()
	_build_markers()
	_build_camera()
	_build_ghost_and_selection()
	sim.state.machine_added.connect(_on_machine_added)
	sim.state.machine_removed.connect(_on_machine_removed)
	sim.state.machine_moved.connect(_on_machine_moved)
	sim.state.round_resolved.connect(_on_round_resolved)


# ---------------------------------------------------------------- 建立場景

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, color: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _material(color)
	mi.position = pos
	if parent != null:
		parent.add_child(mi)
	else:
		add_child(mi)
	return mi


func _label3d(text: String, pos: Vector3, color: Color, size: int = 40) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	return l


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func pos_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x + 0.5, 0.0, p.y + 0.5)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.85)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	sun.light_energy = 0.9
	add_child(sun)


func _build_floor() -> void:
	var w: float = float(Config.GRID_W)
	var h: float = float(Config.GRID_H)
	_box(Vector3(w, 0.1, h), Color(0.12, 0.36, 0.22), Vector3(w * 0.5, -0.05, h * 0.5))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(Config.GRID_W + 1):
		im.surface_add_vertex(Vector3(i, 0.01, 0.0))
		im.surface_add_vertex(Vector3(i, 0.01, h))
	for j in range(Config.GRID_H + 1):
		im.surface_add_vertex(Vector3(0.0, 0.01, j))
		im.surface_add_vertex(Vector3(w, 0.01, j))
	im.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = im
	grid.material_override = _material(Color(0.0, 0.0, 0.0, 0.35), true)
	add_child(grid)


func _build_walls() -> void:
	var w: float = float(Config.GRID_W)
	var h: float = float(Config.GRID_H)
	var wall_color := Color(0.35, 0.33, 0.4)
	var t: float = 0.2
	var ht: float = 0.8
	_box(Vector3(w + 2 * t, ht, t), wall_color, Vector3(w * 0.5, ht * 0.5, -t * 0.5))
	_box(Vector3(w + 2 * t, ht, t), wall_color, Vector3(w * 0.5, ht * 0.5, h + t * 0.5))
	_box(Vector3(t, ht, h), wall_color, Vector3(w + t * 0.5, ht * 0.5, h * 0.5))
	# 左牆在入口與出口處留出缺口
	var gap_a: int = mini(Config.ENTRANCE.y, Config.EXIT.y)
	var gap_b: int = maxi(Config.ENTRANCE.y, Config.EXIT.y) + 1
	if gap_a > 0:
		_box(Vector3(t, ht, float(gap_a)), wall_color, Vector3(-t * 0.5, ht * 0.5, gap_a * 0.5))
	if gap_b < Config.GRID_H:
		var len2: float = float(Config.GRID_H - gap_b)
		_box(Vector3(t, ht, len2), wall_color, Vector3(-t * 0.5, ht * 0.5, gap_b + len2 * 0.5))


func _build_markers() -> void:
	var e: Vector3 = cell_to_world(Config.ENTRANCE)
	var x: Vector3 = cell_to_world(Config.EXIT)
	_box(Vector3(0.9, 0.04, 0.9), Color(0.2, 0.8, 0.3), e + Vector3(0.0, 0.02, 0.0))
	_box(Vector3(0.9, 0.04, 0.9), Color(0.85, 0.25, 0.25), x + Vector3(0.0, 0.02, 0.0))
	add_child(_label3d("IN", e + Vector3(-0.2, 0.9, 0.0), Color(0.6, 1.0, 0.6), 32))
	add_child(_label3d("OUT", x + Vector3(-0.2, 0.9, 0.0), Color(1.0, 0.6, 0.6), 32))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	_update_camera()


func _update_camera() -> void:
	var dir: Vector3 = Vector3(0.0, 1.0, 0.8).normalized()
	camera.position = _cam_target + dir * _cam_dist
	camera.look_at(_cam_target, Vector3.UP)


func _build_ghost_and_selection() -> void:
	_ghost_machine = _box(Vector3(0.8, 1.0, 0.8), Color(0.3, 1.0, 0.3, 0.55), Vector3.ZERO)
	_ghost_seat = _box(Vector3(0.55, 0.3, 0.55), Color(0.3, 1.0, 0.3, 0.55), Vector3.ZERO)
	_ghost_machine.visible = false
	_ghost_seat.visible = false
	_sel_a = _box(Vector3(0.98, 0.03, 0.98), Color(1.0, 0.9, 0.2, 0.8), Vector3.ZERO)
	_sel_b = _box(Vector3(0.98, 0.03, 0.98), Color(1.0, 0.9, 0.2, 0.8), Vector3.ZERO)
	_sel_a.visible = false
	_sel_b.visible = false


# ---------------------------------------------------------------- 機台視圖

func _on_machine_added(id: int) -> void:
	var m: MachineInstance = sim.state.machines[id]
	var def: MachineDef = MachineCatalog.get_def(m.type_id)
	var root := Node3D.new()
	add_child(root)
	var body: MeshInstance3D = _box(Vector3(0.8, 1.0, 0.8), def.color, Vector3.ZERO, root)
	var seat: MeshInstance3D = _box(Vector3(0.55, 0.3, 0.55), def.color.darkened(0.45), Vector3.ZERO, root)
	var label: Label3D = _label3d(def.id, Vector3.ZERO, Color.WHITE, 36)
	root.add_child(label)
	machine_views[id] = {"root": root, "body": body, "seat": seat, "label": label}
	_place_machine_view(id)


func _place_machine_view(id: int) -> void:
	var m: MachineInstance = sim.state.machines[id]
	var v: Dictionary = machine_views[id]
	(v["body"] as MeshInstance3D).position = cell_to_world(m.cell) + Vector3(0.0, 0.5, 0.0)
	(v["seat"] as MeshInstance3D).position = cell_to_world(m.seat_cell()) + Vector3(0.0, 0.15, 0.0)
	(v["label"] as Label3D).position = cell_to_world(m.cell) + Vector3(0.0, 1.3, 0.0)


func _on_machine_removed(id: int, _cell: Vector2i, _seat: Vector2i) -> void:
	if machine_views.has(id):
		(machine_views[id]["root"] as Node3D).queue_free()
		machine_views.erase(id)
	if selected_id == id:
		select(-1)


func _on_machine_moved(id: int, _old_cell: Vector2i, _old_seat: Vector2i) -> void:
	_place_machine_view(id)


func _on_round_resolved(machine_id: int, outcome: int, casino_net: int) -> void:
	if not machine_views.has(machine_id):
		return
	var m: MachineInstance = sim.state.machines.get(machine_id)
	if m == null:
		return
	var txt: String = ("+" if casino_net >= 0 else "") + Config.fmt_money(casino_net)
	if outcome == GamblingModel.Outcome.JACKPOT:
		txt = "JACKPOT! " + txt
	var col: Color = Color(0.5, 1.0, 0.5) if casino_net >= 0 else Color(1.0, 0.5, 0.4)
	var base: Vector3 = cell_to_world(m.cell) + Vector3(0.0, 1.8, 0.0)
	var pop: Label3D = _label3d(txt, base, col, 44)
	add_child(pop)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(pop, "position:y", base.y + 1.0, 1.0)
	tw.tween_property(pop, "modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(pop.queue_free)


# ---------------------------------------------------------------- 每幀同步

func sync_views() -> void:
	# 機台:使用中發光
	for id in machine_views:
		var m: MachineInstance = sim.state.machines.get(id)
		if m == null:
			continue
		var mat: StandardMaterial3D = (machine_views[id]["body"] as MeshInstance3D).material_override
		var def: MachineDef = MachineCatalog.get_def(m.type_id)
		mat.emission_enabled = m.state == MachineInstance.State.BUSY
		mat.emission = def.color * 0.7
	# 顧客
	var alive: Dictionary = {}
	for c: Customer in sim.customers.customers:
		alive[c.id] = true
		var v: MeshInstance3D = customer_views.get(c.id)
		if v == null:
			v = MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.2
			cap.height = 0.75
			v.mesh = cap
			v.material_override = _material(Color.WHITE)
			add_child(v)
			customer_views[c.id] = v
		v.position = pos_to_world(c.pos) + Vector3(0.0, 0.4, 0.0)
		var col: Color = Color(0.9, 0.9, 0.3)
		match c.state:
			Customer.State.WALK_TO_MACHINE: col = Color(0.4, 0.7, 1.0)
			Customer.State.PLAYING: col = Color(0.4, 1.0, 0.5)
			Customer.State.LEAVING: col = Color(0.7, 0.7, 0.7)
		(v.material_override as StandardMaterial3D).albedo_color = col
	for cid in customer_views.keys():
		if not alive.has(cid):
			(customer_views[cid] as MeshInstance3D).queue_free()
			customer_views.erase(cid)
	_update_ghost()
	_update_selection_marker()


func _placing_active() -> bool:
	return placing_type != "" or placing_move_id >= 0


func _placing_type_id() -> String:
	if placing_move_id >= 0 and sim.state.machines.has(placing_move_id):
		return (sim.state.machines[placing_move_id] as MachineInstance).type_id
	return placing_type


func _update_ghost() -> void:
	var show: bool = _placing_active() and hover_cell.x >= 0 and sim.state.in_bounds(hover_cell)
	_ghost_machine.visible = show
	_ghost_seat.visible = show
	if not show:
		return
	var tid: String = _placing_type_id()
	var seat: Vector2i = MachineInstance.seat_for(hover_cell, placing_rot)
	var ok: bool = sim.state.can_place(tid, hover_cell, placing_rot, placing_move_id) == ""
	if ok and placing_move_id < 0:
		ok = sim.state.cash >= MachineCatalog.get_def(tid).price_cents
	var col: Color = Color(0.3, 1.0, 0.3, 0.55) if ok else Color(1.0, 0.25, 0.25, 0.55)
	(_ghost_machine.material_override as StandardMaterial3D).albedo_color = col
	(_ghost_seat.material_override as StandardMaterial3D).albedo_color = col
	_ghost_machine.position = cell_to_world(hover_cell) + Vector3(0.0, 0.5, 0.0)
	_ghost_seat.position = cell_to_world(seat) + Vector3(0.0, 0.15, 0.0)


func _update_selection_marker() -> void:
	var m: MachineInstance = sim.state.machines.get(selected_id)
	_sel_a.visible = m != null
	_sel_b.visible = m != null
	if m == null:
		return
	_sel_a.position = cell_to_world(m.cell) + Vector3(0.0, 0.02, 0.0)
	_sel_b.position = cell_to_world(m.seat_cell()) + Vector3(0.0, 0.02, 0.0)


# ---------------------------------------------------------------- 操作

func select(id: int) -> void:
	selected_id = id
	selection_changed.emit(id)


func begin_place(type_id: String) -> void:
	placing_type = type_id
	placing_move_id = -1
	placing_rot = 0
	select(-1)
	placing_changed.emit()


func begin_move(machine_id: int) -> void:
	if not sim.state.machines.has(machine_id):
		return
	placing_type = ""
	placing_move_id = machine_id
	placing_rot = (sim.state.machines[machine_id] as MachineInstance).rot
	placing_changed.emit()


func cancel_placing() -> void:
	placing_type = ""
	placing_move_id = -1
	placing_changed.emit()


func rotate_placing() -> void:
	placing_rot = posmod(placing_rot + 1, 4)


func _mouse_cell() -> Vector2i:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mp)
	var dir: Vector3 = camera.project_ray_normal(mp)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return Vector2i(-1, -1)
	var p: Vector3 = hit
	return Vector2i(floori(p.x), floori(p.z))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_cell = _mouse_cell()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _placing_active():
				cancel_placing()
			else:
				select(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(8.0, _cam_dist - 1.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(30.0, _cam_dist + 1.0)
			_update_camera()
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.keycode == KEY_R:
				rotate_placing()
			elif k.keycode == KEY_ESCAPE:
				cancel_placing()


func _on_left_click() -> void:
	var cell: Vector2i = _mouse_cell()
	hover_cell = cell
	if _placing_active():
		if placing_move_id >= 0:
			var r: Dictionary = sim.state.try_move(placing_move_id, cell, placing_rot)
			if r["ok"]:
				cancel_placing()
		else:
			sim.state.try_buy_and_place(placing_type, cell, placing_rot)
	else:
		select(int(sim.state.occupancy.get(cell, -1)))


func _process(delta: float) -> void:
	var v: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.z += 1.0
	if v != Vector3.ZERO:
		_cam_target += v.normalized() * 8.0 * delta
		_cam_target.x = clampf(_cam_target.x, 0.0, float(Config.GRID_W))
		_cam_target.z = clampf(_cam_target.z, 0.0, float(Config.GRID_H))
		_update_camera()
