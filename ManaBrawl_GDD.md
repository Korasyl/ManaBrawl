# Mana Brawl - Game Design Document

**Version:** 0.1 (Foundation Phase)  
**Last Updated:** February 3, 2026  
**Game Type:** 2D Platform Brawler  
**Target Mode:** 4v4 Team-based Objective PvP  
**Development Status:** Prototype/Demo Phase

---

## Table of Contents
1. [Core Concept](#core-concept)
2. [Control Scheme](#control-scheme)
3. [Movement Systems](#movement-systems)
4. [Resource Management](#resource-management)
5. [Combat Systems](#combat-systems)
6. [Spell System](#spell-system)
7. [Character Roles](#character-roles)
8. [Attunements System](#attunements-system)
9. [Technical Implementation](#technical-implementation)

---

## Core Concept

**Elevator Pitch:**  
Mana Brawl is a 2D platform brawler that combines the movement mechanics of Super Smash Bros/Brawlhalla with the team-based objective gameplay of hero shooters like Overwatch.

**Key Features:**
- 4v4 team-based objective PvP
- Character roster with distinct roles (Offense, Defense, Support, Hybrid)
- Deep resource management through Mana system
- Skill-based movement with advanced techniques
- Customizable playstyles through Attunements

**Core Gameplay Loop:**
Players select a character from the roster, equip Attunements to customize their playstyle, then compete in team-based matches where they must manage Mana resources while executing combos, supporting teammates, and achieving objectives.

---

## Control Scheme

### Keyboard & Mouse Layout

**Movement:**
- `A` / `Left Arrow` - Move Left
- `D` / `Right Arrow` - Move Right
- `S` / `Down Arrow` - Crouch
- `W` / `Up Arrow` - Jump
- `Shift` - Sprint (hold)
- `Spacebar` - Dash

**Combat:**
- `Left Mouse Click` (tap) - Light Attack
- `Left Mouse Click` (hold >0.5s) - Heavy Attack
- `Right Mouse Button` (hold) - Ranged Mode / Character-Specific Mode

**Utility:**
- `Alt` - Block
- `C` - Coalescence (Mana Regeneration)
- `Q` - Cancel Queued Spell

**Spells:**
- `1` - Spell Slot 1
- `2` - Spell Slot 2
- `3` - Spell Slot 3
- `4` - Spell Slot 4

---

## Movement Systems

### Basic Movement (Universal)
All characters have access to these movements, with varying speeds and properties:

**Walk**
- Default movement speed
- Full directional control

**Sprint**
- Hold Shift while moving
- Significantly faster than walking
- Cannot sprint while crouching

**Crouch**
- Hold S to crouch
- Slower movement speed (crouch-walking)
- May have mechanical benefits (to be determined)

**Jump**
- Press W to jump
- Jump height varies by character
- Maintains horizontal momentum from ground state

**Wall Slide**
- Automatic when touching wall while falling
- Reduces fall speed
- Cannot be touching ground

### Advanced Movement (Mana-Based)
These techniques require Mana and offer skilled players mobility advantages:

**Double Jump**
- Press W again while airborne
- Uses Mana (default: 15)
- Resets on landing or wall jump
- Can only be used once per air time

**Dash**
- Press Spacebar
- Expensive Mana cost (default: 35)
- Brief cooldown (default: 0.5s)
- Grants invulnerability frames (i-frames)
- Dashes in current movement direction, or forward if standing still
- Cannot be spammed due to cooldown

**Wall Cling**
- Hold directional input into wall while airborne
- Stops all falling (velocity = 0)
- Drains Mana over time (default: 1/second)
- If Mana runs out, automatically transitions to Wall Slide
- Can be maintained indefinitely with sufficient Mana

**Wall Jump**
- Press W while Wall Sliding or Wall Clinging
- Uses Mana (default: 10)
- Jumps AWAY from the wall with horizontal boost
- Resets Double Jump
- Brief input lock (0.2s) prevents immediate return to wall

### Air Control & Momentum
- When jumping from ground, character maintains their ground speed in air
- Sprint jumping = fast air speed
- Walk jumping = normal air speed
- Standing jump = allows walk-speed air control
- Wall Jump creates brief input lock to ensure launch direction

---

## Resource Management

Every character has two primary resources:

### Health
- Character's life total
- Varies by character
- Depleted by taking damage
- (Regeneration mechanics TBD)

### Mana
- Fuel for advanced movement and spells
- Maximum amount varies by character
- Three methods of regeneration:

#### 1. Passive Regeneration
- Constant, slow regeneration (default: 5/second)
- Always active
- Negated by Wall Cling drain (1/second drain counters passive)

#### 2. Melee Hit Regeneration
- Gain Mana when landing melee attacks
- **Clean Hit:** Full Mana gain (Heavy > Light)
- **Blocked Hit:** Minor Mana gain
- **Shield Break (Heavy):** Significant bonus Mana
- **Clash:** No Mana gain (attack cancelled)

#### 3. Coalescence (Active Ability)
- Hold `C` to enter meditation state
- **Startup:** 1 second vulnerable period before regen begins
- **Regen Rate:** 4x passive regeneration (default: 20/second)
- **Restrictions:** Cannot move, completely vulnerable
- **Cancelling:** Release C to cancel
- **Recovery:** 0.5 second delay before can act again, cannot cast spells for three seconds
- **Interrupt:** Immune to Flinch, vulnerable to Stagger
- **Strategic Use:** Requires safe positioning or team protection

---

## Combat Systems

### Attack Types

#### Melee Attacks

**Light Attack**
- Input: Tap Left Mouse Button
- Fast, low damage
- Inflicts **Flinch** on hit
- Can combo into second Light Attack or Heavy attack if first lands
- Grants Mana on hit

**Heavy Attack**
- Input: Hold Left Mouse Button (>0.5 seconds)
- Slow, high damage
- Inflicts **Stagger** on hit
- Causes **Knockback** (creates spacing)
- **Flinch Immunity:** Cannot be flinched during windup
- **Stagger Vulnerable:** Can be interrupted by Stagger
- **Shield Break:** Destroys block, grants bonus Mana
- Grants more Mana than Light Attack

**Combo System**
- First Light Attack → If it Flinches → Can combo into second melee attack
- Mix-up Option: Can throw light attack, quicker than first light attack (can be blocked or dashed, safer option to heavy combo, quick recovery)
- Mix-up Option: Can throw Heavy instead of second Light (can break shield, catch early dashes, Flinch immune, slower recovery)
- Melee cooldown after combo, prevents spam.

#### Ranged Attacks

**Basic Ranged**
- Hold Right Mouse Button to enter Ranged Mode
- Character aims at mouse cursor
- Left Click to fire projectile
- Can move while in Ranged Mode (speed may vary)
- Some characters replace this with unique modes (e.g., Aegis's shield deflect)

**Character-Specific Ranged Modes**
- Example: Aegis (Tank) holds up shield and deflects basic ranged attacks at angles, Fervor has a targeted ranged attack instead of free-aim, Gravebrand has short ranged projectiles that can intercept other projectiles
- Mode varies by character design and theme

### Interrupt Mechanics

**Flinch (Light Interrupt)**
- Sources: Light Attacks, Basic Ranged, some Spells
- Effect: Brief hitstun, interrupts most actions
- **Cannot Interrupt:** Heavy Attack windup, Spell Casting, other Flinch-immune states
- Duration: Standard hitstun duration
- Defender can Dash out if they have resources

**Stagger (Heavy Interrupt)**
- Sources: Heavy Attacks (on hit), certain Spells
- Effect: Interrupts EVERYTHING, including Flinch-immune actions
- Duration: Same as Flinch (but breaks through block)
- Knockback: Opens space and creates area-denial

**Clash System**
- Occurs when two attacks hit simultaneously
- **Light vs Light:** Both attacks cancelled, no damage, no Flinch
- **Heavy vs Heavy:** Both attacks cancelled, mutual knockback, no damage
- Rewards timing and spacing, punishes spam

### Defensive Mechanics

**Block**
- Hold `Alt` to block
- **Cost:** Constant Mana drain while active
- **Effect:** Stops Light Attacks, Basic Ranged, and projectile Spells
- **Movement Penalty:** Significantly slows movement
- **Weakness:** Heavy Attacks **Shatter** the block
  - No damage dealt on Shield Break
  - No knockback on Shield Break
  - Block disabled for 2-3 seconds
  - Attacker gains significant bonus Mana
- Cannot block while airborne (ground only)

**Dash (Defensive Use)**
- Press Spacebar
- Grants invulnerability frames (i-frames)
- Prevents all damage during dash duration
- Expensive Mana cost (35)
- Has cooldown (0.5s)
- Can be used to escape combos, timing required for mix-ups

**Movement/Spacing**
- Free defensive option
- Requires prediction and positioning
- No resource cost

**Counterspell(TBD, Not Guaranteed)**
- Press Q to perform (TBD)
- Potential mechanic to counter targeted spells
- Requires precise prediction
- Heavy resource cost

---

## Spell System

Every character has **4 unique spells** bound to keys 1, 2, 3, and 4.

### Spell Properties
- Each spell has unique Mana cost
- Each spell has unique cooldown
- Both Mana AND cooldown must be available to cast

### Spell Casting Types

#### Targeted Spells
- Press spell key → Enter **Queued State**
- Move mouse cursor to select target
- Target = closest enemy/ally near cursor
- Press Left Click → Cast on selected target
- Requires valid target to cast
- Examples: Single-target heals, buffs, debuffs, targeted damage

#### Free-Aim Spells
- Press spell key → Enter **Queued State**
- Aims like Ranged Mode (at mouse cursor)
- Press Left Click → Fire/cast at cursor location
- Examples: Skillshot projectiles, ground-target AoE, directional blasts

#### Toggled Spells
- Press spell key → **Activate immediately** (no queue)
- Press spell key again → Deactivate
- Typically drains Mana over time while active
- May have initial activation cost
- Examples: Auras, buffs, special modes, damage zones

### Spell Queue Management
- Can cancel Queued spell by pressing the same spell key again
- Cannot perform melee or ranged attacks while queuing a spell
- Pressing a different Targeted/Free-Aim spell key cancels current queue and starts new queue
- Pressing a Toggled spell does NOT cancel current queue (can activate aura while queuing targeted heal)

### Spell Interrupts
- **Queued Spells:** Vulnerable to Stagger during queue state
- **Toggled Spells/Auras:** Cannot be removed by Stagger, only by Counterspells/Dispels

### Spell Variables (Per-Spell Modifiers)
Spells can have custom properties that modify character behavior:
- `preventMove` - Locks player in place during cast
- `slowMove` - Reduces movement speed during cast
- Additional modifiers as needed per spell design

---

## Character Roles

Characters are categorized into four roles based on their strengths:

### Offense
- **Strengths:** High damage output, high mobility
- **Weaknesses:** Low health, fragile
- **Playstyle:** Glass cannon, burst damage, flanking
- **Example:** Bolt (Lightning-themed, fast movement, low health, high damage)

### Defense
- **Strengths:** High health, tankiness, area control
- **Weaknesses:** Low damage output, low mobility
- **Playstyle:** Frontline, protecting teammates, absorbing damage
- **Example:** Aegis (Shield-based tank, unique block-deflect mode)

### Support
- **Strengths:** Healing, buffs, utility
- **Weaknesses:** Low health, dies easily
- **Playstyle:** Backline support, enabling teammates
- **Example:** TBD

### Hybrid
- **Strengths:** Balanced stats, versatile
- **Weaknesses:** Not exceptional in any one area
- **Playstyle:** Flexible, adapts to team needs
- **Example:** TBD

### Role Implementation
- Roles differentiated through stat distributions (speed, health, Mana, jump height)
- Roles reinforced through unique spell kits
- Attunements can shift role focus (e.g., Offense character can spec into durability)

---

## Attunements System

Attunements are the primary **customization and build system** in Mana Brawl.

### Core Mechanics
- Players equip 3 Universal Attunements, 1 Role-Specific Attunement, and 1 Character-Specific Attunement per character
- Attunements are equipped in Character Select menu
- Cannot be changed mid-match
- Unlocking system TBD (see Progression section)

### Attunement Types

#### Universal Attunements (Any Character)
Simple stat trades and adjustments:
- **+Mana Pool / -Health**
- **+Health / -Mana Pool**
- **+Movement Speed / +Advanced Movement Costs**
- **+Jump Height / -Speed**
- Generic modifications available to all characters

#### Role-Specific Attunements
Alter mechanics that can better reflect on specific playstyles, or add utility in exchange for other things

#### Character-Specific Attunements
Fundamentally change abilities and playstyles:

**Example: Bolt (Offense) Attunements**
- **"Shock Dash":** Dash Flinches enemies on contact, but significantly increases Mana cost
- **"Chain Lightning":** Changes basic ranged from free-aimed lightning bolt → close-range auto-targeting continuous arc

**Design Philosophy:**
- Character-specific attunements create build variety within a single character
- Same character can be played radically differently based on attunement loadout
- Encourages experimentation and meta-game depth
- Rewards mastery and adaptation

### Progression & Unlocking (Proposed)

**For Demo/Kickstarter:**
- All attunements unlocked by default
- Shows off system depth immediately
- No grind barriers for reviewers/testers

**For Full Game (Hybrid System):**
- **Universal Attunements:** Unlocked with universal currency earned from matches
- **Character-Specific Attunements:** Unlocked by playing that character (character levels)
- **Benefits:**
  - Rewards both general play time AND character specialization
  - Provides progression without excessive grind
  - Gives players agency in what to unlock first (currency) while rewarding mains (character XP)

---

## Technical Implementation

### Engine & Tools
- **Engine:** Godot 4.x
- **Language:** GDScript
- **Renderer:** Forward+ (2D with effects capability)
- **Resolution:** 1920x1080 base
- **Art Style:** Placeholder geometric shapes (current), to be replaced with proper sprites/animations

### Architecture

#### Data-Driven Character System
Characters are built modularly to allow easy addition of new characters:


**Character Structure:**
```
Character (CharacterBody2D)
├─ CharacterStats (resource)
├─ MovementData (resource)
├─ Spells (array of 4 spell resources)
└─ Attunements (array of equipped attunement resources)
```

#### Universal Systems
- Movement controller reads character stats (no hardcoded values)
- Combat system is generic, reads attack damage/timings from character data
- Spell system is a framework that loads character-specific spells
- Adding new character = create new stat resources + spell definitions


### Development Phases

#### Phase 1: Foundation ✅ (COMPLETE)
- ✅ Basic movement (walk, sprint, crouch, jump)
- ✅ Advanced movement (double jump, dash, wall mechanics)
- ✅ Mana system with all three regen methods
- ✅ Debug HUD with real-time feedback
- ✅ Modular character stats system
- ✅ Test environment

#### Phase 2: Combat Foundation (IN PROGRESS)
- ⏳ Training dummy
- ⏳ Melee attacks (light/heavy)
- ⏳ Combo system
- ⏳ Flinch/Stagger mechanics
- ⏳ Blocking system
- ⏳ Clash detection

#### Phase 3: Ranged & Spells
- Ranged mode implementation
- Spell framework (Targeted, Free-Aim, Toggled)
- Create sample spells for first character
- Cooldown/Mana cost system

#### Phase 4: Character Roster
- Character stat differentiation system
- Build 4 characters (one per role)
- Unique spell kits for each
- Role balance testing

#### Phase 5: Attunements
- Attunement data structure
- Character select menu with loadout system
- Universal attunements implementation
- Character-specific attunements
- Attunement application to gameplay

#### Phase 6: Polish & Demo Prep
- UI/UX polish
- Visual feedback (particles, effects)
- Sound effects (placeholder/royalty-free)
- Tutorial/instructions
- Gameplay recording for Kickstarter

**Estimated Timeline:** ~4 months of part-time work (10-15 hours/week)

---

## Demo Scope (Kickstarter Prototype)

### Core Goal
Create a playable demonstration that showcases the unique mechanics and depth of Mana Brawl.

### Deliverables
1. **Training/Testing Ground** - Solo environment for players to explore mechanics
2. **4 Playable Characters** - One per role (Offense, Defense, Support, Hybrid)
3. **Character Select Menu** - With attunement loadout system
4. **Full Movement Kit** - All basic and advanced movement working
5. **Complete Combat System** - Melee, ranged, blocking, resource management
6. **Spell System** - 4 unique spells per character
7. **Attunements** - Universal + character-specific attunements functional
8. **Polish** - Good feel, responsive controls, clear feedback

### What's NOT in Demo
- Online multiplayer (local/solo only)
- Multiple maps
- Objectives/game modes
- Full character roster
- Progression/unlocking (all content available)

### Success Criteria
- Players can immediately feel the depth of movement
- Resource management creates meaningful decisions
- Combat feels responsive and skill-based
- Attunements create clear build variety
- "I want to play more of this" reaction

---

## Design Principles

### 1. Skill Expression
- High skill ceiling through movement tech
- Resource management rewards planning
- Combat has counterplay and mind games
- No "auto-win" buttons

### 2. Readability
- Clear visual feedback for all actions
- Distinct animations for different attacks
- Audio cues for important events
- UI shows all relevant information

### 3. Role Identity
- Each role feels distinct to play
- No character is "just worse" than another
- Team composition matters
- Counter-picking exists but isn't absolute

### 4. Build Variety
- Attunements create meaningful choices
- Same character can fill different niches
- No single "best" build
- Experimentation is rewarding

### 5. Accessibility with Depth
- Easy to learn, hard to master
- Basic movement is simple
- Advanced techniques are optional but powerful
- Tutorial teaches fundamentals

---

## Character Design Template

When creating new characters, use this template:

### Character Name: [Name]
**Role:** Offense / Defense / Support / Hybrid  
**Theme:** [Lightning, Shield, Nature, etc.]  
**Archetype:** [Glass Cannon, Tank, Healer, etc.]

**Stats:**
- Health: [value]
- Mana: [value]
- Speed: [fast/medium/slow]
- Jump: [high/medium/low]

**Spells (1-4):**
1. [Spell Name] - [Type: Targeted/Free-Aim/Toggled] - [Description]
2. [Spell Name] - [Type] - [Description]
3. [Spell Name] - [Type] - [Description]
4. [Spell Name] - [Type] - [Description]

**Unique Mechanic:**
[Any special ranged mode or unique property]
[Any special passive property or ability]

**Example Attunements:**
- [Universal attunement that synergizes]
- [Character-specific attunement that changes playstyle]
- [Character-specific attunement that enhances role]

**Playstyle Description:**
[2-3 sentences on how this character plays and what they're good at]

---

## Known Characters

### Bolt (Offense)
**Theme:** Lightning  
**Archetype:** Glass Cannon

**Stats:**
- Health: Low
- Mana: Medium-High
- Speed: Very Fast
- Jump: High

**Unique Mechanic:**
- Basic Ranged: Free-aimed projectile. Fast travel speed, narrow hitbox.
- Passive: Overcharge - Consecutive successful hits (melee or ranged) build Overcharge stacks (max 3). Each stack increases spell effectiveness. Overcharge decays rapidly when not dealing damage and is lost on Stagger.

**Example Attunements:**
- **"Shock Dash":** Dash Flinches enemies on contact. Dash Mana cost significantly increased.
- **"Chain Lightning":** Basic Ranged replaced with close-range auto-targeting lightning arc. Continuous damage. Reduced range.

**Playstyle:**
High-mobility skirmisher. Relentless pressure and burst damage. Excels at isolating targets and forcing scrambles. Collapses quickly when cornered, Mana-starved, or Staggered.

---

### Gravebrand (Hybrid Offense/Defense)
**Theme:** Anti-Mage  
**Archetype:** Melee Pressure \ Anti-Zone

**Stats:**
- Health: Medium
- Mana: Medium
- Speed: Medium-Fast
- Jump: Medium

**Unique Mechanic:**
- Basic Ranged: Arc Slash - Short-range magic crescent emitted from greatsword. Cancels enemy projectiles on contact. Each slash can cancel multiple projectiles up to a fixed capacity (3-5). Slash dissipates early if capacity is exceeded or at max range. No effect on beams, auras, or ground effects.
- Passive: Spellcut -
  - Light Attacks: If a Light Melee Attack intercepts a projectile during active frames, the projectile is consumed and Gravebrand restores Mana equivalent to a successful melee hit.
  - Heavy Attacks: If a Heavy Melee Attack intercepts a projectile during active frames, the projectile is deflected, reflecting along its incoming angle and swapping ownership.

**Example Attunements:**
- **"Edge Discipline":** Arc Slash projectile-cancel capacity increased. Increased recovery on Arc Slash use.
- **"Relentless Advance":** Mana restored from Spellcut (Light Attacks) increased. Heavy Attack windup slightly longer.

**Playstyle:**
Melee-first enforcer. Uses timing and positioning to convert enemy ranged pressure into Mana sustain. Advances deliberately through projectile-heavy fights. Excels at mid-range lane control and punishing panic casting. Vulnerable to baited swings, close-range rushdown, and sustained pressure during recovery windows.

---

### Fervor (Hybrid Offense/Support)
**Theme:** Phoenix Fire  
**Archetype:** Sustain \ Attrition

**Stats:**
- Health: Low-Medium
- Mana: High
- Speed: Medium
- Jump: Very High

**Unique Mechanic:**
- Basic Ranged: Cauterizing Firebolt - Targeted instead of free-aim, provides DoT heal to allies and DoT damage to enemies.
- Passive: Ashen Rebirth - Allies that die within radius of Fervor leave behind an Ashen Husk with a full health bar. Husks are visible, targetable, and destructible. After 6 seconds, if intact, ally revives at husk location with Health equal to remaining husk HP and Mana equal to 50% of remaining husk HP. Revive is cancelled if husk is destroyed. Allies cannot benefit again for 5 minutes or until next respawn, whichever occurs first.

**Example Attunements:**
- **"Trial by Fire":** Ash Husks revive allies faster. Fervor takes increased damage while any husk is active.
- **"Scorched Doctrine":** Cauterizing Firebolt increases burn damage on enemies. Healing-over-time on allies reduced.

**Playstyle:**
Midline anchor. Sustained pressure and attrition. Rewards proximity and commitment. Strong in prolonged fights and contested spaces. Vulnerable when isolated, burst-focused, or forced to disengage repeatedly.

---

### Aegis (Defense)
**Theme:** Shield  
**Archetype:** Tank

**Stats:**
- Health: Very High
- Mana: Low-Medium
- Speed: Slow
- Jump: Low

**Unique Mechanic:**
- Ranged Mode: Holds up shield and deflects basic ranged attacks at angles (no projectile firing)

**Playstyle:**
Frontline protector, absorbs damage, controls space. Low damage but extremely durable.

---

## Future Considerations

### Post-Demo Features
- Online multiplayer with netcode
- Multiple maps with different layouts
- Objective-based game modes (capture point, payload, etc.)
- Full character roster (10-20+ characters)
- Ranked/competitive mode
- Replay system
- Spectator mode

### Monetization (If Applicable)
- Base game purchase
- Cosmetic skins (never pay-to-win)
- Character unlocks (earnable through play only)

### Community Features
- Custom games
- Map editor (potential)
- Modding support (potential)
- Tournaments/esports support

---

## Glossary

**Flinch** - Light interrupt, brief hitstun, cannot interrupt armored actions  
**Stagger** - Heavy interrupt, breaks through everything  
**Clash** - Simultaneous attacks cancel each other  
**Coalescence** - Meditation ability for fast Mana regeneration  
**Attunement** - Customization modifier that changes character stats/abilities  
**I-frames** - Invulnerability frames during Dash  
**Shield Break** - Heavy attack destroying a Block, disabling it temporarily  
**Queue State** - When aiming/selecting target for Targeted or Free-Aim spell  

---

## Contact & Credits

**Solo Developer:** [Ahjati, the Dumbass]  
**Engine:** Godot 4.x  
**Development Start:** February 2026  
**Target Kickstarter:** [TBD - approximately 4 months from start]

---

## Revision History

**v0.1 (Feb 3, 2026)**
- Initial GDD created
- Foundation phase complete
- Movement systems fully documented
- Combat systems designed (implementation in progress)

