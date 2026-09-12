---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune AutoCombat -- core engine (loadout, combat, movement, plugin host)
-- ----------------------------------------------------------------------------
-- Standalone MacroQuest ImGui script. Run with:  /lua run triune
-- Loads triune_data.lua (produced by extract_spells.py) from your MQ config dir
-- for the real, era-correct spell + activated-AA lists, and persists each
-- character's loadout and settings to triune_loadout.lua next to it.
--
-- This file owns the loadout builder UI, the combat engine (gem / AA / disc /
-- action firing by target + condition + %), movement and navigation, and the
-- plugin host. HUD windows, DPS, inventory, buffbot, map, spellbook and the
-- other tool windows live as plugins under lua/tac/*.lua and talk to this file
-- through the core API built in runtime.initPluginManager().
--
-- NOTE: this file is close to Lua 5.1's limit of 200 active locals in the main
-- chunk. Prefer adding new module-level state and helpers onto `runtime` / `UI`
-- rather than declaring more top-level `local`s.
-- ============================================================================

--[[
Triune Lua navigation guide
1. Core setup and constants
2. Data loading
3. State and runtime storage
4. Persistence
5. Class detection and loadout import
6. UI rendering
7. Combat engine
8. Movement and navigation
9. Main loop
]]

local mq                = require('mq')
local ImGui             = require('ImGui')
local scriptDir         = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path            = scriptDir .. "?.lua;" .. package.path
local VERSION           = '2.15'
local open              = true
local cfg               = mq.configDir

-- ============================================================================
-- Constants / class data
-- ============================================================================
local ALL_ABBR          = { 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm',
    'Nec', 'Wiz', 'Mag', 'Enc', 'Bst', 'Ber' }

-- Canonical class-name-to-abbreviation lookup (module-level so parseClassLine
-- and toCanonicalClassAbbr can both reference it as an upvalue).
local MQSHORT = {
    WARRIOR = 'War', WAR = 'War', WARRIORS = 'War',
    CLERIC = 'Clr', CLR = 'Clr', CLERICS = 'Clr',
    PALADIN = 'Pal', PAL = 'Pal', PALADINS = 'Pal',
    RANGER = 'Rng', RNG = 'Rng', RANGERS = 'Rng',
    SHADOWKNIGHT = 'SK', SHD = 'SK', SK = 'SK', SHADOWKNIGHTS = 'SK',
    DRUID = 'Dru', DRU = 'Dru', DRUIDS = 'Dru',
    MONK = 'Mnk', MNK = 'Mnk', MONKS = 'Mnk',
    BARD = 'Brd', BRD = 'Brd', BARDS = 'Brd',
    ROGUE = 'Rog', ROG = 'Rog', ROGUES = 'Rog',
    SHAMAN = 'Shm', SHM = 'Shm', SHAMANS = 'Shm',
    NECROMANCER = 'Nec', NEC = 'Nec', NECROMANCERS = 'Nec',
    WIZARD = 'Wiz', WIZ = 'Wiz', WIZARDS = 'Wiz',
    MAGICIAN = 'Mag', MAG = 'Mag', MAGICIANS = 'Mag',
    ENCHANTER = 'Enc', ENC = 'Enc', ENCHANTERS = 'Enc',
    BEASTLORD = 'Bst', BST = 'Bst', BEASTLORDS = 'Bst',
    BERSERKER = 'Ber', BER = 'Ber', BERSERKERS = 'Ber',
}

-- the character's gestalt trio (editable). Declared here, before classColor,
-- so slot colors below can be looked up by position in this list.
local myClasses         = {}

-- Set by the "Re-detect" button (drawClassPicker runs inside the ImGui render
-- callback, a non-yieldable thread) and drained in the main loop below. Do
-- NOT call detectClasses()/classesFromInventoryWindow() directly from a UI
-- button handler -- they contain mq.delay() calls (forcing the Inventory
-- window open and waiting for it), and delaying from the ImGui thread is a
-- hard crash: "Cannot delay from non-yieldable thread", which also corrupts
-- ImGui's Begin/End stack and pauses the whole overlay until /mqoverlay
-- resume. Confirmed via a real crash report from a tester.
local reDetectRequested = false

-- theme accents (r,g,b,a 0-1)
local GOLD              = { 1.0, 0.70, 0.54, 1 }
local ARC               = { 0.30, 0.70, 1.0, 1 }
local MUTED             = { 0.49, 0.56, 0.65, 1 }
local GOOD              = { 0.37, 0.88, 0.64, 1 }
local WARN              = { 1.0, 0.72, 0.30, 1 }
local ERR               = { 0.95, 0.35, 0.35, 1 }

-- ============================================================================
-- Data loading
-- ============================================================================
local DATA              = { era_expansion = 5, spells = {}, discs = {}, aas = {} }
local DATA_OK           = false
do
    local paths = { cfg .. '/triune_data.lua' }
    pcall(function()
        if scriptDir then table.insert(paths, scriptDir .. 'triune_data.lua') end
        if scriptDir then table.insert(paths, scriptDir .. '../config/triune_data.lua') end
        if mq.luaDir then table.insert(paths, mq.luaDir .. '/triune_data.lua') end
    end)
    for _, p in ipairs(paths) do
        local f = loadfile(p)
        if f then
            local ok, t = pcall(f)
            if ok and type(t) == 'table' and t.spells then
                DATA = t; DATA_OK = true
                break
            end
        end
    end
end

-- ============================================================================
-- Runtime state
-- ============================================================================
local NUM_GEMS       = 12
local function getNumGems()
    local ng = nil
    pcall(function() ng = mq.TLO.Me.NumGems() end)
    local n = tonumber(ng)
    if n and n >= 8 and n <= 12 then return n end
    return NUM_GEMS
end
local lvlMin, lvlMax = 1, 65

-- loadout.gems[i] = { cls=, spell=, target=, when=, pct= }  (or nil)
-- loadout.aas, loadout.discs, loadout.actions are maps: name -> { cls=, target=, when=, enabled=, pct=, ... }
-- (actions = innate combat abilities, e.g. Kick/Bash/Mend/Backstab/Flying Kick -- fired via /doability)
-- (discs = disciplines, e.g. Defensive/Stonewall/Trueshot -- fired via /disc)
-- (aas = alternate advancements -- fired via /alt act)
local loadout        = { gems = {}, aas = {}, discs = {}, actions = {}, clickies = {}, presets = {} }

-- combat control state (Control tab). NOTE: this is the control surface; wiring it
-- Primary Combat Modes & Submodes
local MODES = {
    PRIMARY       = { 'Manual', 'Puller', 'Assist' },
    SUBMODES      = {
        Puller = { 'Hunt', 'Camp' },
        Assist = { 'Chase', 'Camp', 'Backline' },
    },
    PULL_STYLES   = { 'Melee', 'Spell', 'Pet', 'Ranged' },
    PULL_CON_LIST = {
        'Scowling', 'Threateningly', 'Dubious', 'Apprehensive', 'Indifferent',
        'Amiably', 'Kindly', 'Warmly', 'Ally',
    },
    DESC          = {
        Manual = 'Fights your current or acquired target automatically. Does not roam.',
        Puller = 'Pulling & hunting engine. Hunt roams and solo-kills; Camp pulls mobs back to set camp.',
        Assist = 'Assists the Main Assist. Chase follows MA; Camp holds camp spot; Backline is ranged/caster support.',
    },
    SUB_DESC      = {
        ['Puller:Hunt']     = 'Roams within search radius looking for valid mobs and kills them on the spot.',
        ['Puller:Camp']     = 'Pulls mobs within radius back to set camp location and tanks/fights them at camp.',
        ['Assist:Chase']    = 'Follows Main Assist everywhere and assists on MA target.',
        ['Assist:Camp']     = 'Holds set camp position and assists MA on MA target, returning to camp when idle.',
        ['Assist:Backline'] = 'Ranged/caster support; assists MA without moving to melee range.',
    },
}

local ctrl                   -- forward declaration for lexical scoping in helpers

local function isDucking()
    local d = false
    pcall(function() d = mq.TLO.Me.Ducking() end)
    return not not d
end

local function isSitting()
    local s = false
    pcall(function() s = mq.TLO.Me.Sitting() end)
    return not not s
end

-- Backward compatibility and mode validation sanitizer
local function sanitizeModeConfig(c)
    c = c or ctrl
    if not c then return end
    local m = c.mode
    if m == 'Manual Hunter' then
        c.mode = 'Manual'
        c.submode = 'Hunt'
    elseif m == 'Hunter' or m == 'Pet Tank' then
        c.mode = 'Puller'
        c.submode = 'Hunt'
    elseif m == 'Pull & Assist' then
        c.mode = 'Puller'
        c.submode = 'Camp'
    elseif m == 'Chase Assist' then
        c.mode = 'Assist'
        c.submode = 'Chase'
    elseif m == 'Garrison' or m == 'Tank' then
        c.mode = 'Assist'
        c.submode = 'Camp'
    end

    if c.mode ~= 'Manual' and c.mode ~= 'Puller' and c.mode ~= 'Assist' then
        c.mode = 'Manual'
    end

    if c.mode == 'Puller' then
        if c.submode ~= 'Hunt' and c.submode ~= 'Camp' then c.submode = 'Hunt' end
    elseif c.mode == 'Assist' then
        if c.submode ~= 'Chase' and c.submode ~= 'Camp' and c.submode ~= 'Backline' then c.submode = 'Chase' end
    else
        c.submode = 'Hunt'
    end

    if c.assist_self_defense == nil then c.assist_self_defense = true end
    if c.assist_behind == nil then c.assist_behind = true end
    if c.hunter_z_plane == nil then c.hunter_z_plane = 15 end
    if c.hunter_z == nil then c.hunter_z = 75 end

    if c.check_closer_mobs == nil then c.check_closer_mobs = true end
    if c.max_closer_retargets == nil then c.max_closer_retargets = 1 end
    if c.closer_forward_cone_only == nil then c.closer_forward_cone_only = true end
    if c.closer_los_priority == nil then c.closer_los_priority = true end
    if c.closer_scan_interval == nil then c.closer_scan_interval = 1.0 end
    if c.nav_hazard_avoidance == nil then c.nav_hazard_avoidance = true end
    if c.nav_hazard_radius == nil then c.nav_hazard_radius = 15 end
    if c.nav_hazard_min_hits == nil then c.nav_hazard_min_hits = 2 end
    if c.nav_hazard_max_hits == nil then c.nav_hazard_max_hits = 6 end
    if c.nav_hazard_decay_minutes == nil then c.nav_hazard_decay_minutes = 10 end
    if c.nav_reverse_breadcrumbs == nil then c.nav_reverse_breadcrumbs = true end
    if c.nav_max_path_ratio == nil then c.nav_max_path_ratio = 2.5 end
    if c.nav_proactive_doors == nil then c.nav_proactive_doors = true end
    if c.nav_levitation_clear == nil then c.nav_levitation_clear = true end
    if type(c.zone_hazards) ~= 'table' then c.zone_hazards = {} end
    if type(c.zone_waypoints) ~= 'table' then c.zone_waypoints = {} end
    if type(c.zone_waypoint_presets) ~= 'table' then c.zone_waypoint_presets = {} end

    if c.show_cooldowns == nil then c.show_cooldowns = false end
    if c.show_spellbook == nil then c.show_spellbook = false end
    if c.show_map == nil then c.show_map = false end
    if c.show_auto_aa == nil then c.show_auto_aa = false end
    if c.show_auto_accept == nil then c.show_auto_accept = false end
    if c.show_dps == nil then c.show_dps = false end
    if c.show_inv == nil then c.show_inv = false end
    if c.show_cursor == nil then c.show_cursor = false end
    if c.show_buffbot == nil then c.show_buffbot = false end
    if c.cooldown_alpha == nil then c.cooldown_alpha = 0.90 end
    if c.cooldown_locked == nil then c.cooldown_locked = false end
    if c.cooldown_view_mode == nil then c.cooldown_view_mode = 'table' end
    if c.cooldown_sort_by == nil then c.cooldown_sort_by = 'time' end
    if c.cooldown_category == nil then c.cooldown_category = 'All' end
    if c.cooldown_status_filter == nil then c.cooldown_status_filter = 'All' end
    if c.cooldown_compact == nil then c.cooldown_compact = false end
    if c.cooldown_show_inline_edit == nil then c.cooldown_show_inline_edit = false end

    if c.auto_spend_aa == nil then c.auto_spend_aa = false end
    if c.auto_spend_aa_threshold == nil then
        c.auto_spend_aa_threshold = 100
    elseif tonumber(c.auto_spend_aa_threshold) and tonumber(c.auto_spend_aa_threshold) < 5 then
        c.auto_spend_aa_threshold = 5
    end
    if c.auto_spend_aa_id == nil then c.auto_spend_aa_id = 17788 end
    if c.auto_spend_aa_buy_id == nil then c.auto_spend_aa_buy_id = 0 end
    if c.auto_spend_aa_cost == nil then c.auto_spend_aa_cost = 25 end
    if c.auto_spend_aa_name == nil or c.auto_spend_aa_name == '' then c.auto_spend_aa_name = 'Alternately Advanced Fireworks' end
    if c.auto_spend_aa_action ~= 'window' and c.auto_spend_aa_action ~= 'activate' and c.auto_spend_aa_action ~= 'buy' and c.auto_spend_aa_action ~= 'both' then
        c.auto_spend_aa_action = 'window'
    end
    if c.auto_summon_fireworks == nil then c.auto_summon_fireworks = false end
    if type(c.auto_aa_priorities) ~= 'table' then c.auto_aa_priorities = {} end
    if c.auto_aa_sort_by ~= 'name' and c.auto_aa_sort_by ~= 'cost' and c.auto_aa_sort_by ~= 'trained' then
        c.auto_aa_sort_by = 'name'
    end
    if c.auto_aa_sort_asc == nil then c.auto_aa_sort_asc = true end
    if c.auto_aa_search == nil then c.auto_aa_search = '' end
    if c.auto_aa_hide_maxed == nil then c.auto_aa_hide_maxed = false end
    if c.auto_aa_only_prioritized == nil then c.auto_aa_only_prioritized = false end
    if c.auto_aa_buy_order ~= 'cost' and c.auto_aa_buy_order ~= 'list' then
        c.auto_aa_buy_order = 'cost'
    end
    if c.auto_aa_delegate_aaspend == nil then c.auto_aa_delegate_aaspend = true end
    if c.auto_aa_aaspend_mode ~= 'auto' and c.auto_aa_aaspend_mode ~= 'brute' then
        c.auto_aa_aaspend_mode = 'auto'
    end
    if c.downtime_buffing == nil then c.downtime_buffing = true end
    if c.pause_on_zone == nil then c.pause_on_zone = true end
    c.combat_style = 'Melee'
    if type(c.status_collapsed) ~= 'table' then c.status_collapsed = {} end

    if c.ma_id == nil then c.ma_id = 0 end
    if type(c.custom_ma_list) ~= 'table' then c.custom_ma_list = {} end

    if type(c.pull_con_filter) ~= 'table' then
        c.pull_con_filter = {}
    end
    for _, conName in ipairs(MODES.PULL_CON_LIST) do
        if c.pull_con_filter[conName] == nil then
            c.pull_con_filter[conName] = true
        end
    end
end

-- Single source of truth for ctrl's defaults -- used both at module load and
-- on every character switch (onCharacterChanged).
local function defaultCtrl()
    return {
        plugins              = {},
        running              = false,
        mode                 = 'Manual',
        submode              = 'Hunt',
        manual_auto_xtarget  = true,
        manual_stick         = true,
        manual_auto_nav      = false,
        pull_style           = 'Melee',
        pull_spell           = '',
        pull_spell_gem       = 1,
        pull_engage_dist     = 100,
        pull_stand_back      = false,
        xtar_nav_dist        = 150,
        ignore_distant_xtargets = true,
        combat_style         = 'Melee',
        melee_dist           = 14,
        los_face_only        = false,
        ma_name              = '',
        ma_id                = 0,
        custom_ma_list       = {},
        assist_at            = 98,
        assist_self_defense  = true,
        assist_behind        = true,
        chase                = true,
        chase_dist           = 15,
        automem              = true,
        camp_loc             = nil,
        camp_radius          = 100,
        camp_z               = 75,
        camp_z_plane         = 15,
        hunter_radius        = 1500,
        hunter_z_plane       = 15,
        hunter_z             = 75,
        hunter_min_level     = 1,
        hunter_max_level     = 100,
        hunter_combat_radius = 250, -- max roam distance from anchor when anchor is set
        hunter_combat_loc    = nil, -- {x,y,z} anchor; nil = no constraint
        pull_min_level       = 1,
        pull_max_level       = 100,
        pull_con_filter      = {
            ['Scowling']      = true,
            ['Threateningly'] = true,
            ['Dubious']       = true,
            ['Apprehensive']  = true,
            ['Indifferent']   = true,
            ['Amiably']       = true,
            ['Kindly']        = true,
            ['Warmly']        = true,
            ['Ally']          = true,
        },
        check_closer_mobs        = true,
        max_closer_retargets     = 1,
        closer_forward_cone_only = true,
        closer_los_priority      = true,
        closer_scan_interval     = 1.0,
        nav_fallback_stick       = false,
        nav_hazard_avoidance     = true,
        nav_hazard_radius        = 15,
        nav_hazard_min_hits      = 2,
        nav_hazard_max_hits      = 6,
        nav_hazard_decay_minutes = 10,
        nav_reverse_breadcrumbs = true,
        nav_max_path_ratio       = 2.5,
        nav_proactive_doors      = true,
        nav_levitation_clear     = true,
        zone_hazards             = {},
        debug_mode               = false,
        scribed_only             = true,
        action_trained_only      = true,
        aa_purchased_only        = true,
        disc_trained_only        = true,
        medbreak_enabled         = false,
        medbreak_hp_on           = false,
        medbreak_hp_start        = 20,
        medbreak_hp_stop         = 90,
        medbreak_mana_on         = false,
        medbreak_mana_start      = 20,
        medbreak_mana_stop       = 90,
        medbreak_end_on          = false,
        medbreak_end_start       = 20,
        medbreak_end_stop        = 90,
        cast_max_retries         = 2,
        cast_lockout_sec         = 30,
        min_mana_pct             = 0,
        pull_min_hp_pct          = 0,
        buff_refresh_sec         = 45,
        pet_assist_at            = 100,
        pet_hold_enabled         = true,
        pet_names                = {},   -- cls -> pet name learned from that class's last summon (pet names are unique per player on this server)
        show_map_radius          = true,
        show_crit_floaters       = true,
        show_cooldowns           = false,
        show_spellbook           = false,
        show_map                 = false,
        show_auto_aa             = false,
        show_auto_accept         = false,
        show_dps                 = false,
        show_inv                 = false,
        show_cursor              = false,
        show_buffbot             = false,
        cooldown_alpha           = 0.90,
        cooldown_locked          = false,
        cooldown_view_mode       = 'table',
        cooldown_sort_by         = 'time',
        cooldown_category        = 'All',
        cooldown_status_filter   = 'All',
        cooldown_compact         = false,
        cooldown_show_inline_edit = false,
        show_unit_frames         = false,
        uf_lock                  = false,
        uf_alpha                 = 0.85,
        uf_bar_height            = 14,
        uf_show_endurance        = true,
        uf_show_xp               = true,
        uf_hide_empty_pets       = true,
        uf_buff_max              = 30,
        show_group_window        = false,
        gw_lock                  = false,
        gw_alpha                 = 0.85,
        gw_bar_height            = 14,
        gw_include_self          = true,
        gw_show_mana             = true,
        gw_show_endurance        = false,
        gw_show_pets             = true,
        gw_show_roles            = true,
        show_effects_window      = false,
        eff_lock                 = false,
        eff_alpha                = 0.85,
        eff_bar_height           = 18,
        eff_sort_by              = 'Time Left (Ascending)',
        eff_show_buffs           = true,
        eff_show_songs           = true,
        eff_show_detrimental     = true,
        show_xtarget_window      = false,
        xt_lock                  = false,
        xt_alpha                 = 0.85,
        xt_bar_height            = 16,
        xt_show_empty            = false,
        xt_show_tot              = true,
        xt_show_aggro            = true,
        xt_show_dist             = true,
        show_spell_gems          = false,
        gem_lock                 = false,
        gem_alpha                = 0.85,
        gem_orientation          = 'Auto',
        gem_show_badges          = true,
        gem_show_timer           = true,
        burn                     = false,
        compact                  = false,
        use_waypoints            = false,
        waypoint_radius          = 20,
        waypoint_scan_radius     = 100,
        waypoint_direction       = 1,
        waypoint_loop            = false,
        current_waypoint_idx     = 1,
        waypoints                = {},
        zone_waypoints           = {},
        zone_waypoint_presets    = {},
        auto_spend_aa            = false,
        auto_spend_aa_threshold  = 100,
        auto_spend_aa_id         = 17788,
        auto_spend_aa_buy_id     = 0,
        auto_spend_aa_cost       = 25,
        auto_spend_aa_name       = 'Alternately Advanced Fireworks',
        auto_spend_aa_action     = 'window',
        auto_summon_fireworks    = false,
        auto_aa_priorities       = {},
        auto_aa_sort_by          = 'name',
        auto_aa_sort_asc         = true,
        auto_aa_search           = '',
        auto_aa_hide_maxed       = false,
        auto_aa_only_prioritized = false,
        auto_aa_buy_order        = 'cost',
        auto_aa_delegate_aaspend = true,
        auto_aa_aaspend_mode     = 'auto',
        downtime_buffing         = true,
        pause_on_zone            = true,
        auto_group               = false,
        auto_trade               = false,
        auto_dzadd               = false,
        auto_accept_anyone       = false,
        auto_accept_guild        = false,
        auto_accept_group        = false,
        auto_accept_names        = {},
        fov                      = 100,
        fov_enabled              = false,
        saved_window_positions   = {},
        saved_window_positions_at = nil,
        winpos_auto_restore_on_resize = true,
        winpos_restore_visibility = false,
        status_collapsed         = {
            target = false,
            vitals = false,
            nav    = false,
            xtar   = false,
        }
    }
end
ctrl = defaultCtrl()
sanitizeModeConfig(ctrl)

-- Runtime & state management tables
local runtime = {
    plugins = {},
    pluginManager = nil,
    pullState = 'IDLE',
    pullTargetId = 0,
    pullHpRest = false,
    deathGuardFired = false,
    medBreakActive = false,
    pullBreadcrumbs = {},
    activeDetour = nil,
    lastProactiveDoorAt = 0,
    lastLevClearAt = 0,
    PURE_MELEE = { War = true, WAR = true, Mnk = true, MNK = true, Rog = true, ROG = true, Ber = true, BER = true },
    pendingMem = {},
    lastCast = {},
    lastTick = 0,
    wasRunning = false,
    lastSig = nil,
    autoDirty = false,
    autoDirtyAt = 0,
    lastBuffDiagAt = 0,
    lastHunterDiagAt = 0,
    lastHunterMsgKey = nil,
    lastGemDiagAt = 0,
    lastAssistCmdAt = 0,
    sungBuffs = {},
    npcCastCounts = {},
    npcSpellApplied = {},
    npcSpellLastCast = {},
    lastNpcCastPruneAt = 0,
    lastMapDraw = { active = false, type = nil, key = '' },
    trackStartTime = nil,
    startAA = nil,
    currentAA = 0,
    startPlat = nil,
    currentPlat = 0,
    pendingCursorClearAt = nil,
    ignoreList = {},
    pullList = {},
    ignoreInput = '',
    pullInput = '',
    conCache = {},
    spellbookSetCache = nil,
    lastSpellbookCacheTime = 0,
    hasAACache = {},
    knownDiscSet = nil,
    discExpires = {},
    discCooldown = {},
    filteredSpellsCache = {},
    gemSyncWarned = {},
    lastGemSyncCheckAt = 0,
    colN = 0,
    varN = 0,
    isSwitchingSpells = false,
    switchingSlot = 0,
    switchingSpellName = nil,
    lastDowntimeSwapAt = {},
    interruptedSwap = nil
}

local petState = {
    myPets = {},           -- cls -> living spawn ID of that class's pet (one pet per pet class, an ID is never tracked under two classes)
    lastObservedId = 0,
    summonPending = nil,   -- { cls, spell, at, untilAt, snapshot } while a pet summon is in flight (see beginPetSummon)
    summonBlockedUntil = {}, -- cls -> os.clock() until which 'missing pet' stays false (server refused the summon)
    lastReconcileAt = 0,
    petsCache = nil,       -- short-lived getAllMyPets() result: { at = clock, ids = {...} }
    lastCmdTargetId = 0,
    lastCmdAt = 0,
    manualHunterHold = nil,
    petHoldActive = false, -- true when we issued /pet hold waiting for HP threshold
    holdIssuedForId = 0,   -- target ID for which a hold was issued
    PET_CLASSES = { Nec = true, Mag = true, Bst = true, Enc = true, Shm = true, SK = true, Dru = true, Brd = true },
    selectedScope = 'all',
    lastPetCmdSent = '',
    lastPetCmdTime = 0,
    inspectPetId = nil,
    inspectSlot = nil,
    cachedPetBuffs = {}
}

local pursuit = {
    id = 0,
    bestDist = 9e9,
    improvedAt = 0,
    navStalls = 0,
    wasNavActive = false,
    lastLoSAt = 0,
    lastNavTargetId = 0,
    lastNavLoc = nil,
    wanderLoc = nil,
    wanderSince = 0,
    unreachableIds = {},
    lastTooFarRepositionAt = 0,
    lastCantHitAt = 0,
    cantHitCount = 0,
    hasRetargeted = false,
    retargetCount = 0,
    cycleTargetIds = {},
    lastCloserScanAt = 0,
    nonXtarTargetId = 0,
    nonXtarEngageAt = 0,
    lastCombatFaceAt = 0,
    lastStickDist = 0,
    lastBehindStickDist = 0,
    lastFrontStickDist = 0,
    meshRecoverId = 0,
    meshRecoverAt = 0,
    -- Detour state machine fields
    detourActive = false,
    detourX = 0,
    detourY = 0,
    detourZ = 0,
    detourTargetId = 0,
    detourTargetKey = nil,
    detourStartedAt = 0,
    detourExpiresAt = 0,
    -- Ladder-climb detection sampling (see isClimbingLadder()). X/Y/Z are the
    -- position at the last sample; climbingUntil is a grace-period expiry --
    -- we're considered "climbing" any time os.clock() is before it.
    climbLastX = nil,
    climbLastY = nil,
    climbLastZ = nil,
    climbSampleAt = 0,
    climbingUntil = 0
}

local stuckState = {
    checkAt = 0,
    lastX = 0,
    lastY = 0,
    counter = 0,
    attempts = 0,
    lastDoorClickAt = 0,
    lastStuckRecoveryAt = nil,
    lastCannotSeeAt = 0,
    cannotSeeAttempts = 0
}

local function trioHasPetClass()
    for _, c in ipairs(myClasses) do if petState.PET_CLASSES[c] then return true end end
    return false
end

local COMBO_OPTIONS = {
    FRIENDLY = { 'Myself', 'Main Assist', 'Tank', 'Lowest-HP Ally', 'Whole Group', 'Pet' },
    ENEMY    = { 'Current Target', 'Assist Target', 'Nearest Add', 'Unmezzed Add', 'All Enemies' },
    TARGETS  = {},
    WHENS    = { 'HP <=', 'target HP <=', 'target HP between', 'my HP <=', 'my Mana <=', 'missing buff', 'missing pet',
        'has Poison', 'has Disease', 'has Poison/Disease', 'has Curse', 'has Corruption', 'Aggro on Me', 'my Aggro >=',
        'ally is Dead', 'add is loose', 'twist while fighting', 'in combat',
        'always' }
}
do
    for _, t in ipairs(COMBO_OPTIONS.FRIENDLY) do COMBO_OPTIONS.TARGETS[#COMBO_OPTIONS.TARGETS + 1] = 'F: ' .. t end
    for _, t in ipairs(COMBO_OPTIONS.ENEMY) do COMBO_OPTIONS.TARGETS[#COMBO_OPTIONS.TARGETS + 1] = 'E: ' .. t end
end

-- ============================================================================
-- Local Theme & Common Helpers (Self-Contained Module)
-- ============================================================================
local function idxOf(tbl, val)
    if not tbl then return 1 end
    for i, v in ipairs(tbl) do
        if v == val then return i end
    end
    return 1
end

local function toCanonicalClassAbbr(str)
    if not str then return nil end
    local s = tostring(str)
    if s == '' or s == 'nil' or s == 'NULL' then return nil end
    local up = s:upper():gsub('%s+', '')
    return MQSHORT[up] or (ALL_ABBR and idxOf(ALL_ABBR, s) > 0 and s) or nil
end

local function classColor(abbr)
    local pal = {
        { 0.30, 0.70, 1.00 }, -- slot 1: Arcane Blue
        { 1.00, 0.55, 0.30 }, -- slot 2: Ember Gold
        { 0.37, 0.88, 0.64 }, -- slot 3: Jade Green
    }
    for i, c in ipairs(myClasses) do
        if c == abbr then
            local col = pal[i] or { 0.49, 0.56, 0.65 }
            return col[1], col[2], col[3], col[4] or 1.0
        end
    end
    return 0.49, 0.56, 0.65, 1.0
end

local function defaultsForKind(kind, bene)
    if kind == 'heal' then return 'F: Myself', 'my HP <=', 75 end
    if kind == 'buff' then return 'F: Myself', 'missing buff', 100 end
    if kind == 'pet_buff' then return 'F: Pet', 'missing buff', 100 end
    if kind == 'pet' then return 'F: Myself', 'missing pet', 100 end
    if kind == 'util' then return 'F: Myself', 'always', 100 end
    if kind == 'debuff' then return 'E: Current Target', 'target HP <=', 98 end
    if kind == 'dot' then return 'E: Current Target', 'target HP <=', 98 end
    if kind == 'dd' then return 'E: Current Target', 'target HP <=', 95 end
    if bene == true then return 'F: Myself', 'missing buff', 100 end
    return 'E: Current Target', 'target HP <=', 95
end

local function cleanSpellName(name)
    if not name or type(name) ~= 'string' then return "" end
    local cleaned = name:gsub('%s*%([%w%s/]+%)$', '')
    return (cleaned:gsub('^%s*(.-)%s*$', '%1'))
end

local function normalizeSpellName(name)
    if not name or type(name) ~= 'string' then return "" end
    local s = name:lower()
    s = s:gsub('%s*%(?%s*rk%.?%s*[%ivxlc%d]+%s*%)?', '')
    s = s:gsub('%s*%([^%)]+%)', '')
    s = s:gsub('[%p%s]', '')
    return s
end

---@return table
local function getScribedSpellSet()
    local now = os.clock()
    if runtime.spellbookSetCache and (now - (runtime.lastSpellbookCacheTime or 0)) < 3.0 then
        return runtime.spellbookSetCache
    end

    local set = {}
    pcall(function()
        local count = 720
        pcall(function()
            local c = mq.TLO.Me.BookCount()
            if c then
                local num = tonumber(tostring(c))
                if num and num > 0 then
                    count = math.floor(num)
                end
            end
        end)

        for slot = 1, count do
            pcall(function()
                local spellObj = mq.TLO.Me.Book(slot)
                if spellObj then
                    local id = spellObj.ID()
                    if id and tonumber(tostring(id)) and tonumber(tostring(id)) > 0 then
                        local rawName = spellObj.Name() or spellObj()
                        if rawName then
                            local bName = tostring(rawName)
                            if bName ~= "" and bName ~= "NULL" and bName ~= "nil" then
                                set[bName] = true
                                set[bName:lower()] = true
                                local cleaned = cleanSpellName(bName):lower()
                                if cleaned ~= "" then set[cleaned] = true end
                                local norm = normalizeSpellName(bName)
                                if norm ~= "" then set[norm] = true end
                            end
                        end
                    end
                end
            end)
        end
    end)

    runtime.spellbookSetCache = set
    runtime.lastSpellbookCacheTime = now
    return set
end

local function isScribed(nm)
    if not nm or nm == "" then return false end
    local strNm = tostring(nm)
    if strNm == "" or strNm == "NULL" or strNm == "nil" then return false end

    -- 1. Check cached spellbook map (fastest & handles unindexed TLO names)
    local sbSet = getScribedSpellSet()
    if not sbSet then return false end
    if sbSet[strNm] or sbSet[strNm:lower()] then return true end

    local cleaned = cleanSpellName(strNm):lower()
    if cleaned ~= "" and sbSet[cleaned] then return true end

    local norm = normalizeSpellName(strNm)
    if norm ~= "" and sbSet[norm] then return true end

    -- 2. Direct TLO Book query fallback
    local ok, res = pcall(function() return mq.TLO.Me.Book(strNm)() end)
    if ok and res ~= nil then
        local num = tonumber(tostring(res))
        if num and num > 0 then return true end
    end

    if cleaned ~= "" then
        local okC, resC = pcall(function() return mq.TLO.Me.Book(cleaned)() end)
        if okC and resC ~= nil then
            local numC = tonumber(tostring(resC))
            if numC and numC > 0 then return true end
        end
    end

    -- 3. RankName lookup via TLO Spell
    local okR, rNameObj = pcall(function() return mq.TLO.Spell(strNm).RankName() end)
    if okR and rNameObj ~= nil then
        local rName = tostring(rNameObj)
        if rName ~= "" and rName ~= "NULL" and rName ~= "nil" and rName ~= strNm then
            if sbSet[rName] or sbSet[rName:lower()] then return true end
            local okRB, resRB = pcall(function() return mq.TLO.Me.Book(rName)() end)
            if okRB and resRB ~= nil then
                local numRB = tonumber(tostring(resRB))
                if numRB and numRB > 0 then return true end
            end
        end
    end

    return false
end

local function isGemMatching(slotOrName, targetSpellName)
    if not targetSpellName or targetSpellName == '' then return false end
    local gemName = nil
    if type(slotOrName) == 'number' then
        pcall(function() gemName = mq.TLO.Me.Gem(slotOrName).Name() end)
    else
        gemName = slotOrName
    end
    if not gemName or gemName == '' or gemName == 'NULL' or gemName == 'nil' then return false end
    if gemName == targetSpellName then return true end

    local cleanGem = cleanSpellName(gemName):lower()
    local cleanTarget = cleanSpellName(targetSpellName):lower()
    if cleanGem ~= '' and cleanGem == cleanTarget then return true end

    local normGem = normalizeSpellName(gemName)
    local normTarget = normalizeSpellName(targetSpellName)
    if normGem ~= '' and normGem == normTarget then return true end

    local ok1, r1 = pcall(function() return mq.TLO.Spell(gemName).RankName() end)
    local ok2, r2 = pcall(function() return mq.TLO.Spell(targetSpellName).RankName() end)
    if ok1 and ok2 and r1 and r2 then
        local str1, str2 = tostring(r1), tostring(r2)
        if str1 ~= '' and str1 ~= 'NULL' and str1 == str2 then
            return true
        end
    end
    return false
end

local function hasAA(nm)
    if not nm or nm == "" or tonumber(nm) ~= nil then return false end
    if type(nm) == 'string' then nm = nm:match('^%s*(.-)%s*$') end
    if not nm or nm == "" or tonumber(nm) ~= nil then return false end
    local now = os.clock()
    runtime.hasAACache = runtime.hasAACache or {}
    if runtime.hasAACache[nm] ~= nil and (now - (runtime.hasAACache[nm].time or 0)) < 5.0 then
        return runtime.hasAACache[nm].val
    end
    local ok, res = pcall(function() return mq.TLO.Me.AltAbility(nm).Rank() end)
    local hasIt = (ok and res ~= nil and res > 0)
    runtime.hasAACache[nm] = { val = hasIt, time = now }
    return hasIt
end

local function scanKnownDiscs()
    runtime.knownDiscSet = {}
    runtime.discKnownCache = nil -- rescan invalidates any cached negative lookups
    pcall(function()
        local count = mq.TLO.Me.CombatAbilityCount() or 0 ---@diagnostic disable-line: undefined-field
        for i = 1, count do
            local name = mq.TLO.Me.CombatAbility(i).Name()
            if name and name ~= "" then
                runtime.knownDiscSet[name] = true
                runtime.knownDiscSet[name:lower()] = true
            end
        end
    end)
end

local function isDiscKnown(discName)
    if not discName or discName == "" then return false end
    if not runtime.knownDiscSet then scanKnownDiscs() end
    local kSet = runtime.knownDiscSet or {}
    local nm = cleanSpellName(discName) or ""
    if (nm ~= "" and (kSet[nm] or kSet[nm:lower()])) or kSet[discName] or kSet[discName:lower()] then
        return true
    end
    -- Not in the scanned set: fall back to a live TLO query, but cache the answer
    -- (5s TTL) so the Disc tab's per-row "trained only" filter doesn't hit the TLO
    -- for every untrained disc on every frame.
    local now = os.clock()
    runtime.discKnownCache = runtime.discKnownCache or {}
    local cached = runtime.discKnownCache[discName]
    if cached and (now - cached.time) < 5.0 then return cached.val end
    local ok, res = pcall(function() return mq.TLO.Me.CombatAbility(nm)() end)
    local known = (ok and res ~= nil)
    runtime.discKnownCache[discName] = { val = known, time = now }
    return known
end

local function hasDisc(discName)
    return isDiscKnown(discName)
end

local function parseClassLine(text)
    if not text or type(text) ~= 'string' or text == '' or text == 'NULL' then return nil end
    local cleaned = text:gsub('^%s*%d+[%s%.:]*', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if cleaned == '' then return nil end

    local up = cleaned:upper()
    if up:find('^LEVEL') or up:find('^LVL') then return nil end

    local noSpaces = up:gsub('[%s_%-]+', '')
    if MQSHORT[noSpaces] then return MQSHORT[noSpaces] end
    if ALL_ABBR and idxOf(ALL_ABBR, cleaned) > 0 then return cleaned end

    for word in cleaned:gmatch('%a+') do
        local wup = word:upper()
        if MQSHORT[wup] then return MQSHORT[wup] end
    end

    return nil
end

local function scanOneNode(node, found)
    if not node or not node() then return end
    pcall(function()
        local items = node.Items()
        if items and items > 0 then
            for i = 1, items do
                local ok, text = pcall(function() return node.List(i)() end)
                if ok and text and text ~= '' and text ~= 'NULL' then
                    local norm = parseClassLine(text)
                    if norm then
                        local dup = false
                        for _, existing in ipairs(found) do
                            if existing == norm then
                                dup = true; break
                            end
                        end
                        if not dup then found[#found + 1] = norm end
                    end
                end
            end
        end
    end)
    pcall(function()
        local text = node.Text()
        if text and text ~= '' and text ~= 'NULL' then
            for line in text:gmatch('[^\r\n]+') do
                local norm = parseClassLine(line)
                if norm then
                    local dup = false
                    for _, existing in ipairs(found) do
                        if existing == norm then
                            dup = true; break
                        end
                    end
                    if not dup then found[#found + 1] = norm end
                end
            end
        end
    end)
end

local function walkChildTree(parentNode, found, depth)
    if not parentNode or not parentNode() then return end
    depth = depth or 0
    if depth > 15 then return end
    local okChild, child = pcall(function() return parentNode.FirstChild end)
    if not okChild or not child or not child() then return end
    local visited = 0
    while child and child() and visited < 200 do
        visited = visited + 1
        scanOneNode(child, found)
        walkChildTree(child, found, depth + 1)
        local okNext, nxt = pcall(function() return child.Next end)
        if not okNext or not nxt or not nxt() then break end
        child = nxt
    end
end

local function classesFromInventoryWindow(loud, force)
    local wasOpen = false
    pcall(function() wasOpen = mq.TLO.Window('InventoryWindow').Open() end)

    if not wasOpen and force then
        mq.cmd('/windowstate InventoryWindow open')
        mq.delay(250)
    end

    local found = {}

    -- 1. Check IW_ClassAbbr ("SHD\nMAG\nBST")
    pcall(function()
        local invWin = mq.TLO.Window('InventoryWindow')
        if not invWin or not invWin() then return end
        local abbrChild = invWin.Child('IW_ClassAbbr')
        if abbrChild and abbrChild() then
            local text = abbrChild.Text()
            if text and text ~= '' and text ~= 'NULL' then
                for line in text:gmatch('[^\r\n]+') do
                    local norm = parseClassLine(line)
                    if norm then
                        local dup = false
                        for _, existing in ipairs(found) do
                            if existing == norm then
                                dup = true; break
                            end
                        end
                        if not dup then found[#found + 1] = norm end
                    end
                end
            end
        end
    end)

    -- 2. Check IW_Class ("DreadLord\nArchConvoker\nFeralLord")
    if #found == 0 then
        pcall(function()
            local invWin = mq.TLO.Window('InventoryWindow')
            if not invWin or not invWin() then return end
            local clsChild = invWin.Child('IW_Class')
            if clsChild and clsChild() then
                local text = clsChild.Text()
                if text and text ~= '' and text ~= 'NULL' then
                    for line in text:gmatch('[^\r\n]+') do
                        local norm = parseClassLine(line)
                        if norm then
                            local dup = false
                            for _, existing in ipairs(found) do
                                if existing == norm then
                                    dup = true; break
                                end
                            end
                            if not dup then found[#found + 1] = norm end
                        end
                    end
                end
            end
        end)
    end

    -- 3. Check IW_ClassList
    if #found == 0 then
        pcall(function()
            local invWin = mq.TLO.Window('InventoryWindow')
            if not invWin or not invWin() then return end
            local listChild = invWin.Child('IW_ClassList')
            if listChild and listChild() then
                for i = 1, 10 do
                    local ok, text = pcall(function() return listChild.List(i)() end)
                    if ok and text and text ~= '' and text ~= 'NULL' then
                        local norm = parseClassLine(text)
                        if norm then
                            local dup = false
                            for _, existing in ipairs(found) do
                                if existing == norm then
                                    dup = true; break
                                end
                            end
                            if not dup then found[#found + 1] = norm end
                        end
                    end
                end
                if #found == 0 then
                    local okText, rawText = pcall(function() return listChild.Text() end)
                    if okText and rawText and rawText ~= '' and rawText ~= 'NULL' then
                        for line in rawText:gmatch('[^\r\n]+') do
                            local norm = parseClassLine(line)
                            if norm then
                                local dup = false
                                for _, existing in ipairs(found) do
                                    if existing == norm then
                                        dup = true; break
                                    end
                                end
                                if not dup then found[#found + 1] = norm end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- 4. Tree Walk fallback
    if #found == 0 then
        pcall(function()
            local invWin = mq.TLO.Window('InventoryWindow')
            if invWin and invWin() then
                walkChildTree(invWin, found, 0)
            end
        end)
    end

    if not wasOpen and force then
        mq.cmd('/windowstate InventoryWindow close')
    end

    if #found > 0 then
        if loud then
            print(string.format('\ay[Triune]\ax Detected %d class(es) from InventoryWindow: %s', #found,
                table.concat(found, ', ')))
        end
        return found
    end

    if loud then
        print('\ar[Triune]\ax InventoryWindow returned no classes.')
    end
    return nil
end

local function detectClasses(loud)
    local found = classesFromInventoryWindow(loud, true)
    if found and #found > 0 then return found end

    local ok, mainClass = pcall(function() return mq.TLO.Me.Class.ShortName() end)
    if ok and mainClass and mainClass ~= '' and mainClass ~= 'NULL' then
        local norm = toCanonicalClassAbbr(mainClass)
        if norm then
            if loud then
                print(string.format('\ay[Triune]\ax Single-class character fallback (%s).', norm))
            end
            return { norm }
        end
    end

    return nil
end

local isHostileTarget
local function isSpawnAlive(id)
    if not id or id <= 0 then return false end
    local alive = false
    pcall(function()
        local s = mq.TLO.Spawn(id)
        if not s or not s() then return end
        alive = true -- spawn exists; a failed field read below leaves it "alive" (as before)
        local dead, tp, state = s.Dead(), s.Type(), s.State()
        alive = (not dead) and (tp ~= 'Corpse') and (state ~= 'DEAD')
    end)
    return alive
end

-- ============================================================================
-- Multi-pet tracking (this server lets each pet class of the trio keep its own
-- pet, so up to three at once). The single source of truth is
-- petState.myPets[cls] = spawnId with two invariants that every writer below
-- keeps: an ID is tracked under at most one class, and every tracked ID is a
-- living spawn that belongs to us. Pet names are unique per player here, so a
-- name learned from a class's own summon (ctrl.pet_names) is the most reliable
-- way to map a pet back to its class after a restart or a zone.
-- ============================================================================

-- cls that learned this pet name from its own summon, or nil.
local function petClsForName(name)
    if not name or name == '' then return nil end
    local names = ctrl and ctrl.pet_names
    if type(names) ~= 'table' then return nil end
    local lower = string.lower(name)
    for c, n in pairs(names) do
        if type(n) == 'string' and string.lower(n) == lower then return c end
    end
    return nil
end

local function spawnCleanName(id)
    local nm = ''
    pcall(function()
        local s = mq.TLO.Spawn(id)
        if s and s() then nm = s.CleanName() or '' end
    end)
    return nm
end

local function isSpawnMyPet(s_or_id)
    if not s_or_id then return false end
    local s = (type(s_or_id) == 'number') and mq.TLO.Spawn(s_or_id) or s_or_id
    if not s or not s() then return false end
    local myId = 0
    local myName = ''
    pcall(function()
        myId = mq.TLO.Me.ID() or 0
        myName = mq.TLO.Me.CleanName() or ''
    end)
    if myId <= 0 then return false end

    local isMine = false
    pcall(function()
        local sid = s.ID() or 0
        local curPetId = mq.TLO.Me.Pet.ID() or 0
        if curPetId > 0 and sid == curPetId then
            isMine = true
            return
        end

        -- A pet whose master is someone else is never ours, whatever its name.
        local m = s.Master
        if m and m() then
            local mid = m.ID() or 0
            if mid > 0 then
                isMine = (mid == myId)
                return
            end
        end

        local o = s.Owner
        if o and o() then
            local oid = o.ID() or 0
            if oid > 0 then
                isMine = (oid == myId)
                return
            end
        end

        local cname = s.CleanName() or ''
        if myName ~= '' and cname ~= '' then
            if cname:find(myName .. "'s ", 1, true) or
               cname:find(myName .. "`s ", 1, true) or
               cname:find('(Owner: ' .. myName .. ')', 1, true) then
                isMine = true
                return
            end
        end

        -- Pet-typed spawn whose master could not be resolved: fall back to the
        -- names our own summons taught us (unique per player on this server).
        -- Never applied to plain NPCs, so a mob can never be mistaken for a pet.
        if cname ~= '' and (s.Type() or '') == 'Pet' and petClsForName(cname) then
            isMine = true
            return
        end
    end)
    return isMine
end

-- Which class currently tracks this spawn ID (nil when untracked).
local function petTrackedCls(id)
    if not id or id <= 0 then return nil end
    for c, pid in pairs(petState.myPets) do
        if pid == id then return c end
    end
    return nil
end

-- Drops tracked pets that are dead / gone / not ours, and resolves any ID that
-- ended up under two classes (keeps the first in myClasses order).
local function prunePetTracking()
    local seen = {}
    for _, c in ipairs(myClasses) do
        local pid = petState.myPets[c]
        if pid then
            if pid <= 0 or seen[pid] or not isSpawnAlive(pid) or not isSpawnMyPet(pid) then
                petState.myPets[c] = nil
            else
                seen[pid] = true
            end
        end
    end
    local inTrio = {}
    for _, c in ipairs(myClasses) do inTrio[c] = true end
    for c in pairs(petState.myPets) do -- classes that left the trio
        if not inTrio[c] then petState.myPets[c] = nil end
    end
    petState.petsCache = nil
end

-- Assigns a pet to a class, removing it from any other class first. `learnName`
-- is set only when the assignment is certain (the class just summoned it), so a
-- reconcile guess never poisons ctrl.pet_names.
local function trackPet(cls, id, learnName)
    if not cls or not id or id <= 0 then return end
    for c, pid in pairs(petState.myPets) do
        if pid == id and c ~= cls then petState.myPets[c] = nil end
    end
    petState.myPets[cls] = id
    petState.lastObservedId = id
    petState.petsCache = nil
    if learnName then
        local nm = spawnCleanName(id)
        if nm ~= '' then
            ctrl.pet_names = (type(ctrl.pet_names) == 'table') and ctrl.pet_names or {}
            for c, n in pairs(ctrl.pet_names) do -- a name belongs to one class
                if c ~= cls and type(n) == 'string' and string.lower(n) == string.lower(nm) then ctrl.pet_names[c] = nil end
            end
            if ctrl.pet_names[cls] ~= nm then
                ctrl.pet_names[cls] = nm
                runtime.autoDirty = true
            end
        end
    end
end

-- Collects and returns all living spawn IDs belonging to the player (multi-pet support for trio classes).
-- Cached for a fraction of a second because the HUDs and the gem evaluator call it many times per tick.
local function getAllMyPets()
    local now = os.clock()
    local cache = petState.petsCache
    if cache and (now - cache.at) < 0.25 then
        local copy = {}
        for i, id in ipairs(cache.ids) do copy[i] = id end
        return copy
    end

    local pets = {}
    local seen = {}
    local function addPet(id)
        if id and id > 0 and not seen[id] and isSpawnAlive(id) and isSpawnMyPet(id) then
            seen[id] = true
            pets[#pets + 1] = id
        end
    end

    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if myPetId > 0 then addPet(myPetId) end

    for _, c in ipairs(myClasses) do
        local pid = petState.myPets[c]
        if pid and pid > 0 then
            if isSpawnAlive(pid) and isSpawnMyPet(pid) then
                addPet(pid)
            else
                petState.myPets[c] = nil
            end
        end
    end

    pcall(function()
        local count = mq.TLO.SpawnCount('pet radius 150')() or 0
        for i = 1, count do
            local s = mq.TLO.NearestSpawn(i, 'pet radius 150')
            if s and s() then
                local sid = s.ID() or 0
                if sid > 0 then addPet(sid) end
            end
        end
    end)

    local ids = {}
    for i, id in ipairs(pets) do ids[i] = id end
    petState.petsCache = { at = now, ids = ids }
    return pets
end

-- Returns true if the player currently has an active living pet (or any live trio pet in petState.myPets)
local function hasActivePet()
    local pets = getAllMyPets()
    return #pets > 0
end

petState.PET_SCOPE_LIST = {
    'all', 'swarm', 'mag', 'bst', 'nec', 'enc', 'shm', 'dru', 'brd', 'shd'
}
local function classToPetCmdScope(cls)
    local PET_SCOPE_LIST = petState.PET_SCOPE_LIST
    if not cls or type(cls) ~= 'string' then return 'all' end
    local lower = string.lower(cls)
    if lower == 'sk' or lower == 'shd' then return 'shd' end
    for _, s in ipairs(PET_SCOPE_LIST) do
        if lower == s then return s end
    end
    return 'all'
end

local function sendPetCmd(verb, scope)
    if not verb or verb == '' then return end
    scope = scope or petState.selectedScope or 'all'
    local fullCmd = string.format('#petcmd %s %s', verb, scope)
    mq.cmdf('/say %s', fullCmd)
    petState.lastPetCmdSent = fullCmd
    petState.lastPetCmdTime = os.clock()
    print(string.format('\ag[Triune Pet]\ax Issued: \at%s\ax', fullCmd))
end

-- Best guess at which trio class a pet spawn belongs to: a name one of our
-- classes learned from its own summon wins, then the pet's race / name archetype.
local function detectPetClassFromSpawn(s)
    if not s or not s() then return nil end
    local cname = ''
    local race = ''
    pcall(function()
        cname = string.lower(s.CleanName() or '')
        race = string.lower(s.Race() or '')
    end)
    local learned = petClsForName(cname)
    if learned then return learned end
    if cname:find('warder', 1, true) then return 'Bst' end
    if race:find('animation', 1, true) or cname:find('animation', 1, true) then return 'Enc' end
    if race:find('elemental', 1, true) then return 'Mag' end
    if race:find('skeleton', 1, true) or race:find('spectre', 1, true) or race:find('zombie', 1, true) then return 'Nec' end
    if cname:find('spirit wolf', 1, true) then return 'Shm' end
    return nil
end

-- Maps every living pet of ours that is not tracked yet onto a pet class that
-- has none. `quiet` is the per-tick form used by the gem evaluator: throttled
-- and silent. The explicit form (startup, zone, Re-Scan button) always runs
-- and reports what it found.
local function reconcilePets(quiet)
    local now = os.clock()
    if quiet and (now - (petState.lastReconcileAt or 0)) < 0.5 then return end
    petState.lastReconcileAt = now

    local petClassList = {}
    for _, c in ipairs(myClasses) do
        if petState.PET_CLASSES[c] then petClassList[#petClassList + 1] = c end
    end
    if #petClassList == 0 then return end

    prunePetTracking()
    local allLivingPets = getAllMyPets()

    local untracked = {}
    for _, pid in ipairs(allLivingPets) do
        if not petTrackedCls(pid) then untracked[#untracked + 1] = pid end
    end
    if #untracked == 0 then return end

    local assigned = 0
    -- Pass 1: match by learned name / detected archetype
    for _, pid in ipairs(untracked) do
        local s = mq.TLO.Spawn(pid)
        if s and s() and not petTrackedCls(pid) then
            local detCls = detectPetClassFromSpawn(s)
            if detCls and petState.PET_CLASSES[detCls] then
                for _, c in ipairs(petClassList) do
                    if c == detCls and not petState.myPets[c] then
                        trackPet(c, pid, false)
                        assigned = assigned + 1
                        break
                    end
                end
            end
        end
    end

    -- Pass 2: hand the remaining pets to the remaining pet classes in slot order
    for _, pid in ipairs(untracked) do
        if not petTrackedCls(pid) then
            for _, c in ipairs(petClassList) do
                if not petState.myPets[c] then
                    trackPet(c, pid, false)
                    assigned = assigned + 1
                    break
                end
            end
        end
    end

    if assigned > 0 and not quiet then
        print('\ag[Triune]\ax found ' .. assigned .. ' existing pet(s) -- tracking ' .. assigned .. ' pet(s).')
    end
end

-- One entry per trio slot ({ slotNum, cls, scope, isPetCls, petId }) plus the
-- IDs of any living pet of ours that no slot owns (swarm pets, familiars).
-- A pet never appears in two slots: IDs and names are deduplicated.
local function getMultiPetList()
    local petSlots = {}
    local seenIds = {}
    local seenNames = {}

    prunePetTracking()
    local allLivingPets = getAllMyPets()

    for i = 1, 3 do
        local cls = myClasses[i]
        if cls then
            local isPetCls = petState.PET_CLASSES[cls] == true
            local petId = petState.myPets[cls]
            if petId and petId > 0 and not seenIds[petId] and isSpawnAlive(petId) then
                local nm = string.lower(spawnCleanName(petId))
                if nm ~= '' and seenNames[nm] then
                    petState.myPets[cls] = nil -- same pet name already shown in an earlier slot
                    petId = nil
                else
                    seenIds[petId] = true
                    if nm ~= '' then seenNames[nm] = true end
                end
            else
                if petId and seenIds[petId] then petState.myPets[cls] = nil end
                petId = nil
            end

            if isPetCls and not petId then
                for _, pid in ipairs(allLivingPets) do
                    if not seenIds[pid] and not petTrackedCls(pid) then
                        local nm = string.lower(spawnCleanName(pid))
                        if nm == '' or not seenNames[nm] then
                            petId = pid
                            seenIds[pid] = true
                            if nm ~= '' then seenNames[nm] = true end
                            trackPet(cls, pid, false)
                            break
                        end
                    end
                end
            end

            table.insert(petSlots, {
                slotNum = i,
                cls = cls,
                scope = classToPetCmdScope(cls),
                isPetCls = isPetCls,
                petId = petId
            })
        end
    end

    local extraPets = {}
    for _, pid in ipairs(allLivingPets) do
        if not seenIds[pid] then
            seenIds[pid] = true
            local nm = string.lower(spawnCleanName(pid))
            if nm == '' or not seenNames[nm] then
                if nm ~= '' then seenNames[nm] = true end
                table.insert(extraPets, pid)
            end
        end
    end

    return petSlots, extraPets
end

-- ---------------------------------------------------------------------------
-- Pet summon tracking. A 'missing pet' gem cast records what is around us so
-- the pet that appears afterwards can be pinned to the casting class even
-- when Me.Pet does not change (it usually stays on the first pet here), and
-- the gem stays quiet while the summon is in flight instead of re-casting.
-- ---------------------------------------------------------------------------
local PET_SUMMON_GRACE_SEC = 12
local PET_SUMMON_NEAR_DIST = 40

local function snapshotNearbySpawnIds()
    local set = {}
    pcall(function()
        local filter = 'pet radius 100'
        local count = mq.TLO.SpawnCount(filter)() or 0
        for i = 1, count do
            local s = mq.TLO.NearestSpawn(i, filter)
            if s and s() then
                local sid = s.ID() or 0
                if sid > 0 then set[sid] = true end
            end
        end
    end)
    return set
end

local function beginPetSummon(cls, spellName)
    local now = os.clock()
    petState.summonPending = {
        cls = cls,
        spell = spellName,
        at = now,
        untilAt = now + PET_SUMMON_GRACE_SEC,
        snapshot = snapshotNearbySpawnIds(),
    }
end

-- Called from the main loop. Resolves an in-flight summon to the pet it
-- produced, and keeps Me.Pet changes (dismiss / new pet) in the tracking table.
local function updatePetTracking()
    local now = os.clock()
    prunePetTracking()
    local sp = petState.summonPending
    if sp then
        local found = nil
        -- 1. a living pet of ours that nobody tracks yet
        for _, pid in ipairs(getAllMyPets()) do
            if not petTrackedCls(pid) and not sp.snapshot[pid] then found = pid break end
        end
        if not found then
            for _, pid in ipairs(getAllMyPets()) do
                if not petTrackedCls(pid) then found = pid break end
            end
        end
        -- 2. master could not be resolved (MQ types it Pet but Master() is empty):
        --    a brand-new pet spawn right next to us that nobody else owns
        if not found then
            pcall(function()
                local filter = 'pet radius ' .. PET_SUMMON_NEAR_DIST
                local count = mq.TLO.SpawnCount(filter)() or 0
                for i = 1, count do
                    local s = mq.TLO.NearestSpawn(i, filter)
                    local sid = s and s() and (s.ID() or 0) or 0
                    if sid > 0 and not sp.snapshot[sid] and not petTrackedCls(sid) and isSpawnAlive(sid) then
                        local foreign = false
                        local m = s.Master
                        if m and m() and (m.ID() or 0) > 0 and (m.ID() or 0) ~= (mq.TLO.Me.ID() or 0) then foreign = true end
                        if not foreign then found = sid return end
                    end
                end
            end)
        end
        if found then
            trackPet(sp.cls, found, true)
            petState.summonPending = nil
            if ctrl.debug_mode then
                print(string.format('\ao[DEBUG pet]\ax %s summon "%s" -> pet #%d "%s"', tostring(sp.cls), tostring(sp.spell), found, spawnCleanName(found)))
            end
        elseif now >= sp.untilAt then
            petState.summonPending = nil
            if ctrl.debug_mode then
                print(string.format('\ao[DEBUG pet]\ax %s summon "%s" produced no pet within %ds', tostring(sp.cls), tostring(sp.spell), PET_SUMMON_GRACE_SEC))
            end
        end
    end

    local curPetId = 0
    pcall(function() curPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if curPetId > 0 and curPetId ~= petState.lastObservedId then
        if not petTrackedCls(curPetId) then
            local cls = sp and sp.cls or nil
            if not cls then
                for _, c in ipairs(myClasses) do
                    if petState.PET_CLASSES[c] and (not petState.myPets[c] or not isSpawnAlive(petState.myPets[c])) then
                        cls = c
                        break
                    end
                end
            end
            if cls then trackPet(cls, curPetId, false) end
        end
        petState.lastObservedId = curPetId
    elseif curPetId == 0 then
        petState.lastObservedId = 0
    end
end

-- The server refused a summon because that class already has a pet we did not
-- recognise: hand the least-certain tracked pet (one whose class has not
-- confirmed it by name) to the casting class, and stop re-casting for a while.
local function onPetSummonRefused()
    local sp = petState.summonPending
    petState.summonPending = nil
    if not sp or not sp.cls then return end
    petState.summonBlockedUntil[sp.cls] = os.clock() + 60
    if petState.myPets[sp.cls] and isSpawnAlive(petState.myPets[sp.cls]) then return end
    local names = (type(ctrl.pet_names) == 'table') and ctrl.pet_names or {}
    for _, c in ipairs(myClasses) do
        local pid = petState.myPets[c]
        if c ~= sp.cls and pid and isSpawnAlive(pid) then
            local nm = spawnCleanName(pid)
            if not names[c] or string.lower(names[c]) ~= string.lower(nm) then
                trackPet(sp.cls, pid, true)
                print(string.format('\ay[Triune]\ax server says %s already has a pet -- now tracking "%s" as the %s pet.', sp.cls, nm, sp.cls))
                return
            end
        end
    end
    print(string.format('\ay[Triune]\ax server says %s already has a pet but none was detected -- pausing %s pet summons for 60s.', sp.cls, sp.cls))
end

-- 'missing pet' gem condition: does this gem's class need to summon?
local function isPetMissingForClass(cls)
    local now = os.clock()
    local sp = petState.summonPending
    if sp and now < sp.untilAt and (not cls or sp.cls == cls) then return false end
    if cls and (petState.summonBlockedUntil[cls] or 0) > now then return false end
    reconcilePets(true)
    if cls and petState.PET_CLASSES[cls] then
        local pid = petState.myPets[cls]
        return not (pid and pid > 0 and isSpawnAlive(pid))
    end
    return #getAllMyPets() == 0
end

local function getPetSpawnInfo(petId)
    local info = {
        id = petId or 0,
        name = 'Pet',
        cleanName = 'Pet',
        level = 0,
        class = 'Pet',
        race = 'Unknown',
        hpPct = 0,
        curHp = 0,
        maxHp = 0,
        manaPct = 0,
        curMana = 0,
        maxMana = 0,
        endPct = 0,
        curEnd = 0,
        maxEnd = 0,
        dist = 999,
        x = 0,
        y = 0,
        z = 0,
        heading = 0,
        speed = 0,
        state = 'STAND',
        sitting = false,
        feigning = false,
        stunned = false,
        levitating = false,
        targetName = 'None',
        targetHpPct = 0,
        targetDist = 0,
        targetId = 0,
        buffCount = 0,
        buffs = {},
        buffDetails = {}
    }
    if not petId or petId <= 0 then return info end
    pcall(function()
        local s = mq.TLO.Spawn(petId)
        if s and s() and s.ID() and s.ID() > 0 then
            info.cleanName = s.CleanName() or 'Pet'
            info.name = s.Name() or info.cleanName
            info.level = s.Level() or 0
            info.class = s.Class.ShortName() or s.Class() or 'Pet'
            info.race = s.Race() or 'Pet'
            info.hpPct = s.PctHPs() or 0
            info.curHp = s.CurrentHPs() or 0
            info.maxHp = s.MaxHPs() or 0
            info.manaPct = s.PctMana() or 0
            info.curMana = s.CurrentMana() or 0
            info.maxMana = s.MaxMana() or 0
            info.endPct = s.PctEndurance() or 0
            info.curEnd = s.CurrentEndurance() or 0
            info.maxEnd = s.MaxEndurance() or 0
            info.dist = s.Distance() or 0
            info.x = s.X() or 0
            info.y = s.Y() or 0
            info.z = s.Z() or 0
            if s.Heading and s.Heading() then
                info.heading = s.Heading.Degrees() or 0
            end
            info.speed = s.Speed() or 0
            info.state = s.State() or 'STAND'
            info.sitting = s.Sitting() or false
            info.feigning = s.Feigning() or false
            info.stunned = s.Stunned() or false
            info.levitating = s.Levitating() or false

            -- Pet target resolution: general Spawn does not expose .Target in MacroQuest.
            -- Check Me.Pet.Target, Me.Pet.Following, TargetOfTarget, and combat command state.
            local myPetId = 0
            pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)

            local t = nil
            -- 1. Primary pet target from Me.Pet.Target
            if myPetId > 0 and myPetId == petId then
                pcall(function()
                    local pt = mq.TLO.Me.Pet.Target
                    if pt and pt() and (pt.ID() or 0) > 0 then
                        t = pt
                    end
                end)
                if not t then
                    pcall(function()
                        local pf = mq.TLO.Me.Pet.Following
                        if pf and pf() and (pf.ID() or 0) > 0 and pf.Type() == 'NPC' then
                            t = pf
                        end
                    end)
                end
            end

            -- 2. If this pet is currently targeted by player, check Target.TargetOfTarget
            if not t then
                pcall(function()
                    local curTargId = mq.TLO.Target.ID() or 0
                    if curTargId == petId then
                        local tot = mq.TLO.Target.TargetOfTarget
                        if tot and tot() and (tot.ID() or 0) > 0 then
                            t = tot
                        end
                    end
                end)
            end

            -- 3. Spawn TargetOfTarget
            if not t then
                pcall(function()
                    local tot = s.TargetOfTarget
                    if tot and tot() and (tot.ID() or 0) > 0 then
                        t = tot
                    end
                end)
            end

            -- 4. Fallback to active combat command target if pet was ordered to attack and hold is not active
            if not t and petState and not petState.petHoldActive and (petState.lastCmdTargetId or 0) > 0 then
                local cmdTid = petState.lastCmdTargetId
                if isSpawnAlive(cmdTid) and isHostileTarget(cmdTid) then
                    pcall(function()
                        local ts = mq.TLO.Spawn(cmdTid)
                        if ts and ts() and not ts.Dead() and ts.Type() ~= 'Corpse' then
                            t = ts
                        end
                    end)
                end
            end

            -- 5. Fallback: if pet is actively in combat and master has an engaged hostile NPC target
            if not t and petState and not petState.petHoldActive then
                pcall(function()
                    local petInCombat = false
                    if myPetId > 0 and myPetId == petId then
                        petInCombat = mq.TLO.Me.Pet.Combat() or false
                    end
                    if petInCombat then
                        local curTargId = mq.TLO.Target.ID() or 0
                        if curTargId > 0 and isHostileTarget(curTargId) and isSpawnAlive(curTargId) then
                            local ts = mq.TLO.Spawn(curTargId)
                            if ts and ts() and not ts.Dead() and ts.Type() ~= 'Corpse' then
                                t = ts
                            end
                        end
                    end
                end)
            end

            if t and t() and (t.ID() or 0) > 0 and not t.Dead() and t.Type() ~= 'Corpse' then
                info.targetName = t.CleanName() or 'Target'
                info.targetHpPct = t.PctHPs() or 0
                info.targetDist = t.Distance() or 0
                info.targetId = t.ID() or 0
            else
                info.targetName = 'None'
                info.targetHpPct = 0
                info.targetDist = 0
                info.targetId = 0
            end

            -- 1. Try Me.Pet buffs if this is the player's primary pet
            if myPetId > 0 and myPetId == petId then
                for b = 1, 30 do
                    pcall(function()
                        local pb = mq.TLO.Me.Pet.Buff(b)
                        if pb then
                            local bName = nil
                            if type(pb) == 'string' and pb ~= '' then
                                bName = pb
                            elseif pb() and type(pb()) == 'string' and pb() ~= '' then
                                bName = pb()
                            elseif pb.Name and pb.Name() and pb.Name() ~= '' then
                                bName = pb.Name()
                            end
                            if bName and bName ~= '' and bName ~= 'NONE' then
                                local durSec = 0
                                pcall(function()
                                    local dur = mq.TLO.Me.Pet.BuffDuration(b) or 0
                                    if type(dur) == 'number' then
                                        durSec = math.floor(dur / 1000)
                                    end
                                end)
                                table.insert(info.buffs, bName)
                                table.insert(info.buffDetails, { slot = b, name = bName, duration = durSec })
                            end
                        end
                    end)
                end
            end

            -- 2. Try Target buffs if this pet is currently targeted
            local curTargId = 0
            pcall(function() curTargId = mq.TLO.Target.ID() or 0 end)
            if curTargId == petId and #info.buffs == 0 then
                local tbc = 0
                pcall(function() tbc = mq.TLO.Target.BuffCount() or 0 end)
                if tbc > 0 then
                    for b = 1, math.min(tbc, 30) do
                        pcall(function()
                            local tb = mq.TLO.Target.Buff(b)
                            if tb and tb() then
                                local bName = (tb.Name and tb.Name()) or tb()
                                if bName and bName ~= '' and bName ~= 'NONE' then
                                    local durSec = 0
                                    pcall(function()
                                        if tb.Duration and tb.Duration.TotalSeconds then
                                            durSec = tb.Duration.TotalSeconds() or 0
                                        end
                                    end)
                                    table.insert(info.buffs, bName)
                                    table.insert(info.buffDetails, { slot = b, name = bName, duration = durSec })
                                end
                            end
                        end)
                    end
                end
            end

            -- 3. Try Spawn CachedBuffs
            if #info.buffs == 0 then
                local sbc = 0
                pcall(function()
                    sbc = (s.CachedBuffCount and s.CachedBuffCount()) or (s.BuffCount and s.BuffCount()) or 0
                end)
                if sbc > 0 then
                    for b = 1, math.min(sbc, 30) do
                        pcall(function()
                            local sb = s.Buff(b)
                            if sb and sb() then
                                local bName = (sb.Name and sb.Name()) or (sb.Spell and sb.Spell.Name and sb.Spell.Name()) or sb()
                                if bName and bName ~= '' and bName ~= 'NONE' then
                                    local durSec = 0
                                    pcall(function()
                                        if sb.Duration and sb.Duration.TotalSeconds then
                                            durSec = sb.Duration.TotalSeconds() or 0
                                        end
                                    end)
                                    table.insert(info.buffs, bName)
                                    table.insert(info.buffDetails, { slot = b, name = bName, duration = durSec })
                                end
                            end
                        end)
                    end
                end
            end

            -- 4. Cache or fallback to cached buffs in petState
            if #info.buffs > 0 then
                petState.cachedPetBuffs[petId] = {
                    time = os.clock(),
                    buffs = info.buffs,
                    buffDetails = info.buffDetails
                }
            elseif petState.cachedPetBuffs[petId] and (os.clock() - (petState.cachedPetBuffs[petId].time or 0)) < 300 then
                info.buffs = petState.cachedPetBuffs[petId].buffs or {}
                info.buffDetails = petState.cachedPetBuffs[petId].buffDetails or {}
            end

            info.buffCount = #info.buffs
        end
    end)
    return info
end

-- Export to runtime for testability
runtime.classToPetCmdScope = classToPetCmdScope
runtime.sendPetCmd = sendPetCmd
runtime.getMultiPetList = getMultiPetList
runtime.getPetSpawnInfo = getPetSpawnInfo
runtime.reconcilePets = reconcilePets
runtime.isSpawnAlive = isSpawnAlive
runtime.isSpawnMyPet = isSpawnMyPet
runtime.getAllMyPets = getAllMyPets
runtime.isPetMissingForClass = isPetMissingForClass
runtime.updatePetTracking = updatePetTracking

local function distToId(id)
    if not id or id <= 0 then return 9999 end
    local d = 9999
    pcall(function() d = mq.TLO.Spawn(id).Distance() or 9999 end)
    return d
end

local function distToLoc(x, y, z)
    if not x or not y then return 9999 end
    local mx, my, mz = 0, 0, 0
    pcall(function() mx = mq.TLO.Me.X() or 0 end)
    pcall(function() my = mq.TLO.Me.Y() or 0 end)
    pcall(function() mz = mq.TLO.Me.Z() or 0 end)
    local dx, dy = mx - x, my - y
    local dz = z and (mz - z) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Ladders have no dedicated "am I climbing" TLO/flag to read, so this infers
-- it purely from movement: climbing moves Z steadily while X/Y barely change
-- (the opposite of being genuinely stuck, where NOTHING moves, and of normal
-- ground travel, where X/Y change steadily and Z stays flat). Re-samples at
-- most once per LADDER_CLIMB.SAMPLE_SEC so a single tick's jitter can't
-- trigger it, and once a real climb is detected, stays "true" for a short
-- grace period afterward so a momentary pause between rungs (or a slow
-- server tick) doesn't immediately flip callers back to "not climbing" mid-
-- climb. Used by checkStuck() (skip false-positive stuck detection) and
-- moveToward() (skip false-positive pursuit-stall/unreachable marking) --
-- see comments at each call site.
pursuit.LADDER_CLIMB = {
    Z_DELTA    = 3,      -- minimum Z moved per sample to count as climbing
    XY_DELTA   = 3,      -- maximum X/Y moved per sample to still count as climbing (not just running)
    SAMPLE_SEC = 1.0,    -- resample cadence
    GRACE_SEC  = 3.0,    -- keep reporting "climbing" this long after the last positive sample
}
local function isClimbingLadder()
    local LADDER_CLIMB = pursuit.LADDER_CLIMB
    local now = os.clock()
    if (now - (pursuit.climbSampleAt or 0)) >= LADDER_CLIMB.SAMPLE_SEC then
        local x, y, z = 0, 0, 0
        pcall(function() x = mq.TLO.Me.X() or 0 end)
        pcall(function() y = mq.TLO.Me.Y() or 0 end)
        pcall(function() z = mq.TLO.Me.Z() or 0 end)
        if pursuit.climbLastX then
            local dxy = math.sqrt((x - pursuit.climbLastX) ^ 2 + (y - pursuit.climbLastY) ^ 2)
            local dz = math.abs(z - pursuit.climbLastZ)
            if dz >= LADDER_CLIMB.Z_DELTA and dxy <= LADDER_CLIMB.XY_DELTA then
                pursuit.climbingUntil = now + LADDER_CLIMB.GRACE_SEC
            end
        end
        pursuit.climbLastX, pursuit.climbLastY, pursuit.climbLastZ = x, y, z
        pursuit.climbSampleAt = now
    end
    return (pursuit.climbingUntil or 0) > now
end

local function hasLoS(id)
    if not id or id <= 0 then return false end
    local los = false
    pcall(function() los = mq.TLO.Spawn(id).LineOfSight() or false end)
    return los
end

local function pctHP(id)
    if not id or id <= 0 then return 100 end
    local meId = nil
    pcall(function() meId = mq.TLO.Me.ID() end)
    if meId and id == meId then
        local meHp = 100
        pcall(function() meHp = mq.TLO.Me.PctHPs() or 100 end)
        return meHp
    end
    local hp = 100
    pcall(function()
        local s = mq.TLO.Spawn(id)
        if s and s() then
            hp = s.PctHPs() or 100
        end
    end)
    return hp
end



local function sungKey(spellName, targetId)
    return string.format('%d_%s', targetId or 0, spellName or '')
end

local function navLoaded()
    local ok, loaded = pcall(function()
        if mq.TLO.Navigation and (mq.TLO.Navigation() ~= nil or mq.TLO.Navigation.MeshLoaded() ~= nil) then
            return true
        end
        local p = mq.TLO.Plugin('mq2nav') or mq.TLO.Plugin('MQ2Nav') or mq.TLO.Plugin('nav')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end

local function navMeshLoaded()
    if not navLoaded() then return false end
    local ok, loaded = pcall(function()
        return mq.TLO.Navigation.MeshLoaded() or false
    end)
    return ok and (loaded == true)
end

local function stickLoaded()
    local ok, loaded = pcall(function()
        if mq.TLO.Stick and (mq.TLO.Stick() ~= nil or mq.TLO.Stick.Status() ~= nil) then
            return true
        end
        local p = mq.TLO.Plugin('mq2moveutils') or mq.TLO.Plugin('MQ2MoveUtils') or mq.TLO.Plugin('moveutils')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end

function runtime.mapLoaded()
    local ok, loaded = pcall(function()
        if mq.TLO.Map and mq.TLO.Map() ~= nil then
            return true
        end
        local p = mq.TLO.Plugin('mq2map') or mq.TLO.Plugin('MQ2Map') or mq.TLO.Plugin('map')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end

function runtime.fovLoaded()
    local ok, loaded = pcall(function()
        local p = mq.TLO.Plugin('mq2fov') or mq.TLO.Plugin('MQ2FOV') or mq.TLO.Plugin('fov')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end


local function isMoveActive()
    local navActive, moveActive, moveToActive, nativeActive = false, false, false, false
    if navLoaded() then
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
    end
    if stickLoaded() then
        pcall(function()
            if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                moveActive = mq.TLO.Me.Moving() or false
            end
        end)
    end
    pcall(function()
        if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving then
            moveToActive = mq.TLO.MoveTo.Moving() or false
        end
    end)
    if (pursuit.lastNavLoc and string.find(tostring(pursuit.lastNavLoc), '^native_')) or
       (pursuit.lastNavTargetId and string.find(tostring(pursuit.lastNavTargetId), '^native_')) then
        if mq.TLO.Me.Moving() then
            nativeActive = true
        end
    end
    return navActive or moveActive or moveToActive or nativeActive
end

local function stopMoving()
    if navLoaded() then
        local navActive = false
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
        if navActive then pcall(function() mq.cmd('/nav stop') end) end
    end
    if stickLoaded() then
        local stickActive = false
        pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
        if stickActive then
            pcall(function() mq.cmd('/stick off') end)
        end
    end
    pcall(function()
        if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving() then
            mq.cmd('/moveto off')
        end
    end)
    if (pursuit.lastNavLoc and string.find(tostring(pursuit.lastNavLoc), '^native_')) or
       (pursuit.lastNavTargetId and string.find(tostring(pursuit.lastNavTargetId), '^native_')) then
        pcall(function() mq.cmd('/keypress forward') end)
        pcall(function() mq.cmd('/keypress back') end)
    end
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.lastStickDist = 0
    pursuit.lastBehindStickDist = 0
    pursuit.lastFrontStickDist = 0
    pursuit.meshRecoverId = 0
    pursuit.meshRecoverAt = 0
    pursuit.detourActive = false
    pursuit.detourX = 0
    pursuit.detourY = 0
    pursuit.detourZ = 0
    pursuit.detourTargetId = 0
    pursuit.detourTargetKey = nil
    pursuit.detourStartedAt = 0
    pursuit.detourExpiresAt = 0
end

function runtime.stopMovementForCast(cls, spell)
    -- Bards can sing songs while running in EverQuest
    if cls == 'Brd' then return end
    local isBrd = false
    pcall(function() isBrd = (mq.TLO.Me.Class.ShortName() == 'BRD') end)
    if isBrd and (not cls or cls == 'Brd') then return end

    -- Halt active MQ2Nav
    if navLoaded() then
        local navActive = false
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
        if navActive then
            pcall(function() mq.cmd('/nav stop') end)
            pursuit.id = 0
            pursuit.lastNavTargetId = 0
            pursuit.lastNavLoc = nil
        end
    end

    -- Pause MQ2Stick if active so it can cleanly unpause post-cast
    if stickLoaded() then
        pcall(function()
            if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                mq.cmd('/stick pause')
            end
        end)
    end

    -- Halt active MQ2MoveTo
    pcall(function()
        if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving() then
            mq.cmd('/moveto off')
        end
    end)

    -- Release keyboard movement keys and wait briefly for momentum to stop
    local isMoving = false
    pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
    if isMoving then
        pcall(function() mq.cmd('/keypress forward') end)
        pcall(function() mq.cmd('/keypress back') end)
        pcall(function() mq.cmd('/keypress strafe_left') end)
        pcall(function() mq.cmd('/keypress strafe_right') end)
        local waitStop = 0
        while waitStop < 200 do
            local stillMoving = false
            pcall(function() stillMoving = mq.TLO.Me.Moving() or false end)
            if not stillMoving then break end
            local ok = pcall(function() mq.delay(20) end)
            if not ok then break end
            waitStop = waitStop + 20
        end
    end
end


-- Spawn ids MQ2Nav has told us have no path to. Cleared after 60s in case terrain
-- state changes (a door opens, etc). findRoamTarget skips these when picking a
-- fresh target; Hunter/Puller drop their current target the moment it lands here
-- rather than continuing to sit on something they can never reach.
function runtime.markUnreachable(id)
    pursuit.unreachableIds[id] = os.clock()
    if runtime.clearDetour then runtime.clearDetour() end
end

local function isUnreachable(id)
    local t = pursuit.unreachableIds[id]
    if not t then return false end
    if (os.clock() - t) > 60 then
        pursuit.unreachableIds[id] = nil; return false
    end
    return true
end

-- ignore-list helpers: applies only to Hunter/Puller AUTO-targeting (see findRoamTarget
-- below); Assist and anything you target yourself are never filtered.
local function isIgnored(name)
    if not name then return false end
    local cleanName = tostring(name)
    if cleanName == '' then return false end
    if not runtime.ignoreList then return false end
    for _, n in ipairs(runtime.ignoreList) do
        if tostring(n) == cleanName then return true end
    end
    return false
end

-- Returns true if the spawn ID belongs to the player, their pet, any group member,
-- any group member pet, or any raid member.
-- Set of friendly spawn IDs: me, my pet, group members and their pets, raid
-- members. isGroupOrRaidMember() runs several times per XTarget slot per scan
-- and many scans per combat tick, so walking the Group/Raid TLOs on every call
-- was the single largest per-tick cost (tens of thousands of TLO reads in a
-- raid). Rebuilt at most every 0.5s; a spawn that joins inside that window is
-- still caught by isSpawnPetOrPlayer's live Type/Master/Owner checks.
function runtime.getFriendlyIdSet()
    local now = os.clock()
    local c = runtime.friendlyIdCache
    if c and (now - c.at) < 0.5 then return c.set end
    local set = {}
    pcall(function()
        local meId = mq.TLO.Me.ID() or 0
        if meId > 0 then set[meId] = true end
        local myPetId = mq.TLO.Me.Pet.ID() or 0
        if myPetId > 0 then set[myPetId] = true end
    end)
    pcall(function()
        for i = 1, (mq.TLO.Group.Members() or 0) do
            local m = mq.TLO.Group.Member(i)
            if m and m() then
                local mid = m.ID() or 0
                if mid > 0 then set[mid] = true end
                local mPet = m.Pet
                if mPet and mPet() then
                    local pid = mPet.ID() or 0
                    if pid > 0 then set[pid] = true end
                end
            end
        end
    end)
    pcall(function()
        for i = 1, (mq.TLO.Raid.Members() or 0) do
            local rm = mq.TLO.Raid.Member(i)
            if rm and rm() then
                local rid = rm.ID() or 0
                if rid > 0 then set[rid] = true end
            end
        end
    end)
    runtime.friendlyIdCache = { at = now, set = set }
    return set
end

local function isGroupOrRaidMember(id)
    if not id or id <= 0 then return false end
    if runtime.getFriendlyIdSet()[id] then return true end
    if petState and type(petState.myPets) == 'table' then
        for _, petId in pairs(petState.myPets) do
            if petId == id then return true end
        end
    end
    return false
end

-- Returns true if a spawn (or spawn ID) is ANY pet (player pet, group pet, mercenary,
-- charmed minion, familiar, warder, or NPC pet). Used when finding new roam/pull/hunt targets
-- so the bot never initiates combat on pets.
local function isAnyPet(s_or_id)
    if not s_or_id then return false end
    local s = (type(s_or_id) == 'number') and mq.TLO.Spawn(s_or_id) or s_or_id
    if not s or not s() then return false end

    local isPetSpawn = false
    pcall(function()
        local stype = s.Type() or ''
        if stype == 'Pet' then isPetSpawn = true return end

        local m = s.Master
        if m and m() and (m.ID() or 0) > 0 then
            isPetSpawn = true
            return
        end

        local o = s.Owner
        if o and o() and (o.ID() or 0) > 0 then
            isPetSpawn = true
            return
        end

        local cname = s.CleanName() or ''
        if cname ~= '' then
            if cname:find("`s pet", 1, true) or cname:find("'s pet", 1, true) or
               cname:find("`s warder", 1, true) or cname:find("'s warder", 1, true) or
               cname:find("`s Familiar", 1, true) or cname:find("'s Familiar", 1, true) or
               cname:find("`s familiar", 1, true) or cname:find("'s familiar", 1, true) then
                isPetSpawn = true
                return
            end
        end
    end)
    return isPetSpawn
end

-- Returns true if spawn ID is self, player pet, group member pet, player character, or pet of a player/mercenary
local function isSpawnPetOrPlayer(id)
    if not id or id <= 0 then return false end
    if isGroupOrRaidMember(id) then return true end -- me, my pets, group/raid + their pets

    local s = mq.TLO.Spawn(id)
    if not s or not s() then return false end

    local isPlayerOrFriendly = false
    pcall(function()
        if s.Trader and s.Trader() then isPlayerOrFriendly = true return end
        local stype = s.Type() or ''
        if stype == 'PC' or stype == 'Mercenary' then isPlayerOrFriendly = true return end

        local m = s.Master
        if m and m() then
            local mid = m.ID() or 0
            if mid > 0 then
                local mt = m.Type() or ''
                if mt == 'PC' or mt == 'Mercenary' or mid == mq.TLO.Me.ID() or isGroupOrRaidMember(mid) then
                    isPlayerOrFriendly = true
                    return
                end
            end
        end

        local o = s.Owner
        if o and o() then
            local oid = o.ID() or 0
            if oid > 0 then
                local ot = o.Type() or ''
                if ot == 'PC' or ot == 'Mercenary' or oid == mq.TLO.Me.ID() or isGroupOrRaidMember(oid) then
                    isPlayerOrFriendly = true
                    return
                end
            end
        end

        if stype == 'Pet' then
            local cname = s.CleanName() or ''
            if cname:find("`s pet", 1, true) or cname:find("'s pet", 1, true) or
               cname:find("`s warder", 1, true) or cname:find("'s warder", 1, true) or
               cname:find("`s Familiar", 1, true) or cname:find("'s Familiar", 1, true) or
               cname:find("`s familiar", 1, true) or cname:find("'s familiar", 1, true) then
                isPlayerOrFriendly = true
                return
            end
        end
    end)

    return isPlayerOrFriendly
end

-- Returns true when the given spawn ID is a confirmed hostile target that
-- should receive offensive actions (spells, AAs, discs, auto-attack).
-- Prevents the engine from accidentally casting on friendly NPCs (merchants,
-- quest givers, guards, bankers) or pets that happen to be targeted.
-- Live hostile check: a non-friendly NPC/Pet spawn that exists and is not dead.
-- This is the single source of truth the XTarget scanners below lean on, so keep
-- every "is this a valid enemy" rule here rather than duplicating it at callers.
isHostileTarget = function(id)
    if not id or id <= 0 then return false end
    if isSpawnPetOrPlayer(id) then return false end

    local s = mq.TLO.Spawn(id)
    if not s or not s() then return false end
    if s.Dead and s.Dead() then return false end

    local stype, state = '', ''
    pcall(function()
        stype = s.Type() or ''
        state = s.State() or ''
    end)
    if stype ~= 'NPC' and stype ~= 'Pet' then return false end
    if state == 'DEAD' then return false end

    return true
end

-- True if `id` occupies an XTarget slot and is a live, non-ignored hostile.
-- isHostileTarget() already covers the friendly / dead / type checks.
local function isXTargetId(id)
    if not id or id <= 0 then return false end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) == id then
            return isHostileTarget(id) and not isIgnored(xt.CleanName())
        end
    end
    return false
end

local function hasActualNPCXtarget()
    local found = false
    pcall(function()
        local slots = mq.TLO.Me.XTargetSlots() or 13
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt and xt() then
                local id = xt.ID() or 0
                if id > 0 and isHostileTarget(id) and not isIgnored(xt.CleanName()) then
                    found = true
                    return
                end
            end
        end
    end)
    return found
end

local function findFirstNPCXtarget(unmezzedOnly, isIgnoredFn, isUnreachableFn, maxDist, maxZ, isBuffActiveFn)
    maxDist = maxDist or (ctrl and ctrl.xtar_nav_dist) or 150
    local myZ = mq.TLO.Me.Z() or 0
    local chosenId, lowestHp = nil, 101
    pcall(function()
        local slots = mq.TLO.Me.XTargetSlots() or 13
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isHostileTarget(id) then
                    local s = mq.TLO.Spawn(id)
                    if s() then
                        local cname = s.CleanName() or ''
                        local dist = 999
                        local okDist, sDist = pcall(function() return s.Distance3D() or s.Distance() end)
                        if okDist and sDist then dist = sDist end
                        local okZ, sz = pcall(function() return s.Z() end)
                        local zOk = (not maxZ) or (okZ and sz and math.abs(sz - myZ) <= maxZ)
                        if dist <= maxDist
                            and zOk
                            and (not isIgnoredFn or not isIgnoredFn(cname))
                            and (not isUnreachableFn or not isUnreachableFn(id)) then
                            if not unmezzedOnly or not (isBuffActiveFn and isBuffActiveFn(id, 'Mez')) then
                                local hp = s.PctHPs() or 100
                                if hp < lowestHp then
                                    lowestHp = hp
                                    chosenId = id
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return chosenId
end

local function findMaPcId(maName)
    if not maName or maName == '' then return nil end
    local id = nil
    pcall(function()
        local s = mq.TLO.Spawn('pc ' .. maName)
        if s and s() and isSpawnAlive(s.ID()) then id = s.ID() end
    end)
    return id
end

local function isDetrimentalSpell(name, targetId, kind, targetToken)
    if not name or name == '' then return false end
    if type(name) == 'string' then name = name:match('^%s*(.-)%s*$') end
    if not name or name == '' then return false end

    -- 1. Check kind tag if explicitly provided ('heal', 'buff', 'pet', 'cure', 'util' -> beneficial; 'dd', 'dot', 'debuff', 'nuke' -> detrimental)
    if kind then
        local k = tostring(kind):lower()
        if k == 'dd' or k == 'dot' or k == 'debuff' or k == 'nuke' then return true end
        if k == 'heal' or k == 'buff' or k == 'pet' or k == 'cure' or k == 'util' then return false end
    end

    -- 2. Check targetToken if provided ('E:' -> detrimental enemy; 'F:', 'S:', 'P:', 'G:', 'A:', 'C:' -> beneficial friendly)
    if targetToken then
        local tok = tostring(targetToken)
        if tok:sub(1, 2) == 'E:' then return true end
        if tok:sub(1, 2) == 'F:' or tok:sub(1, 2) == 'S:' or tok:sub(1, 2) == 'P:' or tok:sub(1, 2) == 'G:' or tok:sub(1, 2) == 'A:' or tok:sub(1, 2) == 'C:' then
            return false
        end
    end

    -- 3. Live MacroQuest TLO queries (authoritative in-game)
    local isBene = nil
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then isBene = sp.Beneficial() end
    end)
    if isBene == true then return false end
    if isBene == false then return true end

    pcall(function()
        local aa = mq.TLO.Me.AltAbility(name)
        if aa and aa() then
            local sp = aa.Spell
            if sp and sp() then isBene = sp.Beneficial() end
        end
    end)
    if isBene == true then return false end
    if isBene == false then return true end

    pcall(function()
        local ca = mq.TLO.Me.CombatAbility(name)
        if ca and ca() then
            local sp = ca.Spell
            if sp and sp() then isBene = sp.Beneficial() end
        end
    end)
    if isBene == true then return false end
    if isBene == false then return true end

    -- 4. Check database (DATA.spells) if loaded
    if DATA and DATA.spells then
        for _, list in pairs(DATA.spells) do
            if type(list) == 'table' then
                for _, it in ipairs(list) do
                    if it[1] == name then
                        if it[3] == 1 then return false end
                        if it[3] == 0 then return true end
                        local sKind = it[4]
                        if sKind == 'heal' or sKind == 'buff' or sKind == 'pet' or sKind == 'cure' or sKind == 'util' then return false end
                        if sKind == 'dd' or sKind == 'dot' or sKind == 'debuff' then return true end
                    end
                end
            end
        end
    end

    -- 5. Fallback name heuristics (for unit tests, custom items, or offline sandbox)
    local lowerName = name:lower()
    if lowerName:find('heal') or lowerName:find('buff') or lowerName:find('skin') or lowerName:find('spirit')
        or lowerName:find('aegis') or lowerName:find('breeze') or lowerName:find('clarity') or lowerName:find('haste')
        or lowerName:find('focus') or lowerName:find('valor') or lowerName:find('canni') or lowerName:find('gate')
        or lowerName:find('cure') or lowerName:find('summon') or lowerName:find('pet') or lowerName:find('resurrect')
        or lowerName:find('revive') or lowerName:find('regeneration') or lowerName:find('chloroplast')
        or lowerName:find('alacrity') or lowerName:find('symbol') or lowerName:find('armor') or lowerName:find('shield')
        or lowerName:find('rune') or lowerName:find('pact') or lowerName:find('infusion') then
        return false
    end

    if lowerName:find('kick') or lowerName:find('bash') or lowerName:find('backstab') or lowerName:find('frenzy')
        or lowerName:find('slam') or lowerName:find('strike') or lowerName:find('taunt') or lowerName:find('disarm')
        or lowerName:find('dragon punch') or lowerName:find('eagle strike') or lowerName:find('round kick') or lowerName:find('tiger claw')
        or lowerName:find('nuke') or lowerName:find('dot') or lowerName:find('debuff') or lowerName:find('slow')
        or lowerName:find('tash') or lowerName:find('malo') or lowerName:find('snare') or lowerName:find('root')
        or lowerName:find('mez') or lowerName:find('comet') or lowerName:find('bolt') or lowerName:find('blast')
        or lowerName:find('shock') or lowerName:find('poison') or lowerName:find('disease') or lowerName:find('lifetap')
        or lowerName:find('lifedraw') or lowerName:find('lifespike') or lowerName:find('siphon life')
        or lowerName:find('drain') or lowerName:find('scourge') or lowerName:find('torment') or lowerName:find('burn')
        or lowerName:find('fire') or lowerName:find('frost') or lowerName:find('ice') or lowerName:find('chill')
        or lowerName:find('flame') or lowerName:find('ignite') or lowerName:find('sear') or lowerName:find('doom')
        or lowerName:find('enstill') or lowerName:find('immobil') or lowerName:find('paralyz') or lowerName:find('blind')
        or lowerName:find('fear') or lowerName:find('charm') or lowerName:find('stun') or lowerName:find('drowsy')
        or lowerName:find('curse') or lowerName:find('rot') or lowerName:find('decay') or lowerName:find('pox')
        or lowerName:find('fever') or lowerName:find('plague') or lowerName:find('rend') or lowerName:find('bite') then
        return true
    end

    return false
end

local function createCastTracker()
    local failureCount     = {} -- [spellName] = { count = N, lastFail = timestamp }
    local lockouts         = {} -- [spellName] = untilTimestamp (global lockouts)
    local targetLockouts   = {} -- [targetId] = { [spellName] = untilTimestamp } (target-specific backoffs)
    local targetImmunities = {} -- [targetId] = { [spellName] = true } (permanent target immunities)

    local tracker = {}

    local function getFailCount(spellName)
        if not spellName then return 0 end
        local entry = failureCount[spellName]
        if not entry then return 0 end
        -- 15-second TTL decay for accumulated transient failure count
        if (os.clock() - (tonumber(entry.lastFail) or 0)) > 15.0 then
            failureCount[spellName] = nil
            return 0
        end
        return tonumber(entry.count) or 0
    end

    local function incFailCount(spellName)
        if not spellName then return 1 end
        local count = getFailCount(spellName) + 1
        failureCount[spellName] = { count = count, lastFail = os.clock() }
        return count
    end

    local function resetFailCount(spellName)
        if spellName then failureCount[spellName] = nil end
    end

    local function isLockedOut(spellName, targetId, kind)
        if not spellName or spellName == '' then return false end

        -- Strictly enforce: Beneficial spells are NEVER locked out under any circumstance.
        -- Only casted detrimental spells can ever be locked out.
        if not isDetrimentalSpell(spellName, targetId, kind) then
            return false
        end

        local tid = tonumber(targetId)

        -- 1. Target Immunity check (permanent for this spawn ID)
        if tid and tid > 0 and targetImmunities[tid] and targetImmunities[tid][spellName] then
            return true, 'Immune', 9999
        end

        -- 2. Target-specific lockout check (e.g. resisted debuff backoff, stacking conflict backoff on detrimental spells)
        if tid and tid > 0 and targetLockouts[tid] then
            local untilTime = tonumber(targetLockouts[tid][spellName])
            if untilTime then
                if os.clock() < untilTime then
                    return true, 'TargetLock', math.ceil(untilTime - os.clock())
                else
                    targetLockouts[tid][spellName] = nil
                end
            end
        end

        -- 3. Global lockout check
        local gUntil = tonumber(lockouts[spellName])
        if gUntil then
            if os.clock() < gUntil then
                return true, 'GlobalLock', math.ceil(gUntil - os.clock())
            else
                lockouts[spellName] = nil
            end
        end

        return false
    end

    local function recordFailure(spellName, targetId, reason, maxRetries, lockoutSec, kind)
        if not spellName or spellName == '' then return end
        local tid
        local r = 'generic'
        local mRetries
        local lSec
        local k = kind

        if type(targetId) == 'number' and (type(reason) == 'string' or reason == nil) then
            tid = targetId
            r = reason or 'generic'
            mRetries = tonumber(maxRetries) or 2
            lSec = tonumber(lockoutSec) or 30
        elseif type(targetId) == 'string' then
            r = targetId
            mRetries = tonumber(reason) or 2
            lSec = tonumber(maxRetries) or 30
            k = lockoutSec
        elseif type(targetId) == 'number' and type(reason) == 'number' then
            mRetries = targetId
            lSec = tonumber(reason) or 30
            r = 'generic'
        else
            mRetries = tonumber(maxRetries) or 2
            lSec = tonumber(lockoutSec) or 30
        end

        -- Beneficial spells (heals, buffs, pets, cures) are NEVER locked out under any condition.
        -- Only casted detrimental spells (offensive spells/debuffs) incur failures, immunities, or lockouts.
        if not isDetrimentalSpell(spellName, tid, k) then
            resetFailCount(spellName)
            return
        end

        local rLow = tostring(r):lower()

        if rLow == 'target immune' or rLow == 'immune' then
            -- Mob Immunity: Record permanently for this target ID (0 retries wasted). Does NOT lock globally.
            if tid and tid > 0 then
                targetImmunities[tid] = targetImmunities[tid] or {}
                targetImmunities[tid][spellName] = true
                resetFailCount(spellName)
                local tName = 'Target'
                pcall(function()
                    local s = mq.TLO.Spawn(tid)
                    if s and s() then tName = s.CleanName() or s.Name() or 'Target' end
                end)
                print(string.format('\ar[Triune]\ax Immunity registered for "%s" on %s (ID %d) -- skipping further casts on this mob.', spellName, tName, tid))
            else
                lockouts[spellName] = os.clock() + lSec
                resetFailCount(spellName)
                print(string.format('\ar[Triune]\ax Global lockout applied for "%s" (%ds) due to immunity.', spellName, lSec))
            end

        elseif rLow == 'did not take hold' then
            -- Non-stacking debuff conflict on enemy mob: back off on this target for 120s (or custom lockoutSec), do NOT block other targets.
            local backoff = math.max(lSec, 120)
            if tid and tid > 0 then
                targetLockouts[tid] = targetLockouts[tid] or {}
                targetLockouts[tid][spellName] = os.clock() + backoff
                resetFailCount(spellName)
                if runtime and runtime.npcSpellApplied and runtime.npcSpellApplied[tid] then
                    runtime.npcSpellApplied[tid][spellName] = nil
                end
                print(string.format('\ay[Triune]\ax Detrimental spell "%s" did not take hold on target #%d -- backing off on this target (%ds).', spellName, tid, backoff))
            else
                lockouts[spellName] = os.clock() + lSec
                resetFailCount(spellName)
            end

        elseif rLow == 'resisted' then
            if tid and tid > 0 and spellName and spellName ~= '' then
                if runtime and runtime.npcSpellApplied and runtime.npcSpellApplied[tid] then
                    runtime.npcSpellApplied[tid][spellName] = nil
                end
            end
            -- Resists:
            -- If kind is direct damage ('dd') or damage over time ('dot'), NEVER lock out on resists!
            if k == 'dd' or k == 'dot' then
                resetFailCount(spellName)
                return
            end
            -- For debuffs, CC, and util: retry up to maxRetries, then back off on this target
            local fails = incFailCount(spellName)
            if fails >= mRetries then
                if tid and tid > 0 then
                    targetLockouts[tid] = targetLockouts[tid] or {}
                    targetLockouts[tid][spellName] = os.clock() + lSec
                    resetFailCount(spellName)
                    print(string.format('\ar[Triune]\ax Debuff "%s" resisted %d times by target #%d -- backing off on this target (%ds).', spellName, fails, tid, lSec))
                else
                    lockouts[spellName] = os.clock() + lSec
                    resetFailCount(spellName)
                    print(string.format('\ar[Triune]\ax Lockout applied for "%s" (%ds) after %d resists.', spellName, lSec, fails))
                end
            end

        elseif rLow == 'fizzled' or rLow == 'interrupted' then
            local failTid = (tid and tid > 0 and tid) or (tracker and tracker.activeTargetId)
            local failSpell = (spellName and spellName ~= '' and spellName) or (tracker and tracker.activeSpell)
            if failTid and failTid > 0 and failSpell and failSpell ~= '' then
                if runtime and runtime.npcCastCounts and runtime.npcCastCounts[failTid] and (runtime.npcCastCounts[failTid][failSpell] or 0) > 0 then
                    runtime.npcCastCounts[failTid][failSpell] = runtime.npcCastCounts[failTid][failSpell] - 1
                end
                if runtime and runtime.npcSpellApplied and runtime.npcSpellApplied[failTid] then
                    runtime.npcSpellApplied[failTid][failSpell] = nil
                end
            end
            -- Transient combat mechanics: retry on gem refresh.
            -- Only back off if severely repeating on detrimental spell (e.g. 4+ consecutive failures within 15s)
            local threshold = math.max(mRetries * 2, 4)
            local fails = incFailCount(spellName)
            if fails >= threshold then
                local shortLock = math.min(lSec, 8)
                lockouts[spellName] = os.clock() + shortLock
                resetFailCount(spellName)
                print(string.format('\ay[Triune]\ax Detrimental spell "%s" %s %d times consecutively -- brief pause applied (%ds).', spellName, rLow, fails, shortLock))
            end

        elseif rLow == 'cannot see target' or rLow == 'out of range' or rLow == 'dead target'
            or rLow == 'cannot cast' or rLow == 'insufficient mana' or rLow == 'not ready' then
            -- Positional, dead target, or timing states: Zero failure penalty / zero lockout
            return

        else
            -- Generic failure fallback (detrimental spells only)
            local fails = incFailCount(spellName)
            if fails >= mRetries then
                lockouts[spellName] = os.clock() + lSec
                resetFailCount(spellName)
                print(string.format('\ar[Triune]\ax Lockout applied for "%s" (%ds) [%s].', spellName, lSec, rLow))
            end
        end
    end

    local function recordSuccess(spellName, targetId)
        if not spellName then return end
        resetFailCount(spellName)
        lockouts[spellName] = nil
        local tid = tonumber(targetId)
        if tid and tid > 0 and targetLockouts[tid] then
            targetLockouts[tid][spellName] = nil
        end
    end

    local function onFailureEvent(reason, maxRetries, lockoutSec, eventSpell, eventTargetId)
        local now = os.clock()
        local isCastRecent = (now - (tonumber(tracker.castStartTime) or 0)) <= 1.5
        local castingId = nil
        pcall(function() castingId = mq.TLO.Me.Casting.ID() end)
        local isActivelyCasting = (castingId ~= nil and castingId > 0)
        if not tracker.wasCasting and not isCastRecent and not isActivelyCasting then
            return
        end

        local castingName = eventSpell
        if not castingName or castingName == '' then
            pcall(function() castingName = mq.TLO.Me.Casting.Name() end)
        end
        if not castingName or castingName == '' then
            castingName = tracker.activeSpell
        end
        if not castingName or castingName == '' then
            if isCastRecent then
                castingName = tracker.lastSpell
            end
        end

        if castingName and castingName ~= '' then
            local tid = eventTargetId or tracker.activeTargetId
            if not tid or tid <= 0 then
                pcall(function() tid = mq.TLO.Target.ID() end)
            end

            -- Only casted detrimental spells incur failure tracking or lockouts
            if isDetrimentalSpell(castingName, tid, tracker.activeKind) then
                tracker.failed = true
                recordFailure(castingName, tid, reason, maxRetries, lockoutSec, tracker.activeKind)
            else
                tracker.failed = false
            end
        end
    end

    local function clear(targetId)
        local tid = tonumber(targetId)
        if tid and tid > 0 then
            targetLockouts[tid] = nil
            targetImmunities[tid] = nil
        else
            failureCount     = {}
            lockouts         = {}
            targetLockouts   = {}
            targetImmunities = {}
        end
    end

    local function getActiveCount()
        local count = 0
        local now = os.clock()
        for _, t in pairs(lockouts) do
            if now < (tonumber(t) or 0) then count = count + 1 end
        end
        for _, tMap in pairs(targetLockouts) do
            for _, t in pairs(tMap) do
                if now < (tonumber(t) or 0) then count = count + 1 end
            end
        end
        for _, immMap in pairs(targetImmunities) do
            for _, _ in pairs(immMap) do count = count + 1 end
        end
        return count
    end

    tracker.recordFailure  = recordFailure
    tracker.recordSuccess  = recordSuccess
    tracker.isLockedOut    = isLockedOut
    tracker.onFailureEvent = onFailureEvent
    tracker.clear          = clear
    tracker.getActiveCount = getActiveCount
    tracker.getFailCount   = getFailCount
    tracker.resetFailCount = resetFailCount
    tracker.failed         = false
    tracker.activeSpell    = nil
    tracker.activeTargetId = nil
    tracker.activeKind     = nil
    tracker.castStartTime  = 0
    tracker.lastSpell      = nil
    tracker.wasCasting     = false

    return tracker
end

local castTracker = createCastTracker()

local function isCasting()
    local cid = nil
    pcall(function() cid = mq.TLO.Me.Casting.ID() end)
    return cid ~= nil and cid > 0
end
runtime.isCasting = isCasting

local function isTargetRequiredSpell(spell)
    if not spell then return false end
    local sp = nil
    if type(spell) == 'string' or type(spell) == 'number' then
        pcall(function() sp = mq.TLO.Spell(spell) end)
    else
        sp = spell
    end
    if not sp or not sp() then return false end
    local tt = nil
    pcall(function() tt = sp.TargetType() end)
    if not tt or tt == '' or tt == 'NULL' then return false end
    local s = tostring(tt):lower()
    if s == 'self' or s == 'pb ae' or s == 'group v1' or s == 'group v2' or s:find('group') then
        return false
    end
    return true
end
runtime.isTargetRequiredSpell = isTargetRequiredSpell

local function isCastingOrStarting()
    if isCasting() then return true end
    if castTracker and castTracker.activeSpell and not castTracker.failed and castTracker.castStartTime and castTracker.castStartTime > 0 then
        local elapsed = os.clock() - castTracker.castStartTime
        if elapsed >= 0 and elapsed < 0.8 then
            return true
        end
    end
    return false
end
runtime.isCastingOrStarting = isCastingOrStarting

local function getActiveTargetRequiredCastingId()
    if not isCastingOrStarting() then return nil end

    if castTracker and castTracker.targetRequired and castTracker.activeTargetId and castTracker.activeTargetId > 0 then
        if castTracker.activeTargetId == mq.TLO.Me.ID() then
            local tid = mq.TLO.Target.ID() or 0
            if tid > 0 and isHostileTarget and isHostileTarget(tid) then
                return nil
            end
        end
        return castTracker.activeTargetId
    end

    local activeCasting = false
    pcall(function()
        local cid = mq.TLO.Me.Casting.ID()
        activeCasting = (cid ~= nil and cid > 0)
    end)
    if activeCasting then
        local req = false
        pcall(function()
            local c = mq.TLO.Me.Casting
            if c and c() and isTargetRequiredSpell(c) then
                req = true
            end
        end)
        if req then
            local tid = castTracker and castTracker.activeTargetId
            if not tid or tid <= 0 then
                pcall(function() tid = mq.TLO.Target.ID() end)
            end
            if tid and tid > 0 then
                if tid == mq.TLO.Me.ID() then
                    local curT = mq.TLO.Target.ID() or 0
                    if curT > 0 and isHostileTarget and isHostileTarget(curT) then
                        return nil
                    end
                end
                return tid
            end
        end
    end

    return nil
end
runtime.getActiveTargetRequiredCastingId = getActiveTargetRequiredCastingId

local function clearTarget()
    local reqTargetId = getActiveTargetRequiredCastingId()
    if reqTargetId and reqTargetId > 0 then
        return false
    end
    mq.cmd('/target clear')
    return true
end
runtime.clearTarget = clearTarget

local function clearCursor()
    local item = mq.TLO.Cursor
    if not item() or (item.ID() or 0) <= 0 then return false end
    pcall(function()
        local count = 0
        while (mq.TLO.Cursor.ID() or 0) > 0 and count < 255 do
            mq.cmd('/autoinventory')
            mq.delay(50)
            count = count + 1
        end
    end)
    return true
end

function runtime.checkBook(name)
    if not name or name == '' then return nil end
    local foundSlot = nil
    pcall(function()
        local res = mq.TLO.Me.Book(name)()
        if type(res) == 'number' and res > 0 then
            foundSlot = res
        elseif type(res) == 'string' and tonumber(res) and tonumber(res) > 0 then
            foundSlot = tonumber(res)
        end
    end)
    return foundSlot
end

function runtime.getSpellbookMap()
    local now = os.time()
    if runtime.spellbookMapCache and (now - (runtime.lastSpellbookMapCacheTime or 0)) < 3 then
        return runtime.spellbookMapCache
    end

    local map = { exact = {}, norm = {}, list = {} }

    for s = 1, 720 do
        local bName = nil
        pcall(function() bName = mq.TLO.Me.Book(s).Name() end)
        if not bName or bName == "" or bName == "NULL" then
            pcall(function()
                local res = mq.TLO.Me.Book(s)()
                if type(res) == "string" and res ~= "" and res ~= "NULL" then bName = res end
            end)
        end

        if bName and bName ~= "" and bName ~= "NULL" then
            local lowerName = bName:lower()
            local cleanName = cleanSpellName(bName):lower()
            local normName = normalizeSpellName(bName)

            map.exact[lowerName] = s
            map.exact[cleanName] = s
            if normName ~= "" then map.norm[normName] = s end
            table.insert(map.list, { slot = s, name = bName, norm = normName })
        end
    end
    runtime.spellbookMapCache = map
    runtime.lastSpellbookMapCacheTime = now
    return map
end

function runtime.getSpellBookSlot(spellName)
    if not spellName or spellName == '' then return nil end

    local sbMap = runtime.getSpellbookMap()
    local targetLower = spellName:lower()
    local cleaned = cleanSpellName(spellName)
    local targetCleanLower = cleaned:lower()
    local targetNorm = normalizeSpellName(spellName)

    if sbMap.exact[targetLower] then return sbMap.exact[targetLower] end
    if sbMap.exact[targetCleanLower] then return sbMap.exact[targetCleanLower] end
    if targetNorm ~= "" and sbMap.norm[targetNorm] then return sbMap.norm[targetNorm] end

    local slot = runtime.checkBook(spellName)
    if slot then return slot end

    if cleaned ~= spellName then
        slot = runtime.checkBook(cleaned)
        if slot then return slot end
    end

    pcall(function()
        local rName = mq.TLO.Spell(spellName).RankName()
        if rName and rName ~= '' and rName ~= spellName then
            slot = runtime.checkBook(rName)
        end
    end)
    if slot then return slot end

    pcall(function()
        local rName = mq.TLO.Spell(cleaned).RankName()
        if rName and rName ~= '' and rName ~= cleaned and rName ~= spellName then
            slot = runtime.checkBook(rName)
        end
    end)
    if slot then return slot end

    return nil
end

function runtime.unmemGem(slot)
    slot = tonumber(slot) or 1
    local currentInGem = nil
    pcall(function() currentInGem = mq.TLO.Me.Gem(slot).Name() end)
    if not currentInGem or currentInGem == '' or currentInGem == 'NULL' then return true end

    mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', slot - 1)
    mq.delay(200)
    local clearWait = 0
    while clearWait < 1000 do
        local inGem = nil
        pcall(function() inGem = mq.TLO.Me.Gem(slot).Name() end)
        if not inGem or inGem == '' or inGem == 'NULL' then return true end
        mq.delay(100)
        clearWait = clearWait + 100
        if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then return false end
    end
    local stillInGem = nil
    pcall(function() stillInGem = mq.TLO.Me.Gem(slot).Name() end)
    return not stillInGem or stillInGem == '' or stillInGem == 'NULL'
end

function runtime.tryMem(slot, spellName, bypassCheck)
    if not slot or slot < 1 or not spellName or spellName == '' then return false end
    local cleanName = cleanSpellName(spellName)

    clearCursor()

    if mq.TLO.Me.Combat() or (runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat()) then
        print(string.format('\ay[Triune]\ax Cannot memorize in combat: %s', cleanName))
        return false
    end

    if isGemMatching(slot, cleanName) or isGemMatching(slot, spellName) then
        return true
    end

    -- 1. Unmemorize duplicate instances of this spell in other gem slots first
    for s = 1, NUM_GEMS do
        if s ~= slot and (isGemMatching(s, cleanName) or isGemMatching(s, spellName)) then
            runtime.unmemGem(s)
            break
        end
    end

    -- 2. Unmemorize target slot if occupied
    local currentInGem = nil
    pcall(function() currentInGem = mq.TLO.Me.Gem(slot).Name() end)
    if currentInGem and currentInGem ~= '' and currentInGem ~= 'NULL' then
        runtime.unmemGem(slot)
    end

    -- 3. Verify scribed in spellbook and locate book slot
    local bookSlot = runtime.getSpellBookSlot(spellName)
    if not bookSlot and not bypassCheck then
        print(string.format('\ay[Triune]\ax "%s" is not scribed in your spellbook -- scribe it first.', cleanName))
        return false
    end
    bookSlot = bookSlot or 1

    -- 4. Stand up if sitting or ducking
    local isDucked = false
    pcall(function() isDucked = mq.TLO.Me.Ducking() end)
    if mq.TLO.Me.Sitting() or isDucked then
        mq.cmd('/stand')
        mq.delay(400)
    end

    if mq.TLO.Me.Moving() then
        print(string.format('\ay[Triune]\ax Stand still to memorize %s.', cleanName))
        return false
    end

    -- 5. Open SpellBookWnd
    local SBW = function() return mq.TLO.Window('SpellBookWnd') end

    if not SBW().Open() then mq.cmd('/book') end
    local t = 0
    while not SBW().Open() and t < 2500 do
        mq.delay(100)
        t = t + 100
        if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then
            if SBW().Open() then mq.cmd('/book 0') end
            return false
        end
    end
    if not SBW().Open() then
        print('\ar[Triune]\ax Could not open the spellbook.')
        return false
    end

    -- 6. Detect spells per page in SpellBookWnd
    local per = 0
    for i = 0, 24 do
        local nm
        pcall(function() nm = SBW().Child('SBW_Spell' .. i).Name() end)
        if nm then per = per + 1 else break end
    end
    if per == 0 then per = 8 end

    -- 7. Determine current page by reading displayed spell slots
    local curPage, inferred = 1, false
    for i = 0, per - 1 do
        local txt
        pcall(function() txt = SBW().Child('SBW_Spell' .. i).Text() end)
        if txt and txt ~= '' then
            txt = txt:match('^%s*(.-)%s*$')
            local bs = runtime.getSpellBookSlot(txt)
            if bs then
                curPage = math.ceil(bs / per)
                inferred = true
                break
            end
        end
    end

    if not inferred then
        for _ = 1, 40 do
            mq.cmd('/notify SpellBookWnd SBW_PageDown_Button leftmouseup')
            mq.delay(70)
            if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then
                if SBW().Open() then mq.cmd('/book 0') end
                return false
            end
        end
        curPage = 1
    end

    -- 8. Turn pages to reach target page
    local targetPage = math.ceil(bookSlot / per)
    if curPage ~= targetPage then
        local diff = targetPage - curPage
        local btn = (diff > 0) and 'SBW_PageUp_Button' or 'SBW_PageDown_Button'
        for _ = 1, math.abs(diff) do
            mq.cmdf('/notify SpellBookWnd %s leftmouseup', btn)
            mq.delay(math.random(150, 300))
            if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then
                if SBW().Open() then mq.cmd('/book 0') end
                return false
            end
        end
    end

    -- 9. Pick up spell from book page and drop onto gem slot
    mq.cmdf('/notify SpellBookWnd SBW_Spell%d leftmouseup', (bookSlot - 1) % per)
    mq.delay(math.random(300, 500))
    mq.cmdf('/notify CastSpellWnd CSPW_Spell%d leftmouseup', slot - 1)

    -- 10. Wait for CastingWindow (the memorization bar) to start and finish
    local w = 0
    while not mq.TLO.Window('CastingWindow').Open() and w < 3000 do
        mq.delay(100)
        w = w + 100
        if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then
            if SBW().Open() then mq.cmd('/book 0') end
            clearCursor()
            return false
        end
    end
    while mq.TLO.Window('CastingWindow').Open() do
        mq.delay(100)
        if runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat() then
            if SBW().Open() then mq.cmd('/book 0') end
            clearCursor()
            return false
        end
    end
    mq.delay(400)

    -- 11. Close spellbook
    if SBW().Open() then
        mq.cmd('/notify SpellBookWnd SBW_DoneButton leftmouseup')
    end

    clearCursor()

    -- 12. Verification
    if isGemMatching(slot, cleanName) or isGemMatching(slot, spellName) then
        print(string.format('\ag[Triune]\ax Memorized "%s" -> gem %d', cleanName, slot))
        return true
    elseif (mq.TLO.Me.Gem(cleanName)() or 0) > 0 or (mq.TLO.Me.Gem(spellName)() or 0) > 0 then
        print(string.format('\ag[Triune]\ax "%s" is on the bar.', cleanName))
        return true
    else
        print(string.format('\ar[Triune]\ax Mem may have failed for "%s" (gem %d).', cleanName, slot))
        return false
    end
end

DATA.ALIAS_CLASS_MAP = {
    SK = 'SK',
    SHD = 'SK',
    BST = 'Bst',
    Bst = 'Bst',
    SHM = 'Shm',
    Shm = 'Shm',
}

local function lookupSpells(abbr)
    local ALIAS_CLASS_MAP = DATA.ALIAS_CLASS_MAP
    if not abbr or not DATA.spells then return {} end
    if DATA.spells[abbr] then return DATA.spells[abbr] end

    local u = abbr:upper()
    if DATA.spells[u] then return DATA.spells[u] end

    local titleCase = u:sub(1, 1) .. u:sub(2):lower()
    if DATA.spells[titleCase] then return DATA.spells[titleCase] end

    local alt = ALIAS_CLASS_MAP[u] or ALIAS_CLASS_MAP[abbr]
    if alt and DATA.spells[alt] then return DATA.spells[alt] end
    if alt then
        local altTitle = alt:sub(1, 1):upper() .. alt:sub(2):lower()
        if DATA.spells[altTitle] then return DATA.spells[altTitle] end
    end

    for k, v in pairs(DATA.spells) do
        if type(k) == 'string' and k:upper() == u then
            return v
        end
    end
    return {}
end

local function clearFilteredSpellsCache()
    runtime.filteredSpellsCache = {}
end

local function isDisciplineSpell(abbr, spellName)
    if not abbr or not spellName or spellName == "" then return false end
    if runtime.PURE_MELEE[abbr] or runtime.PURE_MELEE[abbr:upper()] then return true end

    if DATA and DATA.discs then
        local alt = (DATA.ALIAS_CLASS_MAP and DATA.ALIAS_CLASS_MAP[abbr:upper()]) or abbr
        local discList = DATA.discs[abbr] or DATA.discs[abbr:upper()] or DATA.discs[alt]
        if discList then
            for _, row in ipairs(discList) do
                if row[1] == spellName or row[1]:lower() == spellName:lower() then
                    return true
                end
            end
        end
    end

    local isSkill = false
    pcall(function()
        local spObj = mq.TLO.Spell(spellName)
        if spObj() and spObj.IsSkill() then
            isSkill = true
        end
    end)
    if isSkill then return true end

    return isDiscKnown(spellName)
end

local function checkHasSPA(tloSpell, name, sp, spaId)
    local hasIt = false
    pcall(function()
        if tloSpell then
            local res = tloSpell.HasSPA(spaId)
            if res == true or res == 1 then hasIt = true end
            if not hasIt and (type(res) == 'function' or type(res) == 'userdata') then
                local ok, r2 = pcall(res) ---@diagnostic disable-line: param-type-mismatch
                if ok and (r2 == true or r2 == 1) then hasIt = true end
            end
        end
    end)
    if not hasIt and sp and sp.ID and sp.ID() > 0 then
        pcall(function()
            local res = mq.TLO.Spell(sp.ID()).HasSPA(spaId)
            if res == true or res == 1 then hasIt = true end
            if not hasIt and (type(res) == 'function' or type(res) == 'userdata') then
                local ok, r2 = pcall(res) ---@diagnostic disable-line: param-type-mismatch
                if ok and (r2 == true or r2 == 1) then hasIt = true end
            end
        end)
    end
    if not hasIt and name and name ~= "" then
        pcall(function()
            local res = mq.TLO.Spell(name).HasSPA(spaId)
            if res == true or res == 1 then hasIt = true end
            if not hasIt and (type(res) == 'function' or type(res) == 'userdata') then
                local ok, r2 = pcall(res) ---@diagnostic disable-line: param-type-mismatch
                if ok and (r2 == true or r2 == 1) then hasIt = true end
            end
        end)
    end
    return hasIt
end

local function mapTLOCategoryToKind(sp, name)
    if not sp and not name then return 'other' end

    -- Extract Spell TLO via ID first (most reliable in MQ)
    local tloSpell = nil
    pcall(function()
        if sp and sp.ID and sp.ID() > 0 then
            tloSpell = mq.TLO.Spell(sp.ID())
        end
    end)
    if not tloSpell and name and name ~= "" then
        pcall(function()
            tloSpell = mq.TLO.Spell(name)
        end)
    end
    if not tloSpell and name and name ~= "" then
        pcall(function()
            local cl = cleanSpellName(name)
            if cl ~= name then tloSpell = mq.TLO.Spell(cl) end
        end)
    end
    if not tloSpell and type(sp) == 'userdata' then
        tloSpell = sp
    end

    -- 1. Extract Category and Subcategory strings safely
    local catStr = ""
    local subcatStr = ""

    pcall(function()
        if tloSpell then
            local c = tloSpell.Category
            if c then catStr = tostring(c() or c.Name() or c):lower() end
            local sc = tloSpell.Subcategory
            if sc then subcatStr = tostring(sc() or sc.Name() or sc):lower() end
        end
    end)

    if (catStr == "" or catStr == "nil") and sp then
        pcall(function()
            local c = sp.Category
            if c then catStr = tostring(c() or c.Name() or c):lower() end
            local sc = sp.Subcategory
            if sc then subcatStr = tostring(sc() or sc.Name() or sc):lower() end
        end)
    end

    local nmLower = name and name:lower() or ""

    -- Extract Beneficial status and Duration early
    local bene = true
    pcall(function()
        if tloSpell then
            local b = tloSpell.Beneficial
            if type(b) == 'function' or type(b) == 'userdata' then bene = b() or false else bene = b or false end
        elseif sp then
            local b = sp.Beneficial
            if type(b) == 'function' or type(b) == 'userdata' then bene = b() or false else bene = b or false end
        end
    end)

    local dur = 0
    pcall(function()
        if tloSpell and tloSpell.Duration then
            dur = tonumber(tloSpell.Duration() or 0) or 0
        elseif sp and sp.Duration then
            dur = tonumber(sp.Duration() or 0) or 0
        end
    end)
    dur = tonumber(dur) or 0

    -- Timed beneficial buffs on pets (Burnout, Pet Haste, Pet Power, Companion's Aegis, etc.)
    if bene and dur > 0 then
        if subcatStr:find('pet') or catStr:find('pet') or subcatStr:find('burnout') or nmLower:find('burnout') then
            return 'pet_buff'
        end
        if catStr:find('buff') or catStr:find('stat') or catStr:find('resist') or catStr:find('shield')
            or subcatStr:find('buff') or catStr:find('aura') or subcatStr:find('aura') or subcatStr:find('shield')
            or subcatStr:find('haste') or catStr:find('haste')
            or nmLower:find('shield') or nmLower:find('celerity') or nmLower:find('alacrity') or nmLower:find('haste')
            or nmLower:find('swift') or nmLower:find('elemental') or nmLower:find('companion') or nmLower:find('minion') or nmLower:find('servant') then
            return 'buff'
        end
    end

    -- True pet summoning spells: check SPA 103 or instant duration pet summon categories/names
    if checkHasSPA(tloSpell, name, sp, 103) then return 'pet' end

    if dur == 0 and (subcatStr:find('pet') or (catStr:find('pet') and not catStr:find('utility'))
        or nmLower:find('summoning') or nmLower:find('animate dead') or nmLower:find('cavorting bones')
        or nmLower:find('bone walk') or nmLower:find('leering corpse') or nmLower:find('convoke shadow')
        or nmLower:find('servant of bones') or nmLower:find('minion of') or nmLower:find('companion of spirit')
        or nmLower:find("nature's companion") or nmLower:find('animation') or nmLower:find('spirit of sharik')
        or nmLower:find('spirit of khaliz') or nmLower:find('warder')) then
        return 'pet'
    end

    -- Debuff Check for resist debuffs (Mala, Malo, Malosi, Tash, etc.)
    if not bene then
        if catStr:find('debuff') or subcatStr:find('debuff') or catStr:find('slow') or subcatStr:find('slow')
            or catStr:find('dispel') or subcatStr:find('dispel') or catStr:find('blind') or subcatStr:find('blind')
            or nmLower:find('mala') or nmLower:find('malo') or nmLower:find('tash') or nmLower:find('incapacitate') or nmLower:find('listless') or nmLower:find('disempower') then
            return 'debuff'
        end
    end

    -- Utility Check (Gate, Bind Affinity, Invisibility, Camouflage, Teleports, Illusions, Item Summons)
    if nmLower:find('gate') or nmLower:find('bind affinity') or nmLower:find('invisib') or nmLower:find('camouflage') or nmLower:find('translocate')
        or catStr:find('transport') or catStr:find('travel') or catStr:find('teleport') or catStr:find('gate') or catStr:find('illusion') or catStr:find('invis')
        or subcatStr:find('transport') or subcatStr:find('travel') or subcatStr:find('teleport') or subcatStr:find('gate') or subcatStr:find('illusion') or subcatStr:find('invis')
        or (catStr:find('utility') and not catStr:find('debuff')) or (subcatStr:find('utility') and not subcatStr:find('debuff')) then
        return 'util'
    end

    -- 2. SPA-based checks (most authoritative for non-beneficial SPA mechanics)
    if checkHasSPA(tloSpell, name, sp, 32) or checkHasSPA(tloSpell, name, sp, 108) or checkHasSPA(tloSpell, name, sp, 33) then
        return 'util'
    end
    if checkHasSPA(tloSpell, name, sp, 83) or checkHasSPA(tloSpell, name, sp, 88) or checkHasSPA(tloSpell, name, sp, 12) or checkHasSPA(tloSpell, name, sp, 41) or checkHasSPA(tloSpell, name, sp, 29) or checkHasSPA(tloSpell, name, sp, 30) then
        return 'util'
    end
    if checkHasSPA(tloSpell, name, sp, 81) or checkHasSPA(tloSpell, name, sp, 91) then return 'util' end
    if checkHasSPA(tloSpell, name, sp, 18) or checkHasSPA(tloSpell, name, sp, 22) or checkHasSPA(tloSpell, name, sp, 31) then
        return 'util'
    end
    if not bene then
        if checkHasSPA(tloSpell, name, sp, 11) or checkHasSPA(tloSpell, name, sp, 46) or checkHasSPA(tloSpell, name, sp, 23)
            or checkHasSPA(tloSpell, name, sp, 4) or checkHasSPA(tloSpell, name, sp, 5) or checkHasSPA(tloSpell, name, sp, 6) or checkHasSPA(tloSpell, name, sp, 7) then
            return 'debuff'
        end
    end

    -- 3. Match remaining category strings
    if bene and (catStr:find('heal') or subcatStr:find('heal') or catStr:find('restore') or subcatStr:find('restore')) then
        return 'heal'
    elseif catStr:find('dot') or catStr:find('damage over time') or subcatStr:find('dot') or subcatStr:find('damage over time') then
        return 'dot'
    elseif catStr:find('direct damage') or catStr:find('nuke') or catStr:find('dd') or subcatStr:find('direct damage') or subcatStr:find('nuke') or catStr:find('lifetap') or subcatStr:find('lifetap') or nmLower:find('lifetap') or nmLower:find('lifedraw') or nmLower:find('lifespike') or nmLower:find('siphon life') or nmLower:find('drain') then
        return 'dd'
    elseif catStr:find('debuff') or subcatStr:find('debuff') or catStr:find('slow') or subcatStr:find('slow') or catStr:find('dispel') or subcatStr:find('dispel') or catStr:find('blind') or subcatStr:find('blind') or nmLower:find('incapacitate') or nmLower:find('listless') or nmLower:find('disempower') then
        return 'debuff'
    elseif bene or catStr:find('buff') or catStr:find('stat') or catStr:find('resist') or catStr:find('shield') or subcatStr:find('buff') or catStr:find('aura') or subcatStr:find('aura') or subcatStr:find('shield') or nmLower:find('spirit of wolf') or nmLower:find('sow') then
        return 'buff'
    elseif catStr:find('transport') or catStr:find('travel') or catStr:find('utility') or catStr:find('misc') or catStr:find('teleport') or catStr:find('gate') or catStr:find('illusion') or catStr:find('summon') or subcatStr:find('summon') then
        return 'util'
    end

    if bene then
        return 'buff'
    else
        return 'dd'
    end
end

local function filteredSpells(abbr)
    if not abbr then
        return {}, {}
    end
    local KIND_LABEL = { dd = 'DD', dot = 'DoT', heal = 'Heal', buff = 'Buff', pet_buff = 'PetBuff', pet = 'Pet', util = 'Util', debuff = 'Debuff' }
    local now = os.clock()
    local scribedOnly = ctrl and ctrl.scribed_only or false

    runtime.filteredSpellsCache = runtime.filteredSpellsCache or {}
    local cached = runtime.filteredSpellsCache[abbr]
    if cached and (now - cached.time) < 2.0
        and cached.lvlMin == lvlMin
        and cached.lvlMax == lvlMax
        and cached.scribedOnly == scribedOnly then
        return cached.names, cached.lookup
    end

    local names, lookup = {}, {}
    local src = lookupSpells(abbr)
    for _, row in ipairs(src) do
        local nm, lv, bene, dbKind = row[1], row[2], row[3], row[4]
        if not isDisciplineSpell(abbr, nm) then
            if lv >= lvlMin and lv <= lvlMax and (not scribedOnly or isScribed(nm)) then
                local kind = mapTLOCategoryToKind(nil, nm)
                if not kind or kind == 'other' then kind = dbKind or 'other' end
                local label       = KIND_LABEL[kind]
                names[#names + 1] = label and string.format('%s  (L%d) [%s]', nm, lv, label)
                    or string.format('%s  (L%d)', nm, lv)
                lookup[#names]    = { name = nm, level = lv, bene = (bene == 1), kind = kind }
            end
        end
    end

    runtime.filteredSpellsCache[abbr] = {
        names = names,
        lookup = lookup,
        time = now,
        lvlMin = lvlMin,
        lvlMax = lvlMax,
        scribedOnly = scribedOnly
    }
    return names, lookup
end

local function classHasSpells(abbr)
    if not abbr or runtime.PURE_MELEE[abbr] or runtime.PURE_MELEE[abbr:upper()] then
        return false
    end
    local names, _ = filteredSpells(abbr)
    return names ~= nil and #names > 0
end

-- Checked live every time the spell picker renders (not cached), so the list
-- naturally updates the moment you scribe something new -- no separate
-- refresh mechanism needed.
-- isScribed is defined in local helpers above

-- kind tag (4th field the extractor writes: dd/dot/heal/buff, classified from
-- goodEffect + whether the spell has a duration -- verified against known
-- spells: Flame Bolt=dd, Immolate/Heat Blood=dot, Minor Healing=heal, Spirit
-- of Wolf=buff). Shown in the picker so a low-level player isn't left
-- guessing what an unfamiliar spell name actually does.

-- Base Actions & Combat Skills (not spells/discs/AAs -- fired via /doability).
-- Keyed by class. Rendered on the dedicated Abilities tab and executed via
-- runtime.fireSkill() either as continuous Autoskills or priority-ordered conditions.
local CLASS_ACTIONS = {
    Mnk = { 'Kick', 'Round Kick', 'Tiger Claw', 'Eagle Strike', 'Dragon Punch', 'Tail Rake', 'Flying Kick', 'Mend', 'Feign Death', 'Sneak', 'Intimidation', 'Disarm' },
    Rog = { 'Backstab', 'Hide', 'Sneak', 'Pick Pockets', 'Sense Traps', 'Disarm Traps', 'Disarm', 'Intimidation' },
    War = { 'Kick', 'Bash', 'Taunt', 'Disarm', 'Intimidation' },
    Pal = { 'Bash', 'Taunt', 'Disarm' },
    SK  = { 'Bash', 'Taunt', 'Disarm' },
    Rng = { 'Kick', 'Taunt', 'Disarm', 'Hide', 'Sneak', 'Forage', 'Track' },
    Ber = { 'Frenzy', 'Kick', 'Disarm', 'Intimidation', 'Volley' },
    Bst = { 'Kick', 'Disarm' },
    Brd = { 'Disarm', 'Hide', 'Sneak', 'Pick Pockets', 'Track' },
    Clr = { 'Bash' },
    Dru = { 'Forage', 'Track' },
    Shm = {},
    Nec = {},
    Wiz = {},
    Mag = {},
    Enc = {},
    racial = { 'Slam', 'Hide', 'Sneak', 'Forage' },
    universal = { 'Begging', 'Bind Wound', 'Sense Heading' },
}

local function isActionSkill(name)
    if not name or type(name) ~= 'string' or name == '' then return false end
    for _, list in pairs(CLASS_ACTIONS) do
        for _, n in ipairs(list) do if n == name then return true end end
    end
    return false
end

local function isSpecialSkill(name)
    if not name or type(name) ~= 'string' or name == '' then return false end
    for _, list in pairs(CLASS_ACTIONS) do
        for _, n in ipairs(list) do if n == name then return true end end
    end
    return false
end

local function isNonCombatSkill(name)
    if not name or type(name) ~= 'string' or name == '' then return false end
    return name == 'Begging' or name == 'Pick Pockets' or name == 'Hide' or name == 'Sneak' or name == 'Bind Wound' or name == 'Forage' or name == 'Sense Heading'
end

local AUTOSKILL_ABILITIES = {
    ['Kick']           = true,
    ['Flying Kick']    = true,
    ['Dragon Punch']   = true,
    ['Tail Rake']      = true,
    ['Eagle Strike']   = true,
    ['Tiger Claw']     = true,
    ['Round Kick']     = true,
    ['Backstab']       = true,
    ['Bash']           = true,
    ['Slam']           = true,
    ['Frenzy']         = true,
    ['Volley']         = true,
    ['Frenzied Stabs'] = true,
}

local function isAutoskillEligible(name)
    if not name or type(name) ~= 'string' or name == '' then return false end
    return AUTOSKILL_ABILITIES[name] == true
end

local function isFeignDeathAbility(name)
    if not name or type(name) ~= 'string' or name == '' then return false end
    local lower = name:lower()
    return lower == 'feign death'
        or lower == 'death peace'
        or lower == 'imitate death'
        or lower:find('feign death', 1, true) ~= nil
        or lower:find('death peace', 1, true) ~= nil
        or lower:find('imitate death', 1, true) ~= nil
        or lower:find("death's effigy", 1, true) ~= nil
end

local ABILITY_BASE_COOLDOWNS = {
    ['Kick']          = 6,
    ['Bash']          = 6,
    ['Slam']          = 6,
    ['Round Kick']    = 6,
    ['Tiger Claw']    = 6,
    ['Eagle Strike']  = 6,
    ['Dragon Punch']  = 6,
    ['Tail Rake']     = 6,
    ['Flying Kick']   = 6,
    ['Backstab']      = 10,
    ['Taunt']         = 6,
    ['Disarm']        = 10,
    ['Mend']          = 360,
    ['Feign Death']   = 8,
    ['Sneak']         = 6,
    ['Hide']          = 6,
    ['Sense Heading'] = 6,
    ['Forage']        = 10,
    ['Frenzy']        = 10,
    ['Intimidation']  = 10,
    ['Begging']       = 10,
    ['Pick Pockets']  = 10,
    ['Bind Wound']    = 10,
    ['Tracking']      = 10,
    ['Track']         = 10,
    ['Safe Fall']     = 6,
    ['Throw Stone']   = 6,
}

local function getAbilityBaseCooldown(name)
    if not name or name == '' then return 6 end
    if ABILITY_BASE_COOLDOWNS[name] then return ABILITY_BASE_COOLDOWNS[name] end
    local tot = 0
    pcall(function()
        local t = mq.TLO.Me.AbilityTimerTotal(name)
        if not t or not t() then
            local idx = mq.TLO.Me.Ability(name)()
            if idx and idx > 0 then t = mq.TLO.Me.AbilityTimerTotal(idx) end
        end
        if t and t() then
            if type(t.TotalSeconds) == 'function' then
                tot = tonumber(t.TotalSeconds() or 0) or 0
            elseif type(t.TotalSeconds) == 'number' then
                tot = tonumber(t.TotalSeconds() or 0) or 0
            elseif t.Raw and type(t.Raw) == 'function' then
                tot = (tonumber(t.Raw() or 0) or 0) / 1000.0
            elseif tonumber(t()) then
                local n = tonumber(t()) or 0
                tot = n > 1000 and (n / 1000.0) or n
            end
        end
    end)
    if tot > 0 then return tot end
    return 6
end

local function parseDurationSec(durObj)
    if not durObj then return 0 end
    local sec = 0
    pcall(function()
        if type(durObj) == 'number' then
            if durObj >= 2147483647 or durObj < 0 then
                sec = 0
            elseif durObj > 10000 then
                sec = durObj / 1000.0
            else
                sec = durObj
            end
            if sec >= 2000000 or sec < 0 then sec = 0 end
            return
        end

        if type(durObj) == 'table' then
            if durObj.TotalSeconds then
                sec = tonumber(durObj.TotalSeconds) or 0
                if sec >= 2000000 or sec < 0 then sec = 0 end
                if sec > 0 then return end
            end
            if durObj.Raw then
                local r = tonumber(durObj.Raw) or 0
                if r < 2147483647 and r > 0 then
                    sec = r / 1000.0
                    if sec > 0 then return end
                end
            end
            if durObj.Ticks then
                local tk = tonumber(durObj.Ticks) or 0
                if tk > 0 and tk < 350000 then
                    sec = tk * 6
                    if sec > 0 then return end
                end
            end
        end

        if type(durObj.TotalSeconds) == 'function' then
            local ts = tonumber(durObj.TotalSeconds() or 0) or 0
            if ts >= 2000000 or ts < 0 then ts = 0 end
            if ts > 0 then sec = ts; return end
        elseif type(durObj.TotalSeconds) == 'number' then
            local ts = tonumber(durObj.TotalSeconds or 0) or 0
            if ts >= 2000000 or ts < 0 then ts = 0 end
            if ts > 0 then sec = ts; return end
        end

        if durObj.Raw and type(durObj.Raw) == 'function' then
            local raw = tonumber(durObj.Raw() or 0) or 0
            if raw > 0 and raw < 2147483647 then
                sec = raw / 1000.0
                if sec > 0 then return end
            end
        end

        if durObj.Ticks and type(durObj.Ticks) == 'function' then
            local t = tonumber(durObj.Ticks() or 0) or 0
            if t > 0 and t < 350000 then
                sec = t * 6
                if sec > 0 then return end
            end
        end

        if type(durObj) == 'function' or durObj() ~= nil then
            local v = tonumber(durObj()) or 0
            if v >= 2147483647 or v < 0 then
                sec = 0
            elseif v > 1000 then
                sec = v / 1000.0
            elseif v > 0 and v <= 500 then
                sec = v * 6
            else
                sec = v
            end
            if sec >= 2000000 or sec < 0 then sec = 0 end
        end
    end)
    if sec >= 2000000 or sec < 0 then sec = 0 end
    return sec
end

local function parseCombatAbilityTimer(cat)
    if not cat then return 0 end
    local sec = 0
    pcall(function()
        if type(cat) == 'number' then
            if cat > 1000 then sec = cat / 1000.0
            elseif cat > 0 and cat <= 500 then sec = cat * 6
            else sec = cat end
            return
        end
        if type(cat) == 'table' then
            if cat.TotalSeconds then sec = tonumber(cat.TotalSeconds) or 0; return end
            if cat.Ticks then sec = (tonumber(cat.Ticks) or 0) * 6; return end
            if cat.Raw then sec = (tonumber(cat.Raw) or 0) / 1000.0; return end
        end
        if type(cat.TotalSeconds) == 'function' then
            local ts = tonumber(cat.TotalSeconds() or 0) or 0
            if ts > 0 then sec = ts; return end
        elseif type(cat.TotalSeconds) == 'number' then
            local ts = tonumber(cat.TotalSeconds or 0) or 0
            if ts > 0 then sec = ts; return end
        end
        if type(cat.Ticks) == 'function' then
            local t = tonumber(cat.Ticks() or 0) or 0
            if t > 0 then sec = t * 6; return end
        end
        if cat.Raw and type(cat.Raw) == 'function' then
            local raw = tonumber(cat.Raw() or 0) or 0
            if raw > 0 then sec = raw / 1000.0; return end
        end
        if type(cat) == 'function' or cat() ~= nil then
            local n = tonumber(cat()) or 0
            if n > 1000 then sec = n / 1000.0
            elseif n > 0 and n <= 500 then sec = n * 6
            else sec = n end
        end
    end)
    return sec
end

local function parseSpellRecastTime(sp)
    if not sp then return 0 end
    local sec = 0
    pcall(function()
        if type(sp.RecastTime) == 'userdata' or type(sp.RecastTime) == 'table' then
            if type(sp.RecastTime.TotalSeconds) == 'function' then
                local ts = tonumber(sp.RecastTime.TotalSeconds() or 0) or 0
                if ts > 0 then sec = ts; return end
            elseif type(sp.RecastTime.TotalSeconds) == 'number' then
                local ts = tonumber(sp.RecastTime.TotalSeconds or 0) or 0
                if ts > 0 then sec = ts; return end
            end
            if sp.RecastTime.Raw and type(sp.RecastTime.Raw) == 'function' then
                local raw = tonumber(sp.RecastTime.Raw() or 0) or 0
                if raw > 0 then sec = raw / 1000.0; return end
            end
        end

        local rt = sp.RecastTime and sp.RecastTime()
        if type(rt) == 'number' or tonumber(rt) then
            local numRt = tonumber(rt) or 0
            if numRt > 86400 then
                sec = numRt / 1000.0
            elseif numRt >= 10000 and numRt % 500 == 0 then
                sec = numRt / 1000.0
            elseif numRt > 0 then
                sec = numRt
            end
        end
    end)
    return sec
end

local DISC_BASE_COOLDOWNS = {
    ['Defensive Discipline']       = 900,
    ['Evasive Discipline']         = 900,
    ['Stonewall Discipline']       = 900,
    ['Furious Discipline']         = 3600,
    ['Fortitude Discipline']       = 3600,
    ['Mighty Strike Discipline']   = 3600,
    ['Charge Discipline']          = 900,
    ['Resistant Discipline']       = 600,
    ['Fearless Discipline']        = 600,
    ['Precision Discipline']       = 300,
    ['Aggressive Discipline']      = 300,
    ['Frenzied Defense Discipline']= 900,
    ['Fellstrike Discipline']      = 900,
    ['Bellow of the Mastruq']      = 30,
    ['Incite']                     = 30,
    ['Berate']                     = 30,
    ['Provoke']                    = 30,
    ['Bellow']                     = 30,
    ['Ancient: Chaos Cry']         = 30,
    ['Aura of Runes']              = 30,
    ['Infused by Rage']            = 30,
    ['Nimble Discipline']          = 900,
    ['Deftdance Discipline']       = 900,
    ['Kinesthetics Discipline']    = 1800,
    ['Duelist Discipline']         = 900,
    ['Blinding Speed Discipline']  = 900,
    ['Twisted Shank']              = 30,
    ['Kyv Tear']                   = 30,
    ['Kyv Strike']                 = 30,
    ['Stonestance Discipline']     = 720,
    ['Hundred Fists Discipline']   = 1800,
    ['Inner Flame Discipline']     = 1800,
    ['Whirlwind Discipline']       = 1800,
    ['Voiddance Discipline']       = 900,
    ['Ashenhand Discipline']       = 1800,
    ['Thunderkick Discipline']     = 900,
    ['Silentfist Discipline']      = 1800,
    ["Dreamstrider's Discipline"]  = 1800,
    ['Holyforge Discipline']       = 1800,
    ['Sanctification Discipline']  = 1800,
    ['Unholy Aura Discipline']     = 1800,
    ['Leechcurse Discipline']      = 1800,
    ['Bloodthirst Discipline']     = 900,
    ['Trueshot Discipline']        = 1800,
    ['Weapon Shield Discipline']   = 1800,
    ['Fistshot Discipline']        = 900,
    ["Warder's Protection"]        = 900,
    ['Puretone Discipline']        = 1800,
    ['Blind Rage Discipline']      = 900,
    ['Cleaving Anger Discipline']  = 900,
    ['Blood Pact Discipline']      = 900,
    ['Reckless Abandon Discipline']= 900,
    ['Savage Spirit Discipline']   = 900,
    ['Cry Havoc']                  = 30,
    ['Axe of the Destroyer']       = 30,
    ['Vicious Spiral']             = 30,
    ['Confusing Strike']           = 30,
}

local DISC_BASE_DURATIONS = {
    ['Defensive Discipline']       = 18,
    ['Evasive Discipline']         = 18,
    ['Stonewall Discipline']       = 18,
    ['Furious Discipline']         = 12,
    ['Fortitude Discipline']       = 12,
    ['Mighty Strike Discipline']   = 12,
    ['Charge Discipline']          = 12,
    ['Resistant Discipline']       = 120,
    ['Fearless Discipline']        = 120,
    ['Precision Discipline']       = 18,
    ['Aggressive Discipline']      = 18,
    ['Frenzied Defense Discipline']= 18,
    ['Fellstrike Discipline']      = 18,
    ['Nimble Discipline']          = 12,
    ['Deftdance Discipline']       = 12,
    ['Kinesthetics Discipline']    = 18,
    ['Duelist Discipline']         = 14,
    ['Stonestance Discipline']     = 12,
    ['Hundred Fists Discipline']   = 14,
    ['Inner Flame Discipline']     = 14,
    ['Whirlwind Discipline']       = 12,
    ['Voiddance Discipline']       = 8,
    ['Ashenhand Discipline']       = 12,
    ['Thunderkick Discipline']     = 12,
    ['Holyforge Discipline']       = 300,
    ['Sanctification Discipline']  = 18,
    ['Unholy Aura Discipline']     = 300,
    ['Leechcurse Discipline']      = 18,
    ['Bloodthirst Discipline']     = 18,
    ['Trueshot Discipline']        = 120,
    ['Weapon Shield Discipline']   = 18,
    ['Puretone Discipline']        = 120,
    ['Blind Rage Discipline']      = 18,
    ['Cleaving Anger Discipline']  = 18,
    ['Blood Pact Discipline']      = 18,
    ['Reckless Abandon Discipline']= 18,
    ['Savage Spirit Discipline']   = 18,
}

local function getDiscCooldownAndDuration(name)
    local recastSec = 0
    local durSec = 0
    local timerGroupId = nil
    local endCost = 0
    local discIdx = 0

    if not name or name == '' then
        return { recastSec = 0, durSec = 0, timerGroupId = nil, endCost = 0, discIdx = 0 }
    end

    pcall(function()
        local ca = mq.TLO.Me.CombatAbility(name)
        if ca and ca() then
            discIdx = tonumber(ca() or 0) or 0
        end

        local sp = mq.TLO.Spell(name)
        if (not sp or not sp()) and discIdx > 0 then
            sp = mq.TLO.Me.CombatAbility(discIdx)
        end

        if sp and sp() then
            endCost = tonumber(sp.EnduranceCost and sp.EnduranceCost() or 0) or 0
            recastSec = parseSpellRecastTime(sp)

            if sp.Duration then
                durSec = parseDurationSec(sp.Duration)
            end
            if durSec <= 0 and sp.MyDuration then
                durSec = parseDurationSec(sp.MyDuration)
            end

            local tid = sp.TimerID and sp.TimerID()
            if tid and tonumber(tid) and tonumber(tid) > 0 then
                timerGroupId = 'T' .. tostring(tid)
            end
        end
    end)

    if recastSec <= 0 and DISC_BASE_COOLDOWNS[name] then
        recastSec = DISC_BASE_COOLDOWNS[name]
    end
    if durSec <= 0 and DISC_BASE_DURATIONS[name] then
        durSec = DISC_BASE_DURATIONS[name]
    end

    return {
        recastSec = recastSec,
        durSec = durSec,
        timerGroupId = timerGroupId,
        endCost = endCost,
        discIdx = discIdx,
    }
end

local function hasActionSkill(name)
    if not name or type(name) ~= 'string' or name == '' or name == 'NULL' or name == 'false' then return false end
    -- 1. Check if character has trained skill points (> 0) in this skill
    local ok, val = pcall(function()
        local s = mq.TLO.Me.Skill(name)
        if s and s() then return tonumber(s()) or 0 end
        if name == 'Track' then
            local st = mq.TLO.Me.Skill('Tracking')
            if st and st() then return tonumber(st()) or 0 end
        end
        return 0
    end)
    if ok and val and val > 0 then return true end

    -- 2. Check if the ability is mapped to an ability button (1..10)
    local aOk, aVal = pcall(function()
        local ab = mq.TLO.Me.Ability(name)
        if ab and ab() then return tonumber(ab()) or 0 end
        return 0
    end)
    if aOk and aVal and aVal > 0 then return true end

    -- 3. Check if the ability is ready to fire right now
    local rOk, rVal = pcall(function()
        return mq.TLO.Me.AbilityReady(name)()
    end)
    if rOk and rVal == true then return true end

    return false
end

local function actionClassInfo(name)
    if not name or type(name) ~= 'string' or name == '' then return (myClasses and myClasses[1]) or 'War' end
    for _, cls in ipairs(myClasses or {}) do
        local list = CLASS_ACTIONS[cls]
        if list then
            for _, actName in ipairs(list) do
                if actName == name then return cls end
            end
        end
    end
    for cls, list in pairs(CLASS_ACTIONS) do
        for _, actName in ipairs(list) do
            if actName == name then return cls end
        end
    end
    return (myClasses and myClasses[1]) or 'War'
end

-- Retrieves all combat abilities and skills for the character's Gestalt Trio classes
local function getClientAbilities()
    local clientList = {}
    local seen = {}

    -- 1. Populate abilities belonging strictly to the character's Gestalt Trio classes
    for _, cls in ipairs(myClasses or {}) do
        local list = CLASS_ACTIONS[cls]
        if list then
            for _, nm in ipairs(list) do
                if type(nm) == 'string' and nm ~= '' and not seen[nm] then
                    seen[nm] = true
                    local curVal = 0
                    local myCap = 0
                    pcall(function()
                        local s = mq.TLO.Me.Skill(nm)
                        if s and s() then curVal = tonumber(s()) or 0 end
                        if nm == 'Track' and curVal == 0 then
                            local st = mq.TLO.Me.Skill('Tracking')
                            if st and st() then curVal = tonumber(st()) or 0 end
                        end
                        local sc = mq.TLO.Me.SkillCap(nm)
                        if sc and sc() then myCap = tonumber(sc()) or 0 end
                    end)
                    local isTrained = (curVal > 0) or hasActionSkill(nm)
                    clientList[#clientList + 1] = {
                        name = nm,
                        cls = cls,
                        skillCap = myCap,
                        currentSkill = curVal,
                        isTrained = isTrained,
                    }
                end
            end
        end
    end

    -- 2. Race-specific or trained abilities (Slam on large races, Forage on Iksar/Wood Elf, Hide/Sneak)
    for _, nm in ipairs(CLASS_ACTIONS.racial) do
        if type(nm) == 'string' and nm ~= '' and not seen[nm] then
            local curVal = 0
            local myCap = 0
            pcall(function()
                local s = mq.TLO.Me.Skill(nm)
                if s and s() then curVal = tonumber(s()) or 0 end
                local sc = mq.TLO.Me.SkillCap(nm)
                if sc and sc() then myCap = tonumber(sc()) or 0 end
            end)
            local isTrained = (curVal > 0) or hasActionSkill(nm)
            if isTrained or myCap > 0 then
                seen[nm] = true
                clientList[#clientList + 1] = {
                    name = nm,
                    cls = (myClasses and myClasses[1]) or 'War',
                    skillCap = myCap,
                    currentSkill = curVal,
                    isTrained = isTrained,
                }
            end
        end
    end

    -- 3. Universal innate abilities (Begging, Bind Wound, Sense Heading)
    for _, nm in ipairs(CLASS_ACTIONS.universal) do
        if type(nm) == 'string' and nm ~= '' and not seen[nm] then
            local curVal = 0
            local myCap = 0
            pcall(function()
                local s = mq.TLO.Me.Skill(nm)
                if s and s() then curVal = tonumber(s()) or 0 end
                local sc = mq.TLO.Me.SkillCap(nm)
                if sc and sc() then myCap = tonumber(sc()) or 0 end
            end)
            local isTrained = (curVal > 0) or hasActionSkill(nm)
            if isTrained or not ctrl.action_trained_only then
                seen[nm] = true
                clientList[#clientList + 1] = {
                    name = nm,
                    cls = (myClasses and myClasses[1]) or 'War',
                    skillCap = myCap,
                    currentSkill = curVal,
                    isTrained = isTrained,
                }
            end
        end
    end

    -- 4. Active abilities on client hotbars/ActionsWnd (mq.TLO.Me.Ability 1..10)
    for i = 1, 10 do
        pcall(function()
            local ab = mq.TLO.Me.Ability(i)
            if ab then
                local rawVal = (type(ab) == 'function' and ab()) or (type(ab) == 'table' and type(ab.Name) == 'function' and ab.Name()) or ab
                if type(rawVal) == 'table' and type(rawVal.Name) == 'function' then rawVal = rawVal.Name() end
                local nm = (type(rawVal) == 'string' and rawVal) or nil
                if type(nm) == 'string' and nm ~= '' and nm ~= 'NULL' and nm ~= 'false' and not seen[nm] then
                    local curVal = 0
                    local s = mq.TLO.Me.Skill(nm)
                    if s and s() then curVal = tonumber(s()) or 0 end
                    seen[nm] = true
                    clientList[#clientList + 1] = {
                        name = nm,
                        cls = actionClassInfo(nm),
                        skillCap = 0,
                        currentSkill = curVal,
                        isTrained = true,
                    }
                end
            end
        end)
    end

    return clientList
end

local function defaultActionEntry(name, cls)
    if name == 'Mend' then
        return { cls = cls, target = 'F: Myself', when = 'my HP <=', enabled = false, pct = 75, autoskill = false, boss_only = false, burn_only = false, priority = 20, kind = 'heal' }
    elseif name == 'Feign Death' then
        return { cls = cls, target = 'F: Myself', when = 'my HP <=', enabled = false, pct = 25, autoskill = false, boss_only = false, burn_only = false, priority = 10, kind = 'heal' }
    elseif name == 'Hide' or name == 'Sneak' then
        return { cls = cls, target = 'F: Myself', when = 'always', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 70, kind = 'buff' }
    elseif name == 'Sense Traps' or name == 'Disarm Traps' or name == 'Forage' or name == 'Track' or name == 'Sense Heading' then
        return { cls = cls, target = 'F: Myself', when = 'always', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 80, kind = 'util' }
    elseif name == 'Bind Wound' then
        return { cls = cls, target = 'F: Myself', when = 'my HP <=', enabled = false, pct = 50, autoskill = false, boss_only = false, burn_only = false, priority = 60, kind = 'heal' }
    elseif name == 'Taunt' then
        return { cls = cls, target = 'E: Current Target', when = 'in combat', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 40, kind = 'dd' }
    elseif name == 'Disarm' then
        return { cls = cls, target = 'E: Current Target', when = 'in combat', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 60, kind = 'dd' }
    elseif name == 'Intimidation' then
        return { cls = cls, target = 'E: Current Target', when = 'in combat', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 65, kind = 'dd' }
    elseif name == 'Begging' or name == 'Pick Pockets' then
        return { cls = cls, target = 'E: Current Target', when = 'in combat', enabled = false, pct = 100, autoskill = false, boss_only = false, burn_only = false, priority = 80, kind = 'util' }
    else
        -- High-frequency combat melee attacks (Kick, Flying Kick, Dragon Punch, Tail Rake, Eagle Strike, Tiger Claw, Round Kick, Backstab, Bash, Slam, Frenzy, Volley)
        local auto = isAutoskillEligible(name)
        return { cls = cls, target = 'E: Current Target', when = 'in combat', enabled = false, pct = 100, autoskill = auto, boss_only = false, burn_only = false, priority = 50, kind = 'dd' }
    end
end

local function aaTier(sec)
    if sec <= 60 then return 'short' elseif sec <= 300 then return 'mid' else return 'burn' end
end
local function fmtSec(s)
    s = math.floor(tonumber(s) or 0)
    if s < 60 then return s .. 's' end
    if s < 3600 then
        local m = math.floor(s / 60); local r = s % 60
        return (r == 0) and (m .. 'm') or (m .. 'm ' .. r .. 's')
    end
    local h = math.floor(s / 3600); local m = math.floor((s % 3600) / 60)
    return (m == 0) and (h .. 'h') or (h .. 'h ' .. m .. 'm')
end

-- ============================================================================
-- Persistence
-- ============================================================================
local function serialize(o, f, indent)
    local t = type(o)
    if t == 'number' or t == 'boolean' then
        f:write(tostring(o))
    elseif t == 'string' then
        f:write(string.format('%q', o))
    elseif t == 'table' then
        f:write('{\n')
        for k, v in pairs(o) do
            f:write(string.rep('  ', indent))
            if type(k) == 'string' then
                f:write('[' .. string.format('%q', k) .. ']=')
            else
                f:write('[' .. tostring(k) .. ']=')
            end
            serialize(v, f, indent + 1); f:write(',\n')
        end
        f:write(string.rep('  ', indent - 1) .. '}')
    else
        f:write('nil')
    end
end

-- ============================================================================
-- Character storage and class detection
-- ============================================================================
local myName = nil
local ALLDATA = {} -- character name -> saved entry
-- detectClasses, classesFromInventoryWindow, and classesFromTitle are defined in local helpers above

-- Which of the character's classes owns a spell, whether it's beneficial, and
-- its kind tag (dd/dot/heal/buff) -- all three feed defaultsForKind.
local function spellClassInfo(name)
    for _, abbr in ipairs(myClasses) do
        if not runtime.PURE_MELEE[abbr] and not runtime.PURE_MELEE[abbr:upper()] then
            local list = lookupSpells(abbr)
            if list then
                for _, it in ipairs(list) do
                    if it[1] == name and not isDisciplineSpell(abbr, name) then
                        local kind = mapTLOCategoryToKind(nil, name)
                        if not kind or kind == 'other' then kind = it[4] or 'other' end
                        return abbr, (it[3] == 1), kind
                    end
                end
            end
        end
    end
    local fallbackKind = mapTLOCategoryToKind(nil, name)
    return myClasses[1] or 'War', true, fallbackKind
end


function runtime.getPrimarySpellForGem(slot)
    if not loadout or not loadout.gems then return nil end
    slot = tonumber(slot) or 1
    for _, g in ipairs(loadout.gems) do
        if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' then
            local pctVal = tonumber(g.pct)
            if pctVal == nil or pctVal > 0 then
                return g.spell, g
            end
        end
    end
    for _, g in ipairs(loadout.gems) do
        if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' then
            return g.spell, g
        end
    end
    return nil
end

function runtime.queueMemAll()
    local queued = 0
    local maxG = getNumGems()
    for slot = 1, maxG do
        local pSpell = runtime.getPrimarySpellForGem(slot)
        if pSpell and pSpell ~= '' then
            if not isGemMatching(slot, pSpell) then
                runtime.pendingMem[slot] = pSpell
                queued = queued + 1
            end
        end
    end
    if queued > 0 then
        print(string.format('\ag[Triune]\ax Queued %d missing/mismatched priority spell(s) to memorization bar.', queued))
    else
        print('\ag[Triune]\ax All priority spells are already memorized on your gem bar.')
    end
    return queued
end

-- Read the spells currently on the gem bar into the loadout -- no re-memming; the
-- spells are already memmed, so the engine can use them immediately.
function runtime.importCurrentGems(targetGemsTable)
    targetGemsTable = targetGemsTable or loadout.gems
    local newGems = {}
    local numG = getNumGems()
    for i = 1, numG do
        local nm
        pcall(function()
            local g = mq.TLO.Me.Gem(i)
            if g and g() then
                nm = g.Name()
            end
        end)
        if nm and nm ~= '' and nm ~= 'NULL' then
            local cls, bene, kind = spellClassInfo(nm)
            local tgt, wn, pc = defaultsForKind(kind, bene)
            table.insert(newGems, {
                gem = i,
                cls = cls,
                spell = nm,
                target = tgt,
                when = wn,
                pct = pc,
                min_xtar = 1,
                max_casts = 0,
                burn_only = false,
            })
        end
    end
    -- If there were existing configured spells beyond the physical bar, retain them
    if targetGemsTable then
        for idx = numG + 1, #targetGemsTable do
            if targetGemsTable[idx] then
                table.insert(newGems, targetGemsTable[idx])
            end
        end
    end
    for k in pairs(targetGemsTable) do targetGemsTable[k] = nil end
    for idx, v in ipairs(newGems) do targetGemsTable[idx] = v end
    runtime.saveLoadout(true)
    if #newGems > 0 then
        print(string.format('\ag[Triune]\ax Auto-populated %d spell(s) from current gem bar.', #newGems))
    else
        print('\ay[Triune]\ax No memorized spells found on current spell gem bar.')
    end
    return #newGems
end

-- Catches a stale loadout: a gem configured for spell X while the physical
-- bar actually has something else (or nothing) memmed in that slot -- e.g.
-- left over from before a re-mem, or the bar changed outside Triune.
local function checkGemMemSync()
    local now = os.clock()
    if (now - (runtime.lastGemSyncCheckAt or 0)) < 10.0 then return end
    runtime.lastGemSyncCheckAt = now
    runtime.gemSyncWarned = runtime.gemSyncWarned or {}
    if runtime.isSwitchingSpells or runtime.interruptedSwap then return end
    if mq.TLO.Window('SpellBookWnd').Open() then return end -- actively memming right now -- don't check mid-swap
    local maxG = getNumGems()
    for i = 1, maxG do
        local pSpell = runtime.getPrimarySpellForGem(i)
        if pSpell and pSpell ~= '' and not runtime.pendingMem[i] then
            if not isGemMatching(i, pSpell) then
                local matchesConfigured = false
                if loadout.gems then
                    for _, g in ipairs(loadout.gems) do
                        if g and (tonumber(g.gem) or 1) == i and g.spell and isGemMatching(i, g.spell) then
                            matchesConfigured = true
                            break
                        end
                    end
                end
                if not matchesConfigured then
                    local memmed
                    pcall(function() memmed = mq.TLO.Me.Gem(i).Name() end)
                    if memmed and memmed ~= '' and memmed ~= 'NULL' then
                        if not runtime.gemSyncWarned[i] then
                            runtime.gemSyncWarned[i] = true
                            print(string.format(
                                '\ay[Triune]\ax gem %d mismatch -- configured for "%s" but the bar actually has "%s" memmed there. '
                                .. 'Use Mem All to Bar, or re-pick the spell for this gem.',
                                i, pSpell, memmed))
                        end
                    end
                else
                    runtime.gemSyncWarned[i] = nil
                end
            else
                runtime.gemSyncWarned[i] = nil -- resolved (or slot empty) -- allow a future mismatch to warn again
            end
        else
            runtime.gemSyncWarned[i] = nil
        end
    end
end

function runtime.collectEntry()
    return {
        classes = myClasses,
        lvlMin = lvlMin,
        lvlMax = lvlMax,
        gems = loadout.gems,
        aas = loadout.aas,
        discs = loadout.discs,
        actions = loadout.actions,
        clickies = loadout.clickies,
        control = ctrl,
        presets = loadout.presets or {}
    }
end
function runtime.applyEntry(e)
    if type(e) ~= 'table' then return end
    if type(e.classes) == 'table' and #e.classes > 0 then myClasses = e.classes end
    lvlMin = e.lvlMin or lvlMin; lvlMax = e.lvlMax or lvlMax
    clearFilteredSpellsCache()
    loadout.gems = {}
    if type(e.gems) == 'table' then
        for i, g in ipairs(e.gems) do
            if type(g) == 'table' then
                g.gem = tonumber(g.gem) or math.min(i, 12)
                if g.gem < 1 then g.gem = 1 end
                if g.gem > 12 then g.gem = 12 end
                table.insert(loadout.gems, g)
            end
        end
        if #loadout.gems == 0 then
            for k = 1, 12 do
                local g = e.gems[k]
                if type(g) == 'table' then
                    g.gem = tonumber(g.gem) or k
                    table.insert(loadout.gems, g)
                end
            end
        end
    end
    loadout.aas  = {}
    if type(e.aas) == 'table' then
        for k, v in pairs(e.aas) do
            if not tonumber(k) and type(v) == 'table' then
                local cleanK = type(k) == 'string' and k:match('^%s*(.-)%s*$') or k
                if cleanK and cleanK ~= '' and not tonumber(cleanK) then
                    loadout.aas[cleanK] = v
                end
            end
        end
    end
    loadout.discs = e.discs or {}
    loadout.actions = {}
    if type(e.actions) == 'table' then
        for k, v in pairs(e.actions) do
            if not tonumber(k) and type(v) == 'table' then
                loadout.actions[k] = v
            end
        end
    end
    -- Migrate legacy special skills (e.g. Mend) saved in e.discs into loadout.actions
    if type(e.discs) == 'table' then
        for k, v in pairs(e.discs) do
            if isActionSkill(k) and type(v) == 'table' then
                if not loadout.actions[k] then
                    loadout.actions[k] = v
                end
            end
        end
    end
    -- Backfill entry.kind and autoskill on persisted Action entries
    if type(loadout.actions) == 'table' then
        for nm, act in pairs(loadout.actions) do
            if type(act) == 'table' then
                local def = defaultActionEntry(nm, act.cls or (myClasses and myClasses[1]) or 'War')
                if not act.kind then act.kind = def.kind end
                if not isAutoskillEligible(nm) then
                    act.autoskill = false
                elseif act.autoskill == nil then
                    act.autoskill = def.autoskill
                end
            end
        end
    end
    loadout.clickies = {}
    if type(e.clickies) == 'table' then
        for _, v in ipairs(e.clickies) do
            if type(v) == 'table' and v.name then
                table.insert(loadout.clickies, v)
            end
        end
    end
    loadout.presets = {}
    if type(e.presets) == 'table' then
        for k, v in pairs(e.presets) do
            if type(v) == 'table' then
                loadout.presets[k] = v
            end
        end
    end
    if type(e.control) == 'table' then
        for k, v in pairs(e.control) do ctrl[k] = v end
        sanitizeModeConfig()
        ctrl.combat_style = 'Melee'
        if ctrl.melee_dist == nil then ctrl.melee_dist = 14 end
        if ctrl.hunter_z_plane == nil then ctrl.hunter_z_plane = 15 end
        if ctrl.hunter_z == nil then ctrl.hunter_z = 75 end
        if ctrl.pull_min_hp_pct == nil then ctrl.pull_min_hp_pct = 0 end
        if ctrl.action_trained_only == nil then ctrl.action_trained_only = true end
        if ctrl.buff_refresh_sec == nil then ctrl.buff_refresh_sec = 45 end
        if ctrl.ma_id == nil then ctrl.ma_id = 0 end
        if type(ctrl.custom_ma_list) ~= 'table' then ctrl.custom_ma_list = {} end
        if ctrl.auto_group == nil then ctrl.auto_group = false end
        if ctrl.auto_trade == nil then ctrl.auto_trade = false end
        if ctrl.auto_dzadd == nil then ctrl.auto_dzadd = false end
        if ctrl.auto_accept_anyone == nil then ctrl.auto_accept_anyone = false end
        if ctrl.auto_accept_guild == nil then ctrl.auto_accept_guild = false end
        if ctrl.auto_accept_group == nil then ctrl.auto_accept_group = false end
        if type(ctrl.auto_accept_names) ~= 'table' then ctrl.auto_accept_names = {} end
        if ctrl.fov == nil then ctrl.fov = 100 end
        if ctrl.fov_enabled == nil then ctrl.fov_enabled = false end
        if type(ctrl.saved_window_positions) ~= 'table' then ctrl.saved_window_positions = {} end
        if ctrl.winpos_auto_restore_on_resize == nil then ctrl.winpos_auto_restore_on_resize = true end
        if ctrl.winpos_restore_visibility == nil then ctrl.winpos_restore_visibility = false end
        if type(ctrl.plugins) ~= 'table' then ctrl.plugins = {} end
        -- The combat anchor location is a zone-specific position (like camp_loc): never
        -- restore it from a saved file because the player will almost certainly
        -- be in a different location or zone. Keep the user's radius setting intact.
        ctrl.hunter_combat_loc = nil
    end
end

function runtime.deepCopyTable(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[runtime.deepCopyTable(orig_key)] = runtime.deepCopyTable(orig_value)
        end
        setmetatable(copy, runtime.deepCopyTable(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end


function runtime.savePreset(name)
    if type(name) ~= 'string' or name == '' then return end
    loadout.presets = loadout.presets or {}
    for k, _ in pairs(loadout.presets) do
        if type(k) ~= 'string' then loadout.presets[k] = nil end
    end
    loadout.presets[name] = {
        name = name,
        gems = runtime.deepCopyTable(loadout.gems),
        savedAt = os.date('%Y-%m-%d %H:%M:%S')
    }
    runtime.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Saved Spell Gems preset "\ay%s\ax".', name))
end

function runtime.loadPreset(name, autoMem)
    if not name or name == '' then return false end
    if not loadout.presets or not loadout.presets[name] then
        print(string.format('\ar[Triune]\ax Preset "\ay%s\ax" not found.', name))
        return false
    end
    local p = loadout.presets[name]
    if p.gems then
        loadout.gems = runtime.deepCopyTable(p.gems)
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Loaded Spell Gems preset "\ay%s\ax".', name))
        if autoMem or ctrl.automem then
            for slot = 1, getNumGems() do
                local pSpell = runtime.getPrimarySpellForGem(slot)
                if pSpell and pSpell ~= '' then
                    runtime.pendingMem[slot] = pSpell
                end
            end
            print('\ag[Triune]\ax Queued primary spells to memorization bar.')
        end
        return true
    end
    return false
end

function runtime.deletePreset(name)
    if not name or name == '' or not loadout.presets then return end
    if loadout.presets[name] then
        loadout.presets[name] = nil
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Deleted Spell Gems preset "\ay%s\ax".', name))
    else
        print(string.format('\ar[Triune]\ax Preset "\ay%s\ax" does not exist.', name))
    end
end

function runtime.listPresets()
    print('\ag[Triune]\ax --- Saved Spell Gem Presets ---')
    local count = 0
    if loadout.presets then
        for k, v in pairs(loadout.presets) do
            count = count + 1
            print(string.format('  • "\ay%s\ax" (saved: %s)', k, tostring(v.savedAt or 'unknown')))
        end
    end
    if count == 0 then
        print('  \ayNo presets saved yet. Use /ac preset save <name> or the UI to save one.\ax')
    end
end

-- Waypoints are plain {name,x,y,z} tables with no nesting -- a per-entry
-- shallow copy is enough to keep a saved zone/preset snapshot from aliasing
-- the live ctrl.waypoints list (so editing one doesn't silently edit the other).
local function copyWaypointList(list)
    local out = {}
    for i, wp in ipairs(list or {}) do
        out[i] = { name = wp.name, x = wp.x, y = wp.y, z = wp.z }
    end
    return out
end

-- ============================================================================
-- Waypoint preset export/import string helpers
-- ============================================================================
-- Exported strings look like "TACWP1:<base64>". The number after TACWP is a
-- schema version (independent of the addon's own version -- it only bumps if
-- this payload layout changes), so an import from a newer Triune can be
-- rejected with a clear message instead of being misread.
--
-- The base64 payload is plain fielded data, NEVER Lua source -- it must only
-- ever be parsed by splitByChar()/tonumber() below, never handed to
-- load()/loadstring(). These strings get pasted from other players, so
-- treating them as data instead of code is the whole point.
--
-- Fields are joined with \30 (record separator) and \31 (unit separator,
-- used inside each waypoint's own 4 fields) -- both control characters a
-- player can't type into a name field, so sanitizeWpField() strips any stray
-- control characters before a field is written out, guaranteeing they can
-- never collide with our own delimiters.
local WP = {
    VERSION    = 1,
    PREFIX     = 'TACWP1:',
    RS         = string.char(30),
    US         = string.char(31),
    B64_CHARS  = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
    B64_LOOKUP = {},
}
do
    for i = 1, #WP.B64_CHARS do WP.B64_LOOKUP[WP.B64_CHARS:sub(i, i)] = i - 1 end
end

local function sanitizeWpField(s)
    return (tostring(s or ''):gsub('%c', ''))
end

local function base64Encode(data)
    local chars = WP.B64_CHARS
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        b2 = b2 or 0
        b3 = b3 or 0
        local n = b1 * 65536 + b2 * 256 + b3
        local rem = math.min(3, len - i + 1)
        out[#out + 1] = chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = (rem >= 2) and chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '='
        out[#out + 1] = (rem >= 3) and chars:sub(n % 64 + 1, n % 64 + 1) or '='
    end
    return table.concat(out)
end

local function base64Decode(str)
    local lookup = WP.B64_LOOKUP
    str = tostring(str or ''):gsub('[^A-Za-z0-9%+%/%=]', '')
    local out = {}
    local i = 1
    local slen = #str
    while i + 3 <= slen do
        local c1 = lookup[str:sub(i, i)]
        local c2 = lookup[str:sub(i + 1, i + 1)]
        local s3, s4 = str:sub(i + 2, i + 2), str:sub(i + 3, i + 3)
        local c3, c4 = lookup[s3], lookup[s4]
        if not c1 or not c2 then return nil end
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if s3 ~= '=' and c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if s4 ~= '=' and c4 then out[#out + 1] = string.char(n % 256) end
        i = i + 4
    end
    return table.concat(out)
end

local function splitByChar(s, sep)
    local out = {}
    local start = 1
    while true do
        local idx = s:find(sep, start, true)
        if not idx then
            out[#out + 1] = s:sub(start)
            break
        end
        out[#out + 1] = s:sub(start, idx - 1)
        start = idx + 1
    end
    return out
end

-- Per-character loadout file path (multibox-safe). Each client writes ONLY its
-- own triune_loadout_<server>_<char>.lua, so different characters never share
-- (and never overwrite each other's) settings, ignore/pull lists, or zone data.
local function loadoutFilePath()
    local serverName = ''
    pcall(function() serverName = mq.TLO.EverQuest.ServerName() or '' end)
    if not serverName or serverName == '' then
        pcall(function() serverName = mq.TLO.Zone.Server() or '' end)
    end
    local tag = (tostring(serverName or '') .. '_' .. tostring(myName or 'unknown')):gsub('[^%w%_-]', '_')
    return cfg .. '/triune_loadout_' .. tag .. '.lua'
end

function runtime.loadAll()
    local t = nil
    if myName then
        local fn = loadfile(loadoutFilePath())
        if fn then
            local ok, t2 = pcall(fn)
            if ok and type(t2) == 'table' then t = t2 end
        end
    end
    if not t then
        -- Legacy shared file fallback (pre-per-character migration).
        local fn = loadfile(cfg .. '/triune_loadout.lua')
        if fn then
            local ok, t2 = pcall(fn)
            if ok and type(t2) == 'table' then t = t2 end
        end
    end
    if not t then return end
    ALLDATA = t
    if type(ALLDATA.__ignore) == 'table' then runtime.ignoreList = ALLDATA.__ignore end
    if type(ALLDATA.__pullList) == 'table' then runtime.pullList = ALLDATA.__pullList end
    if type(ALLDATA.__zoneHazards) == 'table' then ctrl.zone_hazards = ALLDATA.__zoneHazards end
    if type(ALLDATA.__zoneWaypoints) == 'table' then ctrl.zone_waypoints = ALLDATA.__zoneWaypoints end
    if type(ALLDATA.__zoneWaypointPresets) == 'table' then ctrl.zone_waypoint_presets = ALLDATA.__zoneWaypointPresets end
end

-- Snapshots the live waypoint list/settings into ctrl.zone_waypoints for the
-- current zone (shared across all characters, like zone_hazards). Called from
-- runtime.saveLoadout() so it stays current without needing to be hooked into every
-- individual waypoint-editing call site.
function runtime.syncCurrentZoneWaypoints()
    local zs
    pcall(function() zs = mq.TLO.Zone.ShortName() end)
    if not zs or zs == '' then return end
    if not ctrl.zone_waypoints then ctrl.zone_waypoints = {} end
    ctrl.zone_waypoints[zs] = {
        waypoints            = copyWaypointList(ctrl.waypoints),
        waypoint_radius      = ctrl.waypoint_radius,
        waypoint_scan_radius = ctrl.waypoint_scan_radius,
        waypoint_loop        = ctrl.waypoint_loop,
    }
end

runtime.saveLoadout = function(silent)
    if runtime.pluginManager and runtime.pluginManager.collectSettings then
        runtime.pluginManager.collectSettings()
    end
    if myName then ALLDATA[myName] = runtime.collectEntry() end
    ALLDATA.__ignore = runtime.ignoreList
    ALLDATA.__pullList = runtime.pullList
    ALLDATA.__zoneHazards = ctrl.zone_hazards
    runtime.syncCurrentZoneWaypoints()
    ALLDATA.__zoneWaypoints = ctrl.zone_waypoints
    ALLDATA.__zoneWaypointPresets = ctrl.zone_waypoint_presets
    local f = io.open(loadoutFilePath(), 'w')
    if not f then return end
    f:write('return '); serialize(ALLDATA, f, 1); f:close()
    if runtime.pluginManager and runtime.pluginManager.onLoadoutSaved then
        runtime.pluginManager.onLoadoutSaved()
    end
    if not silent then print('\ag[Triune]\ax saved loadout for ' .. tostring(myName or '?') .. '.') end
end

function runtime.addIgnore(name)
    if not name or name == '' or isIgnored(name) then return end
    table.insert(runtime.ignoreList, name)
    table.sort(runtime.ignoreList)
    runtime.saveLoadout(true)
    print('\ag[Triune]\ax added to ignore list: ' .. name)
end
function runtime.removeIgnore(name)
    for i, n in ipairs(runtime.ignoreList) do
        if n == name then
            table.remove(runtime.ignoreList, i); break
        end
    end
    runtime.saveLoadout(true)
    print('\ag[Triune]\ax removed from ignore list: ' .. name)
end

-- pull-list (include-list) helpers for Puller mode:
function runtime.isPullListed(name)
    if not name or name == '' then return false end
    for _, n in ipairs(runtime.pullList) do if n == name then return true end end
    return false
end
function runtime.addPull(name)
    if not name or name == '' or runtime.isPullListed(name) then return end
    table.insert(runtime.pullList, name)
    table.sort(runtime.pullList)
    runtime.saveLoadout(true)
    print('\ag[Triune]\ax added to pull list: ' .. name)
end
function runtime.removePull(name)
    for i, n in ipairs(runtime.pullList) do
        if n == name then
            table.remove(runtime.pullList, i); break
        end
    end
    runtime.saveLoadout(true)
    print('\ag[Triune]\ax removed from pull list: ' .. name)
end

-- Auto-Accept (group / trade / dzadd) lives in the auto_accept plugin (lua/tac/auto_accept.lua).

-- Waypoint Patrol helpers for Puller mode (attached to runtime table to respect 200 local limit)
function runtime.getMapsDirectory()
    local candidates = {
        'maps',
        '../maps',
        '../../maps',
    }
    if mq.configDir then
        candidates[#candidates + 1] = mq.configDir .. '/../maps'
        candidates[#candidates + 1] = mq.configDir .. '/../../maps'
    end
    if mq.luaDir then
        candidates[#candidates + 1] = mq.luaDir .. '/../maps'
        candidates[#candidates + 1] = mq.luaDir .. '/../../maps'
    end
    for _, dir in ipairs(candidates) do
        local testFile = dir .. '/triune_map_test.tmp'
        local f = io.open(testFile, 'w')
        if f then
            f:close()
            os.remove(testFile)
            return dir
        end
    end
    return nil
end

function runtime.syncWaypointMapLines(zoneShort, forceSync)
    if not zoneShort or zoneShort == '' then
        pcall(function() zoneShort = mq.TLO.Zone.ShortName() end)
    end
    if not zoneShort or zoneShort == '' then return end

    local wps = (ctrl.use_waypoints and ctrl.waypoints) or {}
    local wpsCoordParts = {}
    for idx, wp in ipairs(wps) do
        wpsCoordParts[#wpsCoordParts + 1] = string.format('%d:%.1f,%.1f,%.1f', idx, wp.x or 0, wp.y or 0, wp.z or 0)
    end
    local syncKey = string.format('%s|%s|%s', zoneShort, tostring(ctrl.use_waypoints), table.concat(wpsCoordParts, ';'))
    if not forceSync and runtime.lastSyncedMapWpsKey == syncKey then
        return
    end

    local mapsDir = runtime.getMapsDirectory()
    if not mapsDir then return end

    local mapFilePath = string.format('%s/%s_3.txt', mapsDir, zoneShort)
    local existingLines = {}
    local fRead = io.open(mapFilePath, 'r')
    if fRead then
        local inTriuneSection = false
        for line in fRead:lines() do
            if string.find(line, '^# TRIUNE_WAYPOINTS_START') then
                inTriuneSection = true
            elseif string.find(line, '^# TRIUNE_WAYPOINTS_END') then
                inTriuneSection = false
            elseif not inTriuneSection then
                existingLines[#existingLines + 1] = line
            end
        end
        fRead:close()
    end

    if #wps > 0 then
        existingLines[#existingLines + 1] = '# TRIUNE_WAYPOINTS_START'
        for i = 1, #wps - 1 do
            local wp1 = wps[i]
            local wp2 = wps[i + 1]
            if wp1 and wp2 and wp1.x and wp1.y and wp2.x and wp2.y then
                -- EQ map line format: L StartX, StartY, StartZ, EndX, EndY, EndZ, R, G, B (-x, -y, z)
                existingLines[#existingLines + 1] = string.format('L %.2f, %.2f, %.2f, %.2f, %.2f, %.2f, 0, 255, 255',
                    -(wp1.x or 0), -(wp1.y or 0), wp1.z or 0, -(wp2.x or 0), -(wp2.y or 0), wp2.z or 0)
            end
        end
        for i = 1, #wps do
            local wp1 = wps[i]
            if wp1 and wp1.x and wp1.y then
                existingLines[#existingLines + 1] = string.format('P %.2f, %.2f, %.2f, 255, 215, 0, 1, %s',
                    -(wp1.x or 0), -(wp1.y or 0), wp1.z or 0, wp1.name or ('WP ' .. i))
            end
        end
        existingLines[#existingLines + 1] = '# TRIUNE_WAYPOINTS_END'
    end

    local fWrite = io.open(mapFilePath, 'w')
    if fWrite then
        for _, line in ipairs(existingLines) do
            fWrite:write(line .. '\n')
        end
        fWrite:close()
        runtime.lastSyncedMapWpsKey = syncKey
    end
end

function runtime.setNearestWaypoint()
    local wps = ctrl.waypoints
    if not wps or #wps == 0 then return end
    local myX, myY, myZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    if not myX or not myY or not myZ then return end

    local bestDist = 999999
    local bestIdx = 1
    for i, wp in ipairs(wps) do
        if wp and wp.x and wp.y and wp.z then
            local d = distToLoc(wp.x, wp.y, wp.z)
            if d < bestDist then
                bestDist = d
                bestIdx = i
            end
        end
    end

    ctrl.current_waypoint_idx = bestIdx
    if not ctrl.waypoint_loop and bestIdx >= #wps and #wps > 1 then
        ctrl.waypoint_direction = -1
    else
        ctrl.waypoint_direction = 1
    end

    local targetWp = wps[bestIdx]
    if targetWp then
        print(string.format('\ag[Triune]\ax Nearest waypoint acquired: %s (#%d, dist: %.0f) [%s]',
            targetWp.name or ('WP ' .. bestIdx), bestIdx, bestDist,
            (ctrl.waypoint_direction or 1) == 1 and 'Forward' or 'Reverse'))
    end
end

function runtime.wpAdd(name)
    local y, x, z = mq.TLO.Me.Y(), mq.TLO.Me.X(), mq.TLO.Me.Z()
    if not x or not y or not z then return false end
    ctrl.waypoints = ctrl.waypoints or {}
    local wpNum = #ctrl.waypoints + 1
    local wpName = (name and name ~= '') and name or string.format('WP %d', wpNum)
    table.insert(ctrl.waypoints,
        { name = wpName, x = math.floor(x * 10) / 10, y = math.floor(y * 10) / 10, z = math.floor(z * 10) / 10 })
    ctrl.use_waypoints = true
    runtime.saveLoadout(true)
    runtime.syncWaypointMapLines()
    return wpNum, wpName, x, y, z
end

function runtime.wpClear()
    ctrl.waypoints = {}
    ctrl.current_waypoint_idx = 1
    ctrl.waypoint_direction = 1
    runtime.saveLoadout(true)
    runtime.syncWaypointMapLines()
end

function runtime.wpDelete(idx)
    if not ctrl.waypoints or not ctrl.waypoints[idx] then return false end
    table.remove(ctrl.waypoints, idx)
    if not ctrl.current_waypoint_idx or ctrl.current_waypoint_idx > #ctrl.waypoints then
        ctrl.current_waypoint_idx = 1
        ctrl.waypoint_direction = 1
    end
    runtime.saveLoadout(true)
    runtime.syncWaypointMapLines()
    return true
end

function runtime.wpMoveUp(idx)
    if not ctrl.waypoints or idx <= 1 or idx > #ctrl.waypoints then return false end
    local tmp = ctrl.waypoints[idx]
    ctrl.waypoints[idx] = ctrl.waypoints[idx - 1]
    ctrl.waypoints[idx - 1] = tmp
    if ctrl.current_waypoint_idx == idx then
        ctrl.current_waypoint_idx = idx - 1
    elseif ctrl.current_waypoint_idx == idx - 1 then
        ctrl.current_waypoint_idx = idx
    end
    runtime.saveLoadout(true)
    runtime.syncWaypointMapLines()
    return true
end

function runtime.wpMoveDown(idx)
    if not ctrl.waypoints or idx < 1 or idx >= #ctrl.waypoints then return false end
    local tmp = ctrl.waypoints[idx]
    ctrl.waypoints[idx] = ctrl.waypoints[idx + 1]
    ctrl.waypoints[idx + 1] = tmp
    if ctrl.current_waypoint_idx == idx then
        ctrl.current_waypoint_idx = idx + 1
    elseif ctrl.current_waypoint_idx == idx + 1 then
        ctrl.current_waypoint_idx = idx
    end
    runtime.saveLoadout(true)
    runtime.syncWaypointMapLines()
    return true
end

-- ============================================================================
-- Per-Zone Waypoint Routes & Named Presets
-- ============================================================================
-- "Current" (ctrl.zone_waypoints, keyed by zone) auto-tracks whatever route/
-- settings are live in each zone -- see runtime.syncCurrentZoneWaypoints() above and
-- runtime.loadZoneWaypoints() below (called from onZoned()). Named presets
-- (ctrl.zone_waypoint_presets) are explicit user-saved snapshots on top of
-- that, also keyed by zone, shared across all characters like zone_hazards.

function runtime.getZoneDisplayName(zs)
    local nm
    pcall(function() nm = mq.TLO.Zone.LongName() end)
    if not nm or nm == '' then nm = zs end
    return tostring(nm)
end

-- Applies the zone's auto-saved "Current" route (if any) into the live
-- ctrl.waypoints/settings. No-op if nothing has been saved for this zone yet
-- -- whatever's already loaded is left alone rather than cleared.
function runtime.loadZoneWaypoints(zs)
    zs = zs or runtime.getCurrentZoneShortName()
    local saved = ctrl.zone_waypoints and ctrl.zone_waypoints[zs]
    if not saved then return false end
    ctrl.waypoints            = copyWaypointList(saved.waypoints)
    ctrl.waypoint_radius      = saved.waypoint_radius or ctrl.waypoint_radius
    ctrl.waypoint_scan_radius = saved.waypoint_scan_radius or ctrl.waypoint_scan_radius
    ctrl.waypoint_loop        = saved.waypoint_loop or false
    ctrl.current_waypoint_idx = 1
    ctrl.waypoint_direction   = 1
    runtime.wpSelectedPreset  = nil
    runtime.syncWaypointMapLines(zs, true)
    return true
end

function runtime.wpPresetsForZone(zs)
    zs = zs or runtime.getCurrentZoneShortName()
    if not ctrl.zone_waypoint_presets then ctrl.zone_waypoint_presets = {} end
    if not ctrl.zone_waypoint_presets[zs] then ctrl.zone_waypoint_presets[zs] = {} end
    return ctrl.zone_waypoint_presets[zs]
end

-- Inserts/overwrites `snapshot` (must have a .name) into the given zone's
-- preset list, keyed by name. Shared by manual Save and Import.
function runtime.upsertZonePreset(zs, snapshot)
    local list = runtime.wpPresetsForZone(zs)
    for i, p in ipairs(list) do
        if p.name == snapshot.name then
            list[i] = snapshot
            runtime.saveLoadout(true)
            return
        end
    end
    table.insert(list, snapshot)
    runtime.saveLoadout(true)
end

-- Saving over an existing name overwrites that preset in place.
function runtime.wpPresetSave(name)
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then return false, 'Enter a name for the preset.' end
    local zs = runtime.getCurrentZoneShortName()
    runtime.upsertZonePreset(zs, {
        name                 = name,
        zoneName             = runtime.getZoneDisplayName(zs),
        waypoints            = copyWaypointList(ctrl.waypoints),
        waypoint_radius      = ctrl.waypoint_radius,
        waypoint_scan_radius = ctrl.waypoint_scan_radius,
        waypoint_loop        = ctrl.waypoint_loop,
    })
    return true, nil, name
end

function runtime.wpPresetLoad(name)
    local zs = runtime.getCurrentZoneShortName()
    local list = runtime.wpPresetsForZone(zs)
    for _, p in ipairs(list) do
        if p.name == name then
            ctrl.waypoints            = copyWaypointList(p.waypoints)
            ctrl.waypoint_radius      = p.waypoint_radius or ctrl.waypoint_radius
            ctrl.waypoint_scan_radius = p.waypoint_scan_radius or ctrl.waypoint_scan_radius
            ctrl.waypoint_loop        = p.waypoint_loop or false
            ctrl.current_waypoint_idx = 1
            ctrl.waypoint_direction   = 1
            runtime.syncWaypointMapLines(zs, true)
            runtime.saveLoadout(true) -- also refreshes this zone's "Current" snapshot to match
            return true
        end
    end
    return false
end

function runtime.wpPresetDelete(name)
    local zs = runtime.getCurrentZoneShortName()
    local list = runtime.wpPresetsForZone(zs)
    for i, p in ipairs(list) do
        if p.name == name then
            table.remove(list, i)
            runtime.saveLoadout(true)
            return true
        end
    end
    return false
end

function runtime.wpPresetRename(oldName, newName)
    newName = tostring(newName or ''):match('^%s*(.-)%s*$')
    if newName == '' then return false, 'Enter a new name.' end
    local zs = runtime.getCurrentZoneShortName()
    local list = runtime.wpPresetsForZone(zs)
    for _, p in ipairs(list) do
        if p.name == newName and p.name ~= oldName then
            return false, 'A preset with that name already exists.'
        end
    end
    for _, p in ipairs(list) do
        if p.name == oldName then
            p.name = newName
            runtime.saveLoadout(true)
            return true, nil, newName
        end
    end
    return false
end

-- Exports a named preset as a shareable "TACWP1:..." string. Only named
-- presets can be exported (not the auto-tracked "Current" state) so every
-- export always carries a name for the recipient to import under.
function runtime.wpPresetExport(name)
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then return nil, 'Select a preset to export first.' end
    local zs = runtime.getCurrentZoneShortName()
    local snap
    for _, p in ipairs(runtime.wpPresetsForZone(zs)) do
        if p.name == name then snap = p break end
    end
    if not snap then return nil, 'Preset not found.' end
    if not snap.waypoints or #snap.waypoints == 0 then
        return nil, 'That preset has no waypoints in it.'
    end

    local fields = {
        sanitizeWpField(snap.name),
        sanitizeWpField(zs or ''),
        sanitizeWpField(snap.zoneName or runtime.getZoneDisplayName(zs)),
        string.format('%.2f', snap.waypoint_radius or 0),
        string.format('%.2f', snap.waypoint_scan_radius or 0),
        snap.waypoint_loop and '1' or '0',
    }
    local payload = { table.concat(fields, WP.RS) }
    for _, wp in ipairs(snap.waypoints) do
        payload[#payload + 1] = table.concat({
            sanitizeWpField(wp.name or ''),
            string.format('%.2f', wp.x or 0),
            string.format('%.2f', wp.y or 0),
            string.format('%.2f', wp.z or 0),
        }, WP.US)
    end
    return WP.PREFIX .. base64Encode(table.concat(payload, WP.RS))
end

-- Parses an exported string WITHOUT writing anything -- callers decide what
-- to do next (e.g. confirm before overwriting a same-named preset). Never
-- executes the string as code; only tonumber()/splitByChar() touch it.
function runtime.wpPresetParseImport(str)
    str = tostring(str or ''):match('^%s*(.-)%s*$')
    if str == '' then return nil, 'Paste an exported waypoint string first.' end

    local versionStr, body = str:match('^TACWP(%d+):(.+)$')
    if not versionStr then return nil, 'Not a recognized Triune waypoint string.' end
    local version = tonumber(versionStr)
    if version ~= WP.VERSION then
        return nil, string.format(
            'This string uses waypoint format v%s, but this version of Triune only supports v%d. Update Triune and try again.',
            versionStr, WP.VERSION)
    end

    local payload = base64Decode(body)
    if not payload or payload == '' then
        return nil, 'Could not decode that string -- it looks corrupted or incomplete.'
    end

    local parts = splitByChar(payload, WP.RS)
    if #parts < 6 then return nil, 'That string is missing data -- it looks corrupted or incomplete.' end

    local name, zoneShort, zoneDisplay = parts[1], parts[2], parts[3]
    local radius = tonumber(parts[4])
    local scanRadius = tonumber(parts[5])
    if name == '' then return nil, 'That string has no preset name in it -- it looks corrupted.' end
    if zoneShort == '' or not radius or not scanRadius then
        return nil, 'That string is missing data -- it looks corrupted or incomplete.'
    end

    local waypoints = {}
    for i = 7, #parts do
        local wpFields = splitByChar(parts[i], WP.US)
        local wx, wy, wz = tonumber(wpFields[2]), tonumber(wpFields[3]), tonumber(wpFields[4])
        if not (wx and wy and wz) then
            return nil, 'That string is missing data -- it looks corrupted or incomplete.'
        end
        waypoints[#waypoints + 1] = { name = wpFields[1] or '', x = wx, y = wy, z = wz }
    end
    if #waypoints == 0 then return nil, 'That string has no waypoints in it.' end

    local currentZs = runtime.getCurrentZoneShortName()
    local collision = false
    for _, p in ipairs(runtime.wpPresetsForZone(zoneShort)) do
        if p.name == name then collision = true break end
    end

    return {
        name                 = name,
        zoneShort            = zoneShort,
        zoneDisplay          = zoneDisplay ~= '' and zoneDisplay or zoneShort,
        waypoint_radius      = radius,
        waypoint_scan_radius = scanRadius,
        waypoint_loop        = parts[6] == '1',
        waypoints            = waypoints,
        zoneMismatch         = (currentZs ~= '' and currentZs ~= zoneShort),
        currentZoneDisplay   = runtime.getZoneDisplayName(currentZs),
        collision            = collision,
    }
end

-- Writes a pending import (from wpPresetParseImport) into that zone's preset
-- list, overwriting any same-named preset. Callers are expected to have
-- already confirmed the overwrite with the user when pending.collision is true.
function runtime.wpPresetCommitImport(pending)
    if not pending then return false end
    runtime.upsertZonePreset(pending.zoneShort, {
        name                 = pending.name,
        zoneName             = pending.zoneDisplay,
        waypoints            = copyWaypointList(pending.waypoints),
        waypoint_radius      = pending.waypoint_radius,
        waypoint_scan_radius = pending.waypoint_scan_radius,
        waypoint_loop        = pending.waypoint_loop,
    })
    return true
end

function runtime.isPullAllowed(name)
    if not name then return false end
    local cleanName = tostring(name)
    if cleanName == '' then return false end
    if isIgnored(cleanName) then return false end
    if not runtime.pullList or #runtime.pullList == 0 then return true end
    for _, n in ipairs(runtime.pullList) do
        local strN = tostring(n)
        if strN ~= '' and (cleanName == strN or cleanName:find(strN, 1, true)) then
            return true
        end
    end
    return false
end

function runtime.extractConName(line)
    if not line or line == '' then return nil end
    local name = line:match('^(.-)%s+scowls')
        or line:match('^(.-)%s+glares')
        or line:match('^(.-)%s+glowers')
        or line:match('^(.-)%s+looks')
        or line:match('^(.-)%s+regards')
        or line:match('^(.-)%s+judges')
        or line:match('^(.-)%s+judge')
    if name then
        name = name:gsub('^%s*(.-)%s*$', '%1')
        if name ~= '' then return name end
    end
    return nil
end

function runtime.recordTargetCon(tier, line)
    runtime.conCache = runtime.conCache or {}
    local tgtName = mq.TLO.Target.CleanName()
    if not tgtName or tgtName == '' then
        tgtName = runtime.extractConName(line)
    end
    if not tgtName or tgtName == '' or not tier then return end
    runtime.conCache[tgtName] = tier
    if ctrl and ctrl.debug_mode then
        print(string.format('\ag[Triune]\ax Captured faction consideration for "%s": %s', tgtName, tier))
    end
end

mq.event('TriuneConScowl', '#*#scowls#*#', function(line) runtime.recordTargetCon('Scowling', line) end)
mq.event('TriuneConThreat', '#*#threateningly#*#', function(line) runtime.recordTargetCon('Threateningly', line) end)
mq.event('TriuneConDubious', '#*#dubiously#*#', function(line) runtime.recordTargetCon('Dubious', line) end)
mq.event('TriuneConApprehens', '#*#apprehensively#*#', function(line) runtime.recordTargetCon('Apprehensive', line) end)
mq.event('TriuneConIndiff', '#*#indifferently#*#', function(line) runtime.recordTargetCon('Indifferent', line) end)
mq.event('TriuneConAmiable', '#*#amiably#*#', function(line) runtime.recordTargetCon('Amiably', line) end)
mq.event('TriuneConKindly', '#*#kindly#*#', function(line) runtime.recordTargetCon('Kindly', line) end)
mq.event('TriuneConWarmly', '#*#warmly#*#', function(line) runtime.recordTargetCon('Warmly', line) end)
mq.event('TriuneConAlly', '#*#an ally#*#', function(line) runtime.recordTargetCon('Ally', line) end)


function runtime.isConAllowed(s)
    if not s or not s() then return false end
    if not ctrl or not ctrl.pull_con_filter then return true end

    local cname = nil
    local okName, nameVal = pcall(function() return s.CleanName() end)
    if okName and nameVal and nameVal ~= '' then
        cname = nameVal
    end

    -- 1. Check runtime cache if exact consideration was previously captured via /con
    if cname and runtime.conCache and runtime.conCache[cname] then
        local cachedTier = runtime.conCache[cname]
        if ctrl and ctrl.pull_con_filter and ctrl.pull_con_filter[cachedTier] == false then
            return false
        end
    end

    -- 2. If un-cached, allow initial candidate targeting (faction will be cached upon /con)
    return true
end

function runtime.verifyTargetCon(id, blockUntilCached)
    if not id or id <= 0 then return true end
    if isXTargetId(id) then return true end

    local tgt = mq.TLO.Target
    if not tgt() or (tgt.ID() or 0) ~= id then return true end

    local cname = tgt.CleanName()
    if not cname or cname == '' then return true end

    runtime.conCache = runtime.conCache or {}
    if not runtime.conCache[cname] then
        mq.cmd('/consider')
        if blockUntilCached then
            local waited = 0
            while waited < 400 do
                mq.delay(20)
                mq.doevents()
                waited = waited + 20
                if runtime.conCache[cname] then break end
            end
        else
            mq.doevents()
        end
    end

    local cachedTier = runtime.conCache[cname]
    if cachedTier and ctrl and ctrl.pull_con_filter then
        if ctrl.pull_con_filter[cachedTier] == false then
            return false
        end
    end

    return true
end

-- lightweight signature of the loadout, for auto-save change detection
local function loadoutSig()
    local p = { table.concat(myClasses or {}, ','), tostring(lvlMin), tostring(lvlMax) }
    if loadout.gems then
        for i, g in ipairs(loadout.gems) do
            if type(g) == 'table' then
                p[#p + 1] = tostring(i) ..
                    '~' ..
                    tostring(g.gem or i) ..
                    '~' ..
                    tostring(g.cls) ..
                    '~' ..
                    tostring(g.spell) ..
                    '~' ..
                    tostring(g.target) ..
                    '~' ..
                    tostring(g.when) ..
                    '~' ..
                    tostring(g.pct) ..
                    '~' ..
                    tostring(g.min_hp) ..
                    '~' ..
                    tostring(g.min_xtar) ..
                    '~' ..
                    tostring(g.max_casts or 0) ..
                    '~' ..
                    tostring(g.burn_only)
            end
        end
    end
    local akeys = {}
    if loadout.aas then for k in pairs(loadout.aas) do akeys[#akeys + 1] = k end end
    table.sort(akeys)
    for _, nm in ipairs(akeys) do
        local a = loadout.aas[nm]
        if type(a) == 'table' then
            p[#p + 1] = nm ..
                '~' ..
                tostring(a.enabled) .. '~' .. tostring(a.target) .. '~' .. tostring(a.when) .. '~' .. tostring(a.pct)
                .. '~' .. tostring(a.boss_only) .. '~' .. tostring(a.burn_only) .. '~' .. tostring(a.priority)
        end
    end
    local dkeys = {}
    if loadout.discs then for k in pairs(loadout.discs) do dkeys[#dkeys + 1] = k end end
    table.sort(dkeys)
    for _, nm in ipairs(dkeys) do
        local d = loadout.discs and loadout.discs[nm]
        if type(d) == 'table' then
            p[#p + 1] = nm ..
                '~' ..
                tostring(d.enabled) .. '~' .. tostring(d.target) .. '~' .. tostring(d.when) .. '~' .. tostring(d.pct)
                .. '~' .. tostring(d.boss_only) .. '~' .. tostring(d.burn_only) .. '~' .. tostring(d.priority)
        end
    end
    local actkeys = {}
    if loadout.actions then for k in pairs(loadout.actions) do actkeys[#actkeys + 1] = k end end
    table.sort(actkeys)
    for _, nm in ipairs(actkeys) do
        local act = loadout.actions and loadout.actions[nm]
        if type(act) == 'table' then
            p[#p + 1] = nm ..
                '~' ..
                tostring(act.enabled) .. '~' .. tostring(act.autoskill) .. '~' .. tostring(act.target) .. '~' .. tostring(act.when) .. '~' .. tostring(act.pct)
                .. '~' .. tostring(act.boss_only) .. '~' .. tostring(act.burn_only) .. '~' .. tostring(act.priority)
        end
    end
    local ckeys = {}
    if ctrl then for k in pairs(ctrl) do ckeys[#ckeys + 1] = k end end
    table.sort(ckeys)
    local ctrlParts = {}
    for _, k in ipairs(ckeys) do
        if k ~= 'current_waypoint_idx' and k ~= 'waypoint_direction' then
            local v = ctrl[k]
            if type(v) == 'table' then
                if k == 'camp_loc' or k == 'hunter_combat_loc' then
                    ctrlParts[#ctrlParts + 1] = string.format('%s=%.1f,%.1f,%.1f', k, v.x or 0, v.y or 0, v.z or 0)
                elseif k == 'pull_con_filter' then
                    local conStr = {}
                    for ck, cv in pairs(v) do conStr[#conStr + 1] = ck .. '=' .. tostring(cv) end
                    table.sort(conStr)
                    ctrlParts[#ctrlParts + 1] = 'pull_con_filter:' .. table.concat(conStr, ',')
                elseif k == 'waypoints' then
                    local wpStr = {}
                    for idx, wp in ipairs(v) do
                        wpStr[#wpStr + 1] = string.format('%d:%s=%.1f,%.1f,%.1f', idx, wp.name or ('WP ' .. idx),
                            wp.x or 0,
                            wp.y or 0, wp.z or 0)
                    end
                    ctrlParts[#ctrlParts + 1] = 'waypoints:' .. table.concat(wpStr, ';')
                end
            else
                ctrlParts[#ctrlParts + 1] = string.format('%s=%s', k, tostring(v))
            end
        end
    end
    p[#p + 1] = table.concat(ctrlParts, '~')
    if runtime.ignoreList then p[#p + 1] = 'ignore:' .. table.concat(runtime.ignoreList, ',') end
    if runtime.pullList then p[#p + 1] = 'pull:' .. table.concat(runtime.pullList, ',') end
    return table.concat(p, '|')
end

-- Field of View (FOV) Camera Management
function runtime.applyFov()
    if not ctrl.fov_enabled then return end
    if not runtime.fovLoaded() then return end
    local val = tonumber(ctrl.fov) or 100
    if val < 50 then val = 50 end
    if val > 150 then val = 150 end
    mq.cmdf('/fov %d', math.floor(val))
end

-- Called when the logged-in character changes: load that toon's saved setup, or
-- detect classes fresh if it's new.
function runtime.onCharacterChanged()
    loadout = { gems = {}, aas = {}, discs = {}, actions = {}, clickies = {} }
    ctrl = defaultCtrl()
    runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
    lvlMin, lvlMax = 1, 65
    if ALLDATA[myName] then
        runtime.applyEntry(ALLDATA[myName])
        scanKnownDiscs()
    else
        local detected = detectClasses(true)
        if detected then myClasses = detected end
        runtime.importCurrentGems() -- new character: seed the loadout from the current bar
    end
    if not myClasses or #myClasses == 0 then
        local liveClasses = detectClasses(false)
        if liveClasses then myClasses = liveClasses end
    end
    ctrl.running = false -- never auto-start on load
end

runtime.loadAll()
if ctrl.fov_enabled and runtime.applyFov then
    runtime.applyFov()
end

-- Memorize a spell into a specific gem slot, with verification + a clear reason on
-- failure. /memspell only works on spells that are SCRIBED in your book; the gem
-- planner lists the whole class pool, so a picked spell may not be scribed yet.
-- This server runs the MQ Fast-Mem Detector (Cheat:EnableMQFastMemDetector), so the
-- instant /memspell is rejected. Memorize the legit way instead: open the spellbook,
-- page to the spell, pick it up, drop it on the target gem, and let the mem gauge run
-- its full time -- exactly how a person does it. Mirrors autocombat's Simulated Mem.
-- tryMem is defined in local helpers above

-- ============================================================================
-- UI
-- ============================================================================
local UI = {}

function UI.accent(c, txt) ImGui.TextColored(c[1], c[2], c[3], c[4], txt) end
local accent = UI.accent
function UI.setTooltip(fmt, ...)
    if fmt ~= nil then
        if select('#', ...) > 0 then
            ImGui.SetTooltip('%s', string.format(tostring(fmt), ...))
        else
            ImGui.SetTooltip('%s', tostring(fmt))
        end
    end
end

-- UI: theme and style helpers
function UI.pushTheme()
    local cCount, vCount = 0, 0
    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
    local SV = ImGuiStyleVar or _G.ImGuiStyleVar or (mq.imgui and mq.imgui.StyleVar)
    local function pCol(id, r, g, b, a)
        if id ~= nil and pcall(ImGui.PushStyleColor, id, r, g, b, a) then
            cCount = cCount + 1
        end
    end
    local function pVar(id, a, b)
        if id == nil then return end
        local ok
        if b ~= nil then
            local ImVec2Type = _G.ImVec2 or ImVec2
            if type(ImVec2Type) == 'function' then
                ok = pcall(ImGui.PushStyleVar, id, ImVec2Type(a, b))
            else
                ok = pcall(ImGui.PushStyleVar, id, a, b)
            end
        else
            ok = pcall(ImGui.PushStyleVar, id, a)
        end
        if ok then vCount = vCount + 1 end
    end

    if Col then
        pCol(Col.WindowBg, 0.059, 0.086, 0.133, 1)
        pCol(Col.ChildBg, 0.055, 0.082, 0.125, 1)
        pCol(Col.PopupBg, 0.047, 0.075, 0.118, 1)
        pCol(Col.Border, 0.157, 0.251, 0.345, 1)
        pCol(Col.Text, 0.851, 0.898, 0.953, 1)
        pCol(Col.TextDisabled, 0.490, 0.561, 0.651, 1)
        pCol(Col.TitleBg, 0.043, 0.067, 0.106, 1)
        pCol(Col.TitleBgActive, 0.047, 0.078, 0.125, 1)
        pCol(Col.FrameBg, 0.047, 0.078, 0.125, 1)
        pCol(Col.FrameBgHovered, 0.090, 0.150, 0.220, 1)
        pCol(Col.FrameBgActive, 0.120, 0.190, 0.270, 1)
        pCol(Col.Button, 0.086, 0.125, 0.196, 1)
        pCol(Col.ButtonHovered, 0.300, 0.700, 1.000, 0.35)
        pCol(Col.ButtonActive, 0.300, 0.700, 1.000, 0.60)
        pCol(Col.Header, 0.078, 0.129, 0.204, 1)
        pCol(Col.HeaderHovered, 0.160, 0.440, 0.700, 0.50)
        pCol(Col.HeaderActive, 0.160, 0.500, 0.750, 0.70)
        pCol(Col.Tab, 0.043, 0.067, 0.098, 1)
        pCol(Col.TabHovered, 0.300, 0.700, 1.000, 0.40)
        pCol(Col.TabSelected, 0.075, 0.125, 0.200, 1)
        pCol(Col.CheckMark, 0.370, 0.880, 0.640, 1)
        pCol(Col.SliderGrab, 1.000, 0.700, 0.540, 1)
        pCol(Col.SliderGrabActive, 1.000, 0.550, 0.300, 1)
        pCol(Col.Separator, 0.157, 0.251, 0.345, 1)
        pCol(Col.ScrollbarBg, 0.031, 0.051, 0.078, 1)
        pCol(Col.ScrollbarGrab, 0.157, 0.251, 0.345, 1)
    end
    if SV then
        pVar(SV.WindowRounding, 6)
        pVar(SV.ChildRounding, 5)
        pVar(SV.FrameRounding, 4)
        pVar(SV.PopupRounding, 4)
        pVar(SV.TabRounding, 4)
        pVar(SV.GrabRounding, 3)
        pVar(SV.ScrollbarRounding, 6)

        pVar(SV.FrameBorderSize, 1)
        pVar(SV.FramePadding, 7, 4)
        pVar(SV.ItemSpacing, 8, 6)
        pVar(SV.WindowPadding, 12, 10)
    end

    runtime.themeColStack = runtime.themeColStack or {}
    runtime.themeVarStack = runtime.themeVarStack or {}
    table.insert(runtime.themeColStack, cCount)
    table.insert(runtime.themeVarStack, vCount)
    runtime.colN = cCount
    runtime.varN = vCount
    return cCount, vCount
end

function UI.popTheme()
    local cCnt, vCnt
    if runtime.themeColStack and #runtime.themeColStack > 0 then
        cCnt = table.remove(runtime.themeColStack)
    else
        cCnt = runtime.colN or 0
    end
    if runtime.themeVarStack and #runtime.themeVarStack > 0 then
        vCnt = table.remove(runtime.themeVarStack)
    else
        vCnt = runtime.varN or 0
    end
    if (vCnt or 0) > 0 then pcall(ImGui.PopStyleVar, vCnt) end
    if (cCnt or 0) > 0 then pcall(ImGui.PopStyleColor, cCnt) end
    runtime.colN = 0
    runtime.varN = 0
end

function UI.pushDisabledSliderStyle()
    local pCount = 0
    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
    if not Col then return 0 end
    if pcall(ImGui.PushStyleColor, Col.FrameBg, 0.45, 0.08, 0.08, 1.0) then pCount = pCount + 1 end
    if pcall(ImGui.PushStyleColor, Col.FrameBgHovered, 0.55, 0.12, 0.12, 1.0) then pCount = pCount + 1 end
    if pcall(ImGui.PushStyleColor, Col.FrameBgActive, 0.65, 0.15, 0.15, 1.0) then pCount = pCount + 1 end
    if pcall(ImGui.PushStyleColor, Col.SliderGrab, 0.75, 0.25, 0.25, 1.0) then pCount = pCount + 1 end
    if pcall(ImGui.PushStyleColor, Col.SliderGrabActive, 0.85, 0.30, 0.30, 1.0) then pCount = pCount + 1 end
    if pcall(ImGui.PushStyleColor, Col.Text, 1.0, 0.85, 0.85, 1.0) then pCount = pCount + 1 end
    return pCount
end

function UI.popDisabledSliderStyle(pCount)
    if pCount and pCount > 0 then
        pcall(ImGui.PopStyleColor, pCount)
    end
end

-- ============================================================================
-- Triune Modular Plugin Engine (lua/tac/*.lua)
-- ============================================================================

-- True while a plugin holds the combat loop (see pm.combatHold).
function runtime.combatHold()
    local pm = runtime.pluginManager
    return pm ~= nil and pm.combatHold() == true
end

function runtime.initPluginManager()
    if runtime.pluginManager then return end

    local pm = {
        plugins = {},
        pluginOrder = {},
        dirPath = nil,
        lastScanAt = 0,
    }
    runtime.pluginManager = pm

    function pm.getPluginDir()
        if pm.dirPath then return pm.dirPath end
        local rawCandidates = {}

        if mq and mq.luaDir then
            local l = tostring(mq.luaDir):gsub('[/\\]+$', '')
            table.insert(rawCandidates, l .. '/tac')
            table.insert(rawCandidates, l .. '/TAC')
            table.insert(rawCandidates, l .. '/../TAC/lua/tac')
            table.insert(rawCandidates, l .. '/../lua/tac')
        end

        if scriptDir then
            local s = tostring(scriptDir):gsub('[/\\]+$', '')
            table.insert(rawCandidates, s .. '/tac')
            table.insert(rawCandidates, s .. '/TAC')
            table.insert(rawCandidates, s .. '/../lua/tac')
            table.insert(rawCandidates, s .. '/../TAC/lua/tac')
        end

        table.insert(rawCandidates, 'lua/tac')
        table.insert(rawCandidates, 'lua/TAC')
        table.insert(rawCandidates, 'TAC/lua/tac')
        table.insert(rawCandidates, './tac')
        table.insert(rawCandidates, './TAC')
        table.insert(rawCandidates, 'tac')
        table.insert(rawCandidates, 'TAC')

        local candidates = {}
        local seenCand = {}
        for _, c in ipairs(rawCandidates) do
            local norm = c:gsub('\\', '/'):lower()
            if not seenCand[norm] then
                seenCand[norm] = true
                table.insert(candidates, c)
            end
        end

        local okLfs, lfs = pcall(require, 'lfs')
        if okLfs and lfs and lfs.attributes then
            for _, d in ipairs(candidates) do
                local mode = nil
                pcall(function() mode = lfs.attributes(d, 'mode') end)
                if mode == 'directory' then
                    pm.dirPath = d
                    return d
                end
            end
        end

        local probeFiles = { 'hud_unitframes.lua', 'auto_accept.lua', 'floating_damage.lua' }
        for _, d in ipairs(candidates) do
            for _, pf in ipairs(probeFiles) do
                local f = io.open(d .. '/' .. pf, 'r')
                if f then
                    f:close()
                    pm.dirPath = d
                    return d
                end
            end
        end

        pm.dirPath = (scriptDir and (scriptDir .. 'tac')) or 'lua/tac'
        return pm.dirPath
    end

    -- One shared core API table for every plugin. `ctrl` / `loadout` and the
    -- other mutable core tables are resolved live through __index because
    -- runtime.onCharacterChanged() replaces them wholesale; a snapshot taken at
    -- init would leave plugins reading (and writing) a dead config table.
    function pm.getCoreApi()
        if pm.coreApi then return pm.coreApi end
        local live = {
            ctrl       = function() return ctrl end,
            loadout    = function() return loadout end,
            petState   = function() return petState end,
            pursuit    = function() return pursuit end,
            stuckState = function() return stuckState end,
            myClasses  = function() return myClasses end,
            castTracker = function() return castTracker end,
        }
        local api = {
            VERSION               = VERSION,
            mq                    = mq,
            ImGui                 = ImGui,
            runtime               = runtime,
            DATA                  = DATA,
            saveLoadout           = runtime.saveLoadout,
            colors                = { GOLD = GOLD, ARC = ARC, MUTED = MUTED, GOOD = GOOD, WARN = WARN, ERR = ERR },
            pushTheme             = UI.pushTheme,
            popTheme              = UI.popTheme,
            accent                = UI.accent,
            setTooltip            = UI.setTooltip,
            preBeginWindow        = UI.preBeginWindow,
            postBeginWindow       = UI.postBeginWindow,
            drawStatusProgressBar = UI.drawStatusProgressBar,
            drawSpellIcon         = UI.drawSpellIcon,
            getConColorRgb        = UI.getConColorRgb,
            resolveTargetOfTarget = UI.resolveTargetOfTarget,
            getMultiPetList       = runtime.getMultiPetList or getMultiPetList,
            getPetSpawnInfo       = runtime.getPetSpawnInfo or getPetSpawnInfo,
            isSpawnAlive          = runtime.isSpawnAlive or isSpawnAlive,
            addIgnore             = runtime.addIgnore,
            parseDurationSec      = parseDurationSec,
            parseSpellRecastTime  = parseSpellRecastTime,
            parseCombatAbilityTimer = parseCombatAbilityTimer,
            getAbilityBaseCooldown = getAbilityBaseCooldown,
            getDiscCooldownAndDuration = getDiscCooldownAndDuration,
            getNumGems            = getNumGems,
            classColor            = classColor,
            cleanSpellName        = cleanSpellName,
            normalizeSpellName    = normalizeSpellName,
            requestClassRedetect  = function() reDetectRequested = true end,
            fmtSec                = fmtSec,
            idxOf                 = idxOf,
            col32                 = UI.col32,
            toVec                 = UI.toVec,
            toggleTool            = UI.toggleTool,
            getSpellIconAnimation = UI.getSpellIconAnimation,
            getGemCooldownSec     = UI.getGemCooldownSec,
            drawSpellbookIcon     = UI.drawSpellbookIcon,
            delay                 = function(ms, cond) return pm.delay(ms, cond) end,
        }
        setmetatable(api, {
            __index = function(_, k)
                local getter = live[k]
                if getter then return getter() end
                return nil
            end,
        })
        pm.coreApi = api
        return api
    end

    -- Cooperative stand-in for mq.delay inside a plugin fiber. Yields the fiber
    -- back to the main loop every tick until `ms` has elapsed or `cond()` is
    -- true, so a sequential plugin workflow (buff casting, bag moves) can wait
    -- without ever stalling the combat loop. Outside a fiber it degrades to
    -- mq.delay on the main coroutine. Returns true when the condition fired.
    pm.inFiber = false
    function pm.delay(ms, cond)
        ms = tonumber(ms) or 0
        if not pm.inFiber then
            if mq and mq.delay then mq.delay(ms, cond) end
            if cond then
                local ok, res = pcall(cond)
                return ok and res == true
            end
            return false
        end
        local deadline = os.clock() + ms / 1000
        while true do
            if cond then
                local ok, res = pcall(cond)
                if ok and res then return true end
            end
            if os.clock() >= deadline then return false end
            coroutine.yield()
        end
    end

    -- Every plugin fiber is the same loop: run onTick, yield, repeat while enabled.
    function pm.createFiber(p)
        return coroutine.create(function()
            while p.enabled do
                if p.instance.onTick then
                    local ok, err = pcall(p.instance.onTick)
                    if not ok then
                        p.status = 'Error'
                        p.errorMsg = 'fiber: ' .. tostring(err)
                        print(string.format('\ar[Triune Plugin Error]\ax %s fiber crashed: %s', p.name, tostring(err)))
                        break
                    end
                end
                coroutine.yield()
            end
        end)
    end

    -- Files in the plugin folder that could not be loaded, keyed by filename:
    -- { msg = ..., fullPath = ..., at = os.clock() }. Shown on the Plugins page
    -- so a bad drop-in is visible there, not only as one chat line.
    pm.loadErrors = {}

    local PLUGIN_HOOKS = {
        'onInit', 'onDestroy', 'onTick', 'onDrawUI', 'onDrawSettings', 'onCombatTick', 'onZoned',
        'onLoadoutSaved', 'onSaveSettings', 'onLoadSettings', 'wantsCombatHold', 'onBetweenPulls', 'onCommand',
    }

    -- Executing a dropped-in file runs its main chunk on the core's main
    -- coroutine. A standalone MQ script would start its own mq.delay loop
    -- there (hanging Triune), or register ImGui callbacks / binds / events
    -- that nothing ever cleans up. While a plugin file's chunk runs, those
    -- entry points raise instead, so the file fails to load with a clear
    -- message and no side effects. Real plugins do all of this in onInit.
    local function runPluginChunk(fn, filename)
        local guards = {
            { tbl = mq, key = 'delay',    why = 'mq.delay (a plugin must not block at load; use onTick / core.delay)' },
            { tbl = mq, key = 'doevents', why = 'mq.doevents (the core pumps events)' },
            { tbl = mq, key = 'bind',     why = 'mq.bind at load (register binds in onInit, release them in onDestroy)' },
            { tbl = mq, key = 'event',    why = 'mq.event at load (register events in onInit, release them in onDestroy)' },
            { tbl = mq, key = 'exit',     why = 'mq.exit (a plugin runs inside Triune and cannot exit the script)' },
            { tbl = mq and mq.imgui, key = 'init', why = 'mq.imgui.init (draw from onDrawUI instead)' },
        }
        local saved = {}
        for i, g in ipairs(guards) do
            if type(g.tbl) == 'table' then
                saved[i] = g.tbl[g.key]
                g.tbl[g.key] = function()
                    error(string.format('%s is a standalone script, not a Triune plugin: it called %s while loading', filename, g.why), 2)
                end
            end
        end
        local ok, res = pcall(fn)
        for i, g in ipairs(guards) do
            if type(g.tbl) == 'table' then g.tbl[g.key] = saved[i] end
        end
        return ok, res
    end

    local function looksLikePlugin(inst)
        if type(inst) ~= 'table' then return false end
        if type(inst.id) == 'string' and inst.id ~= '' then return true end
        for _, h in ipairs(PLUGIN_HOOKS) do
            if type(inst[h]) == 'function' then return true end
        end
        return false
    end

    local function loadFailed(filename, fullPath, msg)
        print(string.format('\ar[Triune Plugin Error]\ax %s: %s', filename, tostring(msg)))
        pm.loadErrors[filename] = { msg = tostring(msg), fullPath = fullPath, at = os.clock() }
        pm.scripts[filename] = nil
        return false, tostring(msg)
    end

    -- Files that load fine but are not plugins (standalone MQ scripts, data
    -- files, anything without the plugin contract). They get a basic entry on
    -- the Plugins page with Run / Stop buttons that launch them through
    -- `/lua run`, completely independent of Triune's plugin lifecycle.
    pm.scripts = {}

    -- The name `/lua run` needs for a file inside the plugin folder: relative
    -- to the MQ lua directory when the folder lives under it (e.g. `tac/foo`),
    -- otherwise the folder's last path segment plus the file (`tac/foo`).
    function pm.scriptRunName(fullPath)
        local path = tostring(fullPath or ''):gsub('\\', '/'):gsub('%.lua$', '')
        local luaDir = mq and mq.luaDir and tostring(mq.luaDir):gsub('\\', '/'):gsub('/+$', '') or nil
        if luaDir and luaDir ~= '' and path:sub(1, #luaDir + 1):lower() == (luaDir .. '/'):lower() then
            return path:sub(#luaDir + 2)
        end
        local folder, file = path:match('([^/]+)/([^/]+)$')
        if folder and file then return folder .. '/' .. file end
        return path:match('([^/]+)$') or path
    end

    local function registerScript(filename, fullPath, reason)
        local runName = pm.scriptRunName(fullPath)
        pm.scripts[filename] = {
            name = (tostring(filename):gsub('%.lua$', '')),
            file = filename,
            fullPath = fullPath,
            runName = runName,
            reason = tostring(reason),
            at = os.clock(),
        }
        pm.loadErrors[filename] = nil
        print(string.format('\ay[Triune]\ax %s is not a Triune plugin (%s). Listed under Settings -> Plugins -> Standalone Scripts; run it with /lua run %s.',
            filename, tostring(reason), runName))
        return false, tostring(reason)
    end

    function pm.isScriptRunning(entry)
        if not entry then return false end
        local running = false
        pcall(function()
            local s = mq.TLO.Lua.Script(entry.runName)
            running = (s() and s.Status() == 'RUNNING') == true
        end)
        return running
    end

    -- Run or stop a standalone script (`/lua run` / `/lua stop`). Returns
    -- 'started' or 'stopped'.
    function pm.toggleScript(entry)
        if not entry then return nil end
        if pm.isScriptRunning(entry) then
            mq.cmd('/lua stop ' .. entry.runName)
            return 'stopped'
        end
        mq.cmd('/lua run ' .. entry.runName)
        return 'started'
    end

    function pm.loadPlugin(filename, fullPath)
        local fn, err = loadfile(fullPath)
        if not fn then
            return loadFailed(filename, fullPath, 'Syntax error: ' .. tostring(err))
        end

        local ok, inst = runPluginChunk(fn, filename)
        if not ok then
            local msg = tostring(inst)
            if msg:find('standalone script, not a Triune plugin', 1, true) then
                return registerScript(filename, fullPath, 'standalone script: ' .. (msg:match('it called (.-) while loading') or 'uses MQ script entry points at load'))
            end
            return loadFailed(filename, fullPath, 'Execution error: ' .. msg)
        end
        if type(inst) ~= 'table' then
            return registerScript(filename, fullPath, string.format('returns %s instead of a plugin table', type(inst)))
        end
        if not looksLikePlugin(inst) then
            return registerScript(filename, fullPath, 'returned table has no `id` and none of the plugin hooks')
        end

        local id = inst.id or filename:gsub('%.lua$', '')
        local existing = pm.plugins[id]
        if existing and existing.filename and existing.filename:lower() ~= tostring(filename):lower() then
            return loadFailed(filename, fullPath, string.format('Plugin id "%s" is already registered by %s; rename the id in this file', id, existing.filename))
        end
        pm.loadErrors[filename] = nil
        pm.scripts[filename] = nil

        local p = existing or {
            id = id,
            lastExecMs = 0,
            avgExecMs = 0,
            lastTickAt = 0,
            showSettings = false,
        }

        p.filename = filename
        p.fullPath = fullPath
        p.name = inst.name or id
        p.version = inst.version or '1.0.0'
        p.author = inst.author or 'Unknown'
        p.description = inst.description or ''
        p.tickInterval = tonumber(inst.tickInterval) or 0.1
        if not ctrl.plugins then ctrl.plugins = {} end
        local savedCfg = ctrl.plugins[id]
        if savedCfg and savedCfg.runInCombat ~= nil then
            p.runOutOfCombatOnly = not savedCfg.runInCombat
        else
            p.runOutOfCombatOnly = (inst.runOutOfCombatOnly == true)
        end
        p.hasThread = (inst.hasThread == true)
        p.instance = inst
        p.status = 'Disabled'
        p.errorMsg = nil

        if not existing then
            pm.plugins[id] = p
            table.insert(pm.pluginOrder, id)
        end

        local shouldEnable
        if savedCfg and savedCfg.enabled ~= nil then
            shouldEnable = savedCfg.enabled
        else
            shouldEnable = (inst.defaultEnabled ~= false)
        end

        if shouldEnable then
            pm.enablePlugin(id)
        else
            p.enabled = false
            p.status = 'Disabled'
        end

        return true
    end

    function pm.enablePlugin(id)
        local p = pm.plugins[id]
        if not p then return end

        p.enabled = true
        p.status = 'Active'
        p.errorMsg = nil
        if not ctrl.plugins then ctrl.plugins = {} end
        if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
        ctrl.plugins[id].enabled = true

        local coreApi = pm.getCoreApi()
        if p.instance.onInit then
            local ok, err = pcall(p.instance.onInit, coreApi)
            if not ok then
                p.status = 'Error'
                p.errorMsg = 'onInit: ' .. tostring(err)
                print(string.format('\ar[Triune Plugin Error]\ax %s onInit failed: %s', p.name, tostring(err)))
                return
            end
        end

        if p.instance.onLoadSettings and ctrl.plugins[id].settings then
            pcall(p.instance.onLoadSettings, ctrl.plugins[id].settings)
        end

        if p.hasThread then
            p.thread = pm.createFiber(p)
        end
    end

    function pm.disablePlugin(id)
        local p = pm.plugins[id]
        if not p then return end

        p.enabled = false
        p.status = 'Disabled'
        p.thread = nil
        if not ctrl.plugins then ctrl.plugins = {} end
        if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
        ctrl.plugins[id].enabled = false

        if p.instance.onDestroy then
            pcall(p.instance.onDestroy)
        end
    end

    function pm.reloadPlugin(id)
        local p = pm.plugins[id]
        if not p then return end
        local fullPath = p.fullPath
        local filename = p.filename
        local wasEnabled = p.enabled
        if p.enabled then
            pm.disablePlugin(id)
        end
        -- disablePlugin persisted enabled=false; restore the user's real choice so
        -- loadPlugin re-enables a plugin that was running before the reload.
        if wasEnabled and ctrl.plugins and ctrl.plugins[id] then
            ctrl.plugins[id].enabled = true
        end
        pm.loadPlugin(filename, fullPath)
    end

    function pm.reloadAll()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled then
                pm.disablePlugin(id)
            end
        end
        pm.plugins = {}
        pm.pluginOrder = {}
        pm.loadErrors = {}
        pm.scripts = {}
        pm.discover()
    end

    -- Re-run every plugin's lifecycle against the *current* ctrl without touching
    -- disk. Called after a character swap so each plugin re-seeds its defaults on
    -- the new config table and re-reads its enabled / combat flags from it.
    function pm.restartAll()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                -- Read the new character's saved flags before disablePlugin writes
                -- enabled=false into ctrl.plugins[id].
                local savedCfg = ctrl.plugins and ctrl.plugins[id]
                local savedEnabled = savedCfg and savedCfg.enabled
                local savedRunInCombat = savedCfg and savedCfg.runInCombat
                if p.enabled then pm.disablePlugin(id) end
                if savedRunInCombat ~= nil then
                    p.runOutOfCombatOnly = not savedRunInCombat
                else
                    p.runOutOfCombatOnly = (p.instance.runOutOfCombatOnly == true)
                end
                local shouldEnable
                if savedEnabled ~= nil then
                    shouldEnable = savedEnabled
                else
                    shouldEnable = (p.instance.defaultEnabled ~= false)
                end
                if shouldEnable then
                    pm.enablePlugin(id)
                else
                    if not ctrl.plugins then ctrl.plugins = {} end
                    if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
                    ctrl.plugins[id].enabled = false
                    ctrl.plugins[id].runInCombat = not p.runOutOfCombatOnly
                end
            end
        end
    end

    -- Scan the plugin folder and load any file not already registered. Files that
    -- are already loaded are left alone (use reloadPlugin / reloadAll for those) so
    -- a rescan never re-runs onInit on a live instance without onDestroy.
    function pm.discover()
        local dir = pm.getPluginDir()
        if not dir then return end
        local files = {}
        local fileSet = {}
        local loadedFiles = {}
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.filename then loadedFiles[p.filename:lower()] = true end
        end
        -- Known standalone scripts are not re-executed on a rescan (their
        -- chunk may have side effects); "Re-check" on the Plugins page does that.
        for fname in pairs(pm.scripts or {}) do loadedFiles[tostring(fname):lower()] = true end

        local function addFile(fname)
            if fname and fname:match('%.lua$') then
                local low = fname:lower()
                if not fileSet[low] and not loadedFiles[low] then
                    fileSet[low] = true
                    table.insert(files, fname)
                end
            end
        end

        -- Method 1: LuaFileSystem (lfs)
        local okLfs, lfs = pcall(require, 'lfs')
        if okLfs and lfs and lfs.dir then
            pcall(function()
                for f in lfs.dir(dir) do
                    addFile(f)
                end
            end)
        end

        -- Method 2: OS popen directory query (dynamically finds custom dropped plugins)
        pcall(function()
            local isWin = (package.config and package.config:sub(1, 1) == '\\')
            local cmd
            local dirStr = tostring(dir or '')
            if isWin then
                local winDir = dirStr:gsub('/', '\\')
                cmd = string.format('dir /b "%s\\*.lua" 2>nul', winDir)
            else
                cmd = string.format('ls -1 "%s"/*.lua 2>/dev/null', dirStr)
            end
            local p = io.popen(cmd)
            if p then
                for line in p:lines() do
                    local fname = line:match('([^\\/]+%.lua)$') or line:match('^%s*(.-%.lua)%s*$')
                    addFile(fname)
                end
                p:close()
            end
        end)

        -- Method 3: Core known plugins direct probe fallback
        local known = {
            'hud_unitframes.lua',
            'auto_accept.lua',
            'floating_damage.lua',
            'hud_group.lua',
            'hud_effects.lua',
            'hud_xtarget.lua',
            'hud_cooldowns.lua',
            'hud_spellgems.lua',
            'auto_aa.lua',
            'spellbook.lua',
            'cursor.lua',
            'dps.lua',
            'inventory.lua',
            'buffbot.lua',
            'map.lua',
            'boxnet.lua',
            'buttons.lua',
        }
        for _, f in ipairs(known) do
            if not fileSet[f:lower()] then
                local fp = dir .. '/' .. f
                local testF = io.open(fp, 'r')
                if testF then
                    testF:close()
                    addFile(f)
                end
            end
        end

        table.sort(files)
        for _, f in ipairs(files) do
            local fullPath = dir .. '/' .. f
            pm.loadPlugin(f, fullPath)
        end

        pm.lastScanAt = os.clock()
    end

    -- Plugin lifecycle work requested from the UI (Rescan, Reload, Retry,
    -- Re-check, Enable / Disable) is queued here and run from pm.tick() on the
    -- main script coroutine. Running a dropped-in file's chunk or a plugin's
    -- onInit / onDestroy inside the ImGui render callback crashed mq2lua
    -- (the chunk or hook can register ImGui callbacks, bind commands, or call
    -- mq.exit while the frame is being rendered), so the render thread only
    -- ever enqueues.
    pm.deferred = {}
    function pm.defer(label, fn)
        pm.deferred[#pm.deferred + 1] = { label = tostring(label or 'plugin op'), fn = fn }
    end

    function pm.hasDeferred()
        return #pm.deferred > 0
    end

    function pm.runDeferred()
        if #pm.deferred == 0 then return 0 end
        local ops = pm.deferred
        pm.deferred = {}
        for _, op in ipairs(ops) do
            local ok, err = pcall(op.fn)
            if not ok then
                print(string.format('\ar[Triune Plugin Error]\ax %s failed: %s', op.label, tostring(err)))
            end
        end
        return #ops
    end

    function pm.tick()
        pm.runDeferred()
        local inCombat = false
        pcall(function()
            inCombat = (mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT'))
        end)

        local now = os.clock()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' then
                if inCombat and p.runOutOfCombatOnly then
                    p.status = 'Sleeping (Combat)'
                else
                    p.status = 'Active'
                    if (now - p.lastTickAt) >= p.tickInterval then
                        p.lastTickAt = now
                        local t0 = os.clock()

                        if p.hasThread and p.thread then
                            if coroutine.status(p.thread) == 'dead' then
                                p.thread = pm.createFiber(p)
                            end
                            pm.inFiber = true
                            local ok, err = coroutine.resume(p.thread)
                            pm.inFiber = false
                            if not ok then
                                p.status = 'Error'
                                p.errorMsg = 'resume: ' .. tostring(err)
                                print(string.format('\ar[Triune Plugin Error]\ax %s fiber crashed: %s', p.name, tostring(err)))
                            end
                        elseif p.instance.onTick then
                            local ok, err = pcall(p.instance.onTick)
                            if not ok then
                                p.status = 'Error'
                                p.errorMsg = 'tick: ' .. tostring(err)
                                print(string.format('\ar[Triune Plugin Error]\ax %s onTick error: %s', p.name, tostring(err)))
                            end
                        end

                        local elapsedMs = (os.clock() - t0) * 1000
                        p.lastExecMs = elapsedMs
                        p.avgExecMs = p.avgExecMs and (p.avgExecMs * 0.9 + elapsedMs * 0.1) or elapsedMs
                    end
                end
            end
        end
    end

    -- Render hook. A draw error is fatal for that plugin: an exception between
    -- ImGui.Begin and ImGui.End leaves the ImGui stack unbalanced, so we flag the
    -- plugin as Error (which stops drawing it) rather than retrying every frame.
    function pm.drawUI()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' and p.instance.onDrawUI then
                local ok, err = pcall(p.instance.onDrawUI)
                if not ok then
                    p.status = 'Error'
                    p.errorMsg = 'onDrawUI: ' .. tostring(err)
                    print(string.format('\ar[Triune Plugin Error]\ax %s onDrawUI failed: %s', p.name, tostring(err)))
                end
            end
        end
    end

    -- Draws one plugin's settings panel inline. Lets a core Settings sub-tab keep
    -- its familiar place in the UI while the plugin owns the actual controls.
    function pm.drawPluginSettings(id)
        local p = pm.plugins[id]
        if not p then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4],
                string.format('Plugin "%s" is not loaded. Drop %s.lua into %s and click Rescan on the Plugins tab.',
                    id, id, tostring(pm.dirPath or 'lua/tac')))
            return false
        end
        if p.status == 'Error' then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('%s plugin hit an error: %s', p.name, tostring(p.errorMsg or '?')))
            if ImGui.SmallButton('Reload Plugin##reload_' .. id) then
                pm.defer('reload ' .. id, function() pm.reloadPlugin(id) end)
            end
            return false
        end
        if not p.enabled then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('%s plugin is disabled.', p.name))
            ImGui.SameLine()
            if ImGui.SmallButton('Enable##enable_' .. id) then
                pm.defer('enable ' .. id, function()
                    pm.enablePlugin(id)
                    runtime.saveLoadout(true)
                end)
            end
            return false
        end
        if not p.instance.onDrawSettings then
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'This plugin has no configurable settings.')
            return true
        end
        local ok, err = pcall(p.instance.onDrawSettings)
        if not ok then
            p.status = 'Error'
            p.errorMsg = 'onDrawSettings: ' .. tostring(err)
            print(string.format('\ar[Triune Plugin Error]\ax %s onDrawSettings failed: %s', p.name, tostring(err)))
            return false
        end
        return true
    end

    -- Runs a hook on every active plugin that defines it; a hook error flags the
    -- plugin. `firstTrue` stops at (and returns) the first truthy result.
    local function dispatch(hookName, firstTrue, ...)
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' and p.instance[hookName] then
                local ok, res = pcall(p.instance[hookName], ...)
                if not ok then
                    p.status = 'Error'
                    p.errorMsg = hookName .. ': ' .. tostring(res)
                    print(string.format('\ar[Triune Plugin Error]\ax %s %s failed: %s', p.name, hookName, tostring(res)))
                elseif firstTrue and res then
                    return res
                end
            end
        end
        return false
    end

    -- Per-combat-tick and zone-change notifications.
    function pm.onCombatTick(targetId) dispatch('onCombatTick', false, targetId) end
    function pm.onZoned(curZone) dispatch('onZoned', false, curZone) end

    -- True while any plugin asks the combat loop to stand still (e.g. an AA
    -- purchase workflow with the AA window open).
    function pm.combatHold() return dispatch('wantsCombatHold', true) == true end

    -- Puller idle gap between pulls. A plugin returns true if it started
    -- something that needs the puller to yield this tick.
    function pm.onBetweenPulls() return dispatch('onBetweenPulls', true) == true end

    -- /ac <cmd> fallthrough. A plugin returns true if it handled the command.
    function pm.onCommand(cmd, args) return dispatch('onCommand', true, cmd, args) == true end

    -- Help lines contributed by plugins (plugin.help = { 'line', ... })
    function pm.helpLines()
        local out = {}
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and type(p.instance.help) == 'table' then
                for _, hl in ipairs(p.instance.help) do out[#out + 1] = hl end
            end
        end
        return out
    end

    -- Fired after the loadout file has been written.
    function pm.onLoadoutSaved() dispatch('onLoadoutSaved', false) end

    -- ------------------------------------------------------------------
    -- Plugin windows. A plugin that owns a toggleable window declares
    --   plugin.window = { label = 'Map', tooltip = '...', flag = 'show_map',
    --                     headerButton = true, order = 20 }
    -- `flag` names the ctrl.* boolean that drives visibility (saved with the
    -- loadout); a plugin may supply isOpen() / setOpen(bool) instead. The
    -- Plugins page lets the user pick which of these get a toggle button on
    -- the main window header (ctrl.plugins[id].headerButton, defaulting to
    -- window.headerButton ~= false).
    -- ------------------------------------------------------------------
    function pm.getWindow(id)
        local p = pm.plugins[id]
        local w = p and p.instance and p.instance.window
        if type(w) ~= 'table' then return nil end
        if type(w.flag) ~= 'string' and type(w.isOpen) ~= 'function' then return nil end
        return w
    end

    function pm.isWindowOpen(id)
        local w = pm.getWindow(id)
        if not w then return false end
        if type(w.isOpen) == 'function' then
            local ok, res = pcall(w.isOpen)
            return ok and res == true
        end
        return ctrl[w.flag] == true
    end

    function pm.setWindowOpen(id, val)
        local w = pm.getWindow(id)
        if not w then return false end
        val = (val == true)
        if type(w.setOpen) == 'function' then
            pcall(w.setOpen, val)
        else
            ctrl[w.flag] = val
        end
        runtime.saveLoadout(true)
        return true
    end

    function pm.toggleWindow(id)
        return pm.setWindowOpen(id, not pm.isWindowOpen(id))
    end

    function pm.headerButtonEnabled(id)
        local w = pm.getWindow(id)
        if not w then return false end
        local saved = ctrl.plugins and ctrl.plugins[id] and ctrl.plugins[id].headerButton
        if saved ~= nil then return saved == true end
        return w.headerButton ~= false
    end

    function pm.setHeaderButton(id, val)
        if not ctrl.plugins then ctrl.plugins = {} end
        if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
        ctrl.plugins[id].headerButton = (val == true)
        runtime.saveLoadout(true)
    end

    -- Active plugins with a window, in header order (window.order, then load order).
    function pm.windowPlugins(headerOnly)
        local out = {}
        for i, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            local w = pm.getWindow(id)
            if p and w and p.enabled and p.status ~= 'Error' and (not headerOnly or pm.headerButtonEnabled(id)) then
                out[#out + 1] = { id = id, window = w, order = tonumber(w.order) or 100, idx = i }
            end
        end
        table.sort(out, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.idx < b.idx
        end)
        return out
    end

    -- Main-window header toggle buttons for plugin windows. Open windows are
    -- highlighted. Rows hold at most HEADER_BUTTONS_PER_ROW buttons (the
    -- caller passes how many it already drew on the current row, e.g. the
    -- Compact Mode button) and also wrap early when the header runs out of
    -- width. Returns the number of buttons drawn.
    pm.HEADER_BUTTONS_PER_ROW = 8
    function pm.drawHeaderButtons(buttonsOnRow)
        local entries = pm.windowPlugins(true)
        if #entries == 0 then return 0 end
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local perRow = tonumber(pm.HEADER_BUTTONS_PER_ROW) or 8
        local col = tonumber(buttonsOnRow) or 0
        local winW = 0
        pcall(function()
            local w = ImGui.GetWindowContentRegionMax and ImGui.GetWindowContentRegionMax()
            if type(w) == 'number' then winW = w elseif type(w) == 'table' or type(w) == 'userdata' then winW = w.x or 0 end
        end)
        local drawn = 0
        for _, e in ipairs(entries) do
            local label = tostring(e.window.label or e.id)
            if col > 0 then
                if col >= perRow then
                    -- Row is full: the next button starts a new row.
                    col = 0
                else
                    ImGui.SameLine()
                    if winW > 0 then
                        local okW, textW = pcall(function()
                            local tw = ImGui.CalcTextSize(label)
                            if type(tw) ~= 'number' then tw = tw and tw.x or 0 end
                            return tw + 16
                        end)
                        local okX, curX = pcall(ImGui.GetCursorPosX)
                        if okW and okX and type(curX) == 'number' and (curX + (textW or 0)) > winW then
                            ImGui.NewLine()
                            col = 0
                        end
                    end
                end
            end
            local isOpen = pm.isWindowOpen(e.id)
            local pushed = 0
            if isOpen and Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then pushed = 1 end
            if ImGui.Button(label .. '##hdrPlg_' .. e.id) then
                pm.toggleWindow(e.id)
            end
            if pushed > 0 then pcall(ImGui.PopStyleColor, pushed) end
            if ImGui.IsItemHovered() then
                local tip = e.window.tooltip or ('Toggles the ' .. label .. ' window (' .. e.id .. ' plugin).')
                ImGui.SetTooltip('%s', tostring(tip))
            end
            drawn = drawn + 1
            col = col + 1
        end
        return drawn
    end

    function pm.collectSettings()
        if not ctrl.plugins then ctrl.plugins = {} end
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
                ctrl.plugins[id].enabled = (p.enabled == true)
                ctrl.plugins[id].runInCombat = not p.runOutOfCombatOnly
                if pm.getWindow(id) and ctrl.plugins[id].headerButton == nil then
                    ctrl.plugins[id].headerButton = pm.headerButtonEnabled(id)
                end
                if p.instance and p.instance.onSaveSettings then
                    local ok, s = pcall(p.instance.onSaveSettings)
                    if ok and type(s) == 'table' then
                        ctrl.plugins[id].settings = s
                    end
                end
            end
        end
    end

    pm.discover()
end

function UI.drawPluginsTab()
    if not runtime.pluginManager then
        runtime.initPluginManager()
    end
    local pm = runtime.pluginManager
    if not pm then return end

    -- Header Toolbar
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Triune Modular Plugin System')
    ImGui.SameLine()
    local dirStr = pm.dirPath or 'lua/tac'
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('(Folder: %s)', dirStr))

    ImGui.Spacing()
    if ImGui.Button('Rescan Plugins Folder##btnRescanPlugins', 170, 24) then
        pm.defer('rescan plugins folder', pm.discover)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Scans the lua/tac directory for newly dropped or updated .lua plugins.')
    end

    ImGui.SameLine()
    if ImGui.Button('Reload All##btnReloadAllPlugins', 110, 24) then
        pm.defer('reload all plugins', pm.reloadAll)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Restarts and reloads all discovered plugins.')
    end

    local totalLoaded = #pm.pluginOrder
    local activeCount = 0
    for _, id in ipairs(pm.pluginOrder) do
        local p = pm.plugins[id]
        if p and p.enabled and p.status ~= 'Error' then
            activeCount = activeCount + 1
        end
    end

    local failedFiles = {}
    for fname, info in pairs(pm.loadErrors or {}) do
        failedFiles[#failedFiles + 1] = { file = fname, info = info }
    end
    table.sort(failedFiles, function(a, b) return a.file:lower() < b.file:lower() end)

    local scriptFiles = {}
    for fname, entry in pairs(pm.scripts or {}) do
        scriptFiles[#scriptFiles + 1] = entry
        entry.file = entry.file or fname
    end
    table.sort(scriptFiles, function(a, b) return a.name:lower() < b.name:lower() end)

    ImGui.SameLine()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('Loaded: %d | Active: %d', totalLoaded, activeCount))
    if pm.hasDeferred() then
        ImGui.SameLine()
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], '| working...')
    end
    if #scriptFiles > 0 then
        ImGui.SameLine()
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format('| Standalone scripts: %d', #scriptFiles))
    end
    if #failedFiles > 0 then
        ImGui.SameLine()
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('| Failed to load: %d', #failedFiles))
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Files in the plugin folder that are not loadable plugins (syntax errors,
    -- standalone scripts, data files, duplicate ids). They are never registered,
    -- so without this list a bad drop-in would only ever show as one chat line.
    if #failedFiles > 0 then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Files in the plugin folder that could not be loaded:')
        for i, entry in ipairs(failedFiles) do
            ImGui.Bullet()
            ImGui.SameLine()
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], entry.file)
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('Retry##retryPlg_%d', i)) then
                pm.defer('retry ' .. entry.file, function() pm.loadPlugin(entry.file, entry.info.fullPath) end)
            end
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('Dismiss##dismissPlg_%d', i)) then
                pm.loadErrors[entry.file] = nil
            end
            ImGui.Indent(18)
            ImGui.TextWrapped(tostring(entry.info.msg or ''))
            ImGui.Unindent(18)
        end
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Only files that return a plugin table (an `id` or lifecycle hooks) are loaded as plugins; other runnable files are listed under Standalone Scripts.')
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
    end

    -- Standalone scripts dropped into the folder: not plugins, but they get a
    -- basic entry with Run / Stop so they can be launched independently of
    -- Triune (`/lua run <folder>/<name>`).
    if #scriptFiles > 0 then
        accent(GOLD, 'Standalone Scripts (run independently of Triune)')
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'These files do not follow the plugin contract, so Triune does not load them. Run / Stop launches them as their own /lua script.')
        local sFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('TriuneScriptsTable', 4, sFlags) then
            ImGui.TableSetupColumn('Script', ImGuiTableColumnFlags.WidthFixed, 200)
            ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, 90)
            ImGui.TableSetupColumn('Why not a plugin', ImGuiTableColumnFlags.WidthStretch, 0)
            ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableHeadersRow()
            for i, entry in ipairs(scriptFiles) do
                ImGui.TableNextRow()
                local running = pm.isScriptRunning(entry)

                ImGui.TableNextColumn()
                ImGui.Text(entry.name)
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '/lua run ' .. tostring(entry.runName))

                ImGui.TableNextColumn()
                if running then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'RUNNING')
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Stopped')
                end

                ImGui.TableNextColumn()
                ImGui.TextWrapped(tostring(entry.reason or ''))

                ImGui.TableNextColumn()
                if ImGui.SmallButton((running and 'Stop' or 'Run') .. string.format('##scr_%d', i)) then
                    pm.toggleScript(entry)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', running and ('Executes /lua stop ' .. tostring(entry.runName))
                        or ('Executes /lua run ' .. tostring(entry.runName) .. '\nThe script runs as its own MQ Lua process, independent of Triune.'))
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Re-check##scrchk_%d', i)) then
                    pm.defer('re-check ' .. entry.file, function() pm.loadPlugin(entry.file, entry.fullPath) end)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Re-evaluates the file: if it now returns a plugin table it is loaded as a plugin.')
                end
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
    end

    if totalLoaded == 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'No plugins found in ' .. tostring(dirStr) .. '.')
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Drop any compatible .lua plugin into the folder and click "Rescan Plugins Folder".')
        return
    end

    local flags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.SizingFixedFit)
    if ImGui.BeginTable('TriunePluginsTable', 8, flags) then
        ImGui.TableSetupColumn('Active', ImGuiTableColumnFlags.WidthFixed, 48)
        ImGui.TableSetupColumn('Combat', ImGuiTableColumnFlags.WidthFixed, 56)
        ImGui.TableSetupColumn('Header', ImGuiTableColumnFlags.WidthFixed, 56)
        ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Plugin Name', ImGuiTableColumnFlags.WidthFixed, 170)
        ImGui.TableSetupColumn('Latency', ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableSetupColumn('Description', ImGuiTableColumnFlags.WidthStretch, 0)
        ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 140)
        ImGui.TableHeadersRow()

        for idx, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                ImGui.TableNextRow()

                -- Col 1: Active toggle
                ImGui.TableNextColumn()
                local isEn = (p.enabled == true)
                if p.pendingEnabled ~= nil then isEn = p.pendingEnabled end
                local newEn = ImGui.Checkbox(string.format('##enPlg_%d', idx), isEn)
                if newEn ~= isEn then
                    p.pendingEnabled = newEn
                    pm.defer((newEn and 'enable ' or 'disable ') .. id, function()
                        if newEn then
                            pm.enablePlugin(id)
                        else
                            pm.disablePlugin(id)
                        end
                        p.pendingEnabled = nil
                        runtime.saveLoadout(true)
                    end)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', isEn and 'Plugin is enabled. Uncheck to disable.' or 'Plugin is disabled. Check to enable.')
                end

                -- Col 2: In-Combat toggle
                ImGui.TableNextColumn()
                local runInCombat = not p.runOutOfCombatOnly
                local newRunInCombat = ImGui.Checkbox(string.format('##cbPlg_%d', idx), runInCombat)
                if newRunInCombat ~= runInCombat then
                    p.runOutOfCombatOnly = not newRunInCombat
                    if not ctrl.plugins then ctrl.plugins = {} end
                    if not ctrl.plugins[id] then ctrl.plugins[id] = {} end
                    ctrl.plugins[id].runInCombat = newRunInCombat
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', runInCombat
                        and 'Active in Combat: Fiber updates continuously during battle.\nUncheck to put to sleep during combat.'
                        or 'Sleeps in Combat: Fiber pauses during combat to eliminate latency.\nCheck to allow continuous updates in battle.')
                end

                -- Col 3: Header button toggle (plugins that own a window)
                ImGui.TableNextColumn()
                if pm.getWindow(id) then
                    local hdrOn = pm.headerButtonEnabled(id)
                    local newHdr = ImGui.Checkbox(string.format('##hdrPlg_%d', idx), hdrOn)
                    if newHdr ~= hdrOn then
                        pm.setHeaderButton(id, newHdr)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', string.format('%s a "%s" button on the main window header that opens / closes this plugin\'s window.',
                            hdrOn and 'Showing' or 'Check to show', tostring(pm.getWindow(id).label or id)))
                    end
                    ImGui.SameLine()
                    local wOpen = pm.isWindowOpen(id)
                    if ImGui.SmallButton(string.format(wOpen and 'Hide##win_%d' or 'Show##win_%d', idx)) then
                        pm.toggleWindow(id)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', wOpen and 'Close this plugin\'s window.' or 'Open this plugin\'s window now.')
                    end
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '—')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', 'This plugin has no window of its own.')
                    end
                end

                -- Col 4: Status Pill
                ImGui.TableNextColumn()
                if p.status == 'Active' then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Active')
                elseif p.status == 'Sleeping (Combat)' then
                    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Sleeping (Combat)')
                elseif p.status == 'Error' then
                    ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Error')
                    if ImGui.IsItemHovered() and p.errorMsg then
                        ImGui.SetTooltip('%s', p.errorMsg)
                    end
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Disabled')
                end

                -- Col 5: Plugin Name & Author
                ImGui.TableNextColumn()
                ImGui.Text(p.name or id)
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('v%s by %s', p.version or '1.0', p.author or 'Unknown'))

                -- Col 6: Latency Profiler
                ImGui.TableNextColumn()
                if p.enabled and p.status ~= 'Disabled' then
                    local avg = p.avgExecMs or 0
                    local col = (avg < 1.0) and GOOD or ((avg < 3.0) and WARN or ERR)
                    ImGui.TextColored(col[1], col[2], col[3], col[4], string.format('%.2f ms', avg))
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', string.format('Last Tick: %.3f ms\nAverage: %.3f ms\nInterval: %.2fs\nRuns in Combat: %s',
                            p.lastExecMs or 0, avg, p.tickInterval or 0.1, p.runOutOfCombatOnly and 'No (Sleeps)' or 'Yes'))
                    end
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '—')
                end

                -- Col 7: Description
                ImGui.TableNextColumn()
                ImGui.TextWrapped(p.description or '')

                -- Col 8: Actions
                ImGui.TableNextColumn()
                if p.instance and p.instance.onDrawSettings then
                    if ImGui.SmallButton(string.format('Configure##cfg_%d', idx)) then
                        pm.activeConfigPluginId = id
                        pm.openConfigRequested = true
                    end
                    ImGui.SameLine()
                end
                if ImGui.SmallButton(string.format('Reload##rel_%d', idx)) then
                    pm.defer('reload ' .. id, function() pm.reloadPlugin(id) end)
                end
            end
        end

        ImGui.EndTable()
    end

    -- Plugin Configuration Modal Popup Dialog
    if pm.openConfigRequested then
        pm.openConfigRequested = false
        ImGui.OpenPopup('Plugin Configuration##PluginConfigModal')
    end

    if pm.activeConfigPluginId and pm.plugins[pm.activeConfigPluginId] then
        local p = pm.plugins[pm.activeConfigPluginId]
        ImGui.SetNextWindowSize(540, 420, ImGuiCond.FirstUseEver)
        local openModal, showModal = ImGui.BeginPopupModal('Plugin Configuration##PluginConfigModal', true, ImGuiWindowFlags.AlwaysAutoResize)
        if showModal then
            accent(GOLD, string.format('%s (v%s)', p.name or p.id, p.version or '1.0'))
            ImGui.SameLine()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('by %s', p.author or 'Unknown'))
            if p.description and p.description ~= '' then
                ImGui.TextWrapped(p.description)
            end
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            -- Quick Toggles inside Modal
            local isEn = (p.enabled == true)
            if p.pendingEnabled ~= nil then isEn = p.pendingEnabled end
            local newEn = ImGui.Checkbox('Enabled##modalEn', isEn)
            if newEn ~= isEn then
                local modalId = pm.activeConfigPluginId
                p.pendingEnabled = newEn
                pm.defer((newEn and 'enable ' or 'disable ') .. modalId, function()
                    if newEn then pm.enablePlugin(modalId) else pm.disablePlugin(modalId) end
                    p.pendingEnabled = nil
                    runtime.saveLoadout(true)
                end)
            end
            ImGui.SameLine()
            local runInCombat = not p.runOutOfCombatOnly
            local newCombat = ImGui.Checkbox('Run During Combat##modalCombat', runInCombat)
            if newCombat ~= runInCombat then
                p.runOutOfCombatOnly = not newCombat
                if not ctrl.plugins then ctrl.plugins = {} end
                if not ctrl.plugins[pm.activeConfigPluginId] then ctrl.plugins[pm.activeConfigPluginId] = {} end
                ctrl.plugins[pm.activeConfigPluginId].runInCombat = newCombat
                runtime.saveLoadout(true)
            end
            if pm.getWindow(pm.activeConfigPluginId) then
                ImGui.SameLine()
                local hdrOn = pm.headerButtonEnabled(pm.activeConfigPluginId)
                local newHdr = ImGui.Checkbox('Header Button##modalHdr', hdrOn)
                if newHdr ~= hdrOn then
                    pm.setHeaderButton(pm.activeConfigPluginId, newHdr)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Show a button on the main window header that opens / closes this plugin\'s window.')
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Reload Plugin##modalReload') then
                local modalId = pm.activeConfigPluginId
                pm.defer('reload ' .. modalId, function() pm.reloadPlugin(modalId) end)
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            -- Custom Settings Panel inside child frame for smooth scrolling if large
            if p.instance and p.instance.onDrawSettings then
                if ImGui.BeginChild('plgModalSettingsChild', 520, 240, true) then
                    pm.drawPluginSettings(pm.activeConfigPluginId)
                end
                ImGui.EndChild()
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'This plugin does not require any additional configuration.')
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            local closeClicked = ImGui.Button('Close##modalClose', 100, 24)
            if closeClicked or not openModal then
                ImGui.CloseCurrentPopup()
                pm.activeConfigPluginId = nil
            end

            ImGui.EndPopup()
        elseif not openModal then
            pm.activeConfigPluginId = nil
        end
    end
end

-- Session Tracker Helpers (AA / Platinum)
function UI.getCurrentAA()
    local okTotal, total = pcall(function() return mq.TLO.Me.AAPointsTotal() end)
    local okSpent, spent = pcall(function() return mq.TLO.Me.AAPointsSpent() end)
    local okUnspent, unspent = pcall(function() return mq.TLO.Me.AAPoints() end)
    local okPct, pct = pcall(function() return mq.TLO.Me.PctAAExp() end)

    local aaCount = nil
    if okTotal and type(total) == 'number' then
        aaCount = total
    elseif (okSpent and type(spent) == 'number') or (okUnspent and type(unspent) == 'number') then
        aaCount = (spent or 0) + (unspent or 0)
    end

    if aaCount and okPct and type(pct) == 'number' then
        aaCount = aaCount + (pct / 100)
    end
    return aaCount
end

function UI.getCurrentPlat()
    local okCash, cash = pcall(function() return mq.TLO.Me.Cash() end)
    if okCash and type(cash) == 'number' and cash >= 0 then
        return math.floor(cash / 1000)
    end
    local okPlat, plat = pcall(function() return mq.TLO.Me.Platinum() end)
    if okPlat and type(plat) == 'number' then
        return plat
    end
    return nil
end

function UI.resetTracker()
    runtime.trackStartTime = os.time()
    runtime.startAA = UI.getCurrentAA()
    runtime.currentAA = runtime.startAA or 0
    runtime.startPlat = UI.getCurrentPlat()
    runtime.currentPlat = runtime.startPlat or 0
end

function UI.updateTracker()
    if not runtime.trackStartTime then
        runtime.trackStartTime = os.time()
    end
    local aa = UI.getCurrentAA()
    if aa ~= nil then
        if runtime.startAA == nil then runtime.startAA = aa end
        runtime.currentAA = aa
    end
    local plat = UI.getCurrentPlat()
    if plat ~= nil then
        if runtime.startPlat == nil then runtime.startPlat = plat end
        runtime.currentPlat = plat
    end
end

-- Toggle a standalone Lua script: stop it if running, otherwise run it.
-- Returns 'started' or 'stopped'. stopCmd overrides the default
-- '/lua stop <name>' stop action. (The companion tools are plugins now; this
-- stays for third-party scripts and plugin authors via core.toggleTool.)
function UI.toggleTool(scriptName, stopCmd)
    local s = mq.TLO.Lua.Script(scriptName)
    if s() and s.Status() == 'RUNNING' then
        mq.cmd(stopCmd or ('/lua stop ' .. scriptName))
        return 'stopped'
    end
    mq.cmd('/lua run ' .. scriptName)
    return 'started'
end

function UI.drawHeaderBar()
    UI.updateTracker()

    -- Toolbar buttons (with compact vertical padding)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 5, 2)

    if ImGui.Button('Compact Mode##hdrCompact') then
        ctrl.compact = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Switches Triune AutoCombat into a sleek compact HUD overlay window.')
    end

    -- Plugin window toggles (Spellbook, Map, DPS, Cursor, Cooldowns, HUDs, ...).
    -- Which plugins get a button here is chosen per plugin on Settings -> Plugins.
    if not runtime.pluginManager then runtime.initPluginManager() end
    if runtime.pluginManager then
        -- Compact Mode already occupies the first slot of the first row; the
        -- manager keeps rows to 8 buttons (pm.HEADER_BUTTONS_PER_ROW).
        if runtime.pluginManager.drawHeaderButtons(1) == 0 then
            ImGui.SameLine()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(no plugin window buttons - enable them on Settings -> Plugins)')
        end
    end

    ImGui.PopStyleVar()

    if not DATA_OK then
        accent(WARN,
            'No triune_data.lua found in your MQ config folder -- run extract_spells.py and copy it there. Spell/AA lists will be empty.')
    end
    if not navLoaded() then
        accent(WARN,
            'MQ2Nav plugin is NOT loaded. Pathing, hunter roaming, chase, and return-to-camp require MQ2Nav.')
        ImGui.SameLine()
        if ImGui.Button('Load MQ2Nav##hdrLoadNav') then
            mq.cmd('/plugin mq2nav')
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Executes /plugin mq2nav to load the MQ2Nav plugin.')
        end
    elseif not navMeshLoaded() then
        local curZone = mq.TLO.Zone.ShortName() or 'current zone'
        accent(WARN,
            string.format('No NavMesh loaded for zone "%s". Pathing, roaming, and chase require a zone mesh.', curZone))
        ImGui.SameLine()
        if ImGui.Button('Reload Mesh##hdrReloadMesh') then
            mq.cmd('/nav reload')
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Executes /nav reload to attempt reloading the zone navmesh.')
        end
    end
    if not stickLoaded() then
        accent(WARN,
            'MQ2MoveUtils plugin is NOT loaded. Melee stick, combat positioning, and unstuck require MQ2MoveUtils.')
        ImGui.SameLine()
        if ImGui.Button('Load MQ2MoveUtils##hdrLoadMoveUtils') then
            mq.cmd('/plugin mq2moveutils')
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Executes /plugin mq2moveutils to load the MQ2MoveUtils plugin.')
        end
    end
    ImGui.Separator()
end

function UI.drawClassPicker()
    local CLASS_PICKER_OPTIONS = { '-- None --', 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm', 'Nec',
        'Wiz', 'Mag', 'Enc', 'Bst', 'Ber' }
    if ImGui.CollapsingHeader('Character Classes & Loadout', ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.TextDisabled('Auto-detected from Inventory Window on login; adjust manually if needed:')
        for i = 1, 3 do
            ImGui.SetNextItemWidth(95)
            local currentVal = myClasses[i]
            local currentIdx = 1
            if currentVal then
                for idx, opt in ipairs(CLASS_PICKER_OPTIONS) do
                    if opt == currentVal then
                        currentIdx = idx
                        break
                    end
                end
            end
            local newIdx = ImGui.Combo('##cls' .. i, currentIdx, CLASS_PICKER_OPTIONS)
            if newIdx ~= currentIdx then
                if newIdx == 1 then
                    myClasses[i] = nil
                else
                    myClasses[i] = CLASS_PICKER_OPTIONS[newIdx]
                end
                runtime.saveLoadout()
            end
            ImGui.SameLine()
        end
        if ImGui.Button('Re-detect') then reDetectRequested = true end
        if ImGui.Button('Save Loadout', 140, 24) then runtime.saveLoadout() end
        ImGui.SameLine(); ImGui.TextDisabled('-> triune_loadout.lua (auto-saves on changes)')
        accent(MUTED, 'Detected from your in-game Inventory Window.')
    end
end

function UI.drawHelpTab()
    if not ImGui.BeginTabItem('Help') then return end

    if ImGui.CollapsingHeader('Slash Commands', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Commands (Alias: /ac or /triune):')
        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##HelpCmdTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Command', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Description', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            local commands = {
                { cmd = '/ac run / /ac start',                desc = 'Start / unpause auto-combat execution' },
                { cmd = '/ac pause / /ac stop',               desc = 'Pause auto-combat execution, halt movement & disengage pet' },
                { cmd = '/ac burn [on|off]',                  desc = 'Toggle burn mode (enables "Burn Only" spells, AAs, discs)' },
                { cmd = '/ac memall',                         desc = 'Queue all missing or mismatched priority spells to memorization bar' },
                { cmd = '/ac importbar / /ac import',         desc = 'Auto-populate spell lines from currently memorized spell gems' },
                { cmd = '/ac status',                         desc = 'Print current running state and combat mode to chat' },
                { cmd = '/ac compact / /ac mini',             desc = 'Toggle auto-resizing Compact Mini-Window mode' },
                { cmd = '/ac hud / /ac uf',                   desc = 'Toggle popout Target & Player HUD unit frames window' },
                { cmd = '/ac cd / /ac cooldowns',             desc = 'Toggle popout Cooldown & Ability Monitor window' },
                { cmd = '/ac help / /ac h',                   desc = 'Print slash command usage and command options in chat' },
                { cmd = '/ac spellbook',                      desc = 'Toggle the Spellbook Browser & mem-to-gem queue window' },
                { cmd = '/ac cursorui',                       desc = 'Toggle the Cursor Item Manager window (cursor plugin)' },
                { cmd = '/ac clearcursor',                    desc = 'Clear item on cursor (autoinventory / drop / destroy per rules)' },
                { cmd = '/ac clear lockouts',                 desc = 'Clear all active spell lockouts, non-stacking buff backoffs, and mob immunities' },
                { cmd = '/ac buffbot [on|off]',               desc = 'Toggle the Buffbot window; on/off starts or stops the buffbot station (buffbot plugin)' },
                { cmd = '/ac map / /ac track / /ac zone',     desc = 'Toggle the Map, Zone Atlas & NPC Tracker window (map plugin)' },
                { cmd = '/ac inv / /ac bank',                 desc = 'Toggle the Inventory & Bank Manager window (inventory plugin)' },
                { cmd = '/ac dps / /dps',                     desc = 'Toggle the DPS Parser window (dps plugin)' },
                { cmd = '/ac net [all|zone|group|Name] [command]', desc = 'Toggle the Box Network window, or run an /ac command on your other boxes (boxnet plugin)' },
                { cmd = '/ac btn [n|new|exec <set> <index>|import bm]', desc = 'Toggle the Hot Buttons hotbars, show/hide hotbar n, or fire a button (buttons plugin; also /btn, /btnexec)' },
                { cmd = '/dps compact',                       desc = 'Toggle DPS parser auto-resizing compact mode' },
                { cmd = '/dps report [chan]',                 desc = 'Report combat statistics to /group, /say, /guild, or /raid' },
                { cmd = '/dps reset',                         desc = 'Reset active combat damage counters' },
                { cmd = '/ac zplane [5-100]',                 desc = 'Configure Hunter Tier 1 same-floor / Z plane height threshold (default 15)' },
                { cmd = '/ac huntz [10-300]',                 desc = 'Configure Hunter Tier 2 max vertical height difference (default 75)' },
                { cmd = '/ac <mode> [submode]',               desc = 'Switch combat mode (e.g. /ac manual, /ac puller hunt, /ac puller camp, /ac assist chase, /ac backline, /ac tank)' },
                { cmd = '/ac ma [target|clear|<name>|<id>]',  desc = 'Configure Main Assist by player ID or name, or set from current PC target' },
                { cmd = '/ac xtardist [25-300]',              desc = 'Configure max XTarget / assist engagement chase distance (default 150)' },
                { cmd = '/ac chasedist [5-100]',              desc = 'Configure following distance (how far to stay back) from Main Assist (default 15)' },
                { cmd = '/ac selfdefense [on|off]',           desc = 'Toggle Assist mode self-defense when attacked while MA has no target' },
                { cmd = '/ac assistbehind [on|off]',          desc = 'Toggle Assist mode positioning behind NPC in combat (default: on)' },
                { cmd = '/ac manualstick [on|off]',           desc = 'Manual mode: stick to / chase the NPC being fought (default: on). Off = you drive.' },
                { cmd = '/ac manualnav [on|off]',             desc = 'Manual mode: auto-navigate to a hostile NPC as soon as you select it (default: off)' },
                { cmd = '/ac pullcon [tier] [on|off]',        desc = 'Configure Puller faction consideration filter (Scowling, Indifferent, etc.) or preset' },
                { cmd = '/ac wp [add|clear|del|on|off|list]', desc = 'Configure & toggle Puller Waypoint Patrol loop' },
                { cmd = '/ac pullhp [0-95]',                  desc = 'Configure minimum HP percentage threshold before pausing pulling to rest (default 0 / disabled)' },
                { cmd = '/triunerun',                         desc = 'Quick keybind command to toggle run / pause' },
            }

            for _, entry in ipairs(commands) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                accent(ARC, entry.cmd)
                ImGui.TableNextColumn()
                ImGui.Text(entry.desc)
            end
            ImGui.EndTable()
        end
    end


    if ImGui.CollapsingHeader('Combat Modes', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Available Combat Modes & Behavior:')
        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##HelpModeTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Mode', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Behavior Description', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            for _, primaryName in ipairs(MODES.PRIMARY) do
                if MODES.SUBMODES[primaryName] then
                    for _, subName in ipairs(MODES.SUBMODES[primaryName]) do
                        local fullKey = primaryName .. ':' .. subName
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        accent(GOOD, primaryName .. ' (' .. subName .. ')')
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(MODES.SUB_DESC[fullKey] or '')
                    end
                else
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    accent(GOOD, primaryName)
                    ImGui.TableNextColumn()
                    ImGui.TextWrapped(MODES.DESC[primaryName] or '')
                end
            end
            ImGui.EndTable()
        end
    end

    if ImGui.CollapsingHeader('Spell & Ability Target Filters', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Target Resolution Options (Spell Gems, Clickies, AAs, Discs, Actions):')
        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##HelpTargetTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Target Option', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Targeting Behavior & Resolution', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            local targets = {
                { opt = 'E: All Enemies',     color = ERR,  desc = 'Multi-Target mode: Evaluates ALL hostile enemies on your Extended Target (XTarget) window. For duration spells (DoTs, debuffs, snares, mes), sequentially casts on each enemy missing the effect and yields once all have it. For nukes/direct damage, round-robins casts evenly across all XTarget enemies. Honors per-mob max_casts and skips locked-out/immune mobs.' },
                { opt = 'E: Current Target',  color = ERR,  desc = 'Casts directly on your currently active game target (Target TLO). Does not switch targets automatically.' },
                { opt = 'E: Assist Target',   color = ERR,  desc = 'Targets the hostile mob currently targeted by your configured Main Assist. If MA has no target and Assist Self-Defense is on, falls back to your direct attacker.' },
                { opt = 'E: Nearest Add',     color = ERR,  desc = 'Targets the first hostile NPC add on your Extended Target window within vertical height limits. If XTarget has no adds, falls back to the nearest hostile NPC within camp/hunt radius.' },
                { opt = 'E: Unmezzed Add',    color = ERR,  desc = 'Targets the first hostile add on your Extended Target window that is NOT mesmerized. Ideal for Enchanter, Bard, or Necromancer crowd control (Mez) rotations.' },
                { opt = 'F: Myself',          color = GOOD, desc = 'Always targets and casts on your own character. Standard for self-buffs, personal emergency heals, and Feign Death.' },
                { opt = 'F: Main Assist',     color = GOOD, desc = 'Targets the designated Main Assist character for single-target buffs, heals, or utility.' },
                { opt = 'F: Tank',            color = GOOD, desc = 'Targets the designated Tank character for targeted heals, protective buffs, or damage mitigation.' },
                { opt = 'F: Lowest-HP Ally',  color = GOOD, desc = 'Scans yourself and all group members, automatically targeting the ally with the lowest current HP percentage. Ideal for reactive heals.' },
                { opt = 'F: Whole Group',     color = GOOD, desc = 'Targets your character to cast group-wide spells (group heals, group buffs, group auras).' },
                { opt = 'F: Pet',             color = GOOD, desc = 'Targets your summoned pet. On multi-class trio characters with multiple pets, prioritizes the pet class matching the spell, lowest HP pet, or pet missing the buff.' },
            }

            for _, entry in ipairs(targets) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                accent(entry.color, entry.opt)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(entry.desc)
            end
            ImGui.EndTable()
        end

        ImGui.Spacing()
        accent(GOLD, 'Cast Conditions ("When" Triggers):')
        if ImGui.BeginTable('##HelpWhenTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Condition', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Activation Criteria', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            local conditions = {
                { when = 'always',               desc = 'Casts whenever the spell gem or ability is ready and off cooldown (respects mana and reagent requirements).' },
                { when = 'in combat',            desc = 'Casts whenever your character or group is actively engaged in combat.' },
                { when = 'twist while fighting', desc = 'Continuously sings the song while in combat without waiting for buff duration to expire (Bard songs).' },
                { when = 'target HP <=',         desc = 'Casts when the target\'s HP percentage drops to or below the configured slider threshold.' },
                { when = 'target HP between',    desc = 'Casts only when target HP is between the configured minimum HP and percentage threshold (e.g. DoTs between 20% and 90%).' },
                { when = 'my HP <=',             desc = 'Casts when your own character\'s HP percentage drops to or below threshold (heals, defensives, Feign Death, Mend).' },
                { when = 'my Mana <=',           desc = 'Casts when your character\'s Mana percentage drops to or below threshold (Cannibalize, mana taps, rods).' },
                { when = 'missing buff',         desc = 'Casts only when the target does not currently have this buff or debuff active.' },
                { when = 'missing pet',          desc = 'Casts to summon a class pet when your pet is dead or missing.' },
                { when = 'has Poison',           desc = 'Casts cure spells when the target is afflicted with poison counters.' },
                { when = 'has Disease',          desc = 'Casts cure spells when the target is afflicted with disease counters.' },
                { when = 'has Poison/Disease',   desc = 'Casts cure spells when the target is afflicted with either poison or disease counters (combined trigger).' },
                { when = 'has Curse',            desc = 'Casts cure spells when the target is afflicted with curse counters.' },
                { when = 'has Corruption',       desc = 'Casts cure spells when the target is afflicted with corruption counters.' },
                { when = 'Aggro on Me',          desc = 'Casts when an enemy mob currently has primary aggro on your character.' },
                { when = 'my Aggro >=',          desc = 'Casts when your secondary aggro percentage meets or exceeds threshold (fade, jolt, de-aggro).' },
                { when = 'ally is Dead',         desc = 'Casts resurrection spells when a group member is dead/corpse.' },
                { when = 'add is loose',         desc = 'Casts when an unmezzed or uncontrolled add is detected on your Extended Target list.' },
            }

            for _, entry in ipairs(conditions) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                accent(ARC, entry.when)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(entry.desc)
            end
            ImGui.EndTable()
        end
    end

    ImGui.EndTabItem()
end

function UI.getGemStatusBadge(i, g)
    if not g or not g.spell or g.spell == '' then
        return MUTED, '[--]', 'Slot is empty. Select a class and spell to assign.'
    end
    local gemSlot = tonumber(g.gem) or i
    if runtime.isSwitchingSpells and runtime.switchingSlot == gemSlot and runtime.switchingSpellName == g.spell then
        return WARN, '[MEM*]', string.format('Currently memorizing "%s" into Gem %d...', g.spell, gemSlot)
    end
    if runtime.pendingMem and runtime.pendingMem[gemSlot] == g.spell then
        return WARN, '[MEM*]', string.format('Queued to memorize "%s" into Gem %d', g.spell, gemSlot)
    end
    local isMemmed = isGemMatching(gemSlot, g.spell)
    if not isMemmed then
        local otherSlot = nil
        pcall(function() otherSlot = mq.TLO.Me.Gem(g.spell)() end)
        if otherSlot and otherSlot > 0 then
            gemSlot = otherSlot
            isMemmed = true
        end
    end
    if not isMemmed then
        local memmedName = nil
        pcall(function() memmedName = mq.TLO.Me.Gem(gemSlot).Name() end)
        return WARN, '[UNMEM]', string.format('Configured for Gem %d ("%s"), but Gem %d currently has "%s". (Will auto-mem during downtime if needed)', gemSlot, g.spell, gemSlot, tostring(memmedName or 'empty'))
    end

    local ready = false
    local timer = 0
    pcall(function() ready = mq.TLO.Me.SpellReady(gemSlot)() end)
    if not ready then
        pcall(function() timer = tonumber(mq.TLO.Me.GemTimer(gemSlot)()) or 0 end)
        if timer > 0 and timer < 3600000 then
            return GOLD, string.format('[%.1fs]', timer / 1000), string.format('Spell is recharging (%.1f seconds remaining)', timer / 1000)
        end
        return GOLD, '[CD]', 'Spell is recharging cooldown.'
    end

    local spMana, curMana = 0, 0
    pcall(function()
        spMana = tonumber(mq.TLO.Spell(g.spell).Mana()) or 0
        curMana = tonumber(mq.TLO.Me.CurrentMana()) or 0
    end)
    if curMana < spMana then
        return ERR, '[MANA]', string.format('Insufficient mana: requires %d mana (current: %d)', spMana, curMana)
    end

    if castTracker and castTracker.isLockedOut(g.spell, nil, g.kind) then
        return MUTED, '[LOCK]', 'Spell is temporarily locked out due to resist backoff/fail policy.'
    end

    return GOOD, '[RDY]', string.format('Spell is memorized in Gem %d and ready to cast.', gemSlot)
end

-- Row-rendering for the Spell Gems tab (Compact layout).
-- UI: spell/gem list editor
function UI.drawGemList(gemsTable, idPrefix, isActiveSet, allowBurn)
    if allowBurn == nil then allowBurn = true end
    local maxGems = getNumGems()
    local totalSpells = #gemsTable
    local toDelete = nil

    local gemOpts = {}
    for gNum = 1, 12 do
        table.insert(gemOpts, string.format('G%d', gNum))
    end

    -- Compact styling inside gem list: scaled +10% for improved readability
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 3)

    if ImGui.BeginChild('gemlist_' .. idPrefix, 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        if totalSpells == 0 then
            ImGui.TextDisabled('No spells configured. Click "+ Add Spell" or "Import Bar" above to populate your spell list.')
        else
            for i = 1, totalSpells do
                ImGui.PushID(idPrefix .. i)
                local g = gemsTable[i]
                if not g then g = {}; gemsTable[i] = g end
                if g.gem == nil then g.gem = math.min(i, 12) end
                local cls = g.cls

                -- 1-click Priority Move Buttons (^ / v)
                if i > 1 then
                    if ImGui.Button('^##u', 17, 19) then
                        local tmp = gemsTable[i - 1]
                        gemsTable[i - 1] = gemsTable[i]
                        gemsTable[i] = tmp
                        runtime.saveLoadout(true)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Move priority UP (swap with spell #%d).', i - 1) end
                else
                    ImGui.InvisibleButton('##uDummy', 17, 19)
                end
                ImGui.SameLine()
                if i < totalSpells then
                    if ImGui.Button('v##d', 17, 19) then
                        local tmp = gemsTable[i + 1]
                        gemsTable[i + 1] = gemsTable[i]
                        gemsTable[i] = tmp
                        runtime.saveLoadout(true)
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip('Move priority DOWN (swap with spell #%d).', i + 1) end
                else
                    ImGui.InvisibleButton('##dDummy', 17, 19)
                end
                ImGui.SameLine()

                -- Gem Dropdown selector
                local curGem = tonumber(g.gem) or 1
                if curGem < 1 then curGem = 1 end
                if curGem > 12 then curGem = 12 end
                ImGui.SetNextItemWidth(50)
                local newGem = ImGui.Combo('##gem', curGem, gemOpts)
                if newGem ~= curGem then
                    g.gem = newGem
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Physical spell gem to cast this spell from. Multiple spells can share the same gem!')
                end
                ImGui.SameLine()

                -- Live In-UI Status Badge
                local bCol, bText, bTip = UI.getGemStatusBadge(i, g)
                accent(bCol, bText)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', bTip)
                end
                ImGui.SameLine()

                -- class combo (none + trio)
                local classOpts = { '--' }
                for _, c in ipairs(myClasses) do classOpts[#classOpts + 1] = c end
                local curCi = cls and idxOf(classOpts, cls) or 1
                ImGui.SetNextItemWidth(59)
                local ci = ImGui.Combo('##c', curCi, classOpts)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Select class for slot (or "--" to clear).')
                end
                local newCls = (ci > 1) and classOpts[ci] or nil
                if newCls ~= cls then
                    if newCls then
                        g.cls = newCls
                        g.spell = nil
                        g.target = 'F: Myself'
                        g.when = 'always'
                        g.pct = 100
                    else
                        g.cls = nil
                        g.spell = nil
                    end
                    cls = newCls
                    runtime.saveLoadout(true)
                end

                if cls then
                    if not classHasSpells(cls) then
                        ImGui.SameLine(); accent(MUTED, '  ' .. cls .. ' has no spells (melee) -> Abilities')
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(cls .. ' is a melee class without castable spell gems. Set up disciplines and abilities on the Abilities tab.')
                        end
                    else
                        local names, lookup = filteredSpells(cls)
                        local spOpts = { '-- choose --' }
                        for _, n in ipairs(names) do spOpts[#spOpts + 1] = n end
                        local curSi = 1
                        if g.spell then
                            for k, lu in pairs(lookup) do if lu.name == g.spell then curSi = k + 1 end end
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(180)
                        local si = ImGui.Combo('##s', curSi, spOpts)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Select spell to assign.')
                        end
                        if si > 1 then
                            local lu = lookup[si - 1]
                            if lu and lu.name ~= g.spell then
                                g.spell = lu.name
                                g.target, g.when, g.pct = defaultsForKind(lu.kind, lu.bene)
                                if ctrl.automem and isActiveSet and (tonumber(g.gem) or 1) <= maxGems then
                                    runtime.pendingMem[tonumber(g.gem) or 1] = lu.name
                                end
                                runtime.saveLoadout(true)
                            end
                        end

                        -- target
                        ImGui.SameLine(); ImGui.SetNextItemWidth(133)
                        local ti = ImGui.Combo('##t', idxOf(COMBO_OPTIONS.TARGETS, g.target or 'F: Myself'), COMBO_OPTIONS.TARGETS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Target: who to cast on (Myself, Tank, Target, MA Target, Pet).')
                        end
                        local newTgt = COMBO_OPTIONS.TARGETS[ti]
                        if newTgt ~= g.target then
                            g.target = newTgt
                            runtime.saveLoadout(true)
                        end

                        -- when
                        ImGui.SameLine(); ImGui.SetNextItemWidth(116)
                        local wi = ImGui.Combo('##w', idxOf(COMBO_OPTIONS.WHENS, g.when or 'always'), COMBO_OPTIONS.WHENS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Trigger: condition to cast (HP <=, target HP between, missing buff, has Curse, in combat).')
                        end
                        local newWhen = COMBO_OPTIONS.WHENS[wi]
                        if newWhen ~= g.when then
                            g.when = newWhen
                            runtime.saveLoadout(true)
                        end

                        -- percent: draggable slider that shows the value (0% = Off)
                        ImGui.SameLine(); ImGui.SetNextItemWidth(57)
                        local curPct = tonumber(g.pct)
                        if curPct == nil then curPct = 100 end
                        local isDis = (curPct == 0)
                        local pCount = 0
                        if isDis then pCount = UI.pushDisabledSliderStyle() end
                        local newPct = ImGui.SliderInt('##p', curPct, 0, 100, isDis and 'Off' or '%d%%')
                        local isHov = ImGui.IsItemHovered()
                        if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                        if newPct ~= curPct then
                            g.pct = newPct
                            runtime.saveLoadout(true)
                        end
                        if isHov then
                            if newPct == 0 then
                                UI.setTooltip('Spell is Disabled (0%). Drag slider above 0% to enable.')
                            else
                                UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this spell).', newPct))
                            end
                        end

                        -- If 'target HP between', show Min HP threshold slider
                        if g.when == 'target HP between' then
                            ImGui.SameLine(); ImGui.SetNextItemWidth(48)
                            local minHp = tonumber(g.min_hp) or 20
                            local newMinHp = ImGui.SliderInt('##minhp', minHp, 0, 100, '%d%%>')
                            if newMinHp ~= minHp then
                                g.min_hp = newMinHp
                                runtime.saveLoadout(true)
                            end
                            if ImGui.IsItemHovered() then
                                UI.setTooltip(string.format('Min Target HP%%: %d%% (Cast when target is between %d%% and %d%% HP).', newMinHp, newMinHp, newPct))
                            end
                        end
                    end

                    if allowBurn then
                        ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                        local curXt = tonumber(g.min_xtar) or 1
                        if curXt < 1 then curXt = 1 end
                        if curXt > 10 then curXt = 10 end
                        local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local newXti = ImGui.Combo('##mxt', curXt, xtOpts)
                        if newXti ~= curXt then
                            g.min_xtar = newXti
                            runtime.saveLoadout(true)
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Min active NPCs on XTarget required.')
                        end

                        ImGui.SameLine(); ImGui.SetNextItemWidth(48)
                        local maxCastOpts = { 'Unl', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local curMc = tonumber(g.max_casts) or 0
                        if curMc < 0 or curMc > 10 then curMc = 0 end
                        local newMci = ImGui.Combo('##mc', curMc + 1, maxCastOpts)
                        local newMc = (newMci == 1) and 0 or (newMci - 1)
                        if newMc ~= curMc then
                            g.max_casts = newMc
                            runtime.saveLoadout(true)
                        end
                        if ImGui.IsItemHovered() then
                            if newMc == 0 then
                                UI.setTooltip('Per-NPC Cast Limit: Unlimited (Unl). Triune will cast this spell whenever conditions are met.')
                            else
                                UI.setTooltip(string.format('Per-NPC Cast Limit: Max %d cast(s) per NPC. Once cast %d time(s) on a target, Triune will not cast it on that NPC again.', newMc, newMc))
                            end
                        end

                        ImGui.SameLine()
                        local boVal = ImGui.Checkbox('Burn##bo', g.burn_only or false)
                        if boVal ~= (g.burn_only or false) then
                            g.burn_only = boVal
                            runtime.saveLoadout(true)
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Only cast when Burn Mode is ON.')
                        end
                    end
                end

                -- Delete spell line button
                ImGui.SameLine()
                if ImGui.Button('X##del', 18, 19) then
                    toDelete = i
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Delete this spell line from your loadout.')
                end

                ImGui.PopID()
            end

            if toDelete then
                table.remove(gemsTable, toDelete)
                runtime.saveLoadout(true)
            end
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
end

-- Header controls for the Spell Gems tab: + Add Spell, level band, scribed filter, rebuff threshold, and downtime buffs.
function UI.drawGemTabHeader(gemsTable)
    if ImGui.Button('+ Add Spell##addSpellBtn') then
        local maxG = getNumGems()
        local nextGem = math.min(#gemsTable + 1, maxG)
        table.insert(gemsTable, {
            gem = nextGem,
            cls = (myClasses and myClasses[1]) or 'War',
            spell = nil,
            target = 'F: Myself',
            when = 'missing buff',
            pct = 100,
            min_xtar = 1,
            max_casts = 0,
            burn_only = false
        })
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Add a new spell line with customizable controls and gem selection.')
    end

    ImGui.SameLine(); ImGui.TextDisabled('|')

    ImGui.SameLine()
    local pendingCount = 0
    if runtime.pendingMem then
        for _ in pairs(runtime.pendingMem) do pendingCount = pendingCount + 1 end
    end
    local memBtnLabel = pendingCount > 0 and string.format('Mem All (%d)##memAllBtn', pendingCount) or 'Mem All##memAllBtn'
    if ImGui.Button(memBtnLabel) then
        runtime.queueMemAll()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Memorize any missing or wrong spells on your gem bar back to each gem\'s priority spell.')
    end

    ImGui.SameLine()
    if ImGui.Button('Import Bar##importBarBtn') then
        runtime.importCurrentGems(gemsTable)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Auto-populate spell lines based on what is currently memorized on your spell gems.')
    end

    ImGui.SameLine(); ImGui.TextDisabled('|')

    ImGui.SameLine(); ImGui.TextDisabled('Lvl:')
    if ImGui.IsItemHovered() then ImGui.SetTooltip('Filter available spells by character level range.') end
    ImGui.SameLine(); ImGui.SetNextItemWidth(29)
    local newLvlMin = ImGui.InputInt('##lmin', lvlMin, 0, 0)
    if newLvlMin < 1 then newLvlMin = 1 end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('Minimum spell level.') end
    if newLvlMin ~= lvlMin then lvlMin = newLvlMin; clearFilteredSpellsCache() end
    ImGui.SameLine(); ImGui.TextDisabled('-')
    ImGui.SameLine(); ImGui.SetNextItemWidth(29)
    local playerMaxLvl = (mq.TLO.Me and mq.TLO.Me.Level and (tonumber(mq.TLO.Me.Level()) or 65)) or 65
    if playerMaxLvl < 1 then playerMaxLvl = 65 end
    local newLvlMax = ImGui.InputInt('##lmax', lvlMax, 0, 0)
    if newLvlMax < 1 then newLvlMax = 1 end
    if newLvlMax > 65 then newLvlMax = 65 end
    if ImGui.IsItemHovered() then ImGui.SetTooltip(string.format('Maximum spell level (current character level: %d).', playerMaxLvl)) end
    if newLvlMax ~= lvlMax then lvlMax = newLvlMax; clearFilteredSpellsCache() end
    if lvlMin > lvlMax then lvlMin = lvlMax end

    ImGui.SameLine()
    local newScribed = ImGui.Checkbox('Scribed', ctrl.scribed_only)
    if newScribed ~= ctrl.scribed_only then
        ctrl.scribed_only = newScribed
        clearFilteredSpellsCache()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Only show spells in your spellbook. Turn off to browse all.')
    end

    ImGui.SameLine(); ImGui.TextDisabled('| Rebuff:')
    if ImGui.IsItemHovered() then ImGui.SetTooltip('Pre-refresh buffs out of combat when remaining duration falls below this threshold.') end
    ImGui.SameLine(); ImGui.SetNextItemWidth(60)
    local curRefSec = tonumber(ctrl.buff_refresh_sec) or 45
    local newRefSec = ImGui.SliderInt('##refsec', curRefSec, 0, 300, '%ds')
    ctrl.buff_refresh_sec = newRefSec
    if ImGui.IsItemHovered() then UI.setTooltip(string.format('Pre-refresh buffs out of combat if remaining duration <= %d seconds (0s = only when expired).', newRefSec)) end

    ImGui.SameLine(); ImGui.TextDisabled('|')

    ImGui.SameLine()
    local dtVal = ImGui.Checkbox('Downtime Buffs', ctrl.downtime_buffing ~= false)
    if dtVal ~= (ctrl.downtime_buffing ~= false) then
        ctrl.downtime_buffing = dtVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Auto-swap spell gems during downtime to cast missing buffs.')
    end

    ImGui.Separator()
end

function UI.drawGemTab()
    if not ImGui.BeginTabItem('Spell Gems') then return end
    UI.drawGemTabHeader(loadout.gems)
    UI.drawGemList(loadout.gems, 'gem', true, true)
    ImGui.EndTabItem()
end

function UI.addClickieFromCursor()
    local it = mq.TLO.Cursor
    if not it or not it() or (it.ID() or 0) <= 0 then
        print('\ar[Triune]\ax Cursor is empty -- pick up a clickable item first.')
        return false, 'Cursor is empty'
    end

    local itemName = tostring(it.Name() or '')
    if itemName == '' then
        print('\ar[Triune]\ax Unable to read item on cursor.')
        return false, 'Invalid item'
    end

    loadout.clickies = loadout.clickies or {}
    for _, c in ipairs(loadout.clickies) do
        if c.name == itemName then
            print('\ay[Triune]\ax Item "' .. itemName .. '" is already in your Clickies list.')
            return false, 'Already in list'
        end
    end

    local spellName = ''
    local castTime = 0
    local isBene = true

    pcall(function()
        if it.Clicky and it.Clicky() then
            local sp = it.Clicky.Spell
            if sp and sp() then
                spellName = tostring(sp.Name() or '')
                castTime = tonumber(it.Clicky.CastTime() or sp.CastTime() or 0) or 0
                isBene = not not sp.Beneficial()
            end
        end
    end)

    if spellName == '' then
        pcall(function()
            local sp = it.Spell
            if sp and sp() then
                spellName = tostring(sp.Name() or '')
                castTime = tonumber(it.CastTime() or sp.CastTime() or 0) or 0
                isBene = not not sp.Beneficial()
            end
        end)
    end

    if spellName == '' then
        print('\ar[Triune]\ax Item [' .. itemName .. '] does not have an activatable click effect/spell.')
        return false, 'No click effect'
    end

    local defTarget = isBene and 'F: Myself' or 'E: Current Target'
    local defWhen = isBene and 'missing buff' or 'in combat'
    local defPct = 100

    local entry = {
        name = itemName,
        spell = spellName,
        target = defTarget,
        when = defWhen,
        pct = defPct,
        min_xtar = 1,
        burn_only = false,
        enabled = true,
        cast_time = castTime,
    }

    table.insert(loadout.clickies, entry)
    runtime.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Added Clickie: [%s] (Spell: %s, Target: %s, Condition: %s)',
        itemName, spellName, defTarget, defWhen))
    return true
end

function UI.drawClickieTab()
    if not ImGui.BeginTabItem('Clickies') then return end
    ImGui.TextWrapped('Clickable Items: Manage inventory and equipped items with activatable spell effects. Click [+ Add Item on Cursor] while holding an item to add it.')
    if ImGui.IsItemHovered() then
        UI.setTooltip('Configure automated clickies (inventory/worn items). Items are clicked automatically when conditions are met.')
    end

    -- Cursor inspection info
    local curItem = mq.TLO.Cursor
    local hasCursorItem = curItem and curItem() and (curItem.ID() or 0) > 0
    local curName = hasCursorItem and tostring(curItem.Name() or 'Item') or nil

    if not hasCursorItem then ImGui.BeginDisabled() end
    if ImGui.Button('+ Add Item on Cursor##addCursorClickie', 150, 20) then
        UI.addClickieFromCursor()
    end
    if not hasCursorItem then ImGui.EndDisabled() end

    if ImGui.IsItemHovered() then
        if hasCursorItem then
            UI.setTooltip(string.format('Add [%s] from your cursor to the Clickies list.', curName))
        else
            UI.setTooltip('Pick up an item with a click effect onto your cursor, then click this button.')
        end
    end

    ImGui.SameLine()
    if hasCursorItem then
        accent(GOOD, 'Cursor: ' .. curName)
    else
        accent(MUTED, 'Cursor: (Empty)')
    end

    ImGui.SameLine()
    ImGui.TextDisabled(string.format('| %d item(s)', #(loadout.clickies or {})))

    ImGui.Separator()

    -- Compact styling inside clickies list: tighter item spacing & frame padding
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 3)

    if ImGui.BeginChild('clickielist', 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        loadout.clickies = loadout.clickies or {}
        local toRemove = nil

        for idx, c in ipairs(loadout.clickies) do
            ImGui.PushID('clk_' .. idx .. '_' .. (c.name or ''))

            -- Reorder Up
            if idx > 1 then
                if ImGui.Button('^##up', 17, 19) then
                    local tmp = loadout.clickies[idx]
                    loadout.clickies[idx] = loadout.clickies[idx - 1]
                    loadout.clickies[idx - 1] = tmp
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Move higher in priority order.')
                end
            else
                ImGui.InvisibleButton('##upDummy', 17, 19)
            end

            ImGui.SameLine()
            -- Reorder Down
            if idx < #loadout.clickies then
                if ImGui.Button('v##dn', 17, 19) then
                    local tmp = loadout.clickies[idx]
                    loadout.clickies[idx] = loadout.clickies[idx + 1]
                    loadout.clickies[idx + 1] = tmp
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Move lower in priority order.')
                end
            else
                ImGui.InvisibleButton('##dnDummy', 17, 19)
            end

            ImGui.SameLine()
            -- Delete button
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            local pCol = 0
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.65, 0.15, 0.15, 1.0) then pCol = pCol + 1 end
            if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.85, 0.25, 0.25, 1.0) then pCol = pCol + 1 end
            if ImGui.Button('X##del', 17, 19) then
                toRemove = idx
            end
            if pCol > 0 then pcall(ImGui.PopStyleColor, pCol) end
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Remove [%s] from Clickies.', c.name))
            end

            ImGui.SameLine()
            ImGui.Text(string.format('%2d', idx))
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Clickie Priority #%d', idx))
            end

            ImGui.SameLine()
            c.enabled = ImGui.Checkbox('##en', c.enabled ~= false)
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Enable or disable %s.', c.name))
            end

            ImGui.SameLine()
            accent(c.enabled ~= false and GOOD or MUTED, c.name or 'Item')
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Clickie Item: %s\nSpell Effect: %s', tostring(c.name), tostring(c.spell or 'Unknown')))
            end

            if c.spell and c.spell ~= '' then
                ImGui.SameLine()
                ImGui.TextDisabled('(' .. c.spell .. ')')
                if ImGui.IsItemHovered() then
                    UI.setTooltip(string.format('Click Effect Spell: %s', c.spell))
                end
            end

            if c.enabled ~= false then
                ImGui.SameLine(); ImGui.SetNextItemWidth(133)
                local ti = ImGui.Combo('##ct', idxOf(COMBO_OPTIONS.TARGETS, c.target or 'F: Myself'), COMBO_OPTIONS.TARGETS)
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Target condition: who or what to use this clickie on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                end
                c.target = COMBO_OPTIONS.TARGETS[ti]

                ImGui.SameLine(); ImGui.SetNextItemWidth(116)
                local wi = ImGui.Combo('##cw', idxOf(COMBO_OPTIONS.WHENS, c.when or 'missing buff'), COMBO_OPTIONS.WHENS)
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Trigger condition: when this clickie should be used (e.g. missing buff, HP <=, in combat, always).')
                end
                c.when = COMBO_OPTIONS.WHENS[wi]

                ImGui.SameLine(); ImGui.SetNextItemWidth(57)
                local curPct = tonumber(c.pct)
                if curPct == nil then curPct = 100 end
                local isDis = (curPct == 0)
                local pCount = 0
                if isDis then pCount = UI.pushDisabledSliderStyle() end
                local cpVal = ImGui.SliderInt('##cp', curPct, 0, 100, isDis and 'Off' or '%d%%')
                local isHov = ImGui.IsItemHovered()
                if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                c.pct = cpVal
                if isHov then
                    if cpVal == 0 then
                        UI.setTooltip('Clickie is Disabled (0%). Drag slider above 0% to enable.')
                    else
                        UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this clickie).', cpVal))
                    end
                end

                ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                local curXt = tonumber(c.min_xtar) or 1
                if curXt < 1 then curXt = 1 end
                if curXt > 10 then curXt = 10 end
                local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                local xti = ImGui.Combo('##cmxt', curXt, xtOpts)
                c.min_xtar = xti
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Minimum number of active NPCs on XTarget required for this clickie to fire.')
                end

                ImGui.SameLine()
                local cboVal = ImGui.Checkbox('Burn##cbo', c.burn_only or false)
                c.burn_only = cboVal
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Only use this clickie when Burn Mode is ON.')
                end
            end

            ImGui.PopID()
        end

        if toRemove then
            local removedName = loadout.clickies[toRemove] and loadout.clickies[toRemove].name or 'item'
            table.remove(loadout.clickies, toRemove)
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Removed Clickie: [' .. removedName .. ']')
        end

        if #loadout.clickies == 0 then
            accent(MUTED, '  (No clickies added yet -- pick up an item with a click effect on your cursor and click [+ Add Item on Cursor] above)')
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.EndTabItem()
end

-- UI: Innate Combat Abilities & Skills tab
function UI.drawAbilitiesTab()
    if not ImGui.BeginTabItem('Abilities') then return end
    ImGui.TextWrapped('Innate Combat Abilities & Skills (/doability) -- Kick, Bash, Slam, Mend, Backstab, Monk strikes, Taunt, Disarm, Frenzy, etc.')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Innate class actions and combat abilities operate independently of spell gems and fire automatically when ready or when conditions are met.')
    end
    ctrl.action_trained_only = ImGui.Checkbox('Trained Only##act', ctrl.action_trained_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Only show abilities you\'ve actually trained/unlocked in your skill list. Turn off to browse/plan ahead.')
    end
    ImGui.SameLine()
    if ImGui.Button('Popout Cooldowns##actCdPop') then
        ctrl.show_cooldowns = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Opens the standalone popout Cooldown & Ability Monitor window.')
    end
    ImGui.Separator()

    -- Compact styling inside abilities list: tighter item spacing & frame padding
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 3)

    if ImGui.BeginChild('abilitieslist', 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        local clientAbilities = getClientAbilities()
        local anyAction = false
        for _, item in ipairs(clientAbilities) do
            local nm = item.name
            local cls = item.cls or (myClasses and myClasses[1]) or 'War'
            if type(nm) == 'string' and nm ~= '' and nm ~= 'NULL' and nm ~= 'false' then
                local isTrained = item.isTrained or hasActionSkill(nm)
                if not ctrl.action_trained_only or isTrained then
                    anyAction = true
                    ImGui.PushID('act_' .. tostring(cls) .. '_' .. tostring(nm))
                local entry = loadout.actions[nm] or defaultActionEntry(nm, cls)
                entry.cls = entry.cls or cls
                entry.kind = entry.kind or (defaultActionEntry(nm, cls).kind)
                if entry.autoskill == nil then
                    entry.autoskill = defaultActionEntry(nm, cls).autoskill
                end

                entry.enabled = ImGui.Checkbox('##en', entry.enabled)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip(string.format('Enable or disable %s.', nm))
                end
                ImGui.SameLine()
                local r, gc, b, a = classColor(cls)
                ImGui.TextColored(r, gc, b, a, cls) ---@diagnostic disable-line: param-type-mismatch
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip(string.format('Class: %s', cls))
                end
                ImGui.SameLine()
                ImGui.Text(nm)
                if ImGui.IsItemHovered() then
                    local capStr = (item.skillCap and item.skillCap > 0) and string.format(' (Cap: %d, Skill: %d)', item.skillCap, item.currentSkill or 0) or ''
                    ImGui.SetTooltip(string.format('Combat Ability / Skill: %s%s', nm, capStr))
                end

                if isAutoskillEligible(nm) then
                    ImGui.SameLine()
                    local asVal = ImGui.Checkbox('Auto##as', entry.autoskill or false)
                    entry.autoskill = asVal
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Autoskill: Automatically fire this ability continuously on cooldown during combat against hostile targets in melee range.')
                    end
                else
                    entry.autoskill = false
                end

                if entry.enabled then
                    if entry.autoskill then
                        ImGui.SameLine()
                        ImGui.TextDisabled('[Auto on Cooldown]')
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Autoskill active: Fires whenever ready during melee combat without condition checks.')
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                        local curXt = tonumber(entry.min_xtar) or 1
                        if curXt < 1 then curXt = 1 end
                        if curXt > 10 then curXt = 10 end
                        local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local xti = ImGui.Combo('##actmxt', curXt, xtOpts)
                        entry.min_xtar = xti
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Minimum number of active NPCs on XTarget required for this ability to fire.')
                        end
                        ImGui.SameLine()
                        local aboVal = ImGui.Checkbox('Burn##actbo', entry.burn_only or false)
                        entry.burn_only = aboVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Only fire when Burn Mode is ON.')
                        end
                    else
                        ImGui.SameLine(); ImGui.SetNextItemWidth(133)
                        local ti = ImGui.Combo('##actt', idxOf(COMBO_OPTIONS.TARGETS, entry.target), COMBO_OPTIONS.TARGETS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Target condition: who or what to use this ability on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                        end
                        entry.target = COMBO_OPTIONS.TARGETS[ti]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(116)
                        local wi = ImGui.Combo('##actw', idxOf(COMBO_OPTIONS.WHENS, entry.when), COMBO_OPTIONS.WHENS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Trigger condition: when this ability should be used (e.g. in combat, my HP <=, always).')
                        end
                        entry.when = COMBO_OPTIONS.WHENS[wi]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(57)
                        local curPct = tonumber(entry.pct)
                        if curPct == nil then curPct = 100 end
                        local isDis = (curPct == 0)
                        local pCount = 0
                        if isDis then pCount = UI.pushDisabledSliderStyle() end
                        local spVal = ImGui.SliderInt('##actp', curPct, 0, 100, isDis and 'Off' or '%d%%')
                        local isHov = ImGui.IsItemHovered()
                        if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                        entry.pct = spVal
                        if isHov then
                            if spVal == 0 then
                                UI.setTooltip('Ability is Disabled (0%). Drag slider above 0% to enable.')
                            else
                                UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this ability).', spVal))
                            end
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                        local curXt = tonumber(entry.min_xtar) or 1
                        if curXt < 1 then curXt = 1 end
                        if curXt > 10 then curXt = 10 end
                        local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local xti = ImGui.Combo('##actmxt', curXt, xtOpts)
                        entry.min_xtar = xti
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Minimum number of active NPCs on XTarget required for this ability to fire.')
                        end
                        ImGui.SameLine()
                        local sbrnVal = ImGui.Checkbox('Burn##actbrn', entry.burn_only or false)
                        entry.burn_only = sbrnVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Only fires when Burn Mode is ON.')
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(70)
                        local priVal = ImGui.SliderInt('##actpri', entry.priority or 50, 1, 99, 'Pri %d')
                        entry.priority = priVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Lower = tried first when more than one eligible ability is ready at the same time.')
                        end
                    end
                end
                loadout.actions[nm] = entry
                ImGui.PopID()
            end
        end
    end
        if not anyAction then
            ImGui.TextDisabled('  (no combat abilities found for your classes)')
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('No combat abilities found for your current character classes.')
            end
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.EndTabItem()
end

-- UI: activated AAs tab
function UI.drawAATab()
    if not ImGui.BeginTabItem('AAs') then return end
    ImGui.TextWrapped('Activated Alternate Advancements (each has its own timer -- all fire when ready). Grouped by cooldown.')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Activated Alternate Advancement abilities operate on independent cooldown timers and fire automatically when their conditions are met.')
    end
    ctrl.aa_purchased_only = ImGui.Checkbox('Purchased Only', ctrl.aa_purchased_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show AAs you\'ve actually bought a rank in, not every AA your\nclass could ever train. Updates live as you spend AA points. Turn\noff to browse/plan ahead.')
    end
    ImGui.SameLine()
    if ImGui.Button('Popout Cooldowns##aaCdPop') then
        ctrl.show_cooldowns = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Opens the standalone popout Cooldown & Ability Monitor window.')
    end
    ImGui.Separator()

    -- Compact styling inside AA list: tighter item spacing & frame padding
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 3)

    if ImGui.BeginChild('aalist', 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        local TIER_ORDER = { 'short', 'mid', 'burn' }
        for _, tier in ipairs(TIER_ORDER) do
            local any = false
            for _, cls in ipairs(myClasses) do
                for sec, list in pairs(DATA.aas[cls] or {}) do
                    local isTuple = type(list) == 'table' and type(list[1]) == 'string' and tonumber(list[2]) ~= nil
                    local secNum = isTuple and tonumber(list[2]) or tonumber(sec) or 60
                    if aaTier(secNum) == tier and type(list) == 'table' then
                        local items = isTuple and { list } or list
                        for _, item in ipairs(items) do
                            local nm = type(item) == 'table' and (item[1] or item.name) or tostring(item)
                            if type(nm) == 'string' then nm = nm:match('^%s*(.-)%s*$') end
                            if not tonumber(nm) and (not ctrl.aa_purchased_only or hasAA(nm)) then
                                any = true
                                ImGui.PushID('aa_' .. tier .. '_' .. cls .. '_' .. nm)
                                local isFD = isFeignDeathAbility(nm)
                                local entry = loadout.aas[nm] or
                                    { cls = cls, target = 'F: Myself', when = isFD and 'my HP <=' or 'in combat', enabled = false, pct = isFD and 20 or 30, burn_only = false }
                                entry.enabled = ImGui.Checkbox('##en', entry.enabled)
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip(string.format('Enable or disable %s.', nm))
                                end
                                ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls) ---@diagnostic disable-line: param-type-mismatch
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip(string.format('Class: %s', cls))
                                end
                                ImGui.SameLine(); ImGui.Text(nm)
                                if ImGui.IsItemHovered() then
                                    runtime.showAATabTooltip(nm, cls, secNum, tier)
                                end
                                ImGui.SameLine(); ImGui.TextDisabled('(' .. fmtSec(secNum) .. ')')
                                if ImGui.IsItemHovered() then
                                    runtime.showAATabTooltip(nm, cls, secNum, tier)
                                end
                                if entry.enabled then
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(133)
                                    local ti = ImGui.Combo('##aat', idxOf(COMBO_OPTIONS.TARGETS, entry.target), COMBO_OPTIONS.TARGETS)
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Target condition: who or what to cast this ability on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                                    end
                                    entry.target = COMBO_OPTIONS.TARGETS[ti]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(116)
                                    local wi = ImGui.Combo('##aaw', idxOf(COMBO_OPTIONS.WHENS, entry.when), COMBO_OPTIONS.WHENS)
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Trigger condition: when this ability should be cast (e.g. in combat, HP <=, my Mana <=, missing buff, always).')
                                    end
                                    entry.when = COMBO_OPTIONS.WHENS[wi]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(57)
                                    local curPct = tonumber(entry.pct)
                                    if curPct == nil then curPct = 30 end
                                    local isDis = (curPct == 0)
                                    local pCount = 0
                                    if isDis then pCount = UI.pushDisabledSliderStyle() end
                                    local newPct = ImGui.SliderInt('##aap', curPct, 0, 100, isDis and 'Off' or '%d%%')
                                    local isHov = ImGui.IsItemHovered()
                                    if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                                    entry.pct = newPct
                                    if isHov then
                                        if newPct == 0 then
                                            UI.setTooltip('Ability is Disabled (0%). Drag slider above 0% to enable.')
                                        else
                                            UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this ability).', newPct))
                                        end
                                    end
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                                    local curXt = tonumber(entry.min_xtar) or 1
                                    if curXt < 1 then curXt = 1 end
                                    if curXt > 10 then curXt = 10 end
                                    local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                                    local xti = ImGui.Combo('##aamxt', curXt, xtOpts)
                                    entry.min_xtar = xti
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip(
                                            'Minimum number of active NPCs on XTarget required for this AA to fire.')
                                    end
                                    ImGui.SameLine()
                                    local aaboVal = ImGui.Checkbox('Burn##bo', entry.burn_only or false)
                                    entry.burn_only = aaboVal
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Only fire this AA when Burn Mode is ON.')
                                    end
                                end
                                loadout.aas[nm] = entry
                                ImGui.PopID()
                            end
                        end
                    end
                end
            end
            if any then ImGui.Separator() end
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.EndTabItem()
end

function runtime.wrapText(text, maxLineLen)
    if not text or text == '' then return '' end
    maxLineLen = maxLineLen or 60
    local lines = {}
    for paragraph in tostring(text):gmatch("([^\r\n]+)") do
        local line = ''
        for word in paragraph:gmatch("%S+") do
            if #line == 0 then
                line = word
            elseif #line + 1 + #word <= maxLineLen then
                line = line .. ' ' .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        if #line > 0 then
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, '\n')
end

function runtime.getAADescription(itm)
    if not itm then return '' end
    local name, id, existingDesc
    if type(itm) == 'table' then
        name = itm.name or (itm[1] and tostring(itm[1]))
        id = itm.id or (itm[2] and tonumber(itm[2]))
        existingDesc = itm.description
    else
        name = tostring(itm)
    end
    if not name or name == '' then return '' end

    if existingDesc and existingDesc ~= '' then
        return existingDesc
    end

    if runtime.cachedAAData and runtime.cachedAAData[name] and runtime.cachedAAData[name].description and runtime.cachedAAData[name].description ~= '' then
        if type(itm) == 'table' then itm.description = runtime.cachedAAData[name].description end
        return runtime.cachedAAData[name].description
    end

    local desc = ''

    pcall(function()
        if mq.TLO.Me and mq.TLO.Me.AltAbility then
            local ma = mq.TLO.Me.AltAbility(name)
            if ma and ma() then
                if ma.Description then
                    local d = ma.Description()
                    if d and d ~= '' then desc = tostring(d) end
                end
                if desc == '' and ma.Spell and ma.Spell.Description then
                    local sd = ma.Spell.Description()
                    if sd and sd ~= '' then desc = tostring(sd) end
                end
            end
        end
        if desc == '' and mq.TLO.AltAbility then
            local ga = mq.TLO.AltAbility(name)
            if ga and ga() then
                if ga.Description then
                    local d = ga.Description()
                    if d and d ~= '' then desc = tostring(d) end
                end
                if desc == '' and ga.Spell and ga.Spell.Description then
                    local sd = ga.Spell.Description()
                    if sd and sd ~= '' then desc = tostring(sd) end
                end
            end
            if desc == '' and id and id > 0 then
                local gaId = mq.TLO.AltAbility(id)
                if gaId and gaId() then
                    if gaId.Description then
                        local d = gaId.Description()
                        if d and d ~= '' then desc = tostring(d) end
                    end
                    if desc == '' and gaId.Spell and gaId.Spell.Description then
                        local sd = gaId.Spell.Description()
                        if sd and sd ~= '' then desc = tostring(sd) end
                    end
                end
            end
        end
    end)

    if desc and desc ~= '' then
        if type(itm) == 'table' then itm.description = desc end
        if runtime.cachedAAData and runtime.cachedAAData[name] then
            runtime.cachedAAData[name].description = desc
        end
    end

    return desc
end

function runtime.showAATooltip(itm)
    if not itm then return end
    local desc = runtime.getAADescription and runtime.getAADescription(itm)
    local wrappedDesc = (desc and desc ~= '') and runtime.wrapText(desc, 55) or nil
    local tip
    if wrappedDesc and wrappedDesc ~= '' then
        tip = string.format('%s\nCurrent Rank: %d / %d\nNext Rank Cost: %d AA\nPoints Spent: %d AA\n\n%s',
            itm.name, itm.rank, itm.maxRank, itm.cost, itm.pointsSpent or 0, wrappedDesc)
    else
        tip = string.format('%s\nCurrent Rank: %d / %d\nNext Rank Cost: %d AA\nPoints Spent: %d AA',
            itm.name, itm.rank, itm.maxRank, itm.cost, itm.pointsSpent or 0)
    end
    ImGui.SetTooltip('%s', tip)
end

function runtime.showAATabTooltip(name, cls, secNum, tier)
    if not name or name == '' then return end
    local desc = runtime.getAADescription and runtime.getAADescription(name)
    local wrappedDesc = (desc and desc ~= '') and runtime.wrapText(desc, 55) or nil

    local header = string.format('AA Ability: %s', name)
    local meta = {}
    if cls and cls ~= '' then
        table.insert(meta, string.format('Class: %s', cls))
    end
    if secNum and tonumber(secNum) then
        table.insert(meta, string.format('Cooldown: %s (%s)', fmtSec(tonumber(secNum)), tier or aaTier(tonumber(secNum))))
    end

    local rank, maxRank
    if runtime.cachedAAData and runtime.cachedAAData[name] then
        rank = runtime.cachedAAData[name].rank
        maxRank = runtime.cachedAAData[name].maxRank
    end
    if not rank or not maxRank then
        pcall(function()
            if not rank and mq.TLO.Me and mq.TLO.Me.AltAbility then
                local aa = mq.TLO.Me.AltAbility(name)
                if aa and aa() and aa.Rank then
                    rank = tonumber(aa.Rank() or 0)
                end
            end
            if not maxRank and mq.TLO.AltAbility then
                local ga = mq.TLO.AltAbility(name)
                if ga and ga() and ga.MaxRank then
                    maxRank = tonumber(ga.MaxRank() or 0)
                end
            end
        end)
    end
    if rank and maxRank and maxRank > 0 then
        table.insert(meta, string.format('Rank: %d/%d', rank, maxRank))
    elseif rank and rank > 0 then
        table.insert(meta, string.format('Rank: %d', rank))
    end

    local lines = { header }
    if #meta > 0 then
        table.insert(lines, table.concat(meta, '  |  '))
    end
    if wrappedDesc and wrappedDesc ~= '' then
        table.insert(lines, '')
        table.insert(lines, wrappedDesc)
    end

    UI.setTooltip('%s', table.concat(lines, '\n'))
end

function UI.drawDiscTab()
    if not ImGui.BeginTabItem('Disciplines') then return end
    ImGui.TextWrapped(
        'Disciplines (/disc) -- no cooldown data from the extractor to group by tier, so listed flat per class. '
        ..
        'Boss Only gates a disc to Named targets (save long-cooldown offensive discs like Mighty Strike for real fights, while '
        ..
        'a survival disc like Whirlwind can stay on for regular grinding). Priority: when multiple discs are eligible at once, '
        .. 'lower numbers are tried first -- if the top one is still on cooldown, the next one down the list fires instead. '
        .. 'Innate combat abilities (Kick, Bash, Mend, Monk abilities, etc.) are configured on the Abilities tab.')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Combat disciplines share timer groups and are evaluated in order of assigned priority.')
    end
    ctrl.disc_trained_only = ImGui.Checkbox('Trained Only', ctrl.disc_trained_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show disciplines you\'ve actually trained, not every disc your\nclass could ever learn. Updates live as you train new ones. Turn\noff to browse/plan ahead.')
    end
    ImGui.SameLine()
    if ImGui.Button('Popout Cooldowns##discCdPop') then
        ctrl.show_cooldowns = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Opens the standalone popout Cooldown & Ability Monitor window.')
    end
    ImGui.Separator()
    -- Compact styling inside disciplines list: tighter item spacing & frame padding
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 3)

    if ImGui.BeginChild('disclist', 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        local anyDisc = false
        for _, cls in ipairs(myClasses) do
            for _, row in ipairs(DATA.discs[cls] or {}) do
                local nm, lv = row[1], row[2]
                if not ctrl.disc_trained_only or hasDisc(nm) then
                    anyDisc = true
                    ImGui.PushID('disc' .. cls .. nm)
                    local entry = loadout.discs[nm] or
                        { cls = cls, target = 'F: Myself', when = 'HP <=', enabled = false, pct = 30, boss_only = false, burn_only = false, priority = 50 }
                    entry.enabled = ImGui.Checkbox('##en', entry.enabled)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(string.format('Enable or disable %s.', nm))
                    end
                    ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls) ---@diagnostic disable-line: param-type-mismatch
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(string.format('Class: %s', cls))
                    end
                    ImGui.SameLine(); ImGui.Text(nm)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(string.format('Discipline: %s', nm))
                    end
                    ImGui.SameLine(); ImGui.TextDisabled('(L' .. lv .. ')')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(string.format('Required Level: %s', tostring(lv)))
                    end
                    if entry.enabled then
                        ImGui.SameLine(); ImGui.SetNextItemWidth(133)
                        local ti = ImGui.Combo('##dt', idxOf(COMBO_OPTIONS.TARGETS, entry.target), COMBO_OPTIONS.TARGETS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Target condition: who or what to use this discipline on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                        end
                        entry.target = COMBO_OPTIONS.TARGETS[ti]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(116)
                        local wi = ImGui.Combo('##dw', idxOf(COMBO_OPTIONS.WHENS, entry.when), COMBO_OPTIONS.WHENS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Trigger condition: when this discipline should be used (e.g. HP <=, in combat, my Mana <=, always).')
                        end
                        entry.when = COMBO_OPTIONS.WHENS[wi]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(57)
                        local curPct = tonumber(entry.pct)
                        if curPct == nil then curPct = 30 end
                        local isDis = (curPct == 0)
                        local pCount = 0
                        if isDis then pCount = UI.pushDisabledSliderStyle() end
                        local dpVal = ImGui.SliderInt('##dp', curPct, 0, 100, isDis and 'Off' or '%d%%')
                        local isHov = ImGui.IsItemHovered()
                        if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                        entry.pct = dpVal
                        if isHov then
                            if dpVal == 0 then
                                UI.setTooltip('Discipline is Disabled (0%). Drag slider above 0% to enable.')
                            else
                                UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this discipline).', dpVal))
                            end
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(35)
                        local curXt = tonumber(entry.min_xtar) or 1
                        if curXt < 1 then curXt = 1 end
                        if curXt > 10 then curXt = 10 end
                        local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local xti = ImGui.Combo('##dmxt', curXt, xtOpts)
                        entry.min_xtar = xti
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(
                                'Minimum number of active NPCs on XTarget required for this discipline to fire.')
                        end
                        ImGui.SameLine()
                        local dboVal = ImGui.Checkbox('Boss##bo', entry.boss_only)
                        entry.boss_only = dboVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(
                                'Only fires if the resolved target is a Named mob.')
                        end
                        ImGui.SameLine()
                        local dbrnVal = ImGui.Checkbox('Burn##brn', entry.burn_only or false)
                        entry.burn_only = dbrnVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(
                                'Only fires when Burn Mode is ON.')
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(70)
                        local priVal = ImGui.SliderInt('##pri', entry.priority or 50, 1, 99, 'Pri %d')
                        entry.priority = priVal
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(
                                'Lower = tried first when more than one eligible\ndisc is ready at the same time.')
                        end
                    end
                    loadout.discs[nm] = entry
                    ImGui.PopID()
                end
            end
        end
        if not anyDisc then
            ImGui.TextDisabled('  (none for your classes)')
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('No combat disciplines found for your current character classes.')
            end
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.EndTabItem()
end

local function setManualHunterPetHold(on, force)
    if not hasActivePet() then return end
    if on then
        if force or petState.manualHunterHold ~= true then
            mq.cmd('/say #petcmd hold all')
            mq.cmd('/say #petcmd ghold on')
            mq.cmd('/pet back off')
            petState.manualHunterHold = true
            petState.petHoldActive = true
        end
    else
        if force or petState.manualHunterHold ~= false then
            mq.cmd('/say #petcmd ghold off')
            petState.manualHunterHold = false
            petState.petHoldActive = false
        end
    end
end

-- UI: Action controls (Start / Pause, Burn)
function UI.drawActionControls()
    if ctrl.running then
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local pCount = 0
        if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.18, 0.70, 0.28, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.08, 0.40, 0.15, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.Text, 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

        if ImGui.Button('PAUSE', 130, 24) then
            if ctrl.mode == 'Manual' then
                setManualHunterPetHold(true, true)
            else
                setManualHunterPetHold(false, true)
            end
            ctrl.running = false
            if runtime.fullStop then runtime.fullStop() end
        end

        if pCount > 0 then
            pcall(ImGui.PopStyleColor, pCount)
        end
    else
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local pCount = 0
        if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.65, 0.15, 0.15, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.80, 0.22, 0.22, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.50, 0.10, 0.10, 1.0) then pCount = pCount + 1 end
        if ImGui.Button('START', 130, 24) then
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            ctrl.running = true
            runtime.wasRunning = true
            if not navLoaded() and ctrl.mode ~= 'Manual' then
                mq.cmd('/popup [Triune] WARNING: MQ2Nav is NOT loaded!')
                print('\ar[Triune WARNING]\ax MQ2Nav plugin is not loaded! Movement and navigation require MQ2Nav (/plugin mq2nav).')
            elseif not navMeshLoaded() and ctrl.mode ~= 'Manual' then
                local curZone = mq.TLO.Zone.ShortName() or 'current zone'
                mq.cmdf('/popup [Triune] WARNING: No NavMesh for %s!', curZone)
                print(string.format('\ar[Triune WARNING]\ax No NavMesh loaded for zone "%s"! Movement and pathing require a zone navmesh.', curZone))
            end
            if not stickLoaded() and ctrl.mode ~= 'Manual' then
                mq.cmd('/popup [Triune] WARNING: MQ2MoveUtils is NOT loaded!')
                print('\ar[Triune WARNING]\ax MQ2MoveUtils plugin is not loaded! Target stick and melee positioning require MQ2MoveUtils (/plugin mq2moveutils).')
            end
        end

        if pCount > 0 then
            pcall(ImGui.PopStyleColor, pCount)
        end
    end
    ImGui.SameLine()
    if ctrl.burn then
        local nowSec = os.clock()
        local pulse = (math.sin(nowSec * 8.0) + 1.0) * 0.5
        local r = 0.50 + (0.45 * pulse)
        local g = 0.05 + (0.08 * pulse)
        local b = 0.05 + (0.08 * pulse)
        local rH = math.min(1.0, r + 0.15)
        local gH = math.min(1.0, g + 0.15)
        local bH = math.min(1.0, b + 0.15)

        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local pCount = 0
        if Col and pcall(ImGui.PushStyleColor, Col.Button, r, g, b, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, rH, gH, bH, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.70, 0.00, 0.00, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.Text, 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

        if ImGui.Button('BURN (ON)##btnBurn', 130, 24) then
            ctrl.burn = false
            print('\ag[Triune]\ax Burn mode DISABLED.')
        end

        if pCount > 0 then
            pcall(ImGui.PopStyleColor, pCount)
        end
    else
        if ImGui.Button('BURN (OFF)##btnBurn', 130, 24) then
            ctrl.burn = true
            print('\ag[Triune]\ax Burn mode ENABLED!')
        end
    end
    if ImGui.IsItemHovered() then
        UI.setTooltip(
            'Enable/disable Burn Mode. When enabled, spells, AAs, and disciplines marked "Burn Only" will fire.\nTurns off automatically when extended target list clears.')
    end

    ImGui.SameLine(0, 14)
    local modeStr = ctrl.mode or 'Manual'
    if MODES.SUBMODES[ctrl.mode] and ctrl.submode then
        modeStr = string.format('%s (%s)', ctrl.mode, ctrl.submode)
    end
    ImGui.AlignTextToFramePadding()
    ImGui.TextDisabled('Mode:')
    ImGui.SameLine()
    if ctrl.running then
        accent(GOLD, modeStr)
        ImGui.SameLine()
        accent(GOOD, '[RUNNING]')
    else
        accent(MUTED, modeStr)
        ImGui.SameLine()
        accent(WARN, '[PAUSED]')
    end
    if ImGui.IsItemHovered() then
        UI.setTooltip('Active combat mode and engine execution state.')
    end
end

function UI.drawStatusProgressBar(fraction, w, h, text, r, g, b, a)
    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
    local pCount = 0
    if Col and Col.PlotHistogram and r and g and b then
        if pcall(ImGui.PushStyleColor, Col.PlotHistogram, r, g, b, a or 1.0) then
            pCount = pCount + 1
        end
    end
    local clamped = math.max(0.0, math.min(1.0, fraction or 0.0))
    ImGui.ProgressBar(clamped, w or -1, h or 16, text or '')
    if pCount > 0 then
        pcall(ImGui.PopStyleColor, pCount)
    end
end

function UI.getConColorRgb(conName)
    local c = tostring(conName or ''):upper()
    if c == 'GREY' or c == 'GRAY' then return { 0.60, 0.60, 0.60, 1.0 }
    elseif c == 'GREEN' then return { 0.25, 0.90, 0.35, 1.0 }
    elseif c == 'LIGHT BLUE' or c == 'LIGHTBLUE' then return { 0.35, 0.75, 1.0, 1.0 }
    elseif c == 'BLUE' then return { 0.20, 0.50, 1.0, 1.0 }
    elseif c == 'WHITE' then return { 0.95, 0.95, 0.95, 1.0 }
    elseif c == 'YELLOW' then return { 1.0, 0.85, 0.20, 1.0 }
    elseif c == 'RED' then return { 1.0, 0.28, 0.28, 1.0 }
    end
    return { 0.75, 0.75, 0.75, 1.0 }
end

function UI.drawCollapsingStatusHeader(key, label, id)
    ctrl.status_collapsed = ctrl.status_collapsed or {}
    runtime.statusHeaderInit = runtime.statusHeaderInit or {}
    if not runtime.statusHeaderInit[key] then
        runtime.statusHeaderInit[key] = true
        if ImGui.SetNextItemOpen then
            pcall(ImGui.SetNextItemOpen, not ctrl.status_collapsed[key])
        end
    end
    local flags = (ctrl.status_collapsed[key] and 0) or ImGuiTreeNodeFlags.DefaultOpen
    local isOpen = ImGui.CollapsingHeader(label .. '###' .. id, flags)
    local isCollapsed = not isOpen
    if ctrl.status_collapsed[key] ~= isCollapsed then
        ctrl.status_collapsed[key] = isCollapsed
        runtime.saveLoadout(true)
    end
    return isOpen
end

-- ============================================================================
-- Multi-tier Target of Target (ToT) / Aggro Holder resolution helper.
-- MacroQuest exposes multiple complementary paths depending on group leadership AA,
-- whether the target is an NPC, PC, or Pet, and whether combat aggro is active.
-- ============================================================================
function UI.resolveTargetOfTarget(targetId)
    local totId = 0
    local totName = nil
    local totHpPct = nil
    local myPctAggro = 0
    local isAggroHolder = false

    if not targetId or targetId <= 0 then
        return totName, totId, totHpPct, myPctAggro, isAggroHolder
    end

    pcall(function()
        myPctAggro = mq.TLO.Target.PctAggro() or 0
    end)

    -- 1. Check Target.TargetOfTarget (active when Group or Raid Leadership ToT is available)
    pcall(function()
        local tot = mq.TLO.Target.TargetOfTarget
        if tot and tot() and (tot.ID() or 0) > 0 then
            totId = tot.ID() or 0
            totName = tot.CleanName() or ''
            totHpPct = tot.PctHPs() or 0
        end
    end)

    -- 2. Check Target.AggroHolder (returns the mob's actual combat target without needing leadership AA)
    if not totName or totName == '' or totId <= 0 then
        pcall(function()
            local ah = mq.TLO.Target.AggroHolder
            if ah and ah() and (ah.ID() or 0) > 0 then
                totId = ah.ID() or 0
                totName = ah.CleanName() or ''
                totHpPct = ah.PctHPs() or 0
                isAggroHolder = true
            end
        end)
    end

    -- 3. Check Me.TargetOfTarget (Character TLO)
    if not totName or totName == '' or totId <= 0 then
        pcall(function()
            local mtot = mq.TLO.Me.TargetOfTarget
            if mtot and mtot() and (mtot.ID() or 0) > 0 then
                totId = mtot.ID() or 0
                totName = mtot.CleanName() or ''
                totHpPct = mtot.PctHPs() or 0
            end
        end)
    end

    -- 4. Check Spawn(targetId).TargetOfTarget and Spawn(targetId).AggroHolder
    if not totName or totName == '' or totId <= 0 then
        pcall(function()
            local sp = mq.TLO.Spawn(targetId)
            if sp and sp() then
                local stot = sp.TargetOfTarget
                if stot and stot() and (stot.ID() or 0) > 0 then
                    totId = stot.ID() or 0
                    totName = stot.CleanName() or ''
                    totHpPct = stot.PctHPs() or 0
                else
                    local sah = sp.AggroHolder
                    if sah and sah() and (sah.ID() or 0) > 0 then
                        totId = sah.ID() or 0
                        totName = sah.CleanName() or ''
                        totHpPct = sah.PctHPs() or 0
                        isAggroHolder = true
                    end
                end
            end
        end)
    end

    -- 5. If target is player's own pet, check Me.Pet.Target or Me.Pet.Following
    if not totName or totName == '' or totId <= 0 then
        pcall(function()
            local myPetId = mq.TLO.Me.Pet.ID() or 0
            if myPetId > 0 and targetId == myPetId then
                local pt = mq.TLO.Me.Pet.Target
                if pt and pt() and (pt.ID() or 0) > 0 then
                    totId = pt.ID() or 0
                    totName = pt.CleanName() or ''
                    totHpPct = pt.PctHPs() or 0
                else
                    local pf = mq.TLO.Me.Pet.Following
                    if pf and pf() and (pf.ID() or 0) > 0 and pf.Type() == 'NPC' then
                        totId = pf.ID() or 0
                        totName = pf.CleanName() or ''
                        totHpPct = pf.PctHPs() or 0
                    end
                end
            end
        end)
    end

    -- 6. Fallback: If target is an NPC in combat with player and player has 100% aggro
    if (not totName or totName == '' or totId <= 0) and myPctAggro >= 100 then
        pcall(function()
            if mq.TLO.Target.Type() == 'NPC' then
                totId = mq.TLO.Me.ID() or 0
                totName = mq.TLO.Me.CleanName() or 'Myself'
                totHpPct = mq.TLO.Me.PctHPs() or 100
                isAggroHolder = true
            end
        end)
    end

    -- 7. If totId is valid but totHpPct is missing or nil, query spawn directly
    if totId > 0 and (not totHpPct or totHpPct == 0) then
        pcall(function()
            local s = mq.TLO.Spawn(totId)
            if s and s() then
                totHpPct = s.PctHPs() or 0
                if not totName or totName == '' then
                    totName = s.CleanName() or ''
                end
            end
        end)
    end

    return totName, totId, totHpPct, myPctAggro, isAggroHolder
end

-- UI: status tab
function UI.drawStatusTab()
    if not ImGui.BeginTabItem('Status') then return end

    -- 1. Live Engine & Mode Overview with Integrated Session Tracker
    local inCombat = hasActualNPCXtarget()
    local elapsedSec = os.time() - (runtime.trackStartTime or os.time())
    local elapsedHrs = math.max(elapsedSec / 3600.0, 0)
    local aaGained = (runtime.startAA and runtime.currentAA) and math.max(0, runtime.currentAA - runtime.startAA) or 0
    local aaRate = (elapsedHrs > 0.0001) and (aaGained / elapsedHrs) or 0.0
    local platGained = (runtime.startPlat and runtime.currentPlat) and (runtime.currentPlat - runtime.startPlat) or 0
    local platRate = (elapsedHrs > 0.0001) and (platGained / elapsedHrs) or 0.0

    local m = math.floor(elapsedSec / 60)
    local s = elapsedSec % 60
    local h = math.floor(m / 60)
    m = m % 60
    local timeStr = h > 0 and string.format('%dh %dm %ds', h, m, s) or string.format('%dm %ds', m, s)

    accent(GOLD, 'Overview')
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(ARC, timeStr)
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOOD, string.format('AA/hr: %.1f (%+.2f)', aaRate, aaGained))
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOLD, string.format('Plat/hr: %.1f p (%+d p)', platRate, platGained))
    ImGui.SameLine()
    if ImGui.Button('Reset##statResetTrack', 46, 18) then
        UI.resetTracker()
    end
    if ImGui.IsItemHovered() then
        UI.setTooltip(string.format(
            "Session Tracker (%s):\n" ..
            "-------------------------------\n" ..
            "AA/hr Rate:   %.2f / hr\n" ..
            "Total AA:     %+.2f gained (Current: %.2f | Start: %.2f)\n" ..
            "-------------------------------\n" ..
            "Plat/hr Rate: %.1f p/hr\n" ..
            "Total Plat:   %+d p gained (Current: %dp | Start: %dp)\n" ..
            "-------------------------------\n" ..
            "Click 'Reset' to restart session.",
            timeStr, aaRate, aaGained, runtime.currentAA or 0, runtime.startAA or 0,
            platRate, platGained, runtime.currentPlat or 0, runtime.startPlat or 0
        ))
    end

    local statusTableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
    if ImGui.BeginTable('##StatusOverviewTable', 4, statusTableFlags) then
        ImGui.TableSetupColumn('Engine State', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Active Mode', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Combat & Attack Style', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Subsystems', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableHeadersRow()

        ImGui.TableNextRow()
        -- Column 1: Engine State
        ImGui.TableNextColumn()
        if ctrl.running then
            accent(GOOD, '• ENGINE: RUNNING')
        else
            accent(WARN, '• ENGINE: PAUSED')
        end
        if inCombat then
            accent({ 1.0, 0.35, 0.35, 1.0 }, '• COMBAT: IN COMBAT')
        else
            accent(GOOD, '• COMBAT: STANDBY / IDLE')
        end

        -- Column 2: Active Mode
        ImGui.TableNextColumn()
        local modeStr = ctrl.mode or 'Manual'
        if MODES.SUBMODES[ctrl.mode] and ctrl.submode then
            modeStr = string.format('%s (%s)', ctrl.mode, ctrl.submode)
        end
        accent(GOLD, '• Mode: ' .. modeStr)
        local descKey = ctrl.mode
        if MODES.SUBMODES[ctrl.mode] and ctrl.submode then
            descKey = string.format('%s:%s', ctrl.mode, ctrl.submode)
        end
        ImGui.TextDisabled(MODES.SUB_DESC[descKey] or MODES.DESC[ctrl.mode] or '')

        -- Column 3: Combat & Attack Style
        ImGui.TableNextColumn()
        accent(ARC, '• Style: Melee')
        if ctrl.burn then
            accent({ 1.0, 0.30, 0.30, 1.0 }, '• BURN: ACTIVE')
        else
            ImGui.TextDisabled('• Burn: Inactive')
        end

        -- Column 4: Subsystems (MedBreak, Cast)
        ImGui.TableNextColumn()
        if runtime.medBreakActive then
            accent(ARC, '• MedBreak: RESTING')
        else
            ImGui.TextDisabled('• MedBreak: Inactive')
        end
        local castingName = nil
        pcall(function() castingName = mq.TLO.Me.Casting.Name() end)
        if castingName and castingName ~= '' and castingName ~= 'NULL' then
            accent(GOOD, '• Cast: ' .. castingName)
        else
            ImGui.TextDisabled('• Cast: Idle')
        end

        ImGui.EndTable()
    end

    -- 2. Current Target & Threat Card
    if UI.drawCollapsingStatusHeader('target', 'Current Target & Threat', 'statusTarget') then
        if ctrl.mode == 'Assist' or (ctrl.ma_id and ctrl.ma_id > 0) or (ctrl.ma_name and ctrl.ma_name ~= '') then
            local maInfo = runtime.getMaTargetInfo and runtime.getMaTargetInfo()
            if maInfo and maInfo.hasMA then
                accent(GOLD, 'Main Assist:')
                ImGui.SameLine(); ImGui.Text(string.format('%s (ID: %d)', maInfo.maName, maInfo.maId))
                ImGui.SameLine(); ImGui.TextDisabled('|')
                ImGui.SameLine()
                if maInfo.hasTarget then
                    local clsStr = (maInfo.targetClass ~= '') and (' [' .. maInfo.targetClass .. ']') or ''
                    accent(ARC, 'MA Target:')
                    ImGui.SameLine()
                    local conCol = UI.getConColorRgb(maInfo.targetCon)
                    accent(conCol, string.format('%s%s (ID: %d, %d%% HP, %.1fft)', maInfo.targetName, clsStr, maInfo.targetId, maInfo.targetHp, maInfo.targetDist))
                    ImGui.SameLine()
                    if ImGui.Button('Target MA Target##statCardTargMA', 125, 18) then
                        mq.cmdf('/target id %d', maInfo.targetId)
                    end
                    if ImGui.IsItemHovered() then UI.setTooltip(string.format('Acquire Main Assist target: %s (ID %d)', maInfo.targetName, maInfo.targetId)) end
                else
                    accent(MUTED, 'MA Target: No Target')
                end
                ImGui.Separator()
            end
        end

        local tId, tName, tLvl, tClass, tRace, tType, tCon, tHpPct, tCurHp, tMaxHp, tDist, tLoS, tHeading
        local tTotPct, tMyAggro, tMySecAggro
        pcall(function()
            tId = mq.TLO.Target.ID()
            if tId and tId > 0 then
                tName = mq.TLO.Target.CleanName() or 'Unknown'
                tLvl = mq.TLO.Target.Level() or 0
                tClass = mq.TLO.Target.Class.ShortName() or '?'
                tRace = mq.TLO.Target.Race.Name() or '?'
                tType = mq.TLO.Target.Type() or 'NPC'
                tCon = mq.TLO.Target.ConColor() or 'White'
                tHpPct = mq.TLO.Target.PctHPs() or 0
                tCurHp = mq.TLO.Target.CurrentHPs() or 0
                tMaxHp = mq.TLO.Target.MaxHPs() or 0
                tDist = mq.TLO.Target.Distance() or 0
                tLoS = mq.TLO.Target.LineOfSight() or false
                pcall(function() tHeading = mq.TLO.Target.Heading.Degrees() or 0 end)
                tMyAggro = mq.TLO.Target.SecondaryPctAggro() or 0
                tMySecAggro = mq.TLO.Me.SecondaryPctAggro() or 0
            end
        end)

        local tTotName, _, _, myPctAggro = UI.resolveTargetOfTarget(tId)
        tTotPct = myPctAggro

        if tId and tId > 0 and tName then
            local conCol = UI.getConColorRgb(tCon)
            accent(conCol, string.format('[Lvl %d %s %s] %s (ID: %d)', tLvl or 0, tClass or '?', tRace or '?', tName, tId))
            ImGui.SameLine(); ImGui.TextDisabled('|')
            ImGui.SameLine(); accent(conCol, string.format('Con: %s', tCon or 'White'))
            ImGui.SameLine(); ImGui.TextDisabled('|')
            ImGui.SameLine(); ImGui.TextDisabled(string.format('Type: %s', tType or 'NPC'))

            local isHostile = isHostileTarget and isHostileTarget(tId)
            local isXtar = isXTargetId and isXTargetId(tId)
            ImGui.SameLine(); ImGui.TextDisabled('|')
            ImGui.SameLine()
            if isHostile then
                accent({ 1.0, 0.35, 0.35, 1.0 }, 'Hostile')
            else
                accent(GOOD, 'Friendly/Neutral')
            end
            if isXtar then
                ImGui.SameLine(); accent(WARN, '[On XTarget]')
            end

            -- Health Bar with Dynamic Color
            local hpFrac = (tHpPct or 0) / 100.0
            local r, g, b = 0.25, 0.80, 0.35
            if (tHpPct or 0) <= 20 then
                r, g, b = 0.90, 0.20, 0.20
            elseif (tHpPct or 0) <= 50 then
                r, g, b = 0.95, 0.75, 0.20
            end
            local hpStr = string.format('%d%% HP (%s / %s)', tHpPct or 0,
                (tCurHp and tCurHp > 0) and tostring(tCurHp) or '?',
                (tMaxHp and tMaxHp > 0) and tostring(tMaxHp) or '?')
            UI.drawStatusProgressBar(hpFrac, -1, 18, hpStr, r, g, b, 1.0)

            -- Target Metrics Table
            local targetTableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
            if ImGui.BeginTable('##StatusTargetMetricsTable', 4, targetTableFlags) then
                ImGui.TableSetupColumn('Distance & Range', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Line of Sight & Heading', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Aggro Holder (ToT)', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Threat Metrics', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableHeadersRow()

                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                accent(ARC, string.format('Distance: %.1f ft', tDist or 0))
                local inMelee = false
                pcall(function()
                    local maxD = (runtime.maxMeleeDistance and runtime.maxMeleeDistance(mq.TLO.Target.ID())) or 15
                    inMelee = (tDist or 999) <= maxD
                end)
                if inMelee then
                    accent(GOOD, 'In Melee Range: Yes')
                else
                    ImGui.TextDisabled('In Melee Range: No')
                end

                ImGui.TableNextColumn()
                if tLoS then
                    accent(GOOD, 'Line of Sight: YES')
                else
                    accent(WARN, 'Line of Sight: NO')
                end
                ImGui.TextDisabled(string.format('Heading: %.0f°', tHeading or 0))

                ImGui.TableNextColumn()
                if tTotName and tTotName ~= 'None' and tTotName ~= '' then
                    local isMe = (myName and tTotName == myName)
                    if isMe then
                        accent({ 1.0, 0.35, 0.35, 1.0 }, 'Tanking: YOU (' .. tostring(tTotPct or 100) .. '%)')
                    else
                        accent(GOOD, string.format('Holding: %s (%d%%)', tTotName, tTotPct or 0))
                    end
                else
                    ImGui.TextDisabled('Holding Aggro: None / Unknown')
                end

                ImGui.TableNextColumn()
                ImGui.Text(string.format('My Aggro: %d%%', tMyAggro or 0))
                ImGui.TextDisabled(string.format('Secondary: %d%%', tMySecAggro or 0))

                ImGui.EndTable()
            end

            -- Target Quick Actions Toolbar
            if ImGui.Button('Face Target##statFace') then
                mq.cmd('/face fast')
            end
            if ImGui.IsItemHovered() then UI.setTooltip('Turns character directly toward current target.') end

            ImGui.SameLine()
            local isAttacking = mq.TLO.Me.Combat() or false
            if isAttacking then
                if ImGui.Button('Attack OFF##statAtk') then mq.cmd('/attack off') end
            else
                if ImGui.Button('Attack ON##statAtk') then mq.cmd('/attack on') end
            end
            if ImGui.IsItemHovered() then UI.setTooltip('Toggles auto-attack on/off.') end

            ImGui.SameLine()
            if ImGui.Button('Clear Target##statClear') then
                runtime.clearTarget()
            end
            if ImGui.IsItemHovered() then UI.setTooltip('Clears current target selection.') end

            ImGui.SameLine()
            if runtime.isPullListed(tName) then
                if ImGui.Button('- Pull List##statRemPull') then runtime.removePull(tName) end
            else
                if ImGui.Button('+ Pull List##statAddPull') then runtime.addPull(tName) end
            end
            if ImGui.IsItemHovered() then UI.setTooltip('Adds/removes target name to/from the Puller include list.') end

            ImGui.SameLine()
            if isIgnored(tName) then
                if ImGui.Button('- Ignore List##statRemIgnore') then runtime.removeIgnore(tName) end
            else
                if ImGui.Button('+ Ignore List##statAddIgnore') then runtime.addIgnore(tName) end
            end
            if ImGui.IsItemHovered() then UI.setTooltip('Adds/removes target name to/from the global ignore list.') end
        else
            accent(MUTED, 'No target currently selected.')
            ImGui.TextDisabled('Select a target in EverQuest or use the Extended Target list below to acquire a target.')
        end
    end


    -- 3. Player, Gestalt Trio & Pet Vitals Card
    if UI.drawCollapsingStatusHeader('vitals', 'Player, Gestalt Trio & Pet Vitals', 'statusVitals') then
        local myHpPct, myCurHp, myMaxHp, myManaPct, myCurMana, myMaxMana, myEndPct, myCurEnd, myMaxEnd
        local isDuck, isSit, isFeign, isLev
        pcall(function()
            myHpPct = mq.TLO.Me.PctHPs() or 0
            myCurHp = mq.TLO.Me.CurrentHPs() or 0
            myMaxHp = mq.TLO.Me.MaxHPs() or 0
            myManaPct = mq.TLO.Me.PctMana() or 0
            myCurMana = mq.TLO.Me.CurrentMana() or 0
            myMaxMana = mq.TLO.Me.MaxMana() or 0
            myEndPct = mq.TLO.Me.PctEndurance() or 0
            myCurEnd = mq.TLO.Me.CurrentEndurance() or 0
            myMaxEnd = mq.TLO.Me.MaxEndurance() or 0
            isDuck = isDucking()
            isSit = isSitting()
            isFeign = mq.TLO.Me.Feigning() or false
            isLev = mq.TLO.Me.Levitating() or false
        end)

        -- Player HP Bar
        local r, g, b = 0.25, 0.80, 0.35
        if (myHpPct or 0) <= 25 then
            r, g, b = 0.90, 0.20, 0.20
        elseif (myHpPct or 0) <= 50 then
            r, g, b = 0.95, 0.75, 0.20
        end
        local hpStr = string.format('Player HP: %d%% (%d / %d)', myHpPct or 0, myCurHp or 0, myMaxHp or 0)
        UI.drawStatusProgressBar((myHpPct or 0) / 100.0, -1, 16, hpStr, r, g, b, 1.0)

        -- Player Mana Bar (if character has mana)
        if (myMaxMana or 0) > 0 then
            local manaStr = string.format('Player Mana: %d%% (%d / %d)', myManaPct or 0, myCurMana or 0, myMaxMana or 0)
            UI.drawStatusProgressBar((myManaPct or 0) / 100.0, -1, 14, manaStr, 0.25, 0.60, 0.95, 1.0)
        end

        -- Player Endurance Bar (if character has endurance)
        if (myMaxEnd or 0) > 0 then
            local endStr = string.format('Player Endurance: %d%% (%d / %d)', myEndPct or 0, myCurEnd or 0, myMaxEnd or 0)
            UI.drawStatusProgressBar((myEndPct or 0) / 100.0, -1, 14, endStr, 0.95, 0.60, 0.25, 1.0)
        end

        -- Status flags & Trio class badges
        accent(GOLD, 'Gestalt Trio:')
        for i = 1, 3 do
            local cls = myClasses[i]
            if cls and cls ~= '' and cls ~= '-- None --' then
                ImGui.SameLine()
                local cr, cg, cb = classColor(cls)
                accent({ cr, cg, cb, 1.0 }, string.format('[Slot %d: %s]', i, cls))
            end
        end

        ImGui.SameLine(); ImGui.TextDisabled('|')
        ImGui.SameLine(); ImGui.TextDisabled(string.format('Combat: %s', inCombat and 'Yes' or 'No'))
        ImGui.SameLine(); ImGui.TextDisabled(string.format('Ducking: %s', isDuck and 'Yes' or 'No'))
        ImGui.SameLine(); ImGui.TextDisabled(string.format('Sitting: %s', isSit and 'Yes' or 'No'))
        ImGui.SameLine(); ImGui.TextDisabled(string.format('Feigning: %s', isFeign and 'Yes' or 'No'))
        ImGui.SameLine(); ImGui.TextDisabled(string.format('Lev: %s', isLev and 'Yes' or 'No'))

        -- Active Pet Vitals (support all pets across the trio)
        local petSlots, extraPets = getMultiPetList()
        local activePets = {}
        local seenPetIds = {}
        for _, slot in ipairs(petSlots) do
            if slot.petId and slot.petId > 0 and not seenPetIds[slot.petId] and isSpawnAlive(slot.petId) then
                seenPetIds[slot.petId] = true
                local info = getPetSpawnInfo(slot.petId)
                table.insert(activePets, {
                    id = slot.petId,
                    cls = slot.cls,
                    slotNum = slot.slotNum,
                    info = info
                })
            end
        end
        for _, extraPid in ipairs(extraPets or {}) do
            if extraPid and extraPid > 0 and not seenPetIds[extraPid] and isSpawnAlive(extraPid) then
                seenPetIds[extraPid] = true
                local info = getPetSpawnInfo(extraPid)
                table.insert(activePets, {
                    id = extraPid,
                    cls = 'Pet',
                    slotNum = nil,
                    info = info
                })
            end
        end
        -- Me.Pet is always in getMultiPetList (slot or extra), which is deduplicated by pet name.

        if #activePets > 0 then
            accent(GOLD, string.format('Active Pets (%d):', #activePets))
            ImGui.SameLine()
            if petState.petHoldActive then
                accent(WARN, string.format('Pet Hold: ACTIVE (Holding until mob HP <= %d%%)', ctrl.pet_assist_at or 100))
            else
                accent(GOOD, 'Pet Orders: Normal / Engaged')
            end

            for _, pData in ipairs(activePets) do
                local info = pData.info
                local clsTag = pData.cls and string.format('[%s] ', pData.cls) or ''
                local cr, cg, cb = classColor(pData.cls or 'Mag')
                ImGui.TextColored(cr, cg, cb, 1.0, clsTag)
                ImGui.SameLine()
                accent(GOLD, string.format('%s (Lvl %d %s, ID: %d)', info.cleanName, info.level, info.race, info.id))
                ImGui.SameLine(); ImGui.TextDisabled('|')
                ImGui.SameLine()
                local hasTarg = (info.targetName and info.targetName ~= '' and info.targetName ~= 'None')
                if hasTarg then
                    accent(ARC, string.format('Target: %s (%d%%)', info.targetName, info.targetHpPct or 0))
                    if info.targetDist and info.targetDist > 0 and info.targetDist < 900 then
                        ImGui.SameLine(); ImGui.TextDisabled(string.format('(%.1fft)', info.targetDist))
                    end
                    if info.targetId and info.targetId > 0 then
                        ImGui.SameLine()
                        if ImGui.SmallButton(string.format('Target##petTarg_%d', info.id or 0)) then
                            mq.cmdf('/target id %d', info.targetId)
                        end
                        if ImGui.IsItemHovered() then
                            UI.setTooltip(string.format('Target pet\'s target: %s (ID %d)', info.targetName, info.targetId))
                        end
                    end
                else
                    accent(MUTED, 'Target: None')
                end

                local pr, pg, pb = 0.35, 0.75, 0.45
                local hpVal = tonumber(info.hpPct or 0) or 0
                if hpVal <= 25 then
                    pr, pg, pb = 0.90, 0.20, 0.20
                elseif hpVal <= 50 then
                    pr, pg, pb = 0.95, 0.75, 0.20
                end
                local petHpStr
                if (info.curHp or 0) > 0 and (info.maxHp or 0) > 0 then
                    petHpStr = string.format('%s HP: %d%% (%d / %d)', info.cleanName, hpVal, info.curHp, info.maxHp)
                else
                    petHpStr = string.format('%s HP: %d%%', info.cleanName, hpVal)
                end
                UI.drawStatusProgressBar(hpVal / 100.0, -1, 14, petHpStr, pr, pg, pb, 1.0)
            end
        end
    end


    -- 4. Navigation & MQ2Nav Subsystem Card
    if UI.drawCollapsingStatusHeader('nav', 'Navigation & MQ2Nav Subsystem', 'statusNav') then
        local navOk = navLoaded()
        local meshOk = navMeshLoaded()
        local stickOk = stickLoaded()
        local curZoneShort = 'zone'
        pcall(function()
            curZoneShort = mq.TLO.Zone.ShortName() or 'zone'
        end)

        local navTableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##StatusNavSubsystemTable', 3, navTableFlags) then
            ImGui.TableSetupColumn('Plugin & Mesh Status', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn('Live Navigation State', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn('Anti-Stuck & Diagnostics', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            ImGui.TableNextRow()
            -- Column 1: Plugins & NavMesh
            ImGui.TableNextColumn()
            if navOk then
                accent(GOOD, '• MQ2Nav: Loaded')
            else
                accent(WARN, '• MQ2Nav: NOT LOADED')
                if ImGui.Button('Load MQ2Nav##statBtnLoadNav') then
                    mq.cmd('/plugin mq2nav')
                end
            end

            if meshOk then
                accent(GOOD, string.format('• Zone Mesh: Loaded (%s)', curZoneShort))
            else
                accent(WARN, string.format('• Zone Mesh: MISSING (%s)', curZoneShort))
                if ImGui.Button('Reload Mesh##statBtnRelMesh') then
                    mq.cmd('/nav reload')
                end
            end

            if stickOk then
                local stickActive = false
                pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
                if stickActive then
                    accent(ARC, '• MoveUtils (Stick): ACTIVE')
                else
                    ImGui.TextDisabled('• MoveUtils (Stick): Loaded (Idle)')
                end
            else
                accent(WARN, '• MoveUtils: NOT LOADED')
                if ImGui.Button('Load MQ2MoveUtils##statBtnLoadMoveUtils') then
                    mq.cmd('/plugin mq2moveutils')
                end
            end

            -- Column 2: Live Navigation State
            ImGui.TableNextColumn()
            local navActive = false
            pcall(function() if navOk then navActive = mq.TLO.Navigation.Active() or false end end)
            local isMoving = false
            pcall(function() isMoving = mq.TLO.Me.Moving() or false end)

            if pursuit.meshRecoverId and pursuit.meshRecoverId ~= 0 then
                accent(WARN, '• Nav Status: OFF-MESH RECOVERY (Stick→Remap)')
            elseif navActive then
                accent(GOOD, '• Nav Status: NAVIGATING')
            elseif isMoving then
                accent(ARC, '• Nav Status: MOVING (Manual/Stick)')
            else
                ImGui.TextDisabled('• Nav Status: Idle / Stopped')
            end

            -- Destination Details
            if pursuit.lastNavTargetId and pursuit.lastNavTargetId ~= 0 then
                local tSpawnName = nil
                pcall(function() tSpawnName = mq.TLO.Spawn(pursuit.lastNavTargetId).CleanName() end)
                ImGui.Text(string.format('• Destination: Mob %s (ID %s)', tSpawnName or '', tostring(pursuit.lastNavTargetId)))
            elseif ctrl.mode == 'Puller' and runtime.pullState == 'RETURNING' then
                accent(ARC, '• Destination: Camp Location')
            elseif ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                local curWp = ctrl.waypoints[ctrl.current_waypoint_idx or 1]
                ImGui.Text(string.format('• Destination: WP #%d (%s)', ctrl.current_waypoint_idx or 1, curWp and curWp.name or 'WP'))
            elseif pursuit.wanderLoc then
                ImGui.Text(string.format('• Destination: Wander (Y:%.0f, X:%.0f, Z:%.0f)',
                    pursuit.wanderLoc.y or 0, pursuit.wanderLoc.x or 0, pursuit.wanderLoc.z or 0))
            else
                ImGui.TextDisabled('• Destination: None (Idle)')
            end

            -- Path Length & Distance
            if navActive then
                local pathLen, pathDist = 0, 0
                pcall(function()
                    pathLen = mq.TLO.Navigation.PathLength() or 0
                    pathDist = mq.TLO.Navigation.Distance() or 0
                end)
                ImGui.TextDisabled(string.format('• Path Length: %.1f ft (Dist: %.1f ft)', pathLen, pathDist))
            end

            -- Column 3: Anti-Stuck & Hazard Diagnostics
            ImGui.TableNextColumn()
            if pursuit.detourActive then
                local remSec = math.max(0, (pursuit.detourExpiresAt or 0) - os.clock())
                accent(WARN, string.format('• Detour: ACTIVE (%.1fs rem)', remSec))
            else
                ImGui.TextDisabled('• Detour Avoidance: Clear')
            end

            local stallCount = pursuit.navStalls or 0
            local unreachableCount = 0
            if pursuit.unreachableIds then
                for _ in pairs(pursuit.unreachableIds) do unreachableCount = unreachableCount + 1 end
            end
            ImGui.TextDisabled(string.format('• Nav Stalls: %d | Unreachable Mobs: %d', stallCount, unreachableCount))

            local stuckAttempts = stuckState.attempts or 0
            local stuckCounter = stuckState.counter or 0
            ImGui.TextDisabled(string.format('• Stuck Attempts: %d | Frame Counter: %d', stuckAttempts, stuckCounter))

            local zoneHazards = (ctrl.zone_hazards and ctrl.zone_hazards[curZoneShort]) or {}
            local hazCount = type(zoneHazards) == 'table' and #zoneHazards or 0
            ImGui.TextDisabled(string.format('• Hazard Hotspots: %d recorded in %s', hazCount, curZoneShort))

            ImGui.EndTable()
        end
    end


    -- 5. Mode Operations & Extended Target (XTarget) Threat Monitor
    if UI.drawCollapsingStatusHeader('xtar', 'Mode Operations & Extended Target (XTarget) Threat', 'statusXtar') then
        -- Mode Operations Sub-Panel
        if ctrl.mode == 'Puller' then
            local pullTargName = nil
            if runtime.pullTargetId and runtime.pullTargetId ~= 0 then
                pcall(function() pullTargName = mq.TLO.Spawn(runtime.pullTargetId).CleanName() end)
            end
            local anchorInfo = 'No Camp Anchor (Free Roam)'
            if ctrl.camp_loc then
                local myX, myY, myZ = 0, 0, 0
                pcall(function()
                    myX = mq.TLO.Me.X() or 0
                    myY = mq.TLO.Me.Y() or 0
                    myZ = mq.TLO.Me.Z() or 0
                end)
                local dx = (ctrl.camp_loc.x or 0) - myX
                local dy = (ctrl.camp_loc.y or 0) - myY
                local dz = (ctrl.camp_loc.z or 0) - myZ
                local campDist = math.sqrt(dx * dx + dy * dy + dz * dz)
                anchorInfo = string.format('Camp Anchor (%.1f, %.1f, %.1f) - Dist: %.1f ft (Radius: %d)',
                    ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, campDist, ctrl.hunter_radius or 1500)
            end
            accent(GOLD, 'Puller Operations:')
            ImGui.Text(string.format('• Pull State: %s | Pull Target: %s (ID %s) | Style: %s',
                runtime.pullState or 'IDLE', pullTargName or 'None', tostring(runtime.pullTargetId or 0), ctrl.pull_style or 'Melee'))
            ImGui.TextDisabled(string.format('• Anchor: %s | Min Level: %d | Max Level: %d',
                anchorInfo, ctrl.pull_min_level or 1, ctrl.pull_max_level or 100))
        elseif ctrl.mode == 'Assist' then
            local maInfo = runtime.getMaTargetInfo and runtime.getMaTargetInfo()
            local maDisplay = (maInfo and maInfo.hasMA) and string.format('%s (ID: %d)', maInfo.maName, maInfo.maId) or '(None Set)'
            local maTargStr = 'No Target'
            if maInfo and maInfo.hasTarget then
                local clsStr = (maInfo.targetClass ~= '') and (' [' .. maInfo.targetClass .. ']') or ''
                maTargStr = string.format('%s%s (ID: %d, %d%% HP, %.1fft)', maInfo.targetName, clsStr, maInfo.targetId, maInfo.targetHp, maInfo.targetDist)
            end
            accent(GOLD, 'Assist Operations:')
            ImGui.Text(string.format('• Main Assist: %s | MA Target: %s | Assist At: %d%% HP',
                maDisplay, maTargStr, ctrl.assist_at or 98))
            if maInfo and maInfo.hasTarget then
                ImGui.SameLine()
                if ImGui.SmallButton('Target##statOpTargMA') then
                    mq.cmdf('/target id %d', maInfo.targetId)
                end
                if ImGui.IsItemHovered() then UI.setTooltip(string.format('Target %s (ID %d)', maInfo.targetName, maInfo.targetId)) end
            end
            ImGui.TextDisabled(string.format('• Chase MA: %s (Chase Dist: %d ft) | Max XTar Chase: %d ft | Self-Defense: %s | Behind: %s',
                ctrl.chase and 'Enabled' or 'Disabled', ctrl.chase_dist or 15, ctrl.xtar_nav_dist or 150,
                (ctrl.assist_self_defense ~= false) and 'Enabled' or 'Disabled',
                (ctrl.assist_behind ~= false) and 'Enabled' or 'Disabled'))
        elseif ctrl.mode == 'Manual' then
            accent(GOLD, 'Manual Operations:')
            local campInfo = 'No camp set (stays put wherever fights end)'
            if ctrl.camp_loc then
                campInfo = string.format('Camp at (%.1f, %.1f, %.1f), Radius: %d',
                    ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, ctrl.camp_radius or 100)
            end
            ImGui.Text(string.format('• Auto-Target Hostiles on XTarget: %s | Chase Dist: %d ft',
                ctrl.manual_auto_xtarget ~= false and 'Enabled' or 'Disabled', ctrl.xtar_nav_dist or 150))
            ImGui.Text(string.format('• Stick to Target: %s | Auto-Nav to Selected Target: %s',
                ctrl.manual_stick ~= false and 'Enabled' or 'Disabled',
                ctrl.manual_auto_nav and 'Enabled' or 'Disabled'))
            ImGui.TextDisabled('• ' .. campInfo)
        end

        if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
            local dirStr = (ctrl.waypoint_direction == 1) and 'Forward' or 'Reverse'
            local loopStr = ctrl.waypoint_loop and 'Looping' or 'One-Way'
            accent(ARC, string.format('• Waypoint Patrol: WP #%d of %d | Direction: %s | Mode: %s',
                ctrl.current_waypoint_idx or 1, #ctrl.waypoints, dirStr, loopStr))
        end


        -- Interactive Extended Target (XTarget) Table
        accent(GOLD, 'Extended Target (XTarget) Threat Monitor:')

        local xtarSlots = 13
        pcall(function() xtarSlots = mq.TLO.Me.XTargetSlots() or 13 end)

        local activeXtargets = {}
        for slot = 1, xtarSlots do
            pcall(function()
                local xt = mq.TLO.Me.XTarget(slot)
                if xt and xt() and xt.ID() and xt.ID() > 0 and isSpawnAlive(xt.ID())
                    and not isGroupOrRaidMember(xt.ID()) and not isSpawnPetOrPlayer(xt.ID()) then
                    local stype = xt.Type() or ''
                    if (stype == 'NPC' or stype == 'Pet') and not xt.Dead() and stype ~= 'Corpse'
                        and not (isIgnored and isIgnored(xt.CleanName()))
                        and (not isHostileTarget or isHostileTarget(xt.ID())) then
                        table.insert(activeXtargets, {
                            slot = slot,
                            id = xt.ID(),
                            name = xt.CleanName() or 'Unknown',
                            level = xt.Level() or 0,
                            class = xt.Class.ShortName() or '?',
                            dist = xt.Distance() or 0,
                            hpPct = xt.PctHPs() or 0,
                            con = xt.ConColor() or 'White',
                            tot = xt.TargetOfTarget.CleanName() or 'None',
                            aggroPct = xt.PctAggro() or 0
                        })
                    end
                end
            end)
        end

        if #activeXtargets > 0 then
            local xtTableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
            if ImGui.BeginTable('##StatusXTargetThreatTable', 7, xtTableFlags) then
                ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn('Target Name', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Lvl / Cls', ImGuiTableColumnFlags.WidthFixed, 70)
                ImGui.TableSetupColumn('Dist', ImGuiTableColumnFlags.WidthFixed, 60)
                ImGui.TableSetupColumn('Health', ImGuiTableColumnFlags.WidthFixed, 110)
                ImGui.TableSetupColumn('Aggro Holder', ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, 65)
                ImGui.TableHeadersRow()

                for _, x in ipairs(activeXtargets) do
                    ImGui.TableNextRow()
                    -- Slot
                    ImGui.TableNextColumn()
                    ImGui.Text(string.format('#%d', x.slot))

                    -- Name
                    ImGui.TableNextColumn()
                    local conCol = UI.getConColorRgb(x.con)
                    accent(conCol, x.name)

                    -- Lvl / Cls
                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(string.format('%d %s', x.level, x.class))

                    -- Dist
                    ImGui.TableNextColumn()
                    ImGui.Text(string.format('%.1f', x.dist))

                    -- Health
                    ImGui.TableNextColumn()
                    local r, g, b = 0.25, 0.80, 0.35
                    if x.hpPct <= 20 then
                        r, g, b = 0.90, 0.20, 0.20
                    elseif x.hpPct <= 50 then
                        r, g, b = 0.95, 0.75, 0.20
                    end
                    UI.drawStatusProgressBar(x.hpPct / 100.0, 100, 14, string.format('%d%%', x.hpPct), r, g, b, 1.0)

                    -- Aggro Holder
                    ImGui.TableNextColumn()
                    if x.tot and x.tot ~= 'None' and x.tot ~= '' then
                        if myName and x.tot == myName then
                            accent({ 1.0, 0.35, 0.35, 1.0 }, 'YOU (' .. tostring(x.aggroPct) .. '%)')
                        else
                            ImGui.Text(string.format('%s (%d%%)', x.tot, x.aggroPct))
                        end
                    else
                        ImGui.TextDisabled('None')
                    end

                    -- Action
                    ImGui.TableNextColumn()
                    if ImGui.Button(string.format('Target##statXtar%d', x.slot), 55, 18) then
                        mq.cmdf('/target id %d', x.id)
                    end
                    if ImGui.IsItemHovered() then UI.setTooltip(string.format('Target %s (ID %d)', x.name, x.id)) end
                end

                ImGui.EndTable()
            end
        else
            accent(GOOD, 'No active hostile combatants on Extended Target list.')
        end
    end

    ImGui.EndTabItem()
end

function runtime.getMaTargetInfo()
    local maId = (runtime.maPcId and runtime.maPcId()) or (ctrl and ctrl.ma_id and ctrl.ma_id > 0 and ctrl.ma_id) or nil
    local maName = (ctrl and ctrl.ma_name and ctrl.ma_name ~= '') and ctrl.ma_name or nil
    local maSpawn = nil
    if maId and maId > 0 then
        pcall(function() maSpawn = mq.TLO.Spawn(maId) end)
    elseif maName then
        pcall(function() maSpawn = mq.TLO.Spawn('pc =' .. maName) end)
    end
    if not maSpawn or not maSpawn() then
        return {
            maId = maId or 0,
            maName = maName or '(None Set)',
            hasMA = false,
            hasTarget = false,
            targetName = 'No Target',
            targetId = 0,
            targetHp = 0,
            targetDist = 0,
            targetLvl = 0,
            targetClass = '',
            targetType = '',
            targetCon = 'White',
        }
    end

    local cleanMaName = maSpawn.CleanName() or (maName or 'Unknown')
    local actualMaId = maSpawn.ID() or (maId or 0)
    local t = nil
    pcall(function() t = maSpawn.Target end)
    if not t or not t() or (t.ID() or 0) <= 0 then
        return {
            maId = actualMaId,
            maName = cleanMaName,
            hasMA = true,
            hasTarget = false,
            targetName = 'No Target',
            targetId = 0,
            targetHp = 0,
            targetDist = 0,
            targetLvl = 0,
            targetClass = '',
            targetType = '',
            targetCon = 'White',
        }
    end

    local tId = 0
    local tName = 'No Target'
    local tHp = 0
    local tDist = 0
    local tLvl = 0
    local tClass = ''
    local tType = ''
    local tCon = 'White'
    pcall(function()
        tId = t.ID() or 0
        tName = t.CleanName() or 'No Target'
        tHp = t.PctHPs() or 0
        tDist = t.Distance() or 0
        tLvl = t.Level() or 0
        tClass = t.Class.ShortName() or ''
        tType = t.Type() or ''
        tCon = t.ConColor() or 'White'
    end)

    return {
        maId = actualMaId,
        maName = cleanMaName,
        hasMA = true,
        hasTarget = (tId > 0),
        targetName = tName,
        targetId = tId,
        targetHp = tHp,
        targetDist = tDist,
        targetLvl = tLvl,
        targetClass = tClass,
        targetType = tType,
        targetCon = tCon,
    }
end

function runtime.getAssistCandidates()
    local candidates = {
        { id = 0, name = '', label = '(None)', source = 'none' }
    }
    local seenNames = {}

    -- 1. Dynamic group members (excluding self)
    local grpCount = 0
    pcall(function() grpCount = mq.TLO.Group.Members() or 0 end)
    local leaderName = ''
    pcall(function() leaderName = mq.TLO.Group.Leader.CleanName() or '' end)

    if grpCount > 0 then
        for i = 1, grpCount do
            local mId = 0
            local mName = ''
            local mClass = ''
            pcall(function()
                local m = mq.TLO.Group.Member(i)
                if m and m() then
                    mId = m.ID() or 0
                    mName = m.CleanName() or ''
                    mClass = m.Class.ShortName() or ''
                end
            end)
            if mName ~= '' then
                local isLdr = (leaderName ~= '' and mName:lower() == leaderName:lower())
                local ldrPrefix = isLdr and '[Leader] ' or '[Group] '
                local clsStr = (mClass ~= '') and (' [' .. mClass .. ']') or ''
                local idStr = (mId > 0) and (' (ID: ' .. tostring(mId) .. ')') or ' (Not in zone)'
                local lbl = string.format('%s%s%s%s', ldrPrefix, mName, clsStr, idStr)
                table.insert(candidates, { id = mId, name = mName, label = lbl, source = 'group', class = mClass })
                seenNames[mName:lower()] = true
            end
        end
    end

    -- 2. Custom assist candidates from ctrl.custom_ma_list
    if ctrl and ctrl.custom_ma_list and type(ctrl.custom_ma_list) == 'table' then
        for _, entry in ipairs(ctrl.custom_ma_list) do
            local eName = entry.name or ''
            if eName ~= '' and not seenNames[eName:lower()] then
                local liveId = 0
                local liveCls = entry.class or ''
                pcall(function()
                    local s = mq.TLO.Spawn('pc =' .. eName)
                    if s and s() and isSpawnAlive(s.ID()) then
                        liveId = s.ID() or 0
                        liveCls = s.Class.ShortName() or liveCls
                    end
                end)
                if liveId > 0 then
                    entry.id = liveId
                    entry.class = liveCls
                end
                local clsStr = (liveCls ~= '') and (' [' .. liveCls .. ']') or ''
                local idStr
                if liveId > 0 then
                    idStr = ' (ID: ' .. tostring(liveId) .. ')'
                elseif (entry.id or 0) > 0 then
                    idStr = ' (ID: ' .. tostring(entry.id) .. ' - Away)'
                else
                    idStr = ' (Not in zone)'
                end
                local lbl = string.format('[Custom] %s%s%s', eName, clsStr, idStr)
                table.insert(candidates, {
                    id = liveId > 0 and liveId or (entry.id or 0),
                    name = eName,
                    label = lbl,
                    source = 'custom',
                    class = liveCls
                })
                seenNames[eName:lower()] = true
            end
        end
    end

    return candidates
end

function runtime.addCustomAssistTarget()
    local tId = 0
    local tType = ''
    local tName = ''
    local tClass = ''
    pcall(function()
        local t = mq.TLO.Target
        if t and t() then
            tId = t.ID() or 0
            tType = t.Type() or ''
            tName = t.CleanName() or ''
            tClass = t.Class.ShortName() or ''
        end
    end)

    if tId <= 0 or tName == '' then
        runtime.maStatusMsg = 'Target a player character (PC) first to add.'
        runtime.maStatusTimer = os.clock() + 4.0
        return false
    end

    if tType ~= 'PC' then
        runtime.maStatusMsg = string.format('Target "%s" is not a PC (%s). Target must be a PC.', tName, tType)
        runtime.maStatusTimer = os.clock() + 4.0
        return false
    end

    local myId = 0
    pcall(function() myId = mq.TLO.Me.ID() or 0 end)
    if tId == myId then
        runtime.maStatusMsg = 'Cannot add yourself as Main Assist.'
        runtime.maStatusTimer = os.clock() + 4.0
        return false
    end

    ctrl.custom_ma_list = ctrl.custom_ma_list or {}
    local found = false
    for _, entry in ipairs(ctrl.custom_ma_list) do
        if entry.name:lower() == tName:lower() then
            entry.id = tId
            entry.class = tClass
            found = true
            break
        end
    end
    if not found then
        table.insert(ctrl.custom_ma_list, { name = tName, id = tId, class = tClass })
    end

    ctrl.ma_id = tId
    ctrl.ma_name = tName
    runtime.saveLoadout(true)
    runtime.maStatusMsg = string.format('Added %s (ID: %d) as Main Assist.', tName, tId)
    runtime.maStatusTimer = os.clock() + 4.0
    return true
end

function runtime.removeCustomAssist(targetNameOrId)
    ctrl.custom_ma_list = ctrl.custom_ma_list or {}
    local removeIdx = nil

    if targetNameOrId then
        local searchStr = tostring(targetNameOrId):lower()
        for i, entry in ipairs(ctrl.custom_ma_list) do
            if entry.name:lower() == searchStr or tostring(entry.id) == searchStr then
                removeIdx = i
                break
            end
        end
    end

    if not removeIdx then
        local tName = nil
        pcall(function()
            local t = mq.TLO.Target
            if t and t() and t.Type() == 'PC' then tName = t.CleanName() end
        end)
        if tName and tName ~= '' then
            for i, entry in ipairs(ctrl.custom_ma_list) do
                if entry.name:lower() == tName:lower() then
                    removeIdx = i
                    break
                end
            end
        end
    end

    if not removeIdx then
        for i, entry in ipairs(ctrl.custom_ma_list) do
            if (ctrl.ma_id and ctrl.ma_id > 0 and entry.id == ctrl.ma_id) or
               (ctrl.ma_name and ctrl.ma_name ~= '' and entry.name:lower() == ctrl.ma_name:lower()) then
                removeIdx = i
                break
            end
        end
    end

    if removeIdx then
        local removedName = ctrl.custom_ma_list[removeIdx].name
        table.remove(ctrl.custom_ma_list, removeIdx)
        if ctrl.ma_name and ctrl.ma_name:lower() == removedName:lower() then
            ctrl.ma_id = 0
            ctrl.ma_name = ''
        end
        runtime.saveLoadout(true)
        runtime.maStatusMsg = string.format('Removed "%s" from custom assist list.', removedName)
        runtime.maStatusTimer = os.clock() + 4.0
        return true
    else
        runtime.maStatusMsg = 'Select or target a custom assist to remove (group members are dynamic).'
        runtime.maStatusTimer = os.clock() + 4.0
        return false
    end
end

-- UI: control tab
function UI.drawControlTab()
    if not ImGui.BeginTabItem('Control') then return end
    accent(GOLD, 'Combat Mode')
    ImGui.SetNextItemWidth(160)
    local curPrimaryIdx = idxOf(MODES.PRIMARY, ctrl.mode)
    local newPrimaryIdx = ImGui.Combo('##primaryMode', curPrimaryIdx, MODES.PRIMARY)
    local newPrimaryMode = MODES.PRIMARY[newPrimaryIdx]
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Select primary combat operating mode (Manual, Puller, Assist).')
    end

    if newPrimaryMode ~= ctrl.mode then
        if ctrl.mode == 'Manual' and newPrimaryMode ~= 'Manual' then
            setManualHunterPetHold(false)
        elseif newPrimaryMode == 'Manual' then
            if not ctrl.running or not (runtime.isCombat and runtime.isCombat()) then
                setManualHunterPetHold(true, true)
            end
        end
        ctrl.mode = newPrimaryMode
        if MODES.SUBMODES[ctrl.mode] then
            ctrl.submode = MODES.SUBMODES[ctrl.mode][1]
        else
            ctrl.submode = 'Hunt'
        end
        if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
    end

    if MODES.SUBMODES[ctrl.mode] then
        ImGui.SameLine()
        ImGui.SetNextItemWidth(140)
        local subList = MODES.SUBMODES[ctrl.mode]
        local curSubIdx = idxOf(subList, ctrl.submode)
        local newSubIdx = ImGui.Combo('##submode', curSubIdx, subList)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Select operational submode behavior for ' .. tostring(ctrl.mode) .. '.')
        end
        if newSubIdx ~= curSubIdx then
            ctrl.submode = subList[newSubIdx]
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
        end
    end

    local descKey = ctrl.mode
    if MODES.SUBMODES[ctrl.mode] then
        descKey = string.format('%s:%s', ctrl.mode, ctrl.submode)
    end
    accent(MUTED, MODES.SUB_DESC[descKey] or MODES.DESC[ctrl.mode] or '')

    -- Manual Mode Contextual Controls
    if ctrl.mode == 'Manual' then
        accent(GOLD, 'Camp Location (optional)')
        if ctrl.camp_loc then
            ImGui.Text(string.format('Camp set at: %.1f, %.1f, %.1f',
                ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z))
        else
            accent(MUTED, 'No camp set -- toon stays put wherever fights end.')
        end

        if ImGui.Button('Set Here##manualCampSet') then
            local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
            if mx and my and mz then ctrl.camp_loc = { x = mx, y = my, z = mz } end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Set the current location as the Camp anchor point. Character will return here when idle.')
        end
        ImGui.SameLine()
        if ImGui.Button('Clear Camp##manualCampClear') then
            ctrl.camp_loc = nil
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Clears camp location. Player will not auto-return after combat.')
        end

        if ctrl.camp_loc then
            ImGui.SetNextItemWidth(180)
            local manualCampR, manualCampRChanged = ImGui.SliderInt('Camp Radius##manualRadius', ctrl.camp_radius or 100, 10, 500)
            if manualCampRChanged then
                ctrl.camp_radius = manualCampR
                runtime.saveLoadout(true)
                if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Maximum distance in units from camp center to engage enemies.')
            end
        end

        ctrl.manual_auto_xtarget = ImGui.Checkbox('Auto-Target Hostiles on XTarget##manualAutoXtar',
            ctrl.manual_auto_xtarget ~= false)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Checked: Automatically acquires and fights hostile NPCs that enter your Extended Target (XTarget) list.\nUnchecked: Only fights targets you manually select.')
        end
        if ctrl.manual_auto_xtarget ~= false then
            ImGui.SetNextItemWidth(180)
            ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##manualXtarDist', ctrl.xtar_nav_dist or 150, 25,
                300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget).')
            end
        end

        local manualStick, manualStickChanged = ImGui.Checkbox('Stick to Target in Combat##manualStick',
            ctrl.manual_stick ~= false)
        if manualStickChanged then
            ctrl.manual_stick = manualStick
            if not manualStick and runtime.stopMoving then runtime.stopMoving() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Checked: Once a fight starts, Triune navigates to and sticks to the NPC being attacked.\nUnchecked: You drive. The character stays where you leave it and only attacks/casts when the NPC is in reach.')
        end

        local manualNav, manualNavChanged = ImGui.Checkbox('Auto-Nav to Selected Target##manualAutoNav',
            ctrl.manual_auto_nav == true)
        if manualNavChanged then
            ctrl.manual_auto_nav = manualNav
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Checked: Selecting a hostile NPC immediately navigates to it and engages.\nUnchecked: A selected NPC is only engaged once it is on XTarget or combat starts.')
        end
    end

    -- Puller Mode Contextual Controls
    if ctrl.mode == 'Puller' then
        ImGui.SetNextItemWidth(160)
        local curPullStyleIdx = 1
        for idx, ps in ipairs(MODES.PULL_STYLES) do
            if ps == (ctrl.pull_style or 'Melee') then
                curPullStyleIdx = idx; break
            end
        end
        local newPullStyleIdx = ImGui.Combo('Pull Method##pullStyle', curPullStyleIdx, MODES.PULL_STYLES)
        ctrl.pull_style = MODES.PULL_STYLES[newPullStyleIdx]
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Method used to pull/tag target mob:\n- Melee: Closes to melee range and attacks\n- Spell: Casts spell from range\n- Pet: Sends pet out to tag mob\n- Ranged: Fires bow/ranged from distance')
        end

        if ctrl.pull_style == 'Spell' then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(200)

            local memGems = {}
            local gemSlots = {}
            for i = 1, NUM_GEMS do
                local name
                pcall(function() name = mq.TLO.Me.Gem(i).Name() end)
                if not name or name == '' then
                    name = runtime.getPrimarySpellForGem(i)
                end
                if name and name ~= '' then
                    table.insert(memGems, string.format('Gem %d: %s', i, name))
                    table.insert(gemSlots, i)
                end
            end

            if #memGems == 0 then
                memGems = { '(No Spells Memorized)' }
                gemSlots = { 1 }
            end

            local curIdx = 1
            local curSpell = ctrl.pull_spell or ''
            for idx, slotNum in ipairs(gemSlots) do
                local gName
                pcall(function() gName = mq.TLO.Me.Gem(slotNum).Name() end)
                if not gName or gName == '' then
                    gName = runtime.getPrimarySpellForGem(slotNum)
                end
                if gName == curSpell or slotNum == (ctrl.pull_spell_gem or 1) then
                    curIdx = idx
                    break
                end
            end

            local newIdx = ImGui.Combo('Pull Spell##pullSpellCombo', curIdx, memGems)
            local chosenSlot = gemSlots[newIdx] or 1
            ctrl.pull_spell_gem = chosenSlot

            local chosenName
            pcall(function() chosenName = mq.TLO.Me.Gem(chosenSlot).Name() end)
            if not chosenName or chosenName == '' then
                chosenName = runtime.getPrimarySpellForGem(chosenSlot)
            end
            ctrl.pull_spell = chosenName or ''

            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Select the memorized spell gem to use for ranged pulling')
            end
        end

        if (ctrl.pull_style or 'Melee') ~= 'Melee' then
            ImGui.SetNextItemWidth(180)
            ctrl.pull_engage_dist = ImGui.SliderInt('Engagement Distance##pullEngageDist', ctrl.pull_engage_dist or 100,
                15, 250)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Distance (units) to close to before sending in pets, casting pull spell, or firing bow.')
            end

            ctrl.pull_stand_back = ImGui.Checkbox('Stand Back (Let Pet Tank / Stay Ranged)##pullStandBack',
                ctrl.pull_stand_back == true)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Checked: Stays back at engagement distance during combat and lets pet tank or stays ranged without closing into melee range.')
            end
        end

        ImGui.SetNextItemWidth(180)
        local pullMinHpVal = ImGui.SliderInt('Min Pull HP %##pullMinHpCtrl', ctrl.pull_min_hp_pct or 0, 0, 95, '%d%%')
        ctrl.pull_min_hp_pct = pullMinHpVal
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'Pauses pulling and sits out of combat to recover if current HP drops below\n'
                .. 'this threshold. Pulling resumes once HP reaches 100%.\n'
                .. 'Automatically stands to fight if attacked (0 = disabled / pull at any HP).')
        end


        if ctrl.submode == 'Hunt' then
            accent(ARC, 'Puller (Hunt)')
            ImGui.SetNextItemWidth(180)
            local huntR, huntRChanged = ImGui.SliderInt('Search Radius', ctrl.hunter_radius or 1500, 50, 2000)
            if huntRChanged then
                ctrl.hunter_radius = huntR
                runtime.saveLoadout(true)
                if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
            end
            ImGui.SetNextItemWidth(180)
            ctrl.hunter_z_plane = ImGui.SliderInt('Floor Height (Z Plane)', ctrl.hunter_z_plane or 15, 5, 50)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Tier 1 vertical search threshold. Triune prioritizes NPCs on the same floor or Z plane\nwithin this height difference before searching other floors.')
            end
            ImGui.SetNextItemWidth(180)
            ctrl.hunter_z = ImGui.SliderInt('Max Height Diff (Z)', ctrl.hunter_z or 75, 10, 300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Tier 2 vertical search limit. If no valid NPCs are found on your immediate floor,\nTriune expands search up to this maximum height difference across floors and ledges.')
            end
            ImGui.SetNextItemWidth(180)
            ctrl.hunter_min_level = ImGui.SliderInt('Min NPC Level', ctrl.hunter_min_level or 1, 1, 100)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(180)
            ctrl.hunter_max_level = ImGui.SliderInt('Max NPC Level', ctrl.hunter_max_level or 100, 1, 100)
            if ctrl.hunter_min_level > ctrl.hunter_max_level then ctrl.hunter_min_level = ctrl.hunter_max_level end

            ImGui.SetNextItemWidth(180)
            ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##pullerHuntXtar', ctrl.xtar_nav_dist or 150, 25,
                300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget).')
            end

            ctrl.ignore_distant_xtargets = ImGui.Checkbox('Ignore Distant XTargets When Pulling##pullerHuntXtarIgnore',
                ctrl.ignore_distant_xtargets == true)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'When checked, an XTarget enemy farther than Max XTarget Chase Range is skipped entirely\ninstead of being chased -- Puller looks for a new mob to pull instead.')
            end

            ImGui.Dummy(0, 2)

            accent(GOLD, 'Combat Radius Anchor (optional)')
            if ctrl.hunter_combat_loc then
                ImGui.Text(string.format('Anchor: %.1f, %.1f, %.1f',
                    ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.y, ctrl.hunter_combat_loc.z))
            else
                accent(MUTED, 'No anchor set -- Puller roams freely within Search Radius.')
            end

            if ImGui.Button('Set Anchor##pullerAnchorSet') then
                local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
                if mx and my and mz then
                    ctrl.hunter_combat_loc = { x = mx, y = my, z = mz }
                    if (ctrl.hunter_combat_radius or 0) <= 0 then
                        ctrl.hunter_combat_radius = 250
                    end
                    if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Saves your current position as anchor for roaming.')
            end
            ImGui.SameLine()
            if ImGui.Button('Clear Anchor##pullerAnchorClear') then
                ctrl.hunter_combat_loc = nil
                pursuit.wanderLoc = nil
                if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
            end

            ImGui.SetNextItemWidth(220)
            local curRadius = (ctrl.hunter_combat_radius and ctrl.hunter_combat_radius > 0) and ctrl
                .hunter_combat_radius or 250
            local newRadius, changed = ImGui.SliderInt('Combat Radius##pullerAnchorRadius', curRadius, 1, 2000)
            if changed then
                ctrl.hunter_combat_radius = newRadius
                if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
                runtime.saveLoadout(true)
            end
        elseif ctrl.submode == 'Camp' then
            accent(GOLD, 'Puller Camp Location')
            if ctrl.camp_loc then
                ImGui.Text(string.format('Camp set at: %.1f, %.1f, %.1f',
                    ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z))
            else
                accent(WARN, 'No camp location set -- puller requires a camp position.')
            end

            if ImGui.Button('Set Here##pullerCampSet') then
                local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
                if mx and my and mz then ctrl.camp_loc = { x = mx, y = my, z = mz } end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Set the current location as the Puller Camp anchor point. Puller returns here after pulling.')
            end
            ImGui.SameLine()
            if ImGui.Button('Clear Camp##pullerCampClear') then
                ctrl.camp_loc = nil; runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Clear the Puller Camp anchor point.')
            end

            ImGui.SetNextItemWidth(180)
            local pullRad, pullRadChanged = ImGui.SliderInt('Pull Radius', ctrl.camp_radius or 100, 10, 500)
            if pullRadChanged then
                ctrl.camp_radius = pullRad
                runtime.saveLoadout(true)
                if runtime.updateMapRadiusVisuals then runtime.updateMapRadiusVisuals() end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Maximum horizontal distance in units from camp to search for pullable NPCs.')
            end
            ImGui.SetNextItemWidth(180)
            ctrl.camp_z = ImGui.SliderInt('Pull Height Diff (Z)', ctrl.camp_z or 75, 10, 300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Maximum vertical height difference (Z) in units above or below camp to search for pullable NPCs.')
            end

            ImGui.SetNextItemWidth(180)
            ctrl.pull_min_level = ImGui.SliderInt('Min NPC Level', ctrl.pull_min_level or 1, 1, 100)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Minimum NPC level required to consider a mob eligible for pulling.')
            end
            ImGui.SameLine()
            ImGui.SetNextItemWidth(180)
            ctrl.pull_max_level = ImGui.SliderInt('Max NPC Level', ctrl.pull_max_level or 100, 1, 100)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Maximum NPC level allowed to consider a mob eligible for pulling.')
            end
            if ctrl.pull_min_level > ctrl.pull_max_level then ctrl.pull_min_level = ctrl.pull_max_level end

            ImGui.SetNextItemWidth(180)
            ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##pullerCampXtar', ctrl.xtar_nav_dist or 150, 25,
                300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget).')
            end
        end

        -- Puller Waypoint Patrol Section
        accent(GOLD, 'Puller Waypoint Patrol')
        local useWp = ImGui.Checkbox('Enable Waypoint Patrol##useWaypoints', ctrl.use_waypoints == true)
        if useWp ~= ctrl.use_waypoints then
            ctrl.use_waypoints = useWp
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'When checked, Puller systematically travels through configured 3D waypoints in a loop to search for mobs instead of remaining stationary.')
        end

        if ctrl.use_waypoints then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(120)
            local newRad, changedRad = ImGui.SliderInt('Arrival Radius##wpRadius', ctrl.waypoint_radius or 20, 5, 100)
            if changedRad then
                ctrl.waypoint_radius = newRad
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Distance in units to reach a waypoint before advancing to the next one in the loop.')
            end

            ImGui.SameLine()
            ImGui.SetNextItemWidth(130)
            local newScan, changedScan = ImGui.SliderInt('Scan Radius##wpScanRadius', ctrl.waypoint_scan_radius or 100,
                20, 500)
            if changedScan then
                ctrl.waypoint_scan_radius = newScan
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                'NPC search radius in units around your character to look for mobs while patrolling waypoints.')
            end

            local newLoop = ImGui.Checkbox('Loop##wpLoop', ctrl.waypoint_loop == true)
            if newLoop ~= ctrl.waypoint_loop then
                ctrl.waypoint_loop = newLoop
                if ctrl.waypoint_loop then ctrl.waypoint_direction = 1 end
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'On, patrol always moves forward and wraps to the first waypoint\n'
                    .. 'after the last one. Off (default), patrol bounces back and forth,\n'
                    .. 'reversing direction at each end.')
            end

            do
                local zs = runtime.getCurrentZoneShortName()
                local zoneDisplay = runtime.getZoneDisplayName(zs)
                local presets = runtime.wpPresetsForZone(zs)
                local options = { 'Current' }
                for _, p in ipairs(presets) do
                    options[#options + 1] = string.format('%s - %s', p.name, p.zoneName or zoneDisplay)
                end
                local curIdx = 1
                if runtime.wpSelectedPreset then
                    for i, p in ipairs(presets) do
                        if p.name == runtime.wpSelectedPreset then curIdx = i + 1; break end
                    end
                    if curIdx == 1 then runtime.wpSelectedPreset = nil end -- selection no longer exists (e.g. deleted)
                end
                ImGui.SetNextItemWidth(220)
                local newIdx = ImGui.Combo('##wpPresetCombo', curIdx, options)
                if newIdx ~= curIdx then
                    runtime.wpSelectedPreset = (newIdx > 1) and presets[newIdx - 1].name or nil
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Named waypoint presets saved for this zone (' .. zoneDisplay .. ').')
                end

                ImGui.SameLine()
                if ImGui.Button('Save##wpPresetSaveBtn') then
                    runtime.wpPresetNameInput = runtime.wpSelectedPreset or ''
                    runtime.wpPresetModalMode = 'save'
                    runtime.wpPresetModalOpen = true
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip(
                        'Save the current waypoints/settings as a named preset for this zone.\n'
                        .. 'Saving over an existing name overwrites it.')
                end

                local hasSelection = runtime.wpSelectedPreset ~= nil
                if not hasSelection then ImGui.BeginDisabled() end
                ImGui.SameLine()
                if ImGui.Button('Load##wpPresetLoadBtn') then
                    if runtime.wpSelectedPreset then runtime.wpPresetLoad(runtime.wpSelectedPreset) end
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Load the selected preset, overwriting the current waypoints/settings.')
                end

                ImGui.SameLine()
                if ImGui.Button('Edit##wpPresetEditBtn') then
                    runtime.wpPresetNameInput = runtime.wpSelectedPreset or ''
                    runtime.wpPresetModalMode = 'rename'
                    runtime.wpPresetModalOpen = true
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Rename the selected preset.')
                end

                ImGui.SameLine()
                if ImGui.Button('Delete##wpPresetDeleteBtn') then
                    if runtime.wpSelectedPreset then
                        runtime.wpPresetDelete(runtime.wpSelectedPreset)
                        runtime.wpSelectedPreset = nil
                    end
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Delete the selected preset.')
                end

                ImGui.SameLine()
                if ImGui.Button('Export##wpPresetExportBtn') then
                    local str, err = runtime.wpPresetExport(runtime.wpSelectedPreset)
                    if str then
                        pcall(ImGui.SetClipboardText, str)
                        print(string.format('\ag[Triune]\ax Copied waypoint preset "%s" to clipboard:', runtime.wpSelectedPreset))
                        print(str)
                    elseif err then
                        print('\ay[Triune]\ax ' .. err)
                    end
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Copy the selected preset to your clipboard as a shareable string.')
                end
                if not hasSelection then ImGui.EndDisabled() end

                ImGui.SetNextItemWidth(320)
                runtime.wpImportInput = ImGui.InputText('##wpImportInput', runtime.wpImportInput or '', 4096)
                ImGui.SameLine()
                if ImGui.Button('Import##wpPresetImportBtn') then
                    local pending, err = runtime.wpPresetParseImport(runtime.wpImportInput)
                    if not pending then
                        print('\ay[Triune]\ax ' .. err)
                    elseif pending.collision then
                        runtime.wpImportPending = pending
                        runtime.wpPresetModalMode = 'importConfirm'
                        runtime.wpPresetModalOpen = true
                    else
                        runtime.wpPresetCommitImport(pending)
                        runtime.wpSelectedPreset = pending.name
                        runtime.wpImportInput = ''
                        print(string.format('\ag[Triune]\ax Imported waypoint preset "%s" for %s.',
                            pending.name, pending.zoneDisplay))
                        if pending.zoneMismatch then
                            print(string.format('\ay[Triune]\ax Note: this was exported from %s -- you are currently in %s.',
                                pending.zoneDisplay, pending.currentZoneDisplay))
                        end
                    end
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Paste a waypoint string from Export, then click Import.')
                end

                if runtime.wpPresetModalOpen then
                    runtime.wpPresetModalOpen = false
                    if runtime.wpPresetModalMode == 'importConfirm' then
                        ImGui.OpenPopup('Confirm Import##wpPresetImportConfirmPopup')
                    else
                        ImGui.OpenPopup('Waypoint Preset Name##wpPresetNamePopup')
                    end
                end

                local _, importModalDraw = ImGui.BeginPopupModal('Confirm Import##wpPresetImportConfirmPopup', true,
                    ImGuiWindowFlags.AlwaysAutoResize)
                if importModalDraw then
                    local p = runtime.wpImportPending
                    if not p then
                        ImGui.CloseCurrentPopup()
                    else
                        ImGui.Text(string.format('A preset named "%s" already exists for %s.', p.name, p.zoneDisplay))
                        ImGui.Text('Importing will overwrite it.')
                        if p.zoneMismatch then
                            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format(
                                'Note: this was exported from %s -- you are currently in %s.',
                                p.zoneDisplay, p.currentZoneDisplay))
                        end
                        if ImGui.Button('Overwrite##wpImportConfirmOk') then
                            runtime.wpPresetCommitImport(p)
                            runtime.wpSelectedPreset = p.name
                            runtime.wpImportInput = ''
                            runtime.wpImportPending = nil
                            ImGui.CloseCurrentPopup()
                        end
                        ImGui.SameLine()
                        if ImGui.Button('Cancel##wpImportConfirmCancel') then
                            runtime.wpImportPending = nil
                            ImGui.CloseCurrentPopup()
                        end
                    end
                    ImGui.EndPopup()
                end

                local _, presetModalDraw = ImGui.BeginPopupModal('Waypoint Preset Name##wpPresetNamePopup', true,
                    ImGuiWindowFlags.AlwaysAutoResize)
                if presetModalDraw then
                    ImGui.Text(runtime.wpPresetModalMode == 'rename' and 'Rename preset:' or 'Save preset as:')
                    ImGui.SetNextItemWidth(240)
                    runtime.wpPresetNameInput = ImGui.InputText('##wpPresetNameInput', runtime.wpPresetNameInput or '')
                    if ImGui.Button('OK##wpPresetNameOk') then
                        local ok, err, finalName
                        if runtime.wpPresetModalMode == 'rename' then
                            ok, err, finalName = runtime.wpPresetRename(runtime.wpSelectedPreset, runtime.wpPresetNameInput)
                        else
                            ok, err, finalName = runtime.wpPresetSave(runtime.wpPresetNameInput)
                        end
                        if ok then
                            runtime.wpSelectedPreset = finalName
                            ImGui.CloseCurrentPopup()
                        elseif err then
                            print('\ay[Triune]\ax ' .. err)
                        end
                    end
                    ImGui.SameLine()
                    if ImGui.Button('Cancel##wpPresetNameCancel') then
                        ImGui.CloseCurrentPopup()
                    end
                    ImGui.EndPopup()
                end
            end

            if ImGui.Button('Add Current Location##addWpLoc') then
                runtime.wpAdd()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Captures your current position (Y, X, Z) and adds it to the waypoint patrol loop.')
            end

            ImGui.SameLine()
            if ImGui.Button('Clear All Waypoints##clearWps') then
                runtime.wpClear()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Removes all saved waypoints from the patrol route.')
            end

            local wps = ctrl.waypoints or {}
            if #wps > 0 then
                local wpTableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                    ImGuiTableFlags.SizingFixedFit)
                if ImGui.BeginTable('WaypointTable', 6, wpTableFlags) then
                    ImGui.TableSetupColumn('#', ImGuiTableColumnFlags.WidthFixed, 25)
                    ImGui.TableSetupColumn('Name', ImGuiTableColumnFlags.WidthFixed, 100)
                    ImGui.TableSetupColumn('Coordinates (Y, X, Z)', ImGuiTableColumnFlags.WidthFixed, 150)
                    ImGui.TableSetupColumn('Distance', ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableSetupColumn('Active', ImGuiTableColumnFlags.WidthFixed, 50)
                    ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 130)
                    ImGui.TableHeadersRow()

                    for idx, wp in ipairs(wps) do
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(idx))

                        ImGui.TableNextColumn()
                        ImGui.Text(wp.name or ('WP ' .. idx))

                        ImGui.TableNextColumn()
                        ImGui.Text(string.format('%.1f, %.1f, %.1f', wp.y or 0, wp.x or 0, wp.z or 0))

                        ImGui.TableNextColumn()
                        local dist = distToLoc(wp.x, wp.y, wp.z)
                        ImGui.Text(string.format('%.0f', dist))

                        ImGui.TableNextColumn()
                        if (ctrl.current_waypoint_idx or 1) == idx then
                            if ctrl.waypoint_loop and idx == #wps and #wps > 1 then
                                accent(GOOD, '>> LOOP')
                            else
                                local dirStr = ((ctrl.waypoint_direction or 1) == -1) and '<<' or '>>'
                                accent(GOOD, dirStr .. ' NEXT')
                            end
                        else
                            ImGui.Text('')
                        end

                        ImGui.TableNextColumn()
                        if ImGui.Button(string.format('Set##wpSet_%d', idx)) then
                            ctrl.current_waypoint_idx = idx
                            if ctrl.waypoint_loop then
                                ctrl.waypoint_direction = 1
                            elseif idx == #wps and #wps > 1 then
                                ctrl.waypoint_direction = -1
                            elseif idx == 1 then
                                ctrl.waypoint_direction = 1
                            end
                            runtime.saveLoadout(true)
                        end
                        if ImGui.IsItemHovered() then ImGui.SetTooltip('Set this as the next target waypoint') end

                        ImGui.SameLine()
                        if ImGui.Button(string.format('^##wpUp_%d', idx)) then
                            runtime.wpMoveUp(idx)
                        end
                        if ImGui.IsItemHovered() then ImGui.SetTooltip('Move waypoint up in loop sequence') end

                        ImGui.SameLine()
                        if ImGui.Button(string.format('v##wpDn_%d', idx)) then
                            runtime.wpMoveDown(idx)
                        end
                        if ImGui.IsItemHovered() then ImGui.SetTooltip('Move waypoint down in loop sequence') end

                        ImGui.SameLine()
                        if ImGui.Button(string.format('X##wpDel_%d', idx)) then
                            runtime.wpDelete(idx)
                        end
                        if ImGui.IsItemHovered() then ImGui.SetTooltip('Delete this waypoint') end
                    end
                    ImGui.EndTable()
                end
            else
                accent(MUTED,
                    'No waypoints configured. Stand at desired search locations and click "Add Current Location".')
            end
        end

        -- Puller Mob Filtering: Faction Considerations, Pull List & Ignore List
        ImGui.Separator()
        accent(GOLD, 'Puller Target Filters')

        accent(GOLD, 'Target Faction Considerations')
        accent(MUTED, 'Select which NPC faction considerations Puller is allowed to auto-target.')

        ctrl.pull_con_filter = ctrl.pull_con_filter or {
            ['Scowling'] = true,
            ['Threateningly'] = true,
            ['Dubious'] = true,
            ['Apprehensive'] = true,
            ['Indifferent'] = true,
            ['Amiably'] = true,
            ['Kindly'] = true,
            ['Warmly'] = true,
            ['Ally'] = true,
        }

        if ImGui.Button('Select All##pullConAllBtn') then
            for _, conName in ipairs(MODES.PULL_CON_LIST) do ctrl.pull_con_filter[conName] = true end
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Hostile Only##pullConHostileBtn') then
            for _, conName in ipairs(MODES.PULL_CON_LIST) do
                ctrl.pull_con_filter[conName] = (conName == 'Scowling' or conName == 'Threateningly' or conName == 'Dubious' or conName == 'Apprehensive')
            end
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Hostile + Indifferent##pullConHostileIndiffBtn') then
            for _, conName in ipairs(MODES.PULL_CON_LIST) do
                ctrl.pull_con_filter[conName] = (conName == 'Scowling' or conName == 'Threateningly' or conName == 'Dubious' or conName == 'Apprehensive' or conName == 'Indifferent')
            end
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Clear All##pullConClearBtn') then
            for _, conName in ipairs(MODES.PULL_CON_LIST) do ctrl.pull_con_filter[conName] = false end
            runtime.saveLoadout(true)
        end


        local tableFlags = bit.bor(ImGuiTableFlags.BordersOuter, ImGuiTableFlags.SizingFixedSame)
        if ImGui.BeginTable('PullConTable', 3, tableFlags) then
            for idx, conName in ipairs(MODES.PULL_CON_LIST) do
                if (idx - 1) % 3 == 0 then
                    ImGui.TableNextRow()
                end
                ImGui.TableSetColumnIndex((idx - 1) % 3)

                local curState = ctrl.pull_con_filter[conName] == true
                local newState, changed = ImGui.Checkbox(conName .. '##pullCon_' .. conName, curState)
                if changed then
                    ctrl.pull_con_filter[conName] = newState
                    runtime.saveLoadout(true)
                end
            end
            ImGui.EndTable()
        end


        accent(GOLD, 'NPCs to Pull (Include List)')
        accent(MUTED, 'If empty, pulls any mob in radius. If populated, ONLY pulls listed names.')

        if ImGui.Button('Pull Current Target##pullCurTgt', 170, 24) then
            local nm
            pcall(function() nm = mq.TLO.Target.CleanName() end)
            if nm and nm ~= '' then
                runtime.addPull(nm)
            else
                print('\ay[Triune]\ax no target selected.')
            end
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        runtime.pullInput = ImGui.InputText('##pullAddInput', runtime.pullInput or '')
        ImGui.SameLine()
        if ImGui.Button('Add##pullAddBtn') then
            if runtime.pullInput and runtime.pullInput ~= '' then
                runtime.addPull(runtime.pullInput); runtime.pullInput = ''
            end
        end

        if ImGui.BeginChild('pullListFrame', 0, 90, true) then
            if not runtime.pullList or #runtime.pullList == 0 then
                ImGui.TextDisabled('(all mobs allowed)')
            else
                for i, nm in ipairs(runtime.pullList) do
                    ImGui.PushID('pl_' .. i)
                    if ImGui.Button('x') then runtime.removePull(nm) end
                    ImGui.SameLine(); ImGui.Text(tostring(nm))
                    ImGui.PopID()
                end
            end
        end
        ImGui.EndChild()

        accent(GOLD, 'NPCs to Ignore (Ignore List)')
        accent(MUTED, 'Puller will NEVER auto-target these names (shared across all characters).')

        if ImGui.Button('Ignore Current Target##ignoreCurTgt', 170, 24) then
            local nm
            pcall(function() nm = mq.TLO.Target.CleanName() end)
            if nm and nm ~= '' then
                if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
                runtime.addIgnore(nm)
            else
                print('\ay[Triune]\ax no target selected.')
            end
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        runtime.ignoreInput = ImGui.InputText('##ignoreAddInput', runtime.ignoreInput or '')
        ImGui.SameLine()
        if ImGui.Button('Add##ignoreAddBtn') then
            if runtime.ignoreInput and runtime.ignoreInput ~= '' then
                runtime.addIgnore(runtime.ignoreInput); runtime.ignoreInput = ''
            end
        end

        if ImGui.BeginChild('ignoreListFrame', 0, 90, true) then
            if not runtime.ignoreList or #runtime.ignoreList == 0 then
                ImGui.TextDisabled('(none ignored)')
            else
                for i, nm in ipairs(runtime.ignoreList) do
                    ImGui.PushID('ig_' .. i)
                    if ImGui.Button('x') then runtime.removeIgnore(nm) end
                    ImGui.SameLine(); ImGui.Text(tostring(nm))
                    ImGui.PopID()
                end
            end
        end
        ImGui.EndChild()
    end

    -- Assist Mode Contextual Controls
    if ctrl.mode == 'Assist' then
        accent(GOLD, 'Main Assist Selection (by Player ID)')
        local candidates = runtime.getAssistCandidates()
        local comboLabels = {}
        local curIdx = 1
        for idx, c in ipairs(candidates) do
            table.insert(comboLabels, c.label)
            if ctrl.ma_id and ctrl.ma_id > 0 and c.id == ctrl.ma_id then
                curIdx = idx
            end
        end
        -- Fallback match by name if not matched by ID
        if curIdx == 1 and ctrl.ma_name and ctrl.ma_name ~= '' then
            for idx, c in ipairs(candidates) do
                if c.name:lower() == ctrl.ma_name:lower() then
                    curIdx = idx
                    if c.id > 0 then ctrl.ma_id = c.id end
                    break
                end
            end
        end

        ImGui.SetNextItemWidth(260)
        local newIdx = ImGui.Combo('##maSelectCombo', curIdx, comboLabels)
        if newIdx ~= curIdx then
            local chosen = candidates[newIdx]
            if chosen then
                ctrl.ma_id = chosen.id or 0
                ctrl.ma_name = chosen.name or ''
                runtime.saveLoadout(true)
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Select Main Assist by player ID.\nDynamically populated with current group members and custom targets.')
        end

        ImGui.SameLine()
        if ImGui.Button('+ Add Target##maAdd') then
            runtime.addCustomAssistTarget()
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Target a player character (PC) in game and click to add them to the assist dropdown.')
        end

        local selectedCandidate = candidates[curIdx]
        local isSelectedCustom = (selectedCandidate and selectedCandidate.source == 'custom')
        local selectedInCustom = false
        if selectedCandidate and selectedCandidate.name and selectedCandidate.name ~= '' and ctrl.custom_ma_list then
            for _, entry in ipairs(ctrl.custom_ma_list) do
                if entry.name:lower() == selectedCandidate.name:lower() then
                    selectedInCustom = true
                    break
                end
            end
        end
        local targetInCustom = false
        local tName = nil
        pcall(function()
            local t = mq.TLO.Target
            if t and t() and t.Type() == 'PC' then tName = t.CleanName() end
        end)
        if tName and tName ~= '' and ctrl.custom_ma_list then
            for _, entry in ipairs(ctrl.custom_ma_list) do
                if entry.name:lower() == tName:lower() then
                    targetInCustom = true
                    break
                end
            end
        end
        local canRemove = isSelectedCustom or selectedInCustom or targetInCustom

        ImGui.SameLine()
        if not canRemove then ImGui.BeginDisabled() end
        if ImGui.Button('Remove##maRemove') then
            runtime.removeCustomAssist()
        end
        if not canRemove then ImGui.EndDisabled() end
        if ImGui.IsItemHovered() then
            if canRemove then
                ImGui.SetTooltip('Remove the selected custom player (or current PC target) from the assist dropdown.')
            else
                ImGui.SetTooltip('Remove is only available for custom added players.\nGroup members are dynamically managed by group membership.')
            end
        end

        if runtime.maStatusMsg and os.clock() < (runtime.maStatusTimer or 0) then
            accent(WARN, runtime.maStatusMsg)
        end

        ImGui.SetNextItemWidth(160)
        ctrl.assist_at = ImGui.SliderInt('Assist At %', ctrl.assist_at or 98, 1, 100, '%d%%')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Target HP percentage at or below which this character will engage and attack the Main Assist\'s target.')
        end

        ImGui.SetNextItemWidth(180)
        ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##assistXtarDist', ctrl.xtar_nav_dist or 150, 25, 300)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget) or Main Assist target.')
        end

        ImGui.SetNextItemWidth(180)
        ctrl.chase_dist = ImGui.SliderInt('Chase Distance (Follow MA)##assistChaseDist', ctrl.chase_dist or 15, 5, 100, '%d ft')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('How far to stay back from the Main Assist when following (feet/units).\nWhen moving with the MA, the character will follow and hold position at this distance.')
        end

        ctrl.assist_self_defense = ImGui.Checkbox('Self-Defense When Attacked##assistSelfDefense', ctrl.assist_self_defense ~= false)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('When enabled, if the Main Assist has no active engaged target and an enemy attacks you, defend yourself.\nWhen the MA engages a target, the assistant will strictly focus on the MA target only.')
        end

        local behindVal = ImGui.Checkbox('Position Behind NPC##assistBehind', ctrl.assist_behind ~= false)
        if behindVal ~= (ctrl.assist_behind ~= false) then
            ctrl.assist_behind = behindVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('When enabled in Assist mode, positions the character behind the attacked NPC.\nThe Main Assist stays in front holding aggro, while assistants attack from the rear to avoid ripostes/blocks.\n(If this character pulls aggro, behind positioning suspends until aggro is cleared.)')
        end

        if ctrl.submode == 'Chase' then
            ctrl.chase = ImGui.Checkbox('Chase MA (Auto-Follow)', ctrl.chase)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Automatically follow and stay within Chase Distance of the Main Assist when not engaging an active target.')
            end
        elseif ctrl.submode == 'Camp' then
            accent(GOLD, 'Assist Camp Location')
            if ctrl.camp_loc then
                ImGui.Text(string.format('Camp set at: %.1f, %.1f, %.1f',
                    ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z))
            else
                accent(WARN, 'No camp location set -- character will stay at current spot.')
            end

            if ImGui.Button('Set Here##assistCampSet') then
                local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
                if mx and my and mz then ctrl.camp_loc = { x = mx, y = my, z = mz } end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Set the current location as the Assist Camp anchor point. Character will return here when idle.')
            end
            ImGui.SameLine()
            if ImGui.Button('Clear Camp##assistCampClear') then
                ctrl.camp_loc = nil
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Clear the Assist Camp anchor point. Character will hold wherever the previous fight ended.')
            end
        elseif ctrl.submode == 'Backline' then
            ctrl.chase = ImGui.Checkbox('Follow MA in Backline##backlineChase', ctrl.chase)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('When checked, follows the Main Assist at the configured Chase Distance when out of combat.\nWhen combat begins, holds backline position and assists with spells and ranged attacks without running into melee.')
            end
            accent(MUTED, 'Backline stays back at Chase Distance and assists MA with ranged/spells without moving to melee.')
        end
    end

    ImGui.EndTabItem()
end

function UI.drawPetControlTab()
    if not ImGui.BeginTabItem('Pets') then return end

    local petSlots, extraPets = getMultiPetList()

    -- 1. Global Pet Command Center (Compact Header & Telemetry)
    accent(GOLD, 'Pet Command Center')
    ImGui.SameLine()
    if ImGui.SmallButton('Re-Scan Pets##rescanGlobal') then
        reconcilePets()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Re-scan zone for active pets belonging to your character and update tracking.')
    end
    ImGui.SameLine()
    ImGui.TextDisabled('|')
    ImGui.SameLine()
    if petState.petHoldActive then
        accent(WARN, string.format('Auto Hold: ACTIVE (Holding until target HP <= %d%%)', ctrl.pet_assist_at or 100))
    else
        accent(GOOD, 'Auto Hold: DISENGAGED / ENGAGED')
    end

    -- Pet Assist Slider & Auto Hold Toggle at Top
    local petHoldVal = ImGui.Checkbox('Auto Pet Hold##petCtrlHold', ctrl.pet_hold_enabled ~= false)
    if petHoldVal ~= (ctrl.pet_hold_enabled ~= false) then
        ctrl.pet_hold_enabled = petHoldVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s',
            'Hold pets via "#petcmd hold all" whenever out of combat or prior\n'
            .. 'to reaching the Pet Assist HP threshold, releasing them on attack.')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    local petAssistVal = ImGui.SliderInt('Pet Assist At %##petCtrlAssist', ctrl.pet_assist_at or 100, 1, 100, '%d%%')
    if petAssistVal ~= ctrl.pet_assist_at then
        ctrl.pet_assist_at = petAssistVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s',
            'Send pets to attack once the target drops to or below this HP threshold\n'
            .. 'AND player is engaging. 100% = send immediately upon engagement.')
    end

    -- Primary Combat Actions (all on one line)
    if ImGui.Button('Attack All##atkGlobal') then sendPetCmd('attack', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Send all pets to attack current target (#petcmd attack all).') end
    ImGui.SameLine()
    if ImGui.Button('Back Off##backGlobal') then sendPetCmd('back', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Call all pets back to your side (#petcmd back all).') end
    ImGui.SameLine()
    if ImGui.Button('Follow##flwGlobal') then sendPetCmd('follow', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Order all pets to follow master (#petcmd follow all).') end
    ImGui.SameLine()
    if ImGui.Button('Stop##stopGlobal') then sendPetCmd('stop', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Stop all pets movement in place (#petcmd stop all).') end
    ImGui.SameLine()
    if ImGui.Button('Guard##guardGlobal') then sendPetCmd('guard', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Order all pets to guard current location (#petcmd guard all).') end
    ImGui.SameLine()
    if ImGui.Button('Sit##sitGlobal') then sendPetCmd('sit', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Order all pets to sit (#petcmd sit all).') end
    ImGui.SameLine()
    if ImGui.Button('Dismiss All##leaveGlobal') then sendPetCmd('leave', 'all') end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Dismiss all active pets (#petcmd leave all).') end

    -- Stance Toggles (compact 2-row layout)
    ImGui.TextDisabled('All Stances:')
    ImGui.SameLine()
    ImGui.Text('Taunt')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##tntOnGlobal') then sendPetCmd('taunt on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##tntOffGlobal') then sendPetCmd('taunt off', 'all') end
    ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
    ImGui.Text('Hold')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##hldOnGlobal') then sendPetCmd('hold on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##hldOffGlobal') then sendPetCmd('hold off', 'all') end
    ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
    ImGui.Text('GHold')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##ghldOnGlobal') then sendPetCmd('ghold on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##ghldOffGlobal') then sendPetCmd('ghold off', 'all') end

    ImGui.Text('SpellHold')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##sphOnGlobal') then sendPetCmd('spellhold on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##sphOffGlobal') then sendPetCmd('spellhold off', 'all') end
    ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
    ImGui.Text('Focus')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##fcsOnGlobal') then sendPetCmd('focus on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##fcsOffGlobal') then sendPetCmd('focus off', 'all') end
    ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
    ImGui.Text('Assist')
    ImGui.SameLine()
    if ImGui.SmallButton('ON##astOnGlobal') then sendPetCmd('assist on', 'all') end
    ImGui.SameLine()
    if ImGui.SmallButton('OFF##astOffGlobal') then sendPetCmd('assist off', 'all') end

    ImGui.Separator()

    -- 2. Trio Pet Telemetry & Individual Cards
    accent(GOLD, 'Active Trio Pet Telemetry')
    for _, slot in ipairs(petSlots) do
        local slotHeader = string.format('Slot %d: [%s] ', slot.slotNum, slot.cls)
        local info = getPetSpawnInfo(slot.petId)

        if slot.petId then
            slotHeader = slotHeader .. string.format('%s (Lvl %d %s, ID: %d)', info.cleanName, info.level, info.race, info.id)
        elseif slot.isPetCls then
            slotHeader = slotHeader .. '(Pet Missing / Not Summoned)'
        else
            slotHeader = slotHeader .. '(Non-Pet Class)'
        end

        local headerOpen = ImGui.CollapsingHeader(slotHeader .. '###slotHeader' .. slot.slotNum, ImGuiTreeNodeFlags.DefaultOpen)
        if headerOpen then
            if slot.petId then
                -- Row 1: Status badge line & action buttons
                accent(GOLD, string.format('[%s] %s', slot.cls, info.cleanName))
                ImGui.SameLine()
                if info.targetName ~= 'None' and info.targetName ~= '' then
                    accent(WARN, '[ENGAGED]')
                elseif petState.petHoldActive then
                    accent(GOLD, '[HOLD]')
                else
                    accent(GOOD, '[ALIVE]')
                end
                ImGui.SameLine()
                if ImGui.SmallButton('Target##targPet' .. slot.slotNum) then
                    mq.cmdf('/target id %d', info.id)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Target this pet in-game (/target id)')
                end
                ImGui.SameLine()
                if ImGui.SmallButton('/pet report##petRpt' .. slot.slotNum) then
                    petState.inspectPetId = slot.petId
                    petState.inspectSlot = slot
                    mq.cmdf('/target id %d', info.id)
                    mq.cmd('/pet report')
                    sendPetCmd('health', slot.scope)
                    ImGui.OpenPopup('Pet Stats Report##petStatsModal')
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Issue /pet report in chat & pop up detailed pet stats window')
                end

                -- Row 2: Target & Distance info
                ImGui.TextDisabled(string.format('Lvl %d %s (%.1fm)', info.level, info.race, info.dist))
                ImGui.SameLine()
                if info.targetName ~= 'None' and info.targetName ~= '' then
                    accent(ARC, string.format('Tgt: %s (%d%%)', info.targetName, info.targetHpPct))
                else
                    accent(MUTED, 'Tgt: None')
                end

                -- Row 3: Live HP Progress Bar
                local hpFrac = math.max(0, math.min(1.0, info.hpPct / 100.0))
                local r, g, b = 0.35, 0.75, 0.45
                if info.hpPct <= 25 then
                    r, g, b = 0.95, 0.35, 0.35
                elseif info.hpPct <= 50 then
                    r, g, b = 0.95, 0.75, 0.30
                end
                local hpBarText = string.format('HP: %d%% (%d / %d)', info.hpPct, info.curHp, info.maxHp)
                if info.maxHp == 0 then hpBarText = string.format('HP: %d%%', info.hpPct) end
                UI.drawStatusProgressBar(hpFrac, -1, 14, hpBarText, r, g, b, 1.0)

                -- Row 4: Buffs info
                if info.buffCount > 0 then
                    accent(ARC, string.format('Buffs (%d): ', info.buffCount))
                    ImGui.SameLine()
                    local buffStr = table.concat(info.buffs, ', ')
                    if #buffStr > 40 then
                        ImGui.Text(buffStr:sub(1, 37) .. '...')
                    else
                        ImGui.Text(buffStr)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', table.concat(info.buffs, '\n'))
                    end
                else
                    accent(MUTED, 'Buffs (0): ')
                    ImGui.SameLine()
                    ImGui.TextDisabled('None active')
                end

                -- Row 5: Individual Actions
                if ImGui.SmallButton(string.format('Attack##atk%d', slot.slotNum)) then
                    sendPetCmd('attack', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Back##back%d', slot.slotNum)) then
                    sendPetCmd('back', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Follow##flw%d', slot.slotNum)) then
                    sendPetCmd('follow', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Stop##stp%d', slot.slotNum)) then
                    sendPetCmd('stop', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Guard##grd%d', slot.slotNum)) then
                    sendPetCmd('guard', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Sit##sit%d', slot.slotNum)) then
                    sendPetCmd('sit', slot.scope)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Dismiss##lve%d', slot.slotNum)) then
                    sendPetCmd('leave', slot.scope)
                end

                -- Row 6: Individual Stances (compact 2-row layout)
                ImGui.TextDisabled(string.format('%s Stances:', slot.cls))
                ImGui.SameLine()
                ImGui.Text('Taunt')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##tntOn%d', slot.slotNum)) then sendPetCmd('taunt on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##tntOff%d', slot.slotNum)) then sendPetCmd('taunt off', slot.scope) end
                ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
                ImGui.Text('Hold')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##hldOn%d', slot.slotNum)) then sendPetCmd('hold on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##hldOff%d', slot.slotNum)) then sendPetCmd('hold off', slot.scope) end
                ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
                ImGui.Text('GHold')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##ghldOn%d', slot.slotNum)) then sendPetCmd('ghold on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##ghldOff%d', slot.slotNum)) then sendPetCmd('ghold off', slot.scope) end

                ImGui.Text('SpellHold')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##sphOn%d', slot.slotNum)) then sendPetCmd('spellhold on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##sphOff%d', slot.slotNum)) then sendPetCmd('spellhold off', slot.scope) end
                ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
                ImGui.Text('Focus')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##fcsOn%d', slot.slotNum)) then sendPetCmd('focus on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##fcsOff%d', slot.slotNum)) then sendPetCmd('focus off', slot.scope) end
                ImGui.SameLine(); ImGui.TextDisabled('|'); ImGui.SameLine()
                ImGui.Text('Assist')
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('ON##astOn%d', slot.slotNum)) then sendPetCmd('assist on', slot.scope) end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('OFF##astOff%d', slot.slotNum)) then sendPetCmd('assist off', slot.scope) end
            else
                accent(MUTED, string.format('No active pet detected for %s (%s).', slot.cls, slot.isPetCls and 'Pet-capable class' or 'Non-pet class'))
                if slot.isPetCls then
                    ImGui.SameLine()
                    if ImGui.SmallButton(string.format('Scan for Pet##scanSlot%d', slot.slotNum)) then
                        reconcilePets()
                    end
                end
            end
        end
    end

    -- 3. Extra / Swarm Pets
    if #extraPets > 0 then
        accent(GOLD, string.format('Additional Active Pets / Swarms (%d)', #extraPets))
        for idx, epid in ipairs(extraPets) do
            local einfo = getPetSpawnInfo(epid)
            ImGui.Text(string.format('[#%d] %s (Lvl %d, %.1fm)', idx, einfo.cleanName, einfo.level, einfo.dist))
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('Target##extraTarg%d', idx)) then
                mq.cmdf('/target id %d', einfo.id)
            end
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('/pet report##extraRpt%d', idx)) then
                petState.inspectPetId = epid
                petState.inspectSlot = { slotNum = idx, cls = 'Swarm', scope = 'swarm', isPetCls = true, petId = epid }
                mq.cmdf('/target id %d', einfo.id)
                mq.cmd('/pet report')
                sendPetCmd('health', 'swarm')
                ImGui.OpenPopup('Pet Stats Report##petStatsModal')
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'Issue /pet report & pop up detailed pet stats window')
            end
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('Attack##extraAtk%d', idx)) then
                sendPetCmd('attack', 'swarm')
            end
            ImGui.SameLine()
            if ImGui.SmallButton(string.format('Back##extraBack%d', idx)) then
                sendPetCmd('back', 'swarm')
            end
            local eHpFrac = math.max(0, math.min(1.0, einfo.hpPct / 100.0))
            UI.drawStatusProgressBar(eHpFrac, -1, 12, string.format('HP: %d%%', einfo.hpPct), 0.35, 0.75, 0.45, 1.0)
        end
    end


    -- 4. Pet Stats Report Modal Popup Window
    local _, petStatsModalDraw = ImGui.BeginPopupModal('Pet Stats Report##petStatsModal', true,
        ImGuiWindowFlags.AlwaysAutoResize)
    if petStatsModalDraw then
        local inspectId = petState.inspectPetId or 0
        local slot = petState.inspectSlot or { cls = 'Pet', scope = 'all', slotNum = 1 }
        local pinfo = getPetSpawnInfo(inspectId)

        if inspectId > 0 and isSpawnAlive(inspectId) then
            accent(GOLD, string.format('Pet Telemetry & Stat Report: [%s] %s', slot.cls, pinfo.cleanName))
            ImGui.Separator()

            -- Two-column layout for clean, readable stats
            ImGui.Columns(2, 'petStatsInspectCols', true)
            ImGui.SetColumnWidth(0, 250)

            -- Column 1: Identity & Physical Attributes
            accent(ARC, 'Identity & Position:')
            ImGui.Text(string.format('Clean Name: %s', pinfo.cleanName))
            ImGui.Text(string.format('Full Name: %s', pinfo.name))
            ImGui.Text(string.format('Trio Class: %s (Scope: %s)', slot.cls, slot.scope or 'all'))
            ImGui.Text(string.format('Race / Model: %s', pinfo.race))
            ImGui.Text(string.format('Spawn Class: %s', pinfo.class))
            ImGui.Text(string.format('Level: %d', pinfo.level))
            ImGui.Text(string.format('Spawn ID: %d', pinfo.id))
            ImGui.Text(string.format('Distance: %.1fm', pinfo.dist))
            ImGui.Text(string.format('Loc (Y, X, Z): %.1f, %.1f, %.1f', pinfo.y, pinfo.x, pinfo.z))
            ImGui.Text(string.format('Heading: %.0f°', pinfo.heading))
            ImGui.Text(string.format('Move Speed: %.1f', pinfo.speed))

            ImGui.NextColumn()

            -- Column 2: Vitals & Combat State
            accent(ARC, 'Vitals & Combat Engagement:')
            local hpBarText = string.format('HP: %d%% (%d / %d)', pinfo.hpPct, pinfo.curHp, pinfo.maxHp)
            if pinfo.maxHp == 0 then hpBarText = string.format('HP: %d%%', pinfo.hpPct) end
            local hpFrac = math.max(0, math.min(1.0, pinfo.hpPct / 100.0))
            local hr, hg, hb = 0.35, 0.75, 0.45
            if pinfo.hpPct <= 25 then
                hr, hg, hb = 0.95, 0.35, 0.35
            elseif pinfo.hpPct <= 50 then
                hr, hg, hb = 0.95, 0.75, 0.30
            end
            UI.drawStatusProgressBar(hpFrac, -1, 15, hpBarText, hr, hg, hb, 1.0)

            if pinfo.maxMana and pinfo.maxMana > 0 then
                local manaFrac = math.max(0, math.min(1.0, pinfo.manaPct / 100.0))
                UI.drawStatusProgressBar(manaFrac, -1, 13, string.format('Mana: %d%% (%d / %d)', pinfo.manaPct, pinfo.curMana, pinfo.maxMana), 0.25, 0.60, 0.95, 1.0)
            end

            if pinfo.targetName ~= 'None' and pinfo.targetName ~= '' then
                accent(WARN, string.format('Engaged Target: %s', pinfo.targetName))
                ImGui.Text(string.format('Target HP: %d%% | Target Dist: %.1fm', pinfo.targetHpPct, pinfo.targetDist))
            else
                accent(GOOD, 'Target: None (Idle / Following Master)')
            end

            ImGui.Text(string.format('Animation State: %s', pinfo.state))
            if pinfo.feigning then accent(WARN, 'Posture: Feigning Death') end
            if pinfo.sitting then accent(ARC, 'Posture: Sitting') end
            if pinfo.stunned then accent(ERR, 'Affliction: Stunned') end
            if pinfo.levitating then accent(ARC, 'Effect: Levitating') end

            -- Stance information if available from TLO Me.Pet
            pcall(function()
                if mq.TLO.Pet.ID() == pinfo.id then
                    local stance = mq.TLO.Pet.Stance()
                    if stance and stance ~= '' then
                        ImGui.Text(string.format('Master Pet Stance: %s', stance))
                    end
                end
            end)

            ImGui.Columns(1)
            ImGui.Separator()

            -- Active Buffs
            accent(ARC, string.format('Active Buffs & Effects (%d):', pinfo.buffCount))
            if pinfo.buffCount > 0 and #pinfo.buffs > 0 then
                if ImGui.BeginChild('petModalBuffsChild', 500, 70, true) then
                    for bIdx, bName in ipairs(pinfo.buffs) do
                        ImGui.Text(string.format('%d. %s', bIdx, bName))
                    end
                end
                ImGui.EndChild()
            else
                ImGui.TextDisabled('No active beneficial spells or buffs detected on pet.')
            end

            ImGui.Separator()

            -- Action buttons in popup
            if ImGui.Button('Target Pet##popupTargetBtn') then
                mq.cmdf('/target id %d', pinfo.id)
            end
            ImGui.SameLine()
            if ImGui.Button('/pet report##popupRptBtn') then
                mq.cmdf('/target id %d', pinfo.id)
                mq.cmd('/pet report')
                sendPetCmd('health', slot.scope or 'all')
            end
            ImGui.SameLine()
            if ImGui.Button(string.format('Attack (%s)##popupAtkBtn', slot.scope or 'all')) then
                sendPetCmd('attack', slot.scope or 'all')
            end
            ImGui.SameLine()
            if ImGui.Button(string.format('Back (%s)##popupBackBtn', slot.scope or 'all')) then
                sendPetCmd('back', slot.scope or 'all')
            end
            ImGui.SameLine()
            if ImGui.Button('Close##closePetModalBtn') then
                ImGui.CloseCurrentPopup()
            end
        else
            accent(ERR, 'Selected pet is no longer alive or not found in zone.')
            if ImGui.Button('Close##closePetModalDeadBtn') then
                ImGui.CloseCurrentPopup()
            end
        end
        ImGui.EndPopup()
    end

    ImGui.EndTabItem()
end

-- ============================================================================
-- Window Layout & Position Management Engine
-- ============================================================================

-- Core-owned windows. Every plugin that declares `plugin.window` is appended
-- automatically by runtime.getManagedWindows() (position key = window.key or
-- the plugin id, lock = window.lockFlag / getLock+setLock), so a new plugin
-- window shows up on Settings -> Windows without touching this list.
runtime.CORE_WINDOWS = {
    {
        key = 'main',
        name = 'Main AutoCombat Window',
        short = 'Main',
        desc = 'Core Triune interface with tabs and controls',
        canLock = false,
        getOpen = function() return open and not ctrl.compact end,
        setOpen = function(val)
            open = val
            if val then ctrl.compact = false end
        end,
    },
    {
        key = 'mini',
        name = 'Mini HUD Window',
        short = 'Mini HUD',
        desc = 'Compact HUD overlay widget',
        canLock = false,
        getOpen = function() return open and ctrl.compact end,
        setOpen = function(val)
            open = val
            if val then ctrl.compact = true end
        end,
    },
}

-- Window Layout entries built from the plugin manager's window declarations.
-- Entries are cached per plugin id and rebuilt only when the set of window
-- plugins changes, so the settings page does not allocate closures per frame.
runtime.pluginWindowDefs = {}
function runtime.getManagedWindows()
    local out = {}
    for _, d in ipairs(runtime.CORE_WINDOWS or {}) do out[#out + 1] = d end
    local pm = runtime.pluginManager
    if not pm or not pm.windowPlugins then return out end
    if not runtime.pluginWindowDefs then runtime.pluginWindowDefs = {} end
    for _, e in ipairs(pm.windowPlugins(false)) do
        local id, w = e.id, e.window
        local def = runtime.pluginWindowDefs[id]
        if not def or def.window ~= w then
            local p = pm.plugins[id]
            local lockFlag = type(w.lockFlag) == 'string' and w.lockFlag or nil
            local canLock = (lockFlag ~= nil) or (type(w.getLock) == 'function' and type(w.setLock) == 'function')
            def = {
                key = tostring(w.key or id),
                name = tostring(w.name or (p and p.name) or w.label or id),
                short = tostring(w.label or (p and p.name) or id),
                desc = tostring(w.desc or w.tooltip or (p and p.description) or ''),
                pluginId = id,
                window = w,
                canLock = canLock,
                getOpen = function() return pm.isWindowOpen(id) end,
                setOpen = function(val) pm.setWindowOpen(id, val) end,
            }
            if canLock then
                if lockFlag then
                    def.getLock = function() return ctrl[lockFlag] == true end
                    def.setLock = function(val)
                        ctrl[lockFlag] = (val == true)
                        runtime.saveLoadout(true)
                    end
                else
                    def.getLock = function()
                        local ok, res = pcall(w.getLock)
                        return ok and res == true
                    end
                    def.setLock = function(val)
                        pcall(w.setLock, val == true)
                        runtime.saveLoadout(true)
                    end
                end
            end
            runtime.pluginWindowDefs[id] = def
        end
        out[#out + 1] = def
    end
    return out
end

function runtime.checkDisplaySizeChange()
    local now = os.clock()
    if runtime.lastDisplayCheckAt and (now - runtime.lastDisplayCheckAt) < 0.25 then return end
    runtime.lastDisplayCheckAt = now
    local curW, curH = 0, 0
    pcall(function()
        local io = ImGui.GetIO()
        if io and io.DisplaySize then
            curW = math.floor(io.DisplaySize.x + 0.5)
            curH = math.floor(io.DisplaySize.y + 0.5)
        end
    end)
    if curW > 200 and curH > 200 then
        if runtime.lastDisplayWidth and runtime.lastDisplayHeight then
            if (curW ~= runtime.lastDisplayWidth or curH ~= runtime.lastDisplayHeight) then
                if ctrl.winpos_auto_restore_on_resize and ctrl.saved_window_positions and next(ctrl.saved_window_positions) then
                    runtime.triggerRestoreWindows()
                    print(string.format('\ag[Triune]\ax Display resolution changed (%dx%d -> %dx%d). Auto-restored saved window positions.',
                        runtime.lastDisplayWidth, runtime.lastDisplayHeight, curW, curH))
                end
            end
        end
        runtime.lastDisplayWidth = curW
        runtime.lastDisplayHeight = curH
    end
end

function UI.preBeginWindow(winKey)
    runtime.checkDisplaySizeChange()
    local pending = runtime.pendingWindowRestore and runtime.pendingWindowRestore[winKey]
    if pending then
        local cond = (ImGuiCond and ImGuiCond.Always) or 1
        pcall(ImGui.SetNextWindowPos, pending.x, pending.y, cond)
        if pending.w and pending.h and pending.w > 20 and pending.h > 20 then
            pcall(ImGui.SetNextWindowSize, pending.w, pending.h, cond)
        end
        pending.frames = (pending.frames or 1) - 1
        if pending.frames <= 0 then
            runtime.pendingWindowRestore[winKey] = nil
        end
    end
end

function UI.postBeginWindow(winKey)
    if not runtime.liveWindowPositions then runtime.liveWindowPositions = {} end
    local px, py, pw, ph = 0, 0, 0, 0
    pcall(function()
        if ImGui.GetWindowPosVec then
            local pos = ImGui.GetWindowPosVec()
            if pos then px, py = pos.x, pos.y end
        elseif ImGui.GetWindowPos then
            px, py = ImGui.GetWindowPos()
            if type(px) == 'userdata' or type(px) == 'table' then
                px, py = px.x, px.y
            end
        end
        if ImGui.GetWindowSizeVec then
            local sz = ImGui.GetWindowSizeVec()
            if sz then pw, ph = sz.x, sz.y end
        elseif ImGui.GetWindowSize then
            pw, ph = ImGui.GetWindowSize()
            if type(pw) == 'userdata' or type(pw) == 'table' then
                pw, ph = pw.x, pw.y
            end
        end
    end)
    if (px ~= 0 or py ~= 0 or pw ~= 0 or ph ~= 0) then
        runtime.liveWindowPositions[winKey] = {
            x = math.floor(px + 0.5),
            y = math.floor(py + 0.5),
            w = math.floor(pw + 0.5),
            h = math.floor(ph + 0.5),
            updated = os.clock(),
        }
    end
end

function runtime.saveWindowPositions(silent)
    if not ctrl.saved_window_positions then ctrl.saved_window_positions = {} end
    local count = 0
    for _, def in ipairs(runtime.getManagedWindows()) do
        local live = runtime.liveWindowPositions and runtime.liveWindowPositions[def.key]
        local isOpen = def.getOpen and def.getOpen() or false
        if live and live.x and live.y then
            ctrl.saved_window_positions[def.key] = {
                x = live.x,
                y = live.y,
                w = live.w,
                h = live.h,
                open = isOpen,
            }
            count = count + 1
        elseif ctrl.saved_window_positions[def.key] then
            ctrl.saved_window_positions[def.key].open = isOpen
            count = count + 1
        end
    end
    ctrl.saved_window_positions_at = os.time()
    runtime.saveLoadout(true)
    if not silent then
        print(string.format('\ag[Triune]\ax Saved positions for \ay%d\ax window(s).', count))
    end
    return count
end

function runtime.triggerRestoreWindows(includeVisibility)
    if not ctrl.saved_window_positions or not next(ctrl.saved_window_positions) then
        print('\ay[Triune]\ax No saved window positions found. Click "Save Current Window Positions" first.')
        return 0
    end
    if not runtime.pendingWindowRestore then runtime.pendingWindowRestore = {} end
    local count = 0
    for winKey, pos in pairs(ctrl.saved_window_positions) do
        if type(pos) == 'table' and pos.x and pos.y then
            runtime.pendingWindowRestore[winKey] = {
                x = pos.x,
                y = pos.y,
                w = pos.w,
                h = pos.h,
                frames = 3,
            }
            count = count + 1
        end
    end
    if includeVisibility or ctrl.winpos_restore_visibility then
        for _, def in ipairs(runtime.getManagedWindows()) do
            local saved = ctrl.saved_window_positions[def.key]
            if saved and saved.open ~= nil and def.setOpen then
                def.setOpen(saved.open)
            end
        end
        runtime.saveLoadout(true)
    end
    return count
end

function runtime.resetWindowPositionsToDefault()
    local screenW, screenH = 1920, 1080
    pcall(function()
        local io = ImGui.GetIO()
        if io and io.DisplaySize and io.DisplaySize.x > 200 then
            screenW = math.floor(io.DisplaySize.x)
            screenH = math.floor(io.DisplaySize.y)
        end
    end)
    local defaults = {
        main        = { x = math.floor(screenW * 0.20), y = math.floor(screenH * 0.12), w = 830, h = 640 },
        mini        = { x = 20, y = 20, w = 240, h = 120 },
        unit_frames = { x = math.floor(screenW * 0.35), y = math.floor(screenH * 0.60), w = 320, h = 180 },
        group       = { x = 20, y = 100, w = 220, h = 240 },
        effects     = { x = math.max(10, screenW - 320), y = 30, w = 300, h = 350 },
        cooldowns   = { x = math.floor(screenW * 0.35), y = math.floor(screenH * 0.78), w = 500, h = 160 },
        xtarget     = { x = math.max(10, screenW - 260), y = math.floor(screenH * 0.45), w = 240, h = 260 },
        spell_gems  = { x = 20, y = math.floor(screenH * 0.65), w = 180, h = 320 },
        character   = { x = math.floor(screenW * 0.50), y = math.floor(screenH * 0.20), w = 520, h = 420 },
    }
    -- Plugin windows may ship their own desktop default (window.defaultPos = { x, y, w, h }).
    for _, def in ipairs(runtime.getManagedWindows()) do
        local dp = def.window and def.window.defaultPos
        if type(dp) == 'table' and dp.x and dp.y and not defaults[def.key] then
            defaults[def.key] = { x = dp.x, y = dp.y, w = dp.w or 320, h = dp.h or 240 }
        end
    end
    if not runtime.pendingWindowRestore then runtime.pendingWindowRestore = {} end
    for k, v in pairs(defaults) do
        runtime.pendingWindowRestore[k] = { x = v.x, y = v.y, w = v.w, h = v.h, frames = 3 }
    end
    print('\ag[Triune]\ax Reset all window positions to desktop defaults.')
end

function runtime.centerWindow(winKey)
    local screenW, screenH = 1920, 1080
    pcall(function()
        local io = ImGui.GetIO()
        if io and io.DisplaySize and io.DisplaySize.x > 200 then
            screenW = math.floor(io.DisplaySize.x)
            screenH = math.floor(io.DisplaySize.y)
        end
    end)
    local live = runtime.liveWindowPositions and runtime.liveWindowPositions[winKey]
    local w = (live and live.w and live.w > 50) and live.w or 320
    local h = (live and live.h and live.h > 50) and live.h or 220
    local cx = math.max(10, math.floor((screenW - w) / 2))
    local cy = math.max(10, math.floor((screenH - h) / 2))

    if not runtime.pendingWindowRestore then runtime.pendingWindowRestore = {} end
    runtime.pendingWindowRestore[winKey] = {
        x = cx,
        y = cy,
        w = w,
        h = h,
        frames = 3,
    }
    if not runtime.liveWindowPositions then runtime.liveWindowPositions = {} end
    runtime.liveWindowPositions[winKey] = { x = cx, y = cy, w = w, h = h, updated = os.clock() }
    print(string.format('\ag[Triune]\ax Centered window "%s" to screen center (%d, %d).', winKey, cx, cy))
end

function runtime.restoreSingleWindow(winKey)
    local saved = ctrl.saved_window_positions and ctrl.saved_window_positions[winKey]
    if not saved or not saved.x or not saved.y then
        print(string.format('\ay[Triune]\ax No saved position found for window "%s".', winKey))
        return false
    end
    if not runtime.pendingWindowRestore then runtime.pendingWindowRestore = {} end
    runtime.pendingWindowRestore[winKey] = {
        x = saved.x,
        y = saved.y,
        w = saved.w,
        h = saved.h,
        frames = 3,
    }
    print(string.format('\ag[Triune]\ax Restored window "%s" to saved position (%d, %d).', winKey, saved.x, saved.y))
    return true
end

function runtime.saveSingleWindow(winKey)
    local live = runtime.liveWindowPositions and runtime.liveWindowPositions[winKey]
    if not live or not live.x or not live.y then
        print(string.format('\ay[Triune]\ax Window "%s" must be open to save its position.', winKey))
        return false
    end
    if not ctrl.saved_window_positions then ctrl.saved_window_positions = {} end
    local def = nil
    for _, d in ipairs(runtime.getManagedWindows()) do
        if d.key == winKey then def = d; break end
    end
    local isOpen = def and def.getOpen and def.getOpen() or false
    ctrl.saved_window_positions[winKey] = {
        x = live.x,
        y = live.y,
        w = live.w,
        h = live.h,
        open = isOpen,
    }
    ctrl.saved_window_positions_at = os.time()
    runtime.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Saved position for window "%s" (%d, %d) [%dx%d].', winKey, live.x, live.y, live.w or 0, live.h or 0))
    return true
end

function UI.drawWindowSettings()
    accent(GOLD, 'Window Layout & Position Persistence')
    ImGui.TextDisabled('Save and restore exact screen coordinates and dimensions for all Triune popout windows.\nPrevents window scrambling caused by monitor power-off, display sleep, or resolution changes.')
    ImGui.Separator()

    -- Primary Action Toolbar
    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
    local pushedColors = 0

    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.16, 0.50, 0.22, 1.0) then
        pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.20, 0.62, 0.28, 1.0)
        pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.12, 0.40, 0.18, 1.0)
        pushedColors = pushedColors + 3
    end
    if ImGui.Button('Save Current Positions##winSaveAll', 180, 26) then
        runtime.saveWindowPositions(false)
    end
    if pushedColors > 0 then
        pcall(ImGui.PopStyleColor, pushedColors)
        pushedColors = 0
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Snapshots the current screen coordinates (X, Y) and sizes (W, H)\nof all open Triune windows and saves them to your character loadout.')
    end

    ImGui.SameLine()
    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.18, 0.38, 0.62, 1.0) then
        pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.22, 0.48, 0.78, 1.0)
        pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.14, 0.30, 0.50, 1.0)
        pushedColors = pushedColors + 3
    end
    if ImGui.Button('Restore Saved Positions##winRestoreAll', 180, 26) then
        local cnt = runtime.triggerRestoreWindows()
        print(string.format('\ag[Triune]\ax Restored positions for \ay%d\ax window(s).', cnt))
    end
    if pushedColors > 0 then
        pcall(ImGui.PopStyleColor, pushedColors)
        pushedColors = 0  -- luacheck: ignore 311
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Restores all windows to their previously saved screen coordinates and dimensions.')
    end

    ImGui.SameLine()
    if ImGui.Button('Reset to Defaults##winResetAll', 150, 26) then
        runtime.resetWindowPositionsToDefault()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Re-positions all windows to clean, sensible defaults on your current display.')
    end

    -- Options and metadata
    ImGui.Spacing()
    local autoResVal = ImGui.Checkbox('Auto-Restore on Display Resolution / Monitor Change', ctrl.winpos_auto_restore_on_resize ~= false)
    if autoResVal ~= (ctrl.winpos_auto_restore_on_resize ~= false) then
        ctrl.winpos_auto_restore_on_resize = autoResVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically detects when your monitor wakes up or resolution restores\nand snaps all windows back to their saved positions immediately.')
    end

    ImGui.SameLine()
    local visVal = ImGui.Checkbox('Include Open/Closed Visibility on Restore', ctrl.winpos_restore_visibility or false)
    if visVal ~= (ctrl.winpos_restore_visibility or false) then
        ctrl.winpos_restore_visibility = visVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'When restoring, also opens or closes windows to match their state when saved.')
    end

    -- Status line
    local savedTimeStr = 'Never'
    if ctrl.saved_window_positions_at and ctrl.saved_window_positions_at > 0 then
        savedTimeStr = tostring(os.date('%Y-%m-%d %H:%M:%S', ctrl.saved_window_positions_at))
    end
    local dispW = runtime.lastDisplayWidth or 0
    local dispH = runtime.lastDisplayHeight or 0
    if dispW == 0 then
        pcall(function()
            local io = ImGui.GetIO()
            if io and io.DisplaySize then dispW = math.floor(io.DisplaySize.x); dispH = math.floor(io.DisplaySize.y) end
        end)
    end
    ImGui.TextDisabled(string.format('Display: %dx%d  |  Last Saved: %s  |  Tracked Windows: %d',
        dispW, dispH, savedTimeStr, #runtime.getManagedWindows()))

    ImGui.Spacing()
    accent(GOLD, 'Triune Popout Windows:')

    -- Managed Windows Table
    local tblFlags = bit.bor(
        (ImGuiTableFlags and ImGuiTableFlags.Borders) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.RowBg) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.SizingFixedFit) or 0
    )
    if ImGui.BeginTable('ManagedWinTable', 6, tblFlags) then
        ImGui.TableSetupColumn('Window', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 180)
        ImGui.TableSetupColumn('Status', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 95)
        ImGui.TableSetupColumn('Live Pos (X, Y) [W x H]', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 150)
        ImGui.TableSetupColumn('Saved Pos (X, Y) [W x H]', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 150)
        ImGui.TableSetupColumn('Locked', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 50)
        ImGui.TableSetupColumn('Actions', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 175)
        ImGui.TableHeadersRow()

        for _, def in ipairs(runtime.getManagedWindows()) do
            ImGui.TableNextRow()
            local isOpen = def.getOpen and def.getOpen() or false
            local live = runtime.liveWindowPositions and runtime.liveWindowPositions[def.key]
            local saved = ctrl.saved_window_positions and ctrl.saved_window_positions[def.key]

            -- Col 1: Window Name & short tag
            ImGui.TableNextColumn()
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], def.short)
            ImGui.SameLine()
            ImGui.TextDisabled('(' .. def.key .. ')')
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s\n%s', def.name, def.desc or '')
            end

            -- Col 2: Status
            ImGui.TableNextColumn()
            if isOpen then
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'OPEN')
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'CLOSED')
            end
            ImGui.SameLine()
            if ImGui.SmallButton((isOpen and 'Hide##' or 'Show##') .. def.key) then
                if def.setOpen then def.setOpen(not isOpen) end
            end

            -- Col 3: Live Pos & Size
            ImGui.TableNextColumn()
            if live and live.x and live.y then
                ImGui.Text(string.format('%d, %d [%dx%d]', live.x, live.y, live.w or 0, live.h or 0))
            else
                ImGui.TextDisabled(isOpen and 'Tracking...' or '--')
            end

            -- Col 4: Saved Pos & Size
            ImGui.TableNextColumn()
            if saved and saved.x and saved.y then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('%d, %d [%dx%d]', saved.x, saved.y, saved.w or 0, saved.h or 0))
            else
                ImGui.TextDisabled('None')
            end

            -- Col 5: Locked toggle
            ImGui.TableNextColumn()
            if def.canLock and def.getLock and def.setLock then
                local isLocked = def.getLock()
                local newLock = ImGui.Checkbox('##lock' .. def.key, isLocked)
                if newLock ~= isLocked then
                    def.setLock(newLock)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', isLocked and 'Window is locked (cannot be dragged or resized)' or 'Window is unlocked')
                end
            else
                ImGui.TextDisabled('--')
            end

            -- Col 6: Actions
            ImGui.TableNextColumn()
            if ImGui.SmallButton('Center##' .. def.key) then
                runtime.centerWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Center "%s" on your current display.', def.name)
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Restore##' .. def.key) then
                runtime.restoreSingleWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Restore "%s" to its saved coordinates.', def.name)
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Save##' .. def.key) then
                runtime.saveSingleWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Save current position for "%s".', def.name)
            end
        end

        ImGui.EndTable()
    end

    -- External Triune Tools Quick Launchers
    ImGui.Spacing()
    if ImGui.CollapsingHeader('External Triune Tools & Windows', ImGuiTreeNodeFlags.None) then
        ImGui.TextDisabled('Toggle the Triune companion tool windows (plugins in lua/tac):')
        ImGui.Spacing()
        if ImGui.Button('Inventory & Bank Manager##extInv') then
            ctrl.show_inv = not ctrl.show_inv
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Zone Map & NPC Tracker##extMap') then
            ctrl.show_map = not ctrl.show_map
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Spellbook Browser##extBook') then
            ctrl.show_spellbook = not ctrl.show_spellbook
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Live DPS Parser##extDps') then
            ctrl.show_dps = not ctrl.show_dps
            runtime.saveLoadout(true)
        end

        if ImGui.Button('Cursor Item Manager##extCur') then
            ctrl.show_cursor = not ctrl.show_cursor
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Buffbot Station##extBuff') then
            ctrl.show_buffbot = not ctrl.show_buffbot
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Quick Hotbuttons##extBtns') then
            mq.cmd('/lua run triune_buttons')
        end
    end
end

function UI.drawSettingsTab()
    if not ImGui.BeginTabItem('Settings') then return end

    if ImGui.BeginTabBar('settingsSubTabBar') then
        if ImGui.BeginTabItem('General Settings##settingsGeneral') then
            -- 1. Character Classes & Profile
            UI.drawClassPicker()

    -- 2. Combat & Positioning
    if ImGui.CollapsingHeader('Combat & Positioning', ImGuiTreeNodeFlags.DefaultOpen) then
        ImGui.SetNextItemWidth(200)
        local newDist, changed = ImGui.SliderInt('Melee Distance##meleeRangeSlider', ctrl.melee_dist or 14, 5, 50)
        if changed or (newDist and newDist ~= ctrl.melee_dist) then
            ctrl.melee_dist = newDist
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Max melee distance to position at and strike targets (default: 14).\n'
                .. 'Adjust to stick tighter (e.g. 8-10) or fight from further away (e.g. 15-25).')
        end

        local losVal = ImGui.Checkbox('Re-face Instead Of Stepping Back On Lost Line-of-Sight', ctrl.los_face_only or false)
        if losVal ~= (ctrl.los_face_only or false) then
            ctrl.los_face_only = losVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'On "cannot see target", just turn to face it instead of stepping\n'
                .. 'back and strafing. Useful in tight spaces or areas cluttered\n'
                .. 'with obstacles, where stepping back can wedge you against a\n'
                .. 'wall/prop instead of helping. Off by default.')
        end

        accent(GOLD, 'Spell Failures & Lockouts:')
        ImGui.SetNextItemWidth(160)
        local retriesVal = ImGui.SliderInt('Max Retries##cmr', ctrl.cast_max_retries or 2, 1, 10)
        if retriesVal ~= ctrl.cast_max_retries then
            ctrl.cast_max_retries = retriesVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Consecutive failed debuff/ability attempts before temporarily backing off on that target.\nDefault: 2 tries.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(160)
        local lockoutVal = ImGui.SliderInt('Lockout Time##castLockoutSec', ctrl.cast_lockout_sec or 30, 5, 300, '%d s')
        if lockoutVal ~= ctrl.cast_lockout_sec then
            ctrl.cast_lockout_sec = lockoutVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Seconds to back off before retrying a resisted debuff or locked spell.\nDefault: 30 seconds.')
        end
        ImGui.SameLine()
        local activeLocks = castTracker and castTracker.getActiveCount and castTracker.getActiveCount() or 0
        local clearLabel = (activeLocks > 0) and string.format('Clear Lockouts (%d)##clearLocksBtn', activeLocks) or 'Clear Lockouts##clearLocksBtn'
        if ImGui.Button(clearLabel) then
            if castTracker and castTracker.clear then
                castTracker.clear()
                print('\ag[Triune]\ax Cleared all active spell lockouts, target backoffs, and mob immunities.')
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Instantly clear all active spell lockouts, non-stacking buff backoffs, and mob immunities.')
        end
    end


    -- 3. Navigation & Hazard Avoidance
    if ImGui.CollapsingHeader('Navigation & Hazard Avoidance', ImGuiTreeNodeFlags.DefaultOpen) then
        if not navLoaded() then
            accent(WARN, 'MQ2Nav is NOT loaded! Navigation and pathfinding require MQ2Nav.')
            ImGui.SameLine()
            if ImGui.Button('Load MQ2Nav##settingsLoadNav') then
                mq.cmd('/plugin mq2nav')
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /plugin mq2nav to load the MQ2Nav plugin.')
            end
        elseif not navMeshLoaded() then
            local curZone = mq.TLO.Zone.ShortName() or 'current zone'
            accent(WARN, string.format('No NavMesh loaded for zone "%s" (/nav reload).', curZone))
            ImGui.SameLine()
            if ImGui.Button('Reload Mesh##settingsReloadMesh') then
                mq.cmd('/nav reload')
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /nav reload to attempt reloading the zone navmesh.')
            end
        end
        if not stickLoaded() then
            accent(WARN, 'MQ2MoveUtils is NOT loaded! Combat positioning and stick require MQ2MoveUtils.')
            ImGui.SameLine()
            if ImGui.Button('Load MQ2MoveUtils##settingsLoadMoveUtils') then
                mq.cmd('/plugin mq2moveutils')
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /plugin mq2moveutils to load the MQ2MoveUtils plugin.')
            end
        end

        local hazVal = ImGui.Checkbox('Auto-Avoid Stuck Hotspots', ctrl.nav_hazard_avoidance ~= false)
        if hazVal ~= (ctrl.nav_hazard_avoidance ~= false) then
            ctrl.nav_hazard_avoidance = hazVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Remembers locations where the character repeatedly gets stuck and routes around them with detour waypoints.')
        end
        ImGui.SameLine()
        local rbcVal = ImGui.Checkbox('Reverse Breadcrumbs on Pull Return', ctrl.nav_reverse_breadcrumbs ~= false)
        if rbcVal ~= (ctrl.nav_reverse_breadcrumbs ~= false) then
            ctrl.nav_reverse_breadcrumbs = rbcVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('In Puller Camp mode, remembers the exact path taken to the mob and walks back in reverse to guarantee a safe return to camp.')
        end

        local doorVal = ImGui.Checkbox('Proactive Door & Gate Opening', ctrl.nav_proactive_doors ~= false)
        if doorVal ~= (ctrl.nav_proactive_doors ~= false) then
            ctrl.nav_proactive_doors = doorVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Predictively opens closed doors in your movement path before hitting them.')
        end
        ImGui.SameLine()
        local levVal = ImGui.Checkbox('Levitation Archway Duck-to-Clear', ctrl.nav_levitation_clear ~= false)
        if levVal ~= (ctrl.nav_levitation_clear ~= false) then
            ctrl.nav_levitation_clear = levVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Momentarily ducks under low door frames/archways if levitating to prevent ceiling snags.')
        end

        local stickVal = ImGui.Checkbox('Fallback to Stick on Nav Failure', ctrl.nav_fallback_stick or false)
        if stickVal ~= (ctrl.nav_fallback_stick or false) then
            ctrl.nav_fallback_stick = stickVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Off-mesh holes already stick toward the target and remap\n'
                .. 'nav once a path exists. This checkbox keeps /stick going\n'
                .. 'even after that recovery gives up -- which walks straight\n'
                .. 'at whatever wall is blocking the path.\n'
                .. 'Off by default: unreachable targets are dropped instead.')
        end

        ImGui.SetNextItemWidth(180)
        local newRatio = ImGui.SliderFloat('Max Path / Dist Ratio##navMaxPathRatio', ctrl.nav_max_path_ratio or 2.5, 1.2, 5.0, '%.1fx')
        if newRatio and newRatio ~= ctrl.nav_max_path_ratio then
            ctrl.nav_max_path_ratio = newRatio
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Rejects targets if NavMesh PathLength exceeds this multiple of direct 3D distance.\nFilters out mobs across walls or on high balconies requiring long dungeon detours.')
        end

        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        local newHzRad = ImGui.SliderInt('Hazard Radius##navHazardRadius', ctrl.nav_hazard_radius or 15, 8, 35, '%d units')
        if newHzRad and newHzRad ~= ctrl.nav_hazard_radius then
            ctrl.nav_hazard_radius = newHzRad
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Avoidance radius around learned stuck hotspots.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        local newDecayMin = ImGui.SliderInt('Forget Time##navHazardForget', ctrl.nav_hazard_decay_minutes or 10, 1, 60, '%d min')
        if newDecayMin and newDecayMin ~= ctrl.nav_hazard_decay_minutes then
            ctrl.nav_hazard_decay_minutes = newDecayMin
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Every N minutes without a fresh stuck event, a hotspot loses one hit and eventually deactivates below the active threshold.')
        end

        local curZs = runtime.getCurrentZoneShortName and runtime.getCurrentZoneShortName() or 'unknown'
        local zoneHz = runtime.getZoneHazards and runtime.getZoneHazards(curZs) or {}
        local activeCount = 0
        for _, h in ipairs(zoneHz) do
            if (h.hits or 1) >= (ctrl.nav_hazard_min_hits or 2) then
                activeCount = activeCount + 1
            end
        end
        ImGui.TextDisabled(string.format('Zone "%s": %d hazard hotspot(s) logged (%d active)', curZs, #zoneHz, activeCount))
        ImGui.SameLine()
        if ImGui.Button('Clear Zone Hazards##clearHzBtn') then
            if runtime.clearZoneHazards then runtime.clearZoneHazards(curZs) end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Clears all recorded stuck hotspots for the current zone.')
        end
    end


    -- 4. Closer-NPC Retargeting During Movement
    if ImGui.CollapsingHeader('Closer-NPC Retargeting During Movement', ImGuiTreeNodeFlags.DefaultOpen) then
        local chkVal = ImGui.Checkbox('Switch to Closer Mobs While Traveling', ctrl.check_closer_mobs ~= false)
        if chkVal ~= (ctrl.check_closer_mobs ~= false) then
            ctrl.check_closer_mobs = chkVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Allows switching to a significantly closer mob if one is encountered while traveling toward a distant target.')
        end
        ImGui.SameLine()
        local coneVal = ImGui.Checkbox('Forward Arc Cone Only (+/-75 deg)', ctrl.closer_forward_cone_only ~= false)
        if coneVal ~= (ctrl.closer_forward_cone_only ~= false) then
            ctrl.closer_forward_cone_only = coneVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Only retargets to closer mobs that lie in front of your movement direction, preventing 180 degree turnarounds.')
        end

        local losPrioVal = ImGui.Checkbox('Prioritize Visible Line-of-Sight Mobs', ctrl.closer_los_priority ~= false)
        if losPrioVal ~= (ctrl.closer_los_priority ~= false) then
            ctrl.closer_los_priority = losPrioVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Prioritizes closer mobs with direct Line of Sight if your distant target is obstructed behind walls/corners.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        local curRetargets = ctrl.max_closer_retargets or 1
        local retargetFmt = (curRetargets == 0) and 'Disabled (0)' or '%d retarget(s)'
        local newMaxRetargets = ImGui.SliderInt('Max Retargets Per Leg##maxCloserRetargets', curRetargets, 0, 5, retargetFmt)
        if newMaxRetargets and newMaxRetargets ~= ctrl.max_closer_retargets then
            ctrl.max_closer_retargets = newMaxRetargets
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Max times to switch to closer mobs during a single travel leg (0 = disabled / lock to first mob).')
        end
    end


    -- 5. Resting & Resource Management
    if ImGui.CollapsingHeader('Resting & Resource Management', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Combat Recovery & Pull Thresholds:')
        ImGui.SetNextItemWidth(180)
        local minManaVal = ImGui.SliderInt('Min Mana %##mmp', ctrl.min_mana_pct or 0, 0, 95, '%d%%')
        if minManaVal ~= ctrl.min_mana_pct then
            ctrl.min_mana_pct = minManaVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Prevents automatic spell casting if current mana drops below this percentage.\n'
                .. 'Ignored during Burn Mode (0 = disabled / cast at any mana level).')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        local minPullHpVal = ImGui.SliderInt('Min Pull HP %##minPullHpSettings', ctrl.pull_min_hp_pct or 0, 0, 95, '%d%%')
        if minPullHpVal ~= ctrl.pull_min_hp_pct then
            ctrl.pull_min_hp_pct = minPullHpVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'Pauses pulling and sits out of combat to recover if current HP drops below\n'
                .. 'this threshold. Pulling resumes once HP reaches 100%.\n'
                .. 'Automatically stands to fight if attacked (0 = disabled / pull at any HP).')
        end

        accent(GOLD, 'Med Break Recovery System:')
        local mbVal = ImGui.Checkbox('Enable Med Break', ctrl.medbreak_enabled or false)
        if mbVal ~= (ctrl.medbreak_enabled or false) then
            ctrl.medbreak_enabled = mbVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Stops everything and sits to recover once any enabled\n'
                .. 'resource below drops to its "at" threshold; resumes once ALL enabled\n'
                .. 'resources have recovered up to their "until" threshold.')
        end
        if ctrl.medbreak_enabled then
            local mbHp = ImGui.Checkbox('HP##mbhp', ctrl.medbreak_hp_on or false)
            if mbHp ~= (ctrl.medbreak_hp_on or false) then
                ctrl.medbreak_hp_on = mbHp
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbHpStart = ImGui.SliderInt('##mbhpstart', ctrl.medbreak_hp_start or 20, 0, 100, '%d%%')
            if mbHpStart ~= ctrl.medbreak_hp_start then
                ctrl.medbreak_hp_start = mbHpStart
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbHpStop = ImGui.SliderInt('##mbhpstop', ctrl.medbreak_hp_stop or 90, 0, 100, '%d%%')
            if mbHpStop ~= ctrl.medbreak_hp_stop then
                ctrl.medbreak_hp_stop = mbHpStop
                runtime.saveLoadout(true)
            end

            local mbMana = ImGui.Checkbox('Mana##mbmana', ctrl.medbreak_mana_on or false)
            if mbMana ~= (ctrl.medbreak_mana_on or false) then
                ctrl.medbreak_mana_on = mbMana
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbManaStart = ImGui.SliderInt('##mbmanastart', ctrl.medbreak_mana_start or 20, 0, 100, '%d%%')
            if mbManaStart ~= ctrl.medbreak_mana_start then
                ctrl.medbreak_mana_start = mbManaStart
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbManaStop = ImGui.SliderInt('##mbmanastop', ctrl.medbreak_mana_stop or 90, 0, 100, '%d%%')
            if mbManaStop ~= ctrl.medbreak_mana_stop then
                ctrl.medbreak_mana_stop = mbManaStop
                runtime.saveLoadout(true)
            end

            local mbEnd = ImGui.Checkbox('Endurance##mbend', ctrl.medbreak_end_on or false)
            if mbEnd ~= (ctrl.medbreak_end_on or false) then
                ctrl.medbreak_end_on = mbEnd
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbEndStart = ImGui.SliderInt('##mbendstart', ctrl.medbreak_end_start or 20, 0, 100, '%d%%')
            if mbEndStart ~= ctrl.medbreak_end_start then
                ctrl.medbreak_end_start = mbEndStart
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
            local mbEndStop = ImGui.SliderInt('##mbendstop', ctrl.medbreak_end_stop or 90, 0, 100, '%d%%')
            if mbEndStop ~= ctrl.medbreak_end_stop then
                ctrl.medbreak_end_stop = mbEndStop
                runtime.saveLoadout(true)
            end
        end
    end

    -- 6. Pet Management & Discipline (conditionally shown if trio has pet class or active pet)
    if trioHasPetClass() or hasActivePet() then
        if ImGui.CollapsingHeader('Pet Management & Discipline', ImGuiTreeNodeFlags.DefaultOpen) then
            ImGui.SetNextItemWidth(180)
            local petAssistVal = ImGui.SliderInt('Pet Assist At %##pa', ctrl.pet_assist_at or 100, 1, 100, '%d%%')
            if petAssistVal ~= ctrl.pet_assist_at then
                ctrl.pet_assist_at = petAssistVal
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Send pets to attack once the target drops to or below\n'
                    .. 'this HP threshold AND the player has started hitting the mob.\n'
                    .. '100 percent = send as soon as the first hit connects (default).')
            end
            ImGui.SameLine()
            local petHoldVal = ImGui.Checkbox('Enable Pet Hold', ctrl.pet_hold_enabled ~= false)
            if petHoldVal ~= (ctrl.pet_hold_enabled ~= false) then
                ctrl.pet_hold_enabled = petHoldVal
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Hold pets via "#petcmd hold all" whenever out of combat\n'
                    .. 'or prior to reaching the Pet Assist At HP threshold,\n'
                    .. 'releasing them to attack once threshold is met.')
            end
        end
    end


    -- 7. Interface, Overlays & Diagnostics
    if ImGui.CollapsingHeader('Interface, Overlays & Diagnostics', ImGuiTreeNodeFlags.DefaultOpen) then
        local pauseZoneVal = ImGui.Checkbox('Pause Autocombat When Zoning', ctrl.pause_on_zone ~= false)
        if pauseZoneVal ~= (ctrl.pause_on_zone ~= false) then
            ctrl.pause_on_zone = pauseZoneVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Automatically pause autocombat execution upon entering a new zone.\n'
                .. 'When disabled, autocombat remains active and continues running across zone transitions.')
        end

        local mapAvail = runtime.mapLoaded and runtime.mapLoaded()
        local mapRadVal = ImGui.Checkbox('Show Map Radius Circles', ctrl.show_map_radius or false)
        if mapRadVal ~= (ctrl.show_map_radius or false) then
            ctrl.show_map_radius = mapRadVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Draws green radius circles on the in-game map window\n'
                .. 'for Hunter, Anchor, and Pull/Camp radii.'
                .. (mapAvail and '' or '\n\ayNOTE: MQ2Map plugin is not loaded (/mapfilter and /maploc commands inactive).\ax'))
        end
        if not mapAvail then
            ImGui.SameLine()
            ImGui.TextColored(0.7, 0.7, 0.7, 1.0, '(MQ2Map not loaded)')
        end
        ImGui.SameLine()
        local critVal = ImGui.Checkbox('Critical Hit Floating Text', ctrl.show_crit_floaters or false)
        if critVal ~= (ctrl.show_crit_floaters or false) then
            ctrl.show_crit_floaters = critVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Shows flashy floating damage numbers above your character\n'
                .. 'when you land a critical hit, crippling blow, deadly strike,\n'
                .. 'or other special melee/spell criticals.')
        end

        local compactVal = ImGui.Checkbox('Compact Mini-Window HUD Mode', ctrl.compact or false)
        if compactVal ~= (ctrl.compact or false) then
            ctrl.compact = compactVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Switches the Triune AutoCombat interface into a small, sleek HUD overlay widget.')
        end
        ImGui.SameLine()
        local dbgVal = ImGui.Checkbox('Debug Diagnostic Logging', ctrl.debug_mode or false)
        if dbgVal ~= (ctrl.debug_mode or false) then
            ctrl.debug_mode = dbgVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Prints extra diagnostic lines (e.g. Hunter\'s full targeting\n'
                .. 'state every few seconds) to help track down a stuck/frozen\n'
                .. 'report. Off by default -- noisy for normal use.')
        end

        accent(GOLD, 'Camera & Viewport:')
        local fovAvail = runtime.fovLoaded and runtime.fovLoaded()
        local fovVal = ImGui.Checkbox('Maintain Field of View (/fov)##fovEnabled', ctrl.fov_enabled or false)
        if fovVal ~= (ctrl.fov_enabled or false) then
            ctrl.fov_enabled = fovVal
            if ctrl.fov_enabled and runtime.applyFov then
                runtime.applyFov()
            end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            if fovAvail then
                ImGui.SetTooltip('Enforces your custom camera Field of View and automatically re-applies /fov after zoning.')
            else
                ImGui.SetTooltip('Enforces your custom camera Field of View and automatically re-applies /fov after zoning.\n\ayNOTE: MQ2FOV plugin is not loaded (/fov commands will not execute).\ax')
            end
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(200)
        local curFov = ctrl.fov or 100
        local newFov, fovChanged = ImGui.SliderInt('FOV##fovSlider', curFov, 50, 150, '%d units')
        if fovChanged or (newFov and newFov ~= ctrl.fov) then
            ctrl.fov = newFov
            ctrl.fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            if fovAvail then
                ImGui.SetTooltip('Camera Field of View in units (50-150, default: 100).\nMoving the slider automatically enables FOV persistence across zoning.')
            else
                ImGui.SetTooltip('Camera Field of View in units (50-150, default: 100).\n\ayNOTE: MQ2FOV plugin is not loaded (/fov commands will not execute).\ax')
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Apply##applyFovBtn') then
            ctrl.fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(string.format('Executes /fov %d now and saves the setting.%s', ctrl.fov or 100,
                fovAvail and '' or '\n\ayNOTE: MQ2FOV plugin is not loaded.\ax'))
        end
        if not fovAvail then
            ImGui.SameLine()
            ImGui.TextColored(0.7, 0.7, 0.7, 1.0, '(MQ2FOV not loaded)')
        end
    end

    ImGui.EndTabItem()
    end

    if ImGui.BeginTabItem('Window Settings##settingsWindows') then
        UI.drawWindowSettings()
        ImGui.EndTabItem()
    end

    if ImGui.BeginTabItem('Plugins##settingsPlugins') then
        UI.drawPluginsTab()
        ImGui.EndTabItem()
    end

    ImGui.EndTabBar()
    end

    ImGui.EndTabItem()
end

function UI.drawMiniGui()
    if not open or not ctrl.compact then return end
    UI.pushTheme()
    UI.preBeginWindow('mini')
    local show
    open, show = ImGui.Begin('Triune AutoCombat Mini v' .. VERSION .. '###triuneMini', open,
        ImGuiWindowFlags.AlwaysAutoResize)
    if not open then
        ctrl.compact = false
        ImGui.End()
        UI.popTheme()
        return
    end

    if show then
        UI.postBeginWindow('mini')
        -- Row 1: Header / Status & Mode Selector
        if ctrl.running then
            if runtime.medBreakActive then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'MED BREAK')
            elseif runtime.pullHpRest then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'HP RESTING')
            else
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'RUNNING')
            end
        else
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'PAUSED')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(100)
        local curPrimaryIdx = idxOf(MODES.PRIMARY, ctrl.mode)
        local newPrimaryIdx = ImGui.Combo('##miniPrimaryCombo', curPrimaryIdx, MODES.PRIMARY)
        if newPrimaryIdx ~= curPrimaryIdx then
            local newPrimaryMode = MODES.PRIMARY[newPrimaryIdx]
            if ctrl.mode == 'Manual' and newPrimaryMode ~= 'Manual' then
                setManualHunterPetHold(false)
            elseif newPrimaryMode == 'Manual' then
                if not ctrl.running or not (runtime.isCombat and runtime.isCombat()) then
                    setManualHunterPetHold(true, true)
                end
            end
            ctrl.mode = newPrimaryMode
            if MODES.SUBMODES[ctrl.mode] then
                ctrl.submode = MODES.SUBMODES[ctrl.mode][1]
            else
                ctrl.submode = 'Hunt'
            end
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
            runtime.saveLoadout(true)
        end

        if MODES.SUBMODES[ctrl.mode] then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(90)
            local subList = MODES.SUBMODES[ctrl.mode]
            local curSubIdx = idxOf(subList, ctrl.submode)
            local newSubIdx = ImGui.Combo('##miniSubCombo', curSubIdx, subList)
            if newSubIdx ~= curSubIdx then
                ctrl.submode = subList[newSubIdx]
                if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
                runtime.saveLoadout(true)
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Full Window##miniFull', 95, 22) then
            ctrl.compact = false
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Expand back to full tabbed Triune AutoCombat window')
        end
        ImGui.SameLine()
        if ImGui.Button('CDs##miniCooldowns', 45, 22) then
            ctrl.show_cooldowns = not ctrl.show_cooldowns
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Cooldown & Ability Monitor window')
        end
        ImGui.SameLine()
        local miniUfActive = ctrl.show_unit_frames
        local miniUfPop = 0
        if miniUfActive then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then miniUfPop = miniUfPop + 1 end
        end
        if ImGui.Button('HUD##miniHud', 45, 22) then
            ctrl.show_unit_frames = not ctrl.show_unit_frames
            runtime.saveLoadout(true)
        end
        if miniUfPop > 0 then pcall(ImGui.PopStyleColor, miniUfPop) end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Target & Player HUD window')
        end
        ImGui.SameLine()
        local miniGwActive = ctrl.show_group_window
        local miniGwPop = 0
        if miniGwActive then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then miniGwPop = miniGwPop + 1 end
        end
        if ImGui.Button('Grp##miniGroup', 45, 22) then
            ctrl.show_group_window = not ctrl.show_group_window
            runtime.saveLoadout(true)
        end
        if miniGwPop > 0 then pcall(ImGui.PopStyleColor, miniGwPop) end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Group Window')
        end
        ImGui.SameLine()
        local miniEffActive = ctrl.show_effects_window
        local miniEffPop = 0
        if miniEffActive then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then miniEffPop = miniEffPop + 1 end
        end
        if ImGui.Button('Buffs##miniEffects', 45, 22) then
            ctrl.show_effects_window = not ctrl.show_effects_window
            runtime.saveLoadout(true)
        end
        if miniEffPop > 0 then pcall(ImGui.PopStyleColor, miniEffPop) end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Effects & Songs window')
        end
        ImGui.SameLine()
        local miniXtActive = ctrl.show_xtarget_window
        local miniXtPop = 0
        if miniXtActive then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then miniXtPop = miniXtPop + 1 end
        end
        if ImGui.Button('XT##miniXTarget', 45, 22) then
            ctrl.show_xtarget_window = not ctrl.show_xtarget_window
            runtime.saveLoadout(true)
        end
        if miniXtPop > 0 then pcall(ImGui.PopStyleColor, miniXtPop) end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Extended Target (XTarget) window')
        end
        ImGui.SameLine()
        local miniGemActive = ctrl.show_spell_gems
        local miniGemPop = 0
        if miniGemActive then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then miniGemPop = miniGemPop + 1 end
        end
        if ImGui.Button('Gems##miniGems', 45, 22) then
            ctrl.show_spell_gems = not ctrl.show_spell_gems
            runtime.saveLoadout(true)
        end
        if miniGemPop > 0 then pcall(ImGui.PopStyleColor, miniGemPop) end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Toggle popout Spell Gem Bar window')
        end

        ImGui.Separator()

        if not navLoaded() then
            accent(WARN, '[!] MQ2Nav is NOT loaded')
            if ImGui.IsItemHovered() then
                UI.setTooltip('MQ2Nav plugin is required for pathing and navigation.\nClick Load MQ2Nav or type /plugin mq2nav.')
            end
            ImGui.SameLine()
            if ImGui.Button('Load MQ2Nav##miniLoadNav', 90, 20) then
                mq.cmd('/plugin mq2nav')
            end
        elseif not navMeshLoaded() then
            local curZone = mq.TLO.Zone.ShortName() or 'zone'
            accent(WARN, string.format('[!] No NavMesh for %s', curZone))
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('No navmesh loaded for %s.\nClick Reload or run /nav reload in chat.', curZone))
            end
            ImGui.SameLine()
            if ImGui.Button('Reload##miniReloadMesh', 65, 20) then
                mq.cmd('/nav reload')
            end
        end
        if not stickLoaded() then
            accent(WARN, '[!] MQ2MoveUtils is NOT loaded')
            if ImGui.IsItemHovered() then
                UI.setTooltip('MQ2MoveUtils plugin is required for melee stick and positioning.\nClick Load MoveUtils or type /plugin mq2moveutils.')
            end
            ImGui.SameLine()
            if ImGui.Button('Load MoveUtils##miniLoadMoveUtils', 105, 20) then
                mq.cmd('/plugin mq2moveutils')
            end
        end

        -- Row 2: Action Controls Toolbar (Run/Pause, Burn, Camp)
        if ctrl.running then
            if ImGui.Button('Pause##miniRunBtn', 65, 22) then
                if ctrl.mode == 'Manual' then
                    setManualHunterPetHold(true, true)
                else
                    setManualHunterPetHold(false, true)
                end
                ctrl.running = false
                if runtime.fullStop then runtime.fullStop() end
            end
        else
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            local pCount = 0
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.65, 0.15, 0.15, 1.0) then
                pCount = pCount + 1
            end
            if ImGui.Button('START##miniStartBtn', 80, 22) then
                if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                    runtime.setNearestWaypoint()
                end
                ctrl.running = true
                runtime.wasRunning = true
                if not navLoaded() and ctrl.mode ~= 'Manual' then
                    mq.cmd('/popup [Triune] WARNING: MQ2Nav is NOT loaded!')
                    print('\ar[Triune WARNING]\ax MQ2Nav plugin is not loaded! Movement and navigation require MQ2Nav (/plugin mq2nav).')
                elseif not navMeshLoaded() and ctrl.mode ~= 'Manual' then
                    local curZone = mq.TLO.Zone.ShortName() or 'current zone'
                    mq.cmdf('/popup [Triune] WARNING: No NavMesh for %s!', curZone)
                    print(string.format('\ar[Triune WARNING]\ax No NavMesh loaded for zone "%s"! Movement and pathing require a zone navmesh.', curZone))
                end
                if not stickLoaded() and ctrl.mode ~= 'Manual' then
                    mq.cmd('/popup [Triune] WARNING: MQ2MoveUtils is NOT loaded!')
                    print('\ar[Triune WARNING]\ax MQ2MoveUtils plugin is not loaded! Target stick and melee positioning require MQ2MoveUtils (/plugin mq2moveutils).')
                end
            end
            if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
        end

        ImGui.SameLine()
        if ctrl.burn then
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            local pCount = 0
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.8, 0.2, 0.2, 1.0) then
                pCount = pCount + 1
            end
            if ImGui.Button('BURN ON##miniBurnBtn', 75, 22) then
                ctrl.burn = false
            end
            if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
        else
            if ImGui.Button('Burn##miniBurnBtn', 65, 22) then
                ctrl.burn = true
            end
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Enable/disable Burn Mode (fires Burn Only spells, AAs, and discs)')
        end

        ImGui.Separator()

        -- Live Target / Main Assist Status
        if ctrl.mode == 'Assist' or (ctrl.ma_id and ctrl.ma_id > 0) or (ctrl.ma_name and ctrl.ma_name ~= '') then
            local maInfo = runtime.getMaTargetInfo and runtime.getMaTargetInfo()
            if maInfo and maInfo.hasMA then
                accent(GOLD, 'MA:')
                ImGui.SameLine()
                ImGui.Text(string.format('%s (ID: %d)', maInfo.maName, maInfo.maId))
                ImGui.SameLine(); ImGui.TextDisabled('|')
                ImGui.SameLine()
                if maInfo.hasTarget then
                    accent(ARC, 'Target:')
                    ImGui.SameLine()
                    local conCol = UI.getConColorRgb(maInfo.targetCon)
                    accent(conCol, string.format('%s (%d%%)', maInfo.targetName, maInfo.targetHp))
                    ImGui.SameLine()
                    if ImGui.SmallButton('Target##miniTargMA') then
                        mq.cmdf('/target id %d', maInfo.targetId)
                    end
                    if ImGui.IsItemHovered() then
                        UI.setTooltip(string.format('Target MA Target: %s (ID: %d, %d%% HP, %.1fft)',
                            maInfo.targetName, maInfo.targetId, maInfo.targetHp, maInfo.targetDist))
                    end
                else
                    ImGui.TextDisabled('Target: None')
                end
            else
                accent(MUTED, 'MA: (None Set)')
            end
        else
            local myTId, myTName, myTHp = 0, 'No Target', 0
            pcall(function()
                local t = mq.TLO.Target
                if t and t() and (t.ID() or 0) > 0 then
                    myTId = t.ID() or 0
                    myTName = t.CleanName() or 'Unknown'
                    myTHp = t.PctHPs() or 0
                end
            end)
            if myTId > 0 then
                accent(ARC, 'Target:')
                ImGui.SameLine()
                accent(GOOD, string.format('%s (ID: %d, %d%%)', myTName, myTId, myTHp))
            else
                accent(MUTED, 'Target: None')
            end
        end

        ImGui.Separator()

        -- Row 3: Session Tracker Banner
        UI.updateTracker()
        local elapsedSec = os.time() - (runtime.trackStartTime or os.time())
        local elapsedHrs = math.max(elapsedSec / 3600.0, 0)
        local aaGained = (runtime.startAA and runtime.currentAA) and math.max(0, runtime.currentAA - runtime.startAA) or
            0
        local aaRate = (elapsedHrs > 0.0001) and (aaGained / elapsedHrs) or 0.0
        local platGained = (runtime.startPlat and runtime.currentPlat) and (runtime.currentPlat - runtime.startPlat) or 0
        local platRate = (elapsedHrs > 0.0001) and (platGained / elapsedHrs) or 0.0

        ImGui.TextDisabled(string.format('AA/hr: %.1f | Plat/hr: %.1f', aaRate, platRate))
        if ImGui.IsItemHovered() then
            local m = math.floor(elapsedSec / 60)
            local s = elapsedSec % 60
            local h = math.floor(m / 60)
            m = m % 60
            local timeStr = h > 0 and string.format('%dh %dm %ds', h, m, s) or string.format('%dm %ds', m, s)
            UI.setTooltip(string.format(
                "Session Tracker (%s):\n" ..
                "-------------------------------\n" ..
                "AA/hr Rate:   %.2f / hr\n" ..
                "Total AA:     %+.2f gained (Current: %.2f | Start: %.2f)\n" ..
                "-------------------------------\n" ..
                "Plat/hr Rate: %.1f p/hr\n" ..
                "Total Plat:   %+d p gained (Current: %dp | Start: %dp)\n" ..
                "-------------------------------\n" ..
                "Click 'Reset' to restart session.",
                timeStr, aaRate, aaGained, runtime.currentAA or 0, runtime.startAA or 0,
                platRate, platGained, runtime.currentPlat or 0, runtime.startPlat or 0
            ))
        end
        ImGui.SameLine()
        if ImGui.Button('Reset##miniResetTrack', 55, 20) then
            UI.resetTracker()
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Resets AA and Platinum session tracking values to 0.')
        end

        ImGui.SameLine()
        if ImGui.Button('Map##miniMap', 48, 22) then
            ctrl.show_map = not ctrl.show_map
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Toggles the Map & NPC Tracker window') end

        ImGui.SameLine()
        if ImGui.Button('DPS##miniDPS', 42, 22) then
            ctrl.show_dps = not ctrl.show_dps
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Toggles the DPS Parser window') end

        ImGui.SameLine()
        if ImGui.Button('Cursor##miniCursor', 55, 22) then
            ctrl.show_cursor = not ctrl.show_cursor
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Toggles the Cursor Item Manager window') end
    end

    ImGui.End()
    UI.popTheme()
end

function UI.drawFullGui()
    if not open or ctrl.compact then return end
    UI.pushTheme()
    ImGui.SetNextWindowSize(830, 640, ImGuiCond.FirstUseEver)
    local winFlags = ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0
    local show
    local clsList = {}
    for i = 1, 3 do
        local c = myClasses and myClasses[i]
        if c and c ~= '' and c ~= '-- None --' then
            table.insert(clsList, c)
        end
    end
    local clsText = #clsList > 0 and table.concat(clsList, ' / ') or '?'
    local charName = myName or (mq.TLO.Me.CleanName and mq.TLO.Me.CleanName()) or '(no character)'
    local winTitle = string.format('TAC v%s - %s (%s)###triune', VERSION, charName, clsText)
    UI.preBeginWindow('main')
    open, show = ImGui.Begin(winTitle, open, winFlags)
    if not show then
        ImGui.End(); UI.popTheme(); return
    end
    UI.postBeginWindow('main')

    UI.drawHeaderBar()
    UI.drawActionControls()

    local tabBarFlags = bit.bor(
        (ImGuiTabBarFlags and ImGuiTabBarFlags.Reorderable) or 0,
        (ImGuiTabBarFlags and ImGuiTabBarFlags.FittingPolicyScroll) or 0
    )
    if ImGui.BeginTabBar('triuneTabs_v2', tabBarFlags) then
        UI.drawStatusTab()
        UI.drawControlTab()
        UI.drawPetControlTab()
        UI.drawGemTab()
        UI.drawAbilitiesTab()
        UI.drawAATab()
        UI.drawDiscTab()
        UI.drawClickieTab()
        UI.drawSettingsTab()
        UI.drawHelpTab()
        ImGui.EndTabBar()
    end

    ImGui.End()
    UI.popTheme()
end

function UI.drawPlugins()
    if runtime.pluginManager and runtime.pluginManager.drawUI then
        runtime.pluginManager.drawUI()
    end
end

function UI.draw()
    if not open then return end
    if ctrl.compact then
        UI.drawMiniGui()
    else
        UI.drawFullGui()
    end
end

-- ============================================================================
-- Popout HUD windows migrated to plugins under lua/tac/ (v2.15):
--   Unit Frames (Target/Player/Pet) -> hud_unitframes.lua
--   Group Window                    -> hud_group.lua
--   Effects & Songs Window          -> hud_effects.lua
--   Extended Target Window          -> hud_xtarget.lua
--   Cooldown Monitor (tab + popout) -> hud_cooldowns.lua
--   Spell Gem Bar                   -> hud_spellgems.lua
-- ============================================================================

-- ============================================================================
-- Spell Icon Texture Animation & Caching Helpers
-- ============================================================================
UI.spellIconCache = UI.spellIconCache or {}
UI.spellIconMode = UI.spellIconMode or 'probe'
UI.spellSharedTex = UI.spellSharedTex or nil
UI.spellLastCell = UI.spellLastCell or nil

function UI.probeSpellIconMode()
    if UI.spellIconMode ~= 'probe' then return end
    if mq.TextureAnimation then
        local ok, res = pcall(mq.TextureAnimation, 'triunebuff_probe')
        if ok and res then
            UI.spellIconMode = 'dedicated'
            return
        end
    end
    local ok1, res1 = pcall(mq.FindTextureAnimation, 'A_SpellIcons')
    if ok1 and res1 then
        UI.spellIconMode = 'shared'
        UI.spellSharedTex = res1
        return
    end
    local ok2, res2 = pcall(mq.FindTextureAnimation, 'eq')
    if ok2 and res2 then
        UI.spellIconMode = 'shared'
        UI.spellSharedTex = res2
        return
    end
    UI.spellIconMode = 'none'
end

function UI.getSpellIconAnimation(iconId)
    local id = tonumber(iconId)
    if not id or id <= 0 then return nil end
    UI.probeSpellIconMode()

    if UI.spellIconMode == 'dedicated' then
        local key = tostring(id)
        local ta = UI.spellIconCache[key]
        if not ta then
            local ok, res = pcall(mq.TextureAnimation, 'triunebuff_' .. key)
            if ok and res then
                pcall(function() res:SetTextureCell(id) end)
                UI.spellIconCache[key] = res
                ta = res
            end
        end
        return ta
    elseif UI.spellIconMode == 'shared' and UI.spellSharedTex then
        if UI.spellLastCell ~= id then
            if not pcall(function() UI.spellSharedTex:SetTextureCell(id) end) then
                return nil
            end
            UI.spellLastCell = id
        end
        return UI.spellSharedTex
    end
    return nil
end

function UI.drawSpellIcon(iconId, size)
    local anim = UI.getSpellIconAnimation(iconId)
    if not anim then return false end
    size = size or 18

    if ImGui.DrawTextureAnimation then
        local ok = pcall(function() ImGui.DrawTextureAnimation(anim, size, size) end)
        if ok then return true end
    end

    local dl = ImGui.GetWindowDrawList()
    if dl and dl.AddTextureAnimation then
        local pX, pY = ImGui.GetCursorScreenPos()
        local ok = pcall(function()
            local ImVec2Type = _G.ImVec2 or ImVec2
            dl:AddTextureAnimation(anim, ImVec2Type(pX, pY), ImVec2Type(size, size))
        end)
        if ok then
            ImGui.Dummy(size + 2, size)
            return true
        end
    end
    return false
end

function UI.col32(r, g, b, a)
    local R = math.min(255, math.max(0, math.floor((r or 0) * 255 + 0.5)))
    local G = math.min(255, math.max(0, math.floor((g or 0) * 255 + 0.5)))
    local B = math.min(255, math.max(0, math.floor((b or 0) * 255 + 0.5)))
    local A = math.min(255, math.max(0, math.floor((a or 1) * 255 + 0.5)))
    return (A * 16777216) + (B * 65536) + (G * 256) + R
end

function UI.toVec(x, y)
    local fn = _G.ImVec2 or (ImGui and ImGui.ImVec2) or ImVec2
    if fn then
        local ok, v = pcall(fn, tonumber(x) or 0, tonumber(y) or 0)
        if ok and v then return v end
    end
    return nil
end

-- ============================================================================
-- Vector Spellbook Icon Renderer
-- ============================================================================
function UI.drawSpellbookIcon(dl, mnX, mnY, btnW, btnH)
    if not dl then return end

    local mX = mnX
    local mY = mnY
    if type(mX) == 'userdata' or (type(mX) == 'table' and mX.x) then
        mY = mX.y
        mX = mX.x
    end
    mX = tonumber(mX) or 0
    mY = tonumber(mY) or 0
    btnW = tonumber(btnW) or 24
    btnH = tonumber(btnH) or 24

    local toV = UI.toVec

    local ok = pcall(function()
        local bH = math.max(12, math.floor(btnH * 0.72))
        local bW = math.max(10, math.floor(btnW * 0.70))
        local bX = mX + math.floor((btnW - bW) / 2)
        local bY = mY + math.floor((btnH - bH) / 2)

        local spineW = math.max(3, math.floor(bW * 0.25))
        local coverX = bX + spineW
        local coverW = bW - spineW

        local p1, p2

        -- 1. Dark leather spine with rounded edge
        p1, p2 = toV(bX, bY), toV(bX + spineW, bY + bH)
        if p1 and p2 and dl.AddRectFilled then
            dl:AddRectFilled(p1, p2, UI.col32(0.12, 0.08, 0.22, 1.0), 2)
        end

        -- 2. Spine gold ribs
        local colRib = UI.col32(0.95, 0.82, 0.25, 0.95)
        if dl.AddLine then
            p1, p2 = toV(bX + 1, bY + math.floor(bH * 0.25)), toV(bX + spineW - 1, bY + math.floor(bH * 0.25))
            if p1 and p2 then dl:AddLine(p1, p2, colRib, 1.2) end
            p1, p2 = toV(bX + 1, bY + math.floor(bH * 0.50)), toV(bX + spineW - 1, bY + math.floor(bH * 0.50))
            if p1 and p2 then dl:AddLine(p1, p2, colRib, 1.2) end
            p1, p2 = toV(bX + 1, bY + math.floor(bH * 0.75)), toV(bX + spineW - 1, bY + math.floor(bH * 0.75))
            if p1 and p2 then dl:AddLine(p1, p2, colRib, 1.2) end
        end

        -- 3. Parchment page edges (right & bottom)
        local colPages = UI.col32(0.96, 0.94, 0.82, 1.0)
        if dl.AddRectFilled then
            p1, p2 = toV(bX + bW - 3, bY + 2), toV(bX + bW, bY + bH - 1)
            if p1 and p2 then dl:AddRectFilled(p1, p2, colPages) end
            p1, p2 = toV(coverX + 1, bY + bH - 3), toV(bX + bW, bY + bH)
            if p1 and p2 then dl:AddRectFilled(p1, p2, colPages) end
        end

        -- 4. Deep royal purple arcane leather front cover
        local colCover = UI.col32(0.20, 0.12, 0.36, 1.0)
        p1, p2 = toV(coverX, bY), toV(bX + bW - 2, bY + bH - 2)
        if p1 and p2 and dl.AddRectFilled then
            dl:AddRectFilled(p1, p2, colCover, 1)
        end

        -- 5. Gold embossed border on front cover
        if coverW >= 6 and bH >= 8 then
            local colGold = UI.col32(0.95, 0.82, 0.25, 0.90)
            p1, p2 = toV(coverX + 2, bY + 2), toV(bX + bW - 4, bY + bH - 4)
            if p1 and p2 and dl.AddRect then
                dl:AddRect(p1, p2, colGold, 1)
            end

            -- 6. Arcane star / diamond rune in center of cover
            local cX = coverX + math.floor((coverW - 2) / 2)
            local cY = bY + math.floor(bH / 2)
            local r = math.max(2, math.floor(bH * 0.18))
            if dl.AddQuadFilled then
                local q1, q2, q3, q4 = toV(cX, cY - r), toV(cX + r, cY), toV(cX, cY + r), toV(cX - r, cY)
                if q1 and q2 and q3 and q4 then
                    dl:AddQuadFilled(q1, q2, q3, q4, colGold)
                end
            elseif dl.AddRectFilled then
                p1, p2 = toV(cX - r, cY - r), toV(cX + r, cY + r)
                if p1 and p2 then dl:AddRectFilled(p1, p2, colGold) end
            end
            local centerP = toV(cX, cY)
            if centerP and dl.AddCircleFilled then
                dl:AddCircleFilled(centerP, math.max(1.0, r * 0.45), UI.col32(0.25, 0.95, 1.0, 1.0))
            end

            -- 7. Crimson bookmark ribbon hanging out bottom
            local colRibbon = UI.col32(0.90, 0.20, 0.20, 1.0)
            p1, p2 = toV(cX, bY + bH - 3), toV(cX - 1, bY + bH + 3)
            if p1 and p2 and dl.AddLine then
                dl:AddLine(p1, p2, colRibbon, 1.8)
            end
        end
    end)
    if not ok and dl and dl.AddText then
        pcall(function()
            local pos = toV(mX + math.max(2, (btnW - 14) / 2), mY + math.max(2, (btnH / 2) - 6))
            if pos then dl:AddText(pos, UI.col32(0.4, 0.85, 1.0, 1.0), 'BOOK') end
        end)
    end
end

-- ============================================================================
-- Spell Gem Cooldown Tracker (converts EQ milliseconds to true seconds)
-- ============================================================================
function UI.getGemCooldownSec(slot, spellName, spellRecast)
    local sec = 0
    pcall(function()
        local gt = nil
        if slot and slot > 0 then
            gt = mq.TLO.Me.GemTimer(slot)
        end
        if (not gt or not gt()) and spellName and spellName ~= '' then
            gt = mq.TLO.Me.GemTimer(spellName)
        end
        if gt and gt() then
            -- Guard against unsigned 32-bit -1 sentinel (0xFFFFFFFF = 4294967295)
            local rawVal = nil
            pcall(function()
                if type(gt.Raw) == 'function' then
                    rawVal = tonumber(gt.Raw() or 0)
                elseif type(gt.Raw) == 'number' then
                    rawVal = tonumber(gt.Raw or 0)
                end
            end)
            if rawVal and (rawVal >= 2147483647 or rawVal < 0) then
                sec = 0
                return
            end

            -- 1. Try standard duration parser
            local pSec = parseDurationSec(gt)
            if pSec and pSec > 0 and pSec < 3600 then
                sec = pSec
                return
            end

            -- 2. Try MQ ticks TotalSeconds property (callable or property)
            local ts = nil
            pcall(function()
                if type(gt.TotalSeconds) == 'function' then
                    ts = tonumber(gt.TotalSeconds() or 0) or 0
                elseif type(gt.TotalSeconds) == 'number' then
                    ts = tonumber(gt.TotalSeconds or 0) or 0
                end
            end)
            if ts and ts > 0 and ts < 3600 then
                sec = ts
                return
            end

            -- 3. Try Raw or direct numeric conversion
            local val = rawVal
            if not val or val <= 0 then
                val = tonumber(gt()) or 0
            end
            if val <= 0 or val >= 2147483647 then
                val = 0
            end

            if val > 1000 and val < 3600000 then
                sec = val / 1000.0
            elseif val > 0 and val < 3600 then
                sec = val
            end
        end
    end)

    -- Guard against unsigned underflow (e.g. 4294967s = 1194h) or excessive cooldowns
    if sec >= 3600 or sec < 0 then
        sec = 0
    end
    -- Spell gem cooldown cannot exceed defined recast + buffer
    if spellRecast and type(spellRecast) == 'number' and spellRecast >= 0 then
        local maxAllowed = math.max(3.0, spellRecast + 3.0)
        if sec > maxAllowed then
            sec = 0
        end
    end
    return sec
end

-- ============================================================================
-- COMBAT ENGINE (phase 2, slice 1): act on the loadout -- cast gem rules and fire
-- AAs by target + condition + %. Deferred to a later slice: movement/chase,
-- puller kiting, hunter roaming, and real bard twisting.
-- ============================================================================
-- Combat engine: target and condition helpers
local function baseTok(token)
    local s = tostring(token or '')
    s = s:gsub('^[FE]:%s*', '')
    if s == 'Target' or s == 'Current Target' then return 'Current Target' end
    if s == 'Self' or s == 'Myself' then return 'Myself' end
    return s
end


function runtime.setTarget(id)
    if not id or id == 0 then return false end
    local reqTargetId = getActiveTargetRequiredCastingId()
    if reqTargetId and reqTargetId > 0 and id ~= reqTargetId then
        return false
    end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return false end
    if (s.State() or '') == 'DEAD' then return false end
    if mq.TLO.Target.ID() == id then return true end
    local wasCombat = mq.TLO.Me.Combat()
    mq.cmdf('/target id %d', id)
    local t = 0
    while mq.TLO.Target.ID() ~= id and t < 300 do
        mq.delay(20); t = t + 20
    end
    local success = mq.TLO.Target.ID() == id
    if success and wasCombat and not mq.TLO.Me.Combat() and isHostileTarget(id) then
        mq.cmd('/attack on')
    end
    return success
end

-- true if the target already has the effect. Checks BOTH the buff window and the
-- SONG window (bard song effects live in the song window). Each probe is isolated
-- in its own pcall so an unsupported TLO on this build can't nuke the whole check.
local function tloTrue(fn)
    local hit = false
    pcall(function() if fn() then hit = true end end)
    return hit
end

-- Name-based "Buff(name)" lookups have already proven unreliable on this MQ
-- build twice this session (CombatAbility(name) for discs, Target.Target for
-- assist) -- the proven, reliable pattern instead is numeric indexing +
-- comparing .Name() directly, matching the scanKnownDiscs() fix. This is what
-- was letting Paladin buffs "keep trying to buff even though I have it": a
-- false negative from Buff(name) reads as "missing" and re-fires forever.
local function getBuffRemainingSeconds(spawnObj, name, isMe)
    name = tostring(name or '')
    if name == '' or not spawnObj() then return -1 end
    local rem = -1
    pcall(function()
        local b = spawnObj.Buff(name)
        if b and b() and b.Duration and b.Duration.TotalSeconds then
            rem = tonumber(b.Duration.TotalSeconds()) or -1
        end
    end)
    if rem < 0 and isMe then
        pcall(function()
            local s = spawnObj.Song(name)
            if s and s() and s.Duration and s.Duration.TotalSeconds then
                rem = tonumber(s.Duration.TotalSeconds()) or -1
            end
        end)
    end
    return rem
end

local function hasNamedBuff(spawnObj, name, isMe, minSec)
    name = tostring(name or '')
    if name == '' or not spawnObj() then return false end
    minSec = tonumber(minSec) or 0

    if minSec > 0 then
        local rem = getBuffRemainingSeconds(spawnObj, name, isMe)
        if rem >= 0 then
            return rem > minSec
        end
    end

    local found = false
    pcall(function()
        local b = spawnObj.Buff(name)()
        if b then found = true end
    end)
    if not found and isMe then
        pcall(function()
            local s = spawnObj.Song(name)()
            if s then found = true end
        end)
    end
    if found then return true end

    -- Fallback: enumeration. Still works fine on OTHER spawns (group members,
    -- pets, mobs); only broken for self.
    local cnt = 0
    pcall(function() cnt = spawnObj.BuffCount() or 0 end)
    for i = 1, cnt do
        local b = spawnObj.Buff(i)
        if b() then
            local bn = b.Name() or ''
            if bn == name then found = true end
        end
    end
    if ctrl.debug_mode and not found and (os.clock() - runtime.lastBuffDiagAt) > 5.0 then
        runtime.lastBuffDiagAt = os.clock()
        local directName = 'nil'
        pcall(function()
            local b = spawnObj.Buff(name)(); if b then directName = tostring(b) end
        end)
        local activeNames = {}
        for i = 1, cnt do
            local b = spawnObj.Buff(i)
            if b() then activeNames[#activeNames + 1] = b.Name() or '?' end
        end
        print('\ao[Triune debug]\ax looking for buff "' ..
            tostring(name) .. '" -- ' .. (isMe and 'MyBuffCount' or 'BuffCount') .. '=' .. cnt
            ..
            ' active=[' ..
            table.concat(activeNames, ', ') ..
            '] Buff("name")=' .. directName)
    end
    return found
end

function runtime.recordPetBuff(petId, spellName, durSec)
    if not petId or petId <= 0 or not spellName or spellName == '' then return end
    petState.cachedPetBuffs = petState.cachedPetBuffs or {}
    local cData = petState.cachedPetBuffs[petId] or { time = os.clock(), buffs = {}, buffDetails = {} }
    cData.time = os.clock()
    cData.buffs = cData.buffs or {}
    cData.buffDetails = cData.buffDetails or {}
    local alreadyIn = false
    for _, bn in ipairs(cData.buffs) do
        if bn == spellName then alreadyIn = true break end
    end
    if not alreadyIn then
        table.insert(cData.buffs, spellName)
    end
    table.insert(cData.buffDetails, { name = spellName, duration = durSec or 0 })
    petState.cachedPetBuffs[petId] = cData
end

function runtime.isPetBuffActive(petId, name, minSec)
    if not petId or petId == 0 then return false end
    name = tostring(name or '')
    if name == '' then return false end
    minSec = tonumber(minSec) or 0

    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)

    local function isBuffNameMatch(candidateName)
        if not candidateName or candidateName == '' or candidateName == 'NONE' then return false end
        if candidateName == name then return true end
        if candidateName:lower() == name:lower() then return true end
        if isGemMatching and isGemMatching(candidateName, name) then return true end
        if cleanSpellName and cleanSpellName(candidateName):lower() == cleanSpellName(name):lower() then return true end
        return false
    end

    -- 1. Primary pet inspection via mq.TLO.Me.Pet
    if myPetId > 0 and petId == myPetId then
        local found = false
        local remSec = -1
        local activeBuffNames = {}
        local activeBuffDetails = {}

        for b = 1, 30 do
            pcall(function()
                local pb = mq.TLO.Me.Pet.Buff(b)
                if pb then
                    local bName = nil
                    if type(pb) == 'string' and pb ~= '' then
                        bName = pb
                    elseif pb() and type(pb()) == 'string' and pb() ~= '' then
                        bName = pb()
                    elseif pb.Name and pb.Name() and pb.Name() ~= '' then
                        bName = pb.Name()
                    end
                    if bName and bName ~= '' and bName ~= 'NONE' then
                        local durSec = -1
                        pcall(function()
                            local dur = mq.TLO.Me.Pet.BuffDuration(b) or 0
                            if type(dur) == 'number' and dur > 0 then
                                durSec = math.floor(dur / 1000)
                            end
                        end)
                        table.insert(activeBuffNames, bName)
                        table.insert(activeBuffDetails, { slot = b, name = bName, duration = durSec })

                        if not found and isBuffNameMatch(bName) then
                            found = true
                            remSec = durSec
                        end
                    end
                end
            end)
        end

        -- Update petState.cachedPetBuffs
        if petState and petState.cachedPetBuffs and #activeBuffNames > 0 then
            petState.cachedPetBuffs[petId] = {
                time = os.clock(),
                buffs = activeBuffNames,
                buffDetails = activeBuffDetails
            }
        end

        if found then
            if minSec > 0 and remSec >= 0 then
                return remSec > minSec
            end
            return true
        end

        -- Fallback direct lookup by name
        pcall(function()
            local bSlot = mq.TLO.Me.Pet.Buff(name)()
            if bSlot then
                local sNum = tonumber(bSlot) or 0
                if sNum > 0 or (tostring(bSlot) ~= '' and tostring(bSlot) ~= 'NONE') then
                    found = true
                    local dur = mq.TLO.Me.Pet.BuffDuration(name)()
                    if dur and tonumber(dur) and tonumber(dur) > 0 then
                        remSec = math.floor(tonumber(dur) / 1000)
                    end
                end
            end
        end)

        if found then
            if minSec > 0 and remSec >= 0 then
                return remSec > minSec
            end
            return true
        end

        -- Stacking check: if beneficial spell will not stack on pet, pet already has
        -- this buff effect or a superior non-overwritable buff
        local stacksPet = true
        pcall(function()
            local sp = mq.TLO.Spell(name)
            if sp and sp() and sp.Beneficial() and sp.StacksPet then
                stacksPet = sp.StacksPet()
            end
        end)
        if stacksPet == false then
            return true
        end

        return false
    end

    -- 2. Target buffs if this pet is currently targeted
    local curTargId = 0
    pcall(function() curTargId = mq.TLO.Target.ID() or 0 end)
    if curTargId == petId then
        local tbc = 0
        pcall(function() tbc = mq.TLO.Target.BuffCount() or 0 end)
        if tbc and tbc > 0 then
            for b = 1, math.min(tbc, 30) do
                local foundTarg = false
                local remSec = -1
                pcall(function()
                    local tb = mq.TLO.Target.Buff(b)
                    if tb and tb() then
                        local bName = (tb.Name and tb.Name()) or tb()
                        if isBuffNameMatch(bName) then
                            foundTarg = true
                            if tb.Duration and tb.Duration.TotalSeconds then
                                remSec = tonumber(tb.Duration.TotalSeconds()) or -1
                            end
                        end
                    end
                end)
                if foundTarg then
                    if minSec > 0 and remSec >= 0 then
                        return remSec > minSec
                    end
                    return true
                end
            end
        end

        local stacksTarg = true
        pcall(function()
            local sp = mq.TLO.Spell(name)
            if sp and sp() and sp.Beneficial() and sp.StacksTarget then
                stacksTarg = sp.StacksTarget()
            end
        end)
        if stacksTarg == false then
            return true
        end
    end

    -- 3. Spawn object cached buffs and StacksSpawn
    local s = mq.TLO.Spawn(petId)
    if s and s() then
        local sbc = 0
        pcall(function()
            sbc = (s.CachedBuffCount and s.CachedBuffCount()) or (s.BuffCount and s.BuffCount()) or 0
        end)
        if sbc and sbc > 0 then
            for b = 1, math.min(sbc, 30) do
                local foundSpawn = false
                local remSec = -1
                pcall(function()
                    local sb = s.Buff(b)
                    if sb and sb() then
                        local bName = (sb.Name and sb.Name()) or (sb.Spell and sb.Spell.Name and sb.Spell.Name()) or sb()
                        if isBuffNameMatch(bName) then
                            foundSpawn = true
                            if sb.Duration and sb.Duration.TotalSeconds then
                                remSec = tonumber(sb.Duration.TotalSeconds()) or -1
                            end
                        end
                    end
                end)
                if foundSpawn then
                    if minSec > 0 and remSec >= 0 then
                        return remSec > minSec
                    end
                    return true
                end
            end
        end

        local stacksSpawn = true
        pcall(function()
            local sp = mq.TLO.Spell(name)
            if sp and sp() and sp.Beneficial() and sp.StacksSpawn then
                stacksSpawn = sp.StacksSpawn(petId)
            end
        end)
        if stacksSpawn == false then
            return true
        end
    end

    -- 4. Check petState.cachedPetBuffs
    if petState and petState.cachedPetBuffs and petState.cachedPetBuffs[petId] then
        local cData = petState.cachedPetBuffs[petId]
        local elapsed = os.clock() - (cData.time or 0)
        if elapsed < 300 then
            if cData.buffDetails then
                for _, d in ipairs(cData.buffDetails) do
                    if isBuffNameMatch(d.name) then
                        local remSec = (d.duration or 0) - elapsed
                        if minSec > 0 and (d.duration or 0) > 0 then
                            return remSec > minSec
                        end
                        return true
                    end
                end
            end
            if cData.buffs then
                for _, bName in ipairs(cData.buffs) do
                    if isBuffNameMatch(bName) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function buffActive(id, name, minSec)
    if not id or id == 0 then return false end
    minSec = tonumber(minSec) or 0
    if id == mq.TLO.Me.ID() then
        if hasNamedBuff(mq.TLO.Me, name, true, minSec) then return true end
        if minSec == 0 and tloTrue(function() return mq.TLO.Me.Song(name)() end) then return true end
        return false
    end
    -- Pet buff detection: primary pet, player-owned pet, or any pet spawn
    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if (myPetId > 0 and id == myPetId) or isSpawnMyPet(id) or isAnyPet(id) then
        return runtime.isPetBuffActive(id, name, minSec)
    end
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == id then
            if hasNamedBuff(m, name, false, minSec) then return true end
            if minSec == 0 and tloTrue(function() return m.Song(name)() end) then return true end ---@diagnostic disable-line: undefined-field
            return false
        end
    end
    for _, petId in pairs(petState.myPets) do
        if petId == id then
            return runtime.isPetBuffActive(id, name, minSec)
        end
    end
    if mq.TLO.Target.ID() == id then
        return hasNamedBuff(mq.TLO.Target, name, false, minSec)
    end
    local s = mq.TLO.Spawn(id)
    if s and s() then
        return hasNamedBuff(s, name, false, minSec)
    end
    return false
end
runtime.buffActive = buffActive

function runtime.isNpcSpellActive(id, spellName)
    if not id or id <= 0 or not spellName or spellName == '' then return false end
    if buffActive(id, spellName) then return true end
    if runtime.npcSpellApplied and runtime.npcSpellApplied[id] then
        local now = os.clock()
        for sName, expireAt in pairs(runtime.npcSpellApplied[id]) do
            if expireAt and now < expireAt then
                if sName == spellName or (cleanSpellName and cleanSpellName(sName):lower() == cleanSpellName(spellName):lower()) then
                    return true
                end
            else
                runtime.npcSpellApplied[id][sName] = nil
            end
        end
    end
    return false
end

local function hasSpellReagents(spellName)
    if not spellName or spellName == '' then return true end
    local has = true
    pcall(function()
        local sp = mq.TLO.Spell(spellName)
        if sp and sp() then
            for r = 1, 4 do
                local rid = tonumber(sp.ReagentID(r)()) or 0
                local rcnt = tonumber(sp.ReagentCount(r)()) or 0
                if rid > 0 and rcnt > 0 then
                    local count = tonumber(mq.TLO.FindItemCount(rid)()) or 0
                    if count < rcnt then
                        has = false
                        break
                    end
                end
            end
        end
    end)
    return has
end

function runtime.lowestHpAlly(maxDist)
    maxDist = maxDist or 200
    local bestId, bestHp = mq.TLO.Me.ID(), (mq.TLO.Me.PctHPs() or 100)
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and not m.Dead() then
            local isPresent = true
            pcall(function()
                if m.Present ~= nil and not m.Present() then isPresent = false end
                if m.OtherZone ~= nil and m.OtherZone() then isPresent = false end
                if m.Offline ~= nil and m.Offline() then isPresent = false end
            end)
            if isPresent then
                local mid = m.ID() or 0
                if mid > 0 and isSpawnAlive(mid) then
                    local dist = distToId(mid)
                    if dist >= 0 and dist <= maxDist then
                        local hp = m.PctHPs() or 100
                        if hp < bestHp then
                            bestHp = hp; bestId = mid
                        end
                    end
                end
            end
        end
    end
    return bestId
end

local function firstNPCXtarget(unmezzedOnly, maxZ, maxDist)
    return findFirstNPCXtarget(unmezzedOnly, isIgnored, isUnreachable, maxDist, maxZ, buffActive)
end

-- Returns count of live, non-ignored NPCs occupying XTarget slots.
function runtime.countNPCXtarget(includeUnreachable)
    local cnt = 0
    pcall(function()
        local slots = mq.TLO.Me.XTargetSlots() or 13
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isHostileTarget(id)
                    and not isIgnored(xt.CleanName())
                    and (includeUnreachable or not isUnreachable(id)) then
                    cnt = cnt + 1
                end
            end
        end
    end)
    -- Fallback: if XTarget list is unpopulated or empty, but we have a valid live NPC target, count as at least 1
    if cnt == 0 and not includeUnreachable then
        pcall(function()
            local t = mq.TLO.Target
            local tid = (t() and t.ID()) or 0
            if tid > 0 and isHostileTarget(tid) and not isIgnored(t.CleanName()) and not isUnreachable(tid) then
                cnt = 1
            end
        end)
    end
    return cnt
end

-- Returns true if any live, non-ignored NPC occupies an XTarget slot.
-- When includeUnreachable is true, includes unreachable NPCs (used for combat / med break safety checks).
function runtime.anyXtarAlive(includeUnreachable)
    return runtime.countNPCXtarget(includeUnreachable) > 0
end

-- Returns true if an action (spell, AA, disc, skill) is detrimental (offensive).
function runtime.isDetrimentalAction(name, targetToken, entry)
    local k = entry and entry.kind
    return isDetrimentalSpell(name, nil, k, targetToken)
end

-- Returns true if an action (spell, AA, disc, skill, clickie) is a healing action.
function runtime.isHealAction(name, targetToken, entry)
    if not name or name == '' then return false end
    if runtime.isDetrimentalAction(name, targetToken, entry) then return false end
    if entry and entry.kind == 'heal' then return true end
    local k = entry and entry.kind
    if k and (k == 'dd' or k == 'dot' or k == 'debuff' or k == 'nuke' or k == 'buff' or k == 'pet' or k == 'util') then
        return false
    end
    if entry and entry.when == 'missing buff' then
        return false
    end
    -- Target check: Lowest-HP Ally is almost certainly a heal if not offensive
    if targetToken and baseTok(targetToken) == 'Lowest-HP Ally' then
        if not runtime.isDetrimentalAction(name, targetToken, entry) then
            return true
        end
    end
    -- Condition check: HP threshold conditions on friendly actions
    if entry and entry.when and (entry.when == 'my HP <=' or entry.when == 'HP <=' or entry.when == 'target HP <=') then
        if not runtime.isDetrimentalAction(name, targetToken, entry) then
            local lowerName = tostring(name):lower()
            if not isFeignDeathAbility(name) then
                if lowerName:find('heal') or lowerName:find('mend') or lowerName:find('salve')
                    or lowerName:find('remedy') or lowerName:find('chloroplast') or lowerName:find('regeneration')
                    or lowerName:find('renewal') or lowerName:find('restoration') or lowerName:find('lay on hands')
                    or lowerName:find('burst of life') or lowerName:find('arbitration') or lowerName:find('touch')
                    or (targetToken and baseTok(targetToken) == 'Lowest-HP Ally') then
                    return true
                end
            end
        end
    end
    -- TLO Spell Category check
    local isHealCat = false
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then
            local cat = tostring(sp.Category() or ''):lower()
            local subcat = tostring(sp.Subcategory() or ''):lower()
            if cat:find('heal') or subcat:find('heal') or cat:find('restore') or subcat:find('restore') then
                isHealCat = true
            end
        end
    end)
    if isHealCat then return true end

    -- Check database (DATA.spells) if loaded
    if DATA and DATA.spells then
        for _, list in pairs(DATA.spells) do
            if type(list) == 'table' then
                for _, it in ipairs(list) do
                    if it[1] == name then
                        if it[4] == 'heal' then return true end
                        if it[4] == 'dd' or it[4] == 'dot' or it[4] == 'debuff' or it[4] == 'buff' then return false end
                    end
                end
            end
        end
    end

    -- Fallback name heuristic for recognized heals
    local lowerName = tostring(name):lower()
    if not runtime.isDetrimentalAction(name, targetToken, entry) and not isFeignDeathAbility(name) then
        if lowerName:find('heal') or lowerName:find('mend') or lowerName:find('salve')
            or lowerName:find('remedy') or lowerName:find('chloroplast') or lowerName:find('renewal')
            or lowerName:find('restoration') or lowerName:find('lay on hands') or lowerName:find('burst of life')
            or lowerName:find('divine arbitration') then
            return true
        end
    end
    return false
end

function runtime.isTargetInRange(name, targetId)
    if not targetId or targetId == 0 then return false end
    local myId = mq.TLO.Me.ID() or 0
    if targetId == myId then return true end

    local dist = distToId(targetId)
    if dist < 0 then return false end

    local maxRange = 0
    if name and name ~= '' then
        pcall(function()
            local sp = mq.TLO.Spell(name)
            if sp() then
                local r = sp.Range() or 0
                if r > 0 then maxRange = r end
            end
        end)
    end
    if maxRange == 0 then
        local isBene = not runtime.isDetrimentalAction(name, nil, nil)
        if isBene then
            maxRange = 100
        else
            maxRange = (runtime.maxMeleeDistance and runtime.maxMeleeDistance(targetId)) or 15
        end
    end

    return dist <= (maxRange + 2)
end

function runtime.maPcId()
    if not ctrl then return nil end
    -- 1. If ctrl.ma_id is set and > 0, verify it is a valid, living PC
    if ctrl.ma_id and ctrl.ma_id > 0 then
        local valid = false
        pcall(function()
            local s = mq.TLO.Spawn(ctrl.ma_id)
            if s and s() and isSpawnAlive(ctrl.ma_id) and s.Type() == 'PC' then
                if not ctrl.ma_name or ctrl.ma_name == '' or s.CleanName() == ctrl.ma_name then
                    valid = true
                end
            end
        end)
        if valid then return ctrl.ma_id end
    end
    -- 2. Fallback: if character re-zoned and Spawn ID changed, re-locate by name and re-sync ma_id
    if ctrl.ma_name and ctrl.ma_name ~= '' then
        local id = findMaPcId(ctrl.ma_name)
        if id and id > 0 then
            ctrl.ma_id = id
            return id
        end
    end
    return nil
end

function runtime.targetIsEngaged(id)
    if not id or id <= 0 then return false end
    if isSpawnPetOrPlayer(id) or not isHostileTarget(id) then return false end
    if isXTargetId(id) then return true end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return false end
    if (s.PctHPs() or 100) < 100 then return true end

    -- Check if target of target or aggro holder is player or group member
    local totId = 0
    pcall(function() totId = s.TargetOfTarget.ID() or 0 end)
    if totId > 0 and (isGroupOrRaidMember(totId) or totId == (mq.TLO.Me.ID() or 0)) then
        return true
    end
    local aggroId = 0
    pcall(function() aggroId = s.AggroHolder.ID() or 0 end)
    if aggroId > 0 and (isGroupOrRaidMember(aggroId) or aggroId == (mq.TLO.Me.ID() or 0)) then
        return true
    end

    -- In Assist mode, target is engaged if the Main Assist is actively targeting it and in combat
    if ctrl and ctrl.mode == 'Assist' then
        local maId = runtime.maPcId()
        if maId and maId > 0 then
            local maInCombat = false
            local maTargId = 0
            pcall(function()
                local sp = mq.TLO.Spawn(maId)
                if sp() then
                    maInCombat = sp.Combat() or false
                    maTargId = sp.Target.ID() or 0
                end
            end)
            if maTargId == id and maInCombat then
                return true
            end
        end
    end

    return false
end

local function isCombat()
    local ok, res = pcall(function()
        if mq.TLO.Me.Combat() then return true end
        if mq.TLO.Me.AutoFire() then return true end
        if mq.TLO.Me.CombatState() == 'COMBAT' then return true end
        local hCount = mq.TLO.Me.XTHaterCount() or 0
        if hCount > 0 then return true end
        local aCount = mq.TLO.Me.XTAggroCount() or 0
        if aCount > 0 then return true end
        local t = mq.TLO.Target
        if t() and (t.ID() or 0) > 0 and not isGroupOrRaidMember(t.ID()) and not isSpawnPetOrPlayer(t.ID()) then
            local stype = t.Type() or ''
            if (stype == 'NPC' or stype == 'Pet') and not t.Dead() and stype ~= 'Corpse' and not isIgnored(t.CleanName()) then
                if runtime.targetIsEngaged(t.ID()) or isHostileTarget(t.ID()) then return true end
            end
        end
        local slots = mq.TLO.Me.XTargetSlots() or 13
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) and not isGroupOrRaidMember(id) and not isSpawnPetOrPlayer(id) then
                    local s = mq.TLO.Spawn(id)
                    if s() then
                        local stype = s.Type() or ''
                        if (stype == 'NPC' or stype == 'Pet') and not s.Dead() and stype ~= 'Corpse' and not isIgnored(s.CleanName()) and isHostileTarget(id) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end)
    return ok and res or false
end

function runtime.anyNearbyEngagedNpc(radius)
    radius = radius or (ctrl and ctrl.xtar_nav_dist) or 150
    if firstNPCXtarget(false, nil, radius) then return true end
    local filt = string.format('npc radius %d', radius)
    local n = mq.TLO.SpawnCount(filt)() or 0
    for i = 1, n do
        local s = mq.TLO.NearestSpawn(i, filt)
        if s() and s.ID() > 0 and not isSpawnPetOrPlayer(s.ID()) and isHostileTarget(s.ID()) then
            if runtime.targetIsEngaged(s.ID()) then return true end
        end
    end
    return false
end

function runtime.maTargetId()
    local maId = runtime.maPcId()
    if not maId then return nil end
    local gated = (ctrl.mode == 'Assist')
    local maxNav = (ctrl and ctrl.xtar_nav_dist) or 150
    if gated and not runtime.anyNearbyEngagedNpc(maxNav) then
        return nil -- nothing nearby is actually being fought -- don't even peek via /assist
    end
    local now = os.clock()
    if (now - runtime.lastAssistCmdAt) >= 1.0 then
        runtime.lastAssistCmdAt = now
        local nm = mq.TLO.Spawn(maId).CleanName()
        if nm and nm ~= '' then
            mq.cmdf('/assist %s', nm)
            mq.delay(150)
        end
    end
    local t = mq.TLO.Target
    if not (t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse' and not isSpawnPetOrPlayer(t.ID()) and isHostileTarget(t.ID())) then return nil end
    if gated and not runtime.targetIsEngaged(t.ID()) then
        return nil
    end
    if gated and distToId(t.ID()) > maxNav then
        return nil
    end
    return t.ID()
end

-- Finds a hostile NPC actively attacking the character (self-defense).
-- Used in Assist mode when the Main Assist has no active engaged target.
function runtime.findSelfDefenseTarget(maxDist)
    maxDist = maxDist or (ctrl and ctrl.xtar_nav_dist) or 150
    local myId = mq.TLO.Me.ID() or 0
    if myId <= 0 then return nil end
    local bestId = nil
    local bestDist = maxDist + 1

    -- 1. Scan XTarget slots for any hostile mob attacking or targeting Me
    local slots = 13
    pcall(function() slots = mq.TLO.Me.XTargetSlots() or 13 end)
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and not isUnreachable(xt.ID())
            and not isGroupOrRaidMember(xt.ID()) and not isSpawnPetOrPlayer(xt.ID())
            and isHostileTarget(xt.ID()) and not isIgnored(xt.CleanName()) then
            local xId = xt.ID()
            local d = distToId(xId)
            if d >= 0 and d <= maxDist then
                local isHittingMe = false
                pcall(function()
                    if xt.TargetOfTarget.ID() == myId or xt.AggroHolder.ID() == myId or (xt.PctAggro() or 0) >= 100 then
                        isHittingMe = true
                    end
                end)
                if isHittingMe and d < bestDist then
                    bestDist = d
                    bestId = xId
                end
            end
        end
    end
    if bestId then return bestId end

    -- 2. Scan XTarget for any Auto Hater or mob in close combat range if character is in combat
    local inCombat = mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT') or ((mq.TLO.Me.XTHaterCount() or 0) > 0)
    if inCombat then
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() and (xt.ID() or 0) > 0 and not isUnreachable(xt.ID())
                and not isGroupOrRaidMember(xt.ID()) and not isSpawnPetOrPlayer(xt.ID())
                and isHostileTarget(xt.ID()) and not isIgnored(xt.CleanName()) then
                local xId = xt.ID()
                local d = distToId(xId)
                if d >= 0 and d <= maxDist then
                    local isHater = false
                    pcall(function()
                        local tt = xt.TargetType() or ''
                        if tt == 'Auto Hater' or (xt.PctAggro() or 0) > 0 then
                            isHater = true
                        end
                    end)
                    if isHater and d < bestDist then
                        bestDist = d
                        bestId = xId
                    end
                end
            end
        end
    end
    if bestId then return bestId end

    -- 3. Check current target if it is hostile, alive, within maxDist, and hitting Me
    local t = mq.TLO.Target
    if t() and (t.ID() or 0) > 0 and not isUnreachable(t.ID())
        and not isGroupOrRaidMember(t.ID()) and not isSpawnPetOrPlayer(t.ID())
        and isHostileTarget(t.ID()) and not isIgnored(t.CleanName()) then
        local tId = t.ID()
        local d = distToId(tId)
        if d >= 0 and d <= maxDist then
            local isHittingMe = false
            pcall(function()
                if t.TargetOfTarget.ID() == myId or t.AggroHolder.ID() == myId or (t.PctAggro() or 0) >= 100 then
                    isHittingMe = true
                end
            end)
            if isHittingMe then return tId end
        end
    end

    -- 4. Check nearby NPCs within melee range if in combat
    if inCombat then
        local filt = string.format('npc radius %d', math.min(35, math.floor(maxDist)))
        local n = mq.TLO.SpawnCount(filt)() or 0
        for i = 1, n do
            local s = mq.TLO.NearestSpawn(i, filt)
            if s() and s.ID() > 0 and not isUnreachable(s.ID())
                and not isSpawnPetOrPlayer(s.ID()) and isHostileTarget(s.ID())
                and not isIgnored(s.CleanName()) then
                local sId = s.ID()
                local isHittingMe = false
                pcall(function()
                    if s.TargetOfTarget.ID() == myId or s.AggroHolder.ID() == myId or (s.PctAggro() or 0) >= 100 then
                        isHittingMe = true
                    end
                end)
                if isHittingMe then return sId end
            end
        end
    end

    return nil
end

-- Shared poison/disease probe. `kind` is 'Poison' or 'Disease'; the two
-- afflictions are exposed through identically shaped TLO members
-- (Me.Poisoned / Me.Diseased, CountersPoison / CountersDisease, ...), so one
-- walker covers both and the public helpers below just pick the kind.
local AFFLICTION_MEMBERS = {
    Poison  = { flag = 'Poisoned', counter = 'CountersPoison' },
    Disease = { flag = 'Diseased', counter = 'CountersDisease' },
}

local function hasAffliction(targetId, kind)
    if not targetId or targetId <= 0 then return false end
    local members = AFFLICTION_MEMBERS[kind]
    if not members then return false end
    local flag, counter = members.flag, members.counter

    -- 1. Check local player (Me)
    local myId = 0
    pcall(function() myId = mq.TLO.Me.ID() or 0 end)
    if targetId == myId then
        -- 1a. Numeric counter count (CountersPoison / CountersDisease)
        local cnt = 0
        pcall(function()
            local co = mq.TLO.Me[counter]
            if co then cnt = tonumber(co()) or 0 end
        end)
        if cnt > 0 then return true end

        -- 1b. Direct buff property on Me (Me.Poisoned / Me.Diseased)
        local afflicted = false
        pcall(function()
            local p = mq.TLO.Me[flag]
            if p and p() then
                local str = tostring(p())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    afflicted = true
                end
            end
        end)
        if afflicted then return true end

        -- 1c. Debuffs plugin if loaded
        local debuffCnt = 0
        pcall(function()
            if mq.TLO.Debuffs then
                debuffCnt = tonumber(mq.TLO.Debuffs[flag]()) or 0
            end
        end)
        return debuffCnt > 0
    end

    -- 2. Check other spawns (group members, box characters, target)
    local s = nil
    pcall(function() s = mq.TLO.Spawn(targetId) end)
    if not s or not s() then return false end

    local cleanName = ''
    pcall(function() cleanName = s.CleanName() or '' end)

    -- 2a. NetBots check (trio / box group members sharing debuff counters)
    if cleanName ~= '' then
        local nbCnt = 0
        pcall(function()
            local nb = mq.TLO.NetBots(cleanName)
            if nb and nb() then
                nbCnt = tonumber(nb[flag]()) or 0
                if nbCnt == 0 then
                    local det = tostring(nb.Detrimental() or '')
                    if det:find(kind) then nbCnt = 1 end
                end
            end
        end)
        if nbCnt > 0 then return true end
    end

    -- 2b. Current Target check
    local isTarget = false
    pcall(function() isTarget = ((mq.TLO.Target.ID() or 0) == targetId) end)
    if isTarget then
        local tgtAfflicted = false
        pcall(function()
            local p = mq.TLO.Target[flag]
            if p and p() then
                local str = tostring(p())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    tgtAfflicted = true
                end
            end
        end)
        if tgtAfflicted then return true end
    end

    -- 2c. Group Member check
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == targetId then
            local memAfflicted = false
            pcall(function()
                if m[flag] and m[flag]() then memAfflicted = true end
                if m[counter] and (tonumber(m[counter]()) or 0) > 0 then memAfflicted = true end
            end)
            if memAfflicted then return true end
        end
    end

    return false
end

local function isPoisoned(targetId) return hasAffliction(targetId, 'Poison') end
local function isDiseased(targetId) return hasAffliction(targetId, 'Disease') end

-- Legacy combined check; kept so profiles saved with the old
-- 'has Poison/Disease' trigger keep working.
local function isPoisonedOrDiseased(targetId)
    return isPoisoned(targetId) or isDiseased(targetId)
end

local function isCursed(targetId)
    if not targetId or targetId <= 0 then return false end
    if targetId == mq.TLO.Me.ID() then
        local meC = false
        pcall(function()
            if mq.TLO.Me.Cursed and mq.TLO.Me.Cursed() then meC = true end
            if mq.TLO.Me.CountersCurse and (tonumber(mq.TLO.Me.CountersCurse()) or 0) > 0 then meC = true end
        end)
        if meC then return true end
        local debuffC = 0
        pcall(function()
            for i = 1, (mq.TLO.Me.CountBuffs() or 0) do
                local b = mq.TLO.Me.Buff(i)
                if b and b() and (b.CounterNumber() or 0) > 0 and b.CounterType() == 'Curse' then
                    debuffC = debuffC + 1
                end
            end
        end)
        return debuffC > 0
    end

    local s = nil
    pcall(function() s = mq.TLO.Spawn(targetId) end)
    if not s or not s() then return false end
    local cleanName = ''
    pcall(function() cleanName = s.CleanName() or '' end)
    if cleanName ~= '' then
        local nbC = 0
        pcall(function()
            local nb = mq.TLO.NetBots(cleanName)
            if nb and nb() then
                nbC = tonumber(nb.Cursed()) or 0
                if nbC == 0 and nb.CountersCurse then
                    nbC = tonumber(nb.CountersCurse()) or 0
                end
                if nbC == 0 then
                    local det = tostring(nb.Detrimental() or '')
                    if det:find('Curse') then nbC = 1 end
                end
            end
        end)
        if nbC > 0 then return true end
    end

    if (mq.TLO.Target.ID() or 0) == targetId then
        local tc = false
        pcall(function()
            local c = mq.TLO.Target.Cursed
            if c and c() then
                local str = tostring(c())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then tc = true end
            end
        end)
        if tc then return true end
    end

    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == targetId then
            local mc = false
            pcall(function()
                if m.Cursed and m.Cursed() then mc = true end
                if m.CountersCurse and (tonumber(m.CountersCurse()) or 0) > 0 then mc = true end
            end)
            if mc then return true end
        end
    end
    return false
end

local function isCorrupted(targetId)
    if not targetId or targetId <= 0 then return false end
    if targetId == mq.TLO.Me.ID() then
        local meCorr = false
        pcall(function()
            if mq.TLO.Me.Corrupted and mq.TLO.Me.Corrupted() then meCorr = true end
            if mq.TLO.Me.CountersCorruption and (tonumber(mq.TLO.Me.CountersCorruption()) or 0) > 0 then meCorr = true end
        end)
        if meCorr then return true end
        local debuffCorr = 0
        pcall(function()
            for i = 1, (mq.TLO.Me.CountBuffs() or 0) do
                local b = mq.TLO.Me.Buff(i)
                if b and b() and (b.CounterNumber() or 0) > 0 and b.CounterType() == 'Corruption' then
                    debuffCorr = debuffCorr + 1
                end
            end
        end)
        return debuffCorr > 0
    end

    local s = nil
    pcall(function() s = mq.TLO.Spawn(targetId) end)
    if not s or not s() then return false end
    local cleanName = ''
    pcall(function() cleanName = s.CleanName() or '' end)
    if cleanName ~= '' then
        local nbCorr = 0
        pcall(function()
            local nb = mq.TLO.NetBots(cleanName)
            if nb and nb() then
                nbCorr = tonumber(nb.Corrupted()) or 0
                if nbCorr == 0 and nb.CountersCorruption then
                    nbCorr = tonumber(nb.CountersCorruption()) or 0
                end
                if nbCorr == 0 then
                    local det = tostring(nb.Detrimental() or '')
                    if det:find('Corruption') then nbCorr = 1 end
                end
            end
        end)
        if nbCorr > 0 then return true end
    end

    if (mq.TLO.Target.ID() or 0) == targetId then
        local tcorr = false
        pcall(function()
            local c = mq.TLO.Target.Corrupted
            if c and c() then
                local str = tostring(c())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then tcorr = true end
            end
        end)
        if tcorr then return true end
    end

    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == targetId then
            local mc = false
            pcall(function()
                if m.Corrupted and m.Corrupted() then mc = true end
                if m.CountersCorruption and (tonumber(m.CountersCorruption()) or 0) > 0 then mc = true end
            end)
            if mc then return true end
        end
    end
    return false
end

local function resolvePetTargetId(when, spellName, cls, pct)
    local allPets = getAllMyPets()
    if #allPets == 0 then return nil end
    if #allPets == 1 then return allPets[1] end

    -- HP-based condition (healing): find lowest HP% pet among all player pets
    if when == 'HP <=' or when == 'target HP <=' or when == 'my HP <=' then
        local lowestPetId = nil
        local lowestHp = 9999
        for _, pid in ipairs(allPets) do
            local hp = pctHP(pid)
            if hp < lowestHp then
                lowestHp = hp
                lowestPetId = pid
            end
        end
        return lowestPetId or allPets[1]
    end

    -- Buff condition: find pet missing the buff
    if when == 'missing buff' and spellName and spellName ~= '' then
        local minSec = (not isCombat() and ctrl and tonumber(ctrl.buff_refresh_sec) or 0) or 0
        for _, pid in ipairs(allPets) do
            if not runtime.sungBuffs[sungKey(spellName, pid)] and not buffActive(pid, spellName, minSec) then
                return pid
            end
        end
        return allPets[1]
    end

    -- Cure condition: find pet with affliction
    local petAfflictionCheck = ({
        ['has Poison']         = isPoisoned,
        ['has Disease']        = isDiseased,
        ['has Poison/Disease'] = isPoisonedOrDiseased,
    })[when]
    if petAfflictionCheck then
        for _, pid in ipairs(allPets) do
            if petAfflictionCheck(pid) then
                return pid
            end
        end
        return allPets[1]
    end

    -- If class-specific pet is requested and alive, prefer it; otherwise return first pet
    if cls and petState.myPets[cls] and isSpawnAlive(petState.myPets[cls]) then
        return petState.myPets[cls]
    end

    return allPets[1]
end

function runtime.resolveAllEnemiesTargetId(spellName, when, pct, cls, extra)
    local isPulling = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp')
    local maxZ = isPulling and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75)
    local maxDist = (ctrl and ctrl.xtar_nav_dist) or 150
    local myZ = mq.TLO.Me.Z() or 0

    local isDet = isDetrimentalSpell(spellName, nil, extra and extra.kind, 'E: All Enemies')
    local maxC = tonumber(extra and extra.max_casts) or 0
    local hasDur = false
    if extra and (extra.kind == 'dot' or extra.kind == 'debuff') then
        hasDur = true
    elseif spellName and spellName ~= '' then
        pcall(function()
            local sp = mq.TLO.Spell(spellName)
            if sp and sp() then
                local dur = tonumber(sp.Duration()) or 0
                if dur > 0 then hasDur = true end
            end
        end)
    end

    local candidates = {}
    local slots = 13
    pcall(function() slots = mq.TLO.Me.XTargetSlots() or 13 end)

    for i = 1, slots do
        local xt = nil
        pcall(function() xt = mq.TLO.Me.XTarget(i) end)
        if xt and xt() then
            local id = 0
            pcall(function() id = xt.ID() or 0 end)
            if id > 0 and isSpawnAlive(id) and not isGroupOrRaidMember(id) and not isSpawnPetOrPlayer(id) then
                local s = mq.TLO.Spawn(id)
                if s and s() then
                    local stype = s.Type() or ''
                    local cname = s.CleanName() or ''
                    local dist = 999
                    local okDist, sDist = pcall(function() return s.Distance3D() or s.Distance() end)
                    if okDist and sDist then dist = sDist end
                    local okZ, sz = pcall(function() return s.Z() end)
                    local zOk = okZ and sz and (math.abs(sz - myZ) <= maxZ)

                    if (stype == 'NPC' or stype == 'Pet')
                        and not s.Dead() and stype ~= 'Corpse'
                        and isHostileTarget(id)
                        and dist <= maxDist
                        and zOk
                        and not isIgnored(cname)
                        and not isUnreachable(id) then

                        local engagedOk = not (ctrl.mode == 'Assist' and not runtime.targetIsEngaged(id))
                        if engagedOk then
                            local inRange = (not isDet) or runtime.isTargetInRange(spellName, id)
                            if inRange then
                                local lockedOut = castTracker and castTracker.isLockedOut(spellName, id, extra and extra.kind)
                                if not lockedOut then
                                    local castLimitOk = true
                                    local currentCasts = (runtime.npcCastCounts and runtime.npcCastCounts[id] and runtime.npcCastCounts[id][spellName]) or 0
                                    if maxC > 0 and currentCasts >= maxC then
                                        castLimitOk = false
                                    end
                                    if castLimitOk then
                                        local spellActive = false
                                        if hasDur and isDet and runtime.isNpcSpellActive(id, spellName) then
                                            spellActive = true
                                        end
                                        if not spellActive then
                                            local condMet = true
                                            if when and when ~= '' and when ~= 'always' then
                                                condMet = runtime.conditionMet(when, pct, spellName, id, cls, 'E: All Enemies', extra)
                                            end
                                            if condMet then
                                                local lastCastTime = (runtime.npcSpellLastCast and runtime.npcSpellLastCast[id] and runtime.npcSpellLastCast[id][spellName]) or 0
                                                local hp = s.PctHPs() or 100
                                                table.insert(candidates, {
                                                    id = id,
                                                    casts = currentCasts,
                                                    lastCast = lastCastTime,
                                                    hp = hp,
                                                    dist = dist
                                                })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            if a.casts ~= b.casts then return a.casts < b.casts end
            if a.lastCast ~= b.lastCast then return a.lastCast < b.lastCast end
            if a.hp ~= b.hp then return a.hp < b.hp end
            return a.dist < b.dist
        end)
        return candidates[1].id
    end

    local xtCount = runtime.countNPCXtarget and runtime.countNPCXtarget() or 0
    if xtCount == 0 then
        local curT = mq.TLO.Target.ID() or 0
        if curT > 0 and isHostileTarget(curT) and not isSpawnPetOrPlayer(curT) and isSpawnAlive(curT) then
            local lockedOut = castTracker and castTracker.isLockedOut(spellName, curT, extra and extra.kind)
            if not lockedOut and (not hasDur or not runtime.isNpcSpellActive(curT, spellName)) then
                return curT
            end
        end
    end

    return nil
end

function runtime.resolveTargetId(token, cls, when, spellName, pct, extra)
    local b = baseTok(token)
    local id
    if b == 'Myself' or b == 'Whole Group' then
        id = mq.TLO.Me.ID()
    elseif b == 'Main Assist' or b == 'Tank' then
        id = runtime.maPcId()
    elseif b == 'Lowest-HP Ally' then
        id = runtime.lowestHpAlly()
    elseif b == 'Pet' then
        id = resolvePetTargetId(when, spellName, cls, pct)
    elseif b == 'Current Target' then
        id = mq.TLO.Target.ID()
    elseif b == 'Assist Target' then
        id = runtime.maTargetId()
        if not id and (ctrl and ctrl.assist_self_defense ~= false) then
            local curT = mq.TLO.Target.ID() or 0
            if curT > 0 and isHostileTarget(curT) and not isSpawnPetOrPlayer(curT) then
                id = curT
            end
        end
    elseif b == 'Unmezzed Add' then
        id = firstNPCXtarget(true)
    elseif b == 'Nearest Add' then
        local isPulling = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp')
        local maxZ = isPulling and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75)
        id = firstNPCXtarget(false, maxZ)
        if not id then
            local minL = isPulling and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1)
            local maxL = isPulling and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100)
            local maxR = isPulling and (ctrl.camp_radius or 100) or (ctrl.hunter_radius or 1500)
            local myZ = mq.TLO.Me.Z() or 0
            for i = 1, 10 do
                local s = mq.TLO.NearestSpawn(i, string.format('npc targetable radius %d', maxR))
                if not s() then break end
                local sid = s.ID() or 0
                if sid > 0 and s.Type() == 'NPC' and not s.Dead() and s.Type() ~= 'Corpse'
                    and not isAnyPet(s) and not isSpawnPetOrPlayer(sid) and isHostileTarget(sid)
                    and not isIgnored(s.CleanName()) and not isUnreachable(sid) then
                    local okZ, sz = pcall(function() return s.Z() end)
                    if okZ and sz and math.abs(sz - myZ) <= maxZ then
                        local lvl = s.Level() or 0
                        if lvl == 0 or (lvl >= minL and lvl <= maxL) then
                            id = sid
                            break
                        end
                    end
                end
            end
        end
    elseif b == 'All Enemies' then
        id = runtime.resolveAllEnemiesTargetId(spellName, when, pct, cls, extra)
    else
        id = mq.TLO.Target.ID()
    end
    if not id or id <= 0 then return nil end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return nil end
    local stype = ''
    pcall(function() stype = s.Type() or '' end)
    local cname = ''
    pcall(function() cname = s.CleanName() or '' end)
    if cname ~= '' and isIgnored(cname) then return nil end
    if (stype == 'NPC' or stype == 'Pet') and isHostileTarget(id) and (ctrl.mode == 'Assist')
        and not runtime.targetIsEngaged(id) then
        return nil
    end
    return id
end

mq.event('TriuneZone', 'You have entered #*#', function()
    runtime.sungBuffs = {}; runtime.npcCastCounts = {}; runtime.npcSpellApplied = {}; runtime.npcSpellLastCast = {}; if runtime.onZoned then runtime.onZoned() end
end)

local function reconcileSungBuffs()
    local found = 0
    local function scanGemTable(gemsTable)
        for i = 1, NUM_GEMS do
            local g = gemsTable[i]
            local gpct = g and tonumber(g.pct)
            if gpct == nil then gpct = 100 end
            if g and g.cls == 'Brd' and g.spell and g.spell ~= '' and gpct > 0 then
                local bene = false
                pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                if bene then
                    local id = runtime.resolveTargetId(g.target, g.cls, g.when, g.spell, gpct)
                    if id and buffActive(id, g.spell) then
                        local key = sungKey(g.spell, id)
                        if not runtime.sungBuffs[key] then
                            runtime.sungBuffs[key] = true
                            found = found + 1
                        end
                    end
                end
            end
        end
    end
    scanGemTable(loadout.gems)
    if found > 0 then
        print('\ag[Triune]\ax found ' .. found .. ' bard buff(s) already active -- wont re-sing them.')
    end
end

function runtime.conditionMet(when, pct, spellName, targetId, cls, token, extra)
    pct = tonumber(pct) or 0
    if pct <= 0 then return false end
    if when == 'always' then return true end
    if when == 'in combat' or when == 'twist while fighting' then return isCombat() end

    -- Self-preservation and emergency abilities (Feign Death, Death Peace, Imitate Death, Mend, Bind Wound) ALWAYS evaluate the player's own HP
    if isFeignDeathAbility(spellName) or spellName == 'Mend' or spellName == 'Bind Wound' then
        if when == 'HP <=' or when == 'target HP <=' or when == 'my HP <=' then
            return pctHP(mq.TLO.Me.ID()) <= pct
        end
    end

    if when == 'my Mana <=' then return (mq.TLO.Me.PctMana() or 100) <= pct end
    if when == 'my HP <=' then
        local myMet = pctHP(mq.TLO.Me.ID()) <= pct
        if not runtime.isDetrimentalAction(spellName, token, extra) and token and baseTok(token) ~= 'Myself' and targetId and targetId > 0 and targetId ~= mq.TLO.Me.ID() and not isHostileTarget(targetId) then
            return myMet or (pctHP(targetId) <= pct)
        end
        return myMet
    end
    if when == 'HP <=' or when == 'target HP <=' then
        if token and baseTok(token) == 'Whole Group' then
            return pctHP(runtime.lowestHpAlly()) <= pct
        end
        return pctHP(targetId) <= pct
    end
    if when == 'target HP between' then
        local thp = pctHP(targetId)
        local minHp = 20
        if type(extra) == 'table' and extra.min_hp ~= nil then
            minHp = tonumber(extra.min_hp) or 20
        end
        return thp >= minHp and thp <= pct
    end
    if when == 'missing buff' then
        if not targetId or targetId <= 0 or not isSpawnAlive(targetId) then return false end
        if runtime.sungBuffs[sungKey(spellName, targetId)] then return false end -- already sung this life
        local minSec = (not isCombat() and ctrl and tonumber(ctrl.buff_refresh_sec) or 0) or 0
        return not buffActive(targetId, spellName, minSec)
    end
    -- Pet-summon gems: this server keeps a separate simultaneous pet per pet
    -- class, so this asks whether THIS gem's own class has a living tracked pet
    -- (see isPetMissingForClass) -- never the single-slot Me.Pet.
    if when == 'missing pet' then
        return isPetMissingForClass(cls)
    end
    if when == 'ally is Dead' then
        local s = mq.TLO.Spawn(targetId); return s() and s.Dead()
    end
    local afflictionCheck = ({
        ['has Poison']         = isPoisoned,
        ['has Disease']        = isDiseased,
        ['has Poison/Disease'] = isPoisonedOrDiseased,
    })[when]
    if afflictionCheck then
        if token and baseTok(token) == 'Whole Group' then
            if afflictionCheck(mq.TLO.Me.ID()) then return true end
            local total = 0
            pcall(function() total = mq.TLO.Group.Members() or 0 end)
            for i = 0, total do
                local m = nil
                pcall(function() m = mq.TLO.Group.Member(i) end)
                if m and m() and (m.ID() or 0) > 0 and afflictionCheck(m.ID()) then return true end
            end
            return false
        end
        return afflictionCheck(targetId)
    end
    if when == 'has Curse' then
        if token and baseTok(token) == 'Whole Group' then
            if isCursed(mq.TLO.Me.ID()) then return true end
            local total = 0
            pcall(function() total = mq.TLO.Group.Members() or 0 end)
            for i = 0, total do
                local m = nil
                pcall(function() m = mq.TLO.Group.Member(i) end)
                if m and m() and (m.ID() or 0) > 0 and isCursed(m.ID()) then return true end
            end
            return false
        end
        return isCursed(targetId)
    end
    if when == 'has Corruption' then
        if token and baseTok(token) == 'Whole Group' then
            if isCorrupted(mq.TLO.Me.ID()) then return true end
            local total = 0
            pcall(function() total = mq.TLO.Group.Members() or 0 end)
            for i = 0, total do
                local m = nil
                pcall(function() m = mq.TLO.Group.Member(i) end)
                if m and m() and (m.ID() or 0) > 0 and isCorrupted(m.ID()) then return true end
            end
            return false
        end
        return isCorrupted(targetId)
    end
    if when == 'Aggro on Me' then
        local onMe = false
        pcall(function()
            local holder = mq.TLO.Target.AggroHolder() or ''
            if holder ~= '' and holder == mq.TLO.Me.CleanName() then
                onMe = true
            elseif mq.TLO.Me.SecondaryPctAggro then
                local aggro = tonumber(mq.TLO.Me.PctAggro()) or 0
                if aggro >= 100 then onMe = true end
            end
        end)
        return onMe
    end
    if when == 'my Aggro >=' then
        local aggro = 0
        pcall(function()
            aggro = tonumber(mq.TLO.Me.PctAggro()) or 0
            if aggro == 0 and mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 then
                local holder = mq.TLO.Target.AggroHolder() or ''
                if holder ~= '' and holder == mq.TLO.Me.CleanName() then
                    aggro = 100
                end
            end
        end)
        return aggro >= pct
    end
    if when == 'add is loose' then return firstNPCXtarget(true) ~= nil end
    return true
end

-- ============================================================================
-- Spell Fail-Count & Lockout System (Target-aware, categorized failure policies)
-- ============================================================================
local function onFailureEvent(reason, evSpell, evTarget)
    castTracker.onFailureEvent(reason, ctrl and ctrl.cast_max_retries or 2, ctrl and ctrl.cast_lockout_sec or 30, evSpell, evTarget)
end

local function onCannotSeeEvent()
    onFailureEvent('cannot see target')
    if runtime.handleCannotSeeTarget then
        runtime.handleCannotSeeTarget()
    end
end

mq.event('TriuneFizzle', '#*#Your spell fizzles!#*#', function() onFailureEvent('fizzled') end)
mq.event('TriuneInterrupt1', '#*#Your spell is interrupted#*#', function() onFailureEvent('interrupted') end)
mq.event('TriuneInterrupt2', '#*#Your casting has been interrupted!#*#', function() onFailureEvent('interrupted') end)
mq.event('TriuneOutOfRangeSpell', '#*#target is out of range#*#', function() onFailureEvent('out of range') end)
mq.event('TriuneCannotSee1', '#*#cannot see your target#*#', onCannotSeeEvent)
mq.event('TriuneCannotSee2', '#*#can\'t see your target#*#', onCannotSeeEvent)
mq.event('TriuneNoTakeHold1', 'Your #1# spell did not take hold#*#', function(_, sp) onFailureEvent('did not take hold', sp) end)
mq.event('TriuneNoTakeHold2', '#*#Your spell did not take hold#*#', function() onFailureEvent('did not take hold') end)
mq.event('TriuneNoTakeHold3', '#*#Your spell would not have taken hold#*#', function() onFailureEvent('did not take hold') end)
mq.event('TriuneImmuneSpell1', 'Your target is immune to #1#', function(_, sp) onFailureEvent('target immune', sp) end)
mq.event('TriuneImmuneSpell2', '#*#Your target cannot be mezzed#*#', function() onFailureEvent('target immune') end)
mq.event('TriuneDeadTargetSpell', '#*#dead target#*#', function() onFailureEvent('dead target') end)
mq.event('TriuneCantCast', '#*#cast spells while#*#', function() onFailureEvent('cannot cast') end)
mq.event('TriuneResisted1', '#1# resisted your #2#!', function(_, tgt, sp) onFailureEvent('resisted', sp) end)
mq.event('TriuneResisted2', 'Your target resisted the #1# spell.#*#', function(_, sp) onFailureEvent('resisted', sp) end)
mq.event('TriuneNotReady', '#*#not ready#*#', function() onFailureEvent('not ready') end)
mq.event('TriuneNoMana', '#*#enough mana#*#', function() onFailureEvent('insufficient mana') end)
mq.event('TriunePetExists1', '#*#cannot have more than one pet#*#', function() onPetSummonRefused() end)
mq.event('TriunePetExists2', '#*#already have a pet#*#', function() onPetSummonRefused() end)

function runtime.castGem(i, g, id)
    local isFD = isFeignDeathAbility(g and g.spell)
    if not isFD and (isSitting() or isDucking()) then
        mq.cmd('/stand')
        mq.delay(50)
    end
    if castTracker.isLockedOut(g.spell, id, g.kind) then return false end
    local maxC = tonumber(g and g.max_casts) or 0
    if maxC > 0 and id and id > 0 then
        local currentCasts = (runtime.npcCastCounts and runtime.npcCastCounts[id] and runtime.npcCastCounts[id][g.spell]) or 0
        if currentCasts >= maxC then return false end
    end
    if not hasSpellReagents(g.spell) then
        if ctrl.debug_mode and (os.clock() - (runtime.lastReagentDiagAt or 0)) > 10.0 then
            runtime.lastReagentDiagAt = os.clock()
            print(string.format('\ar[Triune]\ax Cannot cast Gem %d "%s" -- missing required reagent components!', i, g.spell))
        end
        return false
    end
    local key = 'g' .. i
    if (os.clock() - (tonumber(runtime.lastCast[key]) or 0)) < 1.2 then return false end
    local sp = mq.TLO.Spell(g.spell)
    if not sp() then return false end
    local isMemmed = false
    pcall(function()
        isMemmed = isGemMatching(i, g.spell) or (mq.TLO.Me.Gem(g.spell)() ~= nil)
    end)
    if not isMemmed then return false end -- not memmed
    local spMana = tonumber(sp.Mana() or 0) or 0
    local curMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
    if curMana < spMana then return false end
    local isHeal = runtime.isHealAction(g.spell, g.target, g)
    local minMana = tonumber(ctrl and ctrl.min_mana_pct) or 0
    local pctMana = tonumber(mq.TLO.Me.PctMana() or 100) or 100
    if not isHeal and not ctrl.burn and minMana > 0 and pctMana < minMana then return false end
    if not mq.TLO.Me.SpellReady(g.spell)() then return false end

    local dur = 0
    pcall(function() dur = tonumber(sp.Duration()) or 0 end)
    dur = tonumber(dur) or 0
    if dur > 0 and buffActive(id, g.spell) and not (g.cls == 'Brd' and g.when == 'twist while fighting') then
        return false
    end

    if id and id > 0 and id ~= mq.TLO.Me.ID() and not runtime.isTargetInRange(g.spell, id) then
        return false
    end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    local hostileTarget = (orig > 0 and isHostileTarget and isHostileTarget(orig))
    local needsTarget = (orig ~= id) and not (selfCast and hostileTarget)
    if needsTarget and not runtime.setTarget(id) then return false end

    local pauseAttack = isFD and wasAttacking
    if pauseAttack then
        mq.cmd('/attack off')
        mq.delay(50, function() return not mq.TLO.Me.Combat() end)
    end

    local isDet = runtime.isDetrimentalAction(g.spell, g.target, g)
    castTracker.lastSpell      = g.spell
    castTracker.lastTime       = os.clock()
    castTracker.failed         = false
    castTracker.activeSpell    = g.spell
    castTracker.activeTargetId = id
    castTracker.activeKind     = g.kind
    if selfCast and hostileTarget then
        castTracker.targetRequired = false
    else
        castTracker.targetRequired = isDet or isTargetRequiredSpell(g.spell)
    end
    castTracker.castStartTime  = os.clock()
    clearCursor()
    if ctrl.debug_mode then
        print(string.format('\ao[DEBUG cast]\ax Gem %d "%s" on target #%d (dist=%.1f, Me.Combat=%s)',
            i, g.spell, id, distToId(id), tostring(mq.TLO.Me.Combat())))
    end
    if g.cls ~= 'Brd' then
        runtime.stopMovementForCast(g.cls, g.spell)
        local stillMoving = false
        pcall(function() stillMoving = mq.TLO.Me.Moving() or false end)
        if stillMoving then
            if ctrl.debug_mode then
                print(string.format('\ao[DEBUG cast]\ax Gem %d "%s" aborted: character is still moving', i, g.spell))
            end
            return false
        end
    end
    mq.cmdf('/cast "%s"', g.spell)
    runtime.lastCast[key] = os.clock()
    if id and id > 0 and g and g.spell and g.spell ~= '' then
        runtime.npcCastCounts = runtime.npcCastCounts or {}
        runtime.npcCastCounts[id] = runtime.npcCastCounts[id] or {}
        runtime.npcCastCounts[id][g.spell] = ((runtime.npcCastCounts[id][g.spell]) or 0) + 1

        runtime.npcSpellLastCast = runtime.npcSpellLastCast or {}
        runtime.npcSpellLastCast[id] = runtime.npcSpellLastCast[id] or {}
        runtime.npcSpellLastCast[id][g.spell] = os.clock()

        local durSec = 0
        pcall(function()
            local d = mq.TLO.Spell(g.spell).Duration() or 0
            if d and tonumber(d) then durSec = math.floor(tonumber(d) * 6) end
        end)
        if durSec > 0 then
            runtime.npcSpellApplied = runtime.npcSpellApplied or {}
            runtime.npcSpellApplied[id] = runtime.npcSpellApplied[id] or {}
            runtime.npcSpellApplied[id][g.spell] = os.clock() + durSec
        end

        local myPetId = 0
        pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
        if (myPetId > 0 and id == myPetId) or isSpawnMyPet(id) or isAnyPet(id) then
            local bene = false
            pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
            if bene then
                runtime.recordPetBuff(id, g.spell, durSec)
            end
        end
    end
    if g.when == 'missing pet' or g.kind == 'pet' then
        beginPetSummon(g.cls, g.spell)
    end
    if g.cls == 'Brd' then
        if sp.Beneficial() then
            local waited = 0
            while waited < 4000 do
                mq.delay(200); waited = waited + 200
                if buffActive(id, g.spell) then break end
                if not isCasting() then break end
            end
            mq.cmd('/stopsong')
            runtime.sungBuffs[sungKey(g.spell, id)] = true
            local bb, ss
            pcall(function() bb = mq.TLO.Me.Buff(g.spell)() end)
            pcall(function() ss = mq.TLO.Me.Song(g.spell)() end)
            print(string.format(
                '\ay[Triune bard]\ax %s  Buff=%s  Song=%s  (marked sung -- wont resing until zone/death)', g.spell,
                tostring(bb), tostring(ss)))
        else
            local castMs = 0
            pcall(function() castMs = sp.CastTime() or 0 end)
            castMs = tonumber(castMs) or 0
            if castMs <= 0 or castMs > 6000 then castMs = 2000 end
            mq.delay(castMs + 300)
            mq.cmd('/stopsong')
        end
    end
    if orig ~= id and orig > 0 and not (selfCast and hostileTarget) then
        if g.cls ~= 'Brd' then
            -- Spell has a cast time: keep target on ally until cast finishes, then restore combat target!
            runtime.restoreTargetId = orig
        else
            mq.delay(60)
            if mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
        end
    end
    if g.cls == 'Brd' and wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

function runtime.fireAA(name, a, id)
    if not name or name == '' then return false end
    if type(name) == 'string' then name = name:match('^%s*(.-)%s*$') end
    if not name or name == '' then return false end
    local isFD = isFeignDeathAbility(name)
    if not isFD and (isSitting() or isDucking()) then
        mq.cmd('/stand')
    end
    if castTracker.isLockedOut(name, id, a and a.kind) then return false end
    local key = 'a' .. name
    local now = os.clock()
    if runtime.lastCast[key] and now < (tonumber(runtime.lastCast[key]) or 0) then return false end
    local aa = mq.TLO.Me.AltAbility(name)
    if not aa() then return false end
    local aaRank = tonumber(aa.Rank() or 0) or 0
    if aaRank <= 0 then return false end
    if not mq.TLO.Me.AltAbilityReady(name)() then return false end
    local ok, sp = pcall(function() return aa.Spell end)
    local castMs = 0
    if ok and sp and sp() then
        local endCost = tonumber(sp.EnduranceCost() or 0) or 0
        local manaCost = tonumber(sp.Mana() or 0) or 0
        local curEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
        local curMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
        if endCost > 0 and curEnd < endCost then return false end
        if manaCost > 0 and curMana < manaCost then return false end
        pcall(function() castMs = tonumber(sp.CastTime() or 0) or 0 end)
    end
    if castMs > 0 then
        local isMoving = false
        pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
        if isCasting() or (runtime.isMoveActive and runtime.isMoveActive()) or isMoving then return false end
    end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    local hostileTarget = (orig > 0 and isHostileTarget and isHostileTarget(orig))
    local needsTarget = (orig ~= id) and not (selfCast and hostileTarget)
    if needsTarget and not runtime.setTarget(id) then return false end
    clearCursor()

    local pauseAttack = isFD and wasAttacking
    if pauseAttack then
        mq.cmd('/attack off')
        mq.delay(50, function() return not mq.TLO.Me.Combat() end)
    end

    if castMs > 0 then
        runtime.stopMovementForCast(a and a.cls, name)
        local stillMoving = false
        pcall(function() stillMoving = mq.TLO.Me.Moving() or false end)
        if stillMoving then return false end
    end

    local isDet = runtime.isDetrimentalAction(name, a and a.target, a)
    castTracker.lastSpell      = name
    castTracker.lastTime       = now
    castTracker.failed         = false
    castTracker.activeSpell    = name
    castTracker.activeTargetId = id
    castTracker.activeKind     = a and a.kind
    if selfCast and hostileTarget then
        castTracker.targetRequired = false
    else
        castTracker.targetRequired = isDet or isTargetRequiredSpell(name)
    end
    castTracker.castStartTime  = now
    mq.cmdf('/alt act %d', aa.ID())

    local aaReuse = 0
    pcall(function()
        local aaObj = mq.TLO.AltAbility(name)
        if aaObj and aaObj() then
            local mrt = aaObj.MyReuseTime and aaObj.MyReuseTime()
            local rt = aaObj.ReuseTime and aaObj.ReuseTime()
            aaReuse = tonumber(mrt or rt or 0) or 0
            if aaReuse == 0 and aaObj.Spell and aaObj.Spell() then
                aaReuse = tonumber(aaObj.Spell.RecastTime() or 0) or 0
            end
        end
    end)
    if aaReuse <= 0 then aaReuse = 60 end
    if not runtime.lastAAFiredAt then runtime.lastAAFiredAt = {} end
    runtime.lastAAFiredAt[name] = now
    if not runtime.aaCooldownTotal then runtime.aaCooldownTotal = {} end
    runtime.aaCooldownTotal[name] = aaReuse
    runtime.lastCast[key] = now + aaReuse

    print('\ag[Triune]\ax AA fired: ' .. name)
    if orig ~= id and orig > 0 and not (selfCast and hostileTarget) then
        if castMs > 0 then
            runtime.restoreTargetId = orig
        else
            mq.delay(60)
            if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
        end
    end
    if not isFD and wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

-- Auto AA engine (scan / prioritise / purchase / MQ2AAspend / Fireworks) lives in
-- the auto_aa plugin (lua/tac/auto_aa.lua). It reaches the combat loop only via
-- runtime.combatHold() and pm.onBetweenPulls().

runtime.isDiscReady = function(name)
    if not name or name == '' then return false end

    -- 1. Software timers: lockouts from previous cast duration / cooldown / timer groups
    local now = os.clock()
    if runtime.discExpires and runtime.discExpires[name] and now < (tonumber(runtime.discExpires[name]) or 0) then
        return false
    end
    if runtime.discCooldown and runtime.discCooldown[name] and now < (tonumber(runtime.discCooldown[name]) or 0) then
        return false
    end
    local key = 'd' .. name
    if runtime.lastCast[key] and now < (tonumber(runtime.lastCast[key]) or 0) then
        return false
    end

    local discInfo = getDiscCooldownAndDuration(name)
    if discInfo.timerGroupId then
        local tgKey = discInfo.timerGroupId
        if runtime.timerGroupCooldown and runtime.timerGroupCooldown[tgKey] and now < (tonumber(runtime.timerGroupCooldown[tgKey]) or 0) then
            return false
        end
    end

    -- 2. Known combat ability check
    local known = false
    pcall(function()
        local ca = mq.TLO.Me.CombatAbility(name)
        if ca and ca() then known = true end
    end)
    if not known and discInfo.discIdx <= 0 then return false end

    -- 3. MQ CombatAbilityReady check
    local readyOk, isReady = pcall(function() return mq.TLO.Me.CombatAbilityReady(name)() end)
    if readyOk and isReady == false then return false end

    -- 4. MQ CombatAbilityTimer check (dual-path: name, then index)
    local timerOk, timerVal = pcall(function()
        local cat = mq.TLO.Me.CombatAbilityTimer(name)
        if (not cat or not cat()) and discInfo.discIdx > 0 then
            cat = mq.TLO.Me.CombatAbilityTimer(discInfo.discIdx)
        end
        return cat
    end)
    if timerOk and timerVal then
        local sec = parseCombatAbilityTimer(timerVal)
        if sec > 0 then return false end
    end

    -- 5. Spell info (duration, endurance cost, target type)
    local endCost = discInfo.endCost
    local durSec = discInfo.durSec
    local isSelfTarget = true
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then
            local tt = sp.TargetType()
            if tt and tostring(tt):lower() ~= 'self' then isSelfTarget = false end
        end
    end)
    local myEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
    if endCost > 0 and myEnd < endCost then
        return false
    end

    -- 6. Active Disc state (Me.ActiveDisc)
    local adOk, ad = pcall(function() return mq.TLO.Me.ActiveDisc end)
    if adOk and ad and ad() then
        local adId = 0
        local adName = nil
        pcall(function()
            adId = tonumber(ad.ID() or 0) or 0
            adName = ad.Name()
        end)
        if adId > 0 or (adName and adName ~= '' and adName ~= 'NULL') then
            -- Exact same discipline is currently running!
            if adName and (adName:lower() == name:lower() or adName == name) then
                return false
            end
            -- If this discipline is a duration/stance disc, cannot activate while another active disc is running
            if durSec > 0 and isSelfTarget then
                return false
            end
        end
    end

    -- 7. Buff / Song check (for duration discs that land in buff or song window)
    local buffFound = false
    pcall(function()
        local b = mq.TLO.Me.Buff(name)
        if b and b() and parseDurationSec(b.Duration) > 0 then buffFound = true end
        if not buffFound then
            local s = mq.TLO.Me.Song(name)
            if s and s() and parseDurationSec(s.Duration) > 0 then buffFound = true end
        end
    end)
    if buffFound then return false end

    return true
end

runtime.isSkillReady = function(name)
    if not name or name == '' then return false end
    local now = os.clock()
    local key = 's' .. name
    if runtime.lastCast[key] and now < (tonumber(runtime.lastCast[key]) or 0) then return false end
    local readyOk, isReady = pcall(function() return mq.TLO.Me.AbilityReady(name)() end)
    if readyOk and isReady == false then return false end
    local timerOk, timerVal = pcall(function() return mq.TLO.Me.AbilityTimer(name) end)
    if timerOk and timerVal then
        local sec = parseDurationSec(timerVal)
        if sec > 0 then return false end
    end
    return true
end

runtime.fireDisc = function(name, a, id)
    if isSitting() or isDucking() then
        mq.cmd('/stand')
    end
    if not runtime.isDiscReady(name) then return false end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    if not selfCast and not runtime.setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/disc %s', name)

    -- Calculate duration & cooldown to lock out until the timer runs out
    local now = os.clock()
    local key = 'd' .. name
    local discInfo = getDiscCooldownAndDuration(name)
    local durSec = discInfo.durSec
    local recastSec = discInfo.recastSec
    local timerGroupId = discInfo.timerGroupId

    pcall(function()
        local cat = mq.TLO.Me.CombatAbilityTimer(name)
        if (not cat or not cat()) and discInfo.discIdx > 0 then
            cat = mq.TLO.Me.CombatAbilityTimer(discInfo.discIdx)
        end
        if cat and cat() then
            local ts = parseCombatAbilityTimer(cat)
            if ts > recastSec then recastSec = ts end
        end
    end)

    local lockSec = math.max(durSec, recastSec)
    if lockSec <= 0 then lockSec = 5.0 end

    if not runtime.discExpires then runtime.discExpires = {} end
    if not runtime.discCooldown then runtime.discCooldown = {} end
    if not runtime.lastDiscFiredAt then runtime.lastDiscFiredAt = {} end
    if not runtime.discTotalRecast then runtime.discTotalRecast = {} end

    if durSec > 0 then runtime.discExpires[name] = now + durSec end
    if recastSec > 0 then runtime.discCooldown[name] = now + recastSec end
    runtime.lastDiscFiredAt[name] = now
    runtime.discTotalRecast[name] = lockSec
    runtime.lastCast[key] = now + lockSec

    if timerGroupId then
        if not runtime.timerGroupCooldown then runtime.timerGroupCooldown = {} end
        runtime.timerGroupCooldown[timerGroupId] = now + lockSec
    end

    print('\ag[Triune]\ax discipline fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

runtime.fireSkill = function(name, a, id)
    if not name or name == '' then return false end
    local isFD = isFeignDeathAbility(name)
    if not isFD and (isSitting() or isDucking()) then
        mq.cmd('/stand')
    end
    if not runtime.isSkillReady(name) then return false end

    id = id or (a and runtime.resolveTargetId(a.target, a.cls, a.when, name, tonumber(a.pct) or 100)) or mq.TLO.Target.ID() or mq.TLO.Me.ID()
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    if not selfCast and id and id > 0 and not runtime.setTarget(id) then return false end
    clearCursor()

    -- Abilities like Begging, Pick Pockets, and Feign Death require auto-attack to be OFF to execute in EverQuest
    local pauseAttack = (isNonCombatSkill(name) or isFD) and wasAttacking
    if pauseAttack then
        mq.cmd('/attack off')
        mq.delay(50, function() return not mq.TLO.Me.Combat() end)
    end

    mq.cmdf('/doability "%s"', name)

    if pauseAttack and not isFD then
        mq.delay(50)
    end

    local now = os.clock()
    local key = 's' .. name
    local cd = getAbilityBaseCooldown(name)
    pcall(function()
        local t = mq.TLO.Me.AbilityTimer(name)
        if not t or not t() then
            local idx = mq.TLO.Me.Ability(name)()
            if idx and idx > 0 then t = mq.TLO.Me.AbilityTimer(idx) end
        end
        if t and t() then
            local ts = 0
            if type(t.TotalSeconds) == 'function' then
                ts = tonumber(t.TotalSeconds() or 0) or 0
            elseif type(t.TotalSeconds) == 'number' then
                ts = tonumber(t.TotalSeconds) or 0
            elseif t.Raw and type(t.Raw) == 'function' then
                ts = (tonumber(t.Raw() or 0) or 0) / 1000.0
            elseif tonumber(t()) then
                local n = tonumber(t()) or 0
                ts = n > 1000 and (n / 1000.0) or n
            end
            if ts > 0 then cd = ts end
        end
    end)
    runtime.lastCast[key] = now + cd
    if not runtime.lastSkillFiredAt then runtime.lastSkillFiredAt = {} end
    runtime.lastSkillFiredAt[name] = now

    print('\ag[Triune]\ax skill fired: ' .. name)
    if not selfCast and orig > 0 and orig ~= id then
        mq.delay(60)
        if mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if not isFD and wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

runtime.useClickie = function(c, id)
    if not c or not c.name or c.name == '' then return false end
    local effName = (c.spell and c.spell ~= '') and c.spell or c.name
    if castTracker.isLockedOut(effName, id, c.kind) then return false end
    if isSitting() or isDucking() then
        mq.cmd('/stand')
        mq.delay(50)
    end
    local key = 'c_' .. c.name
    if (os.clock() - (tonumber(runtime.lastCast[key]) or 0)) < 1.5 then return false end

    local fi = mq.TLO.FindItem('=' .. c.name)
    if not fi or not fi() then fi = mq.TLO.FindItem(c.name) end
    if not fi or not fi() then return false end

    local ready = false
    pcall(function()
        if mq.TLO.Me.ItemReady(c.name)() then
            ready = true
        elseif fi.TimerReady and tonumber(fi.TimerReady()) == 0 then
            ready = true
        end
    end)
    if not ready then return false end

    local castMs = 0
    pcall(function() castMs = tonumber(fi.CastTime() or 0) or 0 end)
    castMs = tonumber(castMs) or 0
    if castMs > 0 then
        local isMoving = false
        pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
        if isCasting() or isMoveActive() or isMoving then return false end
    end

    local dur = 0
    if c.spell and c.spell ~= '' then
        pcall(function() dur = tonumber(mq.TLO.Spell(c.spell).Duration()) or 0 end)
        dur = tonumber(dur) or 0
        if dur > 0 and buffActive(id, c.spell) then
            return false
        end
    end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    local hostileTarget = (orig > 0 and isHostileTarget and isHostileTarget(orig))
    local needsTarget = (orig ~= id) and not (selfCast and hostileTarget)
    if needsTarget and not runtime.setTarget(id) then return false end

    local isDet = runtime.isDetrimentalAction(effName, c.target, c)
    castTracker.lastSpell      = effName
    castTracker.lastTime       = os.clock()
    castTracker.failed         = false
    castTracker.activeSpell    = effName
    castTracker.activeTargetId = id
    castTracker.activeKind     = c.kind
    if selfCast and hostileTarget then
        castTracker.targetRequired = false
    else
        castTracker.targetRequired = isDet or isTargetRequiredSpell(effName)
    end
    castTracker.castStartTime  = os.clock()

    clearCursor()
    if ctrl.debug_mode then
        print(string.format('\ao[DEBUG clickie]\ax "%s" (spell="%s") on target #%d', c.name, tostring(c.spell), id))
    end
    if castMs > 0 then
        runtime.stopMovementForCast(c.cls, effName)
        local stillMoving = false
        pcall(function() stillMoving = mq.TLO.Me.Moving() or false end)
        if stillMoving then return false end
    end
    mq.cmdf('/useitem "%s"', c.name)
    runtime.lastCast[key] = os.clock()
    print('\ag[Triune]\ax Clickie used: ' .. c.name .. (c.spell and (' (' .. c.spell .. ')') or ''))

    if id and id > 0 then
        local effSpell = (c.spell and c.spell ~= '' and c.spell) or effName
        if effSpell and effSpell ~= '' then
            runtime.npcCastCounts = runtime.npcCastCounts or {}
            runtime.npcCastCounts[id] = runtime.npcCastCounts[id] or {}
            runtime.npcCastCounts[id][effSpell] = ((runtime.npcCastCounts[id][effSpell]) or 0) + 1

            runtime.npcSpellLastCast = runtime.npcSpellLastCast or {}
            runtime.npcSpellLastCast[id] = runtime.npcSpellLastCast[id] or {}
            runtime.npcSpellLastCast[id][effSpell] = os.clock()

            local durSec = 0
            pcall(function()
                local d = mq.TLO.Spell(effSpell).Duration() or 0
                if d and tonumber(d) then durSec = math.floor(tonumber(d) * 6) end
            end)
            if durSec > 0 then
                runtime.npcSpellApplied = runtime.npcSpellApplied or {}
                runtime.npcSpellApplied[id] = runtime.npcSpellApplied[id] or {}
                runtime.npcSpellApplied[id][effSpell] = os.clock() + durSec
            end
        end
    end

    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if id and id > 0 and ((myPetId > 0 and id == myPetId) or isSpawnMyPet(id) or isAnyPet(id)) then
        local cSpell = (c.spell and c.spell ~= '' and c.spell) or effName
        local durSec = 0
        pcall(function()
            local d = mq.TLO.Spell(cSpell).Duration() or 0
            if d and tonumber(d) then durSec = math.floor(tonumber(d) * 6) end
        end)
        runtime.recordPetBuff(id, cSpell, durSec)
    end

    if orig ~= id and orig > 0 and not (selfCast and hostileTarget) then
        if castMs > 0 then
            runtime.restoreTargetId = orig
        else
            mq.delay(60)
            if mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
        end
    end
    if castMs == 0 and wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

-- ============================================================================
-- HEALING PRIORITY ENGINE
-- Prioritizes reactive healing (Gems, AAs, Actions, Discs, Clickies) over all
-- movement, targeting, auto-attack, and offensive actions.
-- ============================================================================
function runtime.processHealPriority()
    if isCasting() or isCastingOrStarting() then return false end
    if not loadout then return false end

    local eligibleHeals = {}

    -- 1. Scan Gems for Heals
    if loadout.gems then
        for i = 1, #loadout.gems do
            local g = loadout.gems[i]
            if g and g.spell and g.spell ~= '' then
                if runtime.isHealAction(g.spell, g.target, g) then
                    local assignedGem = tonumber(g.gem) or math.min(i, 12)
                    local actualGem = assignedGem
                    local isMemmed = isGemMatching(assignedGem, g.spell)
                    if not isMemmed then
                        local otherSlot = nil
                        pcall(function() otherSlot = mq.TLO.Me.Gem(g.spell)() end)
                        if otherSlot and otherSlot > 0 then
                            actualGem = otherSlot
                            isMemmed = true
                        end
                    end
                    if isMemmed then
                        local pctVal = tonumber(g.pct) or 75
                        if pctVal > 0 then
                            local id = runtime.resolveTargetId(g.target, g.cls, g.when, g.spell, pctVal, g)
                            if id and isSpawnAlive(id) then
                                local rangeOk = (id == mq.TLO.Me.ID()) or runtime.isTargetInRange(g.spell, id)
                                if rangeOk then
                                    local lockedOut = castTracker and castTracker.isLockedOut(g.spell, id, g.kind)
                                    if not lockedOut and runtime.conditionMet(g.when, pctVal, g.spell, id, g.cls, g.target, g) then
                                        local sp = mq.TLO.Spell(g.spell)
                                        local spMana = (sp and sp() and tonumber(sp.Mana() or 0)) or 0
                                        local curMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
                                        local ready = false
                                        pcall(function() ready = mq.TLO.Me.SpellReady(g.spell)() end)
                                        if ready and curMana >= spMana and hasSpellReagents(g.spell) then
                                            local targetHp = pctHP(id) or 100
                                            eligibleHeals[#eligibleHeals + 1] = {
                                                type = 'gem',
                                                name = g.spell,
                                                slot = actualGem,
                                                entry = g,
                                                targetId = id,
                                                targetHp = targetHp,
                                                pctThreshold = pctVal,
                                                priority = tonumber(g.priority) or 50,
                                                cls = g.cls,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Scan Activated AAs for Heals
    if loadout.aas then
        for rawName, a in pairs(loadout.aas) do
            local name = type(rawName) == 'string' and rawName:match('^%s*(.-)%s*$') or rawName
            if a.enabled and runtime.isHealAction(name, a.target, a) then
                local aPct = tonumber(a.pct) or 50
                if aPct > 0 and (not a.burn_only or ctrl.burn) then
                    local id = runtime.resolveTargetId(a.target, a.cls, a.when, name, aPct, a)
                    if id and isSpawnAlive(id) then
                        local rangeOk = (id == mq.TLO.Me.ID()) or runtime.isTargetInRange(name, id)
                        if rangeOk and runtime.conditionMet(a.when, aPct, name, id, a.cls, a.target, a) then
                            local ready = false
                            pcall(function() ready = mq.TLO.Me.AltAbilityReady(name)() end)
                            if ready then
                                local targetHp = pctHP(id) or 100
                                eligibleHeals[#eligibleHeals + 1] = {
                                    type = 'aa',
                                    name = name,
                                    entry = a,
                                    targetId = id,
                                    targetHp = targetHp,
                                    pctThreshold = aPct,
                                    priority = tonumber(a.priority) or 15,
                                    cls = a.cls,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. Scan Actions (/doability, e.g. Mend) for Heals
    if loadout.actions then
        for name, act in pairs(loadout.actions) do
            if act.enabled and runtime.isHealAction(name, act.target, act) then
                local actPct = tonumber(act.pct) or 50
                if actPct > 0 and (not act.burn_only or ctrl.burn) then
                    local id = runtime.resolveTargetId(act.target, act.cls, act.when, name, actPct, act)
                    if id and isSpawnAlive(id) then
                        local rangeOk = (id == mq.TLO.Me.ID()) or runtime.isTargetInRange(name, id)
                        if rangeOk and runtime.conditionMet(act.when, actPct, name, id, act.cls, act.target, act) then
                            if runtime.isSkillReady(name) then
                                local targetHp = pctHP(id) or 100
                                eligibleHeals[#eligibleHeals + 1] = {
                                    type = 'action',
                                    name = name,
                                    entry = act,
                                    targetId = id,
                                    targetHp = targetHp,
                                    pctThreshold = actPct,
                                    priority = tonumber(act.priority) or 10,
                                    cls = act.cls,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- 4. Scan Clickies for Heals
    if loadout.clickies and #loadout.clickies > 0 then
        for _, c in ipairs(loadout.clickies) do
            local effName = (c.spell and c.spell ~= '') and c.spell or c.name
            if (c.enabled ~= false) and runtime.isHealAction(effName, c.target, c) then
                local cPct = tonumber(c.pct) or 60
                if cPct > 0 and (not c.burn_only or ctrl.burn) then
                    local id = runtime.resolveTargetId(c.target, 'ALL', c.when, effName, cPct, c)
                    if id and isSpawnAlive(id) then
                        local rangeOk = (id == mq.TLO.Me.ID()) or runtime.isTargetInRange(effName, id)
                        local lockedOut = castTracker and castTracker.isLockedOut(effName, id, c.kind)
                        if rangeOk and not lockedOut and runtime.conditionMet(c.when, cPct, effName, id, 'ALL', c.target, c) then
                            local ready = (not runtime.isClickieReady) or runtime.isClickieReady(c)
                            if ready then
                                local targetHp = pctHP(id) or 100
                                eligibleHeals[#eligibleHeals + 1] = {
                                    type = 'clickie',
                                    name = effName,
                                    entry = c,
                                    targetId = id,
                                    targetHp = targetHp,
                                    pctThreshold = cPct,
                                    priority = tonumber(c.priority) or 30,
                                    cls = c.cls or 'ALL',
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- 5. Scan Disciplines for Heals
    if loadout.discs then
        for name, d in pairs(loadout.discs) do
            if d.enabled and runtime.isHealAction(name, d.target, d) then
                local dPct = tonumber(d.pct) or 30
                if dPct > 0 and (not d.burn_only or ctrl.burn) then
                    local id = runtime.resolveTargetId(d.target, d.cls, d.when, name, dPct, d)
                    if id and isSpawnAlive(id) then
                        local rangeOk = (id == mq.TLO.Me.ID()) or runtime.isTargetInRange(name, id)
                        if rangeOk and runtime.conditionMet(d.when, dPct, name, id, d.cls, d.target, d) then
                            if runtime.isDiscReady(name) then
                                local targetHp = pctHP(id) or 100
                                eligibleHeals[#eligibleHeals + 1] = {
                                    type = 'disc',
                                    name = name,
                                    entry = d,
                                    targetId = id,
                                    targetHp = targetHp,
                                    pctThreshold = dPct,
                                    priority = tonumber(d.priority) or 20,
                                    cls = d.cls,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if #eligibleHeals == 0 then return false end

    -- Sort eligible heals:
    -- 1. Lowest target HP percentage (most damaged target first)
    -- 2. Lowest condition threshold (emergency 25% threshold before maintenance 75%)
    -- 3. Lowest priority setting (higher priority setting)
    table.sort(eligibleHeals, function(a, b)
        if a.targetHp ~= b.targetHp then
            return a.targetHp < b.targetHp
        end
        if a.pctThreshold ~= b.pctThreshold then
            return a.pctThreshold < b.pctThreshold
        end
        return (a.priority or 50) < (b.priority or 50)
    end)

    local best = eligibleHeals[1]
    if not best then return false end

    -- PRIORITIZE HEALING OVER MOVEMENT:
    if isSitting() or isDucking() then
        mq.cmd('/stand')
        mq.delay(50)
    end

    if best.cls ~= 'Brd' then
        runtime.stopMovementForCast(best.cls, best.name)
    end

    if best.type == 'gem' then
        return runtime.castGem(best.slot, best.entry, best.targetId)
    elseif best.type == 'aa' then
        return runtime.fireAA(best.name, best.entry, best.targetId)
    elseif best.type == 'action' then
        return runtime.fireSkill(best.name, best.entry, best.targetId)
    elseif best.type == 'disc' then
        return runtime.fireDisc(best.name, best.entry, best.targetId)
    elseif best.type == 'clickie' then
        return runtime.useClickie(best.entry, best.targetId)
    end

    return false
end


-- ============================================================================
-- MOVEMENT (phase 2, slice 2). Same pattern autocombat.lua proved: prefer MQ2Nav
-- when it's loaded and a path actually exists; otherwise fall back to /stick.
-- If neither plugin is loaded, movement is skipped and the character just fights
-- from wherever it's standing.
-- ============================================================================
-- Movement: plugin and distance helpers
-- ============================================================================

-- Reverted from 20 back to true melee weapon range -- 20 was meant to stop
-- nav short of pixel-stacking against an oversized mob's hitbox, but since
-- moveToward's own arrival check re-confirms "already arrived" every single
-- tick once within this distance (pursuitId stays 0, never re-evaluated), a
-- NORMAL-sized mob (e.g. an orc centurion) sitting anywhere between true
-- weapon range and 20 units was accepted as "arrived, combat=true, all
-- good" forever -- with real swings never actually connecting from that far,
-- and no mechanism to ever notice or correct it (reported live: character
-- flagged as in combat, engage=true, los=true, but not attacking at all,
-- just stuck). Oversized/hitbox-blocked mobs that genuinely can't be reached
-- at 14 are already covered separately by moveToward's own stall-timeout
-- acceptance branch below (dist + 12 tolerance, only after real evidence of
-- being stuck) -- that path doesn't need this constant widened to work.
pursuit.NAV_CONST = {
    MELEE_RANGE           = 14,
    LOS_TRUST_RANGE       = 8,
    PURSUIT_STALL_TIMEOUT = 8,   -- give up if no closer approach for this long
    LOS_FLICKER_GRACE     = 2.5, -- treat LoS as still good this long after the last true reading (stairs flicker it)
}

local function maxMeleeDistance(id)
    local NAV_CONST = pursuit.NAV_CONST
    local userDist = (ctrl and ctrl.melee_dist) or NAV_CONST.MELEE_RANGE
    local spawnReach = 0
    if id and id > 0 then
        pcall(function()
            local s = mq.TLO.Spawn(id)
            if s and s() then
                spawnReach = tonumber(s.MaxRangeTo()) or tonumber(s.MaxMeleeTo()) or 0
            end
        end)
        if spawnReach <= 0 then
            pcall(function()
                local t = mq.TLO.Target
                if t() and t.ID() == id then
                    spawnReach = tonumber(t.MaxRangeTo()) or tonumber(t.MaxMeleeTo()) or 0
                end
            end)
        end
    end
    -- If target is an oversized mob (dragon, giant, etc.) with a huge physical hitbox reach
    -- exceeding the user's configured distance, expand reach to prevent clipping inside the model
    if spawnReach > 18 and spawnReach > userDist then
        return spawnReach
    end
    return userDist
end
runtime.maxMeleeDistance = maxMeleeDistance

local function desiredRange(id)
    local NAV_CONST = pursuit.NAV_CONST
    if ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee' then
        return ctrl.pull_engage_dist or 100
    end
    local userDist = (ctrl and ctrl.melee_dist) or NAV_CONST.MELEE_RANGE
    local spawnReach = 0
    if id and id > 0 then
        pcall(function()
            local s = mq.TLO.Spawn(id)
            if s and s() then
                spawnReach = tonumber(s.MaxRangeTo()) or tonumber(s.MaxMeleeTo()) or 0
            end
        end)
        if spawnReach <= 0 then
            pcall(function()
                local t = mq.TLO.Target
                if t() and t.ID() == id then
                    spawnReach = tonumber(t.MaxRangeTo()) or tonumber(t.MaxMeleeTo()) or 0
                end
            end)
        end
    end
    -- For oversized mobs with hitboxes exceeding user distance, position near the outer edge
    if spawnReach > 18 and spawnReach > userDist then
        return math.max(userDist, math.floor(spawnReach - 3))
    end
    -- Position slightly inside user's max melee distance to avoid edge jitter
    return math.max(4, math.floor(userDist - 2))
end
runtime.desiredRange = desiredRange

-- ============================================================================
-- Navigation Intelligence: Hazard Memory, Breadcrumbs & Proactive Clearance
-- ============================================================================

-- Try to open the nearest door/switch. Direct fallback: door-target whatever
-- Switch is nearest and click it.
function runtime.tryOpenNearbyDoor(force)
    local now = os.clock()
    if not force and (now - stuckState.lastDoorClickAt) < 2.0 then return false end
    local ok, dist = pcall(function() return mq.TLO.Switch.Distance3D() end)
    if not ok or not dist or dist > 25 then return false end
    local isOpen = false
    pcall(function() isOpen = mq.TLO.Switch.Open() or false end)
    if isOpen and not force then return false end
    mq.cmd('/doortarget')
    mq.delay(50)
    mq.cmd('/click left door')
    mq.cmd('/click left target')
    pcall(function()
        if mq.TLO.Switch.Toggle then mq.TLO.Switch.Toggle() end
    end)
    stuckState.lastDoorClickAt = now
    return true
end

function runtime.getCurrentZoneShortName()
    local zs = 'unknown'
    pcall(function() zs = mq.TLO.Zone.ShortName() or 'unknown' end)
    return tostring(zs)
end

function runtime.getZoneHazards(zs)
    zs = zs or runtime.getCurrentZoneShortName()
    if not ctrl.zone_hazards then ctrl.zone_hazards = {} end
    if not ctrl.zone_hazards[zs] then ctrl.zone_hazards[zs] = {} end
    return ctrl.zone_hazards[zs]
end

function runtime.recordStuckHazard(x, y, z, zs)
    if not x or not y or not z then return end
    zs = zs or runtime.getCurrentZoneShortName()
    local hazards = runtime.getZoneHazards(zs)
    local clusterDist = 14.0
    local found = nil
    for _, h in ipairs(hazards) do
        local d = math.sqrt((x - h.x) ^ 2 + (y - h.y) ^ 2)
        if d <= clusterDist and math.abs(z - h.z) <= 15 then
            found = h
            break
        end
    end
    if found then
        local maxHits = ctrl.nav_hazard_max_hits or 6
        local newHits = math.min((found.hits or 1) + 1, maxHits)
        found.x = ((found.x * (newHits - 1)) + x) / newHits
        found.y = ((found.y * (newHits - 1)) + y) / newHits
        found.z = ((found.z * (newHits - 1)) + z) / newHits
        found.hits = newHits
        found.lastHitAt = os.time()
        print(string.format('\ay[Triune]\ax Updated navigation hazard hotspot in %s at (Y:%.1f, X:%.1f, Z:%.1f) [Hits: %d]',
            zs, found.y, found.x, found.z, found.hits))
    else
        table.insert(hazards, {
            x = x,
            y = y,
            z = z,
            radius = ctrl.nav_hazard_radius or 15,
            hits = 1,
            addedAt = os.time(),
            lastHitAt = os.time()
        })
        print(string.format('\ay[Triune]\ax Logged new navigation hazard hotspot in %s at (Y:%.1f, X:%.1f, Z:%.1f)',
            zs, y, x, z))
    end
    runtime.saveLoadout(true)
end

function runtime.clearZoneHazards(zs)
    zs = zs or runtime.getCurrentZoneShortName()
    if ctrl.zone_hazards then
        ctrl.zone_hazards[zs] = {}
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Cleared all navigation hazard hotspots for zone: %s', zs))
    end
end

function runtime.decayZoneHazards(zs)
    if not ctrl or not ctrl.nav_hazard_avoidance then return 0 end
    zs = zs or runtime.getCurrentZoneShortName()
    local zoneHazards = ctrl.zone_hazards or {}
    local hazards = zoneHazards[zs]
    if not hazards or #hazards == 0 then return 0 end
    local decaySeconds = (ctrl.nav_hazard_decay_minutes or 10) * 60
    local minHits = ctrl.nav_hazard_min_hits or 2
    local now = os.time()
    local changed = 0
    local removeList = {}
    for i, h in ipairs(hazards) do
        local lastHit = h.lastHitAt or h.addedAt or 0
        if (now - lastHit) >= decaySeconds then
            local newHits = (h.hits or 1) - 1
            if newHits >= 1 then
                h.hits = newHits
                h.lastHitAt = now
                if newHits < minHits then
                    print(string.format('\ay[Triune]\ax Navigation hazard hotspot in %s dampened below active threshold (Y:%.1f, X:%.1f).',
                        zs, h.y, h.x))
                end
            else
                table.insert(removeList, i)
                print(string.format('\ay[Triune]\ax Navigation hazard hotspot in %s forgotten (Y:%.1f, X:%.1f).',
                    zs, h.y, h.x))
            end
            changed = changed + 1
        end
    end
    for k = #removeList, 1, -1 do
        table.remove(hazards, removeList[k])
    end
    if changed > 0 then runtime.saveLoadout(true) end
    return changed
end

function runtime.isCoordInActiveHazard(x, y, z, zs)
    if not ctrl or not ctrl.nav_hazard_avoidance then return false, nil end
    local hazards = runtime.getZoneHazards(zs)
    local minHits = ctrl.nav_hazard_min_hits or 2
    for _, h in ipairs(hazards) do
        if (h.hits or 1) >= minHits then
            local r = h.radius or ctrl.nav_hazard_radius or 15
            local d = math.sqrt((x - h.x) ^ 2 + (y - h.y) ^ 2)
            if d <= r and math.abs((z or h.z) - h.z) <= 15 then
                return true, h
            end
        end
    end
    return false, nil
end

function runtime.findPathHazardIntersection(x1, y1, x2, y2, z1, zs)
    if not ctrl or not ctrl.nav_hazard_avoidance then return nil end
    local hazards = runtime.getZoneHazards(zs)
    local minHits = ctrl.nav_hazard_min_hits or 2
    local dx = x2 - x1
    local dy = y2 - y1
    local segLenSq = dx * dx + dy * dy
    if segLenSq < 4.0 then return nil end

    for _, h in ipairs(hazards) do
        if (h.hits or 1) >= minHits and math.abs((z1 or h.z) - h.z) <= 15 then
            local r = (h.radius or ctrl.nav_hazard_radius or 15)
            local t = ((h.x - x1) * dx + (h.y - y1) * dy) / segLenSq
            if t > 0.05 and t < 0.95 then
                local projX = x1 + t * dx
                local projY = y1 + t * dy
                local distToSeg = math.sqrt((h.x - projX) ^ 2 + (h.y - projY) ^ 2)
                if distToSeg < (r + 4.0) then
                    return h, t, distToSeg
                end
            end
        end
    end
    return nil
end

function runtime.clearDetour()
    pursuit.detourActive = false
    pursuit.detourX = 0
    pursuit.detourY = 0
    pursuit.detourZ = 0
    pursuit.detourTargetId = 0
    pursuit.detourTargetKey = nil
    pursuit.detourStartedAt = 0
    pursuit.detourExpiresAt = 0
end

function runtime.calculateDetourWaypoint(x1, y1, hx, hy, hz, r, destX, destY, destZ, zs)
    local vx = hx - x1
    local vy = hy - y1
    local vlen = math.sqrt(vx * vx + vy * vy)
    if vlen < 0.1 then
        vx, vy = 1, 0
        vlen = 1
    end
    local nx = -vy / vlen
    local ny = vx / vlen
    local offsetDist = (r or 15) + 8.0

    -- Candidate ground elevation estimation
    local candZ = hz or 0
    if destZ and type(destZ) == 'number' then
        candZ = (candZ + destZ) * 0.5
    end

    local cand1 = { x = hx + nx * offsetDist, y = hy + ny * offsetDist, z = candZ }
    local cand2 = { x = hx - nx * offsetDist, y = hy - ny * offsetDist, z = candZ }

    -- Multi-hazard filter: check if candidate falls inside another active hazard
    zs = zs or (runtime.getCurrentZoneShortName and runtime.getCurrentZoneShortName()) or 'unknown'
    local c1InHazard = false
    local c2InHazard = false
    if runtime.isCoordInActiveHazard then
        c1InHazard = runtime.isCoordInActiveHazard(cand1.x, cand1.y, cand1.z, zs)
        c2InHazard = runtime.isCoordInActiveHazard(cand2.x, cand2.y, cand2.z, zs)
    end

    if navLoaded() then
        local loc1Str = string.format('locyx %.2f %.2f', cand1.y, cand1.x)
        local loc2Str = string.format('locyx %.2f %.2f', cand2.y, cand2.x)
        local p1 = false
        local p2 = false
        pcall(function() p1 = mq.TLO.Navigation.PathExists(loc1Str)() or false end)
        pcall(function() p2 = mq.TLO.Navigation.PathExists(loc2Str)() or false end)

        -- If one candidate is inside another hazard and the other is clear, prefer the clear candidate
        if p1 and not c1InHazard and (not p2 or c2InHazard) then return cand1 end
        if p2 and not c2InHazard and (not p1 or c1InHazard) then return cand2 end

        if p1 and p2 then
            -- Both paths exist on mesh. Compare total travel cost (PathLength to candidate + distance to destination)
            local len1 = 9999
            local len2 = 9999
            pcall(function() len1 = mq.TLO.Navigation.PathLength(loc1Str)() or 9999 end)
            pcall(function() len2 = mq.TLO.Navigation.PathLength(loc2Str)() or 9999 end)

            if destX and destY then
                local d1ToDest = math.sqrt((cand1.x - destX) ^ 2 + (cand1.y - destY) ^ 2)
                local d2ToDest = math.sqrt((cand2.x - destX) ^ 2 + (cand2.y - destY) ^ 2)
                local cost1 = len1 + d1ToDest
                local cost2 = len2 + d2ToDest
                if c1InHazard then cost1 = cost1 + 1000 end
                if c2InHazard then cost2 = cost2 + 1000 end
                -- Heavily penalize candidates whose onward route immediately crosses a
                -- known hazard again (near-side detour points cause re-route oscillation).
                if runtime.findPathHazardIntersection(cand1.x, cand1.y, destX, destY, cand1.z, zs) then cost1 = cost1 + 1500 end
                if runtime.findPathHazardIntersection(cand2.x, cand2.y, destX, destY, cand2.z, zs) then cost2 = cost2 + 1500 end
                return (cost1 <= cost2) and cand1 or cand2
            else
                if c1InHazard and not c2InHazard then return cand2 end
                if c2InHazard and not c1InHazard then return cand1 end
                return (len1 <= len2) and cand1 or cand2
            end
        elseif p1 and not p2 then
            return cand1
        elseif p2 and not p1 then
            return cand2
        end
    end

    -- Fallback without MQ2Nav or when off-mesh
    if c1InHazard and not c2InHazard then return cand2 end
    if c2InHazard and not c1InHazard then return cand1 end
    if destX and destY then
        local d1 = (cand1.x - destX) ^ 2 + (cand1.y - destY) ^ 2
        local d2 = (cand2.x - destX) ^ 2 + (cand2.y - destY) ^ 2
        return (d1 <= d2) and cand1 or cand2
    end
    return cand1
end

function runtime.recordBreadcrumb()
    if not ctrl or not ctrl.nav_reverse_breadcrumbs then return end
    local me = mq.TLO.Me
    if not me() then return end
    local mx, my, mz = me.X() or 0, me.Y() or 0, me.Z() or 0
    local bc = runtime.pullBreadcrumbs
    if not bc then bc = {}; runtime.pullBreadcrumbs = bc end
    if #bc > 0 then
        local last = bc[#bc]
        local d = math.sqrt((mx - last.x) ^ 2 + (my - last.y) ^ 2)
        if d < 12 then return end
    end
    table.insert(bc, { x = mx, y = my, z = mz })
    if #bc > 60 then
        table.remove(bc, 1)
    end
end

function runtime.clearBreadcrumbs()
    runtime.pullBreadcrumbs = {}
end

function runtime.checkProactiveDoorAndLev()
    if not ctrl or (not ctrl.nav_proactive_doors and not ctrl.nav_levitation_clear) then return end
    local now = os.clock()
    if (now - (runtime.lastProactiveDoorAt or 0)) < 0.4 then return end
    runtime.lastProactiveDoorAt = now

    local ok, dist = pcall(function() return mq.TLO.Switch.Distance3D() end)
    if not ok or not dist or dist > 22 then return end

    local isOpen = false
    pcall(function() isOpen = mq.TLO.Switch.Open() or false end)
    if not isOpen and ctrl.nav_proactive_doors then
        runtime.tryOpenNearbyDoor(true)
    end

    if ctrl.nav_levitation_clear and dist <= 12 then
        local isLev = false
        pcall(function() isLev = mq.TLO.Me.Levitating() or false end)
        if isLev and (now - (runtime.lastLevClearAt or 0)) > 3.0 then
            local moving = false
            pcall(function() moving = mq.TLO.Me.Moving() or false end)
            if moving then
                runtime.lastLevClearAt = now
                pcall(function()
                    mq.cmd('/keypress duck')
                    mq.delay(120)
                    mq.cmd('/keypress duck')
                end)
            end
        end
    end
end

function runtime.isHeadingInForwardCone(facingHeadingDeg, px, py, tx, ty, maxAngleDeg)
    local maxDeg = maxAngleDeg or 75
    local minDot = math.cos(math.rad(maxDeg))
    local dx = tx - px
    local dy = ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.001 then return true end

    local vx = dx / dist
    local vy = dy / dist

    local hRad = math.rad(facingHeadingDeg or 0)
    -- In EQ coordinate system (Y is North, X is West):
    -- Heading 0 = North (+Y), 90 = West (+X), 180 = South (-Y), 270 = East (-X)
    local fx = math.sin(hRad)
    local fy = math.cos(hRad)

    local dot = fx * vx + fy * vy
    return dot >= minDot
end

function runtime.isSpawnInForwardCone(spawnId, maxAngleDeg)
    if not spawnId or spawnId <= 0 then return false end
    local me = mq.TLO.Me
    if not me() then return true end
    local s = mq.TLO.Spawn(spawnId)
    if not s() then return false end
    local myX, myY = me.X() or 0, me.Y() or 0
    local sx, sy = s.X() or 0, s.Y() or 0
    local myHeading = 0
    pcall(function() myHeading = me.Heading.Degrees() or me.Heading() or 0 end)
    return runtime.isHeadingInForwardCone(myHeading, myX, myY, sx, sy, maxAngleDeg)
end

function runtime.isBehindTarget(targetId)
    if not targetId or targetId <= 0 then return false end
    local me = mq.TLO.Me
    if not me() then return false end
    local s = mq.TLO.Spawn(targetId)
    if not s() then return false end

    -- Check MQ2MoveUtils TLO if active and stick is tracking this target
    if stickLoaded() then
        local stickOk = false
        local isBehind = false
        pcall(function()
            if (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') and mq.TLO.Stick.StickTarget() == targetId then
                isBehind = mq.TLO.Stick.Behind() or false
                stickOk = true
            end
        end)
        if stickOk then return isBehind end
    end

    -- Mathematical calculation:
    local px, py = me.X() or 0, me.Y() or 0
    local sx, sy = s.X() or 0, s.Y() or 0
    local sHead = 0
    pcall(function() sHead = s.Heading.Degrees() or s.Heading() or 0 end)
    local dx = px - sx
    local dy = py - sy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.001 then return true end

    local vx = dx / dist
    local vy = dy / dist

    -- Target forward unit vector in EQ coordinates (Y is North, X is West)
    local hRad = math.rad(sHead)
    local fx = math.sin(hRad)
    local fy = math.cos(hRad)

    -- Dot product: > 0 is front arc, <= 0 is rear arc (90 to 270 deg)
    local dot = fx * vx + fy * vy
    return dot <= 0.0
end

function runtime.getBehindLoc(targetId, dist)
    if not targetId or targetId <= 0 then return nil end
    local s = mq.TLO.Spawn(targetId)
    if not s() then return nil end
    local sx, sy, sz = s.X() or 0, s.Y() or 0, s.Z() or 0
    local sHead = 0
    pcall(function() sHead = s.Heading.Degrees() or s.Heading() or 0 end)
    local behindDist = dist or runtime.desiredRange(targetId)
    local hRad = math.rad(sHead)
    -- Facing unit vector is (sin(hRad), cos(hRad))
    -- Behind is target minus facing vector * dist
    local bx = sx - behindDist * math.sin(hRad)
    local by = sy - behindDist * math.cos(hRad)
    local bz = sz
    return bx, by, bz
end

function runtime.positionBehindTarget(targetId, targetDist)
    if not targetId or targetId <= 0 then return false end
    local dist = targetDist or runtime.desiredRange(targetId)
    local stickDist = math.max(4, math.floor(dist))

    if stickLoaded() then
        local needStick = true
        pcall(function()
            local sActive = mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON'
            local sTarget = mq.TLO.Stick.StickTarget() or 0
            local sBehind = mq.TLO.Stick.MoveBehind() or false
            if sActive and sTarget == targetId and sBehind and pursuit.lastBehindStickDist == stickDist then
                needStick = false
            end
        end)
        if needStick and not runtime.isCasting() then
            mq.cmdf('/stick id %d %d behind', targetId, stickDist)
            pursuit.lastBehindStickDist = stickDist
        end
        return true
    end

    -- Fallback when MQ2MoveUtils is not loaded: navigate to rear coordinates
    if not runtime.isBehindTarget(targetId) and not runtime.isCasting() then
        local bx, by, bz = runtime.getBehindLoc(targetId, dist)
        if bx then
            runtime.moveTowardLoc(bx, by, bz, 3)
            return false
        end
    else
        if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
            pursuit.lastCombatFaceAt = os.clock()
            mq.cmd('/face fast')
        end
        return true
    end
    return false
end

-- Raw 3D distance says nothing about walls/doors between you and the target --
-- being "within range" through a wall is not being in range at all. Without this,
-- moveToward would call itself "arrived" right at a doorway (in range by straight-
-- line distance, blocked by geometry) and stop navigating, while the engage logic
-- above tried to melee/shoot through the wall. Fails open (true) if the LoS TLO
-- itself errors, so a broken check can't wedge movement forever.

-- True when the zone mesh is loaded but MQ2Nav cannot path from our current
-- feet -- typical mesh hole / off-mesh landing. Used so hunter/puller still
-- pick a nearby NPC instead of standing still forever with "no path" to anyone.
function runtime.isPlayerOffMesh()
    if not navLoaded() then return false end
    local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
    if not meshOk or not meshLoaded then return false end
    local me = mq.TLO.Me
    if not me() then return false end
    local x, y, z = me.X() or 0, me.Y() or 0, me.Z() or 0
    local ok = false
    pcall(function()
        ok = mq.TLO.Navigation.PathExists(string.format('loc %.2f %.2f %.2f', y, x, z))() or false
    end)
    if ok then return false end
    pcall(function()
        ok = mq.TLO.Navigation.PathExists(string.format('locyx %.2f %.2f', y, x))() or false
    end)
    return not ok
end

-- When PathExists is false, walk toward the spawn with /stick (or native keys)
-- so we can step off the hole. moveToward remaps /nav as soon as a path exists
-- again. Existing PURSUIT_STALL_TIMEOUT still abandons if we never get closer.
function runtime.tryOffMeshRecovery(id, targetDist)
    if not id or id <= 0 then return false end
    if pursuit.meshRecoverId ~= id then
        pursuit.meshRecoverId = id
        pursuit.meshRecoverAt = os.clock()
        print(string.format(
            '\ay[Triune]\ax No navigation path to target #%d -- sticking toward it to leave the mesh hole, then remapping.',
            id))
        if navLoaded() then
            local navActive = false
            pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
            if navActive then pcall(function() mq.cmd('/nav stop') end) end
        end
    end

    local dist = math.max(4, math.floor(targetDist or 14))
    if stickLoaded() then
        if pursuit.lastNavTargetId ~= id or pursuit.lastStickDist ~= dist then
            mq.cmdf('/stick id %d %d', id, dist)
            pursuit.lastNavTargetId = id
            pursuit.lastStickDist = dist
        end
        return false
    end

    local nativeKey = string.format('native_spawn_%d', id)
    mq.cmd('/face fast')
    local isMoving = false
    pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
    if not isMoving then
        mq.cmd('/keypress forward hold')
    end
    pursuit.lastNavTargetId = nativeKey
    return false
end

function runtime.moveToward(id, dist, followOnly)
    local NAV_CONST = pursuit.NAV_CONST
    if not id or id <= 0 then return false end
    local d = distToId(id)
    local maxNav = (ctrl and ctrl.xtar_nav_dist) or 150
    if isXTargetId(id) and d > maxNav then
        stopMoving()
        return false
    end

    runtime.checkProactiveDoorAndLev()

    -- Detour State Machine & Hazard Avoidance
    local me = mq.TLO.Me
    if me() and ctrl.nav_hazard_avoidance and not followOnly then
        local mx, my, mz = me.X() or 0, me.Y() or 0, me.Z() or 0
        local now = os.clock()

        -- 1. Check in-flight active detour
        if pursuit.detourActive then
            if pursuit.detourTargetId ~= id then
                runtime.clearDetour()
            else
                local dDetour = math.sqrt((mx - pursuit.detourX) ^ 2 + (my - pursuit.detourY) ^ 2)
                if dDetour <= 8 then
                    runtime.clearDetour()
                else
                    -- Keep the detour alive while navigation to the waypoint is still
                    -- in flight; only abandon it once navigation concluded without arrival.
                    local navActiveToWaypoint = false
                    pcall(function() navActiveToWaypoint = mq.TLO.Navigation.Active() or false end)
                    if string.find(tostring(pursuit.lastNavLoc or ''), '^detour_') ~= nil and not navActiveToWaypoint then
                        runtime.clearDetour()
                    else
                        runtime.moveTowardLoc(pursuit.detourX, pursuit.detourY, pursuit.detourZ, 6)
                        return false
                    end
                end
            end
        end

        -- 2. If no active detour, check if straight path intersects a known hazard
        if not pursuit.detourActive then
            local ts = mq.TLO.Spawn(id)
            if ts() then
                local tx, ty, tz = ts.X() or 0, ts.Y() or 0, ts.Z() or mz
                local hz = runtime.findPathHazardIntersection(mx, my, tx, ty, mz)
                if hz then
                    local detour = runtime.calculateDetourWaypoint(mx, my, hz.x, hz.y, hz.z, hz.radius or 15, tx, ty, tz)
                    if detour then
                        local dDetour = math.sqrt((mx - detour.x) ^ 2 + (my - detour.y) ^ 2)
                        if dDetour > 8 then
                            pursuit.detourActive = true
                            pursuit.detourX = detour.x
                            pursuit.detourY = detour.y
                            pursuit.detourZ = detour.z
                            pursuit.detourTargetId = id
                            pursuit.detourTargetKey = string.format('%.1f_%.1f_%.1f', detour.y, detour.x, detour.z)
                            pursuit.detourStartedAt = now
                            pursuit.detourExpiresAt = now + 15.0
                            runtime.moveTowardLoc(detour.x, detour.y, detour.z, 6)
                            return false
                        end
                    end
                end
            end
        end
    end

    local isMelee = not followOnly
    local targetDist = dist or desiredRange(id)
    local effectiveArrivalDist = targetDist + (isMelee and 2 or 3)

    -- Update pursuit tracking for stall detection. `d` (distToId) is MQ's 2D
    -- Distance -- X/Y only -- so climbing a ladder toward a target mostly
    -- above/below us shows as zero progress here even while we're actually
    -- closing in via Z. Left unhandled, PURSUIT_STALL_TIMEOUT below would
    -- eventually give up and markUnreachable() a target we're mid-climb
    -- toward, purely because the ladder segment isn't meshed. Treat active
    -- climbing as progress too so the stall timer keeps getting refreshed
    -- for as long as we're genuinely climbing.
    if pursuit.id ~= id then
        pursuit.id = id; pursuit.bestDist = d; pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0; pursuit.wasNavActive = false
        pursuit.lastLoSAt = 0
    elseif d < pursuit.bestDist - 2 or isClimbingLadder() then
        pursuit.bestDist = math.min(pursuit.bestDist, d); pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0
    end

    local losNow = hasLoS(id)
    if losNow then pursuit.lastLoSAt = os.clock() end
    local losOk = losNow or (pursuit.lastLoSAt > 0 and (os.clock() - pursuit.lastLoSAt) < NAV_CONST.LOS_FLICKER_GRACE)

    if d <= effectiveArrivalDist and (losOk or d <= NAV_CONST.LOS_TRUST_RANGE) then
        stopMoving()
        if not followOnly then
            if mq.TLO.Target.ID() ~= id then runtime.setTarget(id) end
            if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                pursuit.lastCombatFaceAt = os.clock()
                mq.cmd('/face fast')
            end
        end
        pursuit.lastNavTargetId = 0
        pursuit.id = 0
        return true
    end

    if (os.clock() - pursuit.improvedAt) > NAV_CONST.PURSUIT_STALL_TIMEOUT or pursuit.navStalls >= 3 then
        if d <= effectiveArrivalDist + 12 and losOk then
            stopMoving()
            if not followOnly then
                if mq.TLO.Target.ID() ~= id then runtime.setTarget(id) end
                mq.cmd('/face fast')
            end
            pursuit.lastNavTargetId = 0
            pursuit.id = 0
            return true
        end
        if not followOnly then
            print(string.format(
                '\ay[Triune]\ax giving up on target %d -- %s (likely elevated/blocked despite a ground path existing).',
                id,
                pursuit.navStalls >= 3 and 'nav keeps completing without ever reaching range' or
                ('no progress for ' .. NAV_CONST.PURSUIT_STALL_TIMEOUT .. 's')))
            runtime.markUnreachable(id)
            stopMoving()
            clearTarget()
            pursuit.id = 0
            pursuit.lastNavTargetId = 0
            pursuit.noPathFails = 0
            runtime.pullTargetId = 0
            runtime.pullState = 'IDLE'
            return false
        end
    end

    -- Movement Stage 1: MQ2Nav
    if navLoaded() then
        local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
        local ok = false
        pcall(function() ok = mq.TLO.Navigation.PathExists('id ' .. id)() end)
        if ok then
            if pursuit.meshRecoverId == id then
                print(string.format(
                    '\ag[Triune]\ax Remapped nav path to #%d after off-mesh stick recovery.', id))
                if stickLoaded() then
                    local stickActive = false
                    pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
                    if stickActive then pcall(function() mq.cmd('/stick off') end) end
                end
                if pursuit.lastNavTargetId and string.find(tostring(pursuit.lastNavTargetId), '^native_') then
                    pcall(function() mq.cmd('/keypress forward') end)
                end
                pursuit.meshRecoverId = 0
                pursuit.meshRecoverAt = 0
                pursuit.lastNavTargetId = 0
            end
            pursuit.noPathFails = 0
            local navActiveNow = mq.TLO.Navigation.Active()
            if pursuit.wasNavActive and not navActiveNow then
                pursuit.navStalls = pursuit.navStalls + 1
            end
            pursuit.wasNavActive = navActiveNow
            if pursuit.lastNavTargetId ~= id or not navActiveNow then
                mq.cmdf('/nav id %d distance=%d', id, math.floor(targetDist))
                pursuit.lastNavTargetId = id
            end
            return false
        elseif meshOk and meshLoaded and (d > effectiveArrivalDist or not losOk) then
            -- Zone mesh is loaded but there is no path from here -- typically we
            -- landed in a hole. Stick toward the spawn so we can step back onto
            -- the mesh; the `if ok` branch remaps /nav as soon as PathExists.
            pursuit.noPathFails = (pursuit.noPathFails or 0) + 1
            return runtime.tryOffMeshRecovery(id, targetDist)
        end
    end

    -- Movement Stage 2: MQ2Stick / MoveUtils
    if stickLoaded() and ctrl.nav_fallback_stick then
        if pursuit.lastNavTargetId ~= id or pursuit.lastStickDist ~= targetDist then
            local behindMod = (ctrl.mode == 'Assist' and ctrl.assist_behind ~= false and not runtime.playerHasAggro(id)) and ' behind' or ''
            mq.cmdf('/stick id %d %d%s', id, targetDist, behindMod)
            pursuit.lastNavTargetId = id
            pursuit.lastStickDist = targetDist
        end
        return false
    end

    -- Movement Stage 3: Native EQ movement keys & /face
    local nativeKey = string.format('native_spawn_%d', id)
    mq.cmd('/face fast')
    local isMoving = false
    pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
    if not isMoving then
        mq.cmd('/keypress forward hold')
    end
    pursuit.lastNavTargetId = nativeKey
    return false
end

-- ============================================================================
-- Door / Switch & Reposition / Close-in Handlers
-- ============================================================================

local function repositionCloser()
    if not isCombat() then return end
    -- Manual mode with Stick off: the player owns movement.
    if ctrl.mode == 'Manual' and ctrl.manual_stick == false then return end
    local tgt = mq.TLO.Target
    if not (tgt() and tgt.Type() == 'NPC' and not tgt.Dead()) then return end
    local tid = tgt.ID()
    if not ctrl.running then return end
    if isMoveActive() then return end
    if (os.clock() - pursuit.lastTooFarRepositionAt) < 1.0 then return end
    pursuit.lastTooFarRepositionAt = os.clock()

    local currentDist = distToId(tid)
    -- When EQ reports "too far away", ensure we close in tighter than current distance
    local targetDist = math.max(5, math.min(desiredRange(tid), math.floor(currentDist - 8)))

    print(string.format(
        '\ay[Triune]\ax Target too far away (dist %.1f) -- repositioning closer (%d units) on target #%d.', currentDist,
        targetDist, tid))

    -- Reset navigation target cache so moveToward/reposition issues a fresh movement command
    pursuit.lastNavTargetId = 0
    pursuit.lastStickDist = 0
    if runtime.clearDetour then runtime.clearDetour() end

    mq.cmd('/face fast')

    if navLoaded() then
        local hasPath = false
        pcall(function() hasPath = mq.TLO.Navigation.PathExists('id ' .. tid)() end)
        if hasPath then
            mq.cmdf('/nav id %d distance=%d', tid, targetDist)
            return
        end
    end

    if stickLoaded() then
        local behindMod = (ctrl.mode == 'Assist' and ctrl.assist_behind ~= false and not runtime.playerHasAggro(tid)) and ' behind' or ''
        mq.cmdf('/stick id %d %d%s', tid, targetDist, behindMod)
    else
        mq.cmd('/keypress forward hold')
        mq.delay(200)
        mq.cmd('/keypress forward')
    end
end

local function handleCantHitFromHere()
    if not isCombat() then return end
    -- Manual mode with Stick off: the player owns movement (and their target).
    if ctrl.mode == 'Manual' and ctrl.manual_stick == false then return end
    local tgt = mq.TLO.Target
    if not (tgt() and (tgt.Type() == 'NPC' or tgt.Type() == 'Pet') and not tgt.Dead() and tgt.Type() ~= 'Corpse') then return end
    local tid = tgt.ID()
    if not ctrl.running then return end
    local now = os.clock()
    if (now - (pursuit.lastCantHitAt or 0)) < 1.0 then return end

    if (now - (pursuit.lastCantHitAt or 0)) > 6.0 then
        pursuit.cantHitCount = 1
    else
        pursuit.cantHitCount = (pursuit.cantHitCount or 0) + 1
    end
    pursuit.lastCantHitAt = now

    if pursuit.cantHitCount >= 4 then
        print(string.format(
            '\ay[Triune]\ax Target #%d (%s) obstructed after 4 "cannot hit" attempts -- marking unreachable & picking new target.',
            tid, tostring(tgt.CleanName())))
        runtime.markUnreachable(tid)
        stopMoving()
        clearTarget()
        pursuit.cantHitCount = 0
        pursuit.id = 0
        pursuit.lastNavTargetId = 0
        runtime.pullTargetId = 0
        runtime.pullState = 'IDLE'
        return
    end

    local curDist = distToId(tid)
    print(string.format(
        '\ay[Triune]\ax "Cannot hit from here" (dist %.1f) on #%d (%s) -- opening doors and repositioning.',
        curDist, tid, tostring(tgt.CleanName())))

    -- Try opening any nearby door or switch first
    if runtime.tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax Clicked nearby door/switch to clear line of sight.')
    end

    -- Reset navigation target cache so reposition issues a fresh movement command
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.lastStickDist = 0
    if runtime.clearDetour then runtime.clearDetour() end

    mq.cmd('/face fast')

    -- If we have repeated failures in quick succession (e.g. wedged on doorway frame or wall corner),
    -- execute a brief backup + strafe jump to break geometric collision snags.
    if pursuit.cantHitCount == 3 then
        mq.cmd('/keypress back hold')
        mq.delay(250)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_left hold')
        mq.delay(200)
        mq.cmd('/keypress strafe_left')
        mq.cmd('/keypress jump')
        mq.cmd('/face fast')
    end

    local targetDist = math.max(5, math.min(desiredRange(tid), math.floor(curDist - 8)))

    if navLoaded() then
        local hasPath = false
        pcall(function() hasPath = mq.TLO.Navigation.PathExists('id ' .. tid)() end)
        if hasPath then
            mq.cmdf('/nav id %d distance=%d', tid, targetDist)
            return
        end
    end

    if stickLoaded() then
        local behindMod = (ctrl.mode == 'Assist' and ctrl.assist_behind ~= false and not runtime.playerHasAggro(tid)) and ' behind' or ''
        mq.cmdf('/stick id %d %d%s', tid, targetDist, behindMod)
    else
        mq.cmd('/keypress forward hold')
        mq.delay(250)
        mq.cmd('/keypress forward')
    end
end

mq.event('TriuneTooFar1', '#*#too far away#*#', function() repositionCloser() end)
mq.event('TriuneTooFar2', '#*#get closer#*#', function() repositionCloser() end)
mq.event('TriuneTooFar3', '#*#cannot reach#*#', function() repositionCloser() end)
mq.event('TriuneCantHit1', '#*#cannot hit#*#from here#*#', function() handleCantHitFromHere() end)
mq.event('TriuneCantHit2', '#*#can\'t hit#*#from here#*#', function() handleCantHitFromHere() end)
mq.event('TriuneCantHit3', '#*#not in line of sight#*#', function() handleCantHitFromHere() end)


-- Same idea for a fixed camp location (used returning from a pull).
function runtime.moveTowardLoc(x, y, z, dist)
    dist = dist or 15
    if distToLoc(x, y, z) <= dist then
        stopMoving()
        pursuit.lastNavLoc = nil
        if runtime.clearDetour then runtime.clearDetour() end
        return true
    end

    runtime.checkProactiveDoorAndLev()

    local locKey = string.format('%.1f_%.1f_%.1f', y, x, z)

    -- Detour State Machine for Loc navigation (e.g. camp return, waypoints)
    -- In-flight detours stay active while navigation toward the waypoint makes
    -- progress; a new detour is only created when not already headed to one.
    local me = mq.TLO.Me
    if me() and ctrl.nav_hazard_avoidance then
        local mx, my, mz = me.X() or 0, me.Y() or 0, me.Z() or 0
        local now = os.clock()
        local headingToWaypoint = string.find(tostring(pursuit.lastNavLoc or ''), '^detour_') ~= nil

        -- 1. Check in-flight active detour for this loc target
        if pursuit.detourActive then
            if pursuit.detourTargetKey ~= locKey then
                runtime.clearDetour()
            else
                local dDetour = math.sqrt((mx - pursuit.detourX) ^ 2 + (my - pursuit.detourY) ^ 2)
                if dDetour <= 8 then
                    runtime.clearDetour()
                else
                    local detourKey = string.format('detour_%.1f_%.1f_%.1f', pursuit.detourY, pursuit.detourX, pursuit.detourZ)
                    if navLoaded() then
                        local navActive = false
                        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
                        if headingToWaypoint and navActive then
                            -- still en route to the waypoint: keep following, no hard expiry
                            return false
                        elseif now > (pursuit.detourExpiresAt or 0) then
                            -- waypoint navigation already ended before arrival and the
                            -- backstop elapsed: give up this detour and re-evaluate
                            runtime.clearDetour()
                        else
                            local locyxStr = string.format('locyx %.2f %.2f', pursuit.detourY, pursuit.detourX)
                            local ok = false
                            pcall(function() ok = mq.TLO.Navigation.PathExists(locyxStr)() end)
                            if ok then
                                mq.cmdf('/nav %s', locyxStr)
                                pursuit.lastNavLoc = detourKey
                                return false
                            end
                        end
                    end
                end
            end
        end

        -- 2. If no active detour (and not already heading to a waypoint),
        --    check if straight path to destination intersects a known hazard
        if not pursuit.detourActive and not headingToWaypoint then
            local hz = runtime.findPathHazardIntersection(mx, my, x, y, mz)
            if hz then
                local detour = runtime.calculateDetourWaypoint(mx, my, hz.x, hz.y, hz.z, hz.radius or 15, x, y, z)
                if detour then
                    local dDetour = math.sqrt((mx - detour.x) ^ 2 + (my - detour.y) ^ 2)
                    if dDetour > 8 then
                        pursuit.detourActive = true
                        pursuit.detourX = detour.x
                        pursuit.detourY = detour.y
                        pursuit.detourZ = detour.z
                        pursuit.detourTargetId = 0
                        pursuit.detourTargetKey = locKey
                        pursuit.detourStartedAt = now
                        pursuit.detourExpiresAt = now + 15.0

                        local detourKey = string.format('detour_%.1f_%.1f_%.1f', detour.y, detour.x, detour.z)
                        if navLoaded() then
                            local navActive = false
                            pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
                            if pursuit.lastNavLoc ~= detourKey or not navActive then
                                local locyxStr = string.format('locyx %.2f %.2f', detour.y, detour.x)
                                local ok = false
                                pcall(function() ok = mq.TLO.Navigation.PathExists(locyxStr)() end)
                                if ok then
                                    mq.cmdf('/nav %s', locyxStr)
                                    pursuit.lastNavLoc = detourKey
                                    return false
                                end
                                -- No mesh path around the hazard: abandon the detour and
                                -- let the normal route below aim straight at the destination.
                                runtime.clearDetour()
                            else
                                return false
                            end
                        end
                    end
                end
            end
        end
    end

    local locStr = string.format('loc %.2f %.2f %.2f', y, x, z) -- Y X Z, matches EQ standard

    if navLoaded() then
        local navActive = false
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
        if pursuit.lastNavLoc ~= locKey or not navActive then
            local ok = false
            pcall(function() ok = mq.TLO.Navigation.PathExists(locStr)() end)
            if ok then
                mq.cmdf('/nav %s', locStr)
                pursuit.lastNavLoc = locKey
                return false
            end
            local locyxStr = string.format('locyx %.2f %.2f', y, x)
            local ok2 = false
            pcall(function() ok2 = mq.TLO.Navigation.PathExists(locyxStr)() end)
            if ok2 then
                mq.cmdf('/nav %s', locyxStr)
                pursuit.lastNavLoc = locKey
                return false
            end
        else
            return false
        end
    end

    if stickLoaded() then
        local movetoKey = 'moveto_' .. locKey
        local moveToActive = false
        pcall(function() moveToActive = (mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving()) or false end)
        if pursuit.lastNavLoc ~= movetoKey or not moveToActive then
            mq.cmdf('/moveto loc %.2f %.2f %.2f mdist %d', y, x, z, math.max(5, math.floor(dist)))
            pursuit.lastNavLoc = movetoKey
        end
        return false
    end

    local nativeKey = 'native_' .. locKey
    mq.cmdf('/face fast loc %.2f,%.2f', y, x)
    local isMoving = false
    pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
    if not isMoving then
        mq.cmd('/keypress forward hold')
    end
    pursuit.lastNavLoc = nativeKey
    return false
end

function runtime.wpTick()
    local wps = ctrl.waypoints
    if not wps or #wps == 0 then return false end
    if not ctrl.current_waypoint_idx or ctrl.current_waypoint_idx < 1 or ctrl.current_waypoint_idx > #wps then
        ctrl.current_waypoint_idx = 1
    end
    local wp = wps[ctrl.current_waypoint_idx]
    if not wp or not wp.x or not wp.y or not wp.z then return false end

    local radius = ctrl.waypoint_radius or 20
    local dist = distToLoc(wp.x, wp.y, wp.z)

    if dist <= radius then
        local prevIdx = ctrl.current_waypoint_idx
        if #wps <= 1 then
            ctrl.current_waypoint_idx = 1
            ctrl.waypoint_direction = 1
        elseif ctrl.waypoint_loop then
            -- Looping: always advance forward, wrapping to the first
            -- waypoint after the last instead of reversing direction.
            local nextIdx = prevIdx + 1
            if nextIdx > #wps then nextIdx = 1 end
            ctrl.waypoint_direction = 1
            ctrl.current_waypoint_idx = nextIdx
        else
            local dir = ctrl.waypoint_direction or 1
            if dir ~= 1 and dir ~= -1 then dir = 1 end

            local nextIdx = prevIdx + dir
            if nextIdx > #wps then
                dir = -1
                nextIdx = math.max(1, #wps - 1)
            elseif nextIdx < 1 then
                dir = 1
                nextIdx = math.min(#wps, 2)
            end
            ctrl.waypoint_direction = dir
            ctrl.current_waypoint_idx = nextIdx
        end

        local nextWp = wps[ctrl.current_waypoint_idx]
        if nextWp then
            print(string.format('\ay[Triune]\ax Reached %s (#%d) -- patrolling to %s (#%d) [%s]',
                wp.name or ('WP ' .. prevIdx), prevIdx, nextWp.name or ('WP ' .. ctrl.current_waypoint_idx),
                ctrl.current_waypoint_idx, (ctrl.waypoint_direction or 1) == 1 and 'Forward' or 'Reverse'))
            runtime.moveTowardLoc(nextWp.x, nextWp.y, nextWp.z, radius)
        end
    else
        runtime.moveTowardLoc(wp.x, wp.y, wp.z, radius)
    end
    return true
end

-- Stuck detection/recovery, ported from autocombat.lua's proven perform_unstuck_maneuver.
-- triune's movement had NO recovery at all: if nav/stick got blocked by a wall or a
-- door the mesh doesn't route around, it would just sit there re-issuing the same
-- command forever (this is what "stops on walls" was). Same fix: notice we haven't
-- actually displaced while nav/stick claims to be active, then back up + strafe +
-- jump to break free.

-- Movement: stuck/recovery helpers

function runtime.performUnstuck()
    if runtime.tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax stuck -- tried opening a nearby door.')
        mq.delay(600)
        stuckState.counter = 0
        stuckState.lastStuckRecoveryAt = os.clock()
        pursuit.id = 0; pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil
        if runtime.clearDetour then runtime.clearDetour() end
        return
    end

    local now = os.clock()
    -- Increment attempt sequence for recurring stuck events near the same obstacle.
    -- If previous recovery was > 20s ago, reset attempts counter to 1.
    if not stuckState.lastStuckRecoveryAt or (now - stuckState.lastStuckRecoveryAt) > 20 then
        stuckState.attempts = 1
    else
        stuckState.attempts = (stuckState.attempts or 0) + 1
        if stuckState.attempts > 4 then
            stuckState.attempts = 1
        end
    end
    stuckState.lastStuckRecoveryAt = now

    local me = mq.TLO.Me
    if me() and ctrl.nav_hazard_avoidance then
        local mx, my, mz = me.X() or 0, me.Y() or 0, me.Z() or 0
        if mx ~= 0 or my ~= 0 then
            runtime.recordStuckHazard(mx, my, mz)
        end
    end

    -- Report the target distance at the moment of firing -- if this still
    -- fires right next to a live mob despite the checkStuck deferral above,
    -- this number is what tells us so instead of guessing again.
    local tgt = mq.TLO.Target
    local tgtNote = (tgt() and tgt.Type() == 'NPC') and
        string.format(' (target dist %.0f, desired %.0f)', distToId(tgt.ID()), desiredRange()) or ''

    if navLoaded() then
        local navActive = false
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
        if navActive then mq.cmd('/nav stop') end
    end
    if stickLoaded() then
        local stickActive = false
        pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
        if stickActive then mq.cmd('/stick off') end
    end
    pcall(function()
        if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving() then
            mq.cmd('/moveto off')
        end
    end)
    pcall(function() mq.cmd('/keypress forward') end)

    if stuckState.attempts == 1 then
        -- Step 1: back up and jump
        print('\ay[Triune]\ax stuck (Attempt 1) -- backing up.' .. tgtNote)
        mq.cmd('/keypress back hold')
        mq.delay(1200)
        mq.cmd('/keypress back')
        mq.cmd('/keypress jump')
    elseif stuckState.attempts == 2 then
        -- Step 2: back up briefly then step left
        print('\ay[Triune]\ax stuck (Attempt 2) -- stepping left.' .. tgtNote)
        mq.cmd('/keypress back hold')
        mq.delay(400)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_left hold')
        mq.delay(1000)
        mq.cmd('/keypress strafe_left')
        mq.cmd('/keypress jump')
    elseif stuckState.attempts == 3 then
        -- Step 3: back up briefly then step right past initial position
        print('\ay[Triune]\ax stuck (Attempt 3) -- stepping right past initial position.' .. tgtNote)
        mq.cmd('/keypress back hold')
        mq.delay(400)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_right hold')
        mq.delay(1800)
        mq.cmd('/keypress strafe_right')
        mq.cmd('/keypress jump')
    elseif stuckState.attempts >= 4 then
        -- Step 4: All directional unstuck attempts failed; mark target unreachable & search for a new target
        local currentTgtId = nil
        pcall(function()
            if tgt() and tgt.Type() == 'NPC' and (tgt.ID() or 0) > 0 then
                currentTgtId = tgt.ID()
            end
        end)
        if not currentTgtId and pursuit.id and pursuit.id > 0 then
            currentTgtId = pursuit.id
        end
        if not currentTgtId and runtime.pullTargetId and runtime.pullTargetId > 0 then
            currentTgtId = runtime.pullTargetId
        end

        if currentTgtId and currentTgtId > 0 then
            print(string.format(
                '\ay[Triune]\ax stuck (Attempt 4) -- all directional maneuvers failed. Abandoning target #%d and searching for a new target.',
                currentTgtId))
            runtime.markUnreachable(currentTgtId)
            clearTarget()
        else
            print(
                '\ay[Triune]\ax stuck (Attempt 4) -- all directional maneuvers failed. Clearing pursuit to find a new target/path.')
        end

        pursuit.id = 0
        pursuit.lastNavTargetId = 0
        pursuit.lastNavLoc = nil
        pursuit.wanderLoc = nil
        if runtime.clearDetour then runtime.clearDetour() end
        runtime.pullTargetId = 0
        runtime.pullState = 'IDLE'

        stuckState.attempts = 0
        stuckState.counter = 0
        stuckState.lastX, stuckState.lastY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
        return
    end

    stuckState.counter = 0
    stuckState.lastX, stuckState.lastY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    pursuit.id = 0; pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil -- force a fresh /nav command next tick
    if runtime.clearDetour then runtime.clearDetour() end
end

function runtime.checkStuck()
    local now = os.clock()
    if (now - stuckState.checkAt) < 1.0 then return end
    stuckState.checkAt = now

    -- Stuck detection MUST only evaluate when movement is actively running
    -- (i.e. MQ2Nav or MQ2MoveUtils is active). If neither plugin is moving,
    -- the character is stationary by design (idle, waiting, sitting, medding, or casting).
    local trying = isMoveActive()
    if not trying then
        stuckState.counter = 0
        stuckState.lastX, stuckState.lastY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
        return
    end

    -- If casting, sitting, ducking, medding, or immobilized (stunned/rooted), do not count as stuck
    local me = mq.TLO.Me
    if me() then
        if isCasting() or me.Sitting() or me.Ducking() or me.Stunned() or me.Rooted() or runtime.medBreakActive then
            stuckState.counter = 0
            stuckState.lastX, stuckState.lastY = me.X() or 0, me.Y() or 0
            return
        end
    end

    -- If we have a target (NPC or PC player like MA in chase mode) and are within range, we are not stuck
    local nt = mq.TLO.Target
    if nt() and not nt.Dead() and (nt.Type() or '') ~= 'Corpse' then
        local reqDist = (nt.Type() == 'PC' and (ctrl.chase_dist or 15) or desiredRange()) + 12
        if distToId(nt.ID()) <= reqDist then
            if nt.Type() == 'NPC' and not hasLoS(nt.ID()) then
                runtime.tryOpenNearbyDoor() -- close to target but blocked by door/wall; try opening doors
            else
                stuckState.counter = 0
                stuckState.lastX, stuckState.lastY = me.X() or 0, me.Y() or 0
                return
            end
        end
    end

    -- Climbing a ladder moves almost entirely in Z, so the X/Y-only distance
    -- check below reads it as no progress at all and eventually calls
    -- performUnstuck() mid-climb -- exactly the wrong response (jumping/
    -- strafing off a ladder rung is far more likely to actually get us
    -- stuck, or knock us off, than doing nothing). Treat active climbing the
    -- same as the other legitimate-progress cases above.
    if isClimbingLadder() then
        stuckState.counter = 0
        stuckState.lastX, stuckState.lastY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
        return
    end

    runtime.tryOpenNearbyDoor() -- open any door we're walking past, before we ever stall on it
    local x, y = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    local dist = math.sqrt((x - stuckState.lastX) ^ 2 + (y - stuckState.lastY) ^ 2)
    if dist < 2 then
        stuckState.counter = stuckState.counter + 1
        if stuckState.counter > 2 then runtime.performUnstuck() end
    else
        stuckState.counter = 0
    end
    stuckState.lastX, stuckState.lastY = x, y
end

function runtime.checkCombatStall()
    if (ctrl.mode == 'Assist' and ctrl.submode == 'Backline')
        or (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState ~= 'FIGHTING') then
        return
    end

    -- Must be actively in combat, or have hostile enemies on XTarget, or already attacking
    local inCombat = mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT') or runtime.anyXtarAlive(true)
    if not inCombat then
        return
    end

    local t = mq.TLO.Target
    local haveLiveNPC = t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse'
    if not haveLiveNPC or not isHostileTarget(t.ID()) then
        return
    end

    -- In Manual mode, only watchdog auto-attack if the target is an active hostile XTarget or actively fighting us
    if ctrl.mode == 'Manual' and not (isXTargetId(t.ID()) or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')) then
        return
    end

    -- In Assist mode, only watchdog auto-attack if this target is the active MA target or active self-defense target
    if ctrl.mode == 'Assist' then
        local maId = runtime.maTargetId()
        local defId = nil
        if not maId and (ctrl.assist_self_defense ~= false) then
            defId = runtime.findSelfDefenseTarget()
        end
        local expectedId = maId or defId
        if not expectedId or expectedId ~= t.ID() then
            return
        end
    end

    local d = distToId(t.ID())
    local isPullStandBack = (ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee')
    if not isPullStandBack then
        if d <= maxMeleeDistance(t.ID()) and not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
    end
end

-- When EQ chat reports "You cannot see your target." during combat, this active
-- repositioning maneuver steps back from the target and re-faces it. In EQ, being
-- inside or right under a mob's bounding box/hitbox causes line-of-sight raycasts
-- to fail internally. Stepping backward to the perimeter of melee reach restores LoS.
runtime.handleCannotSeeTarget = function()
    if not ctrl or not ctrl.running then return end
    local tgt = mq.TLO.Target
    if not tgt or not tgt() then return end

    local tid = tgt.ID() or 0
    if tid <= 0 then return end

    local isNpc = (tgt.Type() == 'NPC' or tgt.Type() == 'Pet') and not tgt.Dead() and tgt.Type() ~= 'Corpse'
    if not isNpc or not isHostileTarget(tid) then return end

    -- User override (Settings tab): skip the step-back maneuver entirely.
    if ctrl.los_face_only then
        mq.cmd('/face fast')
        return
    end

    local d = distToId(tid)
    local maxReach = maxMeleeDistance(tid)
    local isMelee = mq.TLO.Me.Combat() or (d <= (maxReach + 10))

    if not isMelee then
        mq.cmd('/face fast')
        return
    end

    local now = os.clock()
    if not stuckState.lastCannotSeeAt or (now - stuckState.lastCannotSeeAt) > 4.0 then
        stuckState.cannotSeeAttempts = 1
    else
        stuckState.cannotSeeAttempts = (stuckState.cannotSeeAttempts or 0) + 1
    end
    stuckState.lastCannotSeeAt = now

    -- Pause stick if active so it doesn't fight our reposition
    if stickLoaded() then
        pcall(function()
            if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                mq.cmd('/stick pause')
            end
        end)
    end
    pcall(function() mq.cmd('/keypress forward') end)

    if stuckState.cannotSeeAttempts == 1 then
        print(string.format('\ay[Triune]\ax "Cannot see target" in melee (Attempt 1) -- stepping back (dist=%.1f).', d))
        mq.cmd('/keypress back hold')
        mq.delay(250)
        mq.cmd('/keypress back')
        mq.cmd('/face fast')
    elseif stuckState.cannotSeeAttempts == 2 then
        print(string.format('\ay[Triune]\ax "Cannot see target" in melee (Attempt 2) -- backing up & strafing left (dist=%.1f).', d))
        mq.cmd('/keypress back hold')
        mq.delay(250)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_left hold')
        mq.delay(200)
        mq.cmd('/keypress strafe_left')
        mq.cmd('/face fast')
    elseif stuckState.cannotSeeAttempts == 3 then
        print(string.format('\ay[Triune]\ax "Cannot see target" in melee (Attempt 3) -- backing up & strafing right (dist=%.1f).', d))
        mq.cmd('/keypress back hold')
        mq.delay(250)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_right hold')
        mq.delay(200)
        mq.cmd('/keypress strafe_right')
        mq.cmd('/face fast')
    else
        -- Attempt 4+: Obstacle or wall blocking sight line
        if runtime.tryOpenNearbyDoor(true) then
            print('\ay[Triune]\ax "Cannot see target" -- attempted to open nearby door.')
            mq.delay(400)
        elseif ctrl and ctrl.mode == 'Puller' then
            print(string.format('\ay[Triune]\ax Target #%d obstructed after 4 reposition attempts -- marking unreachable.', tid))
            runtime.markUnreachable(tid)
            stopMoving()
            clearTarget()
        else
            print(string.format('\ay[Triune]\ax Target #%d still cannot be seen (dist=%.1f) -- performing unstuck recovery.', tid, d))
            runtime.performUnstuck()
        end
        stuckState.cannotSeeAttempts = 0
    end
end

function runtime.chaseMA()
    if not ctrl.chase then return end
    local id = runtime.maPcId()
    if not id then return end
    runtime.moveToward(id, ctrl.chase_dist or 15, true) -- follow position only; id here is the MA player, not a combat target
    -- Face whatever NPC target is already set (from the Assist/Tank block
    -- above) while following along, so the character isn't left facing the
    -- MA player instead of the actual target it's supposed to be watching.
    local t = mq.TLO.Target
    if t() and t.Type() == 'NPC' then mq.cmd('/face fast') end
end

-- Assist/Tank's idle behavior (nothing to assist right now): if a camp spot
-- is set, hold it instead of chasing the MA around -- this was the ORIGINAL
-- design intent for Assist mode (see triune-mode-roadmap memory) that never
-- actually got built. Falls back to chaseMA() unchanged when no camp is set,
-- so this is purely opt-in.
function runtime.idleReturn()
    if ctrl.camp_loc then
        runtime.moveTowardLoc(ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, 15)
    else
        runtime.chaseMA()
    end
end

-- Finds a mob for Hunter/Puller to engage on their own initiative: something
-- already on your aggro list, or the nearest targetable NPC within your search
-- radius. Skips anything on the ignore list, and (Hunter's own request) anything
-- more than `hunter_z` units above/below you, so it won't chase something on
-- another floor or ledge. Never used for Assist or a target you pick yourself.
--
-- NOTE: iterates NearestSpawn directly rather than gating on SpawnCount() first --
-- on this MQ build SpawnCount and NearestSpawn don't always agree for a combined
-- "targetable radius N" filter, which silently returned zero candidates and left
-- Hunter standing still. NearestSpawn(i, ...) returning a falsy spawn () is what
-- actually marks "no more candidates."
function runtime.findRoamTarget(searchRadius, searchMaxZ, minLevel, maxLevel)
    local isPulling    = (ctrl.mode == 'Puller')
    local isCampMode   = isPulling and (ctrl.submode == 'Camp')
    local minLv        = minLevel or (isCampMode and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1))
    local maxLv        = maxLevel or (isCampMode and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100))

    local anchorLoc    = isCampMode and ctrl.camp_loc or ctrl.hunter_combat_loc
    local anchorRadius = isCampMode and (searchRadius or ctrl.camp_radius or 100) or
        (anchorLoc and (ctrl.hunter_combat_radius or 0) or 0)

    -- Explicit Y/X handling to account for EQ's (Y, X) standard
    local function outsideAnchor(sy, sx)
        if anchorRadius <= 0 or not anchorLoc then return false end
        -- When Waypoint Patrol is active, pulling/hunting scans dynamically around the character's patrol location
        if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
            return false
        end
        local ay = anchorLoc.y or anchorLoc[1] or 0
        local ax = anchorLoc.x or anchorLoc[2] or 0
        local dy = sy - ay
        local dx = sx - ax
        return (dx * dx + dy * dy) > (anchorRadius * anchorRadius)
    end

    local playerOffMesh = runtime.isPlayerOffMesh()

    local function scanSpawns(maxZ)
        local radius = searchRadius or 100
        local p = string.format('npc radius %d zradius %d targetable', radius, maxZ)
        for i = 1, 100 do
            local s = mq.TLO.NearestSpawn(i, p)
            if not s() then break end

            local sid = s.ID() or 0
            if sid > 0 then
                local sname = s.CleanName()
                local dead = false
                local stype = ''
                local state = ''
                pcall(function()
                    dead = s.Dead() or false
                    stype = s.Type() or ''
                    state = s.State() or ''
                end)
                local isDead = dead or stype == 'Corpse' or state == 'DEAD'
                if not isDead and runtime.isPullAllowed(sname) and runtime.isConAllowed(s) and not isSpawnPetOrPlayer(sid) and not isUnreachable(sid) then
                    local sy = s.Y() or 0
                    local sx = s.X() or 0
                    if not outsideAnchor(sy, sx) then
                        local slvl = s.Level() or 0
                        if slvl >= minLv and slvl <= maxLv then
                            if isHostileTarget(sid) then
                                if runtime.verifyTargetCon(sid) then
                                    local sz = s.Z() or 0
                                    local inHaz = runtime.isCoordInActiveHazard(sx, sy, sz)
                                    local pathOk = not inHaz
                                    if pathOk and navLoaded() and not playerOffMesh then
                                            local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
                                            if meshOk and meshLoaded then
                                                local dist = s.Distance3D() or 999
                                                local closeReach = desiredRange(sid) or 14
                                                if dist > closeReach or not hasLoS(sid) then
                                                    local hasPath = false
                                                    local ok = pcall(function() hasPath = mq.TLO.Navigation.PathExists('id ' .. sid)() end)
                                                    if ok and not hasPath then
                                                        pathOk = false
                                                    elseif ok and hasPath then
                                                        local pathLen = 0
                                                        pcall(function() pathLen = mq.TLO.Navigation.PathLength('id ' .. sid)() or 0 end)
                                                        local maxRatio = ctrl.nav_max_path_ratio or 2.5
                                                        if pathLen > 0 and dist > 20 and (pathLen / dist) > maxRatio then
                                                            pathOk = false
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if pathOk then
                                        return sid
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    -- Two-Tier Z-Plane Target Acquisition:
    -- Tier 1: Look for NPCs within the player's immediate Z plane (same floor/elevation)
    local floorZ = isCampMode and (ctrl.camp_z_plane or 15) or (ctrl.hunter_z_plane or 15)
    local tier1Z = math.min(floorZ, searchMaxZ or 75)
    local targetId = scanSpawns(tier1Z)
    if targetId then return targetId end

    -- Tier 2: Expand to full maxZ range if no target on immediate floor
    local maxZ = searchMaxZ or (isCampMode and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75))
    if maxZ > tier1Z then
        targetId = scanSpawns(maxZ)
        if targetId then return targetId end
    end

    return nil
end

function runtime.checkCloserTarget(curTargetId, searchRadius, searchMaxZ, minLevel, maxLevel)
    if not curTargetId or curTargetId <= 0 then return nil end
    if ctrl.check_closer_mobs == false then return nil end
    local maxRetargets = ctrl.max_closer_retargets or 1
    if maxRetargets <= 0 or (pursuit.retargetCount or 0) >= maxRetargets then return nil end

    local now = os.clock()
    local interval = ctrl.closer_scan_interval or 1.0
    if (pursuit.lastCloserScanAt or 0) > 0 and (now - pursuit.lastCloserScanAt) < interval then return nil end
    pursuit.lastCloserScanAt = now

    local isPulling = (ctrl.mode == 'Puller')
    local isCampMode = isPulling and (ctrl.submode == 'Camp')
    local minL = minLevel or (isCampMode and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1))
    local maxL = maxLevel or (isCampMode and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100))
    local maxZ = searchMaxZ or (isCampMode and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75))

    local curDist = distToId(curTargetId)
    if curDist <= 35 or mq.TLO.Me.Combat() then return nil end

    local candId = runtime.findRoamTarget(searchRadius, maxZ, minL, maxL)
    if candId and candId ~= curTargetId then
        -- Anti-ping-pong: ignore candidate if already targeted or abandoned during this pull cycle
        if pursuit.cycleTargetIds and pursuit.cycleTargetIds[candId] then
            return nil
        end

        -- Directional cone filter: ensure candidate is in front of the player's movement heading
        if ctrl.closer_forward_cone_only and not runtime.isSpawnInForwardCone(candId, 75) then
            return nil
        end

        local candDist = distToId(candId)
        local curHasLoS = hasLoS(curTargetId)
        local candHasLoS = hasLoS(candId)

        -- If LoS priority is active and current target has no LoS while candidate does,
        -- allow a more lenient distance threshold (15 units closer and 85% of distance)
        local minSavings = 25
        local maxRatio = 0.75
        if ctrl.closer_los_priority and not curHasLoS and candHasLoS then
            minSavings = 15
            maxRatio = 0.85
        end

        if candDist <= (curDist - minSavings) and candDist <= (curDist * maxRatio) then
            return candId, candDist, curDist
        end
    end
    return nil
end

function runtime.checkPullHpRest()
    if ctrl.mode ~= 'Puller' then
        if runtime.pullHpRest then
            runtime.pullHpRest = false
            if isSitting() or isDucking() then mq.cmd('/stand') end
        end
        return false
    end

    local minHp = tonumber(ctrl.pull_min_hp_pct) or 0
    if minHp <= 0 then
        if runtime.pullHpRest then
            runtime.pullHpRest = false
            if isSitting() or isDucking() then mq.cmd('/stand') end
        end
        return false
    end

    local myHp = pctHP(mq.TLO.Me.ID())
    local inCombatOrXtar = isCombat() or runtime.anyXtarAlive(true)
    if not inCombatOrXtar then
        pcall(function()
            if mq.TLO.Me.Combat() or mq.TLO.Me.AutoFire() then inCombatOrXtar = true end
            if mq.TLO.Me.CombatState() == 'COMBAT' then inCombatOrXtar = true end
            local hCount = mq.TLO.Me.XTHaterCount() or 0
            if hCount > 0 then inCombatOrXtar = true end
            local aCount = mq.TLO.Me.XTAggroCount() or 0
            if aCount > 0 then inCombatOrXtar = true end
        end)
    end

    if not runtime.pullHpRest then
        if not inCombatOrXtar and myHp < minHp then
            runtime.pullHpRest = true
            stopMoving()
            if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
            if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
            pursuit.wanderLoc = nil
            if runtime.pullState == 'TO_MOB' then
                runtime.pullState = 'IDLE'
                runtime.pullTargetId = 0
            end
            local t = mq.TLO.Target
            if t() and not isXTargetId(t.ID()) then
                clearTarget()
            end
            print(string.format('\ay[Triune]\ax Puller: HP below %d%% (%d%%) -- resting out of combat until 100%% HP.', minHp, myHp))
            if not isSitting() and not isDucking() and not isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not isMoveActive() then
                mq.cmd('/sit')
            end
            return true
        end
    else
        if inCombatOrXtar then
            -- Attacked while resting: stand up and let combat loop handle defense
            if isSitting() or isDucking() then mq.cmd('/stand') end
            return false
        else
            if myHp >= 100 then
                runtime.pullHpRest = false
                if isSitting() or isDucking() then mq.cmd('/stand') end
                print('\ag[Triune]\ax Puller: HP fully recovered (100%) -- resuming pulling.')
                return false
            else
                -- Still resting
                stopMoving()
                if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
                if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
                pursuit.wanderLoc = nil
                local t = mq.TLO.Target
                if t() and not isXTargetId(t.ID()) then
                    clearTarget()
                end
                if not isSitting() and not isDucking() and not isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not isMoveActive() then
                    mq.cmd('/sit')
                end
                return true
            end
        end
    end

    return false
end

-- Puller: IDLE (find a mob) -> TO_MOB (close in, tag it) -> TO_CAMP (drag it home)
-- -> FIGHTING (normal combat loop takes over via the target already being set).
function runtime.pullerTick()
    if runtime.combatHold() then
        stopMoving()
        return
    end

    local hasWps = (ctrl.waypoints and #ctrl.waypoints > 0)

    if not ctrl.camp_loc then
        -- Auto-initialize camp location if not yet set so puller has a return anchor
        local myX, myY, myZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
        if hasWps then
            local wp1 = ctrl.waypoints[1]
            ctrl.camp_loc = { x = wp1.x or myX or 0, y = wp1.y or myY or 0, z = wp1.z or myZ or 0 }
            print(string.format(
                '\ag[Triune]\ax Puller (Camp): Initialized camp location to Waypoint 1 (Y:%.1f, X:%.1f, Z:%.1f)',
                ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z))
        elseif myX and myY and myZ then
            ctrl.camp_loc = { x = myX, y = myY, z = myZ }
            print(string.format(
                '\ag[Triune]\ax Puller (Camp): Initialized camp location to current position (Y:%.1f, X:%.1f, Z:%.1f)',
                myY, myX, myZ))
        else
            return
        end
    end

    if runtime.pullState == 'IDLE' then
        if runtime.combatHold() then
            stopMoving()
            return
        end

        local maxCampZ = ctrl.camp_z or 75
        local addId = firstNPCXtarget(false, maxCampZ)
        if addId and runtime.setTarget(addId) then
            runtime.pullTargetId = addId
            runtime.pullState = 'FIGHTING'
            return
        end
        if mq.TLO.Me.Combat() then return end -- already fighting something; don't pull yet

        -- If current target is right next to camp (within 25 units), fight it directly
        local pt = mq.TLO.Target
        if pt() and (pt.Type() == 'NPC' or pt.Type() == 'Pet') and not pt.Dead() and pt.Type() ~= 'Corpse'
            and not isSpawnPetOrPlayer(pt.ID()) and isHostileTarget(pt.ID()) and distToId(pt.ID()) <= 25
            and not isUnreachable(pt.ID()) and not isIgnored(pt.CleanName()) then
            runtime.pullTargetId = pt.ID()
            runtime.pullState = 'FIGHTING'
            return
        end

        if runtime.checkPullHpRest() then return end

        -- Let plugins (e.g. Auto AA purchases) use the gap between pulls
        if runtime.pluginManager and not mq.TLO.Me.Combat() and not (runtime.anyXtarAlive and runtime.anyXtarAlive(true)) and not isCasting() then
            if runtime.pluginManager.onBetweenPulls() then
                stopMoving()
                return
            end
        end

        local scanRadius = hasWps and (ctrl.use_waypoints ~= false) and (ctrl.waypoint_scan_radius or 100) or
        (ctrl.camp_radius or 100)
        local id = runtime.findRoamTarget(scanRadius, maxCampZ, ctrl.pull_min_level, ctrl.pull_max_level)
        if id and runtime.setTarget(id) then
            if not runtime.verifyTargetCon(id, true) then
                print(string.format(
                    '\ay[Triune]\ax Puller: target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                    id, tostring(mq.TLO.Target.CleanName())))
                clearTarget()
                runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
                return
            end
            stopMoving()
            runtime.pullTargetId = id; runtime.pullState = 'TO_MOB'
            pursuit.hasRetargeted = false
            pursuit.retargetCount = 0
            pursuit.cycleTargetIds = { [id] = true }
        elseif hasWps and (ctrl.use_waypoints ~= false) then
            runtime.wpTick()
        end
        return
    end

    -- If another mob attacks while heading out to pull (TO_MOB state), switch to incoming aggro immediately and pull back
    if runtime.pullState == 'TO_MOB' then
        local maxCampZ = ctrl.camp_z or 75
        local aggroId = firstNPCXtarget(false, maxCampZ)
        if aggroId and aggroId ~= runtime.pullTargetId and (distToId(runtime.pullTargetId) > 35 and not mq.TLO.Me.Combat()) then
            stopMoving()
            if runtime.setTarget(aggroId) then
                print(string.format(
                    '\ay[Triune]\ax Puller aggro on path to mob -- switching to XTarget #%d (%s) and pulling back',
                    aggroId, tostring(mq.TLO.Target.CleanName())))
                runtime.pullTargetId = aggroId
                runtime.pullState = 'TO_CAMP'
            end
        elseif not mq.TLO.Me.Combat() and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
            local closerId, candDist, curDist = runtime.checkCloserTarget(runtime.pullTargetId, ctrl.camp_radius, maxCampZ,
                ctrl.pull_min_level, ctrl.pull_max_level)
            if closerId and runtime.setTarget(closerId) then
                stopMoving()
                local prevId = runtime.pullTargetId
                pursuit.id = 0
                pursuit.lastNavTargetId = 0
                pursuit.hasRetargeted = true
                pursuit.retargetCount = (pursuit.retargetCount or 0) + 1
                if not pursuit.cycleTargetIds then pursuit.cycleTargetIds = {} end
                if prevId > 0 then pursuit.cycleTargetIds[prevId] = true end
                pursuit.cycleTargetIds[closerId] = true
                print(string.format(
                    '\ay[Triune]\ax Puller: Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f, switch %d/%d]',
                    closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist,
                    pursuit.retargetCount, ctrl.max_closer_retargets or 1))
                runtime.pullTargetId = closerId
            end
        end
    end

    local s = mq.TLO.Spawn(runtime.pullTargetId)
    local alive = s() and s.Type() == 'NPC' and not s.Dead() and s.Type() ~= 'Corpse'
    if not alive then
        local maxCampZ = ctrl.camp_z or 75
        local addId = firstNPCXtarget(false, maxCampZ)
        if addId and runtime.setTarget(addId) then
            runtime.pullTargetId = addId
            runtime.pullState = 'FIGHTING'
        else
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving(); return
        end
    end

    if runtime.pullState == 'TO_MOB' then
        if not isXTargetId(runtime.pullTargetId) and not runtime.verifyTargetCon(runtime.pullTargetId) then
            print(string.format(
                '\ay[Triune]\ax Puller: target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                runtime.pullTargetId, tostring(mq.TLO.Target.CleanName())))
            clearTarget()
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving()
        elseif isUnreachable(runtime.pullTargetId) then
            print('\ay[Triune]\ax pull target unreachable -- picking a different mob.')
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving()
            clearTarget()
        else
            local pullStyle = ctrl.pull_style or 'Melee'
            local reqRange
            if pullStyle == 'Melee' then
                reqRange = desiredRange(runtime.pullTargetId)
            elseif pullStyle == 'Ranged' then
                reqRange = ctrl.pull_stand_back and (ctrl.pull_engage_dist or 100) or 40
            else
                reqRange = ctrl.pull_engage_dist or 100
            end

            local tid = runtime.pullTargetId
            runtime.recordBreadcrumb()
            local arrived = runtime.moveToward(tid, reqRange)
            local inRange = arrived or
                (pullStyle == 'Ranged' and distToId(tid) <= (ctrl.pull_engage_dist or 100) and hasLoS(tid))

            if inRange then
                local tagged = false

                if pullStyle == 'Melee' then
                    if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                    tagged = true
                elseif pullStyle == 'Ranged' then
                    mq.cmd('/face fast')
                    if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
                    if isXTargetId(tid) or distToId(tid) <= 25 then
                        if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
                        tagged = true
                    end
                elseif pullStyle == 'Pet' then
                    mq.cmd('/face fast')
                    local petId = mq.TLO.Me.Pet.ID() or 0
                    petState.petHoldActive = false
                    if petId > 0 and isSpawnAlive(petId) then
                        mq.cmd('/pet attack')
                    end
                    if hasActivePet() then
                        mq.cmd('/say #petcmd attack all')
                    end
                    local petTgtId = 0
                    pcall(function() petTgtId = mq.TLO.Pet.Target.ID() or 0 end)
                    if isXTargetId(tid) or distToId(tid) <= 35 or (petTgtId > 0 and petTgtId == tid) then
                        tagged = true
                    end
                elseif pullStyle == 'Spell' then
                    stopMoving()
                    mq.cmd('/face fast')
                    if isXTargetId(tid) or distToId(tid) <= 30 then
                        tagged = true
                    else
                        local slotToCast = ctrl.pull_spell_gem or 1
                        local g = nil
                        if loadout.gems then
                            for _, eg in ipairs(loadout.gems) do
                                if eg and (tonumber(eg.gem) or 1) == slotToCast then
                                    g = eg
                                    break
                                end
                            end
                        end
                        local spellName = ctrl.pull_spell
                        if not spellName or spellName == '' then
                            pcall(function() spellName = mq.TLO.Me.Gem(slotToCast).Name() end)
                        end
                        if not spellName or spellName == '' then
                            spellName = runtime.getPrimarySpellForGem(slotToCast)
                        end

                        if spellName and spellName ~= '' then
                            local dummyEntry = g or { spell = spellName, target = 'E: Current Target', cls = 'ALL' }
                            runtime.castGem(slotToCast, dummyEntry, tid)
                        else
                            if loadout.gems then
                                for i = 1, #loadout.gems do
                                    local lg = loadout.gems[i]
                                    local lpct = lg and tonumber(lg.pct)
                                    if lpct == nil then lpct = 100 end
                                    if lg and lg.spell and lg.spell ~= '' and lpct > 0 then
                                        local isDet = runtime.isDetrimentalAction(lg.spell, lg.target, lg)
                                        local actualSlot = tonumber(lg.gem) or i
                                        if isDet and runtime.castGem(actualSlot, lg, tid) then break end
                                    end
                                end
                            end
                        end
                    end
                end

                if tagged then
                    runtime.pullState = 'TO_CAMP'
                end
            end
        end
    elseif runtime.pullState == 'TO_CAMP' then
        local c = ctrl.camp_loc
        local bc = runtime.pullBreadcrumbs
        if ctrl.nav_reverse_breadcrumbs and bc and #bc > 0 then
            local nextWp = bc[#bc]
            local d = distToLoc(nextWp.x, nextWp.y, nextWp.z)
            if d <= 12 then
                table.remove(bc, #bc)
                if #bc == 0 and c then
                    runtime.moveTowardLoc(c.x, c.y, c.z, 15)
                end
            else
                runtime.moveTowardLoc(nextWp.x, nextWp.y, nextWp.z, 10)
            end
        else
            if c and runtime.moveTowardLoc(c.x, c.y, c.z, 15) then runtime.pullState = 'FIGHTING' end
        end
        if c and distToLoc(c.x, c.y, c.z) <= (ctrl.camp_radius or 15) then
            runtime.clearBreadcrumbs()
            runtime.pullState = 'FIGHTING'
        end
    elseif runtime.pullState == 'FIGHTING' then
        runtime.clearBreadcrumbs()
        if ctrl.mode == 'Puller' and not mq.TLO.Me.Combat() then
            mq.cmd('/attack on')
        end
    end
end

function runtime.playerHasAggro(targetId)
    if not targetId or targetId == 0 then return false end
    local myId = mq.TLO.Me.ID() or 0
    if myId == 0 then return false end

    local t = mq.TLO.Target
    if t() and t.ID() == targetId then
        local totId = 0
        pcall(function() totId = t.TargetOfTarget.ID() or 0 end)
        if totId == myId then return true end

        local ahId = 0
        pcall(function() ahId = t.AggroHolder.ID() or 0 end)
        if ahId == myId then return true end

        local pct = 0
        pcall(function() pct = t.PctAggro() or mq.TLO.Me.PctAggro() or 0 end)
        if pct >= 100 then return true end
    else
        local s = mq.TLO.Spawn(targetId)
        if s() then
            local totId = 0
            pcall(function() totId = s.TargetOfTarget.ID() or 0 end)
            if totId == myId then return true end

            local ahId = 0
            pcall(function() ahId = s.AggroHolder.ID() or 0 end) ---@diagnostic disable-line: undefined-field
            if ahId == myId then return true end
        end
    end

    if mq.TLO.Me.Combat() and t() and t.ID() == targetId and (t.Distance3D() or 999) <= 25 then
        local pct = 0
        pcall(function() pct = t.PctAggro() or mq.TLO.Me.PctAggro() or 0 end)
        if pct > 0 then return true end
        if (t.PctHPs() or 100) < 100 then return true end
    end

    return false
end

-- Returns true once the player has demonstrably started attacking this target:
--   Melee  -> /attack is on (auto-attack swinging)
--   Ranged -> /autofire is on (e.g. bow pull)
function runtime.playerIsEngagingTarget(tid)
    if mq.TLO.Me.Combat() then return true end
    if mq.TLO.Me.AutoFire() then return true end
    return false
end

function runtime.checkAggroSwitch()
    if isCastingOrStarting() or getActiveTargetRequiredCastingId() then return false end
    if (os.clock() - (runtime.lastAggroSwitchAt or 0)) < 2.0 then return false end
    local cur = mq.TLO.Target
    local curId = (cur() and cur.Type() == 'NPC') and cur.ID() or 0
    local curDist = (curId > 0) and (cur.Distance3D() or 999) or 999
    local bestId, bestDist = 0, 999
    local bestIsHittingMe = false
    local curIsHittingMe = false
    local myId = mq.TLO.Me.ID() or 0

    if curId > 0 and cur() then
        pcall(function()
            if cur.TargetOfTarget.ID() == myId or cur.AggroHolder.ID() == myId or (cur.PctAggro() or 0) >= 100 then
                curIsHittingMe = true
            end
        end)
    end

    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.ID() ~= curId and (xt.Type() == 'NPC' or xt.Type() == 'Pet') and not isUnreachable(xt.ID())
            and not isGroupOrRaidMember(xt.ID()) and not isSpawnPetOrPlayer(xt.ID()) and isHostileTarget(xt.ID())
            and not isIgnored(xt.CleanName()) then
            local d = xt.Distance3D() or 999
            local isHittingMe = false
            pcall(function()
                if xt.TargetOfTarget.ID() == myId or xt.AggroHolder.ID() == myId or (xt.PctAggro() or 0) >= 100 then ---@diagnostic disable-line: undefined-field
                    isHittingMe = true
                end
            end)
            local isHunterMode = (ctrl.mode == 'Manual' or (ctrl.mode == 'Puller' and ctrl.submode == 'Hunt') or ctrl.mode == 'Assist')
            local maxNav = (ctrl and ctrl.xtar_nav_dist) or 150
            local maxRange = isHittingMe and 999 or (isHunterMode and maxNav or 40)
            if d < maxRange and d < bestDist then
                bestDist = d
                bestId = xt.ID()
                bestIsHittingMe = isHittingMe
            end
        end
    end
    if bestId == 0 then return false end
    -- Only switch when a new mob is hitting us while current target is not,
    -- or when current target is missing/dead, or when another mob is significantly closer (>15 units closer).
    if (bestIsHittingMe and not curIsHittingMe) or curId == 0 or (curDist > 25 and bestDist < (curDist - 15)) then
        if runtime.setTarget(bestId) then
            runtime.lastAggroSwitchAt = os.clock()
            stopMoving()
            pursuit.id = 0
            pursuit.lastNavTargetId = 0
            mq.cmd('/face fast')
            print('\ay[Triune]\ax aggro switch -> ' .. tostring(mq.TLO.Target.CleanName()))
            return true
        end
    end
    return false
end

runtime.fullStop = function()
    stopMoving()
    if not ctrl.running and mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    if not ctrl.running and mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
    if isCasting() then
        mq.cmd('/stopsong')
        mq.cmd('/stopcast')
    end
    if ctrl.mode == 'Manual' or not ctrl.running then
        setManualHunterPetHold(true, true)
    else
        setManualHunterPetHold(false)
    end
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.wanderLoc = nil
    pursuit.hasRetargeted = false
    pursuit.retargetCount = 0
    pursuit.cycleTargetIds = {}
    runtime.pullState = 'IDLE'
    runtime.pullTargetId = 0
    if runtime.clearDetour then runtime.clearDetour() end
    runtime.clearBreadcrumbs()
    if runtime.pullHpRest then
        runtime.pullHpRest = false
        if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
    end
    if runtime.medBreakActive then
        runtime.medBreakActive = false; if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
    end
    stuckState.counter = 0
    stuckState.attempts = 0
    stuckState.cannotSeeAttempts = 0
end

runtime.onZoned = function()
    local now = os.clock()
    if (now - (runtime.lastZonedAt or 0)) < 2.0 then return end
    runtime.lastZonedAt = now
    if ctrl.pause_on_zone ~= false and ctrl.running then
        ctrl.running = false
        if runtime.fullStop then runtime.fullStop() end
        print('\ay[Triune]\ax zoned -- pausing autocombat.')
    elseif ctrl.running then
        if runtime.fullStop then runtime.fullStop() end
        print('\ag[Triune]\ax zoned -- continuing autocombat (pause on zone disabled).')
    end
    if castTracker and castTracker.clear then
        castTracker.clear()
    end
    runtime.npcSpellApplied = {}
    runtime.npcSpellLastCast = {}
    pursuit.unreachableIds = {}
    pursuit.id = 0
    pursuit.wanderLoc = nil
    pursuit.hasRetargeted = false
    pursuit.retargetCount = 0
    pursuit.cycleTargetIds = {}
    runtime.pullState = 'IDLE'
    runtime.pullTargetId = 0
    runtime.pullHpRest = false
    runtime.activeDetour = nil
    runtime.clearBreadcrumbs()
    runtime.discExpires = {}
    runtime.discCooldown = {}
    petState.myPets = {}
    petState.summonPending = nil
    petState.summonBlockedUntil = {}
    petState.petsCache = nil
    petState.petHoldActive = false
    petState.manualHunterHold = nil
    petState.lastObservedId = 0
    petState.lastCmdTargetId = 0
    petState.lastCmdAt = 0
    petState.holdIssuedForId = 0
    if ctrl.camp_loc then
        print('\ay[Triune]\ax zoned -- clearing camp (it was set in the previous zone). Set a new one if needed.')
        ctrl.camp_loc = nil
    end
    if ctrl.hunter_combat_loc then
        print('\ay[Triune]\ax zoned -- clearing Hunter combat anchor (it was set in the previous zone).')
        ctrl.hunter_combat_loc = nil
    end
    if runtime.loadZoneWaypoints() then
        print(string.format('\ag[Triune]\ax Loaded saved waypoint route for %s (%d waypoint(s)).',
            runtime.getZoneDisplayName(runtime.getCurrentZoneShortName()), #(ctrl.waypoints or {})))
    end
    if ctrl.fov_enabled and runtime.applyFov then
        runtime.applyFov()
        runtime.pendingFovAt = os.clock() + 1.5
    end
end

-- Bind remaining engine helpers to runtime table
runtime.pctHP = pctHP
runtime.isCombat = isCombat
runtime.hasActualNPCXtarget = hasActualNPCXtarget
runtime.isXTargetId = isXTargetId
runtime.isGroupOrRaidMember = isGroupOrRaidMember
runtime.isAnyPet = isAnyPet
runtime.isSpawnPetOrPlayer = isSpawnPetOrPlayer
runtime.isHostileTarget = isHostileTarget
runtime.firstNPCXtarget = firstNPCXtarget
runtime.findFirstNPCXtarget = findFirstNPCXtarget
runtime.stopMoving = stopMoving
runtime.distToId = distToId
runtime.distToLoc = distToLoc
runtime.hasLoS = hasLoS
runtime.isMoveActive = isMoveActive
runtime.navLoaded = navLoaded
runtime.navMeshLoaded = navMeshLoaded
runtime.stickLoaded = stickLoaded
runtime.hasActivePet = hasActivePet
runtime.trioHasPetClass = trioHasPetClass
runtime.setManualHunterPetHold = setManualHunterPetHold
runtime.checkGemMemSync = checkGemMemSync
runtime.baseTok = baseTok
runtime.sungKey = sungKey
runtime.isSpecialSkill = isSpecialSkill
runtime.isActionSkill = isActionSkill
runtime.isAutoskillEligible = isAutoskillEligible
runtime.isFeignDeathAbility = isFeignDeathAbility
runtime.CLASS_ACTIONS = CLASS_ACTIONS
runtime.defaultActionEntry = defaultActionEntry
runtime.hasActionSkill = hasActionSkill
runtime.actionClassInfo = actionClassInfo
runtime.getClientAbilities = getClientAbilities
runtime.clearCursor = clearCursor
runtime.isIgnored = isIgnored
runtime.isUnreachable = isUnreachable

function runtime.hasDowntimeAggroThreat()
    if mq.TLO.Me.Combat() then return true end
    local cs = nil
    pcall(function() cs = mq.TLO.Me.CombatState() end)
    if cs == 'COMBAT' then return true end
    if (mq.TLO.Me.XTHaterCount() or 0) > 0 then return true end
    if (mq.TLO.Me.XTAggroCount() or 0) > 0 then return true end
    if runtime.anyXtarAlive and runtime.anyXtarAlive(true) then return true end
    if runtime.countNPCXtarget and runtime.countNPCXtarget() > 0 then return true end
    local isAggroed = false
    pcall(function()
        local t = mq.TLO.Target
        if t() and (t.ID() or 0) > 0 and not t.Dead() and t.Type() == 'NPC' then
            if (t.PctAggro() or 0) > 0 or (t.SecondaryPctAggro() or 0) > 0 then
                isAggroed = true
            end
        end
    end)
    if isAggroed then return true end
    return false
end

function runtime.processDowntimeBuffing()
    if not ctrl.running then return end
    if runtime.hasDowntimeAggroThreat() then return end
    if isCasting() or isCastingOrStarting() or isMoveActive() then return end
    if runtime.medBreakActive then return end
    if mq.TLO.Window('SpellBookWnd').Open() then
        mq.cmd('/notify SpellBookWnd SBW_DoneButton leftmouseup')
        mq.delay(100)
    end

    local now = os.clock()
    runtime.lastDowntimeSwapAt = runtime.lastDowntimeSwapAt or {}

    local candidate = nil
    local candidateTargetId = 0
    local targetGem = 0

    -- Only search for missing buffs to swap to if downtime_buffing is enabled
    if ctrl.downtime_buffing ~= false then
        -- 1. Check if we had an interrupted swap to resume
        local resume = runtime.interruptedSwap
        if resume and resume.targetId and isSpawnAlive(resume.targetId) and resume.entry then
            local g = resume.entry
            local pctVal = tonumber(g.pct) or 100
            if pctVal > 0 and runtime.conditionMet(g.when, pctVal, g.spell, resume.targetId, g.cls, g.target, g) then
                candidate = g
                candidateTargetId = resume.targetId
                targetGem = tonumber(resume.slot) or (tonumber(g.gem) or 1)
            end
        end
        if not candidate then
            runtime.interruptedSwap = nil
        end

        -- 2. Scan for missing buffs among all configured spells
        if not candidate and loadout.gems then
            for i = 1, #loadout.gems do
                local g = loadout.gems[i]
                if g and g.spell and g.spell ~= '' and (g.when == 'missing buff' or g.when == 'always') then
                    local pctVal = tonumber(g.pct) or 100
                    if pctVal > 0 and (not g.burn_only or ctrl.burn) then
                        local targetGemSlot = tonumber(g.gem) or math.min(i, 12)
                        local targetId = runtime.resolveTargetId(g.target, g.cls, g.when, g.spell, pctVal)
                        if targetId and targetId > 0 and runtime.conditionMet(g.when, pctVal, g.spell, targetId, g.cls, g.target, g) then
                            local lockedOut = castTracker and castTracker.isLockedOut(g.spell, targetId, g.kind)
                            local hasReagents = hasSpellReagents(g.spell)
                            local lastSwapped = runtime.lastDowntimeSwapAt[g.spell] or 0
                            if not lockedOut and hasReagents and (now - lastSwapped) >= 15.0 then
                                candidate = g
                                candidateTargetId = targetId
                                targetGem = targetGemSlot
                                break
                            end
                        end
                    end
                end
            end
        end

        -- 3. If a candidate buff was found, ensure it is memorized and cast
        if candidate then
            local curSlot = nil
            if isGemMatching(targetGem, candidate.spell) then
                curSlot = targetGem
            else
                local s = nil
                pcall(function() s = mq.TLO.Me.Gem(candidate.spell)() end)
                if s and s > 0 then curSlot = s end
            end

            if curSlot then
                -- Spell is already on the bar! Cast if ready
                local rdy = false
                pcall(function() rdy = mq.TLO.Me.SpellReady(curSlot)() end)
                if rdy then
                    runtime.castGem(curSlot, candidate, candidateTargetId)
                end
                return
            end

            -- Needs to be swapped into targetGem
            if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
            runtime.clearCursor()

            runtime.isSwitchingSpells = true
            runtime.switchingSlot = targetGem
            runtime.switchingSpellName = candidate.spell
            runtime.interruptedSwap = nil

            print(string.format('\ay[Triune]\ax Downtime swap: memorizing "%s" into Gem %d for missing buff...', candidate.spell, targetGem))
            local memSuccess = runtime.tryMem(targetGem, candidate.spell)

            if not memSuccess then
                if runtime.hasDowntimeAggroThreat() then
                    runtime.interruptedSwap = { slot = targetGem, spell = candidate.spell, targetId = candidateTargetId, entry = candidate }
                    print(string.format('\ar[Triune]\ax Aggro threat detected while swapping to "%s"! Aborting swap to engage combat.', candidate.spell))
                else
                    print(string.format('\ar[Triune]\ax Failed to memorize "%s" into Gem %d during downtime swap.', candidate.spell, targetGem))
                end
                runtime.isSwitchingSpells = false
                runtime.switchingSlot = 0
                runtime.switchingSpellName = nil
                if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book 0') end
                return
            end

            -- Spell is now memorized; wait for recharge / ready cooldown
            local rdyStartTime = os.clock()
            while (os.clock() - rdyStartTime) < 6.0 do
                local rdy = false
                pcall(function() rdy = mq.TLO.Me.SpellReady(targetGem)() end)
                if rdy then break end
                mq.delay(100)
                if runtime.hasDowntimeAggroThreat() then
                    runtime.isSwitchingSpells = false
                    runtime.switchingSlot = 0
                    runtime.switchingSpellName = nil
                    if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book 0') end
                    if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                    runtime.interruptedSwap = { slot = targetGem, spell = candidate.spell, targetId = candidateTargetId, entry = candidate }
                    print(string.format('\ar[Triune]\ax Aggro threat detected while waiting for "%s" to ready! Aborting to engage combat.', candidate.spell))
                    return
                end
            end

            runtime.isSwitchingSpells = false
            runtime.switchingSlot = 0
            runtime.switchingSpellName = nil
            runtime.lastDowntimeSwapAt[candidate.spell] = os.clock()

            -- Cast the buff
            runtime.castGem(targetGem, candidate, candidateTargetId)
            return
        end
    end

    -- 4. No candidate buffs needed -- restore priority spells for any gem whose priority spell is not currently memmed and lower-priority spells are not needed
    local maxG = getNumGems()
    for slot = 1, maxG do
        local primarySpell = runtime.getPrimarySpellForGem(slot)
        if primarySpell and primarySpell ~= '' and not isGemMatching(slot, primarySpell) then
            -- Verify if any lower-priority spell on this gem is currently needed
            local lowerNeeded = false
            if ctrl.downtime_buffing ~= false and loadout.gems then
                for _, g in ipairs(loadout.gems) do
                    if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' and not isGemMatching(primarySpell, g.spell) then
                        local pctVal = tonumber(g.pct) or 100
                        if pctVal > 0 and (not g.burn_only or ctrl.burn) and (g.when == 'missing buff' or g.when == 'always') then
                            local targetId = runtime.resolveTargetId(g.target, g.cls, g.when, g.spell, pctVal)
                            if targetId and targetId > 0 and runtime.conditionMet(g.when, pctVal, g.spell, targetId, g.cls, g.target, g) then
                                local lockedOut = castTracker and castTracker.isLockedOut(g.spell, targetId, g.kind)
                                local hasReagents = hasSpellReagents(g.spell)
                                if not lockedOut and hasReagents then
                                    lowerNeeded = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if not lowerNeeded then
                -- Standing check
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                runtime.clearCursor()

                runtime.isSwitchingSpells = true
                runtime.switchingSlot = slot
                runtime.switchingSpellName = primarySpell

                print(string.format('\ag[Triune]\ax Restoring priority spell "%s" into Gem %d (not in combat)...', primarySpell, slot))
                local memSuccess = runtime.tryMem(slot, primarySpell)

                if not memSuccess then
                    if runtime.hasDowntimeAggroThreat() then
                        print(string.format('\ar[Triune]\ax Aggro threat detected while restoring priority spell "%s"! Aborting to engage combat.', primarySpell))
                    else
                        print(string.format('\ar[Triune]\ax Failed to restore priority spell "%s" into Gem %d during downtime swap.', primarySpell, slot))
                    end
                    runtime.isSwitchingSpells = false
                    runtime.switchingSlot = 0
                    runtime.switchingSpellName = nil
                    if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book 0') end
                    return
                end

                -- Wait for recharge cooldown on restored combat spell
                local rdyStartTime = os.clock()
                while (os.clock() - rdyStartTime) < 6.0 do
                    local rdy = false
                    pcall(function() rdy = mq.TLO.Me.SpellReady(slot)() end)
                    if rdy then break end
                    mq.delay(100)
                    if runtime.hasDowntimeAggroThreat() then break end
                end

                runtime.isSwitchingSpells = false
                runtime.switchingSlot = 0
                runtime.switchingSpellName = nil
                if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book 0') end
                return
            end
        end
    end
end

-- Manual mode movement policy. combatTick asks this whether to drive
-- nav/stick toward the current hostile target:
--   'move' -- close to / stick to it (moveToward)
--   'hold' -- fight from wherever the player left the character; never move
--   'wait' -- target is merely selected; do nothing until it engages
-- `engaged` means the target is on XTarget or we are already in combat.
-- `approaching` means an auto-nav approach to this target is still in flight
-- (pursuit.id still points at it), which is allowed to finish even with stick
-- off so a selected target is actually reached before we plant our feet.
local function manualMovePolicy(engaged, approaching)
    if engaged then
        if ctrl.manual_stick ~= false then return 'move' end
        if ctrl.manual_auto_nav and approaching then return 'move' end
        return 'hold'
    end
    return ctrl.manual_auto_nav and 'move' or 'wait'
end

local function combatTick()
    local fullStop = runtime.fullStop
    local anyXtarAlive = runtime.anyXtarAlive
    local countNPCXtarget = runtime.countNPCXtarget
    local playerHasAggro = runtime.playerHasAggro
    local playerIsEngagingTarget = runtime.playerIsEngagingTarget
    local checkStuck = runtime.checkStuck
    local checkCombatStall = runtime.checkCombatStall
    local checkAggroSwitch = runtime.checkAggroSwitch
    local pullerTick = runtime.pullerTick
    local findRoamTarget = runtime.findRoamTarget
    local checkCloserTarget = runtime.checkCloserTarget
    local chaseMA = runtime.chaseMA
    local idleReturn = runtime.idleReturn
    local maTargetId = runtime.maTargetId
    local resolveTargetId = runtime.resolveTargetId
    local castGem = runtime.castGem
    local fireAA = runtime.fireAA
    local fireDisc = runtime.fireDisc
    local fireSkill = runtime.fireSkill
    local isDiscReady = runtime.isDiscReady
    local isSkillReady = runtime.isSkillReady
    local isDetrimentalAction = runtime.isDetrimentalAction
    local isTargetInRange = runtime.isTargetInRange
    local conditionMet = runtime.conditionMet
    local markUnreachable = runtime.markUnreachable
    local moveToward = runtime.moveToward
    local moveTowardLoc = runtime.moveTowardLoc
    local setTarget = runtime.setTarget
    local checkPullHpRest = runtime.checkPullHpRest
    local targetIsEngaged = runtime.targetIsEngaged

    if not ctrl.running then return end
    if mq.TLO.Me.Dead() then
        if not runtime.deathGuardFired then
            runtime.deathGuardFired = true
            fullStop()
            runtime.sungBuffs = {}
            runtime.npcCastCounts = {}
            runtime.npcSpellApplied = {}
            runtime.npcSpellLastCast = {}
            runtime.discExpires = {}
            runtime.discCooldown = {}
            petState.myPets = {}; petState.lastObservedId = 0; petState.summonPending = nil; petState.petsCache = nil
            print('\ar[Triune]\ax character is dead -- paused. Will resume automatically once alive again.')
        end
        return
    end
    local isFeigning = false
    pcall(function() isFeigning = mq.TLO.Me.Feigning() or false end)
    if isFeigning then
        -- Character is feigning death: pause combat loop to remain safely feigned
        return
    end
    if runtime.npcCastCounts and next(runtime.npcCastCounts) ~= nil then
        if (os.clock() - (runtime.lastNpcCastPruneAt or 0)) > 5.0 then
            runtime.lastNpcCastPruneAt = os.clock()
            for tid in pairs(runtime.npcCastCounts) do
                if not isSpawnAlive(tid) then
                    runtime.npcCastCounts[tid] = nil
                    if runtime.npcSpellApplied then runtime.npcSpellApplied[tid] = nil end
                    if runtime.npcSpellLastCast then runtime.npcSpellLastCast[tid] = nil end
                end
            end
        end
    end

    if not ctrl.medbreak_enabled then
        if runtime.medBreakActive then
            runtime.medBreakActive = false
            if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
        end
    else
        local myHp = pctHP(mq.TLO.Me.ID())
        local myMana = mq.TLO.Me.PctMana() or 100
        local maxMana = mq.TLO.Me.MaxMana() or 0
        local myEnd = mq.TLO.Me.PctEndurance() or 100
        local maxEnd = mq.TLO.Me.MaxEndurance() or 0

        -- Strictly verify we are not in combat and have NO hostile NPCs on XTarget
        local inCombatOrXtar = isCombat() or anyXtarAlive(true)
        if not inCombatOrXtar then
            pcall(function()
                if mq.TLO.Me.Combat() or mq.TLO.Me.AutoFire() then inCombatOrXtar = true end
                if mq.TLO.Me.CombatState() == 'COMBAT' then inCombatOrXtar = true end
                local hCount = mq.TLO.Me.XTHaterCount() or 0
                if hCount > 0 then inCombatOrXtar = true end
                local aCount = mq.TLO.Me.XTAggroCount() or 0
                if aCount > 0 then inCombatOrXtar = true end
            end)
        end

        if not runtime.medBreakActive then
            if not inCombatOrXtar then
                local needHp   = ctrl.medbreak_hp_on and myHp <= (ctrl.medbreak_hp_start or 20)
                local needMana = ctrl.medbreak_mana_on and maxMana > 0 and myMana <= (ctrl.medbreak_mana_start or 20)
                local needEnd  = ctrl.medbreak_end_on and maxEnd > 0 and myEnd <= (ctrl.medbreak_end_start or 20)

                if needHp or needMana or needEnd then
                    fullStop()
                    runtime.medBreakActive = true
                    print('\ay[Triune]\ax Med Break -- resting to recover.')
                    if not mq.TLO.Me.Sitting() and not mq.TLO.Me.Ducking() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not isMoveActive() then
                        mq.cmd('/sit')
                    end
                end
            end
        else
            if inCombatOrXtar then
                runtime.medBreakActive = false
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                print('\ay[Triune]\ax Med Break cancelled -- combat / hostile on XTarget!')
            else
                local hpOk   = not ctrl.medbreak_hp_on or myHp >= (ctrl.medbreak_hp_stop or 90)
                local manaOk = not ctrl.medbreak_mana_on or maxMana == 0 or myMana >= (ctrl.medbreak_mana_stop or 90)
                local endOk  = not ctrl.medbreak_end_on or maxEnd == 0 or myEnd >= (ctrl.medbreak_end_stop or 90)

                if hpOk and manaOk and endOk then
                    runtime.medBreakActive = false
                    if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                    print('\ag[Triune]\ax Med Break over -- resuming.')
                end
            end
        end
    end
    if runtime.medBreakActive then
        if not mq.TLO.Me.Sitting() and not mq.TLO.Me.Ducking() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not isMoveActive() then
            mq.cmd('/sit')
        end
        return
    end

    updatePetTracking()

    local isCastingNow = isCastingOrStarting()

    if isCastingNow then
        castTracker.wasCasting = true
        local reqTargetId = getActiveTargetRequiredCastingId()
        if reqTargetId and reqTargetId > 0 and isSpawnAlive(reqTargetId) then
            if mq.TLO.Target.ID() ~= reqTargetId then
                mq.cmdf('/target id %d', reqTargetId)
            end
        end
        local isBrd = false
        pcall(function() isBrd = (mq.TLO.Me.Class.ShortName() == 'BRD') end)
        if castTracker.activeKind ~= 'Brd' and not isBrd then
            if navLoaded() then
                local navActive = false
                pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
                if navActive then pcall(function() mq.cmd('/nav stop') end) end
            end
            if stickLoaded() then
                pcall(function()
                    if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                        mq.cmd('/stick pause')
                    end
                end)
            end
            pcall(function()
                if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving() then
                    mq.cmd('/moveto off')
                end
            end)
            local isMoving = false
            pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
            if isMoving then
                pcall(function() mq.cmd('/keypress forward') end)
                pcall(function() mq.cmd('/keypress back') end)
                pcall(function() mq.cmd('/keypress strafe_left') end)
                pcall(function() mq.cmd('/keypress strafe_right') end)
            end
        end
        mq.doevents()
        return
    elseif castTracker.wasCasting or (castTracker and castTracker.activeSpell and castTracker.failed) then
        castTracker.wasCasting = false
        if stickLoaded() then
            pcall(function()
                if mq.TLO.Stick.Status() == 'PAUSED' then mq.cmd('/stick unpause') end
            end)
        end
        if not castTracker.failed then
            castTracker.recordSuccess(castTracker.activeSpell or castTracker.lastSpell, castTracker.activeTargetId)
        end
        castTracker.activeSpell    = nil
        castTracker.activeTargetId = nil
        castTracker.activeKind     = nil
        castTracker.targetRequired = nil
        clearCursor()
        if runtime.restoreTargetId and runtime.restoreTargetId > 0 then
            local rId = runtime.restoreTargetId
            runtime.restoreTargetId = nil
            if isSpawnAlive(rId) and mq.TLO.Target.ID() ~= rId then
                runtime.setTarget(rId)
            end
        end
    end

    checkStuck()
    checkCombatStall()
    if os.time() >= (runtime.nextHazardDecayAt or 0) then
        runtime.decayZoneHazards()
        runtime.nextHazardDecayAt = os.time() + 60
    end
    checkGemMemSync()
    if (ctrl.mode == 'Manual' and ctrl.manual_auto_xtarget ~= false) or ctrl.mode == 'Puller' then
        checkAggroSwitch()
    end

    -- ========================================================================
    -- HEALING PRIORITY DISPATCH
    -- Prioritize reactive healing (spells, AAs, clickies, actions, discs)
    -- over movement, targeting, auto-attack, and offensive casting.
    -- ========================================================================
    if runtime.processHealPriority and runtime.processHealPriority() then
        return
    end

    local t = mq.TLO.Target
    local tDead = false
    local tType = ''
    local tState = ''
    pcall(function()
        if t() then
            tDead = t.Dead() or false
            tType = t.Type() or ''
            tState = t.State() or ''
        end
    end)
    local isTargetDead = t() and (tDead or tType == 'Corpse' or tState == 'DEAD')
    if isTargetDead then
        clearTarget()
    end
    local numXtar = countNPCXtarget()
    local haveNPC = t() and not isTargetDead and (tType == 'NPC' or tType == 'Pet')
        and not isSpawnPetOrPlayer(t.ID()) and isHostileTarget(t.ID())
    if haveNPC and ctrl.mode == 'Puller' then
        if isIgnored(t.CleanName()) then
            haveNPC = false
            clearTarget()
        elseif not isXTargetId(t.ID()) then
            local isPulling = (ctrl.submode == 'Camp')
            local minL = isPulling and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1)
            local maxL = isPulling and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100)
            local lvl = t.Level() or 0
            if lvl > 0 and (lvl < minL or lvl > maxL) then
                haveNPC = false
                clearTarget()
            end
        end
    elseif haveNPC and ctrl.mode == 'Manual' then
        if isIgnored(t.CleanName()) then
            haveNPC = false
        end
    end
    local engage = false
    -- Manual mode with Stick off: we are fighting from where the player put us,
    -- so the approach timeout below must not mark the target unreachable.
    local manualHold = false

    if ctrl.mode == 'Manual' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then
            haveNPC = false
            clearTarget()
        end

        local autoXtar = (ctrl.manual_auto_xtarget ~= false)
        if not haveNPC and autoXtar then
            local xtarId = firstNPCXtarget(false)
            if xtarId and isHostileTarget(xtarId) and setTarget(xtarId) then
                haveNPC = true
                stopMoving()
                pursuit.id = 0
                pursuit.lastNavTargetId = 0
                print(string.format('\ay[Triune]\ax Manual target acquired: #%d (%s)',
                    xtarId, tostring(mq.TLO.Target.CleanName())))
            end
        end

        if haveNPC then
            local id = mq.TLO.Target.ID()
            if not isHostileTarget(id) then
                haveNPC = false
            else
                local inCombatState = mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')
                local isXtar = isXTargetId(id)
                local policy = manualMovePolicy(isXtar or inCombatState, pursuit.id == id)
                if policy == 'move' then
                    if moveToward(id, desiredRange(id)) then
                        engage = true
                    end
                elseif policy == 'hold' then
                    -- Engaged but Stick is off: cancel any leftover nav/stick and
                    -- let the attack/cast logic work from the current spot.
                    manualHold = true
                    engage = true
                    if isMoveActive() then
                        stopMoving()
                        pursuit.id = 0
                        pursuit.lastNavTargetId = 0
                    end
                end
            end
        elseif ctrl.camp_loc then
            moveTowardLoc(ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, 15)
        end
    elseif ctrl.mode == 'Puller' then
        if ctrl.submode == 'Camp' then
            if runtime.combatHold() then
                stopMoving()
                return
            end
            pullerTick()
            local pt = mq.TLO.Target
            haveNPC = pt() and pt.Type() == 'NPC' and not pt.Dead() and pt.Type() ~= 'Corpse'
            if haveNPC and (isUnreachable(pt.ID()) or isIgnored(pt.CleanName())) then
                haveNPC = false
                clearTarget()
                runtime.pullState = 'IDLE'
                runtime.pullTargetId = 0
            end
            if haveNPC and runtime.pullState == 'FIGHTING' then
                local id = pt.ID()
                if moveToward(id, desiredRange(id)) then
                    engage = true
                else
                    engage = (distToId(id) <= maxMeleeDistance(id) or isXTargetId(id))
                end
            else
                engage = (runtime.pullState == 'FIGHTING')
            end
        else -- Submode 'Hunt'
            local hasWps = (ctrl.waypoints and #ctrl.waypoints > 0 and ctrl.use_waypoints ~= false)
            local maxHuntZ = ctrl.hunter_z or 75
            local myZ = mq.TLO.Me.Z() or 0
            local maxScan = hasWps and (ctrl.waypoint_scan_radius or 100) or (ctrl.hunter_radius or 1500)
            -- Normally widened to at least the scan radius so in-range XTargets aren't
            -- ignored (see: "Fix Puller (Hunt) Mode Ignoring In-Range XTarget Enemies").
            -- ignore_distant_xtargets opts out of that widening: XTargets beyond the raw
            -- chase range are skipped entirely so Puller looks for a different mob instead
            -- of trying to close a long distance.
            local maxHuntXtarDist = ctrl.ignore_distant_xtargets and (ctrl.xtar_nav_dist or 150)
                or math.max(ctrl.xtar_nav_dist or 150, maxScan)
            local maxHuntXtarZ = math.max(maxHuntZ, 75) + 25

            if haveNPC then
                local tid = mq.TLO.Target.ID() or 0
                local tspawn = mq.TLO.Spawn(tid)
                -- Add hysteresis buffer (+35 units for waypoint patrol, +30% for free roam) so boundary spawns are not dropped
                local dropDist = hasWps and (maxScan + 35) or (maxScan * 1.3 + 50)
                local tsDead = false
                local tsType = ''
                pcall(function()
                    if tspawn() then
                        tsDead = tspawn.Dead() or false
                        tsType = tspawn.Type() or ''
                    end
                end)
                local tsIsDead = not tspawn() or tsDead or tsType == 'Corpse' or (tspawn.State and (tspawn.State() or '') == 'DEAD')
                if tsIsDead or isUnreachable(tid) or isIgnored(tspawn.CleanName()) then
                    haveNPC = false
                    clearTarget()
                elseif isXTargetId(tid) then
                    if distToId(tid) > (maxHuntXtarDist + 20) and not mq.TLO.Me.Combat() then
                        -- XTarget is beyond max chase range + buffer and not actively engaged in melee
                        haveNPC = false
                        clearTarget()
                        stopMoving()
                    end
                elseif not isXTargetId(tid) and not mq.TLO.Me.Combat() then
                    local okZ, sz = pcall(function() return tspawn.Z() end)
                    local tooFarZ = okZ and sz and math.abs(sz - myZ) > (maxHuntZ + 15)
                    local tooFarDist = not isMoveActive() and distToId(tid) > dropDist
                    if tooFarZ or tooFarDist then
                        -- Mark unreachable so findRoamTarget() won't immediately re-acquire the
                        -- same spawn on the very next tick, causing the acquire/drop spam loop.
                        -- The blacklist expires after 60s in case the mob moves closer or a path
                        -- opens up (same TTL as the navmesh-fail unreachable entries).
                        local reason = tooFarZ and 'elevation diff' or 'stationary+out-of-range'
                        print(string.format(
                            '\ay[Triune]\ax Hunt: dropping #%d (%s) -- %s. Blacklisting for 60s.',
                            tid, tostring(tspawn.CleanName()), reason))
                        markUnreachable(tid)
                        haveNPC = false
                        clearTarget()
                    end
                end
            end

            local xtarId = firstNPCXtarget(false, maxHuntXtarZ, maxHuntXtarDist)
            if xtarId then
                if pursuit.unreachableIds then pursuit.unreachableIds[xtarId] = nil end
                local curId = haveNPC and mq.TLO.Target.ID() or 0
                if curId ~= xtarId and (curId == 0 or not isXTargetId(curId)) then
                    stopMoving()
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    if setTarget(xtarId) then
                        print(string.format('\ay[Triune]\ax Puller (Hunt) XTarget detected -- engaging #%d (%s) [dist %.1f, max chase %d]',
                            xtarId, tostring(mq.TLO.Target.CleanName()), distToId(xtarId), maxHuntXtarDist))
                    end
                    haveNPC = true
                end
            end

            if haveNPC then
                local curTid = mq.TLO.Target.ID() or 0
                local isCurXtar = isXTargetId(curTid) or (xtarId and (curTid == xtarId or curTid == 0))
                if runtime.pullHpRest and not isCurXtar then
                    clearTarget()
                    haveNPC = false
                elseif not isCurXtar and not anyXtarAlive() and not mq.TLO.Me.Combat() and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
                    local curId = curTid
                    local closerId, candDist, curDist = checkCloserTarget(curId, nil, maxHuntZ, ctrl.hunter_min_level,
                        ctrl.hunter_max_level)
                    if closerId and setTarget(closerId) then
                        stopMoving()
                        local prevId = curId
                        pursuit.id = 0
                        pursuit.lastNavTargetId = 0
                        pursuit.hasRetargeted = true
                        pursuit.retargetCount = (pursuit.retargetCount or 0) + 1
                        if not pursuit.cycleTargetIds then pursuit.cycleTargetIds = {} end
                        if prevId > 0 then pursuit.cycleTargetIds[prevId] = true end
                        pursuit.cycleTargetIds[closerId] = true
                        print(string.format(
                            '\ay[Triune]\ax Puller (Hunt): Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f, switch %d/%d]',
                            closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist,
                            pursuit.retargetCount, ctrl.max_closer_retargets or 1))
                    end
                end
            end

            if not haveNPC then
                if runtime.combatHold() then
                    stopMoving()
                    return
                end
                if checkPullHpRest() then return end

                -- Let plugins (e.g. Auto AA purchases) use the gap between pulls
                if runtime.pluginManager and not mq.TLO.Me.Combat() and not anyXtarAlive(true) and not isCasting() then
                    if runtime.pluginManager.onBetweenPulls() then
                        stopMoving()
                        return
                    end
                end

                local scanRadius = hasWps and (ctrl.waypoint_scan_radius or 100) or (ctrl.hunter_radius or 1500)
                local id = firstNPCXtarget(false, maxHuntXtarZ, maxHuntXtarDist)
                if not id then
                    id = findRoamTarget(scanRadius, maxHuntZ, ctrl.hunter_min_level, ctrl.hunter_max_level)
                end
                if id and setTarget(id) then
                    if not runtime.verifyTargetCon(id, true) then
                        print(string.format(
                            '\ay[Triune]\ax Puller (Hunt): target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                            id, tostring(mq.TLO.Target.CleanName())))
                        clearTarget()
                        pursuit.id = 0
                        return
                    end
                    stopMoving()
                    haveNPC = true
                    pursuit.wanderLoc = nil
                    pursuit.hasRetargeted = false
                    pursuit.retargetCount = 0
                    pursuit.cycleTargetIds = { [id] = true }
                    runtime.lastHunterMsgKey = nil
                    print(string.format('\ay[Triune]\ax Puller (Hunt) target acquired: #%d (%s) dist %.1f',
                        id, tostring(mq.TLO.Target.CleanName()), distToId(id)))
                elseif not anyXtarAlive() then
                    if hasWps then
                        runtime.wpTick()
                    else
                        if pursuit.wanderLoc then
                            pursuit.wanderLoc = nil
                            if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
                            if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
                        end

                        local radius = ctrl.hunter_radius or 1500
                        local minLv = ctrl.hunter_min_level or 1
                        local maxLv = ctrl.hunter_max_level or 100
                        local zDiff = ctrl.hunter_z or 75
                        local zPlane = ctrl.hunter_z_plane or 15
                        local anchorKey = ''
                        if ctrl.hunter_combat_loc and (ctrl.hunter_combat_radius or 0) > 0 then
                            anchorKey = string.format('; anchor R%d @ %.0f,%.0f,%.0f',
                                ctrl.hunter_combat_radius, ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.y,
                                ctrl.hunter_combat_loc.z)
                        end
                        local currentKey = string.format('%d-%d-%d-%d-%d-%s', minLv, maxLv, radius, zDiff, zPlane, anchorKey)

                        if runtime.lastHunterMsgKey ~= currentKey then
                            runtime.lastHunterMsgKey = currentKey
                            print(string.format(
                                '\ay[Triune]\ax Puller (Hunt): No NPCs found (Lvl %d-%d, Radius %d, Max Z %d, Floor Z %d%s). Waiting...',
                                minLv, maxLv, radius, zDiff, zPlane, anchorKey))
                        end
                    end
                end
            end



            if haveNPC and not engage and not mq.TLO.Me.Combat() then
                local id = mq.TLO.Target.ID()
                if id and id > 0 and not isXTargetId(id) and not runtime.verifyTargetCon(id) then
                    print(string.format(
                        '\ay[Triune]\ax Hunter: target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                        id, tostring(mq.TLO.Target.CleanName())))
                    clearTarget()
                    pursuit.id = 0
                    stopMoving()
                    haveNPC = false
                end
            end

            if haveNPC then
                local id = mq.TLO.Target.ID()
                local pullStyle = ctrl.pull_style or 'Melee'

                -- Pet pull: dispatch pets while navigating (don't wait for arrival)
                if pullStyle == 'Pet' and (os.clock() - (runtime.lastPetPullAt or 0)) > 3.0 then
                    runtime.lastPetPullAt = os.clock()
                    petState.petHoldActive = false
                    local petId = mq.TLO.Me.Pet.ID() or 0
                    if petId > 0 and isSpawnAlive(petId) then mq.cmd('/pet attack') end
                    if hasActivePet() then
                        mq.cmd('/say #petcmd attack all')
                    end
                end

                -- For non-Melee pull styles, approach to engagement distance for the
                -- initial tag. Once tagged (XTarget) or already in combat, fall back to
                -- desiredRange() so the post-pull combat_style positioning takes over.
                local reqRange
                if pullStyle == 'Ranged' and not isXTargetId(id) and not mq.TLO.Me.Combat() then
                    reqRange = ctrl.pull_stand_back and (ctrl.pull_engage_dist or 100) or 40
                elseif pullStyle ~= 'Melee' and not isXTargetId(id) and not mq.TLO.Me.Combat() then
                    reqRange = ctrl.pull_engage_dist or 100
                else
                    reqRange = desiredRange(id)
                end

                local arrived = moveToward(id, reqRange)
                local inRange
                if pullStyle == 'Melee' then
                    inRange = arrived or (distToId(id) <= maxMeleeDistance(id) and hasLoS(id))
                else
                    inRange = arrived or (distToId(id) <= (ctrl.pull_engage_dist or 100) and hasLoS(id))
                end

                if inRange then
                    if pullStyle == 'Melee' then
                        -- Melee pull: unchanged -- close to melee range and attack
                        engage = true
                        mq.cmd('/face fast')
                        if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                        if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                    elseif pullStyle == 'Spell' then
                        -- Spell pull: cast pull spell from engagement range
                        stopMoving()
                        mq.cmd('/face fast')
                        if isXTargetId(id) or mq.TLO.Me.Combat() then
                            engage = true
                        else
                            local slotToCast = ctrl.pull_spell_gem or 1
                            local g = nil
                            if loadout.gems then
                                for _, eg in ipairs(loadout.gems) do
                                if eg and (tonumber(eg.gem) or 1) == slotToCast then
                                    g = eg
                                    break
                                end
                            end
                        end
                        local spellName = ctrl.pull_spell
                        if not spellName or spellName == '' then
                            pcall(function() spellName = mq.TLO.Me.Gem(slotToCast).Name() end)
                        end
                        if not spellName or spellName == '' then
                            spellName = runtime.getPrimarySpellForGem(slotToCast)
                        end
                        if spellName and spellName ~= '' then
                            local dummyEntry = g or { spell = spellName, target = 'E: Current Target', cls = 'ALL' }
                            castGem(slotToCast, dummyEntry, id)
                        else
                            -- Fallback: try first detrimental spell in loadout
                            if loadout.gems then
                                for i = 1, #loadout.gems do
                                    local lg = loadout.gems[i]
                                    local lpct = lg and tonumber(lg.pct)
                                    if lpct == nil then lpct = 100 end
                                    if lg and lg.spell and lg.spell ~= '' and lpct > 0 then
                                        local isDet = isDetrimentalAction(lg.spell, lg.target, lg)
                                        local actualSlot = tonumber(lg.gem) or i
                                        if isDet and castGem(actualSlot, lg, id) then break end
                                    end
                                end
                            end
                        end
                            -- Check if spell tagged the mob
                            if isXTargetId(id) then engage = true end
                        end
                    elseif pullStyle == 'Pet' then
                        -- Pet pull: pets already dispatched above during approach
                        mq.cmd('/face fast')
                        if isXTargetId(id) or distToId(id) <= 35 then
                            engage = true
                        else
                            local petTgtId = 0
                            pcall(function() petTgtId = mq.TLO.Pet.Target.ID() or 0 end)
                            if petTgtId > 0 and petTgtId == id then
                                engage = true
                            end
                        end
                    elseif pullStyle == 'Ranged' then
                        -- Ranged pull: try Throw Stone first, then bow/autofire, then melee fallback
                        mq.cmd('/face fast')
                        if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                        if isXTargetId(id) or mq.TLO.Me.Combat() then
                            engage = true
                        else
                            local tsReady = false
                            pcall(function() tsReady = mq.TLO.Me.AbilityReady('Throw Stone')() end)
                            if tsReady then
                                mq.cmd('/doability "Throw Stone"')
                            else
                                -- Fallback to ranged weapon (bow)
                                local hasRanged = false
                                pcall(function() hasRanged = mq.TLO.Me.Inventory('ranged')() ~= nil end)
                                if hasRanged then
                                    if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
                                else
                                    -- No ranged option available; fall back to melee
                                    if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                                end
                            end
                            -- Check if target was tagged
                            if isXTargetId(id) then engage = true end
                        end
                    end
                elseif isXTargetId(id) then
                    if distToId(id) <= (ctrl.xtar_nav_dist or 150) and hasLoS(id) then
                        engage = true
                    end
                end
            end
        end
    elseif ctrl.mode == 'Assist' then
        local maxNav = (ctrl and ctrl.xtar_nav_dist) or 150
        local maId = maTargetId()
        local defendId = nil
        if not maId and (ctrl.assist_self_defense ~= false) then
            defendId = runtime.findSelfDefenseTarget(maxNav)
        end
        local id = maId or defendId
        local isSelfDefense = (not maId and defendId ~= nil)

        if ctrl.submode == 'Backline' then
            local closingOnMob = false
            if id then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
                haveNPC = true
                local canAttack = isSelfDefense or (pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id))
                if canAttack and distToId(id) <= maxNav then
                    closingOnMob = true
                    if distToId(id) <= maxMeleeDistance(id) and hasLoS(id) then
                        engage = true
                    end
                end
            else
                haveNPC = false
            end
            if not closingOnMob and ctrl.chase then
                chaseMA()
            end
        else -- 'Chase' or 'Camp'
            local closingOnMob = false
            if id then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
                haveNPC = true
                local canAttack = isSelfDefense or (pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id))
                if canAttack then
                    if distToId(id) <= maxNav then
                        closingOnMob = true
                        if moveToward(id, desiredRange(id)) then engage = true end
                    end
                end
            else
                haveNPC = false
            end
            if not closingOnMob then
                if runtime.combatHold() then
                    stopMoving()
                    return
                end
                if ctrl.submode == 'Camp' then idleReturn() else chaseMA() end
            end
        end
    end

    -- Target pursuit / approach timeout check:
    -- If we have an active target but cannot get in striking range or establish LoS after 15s,
    -- mark it unreachable and switch to a different mob.
    local inCombatNow = mq.TLO.Me.Combat() or mq.TLO.Me.AutoFire() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')
    if haveNPC and not manualHold and (ctrl.mode ~= 'Manual' or isXTargetId(mq.TLO.Target.ID() or 0) or inCombatNow) then
        local tid = mq.TLO.Target.ID() or 0
        if tid > 0 then
            if pursuit.approachTargetId ~= tid then
                pursuit.approachTargetId = tid
                pursuit.approachStartedAt = os.clock()
            end
            local curDist = distToId(tid)
            local inReach = (curDist <= (desiredRange(tid) + 4)) and hasLoS(tid)
            if inReach or (inCombatNow and engage and hasLoS(tid)) then
                pursuit.approachStartedAt = os.clock()
            elseif (os.clock() - (pursuit.approachStartedAt or os.clock())) > 15.0 then
                print(string.format(
                    '\ay[Triune]\ax Target #%d (%s) unreachable after 15s -- marking unreachable & moving to next NPC.',
                    tid, tostring(mq.TLO.Target.CleanName())))
                markUnreachable(tid)
                stopMoving()
                clearTarget()
                haveNPC = false
                engage = false
                pursuit.id = 0
                pursuit.approachTargetId = 0
                pursuit.approachStartedAt = 0
                pursuit.nonXtarTargetId = 0
                pursuit.nonXtarEngageAt = 0
                runtime.pullTargetId = 0
                runtime.pullState = 'IDLE'
            end
        else
            pursuit.approachTargetId = 0
            pursuit.approachStartedAt = 0
            pursuit.nonXtarTargetId = 0
            pursuit.nonXtarEngageAt = 0
        end
    else
        pursuit.approachTargetId = 0
        pursuit.approachStartedAt = 0
        pursuit.nonXtarTargetId = 0
        pursuit.nonXtarEngageAt = 0
    end

    if ctrl.debug_mode and (os.clock() - (runtime.lastHunterDiagAt or 0)) > 1.5 then
        runtime.lastHunterDiagAt = os.clock()
        t = mq.TLO.Target
        local tid = (t() and t.ID()) or 0
        local tname = (t() and t.CleanName()) or 'none'
        local thp = (t() and t.PctHPs()) or -1
        local dist = (tid > 0) and distToId(tid) or -1
        local reach = (tid > 0) and maxMeleeDistance(tid) or 18
        local los = (tid > 0) and hasLoS(tid) or false
        local navActive = navLoaded() and mq.TLO.Navigation.Active() or false
        local stickActive = stickLoaded() and (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false
        local isHostile = (tid > 0) and isHostileTarget(tid) or false
        local combat = mq.TLO.Me.Combat() or false
        local casting = isCasting()
        local moving = isMoveActive()
        print(string.format(
            '\ao[DEBUG]\ax Mode:%s Style:%s | Tgt:%s(#%d HP:%d%% Hostile:%s) | Dist:%.1f Reach:%.1f LoS:%s | Nav:%s Stick:%s Mov:%s | Eng:%s Combat:%s Cast:%s | XTar:%d',
            tostring(ctrl.mode), tostring(ctrl.combat_style or 'Melee'), tostring(tname), tonumber(tid) or 0, tonumber(thp) or 0, tostring(isHostile), tonumber(dist) or 0, tonumber(reach) or 18, tostring(los),
            tostring(navActive), tostring(stickActive), tostring(moving), tostring(engage), tostring(combat), tostring(casting), tonumber(numXtar) or 0))
    end

    -- Auto-attack handling:
    -- Engage autoattack only when target exists, target is within striking distance,
    -- or target is confirmed engaged on XTarget.
    -- Turn off autoattack whenever out of range or when no NPCs remain on XTarget list.
    -- For player-directed modes (Manual, Assist), also require the NPC to be confirmed hostile before
    -- initiating auto-attack — prevents hitting friendly NPCs (merchants, etc.).
    local xtarActive = anyXtarAlive()
    local tid = mq.TLO.Target.ID() or 0
    local isPullStandBack = (ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee')
    local autoAttackOk = false
    if haveNPC then
        if isHostileTarget(tid) then
            if ctrl.mode == 'Manual' then
                -- In Manual mode, engage autoattack ONLY if actively engaged, mob is on XTarget, or already in combat
                local inCombatState = mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')
                if engage or isXTargetId(tid) or inCombatState then
                    autoAttackOk = true
                end
            elseif ctrl.mode == 'Puller' then
                autoAttackOk = engage or not isPullStandBack
            elseif ctrl.mode == 'Assist' then
                autoAttackOk = engage
            else
                autoAttackOk = engage
            end
        end
    end
    if not isPullStandBack then
        local isDraggingToCamp = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState == 'TO_CAMP')
        if haveNPC and not isDraggingToCamp and autoAttackOk then
            local curDist = (tid > 0) and distToId(tid) or 999
            local maxReach = (tid > 0) and maxMeleeDistance(tid) or ((ctrl and ctrl.melee_dist) or (pursuit.NAV_CONST and pursuit.NAV_CONST.MELEE_RANGE or 14))
            if curDist <= maxReach then
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then
                    print('\ag[Triune]\ax Standing up to attack.')
                    mq.cmd('/stand')
                end
                if not mq.TLO.Me.Combat() then
                    print(string.format('\ag[Triune]\ax Engaging /attack on -> %s (#%d) [dist=%.1f <= reach=%.1f, engage=%s]',
                        tostring(mq.TLO.Target.CleanName()), tid, curDist, maxReach, tostring(engage)))
                    mq.cmd('/attack on')
                end
                local isAssistBehind = (ctrl.mode == 'Assist' and ctrl.assist_behind ~= false)
                if isAssistBehind then
                    if runtime.playerHasAggro(tid) then
                        -- Assistant currently has aggro: suspend behind positioning to prevent circular spinning while tanking
                        if stickLoaded() then
                            pcall(function()
                                local dRange = math.floor(desiredRange(tid))
                                if (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') and (mq.TLO.Stick.MoveBehind() or pursuit.lastFrontStickDist ~= dRange) then
                                    mq.cmdf('/stick id %d %d', tid, dRange)
                                    pursuit.lastFrontStickDist = dRange
                                end
                            end)
                        end
                        if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                            pursuit.lastCombatFaceAt = os.clock()
                            mq.cmd('/face fast')
                        end
                    else
                        runtime.positionBehindTarget(tid, desiredRange(tid))
                    end
                else
                    if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                        pursuit.lastCombatFaceAt = os.clock()
                        mq.cmd('/face fast')
                    end
                end
            elseif not isMoveActive() and curDist > maxReach and tid > 0 then
                -- Mob moved, was pushed, or is out of striking reach: re-close distance
                if ctrl.mode ~= 'Manual' then
                    moveToward(tid, desiredRange(tid))
                end
            end
        else
            -- Not engaging any NPC or dragging mob to camp: turn off auto-attack if not in manual combat
            if mq.TLO.Me.Combat() and not (ctrl.mode == 'Manual' and (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')) then
                mq.cmd('/attack off')
            end
            if mq.TLO.Me.AutoFire() then
                mq.cmd('/autofire off')
            end
            if stickLoaded() then
                pcall(function()
                    if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                        mq.cmd('/stick off')
                    end
                end)
            end
        end
    end

    -- Pet classes on this server can have multiple simultaneous pets (one per
    -- pet class in the trio) -- the standard single-pet "/pet attack" only ever
    -- addresses one of them. This server's own multi-pet extension command
    -- handles all of them at once; fire it once per new target, not every tick.
    -- "#petcmd ..." has no leading slash, so mq.cmd() can't parse it directly
    -- (confirmed: "DoCommand - Couldn't parse '#petcmd attack all'") -- routing
    -- it through /say sends the text as chat, which is the same pipe EQEMU's
    -- #command handler listens on (identical to typing it with no slash at all).
    -- Also skip while casting -- the game rejects any command mid-cast ("You
    -- can't use that command while casting"); leaving lastPetCmdTargetId
    -- unset lets it retry on a later tick once the cast finishes. And skip
    -- entirely for a trio with no pet class at all (e.g. War/Pal/Mnk) -- there's
    -- nothing to send, and it was spamming the /say line for no reason.
    --
    -- A manually-clicked target reaches haveNPC+engage on a clean, isolated
    -- tick and the single send always lands. A self-directed mode's own
    -- target (Hunter/Pet Tank's findRoamTarget) instead flips engage=true on
    -- whatever tick moveToward finishes closing distance -- the same tick that
    -- can also be issuing a stop/face/cast command, and pets have sometimes
    -- been observed just standing at the target when that happens (reported:
    -- pets "just sit there" after auto-acquire, but "go right away" on a
    -- manual click). Rather than one-shot per target, also retry periodically
    -- while still engaged on the same target so a lost first attempt corrects
    -- itself within a few seconds instead of leaving pets idle for the fight.
    --
    -- Advanced Pet Discipline AA / Pet Hold:
    -- "#petcmd hold all" is a toggle command.
    -- If pet_hold_enabled is active and the character has pet classes, we issue:
    --   "#petcmd hold all" while out of combat / waiting for assist threshold to enable hold,
    --   "#petcmd attack all" once in combat and HP threshold is met.
    local assistThreshold = ctrl.pet_assist_at or 100
    local canCommandPets = hasActivePet()
    local petHoldEnabled = (ctrl.pet_hold_enabled ~= false) and canCommandPets

    -- Puller Camp Mode: Keep pets on HOLD while traveling to mob or dragging mob back to camp,
    -- until the mob is brought within camp fight range.
    local isPullingToCamp = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState ~= 'FIGHTING')
    if ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and (ctrl.pull_style or 'Melee') == 'Pet' and runtime.pullState == 'TO_MOB' then
        isPullingToCamp = false
    end
    if isPullingToCamp and ctrl.camp_loc then
        pcall(function()
            local campTargetId = mq.TLO.Target.ID() or 0
            if campTargetId > 0 then
                local ts = mq.TLO.Spawn(campTargetId)
                if ts() then
                    local tx = ts.X()
                    local ty = ts.Y()
                    if tx and ty then
                        local dx = tx - ctrl.camp_loc.x
                        local dy = ty - ctrl.camp_loc.y
                        if (dx * dx + dy * dy) <= (35 * 35) then
                            isPullingToCamp = false -- Mob has arrived at camp!
                        end
                    end
                end
            end
        end)
    end

    -- Puller Hunt Pet Pull: don't re-hold pets while navigating to mob
    local isHuntPetApproach = (ctrl.mode == 'Puller' and ctrl.submode == 'Hunt'
        and (ctrl.pull_style or 'Melee') == 'Pet' and haveNPC and not engage)

    if petHoldEnabled and (not (haveNPC and engage) or isPullingToCamp) and not isHuntPetApproach then
        if not petState.petHoldActive then
            mq.cmd('/say #petcmd hold all')
            petState.petHoldActive = true
        end
    end

    if haveNPC and engage and canCommandPets and not isPullingToCamp then
        if ctrl.mode == 'Manual' then
            setManualHunterPetHold(false)
        end
        tid = mq.TLO.Target.ID() or 0
        local dueForRetry = (os.clock() - (petState.lastCmdAt or 0)) > 5.0
        if (tid ~= petState.lastCmdTargetId or dueForRetry) and not isCasting() then
            local tgtHp = pctHP(tid) or 100
            -- Self-directed modes: character is leading combat directly, skip external MA aggro gate.
            -- Assist modes: require player/tank has started hitting AND HP threshold met.
            local selfDirected = (ctrl.mode == 'Manual' or ctrl.mode == 'Puller')
            local engageOk = selfDirected or (playerHasAggro(tid) and playerIsEngagingTarget(tid))
            if tgtHp <= assistThreshold then
                if engageOk then
                    -- Threshold met: send attack.
                    mq.cmd('/say #petcmd attack all')
                    petState.lastCmdTargetId = tid
                    petState.lastCmdAt = os.clock()
                    petState.petHoldActive = false
                    petState.holdIssuedForId = 0
                end
            elseif petHoldEnabled and not petState.petHoldActive then
                mq.cmd('/say #petcmd hold all')
                petState.petHoldActive = true
                petState.holdIssuedForId = tid
            end
        end
    else
        -- No active NPC target or still pulling back to camp: reset command tracking.
        petState.lastCmdTargetId = 0
        if ctrl.mode == 'Manual' and not mq.TLO.Me.Combat() and canCommandPets then
            setManualHunterPetHold(true)
        end
    end

    -- Auto-turn off Burn Mode when extended target list becomes clear
    if ctrl.burn and not xtarActive then
        ctrl.burn = false
        print('\ag[Triune]\ax Burn mode auto-disabled (XTarget clear).')
    end


    -- Universal hostile-target gate: only allow offensive actions (spells, AAs,
    -- discs, auto-attack) when the NPC target is confirmed hostile. Prevents
    -- the engine from casting on friendly NPCs (merchants, quest givers,
    -- guards, bankers) that the player happens to click on.
    -- Engine-auto-targeting modes (Hunter, Puller, Pull & Assist, Pet Tank,
    -- Garrison) are exempt: their own findRoamTarget/firstNPCXtarget selection
    -- is the safety gate, and they need to initiate combat on fresh targets.
    local ENGINE_TARGETS_MODE = {
        ['Puller'] = true,
    }
    local combatReady = (not haveNPC or engage)
    if haveNPC and engage and not ENGINE_TARGETS_MODE[ctrl.mode] then
        tid = mq.TLO.Target.ID() or 0
        if not isHostileTarget(tid) then
            combatReady = false
        end
    end

    -- activated AAs are instant and off the spell timer: fire every eligible one,
    -- and don't let them block (or be blocked by) the spell cast below
    if combatReady then
        for rawName, a in pairs(loadout.aas) do
            local name = type(rawName) == 'string' and rawName:match('^%s*(.-)%s*$') or rawName
            local aPct = tonumber(a.pct)
            if aPct == nil then aPct = 30 end
            local isDet = isDetrimentalAction(name, a.target, a)
            local minXt = tonumber(a.min_xtar) or 1
            local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
            if a.enabled and (aPct > 0) and (not a.burn_only or ctrl.burn) and xtOk then
                local id = resolveTargetId(a.target, a.cls, a.when, name, aPct, a)
                if id and conditionMet(a.when, aPct, name, id, a.cls, a.target) then
                    if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                        fireAA(name, a, id)
                    end
                end
            end
        end
    end
    -- Innate Combat Abilities (/doability): Autoskill (continuous on cooldown) and Priority Conditions
    if combatReady and loadout.actions then
        -- 1. Autoskill: continuously fire high-frequency combat attacks on cooldown when ready
        for name, act in pairs(loadout.actions) do
            local isDet = isDetrimentalAction(name, act.target, act)
            local minXt = tonumber(act.min_xtar) or 1
            local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
            if act.enabled and act.autoskill and isAutoskillEligible(name) and (not act.burn_only or ctrl.burn) and xtOk then
                local actPct = tonumber(act.pct)
                if actPct == nil then actPct = 100 end
                local id = resolveTargetId(act.target, act.cls, act.when, name, actPct, act)
                if id and id > 0 then
                    if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                        if isSkillReady(name) then
                            fireSkill(name, act, id)
                        end
                    end
                end
            end
        end

        -- 2. Priority Conditional Actions (e.g. Mend on low HP, Feign Death, Taunt, Disarm, Intimidation)
        local eligibleActions = {}
        for name, act in pairs(loadout.actions) do
            if act.enabled and not act.autoskill then
                local actPct = tonumber(act.pct)
                if actPct == nil then actPct = 100 end
                local isDet = isDetrimentalAction(name, act.target, act)
                local minXt = tonumber(act.min_xtar) or 1
                local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
                if (actPct > 0) and (not act.burn_only or ctrl.burn) and xtOk then
                    local id = resolveTargetId(act.target, act.cls, act.when, name, actPct, act)
                    if id and conditionMet(act.when, actPct, name, id, act.cls, act.target) then
                        local bossOk = true
                        if act.boss_only then
                            local s = mq.TLO.Spawn(id)
                            bossOk = not not (s() and s.Named())
                        end
                        if bossOk then
                            if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                                if isSkillReady(name) then
                                    eligibleActions[#eligibleActions + 1] = { name = name, entry = act, id = id }
                                end
                            end
                        end
                    end
                end
            end
        end
        if #eligibleActions > 0 then
            table.sort(eligibleActions, function(a, b) return (tonumber(a.entry.priority) or 50) < (tonumber(b.entry.priority) or 50) end)
            for _, e in ipairs(eligibleActions) do
                if fireSkill(e.name, e.entry, e.id) then
                    break
                end
            end
        end
    end

    -- Disciplines (/disc): Gather every enabled disc whose condition is met, try in priority order
    if combatReady and loadout.discs then
        local eligibleDiscs = {}
        for name, d in pairs(loadout.discs) do
            local dPct = tonumber(d.pct)
            if dPct == nil then dPct = 30 end
            local isDet = isDetrimentalAction(name, d.target, d)
            local minXt = tonumber(d.min_xtar) or 1
            local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
            if d.enabled and (dPct > 0) and (not d.burn_only or ctrl.burn) and xtOk then
                local id = resolveTargetId(d.target, d.cls, d.when, name, dPct, d)
                if id and conditionMet(d.when, dPct, name, id, d.cls, d.target) then
                    local bossOk = true
                    if d.boss_only then
                        local s = mq.TLO.Spawn(id)
                        bossOk = not not (s() and s.Named())
                    end
                    if bossOk then
                        if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                            local ready = isDiscReady(name)
                            if ready then
                                eligibleDiscs[#eligibleDiscs + 1] = { name = name, entry = d, id = id }
                            end
                        end
                    end
                end
            end
        end
        table.sort(eligibleDiscs, function(a, b) return (tonumber(a.entry.priority) or 50) < (tonumber(b.entry.priority) or 50) end)
        for _, e in ipairs(eligibleDiscs) do
            if fireDisc(e.name, e.entry, e.id) then break end
        end
    end
    -- one spell cast per tick, only when not already casting/singing AND not
    -- actively moving. EQ interrupts/cancels almost every spell cast if you
    -- move during it -- with no check for this, a gem's cast would fire while
    -- Hunter/Puller was still pathing toward a mob, get cancelled by the
    -- movement a moment later, and (since the buff never actually landed)
    -- immediately become eligible to retry again next cooldown -- repeating
    -- for the whole approach ("keeps trying to cast X while pulling"). AAs
    -- above are unaffected (instant, no cast bar, usable on the move). Casts
    mq.doevents()

    local isMoving = false
    pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
    local isBrdMe = false
    pcall(function() isBrdMe = (mq.TLO.Me.Class.ShortName() == 'BRD') end)
    local canCastMove = isBrdMe or not isMoving

    if combatReady and not isCasting() and not isMoveActive() and canCastMove and loadout.clickies and #loadout.clickies > 0 then
        if not isCasting() and runtime.restoreTargetId and runtime.restoreTargetId > 0 then
            local rId = runtime.restoreTargetId
            runtime.restoreTargetId = nil
            if isSpawnAlive(rId) and mq.TLO.Target.ID() ~= rId then
                runtime.setTarget(rId)
            end
        end
        for _, c in ipairs(loadout.clickies) do
            local cPct = tonumber(c.pct)
            if cPct == nil then cPct = 100 end
            local isEnabled = (c.enabled ~= false) and (cPct > 0)
            local minXt = tonumber(c.min_xtar) or 1
            local effName = (c.spell and c.spell ~= '') and c.spell or c.name
            local isDet = isDetrimentalAction(effName, c.target, c)
            local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
            local burnOk = (not c.burn_only or ctrl.burn)
            if isEnabled and burnOk and xtOk then
                local id = resolveTargetId(c.target, 'ALL', c.when, effName, cPct, c)
                local lockedOut = id and castTracker.isLockedOut(effName, id, c.kind)
                if not lockedOut then
                    local condOk = id and conditionMet(c.when, cPct, effName, id, 'ALL', c.target)
                    if condOk then
                        local targetValid = (id == mq.TLO.Me.ID()) or (not isDet and runtime.isTargetInRange(effName, id)) or (isDet and isHostileTarget(id) and isTargetInRange(effName, id))
                        if targetValid and runtime.useClickie(c, id) then
                            if c.when == 'missing buff' and c.spell and c.spell ~= '' then
                                local bene = false
                                pcall(function() bene = mq.TLO.Spell(c.spell).Beneficial() end)
                                if bene then runtime.sungBuffs[sungKey(c.spell, id)] = true end
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    local inRealCombat = isCombat() or anyXtarAlive(true) or countNPCXtarget() > 0 or mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT') or runtime.hasDowntimeAggroThreat()
    local gemCasted = false

    if combatReady and not isCasting() and not isMoveActive() and canCastMove then
        if not isCasting() and runtime.restoreTargetId and runtime.restoreTargetId > 0 then
            local rId = runtime.restoreTargetId
            runtime.restoreTargetId = nil
            if isSpawnAlive(rId) and mq.TLO.Target.ID() ~= rId then
                runtime.setTarget(rId)
            end
        end
        if loadout.gems then
            local gemOrder = {}
            for i = 1, #loadout.gems do
                local g = loadout.gems[i]
                if g and g.spell and g.spell ~= '' and runtime.isHealAction(g.spell, g.target, g) then
                    table.insert(gemOrder, 1, i)
                else
                    table.insert(gemOrder, i)
                end
            end
            for _, i in ipairs(gemOrder) do
                local g = loadout.gems[i]
                if g and g.spell and g.spell ~= '' then
                    local assignedGem = tonumber(g.gem) or math.min(i, 12)
                    local actualGem = assignedGem
                    local isMemmed = isGemMatching(assignedGem, g.spell)
                    if not isMemmed then
                        local otherSlot = nil
                        pcall(function() otherSlot = mq.TLO.Me.Gem(g.spell)() end)
                        if otherSlot and otherSlot > 0 then
                            actualGem = otherSlot
                            isMemmed = true
                        end
                    end

                    if isMemmed then
                        local pctVal = tonumber(g.pct)
                        if pctVal == nil then pctVal = 100 end
                        local isEnabled = (pctVal > 0)
                        local minXt = tonumber(g.min_xtar) or 1
                        local isDet = isDetrimentalAction(g.spell, g.target, g)
                        local xtOk = (numXtar >= minXt) or (not isDet and minXt <= 1)
                        local burnOk = (not g.burn_only or ctrl.burn)
                        if isEnabled and burnOk and xtOk then
                            local id = resolveTargetId(g.target, g.cls, g.when, g.spell, pctVal, g)
                            local lockedOut = id and castTracker and castTracker.isLockedOut(g.spell, id, g.kind)
                            local condOk = false
                            if not lockedOut then
                                condOk = not not (id and conditionMet(g.when, pctVal, g.spell, id, g.cls, g.target, g))
                                if condOk then
                                    local castLimitOk = true
                                    local maxC = tonumber(g.max_casts) or 0
                                    if maxC > 0 and id and id > 0 then
                                        local currentCasts = (runtime.npcCastCounts and runtime.npcCastCounts[id] and runtime.npcCastCounts[id][g.spell]) or 0
                                        if currentCasts >= maxC then
                                            castLimitOk = false
                                        end
                                    end
                                    if castLimitOk then
                                        local targetValid = (id == mq.TLO.Me.ID()) or (not isDet and runtime.isTargetInRange(g.spell, id)) or (isDet and isHostileTarget(id) and isTargetInRange(g.spell, id))
                                        if targetValid and castGem(actualGem, g, id) then
                                            gemCasted = true
                                            if g.when == 'missing buff' then
                                                local bene = false
                                                pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                                                if bene then runtime.sungBuffs[sungKey(g.spell, id)] = true end
                                            end
                                            break
                                        end
                                    end
                                end
                            elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                                runtime.lastGemDiagAt = os.clock()
                                tid = mq.TLO.Target.ID() or 0
                                local ts = mq.TLO.Spawn(tid)
                                local ttype = (ts() and ts.Type()) or 'nil'
                                local thp = (ts() and ts.PctHPs()) or -1
                                print(string.format(
                                    '\ao[Triune debug]\ax gem %d "%s" skipped -- tgtTok="%s"(base="%s") id=%s (rawTgt=%d type=%s hp=%d) condOk=%s xtOk=%s(%d>=%d)',
                                    actualGem, g.spell, tostring(g.target), tostring(baseTok(g.target)), tostring(id), tid, ttype, thp,
                                    tostring(condOk), tostring(xtOk), numXtar, minXt))
                            end
                        elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                            runtime.lastGemDiagAt = os.clock()
                            local gLocked = castTracker and castTracker.isLockedOut(g.spell, nil, g.kind)
                            print(string.format(
                                '\ao[Triune debug]\ax gem %d "%s" gate failed -- isEnabled=%s(%d%%) xtOk=%s(%d>=%d) burnOk=%s lockedOut=%s',
                                actualGem, g.spell, tostring(isEnabled), pctVal, tostring(xtOk), numXtar, minXt, tostring(burnOk), tostring(gLocked)))
                        end
                    end
                end
            end
        end
    elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
        runtime.lastGemDiagAt = os.clock()
        local stickOn = false
        pcall(function() stickOn = stickLoaded() and mq.TLO.Stick.Status() == 'ON' end)
        print(string.format('\ao[Triune debug]\ax all gems blocked -- casting=%s navActive=%s stickOn=%s',
            tostring(isCasting()), tostring(navLoaded() and mq.TLO.Navigation.Active()), tostring(stickOn)))
    end

    -- If out of combat and no spell was cast, process downtime buff swapping & priority spell restoration
    if not gemCasted and not inRealCombat and not isCasting() and not isCastingOrStarting() and not isMoveActive() and not runtime.medBreakActive then
        runtime.processDowntimeBuffing()
    end
end

local function normalizeCommandKey(text)
    return tostring(text or ''):lower():gsub('[^%w]', '')
end

local function setTriuneMode(arg1, arg2)
    if not arg1 or arg1 == '' then return false end
    local k1 = normalizeCommandKey(arg1)
    local k2 = arg2 and normalizeCommandKey(arg2) or ''

    local newMode, newSubmode

    if k1 == 'manual' or k1 == 'manualhunter' then
        newMode = 'Manual'
        newSubmode = 'Hunt'
    elseif k1 == 'puller' then
        newMode = 'Puller'
        if k2 == 'hunt' or k2 == 'hunter' or k2 == 'roam' then
            newSubmode = 'Hunt'
        elseif k2 == 'camp' or k2 == 'pull' then
            newSubmode = 'Camp'
        else
            newSubmode = ctrl.submode or 'Camp'
        end
    elseif k1 == 'hunter' or k1 == 'pethunter' or k1 == 'pettank' then
        newMode = 'Puller'
        newSubmode = 'Hunt'
    elseif k1 == 'pull' or k1 == 'pullassist' then
        newMode = 'Puller'
        newSubmode = 'Camp'
    elseif k1 == 'assist' then
        newMode = 'Assist'
        if k2 == 'chase' then
            newSubmode = 'Chase'
        elseif k2 == 'camp' or k2 == 'garrison' or k2 == 'tank' then
            newSubmode = 'Camp'
        elseif k2 == 'backline' or k2 == 'ranged' then
            newSubmode = 'Backline'
        else
            newSubmode = ctrl.submode or 'Chase'
        end
    elseif k1 == 'chase' or k1 == 'chaseassist' then
        newMode = 'Assist'
        newSubmode = 'Chase'
    elseif k1 == 'garrison' or k1 == 'tank' then
        newMode = 'Assist'
        newSubmode = 'Camp'
    elseif k1 == 'backline' or k1 == 'ranged' then
        newMode = 'Assist'
        newSubmode = 'Backline'
    else
        return false
    end

    if ctrl.mode == 'Manual' and newMode ~= 'Manual' then
        setManualHunterPetHold(false, false)
    end

    ctrl.mode = newMode
    ctrl.submode = newSubmode
    if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end

    if MODES.SUBMODES[ctrl.mode] then
        print(string.format('\ag[Triune]\ax mode set to %s (%s).', ctrl.mode, ctrl.submode))
    else
        print(string.format('\ag[Triune]\ax mode set to %s.', ctrl.mode))
    end
    runtime.saveLoadout(true)
    return true
end

function runtime.setRunning(enable)
    if enable then
        if ctrl.running then
            print('\ay[Triune]\ax already running.')
            return
        end
        if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
            runtime.setNearestWaypoint()
        end
        ctrl.running = true
        runtime.wasRunning = true
        print('\ag[Triune]\ax running.')
        if not navLoaded() and ctrl.mode ~= 'Manual' then
            mq.cmd('/popup [Triune] WARNING: MQ2Nav is NOT loaded!')
            print('\ar[Triune WARNING]\ax MQ2Nav plugin is not loaded! Movement and navigation require MQ2Nav (/plugin mq2nav).')
        elseif not navMeshLoaded() and ctrl.mode ~= 'Manual' then
            local curZone = mq.TLO.Zone.ShortName() or 'current zone'
            mq.cmdf('/popup [Triune] WARNING: No NavMesh for %s!', curZone)
            print(string.format('\ar[Triune WARNING]\ax No NavMesh loaded for zone "%s"! Movement and pathing require a zone navmesh.', curZone))
        end
        if not stickLoaded() and ctrl.mode ~= 'Manual' then
            mq.cmd('/popup [Triune] WARNING: MQ2MoveUtils is NOT loaded!')
            print('\ar[Triune WARNING]\ax MQ2MoveUtils plugin is not loaded! Target stick and melee positioning require MQ2MoveUtils (/plugin mq2moveutils).')
        end
    else
        if not ctrl.running then
            print('\ay[Triune]\ax already paused.')
            return
        end
        if ctrl.mode == 'Manual' then
            setManualHunterPetHold(true, true)
        else
            setManualHunterPetHold(false, true)
        end
        ctrl.running = false
        if runtime.fullStop then runtime.fullStop() end
        print('\ag[Triune]\ax paused.')
    end
end

function runtime.triuneToggle()
    runtime.setRunning(not ctrl.running)
end

local function triuneCommand(...)
    local args = { ... }
    local cmd = ''
    if #args > 0 then
        cmd = normalizeCommandKey(args[1])
    end
    if cmd == '' then
        if runtime.triuneToggle then runtime.triuneToggle() end
        return
    end
    if cmd == 'run' or cmd == 'start' then
        runtime.setRunning(true)
    elseif cmd == 'pause' or cmd == 'stop' then
        runtime.setRunning(false)
    elseif cmd == 'status' then
        local modeStr = ctrl.mode
        if MODES.SUBMODES[ctrl.mode] then modeStr = modeStr .. ' (' .. ctrl.submode .. ')' end
        print(string.format('\ag[Triune]\ax status: %s, mode: %s, burn: %s', ctrl.running and 'running' or 'paused',
            modeStr, ctrl.burn and 'ON' or 'OFF'))
    elseif cmd == 'burn' or cmd == 'burnon' or cmd == 'burnoff' or cmd == 'burn1' or cmd == 'burn0' or cmd == 'burntoggle' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or cmd == 'burnon' or cmd == 'burn1' then
            ctrl.burn = true
            print('\ag[Triune]\ax Burn mode ENABLED!')
        elseif sub == 'off' or sub == '0' or cmd == 'burnoff' or cmd == 'burn0' then
            ctrl.burn = false
            print('\ag[Triune]\ax Burn mode DISABLED.')
        else
            ctrl.burn = not ctrl.burn
            print(string.format('\ag[Triune]\ax Burn mode %s.', ctrl.burn and 'ENABLED!' or 'DISABLED.'))
        end
    elseif cmd == 'debug' or cmd == 'debugmode' or cmd == 'diag' then
        ctrl.debug_mode = not ctrl.debug_mode
        print(string.format('\ag[Triune]\ax Debug Mode: %s', ctrl.debug_mode and '\agENABLED (live combat telemetry)\ax' or '\arDISABLED\ax'))
    elseif cmd == 'help' or cmd == 'h' or cmd == '?' then
        print('\ag[Triune]\ax --- Slash Commands (/ac or /triune) ---')
        print('  \ag/ac run | start\ax - Start autocombat execution')
        print('  \ag/ac pause | stop\ax - Pause execution & disengage combat')
        print('  \ag/ac burn [on|off]\ax - Toggle burn mode')
        print('  \ag/ac memall | mem\ax - Memorize priority spells to gem bar')
        print('  \ag/ac importbar | import\ax - Auto-populate spell lines from current spell gems')
        print('  \ag/ac debug\ax - Toggle live combat debug telemetry in chat')
        print('  \ag/ac status\ax - Print running state and mode')
        print('  \ag/ac compact | mini\ax - Toggle compact mini-window mode')
        print('  \ag/ac hud | uf | targetwin\ax - Toggle popout Target & Player HUD window')
        print('  \ag/ac help | h | ?\ax - Print slash command summary')
        print('  \ag/ac clearcursor | autoinv\ax - Clear items from cursor')
        print('  \ag/ac style [melee|ranged|spell]\ax - Configure combat style')
        print('  \ag/ac range [dist]\ax - Configure melee or ranged distance')
        print('  \ag/ac cd | cooldowns\ax - Toggle popout Cooldown & Ability Monitor window')
        print('  \ag/ac zplane [5-100]\ax - Configure Hunter Tier 1 same-floor / Z plane height threshold')
        print('  \ag/ac huntz [10-300]\ax - Configure Hunter Tier 2 max vertical height difference')
        print('  \ag/ac pullcon [con]\ax - Configure faction consideration filter')
        print('  \ag/ac wp [add|clear|del|on|off|list]\ax - Configure & toggle Puller Waypoint Patrol')
        print('  \ag/ac pullhp [0-95]\ax - Set minimum HP % threshold before pausing pulling to rest')
        print('  \ag/ac clear lockouts\ax - Clear all active spell lockouts & mob immunities')
        if runtime.pluginManager and runtime.pluginManager.helpLines then
            for _, hl in ipairs(runtime.pluginManager.helpLines()) do print(hl) end
        end
        print('  \ag/ac pet <verb> [scope]\ax - Dispatch server #petcmd (attack, back, follow, hold on, taunt off, etc.)')
        print('  \ag/ac pet status\ax - Print active pet status for all trio classes')
        print('  \ag/ac petscan\ax - Re-scan zone for active pets belonging to player')
        print('  \ag/ac pethold [on|off]\ax - Toggle automatic out-of-combat Pet Hold')
        print('  \ag/ac petassist [1-100]\ax - Set mob HP % threshold for sending pets to attack')
        print('  \ag/ac ma [target|clear|<name>|<id>]\ax - Configure Main Assist player ID or name')
        print('  \ag/ac xtardist [25-300]\ax - Set max XTarget chase / engagement distance')
        print('  \ag/ac chasedist [5-100]\ax - Set following distance to stay back from Main Assist')
        print('  \ag/ac selfdefense [on|off]\ax - Toggle Assist mode self-defense when attacked')
        print('  \ag/ac assistbehind [on|off]\ax - Toggle positioning behind NPC in Assist mode')
        print('  \ag/ac manualstick [on|off]\ax - Manual mode: stick to the NPC being fought (off = you drive)')
        print('  \ag/ac manualnav [on|off]\ax - Manual mode: auto-nav to a hostile NPC when you select it')
        print('  \ag/ac pausezone [on|off]\ax - Toggle automatic script pause when zoning (default: on)')
        print('  \ag/ac fov [50-150|on|off]\ax - Set camera FOV and toggle maintain on zone')
        print('  \ag/ac winpos [save|restore|reset]\ax - Save or restore window positions & layout')
        print(
            '  \ag/ac <mode> [submode]\ax - Switch combat mode (manual, puller [hunt|camp], assist [chase|camp|backline])')
        print('  \ag/triunerun\ax - Quick keybind command to toggle run/pause')
    elseif cmd == 'pet' or cmd == 'petcmd' then
        local verb = args[2] and string.lower(args[2]) or 'status'
        local scope = args[3] and string.lower(args[3]) or nil
        if verb == 'status' or verb == 'list' then
            local slots, extra = getMultiPetList()
            print('\ag[Triune Pet Status]\ax:')
            for _, s in ipairs(slots) do
                if s.petId then
                    local pinfo = getPetSpawnInfo(s.petId)
                    print(string.format('  Slot %d [%s]: \ag%s\ax (Lvl %d %s, HP: %d%%, Target: %s)',
                        s.slotNum, s.cls, pinfo.cleanName, pinfo.level, pinfo.race, pinfo.hpPct, pinfo.targetName))
                else
                    print(string.format('  Slot %d [%s]: \ay%s\ax', s.slotNum, s.cls, s.isPetCls and 'Missing/Not Summoned' or 'Non-pet class'))
                end
            end
            if #extra > 0 then
                print(string.format('  Additional/Swarm Pets: %d active', #extra))
            end
        elseif verb == 'scan' or verb == 'rescan' or verb == 'reconcile' then
            reconcilePets()
        elseif verb == 'report' or verb == 'health' then
            mq.cmd('/pet report')
            sendPetCmd('health', scope)
        elseif verb == 'hold' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('hold ' .. scope, targetScope)
        elseif verb == 'ghold' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('ghold ' .. scope, targetScope)
        elseif verb == 'taunt' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('taunt ' .. scope, targetScope)
        elseif verb == 'spellhold' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('spellhold ' .. scope, targetScope)
        elseif verb == 'focus' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('focus ' .. scope, targetScope)
        elseif verb == 'regroup' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('regroup ' .. scope, targetScope)
        elseif verb == 'assist' and (scope == 'on' or scope == 'off') then
            local targetScope = args[4] and string.lower(args[4]) or nil
            sendPetCmd('assist ' .. scope, targetScope)
        else
            sendPetCmd(verb, scope)
        end
    elseif cmd == 'petscan' or cmd == 'petreconcile' then
        reconcilePets()
    elseif cmd == 'pethold' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' then
            ctrl.pet_hold_enabled = true
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Auto Pet Hold: ENABLED.')
        elseif sub == 'off' or sub == '0' then
            ctrl.pet_hold_enabled = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Auto Pet Hold: DISABLED.')
        else
            ctrl.pet_hold_enabled = (ctrl.pet_hold_enabled == false)
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto Pet Hold: %s.', ctrl.pet_hold_enabled and 'ENABLED' or 'DISABLED'))
        end
    elseif cmd == 'petassist' or cmd == 'petassistat' then
        local pct = tonumber(args[2])
        if pct and pct >= 1 and pct <= 100 then
            ctrl.pet_assist_at = pct
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Pet Assist threshold set to: \ag%d%%\ax.', pct))
        else
            print(string.format('\ay[Triune]\ax Current Pet Assist threshold: %d%% (Usage: /ac petassist [1-100])', ctrl.pet_assist_at or 100))
        end
    elseif cmd == 'cd' or cmd == 'cds' or cmd == 'cooldown' or cmd == 'cooldowns' or cmd == 'cooldownui' or cmd == 'cooldownwin' then
        ctrl.show_cooldowns = not ctrl.show_cooldowns
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Cooldown Monitor window %s.', ctrl.show_cooldowns and 'OPENED' or 'CLOSED'))
    elseif cmd == 'hud' or cmd == 'uf' or cmd == 'unitframes' or cmd == 'targetwin' or cmd == 'playerwin' then
        ctrl.show_unit_frames = not ctrl.show_unit_frames
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Target & Player HUD window %s.', ctrl.show_unit_frames and 'OPENED' or 'CLOSED'))
    elseif cmd == 'group' or cmd == 'gw' or cmd == 'groupwin' or cmd == 'groupwindow' then
        ctrl.show_group_window = not ctrl.show_group_window
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Group Window %s.', ctrl.show_group_window and 'OPENED' or 'CLOSED'))
    elseif cmd == 'eff' or cmd == 'effects' or cmd == 'buffs' or cmd == 'buffwin' or cmd == 'songwin' or cmd == 'songs' then
        ctrl.show_effects_window = not ctrl.show_effects_window
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Effects & Songs Window %s.', ctrl.show_effects_window and 'OPENED' or 'CLOSED'))
    elseif cmd == 'xtar' or cmd == 'xt' or cmd == 'xtarget' or cmd == 'xtargetwin' or cmd == 'xtwin' then
        ctrl.show_xtarget_window = not ctrl.show_xtarget_window
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Extended Target Window %s.', ctrl.show_xtarget_window and 'OPENED' or 'CLOSED'))
    elseif cmd == 'gems' or cmd == 'gembar' or cmd == 'spellbar' or cmd == 'castbar' or cmd == 'spellgems' then
        ctrl.show_spell_gems = not ctrl.show_spell_gems
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Popout Spell Gem Bar Window %s.', ctrl.show_spell_gems and 'OPENED' or 'CLOSED'))
    elseif cmd == 'winpos' or cmd == 'windows' or cmd == 'window' or cmd == 'savewindows' or cmd == 'restorewindows' then
        local sub = args[2] and string.lower(args[2]) or (cmd == 'savewindows' and 'save' or (cmd == 'restorewindows' and 'restore' or 'help'))
        if sub == 'save' then
            runtime.saveWindowPositions(false)
        elseif sub == 'restore' or sub == 'load' then
            local count = runtime.triggerRestoreWindows()
            print(string.format('\ag[Triune]\ax Restored window positions (%d configured).', count))
        elseif sub == 'reset' or sub == 'default' or sub == 'defaults' then
            runtime.resetWindowPositionsToDefault()
        else
            print('\ag[Triune Window Positions]\ax:')
            print('  \ag/ac winpos save\ax (or \ag/ac savewindows\ax) - Save current open window positions')
            print('  \ag/ac winpos restore\ax (or \ag/ac restorewindows\ax) - Restore saved window positions')
            print('  \ag/ac winpos reset\ax - Reset all window positions to desktop defaults')
        end
    elseif cmd == 'clearlockouts' or cmd == 'unlock' or (cmd == 'clear' and (args[2] and (string.lower(args[2]) == 'lockouts' or string.lower(args[2]) == 'locks' or string.lower(args[2]) == 'all'))) then
        if castTracker and castTracker.clear then
            castTracker.clear()
            print('\ag[Triune]\ax Cleared all active spell lockouts, target backoffs, and mob immunities.')
        end
    elseif cmd == 'ma' or cmd == 'mainassist' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'target' or sub == 'add' then
            runtime.addCustomAssistTarget()
        elseif sub == 'clear' or sub == 'none' then
            ctrl.ma_id = 0
            ctrl.ma_name = ''
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Main Assist cleared.')
        elseif sub == 'remove' or sub == 'delete' then
            local removeArg = args[3]
            runtime.removeCustomAssist(removeArg)
        elseif sub ~= '' then
            local numId = tonumber(sub)
            if numId and numId > 0 then
                ctrl.ma_id = numId
                pcall(function()
                    local s = mq.TLO.Spawn(numId)
                    if s and s() then ctrl.ma_name = s.CleanName() or '' end
                end)
            else
                local nameArg = table.concat(args, ' ', 2)
                ctrl.ma_name = nameArg
                local sId = findMaPcId(nameArg)
                ctrl.ma_id = sId or 0
            end
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Main Assist set to "%s" (ID: %d).', ctrl.ma_name or '', ctrl.ma_id or 0))
        else
            local maDisp = (ctrl.ma_name and ctrl.ma_name ~= '') and ctrl.ma_name or '(None)'
            print(string.format('\ag[Triune]\ax Current Main Assist: %s (ID: %d). Usage: /ac ma [target|clear|<name>|<id>]', maDisp, ctrl.ma_id or 0))
        end
    elseif cmd == 'xtardist' or cmd == 'xtar' or cmd == 'xtarrange' then
        local val = tonumber(args[2])
        if val then
            ctrl.xtar_nav_dist = math.max(25, math.min(300, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Max XTarget Chase Range set to %d units.', ctrl.xtar_nav_dist))
        else
            print(string.format('\ag[Triune]\ax Current Max XTarget Chase Range: %d units. (usage: /ac xtardist [25-300])', ctrl.xtar_nav_dist or 150))
        end
    elseif cmd == 'selfdefense' or cmd == 'assistdefend' or cmd == 'defend' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrl.assist_self_defense = true
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Assist Self-Defense When Attacked: \agENABLED\ax.')
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrl.assist_self_defense = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Assist Self-Defense When Attacked: \arDISABLED\ax.')
        else
            ctrl.assist_self_defense = ctrl.assist_self_defense == false
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Assist Self-Defense When Attacked: %s.',
                ctrl.assist_self_defense and '\agENABLED\ax' or '\arDISABLED\ax'))
        end
    elseif cmd == 'manualstick' or cmd == 'stick' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrl.manual_stick = true
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrl.manual_stick = false
        else
            ctrl.manual_stick = ctrl.manual_stick == false
        end
        if not ctrl.manual_stick and runtime.stopMoving then runtime.stopMoving() end
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Manual Mode Stick to Target: %s.',
            ctrl.manual_stick and '\agENABLED\ax' or '\arDISABLED\ax (you drive; attacks/casts only when the NPC is in reach)'))
    elseif cmd == 'manualnav' or cmd == 'autonav' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrl.manual_auto_nav = true
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrl.manual_auto_nav = false
        else
            ctrl.manual_auto_nav = not ctrl.manual_auto_nav
        end
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Manual Mode Auto-Nav to Selected Target: %s.',
            ctrl.manual_auto_nav and '\agENABLED\ax' or '\arDISABLED\ax'))
    elseif cmd == 'assistbehind' or cmd == 'behind' or cmd == 'posbehind' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrl.assist_behind = true
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Assist Mode Position Behind NPC: \agENABLED\ax.')
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrl.assist_behind = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Assist Mode Position Behind NPC: \arDISABLED\ax.')
        else
            ctrl.assist_behind = ctrl.assist_behind == false
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Assist Mode Position Behind NPC: %s.',
                ctrl.assist_behind and '\agENABLED\ax' or '\arDISABLED\ax'))
        end
    elseif cmd == 'pausezone' or cmd == 'zonepause' or cmd == 'pauseonzone' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrl.pause_on_zone = true
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Pause On Zone: \agENABLED\ax (autocombat pauses when entering a new zone).')
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrl.pause_on_zone = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Pause On Zone: \arDISABLED\ax (autocombat continues across zones).')
        else
            ctrl.pause_on_zone = ctrl.pause_on_zone == false
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Pause On Zone: %s.',
                ctrl.pause_on_zone and '\agENABLED\ax' or '\arDISABLED\ax'))
        end
    elseif cmd == 'fov' or cmd == 'setfov' or cmd == 'camfov' then
        local sub = args[2] and string.lower(args[2]) or ''
        local num = tonumber(args[2])
        if num then
            if not runtime.fovLoaded() then
                print('\ay[Triune WARNING]\ax MQ2FOV plugin is not loaded! Cannot execute /fov (load via \ay/plugin mq2fov\ax).')
            end
            if num < 50 then num = 50 end
            if num > 150 then num = 150 end
            ctrl.fov = math.floor(num)
            ctrl.fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Field of View set to \ag%d\ax units (Maintain on Zone: ENABLED).', ctrl.fov))
        elseif sub == 'on' or sub == '1' or sub == 'enable' or sub == 'true' then
            if not runtime.fovLoaded() then
                print('\ay[Triune WARNING]\ax MQ2FOV plugin is not loaded! Cannot execute /fov (load via \ay/plugin mq2fov\ax).')
            end
            ctrl.fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Maintain Field of View: \agENABLED\ax (%d units).', ctrl.fov or 100))
        elseif sub == 'off' or sub == '0' or sub == 'disable' or sub == 'false' then
            ctrl.fov_enabled = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Maintain Field of View: \arDISABLED\ax.')
        else
            print(string.format('\ag[Triune]\ax Field of View: %d units (Maintain on Zone: %s%s). Usage: /ac fov [50-150|on|off]',
                ctrl.fov or 100, ctrl.fov_enabled and '\agENABLED\ax' or '\arDISABLED\ax',
                runtime.fovLoaded() and '' or ' -- \arMQ2FOV NOT LOADED\ax'))
        end
    elseif cmd == 'chasedist' or cmd == 'chase' or cmd == 'chaserange' or cmd == 'followdist' then
        local arg2 = args[2] and string.lower(args[2]) or ''
        local val = tonumber(arg2)
        if val then
            ctrl.chase_dist = math.max(5, math.min(100, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Chase Distance from Main Assist set to %d ft.', ctrl.chase_dist))
        elseif arg2 == 'on' or arg2 == '1' or arg2 == 'true' then
            ctrl.chase = true
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Chase MA (Auto-Follow): \agENABLED\ax.')
        elseif arg2 == 'off' or arg2 == '0' or arg2 == 'false' then
            ctrl.chase = false
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Chase MA (Auto-Follow): \arDISABLED\ax.')
        else
            print(string.format('\ag[Triune]\ax Chase MA is %s (Chase Distance: %d ft). Usage: /ac chasedist [5-100] or /ac chase [on|off|<dist>]',
                ctrl.chase and '\agENABLED\ax' or '\arDISABLED\ax', ctrl.chase_dist or 15))
        end
    elseif cmd == 'clearcursor' or cmd == 'autoinv' or cmd == 'cursor' then
        clearCursor()
    elseif cmd == 'compact' or cmd == 'mini' then
        ctrl.compact = not ctrl.compact
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Compact Mini mode %s.', ctrl.compact and 'ENABLED' or 'DISABLED'))
    elseif cmd == 'pullcon' or cmd == 'con' or cmd == 'confilter' then
        ctrl.pull_con_filter = ctrl.pull_con_filter or {}
        local arg2 = args[2] and string.lower(args[2]) or ''
        local arg3 = args[3] and string.lower(args[3]) or ''
        if arg2 == 'preset' then
            if arg3 == 'hostile' then
                for _, c in ipairs(MODES.PULL_CON_LIST) do
                    ctrl.pull_con_filter[c] = (c == 'Scowling' or c == 'Threateningly' or c == 'Dubious' or c == 'Apprehensive')
                end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Hostile Only')
            elseif arg3 == 'indifferent' then
                for _, c in ipairs(MODES.PULL_CON_LIST) do
                    ctrl.pull_con_filter[c] = (c == 'Scowling' or c == 'Threateningly' or c == 'Dubious' or c == 'Apprehensive' or c == 'Indifferent')
                end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Hostile + Indifferent')
            elseif arg3 == 'all' or arg3 == 'selectall' then
                for _, c in ipairs(MODES.PULL_CON_LIST) do ctrl.pull_con_filter[c] = true end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Select All')
            elseif arg3 == 'clear' or arg3 == 'none' then
                for _, c in ipairs(MODES.PULL_CON_LIST) do ctrl.pull_con_filter[c] = false end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Clear All')
            else
                print('\ay[Triune]\ax usage: /ac pullcon preset [all|hostile|indifferent|none]')
            end
            runtime.saveLoadout(true)
        elseif arg2 ~= '' then
            local targetCon = nil
            for _, c in ipairs(MODES.PULL_CON_LIST) do
                if string.lower(c) == arg2 then
                    targetCon = c; break
                end
            end
            if targetCon then
                local enable = true
                if arg3 == 'off' or arg3 == '0' or arg3 == 'false' then enable = false end
                ctrl.pull_con_filter[targetCon] = enable
                runtime.saveLoadout(true)
                print(string.format('\ag[Triune]\ax Puller Faction Con "%s" set to %s.', targetCon,
                    enable and 'ENABLED' or 'DISABLED'))
            else
                print('\ay[Triune]\ax unknown consideration tier: ' .. tostring(args[2]))
            end
        else
            print('\ag[Triune]\ax --- Puller Faction Considerations ---')
            for _, c in ipairs(MODES.PULL_CON_LIST) do
                print(string.format('  %s: %s', c, ctrl.pull_con_filter[c] and '\agENABLED\ax' or '\arDISABLED\ax'))
            end
            print(
                '\ay[Triune]\ax usage: /ac pullcon [con_name] [on|off] OR /ac pullcon preset [all|hostile|indifferent|none]')
        end
    elseif cmd == 'wp' or cmd == 'waypoint' or cmd == 'waypoints' then
        ctrl.waypoints = ctrl.waypoints or {}
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'add' then
            local wpName = args[3] or ''
            for i = 4, #args do wpName = wpName .. ' ' .. args[i] end
            local wpNum, name, x, y, z = runtime.wpAdd(wpName)
            if wpNum then
                print(string.format('\ag[Triune]\ax Added Waypoint #%d "%s" @ loc (Y:%.1f, X:%.1f, Z:%.1f)', wpNum, name,
                    y, x, z))
            else
                print('\ar[Triune]\ax Failed to add waypoint -- location unavailable.')
            end
        elseif sub == 'clear' or sub == 'reset' then
            runtime.wpClear()
            print('\ag[Triune]\ax Cleared all waypoints.')
        elseif sub == 'delete' or sub == 'del' or sub == 'remove' then
            local idx = tonumber(args[3])
            if idx and runtime.wpDelete(idx) then
                print(string.format('\ag[Triune]\ax Deleted Waypoint #%d.', idx))
            else
                print('\ay[Triune]\ax usage: /ac wp delete [index]')
            end
        elseif sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.use_waypoints = true
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Waypoint Patrol ENABLED.')
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.use_waypoints = false
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Waypoint Patrol DISABLED.')
        elseif sub == 'toggle' then
            ctrl.use_waypoints = not ctrl.use_waypoints
            if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Waypoint Patrol %s.', ctrl.use_waypoints and 'ENABLED' or 'DISABLED'))
        elseif sub == 'radius' or sub == 'arrival' then
            local r = tonumber(args[3])
            if r and r >= 5 and r <= 100 then
                ctrl.waypoint_radius = r
                runtime.saveLoadout(true)
                print(string.format('\ag[Triune]\ax Waypoint Arrival Radius set to %d.', r))
            else
                print('\ay[Triune]\ax usage: /ac wp radius [5-100]')
            end
        elseif sub == 'scan' or sub == 'scanradius' then
            local r = tonumber(args[3])
            if r and r >= 20 and r <= 500 then
                ctrl.waypoint_scan_radius = r
                runtime.saveLoadout(true)
                print(string.format('\ag[Triune]\ax Waypoint NPC Scan Radius set to %d.', r))
            else
                print('\ay[Triune]\ax usage: /ac wp scan [20-500]')
            end
        elseif sub == 'list' or sub == 'show' or sub == '' then
            print('\ag[Triune]\ax --- Puller Waypoint Patrol Route ---')
            print(string.format('  Patrol Status: %s | Active Target: #%d | Arrival Radius: %d | Scan Radius: %d',
                ctrl.use_waypoints and '\agENABLED\ax' or '\arDISABLED\ax', ctrl.current_waypoint_idx or 1,
                ctrl.waypoint_radius or 20, ctrl.waypoint_scan_radius or 100))
            if #ctrl.waypoints == 0 then
                print('  \ayNo waypoints defined. Use /ac wp add [name] to add locations.\ax')
            else
                for idx, wp in ipairs(ctrl.waypoints) do
                    local isCur = ((ctrl.current_waypoint_idx or 1) == idx) and ' \ag[NEXT]\ax' or ''
                    print(string.format('  #%d: "%s" (Y:%.1f, X:%.1f, Z:%.1f) dist: %.0f%s',
                        idx, wp.name or ('WP ' .. idx), wp.y or 0, wp.x or 0, wp.z or 0, distToLoc(wp.x, wp.y, wp.z),
                        isCur))
                end
            end
        else
            print(
            '\ay[Triune]\ax usage: /ac wp [add [name]|clear|delete [idx]|on|off|toggle|radius [5-100]|scan [20-500]|list]')
        end
    elseif cmd == 'style' or cmd == 'combatstyle' then
        ctrl.combat_style = 'Melee'
        runtime.saveLoadout(true)
        print('\ag[Triune]\ax Combat style is set to: \agMelee\ax (range ' .. tostring(ctrl.melee_dist or 14) .. ')')
    elseif cmd == 'range' or cmd == 'meleerange' or cmd == 'dist' then
        local val = tonumber(args[2])
        if val then
            ctrl.melee_dist = math.max(5, math.min(50, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Max Melee Distance set to %d units.', ctrl.melee_dist))
        else
            print(string.format('\ag[Triune]\ax Current Max Melee Distance: %d units. (usage: /ac range [5-50])', ctrl.melee_dist or 14))
        end
    elseif cmd == 'huntz' or cmd == 'z' then
        local val = tonumber(args[2])
        if val then
            ctrl.hunter_z = math.max(10, math.min(300, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Hunter Max Height Diff (Z) set to %d units.', ctrl.hunter_z))
        else
            print(string.format('\ag[Triune]\ax Current Hunter Max Height Diff (Z): %d units. (usage: /ac huntz [10-300])', ctrl.hunter_z or 75))
        end
    elseif cmd == 'zplane' or cmd == 'huntplane' or cmd == 'floorz' then
        local val = tonumber(args[2])
        if val then
            ctrl.hunter_z_plane = math.max(5, math.min(100, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Hunter Floor Height (Z Plane) set to %d units.', ctrl.hunter_z_plane))
        else
            print(string.format('\ag[Triune]\ax Current Hunter Floor Height (Z Plane): %d units. (usage: /ac zplane [5-100])', ctrl.hunter_z_plane or 15))
        end
    elseif cmd == 'pullhp' or cmd == 'minhp' then
        local val = tonumber(args[2])
        if val then
            ctrl.pull_min_hp_pct = math.max(0, math.min(95, math.floor(val)))
            runtime.saveLoadout(true)
            if ctrl.pull_min_hp_pct == 0 then
                print('\ag[Triune]\ax Min Pull HP % disabled (0% -- pull at any HP).')
            else
                print(string.format('\ag[Triune]\ax Min Pull HP threshold set to %d%% (pause pulling to rest until 100%%).', ctrl.pull_min_hp_pct))
            end
        else
            print(string.format('\ag[Triune]\ax Current Min Pull HP threshold: %d%%. (usage: /ac pullhp [0-95])', ctrl.pull_min_hp_pct or 0))
        end
    elseif cmd == 'preset' or cmd == 'loadout' then
        local sub = args[2] and string.lower(args[2]) or ''
        local name = args[3]
        if sub == 'save' and name and name ~= '' then
            runtime.savePreset(name)
        elseif (sub == 'load' or sub == 'use' or sub == 'set') and name and name ~= '' then
            runtime.loadPreset(name, true)
        elseif sub == 'delete' or sub == 'del' or sub == 'remove' then
            runtime.deletePreset(name)
        elseif sub == 'list' or sub == '' then
            runtime.listPresets()
        else
            print('\ay[Triune]\ax usage: /ac preset [save <name>|load <name>|delete <name>|list]')
        end
    elseif cmd == 'memall' or cmd == 'mem' or cmd == 'remem' then
        runtime.queueMemAll()
    elseif cmd == 'importbar' or cmd == 'import' or cmd == 'importgems' then
        runtime.importCurrentGems()
    elseif runtime.pluginManager and runtime.pluginManager.onCommand(cmd, args) then
        return
    elseif setTriuneMode(args[1], args[2]) then
        return
    else
        print(
            '\ay[Triune]\ax usage: /ac [run|pause|burn|memall|importbar|compact|status|spellbook|cursorui|dps|map|inv|buffbot|net|btn|clearcursor|style|range|zplane|huntz|pullhp|preset|help|pullcon|wp|manual|puller [hunt|camp]|assist [chase|camp|backline]]')
    end
end

mq.unbind('/triune')
mq.bind('/triune', triuneCommand)

mq.unbind('/triunerun')
mq.bind('/triunerun', runtime.triuneToggle)

mq.unbind('/ac')
mq.bind('/ac', triuneCommand)

function runtime.autoloadRequiredPlugins()
    local needWait = false
    if not navLoaded() then
        mq.cmd('/plugin mq2nav')
        needWait = true
    end
    if not stickLoaded() then
        mq.cmd('/plugin mq2moveutils')
        needWait = true
    end
    if needWait and mq.delay then
        mq.delay(250, function()
            return navLoaded() and stickLoaded()
        end)
    end
end
runtime.autoloadRequiredPlugins()

-- ============================================================================
-- Critical Hit Floating Text Overlay
-- Migrated to autonomous plugin in TAC/lua/tac/floating_damage.lua (v2.15).
-- ============================================================================

-- Mob slain detection: immediately clear dead target and schedule fast combat tick to acquire next mob
mq.event('TriuneSlain1', 'You have slain #1#!', function(_, mobName)
    local t = mq.TLO.Target
    local isDead = false
    pcall(function()
        if t() then
            local matches = (mobName and t.CleanName() == mobName)
            isDead = matches or t.Dead() or t.Type() == 'Corpse' or (t.State() or '') == 'DEAD'
        end
    end)
    if isDead then
        runtime.clearTarget()
        runtime.lastTick = 0
    end
end)

mq.event('TriuneSlain2', '#1# has been slain by #*#!', function(_, mobName)
    local t = mq.TLO.Target
    local isDead = false
    pcall(function()
        if t() then
            local matches = (mobName and t.CleanName() == mobName)
            isDead = matches or t.Dead() or t.Type() == 'Corpse' or (t.State() or '') == 'DEAD'
        end
    end)
    if isDead then
        runtime.clearTarget()
        runtime.lastTick = 0
    end
end)

mq.imgui.init('TriunePluginsUI', UI.drawPlugins)
mq.imgui.init('TriuneAutoCombat', UI.draw)
print('\ag[Triune]\ax loaded v' ..
    VERSION ..
    '. Data: ' ..
    (DATA_OK and 'triune_data.lua OK' or 'MISSING -- run extract_spells.py') ..
    '. Use /ac run | /ac pause | /ac status | /ac spellbook | /ac <mode>. /lua stop triune to exit.')
function runtime.checkStartupPluginStatus()
    if not navLoaded() then
        mq.cmd('/popup [Triune] WARNING: MQ2Nav is NOT loaded! Load via /plugin mq2nav')
        print('\ar[Triune WARNING]\ax MQ2Nav plugin is not loaded! Navigation, chase, and pathing require MQ2Nav. Load it using: \ay/plugin mq2nav\ax')
    elseif not navMeshLoaded() then
        local curZone = mq.TLO.Zone.ShortName() or 'current zone'
        mq.cmdf('/popup [Triune] WARNING: No NavMesh for %s!', curZone)
        print(string.format('\ar[Triune WARNING]\ax No NavMesh loaded for zone %s! Pathing and navigation require a valid zone mesh.', curZone))
    end
    if not stickLoaded() then
        mq.cmd('/popup [Triune] WARNING: MQ2MoveUtils is NOT loaded! Load via /plugin mq2moveutils')
        print('\ar[Triune WARNING]\ax MQ2MoveUtils plugin is not loaded! Combat positioning, melee stick, and unstuck require MQ2MoveUtils. Load it using: \ay/plugin mq2moveutils\ax')
    end
end
runtime.checkStartupPluginStatus()
runtime.initPluginManager()

-- ============================================================================
-- Map Visualization Helper
-- ============================================================================

runtime.clearMapRadiusVisuals = function()
    if not runtime.mapLoaded() then return end
    mq.cmd('/maploc remove')
    mq.cmd('/mapfilter pullradius 0')
    mq.cmd('/mapfilter castradius 0')
    runtime.lastMapDraw = { active = false, type = nil, key = '' }
end

runtime.updateMapRadiusVisuals = function()
    if not runtime.mapLoaded() then return end
    if not ctrl.show_map_radius then
        if runtime.lastMapDraw and runtime.lastMapDraw.active then
            runtime.clearMapRadiusVisuals()
        end
        return
    end

    local mode = ctrl.mode
    local submode = ctrl.submode or ''
    local hasWps = ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0
    local zoneShort = ''
    pcall(function() zoneShort = mq.TLO.Zone.ShortName() or '' end)

    local wpsCoordParts = {}
    if hasWps then
        for idx, wp in ipairs(ctrl.waypoints) do
            wpsCoordParts[#wpsCoordParts + 1] = string.format('%d:%.1f,%.1f,%.1f', idx, wp.x or 0, wp.y or 0, wp.z or 0)
        end
    end
    local wpsKey = table.concat(wpsCoordParts, ';')

    local key = string.format('%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s',
        tostring(mode),
        tostring(submode),
        tostring(ctrl.use_waypoints),
        tostring(ctrl.waypoint_scan_radius or 100),
        tostring(ctrl.waypoint_radius or 20),
        tostring(ctrl.camp_radius or 100),
        tostring(ctrl.hunter_radius or 1500),
        tostring(ctrl.hunter_combat_radius or 0),
        tostring(ctrl.current_waypoint_idx or 1),
        tostring(ctrl.xtar_nav_dist or 150),
        ctrl.camp_loc and
        string.format('%.1f,%.1f,%.1f', ctrl.camp_loc.x or 0, ctrl.camp_loc.y or 0, ctrl.camp_loc.z or 0) or 'nocamp',
        ctrl.hunter_combat_loc and
        string.format('%.1f,%.1f,%.1f', ctrl.hunter_combat_loc.x or 0, ctrl.hunter_combat_loc.y or 0,
            ctrl.hunter_combat_loc.z or 0) or 'noanchor',
        zoneShort,
        wpsKey)

    if runtime.lastMapDraw and runtime.lastMapDraw.active and runtime.lastMapDraw.key == key then
        return -- State unchanged; do nothing
    end

    -- Clear all previous map overlays before applying new one
    runtime.clearMapRadiusVisuals()

    if mode == 'Puller' and hasWps then
        runtime.syncWaypointMapLines(zoneShort)

        -- 1. Dynamic Scan Radius circle following the player
        local scanRad = ctrl.waypoint_scan_radius or 100
        if scanRad > 0 then
            mq.cmd('/mapfilter castradius color 0 255 0')
            mq.cmd('/mapfilter castradius show')
            mq.cmdf('/mapfilter castradius %d', scanRad)
        end

        -- 2. Draw arrival radius markers for all waypoints in the patrol route
        for idx, wp in ipairs(ctrl.waypoints) do
            if wp and wp.x and wp.y and wp.z then
                local isNext = ((ctrl.current_waypoint_idx or 1) == idx)
                local rCol = isNext and '255 215 0' or '0 200 255'
                local label = isNext and ('>> ' .. (wp.name or ('WP ' .. idx))) or (wp.name or ('WP ' .. idx))
                mq.cmdf('/maploc %f %f %f radius %d rcolor %s color %s label %s',
                    wp.y, wp.x, wp.z, ctrl.waypoint_radius or 20, rCol, rCol, label)
            end
        end

        -- 3. If in Camp submode and camp location exists, draw Camp anchor
        if submode == 'Camp' and ctrl.camp_loc then
            mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label Camp',
                ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z, ctrl.camp_radius or 100)
        end

        runtime.lastMapDraw = {
            active = true,
            type = 'waypoints',
            key = key
        }
        return
    end

    -- Non-waypoint modes: Clean up any leftover waypoint lines on map file
    runtime.syncWaypointMapLines(zoneShort)

    if mode == 'Manual' then
        if ctrl.camp_loc then
            mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label Camp',
                ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z, ctrl.camp_radius or 100)
        else
            mq.cmd('/mapfilter pullradius color 0 255 0')
            mq.cmd('/mapfilter pullradius show')
            mq.cmdf('/mapfilter pullradius %d', ctrl.camp_radius or 100)
        end
    elseif mode == 'Puller' then
        if submode == 'Camp' then
            if ctrl.camp_loc then
                mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label Camp',
                    ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z, ctrl.camp_radius or 100)
            else
                mq.cmd('/mapfilter pullradius color 0 255 0')
                mq.cmd('/mapfilter pullradius show')
                mq.cmdf('/mapfilter pullradius %d', ctrl.camp_radius or 100)
            end
        else -- Submode 'Hunt'
            if ctrl.hunter_combat_loc and (ctrl.hunter_combat_radius or 0) > 0 then
                mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label Anchor',
                    ctrl.hunter_combat_loc.y, ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.z,
                    ctrl.hunter_combat_radius)
            else
                mq.cmd('/mapfilter castradius color 255 0 0')
                mq.cmd('/mapfilter castradius show')
                mq.cmdf('/mapfilter castradius %d', ctrl.hunter_radius or 1500)
            end
        end
    elseif mode == 'Assist' then
        if submode == 'Camp' and ctrl.camp_loc then
            mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label Camp',
                ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z, ctrl.xtar_nav_dist or 150)
        end
    end

    runtime.lastMapDraw = {
        active = true,
        type = mode,
        key = key
    }
end

-- ============================================================================
-- Main loop
-- ============================================================================
local function runMainLoop()
    while open do
        mq.doevents()
        local nm = mq.TLO.Me.CleanName()
        if nm and nm ~= '' and nm ~= myName then
            myName = nm
            runtime.loadAll()
            runtime.onCharacterChanged()
            if runtime.pluginManager and runtime.pluginManager.restartAll then
                runtime.pluginManager.restartAll() -- ctrl was replaced: re-seed plugin defaults + flags
            end
            UI.resetTracker()
            -- camp restored from a save; no map circle is drawn
            reconcileSungBuffs()                                      -- don't re-sing bard buffs that are already up
            reconcilePets()                                           -- don't re-summon pets that are already out
            runtime.lastSig = loadoutSig(); runtime.autoDirty = false -- baseline; don't save what we just loaded
            if ctrl.fov_enabled and runtime.applyFov then
                runtime.applyFov()
            end
        end
        local curZone = mq.TLO.Zone.ShortName()
        if curZone and curZone ~= '' and curZone ~= runtime.lastZoneShort then
            local prevZone = runtime.lastZoneShort
            runtime.lastZoneShort = curZone
            if prevZone ~= nil then
                runtime.sungBuffs = {}; runtime.npcCastCounts = {}; runtime.npcSpellApplied = {}; runtime.npcSpellLastCast = {}; if runtime.onZoned then runtime.onZoned() end
                if runtime.pluginManager and runtime.pluginManager.onZoned then runtime.pluginManager.onZoned(curZone) end
            end
            reconcilePets()
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            if navLoaded() and not navMeshLoaded() then
                mq.cmdf('/popup [Triune] WARNING: No NavMesh for %s!', curZone)
                print(string.format('\ar[Triune WARNING]\ax No NavMesh loaded for zone "%s"! Pathing and navigation require a valid zone mesh.', curZone))
            end
        end
        if reDetectRequested then
            reDetectRequested = false
            local detected = detectClasses(true) -- safe here -- main loop coroutine can yield/delay
            if detected then myClasses = detected end
        end
        -- (Cursor items are cleared on-demand prior to actions/mems or post-cast completion)
        if runtime.pendingCursorClearAt and os.clock() >= runtime.pendingCursorClearAt then
            runtime.pendingCursorClearAt = nil
            clearCursor()
        end
        if runtime.pendingFovAt and os.clock() >= runtime.pendingFovAt then
            runtime.pendingFovAt = nil
            if ctrl.fov_enabled and runtime.applyFov then
                runtime.applyFov()
            end
        end
        runtime.updateMapRadiusVisuals()
        if runtime.pluginManager and runtime.pluginManager.tick then
            runtime.pluginManager.tick()
        end
        -- drain one queued spell-mem per pass, out of combat, while stationary, and while not casting
        local memmed = false
        if not isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not (runtime.hasDowntimeAggroThreat and runtime.hasDowntimeAggroThreat()) then
            local maxG = getNumGems()
            local slot = nil
            for s = 1, maxG do
                if runtime.pendingMem[s] then
                    slot = s
                    break
                end
            end
            if slot then
                local name = runtime.pendingMem[slot]
                runtime.pendingMem[slot] = nil
                runtime.tryMem(slot, name) -- verifies + reports; blocks briefly while it lands
                memmed = true
            end
        end
        if ctrl.running and not memmed and (os.clock() - runtime.lastTick) > 0.4 then
            local ok, err = pcall(combatTick)
            if not ok and err then
                print('\ar[Triune error]\ax combatTick failed: ' .. tostring(err))
            end
            if runtime.pluginManager and runtime.pluginManager.onCombatTick then
                pcall(function()
                    local tId = 0
                    pcall(function() tId = mq.TLO.Target.ID() or 0 end)
                    runtime.pluginManager.onCombatTick(tId)
                end)
            end
            runtime.lastTick = os.clock()
            runtime.wasRunning = true
        elseif not ctrl.running then
            if runtime.wasRunning then
                runtime.wasRunning = false
                if runtime.fullStop then runtime.fullStop() end
            end
        end

        -- auto-save: persist the loadout ~1.5s after any change (no Save click needed).
        -- loadoutSig() walks every gem/AA/disc/action and all ~250 ctrl keys, so only
        -- re-check it once a second; the save itself is debounced 1.5s anyway.
        local nowClk = os.clock()
        if (nowClk - (runtime.lastSigCheckAt or 0)) >= 1.0 then
            runtime.lastSigCheckAt = nowClk
            local sig = loadoutSig()
            if sig ~= runtime.lastSig then
                runtime.lastSig = sig; runtime.autoDirty = true; runtime.autoDirtyAt = nowClk
            end
        end
        if runtime.autoDirty and (os.clock() - runtime.autoDirtyAt) > 1.5 then
            runtime.saveLoadout(true); runtime.autoDirty = false
        end

        mq.delay(memmed and 200 or 150)
    end
end

runMainLoop()
if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
runtime.saveLoadout(true)
