# Triune AutoCombat - Mode Logic Documentation

This document describes the combat logic loop for each of the 11 combat modes in Triune AutoCombat.

---

## Overview

All modes share a common **combat tick** that runs approximately every 50-100ms when running. The main sequence is:

1. **Death check** - Stop if dead, resume on respawn
2. **Med break check** - Pause combat if resources drop below thresholds (optional)
3. **Stuck detection** - Attempt recovery if movement commands aren't progressing
4. **Target acquisition** - Set target based on mode logic
5. **Movement** - Move toward target or camp location
6. **Engagement** - Flag to start attacking when in range
7. **Spell/AA/Disc casting** - Fire loadout spells based on conditions

---

## Mode Logic Details

### 1. Manual

**Description:** No auto-targeting, chasing, or pulling. Your loadout still fires on whatever YOU target.

**Logic:**
- Only sets `engage = true` when you manually target a valid NPC
- Does not roam, chase, or pull
- Loadout spells fire normally if conditions are met
- Best for: Manual control with automated spell casting

```
if haveNPC then engage = true end
```

---

### 2. Hunter

**Description:** Roams and solo-kills the nearest valid mob within configurable radius.

**Logic:**
1. If currently has target:
   - Check if unreachable → drop target
   - Look for closer XTarget adds (aggro switching)
   - Swap to closer mob if it's significantly better and no other xtar NPCs remain
   
2. If no target:
   - Call `findRoamTarget()` to find a new mob
   - Set wander path (bounded by combat radius if anchor set, otherwise free roam)
   
3. If haveNPC:
   - Move toward target at `desiredRange()`
   - Engage when in range

**Special behaviors:**
- Checks XTarget list for adds and switches to closer ones opportunistically
- Wander path is bounded by `hunter_combat_radius` if anchor is set
- Uses `pullerTick()` internally for kiting management

```
if haveNPC then
    if unreachable → drop target
    check xtar for better options
    moveToward(id, desiredRange()) → engage = true
else
    findRoamTarget() → set target
    wanderLoc generation if idle
end
```

---

### 3. Manual Hunter

**Description:** Fights your current target automatically, but does not roam or search for new mobs.

**Logic:**
- Same as Hunter but **no roaming behavior**
- Only acts on your manually selected target
- Best for: Swarming (multiple characters attacking different targets)

```
if haveNPC then
    if unreachable → drop target
    moveToward(id, desiredRange()) → engage = true
else
    -- No roaming logic!
    -- If pet class and not combat: keep pets on hold
end
```

---

### 4. Puller

**Description:** Pulls mobs back to camp and tanks them yourself.

**Logic:**
1. Uses `pullerTick()` which manages:
   - **IDLE state**: Find mob, pull it toward camp
   - **PULLING state**: Move mob toward camp location
   - **FIGHTING state**: Tank the mob (moveToward at melee range)
   
2. `engage = true` only when in FIGHTING state

**State machine:**
```
IDLE → PULLING → FIGHTING → IDLE
         ↑_____________|

engage = (runtime.pullState == 'FIGHTING' and ctrl.mode == 'Puller')
```

---

### 5. Pull & Assist

**Description:** Pulls mobs back to camp and holds them for the Main Assist — does not self-tank.

**Logic:**
- Same `pullerTick()` state machine as Puller
- BUT `engage = false` (never tanks)
- When mob reaches camp, it's left for MA to kill
- Best for: Supporting a Main Assist in group play

```
pullerTick()  -- same pulling logic
engage = false  -- never engage (MA does the killing)
```

---

### 6. Assist

**Description:** Assists the Main Assist; chases to stay in range, or returns to camp when idle.

**Logic:**
1. Call `maTargetId()` to get MA's target
2. If MA has a target:
   - Set our target to match
   - When target HP ≤ assist_at % AND target is engaged:
     - Move toward at `desiredRange()`
     - Engage when in range
3. If no MA target:
   - Call `idleReturn()` to return to camp (if set)
   - Or chase MA position if chaseMA is enabled

```
id = maTargetId()
if id then
    setTarget(id)
    if HP <= assist_at % AND engaged:
        moveToward() → engage = true
else
    idleReturn() or chaseMA()
end
```

---

### 7. Chase Assist

**Description:** Same as Assist — chases and assists the Main Assist everywhere.

**Logic:**
- Identical to Assist except:
  - `idleReturn()` is NOT called
  - Always returns to camp only when no MA target and no chaseMA set
  
```
id = maTargetId()
if id then
    setTarget(id)
    moveToward() → engage = true
else
    chaseMA()  -- follow MA anywhere, never return to camp
end
```

---

### 8. Backline

**Description:** Assists the Main Assist but NEVER moves or melees — ranged/caster support only.

**Logic:**
- Same target acquisition as Assist/Chase Assist
- BUT:
  - No movement toward target (just checks if already in range)
  - `engage = true` only if target is ALREADY at `desiredRange()` with LoS
  - Never flags `/attack on`
  - Loadout spells do all damage

```
id = maTargetId()
if id then
    setTarget(id)
    -- Check if already in range with LoS (no movement!)
    if HP <= assist_at % AND engaged AND dist ≤ desiredRange() AND hasLoS():
        engage = true
else
    -- No movement, no chasing, no camp return
end
```

---

### 9. Tank

**Description:** Assists the Main Assist and commits to melee immediately, ignoring Assist At %.

**Logic:**
- Always moves toward target (not gated by HP threshold)
- Uses `MELEE_RANGE` (14 units) regardless of combat style
- Returns to camp when idle (if camp set)

