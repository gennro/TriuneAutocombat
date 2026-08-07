# Triune AutoCombat Change Log

## 2026-08-07

- Added `lua/triune_buffbot.lua` standalone MacroQuest ImGui Lua script:
  - Saves current spell gems on script startup/start and restores original spell gems on stop or script exit via `mq.atexit()`.
  - Implemented interactive tell confirmation protocol (`Would you like buffs? Reply 'yes' within 30s`).
  - Added range checking against requesting player spawns.
  - Implemented dropdown combo selectors for 12 buff slots populated with scribed spells from character spellbook.
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
