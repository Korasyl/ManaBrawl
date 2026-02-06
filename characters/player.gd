extends CharacterBody2D

## Signal Queues
signal action_started(action_id: String, ctx: Dictionary)
signal action_ended(action_id: String, ctx: Dictionary)
signal mana_spent(amount: float, reason: String, ctx: Dictionary)
signal dealt_damage(amount: float, target: Node, ctx: Dictionary)
signal took_damage(amount: float, source: Node, ctx: Dictionary)

## References to our data resources
@export var stats: CharacterStats
@export var movement_data: MovementData
@export var starting_attunement: Attunement
var attunements: AttunementManager
var status_effects: StatusEffectManager
var _passive: PassiveSkill = null

## Team identity (0 = player team for demo)
var team_id: int = 0

## Wall detection raycasts
@onready var wall_check_left: RayCast2D = $WallCheckLeft
@onready var wall_check_right: RayCast2D = $WallCheckRight
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_collision: CollisionShape2D = $MeleeHitbox/CollisionShape2D

## HUD reference (we'll set this from the scene)
var debug_hud: Control = null

## Current state
var current_health: float
var current_mana: float
var is_dead: bool = false
var respawn_timer: float = 0.0
const RESPAWN_TIME: float = 3.0

## Movement state
var is_sprinting: bool = false
var is_crouching: bool = false
var can_double_jump: bool = true
var dash_available: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var air_speed: float = 0.0  # Speed we had when leaving ground
var is_on_wall_left: bool = false
var is_on_wall_right: bool = false
var is_wall_sliding: bool = false
var is_wall_clinging: bool = false
var wall_jump_lock_timer: float = 0.0  # Prevents air control right after wall jump
var is_coalescing: bool = false
var coalescence_startup_timer: float = 0.0
var coalescence_recovery_timer: float = 0.0
var coalescence_spell_lockout: float = 0.0  # Cannot cast spells for 3s after coalescence

## Interrupt state
var is_flinched: bool = false
var is_staggered: bool = false
var stun_timer: float = 0.0
const FLINCH_DURATION: float = 0.3
const STAGGER_DURATION: float = 0.3

## Block state
var is_blocking: bool = false
var block_broken: bool = false
var block_broken_timer: float = 0.0
const BLOCK_BROKEN_DURATION: float = 2.5  # GDD: 2-3 seconds

## Attack state
var is_attacking: bool = false
var attack_timer: float = 0.0
var is_heavy_attack: bool = false
var heavy_charge_timer: float = 0.0
var is_charging_heavy: bool = false  # True while holding LMB for heavy
var combo_count: int = 0
var hit_bodies_this_attack: Array = []
var combo_window_timer: float = 0.0
var can_combo: bool = false
var landed_flinch_this_attack: bool = false
var melee_cooldown_timer: float = 0.0  # Prevents attack spam after combo
const MELEE_COOLDOWN_DURATION: float = 0.4

## Ranged state
@export var projectile_spawn_offset: Vector2 = Vector2(0, -24) # Projectile origin point
var is_in_ranged_mode: bool = false
var ranged_cooldown_timer: float = 0.0
var aim_direction: Vector2 = Vector2.RIGHT
var projectile_scene: PackedScene = preload("res://scenes/combat/projectile.tscn")
var _default_ranged_mode: RangedModeData = preload("res://resources/ranged_modes/default_free_aim.tres")

## Spell state
@export var spell_slots: Array[SpellData] = []
var spell_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var queued_spell_index: int = -1  # Which spell is being aimed (-1 = none)
var active_toggles: Array[bool] = [false, false, false, false]

## Placement mode state (for "placement" cast type spells)
var is_placing: bool = false
var placement_position: Vector2 = Vector2.ZERO
var placement_rotation: float = 0.0
var placement_locked: bool = false  # True while holding LMB to rotate

## Physics
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	# Initialize from stats
	if stats:
		current_health = stats.max_health
		current_mana = stats.max_mana
	else:
		push_error("No CharacterStats assigned to Player!")
	
	# Load default test spells if none assigned
	if spell_slots.is_empty():
		spell_slots = [
			preload("res://resources/spells/arcane_bolt.tres"),
			preload("res://resources/spells/focus_strike.tres"),
			preload("res://resources/spells/haste.tres"),
			preload("res://resources/spells/mana_blast.tres"),
		]

	# Check raycasts
	if not wall_check_left:
		push_error("WallCheckLeft not found!")
	if not wall_check_right:
		push_error("WallCheckRight not found!")
	
	# Connect melee hitbox signal
	if melee_hitbox:
		melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	
	# Find and connect to debug HUD
	await get_tree().process_frame
	
	# --- Status effects init ---
	status_effects = StatusEffectManager.new()
	add_child(status_effects)
	status_effects.initialize(self)

	# --- Attunements init ---
	attunements = AttunementManager.new()
	add_child(attunements)
	attunements.initialize(self)
	attunements.set_slot_attunement(0, starting_attunement)

	# --- Passive skill init ---
	_load_passive()
	
	# Try multiple methods to find HUD
	debug_hud = get_tree().get_first_node_in_group("debug_hud")
	if not debug_hud:
		debug_hud = get_node_or_null("/root/TestEnvironment/DebugHUD")
	
	if debug_hud and starting_attunement:
		debug_hud.log_action("[color=violet]Attune Slot 1:[/color] %s" % starting_attunement.attunement_name)
	
	print("Found debug HUD: ", debug_hud)
	if debug_hud:
		update_hud()
	else:
		print("ERROR: Debug HUD not found!")


