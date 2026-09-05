---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune AutoCombat -- Gem & AA loadout builder (PHASE 1: UI + data + persistence)
-- ----------------------------------------------------------------------------
-- Standalone MacroQuest ImGui script. Run with:  /lua run triune
-- Loads triune_data.lua (produced by extract_spells.py) from your MQ config dir
-- for the real, era-correct spell + activated-AA lists. Saves your loadout to
-- triune_loadout.lua next to it.
--
-- This phase builds the LOADOUT (which spell/AA per slot, target, and % to fire
-- at). Wiring the loadout into actual casting is phase 2 (it maps onto the
-- existing autocombat engine: set_caster_target + check_conditions).
--
-- NOTE: written without an in-game test pass. If it errors on first run, paste
-- the console line and it's a quick fix.
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
local VERSION           = '2.01'
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
    if c.nav_reverse_breadcrumbs == nil then c.nav_reverse_breadcrumbs = true end
    if c.nav_max_path_ratio == nil then c.nav_max_path_ratio = 2.5 end
    if c.nav_proactive_doors == nil then c.nav_proactive_doors = true end
    if c.nav_levitation_clear == nil then c.nav_levitation_clear = true end
    if type(c.zone_hazards) ~= 'table' then c.zone_hazards = {} end
    if type(c.zone_waypoints) ~= 'table' then c.zone_waypoints = {} end
    if type(c.zone_waypoint_presets) ~= 'table' then c.zone_waypoint_presets = {} end

    if c.show_cooldowns == nil then c.show_cooldowns = false end
    if c.cooldown_alpha == nil then c.cooldown_alpha = 0.90 end
    if c.cooldown_locked == nil then c.cooldown_locked = false end
    if c.cooldown_view_mode == nil then c.cooldown_view_mode = 'table' end
    if c.cooldown_sort_by == nil then c.cooldown_sort_by = 'time' end
    if c.cooldown_category == nil then c.cooldown_category = 'All' end
    if c.cooldown_status_filter == nil then c.cooldown_status_filter = 'All' end
    if c.cooldown_compact == nil then c.cooldown_compact = false end
    if c.cooldown_show_inline_edit == nil then c.cooldown_show_inline_edit = false end

    if c.auto_spend_aa == nil then c.auto_spend_aa = false end
    if c.auto_spend_aa_threshold == nil then c.auto_spend_aa_threshold = 100 end
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
    if c.downtime_buffing == nil then c.downtime_buffing = true end
    if c.pause_on_zone == nil then c.pause_on_zone = true end
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
        running              = false,
        mode                 = 'Manual',
        submode              = 'Hunt',
        manual_auto_xtarget  = true,
        pull_style           = 'Melee',
        pull_spell           = '',
        pull_spell_gem       = 1,
        pull_engage_dist     = 100,
        pull_stand_back      = false,
        xtar_nav_dist        = 150,
        ignore_distant_xtargets = false,
        combat_style         = 'Melee',
        melee_dist           = 14,
        ranged_dist          = 40,
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
        show_map_radius          = true,
        show_crit_floaters       = true,
        show_cooldowns           = false,
        cooldown_alpha           = 0.90,
        cooldown_locked          = false,
        cooldown_view_mode       = 'table',
        cooldown_sort_by         = 'time',
        cooldown_category        = 'All',
        cooldown_status_filter   = 'All',
        cooldown_compact         = false,
        cooldown_show_inline_edit = false,
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
    pullState = 'IDLE',
    pullTargetId = 0,
    pullHpRest = false,
    deathGuardFired = false,
    medBreakActive = false,
    pullBreadcrumbs = {},
    activeDetour = nil,
    lastProactiveDoorAt = 0,
    lastLevClearAt = 0,
    -- This server's custom "#attackmode ranged"/"#attackmode melee" toggle
    -- controls whether standard auto-attack (/attack on) swings a melee
    -- weapon or fires a bow -- it's independent of MQ's Me.AutoFire TLO,
    -- which stays false the whole time under this scheme. We track the
    -- server's own confirmation ("Attack mode changed to: Ranged"/"Melee",
    -- captured below by the TriuneAttackModeChanged event) as the functional
    -- equivalent of Me.AutoFire for combat_style == 'Ranged'. Assumed Melee
    -- until the server tells us otherwise (a fresh login/zone-in defaults
    -- to melee attack mode).
    PURE_MELEE = { War = true, WAR = true, Mnk = true, MNK = true, Rog = true, ROG = true, Ber = true, BER = true },
    serverAttackMode = 'Melee',
    lastAttackModeCmdAt = 0,
    -- Under server Ranged attack mode, /attack behaves as a pure on/off
    -- toggle rather than "start attacking my current target": if it's
    -- already sitting "on" from a previous mob, sending /attack on again
    -- for a new target is a no-op and the character never actually fires,
    -- even though Me.Combat() keeps reporting true. ensureRangedAutoAttack()
    -- uses this field to detect a target change and force a real
    -- off-then-on cycle (blocking briefly via mq.delay) instead of trusting
    -- the current toggle state.
    lastRangedAttackTargetId = 0,
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
    lastAutoSpendAAAt = 0,
    lastAutoSummonAt = 0,
    pendingCursorClearAt = nil,
    ignoreList = {},
    pullList = {},
    ignoreInput = '',
    pullInput = '',
    conCache = {},
    spellbookSetCache = nil,
    lastSpellbookCacheTime = 0,
    hasAACache = {},
    scannedAAs = nil,
    scannedAAMap = nil,
    lastAAScanAt = 0,
    filteredSortedAAs = nil,
    aaFilterDirty = true,
    lastObservedAAPointsSpent = nil,
    lastObservedAAPoints = nil,
    pendingPostTrainScanAt = nil,
    knownDiscSet = nil,
    discExpires = {},
    discCooldown = {},
    filteredSpellsCache = {},
    gemSyncWarned = {},
    lastGemSyncCheckAt = 0,
    colN = 0,
    varN = 0,
    critFloaters = {},
    cooldownSearch = '',
    isSwitchingSpells = false,
    switchingSlot = 0,
    switchingSpellName = nil,
    lastDowntimeSwapAt = {},
    interruptedSwap = nil
}

local petState = {
    myPets = {},
    lastObservedId = 0,
    lastCastCls = nil,
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
    combatStallSince = nil,
    lastStuckRecoveryAt = nil,
    lastCombatStallRecoveryAt = nil,
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
        'has Poison/Disease', 'has Curse', 'has Corruption', 'Aggro on Me', 'my Aggro >=',
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

function runtime.classPlausible(abbr)
    if not abbr or type(abbr) ~= 'string' then return false end
    if DATA and DATA.spells and DATA.spells[abbr] and #DATA.spells[abbr] > 0 then
        return true
    end
    for _, a in ipairs(ALL_ABBR) do
        if a == abbr then return true end
    end
    return false
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
    local ok, res = pcall(function() return mq.TLO.Me.CombatAbility(nm)() end)
    return (ok and res ~= nil)
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
    local ok, s = pcall(function() return mq.TLO.Spawn(id) end)
    if not ok or not s or not s() then return false end
    local dead, tp, state = false, '', ''
    pcall(function() dead = s.Dead() end)
    pcall(function() tp = s.Type() end)
    pcall(function() state = s.State() end)
    return (not dead) and (tp ~= 'Corpse') and (state ~= 'DEAD')
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
        local curPetId = mq.TLO.Me.Pet.ID() or 0
        local sid = s.ID() or 0
        if curPetId > 0 and sid == curPetId then
            isMine = true
            return
        end

        local m = s.Master
        if m and m() and (m.ID() or 0) == myId then
            isMine = true
            return
        end

        local o = s.Owner
        if o and o() and (o.ID() or 0) == myId then
            isMine = true
            return
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
    end)
    return isMine
end

-- Collects and returns all living spawn IDs belonging to the player (multi-pet support for trio classes)
local function getAllMyPets()
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

    if petState and type(petState.myPets) == 'table' then
        for k, petId in pairs(petState.myPets) do
            if petId and petId > 0 then
                if isSpawnAlive(petId) and isSpawnMyPet(petId) then
                    addPet(petId)
                else
                    petState.myPets[k] = nil
                end
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

local function detectPetClassFromSpawn(s)
    if not s or not s() then return nil end
    local cname = ''
    local race = ''
    pcall(function()
        cname = string.lower(s.CleanName() or '')
        race = string.lower(s.Race() or '')
    end)
    if cname:find('warder', 1, true) then return 'Bst' end
    if race:find('animation', 1, true) or cname:find('animation', 1, true) then return 'Enc' end
    if race:find('elemental', 1, true) then return 'Mag' end
    if race:find('skeleton', 1, true) or race:find('spectre', 1, true) or race:find('zombie', 1, true) then return 'Nec' end
    if cname:find('spirit wolf', 1, true) then return 'Shm' end
    return nil
end

local function reconcilePets()
    local petClassList = {}
    for _, c in ipairs(myClasses) do
        if petState.PET_CLASSES[c] then petClassList[#petClassList + 1] = c end
    end
    if #petClassList == 0 then return end

    local assigned = 0
    local allLivingPets = getAllMyPets()
    local assignedIds = {}

    -- Pass 1: match by detected class archetype
    for _, pid in ipairs(allLivingPets) do
        if assigned >= #petClassList then break end
        local s = mq.TLO.Spawn(pid)
        if s and s() and not assignedIds[pid] then
            local detCls = detectPetClassFromSpawn(s)
            if detCls and petState.PET_CLASSES[detCls] then
                for _, c in ipairs(petClassList) do
                    if c == detCls and not petState.myPets[c] then
                        petState.myPets[c] = pid
                        assignedIds[pid] = true
                        assigned = assigned + 1
                        petState.lastObservedId = pid
                        break
                    end
                end
            end
        end
    end

    -- Pass 2: assign remaining pets in order to remaining unassigned pet classes
    for _, pid in ipairs(allLivingPets) do
        if assigned >= #petClassList then break end
        if not assignedIds[pid] then
            for _, c in ipairs(petClassList) do
                if not petState.myPets[c] then
                    petState.myPets[c] = pid
                    assignedIds[pid] = true
                    assigned = assigned + 1
                    petState.lastObservedId = pid
                    break
                end
            end
        end
    end

    if assigned > 0 then
        print('\ag[Triune]\ax found ' .. assigned .. ' existing pet(s) -- tracking ' .. assigned .. ' pet(s).')
    end
end

local function getMultiPetList()
    local petSlots = {}
    local seenIds = {}

    if petState and type(petState.myPets) == 'table' then
        for k, pid in pairs(petState.myPets) do
            if not pid or pid <= 0 or not isSpawnAlive(pid) then
                petState.myPets[k] = nil
            end
        end
    end

    local allLivingPets = getAllMyPets()

    for i = 1, 3 do
        local cls = myClasses[i]
        if cls then
            local isPetCls = petState.PET_CLASSES[cls] == true
            local petId = petState.myPets[cls]
            if petId and petId > 0 and isSpawnAlive(petId) then
                seenIds[petId] = true
            else
                petId = nil
            end

            if isPetCls and not petId then
                for _, pid in ipairs(allLivingPets) do
                    if not seenIds[pid] then
                        petId = pid
                        seenIds[pid] = true
                        petState.myPets[cls] = pid
                        break
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
            table.insert(extraPets, pid)
        end
    end

    return petSlots, extraPets
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
local function isGroupOrRaidMember(id)
    if not id or id <= 0 then return false end
    if id == mq.TLO.Me.ID() then return true end
    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if myPetId > 0 and id == myPetId then return true end
    if petState and type(petState.myPets) == 'table' then
        for _, petId in pairs(petState.myPets) do
            if petId == id then return true end
        end
    end
    local grpCount = 0
    pcall(function() grpCount = mq.TLO.Group.Members() or 0 end)
    if grpCount > 0 then
        for i = 1, grpCount do
            local m = nil
            pcall(function() m = mq.TLO.Group.Member(i) end)
            if m and m() then
                if (m.ID() or 0) == id then return true end
                local mPet = nil
                pcall(function() mPet = m.Pet end)
                if mPet and mPet() and (mPet.ID() or 0) == id then return true end
            end
        end
    end
    local raidCount = 0
    pcall(function() raidCount = mq.TLO.Raid.Members() or 0 end)
    if raidCount > 0 then
        for i = 1, raidCount do
            local rm = nil
            pcall(function() rm = mq.TLO.Raid.Member(i) end)
            if rm and rm() and (rm.ID() or 0) == id then return true end
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
    if id == mq.TLO.Me.ID() then return true end
    local myPetId = 0
    pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
    if myPetId > 0 and id == myPetId then return true end
    if petState and type(petState.myPets) == 'table' then
        for _, petId in pairs(petState.myPets) do
            if petId == id then return true end
        end
    end
    if isGroupOrRaidMember(id) then return true end

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
isHostileTarget = function(id)
    if not id or id <= 0 then return false end
    if isSpawnPetOrPlayer(id) then return false end

    local s = mq.TLO.Spawn(id)
    if not s or not s() then return false end
    if s.Dead and s.Dead() then return false end

    local stype = ''
    pcall(function() stype = s.Type() or '' end)
    if stype ~= 'NPC' and stype ~= 'Pet' then return false end

    return true
end

local function isXTargetId(id)
    if not id or id <= 0 then return false end
    if isGroupOrRaidMember(id) or isSpawnPetOrPlayer(id) then return false end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) == id
            and not xt.Dead() and (xt.Type() or '') ~= 'Corpse'
            and not (isIgnored and isIgnored(xt.CleanName())) then
            local stype = xt.Type() or ''
            if (stype == 'NPC' or stype == 'Pet') and isHostileTarget(id) then
                return true
            end
        end
    end
    return false
end

local function hasActualNPCXtarget()
    local found = false
    pcall(function()
        local slots = 13
        pcall(function() slots = mq.TLO.Me.XTargetSlots() or 13 end)
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt and xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) and not isGroupOrRaidMember(id) and not isSpawnPetOrPlayer(id) then
                    local stype = xt.Type() or ''
                    if (stype == 'NPC' or stype == 'Pet') and not xt.Dead() and stype ~= 'Corpse'
                        and not (isIgnored and isIgnored(xt.CleanName()))
                        and (not isHostileTarget or isHostileTarget(id)) then
                        found = true
                        return
                    end
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
        local slots = 13
        pcall(function() slots = mq.TLO.Me.XTargetSlots() or 13 end)
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) and not isGroupOrRaidMember(id) and not isSpawnPetOrPlayer(id) then
                    local s = mq.TLO.Spawn(id)
                    if s() then
                        local stype = s.Type() or ''
                        local cname = s.CleanName() or ''
                        local dist = 999
                        local okDist, sDist = pcall(function() return s.Distance3D() or s.Distance() end)
                        if okDist and sDist then dist = sDist end
                        local okZ, sz = pcall(function() return s.Z() end)
                        local zOk = (not maxZ) or (okZ and sz and math.abs(sz - myZ) <= maxZ)
                        if (stype == 'NPC' or stype == 'Pet')
                            and not s.Dead() and stype ~= 'Corpse'
                            and isHostileTarget(id)
                            and dist <= maxDist
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
    if catStr:find('heal') or subcatStr:find('heal') or catStr:find('restore') or subcatStr:find('restore') then
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
            if durObj > 10000 then
                sec = durObj / 1000.0
            else
                sec = durObj
            end
            return
        end

        if type(durObj) == 'table' then
            if durObj.TotalSeconds then
                sec = tonumber(durObj.TotalSeconds) or 0
                if sec > 0 then return end
            end
            if durObj.Raw then
                sec = (tonumber(durObj.Raw) or 0) / 1000.0
                if sec > 0 then return end
            end
            if durObj.Ticks then
                sec = (tonumber(durObj.Ticks) or 0) * 6
                if sec > 0 then return end
            end
        end

        if type(durObj.TotalSeconds) == 'function' then
            local ts = tonumber(durObj.TotalSeconds() or 0) or 0
            if ts > 0 then sec = ts; return end
        elseif type(durObj.TotalSeconds) == 'number' then
            local ts = tonumber(durObj.TotalSeconds or 0) or 0
            if ts > 0 then sec = ts; return end
        end

        if durObj.Raw and type(durObj.Raw) == 'function' then
            local raw = tonumber(durObj.Raw() or 0) or 0
            if raw > 0 then sec = raw / 1000.0; return end
        end

        if durObj.Ticks and type(durObj.Ticks) == 'function' then
            local t = tonumber(durObj.Ticks() or 0) or 0
            if t > 0 then sec = t * 6; return end
        end

        if type(durObj) == 'function' or durObj() ~= nil then
            local v = tonumber(durObj()) or 0
            if v > 1000 then
                sec = v / 1000.0
            elseif v > 0 and v <= 500 then
                sec = v * 6
            else
                sec = v
            end
        end
    end)
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
    if s < 60 then return s .. 's' end
    local m = math.floor(s / 60); local r = s % 60
    return (r == 0) and (m .. 'm') or (m .. 'm ' .. r .. 's')
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
                loadout.aas[k] = v
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
        -- Migrate pre-3.6 saves (separate use_melee/use_ranged checkboxes) to the
        -- single combat_style radio -- old saves have no combat_style field at all.
        if not e.control.combat_style then
            ctrl.combat_style = e.control.use_ranged and 'Ranged' or 'Melee'
        end
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
    if not name or name == '' then return end
    loadout.presets = loadout.presets or {}
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

function runtime.loadAll()
    local fn = loadfile(cfg .. '/triune_loadout.lua')
    if not fn then return end
    local ok, t = pcall(fn)
    if ok and type(t) == 'table' then
        ALLDATA = t
        if type(ALLDATA.__ignore) == 'table' then runtime.ignoreList = ALLDATA.__ignore end
        if type(ALLDATA.__pullList) == 'table' then runtime.pullList = ALLDATA.__pullList end
        if type(ALLDATA.__zoneHazards) == 'table' then ctrl.zone_hazards = ALLDATA.__zoneHazards end
        if type(ALLDATA.__zoneWaypoints) == 'table' then ctrl.zone_waypoints = ALLDATA.__zoneWaypoints end
        if type(ALLDATA.__zoneWaypointPresets) == 'table' then ctrl.zone_waypoint_presets = ALLDATA.__zoneWaypointPresets end
    end
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
    if myName then ALLDATA[myName] = runtime.collectEntry() end
    ALLDATA.__ignore = runtime.ignoreList
    ALLDATA.__pullList = runtime.pullList
    ALLDATA.__zoneHazards = ctrl.zone_hazards
    runtime.syncCurrentZoneWaypoints()
    ALLDATA.__zoneWaypoints = ctrl.zone_waypoints
    ALLDATA.__zoneWaypointPresets = ctrl.zone_waypoint_presets
    local f = io.open(cfg .. '/triune_loadout.lua', 'w')
    if not f then return end
    f:write('return '); serialize(ALLDATA, f, 1); f:close()
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

-- ============================================================================
-- Auto-Accept (group / trade / dzadd) whitelist and authorization helpers
-- ============================================================================
function runtime.getAutoAcceptPlayerInfo(entry)
    if type(entry) == 'table' then
        return tostring(entry.name or ''), tonumber(entry.id) or 0
    else
        return tostring(entry or ''), 0
    end
end

function runtime.isAutoAcceptListed(nameOrId)
    if not nameOrId or nameOrId == '' or nameOrId == 0 then return false end
    if not ctrl or not ctrl.auto_accept_names or type(ctrl.auto_accept_names) ~= 'table' then
        if ctrl then ctrl.auto_accept_names = {} end
        return false
    end
    local targetNum = tonumber(nameOrId)
    local targetStr = tostring(nameOrId):lower():gsub('^%s+', ''):gsub('%s+$', '')
    for _, entry in ipairs(ctrl.auto_accept_names) do
        local eName, eId = runtime.getAutoAcceptPlayerInfo(entry)
        if targetNum and targetNum > 0 and eId > 0 and eId == targetNum then
            return true
        end
        if targetStr ~= '' and eName ~= '' and eName:lower() == targetStr then
            return true
        end
    end
    return false
end

function runtime.addAutoAcceptName(nameOrId, optionalId)
    if not nameOrId then return end
    local s = tostring(nameOrId):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return end

    local name = s
    local id = tonumber(optionalId) or 0

    local num = tonumber(s)
    if num and num > 0 and id == 0 then
        id = num
        name = ''
    end

    if mq and mq.TLO and mq.TLO.Spawn then
        pcall(function()
            if id > 0 and name == '' then
                local sp = mq.TLO.Spawn(string.format('id %d', id))
                if sp and sp() and sp.Type() == 'PC' then
                    name = sp.CleanName() or ''
                end
            elseif name ~= '' and id == 0 then
                local sp = mq.TLO.Spawn(string.format('pc =%s', name))
                if not (sp and sp() and (sp.ID() or 0) > 0) then
                    sp = mq.TLO.Spawn(string.format('pc %s', name))
                end
                if sp and sp() and sp.Type() == 'PC' then
                    id = sp.ID() or 0
                end
            end
        end)
    end

    if name == '' and id > 0 then
        name = string.format('Player_%d', id)
    end

    if name == '' and id == 0 then return end

    if not ctrl.auto_accept_names or type(ctrl.auto_accept_names) ~= 'table' then
        ctrl.auto_accept_names = {}
    end

    local found = false
    for _, entry in ipairs(ctrl.auto_accept_names) do
        local eName, eId = runtime.getAutoAcceptPlayerInfo(entry)
        if (id > 0 and eId > 0 and eId == id) or (name ~= '' and eName ~= '' and eName:lower() == name:lower()) then
            if type(entry) == 'table' then
                if id > 0 then entry.id = id end
                if name ~= '' and (entry.name == '' or entry.name:find('^Player_')) then entry.name = name end
            end
            found = true
            break
        end
    end

    if not found then
        table.insert(ctrl.auto_accept_names, { name = name, id = id })
        table.sort(ctrl.auto_accept_names, function(a, b)
            local aName = runtime.getAutoAcceptPlayerInfo(a)
            local bName = runtime.getAutoAcceptPlayerInfo(b)
            return aName:lower() < bName:lower()
        end)
    end

    runtime.saveLoadout(true)
    if id > 0 then
        print(string.format('\ag[Triune Auto-Accept]\ax Added to auto-accept list: \ay%s\ax (ID: \at%d\ax)', name, id))
    else
        print(string.format('\ag[Triune Auto-Accept]\ax Added to auto-accept list: \ay%s\ax', name))
    end
end

function runtime.removeAutoAcceptName(nameOrIdOrEntry)
    if not nameOrIdOrEntry or not ctrl.auto_accept_names then return false end
    local targetNum, targetStr

    if type(nameOrIdOrEntry) == 'table' then
        targetNum = tonumber(nameOrIdOrEntry.id)
        targetStr = nameOrIdOrEntry.name and tostring(nameOrIdOrEntry.name):lower():gsub('^%s+', ''):gsub('%s+$', '')
    else
        targetNum = tonumber(nameOrIdOrEntry)
        targetStr = tostring(nameOrIdOrEntry):lower():gsub('^%s+', ''):gsub('%s+$', '')
    end

    local removedInfo = nil
    for i, entry in ipairs(ctrl.auto_accept_names) do
        local eName, eId = runtime.getAutoAcceptPlayerInfo(entry)
        if (targetNum and targetNum > 0 and eId > 0 and eId == targetNum) or
           (targetStr and targetStr ~= '' and eName ~= '' and eName:lower() == targetStr) then
            removedInfo = { name = eName, id = eId }
            table.remove(ctrl.auto_accept_names, i)
            break
        end
    end

    if removedInfo then
        runtime.saveLoadout(true)
        if removedInfo.id > 0 then
            print(string.format('\ag[Triune Auto-Accept]\ax Removed from auto-accept list: \ay%s\ax (ID: \at%d\ax)', removedInfo.name, removedInfo.id))
        else
            print(string.format('\ag[Triune Auto-Accept]\ax Removed from auto-accept list: \ay%s\ax', removedInfo.name))
        end
        return true
    end
    return false
end

function runtime.clearAutoAcceptNames()
    ctrl.auto_accept_names = {}
    runtime.saveLoadout(true)
    print('\ag[Triune Auto-Accept]\ax Cleared all names from auto-accept list.')
end

