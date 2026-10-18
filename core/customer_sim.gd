class_name CustomerSim
extends RefCounted
## 顧客模擬:生成 -> 選機台 -> 走路 -> 遊玩 -> 離場。
## 尋路使用內建 AStarGrid2D;機器格是障礙,座位格只在有人坐時才是障礙。

var state: CasinoState
var rng: RandomNumberGenerator
var astar: AStarGrid2D
var customers: Array = []          # Array of Customer
var next_id: int = 1
var spawn_progress: float = 0.0
var spawn_threshold: float = 1.0


func _init(casino: CasinoState, random: RandomNumberGenerator) -> void:
	state = casino
	rng = random
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, Config.GRID_W, Config.GRID_H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	spawn_threshold = rng.randf_range(0.5, 1.5)
	state.machine_added.connect(_on_machine_added)
	state.machine_removed.connect(_on_machine_removed)
	state.machine_moved.connect(_on_machine_moved)


# ---------------------------------------------------------------- 事件

func _on_machine_added(id: int) -> void:
	var m: MachineInstance = state.machines[id]
	astar.set_point_solid(m.cell, true)


func _on_machine_removed(id: int, cell: Vector2i, seat: Vector2i) -> void:
	astar.set_point_solid(cell, false)
	astar.set_point_solid(seat, false)
	# 正在走向這台機台的顧客:改回等待,重新找機台
	for c: Customer in customers:
		if c.machine_id == id and c.state == Customer.State.WALK_TO_MACHINE:
			c.machine_id = -1
			c.state = Customer.State.WAITING


func _on_machine_moved(id: int, old_cell: Vector2i, old_seat: Vector2i) -> void:
	astar.set_point_solid(old_cell, false)
	astar.set_point_solid(old_seat, false)
	var m: MachineInstance = state.machines[id]
	astar.set_point_solid(m.cell, true)


# ---------------------------------------------------------------- 主迴圈

func step(dt: float) -> void:
	_spawn(dt)
	for c: Customer in customers:
		c.age += dt
		_update_customer(c, dt)
	var alive: Array = []
	for c: Customer in customers:
		if c.state != Customer.State.GONE:
			alive.append(c)
	customers = alive


func _spawn(dt: float) -> void:
	var lam: float = state.traffic_per_day()
	spawn_progress += dt * lam / Config.DAY_SECONDS
	if spawn_progress < spawn_threshold:
		return
	spawn_progress = 0.0
	spawn_threshold = rng.randf_range(0.5, 1.5)   # 到達間隔 = 平均 * U(0.5, 1.5),有界
	if customers.size() >= Config.MAX_INSIDE:
		return
	var c := Customer.new()
	c.id = next_id
	next_id += 1
	c.pos = Vector2(Config.ENTRANCE)
	c.bankroll = rng.randi_range(Config.BANKROLL_MIN / Config.CENTS, Config.BANKROLL_MAX / Config.CENTS) * Config.CENTS
	c.rounds_target = rng.randi_range(Config.ROUNDS_MIN, Config.ROUNDS_MAX)
	c.state = Customer.State.WAITING
	customers.append(c)
	state.day_stats["arrivals"] += 1


func _cell_of(c: Customer) -> Vector2i:
	return Vector2i(roundi(c.pos.x), roundi(c.pos.y))


func _update_customer(c: Customer, dt: float) -> void:
	match c.state:
		Customer.State.WAITING:
			c.wait_time += dt
			if _try_assign(c):
				return
			if c.wait_time >= Config.WAIT_LIMIT:
				_leave_unserved(c)
		Customer.State.WALK_TO_MACHINE:
			if _walk(c, dt):
				_sit_down(c)
		Customer.State.PLAYING:
			_play(c, dt)
		Customer.State.LEAVING:
			if _walk(c, dt):
				c.state = Customer.State.GONE
				state.day_stats["departures"] += 1


# ---------------------------------------------------------------- 行為

