extends CharacterBody2D

## AI Bot Opponent — mirrors player mechanics with strategy-driven AI decision-making.
## Uses the same CharacterStats, MovementData, SpellData, and AttunementManager as the player.
## Replaces Input.* calls with a hierarchical state machine:
##   Strategy (AIStrategy resource) → Behavior (approach/engage/retreat/recover) → Actions

# ---- Signals (compatible with player systems) ----
signal action_started(action_id: String, ctx: Dictionary)
signal action_ended(action_id: String, ctx: Dictionary)
signal mana_spent(amount: float, reason: String, ctx: Dictionary)
signal dealt_damage(amount: float, target: Node, ctx: Dictionary)
signal took_damage(amount: float, source: Node, ctx: Dictionary)

# ---- Exported resources ----
@export var stats: CharacterStats
@export var movement_data: MovementData
@export var strategy: AIStrategy
@export var starting_attunement: Attunement
@export var spell_slots: Array[SpellData] = []

# ---- System managers ----
var attunements: AttunementManager
var status_effects: StatusEffectManager

# ---- Team ----
var team_id: int = 1

# ---- Node references ----
@onready var color_rect: ColorRect = $ColorRect
@onready var wall_check_left: RayCast2D = $WallCheckLeft
@onready var wall_check_right: RayCast2D = $WallCheckRight
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_collision: CollisionShape2D = $MeleeHitbox/CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var mana_bar: ProgressBar = $ManaBar
@onready var mana_label: Label = $ManaLabel
@onready var strategy_label: Label = $StrategyLabel

var debug_hud: Control = null

# ---- Core state ----
var current_health: float
var current_mana: float
var is_dead: bool = false
var respawn_timer: float = 0.0
var spawn_position: Vector2
const RESPAWN_TIME: float = 3.0

# ---- Movement state ----
var facing_direction: int = 1
var is_sprinting: bool = false
var is_crouching: bool = false
var can_double_jump: bool = true
var dash_available: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var air_speed_cap: float = 0.0
var is_on_wall_left: bool = false
var is_on_wall_right: bool = false
var is_wall_sliding: bool = false
var is_wall_clinging: bool = false
var wall_jump_lock_timer: float = 0.0

# ---- Coalescence ----
var is_coalescing: bool = false
var coalescence_startup_timer: float = 0.0
var coalescence_recovery_timer: float = 0.0
var coalescence_spell_lockout: float = 0.0

# ---- Interrupt state ----
var is_flinched: bool = false
var is_staggered: bool = false
var stun_timer: float = 0.0
const FLINCH_DURATION: float = 0.3
const STAGGER_DURATION: float = 0.3

# ---- Block state ----
var is_blocking: bool = false
var block_broken: bool = false
var block_broken_timer: float = 0.0
const BLOCK_BROKEN_DURATION: float = 2.5

# ---- Attack state ----
var is_attacking: bool = false
var attack_timer: float = 0.0
var is_heavy_attack: bool = false
var combo_count: int = 0
var hit_bodies_this_attack: Array = []
var combo_window_timer: float = 0.0
var can_combo: bool = false
var landed_flinch_this_attack: bool = false
var melee_cooldown_timer: float = 0.0
const MELEE_COOLDOWN_DURATION: float = 0.4

# ---- Spell state ----
var spell_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var spell_cast_delay: float = 0.0  # Brief delay before spell fires (simulates aim time)

# ---- Ranged state ----
var projectile_scene: PackedScene = preload("res://scenes/combat/projectile.tscn")
var projectile_spawn_offset: Vector2 = Vector2(0, -24)

# ---- Physics ----
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# ---- AI Behavior State Machine ----
enum AIBehavior { IDLE, APPROACH, ENGAGE_MELEE, ENGAGE_SPELL, RETREAT, RECOVER, BLOCK_STANCE }
var current_behavior: AIBehavior = AIBehavior.IDLE
var target: Node = null
var decision_timer: float = 0.0
var action_cooldown: float = 0.0
var coalesce_duration_target: float = 0.0  # How long to coalesce before stopping

# ---- Visual ----
var hit_flash_timer: float = 0.0
var original_color: Color = Color(0.85, 0.25, 0.25)  # Red tint for enemy

# ===========================================================================
#  INITIALIZATION
# ===========================================================================

func _ready():
	add_to_group("enemy")
	add_to_group("ai_opponent")

	if stats:
		current_health = stats.max_health
		current_mana = stats.max_mana
	else:
		push_error("No CharacterStats assigned to AI Opponent!")

	if spell_slots.is_empty():
		spell_slots = [
			preload("res://resources/spells/ice_spike_burst.tres"),
			preload("res://resources/spells/aegis_barrier.tres"),
			preload("res://resources/spells/haste.tres"),
			preload("res://resources/spells/sacred_flame.tres"),
		]

	# Status effects
	status_effects = StatusEffectManager.new()
	add_child(status_effects)
	status_effects.initialize(self)

	# Attunements
	attunements = AttunementManager.new()
	add_child(attunements)
	attunements.initialize(self)
	if starting_attunement:
		attunements.set_slot_attunement(0, starting_attunement)

	# Hitbox
	if melee_hitbox:
		melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)

	# Detection area
	if detection_area:
		detection_area.body_entered.connect(_on_target_detected)
		detection_area.body_exited.connect(_on_target_lost)

	original_color = color_rect.color if color_rect else Color(0.85, 0.25, 0.25)
	spawn_position = global_position

	# Find HUD
	await get_tree().process_frame
	debug_hud = get_tree().get_first_node_in_group("debug_hud")

	_update_bars()
	_update_strategy_label()

# ===========================================================================
#  MAIN LOOP
# ===========================================================================

