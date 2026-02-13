extends Node2D
class_name CrayolaRig

## CrayolaRig — Base class for all character rigs.
##
## ARCHITECTURE:
## Each character subclasses or instances this with their own textures, proportions,
## and AnimationPlayer clips. The player script talks ONLY to this interface.
##
## ANIMATION LAYERS (via AnimationTree):
##   Layer 1: Body — legs, torso, head (driven by body_anim_player)
##   Layer 2: Front Arm — front upper arm + forearm (blended: animation OR code aim)
##   Layer 3: Back Arm — back upper arm + forearm (blended: animation OR code aim)
##   Layer 4: One-Shot — transitions, reactions, weapon draws (plays over everything)
##
## HOW TO CREATE A NEW CHARACTER RIG:
## 1. Create a new scene inheriting from CrayolaRig (or duplicate crayola_rig.tscn)
## 2. Replace sprite textures with character-specific art
## 3. Adjust pivot positions if body proportions differ
## 4. Create animations in the AnimationPlayer:
##    - REQUIRED body anims: idle, walk, walk_back, sprint, sprint_back, crouch,
##      crouchwalk, crouchwalk_back, jump, fall, hit, block, dash, wall_cling,
##      wall_slide, coalesce_ground, coalesce_air, coalesce_wall, ledge_grab,
##      ledge_clamber
##    - OPTIONAL arm anims: any pose referenced by WeaponPoseData
##      (e.g., hold_tome, brace_rifle, flintlock_hold, theatre_idle)
##    - OPTIONAL one-shots: draw_weapon, holster_weapon, toss_flintlock, etc.
## 5. Wire up the AnimationTree (see _setup_animation_tree)
## 6. Create WeaponPoseData resources and assign them to CharacterStats/SpellData/RangedModeData
##
## ANIMATION NAMING CONVENTION:
##   Body anims:       "idle", "walk", "sprint", "jump", etc.
##   Arm anims:        "arm_[description]" e.g., "arm_hold_tome", "arm_brace_rifle"
##   One-shot anims:   "oneshot_[description]" e.g., "oneshot_draw_flintlock"
##   Full override:    "full_[description]" e.g., "full_heavy_attack" (controls everything)

# ---- Configuration ----

@export var rig_scale: float = 2.0
@export var arm_lerp_speed: float = 18.0

## Minimum aim angle in local rig space (radians). Controls how far UP/BACK the arm can aim.
## Default -2.5 allows ~143° upward. Set to -PI for full backward reach.
@export var aim_angle_min: float = -2.5

## Maximum aim angle in local rig space (radians). Controls how far DOWN the arm can aim.
## Default 1.2 allows ~69° downward.
@export var aim_angle_max: float = 1.2

## How much the forearm bends relative to the upper arm during aim.
## e.g., 0.25 means the forearm adds 25% of the upper arm rotation.
## The arm solver compensates for this so the weapon tip aligns with the aim direction.
@export var forearm_aim_ratio: float = 0.25

## Maximum chest pivot tilt (radians) when the arm reaches its rotation limits.
## The upper body leans back/forward to extend aiming range at steep angles.
## Set to 0 to disable chest tilt entirely.
@export var chest_tilt_max: float = 0.5

## Downward screen-space compensation (pixels) applied while aiming.
## Positive values pull the arm aim slightly lower to align hand/muzzle with cursor.
@export var aim_vertical_compensation: float = 10.0

# ---- Internal State ----

var _current_body_anim: StringName = &"idle"
var _facing_right: bool = true
var _front_arm_angle: float = 0.0
var _back_arm_angle: float = 0.0

## Canonical aim direction (world-space, normalized). Shared by arm aiming,
## aim line, and projectile firing so they all agree. Computed from the rig's
## aim origin (chest) toward the cursor, clamped to the forward hemisphere.
var _current_aim_direction: Vector2 = Vector2.RIGHT
var _chest_tilt_angle: float = 0.0
var _chest_rest_rotation: float = 0.0
var _stomach_base_position: Vector2 = Vector2.ZERO
var _front_arm_rest_rotation: float = 0.0
var _back_arm_rest_rotation: float = 0.0
var _front_forearm_rest_rotation: float = 0.0
var _back_forearm_rest_rotation: float = 0.0