## 找最近的空機台(賭注 <= 本金/3、且有路可走),找到就預約。
func _try_assign(c: Customer) -> bool:
	var from: Vector2i = _cell_of(c)
	var best_id: int = -1
	var best_path: Array[Vector2i] = []
	for id in state.machines:
		var m: MachineInstance = state.machines[id]
		if m.state != MachineInstance.State.IDLE:
			continue
		var def: MachineDef = MachineCatalog.get_def(m.type_id)
		if def.wager_cents * Config.MIN_ROUNDS_AFFORDABLE > c.bankroll:
			continue
		var p: Array[Vector2i] = astar.get_id_path(from, m.seat_cell())
		if p.is_empty():
			continue
		if best_id == -1 or p.size() < best_path.size():
			best_id = id
			best_path = p
	if best_id == -1:
		return false
	var chosen: MachineInstance = state.machines[best_id]
	chosen.state = MachineInstance.State.RESERVED
	c.machine_id = best_id
	c.path = best_path
	c.path_idx = 0
	c.stop_loss = MachineCatalog.get_def(chosen.type_id).wager_cents * Config.STOP_LOSS_WAGERS
	c.state = Customer.State.WALK_TO_MACHINE
	return true


## 沿路徑走;走完回傳 true。
func _walk(c: Customer, dt: float) -> bool:
	var remaining: float = Config.WALK_SPEED * dt
	while remaining > 0.0 and c.path_idx < c.path.size():
		var target: Vector2 = Vector2(c.path[c.path_idx])
		var d: float = c.pos.distance_to(target)
		if d <= remaining:
			c.pos = target
			remaining -= d
			c.path_idx += 1
		else:
			c.pos += (target - c.pos) / d * remaining
			remaining = 0.0
	return c.path_idx >= c.path.size()


func _sit_down(c: Customer) -> void:
	var m: MachineInstance = state.machines.get(c.machine_id)
	if m == null:
		c.machine_id = -1
		c.state = Customer.State.WAITING
		return
	m.state = MachineInstance.State.BUSY
	astar.set_point_solid(m.seat_cell(), true)
	c.pos = Vector2(m.seat_cell())
	c.round_timer = MachineCatalog.get_def(m.type_id).round_seconds
	c.state = Customer.State.PLAYING


func _play(c: Customer, dt: float) -> void:
	var m: MachineInstance = state.machines.get(c.machine_id)
	if m == null:
		_start_leaving(c)
		return
	m.busy_time += dt
	c.round_timer -= dt
	if c.round_timer > 0.0:
		return
	var def: MachineDef = MachineCatalog.get_def(m.type_id)
	var cfg: MachineConfig = state.configs[m.type_id]
	var res: Dictionary = GamblingModel.resolve(cfg, def.wager_cents, rng)
	var payout: int = res["payout"]
	c.bankroll += payout - def.wager_cents
	c.wagered += def.wager_cents
	c.paid += payout
	c.rounds_played += 1
	state.apply_round(m.id, def.wager_cents, payout, res["outcome"])
	if c.wagered - c.paid >= c.stop_loss:
		c.hit_limit = true
	if c.bankroll < def.wager_cents:
		c.hit_limit = true
	if c.hit_limit or c.rounds_played >= c.rounds_target:
		_finish_served(c, m)
	else:
		c.round_timer += def.round_seconds


func _finish_served(c: Customer, m: MachineInstance) -> void:
	var rho: float = float(c.paid) / float(maxi(c.wagered, 1))
	var s: float = Config.SAT_BASE + Config.SAT_RHO_SLOPE * (rho - Config.SAT_RHO_REF)
	if c.hit_limit:
		s -= Config.SAT_LIMIT_PENALTY
	s = clampf(s, 0.0, 100.0)
	state.record_departure(s, true)
	astar.set_point_solid(m.seat_cell(), false)
	m.state = MachineInstance.State.IDLE
	c.machine_id = -1
	c.pos = Vector2(m.seat_cell())
	_start_leaving(c)


func _leave_unserved(c: Customer) -> void:
	state.record_departure(Config.UNSERVED_SATISFACTION, false)
	_start_leaving(c)


func _start_leaving(c: Customer) -> void:
	var p: Array[Vector2i] = astar.get_id_path(_cell_of(c), Config.EXIT)
	if p.is_empty():
		c.state = Customer.State.GONE      # 找不到路:直接消失,不卡住
		state.day_stats["departures"] += 1
		return
	c.path = p
	c.path_idx = 0
	c.state = Customer.State.LEAVING
