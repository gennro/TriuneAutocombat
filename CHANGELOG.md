# Triune AutoCombat Change Log

## 2026-08-13

- **Fixed Lexical Scoping, Undefined Globals, ImGui ID Collisions, and Lockout Tracking in `triune.lua`.**
  - **Forward Declarations & Lexical Scoping**: Added forward declarations for `buffActive`, `updateMapRadiusVisuals`, and `isGroupOrRaidMember` at module initialization to prevent runtime `attempt to call global 'X' (a nil value)` errors when invoked before their definitions.
  - **Implemented `isGroupOrRaidMember()`**: Added a full group and raid membership checker covering player, player pet, group members, group member pets, and raid members to support Target-of-Target engagement verification in `targetIsEngaged()`.
  - **Enhanced `buffActive()` Spawn Fallback**: Added a fallback query against arbitrary spawn IDs via `mq.TLO.Spawn(id)` so non-targeted secondary adds on XTarget can have their buffs/debuffs (e.g. Mez) inspected correctly.
  - **Fixed ImGui Button ID Collisions**: Disambiguated duplicate `##id` tokens on "Set" and "Clear" buttons across the Manual, Puller, and Assist control panels (`##manualCampSet`/`##manualCampClear`, `##pullerAnchorSet`/`##pullerAnchorClear`, `##pullerCampSet`/`##pullerCampClear`, `##assistCampSet`/`##assistCampClear`, `##castLockoutSec`) to guarantee 100% reliable click routing.
  - **Repaired Spell Fail-Count & Lockout Tracker**: Updated `createCastTracker()` to fall back to `tracker.activeSpell or tracker.lastSpell` when `mq.TLO.Me.Casting.Name()` is cleared following a fizzle/interrupt/resist event, and set `tracker.failed = true` so `recordSuccess()` does not immediately reset failure counters upon cast conclusion.
  - **Gated `isCombat()` Hostile & Engaged State**: Updated `isCombat()` to verify `isHostileTarget(t.ID())` and `targetIsEngaged(t.ID())` before reporting combat state on targeted NPCs, preventing peaceful vendors, bankers, and quest NPCs from triggering combat status badges and bard combat twisting.
  - **State Table Migration for LuaJIT 200-Local Limit**: Migrated cache locals (`spellbookSetCache`, `lastSpellbookCacheTime`, `hasAACache`, `knownDiscSet`, `filteredSpellsCache`, `gemSyncWarned`, `lastGemSyncCheckAt`, theme counters, and `lastCombatFaceAt`) into `runtime` and `pursuit` state tables, safely reducing the main-chunk local count from 201 to 191 in strict compliance with Lua 5.1 / LuaJIT limits.

- **Fixed Faction Consideration Filtering in `triune.lua`.**
  - **Synchronous `/consider` Polling & Pre-Pull Validation**: Added synchronous event pumping to `verifyTargetCon()` upon initial target acquisition in Puller (Camp) and Puller (Hunt) modes so faction consideration responses (`scowls`, `threateningly`, `indifferently`, `amiably`, `kindly`, etc.) are captured immediately before traveling or pulling. If a target's faction tier is unchecked in the UI filter, it is instantly rejected and cleared (`/target clear`), and subsequent spawn scans bypass the mob name directly via `isConAllowed()`.
  - **Robust Chat Event Line Extraction**: Added `runtime.extractConName()` to parse the NPC name directly from `/consider` chat text if `Target.CleanName()` is blank.

- **Eliminated All Mid-Combat `/attack off` Calls in `triune.lua`.**
  - **Natural EverQuest Combat Disengagement**: In accordance with EverQuest mechanics, auto-attack turns ON once in melee range (`dist <= desiredRange + 15`) and is **never** turned off by the script during combat. When an NPC dies, EverQuest naturally turns off auto-attack on its own. Removed `/attack off` from all mid-combat handlers, restricting `/attack off` solely to manual script pauses / script shutdown (`not ctrl.running`).
  - **Preserved Combat State Across Target Selection (`setTarget`)**: Updated `setTarget()` to capture pre-switch combat state (`wasCombat = mq.TLO.Me.Combat()`) and immediately re-engage `/attack on` whenever EverQuest disengages combat during target changes.
  - **Locked Out Closer-Mob Retargeting During Active Combat**: Guarded `checkCloserTarget()` and Puller mode aggro-switching with `not mq.TLO.Me.Combat()` and `dist <= 35ft` so the bot cannot swap targets or cycle auto-attack off while actively fighting a mob.
  - **Un-gated Auto-Attack from Spellcasting**: Removed `not isCasting()` restrictions from `/attack on` so auto-attack remains engaged continuously even while casting spells and disciplines.
  - **Fixed Med-Break Mid-Combat Trigger (`fullStop`)**: Added active combat detection (`mq.TLO.Me.Combat()` and target proximity `<= 60ft`) to `MedBreak` so low-health/mana/endurance resting triggers cannot execute `fullStop()` or `/attack off` while actively fighting non-XTarget mobs.
  - **Fixed Puller (Camp) Auto-Attack Suppression (`isPullingToCamp`)**: Fixed a bug where `isPullingToCamp` was evaluated as `runtime.pullState ~= 'FIGHTING'`, causing the engine to aggressively issue `/attack off` whenever `pullState` was in `IDLE` or approaching a target. Changed `isDraggingToCamp` to strictly check `runtime.pullState == 'TO_CAMP'`, allowing auto-attack to engage and stay on without being suppressed.
  - **Fixed `pullerTick()` IDLE-to-FIGHTING State Transition**: In `pullerTick()`, if a valid NPC target is already acquired (`haveNPC`), immediately transition `runtime.pullState` to `'FIGHTING'` rather than waiting for `firstNPCXtarget()`, preventing the puller from getting stuck in `IDLE` state during active combat.
  - **Aggro-Switch Debouncing & Hysteresis (`checkAggroSwitch`)**: Added a 2.0-second debounce timer (`runtime.lastAggroSwitchAt`) and a 15-unit distance hysteresis check to `checkAggroSwitch()` to eliminate rapid target switching and auto-attack drops when multiple mobs are near each other.
  - **Eliminated Rapid On/Off Auto-Attack Oscillation Loop**: Fixed a circular disengagement loop between `moveToward()` navigation and `combatTick()` auto-attack gating where `moveToward()` evaluated `Me.Combat() == false` during spell/ability casts and triggered `/nav`, which immediately turned combat off again. Added `isXTargetId(id) or d <= dist + 15` to `moveToward()`'s proximity bypass so position is maintained without repeatedly toggling `/nav id ...` and `/nav stop` mid-combat.
  - **Bypassed Faction Target-Clearing Mid-Combat**: Prevented `verifyTargetCon()` from executing `/target clear` or disengaging `/attack off` mid-fight when `engage`, `mq.TLO.Me.Combat()`, or `isXTargetId(id)` is active. Fixed `isConAllowed()` and `verifyTargetCon()` logic so unconfigured/un-cached faction tiers default to allowed (`true`) rather than returning `false` and clearing targets.
  - **Restored Continuous Auto-Attack Engagement**: Ensured `/attack on` stays engaged continuously throughout combat in all Puller submodes and immediately re-engages after spell or ability casts complete.
  - **Camp Submode Positioning in FIGHTING State**: Added `moveToward(id, desiredRange())` execution during `FIGHTING` state in Puller (Camp) submode so melee pullers step into melee range (14 units) of mobs at camp rather than standing stationary out of range.

- **Fixed Mid-Fight Auto-Attack Disengagement Across Abilities & Assist in `triune.lua`.**
  - **Restored Auto-Attack Across Ability & Spell Executions**: Updated `fireAA()`, `fireDisc()`, `fireSkill()`, and `castGem()` to track pre-cast combat state (`wasAttacking`) and immediately re-engage `/attack on` if EverQuest or MacroQuest disengaged combat during ability target switches.
  - **Removed Erroneous `/attack off` in `maTargetId()`**: Removed a periodic `mq.cmd('/attack off')` call inside `maTargetId()` that was disengaging combat every 1.0 second during target assist checks.
  - **Bypassed Non-XTarget Timeout in Melee Range**: Added a `distToId(tid) > 30` distance check to the non-XTarget engagement timeout, preventing the engine from clearing targets or disengaging `/attack off` mid-combat.

- **Updated Project Version to `1.6`.**
  - Updated `VERSION` constant in `mq2triune/lua/triune.lua` to `'1.6'`.
  - Updated version string in `README.md` to `1.6`.

- **Fixed Faction Consideration Target Filtering in `triune.lua`.**
  - **Replaced Invalid TLO Access & Fixed Initial Spawn Candidate Scan**: Replaced invalid calls to `s.Consideration()` and `s.Standing()` with exact `runtime.conCache` lookup. Fixed untargeted spawn scanning in `isConAllowed(s)` so `s.Aggressive() == false` does not falsely block candidate zone mobs when "Hostile Only" is selected, restoring Puller (Hunt) target acquisition.
  - **Bulletproof `/consider` Chat Event Listeners**: Registered `mq.event` handlers with wildcard patterns (`#*#scowls#*#`, `#*#threateningly#*#`, `#*#dubiously#*#`, `#*#apprehensively#*#`, `#*#indifferently#*#`, `#*#amiably#*#`, `#*#kindly#*#`, `#*#warmly#*#`, `#*#an ally#*#`) and `mq.TLO.Target.CleanName()` caching, bypassing timestamp/chat formatting inconsistencies.
  - **Target Acquisition `/consider` Trigger & Cache Enforcer**: Automatically issues `mq.cmd('/consider')` upon selecting a new roam candidate in `findRoamTarget()`. Verifies `runtime.conCache[cleanName]` prior to starting movement, clearing target (`/target clear`) instantly if its faction is disabled, and caching the mob's clean name so `findRoamTarget()` skips all future mobs of that type in 0ms. Bypasses all faction checks for active XTarget mobs.
  - **Lexical Scoping & Forward Declaration Fix**: Added top-level `local isXTargetId` forward declaration near module initialization so helper functions defined above line 4000 can invoke `isXTargetId` without throwing `attempt to call global 'isXTargetId' (a nil value)` runtime errors.
  - **Config Sanitization & Auto-Save**: Added `pull_con_filter` table sanitization in `sanitizeModeConfig()` and serialized `pull_con_filter` keys in `loadoutSig()` for loadout auto-save change detection.

- **Added Waypoint Patrol System to Puller Mode in `triune.lua`.**
  - **Sequential 3D Waypoint Patrol Loop**: Implemented `runtime.wpTick()` to navigate Puller through user-defined 3D waypoints (`ctrl.waypoints`) in a continuous loop while scanning for valid targets.
  - **Target Scan Interruption & Seamless Resume**: Continuously scans for valid targetable NPCs via `findRoamTarget()` during waypoint traversal; upon acquiring a target, waypoint navigation pauses immediately and resumes seamlessly once combat ends and XTarget clears.
  - **ImGui Puller Waypoint Controls & Lua 5.1 Syntax Fix**: Added a dedicated **Puller Waypoint Patrol** section in the main ImGui UI with Enable Waypoint Patrol checkbox, Arrival Radius slider, active waypoint table (`#`, `Name`, `Coordinates`, `Distance`, `Active NEXT indicator`), and interactive control buttons (`Add Current Location`, `Clear All`, `Set Active`, `Move Up`, `Move Down`, `Delete`). Used `bit.bor()` for `ImGuiTableFlags` in compliance with Lua 5.1 / LuaJIT compatibility rules.
  - **Slash Command Integration**: Added `/ac wp [add [name]|clear|delete [idx]|on|off|toggle|list]` slash commands to manage and query patrol routes directly from EQ chat.
  - **Loadout Persistence & Main-Chunk Safety**: Serialized `waypoints` array in `loadoutSig()` for automatic loadout save/load persistence across character sessions, while scoping all waypoint engine methods on the `runtime` state table to respect LuaJIT's 200 main-chunk local variable limit.

> **TLDR:** Added Waypoint Patrol loop system to Puller mode with ImGui table controls, target scan interruption, `/ac wp` slash commands, and persistent loadout saving.

---

## 2026-08-12

- **Enforced complete character and pet disengagement when paused in Manual mode and across all modes in `triune.lua`.**
  - **Spell Casting Cancellation**: Added `/stopcast` to `fullStop()` alongside `/stopsong` so non-bard spellcasting is immediately interrupted when pausing.
  - **Pet Attack Recall & Hold**: Updated `setManualHunterPetHold()` to issue `#petcmd hold all`, `#petcmd ghold on`, and `/pet back off` when hold is requested, ordering active pets to immediately disengage combat and return to player hold when paused.
  - **Combat Loop Pause Guard**: Added an explicit `if not ctrl.running then return end` guard at the top of `combatTick()` to prevent combat logic execution while paused.
  - **Chat Event Movement Guard**: Added a pause check to `repositionCloser()` so out-of-range chat events do not initiate `/nav` or `/stick` movement when paused.
  - **Continuous Paused Enforcement**: Added a main loop check while `ctrl.running` is false to immediately disengage `/attack`, `/autofire`, `/nav`, and `/stick` if active while paused.