## Active weapon pose (set by player via apply_weapon_state)
var _active_weapon_pose: WeaponPoseData = null
var _current_weapon_node: Node2D = null
var _current_weapon_scene: PackedScene = null  # Tracks attached weapon scene to skip redundant re-creation

## Arm sequence state
var _sequence_index: int = 0
var _sequence_auto_timer: float = 0.0

## Blend state for arm code-vs-animation
var _front_arm_code_blend: float = 0.0  # 0 = animation, 1 = code aim
var _back_arm_code_blend: float = 0.0
var _blend_speed: float = 10.0

## Tracks the currently playing oneshot animation name (for signal filtering).
var _active_oneshot_anim: StringName = &""

# ---- Node References ----
# Subclasses can override these paths if their hierarchy differs.

@onready var stomach_pivot: Node2D = $StomachPivot
@onready var chest_pivot: Node2D = $StomachPivot/ChestPivot
@onready var back_arm_pivot: Node2D = $StomachPivot/ChestPivot/BackArmPivot
@onready var back_forearm: Node2D = $StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot
@onready var back_hand_sprite: Sprite2D = $StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot/BackHand
@onready var back_hand_weapon_anchor: Node2D = $StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot/BackHandWeaponAnchor if has_node("StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot/BackHandWeaponAnchor") else null
@onready var front_arm_pivot: Node2D = $StomachPivot/ChestPivot/FrontArmPivot
@onready var front_forearm: Node2D = $StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot
@onready var front_hand_sprite: Sprite2D = $StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot/FrontHand
@onready var front_hand_weapon_anchor: Node2D = $StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot/FrontHandWeaponAnchor if has_node("StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot/FrontHandWeaponAnchor") else null

## AnimationPlayer for body + arm clips. Add this node to your rig scene.
@onready var anim_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null

## Optional AnimationTree for advanced blending. If absent, falls back to direct anim_player calls.
@onready var anim_tree: AnimationTree = $AnimationTree if has_node("AnimationTree") else null

# ---- Animation Fallback ----

## Animations that all rigs MUST eventually have. If a requested animation is missing,
## the rig falls back to "idle" and prints a warning. This prevents crashes while
## building rigs incrementally.
const REQUIRED_BODY_ANIMS: Array[StringName] = [
	&"idle", &"walk", &"walk_back", &"sprint", &"sprint_back",
	&"crouch", &"crouchwalk", &"crouchwalk_back",
	&"jump", &"fall", &"hit", &"block", &"dash",
	&"wall_cling", &"wall_slide",
	&"coalesce_ground", &"coalesce_air", &"coalesce_wall",
	&"ledge_grab", &"ledge_clamber",
]

## Fallback animation when a requested one doesn't exist.
const FALLBACK_ANIM: StringName = &"idle"

## Track which missing animations have already been warned about to avoid log spam.
var _warned_missing_anims: Dictionary = {}

# ---- Melee Animation State ----

## Currently playing melee attack data (null when not attacking).
var _active_melee_attack: MeleeAttackData = null

## Whether the hitbox is currently active (driven by anim events or timers).
var _hitbox_active: bool = false

# ---- Signals ----

## Emitted when an arm sequence step advances (for gameplay hooks like spawning/despawning weapons).
signal sequence_step_changed(step_index: int, step: ArmSequenceStep)

## Emitted when a one-shot transition animation finishes.
signal transition_finished(anim_name: StringName)

## Emitted when an animation event fires (from AnimationPlayer method call tracks).
## event_name examples: "hitbox_on", "hitbox_off", "impact", "spawn_vfx", "play_sfx"
signal anim_event(event_name: String)

## Emitted when a melee attack animation wants the hitbox toggled.
signal melee_hitbox_requested(active: bool)

# ========================================================================
# PUBLIC INTERFACE — Called by player.gd
# ========================================================================

