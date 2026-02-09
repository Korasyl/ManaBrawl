extends SpellEntity
class_name TauntShout

## Enemies in cone are "marked" — if they attack anyone but the caster in next 4s, they take 15 damage.

@export var cone_angle: float = 60.0  # degrees, half-angle
@export var cone_range: float = 180.0
@export var mark_duration: float = 4.0
@export var mark_damage: float = 15.0
@export var telegraph_color: Color = Color(1.0, 0.5, 0.2, 0.35)
@export var impact_color: Color = Color(1.0, 0.6, 0.1, 0.9)

@onready var telegraph: ColorRect = $Telegraph

var _direction: Vector2 = Vector2.RIGHT
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION):
		_direction = (ctx[ContextKeys.CAST_DIRECTION] as Vector2).normalized()
	if ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]

func _on_spawn() -> void:
	if spell_data != null:
		mark_damage = spell_data.damage
	if telegraph:
		telegraph.color = telegraph_color
	rotation = _direction.angle()
	_resolve_shout()

func _resolve_shout() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

	var cone_rad: float = deg_to_rad(cone_angle)

	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = cone_range
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collide_with_bodies = true
	params.collide_with_areas = false

	var results: Array[Dictionary] = space.intersect_shape(params, 32)
	for hit in results:
		var body: Variant = hit.get("collider", null)
		if body == null or not (body is Node):
			continue
		if body == caster:
			continue
		if "team_id" in body and body.team_id == team_id:
			continue
		if not (body is Node2D):
			continue

		# Check cone
		var to_body: Vector2 = (body as Node2D).global_position - global_position
		var angle_to: float = abs(_direction.angle_to(to_body.normalized()))
		if angle_to > cone_rad:
			continue

		# Apply "taunted" custom status effect
		if body.has_node("StatusEffectManager"):
			var sem: StatusEffectManager = body.get_node("StatusEffectManager") as StatusEffectManager
			if sem:
				sem.apply_effect(StatusEffect.Type.CUSTOM, mark_duration, caster, mark_damage, "taunted")
