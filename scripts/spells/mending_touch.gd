extends SpellEntity
class_name MendingTouch

## Healing projectile that homes toward an ally and heals them on arrival.

@export var move_speed: float = 450.0
@export var heal_amount: float = 40.0
@export var heal_color: Color = Color(0.3, 1.0, 0.5, 0.8)

var direction: Vector2 = Vector2.RIGHT
var _target: Node2D = null
var _healed: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION):
		direction = (ctx[ContextKeys.CAST_DIRECTION] as Vector2).normalized()
	if ctx.has(ContextKeys.CAST_TARGET) and ctx[ContextKeys.CAST_TARGET] is Node2D:
		_target = ctx[ContextKeys.CAST_TARGET] as Node2D
	if ctx.has(ContextKeys.PROJECTILE_SPEED):
		move_speed = float(ctx[ContextKeys.PROJECTILE_SPEED])

func _on_spawn() -> void:
	if spell_data != null:
		heal_amount = spell_data.heal_amount
		move_speed = spell_data.projectile_speed

func _spell_process(delta: float) -> void:
	if _healed:
		return

	if _target != null and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		if to_target.length() < 20.0:
			_apply_heal()
			return
		direction = to_target.normalized()

	global_position += direction * move_speed * delta
	rotation = direction.angle()

func _apply_heal() -> void:
	_healed = true
	if _target != null and is_instance_valid(_target) and _target.has_method("apply_healing"):
		var ctx := {
			ContextKeys.SOURCE: caster,
			ContextKeys.TARGET: _target,
			ContextKeys.ATTACK_ID: "Mending Touch",
			ContextKeys.DAMAGE_TYPE: "spell",
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell_data,
		}
		_target.apply_healing(heal_amount, ctx)
	queue_free()
