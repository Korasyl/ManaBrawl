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

var current_health: float
var is_dead: bool = false
var respawn_timer: float = 0.0
var original_color: Color
var hit_flash_timer: float = 0.0
var spawn_position: Vector2

## Team identity (1 = enemy team for demo)
var team_id: int = 1

## Status effects (needed for DOT/HOT from targeted ranged modes and spells)
var status_effects: StatusEffectManager

# Stun/Interrupt
var is_flinched: bool = false
var is_staggered: bool = false
var stun_timer: float = 0.0
const FLINCH_DURATION: float = 0.3
const STAGGER_DURATION: float = 0.3

# ---- Behavior system ----
enum BehaviorMode { LIGHT_COMBO, LIGHT_HEAVY_MIXUP, HEAVY_ONLY, BLOCK, DASH_EVADE }
var behavior_mode: int = BehaviorMode.LIGHT_COMBO

# AI States
enum AIState { PATROL, WINDUP, ATTACKING, SEQUENCE_GAP, COOLDOWN, BLOCKING, DASHING, STUNNED, DEAD }
var ai_state: AIState = AIState.PATROL
var facing_direction: int = 1
var patrol_speed: float = 100.0

# Attack system
var is_attacking: bool = false
var is_heavy_attack: bool = false
var attack_timer: float = 0.0
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 1.5

# Attack sequence
var attack_sequence: Array = []
var sequence_step: int = -1
var sequence_timer: float = 0.0

# Block
var is_blocking: bool = false
var block_broken: bool = false
var block_broken_timer: float = 0.0
const BLOCK_BROKEN_DURATION: float = 2.0

# Dash
var is_dashing: bool = false
var dash_timer: float = 0.0
const DASH_SPEED: float = 400.0
const DASH_DURATION: float = 0.25

# Target tracking
var target_player: Node = null

# Attack constants
const LIGHT_ATTACK_DURATION: float = 0.4
const HEAVY_WINDUP_DURATION: float = 0.4
const HEAVY_ATTACK_DURATION: float = 0.5
const COMBO_GAP: float = 0.3
const LIGHT_DAMAGE: float = 10.0
const HEAVY_DAMAGE: float = 20.0

func _ready():
	add_to_group("training_dummy")
	attack_hitbox.monitoring = true

	if stats:
		current_health = stats.max_health
		update_health_display()
	else:
		push_error("No DummyStats assigned to TrainingDummy!")

	# Initialize status effects for DOT/HOT support
	status_effects = StatusEffectManager.new()
	add_child(status_effects)
	status_effects.initialize(self)

	original_color = color_rect.color
	spawn_position = global_position

	if detection_area:
		detection_area.body_entered.connect(_on_player_detected)
		detection_area.body_exited.connect(_on_player_lost)

	if attack_hitbox:
		attack_hitbox.body_entered.connect(_on_attack_hit)

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

	# Handle block broken recovery
	if block_broken:
		block_broken_timer -= delta
		if block_broken_timer <= 0:
			block_broken = false
			if behavior_mode == BehaviorMode.BLOCK:
				enter_block()

	# Handle hit flash
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			_update_visual()

	# AI behavior
	match ai_state:
		AIState.PATROL:
			handle_patrol(delta)
		AIState.WINDUP:
			handle_windup(delta)
		AIState.ATTACKING:
			handle_active_attack(delta)
		AIState.SEQUENCE_GAP:
			handle_sequence_gap(delta)
		AIState.COOLDOWN:
			handle_cooldown(delta)
		AIState.BLOCKING:
			handle_blocking_state(delta)
		AIState.DASHING:
			handle_dash(delta)
		AIState.STUNNED:
			velocity.x = 0

	# Physics
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	if is_on_floor() and ai_state != AIState.PATROL and ai_state != AIState.DASHING:
		velocity.x = lerp(velocity.x, 0.0, 0.15)

	move_and_slide()
	queue_redraw()

# ---- AI State Handlers ----

func handle_patrol(delta):
	if wall_check_right.is_colliding():
		facing_direction = -1
	elif wall_check_left.is_colliding():
		facing_direction = 1

	velocity.x = facing_direction * patrol_speed
	update_attack_hitbox_position()

func handle_windup(delta):
	sequence_timer -= delta
	velocity.x = 0
	if sequence_timer <= 0:
		_activate_attack_hitbox()