func _ready() -> void:
	_stomach_base_position = stomach_pivot.position
	_chest_rest_rotation = chest_pivot.rotation
	_front_arm_rest_rotation = front_arm_pivot.rotation
	_back_arm_rest_rotation = back_arm_pivot.rotation
	_front_forearm_rest_rotation = front_forearm.rotation
	_back_forearm_rest_rotation = back_forearm.rotation
	_front_arm_angle = _front_arm_rest_rotation
	_back_arm_angle = _back_arm_rest_rotation
	scale = Vector2.ONE * rig_scale
	_apply_pixel_settings(self)

	if anim_player and anim_player.has_signal("animation_finished"):
		anim_player.animation_finished.connect(_on_animation_finished)

func _process(delta: float) -> void:
	_process_sequence_auto_advance(delta)
	_process_arm_blending(delta)

## Set the body animation (legs, torso, head). Called every frame by player.
func set_body_animation(anim: StringName) -> void:
	if anim == _current_body_anim:
		return

	# Fallback: if animation doesn't exist, warn once and use idle
	var resolved_anim := _resolve_animation(anim)
	_current_body_anim = resolved_anim

	if anim_tree:
		# AnimationTree state machine handles transitions
		_set_tree_body_state(resolved_anim)
	elif anim_player and anim_player.has_animation(resolved_anim):
		anim_player.play(resolved_anim)

## Set facing direction. Flips rig via scale.x.
func set_facing_right(value: bool) -> void:
	if value == _facing_right:
		return
	_facing_right = value
	scale.x = abs(rig_scale) if _facing_right else -abs(rig_scale)

## Play a melee attack animation. Called by player on perform_light_attack / perform_heavy_attack.
## Returns false if the animation doesn't exist.
func play_melee_attack(attack_data: MeleeAttackData) -> bool:
	if attack_data == null:
		return false

	_active_melee_attack = attack_data

	# Apply weapon pose override if specified
	if attack_data.weapon_pose_override:
		apply_weapon_state(attack_data.weapon_pose_override)

	# Play the attack animation as a one-shot
	var anim_name := attack_data.animation_name
	if anim_player and anim_player.has_animation(anim_name):
		_play_oneshot(anim_name)

		# If NOT using anim events, set up timer-based hitbox activation
		# (the player handles the actual timer; we just report readiness)
		if not attack_data.use_anim_events:
			_hitbox_active = false

		return true
	else:
		_warn_missing_animation(anim_name)
		# Still allow the attack to proceed without animation
		_active_melee_attack = attack_data
		return false

## End the current melee attack (call when attack_timer expires).
func end_melee_attack() -> void:
	_active_melee_attack = null
	_hitbox_active = false

## Check if the hitbox should be active based on timer (for non-anim-event attacks).
## Call every frame during an active attack, passing elapsed time.
func should_hitbox_be_active(elapsed: float) -> bool:
	if _active_melee_attack == null:
		return false
	if _active_melee_attack.use_anim_events:
		return _hitbox_active  # Driven by anim events
	return elapsed >= _active_melee_attack.hitbox_active_start and \
		   elapsed < _active_melee_attack.hitbox_active_end

## Get the currently active melee attack data (or null).
func get_active_melee_attack() -> MeleeAttackData:
	return _active_melee_attack

# ---- Animation Event System ----

## Called by AnimationPlayer method call tracks.
## Add a "Call Method" track in your animation, targeting the rig node,
## calling `_on_anim_event` with a String argument.
##
## Standard event names:
##   "hitbox_on"    — Activate melee hitbox
##   "hitbox_off"   — Deactivate melee hitbox
##   "impact"       — Moment of impact (screen shake, particles)
##   "spawn_vfx"    — Spawn a visual effect
##   "play_sfx"     — Play a sound effect
##   "weapon_show"  — Make weapon sprite visible
##   "weapon_hide"  — Hide weapon sprite
##   "step_left"    — Left footstep (for walk cycle SFX)
##   "step_right"   — Right footstep
##
## You can use any custom string — it's emitted via the anim_event signal
## for external systems to react to.
func _on_anim_event(event_name: String) -> void:
	# Handle built-in events
	match event_name:
		"hitbox_on":
			_hitbox_active = true
			melee_hitbox_requested.emit(true)
		"hitbox_off":
			_hitbox_active = false
			melee_hitbox_requested.emit(false)
		"weapon_show":
			if _current_weapon_node:
				_current_weapon_node.visible = true
		"weapon_hide":
			if _current_weapon_node:
				_current_weapon_node.visible = false

	# Always emit the generic signal for custom handling
	anim_event.emit(event_name)

