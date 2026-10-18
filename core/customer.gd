class_name Customer
extends RefCounted
## 一位顧客的資料(行為寫在 CustomerSim)。位置單位是「格」,格中心座標 = 格座標。

enum State { WAITING, WALK_TO_MACHINE, PLAYING, LEAVING, GONE }

var id: int = 0
var state: int = State.WAITING
var pos: Vector2 = Vector2.ZERO
var path: Array[Vector2i] = []
var path_idx: int = 0
var age: float = 0.0
var bankroll: int = 0
var rounds_target: int = 0
var rounds_played: int = 0
var wagered: int = 0
var paid: int = 0
var stop_loss: int = 0
var machine_id: int = -1
var wait_time: float = 0.0
var round_timer: float = 0.0
var hit_limit: bool = false
