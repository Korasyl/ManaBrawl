# ManaBrawl Animation Framework Guide

## Architecture Overview

```
CharacterStats
├── rig_scene ──────────► CrayolaRig (per-character scene)
│                         ├── AnimationPlayer   (all animation clips)
│                         ├── AnimationTree     (body/arm/oneshot blending)
│                         ├── Skeleton pivots   (Node2D body part hierarchy)
│                         └── WeaponSprite      (attached dynamically)
│
├── default_weapon_pose ─► WeaponPoseData (arm behavior when idle)
├── ranged_mode ─────────► RangedModeData.weapon_pose (arm behavior when aiming)
├── light_attack_data ───► MeleeAttackData (attack animation + hitbox timing)
├── heavy_attack_data ───► MeleeAttackData
└── combo_light_data ────► MeleeAttackData (optional second light variant)

SpellData.weapon_pose ───► WeaponPoseData (arm behavior when casting)
```

### Data Flow Every Frame

```
player._physics_process()
  → update_animation()
      → rig.set_body_animation("walk")
          → AnimationTree body state machine transitions
  → update_arms()
      → Resolve pose: spell > ranged > default
      → rig.apply_weapon_state(pose)  [on change only]
          → Blend targets, weapon attach, enter/exit anims
      → rig.update_arm_aim(active, mouse_pos)
          → Code overrides aiming arm rotations

On melee attack:
  → perform_light_attack() / perform_heavy_attack()
      → rig.play_melee_attack(attack_data)
          → One-shot animation overlays
          → Hitbox timing via anim events OR timer fallback

On ranged fire:
  → rig.advance_sequence()
      → Next ArmSequenceStep activates
      → Weapon hand swaps, transition anim plays
```

---

## File Placement

```
scripts/
├── visuals/
│   ├── crayola_rig.gd           ← Base rig class (REPLACE existing)
│   └── weapon_sprite.gd         ← NEW — weapon visual base class
├── combat/
│   ├── ranged_mode_data.gd      ← REPLACE (adds weapon_pose)
│   ├── spell_data.gd            ← REPLACE (adds weapon_pose)
│   └── melee_attack_data.gd     ← NEW — per-character attack defs
├── character_stats.gd           ← REPLACE (adds rig_scene, weapon pose, melee data)
└── resources/
    ├── weapon_pose_data.gd      ← NEW — arm/weapon behavior per state
    └── arm_sequence_step.gd     ← NEW — alternating arm patterns

characters/
├── crayola_rig.tscn             ← UPDATE (add AnimationPlayer + AnimationTree)
├── rigs/                        ← NEW folder for per-character rigs
│   ├── spatchcock_rig.tscn
│   ├── fervor_rig.tscn
│   ├── zip_rig.tscn
│   ├── borealis_rig.tscn
│   └── aegis_rig.tscn
└── weapons/                     ← NEW folder for weapon sprites
    ├── flintlock.tscn
    ├── tome.tscn
    ├── amethyst_staff.tscn
    ├── ice_staff.tscn
    └── shield.tscn

resources/
├── weapon_poses/                ← NEW folder
│   ├── spatchcock_theatre.tres
│   ├── spatchcock_flintlock.tres
│   ├── fervor_tome_cast.tres
│   ├── zip_staff_rifle.tres
│   ├── borealis_spear.tres
│   └── aegis_shield.tres
└── melee_attacks/               ← NEW folder
    ├── generic_light.tres
    ├── generic_heavy.tres
    ├── aegis_punch.tres
    ├── aegis_bash.tres
    ├── borealis_jab.tres
    ├── borealis_sweep.tres
    └── spatchcock_slap.tres
```

---

## System 1: Character Rigs

### Creating a New Rig

1. Duplicate `crayola_rig.tscn` → `characters/rigs/[name]_rig.tscn`
2. Replace sprite textures with character art
3. Adjust pivot positions for different proportions
4. Add `AnimationPlayer` as a direct child of root
5. Create animation clips (see below)
6. Optionally add `AnimationTree` for blending
7. If character needs custom logic, create `[name]_rig.gd` extending `CrayolaRig`