## Apply a weapon pose state. Determines which arms aim vs animate.
## Called by player when weapon/spell/ranged state changes.
func apply_weapon_state(pose: WeaponPoseData) -> void:
	var previous := _active_weapon_pose
	_active_weapon_pose = pose

	if pose == null:
		_front_arm_code_blend = 0.0
		_back_arm_code_blend = 0.0
		_detach_weapon()
		return

	# Play exit animation from previous state
	if previous and previous.exit_animation != &"":
		_play_oneshot(previous.exit_animation)

	# Reset sequence
	_sequence_index = 0
	_sequence_auto_timer = 0.0

	# Determine blend targets from flags (or first sequence step).
	# Auto-derive from weapon_hand when aim_arm_flags is 0 (None) so the
	# AnimationTree blend targets match which arm the rig will actually drive.
	var flags := _get_current_aim_flags()
	if flags == 0:
		flags = _derive_aim_flags_from_weapon_hand()
	_update_blend_targets(flags)

	# Set arm animations for non-tracking arms
	_apply_arm_animations(pose)

	# Blend speed from pose
	if pose.blend_in_time > 0:
		_blend_speed = 1.0 / pose.blend_in_time
	else:
		_blend_speed = 100.0  # Instant

	# Weapon attachment
	_attach_weapon(pose)

	# Play enter animation
	if pose.enter_animation != &"":
		_play_oneshot(pose.enter_animation)

