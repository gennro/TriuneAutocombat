# Triune AutoCombat Change Log

## 2026-08-01

- Added Hunter mode **Combat Radius** anchor feature.
  - New `ctrl.hunter_combat_loc` (x/y/z table) and `ctrl.hunter_combat_radius` (integer, 1–2000) fields in `defaultCtrl()`.
  - New UI sub-section in the Combat tab (Hunter / Pet Tank panel): shows the anchor coordinates or "No anchor set", **Set Anchor** and **Clear Anchor** buttons, and a **Combat Radius** slider (greyed out until an anchor is placed).
  - **Set Anchor** saves the player's current position; if the radius was 0, auto-sets it to 500 as a sensible first-time default.
  - **Clear Anchor** resets both `hunter_combat_loc` and `hunter_combat_radius` to nil/0 and clears any pending `pursuit.wanderLoc`.
  - `findRoamTarget` now post-filters XTarget and NearestSpawn candidates: any mob whose 2D distance from the anchor exceeds `hunter_combat_radius` is rejected, so the player never chases a mob outside the circle.
  - Hunter wander logic is now anchor-bounded: when a combat anchor is active, random wander points are chosen inside the anchor circle (30–90% of the combat radius from the anchor center) rather than near the player's current position.
  - Anchor is cleared automatically on zone-out (matching `camp_loc` behaviour).
  - Both fields persist across log-out/log-in automatically because `ctrl` is serialised whole via `collectEntry()`.


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
