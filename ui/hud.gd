class_name HUD
extends CanvasLayer
## 介面層:全部用程式建立(不需要在編輯器裡拉 UI)。
## 只讀取 sim.state 顯示,操作一律呼叫 state.try_* 或調整 state.configs。

var sim: Simulation
var world: CasinoWorld

var _root: Control
var _lbl_day: Label
var _lbl_cash: Label
var _lbl_rep: Label
var _lbl_inside: Label
var _lbl_warn: Label
var _lbl_summary: Label
var _lbl_msg: Label
var _lbl_hint: Label
var _msg_tween: Tween
var _btn_pause: Button
var _cfg_value_labels: Dictionary = {}    # "A:p_lose" -> Label
var _cfg_derived_labels: Dictionary = {}  # "A" -> Label
var _sel_panel: PanelContainer
var _sel_info: Label
var _sel_sell: Button
var _over_panel: PanelContainer
var _over_label: Label


func setup(p_sim: Simulation, p_world: CasinoWorld) -> void:
	sim = p_sim
	world = p_world
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top_bar()
	_build_left_column()
	_build_right_column()
	_build_message()
	_build_game_over()
	sim.state.message.connect(_show_message)
	sim.state.day_settled.connect(_on_day_settled)
	sim.state.collector_arrived.connect(_on_collector)
	sim.state.game_ended.connect(_on_game_over)
	world.selection_changed.connect(_on_selection_changed)
	world.placing_changed.connect(_on_placing_changed)
	_on_selection_changed(-1)
	_on_placing_changed()


# ---------------------------------------------------------------- 建構輔助

func _panel(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 8)
	p.add_child(mc)
	var vb := VBoxContainer.new()
	mc.add_child(vb)
	if title != "":
		var l := Label.new()
		l.text = title
		l.add_theme_font_size_override("font_size", 16)
		vb.add_child(l)
	return vb


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _label(text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	return l


# ---------------------------------------------------------------- 上方列

func _build_top_bar() -> void:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	_lbl_day = _label()
	_lbl_cash = _label()
	_lbl_rep = _label()
	_lbl_inside = _label()
	for l in [_lbl_day, _lbl_cash, _lbl_rep, _lbl_inside]:
		h.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_btn_pause = _button("暫停 (空白鍵)", _toggle_pause)
	h.add_child(_btn_pause)
	h.add_child(_button("1×", func() -> void: _set_speed(1.0)))
	h.add_child(_button("2×", func() -> void: _set_speed(2.0)))


func _toggle_pause() -> void:
	sim.paused = not sim.paused


func _set_speed(s: float) -> void:
	sim.speed = s
	sim.paused = false


# ---------------------------------------------------------------- 左欄:商店與結算

func _build_left_column() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(10, 56)
	col.add_theme_constant_override("separation", 8)
	_root.add_child(col)
	var shop: VBoxContainer = _panel(col, "商店(點選後到地圖放置)")
	for type_id in MachineCatalog.ids():
		var def: MachineDef = MachineCatalog.get_def(type_id)
		var tid: String = type_id
		var txt: String = "買 %s %s  %s  (賭注 %s)" % [def.id, def.display_name, Config.fmt_money(def.price_cents), Config.fmt_money(def.wager_cents)]
		shop.add_child(_button(txt, func() -> void: world.begin_place(tid)))
	_lbl_hint = _label()
	_lbl_hint.add_theme_font_size_override("font_size", 13)
	shop.add_child(_lbl_hint)
	var help: VBoxContainer = _panel(col, "操作")
	var h := _label("左鍵:放置/選取機台\nR:旋轉  右鍵/Esc:取消\nWASD/方向鍵:移動視角  滾輪:縮放\n空白鍵:暫停  1/2:速度")
	h.add_theme_font_size_override("font_size", 13)
	help.add_child(h)
	var sm: VBoxContainer = _panel(col, "上一天結算")
	_lbl_summary = _label("(尚未結算)")
	_lbl_summary.add_theme_font_size_override("font_size", 13)
	sm.add_child(_lbl_summary)


# ---------------------------------------------------------------- 右欄:賭局設定與選取

func _build_right_column() -> void:
	var col := VBoxContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.offset_left = -360.0
	col.offset_right = -10.0
	col.offset_top = 56.0
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.add_theme_constant_override("separation", 8)
	_root.add_child(col)
	for type_id in MachineCatalog.ids():
		_build_type_settings(col, type_id)
	# 選取中的機台
	_sel_panel = PanelContainer.new()
	col.add_child(_sel_panel)
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 8)
	_sel_panel.add_child(mc)
	var vb := VBoxContainer.new()
	mc.add_child(vb)
	_sel_info = _label()
	_sel_info.add_theme_font_size_override("font_size", 13)
	vb.add_child(_sel_info)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	_sel_sell = _button("賣出", _on_sell_pressed)
	hb.add_child(_sel_sell)
	hb.add_child(_button("移動", _on_move_pressed))


