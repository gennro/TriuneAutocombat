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
3. **Extract to MacroQuest**: Extract the archive directly into your root `MacroQuest` directory. This automatically merges the `lua/`, `config/`, and `resources/` directories into MacroQuest so that all scripts, databases, and zone navmeshes are placed where MacroQuest expects them.
4. **Run MacroQuest**: Launch `MacroQuest.exe`.
5. **Log Into Your EMU Server**: Start your EverQuest RoF2 client and log into your **[Project Triune](https://nms.bestemu.com/)** server account.
6. **Open Triune**: Triune automatically starts on login. If the window is closed or you need to re-open it, type `/ac` or `/lua run triune` in the chat bar.
   - Triune raises MQ2Lua's instruction budget (`/lua conf turboNum 25000`, saved in `config/MQ2Lua.yaml`) the first time it starts. MQ2Lua's default of 500 suspends every Lua script after 500 instructions and resumes it from the game loop, which makes spawn scans, chat and the map 10-50x slower than they should be. A value you set higher yourself is left alone.
7. **Verify Your Trio Classes**: On the main window, verify your 3 detected multiclass roles (or click **Re-Detect** to let Triune scan them automatically).
8. **Configure Your Loadout**: Set up your combat spells and downtime buffs in **Spell Gems**, innate skills in **Abilities**, activated AAs in **AAs**, disciplines in **Disciplines**, and clickies in **Clickies**.
9. **Pick a Mode & Go**: On the **Control** tab, select your combat mode (**Manual**, **Puller**, or **Assist**) and click **Start** (or type `/ac run`)!

---

## Combat Modes

Triune keeps things simple with **3 main combat modes**:

| Mode | Best For | How It Works |
|---|---|---|
| **Manual** | When you want to drive | You control movement and pick where to go. Triune handles attacking, casting your 3-class loadout spells, using AAs/discs, and healing allies. When the fight is over, it will walk back to your camp if you have one set. Three checkboxes on the Control tab decide how much it moves for you: **Auto-Target Hostiles on XTarget** (pick up and switch between mobs on your XTarget list), **Stick to Target in Combat** (chase and stick to the NPC being fought — untick it to fight from wherever you stand; `/ac manualstick`), and **Auto-Nav to Selected Target** (walk to a hostile NPC the moment you select it; `/ac manualnav`, off by default). |
| **Puller** | The group leader / puller | Automates finding and engaging mobs. Comes in two flavors:<br>• **`Camp`**: Runs out, tags a mob (with a spell, bow, melee hit, or pet), brings it back to camp, and tanks it there.<br>• **`Hunt`**: Roams around the zone, finds mobs, and kills them right where they stand. |
| **Assist** | Box characters & helpers | Follows and assists your Main Assist (MA). Automatically positions behind the attacked NPC so only the MA tanks in front (toggleable via checkbox or `/ac assistbehind`). Comes in three flavors:<br>• **`Chase`**: Runs right behind the MA and attacks whatever the MA targets.<br>• **`Camp`**: Holds position at camp and only hits mobs that get brought into camp.<br>• **`Backline`**: For healers and casters — stays safely at range and never charges into melee. |

Every mode fights using one of **3 combat styles** (Settings tab -> *Combat Style & Positioning*, or `/ac style`):

| Style | Best For | How It Works |
|---|---|---|
| **Melee** | Warriors, monks, rogues, any melee trio | Closes to melee reach (**Melee Distance**, 5-50, default 14) and swings with `/attack on`. |
| **Ranged (bow)** | Rangers, bow/throwing users | Stands off at **Combat Distance** (5-200, default 40) and fires the equipped ranged weapon. Uses this server's `#attackmode ranged` toggle plus `/attack on` (Triune waits for the server's "Attack mode changed" confirmation, and falls back to firing anyway after 3 unanswered tries). Switching back to Melee or Spell sends `#attackmode melee` so you don't keep shooting a bow later. |
| **Spell** | Pure caster trios | Stands off at **Combat Distance** and never auto-attacks (no `/attack`, no `/autofire`) — the Spell Gems loadout does all the damage. Triune still faces the mob and re-closes if it drifts out of range. |

The pull method (Melee / Spell / Pet / Ranged) is separate from the combat style: a bow-tag-then-melee puller is *Ranged* pull with *Melee* style.

---

## Key Features

### 📊 Real-Time Status & Diagnostics Dashboard
- **Primary Status Tab**: A dedicated tactical overview tab right next to Control displaying live engine state, active combat modes/submodes, and subsystem indicators.
- **Current Target Hero Card**: Real-time target stats (Level, Class, Race, Con Color), dynamic color-coded HP bar, distance, Line-of-Sight, melee range indicator, aggro holder (Target-of-Target), and 1-click action buttons (`Face`, `Attack`, `Clear`, `+ Pull List`, `+ Ignore List`).
- **MQ2Nav & MoveUtils Navigation Stack**: Live plugin and zone navmesh status with automatic startup plugin autoloading (`mq2nav` and `mq2moveutils`), chat window warnings on missing dependencies, inline UI recovery buttons (`[Load MQ2Nav]`, `[Load MQ2MoveUtils]`, `[Reload Mesh]`), active navigation destination tracking, path length/distance calculations, detour obstacle avoidance timers, and anti-stuck metrics.
- **Player, Trio & Pet Vitals**: Visual HP, Mana, and Endurance progress bars, character action flags (Combat, Moving, Ducking, Sitting, Feigning, Levitation), Gestalt Trio class badges with slot theme colors, and live pet status (HP, Target, and Pet Hold threshold state).
- **Interactive Extended Target (XTarget) Threat Monitor**: Live threat table displaying all active hostile combatants with level, distance, health bars, aggro holder, and 1-click targeting buttons. Each row also carries **F** (Force: the engine stays on that spawn until it dies, then moves on to the rest of the list) and **I** (Ignore: the engine skips that spawn until the toggle is cleared; any number can be ignored) buttons, in every mode.
- **Troubleshooting Log & Diagnostic Dump**: Settings -> General has *Debug Diagnostic Logging* (extra telemetry in chat), *Log To File* (`/ac log on`) which writes every Triune and plugin chat line - plus the debug lines when Debug is on - to `Logs/triune_<server>_<char>.log` in your MacroQuest folder (rotates at 8 MB, plugin errors carry full tracebacks), and *Dump Diagnostics Now* (`/ac dump`) which writes a one-shot `Logs/triune_dump_<server>_<char>_<timestamp>.log` snapshot with a live TLO summary, every setting, combat/pull state, plugin status and the last 500 log lines - attach that file to a bug report. A crash in the main loop also writes its traceback and a dump before MQ reports it.

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
  - **One Pet Per Class, Never Shown Twice**: Each pet class of the trio tracks exactly one pet, a pet is never listed under two classes, and pet lists are deduplicated by name (pet names are unique per player on this server). A `missing pet` gem only fires for its own class's pet, waits for a summon in flight to land before re-casting, and pins the new pet to the casting class even when `Me.Pet` does not change. Learned pet names (`ctrl.pet_names`) map pets back to their classes after a restart or zone.

---

