extends Resource
class_name CharacterStats

## Core Stats
@export var character_name: String = "Character"
@export var max_health: float = 100.0
@export var max_mana: float = 100.0

## Character Rig — the visual skeleton scene for this character.
## Each character has their own rig scene with unique textures, proportions,
## and AnimationPlayer clips. If null, uses the default CrayolaRig.
@export var rig_scene: PackedScene

## Default Weapon Pose — arm/weapon behavior when NOT in ranged mode or casting.
## Controls idle weapon hold, arm animations, etc.
## If null, arms are fully driven by body animations (no weapon).
@export var default_weapon_pose: WeaponPoseData

## Movement Stats
@export var walk_speed: float = 200.0
@export var sprint_speed: float = 350.0
@export var crouch_speed: float = 100.0
@export var jump_velocity: float = -400.0
@export var gravity_scale: float = 1.0

## Advanced Movement Costs
@export var double_jump_cost: float = 15.0
@export var dash_cost: float = 35.0
@export var wall_jump_cost: float = 10.0
@export var wall_cling_drain: float = 1.0  # per second
@export var crouch_boost_cost: float = 25.0
@export var crouch_boost_velocity: float = -650.0  # Powered jump (normal: -400)

## Mana Regen
@export var passive_mana_regen: float = 5.0  # per second
@export var coalescence_multiplier: float = 4.0
@export var melee_hit_mana_gain: float = 10.0  # Light attack mana gain
@export var heavy_melee_hit_mana_gain: float = 15.0  # Heavy attack mana gain (GDD: Heavy > Light)
@export var melee_blocked_mana_gain: float = 3.0
@export var heavy_shield_break_bonus: float = 20.0

## Block Stats
@export var block_mana_drain: float = 8.0  # Mana per second while blocking
@export var block_move_speed: float = 80.0  # Significantly slowed

## Attack Stats
@export var light_attack_damage: float = 15.0
@export var heavy_attack_damage: float = 35.0
@export var heavy_attack_charge_time: float = 0.5
@export var light_attack_duration: float = 0.3  # How long hitbox is active (also clash window)
@export var heavy_attack_duration: float = 0.45
@export var knockback_force: float = 300.0  # For heavy attacks

## Melee Attack Animations — per-character attack definitions.
## If null, attacks still work with the timer-based system (no animation).
## When set, the rig plays the specified animation and optionally uses
## anim events for frame-perfect hitbox control.
@export var light_attack_data: MeleeAttackData
@export var heavy_attack_data: MeleeAttackData
## Optional second light for combos (different animation than first light).
@export var combo_light_attack_data: MeleeAttackData

## Ranged
@export var ranged_mode: RangedModeData

## Passive — character-unique passive ability scene (extends PassiveSkill)
@export var passive_scene: PackedScene