- **Updated slash commands, mode aliases, chat output, and UI Help tab across `triune.lua` and `README.md`.**
  - **Buffbot Slash Command Integration**: Added `/ac buffbot`, `/ac buff`, and `/ac buffui` commands to `triuneCommand()` to launch or stop `triune_buffbot.lua` dynamically.
  - **Chat Help Command**: Added `/ac help`, `/ac h`, and `/ac ?` command handlers to print a formatted summary of all available `/ac` slash commands directly into EverQuest chat.
  - **Expanded Mode Command Aliases**: Updated `setTriuneMode()` so `/ac ranged` maps to `Assist (Backline)` alongside `/ac backline`, `/ac tank` and `/ac garrison` map to `Assist (Camp)`, and `/ac hunter` maps to `Puller (Hunt)`.
  - **Enhanced UI Help Tab**: Updated `UI.drawHelpTab()` in `triune.lua` with all missing standalone window commands (`/ac track`, `/ac buffbot`, `/ac help`), updated usage descriptions, and added command alias references to the Combat Modes table.
  - **Added Faction Consideration Target Filtering to Puller Mode in `triune.lua`.**
  - **Multi-Select Consideration Filtering**: Added `ctrl.pull_con_filter` supporting multi-selection across all 9 EverQuest consideration tiers (`Scowling`, `Threateningly`, `Dubious`, `Apprehensive`, `Indifferent`, `Amiably`, `Kindly`, `Warmly`, `Ally`), with all 9 considerations enabled by default.
  - **Puller Target Selection Guard**: Added `isConAllowed(spawn)` helper to query spawn consideration standing via `Consideration()`, `Standing()`, or `Aggressive()` fallback in `findRoamTarget()` for XTarget and NearestSpawn candidate selection.
  - **ImGui Puller UI Controls**: Added **Target Faction Considerations** multi-select grid layout and quick preset buttons (`Select All`, `Hostile Only`, `Hostile + Indifferent`, `Clear All`) under Puller Target Filters in `renderPullerTab()`.
  - **Slash Command & Persistence**: Added `/ac pullcon [tier] [on|off]` and `/ac pullcon preset [all|hostile|indifferent|none]` slash commands and updated loadout serialization (`collectEntry` / `applyEntry`).

> **TLDR:** Added multi-select Faction Consideration target filtering to Puller mode, with all 9 consideration tiers enabled by default, ImGui presets/checkboxes, and slash command integration.

---

## 2026-08-11

- **Fixed code safety issues and combat mode logic in `triune.lua`.**
  - **Puller (Camp) Add Handling**: Enhanced `pullerTick()` so when a target dies or when in `IDLE` state at camp with active adds/XTargets present, the puller immediately switches to the next live XTarget NPC and remains in `FIGHTING` state, eliminating auto-attack toggling off/on hiccups and state resets when handling multiple mobs at camp.
  - **Camp Mode Roam Filtering**: Updated `findRoamTarget()` in `Puller (Camp)` mode to validate candidate mobs against `ctrl.camp_loc` and `ctrl.camp_radius` to guarantee mobs outside the camp radius are never pulled.
  - **ImGui Child Window Safety**: Replaced `ImVec2(0, 0)` in `ImGui.BeginChild` calls across `drawGemList`, `drawAATab`, and `drawDiscTab` with explicit numeric dimensions (`0, 0`) for consistency and safety across MacroQuest ImGui builds.
  - **Mini GUI Style Color Safety**: Wrapped `PushStyleColor` / `PopStyleColor` calls in the Mini GUI Burn button handler with `pcall` guards to prevent crashes if `ImGuiCol` enums fail to resolve on certain MQ builds.
  - **Puller (Hunt) Navigation Engagement Fix**: Fixed a critical logic flaw in `Puller (Hunt)` mode where `isXTargetId(id)` was setting `engage = true` without calling `moveToward(id, reqRange)`. This caused characters to freeze in place after killing the first mob whenever a second mob/add was on XTarget beyond melee range. `moveToward()` now runs continuously to navigate to targets, allowing characters to close distance and attack subsequent XTarget mobs seamlessly.
  - **Cleaned Up Function Declarations & Dead Variables**: Moved `idxOf()` definition above `toCanonicalClassAbbr()` so it is defined before invocation, removed unused local variables `lastStuckRecoveryAt` and `lastCombatStallRecoveryAt`, added explicit parentheses to the `has Poison/Disease` condition for precedence clarity, and updated pet dispatch logic to query `mq.TLO.Target.ID()` directly for target verification.

- **Redesigned combat mode architecture into Primary Modes and Submodes in `triune.lua`.**
  - Streamlined the 11 legacy combat modes (`Manual`, `Hunter`, `Manual Hunter`, `Puller`, `Pull & Assist`, `Assist`, `Chase Assist`, `Backline`, `Tank`, `Garrison`, `Pet Tank`) into 3 clean Primary Modes: **Manual**, **Puller**, and **Assist**.
  - **Manual**: Acts as the primary manual target engagement mode (former Manual Hunter), auto-attacking and casting loadout spells/AAs/discs on acquired targets. Added a **Camp Location** setting and radius slider so characters automatically return to camp position when idle after combat, protecting AFK players if a mob flees. Added an **Auto-Target Hostiles on XTarget** setting to toggle between auto-engaging incoming XTarget mobs or exclusively fighting manually targeted NPCs.
  - **Puller**: Features dynamic submodes **`Hunt`** (continuous roaming solo hunt — former Hunter) and **`Camp`** (tags mob within radius and pulls back to camp — former Puller).
  - **Assist**: Features dynamic submodes **`Chase`** (follows MA everywhere), **`Camp`** (holds camp position while assisting MA), and **`Backline`** (ranged/caster support staying in position).
  - Added `sanitizeModeConfig()` migration helper in `triune.lua` to automatically map legacy loadout configs to the new Primary Mode and Submode structure.
  - Fixed a lexical scope error in `sanitizeModeConfig()` by forward-declaring `ctrl` and passing the target configuration table parameter.
  - Enforced pet hold (`#petcmd hold all`) during **`Puller (Camp)`** mode while scouting or pulling mobs back to camp, delaying pet attack commands (`#petcmd attack all`) until mobs are brought back within camp range.
- **Removed standalone Mob Ignore tab and added Puller Target Filters in `triune.lua`.**
  - Removed the standalone `Mob Ignore` tab from the top navigation bar.
  - Added a 2-column **Puller Target Filters** section directly under the `Puller` mode controls in the Control tab.
  - **NPCs to Pull (Include List)**: Allows specifying exact NPC names to target. When populated, Puller will *only* pull mobs matching an entry in the list; when empty, all mobs within radius are pulled as usual.
  - **NPCs to Ignore (Ignore List)**: Integrated the global mob ignore list directly into the Puller filter view with quick "Ignore Current Target" and manual entry/removal controls.
  - Moved `ignoreList`, `pullList`, `ignoreInput`, and `pullInput` into `runtime` state table to preserve Lua 200 main-chunk local variable limits.
  - Resolved an ImGui C++ access violation crash caused by nested `ImGui.BeginTable` / `ImGui.BeginChild` layouts by converting Puller filter lists into clean sequential child frames.
  - Added `pcall` guards around spawn distance calculations and `tostring` type hardening in `isPullAllowed()` to ensure non-string or stale TLO objects never throw unhandled exceptions.
  - Updated `updateMapRadiusVisuals()` to map search, camp, and anchor radius circles on the in-game map correctly for **Manual**, **Puller (Hunt / Camp)**, and **Assist (Camp)** primary modes and submodes.
  - Updated `findRoamTarget()` to evaluate candidate spawns against `isPullAllowed(name)` (checking both ignore list and include list).

- **Added customizable Pull Method selector for Puller mode in `triune.lua`.**
  - Added `ctrl.pull_style` configuration field with options: **Melee**, **Spell**, **Pet**, and **Ranged**.
  - **Melee**: Closes range to target NPC and turns on `/attack on` to tag mob.
  - **Spell**: Added a dynamic **Pull Spell** ImGui combo dropdown populated from currently memorized spell gems (`Gem X: <SpellName>`), allowing players to select the exact spell gem to cast when pulling.
  - **Pet**: Closes to range (100 units) and issues native `/pet attack` and `/say #petcmd attack all` to send pet out to tag mob. Fixed an issue where general camp pet hold logic was overriding the pet attack command mid-frame during `TO_MOB` state.
  - **Ranged**: Closes to ranged distance and fires bow via `/autofire on` until mob is tagged.
  - Added full Pull Method engagement support (**Melee**, **Spell**, **Pet**, **Ranged**) to **`Puller (Hunt)`** submode in `combatTick()`, allowing roaming hunters to initiate combat using their chosen pull style.
  - Added **Engagement Distance** slider (`ctrl.pull_engage_dist`, 15–250 units) for non-melee pull methods to control how close the character approaches before casting a pull spell, sending pets, or firing ranged attacks.
  - Added **Stand Back (Let Pet Tank / Stay Ranged)** checkbox (`ctrl.pull_stand_back`), allowing characters to hold position at engagement distance during combat and let pets tank without running into melee range or turning on auto-attack.
  - Added `isTargetInRange(name, targetId)` distance checker and required `engage` to be true when an NPC target is selected before setting `combatReady`. Prevents AAs, Discs, and loadout spells from prematurely firing at distant targets while approaching.
  - Fixed target acquisition in **`Puller (Hunt)`** submode so character automatically clears dead target handles and switches to the next living NPC on XTarget (and updated `checkAggroSwitch()` mode matching for 150-unit XTarget aggro switches).
  - Added customizable **Max XTarget Chase Range** slider (`ctrl.xtar_nav_dist`, 25–300 units, default 150) located directly below `Check for Closer NPCs while Traveling` in `Puller` mode (and under `Auto-Target Hostiles` in `Manual` mode) to control maximum navigation distance for XTarget hostiles in `findFirstNPCXtarget()`, `moveToward()`, and `checkAggroSwitch()`.
  - Moved Pull Method combo selector and Pull Spell dropdown to the top of `Puller` mode controls directly above Search Radius and Pull Radius sliders for improved UI accessibility.

- **Enhanced Configuration Persistence & Dynamic Change Detection in `triune.lua`.**
  - Rewrote `loadoutSig()` to dynamically hash all keys in `ctrl` along with `runtime.ignoreList` and `runtime.pullList`. Ensures all new and future configuration settings (e.g. Pull Method, Pull Spell, Engagement Distance, Stand Back, Manual Auto-Target XTarget, NPCs to Pull, NPCs to Ignore) automatically trigger auto-saving ~1.5s after modification.
  - Fixed `sanitizeModeConfig()` legacy migration logic so valid primary modes (`Puller`, `Assist`) preserve their saved `submode` (`Hunt`, `Camp`, `Chase`, `Backline`) instead of resetting `Puller` back to `Camp`.
  - Added explicit `saveLoadout(true)` execution upon main loop script exit to guarantee configuration changes are persisted when closing windows or stopping script execution.

- **Fixed Spell Gem auto-memorization and gem synchronization in `triune.lua`.**
  - Added `isGemMatching(slotOrName, targetSpellName)` helper to compare spell names against gem bar spells by exact string, cleaned name, normalized name (stripping `Rk. II` / `Rk. III` suffixes), and MacroQuest TLO `Spell(name).RankName()`.
  - Refactored `tryMem(slot, name)` to unmemorize occupied gem slots (`/unmemspell slot`) and duplicate spell instances in other gem slots before issuing `/memspell`.
  - Added combat and movement checks (`mq.TLO.Me.Combat()`, `mq.TLO.Me.Moving()`) and scribed spell verification (`isScribed(name)`) before attempting memorization.
  - Increased spell memorization poll timeout from 2.0s to 6.5s to accommodate full EQ spell memorization casting bar durations.
  - Guarded `runtime.pendingMem` queue processing in the main loop to only drain when stationary, out of combat, and not casting (`not mq.TLO.Me.Casting.ID() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving()`), preventing queued requests from being discarded while moving or fighting.
  - Updated `checkGemMemSync()` and `castGem()` to use `isGemMatching`, eliminating false gem mismatch warnings and false casting failures for rank-based spells.

- **Fixed auto casting on non-hostile targets, player pets, and friendly NPCs in `triune.lua`.**
  - **Bumped version to v1.5.2.** Updated `README.md` to reflect `v1.5.2`.
  - Fixed a critical regression in `Manual Hunter` and engine-targeting modes where targeted pets or non-hostile targets caused endless auto-casting of detrimental (offensive) spells, AAs, and disciplines until mana was depleted.
  - Enhanced `isSpawnPetOrPlayer(id)` to check spawn `Type` (`'PC'`, `'Pet'`, `'Mercenary'`), owner/master relationships (`s.Master` / `s.Owner` where master/owner is a PC or local character), `Me.Pet.ID()`, and `petState.myPets`, ensuring friendly pets, player pets, and allies are 100% recognized.
  - Hardened `isHostileTarget(id)` to reject player/group pets, PCs, corpses, merchants (`'MER'`), bankers (`'BNK'`), guildmasters (`'GMD'`), traders, and buyers.
  - Updated `haveNPC` in `combatTick` to exclude `isSpawnPetOrPlayer(id)`, preventing pets or player targets from being treated as combat targets in `Manual Hunter`, `Hunter`, `Pet Tank`, or `Garrison` modes.
  - Replaced flawed `ENGINE_TARGETS_MODE` target overrides in AA, Disc, and Spell Gem loops (`tryGems`, `tryAAs`, `tryDiscs`) with strict `not isDet or isHostileTarget(id)` checks, guaranteeing detrimental actions are never cast on pets or non-hostile targets while allowing beneficial spells (heals, buffs) to function properly on allies and pets.
- **Gated Med Break resting on XTarget status in `triune.lua`.**
  - Added an `anyXtarAlive()` check before entering Med Break (`runtime.medBreakActive` activation), ensuring characters will not sit down to meditate if any live hostile NPCs are present on the Extended Target list.
  - Added an active XTarget check while resting: if a hostile NPC enters XTarget while Med Break is active, the script immediately cancels Med Break (`runtime.medBreakActive = false`), issues `/stand`, and resumes combat readiness.

- **Resolved mode refactoring bugs and restored missing `normalizeCommandKey` helper in `triune.lua`.**
  - Re-defined `normalizeCommandKey(text)` before `setTriuneMode()`, fixing a runtime error (`attempt to call global 'normalizeCommandKey' (a nil value)`) when running slash commands (`/ac`).
  - Fixed PAUSE button in `drawControlTab()` and pet hold logic in `fullStop()` to check for primary mode `'Manual'`.
  - Updated legacy mode string checks (`Manual Hunter`, `Hunter`, `Pull & Assist`, `Chase Assist`, `Backline`, `Pet Tank`, `Garrison`) in `ENGINE_TARGETS_MODE`, `checkCombatStall()`, `findRoamTarget()`, `checkCloserTarget()`, `checkAggroSwitch()`, debug diagnostics, and auto-attack gates to use updated Primary Modes (`Manual`, `Puller`, `Assist`) and Submodes (`Hunt`, `Camp`, `Chase`, `Backline`).

