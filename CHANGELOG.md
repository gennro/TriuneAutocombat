# Triune AutoCombat Change Log

## 2026-09-05

- **AA Special Tab Scan Infinite Loop Prevention (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Terminal Read State Marking (`runtime.readSpecialTabOnce`)**: Fixed an issue where failing to read the Alternate Advancement Special tab (e.g. empty ability list or unsupported window hierarchy) was treated identically to "not yet tried", causing the engine to re-attempt the read on every main-loop frame. Now sets `runtime.specialTabReadDone = true` unconditionally upon attempt completion, returning `{}` and preventing endless retries.
  - **Eliminated Recursive Loop Re-Arming (`runtime.scanPlayerAAs`)**: Removed the fallback `runtime.pendingReadSpecialTab = true` branch inside `scanPlayerAAs()`, which previously re-armed the pending flag every single time a scan ran without finding Special tab abilities.
  - **State-Aware Execution Gate**: Restricted `pendingReadSpecialTab` execution in the main loop to only trigger when `ctrl.auto_spend_aa` is active and `ctrl.paused` is false (out of combat, stationary, and not casting). If auto-spend is disabled or paused, the flag is immediately cleared.
  - **Removed Intrusive/Invalid Keypress & Notification Automation**: Removed invalid `/nomodkey /keypress alt_advancement` and non-existent `AA_Subwindows` notification attempts, ensuring the engine never issues unworkable MacroQuest commands or delays the game thread. Also removed unconditional startup queueing of the flag.
  - **Automated Regression Suite (`Suite 62`)**: Added unit test coverage verifying that failed Special tab reads are permanently marked as complete, subsequent reads return cached results without retrying, and main-loop gating strictly honors pause and feature toggles.

- **In-Game LLM Test Runner & Autonomous QA Agent (`triune_test.lua`, `triune_llm_bridge.py`, `start_bridge.sh`, `start_bridge.bat`, `tests/check_theme_consistency.sh`, `README.md`).**
  - **Standalone ImGui In-Game Test Harness (`triune_test.lua`)**: Created a standalone ImGui testing interface (`/lua run triune_test`) designed to automate and evaluate in-game tests for TriuneAutocombat using local or cloud Large Language Models. Follows strict standalone architecture (no shared module dependencies, identical duplicated dark theme, non-blocking coroutine loop, safe TLO access via `pcall`).
  - **Zero `eqgame.exe` Halting via Asynchronous Python Bridge (`triune_llm_bridge.py`)**: Solved the game-freeze issue where synchronous HTTP or `curl` execution blocks the EverQuest game thread. All network calls, SSL handshakes, token streaming, and API retries run inside an external Python 3 daemon communicating with Lua via high-speed, non-blocking mailbox file IPC (`req.json` / `res.ready`). Game rendering stays at a smooth 60+ FPS with zero hitching.
  - **Multi-Provider LLM Integration**: Built-in support for **LM Studio** (`http://localhost:1234/v1`), **Google Gemini** (via OpenAI-compatible endpoint), **OpenCode / OpenRouter**, and custom endpoints with masked API key persistence in `triune_test_config.lua`.
  - **Telemetry Capture & In-Game Action Dispatcher**: Captures live player stats (HP/mana, combat state, buffs), target stats, group, XTarget, and memorized spell gems into structured JSON context. Parses structured LLM actions (`COMMAND`, `QUERY`, `DELAY`, `ASSERT`, `FINISH`) to execute slash commands, query TLOs, and report `PASS`/`FAIL` assertions with full reasoning in an interactive console log.
  - **Pre-Built Scenarios & Freeform Prompt Testing**: Includes pre-configured test scenarios for combat mode switching, target engagement, and spell gem inspection, alongside a freeform prompt box allowing players to instruct the LLM to run custom in-game QA objectives.
  - **Launcher Scripts & Theme Verification**: Added `start_bridge.sh` and `start_bridge.bat` for one-click daemon startup, and integrated `triune_test.lua` into `tests/check_theme_consistency.sh` to ensure strict theme parity.

- **Alternate Advancement Trailing Whitespace Cleanup & Defensive Sanitization (`triune_data.lua`, `triune.lua`, `triune_buttons.lua`, `tests/test_pure_logic.lua`).**
  - **Database Whitespace Sanitization (`triune_data.lua`)**: Removed accidental trailing spaces from 10 Alternate Advancement entries in the era database (`Destructive Force  `, `Infused by Rage `, `Warlord's Tenacity  `, `Purification  `, `Druzzil's Mystical Familiar  `, `E'ci's Icy Familiar  `, `Ro's Flaming Familiar  `, `Ward of Destruction  `, `Ice Core `, `Stone Core `).
  - **Defensive Name Sanitization & Lookup Resilience (`triune.lua`, `triune_buttons.lua`)**: Added robust whitespace trimming across `hasAA`, `loadout.aas` deserialization and key migration, AA list UI generation, HUD timer monitoring, healing AA scanning, combat action dispatch (`runtime.fireAA`), and button toolbar timer queries. This guarantees that `mq.TLO.Me.AltAbility()` lookups, "Purchased Only" list filtering, and `/alt act` combat execution function reliably even if external data or saved configurations contain trailing spaces.
  - **Automated Whitespace Regression Suite (`test_pure_logic.lua`)**: Added automated regression checks validating that every spell, disc, and AA name across all classes in `triune_data.lua` contains no leading or trailing whitespace, and verified key migration logic.

- **Healing Priority System & Reliability Overhaul (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Dedicated Pre-Combat Healing Priority Engine (`runtime.processHealPriority`)**: Prioritizes reactive healing (Gems, AAs like *Lay on Hands* / *Burst of Life*, Actions like *Mend*, Clickies, Discs) over all navigation, targeting, auto-attack, and offensive actions. When an eligible heal is needed, it fires before entering target acquisition or damage loops.
  - **Movement Interruption for Heals (`runtime.stopMovementForCast`)**: Resolved an issue where characters actively navigating or chasing the Main Assist (`isMoveActive()`) completely suppressed healing. When an ally or self drops below heal threshold, non-Bard characters now immediately halt movement to execute the heal rather than running endlessly while allies die.
  - **Offensive Gate Decoupling (`combatReady`)**: Decoupled healing from offensive combat readiness. Previously, heals were trapped inside `if combatReady`, which prevented casting while approaching a mob, waiting for assist thresholds (e.g. `assist_at = 95%`), or between pulls.
  - **Resting Mana Exemption for Heals (`runtime.castGem`)**: Exempted healing spells from `ctrl.min_mana_pct`. As long as current mana is sufficient to cast the heal, it will not be suppressed by the resting mana floor.
  - **Group Ally Range & Zone Filtering (`runtime.lowestHpAlly`)**: Enhanced ally selection to strictly verify group members are online, in the same zone (`m.Present() == true`, `not m.OtherZone()`, `not m.Offline()`), and within spell range (`distToId <= 200`). Prevents infinite cast failure loops caused by targeting distant or cross-zone group members.
  - **Beneficial Action Range Checks (`runtime.isTargetInRange`)**: Fixed beneficial ability range calculations to default to 100 rather than 15 (melee) for actions without TLO spell definitions, and enforced target range checks before attempting single-target heals on allies.
  - **Gem Dispatch Order Prioritization**: Updated the regular gem evaluation loop to sort and evaluate heal gems ahead of damage, debuff, or DoT gems.
  - **Target/Condition UX Fallback (`runtime.conditionMet`)**: Added automatic target fallback so that setting a friendly target (e.g. `Lowest-HP Ally`, `Tank`) while leaving the default condition on `my HP <=` evaluates both the player and the target ally, preventing failed heals due to UI dropdown mismatch.
  - **Automated Regression Suite (`Suite 61`)**: Added 25 unit test assertions covering heal classification, out-of-zone/distant group member filtering, `min_mana_pct` bypass, emergency HP precedence sorting, and movement interruption.

- **Project Version Bump (v2.01) (`triune.lua`, `triune_updater.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - Synchronized version bump to `2.01` across the main suite (`triune.lua`), the standalone release updater (`triune_updater.lua`), repository documentation (`README.md`), and regression test suites.

- **Hostile Target Self-Healing & Beneficial Spell Target Correction (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Hostile NPC Targeting Retention for Self-Directed Heals (`runtime.castGem`, `runtime.useClickie`, `runtime.fireAA`)**: When casting single-target heals or beneficial spells on oneself (`id == mq.TLO.Me.ID()`) while currently attacking or targeting a hostile NPC (`isHostileTarget(Target.ID())`), Triune no longer changes target to the player. In EverQuest, casting a beneficial spell while targeting a hostile entity automatically redirects the spell onto the player without losing target on the enemy.
  - **Target Lock Override Prevention (`getActiveTargetRequiredCastingId`)**: Updated active casting target resolution to return `nil` instead of `Me.ID()` whenever the player has a hostile NPC targeted during a self-cast heal or buff. This prevents `combatTick`'s mid-cast target lock from dispatching `/target id <Me.ID>`, which previously broke auto-attack melee combat, cleared target from the engaged mob, and left the character idling on itself post-cast.
  - **Context-Aware Beneficial Ally Targeting**: Retained explicit target switching to `Me.ID()` only when the active target is a friendly ally or pet, ensuring self-heals do not accidentally land on group members while idle or between pulls.
  - **Post-Cast Target Restoration Safety**: Ensured post-cast restoration logic preserves the hostile mob target throughout the cast, keeping auto-attack active without interruption.
  - **Automated Regression Prevention (`Suite 46`)**: Added unit test assertions verifying that self-healing while targeting an enemy NPC sets `targetRequired = false`, returns `nil` from `getActiveTargetRequiredCastingId()`, and retains target lock on the hostile mob throughout the cast.
- **Plugin Command Guards for MQ2Map & MQ2FOV (`triune.lua`).**
  - **MQ2Map Plugin Gate (`runtime.mapLoaded`, `runtime.clearMapRadiusVisuals`, `runtime.updateMapRadiusVisuals`)**: Added `runtime.mapLoaded()` probe checking `mq.TLO.Map` and `mq.TLO.Plugin('mq2map')` before executing map drawing commands. If `MQ2Map` is not loaded, Triune gracefully suppresses `/mapfilter` and `/maploc` execution, eliminating `DoCommand - Couldn't parse '/maploc remove'` and `/mapfilter` red chat errors when running without the map plugin.
  - **MQ2FOV Plugin Gate (`runtime.fovLoaded`, `runtime.applyFov`)**: Added `runtime.fovLoaded()` probe checking `mq.TLO.Plugin('mq2fov')` before dispatching `/fov <val>` commands. Prevents `DoCommand - Couldn't parse '/fov 150'` red errors on MacroQuest installations that do not have the legacy FOV plugin loaded.
  - **Settings UI Status Indicators**: Added telemetry notices in the Settings tab indicating when `MQ2Map` or `MQ2FOV` are not loaded, providing clear feedback on feature availability.

- **Spell Gems Auto-Population Button & Slash Command (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Toolbar "Import Bar" Button (`UI.drawGemTabHeader`, `runtime.importCurrentGems`)**: Restored the `Import Bar` toolbar button on the Spell Gems tab right next to `Mem All`. Clicking the button immediately reads all active in-game spell gems from the character's physical gem bar and auto-populates the Spell Gems page with era-accurate class mapping, beneficial/detrimental classification, and sensible default targets and conditions (`target HP <= 95%` for nukes, `missing buff` for buffs, `my HP <= 75%` for heals).
  - **Loadout Defaults & Safety**: Automatically sets standard loadout attributes (`min_xtar = 1`, `max_casts = 0`, `burn_only = false`), wraps MQ TLO access in `pcall` guards, preserves any extra user-configured spell rows beyond the physical gem bar count, and reports populated spell counts to chat.
  - **UI Guidance & Help Integration**: Updated empty-state text in `UI.drawGemList` to guide players to click `+ Add Spell` or `Import Bar`, and documented the `/ac importbar` (aliases `/ac import`, `/ac importgems`) slash command in `triuneCommand` and the Help tab commands table.
  - **Automated Regression Suite (`Suite 49`)**: Added unit tests verifying gem bar simulation, default field population, downtime spell retention, and UI button presence.

- **Melee Distance Slider & Combat Range Adherence Fix (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Eliminated Hardcoded Downward Clamps (`desiredRange`, `maxMeleeDistance`)**: Resolved an issue where configuring the Melee Distance slider (`ctrl.melee_dist`, 5-50) was effectively ignored during combat. `desiredRange()` previously clamped user-specified distance using `math.min(userDist, spawnReach - 2)`, which capped all slider values >= 12 down to 12 on standard-sized NPCs (`spawnReach ≈ 14`), while `maxMeleeDistance()` clamped low distances up to 14, preventing tight melee positioning (< 14).
  - **Prioritized User Distance with Oversized Hitbox Safety**: `desiredRange()` now directly targets `math.max(4, userDist - 2)` and `maxMeleeDistance()` targets `userDist`, accurately honoring slider adjustments (e.g. 20, 25) and tight stick distances (e.g. 6, 8). For genuinely oversized mobs (dragons/giants with `spawnReach > 18 and spawnReach > userDist`), the engine automatically extends distance to `spawnReach - 3` to prevent players from clipping inside large geometry.
  - **Behind & Stick Distance Synchronization (`runtime.getBehindLoc`, `runtime.positionBehindTarget`, `combatTick`)**: Removed hardcoded `math.min(12, ...)` ceiling from `getBehindLoc()` to use `desiredRange(targetId)` directly. Added `lastBehindStickDist` and `lastFrontStickDist` state tracking in `pursuit` so live slider adjustments immediately re-issue `/stick` commands with updated distances during active combat.
  - **Automated Regression Suite (`Suite 60`)**: Added unit tests verifying default (14), extended (25), tight (8), minimum (5), and giant dragon (45) distance calculations, as well as source-level verification that hardcoded clamps are eliminated.

- **Standalone Universal Inventory & Bank Manager (`triune_inv.lua`, `README.md`, `tests/check_theme_consistency.sh`, `tests/test_pure_logic.lua`).**
  - **Comprehensive Multi-Storage Item Scanning (`scanner.scanAll`)**: Implemented a standalone ImGui utility tool that indexes all items across character equipment (worn slots 0–22), personal inventory bags (pack 1–10 containers and sub-slots), bank bags (1–24), shared bank slots (1–4), and active cursor item into a unified, high-speed searchable interface.
  - **Instant Live Search & Multi-Criteria Filtering (`invLogic.matchesFilter`)**: Real-time filtering by item name, location, category (Weapon, Armor, Jewelry, Bag, Consumable, Tradeskill, Spell, Gem, Aug, Misc), and item property flags (Lore, No-Drop, Tradeskill, Clicky) with instant clearing and category badges.
  - **Offline Bank Cache Persistence (`scanner.saveBankCache`, `scanner.loadBankCache`)**: EverQuest only exposes bank TLOs when standing near an active banker. `triune_inv.lua` automatically snapshots and serializes bank contents to character-specific cache files (`triune_inv_bank_<server>_<char>.lua`) when banker windows are accessed, allowing players out in the field to search their bank storage, verify item availability, and identify exact container locations anywhere in Norrath.
  - **Container Grid Visualizer (`UI.drawVisualizer`)**: Added side-by-side visual representations of personal bags and bank storage with capacity indicators, space utilization progress bars, slot grids, and instant click-to-inspect item interaction.
    - **Interactive Item Movement, Pickup, Placement & Drag-and-Drop (`UI.drawVisualizer`, `pendingAction`)**: Implemented complete interactive item manipulation directly within the container visualizer. Left-clicking an occupied slot picks the item up onto the cursor via `/nomodkey /itemnotify <cmd> leftmouseup`, while clicking any destination slot (empty or filled) with an item on the cursor places, swaps, or stacks it into that slot. Integrated native ImGui Drag & Drop (`BeginDragDropSource` / `BeginDragDropTarget` / `AcceptDragDropPayload`) allowing players to drag items between any bag or live bank slots to execute a two-step coroutine-safe move action (`pickup` -> 120ms delay -> `place` -> 100ms delay -> auto-rescan). Added gold slot hover highlighting, a live cursor status banner with an instant `Auto-Inventory Cursor` button, right-click item inspection (`/nomodkey /itemnotify <cmd> inspect`), and context-sensitive tooltips.
    - **Scan Engine Speedup & Static Item Definition Caching (`scanner.scanAll`, `extractItemData`)**: Implemented persistent in-memory item definition caching (`state.itemDefs[itemId]`). Static item metadata (Name, Icon, Category, Stackable, MaxStack, Weight, Value, Clicky, Stats, Flags) is queried once per unique item ID on initial encounter and reused across all duplicate stacks and subsequent scans. This cuts over 95% of C++ TLO boundary crossings on every inventory update, reducing rescan latency from 2-3 seconds down to under 5 milliseconds.
    - **One-Shot Texture Animation Probing & Zero-Overhead Slot Text (`probeIconMode`, `iconFor`, `textWidth`)**: Replaced per-item unprobed animation loops (which executed up to 300,000 failed `pcall(mq.FindTextureAnimation)` queries per second when icons were missing) with a one-shot probe pipeline (`dedicated`, `shared`, or `none`) matching `triune_buttons.lua`. Eliminated per-frame `pcall(ImGui.CalcTextSize)` invocations across all container slots in favor of instant string-length arithmetic.
    - **Table Virtualization & Filter/Sort Memoization (`UI.drawItemsTable`, `state.tableCache`)**: Replaced per-frame table filtering and sorting (which previously sorted 1,000+ items every render frame) with dirty-flag memoization (`state.tableCache`). Integrated `ImGuiListClipper` virtualization so only the ~25 visible rows on screen are submitted to ImGui, restoring buttery-smooth 60+ FPS when opening or browsing large inventories.
    - **EverQuest Item Icons & Badges**: Integrated native MQ texture animations via `'A_DragItem'` (`mq.FindTextureAnimation('A_DragItem')`, `SetTextureCell(id - 500)`, `ImGui.DrawTextureAnimation` and `dl:AddTextureAnimation`) across both inventory bags and bank container grids. Resolved an issue where userdata member checking set `iconId` to 0, ensuring `itemObj.Icon()` is cleanly extracted and displayed. Reconstructed container slots from offline bank cache files so icons render even when away from the banker.
    - **Search Table Icon Integration**: Added 18x18 item icons alongside item names in the main items search table (`UI.drawItemsTable`).
  - **Organization Assistant (`UI.drawOrganizer`, `invLogic.findDuplicateStacks`, `invLogic.findHeaviestItems`)**:
    - **Stack Consolidator**: Detects fragmented partial stacks of the same stackable item scattered across bags or bank, displaying exact locations and merge counts to free up bag slots.
    - **Weight Watcher**: Evaluates and ranks the heaviest items carried in bags to help Monks maintain weight thresholds and avoid encumbrance.
    - **Quick Controls**: Instant toolbar actions to open all bags, close all bags, or auto-inventory items on the cursor.
  - **Thread Safety & MacroQuest Compliance**: Strict separation of ImGui render callbacks and game actions. Item inspections, bag opening (`/itemnotify packX rightmouseup`), item pickups, and auto-inventory commands are queued to `pendingAction` and executed safely on the yieldable coroutine main thread.
  - **ImGui Return Tuple Fix (`ImGui.SliderInt`, `ImGui.InputTextWithHint`)**: Fixed a return tuple inversion in MacroQuest ImGui where `SliderInt` and `InputTextWithHint` return `(newValue, changed)` rather than `(changed, newValue)`. Previously, unpacking into `changed, interval` assigned boolean `false` to `state.autoScanInterval`, causing a runtime error (`attempt to compare boolean with number`) during the background scan timer comparison.
  - **Automated Verification & CI Integration**: Added `triune_inv.lua` to `tests/check_theme_consistency.sh` (zero theme drift vs `triune_buttons.lua`), added pure-logic test suite (`Suite 104`) in `tests/test_pure_logic.lua`, and passed Luacheck and bytecode syntax validation with 0 warnings/errors.

---

## 2026-09-04

- **Project Version Bump (v2.0-beta) (`triune.lua`, `triune_updater.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - Synchronized major version bump to `2.0-beta` across the main suite (`triune.lua`), the standalone release updater (`triune_updater.lua`), repository documentation (`README.md`), and regression test suites.

- **Camera Field of View (/fov) Slider & Automatic Zoning Persistence (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Custom FOV Slider (`50-150 units`)**: Added a `/fov` slider under the Settings tab (`General Settings -> Interface, Overlays & Diagnostics -> Camera & Viewport`) enabling players to customize their camera viewport between 50 and 150 units (EverQuest default: ~75). Adjusting the slider or clicking the dedicated `[Apply]` button immediately issues `/fov <value>` in-game and saves the preference to `triune_loadout.lua`.
  - **Automatic Zoning Re-Application (`runtime.onZoned`, `runtime.pendingFovAt`)**: EverQuest natively resets camera FOV back to default whenever zoning occurs. Triune now automatically tracks the user's desired FOV and re-applies `/fov <value>` immediately upon zone entry and again 1.5 seconds later to ensure the 3D rendering context and camera matrices are properly overridden after zone geometry loads.
  - **Character Startup & Switch Hook (`runtime.onCharacterChanged`, `runtime.loadAll`)**: Enforces the configured FOV automatically when the script starts or when switching characters.
  - **Maintain FOV Checkbox & Slash Commands**:
    - Added `Maintain Field of View (/fov)` checkbox (`ctrl.fov_enabled`, default: `false`, auto-enabled on slider drag or Apply).
    - Added `/ac fov [50-150|on|off]` (aliases `/ac setfov`, `/ac camfov`) chat commands for quick toggling, inspection, or value adjustment.
  - **Automated Test Coverage (`Suite 59`)**: Added 25 unit test assertions covering default ctrl shape, slider value clamping (50-150), slash command parsing, mock execution, and simulated zone re-application.

- **Assist Mode Combat Positioning: Position Behind NPC with Aggro Safety & Toggle (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Automated Flank/Rear Positioning (`runtime.positionBehindTarget`, `combatTick`)**: In Assist mode, characters engaging in melee combat automatically maneuver behind the attacked NPC so only the Main Assist tanks the front arc, completely mitigating frontal ripostes, parries, blocks, and frontal area-of-effect abilities while enabling Rogue backstabs.
  - **Aggro Safety Gate (`runtime.playerHasAggro`)**: If the assistant character pulls aggro or is being attacked directly, behind-positioning is immediately suspended and switches to direct target facing, preventing infinite circling/spinning while tanking. Behind positioning automatically resumes the moment the Main Assist or another group member regains aggro.
  - **MQ2MoveUtils & Geometric Vector Dual Stack (`runtime.isBehindTarget`, `runtime.getBehindLoc`)**:
    - Leverages MQ2MoveUtils (`/stick id <tid> <dist> behind`) when loaded for continuous, smooth orbital rear tracking.
    - Implements an autonomous trigonometry fallback calculating real-time rear coordinates based on the NPC's compass heading vector ($x_{behind} = x_{target} - dist \cdot \sin(\theta_{rad})$, $y_{behind} = y_{target} - dist \cdot \cos(\theta_{rad})$) and dot-product rear-arc detection ($\le 0$ dot product).
    - Extends `moveToward` fallback, `repositionCloser()`, and `handleCantHitFromHere()` with the `behind` modifier for seamless repositioning.
    - Cleans up active stick commands (`/stick off`) whenever targets die or auto-attack disengages.
  - **User Configurable Opt-Out Checkbox & Slash Command**:
    - Added `Position Behind NPC` checkbox (`ctrl.assist_behind`, default: `true`) to the Assist mode controls tab with a descriptive tooltip explaining the MA vs assistant group mechanics.
    - Added live status feedback in the Assist Operations summary (`Behind: Enabled/Disabled`).
    - Added `/ac assistbehind [on|off]` (and `/ac behind [on|off]`) slash command support for convenient macro and chat toggling.
  - **Automated Test Coverage (`Suite 58`)**: Added 14 unit tests validating default and sanitized state initialization, pure geometric rear-arc detection across all 4 cardinal headings ($0^\circ, 90^\circ, 180^\circ, 270^\circ$), rear coordinate calculations, aggro behavior branching, and slash command toggle logic.

- **New Subsystem: Triune Quest Guide & Server-Ground-Truth Quest Database (`triune_quest.lua`, `triune_quest/`, `build_triune_quest.py`, `tests/test_pure_logic.lua`).**
  - **Standalone Interactive Quest Guide Window (`TAC/lua/triune_quest.lua`)**: Introduced a fully standalone, era-aware ImGui quest browser runnable via `/lua run triune_quest`. Styled with the unified dark cyan/blue Triune theme tokens, complete with master-detail split layout, search bar, expansion dropdown, level slider, and hide-completed toggle.
  - **Comprehensive Multi-Expansion Quest Catalog (Classic to Expansion 32)**: Precompiled 2,633 full quest walkthroughs spanning 32 expansions into partitioned, on-demand per-zone Lua packages (`TAC/resources/triune_quest/zones/<shortname>.lua`) and a lightweight search index (`catalog.lua`). Minimizes LuaJIT memory consumption by loading only active zone data on-demand.
  - **Server Ground-Truth Integration (NMS Quests Repository)**: Cross-referenced with the exact server quest repository (`Release-NMS-Quests/`), indexing 6,647 NPCs across 220 zones to verify exact NPC locations, 100% accurate say dialogue prompts, hand-in item IDs, and quest rewards.
  - **Live NPC Spawn Radar & One-Click Navigation**: Detects if the quest giver is currently spawned in the zone via `mq.TLO.Spawn`, calculating real-time distance and cardinal heading. Provides `[Target]` and `[Navigate to NPC]` buttons executing `/nav spawn npc` or `/nav loc`.
  - **Interactive Dialogue Prompts (Click-to-Hail)**: Automatically presents clickable prompt buttons for hails and bracketed responses that target the NPC and issue `/say <prompt>` in the main coroutine loop.
  - **Live Inventory Turn-In Scanner**: Scans character inventory in real-time (`mq.TLO.FindItemCount`), displaying collected vs required item counts (`[OK] 4x Gnoll Fangs (In Bags: 4/4)`) with intuitive color status cues.
  - **Per-Character Quest Completion Persistence**: Saves completed and tracked quests to `mq.configDir/triune_quest_<Server>_<Char>.ini`, allowing easy filtering of completed quests across multiple characters.
  - **Automated Compilation Tool (`TAC/tools/build_triune_quest.py`)**: Built an automated build script to normalize zones, extract coordinates and dialogues, and emit syntax-verified Lua 5.1 safe tables.
  - **Hardened ImGui Input Signatures & Render Stack Protection**: Corrected `InputTextWithHint` return value order (`newSearch, changedSearch`) and checkbox tuple unpacks, guarded `searchTerm` with strict string type-checks in `refreshActiveQuests`, and wrapped inner window rendering in `pcall` within `UI.drawQuestGuide` to ensure `ImGui.End()` and `popTheme()` are unconditionally called on any rendering exception.
  - **Server Era Limiting & Expansion Cap Filtering**: Automatically detects the server's current expansion cap using `mq.TLO.Me.HaveExpansion()` or `triune_data.lua` (`era_expansion`). Added a dedicated `[X] Server Era Limit` toggle and interactive expansion cap selector in the toolbar, dynamically hiding future expansion quests and pruning the expansion dropdown to only show content available on the current server. Preferences are persisted to character INI.
  - **Zone Directory Atlas & Global Quest Search Lookup Page (`UI.drawLookupTab`, `UI.drawBrowseZonesView`, `UI.drawGlobalQuestSearchView`)**:
    - **Multi-Tab Architecture (`QuestGuideMainTabBar`)**: Introduced a tabbed interface hosting the active `Zone Guide` walkthrough tab and the new `Zone & Quest Lookup` exploration tab, with seamless programmatic tab switching via `state.requestTab`.
    - **Norrath Zone Directory Browser (`UI.drawBrowseZonesView`)**: Built an interactive directory indexing all 169 zones across Norrath, sorted alphabetically with instant name/shortname filtering, expansion era markers, and total quest counts. Selecting any zone displays a complete quest list with levels, quest givers, completion status, and a one-click `[Load in Zone Guide]` button that disengages auto-sync to avoid unwanted snapping.
    - **Global Norrath Quest Search (`UI.drawGlobalQuestSearchView`)**: Added a global query engine searching across all 2,633 quests simultaneously by title, NPC name, zone name, or zone shortname, with real-time era cap enforcement and hide-completed filtering.
    - **One-Click Guide Jump**: Clicking `[Guide]` next to any quest in the Lookup tabs immediately sets the target zone, selects the quest walkthrough, loads required turn-in inventory counts, and jumps directly to the Zone Guide tab.
  - **Walkthrough Narrative Cleaner & Rich Formatter (`UI.cleanPreambleAndTags`, `UI.parseWalkthrough`, `UI.drawFormattedWalkthrough`)**:
    - **Preamble & Metadata Stripping**: Automatically removes raw wiki infobox preambles, rating tags, item/NPC bracket codes (`[item=123]`), and trailing footer junk, instantly exposing the real story narrative, instructions, and objectives.
    - **Character Name Personalization**: Replaces Allakhazam generic underscore placeholders (`_____` / `your name`) with the player's active character name (`mq.TLO.Me.CleanName()`), creating an authentic and immersive quest dialog experience.
    - **Semantic Tokenization & Rich Visual Styling**: Parses narratives into structured tokens rendered with distinct UI treatments:
      - **Section Headers** (`◆ Title`): Highlighted in bright gold with subtle separators.
      - **Player Speech** (`💬 You say:`): Highlighted in emerald green with inline `[Say]` buttons to immediately target the NPC and speak the line in-game.
      - **NPC Responses** (`👤 NPC Name says:`): Speaker styled in bright cyan with indented quoted dialogue blocks.
      - **Action Steps & Objectives** (`▶ Step`): Highlighted with action bullets for clear readability.
      - **Location & Directions** (`📍 Directions`): Marked with location pins in cyan.
      - **Faction & Rewards** (`▲ / ▼ Faction`, `★ Reward`): Color-coded green and red with delta badges.
      - **Alerts & Warnings** (`⚠ Note`): Highlighted in warning orange.
    - **View Mode Toggle**: Added `[Formatted View]` vs `[Raw Text]` radio selectors in the walkthrough header, allowing users to toggle between rich formatted presentation and the raw wiki text at any time.
  - **Static Code Analysis Clean Pass (`.luacheckrc`, `triune.lua`, `triune_quest.lua`)**:
    - Registered `ImGuiInputTextFlags` in `.luacheckrc` globals.
    - Cleaned redundant `nil` declarations for `targetNum` and `targetStr` in `runtime.removeAutoAcceptName`.
    - Eliminated unused region width variables (`availX`) and loop indices across `triune_quest.lua`.
    - Achieved **0 warnings / 0 errors across 182 files** in `luacheck TAC/`.
  - **Automated Test Coverage (`Suite 57`)**: Added regression unit tests validating catalog loading, 33 expansion definitions (00 to 32), zone package schema verification, server era filtering logic, zone list directory building and sorting, global quest query filtering, and narrative preamble stripping and tokenization.

- **Code Audit, Logic Bug Fixes, Thread Safety & Headroom Optimization (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Fixed Slash Command `/ac clear lockouts` (`triuneCommand`)**: Corrected an undefined global variable access (`arg == 'lockouts'`) to inspect `args[2]` (`string.lower(args[2]) == 'lockouts'`), ensuring the command correctly clears all active spell lockouts, target backoffs, and mob immunities as documented.
  - **Fixed ImGui Thread Safety in AA Clear Cursor Button (`UI.drawAAsTab`)**: Replaced a direct synchronous `clearCursor()` call (which invoked `mq.delay()` inside the non-yieldable ImGui render callback) with an asynchronous queue via `runtime.pendingCursorClearAt = os.clock()`, eliminating runtime thread crashes and ensuring multi-item cursors drain properly in the main coroutine loop.
  - **Fixed Missing Parameter in Mob Immunity Event Handler (`TriuneImmuneSpell1`)**: Updated the event handler to capture `(_, sp)` and pass `sp` into `onFailureEvent('target immune', sp)`, ensuring the cast tracker records the exact immune spell rather than relying on heuristic fallbacks.
  - **Hardened Zone Transition Triggering (`runMainLoop`, `runtime.onZoned`)**: Added an automated `runtime.onZoned()` dispatch with a 2.0s debounce timestamp when `mq.TLO.Zone.ShortName()` transitions in the main loop, guaranteeing complete state resets (stuck, pursuit, camp, lockouts, pause-on-zone) even if the `"You have entered ..."` chat line was delayed or missed (e.g. during evac, gate, or succor).
  - **Deduplicated Autocombat Start/Stop Control (`runtime.setRunning`, `runtime.triuneToggle`)**: Unified start/pause execution, waypoint synchronization, pet hold management, and plugin status warnings into a single shared helper used across `/ac run`, `/ac pause`, and `/triunerun`.
  - **Eliminated Dead & Unused Code**: Removed unreferenced `UI.drawEmblem()` helper and dead state fields `runtime.lastBreadcrumbAt` and `runtime.lastConReqAt`.
  - **Enhanced Lua 5.1 Main Chunk Register & Local Variable Headroom**: Attached static tables (`CRIT`, `LADDER_CLIMB`, `PET_SCOPE_LIST`, `NAV_CONST`, `ALIAS_CLASS_MAP`) to their respective subsystems and scoped file-level loops (`COMBO_OPTIONS`, `WP`), dropping main-chunk local variable consumption from 188 down to 182 and slots from 172 to 168 (substantially expanding the safe buffer under Lua 5.1's 200 `MAXVARS` limit).
  - **Resolved Shadowed Variable**: Fixed shadowed `local tid` in `combatTick`'s camp pull distance check.
  - **Automated Test Coverage (`Suite 53`)**: Added unit tests in `tests/test_pure_logic.lua` validating command argument parsing for `/ac clear lockouts` and debounce timing for `onZoned`.

- **Auto-Accept Settings Page: Auto Group, Auto Trade, Auto DZAdd & Whitelist Management (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Dedicated Settings Sub-Page (`UI.drawAutoAcceptSettings`, `UI.drawSettingsTab`)**: Restructured the Settings tab with clean sub-navigation tabs (`General Settings` and `Auto-Accept`), providing an organized dedicated interface for social and group automation without cluttering general engine settings.
  - **Automated Request Acceptance Toggles**:
    - `Auto-Accept Group Invites` (`ctrl.auto_group`): Automatically accepts incoming group invites via `/invite` and dialog confirmation whenever received from an authorized player.
    - `Auto-Accept Trades` (`ctrl.auto_trade`): Automatically clicks the Trade button (`TRDW_Trade_Button`) when the trading partner has marked trade ready and is authorized.
    - `Auto-Accept Dynamic Zone / Expedition Invites (DZAdd)` (`ctrl.auto_dzadd`): Automatically accepts dynamic zone invites (`/dzaccept`), task adds, and expedition confirmation prompts from authorized players.
  - **Flexible Authorization Filtering Rules**:
    - `Accept from Anyone` (`ctrl.auto_accept_anyone`): Unconditionally accepts eligible group, trade, and expedition requests from any player.
    - `Always accept from Group Members` (`ctrl.auto_accept_group`): Automatically authorizes requests from characters currently in your group.
    - `Accept from all Guild Members` (`ctrl.auto_accept_guild`): Automatically authorizes requests from any player in the same guild as your character (`Me.Guild()`).
  - **Player Whitelist Management with Player IDs & Dedicated Removal (`ctrl.auto_accept_names`, `runtime.addAutoAcceptName`, `runtime.removeAutoAcceptName`)**:
    - **Dual Identification (Player Name & Player ID)**: Structured whitelist entries store both character name and numeric Player ID (`{ name = ..., id = ... }`), allowing resilient matching against either player names or spawn IDs with backwards compatibility for legacy string entries.
    - **Interactive Input & Target Resolution**: Text input field accepting player names or IDs with Enter key submission support, plus a one-click `+ Add Target` button that extracts both clean name and spawn ID from the targeted player character (`mq.TLO.Target`).
    - **Dedicated Remove Button**: Added a dedicated `[Remove]` button in the top toolbar to instantly remove the selected player or the targeted player from the whitelist, alongside individual `[Remove]` action buttons on each row of the whitelist table and a `[Clear All]` button.
    - **Structured Whitelist Table (`autoAcceptWhitelistTable`)**: Scrollable 3-column table displaying Player Name (selectable), Player ID, and per-row `[Remove]` button with selected player status badge.
    - Alphabetically sorted, case-insensitive whitelist with duplicate prevention by name and ID.
  - **Continuous Pulse & Event Integration (`runMainLoop`, `runtime.checkAutoAccept`, `mq.event`)**:
    - Integrated throttled background evaluation in `runMainLoop` to monitor `Me.Invited()`, `Window('TradeWnd')` (matching target ID or name), and `Window('ConfirmationDialogBox')`.
    - Added reactive chat event listeners (`TriuneAutoGroupInvite1/2`, `TriuneAutoDZInvite1/2/3`) for immediate instant response to invites.
  - **Unit Test Coverage (`Suite 55`)**: Added unit tests verifying whitelist additions with Player IDs, case-insensitive duplicate prevention, alphabetical sorting, removal by ID/name/entry, clearing, and multi-rule authorization evaluation (anyone, group, guild, whitelist).

- **Multi-Target Extended Target Engine for 'All Enemies' Option (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Multi-Target Cast Distribution (`runtime.resolveAllEnemiesTargetId`)**: Refactored the `E: All Enemies` target selector across Spell Gems, Clickies, Combat Actions, AAs, and Disciplines so that it actively iterates and distributes casts across all hostile NPC candidates on your Extended Target (XTarget) list.
  - **Debuff & DoT Multi-Targeting**: Spells with a duration (DoTs, debuffs, snares, mes) evaluate whether each mob already has the effect active (`runtime.isNpcSpellActive`, checking both MQ target buffs and tracked applied durations). Triune sequentially casts the effect on Mob 1, Mob 2, Mob 3, etc., and cleanly yields to subsequent gems/actions once all mobs on XTarget have the effect active.
  - **Direct Damage & Nuke Round-Robin**: Spells with zero duration or unlimited casts round-robin evenly across all living enemies on XTarget based on fewest cast counts and least-recent cast timestamps.
  - **Max Casts Enforcement per Mob**: Honors `max_casts` on a per-mob basis across XTarget, casting up to the configured limit on each enemy before skipping that target.
  - **Lockout & Resist Resiliency**: Automatically skips mobs that are locked out or immune via `castTracker`, targeting other eligible mobs on XTarget without halting the rotation.
  - **Applied Spell & Cast Tracking Lifecycle**: Added `runtime.npcSpellApplied` and `runtime.npcSpellLastCast` tracking in `castGem` and `useClickie`, clearing applied timers on fizzles, interrupts, resists, and non-stacking debuff conflicts in `castTracker.reportResult`, and pruning dead mobs during combat ticks, death, and zone transitions.
  - **Unit Test Coverage (`Suite 56`)**: Added comprehensive tests in `tests/test_pure_logic.lua` validating sequential DoT distribution across XTarget, yielding when all mobs are DoTed, recast upon expiration, round-robin direct damage nuking, `max_casts` gating, and lockout skipping.

- **Target Filters & Cast Conditions Reference in Help Tab (`triune.lua`).**
  - **In-Game Reference Section (`UI.drawHelpTab`)**: Added a dedicated `Spell & Ability Target Filters` collapsing header to the Help tab, providing comprehensive reference documentation directly in the UI.
  - **Target Resolution Guide (`##HelpTargetTable`)**: Details behavior for all 11 target selectors across Enemy options (`E: All Enemies`, `E: Current Target`, `E: Assist Target`, `E: Nearest Add`, `E: Unmezzed Add`) and Friendly options (`F: Myself`, `F: Main Assist`, `F: Tank`, `F: Lowest-HP Ally`, `F: Whole Group`, `F: Pet`).
  - **Cast Conditions Guide (`##HelpWhenTable`)**: Explains activation criteria and usage for all 16 "When" conditions (HP thresholds, mana checks, buff/debuff presence, cure counter checks, loose adds, aggro triggers, and continuous twisting).

---

## 2026-09-03

- **Configurable Automatic Script Pause on Zoning (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **New Setting & Checkbox in Settings (`ctrl.pause_on_zone`)**: Added a `Pause Autocombat When Zoning` checkbox in the Settings tab under *Interface, Overlays & Diagnostics* (enabled by default). Allows players to toggle whether the script automatically pauses when zoning or seamlessly continues running in the new zone.
  - **Zone Transition Handling (`runtime.onZoned`)**: When `ctrl.pause_on_zone` is enabled (default), zoning halts execution and sets `ctrl.running = false` as before. When disabled, autocombat remains running across zone lines while still performing essential zone transition maintenance (stopping stale movement, clearing prior-zone detours, breadcrumbs, unreachable IDs, and target locks).
  - **New Slash Command `/ac pausezone [on|off]`**: Added `/ac pausezone` (aliases: `/ac zonepause`, `/ac pauseonzone`) to quickly query or toggle the pause-on-zoning behavior via chat or macros.
  - **Unit Test Coverage (`Suite 53`)**: Added unit tests verifying `defaultCtrl` initialization, `sanitizeModeConfig` default and preservation, `runtime.onZoned` execution with pause enabled/disabled, and slash command toggling.

- **Pet Target Live Tracking & Status Page Display (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Fixed Pet Target Resolution (`getPetSpawnInfo`)**: MacroQuest general `Spawn` datatypes do not expose a `.Target` member, which previously caused `s.Target` to evaluate to `nil` and left the pet target permanently displaying `Target: None`. Implemented a multi-tier pet target resolution chain inspecting `mq.TLO.Me.Pet.Target`, `mq.TLO.Me.Pet.Following` (for following hostile NPCs), targeted pet `Target.TargetOfTarget`, `Spawn.TargetOfTarget`, and active combat command fallbacks (`petState.lastCmdTargetId` and `Me.Pet.Combat()`).
  - **Dead & Corpse Target Rejection**: Added verification ensuring pet target state immediately clears to `'None'` if the engaged target dies or becomes a corpse, preventing stale target displays after combat.
  - **Status Tab Target Telemetry & One-Click Target Button (`UI.drawStatusTab`)**: Enhanced the Status tab Pet card to display live target name, health percentage, and distance in `ARC` color (e.g., `Target: a fire goblin (65%) (15.2ft)`), alongside a convenient `[Target]` button to directly target the pet's engaged foe with `/target id <id>`. Idle or held pets cleanly display `Target: None` in `MUTED` gray.
  - **Unit Test Coverage (`Suite 52`)**: Added automated unit tests verifying primary pet target resolution, following fallbacks, secondary pet target-of-target queries, combat command fallbacks, hold-state suppression, and dead target rejection.

- **Pet Buff Detection & Redundant Buff Recast Prevention (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Fixed Pet Buff Query Routing (`runtime.isPetBuffActive`, `buffActive`)**: Previously, `buffActive` checked pets as regular `mq.TLO.Spawn(id)` objects using `hasNamedBuff`, which only inspected `CachedBuffCount` (usually 0 without NetBots/CachedBuffs plugins), causing `buffActive` to falsely return `false` and repeatedly cast buffs on pets that already had them. Added a dedicated `runtime.isPetBuffActive` evaluator that directly queries `mq.TLO.Me.Pet.Buff(1..30)` slots, slot durations (`mq.TLO.Me.Pet.BuffDuration`), and direct name lookups.
  - **Spell Stacking Safeguard (`Spell.StacksPet`)**: Added `mq.TLO.Spell(name).StacksPet()` checks so that if a beneficial spell cannot stack on the pet (e.g., higher tier or conflicting buffs active), Triune considers the buff active and avoids repeated failed casts.
  - **Secondary & Targeted Pet Buff Support**: Added fallback inspection through `Target.Buff` when the pet is targeted, `Spawn.CachedBuff` / `StacksSpawn`, and the 300-second persistent `petState.cachedPetBuffs` cache.
  - **Live Buff Recording (`runtime.recordPetBuff`)**: Updated `castGem` and `castClicky` to record successfully cast beneficial spells and durations directly into `petState.cachedPetBuffs` for immediate reflection across the rotation.
  - **Threshold & Refresh Window Support (`minSec`)**: Integrated `ctrl.buff_refresh_sec` into pet buff checks so pets are only rebuffed when existing buffs are actually missing or expiring within the configured threshold.
  - **Invalid & Dead Target Safeguard (`conditionMet`)**: Added nil and alive checks before checking missing buffs, preventing spurious buff triggers when targets are invalid or dead.
  - **Unit Test Coverage (`Suite 52`)**: Added unit tests covering slot matching, case-insensitivity, refresh threshold timing, `StacksPet` non-stacking detection, secondary pet caching, and multi-pet targeting resolution.

- **Fix Phantom Auto-Attack Activation & Active Combat Disengagement (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Fixed Target Engagement False Positive (`runtime.targetIsEngaged`)**: Removed an unconditional fallback where `ctrl.mode == 'Assist' or ctrl.mode == 'Manual' or ctrl.mode == 'Puller'` blindly returned `true` for any hostile NPC in the zone. `targetIsEngaged` now strictly validates whether the mob is on XTarget, damaged (<100% HP), targeting the character/group, or actively targeted by an attacking Main Assist.
  - **Hardened Self-Defense Distance Gating (`runtime.findSelfDefenseTarget`)**: Eliminated a relaxed `d <= 35` proximity fallback that previously caused unaggressive nearby mobs to be falsely flagged as attackers and engaged in self-defense.
  - **Restricted Watchdog Combat Stall Trigger (`runtime.checkCombatStall`)**: Added strict target verification for Assist mode, ensuring the combat stall watchdog only activates `/attack on` if the target is genuinely the Main Assist's target or active self-defense target.
  - **Manual Mode Engagement Safeguard (`combatTick`)**: In Manual mode, characters will no longer automatically engage or turn on attack merely from targeting an NPC unless the mob is on XTarget or the character is already in combat.
  - **Clean Auto-Attack Disengagement (`combatTick`)**: Added automatic `/attack off` and `/autofire off` execution whenever combat concludes, when the target dies, or when not actively engaged on an enemy.
  - **Unit Test Coverage**: Added comprehensive test cases in Suite 51 validating engaged target state detection and auto-attack shutoff logic.

- **Configurable Chase Distance Slider & Backline Auto-Follow (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Prominent Chase Distance Slider (`ctrl.chase_dist`)**: Promoted the Chase Distance slider (`ctrl.chase_dist`, 5 to 100 ft, default 15 ft) to be permanently visible in the Assist mode Control tab alongside `Assist At %` and `Max XTarget Chase Range`, allowing players to easily configure how far to stay back from the Main Assist.
  - **Backline Auto-Follow Support (`combatTick`)**: Added a `Follow MA in Backline` toggle (`ctrl.chase`) for Backline submode so backline assistants automatically follow the Main Assist at the configured Chase Distance while idle or navigating between pulls, and hold position at range during combat without closing into melee.
  - **New Slash Command `/ac chasedist [5-100]`**: Added `/ac chasedist` (aliases: `/ac chase`, `/ac followdist`) to configure following distance or toggle auto-follow from chat or keybinds.
  - **Unit Test Coverage**: Added test assertions in Suite 51 verifying UI element presence and slash command handling for `chasedist`.

- **Assist Mode Strict Target Locking & Self-Defense When Attacked (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Strict Main Assist Target Locking (`combatTick`)**: When the Main Assist has an active engaged target within range, the assistant now exclusively attacks that target and will never deviate, switch targets, or peel off, even if adds attack the assistant. Removed Assist mode from generic `checkAggroSwitch` calls to eliminate target-thrashing between MA targets and secondary adds.
  - **Self-Defense When Attacked (`runtime.findSelfDefenseTarget`, `ctrl.assist_self_defense`)**: If the Main Assist has no active engaged target (e.g. out of combat, medding, pulling, or moving) and the assistant gets attacked by an enemy, the assistant will automatically fight back and defend itself. Scans XTarget hate lists, aggro holders, and melee attackers within `ctrl.xtar_nav_dist`.
  - **Instant MA Re-Engagement Priority**: The exact instant the Main Assist acquires and engages a target, the assistant immediately drops self-defense, acquires the MA's target, and focuses 100% on assisting.
  - **UI Checkbox Control (`UI.drawControlTab`)**: Added a `Self-Defense When Attacked` checkbox (`ctrl.assist_self_defense`, enabled by default) in Assist mode settings, allowing players to toggle whether characters fight back or strictly hold position/follow when MA has no target.
  - **Spells & Abilities Assist Fallback (`runtime.resolveTargetId`)**: Updated `resolveTargetId('Assist Target')` to fall back to the active self-defense target when MA has no target, enabling full rotation execution during self-defense.
  - **New Slash Command `/ac selfdefense [on|off]`**: Added `/ac selfdefense` (aliases: `/ac assistdefend`, `/ac defend`) to quickly toggle or query the self-defense state from macros or hotkeys.
  - **Unit Test Suite Expansion (`Suite 51`)**: Added test cases verifying strict MA target lock when MA is engaged with adds present, self-defense engagement when MA has no target, self-defense suppression when disabled, and instant dynamic switching back to MA targets.
  - **Comprehensive Hover Tooltips Added**: Added explanatory hover tooltips for all Assist mode controls (`Assist At %`, `Max XTarget Chase Range`, `Self-Defense When Attacked`, `Chase MA`, `Chase Range`, `Set Here`, `Clear Camp`, `+ Add Target`, `Remove`, and `##maSelectCombo`), as well as primary mode/submode combos and camp anchor controls across all modes.

- **XTarget Combat Radius Limit for Assist Mode (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Max XTarget Chase Range Control (`ctrl.xtar_nav_dist`)**: Added an interactive `Max XTarget Chase Range` slider (25 to 300 units, default 150) to the Assist mode Control tab (`UI.drawControlTab`), mirroring the capability found in Manual and Puller modes.
  - **Assist Navigation Distance Gating (`combatTick`)**: In Assist mode (`Chase`, `Camp`, and `Backline` submodes), characters will now only navigate toward and engage the Main Assist's target or XTarget enemies within `ctrl.xtar_nav_dist`. If the target is beyond this range, `closingOnMob` remains false and characters hold camp (`idleReturn()`) or stick with the MA (`chaseMA()`), preventing them from running across the zone to engage distant mobs.
  - **Engaged Spawn & Assist Discovery Limiting (`runtime.anyNearbyEngagedNpc`, `runtime.maTargetId`)**: Updated `runtime.anyNearbyEngagedNpc` and `runtime.maTargetId` to respect `ctrl.xtar_nav_dist`, checking for live XTargets and engaged NPCs strictly within the configured radius before issuing `/assist` or accepting targets.
  - **Aggro Switching Range Clamping (`runtime.checkAggroSwitch`)**: Extended `isHunterMode` check in `checkAggroSwitch` to include Assist mode, bounding secondary aggro swaps to `ctrl.xtar_nav_dist`.
  - **Status Tab & Map Overlay Integration**: Displayed `Max XTar Chase: <N> ft` in the Assist mode operations card on the Status tab and updated the 2D map overlay to visually reflect the configured radius around the camp.
  - **New Slash Command `/ac xtardist [25-300]`**: Added slash command with aliases `/ac xtar` and `/ac xtarrange` to configure or query the XTarget chase radius from chat or hotkeys.
  - **Unit Test Coverage**: Added test coverage in Suite 51 verifying boundary checks, far-mob gating, and UI element presence.

- **Assist Mode Player ID Dropdown Selection & Target Management (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Dynamic Group Member Dropdown (`runtime.getAssistCandidates`)**: Replaced manual text input (`MA Name`) with an interactive `ImGui.Combo` dropdown displaying character names alongside their actual player/spawn IDs (e.g. `[Leader] TankBob [WAR] (ID: 101)` or `[Group] HealJane [CLR] (ID: 102)`), dynamically populated based on real-time group membership.
  - **Player ID-Driven Assist Targeting (`runtime.maPcId`, `ctrl.ma_id`)**: Assist targeting now directly references and resolves player Spawn IDs (`ctrl.ma_id`) with live validation (`isSpawnAlive`), automatically falling back to name resolution to refresh and cache the new Spawn ID whenever characters re-zone or re-log.
  - **One-Click Target Addition (`runtime.addCustomAssistTarget`)**: Added an `[+ Add Target]` button requiring the player to target any valid PC in game to immediately add them to the persistent custom assist list (`ctrl.custom_ma_list`) and select them as Main Assist. Includes validation checks guarding against targeting NPCs, pets, or oneself.
  - **Custom Assist Removal (`runtime.removeCustomAssist`)**: Added a contextual `[Remove]` button enabled whenever a custom assist candidate or PC target is selected, cleanly removing them from the dropdown and resetting selection if active.
  - **Live Main Assist Target Display (`runtime.getMaTargetInfo`)**: Added real-time Main Assist target telemetry to both the Status tab (within the Target card and Mode Operations panel) and Compact HUD mode. Displays the MA's name and ID alongside their active target's name, class, level, ID, HP percentage, and distance, plus a quick `[Target]` button to acquire the MA target in one click.
  - **New `/ac ma` Slash Command**: Added `/ac ma [target|clear|<name>|<id>]` command for quick keybind and macro-driven assist assignment.
  - **Unit Test Suite (`Suite 51`)**: Added automated unit tests covering default initialization, candidate generator formatting, duplicate filtering, target addition/rejection validations, removal logic, and zoning Spawn ID re-acquisition.

- **Dynamic AA Special Tab Discovery & Name Reading (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Eliminated Hardcoded Special AA List & ID Ranges**: Completely removed the static 60+ entry `SPECIAL_AAS` catalog and the `specialRanges` database crawler (Veteran Rewards 4000..4060, Glyphs 5000..5150, Fireworks 17780..17800) that previously injected unearned or phantom abilities into the Auto AA page.
  - **Character Ownership Enforcement (`runtime.recordScannedAA`)**: Updated ability recording to strictly verify `Me.AltAbility` ownership or direct presence in the character's in-game `AAWindow`, preventing the global `AltAbility` database crawler from populating abilities belonging to other classes.
  - **Native Window State Control**: Replaced non-functional `/window open` and `/window close` commands with valid `Window('AAWindow').DoOpen()` / `DoClose()`, `/windowstate AAWindow open/close`, and keypress actions to guarantee `AAWindow` opens, activates Tab 4 (Special), and closes cleanly.
  - **One-Time In-Game Special Tab Reader (`runtime.readSpecialTabOnce`, `runtime.readSpecialTabNamesFromUI`)**: Automatically and dynamically inspects the character's Special tab listbox (`AAW_SpecialList`, `AA_SpecialList`, `SpecialList`, etc.) in `AAWindow` once on startup or character load. Extracts all populated ability names into `runtime.specialTabAAs` and restores the window's prior state.
  - **Opportunistic & On-Demand Sync**: Opportunistically reads the Special tab whenever `AAWindow` is opened by the player or during automated training workflows, and allows on-demand re-reading via the `↻ Refresh` button or `/ac aascan`.

- **Guaranteed Movement Cessation During Spell Casting (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Pre-Cast Movement Halting (`runtime.stopMovementForCast`)**: Implemented a comprehensive movement stopping routine before casting non-bard spells and cast-time clickies/AAs. Explicitly executes `/nav stop`, pauses MQ2Stick via `/stick pause` (preserving target stick configuration so it can unpause cleanly upon cast completion), stops MQ2MoveTo via `/moveto off`, releases native movement keys (`forward`, `back`, `strafe_left`, `strafe_right`), and yields up to 200ms for momentum to stop.
  - **Moving State Verification Before Cast**: Guarded `runtime.castGem`, `runtime.useClickie`, and `runtime.fireAA` to abort initiating cast-time spells if `Me.Moving()` is still active, preventing wasted cooldowns, fizzles, and false lockout tracking when sliding down terrain or coasting. Added `canCastMove` gating in `combatTick` so gems and clickies do not attempt casting mid-motion.
  - **Continuous Movement Suppression While Actively Casting**: In `combatTick`, if `isCastingOrStarting()` is true for non-bards, actively suppresses and halts any stray movement from MQ2Nav, MQ2Stick, MQ2MoveTo, or keyboard inputs every tick until the spell finish or interrupt transition occurs.
  - **Spell Pull Movement Halting**: Ensured Camp Puller mode and Hunt mode explicitly call `stopMoving()` when arriving within spell engagement range for `pullStyle == 'Spell'` prior to firing the initial pull spell.
  - **Pure-Logic Unit Test Suite (`Suite 50`)**: Added automated unit tests verifying Bard movement exemption, MQ2Nav stopping with pursuit reset, MQ2Stick pausing, and keyboard release behavior.

- **Fix AA Window Automation & Tab-Aware In-Game Training (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Recursive Child Window Traversal (`runtime.findChildRecursive`)**: Replaced shallow child lookups with a recursive traversal utility that inspects `.FirstChild` and `.Next` across arbitrary container hierarchies (`AAWindow` -> `AAW_Subwindows` -> `AAW_SpecialPage` -> `AAW_SpecialList`), guaranteeing controls are found regardless of custom UI skins.
  - **Tab-Aware Preparation Step (`runtime.processAATrainWorkflow`)**: Added a dedicated `prepare_tab` phase that identifies the target tab (General=1, Archetype=2, Class=3, Special=4) and activates it via `/notify AAWindow AAW_Subwindows tabselect <N>` and `sub.SetCurrentTab(<N>)` before attempting list selection, resolving an issue where Special tab abilities (such as *Alternately Advanced Fireworks*) were sent selection events while Tab 1 was still active.
  - **Accurate Control Names & Notification Targets**: Corrected UI control names to match the EverQuest client's `EQUI_AAWindow.xml` definitions (`AAW_TrainButton`, `AAW_SpecialList`, `AAW_ArchList`), and updated button clicking to trigger both `btn.LeftMouseUp()` and `/notify AAWindow AAW_TrainButton leftmouseup`.
  - **Fuzzy Target Matching & Guaranteed Fallback**: Implemented sanitized string comparison to seamlessly match typos and variations (e.g. `Alternatly ADvanced fireworks` vs `Alternately Advanced Fireworks`), and added automatic `/alt buy <ID>` secondary execution to ensure abilities train successfully across all server configurations.

- **Quick Start Guide & README Documentation Overhaul (`README.md`).**
  - **Comprehensive Quick Start Guide**: Updated setup steps to guide users through downloading the latest RoF2 MacroQuest release from GitHub releases, downloading the latest Triune AutoCombat full release, extracting the `TAC` contents directly into the root MacroQuest folder (merging `lua/`, `config/`, and `resources/`), launching MacroQuest, and logging into the EMU server.
  - **Tab Flow & Loadouts Documentation**: Documented the natural 12-tab interface progression (`Status -> Control -> Pets -> Spell Gems -> Abilities -> AAs -> Disciplines -> Clickies -> Auto AA -> Cooldowns -> Settings -> Help`), including the Spell Gems `Mem All` button with queue count badging and the Auto AA progression browser.
  - **Complete Bonus Tools & Slash Commands Index**: Added the standalone `triune_buttons.lua` hot button toolbar to the bonus tools table, added missing slash commands (`/ac huntz`, `/ac zplane`, `/ac aaname`, `/lua run triune_buttons`), and updated the project file structure to include `triune_buttons.lua` and `TAC/resources/` (ItemDB, Zones.ini, and MQ2Nav meshes).
- **Window Title & Header Layout Modernization (`triune.lua`).**
  - **Dynamic Title Bar Header**: Moved character name, TAC version, and detected gestalt trio classes directly into the primary window title bar (`TAC v<VERSION> - <PlayerName> (<Classes>)###triune`), freeing up interior window vertical space and keeping character context visible across all tab views.
  - **Compact Status Page Layout**: Integrated the Session Tracker (duration, AA/hr, Plat/hr, and one-click `Reset` button) directly into a streamlined, single-line overview header (`Overview | <Time> | AA/hr: X (+Y) | Plat/hr: Z (+W) [Reset]`) with rich hover tooltips, eliminating the redundant second table and saving over 75 pixels of vertical space so combat targets and vitals are immediately visible.
  - **Clean Top-Level Toolbar**: The main window content now opens cleanly with the primary quick-action tool buttons (`Open Spellbook`, `Map`, `DPS Parser`, `Compact Mode`, `Cursor Manager`, `Cooldowns`) as the top line.

---

## 2026-09-02

- **Auto AA Tab Overhaul & Priority-Based AA Training Engine (`triune.lua`, `README.md`, `tests/test_pure_logic.lua`).**
  - **Comprehensive Character AA Scanner (`runtime.scanPlayerAAs`)**: Scans all available character Alternate Advancement abilities by crawling in-game `AAWindow` listboxes, class combat abilities from `DATA.aas`, common archetype/general Norrath AAs, and the MacroQuest `AltAbility` database index (`mq.TLO.AltAbility(i)`). Dynamically records ability names, current ranks, max ranks, next rank point costs, trainability, and points spent.
  - **Real-Time Filtering & Multi-Criteria Sorting (`runtime.getFilteredSortedAAs`)**:
    - **Search Box**: Instant, case-insensitive substring search with one-click clear button.
    - **Multi-Criteria Sorting**: Sort by **Name** (A-Z / Z-A), **Cost** (cheapest first / highest cost first, with fully trained abilities cleanly placed at the end), or **Fully Trained** status (in-progress/untrained first vs maxed first). Built using strict comparator logic to prevent Lua order function errors.
    - **View Filters**: Instant toggle checkboxes to **Hide Maxed** abilities and show **Prioritized Only** abilities.
  - **Prioritized Auto-Purchase Engine (`runtime.checkAutoSpendAA`)**:
    - Per-ability priority checkboxes `[x]` to queue specific abilities for automatic training.
    - Evaluates unspent AA points against prioritized ability costs (`unspent >= cost`).
    - Configurable **Priority Order** combo: **Cheapest First** (trains the lowest-cost prioritized ability available) vs **Alphabetical** (processes prioritized abilities in alphabetical order).
    - Safely executes training via in-game AA window automation (`runtime.startAATrainWorkflow`), opening the window, navigating tabs/search, selecting the ability, and triggering the Train button.
    - Preserves fallback cap protection (fireworks) when the unspent pool hits the configured cap threshold (default: 100 AA).
  - **Interactive AA Progression Table (`UI.drawAutoAATab`)**:
    - Built using Dear ImGui tables (`##AutoAABrowserTable`) with columns for Priority Checkbox, Ability Name (with hover tooltip for rank/cost/spent stats), Current Rank (`X / Y` or green `MAX`), Cost (green when affordable, yellow when unaffordable, `-` when maxed), Training Status (`Can Train`, `Need X AA`, `Max Rank`), and instant manual `Train` action button.
    - Added quick-action buttons: **Refresh AAs** and **Clear Priorities**.
    - Retained full Fireworks auto-summoning and inventory dumping controls in a neat, expandable collapsing header.
  - **Special Tab AA Discovery & Window Inspection (`runtime.scanPlayerAAs`, `runtime.findAAInWindowLists`)**:
    - Expanded scanning to fully inspect Special tab listboxes (`AAW_SpecialList`, `AA_SpecialList`, `SpecialList`, `Special_List`, `AAW_SpecList`, `AAW_SpecialTabPage`), including subwindows and tab page containers.
    - Added comprehensive discovery of Veteran Rewards (Lesson of the Devoted, Infusion of the Faithful, Expedient Recovery, etc.), Glyphs (Destruction, Frantic Fertility, Arcane Secrets, etc.), and Special utilities/spenders.
    - Updated TLO crawling to probe special ID ranges (`4000..4060`, `5000..5150`, `17780..17800`) without terminating prematurely on nil gaps.
  - **Compact, High-Density 2-Row Header Layout (`UI.drawAutoAATab`)**:
    - Cleaned up and compacted the top of the Auto AA page by eliminating verbose multi-line text banners and spreading separators.
    - Row 1 combines live AA pool status (`Unspent: XX AA (Spent: YY)`), master Auto-Spend checkbox, Priority Buy Order combo, Cap threshold slider, `↻ Refresh` button, and `Clear Prios` button.
    - Row 2 provides real-time search input, one-click `X` clear, sort criteria combo, `▲ Asc / ▼ Desc` toggle, `Hide Maxed` checkbox, `Prio Only` checkbox, and live count badge `(X listed | Y prio)`.
  - **Dynamic Full-Window Table Sizing (`UI.drawAutoAATab`)**:
    - Replaced fixed child window dimensions (`290px`) with dynamic stretch sizing (`ImGui.BeginChild(..., 0, 0, false, ...)`).
    - Enabled `ImGuiTableFlags.SizingStretchProp` so the table and its columns expand and contract smoothly in both width and height to fill any resized window size.
  - **Automated Post-Purchase Refresh & Real-Time Delta Detection (`UI.drawAutoAATab`, `runtime.processAATrainWorkflow`)**:
    - Automatically triggers an immediate re-scan (`runtime.scanPlayerAAs(true)`) upon completing an in-game AA training workflow, plus a scheduled 1.2s follow-up scan to catch delayed server confirmation packets.
    - Added real-time client state delta monitoring for `Me.AAPointsSpent()` and `Me.AAPoints()` in both the UI render pass and background engine loop. Any AA purchase (via Triune automation, manual UI click, the EQ AA window, or slash command) is detected instantly to update ranks, costs, and affordabilities.
    - Registered chat event handlers (`TriuneAAPurchased1/2/3`) for in-game purchase, improvement, and mastery notifications to trigger instant table updates.
  - **New Slash Commands**: Added `/ac aascan` to force a full re-scan of character AAs, and `/ac aaprio <name>` to toggle priority status for any AA directly via chat.

- **Spell Gems "Mem All" Toolbar Button & Slash Command (`triune.lua`, `README.md`).**
  - **Mem All Toolbar Button**: Added a dedicated `Mem All` button to `UI.drawGemTabHeader()` right next to `+ Add Spell`. When clicked, it evaluates all physical gem slots (1 to 12) and queues any slot that is empty or memorized with the wrong spell back to its designated priority spell. Dynamically displays the pending queue count (e.g. `Mem All (3)`).
  - **Sequential Numerical Draining**: Updated the background queue drain loop in the main script to process slots in strict numerical order (1..12) and respect active aggro threats before opening the spellbook.
  - **Slash Command Integration**: Added `/ac memall` (aliases: `/ac mem`, `/ac remem`) to queue all missing or mismatched priority spells directly via chat command.

- **Out-of-Combat Priority Spell Rememming & Aggro Threat Safety (`triune.lua`, `tests/test_pure_logic.lua`).**
  - **Remem Priority Spells When Lower Priority Spells Not Needed**: Updated `runtime.processDowntimeBuffing()` so that when not in combat, any gem slot whose priority combat spell (the first configured spell in the loadout list for that gem, e.g. a Lifetap for G12) is not currently memorized will be automatically rememorized back once lower-priority spells (e.g. downtime buffs) are completed or not currently needed.
  - **Decouple Downtime Processing from `combatReady`**: Moved out-of-combat spell swapping and priority restoration outside the `if combatReady` gate in `combatTick()`. Downtime spell restoration now runs reliably whenever out of combat even if a peaceful, distant, or unengaged NPC is targeted.
  - **Aggro Threat Detection Precision**: Refined `runtime.hasDowntimeAggroThreat()` to verify real combat states (`Me.Combat()`, `CombatState() == 'COMBAT'`, active haters on XTarget, or target aggro `PctAggro > 0`) instead of incorrectly treating any selected hostile-type mob in the zone as active combat.

- **Status Page Layout & Collapsing State Persistence, Mode Indicator on Action Bar (`triune.lua`).**
  - **Mode Indicator Next to Burn Button**: Added a dedicated live status badge next to the Burn button in `UI.drawActionControls()`, displaying the active combat mode (e.g. `Manual`, `Puller (Camp)`, `Assist (Backline)`) along with a color-coded `[RUNNING]` (green) or `[PAUSED]` (amber) tag.
  - **Status Page Vitals Reordering**: Moved the **Player, Gestalt Trio & Pet Vitals** card above the **Navigation & MQ2Nav Subsystem** card on the Status tab so immediate health/mana/endurance and pet telemetry is visible directly below the Current Target card.
  - **Persistent Collapsing State (`UI.drawCollapsingStatusHeader`)**: Integrated `status_collapsed` tracking into `ctrl` and wrapped all Status cards (`target`, `vitals`, `nav`, `xtar`) in `UI.drawCollapsingStatusHeader()`. The open/collapsed state of each card is automatically remembered, saved to configuration, and restored seamlessly across sessions and reloads.
  - **Multi-Pet HP & Vitals Telemetry**: Expanded the Pet Vitals section inside the Vitals card from a single `Me.Pet` access to full multi-pet tracking via `getMultiPetList()`. The card now iterates every active pet across the trio classes, any extra/swarm pets, and primary pets, rendering dedicated class badges (`[Mag]`, `[Nec]`, `[Bst]`), pet names, levels, targets, target distances, and individual color-coded health bars showing both current/max HP and percentage.

- **Horizontal Scrollbars Across All Pages & Panes (`triune.lua`, `triune_spellbook.lua`).**
  - **Main Window & Tab Lists (`triune.lua`)**: Added `ImGuiWindowFlags.HorizontalScrollbar` to `UI.drawFullGui` and all tab child list frames (`gemlist_`, `clickielist`, `abilitieslist`, `aalist`, `disclist`, and cooldown card HUD). Users can now smoothly scroll horizontally across wide rows and tables on every page.
  - **Spellbook Engine Panes (`triune_spellbook.lua`)**: Added `ImGuiWindowFlags.HorizontalScrollbar` to the main window flags, `##SpellbookBrowserPane`, and `##SpellGemsPane`.

- **Fix Spurious Auto-Attack Engagement in Manual Mode & Ability Triggers (`triune.lua`).**
  - **Ability Auto-Attack Restoration Fix**: Fixed a bug where `fireAA`, `fireSkill`, `fireDisc`, `useClickie`, and `castGem` (for Bard) were unconditionally issuing `/attack on` after firing any ability due to `(wasAttacking or (ctrl and (ctrl.combat_style or 'Melee') == 'Melee'))`. Replaced with `wasAttacking and not mq.TLO.Me.Combat()`, ensuring auto-attack is ONLY resumed if the character was already attacking prior to using the ability.
  - **Combat Stall Watchdog Guard (`runtime.checkCombatStall`)**: Added strict combat checks (`inCombat = Me.Combat() or CombatState() == 'COMBAT' or anyXtarAlive(true)`) to `checkCombatStall()`, and required the target in Manual mode to be on XTarget or attacking. This stops the stall watchdog from firing `/attack on` during downtime or simply because a player selected an NPC in melee reach.
  - **Manual Mode Engage Qualification (`combatTick`)**: Corrected `autoAttackOk` in `combatTick` so it defaults to `false`. In Manual mode, auto-attack now only engages if the player is actively engaged, in combat, or the target is an active hostile on XTarget. Also prevented unwanted auto-navigation re-closing when out of reach in Manual mode.

- **Main Chunk Local Variables Reduction & Limit Enforcement (`triune.lua`, `tests/test_pure_logic.lua`, `.github/workflows/ci.yml`).**
  - **Local Variables Consolidation**: Refactored 30+ top-level helper and UI functions (`saveLoadout`, `getPrimarySpellForGem`, `hasDowntimeAggroThreat`, `drawMiniGui`, `drawFullGui`, `draw`, `drawCooldownWindow`, `drawCritOverlay`, `spawnCritFloater`, `addClickieFromCursor`, `toggleTool`, `drawStatusProgressBar`, `getConColorRgb`, `savePreset`, `loadPreset`, `deletePreset`, `listPresets`, `collectEntry`, `applyEntry`, `deepCopyTable`, `importCurrentGems`, `upsertZonePreset`, `isPullAllowed`, `isConAllowed`, `isPullListed`, `addPull`, `removePull`, `addIgnore`, `removeIgnore`, `syncCurrentZoneWaypoints`, `loadAll`, `onCharacterChanged`) to be attached directly to the structured `runtime` and `UI` tables.
  - **Main Chunk Register Reduction**: Reduced the main function's active local register count in `triune.lua` from 201+ down to 174 slots (safely below the Lua 5.1/LuaJIT 200-local `MAXVARS` limit, providing a 26-slot safety buffer).
  - **Encapsulated Plugin Warning Logic**: Relocated file-level startup plugin warnings into `runtime.checkStartupPluginStatus()` to eliminate un-encapsulated block locals in the main chunk.
  - **Automated Regression Suite (Suite 50)**: Added Suite 50 to `tests/test_pure_logic.lua` that executes `luac -l -p` across all 9 suite Lua scripts, asserting that bytecode compilation passes without exceeding the 200 local limit and that `triune.lua` maintains <= 185 slots (1,325 tests passing).
  - **CI Bytecode Enforcement**: Updated `.github/workflows/ci.yml` to install `lua5.1` and compile all repository scripts using both `luajit -bl` and `luac -p` in the CI pipeline, preventing any future regressions.


- **Decoupled Spell Gems Loadout & Dynamic Downtime Buff Swapping (`triune.lua`, `triune_updater.lua`).**
  - **Decoupled Spell Gems Loadout (`loadout.gems`)**: Replaced the fixed 1-to-1 array coupling between spell lines and physical gem bar slots with an arbitrary-length, priority-ordered spell configuration list. Users can now configure any number of spells (exceeding the standard 12 gems).
  - **Per-Spell Gem Dropdown Selector**: Each spell row in the Spell Gems tab now features an individual `G1` through `G12` dropdown combo (scaled to a compact 50px width). Multiple spells can share the same physical gem (e.g. G12 can hold a combat nuke and multiple downtime buffs).
  - **Streamlined Spell Gems Header**: Relocated `+ Add Spell` to the very front of the toolbar directly in front of the level range inputs, and removed the Auto-mem checkbox, Import Bar button, Mem All button, and preset management controls (preset combo, name input, Save button, and Del button) to produce a unified, single-row header.
  - **Dynamic Spell Management & Priority Ordering**: Added `+ Add Spell` button in the tab header to append new customizable spell lines, along with `^` (move up) and `v` (move down) priority reordering buttons, and an `X` delete button per row (removed redundant priority numbers since list order is evaluated strictly top to bottom).
  - **Downtime Buff Swapping & Reliable Memorization (`runtime.processDowntimeBuffing`, `runtime.tryMem`, `runtime.unmemGem`)**: Introduced an automated downtime spell swapping engine based on `triune_spellbook.lua`:
    - **Reliable Unmemorization (`runtime.unmemGem`)**: Replaced non-existent `/unmemspell` commands with EQ gem right-clicks (`/notify CastSpellWnd CSPW_Spell%d rightmouseup`), waiting for the slot to clear.
    - **Simulated Spellbook Memorization (`runtime.tryMem`)**: Bypasses EMU server Fast-Mem detection by opening `SpellBookWnd`, finding the scribed slot (`runtime.getSpellBookSlot`), paging to the spell, lifting it (`SBW_Spell%d leftmouseup`), and dropping it onto the gem (`CSPW_Spell%d leftmouseup`).
    - **Progress & Aggro Monitoring**: Actively tracks `CastingWindow` memorization duration while continually checking for aggro threats to abort cleanly if attacked.
    - **Primary Spell Restoral**: Once missing buffs are satisfied, Triune restores the primary combat spell back into that gem using the same reliable simulated routine.
  - **Immediate Aggro Interruption & State Recovery**: If aggro is detected (`Me.Combat()`, `isCombat()`, `anyXtarAlive(true)`, or `countNPCXtarget() > 0`) at any point during spell swapping or recharge polling, Triune immediately aborts the swap (closes the spellbook window with `/book 0`, stands up), records the interrupted swap context (`runtime.interruptedSwap`), switches to combat mode, and engages all hostile targets on XTarget. Once combat ends and XTarget clears, Triune resumes the interrupted swap and finishes buffing.
  - **In-Combat Gem Safety**: `combatTick` restricts casting strictly to spells that are already memorized on the physical bar, preventing mid-combat spellbook locks or disruption.
  - **Primary Spell Resolution**: Added `getPrimarySpellForGem(slot)` helper to identify the primary combat spell for each physical slot, ensuring `Mem All`, preset loading, puller spell selection, and stale gem synchronization (`checkGemMemSync`) operate on the designated primary spells.
  - **Cooldowns Tab & Live Status Badging**: Updated `UI.getGemStatusBadge` and the Cooldowns tab to reflect `g.gem`, display `[MEM*]` when actively swapping or queued, and show clear `[UNMEM]` status with tooltips indicating downtime swap readiness.
  - **Version Bump**: Bumped version to `1.9.0` across `triune.lua`, `triune_updater.lua`, and `README.md`.


- **Target Retention During Targeted Spell Casting (`triune.lua`).**
  - **Spell Target-Requirement Classification (`isTargetRequiredSpell`)**: Introduced a helper that checks spell metadata via `mq.TLO.Spell.TargetType()` to classify whether a spell requires an active target (such as single-target heals, buffs, nukes, debuffs, dots, and lifetaps) versus self-directed or PB/group area-of-effect spells (`Self`, `PB AE`, `Group v1`, `Group v2`).
  - **Early Top-Level Casting Guard in `combatTick`**: Relocated active casting monitoring from the very end of `combatTick` to the top level (immediately after pet reconciliation and before stuck checks, aggro switches, mode retargeting, and combat movement). When actively casting or during the cast start latency window (`isCastingOrStarting()`), `combatTick` ensures the character stays firmly locked onto the required target (`getActiveTargetRequiredCastingId()`), synchronizes target if desynchronized, processes events, and returns early to prevent mid-cast target switches or navigation interruptions.
  - **Safe Post-Cast Target Restoration**: Upon casting completion (or failed cast), unpauses stick movement, records cast outcomes, clears cursor items, and cleanly restores the pre-cast target (`runtime.restoreTargetId`) before resuming normal combat execution.
  - **Target Locking in `runtime.setTarget` and `runtime.clearTarget`**: Updated `runtime.setTarget(id)` to reject any target switch away from the active casting target while casting a targeted spell (`getActiveTargetRequiredCastingId()`), and wrapped all raw `/target clear` commands across hunting, camping, and unstuck routines into `runtime.clearTarget()`, which preserves the active target during spell casts.
  - **Aggro Switch Suppression (`checkAggroSwitch`)**: Prevented opportunistic aggro switching from running while actively casting or starting a spell, ensuring healer and utility casts on group allies are never aborted by incoming mob aggro.
  - **Automated Regression Prevention**: Added 38 unit test assertions in `tests/test_pure_logic.lua` covering spell classification, target lock retention during single-target heals, target clear protection, and post-cast target restoration (1,289 tests passing).

- **Clickies Tab Compact Layout & Alignment (`triune.lua`).**
  - **Scoped Tighter Spacing & Frame Padding**: Applied scoped `ImGuiStyleVar.ItemSpacing (4, 3)` and `FramePadding (4, 3)` across the Clickies child list in `UI.drawClickieTab()`, reducing row heights and visual sprawl.
  - **Standardized Compact Widget Widths**: Replaced sprawling dropdown and slider widths with standardized compact dimensions matching Spell Gems: Target combo to 133px (was 150px), When combo to 116px (was 140px), Threshold % slider to 57px (was 90px) with `'Off'` label at 0% (was `'Disabled'`), and Min XTarget combo to 35px (was 45px).
  - **Pixel-Perfect Invisible Dummy Button Alignment**: Replaced disabled button elements on boundary slots (`idx == 1` and `idx == #loadout.clickies`) with `ImGui.InvisibleButton (17, 19)`, ensuring priority numbers, status indicators, and item names stay perfectly aligned vertically down every row.
  - **Priority Badging & Status Indication**: Added clickie priority numbering (`%2d`) and grayed-out item labels (`MUTED`) when clickies are disabled.
  - **Streamlined Add Button**: Scaled the `+ Add Item on Cursor` header button down to `(150, 20)` for a tighter header layout.

- **Tab Bar Reordering: Disciplines and Clickies Placement (`triune.lua`).**
  - **Natural Combat Action Flow**: Moved `UI.drawDiscTab()` and `UI.drawClickieTab()` to sit directly between `UI.drawAATab()` and `UI.drawAutoAATab()`. This groups all active combat loadouts together in natural progression (`Spell Gems -> Abilities -> AAs -> Disciplines -> Clickies`), followed by automation & utility tabs (`Auto AA -> Cooldowns -> Settings -> Help`).
  - **TabBar ID Reset & Reorder Support (`triuneTabs_v2`)**: Migrated the tab bar ID from `'triuneTabs'` to `'triuneTabs_v2'` with `ImGuiTabBarFlags.Reorderable` and `ImGuiTabBarFlags.FittingPolicyScroll`. This forces Dear ImGui to invalidate any cached tab order preserved in MacroQuest's C++ memory from previous sessions, guaranteeing the new tab order renders immediately, and allows manual tab dragging.

---

## 2026-09-01

- **Plugin Autoloading & Missing Warnings Suite (`triune.lua`, `triune_map.lua`, `triune_track.lua`).**
  - **Automatic Plugin Load on Startup**: On script initialization, `triune.lua`, `triune_map.lua`, and `triune_track.lua` now automatically detect and attempt to load both `mq2nav` (`/plugin mq2nav`) and `mq2moveutils` (`/plugin mq2moveutils`) if they are not already loaded, waiting briefly for MacroQuest to complete initialization.
  - **MacroQuest Window & Chat Console Warnings**: If either `mq2nav` or `mq2moveutils` is not found or fails to load, all three scripts print clear color-coded warning notices (`\ar[<Script> WARNING]\ax`) directly to the MacroQuest chat window with instructions on how to load them.
  - **Enhanced Combat & Action Validation**: Added MoveUtils missing checks and center-screen `/popup` alerts when starting combat (`/ac run`, `/triunerun`, and UI `START` buttons), and validated plugin availability when clicking map coordinates or tracking navigation actions.
  - **Interactive UI Recovery Buttons**: Added `[Load MQ2MoveUtils]` recovery buttons alongside `[Load MQ2Nav]` across the main Triune window header, Status tab navigation subsystem table, Settings tab under Navigation & Hazard Avoidance, Mini HUD overlay, Triune Map settings, and Triune Track window.
  - **Suite-Wide Core API Verification**: Audited `triune_buffbot.lua`, `triune_buttons.lua`, `triune_cursor.lua`, `triune_dps.lua`, `triune_spellbook.lua`, and `triune_updater.lua` to verify they operate purely on native MacroQuest core APIs without requiring external plugins.
  - **Automated Pure Logic Tests**: Added unit tests in `tests/test_pure_logic.lua` covering `stickLoaded` detection across multiple mock states and cross-file standalone validation for `triune_track.lua` and `triune_map.lua` (1,239 tests passing).

- **Abilities & AA Health Threshold & Feign Death Evaluation Fix (`triune.lua`).**
  - **Universal Feign Death Recognition (`isFeignDeathAbility`)**: Added unified detection covering innate skills, Alternate Advancement abilities (`Death Peace` for Shadowknights, `Imitate Death` for Monks, `Death's Effigy`), and scribed spell gems.
  - **Strict Self-HP Evaluation in `conditionMet`**: Explicitly routes condition checks for survival abilities (`Feign Death`, `Death Peace`, `Imitate Death`, `Mend`, `Bind Wound`) to compare against the local player's current health (`mq.TLO.Me.PctHPs()`), even when configured with `'HP <='`, `'my HP <='`, or `'target HP <='` or when targeting hostile entities. Setting the health slider to `20%` guarantees it only triggers when the player drops to 20% HP or lower.
  - **AA Tab Smart Defaults (`UI.drawAATab`)**: Feign Death AAs (e.g. `Death Peace`, `Imitate Death`) now default to `target = 'F: Myself'`, `when = 'my HP <='`, and `pct = 20` when first enabled.
  - **AA & Spell Posture & Attack Protection (`fireAA`, `castGem`, `fireSkill`)**: Updated `runtime.fireAA` and `runtime.castGem` alongside `runtime.fireSkill` to disengage auto-attack (`/attack off`), omit `/stand` before activation, and suppress automatic `/attack on` re-engagement after firing Feign Death AAs or spells.
  - **Autoskill Gating (`isAutoskillEligible`)**: Restricted the `Auto##as` ("Autoskill") checkbox on the Abilities tab strictly to genuine high-frequency melee attack skills (`Kick`, `Flying Kick`, `Backstab`, `Bash`, `Slam`, `Frenzy`, etc.). Removed the `Auto` checkbox from non-melee and survival abilities (`Feign Death`, `Mend`, `Taunt`, `Bind Wound`, `Hide`, `Sneak`, etc.) so they are never erroneously scheduled for continuous cooldown execution.
  - **Loadout Sanitization**: Automatically backfills and sanitizes persisted action entries so `act.autoskill` is forced to `false` for non-autoskill abilities, and guards the `combatTick` autoskill loop with `isAutoskillEligible(name)`.
  - **Accurate Player Health in `pctHP`**: Enhanced `pctHP(id)` to query `mq.TLO.Me.PctHPs()` directly when checking the local character, and defaulted unresolvable/nil spawn queries to `100%` (safe state) rather than `0%` (which previously produced false emergency triggers).
  - **Active Feign Combat Protection**: Added an active `Me.Feigning()` check at the top of `combatTick` to pause combat movement and offensive actions while feigning death so posture is not broken prematurely.
  - **Automated Regression Prevention**: Added 41 test assertions in `tests/test_pure_logic.lua` covering `isAutoskillEligible`, `isFeignDeathAbility`, `pctHP` accuracy and defaults, `Death Peace` and `Imitate Death` AA condition thresholds, and UI autoskill guards (totaling 1,234 tests passing).

- **Tab Bar Reordering (`triune.lua`).**
  - **Settings Tab Relocation**: Moved the `Settings` tab in `drawFullGui()` (`triuneTabs`) between the `Clickies` and `Help` tabs (`... -> Disciplines -> Clickies -> Settings -> Help`), grouping all combat action and loadout tabs (Spell Gems, Abilities, AAs, Auto AA, Cooldowns, Disciplines, Clickies) together immediately following the Pets tab.

- **Spell Gems Tab Compact Layout & Alignment (`triune.lua`).**
  - **Horizontal Width Optimization**: Optimized widget widths across all gem rows (Class combo from 62px to 46px, Spell combo from 185px to 142px, Target combo from 140px to 105px, When/Condition combo from 138px to 105px, HP% slider from 75px to 52px, Min XT combo from 42px to 32px, and reduced item spacing to 4px), saving ~190px of horizontal sprawl and completely eliminating horizontal scrollbars within the standard 720px window.
  - **Pixel-Perfect Slot Swap Alignment**: Replaced single-space text placeholders with equal-sized invisible dummy buttons (`ImGui.InvisibleButton`) on boundary slots (`i == 1` and `i == maxGems`), aligning slot numbers, status badges, and dropdowns vertically down every row.
  - **Compact Slider Label**: Replaced `'Disabled'` on 0% threshold sliders with `'Off'` (preserving full explanation in hover tooltips), preventing text clipping inside compact sliders.
  - **Streamlined Two-Row Header**: Consolidated filters and automation toggles (Level range, Scribed, Auto-mem, Rebuff threshold, Import Bar, Mem All) onto Row 1, and dedicated Row 2 cleanly to Preset management (Load dropdown, Name input, Save, Delete).
  - **Tighter Row Padding**: Applied scoped `ImGuiStyleVar.ItemSpacing (4, 3)` and `FramePadding (4, 2)` inside `UI.drawGemList()`, reducing row height and allowing full gem sets (up to 12 slots) to fit comfortably on screen with minimal vertical scrolling.

- **Per-NPC Cast Limit Dropdown (`triune.lua`).**
  - **Replaced Boss Checkbox with Cast Limit**: Removed the `Boss` checkbox from the Spell Gems tab and replaced it with a compact dropdown (`##mc`) controlling how many times a spell can be cast on a specific NPC target (`Unl`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `10`).
  - **Dynamic Cast Gating (`runtime.npcCastCounts`)**: Tracks successful spell casts per target spawn ID. When a spell reaches its configured `max_casts` limit on an NPC, the spell is cleanly gated and no longer cast on that target, allowing debuffs, slows, snares, and initial nukes/DoTs to land a designated number of times without mob spam.
  - **Fizzle & Interrupt Recovery**: Decrements target cast count if a cast fails due to fizzle or interruption, ensuring spells reliably reach the desired cast limit.
  - **Auto-Pruning & State Management**: Automatically prunes dead target IDs from `runtime.npcCastCounts` during combat and wipes tracking on zoning or character death.

- **Spell Gems Tab +10% Scale Enhancement (`triune.lua`).**
  - **10% Larger Controls**: Increased button, slider, and dropdown widths across all gem rows by ~10% (When combo to 116px, HP% slider to 57px, Min XT to 35px, and Max Casts combo to 48px; swap buttons to 17x19px), with increased frame padding `(4, 3)` for noticeably improved legibility and clickability.
  - **Expanded Identity Combos (+15%)**: Further broadened the primary identification dropdowns on each gem row (Class combo to 59px, Spell combo to 180px, and Target combo to 133px) and raised default window width to 830px to provide ample room for longer spell names and target descriptors without clipping.
  - **Header & Window Sizing**: Scaled header inputs (level range, rebuff slider, preset dropdown and text field) by +10% and adjusted default window width from 720px to 830px to accommodate the larger row elements comfortably.

- **Compact Layout Applied to Abilities, AAs, and Disciplines Tabs (`triune.lua`).**
  - **Scoped Tighter Spacing & Frame Padding**: Applied scoped `ImGuiStyleVar.ItemSpacing (4, 3)` and `FramePadding (4, 3)` to the child lists in `UI.drawAbilitiesTab()`, `UI.drawAATab()`, and `UI.drawDiscTab()`, eliminating vertical padding bloat and keeping row height streamlined.
  - **Standardized Compact Widget Widths**: Replaced sprawling dropdown and slider widths across all three tabs to match the unified design system: Target dropdown to 133px (was 150px), When dropdown to 116px (was 140px), Threshold % slider to 57px (was 90px) with `'Off'` format for 0%, Min XTarget combo to 35px (was 45px), and Priority slider to 70px (was 80px).
  - **Compact Labels**: Shortened `Boss Only##bo` to `Boss##bo` in the Disciplines tab for clean single-row fitting without line wrapping.
  - **Automated Regression Prevention**: Added child window safety assertions for `abilitieslist`, `aalist`, and `disclist` in `tests/test_pure_logic.lua`.

- **Cast Tracker Scoping Bug Fix (`triune.lua`).**
  - **Fixed `attempt to index global 'castTracker' (a nil value)`**: In `createCastTracker()`, the tracker instance is declared as `local tracker = {}` inside the function, whereas `castTracker` is declared as a file-scoped local after the factory function. Replaced an accidental forward-reference to `castTracker` in `recordFailure()` with the proper local `tracker` instance, preventing a runtime nil crash during spell fizzle or interrupt handling.

- **ImGui Child Window Lifetime & Crash Fix (`triune.lua`, `triune_buffbot.lua`, `triune_updater.lua`).**
  - **Fixed `Must call EndChild() and not End()!` Crash**: In Dear ImGui, `ImGui.BeginChild()` pushes a child window to the stack regardless of whether it returns true or false. Moved all `ImGui.EndChild()` calls outside of `if ImGui.BeginChild(...) then ... end` conditional blocks across `UI.drawGemList()`, `petModalBuffsChild`, `##TriuneCooldownCardsList`, `LogChild`, and `ReleaseNotesBox`/`DiagBox`, ensuring child windows are never left unclosed when culled or clipped.
  - **Added Regression Prevention Unit Tests**: Added automated child window safety checks in `tests/test_pure_logic.lua` and documented the lifetime rule in `.agents/AGENTS.md`.

- **Spellbook Browser UI Layout Redesign & Loadout Tab Removal (`triune_spellbook.lua`).**
  - **Vertical Right-Hand Spell Gem Bar**: Moved the spell gem loadout slots from the cramped horizontal top bar into a dedicated vertical sidebar pane on the right-hand side of the window (`##SpellGemsPane`).
  - **Full Unabbreviated Spell Names**: Eliminated the 9-character truncation (`displayLabel:sub(1, 9)`), allowing full spell names to be read clearly across all active gem buttons (`G%d: <Spell Name>`).
  - **Selected Spell & Queue Visibility**: Added a prominent "Selected Spell" indicator with a `[Clear]` button directly above the gem slots showing which spell is targeted for memorization, plus dynamic `(Memming)` labels for queued spells.
  - **Removed Loadouts / Presets Tab**: Removed the unused "Loadouts / Presets" tab and purged unused preset store structures from the state table.
  - **Removed Gestalt Options Menu Bar**: Removed the top grey menu bar (`ImGui.BeginMenuBar()` / `Gestalt Options`) and replaced it with a sleek inline `[Re-detect]` button next to the active gestalt class buttons.
  - **Removed Unmem All Gems Button**: Removed the bulk "Unmem All Gems" button from the spell gems pane to avoid accidental spell wiping.
  - **Right-Click Spell Info Inspection**: Right-clicking any spell row in the Spellbook Browser table triggers MacroQuest's native in-game inspection (`mq.TLO.Spell(name).Inspect()`), displaying the full EverQuest spell details window (mana, cast time, duration, and effects), accompanied by informative hover tooltips.
  - **Side-by-Side Two-Pane Layout**: The Spellbook Browser (category buttons, level filters, scribed-only toggle, search filter, and full-height scrollable spell table) and vertical spell gem bar now sit side-by-side, maximizing vertical space and providing a clean, responsive interface.

- **Dedicated Pets Tab & Multi-Pet Management (`triune.lua`, v1.8.0).**
  - **"Pets" Tab (`UI.drawPetControlTab`)**: Updated top-level tab label to **`Pets`** positioned immediately next to `Control` in the main Triune window (`Status -> Control -> Pets -> Settings -> ...`), unifying multi-pet telemetry and server command dispatch in a clean interface.
  - **In-Game `/pet report` & Detailed Stats Inspector Window**: Added a `/pet report` button to each active trio pet slot, swarm pet card, and the global toolbar. Clicking it issues `/pet report` in chat, targets the pet, dispatches `#petcmd health <scope>`, and pops up a comprehensive modal inspection window (`Pet Stats Report##petStatsModal`) presenting full identity, loc coords, heading, speed, posture, color-graded HP & Mana bars, target telemetry, active buffs list, and quick action buttons.
  - **Multi-Pet Telemetry for Trio Setups (`getMultiPetList`, `getPetSpawnInfo`)**: Added real-time tracking for up to 3 simultaneous pets across the player's gestalt trio classes (Magician, Beastlord, Necromancer, Enchanter, Shaman, Druid, Bard, Shadowknight) plus active swarm pets. Displays live color-graded HP progress bars, current/max HP values, target engagement telemetry (target name, target HP%, distance), and active buff lists with hover tooltips.
  - **Server `#petcmd` Protocol Integration (`sendPetCmd`, `classToPetCmdScope`)**: Fully implemented the server's `#petcmd` multi-pet command system, routed via `/say #petcmd` to ensure EQEMU chat command handler execution without leading slashes. Supports all server verbs (`attack`, `qattack`, `follow`, `guard`, `sit`, `stop`, `taunt (on/off)`, `hold (on/off)`, `ghold (on/off)`, `spellhold (on/off)`, `focus (on/off)`, `back`, `regroup (on/off)`, `assist (on/off)`, `health`, `leader`, `feign`, `leave`) across all valid scopes (`all`, `swarm`, `mag`, `bst`, `nec`, `enc`, `shm`, `dru`, `brd`, `shd`).
  - **Global & Individual Command Surfaces**: Provides a prominent global action toolbar with scope filtering, dual `[ON] [OFF]` stance toggle buttons, and a custom `#petcmd` execution runner, as well as per-pet card action buttons (`Attack`, `Back`, `Follow`, `Guard`, `Sit`, `Stop`, `Leave`, `/pet report`, and stance toggles) automatically scoped to that specific pet's class.
  - **Smart Multi-Pet Reconcile (`reconcilePets`, `detectPetClassFromSpawn`)**: Enhanced zone pet scanning to detect pet class archetypes (Warder -> Bst, Elemental -> Mag, Skeleton/Spectre -> Nec, Animation -> Enc, Spirit Wolf -> Shm) and accurately map existing pets to trio slots without relying on arbitrary spawn index proximity.
  - **Embedded Automation & Discipline Settings**: Embedded the `Pet Assist At %` HP threshold slider and `Enable Pet Hold` out-of-combat toggle directly into the tab alongside live automation state feedback (`[HOLD ACTIVE]` vs `[ENGAGED]`).
  - **Compact Pets Tab Layout & UI Streamlining**: Removed redundant controls (`feign`, `regroup`, `qattack`, custom `#petcmd` text input/button, target scope dropdown, and global health report) and refactored action buttons into a single clean line (`Attack All`, `Back Off`, `Follow`, `Stop`, `Guard`, `Sit`, `Dismiss All`). Moved the `Pet Assist At %` slider, `Auto Pet Hold` toggle, and live Auto Hold telemetry status directly to the top of the tab for immediate visibility, eliminating lower-window scrolling.
  - **New Slash Commands**: Added `/ac pet <verb> [scope]`, `/ac pet status`, `/ac pet report`, `/ac petscan`, `/ac pethold [on|off]`, and `/ac petassist [1-100]`.
  - **Project Version Bump (v1.8.0)**: Synchronized version **1.8.0** across `triune.lua`, `triune_updater.lua`, and `README.md`.
- **LuaLS Type Safety Fix (`triune_buffbot.lua`).**
  - **Type-Safe Boolean Assignment (`isPlayerSameGuild`)**: Replaced a short-circuit expression on `valid` with an explicit conditional assignment block, preventing LuaLS static type conversion warnings where `nil` could be inferred for boolean variables.

---

- **Guild Priority Buffing Policy & Cast Preemption (`triune_buffbot.lua`, v1.7).**
  - **Guild Policy Selector (`ctrl.guildMode`)**: Added a 3-way Guild Policy option (`Off`, `Guild Priority`, `Guild Only`) replacing the binary guild toggle.
  - **Active Cast Preemption (`/stopcast`)**: When `Guild Priority` is active and a guild member requests buffs while a non-guild player is currently receiving buffs, Buffbot immediately cancels the ongoing spellcast (`/stopcast` + `/interrupt`), sends a polite notification tell to the paused requester (`ctrl.guildPriorityPauseMsg`), prioritizes and buffs the guild member first, and seamlessly resumes the non-guild player's remaining uncast spells afterwards (`ctrl.guildPriorityResumeMsg`).
  - **Priority Queue Insertion (`enqueueBuffJob`, `requeuePreemptedJob`)**: Guild member buff jobs automatically jump ahead of all non-guild requesters in `runtime.activeQueue` while preserving strict FIFO ordering within each tier. Preempted non-guild jobs retain their exact remaining spell lists and re-queue at the front of the non-guild pool.
  - **Live Queue & Policy UI**: Updated the `Controls` tab with Guild Policy radio buttons, live guild name telemetry (`(Your Guild: <Name>)`), and customizable tell message inputs. Enhanced the `Activity Log` queue table with a dedicated `Tier` column (`Guild` vs `Public` vs `Resuming`).
  - **Character Config Persistence & Migration**: Automatically persists `guildMode`, `guildPriorityPauseMsg`, and `guildPriorityResumeMsg` per character in `triune_buffbot_config.lua` with backward-compatible migration for legacy `guildOnly` configs.
- **ImDrawList Function Signature Fix (`triune_map.lua`).**
  - **MacroQuest Sol3 Argument Compatibility**: Added explicit `numSegments` (0) parameter to all 13 `AddCircleFilled` calls and explicit rounding (0.0) to `AddRectFilled` in `DrawMapCanvas`, preventing sol runtime errors ("no matching function call takes this number of arguments and the specified types") on Dear ImGui canvas rendering.
  - **New "Auto AA" Tab (`UI.drawAutoAATab`)**: Added a dedicated top-level `Auto AA` tab to Triune (Status -> Control -> Settings -> Spell Gems -> Abilities -> AAs -> **Auto AA** -> Cooldowns -> Disciplines -> Clickies -> Help) dedicated to server AA point cap management and automated fireworks summoning.
  - **Live AA Point Pool Telemetry**: Renders live unspent AA points with color-coded status badges (`[CAP REACHED!]` in red when at 100/100, `[THRESHOLD MET]` in yellow, or normal status in green) alongside total spent and overall earned points.
  - **Automated AAWindow UI Interaction & Training Workflow (`findAAInWindowLists`, `runtime.startAATrainWorkflow`, `runtime.processAATrainWorkflow`)**: Fully automated the in-game AA window training workflow via guarded MacroQuest `/notify` commands (`TrainButton`) for progression servers where `/alt buy` is disabled. Triune opens the AA window (`/keypress V` / `/window open AAWindow`), scans tabs 1-5 and UI lists (`AAW_List`, `AAW_GeneralList`, `AAW_ArchetypeList`, etc.) for the ability, selects the matching item (`/nomodkey /notify AAWindow <list> listselect <index>`), triggers the Train button (`/nomodkey /notify AAWindow TrainButton leftmouseup`), and cleanly closes the window when finished.
  - **Streamlined Notify-Based Auto AA Tab**: Simplified the `Auto AA` tab to eliminate redundant manual `/alt buy` inputs and method radio buttons, focusing purely on automated window-based training, live AA pool diagnostics, and fireworks summoning.
  - **Auto-Summon Fireworks Engine (`runtime.checkAutoSummonFireworks`)**: Optionally monitors the fireworks summoning ability (ID 17788: *Alternately Advanced Fireworks*) and activates `/alt activate <id>` whenever ready (out of combat and stationary), automatically clearing the summoned firework into inventory bags (`/autoinventory`).
  - **Interactive Actions**: Added instant action buttons in the UI for `Train AA Now (/notify AAWindow)`, `Summon Fireworks Now (/alt activate 17788)`, and `Clear Cursor (/autoinv)`.
  - **Slash Commands**: Added slash command control with `/ac autoaa [on|off]`, `/ac autofw [on|off]`, `/ac aatrain` / `/ac spendnow`, `/ac summonnow`, `/ac aathreshold [25-100]`, `/ac aacost [1-50]`, and `/ac aaid [id]`.
- **Removed Auto Updater UI Buttons (`triune.lua`).**
  - **Main Toolbar & Mini HUD Streamlining**: Removed the `Updater` button from the top header toolbar (`UI.drawHeaderBar`) and the `Update` button from the Compact Mini HUD toolbar (`drawMiniGui`), decluttering the primary navigation surfaces. Standalone update checks remain accessible via `/ac update` and `/lua run triune_updater`.
  - **Project Version Bump (v1.7.9)**: Synchronized version **1.7.9** across `triune.lua`, `triune_updater.lua`, and `README.md`.
- **Class Detection Zoning Reset & Parsing Fix (`triune.lua`, `triune_spellbook.lua`).**
  - **Eliminated Erroneous Zoning Class Reset**: Removed destructive `classesFromInventoryWindow()` calls from `runtime.onZoned()`. Player classes are loaded on character login/switch or configured via the Class Picker UI and should not be re-scanned or overwritten during zone changes.
  - **Fixed UI Text Substring False Positives (`parseClassLine`)**: Removed prefix-slice checks (`sub(1, 3)` and `sub(1, 2)`) that erroneously matched arbitrary Inventory Window UI labels and buttons to classes (such as "Skills" matching "SK" and "Magic Resist" matching "Mag", which caused `myClasses` to reset to `{"SK", "Mag"}`). `parseClassLine` now strictly validates entire cleaned strings or whole-word tokens against the canonical `MQSHORT` table.
  - **Standalone Parity & Unit Tests**: Synchronized `MQSHORT` and `parseClassLine` across `triune.lua` and `triune_spellbook.lua` per the Standalone File Rule, and added test coverage in `tests/test_pure_logic.lua` ensuring UI strings (`Skills`, `Magic`, `Magic Resist`, `Warhammer`, `Stats`, `Inventory`) correctly return `nil`.

---

## 2026-08-30

- **Luacheck Warning Elimination (`triune.lua`).**
  - **Direct Discipline Metric Initialization (`UI.getTrackedCooldownItems`)**: Initialized `totalSec`, `endCost`, `activeTotalSec`, `timerGroupId`, and `discIdx` directly from `discInfo` instead of pre-initializing with dummy zeroes/nil, resolving all luacheck overwritten variable warnings and ensuring clean CI passes (`0 warnings / 0 errors in 10 files`).

- **LuaLS Type Warnings & Nil Check Hardening (`triune_buttons.lua`).**
  - **Type-Safe Timer Key Assignment (`saveEdit`)**: Decoupled buffer string reading from `tk` variable declaration, eliminating LuaLS static type conversion warnings when assigning numeric gem indices, integer second delays, or nil.
  - **Button Edit State Nil Guard (`drawEditWindow`)**: Added an explicit `edit.tmp` nil check and early close fallback before rendering the button edit controls, preventing nil index warnings across all button attribute inputs.

- **Project Version Bump (v1.7.7)**: Synchronized version **1.7.7** across `triune.lua`, `triune_updater.lua`, and `README.md`.

- **Cooldown & Active Duration Accuracy Overhaul (`triune.lua`, `triune_buttons.lua`).**
  - **Accurate Active Duration Calculation (`parseDurationSec`)**: Fixed active duration parsing across Alternate Advancements, Disciplines, Buffs, and Songs. MacroQuest's `Me.Buff.Duration` timestamp object is now parsed directly via `.TotalSeconds()`, `.Raw()` (/ 1000.0), or standard string conversion, eliminating previous tick-multiplication bugs (`duration * 6` on millisecond timestamps) that erroneously multiplied milliseconds by 6.
  - **Discipline Reuse & Base Cooldown Engine (`getDiscCooldownAndDuration`, `DISC_BASE_COOLDOWNS`, `DISC_BASE_DURATIONS`)**: Added a comprehensive database of era-accurate discipline cooldowns and durations across all melee/hybrid classes (War, Pal, SK, Mnk, Rog, Rng, Ber, Bst). Discipline recast lookups now seamlessly merge spell data with `DISC_BASE_COOLDOWNS` fallbacks when MacroQuest `Spell.RecastTime` returns 0 for classic EQ combat abilities.
  - **Discipline Timer Parsing (`parseCombatAbilityTimer`)**: Fixed `CombatAbilityTimer` lookups by supporting dual-path query (both by discipline name and integer combat ability index) and properly converting raw tick values (`1 tick = 6s`) to seconds while safely handling millisecond returns.
  - **Eliminated Phantom Cooldown Loops**: Removed destructive fallback blocks in `UI.getTrackedCooldownItems()` that falsely set full artificial cooldowns and stamped `lastDiscFiredAt = now` on every frame for ready abilities gated by resource/combat checks (`LOW END`, `BLOCKED`, `NEED BURN`, `NEED BOSS`, `MIN XTAR`).
  - **Cyan Active Progress Bar Scaling (`activeTotalSec`)**: Connected each ability's true baseline active duration (`activeTotalSec`) to both Table and HUD Card progress bars, ensuring active stances and buffs render a full 100% -> 0% countdown rather than a thin 2% sliver.
  - **Toolbar Buttons Cooldown Sync (`triune_buttons.lua`)**: Updated `getCooldown(btn)` to use the shared `parseTloTimer` logic, properly converting `CombatAbilityTimer` ticks to seconds rather than misinterpreting ticks as milliseconds.

- **Control Tab UI Streamlining (`triune.lua`).**
  - **Removed Redundant Closer-Mobs Checkboxes**: Removed the duplicate `Check for Closer NPCs while Traveling` checkboxes from the `Hunter` and `Camp` submode sections on the Control tab, consolidating closer-target movement configuration onto the dedicated `Closer-NPC Retargeting During Movement` section on the Settings tab.

- **Dedicated Cooldowns Tab & Shared Popout Integration (`triune.lua`).**
  - **New Cooldowns Tab (`UI.drawCooldownsTab`)**: Added a dedicated `Cooldowns` tab directly in the main Triune window positioned right after the `AAs` tab (Status -> Control -> Settings -> Spell Gems -> Abilities -> AAs -> **Cooldowns** -> Disciplines -> Clickies -> Help).
  - **Shared Collision-Free Cooldown UI (`UI.renderCooldownContent`)**: Refactored the live ability, AA, discipline, spell, and clickie cooldown monitoring view into a unified renderer accepting unique ImGui ID suffixes (`_tab` vs `_win`), preventing ID collisions and input freezing when both the main window tab and the floating popout window are active simultaneously.
  - **Popout Window Option Inside Tab**: Added a dedicated `Popout Window` button directly inside the Cooldowns tab header, allowing users to pop out the monitor into a standalone floating window at any time while retaining full in-tab functionality.
  - **Unit Tests**: Added test cases in `tests/test_pure_logic.lua` validating the presence and exact tab sequence ordering of `UI.drawCooldownsTab()` right after `UI.drawAATab()`.

- **Lua Variable Shadowing Fix (`triune_map.lua`).**
  - **Luacheck Warning Elimination**: Renamed shadowed `childFlags` variables within `DrawMapCanvas` to unique identifiers (`canvasChildFlags`, `floorNavFlags`, `overlayFlags`), resolving all luacheck shadowing warnings and ensuring clean CI passes.

- **Map Loading Time & Anti-Stutter Performance Engine Overhaul (`triune_map.lua`).**
  - **High-Speed Stream Map Parser (`parseMapFile`)**: Replaced line-by-line regex parsing (`gmatch('[^\r\n]+')` + `line:match(...)`) with direct single-pass stream tokenizers for lines and labels, eliminating hundreds of thousands of intermediate string allocations and reducing zone map parse times by over 80%.
  - **Eliminated Blocking Process Spawns (`io.popen`)**: Removed all blocking subshell child process spawns (`cmd /c dir` / `find`) from folder and file scanning routines, substituting them with instant C-level non-blocking direct file probes (`<1ms` total probe time across all 300+ Atlas zones) to eliminate game hitching on scan/init.
  - **O(1) Navmesh Background Queue (`processNavBatch`)**: Replaced $O(N)$ `table.remove(queue, 1)` array shifts with an $O(1)$ amortized `queueHead` pointer, preventing frame drops during background navmesh path verification.
  - **Optimized Radar Spawn Scans (`scanZoneSpawns`)**: Throttled maximum nearby NPC radar queries to 120 closest spawns, eliminating $O(N^2)$ `NearestSpawn` iteration freezes in densely populated zones.

- **Compact Map UI & Floating Bottom Control Dock (`triune_map.lua`).**
  - **Removed Redundant Top Toolbar**: Eliminated the top text bar and metrics header above the tab bar so the tabs start flush at the top of the window, maximizing vertical map canvas viewing area.
  - **Unified Floating Canvas Control Dock (`##MapControlOverlayChild`)**: Relocated the `Follow` checkbox, `Center Me` / `Center Map`, `POIs` drawer toggle, `Stop Nav`, and `Live Zone` return buttons down into a sleek floating 2-row bottom-right overlay dock alongside `+`, `-`, `⟲`, and `AZ` controls.
  - **Larger Button Hitboxes & Double-Click Exclusion**: Increased button dimensions from 24px to 28px/26px and expanded the hitbox exclusion barrier so double-clicking on or near on-canvas control buttons never triggers accidental ground navigation or mob targeting on the underlying map canvas.
  - **ImGui Style Stack Balance Guard**: Fixed a state-flip condition on the POIs button where toggling `state.showPoiDrawer` during the click callback caused `PopStyleColor` to be called without a preceding push, eliminating the `Calling PopStyleColor() too many times!` crash.

- **Left-Click Only Map Panning (`triune_map.lua`).**
  - **Restricted Viewport Drag Panning**: Updated viewport drag panning to trigger strictly when holding down the primary Left Mouse Button (`isItemActive and ImGui.IsMouseDown(0)` without Ctrl held), removing right-click panning initiation and right-click drag tracking.

- **Interactive Mouse Wheel Zoom Fix (`triune_map.lua`).**
  - **Scrollable Child Window Region (`##MapCanvasScrollRegion`)**: Enclosed the 2D map canvas in a dedicated child window container with virtual scroll content height (`SetNextWindowContentSize`) and baseline scroll midpoint tracking (`ImGui.GetScrollY`), replacing the unsupported `io.MouseWheel` query (which is not bound on MacroQuest's `ImGuiIO` Lua usertype) with native ImGui scroll delta capture.
  - **Window Scroll Flag Unlocking**: Removed `ImGuiWindowFlags.NoScrollWithMouse` from the top-level main window flags so mouse wheel scroll events cleanly reach the canvas viewport and inner scrollable list panes.
  - **Cursor-Centered Smooth Zooming**: Restored smooth zooming in (wheel up) and zooming out (wheel down) centered on the active mouse cursor coordinate.

- **ImGui Window Layout Streamlining & Spacing Cleanup (`triune.lua`).**
  - **Removed Extraneous Dummy Spacing**: Removed 77 redundant `ImGui.Dummy(0, N)` and `ImGui.Dummy(N, 0)` spacers across all tabs (Status, Control, Settings, Gems, Clickies, Abilities, AAs, Discs, Help, and Class Picker), relying on natural theme item spacing for consistent, uncluttered padding.
  - **Streamlined Action Controls Bar (`UI.drawActionControls`)**: Compacted `START`/`PAUSE` and `BURN` buttons to sleek 130x24 standard dimensions with direct `ImGui.SameLine()` alignment right above the tab bar.
  - **Mini HUD Mode Spacing Refinement (`drawMiniGui`)**: Replaced double-spaced separator blocks (`Spacing(); Separator(); Spacing()`) with clean single separators and removed empty spacing lines, keeping the compact mini-window tightly fitted.
  - **Tighter Tab Layouts & Metric Overview**: Compacted vertical padding in the Status tab overview table, Target Threat card, Navigation diagnostics, and Settings tabs so key combat telemetry and controls fit naturally on screen without excessive scrolling.

- **Popout Cooldown & Ability Monitor Window (`triune.lua`).**
  - **Standalone Popout ImGui Window (`TriuneCooldownWindow`)**: Registered an independent, top-level ImGui window (`TriuneCooldownWindow`) providing real-time live monitoring of all enabled Innate Combat Abilities, Alternate Advancements (AAs), Disciplines, Spells (Gems), and Clickie items across all three character classes.
  - **Cooldown-First Automatic Sorting**: Updated default time sorting so items currently on cooldown and active effects sort directly to the **top** of the list with soonest-to-recover abilities appearing first, followed by ready abilities ordered by priority.
  - **AA & Discipline Cooldown Timer Overhaul (`runtime.fireAA`, `runtime.fireDisc`, `isDiscReady`)**:
    - **Alternate Advancements (AAs)**: Dual-path lookup querying `mq.TLO.Me.AltAbilityTimer` by both name and integer AA ID (`aaObj.ID()`), evaluating hastened reuse times (`MyReuseTime()`), tracking software timestamps (`runtime.lastAAFiredAt`), and inspecting spell-name buffers (`Buff(spellName)`, `Song(spellName)`) so AA durations and cooldowns tick down second-by-second.
    - **Combat Disciplines (Discs)**: Handled MQ `CombatAbilityTimer` ticks conversion (1 tick = 6s) and milliseconds normalization, added shared EverQuest Timer Group cooldown tracking (`runtime.timerGroupCooldown`), and software elapsed tracking (`runtime.lastDiscFiredAt`).
    - **Innate Abilities**: Implemented `ABILITY_BASE_COOLDOWNS` lookup database and dual-path TLO inspection (`mq.TLO.Me.AbilityTimer(nm)`, `mq.TLO.Me.AbilityTimer(idx)`, `AbilityTimerTotal`) with software elapsed time tracking (`runtime.lastSkillFiredAt`).
  - **Active Duration & Stance Countdown**: Displays active buff and discipline stance durations with glowing cyan progress bars and countdowns (`[ ACTIVE: Xs ]`) before transitioning into cooldown.
  - **Smart Readiness & Condition Diagnostics**: Pinpoints the exact reason why an ability is gated: `[ READY ]`, `[ LOW END ]` (with required vs current endurance values), `[ LOW MANA ]`, `[ NEED BURN ]`, `[ NEED BOSS ]`, `[ MIN XTAR ]`, `[ LOCKED ]`, and `[ BLOCKED ]`.
  - **EverQuest Shared Timer Group Detection**: Identifies and badges EQ discipline and skill timer groups (`[T1]`, `[T2]`, `[T4]`, etc.) to clearly highlight shared cooldown lockouts.
  - **Compact Mode & Streamlined Screen Space Footprint**:
    - Reduced default window footprint to a sleek 500x340 overlay with tight padding (`CellPadding 3,2`, `ItemSpacing 4,3`, `FramePadding 3,2`).
    - Merged multi-line toolbars into a clean 2-line header: Line 1 hosts live counters (`R:5 A:1 CD:2`), `[HUD]/[Table]` toggle, `Lock` checkbox, `Compact` checkbox, and inline `Tune` toggle; Line 2 provides compact category, status, sort, search, and alpha controls.
    - Removed unused "Next Up" indicator and star column, streamlining the table directly to Class, Ability Name, Status & Timer, and Action button.
  - **Floating Overlay Controls**: Configurable background transparency slider (`Alpha 0.10 - 1.00`), window lock mode (`NoTitleBar / NoMove / NoResize`), category filters (`All`, `Abilities`, `AAs`, `Disciplines`, `Spells`, `Items`), status filters (`All`, `Ready`, `Cooldown`, `Active`), sort selector (`Time Left`, `Status`, `Priority`, `Class`, `Type`, `Alphabetical`), and live name search box.
  - **In-Place Loadout Tuning**: Optional inline editing controls enabling live adjustment of `Enabled`, threshold `HP %`, and `Burn Only` toggles directly from the monitor table.
  - **UI Integration & Slash Commands**: Added popout toggle buttons across the Main Header Bar (`Cooldowns##hdrCooldowns`), Mini HUD (`CDs##miniCooldowns`), Status Tab (`Popout Cooldowns##statCdBtn`), Abilities Tab, AAs Tab, and Disciplines Tab, along with `/ac cd`, `/ac cds`, `/ac cooldown`, `/ac cooldowns`, and `/triune cd` slash commands.
  - **Unit Tests**: Added test suites in `tests/test_pure_logic.lua` verifying cooldown configuration fields in `defaultCtrl()`, ability base cooldowns, AA/disc timer conversions, shared timer groups, status evaluation, and cooldown-first sorting algorithms.

- **Beneficial Spell Lockout Exemption & Detrimental-Only Lockout Restriction (`triune.lua`).**
  - **Zero Lockout Policy for Beneficial Spells**: Ensured that beneficial spells (heals, buffs, pet summons, cures, teleports) are never locked out under any failure scenario (fizzles, interrupts, "did not take hold", generic failures, or out-of-range).
  - **Authoritative Beneficial vs Detrimental Classification (`isDetrimentalSpell`)**: Added multi-layered action classification checking explicit entry kind tags (`heal`, `buff`, `pet`, `cure`, `util` vs `dd`, `dot`, `debuff`, `nuke`), target token prefixes (`E:` vs `S:`, `P:`, `G:`, `A:`, `C:`), live MacroQuest spell/ability beneficial properties (`Spell().Beneficial()`, `AltAbility().Spell.Beneficial()`, `CombatAbility().Spell.Beneficial()`), era spell database definitions, and fallback keyword heuristics.
  - **Restricted Cast Tracker Failures (`createCastTracker`)**:
    - `isLockedOut(spellName, targetId, kind)` immediately returns `false` for any beneficial spell or ability.
    - `recordFailure(spellName, targetId, reason, ...)` ignores failures on beneficial spells without creating target lockouts, global lockouts, or immunity flags.
    - `onFailureEvent(reason, ...)` skips failure logging on beneficial spells so healer and buffer rotations never stall due to non-stacking buffs or interrupted casts.
    - `runtime.fireAA` updated to maintain cast tracker context (`lastSpell`, `activeSpell`, `activeTargetId`, `activeKind`, `castStartTime`).
    - `runtime.castGem`, `runtime.fireAA`, `runtime.useClickie`, and `combatTick` loop updated to pass `kind` to `isLockedOut` for reliable spell classification.
  - **Unit Tests**: Added test suites in `tests/test_pure_logic.lua` covering `isDetrimentalSpell` classification across beneficial/detrimental spells and verifying that beneficial spells never lock out while detrimental spells retain target immunity, debuff resist backoff, and failure recovery.
- **Function Parameter Consistency (`triune_map.lua`)**:
  - Updated `getZAlphaMultiplier(avgZ, minZ, maxZ, zFilterMode, zDepthFading)` signature to formally declare optional `zFilterMode` and `zDepthFading` parameters with fallbacks to `ctrl`, eliminating language server argument count mismatch warnings.
- **Status Page Active NPC On XTarget Combat State (`triune.lua`)**:
  - **Strict XTarget NPC In-Combat Filter (`hasActualNPCXtarget`)**: Updated the Status tab to only display the engine in combat (`• COMBAT: IN COMBAT` / `Combat: Yes`) when there is an actual live, non-ignored, hostile NPC occupying an active Extended Target (XTarget) slot, preventing lingering out-of-combat timers or idle auto-attack from misrepresenting combat state.
  - **Threat Monitor Threat Filtering**: Updated the active XTarget list generator in the Threat Monitor table to filter out corpses, dead targets, players, friendly pets, and ignored spawns.
  - **Unit Tests**: Added unit tests in `tests/test_pure_logic.lua` covering `hasActualNPCXtarget` across live hostile NPCs, corpses, players, friendly pets, and ignored targets.
- **Combat Engine Spell Gems, Abilities, AA, Disciplines, Buffs & Heals Overhaul (`triune.lua`).**
  - **Out-of-Combat `min_xtar` Gate Fix**: Updated Spell Gems, Clickies, AAs, Autoskill Actions, Priority Conditional Actions, and Disciplines execution loops to allow beneficial actions (buffs, heals, cures, pet summons, resurrection) to execute out of combat when `numXtar == 0`, evaluating `xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)`.
  - **Deferred Target Restoration for Cast-Time Spells & Clickies**: Fixed an issue in `castGem` and `useClickie` where beneficial spells and cast-time clickies targeting friendly party members or pets prematurely retargeted the mob after 60ms during mid-cast. The engine now holds target on the ally throughout the cast bar, and defers restoring the combat mob target until the spell finishes casting in `combatTick`.
  - **Assist Mode Friendly Pet Target Safety**: Fixed a critical target-acquisition bug in `resolveTargetId` where friendly player pets (`stype == 'Pet'`) were rejected in Assist mode by the unengaged mob gate. Added `isHostileTarget(id)` verification so only unengaged hostile enemy pets/adds are gated.
  - **Whole Group Heal & Cure Condition Evaluation**: Updated `conditionMet` to evaluate the lowest health in the group (`pctHP(runtime.lowestHpAlly()) <= pct`) and scan all group members for poison/disease when targeting `F: Whole Group`, ensuring group heals and group cures fire when party members are endangered.
  - **Target Token Beneficial Prefix (`F:`)**: Added `tok:sub(1, 2) == 'F:'` to `isDetrimentalSpell` to immediately recognize all standard friendly target tokens (`F: Myself`, `F: Lowest-HP Ally`, `F: Whole Group`, `F: Pet`, `F: Tank`, `F: Main Assist`) as beneficial actions.
  - **Group Member Cure Counter Inspection**: Enhanced `isPoisonedOrDiseased` to iterate through standard `Group.Member(0..total)` party members and inspect their poison/disease status and counter totals (`CountersPoison`, `CountersDisease`), allowing party curing even without NetBots.
  - **Bard Twist Song Cycling**: Updated `castGem` to allow bard songs with `when == 'twist while fighting'` to bypass the `dur > 0 and buffActive` lockout, ensuring bard song twist rotations continuously cycle and refresh.
  - **Unit Tests**: Added test cases in `tests/test_pure_logic.lua` validating `F:` target tokens and out-of-combat `min_xtar` evaluation.
- **Spell Gems Modernization: Presets, Advanced Triggers, Rebuffing & Live Badges (`triune.lua`).**
  - **Spell Gem Presets & Multi-Spec Profiles**: Added full named loadout preset management (`loadout.presets`) with in-UI selector combo, save/load/delete buttons, and slash commands (`/ac preset [save|load|delete|list]`, `/ac loadout`). Loading a preset automatically memorizes the entire spell set to the spell bar.
  - **Live In-UI Gem Status Badges (`UI.getGemStatusBadge`)**: Added color-coded live feedback badges on every gem row: `[Ready]` (Green), `[CD: X.Xs]` (Gold with active countdown timer), `[Not Memmed]` / `[Memming...]` (Orange), `[Low Mana]` (Red with mana requirement tooltip), and `[Locked Out]` (Purple).
  - **1-Click Gem Slot Reordering (`▲` / `▼`)**: Added interactive Move Up and Move Down buttons on every gem slot for instant swapping and reordering without manual dropdown re-selection.
  - **Advanced Triggers & Conditions**:
    - `target HP between`: Added configurable `Min HP%` and `Max HP%` window for damage-over-time (DoT) and nukes, preventing wasting mana on mobs about to die.
    - `has Curse` & `has Corruption`: Added full cure evaluation (`isCursed`, `isCorrupted`) inspecting `Me`, `Group.Member(i)`, `NetBots`, and `Target` counters.
    - `Aggro on Me` & `my Aggro >=`: Added threat triggers reacting when mob aggro shifts to the player or exceeds a percentage threshold.
    - `Boss Only` Toggle on Gems: Added dedicated Named / Boss mob filtering checkbox per gem slot.
  - **Intelligent Pre-Buff Refreshing & Reagent Verification**:
    - Added proactive out-of-combat buff refreshing (`ctrl.buff_refresh_sec`, default 45s) so buffs are renewed before falling off mid-combat.
    - Added `hasSpellReagents(spellName)` verifying inventory component counts (`Spell.ReagentID`) before casting to eliminate missing reagent chat spam.
  - **Compact UI Layout & Screen Space Optimization**: Streamlined the entire Spell Gems tab with concise status badges (`[RDY]`, `[CD]`, `[UNMEM]`, `[MANA]`, `[LOCK]`, `[--]`), optimized dropdown and slider widths, compact plain numerical text boxes for level range filtering without stepper `+`/`-` buttons, tight button padding, and compact two-row header controls, significantly reducing horizontal width footprint by ~240px.
  - **Dynamic Spell Gem Slot Support (`getNumGems`)**: Automatically queries `mq.TLO.Me.NumGems()` to dynamically display 8 to 12 gem slots based on character AAs and server client capabilities.
  - **Unit Tests**: Added test suite in `tests/test_pure_logic.lua` covering preset snapshots and deep-copy isolation, gem slot swapping, `target HP between` windows, aggro triggers, and reagent verification.

---

## 2026-08-29

- **Project Version Bump (v1.7.5)**: Synchronized version **1.7.5** across `triune.lua`, `triune_updater.lua`, and `README.md`.

- **Norrath Zone Atlas & Travel Explorer (`triune_map.lua`, v1.1).**
  - **Replicated & Enhanced Stock In-Game Map Atlas**: Added full offline and remote zone map browsing to `triune_map`, enabling players to preview and search any zone in EverQuest without traveling or zoning.
  - **Zone Route Finder & Travel Itinerary (`findZoneRoute`)**:
    - Built-in Breadth-First Search (BFS) graph pathfinding engine traversing the entire interconnected Norrathian zone network.
    - Calculates the shortest zone hop route from your current zone to any destination in Norrath, including city stones, planar connections, and overland zone lines.
    - **Step-by-Step Travel Pathway Table**: Displays each zone transition step with zone type/era badges and 1-click `[View]` buttons to inspect the map of any waypoint zone on the journey.
    - **Toolbar Route Badge**: In Atlas Mode, the top navigation toolbar displays an interactive `[Route: N hops]` button that immediately jumps to the step-by-step travel itinerary.
  - **Comprehensive Norrath Zone Registry (`NORRATH_ZONE_REGISTRY`)**: Built-in era-categorized database of ~135 Norrathian zones spanning Classic (Antonica, Faydwer, Odus), Kunark, Velious, Luclin, Planes of Power, Legacy of Ykesha, Gates of Discord, Omens of War, The Serpent's Spine, and Hubs/Special, complete with recommended level ranges and direct connected zone travel links.
  - **Dynamic Map Pack Scanner (`scanMapFiles()`)**: Automatically scans the active map directory (`maps/`, `maps/Brewall/`, `maps/Goodurden/`, etc.) to index available `.txt` map files and detects custom or uncataloged expansion zones on disk.
  - **Zone Atlas Tab (`DrawAtlasTab()`)**:
    - **Fuzzy Search & Filters**: Search zones by name, shortname, era, or continent, with Era combo filter and Type filter (Cities & Hubs, Outdoor & Wilderness, Dungeons, Planes, Raid Zones).
    - **Connected Zone Routing Graph**: Interactive list of adjacent connected zones with 1-click navigation buttons to inspect neighboring zone maps.
    - **Zone POI & Landmark Inspector**: Searchable table of all landmarks and points of interest in the selected zone.
  - **Seamless Live vs. Atlas Mode Switching (`state.viewMode`)**:
    - Full bidirectional history stack (`<` Back and `>` Forward buttons) for traversing explored maps.
    - **1-Click "Return to Live"**: Automatically restores camera follow on the player and re-engages real-time entity tracking.
    - Remote zone viewing safety: Watermark banner and automatic suppression of live entity rendering when viewing non-current zones.
  - **Searchable POI Side Drawer (`DrawPoiDrawer`) & Animated Highlight Pin**:
    - Slide-out POI drawer on the Map View tab with instant filter search across all map labels and points of interest.
    - **Side-by-Side Top-Aligned Layout Fix**: Corrected ImGui cursor screen pos alignment so the POI panel opens cleanly side-by-side with the map canvas from the top of the tab area rather than being displaced to the bottom right of the window.
    - **Responsive Full-Width Layout**: Upgraded POI table with dedicated Landmark Name (Stretch), Coordinates `(Y, X)` column, and `[Focus]` action button, eliminating wasted right-side margins.
    - **1-Click "Focus"**: Automatically centers the viewport on the selected landmark and spawns an animated pulsing locator pin.
  - **On-Canvas Floating Zoom, Auto-Z & Recenter HUD**:
    - Moved `[+]`, `[-]`, and `[⟲]` zoom/reset buttons directly onto the bottom-right corner of the map canvas in a sleek semi-transparent HUD overlay.
    - Removed redundant `Zoom -` / `Zoom +` buttons from the top navigation toolbar to keep the header uncluttered.
    - Added an interactive **Auto-Z Toggle (`[AZ]`)** button directly alongside the on-canvas zoom controls to switch smart floor filtering ON/OFF on the fly, complete with active color states and descriptive hover tooltips.
  - **High-Contrast Dark Line & Label Brightness Correction (`ctrl.boostDarkLines`)**:
    - Standard EQ maps authored for light/parchment backgrounds often use black (`0, 0, 0`) or dark charcoal for walls, contours, and landmark labels.
    - Implemented automatic luminance detection that boosts any low-luminance lines (`lum < 0.25`) to a crisp visible light silver-slate tone (`0.72, 0.76, 0.82`) and dark labels to clean off-white (`0.88, 0.92, 0.96`), ensuring zero black-on-black invisibility across the map canvas and POI tables.
    - Added user toggle in the Settings & Layers tab.
  - **NPC Tracker Table Event & Target Lock Fix (`triune_map.lua` & `triune_track.lua`)**:
    - **Removed Sticky Target Lock (`/stick hold`)**: Removed the `hold` parameter from fallback stick commands (`/stick 10 id %d`), which was previously instructing MQ2Stick to continuously re-acquire and lock target onto the mob, preventing players from clearing or changing targets while navigating.
    - **Navigation Arrival Auto-Stop**: Added proximity arrival detection (<= 12 yards) and mob death detection that cleanly stops `/nav` and `/stick` when reaching the destination.
    - **Unblocked Action Buttons**: Removed `ImGuiSelectableFlags.SpanAllColumns` from the row selection widget in column 0 which was intercepting all mouse clicks across the entire row, restoring full responsiveness to `[Tar]`, `[Nav]`, and `[Map]` action buttons.
    - **Programmatic Tab Navigation (`switchToTab`)**: Added `requestedTab` state and `ImGuiTabItemFlags.SetSelected` integration to ensure clicking `[Map]` on the NPC Tracker or `[View]` in the Atlas tab properly switches active tabs in MacroQuest ImGui.
  - **High-Performance Map Loading, In-Memory Caching & Stutter Elimination**:
    - **Zone Map In-Memory Cache (`zoneMapCache`)**: Cached parsed map layer geometries and label structures in memory. Revisiting zones or switching between Live and Atlas mode loads in 0ms without disk I/O or re-parsing.
    - **Precomputed Line & Label Geometry**: Pre-calculates segment bounding boxes `[minX, maxX, minY, maxY]`, `avgZ`, and luminance boosts during map parse time.
    - **World-Space AABB Frustum Culling**: Viewport bounds are calculated once per frame in world space. 90–98% of offscreen map lines and labels are culled with integer comparisons before coordinate transformations, eliminating ~100,000 `worldToScreen` calculations and `ImVec2` Lua allocations per frame.
    - **Consolidated Batch Spawn Queries**: Collapsed 11 individual protected calls per NPC into a single consolidated protected query, reducing closure allocations and `pcall` invocations from ~5,000 to ~200 per scan tick (96% reduction).
    - **Smoothed Navmesh & Scan Throttles**: Reduced navmesh pathing batch size to 4 with an 80ms interval and increased spawn scan interval to 300ms, eliminating background micro-stutters during combat and zone exploration.
    - **Optimized Folder & File Discovery**: Bypassed redundant probe loops in `scanMapFolders` and `scanMapFiles` when directory contents are already discovered.
  - **Unit Tests**: Added Suites 43 and 44 to `tests/test_pure_logic.lua` covering Atlas history navigation, shortest route pathfinding, dark color boosting, zone cache hit/miss behavior, world AABB frustum culling, and consolidated spawn unpacking.

- **Guild-Only Buffing Restriction (`triune_buffbot.lua`, v1.6).**
  - **Guild Member Gating (`ctrl.guildOnly`)**: Added an optional `Guild Members Only` toggle to restrict buffing services strictly to characters belonging to the same guild as the buffbot (`isSameGuild()`).
  - **Tell & Hail Handling**:
    - Unauthorized tell requests receive an immediate configurable rejection notice (`ctrl.guildOnlyMsg`), logged to the activity feed and console with rate-limit protection.
    - Hails from non-guild characters are silently ignored, preventing public advertisement when the bot is in private guild mode.
  - **Character Config Persistence**: Guild-only restriction state (`ctrl.guildOnly`) and custom tell message (`ctrl.guildOnlyMsg`) are persisted per character/server across sessions in `triune_buffbot_config.lua`.
  - **UI & Live Status Integration**: Real-time display of current guild name and dynamic warning badge if unguilded (`[GUILD ONLY: <GuildName>]` / `[GUILD ONLY: UNGUILDED!]`), with inline checkbox and custom rejection message input box in the Controls tab.
  - **Unit Tests**: Added test suite in `tests/test_pure_logic.lua` covering case-insensitive guild matching, unguilded characters, and cross-guild rejection scenarios.

- **Lua 5.1 Main Chunk 200-Local Variable Refactoring & Consolidation (`triune.lua`).**
  - **Eliminated File-Scope Local Overflow**: Resolved Lua 5.1 / LuaJIT `Only 200 active local variables and upvalues can be existed at the same time` compiler error by eliminating redundant file-scope forward declarations and grouping loose constants into structured tables.
  - **Consolidated Constant & Helper Tables**:
    - Grouped mode and consideration constants into a unified `MODES` table (`PRIMARY`, `SUBMODES`, `PULL_STYLES`, `PULL_CON_LIST`, `DESC`, `SUB_DESC`).
    - Grouped floating combat crit rendering parameters into `CRIT` table (`LIFETIME`, `RISE_SPEED`, `SPREAD`, `BASE_SIZE`, `BIG_SIZE`, `COLORS`).
    - Grouped waypoint serialisation constants into `WP` table (`EXPORT_PREFIX`, `EXPORT_VERSION`, `RS`, `US`, `B64_CHARS`, `B64_LOOKUP`).
    - Grouped ladder navigation constants into `LADDER_CLIMB` table.
    - Grouped pursuit and melee navigation thresholds into `NAV_CONST` table (`MELEE_RANGE`, `LOS_TRUST_RANGE`, `PURSUIT_STALL_TIMEOUT`, `LOS_FLICKER_GRACE`).
    - Grouped class, racial, and universal ability definitions into `CLASS_ACTIONS` table.
    - Grouped UI combo option arrays into `COMBO_OPTIONS`.
  - **Scoped Function Definitions**: Replaced top-level forward declarations (`isUnreachable`, `isIgnored`, `buffActive`, `isCombat`, `resolvePetTargetId`, `isPoisonedOrDiseased`, `maxMeleeDistance`, `desiredRange`, `fullStop`, `onZoned`, `handleCannotSeeTarget`, `revertAttackModeToMelee`, `updateMapRadiusVisuals`, `clearMapRadiusVisuals`) with properly ordered `local function`s and direct bindings on the `runtime` table.
  - **Headroom & Linting**: Reduced total file-scope locals from over 200 down to 161 (over 20% safety margin below Lua 5.1's 200-local ceiling), passing full unit test suite (814 tests) and zero `luacheck` warnings.

- **Separated Abilities & AAs Tabs with Full Combat Actions & Autoskill (`triune.lua`).**
  - **Dedicated Abilities Tab**: Split the previously combined "Abilities & AAs" page into two distinct, dedicated tabs: **Abilities** (`UI.drawAbilitiesTab()`) for innate class combat actions and **AAs** (`UI.drawAATab()`) for Alternate Advancements.
  - **Gestalt Trio Class Mapping & Live Skill Queries (`getClientAbilities`)**:
    - Strictly populates abilities for the character's active 3 Gestalt classes (`myClasses`), guaranteeing that skills for classes you don't have are excluded while all abilities for your 3 classes are included.
    - Queries `mq.TLO.Me.Skill(name)`, `mq.TLO.Me.SkillCap(name)`, and `mq.TLO.Me.AbilityReady(name)` in real time to fetch live trained skill levels and ability status.
    - Includes race-specific abilities (such as `Slam` on large races) when trained on the character.
  - **Full Innate Class Combat Actions**: Comprehensive class action support across all 16 EverQuest classes for innate abilities executed via `/doability` (Monk strikes, Mend, Backstab, Kick, Bash, Slam, Frenzy, Taunt, Disarm, Intimidation, Feign Death, etc.).
  - **Non-Combat Abilities Auto-Attack Pausing (`isNonCombatSkill`)**: Abilities that cannot be used while auto-attacking in EverQuest (e.g. `Begging`, `Pick Pockets`, `Hide`, `Sneak`, `Bind Wound`, `Forage`) automatically pause auto-attack (`/attack off`), execute `/doability`, and seamlessly resume auto-attack (`/attack on`).
  - **Autoskill Toggle (`entry.autoskill`)**: Added an **Auto** checkbox to each combat ability. When enabled, the combat engine automatically fires the ability continuously on cooldown during melee combat against engaged hostile targets without blocking spell gems or disciplines.
  - **Conditional & Priority Execution**: Non-autoskill abilities (e.g. Mend, Feign Death, Taunt, Disarm) support full Target condition, Trigger When rule, HP % threshold, Min XTarget count, Burn Mode gate, and numeric Priority order.
  - **Trained Only Filtering**: Added `Trained Only` (`ctrl.action_trained_only`) toggle verifying live skill levels (`mq.TLO.Me.Skill` / `mq.TLO.Me.Ability`).
  - **Persistence & Migration**: Fully serialized `loadout.actions` with automatic legacy migration of special skills (such as Mend) from `loadout.discs`.
  - **Unit Tests**: Updated `tests/test_pure_logic.lua` with test cases for `actionClassInfo`, `getClientAbilities`, `isActionSkill`, `isSpecialSkill`, `isNonCombatSkill`, and `defaultActionEntry`.

---

## 2026-08-28

- **Target-Aware Spell Failure, Immunity & Lockout System (`triune.lua`).**
  - **Categorized Failure Policies**: Replaced the legacy uniform 2-try/30s lockout with specialized policies tailored to EverQuest combat mechanics:
    - **Mob Immunities**: Instant target-specific immunity registration (`targetImmunities[targetId][spell] = true`) with 0 retries wasted; permanently disables casting that debuff on that mob spawn without blocking other targets.
    - **Non-Stacking Buff Conflicts ("Did Not Take Hold")**: Applies a 120-second target-specific backoff (`targetLockouts[targetId][spell]`) while leaving the buff active for other party members.
    - **Detrimental Resists vs. DD Nukes**: Direct damage spells (DD / DoT) never lock out on resists. Debuffs and CC spells retry up to `cast_max_retries` before applying a temporary target-specific backoff on that target.
    - **Transient Combat Mechanics**: Fizzles and interrupts retry immediately on gem refresh, with a 15-second TTL decay preventing unrelated failures minutes apart from triggering accidental lockouts.
    - **Positional & State Events**: Line-of-sight, out-of-range, and dead target events incur zero lockout penalties.
  - **Target-Scoped Execution**: `castTracker.isLockedOut(spell, targetId)` checks target immunities, target backoffs, and global lockouts, allowing multi-target debuffing and healing without global rotation stalls.
  - **Clickie & AA Integration**: Integrated `isLockedOut` checks into `runtime.useClickie` and `runtime.fireAA` to prevent ability spam on immune or blocked targets.
  - **Accurate Event Attribution & Cast Guard**: Refined event patterns (`Your spell fizzles!`, `#1# resisted your #2#!`, `Your target is immune to #1#`) and added active cast time-window guards to eliminate false positives from group/raid chat.
  - **Zone Lifecycle & Manual Overrides**: Automatically clears mob immunities and target lockouts on zone changes (`onZoned()`), added `/ac clear lockouts` (and `/triune clear lockouts`) slash command, and added a **Clear Lockouts (N)** button to the Settings UI.
  - **Unit Tests**: Updated `tests/test_pure_logic.lua` with test assertions validating target-scoped immunities, non-stacking buff backoff, DD resist resilience, debuff retries, failure count TTL decay, and clearing.

- **Live Status & Engine Diagnostics Tab (`triune.lua`).**
  - **New Primary Status Tab**: Added a dedicated **Status** tab positioned to the left of the Control tab (`UI.drawStatusTab()`), providing a real-time tactical overview of combat engine state and active subsystems.
  - **Live Engine & Mode Banner**: Displays live engine running/paused state, active primary combat mode (Manual, Puller, Assist) and submode (Hunt, Camp, Chase, Backline), combat & attack style (Melee vs Ranged with server attack mode sync), burn state, medbreak/resting state, and active spell casting info.
  - **Current Target & Threat Hero Card**: Renders target name, level, class, race, con color badge, dynamic color-coded HP progress bar (>50% green, 25-50% yellow, <=25% red), distance, line-of-sight status, melee range check, target heading, aggro holder (Target-of-Target), primary and secondary aggro percentages, and quick-action toolbar buttons (`Face Target`, `Attack Toggle`, `Clear Target`, `+ Pull List`, `+ Ignore List`).
  - **Navigation & MQ2Nav Subsystem Diagnostics**: Monitors MQ2Nav plugin status, zone navmesh load status (with inline `[Load MQ2Nav]` and `[Reload Mesh]` action buttons), live navigation destination (target mob, camp location, waypoint patrol, or hunter roam), path length and distance, MoveUtils / stick status, detour obstacle avoidance countdown, nav stall counters, unreachable mob counters, stuck recovery attempts, and zone hazard hotspot counts.
  - **Player, Gestalt Trio & Pet Vitals**: Displays player HP, Mana, and Endurance progress bars, character action flags (Combat, Moving, Ducking, Sitting, Feigning, Levitation), Gestalt Trio class badges with slot theme colors (Arcane Blue, Ember Gold, Jade Green), and active pet vitals (Pet Level, Pet HP bar, Pet Target, and Pet Hold assist threshold status).
  - **Mode Operations & Interactive Extended Target (XTarget) Threat Monitor**: Shows mode-specific operational context (Puller state machine & camp anchor/radius, Assist MA target & chase distance, Manual camp leash, Waypoint patrol progress) and an interactive XTarget monitor table displaying active hostiles with level, distance, health bars, aggro holder, and 1-click targeting buttons.
  - **Toolbar Button Layout Reorganization**: Moved `Cursor Manager` and `Updater` buttons all the way to the far right of the top toolbar in both the Full GUI header (`Open Spellbook` ➔ `Map` ➔ `DPS Parser` ➔ `Compact Mode` ➔ `Cursor Manager` ➔ `Updater`) and Mini HUD overlay (`Reset` ➔ `Map` ➔ `DPS` ➔ `Cursor` ➔ `Update`).
  - **Settings Tab Categorization & UI Cleanup**: Redesigned the Settings tab (`UI.drawSettingsTab()`) into clean, structured collapsible sections: **Character Classes & Profile**, **Combat Style & Positioning** (with engagement radios, distance sliders, LoS re-facing, and spell retry/lockout timers), **Navigation & Hazard Avoidance** (paired toggles, path ratio, hazard radius, zone hazard memory & clear actions), **Closer-NPC Retargeting During Movement** (cone angle & LoS priority toggles, retarget limits), **Resting & Resource Management** (min mana/pull HP thresholds and detailed Med Break resource rules), **Pet Management & Discipline** (assist HP threshold, pet hold toggle), and **Interface, Overlays & Diagnostics** (map circles, crit floaters, compact mode, debug logging).
- **Standalone In-Game 2D Map Replacement & NPC Tracker (`triune_map.lua`).**
  - **Standalone Architecture**: Fully independent MacroQuest ImGui 2D map engine launched via `/lua run triune_map` or `/ac map`, carrying a standalone copy of the unified dark cyan theme.
  - **EverQuest Map Directory File Parser**: Auto-detects EverQuest map files (`maps/` in EQ folder, MQ folder, or custom path) and parses all four zone layers (`<zone>.txt`, `<zone>_1.txt`, `<zone>_2.txt`, `<zone>_3.txt`) plus label files (`<zone>_labels.txt` and `P` map points).
  - **Interactive 2D Map Viewport**: High-performance canvas rendering via `ImGui.GetWindowDrawList` with frustum culling, smooth dragging/panning, mouse-wheel zooming centered on cursor, automatic "Follow Player" mode, coordinate grid lines, and Z-height altitude filtering for multi-story dungeons.
  - **Real-Time Navmesh Reachability Visualization (Green / Red Filter)**:
    - Integrates with MQ2Nav (`mq.TLO.Navigation.PathExists` / `PathLength`) using a throttled background batch queue (evaluating 10 NPCs per tick) to maintain a steady 60 FPS without UI stutter.
    - Three color modes: **Dual Mode** (Con-colored fill with Green/Red navmesh halo), **Navmesh Reachability Only** (Green for pathable, Red for unreachable/blocked), and **Consideration Colors Only**.
    - Filter checkbox: "Pathable Only" instantly removes unreachable NPCs from both the map viewport and the tracker table.
  - **Map Click-to-Move & Interactive Targeting**:
    - Left-click on any NPC node targets the spawn (`/target id <id>`).
    - Double-click on any NPC node targets and starts navigation (`/nav id <id>` or stick fallback).
    - Double-click or Ctrl+Left-Click on open ground calculates world coordinates and commands navigation (`/nav loc <y> <x> <z>`).
    - Draws active navigation line and waypoint marker when MQ2Nav is in progress.
  - **Dedicated NPC Tracking Tab**: Interactive searchable table featuring fuzzy text search, con filters, LoS filters, sort orders, and color-coded `[PATHABLE]` (green with distance) / `[NO PATH]` (red) / `[NO MESH]` status badges.
  - **Triune Integration & Tracker Button Replacement**: Replaced the legacy Zone Tracker toolbar buttons in the main header and Mini HUD with `Map` launching `triune_map.lua`, and routed `/ac track` / `/ac tracker` / `/ac map` slash commands to `triune_map`.
  - **Navigation Destination & Input Safety Fixes (`triune_map.lua`)**: Replaced non-existent `Navigation.DestinationY/X` calls with state-tracked destination coordinates and spawn tracking, pcall-guarded all `Zone.ID` calls, and added safe numeric type validation for `io.MouseWheel` and `io.KeyCtrl` to prevent nil arithmetic crashes.
  - **Player Heading Vector & Active Path Nav Line Fix (`triune_map.lua`)**: Fixed heading directional vector math to match standard clockwise compass degrees in 2D screen space (correcting East/West inversion), prevented premature destination state clearing before MQ2Nav starts, and rendered an emerald green path line with dark contrast borders and a pulsing waypoint bullseye.
  - **Multi-Stage Map Pack Discovery & Custom Subfolder Entry (`triune_map.lua`)**:
    - **4-Stage Resilient Folder Discovery Engine**: Combines `lfs` directory iteration, fast Windows shell querying (`cmd /c dir /a:d /b`), POSIX `find` discovery, and deep map file probing across 50+ known community map pack subfolder names (`Brewall`, `Goodurden`, `Goods`, `MyMaps`, `Custom`, `Atlas`, `Cartography`, `RoF2`, `Live`, `Titanium`, `P99`, `Project1999`, etc.), ensuring all installed map packs are discovered regardless of whether LuaFileSystem is bundled in MacroQuest.
    - **Zone File Directory Probing**: Upgraded directory accessibility tests to verify actual map file headers (`poknowledge.txt`, `qeynos.txt`, `freporte.txt`, `bazaar.txt`, etc.) preventing Windows C-runtime directory file handle failures.
    - **Interactive Add Custom Subfolder UI**: Added an `[Add Subfolder Name]` text box and `[Add / Select Folder]` action button in the Settings tab, allowing any custom or arbitrary map subfolder to be indexed and selected on demand.
  - **Triune Combat Radii, Waypoints & Hazard Hotspot Overlays (`triune_map.lua`)**: Automatically syncs character loadout and zone data from `triune_loadout.lua`. Renders Camp/Combat tether radius circles, dynamic Search / Roam / Pull perimeter radii (anchored to Camp if set or centered dynamically on the Player character), waypoint scan radii and connected patrol routes with pulsing active target pins, and anti-stuck hazard danger rings on the 2D map canvas with independent visibility toggles and a real-time radius slider.
  - **Full Settings & Viewport Zoom Persistence (`triune_map_config.lua`)**: Automatically persists all UI configuration, layer toggles, visual geometry, active map pack selection, search/pull radius settings, and mouse-wheel viewport zoom level per character to `mq.configDir/triune_map_config.lua` with debounced auto-saves on change and on clean script exit.
  - **Window Frame & Scrollbar Cleanup (`triune_map.lua`)**: Removed unused `ImGuiWindowFlags.MenuBar` flag and enabled `ImGuiWindowFlags.NoScrollbar`/`NoScrollWithMouse` with proper child bounds reservation to eliminate unwanted grey vertical and horizontal scrollbars on the right and bottom of the map window.
  - **ImGui Child Window Stack Safety (`triune_map.lua`)**: Replaced temporary child windows in the on-canvas Floor HUD pill and Settings tab with direct canvas rendering and clean tab views, resolving the `Must call EndChild() and not End()` assertion crash.
  - **Smart Auto-Z & Adaptive Floor Isolation (`triune_map.lua`)**:
    - **Dynamic Elevation Clustering**: Analyzes local zone map geometry and vertical histogram distributions around the player to automatically identify floor boundaries and ceiling voids (e.g. Tower of Frozen Shadow, Ssra, Sebilis), eliminating the need to manually adjust Z sliders.
    - **Smooth Alpha Depth Fading**: Implemented smooth alpha falloff on stairs, ramps, and elevation transitions so ascending/descending paths are clearly visible without jarring pop-in or upper/lower floor bleed-through.
    - **Interactive On-Canvas Floor Navigator HUD**: Rendered a floating HUD pill with live floor bounds (`[ Auto-Z: 40..68 ]`), quick-peek floor buttons (`[▲]` and `[▼]`), and a one-click live player floor reset (`[↺]`).
    - **Z-Filter Mode Selector & Persistence**: Added a 3-mode selector (`1: Auto-Z`, `2: Manual Window`, `3: Disabled`) with full persistence in `triune_map_config.lua`.
    - **Unit Tests**: Added Suite 42 to `tests/test_pure_logic.lua` validating floor core opacity, edge fading, adjacent floor ghosting, and culling.
  - **High-Performance Map Parser & Instant Startup Acceleration (`triune_map.lua`)**:
    - **Bulk File Read & Fast Tokenizer**: Replaced line-by-line file streaming and complex multi-group regexes with whole-file memory reads (`f:read('*a')`) and fast LuaJIT byte matching, speeding up map loading by over 10x (parsing 60,000+ lines in $<160\text{ms}$).
    - **Zero-Process Folder Discovery**: Replaced shell `io.popen` and disk write probes with non-blocking `lfs` attributes and fast read-only checks, eliminating the multi-second startup freeze.
    - **Auto-Z Subsampling**: Optimized real-time floor geometry histogram generation with adaptive step subsampling for giant zones.
    - **Progressive Startup Spawn Scan**: Spreads initial spawn acquisition smoothly so the map canvas renders instantly on frame 1 without freezing the game.
- **Standalone Release Updater Modernization & Suite Compatibility (`triune_updater.lua`).**
  - **Complete Suite Manifest Synchronization (`UPDATE_MAP`)**: Added `triune_map.lua`, `triune_buttons.lua`, `triune_track.lua`, and `ingame.cfg` to the updater's download map so all current satellite modules and configs are updated when applying releases.
  - **Dual Config Destination Sync**: Automatically updates both the active `mq.configDir` and the package `TAC/config/` folder if located in separate directories.
  - **Full Script Auto-Reloading on Update (`TRIUNE_SCRIPTS`)**: Expanded the post-update script restart pipeline to detect, stop, and restart running instances of `triune_map`, `triune_buttons`, and `triune_track` in addition to `triune`, `triune_buffbot`, `triune_cursor`, `triune_dps`, and `triune_spellbook`.
  - **Robust JSON Tokenizer (`extractJsonString`)**: Replaced naive regex parsing with an unescaping tokenizer that preserves markdown release notes containing quotes, newlines, tabs, and slashes without premature truncation, and parses GitHub API rate-limit error responses for clear user feedback.
  - **Binary-Safe File I/O**: Switched file writing from text mode to binary mode (`'wb'`) to prevent Windows CRLF line-ending duplication.
  - **Wget Fallback Support**: Added `wget` fallback for individual file downloads in `executeUpdate` if `curl` is missing.
  - **Unit Tests**: Added Suite 41 to `tests/test_pure_logic.lua` covering `cleanTag`, `extractJsonString`, error parsing, and payload tokenization.

---

## 2026-08-28

- **[Experimental] Ignore Distant XTargets When Pulling (`triune.lua`).**
  - **New Puller (Hunt) Option (`ctrl.ignore_distant_xtargets`)**: Added a checkbox next to Max XTarget Chase Range. When checked, an XTarget enemy farther than that range is skipped entirely instead of being chased -- Puller looks for a different mob instead, rather than closing a long distance. Off by default, which keeps the existing behavior of widening the chase range to the search/waypoint scan radius so in-range XTargets aren't ignored.
  - **Mostly Useful For Multi-Puller Groups**: When more than one puller is running, a groupmate's XTarget enemy can land on your own XTarget list far outside your effective range. Without this option, Puller (Hunt) will still chase it since the chase range widens to cover the whole search/waypoint area; with it checked, that distant enemy is left for whoever pulled it and your puller grabs a closer mob instead.

## 2026-08-27

- **Critical Hit Floating Text Overlay (`triune.lua`).**
  - Adds a full-screen transparent ImGui overlay that renders floating damage numbers above the player character whenever a critical hit, crippling blow, deadly strike, spell crit, heal crit, flurry, assassinate, headshot, slay undead, or finishing blow lands.
  - Each floater type has a unique color theme (golden crit, fiery red crippling blow, purple deadly strike, arcane blue spell crit, etc.) with pulsing brightness and gentle horizontal wobble animation.
  - Big hits (>500 dmg) render at a larger font size with an exaggerated pop-in bounce; massive hits (>2000 dmg) get a full rainbow hue-cycling shimmer; hits >1000 dmg spawn orbiting sparkle particles.
  - Text has a black shadow outline for readability over any game background, fades in quickly, floats upward, and fades out over 2 seconds.
  - Capped at 20 simultaneous floaters to prevent AoE spam from overwhelming the overlay.
  - Registered as an independent `mq.imgui.init` callback (`TriuneCritOverlay`) to avoid nested `ImGui.Begin()` violations.
  - Togglable via `ctrl.show_crit_floaters` (Settings tab checkbox: "Critical Hit Floating Text"), persisted with the loadout, enabled by default.
  - Classic EQ progression server message patterns captured: `You score a critical hit! (X)`, `You land a Crippling Blow!(X)`, `You score a Deadly Strike!(X)`, `You flurry`, `You assassinate`, `You headshotted`, `You slay undead`, `You land a Finishing Blow!(X)`, `critical blast!(X)`, `critical heal(X)`, `critical dot(X)`.
- **Auto-Avoid Stuck Hotspots Routing Architecture Rework (`triune.lua`).**
  - **Detour State Machine (`pursuit.detourActive`, `runtime.clearDetour`)**: Replaced stateless per-tick detour recalculation with a locked detour state machine. When routing around a hazard, locks in a stable detour waypoint with a safety timeout and 8-unit arrival threshold, completely eliminating waypoint drifting, `/nav` command spam, and curved movement jitter.
  - **PathLength & Travel Cost Candidate Selection (`calculateDetourWaypoint`)**: Queries `Navigation.PathLength` and straight-line distance to destination for both left and right detour candidates, selecting the candidate that yields the shortest total valid travel path to the target.
  - **Multi-Hazard Avoidance Filter**: Validates candidate waypoints against all active zone hazards (`isCoordInActiveHazard`), discarding candidates that would push the character into a neighboring hazard.
  - **Ground Elevation Clamping**: Validates and interpolates candidate Z elevation between the player, hazard, and target ground heights, preventing airborne or subterranean detour waypoints.
  - **Mathematically Accurate Centroid Calculation (`recordStuckHazard`)**: Replaced running exponential averaging with exact cumulative centroid math ($\text{newPos} = (\text{oldPos} \cdot (N - 1) + \text{pos}) / N$), accurately clustering multiple stuck points into precise geometric hotspot centers.
  - **Comprehensive Safety Resets**: Automatically clears detour state on unstuck maneuvers (`performUnstuck`), unreachable target blacklisting (`markUnreachable`), repositioning events (`repositionCloser`, `handleCantHitFromHere`), target clearing, and script stop (`fullStop`).
  - **Unit Tests**: Updated and expanded unit tests in `tests/test_pure_logic.lua` covering exact 3-hit centroid calculations, detour state clearing, candidate selection with destination cost evaluation, and ground elevation clamping.

- **MQ2Nav Plugin & Zone NavMesh Detection with Center-Screen Warning (`triune.lua`).**
  - **Automatic Plugin Load Attempt on Startup**: On script initialization, Triune now automatically attempts to load `mq2nav` (`/plugin mq2nav`) if it is not already loaded, waiting briefly for MacroQuest to complete initialization.
  - **Zone NavMesh Loaded Check (`navMeshLoaded`)**: Added validation via `Navigation.MeshLoaded()` to verify that a valid `.nav` navmesh is loaded for the character's active zone.
  - **Center-Screen EverQuest `/popup` Warning**: Fires an in-game center-screen `/popup` alert across the middle of the player's screen on startup, when entering a new zone without a navmesh, and when starting combat if either `MQ2Nav` is missing or the zone lacks a navmesh.
  - **GUI Warning Banners & Quick-Actions**: Added dynamic warning notices with `[Load MQ2Nav]` and `[Reload Mesh]` (`/nav reload`) buttons across the main window header bar, the Settings tab under Navigation & Hazard Avoidance, and the Mini GUI HUD overlay.
  - **Combat Execution Gate Warning**: Added warning messages in chat and center-screen `/popup` alerts when starting autocombat (`/ac run`, `/triunerun`, or START buttons) if MQ2Nav is missing or no navmesh exists.
  - **Unit Tests**: Added pure-logic unit test suites (Suites 34 & 35) in `tests/test_pure_logic.lua` covering Navigation TLO presence, Plugin loaded detection, and Zone NavMesh loaded validation.

- **Relocate Start/Pause and Burn Buttons to Top Level & Move Classes to Settings (`triune.lua`).**
  - **Global Top-Level Action Buttons (`UI.drawActionControls`)**: Moved the main `START` / `PAUSE` and `BURN (ON)` / `BURN (OFF)` action buttons out of the `Control` tab and placed them at the top of the main Triune window above all tabs, ensuring combat controls are immediately accessible regardless of active tab.
  - **Character Classes & Loadout in Settings Tab (`UI.drawSettingsTab`)**: Relocated the `Character Classes & Loadout` collapsible header and class picker dropdowns from the top-level window into the `Settings` tab (`ImGuiTreeNodeFlags.DefaultOpen`), decluttering the top window header and organizing loadout configuration with other character settings.
  - **Clean Control Tab Layout (`UI.drawControlTab`)**: Streamlined the `Control` tab to focus exclusively on combat modes, submodes, camp controls, waypoint routing, and target management.

- **Luacheck Static Analysis Fix (`triune.lua`).**
  - **Shadowed `locKey` Variable**: Removed redundant duplicate `local locKey` declaration in `runtime.moveTowardLoc`, resolving a static analysis shadowing warning and ensuring a clean zero-warning Luacheck run across all files.

- **Per-Zone Waypoint Persistence & Named Presets (`triune.lua`).**
  - **Auto-Save/Load Per Zone (`ctrl.zone_waypoints`)**: Waypoint routes and settings (radius, scan radius, loop) are now auto-saved per zone and auto-loaded when you re-enter that zone. Shared across all characters, like zone hazards.
  - **Named Presets (`ctrl.zone_waypoint_presets`)**: Added a dropdown next to the waypoint list, filtered to presets saved for the current zone, plus Save / Load / Edit / Delete buttons. Save prompts for a name (overwrites on duplicate); Edit renames the selected preset. Entries display as `<name> - <zone>`.
  - Loading a preset or the auto-saved "Current" route always restarts at waypoint 1.
  - **Unit Tests**: Added `copyWaypointList` pure-logic tests and extended `defaultCtrl()` field validation for the new fields.
  - **Export/Import Presets**: Added Export/Import buttons for named presets. Export copies a shareable `TACWP1:...` string to your clipboard; Import parses a pasted string, warns if it was exported from a different zone than you're currently in, and prompts to confirm before overwriting a same-named preset. Import strings are parsed as plain data only (never executed as code) and unsupported format versions are rejected with a clear message.
  - **Unit Tests**: Added `sanitizeWpField`, `base64Encode`/`base64Decode` (including round-trip), and `splitByChar` pure-logic tests.

---

## 2026-08-25

- **Fix Puller (Hunt) Mode Ignoring In-Range XTarget Enemies (`triune.lua`).**
  - **Dynamic XTarget Chase Distance (`maxHuntXtarDist`, `maxHuntXtarZ`)**: In `Puller (Hunt)` mode, XTarget mob detection and chase range now scale up to the active hunt / waypoint scan radius (`math.max(ctrl.xtar_nav_dist, scanRadius)` with relaxed Z threshold `maxHuntXtarZ`), preventing the engine from dropping or ignoring aggroed XTarget enemies beyond the default 150-unit slider limit while roaming.
  - **Preempt Ambient Roam Scanning (`firstNPCXtarget` Priority)**: When acquiring new targets in Hunt mode, verifies and engages active in-range XTarget enemies before scanning the zone for distant unaggroed roaming spawns.
  - **Closer-NPC Retargeting Guard (`checkCloserTarget`)**: Added checks ensuring `checkCloserTarget()` will never execute or switch targets away to ambient roam spawns while an XTarget enemy is currently targeted or active on the Extended Target list.
  - **Ambient Spawn Unreachable Blacklist Fix**: Removed aggressive `markUnreachable()` calls in `findRoamTarget()` during candidate scanning loops. Candidate mobs that temporarily lack a path mesh are simply skipped without contaminating `pursuit.unreachableIds` for 60 seconds.
  - **XTarget Hostile Recognition (`isXTargetId`)**: Removed stale unreachable blacklist checks from `isXTargetId()` so active hostile enemies engaged in combat with the player or party are never falsely ignored.

- **Player Ignore List & Automated Ban Notification (`triune_buffbot.lua`).**
  - **Ignore / Ban List Management (`ctrl.ignoreList`, `isPlayerIgnored`)**: Added persistent player ignore list support per character. Tells from ignored/banned players are automatically blocked from receiving the buff menu or queueing buffs.
  - **Customizable Ban Tell Notification (`ctrl.banMsg`)**: Automatically responds to blocked requests with a ban tell notification (defaults to `"You are banned from getting buffs."`, configurable in the UI and persisted to character config).
  - **Dedicated UI Tab ("Ignore List")**: Added a management tab featuring an input text box to add players by name, a one-click "Add Target" button for the current PC target, an interactive table of currently banned players with individual "Remove" buttons, a "Clear All" action, and a live input field for editing the ban tell message.
  - **Hail & Spam Protection**: Silently ignores `/say` hails from banned players and applies standard request cooldowns to prevent tell spam.
  - **Unit Tests**: Added pure-logic unit test suite (Suite 28) in `tests/test_pure_logic.lua` covering case-insensitive matching, whitespace trimming, duplicate prevention, and add/remove helper operations.

---

## 2026-08-24

- **Intelligent Closer-NPC Retargeting & Directional Arc Filtering (`triune.lua`, v1.7.2).**
  - **Configurable Retarget Limits (`ctrl.max_closer_retargets`)**: Replaced the rigid single-switch lock with a configurable slider (`0â€“5`, default `1` / `0` to disable). Allows players in massive open zones to progressively retarget to closer mobs while retaining strict loop limits.
  - **Forward Arc Cone Gate (`runtime.isHeadingInForwardCone`, `runtime.isSpawnInForwardCone`)**: Filters candidates using a $\pm 75^\circ$ forward movement vector calculation. Prevents characters from turning $180^\circ$ backwards to chase mobs that spawned behind them after passing.
  - **Proximity Scan Throttling (`ctrl.closer_scan_interval`)**: Throttles closer-mob proximity searches to 1.0s intervals during transit, eliminating micro-stutters and reducing CPU load in mob-dense areas.
  - **Line-of-Sight Priority (`ctrl.closer_los_priority`)**: If the current distant target is obstructed behind a corner/wall while a closer candidate has clear Line of Sight, relaxes distance-saving thresholds (to 15 units closer and $\le 85\%$ distance) to prioritize immediately engageable mobs.
  - **Anti-Ping-Pong Cycle Blacklisting (`pursuit.cycleTargetIds`)**: Tracks all target IDs engaged or switched during the current pull transit leg, preventing rapid oscillation between two equidistant candidates.
  - **Navigation Settings UI**: Added controls for closer mob switching, forward arc filtering, LoS prioritization, and max retarget count slider in `UI.drawSettingsTab()`.
  - **Project Version Bump (v1.7.2)**: Synchronized version **1.7.2** across `triune.lua`, `triune_updater.lua`, and `README.md`.

- **Intelligent Navigation & Autonomous Hazard Avoidance Suite (`triune.lua`, v1.7.1).**
  - **Stuck Memory & Zone Hazard Clustering (`recordStuckHazard`)**: Automatically logs the coordinates whenever `performUnstuck()` is triggered, clustering nearby points within 14 units into a persistent zone hazard database (`ctrl.zone_hazards` / `ALLDATA.__zoneHazards`). Once a location triggers 2+ stuck incidents, it becomes an active avoidance bubble.
  - **Dynamic Avoidance Detour Waypoints (`calculateDetourWaypoint`, `findPathHazardIntersection`)**: Evaluates movement trajectories in `moveToward` and `moveTowardLoc`. If a path crosses a known hazard bubble, calculates perpendicular detour waypoints to route smoothly around the obstacle before resuming pathing to the destination.
  - **Reverse Breadcrumbs for Safe Camp Return (`recordBreadcrumb`)**: In `Puller (Camp)` mode, records forward movement coordinates into a ring-buffer (`runtime.pullBreadcrumbs`) during the outward `TO_MOB` journey. When returning with aggro (`TO_CAMP`), reverses the exact breadcrumbs back to camp, preventing pathing through uncleared mob rooms or flawed navmesh geometry.
  - **Path Complexity & Sanity Ratio Gate (`ctrl.nav_max_path_ratio`)**: Evaluates `NavMesh PathLength / 3D Distance` in `findRoamTarget()` (default limit: 2.5x). Discards candidate mobs located across thin walls or high balconies that would otherwise cause 300+ unit long dungeon detours.
  - **Proactive Door & Gate Automation (`checkProactiveDoorAndLev`)**: Scans ahead for closed `Switch` objects within 22 units and opens them before collision occurs, maintaining forward running momentum without pausing.
  - **Levitation Duck-to-Clear (`ctrl.nav_levitation_clear`)**: Automatically executes a momentary crouch/duck when floating under door frames and archways with levitation active, eliminating ceiling collisions.
  - **Hazard Management UI (Settings Tab)**: Added navigation controls, sliders for path ratio and hazard radius, live zone hazard statistics, and a one-click `Clear Zone Hazards` button.
  - **Project Version Bump (v1.7.1)**: Bumped version to **1.7.1** across `triune.lua`, `triune_updater.lua`, and `README.md`.

- **Fix Ranged Style Backing Away From Target ("Cannot See Target" Loop) + Settings Override (`triune.lua`).**
  - Lowering the min Ranged distance to 5 (see below) put bow users inside the proximity radius that `handleCannotSeeTarget()`'s melee/ranged check treated as "close enough to be melee," so a normal point-blank LoS hiccup triggered its step-back-and-strafe recovery -- which the Ranged engage logic then immediately undid by closing back to `ranged_dist`, repeating indefinitely. `combat_style == 'Ranged'` now always just re-faces (`/face fast`) instead.
  - Added a Settings tab toggle, "Re-face Instead Of Stepping Back On Lost Line-of-Sight," that applies the same face-only behavior to all three combat styles (off by default -- Melee generally still needs the real step-back to restore LoS).

- **Support Monk's Mend as a Special Skill on the Disciplines Tab (`triune.lua`, `README.md`).**
  - Mend is an innate class skill (no AA/Discipline entry), so it never had anywhere to configure. Added a "Special Skills" section to the Disciplines tab with the same target/trigger/threshold/priority controls as a real Discipline, firing via `/doability` through the existing `isSpecialSkill`/`fireSkill` pipeline. Defaults to self-heal at 75% HP.
  - **Fix (same day)**: Mend wasn't firing -- `isDetrimentalAction()` couldn't classify a bare skill and defaulted to detrimental, requiring a hostile self-target (never true). Fixed by tagging the entry `kind = 'heal'`, backfilled on load for anyone who saved it before the fix.

- **Fix Ranged Auto-Attack Getting Stuck / Toggling Off On Target Switch (`triune.lua`).**
  - Under this server's `#attackmode ranged` scheme, `/attack` is a pure on/off toggle rather than "attack my current target," so switching targets while the toggle was already "on" was a no-op and the character silently stopped firing. Added `ensureRangedAutoAttack(tid)`, a shared helper that detects a genuine target change (`runtime.lastRangedAttackTargetId`) and forces a synchronous `/attack off` -> `/attack on` retoggle (via `mq.delay`) instead of trusting the current toggle state. Wired into all four Ranged auto-attack call sites: `checkCombatStall()`, `combatTick()`'s main Ranged engage block, both puller paths, and the Hunter-mode roam-pull "already engaged" shortcut that previously skipped the retoggle whenever mobs were clustered close together.

- **Lower Minimum Ranged/Spell Combat Distance From 15 To 5 (`triune.lua`, `README.md`).**
  - The Settings tab's "Combat Distance" slider, the `/ac range` command, and the `repositionCloser()` reposition floor all had a hardcoded 15-unit minimum, forcing melee-leaning hybrid builds using Ranged/Spell style to back out further than intended. Lowered all three to 5, matching the existing Melee Distance floor.

## 2026-08-23

- **Server-Native Ranged Attack Mode Replaces `/autofire` for Ranged Style (`triune.lua`).**
  - `Me.AutoFire` never reflects real state on this server, so general Ranged-style combat and Ranged pulling now track attack mode via a new `TriuneAttackModeChanged` chat event watching the server's `#attackmode` feedback line (`runtime.serverAttackMode`), and drive Ranged combat through `#attackmode ranged` + plain `/attack on` instead of `/autofire`. Auto-reverts to `#attackmode melee` on style change or full stop (`revertAttackModeToMelee`). Updated `handleCannotSeeTarget()`'s melee/ranged heuristic accordingly. `pull_style == 'Ranged'` combined with a Melee/Spell combat style (bow-tag then melee/spell) is unaffected and still uses `/autofire`.

- **Ranged Pulling: Aggressive Close-and-Fire (`triune.lua`).**
  - Ranged pulls previously stopped at the loose `pull_engage_dist` (100) and waited passively for the mob to close the gap. Both puller paths (`pullerTick()`'s Camp-mode pull and `combatTick()`'s Hunter-mode roam pull) now decouple movement from the attack trigger, closing to true `ranged_dist` engagement range while already firing.

- **CI Testing Infrastructure (`ci.yml`, `tests/`).**
  - **Luacheck static analysis**: Added `.luacheckrc` config and CI job for Luacheck linting. Catches typos, unused variables, shadowed locals, and undefined global references across all Lua files.
  - **Pure-logic unit tests**: Added `tests/test_pure_logic.lua` with 555 assertions across 28 test suites covering `triune.lua` (`sanitizeModeConfig`, `toCanonicalClassAbbr`, `parseClassLine`, `cleanSpellName`, `normalizeSpellName`, `defaultsForKind`, `defaultCtrl` shape validation, `idxOf`, `isSpecialSkill`, `aaTier`, `fmtSec`, `baseTok`, `normalizeCommandKey`, `sungKey`, `classPlausible`, `serialize`, `extractConName`, and cast tracker lockout/retry logic), `triune_dps.lua` (`cleanLine`, `parseDamageValue`, `isValidMobName`, `getVerbCategory`, `calculateCategoryTotals`, `getFightDPS`), `triune_buffbot.lua` (`parseBuffRequest`, `isThankYou`), and `triune_data.lua` schema/level validation. Tests extract functions directly from source and run under plain LuaJIT with no MQ dependency.
  - **Theme consistency check**: Added `tests/check_theme_consistency.sh` that extracts pushTheme color/style-var tuples from each satellite module and diffs against the canonical copy. Prevents accidental theme drift when updating the duplicated theme helpers.
- **Fix `parseClassLine` MQSHORT scoping bug (`triune.lua`).**
  - Hoisted `MQSHORT` lookup table from a local inside `toCanonicalClassAbbr` to module scope. `parseClassLine` referenced `MQSHORT` as an upvalue but it was scoped to a different function, causing 3-letter and 2-letter class code lookups to silently error (indexing nil) inside pcall blocks.
- **Sync `triune_updater.lua` theme to canonical copy.**
  - Added 8 missing color entries (CheckMark, SliderGrab, SliderGrabActive, ScrollbarBg, ScrollbarGrab, Tab, TabHovered, TabSelected) and aligned all StyleVar values (ChildRounding, FrameBorderSize, FramePadding, GrabRounding, ItemSpacing, ScrollbarRounding, TabRounding, WindowPadding) to match the canonical satellite theme.
- **Luacheck Static Analysis & CI Diagnostic Cleanups (0 warnings / 0 errors across 15 files).**
  - **`.luacheckrc`**: Added missing MacroQuest runtime globals (`ImGuiTreeNodeFlags`, `ImGuiTabBarFlags`, `ImGuiTabItemFlags`, `ImGuiMod`, `ImGuiKey`), ignored whitespace rules (611, 612, 613, 621) and unused callback arguments (212, 432), and configured legacy/test-extracted file overrides.
  - **Scoping & Variable Fixes (`triune.lua`)**: Hoisted `SLOT_COLORS` to module scope for `drawGestaltLogo()`, assigned `isPoisonedOrDiseased` to its forward-declared local, removed dead `hp` and `haveNPC` writes, eliminated variable shadowing for `t` and `tid` in `combatTick()`, converted single-iteration loop to `next()`, and removed unused local aliases.
  - **Satellite Modules (`triune_track.lua`, `triune_spellbook.lua`, `triune_dps.lua`, `triune_buffbot.lua`)**: Cleaned up unused pcall return variables, passed `windowFlags` in track window, removed dead helper functions, and resolved variable shadowing.

- **Ranged Combat Autofire Parity with Auto-Attack (`triune.lua`).**
  - **Eliminated Rapid Autofire Toggle Overhead**: Removed redundant per-tick `/autofire` commands from individual spell, AA, discipline, ability, and clickie execution routines as well as post-cast checks.
  - **Casting & Command Throttle Protection**: Guarded autofire activation behind `not isCasting()` and added a 1.0-second command debounce (`runtime.lastAutoFireCmdAt`) in `combatTick()` and `checkCombatStall()`, preventing rapid toggle loops caused by calling `/autofire` before `Me.AutoFire` TLO updates.
  - **Comprehensive Range & Facing Management**: Added periodic `/face fast` re-facing, stand-up checks, and out-of-range navigation (`moveToward` closing to `ctrl.ranged_dist`) matching melee auto-attack handling.

- **Automated Clickie Item Management Tab (`triune.lua`, v1.7.0).**
  - **Dedicated Clickies Tab (`UI.drawClickieTab`)**: Added a full-featured "Clickies" tab alongside Spell Gems and Abilities & AAs for managing clickable inventory, bag, and worn items.
  - **Dynamic Cursor Item Addition (`addClickieFromCursor`)**: Added `+ Add Item on Cursor` button that inspects the currently held item on the player's cursor, validates its clickable spell effect (`it.Clicky` / `it.Spell`), extracts spell metadata, and assigns smart default triggers (`F: Myself` + `missing buff` for beneficial effects, `E: Current Target` + `in combat` for offensive effects).
  - **Per-Item Trigger Rules & Controls**: Each clickie row includes enable/disable toggle, target dropdown (`TARGETS`), trigger condition dropdown (`WHENS`), threshold slider (`0â€“100%`), Min XTarget requirement (`1â€“10`), Burn Mode checkbox (`burn_only`), and priority reordering buttons (`â–²` / `â–¼`).
  - **Combat & Out-of-Combat Automation (`runtime.useClickie`)**: Seamlessly integrated clickie execution into `autocombatTick()`. Automates buff maintenance out of combat and emergency heals/offensive clickies in combat with item readiness verification (`Me.ItemReady` / timer check), movement guards, and throttle timers.
  - **Full Persistence Support**: Updated `collectEntry()`, `applyEntry()`, and `onCharacterChanged()` to save and restore `loadout.clickies` directly in `triune_loadout.lua`.
  - **Project Version Bump (v1.7.0)**: Bumped version to **1.7.0** across `triune.lua`, `triune_updater.lua`, and `README.md`.
- **Minimum Pull HP % Threshold & Out-of-Combat Rest System (`triune.lua`).**
  - **Configurable Min Pull HP % Setting (`ctrl.pull_min_hp_pct`)**: Added a slider (`Min Pull HP %`, 0â€“95%, default 0 / disabled) in both the Settings tab (under *Health & Mana Management*) and the Control tab (under *Puller Mode Controls*).
  - **Automated Out-of-Combat Resting (`checkPullHpRest`)**: When Puller mode is active (both *Hunt* and *Camp* submodes) and player HP drops below the threshold, pulling and waypoint navigation pause immediately, non-engaged targets are cleared, and the character sits out of combat until HP recovers to 100%.
  - **Combat & Aggro Safety Guards**: Integrates thorough checks (`isCombat()`, hostile XTargets, `Me.Combat()`, `CombatState == 'COMBAT'`). If an enemy attacks while resting, the character immediately stands up (`/stand`) and engages/defends without delay.
  - **Mini HUD Status Indicator**: Added `HP RESTING` badge in the compact Mini HUD when resting for HP.
  - **Slash Commands**: Added `/ac pullhp [0-95]` (alias `/ac minhp`) to inspect or configure the threshold via chat.
- **NavMesh Unpathable Mob Loop & Erroneous Repositioning Fix (`triune.lua`).**
  - **Eliminated Erroneous `performMeshRecovery()` Loop**: Removed the flawed `performMeshRecovery()` routine and `runtime.meshPathFails` counter that incorrectly assumed the *player* was standing off the navmesh whenever candidate roaming spawns failed `mq.TLO.Navigation.PathExists()`. This bug caused characters to endlessly jump forward, backward, strafe left/right, and run `/nav reload` whenever unreachable mobs (e.g. on ledges, in locked rooms, or across unmeshed gaps) existed in the zone.
  - **Smart Unreachable Mob Caching (`markUnreachable`)**: In `findRoamTarget()`, when `Navigation.PathExists('id ' .. sid)` returns false for a distant spawn, that specific NPC is now marked unreachable via `markUnreachable(sid)` (60-second TTL). This immediately skips that spawn on subsequent scan passes without lagging the navigation engine.
  - **Unblocked Waypoint & Idle Fallthrough**: Cleaned up `pullerTick()` and `combatTick()` (Hunter mode) roam fallthroughs, allowing characters to smoothly advance to waypoint patrols (`runtime.wpTick()`) or wait for spawns rather than getting trapped in repositioning loops.
- **Pet Summon Recasting & Auto-Association Fix (`triune.lua`, v1.6.14).**
  - **Self-Healing `conditionMet('missing pet')`**: Overhauled `'missing pet'` trigger condition evaluation. Instead of exclusively checking `petState.myPets[cls]`, `conditionMet` now validates live pets via `mq.TLO.Me.Pet.ID()` and `getAllMyPets()`. If the character already has an active living pet belonging to them and unclaimed by another pet class, it is automatically claimed for that class and returns `false`, eliminating infinite pet summon recasting loops.
  - **Isolated `petState.lastCastCls` Tracking**: Restricted `petState.lastCastCls` assignment to pet-summoning actions (`when == 'missing pet'` or `kind == 'pet'`) in `castGem`. Removed conflicting `lastCastCls` assignments from `fireAA`, `fireDisc`, and `fireSkill` so non-pet abilities no longer overwrite the class tag during long pet cast times.
  - **Robust Combat Tick Pet Assignment**: Enhanced `combatTick` pet observation on spawn to clear `lastCastCls` upon assignment and fall back to assigning newly detected pets to the first unassigned pet class in the trio if `lastCastCls` was not explicitly set (e.g. manual summoning).
  - **Spell Categorization Refinement (`mapTLOCategoryToKind`)**: Beneficial spells with active duration (`dur > 0`) are now correctly categorized as `buff` / `pet_buff` (defaulting to `target = 'F: Pet'`, `when = 'missing buff'`), preventing pet buffs (e.g. `Burnout`, `Pet Haste`, `Companion's Health`) and player buffs (e.g. `Elemental Armor`, `Elemental Shield`) from being misclassified as pet summons (`kind = 'pet'`) with impossible-to-satisfy `'missing pet'` triggers.
  - **Type-Safe Numeric Comparisons & Lockout Guards**: Added `tonumber()` coercion guards across `isDiscReady`, `isSkillReady`, `fireAA`, `fireDisc`, `castGem`, `createCastTracker`, and the `table.sort` priority comparator for `eligibleDiscs`, resolving the runtime `combatTick failed: attempt to compare number with string` error.
  - **Project Version Bump (v1.6.14)**: Bumped version to **1.6.14** across `triune.lua`, `triune_updater.lua`, and `README.md`.
- **Multi-Pet Health Tracking & Smart Heal Targeting (`triune.lua`, v1.6.13).**
  - **Dynamic Multi-Pet Discovery (`getAllMyPets`)**: Added `getAllMyPets()` to collect all active living pets belonging to the character by combining `mq.TLO.Me.Pet.ID()`, the multi-class `petState.myPets` table, and scanning nearby friendly spawns verified via `isSpawnMyPet()`.
  - **Smart Pet Target Resolution (`resolvePetTargetId`)**: Overhauled pet target resolution for gems, AAs, and discs configured with target `F: Pet`:
    - **HP-based Heals (`HP <=`, `target HP <=`)**: Evaluates the health percentages of *all* active player pets and targets the pet with the lowest HP percentage, ensuring heals (Cleric, Druid, Shaman, or Magician/Necromancer pet heals) cast no matter which pet took damage.
    - **Buffing (`missing buff`)**: Targets any player pet that is currently missing the specified buff.
    - **Curing (`has Poison/Disease`)**: Targets any player pet currently afflicted with poison or disease debuffs.
  - **Context-Aware `resolveTargetId` Dispatch**: Updated `resolveTargetId` calls across AA, Disc, and Gem evaluation loops in `combatTick` and `reconcileSungBuffs` to pass condition type (`when`), spell/ability name, and threshold percentage.
  - **Automatic Zone Pet Reconciliation**: Added `reconcilePets()` triggering upon zone changes in the main loop so pets that survive zoning are immediately indexed without requiring a script reload or re-summoning.
  - **Project Version Bump (v1.6.13)**: Bumped version to **1.6.13** across `triune.lua`, `triune_updater.lua`, and `README.md`.
- **Updater Phantom-Update Fix (`triune_updater.lua`).**
  - Synced the updater's embedded `VERSION` constant from 1.6.7 to 1.6.12 to match the suite version. The updater compares its own VERSION against the latest GitHub release tag, so the stale constant made every fresh install report "New version available" on first run.
- **Chat Color Code Normalization (`triune.lua`).**
  - Replaced 4 raw ANSI escape sequences (`\127[31m` / `\127[33m`) in class-detection and cast-lockout messages with the MacroQuest-native color codes (`\ar` / `\ay` / `\ax`) used everywhere else in the suite, so messages render correctly instead of printing control characters.
- **Tool-Launch Deduplication (`triune.lua`).**
  - Consolidated 14 identical copy-pasted "stop-if-running / run-if-stopped" tool-launch blocks (header toolbar, Mini HUD, and slash-command handler) into a single new `toggleTool(scriptName, stopCmd)` helper. All original chat messages and the DPS parser's `/dps toggle` special case are preserved exactly.
- **CI Pipeline (`.github/workflows/ci.yml`).**
  - Added a LuaJIT bytecode-compile (`luajit -bl`) syntax check across every `.lua` file in `TAC/`, catching Lua 5.1/LuaJIT-incompatible syntax before release.
  - Added a version-consistency gate that fails CI if `triune.lua`, `triune_updater.lua`, and `README.md` ever drift apart in version.
- **Buffbot User-Controlled Low-Level (<= 46) Buff Checkboxes (`triune_buffbot.lua`, v1.5).**
  - **Per-Spell Low-Level Checkboxes in Controls Tab**: Added an intuitive checkbox next to every memorized spell gem in the Controls tab. Checking the box designates that the spell can land on players Level 46 and below. Unchecked spells are restricted to players Level 47+ (and cast on pets of any level).
  - **Character Config Persistence (`ctrl.allowLowLevel`)**: Checkbox states are automatically saved and loaded per character/server in `triune_buffbot_config.lua` across sessions.
  - **Requester Level Tell Menu Annotations**: Requesters Level <= 46 receive tell menus clearly distinguishing low-level eligible buffs from high-level/pet-only buffs (`[47+/Pet]`).
  - **Player & Multi-Target Request Validation**: When requesters Level <= 46 request buffs in `player` or `both` modes, unchecked spells are skipped for the player with clear feedback tells, while `both` and `pet` modes continue to cast all requested buffs on their pets without restriction.
  - **Pre-Cast Execution Safety Guard**: Re-verifies player target level and checkbox state immediately before casting in `processBuffQueue`, preventing wasted mana, fizzles, or spell bouncing.
  - **Casting Loop Latency & Dead-Time Elimination**: Removed the hardcoded 800ms post-cast sleep, redundant target-acquisition pauses, and duplicate `/face fast` delays in `processBuffQueue`. Replaced them with reactive 50ms spell readiness / global cooldown polling (`mq.TLO.Me.SpellReady()`), casting subsequent buffs instantaneously as soon as the client GCD clears.
  - **Cooldown Skip Guard (> 30s)**: Added `getSpellCooldownSec` using `mq.TLO.Me.GemTimer()`. If a requested spell has more than 30 seconds of recast cooldown remaining, it is immediately skipped with a notification tell to avoid blocking the queue. Tell menus also display active cooldowns > 30s.

> **TLDR:** Added multi-pet health tracking and smart pet heal/buff targeting across all trio pets (v1.6.13), added user-controlled low-level buff checkboxes to Buffbot, eliminated cast dead-time, and added automatic skipping of spells with > 30s recast cooldowns.

---

## 2026-08-22

- **Buffbot Configurable Tell Dispatch Delay & Menu Compaction (`triune_buffbot.lua`, v1.4).**
  - **Configurable Outgoing Tell Dispatch Delay (`ctrl.tellDelayMs`)**: Increased the default outgoing tell interval from 1100ms to 2500ms (2.5 seconds) and added an interactive UI slider (`Tell Dispatch Delay (ms)`, 1000â€“5000ms) with character config persistence. Spacing out outgoing `/tell` packets prevents chat rate limiter kicks on servers with strict anti-flood protections.
  - **Compact Tell Menu Chunking**: Increased line packing threshold in `sendMenuTells` from 75 to 100 characters, condensing memorized buff lists into fewer total messages (reducing overall chat packet volume).
  - **Requester Repeat Cooldown Increase**: Raised default per-character request repeat cooldown to 3 seconds (`ctrl.cooldownSec`) to prevent rapid-fire requests from queuing duplicate tell bursts.

---

## 2026-08-21

- **Buffbot Disconnect Prevention & Anti-AFK Engine Overhaul (`triune_buffbot.lua`, v1.3).**
  - **Simulated DirectInput Hardware Keystroke for Native IdleTimer Reset**: Overhauled the Anti-AFK pulse mechanism to issue `/nomodkey /keypress HOME` every 120 seconds. In EverQuest, slash commands like `/stand`, `/sit`, and `/afk off` do not generate DirectInput hardware events and fail to reset EverQuest's internal `IdleTimer` (`${EverQuest.IdleTime}`), causing the EQ client to auto-camp to Character Select after 15â€“45 minutes of inactivity. Simulating a harmless keypress directly resets the idle timer without breaking meditation or casting.
  - **Auto-Med Sitting Command Rate Limiting**: Added `lastSitAttemptTime` and a 2-3 second throttle to `/sit` execution across Auto-Med idle upkeep, pre-cast mana recovery, and post-cast meditation. Prevents the 100ms main loop from spamming rapid-fire `/sit` packets while waiting for server position acknowledgement, eliminating server-side stance flood and anti-warp kicks.
  - **GameState Validation Guard**: Added an `mq.TLO.MacroQuest.GameState() == 'INGAME'` check to wrap the main loop and mana meditation loops, cleanly yielding when zoning, logging in, or camping rather than executing commands into uninitialized game states.
  - **Radius-Bounded & Capped Pet Discovery**: Constrained secondary and tertiary pet scanning in `getRequesterPets` to `pet radius <maxRange>` and capped inspection to 15 pets. Eliminates O(NÂ²) full-zone linear scans and frame lag freezes in high-population hub zones (e.g. PoK, Guild Lobby) that caused UDP heartbeat timeout disconnects ("Server not responding").
  - **Hail `/say` Rate Limiting**: Increased per-player hail cooldown to 5 seconds and global cooldown to 3 seconds to prevent chat packet flooding when multiple players hail simultaneously.
  - **Cast Bar Registration Verification**: Updated `processBuffQueue` to allow up to 800ms for `mq.TLO.Me.Casting()` to register before waiting for cast completion, preventing network ping from causing premature loop exits or ghost casts.
  - **Memory Table Pruning**: Added a periodic 10-minute maintenance cycle to prune stale entries from `runtime.cooldowns`, `lastTellBySender`, and `lastHailTimes` to guarantee low memory usage during long-running 24/7 sessions.
- **Discipline Command Formatting Fix (`triune.lua`, `triune_buttons.lua`).**
  - Removed surrounding quotation marks when invoking `/disc` commands (`runtime.fireDisc` and button builder). EverQuest's `/disc` parser expects the discipline name as raw arguments (e.g., `/disc Nimble Discipline`), and surrounding quotes could cause the command to fail to execute.

---

## 2026-08-20

- **Hunt Mode Acquire/Drop Spam Loop Fix (`triune.lua`).**
  - When a Hunt-mode target is dropped for failing the Z-elevation (`tooFarZ`) or stationary-distance (`tooFarDist`) validation checks, `markUnreachable(tid)` is now called before clearing the target. This prevents `findRoamTarget()` from immediately re-acquiring the same spawn on the very next tick and producing the endless `Puller (Hunt) target acquired / Target cleared` spam seen when navigation cannot path to a mob that is within scan radius.
  - The blacklist TTL is 60 seconds (shared with navmesh-fail entries), after which the spawn becomes eligible again in case the mob has moved or a path has opened.
  - A human-readable reason (`elevation diff` or `stationary+out-of-range`) is printed when the mob is blacklisted so it is obvious in the MQ chat log what triggered the drop.


- **Spell Gems, Abilities & Disciplines 0% Disabled Logic & Dark Red Sliders (`triune.lua`, v1.6.12).**
  - **Universal 0% Disabled Semantics Across All 3 Tabs**: Setting the percentage threshold slider to `0%` now marks the entry as disabled across **Spell Gems**, **Abilities & AAs**, and **Disciplines**.
  - **Dark Red Slider Styling on Disabled (0%)**: Implemented `pushDisabledSliderStyle` / `popDisabledSliderStyle` to dynamically color the slider box and grab elements dark red (`#731414`) whenever any percentage slider on the Spell Gems, Abilities & AAs, or Disciplines tabs is set to 0%. The slider displays `Disabled` with tooltip guidance to drag above 0% to re-enable.
  - **Engine Gating in `combatTick` & `conditionMet`**: Updated `conditionMet` to immediately return `false` if `pct <= 0`. Added explicit `(pct > 0)` gates to AA execution loops, discipline priority dispatcher, and spell casting loops in `combatTick`.
  - **Default Percentage Values for Spell Types**: Updated `defaultsForKind` to assign appropriate non-zero percentages (e.g. 75% for heals, 95% for direct damage, 98% for DoTs/debuffs, 100% for buffs/pets/utility) upon spell selection and class slot initialization so newly configured entries start enabled.
  - **Comprehensive Tooltips Across Tabs**: Added descriptive tooltips to every control and label across the Spell Gems, Abilities & AAs, and Disciplines tabs, including slot numbers, class owner dropdowns, ability toggles, target conditions, trigger conditions, percentage threshold sliders, min XTarget counts, burn toggles, level band controls, and memorization queue counters.
  - **Safe ImGui Tooltip String Formatting**: Fixed a Dear ImGui format string bug where tooltips containing percentage signs (`%`) or dynamic format strings caused Dear ImGui's C++ binding (`ImGui::SetTooltip`) to interpret `%` as unhandled `printf` format specifiers and render debug error garbage. Added `UI.setTooltip('%s', tostring(txt))` to safely escape all tooltip text.
  - **Main Chunk Local Variable Limit Optimization**: Refactored UI helpers, style applicators, and tracker utilities onto the structured `UI` table, preventing Lua 5.1 / LuaJIT's 200 main-chunk local variable limit from being exceeded.
  - **ImGui Style Color Table Fix**: Fixed an issue where `ImGuiCol` table references were invoked as function calls rather than accessing table enum constants directly, preventing `attempt to call upvalue 'ImGuiColType'` errors during UI rendering.
- **0% HP Mob Target Retention & Death Detection Engine (`triune.lua`, v1.6.11).**
  - **Fixed Premature Target Abandonment at 0% HP**: Resolved an issue where living NPCs with very low hit points (truncating to 0% in EverQuest / MacroQuest) were falsely presumed dead by the combat engine, causing characters to clear target and roam to a new mob while the current enemy was still alive and hitting the party.
  - **Overhauled `isSpawnAlive` Liveness Check**: Removed `((hp or 0) > 0)` requirement from `isSpawnAlive()`. Liveness is now determined strictly by `not s.Dead()`, `s.Type() ~= 'Corpse'`, and `s.State() ~= 'DEAD'`, ensuring living spawns at 0% HP remain recognized as active entities.
  - **Unblocked 0% HP Target Selection & Maintenance (`setTarget`)**: Removed `s.PctHPs() <= 0` restriction in `setTarget()`, allowing characters to acquire and maintain target lock on low-health mobs to deliver the finishing blow.
  - **Corrected Combat Tick Target Drop Guard**: Updated the target validity check in `combatTick()` (Hunt mode) to verify `tspawn.Type() == 'Corpse'` instead of `tspawn.PctHPs() <= 0`, preventing `/target clear` from dropping living targets at 0% HP.
  - **Preserved XTarget Tracking & Combat Status**: Removed `PctHPs > 0` filters from `countNPCXtarget()`, `anyXtarAlive()`, `isXTargetId()`, and `isCombat()`. Ensures the engine maintains combat status and avoids starting med break or disabling burn mode while fighting 0% HP enemies.
  - **Main Assist & Ability Target Resolution Fix**: Removed `hp <= 0` filtering from `resolveTargetId()` and `maTargetId()`, enabling spells, AAs, disciplines, and assist followers to continue attacking and casting on 0% HP mobs until they transition to a corpse.
  - **Roam & Puller Loop Continuity**: Removed `PctHPs > 0` gates from `findRoamTarget()` and `pullerTick()`, preventing the puller from resetting to `IDLE` or switching to distant targets before the active encounter is completed.

---

## 2026-08-18

- **NavMesh Pre-Validation & Autonomous Mesh Recovery Engine (`triune.lua`, v1.6.10).**
  - **Retained `Navigation.PathExists` Target Pre-Validation**: Kept `mq.TLO.Navigation.PathExists` pre-filtering for distant candidate spawns (> 25 units) in `scanSpawns()`, ensuring characters never select or pull NPCs stuck inside walls, ceiling geometry, or impassable rooms.
  - **Autonomous Off-Mesh Repositioning (`performMeshRecovery`)**: Added an automated mesh recovery system that detects when candidate spawns exist within range and elevation settings but cannot be pathed to because the player is standing on a bad mesh polygon or off-mesh. Performs progressive directional nudges (forward, backward, left, right, jump, and `/nav reload`) to re-seat the character onto a walkable mesh polygon so pathing succeeds.
  - **Expanded Proximity Scan Depth**: Increased spawn inspection depth in `scanSpawns()` to 300 spawns to ensure all candidate NPCs within search radius are evaluated even in high-density zones.
  - **Fixed `NearestSpawn` Zero Candidate Bug**: Removed `zradius` from MacroQuest `NearestSpawn(i, search)` query string and shifted elevation bounding entirely to Lua via `pcall(function() return s.Z() end)`. In MacroQuest, passing `zradius` without `loc` caused `NearestSpawn` to test against world elevation 0.0, returning 0 candidates and falsely printing "No NPCs found" when mobs were in range.
  - **Strict Multi-Floor Z Bounding**: Fixed an issue where the engine bypassed the `Max Height Diff (Z)` slider (`ctrl.hunter_z` / `ctrl.camp_z`) when no NPC was found on the player's immediate floor (Tier 1). Tier 2 multi-floor expansion now strictly bounds all queries to the configured max height diff.
  - **XTarget Elevation Gating**: Constrained Extended Target discovery in `findRoamTarget()` (Step 1), `pullerTick()`, and `combatTick()` (Hunt mode) to `math.abs(xt.Z() - myZ) <= maxZ`. Previously, distant-floor adds entering XTarget were acquired across massive vertical distances (up to 150 units 3D) without height checking.
  - **Spawn Z Nil-Safety in `scanSpawns`**: Fixed a bug where `s.Z() or myZ` defaulted to `myZ` when nil, evaluating `math.abs(sz - myZ) <= zLimit` as always true. Now explicitly requires `sz` to be a valid number before evaluating height difference.
  - **Unengaged Target Vertical Retention Leash**: Added vertical height validation to target retention in `combatTick()`. If an unengaged target's elevation difference exceeds `maxZ + 15` (hysteresis) and the character is not engaged in melee combat, the target is cleanly cleared via `/target clear`.
  - **Bounded Detrimental Fallback Targeting**: Added `maxZ` height filtering and `radius` bounding to `resolveTargetId()` for `Nearest Add` and `All Enemies` fallback searches.
- **Puller Target Acquisition & Clear Loop Elimination Engine (`triune.lua`, v1.6.9).**
  - **Eliminated Rapid Target Clear Loops**: Resolved an infinite loop where the puller repeatedly acquired a valid target, printed its distance, and cleared the target on the subsequent frame while remaining stationary.
  - **XTarget Acquisition Distance Alignment**: In `findRoamTarget()`, clamped XTarget discovery strictly to `ctrl.xtar_nav_dist` (default 150 units). Previously, `findRoamTarget` expanded XTarget discovery up to `hunter_radius` (1500 units), which caused distant XTarget adds to be acquired and then immediately dropped by `combatTick` and `moveToward`.
  - **Distance Drop Hysteresis & Navigation Leash**: Added a +35 unit / 30% hysteresis buffer (`dropDist`) to unengaged target range checks in `combatTick()`. This prevents 2D vs 3D distance variance or slight coordinate jitter at the search boundary from triggering instant target drops. In addition, unengaged target drops are suppressed while the character is actively navigating towards the target (`isMoveActive()`).
  - **Submode Level Bounds Separation**: Fixed `findRoamTarget()` and `checkCloserTarget()` defaulting to `pull_min_level`/`pull_max_level` in Hunt submode. `isCampMode` is now strictly enforced so Hunt submode always uses `hunter_min_level` and `hunter_max_level`.
  - **Synchronized Client Target on Spawn Invalidation**: Added explicit `/target clear` when a target is invalidated by level limits or ignore lists at the start of `combatTick()`, ensuring game client target state and engine internal state remain fully synchronized.
- **Pet Buffing Engine & Level-Aware Selection (`triune_buffbot.lua`, v1.2).**
  - **Multi-Pet Discovery & Buffing (Up to 3 Pets)**: Enhanced pet discovery (`getRequesterPets`) to scan both the primary `.Pet` TLO property and all zone pet spawns matching the requester's ID, clean name, Master, or Owner. On multi-class characters with up to 3 active pets (e.g. Necro/Mage/Beastlord), Buffbot automatically discovers and buffs **all** summoned pets in sequence.
  - **Pet Buffing Support (`pet`, `both`)**: Added full support for buffing summoned pets via tell requests. Players can request buffs for their pets only (`pet 1 3`, `1 3 pet`, `p 1 2`) or for both themselves and their pets (`both 1 3`, `1 3 both`, `b 1 2`).
  - **Level Landing Restrictions & No 'All' Option**: Removed all 'all' options from the tell menu, choice parser, and suggested commands. In EverQuest, higher-level spells fail to land on low-level players due to level caps, whereas pets have no spell landing level restrictions. Requiring explicit spell numbers ensures players only request buffs that can land on their character, while retaining the freedom to cast high-level buffs on pets.
  - **Active Pet Presence & Range Validation**: Verifies that the requester has active, living pets summoned within `ctrl.maxRange` before queueing or casting. Sends clear feedback if no pets are summoned or if pets are out of range.
  - **Multi-Target Queue Sequencing & Recovery**: Updates `acquireTarget()` to support pet spawns by ID with fallback recovery via `getRequesterPets()`. Correctly sequences multi-pet queues and sends tell notifications tracking queue positions and individual pet completions.
  - **UI & Configuration Persistence**: Added `Allow Pet Buffing` checkbox toggle (`ctrl.allowPets`) in the Controls tab, persisted per-character to `triune_buffbot_config.lua`. Updated the Active Request Queue table to display target type (`Self` vs `Pet (<PetName>)`) and spawn ID.
- **Pull Style-Aware Hunt Mode Engagement Engine (`triune.lua`).**
  - **Hunt mode now respects `pull_style`**: Previously, Puller Hunt submode ignored the Pull Method setting entirely and always used `combat_style` (melee/ranged/spell) logic to engage. Now Spell, Pet, and Ranged pull styles each have dedicated engagement branches in Hunt mode, matching the Camp mode puller behavior.
  - **Spell Pull**: Closes to `pull_engage_dist` (Engagement Distance slider), faces target, and casts the selected pull spell via `castGem()`. Engages once mob appears on XTarget. Respects spell gem selector and fallback detrimental search.
  - **Pet Pull**: Dispatches pets (`/pet attack` + `#petcmd attack all`) **during navigation** to the target with a 3-second throttle, rather than waiting until arrival. Pet hold is suppressed during approach. Considers mob tagged once on XTarget, pet has aggro, or within 35 units.
  - **Ranged Pull**: Closes to `pull_engage_dist`, then tries Throw Stone ability (`/doability "Throw Stone"`) first. Falls back to ranged weapon autofire (`/autofire on`) if Throw Stone unavailable. Falls back to melee (`/attack on`) if no ranged option exists.
  - **Melee Pull**: Completely unchanged â€” walks to melee range and auto-attacks exactly as before.
  - **Stand Back extended to Hunt**: `pull_stand_back` checkbox and `desiredRange()` now apply to both Hunt and Camp submodes (was Camp-only). `isPullStandBack` gate in auto-attack and combat stall logic also extended.
  - **Post-pull combat_style transition**: After initial tag, `reqRange` switches from `pull_engage_dist` to `desiredRange()` (based on `combat_style`) so the player closes to melee range (Melee style) or stays at ranged distance (Ranged/Spell style) for the actual fight.
- **Two-Tier Z-Plane NPC Target Acquisition Engine (`triune.lua`, v1.6.8).**
  - **Two-Tier Elevation Targeting**: Replaced single-pass proximity roaming with a tiered target acquisition system for Hunt mode (`findRoamTarget`).
    - **Tier 1 (Same Floor / Z Plane)**: First prioritizes NPCs on the player's immediate level/elevation within `ctrl.hunter_z_plane` (default 15 units) using MacroQuest's native `zradius` filter (`npc targetable radius %d zradius %d`) and delta Z validation. Prevents the engine from acquiring mobs on lower/upper floors when valid targets exist on the current level.
    - **Tier 2 (Max Z Range Expansion)**: If (and only if) no valid candidates exist on the player's immediate level, expands vertical scanning up to `ctrl.hunter_z` (default 75 units) to engage mobs on other floors and ledges.
  - **Interactive Floor Height Slider**: Added `Floor Height (Z Plane)` slider (5â€“50 units, default 15) to the Control tab under Puller (Hunt) settings, with detailed tooltip documentation.
  - **Slash Command Controls**: Added `/ac zplane [5-100]` (aliases `/ac huntplane`, `/ac floorz`) to adjust Tier 1 floor height and `/ac huntz [10-300]` (alias `/ac z`) to adjust Tier 2 max vertical difference.
  - **Diagnostic Telemetry**: Enhanced idle search status messages to output both Max Z and Floor Z thresholds (e.g. `(Lvl 1-100, Radius 1500, Max Z 75, Floor Z 15)`).
  - **Configuration Persistence**: Added `ctrl.hunter_z_plane` to character loadout serialization and profile migration in `triune_loadout.lua`.
- **Configurable Melee Range Slider & Dynamic Strike Distance (`triune.lua`, v1.6.7).**
  - **Interactive Melee Range Slider**: Added a dedicated `Melee Distance##meleeRangeSlider` slider (5â€“50 units, default 14) under the Settings tab's Combat Style section on a dedicated row with explicit `changed` detection and auto-saving.
  - **Direct Melee Positioning & Reach Logic (`maxMeleeDistance` & `desiredRange`)**: Overhauled `maxMeleeDistance(id)` and `desiredRange(id)` to directly use the user-configured `ctrl.melee_dist`. The bot now reliably navigates to and sticks at the exact desired melee distance (e.g. 8 for tight stick, 20 for loose melee), bounded safely by mob hitbox limits without ignoring user inputs.
  - **Fixed Reposition & Arrival Distance Stalls**: Fixed `moveToward()` and `repositionCloser()` calculating destination distance from inflated `MaxRangeTo` values (e.g. 70 units), which caused Nav to falsely declare destination reached while 50+ units away from the mob and stall in "Target too far away" loops. Repositioning now always drives the character closer into `desiredRange(id)`.
  - **Loadout Configuration Persistence**: Added `ctrl.melee_dist` to character profile serialization in `triune_loadout.lua`.
  - **Slash Command Control**: Added `/ac range [5-50]` and `/ac style [melee|ranged|spell]` slash commands for easy macro and keybind adjustments.
- **Active Melee Reposition & Step-Back Engine on "Cannot See Target" (`triune.lua`, v1.6.6).**
  - **Reactive Reposition Maneuver (`handleCannotSeeTarget`)**: Added an automated repositioning system that triggers when EverQuest reports `"You cannot see your target."` while engaged in melee combat or within striking range of a hostile target.
  - **Strict Melee Range Contact Gate**: Restricted physical step-back maneuvers strictly to true melee striking contact (`dist <= maxReach + 5`). Distant targets during pulling or travel now only issue `/face fast` to re-align facing vectors without stepping backward.
  - **Progressive Hitbox Escape**: When inside or underneath a mob's bounding box, pauses active stick movement (`/stick pause`), clears forward key states, and performs progressive step-backs (Attempt 1: 250ms back + `/face fast`; Attempt 2: 250ms back + 200ms strafe left + `/face fast`; Attempt 3: 250ms back + 200ms strafe right + `/face fast`) to reposition to the perimeter of melee reach.
  - **Multi-Attempt Obstacle & Door Resolution**: If repeated attempts fail within 4 seconds, attempts opening nearby doors (`tryOpenNearbyDoor`), marks the target unreachable in Puller mode, or executes a directional unstuck maneuver.
  - **Fixed `moveToward` LoS Arrival Short-Circuit**: Resolved a bug in `moveToward()` where selecting a target allowed arrival acceptance within distance range before line-of-sight checks ran, preventing characters from stalling against walls or corners.
  - **Hunter Active Navigation Leash Fix**: Prevented Hunter mode patrol leash checks from clearing an acquired target while the character is actively navigating towards it (`isMoveActive()`), eliminating rapid target clear / re-acquire cycles.
  - **Combat Engagement LoS Guard**: Gated off-nav melee fallback engagement with `hasLoS(id)` to prevent auto-attacking through walls and solid geometry.
- **Fix `ALIAS_CLASS_MAP` nil crash in `isDisciplineSpell` (`triune.lua`).**
  - `ALIAS_CLASS_MAP` was declared as a `local` inside `lookupSpells()`, making it invisible to `isDisciplineSpell()` which referenced it as a global. Hoisted the table to module scope so both functions share the same map. Fixes `attempt to index global 'ALIAS_CLASS_MAP' (a nil value)` crash at line 1511 that cascaded into an ImGui Begin/EndChild mismatch fatal error.

---

## 2026-08-17

- **Safe-Length Tell Chunking & Outgoing Tell Queue (`triune_buffbot.lua`).**
  - **Dynamic Message Packing**: Replaced fixed 300-char string concatenation with a dynamic word-wrap chunker packing spell options into safe lines of $\le 140$ characters (`Buffs (1/2): ...`, `Buffs (2/2): ...`).
  - **Asynchronous Outgoing Tell Queue & Flood Protection**: Created a dedicated outgoing tell queue (`runtime.outgoingTells` & `queueTell`) drained in the main coroutine loop with a 1100ms wall-clock (`mq.gettime()`) pacing interval. This completely bypasses EQ server-side tell flood filters and eliminates dropped lines.
  - **Chat Buffer Truncation Prevention**: Completely eliminates EverQuest chat buffer truncation when memorizing long spell names or large gem bars, ensuring players receive the complete numbered spell menu.
  - **1-Second Silent Request Limiter**: Fixed the request delay to 1 second (`ctrl.cooldownSec = 1`) and removed the rejection tell message when players send rapid repeat requests. Repeats under 1 second are now silently ignored without spamming the requester.
  - **Single Tell Event Listener & Queue Pruning**: Consolidated tell event listeners to a single unified pattern (`#*##1# tells you, #2#`) with millisecond sender deduplication and automatic un-sent queue pruning, eliminating duplicate triggers of lines 1 and 2.
  - **MacroQuest Pipe Delimiter Fix & Safe Message Length**: Removed the `|` pipe character from the final menu tell string and capped spell chunks to $\le 75$ characters with instructions on a dedicated line so every tell packet remains strictly $\le 95$ characters (well below EverQuest client packet limits).
  - **Removed "All" Buffs Option**: Removed `[all] All` from the tell menu, parsing logic, and UI display. Requesters now select specific buff numbers (e.g. `1 3`, `1 2 4`).
  - **Anti-AFK Keep-Alive Engine (`ctrl.antiAfk`)**: Added an automated anti-AFK system that continuously monitors `Me.AFK()` to clear AFK mode immediately (`/afk off`) and performs a periodic 3-minute keep-alive pulse (stand/sit or duck/stand) while idle or medding. Includes a dedicated UI checkbox with character config persistence.
  - **UI Simplification**: Removed the redundant "Player Cooldown" slider from the Controls tab.
- **Active Pet Verification & Pet Command Anti-Spam Gate (`triune.lua`).**
  - **Pet Ownership Verification (`isSpawnMyPet`)**: Added `isSpawnMyPet(s_or_id)` helper verifying that a spawn ID or spawn object explicitly belongs to the player (via `Me.Pet.ID()`, `s.Master.ID()`, `s.Owner.ID()`, or naming conventions like `<Me>'s pet` and `(Owner: <Me>)`).
  - **Strict Active Pet Gating (`hasActivePet`)**: Strengthened `hasActivePet()` to verify both liveness (`isSpawnAlive`) and ownership (`isSpawnMyPet`) on all tracked pet IDs, pruning dead or unowned pet entries.
  - **Eliminated Command Spam Without Summoned Pets**: Switched all pet command gates (`setManualHunterPetHold`, Puller Pet style, Pet combat style, and universal combat tick `#petcmd hold/attack all`) from `hasActivePet() or trioHasPetClass()` to strictly check `hasActivePet()`. If a character has a pet class but has not summoned a pet, pet commands are completely suppressed.
  - **Accurate Startup Pet Reconciliation (`reconcilePets`)**: Updated `reconcilePets()` on script startup to only claim nearby pets within 100 units if `isSpawnMyPet(s)` is true, preventing other players' or NPC pets from falsely registering as the local player's pets.
  - **Zoning State Reset (`onZoned`)**: Added clean resets of `petState` tracking tables, target IDs, and hold status flags when zoning.

---

## 2026-08-16

- **Interactive Tell Menu & Numbered Spell Selection for Buffbot (`triune_buffbot.lua`).**
  - **Dynamic Numbered Tell Menu**: When a player sends a `/tell` to the buffbot, it automatically responds with a numbered menu of all currently memorized spell gems on the bar along with an `[all]` option.
  - **Multi-Spell & All Selection**: Requesters can reply with `'all'` or specific spell numbers (e.g. `'1'`, `'1 3'`, `'1, 2, 4'`), and the buffbot queues and casts only their requested spells. Numbered choices are strictly parsed against the active gem bar, while non-choice tells send the numbered menu.
  - **Direct Spell Gem Casting**: Casts requested spells directly from the character's active spell gems (`Me.Gem(1..NumGems)`) without book scanning, gem swapping, or restoration delays.
  - **Robust Tell Event Detection & Self-Tell Guard**: Added wildcard-tolerant event patterns matching single quotes, double quotes, unquoted messages, and chat lines with client/MQ timestamps. Added sender name sanitization and an explicit self-tell guard preventing the buffbot's own outgoing menu tells (`[all] All`) from triggering self-buffing loops.
  - **Out-of-Range Location Feedback (`/loc`)**: When an out-of-range or distant requester sends a `/tell`, the buffbot replies with its exact `/loc Y, X, Z` coordinates so the player knows where to run to receive buffs.
  - **Active Requester Target & Facing Enforcement**: Added dedicated `acquireTarget()` helper ensuring the buffbot targets the requester by ID or PC name, stands, and faces them (`/face fast`) before casting each requested buff.
  - **Auto Meditate Engine (`ctrl.autoMed`)**: Added intelligent meditation management that automatically sits (`/sit`) to med to 100% mana immediately after buffing completes or when idle. When an incoming buff request arrives while below `minManaPct`, the bot automatically tells the requester that mana is low and meditates until reaching the threshold before buffing them. Configurable via UI checkbox with character persistence.
  - **Continuous Tell Checking & Queue Line Numbers**: Added continuous `mq.doevents()` polling across all casting, gem readiness, and meditation delay loops so incoming tells are received and processed in real-time even while actively casting on someone else. Requesters are given their dynamic queue position / line number (e.g. `You are #2 in line (1 ahead)`) upon choosing buffs.
  - **Interactive Hail Response in /say**: Added automated hail detection (`'Hail, <BotName>'` and nearby `'Hail'`). When hailed, the bot responds in `/say` instructing the player to send a `/tell` to receive buffs (`<Player>, send tell to me to receive buffs!`), with a 3-second anti-spam rate limiter.
  - **Gratitude & Thank-You Tell Response**: Added smart recognition for thank-you messages (`thank you`, `thanks`, `ty`, `thx`, `tyvm`, `tysm`, `much appreciated`, etc.). When a player sends a thank-you tell, the bot immediately and politely responds with `/tell <Player> You're welcome!` without triggering cooldown or range warnings.
  - **Spell Cooldown & Recovery Verification**: Added dedicated `isSpellReady` and `waitForSpellReady` helpers that query `Me.SpellReady(gem)` and `Me.SpellReady(name)` before every cast. If a spell is on recast cooldown or global recovery, the bot waits up to 30 seconds for full recovery before firing `/cast`, preventing failed cast attempts.
  - **Streamlined Control Header & Auto-Save**: Initialized `ctrl.enabled = true` by default and removed redundant Start/Stop and Save buttons, presenting a clean live status bar while configuration changes auto-save immediately.

- **Discipline Duration & Reuse Cooldown Timer Engine (v1.6.5).**
  - **Discipline Readiness Verification (`isDiscReady`)**: Added dedicated `runtime.isDiscReady(name)` helper with multi-tier validation preventing disciplines from re-firing while active or on cooldown.
  - **Active Discipline Stance Tracking (`Me.ActiveDisc`)**: Checks `mq.TLO.Me.ActiveDisc` before attempting discipline activation. Prevents re-firing the currently active discipline or trying to start duration/stance disciplines while another discipline is active.
  - **Discipline Reuse Cooldown Tracking (`Me.CombatAbilityTimer`)**: Queries `mq.TLO.Me.CombatAbilityTimer(name)` for active reuse cooldown ticks and seconds, eliminating false positives from `Me.CombatAbilityReady` on emulators and non-hotbar abilities.
  - **Buff & Song Window Duration Checks**: Checks `mq.TLO.Me.Buff(name)` and `mq.TLO.Me.Song(name)` to ensure disciplines with persistent buff durations (such as Auras or defensive buffs) do not fire while already active on the character.
  - **Endurance Requirement Validation**: Checks `Spell(name).EnduranceCost()` against `Me.CurrentEndurance()` to prevent repetitive failed activation attempts when endurance is depleted.
  - **Software Timer & Duration Fallback (`runtime.discExpires` & `runtime.discCooldown`)**: Records spell duration (`Duration * 6` seconds) and recast time upon firing, locking out the ability until both the active duration and cooldown period run out.
  - **Candidate Selection Filtering (`combatTick`)**: Gated discipline priority queue evaluation behind `isDiscReady(name)` and `isSkillReady(name)` so unready or active abilities are skipped cleanly and lower-priority ready abilities can fire.
  - **Clean State Lifecycle**: Resets discipline software timers on zone changes (`onZoned`) and character death (`deathGuardFired`).
  - **Project Version Bump**: Bumped version to **1.6.5** across `triune.lua`, `triune_updater.lua`, and `README.md`.

---

- **Comprehensive Pet Filtering & Ignore Logic for NPC Target Acquisition (v1.6.4).**
  - **Universal Pet Detector (`isAnyPet`)**: Added `isAnyPet(s)` helper that thoroughly checks `s.Type() == 'Pet'`, `s.Master` existence (ID > 0), `s.Owner` existence (ID > 0), and standard pet clean name naming patterns (`'s pet`, `'s warder`, `'s Familiar`).
  - **Robust Player/Friendly Pet Identifier (`isSpawnPetOrPlayer`)**: Enhanced `isSpawnPetOrPlayer(id)` to accurately detect local player pets, multi-trio pets, group/raid member pets, mercenary pets, and any player-owned pets regardless of whether MacroQuest reports their spawn type as `'Pet'` or `'NPC'`.
  - **Hunter & Puller Roam Target Pet Exclusion (`findRoamTarget`)**: Updated `findRoamTarget` to filter out all pets (`isAnyPet`, `isSpawnPetOrPlayer`, and `isHostileTarget`) when scanning zone spawns for new NPCs to pull or hunt. This guarantees pullers/hunters never initiate combat on player pets, group pets, or summoned NPC minion pets (e.g. necromancer skeletons or magician elementals), ensuring they target and pull the actual master mob instead.
  - **Combat Loop & Auto-Target Protection (`combatTick` & `pullerTick`)**: Added `not isSpawnPetOrPlayer` and `isHostileTarget` guards to `haveNPC` evaluation, camp pull checks, aggro switching (`checkAggroSwitch`), and XTarget list processing (`findFirstNPCXtarget`, `countNPCXtarget`, `isXTargetId`).
  - **Detrimental Targeting Fallback Filtering (`resolveTargetId`)**: Updated `'Nearest Add'` and `'All Enemies'` fallback queries to skip all pets and non-hostiles when resolving auto-cast targets.
  - **Lua 5.1 / LuaJIT 60-Upvalue Limit Architecture**: Bound engine helpers to the structured `runtime` state table before `combatTick()` execution, reducing the closure's outer upvalue footprint down to under 10 and permanently preventing "function has more than 60 upvalues" compiler errors.
  - **Project Version Bump**: Bumped version to **1.6.4** across `triune.lua`, `triune_updater.lua`, and `README.md`.

---

- **Maximum Melee Distance Positioning & Combat Round Range Engine (v1.6.3).**
  - **Dynamic Maximum Melee Reach Calculation (`maxMeleeDistance`)**: Added dedicated `maxMeleeDistance(id)` helper querying `Spawn(id).MaxRangeTo()` and `Target.MaxRangeTo()` with fallbacks, accurately determining the maximum strike range for both small humanoid NPCs and giant/dragon hitboxes.
  - **Precision Max Melee Standing Range (`desiredRange`)**: Refactored `desiredRange(id)` for the `Melee` combat style to position characters comfortably inside maximum strike reach (`math.max(5, math.floor(maxReach - 2))`). This prevents characters from running into the center/hitbox of the mob while keeping all melee attacks connecting reliably.
  - **Continuous Combat Round Range Maintenance**: Every tick of the combat engine actively evaluates `dist <= maxMeleeDistance(id)`. If an NPC moves, paths away, or gets pushed during combat, `combatTick` and post-cast handlers immediately re-initiate movement to restore proper melee distance.
  - **Active Combat Facing & Re-Engagement**: Enhanced combat facing to update every 0.4s during active combat and ensured auto-attack and melee skills stay engaged seamlessly.
  - **Melee Ability & Skill Range Verification**: Updated `isTargetInRange` to verify distance against `maxMeleeDistance` for instant melee disciplines and combat skills (Kick, Bash, Backstab, Flying Kick).
  - **Dynamic Repositioning Handlers**: Updated `repositionCloser()` and `handleCantHitFromHere()` to calculate target distances dynamically based on `maxMeleeDistance() - 2` instead of fixed offsets, preventing characters from unnecessarily rushing into the center of large/dragon hitboxes.
  - **Project Version Bump**: Bumped version to **1.6.3** across `triune.lua`, `triune_updater.lua`, and `README.md`.

- **Unified Live Pet Detection & `#petcmd attack all` / Hold Dispatch Gating (v1.6.2).**
  - **Live Pet Detection Helper (`hasActivePet`)**: Added `hasActivePet()` to safely query `mq.TLO.Me.Pet.ID()` and multi-pet table (`petState.myPets`) using `isSpawnAlive()`, ensuring pet commands are only evaluated and issued when the character actually has a living pet active in the world.
  - **Expanded `PET_CLASSES`**: Added all EverQuest pet-summoning classes (`Nec`, `Mag`, `Bst`, `Enc`, `Shm`, `SK`, `Dru`) to `PET_CLASSES` so Enchanter animations, Shaman spirit wolves, Shadowknight skeleton minions, and Druid pets are recognized alongside Mag/Nec/Bst for automated pet commands and startup reconciliation.
  - **Cross-Mode `#petcmd attack all` Gating**: Updated the universal combat pet handler (`combatTick`) and mode-specific pet triggers (`Puller Hunt`, `Puller Camp`, `Manual`, and `Assist`) to gate on `canCommandPets` (`hasActivePet() or trioHasPetClass()`). This guarantees `#petcmd attack all` fires whenever engaging an NPC in range with an active pet while completely eliminating spam of `/say #petcmd` commands for trios without pets.
  - **Clean Pet Hold Management in Manual Mode**: Gated `setManualHunterPetHold()` behind pet presence checks to prevent unneeded `/say #petcmd hold all` / `/say #petcmd ghold` chat spam when playing non-pet trios.
  - **UI Pet Controls Visibility**: Updated the Control tab to display Pet Settings whenever the trio has a pet class or currently has an active pet summoned.
  - **Project Version Bump**: Bumped version to **1.6.2** across `triune.lua`, `triune_updater.lua`, and `README.md`.

---

## 2026-08-14

- **Ducking State Detection & Un-Duck / Stand Guards across Combat & Casting.**
  - **Comprehensive Ducking Checks**: Added `isDucking()` (`mq.TLO.Me.Ducking()`) and `isSitting()` helpers with `pcall` guards to detect when the player is crouched/ducked.
  - **Combat & Spell Casting Unlock**: Added automatic `/stand` commands before casting spells (`castGem`), firing activated Alternate Advancement abilities (`fireAA`), initiating disciplines (`fireDisc`), triggering combat skills (`fireSkill`), engaging melee auto-attack, engaging ranged auto-fire, and memorizing spells (`memorizeSpell` & `triune_spellbook.lua`). This prevents characters from getting stuck unable to fight or cast if ducked.
  - **Anti-Stuck & Med Break Integration**: Included `Me.Ducking()` in `checkStuck()` and resting state checks so ducked characters are properly handled and restored to standing when combat or movement resumes.

- **Med Break Logic Refinement & Combat / XTarget Safety Guards.**
  - **Comprehensive In-Combat & XTarget Verification**: Gated entering and maintaining a Med Break behind exhaustive combat checks (`isCombat()`, `Me.Combat()`, `Me.AutoFire()`, `Me.CombatState() == 'COMBAT'`, `Me.XTHaterCount()`, `Me.XTAggroCount()`, and scanning all XTarget slots for any live hostile NPCs/Pets).
  - **Non-Hostile / Unreachable Filter Separation**: Ensured friendly players, group/raid members, and player/mercenary pets on XTarget slots are never mistaken for hostile enemies. Added `includeUnreachable` safety flag to `countNPCXtarget()` / `anyXtarAlive()` so unreachable aggro mobs prevent sitting.
  - **Non-Mana Class Support**: Added `MaxMana() > 0` and `MaxEndurance() > 0` validation to prevent pure melee or non-endurance classes from becoming locked in recovery states if thresholds are active.
  - **Smooth Sit Execution & UI Status**: Cleanly executes `/sit` when stationary out of combat and displays `MED BREAK` in Arcane blue on the Mini GUI while resting.

- **"Cannot Hit From Here" Door-Opening Recovery & Close-in Repositioning.**
  - **Chat Event Listeners**: Registered event handlers for `#*#cannot hit#*#from here#*#`, `#*#can't hit#*#from here#*#`, and `#*#not in line of sight#*#`.
  - **Automated Door & Switch Interaction**: When combat reports being unable to strike the target, the engine immediately attempts to click/toggle the nearest door or switch within 25 units (`/doortarget`, `/click left door`, `/click left target`, `Switch.Toggle()`).
  - **Dynamic Unwedge & Repositioning**: Resets pursuit arrival caches, faces the target, executes a backup/strafe/jump maneuver if repeated geometry snags occur in quick succession, and re-engages close-in navigation (distance 6) to re-establish line of sight.
  - **LoS Check in `checkStuck()`**: `checkStuck()` now verifies Line of Sight (`hasLoS`) before assuming arrival near an NPC, allowing door opening and unstuck maneuvers to trigger when separated by a closed door or corner.

- **Refined Nearest NPC Target Acquisition (`findRoamTarget`).**
  - **Direct Sequential Proximity Iteration**: Removed the `SpawnCount` loop limiter in `findRoamTarget()`, which could return 0 on some MQ builds and cause target selection to silently stall. The engine now directly evaluates candidate spawns up to 50 matches and terminates cleanly on falsy returns.
  - **Player & Mercenary Pet Filtering**: Added ownership checks to ensure player-owned and mercenary-owned pets or bazaar traders are never selected as roam/pull targets.
  - **Navigation Path Pre-Validation**: When MQ2Nav is active, distant spawns (> 25 units) are verified for a valid navigation path (`PathExists`) prior to selection, automatically skipping mobs stuck inside unreachable walls or ceiling geometry in favor of reachable NPCs.
  - **Chase-Range XTarget Ingestion**: Synchronized `findRoamTarget()` XTarget evaluation with `ctrl.xtar_nav_dist` so active aggro within chase range is consistently prioritized over distant roam targets.

- **Puller Hunt Mode XTarget Prioritization & Chase Range Enforcement.**
  - **Immediate XTarget Acquisition**: In `Puller (Hunt)` mode, if an alive NPC appears on XTarget within `Max XTarget Chase Range` (`ctrl.xtar_nav_dist`), the bot immediately switches target to the XTarget add rather than continuing to pursue an un-aggroed roam mob.
  - **Chase Range Boundaries**: Enforced `ctrl.xtar_nav_dist` so XTargets beyond the configured chase range are cleared (returning the bot to patrol/hunting) while in-range XTargets are pursued and destroyed.
  - **Fixed Combat Style Spell Check**: Corrected variable check in Puller Hunt attack routine to ensure `Spell` combat style casts detrimental gems appropriately.

- **Fixed `DoCommand - Couldn't parse '/moveto ...'` Error When Pursuing Off-Mesh Spawns.**
  - **Clean Native Fallback in `moveToward`**: Removed an unguarded `/moveto loc` call in `moveToward()` that fired when MQ2Nav had no path (e.g., flying/elevated mobs like sky drakes) and MQ2MoveUtils was not loaded. When MoveUtils is not installed, movement now falls through directly to native EQ keyboard movement (`/face fast` + `/keypress forward hold`) without erroring or stalling.
  - **Native Keypress Release**: Updated `stopMoving()` to release `/keypress forward` when native movement was active for spawn pursuit.
  - **Unified Stuck Detection across Movement Types**: Added native keyboard pursuit state to `isMoveActive()`, ensuring `checkStuck()` actively monitors displacement and triggers `performUnstuck()` maneuvers even when falling back to native movement. Ensured `performUnstuck()` releases all movement types before performing directional unstuck maneuvers.

- **Fixed Manual mode not auto-attacking or closing to melee range.**
  - **Dynamic Spawn Melee Reach (`desiredRange`)**: Replaced the static hardcoded distance check with dynamic spawn reach (`s.MaxRangeTo()`, default 18 units) so character movement does not stall or freeze just outside melee range on larger models or uneven terrain.
  - **Sequential Melee Engagement**: Character navigates directly to melee range first with all abilities/spells suppressed (`engage = false`).
  - **Instant Attack & Combat Unlock**: The instant melee reach is achieved, `/attack on` is turned on and `engage = true` unlocks AAs, discs, and spells.
  - **Consistent Target Reach Calculation**: Updated all mode blocks (`Manual`, `Puller`, `Assist`, `CombatStall`) to pass target ID to `desiredRange(id)` so accurate collision reach is calculated across all combat modes.
  - **Fixed Premature Nav Arrival Shortcut**: Removed the `d <= dist + 20` bypass in `moveToward()` which was causing characters to declare arrival 35+ units away from mobs on XTarget, halting movement before reaching actual melee range and firing spells from distance. Movement now drives all the way to `desiredRange(id)` before stopping and attacking.
  - **Live Combat Diagnostic Telemetry & `/ac debug`**: Added live combat diagnostic logging across all modes (`Manual`, `Puller`, `Assist`), printing real-time target details, 3D distance, melee reach, LoS, navigation plugin states, attack engagement, and cast states to chat. Added `/ac debug` slash command to quickly toggle diagnostics.
  - **Scoped `pull_stand_back` Strictly to Puller Camp Submode**: Fixed an issue where `desiredRange()` returned 100 in `Puller (Hunt)` mode because `ctrl.submode == 'Camp'` was missing from the check. This caused the bot to stop 96-97 units away from mobs in Hunt mode. Also clamped melee repositioning to max 14 units.
  - Fixed crash: `isHostileTarget` was called in `setTarget` (line 4070) but defined as a `local function` 300 lines later â€” added forward declaration.


- **Project Version & Documentation Overhaul (v1.6.1).**
  - Set project version to **1.6.1** across `triune.lua`, `triune_updater.lua`, and `README.md`.
  - Rewrote and simplified `README.md` into a friendly, player-focused guide with a 2-minute quick start guide, clean combat mode breakdown, and full command reference.
  - Added dedicated server context and links for **[Project Triune](https://nms.bestemu.com/)**, highlighting support for 3-class multiclass / gestalt builds.

- **Automated GitHub Release Workflow (`.github/workflows/release.yml`).**
  - Configured automated release notes generation that extracts the latest changelog entry, bullet points, and TLDR directly from `CHANGELOG.md`.
  - Appended structured installation and update instructions to every published release for both new users (`Source code (zip)`) and existing installs (In-Game Updater / `TriuneAutocombat-Update.zip`).

- **Improved Waypoint Patrol Navigation & Pulling in `triune.lua`.**
  - **Smooth Ping-Pong Patrols**: Puller patrol now walks back and forth sequentially between waypoints (`1 -> 2 -> 3 -> 2 -> 1`) instead of making jarring jumps from the last waypoint back to the first.
  - **Instant Patrol on Start**: Fixed an issue where the puller would stand idle when starting or unpausing; patrol traversal now kicks off immediately in both Camp and Hunt submodes.
  - **Closest Waypoint Auto-Pick**: When starting the script or zoning into a new area, Triune automatically finds and begins patrolling from the closest waypoint to your character.
  - **Multi-Tier Movement Fallbacks**: Added smooth 3-stage movement handling: MQ2Nav mesh navigation, MoveUtils coordinate movement, and native EQ movement keys. If a character is off-mesh, movement falls back seamlessly without getting stuck or spamming errors.
  - **Auto-Camp Setup for Pullers**: In Puller (Camp) mode, if no camp is manually set, Triune automatically anchors your camp to Waypoint 1 or your starting location so mobs are brought back to the group smoothly.
  - **Target Acquisition Movement Stop**: The bot now cleanly halts waypoint movement the moment a target is acquired so combat positioning can take over immediately.

- **In-Game Map Lines & Waypoint Overlays.**
  - **Patrol Route Lines on EQ Map**: Automatically draws clean path lines connecting your waypoints directly on Layer 3 of EverQuest's in-game map.
  - **Live Waypoint Markers**: Displays color-coded waypoint circles on the in-game map with labeled arrival radii, highlighting the active target waypoint in bright gold and other waypoints in cyan.
  - **Lag-Free Map Syncing**: Cached waypoint and zone coordinates so map lines only update when waypoints are added, changed, or deleted, eliminating unnecessary disk writes while patrolling.
  - **Live Dynamic Scan Radius Circle**: Uses `/mapfilter castradius` to render a scan radius circle on the map that dynamically follows your character in real-time as you move.

- **Waypoint Scan Radius Controls & Slash Commands.**
  - **Interactive Scan Radius Slider**: Added a dedicated `Scan Radius` slider (20â€“500 units) in the Puller Waypoint Patrol panel alongside the arrival radius slider.
  - **New Slash Commands**: Added `/ac wp scan [20-500]` and `/ac wp radius [5-100]` to tweak patrol search and arrival distances on the fly from chat.

- **Combat Engine Stability & Safety Fixes.**
  - **Safe Spellcasting & Group Checks**: Added safeguards around spellcasting and group queries to prevent errors or freezes during zoning and group roster changes.
  - **Melee Auto-Attack Resumption**: Ensured melee auto-attack immediately re-engages after finishing spell casts in Melee combat style, matching AA and discipline behavior.
  - **MoveTo Re-issue**: Added active movement checks so that if MoveUtils gets interrupted before arriving at a waypoint, the command is promptly re-issued.

- **Player Poison & Disease Affliction Detection Fix in `triune.lua`.**
  - **Accurate Player Debuff Queries**: Replaced the non-existent `spawn.Poisoned()` / `spawn.Diseased()` checks with a dedicated `isPoisonedOrDiseased()` helper that properly inspects `Me.CountersPoison`, `Me.CountersDisease`, `Me.Poisoned`, `Me.Diseased`, and the Debuffs plugin.
  - **Group & NetBots Integration**: Added support for inspecting party and box member affliction states via `MQ2NetBots` and target debuff TLOs, allowing cure spells, AAs (e.g. *Purge Poison*, *Radiant Cure*, *Purify Body*), and disciplines configured with the `has Poison/Disease` condition to trigger promptly.

- **Manual Mode Auto-Attack & Target Engagement Fixes in `triune.lua`.**
  - **Instant Auto-Attack on Target Engagement**: `/attack on` is turned on immediately the instant an NPC is targeted or acquired in Melee combat style without waiting to cross close-proximity range thresholds, ensuring characters enter combat stance immediately upon engagement.
  - **Immediate & Persistent Auto-Attack Engagement**: Auto-attack stays active continuously without turning off until the target is dead.
  - **Uninterrupted Attack Across Spell Casting**: Removed `and not isCasting()` restrictions from `castGem` and enabled instant attack engagement in `setTarget` and `checkCombatStall`.
  - **Direct Manual Engagement Flagging**: Set `engage = true` unconditionally upon targeting a live hostile NPC in Manual mode, ensuring auto-attack (`/attack on`) immediately engages and persists.
  - **Melee Approach Priority (`isMeleeClosing`)**: Prevented long-cast-time spell gems from cancelling movement while approaching targets from a distance in Melee combat style, allowing characters to close in to melee range and begin swinging weapons before pausing to cast spells.
  - **Multi-Tier Combat Movement Fallbacks in `moveToward`**: Integrated smooth 4-tier movement fallbacks (`MQ2Nav` -> `MQ2Stick` -> MoveUtils `/moveto` -> native EQ movement keys & `/face fast`) so characters never get stuck or stand still when closing in to engage targets in unmeshed or off-mesh areas.
  - **Removed Roaming Level Restrictions from Manual Targets**: Eliminated `hunter_min_level` and `hunter_max_level` checks from manual targeting, ensuring players can freely select and engage any mob without being blocked by previous roaming settings.
  - **Dynamic Melee Strike Range**: Enhanced melee auto-attack distance calculation to dynamically check `Target.MaxRangeTo()` and `Target.MaxMeleeTo()`, ensuring large hitboxes (giants, dragons, oversized NPCs) immediately engage auto-attack without stalling.
  - **Target Hostility & Enemy Pet Recognition**: Fixed `isSpawnPetOrPlayer` to distinguish enemy NPC caster pets from friendly/group player pets, allowing hostile pets to be attacked and fought normally.
  - **Manual Mode Watchdog Activation**: Enabled the `checkCombatStall()` auto-attack watchdog for Manual mode to guarantee immediate auto-attack resumption when in range of a live hostile mob.
  - **Unreachable Blacklist Bypass for Manual Targets**: Prevented `isUnreachable` and 15-second non-XTarget timeouts from clearing or dropping manually selected targets.
  - **Ability Readiness in Manual Mode**: Enabled `combatReady` for Manual mode to ensure offensive spells, AAs, and disciplines cast at their respective ranges without requiring point-blank melee proximity.

> **TLDR:** Upgraded to v1.6 with player-friendly documentation and Project Triune multiclass integration. Polished Waypoint Patrol with ping-pong routes, live map lines, dynamic scan sliders, rock-solid movement fallbacks, fixed player poison/disease condition checking for cure abilities, and resolved Manual mode auto-attack and enemy pet engagement gating.

---

## 2026-08-13

- **Natural Auto-Attack Engagement & Mid-Combat Fixes in `triune.lua`.**
  - **Continuous Auto-Attack**: In accordance with EverQuest mechanics, auto-attack turns ON once in melee range and stays on continuously through spell casts, ability usage, and target switches until the mob dies. Removed disruptive mid-fight `/attack off` calls.
  - **Combat State Retention**: Preserved auto-attack engagement across target switches, ability activations (`fireAA`, `fireDisc`, `fireSkill`), and spell gems.
  - **Anti-Target-Flipping Debounce**: Added a 2-second debounce timer and 15-unit distance buffer to aggro switching to prevent rapid target-swapping when multiple mobs are packed close together.
  - **Camp Fighting Positioning**: Melee pullers now step directly into melee range (14 units) of mobs at camp rather than standing stationary out of reach.
  - **Safe Med Breaks**: Low mana/health med breaks will no longer sit down or turn off attack while actively fighting nearby enemies.

- **Faction Consideration Filtering for Puller Mode.**
  - **9-Tier Consideration Filter Grid**: Added multi-select checkboxes across all 9 EverQuest faction tiers (`Scowling`, `Threatening`, `Dubious`, `Apprehensive`, `Indifferent`, `Amiably`, `Kindly`, `Warmly`, `Ally`).
  - **Quick Presets & Slash Commands**: Added one-click presets (**Hostile Only**, **Hostile + Indifferent**, **Select All**, **Clear All**) and `/ac pullcon` chat commands.
  - **Instant Faction Caching**: Verifies mob factions with `/consider` before traveling and caches clean names so non-matching mobs are skipped instantly on future scans. Active XTarget mobs always bypass filters to protect the group.

- **Engine Safety, Scoping & ImGui Improvements.**
  - **Helper Scope Fixes**: Resolved scoping for forward-declared helper functions (`buffActive`, `isGroupOrRaidMember`, `isXTargetId`, `updateMapRadiusVisuals`) to ensure smooth execution.
  - **Disambiguated ImGui Button IDs**: Unique element IDs applied across Manual, Puller, and Assist control panels so buttons never interfere with each other.
  - **Spell Lockout Tracking**: Improved spell failure tracking to correctly retain failure counts on fizzles, resists, and interrupts without premature resets.
  - **Memory & Local Variable Optimization**: Migrated internal caches into structured state tables to keep the codebase well within LuaJIT's local variable limits.

---

## 2026-08-12

- **Clean Pause & Disengagement Across All Modes in `triune.lua`.**
  - **Immediate Spell & Song Stop**: Pausing via UI or `/ac pause` immediately stops active spellcasting (`/stopcast`) and bard songs (`/stopsong`).
  - **Pet Recall on Pause**: Active pets are immediately ordered to hold and disengage (`/pet back off`, `#petcmd hold all`) when pausing.
  - **Movement Cancellation**: Pausing halts all active `/nav`, `/stick`, `/attack`, and `/autofire` movement instantly.

- **Expanded Slash Commands & Help Tab.**
  - **Buffbot Commands**: Added `/ac buffbot`, `/ac buff`, and `/ac buffui` to easily toggle the standalone buffbot tool.
  - **In-Game Chat Help**: Added `/ac help` (and `/ac ?`) to print a clean summary of commands directly to the chat window.
  - **Mode Command Aliases**: Added handy shortcuts like `/ac hunter` (Puller Hunt), `/ac tank` / `/ac garrison` (Assist Camp), and `/ac ranged` / `/ac backline` (Assist Backline).

---

## 2026-08-11

- **Streamlined Primary Combat Modes & Submodes in `triune.lua`.**
  - Consolidated the 11 legacy combat modes into **3 intuitive primary modes**: **Manual**, **Puller** (`Hunt` / `Camp`), and **Assist** (`Chase` / `Camp` / `Backline`).
  - **Automatic Settings Migration**: Automatically updates saved legacy configurations into the new primary mode and submode structure.
  - **Camp Return for Manual Mode**: Added a camp setting and radius slider so manual players automatically walk back to camp when idle after a fight.
  - **Auto-Target XTarget Toggle**: Added a toggle in Manual mode to choose between auto-engaging incoming XTarget enemies or only fighting manually selected targets.

- **Customizable Pull Methods for Puller Mode.**
  - **4 Pull Styles**: Choose between **Melee** (runs up and attacks), **Spell** (casts a chosen spell gem), **Pet** (sends pet to tag from 100 units), or **Ranged** (shoots with bow/throwing).
  - **Engagement Distance Slider (15â€“250 units)**: Customize how close the puller approaches before casting a pull spell, shooting, or sending pets.
  - **Stand Back (Pet Tank / Ranged) Mode**: Lets pets tank while your character stays safely at range without entering melee.
  - **Puller Target Lists**: Integrated Whitelist (**NPCs to Pull**) and Blacklist (**NPCs to Ignore**) directly into the Puller UI.

- **Spell Gem Synchronization & Auto-Memorization Fixes.**
  - **Rank-Aware Spell Matching**: Recognizes spell ranks (`Rk. II`, `Rk. III`) and clean names, preventing false gem mismatch warnings.
  - **Safe Out-of-Combat Memorization**: Queued spell memorization only executes while stationary, out of combat, and not casting, allowing full memorization bars to complete cleanly.
  - **Non-Hostile Targeting Safeguards**: Strict safety gates prevent offensive spells, AAs, and disciplines from ever targeting player pets, group pets, friendly players, merchants, bankers, or quest NPCs.

---

## 2026-08-10

- **Added Standalone Zone NPC Tracker (`triune_track.lua`).**
  - Real-time window listing all NPCs in the zone with live distance updates (in yards), level, consideration color badges, line of sight, and spawn IDs.
  - Color-coded consideration filtering, live search text filtering, and sorting options (Nearest, Farthest, Level, Name).
  - Double-click any NPC row (or click `[Nav]`) to target and navigate straight to that mob.
  - Launch via `/ac track`, `/ac zone`, or the **Zone Tracker** header button.

- **Added Real-Time AA & Platinum Session Rate Tracker.**
  - Live AA/hr and Plat/hr metrics displayed on the main UI header and Mini HUD.
  - Interactive tooltip showing total session elapsed time, start/current balances, and total AAs and Platinum earned with an inline Reset button.

- **Added Compact Floating Mini HUD Mode (`triune.lua`).**
  - Space-saving floating mini window with Start/Pause, mode selector, Burn toggle, session rate banner, and one-click tool launchers.
  - Toggle via `/ac compact`, `/ac mini`, `/ac hud`, or the **Compact Mode** header button.

- **Standalone Cross-Platform Release Updater Improvements.**
  - Improved `triune_updater.lua`, `triune_updater.py`, `update.bat`, and `update.sh` with zero-dependency direct download fallbacks for Windows and Linux.
  - Thread-safe updater execution prevents UI lockups or game crashes during updates.

---

## 2026-08-09

- **Improved Character Class Detection & Manual Pickers.**
  - Enhanced multi-class detection via the EQ Inventory Window to reliably identify all 3 classes on Project Triune characters without relying on window title text.
  - Added full manual class dropdown selectors in the UI to easily set or override trio classes anytime.
  - Fixed "Scribed Only" spell dropdown filtering so scribed spells across all 3 classes populate smoothly.

- **Multi-Step Stuck Recovery Navigation.**
  - Implemented 4-stage directional recovery when navigating around obstacles: back-up and jump, strafe left, strafe right, and unreachable target bypass.

---

## 2026-08-08

- **Offensive Action Safety Gates.**
  - Strictly gated all offensive spells, AAs, disciplines, and auto-attacks behind hostile XTarget verification so friendly players, pets, merchants, and quest givers are never attacked.

- **Just-In-Time Cursor Management.**
  - Optimized cursor clearing so players can freely hold, inspect, and organize items without the script clearing the cursor mid-use.

- **Smoother Travel & Aggro Handling.**
  - Added dynamic closer mob retargeting during long travel paths and pulsing red visual highlights on the BURN button when Burn mode is active.

---

## 2026-08-07

- **Added Standalone ImGui DPS Parser (`triune_dps.lua`).**
  - Real-time combat tracking for player melee, direct damage spells, DoTs, damage shields, and pet damage.
  - Live DPS gauges, attack breakdowns (Min, Max, Avg, Crit %, Accuracy %), and player vs pet damage splits.
  - Retains a history of up to 50 previous fights with an interactive Encounter Inspector and chat reporting (`/dps report [group|say|guild|raid]`).
  - Open via `/dps`, `/ac dps`, or the **DPS Parser** header button.

- **Added Standalone Interactive Buffbot (`triune_buffbot.lua`).**
  - Automated tell-based buff station that memorizes buff spells, responds to incoming `/tell` requests from nearby players, hands out buffs, and restores original spell gems upon stopping.
  - Open via `/ac buffbot` or `/ac buff`.

- **Enhanced Spell Failure & Lockout Management.**
  - Tracks fizzles, interrupts, out-of-range, and immune spells with configurable retry limits and lockout timers to prevent rotation stalls.
  - Added **Min Mana %** threshold slider and automatic active effect checks on DoTs and debuffs to eliminate wasted mana and duplicate casts.
  - Added **Burn Mode** (`/ac burn`) with per-slot **Burn Only** toggles for saving heavy cooldowns and nukes for boss encounters.

---

## 2026-08-05

- **Combat Radius Anchoring & Map Radius Overlays.**
  - Added **Combat Radius** anchor settings to constrain hunting and pulling within a designated area.
  - Added real-time in-game map circles visualizing camp, anchor, and search radiuses.
  - Added **Help Tab** with in-game command and mode reference tables.

---

## 2026-08-01

- **Hunter Mode Aggro Switching & Corpse Filtering.**
  - Immediate target switching to aggressive adds on XTarget with full dead-spawn and corpse filtering.
  - Improved pet dispatching with customizable **Pet Assist At %** threshold slider.
  - Separated operational mode controls into the **Control** tab and global options into the **Settings** tab.

---

## 2026-07-31

- **Multi-Class Spellbook Browser & Cursor Manager.**
  - Added standalone `triune_spellbook.lua` with multi-class spell filtering, category badges, and 1-click gem assignment.
  - Added standalone `triune_cursor.lua` for inspecting cursor items, auto-inventorying (`/ac clearcursor`), and destroying unwanted items.
  - Centralized unified dark theme styling and color-coded class trio emblems across all windows.
  - Performance optimizations to eliminate UI lag when browsing spells and abilities.

---

## 2026-07-30

- **Slash Command Interface & Combat Repositioning.**
  - Standardized `/ac` command interface (`/ac run`, `/ac pause`, `/ac status`, `/ac <mode>`).
  - Added automated combat repositioning when receiving "too far away / get closer" messages.
  - Added lowest-HP NPC targeting logic and XTarget add prioritization.
  - Refactored runtime state into structured tables to ensure long-term stability and responsiveness.

---

## 2026-07-29

- **Initial Multi-Class Combat Engine Release.**
  - Initial implementation of the Triune AutoCombat engine for Project Triune multi-class characters.
  - Added core combat loop, level filtering, pet hold management, and initial loadout persistence.
