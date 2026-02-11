# ManaBrawl — player.gd Wiring Guide
# Every addition below is commented out and safe to paste.
# Uncomment when the relevant system is ready to use.


# ============================================================
# LOCATION 1: Near top of file, with your other var declarations
# (after the "var current_body_anim" / "var arm_override_active" lines)
# ============================================================

## var _current_weapon_pose: WeaponPoseData = null


# ============================================================
# LOCATION 2: End of _ready(), after the wall_check_right error check
# ============================================================

##	_load_character_rig()


# ============================================================
# LOCATION 3: New function — paste anywhere in the file as a new function
# (recommended: near update_arms)
# ============================================================

#func _load_character_rig() -> void:
#	if stats and stats.rig_scene:
#		if crayola_rig:
#			crayola_rig.queue_free()
#		crayola_rig = stats.rig_scene.instantiate()
#		add_child(crayola_rig)
#
#	if crayola_rig:
#		if not crayola_rig.sequence_step_changed.is_connected(_on_sequence_step_changed):
#			crayola_rig.sequence_step_changed.connect(_on_sequence_step_changed)
#		if not crayola_rig.anim_event.is_connected(_on_rig_anim_event):
#			crayola_rig.anim_event.connect(_on_rig_anim_event)
#		if not crayola_rig.melee_hitbox_requested.is_connected(_on_melee_hitbox_requested):
#			crayola_rig.melee_hitbox_requested.connect(_on_melee_hitbox_requested)


# ============================================================
# LOCATION 4: REPLACE your existing update_arms() function entirely
# (the one that currently calls crayola_rig.update_arm_pose)
# ============================================================

#func update_arms() -> void:
#	if not crayola_rig:
#		return
#
#	crayola_rig.set_facing_right(not animated_sprite.flip_h)
#
#	# Resolve active weapon pose (priority: spell > ranged > default)
#	var pose: WeaponPoseData = null
#
#	if queued_spell_index >= 0 and queued_spell_index < spell_slots.size():
#		var spell := spell_slots[queued_spell_index]
#		if spell and spell.weapon_pose:
#			pose = spell.weapon_pose
#
#	if pose == null and is_in_ranged_mode:
#		var rm := stats.ranged_mode if stats and stats.ranged_mode else _default_ranged_mode
#		if rm.weapon_pose:
#			pose = rm.weapon_pose
#
#	if pose == null and stats:
#		pose = stats.default_weapon_pose
#
#	# Apply weapon state only on change
#	if pose != _current_weapon_pose:
#		crayola_rig.apply_weapon_state(pose)
#		_current_weapon_pose = pose
#
#	# Update aim tracking
#	var should_aim := arm_override_active and pose != null
#	if should_aim:
#		var flags := crayola_rig.get_current_aim_flags()
#		if flags > 0:
#			crayola_rig.update_arm_aim(true, get_global_mouse_position())
#			return
#
#	crayola_rig.update_arm_aim(false, Vector2.ZERO)


# ============================================================
# LOCATION 5: Inside perform_light_attack(), AFTER the existing
#   "melee_collision.disabled = false" line, ADD:
# ============================================================

#	# --- Rig melee animation hook ---
#	#var attack_data: MeleeAttackData = null
#	#if stats:
#	#	if combo_count >= 2 and stats.combo_light_attack_data:
#	#		attack_data = stats.combo_light_attack_data
#	#	elif stats.light_attack_data:
#	#		attack_data = stats.light_attack_data
#	#if attack_data and crayola_rig:
#	#	crayola_rig.play_melee_attack(attack_data)


# ============================================================
# LOCATION 6: Inside perform_heavy_attack(), AFTER the existing
#   "melee_collision.disabled = false" line, ADD:
# ============================================================

#	# --- Rig melee animation hook ---
#	#var attack_data: MeleeAttackData = null
#	#if stats:
#	#	attack_data = stats.heavy_attack_data
#	#if attack_data and crayola_rig:
#	#	crayola_rig.play_melee_attack(attack_data)


# ============================================================
# LOCATION 7: Inside end_attack(), RIGHT AFTER the
#   "melee_collision.disabled = true" line, ADD:
# ============================================================

#	#if crayola_rig:
#	#	crayola_rig.end_melee_attack()