func handle_active_attack(delta):
	attack_timer -= delta
	velocity.x = 0
	if attack_timer <= 0:
		end_current_attack()

func handle_sequence_gap(delta):
	sequence_timer -= delta
	velocity.x = 0
	if sequence_timer <= 0:
		start_sequence_step()

func handle_cooldown(delta):
	attack_cooldown -= delta
	velocity.x = 0
	if attack_cooldown <= 0:
		if target_player != null and is_instance_valid(target_player):
			face_target(target_player)
			start_behavior()
		else:
			ai_state = AIState.PATROL

func handle_blocking_state(delta):
	velocity.x = 0
	if target_player != null and is_instance_valid(target_player):
		face_target(target_player)

func handle_dash(delta):
	dash_timer -= delta
	if dash_timer <= 0:
		is_dashing = false
		ai_state = AIState.COOLDOWN
		attack_cooldown = ATTACK_COOLDOWN_TIME
		velocity.x = 0
		_update_visual()

# ---- Behavior Mode System ----

func set_behavior_mode(mode: int) -> void:
	behavior_mode = mode
	_reset_combat_state()

	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=white]Dummy mode: %s[/color]" % BehaviorMode.keys()[mode])

	if mode == BehaviorMode.BLOCK and not is_dead:
		enter_block()
	else:
		ai_state = AIState.PATROL

func _reset_combat_state() -> void:
	is_attacking = false
	is_heavy_attack = false
	is_blocking = false
	is_dashing = false
	block_broken = false
	block_broken_timer = 0.0
	attack_sequence.clear()
	sequence_step = -1
	sequence_timer = 0.0
	attack_timer = 0.0
	attack_cooldown = 0.0
	dash_timer = 0.0
	attack_collision.set_deferred("disabled", true)
	if status_effects:
		status_effects.clear_all()
	_update_visual()

func start_behavior() -> void:
	match behavior_mode:
		BehaviorMode.LIGHT_COMBO:
			attack_sequence = ["light", "light", "light"]
			_begin_sequence()
		BehaviorMode.LIGHT_HEAVY_MIXUP:
			attack_sequence = ["light", "light", "heavy"]
			_begin_sequence()
		BehaviorMode.HEAVY_ONLY:
			attack_sequence = ["heavy"]
			_begin_sequence()
		BehaviorMode.BLOCK:
			enter_block()
		BehaviorMode.DASH_EVADE:
			if target_player != null and is_instance_valid(target_player):
				start_dash()
			else:
				ai_state = AIState.PATROL

# ---- Attack Sequence ----

func _begin_sequence() -> void:
	sequence_step = 0
	start_sequence_step()

func start_sequence_step() -> void:
	if sequence_step >= attack_sequence.size():
		_end_sequence()
		return

	var step_type: String = attack_sequence[sequence_step]
	face_target_if_possible()
	update_attack_hitbox_position()

	if step_type == "heavy":
		is_heavy_attack = true
		ai_state = AIState.WINDUP
		sequence_timer = HEAVY_WINDUP_DURATION
		color_rect.modulate = Color(1.0, 0.6, 0.0)  # Orange for windup
		var hud = get_tree().get_first_node_in_group("debug_hud")
		if hud and hud.has_method("log_action"):
			hud.log_action("[color=orange]Dummy winding up HEAVY...[/color]")
	else:
		is_heavy_attack = false
		_activate_attack_hitbox()

func _activate_attack_hitbox() -> void:
	is_attacking = true
	ai_state = AIState.ATTACKING
	attack_timer = HEAVY_ATTACK_DURATION if is_heavy_attack else LIGHT_ATTACK_DURATION

	attack_collision.set_deferred("disabled", false)
	call_deferred("_apply_attack_overlap_hits")

	if is_heavy_attack:
		color_rect.modulate = Color(1.0, 0.2, 0.0)  # Red-orange for heavy
	else:
		color_rect.modulate = Color(1.0, 0.3, 0.3)  # Red for light

	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		var type_str := "HEAVY" if is_heavy_attack else "Light"
		hud.log_action("[color=red]Dummy %s ATTACK![/color]" % type_str)

func end_current_attack() -> void:
	is_attacking = false
	attack_collision.set_deferred("disabled", true)
	_update_visual()

	sequence_step += 1
	if sequence_step < attack_sequence.size():
		ai_state = AIState.SEQUENCE_GAP
		sequence_timer = COMBO_GAP
	else:
		_end_sequence()

