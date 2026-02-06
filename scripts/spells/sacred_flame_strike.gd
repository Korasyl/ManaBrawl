extends SpellEntity
class_name SacredFlameStrike

@export var telegraph_time: float = 0.55
@export var strike_radius: float = 36.0
@export var strike_damage: float = 26.0
@export var strike_interrupt: String = "flinch"
@export var telegraph_color: Color = Color(1.0, 0.9, 0.35, 0.35)
@export var impact_color: Color = Color(1.0, 0.75, 0.2, 0.85)

@onready var telegraph: ColorRect = $Telegraph

var _timer: float = 0.0
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_TARGET):
		var t: Node = ctx[ContextKeys.CAST_TARGET]
		if t and is_instance_valid(t):
			global_position = t.global_position
	elif ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]

func _on_spawn() -> void:
	if spell_data != null:
		strike_damage = spell_data.damage
		strike_interrupt = spell_data.interrupt_type
	if telegraph:
		telegraph.color = telegraph_color

func _spell_process(delta: float) -> void:
	if _resolved:
		return

	_timer += delta
	if _timer >= telegraph_time:
		_resolve_strike()

func _resolve_strike() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

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
		var collider_variant: Variant = hit.get("collider", null)
		if collider_variant == null or not (collider_variant is Node):
			continue
		var body: Node = collider_variant
		if body == caster:
			continue
		if "team_id" in body and body.team_id == team_id:
			continue
		if body.has_method("take_damage"):
			var ctx := {
				ContextKeys.SOURCE: caster,
				ContextKeys.TARGET: body,
				ContextKeys.ATTACK_ID: "Sacred Flame",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			body.take_damage(strike_damage, Vector2.ZERO, strike_interrupt, ctx)

	queue_free()
