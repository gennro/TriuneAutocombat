# Triune AutoCombat Releases

Short, human-readable notes for each release. The GitHub release page is built
from the entry that matches the tag (`v3.0` -> `## 3.0`). The full, detailed
history of every change stays in [CHANGELOG.md](CHANGELOG.md).

## 3.0

The biggest update yet. Triune is now a plugin system: every window and tool is
its own file in `lua/tac/`, can be turned on or off under **Settings -> Plugins**,
and a broken plugin no longer takes the bot down with it.

### New

- **Box Network** - your Triune instances on one PC now talk to each other over
  MacroQuest Actors (nothing extra to install). Assist boxes follow the main
  assist's real target, pullers stay off each other's mobs, boxes count as
  allies for cures and buff requests, and `/ac net all <command>` runs a command
  on every box.
- **Chat Windows** (`/tacchat`) - a full chat window replacement: tabs, filters,
  colours, highlights, a Tells window, `@Name` completion, input history,
  clickable item / spell / NPC links, and tells that survive a crash.
- **Game Database** (`/ac db`) - an offline copy of the server's items, NPCs and
  spells with search, item filters and a Spell Info replacement window. Ships in
  `resources/gamedb/` (included in the update zip).
- **Hot Buttons** (`/ac btn`) - Button Master-style hotbars with cooldown
  overlays, share strings and Group / Zone / All box-control buttons.
- **NMS Loot** (`/ac nms`) - the server's `#nms` personal loot system as a
  window, shared across your boxes.
- **Inventory & Bank: Box Inventories** - see every box's bags and hand items
  between characters from one window.
- **Parcels** (`/ac parcels`) - tells you when parcels arrive and collects them
  all at a parcel merchant.
- **Update Checker** (`/ac update`) - tells you when a newer release is out.
  Nothing is downloaded automatically.
- **Group DPS meter** in the DPS Parser, fed by the Box Network.
- **Floating Damage 2.0** - impact pops, damage tiers, combos and records.
- **Diagnostic logging** - `/ac log on` writes to a file in `Logs/`, `/ac dump`
  saves a one-shot state dump for bug reports.

### Improved

- **Every window**: one right-click menu, hide title bar, ghost fade, and a
  global UI scale (`/ac scale 1.25`).
- **Target & Player HUD**: cast bars, every pet you own, and the target frame
  as its own popout window.
- **Extended Target**: per-spawn Force / Ignore toggles; pets and friendly
  players are hidden.
- **Manual mode**: stick-to-target and auto-nav are optional, and another
  character's fights no longer count as your combat.
- **Ranged and Spell combat styles** are back (`/ac style melee|ranged|spell`).
- **Multi-pet tracking**: one pet per class, no duplicates, no re-summon loops.
- **Auto AA** no longer needs MQ2AAspend - every purchase goes through the AA
  window - and fireworks are summoned only after the AA is actually bought.
- **Navigation**: a character stranded on a navmesh island no longer waits
  forever; the map draws player movement smoothly.
- **Compact Mini HUD** reworked, with Ghost mode as its own option.
- Only heals cast through a hostile target; everything else selects the caster.
- Separate *has Poison* and *has Disease* triggers.

### Removed

- The popout Character Stats / Inventory / Currency window (the Inventory &
  Bank plugin replaces it).
- The standalone companion scripts (`triune_spellbook.lua`, map, DPS, inventory,
  buffbot, cursor) - they are all plugins now and open from the header buttons.
- The MQ2AAspend dependency for Auto AA.

---
