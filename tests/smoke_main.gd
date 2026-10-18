extends SceneTree
## 冒煙測試:載入完整場景(3D + HUD),自動買機台、跑多天、賣出/移動,檢查沒有執行期錯誤。
## godot --headless --path . -s res://tests/smoke_main.gd

var main: Node
var frame: int = 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var sim: Simulation = main.sim
	var world: CasinoWorld = main.world
	if frame == 3:
		sim.speed = 60.0
		world.begin_place("A")
		world.hover_cell = Vector2i(3, 2)
		world.placing_rot = 0
		sim.state.try_buy_and_place("A", Vector2i(3, 2), 0)
		sim.state.try_buy_and_place("A", Vector2i(3, 4), 1)
		sim.state.try_buy_and_place("B", Vector2i(7, 7), 2)
		world.cancel_placing()
	if frame == 5:
		world.select(1)
		main.hud._adjust("A", "p_lose", 10)
		main.hud._adjust("A", "p_lose", 5000)   # 不合法,應被拒絕
	if frame == 400:
		world.begin_move(2)
		world.hover_cell = Vector2i(5, 9)
		sim.state.try_move(2, Vector2i(5, 9), 3)
		world.cancel_placing()
		world.select(3)
		main.hud._on_sell_pressed()
	if frame == 1500:
		print("smoke: day %d, cash %s, rep %.1f, customers %d, machines %d" % [
			sim.state.day, Config.fmt_money(sim.state.cash), sim.state.reputation,
			sim.customers.customers.size(), sim.state.machines.size()])
		print("smoke: OK")
		quit(0)
	return false
