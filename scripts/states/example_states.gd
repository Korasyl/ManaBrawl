## ============================================================================
## PLAYER STATE IMPLEMENTATIONS — MIGRATION REFERENCE
## ============================================================================
## These are example state classes showing how to extract logic from the
## current boolean-flag-based player.gd into discrete states.
##
## You DON'T need to implement all states at once. Migrate incrementally:
## 1. Start with the state machine + IdleState + a catch-all "Legacy" state
## 2. Extract one state at a time (Dashing is a good first candidate — it's simple)
## 3. Each extraction removes booleans and if-guards from player.gd
##
## FILE ORGANIZATION:
## You can put all states in one file or split them into separate files:
##   scripts/states/idle_state.gd
##   scripts/states/walking_state.gd
##   scripts/states/airborne_state.gd
##   etc.
## ============================================================================


# ========================================================================
# IDLE STATE — Standing on ground, no actions
# ========================================================================

class_name IdleState
extends PlayerState

func enter(prev_state: String) -> void:
	# Cancel any leftover velocities from previous states
	player.is_attacking = false
	player.is_dashing = false
	player.is_coalescing = false
	player.is_blocking = false

func handle_input() -> String:
	# Priority-ordered transition checks
	if player.is_dead:
		return "Dead"

	if Input.is_action_just_pressed("dash") and player.current_mana >= player.stats.dash_cost:
		return "Dashing"

	if Input.is_action_pressed("block") and not player.block_broken:
		return "Blocking"

	if Input.is_action_pressed("coalesce"):
		return "Coalescing"

	if player.queued_spell_index >= 0 and player.is_placing:
		return "Placing"

	if player.queued_spell_index >= 0 or player.is_in_ranged_mode:
		return "RangedMode"

	if Input.is_action_just_released("light_attack"):
		return "Attacking"

	if not player.is_on_floor():
		return "Airborne"

	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir != 0:
		return "Walking"

	return ""

func process(delta: float) -> String:
	# Gravity if somehow not on floor
	if not player.is_on_floor():
		return "Airborne"

	# Handle crouch (stays in Idle but crouching)
	player.is_crouching = Input.is_action_pressed("crouch")
	player.is_crouchwalking = false
	player.is_sprinting = false

	player.handle_crouch_boost(delta)
	player.regenerate_mana(delta)
	player.move_and_slide()

	return ""


## ========================================================================
## WALKING STATE — Moving on ground
## ========================================================================
##
## class_name WalkingState
## extends PlayerState
##
## func enter(prev_state: String) -> void:
##     pass
##
## func handle_input() -> String:
##     if player.is_dead:
##         return "Dead"
##     if Input.is_action_just_pressed("dash") and player.current_mana >= player.stats.dash_cost:
##         return "Dashing"
##     if Input.is_action_pressed("block") and not player.block_broken:
##         return "Blocking"
##     if Input.is_action_just_pressed("jump"):
##         return "Airborne"  # After applying jump velocity
##     if not player.is_on_floor():
##         return "Airborne"
##     var input_dir := Input.get_axis("move_left", "move_right")
##     if input_dir == 0:
##         return "Idle"
##     return ""
##
## func process(delta: float) -> String:
##     player.handle_movement(delta)
##     player.regenerate_mana(delta)
##     player.move_and_slide()
##     return ""


## ========================================================================
## DASHING STATE — i-frames, fixed velocity, timer-based
## ========================================================================
##
## class_name DashingState
## extends PlayerState
##
## var dash_timer: float = 0.0
##
## func enter(prev_state: String) -> void:
##     player.is_dashing = true
##     dash_timer = player.movement_data.dash_duration if player.movement_data else 0.2
##     var dir := -1 if player.animated_sprite.flip_h else 1
##     player.velocity = Vector2(dir * (player.movement_data.dash_speed if player.movement_data else 500), 0)
##     player.use_mana(player.stats.dash_cost, "dash")
##
## func exit(next_state: String) -> void:
##     player.is_dashing = false
##
## func process(delta: float) -> String:
##     dash_timer -= delta
##     if dash_timer <= 0:
##         if player.is_on_floor():
##             return "Idle"
##         return "Airborne"
##     player.move_and_slide()
##     return ""


