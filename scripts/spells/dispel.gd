extends SpellEntity
class_name Dispel

## Removes all status effects from target (buffs if enemy, debuffs if ally).

@export var telegraph_color: Color = Color(1.0, 1.0, 0.8, 0.35)
@export var impact_color: Color = Color(1.0, 1.0, 1.0, 0.9)

@onready var telegraph: ColorRect = $Telegraph

var _target: Node = null
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_TARGET):
		_target = ctx[ContextKeys.CAST_TARGET]
	elif ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]

func _on_spawn() -> void:
	if telegraph:
		telegraph.color = telegraph_color
	_resolve_dispel()

func _resolve_dispel() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	global_position = _target.global_position

	if not _target.has_node("StatusEffectManager"):
		return

	var sem: StatusEffectManager = _target.get_node("StatusEffectManager") as StatusEffectManager
	if sem == null:
		return

	# Clear all status effects from target
	sem.clear_all()
