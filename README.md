# Triune AutoCombat

> A standalone [MacroQuest](https://macroquest.org/) ImGui Lua script that automates combat, spell memorization, and navigation for **trio (3-box) characters** on EverQuest progression servers.

---

## Overview

Triune AutoCombat is a fully-featured autocombat engine built for players who run a "triune" — a set of three EverQuest classes played together. It handles targeting, spell casting, pet commands, navigation, and loadout management through an in-game ImGui overlay, all without requiring any macros or keyboard binds beyond a single `/lua run triune` command.

The script reads an era-correct spell and activated-AA database (`triune_data.lua`) to populate class-specific spell pickers, then lets you build and persist a **loadout** — which spells, AAs, and disciplines to fire, at which targets, under which conditions — and drives the entire combat loop automatically.

---

## Features

### ⚔️ Combat Modes

Triune supports **11 distinct combat modes** modelled on classic autocombat concepts:

| Mode | Description |
|---|---|
| **Manual** | No auto-targeting; your loadout fires on whatever you manually target. |
| **Hunter** | Roams and solo-kills the nearest valid mob within a configurable radius. |
| **Manual Hunter** | Fights your current target automatically, but does not roam for new mobs. Great for swarming. |
| **Puller** | Pulls mobs back to camp and tanks them yourself. |
| **Pull & Assist** | Pulls to camp then holds for the Main Assist — does not self-tank. |
| **Assist** | Assists the Main Assist; chases to stay in range, returns to camp when idle. |
| **Chase Assist** | Same as Assist — chases the Main Assist everywhere. |
| **Backline** | Assists the Main Assist but never moves or melees — ranged/caster support only. |
| **Tank** | Assists the Main Assist and commits to melee immediately. |
| **Garrison** | Holds a camp point and reactively tanks whatever aggros — does not roam. |
| **Pet Tank** | Roams for targets, closes to ranged distance, and sends pets in to tank while you free-cast from range. |

### 🔮 Spell & Ability Loadout Builder

- **12 combat gem slots** + **12 buff gem slots** (independently edited; only one set is memorized at a time)
- **AA (Alternate Advancement)** ability slots with per-ability enable/disable toggles
- **Discipline** slots (fired via `/disc`) — separate from AAs but using the same entry shape
- Per-slot configuration: spell/ability, target type, firing condition (`HP <=`, `target HP <=`, `missing buff`, `in combat`, `always`, and more), and fire percentage threshold
- Filters spells to **scribed only**, era-correct level range, and spell category (DD, DoT, Heal, Buff, Pet, Util)
- Loadout is automatically saved to `triune_loadout.lua` and reloaded on next run

### 🧙 Spellbook Browser (`triune_spellbook.lua`)

A standalone ImGui window for browsing all spells available to your trio:
- Tabs per class with level and category filters
- Searchable spell list with type badges (DD / DoT / Heal / Buff / Pet / Util)
- One-click memorization queue: click a spell to assign it directly to a gem slot
- Loadout preset management (save and recall named presets such as "Solo / DPS", "Group Healing", "Buff Suite")
- Launch from the main window header button or via `/ac spellbook`

### 🖱️ Cursor Manager (`triune_cursor.lua`)

A lightweight standalone ImGui utility for managing items on the EQ cursor:
- Live display of current cursor item (name, quantity, Lore/NoDrop flags)
- **Auto Inv** — drains queued cursor item stacks to inventory
- **Destroy** — destroys cursor item with safety confirmation prompt
- **Auto-Clear on Pick (Continuous)** toggle — automatically inventories anything that lands on the cursor
- Session history log with timestamps, item names, quantities, and actions taken
- Launch via `/ac cursorui` or the **Cursor Manager** header button

### 🗺️ Navigation & Movement

- NavMesh (`/nav`) with automatic fallback to `/stick` when nav is unavailable
- Line-of-sight verification before confirming arrival at target
- Periodic re-facing (`/face fast`) during combat to maintain melee contact
- Stuck detection with automatic unstuck recovery (door clicks, position retries)
- Combat stall detection and recovery
- Automatic repositioning when receiving "too far away / get closer" chat messages
- Wander-path generation for Hunter/Garrison roaming

### 🐾 Pet Management

- Automatic pet-hold when entering Manual Hunter (prevents pets attacking while gathering mobs)
- Pet dispatch gated behind actual player aggro — pets only engage once you are demonstrably hitting the target
- Configurable **Pet Assist At %** threshold (hold pets until mob HP drops to this level)
- Pet Tank mode bypasses the engagement gate (pets tank by design)
- Non-pet trios see no pet UI and never issue `/say #petcmd` commands

### ⚙️ Combat Intelligence

- **Aggro detection**: inspects TargetOfTarget, AggroHolder, PctAggro, and active damage/combat hits
- **Lowest-HP NPC prioritization**: automatically targets the weakest mob on the extended target list (XTarget) first, preferring unmezzed targets
- **XTarget clearing check**: Hunter, Puller, Garrison, and Pet Tank modes verify all XTarget NPCs are dead before seeking new mobs
- **Spell failure tracking**: per-spell fizzle, interrupt, out-of-range, LoS, and immune counters with configurable retry limit and lockout duration
- **Med break system**: optional auto-meditate when HP/Mana/Endurance drops below a configurable threshold, resuming when recovered

### 🖼️ ImGui Interface

- Unified dark theme across all windows (Midnight Blue backgrounds, Steel Blue borders, Arc Cyan highlights, Amber sliders, Emerald checkmarks)
- Color-coded class trio emblems — one distinct, colorblind-safe hue per slot
- Collapsible header sections to keep the UI compact
- **Control tab**: Status / Start-Pause, mode selector, Hunter radius & level range, Main Assist settings, camp location, pet settings
- **Settings tab**: Combat style (Melee / Ranged / Spell), navigation options, spell failure sliders, med break configuration
- Debug mode for verbose console output

---

## Commands

| Command | Aliases | Description |
|---|---|---|
| `/ac` | | Toggle run / pause |
| `/ac run` | | Start autocombat |
| `/ac pause` | | Pause autocombat |
| `/ac status` | | Print current status to console |
| `/ac <mode>` | | Switch mode (`/ac hunter`, `/ac garrison`, `/ac tank`, etc.) |
| `/ac spellbook` | `/ac book` | Open the Spellbook browser window |
| `/ac cursorui` | `/ac cursorwin`, `/ac cursormgr` | Open the Cursor Manager window |
| `/ac clearcursor` | `/ac autoinv`, `/ac cursor` | Manually drain all cursor items to inventory |

---

## File Structure

```
TriuneAutocombat/
├── lua/
│   ├── triune.lua            # Main autocombat engine + ImGui UI (run with /lua run triune)
│   ├── triune_common.lua     # Shared utilities: navigation, spell helpers, class detection, theming
│   ├── triune_spellbook.lua  # Standalone spellbook browser + memorization queue
│   └── triune_cursor.lua     # Standalone cursor item manager
├── config/
│   └── triune_data.lua       # Era-correct spell, disc, and AA database (generated by extract_spells.py)
└── CHANGELOG.md
```

> **Note:** Your personal loadout is saved to `triune_loadout.lua` in your MacroQuest config directory alongside `triune_data.lua`.

---

## Requirements

- [MacroQuest](https://macroquest.org/) with the **Lua** plugin enabled
- **MQ2Nav** (recommended) for NavMesh-based pathfinding; falls back to `/stick` automatically
- `triune_data.lua` in your MQ config directory (era-correct spell/AA database for your server)

---

## Getting Started

1. Place all four `.lua` files from the `lua/` folder into your MacroQuest `lua/` directory (or a `triune/` subdirectory within it).
2. Ensure `triune_data.lua` is present in your MacroQuest config directory.
3. Log in with your trio character and run:
   ```
   /lua run triune
   ```
4. In the **Character Classes & Loadout** section, verify or re-detect your class trio.
5. Open the **Spell Gems** tab to assign spells and abilities to your loadout slots.
6. Choose your combat mode in the **Control** tab and click **Start**.

---

## Version

Current version: **3.25-commonmod**

See [CHANGELOG.md](CHANGELOG.md) for a full history of changes.
