extends SpellEntity
class_name VampiricStrike

## Projectile that deals damage and heals caster for 40% of damage dealt.

@export var move_speed: float = 500.0
@export var base_damage: float = 25.0
@export var lifesteal_percent: float = 0.4
@export var strike_interrupt: String = "flinch"
@export var strike_color: Color = Color(0.8, 0.1, 0.3, 0.9)

var direction: Vector2 = Vector2.RIGHT
var _current_target: Node2D = null
var _hit: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION):
		direction = (ctx[ContextKeys.CAST_DIRECTION] as Vector2).normalized()
	if ctx.has(ContextKeys.CAST_TARGET) and ctx[ContextKeys.CAST_TARGET] is Node2D:
		_current_target = ctx[ContextKeys.CAST_TARGET] as Node2D
	if ctx.has(ContextKeys.DAMAGE):
		base_damage = float(ctx[ContextKeys.DAMAGE])
	if ctx.has(ContextKeys.PROJECTILE_SPEED):
		move_speed = float(ctx[ContextKeys.PROJECTILE_SPEED])

func _on_spawn() -> void:
	if spell_data != null:
		base_damage = spell_data.damage
		strike_interrupt = spell_data.interrupt_type
		move_speed = spell_data.projectile_speed

func _spell_process(delta: float) -> void:
	if _hit:
		return

	# Home toward target
	if _current_target != null and is_instance_valid(_current_target):
		var to_target := _current_target.global_position - global_position
		if to_target.length() < 20.0:
			_apply_strike(_current_target)
			return
		# Gentle homing
		var desired := to_target.normalized()
		direction = direction.slerp(desired, clampf(8.0 * delta, 0.0, 1.0)).normalized()

	global_position += direction * move_speed * delta
	rotation = direction.angle()

	# Check wall collision
	_check_wall()

func _apply_strike(target: Node) -> void:
	_hit = true
	if target.has_method("take_damage"):
		var ctx := {
			ContextKeys.SOURCE: caster,
			ContextKeys.TARGET: target,
			ContextKeys.ATTACK_ID: "Vampiric Strike",
			ContextKeys.DAMAGE_TYPE: "spell",
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell_data,
		}
		var knockback := direction * 120.0
		target.take_damage(base_damage, knockback, strike_interrupt, ctx)

	# Heal caster for lifesteal
	if caster != null and is_instance_valid(caster) and caster.has_method("apply_healing"):
		var heal_amount: float = base_damage * lifesteal_percent
		var heal_ctx := {
			ContextKeys.SOURCE: caster,
			ContextKeys.TARGET: caster,
			ContextKeys.ATTACK_ID: "Vampiric Strike",
			ContextKeys.DAMAGE_TYPE: "spell",
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell_data,
		}
		caster.apply_healing(heal_amount, heal_ctx)

	queue_free()

func _check_wall() -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position - direction * 5.0,
		global_position + direction * 5.0,
		1  # World layer
	)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		queue_free()
