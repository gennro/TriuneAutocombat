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
  - **One Pet Per Class, Never Shown Twice**: Each pet class of the trio tracks exactly one pet, a pet is never listed under two classes, and pet lists are deduplicated by name (pet names are unique per player on this server). A `missing pet` gem only fires for its own class's pet, waits for a summon in flight to land before re-casting, and pins the new pet to the casting class even when `Me.Pet` does not change. Learned pet names (`ctrl.pet_names`) map pets back to their classes after a restart or zone.

---

### 🧩 Modular Plugin System (`lua/tac/` & Settings Sub-Page)
Triune features a plug-and-play plugin architecture designed to keep the core combat engine blazing fast while allowing custom and auxiliary features to be dropped in seamlessly:
- **Drop-and-Play Directory (`lua/tac/`)**: Any `.lua` plugin placed into `lua/tac/` (or `TAC/lua/tac/`) is automatically recognized and loaded by Triune.
- **Dedicated Settings -> Plugins Tab**: View all loaded plugins, enable/disable toggles, live latency and execution time profiling (`Last ms` and `Avg ms`), author/version details, and embedded configuration panels. The **Header** column decides which plugin windows get a toggle button on the main window's top toolbar (with a Show/Hide shortcut right there); open windows are highlighted on the toolbar.
- **Coroutine Fiber Execution ("Green Threads")**: Plugins run in their own dedicated coroutine fibers with custom tick intervals (e.g. 1.0s or 50ms) rather than firing every combat tick.
- **Combat Latency Elimination**: Non-combat plugins automatically enter `Sleeping (Combat)` mode during active combat, preserving 100% of CPU cycles for combat logic.
- **Crash Isolation**: Every plugin execution and render pass is wrapped in crash-containment guards. A faulty plugin displays an error tooltip and will never crash Triune or EverQuest.
- **Safe Drop-Ins & Standalone Scripts**: only files that return a plugin table (an `id` or lifecycle hooks) are loaded as plugins. Any other runnable `.lua` file dropped into the folder (a standalone MQ script, a data file, anything without the plugin contract) gets a basic entry under **Settings -> Plugins -> Standalone Scripts** with **Run / Stop** buttons that launch it as its own `/lua run` process, completely independent of Triune, plus a **Re-check** button that loads it as a plugin once it conforms. A standalone script cannot start its own `mq.delay` loop on the core, register ImGui callbacks, or bind commands while being inspected. Files with syntax errors or a duplicate plugin id are listed under *Failed to load* with the reason and Retry / Dismiss buttons.
- **Plugins Included**:
  - `hud_unitframes.lua`: Popout HUD for Player, Target, and Pet vitals (50ms throttled snapshots, stays live in combat).
  - `hud_group.lua`: Popout Group window with vitals bars, role badges, member pets, Invite/Disband, and click-to-target.
  - `hud_effects.lua`: Popout Effects & Songs window with spell icons, time-left bars, sorting, and Remove/Block/Inspect actions.
  - `hud_xtarget.lua`: Popout Extended Target window with HP bars, aggro %, distance/LoS, ToT, and right-click actions.
  - `hud_cooldowns.lua`: The popout Cooldown & Ability Monitor window with live timers, filters, and click-to-fire.
  - `hud_spellgems.lua`: Popout Spell Gem Bar with recast timers, casting overlays, spell-set presets, and right-click actions.
  - `spellbook.lua`: The Spellbook Browser (formerly the standalone `triune_spellbook.lua` script) - per-class spell database browser with scribed status, filters, spell info, and a mem-to-gem queue; `/ac spellbook` / `/ac book` toggle it.
  - `auto_accept.lua`: Automated group, trade, and expedition/DZ invite acceptance with group/guild rules and whitelisting; owns the **Auto-Accept** popout window (header button, `/ac autoaccept`).
  - `auto_aa.lua`: Priority-based AA spending (native AA window trainer or MQ2AAspend delegation with fallback), Fireworks cap spender and auto-summon; owns the **Auto AA** popout window (header button, `/ac aawin`) and the `/ac autoaa` commands.
  - `floating_damage.lua`: Flashy animated floating damage numbers for critical hits, crippling blows, deadly strikes, and spell crits - elastic impact pop, outlined text with a count-up number, BIG / HUGE / MASSIVE damage tiers with particle bursts, shockwave rings, rainbow shimmer, screen flash and shake, a combo streak counter with milestone shouts, and NEW RECORD! callouts; text scale, effects intensity and tier thresholds are adjustable in its settings panel.
  - `map.lua`: The 2D Map, Norrath Zone Atlas & NPC Tracker (formerly `triune_map.lua`) - camp / hunter anchor / waypoint / hazard overlays are mirrored from the live core config; `/ac map` / `/ac track` toggle it.
  - `dps.lua`: The DPS Parser (formerly `triune_dps.lua`) - parses combat chat into per-fight player / multi-pet breakdowns even while its window is hidden; `/dps` and `/ac dps` toggle it.
  - `inventory.lua`: The Inventory & Bank Manager (formerly `triune_inv.lua`) - bag moves, stack combines and sorts run in the plugin fiber through the cooperative `core.delay`; `/ac inv` toggles it.
  - `buffbot.lua`: The Buffbot Station (formerly `triune_buffbot.lua`) - off until switched on (`/ac buffbot on` or the window button), holds the combat loop while casting a buff job.
  - `cursor.lua`: The Cursor Item Manager (formerly `triune_cursor.lua`) - one `/autoinventory` per tick instead of a blocking loop; `/ac cursorui` toggles it.
  - `boxnet.lua`: The **Box Network** - communication between your boxed characters on the same computer over MacroQuest's native **Actors** API (no EQBC / DanNet needed): live peer roster with vitals, `/ac net <all|zone|group|Name> <command>` to run any `/ac` command on other boxes, Follow Me / Set Me as MA / Camp Here buttons, ping, an allowlist, and a `core.boxnet` message API for other plugins.
  - `buttons.lua`: **Hot Buttons** - a Button Master-style replacement for EverQuest's hot button bars: a button library shared by every character, named sets shown as tabs, any number of hotbars per character, cooldown overlays (spell gem / AA / disc / ability / item / manual / custom Lua), one-click capture from whatever is on your cursor, drag-and-drop, Button Master share strings, and a one-click `ButtonMaster.lua` import; `/ac btn`, `/btn <n>`, `/btnexec` toggle and fire them.
