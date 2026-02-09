extends SpellEntity
class_name EarthenWall

## Creates temporary solid barrier that blocks projectiles and movement. Lasts 6s.

@export var wall_size: Vector2 = Vector2(200.0, 20.0)
@export var wall_color: Color = Color(0.55, 0.4, 0.25, 0.7)
@export var damaged_color: Color = Color(0.7, 0.35, 0.2, 0.8)

@onready var wall_body: StaticBody2D = $WallBody
@onready var collision_shape: CollisionShape2D = $WallBody/CollisionShape2D
@onready var visual: ColorRect = $WallBody/ColorRect

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]
	if ctx.has(ContextKeys.CAST_ROTATION):
		rotation = float(ctx[ContextKeys.CAST_ROTATION])

func _on_spawn() -> void:
	if collision_shape and collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = wall_size
	if visual:
		visual.color = wall_color
		visual.size = wall_size
		visual.position = -wall_size * 0.5
	if wall_body and wall_body.has_method("set_owner_entity"):
		wall_body.call("set_owner_entity", self)

func _spell_process(_delta: float) -> void:
	if max_hp <= 0:
		return
	if visual == null:
		return

	var hp_ratio: float = clampf(current_hp / max_hp, 0.0, 1.0)
	visual.color = damaged_color.lerp(wall_color, hp_ratio)

func _on_expire() -> void:
	if visual:
		visual.color = Color(0.6, 0.5, 0.3, 0.2)
