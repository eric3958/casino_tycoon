class_name Simulation
extends RefCounted
## 模擬總管:固定步長、暫停、倍速。UI 與 3D 場景只呼叫 advance()。

var state: CasinoState
var customers: CustomerSim
var rng := RandomNumberGenerator.new()
var paused: bool = false
var speed: float = 1.0
var _acc: float = 0.0


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	state = CasinoState.new()
	customers = CustomerSim.new(state, rng)


## 每個畫面呼叫一次,real_dt 是真實經過的秒數。
func advance(real_dt: float) -> void:
	if paused or state.is_game_over:
		return
	_acc += real_dt * speed
	var steps: int = 0
	while _acc >= Config.SIM_STEP and steps < 200:
		_acc -= Config.SIM_STEP
		step(Config.SIM_STEP)
		steps += 1
	if steps >= 200:
		_acc = 0.0


func step(dt: float) -> void:
	if state.is_game_over:
		return
	for id in state.machines:
		var m: MachineInstance = state.machines[id]
		m.alive_time += dt
	customers.step(dt)
	state.time_in_day += dt
	if state.time_in_day >= Config.DAY_SECONDS - 0.0001:
		state.settle_day()
