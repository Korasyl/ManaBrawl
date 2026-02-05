extends Area2D
class_name Projectile

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: float = 8.0
var interrupt_type: String = "flinch"
var source: Node = null
var lifetime: float = 3.0
var _lifetime_timer: float = 0.0

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var visual: ColorRect = $ColorRect

func _ready():
	body_entered.connect(_on_body_entered)
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

	# Hit walls — just destroy
	if body is StaticBody2D:
		queue_free()
		return

	# Hit a damageable target
	if body.has_method("take_damage"):
		var knockback := direction * 200
		var ctx := {
			ContextKeys.SOURCE: source,
			ContextKeys.ATTACK_ID: "ranged_basic",
			ContextKeys.DAMAGE_TYPE: "ranged"
		}
		body.take_damage(damage, knockback, interrupt_type, ctx)
		queue_free()