func _physics_process(delta):
	if is_dead:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_respawn()
		return

	# ---- Timers ----
	_tick_timers(delta)

	# ---- Wall detection ----
	is_on_wall_left = wall_check_left.is_colliding()
	is_on_wall_right = wall_check_right.is_colliding()

	# ---- Gravity ----
	if not is_on_floor() and not is_dashing and not is_coalescing:
		velocity.y += gravity * delta

	# ---- Landing reset ----
	if is_on_floor():
		can_double_jump = true
		wall_jump_lock_timer = 0.0

	# ---- Wall mechanics ----
	_handle_wall_mechanics(delta)

	# ---- Stunned: no actions ----
	var is_stunned := is_flinched or is_staggered
	var is_cc := status_effects.is_grabbed() if status_effects else false
	if is_stunned or is_cc:
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
		if is_cc:
			velocity = Vector2.ZERO
		move_and_slide()
		_update_bars()
		_update_visual()
		queue_redraw()
		return

	# ---- AI Decision Layer ----
	decision_timer -= delta
	if decision_timer <= 0 and target != null and is_instance_valid(target):
		_evaluate_behavior()
		decision_timer = strategy.decision_interval if strategy else 0.3

	# ---- Execute current behavior ----
	_execute_behavior(delta)

	# ---- Mana regen ----
	_regenerate_mana(delta)

	# ---- Physics ----
	move_and_slide()

	# ---- Update visuals ----
	_update_bars()
	_update_visual()
	queue_redraw()

func _tick_timers(delta):
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			set_collision_mask_value(4, true)
			emit_signal("action_ended", "dash", {ContextKeys.IS_AIRBORNE: not is_on_floor()})

	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0:
			dash_available = true

	if wall_jump_lock_timer > 0:
		wall_jump_lock_timer -= delta

	if coalescence_recovery_timer > 0:
		coalescence_recovery_timer -= delta

	if coalescence_spell_lockout > 0:
		coalescence_spell_lockout -= delta

	if melee_cooldown_timer > 0:
		melee_cooldown_timer -= delta

	if block_broken_timer > 0:
		block_broken_timer -= delta
		if block_broken_timer <= 0:
			block_broken = false

	if stun_timer > 0:
		stun_timer -= delta
		if stun_timer <= 0:
			is_flinched = false
			is_staggered = false

	if action_cooldown > 0:
		action_cooldown -= delta

	if spell_cast_delay > 0:
		spell_cast_delay -= delta

	if hit_flash_timer > 0:
		hit_flash_timer -= delta

	# Attack timer
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0:
			_end_attack()

	# Combo window
	if combo_window_timer > 0:
		combo_window_timer -= delta
		if combo_window_timer <= 0:
			can_combo = false
			combo_count = 0

	# Spell cooldowns
	for i in 4:
		if spell_cooldowns[i] > 0:
			spell_cooldowns[i] -= delta

	# Coalescence tick
	if is_coalescing:
		if coalescence_startup_timer > 0:
			coalescence_startup_timer -= delta
		velocity = Vector2.ZERO
		coalesce_duration_target -= delta
		if coalesce_duration_target <= 0:
			_stop_coalescing()

# ===========================================================================
#  AI DECISION LAYER — Hierarchical State Machine
# ===========================================================================

func _evaluate_behavior():
	if target == null or not is_instance_valid(target):
		current_behavior = AIBehavior.IDLE
		return

	var dist: float = global_position.distance_to(target.global_position)
	var health_pct: float = current_health / maxf(1.0, stats.max_health)
	var mana_pct: float = current_mana / maxf(1.0, stats.max_mana)
	var strat := _get_strategy()

	# --- Priority 1: Recovery when low resources ---
	if mana_pct < strat.coalesce_mana_threshold and health_pct > strat.retreat_health_threshold:
		if not is_coalescing and coalescence_recovery_timer <= 0 and dist > 120.0:
			current_behavior = AIBehavior.RECOVER
			return

	# --- Priority 2: Retreat when low health ---
	if health_pct < strat.retreat_health_threshold:
		current_behavior = AIBehavior.RETREAT
		return

	# --- Priority 3: Block if target is attacking and we're defensive ---
	if _target_is_attacking() and randf() < strat.block_chance and is_on_floor():
		if not block_broken and not is_attacking:
			current_behavior = AIBehavior.BLOCK_STANCE
			return

	# --- Priority 4: Engage ---
	if dist < strat.preferred_melee_range and mana_pct > strat.spell_mana_reserve:
		# Close range — decide melee vs spell based on strategy
		if randf() < strat.spell_preference and _has_ready_spell():
			current_behavior = AIBehavior.ENGAGE_SPELL
		else:
			current_behavior = AIBehavior.ENGAGE_MELEE
		return

	if dist < strat.preferred_spell_range and _has_ready_spell() and mana_pct > strat.spell_mana_reserve:
		current_behavior = AIBehavior.ENGAGE_SPELL
		return

	# --- Priority 5: Approach ---
	if dist > strat.preferred_melee_range:
		# Aggressive bots prefer closing in, defensive prefer spell range
		if strat.aggression > 0.5 or not _has_ready_spell():
			current_behavior = AIBehavior.APPROACH
		elif dist > strat.preferred_spell_range:
			current_behavior = AIBehavior.APPROACH
		else:
			current_behavior = AIBehavior.ENGAGE_SPELL
		return

	current_behavior = AIBehavior.APPROACH

func _execute_behavior(delta):
	if target == null or not is_instance_valid(target):
		# No target — slow patrol
		_do_patrol(delta)
		return

	# Always face target (unless wall-jump locked)
	if wall_jump_lock_timer <= 0:
		_face_target()

	match current_behavior:
		AIBehavior.IDLE:
			_do_patrol(delta)
		AIBehavior.APPROACH:
			_do_approach(delta)
		AIBehavior.ENGAGE_MELEE:
			_do_engage_melee(delta)
		AIBehavior.ENGAGE_SPELL:
			_do_engage_spell(delta)
		AIBehavior.RETREAT:
			_do_retreat(delta)
		AIBehavior.RECOVER:
			_do_recover(delta)
		AIBehavior.BLOCK_STANCE:
			_do_block(delta)

# ===========================================================================
#  BEHAVIOR IMPLEMENTATIONS
# ===========================================================================

