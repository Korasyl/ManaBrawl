extends Resource
class_name AIStrategy

## Data-driven strategy profile for AI opponents.
## Controls how the AI prioritizes actions, manages resources, and positions itself.
## Three archetypes: Aggressive (pressure), Defensive (spacing/control), Supportive (attrition).

@export var strategy_name: String = "Balanced"
@export_multiline var description: String = ""

## Behavior weights (0.0–1.0) — influence which mid-level behavior the AI selects.
@export_group("Behavior Weights")
@export_range(0.0, 1.0) var aggression: float = 0.5
@export_range(0.0, 1.0) var defensiveness: float = 0.5
@export_range(0.0, 1.0) var spell_preference: float = 0.5

## Spacing — preferred distances from the target.
@export_group("Spacing")
@export var preferred_melee_range: float = 80.0
@export var preferred_spell_range: float = 250.0
@export var too_close_distance: float = 40.0
@export var chase_max_distance: float = 400.0

## Resource management — health/mana thresholds that trigger behavior changes.
@export_group("Resource Management")
@export_range(0.0, 1.0) var coalesce_mana_threshold: float = 0.3
@export_range(0.0, 1.0) var retreat_health_threshold: float = 0.25
@export_range(0.0, 1.0) var aggressive_health_threshold: float = 0.6
@export_range(0.0, 1.0) var spell_mana_reserve: float = 0.2

## Difficulty tuning — controls reaction speed and decision quality.
@export_group("Difficulty")
@export var decision_interval: float = 0.3
@export var reaction_delay: float = 0.1
@export_range(0.0, 1.0) var block_chance: float = 0.5
@export_range(0.0, 1.0) var dodge_chance: float = 0.3

## Spell usage — priority order and placement strategy.
@export_group("Spell Usage")
@export var spell_priority: Array[int] = [0, 1, 2, 3]
@export_range(0.0, 1.0) var placement_defensiveness: float = 0.5
