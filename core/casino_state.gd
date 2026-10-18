class_name CasinoState
extends RefCounted
## 賭場的「規則層」:現金、機台、格子佔用、帳本、聲望、債務。
## 不引用任何 Node / UI。所有玩家操作都從 try_* 函式進來,UI 只負責呼叫與顯示。

signal cash_changed(cash: int)
signal machine_added(id: int)
signal machine_removed(id: int, cell: Vector2i, seat: Vector2i)
signal machine_moved(id: int, old_cell: Vector2i, old_seat: Vector2i)
signal round_resolved(machine_id: int, outcome: int, casino_net: int)
signal day_settled(summary: Dictionary)
signal collector_arrived(fee: int)
signal game_ended(reason: String)
signal message(text: String)

var cash: int = Config.START_CASH
var day: int = 1
var time_in_day: float = 0.0
var reputation: float = Config.START_REPUTATION
var machines: Dictionary = {}     # id -> MachineInstance
var occupancy: Dictionary = {}    # Vector2i -> machine id(機器格與座位格都算)
var configs: Dictionary = {}      # type_id -> MachineConfig(玩家可調整)
var next_machine_id: int = 1
var negative_days: int = 0
var in_debt_episode: bool = false
var last_collector_day: int = -999
var is_game_over: bool = false
var game_over_reason: String = ""
var day_stats: Dictionary = {}
var history: Array = []           # 每日結算摘要


func _init() -> void:
	for type_id in MachineCatalog.ids():
		configs[type_id] = MachineCatalog.get_def(type_id).default_config.clone()
	_new_day_stats()


func _new_day_stats() -> void:
	day_stats = {
		"opening_cash": cash, "wagers": 0, "payouts": 0, "purchases": 0, "resale": 0,
		"rent": 0, "fees": 0, "arrivals": 0, "departures": 0, "unserved": 0,
		"sat_sum": 0.0, "sat_count": 0, "rounds": 0, "jackpots": 0,
	}


func _change_cash(delta: int) -> void:
	cash += delta
	cash_changed.emit(cash)


func _fail(reason: String) -> Dictionary:
	message.emit(reason)
	return {"ok": false, "reason": reason, "id": -1}


# ---------------------------------------------------------------- 放置規則

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < Config.GRID_W and c.y < Config.GRID_H


## 回傳空字串代表可放置,否則回傳原因。
func can_place(type_id: String, cell: Vector2i, rot: int, ignore_id: int = -1) -> String:
	if not MachineCatalog.has_type(type_id):
		return "未知的機台型號"
	var seat: Vector2i = MachineInstance.seat_for(cell, rot)
	for c in [cell, seat]:
		if not in_bounds(c):
			return "超出場地範圍"
		if c == Config.ENTRANCE or c == Config.EXIT:
			return "不能放在出入口"
		if occupancy.has(c) and occupancy[c] != ignore_id:
			return "格子已被佔用"
	return ""


func try_buy_and_place(type_id: String, cell: Vector2i, rot: int) -> Dictionary:
	if is_game_over:
		return _fail("遊戲已結束")
	var why: String = can_place(type_id, cell, rot)
	if why != "":
		return _fail(why)
	var def: MachineDef = MachineCatalog.get_def(type_id)
	if cash < def.price_cents:
		return _fail("資金不足")
	var m := MachineInstance.new()
	m.id = next_machine_id
	next_machine_id += 1
	m.type_id = type_id
	m.cell = cell
	m.rot = posmod(rot, 4)
	machines[m.id] = m
	occupancy[m.cell] = m.id
	occupancy[m.seat_cell()] = m.id
	day_stats["purchases"] += def.price_cents
	_change_cash(-def.price_cents)
	machine_added.emit(m.id)
	return {"ok": true, "reason": "", "id": m.id}


@warning_ignore("integer_division")
func resale_value(m: MachineInstance) -> int:
	return MachineCatalog.get_def(m.type_id).price_cents * Config.RESALE_PCT / 100


func try_sell(id: int) -> Dictionary:
	if is_game_over:
		return _fail("遊戲已結束")
	if not machines.has(id):
		return _fail("找不到機台")
	var m: MachineInstance = machines[id]
	if m.state == MachineInstance.State.BUSY:
		return _fail("機台使用中,無法賣出")
	var refund: int = resale_value(m)
	var cell: Vector2i = m.cell
	var seat: Vector2i = m.seat_cell()
	occupancy.erase(cell)
	occupancy.erase(seat)
	machines.erase(id)
	day_stats["resale"] += refund
	_change_cash(refund)
	machine_removed.emit(id, cell, seat)
	_check_dead_end()
	return {"ok": true, "reason": "", "id": id}


