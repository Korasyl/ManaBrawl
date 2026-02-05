extends Node
class_name ContextKeys

# Core identity
const SOURCE := "source"
const TARGET := "target"
const ATTACK_ID := "attack_id"
const DAMAGE_TYPE := "damage_type"

# Damage
const DAMAGE := "damage"
const BASE_DAMAGE := "base_damage"
const MOD_KEY := "mod_key"
const INTERRUPT := "interrupt"

# Avoidance
const WAS_AVOIDED := "was_avoided"
const AVOID_REASON := "avoid_reason"

# Mana
const BASE_MANA_GAIN := "base_mana_gain"
const FINAL_MANA_GAIN := "final_mana_gain"
const MANA_SPENT := "mana_spent"
const COST_REASON := "cost_reason"

# Player state (needed by attunements for conditional logic)
const IS_AIRBORNE := "is_airborne"
const IS_COALESCING := "is_coalescing"
const FACING := "facing"  # -1 left, 1 right
const COMBO_COUNT := "combo_count"

# Block/shield (Phase 2 — reserved so attunements can hook in)
const IS_BLOCKED := "is_blocked"
const IS_SHIELD_BREAK := "is_shield_break"
