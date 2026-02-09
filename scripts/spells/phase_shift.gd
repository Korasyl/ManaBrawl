extends SpellEntity
class_name PhaseShift

## Short-range teleport to cursor location (ignores terrain).

@export var max_range: float = 250.0
@export var afterimage_color: Color = Color(0.5, 0.3, 1.0, 0.5)
@export var arrival_color: Color = Color(0.6, 0.4, 1.0, 0.8)

@onready var telegraph: ColorRect = $Telegraph

var _target_pos: Vector2 = Vector2.ZERO
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION) and ctx.has(ContextKeys.CAST_POSITION):
		var cast_dir: Vector2 = ctx[ContextKeys.CAST_DIRECTION]
		var origin: Vector2 = ctx[ContextKeys.CAST_POSITION]
		# Teleport in cast direction, clamped to max range
		if caster != null and is_instance_valid(caster):
			var mouse_offset: Vector2 = cast_dir * max_range
			_target_pos = caster.global_position + mouse_offset.limit_length(max_range)
		else:
			_target_pos = origin + cast_dir * max_range

func _on_spawn() -> void:
	if telegraph:
		telegraph.color = afterimage_color
	_execute_shift()

func _execute_shift() -> void:
	_resolved = true
	if caster == null or not is_instance_valid(caster):
		queue_free()
		return

	# Place afterimage at origin
	global_position = caster.global_position

	# Teleport caster to target
	caster.global_position = _target_pos

	if telegraph:
		telegraph.color = afterimage_color
