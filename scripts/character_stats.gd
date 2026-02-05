extends Resource
class_name CharacterStats

## Core Stats
@export var character_name: String = "Character"
@export var max_health: float = 100.0
@export var max_mana: float = 100.0

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

## Mana Regen
@export var passive_mana_regen: float = 5.0  # per second
@export var coalescence_multiplier: float = 4.0
@export var melee_hit_mana_gain: float = 10.0  # Light attack mana gain
@export var heavy_melee_hit_mana_gain: float = 15.0  # Heavy attack mana gain (GDD: Heavy > Light)
@export var melee_blocked_mana_gain: float = 3.0
@export var heavy_shield_break_bonus: float = 20.0

## Attack Stats
@export var light_attack_damage: float = 15.0
@export var heavy_attack_damage: float = 35.0
@export var heavy_attack_charge_time: float = 0.5
@export var light_attack_duration: float = 0.2  # How long hitbox is active
@export var heavy_attack_duration: float = 0.3
@export var knockback_force: float = 300.0  # For heavy attacks
