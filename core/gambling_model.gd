class_name GamblingModel
extends RefCounted
## 賭局數學:全部是純函式,方便單元測試。

enum Outcome { LOSE, WIN, JACKPOT }


@warning_ignore("integer_division")
static func payout_cents(wager: int, mult_pm: int) -> int:
	return (wager * mult_pm + 500) / 1000


## 抽一次結果。回傳 {"outcome": Outcome, "payout": 顧客拿回的總額(含本金)}。
static func resolve(cfg: MachineConfig, wager: int, rng: RandomNumberGenerator) -> Dictionary:
	var roll: int = rng.randi_range(0, 999)
	if roll < cfg.p_lose_pm:
		return {"outcome": Outcome.LOSE, "payout": 0}
	if roll < cfg.p_lose_pm + cfg.p_standard_pm():
		return {"outcome": Outcome.WIN, "payout": payout_cents(wager, cfg.std_mult_pm)}
	return {"outcome": Outcome.JACKPOT, "payout": payout_cents(wager, cfg.jackpot_mult_pm)}


## 回報率 RTP = 顧客長期拿回的比例。
static func rtp(cfg: MachineConfig) -> float:
	return float(cfg.p_standard_pm() * cfg.std_mult_pm + cfg.p_jackpot_pm * cfg.jackpot_mult_pm) / 1000000.0


static func house_edge(cfg: MachineConfig) -> float:
	return 1.0 - rtp(cfg)


## 每回合賭場期望利潤(分),用實際的整數賠付計算,和 resolve() 完全一致。
static func expected_profit_cents(cfg: MachineConfig, wager: int) -> float:
	var win_pay: float = float(payout_cents(wager, cfg.std_mult_pm))
	var jp_pay: float = float(payout_cents(wager, cfg.jackpot_mult_pm))
	var p_l: float = cfg.p_lose_pm / 1000.0
	var p_w: float = cfg.p_standard_pm() / 1000.0
	var p_j: float = cfg.p_jackpot_pm / 1000.0
	return p_l * wager + p_w * (wager - win_pay) + p_j * (wager - jp_pay)


## 單回合最大可能損失(分,正數)。
static func max_loss_cents(cfg: MachineConfig, wager: int) -> int:
	var worst: int = 0
	if cfg.p_standard_pm() > 0:
		worst = maxi(worst, payout_cents(wager, cfg.std_mult_pm))
	if cfg.p_jackpot_pm > 0:
		worst = maxi(worst, payout_cents(wager, cfg.jackpot_mult_pm))
	return maxi(0, worst - wager)