- **Removed Buff Loadout tab and related code (`mq2triune/lua/triune.lua`, `README.md`).**
  - Removed secondary `Buff Loadout` tab, `loadout.buffGems` table, and `ctrl.buff_mode` state toggle from `triune.lua`.
  - Simplified `Spell Gems` tab header UI (`UI.drawGemTabHeader`), auto-mem, and import controls for the single active spell gem loadout.
  - Streamlined `checkGemMemSync()`, `tryGems()`, `collectEntry()`, `applyEntry()`, `loadoutSig()`, and character initialization routines to operate directly on `loadout.gems`.
  - Updated `README.md` documentation to reflect the single 12-slot spell gem loadout.

- **Removed obsolete `'on Named / burn'` condition option (`mq2triune/lua/triune.lua`, `README.md`).**
  - Removed `'on Named / burn'` from the `WHENS` trigger condition dropdown array in `triune.lua`, cleaning up the condition selection for Spell Gems, Abilities & AAs, and Disciplines.
  - Updated `README.md` documentation to remove references to `'on Named / burn'`.

---

## 2026-08-10

- **Bumped project version to v1.5.**
  - Updated `README.md` documentation, feature list (Compact Mini HUD, AA & Plat Session Rate Tracker, Zone NPC Tracker), commands table, and directory file structure tree.
- **Fixed Release Updater button responses and execution pipeline (`mq2triune/lua/triune_updater.lua`, `mq2triune/triune_updater.py`, `update.sh`, `update.bat`).**
  - Resolved scope variable shadowing bug on `pendingAction` in `triune_updater.lua` where `local pendingAction = 'check'` declared in the script body created a shadowed local variable, causing ImGui button clicks (`Check for Updates` and `Update Now`) to be ignored by the main execution coroutine.
  - Added Candidate 0 direct `curl CLI` individual file downloader to `executeUpdate()` in `triune_updater.lua`, enabling zero-dependency release file updates on Linux, macOS, and Windows.
  - Created standalone Python 3 updater script `mq2triune/triune_updater.py` using standard library (`urllib.request`, `json`, `zipfile`, `shutil`, `argparse`) for release checking and archive extraction.
  - Added existence checks (`[ -f "${SCRIPT_DIR}/triune_updater.py" ]` and `if exist "%~dp0triune_updater.py"`) to `update.sh` and `update.bat` so fallback execution paths (`curl`/`unzip` or PowerShell) run smoothly when Python scripts are omitted.
- **Fixed combat initiation & auto-attack cancellation on fresh targets in `triune.lua`.**
  - Fixed a critical issue where `/attack on` and `/autofire on` were being immediately cancelled by `not xtarActive` checks when navigating to a fresh target that had not yet entered XTarget.
  - Updated detrimental action gates for Spells, AAs, and Discs to allow all engine auto-targeting modes (`Hunter`, `Manual Hunter`, `Pet Tank`, `Puller`, `Pull & Assist`, `Garrison`) to cast offensive spells/abilities to initiate combat on fresh non-XTarget targets.
  - Added `Manual Hunter` to `ENGINE_TARGETS_MODE` so `combatReady` remains `true` when engaging fresh targets.
  - Expanded auto-attack & auto-fire distance tolerances upon arrival (`MELEE_RANGE + 4` and `ranged_dist + 5`) to prevent navigation stall freezes where `/nav` arrived at target boundary but auto-attack failed to activate.
- **Updated XTarget handling & added Non-XTarget attack timeout in `triune.lua`.**
  - Removed level restrictions from `findFirstNPCXtarget()`, `firstNPCXtarget()`, and `checkAggroSwitch()`: any hostile mob that enters the player's Extended Target list (XTarget) is now targeted and attacked immediately, regardless of level.
  - Initial target selection in `findRoamTarget()` and non-XTarget `haveNPC` validation still enforce `hunter_min_level`/`hunter_max_level` and `pull_min_level`/`pull_max_level`.
  - Added a 4.0-second non-XTarget engagement timeout: when attempting to attack an NPC that fails to join `Me.XTarget` after 4 seconds of active engagement (e.g. un-aggroable, non-hostile, or bugged NPC), the script marks the mob as unreachable, clears target, and moves on to the next mob.
- **Added standalone Zone NPC Tracker window (`mq2triune/lua/triune_track.lua`).**
  - Displays all active NPCs in the current zone with real-time distance updates (in yards), level, consideration color badge, line of sight indicator, and spawn ID.
  - Formatted table layout with Clean Name as Column 1 (`Name`), followed by Level (`Lvl`), Distance (`Dist`), Consideration (`Con`), Spawn ID (`ID`), Line of Sight (`LoS`), and Action buttons (`Actions`).
  - Added consideration color filtering (`All`, `Red / Dark Red`, `Yellow`, `White`, `Blue`, `Light Blue`, `Green`, `Grey`).
  - Added live search text filter matching NPC clean names and spawn IDs.
  - Added sorting options (`Nearest First`, `Farthest First`, `Level High -> Low`, `Level Low -> High`, `Name A - Z`) and interactive column header sorting.
  - Double-clicking any cell on an NPC row (or clicking `[Nav]`) acquires target (`/target id <ID>`) and issues nav command (`/nav id <ID>` with `/stick 10` fallback).
- **Added AA/hr and Plat/hr session tracking in `triune.lua` header bar.**
  - Displayed real-time AA per hour (`AA/hr: 12.4`) and Platinum per hour (`Plat/hr: 120.5`) with an inline `Reset` button on the header script info line.
  - Hovering over the tracker text reveals a detailed tooltip showing elapsed session time, AA/hr rate, total AA gained, Plat/hr rate, and total session Platinum gained (with start & current balances).
- **Added Compact Window Mode (Mini HUD) for `triune.lua`.**
  - Added `ctrl.compact` state variable persisted per-character in `triune_loadout.lua`.
  - Created `drawMiniGui()` auto-resizing HUD overlay window titled `Triune AutoCombat Mini v1.4.3###triuneMini`.
  - Compact Mini HUD includes live combat mode selector combo dropdown, Pause/Run toggle button, Burn toggle button (highlighted bright red when active), AA/plat session rate tracking banner with hover tooltip and reset button, sub-module launcher buttons (`Spellbook`, `Cursor`, `DPS`, `Update`, `Tracker`), and `[Full Window]` expand button.
  - Added `Compact Mode` header button in full tabbed window and `Compact Mini-Window HUD Mode` checkbox in Settings tab.
  - Added `/ac compact` (`/ac mini`, `/ac hud`) slash command toggle.
- **Fixed Hunter Combat Radius persistence & compact HUD toolbar in `triune.lua`.**
  - Removed `Set Camp` button from the compact mini HUD action controls toolbar.
  - Removed initial loadout reset (`ctrl.hunter_combat_radius = 0`) in `applyEntry()` that was wiping saved Hunter combat radius settings.
  - Added `ctrl.hunter_combat_radius` to `loadoutSig()` serialization, ensuring user-configured combat radius settings persist across sessions and anchor re-locations.
- **Fixed game crash when clicking `[Updater]` button (`mq2triune/lua/triune_updater.lua`).**
  - Deferred initial release update check (`checkForUpdates()`) from chunk-load level to the main yieldable coroutine thread (`pendingAction = 'check'`), preventing blocking process execution inside ImGui frame render callbacks.
  - Re-ordered HTTP query candidates in `checkForUpdates()` to prioritize native `curl CLI` (`io.popen`) over legacy `VBScript MSXML2` (`cscript.exe`), avoiding Windows Script Host popups and process thread hangs.
  - Refactored `execCommand()` to execute commands via `io.popen` streams first without popping up console windows or blocking MacroQuest's Direct3D rendering loop.
  - Added clean `mq.imgui.destroy('TriuneUpdaterWin')` unregistration when the window exits to eliminate dangling C++ render callback access violations.
  - Excluded `triune_updater` from self-termination during active script restart loops in `executeUpdate()`.

---

## 2026-08-09

- **Bumped version to v1.4.2.**
- **Fixed character class detection and manual class selection dropdowns in `triune.lua` and `triune_spellbook.lua`.**
  - Removed `classesFromTitle` completely from both scripts so title bar text (e.g. MacroQuest window title containing "Bard") is never used for class detection.
  - Enforced Inventory Window as the sole source of live auto-detection: checks `IW_ClassAbbr` (`Text="SHD\nMAG\nBST"`), `IW_Class` (`Text="DreadLord\nArchConvoker\nFeralLord"`), `IW_ClassList`, and full `FirstChild`/`Next` tree traversal, falling back only to `Me.Class.ShortName()` for single-class characters.
  - Refactored `UI.drawClassPicker()` in `triune.lua` with a `CLASS_PICKER_OPTIONS` array containing `'-- None --'` and all 16 class abbreviations. Allows full manual dropdown selection for any slot at any time, saving choices immediately to `triune_loadout.lua`.
  - Removed the `classPlausible` discard loop from `onCharacterChanged()` that was wiping saved non-primary/melee class slots.
- Fixed spell gem dropdown spell filtering and "Scribed Only" checkbox toggle reactivity in `triune.lua`.
  - Removed the `isMyClass` gate from `filteredSpells()` that was preventing the Scribed Only filter from ever applying. The old logic only checked `isScribed()` when the dropdown's class matched `Me.Class.ShortName()`, but the class comparison was always failing (different string formats between MQ TLO return and Triune abbreviations), making the checkbox a complete no-op. Now `isScribed()` is called directly when `scribed_only` is on, for every class — `Me.Book()` naturally returns false for classes the character hasn't scribed.
  - Added `toCanonicalClassAbbr(str)` helper and expanded `MQSHORT` table to map 3-letter MQ ShortName codes (`SHD`, `CLR`, `MAG`, `ENC`, etc.) to Triune class abbreviations.
  - Converted MQ TLO return objects via `tostring()` across `toCanonicalClassAbbr`, `getScribedSpellSet`, and `isScribed`, preventing Lua `userdata` type check rejections.
  - Isolated individual spellbook slot queries in `getScribedSpellSet()` with per-slot `pcall` blocks and checked `spellObj.ID() > 0`, ensuring unscribed/empty slots do not break spellbook indexing.
  - Refactored `filteredSpellsCache` to store `lvlMin`, `lvlMax`, `scribedOnly`, and timestamp per class abbreviation, eliminating global filter state collisions across gem rows.
- Added cross-platform GitHub Release updater (`triune_updater.py`, `update.bat`, `update.sh`, and `triune_updater.lua`).
  - Implemented `triune_updater.py` using Python 3 standard library (`urllib.request`, `zipfile`, `shutil`) for zero-dependency updates on both Windows and Linux.
  - Added `update.bat` and `update.sh` OS shell wrappers with PowerShell (`Invoke-RestMethod` / `Expand-Archive`) and Linux `curl`/`unzip` fallback paths when Python is absent.
  - Created standalone ImGui release updater window (`mq2triune/lua/triune_updater.lua`) with version comparison, GitHub release notes display, and in-game update execution with automatic Lua script reloading.
  - Integrated `[Updater]` header button and `/ac update` (`/ac checkupdate`) slash command in `triune.lua`.
  - Enforced user configuration preservation (`triune_loadout.lua`, `MacroQuest.ini`, character INIs are explicitly protected from overwrite).
  - Added multi-stage fallback (VBScript `MSXML2.ServerXMLHTTP` -> Python CLI -> direct `curl`/`curl.exe` -> PowerShell TLS 1.2) in `triune_updater.lua` for zero-dependency HTTP downloads under native Windows, Linux, and Wine/Lutris environments.
  - Implemented raw GitHub content individual text file downloads with HTTP 404 fallback for legacy release tag paths, ensuring seamless updates under Wine without binary `ADODB.Stream` limitations.
  - Refactored release updater to use dynamic runtime script directory resolution (`debug.getinfo`), eliminating all hardcoded paths and allowing updates to function regardless of custom installation location or folder renaming.
  - Enforced an active script detection loop (`mq.TLO.Lua.Script`) in `triune_updater.lua` that automatically stops and restarts all currently running Triune Lua scripts (`triune`, `triune_spellbook`, `triune_cursor`, `triune_buffbot`, `triune_dps`) after an update, ensuring every active module reloads fresh from disk.
- Enhanced stuck recovery logic in `triune.lua` with a multi-step directional attempt sequence (`stuckState.attempts`).
  - Attempt 1: Backs up for 1200ms and jumps to clear immediate frontal collisions.
  - Attempt 2: If still stuck on the obstacle, backs up briefly and strafes left for 1000ms to maneuver around the left side.
  - Attempt 3: If still stuck, backs up briefly and strafes right for 1800ms to step past the initial point to the right side.
  - Attempt 4: If all directional maneuvers fail, marks current target unreachable (`markUnreachable`), clears target (`/target clear`), resets pursuit state, and forces the bot to search for a new target.
  - Resets attempt progression after 20 seconds of clear movement or when `fullStop()` is called.

---

## 2026-08-08

- Updated `README.md` documentation to include MacroQuest (MQ2) setup instructions.
  - Added installation instructions covering unzipping the release package into the `Documents` directory and starting `MacroQuest.exe` prior to launching EverQuest.

- Added GitHub release workflow (`release.yml`) and configured `.gitattributes` release archive exclusions.
  - Configured `git archive` packaging in `.github/workflows/release.yml` to bundle engine modules, executables, plugins, scripts, and configs into `TriuneAutocombat.zip` (~25MB base install).
  - Added script-and-config update package (`TriuneAutocombat-Update.zip`, ~1.6MB) containing `lua/`, `config/triune_data.lua`, `macros/`, `README.md`, and `CHANGELOG.md` for fast updates over existing installs.
  - Split offline pre-built navmesh files into `TriuneAutocombat-NavMeshes-Part1.zip` (~1.2GB) and `TriuneAutocombat-NavMeshes-Part2.zip` (~860MB) to stay strictly below GitHub's 2.0GB per-file release asset upload limit.
  - Updated `.gitattributes` with `export-ignore` directives to strip repository metadata, CI workflows, agent rules, and dev configs (`.git`, `.github`, `.agents`, `.luarc.json`, `.gitattributes`) from release zip archives.

