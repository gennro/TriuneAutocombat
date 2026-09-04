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

> 📥 **Download the latest versions here**:
> - **MacroQuest (RoF2)**: [**MacroQuest GitHub Releases**](https://github.com/macroquest/macroquest/releases)
> - **Triune AutoCombat (Full Release)**: [**Triune AutoCombat GitHub Releases (Latest)**](https://github.com/gennro/TriuneAutocombat/releases/latest)

Getting started takes less than two minutes:

1. **Download MacroQuest**: Download the latest **RoF2** release of MacroQuest from the [MacroQuest Releases page](https://github.com/macroquest/macroquest/releases) (e.g. `MacroQuest-RoF2.zip`) and extract it to your chosen directory (such as `C:\MacroQuest` or `Documents\MacroQuest`).
2. **Download Triune AutoCombat**: Download the latest **Triune AutoCombat full release** archive from [Triune AutoCombat Releases](https://github.com/gennro/TriuneAutocombat/releases/latest).
3. **Extract TAC to MacroQuest**: Extract the contents of the `TAC` folder directly into your root `MacroQuest` directory. This automatically merges the `lua/`, `config/`, and `resources/` directories into MacroQuest so that all scripts, databases, and zone navmeshes are placed where MacroQuest expects them.
4. **Run MacroQuest**: Launch `MacroQuest.exe`.
5. **Log Into Your EMU Server**: Start your EverQuest RoF2 client and log into your **[Project Triune](https://nms.bestemu.com/)** server account.
6. **Open Triune**: Triune automatically starts on login. If the window is closed or you need to re-open it, type `/ac` or `/lua run triune` in the chat bar.
7. **Verify Your Trio Classes**: On the main window, verify your 3 detected multiclass roles (or click **Re-Detect** to let Triune scan them automatically).
8. **Configure Your Loadout**: Set up your combat spells and downtime buffs in **Spell Gems**, innate skills in **Abilities**, activated AAs in **AAs**, disciplines in **Disciplines**, and clickies in **Clickies**.
9. **Pick a Mode & Go**: On the **Control** tab, select your combat mode (**Manual**, **Puller**, or **Assist**) and click **Start** (or type `/ac run`)!

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
- **MQ2Nav & MoveUtils Navigation Stack**: Live plugin and zone navmesh status with automatic startup plugin autoloading (`mq2nav` and `mq2moveutils`), chat window warnings on missing dependencies, inline UI recovery buttons (`[Load MQ2Nav]`, `[Load MQ2MoveUtils]`, `[Reload Mesh]`), active navigation destination tracking, path length/distance calculations, detour obstacle avoidance timers, and anti-stuck metrics.
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
- **Export & Share Routes**: Export a named preset as a copy/paste string to share with guildmates; Import pastes one back in, filed under whichever zone it was made for.

---

### 🔮 Simple & Powerful Loadouts & Autoskill
- **Streamlined Tabbed Interface**: All combat loadouts and settings are organized logically across dedicated tabs:
  `Status` ➔ `Control` ➔ `Pets` ➔ `Spell Gems` ➔ `Abilities` ➔ `AAs` ➔ `Disciplines` ➔ `Clickies` ➔ `Auto AA` ➔ `Cooldowns` ➔ `Settings` ➔ `Help`
- **12 Spell Gem Slots + Innate Abilities + AAs + Disciplines + Clickies**: Set up spells, combat actions, activated AA abilities, combat disciplines, and clickable items from all 3 of your classes in dedicated tabs.
- **Dedicated Abilities Tab & Autoskill**: Full automation for innate class combat actions (Kick, Bash, Slam, Mend, Backstab, Monk special strikes, Taunt, Disarm, Frenzy, Intimidation, Feign Death, etc.) with a continuous **Autoskill** toggle that automatically fires melee attacks on cooldown during combat without blocking spells.
- **Dedicated AAs Tab**: Manage Activated Alternate Advancements grouped by cooldown tiers (Short, Mid, Burn) with live purchased-rank filtering.
- **Combat Disciplines Tab**: Configure `/disc` disciplines with priority ordering, Boss Only Named mob gates, and Burn mode support.
- **Easy Trigger Rules**: Tell each ability, spell, or disc exactly when to fire (e.g. *Target HP < 90%*, *My HP < 40%*, *Missing Buff*, *Always*, *In Combat*).
- **No Wasted Mana**: Triune automatically checks if a DoT, snare, slow, or debuff is already on the mob before casting, so you never double-cast or waste mana.
- **Burn Mode**: Tag big cooldowns and nukes as **Burn Only**, then toggle Burn on when fighting named mobs or big pulls (`/ac burn`).
- **Min XTarget Gate**: Set heavy abilities or area-of-effect nukes to only fire when you have multiple enemies on you (e.g. *Only cast if 3+ mobs on XTarget*).
- **Auto-Memorize & Mem All**: Triune remembers your setup in `triune_loadout.lua` and will automatically memorize missing spells when you're out of combat.

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

### 🤝 Auto-Accept & Social Automation (Settings Sub-Page)
Triune includes a dedicated **Auto-Accept** sub-page located directly under the **Settings** tab:
- **Auto-Accept Group Invites**: Automatically accepts incoming party invites via `/invite` and dialog confirmation when received from an authorized player.
- **Auto-Accept Trades**: Automatically clicks the Trade accept button when the other party is ready and authorized.
- **Auto-Accept Dynamic Zone / Expedition Invites (DZAdd)**: Automatically accepts expedition (`/dzaccept`), dynamic zone, and task addition invites from authorized players.
- **Flexible Authorization Rules**:
  - **Accept from Anyone**: Accept requests from any player unconditionally.
  - **Always accept from Group Members**: Authorize trades and expedition requests from current group members.
  - **Accept from all Guild Members**: Authorize requests from any player in the same guild (`Me.Guild()`).
- **Interactive Whitelist Management with Player IDs**:
  - Add players by **Name or Player ID** manually with Enter key submission.
  - One-click **`+ Add Target`** button to instantly whitelist your currently targeted player character with both character name and player ID.
  - Dedicated **`Remove`** button in the top toolbar to remove the selected player or currently targeted player.
  - Structured 3-column table (`Player Name`, `Player ID`, `Action`) with row selection and per-row **`Remove`** buttons.
  - **`Clear All`** button to quickly wipe the whitelist.

---

### 📱 Compact Mini HUD
Want to clear up screen clutter while playing?
- Switch to the **Mini HUD** (`/ac compact` or click the **Compact** button).
- Gives you a tiny, clean floating window with Start/Pause, mode selection, Burn toggle, and fast one-click buttons for extra tools.
- Shows your live **AA/hr** and **Plat/hr** session rates right on your screen.

---

### 🔮 Decoupled Spell Gems & Downtime Buff Swapping
- **Unlimited Decoupled Spell List**: Configure as many spells as you need beyond the physical 12-gem limit.
- **Per-Spell Gem Dropdown**: Assign each spell line to any physical gem slot (Gem 1 to Gem 12). Multiple spells can share the same physical gem (e.g., a primary combat nuke and several long-duration buffs sharing Gem 12).
- **Dynamic Spell Management**: 1-click `+ Add Spell` button to append new lines, `^` and `v` priority buttons to reorder evaluation order, and `X` button to delete lines.
- **1-Click "Mem All" Restoral**: The `Mem All` toolbar button (and `/ac memall` command) scans all 12 physical slots, shows a pending queue count badge (e.g. `Mem All (3)`), and systematically rememorizes missing or mismatched priority combat spells in strict numerical order.
- **Automated Downtime Buff Swapping**: When out of combat, stationary, and not casting, Triune automatically swaps missing buffs into their assigned gems, waits for recharge, and casts them.
- **Instant Aggro Interruption**: If aggro is detected at any point during a swap, Triune instantly stands up, closes the spellbook, engages combat, and kills all enemies on XTarget before safely resuming the swap.
- **Primary Combat Spell Restoration**: Once all downtime buffs for a shared gem are cast, Triune automatically re-memorizes the primary combat spell back to that gem so your combat bar is always ready.

---

### ⏱️ Cooldown & Ability Monitor
Keep track of every enabled combat ability, activated AA, discipline, spell gem, and clickie item in real time:
- **Dedicated Tab & Popout Window**: Access directly via the **Cooldowns** tab in the main window (positioned right after Auto AA) or float as a standalone window using the `Popout Window` button, `/ac cd`, `/ac cooldowns`, the top toolbar, or the Mini HUD.
- **Active Duration Tracking**: Glowing cyan progress bars show remaining active buff/stance duration (e.g. *Defensive Discipline*, *Harmshield*, *Furious*) before transitioning to cooldown.
- **Smart Readiness Diagnostics**: Instant feedback on why abilities are gated: `[READY]`, `[LOW END]`, `[LOW MANA]`, `[NEED BURN]`, `[NEED BOSS]`, `[MIN XTAR]`, or `[LOCKED]`.
- **EverQuest Timer Groups**: Badges display EQ shared timer banks (`[T1]`, `[T2]`, `[T4]`) to clarify shared cooldown lockouts.
- **1-Click Execution**: Interactive **`[ Use ]`** buttons allow manual firing of any ready ability directly from the monitor.
- **Dual View Modes & HUD Overlay**: Switch between a detailed Table View and a sleek horizontal HUD Cards View with background transparency opacity slider and window position lock.
- **In-Place Loadout Tuning**: Optional inline editing controls enabling live adjustment of `Enabled`, threshold `HP %`, and `Burn Only` toggles directly from the monitor.

---

### 🌟 Alternate Advancement (AA) Progression & Auto-Training
Keep your character progressing without wasting unspent AA points with the dedicated **Auto AA** tab:
- **Comprehensive AA Browser**: Automatically scans and lists all available character Alternate Advancement abilities, displaying real-time ranks, max ranks, point costs, training eligibility, and total points spent.
- **Compact Two-Row Header Layout**: Real-time unspent/spent pool metrics, master auto-spend toggle, buy order dropdown, cap threshold slider, instant search box with `X` clear, sort criteria combo, `▲ Asc / ▼ Desc` toggle, `Hide Maxed` filter, `Prio Only` filter, and live ability count badge.
- **Instant Search & Multi-Sort**: Search abilities by name in real time, sort by **Name** (A-Z / Z-A), **Cost** (cheapest first / highest first), or **Fully Trained** status, and filter with one-click **Hide Maxed** and **Prioritized Only** checkboxes.
- **Priority-Based Auto-Training**: Check the priority box `[x]` next to any abilities you want Triune to train. As soon as enough unspent AA points are accumulated, Triune automatically opens the in-game AA window and purchases the next rank.
- **Custom Buy Order**: Choose between **Cheapest First** (maximize quick rank gains by buying lowest cost abilities first) or **Alphabetical** order.
- **Cap Protection & Fireworks Dump**: Automatically protects against the server AA cap by dumping surplus points into fireworks (or any configured ability) when your pool reaches the cap threshold (default: 100 AA).

---

## Built-in Bonus Tools

Triune comes packed with handy standalone tools you can open right from the main window or via chat commands:

| Tool | Chat Command | What It Does |
|---|---|---|
| ⏱️ **Cooldown Monitor** | `/ac cd` | Standalone popout live ability, AA, and discipline cooldown monitor with active buff duration countdowns, smart diagnostics, timer groups, next-up forecast, and 1-click execution. |
| 🎛️ **Hot Buttons Toolbar** | `/lua run triune_buttons` | Standalone ImGui tabbed hot button toolbar (ButtonMaster-style) replacing EQ's default hotbars with tabs, icon animations, live cooldown overlays, 1-click button creation from cursor, and multi-line macro execution. |
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
| `/ac pausezone [on\|off]` | `/ac zonepause`, `/ac pauseonzone` | Toggle automatic script pause when zoning (default: on) |
| `/ac burn [on\|off]` | `/ac burnon`, `/ac burnoff` | Toggle Burn mode on/off |
| `/ac memall` | `/ac mem`, `/ac remem` | Queue all missing or mismatched priority spells to memorization bar |
| `/ac debug` | `/ac diag`, `/ac debugmode` | Toggle live combat debug telemetry in chat |
| `/ac compact` | `/ac mini`, `/ac hud` | Toggle the compact Mini HUD |
| `/ac cd` | `/ac cooldowns`, `/ac cds` | Toggle the popout Cooldown & Ability Monitor window |
| `/ac status` | | Print current status and mode to chat |
| `/ac help` | `/ac ?` | Show command help in chat |
| `/ac <mode> [submode]` | | Switch mode (e.g. `/ac manual`, `/ac puller camp`, `/ac assist chase`, `/ac backline`) |
| `/ac ma [target\|clear\|<name>\|<id>]` | `/ac mainassist` | Configure Main Assist by player ID or name, or set from current PC target |
| `/ac xtardist [25-300]` | `/ac xtar`, `/ac xtarrange` | Configure max XTarget / assist engagement chase distance (default: 150) |
| `/ac chasedist [5-100]` | `/ac chase`, `/ac followdist` | Configure following distance (how far to stay back) from Main Assist (default: 15) |
| `/ac selfdefense [on\|off]` | `/ac assistdefend`, `/ac defend` | Toggle Assist mode self-defense when attacked while MA has no target |
| `/ac pullhp [0-95]` | `/ac minhp` | Set minimum HP % threshold before pausing pulling to rest until 100% |
| `/ac pullcon [preset\|con]` | `/ac con`, `/ac confilter` | Configure faction filters (`hostile`, `indifferent`, `all`, `none`) or toggle single considerations |
| `/ac wp [add\|clear\|del\|on\|off\|list]` | `/ac waypoint`, `/ac waypoints` | Manage waypoint patrol routes, arrival radius, and scan distance |
| `/ac huntz [10-300]` | `/ac z` | Configure Hunter Tier 2 max vertical height difference (default: 75) |
| `/ac zplane [5-100]` | `/ac huntplane`, `/ac floorz` | Configure Hunter Tier 1 same-floor / Z plane height threshold (default: 15) |
| `/ac spellbook` | `/ac book` | Open the Spellbook Browser |
| `/ac cursorui` | `/ac cursormgr` | Open the Cursor Manager |
| `/ac clearcursor` | `/ac autoinv` | Dump cursor items to inventory |
| `/ac autoaa [on\|off]` | `/ac autospendaa`, `/ac autospend`, `/ac fireworks` | Toggle automatic AA priority training & cap protection |
| `/ac aascan` | `/ac scanaa`, `/ac aarefresh` | Re-scan all character Alternate Advancement abilities |
| `/ac aaprio <name>` | `/ac prioritizeaa` | Toggle priority auto-training for a specific AA ability |
| `/ac autofw [on\|off]` | `/ac summonfw` | Toggle automatic fireworks summoning (/alt activate) & autoinventory |
| `/ac spendnow` | `/ac spendaa`, `/ac spendpoints`, `/ac aatrain` | Immediately purchase 1 rank of the configured AA (e.g. 25 AA) |
| `/ac summonnow` | `/ac summonfireworks` | Immediately summon fireworks via `/alt activate 17788` |
| `/ac aathreshold [25-100]` | `/ac spendthreshold` | Set unspent AA threshold for automatic purchases (default: 100) |
| `/ac aacost [1-50]` | `/ac spendcost` | Set AA cost per rank (default: 25) |
| `/ac aaid [id]` | `/ac spendaaid` | Set AA ability ID to purchase and activate (default: 17788) |
| `/ac aaname [name]` | `/ac setaaname` | Set AA ability name to search and purchase (default: 'Alternately Advanced Fireworks') |
| `/ac pet <verb> [scope]` | `/ac petcmd` | Dispatch server `#petcmd` (attack, back, follow, guard, sit, feign, leave, hold on/off, taunt on/off, etc.) |
| `/ac pet status` | `/ac pet list` | Print live status, HP, target, and class for all active trio pets |
| `/ac pet report [scope]` | `/ac pethealth` | Issue `/pet report` in chat and request `#petcmd health` for active pets |
| `/ac petscan` | `/ac petreconcile` | Re-scan zone for active pets belonging to player and re-sync tracking |
| `/ac pethold [on\|off]` | | Toggle automatic out-of-combat Pet Hold |
| `/ac petassist [1-100]` | `/ac petassistat` | Set target HP % threshold before releasing pets to attack |
| `/ac clear lockouts` | `/ac clearlockouts`, `/ac unlock` | Clear active spell lockouts, non-stacking buff backoffs, and mob immunities |
| `/ac preset [save\|load\|del\|list]` | `/ac loadout` | Save, load, list, or delete named spell gem loadout presets |
| `/ac style [melee\|ranged\|spell]` | `/ac combatstyle` | Set combat style |
| `/ac range [dist]` | `/ac meleerange`, `/ac dist` | Set melee (5-50) or ranged (5-200) distance |
| `/ac buffbot` | `/ac buff` | Open the Buffbot window |
| `/ac track` | `/ac zone` | Open the Zone NPC Tracker |
| `/ac map` | `/ac mapui` | Open the 2D Map & Norrath Zone Atlas |
| `/ac update` | `/ac checkupdate` | Check for updates via in-game release updater |
| `/dps` | `/triunedps` | Open/toggle the DPS parser |
| `/triunerun` | | Fast keybind command to toggle start/pause |
| `/lua run triune_buttons` | `/lua stop triune_buttons` | Launch or stop the standalone Hot Buttons toolbar |

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
│   │   ├── triune_buttons.lua   # Standalone ImGui hot button toolbar
│   │   ├── triune_map.lua       # Standalone 2D in-game map, Norrath Zone Atlas & NPC tracker
│   │   ├── triune_track.lua     # Zone NPC tracker & navigation tool
│   │   ├── triune_updater.lua   # In-game updater window
│   │   ├── triune_spellbook.lua # Spellbook browser & loadout helper
│   │   ├── triune_cursor.lua    # Cursor item manager
│   │   ├── triune_buffbot.lua   # Automated tell buffbot
│   │   └── triune_dps.lua       # Standalone DPS parser
│   ├── config/
│   │   └── triune_data.lua      # Era-correct spell and ability database
│   └── resources/
│       ├── ItemDB.txt           # Item database lookup
│       ├── Zones.ini            # Zone configuration metadata
│       └── MQ2Nav/              # Pre-packaged zone navigation meshes (.nav)
├── README.md                # User guide & documentation
└── CHANGELOG.md             # Detailed update and change history
```

> **Note:** Your personal character settings and loadouts are automatically saved to `triune_loadout.lua` in your MacroQuest config directory, so updates will never overwrite your setups.

---

## Helpful Links

- **MacroQuest GitHub Releases (RoF2)**: [https://github.com/macroquest/macroquest/releases](https://github.com/macroquest/macroquest/releases)
- **Triune AutoCombat Releases (Latest)**: [https://github.com/gennro/TriuneAutocombat/releases/latest](https://github.com/gennro/TriuneAutocombat/releases/latest)
- **Project Triune Website & Database (PTDex)**: [https://nms.bestemu.com/](https://nms.bestemu.com/)
- **MacroQuest**: [https://macroquest.org/](https://macroquest.org/)

---

## Version

Current version: **1.9.0**

See [CHANGELOG.md](CHANGELOG.md) for full release notes and update history.
