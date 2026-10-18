class_name MachineInstance
extends RefCounted
## 場上的一台機台:佔 2 格 = 機器格 + 座位格(座位在旋轉方向的那一側)。

enum State { IDLE, RESERVED, BUSY }

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

var id: int = 0
var type_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var rot: int = 0
var state: int = State.IDLE

# 統計
var rounds: int = 0
var wagers: int = 0
var payouts: int = 0
var jackpots: int = 0
var busy_time: float = 0.0
var alive_time: float = 0.0


static func seat_for(machine_cell: Vector2i, machine_rot: int) -> Vector2i:
	return machine_cell + DIRS[posmod(machine_rot, 4)]


func seat_cell() -> Vector2i:
	return seat_for(cell, rot)


func utilization() -> float:
	if alive_time <= 0.0:
		return 0.0
	return busy_time / alive_time


func net_cents() -> int:
	return wagers - payouts
