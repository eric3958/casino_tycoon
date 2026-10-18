class_name MachineCatalog
extends RefCounted
## 所有機台型號都在這裡定義(資料驅動,新增機台只要加一行)。

static var _defs: Dictionary = {}


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_defs["A"] = _make("A", "標準機", 500, 25, 3.0, Color(0.25, 0.55, 0.95),
		MachineConfig.make(650, 5, 2319, 20000))
	_defs["B"] = _make("B", "高級機", 1500, 100, 5.0, Color(0.9, 0.35, 0.3),
		MachineConfig.make(696, 4, 2667, 25000))


static func _make(type_id: String, label: String, price: int, wager: int, secs: float,
		color: Color, cfg: MachineConfig) -> MachineDef:
	var d := MachineDef.new()
	d.id = type_id
	d.display_name = label
	d.price_cents = price * Config.CENTS
	d.wager_cents = wager * Config.CENTS
	d.round_seconds = secs
	d.color = color
	d.default_config = cfg
	return d


static func ids() -> Array:
	_ensure()
	return _defs.keys()


static func has_type(type_id: String) -> bool:
	_ensure()
	return _defs.has(type_id)


static func get_def(type_id: String) -> MachineDef:
	_ensure()
	return _defs[type_id]


static func cheapest_price() -> int:
	_ensure()
	var best: int = 1 << 60
	for k in _defs:
		var d: MachineDef = _defs[k]
		best = mini(best, d.price_cents)
	return best
