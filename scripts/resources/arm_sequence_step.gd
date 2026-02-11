extends Resource
class_name ArmSequenceStep

## ArmSequenceStep — One step in an alternating arm sequence.
##
## Used by WeaponPoseData.sequence_steps for characters who swap arms
## between actions (e.g., Spatchcock fires right flintlock → tosses it →
## pulls left flintlock from coat → fires left → repeat).
##
## SETUP GUIDE:
## 1. Create one ArmSequenceStep per distinct arm state in the cycle
## 2. Set which arm aims and which plays an animation
## 3. Configure weapon hand if it changes per step
## 4. Add an optional transition animation between steps
##
## EXAMPLE — Spatchcock's Flintlock Cycle:
##   Step 0: Front arm aims (holding flintlock), back arm idle
##     aim_arm_flags = 1, weapon_hand = "Front", front_arm_animation = ""
##   Step 1: Front arm tosses (playing "toss_flintlock"), back arm draws new gun
##     aim_arm_flags = 0, transition_animation = "toss_flintlock_front"
##   Step 2: Back arm aims (holding flintlock), front arm idle
##     aim_arm_flags = 2, weapon_hand = "Back", back_arm_animation = ""
##   Step 3: Back arm tosses, front arm draws
##     aim_arm_flags = 0, transition_animation = "toss_flintlock_back"
##   (wraps to step 0)

## Which arms track the mouse in this step.
@export_enum("None:0", "Front:1", "Back:2", "Both:3") var aim_arm_flags: int = 1

## Arm animation overrides for this step (non-aiming arms).
@export var front_arm_animation: StringName = &""
@export var back_arm_animation: StringName = &""

## Weapon hand for this step (weapon may swap between hands).
@export_enum("None", "Front", "Back") var weapon_hand: String = "Front"

## One-shot animation to play when transitioning INTO this step.
## e.g., "draw_flintlock_left", "toss_flintlock_right"
@export var transition_animation: StringName = &""

## How long this step lasts before auto-advancing (seconds).
## 0 = step does not auto-advance (waits for manual advance_sequence call).
## Use > 0 for timed steps like toss animations.
@export var auto_advance_time: float = 0.0
