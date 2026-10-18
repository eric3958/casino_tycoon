extends Node3D
## 入口:建立模擬、3D 場景與 HUD,然後每個畫面推進模擬並同步畫面。

var sim: Simulation
var world: CasinoWorld
var hud: HUD


func _ready() -> void:
	sim = Simulation.new()
	world = CasinoWorld.new()
	add_child(world)
	world.setup(sim)
	hud = HUD.new()
	add_child(hud)
	hud.setup(sim, world)


func _process(delta: float) -> void:
	sim.advance(delta)
	world.sync_views()
	hud.refresh()