func _do_patrol(delta):
	is_blocking = false
	if is_coalescing:
		return

	# Simple patrol: walk back and forth, turn at walls
	if wall_check_right.is_colliding():
		facing_direction = -1
	elif wall_check_left.is_colliding():
		facing_direction = 1

	var speed := stats.walk_speed * 0.5
	velocity.x = move_toward(velocity.x, facing_direction * speed, 2000.0 * delta)
	_update_melee_hitbox_position()

func _do_approach(delta):
	is_blocking = false
	if is_coalescing:
		_stop_coalescing()
	if is_dashing or is_attacking:
		return

	var dir: float = signf(target.global_position.x - global_position.x)
	var dist: float = absf(target.global_position.x - global_position.x)
	var strat := _get_strategy()

	# Sprint if far away
	var target_speed: float
	if dist > strat.preferred_spell_range:
		is_sprinting = true
		target_speed = stats.sprint_speed
	else:
		is_sprinting = false
		target_speed = stats.walk_speed

	if attunements:
		target_speed *= attunements.get_move_speed_mult()
	if status_effects:
		target_speed *= status_effects.get_speed_mult()

	# Move toward target
	if is_on_floor():
		velocity.x = move_toward(velocity.x, dir * target_speed, movement_data.ground_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, dir * target_speed, movement_data.air_acceleration * delta)

	# Jump if target is significantly above us
	if target.global_position.y < global_position.y - 80 and is_on_floor():
		_do_jump()

	# Dash toward target if far and dash available
	if dist > strat.chase_max_distance * 0.8 and dash_available and strat.aggression > 0.5:
		_do_dash(Vector2(dir, 0))

	_update_melee_hitbox_position()

func _do_engage_melee(delta):
	is_blocking = false
	if is_coalescing:
		_stop_coalescing()
	if is_dashing:
		return

	var dist: float = absf(target.global_position.x - global_position.x)
	var dir: float = signf(target.global_position.x - global_position.x)
	var strat := _get_strategy()

	# Close in to melee range
	if dist > strat.preferred_melee_range and not is_attacking:
		var target_speed := stats.walk_speed
		if attunements:
			target_speed *= attunements.get_move_speed_mult()
		velocity.x = move_toward(velocity.x, dir * target_speed, movement_data.ground_acceleration * delta)
	elif not is_attacking:
		velocity.x = move_toward(velocity.x, 0.0, movement_data.ground_deceleration * delta)

	# Attack when in range and cooldown allows
	if dist < strat.preferred_melee_range * 1.2 and action_cooldown <= 0 and not is_attacking:
		if melee_cooldown_timer <= 0:
			# Decide attack type based on strategy
			if combo_count == 1 and can_combo:
				# In combo — follow up with light or heavy
				if randf() < strat.aggression * 0.7:
					_perform_heavy_attack()
				else:
					_perform_light_attack()
			elif _target_is_blocking() and strat.aggression > 0.4:
				# Target blocking — use heavy to break shield
				_perform_heavy_attack()
			else:
				_perform_light_attack()
			action_cooldown = 0.2 + randf() * 0.3

	# Dodge if target attacks while we're close
	if _target_is_attacking() and dist < 60 and dash_available:
		if randf() < strat.dodge_chance:
			_do_dash(Vector2(-dir, 0))

	_update_melee_hitbox_position()

func _do_engage_spell(delta):
	is_blocking = false
	if is_coalescing:
		_stop_coalescing()
	if is_dashing or is_attacking:
		return

	var dist: float = absf(target.global_position.x - global_position.x)
	var dir: float = signf(target.global_position.x - global_position.x)
	var strat := _get_strategy()

	# Maintain spell range — back off if too close, close in if too far
	if dist < strat.too_close_distance and is_on_floor():
		velocity.x = move_toward(velocity.x, -dir * stats.walk_speed, movement_data.ground_acceleration * delta)
	elif dist > strat.preferred_spell_range * 1.3:
		velocity.x = move_toward(velocity.x, dir * stats.walk_speed, movement_data.ground_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, movement_data.ground_deceleration * delta)

	# Cast spells
	if action_cooldown <= 0 and coalescence_spell_lockout <= 0:
		var spell_idx := _pick_best_spell()
		if spell_idx >= 0:
			_cast_spell(spell_idx)
			action_cooldown = 0.5 + randf() * 0.5

	_update_melee_hitbox_position()

func _do_retreat(delta):
	if is_coalescing:
		_stop_coalescing()
	if is_dashing:
		return

	var dir: float = signf(target.global_position.x - global_position.x)
	var dist: float = absf(target.global_position.x - global_position.x)
	var strat := _get_strategy()

	is_blocking = false

	# Move away from target
	var target_speed := stats.sprint_speed
	if attunements:
		target_speed *= attunements.get_move_speed_mult()
	velocity.x = move_toward(velocity.x, -dir * target_speed, movement_data.ground_acceleration * delta)

	# Dash away if target is close
	if dist < 80.0 and dash_available:
		_do_dash(Vector2(-dir, 0))

	# Jump to escape
	if is_on_floor() and dist < 100:
		_do_jump()

	# Wall jump if sliding
	if (is_wall_sliding or is_wall_clinging) and movement_data.can_wall_jump:
		_do_wall_jump()

	# If far enough away and low mana, transition to recover
	if dist > 200.0 and (current_mana / max(1.0, stats.max_mana)) < strat.coalesce_mana_threshold:
		current_behavior = AIBehavior.RECOVER

	_update_melee_hitbox_position()

func _do_recover(delta):
	is_blocking = false
	if is_dashing:
		return

	var dist: float = absf(target.global_position.x - global_position.x) if target and is_instance_valid(target) else 999.0

	# Start coalescing if safe
	if not is_coalescing and coalescence_recovery_timer <= 0 and dist > 120.0:
		_start_coalescing()

	# If target gets close, stop and retreat
	if dist < 100.0:
		_stop_coalescing()
		current_behavior = AIBehavior.RETREAT
		return

	# Move away while recovering
	if target and is_instance_valid(target):
		var dir: float = signf(target.global_position.x - global_position.x)
		if not is_coalescing:
			velocity.x = move_toward(velocity.x, -dir * stats.walk_speed * 0.5, movement_data.ground_acceleration * delta)

	# Stop recovering when mana is above threshold
	if (current_mana / max(1.0, stats.max_mana)) > 0.7:
		_stop_coalescing()
		current_behavior = AIBehavior.APPROACH

	_update_melee_hitbox_position()

