# Triune AutoCombat Change Log

## 2026-08-14

- **Fixed Manual mode not auto-attacking or closing to melee range.**
  - **Dynamic Spawn Melee Reach (`desiredRange`)**: Replaced the static hardcoded distance check with dynamic spawn reach (`s.MaxRangeTo()`, default 18 units) so character movement does not stall or freeze just outside melee range on larger models or uneven terrain.
  - **Sequential Melee Engagement**: Character navigates directly to melee range first with all abilities/spells suppressed (`engage = false`).
  - **Instant Attack & Combat Unlock**: The instant melee reach is achieved, `/attack on` is turned on and `engage = true` unlocks AAs, discs, and spells.
  - **Consistent Target Reach Calculation**: Updated all mode blocks (`Manual`, `Puller`, `Assist`, `CombatStall`) to pass target ID to `desiredRange(id)` so accurate collision reach is calculated across all combat modes.
  - **Fixed Premature Nav Arrival Shortcut**: Removed the `d <= dist + 20` bypass in `moveToward()` which was causing characters to declare arrival 35+ units away from mobs on XTarget, halting movement before reaching actual melee range and firing spells from distance. Movement now drives all the way to `desiredRange(id)` before stopping and attacking.
  - **Live Combat Diagnostic Telemetry & `/ac debug`**: Added live combat diagnostic logging across all modes (`Manual`, `Puller`, `Assist`), printing real-time target details, 3D distance, melee reach, LoS, navigation plugin states, attack engagement, and cast states to chat. Added `/ac debug` slash command to quickly toggle diagnostics.
  - **Scoped `pull_stand_back` Strictly to Puller Camp Submode**: Fixed an issue where `desiredRange()` returned 100 in `Puller (Hunt)` mode because `ctrl.submode == 'Camp'` was missing from the check. This caused the bot to stop 96-97 units away from mobs in Hunt mode. Also clamped melee repositioning to max 14 units.
  - Fixed crash: `isHostileTarget` was called in `setTarget` (line 4070) but defined as a `local function` 300 lines later — added forward declaration.


- **Project Version & Documentation Overhaul.**
  - Set project version to **1.6** across `triune.lua`, `triune_updater.lua`, and `README.md`.
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
  - **Interactive Scan Radius Slider**: Added a dedicated `Scan Radius` slider (20–500 units) in the Puller Waypoint Patrol panel alongside the arrival radius slider.
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
  - **Engagement Distance Slider (15–250 units)**: Customize how close the puller approaches before casting a pull spell, shooting, or sending pets.
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