### Character-Specific Rig Subclasses

For characters that need custom behavior beyond data:

```gdscript
# scripts/visuals/aegis_rig.gd
extends CrayolaRig
class_name AegisRig

## Aegis has a shield collision area on his back arm for projectile deflection.
@onready var shield_area: Area2D = $Skeleton2D/StomachPivot/ChestPivot/BackArmPivot/ShieldArea

func _ready() -> void:
    super._ready()
    shield_area.monitoring = false  # Only active during block

func set_shield_blocking(active: bool) -> void:
    shield_area.monitoring = active
```

```gdscript
# scripts/visuals/fervor_rig.gd
extends CrayolaRig
class_name FervorRig

## Fervor's tome emits particles while open.
var _tome_particles: GPUParticles2D = null

func _on_anim_event(event_name: String) -> void:
    super._on_anim_event(event_name)
    match event_name:
        "tome_open":
            _start_tome_particles()
        "tome_close":
            _stop_tome_particles()

func _start_tome_particles() -> void:
    var ws := get_weapon_sprite()
    if ws and ws.effect_anchor:
        # Spawn particle emitter at tome's effect anchor
        pass
```

### Required Body Animations

Create these clips in the AnimationPlayer. Keyframe legs, torso, head
(NOT arms — arms are handled by the weapon pose system).

| Animation         | Type       | Duration  | Notes                           |
|-------------------|------------|-----------|----------------------------------|
| idle              | Loop       | ~1.0s     | Subtle breathing                 |
| walk              | Loop       | ~0.6s     | Leg cycle, slight torso lean     |
| walk_back         | Loop       | ~0.6s     | Reversed lean                    |
| sprint            | Loop       | ~0.4s     | Wider stride, more lean          |
| sprint_back       | Loop       | ~0.4s     | Reversed sprint                  |
| crouch            | Static/Loop| —         | Legs bent, torso lowered         |
| crouchwalk        | Loop       | ~0.6s     | Low walk                         |
| crouchwalk_back   | Loop       | ~0.6s     | Reversed                         |
| jump              | Static     | —         | Legs tucked                      |
| fall              | Static/Loop| —         | Legs extended                    |
| hit               | One-shot   | ~0.2s     | Recoil                           |
| block             | Static     | —         | Guard stance                     |
| dash              | One-shot   | ~0.2s     | Streamlined forward              |
| wall_cling        | Static     | —         | Pressed to wall                  |
| wall_slide        | Loop       | ~0.4s     | Sliding down                     |
| coalesce_ground   | Loop       | ~0.8s     | Channeling (grounded)            |
| coalesce_air      | Loop       | ~0.8s     | Channeling (airborne)            |
| coalesce_wall     | Loop       | ~0.8s     | Channeling (wall)                |
| ledge_grab        | Static     | —         | Hanging                          |
| ledge_clamber     | One-shot   | ~0.4s     | Pulling up                       |

**Missing animation fallback:** If a clip doesn't exist yet, the rig
automatically falls back to "idle" and prints a one-time warning.
Build rigs incrementally — you won't crash from missing clips.

### Keyframing Tips

- Select a pivot node → Inspector → `rotation` → click key icon
- Move timeline playhead → adjust rotation → key again
- Set "Loop" wrap mode for looping anims in animation properties
- Use "Onion Skinning" to preview previous/next frames overlaid
- For walk cycles: key at 0%, 25%, 50%, 75%, 100% of cycle

---

## System 2: Arm Animations

Arm-only clips that play on non-aiming arms. Only keyframe arm bone pivots
(under Skeleton2D): `FrontArmPivot`, `FrontForearmPivot`, `BackArmPivot`, `BackForearmPivot`

**Naming convention:** `arm_[description]`

