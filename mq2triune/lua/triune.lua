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
local VERSION           = '1.7.0'
local open              = true
local cfg               = mq.configDir

-- ============================================================================
-- Constants / class data
-- ============================================================================
local ALL_ABBR          = { 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm',
    'Nec', 'Wiz', 'Mag', 'Enc', 'Bst', 'Ber' }

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
local lvlMin, lvlMax = 1, 65

-- loadout.gems[i] = { cls=, spell=, target=, when=, pct= }  (or nil)
-- loadout.aas and loadout.discs are maps: name -> { cls=, target=, when=, enabled=, pct= }
-- (discs = disciplines, e.g. Mend/Lay on Hands/Hand of Piety -- fired via
-- /disc, not /alt act; kept separate from aas since they're a different
-- activation command and data source, but use the identical entry shape)
local loadout        = { gems = {}, aas = {}, discs = {}, clickies = {} }

-- combat control state (Control tab). NOTE: this is the control surface; wiring it
-- into the actual casting/movement engine is phase 2.
-- Primary Combat Modes & Submodes
local PRIMARY_MODES  = { 'Manual', 'Puller', 'Assist' }
local SUBMODES       = {
    Puller = { 'Hunt', 'Camp' },
    Assist = { 'Chase', 'Camp', 'Backline' }
}
local PULL_STYLES    = { 'Melee', 'Spell', 'Pet', 'Ranged' }
local PULL_CON_LIST  = {
    'Scowling',
    'Threateningly',
    'Dubious',
    'Apprehensive',
    'Indifferent',
    'Amiably',
    'Kindly',
    'Warmly',
    'Ally',
}

local MODE_DESC      = {
    Manual = 'Fights your current or acquired target automatically. Does not roam.',
    Puller = 'Pulling & hunting engine. Hunt roams and solo-kills; Camp pulls mobs back to set camp.',
    Assist = 'Assists the Main Assist. Chase follows MA; Camp holds camp spot; Backline is ranged/caster support.'
}

local SUBMODE_DESC   = {
    ['Puller:Hunt']     = 'Roams within search radius looking for valid mobs and kills them on the spot.',
    ['Puller:Camp']     = 'Pulls mobs within radius back to set camp location and tanks/fights them at camp.',
    ['Assist:Chase']    = 'Follows Main Assist everywhere and assists on MA target.',
    ['Assist:Camp']     = 'Holds set camp position and assists MA on MA target, returning to camp when idle.',
    ['Assist:Backline'] = 'Ranged/caster support; assists MA without moving to melee range.'
}

local ctrl                   -- forward declaration for lexical scoping in helpers
local isXTargetId            -- forward declaration for lexical scoping in helpers
local isGroupOrRaidMember    -- forward declaration for lexical scoping in helpers
local isSpawnPetOrPlayer     -- forward declaration for lexical scoping in helpers
local isAnyPet               -- forward declaration for lexical scoping in helpers
local isHostileTarget        -- forward declaration for lexical scoping in helpers
local isCombat               -- forward declaration for lexical scoping in helpers
local buffActive             -- forward declaration for lexical scoping in helpers
local updateMapRadiusVisuals -- forward declaration for lexical scoping in UI & helpers
local clearMapRadiusVisuals  -- forward declaration for lexical scoping in UI & helpers
local isPoisonedOrDiseased   -- forward declaration for lexical scoping in helpers
local getAllMyPets           -- forward declaration for lexical scoping in helpers
local resolvePetTargetId     -- forward declaration for lexical scoping in helpers

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

local function standIfSittingOrDucked()
    if isSitting() or isDucking() then
        mq.cmd('/stand')
        return true
    end
    return false
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

    if c.hunter_z_plane == nil then c.hunter_z_plane = 15 end
    if c.hunter_z == nil then c.hunter_z = 75 end
    if c.buff_on_start == nil then c.buff_on_start = true end

    if type(c.pull_con_filter) ~= 'table' then
        c.pull_con_filter = {}
    end
    for _, conName in ipairs(PULL_CON_LIST) do
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
        combat_style         = 'Melee',
        melee_dist           = 14,
        ranged_dist          = 40,
        ma_name              = '',
        assist_at            = 98,
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
        check_closer_mobs    = true,
        nav_fallback_stick   = false,
        debug_mode           = false,
        scribed_only         = true,
        aa_purchased_only    = true,
        disc_trained_only    = true,
        medbreak_enabled     = false,
        medbreak_hp_on       = false,
        medbreak_hp_start    = 20,
        medbreak_hp_stop     = 90,
        medbreak_mana_on     = false,
        medbreak_mana_start  = 20,
        medbreak_mana_stop   = 90,
        medbreak_end_on      = false,
        medbreak_end_start   = 20,
        medbreak_end_stop    = 90,
        cast_max_retries     = 2,
        cast_lockout_sec     = 30,
        buff_on_start        = true,
        buff_in_combat       = false,
        buff_instant_in_combat = true,
        buff_max_tries       = 3,
        buff_retry_sec       = 60,
        min_mana_pct         = 0,
        pull_min_hp_pct      = 0,
        pet_assist_at        = 100,
        pet_hold_enabled     = true,
        show_map_radius      = true,
        burn                 = false,
        compact              = false,
        use_waypoints        = false,
        waypoint_radius      = 20,
        waypoint_scan_radius = 100,
        waypoint_direction   = 1,
        current_waypoint_idx = 1,
        waypoints            = {}
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
    pendingMem = {},
    lastCast = {},
    lastTick = 0,
    wasRunning = false,
    startBuffPass = false,
    startBuffAt = 0,
    wasUnderAttack = false,
    buffTries = {},
    startBuffStalls = {},
    lastSig = nil,
    autoDirty = false,
    autoDirtyAt = 0,
    lastBuffDiagAt = 0,
    lastHunterDiagAt = 0,
    lastHunterMsgKey = nil,
    lastGemDiagAt = 0,
    lastAssistCmdAt = 0,
    sungBuffs = {},
    lastMapDraw = { active = false, type = nil, key = '' },
    trackStartTime = nil,
    startAA = nil,
    currentAA = 0,
    startPlat = nil,
    currentPlat = 0,
    ignoreList = {},
    pullList = {},
    ignoreInput = '',
    pullInput = '',
    conCache = {},
    lastConReqAt = 0,
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
    varN = 0
}

-- A "missing buff" that still reads missing right after it was cast is nearly
-- always a detection false negative rather than a buff that failed to land. With
-- no cap the entry re-fires every tick for as long as the condition holds. After
-- a few attempts the entry is parked for a while; it is retried later in case
-- the cast really did fail.
runtime.buffRetryOk = function(key)
    local st = runtime.buffTries[key]
    if not st then return true end
    if st.blockedUntil and os.clock() < st.blockedUntil then return false end
    if st.blockedUntil then runtime.buffTries[key] = nil end
    return true
end

runtime.buffTryRecorded = function(key, spellName)
    -- The bar snapshot is cached for a fraction of a second; without dropping it
    -- here the very next tick would still read the buff we just landed as
    -- missing and cast it a second time.
    if runtime.invalidateBarCache then runtime.invalidateBarCache() end
    local maxTries = tonumber(ctrl and ctrl.buff_max_tries) or 3
    local backoff = tonumber(ctrl and ctrl.buff_retry_sec) or 60
    local st = runtime.buffTries[key] or { n = 0 }
    st.n = (st.n or 0) + 1
    if st.n >= maxTries then
        st.n = 0
        st.blockedUntil = os.clock() + backoff
        print(string.format('\ay[Triune]\ax "%s" still reads missing after %d casts -- pausing that buff for %ds.',
            tostring(spellName), maxTries, backoff))
    end
    runtime.buffTries[key] = st
end

-- Queue a one-shot self-buff pass. Armed on Start and again each time a fight
-- ends, never while paused or mid-combat. See startBuffTick.
local function beginStartBuffPass()
    if ctrl.buff_on_start == false then
        runtime.startBuffPass = false
        return
    end
    runtime.startBuffPass = true
    runtime.startBuffAt = os.clock()
    runtime.startBuffStalls = {}
    -- Stop swinging before the pass judges whether a fight is on, so leftover
    -- /attack from the last kill does not read as combat on the first tick.
    if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    print('\ag[Triune]\ax checking self buffs.')
end

