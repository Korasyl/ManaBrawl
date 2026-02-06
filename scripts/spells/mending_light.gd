extends SpellEntity
class_name MendingLight

@export var telegraph_time: float = 0.35
@export var heal_radius: float = 36.0
@export var heal_amount: float = 30.0
@export var telegraph_color: Color = Color(0.3, 1.0, 0.5, 0.35)
@export var impact_color: Color = Color(0.4, 1.0, 0.6, 0.85)

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
		heal_amount = spell_data.heal_amount
	if telegraph:
		telegraph.color = telegraph_color

func _spell_process(delta: float) -> void:
	if _resolved:
		return

	_timer += delta
	if _timer >= telegraph_time:
		_resolve_heal()

func _resolve_heal() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = heal_radius
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
		# Only heal allies (same team)
		if not is_ally(body) and body != caster:
			continue
		if body.has_method("apply_healing"):
			var ctx := {
				ContextKeys.SOURCE: caster,
				ContextKeys.TARGET: body,
				ContextKeys.ATTACK_ID: "Mending Light",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			body.apply_healing(heal_amount, ctx)

	queue_free()
