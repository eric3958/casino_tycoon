extends SceneTree
## 執行方式:godot --headless --path . -s res://tests/run_tests.gd
## 只測規則層(core/),不需要 3D 場景或 UI。

var checks: int = 0
var failures: int = 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL: ", label)


func _initialize() -> void:
	test_gambling()
	test_placement_and_resale()
	test_simulation_invariants()
	test_debt_rules()
	test_economy_report()
	print("\n==== %d checks, %d failures ====" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ 賭局數學
func test_gambling() -> void:
	print("[gambling]")
	for type_id in MachineCatalog.ids():
		var def: MachineDef = MachineCatalog.get_def(type_id)
		var cfg: MachineConfig = def.default_config
		check(cfg.is_valid(), "%s 預設設定合法" % type_id)
		check(absf(GamblingModel.rtp(cfg) - 0.9) < 0.001, "%s RTP 約 90%%" % type_id)
		# 蒙地卡羅:平均賭場利潤應落在期望值 4 個標準誤內
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var n: int = 300000
		var sum: float = 0.0
		var sum2: float = 0.0
		for i in n:
			var r: Dictionary = GamblingModel.resolve(cfg, def.wager_cents, rng)
			var net: float = float(def.wager_cents - int(r["payout"]))
			sum += net
			sum2 += net * net
		var mean: float = sum / n
		var sd: float = sqrt(sum2 / n - mean * mean)
		var ev: float = GamblingModel.expected_profit_cents(cfg, def.wager_cents)
		check(absf(mean - ev) < 4.0 * sd / sqrt(n), "%s 蒙地卡羅平均 %.1f ≈ 期望 %.1f (sd %.0f)" % [type_id, mean, ev, sd])
	var bad := MachineConfig.make(1001, 0, 2000, 2000)
	check(not bad.is_valid(), "機率和超過 100% 不合法")
	check(not MachineConfig.make(-1, 0, 1, 1).is_valid(), "負機率不合法")
	# 範例:賭注 $10、2.676 倍 → 賭場淨額 -$16.76;100 倍 → -$990
	check(GamblingModel.payout_cents(1000, 2676) == 2676, "2.676 倍 = $26.76")
	check(1000 - GamblingModel.payout_cents(1000, 100000) == -99000, "大獎淨額 -$990")
	var ex := MachineConfig.make(700, 1, 2676, 100000)
	check(absf(GamblingModel.expected_profit_cents(ex, 1000) - 99.876) < 0.01, "原案期望利潤 ≈ $0.99876")


# ------------------------------------------------------------------ 放置與轉售
func test_placement_and_resale() -> void:
	print("[placement]")
	var st := CasinoState.new()
	check(st.can_place("A", Vector2i(5, 5), 0) == "", "可放置於中央")
	check(st.can_place("A", Vector2i(11, 5), 0) != "", "座位超出邊界")
	check(st.can_place("A", Vector2i(1, 5), 2) != "", "座位壓到入口")
	check(st.can_place("A", Vector2i(0, 5), 0) != "", "機器壓到入口")
	var r: Dictionary = st.try_buy_and_place("A", Vector2i(5, 5), 0)
	check(r["ok"], "購買成功")
	check(st.cash == Config.START_CASH - 500 * 100, "扣款 $500")
	check(st.occupancy.has(Vector2i(5, 5)) and st.occupancy.has(Vector2i(6, 5)), "佔用兩格")
	check(st.can_place("A", Vector2i(6, 5), 0) != "", "座位格不可被覆蓋")
	check(st.can_place("A", Vector2i(5, 6), 3) != "", "另一台的座位不可壓到既有機台")
	check(st.can_place("A", Vector2i(5, 5), 1, int(r["id"])) == "", "移動時可忽略自己")
	# 旋轉:四個方向的座位
	for rot in 4:
		check(MachineInstance.seat_for(Vector2i(5, 5), rot) != Vector2i(5, 5), "旋轉 %d 的座位不同於機器格" % rot)
	# 資金不足
	st.cash = 100
	check(not st.try_buy_and_place("A", Vector2i(8, 8), 0)["ok"], "資金不足被拒絕")
	st.cash = Config.START_CASH
	# 賣出返還 50%
	var before: int = st.cash
	var sold: Dictionary = st.try_sell(int(r["id"]))
	check(sold["ok"], "賣出成功")
	check(st.cash - before == 250 * 100, "返還 50% = $250")
	check(not st.occupancy.has(Vector2i(5, 5)) and not st.occupancy.has(Vector2i(6, 5)), "格子已釋放")
	# 買再賣的循環永遠虧錢,不能印錢
	var cash0: int = st.cash
	for i in 5:
		var b: Dictionary = st.try_buy_and_place("A", Vector2i(5, 5), 0)
		st.try_sell(int(b["id"]))
	check(st.cash == cash0 - 5 * 250 * 100, "買賣循環每次損失 50%")
	# 使用中的機台不能賣或移動
	var b2: Dictionary = st.try_buy_and_place("A", Vector2i(5, 5), 0)
	(st.machines[int(b2["id"])] as MachineInstance).state = MachineInstance.State.BUSY
	check(not st.try_sell(int(b2["id"]))["ok"], "使用中不能賣")
	check(not st.try_move(int(b2["id"]), Vector2i(8, 8), 0)["ok"], "使用中不能移動")
	(st.machines[int(b2["id"])] as MachineInstance).state = MachineInstance.State.IDLE
	check(st.try_move(int(b2["id"]), Vector2i(8, 8), 1)["ok"], "閒置可移動(免費)")
	check(st.occupancy.has(Vector2i(8, 9)) and not st.occupancy.has(Vector2i(5, 5)), "移動後佔用更新")


func place_standard_machines(sim: Simulation, count: int) -> void:
	var spots: Array = [Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 7), Vector2i(3, 9), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 7), Vector2i(7, 9)]
	for i in count:
		var r: Dictionary = sim.state.try_buy_and_place("A", spots[i], 0)
		assert(r["ok"])


