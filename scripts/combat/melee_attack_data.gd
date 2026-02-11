extends Resource
class_name MeleeAttackData

## MeleeAttackData — Defines a single melee attack's animation and timing.
##
## Each character can have unique light/heavy attacks with different animations,
## hitbox timings, and weapon poses. Assigned via CharacterStats.
##
## SETUP GUIDE:
## 1. Create a MeleeAttackData resource for each attack type (light, heavy, combo light)
## 2. Set the animation name to match a clip in the character's rig AnimationPlayer
## 3. Configure hitbox timing relative to the animation
## 4. Optionally set a weapon pose override for the attack
##
## ANIMATION EVENT INTEGRATION:
## Instead of using hitbox_active_start/end timers, you can use AnimationPlayer
## method call tracks to call "anim_event_hitbox_on" and "anim_event_hitbox_off"
## on the rig. Set use_anim_events = true to use this approach.
## This gives frame-perfect hitbox control synced to the animation.
##
## EXAMPLES:
##   Aegis Light: punch animation, short duration, fist hitbox
##   Aegis Heavy: shield bash, longer windup, wide hitbox
##   Borealis Light: quick spear jab, narrow hitbox
##   Borealis Heavy: sweeping spear arc, wide hitbox with knockback
##   Spatchcock Light: theatrical slap, fast
##   Spatchcock Heavy: dramatic overhead swing, slow with flair

## ---- Identity ----

## Display name (for debug HUD / tooltips)
@export var attack_name: String = "Attack"

## ---- Animation ----

## One-shot animation name played on the rig when this attack executes.
## Must match a clip in the character's rig AnimationPlayer.
## Convention: "oneshot_light_1", "oneshot_light_2", "oneshot_heavy", etc.
@export var animation_name: StringName = &"oneshot_light_attack"

## If true, hitbox activation is driven by animation method call tracks
## instead of the timer-based hitbox_active_start/end values.
## The animation should call _on_anim_event("hitbox_on") and _on_anim_event("hitbox_off").
@export var use_anim_events: bool = false

## ---- Timing ----

## Total duration of the attack (seconds). After this, attack ends.
## Should match or slightly exceed the animation length.
@export var duration: float = 0.3

## When the hitbox becomes active (seconds into the attack).
## Ignored if use_anim_events = true.
@export var hitbox_active_start: float = 0.05

## When the hitbox deactivates (seconds into the attack).
## Ignored if use_anim_events = true.
@export var hitbox_active_end: float = 0.25

## Heavy attack windup time (how long LMB must be held). Only relevant for heavy attacks.
@export var charge_time: float = 0.5

## ---- Weapon Pose ----

## Optional weapon pose override during this attack.
## e.g., Aegis punches with fist forward (different from his shield guard stance).
## If null, the current active pose remains.
@export var weapon_pose_override: WeaponPoseData

## ---- VFX / SFX ----

## Complete effect profile for this attack's impact (VFX + SFX + shake + hitstop).
## Played via the EffectManager when the attack connects.
## If null, falls back to generic hit feedback based on light/heavy.
@export var effect_profile: EffectProfile

## Additional per-attack VFX/SFX for backwards compat or simple overrides:

## Animation event fired at the moment of impact (for screen shake, hit flash, etc.)
## The rig calls _on_anim_event(impact_event_name) at the keyframed moment.
@export var impact_event_name: String = "impact"

## Particle/VFX scene to spawn at the hitbox position on activation.
## null = no VFX.
@export var swing_vfx_scene: PackedScene

## Sound effect to play on attack start.
@export var start_sfx: AudioStream

## Sound effect to play on hit connection.
@export var hit_sfx: AudioStream