## Update arm aiming. Call every frame AFTER apply_weapon_state.
## aim_active: whether any arm should be code-driven this frame.
## aim_world_pos: mouse position in world coordinates.
##
## This computes a single canonical aim direction from the rig's aim origin
## (chest pivot) toward the cursor, clamped to the forward hemisphere so the
## player can never fire backward. The arm rotation is solved so the weapon
## tip aligns with this direction (compensating for the forearm bend).
## Retrieve the result via get_aim_direction() for projectile/aim-line use.
func update_arm_aim(aim_active: bool, aim_world_pos: Vector2) -> void:
	if not aim_active:
		# No aiming — smoothly return to rest pose.
		_current_aim_direction = Vector2.RIGHT if _facing_right else Vector2.LEFT
		var reset_lerp := 0.20 * arm_lerp_speed / 18.0
		_front_arm_angle = lerp_angle(_front_arm_angle, _front_arm_rest_rotation, reset_lerp)
		_back_arm_angle = lerp_angle(_back_arm_angle, _back_arm_rest_rotation, reset_lerp)
		front_arm_pivot.rotation = _front_arm_angle
		back_arm_pivot.rotation = _back_arm_angle
		front_forearm.rotation = lerp_angle(front_forearm.rotation, _front_forearm_rest_rotation, reset_lerp)
		back_forearm.rotation = lerp_angle(back_forearm.rotation, _back_forearm_rest_rotation, reset_lerp)
		# Ease chest tilt back to neutral (rest rotation preserved for hunched rigs, etc.).
		_chest_tilt_angle = lerp(_chest_tilt_angle, 0.0, reset_lerp)
		chest_pivot.rotation = _chest_rest_rotation + _chest_tilt_angle
		_sync_weapon_rotation_to_hand()
		return

	# ---- 1. Compute canonical aim direction from aim origin to cursor ----
	var aim_origin := get_aim_origin()
	var compensated_aim := aim_world_pos + Vector2(0, aim_vertical_compensation)
	var raw_dir := compensated_aim - aim_origin
	var facing_sign := 1.0 if _facing_right else -1.0

	# Enforce minimum distance to avoid wild angles when cursor is on top of player.
	if raw_dir.length_squared() < 100.0:  # < 10px
		raw_dir = Vector2(facing_sign, 0.0)

	# ---- 2. Clamp to forward hemisphere (Starbound-style) ----
	if raw_dir.x * facing_sign < 0.0:
		raw_dir.x = 0.0
		if raw_dir.length_squared() < 1.0:
			raw_dir = Vector2(facing_sign, 0.0)

	var hemisphere_dir := raw_dir.normalized()

	# ---- 3. Convert to local arm angle ----
	var local_dir := hemisphere_dir
	if not _facing_right:
		local_dir.x = -local_dir.x

	# Unclamped desired angle for the weapon tip (forearm end) in rig-local space.
	var unclamped_desired := local_dir.angle() - PI / 2.0

	# ---- 4. Chest tilt — extend range when arm hits its limits ----
	var chest_tilt_target := 0.0
	if chest_tilt_max > 0.0:
		if unclamped_desired < aim_angle_min:
			# Aiming steeply up — lean the chest backward.
			chest_tilt_target = clampf(unclamped_desired - aim_angle_min, -chest_tilt_max, 0.0)
		elif unclamped_desired > aim_angle_max:
			# Aiming steeply down — lean the chest forward.
			chest_tilt_target = clampf(unclamped_desired - aim_angle_max, 0.0, chest_tilt_max)

	var lerp_factor := 0.15 * arm_lerp_speed / 18.0
	_chest_tilt_angle = lerp(_chest_tilt_angle, chest_tilt_target, lerp_factor)
	chest_pivot.rotation = _chest_rest_rotation + _chest_tilt_angle

	# ---- 5. Arm angle = remainder after chest tilt, with forearm compensation ----
	# The arm's desired angle is relative to the chest (its parent), so subtract
	# the chest tilt. Then clamp to the arm's own limits.
	var desired_angle := clampf(unclamped_desired - _chest_tilt_angle, aim_angle_min, aim_angle_max)

	# Solve for upper arm so total rotation (upper + forearm) hits desired_angle.
	var upper_angle := desired_angle / (1.0 + forearm_aim_ratio)

	# ---- 6. Compute the actual achievable direction and store it ----
	# This ensures the aim line and projectile match the weapon, with no deadzone.
	var actual_total := _chest_tilt_angle + desired_angle  # chest + arm contribution
	var actual_local := Vector2.from_angle(actual_total + PI / 2.0)
	if not _facing_right:
		actual_local.x = -actual_local.x
	_current_aim_direction = actual_local.normalized()

	# ---- 7. Apply to arms ----
	var flags := _get_current_aim_flags()
	if flags == 0:
		flags = _derive_aim_flags_from_weapon_hand()

	var weapon_hand := _get_current_weapon_hand()
	var both_handed := weapon_hand == "Both"
	var primary_is_front := true
	if both_handed and _active_weapon_pose:
		primary_is_front = (_active_weapon_pose.primary_hand == "Front")

	if both_handed and (flags & 3) == 3:
		# Both-handed + both arms aim: primary arm tracks cursor, secondary
		# arm reaches toward the weapon's SecondaryGrip marker.
		_apply_arm_aim(primary_is_front, upper_angle, lerp_factor)
		_sync_weapon_rotation_to_hand()
		var secondary_angle := _compute_secondary_grip_angle(primary_is_front, upper_angle)
		_apply_arm_aim(not primary_is_front, secondary_angle, lerp_factor)
	else:
		# Standard: all flagged arms aim at cursor.
		if flags & 1:
			_apply_arm_aim(true, upper_angle, lerp_factor)
		if flags & 2:
			_apply_arm_aim(false, upper_angle, lerp_factor)
		_sync_weapon_rotation_to_hand()

## Advance the arm sequence to the next step (call on fire, cooldown start, etc.)
func advance_sequence() -> void:
	if _active_weapon_pose == null or not _active_weapon_pose.use_arm_sequence:
		return
	if _active_weapon_pose.sequence_steps.is_empty():
		return

	_sequence_index = (_sequence_index + 1) % _active_weapon_pose.sequence_steps.size()
	var step := _active_weapon_pose.sequence_steps[_sequence_index]

	# Update blend targets
	_update_blend_targets(step.aim_arm_flags)

	# Update arm animations
	_apply_arm_animations_from_step(step)

	# Swap weapon hand if needed
	_update_weapon_hand(step.weapon_hand)

	# Play transition animation
	if step.transition_animation != &"":
		_play_oneshot(step.transition_animation)

	# Start auto-advance timer
	_sequence_auto_timer = step.auto_advance_time

	sequence_step_changed.emit(_sequence_index, step)