- Fixed character class detection and save validation across `triune.lua` and `triune_spellbook.lua`.
  - Rewrote `classesFromInventoryWindow` to walk the **entire** `InventoryWindow` child tree using MQ's `FirstChild`/`Next` sibling traversal API instead of guessing hardcoded child control names like `IW_ClassList`. This discovers class text in any label, list, or STMLbox child regardless of custom UI XML layout.
  - Added diagnostic console output when `loud=true`: every child node's `Name`, `ScreenID`, `Type`, and `Text` are printed to the MQ chat window so class detection problems can be debugged visually.
  - Updated `onCharacterChanged()` and `runMainLoop()` to execute live `detectClasses(true)` on login and re-detection, immediately replacing stale `brd/war/war` saves in `triune_loadout.lua`.
  - Seeded `myName` from `mq.TLO.Me.CleanName()` at the top of `runMainLoop()` so detection fires on first script launch, not only on character change events.
  - Implemented `parseClassLine(text)` helper using 3-letter (`SHD`, `MAG`, `BST`) and 2-letter (`SK`) prefix matching to parse un-spaced concatenated class/title strings (e.g. `"MAGArchConvoker"`, `"SHD DreadLord"`, `"BST FeralLord"`) and skip header lines (e.g. `"Level: 65"`).
  - Expanded `MQSHORT` dictionary mapping table to include standard 3-letter MacroQuest ShortNames, long class names, and word tokens.
  - Added `normalizeClass(raw)` helper function to convert any class string/token into Triune's canonical mixed-case format (`War`, `Clr`, `SK`, etc.).
  - Synchronized `triune_spellbook.lua` with the same `walkChildTree` / `scanOneNode` approach.

- Gated detrimental spells, AAs, combat abilities, disciplines, and skills behind XTarget verification.
  - Added `isDetrimentalAction(name, targetToken, entry)` helper to authoritatively classify offensive/detrimental actions vs beneficial spells/heals/buffs.
  - Added `isSpawnPetOrPlayer(id)` helper to ensure self, player pets, group pets, player characters, and master-owned spawns are never misclassified as hostile targets.
  - Updated `isXTargetId(id)` to check both `'NPC'` and `'Pet'` spawn types on XTarget slots.
  - Updated `isHostileTarget(id)` to exclude pets and players from hostile target classification.
  - Updated `Manual Hunter` mode targeting logic in `combatTick()`: if the current target is a pet, player, or non-XTarget spawn, the engine auto-switches to an available XTarget NPC or sets `haveNPC = false`, preventing pets from being attacked or targeted while gathering mobs.
  - Gated AA, disc, skill, and spell gem execution so detrimental actions require the target `id` to be on the XTarget list (exempting `Puller` mode during `TO_MOB` state), while allowing beneficial spells (heals, buffs, pet summons) to fire freely in or out of combat.
- Shifted cursor item clearing from continuous main loop polling to Just-In-Time (JIT) targeted execution.
  - Removed unconditional `clearCursor()` call from `runMainLoop()`, allowing players to hold, inspect, organize, or trade items on the cursor without the script auto-inventorying them every loop pass.
  - Optimized `clearCursor()` with an instant early-exit check when the cursor is empty.
  - Added targeted `clearCursor()` calls immediately prior to executing `/cast` in `castGem()`, `/alt act` in `fireAA()`, `/disc` in `fireDisc()`, and `/doability` in `fireSkill()`.
  - Added `clearCursor()` at the completion of `tryMem()` in `triune.lua` and `triune_spellbook.lua` to clean up any leftover spell icons.
  - Added post-cast `clearCursor()` in `combatTick()` when `wasCasting` transitions to `false` to clear summoned items (Mod Rods, Pet Weapons, Food/Reagents) into inventory upon spell completion.
- Added dynamic closer NPC retargeting during travel for `Hunter`, `Puller`, `Pull & Assist`, and `Pet Tank` modes.
  - Implemented `checkCloserTarget(curTargetId, searchRadius, searchMaxZ, minLevel, maxLevel)` helper to evaluate if a candidate spawn visible during movement is significantly closer (`candDist <= curDist - 25` AND `candDist <= curDist * 0.75`).
  - Enforced a single retarget limit per pursuit run (`pursuit.hasRetargeted`) to prevent target bouncing or ping-ponging between nearby mobs.
  - Maintained strict priority for active XTarget aggro interrupts in `checkAggroSwitch()` and `pullerTick()`, ensuring attacking mobs are engaged immediately.
  - Fixed false-positive stuck detection (`stuck -- backing up and pivoting`) during idle, manual hunter, casting, sitting, and player chase states.
  - Restricted `checkStuck()` evaluation strictly to when movement plugins are active (`isMoveActive() == true`), eliminating false-positive stuck maneuvers while standing still or waiting for targets.
  - Added state guards in `checkStuck()` for spell casting (`me.Casting.ID()`), sitting (`me.Sitting()`), med break (`runtime.medBreakActive`), stunned (`me.Stunned()`), and rooted (`me.Rooted()`) states.
  - Extended target proximity check in `checkStuck()` to handle player targets (e.g. MA player in `Chase Assist` mode with `ctrl.chase_dist`) in addition to NPC targets.
  - Updated script version number to `1.3` in `lua/triune.lua` and `README.md`.
- Added pulsing red visual style to the BURN button when Burn Mode is enabled.
  - Implemented smooth sine-wave RGB color oscillation (`os.clock()`) pulsing between deep red and vibrant glowing red for `ctrl.burn == true`.
  - Applied high-contrast white text and hover highlighting with proper `ImGui.PopStyleColor()` cleanup.
- Fixed `Manual Hunter` mode targeting lock, pet hold deadlocks, XTarget range evaluation, and XTarget slot filtering.
  - Updated `Manual Hunter` mode target dispatch in `combatTick()` to respect player-selected NPC targets (not dead, not ignored, not unreachable) and auto-acquire the top-priority XTarget mob when current target dies or is cleared.
  - Removed restrictive non-XTarget target rejection that was forcibly discarding manual player targets and preventing combat initiation.
  - Integrated `Manual Hunter` into unified `selfDirected` pet command handling, eliminating the pet aggro deadlock where casters and pet classes got stuck waiting for direct melee/spell aggro before sending pets to attack.
  - Strictly enforced Pet Assist HP threshold (`ctrl.pet_assist_at`): pets remain on hold (`#petcmd hold all`) until target NPC HP percentage drops to or below `ctrl.pet_assist_at`, engaging immediately with `#petcmd attack all` once threshold is met.
  - Extended `checkAggroSwitch()` range check to 60 units for `Manual Hunter` mode to properly evaluate XTarget adds within range.
  - Fixed `findFirstNPCXtarget()` filtering by removing `TargetType() == 'Auto Hater'` check to recognize all XTarget slot configurations (`Hater`, `Specific NPC`, `Group Tank Target`, etc.) and passing spawn clean name (string) instead of ID (number) to `isIgnoredFn`.
- Styled the main execution toggle button based on script state (`ctrl.running`).
  - Rendered a vibrant green button (`PAUSE`) when the engine is actively running (`ctrl.running == true`).
  - Rendered a deep crimson red button (`START`) when the engine is paused (`ctrl.running == false`).
  - Removed redundant `STATUS: RUNNING` / `STATUS: PAUSED` text label from the main ImGui Control tab layout.

---

## 2026-08-07

- Fixed ImGui PAUSE button not stopping navigation and combat actions.
  - The UI PAUSE button now calls `fullStop()` (stops `/nav`, `/stick`, `/attack`, `/autofire`, casting, and resets pursuit state), matching the behavior already present in `/ac pause` and `/triunerun`.
  - Also added missing `setManualHunterPetHold()` consistency for Manual Hunter mode.
- Added universal hostile-target safety gate across all combat modes.
  - New `isHostileTarget(id)` helper: confirms an NPC is hostile (on XTarget, player is attacking it, target-of-target points at player, or HP < 100%) before allowing any offensive actions.
  - Auto-attack (`/attack on`, `/autofire on`) and all casting (AAs, discs, spell gems) are now gated behind this check for player-directed modes (Manual, Manual Hunter, Assist, Chase Assist, Backline, Tank).
  - Engine-auto-targeting modes (Hunter, Puller, Pull & Assist, Pet Tank, Garrison) are exempt since their own `findRoamTarget`/`firstNPCXtarget` target selection is the safety gate.
  - Prevents accidentally attacking or casting on friendly NPCs (merchants, quest givers, guards, bankers) in any mode.
- Improved `checkAggroSwitch()` to respond immediately when an NPC is directly hitting the player.
  - Removed the 60-unit distance cap for NPCs with confirmed aggro (`isHittingMe`); the engine now switches to the attacker regardless of range.
  - Added `bestIsHittingMe` condition: always switches to an NPC that is directly hitting the player, even if the current target is on XTarget.
