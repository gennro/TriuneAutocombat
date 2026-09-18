# Triune AutoCombat Releases

Short, human-readable notes for each release. The GitHub release page is built
from the entry that matches the tag (`v3.0` -> `## 3.0`). The full, detailed
history of every change stays in [CHANGELOG.md](CHANGELOG.md).

## 3.1

A bug-fix release for 3.0. No new plugins; if you are on 3.0 this is a
straight drop-in update.

### Fixed

- **Box Network: crash in mq2lua.dll.** Pressing a group- or single-box Box
  Control button more than once (or any `/ac net group ...` / `/ac net Bob ...`
  command, ping, buffme) could crash the client. The RPC reply was read after
  MacroQuest had already freed it; it is now read immediately.
- **Box Network: `/ac net all /camp` runs `/camp`.** A full slash command sent
  over the network now runs on the boxes exactly as typed instead of being
  mangled into an `/ac` command.
- **Effects & Songs / Spell Gems: wrong buff totals and missing rows.** Buff
  durations were read through a string fallback that mistook ticks for
  seconds, so a 60-minute buff showed as 600 s and a 2h30 buff as 1.5 s with
  the bar pinned full; disc reuse timers past 50 minutes had the same hole.
  The Effects window also walks all 42 buff slots and shows the running
  discipline, and the Spell Gem bar no longer trusts `Me.NumGems` alone.
- **Auto AA: priorities are bought first.** Checked priority abilities are
  trained before the fireworks cap spender gets to spend anything; the spender
  no longer runs while a priority is still saving up.
- **Puller (Hunt): the Combat Radius Anchor is a hard limit.** XTarget adds and
  chases no longer drag the character outside the anchor circle.
- **Manual mode: with Stick to Target off, a selected hostile in reach is
  fought** instead of being ignored until something else engaged it.
- **Floating Damage: melee, ranged and skill crits float.** Only spell and heal
  crits used to show.
- **Chat Windows: NPC dialogue links answer the NPC** (`[ready]`,
  `[Non-Respawning]` and other EQEmu saylinks) instead of searching for an
  item.
- **Chat Windows: every tab keeps its own history**, so guild / ooc lines are
  no longer pushed out by one fight's combat spam.
- **Parcels: Collect All works on UIs where Parcels is not the third tab**, and
  the parcel list shows Item / Qty / From / Sent / Note in the right columns.
- **Navigation: a character stranded on a navmesh island no longer waits
  forever.**

### Improved

- **Hot Buttons: custom Box Network commands** and a single-box scope on the
  Box Control tab of the Add From Game browser.
- **Chat Windows: NMS loot lines get their own channel.**

---

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