function runtime.isAutoAcceptAllowed(senderName, senderId)
    if (not senderName or senderName == '') and (not senderId or senderId == 0) then return false end
    if senderName then
        senderName = tostring(senderName):gsub('^%s+', ''):gsub('%s+$', '')
    end

    -- 1. Accept from anyone
    if ctrl.auto_accept_anyone then return true end

    -- 2. Whitelist match (by ID or case-insensitive Name)
    if senderId and senderId > 0 and runtime.isAutoAcceptListed(senderId) then return true end
    if senderName and senderName ~= '' and runtime.isAutoAcceptListed(senderName) then return true end

    local sLower = senderName and senderName:lower() or ''
    local sIdNum = tonumber(senderId) or 0

    -- If senderId was not passed but senderName is given, attempt resolving in zone
    if sIdNum == 0 and senderName and senderName ~= '' and mq and mq.TLO and mq.TLO.Spawn then
        pcall(function()
            local sp = mq.TLO.Spawn(string.format('pc =%s', senderName))
            if not (sp and sp() and (sp.ID() or 0) > 0) then
                sp = mq.TLO.Spawn(string.format('pc %s', senderName))
            end
            if sp and sp() and (sp.ID() or 0) > 0 then
                sIdNum = sp.ID()
                if runtime.isAutoAcceptListed(sIdNum) then return true end
            end
        end)
    end

    -- 3. Group member match
    if ctrl.auto_accept_group and mq and mq.TLO and mq.TLO.Group then
        local isGrp = false
        pcall(function()
            local memCount = mq.TLO.Group.Members() or 0
            for i = 1, memCount do
                local mem = mq.TLO.Group.Member(i)
                if mem and mem() then
                    local mId = mem.ID and mem.ID() or 0
                    local mName = mem.CleanName and mem.CleanName() or ''
                    if (sIdNum > 0 and mId > 0 and mId == sIdNum) or
                       (sLower ~= '' and mName ~= '' and mName:lower() == sLower) then
                        isGrp = true
                        break
                    end
                end
            end
        end)
        if isGrp then return true end
    end

    -- 4. Guild member match
    if ctrl.auto_accept_guild and mq and mq.TLO and mq.TLO.Me then
        local isGld = false
        pcall(function()
            local myG = mq.TLO.Me.Guild
            local myGuild = (myG and myG() and myG() ~= '') and myG() or nil
            if myGuild then
                local sp = nil
                if sIdNum > 0 then
                    sp = mq.TLO.Spawn(string.format('id %d', sIdNum))
                end
                if not (sp and sp() and (sp.ID() or 0) > 0) and senderName and senderName ~= '' then
                    sp = mq.TLO.Spawn(string.format('pc =%s', senderName))
                    if not (sp and sp() and (sp.ID() or 0) > 0) then
                        sp = mq.TLO.Spawn(string.format('pc %s', senderName))
                    end
                end
                if sp and sp() and sp.Guild then
                    local theirG = sp.Guild()
                    if theirG and theirG ~= '' and theirG:lower() == myGuild:lower() then
                        isGld = true
                    end
                end
            end
        end)
        if isGld then return true end
    end

    return false
end

function runtime.checkAutoAccept()
    if not ctrl.auto_group and not ctrl.auto_trade and not ctrl.auto_dzadd then return end
    local now = os.clock()
    if runtime.lastAutoAcceptCheckAt and (now - runtime.lastAutoAcceptCheckAt) < 0.3 then return end
    runtime.lastAutoAcceptCheckAt = now

    -- 1. Auto Group Invite
    if ctrl.auto_group and mq and mq.TLO and mq.TLO.Me then
        local isInvited = false
        pcall(function() isInvited = mq.TLO.Me.Invited() end)
        if isInvited then
            local inviter = nil
            local inviterId = 0
            pcall(function() inviter = mq.TLO.Me.Inviter() end)
            if inviter and inviter ~= '' then
                pcall(function()
                    local sp = mq.TLO.Spawn(string.format('pc =%s', inviter))
                    if sp and sp() then inviterId = sp.ID() or 0 end
                end)
                if runtime.isAutoAcceptAllowed(inviter, inviterId) then
                    if not runtime.lastAutoGroupAcceptAt or (now - runtime.lastAutoGroupAcceptAt) > 2.0 then
                        runtime.lastAutoGroupAcceptAt = now
                        mq.cmd('/timed 5 /invite')
                        if inviterId > 0 then
                            print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax (ID: \at%d\ax).', inviter, inviterId))
                        else
                            print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax.', inviter))
                        end
                        local confOpen = false
                        pcall(function() confOpen = mq.TLO.Window('ConfirmationDialogBox').Open() end)
                        if confOpen then
                            pcall(function() mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup') end)
                        end
                    end
                end
            end
        end
    end

    -- 2. Auto Trade
    if ctrl.auto_trade and mq and mq.TLO and mq.TLO.Window then
        local tradeOpen = false
        pcall(function() tradeOpen = mq.TLO.Window('TradeWnd').Open() end)
        if tradeOpen then
            local hisReady = false
            local myReady = false
            pcall(function()
                hisReady = mq.TLO.Window('TradeWnd').HisTradeReady()
                myReady = mq.TLO.Window('TradeWnd').MyTradeReady()
            end)
            if hisReady and not myReady then
                local traderName = nil
                local traderId = 0
                pcall(function()
                    local lbl = mq.TLO.Window('TradeWnd').Child('TRDW_HisName')
                    if lbl and lbl() then traderName = lbl.Text() end
                end)
                pcall(function()
                    local tgt = mq.TLO.Target
                    if tgt and tgt() and tgt.Type() == 'PC' then
                        if not traderName or traderName == '' then traderName = tgt.CleanName() end
                        traderId = tgt.ID() or 0
                    end
                end)
                if traderName and traderName ~= '' and traderId == 0 then
                    pcall(function()
                        local sp = mq.TLO.Spawn(string.format('pc =%s', traderName))
                        if sp and sp() then traderId = sp.ID() or 0 end
                    end)
                end
                if ((traderName and traderName ~= '') or traderId > 0) and runtime.isAutoAcceptAllowed(traderName, traderId) then
                    if not runtime.lastAutoTradeAcceptAt or (now - runtime.lastAutoTradeAcceptAt) > 1.5 then
                        runtime.lastAutoTradeAcceptAt = now
                        mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
                        if traderId > 0 then
                            print(string.format('\ag[Triune Auto-Accept]\ax Accepted trade from \ay%s\ax (ID: \at%d\ax).', traderName or 'Unknown', traderId))
                        else
                            print(string.format('\ag[Triune Auto-Accept]\ax Accepted trade from \ay%s\ax.', traderName))
                        end
                    end
                end
            end
        end
    end

    -- 3. Auto DZAdd / Expedition / Task Confirmation
    if ctrl.auto_dzadd and mq and mq.TLO and mq.TLO.Window then
        local confOpen = false
        pcall(function() confOpen = mq.TLO.Window('ConfirmationDialogBox').Open() end)
        if confOpen then
            local text = ''
            pcall(function()
                local out = mq.TLO.Window('ConfirmationDialogBox').Child('CD_TextOutput')
                if out and out() then text = out.Text() or '' end
            end)
            local tLower = text:lower()
            -- Ignore rez prompts or fellowship removals
            if not tLower:find('percent') and not tLower:find('corpse') and not tLower:find('resurrect') and not tLower:find('remove') then
                if tLower:find('expedition') or tLower:find('dynamic zone') or tLower:find('task') or tLower:find('dzadd') or tLower:find('dz') then
                    local candidateName = text:match('^([%a%d]+)%s+has%s+invited%s+you') or text:match('^([%a%d]+)%s+invites%s+you')
                    local candidateId = 0
                    if candidateName and candidateName ~= '' then
                        pcall(function()
                            local sp = mq.TLO.Spawn(string.format('pc =%s', candidateName))
                            if sp and sp() then candidateId = sp.ID() or 0 end
                        end)
                    end
                    local allowed = false
                    if ctrl.auto_accept_anyone then
                        allowed = true
                    elseif candidateName and candidateName ~= '' then
                        allowed = runtime.isAutoAcceptAllowed(candidateName, candidateId)
                    elseif ctrl.auto_accept_names and #ctrl.auto_accept_names > 0 then
                        for _, n in ipairs(ctrl.auto_accept_names) do
                            local eName, eId = runtime.getAutoAcceptPlayerInfo(n)
                            if (eName ~= '' and tLower:find(eName:lower(), 1, true)) or
                               (eId > 0 and tLower:find(tostring(eId), 1, true)) then
                                allowed = true
                                candidateName = eName
                                candidateId = eId
                                break
                            end
                        end
                    end
                    if allowed then
                        if not runtime.lastAutoDzAcceptAt or (now - runtime.lastAutoDzAcceptAt) > 1.5 then
                            runtime.lastAutoDzAcceptAt = now
                            mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup')
                            mq.cmd('/dzaccept')
                            local who = candidateName or (candidateId > 0 and tostring(candidateId)) or 'sender'
                            print(string.format('\ag[Triune Auto-Accept]\ax Accepted expedition / dynamic zone invite from \ay%s\ax.', who))
                        end
                    end
                end
            end
        end
    end
end

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
mq.event('TriuneAAPurchased1', '#*#You have purchased #*#', function()
    runtime.lastAAScanAt = 0
    runtime.aaFilterDirty = true
    if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
end)
mq.event('TriuneAAPurchased2', '#*#You have improved #*#', function()
    runtime.lastAAScanAt = 0
    runtime.aaFilterDirty = true
    if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
end)
mq.event('TriuneAAPurchased3', '#*#You have mastered #*#', function()
    runtime.lastAAScanAt = 0
    runtime.aaFilterDirty = true
    if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
end)

mq.event('TriuneAutoGroupInvite1', '#1# invites you to join a group#*#', function(_, inviter)
    if ctrl and ctrl.auto_group and inviter and runtime.isAutoAcceptAllowed and runtime.isAutoAcceptAllowed(inviter) then
        local now = os.clock()
        if not runtime.lastAutoGroupAcceptAt or (now - runtime.lastAutoGroupAcceptAt) > 2.0 then
            runtime.lastAutoGroupAcceptAt = now
            mq.cmd('/timed 5 /invite')
            print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax.', inviter))
        end
    end
end)
mq.event('TriuneAutoGroupInvite2', '#1# has invited you to join a group#*#', function(_, inviter)
    if ctrl and ctrl.auto_group and inviter and runtime.isAutoAcceptAllowed and runtime.isAutoAcceptAllowed(inviter) then
        local now = os.clock()
        if not runtime.lastAutoGroupAcceptAt or (now - runtime.lastAutoGroupAcceptAt) > 2.0 then
            runtime.lastAutoGroupAcceptAt = now
            mq.cmd('/timed 5 /invite')
            print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax.', inviter))
        end
    end
end)
mq.event('TriuneAutoDZInvite1', '#1# has invited you to join #*# expedition#*#', function(_, inviter)
    if ctrl and ctrl.auto_dzadd and inviter and runtime.isAutoAcceptAllowed and runtime.isAutoAcceptAllowed(inviter) then
        local now = os.clock()
        if not runtime.lastAutoDzAcceptAt or (now - runtime.lastAutoDzAcceptAt) > 1.5 then
            runtime.lastAutoDzAcceptAt = now
            mq.cmd('/dzaccept')
            print(string.format('\ag[Triune Auto-Accept]\ax Accepted expedition invite from \ay%s\ax.', inviter))
        end
    end
end)
mq.event('TriuneAutoDZInvite2', '#1# invites you to join an expedition#*#', function(_, inviter)
    if ctrl and ctrl.auto_dzadd and inviter and runtime.isAutoAcceptAllowed and runtime.isAutoAcceptAllowed(inviter) then
        local now = os.clock()
        if not runtime.lastAutoDzAcceptAt or (now - runtime.lastAutoDzAcceptAt) > 1.5 then
            runtime.lastAutoDzAcceptAt = now
            mq.cmd('/dzaccept')
            print(string.format('\ag[Triune Auto-Accept]\ax Accepted expedition invite from \ay%s\ax.', inviter))
        end
    end
end)
mq.event('TriuneAutoDZInvite3', '#1# has invited you to join a Dynamic Zone#*#', function(_, inviter)
    if ctrl and ctrl.auto_dzadd and inviter and runtime.isAutoAcceptAllowed and runtime.isAutoAcceptAllowed(inviter) then
        local now = os.clock()
        if not runtime.lastAutoDzAcceptAt or (now - runtime.lastAutoDzAcceptAt) > 1.5 then
            runtime.lastAutoDzAcceptAt = now
            mq.cmd('/dzaccept')
            print(string.format('\ag[Triune Auto-Accept]\ax Accepted Dynamic Zone invite from \ay%s\ax.', inviter))
        end
    end
end)

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

-- Does this character own ANY item at all (spell/disc/AA, shared or unique) from
-- abbr's full pool? A much lower bar than the UNIQUE-only ranking score used by
-- detectClasses -- this is for VALIDATING an already-saved class slot, not for
-- competitively ranking candidates. A real Bard, at any level, knows at least
-- one Bard song/spell/disc/AA ever; a class name that's only in the save because
-- of a past bug (detectClasses used to hardcode 'Rng'/'Brd' when it couldn't
-- find a real 2nd/3rd class) will show zero.
-- classPlausible is defined in local helpers above

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
    runtime.specialTabAAs = nil
    runtime.specialTabReadDone = false
    runtime.pendingReadSpecialTab = true
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
function UI.pushCol(id, r, g, b, a)
    if id == nil then return end
    if pcall(ImGui.PushStyleColor, id, r, g, b, a) then runtime.colN = (runtime.colN or 0) + 1 end
end
function UI.pushVar(id, a, b)
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
    if ok then runtime.varN = (runtime.varN or 0) + 1 end
end

function UI.pushTheme()
    runtime.colN, runtime.varN = 0, 0
    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
    local SV = ImGuiStyleVar or _G.ImGuiStyleVar or (mq.imgui and mq.imgui.StyleVar)
    if Col then
        UI.pushCol(Col.WindowBg, 0.059, 0.086, 0.133, 1)
        UI.pushCol(Col.ChildBg, 0.055, 0.082, 0.125, 1)
        UI.pushCol(Col.PopupBg, 0.047, 0.075, 0.118, 1)
        UI.pushCol(Col.Border, 0.157, 0.251, 0.345, 1)
        UI.pushCol(Col.Text, 0.851, 0.898, 0.953, 1)
        UI.pushCol(Col.TextDisabled, 0.490, 0.561, 0.651, 1)
        UI.pushCol(Col.TitleBg, 0.043, 0.067, 0.106, 1)
        UI.pushCol(Col.TitleBgActive, 0.047, 0.078, 0.125, 1)
        UI.pushCol(Col.FrameBg, 0.047, 0.078, 0.125, 1)
        UI.pushCol(Col.FrameBgHovered, 0.090, 0.150, 0.220, 1)
        UI.pushCol(Col.FrameBgActive, 0.120, 0.190, 0.270, 1)
        UI.pushCol(Col.Button, 0.086, 0.125, 0.196, 1)
        UI.pushCol(Col.ButtonHovered, 0.300, 0.700, 1.000, 0.35)
        UI.pushCol(Col.ButtonActive, 0.300, 0.700, 1.000, 0.60)
        UI.pushCol(Col.Header, 0.078, 0.129, 0.204, 1)
        UI.pushCol(Col.HeaderHovered, 0.160, 0.440, 0.700, 0.50)
        UI.pushCol(Col.HeaderActive, 0.160, 0.500, 0.750, 0.70)
        UI.pushCol(Col.Tab, 0.043, 0.067, 0.098, 1)
        UI.pushCol(Col.TabHovered, 0.300, 0.700, 1.000, 0.40)
        UI.pushCol(Col.TabSelected, 0.075, 0.125, 0.200, 1)
        UI.pushCol(Col.CheckMark, 0.370, 0.880, 0.640, 1)
        UI.pushCol(Col.SliderGrab, 1.000, 0.700, 0.540, 1)
        UI.pushCol(Col.SliderGrabActive, 1.000, 0.550, 0.300, 1)
        UI.pushCol(Col.Separator, 0.157, 0.251, 0.345, 1)
        UI.pushCol(Col.ScrollbarBg, 0.031, 0.051, 0.078, 1)
        UI.pushCol(Col.ScrollbarGrab, 0.157, 0.251, 0.345, 1)
    end
    if SV then
        UI.pushVar(SV.WindowRounding, 6)
        UI.pushVar(SV.ChildRounding, 5)
        UI.pushVar(SV.FrameRounding, 4)
        UI.pushVar(SV.PopupRounding, 4)
        UI.pushVar(SV.TabRounding, 4)
        UI.pushVar(SV.GrabRounding, 3)
        UI.pushVar(SV.ScrollbarRounding, 6)

        UI.pushVar(SV.FrameBorderSize, 1)
        UI.pushVar(SV.FramePadding, 7, 4)
        UI.pushVar(SV.ItemSpacing, 8, 6)
        UI.pushVar(SV.WindowPadding, 12, 10)
    end
end

function UI.popTheme()
    if (runtime.varN or 0) > 0 then
        pcall(ImGui.PopStyleVar, runtime.varN); runtime.varN = 0
    end
    if (runtime.colN or 0) > 0 then
        pcall(ImGui.PopStyleColor, runtime.colN); runtime.colN = 0
    end
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

-- Toggle a standalone Triune tool script: stop it if running, otherwise run
-- it. Returns 'started' or 'stopped'. stopCmd overrides the default
-- '/lua stop <name>' stop action (the DPS parser uses its own '/dps toggle').
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

    -- Toolbar buttons
    if ImGui.Button('Open Spellbook##hdrBook') then
        UI.toggleTool('triune_spellbook')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Spellbook interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('Map##hdrMap') then
        UI.toggleTool('triune_map')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Map & NPC Tracker interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('DPS Parser##hdrDPS') then
        UI.toggleTool('triune_dps', '/dps toggle')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or toggles the standalone Triune DPS Parser window.')
    end
    ImGui.SameLine()
    if ImGui.Button('Compact Mode##hdrCompact') then
        ctrl.compact = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Switches Triune AutoCombat into a sleek compact HUD overlay window.')
    end
    ImGui.SameLine()
    if ImGui.Button('Cursor Manager##hdrCursor') then
        UI.toggleTool('triune_cursor')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Cursor Item Manager.')
    end
    ImGui.SameLine()
    local cdActive = ctrl.show_cooldowns
    local cdPop = 0
    if cdActive then
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then cdPop = cdPop + 1 end
    end
    if ImGui.Button('Cooldowns##hdrCooldowns') then
        ctrl.show_cooldowns = not ctrl.show_cooldowns
        runtime.saveLoadout(true)
    end
    if cdPop > 0 then pcall(ImGui.PopStyleColor, cdPop) end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Toggles the standalone popout Cooldown & Ability Monitor window.')
    end

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
                { cmd = '/ac compact / /ac mini',             desc = 'Toggle auto-resizing Compact Mini-Window HUD mode' },
                { cmd = '/ac help / /ac h',                   desc = 'Print slash command usage and command options in chat' },
                { cmd = '/ac spellbook',                      desc = 'Toggle the standalone spellbook & auto-memorization queue window' },
                { cmd = '/ac cursorui',                       desc = 'Toggle the standalone cursor item manager window' },
                { cmd = '/ac clearcursor',                    desc = 'Clear item on cursor (autoinventory / drop / destroy per rules)' },
                { cmd = '/ac clear lockouts',                 desc = 'Clear all active spell lockouts, non-stacking buff backoffs, and mob immunities' },
                { cmd = '/ac buffbot / /ac buff',             desc = 'Toggle the standalone Interactive Buffbot window' },
                { cmd = '/ac track / /ac zone',               desc = 'Toggle the standalone Zone NPC Tracker window for live targeting & navigation' },
                { cmd = '/ac update',                         desc = 'Check for GitHub updates and launch the Triune Release Updater' },
                { cmd = '/ac dps / /dps',                     desc = 'Toggle or launch the standalone DPS Parser window' },
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
                { when = 'has Poison/Disease',   desc = 'Casts cure spells when the target is afflicted with poison or disease counters.' },
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
        if timer > 0 then
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
                    local secNum = tonumber(sec) or 60
                    if aaTier(secNum) == tier and type(list) == 'table' then
                        for _, item in ipairs(list) do
                            local nm = type(item) == 'table' and (item[1] or item.name) or tostring(item)
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
                                    ImGui.SetTooltip(string.format('AA Ability: %s', nm))
                                end
                                ImGui.SameLine(); ImGui.TextDisabled('(' .. fmtSec(secNum) .. ')')
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip(string.format('Cooldown: %s (Tier: %s)', fmtSec(secNum), tier))
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

-- UI: Auto AA / Point Spender & AA Progression Tab
function UI.drawAutoAATab()
    if not ImGui.BeginTabItem('Auto AA') then return end

    local unspentAA = 0
    local spentAA = 0
    local totalAA = 0
    pcall(function()
        unspentAA = tonumber(mq.TLO.Me.AAPoints() or 0) or 0
        spentAA = tonumber(mq.TLO.Me.AAPointsSpent() or 0) or 0
        totalAA = tonumber(mq.TLO.Me.AAPointsTotal() or 0) or (unspentAA + spentAA)
    end)

    if runtime.lastObservedAAPointsSpent ~= nil and spentAA ~= runtime.lastObservedAAPointsSpent then
        runtime.lastObservedAAPointsSpent = spentAA
        runtime.lastAAScanAt = 0
        runtime.aaFilterDirty = true
        if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
    else
        runtime.lastObservedAAPointsSpent = spentAA
    end

    if runtime.lastObservedAAPoints ~= nil and unspentAA ~= runtime.lastObservedAAPoints then
        runtime.lastObservedAAPoints = unspentAA
        runtime.aaFilterDirty = true
    else
        runtime.lastObservedAAPoints = unspentAA
    end

    accent(GOLD, 'Alternate Advancement (AA) Progression & Auto-Training')

    -- Compact Row 1: Live AA Pool Status & Master Automation Controls
    ImGui.Text('Unspent:')
    ImGui.SameLine()
    if unspentAA >= 100 then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('%d/100 [CAP!]', unspentAA))
    elseif unspentAA >= (ctrl.auto_spend_aa_threshold or 100) then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('%d [THRESHOLD]', unspentAA))
    else
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('%d AA', unspentAA))
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', string.format('Unspent: %d AA\nSpent: %d AA\nTotal: %d AA', unspentAA, spentAA, totalAA))
    end

    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(Spent: %d)', spentAA))

    ImGui.SameLine()
    ImGui.TextDisabled('|')
    ImGui.SameLine()

    local spendVal = ImGui.Checkbox('Auto-Spend##aaAutoSpendMaster', ctrl.auto_spend_aa or false)
    if spendVal ~= (ctrl.auto_spend_aa or false) then
        ctrl.auto_spend_aa = spendVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'When enabled, Triune automatically purchases prioritized AAs when sufficient points are available.')
    end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(110)
    local orderOpts = { 'Cheapest First', 'Alphabetical' }
    local orderKeys = { 'cost', 'list' }
    local curOrderIdx = (ctrl.auto_aa_buy_order == 'list') and 2 or 1
    local newOrderIdx = ImGui.Combo('##aaOrderCombo', curOrderIdx, orderOpts)
    if newOrderIdx ~= curOrderIdx then
        ctrl.auto_aa_buy_order = orderKeys[newOrderIdx]
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Priority Buy Order:\n- Cheapest First: Buys lowest-cost prioritized ability available.\n- Alphabetical: Evaluates prioritized abilities in A-Z order.')
    end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(100)
    local curThresh = ctrl.auto_spend_aa_threshold or 100
    local newThresh = ImGui.SliderInt('##autoAaThresh', curThresh, 25, 100, 'Cap: %d')
    if newThresh ~= curThresh then
        ctrl.auto_spend_aa_threshold = newThresh
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', string.format('Cap Protection Threshold: %d AA\nSurplus points will dump into fireworks when reached.', curThresh))
    end

    ImGui.SameLine()
    if ImGui.Button('↻ Refresh##autoAaRefreshBtn') then
        runtime.specialTabReadDone = false
        runtime.pendingReadSpecialTab = true
        if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Re-scans all character Alternate Advancement abilities (including Special tab).')
    end

    ImGui.SameLine()
    if ImGui.Button('Clear Prios##autoAaClearPrioBtn') then
        ctrl.auto_aa_priorities = {}
        runtime.aaFilterDirty = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Unchecks all prioritized abilities.')
    end

    -- Compact Row 2: Search, Sort & View Filter Toggles
    local allItems = runtime.getFilteredSortedAAs and runtime.getFilteredSortedAAs() or {}
    local prioCount = 0
    if ctrl.auto_aa_priorities then
        for _, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled then prioCount = prioCount + 1 end
        end
    end

    ImGui.SetNextItemWidth(130)
    local curSearch = ctrl.auto_aa_search or ''
    local newSearch = ImGui.InputTextWithHint('##autoAaSearchBox', 'Search AAs...', curSearch, 64)
    if newSearch ~= curSearch then
        ctrl.auto_aa_search = newSearch
        runtime.aaFilterDirty = true
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Filter abilities by name in real-time.')
    end

    ImGui.SameLine()
    if ImGui.Button('X##clearAaSearch') then
        ctrl.auto_aa_search = ''
        runtime.aaFilterDirty = true
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Clear search text.')
    end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(105)
    local sortNames = { 'Name', 'Cost', 'Trained' }
    local sortKeys = { 'name', 'cost', 'trained' }
    local curSortIdx = 1
    for idx, sk in ipairs(sortKeys) do
        if ctrl.auto_aa_sort_by == sk then curSortIdx = idx; break end
    end
    local newSortIdx = ImGui.Combo('##autoAaSortCombo', curSortIdx, sortNames)
    if newSortIdx ~= curSortIdx then
        ctrl.auto_aa_sort_by = sortKeys[newSortIdx]
        runtime.aaFilterDirty = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Sort by ability name, point cost to buy next rank, or training status.')
    end

    ImGui.SameLine()
    local isAsc = (ctrl.auto_aa_sort_asc ~= false)
    local dirBtnText = isAsc and '▲ Asc' or '▼ Desc'
    if ImGui.Button(dirBtnText .. '##autoAaSortDir') then
        ctrl.auto_aa_sort_asc = not isAsc
        runtime.aaFilterDirty = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Toggle sort direction: Ascending vs Descending.')
    end

    ImGui.SameLine()
    local hideVal = ImGui.Checkbox('Hide Maxed##autoAaHideMax', ctrl.auto_aa_hide_maxed or false)
    if hideVal ~= (ctrl.auto_aa_hide_maxed or false) then
        ctrl.auto_aa_hide_maxed = hideVal
        runtime.aaFilterDirty = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Hide abilities that have reached maximum rank.')
    end

    ImGui.SameLine()
    local prioOnlyVal = ImGui.Checkbox('Prio Only##autoAaPrioOnly', ctrl.auto_aa_only_prioritized or false)
    if prioOnlyVal ~= (ctrl.auto_aa_only_prioritized or false) then
        ctrl.auto_aa_only_prioritized = prioOnlyVal
        runtime.aaFilterDirty = true
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Show only AAs that are checked for priority auto-purchase.')
    end

    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(%d listed | %d prio)', #allItems, prioCount))

    -- 3. Scrollable Table (Dynamically Sized to Window)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 2)
    local childFlags = bit.bor(ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0)
    local tableChildOpen = ImGui.BeginChild('auto_aa_table_scroll', 0, 0, false, childFlags)
    if tableChildOpen then
        local tableFlags = bit.bor(
            ImGuiTableFlags.RowBg,
            ImGuiTableFlags.Borders,
            ImGuiTableFlags.Resizable,
            ImGuiTableFlags.SizingStretchProp
        )
        if ImGui.BeginTable('##AutoAABrowserTable', 6, tableFlags) then
            ImGui.TableSetupColumn('Prio', ImGuiTableColumnFlags.WidthFixed, 32)
            ImGui.TableSetupColumn('Ability Name', ImGuiTableColumnFlags.WidthStretch, 200)
            ImGui.TableSetupColumn('Rank', ImGuiTableColumnFlags.WidthFixed, 55)
            ImGui.TableSetupColumn('Cost', ImGuiTableColumnFlags.WidthFixed, 55)
            ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, 95)
            ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, 55)
            ImGui.TableHeadersRow()

            for _, itm in ipairs(allItems) do
                ImGui.TableNextRow()
                ImGui.PushID('aa_row_' .. itm.name)

                -- Col 1: Priority Checkbox
                ImGui.TableNextColumn()
                local isPrio = not not (ctrl.auto_aa_priorities and ctrl.auto_aa_priorities[itm.name])
                local newPrio = ImGui.Checkbox('##prioCheck', isPrio)
                if newPrio ~= isPrio then
                    if not ctrl.auto_aa_priorities then ctrl.auto_aa_priorities = {} end
                    ctrl.auto_aa_priorities[itm.name] = newPrio and true or nil
                    runtime.aaFilterDirty = true
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('Prioritize "%s" for automatic training when points are available.', itm.name))
                end

                -- Col 2: Ability Name
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], itm.name)
                else
                    ImGui.Text(itm.name)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('%s\nCurrent Rank: %d / %d\nNext Rank Cost: %d AA\nPoints Spent: %d AA',
                        itm.name, itm.rank, itm.maxRank, itm.cost, itm.pointsSpent or 0))
                end

                -- Col 3: Rank
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('%d/%d', itm.rank, itm.maxRank))
                else
                    ImGui.Text(string.format('%d/%d', itm.rank, itm.maxRank))
                end

                -- Col 4: Cost
                ImGui.TableNextColumn()
                if itm.fullyTrained or itm.cost <= 0 then
                    ImGui.TextDisabled('-')
                elseif unspentAA >= itm.cost then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('%d AA', itm.cost))
                else
                    ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('%d AA', itm.cost))
                end

                -- Col 5: Status
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Max Rank')
                elseif itm.cost > 0 and unspentAA >= itm.cost then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Can Train')
                elseif itm.cost > 0 then
                    ImGui.TextDisabled(string.format('Need %d AA', itm.cost - unspentAA))
                else
                    ImGui.TextDisabled('Untrained')
                end

                -- Col 6: Action (Train button)
                ImGui.TableNextColumn()
                if not itm.fullyTrained and itm.cost > 0 then
                    local canAfford = (unspentAA >= itm.cost)
                    if not canAfford then ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5) end
                    if ImGui.Button('Train##btn') then
                        if runtime.manualSpendAA then runtime.manualSpendAA(itm.name) end
                    end
                    if not canAfford then ImGui.PopStyleVar() end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', string.format('Click to train next rank of "%s" (%d AA).', itm.name, itm.cost))
                    end
                else
                    ImGui.TextDisabled('---')
                end

                ImGui.PopID()
            end

            ImGui.EndTable()
        end

        -- 4. Fireworks & Utility Actions Collapsible Section
        ImGui.Spacing()
        if ImGui.CollapsingHeader('Fireworks Spender & Utility Actions##autoAaFwHeader', false) then
            ImGui.Indent(10)
            local curName = ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
            local curId = ctrl.auto_spend_aa_id or 17788

            local summonVal = ImGui.Checkbox('Enable Auto-Summon Fireworks (/alt activate)', ctrl.auto_summon_fireworks or false)
            if summonVal ~= (ctrl.auto_summon_fireworks or false) then
                ctrl.auto_summon_fireworks = summonVal
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'When ready (out of combat & stationary), automatically activates the AA ability to summon fireworks\nand clears the cursor into inventory via /autoinventory.')
            end

            ImGui.SameLine()
            local summonLabel = string.format('Summon Fireworks (/alt act %d)##manualSummonBtn', curId)
            if ImGui.Button(summonLabel) then
                if runtime.manualSummonFireworks then runtime.manualSummonFireworks() end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', string.format('Manually triggers /alt activate %d to summon fireworks and puts them into your inventory.', curId))
            end

            ImGui.SameLine()
            if ImGui.Button('Clear Cursor (/autoinv)##clearCursorAutoAaBtn') then
                runtime.pendingCursorClearAt = os.clock()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'Clears any item currently on cursor into your inventory bags.')
            end

            ImGui.SetNextItemWidth(260)
            local newName = ImGui.InputText('Cap Spender AA Name##autoAaCapName', curName, 128)
            if newName and newName ~= curName and newName ~= '' then
                ctrl.auto_spend_aa_name = newName
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'The fallback AA Ability name used for point dumping when cap is reached (e.g. Alternately Advanced Fireworks).')
            end

            ImGui.SameLine()
            ImGui.SetNextItemWidth(120)
            local newId = ImGui.InputInt('Activation ID##autoAaActId', curId)
            if newId ~= curId and newId > 0 then
                ctrl.auto_spend_aa_id = newId
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'The Spell / Ability ID used for fireworks summoning (default: 17788).')
            end
            ImGui.Unindent(10)
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)

    ImGui.EndTabItem()
