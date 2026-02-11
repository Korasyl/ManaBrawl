extends Resource
class_name RangedModeData

## Identity
@export var mode_name: String = "Basic Ranged"
@export_enum("free_aim", "targeted", "deflect", "none") var mode_type: String = "free_aim"

## Weapon Pose — arm/weapon behavior while in this ranged mode.
## Overrides the default weapon pose from CharacterStats.
## If null, falls back to CharacterStats.default_weapon_pose.
@export var weapon_pose: WeaponPoseData

## Projectile properties
@export var damage: float = 8.0
@export var damage_type: String = "ranged"  # Flows into ContextKeys.DAMAGE_TYPE for attunement hooks
@export var interrupt_type: String = "flinch"
@export var projectile_speed: float = 600.0
@export var projectile_color: Color = Color(1, 0.9, 0.3, 1)
@export var projectile_scene: PackedScene  # null = use default projectile

## Mode behavior
@export var fire_cooldown: float = 0.4
@export var mana_cost: float = 5.0
@export var move_speed_mult: float = 0.7  # Movement speed while in ranged mode

## Targeted delivery options (used when mode_type == "targeted")
@export var targeted_max_range_from_cursor: float = 220.0
@export var targeted_allow_self: bool = true
@export var targeted_affect_allies: bool = true
@export var targeted_affect_enemies: bool = true
@export var requires_line_of_sight: bool = true

## Targeted delivery method: how effects reach the target
## "apply_at_target" = instant application, "projectile" = homing projectile delivers effects on hit
@export_enum("apply_at_target", "projectile") var targeted_delivery: String = "apply_at_target"
## Homing turn speed for projectile delivery (radians/sec)
@export var targeted_homing_turn_speed: float = 8.0

## Cauterizing Fire-style effects
@export var targeted_burst_damage: float = 0.0
@export var targeted_burst_heal: float = 0.0
@export var targeted_dot_duration: float = 0.0
@export var targeted_dot_damage_per_second: float = 0.0
@export var targeted_hot_duration: float = 0.0
@export var targeted_hot_heal_per_second: float = 0.0
@export var targeted_effect_id: String = ""