func _physics_process(delta):
	# Handle death/respawn
	if is_dead:
		respawn_timer -= delta
		if respawn_timer <= 0:
			respawn()
		update_hud()
		return

	# --- Timers (always tick) ---
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			set_collision_mask_value(2, true)
			var ctx := {ContextKeys.IS_AIRBORNE: not is_on_floor()}
			emit_signal("action_ended", "dash", ctx)
			if attunements:
				attunements.notify_action_ended("dash", ctx)

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

	if ranged_cooldown_timer > 0:
		ranged_cooldown_timer -= delta

	# Spell cooldowns
	for i in 4:
		if spell_cooldowns[i] > 0:
			spell_cooldowns[i] -= delta

	# Toggle spell mana drain
	for i in 4:
		if active_toggles[i] and i < spell_slots.size() and spell_slots[i] != null:
			var drain: float = spell_slots[i].toggle_mana_drain * delta
			current_mana -= drain
			if current_mana <= 0:
				current_mana = 0.0
				active_toggles[i] = false
				if debug_hud:
					debug_hud.log_action("[color=gray]%s OFF (no mana)[/color]" % spell_slots[i].spell_name)

	if block_broken_timer > 0:
		block_broken_timer -= delta
		if block_broken_timer <= 0:
			block_broken = false
			if debug_hud:
				debug_hud.log_action("[color=lime]Block restored[/color]")

	# Handle stun (flinch/stagger)
	if stun_timer > 0:
		stun_timer -= delta
		if stun_timer <= 0:
			is_flinched = false
			is_staggered = false

	handle_attack_timers(delta)

	# Detect walls
	is_on_wall_left = wall_check_left.is_colliding()
	is_on_wall_right = wall_check_right.is_colliding()

	# Apply gravity (unless dashing or coalescing)
	if not is_on_floor() and not is_dashing and not is_coalescing:
		velocity.y += gravity * delta

	# Reset double jump when landing
	if is_on_floor():
		can_double_jump = true
		wall_jump_lock_timer = 0.0

	# --- Stunned or CC'd: no actions, just slide to a stop ---
	var is_stunned := is_flinched or is_staggered
	var is_cc := status_effects.is_grabbed() if status_effects else false
	if is_stunned or is_cc:
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0.0, 0.15)
		if is_cc:
			velocity = Vector2.ZERO
		move_and_slide()
		update_hud()
		update_facing_direction()
		update_animation()
		return

	# --- Normal action processing ---
	handle_blocking(delta)
	handle_coalescence(delta)

	if not is_coalescing and not is_attacking and not is_blocking:
		handle_wall_mechanics(delta)

	if not is_coalescing and not is_attacking and not is_blocking:
		handle_dash()

	handle_ranged_mode()
	handle_spell_input()
	handle_placement_mode()
	handle_attack_input()

	# Tick passive skill
	if _passive:
		_passive._passive_process(delta)

	# Movement: not while dashing, wall jump locked, coalescing, recovering, attacking, or blocking
	if not is_dashing and wall_jump_lock_timer <= 0 and not is_coalescing and coalescence_recovery_timer <= 0 and not is_attacking:
		handle_movement(delta)

	regenerate_mana(delta)
	move_and_slide()
	update_hud()
	update_facing_direction()
	update_animation()
	if is_in_ranged_mode or queued_spell_index >= 0:
		queue_redraw()

func handle_movement(delta):
	# Get input direction
	var input_dir = Input.get_axis("move_left", "move_right")

	# Determine speed based on state
	var target_speed = 0.0

	if is_on_floor():
		# ON GROUND: Check input for speed
		if input_dir != 0:
			is_crouching = Input.is_action_pressed("crouch")
			is_sprinting = Input.is_action_pressed("sprint") and not is_crouching

			if is_crouching:
				target_speed = stats.crouch_speed
			elif is_sprinting:
				target_speed = stats.sprint_speed
			else:
				target_speed = stats.walk_speed

		# Store this speed for when we go airborne
		air_speed = target_speed
	else:
		# IN AIR: Use stored air speed, but allow control if it's zero
		if input_dir != 0:
			if air_speed > 0:
				# Use the speed we had when we left ground
				target_speed = air_speed
			else:
				# If we jumped from standing still, allow walk-speed air control
				target_speed = stats.walk_speed

	# Block movement penalty (GDD: significantly slows movement)
	if is_blocking:
		target_speed = stats.block_move_speed

	# Ranged mode movement penalty
	if is_in_ranged_mode:
		var mode := _get_effective_ranged_mode()
		target_speed *= mode.move_speed_mult

	# Toggle spell speed modifiers
	for i in 4:
		if active_toggles[i] and i < spell_slots.size() and spell_slots[i] != null:
			target_speed *= spell_slots[i].slow_move

	# Apply attunement move speed multiplier
	if attunements:
		target_speed *= attunements.get_move_speed_mult()

	# Apply status effect speed modifiers
	if status_effects:
		target_speed *= status_effects.get_speed_mult()

	# Apply horizontal movement
	velocity.x = input_dir * target_speed

	# Jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = stats.jump_velocity
		elif can_double_jump and movement_data.can_double_jump:
			var spent := use_mana(stats.double_jump_cost, "double_jump")
			if spent > 0.0:
				velocity.y = stats.jump_velocity
				can_double_jump = false
				if debug_hud:
					debug_hud.log_action("Double Jump", -spent)

func update_facing_direction():
	# Get mouse position in world space
	var mouse_pos = get_global_mouse_position()
	var player_pos = global_position
	
	# Flip sprite based on mouse position relative to player
	if mouse_pos.x < player_pos.x:
		animated_sprite.flip_h = true  # Facing left
		# Move hitbox to left side
		melee_hitbox.position.x = -30
	else:
		animated_sprite.flip_h = false  # Facing right
		# Move hitbox to right side
		melee_hitbox.position.x = 30

func regenerate_mana(delta):
	if stats and current_mana < stats.max_mana:
		var regen_rate = stats.passive_mana_regen

		# Enhanced regen if coalescing and past startup
		if is_coalescing and coalescence_startup_timer <= 0:
			regen_rate *= stats.coalescence_multiplier

		# Attunement modifier
		if attunements:
			regen_rate *= attunements.get_regen_mult()

		current_mana = min(current_mana + regen_rate * delta, stats.max_mana)

func use_mana(amount: float, reason: String = "", ctx: Dictionary = {}) -> float:
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

