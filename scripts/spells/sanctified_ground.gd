extends SpellEntity
class_name SanctifiedGround

## Creates zone that heals allies for 5 HP/sec and grants +20% movement speed.

@export var zone_radius: float = 80.0
@export var heal_per_second: float = 5.0
@export var speed_bonus: float = 1.2  # 20% faster
@export var zone_color: Color = Color(0.4, 1.0, 0.6, 0.25)

@onready var zone_visual: ColorRect = $ZoneVisual

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]
	if ctx.has(ContextKeys.CAST_ROTATION):
		rotation = float(ctx[ContextKeys.CAST_ROTATION])

func _on_spawn() -> void:
	if zone_visual:
		zone_visual.color = zone_color

func _spell_process(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = zone_radius
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

		# Only affect allies
		if not is_ally(body) and body != caster:
			continue

		# Heal over time
		if body.has_method("apply_healing"):
			var heal_this_frame: float = heal_per_second * delta
			var ctx := {
				ContextKeys.SOURCE: caster,
				ContextKeys.TARGET: body,
				ContextKeys.ATTACK_ID: "Sanctified Ground",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			body.apply_healing(heal_this_frame, ctx)

func _on_expire() -> void:
	if zone_visual:
		zone_visual.color = Color(0.4, 1.0, 0.6, 0.05)
