class_name Config
extends RefCounted
## 全域參數(全部是暫定值,集中在這裡方便之後調整)。
## 金額一律使用整數「分」(cents),避免浮點誤差。

const CENTS := 100

# --- 場地 ---
const GRID_W := 12
const GRID_H := 12
const ENTRANCE := Vector2i(0, 5)
const EXIT := Vector2i(0, 6)

# --- 時間 ---
const DAY_SECONDS := 120.0   # 1x 速度下一天的秒數
const SIM_STEP := 0.1        # 固定模擬步長(秒)

# --- 財務 ---
const START_CASH := 5000 * CENTS
const RENT_PER_DAY := 75 * CENTS
const DEBT_FEE := 100 * CENTS
const DEBT_FEE_COOLDOWN_DAYS := 3
const NEGATIVE_DAYS_LIMIT := 3
const RESALE_PCT := 50

# --- 聲望與客流 ---
const START_REPUTATION := 50.0
const TRAFFIC_BASE_PER_DAY := 16.0
const TRAFFIC_GAMMA := 2.0           # 客流 = BASE * (R/50)^GAMMA,無人為下限與上限
const REP_ALPHA_UP := 0.04
const REP_ALPHA_DOWN := 0.15
const UNSERVED_SATISFACTION := 25.0

# --- 顧客 ---
const MAX_INSIDE := 30               # 效能保險,不是玩法上限
const WALK_SPEED := 2.0              # 格/秒
const WAIT_LIMIT := 8.0              # 等不到機台就離開(秒)
const BANKROLL_MIN := 200 * CENTS
const BANKROLL_MAX := 500 * CENTS
const ROUNDS_MIN := 6
const ROUNDS_MAX := 12
const MIN_ROUNDS_AFFORDABLE := 3     # 賭注 <= 本金 / 3 才會選這台
const STOP_LOSS_WAGERS := 4          # 單次來訪累計輸掉 4 倍賭注就離場

# --- 滿意度:s = 50 + 100 * (回報率 - 0.9) - 停損懲罰 ---
const SAT_BASE := 92.0
const SAT_RHO_REF := 0.9
const SAT_RHO_SLOPE := 100.0
const SAT_LIMIT_PENALTY := 10.0


@warning_ignore("integer_division")
static func fmt_money(cents: int) -> String:
	var a: int = absi(cents)
	var dollars: int = a / CENTS
	var rem: int = a % CENTS
	var s: String = str(dollars)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	if rem != 0:
		out += ".%02d" % rem
	return ("-$" if cents < 0 else "$") + out