- **Writing a Plugin**: a plugin is a Lua file in `lua/tac/` that returns a table. Metadata fields: `id`, `name`, `version`, `author`, `description`, `defaultEnabled`, `tickInterval` (seconds), `runOutOfCombatOnly`, `hasThread`. Lifecycle hooks (all optional): `onInit(core)`, `onDestroy()`, `onTick()`, `onDrawUI()`, `onDrawSettings()`, `onCombatTick(targetId)`, `onZoned(zoneShortName)`, `onLoadoutSaved()`, `onSaveSettings()` -> table, `onLoadSettings(table)`. Combat-loop hooks: `wantsCombatHold()` -> true makes the combat loop stand still (used while the AA window is open); `onBetweenPulls()` -> return true to make the puller yield this tick. Command hooks: `onCommand(cmd, args)` -> return true if you handled `/ac <cmd>`, and `plugin.help = { 'line', ... }` adds lines to `/ac help`. Windows: declare `plugin.window = { label = 'Map', tooltip = '...', flag = 'show_map', headerButton = true, order = 20 }` (`flag` is the `ctrl.*` boolean that drives visibility, or give `isOpen()` / `setOpen(bool)` functions) and the core draws a highlighted toggle button for it on the main window header - the user picks which plugins get one in the Plugins tab's **Header** column (`headerButton` is the default), `order` sorts the buttons. The same declaration registers the window on Settings -> Windows (position save / restore / center, Show / Hide) automatically: optional `key` sets the position key used with `core.preBeginWindow(key)` (defaults to the plugin id), `lockFlag = 'my_lock'` (a `ctrl.*` boolean) or `getLock()` / `setLock(bool)` adds the Locked toggle, `desc` is the row tooltip, and `defaultPos = { x, y, w, h }` is used by *Reset to Defaults*. The `core` table passed to `onInit` exposes `mq`, `ImGui`, a **live** `ctrl` (always the current character's config), `loadout`, `runtime`, `DATA`, `VERSION`, `saveLoadout`, `colors`, and UI helpers (`pushTheme`/`popTheme`, `accent`, `setTooltip`, `preBeginWindow`/`postBeginWindow`, `drawStatusProgressBar`, `drawSpellIcon`, `getConColorRgb`, `resolveTargetOfTarget`, `getMultiPetList`, `getPetSpawnInfo`, `isSpawnAlive`, `addIgnore`, `parseDurationSec`, `fmtSec`, `idxOf`, `toggleTool`). `core.delay(ms, cond)` is a cooperative stand-in for `mq.delay` inside a plugin fiber (`hasThread = true`): it yields the fiber back to the main loop each tick until the time elapses or `cond()` is true, so a sequential workflow (casting, bag moves) never stalls the combat loop; never call `mq.delay` from a plugin. Store persistent options on `core.ctrl` so they save with the loadout.