end

-- UI: Cooldown & Ability Monitor Tab
function UI.drawCooldownsTab()
    if not ImGui.BeginTabItem('Cooldowns') then return end
    UI.renderCooldownContent('_tab', false)
    ImGui.EndTabItem()
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
        local styleStr = ctrl.combat_style or 'Melee'
        if styleStr == 'Ranged' and runtime.serverAttackMode then
            styleStr = string.format('Ranged (Server: %s)', runtime.serverAttackMode)
        end
        accent(ARC, '• Style: ' .. styleStr)
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
        local tTotName, tTotPct, tMyAggro, tMySecAggro
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
                tTotName = mq.TLO.Target.TargetOfTarget.CleanName() or 'None'
                tTotPct = mq.TLO.Target.PctAggro() or 0
                tMyAggro = mq.TLO.Target.SecondaryPctAggro() or 0
                tMySecAggro = mq.TLO.Me.SecondaryPctAggro() or 0
            end
        end)

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
        local myPetId = 0
        pcall(function() myPetId = mq.TLO.Me.Pet.ID() or 0 end)
        if myPetId > 0 and not seenPetIds[myPetId] and isSpawnAlive(myPetId) then
            seenPetIds[myPetId] = true
            local info = getPetSpawnInfo(myPetId)
            table.insert(activePets, {
                id = myPetId,
                cls = 'Pet',
                slotNum = nil,
                info = info
            })
        end

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

            if navActive then
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
            ctrl.camp_radius = ImGui.SliderInt('Camp Radius##manualRadius', ctrl.camp_radius or 100, 10, 500)
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
            ctrl.hunter_radius = ImGui.SliderInt('Search Radius', ctrl.hunter_radius or 1500, 50, 2000)
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
            ctrl.camp_radius = ImGui.SliderInt('Pull Radius', ctrl.camp_radius or 100, 10, 500)
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