### 🧩 Modular Plugin System (`lua/tac/` & Settings Sub-Page)
Triune features a plug-and-play plugin architecture designed to keep the core combat engine blazing fast while allowing custom and auxiliary features to be dropped in seamlessly:
- **Drop-and-Play Directory (`lua/tac/`)**: Any `.lua` plugin placed into `lua/tac/` (or `TAC/lua/tac/`) is automatically recognized and loaded by Triune.
- **Dedicated Settings -> Plugins Tab**: View all loaded plugins, enable/disable toggles, live latency and execution time profiling (`Last ms` and `Avg ms`), author/version details, and embedded configuration panels. The **Header** column decides which plugin windows get a toggle button on the main window's top toolbar (with a Show/Hide shortcut right there); open windows are highlighted on the toolbar.
- **Coroutine Fiber Execution ("Green Threads")**: Plugins run in their own dedicated coroutine fibers with custom tick intervals (e.g. 1.0s or 50ms) rather than firing every combat tick.
- **Combat Latency Elimination**: Non-combat plugins automatically enter `Sleeping (Combat)` mode during active combat, preserving 100% of CPU cycles for combat logic.
- **Crash Isolation**: Every plugin execution and render pass is wrapped in crash-containment guards. A faulty plugin displays an error tooltip and will never crash Triune or EverQuest.
- **Safe Drop-Ins & Standalone Scripts**: only files that return a plugin table (an `id` or lifecycle hooks) are loaded as plugins. Any other runnable `.lua` file dropped into the folder (a standalone MQ script, a data file, anything without the plugin contract) gets a basic entry under **Settings -> Plugins -> Standalone Scripts** with **Run / Stop** buttons that launch it as its own `/lua run` process, completely independent of Triune, plus a **Re-check** button that loads it as a plugin once it conforms. Tick **Header Btn** to put a Run / Stop button for the script on the main window header (highlighted while the script runs) and type a **Button Name** for it (blank = file name). A standalone script cannot start its own `mq.delay` loop on the core, register ImGui callbacks, or bind commands while being inspected. Files with syntax errors or a duplicate plugin id are listed under *Failed to load* with the reason and Retry / Dismiss buttons.
- **Plugins Included**:
  - `hud_unitframes.lua`: Popout HUD for Player, Target, and Pet vitals (50ms throttled snapshots, stays live in combat).
  - `hud_group.lua`: Popout Group window with vitals bars, role badges, member pets, Invite/Disband, and click-to-target.
  - `hud_effects.lua`: Popout Effects & Songs window with spell icons, time-left bars, sorting, and Remove/Block/Inspect actions.
  - `hud_xtarget.lua`: Popout Extended Target window with HP bars, aggro %, distance/LoS, ToT, per-row Force/Ignore toggles, and right-click actions.
  - `hud_cooldowns.lua`: The popout Cooldown & Ability Monitor window with live timers, filters, and click-to-fire.
  - `hud_spellgems.lua`: Popout Spell Gem Bar with recast timers, casting overlays, spell-set presets, and right-click actions.
  - `spellbook.lua`: The Spellbook Browser (formerly the standalone `triune_spellbook.lua` script) - per-class spell database browser with scribed status, filters, spell info, and a mem-to-gem queue; `/ac spellbook` / `/ac book` toggle it.
  - `auto_accept.lua`: Automated group, trade, and expedition/DZ invite acceptance with group/guild rules and whitelisting; owns the **Auto-Accept** popout window (header button, `/ac autoaccept`).
  - `auto_aa.lua`: Priority-based AA spending through the game's AA window (no MQ2AAspend), Fireworks cap spender and auto-summon; owns the **Auto AA** popout window (header button, `/ac aawin`) and the `/ac autoaa` commands.
  - `floating_damage.lua`: Flashy animated floating damage numbers for critical hits, crippling blows, deadly strikes, and spell crits - elastic impact pop, outlined text with a count-up number, BIG / HUGE / MASSIVE damage tiers with particle bursts, shockwave rings, rainbow shimmer, screen flash and shake, a combo streak counter with milestone shouts, and NEW RECORD! callouts; text scale, effects intensity and tier thresholds are adjustable in its settings panel.
  - `map.lua`: The 2D Map, Norrath Zone Atlas & NPC Tracker (formerly `triune_map.lua`) - camp / hunter anchor / waypoint / hazard overlays are mirrored from the live core config; `/ac map` / `/ac track` toggle it.
  - `dps.lua`: The DPS Parser (formerly `triune_dps.lua`) - parses combat chat into per-fight player / multi-pet breakdowns even while its window is hidden; `/dps` and `/ac dps` toggle it.
  - `inventory.lua`: The Inventory & Bank Manager (formerly `triune_inv.lua`) - bag moves, stack combines, sorts and character-to-character gives run in the plugin fiber through the cooperative `core.delay`; the **Box Inventories** tab shows every other box's bags / bank / worn gear over the Box Network and hands items between characters through the trade window; `/ac inv` toggles it.
  - `buffbot.lua`: The Buffbot Station (formerly `triune_buffbot.lua`) - off until switched on (`/ac buffbot on` or the window button), holds the combat loop while casting a buff job.
  - `cursor.lua`: The Cursor Item Manager (formerly `triune_cursor.lua`) - one `/autoinventory` per tick instead of a blocking loop; `/ac cursorui` toggles it.
  - `boxnet.lua`: The **Box Network** - communication between your boxed characters on the same computer over MacroQuest's native **Actors** API (no EQBC / DanNet needed): live peer roster with vitals, `/ac net <all|zone|group|Name> <command>` to run any `/ac` command on other boxes, Follow Me / Set Me as MA / Camp Here buttons, ping, an allowlist, and a `core.boxnet` message API for other plugins.
  - `chat.lua`: **Chat Windows** - a chat window replacement: every chat line is captured through one catch-all event, classified into 45 channels by pattern, and shown in any number of popout windows with filtered tabs, colours, timestamps, highlights, mutes, per-tab logs and an input line with inline clickable item links; `/tacchat` and `/ac chat` toggle it.
  - `gamedb.lua`: **Game Database** - an offline copy of the Project Triune item / NPC / spell database read from `resources/gamedb/`: every item with stats, effects and Base / Enchanted / Legendary tiers, where it drops (server-accurate chance), which quest NPCs reward or take it, the tradeskill recipes that make or use it; every NPC with stats, spawn zones, loot, spells, faction and vendor list; every spell with classes, costs, decoded effects and the items / NPCs that carry it. No network, no extra plugins; `/ac db`, `/ac item`, `/ac npc`, `/ac spell` open it.
  - `buttons.lua`: **Hot Buttons** - a Button Master-style replacement for EverQuest's hot button bars: a button library shared by every character, named sets shown as tabs, any number of hotbars per character, cooldown overlays (spell gem / AA / disc / ability / item / manual / custom Lua), one-click capture from whatever is on your cursor, drag-and-drop, Button Master share strings, and a one-click `ButtonMaster.lua` import; `/ac btn`, `/btn <n>`, `/btnexec` toggle and fire them.
  - `update_check.lua`: **Update Checker** - asks GitHub for the latest published Triune release and tells you in chat (and a small popup with the release notes, **Copy Release Link**, **Skip This Version**, **Remind Me Later**) when it is newer than the copy you are running. Check only, nothing is downloaded. It never spawns a process: LuaJIT's `ffi` drives the `WinHttp.WinHttpRequest.5.1` COM object that ships with Windows (and Wine) in async mode, and `onTick` polls for completion with calls that cannot wait, so the game never hitches. One automatic check 20 s after load (Settings -> Plugins -> Update Checker: every session / daily / weekly / off, popup on/off), `/ac update` any time.
