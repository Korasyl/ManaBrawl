extends SpellEntity
class_name GuardiansLeap

## Dash to ally and grant them +50 temporary shield for 4s.
## Shield is approximated as healing + damage reduction status effect.

@export var shield_amount: float = 50.0
@export var shield_duration: float = 4.0
@export var telegraph_color: Color = Color(0.3, 0.8, 1.0, 0.35)
@export var impact_color: Color = Color(0.4, 0.9, 1.0, 0.9)

@onready var telegraph: ColorRect = $Telegraph

var _target: Node = null
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_TARGET):
		_target = ctx[ContextKeys.CAST_TARGET]

func _on_spawn() -> void:
	if telegraph:
		telegraph.color = telegraph_color
	_execute_leap()

func _execute_leap() -> void:
	_resolved = true
	if _target == null or not is_instance_valid(_target) or caster == null or not is_instance_valid(caster):
		queue_free()
		return

	# Teleport caster to ally
	caster.global_position = _target.global_position + Vector2(40, 0)
	global_position = _target.global_position

	if telegraph:
		telegraph.color = impact_color

	# Grant shield as healing (temporary HP)
	if _target.has_method("apply_healing"):
		var ctx := {
			ContextKeys.SOURCE: caster,
			ContextKeys.TARGET: _target,
			ContextKeys.ATTACK_ID: "Guardian's Leap",
			ContextKeys.DAMAGE_TYPE: "spell",
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell_data,
		}
		_target.apply_healing(shield_amount, ctx)

	# Apply a custom "shielded" status effect for visual/tracking
	if _target.has_node("StatusEffectManager"):
		var sem: StatusEffectManager = _target.get_node("StatusEffectManager") as StatusEffectManager
		if sem:
			sem.apply_effect(StatusEffect.Type.CUSTOM, shield_duration, caster, 1.0, "guardian_shield")
