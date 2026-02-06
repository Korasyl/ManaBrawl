extends Node
class_name StatusEffectManager

## Manages active status effects on a character.
## Add as child of Player or any entity that can receive status effects.

signal effect_applied(effect: StatusEffect)
signal effect_expired(effect: StatusEffect)

var _effects: Array[StatusEffect] = []
var _owner: Node = null

func initialize(owner: Node) -> void:
	_owner = owner

func _physics_process(delta):
	var expired: Array[StatusEffect] = []

	for effect in _effects:
		# Tick duration
		if effect.duration > 0:
			effect.duration -= delta
			if effect.duration <= 0:
				expired.append(effect)
				continue

		# Apply DoT
		if effect.type == StatusEffect.Type.BURNING and _owner != null:
			if _owner.has_method("take_damage"):
				var dot_damage: float = float(effect.magnitude) * float(delta)
				var ctx := {ContextKeys.SOURCE: effect.source, ContextKeys.DAMAGE_TYPE: "dot"}
				_owner.take_damage(dot_damage, Vector2.ZERO, "none", ctx)

	# Remove expired effects
	for effect in expired:
		_effects.erase(effect)
		emit_signal("effect_expired", effect)

## Apply a new status effect. Returns the effect for further modification.
func apply_effect(type: StatusEffect.Type, duration: float, source: Node = null, magnitude: float = 1.0, effect_id: String = "") -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = type
	effect.duration = duration
	effect.source = source
	effect.magnitude = magnitude
	effect.effect_id = effect_id
	_effects.append(effect)
	emit_signal("effect_applied", effect)
	return effect

## Remove all effects matching a type
func remove_effects_by_type(type: StatusEffect.Type) -> void:
	var to_remove: Array[StatusEffect] = []
	for effect in _effects:
		if effect.type == type:
			to_remove.append(effect)
	for effect in to_remove:
		_effects.erase(effect)
		emit_signal("effect_expired", effect)

## Remove all effects matching an effect_id
func remove_effects_by_id(id: String) -> void:
	var to_remove: Array[StatusEffect] = []
	for effect in _effects:
		if effect.effect_id == id:
			to_remove.append(effect)
	for effect in to_remove:
		_effects.erase(effect)
		emit_signal("effect_expired", effect)

## Remove all effects from a specific source
func remove_effects_by_source(source: Node) -> void:
	var to_remove: Array[StatusEffect] = []
	for effect in _effects:
		if effect.source == source:
			to_remove.append(effect)
	for effect in to_remove:
		_effects.erase(effect)
		emit_signal("effect_expired", effect)

## Clear all effects
func clear_all() -> void:
	for effect in _effects:
		emit_signal("effect_expired", effect)
	_effects.clear()

## Query helpers
func is_rooted() -> bool:
	for effect in _effects:
		if effect.blocks_movement():
			return true
	return false

func is_silenced() -> bool:
	for effect in _effects:
		if effect.blocks_spells():
			return true
	return false

func is_grabbed() -> bool:
	for effect in _effects:
		if effect.blocks_actions():
			return true
	return false

func get_speed_mult() -> float:
	var mult := 1.0
	for effect in _effects:
		mult *= effect.get_speed_mult()
	return mult

func has_effect_id(id: String) -> bool:
	for effect in _effects:
		if effect.effect_id == id:
			return true
	return false

func get_active_effects() -> Array[StatusEffect]:
	return _effects.duplicate()

func get_effect_count() -> int:
	return _effects.size()