## Play a one-shot animation (overlays on top of everything).
## Use for attack windups, hit reactions, weapon flourishes.
func play_oneshot(anim_name: StringName) -> void:
	_play_oneshot(anim_name)

## Get the currently active aim flags (accounting for sequences).
func get_current_aim_flags() -> int:
	return _get_current_aim_flags()

## Get current sequence step index (-1 if not sequencing).
func get_sequence_index() -> int:
	if _active_weapon_pose and _active_weapon_pose.use_arm_sequence:
		return _sequence_index
	return -1

## Get the canonical aim direction (world-space, normalized).
## All systems (projectiles, aim line, arm visuals) should use this to stay in sync.
func get_aim_direction() -> Vector2:
	return _current_aim_direction

## Get the aim origin point (world-space). Used as the reference point for
## computing aim direction. Currently the chest pivot position.
func get_aim_origin() -> Vector2:
	return chest_pivot.global_position

# ========================================================================
# INTERNAL
# ========================================================================

func _derive_aim_flags_from_weapon_hand() -> int:
	var hand := _get_current_weapon_hand()
	match hand:
		"Front": return 1
		"Back": return 2
		"Both": return 3
	return 1  # Fallback: front arm

func _apply_arm_aim(is_front: bool, angle: float, lerp_factor: float) -> void:
	if is_front:
		_front_arm_angle = lerp_angle(_front_arm_angle, angle, lerp_factor)
		front_arm_pivot.rotation = _front_arm_angle
		front_forearm.rotation = _front_arm_angle * forearm_aim_ratio
	else:
		_back_arm_angle = lerp_angle(_back_arm_angle, angle, lerp_factor)
		back_arm_pivot.rotation = _back_arm_angle
		back_forearm.rotation = _back_arm_angle * forearm_aim_ratio

func _compute_secondary_grip_angle(primary_is_front: bool, primary_angle: float) -> float:
	var ws := get_weapon_sprite()
	if ws and ws.secondary_grip:
		var grip_pos := ws.secondary_grip.global_position
		var pivot: Node2D = back_arm_pivot if primary_is_front else front_arm_pivot
		var delta := grip_pos - pivot.global_position
		var local_delta := delta.rotated(-chest_pivot.global_rotation)
		var raw_angle := local_delta.angle() - PI / 2.0
		return clampf(raw_angle, aim_angle_min, aim_angle_max) / (1.0 + forearm_aim_ratio)
	# Fallback: offset from primary angle
	if _active_weapon_pose:
		return primary_angle + _active_weapon_pose.secondary_arm_offset
	return primary_angle

func _get_current_aim_flags() -> int:
	if _active_weapon_pose == null:
		return 0
	if _active_weapon_pose.use_arm_sequence and not _active_weapon_pose.sequence_steps.is_empty():
		var step := _active_weapon_pose.sequence_steps[_sequence_index]
		return step.aim_arm_flags
	return _active_weapon_pose.aim_arm_flags

func _update_blend_targets(flags: int) -> void:
	# Target blend: 1.0 = code drives, 0.0 = animation drives
	_front_arm_code_blend = 1.0 if (flags & 1) else 0.0
	_back_arm_code_blend = 1.0 if (flags & 2) else 0.0

func _process_arm_blending(delta: float) -> void:
	# Smooth blend between code and animation control
	# The actual blending is handled by the AnimationTree if present,
	# or by selectively overriding rotation after anim_player updates.
	if anim_tree:
		var front_current: float = anim_tree.get("parameters/front_arm_blend/blend_amount")
		var back_current: float = anim_tree.get("parameters/back_arm_blend/blend_amount")
		anim_tree.set("parameters/front_arm_blend/blend_amount",
			move_toward(front_current, _front_arm_code_blend, _blend_speed * delta))
		anim_tree.set("parameters/back_arm_blend/blend_amount",
			move_toward(back_current, _back_arm_code_blend, _blend_speed * delta))