func _end_sequence() -> void:
	is_attacking = false
	is_heavy_attack = false
	attack_sequence.clear()
	sequence_step = -1
	attack_collision.set_deferred("disabled", true)
	ai_state = AIState.COOLDOWN
	attack_cooldown = ATTACK_COOLDOWN_TIME
	_update_visual()

# Compatibility: player's clash detection calls this
func end_dummy_attack() -> void:
	is_attacking = false
	is_heavy_attack = false
	attack_collision.set_deferred("disabled", true)
	_end_sequence()

# ---- Block ----

func enter_block() -> void:
	if block_broken:
		return
	is_blocking = true
	ai_state = AIState.BLOCKING
	color_rect.modulate = Color(0.3, 0.5, 1.0)  # Blue for blocking
	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=cyan]Dummy BLOCKING[/color]")

# ---- Dash ----

func start_dash() -> void:
	if target_player == null or not is_instance_valid(target_player):
		return

	# Dash away from player
	var dir := -1 if target_player.global_position.x > global_position.x else 1
	facing_direction = -dir  # Face the player while dashing back

	is_dashing = true
	dash_timer = DASH_DURATION
	ai_state = AIState.DASHING
	velocity = Vector2(dir * DASH_SPEED, -100)

	color_rect.modulate = Color(0.5, 1.0, 0.5)  # Green for dash
	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=green]Dummy DASH![/color]")

# ---- Detection ----

func _on_player_detected(body):
	if not (body.is_in_group("player") or body.name == "Player"):
		return

	target_player = body

	# Only start new behavior if idle/patrolling
	if ai_state != AIState.PATROL:
		return

	face_target(body)
	update_attack_hitbox_position()
	start_behavior()

func _on_player_lost(body):
	if body == target_player:
		target_player = null

# ---- Helpers ----

func face_target(target: Node) -> void:
	if target.global_position.x < global_position.x:
		facing_direction = -1
	else:
		facing_direction = 1

func face_target_if_possible() -> void:
	if target_player != null and is_instance_valid(target_player):
		face_target(target_player)

func update_attack_hitbox_position():
	if attack_hitbox:
		attack_hitbox.position.x = 50 * facing_direction
		attack_hitbox.position.y = -40

func _update_visual() -> void:
	if is_blocking:
		color_rect.modulate = Color(0.3, 0.5, 1.0)
	elif is_flinched:
		color_rect.modulate = Color(1.0, 0.8, 0.0)
	elif is_staggered:
		color_rect.modulate = Color(1.0, 0.3, 0.0)
	elif block_broken:
		color_rect.modulate = Color(0.5, 0.2, 0.2)
	else:
		color_rect.modulate = Color.WHITE

# ---- Damage ----

func _on_attack_hit(body):
	if not is_attacking:
		return
	if not (body.is_in_group("player") or body.name == "Player"):
		return

	if body.has_method("take_damage"):
		var damage := HEAVY_DAMAGE if is_heavy_attack else LIGHT_DAMAGE
		var knockback_mult := 1.5 if is_heavy_attack else 1.0
		var knockback := Vector2(facing_direction * 300 * knockback_mult, -150)
		var interrupt := "stagger" if is_heavy_attack else "flinch"

		var ctx := {
			ContextKeys.SOURCE: self,
			ContextKeys.ATTACK_ID: "dummy_heavy" if is_heavy_attack else "dummy_light",
			ContextKeys.DAMAGE_TYPE: "melee"
		}
		body.take_damage(damage, knockback, interrupt, ctx)

		# Disable hitbox after first hit
		attack_collision.set_deferred("disabled", true)

func _apply_attack_overlap_hits() -> void:
	if not is_attacking or attack_hitbox == null:
		return
	attack_hitbox.monitoring = true
	var bodies := attack_hitbox.get_overlapping_bodies()
	for b in bodies:
		_on_attack_hit(b)

func apply_healing(amount: float, _ctx: Dictionary = {}) -> void:
	if is_dead or amount <= 0.0:
		return
	if stats == null:
		return
	current_health = min(current_health + amount, stats.max_health)
	update_health_display()

