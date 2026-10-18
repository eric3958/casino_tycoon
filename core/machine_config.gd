class_name MachineConfig
extends RefCounted
## 玩家可調整的賭局設定(整數千分比 per-mille,避免浮點誤差)。
## 標準獎機率 = 1000 - 輸機率 - 大獎機率。
## 倍率是「總賠付倍率」:含本金退還。例如 2319 = 賠付賭注的 2.319 倍。

var p_lose_pm: int = 650
var p_jackpot_pm: int = 5
var std_mult_pm: int = 2319
var jackpot_mult_pm: int = 20000


static func make(p_lose: int, p_jackpot: int, std_mult: int, jackpot_mult: int) -> MachineConfig:
	var c := MachineConfig.new()
	c.p_lose_pm = p_lose
	c.p_jackpot_pm = p_jackpot
	c.std_mult_pm = std_mult
	c.jackpot_mult_pm = jackpot_mult
	return c


func p_standard_pm() -> int:
	return 1000 - p_lose_pm - p_jackpot_pm


## 只做合法性檢查(機率不得為負、總和不得超過 100%、倍率不得為負)。
func is_valid() -> bool:
	return p_lose_pm >= 0 and p_jackpot_pm >= 0 and p_standard_pm() >= 0 \
		and std_mult_pm >= 0 and jackpot_mult_pm >= 0


func clone() -> MachineConfig:
	return MachineConfig.make(p_lose_pm, p_jackpot_pm, std_mult_pm, jackpot_mult_pm)
