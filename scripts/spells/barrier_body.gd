extends StaticBody2D

var _owner_entity: SpellEntity = null

func set_owner_entity(owner_entity: SpellEntity) -> void:
	_owner_entity = owner_entity

func take_damage(damage: float, knockback: Vector2 = Vector2.ZERO, interrupt_type: String = "none", ctx: Dictionary = {}) -> void:
	if _owner_entity:
		_owner_entity.take_damage(damage, knockback, interrupt_type, ctx)

func is_ally(other: Node) -> bool:
	if _owner_entity:
		return _owner_entity.is_ally(other)
	return false

func is_enemy(other: Node) -> bool:
	if _owner_entity:
		return _owner_entity.is_enemy(other)
	return false