func is_ally(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id == team_id
	return false

func is_enemy(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id != team_id
	return other != self

func take_damage(damage: float, knockback_velocity: Vector2 = Vector2.ZERO, interrupt_type: String = "none", ctx: Dictionary = {}):
	if is_dead:
		return

	# Dash i-frames
	if is_dashing:
		return

	# Block absorption (light attacks)
	if is_blocking and interrupt_type == "flinch":
		var hud = get_tree().get_first_node_in_group("debug_hud")
		if hud and hud.has_method("log_action"):
			hud.log_action("[color=cyan]Dummy BLOCKED![/color]")
		return

	# Shield break (heavy attack vs block)
	if is_blocking and interrupt_type == "stagger":
		is_blocking = false
		block_broken = true
		block_broken_timer = BLOCK_BROKEN_DURATION
		color_rect.modulate = Color(0.5, 0.2, 0.2)
		var hud = get_tree().get_first_node_in_group("debug_hud")
		if hud and hud.has_method("log_action"):
			hud.log_action("[color=red]Dummy SHIELD BREAK![/color]")
		return  # No damage on shield break

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

	if current_health <= 0:
		die()

func apply_flinch():
	is_flinched = true
	is_staggered = false
	stun_timer = FLINCH_DURATION
	ai_state = AIState.STUNNED

	# Cancel current attack
	if is_attacking:
		is_attacking = false
		attack_collision.set_deferred("disabled", true)
		attack_sequence.clear()
		sequence_step = -1

	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=yellow]Dummy FLINCHED![/color]")

func apply_stagger():
	is_flinched = false
	is_staggered = true
	stun_timer = STAGGER_DURATION
	ai_state = AIState.STUNNED

	# Cancel current attack
	if is_attacking:
		is_attacking = false
		attack_collision.set_deferred("disabled", true)
		attack_sequence.clear()
		sequence_step = -1

	var hud = get_tree().get_first_node_in_group("debug_hud")
	if hud and hud.has_method("log_action"):
		hud.log_action("[color=orange]Dummy STAGGERED![/color]")

func end_stun():
	is_flinched = false
	is_staggered = false
	_update_visual()

	if is_dead:
		return

	# After stun recovery, resume behavior based on mode
	if behavior_mode == BehaviorMode.DASH_EVADE and target_player != null and is_instance_valid(target_player):
		start_dash()
	elif behavior_mode == BehaviorMode.BLOCK:
		enter_block()
	else:
		ai_state = AIState.PATROL

# ---- Health / Respawn ----

func update_health_display():
	if health_bar and health_label:
		health_bar.max_value = stats.max_health
		health_bar.value = current_health
		health_label.text = "%.0f/%.0f" % [current_health, stats.max_health]

func die():
	is_dead = true
	respawn_timer = stats.respawn_time
	color_rect.modulate = Color.DIM_GRAY
	_reset_combat_state()
	is_flinched = false
	is_staggered = false
	stun_timer = 0.0

func respawn():
	is_dead = false
	current_health = stats.max_health
	velocity = Vector2.ZERO
	global_position = spawn_position
	if status_effects:
		status_effects.clear_all()
	update_health_display()

	if behavior_mode == BehaviorMode.BLOCK:
		enter_block()
	else:
		color_rect.modulate = Color.WHITE
		ai_state = AIState.PATROL

# ---- Debug Drawing ----

func _draw():
	if not attack_hitbox:
		return

	draw_circle(Vector2(0, -40), 100, Color(0, 1, 1, 0.1))

	var hitbox_pos = attack_hitbox.position
	var hitbox_rect = Rect2(hitbox_pos.x - 35, hitbox_pos.y - 25, 70, 50)

	var hitbox_color = Color.GREEN if is_attacking else Color.RED
	hitbox_color.a = 0.3
	draw_rect(hitbox_rect, hitbox_color, false, 2.0)

	var arrow_end = Vector2(30 * facing_direction, -40)
	draw_line(Vector2(0, -40), arrow_end, Color.YELLOW, 3.0)

func _process(delta):
	if is_dead and health_label:
		health_label.text = "DEAD (%.1fs)" % respawn_timer

	if attack_collision:
		var color_to_use = Color.GREEN if not attack_collision.disabled else Color.RED
		if attack_hitbox.has_node("ColorRect"):
			var rect = attack_hitbox.get_node("ColorRect")
			rect.color = color_to_use
			rect.color.a = 0.3