func _do_block(delta):
	if is_coalescing:
		_stop_coalescing()
	if is_dashing or is_attacking:
		return

	if block_broken:
		is_blocking = false
		current_behavior = AIBehavior.RETREAT
		return

	# Block costs mana
	var spent := _use_mana(stats.block_mana_drain * delta, "block")
	if spent > 0.0:
		is_blocking = true
		velocity.x = move_toward(velocity.x, 0.0, movement_data.ground_deceleration * delta)
	else:
		is_blocking = false
		current_behavior = AIBehavior.RETREAT

	# Stop blocking after target stops attacking
	if not _target_is_attacking():
		is_blocking = false
		action_cooldown = 0.1

	_update_melee_hitbox_position()

# ===========================================================================
#  MOVEMENT ACTIONS
# ===========================================================================

func _handle_wall_mechanics(delta):
	var on_wall := is_on_wall_left or is_on_wall_right

	if is_on_floor() or not on_wall:
		is_wall_sliding = false
		is_wall_clinging = false
		return

	if not is_on_floor() and on_wall and velocity.y > 0:
		# Wall slide: slow fall when touching wall
		is_wall_sliding = true
		is_wall_clinging = false
		velocity.y = movement_data.wall_slide_speed if movement_data else 100.0
	else:
		is_wall_sliding = false
		is_wall_clinging = false

func _do_jump():
	if is_on_floor():
		velocity.y = stats.jump_velocity
		air_speed_cap = abs(velocity.x) if abs(velocity.x) > 0 else stats.walk_speed
	elif can_double_jump and movement_data.can_double_jump:
		var spent := _use_mana(stats.double_jump_cost, "double_jump")
		if spent > 0.0:
			velocity.y = stats.jump_velocity
			can_double_jump = false

func _do_wall_jump():
	if not (is_wall_sliding or is_wall_clinging):
		return
	if not movement_data.can_wall_jump:
		return

	var spent := _use_mana(stats.wall_jump_cost, "wall_jump")
	if spent > 0.0:
		var jump_dir := 1 if is_on_wall_left else -1
		velocity.y = stats.jump_velocity
		velocity.x = jump_dir * movement_data.wall_jump_horizontal_boost
		wall_jump_lock_timer = 0.2
		can_double_jump = true
		air_speed_cap = movement_data.wall_jump_horizontal_boost
		is_wall_sliding = false
		is_wall_clinging = false

func _do_dash(direction: Vector2):
	if not dash_available or is_dashing:
		return

	var spent := _use_mana(stats.dash_cost, "dash")
	if spent <= 0.0:
		return

	dash_direction = direction.normalized()
	is_dashing = true
	dash_timer = movement_data.dash_duration
	dash_available = false
	dash_cooldown_timer = movement_data.dash_cooldown

	# Disable collision with player during dash
	set_collision_mask_value(4, false)

	velocity = dash_direction * movement_data.dash_distance / movement_data.dash_duration

	if not is_on_floor():
		air_speed_cap = maxf(air_speed_cap, stats.walk_speed)

	emit_signal("action_started", "dash", {ContextKeys.DASH_DIRECTION: dash_direction, ContextKeys.DASH_AIRBORNE: not is_on_floor(), ContextKeys.MANA_SPENT: spent})
	if attunements:
		attunements.notify_action_started("dash", {ContextKeys.DASH_DIRECTION: dash_direction})

# ===========================================================================
#  MELEE COMBAT
# ===========================================================================

func _perform_light_attack():
	if is_attacking or is_blocking or is_coalescing or is_dashing:
		return
	if melee_cooldown_timer > 0:
		return

	is_attacking = true
	is_heavy_attack = false
	attack_timer = stats.light_attack_duration
	hit_bodies_this_attack.clear()
	landed_flinch_this_attack = false
	combo_count += 1

	melee_collision.disabled = false
	call_deferred("_apply_melee_overlap_hits")

	_log_action("[color=red]AI Light Attack #%d[/color]" % combo_count)

func _perform_heavy_attack():
	if is_attacking or is_blocking or is_coalescing or is_dashing:
		return
	if melee_cooldown_timer > 0:
		return

	is_attacking = true
	is_heavy_attack = true
	attack_timer = stats.heavy_attack_duration
	hit_bodies_this_attack.clear()

	melee_collision.disabled = false
	call_deferred("_apply_melee_overlap_hits")

	_log_action("[color=orange]AI Heavy Attack![/color]")

func _end_attack():
	is_attacking = false
	melee_collision.disabled = true

	if combo_count == 1 and not is_heavy_attack and landed_flinch_this_attack:
		can_combo = true
		combo_window_timer = 0.5
	elif combo_count >= 2 or is_heavy_attack:
		combo_count = 0
		can_combo = false
		combo_window_timer = 0.0
		melee_cooldown_timer = MELEE_COOLDOWN_DURATION

	is_heavy_attack = false

func _apply_melee_overlap_hits():
	if not is_attacking or melee_hitbox == null:
		return
	melee_hitbox.monitoring = true
	for b in melee_hitbox.get_overlapping_bodies():
		_on_melee_hitbox_body_entered(b)