func _process_sequence_auto_advance(delta: float) -> void:
	if _sequence_auto_timer > 0:
		_sequence_auto_timer -= delta
		if _sequence_auto_timer <= 0:
			advance_sequence()

func _apply_arm_animations(pose: WeaponPoseData) -> void:
	_set_arm_anims(pose.front_arm_animation, pose.back_arm_animation)

func _apply_arm_animations_from_step(step: ArmSequenceStep) -> void:
	_set_arm_anims(step.front_arm_animation, step.back_arm_animation)

func _set_arm_anims(front_anim: StringName, back_anim: StringName) -> void:
	if anim_tree:
		if front_anim != &"":
			anim_tree.set("parameters/front_arm_anim/animation", front_anim)
		if back_anim != &"":
			anim_tree.set("parameters/back_arm_anim/animation", back_anim)
	elif anim_player:
		# Fallback: play arm animations directly on the AnimationPlayer.
		# Non-aiming arms get their pose clip; aiming arms are code-driven.
		if back_anim != &"" and anim_player.has_animation(back_anim):
			anim_player.play(back_anim)
		elif front_anim != &"" and anim_player.has_animation(front_anim):
			anim_player.play(front_anim)

func _set_tree_body_state(anim: StringName) -> void:
	if anim_tree == null:
		return
	# For AnimationNodeStateMachine, travel to the state.
	# For BlendTree setups, set the animation parameter directly.
	var playback = anim_tree.get("parameters/body_state/playback")
	if playback and playback is AnimationNodeStateMachinePlayback:
		if anim_tree.tree_root and playback.is_playing():
			playback.travel(anim)
		else:
			playback.start(anim)
	else:
		# Fallback: set animation name parameter directly
		anim_tree.set("parameters/body_anim/animation", anim)

func _play_oneshot(anim_name: StringName) -> void:
	_active_oneshot_anim = anim_name
	if anim_tree:
		# Trigger the one-shot layer
		anim_tree.set("parameters/oneshot_anim/animation", anim_name)
		anim_tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

func _on_animation_finished(anim_name: StringName) -> void:
	# Only emit for oneshot/transition animations, not looping body anims.
	if anim_name == _active_oneshot_anim:
		_active_oneshot_anim = &""
		transition_finished.emit(anim_name)

# ---- Weapon Management ----

func _attach_weapon(pose: WeaponPoseData) -> void:
	if pose.weapon_scene == null:
		_detach_weapon()
		return

	# Skip re-instantiation if the same weapon scene is already attached.
	if pose.weapon_scene == _current_weapon_scene and is_instance_valid(_current_weapon_node):
		# Weapon scene unchanged — just re-parent if hand changed.
		_update_weapon_hand(pose.weapon_hand)
		return

	_detach_weapon()
	_current_weapon_scene = pose.weapon_scene
	_current_weapon_node = pose.weapon_scene.instantiate()
	var parent := _get_weapon_parent(pose.weapon_hand)
	if parent:
		parent.add_child(_current_weapon_node)
		_sync_weapon_visual_to_hand(pose.weapon_hand)
		_sync_weapon_rotation_to_hand()

func _detach_weapon() -> void:
	if _current_weapon_node and is_instance_valid(_current_weapon_node):
		_current_weapon_node.queue_free()
	_current_weapon_node = null
	_current_weapon_scene = null

func _update_weapon_hand(hand: String) -> void:
	if _current_weapon_node == null or not is_instance_valid(_current_weapon_node):
		return

	var current_parent := _current_weapon_node.get_parent()
	var target_parent := _get_weapon_parent(hand)

	if hand == "None":
		_detach_weapon()
		return

	if current_parent != target_parent and target_parent:
		current_parent.remove_child(_current_weapon_node)
		target_parent.add_child(_current_weapon_node)
	_sync_weapon_visual_to_hand(hand)
	_sync_weapon_rotation_to_hand()

func _get_weapon_parent(hand: String) -> Node2D:
	match hand:
		"Front":
			if front_hand_weapon_anchor:
				return front_hand_weapon_anchor
			return front_forearm
		"Back":
			if back_hand_weapon_anchor:
				return back_hand_weapon_anchor
			return back_forearm
		"Both":
			# Parent to the primary hand's anchor.
			var primary := "Front"
			if _active_weapon_pose:
				primary = _active_weapon_pose.primary_hand
			return _get_weapon_parent(primary)
		_:
			return null

