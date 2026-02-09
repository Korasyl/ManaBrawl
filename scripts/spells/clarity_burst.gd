extends SpellEntity
class_name ClarityBurst

## Instantly restore 50 mana to target ally.

@export var mana_restore: float = 50.0
@export var telegraph_color: Color = Color(0.3, 0.5, 1.0, 0.35)
@export var impact_color: Color = Color(0.5, 0.7, 1.0, 0.9)

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
	_resolve_burst()

func _resolve_burst() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	global_position = _target.global_position

	# Restore mana directly
	if "current_mana" in _target and "stats" in _target and _target.stats != null:
		_target.current_mana = minf(_target.current_mana + mana_restore, _target.stats.max_mana)