func _on_melee_hitbox_body_entered(hit_body):
	if not is_attacking:
		return
	if hit_body == self:
		return
	if hit_body in hit_bodies_this_attack:
		return
	if not hit_body.has_method("take_damage"):
		return

	hit_bodies_this_attack.append(hit_body)

	var base_damage: float = float(stats.heavy_attack_damage if is_heavy_attack else stats.light_attack_damage)
	var dmg_key := ModKeys.HEAVY_DAMAGE if is_heavy_attack else ModKeys.LIGHT_DAMAGE

	var ctx := {
		ContextKeys.SOURCE: self,
		ContextKeys.TARGET: hit_body,
		ContextKeys.ATTACK_ID: "heavy_attack" if is_heavy_attack else "light_attack",
		ContextKeys.DAMAGE_TYPE: "melee",
		ContextKeys.BASE_DAMAGE: base_damage,
		ContextKeys.IS_AIRBORNE: not is_on_floor(),
		ContextKeys.FACING: facing_direction,
		ContextKeys.COMBO_COUNT: combo_count,
	}

	var final_damage: float = base_damage
	if attunements:
		final_damage = float(attunements.modify_damage(dmg_key, base_damage, ctx))

	var knockback := Vector2.ZERO
	if is_heavy_attack:
		knockback = Vector2(facing_direction * stats.knockback_force, -400)

	var interrupt_type := "stagger" if is_heavy_attack else "flinch"

	# Clash detection
	if "is_attacking" in hit_body and hit_body.is_attacking:
		var target_is_heavy := false
		if "is_heavy_attack" in hit_body:
			target_is_heavy = hit_body.is_heavy_attack
		if not is_heavy_attack and not target_is_heavy:
			_end_attack()
			if hit_body.has_method("end_attack"):
				hit_body.end_attack()
			elif hit_body.has_method("end_dummy_attack"):
				hit_body.end_dummy_attack()
			return
		elif is_heavy_attack and target_is_heavy:
			var clash_dir := facing_direction
			velocity = Vector2(-clash_dir * stats.knockback_force * 0.5, -200)
			if hit_body is CharacterBody2D:
				hit_body.velocity = Vector2(clash_dir * stats.knockback_force * 0.5, -200)
			_end_attack()
			if hit_body.has_method("end_attack"):
				hit_body.end_attack()
			elif hit_body.has_method("end_dummy_attack"):
				hit_body.end_dummy_attack()
			return

	var target_is_blocking := false
	if "is_blocking" in hit_body:
		target_is_blocking = hit_body.is_blocking

	ctx[ContextKeys.DAMAGE] = final_damage
	ctx[ContextKeys.INTERRUPT] = interrupt_type
	hit_body.take_damage(final_damage, knockback, interrupt_type, ctx)

	# Mana gain
	var base_gain: float
	var gain_key: String

	if target_is_blocking and interrupt_type == "stagger":
		base_gain = stats.heavy_shield_break_bonus
		gain_key = ModKeys.HEAVY_MELEE_HIT_MANA_GAIN
		_log_action("[color=yellow]AI SHIELD BREAK![/color]")
	elif target_is_blocking and interrupt_type == "flinch":
		base_gain = stats.melee_blocked_mana_gain
		gain_key = ModKeys.MELEE_HIT_MANA_GAIN
	else:
		base_gain = float(stats.heavy_melee_hit_mana_gain if is_heavy_attack else stats.melee_hit_mana_gain)
		gain_key = ModKeys.HEAVY_MELEE_HIT_MANA_GAIN if is_heavy_attack else ModKeys.MELEE_HIT_MANA_GAIN
		if interrupt_type == "flinch":
			landed_flinch_this_attack = true

	var final_gain: float = base_gain
	if attunements:
		final_gain = float(attunements.modify_mana_gain(gain_key, base_gain, ctx))

	emit_signal("dealt_damage", final_damage, hit_body, ctx)
	if attunements:
		attunements.notify_dealt_damage(final_damage, hit_body, ctx)

	current_mana = min(current_mana + final_gain, stats.max_mana)

# ===========================================================================
#  SPELL CASTING
# ===========================================================================

func _pick_best_spell() -> int:
	var strat := _get_strategy()
	var mana_pct: float = current_mana / maxf(1.0, stats.max_mana)

	for idx in strat.spell_priority:
		if idx < 0 or idx >= spell_slots.size() or spell_slots[idx] == null:
			continue
		var spell: SpellData = spell_slots[idx]
		if spell_cooldowns[idx] > 0:
			continue

		# Check mana (keep reserve)
		var cost := spell.mana_cost
		if attunements:
			cost *= attunements.get_cost_mult("spell_cast")
		if current_mana < cost or (current_mana - cost) / stats.max_mana < strat.spell_mana_reserve:
			continue

		# Skip toggled/channeled for simplicity in AI v1
		if spell.cast_type == "toggled" or spell.is_channeled:
			continue

		return idx

	return -1

func _cast_spell(index: int):
	if index < 0 or index >= spell_slots.size() or spell_slots[index] == null:
		return
	if coalescence_spell_lockout > 0:
		return

	var spell: SpellData = spell_slots[index]

	# Pay mana
	var spent := _use_mana(spell.mana_cost, "spell_cast")
	if spent <= 0.0:
		return

	spell_cooldowns[index] = spell.cooldown

	match spell.cast_type:
		"free_aim":
			_fire_spell_free_aim(spell)
		"targeted":
			_fire_spell_targeted(spell)
		"placement":
			_place_spell(spell)

	_log_action("[color=violet]AI Cast: %s[/color]" % spell.spell_name)

