extends Node2D
class_name WeaponSprite

## WeaponSprite — Base class for all held weapon visuals.
##
## Provides standardized attachment points for VFX, projectile origins,
## and trails. Parent this to a forearm pivot via WeaponPoseData.weapon_scene.
##
## SETUP GUIDE:
## 1. Create a scene with WeaponSprite as the root
## 2. Add a Sprite2D child with the weapon texture
## 3. Position the Sprite2D so the grip point is at origin (0,0)
##    — origin = where the hand holds the weapon
## 4. Add Marker2D children for effect points (optional):
##    - MuzzlePoint: where projectiles/flashes spawn (gun barrel tip)
##    - EffectAnchor: where persistent effects attach (staff crystal glow)
##    - TrailOrigin: where motion trails emit from (sword blade tip)
##    - ImpactPoint: where hit sparks spawn (shield face center)
## 5. Configure exports for behavior
##
## NODE STRUCTURE EXAMPLE (Flintlock):
##   WeaponSprite (this script)
##   ├── Sprite2D (flintlock texture, offset so grip is at origin)
##   ├── MuzzlePoint (Marker2D at barrel tip)
##   ├── EffectAnchor (Marker2D at flintlock hammer for spark)
##   └── TrailOrigin (Marker2D along barrel for smoke trail)
##
## NODE STRUCTURE EXAMPLE (Amethyst Staff):
##   WeaponSprite (this script)
##   ├── Sprite2D (staff texture)
##   ├── MuzzlePoint (Marker2D at amethyst crystal tip)
##   ├── EffectAnchor (Marker2D at crystal center for glow shader)
##   ├── TrailOrigin (Marker2D at staff tip for arc trails)
##   └── GlowSprite (Sprite2D with additive blend for crystal glow)
##
## NODE STRUCTURE EXAMPLE (Shield):
##   WeaponSprite (this script)
##   ├── Sprite2D (shield face texture)
##   ├── ImpactPoint (Marker2D at shield center for block sparks)
##   ├── EffectAnchor (Marker2D for enchantment glow)
##   └── BlockArea (Area2D for deflection hitbox — Aegis-specific)

# ---- Marker Points ----

## Where projectiles and muzzle flashes spawn.
## e.g., flintlock barrel tip, staff crystal tip.
@export var muzzle_point_path: NodePath = "MuzzlePoint"

## Where persistent effects attach (glows, enchantments, auras).
## e.g., amethyst crystal on Zip's staff, rune glow on Fervor's tome.
@export var effect_anchor_path: NodePath = "EffectAnchor"

## Where motion trails emit from.
## e.g., blade tip for sword trails, spear point for thrust trails.
@export var trail_origin_path: NodePath = "TrailOrigin"

## Where impact effects spawn (block sparks, parry flashes).
## e.g., center of Aegis's shield face.
@export var impact_point_path: NodePath = "ImpactPoint"

# ---- Resolved References (populated in _ready) ----

var muzzle_point: Marker2D = null
var effect_anchor: Marker2D = null
var trail_origin: Marker2D = null
var impact_point: Marker2D = null

# ---- Active Effects ----

var _active_effects: Array[Node] = []

# ---- Configuration ----

## Idle animation for the weapon itself (e.g., crystal pulsing, flame flicker).
## Played on a child AnimationPlayer if present.
@export var idle_animation: StringName = &""

## Whether the weapon sprite should flip when the character faces left.
## Usually false because the rig's scale.x flip handles this.
@export var flip_with_facing: bool = false

## Per-weapon rotation correction (degrees) applied after hand/anchor rotation sync.
## Use this when a weapon's authored forward axis differs from the rig convention.
@export var hand_rotation_offset_degrees: float = 0.0

func _ready() -> void:
	# Resolve marker paths
	if muzzle_point_path != NodePath(""):
		muzzle_point = get_node_or_null(muzzle_point_path) as Marker2D
	if effect_anchor_path != NodePath(""):
		effect_anchor = get_node_or_null(effect_anchor_path) as Marker2D
	if trail_origin_path != NodePath(""):
		trail_origin = get_node_or_null(trail_origin_path) as Marker2D
	if impact_point_path != NodePath(""):
		impact_point = get_node_or_null(impact_point_path) as Marker2D

	# Apply pixel art settings to all child sprites
	_apply_pixel_settings(self)

	# Start idle animation if present
	if idle_animation != &"":
		var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim and anim.has_animation(idle_animation):
			anim.play(idle_animation)

# ========================================================================
# PUBLIC API — Called by rig or player systems
# ========================================================================

## Get the global position of a marker point. Returns weapon center if marker missing.
func get_muzzle_position() -> Vector2:
	return muzzle_point.global_position if muzzle_point else global_position

func get_effect_anchor_position() -> Vector2:
	return effect_anchor.global_position if effect_anchor else global_position

func get_trail_origin_position() -> Vector2:
	return trail_origin.global_position if trail_origin else global_position

func get_impact_position() -> Vector2:
	return impact_point.global_position if impact_point else global_position

## Spawn a VFX scene at a marker point. Returns the spawned node.
func spawn_effect_at(marker_name: String, effect_scene: PackedScene, parent_to_weapon: bool = false) -> Node:
	var pos := global_position
	match marker_name:
		"muzzle":
			pos = get_muzzle_position()
		"effect":
			pos = get_effect_anchor_position()
		"trail":
			pos = get_trail_origin_position()
		"impact":
			pos = get_impact_position()

	var effect := effect_scene.instantiate()

	if parent_to_weapon:
		# Effect follows the weapon (e.g., staff glow)
		var anchor := _get_marker_node(marker_name)
		if anchor:
			anchor.add_child(effect)
		else:
			add_child(effect)
		effect.position = Vector2.ZERO
	else:
		# Effect spawns in world space (e.g., muzzle flash that stays in place)
		get_tree().current_scene.add_child(effect)
		effect.global_position = pos

	_active_effects.append(effect)
	return effect

## Remove all active effects spawned by this weapon.
func clear_effects() -> void:
	for effect in _active_effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_active_effects.clear()

## Play a one-shot animation on the weapon's own AnimationPlayer.
## e.g., "fire_recoil" for flintlock kickback, "crystal_pulse" for staff charge.
func play_weapon_animation(anim_name: StringName) -> void:
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation(anim_name):
		anim.play(anim_name)

## Get the currently held weapon as a WeaponSprite from a rig.
## Static helper for external systems.
static func get_from_rig(rig: CrayolaRig) -> WeaponSprite:
	return rig.get_weapon_sprite()

# ========================================================================
# INTERNAL
# ========================================================================

func _get_marker_node(marker_name: String) -> Node2D:
	match marker_name:
		"muzzle":
			return muzzle_point
		"effect":
			return effect_anchor
		"trail":
			return trail_origin
		"impact":
			return impact_point
	return null

func _apply_pixel_settings(root: Node) -> void:
	for child in root.get_children():
		if child is Sprite2D:
			child.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply_pixel_settings(child)
