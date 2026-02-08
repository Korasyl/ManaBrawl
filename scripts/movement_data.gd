extends Resource
class_name MovementData

## Advanced Movement Properties
@export var can_double_jump: bool = true
@export var can_wall_cling: bool = true
@export var can_wall_jump: bool = true

## Dash Properties
@export var dash_distance: float = 150.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.5
@export var dash_grants_iframes: bool = true

## Ground Acceleration
@export var ground_acceleration: float = 2000.0   # px/s² — how fast we reach target speed
@export var ground_deceleration: float = 2400.0   # px/s² — how fast we stop (slightly snappier)

## Air Control
@export var air_acceleration: float = 900.0       # px/s² — steering authority while airborne
@export var air_deceleration: float = 200.0        # px/s² — very low, preserves momentum

## Coyote Time
@export var coyote_time: float = 0.12              # seconds of grace after leaving a ledge

## Wall Properties
@export var wall_slide_speed: float = 100.0
@export var wall_jump_horizontal_boost: float = 300.0