# ============================================================
# LOCATION 8: Inside handle_attack_timers(), inside the
#   "if is_attacking:" block, BEFORE "if attack_timer <= 0:", ADD:
# ============================================================

#		# --- Anim-driven hitbox timing ---
#		#if crayola_rig and crayola_rig.get_active_melee_attack():
#		#	var elapsed := (crayola_rig.get_active_melee_attack().duration - attack_timer)
#		#	var should_be_active := crayola_rig.should_hitbox_be_active(elapsed)
#		#	melee_collision.disabled = not should_be_active


# ============================================================
# LOCATION 9: Inside take_damage(), REPLACE the line:
#   _flash_damage()
# with:
# ============================================================

#	# --- EffectManager hit feedback ---
#	#var strength := "heavy" if interrupt_type == "stagger" else "light"
#	#if Effects:
#	#	Effects.hit_feedback(animated_sprite if animated_sprite else self, global_position, strength)


# ============================================================
# LOCATION 10: Inside _on_melee_hitbox_body_entered(),
#   AFTER the "hit_body.take_damage(...)" line, ADD:
# ============================================================

#	# --- EffectManager hit effects ---
#	#if Effects:
#	#	var attack_data: MeleeAttackData = null
#	#	if stats:
#	#		attack_data = stats.heavy_attack_data if is_heavy_attack else stats.light_attack_data
#	#	if attack_data and attack_data.effect_profile:
#	#		Effects.play_profile(attack_data.effect_profile, hit_body.global_position)
#	#	else:
#	#		Effects.play_hit(hit_body.global_position, "melee", "heavy" if is_heavy_attack else "light")


# ============================================================
# LOCATION 11: Inside fire_projectile(), AFTER the line:
#   get_tree().current_scene.add_child(proj)
# ADD:
# ============================================================

#	# --- Arm sequence advance (Spatchcock flintlock swap) ---
#	#if crayola_rig:
#	#	crayola_rig.advance_sequence()


# ============================================================
# LOCATION 12: REPLACE the _get_projectile_spawn_base() function with:
# (or add as an alternative alongside the existing one)
# ============================================================

#func _get_projectile_spawn_base() -> Vector2:
#	# Use weapon muzzle point if available, else default offset
#	#if crayola_rig:
#	#	return crayola_rig.get_projectile_spawn_position()
#	return global_position + projectile_spawn_offset


# ============================================================
# LOCATION 13: At the END of set_character_stats(), after the
#   "_load_passive()" call and status_effects.clear_all(), ADD:
# ============================================================

	_load_character_rig()
	_current_weapon_pose = null  # Force re-evaluation on next update_arms


# ============================================================
# LOCATION 14: New signal callbacks — paste as new functions
#   anywhere in the file (recommended: near update_arms)
# ============================================================

#func _on_sequence_step_changed(step_index: int, step: ArmSequenceStep) -> void:
#	# Hook for Spatchcock flintlock swap VFX, etc.
#	pass

#func _on_rig_anim_event(event_name: String) -> void:
#	# React to animation events from the rig
#	#match event_name:
#	#	"impact":
#	#		var attack_data := crayola_rig.get_active_melee_attack() if crayola_rig else null
#	#		if attack_data and attack_data.effect_profile:
#	#			Effects.play_profile(attack_data.effect_profile, global_position)
#	#		else:
#	#			Effects.screen_shake(4.0, 0.1)
#	#	"step_left", "step_right":
#	#		pass  # Footstep sounds
#	pass

#func _on_melee_hitbox_requested(active: bool) -> void:
#	# Called by anim event hitbox_on/hitbox_off
#	#if is_attacking:
#	#	melee_collision.disabled = not active
#	pass


# ============================================================
# LOCATION 15: State machine setup (DO NOT uncomment until all
#   state classes exist — see example_states.gd)
# ============================================================

# In _ready(), after _load_character_rig():
#
#	#var machine: PlayerStateMachine = $PlayerStateMachine
#	#machine.initialize(self, {
#	#	"Idle": IdleState.new(),
#	#	# ... add states as you create them ...
#	#}, "Idle")
#	#
#	#machine.state_changed.connect(func(old_state, new_state):
#	#	if debug_hud:
#	#		debug_hud.update_custom("State", new_state)
#	#)

# In take_damage(), after applying flinch/stagger:
#	#if machine:
#	#	machine.transition_to("Stunned")
