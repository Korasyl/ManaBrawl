extends Node
class_name PassiveSkill

## Base class for character-unique passive abilities.
## Instantiated as a child of the player. Hooks into player signals.
## Subclasses override the event methods for unique behavior.

var player: Node = null

## Called by player after adding this as a child. Connects to player signals.
func initialize(p: Node) -> void:
	player = p

	# Auto-connect to player signals
	if player.has_signal("action_started"):
		player.action_started.connect(_on_action_started)
	if player.has_signal("action_ended"):
		player.action_ended.connect(_on_action_ended)
	if player.has_signal("dealt_damage"):
		player.dealt_damage.connect(_on_dealt_damage)
	if player.has_signal("took_damage"):
		player.took_damage.connect(_on_took_damage)
	if player.has_signal("mana_spent"):
		player.mana_spent.connect(_on_mana_spent)

	_on_passive_ready()

## Override: called once after initialization. Set up timers, state, etc.
func _on_passive_ready() -> void:
	pass

## Override: called every physics frame.
func _passive_process(_delta: float) -> void:
	pass

## Override: when the player starts an action (dash, attack, coalesce, etc.)
func _on_action_started(_action_id: String, _ctx: Dictionary) -> void:
	pass

## Override: when the player finishes an action
func _on_action_ended(_action_id: String, _ctx: Dictionary) -> void:
	pass

## Override: when the player deals damage
func _on_dealt_damage(_amount: float, _target: Node, _ctx: Dictionary) -> void:
	pass

## Override: when the player takes damage
func _on_took_damage(_amount: float, _source: Node, _ctx: Dictionary) -> void:
	pass

## Override: when the player spends mana
func _on_mana_spent(_amount: float, _reason: String, _ctx: Dictionary) -> void:
	pass

## Override: modify a spell before it's cast (return modified spell data or null for no change).
## Called by player's cast_spell to let passives alter spell behavior.
func modify_spell(_spell: SpellData, _ctx: Dictionary) -> void:
	pass

## Override: modify outgoing damage value. Return the modified value.
func modify_damage(value: float, _ctx: Dictionary) -> float:
	return value

## Override: modify incoming damage value. Return the modified value.
func modify_incoming_damage(value: float, _ctx: Dictionary) -> float:
	return value