func update_hud():
	if not debug_hud:
		print("DEBUG HUD IS NULL!")
		return
	
	# Update mana and health
	debug_hud.update_mana(current_mana, stats.max_mana)
	debug_hud.update_health(current_health, stats.max_health)
	
	# Update state
	var state = "Idle"
	if is_flinched:
		state = "FLINCHED (%.1fs)" % stun_timer
	elif is_staggered:
		state = "STAGGERED (%.1fs)" % stun_timer
	elif is_blocking:
		state = "BLOCKING"
	elif block_broken:
		state = "Block Broken (%.1fs)" % block_broken_timer
	elif is_coalescing:
		if coalescence_startup_timer > 0:
			state = "Coalescing... (%.1fs)" % coalescence_startup_timer
		else:
			state = "COALESCING! (Mult Regen)"
	elif coalescence_recovery_timer > 0:
		state = "Recovery (%.1fs)" % coalescence_recovery_timer
	elif coalescence_spell_lockout > 0:
		state = "Spell Locked (%.1fs)" % coalescence_spell_lockout
	elif status_effects and status_effects.is_grabbed():
		state = "GRABBED"
	elif status_effects and status_effects.is_rooted():
		state = "ROOTED"
	elif is_dashing:
		state = "DASHING"
	elif is_placing and queued_spell_index >= 0 and queued_spell_index < spell_slots.size():
		var pstate := "rotating" if placement_locked else "positioning"
		state = "Placing: %s (%s)" % [spell_slots[queued_spell_index].spell_name, pstate]
	elif queued_spell_index >= 0 and queued_spell_index < spell_slots.size() and spell_slots[queued_spell_index] != null:
		state = "Spell Queued: %s" % spell_slots[queued_spell_index].spell_name
	elif is_in_ranged_mode:
		state = "RANGED MODE"
	elif is_charging_heavy:
		state = "Charging Heavy (%.1fs)" % heavy_charge_timer
	elif melee_cooldown_timer > 0:
		state = "Melee CD (%.1fs)" % melee_cooldown_timer
	elif is_wall_clinging:
		state = "Wall Cling"
	elif is_wall_sliding:
		state = "Wall Slide"
	elif not is_on_floor():
		state = "In Air"
	elif is_sprinting:
		state = "Sprinting"
	elif is_crouching:
		state = "Crouching"
	elif velocity.x != 0:
		state = "Walking"
	
	debug_hud.update_state(state)
	
	# Update combo display
	debug_hud.update_combo(combo_count, can_combo)

	# Update spell display
	if debug_hud.has_method("update_spells"):
		debug_hud.update_spells(spell_slots, spell_cooldowns, active_toggles, queued_spell_index)

func handle_dash():
	if Input.is_action_just_pressed("dash") and dash_available:
		# Spend mana ONCE and capture actual cost
		var spent := use_mana(stats.dash_cost, "dash")
		if spent <= 0.0:
			return  # Not enough mana

		# Determine dash direction
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir == 0:
			input_dir = -1 if animated_sprite.flip_h else 1

		dash_direction = Vector2(input_dir, 0).normalized()

		var ctx := {ContextKeys.DASH_DIRECTION: dash_direction, ContextKeys.DASH_AIRBORNE: not is_on_floor(), ContextKeys.MANA_SPENT: spent}
		emit_signal("action_started", "dash", ctx)
		if attunements:
			attunements.notify_action_started("dash", ctx)

		# Start dash
		is_dashing = true
		dash_timer = movement_data.dash_duration
		dash_available = false
		dash_cooldown_timer = movement_data.dash_cooldown

		# Disable collision with enemies during dash
		set_collision_mask_value(2, false)

		# Apply dash velocity
		velocity = dash_direction * movement_data.dash_distance / movement_data.dash_duration

		# Log it with the true cost
		if debug_hud:
			debug_hud.log_action("DASH!", -spent)

func handle_wall_mechanics(delta):
	var on_wall = is_on_wall_left or is_on_wall_right
	
	# Reset wall sliding/clinging when on floor or not on wall
	if is_on_floor() or not on_wall:
		is_wall_sliding = false
		is_wall_clinging = false
		return
	
	# Wall mechanics: touching wall + falling + not on ground
	if not is_on_floor() and on_wall and velocity.y > 0:
		var input_dir = Input.get_axis("move_left", "move_right")
		var pressing_into_wall = (is_on_wall_left and input_dir < 0) or (is_on_wall_right and input_dir > 0)

		# Wall Cling: Pressing into wall with cling enabled and mana available
		if pressing_into_wall and movement_data.can_wall_cling:
			var spent := use_mana(stats.wall_cling_drain * delta, "wall_cling")
			if spent > 0.0:
				is_wall_clinging = true
				is_wall_sliding = false
				velocity.y = 0  # Stop falling completely
			else:
				# No mana — fall back to wall slide
				is_wall_clinging = false
				is_wall_sliding = true
				velocity.y = movement_data.wall_slide_speed
		else:
			# Wall Slide: Passive, just touching wall while falling (GDD)
			is_wall_clinging = false
			is_wall_sliding = true
			velocity.y = movement_data.wall_slide_speed
	else:
		is_wall_sliding = false
		is_wall_clinging = false
	
	# Wall Jump: Press jump while on wall
	if (is_wall_sliding or is_wall_clinging) and Input.is_action_just_pressed("jump"):
		if movement_data.can_wall_jump:
			var spent := use_mana(stats.wall_jump_cost, "wall_jump")
			if spent > 0.0:
				var jump_dir = 1 if is_on_wall_left else -1
				velocity.y = stats.jump_velocity
				velocity.x = jump_dir * movement_data.wall_jump_horizontal_boost

				wall_jump_lock_timer = 0.2
				can_double_jump = true

				is_wall_sliding = false
				is_wall_clinging = false

				if debug_hud:
					debug_hud.log_action("Wall Jump", -spent)


func handle_blocking(delta):
	# GDD: Hold Alt to block. Ground only. Constant mana drain. Cannot block while airborne.
	if Input.is_action_pressed("block") and is_on_floor() and not block_broken and not is_attacking and not is_coalescing and not is_dashing:
		var spent := use_mana(stats.block_mana_drain * delta, "block")
		if spent > 0.0:
			if not is_blocking:
				is_blocking = true
				if debug_hud:
					debug_hud.log_action("[color=cyan]Blocking[/color]")
		else:
			# Ran out of mana
			if is_blocking:
				is_blocking = false
				if debug_hud:
					debug_hud.log_action("[color=gray]Block dropped (no mana)[/color]")
	else:
		is_blocking = false

func handle_coalescence(delta):
	# Check if player wants to start/continue coalescing
	if Input.is_action_pressed("coalesce") and coalescence_recovery_timer <= 0:
		if not is_coalescing:
			# Start coalescence
			is_coalescing = true
			coalescence_startup_timer = 1.0  # 1 second startup (GDD)
			velocity = Vector2.ZERO  # Stop all movement
			if debug_hud:
				debug_hud.log_action("Coalescing...")
		else:
			# Continue coalescing - handle startup timer
			if coalescence_startup_timer > 0:
				coalescence_startup_timer -= delta
			
			# Keep velocity at zero while coalescing
			velocity = Vector2.ZERO
	else:
		# Player released the button or is in recovery
		if is_coalescing:
			# Cancel coalescence
			is_coalescing = false
			coalescence_recovery_timer = 0.5  # 0.5 second recovery (GDD)
			coalescence_spell_lockout = 3.0  # Cannot cast spells for 3s (GDD)
			coalescence_startup_timer = 0.0
			if debug_hud:
				debug_hud.log_action("Coalescence cancelled")