function UI.drawAutoAcceptSettings()
    accent(GOLD, 'Social & Group Automation')
    ImGui.TextDisabled('Automatically accept group invites, trades, and expedition (DZ) requests based on configured rules.')
    ImGui.Separator()

    -- Automation Actions
    accent(GOLD, 'Automation Actions:')
    local grpVal = ImGui.Checkbox('Auto-Accept Group Invites##aaGrp', ctrl.auto_group or false)
    if grpVal ~= (ctrl.auto_group or false) then
        ctrl.auto_group = grpVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically joins group when invited by an authorized player.')
    end

    local trdVal = ImGui.Checkbox('Auto-Accept Trades##aaTrd', ctrl.auto_trade or false)
    if trdVal ~= (ctrl.auto_trade or false) then
        ctrl.auto_trade = trdVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically clicks trade accept when incoming trade partner has clicked their trade button and is authorized.')
    end

    local dzVal = ImGui.Checkbox('Auto-Accept Dynamic Zone / Expedition Invites (DZAdd)##aaDz', ctrl.auto_dzadd or false)
    if dzVal ~= (ctrl.auto_dzadd or false) then
        ctrl.auto_dzadd = dzVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically accepts expedition (/dzaccept), dynamic zone, and task addition invites from authorized players.')
    end

    ImGui.Separator()

    -- Authorization Rules
    accent(GOLD, 'Authorization Rules (Who to accept from):')
    local anyVal = ImGui.Checkbox('Accept from Anyone##aaAnyone', ctrl.auto_accept_anyone or false)
    if anyVal ~= (ctrl.auto_accept_anyone or false) then
        ctrl.auto_accept_anyone = anyVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Accept requests from ANY player unconditionally (bypasses group, guild, and whitelist checks).')
    end

    local grpMemVal = ImGui.Checkbox('Always accept from Group Members##aaGrpMem', ctrl.auto_accept_group or false)
    if grpMemVal ~= (ctrl.auto_accept_group or false) then
        ctrl.auto_accept_group = grpMemVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Accept trades and expedition requests from current group members.')
    end

    local gldVal = ImGui.Checkbox('Accept from all Guild Members##aaGuild', ctrl.auto_accept_guild or false)
    if gldVal ~= (ctrl.auto_accept_guild or false) then
        ctrl.auto_accept_guild = gldVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Accept requests from players in the same guild as your character.')
    end

    ImGui.Separator()

    -- Whitelisted Players
    accent(GOLD, 'Whitelisted Players:')
    ImGui.TextDisabled('Specific character names and player IDs allowed to trigger auto-accept (case-insensitive):')

    ImGui.SetNextItemWidth(170)
    local enteredText, enterPressed = ImGui.InputTextWithHint('##autoAcceptAddInput', 'Player Name or ID', runtime.autoAcceptInputName or '', (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0)
    if enteredText ~= nil then runtime.autoAcceptInputName = enteredText end
    ImGui.SameLine()
    if ImGui.Button('Add##autoAcceptAddBtn') or enterPressed then
        if runtime.autoAcceptInputName and runtime.autoAcceptInputName:gsub('%s+', '') ~= '' then
            runtime.addAutoAcceptName(runtime.autoAcceptInputName)
            runtime.autoAcceptInputName = ''
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Add the entered player name or ID to the auto-accept whitelist.')
    end

    ImGui.SameLine()
    if ImGui.Button('+ Add Target##autoAcceptAddTargetBtn') then
        local tName, tId = nil, 0
        pcall(function()
            local tgt = mq.TLO.Target
            if tgt and tgt() and tgt.Type() == 'PC' then
                tName = tgt.CleanName()
                tId = tgt.ID() or 0
            end
        end)
        if tName and tName ~= '' then
            runtime.addAutoAcceptName(tName, tId)
        else
            print('\ar[Triune Auto-Accept]\ax Target is not a player character.')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Target a player character (PC) in-game and click to add their Name and Player ID.')
    end

    local canRemove = (runtime.autoAcceptSelectedPlayer and runtime.autoAcceptSelectedPlayer ~= '')
    if not canRemove then
        pcall(function()
            local tgt = mq.TLO.Target
            if tgt and tgt() and tgt.Type() == 'PC' then
                local tgtName = tgt.CleanName()
                local tgtId = tgt.ID() or 0
                if runtime.isAutoAcceptListed(tgtName) or (tgtId > 0 and runtime.isAutoAcceptListed(tgtId)) then
                    canRemove = true
                end
            end
        end)
    end

    ImGui.SameLine()
    if not canRemove then ImGui.BeginDisabled() end
    if ImGui.Button('Remove##autoAcceptRemoveBtn') then
        if runtime.autoAcceptSelectedPlayer and runtime.autoAcceptSelectedPlayer ~= '' then
            runtime.removeAutoAcceptName(runtime.autoAcceptSelectedPlayer)
            runtime.autoAcceptSelectedPlayer = nil
        else
            local tgtName, tgtId = nil, 0
            pcall(function()
                local tgt = mq.TLO.Target
                if tgt and tgt() and tgt.Type() == 'PC' then
                    tgtName = tgt.CleanName()
                    tgtId = tgt.ID() or 0
                end
            end)
            if tgtId > 0 and runtime.isAutoAcceptListed(tgtId) then
                runtime.removeAutoAcceptName(tgtId)
            elseif tgtName and tgtName ~= '' and runtime.isAutoAcceptListed(tgtName) then
                runtime.removeAutoAcceptName(tgtName)
            end
        end
    end
    if not canRemove then ImGui.EndDisabled() end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Remove the selected player from the whitelist (or target a whitelisted player to remove them).')
    end

    if ctrl.auto_accept_names and #ctrl.auto_accept_names > 0 then
        ImGui.SameLine()
        if ImGui.Button('Clear All##autoAcceptClearBtn') then
            runtime.clearAutoAcceptNames()
            runtime.autoAcceptSelectedPlayer = nil
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s', 'Remove all players from the auto-accept whitelist.')
        end
    end

    -- Whitelist table frame
    local names = ctrl.auto_accept_names or {}
    if #names == 0 then
        accent(MUTED, 'No whitelisted players configured.')
    else
        local tableFlags = bit.bor(
            (ImGuiTableFlags and ImGuiTableFlags.Borders) or 0,
            (ImGuiTableFlags and ImGuiTableFlags.RowBg) or 0,
            (ImGuiTableFlags and ImGuiTableFlags.ScrollY) or 0
        )
        if ImGui.BeginTable('autoAcceptWhitelistTable', 3, tableFlags, 0, 180) then
            ImGui.TableSetupColumn('Player Name', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthStretch) or 0)
            ImGui.TableSetupColumn('Player ID', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 95)
            ImGui.TableSetupColumn('Action', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 75)
            ImGui.TableHeadersRow()

            local toRemove = nil
            for i, entry in ipairs(names) do
                local eName, eId = runtime.getAutoAcceptPlayerInfo(entry)
                local isSelected = (runtime.autoAcceptSelectedPlayer and runtime.autoAcceptSelectedPlayer:lower() == eName:lower())
                ImGui.TableNextRow()

                -- Column 1: Player Name (Selectable)
                ImGui.TableSetColumnIndex(0)
                ImGui.PushID('aa_row_name_' .. i)
                if ImGui.Selectable(eName, isSelected, (ImGuiSelectableFlags and ImGuiSelectableFlags.SpanAllColumns) or 0) then
                    runtime.autoAcceptSelectedPlayer = eName
                end
                ImGui.PopID()

                -- Column 2: Player ID
                ImGui.TableSetColumnIndex(1)
                if eId > 0 then
                    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(eId))
                else
                    ImGui.TextDisabled('--')
                end

                -- Column 3: Remove button
                ImGui.TableSetColumnIndex(2)
                ImGui.PushID('aa_btn_remove_' .. i)
                if ImGui.Button('Remove', 60, 20) then
                    toRemove = entry
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('Remove %s from the whitelist.', eName))
                end
                ImGui.PopID()
            end

            ImGui.EndTable()

            if toRemove then
                runtime.removeAutoAcceptName(toRemove)
                local rName = runtime.getAutoAcceptPlayerInfo(toRemove)
                if runtime.autoAcceptSelectedPlayer and rName:lower() == runtime.autoAcceptSelectedPlayer:lower() then
                    runtime.autoAcceptSelectedPlayer = nil
                end
            end
        end
        ImGui.TextDisabled(string.format('%d whitelisted player(s) configured', #names))
        if runtime.autoAcceptSelectedPlayer then
            ImGui.SameLine()
            accent(GOLD, string.format('Selected: %s', runtime.autoAcceptSelectedPlayer))
        end
    end
end

function UI.drawSettingsTab()
    if not ImGui.BeginTabItem('Settings') then return end

    if ImGui.BeginTabBar('settingsSubTabBar') then
        if ImGui.BeginTabItem('General Settings##settingsGeneral') then
            -- 1. Character Classes & Profile
            UI.drawClassPicker()

    -- 2. Combat Style & Positioning
    if ImGui.CollapsingHeader('Combat Style & Positioning', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Engagement Style:')
        if ImGui.RadioButton('Melee', ctrl.combat_style == 'Melee') then
            ctrl.combat_style = 'Melee'
            if runtime.revertAttackModeToMelee then runtime.revertAttackModeToMelee() end
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.RadioButton('Ranged (bow)', ctrl.combat_style == 'Ranged') then
            ctrl.combat_style = 'Ranged'
            runtime.saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.RadioButton('Spell', ctrl.combat_style == 'Spell') then
            ctrl.combat_style = 'Spell'
            if runtime.revertAttackModeToMelee then runtime.revertAttackModeToMelee() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Spell: stand off at the range below and never auto-attack (no\n'
                .. '/attack, no /autofire) -- your Spell Gems loadout does all the\n'
                .. 'damage. For pure caster trios that don\'t melee or carry a bow.')
        end

        if ctrl.combat_style == 'Melee' then
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
        else
            ImGui.SetNextItemWidth(200)
            local newDist, changed = ImGui.SliderInt('Combat Distance##rangedRangeSlider', ctrl.ranged_dist or 40, 5, 200)
            if changed or (newDist and newDist ~= ctrl.ranged_dist) then
                ctrl.ranged_dist = newDist
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Distance to position at and engage targets from with ranged/spells (default: 40).')
            end
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
                .. 'wall/prop instead of helping. Applies to Melee, Ranged, and\n'
                .. 'Spell alike. Off by default.')
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
                'If MQ2Nav reports no path to a target, /stick will still\n'
                .. 'try to close on it in a straight line -- which walks\n'
                .. 'straight at whatever wall is blocking the path.\n'
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

    if ImGui.BeginTabItem('Auto-Accept##settingsAutoAccept') then
        UI.drawAutoAcceptSettings()
        ImGui.EndTabItem()
    end

    ImGui.EndTabBar()
    end

    ImGui.EndTabItem()
end

function UI.drawMiniGui()
    if not open or not ctrl.compact then return end
    UI.pushTheme()
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
            UI.toggleTool('triune_map')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or closes Map & NPC Tracker window') end

        ImGui.SameLine()
        if ImGui.Button('DPS##miniDPS', 42, 22) then
            UI.toggleTool('triune_dps', '/dps toggle')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or toggles standalone DPS Parser window') end

        ImGui.SameLine()
        if ImGui.Button('Cursor##miniCursor', 55, 22) then
            UI.toggleTool('triune_cursor')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or closes standalone Cursor Manager') end
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
    open, show = ImGui.Begin(winTitle, open, winFlags)
    if not show then
        ImGui.End(); UI.popTheme(); return
    end

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
        UI.drawAutoAATab()
        UI.drawCooldownsTab()
        UI.drawSettingsTab()
        UI.drawHelpTab()
        ImGui.EndTabBar()
    end

    ImGui.End()
    UI.popTheme()
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
-- Popout Cooldown & Ability Monitor Window
-- ============================================================================

function UI.getTrackedCooldownItems()
    local items = {}
    local now = os.clock()
    local myEnd = 0
    local myMana = 0
    local targetId = 0
    local isNamedTarget = false
    local activeXtarCount = 0

    pcall(function()
        myEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
        myMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
        targetId = mq.TLO.Target.ID() or 0
        if targetId > 0 then
            local sp = mq.TLO.Spawn(targetId)
            if sp and sp() and sp.Named and sp.Named() then
                isNamedTarget = true
            end
        end
        if runtime.countNPCXtarget then
            activeXtarCount = runtime.countNPCXtarget() or 0
        end
    end)

    local activeDiscName = nil
    pcall(function()
        local ad = mq.TLO.Me.ActiveDisc
        if ad and ad() then
            local n = ad.Name()
            if n and n ~= '' and n ~= 'NULL' then activeDiscName = n end
        end
    end)

    -- 1. Innate Combat Abilities / Skills
    if loadout and loadout.actions then
        for nm, entry in pairs(loadout.actions) do
            if entry and entry.enabled then
                local isReady = false
                local timerSec = 0
                local totalSec = getAbilityBaseCooldown(nm)

                pcall(function()
                    local r = mq.TLO.Me.AbilityReady(nm)()
                    if r ~= nil then isReady = (r == true) end

                    local t = mq.TLO.Me.AbilityTimer(nm)
                    if not t or not t() then
                        local idx = mq.TLO.Me.Ability(nm)()
                        if idx and idx > 0 then t = mq.TLO.Me.AbilityTimer(idx) end
                    end
                    if t and t() then
                        timerSec = parseDurationSec(t)
                    end

                    local tot = mq.TLO.Me.AbilityTimerTotal(nm)
                    if not tot or not tot() then
                        local idx = mq.TLO.Me.Ability(nm)()
                        if idx and idx > 0 then tot = mq.TLO.Me.AbilityTimerTotal(idx) end
                    end
                    if tot and tot() then
                        local numTot = parseDurationSec(tot)
                        if numTot > 0 then totalSec = numTot end
                    end
                end)

                local sKey = 's' .. nm
                if runtime.lastCast[sKey] and runtime.lastCast[sKey] > now then
                    local sRem = runtime.lastCast[sKey] - now
                    if sRem > timerSec then timerSec = sRem end
                    isReady = false
                end

                if runtime.lastSkillFiredAt and runtime.lastSkillFiredAt[nm] then
                    local elapsed = now - runtime.lastSkillFiredAt[nm]
                    if elapsed < totalSec then
                        local sRem = totalSec - elapsed
                        if sRem > timerSec then timerSec = sRem end
                    else
                        runtime.lastSkillFiredAt[nm] = nil
                    end
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 6) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isReady then
                    if entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText
                if entry.autoskill then
                    condText = 'Auto on Cooldown'
                else
                    condText = string.format('%s (%s %d%%)', entry.target or 'Target', entry.when or 'in combat', tonumber(entry.pct) or 100)
                end

                table.insert(items, {
                    kind = 'Skill',
                    typeLabel = 'Skill',
                    cls = entry.cls or (myClasses and myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = entry.priority or 50,
                    burn_only = entry.burn_only or false,
                    conditionText = condText,
                    use = function() runtime.fireSkill(nm, entry) end,
                })
            end
        end
    end

    -- 2. Alternate Advancements (AAs)
    if loadout and loadout.aas then
        for nm, entry in pairs(loadout.aas) do
            if entry and entry.enabled then
                local isReady = false
                local timerSec = 0
                local totalSec = 0
                local endCost = 0
                local manaCost = 0
                local activeSec = 0
                local activeTotalSec = 0
                local isActive = false
                local aaId = 0
                local spellName = nil

                pcall(function()
                    local r = mq.TLO.Me.AltAbilityReady(nm)()
                    if r ~= nil then isReady = (r == true) end

                    local aaObj = mq.TLO.AltAbility(nm)
                    if aaObj and aaObj() then
                        aaId = tonumber(aaObj.ID and aaObj.ID() or 0) or 0
                        local mrt = aaObj.MyReuseTime and aaObj.MyReuseTime()
                        local rt = aaObj.ReuseTime and aaObj.ReuseTime()
                        totalSec = tonumber(mrt or rt or 0) or 0
                        if totalSec == 0 and aaObj.Spell and aaObj.Spell() then
                            totalSec = parseSpellRecastTime(aaObj.Spell)
                            spellName = aaObj.Spell.Name and aaObj.Spell.Name()
                        end
                        if aaObj.Spell and aaObj.Spell() and aaObj.Spell.Duration then
                            activeTotalSec = parseDurationSec(aaObj.Spell.Duration)
                        end
                    end

                    local myAA = mq.TLO.Me.AltAbility(nm)
                    if myAA and myAA() then
                        if aaId == 0 and myAA.ID and myAA.ID() then
                            aaId = tonumber(myAA.ID() or 0) or 0
                        end
                        if myAA.Spell and myAA.Spell() then
                            endCost = tonumber(myAA.Spell.EnduranceCost() or 0) or 0
                            manaCost = tonumber(myAA.Spell.Mana() or 0) or 0
                            if not spellName and myAA.Spell.Name then
                                spellName = myAA.Spell.Name()
                            end
                            if activeTotalSec <= 0 and myAA.Spell.Duration then
                                activeTotalSec = parseDurationSec(myAA.Spell.Duration)
                            end
                        end
                    end

                    -- Query AltAbilityTimer by Name, then by ID
                    local t = mq.TLO.Me.AltAbilityTimer(nm)
                    if (not t or not t()) and aaId > 0 then
                        t = mq.TLO.Me.AltAbilityTimer(aaId)
                    end
                    if t and t() then
                        timerSec = parseDurationSec(t)
                    end

                    -- Check Active state on Buff or Song (by AA name or Spell name)
                    local b = mq.TLO.Me.Buff(nm)
                    if (not b or not b()) and spellName and spellName ~= '' then
                        b = mq.TLO.Me.Buff(spellName)
                    end
                    if b and b() then
                        local bDur = parseDurationSec(b.Duration)
                        if bDur > 0 then
                            isActive = true
                            activeSec = bDur
                        end
                    end

                    if not isActive then
                        local s = mq.TLO.Me.Song(nm)
                        if (not s or not s()) and spellName and spellName ~= '' then
                            s = mq.TLO.Me.Song(spellName)
                        end
                        if s and s() then
                            local sDur = parseDurationSec(s.Duration)
                            if sDur > 0 then
                                isActive = true
                                activeSec = sDur
                            end
                        end
                    end
                end)

                -- Check software timer if lastAAFiredAt exists
                if runtime.lastAAFiredAt and runtime.lastAAFiredAt[nm] then
                    local elapsed = now - runtime.lastAAFiredAt[nm]
                    if totalSec <= 0 and runtime.aaCooldownTotal and runtime.aaCooldownTotal[nm] then
                        totalSec = runtime.aaCooldownTotal[nm]
                    end
                    if totalSec > 0 and elapsed < totalSec then
                        local rem = totalSec - elapsed
                        if rem > timerSec then timerSec = rem end
                    else
                        runtime.lastAAFiredAt[nm] = nil
                    end
                end

                local aKey = 'a' .. nm
                if runtime.lastCast[aKey] and runtime.lastCast[aKey] > now then
                    local rem = runtime.lastCast[aKey] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady and not isActive then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 60) end
                if activeTotalSec <= 0 then activeTotalSec = math.max(activeSec, 18) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isActive then
                    status = 'ACTIVE'
                    reason = string.format('Active duration: %s left', activeSec > 0 and fmtSec(math.floor(activeSec)) or 'Running')
                elseif isReady then
                    if endCost > 0 and myEnd < endCost then
                        status = 'LOW END'
                        reason = string.format('Need %d End (Have %d)', endCost, myEnd)
                    elseif manaCost > 0 and myMana < manaCost then
                        status = 'LOW MANA'
                        reason = string.format('Need %d Mana (Have %d)', manaCost, myMana)
                    elseif castTracker and castTracker.isLockedOut and castTracker.isLockedOut(nm, targetId, entry.kind) then
                        status = 'LOCKED'
                        reason = 'Spell lockout / Target immunity active'
                    elseif entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText = string.format('%s (%s %d%%)', entry.target or 'Myself', entry.when or 'in combat', tonumber(entry.pct) or 30)

                table.insert(items, {
                    kind = 'AA',
                    typeLabel = 'AA',
                    cls = entry.cls or (myClasses and myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = nil,
                    ready = isReady,
                    active = isActive,
                    activeSec = activeSec,
                    activeTotalSec = activeTotalSec,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = 45,
                    burn_only = entry.burn_only or false,
                    autoskill = false,
                    min_xtar = minXt,
                    entry = entry,
                    conditionText = condText,
                    use = function() runtime.fireAA(nm, entry, targetId > 0 and targetId or mq.TLO.Me.ID()) end,
                })
            end
        end
    end

    -- 3. Disciplines
    if loadout and loadout.discs then
        for nm, entry in pairs(loadout.discs) do
            if entry and entry.enabled then
                local discInfo = getDiscCooldownAndDuration(nm)
                local isReady = false
                local timerSec = 0
                local totalSec = discInfo.recastSec
                local endCost = discInfo.endCost
                local activeSec = 0
                local activeTotalSec = discInfo.durSec
                local isActive = false
                local timerGroupId = discInfo.timerGroupId
                local discIdx = discInfo.discIdx

                pcall(function()
                    isReady = runtime.isDiscReady(nm)

                    local r = mq.TLO.Me.CombatAbilityReady(nm)()
                    if r ~= nil and not r then isReady = false end

                    local cat = mq.TLO.Me.CombatAbilityTimer(nm)
                    if (not cat or not cat()) and discIdx > 0 then
                        cat = mq.TLO.Me.CombatAbilityTimer(discIdx)
                    end
                    if cat and cat() then
                        local cSec = parseCombatAbilityTimer(cat)
                        if cSec > 0 then timerSec = cSec end
                    end
                end)

                -- Check active state: ActiveDisc / Buff / Song
                if activeDiscName and (activeDiscName:lower() == nm:lower() or activeDiscName == nm) then
                    isActive = true
                end

                pcall(function()
                    local b = mq.TLO.Me.Buff(nm)
                    if b and b() then
                        local bDur = parseDurationSec(b.Duration)
                        if bDur > 0 then
                            isActive = true
                            activeSec = bDur
                        end
                    else
                        local s = mq.TLO.Me.Song(nm)
                        if s and s() then
                            local sDur = parseDurationSec(s.Duration)
                            if sDur > 0 then
                                isActive = true
                                activeSec = sDur
                            end
                        end
                    end
                end)

                if runtime.discExpires and runtime.discExpires[nm] and runtime.discExpires[nm] > now then
                    local rem = runtime.discExpires[nm] - now
                    isActive = true
                    if rem > activeSec then activeSec = rem end
                end

                -- If active but activeSec is 0, estimate from base duration and initialize software expiry
                if isActive and activeSec <= 0 then
                    local baseDur = activeTotalSec > 0 and activeTotalSec or 18
                    if not runtime.discExpires then runtime.discExpires = {} end
                    if not runtime.discExpires[nm] or runtime.discExpires[nm] <= now then
                        runtime.discExpires[nm] = now + baseDur
                    end
                    activeSec = math.max(1, runtime.discExpires[nm] - now)
                end

                if runtime.discCooldown and runtime.discCooldown[nm] and runtime.discCooldown[nm] > now then
                    local rem = runtime.discCooldown[nm] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end
                if timerGroupId and runtime.timerGroupCooldown and runtime.timerGroupCooldown[timerGroupId] and runtime.timerGroupCooldown[timerGroupId] > now then
                    local rem = runtime.timerGroupCooldown[timerGroupId] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end
                local dKey = 'd' .. nm
                if runtime.lastCast[dKey] and runtime.lastCast[dKey] > now then
                    local rem = runtime.lastCast[dKey] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end

                if runtime.lastDiscFiredAt and runtime.lastDiscFiredAt[nm] then
                    local elapsed = now - runtime.lastDiscFiredAt[nm]
                    if totalSec > 0 and elapsed < totalSec then
                        local rem = totalSec - elapsed
                        if rem > timerSec then timerSec = rem end
                    else
                        runtime.lastDiscFiredAt[nm] = nil
                    end
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady and not isActive then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 30) end
                if activeTotalSec <= 0 then activeTotalSec = math.max(activeSec, 18) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isActive then
                    status = 'ACTIVE'
                    reason = string.format('Active duration: %s left', activeSec > 0 and fmtSec(math.floor(activeSec)) or 'Running')
                elseif isReady then
                    if endCost > 0 and myEnd < endCost then
                        status = 'LOW END'
                        reason = string.format('Need %d End (Have %d)', endCost, myEnd)
                    elseif activeDiscName and activeDiscName ~= '' and activeDiscName:lower() ~= nm:lower() then
                        status = 'BLOCKED'
                        reason = string.format('Active Disc conflict: %s is running', activeDiscName)
                    elseif entry.boss_only and not isNamedTarget then
                        status = 'NEED BOSS'
                        reason = 'Requires Named / Boss target'
                    elseif entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText = string.format('%s (%s %d%%)', entry.target or 'Myself', entry.when or 'HP <=', tonumber(entry.pct) or 30)

                table.insert(items, {
                    kind = 'Disc',
                    typeLabel = timerGroupId and ('Disc ' .. timerGroupId) or 'Disc',
                    cls = entry.cls or (myClasses and myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = timerGroupId,
                    ready = isReady,
                    active = isActive,
                    activeSec = activeSec,
                    activeTotalSec = activeTotalSec,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = entry.priority or 50,
                    burn_only = entry.burn_only or false,
                    boss_only = entry.boss_only or false,
                    autoskill = false,
                    min_xtar = minXt,
                    entry = entry,
                    conditionText = condText,
                    use = function() runtime.fireDisc(nm, entry, targetId > 0 and targetId or mq.TLO.Me.ID()) end,
                })
            end
        end
    end

    -- 4. Spells (Gems) - when category includes Spells or All
    if loadout and loadout.gems and (ctrl.cooldown_category == 'Spells' or ctrl.cooldown_category == 'All') then
        for i, g in ipairs(loadout.gems) do
            local spName = g and (g.spell or g.name)
            local pctVal = tonumber(g and g.pct) or 100
            local isEnabled = (g and g.enabled ~= false) and (pctVal > 0)
            if g and isEnabled and spName and spName ~= '' then
                local slot = tonumber(g.gem) or math.min(i, 12)
                local isReady = false
                local timerSec = 0
                pcall(function()
                    isReady = mq.TLO.Me.SpellReady(slot)() or false
                    local gt = mq.TLO.Me.GemTimer(slot)
                    if gt and gt() then
                        timerSec = parseDurationSec(gt)
                    end
                end)
                local condText = string.format('Gem %d: %s (%s %d%%)', slot, g.target or 'Target', g.when or 'in combat', pctVal)
                table.insert(items, {
                    kind = 'Spell',
                    typeLabel = 'Gem ' .. tostring(slot),
                    cls = g.cls or (myClasses and myClasses[1]) or 'War',
                    name = spName,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = math.max(timerSec, 5),
                    status = isReady and 'READY' or 'COOLDOWN',
                    reason = '',
                    priority = i * 10,
                    burn_only = g.burn_only or false,
                    autoskill = false,
                    min_xtar = 1,
                    entry = g,
                    conditionText = condText,
                    use = function() runtime.castGem(slot, g) end,
                })
            end
        end
    end

    -- 5. Clickies (Items) - when category includes Items or All
    if loadout and loadout.clickies and (ctrl.cooldown_category == 'Items' or ctrl.cooldown_category == 'All') then
        for _, c in ipairs(loadout.clickies) do
            if c and c.enabled and c.name and c.name ~= '' then
                local isReady = false
                local timerSec = 0
                pcall(function()
                    isReady = mq.TLO.Me.ItemReady(c.name)() or false
                    local itm = mq.TLO.FindItem(c.name)
                    if itm and itm() then
                        if itm.TimerReady then
                            local tr = itm.TimerReady()
                            if type(tr) == 'number' and tr > 0 then
                                timerSec = tr > 1800 and (tr / 1000.0) or tr
                            end
                        elseif itm.Timer and itm.Timer() then
                            timerSec = parseDurationSec(itm.Timer)
                        end
                    end
                end)
                local condText = string.format('%s (%s %d%%)', c.target or 'Myself', c.when or 'in combat', tonumber(c.pct) or 100)
                table.insert(items, {
                    kind = 'Item',
                    typeLabel = 'Item',
                    cls = c.cls or (myClasses and myClasses[1]) or 'War',
                    name = c.name,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = math.max(timerSec, 30),
                    status = isReady and 'READY' or 'COOLDOWN',
                    reason = '',
                    priority = 60,
                    burn_only = c.burn_only or false,
                    autoskill = false,
                    min_xtar = 1,
                    entry = c,
                    conditionText = condText,
                    use = function() runtime.useClickie(c) end,
                })
            end
        end
    end

    return items
end

function UI.renderCooldownContent(idSuffix, isPopout)
    idSuffix = idSuffix or ''
    local allItems = UI.getTrackedCooldownItems()

    -- Count totals
    local countReady = 0
    local countActive = 0
    local countCooldown = 0
    for _, itm in ipairs(allItems) do
        if itm.active then countActive = countActive + 1
        elseif itm.status == 'READY' then countReady = countReady + 1
        else countCooldown = countCooldown + 1 end
    end

    -- Header Line 1: Metrics Strip & Quick View Toggles
    accent(ARC, 'COOLDOWNS')
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOOD, string.format('R:%d', countReady))
    ImGui.SameLine(); accent(ARC, string.format('A:%d', countActive))
    ImGui.SameLine(); accent(WARN, string.format('CD:%d', countCooldown))

    if not isPopout then
        ImGui.SameLine()
        if ImGui.Button('Popout Window##cdTabPop' .. idSuffix) then
            ctrl.show_cooldowns = true
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Opens the standalone popout Cooldown & Ability Monitor window.')
        end
    end

    -- Right-aligned Quick Controls
    ImGui.SameLine()
    local isTableView = (ctrl.cooldown_view_mode ~= 'cards')
    if ImGui.Button((isTableView and 'HUD##cdView' or 'Table##cdView') .. idSuffix, 44, 18) then
        ctrl.cooldown_view_mode = isTableView and 'cards' or 'table'
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Toggle Table View / Compact HUD Cards') end

    if isPopout then
        ImGui.SameLine()
        local lockVal = ImGui.Checkbox('Lock##cdLock' .. idSuffix, ctrl.cooldown_locked or false)
        if lockVal ~= ctrl.cooldown_locked then
            ctrl.cooldown_locked = lockVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Lock window position and hide borders') end
    end

    ImGui.SameLine()
    local isCmp = (ctrl.cooldown_compact ~= false)
    local cmpVal = ImGui.Checkbox('Compact##cdCmp' .. idSuffix, isCmp)
    if cmpVal ~= isCmp then
        ctrl.cooldown_compact = cmpVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Ultra-compact mode (streamlined columns)') end

    ImGui.SameLine()
    local editVal = ImGui.Checkbox('Tune##cdEdit' .. idSuffix, ctrl.cooldown_show_inline_edit or false)
    if editVal ~= ctrl.cooldown_show_inline_edit then
        ctrl.cooldown_show_inline_edit = editVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Show inline loadout tuning controls (Enabled, HP %, Burn)') end

    -- Header Line 2: Streamlined Filters & Search
    -- Category Dropdown
    ImGui.SetNextItemWidth(72)
    local CAT_OPTS = { 'All', 'Skills', 'AAs', 'Discs', 'Spells', 'Items' }
    local CAT_MAP = { All = 'All', Skills = 'Abilities', AAs = 'AAs', Discs = 'Disciplines', Spells = 'Spells', Items = 'Items' }
    local REV_CAT = { All = 'All', Abilities = 'Skills', AAs = 'AAs', Disciplines = 'Discs', Spells = 'Spells', Items = 'Items' }
    local curCatLabel = REV_CAT[ctrl.cooldown_category or 'All'] or 'All'
    local curCatIdx = idxOf(CAT_OPTS, curCatLabel)
    local newCatIdx = ImGui.Combo('##cdCat' .. idSuffix, curCatIdx, CAT_OPTS)
    if newCatIdx ~= curCatIdx then
        ctrl.cooldown_category = CAT_MAP[CAT_OPTS[newCatIdx]] or 'All'
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Filter by ability category') end

    ImGui.SameLine()
    -- Status Filter Dropdown
    ImGui.SetNextItemWidth(68)
    local STATUS_OPTS = { 'All', 'Ready', 'CD', 'Active' }
    local STATUS_MAP = { All = 'All', Ready = 'Ready', CD = 'Cooldown', Active = 'Active' }
    local REV_STATUS = { All = 'All', Ready = 'Ready', Cooldown = 'CD', Active = 'Active' }
    local curStatusLabel = REV_STATUS[ctrl.cooldown_status_filter or 'All'] or 'All'
    local curStatusIdx = idxOf(STATUS_OPTS, curStatusLabel)
    local newStatusIdx = ImGui.Combo('##cdStatusFilter' .. idSuffix, curStatusIdx, STATUS_OPTS)
    if newStatusIdx ~= curStatusIdx then
        ctrl.cooldown_status_filter = STATUS_MAP[STATUS_OPTS[newStatusIdx]] or 'All'
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Filter by readiness status') end

    ImGui.SameLine()
    -- Sort Selector
    ImGui.SetNextItemWidth(70)
    local SORT_LABELS = { 'Time', 'Status', 'Pri', 'Cls', 'Type', 'A-Z' }
    local SORT_KEYS = { 'time', 'status', 'priority', 'class', 'type', 'alpha' }
    local curSortIdx = idxOf(SORT_KEYS, ctrl.cooldown_sort_by or 'time')
    local newSortIdx = ImGui.Combo('##cdSortBy' .. idSuffix, curSortIdx, SORT_LABELS)
    if newSortIdx ~= curSortIdx then
        ctrl.cooldown_sort_by = SORT_KEYS[newSortIdx]
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Sort items by time, status, priority, or class') end

    ImGui.SameLine()
    -- Search Input
    ImGui.SetNextItemWidth(105)
    runtime.cooldownSearch = ImGui.InputTextWithHint('##cdSearch' .. idSuffix, 'Search...', runtime.cooldownSearch or '', 64)

    if isPopout then
        ImGui.SameLine()
        -- Transparency Slider
        ImGui.SetNextItemWidth(55)
        local newAlpha = ImGui.SliderFloat('##cdAlpha' .. idSuffix, ctrl.cooldown_alpha or 0.90, 0.10, 1.00, '%.2f')
        if newAlpha ~= ctrl.cooldown_alpha then
            ctrl.cooldown_alpha = newAlpha
        end
        if ImGui.IsItemHovered() then UI.setTooltip(string.format('Overlay transparency (current: %.2f)', ctrl.cooldown_alpha or 0.90)) end
    end

    ImGui.Separator()

    -- Filter items based on active criteria
    local filteredItems = {}
    local searchStr = (runtime.cooldownSearch or ''):lower()
    for _, itm in ipairs(allItems) do
        local passCat = true
        if ctrl.cooldown_category == 'Abilities' then passCat = (itm.kind == 'Skill')
        elseif ctrl.cooldown_category == 'AAs' then passCat = (itm.kind == 'AA')
        elseif ctrl.cooldown_category == 'Disciplines' then passCat = (itm.kind == 'Disc')
        elseif ctrl.cooldown_category == 'Spells' then passCat = (itm.kind == 'Spell')
        elseif ctrl.cooldown_category == 'Items' then passCat = (itm.kind == 'Item')
        end

        local passStatus = true
        if ctrl.cooldown_status_filter == 'Ready' then passStatus = itm.ready
        elseif ctrl.cooldown_status_filter == 'Cooldown' then passStatus = (not itm.ready and not itm.active)
        elseif ctrl.cooldown_status_filter == 'Active' then passStatus = itm.active
        end

        local passSearch = true
        if searchStr ~= '' then
            passSearch = string.find(itm.name:lower(), searchStr, 1, true) ~= nil
        end

        if passCat and passStatus and passSearch then
            table.insert(filteredItems, itm)
        end
    end

    -- Sort filtered items
    local sortKey = ctrl.cooldown_sort_by or 'time'
    table.sort(filteredItems, function(a, b)
        if sortKey == 'time' then
            -- 1. Active items first (running stances / active duration buffs)
            if a.active ~= b.active then
                return a.active
            end
            if a.active and b.active then
                return (a.activeSec or 0) < (b.activeSec or 0)
            end

            -- 2. Items on Cooldown NEXT at the top of the list
            local aInCd = (not a.ready)
            local bInCd = (not b.ready)
            if aInCd ~= bInCd then
                return aInCd
            end

            -- Both are on cooldown: sort by time remaining ascending (soonest to become ready first)
            if aInCd and bInCd then
                if math.abs((a.timeLeft or 0) - (b.timeLeft or 0)) > 0.05 then
                    return (a.timeLeft or 0) < (b.timeLeft or 0)
                end
                return (a.priority or 50) < (b.priority or 50)
            end

            -- 3. Both are Ready: sort by priority ascending (pri 1 before pri 50)
            if (a.priority or 50) ~= (b.priority or 50) then
                return (a.priority or 50) < (b.priority or 50)
            end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'status' then
            local statusRank = {
                ACTIVE = 1,
                COOLDOWN = 2,
                ['LOW END'] = 3,
                ['LOW MANA'] = 4,
                ['NEED BURN'] = 5,
                ['NEED BOSS'] = 6,
                ['MIN XTAR'] = 7,
                LOCKED = 8,
                BLOCKED = 9,
                READY = 10,
            }
            local rA = statusRank[a.status] or 11
            local rB = statusRank[b.status] or 11
            if rA ~= rB then return rA < rB end
            return (a.timeLeft or 0) < (b.timeLeft or 0)
        elseif sortKey == 'priority' then
            return (a.priority or 50) < (b.priority or 50)
        elseif sortKey == 'class' then
            if (a.cls or '') ~= (b.cls or '') then return (a.cls or '') < (b.cls or '') end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'type' then
            if (a.kind or '') ~= (b.kind or '') then return (a.kind or '') < (b.kind or '') end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'alpha' then
            return (a.name or ''):lower() < (b.name or ''):lower()
        end
        return false
    end)

    -- Render Items in Table View or Cards HUD View
    if #filteredItems == 0 then
        if #allItems == 0 then
            accent(MUTED, '  (No abilities, AAs, or disciplines enabled in loadout.)')
        else
            accent(MUTED, '  (No abilities match current filters.)')
        end
    elseif isTableView then
        -- Compact Table View
        local tableFlags = bit.bor(
            ImGuiTableFlags.Borders,
            ImGuiTableFlags.RowBg,
            ImGuiTableFlags.Resizable,
            ImGuiTableFlags.ScrollY,
            ImGuiTableFlags.SizingFixedFit
        )
        local isCompactMode = (ctrl.cooldown_compact ~= false)
        local colCount = isCompactMode and 4 or 6
        if ctrl.cooldown_show_inline_edit then colCount = colCount + 1 end

        if ImGui.BeginTable('##TriuneCooldownTable' .. idSuffix, colCount, tableFlags) then
            ImGui.TableSetupColumn('Cls', ImGuiTableColumnFlags.WidthFixed, 28)
            if not isCompactMode then
                ImGui.TableSetupColumn('Type', ImGuiTableColumnFlags.WidthFixed, 55)
            end
            ImGui.TableSetupColumn('Ability Name', ImGuiTableColumnFlags.WidthStretch, 130)
            if not isCompactMode then
                ImGui.TableSetupColumn('Trigger / Cond', ImGuiTableColumnFlags.WidthStretch, 110)
            end
            ImGui.TableSetupColumn('Status & Timer', ImGuiTableColumnFlags.WidthFixed, 115)
            if ctrl.cooldown_show_inline_edit then
                ImGui.TableSetupColumn('Tuning', ImGuiTableColumnFlags.WidthFixed, 120)
            end
            ImGui.TableSetupColumn('Act', ImGuiTableColumnFlags.WidthFixed, 36)
            ImGui.TableHeadersRow()

            for _, itm in ipairs(filteredItems) do
                ImGui.TableNextRow()
                ImGui.PushID('cdrow_' .. idSuffix .. '_' .. itm.kind .. '_' .. tostring(itm.cls) .. '_' .. tostring(itm.name))

                -- 1. Class Badge
                ImGui.TableNextColumn()
                local r, g, b, a = classColor(itm.cls)
                ImGui.TextColored(r, g, b, a, itm.cls) ---@diagnostic disable-line: param-type-mismatch
                if ImGui.IsItemHovered() then UI.setTooltip(string.format('Class: %s', itm.cls)) end

                -- Optional Type Column
                if not isCompactMode then
                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(itm.typeLabel or itm.kind)
                    if itm.timerGroup and ImGui.IsItemHovered() then
                        UI.setTooltip(string.format('EQ Timer Group: %s', itm.timerGroup))
                    end
                end

                -- 2. Ability Name
                ImGui.TableNextColumn()
                ImGui.Text(itm.name)
                if itm.timerGroup then
                    ImGui.SameLine()
                    accent(ARC, '[' .. itm.timerGroup .. ']')
                end
                if ImGui.IsItemHovered() then
                    local desc = string.format('%s (%s)\nPriority: %d\nTrigger: %s',
                        itm.name, itm.typeLabel or itm.kind, itm.priority or 50, itm.conditionText or '')
                    if itm.reason and itm.reason ~= '' then
                        desc = desc .. '\nStatus Note: ' .. itm.reason
                    end
                    if itm.timerGroup then
                        desc = desc .. string.format('\nShared EQ Timer Group: %s', itm.timerGroup)
                    end
                    UI.setTooltip(desc)
                end

                -- Optional Trigger / Condition Column
                if not isCompactMode then
                    ImGui.TableNextColumn()
                    ImGui.Text(itm.conditionText or '')
                    if itm.burn_only then
                        ImGui.SameLine(); accent({ 1.0, 0.35, 0.35, 1.0 }, '[B]')
                    end
                    if itm.boss_only then
                        ImGui.SameLine(); accent(GOLD, '[Boss]')
                    end
                end

                -- 3. Status Bar & Timer
                ImGui.TableNextColumn()
                if itm.active then
                    local actTotal = (itm.activeTotalSec and itm.activeTotalSec > 0) and itm.activeTotalSec or (itm.totalSec > 0 and itm.totalSec or 18)
                    local frac = math.min(1.0, math.max(0.0, (itm.activeSec or 0) / actTotal))
                    local tStr = (itm.activeSec and itm.activeSec > 0) and string.format('ACT: %s', fmtSec(math.ceil(itm.activeSec))) or 'ACTIVE'
                    UI.drawStatusProgressBar(frac, 110, 15, tStr, ARC[1], ARC[2], ARC[3], 1.0)
                elseif itm.ready then
                    if itm.status ~= 'READY' then
                        -- Gated ready (e.g. LOW END, NEED BURN, MIN XTAR, BLOCKED)
                        UI.drawStatusProgressBar(1.0, 110, 15, itm.status, 0.85, 0.55, 0.15, 1.0)
                    else
                        UI.drawStatusProgressBar(1.0, 110, 15, 'READY', GOOD[1], GOOD[2], GOOD[3], 1.0)
                    end
                else
                    local cdTotal = (itm.totalSec and itm.totalSec > 0) and itm.totalSec or math.max(itm.timeLeft or 0, 30)
                    local frac = math.max(0.0, math.min(1.0, 1.0 - ((itm.timeLeft or 0) / cdTotal)))
                    local tStr = fmtSec(math.ceil(itm.timeLeft or 0))
                    UI.drawStatusProgressBar(frac, 110, 15, tStr, WARN[1], WARN[2], WARN[3], 1.0)
                end
                if itm.reason and itm.reason ~= '' and ImGui.IsItemHovered() then
                    UI.setTooltip(itm.reason)
                end

                -- Optional In-Place Tuning Column
                if ctrl.cooldown_show_inline_edit then
                    ImGui.TableNextColumn()
                    if itm.entry then
                        local enVal = ImGui.Checkbox('##tblEn', itm.entry.enabled or false)
                        itm.entry.enabled = enVal
                        if itm.entry.pct ~= nil then
                            ImGui.SameLine(); ImGui.SetNextItemWidth(55)
                            local spVal = ImGui.SliderInt('##tblPct', tonumber(itm.entry.pct) or 100, 0, 100, '%d%%')
                            itm.entry.pct = spVal
                        end
                        if itm.entry.burn_only ~= nil then
                            ImGui.SameLine()
                            local boVal = ImGui.Checkbox('B##tblBo', itm.entry.burn_only or false)
                            itm.entry.burn_only = boVal
                            if ImGui.IsItemHovered() then UI.setTooltip('Burn Only toggle') end
                        end
                    end
                end

                -- 4. Direct Action Button
                ImGui.TableNextColumn()
                if itm.ready and not itm.active then
                    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                    local pCount = 0
                    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
                    if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.18, 0.70, 0.28, 1.0) then pCount = pCount + 1 end
                    if Col and pcall(ImGui.PushStyleColor, Col.Text, 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end
                    if ImGui.Button('Use##cdBtnUse', 34, 16) then
                        if itm.use then itm.use() end
                    end
                    if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
                    if ImGui.IsItemHovered() then UI.setTooltip(string.format('Click to execute %s', itm.name)) end
                else
                    ImGui.TextDisabled(' --')
                end

                ImGui.PopID()
            end

            ImGui.EndTable()
        end
    else
        -- Compact HUD Cards View
        if ImGui.BeginChild('##TriuneCooldownCardsList' .. idSuffix, 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
            for _, itm in ipairs(filteredItems) do
                ImGui.PushID('card_' .. idSuffix .. '_' .. itm.kind .. '_' .. tostring(itm.cls) .. '_' .. tostring(itm.name))

                local r, g, b, a = classColor(itm.cls)
                ImGui.TextColored(r, g, b, a, string.format('[%s]', itm.cls)) ---@diagnostic disable-line: param-type-mismatch
                ImGui.SameLine()

                ImGui.Text(itm.name)
                if itm.timerGroup then
                    ImGui.SameLine()
                    accent(ARC, '[' .. itm.timerGroup .. ']')
                end

                ImGui.SameLine(); ImGui.SetNextItemWidth(105)
                if itm.active then
                    local actTotal = (itm.activeTotalSec and itm.activeTotalSec > 0) and itm.activeTotalSec or (itm.totalSec > 0 and itm.totalSec or 18)
                    local frac = math.min(1.0, math.max(0.0, (itm.activeSec or 0) / actTotal))
                    local tStr = (itm.activeSec and itm.activeSec > 0) and string.format('ACT: %s', fmtSec(math.ceil(itm.activeSec))) or 'ACTIVE'
                    UI.drawStatusProgressBar(frac, 105, 15, tStr, ARC[1], ARC[2], ARC[3], 1.0)
                elseif itm.ready then
                    if itm.status ~= 'READY' then
                        UI.drawStatusProgressBar(1.0, 105, 15, itm.status, 0.85, 0.55, 0.15, 1.0)
                    else
                        UI.drawStatusProgressBar(1.0, 105, 15, 'READY', GOOD[1], GOOD[2], GOOD[3], 1.0)
                    end
                else
                    local cdTotal = (itm.totalSec and itm.totalSec > 0) and itm.totalSec or math.max(itm.timeLeft or 0, 30)
                    local frac = math.max(0.0, math.min(1.0, 1.0 - ((itm.timeLeft or 0) / cdTotal)))
                    local tStr = fmtSec(math.ceil(itm.timeLeft or 0))
                    UI.drawStatusProgressBar(frac, 105, 15, tStr, WARN[1], WARN[2], WARN[3], 1.0)
                end

                if itm.ready and not itm.active then
                    ImGui.SameLine()
                    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                    local pCount = 0
                    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
                    if ImGui.Button('Use##cardUse', 34, 15) then
                        if itm.use then itm.use() end
                    end
                    if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
                end

                ImGui.PopID()
            end
        end
        ImGui.EndChild()
    end
end

function UI.drawCooldownWindow()
    if not ctrl.show_cooldowns then return end
    UI.pushTheme()

    if ctrl.cooldown_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.cooldown_alpha)
    end
    ImGui.SetNextWindowSize(500, 340, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.cooldown_locked then
        winFlags = bit.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoMove)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 3, 2)

    local show
    ctrl.show_cooldowns, show = ImGui.Begin('Triune Cooldown Monitor v' .. VERSION .. '###triuneCooldowns', ctrl.show_cooldowns, winFlags)
    if not ctrl.show_cooldowns then
        ImGui.End()
        ImGui.PopStyleVar(3)
        UI.popTheme()
        return
    end

    if show then
        UI.renderCooldownContent('_win', true)
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    UI.popTheme()
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

