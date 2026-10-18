extends SceneTree
## 比較機台組合:4A / 3A+1B / 2A+2B(預設設定,30 天,3 個種子)

func _initialize() -> void:
	var spots: Array = [Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 7), Vector2i(3, 9), Vector2i(7, 2), Vector2i(7, 4)]
	var mixes: Dictionary = {"4A": ["A", "A", "A", "A"], "3A+1B": ["A", "A", "A", "B"], "2A+2B": ["A", "A", "B", "B"]}
	for name in mixes:
		var nw: float = 0.0
		var rep: float = 0.0
		var over: int = 0
		for sd in [1, 2, 3]:
			var sim := Simulation.new(int(sd))
			for i in mixes[name].size():
				sim.state.try_buy_and_place(mixes[name][i], spots[i], 0)
			for d in 30:
				for i in int(Config.DAY_SECONDS / Config.SIM_STEP):
					sim.step(Config.SIM_STEP)
			nw += sim.state.net_worth()
			rep += sim.state.reputation
			if sim.state.is_game_over:
				over += 1
		print("%-6s 淨資產 %9s  聲望 %5.1f  破產 %d/3" % [name, Config.fmt_money(int(nw / 3.0)), rep / 3.0, over])
	quit()