```
id = maTargetId()
if id then
    setTarget(id)
    moveToward(id, MELEE_RANGE) → engage = true  -- immediate melee commitment
else
    idleReturn()  -- return to camp if no target
end
```

---

### 10. Garrison

**Description:** Holds a camp point and reactively tanks whatever aggros — does not roam looking for fights.

**Logic:**
1. If haveNPC:
   - Check unreachable → drop
   - Move toward at MELEE_RANGE
   - Engage when in range
   
2. If no NPC target but camp is set:
   - Move toward camp location (15 units)
   
3. Eager melee flag set (flags `/attack on` immediately when target acquired)

```
if haveNPC then
    moveToward(id, MELEE_RANGE) → engage = true
elseif camp_loc is set then
    moveTowardLoc(camp_loc, 15)  -- hold position
end
```

---

### 11. Pet Tank

**Description:** Roams for targets like Hunter, closes to ranged distance (never melee range), sends pets in to tank while you free-cast from range.

**Logic:**
- Same roaming as Hunter (`findRoamTarget()`, wander paths)
- BUT moves to `ranged_dist` (default 40) instead of MELEE_RANGE
- Pets are sent to attack via `/pet attack`
- Never flags `/attack on` for self

```
if haveNPC then
    moveToward(id, ctrl.ranged_dist or 40) → engage = true
else
    -- Same Hunter roaming logic:
    findRoamTarget() and wanderLoc generation
end

-- Pet dispatch (separate from melee flag):
if new target and trioHasPetClass():
    mq.cmdf('/pet attack %s', cleanName)
```

---

## Shared Engine Components

### Target Resolution (`resolveTargetId`)

All modes use this function to convert target tokens to spawn IDs:

| Token | Resolves To |
|-------|-------------|
| `F: Myself` | Character's own ID |
| `F: Main Assist` | MA PC's ID (via `maPcId()`) |
| `F: Lowest-HP Ally` | Group member with lowest HP |
| `F: Pet` | Tracked pet for the spell's class |
| `E: Current Target` | `mq.TLO.Target.ID()` |
| `E: Assist Target` | MA's target (via `maTargetId()`) |
| `E: Unmezzed Add` | First unmezzed XTarget NPC |
| `E: Nearest Add` | First reachable XTarget NPC |
| `E: All Enemies` | Same as Nearest Add |

### Condition Checking (`conditionMet`)

Loadout slots fire when conditions are met:

- `always`: Always eligible
- `in combat`: Only when any combat is active
- `HP <=`, `target HP <=`, `my HP <=`, `my Mana <=`: Percentage thresholds
- `missing buff`: Spell not active on target (with song tracking for bards)
- `missing pet`: Pet not alive for that class
- `has Poison/Disease`: Target has status effect
- `ally is Dead`: Target is dead (for cleanup)
- `add is loose`: Unmezzed XTarget exists
- `twist while fighting`: Bard-only, checks combat state

### Spell/Cast Loop

1. Check if already casting → skip
2. Try AAs (no cooldowns, instant cast)
3. Try disciplines/skills in priority order (lowest first)
4. Try gem slots 1-12 in order:
   - Skip if locked out (failure count ≥ maxRetries)
   - Skip if not enough mana/mana ready
   - Check conditionMet()
   - Set target, cast spell
   - Break on success (try next slot only if this one failed)

---

## State Management

### `runtime` Table
- `pullState`: 'IDLE', 'PULLING', 'FIGHTING' (Puller modes)
- `medBreakActive`: true when resting to recover
- `sungBuffs`: Track bard buffs already cast this life (avoids re-casting)
- `pendingMem`: Queue of spells waiting to be memorized

### `petState` Table  
- `myPets`: Map of {cls → petId} for each pet class in trio
- `lastCastCls`: Class that last cast a pet spell
- `manualHunterHold`: true when pets are held for Manual Hunter mode
- `petHoldActive`: true when hold issued (waiting for HP threshold)

### `pursuit` Table
- `id`: Current target being pursued
- `bestDist`: Closest distance achieved this pursuit
- `improvedAt`: When bestDist was last updated
- `navStalls`: Count of nav completions without progress
- `wanderLoc`: Random point for Hunter/Garrison roaming
- `unreachableIds`: Map of IDs that have no path (60s timeout)

### `stuckState` Table
- `checkAt`, `lastX`, `lastY`: Position tracking for stuck detection
- `counter`: Consecutive non-movement ticks before unstuck
- `combatStallSince`: Time when character is in range but not fighting

---

## Summary Table

| Mode | Roams? | Chases MA? | Tanks? | Ranged? | Camp Return |
|------|--------|------------|--------|---------|-------------|
| Manual | ❌ | ❌ | N/A | Depends on style | N/A |
| Hunter | ✅ | ❌ | ✅ | ✅ (ranged) | ❌ |
| Manual Hunter | ❌ | ❌ | ✅ | ✅ (ranged) | ❌ |
| Puller | ✅ | ❌ | ✅ | ✅ (kite) | ❌ |
| Pull & Assist | ✅ | ❌ | ❌ | ✅ (hold for MA) | ❌ |
| Assist | ❌ | ✅ | ✅ | ✅ | ✅ (if set) |
| Chase Assist | ❌ | ✅ | ✅ | ✅ | ❌ |
| Backline | ❌ | ❌ | ❌ | ✅ (no move) | ❌ |
| Tank | ❌ | ✅ | ✅ (immediate) | ❌ | ✅ (if set) |
| Garrison | ❌ | ❌ | ✅ | ❌ | ✅ (hold position) |
| Pet Tank | ✅ | ❌ | ❌ (pets tank) | ✅ | ❌ |

---

*Last updated: 2026-08-05*