function runtime.lowestHpAlly()
    local bestId, bestHp = mq.TLO.Me.ID(), (mq.TLO.Me.PctHPs() or 100)
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and not m.Dead() then
            local hp = m.PctHPs() or 100
            if hp < bestHp then
                bestHp = hp; bestId = m.ID()
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
        local slots = 13
        pcall(function() slots = mq.TLO.Me.XTargetSlots() or 13 end)
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) and not isGroupOrRaidMember(id) and not isSpawnPetOrPlayer(id) then
                    local s = mq.TLO.Spawn(id)
                    local stype = (s() and s.Type()) or ''
                    if (stype == 'NPC' or stype == 'Pet')
                        and not s.Dead() and stype ~= 'Corpse'
                        and isHostileTarget(id)
                        and not isIgnored(s.CleanName())
                        and (includeUnreachable or not isUnreachable(id)) then
                        cnt = cnt + 1
                    end
                end
            end
        end
    end)
    -- Fallback: if XTarget list is unpopulated or empty, but we have a valid live NPC target, count as at least 1
    if cnt == 0 and not includeUnreachable then
        pcall(function()
            local t = mq.TLO.Target
            if t() and (t.ID() or 0) > 0 and not isGroupOrRaidMember(t.ID()) and not isSpawnPetOrPlayer(t.ID()) and isHostileTarget(t.ID()) then
                local stype = t.Type() or ''
                if (stype == 'NPC' or stype == 'Pet') and not t.Dead() and stype ~= 'Corpse'
                    and not isIgnored(t.CleanName()) and not isUnreachable(t.ID()) then
                    cnt = 1
                end
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

isXTargetId = function(id)
    if not id or id <= 0 then return false end
    if isGroupOrRaidMember(id) or isSpawnPetOrPlayer(id) then return false end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) == id
            and not xt.Dead() and (xt.Type() or '') ~= 'Corpse'
            and not isIgnored(xt.CleanName()) then
            local stype = xt.Type() or ''
            if (stype == 'NPC' or stype == 'Pet') and isHostileTarget(id) then
                return true
            end
        end
    end
    return false
end

-- Returns true if an action (spell, AA, disc, skill) is detrimental (offensive).
function runtime.isDetrimentalAction(name, targetToken, entry)
    local k = entry and entry.kind
    return isDetrimentalSpell(name, nil, k, targetToken)
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
        maxRange = (runtime.maxMeleeDistance and runtime.maxMeleeDistance(targetId)) or 15
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

local function isPoisonedOrDiseased(targetId)
    if not targetId or targetId <= 0 then return false end

    -- 1. Check local player (Me)
    local myId = 0
    pcall(function() myId = mq.TLO.Me.ID() or 0 end)
    if targetId == myId then
        -- 1a. Check numeric counter counts (CountersPoison / CountersDisease)
        local cp, cd = 0, 0
        pcall(function()
            local cpo = mq.TLO.Me.CountersPoison
            if cpo then cp = tonumber(cpo()) or 0 end
        end)
        if cp > 0 then return true end

        pcall(function()
            local cdo = mq.TLO.Me.CountersDisease
            if cdo then cd = tonumber(cdo()) or 0 end
        end)
        if cd > 0 then return true end

        -- 1b. Check direct buff properties on Me (Me.Poisoned / Me.Diseased)
        local poisoned, diseased = false, false
        pcall(function()
            local p = mq.TLO.Me.Poisoned
            if p and p() then
                local str = tostring(p())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    poisoned = true
                end
            end
        end)
        if poisoned then return true end

        pcall(function()
            local d = mq.TLO.Me.Diseased
            if d and d() then
                local str = tostring(d())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    diseased = true
                end
            end
        end)
        if diseased then return true end

        -- 1c. Check Debuffs plugin if loaded
        local debuffP, debuffD = 0, 0
        pcall(function()
            if mq.TLO.Debuffs then
                debuffP = tonumber(mq.TLO.Debuffs.Poisoned()) or 0
                debuffD = tonumber(mq.TLO.Debuffs.Diseased()) or 0
            end
        end)
        if debuffP > 0 or debuffD > 0 then return true end

        return false
    end

    -- 2. Check other spawns (group members, box characters, target)
    local s = nil
    pcall(function() s = mq.TLO.Spawn(targetId) end)
    if not s or not s() then return false end

    local cleanName = ''
    pcall(function() cleanName = s.CleanName() or '' end)

    -- 2a. NetBots check (trio / box group members sharing debuff counters)
    if cleanName ~= '' then
        local nbP, nbD = 0, 0
        pcall(function()
            local nb = mq.TLO.NetBots(cleanName)
            if nb and nb() then
                nbP = tonumber(nb.Poisoned()) or 0
                nbD = tonumber(nb.Diseased()) or 0
                if nbP == 0 and nbD == 0 then
                    local det = tostring(nb.Detrimental() or '')
                    if det:find('Poison') or det:find('Disease') then
                        nbP = 1
                    end
                end
            end
        end)
        if nbP > 0 or nbD > 0 then return true end
    end

    -- 2b. Current Target check
    local isTarget = false
    pcall(function() isTarget = ((mq.TLO.Target.ID() or 0) == targetId) end)
    if isTarget then
        local tp, td = false, false
        pcall(function()
            local p = mq.TLO.Target.Poisoned
            if p and p() then
                local str = tostring(p())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    tp = true
                end
            end
        end)
        if tp then return true end

        pcall(function()
            local d = mq.TLO.Target.Diseased
            if d and d() then
                local str = tostring(d())
                if str ~= '' and str ~= 'NULL' and str ~= 'nil' then
                    td = true
                end
            end
        end)
        if td then return true end
    end

    -- 2c. Group Member check
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == targetId then
            local mp, md = false, false
            pcall(function()
                if m.Poisoned and m.Poisoned() then mp = true end
                if m.Diseased and m.Diseased() then md = true end
                if m.CountersPoison and (tonumber(m.CountersPoison()) or 0) > 0 then mp = true end
                if m.CountersDisease and (tonumber(m.CountersDisease()) or 0) > 0 then md = true end
            end)
            if mp or md then return true end
        end
    end

    return false
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
    if when == 'has Poison/Disease' and isPoisonedOrDiseased then
        for _, pid in ipairs(allPets) do
            if isPoisonedOrDiseased(pid) then
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
    if when == 'my HP <=' then return pctHP(mq.TLO.Me.ID()) <= pct end
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
    -- For pet-summon gems (Nec/Mag/Bst warder/pet lines, etc.): this server keeps
    -- a separate simultaneous pet per pet class, so this checks THIS gem's OWN
    -- class's tracked pet specifically (myPets), not the single-slot Me.Pet --
    -- otherwise summoning class A's pet would make class B's gem think it
    -- already has one too, per class C never gets cast ("cast one, gave up").
    if when == 'missing pet' then
        -- 1. If we have an alive tracked pet for this specific class, pet is NOT missing
        if cls and petState.myPets[cls] and isSpawnAlive(petState.myPets[cls]) then
            return false
        end

        -- 2. If Me.Pet is alive and belongs to us, check if it can satisfy this class
        local curPetId = 0
        pcall(function() curPetId = mq.TLO.Me.Pet.ID() or 0 end)
        if curPetId > 0 and isSpawnAlive(curPetId) and isSpawnMyPet(curPetId) then
            local petClasses = {}
            for _, c in ipairs(myClasses) do if petState.PET_CLASSES[c] then petClasses[#petClasses + 1] = c end end
            if #petClasses <= 1 or not cls then
                if cls then petState.myPets[cls] = curPetId end
                return false
            end
            local claimedByOther = false
            for k, pid in pairs(petState.myPets) do
                if k ~= cls and pid == curPetId and isSpawnAlive(pid) then
                    claimedByOther = true
                    break
                end
            end
            if not claimedByOther and cls then
                petState.myPets[cls] = curPetId
                return false
            end
        end

        -- 3. Check all nearby living pets belonging to us
        local allPets = getAllMyPets()
        if cls then
            for _, pid in ipairs(allPets) do
                local claimedByOther = false
                for k, cpid in pairs(petState.myPets) do
                    if k ~= cls and cpid == pid and isSpawnAlive(cpid) then
                        claimedByOther = true
                        break
                    end
                end
                if not claimedByOther then
                    petState.myPets[cls] = pid
                    return false
                end
            end
        elseif #allPets > 0 then
            return false
        end

        return true
    end
    if when == 'ally is Dead' then
        local s = mq.TLO.Spawn(targetId); return s() and s.Dead()
    end
    if when == 'has Poison/Disease' then
        if token and baseTok(token) == 'Whole Group' then
            if isPoisonedOrDiseased(mq.TLO.Me.ID()) then return true end
            local total = 0
            pcall(function() total = mq.TLO.Group.Members() or 0 end)
            for i = 0, total do
                local m = nil
                pcall(function() m = mq.TLO.Group.Member(i) end)
                if m and m() and (m.ID() or 0) > 0 and isPoisonedOrDiseased(m.ID()) then return true end
            end
            return false
        end
        return isPoisonedOrDiseased(targetId)
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
    local minMana = tonumber(ctrl and ctrl.min_mana_pct) or 0
    local pctMana = tonumber(mq.TLO.Me.PctMana() or 100) or 100
    if not ctrl.burn and minMana > 0 and pctMana < minMana then return false end
    if not mq.TLO.Me.SpellReady(g.spell)() then return false end

    local dur = 0
    pcall(function() dur = tonumber(sp.Duration()) or 0 end)
    dur = tonumber(dur) or 0
    if dur > 0 and buffActive(id, g.spell) and not (g.cls == 'Brd' and g.when == 'twist while fighting') then
        return false
    end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    local hostileTarget = (orig > 0 and isHostileTarget and isHostileTarget(orig))
    local needsTarget = (not selfCast) or (not hostileTarget and orig > 0 and orig ~= id)
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
        castTracker.targetRequired = isDet or (isTargetRequiredSpell(g.spell) and (not selfCast or orig == id))
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
        petState.lastCastCls = g.cls
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
    local needsTarget = (not selfCast) or (not hostileTarget and orig > 0 and orig ~= id)
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
        castTracker.targetRequired = isDet or (isTargetRequiredSpell(name) and (not selfCast or orig == id))
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
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if not isFD and wasAttacking and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end



function runtime.findChildRecursive(parent, targetName)
    if not parent or not parent() or not targetName or targetName == '' then return nil end
    local tLower = targetName:lower()

    -- Try direct Child lookup first
    local direct = nil
    pcall(function() direct = parent.Child(targetName) end)
    if direct and direct() then return direct end

    -- Check immediate children by iterating FirstChild -> Next
    local curr = nil
    pcall(function() curr = parent.FirstChild end)
    local safety = 0
    while curr and curr() and safety < 120 do
        safety = safety + 1
        local match = false
        pcall(function()
            local nm = curr.Name and curr.Name()
            local sid = curr.ScreenID and curr.ScreenID()
            if (nm and nm:lower() == tLower) or (sid and sid:lower() == tLower) then
                match = true
            end
        end)
        if match then return curr end

        -- Recurse into child if it has children
        local hasChildren = false
        pcall(function() hasChildren = curr.Children and (curr.Children() == true) end)
        if hasChildren then
            local found = runtime.findChildRecursive(curr, targetName)
            if found and found() then return found end
        end

        local nextSibling = nil
        pcall(function() nextSibling = curr.Next end)
        curr = nextSibling
    end
    return nil
end

function runtime.findAAInWindowLists(targetName)
    local win = nil
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w() then win = w end
    end)
    if not win then return nil, nil, nil, nil end

    local listCandidates = {
        { name = 'AAW_SpecialList', tab = 4 },
        { name = 'AAW_ClassList', tab = 3 },
        { name = 'AAW_ArchList', tab = 2 },
        { name = 'AAW_GeneralList', tab = 1 },
        { name = 'AA_SpecialList', tab = 4 },
        { name = 'AA_ClassList', tab = 3 },
        { name = 'AA_ArchetypeList', tab = 2 },
        { name = 'AA_GeneralList', tab = 1 },
        { name = 'SpecialList', tab = 4 },
        { name = 'ClassList', tab = 3 },
        { name = 'ArchList', tab = 2 },
        { name = 'GeneralList', tab = 1 },
        { name = 'AAW_List', tab = 1 },
        { name = 'AA_List', tab = 1 }
    }

    local cleanTarget = tostring(targetName or ''):lower():gsub('[^%a%d]', '')
    local isFireworks = cleanTarget:find('firework') ~= nil

    -- If searching for Fireworks, prioritize Special tab listbox
    if isFireworks then
        table.sort(listCandidates, function(a, b)
            if a.tab == 4 and b.tab ~= 4 then return true end
            if b.tab == 4 and a.tab ~= 4 then return false end
            return a.tab > b.tab
        end)
    end

    for _, cand in ipairs(listCandidates) do
        local child = runtime.findChildRecursive(win, cand.name)
        if child and child() and child.Items then
            local count = 0
            pcall(function() count = tonumber(child.Items() or 0) or 0 end)
            if count > 0 and count <= 500 then
                for row = 1, count do
                    local rowText = nil
                    pcall(function() rowText = child.List(row, 1)() or child.List(row)() end)
                    if rowText and type(rowText) == 'string' and rowText ~= '' then
                        local cleanRow = rowText:lower():gsub('[^%a%d]', '')
                        local matched = false
                        if cleanRow == cleanTarget then
                            matched = true
                        elseif cleanRow ~= '' and cleanTarget ~= '' and (cleanRow:find(cleanTarget, 1, true) or cleanTarget:find(cleanRow, 1, true)) then
                            matched = true
                        elseif isFireworks and cleanRow:find('firework') then
                            matched = true
                        end
                        if matched then
                            return cand.name, row, cand.tab, child
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil
end

