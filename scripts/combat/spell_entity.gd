extends Node2D
class_name SpellEntity

## Base class for persistent spell effects (barriers, vines, husks, zones, etc.).
## Subclasses override _on_spawn(), _spell_process(), and _on_expire() for unique behavior.

## Who cast this spell
var caster: Node = null
var team_id: int = 0

## Lifetime — 0 = infinite (must be manually freed)
@export var max_lifetime: float = 10.0
var _lifetime_timer: float = 0.0

## Optional HP — if > 0, entity is destructible
@export var max_hp: float = 0.0
var current_hp: float = 0.0

## Spell data reference (set by caster before adding to scene)
var spell_data: SpellData = null

## Optional follow behavior (used by apply_at_target style spells)
var follow_target: Node2D = null
var follow_offset: Vector2 = Vector2.ZERO


func _ready():
	if max_hp > 0:
		current_hp = max_hp
	add_to_group("spell_entity")
	_on_spawn()

func _physics_process(delta):
	if follow_target != null:
		if not is_instance_valid(follow_target):
			_on_expire()
			queue_free()
			return
		global_position = follow_target.global_position + follow_offset

	if max_lifetime > 0:
		_lifetime_timer += delta
		if _lifetime_timer >= max_lifetime:
			_on_expire()
			queue_free()
			return
	_spell_process(delta)

## Override in subclasses — called once when the entity enters the scene.
func _on_spawn() -> void:
	pass

## Override in subclasses — called every physics frame.
func _spell_process(_delta: float) -> void:
	pass

## Override in subclasses — called when lifetime expires or HP depletes.
func _on_expire() -> void:
	pass

func attach_to_target(target: Node2D, offset: Vector2 = Vector2.ZERO) -> void:
	follow_target = target
	follow_offset = offset
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position + follow_offset


## Destructible entities: call this to deal damage to the spell entity.
func take_damage(damage: float, _knockback: Vector2 = Vector2.ZERO, _interrupt_type: String = "none", _ctx: Dictionary = {}):
	if max_hp <= 0:
		return  # Not destructible
	current_hp -= damage
	if current_hp <= 0:
		current_hp = 0.0
		_on_expire()
		queue_free()

## Helper: check if a node is on the same team
func is_ally(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id == team_id
	return false

func is_enemy(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id != team_id
	return other != caster
