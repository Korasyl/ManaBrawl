extends CharacterBody2D

@export var stats: DummyStats

@onready var health_bar = $HealthBar
@onready var health_label = $HealthLabel
@onready var color_rect = $ColorRect
@onready var wall_check_left: RayCast2D = $WallCheckLeft
@onready var wall_check_right: RayCast2D = $WallCheckRight
@onready var detection_area: Area2D = $DetectionArea
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_collision: CollisionShape2D = $AttackHitbox/CollisionShape2D
var hit_bodies_this_attack: Array = []

var current_health: float
var is_dead: bool = false
var respawn_timer: float = 0.0
var original_color: Color
var hit_flash_timer: float = 0.0
var spawn_position: Vector2

# Stun/Interrupt states
var is_flinched: bool = false
var is_staggered: bool = false
var stun_timer: float = 0.0
const FLINCH_DURATION: float = 0.3
const STAGGER_DURATION: float = 0.3

# AI States
enum AIState { PATROL, ATTACKING, STUNNED, DEAD }
var ai_state: AIState = AIState.PATROL
var facing_direction: int = 1  # 1 = right, -1 = left
var patrol_speed: float = 100.0
var attack_cooldown: float = 0.0
var attack_cooldown_time: float = 2.0
var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_duration: float = 0.5  # Give hitbox more time to connect

func _ready():
	attack_hitbox.monitoring = true
	
	if stats:
		current_health = stats.max_health
		update_health_display()
	else:
		push_error("No DummyStats assigned to TrainingDummy!")
	
	# Store original color
	original_color = color_rect.color
	
	# Store spawn position
	spawn_position = global_position
	
	# Connect signals
	if detection_area:
		detection_area.body_entered.connect(_on_player_detected)
		print("Dummy: DetectionArea connected. Mask=%d" % detection_area.collision_mask)
	else:
		push_error("Dummy: DetectionArea not found!")
	
	if attack_hitbox:
		attack_hitbox.body_entered.connect(_on_attack_hit)
		print("Dummy: AttackHitbox connected. Mask=%d" % attack_hitbox.collision_mask)
	else:
		push_error("Dummy: AttackHitbox not found!")

func _draw():
	if not attack_hitbox:
		return
	
	# Draw detection range
	draw_circle(Vector2(0, -40), 100, Color(0, 1, 1, 0.1))  # Cyan circle for detection
	
	# Draw attack hitbox position
	var hitbox_pos = attack_hitbox.position
	var hitbox_rect = Rect2(hitbox_pos.x - 35, hitbox_pos.y - 25, 70, 50)
	
	var hitbox_color = Color.GREEN if is_attacking else Color.RED
	hitbox_color.a = 0.3
	draw_rect(hitbox_rect, hitbox_color, false, 2.0)  # Outline
	
	# Draw facing direction arrow
	var arrow_end = Vector2(30 * facing_direction, -40)
	draw_line(Vector2(0, -40), arrow_end, Color.YELLOW, 3.0)

func _physics_process(delta):
	# Handle respawn
	if is_dead:
		ai_state = AIState.DEAD
		respawn_timer -= delta
		if respawn_timer <= 0:
			respawn()
		return
	
	# Handle stun
	if stun_timer > 0:
		ai_state = AIState.STUNNED
		stun_timer -= delta
		velocity.x = 0
		if stun_timer <= 0:
			end_stun()
	
	# Handle attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	# Handle attack duration
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0:
			end_dummy_attack()
	
	# Handle hit flash
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			if is_flinched:
				color_rect.modulate = Color(1.0, 0.8, 0.0)
			elif is_staggered:
				color_rect.modulate = Color(1.0, 0.3, 0.0)
			else:
				color_rect.modulate = Color.WHITE
	
	# AI behavior
	match ai_state:
		AIState.PATROL:
			handle_patrol(delta)
		AIState.ATTACKING:
			velocity.x = 0  # Stay still while attacking
		AIState.STUNNED:
			velocity.x = 0
	
	# Physics
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
	
	if is_on_floor() and ai_state != AIState.PATROL:
		velocity.x = lerp(velocity.x, 0.0, 0.15)
	
	move_and_slide()
	queue_redraw()

func handle_patrol(delta):
	# Check walls and turn around
	if wall_check_right.is_colliding():
		facing_direction = -1
	elif wall_check_left.is_colliding():
		facing_direction = 1
	
	# Move
	velocity.x = facing_direction * patrol_speed
	
	# Position attack hitbox for current facing
	update_attack_hitbox_position()

func update_attack_hitbox_position():
	# Position hitbox in front of dummy based on facing direction
	if attack_hitbox:
		attack_hitbox.position.x = 50 * facing_direction  # 50 pixels in front
		attack_hitbox.position.y = -40  # Middle height

func _on_player_detected(body):
	print("Dummy: Player detected! body=%s, state=%s, attacking=%s, cooldown=%.1f" % [body.name, AIState.keys()[ai_state], is_attacking, attack_cooldown])
	
	# Can't attack if stunned, dead, already attacking, or on cooldown
	if ai_state in [AIState.STUNNED, AIState.DEAD]:
		return
	if is_attacking or attack_cooldown > 0:
		return
	
	# Must be player
	if not (body.is_in_group("player") or body.name == "Player"):
		print("  -> Not player, ignoring")
		return
	
	# Face the player
	if body.global_position.x < global_position.x:
		facing_direction = -1
	else:
		facing_direction = 1
	
	update_attack_hitbox_position()
	perform_dummy_attack()