| Clip Name            | Character   | Description                        |
|----------------------|-------------|------------------------------------|
| arm_hold_tome        | Fervor      | Back arm cradling book at chest    |
| arm_brace_rifle      | Zip         | Back arm supporting front (grip)   |
| arm_hip_rest         | Generic     | Arm relaxed at hip                 |
| arm_flintlock_hold   | Spatchcock  | Arm extended holding pistol        |
| arm_theatre_idle     | Spatchcock  | Dramatic resting pose              |
| arm_shield_guard     | Aegis       | Back arm with shield raised        |
| arm_fist_ready       | Aegis       | Front arm in punching stance       |
| arm_spear_brace      | Borealis    | Back arm bracing spear shaft       |

---

## System 3: One-Shot Animations

Overlay animations for attacks, transitions, flourishes. These play on
top of everything via the AnimationTree's OneShot node.

**Naming convention:** `oneshot_[description]`

| Clip Name                    | Character   | Use                               |
|------------------------------|-------------|------------------------------------|
| oneshot_light_attack         | Generic     | Quick jab/slash                    |
| oneshot_heavy_attack         | Generic     | Wind-up and swing                  |
| oneshot_draw_flintlock       | Spatchcock  | Hand reaches into coat, pulls gun  |
| oneshot_toss_flintlock_front | Spatchcock  | Front arm flicks gun over shoulder |
| oneshot_toss_flintlock_back  | Spatchcock  | Back arm flicks gun                |
| oneshot_open_tome            | Fervor      | Arm brings tome up, opens it       |
| oneshot_close_tome           | Fervor      | Closes and lowers tome             |
| oneshot_punch                | Aegis       | Quick punch jab                    |
| oneshot_shield_bash          | Aegis       | Shield forward slam                |
| oneshot_spear_jab            | Borealis    | Quick thrust                       |
| oneshot_spear_sweep          | Borealis    | Wide sweeping arc                  |
| oneshot_staff_blast          | Zip         | Staff recoil after firing          |
| oneshot_slap                 | Spatchcock  | Theatrical slap                    |

---

## System 4: Animation Events

Godot's AnimationPlayer supports **method call tracks** — keyframes that
call a function at a specific point in the animation.

### Setup in Editor

1. Open your attack animation in the AnimationPlayer
2. Click "Add Track" → "Call Method Track"
3. Set the target node to the CrayolaRig root
4. Add keyframes calling `_on_anim_event` with a String argument

### Standard Event Names

| Event Name     | Purpose                                      | When to Use                    |
|---------------|----------------------------------------------|--------------------------------|
| `hitbox_on`   | Activate melee hitbox                         | Frame where swing connects     |
| `hitbox_off`  | Deactivate melee hitbox                       | End of active frames           |
| `impact`      | Moment of peak impact                         | Screen shake, particles        |
| `spawn_vfx`   | Spawn a visual effect                        | Muzzle flash, swing trail      |
| `play_sfx`    | Play a sound effect                          | Whoosh, clang, gunshot         |
| `weapon_show` | Make weapon sprite visible                   | After draw animation           |
| `weapon_hide` | Hide weapon sprite                           | During holster animation       |
| `step_left`   | Left footstep                                | Walk cycle contact frame       |
| `step_right`  | Right footstep                               | Walk cycle contact frame       |

### Custom Events

Use any string — it's emitted via the `anim_event` signal for the player
or character-specific rig subclass to react to:

```gdscript
# In a Spatchcock rig subclass:
func _on_anim_event(event_name: String) -> void:
    super._on_anim_event(event_name)
    match event_name:
        "flintlock_release":
            _spawn_tossed_flintlock_vfx()
        "coat_reach":
            _play_coat_rustle_sfx()
```

### Hitbox Timing: Anim Events vs Timer Fallback

**Option A — Anim events (recommended for final animations):**
Set `MeleeAttackData.use_anim_events = true`. Add `hitbox_on` and
`hitbox_off` method call keyframes in the attack animation.
Frame-perfect hitbox sync.

