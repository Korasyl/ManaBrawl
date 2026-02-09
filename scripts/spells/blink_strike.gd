extends SpellEntity
class_name BlinkStrike

## Instantly teleport behind enemy and deliver a melee strike.

@export var strike_damage: float = 20.0
@export var strike_radius: float = 30.0
@export var strike_interrupt: String = "flinch"
@export var telegraph_color: Color = Color(0.6, 0.2, 1.0, 0.4)
@export var impact_color: Color = Color(0.8, 0.4, 1.0, 0.9)
@export var blink_offset: float = 50.0

@onready var telegraph: ColorRect = $Telegraph

var _target: Node = null
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_TARGET):
		_target = ctx[ContextKeys.CAST_TARGET]
	if ctx.has(ContextKeys.DAMAGE):
		strike_damage = float(ctx[ContextKeys.DAMAGE])

func _on_spawn() -> void:
	if spell_data != null:
		strike_damage = spell_data.damage
		strike_interrupt = spell_data.interrupt_type
	if telegraph:
		telegraph.color = telegraph_color
	_execute_blink()

func _execute_blink() -> void:
	_resolved = true
	if _target == null or not is_instance_valid(_target) or caster == null or not is_instance_valid(caster):
		queue_free()
		return

	# Teleport caster behind target
	var dir_to_target: Vector2 = (_target.global_position - caster.global_position).normalized()
	var behind_pos: Vector2 = _target.global_position + dir_to_target * blink_offset
	caster.global_position = behind_pos
	global_position = _target.global_position

	if telegraph:
		telegraph.color = impact_color

	# Deal damage in radius
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = strike_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collide_with_bodies = true
	params.collide_with_areas = false

	var results: Array[Dictionary] = space.intersect_shape(params, 16)
	for hit in results:
		var body: Variant = hit.get("collider", null)
		if body == null or not (body is Node):
			continue
		if body == caster:
			continue
		if "team_id" in body and body.team_id == team_id:
			continue
		if body.has_method("take_damage"):
			var ctx := {
				ContextKeys.SOURCE: caster,
				ContextKeys.TARGET: body,
				ContextKeys.ATTACK_ID: "Blink Strike",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			body.take_damage(strike_damage, Vector2.ZERO, strike_interrupt, ctx)