func perform_dummy_attack():
	print("Dummy: Starting attack! facing=%d, hitbox_pos=%s" % [facing_direction, attack_hitbox.position])
	
	ai_state = AIState.ATTACKING
	is_attacking = true
	attack_timer = attack_duration
	attack_cooldown = attack_cooldown_time
	
	# Make sure hitbox is positioned correctly
	update_attack_hitbox_position()
	
	# Enable hitbox
	attack_collision.set_deferred("disabled", false)
	call_deferred("_apply_attack_overlap_hits")
	print("  -> Hitbox ENABLED. Disabled=%s" % attack_collision.disabled)
	
	# Visual feedback
	color_rect.modulate = Color(1.0, 0.3, 0.3)
	
	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=red]Dummy ATTACKS![/color]")

func end_dummy_attack():
	print("Dummy: Ending attack. Hitbox was disabled=%s" % attack_collision.disabled)
	
	is_attacking = false
	attack_collision.set_deferred("disabled", true)
	print("  -> Hitbox now DISABLED=%s" % attack_collision.disabled)
	
	if ai_state == AIState.ATTACKING:
		ai_state = AIState.PATROL
	
	if not is_flinched and not is_staggered:
		color_rect.modulate = Color.WHITE

func _on_attack_hit(body):
	print("Dummy: Attack hitbox entered! body=%s, is_attacking=%s" % [body.name, is_attacking])
	
	if not is_attacking:
		print("  -> Not currently attacking, ignoring")
		return
	
	# Must be player
	if not (body.is_in_group("player") or body.name == "Player"):
		print("  -> Not player, ignoring")
		return
	
	# Deal damage
	if body.has_method("take_damage"):
		var damage = 10.0
		var knockback = Vector2(facing_direction * 300, -150)
		
		print("  -> Dealing %d damage with knockback %s" % [damage, knockback])
		var ctx := {
			ContextKeys.SOURCE: self,
			ContextKeys.ATTACK_ID: "dummy_attack",
			ContextKeys.DAMAGE_TYPE: "melee"
		}
		body.take_damage(damage, knockback, "flinch", ctx)
		
		# Disable hitbox after first hit (no multi-hitting)
		attack_collision.set_deferred("disabled", true)
	else:
		print("  -> Body has no take_damage method!")

func _apply_attack_overlap_hits() -> void:
	if not is_attacking or attack_hitbox == null:
		return

	# Make sure monitoring is on
	attack_hitbox.monitoring = true

	var bodies := attack_hitbox.get_overlapping_bodies()
	for b in bodies:
		_on_attack_hit(b)

func take_damage(damage: float, knockback_velocity: Vector2 = Vector2.ZERO, interrupt_type: String = "none", ctx: Dictionary = {}):
	if is_dead:
		return
	
	current_health -= damage
	update_health_display()
	
	# Flash
	color_rect.modulate = Color.WHITE
	hit_flash_timer = 0.1
	
	# Interrupt
	match interrupt_type:
		"flinch":
			if not is_staggered:
				apply_flinch()
		"stagger":
			apply_stagger()
	
	# Knockback
	if stats.can_be_knocked_back and knockback_velocity != Vector2.ZERO:
		velocity = knockback_velocity * (1.0 - stats.knockback_resistance)
	
	# Death check
	if current_health <= 0:
		die()

func apply_flinch():
	is_flinched = true
	is_staggered = false
	stun_timer = FLINCH_DURATION
	ai_state = AIState.STUNNED
	
	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=yellow]Dummy FLINCHED![/color]")

func apply_stagger():
	is_flinched = false
	is_staggered = true
	stun_timer = STAGGER_DURATION
	ai_state = AIState.STUNNED
	
	# Cancel attack
	if is_attacking:
		end_dummy_attack()
	
	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=orange]Dummy STAGGERED![/color]")

func end_stun():
	is_flinched = false
	is_staggered = false
	color_rect.modulate = Color.WHITE
	
	if not is_dead:
		ai_state = AIState.PATROL

func update_health_display():
	if health_bar and health_label:
		health_bar.max_value = stats.max_health
		health_bar.value = current_health
		health_label.text = "%.0f/%.0f" % [current_health, stats.max_health]

func die():
	is_dead = true
	respawn_timer = stats.respawn_time
	color_rect.modulate = Color.DIM_GRAY
	health_label.text = "DEAD (%.1fs)" % respawn_timer
	
	is_flinched = false
	is_staggered = false
	stun_timer = 0.0

func respawn():
	is_dead = false
	current_health = stats.max_health
	velocity = Vector2.ZERO
	color_rect.modulate = Color.WHITE
	global_position = spawn_position
	update_health_display()

func _process(delta):
	if is_dead and health_label:
		health_label.text = "DEAD (%.1fs)" % respawn_timer
	
	# DEBUG: Show attack hitbox state every frame
	if attack_collision:
		var state_text = "ENABLED" if not attack_collision.disabled else "DISABLED"
		var color_to_use = Color.GREEN if not attack_collision.disabled else Color.RED
		
		# If there's a ColorRect child, update its color
		if attack_hitbox.has_node("ColorRect"):
			var rect = attack_hitbox.get_node("ColorRect")
			rect.color = color_to_use
			rect.color.a = 0.3  # Keep transparent