function runtime.recordScannedAA(list, foundMap, name)
    if not name or name == '' or tonumber(name) then return end
    name = tostring(name):match('^%s*(.-)%s*$')
    if name == '' or foundMap[name] then return end
    local rank, maxRank, cost, canTrain, pointsSpent, id, passive, aaType = 0, 0, 0, false, 0, 0, false, 0
    local isCharacterAA = false
    pcall(function()
        local ma = mq.TLO.Me.AltAbility(name)
        if ma and ma() then
            id = tonumber(ma.ID and ma.ID() or 0) or 0
            if id > 0 then
                isCharacterAA = true
                rank = tonumber(ma.Rank and ma.Rank() or 0) or 0
                maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0
                cost = tonumber(ma.Cost and ma.Cost() or 0) or 0
                canTrain = (ma.CanTrain and ma.CanTrain() == true)
                pointsSpent = tonumber(ma.PointsSpent and ma.PointsSpent() or 0) or 0
                passive = (ma.Passive and ma.Passive() == true)
                aaType = tonumber(ma.Type and ma.Type() or 0) or 0
            end
        end
        if isCharacterAA and (maxRank == 0 or (cost == 0 and not (maxRank > 0 and rank >= maxRank))) then
            local ga = mq.TLO.AltAbility(name)
            if ga and ga() then
                if maxRank == 0 then maxRank = tonumber(ga.MaxRank and ga.MaxRank() or 0) or 0 end
                if cost == 0 then cost = tonumber(ga.Cost and ga.Cost() or 0) or 0 end
                if not canTrain and ga.CanTrain then canTrain = (ga.CanTrain() == true) end
                if aaType == 0 and ga.Type then aaType = tonumber(ga.Type() or 0) or 0 end
            end
        end
        -- Fallback: allow abilities that were explicitly read from the character's in-game Special tab or AAWindow
        if not isCharacterAA and runtime.specialTabAAs then
            for _, sName in ipairs(runtime.specialTabAAs) do
                if sName == name then
                    local ga = mq.TLO.AltAbility(name)
                    if ga and ga() then
                        id = tonumber(ga.ID and ga.ID() or 0) or 0
                        maxRank = tonumber(ga.MaxRank and ga.MaxRank() or 0) or 0
                        cost = tonumber(ga.Cost and ga.Cost() or 0) or 0
                        canTrain = (ga.CanTrain and ga.CanTrain() == true)
                        aaType = tonumber(ga.Type and ga.Type() or 0) or 0
                        isCharacterAA = true
                    end
                    break
                end
            end
        end
    end)
    if isCharacterAA and (maxRank > 0 or rank > 0 or canTrain or cost > 0) then
        local entry = {
            name = name,
            rank = rank,
            maxRank = maxRank,
            cost = cost,
            canTrain = canTrain,
            pointsSpent = pointsSpent,
            id = id,
            passive = passive,
            type = aaType,
            fullyTrained = (maxRank > 0 and rank >= maxRank)
        }
        foundMap[name] = entry
        list[#list + 1] = entry
    end
end

function runtime.readSpecialTabNamesFromUI()
    local win = nil
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w() then win = w end
    end)
    if not win then return nil end

    local specialCandidates = {
        'AAW_SpecialList', 'AA_SpecialList', 'SpecialList', 'Special_List',
        'AAW_Special_List', 'AAW_SpecList', 'AA_SpecList'
    }
    local tabParents = { 'AAW_Subwindows', 'AA_Subwindows', 'AA_SubWnd', 'AAW_SpecialTabPage', 'AA_SpecialTabPage' }

    for _, lName in ipairs(specialCandidates) do
        local child = nil
        pcall(function()
            child = win.Child(lName)
            if not child or not child() then
                for _, tp in ipairs(tabParents) do
                    local p = win.Child(tp)
                    if p and p() then
                        local sc = p.Child(lName)
                        if sc and sc() then child = sc; break end
                    end
                end
            end
            if not child or not child() then
                child = runtime.findChildRecursive(win, lName)
            end
        end)

        if child and child() and child.Items then
            local count = 0
            pcall(function() count = tonumber(child.Items() or 0) or 0 end)
            if count > 0 and count <= 1000 then
                local names = {}
                local seen = {}
                for row = 1, count do
                    local rowTxt = nil
                    pcall(function() rowTxt = child.List(row, 1)() or child.List(row)() end)
                    if rowTxt and type(rowTxt) == 'string' and rowTxt ~= '' then
                        local trimmed = rowTxt:match('^%s*(.-)%s*$')
                        if trimmed and trimmed ~= '' and not seen[trimmed] then
                            seen[trimmed] = true
                            names[#names + 1] = trimmed
                        end
                    end
                end
                if #names > 0 then
                    return names
                end
            end
        end
    end
    return nil
end

function runtime.readSpecialTabOnce(force)
    if not force and runtime.specialTabReadDone and runtime.specialTabAAs and #runtime.specialTabAAs > 0 then
        return runtime.specialTabAAs
    end

    -- 1. Try non-blocking read if already populated in UI
    local names = runtime.readSpecialTabNamesFromUI()
    if names and #names > 0 then
        runtime.specialTabAAs = names
        runtime.specialTabReadDone = true
        return names
    end

    -- 2. Open AAWindow if not open, select tab 4, read, and restore window state
    local wasOpen = false
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w() and w.Open and w.Open() then wasOpen = true end
    end)

    if not wasOpen then
        pcall(function()
            local w = mq.TLO.Window('AAWindow')
            if w and w() and w.DoOpen then w.DoOpen() end
        end)
        mq.cmd('/windowstate AAWindow open')
        mq.cmd('/nomodkey /keypress alt_advancement')
        mq.delay(250)
    end

    -- Select Tab 4 (Special)
    mq.cmd('/nomodkey /notify AAWindow AAW_Subwindows tabselect 4')
    mq.cmd('/nomodkey /notify AAWindow AA_Subwindows tabselect 4')
    pcall(function()
        local win = mq.TLO.Window('AAWindow')
        if win and win() then
            local sub = runtime.findChildRecursive(win, 'AAW_Subwindows') or runtime.findChildRecursive(win, 'AA_Subwindows')
            if sub and sub() and sub.SetCurrentTab then sub.SetCurrentTab(4) end
        end
    end)
    mq.delay(150)

    names = runtime.readSpecialTabNamesFromUI()
    if names and #names > 0 then
        runtime.specialTabAAs = names
        runtime.specialTabReadDone = true
        print(string.format('\ag[Triune]\ax Read %d abilities from AA Special tab.', #names))
    else
        runtime.specialTabReadDone = true
    end

    if not wasOpen then
        pcall(function()
            local w = mq.TLO.Window('AAWindow')
            if w and w() and w.DoClose then w.DoClose() end
        end)
        mq.cmd('/windowstate AAWindow close')
        mq.cmd('/nomodkey /keypress alt_advancement')
    end

    return runtime.specialTabAAs or {}
end

function runtime.scanPlayerAAs(force)
    local now = os.clock()
    if not force and runtime.lastAAScanAt and (now - runtime.lastAAScanAt) < 10.0 and runtime.scannedAAs and #runtime.scannedAAs > 0 then
        return runtime.scannedAAs
    end
    runtime.lastAAScanAt = now

    local foundMap = {}
    local list = {}

    -- 1. Scan in-game AAWindow lists if AAWindow is open
    pcall(function()
        local win = mq.TLO.Window('AAWindow')
        if win and win() then
            local listNames = {
                'AAW_SpecialList', 'AA_SpecialList', 'SpecialList', 'Special_List',
                'AAW_Special_List', 'AA_Special_List', 'AAW_SpecList', 'AA_SpecList',
                'AAW_GeneralList', 'AAW_ArchetypeList', 'AAW_ClassList', 'AAW_FocusList',
                'AA_GeneralList', 'AA_ArchetypeList', 'AA_ClassList', 'AA_FocusList',
                'AAW_List', 'AA_List', 'AAW_SearchResultList', 'AA_SearchResultList'
            }
            local tabParents = { 'AAW_Subwindows', 'AA_Subwindows', 'AA_SubWnd', 'AAW_SpecialTabPage', 'AA_SpecialTabPage' }
            for _, lName in ipairs(listNames) do
                local child = win.Child(lName)
                if not child or not child() then
                    for _, tp in ipairs(tabParents) do
                        local p = win.Child(tp)
                        if p and p() then
                            local sc = p.Child(lName)
                            if sc and sc() then child = sc; break end
                        end
                    end
                end
                if child and child() and child.Items then
                    local count = tonumber(child.Items() or 0) or 0
                    if count > 0 and count <= 1000 then
                        for row = 1, count do
                            local rowTxt = child.List(row, 1)() or child.List(row)()
                            if rowTxt and rowTxt ~= '' then
                                runtime.recordScannedAA(list, foundMap, rowTxt)
                            end
                        end
                    end
                end
            end
        end
    end)

    -- 2. Scan known DATA.aas combat abilities
    if DATA and DATA.aas then
        for _, cls in ipairs(myClasses) do
            for _, aList in pairs(DATA.aas[cls] or {}) do
                if type(aList) == 'table' then
                    for _, item in ipairs(aList) do
                        local nm = type(item) == 'table' and (item[1] or item.name) or tostring(item)
                        runtime.recordScannedAA(list, foundMap, nm)
                    end
                end
            end
        end
    end

    -- 3. Scan common general, archetype, and passive Norrath AAs
    local COMMON_AAS = {
        'Run Speed', 'Innate Run Speed', 'Combat Agility', 'Combat Stability', 'Natural Durability',
        'Physical Enhancement', 'Planar Power', 'Planar Durability', 'First Aid', 'Bandage Wounds',
        'Innate Strength', 'Innate Stamina', 'Innate Agility', 'Innate Dexterity', 'Innate Intelligence',
        'Innate Wisdom', 'Innate Charisma', 'Spell Casting Mastery', 'Spell Casting Reinforcement',
        'Spell Casting Subtlety', 'Spell Casting Fury', 'Healing Adept', 'Healing Gift', 'Combat Fury',
        'Ambidexterity', 'Dual Wield', 'Double Attack', 'Flurry', 'Critical Affliction', 'Destructive Fury',
        'Mental Clarity', 'Body and Mind', 'Delay Death', 'New Tanaan Crafting Mastery', 'Baking Mastery',
        'Blacksmithing Mastery', 'Brewing Mastery', 'Fletching Mastery', 'Jewelcraft Mastery',
        'Pottery Mastery', 'Tailoring Mastery', 'Salvage', 'Origin', 'Chaotic Stab', 'Sinister Strikes',
        'Headshot', 'Endless Quiver', 'Archery Mastery', 'Weapon Affinity', 'Ferocity', 'Punishing Blow',
        'Hastened Purification', 'Hastened Curing', 'Mass Group Buff', 'Radiant Cure', 'Purification',
        'Suspend Minion', 'Pet Affinity', 'Companion\'s Fury', 'Companion\'s Strength', 'Companion\'s Durability'
    }
    for _, nm in ipairs(COMMON_AAS) do
        runtime.recordScannedAA(list, foundMap, nm)
    end

    -- 4. Scan Special tab abilities (from one-time read of the Special tab)
    local specialList = runtime.specialTabAAs
    if not specialList or #specialList == 0 then
        local uiNames = runtime.readSpecialTabNamesFromUI()
        if uiNames and #uiNames > 0 then
            runtime.specialTabAAs = uiNames
            runtime.specialTabReadDone = true
            specialList = uiNames
        else
            runtime.pendingReadSpecialTab = true
        end
    end
    if specialList and #specialList > 0 then
        for _, nm in ipairs(specialList) do
            runtime.recordScannedAA(list, foundMap, nm)
        end
    end
    if ctrl.auto_spend_aa_name and ctrl.auto_spend_aa_name ~= '' then
        runtime.recordScannedAA(list, foundMap, ctrl.auto_spend_aa_name)
    end

    -- 5. Scan character AltAbility indices
    pcall(function()
        for idx = 1, 1000 do
            local ma = mq.TLO.Me.AltAbility(idx)
            if ma and ma() then
                local nm = ma.Name and ma.Name()
                if nm and nm ~= '' then runtime.recordScannedAA(list, foundMap, nm) end
            end
        end
    end)

    -- 6. Saved priorities
    if ctrl.auto_aa_priorities then
        for nm in pairs(ctrl.auto_aa_priorities) do
            runtime.recordScannedAA(list, foundMap, nm)
        end
    end

    runtime.scannedAAs = list
    runtime.scannedAAMap = foundMap
    runtime.aaFilterDirty = true
    return list
end

function runtime.getFilteredSortedAAs()
    if not runtime.scannedAAs or #runtime.scannedAAs == 0 then
        runtime.scanPlayerAAs(false)
    end

    if not runtime.aaFilterDirty and runtime.filteredSortedAAs then
        return runtime.filteredSortedAAs
    end

    local result = {}
    local rawQuery = ctrl.auto_aa_search or ''
    local query = rawQuery:lower():match('^%s*(.-)%s*$')
    local hideMaxed = ctrl.auto_aa_hide_maxed or false
    local onlyPrio = ctrl.auto_aa_only_prioritized or false
    local priorities = ctrl.auto_aa_priorities or {}

    for _, item in ipairs(runtime.scannedAAs or {}) do
        local match = true
        if hideMaxed and item.fullyTrained then
            match = false
        end
        if match and onlyPrio and not priorities[item.name] then
            match = false
        end
        if match and query and query ~= '' then
            if not item.name:lower():find(query, 1, true) then
                match = false
            end
        end
        if match then
            result[#result + 1] = item
        end
    end

    local sortBy = ctrl.auto_aa_sort_by or 'name'
    local asc = (ctrl.auto_aa_sort_asc ~= false)

    table.sort(result, function(a, b)
        if sortBy == 'cost' then
            local costA = a.fullyTrained and 999999 or (a.cost or 0)
            local costB = b.fullyTrained and 999999 or (b.cost or 0)
            if costA ~= costB then
                if asc then return costA < costB else return costA > costB end
            end
            return a.name:lower() < b.name:lower()
        elseif sortBy == 'trained' then
            local tA = a.fullyTrained and 1 or 0
            local tB = b.fullyTrained and 1 or 0
            if tA ~= tB then
                if asc then return tA < tB else return tA > tB end
            end
            return a.name:lower() < b.name:lower()
        else -- 'name'
            local nA = a.name:lower()
            local nB = b.name:lower()
            if nA ~= nB then
                if asc then return nA < nB else return nA > nB end
            end
            return (a.cost or 0) < (b.cost or 0)
        end
    end)

    runtime.filteredSortedAAs = result
    runtime.aaFilterDirty = false
    return result
end

function runtime.startAATrainWorkflow(targetName)
    if runtime.pendingAATrain then return false end
    targetName = targetName or ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'

    local aaId = 0
    local aaType = 0
    pcall(function()
        local ma = mq.TLO.Me.AltAbility(targetName)
        if ma and ma() then
            if ma.ID then aaId = tonumber(ma.ID() or 0) or 0 end
            if ma.Type then aaType = tonumber(ma.Type() or 0) or 0 end
        end
        if aaId == 0 or aaType == 0 then
            local ga = mq.TLO.AltAbility(targetName)
            if ga and ga() then
                if aaId == 0 and ga.ID then aaId = tonumber(ga.ID() or 0) or 0 end
                if aaType == 0 and ga.Type then aaType = tonumber(ga.Type() or 0) or 0 end
            end
        end
    end)
    if aaId == 0 and (targetName:lower():find('firework') or targetName == (ctrl.auto_spend_aa_name or '')) then
        aaId = tonumber(ctrl.auto_spend_aa_id or 17788) or 17788
        aaType = 4
    end

    local prefTab = 1
    if aaType == 4 or targetName:lower():find('firework') then
        prefTab = 4
    elseif aaType == 3 then
        prefTab = 3
    elseif aaType == 2 then
        prefTab = 2
    elseif aaType == 1 then
        prefTab = 1
    end

    runtime.pendingAATrain = {
        name = targetName,
        aaId = aaId,
        aaType = aaType,
        targetTab = prefTab,
        step = 'open',
        tab = prefTab,
        maxTabs = 4,
        openedByUs = false,
        nextStepAt = os.clock(),
        retries = 0
    }
    print(string.format('\ag[Triune]\ax Initiating AA Window train sequence for "%s" (ID: %d, Tab: %d)...', targetName, aaId, prefTab))
    return true
end

function runtime.processAATrainWorkflow()
    local task = runtime.pendingAATrain
    if not task then return end
    local now = os.clock()
    if now < (task.nextStepAt or 0) then return end

    if task.step == 'open' then
        local isOpen = false
        pcall(function()
            local w = mq.TLO.Window('AAWindow')
            if w and w() and w.Open and w.Open() then isOpen = true end
        end)
        if not isOpen then
            task.openedByUs = true
            pcall(function()
                local w = mq.TLO.Window('AAWindow')
                if w and w() and w.DoOpen then w.DoOpen() end
            end)
            mq.cmd('/windowstate AAWindow open')
            mq.cmd('/nomodkey /keypress alt_advancement')
            task.nextStepAt = now + 0.35
            task.step = 'wait_open'
            return
        else
            task.step = 'prepare_tab'
            task.nextStepAt = now + 0.05
            return
        end

    elseif task.step == 'wait_open' then
        local isOpen = false
        pcall(function()
            local w = mq.TLO.Window('AAWindow')
            if w and w() and w.Open and w.Open() then isOpen = true end
        end)
        if isOpen or (task.retries and task.retries > 3) then
            task.step = 'prepare_tab'
            task.nextStepAt = now + 0.1
        else
            task.retries = (task.retries or 0) + 1
            pcall(function()
                local w = mq.TLO.Window('AAWindow')
                if w and w() and w.DoOpen then w.DoOpen() end
            end)
            mq.cmd('/windowstate AAWindow open')
            mq.cmd('/nomodkey /keypress alt_advancement')
            task.nextStepAt = now + 0.35
        end
        return

    elseif task.step == 'prepare_tab' then
        local win = nil
        pcall(function() win = mq.TLO.Window('AAWindow') end)
        local targetTab = task.targetTab or task.tab or 1

        -- Select the target tab page first so its listbox is active
        mq.cmdf('/nomodkey /notify AAWindow AAW_Subwindows tabselect %d', targetTab)
        pcall(function()
            if win and win() then
                local sub = runtime.findChildRecursive(win, 'AAW_Subwindows')
                if sub and sub() and sub.SetCurrentTab then sub.SetCurrentTab(targetTab) end
            end
        end)

        task.step = 'select_item'
        task.nextStepAt = now + 0.3
        return

    elseif task.step == 'select_item' then
        local listName, listIdx, _, listObj = runtime.findAAInWindowLists(task.name)

        if listName and listIdx and listIdx > 0 then
            -- Found the ability row! Select it
            pcall(function()
                if listObj and listObj() then
                    if listObj.Select then listObj.Select(listIdx) end
                    if listObj.LeftMouseUp then listObj.LeftMouseUp() end
                end
            end)
            mq.cmdf('/nomodkey /notify AAWindow %s listselect %d', listName, listIdx)
            mq.cmdf('/nomodkey /notify AAWindow %s leftmouseup', listName)
            task.step = 'click_train'
            task.nextStepAt = now + 0.25
            return
        else
            -- If not found on current tab, try next tab
            task.tab = (task.tab or 1) + 1
            if task.tab <= (task.maxTabs or 4) then
                task.targetTab = task.tab
                task.step = 'prepare_tab'
                task.nextStepAt = now + 0.1
                return
            else
                -- Fallback directly to /alt buy if ID is known
                if task.aaId and task.aaId > 0 then
                    mq.cmdf('/alt buy %d', task.aaId)
                    print(string.format('\ag[Triune]\ax Issued fallback /alt buy %d for "%s"...', task.aaId, task.name))
                end
                task.step = 'finish'
                task.nextStepAt = now + 0.4
                return
            end
        end

    elseif task.step == 'click_train' then
        local win = nil
        pcall(function() win = mq.TLO.Window('AAWindow') end)
        local trainButtons = { 'AAW_TrainButton', 'TrainButton', 'AA_TrainButton' }
        local clicked = false
        if win and win() then
            for _, btnName in ipairs(trainButtons) do
                local btn = runtime.findChildRecursive(win, btnName)
                if btn and btn() then
                    pcall(function() if btn.LeftMouseUp then btn.LeftMouseUp() end end)
                    mq.cmdf('/nomodkey /notify AAWindow %s leftmouseup', btnName)
                    clicked = true
                    break
                end
            end
        end
        if not clicked then
            mq.cmd('/nomodkey /notify AAWindow AAW_TrainButton leftmouseup')
            mq.cmd('/nomodkey /notify AAWindow TrainButton leftmouseup')
        end

        -- Also issue /alt buy <id> as a secondary fallback to guarantee purchase
        if task.aaId and task.aaId > 0 then
            mq.cmdf('/alt buy %d', task.aaId)
        end

        print(string.format('\ag[Triune]\ax Clicked Train Button in AA Window for "%s".', task.name))
        task.step = 'finish'
        task.nextStepAt = now + 0.4
        return

    elseif task.step == 'finish' then
        if task.openedByUs then
            pcall(function()
                local w = mq.TLO.Window('AAWindow')
                if w and w() and w.DoClose then w.DoClose() end
            end)
            mq.cmd('/windowstate AAWindow close')
        end
        runtime.pendingAATrain = nil
        runtime.lastAAScanAt = 0
        runtime.aaFilterDirty = true
        if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
        runtime.pendingPostTrainScanAt = now + 1.2
        runtime.saveLoadout(true)
        return
    end
end

function runtime.checkAutoSpendAA()
    if not ctrl.auto_spend_aa then return false end
    if runtime.pendingAATrain then return false end
    local now = os.clock()
    if (now - (runtime.lastAutoSpendAAAt or 0)) < 2.0 then return false end

    local unspent = 0
    pcall(function()
        local raw = mq.TLO.Me.AAPoints()
        unspent = tonumber(raw or 0) or 0
    end)
    if unspent <= 0 then return false end

    -- 1. Check prioritized AAs
    if ctrl.auto_aa_priorities and next(ctrl.auto_aa_priorities) then
        local candidates = {}
        for nm, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled then
                local rank, maxRank, cost = 0, 0, 0
                pcall(function()
                    local ma = mq.TLO.Me.AltAbility(nm)
                    if ma and ma() then
                        rank = tonumber(ma.Rank and ma.Rank() or 0) or 0
                        maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0
                        cost = tonumber(ma.Cost and ma.Cost() or 0) or 0
                    end
                end)
                local fullyTrained = (maxRank > 0 and rank >= maxRank)
                if not fullyTrained and cost > 0 and unspent >= cost then
                    candidates[#candidates + 1] = { name = nm, cost = cost, rank = rank, maxRank = maxRank }
                end
            end
        end

        if #candidates > 0 then
            if ctrl.auto_aa_buy_order == 'list' then
                table.sort(candidates, function(a, b) return a.name:lower() < b.name:lower() end)
            else
                table.sort(candidates, function(a, b)
                    if a.cost ~= b.cost then return a.cost < b.cost end
                    return a.name:lower() < b.name:lower()
                end)
            end
            local target = candidates[1]
            runtime.lastAutoSpendAAAt = now
            print(string.format('\ag[Triune]\ax Auto-spending AA on prioritized ability "%s" (Rank %d/%d, Cost: %d AA, Unspent: %d AA)...',
                target.name, target.rank, target.maxRank, target.cost, unspent))
            return runtime.startAATrainWorkflow(target.name)
        end
    end

    -- 2. Fallback: Cap threshold spender (Fireworks)
    local threshold = tonumber(ctrl.auto_spend_aa_threshold) or 100
    local cost = tonumber(ctrl.auto_spend_aa_cost) or 25
    local effectiveName = ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'

    if cost > 0 and unspent >= threshold and unspent >= cost then
        runtime.lastAutoSpendAAAt = now
        print(string.format('\ag[Triune]\ax Auto-spending AA cap protection on "%s" (Threshold: %d AA, Cost: %d AA, Unspent: %d AA)...',
            effectiveName, threshold, cost, unspent))
        return runtime.startAATrainWorkflow(effectiveName)
    end
    return false
end

function runtime.manualSpendAA(targetName)
    local effectiveName = targetName or ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
    local unspent = 0
    pcall(function()
        local raw = mq.TLO.Me.AAPoints()
        unspent = tonumber(raw or 0) or 0
    end)
    local cost = 0
    pcall(function()
        local ma = mq.TLO.Me.AltAbility(effectiveName)
        if ma and ma() and ma.Cost then
            cost = tonumber(ma.Cost() or 0) or 0
        end
    end)
    if cost == 0 then
        cost = tonumber(ctrl.auto_spend_aa_cost) or 25
    end

    if unspent < cost then
        print(string.format('\ay[Triune]\ax Cannot purchase %s: have %d unspent AA, need %d AA.', effectiveName, unspent, cost))
        return false
    end

    return runtime.startAATrainWorkflow(effectiveName)
end

function runtime.checkAutoSummonFireworks()
    if not ctrl.auto_summon_fireworks then return false end
    local now = os.clock()
    if (now - (runtime.lastAutoSummonAt or 0)) < 3.0 then return false end

    if isCasting() or isSitting() or isDucking() then return false end
    if mq.TLO.Me.Dead() or mq.TLO.Me.Moving() or mq.TLO.Me.Combat() then return false end
    if runtime.isMoveActive and runtime.isMoveActive() then return false end
    if runtime.anyXtarAlive and runtime.anyXtarAlive(true) then return false end

    local aaId = tonumber(ctrl.auto_spend_aa_id) or 17788
    if aaId <= 0 then return false end

    local ready = false
    pcall(function()
        local r = mq.TLO.Me.AltAbilityReady(aaId)
        if r and r() then ready = true end
    end)
    if not ready then return false end

    runtime.lastAutoSummonAt = now
    mq.cmdf('/alt activate %d', aaId)
    print(string.format('\ag[Triune]\ax Auto-summoning fireworks via /alt activate %d.', aaId))
    runtime.pendingCursorClearAt = os.clock() + 0.4
    return true
end

function runtime.manualSummonFireworks()
    local aaId = tonumber(ctrl.auto_spend_aa_id) or 17788
    mq.cmdf('/alt activate %d', aaId)
    print(string.format('\ag[Triune]\ax Summoning fireworks via /alt activate %d...', aaId))
    runtime.pendingCursorClearAt = os.clock() + 0.4
    return true
end

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
    local needsTarget = (not selfCast) or (not hostileTarget and orig > 0 and orig ~= id)
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
        castTracker.targetRequired = isDet or (isTargetRequiredSpell(effName) and (not selfCast or orig == id))
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
    if spawnReach > 0 then
        -- Allow reasonable reach bounded by user preference and true hitbox
        return math.max(userDist, math.min(spawnReach, userDist + 10))
    end
    return userDist
end
runtime.maxMeleeDistance = maxMeleeDistance

local function desiredRange(id)
    local NAV_CONST = pursuit.NAV_CONST
    if ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee' then
        return ctrl.pull_engage_dist or 100
    end
    local style = ctrl and ctrl.combat_style or 'Melee'
    if style ~= 'Melee' then
        return ctrl.ranged_dist or 40
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
    if spawnReach > 0 then
        local maxSafe = math.max(5, spawnReach - 2)
        return math.max(5, math.min(userDist, maxSafe))
    end
    return math.max(5, math.floor(userDist - 2))
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
        local newHits = (found.hits or 1) + 1
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
    local behindDist = dist or math.max(6, math.min(12, (ctrl and ctrl.melee_dist) or 12))
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
            if sActive and sTarget == targetId and sBehind then
                needStick = false
            end
        end)
        if needStick and not runtime.isCasting() then
            mq.cmdf('/stick id %d %d behind', targetId, stickDist)
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
            if now > (pursuit.detourExpiresAt or 0) or pursuit.detourTargetId ~= id then
                runtime.clearDetour()
            else
                local dDetour = math.sqrt((mx - pursuit.detourX) ^ 2 + (my - pursuit.detourY) ^ 2)
                if dDetour <= 8 then
                    runtime.clearDetour()
                else
                    runtime.moveTowardLoc(pursuit.detourX, pursuit.detourY, pursuit.detourZ, 6)
                    return false
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
                            pursuit.detourTargetKey = nil
                            pursuit.detourStartedAt = now
                            pursuit.detourExpiresAt = now + 6.0
                            runtime.moveTowardLoc(detour.x, detour.y, detour.z, 6)
                            return false
                        end
                    end
                end
            end
        end
    end

    local isMelee = (not followOnly and (ctrl and ctrl.combat_style or 'Melee') == 'Melee')
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
        if ctrl.mode == 'Puller' then
            print(string.format(
                '\ay[Triune]\ax giving up on target %d -- %s (likely elevated/blocked despite a ground path existing).',
                id,
                pursuit.navStalls >= 3 and 'nav keeps completing without ever reaching range' or
                ('no progress for ' .. NAV_CONST.PURSUIT_STALL_TIMEOUT .. 's')))
            runtime.markUnreachable(id)
            stopMoving()
            pursuit.id = 0
            return false
        end
    end

    -- Movement Stage 1: MQ2Nav
    if navLoaded() then
        local ok = false
        pcall(function() ok = mq.TLO.Navigation.PathExists('id ' .. id)() end)
        if ok then
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
    local tgt = mq.TLO.Target
    if not (tgt() and tgt.Type() == 'NPC' and not tgt.Dead()) then return end
    local tid = tgt.ID()
    if not ctrl.running then return end
    if isMoveActive() then return end
    if (os.clock() - pursuit.lastTooFarRepositionAt) < 1.0 then return end
    pursuit.lastTooFarRepositionAt = os.clock()

    local currentDist = distToId(tid)
    local targetDist = desiredRange(tid)
    if (ctrl and ctrl.combat_style) ~= 'Melee' then
        targetDist = math.max(5, math.min(targetDist, math.floor(currentDist - 15)))
    else
        -- When EQ reports "too far away", ensure we close in tighter than current distance
        targetDist = math.max(5, math.min(targetDist, math.floor(currentDist - 8)))
    end

    print(string.format(
        '\ay[Triune]\ax Target too far away (dist %.1f) -- repositioning closer (%d units) on target #%d.', currentDist,
        targetDist, tid))

    -- Reset pursuit tracking so moveToward doesn't short-circuit on stale arrival flags
    pursuit.id = 0
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

    local curDist = distToId(tid)
    print(string.format(
        '\ay[Triune]\ax "Cannot hit from here" (dist %.1f) on #%d (%s) -- opening doors and repositioning.',
        curDist, tid, tostring(tgt.CleanName())))

    -- Try opening any nearby door or switch first
    if runtime.tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax Clicked nearby door/switch to clear line of sight.')
    end

    -- Reset pursuit tracking so moveToward doesn't short-circuit on stale arrival flags
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.lastStickDist = 0
    if runtime.clearDetour then runtime.clearDetour() end

    mq.cmd('/face fast')

    -- If we have repeated failures in quick succession (e.g. wedged on doorway frame or wall corner),
    -- execute a brief backup + strafe jump to break geometric collision snags.
    if pursuit.cantHitCount >= 3 then
        pursuit.cantHitCount = 0
        mq.cmd('/keypress back hold')
        mq.delay(250)
        mq.cmd('/keypress back')
        mq.cmd('/keypress strafe_left hold')
        mq.delay(200)
        mq.cmd('/keypress strafe_left')
        mq.cmd('/keypress jump')
        mq.cmd('/face fast')
    end

    local targetDist = desiredRange(tid)
    if (ctrl and ctrl.combat_style) ~= 'Melee' then
        targetDist = math.max(12, math.min(targetDist, math.floor(curDist - 10)))
    else
        targetDist = math.max(5, math.min(targetDist, math.floor(curDist - 8)))
    end

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

-- Server-custom attack-mode toggle feedback ("#attackmode ranged"/"melee").
-- This is the only reliable signal we have for which mode we're actually in
-- -- Me.AutoFire never flips true under this scheme -- so keep our own
-- runtime.serverAttackMode in sync with it. #1# captures everything after
-- the colon; matched with find() rather than exact equality so it's not
-- thrown off by trailing punctuation/color codes/whitespace that may or may
-- not be present on the real server line.
mq.event('TriuneAttackModeChanged', 'Attack mode changed to: #1#', function(_, mode)
    if not mode then return end
    if mode:find('Ranged') then
        runtime.serverAttackMode = 'Ranged'
    elseif mode:find('Melee') then
        runtime.serverAttackMode = 'Melee'
    end
end)

-- Reverts the server's attack mode back to melee whenever we're leaving
-- Ranged combat style (switching combat style away from Ranged, or a full
-- stop) so a later /attack on doesn't keep firing a bow instead of swinging
-- a melee weapon. No-op if we're not confirmed in server Ranged mode, and
-- throttled the same as the Ranged-side switch so repeated calls can't spam
-- the chat line.
runtime.revertAttackModeToMelee = function()
    if runtime.serverAttackMode ~= 'Ranged' then return end
    if (os.clock() - (runtime.lastAttackModeCmdAt or 0)) < 1.0 then return end
    runtime.lastAttackModeCmdAt = os.clock()
    mq.cmd('/say #attackmode melee')
end

-- Call only once runtime.serverAttackMode == 'Ranged' is already confirmed
-- and tid is a valid, in-range target we want to be firing at. Handles the
-- toggle-vs-target-change quirk described above: on a genuine target
-- change, forces /attack off then a short beat later /attack on (so the two
-- commands don't collapse into a same-tick no-op), rather than only
-- checking whether the toggle currently reads off. For the common case
-- (same target as last tick, already firing) this is just the original
-- "turn it on if it's off" check.
--
-- This is synchronous (uses mq.delay) rather than spreading the retoggle
-- across two separate ticks via a pending flag. The earlier async version
-- required a follow-up call after the delay window to send the completing
-- /attack on, but this function is only invoked from inside conditionally
-- gated combat-tick code (distance/casting/haveNPC checks) -- those gates
-- can flip false on the very next tick and never call back in, permanently
-- stranding the character with attack off. Blocking here for one short
-- delay (this always runs on the main-loop coroutine, never an ImGui
-- render callback, so mq.delay is safe) guarantees /attack off is always
-- immediately followed by /attack on within the same call.
function runtime.ensureRangedAutoAttack(tid)
    if tid ~= runtime.lastRangedAttackTargetId then
        runtime.lastRangedAttackTargetId = tid
        if mq.TLO.Me.Combat() then
            mq.cmd('/attack off')
            mq.delay(300)
            mq.cmd('/attack on')
        else
            mq.cmd('/attack on')
        end
        return
    end

    if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
end

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
    -- Do not trigger a new detour if we are currently moving toward a detour waypoint itself!
    local me = mq.TLO.Me
    if me() and ctrl.nav_hazard_avoidance and not string.find(tostring(pursuit.lastNavLoc or ''), '^detour_') then
        local mx, my, mz = me.X() or 0, me.Y() or 0, me.Z() or 0
        local now = os.clock()

        -- 1. Check in-flight active detour for this loc target
        if pursuit.detourActive then
            if now > (pursuit.detourExpiresAt or 0) or pursuit.detourTargetKey ~= locKey then
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
                        if pursuit.lastNavLoc ~= detourKey or not navActive then
                            local locyxStr = string.format('locyx %.2f %.2f', pursuit.detourY, pursuit.detourX)
                            local ok = false
                            pcall(function() ok = mq.TLO.Navigation.PathExists(locyxStr)() end)
                            if ok then
                                mq.cmdf('/nav %s', locyxStr)
                                pursuit.lastNavLoc = detourKey
                                return false
                            end
                        else
                            return false
                        end
                    end
                end
            end
        end

        -- 2. If no active detour, check if straight path to destination intersects a known hazard
        if not pursuit.detourActive then
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
                        pursuit.detourExpiresAt = now + 6.0

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
        stuckState.combatStallSince = nil
        return
    end

    -- Must be actively in combat, or have hostile enemies on XTarget, or already attacking
    local inCombat = mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT') or runtime.anyXtarAlive(true)
    if not inCombat then
        stuckState.combatStallSince = nil
        return
    end

    local t = mq.TLO.Target
    local haveLiveNPC = t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse'
    if not haveLiveNPC or not isHostileTarget(t.ID()) then
        stuckState.combatStallSince = nil
        return
    end

    -- In Manual mode, only watchdog auto-attack if the target is an active hostile XTarget or actively fighting us
    if ctrl.mode == 'Manual' and not (isXTargetId(t.ID()) or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT')) then
        stuckState.combatStallSince = nil
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
            stuckState.combatStallSince = nil
            return
        end
    end

    local d = distToId(t.ID())
    local isPullStandBack = (ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee')
    if ctrl.combat_style == 'Melee' and not isPullStandBack then
        if d <= maxMeleeDistance(t.ID()) and not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
    elseif ctrl.combat_style == 'Ranged' then
        if d <= (ctrl.ranged_dist or 40) and not isCasting() then
            if runtime.serverAttackMode ~= 'Ranged' and (os.clock() - (runtime.lastAttackModeCmdAt or 0)) > 1.0 then
                runtime.lastAttackModeCmdAt = os.clock()
                mq.cmd('/say #attackmode ranged')
            elseif runtime.serverAttackMode == 'Ranged' then
                runtime.ensureRangedAutoAttack(t.ID())
            end
        end
    end
    stuckState.combatStallSince = nil
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

    -- User override (Settings tab): skip the step-back maneuver entirely,
    -- for any combat style. Off by default -- see below for why melee still
    -- needs the real maneuver in most cases.
    if ctrl.los_face_only then
        mq.cmd('/face fast')
        return
    end

    local d = distToId(tid)
    local maxReach = maxMeleeDistance(tid)
    -- Me.Combat() is no longer melee-exclusive: under this server's
    -- attackmode scheme, Ranged style also drives its bow through plain
    -- /attack on, so Combat() reads true while ranged-attacking too. Only
    -- let it count toward "melee" when we're not confirmed in server Ranged
    -- attack mode.
    local isConfirmedRanged = ctrl and ctrl.combat_style == 'Ranged' and runtime.serverAttackMode == 'Ranged'
    -- combat_style == 'Ranged' always re-faces instead of stepping back: the
    -- distance fallback below (d <= maxReach+10) used to catch Ranged too
    -- once low ranged_dist values (down to 5) put bow users inside that
    -- radius, causing a back-away/re-approach loop as the normal Ranged
    -- engage logic immediately closed the gap back to ranged_dist.
    local isMelee = (ctrl and ctrl.combat_style ~= 'Ranged') and
        ((ctrl and ctrl.combat_style == 'Melee') or (mq.TLO.Me.Combat() and not isConfirmedRanged) or
            (d <= (maxReach + 10)))

    if not isMelee then
        -- In Ranged / caster mode or far away, re-align view vector
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

    local function scanSpawns(maxZ)
        local radius = searchRadius or 100
        local p = string.format('npc radius %d zradius %d targetable', radius, maxZ)
        for i = 1, 100 do
            local s = mq.TLO.NearestSpawn(i, p)
            if not s() then break end

            local sid = s.ID() or 0
            if sid > 0 then
                local sname = s.CleanName()
                if runtime.isPullAllowed(sname) and runtime.isConAllowed(s) and not isSpawnPetOrPlayer(sid) and not isUnreachable(sid) then
                    local sy = s.Y() or 0
                    local sx = s.X() or 0
                    if not outsideAnchor(sy, sx) then
                        local slvl = s.Level() or 0
                        if slvl >= minLv and slvl <= maxLv then
                            if isHostileTarget(sid) then
                                if runtime.verifyTargetCon(sid) then
                                    local sz = s.Z() or 0
                                    local inHaz = runtime.isCoordInActiveHazard(sx, sy, sz)
                                    if not inHaz or (ctrl and ctrl.combat_style ~= 'Melee') then
                                        local pathOk = true
                                        if inHaz then
                                            local isMelee = (ctrl and (ctrl.combat_style or 'Melee') == 'Melee')
                                            if isMelee then
                                                pathOk = false
                                            end
                                        end
                                        if pathOk and navLoaded() then
                                            local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
                                            if meshOk and meshLoaded then
                                                local dist = s.Distance3D() or 999
                                                if dist > 25 then
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
            and not isSpawnPetOrPlayer(pt.ID()) and isHostileTarget(pt.ID()) and distToId(pt.ID()) <= 25 then
            runtime.pullTargetId = pt.ID()
            runtime.pullState = 'FIGHTING'
            return
        end

        if runtime.checkPullHpRest() then return end

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
        else
            local pullStyle = ctrl.pull_style or 'Melee'
            local reqRange
            if pullStyle == 'Melee' then
                reqRange = desiredRange(runtime.pullTargetId)
            elseif pullStyle == 'Ranged' then
                -- Close all the way to the real ranged engagement distance
                -- (or the Stand Back distance, if that's enabled) instead of
                -- parking at the looser pull_engage_dist -- this uses
                -- ctrl.ranged_dist directly rather than desiredRange() so it
                -- still closes to bow range even if overall combat_style is
                -- Melee/Spell (bow-tag-then-melee/spell pulling).
                reqRange = ctrl.pull_stand_back and (ctrl.pull_engage_dist or 100) or (ctrl.ranged_dist or 40)
            else
                reqRange = ctrl.pull_engage_dist or 100
            end

            local tid = runtime.pullTargetId
            runtime.recordBreadcrumb()
            local arrived = runtime.moveToward(tid, reqRange)
            -- Ranged: start firing as soon as we're within the outer
            -- pull-engage window and have LoS -- same threshold as before --
            -- rather than waiting for full arrival at the tighter reqRange
            -- above. Lets the character keep closing toward true engagement
            -- range while already shooting, instead of stopping short and
            -- standing still waiting for the mob to close the gap itself.
            local inRange = arrived or
                (pullStyle == 'Ranged' and distToId(tid) <= (ctrl.pull_engage_dist or 100) and hasLoS(tid))

            if inRange then
                local tagged = false

                if pullStyle == 'Melee' then
                    if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                    tagged = true
                elseif pullStyle == 'Ranged' then
                    mq.cmd('/face fast')
                    if ctrl.combat_style == 'Ranged' then
                        -- AutoCombat is set to Ranged: /autofire leaves the
                        -- character not attacking at all on this server.
                        -- Use the server's own #attackmode ranged toggle
                        -- (tracked in runtime.serverAttackMode) plus plain
                        -- /attack on instead -- same approach as general
                        -- Ranged-style combat engagement.
                        if runtime.serverAttackMode ~= 'Ranged' and (os.clock() - (runtime.lastAttackModeCmdAt or 0)) > 1.0 then
                            runtime.lastAttackModeCmdAt = os.clock()
                            mq.cmd('/say #attackmode ranged')
                        elseif runtime.serverAttackMode == 'Ranged' then
                            runtime.ensureRangedAutoAttack(tid)
                        end
                    else
                        -- combat_style is Melee/Spell but pull_style is
                        -- Ranged (bow-tag then melee/spell) -- unaffected,
                        -- still uses /autofire as before.
                        if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
                    end
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
        if ctrl.mode == 'Puller' and ctrl.combat_style == 'Melee' and not mq.TLO.Me.Combat() then
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
--   Ranged -> /attack is on with server attack mode == Ranged (bow firing
--             via this server's #attackmode toggle; caught by the first
--             check below same as melee -- Me.AutoFire never flips true
--             under this scheme, so it's kept only as a legacy fallback for
--             any lingering bow-pull-while-melee-style case)
--   Spell  -> mob HP has dropped below 100% AND player holds aggro
--             (at least one spell has connected)
-- Works for all three combat styles; safe to call with no pets present.
function runtime.playerIsEngagingTarget(tid)
    if mq.TLO.Me.Combat() then return true end   -- melee /attack on, or ranged /attack on in server Ranged attack mode
    if mq.TLO.Me.AutoFire() then return true end -- legacy: autofire on (e.g. bow pull while combat_style == Melee)
    -- Spell style: confirm a hit has landed via HP drop + aggro ownership
    local tpct = pctHP(tid) or 100
    if tpct < 100 and runtime.playerHasAggro(tid) then return true end
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
    -- Deliberately NOT reverting server attackmode to melee here: pausing
    -- or stopping the script should preserve whatever attack mode
    -- (melee/ranged) was active, not force it back. revertAttackModeToMelee()
    -- is still called on an explicit combat_style change to Melee/Spell
    -- (radio button, /ac style command) -- that's a real user choice, unlike
    -- a pause/stop.
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
runtime.isCasting = isCasting
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
runtime.desiredRange = desiredRange
runtime.maxMeleeDistance = maxMeleeDistance
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

local function combatTick()
    local fullStop = runtime.fullStop
    local pctHP = runtime.pctHP
    local isCombat = runtime.isCombat
    local anyXtarAlive = runtime.anyXtarAlive
    local countNPCXtarget = runtime.countNPCXtarget
    local isXTargetId = runtime.isXTargetId
    local isSpawnPetOrPlayer = runtime.isSpawnPetOrPlayer
    local isHostileTarget = runtime.isHostileTarget
    local firstNPCXtarget = runtime.firstNPCXtarget
    local stopMoving = runtime.stopMoving
    local distToId = runtime.distToId
    local hasLoS = runtime.hasLoS
    local isMoveActive = runtime.isMoveActive
    local isCasting = runtime.isCasting
    local isCastingOrStarting = runtime.isCastingOrStarting
    local getActiveTargetRequiredCastingId = runtime.getActiveTargetRequiredCastingId
    local clearTarget = runtime.clearTarget
    local navLoaded = runtime.navLoaded
    local stickLoaded = runtime.stickLoaded
    local hasActivePet = runtime.hasActivePet
    local setManualHunterPetHold = runtime.setManualHunterPetHold
    local playerHasAggro = runtime.playerHasAggro
    local playerIsEngagingTarget = runtime.playerIsEngagingTarget
    local checkStuck = runtime.checkStuck
    local checkCombatStall = runtime.checkCombatStall
    local checkGemMemSync = runtime.checkGemMemSync
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
    local baseTok = runtime.baseTok
    local sungKey = runtime.sungKey
    local clearCursor = runtime.clearCursor
    local markUnreachable = runtime.markUnreachable
    local moveToward = runtime.moveToward
    local moveTowardLoc = runtime.moveTowardLoc
    local setTarget = runtime.setTarget
    local desiredRange = runtime.desiredRange
    local maxMeleeDistance = runtime.maxMeleeDistance
    local isIgnored = runtime.isIgnored
    local isUnreachable = runtime.isUnreachable
    local checkPullHpRest = runtime.checkPullHpRest
    local targetIsEngaged = runtime.targetIsEngaged
    local ensureRangedAutoAttack = runtime.ensureRangedAutoAttack

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
            petState.myPets = {}; petState.lastObservedId = 0; petState.lastCastCls = nil
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
    if ctrl.auto_spend_aa and runtime.checkAutoSpendAA then
        runtime.checkAutoSpendAA()
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

    local curPetId = mq.TLO.Me.Pet.ID() or 0
    if curPetId ~= 0 and curPetId ~= petState.lastObservedId then
        if petState.lastCastCls then
            petState.myPets[petState.lastCastCls] = curPetId
            petState.lastCastCls = nil
        else
            for _, c in ipairs(myClasses) do
                if petState.PET_CLASSES[c] and (not petState.myPets[c] or not isSpawnAlive(petState.myPets[c])) then
                    petState.myPets[c] = curPetId
                    break
                end
            end
        end
        petState.lastObservedId = curPetId
    elseif curPetId == 0 then
        petState.lastObservedId = 0
    end

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
    checkGemMemSync()
    if (ctrl.mode == 'Manual' and ctrl.manual_auto_xtarget ~= false) or ctrl.mode == 'Puller' then
        checkAggroSwitch()
    end

    local numXtar = countNPCXtarget()
    local t = mq.TLO.Target
    local haveNPC = t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse'
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

    if ctrl.mode == 'Manual' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then
            haveNPC = false
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
                if isXtar or inCombatState then
                    if moveToward(id, desiredRange(id)) then
                        engage = true
                    end
                end
            end
        elseif ctrl.camp_loc then
            moveTowardLoc(ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, 15)
        end
    elseif ctrl.mode == 'Puller' then
        if ctrl.submode == 'Camp' then
            pullerTick()
            local pt = mq.TLO.Target
            haveNPC = pt() and pt.Type() == 'NPC' and not pt.Dead() and pt.Type() ~= 'Corpse'
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
                if not tspawn() or tspawn.Dead() or tspawn.Type() == 'Corpse' or isUnreachable(tid) or isIgnored(tspawn.CleanName()) then
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
                if checkPullHpRest() then return end
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
                    -- Close all the way to the real ranged engagement
                    -- distance (or Stand Back distance) instead of parking
                    -- at the looser pull_engage_dist -- uses ctrl.ranged_dist
                    -- directly so it still closes to bow range even if
                    -- overall combat_style is Melee/Spell (bow-tag-then-
                    -- melee/spell pulling).
                    reqRange = ctrl.pull_stand_back and (ctrl.pull_engage_dist or 100) or (ctrl.ranged_dist or 40)
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
                            -- Already "tagged"/Me.Combat()==true doesn't mean we're
                            -- actually firing at THIS id -- e.g. a fresh, already-
                            -- adjacent mob picked up the instant the previous one
                            -- died, while Me.Combat() is still reading true from
                            -- that kill. This shortcut used to return here without
                            -- ever calling ensureRangedAutoAttack, so the new
                            -- target's off/on retoggle never happened and the
                            -- character silently never fired on it. Route through
                            -- it here too so a genuine target change is still
                            -- caught even when we think we're already engaged.
                            if ctrl.combat_style == 'Ranged' and runtime.serverAttackMode == 'Ranged' then
                                ensureRangedAutoAttack(id)
                            end
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
                                    if ctrl.combat_style == 'Ranged' then
                                        -- AutoCombat is set to Ranged: /autofire leaves
                                        -- the character not attacking at all on this
                                        -- server. Use the server's #attackmode ranged
                                        -- toggle plus plain /attack on instead.
                                        if runtime.serverAttackMode ~= 'Ranged' and (os.clock() - (runtime.lastAttackModeCmdAt or 0)) > 1.0 then
                                            runtime.lastAttackModeCmdAt = os.clock()
                                            mq.cmd('/say #attackmode ranged')
                                        elseif runtime.serverAttackMode == 'Ranged' then
                                            ensureRangedAutoAttack(id)
                                        end
                                    else
                                        -- combat_style is Melee/Spell but pull_style is
                                        -- Ranged (bow-tag then melee/spell) -- unaffected,
                                        -- still uses /autofire as before.
                                        if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
                                    end
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
                if ctrl.submode == 'Camp' then idleReturn() else chaseMA() end
            end
        end
    end

    -- Non-XTarget engagement timeout check (only when far away and unable to reach target in Puller mode):
    if haveNPC and ctrl.mode == 'Puller' then
        local tid = mq.TLO.Target.ID() or 0
        if tid > 0 and not isXTargetId(tid) and distToId(tid) > 30 then
            if pursuit.nonXtarTargetId ~= tid then
                pursuit.nonXtarTargetId = tid
                pursuit.nonXtarEngageAt = 0
            end
            if engage or mq.TLO.Me.Combat() or mq.TLO.Me.AutoFire() then
                if pursuit.nonXtarEngageAt == 0 then
                    pursuit.nonXtarEngageAt = os.clock()
                elseif (os.clock() - pursuit.nonXtarEngageAt) > 15.0 then
                    print(string.format(
                        '\ay[Triune]\ax Target #%d (%s) unreachable after 15s -- marking unreachable & moving to next NPC.',
                        tid, tostring(mq.TLO.Target.CleanName())))
                    markUnreachable(tid)
                    stopMoving()
                    clearTarget()
                    haveNPC = false
                    engage = false
                    pursuit.id = 0
                    pursuit.nonXtarTargetId = 0
                    pursuit.nonXtarEngageAt = 0
                end
            else
                pursuit.nonXtarEngageAt = 0
            end
        else
            pursuit.nonXtarTargetId = 0
            pursuit.nonXtarEngageAt = 0
        end
    else
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
            '\ao[DEBUG]\ax Mode:%s Style:%s AtkMode:%s | Tgt:%s(#%d HP:%d%% Hostile:%s) | Dist:%.1f Reach:%.1f LoS:%s | Nav:%s Stick:%s Mov:%s | Eng:%s Combat:%s Cast:%s | XTar:%d',
            tostring(ctrl.mode), tostring(ctrl.combat_style or 'Melee'), tostring(runtime.serverAttackMode or 'Melee'), tostring(tname), tonumber(tid) or 0, tonumber(thp) or 0, tostring(isHostile), tonumber(dist) or 0, tonumber(reach) or 18, tostring(los),
            tostring(navActive), tostring(stickActive), tostring(moving), tostring(engage), tostring(combat), tostring(casting), tonumber(numXtar) or 0))
    end

    -- Auto-attack / Auto-fire handling:
    -- Engage autoattack/autofire only when target exists, target is within striking distance,
    -- or target is confirmed engaged on XTarget.
    -- Turn off autoattack/autofire whenever out of range or when no NPCs remain on XTarget list.
    -- For player-directed modes (Manual, Assist), also require the NPC to be confirmed hostile before
    -- initiating auto-attack — prevents hitting friendly NPCs (merchants, etc.).
    local xtarActive = anyXtarAlive()
    local style = ctrl and ctrl.combat_style or 'Melee'
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
    if style == 'Melee' then
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
                                    if (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') and mq.TLO.Stick.MoveBehind() then
                                        mq.cmdf('/stick id %d %d', tid, math.floor(desiredRange(tid)))
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
                if stickLoaded() then
                    pcall(function()
                        if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                            mq.cmd('/stick off')
                        end
                    end)
                end
            end
        end
    elseif style == 'Ranged' then
        local isDraggingToCamp = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState == 'TO_CAMP')
        if haveNPC and not isDraggingToCamp and autoAttackOk then
            local curDist = (tid > 0) and distToId(tid) or 999
            local maxReach = (ctrl and ctrl.ranged_dist) or 40
            if curDist <= maxReach then
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then
                    print('\ag[Triune]\ax Standing up to attack.')
                    mq.cmd('/stand')
                end
                if not isCasting() then
                    if runtime.serverAttackMode ~= 'Ranged' and (os.clock() - (runtime.lastAttackModeCmdAt or 0)) > 1.0 then
                        runtime.lastAttackModeCmdAt = os.clock()
                        print(string.format('\ag[Triune]\ax Switching server attack mode -> Ranged -> %s (#%d)',
                            tostring(mq.TLO.Target.CleanName()), tid))
                        mq.cmd('/say #attackmode ranged')
                    elseif runtime.serverAttackMode == 'Ranged' then
                        if tid ~= runtime.lastRangedAttackTargetId or not mq.TLO.Me.Combat() then
                            print(string.format('\ag[Triune]\ax Engaging /attack on (ranged) -> %s (#%d) [dist=%.1f <= reach=%.1f, engage=%s]',
                                tostring(mq.TLO.Target.CleanName()), tid, curDist, maxReach, tostring(engage)))
                        end
                        ensureRangedAutoAttack(tid)
                    end
                end
                if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                    pursuit.lastCombatFaceAt = os.clock()
                    mq.cmd('/face fast')
                end
            elseif not isMoveActive() and curDist > maxReach and tid > 0 then
                -- Mob moved, was pushed, or is out of ranged reach: re-close distance
                if ctrl.mode ~= 'Manual' then
                    moveToward(tid, desiredRange(tid))
                end
            end
        else
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
        for name, a in pairs(loadout.aas) do
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
                        local targetValid = not isDet or (isHostileTarget(id) and isTargetInRange(effName, id))
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
            for i = 1, #loadout.gems do
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
                                        local targetValid = not isDet or (isHostileTarget(id) and isTargetInRange(g.spell, id))
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
        print('  \ag/ac compact | mini | hud\ax - Toggle compact HUD mode')
        print('  \ag/ac help | h | ?\ax - Print slash command summary')
        print('  \ag/ac spellbook | book\ax - Toggle spellbook browser')
        print('  \ag/ac cursorui | cursormgr\ax - Toggle cursor item manager')
        print('  \ag/ac clearcursor | autoinv\ax - Clear items from cursor')
        print('  \ag/ac style [melee|ranged|spell]\ax - Configure combat style')
        print('  \ag/ac range [dist]\ax - Configure melee or ranged distance')
        print('  \ag/ac buffbot | buff\ax - Toggle interactive buffbot window')
        print('  \ag/ac track | zone\ax - Toggle zone NPC tracker window')
        print('  \ag/ac update | updater\ax - Toggle release updater window')
        print('  \ag/ac cd | cooldowns\ax - Toggle popout Cooldown & Ability Monitor window')
        print('  \ag/ac dps | /dps\ax - Toggle DPS parser window')
        print('  \ag/ac zplane [5-100]\ax - Configure Hunter Tier 1 same-floor / Z plane height threshold')
        print('  \ag/ac huntz [10-300]\ax - Configure Hunter Tier 2 max vertical height difference')
        print('  \ag/ac pullcon [con]\ax - Configure faction consideration filter')
        print('  \ag/ac wp [add|clear|del|on|off|list]\ax - Configure & toggle Puller Waypoint Patrol')
        print('  \ag/ac pullhp [0-95]\ax - Set minimum HP % threshold before pausing pulling to rest')
        print('  \ag/ac clear lockouts\ax - Clear all active spell lockouts & mob immunities')
        print('  \ag/ac autoaa | autospendaa [on|off]\ax - Toggle automatic AA point spending')
        print('  \ag/ac autofw | summonfw [on|off]\ax - Toggle automatic fireworks summoning')
        print('  \ag/ac spendnow | spendaa\ax - Instantly purchase 1 rank of fireworks AA')
        print('  \ag/ac summonnow\ax - Instantly activate fireworks summon AA')
        print('  \ag/ac aathreshold [25-100]\ax - Set AA auto-spend trigger threshold')
        print('  \ag/ac aacost [1-50]\ax - Set AA point cost per rank')
        print('  \ag/ac aaid [id]\ax - Set AA ability ID to purchase/activate (default 17788)')
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
        print('  \ag/ac pausezone [on|off]\ax - Toggle automatic script pause when zoning (default: on)')
        print('  \ag/ac fov [50-150|on|off]\ax - Set camera FOV and toggle maintain on zone')
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
    elseif cmd == 'spellbook' or cmd == 'book' then
        if UI.toggleTool('triune_spellbook') == 'started' then
            print('\ag[Triune]\ax launching spellbook engine...')
        else
            print('\ag[Triune]\ax stopping spellbook engine...')
        end
    elseif cmd == 'cursorui' or cmd == 'cursorwin' or cmd == 'cursormgr' then
        if UI.toggleTool('triune_cursor') == 'started' then
            print('\ag[Triune]\ax launching cursor manager...')
        else
            print('\ag[Triune]\ax stopping cursor manager...')
        end
    elseif cmd == 'buff' or cmd == 'buffbot' or cmd == 'buffui' then
        if UI.toggleTool('triune_buffbot') == 'started' then
            print('\ag[Triune]\ax launching buffbot engine...')
        else
            print('\ag[Triune]\ax stopping buffbot engine...')
        end
    elseif cmd == 'dps' or cmd == 'dpsui' or cmd == 'dpsparser' then
        if UI.toggleTool('triune_dps', '/dps toggle') == 'started' then
            print('\ag[Triune]\ax launching DPS parser window...')
        else
            print('\ag[Triune]\ax toggling DPS parser window...')
        end
    elseif cmd == 'clearlockouts' or cmd == 'unlock' or (cmd == 'clear' and (args[2] and (string.lower(args[2]) == 'lockouts' or string.lower(args[2]) == 'locks' or string.lower(args[2]) == 'all'))) then
        if castTracker and castTracker.clear then
            castTracker.clear()
            print('\ag[Triune]\ax Cleared all active spell lockouts, target backoffs, and mob immunities.')
        end
    elseif cmd == 'autoaa' or cmd == 'autospendaa' or cmd == 'autospend' or cmd == 'fireworks' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.auto_spend_aa = true
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.auto_spend_aa = false
        else
            ctrl.auto_spend_aa = not ctrl.auto_spend_aa
        end
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Auto-Spend AA Points %s (Threshold: %d AA, Cost: %d AA, ID: %d).',
            ctrl.auto_spend_aa and '\agENABLED\ax' or '\arDISABLED\ax',
            ctrl.auto_spend_aa_threshold or 100, ctrl.auto_spend_aa_cost or 25, ctrl.auto_spend_aa_id or 17788))
    elseif cmd == 'autofw' or cmd == 'summonfw' or cmd == 'auto_summon_fireworks' or cmd == 'autofireworks' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.auto_summon_fireworks = true
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.auto_summon_fireworks = false
        else
            ctrl.auto_summon_fireworks = not ctrl.auto_summon_fireworks
        end
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Auto-Summon Fireworks %s (/alt activate %d).',
            ctrl.auto_summon_fireworks and '\agENABLED\ax' or '\arDISABLED\ax', ctrl.auto_spend_aa_id or 17788))
    elseif cmd == 'aatrain' or cmd == 'trainwindow' or cmd == 'trainaa' or cmd == 'spendnow' or cmd == 'spendaa' or cmd == 'spendpoints' then
        if runtime.manualSpendAA then runtime.manualSpendAA() end
    elseif cmd == 'summonnow' or cmd == 'summonfireworks' then
        if runtime.manualSummonFireworks then runtime.manualSummonFireworks() end
    elseif cmd == 'aathreshold' or cmd == 'spendthreshold' or cmd == 'aathresh' then
        local val = tonumber(args[2])
        if val then
            ctrl.auto_spend_aa_threshold = math.max(1, math.min(500, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Trigger Threshold set to %d AA.', ctrl.auto_spend_aa_threshold))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Threshold: %d AA. (usage: /ac aathreshold [25-100])', ctrl.auto_spend_aa_threshold or 100))
        end
    elseif cmd == 'aacost' or cmd == 'spendcost' then
        local val = tonumber(args[2])
        if val then
            ctrl.auto_spend_aa_cost = math.max(1, math.min(500, math.floor(val)))
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Cost Per Rank set to %d AA.', ctrl.auto_spend_aa_cost))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Cost: %d AA. (usage: /ac aacost [1-50])', ctrl.auto_spend_aa_cost or 25))
        end
    elseif cmd == 'aaid' or cmd == 'spendaaid' then
        local val = tonumber(args[2])
        if val and val > 0 then
            ctrl.auto_spend_aa_id = math.floor(val)
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend Activation Spell ID set to %d.', ctrl.auto_spend_aa_id))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend Activation ID: %d. (usage: /ac aaid [id])', ctrl.auto_spend_aa_id or 17788))
        end
    elseif cmd == 'aaname' or cmd == 'setaaname' then
        local newName = table.concat(args, ' ', 2)
        if newName and newName ~= '' then
            ctrl.auto_spend_aa_name = newName
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Ability Name set to "%s".', ctrl.auto_spend_aa_name))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Ability Name: "%s". (usage: /ac aaname [name])', ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'))
        end
    elseif cmd == 'aascan' or cmd == 'scanaa' or cmd == 'aarefresh' then
        runtime.specialTabReadDone = false
        runtime.pendingReadSpecialTab = true
        if runtime.scanPlayerAAs then
            runtime.scanPlayerAAs(true)
            local count = runtime.scannedAAs and #runtime.scannedAAs or 0
            print(string.format('\ag[Triune]\ax Scanned character Alternate Advancements: %d abilities found.', count))
        end
    elseif cmd == 'aaprio' or cmd == 'prioritizeaa' then
        local aaName = table.concat(args, ' ', 2)
        if aaName and aaName ~= '' then
            if not ctrl.auto_aa_priorities then ctrl.auto_aa_priorities = {} end
            ctrl.auto_aa_priorities[aaName] = not ctrl.auto_aa_priorities[aaName]
            runtime.aaFilterDirty = true
            runtime.saveLoadout(true)
            print(string.format('\ag[Triune]\ax AA priority for "%s" set to %s.',
                aaName, ctrl.auto_aa_priorities[aaName] and '\agENABLED\ax' or '\arDISABLED\ax'))
        else
            print('\ag[Triune]\ax usage: /ac aaprio <Ability Name>')
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
    elseif cmd == 'update' or cmd == 'updater' or cmd == 'checkupdate' then
        mq.cmd('/lua run triune_updater')
    elseif cmd == 'map' or cmd == 'mapui' or cmd == 'triunemap' or cmd == 'track' or cmd == 'tracker' or cmd == 'trackui' or cmd == 'zone' then
        if UI.toggleTool('triune_map') == 'started' then
            print('\ag[Triune]\ax launching map & tracker window...')
        else
            print('\ag[Triune]\ax stopping map & tracker window...')
        end
    elseif cmd == 'compact' or cmd == 'mini' or cmd == 'hud' then
        ctrl.compact = not ctrl.compact
        runtime.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Compact HUD mode %s.', ctrl.compact and 'ENABLED' or 'DISABLED'))
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
        local st = args[2] and string.lower(args[2]) or ''
        if st == 'melee' then
            ctrl.combat_style = 'Melee'
            if runtime.revertAttackModeToMelee then runtime.revertAttackModeToMelee() end
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agMelee\ax (range ' .. tostring(ctrl.melee_dist or 14) .. ')')
        elseif st == 'ranged' or st == 'bow' then
            ctrl.combat_style = 'Ranged'
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agRanged (bow)\ax (range ' .. tostring(ctrl.ranged_dist or 40) .. ')')
        elseif st == 'spell' or st == 'cast' or st == 'caster' then
            ctrl.combat_style = 'Spell'
            if runtime.revertAttackModeToMelee then runtime.revertAttackModeToMelee() end
            runtime.saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agSpell\ax (range ' .. tostring(ctrl.ranged_dist or 40) .. ')')
        else
            print('\ay[Triune]\ax usage: /ac style [melee|ranged|spell]')
        end
    elseif cmd == 'range' or cmd == 'meleerange' or cmd == 'dist' then
        local val = tonumber(args[2])
        if val then
            if ctrl.combat_style == 'Melee' or cmd == 'meleerange' then
                ctrl.melee_dist = math.max(5, math.min(50, math.floor(val)))
                runtime.saveLoadout(true)
                print(string.format('\ag[Triune]\ax Max Melee Distance set to %d units.', ctrl.melee_dist))
            else
                ctrl.ranged_dist = math.max(5, math.min(200, math.floor(val)))
                runtime.saveLoadout(true)
                print(string.format('\ag[Triune]\ax Ranged Engagement Distance set to %d units.', ctrl.ranged_dist))
            end
        else
            if ctrl.combat_style == 'Melee' then
                print(string.format('\ag[Triune]\ax Current Max Melee Distance: %d units. (usage: /ac range [5-50])', ctrl.melee_dist or 14))
            else
                print(string.format('\ag[Triune]\ax Current Ranged Distance: %d units. (usage: /ac range [5-200])', ctrl.ranged_dist or 40))
            end
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
    elseif setTriuneMode(args[1], args[2]) then
        return
    else
        print(
            '\ay[Triune]\ax usage: /ac [run|pause|burn|memall|importbar|compact|status|spellbook|cursorui|dps|track|buffbot|update|clearcursor|style|range|zplane|huntz|pullhp|preset|help|pullcon|wp|manual|puller [hunt|camp]|assist [chase|camp|backline]]')
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
        mq.delay(250, function() return navLoaded() and stickLoaded() end)
    end
