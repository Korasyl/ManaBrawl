extends Node
class_name PlayerStateMachine

## PlayerStateMachine — Manages player states and transitions.
##
## SETUP:
## 1. Add as a child node of the Player scene
## 2. In player._ready(), call machine.initialize(self, states_dict, "Idle")
## 3. In player._physics_process(), call machine.process(delta)
##
## USAGE FROM PLAYER:
##   var machine: PlayerStateMachine
##
##   func _ready():
##       machine = $PlayerStateMachine
##       machine.initialize(self, {
##           "Idle": IdleState.new(),
##           "Walking": WalkingState.new(),
##           "Airborne": AirborneState.new(),
##           "Dashing": DashingState.new(),
##           "Attacking": AttackingState.new(),
##           "Blocking": BlockingState.new(),
##           "Coalescing": CoalescingState.new(),
##           "Casting": CastingState.new(),
##           "Stunned": StunnedState.new(),
##           "Dead": DeadState.new(),
##           "WallCling": WallClingState.new(),
##           "LedgeGrab": LedgeGrabState.new(),
##           "RangedMode": RangedModeState.new(),
##           "Placing": PlacingState.new(),
##       }, "Idle")
##
## FORCING TRANSITIONS:
##   machine.transition_to("Stunned")  # External force (e.g., take_damage)
##
## QUERYING:
##   machine.current_state_name  # "Idle", "Attacking", etc.
##   machine.is_in_state("Attacking")
##   machine.get_state("Attacking")

## Emitted on every state transition. Useful for debug HUD, animation sync.
signal state_changed(old_state: String, new_state: String)

## Current active state object.
var current_state: PlayerState = null

## Current state name.
var current_state_name: String = ""

## All registered states.
var _states: Dictionary = {}

## Player reference.
var _player: CharacterBody2D = null

## State history for debugging (last N transitions).
var _history: Array[String] = []
const HISTORY_SIZE: int = 10

## Lock flag — prevents transitions during certain critical operations.
var _transition_locked: bool = false

# ========================================================================
# PUBLIC API
# ========================================================================

## Initialize the state machine with a player reference, states dict, and starting state.
func initialize(player: CharacterBody2D, states: Dictionary, starting_state: String) -> void:
	_player = player

	for state_name in states:
		var state: PlayerState = states[state_name]
		state.player = player
		state.machine = self
		_states[state_name] = state

	# Enter the starting state
	if _states.has(starting_state):
		current_state = _states[starting_state]
		current_state_name = starting_state
		current_state.enter("")
		_push_history(starting_state)
	else:
		push_error("PlayerStateMachine: Starting state '%s' not found!" % starting_state)

## Call this from player._physics_process(delta).
func process(delta: float) -> void:
	if current_state == null:
		return

	# Check input for transitions
	var input_transition := current_state.handle_input()
	if input_transition != "":
		transition_to(input_transition)
		return

	# Process the state (physics, timers, etc.)
	var process_transition := current_state.process(delta)
	if process_transition != "":
		transition_to(process_transition)

## Force a transition to a specific state. Use for external events like take_damage.
func transition_to(new_state_name: String) -> void:
	if _transition_locked:
		return

	if not _states.has(new_state_name):
		push_warning("PlayerStateMachine: State '%s' not found, staying in '%s'" % [new_state_name, current_state_name])
		return

	if new_state_name == current_state_name:
		return  # Already in this state

	var old_name := current_state_name
	var new_state: PlayerState = _states[new_state_name]

	# Exit current state
	if current_state:
		current_state.exit(new_state_name)

	# Enter new state
	current_state = new_state
	current_state_name = new_state_name
	current_state.enter(old_name)

	_push_history(new_state_name)
	state_changed.emit(old_name, new_state_name)

## Check if currently in a specific state.
func is_in_state(state_name: String) -> bool:
	return current_state_name == state_name

## Check if currently in any of the given states.
func is_in_any(state_names: Array[String]) -> bool:
	return current_state_name in state_names

## Get a state object by name (for querying state-specific data).
func get_state(state_name: String) -> PlayerState:
	return _states.get(state_name, null)

## Lock transitions temporarily (e.g., during a critical animation frame).
func lock_transitions() -> void:
	_transition_locked = true

## Unlock transitions.
func unlock_transitions() -> void:
	_transition_locked = false

## Get recent state history for debugging.
func get_history() -> Array[String]:
	return _history.duplicate()

## Get a formatted string of current + recent history for debug HUD.
func get_debug_string() -> String:
	return "%s ← %s" % [current_state_name, " ← ".join(_history.slice(0, 3))]

# ========================================================================
# INTERNAL
# ========================================================================

func _push_history(state_name: String) -> void:
	_history.push_front(state_name)
	if _history.size() > HISTORY_SIZE:
		_history.resize(HISTORY_SIZE)