- Added `DPS Parser` header button to `lua/triune.lua` top navigation bar next to `Open Spellbook` and `Cursor Manager`, with `/ac dps` slash command integration to launch or toggle the standalone DPS parser script.
- Added `lua/triune_dps.lua` standalone MacroQuest ImGui Lua script:
  - Real-time combat damage tracking for player melee, direct damage spells, DoTs, damage shields, and pet attacks.
  - Implemented live performance gauges, breakdown tables (Min, Max, Avg, Crit %, Accuracy %), and player/pet percentage contribution split.
  - Added historic encounter logging (retains up to 50 completed fights) with fight inspector and clear options.
  - Added slash command handler (`/dps` and `/triunedps`) supporting `show`, `hide`, `toggle`, `reset`, `pause`, `resume`, and `report <channel>` commands.
  - Implemented auto-fight completion after configurable inactivity timeout (default 6.0s).
  - Added per-character configuration persistence (`triune_dps_<Name>.lua` in MQ config dir).
  - Added combat verb validation lookup (`COMBAT_VERBS`) and non-combat string filtering (`healed`, `taken`, `been`, `mana`) to prevent non-damage messages from misparsing as attacks.
  - Implemented `isPetActor()` helper with dynamic `mq.TLO.Pet` clean name matching to accurately capture pet melee, pet spells, and pet misses.
  - Added automatic mob death and target-switch encounter archiving (`mq.TLO.Target.IsDead()` / target ID change) to push completed fights into Fight History per mob.
  - Rendered a unified Player & Pet attack breakdown table on the Live Overview tab with color-coded source tags (`[Player]` / `[Pet]`).
  - Consolidated melee event registration into a unified `onCombatHit` callback (`#1# #2# #3# for #4# points of damage#5#`), resolving MacroQuest event pattern shadowing where broad pet match wildcards intercepted player hits before player events fired.
  - Updated `UI.drawHelpTab()` in `lua/triune.lua`, adding `/ac dps`, `/dps compact`, `/dps report [chan]`, and `/dps reset` slash commands and descriptions to the main Help tab reference table.
  - Updated project rules in `.agents/AGENTS.md`, documenting mandatory practices for thread-safe script exit outside ImGui callbacks (prevents fatal crashes), omitting `ImGuiWindowFlags.NoCollapse` for proper `WindowRounding` rendering, and using sequential `SameLine()` toolbar positioning.
  - Enabled Window Corner Rounding (`v4.3`), removing `ImGuiWindowFlags.NoCollapse` flag from `ImGui.Begin()` calls so ImGui's `WindowRounding` style token (6.0) applies directly to both the full parser window and mini HUD frame.
  - Unified Design System & Window Rounding (`v4.2`), bringing `pushTheme()` and `popTheme()` into 100% alignment with `triune.lua` design tokens including `WindowRounding` (6), `ChildRounding` (5), `FrameRounding` (4), `ScrollbarRounding` (6), `FrameBorderSize` (1), and exact color palettes across all windows.
  - Resolved Fatal C++ Access Violation Crash on Window Close (`v4.1`), removing inline `mq.exit()` and `mq.imgui.destroy()` calls from inside the non-yieldable ImGui render callback and command handler so window termination occurs safely on the main script thread.
  - Optimized Compact Mini HUD Layout (`v4.0`), increasing vertical padding and spacing, removing redundant header expand button in favor of single bottom `[Full Window]` action button, and converting full window toolbar to sequential `SameLine()` alignment to prevent button overlaps.
  - Refactored Compact Mode into Dual Top-Level Window Architecture (`v3.9`), registering an independent, auto-resizing mini HUD window (`TriuneDPSMiniWindow`) that cleanly replaces the main window when toggled into compact mode.
  - Implemented Compact Mini-Window Mode (`v3.8`), creating a low-profile widget view showing live target, fight duration, combined DPS, and player/pet contribution split with quick `[Expand]` / `[Compact Mode]` toggles and `/dps compact` / `/dps mini` command support.
  - Updated fight history retention capacity to 25 fights max (`v3.7`) to optimize memory footprint during long farming sessions.
  - Implemented First-Person Verb Parsing Engine (`v3.6`), allowing player melee lines that omit "You" (e.g. `punch a cleric of hate for 607`, `kick a cleric...`, `crush a...`) to properly parse as player attacks.
  - Implemented Dedicated Critical Hit & Blast Event Handlers (`v3.6`), adding `#1# scores a critical hit! (#2#)` and `#1# delivers a critical blast! (#2#)#3#` event listeners to record critical hits and spell blasts across player and multi-pet breakdown statistics.
  - Implemented Short Combat Log Pattern Engine (`v3.5`), adding `#1# for #2#` damage pattern and `#1# missed #2#` miss pattern to support custom/emulator server abbreviated melee chat formats (`Tenekis crushes a forlorn revenant for 204`, `Grimrorik kicks a forlorn revenant for 25`).
  - Implemented `calculateCategoryTotals()` dynamic breakdown scanner (`v3.4`), calculating category metrics (Melee, Skills, Spells, DoTs, DS) directly from player and multi-pet attack breakdown tables to guarantee category sync in Fight History and live UI.
  - Resolved event pattern precedence shadowing (`v3.3`), removing the redundant `#1# hit #2# for #3# points of damage#4#` pattern which was intercepting all physical melee hits before `DPS_MeleeHitPlural` could execute.
  - Added fallback pattern matching to `parseMeleeSentence()` to guarantee 100% verb extraction across all space-separated combat lines.
  - Updated `parseMeleeSentence()` to use plaintext space-bounded verb matching (`v3.2`), replacing Lua frontier pattern regexes (`%f[%a]`) with `string.find(" " .. verb .. " ", 1, true)` for 100% reliable execution in MacroQuest LuaJIT.
  - Implemented `parseMeleeSentence()` Lua verb parsing engine (`v3.1`), resolving MacroQuest event pattern greedy wildcard behavior (`#1# #2# #3# for #4#`) that was swallowing actor, verb, and target names into single wildcards.
  - Simplified melee and skill event registration to `#1# for #2# points of damage#3#` and `#1# for #2# point of damage#3#`, guaranteeing 100% accurate capture of player melee, pet melee, and special combat skills (Kick, Bash, Backstab, Flying Kick, Frenzy, etc.).
  - Implemented Damage Category Classification Engine (`v3.0`), categorizing all attacks, spells, and skills into 5 distinct metrics: **Melee**, **Skills / Abilities** (Kick, Bash, Backstab, Flying Kick, Frenzy, Headbutt, Maul, etc.), **Spells (DD)**, **DoTs**, and **Proc / Damage Shield**.
  - Added categorized damage columns to Fight History table (`Melee Dmg`, `Skill Dmg`, `Spell/DoT Dmg`) and category metric badges to the Encounter Inspector header (`Melee: X (X%) | Skills: Y (Y%) | Spells: Z (Z%) | DoTs: A (A%) | DS: B (B%)`).
  - Added color-coded Category badges (`[Melee]`, `[Skill]`, `[Spell]`, `[DoT]`, `[DS/Proc]`) to all breakdown tables across Overview, Player Details, and Pet Details.
  - Enhanced `/dps report` and chat report buttons to include category percentage breakdowns (`Types: Melee X%, Skill Y%, Spell Z%, DoT A%`).
  - Implemented `isValidMobName()` target name filtering (`v2.9`), preventing combat lines like `was hit by non-melee` from incorrectly saving `by non-melee` as the target name in Fight History.
  - Added dedicated event listeners (`DPS_MobNonMeleePlural`, `DPS_MobNonMeleeSingular`) for `#1# was hit by non-melee for #2# points of damage`, accurately capturing mob damage shield and environmental damage under the mob's actual clean name.
  - Added automatic target name fallback to `mq.TLO.Target.CleanName()` whenever an incoming hit event contains an invalid or non-actor target string.
  - Implemented Dual-Mode Encounter Inspector (`v2.8`), rendering an instant **In-Tab Fight Detail View** directly inside the Fight History tab with `< Back to Fight List`, `Report Fight`, and `Pop Out Window` controls, as well as an `ImGui.BeginPopupModal` dialog for 100% mouse input focus.
  - Added **Secondary Window Focus & Inspectors** rule to `.agents/AGENTS.md`, documenting that secondary windows in MQ Lua do not automatically capture mouse focus from the primary window, making In-Tab Detail Views and ImGui Modal Popups the standard pattern for responsive sub-inspectors.
  - Registered `drawInspectorGui()` as an independent top-level MacroQuest ImGui window callback (`mq.imgui.init('TriuneDPSInspectorWindow', drawInspectorGui)`), eliminating nested `ImGui.Begin()` calls inside `drawDpsGui()`.
  - Added **No Nested ImGui.Begin Window Callbacks** rule to `.agents/AGENTS.md`, documenting that calling `ImGui.Begin()` for a secondary window inside a primary window's render callback corrupts ImGui's input focus stack and freezes secondary window controls.
  - Removed `ImGuiSelectableFlags.SpanAllColumns` from `HistoryTable` target selectables, ensuring column 8 buttons (`Inspect`, `Report`) receive mouse clicks cleanly without row overlap.
  - Implemented unique string ID suffixes across `drawDpsGui()` and `drawInspectorGui()` in `lua/triune_dps.lua` (`MainOverviewTable`, `InspectOverviewTable`, `MainMultiPetTabBar`, `InspectMultiPetTabBar`), fixing ImGui mouse routing collision where buttons (`Close Inspector`, `Report`) and titlebar `X` close button froze on pop-out windows.
  - Updated window titlebar `X` close logic in `drawInspectorGui()` to cleanly handle `open == false` from `ImGui.Begin()`.
  - Added interactive Encounter Inspector window (`drawInspectorGui`), allowing users to click any fight row or Inspect button in Fight History to open a dedicated window displaying complete historical fight stats, player breakdown, and multi-pet breakdown tabs.
  - Added per-fight `Report` button in Fight History table and Encounter Inspector, enabling instant reporting of any past encounter to chat (/group, /say, /guild, /raid).
  - Fixed player vs pet actor resolution in `isPlayerActor()` by checking for explicit `(Owner: ...)` strings and enforcing exact character name matching, preventing pet spells (`Hand of Retribution`, `Spirit of Storm Strike`) and swarm pets (`Gennro's Animated Corpse`) from misclassifying under Player DPS.
  - Added `getCleanPetName()` to strip `(Owner: ...)` tags from pet actors, cleanly grouping pet melee and pet spell attacks under their proper pet names (`Glidequill`, `Tenekis`, `Grimrorik`, `Gennro's Animated Corpse`).
  - Added chat-driven mob slain listeners (`DPS_MobSlain1`, `DPS_MobSlain2`) for `"has been slain"` and `"You have slain"` lines, ensuring 100% reliable fight session archiving on mob death.
  - Added Multi-Pet Detailed Breakdown under Pet Details tab, rendering individual tab pages per pet name (`Jobab`, `Water Spirit`, `Charmed NPC`) as well as an `All Pets Combined` overview tab.
  - Implemented automatic target-switch fight archiving in `startFightIfNeeded()`, cleanly completing and saving Mob A's fight session into Fight History when Mob B is engaged.
  - Fixed premature mid-combat encounter resets by removing `targetId ~= currentTargetId` triggers when player targets self or party members to cast spells, preventing accumulative fight damage from resetting to 0 mid-fight.
  - Added `parseDamageValue()` helper to strip commas from damage values (e.g. `1,250` -> `1250`), resolving a bug where all combat damage hits >= 1,000 returned `nil` under `tonumber()` and were silently dropped.
  - Expanded `COMBAT_VERBS` matrix with additional special attack verbs (`headbutt`, `maul`, `pummel`, `rend`, `rip`, `sweep`).
  - Fixed post-encounter DPS calculation in `getCurrentFightDuration()`, preserving actual fight duration from `fightStartTime` to `lastDamageTime` after mob death so calculated DPS does not reset to 0 upon fight completion.
  - Expanded `isPetActor()` to recognize `"Your pet"`, `"your pet"`, swarm pets, and `mq.TLO.Pet` clean names, ensuring all pet attacks are accurately categorized.
  - Fixed `isPlayerActor()` string matching by switching to exact string equality (`cleanActor == 'you'` / `cleanActor == cleanMyName`), resolving a bug where empty player name queries matched all pet damage and misclassified it under Player DPS.
  - Implemented `isPlayerActor()` with non-alphanumeric character stripping (`gsub("%W", "")`) and `mq.TLO.Me.CleanName()` verification, capturing player damage accurately regardless of first-person ("You") or third-person (Character Name) chat settings.
  - Consolidated event pattern registration into `onUnifiedMeleeHit` (`#1# #2# #3# for #4# points of damage#5#`) and `onUnifiedSpellHit` (`#1# hit #2# for #3# points of non-melee damage#4#`), eliminating MacroQuest event shadowing where generic wildcard listeners intercepted player combat lines before specific player listeners fired.
  - Corrected `ImGui.Begin` return order (`local open, draw = ImGui.Begin(...)`), resolving an issue where the titlebar `X` button close state was received in the `draw` variable instead of `open`.
  - Implemented dual-mode ASCII 7 (BEL character) & ASCII 127 color tag stripper in `cleanLine()`, removing hidden MQ color control bytes that prevented player combat log matching.
  - Implemented explicit script unloading via `mq.imgui.destroy()` and `mq.exit()` upon clicking the window titlebar close (`X`) button or typing `/dps close`.
  - Added safety guard (`type(mq.atexit) == 'function'`) for graceful exit handling on all MacroQuest Lua builds.
  - Styled interface adhering to the dark Triune design system.

- Added `lua/triune_buffbot.lua` standalone MacroQuest ImGui Lua script:
  - Saves current spell gems on script startup/start and restores original spell gems on stop or script exit via `mq.atexit()`.
  - Implemented interactive tell confirmation protocol (`Would you like buffs? Reply 'yes' within 30s`).
  - Added range checking against requesting player spawns.
  - Implemented dropdown combo selectors for 12 buff slots populated with scribed spells from character spellbook.
  - Added per-character configuration persistence (`triune_buffbot_config.lua` in MQ config dir) so buff slot selections and settings load automatically on launch.
  - Added automatic completion `/tell` sent to requesters after all configured buff spells finish casting.
  - Styled interface adhering to the dark Triune design system.

---

  - Added `recordSuccess()` helper to reset fail counts and clear lockouts upon successful spell completion.
  - Fixes `attempt to call field 'recordSuccess' (a nil value)` error post-cast.

- Fixed `sp.Duration()` type handling in `castGem()` in `lua/triune.lua`:
  - Wrapped `sp.Duration()` in `tonumber()` to ensure numeric comparison in `dur > 0`.
  - Fixes `attempt to compare number with string` runtime crash in `castGem()` line 2871.

- Fixed error handling & safety in `lua/triune.lua`:
  - Added explicit error reporting to `pcall(combatTick)` in `runMainLoop()`, printing red `[Triune error]` messages to chat if any sub-call throws a Lua runtime error.
  - Wrapped `s.CleanName()` in `resolveTargetId()` with `pcall` protection to prevent uncaught TLO exceptions.

- Fixed `resolveTargetId()` spawn HP & type evaluation in `lua/triune.lua`:
  - Wrapped `s.PctHPs()` and `s.Type()` evaluation in `pcall` guards within `resolveTargetId()`.
  - Fixes false `hp=0` / `nil` return on `Spawn(id).PctHPs()` when evaluating live NPC targets during combat.

- Fixed `baseTok()` target token resolution for saved character loadouts in `lua/triune.lua`:
  - Updated `baseTok()` to map legacy target strings (`'Target'`, `'Self'`) to canonical target names (`'Current Target'`, `'Myself'`).
  - Resolves `id=nil condOk=nil` spell evaluation failure when processing saved loadouts with un-prefixed target tokens.

- Fixed `countNPCXtarget()` XTarget & Target TLO property resolution in `lua/triune.lua`:
  - Resolved `xt.Type()` returning `nil` on XTarget slot TLO objects by querying `mq.TLO.Spawn(id).Type()` directly.
  - Added `pcall` guards and support for `NPC` and hostile `Pet` spawn types for both XTarget list slots and active target fallback.
  - Resolves `xtOk=false(0>=1)` gate failure when hostiles are on target or XTarget.

- Fixed spell gem targeting and memorization verification in `lua/triune.lua`:
  - Fixed `defaultsForKind()` returning raw target tokens (`'Target'`, `'Self'`) instead of prefixed tokens expected by `TARGETS` (`'E: Current Target'`, `'F: Myself'`), which caused newly picked spells or default loadouts to fail `resolveTargetId()`.
  - Fixed `castGem()` verification check for memorized spells: updated `Me.Gem(g.spell)()` check to inspect `Me.Gem(i).Name()` by slot index `i` as well as spell name, preventing false negatives where MacroQuest TLO gem-by-name returned `nil` for valid memmed spells.
  - Enhanced debug diagnostics in `combatTick()` to print explicit gating and condition status when `Debug Mode` is enabled.

- Fixed `isCombat()` detection helper in `lua/triune.lua`:
  - Updated `isCombat()` to evaluate `true` when `Me.Combat()`, `Me.CombatState() == 'COMBAT'`, active target is a live NPC, or XTarget has live NPCs.
  - Fixes spells configured with `when = 'in combat'` not firing in **Hunter**, **Manual Hunter**, and **Pet Tank** modes when fighting mobs before combat state or XTarget is registered by EverQuest.

- Fixed spell casting in **Hunter** and **Manual Hunter** modes in `lua/triune.lua`:
  - Added explicit `stopMoving()` call when `moveToward()` arrives within desired casting/attack range of the target.
  - Resolves issue where active `/stick` state remained flag-active (`isMoveActive() == true`), blocking spell casting in `combatTick()`.

- Fixed spell/ability casting issue caused by `min_xtar` combo selection:
  - Resolved `ImGui.Combo` returning option index `1` (`1`), which previously set `min_xtar` to `1` when selected but evaluated `0` or `nil` on existing unedited entries.
  - Added target fallback in `countNPCXtarget()`: if XTarget slots are empty or unpopulated, a current active live NPC target counts as `1` target so single-target spells (with `min_xtar = 1`) fire as expected.
  - Added `tonumber()` guards and bounds validation (`1` to `10`) for `min_xtar` combo rendering and condition evaluation (`numXtar >= (tonumber(g.min_xtar) or 1)`) across Spell Gems, AAs, and Disciplines tabs.

- Fixed zoning event processing bug in `lua/triune.lua`:
  - Added `mq.doevents()` call to the main loop loop iteration (`runMainLoop()`).
  - Ensures queued MacroQuest chat events (like `You have entered...`) process immediately while paused, preventing stale zone events from firing and pausing the engine when the user clicks **START** after zoning.

- Added **Min XTarget** (1-10) dropdown filter in `lua/triune.lua`:
  - Added per-entry `min_xtar` dropdown selector (displaying plain numbers `1` through `10`, width 45px, with tooltip on hover) to **Spell Gems**, **Abilities & AAs**, and **Disciplines** tabs (excluded from **Buff Loadout** tab).
  - Added `countNPCXtarget()` helper counting active, living, non-ignored, reachable NPCs on the player's XTarget list.
  - Enforced minimum XTarget check during combat loop execution: spells, AAs, and disciplines with `min_xtar > 1` only fire when the number of hostiles on XTarget meets or exceeds the specified threshold.
  - Persisted `min_xtar` settings across sessions in character loadout config files.