**Option B — Timer fallback (good for prototyping):**
Set `MeleeAttackData.use_anim_events = false`. Configure
`hitbox_active_start` and `hitbox_active_end` as seconds.
Works without animation events — good for blocking out timing.

---

## System 5: Melee Attacks

### MeleeAttackData Resource

Each character defines their attacks as `MeleeAttackData` resources
assigned on `CharacterStats`:

```
CharacterStats
├── light_attack_data       → first light in combo
├── heavy_attack_data       → heavy attack
└── combo_light_attack_data → second light in combo (optional, different anim)
```

### Example Configurations

**Aegis — Punch (Light):**
```
attack_name: "Punch"
animation_name: "oneshot_punch"
duration: 0.3
hitbox_active_start: 0.05
hitbox_active_end: 0.2
use_anim_events: false  (switch to true once anim is keyframed)
```

**Aegis — Shield Bash (Heavy):**
```
attack_name: "Shield Bash"
animation_name: "oneshot_shield_bash"
duration: 0.5
use_anim_events: true  (hitbox_on/off keyframed in animation)
weapon_pose_override: [shield forward pose]
impact_event_name: "shield_impact"
```

**Spatchcock — Theatrical Slap (Light):**
```
attack_name: "Slap"
animation_name: "oneshot_slap"
duration: 0.25
hitbox_active_start: 0.08
hitbox_active_end: 0.18
```

---

## System 6: Weapon Sprites

### WeaponSprite Base Class

All held weapons extend `WeaponSprite`, which provides standardized
marker points for effects:

```
WeaponSprite (Node2D + script)
├── Sprite2D          (weapon texture, positioned so grip is at origin)
├── MuzzlePoint       (Marker2D — projectile/flash spawn point)
├── EffectAnchor      (Marker2D — persistent effect attachment)
├── TrailOrigin       (Marker2D — motion trail emission point)
├── ImpactPoint       (Marker2D — hit spark spawn point)
└── AnimationPlayer   (optional — weapon idle anim like crystal pulse)
```

### Positioning

The weapon is parented to a forearm pivot, so **origin (0,0) = where
the hand grips**. Offset the Sprite2D so the grip point sits at origin:

```
Flintlock:  Sprite2D.offset = Vector2(-2, -12)  (grip near bottom)
Staff:      Sprite2D.offset = Vector2(-3, -40)  (grip at middle)
Shield:     Sprite2D.offset = Vector2(-8, -16)  (grip at handle)
Tome:       Sprite2D.offset = Vector2(-6, -10)  (cradled in palm)
```

### Accessing Weapon Data at Runtime

```gdscript
# From player code:
var ws: WeaponSprite = WeaponSprite.get_from_rig(crayola_rig)
if ws:
    var muzzle_pos := ws.get_muzzle_position()
    ws.spawn_effect_at("muzzle", muzzle_flash_scene)
    ws.play_weapon_animation("fire_recoil")

# From rig code:
var spawn_pos := get_projectile_spawn_position()  # auto-uses muzzle if available
```

---

## System 7: Weapon Poses

### WeaponPoseData Resource

Controls which arms aim, which animate, weapon attachment, and sequencing.

### Per-Character Configurations

#### Spatchcock

**Default (Theatre Stance):**
```
aim_arm_flags: None (0)
front_arm_animation: "arm_theatre_idle"
back_arm_animation: "arm_theatre_idle"
weapon_scene: null
weapon_hand: Front
```

**Ranged (Flintlock Juggle):**
```
aim_arm_flags: Front (1)
use_arm_sequence: true
sequence_steps:
  [0] flags=1, hand="Front"    (front aims with gun)
  [1] flags=0, auto=0.3        (toss animation, no aim)
      transition: "oneshot_toss_flintlock_front"
  [2] flags=2, hand="Back"     (back aims with new gun)
  [3] flags=0, auto=0.3        (toss from back)
      transition: "oneshot_toss_flintlock_back"
weapon_scene: flintlock.tscn
enter_animation: "oneshot_draw_flintlock"
exit_animation: "oneshot_toss_flintlock_front"
```