## ========================================================================
## ATTACKING STATE — Melee light/heavy with combo tracking
## ========================================================================
##
## class_name AttackingState
## extends PlayerState
##
## func enter(prev_state: String) -> void:
##     # Determine light vs heavy from charge timer
##     if player.heavy_charge_timer >= player.stats.heavy_attack_charge_time:
##         player.perform_heavy_attack()
##     else:
##         player.perform_light_attack()
##
## func exit(next_state: String) -> void:
##     player.end_attack()
##
## func handle_input() -> String:
##     # Can't cancel attacks with most actions
##     # But dash can cancel (GDD: dash out of flinch)
##     if Input.is_action_just_pressed("dash") and player.current_mana >= player.stats.dash_cost:
##         return "Dashing"
##     return ""
##
## func process(delta: float) -> String:
##     player.attack_timer -= delta
##
##     # Anim-event hitbox timing
##     if player.crayola_rig and player.crayola_rig.get_active_melee_attack():
##         var elapsed := player.crayola_rig.get_active_melee_attack().duration - player.attack_timer
##         var active := player.crayola_rig.should_hitbox_be_active(elapsed)
##         player.melee_collision.disabled = not active
##
##     if player.attack_timer <= 0:
##         # Attack finished — check for combo window
##         if player.can_combo:
##             return "Idle"  # Idle handles next combo input
##         return "Idle"
##
##     # Still apply gravity
##     if not player.is_on_floor():
##         player.velocity.y += player.gravity * delta
##     player.move_and_slide()
##     return ""


## ========================================================================
## STUNNED STATE — Flinch or Stagger hitstun
## ========================================================================
##
## class_name StunnedState
## extends PlayerState
##
## func enter(prev_state: String) -> void:
##     # Stun state is entered via machine.transition_to("Stunned") from take_damage
##     pass
##
## func process(delta: float) -> String:
##     player.stun_timer -= delta
##
##     # Slide to stop on ground
##     if player.is_on_floor():
##         player.velocity.x = move_toward(player.velocity.x, 0.0,
##             player.movement_data.ground_deceleration * delta)
##     else:
##         player.velocity.y += player.gravity * delta
##
##     player.move_and_slide()
##
##     if player.stun_timer <= 0:
##         player.is_flinched = false
##         player.is_staggered = false
##         if player.is_on_floor():
##             return "Idle"
##         return "Airborne"
##
##     return ""


## ========================================================================
## DEAD STATE — Waiting for respawn
## ========================================================================
##
## class_name DeadState
## extends PlayerState
##
## func enter(prev_state: String) -> void:
##     player.die()  # Sets is_dead, cancels everything, visual feedback
##
## func process(delta: float) -> String:
##     player.respawn_timer -= delta
##     if player.respawn_timer <= 0:
##         player.respawn()
##         return "Idle"
##     return ""


## ========================================================================
## MIGRATION STRATEGY
## ========================================================================
##
## Phase 1: Add the state machine alongside existing code
##   - Add PlayerStateMachine as a child of Player
##   - Create a "Legacy" state that just calls all existing player logic
##   - Machine starts in "Legacy" — everything works exactly as before
##
## Phase 2: Extract simple states first
##   - Dashing (self-contained timer, clear entry/exit)
##   - Dead (simple timer, no input)
##   - Stunned (simple timer, no input)
##   - Each extraction removes a boolean flag and its if-guards from player.gd
##
## Phase 3: Extract complex states
##   - Attacking (combo logic, hitbox timing)
##   - Coalescing (startup timer, regen multiplier)
##   - Blocking (mana drain, shield break vulnerability)
##   - RangedMode (aim direction, fire cooldown)
##
## Phase 4: Extract movement states
##   - Idle, Walking, Airborne, WallCling, LedgeGrab
##   - These are the most intertwined, save for last
##   - After this, player.gd becomes a thin shell: variable storage + state machine dispatch
##
## Each phase is a working game. No big-bang rewrite needed.
