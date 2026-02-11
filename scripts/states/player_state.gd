extends RefCounted
class_name PlayerState

## PlayerState — Base class for all player states.
##
## Each state handles its own input, physics, and transitions.
## Override the virtual methods to define state behavior.
##
## LIFECYCLE:
##   enter(prev_state)    — Called once when transitioning INTO this state
##   exit(next_state)     — Called once when transitioning OUT of this state
##   process(delta)       — Called every _physics_process frame
##   handle_input()       — Called every frame for input checking (returns transition)
##
## TRANSITIONS:
##   Return a state name string from handle_input() or process() to trigger a transition.
##   Return "" (empty string) to stay in the current state.
##
## ACCESSING PLAYER:
##   self.player — reference to the player CharacterBody2D
##   self.machine — reference to the PlayerStateMachine

var player: CharacterBody2D = null
var machine = null  # PlayerStateMachine (can't type-hint due to circular ref)

## Called when entering this state. prev_state is the name of the state we came from.
func enter(prev_state: String) -> void:
	pass

## Called when exiting this state. next_state is the name of the state we're going to.
func exit(next_state: String) -> void:
	pass

## Called every _physics_process. Return a state name to transition, or "" to stay.
func process(delta: float) -> String:
	return ""

## Called every frame for input. Return a state name to transition, or "" to stay.
func handle_input() -> String:
	return ""

## Convenience: get the state name (derived from class or set by machine).
func get_state_name() -> String:
	return ""
