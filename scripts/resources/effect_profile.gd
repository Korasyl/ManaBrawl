extends Resource
class_name EffectProfile

## EffectProfile — A reusable data bundle defining what VFX, SFX, and screen
## feedback to trigger for a specific game event.
##
## USAGE:
## Create .tres resources for different events and assign them to:
## - MeleeAttackData.effect_profile (attack impacts)
## - SpellData (spell cast/impact effects)
## - WeaponPoseData (weapon draw/holster effects)
## - Or call Effects.play_profile(profile, position) directly
##
## EXAMPLES:
##   light_hit.tres     — small spark, quiet thwack, mild shake
##   heavy_hit.tres     — big impact burst, loud slam, strong shake + hitstop
##   shield_break.tres  — shatter particles, glass crack sfx, big shake
##   block_hit.tres     — small spark on shield, metallic clang, no shake
##   clash.tres         — crossed sparks, sword clang, mutual shake
##   spell_cast.tres    — magic swirl at hand, woosh sfx
##   flintlock_fire.tres — muzzle flash, gunshot sfx, small shake

## ---- VFX ----

## Particle/VFX scene to spawn at the effect position.
@export var vfx_scene: PackedScene

## Scale of the spawned VFX.
@export var vfx_scale: Vector2 = Vector2.ONE

## Rotation offset (degrees) applied to the VFX.
@export var vfx_rotation: float = 0.0

## ---- SFX ----

## Sound effect to play.
@export var sfx_stream: AudioStream

## Volume adjustment (dB). 0 = default, negative = quieter.
@export var sfx_volume_db: float = 0.0

## Random pitch variance (0 = none, 0.1 = ±10% pitch randomization).
## Adds natural variation so repeated hits don't sound identical.
@export var sfx_pitch_variance: float = 0.05

## ---- Screen Feedback ----

## Screen shake intensity (pixels of displacement). 0 = no shake.
@export var shake_intensity: float = 0.0

## Screen shake duration (seconds).
@export var shake_duration: float = 0.0

## Hitstop freeze duration (seconds). 0 = no hitstop.
@export var hitstop_duration: float = 0.0

## ---- Hit Flash ----

## Whether to flash the target white on hit.
@export var apply_hit_flash: bool = true

## Flash color (usually white or a tinted version).
@export var hit_flash_color: Color = Color.WHITE

## Flash duration in seconds.
@export var hit_flash_duration: float = 0.08
