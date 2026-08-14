# Triune AutoCombat

> A standalone [MacroQuest](https://macroquest.org/) ImGui Lua script that automates combat, spell memorization, and navigation for **trio (3-box) characters** on EverQuest progression servers.

---

## Overview

Triune AutoCombat is a fully-featured autocombat engine built for players who run a "triune" — a set of three EverQuest classes played together. It handles targeting, spell casting, pet commands, navigation, and loadout management through an in-game ImGui overlay, all without requiring any macros or keyboard binds beyond a single `/lua run triune` command.

The script reads an era-correct spell and activated-AA database (`triune_data.lua`) to populate class-specific spell pickers, then lets you build and persist a **loadout** — which spells, AAs, and disciplines to fire, at which targets, under which conditions — and drives the entire combat loop automatically.

---

## Features

### ⚔️ Combat Modes

Triune features **3 streamlined primary combat modes** with dynamic submodes:

| Mode | Submodes | Description |
|---|---|---|
| **Manual** | *(None)* | Auto-attacks and casts loadout on your current/acquired target; does not roam. Includes **Set Camp** location and return radius slider to auto-return to camp when idle after combat. Features an **Auto-Target Hostiles on XTarget** toggle to switch between auto-engaging incoming XTarget mobs or exclusively fighting manually targeted NPCs. |
| **Puller** | **`Hunt`** / **`Camp`** | **`Hunt`**: Roams within search radius seeking valid mobs and kills them on the spot.<br>**`Camp`**: Scouts candidate mobs within radius, tags them via chosen Pull Method, and pulls back to camp to tank and fight at camp.<br>Supports customizable **Pull Methods** (**Melee**, **Spell**, **Pet**, **Ranged**), **Engagement Distance** (15–250 units), **Stand Back (Let Pet Tank / Stay Ranged)** mode, **Waypoint Patrol** loops, and **Target Filters** (Include whitelist, Ignore blacklist, and 9-tier Faction Consideration filters). |
| **Assist** | **`Chase`** / **`Camp`** / **`Backline`** | **`Chase`**: Follows Main Assist everywhere and engages the MA's target.<br>**`Camp`**: Holds camp position and assists MA on mobs within range, returning to camp when target dies.<br>**`Backline`**: Ranged/caster support; assists MA without moving into melee range. |

---

### 🎯 Puller System & Target Filters

- **Customizable Pull Methods**:
  - **Melee**: Navigates into melee range and engages auto-attack to tag mob.
  - **Spell**: Approaches to engagement distance and casts a selected spell gem (configured via a dynamic dropdown populated from memorized spells).
  - **Pet**: Commands pet (`/pet attack` and `/say #petcmd attack all`) to tag and engage mob from distance (100 units).
  - **Ranged**: Approaches to engagement distance and fires bow/ranged attacks via `/autofire on`.
- **Engagement Distance Slider (15–250 units)**: Controls how close the puller approaches before casting a pull spell, commanding pets, or firing ranged attacks.
- **Stand Back (Let Pet Tank / Stay Ranged)**: Holds position at engagement distance during combat while pets tank or ranged DPS continues, without closing to melee range or turning on auto-attack.
- **Puller Target Include & Ignore Lists**:
  - **NPCs to Pull (Include List)**: Exact whitelist; when populated, Puller will *only* pull mobs matching an entry in the list.
  - **NPCs to Ignore (Ignore List)**: Blacklist; skips matching mobs (includes a quick "Ignore Current Target" button).
- **Faction Consideration Target Filtering**:
  - Multi-select grid across all 9 EverQuest consideration tiers: `Scowling`, `Threateningly`, `Dubious`, `Apprehensive`, `Indifferent`, `Amiably`, `Kindly`, `Warmly`, `Ally`.
  - Quick presets: `Select All`, `Hostile Only`, `Hostile + Indifferent`, `Clear All`.
  - Synchronous `/consider` verification with wildcard chat parsing and automatic clean-name caching so non-matching mob types are skipped instantly (0ms) on subsequent scans. Active XTarget mobs always bypass consideration filtering to protect the group.
  - Controlled via UI checkboxes or slash commands (`/ac pullcon`).
- **Max XTarget Chase Range (25–300 units)**: Restricts navigation distance for chasing hostile XTarget adds in Puller and Manual modes.

---

### 🚩 Waypoint Patrol System

- **Autonomous 3D Waypoint Route**: Navigates Puller sequentially through user-defined 3D waypoints (`X`, `Y`, `Z`) in a continuous loop while scanning for targets.
- **Target Scan Interruption & Seamless Resume**: Pauses patrol immediately upon acquiring a valid target; once combat ends and XTarget clears, waypoint patrol resumes seamlessly from the current waypoint.
- **Interactive ImGui Waypoint Controls**:
  - Enable / disable patrol toggle and configurable **Arrival Radius** slider.
  - Live route table with `#`, `Name`, `Coordinates`, `Distance`, and `[NEXT]` active waypoint indicator.
  - Control buttons: `Add Current Location`, `Clear All`, `Set Active`, `Move Up`, `Move Down`, `Delete`.
- **Slash Command Route Management**: Manage patrol routes directly from EQ chat via `/ac wp [add [name]|clear|delete [idx]|on|off|toggle|list]`.
- **Full Loadout Persistence**: Waypoint routes are serialized and saved automatically to `triune_loadout.lua`.

---

### 🔮 Spell & Ability Loadout Builder

- **12 spell gem slots** (per-slot class, target, trigger condition, percent threshold, Min XTarget, and Burn Only toggle)
- **AA (Alternate Advancement)** ability slots with per-ability enable/disable toggles
- **Discipline** slots (fired via `/disc`) — separate from AAs but using the same entry shape
- Per-slot configuration: spell/ability, target type, firing condition (`HP <=`, `target HP <=`, `missing buff`, `in combat`, `always`, and more), fire percentage threshold, **Min XTarget** (1-10 NPCs), and **Burn Only** mode toggle
- **Min XTarget Dropdown (1-10)**: Restricts spell gems, AAs, and disciplines to fire only when the specified number of active hostiles are present on your XTarget list (ideal for gating AE spells or heavy cooldowns to multi-mob pulls).
- **Smart Active Effect Checking**: Duration-based spells (DoTs, debuffs, slows, snares, CC, and buffs) automatically check if their effect is active on the target before casting, preventing mana waste and recast loops on `always` or `in combat` settings. Instant spells (nukes, heals) bypass this check to fire freely.
- **Min Mana % Threshold**: Configurable minimum mana slider in Settings halts automatic spell casting when mana falls below the threshold (automatically ignored during Burn Mode).
- **Rank-Aware Gem Sync & Memorization**: Supports exact names, clean names, and rank normalization (`Rk. II` / `Rk. III`), automatically queueing spell memorization when out of combat.
- Loadout is automatically saved to `triune_loadout.lua` and reloaded on next run.

---

### 🧙 Spellbook Browser (`triune_spellbook.lua`)

A standalone ImGui window for browsing all spells available to your trio:
- Tabs per class with level and category filters
- Searchable spell list with type badges (DD / DoT / Heal / Buff / Pet / Util)
- One-click memorization queue: click a spell to assign it directly to a gem slot
- Loadout preset management (save and recall named presets such as "Solo / DPS", "Group Healing", "Buff Suite")
- Launch from the main window header button or via `/ac spellbook`

---

### 🖱️ Cursor Manager (`triune_cursor.lua`)

A lightweight standalone ImGui utility for managing items on the EQ cursor:
- Live display of current cursor item (name, quantity, Lore/NoDrop flags)
- **Auto Inv** — drains queued cursor item stacks to inventory
- **Destroy** — destroys cursor item with safety confirmation prompt
- **Auto-Clear on Pick (Continuous)** toggle — automatically inventories anything that lands on the cursor
- Session history log with timestamps, item names, quantities, and actions taken
- Launch via `/ac cursorui` or the **Cursor Manager** header button

---

### 🛡️ Interactive Tell Buffbot (`triune_buffbot.lua`)

A standalone ImGui utility for managing an automated tell buff service:
- **Safe Spell Gem Management**: Automatically saves active spell gems on startup/start, memorizes configured buff spells, and cleanly restores original gems on stop or script exit via `mq.atexit()`.
- **Proximity & Tell Monitoring**: Listens for incoming `/tell` requests and verifies that the requester is within configurable proximity.
- **Two-Stage Confirmation**: Offers interactive confirmation ("Would you like buffs? Reply 'yes'") or direct auto-buffing.
- **Custom Buff Slots**: Configure buff spells per slot using dynamic dropdowns populated from scribed spells in your spellbook.
- **Completion Feedback**: Automatically sends a `/tell` confirmation when buffing is complete.
- **Per-Character Persistence**: Saves configuration to `triune_buffbot_config.lua` in your MQ config directory.
- Launch via `/ac buffbot`, `/ac buff`, `/ac buffui`, or `/lua run triune_buffbot`.

---

### 📊 DPS Parser (`triune_dps.lua`)

A standalone ImGui DPS parser for tracking player and pet combat performance:
- **Real-Time Damage Tracking**: Monitors player melee, direct damage spells, DoTs, damage shields, and pet combat damage.
- **Live Metrics**: Combined DPS, Player DPS, Pet DPS, active target name, encounter duration, and damage contribution percentage gauge.
- **Detailed Attack Breakdowns**: Min, Max, Avg, Crit %, and Accuracy % per attack type and spell.
- **Historic Fight Log**: Retains up to 50 previous combat encounters with fight inspection and single-click clear.
- **Chat Reporting**: Post formatted DPS reports to `/group`, `/say`, `/guild`, or `/raid` with `/dps report`.
- Launch via `/dps`, `/ac dps`, or `/lua run triune_dps`.

---

### 🎯 Zone Tracker (`triune_track.lua`)

A standalone ImGui window for tracking and navigating to NPCs in the current zone:
- **Live Zone NPC Listing**: Displays all active NPCs in the zone with live distance updates (in yards), level, consideration color badge, line of sight, and spawn ID.
- **Clean Name First Layout**: Displays clean mob name prominently in column 1 followed by Level, Distance, Con, ID, LoS, and Action buttons.
- **Consideration & Search Filtering**: Filter by consideration color (`Red / Dark Red`, `Yellow`, `White`, `Blue`, `Light Blue`, `Green`, `Grey`) and search text matching mob names or IDs.
- **Sorting Options**: Sort by `Nearest First`, `Farthest First`, `Level (High -> Low)`, `Level (Low -> High)`, or `Name (A - Z)`.
- **Double-Click Target & Nav**: Double-clicking any cell on an NPC row (or clicking `[Nav]`) acquires target (`/target id`) and initiates navigation (`/nav id` with `/stick` fallback).
- Launch via `/ac track`, `/ac zone`, `/lua run triune_track`, or the **Zone Tracker** header button.

---

### 🔄 Release Updater (`triune_updater.py` / `triune_updater.lua`)

A cross-platform updater for Windows and Linux to pull and apply GitHub release updates:
- **Zero-Dependency Python Script (`triune_updater.py`)**: Uses Python 3 standard library (`urllib.request`, `zipfile`, `shutil`) to check releases, download zip packages, and extract updated engine files.
- **OS Launchers (`update.bat` / `update.sh`)**: One-click scripts for Windows and Linux with PowerShell and `curl`/`unzip` fallbacks if Python is absent.
- **In-Game ImGui Updater (`triune_updater.lua`)**: Check for updates, inspect release notes, and update/reload scripts on the fly without leaving EverQuest.
- **Preserved User Configuration**: Engine updates never touch or overwrite `triune_loadout.lua`, character settings, or custom INI files.
- Launch via `/ac update`, `/lua run triune_updater`, `mq2triune/update.bat` (Windows), or `mq2triune/update.sh` (Linux).

---

### 🗺️ Navigation & Movement

- NavMesh (`/nav`) with automatic fallback to `/stick` when nav is unavailable
- Line-of-sight verification before confirming arrival at target
- Periodic re-facing (`/face fast`) during combat to maintain melee contact
- Stuck detection with automatic unstuck recovery (door clicks, position retries)
- Combat stall detection and recovery
- Automatic repositioning when receiving "too far away / get closer" chat messages
- Dynamic mid-travel closer NPC retargeting: checks once for significantly closer targetable NPCs while moving toward distant targets in Hunter/Puller modes (configurable)
- Wander-path generation for roaming search
- Return to camp navigation when idle in **Manual** and **Assist (Camp)** modes

---

### 🐾 Pet Management

- Automatic pet-hold when entering Manual mode (prevents pets attacking while gathering mobs)
- Pet dispatch gated behind actual player aggro — pets only engage once you are demonstrably hitting the target
- Configurable **Pet Assist At %** threshold (hold pets until mob HP drops to this level)
- Pet pull method tags mobs from distance using `/pet attack` and `/say #petcmd attack all`
- Stand Back (Let Pet Tank) mode allows pets to tank while player stays at engagement distance
- Enforced pet hold during Puller (Camp) scouting to prevent pets pulling adds prematurely
- Non-pet trios see no pet UI and never issue `/say #petcmd` commands

---

### ⚙️ Combat Intelligence

- **Natural EverQuest Combat Disengagement**: In accordance with EverQuest mechanics, auto-attack turns on in melee range and stays continuously engaged throughout combat across ability casts, spellcasting, and target switching. Never issues disruptive `/attack off` mid-fight; EQ naturally turns off auto-attack upon mob death.
- **Aggro Detection & Hysteresis**: Inspects TargetOfTarget, AggroHolder, PctAggro, and active damage/combat hits. Features a 2.0-second debounce timer and 15-unit distance hysteresis to eliminate rapid target switching when multiple mobs are grouped.
- **Target Engagement Safety**: Detrimental spells, AAs, and disciplines strictly reject player pets, group pets, friendly PCs, merchants, bankers, guildmasters, and peaceful quest NPCs.
- **Lowest-HP NPC Prioritization**: Automatically prioritizes the weakest mob on the Extended Target list (XTarget), preferring unmezzed targets.
- **XTarget Clearing Check**: Puller and roam modes verify all XTarget NPCs are dead before seeking new candidate mobs.
- **Spell Failure & Lockout Tracking**: Per-spell fizzle, interrupt, out-of-range, LoS, and immune counters with configurable retry limit and lockout duration.
- **Med Break System**: Optional auto-meditate when HP/Mana/Endurance drops below a configurable threshold. Gated behind active XTarget status (never sits if live hostiles are on XTarget; instantly cancels and stands if a mob appears).

---

### 📱 Compact Mini HUD Mode

- **Minimal Floating Overlay**: Essential combat controls in a minimal, space-saving mini-window (`Triune AutoCombat Mini`).
- **Live Combat Controls**: Mode selector dropdown, Start/Pause toggle button, and Burn toggle button (highlighted bright red when active).
- **Session Rate Banner**: Displays real-time AA/hr and Plat/hr rates with hover tooltip and inline Reset button.
- **Quick Module Launchers**: One-click launcher buttons for `Spellbook`, `Cursor`, `DPS`, `Buffbot`, `Update`, and `Tracker`.
- Toggle via `/ac compact`, `/ac mini`, `/ac hud`, the **Compact Mode** header button, or Settings tab.

---

### 📈 AA & Platinum Session Rate Tracker

- **Real-Time Efficiency Metrics**: Tracks total session elapsed time, AA/hr rate (`AA/hr: 12.4`), total AAs gained, Plat/hr rate (`Plat/hr: 120.5`), and total Platinum earned.
- **Interactive Tooltip**: Hovering over the rate banner in the main header or Compact HUD displays a complete breakdown of session start and current balances.
- **Reset Button**: One-click session reset to start a fresh tracking period.

---

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
| `/ac run` | `/ac start` | Start autocombat execution |
| `/ac pause` | `/ac stop` | Pause autocombat execution, halt movement & disengage pet |
| `/ac burn [on\|off]` | `/ac burnon`, `/ac burnoff` | Toggle burn mode (enables "Burn Only" spells, AAs, discs) |
| `/ac compact` | `/ac mini`, `/ac hud` | Toggle compact mini-window HUD mode |
| `/ac status` | | Print current running state and combat mode to chat |
| `/ac help` | `/ac h`, `/ac ?` | Print slash command summary & mode usage to chat |
| `/ac <mode> [submode]` | | Switch primary mode and submode (`/ac manual`, `/ac puller hunt`, `/ac puller camp`, `/ac assist chase`, `/ac assist camp`, `/ac assist backline`, `/ac backline`, `/ac tank`, `/ac garrison`, `/ac hunter`, `/ac pull`, `/ac ranged`) |
| `/ac pullcon [tier] [on\|off]` | `/ac con`, `/ac confilter` | Configure Puller mode target faction consideration filters or apply presets (`/ac pullcon preset [all\|hostile\|indifferent\|none]`) |
| `/ac wp [add\|clear\|del\|on\|off\|toggle\|list]` | `/ac waypoint`, `/ac waypoints` | Configure and toggle Puller mode Waypoint Patrol loop (`/ac wp add [name]`, `/ac wp del [idx]`, `/ac wp on`, `/ac wp off`, `/ac wp list`) |
| `/ac spellbook` | `/ac book` | Open the Spellbook browser window |
| `/ac cursorui` | `/ac cursorwin`, `/ac cursormgr` | Open the Cursor Manager window |
| `/ac clearcursor` | `/ac autoinv`, `/ac cursor` | Manually drain all cursor items to inventory |
| `/ac buffbot` | `/ac buff`, `/ac buffui`, `/lua run triune_buffbot` | Open the Interactive Buffbot window |
| `/ac track` | `/ac tracker`, `/ac trackui`, `/ac zone` | Open the Zone NPC Tracker window for live targeting and navigation |
| `/ac update` | `/ac updater`, `/ac checkupdate` | Launch the Release Updater window and check for GitHub release updates |
| `/dps` | `/triunedps`, `/ac dps`, `/lua run triune_dps` | Toggle or control the standalone DPS Parser window (`/dps compact`, `/dps report [chan]`, `/dps reset`, `/dps pause`) |
| `/triunerun` | | Quick keybind command to toggle run / pause |

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
2. In the **Character Classes & Loadout** section, verify or re-detect your class trio.
3. Open the **Spell Gems** tab to assign spells and abilities to your loadout slots.
4. Choose your combat mode in the **Control** tab and click **Start**.

---

## Version

Current version: **1.6**

See [CHANGELOG.md](CHANGELOG.md) for a full history of changes.