# ------------------------------------------------------------------ 模擬不變式
func test_simulation_invariants() -> void:
	print("[simulation invariants]")
	var sim := Simulation.new(12345)
	place_standard_machines(sim, 4)
	var max_age: float = 0.0
	var double_use: bool = false
	var rep_ok: bool = true
	var steps: int = int(Config.DAY_SECONDS / Config.SIM_STEP) * 20
	for i in steps:
		sim.step(Config.SIM_STEP)
		var use_count: Dictionary = {}
		for c: Customer in sim.customers.customers:
			max_age = maxf(max_age, c.age)
			if c.machine_id >= 0 and (c.state == Customer.State.WALK_TO_MACHINE or c.state == Customer.State.PLAYING):
				use_count[c.machine_id] = int(use_count.get(c.machine_id, 0)) + 1
		for k in use_count:
			if use_count[k] > 1:
				double_use = true
		if sim.state.reputation < 0.0 or sim.state.reputation > 100.0:
			rep_ok = false
	check(not double_use, "同一台機台不會同時被兩位顧客使用或預約")
	check(rep_ok, "聲望維持在 0~100")
	check(max_age < 300.0, "沒有顧客卡住(最長停留 %.0f 秒)" % max_age)
	check(sim.state.history.size() == 20, "結算了 20 天")
	# 帳本不變式
	var ledger_ok: bool = true
	var prev_close: int = Config.START_CASH
	var first: bool = true
	for s: Dictionary in sim.state.history:
		var expected: int = int(s["opening_cash"]) + int(s["wagers"]) - int(s["payouts"]) - int(s["rent"]) \
			+ int(s["resale"]) - int(s["purchases"]) - int(s["fees"])
		if expected != int(s["closing_cash"]):
			ledger_ok = false
		if not first and int(s["opening_cash"]) != prev_close:
			ledger_ok = false
		prev_close = int(s["closing_cash"])
		first = false
	check(ledger_ok, "每日:期末 = 期初 + 賭注 - 賠付 - 租金 + 轉售 - 購買 - 罰款,且逐日連續")


