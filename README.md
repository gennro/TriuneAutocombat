# Triune AutoCombat

> A friendly, easy-to-use combat bot and multiclass automation tool built specifically for the **[Project Triune](https://nms.bestemu.com/)** EverQuest server (via [MacroQuest](https://macroquest.org/)).

---

## What is Triune AutoCombat?

On **[Project Triune](https://nms.bestemu.com/)**, every character is a multiclass combination of three EverQuest classes (a "trio" or "gestalt"). Juggling three full spellbooks, disciplines, and dozens of activated AAs on a single character can get overwhelming fast — that's where **Triune AutoCombat** comes in!

Triune gives you a clean visual in-game window to manage your 3-class combo and automate your combat loop without needing clunky macros or endless hotbars.

It handles all the busywork for you:
- **Multiclass Combat & Spellcasting**: Fires nukes, heals, buffs, DoTs, debuffs, disciplines, and AAs from all 3 of your classes based on simple rules you set.
- **Smart Pulling & Patrols**: Pulls mobs to your camp, roams zones to hunt, or walks custom waypoint routes.
- **Pet Control**: Commands pets from any of your pet classes (Mage, Necro, Beastlord, Shaman, Shadowknight, Enchanter) to attack, pull, or tank while you hang back.
- **Group Assists & Boxing**: Lets your box characters follow the tank, assist on targets, and cast safely from the backline.
- **Auto-Resting**: Sits to med and regenerate mana/endurance when it's safe, and stands up instantly if attacked.

Just type `/ac run` (or click **Start** in the UI) and let your character go to work!

---

## Quick Start Guide

> 📥 **Download the latest version here**: [**GitHub Releases (Latest)**](https://github.com/gennro/TriuneAutocombat/releases/latest)

Getting started takes less than two minutes:

1. **Download & Extract**: Grab the latest release from the link above and extract it into a folder under your user directory (for example, `Documents\MacroQuest`).
2. **Start MacroQuest** and log into Everquest.
3. **Open Triune**: Triune starts automatically on login. If the window is closed, type `/ac` or `/lua run triune`.
4. **Verify Your Classes**: In the **Character Classes & Loadout** section, verify your 3 classes (or click **Re-Detect** to let Triune detect them automatically).
5. **Set Up Your Spells**: Go to the **Spell Gems** tab and choose what each gem slot should do (e.g. *Heal when HP < 50%*, *Snare on incoming mobs*, *Nuke in combat*).
6. **Pick a Mode & Go**: On the **Control** tab, pick your mode (**Manual**, **Puller**, or **Assist**) and click **Start**!

---

## Combat Modes

Triune keeps things simple with **3 main combat modes**:

| Mode | Best For | How It Works |
|---|---|---|
| **Manual** | When you want to drive | You control movement and pick where to go. Triune handles attacking, casting your 3-class loadout spells, using AAs/discs, and healing allies. When the fight is over, it will walk back to your camp if you have one set. |
| **Puller** | The group leader / puller | Automates finding and engaging mobs. Comes in two flavors:<br>• **`Camp`**: Runs out, tags a mob (with a spell, bow, melee hit, or pet), brings it back to camp, and tanks it there.<br>• **`Hunt`**: Roams around the zone, finds mobs, and kills them right where they stand. |
| **Assist** | Box characters & helpers | Follows and assists your Main Assist (MA). Comes in three flavors:<br>• **`Chase`**: Runs right behind the MA and attacks whatever the MA targets.<br>• **`Camp`**: Holds position at camp and only hits mobs that get brought into camp.<br>• **`Backline`**: For healers and casters — stays safely at range and never charges into melee. |

---

## Key Features

### 📊 Real-Time Status & Diagnostics Dashboard
- **Primary Status Tab**: A dedicated tactical overview tab right next to Control displaying live engine state, active combat modes/submodes, and subsystem indicators.
- **Current Target Hero Card**: Real-time target stats (Level, Class, Race, Con Color), dynamic color-coded HP bar, distance, Line-of-Sight, melee range indicator, aggro holder (Target-of-Target), and 1-click action buttons (`Face`, `Attack`, `Clear`, `+ Pull List`, `+ Ignore List`).
- **MQ2Nav & Pathing Monitor**: Live plugin and zone navmesh load status (with inline `[Load MQ2Nav]` and `[Reload Mesh]` recovery buttons), active navigation destination, path length/distance, MoveUtils status, detour obstacle avoidance timers, and anti-stuck metrics.
- **Player, Trio & Pet Vitals**: Visual HP, Mana, and Endurance progress bars, character action flags (Combat, Moving, Ducking, Sitting, Feigning, Levitation), Gestalt Trio class badges with slot theme colors, and live pet status (HP, Target, and Pet Hold threshold state).
- **Interactive Extended Target (XTarget) Threat Monitor**: Live threat table displaying all active hostile combatants with level, distance, health bars, aggro holder, and 1-click targeting buttons.

---

### 🎯 Smart Pulling & Target Filters
- **Choose Your Pull Method**: Tag mobs using **Melee**, a **Spell** of your choice, a **Pet**, or **Ranged** (bow/throwing).
- **Stand Back Mode**: Great for pet classes and rangers! Lets your pet tank or keeps you at range without running into melee.
- **Pull Lists**:
  - **Include List (Whitelist)**: Only pull specific mobs you name.
  - **Ignore List (Blacklist)**: Skip unwanted mobs, dangerous roamers, or rares you aren't ready for.
- **Faction Filters**: Choose which mob factions to fight (`Scowling`, `Threatening`, `Indifferent`, etc.) with quick one-click presets like **Hostile Only**. Never accidentally pull a friendly guard or quest NPC again!

---

### 🚩 Waypoint Patrol Routes
- **Walk Custom Routes**: Create a list of waypoints and let your puller smoothly walk the path back and forth (1 ➔ 2 ➔ 3 ➔ 2 ➔ 1) while scanning for mobs.
- **Optional Looping**: Enable **Loop** to walk the route as a one-way circuit (1 ➔ 2 ➔ 3 ➔ 1) instead of bouncing back and forth.
- **Map Path Lines**: Your waypoint route and arrival circles are drawn directly on your in-game EverQuest map so you can see exactly where your character will walk.
- **Pause & Resume**: Whenever a mob is spotted, patrol pauses to fight. Once the mob dies, patrol picks right back up where it left off.
- **Easy Setup**: Click **Add Current Location** to drop waypoints as you walk, or use chat commands like `/ac wp add`.
- **Per-Zone Saving & Named Presets**: Your route and settings auto-save per zone and reload the next time you enter it. Save named presets (e.g. `<name> - <zone>`) from a dropdown to keep multiple routes per zone and switch between them with Load/Edit/Delete.
- **Export & Share Routes**: Export a named preset as a copy/paste string to share with guildmates; Import pastes one back in, filed under whichever zone it was made for.

---

### 🔮 Simple & Powerful Loadouts & Autoskill
- **12 Spell Gem Slots + Innate Abilities + AAs + Disciplines**: Set up spells, combat actions, activated AA abilities, and combat disciplines from all 3 of your classes in dedicated tabs.
- **Dedicated Abilities Tab & Autoskill**: Full automation for innate class combat actions (Kick, Bash, Slam, Mend, Backstab, Monk special strikes, Taunt, Disarm, Frenzy, Intimidation, Feign Death, etc.) with a continuous **Autoskill** toggle that automatically fires melee attacks on cooldown during combat without blocking spells.
- **Dedicated AAs Tab**: Manage Activated Alternate Advancements grouped by cooldown tiers (Short, Mid, Burn) with live purchased-rank filtering.
- **Combat Disciplines Tab**: Configure `/disc` disciplines with priority ordering, Boss Only Named mob gates, and Burn mode support.
- **Easy Trigger Rules**: Tell each ability, spell, or disc exactly when to fire (e.g. *Target HP < 90%*, *My HP < 40%*, *Missing Buff*, *Always*, *In Combat*).
- **No Wasted Mana**: Triune automatically checks if a DoT, snare, slow, or debuff is already on the mob before casting, so you never double-cast or waste mana.
- **Burn Mode**: Tag big cooldowns and nukes as **Burn Only**, then toggle Burn on when fighting named mobs or big pulls (`/ac burn`).
- **Min XTarget Gate**: Set heavy abilities or area-of-effect nukes to only fire when you have multiple enemies on you (e.g. *Only cast if 3+ mobs on XTarget*).
- **Auto-Memorize**: Triune remembers your setup in `triune_loadout.lua` and will automatically memorize missing spells when you're out of combat.

---

### 🎒 Automated Clickie Item Management
- **Dynamic Setup from Cursor**: Pick up any inventory, bag, or equipped item with a clickable spell effect onto your cursor and click **`+ Add Item on Cursor`** in the **Clickies** tab.
- **Context-Aware Trigger Rules**: Configure target condition (`F: Myself`, `F: Tank`, `E: Current Target`), trigger condition (`Missing Buff`, `HP <=`, `In Combat`, `Always`), health/mana threshold slider, and Min XTarget requirements.
- **Priority Reordering & Deletion**: Use `▲` and `▼` buttons to reorder clickie priority and `✕` to remove items from your loadout.
- **Smart Cooldown & Buff Detection**: Automatically checks item readiness (`ItemReady` / timer ready) and avoids re-clicking active duration buffs.

---

### 🧭 Intelligent Navigation & Hazard Avoidance
- **Stuck Memory & Autonomous Detours**: Remembers locations where characters get stuck in each zone, clusters them into hazard hotspots, and dynamically routes around them using perpendicular detour waypoints.
- **Reverse Breadcrumbs (Puller Mode)**: When pulling mobs in `Puller (Camp)` mode, Triune records the exact path walked to reach the mob and traverses it in reverse to guarantee a safe return to camp along cleared ground.
- **Closer-NPC Retargeting & Directional Arc Filtering**: Dynamically switches to closer mobs encountered during movement with configurable retarget limits (0–5), forward arc cone constraints ($\pm 75^\circ$) to prevent 180° turnarounds, scan throttling, and Line-of-Sight prioritization.
- **Path Ratio Sanity Gates**: Evaluates `NavMesh PathLength / 3D Distance` before engaging targets to prevent taking massive loops through distant corridors to reach mobs behind thin walls or on high balconies.
- **Proactive Door & Gate Automation**: Scans the path ahead while moving and opens doors predictively before colliding with them.
- **Levitation Duck-to-Clear**: Automatically ducks momentarily under low door headers and archways while floating with levitation to eliminate ceiling snags.
- **Hazard Management UI**: Inspect logged hazard counts and clear zone hotspots with a single click from the Settings tab.

---

### 🐾 Smart Pet Control & Dedicated "Pets" Tab
- **Dedicated "Pets" Tab**: Positioned directly next to **Control** in the main Triune window (`Status -> Control -> Pets -> Spell Gems -> ...`) for live monitoring and complete command of all active pets.
- **Multi-Pet Management (Up to 3 Pets)**: Full support for multi-class trio setups where characters can summon up to 3 simultaneous pets (e.g. Magician, Beastlord, Necromancer, Enchanter, Shaman, Druid, Bard, Shadowknight) plus swarm pets.
- **Interactive `/pet report` & Stats Inspector**: Click the **`[/pet report]`** button on any pet card to issue `/pet report` in game, target the pet, send `#petcmd health <scope>`, and pop up a dedicated **Pet Stats Report** window showing detailed coordinates, heading, speed, level, race, posture, color-graded HP/Mana bars, target engagement, active buff lists, and quick command buttons.
- **Live Status Telemetry**: Live HP progress bars, current/max HP values, target tracking (target name, target HP%, target distance), and active buff lists with hover tooltips for each individual pet.
- **Server `#petcmd` Command Center**: Full integration with the server's `#petcmd` multi-pet control protocol:
  - **Direct Actions**: Attack, Quick Attack (`qattack`), Back Off, Follow, Stop, Guard, Sit, Feign Death, and Dismiss (`leave`).
  - **Stance & Discipline Toggles**: One-click toggles for `Taunt (on/off)`, `Hold (on/off)`, `GHold (on/off)`, `SpellHold (on/off)`, `Focus (on/off)`, `Regroup (on/off)`, and `Assist (on/off)`.
  - **Scope Filtering**: Target commands to `all` pets, `swarm` pets, or specific class pets (`mag`, `bst`, `nec`, `enc`, `shm`, `dru`, `brd`, `shd`).
  - **Custom Command Runner**: Send any arbitrary `#petcmd` string directly from the UI.
- **Pet Automation & Discipline**:
  - **No Early Aggro**: Pets automatically stay on hold until you start hitting the mob, preventing accidental add pulls.
  - **Pet Assist %**: Configurable HP threshold slider (`ctrl.pet_assist_at`) so pets only engage after the target drops below a set percentage.
  - **Pet Pulling**: Command pets to tag distant targets and drag them to camp.
  - **Re-Scan / Reconcile Engine**: One-click button to re-sync pet detection if pets are summoned or rezzed outside combat.

---

### 📱 Compact Mini HUD
Want to clear up screen clutter while playing?
- Switch to the **Mini HUD** (`/ac compact` or click the **Compact** button).
- Gives you a tiny, clean floating window with Start/Pause, mode selection, Burn toggle, and fast one-click buttons for extra tools.
- Shows your live **AA/hr** and **Plat/hr** session rates right on your screen.

---

### ⏱️ Cooldown & Ability Monitor
Keep track of every enabled combat ability, activated AA, discipline, spell gem, and clickie item in real time:
- **Dedicated Tab & Popout Window**: Access directly via the **Cooldowns** tab in the main window (positioned right after AAs) or float as a standalone window using the `Popout Window` button, `/ac cd`, `/ac cooldowns`, the top toolbar, or the Mini HUD.
- **Active Duration Tracking**: Glowing cyan progress bars show remaining active buff/stance duration (e.g. *Defensive Discipline*, *Harmshield*, *Furious*) before transitioning to cooldown.
- **Smart Readiness Diagnostics**: Instant feedback on why abilities are gated: `[READY]`, `[LOW END]`, `[LOW MANA]`, `[NEED BURN]`, `[NEED BOSS]`, `[MIN XTAR]`, or `[LOCKED]`.
- **EverQuest Timer Groups**: Badges display EQ shared timer banks (`[T1]`, `[T2]`, `[T4]`) to clarify shared cooldown lockouts.
- **1-Click Execution**: Interactive **`[ Use ]`** buttons allow manual firing of any ready ability directly from the monitor.
- **Dual View Modes & HUD Overlay**: Switch between a detailed Table View and a sleek horizontal HUD Cards View with background transparency opacity slider and window position lock.
- **In-Place Loadout Tuning**: Optional inline editing controls enabling live adjustment of `Enabled`, threshold `HP %`, and `Burn Only` toggles directly from the monitor.

---

## Built-in Bonus Tools

Triune comes packed with handy standalone tools you can open right from the main window or via chat commands:

| Tool | Chat Command | What It Does |
|---|---|---|
| ⏱️ **Cooldown Monitor** | `/ac cd` | Standalone popout live ability, AA, and discipline cooldown monitor with active buff duration countdowns, smart diagnostics, timer groups, next-up forecast, and 1-click execution. |
| 🗺️ **2D Map & Norrath Atlas** | `/ac map` | Interactive 2D vector map, Norrath Zone Atlas & Travel Explorer, live NPC radar, and Point of Interest locator. |
| 🧙 **Spellbook Browser** | `/ac spellbook` | Browse and search all spells across all 3 of your character's classes, filter by level or type, and assign them to your loadout with one click. |
| 🖱️ **Cursor Manager** | `/ac cursorui` | Displays what's on your cursor and can automatically dump items into your bags (`/ac clearcursor`). |
| 🛡️ **Interactive Buffbot** | `/ac buffbot` | Run an automated buffing station! Listens for `/tell` requests from nearby players, hands out buffs, and sends a reply when done. |
| 📊 **DPS Parser** | `/dps` | Live combat parser tracking player damage, spell hits, DoTs, and pet DPS with historic fight logs. |
| 🎯 **Zone NPC Tracker** | `/ac track` | Lists all NPCs in the zone by distance and level. Double-click any mob (or click `[Nav]`) to run straight to it! |
| 🔄 **Release Updater** | `/ac update` | Checks GitHub for new Triune updates and lets you update your files with a single click. |

---

## Slash Commands

You can control almost everything using simple in-game chat commands:

| Command | Aliases | What It Does |
|---|---|---|
| `/ac` | | Start or pause autocombat |
| `/ac run` | `/ac start` | Start autocombat |
| `/ac pause` | `/ac stop` | Pause autocombat and stop moving |
| `/ac burn [on\|off]` | `/ac burnon`, `/ac burnoff` | Toggle Burn mode on/off |
| `/ac debug` | `/ac diag`, `/ac debugmode` | Toggle live combat debug telemetry in chat |
| `/ac compact` | `/ac mini`, `/ac hud` | Toggle the compact Mini HUD |
| `/ac cd` | `/ac cooldowns`, `/ac cds` | Toggle the popout Cooldown & Ability Monitor window |
| `/ac status` | | Print current status and mode to chat |
| `/ac help` | `/ac ?` | Show command help in chat |
| `/ac <mode> [submode]` | | Switch mode (e.g. `/ac manual`, `/ac puller camp`, `/ac assist chase`, `/ac backline`) |
| `/ac pullhp [0-95]` | `/ac minhp` | Set minimum HP % threshold before pausing pulling to rest until 100% |
| `/ac pullcon [preset]` | `/ac con` | Set faction filters (e.g. `/ac pullcon preset hostile`) |
| `/ac wp [add\|clear\|del\|on\|off\|list]` | `/ac waypoint` | Manage waypoint patrol routes |
| `/ac spellbook` | `/ac book` | Open the Spellbook Browser |
| `/ac cursorui` | `/ac cursormgr` | Open the Cursor Manager |
| `/ac clearcursor` | `/ac autoinv` | Dump cursor items to inventory |
| `/ac autoaa [on\|off]` | `/ac autospendaa`, `/ac fireworks` | Toggle automatic AA point spending (e.g. Fireworks AA ID 17788) |
| `/ac autofw [on\|off]` | `/ac summonfw` | Toggle automatic fireworks summoning (/alt activate) & autoinventory |
| `/ac spendnow` | `/ac spendaa`, `/ac spendpoints` | Immediately purchase 1 rank of the configured AA (e.g. 25 AA) |
| `/ac summonnow` | `/ac summonfireworks` | Immediately summon fireworks via `/alt activate 17788` |
| `/ac aathreshold [25-100]` | `/ac spendthreshold` | Set unspent AA threshold for automatic purchases (default: 100) |
| `/ac aacost [1-50]` | `/ac spendcost` | Set AA cost per rank (default: 25) |
| `/ac aaid [id]` | | Set AA ability ID to purchase and activate (default: 17788) |
| `/ac pet <verb> [scope]` | `/ac petcmd` | Dispatch server `#petcmd` (attack, back, follow, guard, sit, feign, leave, hold on/off, taunt on/off, etc.) |
| `/ac pet status` | | Print live status, HP, target, and class for all active trio pets |
| `/ac pet report [scope]` | `/ac pethealth` | Issue `/pet report` in chat and request `#petcmd health` for active pets |
| `/ac petscan` | `/ac petreconcile` | Re-scan zone for active pets belonging to player and re-sync tracking |
| `/ac pethold [on\|off]` | | Toggle automatic out-of-combat Pet Hold |
| `/ac petassist [1-100]` | `/ac petassistat` | Set target HP % threshold before releasing pets to attack |
| `/ac clear lockouts` | `/ac clearlockouts`, `/ac unlock` | Clear active spell lockouts, non-stacking buff backoffs, and mob immunities |
| `/ac preset [save\|load\|del\|list]` | `/ac loadout` | Save, load, list, or delete named spell gem loadout presets |
| `/ac style [melee\|ranged\|spell]` | | Set combat style |
| `/ac range [dist]` | `/ac meleerange` | Set melee (5-50) or ranged (5-200) distance |
| `/ac buffbot` | `/ac buff` | Open the Buffbot window |
| `/ac track` | `/ac zone` | Open the Zone NPC Tracker |
| `/ac map` | `/ac mapui` | Open the 2D Map & Navmesh Reachability Tracker |
| `/ac update` | `/ac checkupdate` | Check for updates |
| `/dps` | `/triunedps` | Open/toggle the DPS parser |
| `/triunerun` | | Fast keybind command to toggle start/pause |

---

## File Structure

```
TriuneAutocombat/
├── TAC/
│   ├── triune_updater.py    # Python updater script
│   ├── update.bat           # Windows updater launcher
│   ├── update.sh            # Linux updater launcher
│   ├── lua/
│   │   ├── triune.lua           # Main autocombat engine & Mini HUD
│   │   ├── triune_map.lua       # Standalone 2D in-game map, Norrath Zone Atlas & NPC tracker
│   │   ├── triune_track.lua     # Zone NPC tracker & navigation tool
│   │   ├── triune_updater.lua   # In-game updater window
│   │   ├── triune_spellbook.lua # Spellbook browser & loadout helper
│   │   ├── triune_cursor.lua    # Cursor item manager
│   │   ├── triune_buffbot.lua   # Automated tell buffbot
│   │   └── triune_dps.lua       # Standalone DPS parser
│   ├── config/
│   │   └── triune_data.lua      # Spell and ability database
├── README.md                # This guide!
└── CHANGELOG.md             # Detailed update and change history
```

> **Note:** Your personal character settings and loadouts are automatically saved to `triune_loadout.lua` in your MacroQuest config directory, so updates will never overwrite your setups.

---

## Helpful Links

- **GitHub Releases (Latest Downloads)**: [https://github.com/gennro/TriuneAutocombat/releases/latest](https://github.com/gennro/TriuneAutocombat/releases/latest)
- **Project Triune Website & Database (PTDex)**: [https://nms.bestemu.com/](https://nms.bestemu.com/)
- **MacroQuest**: [https://macroquest.org/](https://macroquest.org/)

---

## Version

Current version: **1.8.0**

See [CHANGELOG.md](CHANGELOG.md) for full release notes and update history.
