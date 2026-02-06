extends SpellEntity
class_name AegisBarrier

@export var barrier_size: Vector2 = Vector2(220.0, 18.0)
@export var barrier_color: Color = Color(0.35, 0.75, 1.0, 0.55)
@export var damaged_color: Color = Color(1.0, 0.45, 0.45, 0.7)

@onready var barrier_body: StaticBody2D = $BarrierBody
@onready var collision_shape: CollisionShape2D = $BarrierBody/CollisionShape2D
@onready var visual: ColorRect = $BarrierBody/ColorRect

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
		(collision_shape.shape as RectangleShape2D).size = barrier_size
	if visual:
		visual.color = barrier_color
		visual.size = barrier_size
		visual.position = -barrier_size * 0.5
	if barrier_body and barrier_body.has_method("set_owner_entity"):
		barrier_body.call("set_owner_entity", self)

func _spell_process(_delta: float) -> void:
	if max_hp <= 0:
		return
	if visual == null:
		return

	var hp_ratio: float = clampf(current_hp / max_hp, 0.0, 1.0)
	visual.color = damaged_color.lerp(barrier_color, hp_ratio)

func _on_expire() -> void:
	if visual:
		visual.color = Color(1.0, 1.0, 1.0, 0.2)