func update_animation():
	if not animated_sprite:
		return
	
	# Determine which animation to play based on state
	var anim = "idle"

	if is_flinched or is_staggered:
		anim = "hit"
	elif is_blocking:
		anim = "block"
	elif is_coalescing:
		# Different coalesce animations based on ground vs air
		if is_on_floor():
			anim = "coalesce_ground"
		else:
			anim = "coalesce_air"
	elif is_dashing:
		anim = "dash"
	elif is_wall_clinging:
		anim = "wall_cling"
	elif is_wall_sliding:
		anim = "wall_slide"
	elif not is_on_floor():
		# In air
		if velocity.y < 0:
			anim = "jump"
		else:
			anim = "fall"
	elif is_crouching:
		anim = "crouch"
	elif abs(velocity.x) > 0:
		# Moving on ground
		if is_sprinting:
			anim = "sprint"
		else:
			anim = "walk"
	else:
		anim = "idle"
	
	# Play the animation if it's different from current
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)
	
	# Update debug HUD with current animation
	if debug_hud:
		debug_hud.update_animation(anim)

func handle_attack_timers(delta):
	# Handle attack duration
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0:
			end_attack()
	
	# Handle combo window
	if combo_window_timer > 0:
		combo_window_timer -= delta
		if combo_window_timer <= 0:
			can_combo = false
			combo_count = 0
			if debug_hud:
				debug_hud.log_action("[color=gray]Combo window expired[/color]")
	
	# Handle heavy attack charging — track is_charging_heavy for flinch immunity
	if Input.is_action_pressed("light_attack") and not is_attacking and not is_blocking:
		heavy_charge_timer += delta
		if heavy_charge_timer >= stats.heavy_attack_charge_time:
			is_charging_heavy = true
	else:
		if not is_attacking:
			is_charging_heavy = false

func handle_attack_input():
	# Can't melee while in ranged mode, spell queue, coalescing, dashing, recovery, blocking, or on cooldown
	if is_in_ranged_mode or queued_spell_index >= 0:
		return
	if is_coalescing or is_dashing or coalescence_recovery_timer > 0 or wall_jump_lock_timer > 0 or is_blocking:
		return
	if melee_cooldown_timer > 0:
		return

	# Light attack (tap) or Heavy attack (hold and release)
	if Input.is_action_just_released("light_attack") and not is_attacking:
		if heavy_charge_timer >= stats.heavy_attack_charge_time:
			# Heavy attack (can be used as combo ender)
			perform_heavy_attack()
			combo_count = 0
			can_combo = false
			combo_window_timer = 0.0
		else:
			# Light attack
			if combo_count == 0:
				perform_light_attack()
			elif can_combo and combo_count == 1:
				# Second light in combo (guaranteed if first flinched)
				perform_light_attack()
			else:
				combo_count = 0
				can_combo = false
				perform_light_attack()

		heavy_charge_timer = 0.0
		is_charging_heavy = false

	if Input.is_action_just_released("light_attack"):
		heavy_charge_timer = 0.0
		is_charging_heavy = false

func perform_light_attack():
	is_attacking = true
	is_heavy_attack = false
	attack_timer = stats.light_attack_duration
	hit_bodies_this_attack.clear()
	landed_flinch_this_attack = false  # Reset flinch tracker
	
	# Increment combo count
	combo_count += 1
	
	# Enable hitbox
	melee_collision.disabled = false
	
	if debug_hud:
		var combo_text = " #%d" % combo_count if combo_count > 1 else ""
		debug_hud.log_action("[color=cyan]Light Attack%s[/color]" % combo_text)

func perform_heavy_attack():
	is_attacking = true
	is_heavy_attack = true
	attack_timer = stats.heavy_attack_duration
	hit_bodies_this_attack.clear()  # Clear hit list
	
	# Enable hitbox
	melee_collision.disabled = false
	
	if debug_hud:
		debug_hud.log_action("Heavy Attack")

func end_attack():
	is_attacking = false
	melee_collision.disabled = true

	# If first light landed a flinch, open combo window
	if combo_count == 1 and not is_heavy_attack and landed_flinch_this_attack:
		can_combo = true
		combo_window_timer = 0.5
		if debug_hud:
			debug_hud.log_action("[color=lime]Combo available![/color]")
	elif combo_count >= 2 or is_heavy_attack:
		# Combo finished or heavy used — apply melee cooldown (GDD: prevents spam)
		combo_count = 0
		can_combo = false
		combo_window_timer = 0.0
		melee_cooldown_timer = MELEE_COOLDOWN_DURATION

	is_heavy_attack = false

