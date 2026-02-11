## ============================================================================
## PLAYER.GD — INTEGRATION SNIPPET (COMPLETE)
## ============================================================================
## Replace / merge these sections into your existing player.gd.
## This is NOT a standalone file — it shows the specific functions to update.
## ============================================================================


# ========================================================================
# SECTION 1: NEW VARIABLES (add near the top, with other var declarations)
# ========================================================================

## Track previous weapon pose to detect changes
var _current_weapon_pose: WeaponPoseData = null


# ========================================================================
# SECTION 2: RIG LOADING (call from _ready, after stats initialization)
# ========================================================================

func _load_character_rig() -> void:
	"""Load the character-specific rig scene from stats, or keep default."""
	if stats and stats.rig_scene:
		if crayola_rig:
			crayola_rig.queue_free()
		crayola_rig = stats.rig_scene.instantiate()
		add_child(crayola_rig)

	# Connect rig signals
	if crayola_rig:
		if not crayola_rig.sequence_step_changed.is_connected(_on_sequence_step_changed):
			crayola_rig.sequence_step_changed.connect(_on_sequence_step_changed)
		if not crayola_rig.anim_event.is_connected(_on_rig_anim_event):
			crayola_rig.anim_event.connect(_on_rig_anim_event)
		if not crayola_rig.melee_hitbox_requested.is_connected(_on_melee_hitbox_requested):
			crayola_rig.melee_hitbox_requested.connect(_on_melee_hitbox_requested)


# ========================================================================
# SECTION 3: WEAPON POSE RESOLUTION + ARM UPDATE (replace update_arms)
# ========================================================================

func update_arms() -> void:
	if not crayola_rig:
		return

	crayola_rig.set_facing_right(not animated_sprite.flip_h)

	# ---- Resolve active weapon pose (priority: spell > ranged > default) ----
	var pose: WeaponPoseData = null

	if queued_spell_index >= 0 and queued_spell_index < spell_slots.size():
		var spell := spell_slots[queued_spell_index]
		if spell and spell.weapon_pose:
			pose = spell.weapon_pose

	if pose == null and is_in_ranged_mode:
		var rm := stats.ranged_mode if stats and stats.ranged_mode else _default_ranged_mode
		if rm.weapon_pose:
			pose = rm.weapon_pose

	if pose == null and stats:
		pose = stats.default_weapon_pose

	# ---- Apply weapon state only on change ----
	if pose != _current_weapon_pose:
		crayola_rig.apply_weapon_state(pose)
		_current_weapon_pose = pose

	# ---- Update aim tracking ----
	var should_aim := arm_override_active and pose != null
	if should_aim:
		var flags := crayola_rig.get_current_aim_flags()
		if flags > 0:
			crayola_rig.update_arm_aim(true, get_global_mouse_position())
			return

	crayola_rig.update_arm_aim(false, Vector2.ZERO)


# ========================================================================
# SECTION 4: MELEE ATTACK ANIMATION HOOKS (update perform_light/heavy_attack)
# ========================================================================

## Updated perform_light_attack — plays rig animation if MeleeAttackData exists.
func perform_light_attack():
	is_attacking = true
	is_heavy_attack = false
	combo_count += 1
	hit_bodies_this_attack.clear()
	landed_flinch_this_attack = false

	# Determine which attack data to use (combo second hit vs first)
	var attack_data: MeleeAttackData = null
	if stats:
		if combo_count >= 2 and stats.combo_light_attack_data:
			attack_data = stats.combo_light_attack_data
		elif stats.light_attack_data:
			attack_data = stats.light_attack_data

	# Use attack data duration if available, otherwise fall back to stats
	if attack_data:
		attack_timer = attack_data.duration
		if crayola_rig:
			crayola_rig.play_melee_attack(attack_data)
		# If using anim events, DON'T enable hitbox here — anim will trigger it
		if not attack_data.use_anim_events:
			melee_collision.disabled = false
	else:
		attack_timer = stats.light_attack_duration
		melee_collision.disabled = false

	if debug_hud:
		var combo_text = " #%d" % combo_count if combo_count > 1 else ""
		debug_hud.log_action("[color=cyan]Light Attack%s[/color]" % combo_text)


## Updated perform_heavy_attack — plays rig animation if MeleeAttackData exists.
func perform_heavy_attack():
	is_attacking = true
	is_heavy_attack = true
	hit_bodies_this_attack.clear()

	var attack_data: MeleeAttackData = null
	if stats:
		attack_data = stats.heavy_attack_data

	if attack_data:
		attack_timer = attack_data.duration
		if crayola_rig:
			crayola_rig.play_melee_attack(attack_data)
		if not attack_data.use_anim_events:
			melee_collision.disabled = false
	else:
		attack_timer = stats.heavy_attack_duration
		melee_collision.disabled = false

	if debug_hud:
		debug_hud.log_action("Heavy Attack")


## Updated end_attack — notify rig.
func end_attack():
	is_attacking = false
	melee_collision.disabled = true

	if crayola_rig:
		crayola_rig.end_melee_attack()

	# Existing combo logic remains unchanged below...
	if combo_count == 1 and not is_heavy_attack and landed_flinch_this_attack:
		can_combo = true
		combo_window_timer = 0.5
		if debug_hud:
			debug_hud.log_action("[color=lime]Combo available![/color]")
	elif combo_count >= 2 or is_heavy_attack:
		combo_count = 0
		can_combo = false
		combo_window_timer = 0.0
		melee_cooldown_timer = MELEE_COOLDOWN_DURATION

	is_heavy_attack = false


