extends SpellEntity
class_name LightningJavelin

## Fast projectile that pierces through the first enemy, dealing reduced damage to targets behind.

@export var move_speed: float = 700.0
@export var base_damage: float = 25.0
@export var pierce_damage_mult: float = 0.6
@export var javelin_interrupt: String = "flinch"
@export var javelin_color: Color = Color(0.9, 0.95, 0.3, 0.9)

var direction: Vector2 = Vector2.RIGHT
var _hits: Array[Node] = []
var _max_pierce: int = 1
var _pierce_count: int = 0

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION):
		direction = (ctx[ContextKeys.CAST_DIRECTION] as Vector2).normalized()
	if ctx.has(ContextKeys.DAMAGE):
		base_damage = float(ctx[ContextKeys.DAMAGE])
	if ctx.has(ContextKeys.PROJECTILE_SPEED):
		move_speed = float(ctx[ContextKeys.PROJECTILE_SPEED])

func _on_spawn() -> void:
	if spell_data != null:
		base_damage = spell_data.damage
		javelin_interrupt = spell_data.interrupt_type
		move_speed = spell_data.projectile_speed
	rotation = direction.angle()

func _spell_process(delta: float) -> void:
	global_position += direction * move_speed * delta
	_check_hits()

func _check_hits() -> void:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = 10.0
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
		if body in _hits:
			continue
		# Hit a wall — destroy
		if body is StaticBody2D:
			queue_free()
			return
		if "team_id" in body and body.team_id == team_id:
			continue
		if body.has_method("take_damage"):
			_hits.append(body)
			var dmg: float = base_damage if _pierce_count == 0 else base_damage * pierce_damage_mult
			var ctx := {
				ContextKeys.SOURCE: caster,
				ContextKeys.TARGET: body,
				ContextKeys.ATTACK_ID: "Lightning Javelin",
				ContextKeys.DAMAGE_TYPE: "spell",
				ContextKeys.TEAM_ID: team_id,
				ContextKeys.SPELL_DATA: spell_data,
			}
			var knockback := direction * 150.0
			body.take_damage(dmg, knockback, javelin_interrupt, ctx)
			_pierce_count += 1
			if _pierce_count > _max_pierce:
				queue_free()
				return