---

### 📡 Box Network: Talk Between Your Boxes (Popout Window)
Running two, three, or six characters on one computer? The **Box Network** plugin (`tac/boxnet.lua`) lets every Triune instance on that computer see and steer the others - built on MacroQuest's native **Actors** messaging, so there is nothing extra to install: the `MacroQuest.exe` launcher you already run is the hub that routes messages between your EverQuest clients.
- **Peer Roster with Live Vitals**: Every box broadcasts a one-second heartbeat (trio classes, zone, mode, Running / Paused, Burn, HP / Mana / End, current target, Main Assist, pet). The **Box Net** window (header button, `/ac net`) lists every other box, how long ago it was seen, and its round-trip ping.
- **Remote `/ac` Commands**: `/ac net all burn on`, `/ac net zone pause`, `/ac net group puller camp`, `/ac net Bob ma Alice` - the receiving box simply runs `/ac <command>` locally, so every existing command works across boxes on day one. Direct sends are round-trips: the sender is told when a box refused (allowlist, commands disabled) or could not be reached.
- **One-Click Group Control**: **Run / Pause / Burn On / Burn Off** for the selected scope (all boxes, same zone, or my group), **Follow Me** (sets you as Main Assist and switches them to Assist (Chase)), **Set Me as MA**, and **Camp Here** (pushes your current location as their camp anchor - same zone only). Per-peer Run / Pause, Burn, and Ping buttons on each roster row.
- **Trust & Safety**: By default any box connected to the same MacroQuest launcher is trusted; flip on **Only accept from the allowlist** and name the characters you box, or turn remote commands off entirely for a character. Nested `net` commands are refused on both ends so a command can never loop. Broadcasts echoed back by the launcher are dropped, and boxes on a different Triune protocol version are ignored with a one-time warning.
- **Launcher Awareness & Diagnostics**: The window's *Launcher check* line runs a loopback message through `MacroQuest.exe` and says which hop is broken (`OK`, `NoConnection`, `RoutingFailed`, `no answer`) with a matching hint. `/ac net debug` dumps counters and recent events, `/ac net trace` logs every message, `/ac net probe` re-runs the check, and `/lua run triune_actortest [suffix]` is a Triune-independent Actors smoke test (open the launcher window -> **Actors** panel to see connected clients). After updating the plugin, restart Triune with `/lua run triune` once - MQ keeps an actor mailbox alive until the old Lua state is collected.
- **For Plugin Authors**: `core.boxnet` exposes `peers()`, `peer(name)`, `command(scope, lines)`, `campHere(scope)`, `ping(name)`, `broadcast(kind, data)`, `send(name, kind, data, callback)` (an RPC when a callback is given), and `subscribe(kind, fn(data, sender, message))` -> unsubscribe function (`message:reply(status, payload)` answers an RPC). Payloads must be plain Lua values - MQ datatype objects cannot be serialized.

---

