extends Area2D
class_name Projectile

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: float = 8.0
var damage_type: String = "ranged"  # Flows into ContextKeys.DAMAGE_TYPE
var interrupt_type: String = "flinch"
var source: Node = null
var team_id: int = 0
var lifetime: float = 3.0
var _lifetime_timer: float = 0.0

## Scene to spawn at impact point (vine grab, AoE zone, etc.)
var on_impact_scene: PackedScene = null

## Spell data reference (null for basic ranged)
var spell_data: SpellData = null

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var visual: ColorRect = $ColorRect

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	add_to_group("projectile")
	# Rotate visual to face travel direction
	rotation = direction.angle()

func _physics_process(delta):
	position += direction * speed * delta
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()

func _on_body_entered(body):
	# Don't hit the source
	if body == source:
		return

	# Hit walls — spawn impact entity if any, then destroy
	if body is StaticBody2D:
		_spawn_impact_entity(global_position)
		queue_free()
		return

	# Team check: don't damage allies
	if "team_id" in body and body.team_id == team_id:
		return

	# Hit a damageable target
	if body.has_method("take_damage"):
		var knockback := direction * 200
		var ctx := {
			ContextKeys.SOURCE: source,
			ContextKeys.ATTACK_ID: "ranged_basic" if spell_data == null else spell_data.spell_name,
			ContextKeys.DAMAGE_TYPE: damage_type,
			ContextKeys.TEAM_ID: team_id,
		}
		if spell_data != null:
			ctx[ContextKeys.SPELL_DATA] = spell_data
		body.take_damage(damage, knockback, interrupt_type, ctx)
		_spawn_impact_entity(body.global_position)
		queue_free()

## Projectile-on-projectile collision (for interception mechanics)
func _on_area_entered(area):
	if area == self:
		return
	# Projectile interception: if two enemy projectiles collide, both destroyed
	if area is Projectile and area.team_id != team_id:
		area.queue_free()
		queue_free()

## Deflect this projectile: reverse ownership and redirect.
## Used by Gravebrand's heavy melee, Aegis's shield, etc.
func deflect(new_direction: Vector2, new_owner: Node) -> void:
	direction = new_direction.normalized()
	source = new_owner
	if "team_id" in new_owner:
		team_id = new_owner.team_id
	rotation = direction.angle()
	# Reset lifetime so deflected projectile doesn't immediately expire
	_lifetime_timer = 0.0

## Spawn the on_impact_scene at a given position (if one is set).
func _spawn_impact_entity(pos: Vector2) -> void:
	if on_impact_scene == null:
		return
	var entity = on_impact_scene.instantiate()
	entity.global_position = pos
	# Pass context if the entity supports it
	if entity.has_method("initialize"):
		entity.initialize({
			ContextKeys.SOURCE: source,
			ContextKeys.CAST_DIRECTION: direction,
			ContextKeys.TEAM_ID: team_id,
		})
	# Set common SpellEntity fields
	if "caster" in entity:
		entity.caster = source
	if "team_id" in entity:
		entity.team_id = team_id
	if "spell_data" in entity and spell_data != null:
		entity.spell_data = spell_data
	get_tree().current_scene.add_child(entity)
