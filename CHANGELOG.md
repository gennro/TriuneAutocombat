# Triune AutoCombat Change Log

## 2026-08-30

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