- Added **Min Mana %** setting to `lua/triune.lua`:
  - Added `ctrl.min_mana_pct` control setting (default `0%`, range `0%` to `95%`) persisted across sessions.
  - Added a `Min Mana %` slider under a new `Mana Management` section in the **Settings** tab UI.
  - Fixed an `invalid option '% =` printf format error in C/C++ `ImGui.SetTooltip` by replacing unescaped `%` percent specifier characters in tooltip strings with plain text.
  - Enforced minimum mana check in `castGem()`: automatically halts spell gem casting when character mana drops below the configured percentage threshold.
  - Automatically bypasses the minimum mana restriction when **Burn Mode** (`ctrl.burn`) is active, allowing full burst spending during burn burns.

- Added pre-cast active spell & debuff check to `lua/triune.lua`:
  - Added target active check in `castGem()` for all spells with a duration (`sp.Duration() > 0`), including DoTs, debuffs, slows, snares, CC, and buffs.
  - Prevents duplicate spell casting on targets when the effect is already active, conserving mana and preventing recast loops on `always`, `in combat`, and `on Named / burn` conditions.
  - Instant spells with zero duration (direct damage nukes, instant heals, cures, lifetaps) bypass the check and continue firing on demand.
  - Cleaned up duplicate function stub for `buffActive()` at lines 609-621 in `lua/triune.lua`.


- Added **Burn Mode** feature for burst damage on boss fights in `lua/triune.lua`:
  - Added `ctrl.burn` state persisted across loadout sessions.
  - Added a `BURN` toggle button beside `START` / `PAUSE` on the Control tab UI header.
  - Replaced the old 'x' clear button at the end of each Spell Gem row with the `Burn` checkbox (`Burn##bo`). To clear a gem slot, simply select `-- choose --` or `--` from the class/spell dropdowns.
  - Added `/ac burn [on|off]` slash command (and `/ac burn` toggle) with chat feedback, `ctrl.burn` state in `/ac status`, and documentation in the Help tab and `README.md`.
  - Added `Burn Only` (`Burn`) checkboxes to item rows in **Spell Gems**, **Abilities & AAs**, and **Disciplines** tabs (suppressed on **Buff Loadout** tab).
  - Gated execution of marked spells, AAs, and disciplines: when Burn Mode is OFF (`ctrl.burn == false`), marked abilities are skipped. When ON, they fire according to their normal triggers.
  - Added auto-disable feature: Burn Mode automatically turns OFF (`ctrl.burn = false`) as soon as all mobs are cleared from the extended target list (`not anyXtarAlive()`).

- Removed "Repeat Missing Mob Msg" checkbox and control setting from Hunter mode in `lua/triune.lua`:
  - Removed `ctrl.hunter_repeat_msg` setting and its ImGui checkbox from the Hunter tab UI.
  - Simplified Hunter mode log behavior to log missing target diagnostics once whenever target search parameters or anchor settings change.

- Fixed discipline classification issue in `lua/triune.lua`:
  - Filtered out combat disciplines from `filteredSpells()` so they no longer appear inside the spell selection dropdowns under the **Spell Gems** tab and **Buff Loadout** tab.
  - Added `PURE_MELEE_CLASSES` mapping (`War`, `Mnk`, `Rog`, `Ber`) and `isDisciplineSpell(abbr, spellName)` helper to identify disciplines by checking `DATA.discs`, MQ TLO `Spell.IsSkill()`, and discipline state.
  - Updated `classHasSpells()` to return `false` for pure melee classes so they correctly display `"has no gem spells (melee) -> Abilities tab"` in the UI instead of rendering empty or discipline-populated spell pickers.
  - Updated `spellClassInfo()` to exclude disciplines and pure melee classes from spell class ownership lookups.

