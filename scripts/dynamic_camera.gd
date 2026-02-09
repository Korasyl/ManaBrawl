extends Camera2D

## The node to follow (auto-finds player group if empty)
@export var target_path: NodePath

## Smooth follow — higher = snappier tracking
@export var smooth_speed: float = 8.0

## Mouse lookahead — shifts camera toward cursor for situational awareness
@export var mouse_influence: float = 0.3        # Fraction of mouse-to-player distance applied as offset
@export var deadzone_radius: float = 50.0       # Mouse must be this far from player before camera shifts
@export var max_lookahead: float = 80.0         # Max camera offset (pixels) when not aiming
@export var aim_lookahead: float = 200.0        # Max camera offset (pixels) when aiming

var target: Node2D = null

func _ready():
	if target_path != NodePath():
		target = get_node(target_path)
	else:
		await get_tree().process_frame
		target = get_tree().get_first_node_in_group("player")

func _process(delta):
	if not target:
		return

	# Check if player is aiming (ranged mode, spell queued, or channeling)
	var is_aiming := false
	if "is_in_ranged_mode" in target:
		is_aiming = is_aiming or target.is_in_ranged_mode
	if "queued_spell_index" in target:
		is_aiming = is_aiming or (target.queued_spell_index >= 0)
	if "is_channeling_spell" in target:
		is_aiming = is_aiming or target.is_channeling_spell

	var current_max := aim_lookahead if is_aiming else max_lookahead

	# Calculate mouse offset from player in world space
	var mouse_world := get_global_mouse_position()
	var mouse_offset := mouse_world - target.global_position
	var mouse_dist := mouse_offset.length()

	# Apply camera offset toward mouse, clamped to max lookahead
	var cam_offset := Vector2.ZERO
	if mouse_dist > deadzone_radius:
		var effective := mouse_dist - deadzone_radius
		cam_offset = mouse_offset.normalized() * minf(effective * mouse_influence, current_max)

	# Target camera position = player + lookahead offset
	var target_pos := target.global_position + cam_offset

	# Smooth follow with exponential decay (frame-rate independent)
	global_position = global_position.lerp(target_pos, 1.0 - exp(-smooth_speed * delta))