func _sync_weapon_visual_to_hand(hand: String) -> void:
	if _current_weapon_node == null or not is_instance_valid(_current_weapon_node):
		return

	_current_weapon_node.z_as_relative = true

	match hand:
		"Front":
			if front_hand_sprite:
				_current_weapon_node.z_index = front_hand_sprite.z_index
		"Back":
			if back_hand_sprite:
				_current_weapon_node.z_index = back_hand_sprite.z_index
		"Both":
			var primary := "Front"
			if _active_weapon_pose:
				primary = _active_weapon_pose.primary_hand
			_sync_weapon_visual_to_hand(primary)
		_:
			pass

func _get_current_weapon_hand() -> String:
	if _active_weapon_pose == null:
		return "Front"
	if _active_weapon_pose.use_arm_sequence and not _active_weapon_pose.sequence_steps.is_empty():
		var step := _active_weapon_pose.sequence_steps[_sequence_index]
		return step.weapon_hand
	return _active_weapon_pose.weapon_hand

func _sync_weapon_rotation_to_hand() -> void:
	if _current_weapon_node == null or not is_instance_valid(_current_weapon_node):
		return

	var hand := _get_current_weapon_hand()
	var effective_hand := hand
	if hand == "Both" and _active_weapon_pose:
		effective_hand = _active_weapon_pose.primary_hand

	match effective_hand:
		"Front":
			if front_hand_weapon_anchor:
				_current_weapon_node.global_rotation = front_hand_weapon_anchor.global_rotation
			elif front_forearm:
				_current_weapon_node.global_rotation = front_forearm.global_rotation
		"Back":
			if back_hand_weapon_anchor:
				_current_weapon_node.global_rotation = back_hand_weapon_anchor.global_rotation
			elif back_forearm:
				_current_weapon_node.global_rotation = back_forearm.global_rotation
		_:
			pass

	if _current_weapon_node is WeaponSprite:
		var ws := _current_weapon_node as WeaponSprite
		_current_weapon_node.global_rotation += deg_to_rad(ws.hand_rotation_offset_degrees)

# ---- Utility ----

func _apply_pixel_settings(root: Node) -> void:
	for child in root.get_children():
		if child is Sprite2D:
			child.centered = false
			child.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply_pixel_settings(child)

## Resolve an animation name, falling back to FALLBACK_ANIM if it doesn't exist.
func _resolve_animation(anim: StringName) -> StringName:
	# Check AnimationPlayer first
	if anim_player and anim_player.has_animation(anim):
		return anim

	# Check if AnimationTree state machine has this state
	if anim_tree:
		var playback = anim_tree.get("parameters/body_state/playback")
		if playback is AnimationNodeStateMachinePlayback:
			# Can't easily check states, trust the AnimationPlayer check above
			pass

	# Animation missing — warn and fallback
	_warn_missing_animation(anim)
	return FALLBACK_ANIM

func _warn_missing_animation(anim: StringName) -> void:
	if anim in _warned_missing_anims:
		return
	_warned_missing_anims[anim] = true
	push_warning("CrayolaRig: Animation '%s' not found — falling back to '%s'. Create this clip in the AnimationPlayer." % [anim, FALLBACK_ANIM])

## Get the currently attached WeaponSprite (or null if no weapon or not a WeaponSprite).
func get_weapon_sprite() -> WeaponSprite:
	if _current_weapon_node and _current_weapon_node is WeaponSprite:
		return _current_weapon_node as WeaponSprite
	return null

## Get projectile spawn position from the weapon's muzzle point.
## Falls back to a default offset from the rig's chest if no weapon/muzzle.
func get_projectile_spawn_position() -> Vector2:
	var ws := get_weapon_sprite()
	if ws:
		return ws.get_muzzle_position()
	# Fallback: offset from chest pivot in facing direction
	var offset := Vector2(20, -8) if _facing_right else Vector2(-20, -8)
	return chest_pivot.global_position + offset