local petState = {
    myPets = {},
    lastObservedId = 0,
    lastCastCls = nil,
    lastCmdTargetId = 0,
    lastCmdAt = 0,
    manualHunterHold = nil,
    petHoldActive = false, -- true when we issued /pet hold waiting for HP threshold
    holdIssuedForId = 0    -- target ID for which a hold was issued
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
    nonXtarTargetId = 0,
    nonXtarEngageAt = 0,
    lastCombatFaceAt = 0,
    lastStickDist = 0
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

-- Full-stop and onZoned: reset every movement/combat command and stale state.
-- Used by STOP, a mode switch, and the death guard.
local fullStop, onZoned, hasActivePet, handleCannotSeeTarget
local PET_CLASSES = { Nec = true, Mag = true, Bst = true, Enc = true, Shm = true, SK = true, Dru = true }
local function trioHasPetClass()
    for _, c in ipairs(myClasses) do if PET_CLASSES[c] then return true end end
    return false
end

-- Returns true if any character in the trio owns the Advanced Pet Discipline AA
-- (rank >= 1). This AA unlocks the /pet hold command; without it the command is
-- silently ignored by the game, so we gate the hold logic on its presence.
-- NOTE: the entire check is wrapped in a single pcall -- calling aa() on a TLO
-- object for an AA the character doesn't own throws in some MQ builds, and that
-- exception would silently abort combatTick (caught by the outer pcall in the
-- main loop). The single pcall catches any throw and returns false safely.
local function hasAdvPetDiscipline()
    local ok, result = pcall(function()
        local aa = mq.TLO.Me.AltAbility('Advanced Pet Discipline')
        if not aa or not aa() then return false end
        local rank = aa.Rank() or 0
        return rank >= 1
    end)
    return ok and result == true
end

-- Ignore list: names Hunter/Puller must never auto-target (e.g. a friendly NPC
-- it tried to attack by mistake). Shared across ALL your characters (stored at
-- ALLDATA.__ignore, not per-character), since a friendly name is friendly no
-- matter which toon is playing. Never filters Assist or a target you pick yourself.


local FRIENDLY = { 'Myself', 'Main Assist', 'Tank', 'Lowest-HP Ally', 'Whole Group', 'Pet' }
local ENEMY    = { 'Current Target', 'Assist Target', 'Nearest Add', 'Unmezzed Add', 'All Enemies' }
local TARGETS  = {}
for _, t in ipairs(FRIENDLY) do TARGETS[#TARGETS + 1] = 'F: ' .. t end
for _, t in ipairs(ENEMY) do TARGETS[#TARGETS + 1] = 'E: ' .. t end
local WHENS = { 'HP <=', 'target HP <=', 'my HP <=', 'my Mana <=', 'missing buff', 'missing pet', 'has Poison/Disease',
    'ally is Dead', 'add is loose', 'twist while fighting', 'in combat',
    'always' }

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
    local MQSHORT = {
        WARRIOR = 'War', WAR = 'War', WARRIORS = 'War',
        CLERIC = 'Clr', CLR = 'Clr', CLERICS = 'Clr',
        PALADIN = 'Pal', PAL = 'Pal', PALADINS = 'Pal',
        RANGER = 'Rng', RNG = 'Rng', RANGERS = 'Rng',
        SHADOWKNIGHT = 'SK', SHADOW = 'SK', SHD = 'SK', SK = 'SK', SHADOWKNIGHTS = 'SK',
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
        BERSERKER = 'Ber', BER = 'Ber', BERSERKERS = 'Ber'
    }
    return MQSHORT[up] or (ALL_ABBR and idxOf(ALL_ABBR, s) > 0 and s) or nil
end

local function classColor(abbr)
    local SLOT_COLORS = {
        { 0.30, 0.70, 1.00 }, -- slot 1: Arcane Blue
        { 1.00, 0.55, 0.30 }, -- slot 2: Ember Gold
        { 0.37, 0.88, 0.64 }, -- slot 3: Jade Green
    }
    for i, c in ipairs(myClasses) do
        if c == abbr then
            local col = SLOT_COLORS[i] or { 0.49, 0.56, 0.65 }
            return col[1], col[2], col[3], col[4] or 1.0
        end
    end
    return 0.49, 0.56, 0.65, 1.0
end

local function classPlausible(abbr)
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
            if c and tonumber(tostring(c)) and tonumber(tostring(c)) > 0 then
                count = tonumber(tostring(c))
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
    local cleaned = text:gsub('^%s*%d+[%s%.:]*', ''):gsub('^%s+', '')
    if cleaned == '' then return nil end

    local up = cleaned:upper()
    if up:find('^LEVEL') or up:find('^LVL') then return nil end

    local code3 = up:sub(1, 3)
    if MQSHORT[code3] then return MQSHORT[code3] end

    local code2 = up:sub(1, 2)
    if MQSHORT[code2] then return MQSHORT[code2] end

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
getAllMyPets = function()
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
hasActivePet = function()
    local pets = getAllMyPets()
    return #pets > 0
end

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

local function hasLoS(id)
    if not id or id <= 0 then return false end
    local los = false
    pcall(function() los = mq.TLO.Spawn(id).LineOfSight() or false end)
    return los
end

local function pctHP(id)
    if not id or id <= 0 then return 0 end
    local hp = 0
    pcall(function() hp = mq.TLO.Spawn(id).PctHPs() or 0 end)
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
end

-- Returns true if the spawn ID belongs to the player, their pet, any group member,
-- any group member pet, or any raid member.
isGroupOrRaidMember = function(id)
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
isAnyPet = function(s_or_id)
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
isSpawnPetOrPlayer = function(id)
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

local function findFirstNPCXtarget(unmezzedOnly, isIgnoredFn, isUnreachableFn, maxDist, maxZ)
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
                        local dist = s.Distance3D() or 999
                        local okZ, sz = pcall(function() return s.Z() end)
                        local zOk = (not maxZ) or (okZ and sz and math.abs(sz - myZ) <= maxZ)
                        if (stype == 'NPC' or stype == 'Pet')
                            and not s.Dead() and stype ~= 'Corpse'
                            and isHostileTarget(id)
                            and dist <= maxDist
                            and zOk
                            and (not isIgnoredFn or not isIgnoredFn(cname))
                            and (not isUnreachableFn or not isUnreachableFn(id)) then
                            if not unmezzedOnly or not buffActive(id, 'Mez') then
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

local function createCastTracker()
    local failureCount = {}
    local lockouts = {}
    -- Why each spell last failed ('fizzled', 'did not take hold', ...), so a
    -- lockout can say what went wrong instead of just that it gave up.
    local lastReason = {}

    local tracker = {}

    local function recordFailure(spellName, maxRetries, lockoutSec, reason)
        if not spellName then return end
        if reason then lastReason[spellName] = reason end
        local mRetries = tonumber(maxRetries) or 2
        local lSec = tonumber(lockoutSec) or 30
        failureCount[spellName] = (tonumber(failureCount[spellName]) or 0) + 1
        if failureCount[spellName] >= mRetries then
            lockouts[spellName] = os.clock() + lSec
            failureCount[spellName] = 0
            print(string.format('\ar[Triune]\ax Lockout applied for "%s" (%ds) -- %s', spellName, lSec,
                lastReason[spellName] or 'repeated failures'))
        end
    end

    local function isLockedOut(spellName)
        if not spellName then return false end
        local untilTime = tonumber(lockouts[spellName])
        if not untilTime then return false end
        if os.clock() < untilTime then return true end
        lockouts[spellName] = nil
        return false
    end

    local function onFailureEvent(reason, maxRetries, lockoutSec)
        local castingName = nil
        pcall(function() castingName = mq.TLO.Me.Casting.Name() end)
        if not castingName or castingName == '' then
            castingName = tracker.activeSpell or tracker.lastSpell
        end
        if castingName and castingName ~= '' then
            tracker.failed = true
            recordFailure(castingName, maxRetries, lockoutSec, reason)
        end
    end

    local function recordSuccess(spellName)
        if not spellName then return end
        failureCount[spellName] = 0
        lockouts[spellName] = nil
        lastReason[spellName] = nil
    end

    local function failureReason(spellName)
        if not spellName then return nil end
        return lastReason[spellName]
    end

    tracker.recordFailure = recordFailure
    tracker.recordSuccess = recordSuccess
    tracker.isLockedOut = isLockedOut
    tracker.onFailureEvent = onFailureEvent
    tracker.failureReason = failureReason
    tracker.clear = function()
        failureCount = {}; lockouts = {}; lastReason = {}
    end
    tracker.failed = false
    tracker.activeSpell = nil
    tracker.lastSpell = nil
    tracker.wasCasting = false

    return tracker
end

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

local function tryMem(slot, name)
    if not slot or not name or name == '' then return false end

    -- 1. Already memorized in target slot? (matches exact string, clean name, rank name, or normalized name)
    if isGemMatching(slot, name) then return true end

    -- 2. Check combat/moving conditions
    if mq.TLO.Me.Combat() then
        print(string.format('\ay[Triune]\ax Cannot memorize "%s" into gem %d while in combat.', name, slot))
        return false
    end
    if mq.TLO.Me.Moving() then
        print(string.format('\ay[Triune]\ax Stand still to memorize "%s" into gem %d.', name, slot))
        return false
    end

    -- 3. Verify spell is scribed
    if not isScribed(name) then
        print(string.format('\ar[Triune]\ax Cannot memorize "%s" -- not scribed in spellbook!', name))
        return false
    end

    -- 4. Unmemorize duplicate instances of this spell in other gem slots
    for s = 1, NUM_GEMS do
        if s ~= slot and isGemMatching(s, name) then
            pcall(function()
                mq.cmdf('/unmemspell %d', s)
                mq.delay(200)
            end)
            break
        end
    end

    -- 5. Clear cursor before starting
    clearCursor()

    -- 6. Unmemorize target slot if occupied by a different spell
    local currentGemName = nil
    pcall(function() currentGemName = mq.TLO.Me.Gem(slot).Name() end)
    if currentGemName and currentGemName ~= '' and currentGemName ~= 'NULL' then
        pcall(function()
            mq.cmdf('/unmemspell %d', slot)
            mq.delay(300)
        end)
    end

    -- 7. Stand up if sitting or ducking
    if isSitting() or isDucking() then
        mq.cmd('/stand')
        mq.delay(200)
    end

    -- 8. Issue /memspell command
    print(string.format('\ay[Triune]\ax Memorizing "%s" into gem %d...', name, slot))
    pcall(function()
        mq.cmdf('/memspell %d "%s"', slot, name)
    end)

    -- 9. Poll up to 6.5s for spell memorization to finish
    local landed = false
    local startWait = os.clock()
    while (os.clock() - startWait) < 6.5 do
        if isGemMatching(slot, name) then
            landed = true
            break
        end
        if mq.TLO.Me.Combat() or mq.TLO.Me.Moving() then break end
        mq.delay(200)
    end

    clearCursor()

    if landed then
        print(string.format('\ag[Triune]\ax Successfully memorized "%s" -> gem %d', name, slot))
    else
        print(string.format('\ar[Triune]\ax Memorization of "%s" (gem %d) timed out or failed.', name, slot))
    end

    return landed
end

local ALIAS_CLASS_MAP = {
    SK = 'SK',
    SHD = 'SK',
    BST = 'Bst',
    Bst = 'Bst',
    SHM = 'Shm',
    Shm = 'Shm',
}

local function lookupSpells(abbr)
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

local PURE_MELEE_CLASSES = { War = true, WAR = true, Mnk = true, MNK = true, Rog = true, ROG = true, Ber = true, BER = true }

local function clearFilteredSpellsCache()
    runtime.filteredSpellsCache = {}
end

local function isDisciplineSpell(abbr, spellName)
    if not abbr or not spellName or spellName == "" then return false end
    if PURE_MELEE_CLASSES[abbr] or PURE_MELEE_CLASSES[abbr:upper()] then return true end

    if DATA and DATA.discs then
        local alt = ALIAS_CLASS_MAP[abbr:upper()] or abbr
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
    if not abbr or PURE_MELEE_CLASSES[abbr] or PURE_MELEE_CLASSES[abbr:upper()] then
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

-- Base SKILLS (not spells/discs/AAs -- no extractor entry, no cooldown data,
-- fired via /doability) worth an emergency %-based condition. Keyed by class
-- so this stays correctly empty for classes with no notable one. Routine
-- rotation skills (Kick, Tiger Claw, Flying Kick, etc.) deliberately excluded
-- -- handled by the user's separate autoskill window.
local function isSpecialSkill(name)
    local SPECIAL_SKILLS = {
        Mnk = { 'Mend', 'Feign Death' },
    }
    for _, list in pairs(SPECIAL_SKILLS) do
        for _, n in ipairs(list) do if n == name then return true end end
    end
    return false
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
        if not PURE_MELEE_CLASSES[abbr] and not PURE_MELEE_CLASSES[abbr:upper()] then
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

-- Read the spells currently on the gem bar into the loadout -- no re-memming; the
-- spells are already memmed, so the engine can use them immediately.
local function importCurrentGems(targetGemsTable)
    targetGemsTable = targetGemsTable or loadout.gems
    for i = 1, NUM_GEMS do
        local nm
        pcall(function() nm = mq.TLO.Me.Gem(i).Name() end)
        if nm and nm ~= '' and nm ~= 'NULL' then
            local cls, bene, kind = spellClassInfo(nm)
            local tgt, wn, pc = defaultsForKind(kind, bene)
            targetGemsTable[i] = { cls = cls, spell = nm, target = tgt, when = wn, pct = pc }
        else
            targetGemsTable[i] = nil
        end
    end
end

-- Catches a stale loadout: a gem configured for spell X while the physical
-- bar actually has something else (or nothing) memmed in that slot -- e.g.
-- left over from before a re-mem, or the bar changed outside Triune. This is
-- exactly what caused a "missing buff" condition to spam forever on a spell
-- that was never actually going to land, because Me.Gem(g.spell)() inside
-- castGem silently failed every attempt without ever explaining why. Warns
-- once per mismatch (not every check) rather than auto-fixing, since
-- auto-correcting could clobber a spell you just picked and haven't memmed
-- yet -- skips any slot with a mem still queued/in-progress for that reason.
local function checkGemMemSync()
    local now = os.clock()
    if (now - (runtime.lastGemSyncCheckAt or 0)) < 10.0 then return end
    runtime.lastGemSyncCheckAt = now
    runtime.gemSyncWarned = runtime.gemSyncWarned or {}
    if mq.TLO.Window('SpellBookWnd').Open() then return end -- actively memming right now -- don't check mid-swap
    for i = 1, NUM_GEMS do
        local g = loadout.gems[i]
        if g and g.spell and g.spell ~= '' and not runtime.pendingMem[i] then
            if not isGemMatching(i, g.spell) then
                local memmed
                pcall(function() memmed = mq.TLO.Me.Gem(i).Name() end)
                if memmed and memmed ~= '' and memmed ~= 'NULL' then
                    if not runtime.gemSyncWarned[i] then
                        runtime.gemSyncWarned[i] = true
                        print(string.format(
                            '\ay[Triune]\ax gem %d mismatch -- configured for "%s" but the bar actually has "%s" memmed there. '
                            .. 'It will never successfully cast/detect correctly like this -- use Mem All to Bar, or re-pick the spell for this gem.',
                            i, g.spell, memmed))
                    end
                end
            else
                runtime.gemSyncWarned[i] = nil -- resolved (or slot empty) -- allow a future mismatch to warn again
            end
        else
            runtime.gemSyncWarned[i] = nil
        end
    end
end

local function collectEntry()
    return {
        classes = myClasses,
        lvlMin = lvlMin,
        lvlMax = lvlMax,
        gems = loadout.gems,
        aas = loadout.aas,
        discs = loadout.discs,
        clickies = loadout.clickies,
        control = ctrl
    }
end
local function applyEntry(e)
    if type(e) ~= 'table' then return end
    if type(e.classes) == 'table' and #e.classes > 0 then myClasses = e.classes end
    lvlMin = e.lvlMin or lvlMin; lvlMax = e.lvlMax or lvlMax
    clearFilteredSpellsCache()
    loadout.gems = e.gems or {}
    loadout.aas  = {}
    if type(e.aas) == 'table' then
        for k, v in pairs(e.aas) do
            if not tonumber(k) and type(v) == 'table' then
                loadout.aas[k] = v
            end
        end
    end
    loadout.discs = e.discs or {}
    loadout.clickies = {}
    if type(e.clickies) == 'table' then
        for _, v in ipairs(e.clickies) do
            if type(v) == 'table' and v.name then
                table.insert(loadout.clickies, v)
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
        -- The combat anchor location is a zone-specific position (like camp_loc): never
        -- restore it from a saved file because the player will almost certainly
        -- be in a different location or zone. Keep the user's radius setting intact.
        ctrl.hunter_combat_loc = nil
    end
end

local function loadAll()
    local fn = loadfile(cfg .. '/triune_loadout.lua')
    if not fn then return end
    local ok, t = pcall(fn)
    if ok and type(t) == 'table' then
        ALLDATA = t
        if type(ALLDATA.__ignore) == 'table' then runtime.ignoreList = ALLDATA.__ignore end
        if type(ALLDATA.__pullList) == 'table' then runtime.pullList = ALLDATA.__pullList end
    end
end

local function saveLoadout(silent)
    if myName then ALLDATA[myName] = collectEntry() end
    ALLDATA.__ignore = runtime.ignoreList
    ALLDATA.__pullList = runtime.pullList
    local f = io.open(cfg .. '/triune_loadout.lua', 'w')
    if not f then return end
    f:write('return '); serialize(ALLDATA, f, 1); f:close()
    if not silent then print('\ag[Triune]\ax saved loadout for ' .. tostring(myName or '?') .. '.') end
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
local function addIgnore(name)
    if not name or name == '' or isIgnored(name) then return end
    table.insert(runtime.ignoreList, name)
    table.sort(runtime.ignoreList)
    saveLoadout(true)
    print('\ag[Triune]\ax added to ignore list: ' .. name)
end
local function removeIgnore(name)
    for i, n in ipairs(runtime.ignoreList) do
        if n == name then
            table.remove(runtime.ignoreList, i); break
        end
    end
    saveLoadout(true)
    print('\ag[Triune]\ax removed from ignore list: ' .. name)
end

-- pull-list (include-list) helpers for Puller mode:
local function isPullListed(name)
    if not name or name == '' then return false end
    for _, n in ipairs(runtime.pullList) do if n == name then return true end end
    return false
end
local function addPull(name)
    if not name or name == '' or isPullListed(name) then return end
    table.insert(runtime.pullList, name)
    table.sort(runtime.pullList)
    saveLoadout(true)
    print('\ag[Triune]\ax added to pull list: ' .. name)
end
local function removePull(name)
    for i, n in ipairs(runtime.pullList) do
        if n == name then
            table.remove(runtime.pullList, i); break
        end
    end
    saveLoadout(true)
    print('\ag[Triune]\ax removed from pull list: ' .. name)
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
    if bestIdx >= #wps and #wps > 1 then
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
    saveLoadout(true)
    runtime.syncWaypointMapLines()
    return wpNum, wpName, x, y, z
end

function runtime.wpClear()
    ctrl.waypoints = {}
    ctrl.current_waypoint_idx = 1
    ctrl.waypoint_direction = 1
    saveLoadout(true)
    runtime.syncWaypointMapLines()
end

function runtime.wpDelete(idx)
    if not ctrl.waypoints or not ctrl.waypoints[idx] then return false end
    table.remove(ctrl.waypoints, idx)
    if not ctrl.current_waypoint_idx or ctrl.current_waypoint_idx > #ctrl.waypoints then
        ctrl.current_waypoint_idx = 1
        ctrl.waypoint_direction = 1
    end
    saveLoadout(true)
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
    saveLoadout(true)
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
    saveLoadout(true)
    runtime.syncWaypointMapLines()
    return true
end

local function isPullAllowed(name)
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

local function isConAllowed(s)
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
    for i = 1, NUM_GEMS do
        local g = loadout.gems and loadout.gems[i]
        if type(g) == 'table' then
            p[#p + 1] = tostring(i) ..
                '~' ..
                tostring(g.enabled) ..
                '~' ..
                tostring(g.spell) ..
                '~' ..
                tostring(g.target) ..
                '~' ..
                tostring(g.when) ..
                '~' ..
                tostring(g.pct) ..
                '~' ..
                tostring(g.boss_only) ..
                '~' .. tostring(g.burn_only) .. '~' .. tostring(g.priority) .. '~' .. tostring(g.max_xtargets)
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

-- Called when the logged-in character changes: load that toon's saved setup, or
-- detect classes fresh if it's new.
local function onCharacterChanged()
    loadout = { gems = {}, aas = {}, discs = {}, clickies = {} }
    ctrl = defaultCtrl()
    runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
    lvlMin, lvlMax = 1, 65
    if ALLDATA[myName] then
        applyEntry(ALLDATA[myName])
        scanKnownDiscs()
    else
        local detected = detectClasses(true)
        if detected then myClasses = detected end
        importCurrentGems() -- new character: seed the loadout from the current bar
    end
    if not myClasses or #myClasses == 0 then
        local liveClasses = detectClasses(false)
        if liveClasses then myClasses = liveClasses end
    end
    ctrl.running = false -- never auto-start on load
end

loadAll()

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
function UI.setTooltip(txt)
    if txt ~= nil then
        ImGui.SetTooltip('%s', tostring(txt))
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

-- Renders the Triune sigil (outer ring + inner triangle + three class-colored
-- nodes) at the cursor, matching the site emblem: top node = slot 1 (arcane),
-- bottom-right = slot 2 (ember), bottom-left = slot 3 (jade). Node colors track
-- your actual gestalt trio via SLOT_COLORS/classColor. Every draw call is
-- pcall-guarded so an unsupported binding can't take the header down with it.
-- UI: header emblem
function UI.drawEmblem(size)
    pcall(function()
        local ImVec2Type = _G.ImVec2 or ImVec2 or
            (mq.imgui and mq.imgui.ImVec2) ---@diagnostic disable-line: undefined-field
        local dl = ImGui.GetWindowDrawList()
        local p = ImGui.GetCursorScreenPosVec()
        local r = size / 2
        local cx, cy = p.x + r, p.y + r

        dl:AddCircle(ImVec2Type(cx, cy), r - 1, IM_COL32(143, 208, 255, 160), 24, 1.2)

        local tri_r = r * 0.62
        local top   = ImVec2Type(cx, cy - tri_r)
        local right = ImVec2Type(cx + tri_r * 0.87, cy + tri_r * 0.55)
        local left  = ImVec2Type(cx - tri_r * 0.87, cy + tri_r * 0.55)
        dl:AddTriangle(top, right, left, IM_COL32(143, 165, 235, 150), 1.1)

        local function node(pt, slot)
            local c = SLOT_COLORS[slot] or { 0.5, 0.5, 0.5 }
            dl:AddCircleFilled(pt, r * 0.16,
                IM_COL32(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), 255), 12)
        end
        node(top, 1); node(right, 2); node(left, 3)
    end)
    ImGui.Dummy(size, size) -- reserve the layout space even if the draw above failed
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
local function toggleTool(scriptName, stopCmd)
    local s = mq.TLO.Lua.Script(scriptName)
    if s() and s.Status() == 'RUNNING' then
        mq.cmd(stopCmd or ('/lua stop ' .. scriptName))
        return 'stopped'
    end
    mq.cmd('/lua run ' .. scriptName)
    return 'started'
end

function UI.drawHeaderBar()
    UI.drawEmblem(22)
    ImGui.SameLine()
    UI.accent(ARC, myName or '(no character)')
    ImGui.SameLine(); ImGui.TextDisabled(string.format('| %s / %s / %s',
        myClasses[1] or '?', myClasses[2] or '?', myClasses[3] or '?'))
    ImGui.SameLine(); ImGui.TextDisabled(string.format('| PoP exp %d | v%s',
        DATA.era_expansion or 5, VERSION))

    UI.updateTracker()
    local elapsedSec = os.time() - (runtime.trackStartTime or os.time())
    local elapsedHrs = math.max(elapsedSec / 3600.0, 0)
    local aaGained = (runtime.startAA and runtime.currentAA) and math.max(0, runtime.currentAA - runtime.startAA) or 0
    local aaRate = (elapsedHrs > 0.0001) and (aaGained / elapsedHrs) or 0.0
    local platGained = (runtime.startPlat and runtime.currentPlat) and (runtime.currentPlat - runtime.startPlat) or 0
    local platRate = (elapsedHrs > 0.0001) and (platGained / elapsedHrs) or 0.0

    ImGui.SameLine(); ImGui.TextDisabled(string.format('| AA/hr: %.1f | Plat/hr: %.1f',
        aaRate, platRate))
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
    if ImGui.Button('Reset##hdrResetTrack') then
        UI.resetTracker()
    end
    if ImGui.IsItemHovered() then
        UI.setTooltip('Resets AA and Platinum session tracking values to 0.')
    end

    -- Toolbar buttons (on line below script info and trackers)
    if ImGui.Button('Open Spellbook##hdrBook') then
        toggleTool('triune_spellbook')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Spellbook interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('Cursor Manager##hdrCursor') then
        toggleTool('triune_cursor')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Cursor Item Manager.')
    end
    ImGui.SameLine()
    if ImGui.Button('DPS Parser##hdrDPS') then
        toggleTool('triune_dps', '/dps toggle')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or toggles the standalone Triune DPS Parser window.')
    end
    ImGui.SameLine()
    if ImGui.Button('Updater##hdrUpdate') then
        toggleTool('triune_updater')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Release Updater interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('Zone Tracker##hdrTrack') then
        toggleTool('triune_track')
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Zone Tracker interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('Compact Mode##hdrCompact') then
        ctrl.compact = true
        saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Switches Triune AutoCombat into a sleek compact HUD overlay window.')
    end

    if not DATA_OK then
        accent(WARN,
            'No triune_data.lua found in your MQ config folder -- run extract_spells.py and copy it there. Spell/AA lists will be empty.')
    end
    ImGui.Separator()
end

local CLASS_PICKER_OPTIONS = { '-- None --', 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm', 'Nec',
    'Wiz', 'Mag', 'Enc', 'Bst', 'Ber' }

function UI.drawClassPicker()
    if ImGui.CollapsingHeader('Character Classes & Loadout') then
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
                saveLoadout()
            end
            ImGui.SameLine()
        end
        if ImGui.Button('Re-detect') then reDetectRequested = true end
        ImGui.Dummy(0, 4)
        if ImGui.Button('Save Loadout', 140, 24) then saveLoadout() end
        ImGui.SameLine(); ImGui.TextDisabled('-> triune_loadout.lua (auto-saves on changes)')
        accent(MUTED, 'Detected from your in-game Inventory Window.')
        ImGui.Dummy(0, 2)
    end
end

function UI.drawHelpTab()
    if not ImGui.BeginTabItem('Help') then return end
    ImGui.Dummy(0, 4)

    if ImGui.CollapsingHeader('Slash Commands', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Commands (Alias: /ac or /triune):')
        ImGui.Dummy(0, 2)
        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##HelpCmdTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Command', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Description', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            local commands = {
                { cmd = '/ac run / /ac start',                desc = 'Start / unpause auto-combat execution' },
                { cmd = '/ac pause / /ac stop',               desc = 'Pause auto-combat execution, halt movement & disengage pet' },
                { cmd = '/ac burn [on|off]',                  desc = 'Toggle burn mode (enables "Burn Only" spells, AAs, discs)' },
                { cmd = '/ac status',                         desc = 'Print current running state and combat mode to chat' },
                { cmd = '/ac buffs',                          desc = 'Print the Effects & Songs windows and each self buff UP/MISSING verdict' },
                { cmd = '/ac compact / /ac mini',             desc = 'Toggle auto-resizing Compact Mini-Window HUD mode' },
                { cmd = '/ac help / /ac h',                   desc = 'Print slash command usage and command options in chat' },
                { cmd = '/ac spellbook',                      desc = 'Toggle the standalone spellbook & auto-memorization queue window' },
                { cmd = '/ac cursorui',                       desc = 'Toggle the standalone cursor item manager window' },
                { cmd = '/ac clearcursor',                    desc = 'Clear item on cursor (autoinventory / drop / destroy per rules)' },
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

    ImGui.Dummy(0, 6)

    if ImGui.CollapsingHeader('Combat Modes', ImGuiTreeNodeFlags.DefaultOpen) then
        accent(GOLD, 'Available Combat Modes & Behavior:')
        ImGui.Dummy(0, 2)
        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)
        if ImGui.BeginTable('##HelpModeTable', 2, tableFlags) then
            ImGui.TableSetupColumn('Mode', ImGuiTableColumnFlags.WidthFixed, 180)
            ImGui.TableSetupColumn('Behavior Description', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            for _, primaryName in ipairs(PRIMARY_MODES) do
                if SUBMODES[primaryName] then
                    for _, subName in ipairs(SUBMODES[primaryName]) do
                        local fullKey = primaryName .. ':' .. subName
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        accent(GOOD, primaryName .. ' (' .. subName .. ')')
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(SUBMODE_DESC[fullKey] or '')
                    end
                else
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    accent(GOOD, primaryName)
                    ImGui.TableNextColumn()
                    ImGui.TextWrapped(MODE_DESC[primaryName] or '')
                end
            end
            ImGui.EndTable()
        end
    end

    ImGui.EndTabItem()
end

-- Row-rendering for the Spell Gems tab.
-- UI: spell/gem list editor
function UI.drawGemList(gemsTable, idPrefix, isActiveSet, allowBurn)
    if allowBurn == nil then allowBurn = true end
    if ImGui.BeginChild('gemlist_' .. idPrefix, 0, 0) then
        for i = 1, NUM_GEMS do
            ImGui.PushID(idPrefix .. i)
            local g = gemsTable[i]
            local cls = g and g.cls or nil

            ImGui.Text(string.format('%2d', i))
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(string.format('Gem Slot %d', i))
            end
            ImGui.SameLine()

            -- class combo (none + trio)
            local classOpts = { '--' }
            for _, c in ipairs(myClasses) do classOpts[#classOpts + 1] = c end
            local curCi = cls and idxOf(classOpts, cls) or 1
            ImGui.SetNextItemWidth(64)
            local ci = ImGui.Combo('##c', curCi, classOpts)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Select the character class that owns this spell slot (or "--" to clear/disable).')
            end
            local newCls = (ci > 1) and classOpts[ci] or nil
            if newCls ~= cls then
                if newCls then
                    gemsTable[i] = { cls = newCls, spell = nil, target = 'F: Myself', when = 'always', pct = 100 }
                else
                    gemsTable[i] = nil
                end
                g = gemsTable[i]; cls = newCls
            end

            if cls then
                if not classHasSpells(cls) then
                    ImGui.SameLine(); accent(MUTED, '  ' .. cls .. ' has no gem spells (melee) -> Abilities tab')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(cls .. ' is a melee class without castable spell gems. Set up disciplines and abilities on the Abilities & AAs tab.')
                    end
                else
                    local names, lookup = filteredSpells(cls)
                    local spOpts = { '-- choose --' }
                    for _, n in ipairs(names) do spOpts[#spOpts + 1] = n end
                    -- find current selection index
                    local curSi = 1
                    if g.spell then
                        for k, lu in pairs(lookup) do if lu.name == g.spell then curSi = k + 1 end end
                    end
                    ImGui.SameLine(); ImGui.SetNextItemWidth(190)
                    local si = ImGui.Combo('##s', curSi, spOpts)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Select the spell to assign to this gem slot.')
                    end
                    if si > 1 then
                        local lu = lookup[si - 1]
                        if lu and lu.name ~= g.spell then
                            g.spell = lu.name
                            g.target, g.when, g.pct = defaultsForKind(lu.kind, lu.bene)
                            if ctrl.automem and isActiveSet then runtime.pendingMem[i] = lu.name end
                        end
                    end

                    -- target
                    ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                    local ti = ImGui.Combo('##t', idxOf(TARGETS, g.target or 'F: Myself'), TARGETS)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Target condition: who or what to cast this spell on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                    end
                    g.target = TARGETS[ti]

                    -- when
                    ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                    local wi = ImGui.Combo('##w', idxOf(WHENS, g.when or 'always'), WHENS)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Trigger condition: when this spell should be cast (e.g. HP <=, my Mana <=, missing buff, in combat, always).')
                    end
                    g.when = WHENS[wi]

                    -- percent: draggable slider that shows the value (0% = Disabled)
                    ImGui.SameLine(); ImGui.SetNextItemWidth(90)
                    local curPct = tonumber(g.pct)
                    if curPct == nil then curPct = 100 end
                    local isDis = (curPct == 0)
                    local pCount = 0
                    if isDis then pCount = UI.pushDisabledSliderStyle() end
                    local newPct = ImGui.SliderInt('##p', curPct, 0, 100, isDis and 'Disabled' or '%d%%')
                    local isHov = ImGui.IsItemHovered()
                    if pCount > 0 then UI.popDisabledSliderStyle(pCount) end
                    g.pct = newPct
                    if isHov then
                        if newPct == 0 then
                            UI.setTooltip('Spell is Disabled (0%). Drag slider above 0% to enable.')
                        else
                            UI.setTooltip(string.format('Threshold: %d%% (Set to 0%% to disable this spell).', newPct))
                        end
                    end
                end

                if allowBurn then
                    ImGui.SameLine(); ImGui.SetNextItemWidth(45)
                    local curXt = tonumber(g.min_xtar) or 1
                    if curXt < 1 then curXt = 1 end
                    if curXt > 10 then curXt = 10 end
                    local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                    local newXti = ImGui.Combo('##mxt', curXt, xtOpts)
                    g.min_xtar = newXti
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Minimum number of active NPCs on XTarget required for this spell to fire.')
                    end

                    ImGui.SameLine()
                    local boVal = ImGui.Checkbox('Burn##bo', g.burn_only or false)
                    g.burn_only = boVal
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Only cast this spell when Burn Mode is ON.')
                    end
                end
            end
            ImGui.PopID()
        end
    end
    ImGui.EndChild()
end

-- Header controls for the Spell Gems tab: level band, auto-mem, import, and "Mem All to Bar".
function UI.drawGemTabHeader(gemsTable)
    ImGui.Dummy(0, 4)
    ImGui.TextDisabled('Level band:')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Filter available spells by character level range.')
    end
    ImGui.SameLine(); ImGui.SetNextItemWidth(110)
    local newLvlMin = ImGui.InputInt('##lmin', lvlMin); if newLvlMin < 1 then newLvlMin = 1 end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Minimum character level for spell dropdown list.')
    end
    if newLvlMin ~= lvlMin then
        lvlMin = newLvlMin; clearFilteredSpellsCache()
    end
    ImGui.SameLine(); ImGui.Text('to')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Level range separator.')
    end
    ImGui.SameLine(); ImGui.SetNextItemWidth(110)
    local newLvlMax = ImGui.InputInt('##lmax', lvlMax); if newLvlMax > 65 then newLvlMax = 65 end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Maximum character level for spell dropdown list.')
    end
    if newLvlMax ~= lvlMax then
        lvlMax = newLvlMax; clearFilteredSpellsCache()
    end
    if lvlMin > lvlMax then lvlMin = lvlMax end
    ImGui.SameLine(); ImGui.TextDisabled('(spells learned in this band)')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Only spells learned between Min Level and Max Level appear in the spell dropdowns below.')
    end
    local newScribed = ImGui.Checkbox('Scribed Only', ctrl.scribed_only)
    if newScribed ~= ctrl.scribed_only then
        ctrl.scribed_only = newScribed
        clearFilteredSpellsCache()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show spells actually in your spellbook, not every spell your\nclass could ever learn in this level range. Updates live the moment\nyou scribe something new. Turn off to browse/plan ahead.')
    end
    ImGui.SameLine()
    ctrl.automem = ImGui.Checkbox('Auto-mem on pick', ctrl.automem)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'When on, choosing a spell for a gem immediately /memspell-s it into that slot (out of combat).')
    end
    ImGui.SameLine()
    if ImGui.Button('Import Memmed Gems') then
        importCurrentGems(gemsTable)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Read the spells already on your gem bar into this loadout -- no re-memming.')
    end
    ImGui.SameLine()
    local pendingCount = 0
    for _ in pairs(runtime.pendingMem) do pendingCount = pendingCount + 1 end
    if ImGui.Button('Mem All to Bar') then
        if mq.TLO.Me.Combat() then
            print('\ay[Triune]\ax cannot mem in combat -- wait until combat ends, then click Mem All to Bar again.')
        else
            for i = 1, NUM_GEMS do
                local gg = gemsTable[i]
                if gg and gg.spell then runtime.pendingMem[i] = gg.spell end
            end
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Memorizes every gem in this list onto your bar. Takes a few seconds per gem -- out of combat only.')
    end
    if pendingCount > 0 then
        ImGui.SameLine(); accent(WARN, string.format('memming... %d queued', pendingCount))
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(string.format('%d spell(s) currently queued to be memorized to your spell bar.', pendingCount))
        end
    end
    ImGui.Separator()
end

function UI.drawGemTab()
    if not ImGui.BeginTabItem('Spell Gems') then return end
    UI.drawGemTabHeader(loadout.gems)
    UI.drawGemList(loadout.gems, 'gem', true, true)
    ImGui.EndTabItem()
end

local function addClickieFromCursor()
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
    saveLoadout(true)
    print(string.format('\ag[Triune]\ax Added Clickie: [%s] (Spell: %s, Target: %s, Condition: %s)',
        itemName, spellName, defTarget, defWhen))
    return true
end

function UI.drawClickieTab()
    if not ImGui.BeginTabItem('Clickies') then return end
    ImGui.Dummy(0, 4)
    ImGui.TextWrapped('Clickable Items: Manage inventory and equipped items with activatable spell effects. Click [+ Add Item on Cursor] while holding an item to add it.')
    if ImGui.IsItemHovered() then
        UI.setTooltip('Configure automated clickies (inventory/worn items). Items are clicked automatically when conditions are met.')
    end
    ImGui.Dummy(0, 2)

    -- Cursor inspection info
    local curItem = mq.TLO.Cursor
    local hasCursorItem = curItem and curItem() and (curItem.ID() or 0) > 0
    local curName = hasCursorItem and tostring(curItem.Name() or 'Item') or nil

    if not hasCursorItem then ImGui.BeginDisabled() end
    if ImGui.Button('+ Add Item on Cursor', 170, 24) then
        addClickieFromCursor()
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

    if ImGui.BeginChild('clickielist', 0, 0) then
        loadout.clickies = loadout.clickies or {}
        local toRemove = nil

        for idx, c in ipairs(loadout.clickies) do
            ImGui.PushID('clk_' .. idx .. '_' .. (c.name or ''))

            -- Reorder Up
            local isFirst = (idx == 1)
            if isFirst then ImGui.BeginDisabled() end
            if ImGui.Button('^##up', 20, 20) then
                local tmp = loadout.clickies[idx]
                loadout.clickies[idx] = loadout.clickies[idx - 1]
                loadout.clickies[idx - 1] = tmp
                saveLoadout(true)
            end
            if isFirst then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() and not isFirst then
                UI.setTooltip('Move higher in priority order.')
            end

            ImGui.SameLine()
            -- Reorder Down
            local isLast = (idx == #loadout.clickies)
            if isLast then ImGui.BeginDisabled() end
            if ImGui.Button('v##dn', 20, 20) then
                local tmp = loadout.clickies[idx]
                loadout.clickies[idx] = loadout.clickies[idx + 1]
                loadout.clickies[idx + 1] = tmp
                saveLoadout(true)
            end
            if isLast then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() and not isLast then
                UI.setTooltip('Move lower in priority order.')
            end

            ImGui.SameLine()
            -- Delete button
            local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
            local pCol = 0
            if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.65, 0.15, 0.15, 1.0) then pCol = pCol + 1 end
            if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.85, 0.25, 0.25, 1.0) then pCol = pCol + 1 end
            if ImGui.Button('X##del', 20, 20) then
                toRemove = idx
            end
            if pCol > 0 then pcall(ImGui.PopStyleColor, pCol) end
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Remove [%s] from Clickies.', c.name))
            end

            ImGui.SameLine()
            c.enabled = ImGui.Checkbox('##en', c.enabled ~= false)
            if ImGui.IsItemHovered() then
                UI.setTooltip(string.format('Enable or disable %s.', c.name))
            end

            ImGui.SameLine()
            accent(GOOD, c.name or 'Item')
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
                ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                local ti = ImGui.Combo('##ct', idxOf(TARGETS, c.target or 'F: Myself'), TARGETS)
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Target condition: who or what to use this clickie on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                end
                c.target = TARGETS[ti]

                ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                local wi = ImGui.Combo('##cw', idxOf(WHENS, c.when or 'missing buff'), WHENS)
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Trigger condition: when this clickie should be used (e.g. missing buff, HP <=, in combat, always).')
                end
                c.when = WHENS[wi]

                ImGui.SameLine(); ImGui.SetNextItemWidth(90)
                local curPct = tonumber(c.pct)
                if curPct == nil then curPct = 100 end
                local isDis = (curPct == 0)
                local pCount = 0
                if isDis then pCount = UI.pushDisabledSliderStyle() end
                local cpVal = ImGui.SliderInt('##cp', curPct, 0, 100, isDis and 'Disabled' or '%d%%')
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

                ImGui.SameLine(); ImGui.SetNextItemWidth(45)
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
            saveLoadout(true)
            print('\ag[Triune]\ax Removed Clickie: [' .. removedName .. ']')
        end

        if #loadout.clickies == 0 then
            ImGui.Dummy(0, 10)
            accent(MUTED, '  (No clickies added yet -- pick up an item with a click effect on your cursor and click [+ Add Item on Cursor] above)')
        end
    end
    ImGui.EndChild()
    ImGui.EndTabItem()
end

local TIER_LABEL = { short = 'Short  (<= 1 min)', mid = 'Sustained  (1-5 min)', burn = 'Burn  (5 min+)' }
local TIER_ORDER = { 'short', 'mid', 'burn' }

-- UI: activated AAs tab
function UI.drawAATab()
    if not ImGui.BeginTabItem('Abilities & AAs') then return end
    ImGui.Dummy(0, 4)
    ImGui.TextWrapped('Activated AAs (each has its own timer -- all fire when ready). Grouped by cooldown.')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Activated Alternate Advancement abilities operate on independent cooldown timers and fire automatically when their conditions are met.')
    end
    ctrl.aa_purchased_only = ImGui.Checkbox('Purchased Only', ctrl.aa_purchased_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show AAs you\'ve actually bought a rank in, not every AA your\nclass could ever train. Updates live as you spend AA points. Turn\noff to browse/plan ahead.')
    end
    ImGui.Separator()

    if ImGui.BeginChild('aalist', 0, 0) then
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
                                local entry = loadout.aas[nm] or
                                    { cls = cls, target = 'F: Myself', when = 'in combat', enabled = false, pct = 30, burn_only = false }
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
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                                    local ti = ImGui.Combo('##aat', idxOf(TARGETS, entry.target), TARGETS)
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Target condition: who or what to cast this ability on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                                    end
                                    entry.target = TARGETS[ti]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                                    local wi = ImGui.Combo('##aaw', idxOf(WHENS, entry.when), WHENS)
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Trigger condition: when this ability should be cast (e.g. in combat, HP <=, my Mana <=, missing buff, always).')
                                    end
                                    entry.when = WHENS[wi]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(90)
                                    local curPct = tonumber(entry.pct)
                                    if curPct == nil then curPct = 30 end
                                    local isDis = (curPct == 0)
                                    local pCount = 0
                                    if isDis then pCount = UI.pushDisabledSliderStyle() end
                                    local newPct = ImGui.SliderInt('##aap', curPct, 0, 100, isDis and 'Disabled' or '%d%%')
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
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(45)
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
    ImGui.EndTabItem()
end

function UI.drawDiscTab()
    if not ImGui.BeginTabItem('Disciplines') then return end
    ImGui.Dummy(0, 4)
    ImGui.TextWrapped(
        'Disciplines (/disc) -- no cooldown data from the extractor to group by tier, so listed flat per class. '
        ..
        'Boss Only gates a disc to Named targets (save long-cooldown offensive discs like Mighty Strike for real fights, while '
        ..
        'a survival disc like Whirlwind can stay on for regular grinding). Priority: when multiple discs are eligible at once, '
        .. 'lower numbers are tried first -- if the top one is still on cooldown, the next one down the list fires instead.')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Combat disciplines and special skills share timer groups and are evaluated in order of assigned priority.')
    end
    ctrl.disc_trained_only = ImGui.Checkbox('Trained Only', ctrl.disc_trained_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show disciplines you\'ve actually trained, not every disc your\nclass could ever learn. Updates live as you train new ones. Turn\noff to browse/plan ahead.')
    end
    ImGui.Separator()
    if ImGui.BeginChild('disclist', 0, 0) then
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
                        ImGui.SetTooltip(string.format('Discipline/Skill: %s', nm))
                    end
                    ImGui.SameLine(); ImGui.TextDisabled('(L' .. lv .. ')')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip(string.format('Required Level: %s', tostring(lv)))
                    end
                    if entry.enabled then
                        ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                        local ti = ImGui.Combo('##dt', idxOf(TARGETS, entry.target), TARGETS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Target condition: who or what to use this discipline on (e.g. Myself, Tank, Current Target, MA Target, Pet).')
                        end
                        entry.target = TARGETS[ti]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                        local wi = ImGui.Combo('##dw', idxOf(WHENS, entry.when), WHENS)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Trigger condition: when this discipline should be used (e.g. HP <=, in combat, my Mana <=, always).')
                        end
                        entry.when = WHENS[wi]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(90)
                        local curPct = tonumber(entry.pct)
                        if curPct == nil then curPct = 30 end
                        local isDis = (curPct == 0)
                        local pCount = 0
                        if isDis then pCount = UI.pushDisabledSliderStyle() end
                        local dpVal = ImGui.SliderInt('##dp', curPct, 0, 100, isDis and 'Disabled' or '%d%%')
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
                        ImGui.SameLine(); ImGui.SetNextItemWidth(45)
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
                        local dboVal = ImGui.Checkbox('Boss Only##bo', entry.boss_only)
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
                        ImGui.SameLine(); ImGui.SetNextItemWidth(80)
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

local desiredRange    -- forward declaration; defined in the engine section below
local maxMeleeDistance -- forward declaration; defined in the engine section below

-- UI: control/settings tab
function UI.drawControlTab()
    if not ImGui.BeginTabItem('Control') then return end
    if ctrl.running then
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local pCount = 0
        if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.18, 0.70, 0.28, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.ButtonActive, 0.08, 0.40, 0.15, 1.0) then pCount = pCount + 1 end
        if Col and pcall(ImGui.PushStyleColor, Col.Text, 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

        if ImGui.Button('PAUSE', 150, 30) then
            if ctrl.mode == 'Manual' then
                setManualHunterPetHold(true, true)
            else
                setManualHunterPetHold(false, true)
            end
            ctrl.running = false
            fullStop()
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
        if ImGui.Button('START', 150, 30) then
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            ctrl.running = true
            runtime.wasRunning = true
            beginStartBuffPass()
        end

        if pCount > 0 then
            pcall(ImGui.PopStyleColor, pCount)
        end
    end
    ImGui.SameLine(); ImGui.Dummy(10, 0); ImGui.SameLine()
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

        if ImGui.Button('BURN (ON)##btnBurn', 150, 30) then
            ctrl.burn = false
            print('\ag[Triune]\ax Burn mode DISABLED.')
        end

        if pCount > 0 then
            pcall(ImGui.PopStyleColor, pCount)
        end
    else
        if ImGui.Button('BURN (OFF)##btnBurn', 150, 30) then
            ctrl.burn = true
            print('\ag[Triune]\ax Burn mode ENABLED!')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Enable/disable Burn Mode. When enabled, spells, AAs, and disciplines marked "Burn Only" will fire.\nTurns off automatically when extended target list clears.')
    end

    ImGui.Dummy(0, 6)
    accent(GOLD, 'Combat Mode')
    ImGui.SetNextItemWidth(160)
    local curPrimaryIdx = idxOf(PRIMARY_MODES, ctrl.mode)
    local newPrimaryIdx = ImGui.Combo('##primaryMode', curPrimaryIdx, PRIMARY_MODES)
    local newPrimaryMode = PRIMARY_MODES[newPrimaryIdx]

    if newPrimaryMode ~= ctrl.mode then
        if ctrl.mode == 'Manual' and newPrimaryMode ~= 'Manual' then
            setManualHunterPetHold(false)
        elseif newPrimaryMode == 'Manual' then
            if not ctrl.running or not isCombat() then
                setManualHunterPetHold(true, true)
            end
        end
        ctrl.mode = newPrimaryMode
        if SUBMODES[ctrl.mode] then
            ctrl.submode = SUBMODES[ctrl.mode][1]
        else
            ctrl.submode = 'Hunt'
        end
        clearMapRadiusVisuals()
    end

    if SUBMODES[ctrl.mode] then
        ImGui.SameLine()
        ImGui.SetNextItemWidth(140)
        local subList = SUBMODES[ctrl.mode]
        local curSubIdx = idxOf(subList, ctrl.submode)
        local newSubIdx = ImGui.Combo('##submode', curSubIdx, subList)
        if newSubIdx ~= curSubIdx then
            ctrl.submode = subList[newSubIdx]
            clearMapRadiusVisuals()
        end
    end

    local descKey = ctrl.mode
    if SUBMODES[ctrl.mode] then
        descKey = string.format('%s:%s', ctrl.mode, ctrl.submode)
    end
    accent(MUTED, SUBMODE_DESC[descKey] or MODE_DESC[ctrl.mode] or '')

    -- Manual Mode Contextual Controls
    if ctrl.mode == 'Manual' then
        ImGui.Dummy(0, 4)
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
        end

        ImGui.Dummy(0, 4)
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
        ImGui.Dummy(0, 2)
        ImGui.SetNextItemWidth(160)
        local curPullStyleIdx = 1
        for idx, ps in ipairs(PULL_STYLES) do
            if ps == (ctrl.pull_style or 'Melee') then
                curPullStyleIdx = idx; break
            end
        end
        local newPullStyleIdx = ImGui.Combo('Pull Method##pullStyle', curPullStyleIdx, PULL_STYLES)
        ctrl.pull_style = PULL_STYLES[newPullStyleIdx]
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
                    local g = loadout.gems and loadout.gems[i]
                    if g and g.spell and g.spell ~= '' then name = g.spell end
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
                    local g = loadout.gems and loadout.gems[slotNum]
                    if g then gName = g.spell end
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
                local g = loadout.gems and loadout.gems[chosenSlot]
                if g then chosenName = g.spell end
            end
            ctrl.pull_spell = chosenName or ''

            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Select the memorized spell gem to use for ranged pulling')
            end
        end

        if (ctrl.pull_style or 'Melee') ~= 'Melee' then
            ImGui.Dummy(0, 2)
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

        ImGui.Dummy(0, 2)
        ImGui.SetNextItemWidth(180)
        local pullMinHpVal = ImGui.SliderInt('Min Pull HP %##pullMinHpCtrl', ctrl.pull_min_hp_pct or 0, 0, 95, '%d%%')
        ctrl.pull_min_hp_pct = pullMinHpVal
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'Pauses pulling and sits out of combat to recover if current HP drops below\n'
                .. 'this threshold. Pulling resumes once HP reaches 100%.\n'
                .. 'Automatically stands to fight if attacked (0 = disabled / pull at any HP).')
        end

        ImGui.Dummy(0, 4)

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

            ctrl.check_closer_mobs = ImGui.Checkbox('Check for Closer NPCs while Traveling##pullerHunt',
                ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'While traveling to a distant target, check once for newly visible or spawning NPCs\nthat are significantly closer and switch to them.')
            end

            ImGui.SetNextItemWidth(180)
            ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##pullerHuntXtar', ctrl.xtar_nav_dist or 150, 25,
                300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget).')
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
                    if updateMapRadiusVisuals then updateMapRadiusVisuals() end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Saves your current position as anchor for roaming.')
            end
            ImGui.SameLine()
            if ImGui.Button('Clear Anchor##pullerAnchorClear') then
                ctrl.hunter_combat_loc = nil
                pursuit.wanderLoc = nil
                if updateMapRadiusVisuals then updateMapRadiusVisuals() end
            end

            ImGui.SetNextItemWidth(220)
            local curRadius = (ctrl.hunter_combat_radius and ctrl.hunter_combat_radius > 0) and ctrl
                .hunter_combat_radius or 250
            local newRadius, changed = ImGui.SliderInt('Combat Radius##pullerAnchorRadius', curRadius, 1, 2000)
            if changed then
                ctrl.hunter_combat_radius = newRadius
                if updateMapRadiusVisuals then updateMapRadiusVisuals() end
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
            ImGui.SameLine()
            if ImGui.Button('Clear Camp##pullerCampClear') then
                ctrl.camp_loc = nil; runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
            end

            ImGui.SetNextItemWidth(180)
            ctrl.camp_radius = ImGui.SliderInt('Pull Radius', ctrl.camp_radius or 100, 10, 500)
            ImGui.SetNextItemWidth(180)
            ctrl.camp_z = ImGui.SliderInt('Pull Height Diff (Z)', ctrl.camp_z or 75, 10, 300)

            ImGui.SetNextItemWidth(180)
            ctrl.pull_min_level = ImGui.SliderInt('Min NPC Level', ctrl.pull_min_level or 1, 1, 100)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(180)
            ctrl.pull_max_level = ImGui.SliderInt('Max NPC Level', ctrl.pull_max_level or 100, 1, 100)
            if ctrl.pull_min_level > ctrl.pull_max_level then ctrl.pull_min_level = ctrl.pull_max_level end

            ctrl.check_closer_mobs = ImGui.Checkbox('Check for Closer NPCs while Traveling##pullerCampClose',
                ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs)

            ImGui.SetNextItemWidth(180)
            ctrl.xtar_nav_dist = ImGui.SliderInt('Max XTarget Chase Range##pullerCampXtar', ctrl.xtar_nav_dist or 150, 25,
                300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Maximum distance (units) to navigate toward an active NPC on Extended Target (XTarget).')
            end
        end

        -- Puller Waypoint Patrol Section
        ImGui.Dummy(0, 4)
        accent(GOLD, 'Puller Waypoint Patrol')
        local useWp = ImGui.Checkbox('Enable Waypoint Patrol##useWaypoints', ctrl.use_waypoints == true)
        if useWp ~= ctrl.use_waypoints then
            ctrl.use_waypoints = useWp
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            clearMapRadiusVisuals()
            saveLoadout(true)
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
                saveLoadout(true)
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
                saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                'NPC search radius in units around your character to look for mobs while patrolling waypoints.')
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
                            local dirStr = ((ctrl.waypoint_direction or 1) == -1) and '<<' or '>>'
                            accent(GOOD, dirStr .. ' NEXT')
                        else
                            ImGui.Text('')
                        end

                        ImGui.TableNextColumn()
                        if ImGui.Button(string.format('Set##wpSet_%d', idx)) then
                            ctrl.current_waypoint_idx = idx
                            if idx == #wps and #wps > 1 then
                                ctrl.waypoint_direction = -1
                            elseif idx == 1 then
                                ctrl.waypoint_direction = 1
                            end
                            saveLoadout(true)
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
        ImGui.Dummy(0, 4)
        ImGui.Separator()
        ImGui.Dummy(0, 4)
        accent(GOLD, 'Puller Target Filters')

        accent(GOLD, 'Target Faction Considerations')
        accent(MUTED, 'Select which NPC faction considerations Puller is allowed to auto-target.')
        ImGui.Dummy(0, 2)

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
            for _, conName in ipairs(PULL_CON_LIST) do ctrl.pull_con_filter[conName] = true end
            saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Hostile Only##pullConHostileBtn') then
            for _, conName in ipairs(PULL_CON_LIST) do
                ctrl.pull_con_filter[conName] = (conName == 'Scowling' or conName == 'Threateningly' or conName == 'Dubious' or conName == 'Apprehensive')
            end
            saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Hostile + Indifferent##pullConHostileIndiffBtn') then
            for _, conName in ipairs(PULL_CON_LIST) do
                ctrl.pull_con_filter[conName] = (conName == 'Scowling' or conName == 'Threateningly' or conName == 'Dubious' or conName == 'Apprehensive' or conName == 'Indifferent')
            end
            saveLoadout(true)
        end
        ImGui.SameLine()
        if ImGui.Button('Clear All##pullConClearBtn') then
            for _, conName in ipairs(PULL_CON_LIST) do ctrl.pull_con_filter[conName] = false end
            saveLoadout(true)
        end

        ImGui.Dummy(0, 4)

        local tableFlags = bit.bor(ImGuiTableFlags.BordersOuter, ImGuiTableFlags.SizingFixedSame)
        if ImGui.BeginTable('PullConTable', 3, tableFlags) then
            for idx, conName in ipairs(PULL_CON_LIST) do
                if (idx - 1) % 3 == 0 then
                    ImGui.TableNextRow()
                end
                ImGui.TableSetColumnIndex((idx - 1) % 3)

                local curState = ctrl.pull_con_filter[conName] == true
                local newState, changed = ImGui.Checkbox(conName .. '##pullCon_' .. conName, curState)
                if changed then
                    ctrl.pull_con_filter[conName] = newState
                    saveLoadout(true)
                end
            end
            ImGui.EndTable()
        end

        ImGui.Dummy(0, 6)

        accent(GOLD, 'NPCs to Pull (Include List)')
        accent(MUTED, 'If empty, pulls any mob in radius. If populated, ONLY pulls listed names.')
        ImGui.Dummy(0, 2)

        if ImGui.Button('Pull Current Target##pullCurTgt', 170, 24) then
            local nm
            pcall(function() nm = mq.TLO.Target.CleanName() end)
            if nm and nm ~= '' then
                addPull(nm)
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
                addPull(runtime.pullInput); runtime.pullInput = ''
            end
        end

        ImGui.Dummy(0, 2)
        if ImGui.BeginChild('pullListFrame', 0, 90, true) then
            if not runtime.pullList or #runtime.pullList == 0 then
                ImGui.TextDisabled('(all mobs allowed)')
            else
                for i, nm in ipairs(runtime.pullList) do
                    ImGui.PushID('pl_' .. i)
                    if ImGui.Button('x') then removePull(nm) end
                    ImGui.SameLine(); ImGui.Text(tostring(nm))
                    ImGui.PopID()
                end
            end
        end
        ImGui.EndChild()

        ImGui.Dummy(0, 4)
        accent(GOLD, 'NPCs to Ignore (Ignore List)')
        accent(MUTED, 'Puller will NEVER auto-target these names (shared across all characters).')
        ImGui.Dummy(0, 2)

        if ImGui.Button('Ignore Current Target##ignoreCurTgt', 170, 24) then
            local nm
            pcall(function() nm = mq.TLO.Target.CleanName() end)
            if nm and nm ~= '' then
                if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
                addIgnore(nm)
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
                addIgnore(runtime.ignoreInput); runtime.ignoreInput = ''
            end
        end

        ImGui.Dummy(0, 2)
        if ImGui.BeginChild('ignoreListFrame', 0, 90, true) then
            if not runtime.ignoreList or #runtime.ignoreList == 0 then
                ImGui.TextDisabled('(none ignored)')
            else
                for i, nm in ipairs(runtime.ignoreList) do
                    ImGui.PushID('ig_' .. i)
                    if ImGui.Button('x') then removeIgnore(nm) end
                    ImGui.SameLine(); ImGui.Text(tostring(nm))
                    ImGui.PopID()
                end
            end
        end
        ImGui.EndChild()
    end

    -- Assist Mode Contextual Controls
    if ctrl.mode == 'Assist' then
        accent(GOLD, 'Main Assist Settings')
        ImGui.SetNextItemWidth(160)
        ctrl.ma_name = ImGui.InputText('MA Name', ctrl.ma_name or '')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Character to assist. Leave blank to assist group leader.') end
        ImGui.SetNextItemWidth(160)
        ctrl.assist_at = ImGui.SliderInt('Assist At %', ctrl.assist_at or 98, 1, 100, '%d%%')

        if ctrl.submode == 'Chase' then
            ctrl.chase = ImGui.Checkbox('Chase MA', ctrl.chase)
            if ctrl.chase then
                ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                ctrl.chase_dist = ImGui.SliderInt('Chase Range', ctrl.chase_dist or 15, 5, 100)
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
            ImGui.SameLine()
            if ImGui.Button('Clear Camp##assistCampClear') then
                ctrl.camp_loc = nil
            end
        elseif ctrl.submode == 'Backline' then
            accent(MUTED, 'Backline stays in position and assists MA with ranged/spells without moving to melee.')
        end
    end

    ImGui.EndTabItem()
end

function UI.drawSettingsTab()
    if not ImGui.BeginTabItem('Settings') then return end
    ImGui.Dummy(0, 4)

    accent(GOLD, 'Combat Style')
    if ImGui.RadioButton('Melee', ctrl.combat_style == 'Melee') then
        ctrl.combat_style = 'Melee'
        saveLoadout(true)
    end
    ImGui.SameLine()
    if ImGui.RadioButton('Ranged (bow)', ctrl.combat_style == 'Ranged') then
        ctrl.combat_style = 'Ranged'
        saveLoadout(true)
    end
    ImGui.SameLine()
    if ImGui.RadioButton('Spell', ctrl.combat_style == 'Spell') then
        ctrl.combat_style = 'Spell'
        saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Spell: stand off at the range below and never auto-attack (no\n'
            .. '/attack, no /autofire) -- your Spell Gems loadout does all the\n'
            .. 'damage. For pure caster trios that don\'t melee or carry a bow.')
    end

    ImGui.Dummy(0, 2)
    if ctrl.combat_style == 'Melee' then
        ImGui.SetNextItemWidth(200)
        local newDist, changed = ImGui.SliderInt('Melee Distance##meleeRangeSlider', ctrl.melee_dist or 14, 5, 50)
        if changed or (newDist and newDist ~= ctrl.melee_dist) then
            ctrl.melee_dist = newDist
            saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Max melee distance to position at and strike targets (default: 14).\n'
                .. 'Adjust to stick tighter (e.g. 8-10) or fight from further away (e.g. 15-25).')
        end
    else
        ImGui.SetNextItemWidth(200)
        local newDist, changed = ImGui.SliderInt('Combat Distance##rangedRangeSlider', ctrl.ranged_dist or 40, 15, 200)
        if changed or (newDist and newDist ~= ctrl.ranged_dist) then
            ctrl.ranged_dist = newDist
            saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Distance to position at and engage targets from with ranged/spells (default: 40).')
        end
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Navigation')
    ctrl.nav_fallback_stick = ImGui.Checkbox('Fallback to Stick on Nav Failure', ctrl.nav_fallback_stick)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'If MQ2Nav reports no path to a target, /stick will still\n'
            .. 'try to close on it in a straight line -- which walks\n'
            .. 'straight at whatever wall is blocking the path.\n'
            .. 'Off by default: unreachable targets are dropped instead.')
    end
    ctrl.debug_mode = ImGui.Checkbox('Debug Mode', ctrl.debug_mode)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Prints extra diagnostic lines (e.g. Hunter\'s full targeting\n'
            .. 'state every few seconds) to help track down a stuck/frozen\n'
            .. 'report. Off by default -- noisy for normal use.')
    end
    ctrl.show_map_radius = ImGui.Checkbox('Show Map Radius Circles', ctrl.show_map_radius)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Draws green radius circles on the in-game map window\n'
            .. 'for Hunter, Anchor, and Pull/Camp radii.')
    end
    ctrl.compact = ImGui.Checkbox('Compact Mini-Window HUD Mode', ctrl.compact or false)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Switches the Triune AutoCombat interface into a small, sleek HUD overlay widget.')
    end
    ctrl.buff_on_start = ImGui.Checkbox('Buff Up Between Fights', ctrl.buff_on_start ~= false)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Puts self "missing buff" / always spells and AAs up when you hit\n'
            .. 'Start, and again each time a fight ends, before the next pull.\n'
            .. 'Never runs while paused or mid-combat. Drops on aggro, and\n'
            .. 'times out after 25 seconds so a blocked buff cannot stall you.')
    end
    ctrl.buff_in_combat = ImGui.Checkbox('Refresh Buffs In Combat', ctrl.buff_in_combat or false)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Off by default: a self "missing buff" gem is held until the fight\n'
            .. 'ends, instead of spending cast time re-buffing mid-swing.\n'
            .. 'Target debuffs and "always" entries always fire normally.')
    end
    ctrl.buff_instant_in_combat = ImGui.Checkbox('Allow Instant Buffs In Combat',
        ctrl.buff_instant_in_combat ~= false)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'On by default: a self buff with no cast time is exempt from the\n'
            .. 'hold above and fires mid-fight. An instant costs no cast time\n'
            .. 'and does not interrupt melee, so there is nothing to save by\n'
            .. 'waiting. Applies to both gems and AAs; AAs whose cast time\n'
            .. 'cannot be read are treated as instant.')
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Spell Failures & Lockout')
    ImGui.SetNextItemWidth(140)
    local retriesVal = ImGui.SliderInt('Max Retries##cmr', ctrl.cast_max_retries or 2, 1, 10)
    ctrl.cast_max_retries = retriesVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Consecutive failed cast attempts allowed before temporarily locking out a spell.\nDefault: 2 tries.')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(140)
    local lockoutVal = ImGui.SliderInt('Lockout Time (s)##castLockoutSec', ctrl.cast_lockout_sec or 30, 5, 300, '%d s')
    ctrl.cast_lockout_sec = lockoutVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('How many seconds to wait before trying a locked-out spell again.\nDefault: 30 seconds.')
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Health & Mana Management')
    ImGui.SetNextItemWidth(180)
    local minManaVal = ImGui.SliderInt('Min Mana %##mmp', ctrl.min_mana_pct or 0, 0, 95, '%d%%')
    ctrl.min_mana_pct = minManaVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Prevents automatic spell casting if current mana drops below this percentage.\n'
            .. 'Ignored during Burn Mode (0 = disabled / cast at any mana level).')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(180)
    local minPullHpVal = ImGui.SliderInt('Min Pull HP %##minPullHpSettings', ctrl.pull_min_hp_pct or 0, 0, 95, '%d%%')
    ctrl.pull_min_hp_pct = minPullHpVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s',
            'Pauses pulling and sits out of combat to recover if current HP drops below\n'
            .. 'this threshold. Pulling resumes once HP reaches 100%.\n'
            .. 'Automatically stands to fight if attacked (0 = disabled / pull at any HP).')
    end

    ImGui.Dummy(0, 4)
    -- Pet Settings: shown when the trio has a pet class or active pet
    if trioHasPetClass() or hasActivePet() then
        accent(ARC, 'Pet Settings')
        ImGui.SetNextItemWidth(180)
        local petAssistVal = ImGui.SliderInt('Pet Assist At %##pa', ctrl.pet_assist_at or 100, 1, 100, '%d%%')
        ctrl.pet_assist_at = petAssistVal
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Send pets to attack once the target drops to or below\n'
                .. 'this HP threshold AND the player has started hitting the mob.\n'
                .. '100 percent = send as soon as the first hit connects (default).')
        end
        ctrl.pet_hold_enabled = ImGui.Checkbox('Enable Pet Hold', ctrl.pet_hold_enabled ~= false)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Hold pets via "#petcmd hold all" whenever out of combat\n'
                .. 'or prior to reaching the Pet Assist At HP threshold,\n'
                .. 'releasing them to attack once threshold is met.')
        end
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Med Break')
    ctrl.medbreak_enabled = ImGui.Checkbox('Enable Med Break', ctrl.medbreak_enabled)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Stops everything and sits to recover once any enabled\n'
            .. 'resource below drops to its "at" threshold; resumes once ALL enabled\n'
            .. 'resources have recovered up to their "until" threshold.')
    end
    if ctrl.medbreak_enabled then
        ctrl.medbreak_hp_on = ImGui.Checkbox('HP##mbhp', ctrl.medbreak_hp_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbHpStart = ImGui.SliderInt('##mbhpstart', ctrl.medbreak_hp_start or 20, 0, 100, '%d%%')
        ctrl.medbreak_hp_start = mbHpStart
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbHpStop = ImGui.SliderInt('##mbhpstop', ctrl.medbreak_hp_stop or 90, 0, 100, '%d%%')
        ctrl.medbreak_hp_stop = mbHpStop

        ctrl.medbreak_mana_on = ImGui.Checkbox('Mana##mbmana', ctrl.medbreak_mana_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbManaStart = ImGui.SliderInt('##mbmanastart', ctrl.medbreak_mana_start or 20, 0, 100, '%d%%')
        ctrl.medbreak_mana_start = mbManaStart
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbManaStop        = ImGui.SliderInt('##mbmanastop', ctrl.medbreak_mana_stop or 90, 0, 100, '%d%%')
        ctrl.medbreak_mana_stop = mbManaStop

        ctrl.medbreak_end_on    = ImGui.Checkbox('Endurance##mbend', ctrl.medbreak_end_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbEndStart = ImGui.SliderInt('##mbendstart', ctrl.medbreak_end_start or 20, 0, 100, '%d%%')
        ctrl.medbreak_end_start = mbEndStart
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        local mbEndStop = ImGui.SliderInt('##mbendstop', ctrl.medbreak_end_stop or 90, 0, 100, '%d%%')
        ctrl.medbreak_end_stop = mbEndStop
    end

    ImGui.EndTabItem()
end

local function drawMiniGui()
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
        local curPrimaryIdx = idxOf(PRIMARY_MODES, ctrl.mode)
        local newPrimaryIdx = ImGui.Combo('##miniPrimaryCombo', curPrimaryIdx, PRIMARY_MODES)
        if newPrimaryIdx ~= curPrimaryIdx then
            local newPrimaryMode = PRIMARY_MODES[newPrimaryIdx]
            if ctrl.mode == 'Manual' and newPrimaryMode ~= 'Manual' then
                setManualHunterPetHold(false)
            elseif newPrimaryMode == 'Manual' then
                if not ctrl.running or not isCombat() then
                    setManualHunterPetHold(true, true)
                end
            end
            ctrl.mode = newPrimaryMode
            if SUBMODES[ctrl.mode] then
                ctrl.submode = SUBMODES[ctrl.mode][1]
            else
                ctrl.submode = 'Hunt'
            end
            clearMapRadiusVisuals()
            saveLoadout(true)
        end

        if SUBMODES[ctrl.mode] then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(90)
            local subList = SUBMODES[ctrl.mode]
            local curSubIdx = idxOf(subList, ctrl.submode)
            local newSubIdx = ImGui.Combo('##miniSubCombo', curSubIdx, subList)
            if newSubIdx ~= curSubIdx then
                ctrl.submode = subList[newSubIdx]
                clearMapRadiusVisuals()
                saveLoadout(true)
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Full Window##miniFull', 95, 22) then
            ctrl.compact = false
            saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Expand back to full tabbed Triune AutoCombat window')
        end

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- Row 2: Action Controls Toolbar (Run/Pause, Burn, Camp)
        if ctrl.running then
            if ImGui.Button('Pause##miniRunBtn', 65, 22) then
                if ctrl.mode == 'Manual' then
                    setManualHunterPetHold(true, true)
                else
                    setManualHunterPetHold(false, true)
                end
                ctrl.running = false
                fullStop()
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
                beginStartBuffPass()
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

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

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
        if ImGui.Button('Cursor##miniCursor', 55, 22) then
            toggleTool('triune_cursor')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or closes standalone Cursor Manager') end

        ImGui.SameLine()
        if ImGui.Button('DPS##miniDPS', 42, 22) then
            toggleTool('triune_dps', '/dps toggle')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or toggles standalone DPS Parser window') end

        ImGui.SameLine()
        if ImGui.Button('Update##miniUpdate', 58, 22) then
            toggleTool('triune_updater')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or closes Release Updater window') end

        ImGui.SameLine()
        if ImGui.Button('Tracker##miniTrack', 60, 22) then
            toggleTool('triune_track')
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Launches or closes Zone Tracker window') end
    end

    ImGui.End()
    UI.popTheme()
end

local function drawFullGui()
    if not open or ctrl.compact then return end
    UI.pushTheme()
    ImGui.SetNextWindowSize(720, 640, ImGuiCond.FirstUseEver)
    local show
    open, show = ImGui.Begin('Triune AutoCombat##triune', open)
    if not show then
        ImGui.End(); UI.popTheme(); return
    end

    UI.drawHeaderBar()
    UI.drawClassPicker()

    if ImGui.BeginTabBar('triuneTabs') then
        UI.drawControlTab()
        UI.drawSettingsTab()
        UI.drawGemTab()
        UI.drawClickieTab()
        UI.drawAATab()
        UI.drawDiscTab()
        UI.drawHelpTab()
        ImGui.EndTabBar()
    end

    ImGui.End()
    UI.popTheme()
end

local function draw()
    if not open then return end
    if ctrl.compact then
        drawMiniGui()
    else
        drawFullGui()
    end
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


local function setTarget(id)
    if not id or id == 0 then return false end
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

-- Buff-bar detection. The icon on your buff/song bar is the ground truth for
-- "do I have this", and it is the only thing that reads correctly for the cases
-- that cause repeat casts: bard persist songs (which sit on the bar with a
-- null/0 duration once they lock, so any duration-based check calls them
-- missing) and self buffs that Buff("name") simply fails to see on some builds.
-- Scraped from the buff windows as well as the TLOs, because index enumeration
-- can come back empty while the icons are plainly there.
--
-- Nested so the locals do not count against the Lua 5.1 200-local main-chunk
-- limit, which this file is close to.
(function()
    local barNameCache, barNameCacheAt = nil, 0

    local function spellNamesEqual(a, b)
        a, b = tostring(a or ''), tostring(b or '')
        if a == '' or b == '' then return false end
        if a == b then return true end
        if cleanSpellName(a):lower() == cleanSpellName(b):lower() then return true end
        return normalizeSpellName(a) == normalizeSpellName(b)
    end

    local function tloEffectPresent(tlo)
        local present = false
        pcall(function()
            if not tlo then return end
            local n = tlo.Name()
            if n and n ~= '' and n ~= 'NULL' then
                present = true
                return
            end
            local id = tonumber(tlo.ID() or 0) or 0
            if id > 0 then present = true end
        end)
        return present
    end

    local function selfHasWindowEffect(windowName, name)
        local byName = false
        pcall(function() byName = tloEffectPresent(mq.TLO.Me[windowName](name)) end)
        if byName then return true end
        local wantId = 0
        pcall(function() wantId = tonumber(mq.TLO.Spell(name).ID() or 0) or 0 end)
        local maxSlot = (windowName == 'Song') and 30 or 42
        for i = 1, maxSlot do
            local slotName, slotId = nil, 0
            pcall(function()
                local slot = mq.TLO.Me[windowName](i)
                slotName = slot.Name()
                slotId = tonumber(slot.SpellID() or slot.ID() or 0) or 0
            end)
            if slotName and spellNamesEqual(slotName, name) then return true end
            if wantId > 0 and slotId == wantId then return true end
        end
        return false
    end

    local function addBarName(into, n, source)
        n = tostring(n or '')
        if n == '' or n == 'NULL' then return end
        local first = n:match('^[^\r\n]+') or n
        first = first:gsub('%s+$', '')
        if first == '' then return end
        into.raw[#into.raw + 1] = first
        into.src[first:lower()] = into.src[first:lower()] or source
        into.set[first] = true
        into.set[first:lower()] = true
        into.set[cleanSpellName(first):lower()] = true
        into.set[normalizeSpellName(first)] = true
    end

    -- There are two places an effect can live: the buff window (labelled
    -- "Effects") and the short-duration window (labelled "Songs"). Bard songs
    -- and several short self buffs only ever appear in the second one, so
    -- checking the first alone reports them missing. Both are read here, by TLO
    -- index and by scraping the window icons, because neither route is complete
    -- on its own -- BuffCount has been seen reporting more slots than it will
    -- return names for.
    local function gatherSelfBarEffects(force)
        local now = os.clock()
        if not force and barNameCache and (now - barNameCacheAt) < 0.45 then
            return barNameCache
        end
        local into = { raw = {}, set = {}, src = {}, effects = {}, songs = {} }
        for i = 1, 42 do
            pcall(function()
                local n = mq.TLO.Me.Buff(i).Name()
                if n and n ~= '' and n ~= 'NULL' then
                    into.effects[#into.effects + 1] = n
                    addBarName(into, n, 'Effects')
                end
            end)
        end
        for i = 1, 30 do
            pcall(function()
                local n = mq.TLO.Me.Song(i).Name()
                if n and n ~= '' and n ~= 'NULL' then
                    into.songs[#into.songs + 1] = n
                    addBarName(into, n, 'Songs')
                end
            end)
        end
        local winSpecs = {
            { 'BuffWindow',              'Effects', { 'Buff%d', 'BW_Buff%d_Button' } },
            { 'ShortDurationBuffWindow', 'Songs',   { 'Buff%d', 'SDBW_Buff%d_Button', 'SDB_Buff%d' } },
        }
        for _, spec in ipairs(winSpecs) do
            for _, fmt in ipairs(spec[3]) do
                for i = 0, 41 do
                    pcall(function()
                        local c = mq.TLO.Window(spec[1]).Child(string.format(fmt, i))
                        if c and c() then
                            addBarName(into, c.Tooltip(), spec[2])
                            addBarName(into, c.Text(), spec[2])
                        end
                    end)
                end
            end
        end
        barNameCache, barNameCacheAt = into, now
        return into
    end

    local function selfBarHasSpell(name)
        name = tostring(name or '')
        if name == '' then return false end
        local bar = gatherSelfBarEffects()
        if bar.set[name] or bar.set[name:lower()] then return true end
        if bar.set[cleanSpellName(name):lower()] or bar.set[normalizeSpellName(name)] then return true end
        local needle = cleanSpellName(name):lower()
        if needle == '' then return false end
        for _, raw in ipairs(bar.raw) do
            if tostring(raw):lower():find(needle, 1, true) then return true end
        end
        return false
    end

    runtime.tloEffectPresent = tloEffectPresent
    runtime.selfHasWindowEffect = selfHasWindowEffect
    runtime.selfBarHasSpell = selfBarHasSpell
    runtime.invalidateBarCache = function() barNameCache = nil end

    -- Prints both windows and the UP/MISSING verdict for every self buff entry
    -- in the loadout, so a buff that is plainly on screen but keeps getting
    -- re-cast can be traced to which window it is in and which probe missed it.
    runtime.dumpSelfBar = function()
        local bar = gatherSelfBarEffects(true)
        local nBuff, nSong = -1, -1
        pcall(function() nBuff = mq.TLO.Me.CountBuffs() or -1 end)
        pcall(function() nSong = mq.TLO.Me.CountSongs() or -1 end)
        print(string.format('\ag[Triune bar]\ax Effects (CountBuffs=%d): %s', nBuff,
            (#bar.effects > 0) and table.concat(bar.effects, ', ') or '(none)'))
        print(string.format('\ag[Triune bar]\ax Songs (CountSongs=%d): %s', nSong,
            (#bar.songs > 0) and table.concat(bar.songs, ', ') or '(none)'))

        local myId = mq.TLO.Me.ID() or 0
        local seen = {}
        local function report(name, isAA)
            if not name or name == '' or seen[name] then return end
            seen[name] = true
            local up = runtime.buffFactuallyUp(myId, name)
            local ms = runtime.castTimeMs(name, isAA)
            local timing
            if ms == nil then
                timing = runtime.isInstantCast(name, isAA) and 'instant?' or 'unknown'
            elseif ms <= 0 then
                timing = 'instant'
            else
                timing = string.format('%.1fs', ms / 1000)
            end
            print(string.format('  %s %s [%s] -- %s%s',
                up and '\ag[UP]\ax' or '\ay[MISSING]\ax', name, timing,
                up and 'will not recast' or 'will cast',
                bar.src[name:lower()] and (' (found in ' .. bar.src[name:lower()] .. ')') or ''))
        end
        -- Only entries the engine would actually act on. Listing a disabled or
        -- non-self entry alongside "will cast" reads as a bug report when it is
        -- simply switched off, and a pet/group buff checked against your own
        -- bar would give the wrong verdict anyway.
        local function selfMissingBuff(when, target)
            if when ~= 'missing buff' then return false end
            local tok = baseTok(target)
            return tok == 'Myself' or tok == 'Self'
        end
        print('\ag[Triune bar]\ax enabled self buff entries:')
        for i = 1, NUM_GEMS do
            local g = loadout.gems[i]
            if g and selfMissingBuff(g.when, g.target) then
                local pctVal = tonumber(g.pct)
                if pctVal == nil then pctVal = 100 end
                if pctVal > 0 then report(g.spell, false) end
            end
        end
        for name, a in pairs(loadout.aas) do
            if a and a.enabled and selfMissingBuff(a.when, a.target) then
                local aPct = tonumber(a.pct)
                if aPct == nil then aPct = 30 end
                if aPct > 0 then report(name, true) end
            end
        end
    end

    -- Bard persist songs sit on the song/buff bar after a single apply and never
    -- need re-singing. Buff-window presence means the persist already locked,
    -- even with Duration 0. Song-window presence while THAT song is the current
    -- cast is just the cast in flight, not a lock, so it only counts once we are
    -- no longer singing it.
    runtime.persistSongOnBar = function(name)
        name = tostring(name or '')
        if name == '' then return false end
        if selfHasWindowEffect('Buff', name) then return true end
        if not selfHasWindowEffect('Song', name) then return false end
        local singing = ''
        pcall(function() singing = mq.TLO.Me.Casting.Name() or '' end)
        if singing == '' then return true end
        return not spellNamesEqual(singing, name)
    end

    -- Authoritative "is this effect up". Use this for every missing-buff
    -- decision; buffActive alone produces false negatives on self.
    -- Cast time in milliseconds, or nil when the build will not tell us.
    -- Cached: a spell's cast time never changes, and this is consulted on every
    -- combat tick for every buff entry.
    local castTimeCache = {}
    runtime.castTimeMs = function(name, isAA)
        name = tostring(name or '')
        if name == '' then return nil end
        local cacheKey = (isAA and 'a:' or 's:') .. name
        local hit = castTimeCache[cacheKey]
        if hit ~= nil then
            if hit == false then return nil end
            return hit
        end
        local ms = nil
        pcall(function()
            local sp
            if isAA then
                local aa = mq.TLO.Me.AltAbility(name)
                if aa and aa() then sp = aa.Spell end
            else
                sp = mq.TLO.Spell(name)
            end
            if sp and sp() then
                local v = tonumber(sp.CastTime())
                if v then ms = v end
            end
        end)
        castTimeCache[cacheKey] = (ms == nil) and false or ms
        return ms
    end

    -- An instant buff costs no cast time and does not interrupt melee, so
    -- holding it until the fight ends buys nothing. AAs whose cast time cannot
    -- be read are treated as instant: activated AAs overwhelmingly are, and
    -- AltAbilityReady already gates them. An unreadable spell is not, since a
    -- long self buff mid-fight is exactly what the hold exists to prevent.
    runtime.isInstantCast = function(name, isAA)
        local ms = runtime.castTimeMs(name, isAA)
        if ms == nil then return isAA and true or false end
        return ms <= 0
    end

    runtime.buffFactuallyUp = function(id, name)
        name = tostring(name or '')
        if not id or id == 0 or name == '' then return false end
        local myId = 0
        pcall(function() myId = mq.TLO.Me.ID() or 0 end)
        if id == myId then
            if selfBarHasSpell(name) then return true end
            return selfHasWindowEffect('Buff', name) or selfHasWindowEffect('Song', name)
        end
        return buffActive(id, name)
    end
end)()

-- Name-based "Buff(name)" lookups have already proven unreliable on this MQ
-- build twice this session (CombatAbility(name) for discs, Target.Target for
-- assist) -- the proven, reliable pattern instead is numeric indexing +
-- comparing .Name() directly, matching the scanKnownDiscs() fix. This is what
-- was letting Paladin buffs "keep trying to buff even though I have it": a
-- false negative from Buff(name) reads as "missing" and re-fires forever.
local function hasNamedBuff(spawnObj, name, isMe)
    -- Index enumeration (Buff(i)/MyBuff(i) up to BuffCount/MyBuffCount) read
    -- as EMPTY for the character's own buffs on this build no matter which
    -- member set was used -- confirmed live: MyBuffCount=0, active=[] on
    -- every check for buffs that were demonstrably up. The direct BY-NAME
    -- lookup (Buff("name")/Song("name")) doesn't depend on that count/array
    -- being populated the same way, so it works where enumeration doesn't.
    -- Try the name lookup FIRST and trust it; only fall back to enumeration
    -- if that produced nothing.
    name = tostring(name or '')
    if name == '' or not spawnObj() then return false end

    local found = false
    pcall(function()
        if runtime.tloEffectPresent(spawnObj.Buff(name)) then found = true end
    end)
    if not found and isMe then
        pcall(function()
            if runtime.tloEffectPresent(spawnObj.Song(name)) then found = true end
        end)
        if not found then
            found = runtime.selfHasWindowEffect('Buff', name) or runtime.selfHasWindowEffect('Song', name)
        end
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
        -- Also show what the direct name lookup returned, so we can tell
        -- "genuinely not up" from "detection still can't see it."
        local directName = 'nil'
        pcall(function()
            local b = spawnObj.Buff(name)(); if b then directName = tostring(b) end
        end)
        -- Collect active buff names for display
        local activeNames = {}
        for i = 1, cnt do
            local b = spawnObj.Buff(i)
            if b() then activeNames[#activeNames + 1] = b.Name() or '?' end
        end
        -- The Songs window is the other half of the answer and was missing from
        -- this line, which made every short self buff look like it was simply
        -- not up anywhere.
        local songNames = {}
        if isMe then
            for i = 1, 30 do
                pcall(function()
                    local n = mq.TLO.Me.Song(i).Name()
                    if n and n ~= '' and n ~= 'NULL' then songNames[#songNames + 1] = n end
                end)
            end
        end
        print('\ao[Triune debug]\ax looking for buff "' ..
            tostring(name) .. '" -- ' .. (isMe and 'MyBuffCount' or 'BuffCount') .. '=' .. cnt
            ..
            ' Effects=[' ..
            table.concat(activeNames, ', ') ..
            '] Songs=[' .. table.concat(songNames, ', ') ..
            '] Buff("name")=' .. directName)
    end
    return found
end
buffActive = function(id, name)
    if not id or id == 0 then return false end
    if id == mq.TLO.Me.ID() then
        if hasNamedBuff(mq.TLO.Me, name, true) then return true end
        if tloTrue(function() return mq.TLO.Me.Song(name)() end) then return true end
        return false
    end
    local total = 0
    pcall(function() total = mq.TLO.Group.Members() or 0 end)
    for i = 0, total do
        local m = nil
        pcall(function() m = mq.TLO.Group.Member(i) end)
        if m and m() and (m.ID() or 0) == id then
            if hasNamedBuff(m, name) then return true end
            if tloTrue(function() return m.Song(name)() end) then return true end ---@diagnostic disable-line: undefined-field
            return false
        end
    end
    -- Pets were completely uncovered here -- neither Me, Group.Member, nor
    -- Target matches a pet's id, so this fell straight through to "false"
    -- (always reads as missing) for ANY pet-targeted buff, causing it to be
    -- re-cast every eligible tick forever. Checked against any of our
    -- tracked pets (not just the current Me.Pet slot), since this server can
    -- have several simultaneous pets at once.
    for _, petId in pairs(petState.myPets) do
        if petId == id then
            local s = mq.TLO.Spawn(id)
            return s() and hasNamedBuff(s, name)
        end
    end
    if mq.TLO.Target.ID() == id then
        return hasNamedBuff(mq.TLO.Target, name)
    end
    local s = mq.TLO.Spawn(id)
    if s and s() then
        return hasNamedBuff(s, name)
    end
    return false
end

local function lowestHpAlly()
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

local isUnreachable -- forward declaration; defined in the pursuit section below

local function firstNPCXtarget(unmezzedOnly, maxZ)
    return findFirstNPCXtarget(unmezzedOnly, isIgnored, isUnreachable, nil, maxZ)
end

-- Returns count of live, non-ignored NPCs occupying XTarget slots.
local function countNPCXtarget(includeUnreachable)
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
local function anyXtarAlive(includeUnreachable)
    return countNPCXtarget(includeUnreachable) > 0
end

isXTargetId = function(id)
    if not id or id <= 0 then return false end
    if isGroupOrRaidMember(id) or isSpawnPetOrPlayer(id) then return false end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) == id
            and not xt.Dead() and (xt.Type() or '') ~= 'Corpse'
            and not isIgnored(xt.CleanName())
            and not isUnreachable(id) then
            local stype = xt.Type() or ''
            if (stype == 'NPC' or stype == 'Pet') and isHostileTarget(id) then
                return true
            end
        end
    end
    return false
end

-- Returns true if an action (spell, AA, disc, skill) is detrimental (offensive).
local function isDetrimentalAction(name, targetToken, entry)
    if not name or name == '' then return false end
    targetToken = tostring(targetToken or '')

    if targetToken:sub(1, 2) == 'E:' then return true end

    local isBene = nil
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp() then isBene = sp.Beneficial() end
    end)
    if isBene == false then return true end
    if isBene == true then return false end

    pcall(function()
        local aa = mq.TLO.Me.AltAbility(name)
        if aa() then
            local sp = aa.Spell
            if sp() then isBene = sp.Beneficial() end
        end
    end)
    if isBene == false then return true end
    if isBene == true then return false end

    pcall(function()
        local ca = mq.TLO.Me.CombatAbility(name)
        if ca() then
            local sp = ca.Spell
            if sp() then isBene = sp.Beneficial() end
        end
    end)
    if isBene == false then return true end
    if isBene == true then return false end

    if entry and entry.kind then
        if entry.kind == 'dd' or entry.kind == 'dot' or entry.kind == 'debuff' then return true end
        if entry.kind == 'buff' or entry.kind == 'heal' or entry.kind == 'pet' or entry.kind == 'util' then return false end
    end

    local _, spellBene, kind = spellClassInfo(name)
    if not spellBene then return true end
    if kind == 'dd' or kind == 'dot' or kind == 'debuff' then return true end

    local lowerName = name:lower()
    if lowerName:find('kick') or lowerName:find('bash') or lowerName:find('backstab') or lowerName:find('frenzy')
        or lowerName:find('slam') or lowerName:find('strike') or lowerName:find('taunt') or lowerName:find('disarm')
        or lowerName:find('dragon punch') or lowerName:find('eagle strike') or lowerName:find('round kick') or lowerName:find('tiger claw') then
        return true
    end

    return false
end

local function isTargetInRange(name, targetId)
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
        maxRange = maxMeleeDistance(targetId)
    end

    return dist <= (maxRange + 2)
end

local function maPcId()
    return findMaPcId(ctrl and ctrl.ma_name)
end

local function targetIsEngaged(id)
    if not id or id <= 0 then return false end
    if isSpawnPetOrPlayer(id) or not isHostileTarget(id) then return false end
    if isXTargetId(id) then return true end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return false end
    if (s.PctHPs() or 100) < 100 then return true end

    -- Check if target of target is player or group member
    local totId = 0
    pcall(function() totId = s.TargetOfTarget.ID() or 0 end)
    if totId > 0 then
        if isGroupOrRaidMember(totId) or totId == (mq.TLO.Me.ID() or 0) then
            return true
        end
    end

    -- If in Assist, Manual, or Puller mode, valid NPC targets selected by engine/MA are engaged
    if ctrl and (ctrl.mode == 'Assist' or ctrl.mode == 'Manual' or ctrl.mode == 'Puller') then
        return true
    end

    return false
end

isCombat = function()
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
                if targetIsEngaged(t.ID()) or isHostileTarget(t.ID()) then return true end
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

local function anyNearbyEngagedNpc(radius)
    if anyXtarAlive() then return true end
    local filt = string.format('npc radius %d', radius or 150)
    local n = mq.TLO.SpawnCount(filt)() or 0
    for i = 1, n do
        local s = mq.TLO.NearestSpawn(i, filt)
        if s() and s.ID() > 0 and not isSpawnPetOrPlayer(s.ID()) and isHostileTarget(s.ID()) then
            if targetIsEngaged(s.ID()) then return true end
        end
    end
    return false
end

local function maTargetId()
    local maId = maPcId()
    if not maId then return nil end
    local gated = (ctrl.mode == 'Assist')
    if gated and not anyNearbyEngagedNpc(150) then
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
    if gated and not targetIsEngaged(t.ID()) then
        return nil
    end
    return t.ID()
end

resolvePetTargetId = function(when, spellName, cls, pct)
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
        for _, pid in ipairs(allPets) do
            if not runtime.sungBuffs[sungKey(spellName, pid)] and not buffActive(pid, spellName) then
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

local function resolveTargetId(token, cls, when, spellName, pct)
    local b = baseTok(token)
    local id
    if b == 'Myself' or b == 'Whole Group' then
        id = mq.TLO.Me.ID()
    elseif b == 'Main Assist' or b == 'Tank' then
        id = maPcId()
    elseif b == 'Lowest-HP Ally' then
        id = lowestHpAlly()
    elseif b == 'Pet' then
        id = resolvePetTargetId(when, spellName, cls, pct)
    elseif b == 'Current Target' then
        id = mq.TLO.Target.ID()
    elseif b == 'Assist Target' then
        id = maTargetId()
    elseif b == 'Unmezzed Add' then
        id = firstNPCXtarget(true)
    elseif b == 'Nearest Add' or b == 'All Enemies' then
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
    else
        id = mq.TLO.Target.ID()
    end
    if not id or id <= 0 then return nil end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return nil end
    local hp = 100
    pcall(function() hp = s.PctHPs() or 100 end)
    local stype = ''
    pcall(function() stype = s.Type() or '' end)
    local cname = ''
    pcall(function() cname = s.CleanName() or '' end)
    if cname ~= '' and isIgnored(cname) then return nil end
    if (stype == 'NPC' or stype == 'Pet') and (ctrl.mode == 'Assist')
        and not targetIsEngaged(id) then
        return nil
    end
    return id
end

mq.event('TriuneZone', 'You have entered #*#', function()
    runtime.sungBuffs = {}; runtime.buffTries = {}; onZoned()
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
                    local id = resolveTargetId(g.target, g.cls, g.when, g.spell, gpct)
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

local function reconcilePets()
    local petClassList = {}
    for _, c in ipairs(myClasses) do if PET_CLASSES[c] then petClassList[#petClassList + 1] = c end end
    if #petClassList == 0 then return end
    local n = 0
    pcall(function() n = mq.TLO.SpawnCount('pet radius 150')() or 0 end)
    local assigned = 0
    for i = 1, n do
        if assigned >= #petClassList then break end
        local s = mq.TLO.NearestSpawn(i, 'pet radius 150')
        if s and s() and s.ID() and isSpawnMyPet(s) then
            assigned = assigned + 1
            petState.myPets[petClassList[assigned]] = s.ID()
            petState.lastObservedId = s.ID()
        end
    end
    if assigned > 0 then
        print('\ag[Triune]\ax found ' .. assigned .. ' existing pet(s) -- tracking ' .. assigned .. ' pet(s).')
    end
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

    return false
end

local function isAnyGroupMemberAfflicted()
    local myId = 0
    pcall(function() myId = mq.TLO.Me.ID() or 0 end)
    if myId > 0 and isPoisonedOrDiseased(myId) then return true end

    local grpCount = 0
    pcall(function() grpCount = mq.TLO.Group.Members() or 0 end)
    for i = 1, grpCount do
        local mid = nil
        pcall(function()
            local m = mq.TLO.Group.Member(i)
            if m and m() and not m.Dead() then
                mid = m.ID() or 0
            end
        end)
        if mid and mid > 0 and isPoisonedOrDiseased(mid) then
            return true
        end
    end
    return false
end

local function conditionMet(when, pct, spellName, targetId, cls)
    pct = tonumber(pct) or 0
    if pct <= 0 then return false end
    if when == 'always' then return true end
    if when == 'in combat' or when == 'twist while fighting' then return isCombat() end
    if when == 'my Mana <=' then return (mq.TLO.Me.PctMana() or 100) <= pct end
    -- Lets a lifetap DD/DoT (SK/Necro) target the enemy (E: Current Target,
    -- for the drain to actually land) while triggering on the CASTER's own
    -- HP rather than the target's -- "HP <="/"target HP <=" both check
    -- whatever the entry's own Target resolves to, which can't express
    -- "attack it, but only because I need the heal."
    if when == 'my HP <=' then return pctHP(mq.TLO.Me.ID()) <= pct end
    if when == 'HP <=' or when == 'target HP <=' then return pctHP(targetId) <= pct end
    if when == 'missing buff' then
        -- The buff bar is the answer. The old "already sung this life"
        -- sungBuffs latch was a workaround for detection that could not see a
        -- bard persist song sitting on the bar with a null duration; with the
        -- bar check in place it only does harm, since it also meant a buff
        -- could never be put back up after it genuinely faded.
        return not runtime.buffFactuallyUp(targetId, spellName)
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
            for _, c in ipairs(myClasses) do if PET_CLASSES[c] then petClasses[#petClasses + 1] = c end end
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
        return isPoisonedOrDiseased(targetId)
    end
    if when == 'add is loose' then return firstNPCXtarget(true) ~= nil end
    return true
end

local function isCasting()
    local cid = nil
    pcall(function() cid = mq.TLO.Me.Casting.ID() end)
    return cid ~= nil and cid > 0
end

-- ============================================================================
-- Spell Fail-Count & Lockout System (2-try limit -> 30s lockout)
-- ============================================================================
local castTracker = createCastTracker()

local function onFailureEvent(reason)
    castTracker.onFailureEvent(reason, ctrl and ctrl.cast_max_retries or 2, ctrl and ctrl.cast_lockout_sec or 30)
end

local function onCannotSeeEvent()
    onFailureEvent('cannot see target')
    if handleCannotSeeTarget then
        handleCannotSeeTarget()
    end
end

mq.event('TriuneFizzle', '#*#fizzle#*#', function() onFailureEvent('fizzled') end)
mq.event('TriuneInterrupt', '#*#interrupted#*#', function() onFailureEvent('interrupted') end)
mq.event('TriuneOutOfRangeSpell', '#*#out of range#*#', function() onFailureEvent('out of range') end)
mq.event('TriuneCannotSee', '#*#see your target#*#', onCannotSeeEvent)
mq.event('TriuneNoTakeHold', '#*#take hold#*#', function() onFailureEvent('did not take hold') end)
-- "Your spell would not have taken hold" is the stacking refusal: something
-- stronger in the same line already occupies the slot. Worth naming separately
-- from a plain fizzle, since re-casting will never fix it.
mq.event('TriuneStackBlocked', '#*#taken hold#*#',
    function() onFailureEvent('blocked -- a stronger buff is already up') end)
mq.event('TriuneImmuneSpell', '#*#immune#*#', function() onFailureEvent('target immune') end)
mq.event('TriuneDeadTargetSpell', '#*#dead target#*#', function() onFailureEvent('dead target') end)
mq.event('TriuneCantCast', '#*#cast spells while#*#', function() onFailureEvent('cannot cast') end)
mq.event('TriuneResisted1', '#*#resisted your#*#', function() onFailureEvent('resisted') end)
mq.event('TriuneResisted2', '#*#resisted the#*#', function() onFailureEvent('resisted') end)
mq.event('TriuneNotReady', '#*#not ready#*#', function() onFailureEvent('not ready') end)
mq.event('TriuneNoMana', '#*#enough mana#*#', function() onFailureEvent('insufficient mana') end)

local function castGem(i, g, id)
    if isSitting() or isDucking() then
        mq.cmd('/stand')
        mq.delay(50)
    end
    if castTracker.isLockedOut(g.spell) then return false end
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
    if dur > 0 and buffActive(id, g.spell) then
        return false
    end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    if not selfCast and not setTarget(id) then return false end

    -- EQ redirects a beneficial spell to your TARGET'S target. Mid-fight the mob
    -- is beating on you, so self heals and buffs land on you by accident -- which
    -- is the only reason they have ever appeared to work. Out of combat that
    -- redirect resolves to nobody and the cast is wasted, and in a group it hands
    -- your emergency self heal to whoever the mob happens to be on. Target
    -- yourself explicitly so a self-cast means self.
    local selfTargeted = false
    if selfCast and orig ~= id then
        local bene = true
        pcall(function() bene = not not sp.Beneficial() end)
        if bene then
            if not setTarget(id) then return false end
            selfTargeted = true
        end
    end

    castTracker.lastSpell   = g.spell
    castTracker.lastTime    = os.clock()
    castTracker.failed      = false
    castTracker.activeSpell = g.spell
    clearCursor()
    if ctrl.debug_mode then
        print(string.format('\ao[DEBUG cast]\ax Gem %d "%s" on target #%d (dist=%.1f, Me.Combat=%s)',
            i, g.spell, id, distToId(id), tostring(mq.TLO.Me.Combat())))
    end
    if stickLoaded() and g.cls ~= 'Brd' then
        pcall(function()
            if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                mq.cmd('/stick pause')
            end
        end)
    end
    mq.cmdf('/cast "%s"', g.spell)
    runtime.lastCast[key] = os.clock()
    if g.when == 'missing pet' or g.kind == 'pet' then
        petState.lastCastCls = g.cls
    end
    if g.cls == 'Brd' then
        if sp.Beneficial() then
            -- Wait for the song to reach the bar, and do NOT /stopsong: cutting
            -- a persist song short is what stops it locking, so it never
            -- appears and is sung again on the next pass. Only mark it sung
            -- once it is actually on the bar -- marking it regardless meant a
            -- song that failed to land was never retried until zone or death.
            local waited, onBar = 0, false
            while waited < 5500 do
                mq.delay(200); waited = waited + 200
                if runtime.persistSongOnBar(g.spell) then onBar = true; break end
                if runtime.selfHasWindowEffect('Buff', g.spell) then onBar = true; break end
                if runtime.selfHasWindowEffect('Song', g.spell) and waited >= 3000 then
                    onBar = true; break
                end
            end
            if onBar then
                runtime.sungBuffs[sungKey(g.spell, id)] = true
                runtime.invalidateBarCache()
                print(string.format('\ay[Triune bard]\ax %s is on the bar.', g.spell))
            end
        else
            local castMs = 0
            pcall(function() castMs = sp.CastTime() or 0 end)
            castMs = tonumber(castMs) or 0
            if castMs <= 0 or castMs > 6000 then castMs = 2000 end
            mq.delay(castMs + 300)
            mq.cmd('/stopsong')
        end
    end
    if (not selfCast or selfTargeted) and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    -- The Start buff pass casts on yourself while a hunt target may already be
    -- selected far away. Swinging at it here makes EQ answer "too far away",
    -- which trips the reposition handler and runs off mid-buff.
    if not runtime.startBuffPass
        and (wasAttacking or (ctrl and ctrl.combat_style == 'Melee')) and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

local function fireAA(name, a, id)
    if isSitting() or isDucking() then
        mq.cmd('/stand')
    end
    local key = 'a' .. name
    if (os.clock() - (tonumber(runtime.lastCast[key]) or 0)) < 1.5 then return false end
    local aa = mq.TLO.Me.AltAbility(name)
    if not aa() then return false end
    local aaRank = tonumber(aa.Rank() or 0) or 0
    if aaRank <= 0 then return false end
    if not mq.TLO.Me.AltAbilityReady(name)() then return false end
    local ok, sp = pcall(function() return aa.Spell end)
    if ok and sp and sp() then
        local endCost = tonumber(sp.EnduranceCost() or 0) or 0
        local manaCost = tonumber(sp.Mana() or 0) or 0
        local curEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
        local curMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
        if endCost > 0 and curEnd < endCost then return false end
        if manaCost > 0 and curMana < manaCost then return false end
    end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    if not selfCast and not setTarget(id) then return false end

    -- Same redirect castGem has to work around: EQ sends a beneficial effect to
    -- your TARGET'S target, so a self buff AA fired with a hostile selected can
    -- resolve to nobody out of combat, or to whoever the mob is on in a group.
    local selfTargeted = false
    if selfCast and orig ~= id then
        local bene = true
        pcall(function() bene = not not sp.Beneficial() end)
        if bene then
            if not setTarget(id) then return false end
            selfTargeted = true
        end
    end

    clearCursor()
    mq.cmdf('/alt act %d', aa.ID())
    runtime.lastCast[key] = os.clock()
    print('\ag[Triune]\ax AA fired: ' .. name)
    if (not selfCast or selfTargeted) and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if not runtime.startBuffPass
        and (wasAttacking or (ctrl and (ctrl.combat_style or 'Melee') == 'Melee')) and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

runtime.isDiscReady = function(name)
    if not name or name == '' then return false end

    -- 1. Software timers: lockouts from previous cast duration / cooldown
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

    -- 2. Known combat ability check
    local known = false
    pcall(function()
        local ca = mq.TLO.Me.CombatAbility(name)
        if ca and ca() then known = true end
    end)
    if not known then return false end

    -- 3. MQ CombatAbilityReady check
    local readyOk, isReady = pcall(function() return mq.TLO.Me.CombatAbilityReady(name)() end)
    if readyOk and isReady == false then return false end

    -- 4. MQ CombatAbilityTimer check
    local timerOk, timerVal = pcall(function() return mq.TLO.Me.CombatAbilityTimer(name) end)
    if timerOk and timerVal then
        local sec = 0
        pcall(function()
            if type(timerVal.TotalSeconds) == 'function' then
                sec = tonumber(timerVal.TotalSeconds() or 0) or 0
            elseif type(timerVal.TotalSeconds) == 'number' then
                sec = tonumber(timerVal.TotalSeconds) or 0
            elseif timerVal() then
                local v = timerVal()
                sec = tonumber(v) or 0
            end
        end)
        if sec > 0 then return false end
    end

    -- 5. Spell info (duration, endurance cost, target type)
    local spOk, sp = pcall(function() return mq.TLO.Spell(name) end)
    local hasDuration = false
    local isSelfTarget = true
    if spOk and sp and sp() then
        local endCost = 0
        local durTicks = 0
        pcall(function()
            endCost = tonumber(sp.EnduranceCost() or 0) or 0
            durTicks = tonumber(sp.Duration() or sp.MyDuration() or 0) or 0
            local tt = sp.TargetType()
            if tt and tostring(tt):lower() ~= 'self' then isSelfTarget = false end
        end)
        local myEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
        if endCost > 0 and myEnd < endCost then
            return false
        end
        if durTicks > 0 then
            hasDuration = true
        end
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
            if hasDuration and isSelfTarget then
                return false
            end
        end
    end

    -- 7. Buff / Song check (for duration discs that land in buff or song window)
    local buffFound = false
    pcall(function()
        local b = mq.TLO.Me.Buff(name)
        if b and b() and (tonumber(b.Duration() or 0) or 0) > 0 then buffFound = true end
        if not buffFound then
            local s = mq.TLO.Me.Song(name)
            if s and s() and (tonumber(s.Duration() or 0) or 0) > 0 then buffFound = true end
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
        local sec = 0
        pcall(function()
            if type(timerVal.TotalSeconds) == 'function' then
                sec = tonumber(timerVal.TotalSeconds() or 0) or 0
            elseif type(timerVal.TotalSeconds) == 'number' then
                sec = tonumber(timerVal.TotalSeconds) or 0
            elseif timerVal() then
                local v = timerVal()
                sec = tonumber(v) or 0
            end
        end)
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
    if not selfCast and not setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/disc %s', name)

    -- Calculate duration & cooldown to lock out until the timer runs out
    local now = os.clock()
    local key = 'd' .. name
    local durSec = 0
    local recastSec = 0
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then
            local ticks = tonumber(sp.Duration() or sp.MyDuration() or 0) or 0
            if ticks > 0 then durSec = ticks * 6 end
            local rt = sp.RecastTime() or 0
            if type(rt) == 'number' or tonumber(rt) then
                local numRt = tonumber(rt) or 0
                if numRt > 1800 then recastSec = numRt / 1000 else recastSec = numRt end
            end
            if recastSec == 0 and type(sp.RecastTime) == 'userdata' then
                local ts = tonumber(sp.RecastTime.TotalSeconds() or 0) or 0
                if ts > 0 then recastSec = ts end
            end
        end
    end)

    pcall(function()
        local cat = mq.TLO.Me.CombatAbilityTimer(name)
        if cat and cat() then
            local ts = 0
            if type(cat.TotalSeconds) == 'function' then
                ts = tonumber(cat.TotalSeconds() or 0) or 0
            elseif type(cat.TotalSeconds) == 'number' then
                ts = tonumber(cat.TotalSeconds) or 0
            elseif type(cat) == 'number' or tonumber(cat) then
                ts = tonumber(cat) or 0
            end
            if ts > recastSec then recastSec = ts end
        end
    end)

    local lockSec = math.max(durSec, recastSec)
    if lockSec <= 0 then lockSec = 5.0 end

    if not runtime.discExpires then runtime.discExpires = {} end
    if not runtime.discCooldown then runtime.discCooldown = {} end

    if durSec > 0 then runtime.discExpires[name] = now + durSec end
    if recastSec > 0 then runtime.discCooldown[name] = now + recastSec end
    runtime.lastCast[key] = now + lockSec

    print('\ag[Triune]\ax discipline fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if (wasAttacking or (ctrl and (ctrl.combat_style or 'Melee') == 'Melee')) and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

runtime.fireSkill = function(name, a, id)
    if isSitting() or isDucking() then
        mq.cmd('/stand')
    end
    if not runtime.isSkillReady(name) then return false end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    local wasAttacking = mq.TLO.Me.Combat()
    if not selfCast and not setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/doability "%s"', name)

    local now = os.clock()
    local key = 's' .. name
    local cd = 5.0
    pcall(function()
        local t = mq.TLO.Me.AbilityTimer(name)
        if t and t() then
            local ts = 0
            if type(t.TotalSeconds) == 'function' then
                ts = tonumber(t.TotalSeconds() or 0) or 0
            elseif type(t.TotalSeconds) == 'number' then
                ts = tonumber(t.TotalSeconds) or 0
            elseif type(t) == 'number' or tonumber(t) then
                ts = tonumber(t) or 0
            end
            if ts > 0 then cd = ts end
        end
    end)
    runtime.lastCast[key] = now + cd

    print('\ag[Triune]\ax skill fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if (wasAttacking or (ctrl and (ctrl.combat_style or 'Melee') == 'Melee')) and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
    return true
end

runtime.useClickie = function(c, id)
    if not c or not c.name or c.name == '' then return false end
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
    if castMs > 0 and (isCasting() or isMoveActive()) then return false end

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
    if not selfCast and not setTarget(id) then return false end

    clearCursor()
    if ctrl.debug_mode then
        print(string.format('\ao[DEBUG clickie]\ax "%s" (spell="%s") on target #%d', c.name, tostring(c.spell), id))
    end
    mq.cmdf('/useitem "%s"', c.name)
    runtime.lastCast[key] = os.clock()
    print('\ag[Triune]\ax Clickie used: ' .. c.name .. (c.spell and (' (' .. c.spell .. ')') or ''))

    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    if (wasAttacking or (ctrl and (ctrl.combat_style or 'Melee') == 'Melee')) and not mq.TLO.Me.Combat() then
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
local MELEE_RANGE = 14
-- Deliberately much tighter than MELEE_RANGE -- this is ONLY the "trust
-- proximity over a flaky point-blank raycast" exception (stairs/uneven
-- terrain/prop geometry can report a false "blocked" right next to the mob),
-- not a general LoS bypass. It used to be 20, same as MELEE_RANGE -- since
-- the arrival check already requires d <= MELEE_RANGE, that made the "or
-- d <= 20" clause always true and LoS was never actually checked at all for
-- melee, so a mob just around a corner (in range by straight-line distance,
-- no LoS at all) was accepted as "arrived" and never approached further --
-- reported live as sitting at a corner saying "you cannot see your target"
-- with no correction.
local LOS_TRUST_RANGE = 8

maxMeleeDistance = function(id)
    local userDist = (ctrl and ctrl.melee_dist) or MELEE_RANGE
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

desiredRange = function(id)
    if ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee' then
        return ctrl.pull_engage_dist or 100
    end
    local style = ctrl and ctrl.combat_style or 'Melee'
    if style ~= 'Melee' then
        return ctrl.ranged_dist or 40
    end
    local userDist = (ctrl and ctrl.melee_dist) or MELEE_RANGE
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

-- Move to within `dist` of a spawn. Returns true once already in range (nothing
local PURSUIT_STALL_TIMEOUT = 8 -- give up if no closer approach for this long
local LOS_FLICKER_GRACE = 2.5   -- treat LoS as still good this long after the last true reading (stairs flicker it)

-- Spawn ids MQ2Nav has told us have no path to. Cleared after 60s in case terrain
-- state changes (a door opens, etc). findRoamTarget skips these when picking a
-- fresh target; Hunter/Puller drop their current target the moment it lands here
-- rather than continuing to sit on something they can never reach.
local function markUnreachable(id) pursuit.unreachableIds[id] = os.clock() end
isUnreachable = function(id)
    local t = pursuit.unreachableIds[id]
    if not t then return false end
    if (os.clock() - t) > 60 then
        pursuit.unreachableIds[id] = nil; return false
    end
    return true
end

-- Raw 3D distance says nothing about walls/doors between you and the target --
-- being "within range" through a wall is not being in range at all. Without this,
-- moveToward would call itself "arrived" right at a doorway (in range by straight-
-- line distance, blocked by geometry) and stop navigating, while the engage logic
-- above tried to melee/shoot through the wall. Fails open (true) if the LoS TLO
-- itself errors, so a broken check can't wedge movement forever.


local function moveToward(id, dist, followOnly)
    if not id or id <= 0 then return false end
    local d = distToId(id)
    local maxNav = (ctrl and ctrl.xtar_nav_dist) or 150
    if isXTargetId(id) and d > maxNav then
        stopMoving()
        return false
    end

    local isMelee = (not followOnly and (ctrl and ctrl.combat_style or 'Melee') == 'Melee')
    local targetDist = dist or (isMelee and desiredRange(id) or 18)
    local effectiveArrivalDist = targetDist + (isMelee and 2 or 3)

    -- Update pursuit tracking for stall detection
    if pursuit.id ~= id then
        pursuit.id = id; pursuit.bestDist = d; pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0; pursuit.wasNavActive = false
        pursuit.lastLoSAt = 0
    elseif d < pursuit.bestDist - 2 then
        pursuit.bestDist = d; pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0
    end

    local losNow = hasLoS(id)
    if losNow then pursuit.lastLoSAt = os.clock() end
    local losOk = losNow or (pursuit.lastLoSAt > 0 and (os.clock() - pursuit.lastLoSAt) < LOS_FLICKER_GRACE)

    if d <= effectiveArrivalDist and (losOk or d <= LOS_TRUST_RANGE) then
        stopMoving()
        if not followOnly then
            if mq.TLO.Target.ID() ~= id then setTarget(id) end
            if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                pursuit.lastCombatFaceAt = os.clock()
                mq.cmd('/face fast')
            end
        end
        pursuit.lastNavTargetId = 0
        pursuit.id = 0
        return true
    end

    if (os.clock() - pursuit.improvedAt) > PURSUIT_STALL_TIMEOUT or pursuit.navStalls >= 3 then
        if d <= effectiveArrivalDist + 12 and losOk then
            stopMoving()
            if not followOnly then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
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
                ('no progress for ' .. PURSUIT_STALL_TIMEOUT .. 's')))
            markUnreachable(id)
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
    if stickLoaded() then
        local stickActive = false
        pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
        local stickDist = math.max(5, math.floor(targetDist))
        local stickTgt = 0
        pcall(function() stickTgt = mq.TLO.Stick.StickTarget() or 0 end)
        if pursuit.lastNavTargetId ~= id or not stickActive or stickTgt ~= id then
            mq.cmdf('/stick id %d %d', id, stickDist)
            pursuit.lastNavTargetId = id
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

-- Try to open the nearest door/switch. MQ2Nav's own OpenDoors setting only opens
-- doors the navmesh recognizes as door links; on this server that's evidently not
-- catching every door (that's exactly what "gets stuck" at a door looks like). This
-- is a direct fallback: door-target whatever Switch is nearest and click it.
-- Harmless when nothing is close by, and throttled so it doesn't spam-click one
-- while just walking past it.
local function tryOpenNearbyDoor(force)
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

local function repositionCloser()
    if runtime.startBuffPass then return end
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
        targetDist = math.max(15, math.min(targetDist, math.floor(currentDist - 15)))
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
        mq.cmdf('/stick id %d %d', tid, targetDist)
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
    if tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax Clicked nearby door/switch to clear line of sight.')
    end

    -- Reset pursuit tracking so moveToward doesn't short-circuit on stale arrival flags
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.lastStickDist = 0

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
        mq.cmdf('/stick id %d %d', tid, targetDist)
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
local function moveTowardLoc(x, y, z, dist)
    dist = dist or 15
    if distToLoc(x, y, z) <= dist then
        stopMoving()
        pursuit.lastNavLoc = nil
        return true
    end

    local locStr = string.format('loc %.2f %.2f %.2f', y, x, z) -- Y X Z, matches EQ standard
    local locKey = string.format('%.1f_%.1f_%.1f', y, x, z)

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
            moveTowardLoc(nextWp.x, nextWp.y, nextWp.z, radius)
        end
    else
        moveTowardLoc(wp.x, wp.y, wp.z, radius)
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

local function performUnstuck()
    if tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax stuck -- tried opening a nearby door.')
        mq.delay(600)
        stuckState.counter = 0
        stuckState.lastStuckRecoveryAt = os.clock()
        pursuit.id = 0; pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil
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
            markUnreachable(currentTgtId)
            mq.cmd('/target clear')
        else
            print(
                '\ay[Triune]\ax stuck (Attempt 4) -- all directional maneuvers failed. Clearing pursuit to find a new target/path.')
        end

        pursuit.id = 0
        pursuit.lastNavTargetId = 0
        pursuit.lastNavLoc = nil
        pursuit.wanderLoc = nil
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
end

local function checkStuck()
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
                tryOpenNearbyDoor() -- close to target but blocked by door/wall; try opening doors
            else
                stuckState.counter = 0
                stuckState.lastX, stuckState.lastY = me.X() or 0, me.Y() or 0
                return
            end
        end
    end

    tryOpenNearbyDoor() -- open any door we're walking past, before we ever stall on it
    local x, y = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    local dist = math.sqrt((x - stuckState.lastX) ^ 2 + (y - stuckState.lastY) ^ 2)
    if dist < 2 then
        stuckState.counter = stuckState.counter + 1
        if stuckState.counter > 2 then performUnstuck() end
    else
        stuckState.counter = 0
    end
    stuckState.lastX, stuckState.lastY = x, y
end

-- Safety net for an intermittent, hard-to-pin-down report: occasionally Hunter
-- arrives at a mob and just stands there without ever starting the attack.
-- Rather than guess at the exact internal cause, this detects the SYMPTOM
-- directly -- stationary, a live NPC target already within range, but not
-- fighting or casting -- and forces a clean pursuit reset so the normal
-- engage logic gets a fresh, unstuck shot at it next tick. Can't false-fire
-- during normal play: all four conditions are only simultaneously true when
-- something's already wedged. Skipped for modes that deliberately don't
-- self-engage (Manual: no automation at all; Backline/Pet Tank: never
-- move/melee by design, so "stationary and not fighting" is often correct).
local function checkCombatStall()
    if (ctrl.mode == 'Assist' and ctrl.submode == 'Backline')
        or (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState ~= 'FIGHTING') then
        stuckState.combatStallSince = nil
        return
    end
    local t = mq.TLO.Target
    local haveLiveNPC = t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse'
    if not haveLiveNPC or not isHostileTarget(t.ID()) then
        stuckState.combatStallSince = nil
        return
    end

    local d = distToId(t.ID())
    local isPullStandBack = (ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee')
    if ctrl.combat_style == 'Melee' and not isPullStandBack then
        if d <= maxMeleeDistance(t.ID()) and not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
    elseif ctrl.combat_style == 'Ranged' then
        if d <= (ctrl.ranged_dist or 40) and not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
    end
    stuckState.combatStallSince = nil
end

-- When EQ chat reports "You cannot see your target." during combat, this active
-- repositioning maneuver steps back from the target and re-faces it. In EQ, being
-- inside or right under a mob's bounding box/hitbox causes line-of-sight raycasts
-- to fail internally. Stepping backward to the perimeter of melee reach restores LoS.
handleCannotSeeTarget = function()
    if not ctrl or not ctrl.running then return end
    local tgt = mq.TLO.Target
    if not tgt or not tgt() then return end

    local tid = tgt.ID() or 0
    if tid <= 0 then return end

    local isNpc = (tgt.Type() == 'NPC' or tgt.Type() == 'Pet') and not tgt.Dead() and tgt.Type() ~= 'Corpse'
    if not isNpc or not isHostileTarget(tid) then return end

    local d = distToId(tid)
    local maxReach = maxMeleeDistance(tid)
    local isMelee = (ctrl and ctrl.combat_style == 'Melee') or mq.TLO.Me.Combat() or (d <= (maxReach + 10))

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
        if tryOpenNearbyDoor and tryOpenNearbyDoor(true) then
            print('\ay[Triune]\ax "Cannot see target" -- attempted to open nearby door.')
            mq.delay(400)
        elseif ctrl and ctrl.mode == 'Puller' then
            print(string.format('\ay[Triune]\ax Target #%d obstructed after 4 reposition attempts -- marking unreachable.', tid))
            markUnreachable(tid)
            stopMoving()
            mq.cmd('/target clear')
        else
            print(string.format('\ay[Triune]\ax Target #%d still cannot be seen (dist=%.1f) -- performing unstuck recovery.', tid, d))
            performUnstuck()
        end
        stuckState.cannotSeeAttempts = 0
    end
end

local function chaseMA()
    if not ctrl.chase then return end
    local id = maPcId()
    if not id then return end
    moveToward(id, ctrl.chase_dist or 15, true) -- follow position only; id here is the MA player, not a combat target
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
local function idleReturn()
    if ctrl.camp_loc then
        moveTowardLoc(ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, 15)
    else
        chaseMA()
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
local function findRoamTarget(searchRadius, searchMaxZ, minLevel, maxLevel)
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

    local defaultRadius = 100
    if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
        defaultRadius = ctrl.waypoint_scan_radius or 100
    elseif isCampMode then
        defaultRadius = ctrl.camp_radius or 100
    else
        defaultRadius = ctrl.hunter_radius or 1500
    end
    local radius = searchRadius or defaultRadius
    local maxZ   = searchMaxZ or (isCampMode and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75))
    local myZ    = mq.TLO.Me.Z() or 0

    -- 1. Check XTarget first (strictly constrained to max XTarget chase range and maxZ height diff)
    local maxXtarDist = (ctrl and ctrl.xtar_nav_dist) or 150
    if isCampMode and radius > 0 then
        maxXtarDist = math.min(radius, maxXtarDist)
    end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and (xt.Type() == 'NPC' or xt.Type() == 'Pet') and not xt.Dead() and xt.Type() ~= 'Corpse' then
            local id = xt.ID()
            if not isSpawnPetOrPlayer(id) and isHostileTarget(id) then
                local dist = xt.Distance3D() or 999
                local lvl = xt.Level() or 0
                local okZ, xz = pcall(function() return xt.Z() end)
                if dist <= maxXtarDist and (okZ and xz and math.abs(xz - myZ) <= maxZ) and lvl >= minLv and lvl <= maxLv then
                    if isPullAllowed(xt.CleanName()) and not isUnreachable(id) then
                        if not outsideAnchor(xt.Y() or 0, xt.X() or 0) then
                            return id
                        end
                    end
                end
            end
        end
    end

    -- 2. Scan Zone Spawns sequentially by proximity with Two-Tier Z filtering
    local function scanSpawns(zLimit)
        local search = string.format('npc targetable radius %d', radius)
        for i = 1, 300 do
            local s = mq.TLO.NearestSpawn(i, search)
            if not (s and s()) then break end
            local sid = s.ID() or 0
            if sid > 0 then
                local stype = s.Type() or ''
                if stype == 'NPC' and not s.Dead() and stype ~= 'Corpse' then
                    if not isAnyPet(s) and not isSpawnPetOrPlayer(sid) and isHostileTarget(sid) then
                        local lvl = s.Level() or 0
                        if lvl >= minLv and lvl <= maxLv then
                            local okZ, sz = pcall(function() return s.Z() end)
                            if okZ and sz and math.abs(sz - myZ) <= zLimit then
                                local sy, sx = s.Y() or 0, s.X() or 0
                                if not outsideAnchor(sy, sx) then
                                    if isPullAllowed(s.CleanName()) and isConAllowed(s) and not isUnreachable(sid) then
                                        local pathOk = true
                                        if navLoaded() then
                                            local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
                                            if meshOk and meshLoaded then
                                                local dist = s.Distance3D() or 999
                                                if dist > 25 then
                                                    local hasPath = false
                                                    local ok = pcall(function() hasPath = mq.TLO.Navigation.PathExists('id ' .. sid)() end)
                                                    if ok and not hasPath then
                                                        pathOk = false
                                                        markUnreachable(sid)
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
    local tier1Z = math.min(floorZ, maxZ)
    local targetId = scanSpawns(tier1Z)
    if targetId then return targetId end

    -- Tier 2: Expand to full maxZ range if no target on immediate floor
    if maxZ > tier1Z then
        targetId = scanSpawns(maxZ)
        if targetId then return targetId end
    end

    return nil
end
local function checkCloserTarget(curTargetId, searchRadius, searchMaxZ, minLevel, maxLevel)
    if not curTargetId or curTargetId <= 0 then return nil end
    if ctrl.check_closer_mobs == false then return nil end
    if pursuit.hasRetargeted then return nil end

    local isPulling = (ctrl.mode == 'Puller')
    local isCampMode = isPulling and (ctrl.submode == 'Camp')
    local minL = minLevel or (isCampMode and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1))
    local maxL = maxLevel or (isCampMode and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100))
    local maxZ = searchMaxZ or (isCampMode and (ctrl.camp_z or 75) or (ctrl.hunter_z or 75))

    local curDist = distToId(curTargetId)
    if curDist <= 35 or mq.TLO.Me.Combat() then return nil end

    local candId = findRoamTarget(searchRadius, maxZ, minL, maxL)
    if candId and candId ~= curTargetId then
        local candDist = distToId(candId)
        if candDist <= (curDist - 25) and candDist <= (curDist * 0.75) then
            return candId, candDist, curDist
        end
    end
    return nil
end

local function checkPullHpRest()
    -- Buff before sitting. Both this and the between-fights buff pass own the
    -- idle window, and castGem stands you up to cast, so running them together
    -- flaps sit/stand. Buffing takes seconds and costs mana; resting to full
    -- takes far longer, so the useful order is buffs first, then recover.
    if runtime.startBuffPass then return false end
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
                mq.cmd('/target clear')
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
                    mq.cmd('/target clear')
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
local function pullerTick()
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
        if addId and setTarget(addId) then
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

        if checkPullHpRest() then return end

        local scanRadius = hasWps and (ctrl.use_waypoints ~= false) and (ctrl.waypoint_scan_radius or 100) or
        (ctrl.camp_radius or 100)
        local id = findRoamTarget(scanRadius, maxCampZ, ctrl.pull_min_level, ctrl.pull_max_level)
        if id and setTarget(id) then
            if not runtime.verifyTargetCon(id, true) then
                print(string.format(
                    '\ay[Triune]\ax Puller: target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                    id, tostring(mq.TLO.Target.CleanName())))
                mq.cmd('/target clear')
                runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
                return
            end
            stopMoving()
            runtime.pullTargetId = id; runtime.pullState = 'TO_MOB'
            pursuit.hasRetargeted = false
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
            if setTarget(aggroId) then
                print(string.format(
                    '\ay[Triune]\ax Puller aggro on path to mob -- switching to XTarget #%d (%s) and pulling back',
                    aggroId, tostring(mq.TLO.Target.CleanName())))
                runtime.pullTargetId = aggroId
                runtime.pullState = 'TO_CAMP'
            end
        elseif not mq.TLO.Me.Combat() and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
            local closerId, candDist, curDist = checkCloserTarget(runtime.pullTargetId, ctrl.camp_radius, maxCampZ,
                ctrl.pull_min_level, ctrl.pull_max_level)
            if closerId and setTarget(closerId) then
                stopMoving()
                pursuit.id = 0
                pursuit.lastNavTargetId = 0
                pursuit.hasRetargeted = true
                print(string.format(
                    '\ay[Triune]\ax Puller: Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f]',
                    closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist))
                runtime.pullTargetId = closerId
            end
        end
    end

    local s = mq.TLO.Spawn(runtime.pullTargetId)
    local alive = s() and s.Type() == 'NPC' and not s.Dead() and s.Type() ~= 'Corpse'
    if not alive then
        local maxCampZ = ctrl.camp_z or 75
        local addId = firstNPCXtarget(false, maxCampZ)
        if addId and setTarget(addId) then
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
            mq.cmd('/target clear')
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving()
        elseif isUnreachable(runtime.pullTargetId) then
            print('\ay[Triune]\ax pull target unreachable -- picking a different mob.')
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving()
        else
            local pullStyle = ctrl.pull_style or 'Melee'
            local reqRange = (pullStyle == 'Melee') and desiredRange(runtime.pullTargetId) or (ctrl.pull_engage_dist or 100)

            if moveToward(runtime.pullTargetId, reqRange) then
                local tid = runtime.pullTargetId
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
                    mq.cmd('/face fast')
                    if isXTargetId(tid) or distToId(tid) <= 30 then
                        tagged = true
                    else
                        local slotToCast = ctrl.pull_spell_gem or 1
                        local g = loadout.gems and loadout.gems[slotToCast]
                        local spellName = ctrl.pull_spell
                        if not spellName or spellName == '' then
                            pcall(function() spellName = mq.TLO.Me.Gem(slotToCast).Name() end)
                        end

                        if spellName and spellName ~= '' then
                            local dummyEntry = g or { spell = spellName, target = 'E: Current Target', cls = 'ALL' }
                            castGem(slotToCast, dummyEntry, tid)
                        else
                            for i = 1, NUM_GEMS do
                                local lg = loadout.gems and loadout.gems[i]
                                local lpct = lg and tonumber(lg.pct)
                                if lpct == nil then lpct = 100 end
                                if lg and lg.spell and lg.spell ~= '' and lpct > 0 then
                                    local isDet = isDetrimentalAction(lg.spell, lg.target, lg)
                                    if isDet and castGem(i, lg, tid) then break end
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
        if c and moveTowardLoc(c.x, c.y, c.z, 15) then runtime.pullState = 'FIGHTING' end
    elseif runtime.pullState == 'FIGHTING' then
        if ctrl.mode == 'Puller' and ctrl.combat_style == 'Melee' and not mq.TLO.Me.Combat() then
            mq.cmd('/attack on')
        end
    end
end

local function playerHasAggro(targetId)
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
--   Ranged -> /autofire is on (bow is firing)
--   Spell  -> mob HP has dropped below 100% AND player holds aggro
--             (at least one spell has connected)
-- Works for all three combat styles; safe to call with no pets present.
local function playerIsEngagingTarget(tid)
    if mq.TLO.Me.Combat() then return true end   -- melee /attack on
    if mq.TLO.Me.AutoFire() then return true end -- ranged autofire on
    -- Spell style: confirm a hit has landed via HP drop + aggro ownership
    local tpct = pctHP(tid) or 100
    if tpct < 100 and playerHasAggro(tid) then return true end
    return false
end

local function checkAggroSwitch()
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
            local isHunterMode = (ctrl.mode == 'Manual' or (ctrl.mode == 'Puller' and ctrl.submode == 'Hunt'))
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
        if setTarget(bestId) then
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

fullStop = function()
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
    runtime.pullState = 'IDLE'
    runtime.pullTargetId = 0
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
    runtime.startBuffPass = false
    runtime.buffTries = {}
end

onZoned = function()
    if ctrl.running then
        ctrl.running = false
        fullStop()
        print('\ay[Triune]\ax zoned -- pausing autocombat.')
    end
    pursuit.unreachableIds = {}
    pursuit.id = 0
    pursuit.wanderLoc = nil
    runtime.pullState = 'IDLE'
    runtime.pullTargetId = 0
    runtime.pullHpRest = false
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
    local detected = classesFromInventoryWindow(false, true)
    if detected then
        myClasses = detected
    end
end

-- Bind engine helpers to runtime table to prevent exceeding Lua 5.1 / LuaJIT 60-upvalue limit
runtime.fullStop = fullStop
runtime.pctHP = pctHP
runtime.isCombat = isCombat
runtime.anyXtarAlive = anyXtarAlive
runtime.countNPCXtarget = countNPCXtarget
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
runtime.stickLoaded = stickLoaded
runtime.hasActivePet = hasActivePet
runtime.trioHasPetClass = trioHasPetClass
runtime.setManualHunterPetHold = setManualHunterPetHold
runtime.playerHasAggro = playerHasAggro
runtime.playerIsEngagingTarget = playerIsEngagingTarget
runtime.checkStuck = checkStuck
runtime.checkCombatStall = checkCombatStall
runtime.checkGemMemSync = checkGemMemSync
runtime.checkAggroSwitch = checkAggroSwitch
runtime.pullerTick = pullerTick
runtime.findRoamTarget = findRoamTarget
runtime.checkCloserTarget = checkCloserTarget
runtime.chaseMA = chaseMA
runtime.idleReturn = idleReturn
runtime.maTargetId = maTargetId
runtime.resolveTargetId = resolveTargetId
runtime.castGem = castGem
runtime.fireAA = fireAA
runtime.isDetrimentalAction = isDetrimentalAction
runtime.isTargetInRange = isTargetInRange
runtime.conditionMet = conditionMet
runtime.baseTok = baseTok
runtime.sungKey = sungKey
runtime.isSpecialSkill = isSpecialSkill
runtime.clearCursor = clearCursor
runtime.markUnreachable = markUnreachable
runtime.moveToward = moveToward
runtime.moveTowardLoc = moveTowardLoc
runtime.setTarget = setTarget
runtime.desiredRange = desiredRange
runtime.maxMeleeDistance = maxMeleeDistance
runtime.isIgnored = isIgnored
runtime.isUnreachable = isUnreachable

-- Self-buff pass: self "missing buff" / always gems and AAs only.
-- Returns 'cast' if something fired, 'wait' if a buff is still landing, 'done'
-- when nothing is left. Hunt waits until 'done', real aggro, or the timeout.
--
-- Every cast is recorded against buffTries. Once an entry has been cast
-- buff_max_tries times and still reads missing it is parked for buff_retry_sec,
-- which is what stops a mis-detected buff being re-cast on every single tick.
local function startBuffTick()
    if mq.TLO.Me.Dead() then return 'done' end
    if isCasting() then return 'wait' end
    local myId = mq.TLO.Me.ID() or 0
    if myId <= 0 then return 'wait' end

    local pending = false
    local blocked = nil

    local function idleSelf(when, target)
        local tok = baseTok(target)
        return (when == 'missing buff' or when == 'always') and (tok == 'Myself' or tok == 'Self')
    end

    -- An entry that is missing but cannot fire right now -- spell not memmed,
    -- AA on cooldown, not enough mana or endurance -- must not hold the pass
    -- open, or a single unusable entry stalls every pull for the full timeout.
    -- It gets four ticks of grace, in case it is simply mid-recast, and is then
    -- left for the next post-combat pass.
    local function stalled(key)
        local n = (runtime.startBuffStalls[key] or 0) + 1
        runtime.startBuffStalls[key] = n
        return n < 4
    end

    for name, a in pairs(loadout.aas) do
        if a and a.enabled and idleSelf(a.when, a.target) then
            local aPct = tonumber(a.pct) or 100
            local key = sungKey(name, myId)
            if aPct > 0 and not a.burn_only and runtime.buffRetryOk(key)
                and not runtime.buffFactuallyUp(myId, name) then
                if fireAA(name, a, myId) then
                    runtime.buffTryRecorded(key, name)
                    return 'cast'
                end
                if stalled(key) then pending = true end
            end
        end
    end

    for i = 1, NUM_GEMS do
        local g = loadout.gems[i]
        if g and g.spell and g.spell ~= '' and idleSelf(g.when, g.target) then
            local pctVal = tonumber(g.pct)
            if pctVal == nil then pctVal = 100 end
            local key = sungKey(g.spell, myId)
            if pctVal > 0 and not g.burn_only and runtime.buffRetryOk(key)
                and not runtime.buffFactuallyUp(myId, g.spell) then
                if castTracker.isLockedOut(g.spell) then
                    blocked = (blocked and (blocked .. ', ') or '')
                        .. string.format('%s (%s)', g.spell,
                            castTracker.failureReason(g.spell) or 'repeated failures')
                else
                    if castGem(i, g, myId) then
                        runtime.buffTryRecorded(key, g.spell)
                        return 'cast'
                    end
                    if stalled(key) then pending = true end
                end
            end
        end
    end
    if not pending and blocked then
        print('\ay[Triune]\ax buff skipped -- ' .. blocked)
    end
    return pending and 'wait' or 'done'
end

local function combatTick()
    local fullStop = runtime.fullStop
    local pctHP = runtime.pctHP
    local isCombat = runtime.isCombat
    local anyXtarAlive = runtime.anyXtarAlive
    local countNPCXtarget = runtime.countNPCXtarget
    local isXTargetId = runtime.isXTargetId
    local isGroupOrRaidMember = runtime.isGroupOrRaidMember
    local isAnyPet = runtime.isAnyPet
    local isSpawnPetOrPlayer = runtime.isSpawnPetOrPlayer
    local isHostileTarget = runtime.isHostileTarget
    local firstNPCXtarget = runtime.firstNPCXtarget
    local stopMoving = runtime.stopMoving
    local distToId = runtime.distToId
    local distToLoc = runtime.distToLoc
    local hasLoS = runtime.hasLoS
    local isMoveActive = runtime.isMoveActive
    local isCasting = runtime.isCasting
    local navLoaded = runtime.navLoaded
    local stickLoaded = runtime.stickLoaded
    local hasActivePet = runtime.hasActivePet
    local trioHasPetClass = runtime.trioHasPetClass
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
    local isSpecialSkill = runtime.isSpecialSkill
    local clearCursor = runtime.clearCursor
    local markUnreachable = runtime.markUnreachable
    local moveToward = runtime.moveToward
    local moveTowardLoc = runtime.moveTowardLoc
    local setTarget = runtime.setTarget
    local desiredRange = runtime.desiredRange
    local maxMeleeDistance = runtime.maxMeleeDistance
    local isIgnored = runtime.isIgnored
    local isUnreachable = runtime.isUnreachable

    if not ctrl.running then return end
    if mq.TLO.Me.Dead() then
        if not runtime.deathGuardFired then
            runtime.deathGuardFired = true
            fullStop()
            runtime.sungBuffs = {}
            runtime.buffTries = {}
            runtime.discExpires = {}
            runtime.discCooldown = {}
            petState.myPets = {}; petState.lastObservedId = 0; petState.lastCastCls = nil
            print('\ar[Triune]\ax character is dead -- paused. Will resume automatically once alive again.')
        end
        return
    end
    runtime.deathGuardFired = false

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

    -- Buff upkeep runs between fights. "Something hostile is on my XTarget" is
    -- the signal, not isCombat(), which is also true with a hostile merely
    -- targeted -- the normal state the instant hunting resumes. The hater and
    -- aggro counts alone were not enough: they read 0 on some builds, which
    -- left the pass running straight through fights.
    local inFight = anyXtarAlive(true)
    if not inFight then
        pcall(function()
            if (mq.TLO.Me.XTHaterCount() or 0) > 0 then inFight = true end
            if (mq.TLO.Me.XTAggroCount() or 0) > 0 then inFight = true end
            if mq.TLO.Me.CombatState() == 'COMBAT' then inFight = true end
        end)
    end
    if runtime.wasUnderAttack and not inFight then
        beginStartBuffPass()
    end
    runtime.wasUnderAttack = inFight

    if runtime.startBuffPass then
        local now = os.clock()
        local timedOut = (now - (runtime.startBuffAt or now)) > 25
        if inFight or timedOut then
            runtime.startBuffPass = false
            if timedOut and not inFight then
                print('\ay[Triune]\ax buff check timed out -- moving on.')
            elseif inFight then
                print('\ay[Triune]\ax buff check dropped -- aggro.')
            end
        elseif isCasting() then
            return
        else
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            if isMoveActive() or mq.TLO.Me.Moving() then
                stopMoving()
                return
            end
            local result = startBuffTick()
            if result == 'cast' or result == 'wait' then
                return
            end
            runtime.startBuffPass = false
            print('\ag[Triune]\ax buffs up.')
        end
    end

    local curPetId = mq.TLO.Me.Pet.ID() or 0
    if curPetId ~= 0 and curPetId ~= petState.lastObservedId then
        if petState.lastCastCls then
            petState.myPets[petState.lastCastCls] = curPetId
            petState.lastCastCls = nil
        else
            for _, c in ipairs(myClasses) do
                if PET_CLASSES[c] and (not petState.myPets[c] or not isSpawnAlive(petState.myPets[c])) then
                    petState.myPets[c] = curPetId
                    break
                end
            end
        end
        petState.lastObservedId = curPetId
    elseif curPetId == 0 then
        petState.lastObservedId = 0
    end

    checkStuck()
    checkCombatStall()
    checkGemMemSync()
    if (ctrl.mode == 'Manual' and ctrl.manual_auto_xtarget ~= false) or ctrl.mode == 'Puller' or (ctrl.mode == 'Assist' and ctrl.submode == 'Camp') then
        checkAggroSwitch()
    end

    local numXtar = countNPCXtarget()
    local t = mq.TLO.Target
    local haveNPC = t() and (t.Type() == 'NPC' or t.Type() == 'Pet') and not t.Dead() and t.Type() ~= 'Corpse'
        and not isSpawnPetOrPlayer(t.ID()) and isHostileTarget(t.ID())
    if haveNPC and ctrl.mode == 'Puller' then
        if isIgnored(t.CleanName()) then
            haveNPC = false
            mq.cmd('/target clear')
        elseif not isXTargetId(t.ID()) then
            local isPulling = (ctrl.submode == 'Camp')
            local minL = isPulling and (ctrl.pull_min_level or 1) or (ctrl.hunter_min_level or 1)
            local maxL = isPulling and (ctrl.pull_max_level or 100) or (ctrl.hunter_max_level or 100)
            local lvl = t.Level() or 0
            if lvl > 0 and (lvl < minL or lvl > maxL) then
                haveNPC = false
                mq.cmd('/target clear')
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
            elseif moveToward(id, desiredRange(id)) then
                engage = true
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
            if haveNPC then
                local tid = mq.TLO.Target.ID() or 0
                local tspawn = mq.TLO.Spawn(tid)
                local maxScan = hasWps and (ctrl.waypoint_scan_radius or 100) or (ctrl.hunter_radius or 1500)
                -- Add hysteresis buffer (+35 units for waypoint patrol, +30% for free roam) so boundary spawns are not dropped
                local dropDist = hasWps and (maxScan + 35) or (maxScan * 1.3 + 50)
                if not tspawn() or tspawn.Dead() or tspawn.Type() == 'Corpse' or isUnreachable(tid) or isIgnored(tspawn.CleanName()) then
                    haveNPC = false
                    mq.cmd('/target clear')
                elseif isXTargetId(tid) then
                    local maxXtarDist = (ctrl.xtar_nav_dist or 150)
                    if distToId(tid) > (maxXtarDist + 20) and not mq.TLO.Me.Combat() then
                        -- XTarget is beyond max chase range + buffer and not actively engaged in melee
                        haveNPC = false
                        mq.cmd('/target clear')
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
                            '\\ay[Triune]\\ax Hunt: dropping #%d (%s) -- %s. Blacklisting for 60s.',
                            tid, tostring(tspawn.CleanName()), reason))
                        markUnreachable(tid)
                        haveNPC = false
                        mq.cmd('/target clear')
                    end
                end
            end

            local xtarId = firstNPCXtarget(false, maxHuntZ)
            if xtarId then
                local curId = haveNPC and mq.TLO.Target.ID() or 0
                if curId ~= xtarId and (curId == 0 or not isXTargetId(curId)) then
                    stopMoving()
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    if setTarget(xtarId) then
                        print(string.format('\ay[Triune]\ax Puller (Hunt) XTarget detected -- engaging #%d (%s) [dist %.1f, max chase %d]',
                            xtarId, tostring(mq.TLO.Target.CleanName()), distToId(xtarId), ctrl.xtar_nav_dist or 150))
                    end
                    haveNPC = true
                end
            end

            if haveNPC then
                if runtime.pullHpRest and not isXTargetId(mq.TLO.Target.ID()) then
                    mq.cmd('/target clear')
                    haveNPC = false
                elseif not isXTargetId(mq.TLO.Target.ID()) and not mq.TLO.Me.Combat() and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
                    local curId = mq.TLO.Target.ID()
                    local closerId, candDist, curDist = checkCloserTarget(curId, nil, maxHuntZ, ctrl.hunter_min_level,
                        ctrl.hunter_max_level)
                    if closerId and setTarget(closerId) then
                        stopMoving()
                        pursuit.id = 0
                        pursuit.lastNavTargetId = 0
                        pursuit.hasRetargeted = true
                        print(string.format(
                            '\ay[Triune]\ax Puller (Hunt): Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f]',
                            closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist))
                    end
                end
            end

            if not haveNPC then
                if checkPullHpRest() then return end
                local scanRadius = hasWps and (ctrl.waypoint_scan_radius or 100) or (ctrl.hunter_radius or 1500)
                local id = findRoamTarget(scanRadius, maxHuntZ, ctrl.hunter_min_level, ctrl.hunter_max_level)
                if id and setTarget(id) then
                    if not runtime.verifyTargetCon(id, true) then
                        print(string.format(
                            '\ay[Triune]\ax Puller (Hunt): target #%d (%s) blocked by Faction Consideration filter -- clearing target.',
                            id, tostring(mq.TLO.Target.CleanName())))
                        mq.cmd('/target clear')
                        haveNPC = false
                        pursuit.id = 0
                        return
                    end
                    stopMoving()
                    haveNPC = true
                    pursuit.wanderLoc = nil
                    pursuit.hasRetargeted = false
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
                    mq.cmd('/target clear')
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
                if pullStyle ~= 'Melee' and not isXTargetId(id) and not mq.TLO.Me.Combat() then
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
                        mq.cmd('/face fast')
                        if isXTargetId(id) or mq.TLO.Me.Combat() then
                            engage = true
                        else
                            local slotToCast = ctrl.pull_spell_gem or 1
                            local g = loadout.gems and loadout.gems[slotToCast]
                            local spellName = ctrl.pull_spell
                            if not spellName or spellName == '' then
                                pcall(function() spellName = mq.TLO.Me.Gem(slotToCast).Name() end)
                            end
                            if spellName and spellName ~= '' then
                                local dummyEntry = g or { spell = spellName, target = 'E: Current Target', cls = 'ALL' }
                                castGem(slotToCast, dummyEntry, id)
                            else
                                -- Fallback: try first detrimental spell in loadout
                                for i = 1, NUM_GEMS do
                                    local lg = loadout.gems and loadout.gems[i]
                                    local lpct = lg and tonumber(lg.pct)
                                    if lpct == nil then lpct = 100 end
                                    if lg and lg.spell and lg.spell ~= '' and lpct > 0 then
                                        local isDet = isDetrimentalAction(lg.spell, lg.target, lg)
                                        if isDet and castGem(i, lg, id) then break end
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
                                -- Fallback to ranged weapon (bow/autofire)
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
        if ctrl.submode == 'Backline' then
            local id = maTargetId()
            if id then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
                haveNPC = true
                if pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id) and distToId(id) <= maxMeleeDistance(id) and hasLoS(id) then
                    engage = true
                end
            else
                haveNPC = false
            end
        else -- 'Chase' or 'Camp'
            local id = maTargetId()
            local closingOnMob = false
            if id then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
                haveNPC = true
                if pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id) then
                    closingOnMob = true
                    if moveToward(id, desiredRange(id)) then engage = true end
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
                    mq.cmd('/target clear')
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
        local t = mq.TLO.Target
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

    -- Auto-attack / Auto-fire handling:
    -- Engage autoattack/autofire only when target exists, target is within striking distance,
    -- or target is confirmed engaged on XTarget.
    -- Turn off autoattack/autofire whenever out of range or when no NPCs remain on XTarget list.
    -- For player-directed modes (Manual, Assist), also require the NPC to be confirmed hostile before
    -- initiating auto-attack — prevents hitting friendly NPCs (merchants, etc.).
    local xtarActive = anyXtarAlive()
    local autoAttackOk = true
    if haveNPC and engage then
        local engineMode = (ctrl.mode == 'Puller')
        if not engineMode then
            local tid = mq.TLO.Target.ID() or 0
            if not isHostileTarget(tid) then autoAttackOk = false end
        end
    end
    local style = ctrl and ctrl.combat_style or 'Melee'
    local tid = mq.TLO.Target.ID() or 0
    local isPullStandBack = (ctrl.mode == 'Puller' and ctrl.pull_stand_back and (ctrl.pull_style or 'Melee') ~= 'Melee')
    if style == 'Melee' then
        if not isPullStandBack then
            local isDraggingToCamp = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState == 'TO_CAMP')
            if haveNPC and not isDraggingToCamp and autoAttackOk then
                local curDist = (tid > 0) and distToId(tid) or 999
                local maxReach = (tid > 0) and maxMeleeDistance(tid) or ((ctrl and ctrl.melee_dist) or MELEE_RANGE)
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
                    if (os.clock() - (pursuit.lastCombatFaceAt or 0)) > 0.4 then
                        pursuit.lastCombatFaceAt = os.clock()
                        mq.cmd('/face fast')
                    end
                elseif not isMoveActive() and curDist > maxReach and tid > 0 then
                    -- Mob moved, was pushed, or is out of striking reach: re-close distance
                    moveToward(tid, desiredRange(tid))
                end
            end
        end
    elseif style == 'Ranged' then
        if haveNPC and engage and autoAttackOk then
            if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
            if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
        else
            if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
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
            local tid = mq.TLO.Target.ID() or 0
            if tid > 0 then
                local ts = mq.TLO.Spawn(tid)
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
        local tid = mq.TLO.Target.ID() or 0
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
        local tid = mq.TLO.Target.ID() or 0
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
            -- Same treatment the gem loop gets below: a self buff AA is exempt
            -- from Min XTarget (empty out of combat, where buffing happens) and
            -- is held until the fight ends unless it is instant.
            local aTok = baseTok(a.target)
            local aSelfBuff = (a.when == 'missing buff') and (aTok == 'Myself' or aTok == 'Self')
            local aMinXt = aSelfBuff and 0 or (tonumber(a.min_xtar) or 1)
            local aInstant = (ctrl.buff_instant_in_combat ~= false)
                and runtime.isInstantCast(name, true)
            local aHeld = aSelfBuff and not ctrl.buff_in_combat and isCombat() and not aInstant
            if a.enabled and (aPct > 0) and (not a.burn_only or ctrl.burn) and (numXtar >= aMinXt) and not aHeld then
                local id = resolveTargetId(a.target, a.cls, a.when, name, aPct)
                local aKey = (a.when == 'missing buff') and id and sungKey(name, id) or nil
                local aRetryOk = (not aKey) or runtime.buffRetryOk(aKey)
                if id and aRetryOk and conditionMet(a.when, aPct, name, id, a.cls) then
                    local isDet = isDetrimentalAction(name, a.target, a)
                    if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                        if fireAA(name, a, id) and aKey then
                            runtime.buffTryRecorded(aKey, name)
                        end
                    end
                end
            end
        end
    end
    -- Gather every enabled disc/skill whose condition (and Boss Only gate, if
    -- set) is currently satisfied, then try them in priority order (lowest
    -- first) and stop at the first one that actually fires. fireDisc/fireSkill
    -- return false if the ability's own cooldown isn't up, so this is what
    -- lets "try the next disc down the list if the top one is still on
    -- cooldown" work -- exactly the same pattern gems already use (try slot
    -- 1..12 in order, break on success).
    if combatReady then
        local eligibleDiscs = {}
        for name, d in pairs(loadout.discs) do
            local dPct = tonumber(d.pct)
            if dPct == nil then dPct = 30 end
            if d.enabled and (dPct > 0) and (not d.burn_only or ctrl.burn) and (numXtar >= (tonumber(d.min_xtar) or 1)) then
                local id = resolveTargetId(d.target, d.cls, d.when, name, dPct)
                if id and conditionMet(d.when, dPct, name, id, d.cls) then
                    local bossOk = true
                    if d.boss_only then
                        local s = mq.TLO.Spawn(id)
                        bossOk = not not (s() and s.Named())
                    end
                    if bossOk then
                        local isDet = isDetrimentalAction(name, d.target, d)
                        if not isDet or (isHostileTarget(id) and isTargetInRange(name, id)) then
                            local ready = isSpecialSkill(name) and isSkillReady(name) or isDiscReady(name)
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
            local fired
            if isSpecialSkill(e.name) then
                fired = fireSkill(e.name, e.entry, e.id)
            else
                fired = fireDisc(e.name, e.entry, e.id)
            end
            if fired then break end
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

    if isCasting() then
        castTracker.wasCasting = true
    elseif castTracker.wasCasting then
        castTracker.wasCasting = false
        if stickLoaded() then
            pcall(function()
                if mq.TLO.Stick.Status() == 'PAUSED' then mq.cmd('/stick unpause') end
            end)
        end
        if not castTracker.failed then
            castTracker.recordSuccess(castTracker.activeSpell or castTracker.lastSpell)
        end
        castTracker.activeSpell = nil
        clearCursor()
        local isDraggingToCamp = (ctrl.mode == 'Puller' and ctrl.submode == 'Camp' and runtime.pullState == 'TO_CAMP')
        local tid = mq.TLO.Target.ID() or 0
        local d = (tid > 0) and distToId(tid) or 999
        local maxReach = (tid > 0) and maxMeleeDistance(tid) or ((ctrl and ctrl.melee_dist) or MELEE_RANGE)
        if ctrl and ctrl.combat_style == 'Melee' and haveNPC and not isDraggingToCamp then
            if d <= maxReach then
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                mq.cmd('/face fast')
                if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
            elseif not isMoveActive() and tid > 0 then
                moveToward(tid, desiredRange(tid))
            end
        end
    end

    if combatReady and not isCasting() and not isMoveActive() and loadout.clickies and #loadout.clickies > 0 then
        for _, c in ipairs(loadout.clickies) do
            local cPct = tonumber(c.pct)
            if cPct == nil then cPct = 100 end
            local isEnabled = (c.enabled ~= false) and (cPct > 0)
            local minXt = tonumber(c.min_xtar) or 1
            local xtOk = (numXtar >= minXt)
            local burnOk = (not c.burn_only or ctrl.burn)
            if isEnabled and burnOk and xtOk then
                local effName = (c.spell and c.spell ~= '') and c.spell or c.name
                local id = resolveTargetId(c.target, 'ALL', c.when, effName, cPct)
                local condOk = id and conditionMet(c.when, cPct, effName, id, 'ALL')
                -- An item's effect name often differs from what lands on the
                -- bar, so a buff clickie is a prime candidate to read missing
                -- forever. Same backoff the gem and AA loops use: after
                -- buff_max_tries clicks that do not change the bar, park it.
                local cKey = (c.when == 'missing buff') and id and sungKey(effName, id) or nil
                if cKey and not runtime.buffRetryOk(cKey) then condOk = false end
                if condOk then
                    local isDet = isDetrimentalAction(effName, c.target, c)
                    local targetValid = not isDet or (isHostileTarget(id) and isTargetInRange(effName, id))
                    if targetValid and runtime.useClickie(c, id) then
                        if c.when == 'missing buff' and c.spell and c.spell ~= '' then
                            local bene = false
                            pcall(function() bene = mq.TLO.Spell(c.spell).Beneficial() end)
                            if bene then runtime.sungBuffs[sungKey(c.spell, id)] = true end
                        end
                        if cKey then runtime.buffTryRecorded(cKey, effName) end
                        break
                    end
                end
            end
        end
    end

    if combatReady and not isCasting() and not isMoveActive() then
        for i = 1, NUM_GEMS do
            local g = loadout.gems[i]
            if g and g.spell and g.spell ~= '' then
                local pctVal = tonumber(g.pct)
                if pctVal == nil then pctVal = 100 end
                local isEnabled = (pctVal > 0)
                local tok = baseTok(g.target)
                local selfBuff = (g.when == 'missing buff') and (tok == 'Myself' or tok == 'Self')
                -- Min XTarget is a "don't waste this on one mob" gate for combat
                -- spells. A self buff has to be exempt or it could never land
                -- out of combat, where XTarget is empty by definition.
                local minXt = selfBuff and 0 or (tonumber(g.min_xtar) or 1)
                local xtOk = (numXtar >= minXt)
                local burnOk = (not g.burn_only or ctrl.burn)
                local lockedOut = castTracker.isLockedOut(g.spell)
                -- Refreshing a self buff mid-fight costs cast time you owe the
                -- fight. Held until combat ends unless Refresh Buffs In Combat
                -- is on -- or the buff is instant, which costs nothing and does
                -- not interrupt melee, so there is no reason to wait. Target
                -- debuffs and 'always' entries are untouched.
                local instantOk = (ctrl.buff_instant_in_combat ~= false)
                    and runtime.isInstantCast(g.spell, false)
                local heldBuff = selfBuff and not ctrl.buff_in_combat and isCombat() and not instantOk
                if isEnabled and burnOk and xtOk and not lockedOut and not heldBuff then
                    local id = resolveTargetId(g.target, g.cls, g.when, g.spell, pctVal)
                    local condOk = id and conditionMet(g.when, pctVal, g.spell, id, g.cls)
                    local buffKey = (g.when == 'missing buff') and id and sungKey(g.spell, id) or nil
                    if buffKey and not runtime.buffRetryOk(buffKey) then condOk = false end
                    if condOk then
                        local isDet = isDetrimentalAction(g.spell, g.target, g)
                        local targetValid = not isDet or (isHostileTarget(id) and isTargetInRange(g.spell, id))
                        if targetValid and castGem(i, g, id) then
                            if buffKey then
                                local bene = false
                                pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                                if bene then runtime.sungBuffs[buffKey] = true end
                                runtime.buffTryRecorded(buffKey, g.spell)
                            end
                            break
                        end
                    elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                        runtime.lastGemDiagAt = os.clock()
                        local tid = mq.TLO.Target.ID() or 0
                        local ts = mq.TLO.Spawn(tid)
                        local ttype = (ts() and ts.Type()) or 'nil'
                        local thp = (ts() and ts.PctHPs()) or -1
                        print(string.format(
                            '\ao[Triune debug]\ax gem %d "%s" skipped -- tgtTok="%s"(base="%s") id=%s (rawTgt=%d type=%s hp=%d) condOk=%s xtOk=%s(%d>=%d)',
                            i, g.spell, tostring(g.target), tostring(baseTok(g.target)), tostring(id), tid, ttype, thp,
                            tostring(condOk), tostring(xtOk), numXtar, minXt))
                    end
                elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                    runtime.lastGemDiagAt = os.clock()
                    print(string.format(
                        '\ao[Triune debug]\ax gem %d "%s" gate failed -- isEnabled=%s(%d%%) xtOk=%s(%d>=%d) burnOk=%s lockedOut=%s',
                        i, g.spell, tostring(isEnabled), pctVal, tostring(xtOk), numXtar, minXt, tostring(burnOk), tostring(lockedOut)))
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
    clearMapRadiusVisuals()

    if SUBMODES[ctrl.mode] then
        print(string.format('\ag[Triune]\ax mode set to %s (%s).', ctrl.mode, ctrl.submode))
    else
        print(string.format('\ag[Triune]\ax mode set to %s.', ctrl.mode))
    end
    saveLoadout(true)
    return true
end

local triuneToggle
local function triuneCommand(...)
    local args = { ... }
    local cmd = ''
    if #args > 0 then
        cmd = normalizeCommandKey(args[1])
    end
    if cmd == '' then
        triuneToggle()
        return
    end
    if cmd == 'run' or cmd == 'start' then
        if ctrl.running then
            print('\ay[Triune]\ax already running.')
        else
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
            ctrl.running = true
            runtime.wasRunning = true
            beginStartBuffPass()
            print('\ag[Triune]\ax running.')
        end
    elseif cmd == 'pause' or cmd == 'stop' then
        if not ctrl.running then
            print('\ay[Triune]\ax already paused.')
        else
            if ctrl.mode == 'Manual' then
                setManualHunterPetHold(true, true)
            else
                setManualHunterPetHold(false, true)
            end
            ctrl.running = false
            fullStop()
            print('\ag[Triune]\ax paused.')
        end
    elseif cmd == 'status' then
        local modeStr = ctrl.mode
        if SUBMODES[ctrl.mode] then modeStr = modeStr .. ' (' .. ctrl.submode .. ')' end
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
    elseif cmd == 'buffs' or cmd == 'buffbar' or cmd == 'buffdump' then
        runtime.dumpSelfBar()
    elseif cmd == 'help' or cmd == 'h' or cmd == '?' then
        print('\ag[Triune]\ax --- Slash Commands (/ac or /triune) ---')
        print('  \ag/ac run | start\ax - Start autocombat execution')
        print('  \ag/ac pause | stop\ax - Pause execution & disengage combat')
        print('  \ag/ac burn [on|off]\ax - Toggle burn mode')
        print('  \ag/ac debug\ax - Toggle live combat debug telemetry in chat')
        print('  \ag/ac status\ax - Print running state and mode')
        print('  \ag/ac buffs\ax - Print buff/song bar contents and the up/missing verdict per self buff')
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
        print('  \ag/ac dps | /dps\ax - Toggle DPS parser window')
        print('  \ag/ac zplane [5-100]\ax - Configure Hunter Tier 1 same-floor / Z plane height threshold')
        print('  \ag/ac huntz [10-300]\ax - Configure Hunter Tier 2 max vertical height difference')
        print('  \ag/ac pullcon [con]\ax - Configure faction consideration filter')
        print('  \ag/ac wp [add|clear|del|on|off|list]\ax - Configure & toggle Puller Waypoint Patrol')
        print('  \ag/ac pullhp [0-95]\ax - Set minimum HP % threshold before pausing pulling to rest')
        print(
            '  \ag/ac <mode> [submode]\ax - Switch combat mode (manual, puller [hunt|camp], assist [chase|camp|backline])')
        print('  \ag/triunerun\ax - Quick keybind command to toggle run/pause')
    elseif cmd == 'spellbook' or cmd == 'book' then
        if toggleTool('triune_spellbook') == 'started' then
            print('\ag[Triune]\ax launching spellbook engine...')
        else
            print('\ag[Triune]\ax stopping spellbook engine...')
        end
    elseif cmd == 'cursorui' or cmd == 'cursorwin' or cmd == 'cursormgr' then
        if toggleTool('triune_cursor') == 'started' then
            print('\ag[Triune]\ax launching cursor manager...')
        else
            print('\ag[Triune]\ax stopping cursor manager...')
        end
    elseif cmd == 'buff' or cmd == 'buffbot' or cmd == 'buffui' then
        if toggleTool('triune_buffbot') == 'started' then
            print('\ag[Triune]\ax launching buffbot engine...')
        else
            print('\ag[Triune]\ax stopping buffbot engine...')
        end
    elseif cmd == 'dps' or cmd == 'dpsui' or cmd == 'dpsparser' then
        if toggleTool('triune_dps', '/dps toggle') == 'started' then
            print('\ag[Triune]\ax launching DPS parser window...')
        else
            print('\ag[Triune]\ax toggling DPS parser window...')
        end
    elseif cmd == 'clearcursor' or cmd == 'autoinv' or cmd == 'cursor' then
        clearCursor()
    elseif cmd == 'update' or cmd == 'updater' or cmd == 'checkupdate' then
        mq.cmd('/lua run triune_updater')
    elseif cmd == 'track' or cmd == 'tracker' or cmd == 'trackui' or cmd == 'zone' then
        if toggleTool('triune_track') == 'started' then
            print('\ag[Triune]\ax launching zone tracker window...')
        else
            print('\ag[Triune]\ax stopping zone tracker window...')
        end
    elseif cmd == 'compact' or cmd == 'mini' or cmd == 'hud' then
        ctrl.compact = not ctrl.compact
        saveLoadout(true)
        print(string.format('\ag[Triune]\ax Compact HUD mode %s.', ctrl.compact and 'ENABLED' or 'DISABLED'))
    elseif cmd == 'pullcon' or cmd == 'con' or cmd == 'confilter' then
        ctrl.pull_con_filter = ctrl.pull_con_filter or {}
        local arg2 = args[2] and string.lower(args[2]) or ''
        local arg3 = args[3] and string.lower(args[3]) or ''
        if arg2 == 'preset' then
            if arg3 == 'hostile' then
                for _, c in ipairs(PULL_CON_LIST) do
                    ctrl.pull_con_filter[c] = (c == 'Scowling' or c == 'Threateningly' or c == 'Dubious' or c == 'Apprehensive')
                end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Hostile Only')
            elseif arg3 == 'indifferent' then
                for _, c in ipairs(PULL_CON_LIST) do
                    ctrl.pull_con_filter[c] = (c == 'Scowling' or c == 'Threateningly' or c == 'Dubious' or c == 'Apprehensive' or c == 'Indifferent')
                end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Hostile + Indifferent')
            elseif arg3 == 'all' or arg3 == 'selectall' then
                for _, c in ipairs(PULL_CON_LIST) do ctrl.pull_con_filter[c] = true end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Select All')
            elseif arg3 == 'clear' or arg3 == 'none' then
                for _, c in ipairs(PULL_CON_LIST) do ctrl.pull_con_filter[c] = false end
                print('\ag[Triune]\ax Puller Faction Con filter set to preset: Clear All')
            else
                print('\ay[Triune]\ax usage: /ac pullcon preset [all|hostile|indifferent|none]')
            end
            saveLoadout(true)
        elseif arg2 ~= '' then
            local targetCon = nil
            for _, c in ipairs(PULL_CON_LIST) do
                if string.lower(c) == arg2 then
                    targetCon = c; break
                end
            end
            if targetCon then
                local enable = true
                if arg3 == 'off' or arg3 == '0' or arg3 == 'false' then enable = false end
                ctrl.pull_con_filter[targetCon] = enable
                saveLoadout(true)
                print(string.format('\ag[Triune]\ax Puller Faction Con "%s" set to %s.', targetCon,
                    enable and 'ENABLED' or 'DISABLED'))
            else
                print('\ay[Triune]\ax unknown consideration tier: ' .. tostring(args[2]))
            end
        else
            print('\ag[Triune]\ax --- Puller Faction Considerations ---')
            for _, c in ipairs(PULL_CON_LIST) do
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
            clearMapRadiusVisuals()
            saveLoadout(true)
            print('\ag[Triune]\ax Waypoint Patrol ENABLED.')
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.use_waypoints = false
            clearMapRadiusVisuals()
            saveLoadout(true)
            print('\ag[Triune]\ax Waypoint Patrol DISABLED.')
        elseif sub == 'toggle' then
            ctrl.use_waypoints = not ctrl.use_waypoints
            clearMapRadiusVisuals()
            saveLoadout(true)
            print(string.format('\ag[Triune]\ax Waypoint Patrol %s.', ctrl.use_waypoints and 'ENABLED' or 'DISABLED'))
        elseif sub == 'radius' or sub == 'arrival' then
            local r = tonumber(args[3])
            if r and r >= 5 and r <= 100 then
                ctrl.waypoint_radius = r
                saveLoadout(true)
                print(string.format('\ag[Triune]\ax Waypoint Arrival Radius set to %d.', r))
            else
                print('\ay[Triune]\ax usage: /ac wp radius [5-100]')
            end
        elseif sub == 'scan' or sub == 'scanradius' then
            local r = tonumber(args[3])
            if r and r >= 20 and r <= 500 then
                ctrl.waypoint_scan_radius = r
                saveLoadout(true)
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
            saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agMelee\ax (range ' .. tostring(ctrl.melee_dist or 14) .. ')')
        elseif st == 'ranged' or st == 'bow' then
            ctrl.combat_style = 'Ranged'
            saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agRanged (bow)\ax (range ' .. tostring(ctrl.ranged_dist or 40) .. ')')
        elseif st == 'spell' or st == 'cast' or st == 'caster' then
            ctrl.combat_style = 'Spell'
            saveLoadout(true)
            print('\ag[Triune]\ax Combat style set to: \agSpell\ax (range ' .. tostring(ctrl.ranged_dist or 40) .. ')')
        else
            print('\ay[Triune]\ax usage: /ac style [melee|ranged|spell]')
        end
    elseif cmd == 'range' or cmd == 'meleerange' or cmd == 'dist' then
        local val = tonumber(args[2])
        if val then
            if ctrl.combat_style == 'Melee' or cmd == 'meleerange' then
                ctrl.melee_dist = math.max(5, math.min(50, math.floor(val)))
                saveLoadout(true)
                print(string.format('\ag[Triune]\ax Max Melee Distance set to %d units.', ctrl.melee_dist))
            else
                ctrl.ranged_dist = math.max(15, math.min(200, math.floor(val)))
                saveLoadout(true)
                print(string.format('\ag[Triune]\ax Ranged Engagement Distance set to %d units.', ctrl.ranged_dist))
            end
        else
            if ctrl.combat_style == 'Melee' then
                print(string.format('\ag[Triune]\ax Current Max Melee Distance: %d units. (usage: /ac range [5-50])', ctrl.melee_dist or 14))
            else
                print(string.format('\ag[Triune]\ax Current Ranged Distance: %d units. (usage: /ac range [15-200])', ctrl.ranged_dist or 40))
            end
        end
    elseif cmd == 'huntz' or cmd == 'z' then
        local val = tonumber(args[2])
        if val then
            ctrl.hunter_z = math.max(10, math.min(300, math.floor(val)))
            saveLoadout(true)
            print(string.format('\ag[Triune]\ax Hunter Max Height Diff (Z) set to %d units.', ctrl.hunter_z))
        else
            print(string.format('\ag[Triune]\ax Current Hunter Max Height Diff (Z): %d units. (usage: /ac huntz [10-300])', ctrl.hunter_z or 75))
        end
    elseif cmd == 'zplane' or cmd == 'huntplane' or cmd == 'floorz' then
        local val = tonumber(args[2])
        if val then
            ctrl.hunter_z_plane = math.max(5, math.min(100, math.floor(val)))
            saveLoadout(true)
            print(string.format('\ag[Triune]\ax Hunter Floor Height (Z Plane) set to %d units.', ctrl.hunter_z_plane))
        else
            print(string.format('\ag[Triune]\ax Current Hunter Floor Height (Z Plane): %d units. (usage: /ac zplane [5-100])', ctrl.hunter_z_plane or 15))
        end
    elseif cmd == 'pullhp' or cmd == 'minhp' then
        local val = tonumber(args[2])
        if val then
            ctrl.pull_min_hp_pct = math.max(0, math.min(95, math.floor(val)))
            saveLoadout(true)
            if ctrl.pull_min_hp_pct == 0 then
                print('\ag[Triune]\ax Min Pull HP % disabled (0% -- pull at any HP).')
            else
                print(string.format('\ag[Triune]\ax Min Pull HP threshold set to %d%% (pause pulling to rest until 100%%).', ctrl.pull_min_hp_pct))
            end
        else
            print(string.format('\ag[Triune]\ax Current Min Pull HP threshold: %d%%. (usage: /ac pullhp [0-95])', ctrl.pull_min_hp_pct or 0))
        end
    elseif setTriuneMode(args[1], args[2]) then
        -- mode command handled
    else
        print(
            '\ay[Triune]\ax usage: /ac [run|pause|burn|compact|status|spellbook|cursorui|dps|track|buffbot|update|clearcursor|style|range|zplane|huntz|pullhp|help|pullcon|wp|manual|puller [hunt|camp]|assist [chase|camp|backline]]')
    end
end

triuneToggle = function()
    if ctrl.running then
        if ctrl.mode == 'Manual' then
            setManualHunterPetHold(true, true)
        else
            setManualHunterPetHold(false, true)
        end
        ctrl.running = false
        fullStop()
        print('\ag[Triune]\ax paused.')
    else
        if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
            runtime.setNearestWaypoint()
        end
        ctrl.running = true
        runtime.wasRunning = true
        beginStartBuffPass()
        print('\ag[Triune]\ax running.')
    end
end

mq.unbind('/triune')
mq.bind('/triune', triuneCommand)

mq.unbind('/triunerun')
mq.bind('/triunerun', triuneToggle)

mq.unbind('/ac')
mq.bind('/ac', triuneCommand)

mq.imgui.init('TriuneAutoCombat', draw)
print('\ag[Triune]\ax loaded v' ..
    VERSION ..
    '. Data: ' ..
    (DATA_OK and 'triune_data.lua OK' or 'MISSING -- run extract_spells.py') ..
    '. Use /ac run | /ac pause | /ac status | /ac spellbook | /ac <mode>. /lua stop triune to exit.')

-- ============================================================================
-- Map Visualization Helper
-- ============================================================================

clearMapRadiusVisuals = function()
    mq.cmd('/maploc remove')
    mq.cmd('/mapfilter pullradius 0')
    mq.cmd('/mapfilter castradius 0')
    runtime.lastMapDraw = { active = false, type = nil, key = '' }
end

updateMapRadiusVisuals = function()
    if not ctrl.show_map_radius then
        if runtime.lastMapDraw and runtime.lastMapDraw.active then
            clearMapRadiusVisuals()
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

    local key = string.format('%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s',
        tostring(mode),
        tostring(submode),
        tostring(ctrl.use_waypoints),
        tostring(ctrl.waypoint_scan_radius or 100),
        tostring(ctrl.waypoint_radius or 20),
        tostring(ctrl.camp_radius or 100),
        tostring(ctrl.hunter_radius or 1500),
        tostring(ctrl.hunter_combat_radius or 0),
        tostring(ctrl.current_waypoint_idx or 1),
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
    clearMapRadiusVisuals()

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
            mq.cmdf('/maploc %f %f %f radius 30 rcolor 0 255 0 color 0 255 0 label Camp',
                ctrl.camp_loc.y, ctrl.camp_loc.x, ctrl.camp_loc.z)
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
            onCharacterChanged()
            UI.resetTracker()
            -- camp restored from a save; no map circle is drawn
            reconcileSungBuffs()                                      -- don't re-sing bard buffs that are already up
            reconcilePets()                                           -- don't re-summon pets that are already out
            runtime.lastSig = loadoutSig(); runtime.autoDirty = false -- baseline; don't save what we just loaded
        end
        local curZone = mq.TLO.Zone.ShortName()
        if curZone and curZone ~= '' and curZone ~= runtime.lastZoneShort then
            runtime.lastZoneShort = curZone
            reconcilePets()
            if ctrl.use_waypoints and ctrl.waypoints and #ctrl.waypoints > 0 then
                runtime.setNearestWaypoint()
            end
        end
        if reDetectRequested then
            reDetectRequested = false
            local detected = detectClasses(true) -- safe here -- main loop coroutine can yield/delay
            if detected then myClasses = detected end
        end
        -- (Cursor items are cleared on-demand prior to actions/mems or post-cast completion)
        updateMapRadiusVisuals()
        -- drain one queued spell-mem per pass, out of combat, while stationary, and while not casting
        local memmed = false
        if not isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() then
            for slot, name in pairs(runtime.pendingMem) do
                runtime.pendingMem[slot] = nil
                tryMem(slot, name) -- verifies + reports; blocks briefly while it lands
                memmed = true
                break
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
                fullStop()
            end
        end

        -- auto-save: persist the loadout ~1.5s after any change (no Save click needed)
        local sig = loadoutSig()
        if sig ~= runtime.lastSig then
            runtime.lastSig = sig; runtime.autoDirty = true; runtime.autoDirtyAt = os.clock()
        end
        if runtime.autoDirty and (os.clock() - runtime.autoDirtyAt) > 1.5 then
            saveLoadout(true); runtime.autoDirty = false
        end

        mq.delay(memmed and 200 or 150)
    end
end

runMainLoop()
clearMapRadiusVisuals()
saveLoadout(true)
