extends RefCounted
class_name StatusEffect

## A single active status effect on a character.
## Managed by StatusEffectManager.

## Effect types — extend as needed
enum Type {
	ROOTED,     # Cannot move
	SILENCED,   # Cannot cast spells
	GRABBED,    # Cannot move or act (vine grab, etc.)
	SLOWED,     # Reduced move speed
	BURNING,    # Damage over time
	CUSTOM,     # For unique effects — check effect_id
}

var type: Type = Type.CUSTOM
var effect_id: String = ""   # Unique identifier (e.g. "vine_grab", "aegis_slow")
var duration: float = 0.0    # Remaining duration (0 = permanent until removed)
var source: Node = null       # Who applied this effect
var magnitude: float = 1.0   # For SLOWED: speed multiplier (0.5 = half speed), BURNING: dps

## Returns true if this effect prevents movement
func blocks_movement() -> bool:
	return type == Type.ROOTED or type == Type.GRABBED

## Returns true if this effect prevents all actions (attacks, spells, block)
func blocks_actions() -> bool:
	return type == Type.GRABBED

## Returns true if this effect prevents spell casting
func blocks_spells() -> bool:
	return type == Type.SILENCED or type == Type.GRABBED

## Returns the speed multiplier (1.0 if this effect doesn't affect speed)
func get_speed_mult() -> float:
	if type == Type.SLOWED:
		return magnitude
	if blocks_movement():
		return 0.0
	return 1.0