end
runtime.autoloadRequiredPlugins()

-- ============================================================================
-- Critical Hit Floating Text Overlay
-- ============================================================================
-- Renders flashy floating damage numbers above the player character when a
-- critical hit / crippling blow / deadly strike / spell crit lands. Drawn as
-- a separate, transparent, click-through ImGui overlay window registered via
-- its own mq.imgui.init (never nested inside the main Triune window).
--
-- Each floater entry: { text, type, dmg, spawnedAt, x, y, seed }
-- "type" drives the visual theme: 'crit', 'crip', 'deadly', 'spellcrit',
--                                   'holy', 'flurry', 'finish', 'assassin',
--                                   'headshot', 'slay'.
-- ============================================================================

runtime.CRIT = {
    LIFETIME   = 2.0,    -- seconds a floater lives
    RISE_SPEED = 80,     -- pixels per second upward drift
    SPREAD     = 120,    -- horizontal jitter range (pixels)
    BASE_SIZE  = 22,     -- base font scale for normal crits
    BIG_SIZE   = 32,     -- font scale for massive hits
    COLORS     = {
        crit      = { 1.0, 0.85, 0.20 },   -- golden yellow
        crip      = { 1.0, 0.30, 0.15 },   -- fiery red-orange
        deadly    = { 0.85, 0.10, 1.0  },   -- purple
        spellcrit = { 0.30, 0.80, 1.0  },   -- arcane blue
        holy      = { 1.0, 1.0,  0.75 },   -- holy white-gold
        flurry    = { 0.20, 1.0,  0.50 },   -- emerald green
        finish    = { 1.0, 0.55, 0.0  },    -- finishing blow orange
        assassin  = { 0.65, 0.0,  0.0 },    -- dark blood red
        headshot  = { 0.95, 0.60, 0.80 },   -- rose pink
        slay      = { 1.0, 0.95, 0.60 },    -- radiant gold
    },
}

