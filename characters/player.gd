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
var combo_window: bool = false
var combo_count: int = 0
var hit_bodies_this_attack: Array = []
var combo_window_timer: float = 0.0
var can_combo: bool = false
var landed_flinch_this_attack: bool = false
var melee_cooldown_timer: float = 0.0  # Prevents attack spam after combo
const MELEE_COOLDOWN_DURATION: float = 0.4

## Physics
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	# Initialize from stats
	if stats:
		current_health = stats.max_health
		current_mana = stats.max_mana
	else:
		push_error("No CharacterStats assigned to Player!")
	
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
	
	# --- Attunements init ---
	attunements = AttunementManager.new()
	add_child(attunements)
	attunements.initialize(self)
	attunements.set_slot_attunement(0, starting_attunement)
	
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

	# --- Stunned: no actions, just slide to a stop ---
	var is_stunned := is_flinched or is_staggered
	if is_stunned:
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0.0, 0.15)
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

	handle_attack_input()

	# Movement: not while dashing, wall jump locked, coalescing, recovering, attacking, or blocking
	if not is_dashing and wall_jump_lock_timer <= 0 and not is_coalescing and coalescence_recovery_timer <= 0 and not is_attacking:
		handle_movement(delta)

	regenerate_mana(delta)
	move_and_slide()
	update_hud()
	update_facing_direction()
	update_animation()

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

	# Apply attunement move speed multiplier
	if attunements:
		target_speed *= attunements.get_move_speed_mult()

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
	elif is_dashing:
		state = "DASHING"
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

		var ctx := {"dir": dash_direction, "airborne": not is_on_floor(), "mana_spent": spent}
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
	# Can't attack while coalescing, dashing, recovery, blocking, or on melee cooldown
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
	var target_is_attacking := hit_body.get("is_attacking") == true
	if target_is_attacking:
		var target_is_heavy := hit_body.get("is_heavy_attack") == true
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
	var target_is_blocking := hit_body.get("is_blocking") == true if hit_body.get("is_blocking") != null else false

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
	stun_timer = 0.0
	melee_collision.disabled = true
	
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
	
	# Visual feedback
	if animated_sprite:
		animated_sprite.modulate = Color.WHITE
	
	if debug_hud:
		debug_hud.log_action("[color=lime]Respawned![/color]")
