class_name MachineDef
extends RefCounted
## 機台「型號」的靜態資料(價格、賭注、回合時間、預設賭局設定)。

var id: String = ""
var display_name: String = ""
var price_cents: int = 0
var wager_cents: int = 0
var round_seconds: float = 3.0
var color: Color = Color.WHITE
var default_config: MachineConfig