func _fire_spell_free_aim(spell: SpellData):
	if target == null or not is_instance_valid(target):
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()
	# Add slight inaccuracy based on difficulty
	var inaccuracy: float = (1.0 - _get_strategy().aggression) * 0.15
	dir = dir.rotated(randf_range(-inaccuracy, inaccuracy))

	var spell_ctx := {
		ContextKeys.SOURCE: self,
		ContextKeys.ATTACK_ID: spell.spell_name,
		ContextKeys.DAMAGE_TYPE: "spell",
		ContextKeys.CAST_DIRECTION: dir,
		ContextKeys.TEAM_ID: team_id,
		ContextKeys.SPELL_DATA: spell,
	}

	var final_speed: float = spell.projectile_speed
	var final_damage: float = spell.damage
	if attunements:
		final_speed = float(attunements.modify_value(ModKeys.SPELL_PROJECTILE_SPEED, final_speed, spell_ctx))
		final_damage = float(attunements.modify_value(ModKeys.SPELL_DAMAGE, final_damage, spell_ctx))

	if spell.spell_scene:
		spell_ctx[ContextKeys.PROJECTILE_SPEED] = final_speed
		spell_ctx[ContextKeys.DAMAGE] = final_damage
		_spawn_spell_scene(spell, _get_projectile_spawn_base() + dir * 40, dir, null, spell_ctx)
		return

	var proj = projectile_scene.instantiate()
	proj.global_position = _get_projectile_spawn_base() + dir * 40
	proj.direction = dir
	proj.speed = final_speed
	proj.damage = final_damage
	proj.damage_type = "spell"
	proj.interrupt_type = spell.interrupt_type
	proj.source = self
	proj.team_id = team_id
	proj.spell_data = spell
	get_tree().current_scene.add_child(proj)
	if proj.has_node("ColorRect"):
		proj.get_node("ColorRect").color = spell.projectile_color

func _fire_spell_targeted(spell: SpellData):
	var spell_target := _find_spell_target(spell)
	if spell_target == null:
		return

	var dir: Vector2 = (spell_target.global_position - global_position).normalized()
	var spell_ctx := {
		ContextKeys.SOURCE: self,
		ContextKeys.TARGET: spell_target,
		ContextKeys.ATTACK_ID: spell.spell_name,
		ContextKeys.DAMAGE_TYPE: "spell",
		ContextKeys.TEAM_ID: team_id,
		ContextKeys.SPELL_DATA: spell,
		ContextKeys.CAST_DIRECTION: dir,
		ContextKeys.TARGETED_DELIVERY: spell.targeted_delivery,
	}

	var final_damage: float = spell.damage
	var final_speed: float = spell.projectile_speed
	var final_homing: float = spell.targeted_homing_turn_speed
	if attunements:
		final_damage = float(attunements.modify_value(ModKeys.SPELL_DAMAGE, final_damage, spell_ctx))
		final_speed = float(attunements.modify_value(ModKeys.SPELL_PROJECTILE_SPEED, final_speed, spell_ctx))
		final_homing = float(attunements.modify_value(ModKeys.SPELL_HOMING_TURN_SPEED, final_homing, spell_ctx))
	spell_ctx[ContextKeys.DAMAGE] = final_damage
	spell_ctx[ContextKeys.PROJECTILE_SPEED] = final_speed
	spell_ctx[ContextKeys.HOMING_TURN_SPEED] = final_homing

	# Apply-at-target delivery
	if spell.targeted_delivery == "apply_at_target":
		if spell.spell_scene:
			_spawn_spell_scene(spell, spell_target.global_position, dir, spell_target, spell_ctx)
		else:
			var target_is_ally := is_ally(spell_target)
			if target_is_ally and spell.heal_amount > 0.0 and spell_target.has_method("apply_healing"):
				spell_target.apply_healing(spell.heal_amount, spell_ctx)
			elif not target_is_ally and spell_target.has_method("take_damage"):
				spell_target.take_damage(final_damage, Vector2.ZERO, spell.interrupt_type, spell_ctx)
		return

	# Projectile delivery
	if spell.spell_scene:
		_spawn_spell_scene(spell, global_position + dir * 40, dir, spell_target, spell_ctx)
		return

	var proj = projectile_scene.instantiate()
	proj.global_position = _get_projectile_spawn_base() + dir * 40
	proj.direction = dir
	proj.speed = final_speed
	proj.damage = final_damage
	proj.damage_type = "spell"
	proj.interrupt_type = spell.interrupt_type
	proj.source = self
	proj.team_id = team_id
	proj.spell_data = spell
	if proj is Projectile:
		proj.homing_target = spell_target if spell_target is Node2D else null
		proj.homing_turn_speed = final_homing
	get_tree().current_scene.add_child(proj)
	if proj.has_node("ColorRect"):
		proj.get_node("ColorRect").color = spell.projectile_color

func _place_spell(spell: SpellData):
	if target == null or not is_instance_valid(target):
		return
	if spell.spell_scene == null:
		return

	var strat := _get_strategy()
	var dir_to_target: float = signf(target.global_position.x - global_position.x)

	# Strategy-driven placement position
	var place_pos: Vector2
	if strat.placement_defensiveness > 0.6:
		# Defensive: place between self and target
		place_pos = global_position + Vector2(dir_to_target * 60, 0)
	elif strat.placement_defensiveness < 0.4:
		# Aggressive: place to cut off target's retreat
		place_pos = target.global_position + Vector2(dir_to_target * 40, 0)
	else:
		# Neutral: place at midpoint
		place_pos = (global_position + target.global_position) * 0.5

	var place_rotation := 0.0  # Upright by default

	var entity = spell.spell_scene.instantiate()
	entity.global_position = place_pos
	entity.rotation = place_rotation
	if "caster" in entity:
		entity.caster = self
	if "team_id" in entity:
		entity.team_id = team_id
	if "spell_data" in entity:
		entity.spell_data = spell
	if entity.has_method("initialize"):
		entity.initialize({
			ContextKeys.SOURCE: self,
			ContextKeys.CAST_POSITION: place_pos,
			ContextKeys.CAST_ROTATION: place_rotation,
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell,
		})
	get_tree().current_scene.add_child(entity)

func _find_spell_target(spell: SpellData) -> Node:
	# For offensive spells, target the tracked enemy
	if spell.can_target_enemies and target != null and is_instance_valid(target):
		if spell.requires_line_of_sight and not _has_line_of_sight(global_position, target.global_position):
			return null
		return target
	# For ally spells, target self (in 1v1 context)
	if spell.can_target_allies:
		return self
	return null