func _on_melee_hitbox_body_entered(hit_body):
	# Only process hits during active attack
	if not is_attacking:
		return

	# Don't hit ourselves
	if hit_body == self:
		return

	# Don't hit the same body twice in one attack
	if hit_body in hit_bodies_this_attack:
		return

	# Must be damageable
	if not hit_body.has_method("take_damage"):
		return

	# Add to hit list
	hit_bodies_this_attack.append(hit_body)

	# Base damage + key
	var base_damage: float = float(stats.heavy_attack_damage if is_heavy_attack else stats.light_attack_damage)
	var dmg_key := ModKeys.HEAVY_DAMAGE if is_heavy_attack else ModKeys.LIGHT_DAMAGE

	# Context for attunements
	var ctx := {
		ContextKeys.SOURCE: self,
		ContextKeys.TARGET: hit_body,
		ContextKeys.ATTACK_ID: ("heavy_attack" if is_heavy_attack else "light_attack"),
		ContextKeys.DAMAGE_TYPE: "melee",
		ContextKeys.BASE_DAMAGE: base_damage,
		ContextKeys.IS_AIRBORNE: not is_on_floor(),
		ContextKeys.IS_COALESCING: is_coalescing,
		ContextKeys.FACING: -1 if animated_sprite.flip_h else 1,
		ContextKeys.COMBO_COUNT: combo_count,
	}
	
	# Final damage (attunements decide how)
	var final_damage: float = base_damage
	if attunements:
		final_damage = float(attunements.modify_damage(dmg_key, base_damage, ctx))

	# Knockback
	var knockback := Vector2.ZERO
	if is_heavy_attack:
		var direction := 1 if not animated_sprite.flip_h else -1
		knockback = Vector2(direction * stats.knockback_force, -400)

	# Determine interrupt type
	var interrupt_type := "flinch" if not is_heavy_attack else "stagger"

	# --- Clash detection ---
	# If target is also actively attacking, check for clash
	var target_is_attacking := false
	if "is_attacking" in hit_body:
		target_is_attacking = hit_body.is_attacking
	if target_is_attacking:
		var target_is_heavy := false
		if "is_heavy_attack" in hit_body:
			target_is_heavy = hit_body.is_heavy_attack
		if not is_heavy_attack and not target_is_heavy:
			# Light vs Light: both cancelled, no damage, no flinch
			end_attack()
			if hit_body.has_method("end_attack"):
				hit_body.end_attack()
			elif hit_body.has_method("end_dummy_attack"):
				hit_body.end_dummy_attack()
			if debug_hud:
				debug_hud.log_action("[color=white]CLASH! (Light vs Light)[/color]")
			return
		elif is_heavy_attack and target_is_heavy:
			# Heavy vs Heavy: both cancelled, mutual knockback, no damage
			var clash_dir := 1 if not animated_sprite.flip_h else -1
			velocity = Vector2(-clash_dir * stats.knockback_force * 0.5, -200)
			if hit_body is CharacterBody2D:
				hit_body.velocity = Vector2(clash_dir * stats.knockback_force * 0.5, -200)
			end_attack()
			if hit_body.has_method("end_attack"):
				hit_body.end_attack()
			elif hit_body.has_method("end_dummy_attack"):
				hit_body.end_dummy_attack()
			if debug_hud:
				debug_hud.log_action("[color=white]CLASH! (Heavy vs Heavy)[/color]")
			return
		# Mixed (light vs heavy, heavy vs light): no clash, stronger wins

	# Check if target is blocking (before calling take_damage so we can adjust mana)
	var target_is_blocking := false
	if "is_blocking" in hit_body:
		target_is_blocking = hit_body.is_blocking

	# Deal damage with interrupt type
	ctx[ContextKeys.DAMAGE] = final_damage
	ctx[ContextKeys.INTERRUPT] = interrupt_type
	hit_body.take_damage(final_damage, knockback, interrupt_type, ctx)

	# Determine mana gain based on what happened
	var base_gain: float
	var gain_key: String
	var hit_log: String

	if target_is_blocking and interrupt_type == "stagger":
		# Shield break — GDD: attacker gains significant bonus mana, no damage dealt
		base_gain = stats.heavy_shield_break_bonus
		gain_key = ModKeys.HEAVY_MELEE_HIT_MANA_GAIN
		hit_log = "[color=yellow]SHIELD BREAK![/color]"
	elif target_is_blocking and interrupt_type == "flinch":
		# Blocked hit — GDD: minor mana gain
		base_gain = stats.melee_blocked_mana_gain
		gain_key = ModKeys.MELEE_HIT_MANA_GAIN
		hit_log = "[color=gray]Blocked[/color]"
	else:
		# Clean hit
		base_gain = float(stats.heavy_melee_hit_mana_gain if is_heavy_attack else stats.melee_hit_mana_gain)
		gain_key = ModKeys.HEAVY_MELEE_HIT_MANA_GAIN if is_heavy_attack else ModKeys.MELEE_HIT_MANA_GAIN
		hit_log = "HIT!"
		# Track flinch for combo system (only on clean hit)
		if interrupt_type == "flinch":
			landed_flinch_this_attack = true

	var final_gain: float = base_gain
	if attunements:
		final_gain = float(attunements.modify_mana_gain(gain_key, base_gain, ctx))

	# Signals + attunement notification
	emit_signal("dealt_damage", final_damage, hit_body, ctx)
	if attunements:
		attunements.notify_dealt_damage(final_damage, hit_body, ctx)

	current_mana = min(current_mana + final_gain, stats.max_mana)
	if debug_hud:
		debug_hud.log_action(hit_log, final_gain)

func set_character_stats(new_stats: CharacterStats, keep_ratios: bool = true) -> void:
	if new_stats == null:
		return

	var health_ratio := 1.0
	var mana_ratio := 1.0

	if stats != null and keep_ratios:
		health_ratio = current_health / max(1.0, stats.max_health)
		mana_ratio = current_mana / max(1.0, stats.max_mana)

	stats = new_stats

	if keep_ratios:
		current_health = clamp(stats.max_health * health_ratio, 0.0, stats.max_health)
		current_mana = clamp(stats.max_mana * mana_ratio, 0.0, stats.max_mana)
	else:
		current_health = stats.max_health
		current_mana = stats.max_mana

	# State cleanup when switching characters
	is_attacking = false
	is_coalescing = false
	is_dashing = false
	is_blocking = false
	is_flinched = false
	is_staggered = false
	is_charging_heavy = false
	block_broken = false
	stun_timer = 0.0
	attack_timer = 0.0
	heavy_charge_timer = 0.0
	coalescence_startup_timer = 0.0
	coalescence_recovery_timer = 0.0
	coalescence_spell_lockout = 0.0
	block_broken_timer = 0.0
	melee_cooldown_timer = 0.0
	is_in_ranged_mode = false
	ranged_cooldown_timer = 0.0
	queued_spell_index = -1
	is_placing = false
	placement_locked = false

	# Reload passive for new character
	_load_passive()

	# Clear status effects
	if status_effects:
		status_effects.clear_all()

	if debug_hud:
		debug_hud.log_action("[color=cyan]Swapped to:[/color] %s" % stats.character_name)
		update_hud()

func set_attunement_slot(slot_index: int, a: Attunement) -> void:
	if attunements == null:
		return

	attunements.set_slot_attunement(slot_index, a)

	# Optional: tell HUD
	if debug_hud:
		var name := a.attunement_name if a else "— Empty —"
		debug_hud.log_action("[color=violet]Attune Slot %d:[/color] %s" % [slot_index + 1, name])

func get_attunement_slot(slot_index: int) -> Attunement:
	if attunements == null:
		return null
	return attunements.get_slot_attunement(slot_index)