func _build_type_settings(parent: Control, type_id: String) -> void:
	var def: MachineDef = MachineCatalog.get_def(type_id)
	var vb: VBoxContainer = _panel(parent, "賭局設定:%s %s(賭注 %s)" % [def.id, def.display_name, Config.fmt_money(def.wager_cents)])
	var rows: Array = [
		["p_lose", "輸機率", 10],
		["p_jackpot", "大獎機率", 1],
		["std_mult", "標準獎倍率", 100],
		["jackpot_mult", "大獎倍率", 1000],
	]
	for row in rows:
		var field: String = row[0]
		var step: int = row[2]
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var name_lbl := _label(row[1])
		name_lbl.custom_minimum_size = Vector2(96, 0)
		hb.add_child(name_lbl)
		hb.add_child(_button("−", func() -> void: _adjust(type_id, field, -step)))
		var val := _label()
		val.custom_minimum_size = Vector2(70, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(val)
		_cfg_value_labels["%s:%s" % [type_id, field]] = val
		hb.add_child(_button("＋", func() -> void: _adjust(type_id, field, step)))
	var derived := _label()
	derived.add_theme_font_size_override("font_size", 12)
	vb.add_child(derived)
	_cfg_derived_labels[type_id] = derived


func _adjust(type_id: String, field: String, delta: int) -> void:
	var cfg: MachineConfig = (sim.state.configs[type_id] as MachineConfig).clone()
	match field:
		"p_lose": cfg.p_lose_pm += delta
		"p_jackpot": cfg.p_jackpot_pm += delta
		"std_mult": cfg.std_mult_pm += delta
		"jackpot_mult": cfg.jackpot_mult_pm += delta
	if not cfg.is_valid():
		sim.state.message.emit("設定不合法:機率不得為負、總和不得超過 100%、倍率不得為負")
		return
	sim.state.configs[type_id] = cfg


func _on_sell_pressed() -> void:
	if world.selected_id >= 0:
		sim.state.try_sell(world.selected_id)


func _on_move_pressed() -> void:
	if world.selected_id >= 0:
		world.begin_move(world.selected_id)


# ---------------------------------------------------------------- 訊息與結束畫面

func _build_message() -> void:
	_lbl_msg = _label()
	_lbl_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_msg.offset_top = 60.0
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.add_theme_font_size_override("font_size", 20)
	_lbl_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	_lbl_msg.add_theme_constant_override("outline_size", 6)
	_lbl_msg.modulate.a = 0.0
	_lbl_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lbl_msg)
	_lbl_warn = _label("現金為負!結算前請賣出機台或賺回現金,否則打手上門")
	_lbl_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lbl_warn.offset_top = -50.0
	_lbl_warn.add_theme_font_size_override("font_size", 20)
	_lbl_warn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_lbl_warn.add_theme_color_override("font_outline_color", Color.BLACK)
	_lbl_warn.add_theme_constant_override("outline_size", 6)
	_lbl_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lbl_warn)


func _show_message(text: String) -> void:
	_lbl_msg.text = text
	_lbl_msg.modulate.a = 1.0
	if _msg_tween != null:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(2.5)
	_msg_tween.tween_property(_lbl_msg, "modulate:a", 0.0, 0.6)


func _build_game_over() -> void:
	_over_panel = PanelContainer.new()
	_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over_panel.visible = false
	_root.add_child(_over_panel)
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 24)
	_over_panel.add_child(mc)
	var vb := VBoxContainer.new()
	mc.add_child(vb)
	_over_label = _label()
	_over_label.add_theme_font_size_override("font_size", 22)
	vb.add_child(_over_label)
	vb.add_child(_button("重新開始", func() -> void: get_tree().reload_current_scene()))


func _on_game_over(reason: String) -> void:
	var s: CasinoState = sim.state
	_over_label.text = "遊戲結束\n%s\n撐了 %d 天,最終淨資產 %s" % [reason, s.day, Config.fmt_money(s.net_worth())]
	_over_panel.visible = true


func _on_collector(fee: int) -> void:
	_show_message("債務催收人上門!罰款 %s" % Config.fmt_money(fee))


