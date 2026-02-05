extends Node
class_name AttunementManager

signal attunements_changed(slots: Array)

@export var slot_count: int = 3

var _player: Node = null
var _slots: Array[Attunement] = []  # may contain nulls

func initialize(player: Node) -> void:
	_player = player
	_slots.resize(slot_count)
	for i in range(slot_count):
		_slots[i] = null

func set_slot_attunement(slot_index: int, a: Attunement) -> void:
	if slot_index < 0 or slot_index >= slot_count:
		return
	_slots[slot_index] = a
	emit_signal("attunements_changed", _slots)

func get_slot_attunement(slot_index: int) -> Attunement:
	if slot_index < 0 or slot_index >= slot_count:
		return null
	return _slots[slot_index]

func get_all_slots() -> Array:
	return _slots.duplicate()

# --- Combined multipliers ---
# Rule: multiply modifiers together (stacking feels clean + predictable)

func get_cost_mult(action_id: String) -> float:
	var mult := 1.0
	for a in _slots:
		if a == null:
			continue
		# Attunement.get_cost_mult(action_id) should already include its global mana_cost_mult if you wrote it that way.
		mult *= a.get_cost_mult(action_id)
	return mult

func get_regen_mult() -> float:
	var mult := 1.0
	for a in _slots:
		if a == null:
			continue
		mult *= a.mana_regen_mult
	return mult

func get_move_speed_mult() -> float:
	var mult := 1.0
	for a in _slots:
		if a == null:
			continue
		mult *= a.move_speed_mult
	return mult

# --- Event forwarding to all equipped attunements ---
func notify_action_started(action_id: String, ctx: Dictionary = {}) -> void:
	for a in _slots:
		if a: a.on_action_started(_player, action_id, ctx)

func notify_action_ended(action_id: String, ctx: Dictionary = {}) -> void:
	for a in _slots:
		if a: a.on_action_ended(_player, action_id, ctx)

func notify_mana_spent(amount: float, reason: String, ctx: Dictionary = {}) -> void:
	for a in _slots:
		if a: a.on_mana_spent(_player, amount, reason, ctx)

func notify_dealt_damage(amount: float, target: Node, ctx: Dictionary = {}) -> void:
	for a in _slots:
		if a: a.on_dealt_damage(_player, amount, target, ctx)

func notify_took_damage(amount: float, source: Node, ctx: Dictionary = {}) -> void:
	for a in _slots:
		if a: a.on_took_damage(_player, amount, source, ctx)

func get_damage_mult(value_key: String) -> float:
	var mult := 1.0
	for a in _slots:
		if a == null:
			continue
		mult *= a.damage_mult * a.get_value_mult(value_key)
	return mult

func modify_damage(value_key: String, base_value: float, ctx: Dictionary = {}) -> float:
	# Step 1: Apply static multipliers (global damage_mult * per-key value_mult)
	var result: float = float(base_value) * get_damage_mult(value_key)

	# Step 2: Let each attunement's modify_value do context-aware adjustments
	for a in _slots:
		if a == null:
			continue
		result = a.modify_value(_player, value_key, result, ctx)

	return result

func get_mana_gain_mult(value_key: String) -> float:
	var mult := 1.0
	for a in _slots:
		if a == null:
			continue
		mult *= a.mana_gain_mult * a.get_value_mult(value_key)
	return mult

func modify_mana_gain(value_key: String, base_value: float, ctx: Dictionary = {}) -> float:
	# Step 1: Apply static multipliers (global mana_gain_mult * per-key value_mult)
	var result: float = float(base_value) * get_mana_gain_mult(value_key)

	# Step 2: Let each attunement's modify_value do context-aware adjustments
	for a in _slots:
		if a == null:
			continue
		result = a.modify_value(_player, value_key, result, ctx)

	return result

func get_multiplier_summary() -> Dictionary:
	return {
		"regen_mult": get_regen_mult(),
		"dash_cost_mult": get_cost_mult("dash"),
		"double_jump_cost_mult": get_cost_mult("double_jump"),
		"wall_jump_cost_mult": get_cost_mult("wall_jump"),
		"wall_cling_cost_mult": get_cost_mult("wall_cling"),
		"move_speed_mult": get_move_speed_mult(),
	}

func get_debug_summary_text(stats: CharacterStats) -> String:
	var s := get_multiplier_summary()

	var dash_base := stats.dash_cost if stats else 0.0
	var dj_base := stats.double_jump_cost if stats else 0.0
	var wj_base := stats.wall_jump_cost if stats else 0.0
	var cling_base := stats.wall_cling_drain if stats else 0.0

	var dash_eff := dash_base * float(s["dash_cost_mult"])
	var dj_eff := dj_base * float(s["double_jump_cost_mult"])
	var wj_eff := wj_base * float(s["wall_jump_cost_mult"])
	var cling_eff := cling_base * float(s["wall_cling_cost_mult"])

	# Slot names (3 slots)
	var slot_names: Array[String] = []
	for i in range(slot_count):
		var a: Attunement = get_slot_attunement(i)
		slot_names.append(a.attunement_name if a else "— Empty —")

	return (
		"Attunements: [%s] [%s] [%s]\n" +
		"Regen x%.2f | Move x%.2f\n" +
		"Cost mults: Dash x%.2f, DJ x%.2f, WJ x%.2f, Cling x%.2f\n" +
		"Effective:  Dash %.0f→%.0f, DJ %.0f→%.0f, WJ %.0f→%.0f, Cling %.1f/s→%.1f/s"
	) % [
		slot_names[0], slot_names[1], slot_names[2],
		float(s["regen_mult"]), float(s["move_speed_mult"]),
		float(s["dash_cost_mult"]), float(s["double_jump_cost_mult"]), float(s["wall_jump_cost_mult"]), float(s["wall_cling_cost_mult"]),
		dash_base, dash_eff, dj_base, dj_eff, wj_base, wj_eff, cling_base, cling_eff
	]
