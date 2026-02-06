extends Resource
class_name Attunement

@export var attunement_name: String = "Unnamed Attunement"
@export var description: String = ""

# Generic, global modifiers (keep these small and universal)
@export var mana_regen_mult: float = 1.0
@export var mana_cost_mult: float = 1.0
@export var mana_gain_mult: float = 1.0
@export var damage_mult: float = 1.0
@export var move_speed_mult: float = 1.0

# Per-action overrides (optional, scalable, future-proof)
# Example keys: "dash", "double_jump", "wall_jump", "wall_cling", "light_attack", "heavy_attack", "coalesce"
# Values are multipliers.
@export var action_cost_mults: Dictionary = {}
@export var action_value_mults: Dictionary = {} # for damage/knockback/etc by action_id if you want later

func get_cost_mult(action_id: String) -> float:
	return float(action_cost_mults.get(action_id, 1.0)) * mana_cost_mult

func get_value_mult(action_id: String) -> float:
	return float(action_value_mults.get(action_id, 1.0))

func modify_value(_player: Node, _key: String, value: float, _ctx: Dictionary) -> float:
	# Base implementation: pass-through. Static multipliers (damage_mult, mana_gain_mult,
	# action_value_mults) are already applied by AttunementManager before this is called.
	# Override in subclasses for context-aware conditional modifiers.
	return value

## Ranged mode override — subclasses return a RangedModeData to replace the character's
## default ranged mode entirely (e.g. Bolt's attunement swapping free-aim to targeted).
## Return null to keep the character's default.
func get_ranged_mode_override() -> RangedModeData:
	return null

# --- Event hooks (optional) ---
# These are intentionally generic. You can subclass Attunement later for special behavior.

func on_action_started(_player: Node, _action_id: String, _ctx: Dictionary) -> void:
	pass

func on_action_ended(_player: Node, _action_id: String, _ctx: Dictionary) -> void:
	pass

func on_mana_spent(_player: Node, _amount: float, _reason: String, _ctx: Dictionary) -> void:
	pass

func on_dealt_damage(_player: Node, _amount: float, _target: Node, _ctx: Dictionary) -> void:
	pass

func on_took_damage(_player: Node, _amount: float, _source: Node, _ctx: Dictionary) -> void:
	pass
