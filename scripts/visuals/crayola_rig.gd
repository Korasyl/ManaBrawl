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

## Downward screen-space compensation (pixels) applied while aiming.
## Positive values pull the arm aim slightly lower to align hand/muzzle with cursor.
@export var aim_vertical_compensation: float = 10.0

# ---- Internal State ----

var _current_body_anim: StringName = &"idle"
var _facing_right: bool = true
var _front_arm_angle: float = 0.0
var _back_arm_angle: float = 0.0
var _stomach_base_position: Vector2 = Vector2.ZERO
var _front_arm_rest_rotation: float = 0.0
var _back_arm_rest_rotation: float = 0.0
var _front_forearm_rest_rotation: float = 0.0
var _back_forearm_rest_rotation: float = 0.0

## Active weapon pose (set by player via apply_weapon_state)
var _active_weapon_pose: WeaponPoseData = null
var _current_weapon_node: Node2D = null

## Arm sequence state
var _sequence_index: int = 0
var _sequence_auto_timer: float = 0.0

## Blend state for arm code-vs-animation
var _front_arm_code_blend: float = 0.0  # 0 = animation, 1 = code aim
var _back_arm_code_blend: float = 0.0
var _blend_speed: float = 10.0

# ---- Node References ----
# Subclasses can override these paths if their hierarchy differs.

@onready var stomach_pivot: Node2D = $StomachPivot
@onready var chest_pivot: Node2D = $StomachPivot/ChestPivot
@onready var back_arm_pivot: Node2D = $StomachPivot/ChestPivot/BackArmPivot
@onready var back_forearm: Node2D = $StomachPivot/ChestPivot/BackArmPivot/BackForearmPivot
@onready var front_arm_pivot: Node2D = $StomachPivot/ChestPivot/FrontArmPivot
@onready var front_forearm: Node2D = $StomachPivot/ChestPivot/FrontArmPivot/FrontForearmPivot

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

	# Determine blend targets from flags (or first sequence step)
	var flags := _get_current_aim_flags()
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
func update_arm_aim(aim_active: bool, aim_world_pos: Vector2) -> void:
	if not aim_active:
		# No aiming — smoothly return to rest pose.
		# (Especially important for rigs without AnimationTree blend tracks.)
		var reset_lerp := 0.20 * arm_lerp_speed / 18.0
		_front_arm_angle = lerp_angle(_front_arm_angle, _front_arm_rest_rotation, reset_lerp)
		_back_arm_angle = lerp_angle(_back_arm_angle, _back_arm_rest_rotation, reset_lerp)
		front_arm_pivot.rotation = _front_arm_angle
		back_arm_pivot.rotation = _back_arm_angle
		front_forearm.rotation = lerp_angle(front_forearm.rotation, _front_forearm_rest_rotation, reset_lerp)
		back_forearm.rotation = lerp_angle(back_forearm.rotation, _back_forearm_rest_rotation, reset_lerp)
		return

	var flags := _get_current_aim_flags()
	# Fallback: if no pose/flags are configured, still aim the front arm for free-aim gameplay.
	if flags == 0:
		flags = 1

	var lerp_factor := 0.15 * arm_lerp_speed / 18.0
	var compensated_aim_world_pos := aim_world_pos + Vector2(0, aim_vertical_compensation)

	# Front arm code aim
	if flags & 1:
		var target := _compute_aim_angle(front_arm_pivot.global_position, compensated_aim_world_pos)
		_front_arm_angle = lerp_angle(_front_arm_angle, target, lerp_factor)
		front_arm_pivot.rotation = _front_arm_angle
		front_forearm.rotation = _front_arm_angle * 0.25

	# Back arm code aim
	if flags & 2:
		var target := _compute_aim_angle(back_arm_pivot.global_position, compensated_aim_world_pos)
		_back_arm_angle = lerp_angle(_back_arm_angle, target, lerp_factor)
		back_arm_pivot.rotation = _back_arm_angle
		back_forearm.rotation = _back_arm_angle * 0.25

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

# ========================================================================
# INTERNAL
# ========================================================================

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
	if not anim_tree:
		return
	if pose.front_arm_animation != &"":
		anim_tree.set("parameters/front_arm_anim/animation", pose.front_arm_animation)
	if pose.back_arm_animation != &"":
		anim_tree.set("parameters/back_arm_anim/animation", pose.back_arm_animation)

func _apply_arm_animations_from_step(step: ArmSequenceStep) -> void:
	if not anim_tree:
		return
	if step.front_arm_animation != &"":
		anim_tree.set("parameters/front_arm_anim/animation", step.front_arm_animation)
	if step.back_arm_animation != &"":
		anim_tree.set("parameters/back_arm_anim/animation", step.back_arm_animation)

func _compute_aim_angle(shoulder_pos: Vector2, aim_world_pos: Vector2) -> float:
	var world_dir := aim_world_pos - shoulder_pos
	if not _facing_right:
		world_dir.x = -world_dir.x
	var aim_angle := world_dir.angle() - PI / 2.0
	return clamp(aim_angle, aim_angle_min, aim_angle_max)

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
	if anim_tree:
		# Trigger the one-shot layer
		var oneshot = anim_tree.get("parameters/oneshot/request")
		if oneshot != null:
			anim_tree.set("parameters/oneshot_anim/animation", anim_name)
			anim_tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

func _on_animation_finished(anim_name: StringName) -> void:
	transition_finished.emit(anim_name)

# ---- Weapon Management ----

func _attach_weapon(pose: WeaponPoseData) -> void:
	_detach_weapon()

	if pose.weapon_scene == null or pose.weapon_hand == "None":
		return

	_current_weapon_node = pose.weapon_scene.instantiate()
	var parent := _get_weapon_parent(pose.weapon_hand)
	if parent:
		parent.add_child(_current_weapon_node)

func _detach_weapon() -> void:
	if _current_weapon_node and is_instance_valid(_current_weapon_node):
		_current_weapon_node.queue_free()
		_current_weapon_node = null

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

func _get_weapon_parent(hand: String) -> Node2D:
	match hand:
		"Front":
			return front_forearm
		"Back":
			return back_forearm
		_:
			return null

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