# ------------------------------------------------------------------ 債務規則
func test_debt_rules() -> void:
	print("[debt]")
	var st := CasinoState.new()
	st.try_buy_and_place("A", Vector2i(5, 5), 0)
	st.cash = 5000            # $50,扣掉租金 $100 後為負
	st.settle_day()
	check(st.negative_days == 1 and st.in_debt_episode, "第 1 次負結算")
	check(st.cash == 5000 - Config.RENT_PER_DAY - Config.DEBT_FEE, "打手費用只收一次")
	var cash_after_fee: int = st.cash
	st.settle_day()
	check(st.negative_days == 2, "第 2 次負結算")
	check(st.cash == cash_after_fee - Config.RENT_PER_DAY, "同一段負債期間不再收費")
	st.settle_day()
	check(st.is_game_over, "連續 3 次負結算 → 遊戲結束")
	# 日內變負但結算前回正,不算負結算
	var st2 := CasinoState.new()
	st2.try_buy_and_place("A", Vector2i(5, 5), 0)
	st2.cash = -5000
	st2.cash = 50000
	st2.settle_day()
	check(st2.negative_days == 0 and not st2.is_game_over, "結算時為正 → 計數歸零")
	# 負 → 正 → 負:計數歸零後重新計算
	var st3 := CasinoState.new()
	st3.try_buy_and_place("A", Vector2i(5, 5), 0)
	st3.cash = 5000
	st3.settle_day()
	st3.cash = 50000
	st3.settle_day()
	check(st3.negative_days == 0 and not st3.in_debt_episode, "回正後債務期間結束")
	# 死局:沒有機台且買不起
	var st4 := CasinoState.new()
	st4.cash = 100
	st4.settle_day()
	check(st4.is_game_over, "沒機台又買不起 → 立即結束")


# ------------------------------------------------------------------ 經濟報告(僅印出,不 assert)
func run_scenario(seed_value: int, plan: Callable, days: int) -> Dictionary:
	var sim := Simulation.new(seed_value)
	place_standard_machines(sim, 4)
	var steps_per_day: int = int(Config.DAY_SECONDS / Config.SIM_STEP)
	for d in days:
		plan.call(sim, d)
		for i in steps_per_day:
			sim.step(Config.SIM_STEP)
			if sim.state.is_game_over:
				break
		if sim.state.is_game_over:
			break
	return {"nw": sim.state.net_worth(), "rep": sim.state.reputation, "cash": sim.state.cash, "over": sim.state.is_game_over, "days": sim.state.day}


func set_rtp_cfg(sim: Simulation, p_lose: int, p_jp: int, mj: int, target_rtp: float) -> void:
	var p_std: int = 1000 - p_lose - p_jp
	var ms: int = int(round((target_rtp - p_jp * mj / 1000000.0) / (p_std / 1000.0) * 1000.0))
	sim.state.configs["A"] = MachineConfig.make(p_lose, p_jp, maxi(ms, 0), mj)


func test_economy_report() -> void:
	print("[economy report: 4 台 A 機, 30 天, 4 個種子平均]")
	var seeds: Array = [11, 22, 33, 44]
	var scenarios: Dictionary = {
		"標準(RTP90%)": func(sim: Simulation, d: int) -> void: pass,
		"偏緊(RTP80%)": func(sim: Simulation, d: int) -> void: set_rtp_cfg(sim, 700, 5, 20000, 0.80),
		"偏鬆(RTP95%)": func(sim: Simulation, d: int) -> void: set_rtp_cfg(sim, 620, 5, 20000, 0.95),
		"割韭菜 1 天後回標準": func(sim: Simulation, d: int) -> void:
			if d < 1: set_rtp_cfg(sim, 999, 0, 20000, 0.0)
			else: sim.state.configs["A"] = MachineCatalog.get_def("A").default_config.clone(),
		"割韭菜 3 天後回標準": func(sim: Simulation, d: int) -> void:
			if d < 3: set_rtp_cfg(sim, 999, 0, 20000, 0.0)
			else: sim.state.configs["A"] = MachineCatalog.get_def("A").default_config.clone(),
		"割 1 天 + 鬆(RTP100%)回聲望": func(sim: Simulation, d: int) -> void:
			if d < 1: set_rtp_cfg(sim, 999, 0, 20000, 0.0)
			elif sim.state.reputation < 45.0: set_rtp_cfg(sim, 570, 5, 20000, 1.0)
			else: sim.state.configs["A"] = MachineCatalog.get_def("A").default_config.clone(),
	}
	for name in scenarios:
		var nw: float = 0.0
		var rep: float = 0.0
		var over: int = 0
		for sd in seeds:
			var res: Dictionary = run_scenario(int(sd), scenarios[name], 30)
			nw += float(res["nw"])
			rep += float(res["rep"])
			if res["over"]:
				over += 1
		print("  %-28s 淨資產 %9s  聲望 %5.1f  破產 %d/4" % [name, Config.fmt_money(int(nw / seeds.size())), rep / seeds.size(), over])