func try_move(id: int, cell: Vector2i, rot: int) -> Dictionary:
	if is_game_over:
		return _fail("遊戲已結束")
	if not machines.has(id):
		return _fail("找不到機台")
	var m: MachineInstance = machines[id]
	if m.state != MachineInstance.State.IDLE:
		return _fail("機台使用中,無法移動")
	var why: String = can_place(m.type_id, cell, rot, id)
	if why != "":
		return _fail(why)
	var old_cell: Vector2i = m.cell
	var old_seat: Vector2i = m.seat_cell()
	occupancy.erase(old_cell)
	occupancy.erase(old_seat)
	m.cell = cell
	m.rot = posmod(rot, 4)
	occupancy[m.cell] = id
	occupancy[m.seat_cell()] = id
	machine_moved.emit(id, old_cell, old_seat)
	return {"ok": true, "reason": "", "id": id}


# ---------------------------------------------------------------- 帳本與聲望

## 一回合結算:賭注與賠付一起寫進帳本(原子操作)。
func apply_round(machine_id: int, wager: int, payout: int, outcome: int) -> void:
	var m: MachineInstance = machines.get(machine_id)
	if m != null:
		m.rounds += 1
		m.wagers += wager
		m.payouts += payout
		if outcome == GamblingModel.Outcome.JACKPOT:
			m.jackpots += 1
	day_stats["wagers"] += wager
	day_stats["payouts"] += payout
	day_stats["rounds"] += 1
	if outcome == GamblingModel.Outcome.JACKPOT:
		day_stats["jackpots"] += 1
	_change_cash(wager - payout)
	round_resolved.emit(machine_id, outcome, wager - payout)


## 顧客離場時呼叫:即時更新聲望(跌快漲慢)。
func record_departure(sat: float, served: bool) -> void:
	var alpha: float = Config.REP_ALPHA_UP if sat > reputation else Config.REP_ALPHA_DOWN
	reputation = clampf(reputation + alpha * (sat - reputation), 0.0, 100.0)
	day_stats["sat_sum"] += sat
	day_stats["sat_count"] += 1
	if not served:
		day_stats["unserved"] += 1


## 預期每日到客數。聲望為 0 時是 0(無下限),沒有人為上限。
func traffic_per_day() -> float:
	return Config.TRAFFIC_BASE_PER_DAY * pow(maxf(reputation, 0.0) / 50.0, Config.TRAFFIC_GAMMA)


@warning_ignore("integer_division")
func net_worth() -> int:
	var total: int = cash
	for id in machines:
		total += resale_value(machines[id])
	return total


# ---------------------------------------------------------------- 每日結算與失敗

func settle_day() -> Dictionary:
	var s: Dictionary = day_stats
	s["rent"] = Config.RENT_PER_DAY
	_change_cash(-Config.RENT_PER_DAY)
	var fee: int = 0
	if cash < 0:
		negative_days += 1
		# 打手只在結算時出現;同一段負債期間只收一次,並有冷卻天數
		if not in_debt_episode and day - last_collector_day >= Config.DEBT_FEE_COOLDOWN_DAYS:
			fee = Config.DEBT_FEE
			last_collector_day = day
			_change_cash(-fee)
			collector_arrived.emit(fee)
		in_debt_episode = true
	else:
		negative_days = 0
		in_debt_episode = false
	s["fees"] = fee
	s["closing_cash"] = cash
	s["net_gambling"] = int(s["wagers"]) - int(s["payouts"])
	s["day"] = day
	s["reputation"] = reputation
	s["negative_days"] = negative_days
	var n: int = int(s["sat_count"])
	s["avg_sat"] = float(s["sat_sum"]) / float(n) if n > 0 else 0.0
	var summary: Dictionary = s.duplicate()
	history.append(summary)
	day += 1
	time_in_day = 0.0
	_new_day_stats()
	day_settled.emit(summary)
	if negative_days >= Config.NEGATIVE_DAYS_LIMIT:
		_end_game("連續 %d 次結算現金為負,賭場破產了" % Config.NEGATIVE_DAYS_LIMIT)
	else:
		_check_dead_end()
	return summary


func _check_dead_end() -> void:
	if not is_game_over and machines.is_empty() and cash < MachineCatalog.cheapest_price():
		_end_game("沒有機台、也買不起新機台,賭場無法再營收")


func _end_game(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_reason = reason
	game_ended.emit(reason)
