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

# Spell behavior overrides (optional)
@export var spell_damage_mult: float = 1.0
@export var spell_projectile_speed_mult: float = 1.0
@export var spell_homing_turn_speed_mult: float = 1.0
@export var spell_channel_drain_mult: float = 1.0
@export var spell_channel_interval_mult: float = 1.0
@export var spell_channel_projectiles_mult: float = 1.0
@export_enum("unchanged", "projectile", "apply_at_target") var forced_targeted_delivery: String = "unchanged"
@export_enum("unchanged", "false", "true") var forced_channeled: String = "unchanged"
@export_enum("unchanged", "false", "true") var forced_line_of_sight: String = "unchanged"


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
	# Base implementation applies generic spell tuning multipliers.
	# Subclasses can still override for context-aware behavior.
	var out := value
	match _key:
		ModKeys.SPELL_DAMAGE:
			out *= spell_damage_mult
		ModKeys.SPELL_PROJECTILE_SPEED:
			out *= spell_projectile_speed_mult
		ModKeys.SPELL_HOMING_TURN_SPEED:
			out *= spell_homing_turn_speed_mult
		ModKeys.SPELL_CHANNEL_DRAIN:
			out *= spell_channel_drain_mult
		ModKeys.SPELL_CHANNEL_INTERVAL:
			out *= spell_channel_interval_mult
		ModKeys.SPELL_CHANNEL_PROJECTILES_PER_TICK:
			out *= spell_channel_projectiles_mult
	return out

## Ranged mode override — subclasses return a RangedModeData to replace the character's
## default ranged mode entirely (e.g. Bolt's attunement swapping free-aim to targeted).
## Return null to keep the character's default.
func get_ranged_mode_override() -> RangedModeData:
	return null

## Optional override for targeted spell delivery behavior.
## Return the input unchanged to keep the spell default.
func override_targeted_delivery(_player: Node, base_delivery: String, _ctx: Dictionary = {}) -> String:
	if forced_targeted_delivery == "unchanged":
		return base_delivery
	return forced_targeted_delivery

## Optional override for channeled behavior.
## Return the input unchanged to keep the spell default.
func override_spell_channeled(_player: Node, base_channeled: bool, _ctx: Dictionary = {}) -> bool:
	if forced_channeled == "unchanged":
		return base_channeled
	return forced_channeled == "true"

## Optional override for line-of-sight requirement.
## An attunement with forced_line_of_sight = "false" removes the LOS restriction.
func override_line_of_sight(_player: Node, base_los: bool, _ctx: Dictionary = {}) -> bool:
	if forced_line_of_sight == "unchanged":
		return base_los
	return forced_line_of_sight == "true"


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