func _spawn_spell_scene(spell: SpellData, pos: Vector2, dir: Vector2 = Vector2.RIGHT, spell_target: Node = null, extra_ctx: Dictionary = {}):
	var entity = spell.spell_scene.instantiate()
	entity.global_position = pos
	if "caster" in entity:
		entity.caster = self
	if "team_id" in entity:
		entity.team_id = team_id
	if "spell_data" in entity:
		entity.spell_data = spell
	if "direction" in entity:
		entity.direction = dir
	if "source" in entity:
		entity.source = self
	if entity.has_method("initialize"):
		var ctx := {
			ContextKeys.SOURCE: self,
			ContextKeys.CAST_DIRECTION: dir,
			ContextKeys.CAST_POSITION: pos,
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell,
		}
		if spell_target:
			ctx[ContextKeys.CAST_TARGET] = spell_target
		for k in extra_ctx.keys():
			ctx[k] = extra_ctx[k]
		entity.initialize(ctx)
	get_tree().current_scene.add_child(entity)
	if spell.targeted_delivery == "apply_at_target" and entity is SpellEntity and spell_target is Node2D:
		(entity as SpellEntity).attach_to_target(spell_target as Node2D)

# ===========================================================================
#  COALESCENCE
# ===========================================================================

func _start_coalescing():
	if is_coalescing or coalescence_recovery_timer > 0:
		return
	is_coalescing = true
	coalescence_startup_timer = 1.0
	velocity = Vector2.ZERO
	coalesce_duration_target = 2.0 + randf() * 2.0  # Coalesce 2-4 seconds
	_log_action("[color=aqua]AI Coalescing...[/color]")

func _stop_coalescing():
	if not is_coalescing:
		return
	is_coalescing = false
	coalescence_recovery_timer = 0.5
	coalescence_spell_lockout = 3.0
	coalescence_startup_timer = 0.0

# ===========================================================================
#  MANA SYSTEM
# ===========================================================================

func _regenerate_mana(delta):
	if stats == null or current_mana >= stats.max_mana:
		return

	var regen_rate := stats.passive_mana_regen

	if is_coalescing and coalescence_startup_timer <= 0:
		regen_rate *= stats.coalescence_multiplier

	if attunements:
		regen_rate *= attunements.get_regen_mult()

	current_mana = min(current_mana + regen_rate * delta, stats.max_mana)

func _use_mana(amount: float, reason: String = "", ctx: Dictionary = {}) -> float:
	var final_amount := amount
	if attunements and reason != "":
		final_amount = amount * attunements.get_cost_mult(reason)

	if current_mana >= final_amount:
		current_mana -= final_amount
		emit_signal("mana_spent", final_amount, reason, ctx)
		if attunements:
			attunements.notify_mana_spent(final_amount, reason, ctx)
		return final_amount

	return 0.0

# ===========================================================================
#  DAMAGE & HEALTH
# ===========================================================================

