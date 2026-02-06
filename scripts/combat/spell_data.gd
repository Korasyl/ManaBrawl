extends Resource
class_name SpellData

@export var spell_name: String = ""
@export_multiline var description: String = ""
@export var mana_cost: float = 20.0
@export var cooldown: float = 5.0
@export_enum("targeted", "free_aim", "toggled", "placement") var cast_type: String = "free_aim"

## Spell scene — if set, this scene is instantiated as the spell's effect.
## For projectile spells: overrides the default projectile scene.
## For placement spells: the scene spawned at the placement location.
## The scene receives context via initialize() if it has that method.
@export var spell_scene: PackedScene

## Projectile properties (for targeted / free_aim when spell_scene is null)
@export var damage: float = 20.0
@export var interrupt_type: String = "flinch"
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color(0.5, 0.3, 1.0)

## Targeted spell behavior
@export_enum("projectile", "apply_at_target") var targeted_delivery: String = "projectile"
@export var targeted_homing_turn_speed: float = 8.0  # radians per second
@export var can_target_allies: bool = false

## Channeled casting
@export var is_channeled: bool = false
@export var channel_mana_drain_per_second: float = 16.0
@export var channel_fire_interval: float = 0.16
@export var channel_projectiles_per_tick: int = 1


## Cast modifiers (GDD spell variables)
@export var prevent_move: bool = false
@export var slow_move: float = 1.0  # 1.0 = normal, 0.5 = half speed while active

## Toggle properties
@export var toggle_mana_drain: float = 5.0  # Mana per second while toggled on

## Placement preview tuning (used by Player._draw placement ghost)
@export var placement_preview_size: Vector2 = Vector2(220.0, 18.0)
@export var placement_preview_color: Color = Color(0.35, 0.75, 1.0, 0.30)
@export var placement_preview_outline_color: Color = Color(0.35, 0.75, 1.0, 0.85)