function runtime.spawnCritFloater(text, critType, dmg)
    if not ctrl.show_crit_floaters then return end
    local CRIT = runtime.CRIT
    local seed = math.random(1000)
    local xOff = math.random(-CRIT.SPREAD / 2, CRIT.SPREAD / 2)
    table.insert(runtime.critFloaters, {
        text      = text,
        type      = critType or 'crit',
        dmg       = dmg or 0,
        spawnedAt = os.clock(),
        xOff      = xOff,
        seed      = seed,
    })
    -- cap the queue so a massive AoE can't pile up unbounded entries
    while #runtime.critFloaters > 20 do
        table.remove(runtime.critFloaters, 1)
    end
end

function UI.drawCritOverlay()
    if not ctrl.show_crit_floaters then return end
    if #runtime.critFloaters == 0 then return end
    local CRIT = runtime.CRIT

    -- Get screen dimensions for centering
    local screenW, screenH = 0, 0
    pcall(function()
        local io = ImGui.GetIO()
        screenW = io.DisplaySize.x
        screenH = io.DisplaySize.y
    end)
    if screenW < 100 or screenH < 100 then return end

    -- The anchor point: horizontally centered, vertically at ~35% from top
    -- (roughly where the player character's head would be in a typical view).
    local anchorX = screenW / 2
    local anchorY = screenH * 0.35

    -- Overlay window: fully transparent, no decorations, click-through, always on top
    local overlayFlags = bit.bor(
        ImGuiWindowFlags.NoTitleBar,
        ImGuiWindowFlags.NoResize,
        ImGuiWindowFlags.NoMove,
        ImGuiWindowFlags.NoScrollbar,
        ImGuiWindowFlags.NoBackground,
        ImGuiWindowFlags.NoInputs,
        ImGuiWindowFlags.NoFocusOnAppearing,
        ImGuiWindowFlags.NoBringToFrontOnFocus,
        ImGuiWindowFlags.NoSavedSettings,
        ImGuiWindowFlags.NoNav
    )

    ImGui.SetNextWindowPos(0, 0)
    ImGui.SetNextWindowSize(screenW, screenH)
    ImGui.SetNextWindowBgAlpha(0)

    local _, show = ImGui.Begin('TriuneCritOverlay###critOverlay', true, overlayFlags)
    if show then
        local now = os.clock()
        local dl = ImGui.GetWindowDrawList()
        local ImVec2Type = _G.ImVec2 or ImVec2

        -- Walk floaters newest-to-oldest, prune expired ones
        local i = 1
        while i <= #runtime.critFloaters do
            local f = runtime.critFloaters[i]
            local age = now - f.spawnedAt
            if age > CRIT.LIFETIME then
                table.remove(runtime.critFloaters, i)
            else
                local t = age / CRIT.LIFETIME  -- 0..1 normalized lifetime

                -- Position: float upward, slight horizontal wobble via sin
                local wobble = math.sin(age * 4 + f.seed) * 8
                local px = anchorX + f.xOff + wobble
                local py = anchorY - (age * CRIT.RISE_SPEED) - (t * t * 30)

                -- Alpha: fade in fast, hold, fade out in last 30%
                local alpha
                if t < 0.1 then
                    alpha = t / 0.1
                elseif t > 0.7 then
                    alpha = 1.0 - ((t - 0.7) / 0.3)
                else
                    alpha = 1.0
                end
                alpha = math.max(0, math.min(1, alpha))

                -- Scale: initial pop-in bounce, then settle
                local isBig = f.dmg > 500
                local baseSize = isBig and CRIT.BIG_SIZE or CRIT.BASE_SIZE
                local scale
                if t < 0.15 then
                    -- Pop-in: overshoot to 1.5x then settle
                    scale = 1.0 + 0.5 * math.sin(t / 0.15 * math.pi)
                else
                    -- Gentle pulse
                    scale = 1.0 + 0.08 * math.sin(age * 6 + f.seed)
                end
                local fontSize = baseSize * scale

                -- Color: use type palette with pulsing brightness / hue shift
                local c = CRIT.COLORS[f.type] or CRIT.COLORS.crit
                local pulse = 0.7 + 0.3 * math.sin(age * 8 + f.seed)
                local r = math.min(1, c[1] * pulse + 0.15 * math.sin(age * 5))
                local g = math.min(1, c[2] * pulse + 0.10 * math.cos(age * 6))
                local b = math.min(1, c[3] * pulse + 0.10 * math.sin(age * 7))

                -- Rainbow shimmer for really big hits (>2000 damage)
                if f.dmg > 2000 then
                    local hueShift = (age * 3 + f.seed * 0.01) % 1.0
                    r = 0.5 + 0.5 * math.sin(hueShift * 6.28)
                    g = 0.5 + 0.5 * math.sin(hueShift * 6.28 + 2.09)
                    b = 0.5 + 0.5 * math.sin(hueShift * 6.28 + 4.19)
                end

                local colU32 = IM_COL32(
                    math.floor(r * 255),
                    math.floor(g * 255),
                    math.floor(b * 255),
                    math.floor(alpha * 255)
                )

                -- Shadow/outline: draw text offset by 1px in black for readability
                local shadowCol = IM_COL32(0, 0, 0, math.floor(alpha * 180))
                pcall(function()
                    dl:AddText(nil, fontSize, ImVec2Type(px + 1, py + 1), shadowCol, f.text)
                    dl:AddText(nil, fontSize, ImVec2Type(px, py), colU32, f.text)
                end)

                -- Sparkle particles for crits >1000 — tiny bright dots around the text
                if f.dmg > 1000 and t < 0.6 then
                    pcall(function()
                        for s = 1, 3 do
                            local sx = px + math.sin(age * 10 + s * 2.1 + f.seed) * (30 + s * 10)
                            local sy = py + math.cos(age * 10 + s * 1.7 + f.seed) * (15 + s * 8)
                            local sparkleA = alpha * (1.0 - t / 0.6) * (0.5 + 0.5 * math.sin(age * 20 + s))
                            local sparkleCol = IM_COL32(255, 255, 200, math.floor(sparkleA * 255))
                            dl:AddCircleFilled(ImVec2Type(sx, sy), 2 + math.sin(age * 15 + s) * 1, sparkleCol, 6)
                        end
                    end)
                end

                i = i + 1
            end
        end
    end
    ImGui.End()
end

-- Event handlers: capture EQ critical hit chat messages and spawn floaters.
-- Progression server (classic) format: separate lines like
--   "You score a critical hit! (123)"
--   "You land a Crippling Blow!(456)"
--   "You score a Deadly Strike!(789)"
-- Modern format (TBL+): appended to the damage line:
--   "You hit a gnoll for 123 points of damage. (Critical)"
-- We handle both patterns.

mq.event('TriuneCritHit', '#*#You score a critical hit!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('CRITICAL! %d', dmg), 'crit', dmg)
end)

mq.event('TriuneCripBlow', '#*#You land a Crippling Blow!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('CRIPPLING BLOW! %d', dmg), 'crip', dmg)
end)

mq.event('TriuneDeadlyStrike', '#*#You score a Deadly Strike!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('DEADLY STRIKE! %d', dmg), 'deadly', dmg)
end)

-- Holy Forge (Paladin Slay Undead)
mq.event('TriuneSlayUndead', '#*#You slay#*#undead!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('SLAY UNDEAD! %d', dmg), 'slay', dmg)
end)

-- Finishing Blow (low HP instant-kill)
mq.event('TriuneFinishBlow', '#*#You land a Finishing Blow!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('FINISHING BLOW! %d', dmg), 'finish', dmg)
end)

-- Assassinate (Rogue)
mq.event('TriuneAssassinate', '#*#You assassinate#*#', function()
    runtime.spawnCritFloater('ASSASSINATE!', 'assassin', 32000)
end)

-- Headshot (Ranger)
mq.event('TriuneHeadshot', '#*#You headshotted#*#', function()
    runtime.spawnCritFloater('HEADSHOT!', 'headshot', 32000)
end)

-- Flurry (extra melee swings)
mq.event('TriuneFlurry', '#*#You flurry#*#', function()
    runtime.spawnCritFloater('FLURRY!', 'flurry', 0)
end)

-- Critical spell nuke (modern format: "You deliver a critical blast! (X)")
mq.event('TriuneSpellCrit', '#*#critical blast!#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('SPELL CRIT! %d', dmg), 'spellcrit', dmg)
end)

-- Critical heal
mq.event('TriuneHealCrit', '#*#critical heal#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('CRIT HEAL! %d', dmg), 'holy', dmg)
end)

-- Critical DoT tick (older format)
mq.event('TriuneDotCrit', '#*#critical dot#*#(#1#)#*#', function(_, dmgStr)
    local dmg = tonumber(dmgStr) or 0
    runtime.spawnCritFloater(string.format('CRIT DOT! %d', dmg), 'spellcrit', dmg)
end)

mq.imgui.init('TriuneCritOverlay', UI.drawCritOverlay)
mq.imgui.init('TriuneCooldownWindow', UI.drawCooldownWindow)
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
            runtime.onCharacterChanged()
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
        if runtime.pendingAATrain and runtime.processAATrainWorkflow then
            runtime.processAATrainWorkflow()
        end
        if runtime.pendingPostTrainScanAt and os.clock() >= runtime.pendingPostTrainScanAt then
            runtime.pendingPostTrainScanAt = nil
            runtime.lastAAScanAt = 0
            runtime.aaFilterDirty = true
            if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
        end
        if runtime.pendingReadSpecialTab and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not isCasting() then
            runtime.pendingReadSpecialTab = false
            if runtime.readSpecialTabOnce then runtime.readSpecialTabOnce(false) end
            if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
        end
        local currentSpentAA = nil
        pcall(function() currentSpentAA = tonumber(mq.TLO.Me.AAPointsSpent() or 0) or 0 end)
        if currentSpentAA and runtime.lastObservedAAPointsSpent ~= nil and currentSpentAA ~= runtime.lastObservedAAPointsSpent then
            runtime.lastObservedAAPointsSpent = currentSpentAA
            runtime.lastAAScanAt = 0
            runtime.aaFilterDirty = true
            if runtime.scanPlayerAAs then runtime.scanPlayerAAs(true) end
        end
        if ctrl.auto_spend_aa and runtime.checkAutoSpendAA then
            runtime.checkAutoSpendAA()
        end
        if ctrl.auto_summon_fireworks and runtime.checkAutoSummonFireworks and not isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() then
            runtime.checkAutoSummonFireworks()
        end
        if (ctrl.auto_group or ctrl.auto_trade or ctrl.auto_dzadd) and runtime.checkAutoAccept then
            runtime.checkAutoAccept()
        end
        runtime.updateMapRadiusVisuals()
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
            runtime.lastTick = os.clock()
            runtime.wasRunning = true
        elseif not ctrl.running then
            if runtime.wasRunning then
                runtime.wasRunning = false
                if runtime.fullStop then runtime.fullStop() end
            end
        end

        -- auto-save: persist the loadout ~1.5s after any change (no Save click needed)
        local sig = loadoutSig()
        if sig ~= runtime.lastSig then
            runtime.lastSig = sig; runtime.autoDirty = true; runtime.autoDirtyAt = os.clock()
        end
        if runtime.autoDirty and (os.clock() - runtime.autoDirtyAt) > 1.5 then
            runtime.saveLoadout(true); runtime.autoDirty = false
        end

        mq.delay(memmed and 200 or 150)
    end
end

runtime.pendingReadSpecialTab = true
runMainLoop()
if runtime.clearMapRadiusVisuals then runtime.clearMapRadiusVisuals() end
runtime.saveLoadout(true)