func is_ally(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id == team_id
	return false

func is_enemy(other: Node) -> bool:
	if "team_id" in other:
		return other.team_id != team_id
	return other != self

func take_damage(damage: float, knockback_velocity: Vector2 = Vector2.ZERO, interrupt_type: String = "none", ctx: Dictionary = {}):
	print("PLAYER: take_damage called! damage=%.1f, knockback=%s, type=%s" % [damage, knockback_velocity, interrupt_type])
	if is_dead:
		return
	
	if is_dashing:
		# Record that this hit was avoided (so attunements can react later)
		ctx[ContextKeys.WAS_AVOIDED] = true
		ctx[ContextKeys.AVOID_REASON] = "dash"

		var source_name := "unknown"
		if ctx.has(ContextKeys.SOURCE) and ctx[ContextKeys.SOURCE] != null:
			source_name = str(ctx[ContextKeys.SOURCE].name)

		if debug_hud:
			debug_hud.log_action(
				"[color=gray]Avoided %.0f damage from %s (DASH)[/color]" % [damage, source_name],
				0
			)

		# Still notify systems that a hit attempt occurred (but did 0 damage)
		emit_signal("took_damage", 0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		if attunements:
			attunements.notify_took_damage(0.0, ctx.get(ContextKeys.SOURCE, null), ctx)

		return
	
	# --- Check flinch immunity ---
	# Coalescence: immune to flinch, vulnerable to stagger (GDD)
	# Heavy attack windup/active: immune to flinch, vulnerable to stagger (GDD)
	var flinch_immune := is_coalescing or (is_attacking and is_heavy_attack) or is_charging_heavy
	if interrupt_type == "flinch" and flinch_immune:
		# Take damage but ignore the interrupt entirely
		current_health -= damage
		_flash_damage()
		if debug_hud:
			var reason_str := "Coalescing" if is_coalescing else "Heavy Armor"
			debug_hud.log_action("[color=gray]Flinch ignored (%s)[/color]" % reason_str)
			debug_hud.log_action("[color=red]Took %.0f damage![/color]" % damage, -damage)
		emit_signal("took_damage", damage, ctx.get(ContextKeys.SOURCE, null), ctx)
		if attunements:
			attunements.notify_took_damage(damage, ctx.get(ContextKeys.SOURCE, null), ctx)
		if current_health <= 0:
			die()
		return

	# --- Block absorption ---
	if is_blocking and interrupt_type == "flinch":
		# Block stops light attacks — no damage, minor mana gain for attacker
		ctx[ContextKeys.IS_BLOCKED] = true
		if debug_hud:
			debug_hud.log_action("[color=cyan]BLOCKED![/color]")
		emit_signal("took_damage", 0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		if attunements:
			attunements.notify_took_damage(0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		return

	if is_blocking and interrupt_type == "stagger":
		# Heavy attack shatters the block (GDD: no damage, no knockback)
		is_blocking = false
		block_broken = true
		block_broken_timer = BLOCK_BROKEN_DURATION
		ctx[ContextKeys.IS_SHIELD_BREAK] = true
		if debug_hud:
			debug_hud.log_action("[color=red]SHIELD BREAK![/color]")
		emit_signal("took_damage", 0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		if attunements:
			attunements.notify_took_damage(0.0, ctx.get(ContextKeys.SOURCE, null), ctx)
		return

	# --- Apply damage ---
	current_health -= damage
	_flash_damage()

	# Stagger interrupts coalescence — check before knockback clears state
	if is_coalescing and interrupt_type == "stagger":
		is_coalescing = false
		coalescence_recovery_timer = 0.5
		coalescence_spell_lockout = 3.0
		coalescence_startup_timer = 0.0
		if debug_hud:
			debug_hud.log_action("[color=orange]Coalescence interrupted (Stagger)![/color]")

	# Apply knockback and interrupt current actions
	if knockback_velocity != Vector2.ZERO:
		velocity = knockback_velocity
		is_attacking = false
		is_coalescing = false
		is_dashing = false
		is_charging_heavy = false
		heavy_charge_timer = 0.0
		melee_collision.disabled = true

	# Apply flinch/stagger hitstun
	match interrupt_type:
		"flinch":
			is_flinched = true
			is_staggered = false
			stun_timer = FLINCH_DURATION
			# Cancel current attack
			if is_attacking:
				end_attack()
			is_charging_heavy = false
			heavy_charge_timer = 0.0
		"stagger":
			is_flinched = false
			is_staggered = true
			stun_timer = STAGGER_DURATION
			# Stagger cancels everything
			if is_attacking:
				end_attack()
			is_charging_heavy = false
			heavy_charge_timer = 0.0
			is_blocking = false

	if debug_hud:
		debug_hud.log_action("[color=red]Took %.0f damage![/color]" % damage, -damage)

	emit_signal("took_damage", damage, ctx.get(ContextKeys.SOURCE, null), ctx)
	if attunements:
		attunements.notify_took_damage(damage, ctx.get(ContextKeys.SOURCE, null), ctx)

	if current_health <= 0:
		die()

func _flash_damage():
	if animated_sprite:
		animated_sprite.modulate = Color.RED
		await get_tree().create_timer(0.1).timeout
		if not is_dead:
			animated_sprite.modulate = Color.WHITE

func die():
	is_dead = true
	respawn_timer = RESPAWN_TIME
	current_health = 0
	velocity = Vector2.ZERO

	# Cancel all actions
	is_attacking = false
	is_coalescing = false
	is_dashing = false
	is_blocking = false
	is_flinched = false
	is_staggered = false
	is_charging_heavy = false
	is_in_ranged_mode = false
	queued_spell_index = -1
	active_toggles = [false, false, false, false]
	is_placing = false
	placement_locked = false
	stun_timer = 0.0
	melee_collision.disabled = true
	if status_effects:
		status_effects.clear_all()
	
	# Visual feedback
	if animated_sprite:
		animated_sprite.modulate = Color(0.3, 0.3, 0.3)  # Dark gray
	
	if debug_hud:
		debug_hud.log_action("[color=red]DIED! Respawning...[/color]")

func respawn():
	is_dead = false
	current_health = stats.max_health
	current_mana = stats.max_mana
	velocity = Vector2.ZERO

	# Reset all combat states
	is_flinched = false
	is_staggered = false
	stun_timer = 0.0
	is_blocking = false
	block_broken = false
	block_broken_timer = 0.0
	is_charging_heavy = false
	melee_cooldown_timer = 0.0
	is_in_ranged_mode = false
	ranged_cooldown_timer = 0.0
	queued_spell_index = -1
	spell_cooldowns = [0.0, 0.0, 0.0, 0.0]
	active_toggles = [false, false, false, false]
	is_placing = false
	placement_locked = false
	if status_effects:
		status_effects.clear_all()

	# Visual feedback
	if animated_sprite:
		animated_sprite.modulate = Color.WHITE

	if debug_hud:
		debug_hud.log_action("[color=lime]Respawned![/color]")

# ---- Ranged Mode ----

## Returns the effective ranged mode: attunement override > stats.ranged_mode > fallback default.
func _get_effective_ranged_mode() -> RangedModeData:
	if attunements:
		var override := attunements.get_ranged_mode_override()
		if override != null:
			return override
	if stats and stats.ranged_mode:
		return stats.ranged_mode
	return _default_ranged_mode

func handle_ranged_mode():
	# Can't enter ranged mode during these states
	if is_attacking or is_blocking or is_coalescing or is_dashing:
		is_in_ranged_mode = false
		return

	var mode := _get_effective_ranged_mode()
	if mode.mode_type == "none":
		is_in_ranged_mode = false
		return

	if Input.is_action_pressed("ranged_mode"):
		is_in_ranged_mode = true
		aim_direction = (get_global_mouse_position() - global_position).normalized()

		# Fire on LMB (only if no spell queued)
		if Input.is_action_just_pressed("light_attack") and ranged_cooldown_timer <= 0 and queued_spell_index < 0:
			fire_projectile(mode)
	else:
		is_in_ranged_mode = false

func fire_projectile(mode: RangedModeData):
	var scene := mode.projectile_scene if mode.projectile_scene else projectile_scene
	var proj = scene.instantiate()
	proj.global_position = _get_projectile_spawn_base() + aim_direction * 40
	proj.direction = aim_direction
	proj.speed = mode.projectile_speed
	proj.damage = mode.damage
	proj.damage_type = mode.damage_type
	proj.interrupt_type = mode.interrupt_type
	proj.source = self
	proj.team_id = team_id
	get_tree().current_scene.add_child(proj)
	# Apply projectile color
	if proj.has_node("ColorRect"):
		proj.get_node("ColorRect").color = mode.projectile_color
	ranged_cooldown_timer = mode.fire_cooldown

	if debug_hud:
		debug_hud.log_action("[color=yellow]%s[/color]" % mode.mode_name)

func _get_projectile_spawn_base() -> Vector2:
	return global_position + projectile_spawn_offset	

# ---- Spell System ----

func handle_spell_input():
	if is_coalescing or is_dashing or coalescence_spell_lockout > 0:
		return
	if status_effects and status_effects.is_silenced():
		return

	# Check spell keys 1-4
	for i in 4:
		var action_name := "spell_%d" % (i + 1)
		if Input.is_action_just_pressed(action_name):
			_on_spell_key_pressed(i)

	# If a spell is queued and LMB pressed, cast it
	if queued_spell_index >= 0 and Input.is_action_just_pressed("light_attack"):
		cast_spell(queued_spell_index)

func _on_spell_key_pressed(index: int):
	if index >= spell_slots.size() or spell_slots[index] == null:
		return

	var spell := spell_slots[index]

	if spell.cast_type == "toggled":
		_toggle_spell(index)
	else:
		# Targeted, free_aim, or placement: queue/cancel
		if queued_spell_index == index:
			# Cancel queue (also cancels placement mode)
			if is_placing:
				_cancel_placement()
			else:
				queued_spell_index = -1
				if debug_hud:
					debug_hud.log_action("[color=gray]Spell cancelled[/color]")
		else:
			if spell_cooldowns[index] > 0:
				if debug_hud:
					debug_hud.log_action("[color=red]On cooldown (%.1fs)[/color]" % spell_cooldowns[index])
				return
			if current_mana < spell.mana_cost:
				if debug_hud:
					debug_hud.log_action("[color=red]Not enough mana[/color]")
				return
			queued_spell_index = index
			# Enter placement mode for placement spells
			if spell.cast_type == "placement":
				is_placing = true
				placement_locked = false
				placement_position = get_global_mouse_position()
				if debug_hud:
					debug_hud.log_action("[color=violet]Placing: %s (click to position)[/color]" % spell.spell_name)
			else:
				if debug_hud:
					debug_hud.log_action("[color=violet]Queued: %s (LMB to cast)[/color]" % spell.spell_name)

func _toggle_spell(index: int):
	var spell := spell_slots[index]
	if active_toggles[index]:
		active_toggles[index] = false
		if debug_hud:
			debug_hud.log_action("[color=gray]%s OFF[/color]" % spell.spell_name)
	else:
		if spell_cooldowns[index] > 0:
			if debug_hud:
				debug_hud.log_action("[color=red]On cooldown (%.1fs)[/color]" % spell_cooldowns[index])
			return
		if current_mana < spell.mana_cost:
			if debug_hud:
				debug_hud.log_action("[color=red]Not enough mana[/color]")
			return
		var spent := use_mana(spell.mana_cost, "spell_toggle")
		if spent > 0:
			active_toggles[index] = true
			if debug_hud:
				debug_hud.log_action("[color=violet]%s ON[/color]" % spell.spell_name, -spent)

func cast_spell(index: int):
	if index >= spell_slots.size() or spell_slots[index] == null:
		queued_spell_index = -1
		return

	var spell := spell_slots[index]

	# Placement spells are handled by handle_placement_mode(), not here
	if spell.cast_type == "placement":
		return

	# For targeted spells, find target first (don't consume mana if no target)
	var target_body: Node = null
	if spell.cast_type == "targeted":
		target_body = _find_target_near_cursor()
		if target_body == null:
			if debug_hud:
				debug_hud.log_action("[color=red]No target found[/color]")
			return

	var spent := use_mana(spell.mana_cost, "spell_cast")
	if spent <= 0:
		queued_spell_index = -1
		return

	spell_cooldowns[index] = spell.cooldown
	queued_spell_index = -1

	match spell.cast_type:
		"free_aim":
			_fire_spell_projectile(spell)
		"targeted":
			_fire_targeted_projectile(spell, target_body)

	if debug_hud:
		debug_hud.log_action("[color=violet]Cast: %s[/color]" % spell.spell_name, -spent)

func _fire_spell_projectile(spell: SpellData):
	var dir := (get_global_mouse_position() - global_position).normalized()

	# If spell has a custom scene, spawn it directly (it handles its own behavior)
	if spell.spell_scene:
		_spawn_spell_scene(spell, _get_projectile_spawn_base() + dir * 40, dir)
		return

	# Default: fire a projectile
	var proj = projectile_scene.instantiate()
	proj.global_position = _get_projectile_spawn_base() + dir * 40
	proj.direction = dir
	proj.speed = spell.projectile_speed
	proj.damage = spell.damage
	proj.damage_type = "spell"
	proj.interrupt_type = spell.interrupt_type
	proj.source = self
	proj.team_id = team_id
	proj.spell_data = spell
	get_tree().current_scene.add_child(proj)
	if proj.has_node("ColorRect"):
		proj.get_node("ColorRect").color = spell.projectile_color

func _fire_targeted_projectile(spell: SpellData, target: Node):
	var dir: Vector2 = (target.global_position - global_position).normalized()

	if spell.spell_scene:
		_spawn_spell_scene(spell, global_position + dir * 40, dir, target)
		return

	var proj = projectile_scene.instantiate()
	proj.global_position = _get_projectile_spawn_base() + dir * 40
	proj.direction = dir
	proj.speed = spell.projectile_speed
	proj.damage = spell.damage
	proj.damage_type = "spell"
	proj.interrupt_type = spell.interrupt_type
	proj.source = self
	proj.team_id = team_id
	proj.spell_data = spell
	get_tree().current_scene.add_child(proj)
	if proj.has_node("ColorRect"):
		proj.get_node("ColorRect").color = spell.projectile_color

## Spawn a spell's custom scene, passing it context for initialization.
func _spawn_spell_scene(spell: SpellData, pos: Vector2, dir: Vector2 = Vector2.RIGHT, target: Node = null):
	var entity = spell.spell_scene.instantiate()
	entity.global_position = pos

	# Set common fields if the scene supports them
	if "caster" in entity:
		entity.caster = self
	if "team_id" in entity:
		entity.team_id = team_id
	if "spell_data" in entity:
		entity.spell_data = spell
	# For projectile-type spell scenes
	if "direction" in entity:
		entity.direction = dir
	if "source" in entity:
		entity.source = self

	# Call initialize() with full context if available
	if entity.has_method("initialize"):
		var ctx := {
			ContextKeys.SOURCE: self,
			ContextKeys.CAST_DIRECTION: dir,
			ContextKeys.CAST_POSITION: pos,
			ContextKeys.TEAM_ID: team_id,
			ContextKeys.SPELL_DATA: spell,
		}
		if target:
			ctx[ContextKeys.CAST_TARGET] = target
		entity.initialize(ctx)

	get_tree().current_scene.add_child(entity)

func _find_target_near_cursor() -> Node:
	var mouse_pos := get_global_mouse_position()
	var nearest: Node = null
	var nearest_dist := 200.0  # Max targeting range from cursor

	# Search all bodies that can take damage
	for body in get_tree().get_nodes_in_group("enemy"):
		var dist := mouse_pos.distance_to(body.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = body

	# Also check training dummies
	for body in get_tree().get_nodes_in_group("training_dummy"):
		var dist := mouse_pos.distance_to(body.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = body

	return nearest

# ---- Placement Mode ----

func handle_placement_mode():
	if not is_placing:
		return

	if queued_spell_index < 0 or queued_spell_index >= spell_slots.size():
		is_placing = false
		return

	var spell := spell_slots[queued_spell_index]
	if spell == null or spell.cast_type != "placement":
		is_placing = false
		return

	if not placement_locked:
		# Phase 1: cursor sets position
		placement_position = get_global_mouse_position()

		if Input.is_action_just_pressed("light_attack"):
			# Lock position, enter rotation phase
			placement_locked = true
			placement_rotation = 0.0
	else:
		# Phase 2: holding LMB — drag to rotate
		var delta_to_mouse := get_global_mouse_position() - placement_position
		placement_rotation = delta_to_mouse.angle()

		if Input.is_action_just_released("light_attack"):
			# Confirm placement — spend mana and spawn
			var spent := use_mana(spell.mana_cost, "spell_cast")
			if spent <= 0:
				# Not enough mana — cancel
				is_placing = false
				placement_locked = false
				queued_spell_index = -1
				return

			spell_cooldowns[queued_spell_index] = spell.cooldown

			# Spawn the spell entity at the placement location
			if spell.spell_scene:
				var entity = spell.spell_scene.instantiate()
				entity.global_position = placement_position
				entity.rotation = placement_rotation
				if "caster" in entity:
					entity.caster = self
				if "team_id" in entity:
					entity.team_id = team_id
				if "spell_data" in entity:
					entity.spell_data = spell
				if entity.has_method("initialize"):
					entity.initialize({
						ContextKeys.SOURCE: self,
						ContextKeys.CAST_POSITION: placement_position,
						ContextKeys.CAST_ROTATION: placement_rotation,
						ContextKeys.TEAM_ID: team_id,
						ContextKeys.SPELL_DATA: spell,
					})
				get_tree().current_scene.add_child(entity)

			if debug_hud:
				debug_hud.log_action("[color=violet]Placed: %s[/color]" % spell.spell_name, -spent)

			# Clean up placement state
			is_placing = false
			placement_locked = false
			queued_spell_index = -1

	# Cancel with Q or pressing the same spell key
	if Input.is_action_just_pressed("cancel_cast"):
		_cancel_placement()

	queue_redraw()

func _cancel_placement():
	is_placing = false
	placement_locked = false
	queued_spell_index = -1
	if debug_hud:
		debug_hud.log_action("[color=gray]Placement cancelled[/color]")

# ---- Passive Skill ----

func _load_passive():
	# Remove existing passive if any
	if _passive:
		_passive.queue_free()
		_passive = null

	if stats and stats.passive_scene:
		var instance = stats.passive_scene.instantiate()
		if instance is PassiveSkill:
			_passive = instance
			add_child(_passive)
			_passive.initialize(self)

# ---- Draw (aim line) ----

func _draw():
	# Placement mode preview
	if is_placing:
		var local_pos := placement_position - global_position
		if not placement_locked:
			# Show crosshair at cursor
			draw_circle(local_pos, 8.0, Color(0.3, 1.0, 0.6, 0.6))
			draw_arc(local_pos, 12.0, 0, TAU, 16, Color(0.3, 1.0, 0.6, 0.3), 2.0)
		else:
			# Show locked position + rotation indicator
			draw_circle(local_pos, 6.0, Color(1.0, 0.8, 0.2, 0.8))
			var rot_end := local_pos + Vector2.from_angle(placement_rotation) * 40
			draw_line(local_pos, rot_end, Color(1.0, 0.8, 0.2, 0.8), 2.0)
		return

	if is_in_ranged_mode or queued_spell_index >= 0:
		var origin_g := _get_projectile_spawn_base()          # global spawn origin (same as projectiles)
		var origin_l := origin_g - global_position            # convert to local space for _draw()

		var dir := (get_global_mouse_position() - origin_g).normalized()
		var aim_end := origin_l + dir * 120

		var line_color: Color
		if is_in_ranged_mode:
			var mode := _get_effective_ranged_mode()
			line_color = Color(mode.projectile_color, 0.5)
		else:
			line_color = Color(0.6, 0.3, 1.0, 0.5)

		draw_line(origin_l, aim_end, line_color, 2.0)
