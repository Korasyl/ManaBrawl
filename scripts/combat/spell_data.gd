extends Resource
class_name SpellData

@export var spell_name: String = ""
@export var mana_cost: float = 20.0
@export var cooldown: float = 5.0
@export_enum("targeted", "free_aim", "toggled") var cast_type: String = "free_aim"

## Projectile properties (for targeted / free_aim)
@export var damage: float = 20.0
@export var interrupt_type: String = "flinch"
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color(0.5, 0.3, 1.0)

## Cast modifiers (GDD spell variables)
@export var prevent_move: bool = false
@export var slow_move: float = 1.0  # 1.0 = normal, 0.5 = half speed while active

## Toggle properties
@export var toggle_mana_drain: float = 5.0  # Mana per second while toggled on
