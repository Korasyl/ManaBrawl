extends Resource
class_name WeaponPoseData

## WeaponPoseData — Defines arm behavior, weapon attachment, and animation overrides
## for a specific character state (default stance, ranged mode, or spell casting).
##
## SETUP GUIDE:
## 1. Create a new WeaponPoseData resource in the inspector
## 2. Set aim_arm_flags to control which arms track the mouse
## 3. Set arm animation names for non-tracking arms (must match AnimationPlayer clips)
## 4. Optionally attach a weapon scene to a specific hand
##
## ARM FLAGS:
##   0 = Neither arm aims (both play animations) — use for melee stances, theatre poses
##   1 = Front arm aims (back arm plays animation) — use for pistols, one-handed casting
##   2 = Back arm aims (front arm plays animation) — use for backhand throws
##   3 = Both arms aim — use for rifles, two-handed channeling
##
## ANIMATION NAMES:
##   These must correspond to animation clips in the character's rig AnimationPlayer.
##   Leave empty ("") to let the body animation's arm track drive that arm.
##   Examples: "hold_tome", "brace_rifle", "hip_rest", "flintlock_hold"
##
## WEAPON HAND:
##   "None"  — No weapon sprite shown
##   "Front" — Weapon parented to FrontForearmPivot (the hand closer to camera)
##   "Back"  — Weapon parented to BackForearmPivot
##
## ARM SEQUENCE (Advanced):
##   For characters like Spatchcock who alternate arms (fire right, swap to left on cooldown),
##   enable use_arm_sequence and configure the sequence_steps array.
##   The rig will advance through steps on each fire event.

## ---- Arm Aiming ----

## Which arms the code-driven aim tracker controls.
## 0 = None, 1 = Front, 2 = Back, 3 = Both
@export_enum("None:0", "Front:1", "Back:2", "Both:3") var aim_arm_flags: int = 0

## ---- Arm Animations (for non-aiming arms) ----

## Animation clip name for the front arm when it is NOT aim-tracking.
## Leave empty to inherit from the body animation.
@export var front_arm_animation: StringName = &""

## Animation clip name for the back arm when it is NOT aim-tracking.
## Leave empty to inherit from the body animation.
@export var back_arm_animation: StringName = &""

## ---- Weapon Attachment ----

## Scene to instantiate as the held weapon (e.g., a Sprite2D with offset).
## null = no weapon visible in this state.
@export var weapon_scene: PackedScene

## Which hand holds the weapon.
@export_enum("None", "Front", "Back") var weapon_hand: String = "None"

## ---- Arm Sequencing (for alternating arm patterns) ----

## Enable multi-step arm sequences (e.g., Spatchcock's alternating flintlocks).
## When true, the rig reads from sequence_steps instead of the single aim_arm_flags.
@export var use_arm_sequence: bool = false

## Each step defines a full arm state. The rig advances to the next step
## on each "advance_sequence" call (typically on fire or cooldown start).
## After the last step, it wraps back to step 0.
@export var sequence_steps: Array[ArmSequenceStep] = []

## ---- Transition ----

## How quickly arms blend into this pose (seconds). 0 = instant snap.
@export var blend_in_time: float = 0.15

## Animation to play as a one-shot when ENTERING this weapon state.
## e.g., "draw_flintlock", "open_tome". Leave empty for no transition.
@export var enter_animation: StringName = &""

## Animation to play as a one-shot when EXITING this weapon state.
## e.g., "holster_flintlock", "close_tome". Leave empty for no transition.
@export var exit_animation: StringName = &""