# ========================================================================
# SECTION 5: ANIM EVENT TIMER CHECK (add to handle_attack_timers)
# ========================================================================

## Add this block inside handle_attack_timers, inside the `if is_attacking:` block,
## BEFORE the `if attack_timer <= 0:` check:
##
##   # Anim-event-free hitbox timing (for attacks without method call tracks)
##   if crayola_rig and crayola_rig.get_active_melee_attack():
##       var elapsed := (crayola_rig.get_active_melee_attack().duration - attack_timer)
##       var should_be_active := crayola_rig.should_hitbox_be_active(elapsed)
##       melee_collision.disabled = not should_be_active


# ========================================================================
# SECTION 6: SIGNAL CALLBACKS
# ========================================================================

func _on_sequence_step_changed(step_index: int, step: ArmSequenceStep) -> void:
	"""Hook for gameplay events triggered by arm sequence changes.
	e.g., Spatchcock could spawn/despawn flintlock VFX here."""
	pass


func _on_rig_anim_event(event_name: String) -> void:
	"""React to animation events from the rig.
	Standard events are handled by the rig internally (hitbox_on/off).
	Add custom handling here for character-specific events."""
	match event_name:
		"impact":
			# Use the EffectManager for hit feedback
			var attack_data := crayola_rig.get_active_melee_attack() if crayola_rig else null
			if attack_data and attack_data.effect_profile:
				Effects.play_profile(attack_data.effect_profile, global_position)
			else:
				Effects.screen_shake(4.0, 0.1)
		"spawn_vfx":
			# Spawn VFX at weapon's effect anchor
			pass
		"play_sfx":
			# Play sound effect
			pass
		"step_left", "step_right":
			# Footstep sounds
			pass


func _on_melee_hitbox_requested(active: bool) -> void:
	"""Called when an animation event toggles the hitbox.
	Only fires for attacks with use_anim_events = true."""
	if is_attacking:
		melee_collision.disabled = not active


# ========================================================================
# SECTION 7: EFFECT MANAGER INTEGRATION (update take_damage and melee hit)
# ========================================================================

## In take_damage(), REPLACE the _flash_damage() call with:
##
##   # Hit feedback via EffectManager
##   var strength := "heavy" if interrupt_type == "stagger" else "light"
##   if Effects:
##       Effects.hit_feedback(animated_sprite if animated_sprite else self, global_position, strength)
##
## In _on_melee_hitbox_body_entered(), AFTER hit_body.take_damage(), ADD:
##
##   # Play hit effects
##   if Effects:
##       var attack_data: MeleeAttackData = null
##       if stats:
##           attack_data = stats.heavy_attack_data if is_heavy_attack else stats.light_attack_data
##       if attack_data and attack_data.effect_profile:
##           Effects.play_profile(attack_data.effect_profile, hit_body.global_position)
##       else:
##           Effects.play_hit(hit_body.global_position, "melee", "heavy" if is_heavy_attack else "light")
##
## You can then DELETE the _flash_damage() function entirely — EffectManager handles it.


# ========================================================================
# SECTION 8: STATE MACHINE SETUP (Phase 1 — alongside existing code)
# ========================================================================

## To add the state machine without breaking anything:
##
## 1. Add a PlayerStateMachine node as child of the Player scene
##
## 2. In _ready(), after existing setup:
##
##   var machine: PlayerStateMachine = $PlayerStateMachine
##   machine.initialize(self, {
##       "Idle": IdleState.new(),
##       "Walking": WalkingState.new(),
##       "Airborne": AirborneState.new(),
##       "Dashing": DashingState.new(),
##       "Attacking": AttackingState.new(),
##       "Blocking": BlockingState.new(),
##       "Coalescing": CoalescingState.new(),
##       "Casting": CastingState.new(),
##       "Stunned": StunnedState.new(),
##       "Dead": DeadState.new(),
##       "WallCling": WallClingState.new(),
##       "LedgeGrab": LedgeGrabState.new(),
##       "RangedMode": RangedModeState.new(),
##       "Placing": PlacingState.new(),
##   }, "Idle")
##
## 3. Hook the state_changed signal for debug HUD:
##
##   machine.state_changed.connect(func(old_state, new_state):
##       if debug_hud:
##           debug_hud.update_custom("State", new_state)
##   )
##
## 4. In take_damage(), force transition to Stunned:
##
##   machine.transition_to("Stunned")
##
## 5. See example_states.gd for the incremental migration strategy.
##    Start with "Legacy" state that runs all existing code, then extract one at a time.


# ========================================================================
# SECTION 9: RANGED FIRE SEQUENCE ADVANCE
# ========================================================================

## In your ranged fire logic, after spawning the projectile, add:
##
##   if crayola_rig:
##       crayola_rig.advance_sequence()
##
## This drives Spatchcock's alternating flintlock behavior.


# ========================================================================
# SECTION 10: PROJECTILE SPAWN POSITION FROM WEAPON
# ========================================================================

## Update your projectile spawn logic to use the weapon's muzzle point:
##
##   var spawn_pos: Vector2
##   if crayola_rig:
##       spawn_pos = crayola_rig.get_projectile_spawn_position()
##   else:
##       spawn_pos = global_position + projectile_spawn_offset


# ========================================================================
# SECTION 11: SET_CHARACTER_STATS UPDATE
# ========================================================================

## At the end of your existing set_character_stats() function, add:
##
##   _load_character_rig()
##   _current_weapon_pose = null  # Force re-evaluation of weapon state