func _on_day_settled(sm: Dictionary) -> void:
	_lbl_summary.text = "第 %d 天\n期初現金 %s\n總賭注 %s\n總賠付 %s\n淨賭博收入 %s\n購買 %s  轉售 %s\n租金 %s  罰款 %s\n期末現金 %s\n到客 %d  離場 %d  未服務 %d\n平均滿意度 %.1f  聲望 %.1f" % [
		sm["day"], Config.fmt_money(sm["opening_cash"]), Config.fmt_money(sm["wagers"]),
		Config.fmt_money(sm["payouts"]), Config.fmt_money(sm["net_gambling"]),
		Config.fmt_money(sm["purchases"]), Config.fmt_money(sm["resale"]),
		Config.fmt_money(sm["rent"]), Config.fmt_money(sm["fees"]),
		Config.fmt_money(sm["closing_cash"]), sm["arrivals"], sm["departures"], sm["unserved"],
		sm["avg_sat"], sm["reputation"]]


# ---------------------------------------------------------------- 狀態變化

func _on_selection_changed(_id: int) -> void:
	_sel_panel.visible = world.selected_id >= 0


func _on_placing_changed() -> void:
	if world.placing_move_id >= 0:
		_lbl_hint.text = "移動中:點地圖放下(R 旋轉,右鍵取消)"
	elif world.placing_type != "":
		_lbl_hint.text = "放置 %s:左鍵購買,R 旋轉,右鍵取消" % world.placing_type
	else:
		_lbl_hint.text = ""


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		_toggle_pause()
	elif k.keycode == KEY_1:
		_set_speed(1.0)
	elif k.keycode == KEY_2:
		_set_speed(2.0)


# ---------------------------------------------------------------- 每幀更新

func refresh() -> void:
	var s: CasinoState = sim.state
	var status: String = "  [暫停]" if sim.paused else ("  [%d×]" % int(sim.speed))
	_lbl_day.text = "第 %d 天  %d%%%s" % [s.day, int(s.time_in_day / Config.DAY_SECONDS * 100.0), status]
	_lbl_cash.text = "現金 " + Config.fmt_money(s.cash)
	_lbl_cash.modulate = Color(1.0, 0.45, 0.45) if s.cash < 0 else Color.WHITE
	_lbl_rep.text = "聲望 %.1f  預期客流 %.1f/天" % [s.reputation, s.traffic_per_day()]
	_lbl_inside.text = "場內顧客 %d" % sim.customers.customers.size()
	_lbl_warn.visible = s.cash < 0 and not s.is_game_over
	_btn_pause.text = "繼續 (空白鍵)" if sim.paused else "暫停 (空白鍵)"
	_refresh_settings()
	_refresh_selection()


func _refresh_settings() -> void:
	for type_id in MachineCatalog.ids():
		var cfg: MachineConfig = sim.state.configs[type_id]
		var def: MachineDef = MachineCatalog.get_def(type_id)
		(_cfg_value_labels["%s:p_lose" % type_id] as Label).text = "%.1f%%" % (cfg.p_lose_pm / 10.0)
		(_cfg_value_labels["%s:p_jackpot" % type_id] as Label).text = "%.1f%%" % (cfg.p_jackpot_pm / 10.0)
		(_cfg_value_labels["%s:std_mult" % type_id] as Label).text = "%.1f×" % (cfg.std_mult_pm / 1000.0)
		(_cfg_value_labels["%s:jackpot_mult" % type_id] as Label).text = "%.0f×" % (cfg.jackpot_mult_pm / 1000.0)
		(_cfg_derived_labels[type_id] as Label).text = "標準獎機率 %.1f%%  RTP %.1f%%  莊家優勢 %.1f%%\n每回合期望利潤 %s  最大單回合損失 %s" % [
			cfg.p_standard_pm() / 10.0, GamblingModel.rtp(cfg) * 100.0, GamblingModel.house_edge(cfg) * 100.0,
			Config.fmt_money(int(GamblingModel.expected_profit_cents(cfg, def.wager_cents))),
			Config.fmt_money(GamblingModel.max_loss_cents(cfg, def.wager_cents))]


func _refresh_selection() -> void:
	if world.selected_id < 0:
		return
	var m: MachineInstance = sim.state.machines.get(world.selected_id)
	if m == null:
		return
	var def: MachineDef = MachineCatalog.get_def(m.type_id)
	var st_name: String = ["閒置", "已預約", "使用中"][m.state]
	_sel_info.text = "機台 #%d  %s %s  [%s]\n回合 %d  總賭注 %s  總賠付 %s\n淨賭博收入 %s  大獎 %d 次  使用率 %.0f%%" % [
		m.id, def.id, def.display_name, st_name, m.rounds, Config.fmt_money(m.wagers),
		Config.fmt_money(m.payouts), Config.fmt_money(m.net_cents()), m.jackpots, m.utilization() * 100.0]
	_sel_sell.text = "賣出(返還 %s)" % Config.fmt_money(sim.state.resale_value(m))