### 🔘 Hot Buttons: Button Master-Style Hotbars (Popout Windows)
Miss Button Master? The **Hot Buttons** plugin (`tac/buttons.lua`) is a Triune-native version of Derple's [Button Master](https://github.com/DerpleDude/buttonmaster): custom hot button bars that replace EverQuest's built-in hotbars, running inside Triune with the Triune theme, the Window Layout manager, and Box Network sync - no second script to keep running.
- **Shared Button Library & Sets**: Buttons (label, multi-line commands, icon, colours, cooldown timer) live in one file shared by every character (`config/triune_buttons.lua`). Named **sets** are sparse grids of up to 100 slots; each **hotbar** window shows one or more sets as tabs (or a single set in **Compact Mode**). Create as many hotbars per character as you like, each with its own button size (30-120 px), font scale, opacity, lock, hidden title bar, search box, and per-character or global window position.
- **Add From Game Browser**: Right-click an empty slot -> **Add AAs... / Spell Gems... / Abilities... / Discs... / Items...** (or gear menu -> **Add From Game...**, or `/ac btn add [aa|gem|ability|disc|item]`) opens a searchable browser of what your character actually has: trained activatable AAs (`/alt act <id>` + AA timer), your spell gems (`/cast <gem>` + gem timer), trained skills (`/doability` + ability timer), disciplines (`/disc` + disc timer), and worn/bagged clickies (`/useitem` + item timer). One click creates the button with the right icon and cooldown and drops it in the slot (or the first free slot of the set, so you can keep clicking); the editor's **Fill From Game...** does the same into a button you're editing.
- **Simple Styling**: The editor has swatch rows of basic colours for the button background and its text (Default, Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, Brown, Gray, Black, White), a per-button **Font Size** (60%-200%, or the hotbar's default), Show Label, and a Reset Style button.
- **Make a Button in One Click**: Left-click an empty slot with a spell gem, item, ability, discipline, AA, social, or command on your cursor and the editor opens pre-filled (`/cast <gem>`, `/useitem "Name"`, `/doability`, `/disc`, `/alt act`, or the social's command lines) with the matching icon and cooldown timer. Right-click a slot to assign any existing button, edit, duplicate, unassign, delete, or copy its share string; drag a button onto another slot (even on another hotbar) to swap them.
- **Cooldown Overlays**: A dark sweep with a countdown covers each button while its timer runs - **Spell Gem**, **AA**, **Disc**, **Ability**, **Item** clicky, a manual **Seconds Timer** that starts when the button fires, or **Custom Lua** (remaining / total / active-toggle expressions). Labels and icons can be Lua too (`return string.format("HP %d%%", mq.TLO.Me.PctHPs())`), and each button has its own evaluation rate.
- **Runs on the Plugin Fiber**: Clicks are queued and executed from the plugin tick, never from the render callback, so multi-line command buttons and `--lua` script buttons can `delay()` without stalling the combat loop.
- **Button Master Compatible**: Share strings use Button Master's format - paste a friend's Button Master button or set straight into **Import Button or Set...**, and your exports work in Button Master. **Import Button Master Config** (Settings -> Plugins -> Hot Buttons, or `/ac btn import bm`) converts an existing `ButtonMaster.lua` - buttons, sets, and this character's windows - in one click. `/btn [n]`, `/btnexec "<set>" <index>`, and `/btncopy <server> <char>` keep working.
- **Box Network Sync**: Saving on one box tells the other Triune boxes on the computer to reload the shared library, so a button edited on your tank shows up on your cleric.

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
- **1-Click "Import Bar" Auto-Population**: The `Import Bar` toolbar button (and `/ac importbar` / `/ac import` command) reads all currently memorized spells from your in-game spell gems and automatically populates the Spell Gems page with era-accurate class, default targets, and condition triggers to make character setup effortless.
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
- **Priority-Based Auto-Training & Native Fallback**: Check the priority box `[x]` next to any abilities you want Triune to train. As soon as enough unspent AA points are accumulated, Triune purchases the next rank. When `MQ2AAspend` is loaded, Triune can delegate purchases to it or directly train abilities; if `MQ2AAspend` stalls or fails on server restrictions, Triune automatically falls back to its built-in native window trainer. The native window trainer commands the EverQuest UI directly, opening the AA window via internal EQ commands (`/keypress TOGGLE_ALTADVWIN`), selecting the target tab, highlighting the ability row, clicking the in-game Train button, and closing cleanly. Purchases are verified via point and rank deltas; unpurchasable abilities (due to level restrictions or missing prerequisites) are temporarily skipped so Auto AA never gets stuck and advances to subsequent priorities.
- **Custom Buy Order**: Choose between **Cheapest First** (maximize quick rank gains by buying lowest cost abilities first) or **Alphabetical** order.
- **Cap Protection & Fireworks Dump**: Automatically protects against the server AA cap by dumping surplus points into fireworks (or any configured ability) when your pool reaches the cap threshold (default: 100 AA).

---

## Built-in Bonus Tools

Triune comes packed with handy companion tools (all in-process plugins in `lua/tac/`) you can open right from the main window, the Mini HUD, the Window Layout manager, or via chat commands:

| Tool | Chat Command | What It Does |
|---|---|---|
| ⏱️ **Cooldown Monitor** | `/ac cd` | Standalone popout live ability, AA, and discipline cooldown monitor with active buff duration countdowns, smart diagnostics, timer groups, next-up forecast, and 1-click execution. |
| 🎯 **Target & Player HUD** | `/ac hud` | Standalone popout compact unit frames window with pulsing auto-attack aggro outline, target buffs, ToT, player vitals, multi-pet status, and right-click settings. |
| 👥 **Popout Group Window** | `/ac group` | Standalone popout group window replacing EQ's default group window with auto-scaling vitals, role & leader badges, pet tracking, offline/other-zone states, and right-click settings. |
| ⚔️ **Popout XTarget Window** | `/ac xtar` | Standalone popout extended target window replacing EQ's default with auto-scaling health bars, current target highlight, ToT, aggro %, distance, LoS, and right-click settings. |
| 🔮 **Popout Spell Gem Bar** | `/ac gems` | Standalone popout spell gem bar window replacing EQ's default with dual orientations (Vertical/Horizontal), Compact vs Full layouts, live recast overlays, casting progress, and right-click spell inspection. |
| 🗺️ **2D Map & Norrath Atlas** | `/ac map` | `map.lua` plugin: interactive 2D vector map, Norrath Zone Atlas & Travel Explorer, live NPC radar, Point of Interest locator, and Triune camp / waypoint / hazard overlays read straight from the live config. |
| 🧙 **Spellbook Browser** | `/ac spellbook` | In-process plugin (`tac/spellbook.lua`) window: browse and search all spells across all 3 of your character's classes, filter by level or type, inspect them, and queue them to a gem with one click (memorized through the core's spellbook-aware trainer). |
| 🖱️ **Cursor Manager** | `/ac cursorui` | `cursor.lua` plugin: displays what's on your cursor, auto-inventories or destroys it, optional continuous auto-clear, and a session history log (`/ac clearcursor` for a quick dump). |
| 🛡️ **Interactive Buffbot** | `/ac buffbot [on\|off]` | `buffbot.lua` plugin: run an automated buffing station! Listens for `/tell` requests from nearby players, hands out buffs (pets too), guild priority / guild-only policies, ignore list, auto-med, anti-AFK, and sends a reply when done. The station stays off until you start it. |
| 📊 **DPS Parser** | `/dps` or `/ac dps` | `dps.lua` plugin: live combat parser tracking player damage, spell hits, DoTs, and pet DPS with historic fight logs; keeps parsing while the window is hidden. |
| 🎯 **Zone NPC Tracker** | `/ac track` | The map plugin's NPC Tracker tab: lists all NPCs in the zone by distance and level. Double-click any mob (or click `[Nav]`) to run straight to it! |
| 📜 **Quest Guide & Lookup** | `/lua run triune_quest` | Standalone interactive quest guide and atlas across 32 expansions with live NPC radar, dialogue triggers, inventory scanner, Norrath Zone Directory, and global quest search. |
| 🎒 **Inventory & Bank Manager** | `/ac inv` | `inventory.lua` plugin: universal inventory, worn equipment, bank, and shared bank search, container grid visualizer, stack consolidator, and offline bank cache persistence. |
| 📡 **Box Network** | `/ac net` | `boxnet.lua` plugin: see and steer your other boxed characters on this computer over MacroQuest Actors - live vitals roster, `/ac net <scope> <command>` remote commands, Follow Me / Set Me as MA / Camp Here, ping, allowlist. |
| 🔘 **Hot Buttons** | `/ac btn` | `buttons.lua` plugin: Button Master-style hot button bars - shared button library, tabbed sets, multiple hotbars per character, cooldown overlays, cursor capture, drag-and-drop, Button Master share strings and config import. |
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
| `/ac compact` | `/ac mini` | Toggle the compact Mini HUD |
| `/ac hud` | `/ac uf`, `/ac unitframes`, `/ac targetwin` | Toggle the popout Target & Player HUD unit frames window |
| `/ac group` | `/ac gw`, `/ac groupwin` | Toggle the popout Group Window |
| `/ac eff` | `/ac effects`, `/ac buffs`, `/ac songs` | Toggle the popout Effects & Songs Window (unified buffs, songs, timers, and icons) |
| `/ac xtar` | `/ac xt`, `/ac xtarget`, `/ac xtwin` | Toggle the popout Extended Target (XTarget) window |
| `/ac gems` | `/ac gembar`, `/ac spellbar`, `/ac castbar` | Toggle the popout Spell Gem Bar window |
| `/ac cd` | `/ac cooldowns`, `/ac cds` | Toggle the popout Cooldown & Ability Monitor window |
| `/ac winpos [save\|restore\|reset]` | `/ac savewindows`, `/ac restorewindows` | Save or restore popout window screen coordinates and dimensions |
| `/ac status` | | Print current status and mode to chat |
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
| `/ac clearcursor` | `/ac autoinv` | Dump cursor items to inventory |
| `/ac autoaa [on\|off]` | `/ac autospendaa`, `/ac autospend`, `/ac fireworks` | Toggle automatic AA priority training & cap protection |
| `/ac aaspend [on\|off\|auto\|brute\|now]` | `/ac mq2aaspend` | Delegate AA spending to MQ2AAspend plugin (toggles delegation, sets mode, or triggers now; Triune automatically falls back to native training if stalled) |
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
| `/ac style [melee]` | `/ac combatstyle` | Set combat style (Melee) |
| `/ac range [dist]` | `/ac meleerange`, `/ac dist` | Set max melee distance (5-50) |
| `/ac track` | `/ac zone` | Toggle the Map window on the NPC Tracker tab |
| `/ac map` | `/ac mapui` | Toggle the 2D Map & Norrath Zone Atlas window |
| `/dps [show\|hide\|compact\|reset\|pause\|resume\|report <chan>]` | `/triunedps`, `/ac dps` | Toggle the DPS parser window and control it |
| `/ac net` | `/ac boxnet` | Toggle the Box Network window (boxed characters on this computer) |
| `/ac net <all\|zone\|group\|Name> <command>` | | Run any `/ac` command on the matching boxes (e.g. `/ac net all burn on`, `/ac net Bob pause`) |
| `/ac net peers` | `/ac net list` | Print the roster of boxes with zone, mode, state, and vitals |
| `/ac net ping <Name>` | | Round-trip ping to a box (also checks the MacroQuest launcher is routing) |
| `/ac net camp [all\|zone\|group\|Name]` | `/ac net camphere` | Push your current location as the camp anchor to boxes in this zone |
| `/ac net debug` | `/ac net diag` | Print Box Network diagnostics (identity, counters, launcher loopback, recent events) |
| `/ac net trace` | | Toggle logging of every sent / received message to the Box Net event log |
| `/ac net probe` | `/ac net loopback` | Re-run the launcher loopback check |
| `/lua run triune_actortest [suffix]` | | Standalone MacroQuest Actors smoke test (no Triune involved) |
| `/ac btn` | `/ac buttons`, `/ac hotbar` | Toggle the Hot Buttons hotbars (Button Master-style) |
| `/ac btn <n>` | `/btn <n>` | Show / hide hotbar n (`/btn` alone toggles all hotbars) |
| `/ac btn new` | | Create another hotbar for this character |
| `/ac btn add [aa\|gem\|ability\|disc\|item]` | `/ac btn browse` | Open the Add From Game browser on that tab (AAs, spell gems, skills, discs, clickies) |
| `/ac btn exec <set> <index>` | `/btnexec "<set>" <index>` | Fire the button in slot `<index>` of set `<set>` |
| `/ac btn import [bm]` | | Open the share-string importer, or import `config/ButtonMaster.lua` |
| `/ac btn copy <server> <char>` | `/btncopy <server> <char>` | Copy another character's hotbars onto this one |
| `/ac btn list` | | Print every set and its buttons to chat |
| `/triunerun` | | Fast keybind command to toggle start/pause |
| `/lua run triune_quest` | `/lua stop triune_quest` | Launch or stop the standalone Triune Quest Guide window |
| `/ac inv` | `/ac inventory`, `/ac bank` | Toggle the Inventory & Bank Manager window |
| `/ac cursorui` | `/ac cursormgr` | Toggle the Cursor Item Manager window |
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
│   │       └── buttons.lua      # Hot Buttons plugin: Button Master-style hotbars (/ac btn)
│   ├── config/
│   │   └── triune_data.lua      # Era-correct spell and ability database
│   └── resources/
│       ├── ItemDB.txt           # Item database lookup
│       ├── Zones.ini            # Zone configuration metadata
│       ├── MQ2Nav/              # Pre-packaged zone navigation meshes (.nav)
│       └── triune_quest/        # Pre-packaged quest database (catalog & per-zone packages)
│           ├── catalog.lua      # Lightweight global search index
│           ├── expansions.lua   # Expansion metadata & levels
│           └── zones/           # Partitioned per-zone quest walkthroughs (169 zones)
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
