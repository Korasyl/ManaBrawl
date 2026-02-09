extends SpellEntity
class_name GravityWell

## Creates zone that pulls enemies toward center slowly for 4s.

@export var pull_radius: float = 120.0
@export var pull_strength: float = 80.0  # pixels per second toward center
@export var zone_color: Color = Color(0.4, 0.1, 0.6, 0.3)

@onready var zone_visual: ColorRect = $ZoneVisual

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]

func _on_spawn() -> void:
	if zone_visual:
		zone_visual.color = zone_color

func _spell_process(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = pull_radius
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
		if not (body is CharacterBody2D):
			continue

		# Pull toward center
		var to_center: Vector2 = global_position - body.global_position
		var dist: float = to_center.length()
		if dist < 5.0:
			continue
		var pull_dir: Vector2 = to_center.normalized()
		# Stronger pull at edges, weaker near center
		var pull_factor: float = clampf(dist / pull_radius, 0.0, 1.0)
		body.global_position += pull_dir * pull_strength * pull_factor * delta

func _on_expire() -> void:
	if zone_visual:
		zone_visual.color = Color(0.4, 0.1, 0.6, 0.05)