- Standardized spell categorization across `lua/triune_spellbook.lua` and `lua/triune.lua`:
  - Established standardized 8-category system: `ALL`, `DD` (nukes), `DoT` (damage over time), `Debuff` (slows, Tash, Malo, AC debuffs), `Buff` (beneficial buffs), `Heal` (heals/HoTs), `Pet` (SPA 103 pet summons), and `Util` (item summons, ports/gate, rez/corpse, CC).
  - Created `checkHasSPA()` in `lua/triune_spellbook.lua` supporting SPA 103 (`SE_SummonPet`), item summoning (SPAs 32, 33, 108), Teleport/Gate/Evac (SPAs 83, 88), Resurrection/Corpse (SPAs 81, 91), CC (SPAs 18, 22, 31), and Debuffs (SPAs 11, 23, 46).
  - Updated spellbook top category filter buttons to `ALL`, `DD`, `DoT`, `Debuff`, `Buff`, `Heal`, `Pet`, `Util`.
  - Updated `KIND_LABEL` in `lua/triune.lua` and `KIND_LABELS` in `lua/triune_spellbook.lua` to sync category tags across dropdown pickers and spell table rows.
  - Defined `KIND_LABEL` above `filteredSpells()` in `lua/triune.lua` to prevent `nil` scoping errors when rendering the **Spell Gems** tab.
  - Reordered evaluation order inside `mapTLOCategoryToKind()` in `lua/triune_spellbook.lua` and `lua/triune.lua`: beneficial status is extracted early so beneficial player haste (*Celerity*, *Alacrity*, *Swift*), movement buffs (*Spirit of Wolf*, *SoW*), and damage shields (*Shield of Lava*, *Shield of Fire*) route directly to **`buff`**, non-beneficial direct damage nukes and lifetaps (*Lifetap*, *Lifedraw*, *Lifespike*, *Siphon Life*, *Drain*) route to **`dd`**, non-beneficial debuffs (*Mala*, *Malo*, *Malosi*, *Tash*, *Incapacitate*, *Listless Power*, *Disempower*, *Turgur's*) route to **`debuff`**, and utility/travel/stealth spells (*Gate*, *Bind Affinity*, *Invisibility*, *Camouflage*, *Translocate*, SPAs 12, 29, 30, 41, 83, 88) route to **`util`**.
  - Positioned `mapTLOCategoryToKind()` lexically above `filteredSpells()` in `lua/triune.lua` to fix a nil function reference error when populating spell gem dropdown pickers.
  - Prioritized dynamic `mapTLOCategoryToKind()` SPA and category string evaluation over legacy static `kind` values from database tables across `triune_spellbook.lua` (`getActiveClassSpells`) and `triune.lua` (`filteredSpells` & `spellClassInfo`).

- Fixed character class auto-detection fallback issue in `lua/triune.lua`:
  - Replaced hardcoded default `myClasses = { 'War', 'Rng', 'Brd' }` with an empty table `{}`.
  - Updated `UI.drawClassPicker()` combo box logic so unassigned class slots do not implicitly overwrite class slots with `'War'`, `'Rng'`, or `'Brd'`, preventing incorrect class AA/spell lists from rendering.

- Updated zoning behavior in `lua/triune.lua`:
  - Updated `onZoned()` handler to set `ctrl.running = false`, issue `fullStop()`, and log `zoned -- pausing autocombat` when transitioning between zones.

## 2026-08-05

- Updated Pet Hold management in `lua/triune.lua`:
  - When **Enable Pet Hold** is checked (`ctrl.pet_hold_enabled`), the engine issues `/say #petcmd hold all` (a toggle command) anytime the trio is out of combat or prior to reaching the configured Pet Assist At HP% threshold to enable pet hold.
  - Once in combat and the mob HP meets or drops below `ctrl.pet_assist_at`, the engine issues `/say #petcmd attack all` to send pets.
  - Updated tooltips and documentation comments to reflect exact `#petcmd hold all` toggle syntax.

- Updated **Puller** mode in `lua/triune.lua` to handle incoming aggro on path to mob:
  - Checked `firstNPCXtarget(false)` during the `TO_MOB` state in `pullerTick()`.
  - If another NPC attacks the puller while running toward a target mob, the puller halts navigation, switches target to the incoming aggro mob (`runtime.pullTargetId = aggroId`), and transitions immediately to `TO_CAMP` state to pull it back to camp.

- Added **Help** tab to `lua/triune.lua` ImGui window:
  - Positioned at the end of the tab bar after the Ignore List tab.
  - Formatted ImGui tables for Slash Commands (`/ac run`, `/ac pause`, `/ac status`, `/ac spellbook`, `/ac cursorui`, `/ac clearcursor`, `/ac <mode>`, `/triunerun`) and Combat Modes (`MODES` table with `MODE_DESC` explanations).
  - Used `accent(COLOR, text)` helper and `bit.bor()` for combining `ImGuiTableFlags` enum values, ensuring strict Lua 5.1 / LuaJIT compatibility and preventing `')' expected near '|'` syntax errors.

- Updated Hunter Combat Radius UI slider in `lua/triune.lua`:
  - Removed `ImGui.BeginDisabled()` constraint so the **Combat Radius** slider remains fully interactive regardless of whether an anchor location is set.
  - Added immediate `updateMapRadiusVisuals()` invocation when dragging the Combat Radius slider or clicking Set/Clear Anchor to update the green anchor circle on the map live in real-time.
  - Preserved radius value when clearing the anchor so pre-configured radius preferences persist when re-anchoring.

- Updated Hunter mode behavior when no targetable NPCs are found in `lua/triune.lua`:
  - Player now stops moving and stays in place instead of wandering to random locations when no valid mobs are in search/level range.
  - Clears `pursuit.wanderLoc` and halts `/nav` / `/stick` movement when idle in Hunter mode.
  - Prints a diagnostic message (`Hunter: No NPCs found (Lvl min-max, Radius R, Z diff...). Waiting...`) when no mobs are found.
  - Diagnostic message appears once and does not repeat continuously on every tick, unless search range/level settings or anchor config are changed.
  - Set default `hunter_combat_radius` in `defaultCtrl()` table to `250` in `lua/triune.lua`.
  - Added `hunter_repeat_msg` setting under `ctrl` table and a "Repeat Missing Mob Msg" checkbox in the Hunter tab UI to allow optionally repeating the diagnostic message.
  - Resets missing mob message tracking state as soon as a target is acquired.

- Added map radius circle visualization for combat modes in `lua/triune.lua`:
  - Hunter search radius draws a **red** circle (`/mapfilter castradius color 255 0 0` + `castradius show`) centered on the character that dynamically moves with the player across the map as they hunt.
  - Stationary Camp/Anchor locations continue to draw green circles (`rcolor 0 255 0`) via `/maploc` and `/mapfilter pullradius`.
  - Unconditionally clears all previous map overlays (`/maploc remove`, `/mapfilter pullradius 0`, `/mapfilter castradius 0`) when switching modes or redrawing to prevent leftover initial circles from lingering on the map.
  - Added state key tracking in `updateMapRadiusVisuals()` to prevent redundant `/maploc` or `/mapfilter` command executions.
  - Added `show_map_radius` setting (default `true`) under `ctrl` table, saved settings persistence, and auto-save signature calculation.
  - Added "Show Map Radius Circles" checkbox and tooltip under Navigation in the Settings UI tab.
  - Added `clearMapRadiusVisuals()` to clean up all map markers and filters on script exit or when disabled.

- Fixed IDE diagnostic warnings for undefined MacroQuest ImGui globals and fields across `lua/triune_cursor.lua`, `lua/triune_spellbook.lua`, and `lua/triune.lua`:
  - Added `local ImGui = require('ImGui')` import to `lua/triune_cursor.lua`.
  - Added `---@diagnostic disable: undefined-global, undefined-field` file annotations to suppress MacroQuest C++ runtime ImGui global type & field LSP warnings.

- Fixed `mq2movutils you are not sticking to anything` chat spam in `lua/triune.lua`:
  - Added `mq.TLO.Stick.Active()` and `mq.TLO.Stick.Status() == 'ON'` checks in `stopMoving()`, `fullStop()`, `moveToward()`, and `performUnstuck()` prior to issuing `/stick off` or `/stick id`.
  - Fixed `performUnstuck()` calling `/stick off` and `/nav stop` unconditionally without checking active status.
  - Guarded `moveToward()` to prevent re-issuing `/stick id` every tick when already sticking to the current target.

- Prevented NPC target bouncing in Hunter mode in `lua/triune.lua`:
  - Removed opportunistic target swapping logic that checked for closer fresh mobs while already navigating toward or engaging an NPC.
  - Hunter now sticks to its target until it dies, becomes unreachable/ignored, or `checkAggroSwitch()` detects a hostile NPC actively attacking the player.

- Fixed AA name rendering and checkbox synchronization in `drawAATab` in `lua/triune.lua`:
  - Added strict `not tonumber(nm)` filtering in `hasAA()` and `drawAATab()` to filter out numeric cooldown keys (e.g., `60`, `90`) from being displayed as AAs.
  - Scoped ImGui IDs using `ImGui.PushID('aa_' .. tier .. '_' .. cls .. '_' .. nm)` so checkboxes for distinct AAs maintain isolated state without checking multiple rows simultaneously.

- Fixed `attempt to index local 'a' (a nil value)` crash in `loadoutSig()` in `lua/triune.lua`:
  - Added `type(a) == 'table'` and `type(d) == 'table'` guards when iterating over `loadout.aas` and `loadout.discs` entries during auto-save signature calculation.

- Fixed ImGui runtime exception in `drawDiscTab` / `drawAATab` in `lua/triune.lua`:
  - Updated `classColor(abbr)` helper to unpack `r, g, b, a` RGBA values instead of returning a table array. Fixes `sol: no matching function call` crash in `ImGui.TextColored` when drawing class tabs.

- Cleaned up IDE diagnostic warnings in `lua/triune.lua` and `lua/triune_spellbook.lua`:
  - Added line-level `---@diagnostic disable-line: undefined-field` annotations for MacroQuest ImGui `PopStyleVar`, `PopStyleColor`, and `StyleVar` dynamic lookups.

- Updated auto-attack / auto-fire gating in `lua/triune.lua`:
  - Enforced distance check so `/attack on` (or `/autofire on`) only turns on once within range of the target (`MELEE_RANGE` / `ranged_dist`).
  - Added XTarget list check via `anyXtarAlive()` to immediately execute `/attack off` and `/autofire off` as soon as all hostile NPCs on the XTarget list are dead/cleared.

- Updated pet hold command and added a toggle setting in `lua/triune.lua`:
  - Updated pet hold command execution from `/pet hold` to `/say #petcmd hold all` in combat loop pet management logic.
  - Added `pet_hold_enabled` (default `true`) under `ctrl` table, saved settings persistence, and auto-save signature calculation `loadoutSig()`.
  - Added "Enable Pet Hold" checkbox and tooltip in the Control/Settings UI tab under Pet Settings.

- Completed Option A refactor to make `triune.lua` fully self-contained:
  - Removed missing module dependency `local common = require('triune_common')` from `lua/triune.lua`.
  - Inlined all common utilities into `triune.lua` (`MQSHORT`, `SLOT_COLORS`, `classColor`, `classPlausible`, `detectClasses`, `defaultsForKind`, `idxOf`, `isScribed`, `hasAA`, `hasDisc`, `isSpawnAlive`, `distToId`, `distToLoc`, `hasLoS`, `pctHP`, `buffActive`, `sungKey`, `navLoaded`, `stickLoaded`, `isMoveActive`, `stopMoving`, `firstNPCXtarget`, `maPcId`, `createCastTracker`, `clearCursor`, `tryMem`, `pushTheme`, `popTheme`).
  - Fixed ImGui `ImVec2` vector safety in `drawEmblem()` using `_G.ImVec2` fallback.
  - Bumped version to `3.27-no-commonmod` across `lua/triune.lua` and `README.md`.
- Resolved static analysis warnings and critical logic bugs across project files:
  - Fixed critical infinite recursion stack overflows in `triune.lua` by renaming inner helpers (`firstNPCXtarget` -> `findFirstNPCXtarget`, `maPcId` -> `findMaPcId`).
  - Restored missing `pushTheme()` and `popTheme()` local functions in `triune.lua`.
  - Fixed `classColor()` return tuple unpacking bug causing `nil` alpha parameters in `ImGui.TextColored()`.
  - Added standalone `detectClasses()` implementation to `triune_spellbook.lua` and fixed undeclared global functions (`cleanSpellName`, `normalizeSpellName`, `checkBook`, `getSpellBookSlot`, `isScribed`).
  - Added diagnostic annotations for MQ TLOs (`CombatAbilityCount`, `Title`, `Song`, `Poisoned`, `Diseased`, `AggroHolder`) and ImGui deprecation flags across `triune.lua`, `triune_spellbook.lua`, and `triune_cursor.lua`.
  - Cleaned up duplicate code blocks in `triune_spellbook.lua` to resolve syntax errors (`Miss corresponding end`), defined `cleanSpellName()` and `hasDisc()` alias in `triune.lua`, and updated `ImGuiCol.TabSelected` across all windows.
  - Added explicit table fallback for `knownDiscSet` in `isDiscKnown()` and guarded `myClasses` assignment on line 997 against `nil` in `triune.lua`.
  - Cleaned up stale `(Delegated to triune_common)` comment header in `lua/triune.lua`.

- Fixed spell dropdown population bug in ImGui spell picker in `lua/triune.lua`:
  - Scoped `ctrl.scribed_only` filtering in `filteredSpells()` so it only applies when querying spells for the currently logged in player's class (`mq.TLO.Me.Class.ShortName()`). Prevents non-local trio classes (e.g. Enchanter/Magician when logged in as Cleric) from having empty spell dropdowns.
  - Fixed TLO query syntax in `isScribed()` fallback (`mq.TLO.Me.Book(name)()`), correcting `.ID()` calls on integer return values from `Me.Book(name)`.
  - Updated `spellClassInfo()` to use `lookupSpells(abbr)` for case-insensitive and class alias safety.
- Fixed class detection in `triune_spellbook.lua`:
  - Added primary lookup of saved character class configurations from `mq.configDir .. '/triune_loadout.lua'` so the standalone spellbook automatically loads the character's saved trio configuration.
  - Upgraded fallback `detectClasses()` to check MacroQuest Window Title and `InventoryWindow` class list (`IW_ClassList`) before falling back to single primary character class.
  - Added `pcall` guards around `mq.TLO.Me.Class.ShortName()` in `getSpellLevelForClassID()` to prevent nil crashes.

---

## 2026-08-04

- Fixed duplicate code block in `pullerTick()` - removed redundant `if not ctrl.camp_loc then return end` check (line 2394)
- Fixed potential crash in `fireAA()` when accessing AA spell data - wrapped `aa.Spell()` call with proper type checks before accessing EnduranceCost/ManaCost
- Added missing `mq.doevents()` calls to ensure chat events are processed:
  - Moved doevents() earlier in combat loop (before gem casting) to catch repositioning cues and failure messages immediately
  - Added final doevents() in main loop to process any remaining queued events
- Fixed unsafe camp_loc field access by adding table type checks before accessing `.x/.y/.z` fields:
  - UI Camp Location section (line 1257)
  - idleReturn() function (line 2326)
  - Garrison mode camp return (line 2790)
- Increased setTarget() timeout from 300ms to 1000ms to prevent premature target switch failures on laggy servers
- Fixed ImGui window rounding not being applied:
  - Removed `NoDecoration` flag from all windows to restore title bar with close button (X)
  - Updated `pushVar()` to properly handle ImVec2 for 2D style variables using `_G.ImVec2` fallback
  - Changed WindowRounding to 10, ChildRounding to 8, added BorderSize settings for Window/Child/Popup
  - Ensured FramePadding (7,4), ItemSpacing (8,6), WindowPadding (12,10) use ImVec2 vectors correctly
- Fixed linter warnings by converting global functions to local and adding forward declarations:
  - Added forward declaration for `isCombat` and `isUnreachable` before their use
  - `fullStop` and `onZoned` already had forward declarations (line 237)
  - `triuneToggle` converted to `local`
- Fixed ImGui window rounding by moving theme code from triune_common.lua into each UI file:
  - Moved pushTheme/popTheme functions from triune_common.lua to triune.lua
  - Added same theme code to triune_spellbook.lua and triune_cursor.lua
  - Theme now uses mq.imgui or _G.ImGui* enums with pcall guards for safe fallback
  - WindowRounding, ChildRounding, FramePadding, ItemSpacing, WindowPadding all applied correctly

---
## 2026-08-03

- Updated **ImGui Theme & Window Rounding Styling**:
  - Implemented proper 2D `ImVec2` vector handling in `pushVar()` in `triune_common.lua` for style variables that expect 2D dimensions (`FramePadding`, `ItemSpacing`, `WindowPadding`).
  - Set `WindowRounding` to 10 and added `WindowBorderSize = 1` in `common.pushTheme()` so all ImGui windows feature smooth, prominent rounded corners and clean borders.
  - Aligned `ChildRounding` (8), `ChildBorderSize` (1), `PopupRounding` (8), `PopupBorderSize` (1), `FrameRounding` (6), `FrameBorderSize` (1), `TabRounding` (6), `GrabRounding` (6), and `ScrollbarRounding` (8) for consistent rounded styling across all windows, sub-panels, tooltips, popups, tabs, and input controls.

---

## 2026-08-01

- Fixed **Hunter mode aggro switching & XTarget clearing flow**:
  - If Hunter takes aggro while running toward a distant roam target (an NPC enters XTarget), movement immediately stops (`stopMoving()`, pursuit state reset), and target switches to the aggroed XTarget NPC (`firstNPCXtarget(false)`).
  - Hunter now fights all NPCs on XTarget sequentially until `anyXtarAlive()` is false before seeking new roaming targets.
  - XTarget hostiles in `findRoamTarget` are no longer filtered by the combat anchor radius, ensuring characters always defend themselves against active aggressors regardless of position.
  - `checkAggroSwitch()` now calls `stopMoving()` and resets `pursuit.id` / `pursuit.lastNavTargetId` on target switch so navigation re-routes cleanly.
  - Added strict global corpse and dead-spawn filtering (`not s.Dead()`, `s.Type() ~= 'Corpse'`, `(s.PctHPs() or 0) > 0`) across `setTarget`, `isCombat`, `haveNPC`, `findRoamTarget`, `pullerTick`, `maTargetId`, `resolveTargetId`, `common.isSpawnAlive`, `common.firstNPCXtarget`, and `common.lowestHpNPCXtarget` to completely prevent targeting or navigating to dead corpses.
  - Fixed invalid `noanim` MQ TLO search string parameter in `findRoamTarget()` and `resolveTargetId()` that caused `NearestSpawn` lookups to fail and return nil, fixing the issue where Hunter would stand still or wander to random locations without acquiring targets. Expanded nearest spawn scan to 30 candidates.
  - Updated pet assist threshold logic for self-directed modes (`Hunter`, `Pet Tank`, `Garrison`, etc.) so pet attacks dispatch reliably at `ctrl.pet_assist_at` without getting blocked by `playerIsEngagingTarget()`.

- Added Hunter mode **Combat Radius** anchor feature.
  - New `ctrl.hunter_combat_loc` (x/y/z table) and `ctrl.hunter_combat_radius` (integer, 1–2000) fields in `defaultCtrl()`.
  - New UI sub-section in the Combat tab (Hunter / Pet Tank panel): shows the anchor coordinates or "No anchor set", **Set Anchor** and **Clear Anchor** buttons, and a **Combat Radius** slider (greyed out until an anchor is placed).
  - **Set Anchor** saves the player's current position; if the radius was 0, auto-sets it to 500 as a sensible first-time default.
  - **Clear Anchor** resets both `hunter_combat_loc` and `hunter_combat_radius` to nil/0 and clears any pending `pursuit.wanderLoc`.
  - `findRoamTarget` now post-filters XTarget and NearestSpawn candidates: any mob whose 2D distance from the anchor exceeds `hunter_combat_radius` is rejected, so the player never chases a mob outside the circle.
  - Hunter wander logic is now anchor-bounded: when a combat anchor is active, random wander points are chosen inside the anchor circle (30–90% of the combat radius from the anchor center) rather than near the player's current position.
  - Anchor is cleared automatically on zone-out (matching `camp_loc` behaviour).
  - Both fields persist across log-out/log-in automatically because `ctrl` is serialised whole via `collectEntry()`.

- Fixed **Pet Assist At %** threshold not actually holding pets before the HP condition is met.
  - Added `hasAdvPetDiscipline()` helper that checks `mq.TLO.Me.AltAbility('Advanced Pet Discipline')` (with pcall guard) and returns `true` only when the AA is owned at rank ≥ 1.
  - When **Pet Assist At % < 100** and the player owns the AA: `/pet hold` is issued the first tick a new target is engaged (before the threshold is reached), keeping pets stationary; `/say #petcmd attack all` is then sent as soon as target HP drops to or below the threshold.
  - When the AA is not owned: the hold command is skipped entirely (it is silently ignored by the game without the AA); pets continue to receive the attack command at threshold exactly as before.
  - If combat ends before the threshold is ever reached (mob died too fast, player disengaged, etc.), `/pet back off` is sent to release any stale hold so pets are not left frozen after the fight.
  - Added `petHoldActive` and `holdIssuedForId` fields to `petState` to track hold state without bare top-level locals.
  - **Critical crash fix:** `hasAdvPetDiscipline()` called `aa()` outside any pcall guard. Calling the TLO functor on an AA the character doesn't own throws an exception in some MacroQuest builds; this exception propagated up and was silently swallowed by the `pcall(combatTick)` in the main loop, halting the entire combat engine every tick. The whole AA check is now a single `pcall` so any throw is caught and returns `false`.

- Fixed Hunter mode going to random locations instead of seeking mobs after a reload.
  - Root cause: `hunter_combat_loc` (the combat radius anchor) was being restored from the saved loadout via `applyEntry`. Since the anchor is a zone-specific position (like `camp_loc`), reloading it in a new session/zone caused `findRoamTarget` to reject every mob outside the stale anchor circle, leaving no valid targets and forcing the wander path.
  - `applyEntry` now explicitly clears `hunter_combat_loc` and `hunter_combat_radius` after applying the saved `ctrl` block. Players set the anchor in-game each session.
  - Added `hunter_combat_loc` and `hunter_combat_radius` to `loadoutSig` so anchor Set/Clear actions trigger auto-save (previously, clearing the anchor would not save immediately).
  - Increased wander point hold-time from 8 s to 20 s so MQ2Nav has time to actually reach a random wander destination before the engine picks a new one.

- Fixed Hunter mode roaming to a new mob before all current XTarget NPCs are dead.
  - Added `anyXtarAlive()` helper that iterates `Me.XTarget(1..13)` and returns `true` if any live (HP > 0), non-ignored, reachable NPC remains on the extended target list.
  - Guarded the "swap to a closer fresh mob" optimisation: Hunter will no longer redirect to a nearby `NearestSpawn` mob while xtar still contains live hostiles. `checkAggroSwitch()` continues to handle close-range in-combat adds unconditionally.
  - Guarded the wander path: Hunter will no longer navigate toward a random wander location to seek new mobs while xtar is not fully cleared. If xtar has live entries but `findRoamTarget` returns nil (e.g. all ignored/unreachable), the character idles for that tick until the situation resolves naturally.
- Fixed `attempt to compare number with string` crash in `loadoutSig()` (`table.sort` on `loadout.aas` / `loadout.discs` key lists). Stale save files can persist numeric keys in those maps; keys are now coerced to `tostring()` before sorting so the comparison is always string-vs-string regardless of what the save file contains.
- Improved pet dispatch for Hunter and all other modes:
  - Added `playerIsEngagingTarget(tid)` helper: returns `true` once the player is demonstrably hitting the mob — `/attack` on (melee), `/autofire` on (ranged), or mob HP has dropped below 100% and the player holds aggro (spell landed). Replaces the previous proximity-only check so Spell/Ranged players correctly trigger pet dispatch without closing to melee range.
  - Added `ctrl.pet_assist_at` slider (1–100%, default 100%) in the Control tab, visible only when the trio contains a pet class. Pets are withheld until the target's HP drops to or below this threshold AND the player has started hitting the mob.
  - Pet Tank mode bypasses the engagement gate (pets are the tank by design); only the HP threshold applies.
  - Non-pet trios (e.g. War/Pal/Mnk) see no Pet Settings UI and never trigger `/say #petcmd`.
- UI: extracted universal settings from the Control tab into a new **Settings** tab:
  - **Control tab** now shows only operational/mode-specific controls: Status/Start-Pause, Mode selector, Hunter/Pet Tank sliders, Main Assist settings, Camp Location, and Pet Settings (for pet-class trios).
  - **Settings tab** contains all settings that apply regardless of mode: Combat Style (Melee/Ranged/Spell) + Range slider, Navigation (Fallback to Stick, Debug Mode), Spell Failures & Lockout (Max Retries, Lockout Time), and Med Break.

---

## 2026-07-31

- Fixed `triune_spellbook.lua` not showing correct classes: `MQSHORT` table was mapping to uppercase abbreviations (`WAR`, `CLR`, `BST`) instead of the mixed-case keys used by `triune_data.lua` (`War`, `Clr`, `Bst`, `SK`). Aligned all mappings to match the data file.
- Fixed `triune_spellbook.lua` `detectClasses()` not reading the character's class trio: the InventoryWindow was not being force-opened, so the `IW_ClassAbbr` label was never populated. Now mirrors `triune.lua`'s approach — force-opens the window, retries up to 12 times for the label to populate, then closes it back.
- Fixed `triune_spellbook.lua` not showing scribed spells for non-primary classes: `Spell.Level(classId)` returns 0 for secondary/tertiary classes on a multi-class server. Added a fallback that cross-references scribed spell names against the `triune_data.lua` class spell list to correctly identify and display them with proper levels.
- Updated `CLASS_SHORT_TO_ID` in `triune_spellbook.lua` to accept both mixed-case and uppercase class abbreviations.
- Added `loadData()` multi-path search (configDir + luaDir) and startup diagnostic console output showing detected classes and DB spell counts per class.
- Fixed remaining bare state variable references in `triune.lua` (`performUnstuck`, `hasNamedBuff`, `onCharacterChanged`, Clear Camp button, `conditionMet`) that were still using `stuckCounter`, `lastNavTargetId`, `lastBuffDiagAt`, `sungBuffs`, `pullState`, and `pullTargetId` instead of their state table equivalents.
- Consolidated shared functions across `triune.lua` and `triune_spellbook.lua` into `triune_common.lua`:
  - **`common.MQSHORT`**: Unified class abbreviation mapping table.
  - **`common.cleanSpellName` & `common.normalizeSpellName`**: Shared spell rank and fuzzy normalization helpers.
  - **`common.getSpellbookMap`, `common.getSpellBookSlot`, `common.checkBook`, `common.isScribed`**: Robust spellbook inspection and multi-stage scribed lookup.
  - **`common.detectClasses`, `common.classesFromInventoryWindow`, `common.classesFromTitle`**: Standardized class trio detection engine.
  - **`common.tryMem` & `common.SBW`**: Unified UI spell memorization engine with target gem clearing, page turning, pickup/drop, and casting gauge verification.
- Cleaned up duplicate local definitions in `triune.lua` (`isSpawnAlive`, `isCasting`, `buffActive`, `classColor`, `defaultsForKind`, `detectClasses`, `isScribed`, `tryMem`, `MQSHORT`), reducing `triune.lua` by over 360 lines and freeing up local variable space.
- Added `common.clearCursor()` auto-inventory engine in `triune_common.lua`: inspects `Cursor()` for items and executes `/autoinventory` with up to 255 iterations to clear large item queues/stacks.
- Integrated `common.clearCursor()` into `common.tryMem()` and `triune.lua` main execution loop to prevent cursor items from blocking spell memorization or combat loops.
- Added `/ac clearcursor` (aliases: `/ac autoinv`, `/ac cursor`) slash command to manually trigger item cursor clearing.
- Fixed severe script lag/game slowdown by eliminating 150ms continuous `classesFromInventoryWindow` UI polling in `runMainLoop()`. Restricted class trio re-detection strictly to **zoning** (`onZoned()`), **login/startup** (`onCharacterChanged()`), and **manual user demand** ("Re-detect Classes" button).
- Fixed severe framerate drop and lag when opening the **Spell Gems** and **Buff Loadout** ImGui tabs:
  - Optimized `common.getSpellBookSlot()` in `triune_common.lua` to check the pre-cached O(1) spellbook map first, reducing live TLO queries per spell check from ~8 to 0.
  - Added 2-second caching to `filteredSpells()` in `triune.lua`, eliminating the 28,800 TLO queries per frame executed across 12 gem dropdowns during ImGui tab renders.
  - Added 5-second caching to `common.hasAA()` in `triune_common.lua` for smooth rendering of the Abilities & AAs tab.
- Restored `common.defaultsForKind(kind, bene)` in `triune_common.lua` to fix the `attempt to call upvalue 'defaultsForKind' (a nil value)` error in `drawGemList`.
- Added standalone `triune_cursor.lua` ImGui cursor manager:
  - Displays current cursor item details in a 3-column ImGui Table (**Item Name**, **Qty / Stack**, and **Actions**).
  - Provides **Auto Inv** (delegates to `common.clearCursor()`) and **Destroy** (delegates to `common.destroyCursor()`) buttons with safety confirmation check.
  - Fixed `unexpected symbol near '|'` error in `triune_cursor.lua` by using Lua 5.1 compliant ImGui table flag combination syntax.
  - Added `common.destroyCursor()` helper to `triune_common.lua`.
  - Added `/ac cursorui` (aliases: `/ac cursorwin`, `/ac cursormgr`) command and a **Cursor Manager** header button to `triune.lua`.
  - Added live active item inspector (Name, ID, Qty, Lore/NoDrop flags) and an interactive **Session History Log** ImGui Table (`#`, `Time`, `Item Name`, `Qty`, `Action`).
  - Added **Auto-Clear Items on Pick (Continuous)** toggle to automatically drain any queued items touching the cursor.
  - Added `ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)` to ensure the Cursor Manager window opens fully expanded.
  - Fixed `Cannot delay from non-yieldable thread` error when clicking ImGui action buttons in `triune_cursor.lua` by queueing button actions to execute safely on the yieldable main coroutine thread.
- Unified ImGui theme and visual styling across all Triune windows (`triune.lua`, `triune_spellbook.lua`, `triune_cursor.lua`):
  - Centralized `common.pushTheme()` and `common.popTheme()` in `triune_common.lua`.
  - Enforced 100% consistent color palette (Midnight Blue `#0F1622` backgrounds, Steel Blue `#284058` borders, Arc Cyan highlights, Amber sliders, Emerald checkmarks) and frame padding/rounding across all windows.
- Moved the **Save Loadout** button inside the `Character Classes & Loadout` collapsing header in `triune.lua` so it collapses cleanly alongside the class trio selector, keeping the main interface compact.
- Resolved all linter scope warnings and undefined references across `triune.lua`, `triune_spellbook.lua`, and `triune_common.lua`:
  - Created `.luarc.json` project config declaring all MacroQuest ImGui runtime globals (`ImGuiCond`, `ImGuiCol`, `ImGuiStyleVar`, `ImGuiTableFlags`, `ImGuiTableColumnFlags`, `ImGuiSelectableFlags`, `ImGuiWindowFlags`, `ImVec2`, `ImVec4`, `IM_COL32`) so the Lua language server stops flagging them as undefined.
  - Added `---@diagnostic disable-line: undefined-field` on `mq.imgui.Col` and `mq.imgui.StyleVar` accesses in `common.pushTheme()` — these are MQ runtime fields the LLS cannot introspect.
  - Fixed `getSpellBookSlot` reference in `triune_spellbook.lua` BST diagnostics block to call `common.getSpellBookSlot` (regression from prior refactor).
  - Removed legacy `OWNERS` and `buildIndex()` dead-code branches in `spellClassInfo()` and `importCurrentGems()` in `triune.lua` (CHANGELOG noted removal but references remained in code).
  - Fixed `SLOT_COLORS` real runtime bug in `drawEmblem()`: `triune.lua` was referencing a `local` that only exists in `triune_common.lua`. Exposed it as `common.SLOT_COLORS` and updated `drawEmblem()` to use `common.SLOT_COLORS[slot]`.
  - Fixed stale debug print variables (`n`, `names`, `ok`, `err`) inside `hasNamedBuff()` that no longer existed after a prior refactor. Replaced with `cnt` (already in scope) and a locally-built `activeNames` table; removed the now-obsolete `ok`/`err` error suffix.
  - Added nil guard on `ctrl.camp_loc` before `.x/.y/.z` field access in the `TO_CAMP` pull-state branch — a nil `camp_loc` would crash if the puller state machine entered that branch without a camp set.
  - Added nil guard `(knownDiscSet or {})` in `common.hasDisc()` to satisfy the LLS nil-check warning (runtime behavior unchanged; `scanKnownDiscs()` always initialises the table just above).
  - Declared `lastCombatFaceAt` as a proper `local` before `moveToward()` in `triune.lua` (was an implicit global).
  - Fixed forward declarations for `isCombat` and `isUnreachable`: previous attempt placed the `local` declarations *after* their first call sites, leaving the LLS unable to resolve them. Corrected by declaring each name once with `local` before its first use and changing `local function isCombat()` / `local function isUnreachable()` to plain `isCombat = function()` / `isUnreachable = function()` assignments so the single upfront binding is the authoritative reference for both the LLS and the runtime.

---

## 2026-07-30

- Updated command bindings to use `/ac` as the main interface, including `/ac run`, `/ac pause`, `/ac status`, and `/ac` as a run/pause toggle.
- Added mode commands `/ac <mode>` for every supported mode, including `/ac hunter`, `/ac manualhunter`, `/ac garrison`, and other modes from the script.
- Fixed auto-memorization (`tryMem`) failure when target gem slot (or a duplicate gem slot) is occupied by automatically right-clicking to unmemorize existing spells before picking up the new spell. Added RankName fallback matching.
- Implemented player aggro detection (`playerHasAggro`) inspecting TargetOfTarget, AggroHolder, PctAggro, and active damage/combat hits.
- Gated pet attack dispatch (`#petcmd attack all`) behind `playerHasAggro` check for Hunter, Manual Hunter, Garrison, Puller, and Tank modes, ensuring pets only engage once player has generated aggro.
- Enhanced positioning & line-of-sight checks in `moveToward` during combat: now verifies `hasLoS` before confirming arrival and periodically re-faces target (`/face fast`) every second while fighting.
- Expanded `checkAggroSwitch` self-defense target switching to detect and prioritize any mobs hitting/aggroing the player up to 40 units away.
- Implemented consecutive spell failure tracking (`castTracker`): tracks fizzles, interrupts, out-of-range, target out of sight, and immune/failed casts. Enforces a retry limit per spell; if a spell fails continuously, it is locked out before attempting again, allowing other loadout spells to fire without getting stuck.
- Implemented automatic combat repositioning (`repositionCloser`): catches chat messages ("too far away", "get closer", "cannot reach"), immediately re-faces the target (`/face fast`), clears stale arrival state, and issues `/nav` or `/stick` to close distance directly into hit range.
- Implemented XTarget clearing check (`lowestHpNPCXtarget`): in Hunter, Puller, Garrison, and Pet Tank modes, Triune now ensures all active mobs on the extended target list (XTarget) are completely cleared before looking for new roam/pull targets.
- Added lowest HP NPC targeting logic: when multiple mobs are active on XTarget, Triune automatically targets and attacks the mob with the lowest percentage HP first (prioritizing unmezzed mobs).
- Fixed spell lockout & failure tracking logic: added `mq.doevents()` processing in combat loop to instantly parse chat failure events, fixed Lua boolean truthiness issue where `Me.Casting.ID()` returning `0` was treated as `true` (`isCasting()`), and expanded chat event patterns (`fizzle`, `interrupted`, `see your target`, `take hold`, `resisted`, `not ready`, `insufficient mana`).
- Added **Max Retries** and **Lockout Time (s)** ImGui slider controls to the **Control** tab under *Spell Failures & Lockout* to allow customizing the retry limit (1 to 10) and lockout duration (5s to 300s).
- Refactored core utility functions, EQ world queries, navigation primitives, target resolution, and spell failure tracking into a separate reusable module `triune_common.lua`.
- Consolidated 46 loose top-level state variables into 4 structured state tables (`pursuit`, `stuckState`, `petState`, `runtime`), improving state encapsulation and preventing main chunk local variable limit issues.
- Fixed `attempt to index global 'myPets' (a nil value)` error in `reconcilePets` by thoroughly updating all remaining bare state variable references across `triune.lua` to access `petState`, `pursuit`, `stuckState`, and `runtime`.
- Added `/ac spellbook` (and `/ac book`) command and an **Open Spellbook** header button in the ImGui interface to launch `triune_spellbook.lua`.

> **TLDR:** Added new Manual Hunter Mode — kills everything on the xtar list then idles until aggro again, great for swarming (auto pet-hold while gathering mobs). Added `/ac` toggle and mode commands. Fixed spell memorization blocking on occupied gem slots. Added player aggro checking, improved combat facing/LoS tracking, enhanced self-defense target switching. Added spell failure limit & lockout with configurable sliders, automatic combat repositioning, XTarget clearing & lowest-HP NPC prioritization. Refactored common utilities into `triune_common.lua`. Added `/ac spellbook` command and ImGui button.

---

## 2026-07-29

- Diagnosed and fixed a Lua parse failure in `triune.lua` caused by too many top-level local variables in the main chunk.
- Refactored the main runtime loop into a local function `runMainLoop()` so the loop's locals no longer count against Lua's 200-local limit.
- Added a new `Manual Hunter` mode and implemented pet-hold behavior via `setManualHunterPetHold()` when entering/exiting that mode, ensuring pets stay held during pause/resume transitions.
- Added level filtering for Hunter and Puller modes with `ctrl.hunter_min_level`, `ctrl.hunter_max_level`, `ctrl.pull_min_level`, and `ctrl.pull_max_level` sliders.
