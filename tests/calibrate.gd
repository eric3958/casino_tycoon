extends SceneTree
## 校準工具:godot --headless --path . -s res://tests/calibrate.gd
## 掃描 RTP,印出 30 天後的聲望、淨資產、平均滿意度、未服務比例。

func place_machines(sim: Simulation, count: int) -> void:
	var spots: Array = [Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 7), Vector2i(3, 9), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 7), Vector2i(7, 9)]
	for i in count:
		sim.state.try_buy_and_place("A", spots[i], 0)


func set_rtp(sim: Simulation, rtp: float) -> void:
	# 輸機率隨 RTP 線性變化:RTP 0.9 → 65%
	var p_lose: int = clampi(int(round(650 + 800.0 * (0.9 - rtp))), 0, 990)
	var p_jp: int = 5
	var p_std: int = 1000 - p_lose - p_jp
	var ms: int = int(round((rtp - p_jp * 20000 / 1000000.0) / (p_std / 1000.0) * 1000.0))
	sim.state.configs["A"] = MachineConfig.make(p_lose, p_jp, maxi(ms, 0), 20000)


func _initialize() -> void:
	var machines: int = 4
	var days: int = 30
	var seeds: Array = [1, 2, 3]
	print("RTP    淨資產     聲望   平均滿意度  未服務%  每日到客")
	for rtp in [0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0]:
		var nw: float = 0.0
		var rep: float = 0.0
		var sat: float = 0.0
		var uns: float = 0.0
		var arr: float = 0.0
		for sd in seeds:
			var sim := Simulation.new(int(sd))
			place_machines(sim, machines)
			set_rtp(sim, rtp)
			for d in days:
				for i in int(Config.DAY_SECONDS / Config.SIM_STEP):
					sim.step(Config.SIM_STEP)
			nw += sim.state.net_worth()
			rep += sim.state.reputation
			var a: float = 0.0
			var u: float = 0.0
			var s_sum: float = 0.0
			for h: Dictionary in sim.state.history:
				a += float(h["arrivals"])
				u += float(h["unserved"])
				s_sum += float(h["avg_sat"])
			arr += a / sim.state.history.size()
			uns += u / maxf(a, 1.0)
			sat += s_sum / sim.state.history.size()
		var n: float = seeds.size()
		print("%.2f  %9s  %5.1f   %6.1f     %5.1f    %5.1f" % [rtp, Config.fmt_money(int(nw / n)), rep / n, sat / n, 100.0 * uns / n, arr / n])
	quit()
