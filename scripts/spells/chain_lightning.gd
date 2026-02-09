extends SpellEntity
class_name ChainLightning

## Arcing projectile that bounces to 2 nearby enemies after hitting primary target.

@export var move_speed: float = 600.0
@export var base_damage: float = 25.0
@export var bounce_damage_mult: float = 0.7
@export var bounce_range: float = 200.0
@export var max_bounces: int = 2
@export var chain_interrupt: String = "flinch"
@export var chain_color: Color = Color(0.3, 0.7, 1.0, 0.9)

var direction: Vector2 = Vector2.RIGHT
var _current_target: Node = null
var _hits: Array[Node] = []
var _bounce_count: int = 0

func initialize(ctx: Dictionary) -> void:
	caster = ctx.get(ContextKeys.SOURCE, caster)
	team_id = int(ctx.get(ContextKeys.TEAM_ID, team_id))
	spell_data = ctx.get(ContextKeys.SPELL_DATA, spell_data)
	if ctx.has(ContextKeys.CAST_DIRECTION):
		direction = (ctx[ContextKeys.CAST_DIRECTION] as Vector2).normalized()
	if ctx.has(ContextKeys.CAST_TARGET):
		_current_target = ctx[ContextKeys.CAST_TARGET]
	if ctx.has(ContextKeys.DAMAGE):
		base_damage = float(ctx[ContextKeys.DAMAGE])
	if ctx.has(ContextKeys.PROJECTILE_SPEED):
		move_speed = float(ctx[ContextKeys.PROJECTILE_SPEED])

func _on_spawn() -> void:
	if spell_data != null:
		base_damage = spell_data.damage
		chain_interrupt = spell_data.interrupt_type
		move_speed = spell_data.projectile_speed

func _spell_process(delta: float) -> void:
	# Home toward current target if we have one
	if _current_target != null and is_instance_valid(_current_target):
		var to_target: Vector2 = _current_target.global_position - global_position
		if to_target.length() < 20.0:
			_hit_target(_current_target)
			return
		direction = to_target.normalized()

	global_position += direction * move_speed * delta
	rotation = direction.angle()

	# If no target and just flying, check for wall collision
	if _current_target == null or not is_instance_valid(_current_target):
		_check_wall_hit()

func _hit_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	_hits.append(target)
	global_position = target.global_position

	if target.has_method("take_damage"):
		var dmg: float = base_damage if _bounce_count == 0 else base_damage * bounce_damage_mult
		var ctx := {
			ContextKeys.SOURCE: caster,
			ContextKeys.TARGET: target,
			ContextKeys.ATTACK_ID: "Chain Lightning",
			ContextKeys.DAMAGE_TYPE: "spell",
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell_data,
		}
		var knockback := direction * 100.0
		target.take_damage(dmg, knockback, chain_interrupt, ctx)

	_bounce_count += 1
	if _bounce_count > max_bounces:
		queue_free()
		return

	# Find next bounce target
	var next_target := _find_nearest_enemy(bounce_range)
	if next_target == null:
		queue_free()
		return

	_current_target = next_target

func _find_nearest_enemy(search_range: float) -> Node:
	var nearest: Node = null
	var nearest_dist: float = search_range

	for group_name in ["enemy", "training_dummy", "player"]:
		for body in get_tree().get_nodes_in_group(group_name):
			if body in _hits:
				continue
			if body == caster:
				continue
			if "team_id" in body and body.team_id == team_id:
				continue
			if not (body is Node2D):
				continue
			var dist: float = global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = body

	return nearest

func _check_wall_hit() -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position - direction * 5.0,
		global_position + direction * 5.0,
		1  # World layer
	)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		queue_free()