func take_damage(damage: float, knockback_velocity: Vector2 = Vector2.ZERO, interrupt_type: String = "none", ctx: Dictionary = {}):
	if is_dead:
		return

	# Dash i-frames
	if is_dashing:
		return

	# Flinch immunity during coalescence
	var flinch_immune := is_coalescing or (is_attacking and is_heavy_attack)
	if interrupt_type == "flinch" and flinch_immune:
		current_health -= damage
		hit_flash_timer = 0.1
		emit_signal("took_damage", damage, ctx.get(ContextKeys.SOURCE, null), ctx)
		if attunements:
			attunements.notify_took_damage(damage, ctx.get(ContextKeys.SOURCE, null), ctx)
		if current_health <= 0:
			_die()
		return

	# Block absorption
	if is_blocking and interrupt_type == "flinch":
		ctx[ContextKeys.IS_BLOCKED] = true
		emit_signal("took_damage", 0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		return

	if is_blocking and interrupt_type == "stagger":
		is_blocking = false
		block_broken = true
		block_broken_timer = BLOCK_BROKEN_DURATION
		ctx[ContextKeys.IS_SHIELD_BREAK] = true
		_log_action("[color=red]AI SHIELD BREAK![/color]")
		emit_signal("took_damage", 0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		return

	# Apply damage
	current_health -= damage
	hit_flash_timer = 0.1

	# Stagger interrupts coalescence
	if is_coalescing and interrupt_type == "stagger":
		is_coalescing = false
		coalescence_recovery_timer = 0.5
		coalescence_spell_lockout = 3.0
		coalescence_startup_timer = 0.0

	# Knockback
	if knockback_velocity != Vector2.ZERO:
		velocity = knockback_velocity
		is_attacking = false
		is_coalescing = false
		is_dashing = false
		melee_collision.disabled = true

	# Interrupts
	match interrupt_type:
		"flinch":
			is_flinched = true
			is_staggered = false
			stun_timer = FLINCH_DURATION
			if is_attacking:
				_end_attack()
		"stagger":
			is_flinched = false
			is_staggered = true
			stun_timer = STAGGER_DURATION
			if is_attacking:
				_end_attack()
			is_blocking = false

	emit_signal("took_damage", damage, ctx.get(ContextKeys.SOURCE, null), ctx)
	if attunements:
		attunements.notify_took_damage(damage, ctx.get(ContextKeys.SOURCE, null), ctx)

	if current_health <= 0:
		_die()

func apply_healing(amount: float, _ctx: Dictionary = {}) -> void:
	if is_dead or amount <= 0.0 or stats == null:
		return
	current_health = min(current_health + amount, stats.max_health)

func is_ally(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id == team_id
	return false

func is_enemy(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id != team_id
	return other != self

func _die():
	is_dead = true
	respawn_timer = RESPAWN_TIME
	current_health = 0
	velocity = Vector2.ZERO
	_reset_all_state()
	if status_effects:
		status_effects.clear_all()
	_log_action("[color=red]AI DIED![/color]")

func _respawn():
	is_dead = false
	current_health = stats.max_health
	current_mana = stats.max_mana
	velocity = Vector2.ZERO
	global_position = spawn_position
	_reset_all_state()
	if status_effects:
		status_effects.clear_all()
	current_behavior = AIBehavior.IDLE
	_log_action("[color=lime]AI Respawned![/color]")

func _reset_all_state():
	is_attacking = false
	is_coalescing = false
	is_dashing = false
	is_blocking = false
	is_flinched = false
	is_staggered = false
	block_broken = false
	stun_timer = 0.0
	attack_timer = 0.0
	coalescence_startup_timer = 0.0
	coalescence_recovery_timer = 0.0
	coalescence_spell_lockout = 0.0
	block_broken_timer = 0.0
	melee_cooldown_timer = 0.0
	melee_collision.disabled = true
	spell_cooldowns = [0.0, 0.0, 0.0, 0.0]

# ===========================================================================
#  DETECTION
# ===========================================================================

func _on_target_detected(body):
	if body == self:
		return
	if not (body.is_in_group("player")):
		return
	target = body
	_face_target()
	_update_melee_hitbox_position()

func _on_target_lost(body):
	if body == target:
		target = null

# ===========================================================================
#  HELPERS
# ===========================================================================

func _get_strategy() -> AIStrategy:
	if strategy:
		return strategy
	# Fallback defaults if no strategy assigned
	return AIStrategy.new()

func _face_target():
	if target == null or not is_instance_valid(target):
		return
	if target.global_position.x < global_position.x:
		facing_direction = -1
	else:
		facing_direction = 1

func _update_melee_hitbox_position():
	if melee_hitbox:
		melee_hitbox.position.x = 50 * facing_direction
		melee_hitbox.position.y = -40

func _target_is_attacking() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if "is_attacking" in target:
		return target.is_attacking
	if "is_charging_heavy" in target:
		return target.is_charging_heavy
	return false

func _target_is_blocking() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if "is_blocking" in target:
		return target.is_blocking
	return false

func _has_ready_spell() -> bool:
	for i in spell_slots.size():
		if spell_slots[i] != null and spell_cooldowns[i] <= 0:
			var spell: SpellData = spell_slots[i]
			if spell.cast_type != "toggled" and not spell.is_channeled:
				if current_mana >= spell.mana_cost:
					return true
	return false

func _has_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos, 1)
	var result := space.intersect_ray(query)
	return result.is_empty()

func _get_projectile_spawn_base() -> Vector2:
	return global_position + projectile_spawn_offset

func _log_action(text: String):
	if debug_hud and debug_hud.has_method("log_action"):
		debug_hud.log_action(text)

# Compatibility: player's clash detection calls this
func end_attack() -> void:
	_end_attack()

# Compatibility alias
func end_dummy_attack() -> void:
	_end_attack()

# ===========================================================================
#  VISUAL & UI
# ===========================================================================

func _update_bars():
	if not stats:
		return

	if health_bar:
		health_bar.max_value = stats.max_health
		health_bar.value = current_health
	if health_label:
		if is_dead:
			health_label.text = "DEAD (%.1fs)" % respawn_timer
		else:
			health_label.text = "%.0f/%.0f" % [current_health, stats.max_health]

	if mana_bar:
		mana_bar.max_value = stats.max_mana
		mana_bar.value = current_mana
	if mana_label:
		mana_label.text = "%.0f/%.0f" % [current_mana, stats.max_mana]

func _update_strategy_label():
	if strategy_label and strategy:
		strategy_label.text = strategy.strategy_name

func _update_visual():
	if not color_rect:
		return
	if is_dead:
		color_rect.modulate = Color.DIM_GRAY
	elif hit_flash_timer > 0:
		color_rect.modulate = Color.WHITE
	elif is_blocking:
		color_rect.modulate = Color(0.3, 0.5, 1.0)
	elif is_flinched:
		color_rect.modulate = Color(1.0, 0.8, 0.0)
	elif is_staggered:
		color_rect.modulate = Color(1.0, 0.3, 0.0)
	elif is_coalescing:
		color_rect.modulate = Color(0.3, 1.0, 0.8)
	elif is_attacking and is_heavy_attack:
		color_rect.modulate = Color(1.0, 0.2, 0.0)
	elif is_attacking:
		color_rect.modulate = Color(1.0, 0.4, 0.4)
	elif is_dashing:
		color_rect.modulate = Color(0.5, 1.0, 0.5)
	elif block_broken:
		color_rect.modulate = Color(0.5, 0.2, 0.2)
	else:
		color_rect.modulate = Color.WHITE

func _draw():
	# Detection range
	draw_circle(Vector2(0, -40), 200, Color(1, 0, 0, 0.05))

	# Hitbox debug
	if melee_hitbox:
		var hitbox_pos := melee_hitbox.position
		var hitbox_rect := Rect2(hitbox_pos.x - 35, hitbox_pos.y - 25, 70, 50)
		var hitbox_color := Color.GREEN if is_attacking else Color.RED
		hitbox_color.a = 0.3
		draw_rect(hitbox_rect, hitbox_color, false, 2.0)

	# Facing arrow
	var arrow_end := Vector2(30 * facing_direction, -40)
	draw_line(Vector2(0, -40), arrow_end, Color.YELLOW, 3.0)

	# Behavior indicator
	var behavior_text: String = String(AIBehavior.keys()[current_behavior])
	draw_string(ThemeDB.fallback_font, Vector2(-30, -100), behavior_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

# ===========================================================================
#  PUBLIC API — for strategy switching from UI
# ===========================================================================

func set_strategy(new_strategy: AIStrategy) -> void:
	strategy = new_strategy
	_update_strategy_label()
	_log_action("[color=white]AI Strategy: %s[/color]" % (strategy.strategy_name if strategy else "None"))

func set_character_stats(new_stats: CharacterStats) -> void:
	if new_stats == null:
		return
	var health_ratio: float = current_health / maxf(1.0, stats.max_health) if stats else 1.0
	var mana_ratio: float = current_mana / maxf(1.0, stats.max_mana) if stats else 1.0
	stats = new_stats
	current_health = clamp(stats.max_health * health_ratio, 0.0, stats.max_health)
	current_mana = clamp(stats.max_mana * mana_ratio, 0.0, stats.max_mana)
	_reset_all_state()
