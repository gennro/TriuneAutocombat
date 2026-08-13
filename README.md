# Triune AutoCombat

> A standalone [MacroQuest](https://macroquest.org/) ImGui Lua script that automates combat, spell memorization, and navigation for **trio (3-box) characters** on EverQuest progression servers.

---

## Overview

Triune AutoCombat is a fully-featured autocombat engine built for players who run a "triune" — a set of three EverQuest classes played together. It handles targeting, spell casting, pet commands, navigation, and loadout management through an in-game ImGui overlay, all without requiring any macros or keyboard binds beyond a single `/lua run triune` command.

The script reads an era-correct spell and activated-AA database (`triune_data.lua`) to populate class-specific spell pickers, then lets you build and persist a **loadout** — which spells, AAs, and disciplines to fire, at which targets, under which conditions — and drives the entire combat loop automatically.

---

## Features

### ⚔️ Combat Modes

Triune supports **3 primary combat modes** with dynamic submodes:

| Mode | Submodes | Description |
|---|---|---|
| **Manual** | *(None)* | Auto-attacks and casts loadout on your current/acquired target; does not roam. Includes Set Camp and radius slider to auto-return to camp when idle after combat, plus an **Auto-Target Hostiles on XTarget** toggle to switch between auto-engaging XTarget hostiles or only fighting manually selected targets. |
| **Puller** | **`Hunt`** / **`Camp`** | **`Hunt`**: Roams within search radius looking for valid mobs and kills them on the spot.<br>**`Camp`**: Scouts mobs within radius, tags them via chosen Pull Method (**Melee**, **Spell**, **Pet**, or **Ranged**), and pulls back to camp to tank/fight at camp. Supports **Engagement Distance** slider (15-250 units) and **Stand Back (Let Pet Tank)** option to stay ranged during combat. |
| **Assist** | **`Chase`** / **`Camp`** / **`Backline`** | **`Chase`**: Follows Main Assist everywhere and assists on MA target.<br>**`Camp`**: Holds camp position and assists MA, returning to camp when target dies.<br>**`Backline`**: Ranged/caster support; assists MA without moving to melee. |

### 🔮 Spell & Ability Loadout Builder

- **12 spell gem slots** (per-slot class, target, trigger condition, percent threshold, Min XTarget, and Burn Only toggle)
- **AA (Alternate Advancement)** ability slots with per-ability enable/disable toggles
- **Discipline** slots (fired via `/disc`) — separate from AAs but using the same entry shape
- Per-slot configuration: spell/ability, target type, firing condition (`HP <=`, `target HP <=`, `missing buff`, `in combat`, `always`, and more), fire percentage threshold, **Min XTarget** (1-10 NPCs), and **Burn Only** mode toggle
- **Min XTarget Dropdown (1-10)**: Restricts spell gems, AAs, and disciplines to fire only when the specified number of active hostiles are present on your XTarget list (ideal for gating AE spells or heavy cooldowns to multi-mob pulls).
- **Smart Active Effect Checking**: Duration-based spells (DoTs, debuffs, slows, snares, CC, and buffs) automatically check if their effect is active on the target before casting, preventing mana waste and recast loops on `always` or `in combat` settings. Instant spells (nukes, heals) bypass this check to fire freely.
- **Min Mana % Threshold**: Configurable minimum mana slider in Settings halts automatic spell casting when mana falls below the threshold (automatically ignored during Burn Mode).
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

### 📊 DPS Parser (`triune_dps.lua`)

A standalone ImGui DPS parser for tracking player and pet combat performance:
- **Real-Time Damage Tracking**: Monitors player melee, direct damage spells, DoTs, damage shields, and pet combat damage.
- **Live Metrics**: Combined DPS, Player DPS, Pet DPS, active target name, encounter duration, and damage contribution percentage gauge.
- **Detailed Attack Breakdowns**: Min, Max, Avg, Crit %, and Accuracy % per attack type and spell.
- **Historic Fight Log**: Retains up to 50 previous combat encounters with fight inspection and single-click clear.
- **Chat Reporting**: Post formatted DPS reports to `/group`, `/say`, `/guild`, or `/raid` with `/dps report`.
- **Launch via**: `/lua run triune_dps` or slash command `/dps`.

### 🔄 Release Updater (`triune_updater.py` / `triune_updater.lua`)

A cross-platform updater for Windows and Linux to pull and apply GitHub release updates:
- **Zero-Dependency Python Script (`triune_updater.py`)**: Uses Python 3 standard library (`urllib.request`, `zipfile`, `shutil`) to check releases, download zip packages, and extract updated engine files.
- **OS Launchers (`update.bat` / `update.sh`)**: One-click scripts for Windows and Linux with PowerShell and `curl`/`unzip` fallbacks if Python is absent.
- **In-Game ImGui Updater (`triune_updater.lua`)**: Check for updates, inspect release notes, and update/reload scripts on the fly without leaving EverQuest.
- **Preserved User Configuration**: Engine updates never touch or overwrite `triune_loadout.lua`, character settings, or custom INI files.
- **Launch via**: `/ac update`, `/lua run triune_updater`, `mq2triune/update.bat` (Windows), or `mq2triune/update.sh` (Linux).

### 🎯 Zone Tracker (`triune_track.lua`)

A standalone ImGui window for tracking and navigating to NPCs in the current zone:
- **Live Zone NPC Listing**: Displays all active NPCs in the zone with live distance updates (in yards), level, consideration color badge, line of sight, and spawn ID.
- **Clean Name First Layout**: Displays clean mob name prominently in column 1 followed by Level, Distance, Con, ID, LoS, and Action buttons.
- **Consideration & Search Filtering**: Filter by consideration color (`Red / Dark Red`, `Yellow`, `White`, `Blue`, `Light Blue`, `Green`, `Grey`) and search text matching mob names or IDs.
- **Sorting Options**: Sort by `Nearest First`, `Farthest First`, `Level (High -> Low)`, `Level (Low -> High)`, or `Name (A - Z)`.
- **Double-Click Target & Nav**: Double-clicking any cell on an NPC row (or clicking `[Nav]`) acquires target (`/target id`) and initiates navigation (`/nav id` with `/stick` fallback).
- **Launch via**: `/ac track`, `/lua run triune_track`, or the **Zone Tracker** header button.

### 🗺️ Navigation & Movement

- NavMesh (`/nav`) with automatic fallback to `/stick` when nav is unavailable
- Line-of-sight verification before confirming arrival at target
- Periodic re-facing (`/face fast`) during combat to maintain melee contact
- Stuck detection with automatic unstuck recovery (door clicks, position retries)
- Combat stall detection and recovery
- Automatic repositioning when receiving "too far away / get closer" chat messages
- Dynamic mid-travel closer NPC retargeting: checks once for significantly closer targetable NPCs while moving toward distant targets in Hunter, Puller, and Pet Tank modes (configurable)
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

### 📱 Compact Mini HUD Mode

- **Minimal Floating Overlay**: Essential combat controls in a minimal, space-saving mini-window (`Triune AutoCombat Mini`).
- **Live Combat Controls**: Mode selector dropdown, Start/Pause toggle button, and Burn toggle button (highlighted bright red when active).
- **Session Rate Banner**: Displays real-time AA/hr and Plat/hr rates with hover tooltip and inline Reset button.
- **Quick Module Launchers**: One-click launcher buttons for `Spellbook`, `Cursor`, `DPS`, `Update`, and `Tracker`.
- **Toggle via**: `/ac compact`, `/ac mini`, `/ac hud`, the **Compact Mode** header button, or Settings tab.

### 📈 AA & Platinum Session Rate Tracker

- **Real-Time Efficiency Metrics**: Tracks total session elapsed time, AA/hr rate (`AA/hr: 12.4`), total AAs gained, Plat/hr rate (`Plat/hr: 120.5`), and total Platinum earned.
- **Interactive Tooltip**: Hovering over the rate banner in the main header or Compact HUD displays a complete breakdown of session start and current balances.
- **Reset Button**: One-click session reset to start a fresh tracking period.

### 🖼️ ImGui Interface

- Unified dark theme across all windows (Midnight Blue backgrounds, Steel Blue borders, Arc Cyan highlights, Amber sliders, Emerald checkmarks)
- Color-coded class trio emblems — one distinct, colorblind-safe hue per slot
- Collapsible header sections to keep the UI compact
- **Control tab**: Status / Start-Pause, mode selector, Hunter radius & level range, Main Assist settings, camp location, pet settings, Puller Target Filters (NPCs to Pull include list & NPCs to Ignore list)
- **Settings tab**: Combat style (Melee / Ranged / Spell), navigation options, spell failure sliders, med break configuration, Compact Mode toggle
- Debug mode for verbose console output

---

## Commands

| Command | Aliases | Description |
|---|---|---|
| `/ac` | | Toggle run / pause |
| `/ac run` | | Start autocombat |
| `/ac pause` | | Pause autocombat |
| `/ac burn [on|off]` | `/ac burn` | Toggle burn mode (enables "Burn Only" spells, AAs, discs) |
| `/ac compact` | `/ac mini`, `/ac hud` | Toggle compact mini-window HUD mode |
| `/ac status` | | Print current status to console |
| `/ac <mode> [submode]` | | Switch primary mode and submode (`/ac manual`, `/ac puller hunt`, `/ac puller camp`, `/ac assist chase`, etc.) |
| `/ac spellbook` | `/ac book` | Open the Spellbook browser window |
| `/ac cursorui` | `/ac cursorwin`, `/ac cursormgr` | Open the Cursor Manager window |
| `/ac clearcursor` | `/ac autoinv`, `/ac cursor` | Manually drain all cursor items to inventory |
| `/ac update` | `/ac updater`, `/ac checkupdate` | Launch the Release Updater window and check for GitHub release updates |
| `/ac track` | `/ac tracker`, `/ac trackui`, `/lua run triune_track` | Open the Zone NPC Tracker window for live targeting and navigation |
| `/lua run triune_buffbot` | | Launch the standalone Interactive Buffbot window |
| `/dps` | `/triunedps`, `/ac dps`, `/lua run triune_dps` | Toggle or control the standalone DPS Parser window (`/dps compact`, `/dps report [chan]`, `/dps reset`, `/dps pause`) |

---

## File Structure

```
TriuneAutocombat/
├── mq2triune/
│   ├── triune_updater.py    # Standalone cross-platform Python 3 updater script
│   ├── update.bat           # Windows updater launcher (Python / PowerShell fallback)
│   ├── update.sh            # Linux updater launcher (Python 3 / curl fallback)
│   ├── lua/
│   │   ├── triune.lua           # Main autocombat engine, loadout UI & Compact Mini HUD
│   │   ├── triune_track.lua     # Standalone ImGui zone NPC tracking & navigation window
│   │   ├── triune_updater.lua   # Standalone ImGui release updater window
│   │   ├── triune_spellbook.lua # Standalone spellbook browser & memorization window
│   │   ├── triune_cursor.lua    # Standalone cursor item manager window
│   │   ├── triune_buffbot.lua   # Standalone interactive tell buffbot window
│   │   └── triune_dps.lua       # Standalone ImGui DPS parser for player & pet damage
│   ├── config/
│   │   └── triune_data.lua      # Era-correct spell/disc/AA database (generated)
├── README.md                # User-facing documentation & feature overview
└── CHANGELOG.md             # Version history
```

> **Note:** Your personal loadout is saved to `triune_loadout.lua` in your MacroQuest config directory alongside `triune_data.lua`.

---

## Getting Started

### 1. MacroQuest Setup
1. Unzip the downloaded release folder to your **Documents** folder (e.g. `Documents\MacroQuest`).
2. Run `MacroQuest.exe` **before** launching EverQuest.
3. MacroQuest will run in your Windows system tray while waiting for the game to start.

### 2. Running Triune AutoCombat
1. Launch EverQuest and log in with your character. Triune loads automatically.
4. In the **Character Classes & Loadout** section, verify or re-detect your class trio.
5. Open the **Spell Gems** tab to assign spells and abilities to your loadout slots.
6. Choose your combat mode in the **Control** tab and click **Start**.

---

## Version

Current version: **1.5.2**

See [CHANGELOG.md](CHANGELOG.md) for a full history of changes.