#### Fervor

**Default & Casting (Tome + Cast Hand):**
```
aim_arm_flags: Front (1)
back_arm_animation: "arm_hold_tome"
weapon_scene: tome.tscn
weapon_hand: Back
enter_animation: "oneshot_open_tome"
exit_animation: "oneshot_close_tome"
```

#### Zip

**Ranged (Staff Rifle):**
```
aim_arm_flags: Both (3)
back_arm_animation: "arm_brace_rifle"
weapon_scene: amethyst_staff.tscn
weapon_hand: Front
```

#### Borealis

**Default (Ice Spear):**
```
aim_arm_flags: Front (1)
back_arm_animation: "arm_spear_brace"
weapon_scene: ice_staff.tscn
weapon_hand: Front
```

#### Aegis

**Default (Shield + Fist):**
```
aim_arm_flags: None (0)
front_arm_animation: "arm_fist_ready"
back_arm_animation: "arm_shield_guard"
weapon_scene: shield.tscn
weapon_hand: Back
```

---

## System 8: AnimationTree Setup

### Node Graph Structure

```
AnimationNodeBlendTree (root)
│
├── body_state: AnimationNodeStateMachine
│   Contains all body animations with transitions:
│   idle ←→ walk ←→ sprint
│   idle ←→ crouch ←→ crouchwalk
│   idle → jump → fall → idle
│   idle → hit → idle
│   idle → dash → idle
│   (etc.)
│
├── front_arm_blend: AnimationNodeBlend2
│   Input 0 (blend=0): front_arm_anim (AnimationNodeAnimation)
│   Input 1 (blend=1): [empty — code drives rotation]
│
├── back_arm_blend: AnimationNodeBlend2
│   Input 0 (blend=0): back_arm_anim (AnimationNodeAnimation)
│   Input 1 (blend=1): [empty — code drives rotation]
│
├── oneshot: AnimationNodeOneShot
│   Base: [output from body + arm blend chain]
│   Shot: oneshot_anim (AnimationNodeAnimation)
│
└── Output

Parameter paths (must match exactly):
  parameters/body_state/playback
  parameters/front_arm_blend/blend_amount
  parameters/back_arm_blend/blend_amount
  parameters/front_arm_anim/animation
  parameters/back_arm_anim/animation
  parameters/oneshot/request
  parameters/oneshot_anim/animation
```

### Simpler Alternative (No AnimationTree)

Skip the AnimationTree entirely. The rig falls back gracefully:
- Body anims play via `anim_player.play()`
- Code-driven arm aiming overrides pivot rotations after anim updates
- One-shots play via `anim_player.play()` (interrupts body anim briefly)

Good for prototyping. Upgrade to AnimationTree when you need smooth
body-to-arm blending.

---

## Debugging

### Missing Animation Warnings

The rig prints a one-time warning for each missing animation:
```
CrayolaRig: Animation 'wall_cling' not found — falling back to 'idle'.
Create this clip in the AnimationPlayer.
```

### Debug HUD Integration

Add to your debug HUD update:
```gdscript
if crayola_rig:
    debug_hud.update_custom("Aim Flags", str(crayola_rig.get_current_aim_flags()))
    debug_hud.update_custom("Seq Step", str(crayola_rig.get_sequence_index()))
    debug_hud.update_custom("Body Anim", crayola_rig._current_body_anim)
    var ws := crayola_rig.get_weapon_sprite()
    if ws:
        debug_hud.update_custom("Weapon", ws.name)
    var melee := crayola_rig.get_active_melee_attack()
    if melee:
        debug_hud.update_custom("Attack", melee.attack_name)
```

### Testing Without Full Art

You can test the entire system with colored rectangles:
- Weapon sprites: small colored `ColorRect` nodes instead of `Sprite2D`
- Body parts: keep existing crayola placeholder textures
- Animations: keyframe rough rotations to verify timing

The framework is fully functional with placeholders. Art upgrades
are texture/offset swaps, not code changes.