- **Writing a Plugin**: a plugin is a Lua file in `lua/tac/` that returns a table. Metadata fields: `id`, `name`, `version`, `author`, `description`, `defaultEnabled`, `tickInterval` (seconds), `runOutOfCombatOnly`, `hasThread`, and `uses` for soft links to other plugins (`uses = { boxnet = 'what the link is for' }` or a plain id list): the Plugins tab's **Uses** column shows them, amber when the used plugin is off or missing, and the used plugin's row shows *(used by N)* with the reverse list in its tooltip. `uses` is informational - a plugin must keep working (feature off) when a used plugin is absent, the way `buttons` / `dps` / `hud_group` guard `core.boxnet` and `hud_spellgems` guards `pm.getWindow('spellbook')`. Lifecycle hooks (all optional): `onInit(core)`, `onDestroy()`, `onTick()`, `onDrawUI()`, `onDrawSettings()`, `onCombatTick(targetId)`, `onZoned(zoneShortName)`, `onLoadoutSaved()`, `onSaveSettings()` -> table, `onLoadSettings(table)`. Combat-loop hooks: `wantsCombatHold()` -> true makes the combat loop stand still (used while the AA window is open); `onBetweenPulls()` -> return true to make the puller yield this tick. Command hooks: `onCommand(cmd, args)` -> return true if you handled `/ac <cmd>`, and `plugin.help = { 'line', ... }` adds lines to `/ac help`. Windows: declare `plugin.window = { label = 'Map', tooltip = '...', flag = 'show_map', headerButton = true, order = 20 }` (`flag` is the `ctrl.*` boolean that drives visibility, or give `isOpen()` / `setOpen(bool)` functions) and the core draws a highlighted toggle button for it on the main window header - the user picks which plugins get one in the Plugins tab's **Header** column (`headerButton` is the default), `order` sorts the buttons. The same declaration registers the window on Settings -> Windows (position save / restore / center, Show / Hide) automatically: optional `key` sets the position key used with `core.preBeginWindow(key)` (defaults to the plugin id), `lockFlag = 'my_lock'` (a `ctrl.*` boolean) or `getLock()` / `setLock(bool)` adds the Locked toggle, `desc` is the row tooltip, and `defaultPos = { x, y, w, h }` is used by *Reset to Defaults*. A plugin with more than one window lists the others in `plugin.windows = { { key = 'target_window', label = 'Target', flag = 'show_target_window', ... }, ... }` (same fields, `key` required and unique - it is the layout key); the core addresses each as `'<pluginId>:<key>'` everywhere (`pm.getWindow`, `pm.toggleWindow`, `pm.setHeaderButton`), lists it after the plugin's main window on the header and on Settings -> Windows, and keeps its header-button choice in `ctrl.plugins[pluginId].windowHeader[key]` (`hud_unitframes` declares its Target popout this way). The `core` table passed to `onInit` exposes `mq`, `ImGui`, a **live** `ctrl` (always the current character's config), `loadout`, `runtime`, `DATA`, `VERSION`, `saveLoadout`, `colors`, and UI helpers (`pushTheme`/`popTheme`, `accent`, `setTooltip`, `preBeginWindow`/`postBeginWindow`, `drawStatusProgressBar`, `drawSpellIcon`, `getConColorRgb`, `resolveTargetOfTarget`, `getMultiPetList`, `getPetSpawnInfo`, `isSpawnAlive`, `addIgnore`, `parseDurationSec`, `fmtSec`, `idxOf`, `toggleTool`). `core.log` is the diagnostic logger: `core.log.debug('myplugin', 'fmt %d', n)` lines only appear while Debug Mode is on, `core.log.info` / `warn` / `error` are always kept, and every level lands in the log file when *Log To File* is on (plain `print` lines are captured there too, so existing output needs no changes). `core.delay(ms, cond)` is a cooperative stand-in for `mq.delay` inside a plugin fiber (`hasThread = true`): it yields the fiber back to the main loop each tick until the time elapses or `cond()` is true, so a sequential workflow (casting, bag moves) never stalls the combat loop; never call `mq.delay` from a plugin. Store persistent options on `core.ctrl` so they save with the loadout.

---

### 💬 Chat Windows: A Chat Window Replacement (Popout Windows)
The `chat.lua` plugin replaces EverQuest's chat windows with ImGui windows you control - open them with the **Chat** header button, `/tacchat` or `/ac chat` (`/chat` itself is an EQ command). EQ's own windows stay where they are; shrink them to a corner once you are happy.
- **Channels, not colours**: every incoming line (game text and Triune / MQ output alike) is sorted by its wording into one of 45 channels - Social (say, NPC dialogue, tells in / out, group, guild, raid, OOC, auction, shout, emotes, `/join` channels, pet chat, the `#server` commands Triune sends through `/say`), Combat (this server's abbreviated melee numbers and `miss`, your / others' / taken melee, crits, flurry-rampage, your pet, your / others' / taken spell damage, spell effect text, DoTs, damage shields, heals, casting, deaths, resists, combat messages) and Info (experience, loot & money, item effects / upgrades, buffs landed / worn, skill ups, faction, consider, zone, system, Triune, MQ, unclassified). Anything the classifier does not know lands in **Unclassified** rather than disappearing; **Capture lines to file** (`/tacchat capture on`) writes every line with its channel to `logs/tac_chat_capture_<Name>.txt` so new patterns can be added.
- **Windows and tabs**: each window has tabs, each tab is a filter - a channel set (All / None / presets Social, Combat, Loot, Tells, Triune, or tick channels one by one), *only lines containing* / *hide lines containing* keyword lists, its own send channel (Say / Group / Guild / Raid / OOC / Auction / Shout / Tell + target), an unread badge, and optional logging to `logs/tac_chat_<Name>_<tab>_<date>.txt`. **Right-click a tab** (or empty log space) for everything else: filters & settings, new / move / close tab, move a tab to another window, log to file, clear, jump to bottom, and a Window submenu with title, **font scale**, UI scale, opacity, lock, new / close window. **Split / panes** shows several tabs at once in one window - a tab into a new pane on the right or below (up to six, side by side or stacked), move tabs between panes, drag the splitter to resize, unsplit. There is no toolbar - a window is tabs, log and input line. Defaults: one window with **All / Social / Combat / Loot & XP / Tells / Notifications / Triune**. The **Notifications** tab collects only the lines that mention your name or hit a highlight word (all channels, so you never miss a mention while reading another tab); *Notifications only* in any tab's Filters & settings turns that tab into one, and the channel / keyword filters still apply on top.
 Layout, filters and colours save per character in `config/triune_chat_<Name>.lua`.
- **Reading**: per-channel colours (right-click -> Colours...), timestamps, **Highlights** (a word or phrase drawn in its own colour, with tab flash and optional `/beep`), **Mentions** (another player saying your name - whole word, any case, on say / tells / group / guild / raid / OOC / auction / shout / emotes / channels - is drawn in the mention colour, flashes the tab, and can beep; Triune output, NPC dialogue and your own lines do not count), **Muted senders**, and right-click on any line for Copy / Reply / Target / Invite / Mute. Item names are clickable inline links that open the item window for anything you carry or have banked (MQ cannot open this server's links for items you do not have; the **Links** menu lists the last 20 either way).
- **Typing**: press **Enter** to open the chat input (like the game's windows: it goes to the input you last used, or the first window's active tab), type, Enter sends and hands the keyboard back. `/commands` go straight through, plain text goes to the tab's send channel, Up / Down recall history. Turn *Enter opens the input* off (tab menu or General settings) to keep the input focused after each send instead.
- **Tells**: with the send channel on Tell, the arrow next to the target lists the last five people you exchanged tells with - pick one to reply. **Click a player's name** in any chat line (tells, say, group, guild, raid, OOC, auction, shout) and the **Tells window** opens with a tab for that person - only your conversation with them, input already set to tell them, cursor in it. Right-click a line for the same (*Tell X (Tells window)*), or *Reply to X here* to keep it in the current tab; `/tacchat tell <name>` does it from a command. Turn on **Incoming tells open the Tells window** (right-click a tab, or General settings) and arriving tells add their tab too, with an unread badge instead of stealing the one you are typing in - the game's tell windows folded into one. Middle-click a tab (or *Close tab*) to drop a conversation; closing the last one, or the window, closes it, and the next tell or name click brings it back. (Middle-click closes any tab in any window, as long as the window keeps one.)

- **Ghost windows**: *Ghost: only the text until the mouse is over it* in a window's menu (right-click a tab -> Window) makes that window invisible except for its text - the title bar, tabs, background, border, input line and scrollbar fade out when the mouse leaves and fade back in under it. The window keeps its place and size, so it still takes the mouse for scrolling and dragging, it stays drawn in full while one of its menus is open or you are typing in its input, and `/tacchat ghost [window]` toggles it from a command. Per window, so a ghosted combat log can sit over the game while the main window stays solid.
- **Tells and notifications survive a crash**: every tell (in or out) and every line that lands in a Notifications tab (a mention of your name or a highlight hit) is written to `config/triune_chat_history_<Name>.txt` the moment it arrives, and the next start - after a camp, a `/lua` reload or a client crash - puts the last ones back into the Tells and Notifications tabs only (and into a person's tab in the Tells window when it reopens; nothing restored lands in All / Social), under whatever arrives next, with the date in the timestamp of lines from another day. **Clear notifications** in the Notifications tab's right-click menu drops every notification from the tab, from memory and from the history file (tells stay). On by default; **Keep tells and notifications across restarts** in General settings (or the tab menu) turns it off, and `/tacchat history on|off|clear` does the same from a command. Nothing else is kept this way - the per-tab log files are for that. The same lines also live in their own buffer in memory, sized by **Tell / notification lines kept** (1000 by default, 100-5000) and separate from *Buffer lines*: a conversation tab in the Tells window, the Tells tab and the Notifications tab read from it, so a fight's thousands of combat lines rolling through the main buffer never empty a conversation that is still open (general tabs roll with *Buffer lines* as before).
- Commands: `/tacchat show|hide|toggle|focus|settings|clear|tab <name>|tabs|window new|close <name>|mute|unmute <name>|timestamps|capture on|off|history on|off|clear|ghost [window]|stats|reset` (also as `/ac chat ...`).

---

### 📚 Game Database: Offline Item, NPC & Spell Lookup (Popout Window)
The **Database** header button (`/ac db`) opens an in-game copy of the Project Triune database - the same data PTDex shows - that works in any zone with no network access and no extra MacroQuest plugins:
- **Items**: search by name or ID (`/ac item <text>`, or **Cursor Item** for whatever you are holding). The **Filters** block under the search box narrows the list by **class**, **race**, **slot**, **item type**, **required level** range, **effect** (has any / click / proc / worn / focus / none), **Tradeable** (hides NO DROP) and **minimum AC / HP / mana**; **Top tier** takes those minimums from the item's Legendary / Enchanted stats instead of the base item. **Sort** orders every match by AC, HP, mana or required level (highest first, top 300 shown with the full match count), so an empty search with *Warrior + Chest + Sort: AC* is a best-in-slot list. The card shows the icon, flags (MAGIC / LORE / NO DROP / ATTUNEABLE / QUEST ...), slot, type, size and weight, level requirements, classes and races, AC / HP / mana / endurance, stats with heroics, resists, damage / delay / ratio, mods (haste, regen, spell damage ...), click / proc / worn / focus / scroll effects (click through to the spell), augment slots, container and value. **Base / Enchanted / Legendary** tabs switch tiers. Below the stats: **Drops From** (NPC, level, zone and the drop chance computed the way the server rolls its loot tables), **Quests** (the NPC that rewards or takes the item, from the server's quest scripts), **Tradeskill: Made By** (recipe, tradeskill, skill needed, trivial, components and container) and **Used In**, foraged / fished / ground-spawn zones, and **Sold By**.
- **NPCs**: search by name, filter by zone and level range (`/ac npc <text>`). The card shows level, race, class, body type, HP / mana / AC, damage and attack delay, run speed, resists, stats, special abilities (summons, rampages, immunities ...), see-invis / hide, faction and faction hits, **Spawns In** (zone, spawn points, respawn time, chance), **Drops** with chances, **Casts** (spell list with NPC spell types), quest rewards and turn-ins, and the vendor list.
- **Spells**: search by name, filter by class and level range (`/ac spell <text>`, e.g. everything a level 40 Cleric can learn). The card shows classes and levels, mana / endurance, cast / recast / recovery, duration at your level, target, range, resist type and adjust, skill, components, the decoded **effect lines** (Lucy-style text for the common effects, raw SPA values for the rest), the client's description, the **items** that click / proc / focus / teach it, and the **NPCs** that cast it.
- Every name in a card is a link - drops open the NPC, the NPC's loot opens the item, an item's click effect opens the spell - with **Back / Forward** history. Clicking an item link in a Chat Windows log opens a small **popout card** for that exact item and tier (carried or not - the link carries the item ID), and the tab menu's **Look up in Database** opens it in the full window. Every item, spell and NPC card has a **Link to chat** button that links it the way the game's input line takes a dragged item: the link lands in the Chat Windows input line as `[Name]` and goes out as a real clickable item link when you send (right-click the button to send it straight to Say / Group / Guild / Raid / OOC / Auction / Shout). The client has no spell or NPC links, so those go out as plain `[Spell Name]` / `[NPC Name (Zone)]` text that everyone can read and that Triune's chat windows draw as a clickable card; `/ac linkitem`, `/ac linkspell`, `/ac linknpc`, `/ac linkcursor` and `/ac linktarget` do the same from the command line, and a chat line's right-click menu re-links any item someone else posted.
- **Spell Info replacement**: EverQuest's own Spell Display window (right-click a spell gem, a buff, a spellbook page) is replaced by the spell's popout card - the window is closed the frame it opens and the card takes its place, with everything above plus a **Scribed - Gem N** line. Triune's own Inspect / Display Spell Info actions (Gems bar, Effects window, Spellbook Browser) open the card directly. Spells the database does not know keep the game window. `/ac spellwindow` (or the Plugins page checkbox) turns the replacement off; `/ac spellinfo <name|id>` opens a card by hand.
- **Beyond lookups**: the combat loop asks the database before the first cast, so mez / slow / snare / charm / fear / stun / dispel are never wasted on NPCs whose special abilities make them immune (one chat line says why). `/ac dbtarget` opens a card for your target. **Inventory** tooltips end with the item's tiers, top dropper, quest NPCs, recipe and vendor facts (Shift+Right-click a slot for the card). **Spellbook** tooltips show decoded effects and where each scroll comes from (middle-click for the card). While looting, the **Loot Advisor** window lists the corpse's items with their drop chance on that NPC (rare drops flagged), value and quest / recipe notes (`/ac lootadvisor` toggles it). NPC spawn rows have a **Map** button that opens the Zone Atlas on that zone.
- The data lives in `resources/gamedb/` (about 180 MB of plain text: an index per type plus chunked record files) and ships with the **full release** only. Indexes preload in small per-frame slices from the moment Triune starts (about ten seconds in the background; a progress bar shows if you open the window before they are done), searches are instant, and a card is one seek in the record file. `tools/build_gamedb.py` rebuilds the folder from a server database dump and quest script tree (`python3 tools/build_gamedb.py --sql release-peq.sql --quests Release-NMS-Quests`); the item filters need the v2 `items.idx`, which `python3 tools/build_gamedb.py --reindex-items` regenerates from an installed database without the dump (a v1 index still searches, the Filters block just says so).

### 📡 Box Network: Talk Between Your Boxes (Popout Window)
Running two, three, or six characters on one computer? The **Box Network** plugin (`tac/boxnet.lua`) lets every Triune instance on that computer see and steer the others - built on MacroQuest's native **Actors** messaging, so there is nothing extra to install: the `MacroQuest.exe` launcher you already run is the hub that routes messages between your EverQuest clients.
- **Peer Roster with Live Vitals**: Every box broadcasts a one-second heartbeat (trio classes, zone, mode, Running / Paused, Burn, HP / Mana / End, current target, Main Assist, pet). The **Box Net** window (header button, `/ac net`) lists every other box, how long ago it was seen, and its round-trip ping.
- **Remote `/ac` Commands**: `/ac net all burn on`, `/ac net zone pause`, `/ac net group puller camp`, `/ac net Bob ma Alice` - the receiving box simply runs `/ac <command>` locally, so every existing command works across boxes on day one. Direct sends are round-trips: the sender is told when a box refused (allowlist, commands disabled) or could not be reached.
- **One-Click Group Control**: **Run / Pause / Burn On / Burn Off** for the selected scope (all boxes, same zone, or my group), **Follow Me** (sets you as Main Assist and switches them to Assist (Chase)), **Set Me as MA**, and **Camp Here** (pushes your current location as their camp anchor - same zone only). Per-peer Run / Pause, Burn, and Ping buttons on each roster row.
- **Trust & Safety**: By default any box connected to the same MacroQuest launcher is trusted; flip on **Only accept from the allowlist** and name the characters you box, or turn remote commands off entirely for a character. Nested `net` commands are refused on both ends so a command can never loop. Broadcasts echoed back by the launcher are dropped, and boxes on a different Triune protocol version are ignored with a one-time warning.
- **Assist Boxes Follow the MA's Real Target**: every box publishes its target (spawn ID, name, HP, engaged) in its heartbeat. An Assist box whose Main Assist is another box in the zone uses that exact target - no `/assist` spam, no blocking delay, no target clobbering - and only falls back to `/assist` when the MA isn't a fresh Box Network peer. The MA's own *engaged* state counts as proof the mob is being fought.
- **Cures Without NetBots**: Poison / Disease / Curse / Corruption counters ride in the heartbeat (the roster's **Afflict** column shows them), so `has Poison` / `has Disease` / `Cursed` / `Corrupted` cure gems aimed at a box character work without MQ2NetBots or EQBC.
- **Boxes Are Allies**: single-target heals aimed at `Lowest-HP Ally` consider your ungrouped boxes in the zone, and a mob that one of your boxes is tanking counts as engaged for the others.
- **Pullers Stay Off Each Other's Mobs**: two boxes running **Puller** (Camp or Hunt) in the same zone no longer converge on the same NPC. A puller skips any mob another box is heading for (a Puller peer's target) or already fighting (any peer's *engaged* target), and when two pullers still grab the same mob in the same instant the one that acquired it later lets go and picks something else (the heartbeat carries when each target was acquired; a same-time tie goes to the name that sorts first). A mob that is already on your XTarget or that you are fighting is never given up. Assist boxes are unaffected - following the MA onto one mob is the point. Toggle: **Settings -> Closer-NPC Retargeting -> Stay Off Other Boxes' Pulls (Box Network)** (`box_pull_coordination`, default on).
- **Buff Me (Core Loadout, Not Buffbot)**: **Buff Me** on a roster row / the scope bar, or `/ac net buffme [scope|Name]`, asks your other boxes for every friendly `missing buff` gem you lack; they cast them in their downtime pass and report back. The public Buffbot station is untouched.
- **Box Inventories & Item Transfers**: the Inventory & Bank Manager's **Box Inventories** tab (`/ac inv`) lists every box on the network on the left - zone, distance from you, item count, free slots, snapshot age - and shows the selected box's items on the right (or **All boxes** for one searchable list across every character: type a name and see who has it and where), as a sortable table or as the box's bag / bank grids with icons. Snapshots are pulled on demand (first look at the tab, selecting a box, **Refresh**, an optional auto-refresh interval) and streamed in pages, and a box announces when its items change so open viewers refresh. **Give** on any row or slot - yours or another box's - opens a picker of receivers with their distance from the giver (**Come to** sends a far box over with `/ac cometo`); the box that *holds* the item picks it up (whole stack, one, or a quantity), targets the receiver, opens the trade with `/click left target`, clicks Trade, and the receiver box clicks its own Trade button - so you can move an item from box A to box B while sitting on box C. NO TRADE and bank items are refused up front, a trade that never opens or is not accepted is cancelled and the item put back, and the outcome goes to the transfer log (and chat). Both boxes must be in the same zone within the **Trade range** setting (15 by default; the game itself refuses beyond about that). Settings -> Plugins -> Inventory (or the window's Settings tab): **Share my inventory**, **Accept give requests** (also gated by the Box Network's accept / allowlist), **Trade range**, chat announcements.
- **Group HUD & Group DPS Meter**: the popout Group window lists boxes that are not in your group with live vitals and a `[Box]` badge (toggle in its settings). The DPS parser's **Group** tab is a group DPS meter fed over the Box Network: one bar per member (you plus every box on the computer that shares a parse, grouped or not - or only your group with *Meter Scope -> Group Members*), sorted by DPS with each member's share of the combined damage, live while anyone is fighting and everybody's last fight otherwise; the compact window carries the same meter (toggle in the parser's Settings tab) and **Report Group** / `/dps group [channel]` posts it to chat. Only characters running Triune on this computer can feed the meter - the client never sees other players' damage lines.
- **Launcher Awareness & Diagnostics**: The window's *Launcher check* line runs a loopback message through `MacroQuest.exe` and says which hop is broken (`OK`, `NoConnection`, `RoutingFailed`, `no answer`) with a matching hint. `/ac net debug` dumps counters and recent events, `/ac net trace` logs every message, `/ac net probe` re-runs the check, and `/lua run triune_actortest [suffix]` is a Triune-independent Actors smoke test (open the launcher window -> **Actors** panel to see connected clients). After updating the plugin, restart Triune with `/lua run triune` once - MQ keeps an actor mailbox alive until the old Lua state is collected.
- **For Plugin Authors**: `core.boxnet` exposes `peers()`, `peer(name)`, `command(scope, lines)`, `campHere(scope)`, `ping(name)`, `broadcast(kind, data)`, `send(name, kind, data, callback)` (an RPC when a callback is given), `subscribe(kind, fn(data, sender, message))` -> unsubscribe function (`message:reply(status, payload)` answers an RPC), and `trusted(sender)` - whether the user's accept-remote-commands switch and allowlist let that box drive this one (the Inventory give flow gates on it). Payloads must be plain Lua values - MQ datatype objects cannot be serialized.

---

### 🔘 Hot Buttons: Button Master-Style Hotbars (Popout Windows)
Miss Button Master? The **Hot Buttons** plugin (`tac/buttons.lua`) is a Triune-native version of Derple's [Button Master](https://github.com/DerpleDude/buttonmaster): custom hot button bars that replace EverQuest's built-in hotbars, running inside Triune with the Triune theme, the Window Layout manager, and Box Network sync - no second script to keep running.
- **Shared Button Library & Sets**: Buttons (label, multi-line commands, icon, colours, cooldown timer) live in one file shared by every character (`config/triune_buttons.lua`). Named **sets** are sparse grids of up to 100 slots; each **hotbar** window shows one or more sets as tabs (or a single set in **Compact Mode**). Create as many hotbars per character as you like, each with its own button size (30-120 px), font scale, opacity, lock, hidden title bar, search box, and per-character or global window position. Like the other popouts there is no header chrome: right-click the window background (or any slot / tab -> **Hotbar Options**) for the menu.
- **Add From Game Browser**: Right-click an empty slot -> **Add AAs... / Spell Gems... / Abilities... / Discs... / Items... / Box Control... / Commands...** (or right-click the hotbar -> **Add From Game...**, or `/ac btn add [aa|gem|ability|disc|item]`) opens a searchable browser of what your character actually has: trained activatable AAs (`/alt act <id>` + AA timer), your spell gems (`/cast <gem>` + gem timer), trained skills (`/doability` + ability timer), disciplines (`/disc` + disc timer), and worn/bagged clickies (`/useitem` + item timer). One click creates the button with the right icon and cooldown and drops it in the slot (or the first free slot of the set, so you can keep clicking); the editor's **Fill From Game...** does the same into a button you're editing.
- **Box Control Presets**: The browser's **Box Control** tab turns the Box Net quick actions into buttons: Run, Pause, Burn On, Burn Off, Follow Me (`ma <me>` + `assist chase`), Assist Me (`ma <me>` + `assist camp`), Set Me as MA, Buff Me, Camp Here - colour-coded, using `${Me.CleanName}` so the shared library works on every box. **Add All as a Set** drops the whole row onto the hotbar as a "Box Control" tab in one click (`/ac btn add box`).
- **Box Scope Switch**: With the default **Hotbar switch** scope the buttons carry a `{scope}` token instead of a fixed target, and the hotbar grows a **Boxes: Group / Zone / All** row that decides where they send when pressed - one set of buttons serves your group or every box, and the switch is remembered per hotbar (right-click -> **Box Control Scope**, or `/ac btn scope group|zone|all|next [hotbar]` for a keybind). Pick **All boxes / Same zone / My group** in the tab instead to bake a fixed scope into the buttons (`Run (grp)`, `Run (all)`, ...). The row only appears while the bar holds switch-driven buttons and can be hidden from the hotbar menu.
- **Commands Pick List**: The browser's **Commands** tab lists every Triune slash command as a button - a curated core list grouped by Control / Mode / Main Assist / Style / Toggle / Window / Setting (with ready-made variants such as Burn On, Burn Off, Puller (Camp), Assist (Chase), MA = Target, Style: Ranged) plus every loaded plugin's help commands pulled live. Commands that take an `<argument>` open the editor pre-filled so you can type it in (`/ac btn add cmd`).
- **Simple Styling**: The editor has swatch rows of basic colours for the button background and its text (Default, Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, Brown, Gray, Black, White), a per-button **Font Size** (60%-200%, or the hotbar's default), Show Label, and a Reset Style button.
- **Make a Button in One Click**: Left-click an empty slot with a spell gem, item, ability, discipline, AA, social, or command on your cursor and the editor opens pre-filled (`/cast <gem>`, `/useitem "Name"`, `/doability`, `/disc`, `/alt act`, or the social's command lines) with the matching icon and cooldown timer. Right-click a slot to assign any existing button, edit, duplicate, unassign, delete, or copy its share string; drag a button onto another slot (even on another hotbar) to swap them.
- **Cooldown Overlays**: A dark sweep with a countdown covers each button while its timer runs - **Spell Gem**, **AA**, **Disc**, **Ability**, **Item** clicky, a manual **Seconds Timer** that starts when the button fires, or **Custom Lua** (remaining / total / active-toggle expressions). Labels and icons can be Lua too (`return string.format("HP %d%%", mq.TLO.Me.PctHPs())`), and each button has its own evaluation rate.
- **Zero-Latency Clicks**: Command buttons issue their lines the instant they are clicked (no waiting for the core's 150 ms loop pass), and `--lua` script buttons start immediately as their own coroutine that is pumped every frame, so `delay()` inside a script yields for exactly that long without stalling the combat loop.
- **Button Master Compatible**: Share strings use Button Master's format - paste a friend's Button Master button or set straight into **Import Button or Set...**, and your exports work in Button Master. **Import Button Master Config** (Settings -> Plugins -> Hot Buttons, or `/ac btn import bm`) converts an existing `ButtonMaster.lua` - buttons, sets, and this character's windows - in one click. `/btn [n]`, `/btnexec "<set>" <index>`, and `/btncopy <server> <char>` keep working.
- **Box Network Sync**: Saving on one box tells the other Triune boxes on the computer to reload the shared library, so a button edited on your tank shows up on your cleric.
- **Group Window "Come"**: On the popout Group window, any member that is one of your Box Network boxes (in your zone) gets a small **Come** button next to its distance - it sends `/ac net <Name> cometo <you>` and that box navigates to you with MQ2Nav (`/ac cometo <Name> | stop` is the command it runs).

---

### 🤝 Auto-Accept & Social Automation (Popout Window)
Triune includes a dedicated **Auto-Accept** popout window (provided by the `auto_accept.lua` plugin - open it with the **Auto-Accept** header button or `/ac autoaccept`; disable or reload the plugin from Settings -> Plugins):
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

### 🔍 UI Scale
Running at 4K, or on a laptop? **Settings -> Window Layout -> UI Scale** (or `/ac scale <0.75-2.0>`, `/ac scale reset`) sizes every Triune window - text, buttons, bars, columns and padding - in one go; the popout HUDs, the hotbars, the DPS parser, the map and the dialogs all follow. Any window can override the global factor: the **Scale** column of the Window Layout table covers all of them, and the popout HUDs and the Mini HUD have the same picker in their right-click menu (*Global (1.00x)* or a preset from 0.75x to 2.00x). Saved with the loadout. Fonts are stretched rather than re-rendered, so for crisp text at large factors raise MQ's own overlay font size as well - the two compose.

**Every window has the same right-click menu.** Right-click empty space in any Triune window - the main window, the Mini HUD, every popout HUD, the parser (full and compact), the map, the database and its popout cards, the hotbars, the dialogs - for the window's options: **Hide title bar** (a clean overlay with no bar and no close button; drag the window by its body, and the same menu closes it or brings the bar back), **Ghost: fade the frame when the mouse is away** (background, border, title bar and scrollbar fade out when the mouse leaves and back in under it while the contents stay - pair it with the hidden title bar for a HUD that is only its content), **Lock position & size**, the per-window **UI scale**, a **Window layout** submenu to save or restore every window's position, and **Close window**. Windows that already had a right-click menu (the HUDs, the Mini HUD, the hotbars, the chat windows' tab menu) carry the same items inside it. Saved per window with the loadout.

---

### 📱 Compact Mini HUD
Want to clear up screen clutter while playing? Switch to the **Mini HUD** (`/ac compact` or the **Compact Mode** header button) - one dense column that tells you what the engine is doing:
- **Header**: the same green PAUSE / red START and pulsing BURN buttons as the full window, the mode and submode combos, **Full** (back to the tabbed window) and **Menu**.
- **Activity line**: RUNNING / PAUSED plus what is happening right now - *Pulling a gnoll scout*, *Bringing the pull to camp*, *Fighting ...*, *In combat*, *Casting ...*, *Roaming for a target*, *Following the Main Assist*, *Returning to camp*, *Med break*, *Resting - HP below N%*, or what the mode is waiting for.
- **Target bar**: your target with level / class / distance, aggro (or *tanking*), a *no LoS* warning and an HP bar; in Assist mode (or with a Main Assist set) the MA and the MA's target with a one-click **Target** button.
- **My vitals**: HP / Mana / Endurance bars (no mana bar for manaless classes).
- **Camp row** (Manual, Puller Camp, Assist Camp): distance to camp (amber when you are outside its radius), **Set Here** and **Clear**; warns when the puller has no camp.
- **Session tracker**: session time, **AA/hr**, **plat/hr** and **Reset**.
- **Plugin buttons**: the same window / script toggle buttons as the main window header, picked per plugin on **Settings -> Plugins** (open windows and running scripts highlighted) - so every plugin with a window shows up, not a fixed list.
- MQ2Nav / navmesh / MQ2MoveUtils warnings with a Load / Reload button, as in the full window.
- **Menu** (or right-click the window): hide any row, lock the position, hide the title bar, turn on **Ghost mode** (the background, border, title bar and buttons fade out when the mouse leaves the window and back in under it, leaving just the text and bars - also `/ac ghost [on|off]`), set the opacity, or go back to the full window. Everything is saved with the loadout (`mini_*`).

---

### 🔮 Decoupled Spell Gems & Downtime Buff Swapping
- **Unlimited Decoupled Spell List**: Configure as many spells as you need beyond the physical 12-gem limit.
- **Per-Spell Gem Dropdown**: Assign each spell line to any physical gem slot (Gem 1 to Gem 12). Multiple spells can share the same physical gem (e.g., a primary combat nuke and several long-duration buffs sharing Gem 12).
- **Dynamic Spell Management**: 1-click `+ Add Spell` button to append new lines, `^` and `v` priority buttons to reorder evaluation order, and `X` button to delete lines.
- **1-Click "Mem All" Restoral**: The `Mem All` toolbar button (and `/ac memall` command) scans all 12 physical slots, shows a pending queue count badge (e.g. `Mem All (3)`), and systematically rememorizes missing or mismatched priority combat spells in strict numerical order.
- **1-Click "Import Bar" Auto-Population**: The `Import Bar` toolbar button (and `/ac importbar` / `/ac import` command) reads all currently memorized spells from your in-game spell gems and automatically populates the Spell Gems page with era-accurate class, default targets, and condition triggers to make character setup effortless.
- **Bard `Twist` Box (Keep Singing vs Sing Once)**: Every Bard spell line gets a `Twist` checkbox. Checked, the song is sung over and over whenever its trigger is met, even while its effect shows as up -- for songs that only work while you are singing them (most detrimental songs on this server). Unchecked, the song is sung once and left alone until Triune sees the effect drop, then sung again -- for beneficial songs, which stay up after one sing here. Picking a song (or `Import Bar`) sets the box from the song's beneficial/detrimental flag; the older `twist while fighting` trigger still works and means `in combat` + `Twist`.
- **Automated Downtime Buff Swapping**: When out of combat, stationary, and not casting, Triune automatically swaps missing buffs into their assigned gems, waits for recharge, and casts them.
- **Instant Aggro Interruption**: If aggro is detected at any point during a swap, Triune instantly stands up, closes the spellbook, engages combat, and kills all enemies on XTarget before safely resuming the swap.
- **Primary Combat Spell Restoration**: Once all downtime buffs for a shared gem are cast, Triune automatically re-memorizes the primary combat spell back to that gem so your combat bar is always ready.

---

### ⏱️ Cooldown & Ability Monitor
Keep track of every enabled combat ability, activated AA, discipline, spell gem, and clickie item in real time:
- **Popout Window** (provided by the `hud_cooldowns.lua` plugin): open it with the **Cooldowns** header button, `/ac cd`, `/ac cooldowns`, the Mini HUD, or the Window Layout manager.
- **Active Duration Tracking**: Glowing cyan progress bars show remaining active buff/stance duration (e.g. *Defensive Discipline*, *Harmshield*, *Furious*) before transitioning to cooldown.
- **Smart Readiness Diagnostics**: Instant feedback on why abilities are gated: `[READY]`, `[LOW END]`, `[LOW MANA]`, `[NEED BURN]`, `[NEED BOSS]`, `[MIN XTAR]`, or `[LOCKED]`.
- **EverQuest Timer Groups**: Badges display EQ shared timer banks (`[T1]`, `[T2]`, `[T4]`) to clarify shared cooldown lockouts.
- **1-Click Execution**: Interactive **`[ Use ]`** buttons allow manual firing of any ready ability directly from the monitor.
- **Dual View Modes & HUD Overlay**: Switch between a detailed Table View and a sleek horizontal HUD Cards View with background transparency opacity slider and window position lock.
- **In-Place Loadout Tuning**: Optional inline editing controls enabling live adjustment of `Enabled`, threshold `HP %`, and `Burn Only` toggles directly from the monitor.

---

### 🌟 Alternate Advancement (AA) Progression & Auto-Training
Keep your character progressing without wasting unspent AA points with the dedicated **Auto AA** popout window (provided by the `auto_aa.lua` plugin - open it with the **Auto AA** header button or `/ac aawin`; the plugin also owns the `/ac autoaa` command family and can be disabled or reloaded from Settings -> Plugins):
- **Comprehensive AA Browser**: Automatically scans and lists all available character Alternate Advancement abilities, displaying real-time ranks, max ranks, point costs, training eligibility, and total points spent.
- **Compact Two-Row Header Layout**: Real-time unspent/spent pool metrics, master auto-spend toggle, buy order dropdown, cap threshold slider, instant search box with `X` clear, sort criteria combo, `▲ Asc / ▼ Desc` toggle, `Hide Maxed` filter, `Prio Only` filter, and live ability count badge.
- **Instant Search & Multi-Sort**: Search abilities by name in real time, sort by **Name** (A-Z / Z-A), **Cost** (cheapest first / highest first), or **Fully Trained** status, and filter with one-click **Hide Maxed** and **Prioritized Only** checkboxes.
- **Priority-Based Auto-Training through the AA window**: Check the priority box `[x]` next to any abilities you want Triune to train. Once your unspent pool reaches the **Bank** threshold (out of combat, standing still), Triune purchases the next rank of the cheapest (or alphabetically first) affordable priority itself - no MQ2AAspend involved. The window trainer commands the EverQuest UI directly: it opens the AA window (`/keypress TOGGLE_ALTADVWIN`), selects the target tab, highlights the ability row, clicks the in-game Train button, confirms the unspent total dropped, and closes the window again (restoring the *Can Purchase* filter if it had to toggle it). Purchases are verified via point and rank deltas; unpurchasable abilities (due to level restrictions or missing prerequisites) are backed off for five minutes so Auto AA never gets stuck and advances to subsequent priorities. **Spend Now** buys the top affordable priority immediately, ignoring the threshold.
- **Custom Buy Order**: Choose between **Cheapest First** (maximize quick rank gains by buying lowest cost abilities first) or **Alphabetical** order.
- **Cap Protection & Fireworks Dump**: Automatically protects against the server AA cap by dumping surplus points into fireworks (or any configured ability) when your pool reaches the cap threshold (default: 100 AA).

---

## Built-in Bonus Tools

Triune comes packed with handy companion tools (all in-process plugins in `lua/tac/`) you can open right from the main window, the Mini HUD, the Window Layout manager, or via chat commands:

| Tool | Chat Command | What It Does |
|---|---|---|
| ⏱️ **Cooldown Monitor** | `/ac cd` | Standalone popout live ability, AA, and discipline cooldown monitor with active buff duration countdowns, smart diagnostics, timer groups, next-up forecast, and 1-click execution. |
| 🎯 **Target & Player HUD** | `/ac hud` | Standalone popout compact unit frames window with pulsing auto-attack aggro outline, target buffs, ToT, player vitals, multi-pet status, and right-click settings. The target section sits in a fixed-height box at the top, so the player bars never shift as the target or its buffs change. Cast bars: the target's under its HP bar, yours after the mana / endurance bars with the seconds left. The pet section lists every pet you own - trio slot pets, swarm pets, familiars - with a count, class tag, HP, the pet's target, and click-to-target. |
| 🎯 **Target Window** | `/ac target` | The target frame on its own (name / level / distance / LoS, HP bar with the auto-attack pulse, the target's cast bar, ToT and aggro, buff chips) in a popout with its own scale, bar height, opacity, lock, and ToT / buff toggles - scale it up and park it where you can always see what you are on. Opened from the HUD's right-click menu, `/ac target`, Settings -> Windows, or an optional header button. |
| 👥 **Popout Group Window** | `/ac group` | Standalone popout group window replacing EQ's default group window with auto-scaling vitals, role & leader badges, pet tracking, offline/other-zone states, and right-click settings. |
| ⚔️ **Popout XTarget Window** | `/ac xtar` | Standalone popout extended target window replacing EQ's default with auto-scaling health bars, current target highlight, ToT, aggro %, distance, LoS, per-row **F**orce / **I**gnore toggles (stay on one spawn until it dies / skip one spawn until cleared), and right-click settings. |
| 🔮 **Popout Spell Gem Bar** | `/ac gems` | Standalone popout spell gem bar window replacing EQ's default with dual orientations (Vertical/Horizontal), Compact vs Full layouts, live recast overlays, casting progress, and right-click spell inspection. |
| 🗺️ **2D Map & Norrath Atlas** | `/ac map` | `map.lua` plugin: interactive 2D vector map, Norrath Zone Atlas & Travel Explorer, live NPC radar, Point of Interest locator, and Triune camp / waypoint / hazard overlays read straight from the live config. |
| 🧙 **Spellbook Browser** | `/ac spellbook` | In-process plugin (`tac/spellbook.lua`) window: browse and search all spells across all 3 of your character's classes, filter by level or type, inspect them, and queue them to a gem with one click (memorized through the core's spellbook-aware trainer). |
| 🖱️ **Cursor Manager** | `/ac cursorui` | `cursor.lua` plugin: displays what's on your cursor, auto-inventories or destroys it, optional continuous auto-clear, and a session history log (`/ac clearcursor` for a quick dump). |
| 🛡️ **Interactive Buffbot** | `/ac buffbot [on\|off]` | `buffbot.lua` plugin: run an automated buffing station! Listens for `/tell` requests from nearby players, hands out buffs (pets too), guild priority / guild-only policies, ignore list, auto-med, anti-AFK, and sends a reply when done. The station stays off until you start it. |
| 📊 **DPS Parser** | `/dps` or `/ac dps` | `dps.lua` plugin: live combat parser tracking player damage, spell hits, DoTs, and pet DPS with historic fight logs, a Box Network group DPS meter (Group tab / compact window), and a compact window; keeps parsing while the window is hidden. |
| 🎯 **Zone NPC Tracker** | `/ac track` | The map plugin's NPC Tracker tab: lists all NPCs in the zone by distance and level. Double-click any mob (or click `[Nav]`) to run straight to it! |
| 📜 **Quest Guide & Lookup** | `/lua run triune_quest` | Standalone interactive quest guide and atlas across 32 expansions with live NPC radar, dialogue triggers, inventory scanner, Norrath Zone Directory, and global quest search. |
| 🎒 **Inventory & Bank Manager** | `/ac inv` | `inventory.lua` plugin: universal inventory, worn equipment, bank, and shared bank search, container grid visualizer, stack consolidator, offline bank cache persistence, and a **Box Inventories** tab - every other box's items in one searchable list (or its bag grids) with **Give** to move an item to any character on the network. |
| 📡 **Box Network** | `/ac net` | `boxnet.lua` plugin: see and steer your other boxed characters on this computer over MacroQuest Actors - live vitals roster, `/ac net <scope> <command>` remote commands, Follow Me / Set Me as MA / Camp Here, ping, allowlist. |
| 💬 **Chat Windows** | `/tacchat` or `/ac chat` | `chat.lua` plugin: chat window replacement - 45 pattern-classified channels, any number of windows with filtered tabs, colours, timestamps, highlights, mutes, per-tab logs, inline clickable item links and an input line. |
| 🔘 **Hot Buttons** | `/ac btn` | `buttons.lua` plugin: Button Master-style hot button bars - shared button library, tabbed sets, multiple hotbars per character, cooldown overlays, cursor capture, drag-and-drop, Button Master share strings and config import. |
| 📚 **Game Database** | `/ac db` | `gamedb.lua` plugin: offline item / NPC / spell database (PTDex data in game, any zone, no network) - item stats and tiers, drops with server-accurate chances, quest NPCs, tradeskill recipes, NPC spawns / loot / spells / faction, spell effects and who carries or casts them. |
| 🔔 **Update Checker** | `/ac update` | `update_check.lua` plugin: checks GitHub for a newer Triune release without hitching the game (async WinHTTP through LuaJIT ffi, no external process) - chat notice plus a popup with release notes, copy-link, skip-this-version and remind-me-later; automatic once per session / day / week or manual only. |
| 🤖 **LLM Test Harness & QA Agent** | `/lua run triune_test` | Standalone in-game testing harness interfacing with local LLMs (LM Studio) and cloud LLMs (Google Gemini, OpenCode) for autonomous QA testing via non-blocking bridge. |

---

## Slash Commands

You can control almost everything using simple in-game chat commands:

| Command | Aliases | What It Does |
|---|---|---|
| `/ac` | | Start or pause autocombat |
| `/ac run` | `/ac start` | Start autocombat |
| `/ac pause` | `/ac stop` | Pause autocombat and stop moving |
| `/ac pausezone [on\|off]` | `/ac zonepause`, `/ac pauseonzone` | Toggle automatic script pause when zoning (default: on) |
| `/ac fov [50-150\|on\|off]` | `/ac setfov`, `/ac camfov` | Configure camera Field of View (50-150 units) and maintain across zoning |
| `/ac burn [on\|off]` | `/ac burnon`, `/ac burnoff` | Toggle Burn mode on/off |
| `/ac memall` | `/ac mem`, `/ac remem` | Queue all missing or mismatched priority spells to memorization bar |
| `/ac importbar` | `/ac import`, `/ac importgems` | Auto-populate spell lines from currently memorized spell gems |
| `/ac debug` | `/ac diag`, `/ac debugmode` | Toggle live combat debug telemetry in chat |
| `/ac log [on\|off\|path]` | `/ac logfile` | Write all Triune chat + debug output to `Logs/triune_<server>_<char>.log`; `path` prints the file location |
| `/ac dump` | `/ac dumpstate`, `/ac snapshot` | Write a one-shot diagnostic snapshot file (settings, state, plugin status, recent log lines) |
| `/ac compact` | `/ac mini` | Toggle the compact Mini HUD |
| `/ac ghost [on\|off]` | `/ac minighost` | Ghost mode for the Mini HUD: the frame fades when the mouse is away |
| `/ac hud` | `/ac uf`, `/ac unitframes`, `/ac targetwin` | Toggle the popout Target & Player HUD unit frames window |
| `/ac target` | `/ac tw`, `/ac targetwindow`, `/ac targetframe` | Toggle the popout Target-only window (a big target frame) |
| `/ac group` | `/ac gw`, `/ac groupwin` | Toggle the popout Group Window |
| `/ac eff` | `/ac effects`, `/ac buffs`, `/ac songs` | Toggle the popout Effects & Songs Window (unified buffs, songs, timers, and icons) |
| `/ac xtar` | `/ac xt`, `/ac xtarget`, `/ac xtwin` | Toggle the popout Extended Target (XTarget) window |
| `/ac gems` | `/ac gembar`, `/ac spellbar`, `/ac castbar` | Toggle the popout Spell Gem Bar window |
| `/ac cd` | `/ac cooldowns`, `/ac cds` | Toggle the popout Cooldown & Ability Monitor window |
| `/ac scale [0.75-2.0\|reset]` | `/ac uiscale` | Scale every Triune window (per-window overrides on Settings -> Window Layout or a popout's right-click menu) |
| `/ac winpos [save\|restore\|reset]` | `/ac savewindows`, `/ac restorewindows` | Save or restore popout window screen coordinates and dimensions |
| `/ac status` | | Print current status and mode to chat |
| `/ac restart` | `/ac reload` | Stop and re-run the whole script (same as `/lua stop triune` then `/lua run triune`); also the **Restart Triune** button on Settings -> General |
| `/ac help` | `/ac ?` | Show command help in chat |
| `/ac <mode> [submode]` | | Switch mode (e.g. `/ac manual`, `/ac puller camp`, `/ac assist chase`, `/ac backline`) |
| `/ac ma [target\|clear\|<name>\|<id>]` | `/ac mainassist` | Configure Main Assist by player ID or name, or set from current PC target |
| `/ac xtardist [25-300]` | `/ac xtar`, `/ac xtarrange` | Configure max XTarget / assist engagement chase distance (default: 150) |
| `/ac chasedist [5-100]` | `/ac chase`, `/ac followdist` | Configure following distance (how far to stay back) from Main Assist (default: 15) |
| `/ac selfdefense [on\|off]` | `/ac assistdefend`, `/ac defend` | Toggle Assist mode self-defense when attacked while MA has no target |
| `/ac assistbehind [on\|off]` | `/ac behind`, `/ac posbehind` | Toggle Assist mode positioning behind NPC in combat (default: on) |
| `/ac manualstick [on\|off]` | `/ac stick` | Manual mode: stick to / chase the NPC being fought (default: on). Off = you drive; Triune only attacks/casts when the NPC is in reach |
| `/ac manualnav [on\|off]` | `/ac autonav` | Manual mode: auto-navigate to a hostile NPC as soon as you select it (default: off) |
| `/ac pullhp [0-95]` | `/ac minhp` | Set minimum HP % threshold before pausing pulling to rest until 100% |
| `/ac pullcon [preset\|con]` | `/ac con`, `/ac confilter` | Configure faction filters (`hostile`, `indifferent`, `all`, `none`) or toggle single considerations |
| `/ac wp [add\|clear\|del\|on\|off\|list]` | `/ac waypoint`, `/ac waypoints` | Manage waypoint patrol routes, arrival radius, and scan distance |
| `/ac huntz [10-300]` | `/ac z` | Configure Hunter Tier 2 max vertical height difference (default: 75) |
| `/ac zplane [5-100]` | `/ac huntplane`, `/ac floorz` | Configure Hunter Tier 1 same-floor / Z plane height threshold (default: 15) |
| `/ac spellbook` | `/ac book` | Open the Spellbook Browser |
| `/ac cursorui` | `/ac cursormgr` | Open the Cursor Manager |
| `/ac update [now\|show\|skip\|unskip\|auto on\|off\|link]` | `/ac checkupdate`, `/ac updater` | Check GitHub for a newer Triune release (non-blocking); show the notice, skip / unskip a version, toggle the automatic check, copy the release link |
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
| `/ac style [melee\|ranged\|spell]` | `/ac combatstyle` | Set combat style (no argument prints the current one) |
| `/ac range [dist]` | `/ac dist` | Set the distance for the active style: melee (5-50) or ranged/spell (5-200) |
| `/ac meleerange [5-50]` / `/ac rangeddist [5-200]` | | Set a specific distance regardless of the active style |
| `/ac track` | `/ac zone` | Toggle the Map window on the NPC Tracker tab |
| `/ac map` | `/ac mapui` | Toggle the 2D Map & Norrath Zone Atlas window |
| `/dps [show\|hide\|compact\|reset\|pause\|resume\|report <chan>\|group <chan>]` | `/triunedps`, `/ac dps` | Toggle the DPS parser window and control it; `group` posts the Box Network group meter |
| `/ac net` | `/ac boxnet` | Toggle the Box Network window (boxed characters on this computer) |
| `/ac net <all\|zone\|group\|Name> <command>` | | Run any `/ac` command on the matching boxes (e.g. `/ac net all burn on`, `/ac net Bob pause`) |
| `/ac net peers` | `/ac net list` | Print the roster of boxes with zone, mode, state, and vitals |
| `/ac net ping <Name>` | | Round-trip ping to a box (also checks the MacroQuest launcher is routing) |
| `/ac net camp [all\|zone\|group\|Name]` | `/ac net camphere` | Push your current location as the camp anchor to boxes in this zone |
| `/ac net buffme [all\|zone\|group\|Name]` | `/ac net buffs` | Ask your other boxes for the loadout buffs you are missing (core loadout, not Buffbot) |
| `/ac net debug` | `/ac net diag` | Print Box Network diagnostics (identity, counters, launcher loopback, recent events) |
| `/ac net trace` | | Toggle logging of every sent / received message to the Box Net event log |
| `/ac net probe` | `/ac net loopback` | Re-run the launcher loopback check |
| `/lua run triune_actortest [suffix]` | | Standalone MacroQuest Actors smoke test (no Triune involved) |
| `/lua run triune_update_check [verbose]` | | Standalone release-check diagnostic (no Triune involved): times every call of the async WinHTTP transport the Update Checker plugin uses |
| `/ac btn` | `/ac buttons`, `/ac hotbar` | Toggle the Hot Buttons hotbars (Button Master-style) |
| `/ac btn <n>` | `/btn <n>` | Show / hide hotbar n (`/btn` alone toggles all hotbars) |
| `/ac btn new` | | Create another hotbar for this character |
| `/ac btn add [aa\|gem\|ability\|disc\|item\|box\|cmd]` | `/ac btn browse` | Open the Add From Game browser on that tab (AAs, spell gems, skills, discs, clickies, Box Control presets, Triune commands) |
| `/ac btn exec <set> <index>` | `/btnexec "<set>" <index>` | Fire the button in slot `<index>` of set `<set>` |
| `/ac btn scope [group\|zone\|all\|next] [hotbar]` | | Set (or cycle) where a hotbar's Box Control buttons send; no hotbar number = the first bar holding such buttons; no scope = print the current one |
| `/ac btn import [bm]` | | Open the share-string importer, or import `config/ButtonMaster.lua` |
| `/ac btn copy <server> <char>` | `/btncopy <server> <char>` | Copy another character's hotbars onto this one |
| `/ac btn list` | | Print every set and its buttons to chat |
| `/ac cometo <Name>` | `/ac come`, `/ac moveto`, `/ac cometo stop` | Navigate to a player in this zone (what a box runs when you click **Come** on the Group window) |
| `/triunerun` | | Fast keybind command to toggle start/pause |
| `/lua run triune_quest` | `/lua stop triune_quest` | Launch or stop the standalone Triune Quest Guide window |
| `/ac inv` | `/ac inventory`, `/ac bank` | Toggle the Inventory & Bank Manager window |
| `/ac inv give <Name> <item\|id> [qty]` | | Hand one of your items to another box through the trade window (the receiver box accepts by itself) |
| `/ac inv find <text>` | | Search every box's inventory snapshot for an item and print who has it where |
| `/ac inv refresh [Name]` | | Ask your other boxes for fresh inventory snapshots |
| `/ac cursorui` | `/ac cursormgr` | Toggle the Cursor Item Manager window |
| `/ac db` | `/ac gamedb`, `/ac database` | Toggle the Game Database window (items / NPCs / spells); `/ac db <text>` searches items |
| `/ac item <name\|id>` | | Search the Game Database for an item and open the window |
| `/ac npc <name\|id>` | | Search the Game Database for an NPC |
| `/ac spell <name\|id>` | | Search the Game Database for a spell |
| `/ac dbcursor` | | Look up the item on your cursor in the Game Database |
| `/ac dbtarget` | | Open a Game Database card for your current target (stats, abilities, spawns, loot) |
| `/ac lootadvisor` | | Toggle the Loot Advisor window shown while looting a corpse |
| `/ac spellwindow` | | Toggle replacing the game's Spell Info window with a Game Database spell card |
| `/ac spellinfo <name\|id>` | | Open the Spell Info card for a spell |
| `/ac linkitem [/channel] <name\|id>` | | Put an item link in the Chat Windows input line (`/g`, `/gu`, `/tell Name`... sends it there instead) |
| `/ac linkspell [/channel] <name\|id>` | | The same for a spell link |
| `/ac linknpc [/channel] <name\|id>` | | The same for an NPC link (`[Name (Zone)]`) |
| `/ac linkcursor [/channel]` | | Link the item on your cursor |
| `/ac linktarget [/channel]` | | Link the database NPC behind your current target |
| `/ac buffbot [on\|off\|toggle]` | `/ac buff` | Toggle the Buffbot window; `on` / `off` start or stop the buffbot station |
| `/lua run triune_test` | `/lua stop triune_test` | Launch or stop the standalone In-Game LLM Test Harness & QA Agent |

---

## File Structure

```
TriuneAutocombat/
├── TAC/
│   ├── triune_llm_bridge.py # External asynchronous Python bridge daemon for LLM testing
│   ├── start_bridge.bat     # Windows LLM bridge launcher
│   ├── start_bridge.sh      # Linux/macOS LLM bridge launcher
│   ├── tools/
│   │   └── build_triune_quest.py # Quest database compilation script
│   ├── lua/
│   │   ├── triune.lua           # Main autocombat engine & Mini HUD
│   │   ├── triune_log.lua       # File-backed diagnostic logger (/ac log, /ac dump)
│   │   ├── triune_quest.lua     # Standalone Quest Guide, radar & dialogue assistant
│   │   ├── triune_test.lua      # Standalone In-Game LLM Test Harness & QA Agent
│   │   └── tac/                 # Modular plugin directory (lua/tac/*.lua)
│   │       ├── hud_unitframes.lua # Popout Unit Frames HUD plugin
│   │       ├── hud_group.lua    # Popout Group window plugin
│   │       ├── hud_effects.lua  # Popout Effects & Songs window plugin
│   │       ├── hud_xtarget.lua  # Popout Extended Target window plugin
│   │       ├── hud_cooldowns.lua # Popout Cooldown Monitor plugin (/ac cd)
│   │       ├── hud_spellgems.lua # Popout Spell Gem Bar plugin
│   │       ├── spellbook.lua    # Spellbook Browser plugin (/ac spellbook)
│   │       ├── auto_accept.lua  # Auto-Accept group/trade/DZ invites plugin (Auto-Accept window, /ac autoaccept)
│   │       ├── auto_aa.lua      # Auto AA spender plugin (Auto AA window, /ac aawin, /ac autoaa)
│   │       ├── floating_damage.lua # Floating critical damage numbers plugin
│   │       ├── map.lua          # 2D in-game map, Norrath Zone Atlas & NPC tracker plugin (/ac map)
│   │       ├── dps.lua          # DPS parser plugin (/dps, /ac dps)
│   │       ├── inventory.lua    # Inventory & Bank manager plugin (/ac inv)
│   │       ├── buffbot.lua      # Tell-driven buffbot station plugin (/ac buffbot)
│   │       ├── cursor.lua       # Cursor item manager plugin (/ac cursorui)
│   │       ├── boxnet.lua       # Box Network plugin: MQ Actors inter-box comms (/ac net)
│   │       ├── buttons.lua      # Hot Buttons plugin: Button Master-style hotbars (/ac btn)
│   │       └── gamedb.lua       # Game Database plugin: offline item / NPC / spell lookup (/ac db)
│   ├── config/
│   │   └── triune_data.lua      # Era-correct spell and ability database
│   └── resources/
│       ├── ItemDB.txt           # Item database lookup
│       ├── Zones.ini            # Zone configuration metadata
│       ├── MQ2Nav/              # Pre-packaged zone navigation meshes (.nav)
│       ├── gamedb/              # Offline game database for the Game Database plugin (full release only)
│       │   ├── items.idx, items.N.dat   # item index + chunked records (stats, tiers, drops, quests, recipes)
│       │   ├── npcs.idx, npcs.N.dat     # NPC index + records (spawns, loot, spells, faction, vendor)
│       │   ├── spells.idx, spells.N.dat # spell index + records (classes, effects, items, casters)
│       │   └── zones.idx, manifest.txt  # zone names, build date and counts
│       └── triune_quest/        # Pre-packaged quest database (catalog & per-zone packages)
│           ├── catalog.lua      # Lightweight global search index
│           ├── expansions.lua   # Expansion metadata & levels
│           └── zones/           # Partitioned per-zone quest walkthroughs (169 zones)
├── tools/
│   └── build_gamedb.py      # Builds resources/gamedb/ from a server SQL dump + quest scripts (not shipped)
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

Current version: **2.15**

See [CHANGELOG.md](CHANGELOG.md) for full release notes and update history.
