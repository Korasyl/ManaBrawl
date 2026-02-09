extends SpellEntity
class_name ShockNova

## After 0.5s delay, creates electrical explosion at location dealing damage and stagger.

@export var warmup_time: float = 0.5
@export var burst_radius: float = 50.0
@export var burst_damage: float = 30.0
@export var burst_interrupt: String = "stagger"
@export var telegraph_color: Color = Color(0.9, 0.95, 0.3, 0.3)
@export var impact_color: Color = Color(1.0, 1.0, 0.4, 0.95)

@onready var telegraph: ColorRect = $Telegraph

var _timer: float = 0.0
var _resolved: bool = false

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_POSITION):
		global_position = ctx[ContextKeys.CAST_POSITION]
	if ctx.has(ContextKeys.DAMAGE):
		burst_damage = float(ctx[ContextKeys.DAMAGE])

func _on_spawn() -> void:
	if spell_data != null:
		burst_damage = spell_data.damage
		burst_interrupt = spell_data.interrupt_type
	if telegraph:
		telegraph.color = telegraph_color

func _spell_process(delta: float) -> void:
	if _resolved:
		return
	_timer += delta
	if _timer >= warmup_time:
		_resolve_burst()

func _resolve_burst() -> void:
	_resolved = true
	if telegraph:
		telegraph.color = impact_color

	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = burst_radius
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
				ContextKeys.ATTACK_ID: "Shock Nova",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			var knockback := (body.global_position - global_position).normalized() * 280.0
			body.take_damage(burst_damage, knockback, burst_interrupt, ctx)

	queue_free()
