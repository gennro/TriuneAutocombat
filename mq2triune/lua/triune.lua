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
local VERSION           = '1.3'
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
-- loadout.buffGems is the same shape as loadout.gems -- a second, independently
-- edited set of 12 gem slots for pet-summon/buff spells (e.g. Nec/Mag pet
-- summons, Bst buffs) that don't fit on the bar alongside your combat spells.
-- Only one of the two is ever actually memmed at a time (ctrl.buff_mode picks
-- which); "Mem All to Bar" on either tab both memorizes AND activates that set.
-- loadout.aas and loadout.discs are maps: name -> { cls=, target=, when=, enabled=, pct= }
-- (discs = disciplines, e.g. Mend/Lay on Hands/Hand of Piety -- fired via
-- /disc, not /alt act; kept separate from aas since they're a different
-- activation command and data source, but use the identical entry shape)
local loadout        = { gems = {}, buffGems = {}, aas = {}, discs = {} }

-- combat control state (Control tab). NOTE: this is the control surface; wiring it
-- into the actual casting/movement engine is phase 2.
-- Single source of truth for ctrl's defaults -- used both at module load and
-- on every character switch (onCharacterChanged). Was previously written out
-- twice, byte-for-byte, in both places; a field added to one copy and missed
-- in the other would silently default to nil after a character switch.
local function defaultCtrl()
    return {
        running              = false,
        mode                 = 'Assist',
        combat_style         = 'Melee',
        ranged_dist          = 40,
        ma_name              = '',
        assist_at            = 98,
        chase                = true,
        chase_dist           = 15,
        automem              = true,
        camp_loc             = nil,
        camp_radius          = 100,
        camp_z               = 75,
        hunter_radius        = 1500,
        hunter_z             = 75,
        hunter_min_level     = 1,
        hunter_max_level     = 100,
        hunter_combat_radius = 250, -- max roam distance from anchor when anchor is set
        hunter_combat_loc    = nil, -- {x,y,z} anchor; nil = no constraint
        pull_min_level       = 1,
        pull_max_level       = 100,
        check_closer_mobs    = true,
        nav_fallback_stick   = false,
        debug_mode           = false,
        buff_mode            = false,
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
        min_mana_pct         = 0,
        pet_assist_at        = 100,
        pet_hold_enabled     = true,
        show_map_radius      = true,
        burn                 = false
    }
end
local ctrl = defaultCtrl()
-- Modelled on KissAssist's 9 modes, renamed to our own vocabulary (see the
-- triune-mode-roadmap project memory). Most of these are combinations of the
-- same primitives (chase/camp/pull/engage-immediately) rather than separate
-- systems -- see the combatTick dispatch below.
local MODES = { 'Manual', 'Hunter', 'Manual Hunter', 'Puller', 'Pull & Assist',
    'Assist', 'Chase Assist', 'Backline', 'Tank', 'Garrison', 'Pet Tank' }
local MODE_DESC = {
    Manual            = 'No auto-targeting, chasing, or pulling. Your loadout still fires on whatever YOU target.',
    Hunter            = 'Roams and solo-kills the nearest valid mob.',
    ['Manual Hunter'] = 'Fights your current target automatically, but does not roam or search for new mobs.',
    Puller            = 'Pulls mobs back to camp and tanks them yourself.',
    ['Pull & Assist'] = 'Pulls mobs back to camp and holds them for the Main Assist -- does not self-tank.',
    Assist            = 'Assists the Main Assist; chases to stay in range, or returns to camp when idle if one is set.',
    ['Chase Assist']  = 'Same as Assist -- chases and assists the Main Assist everywhere.',
    Backline          = 'Assists the Main Assist but NEVER moves or melees -- ranged/caster support only.',
    Tank              =
    'Assists the Main Assist and commits to melee immediately, ignoring Assist At %. Returns to camp when idle if one is set.',
    Garrison          = 'Holds a camp point and reactively tanks whatever aggros -- does not roam looking for fights.',
    ['Pet Tank']      =
    'Roams for targets like Hunter, closes to Ranged Distance (never melee range) and sends pets in to tank while you free-cast/ranged from there.',
}

-- Runtime & state management tables
local runtime = {
    pullState = 'IDLE',
    pullTargetId = 0,
    deathGuardFired = false,
    medBreakActive = false,
    pendingMem = {},
    lastCast = {},
    lastTick = 0,
    lastSig = nil,
    autoDirty = false,
    autoDirtyAt = 0,
    lastBuffDiagAt = 0,
    lastHunterDiagAt = 0,
    lastHunterMsgKey = nil,
    lastGemDiagAt = 0,
    lastAssistCmdAt = 0,
    sungBuffs = {},
    lastMapDraw = { active = false, type = nil, key = '' }
}

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
    hasRetargeted = false
}

local stuckState = {
    checkAt = 0,
    lastX = 0,
    lastY = 0,
    counter = 0,
    lastDoorClickAt = 0,
    combatStallSince = nil,
    lastStuckRecoveryAt = nil,
    lastCombatStallRecoveryAt = nil
}

-- Full-stop and onZoned: reset every movement/combat command and stale state.
-- Used by STOP, a mode switch, and the death guard.
local fullStop, onZoned
local PET_CLASSES = { Nec = true, Mag = true, Bst = true }
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
local ignoreList  = {}
local ignoreInput = ''

local FRIENDLY    = { 'Myself', 'Main Assist', 'Tank', 'Lowest-HP Ally', 'Whole Group', 'Pet' }
local ENEMY       = { 'Current Target', 'Assist Target', 'Nearest Add', 'Unmezzed Add', 'All Enemies' }
local TARGETS     = {}
for _, t in ipairs(FRIENDLY) do TARGETS[#TARGETS + 1] = 'F: ' .. t end
for _, t in ipairs(ENEMY) do TARGETS[#TARGETS + 1] = 'E: ' .. t end
local WHENS = { 'HP <=', 'target HP <=', 'my HP <=', 'my Mana <=', 'missing buff', 'missing pet', 'has Poison/Disease',
    'ally is Dead', 'add is loose', 'twist while fighting', 'in combat', 'on Named / burn',
    'always' }

-- ============================================================================
-- Local Theme & Common Helpers (Self-Contained Module)
-- ============================================================================
local MQSHORT = {
    WARRIOR = 'War',
    CLERIC = 'Clr',
    PALADIN = 'Pal',
    RANGER = 'Rng',
    SHADOWKNIGHT = 'SK',
    DRUID = 'Dru',
    MONK = 'Mnk',
    BARD = 'Brd',
    ROGUE = 'Rog',
    SHAMAN = 'Shm',
    NECROMANCER = 'Nec',
    WIZARD = 'Wiz',
    MAGICIAN = 'Mag',
    ENCHANTER = 'Enc',
    BEASTLORD = 'Bst',
    BERSERKER = 'Ber'
}

local SLOT_COLORS = {
    { 0.30, 0.70, 1.00 }, -- slot 1: Arcane Blue
    { 1.00, 0.55, 0.30 }, -- slot 2: Ember Gold
    { 0.37, 0.88, 0.64 }, -- slot 3: Jade Green
}

local function classColor(abbr)
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

local function idxOf(tbl, val)
    if not tbl then return 1 end
    for i, v in ipairs(tbl) do
        if v == val then return i end
    end
    return 1
end

local function defaultsForKind(kind, bene)
    if kind == 'heal' then return 'F: Myself', 'my HP <=' end
    if kind == 'buff' then return 'F: Myself', 'missing buff' end
    if kind == 'pet' then return 'F: Myself', 'missing pet' end
    if kind == 'util' then return 'F: Myself', 'always' end
    if kind == 'debuff' then return 'E: Current Target', 'target HP <=' end
    if kind == 'dot' then return 'E: Current Target', 'target HP <=' end
    if kind == 'dd' then return 'E: Current Target', 'target HP <=' end
    if bene == true then return 'F: Myself', 'missing buff' end
    return 'E: Current Target', 'target HP <='
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

local spellbookSetCache = nil
local lastSpellbookCacheTime = 0

local function getScribedSpellSet()
    local now = os.clock()
    if spellbookSetCache and (now - lastSpellbookCacheTime) < 3.0 then
        return spellbookSetCache
    end

    local set = {}
    pcall(function()
        local count = mq.TLO.Me.BookCount() or 720 ---@diagnostic disable-line: undefined-field
        for slot = 1, count do
            local bName = nil
            pcall(function() bName = mq.TLO.Me.Book(slot).Name() end)
            if not bName or bName == "" or bName == "NULL" then
                pcall(function()
                    local res = mq.TLO.Me.Book(slot)()
                    if type(res) == "string" and res ~= "" and res ~= "NULL" then bName = res end
                end)
            end

            if bName and bName ~= "" and bName ~= "NULL" then
                set[bName] = true
                set[bName:lower()] = true
                local cleaned = cleanSpellName(bName):lower()
                set[cleaned] = true
                local norm = normalizeSpellName(bName)
                if norm ~= "" then set[norm] = true end
            end
        end
    end)

    spellbookSetCache = set
    lastSpellbookCacheTime = now
    return set
end

local function isScribed(nm)
    if not nm or nm == "" then return false end

    -- 1. Check cached spellbook map (fastest & handles unindexed TLO names)
    local sbSet = getScribedSpellSet()
    if sbSet[nm] or sbSet[nm:lower()] then return true end

    local cleaned = cleanSpellName(nm):lower()
    if cleaned ~= "" and sbSet[cleaned] then return true end

    local norm = normalizeSpellName(nm)
    if norm ~= "" and sbSet[norm] then return true end

    -- 2. Direct TLO Book query fallback (Me.Book(name) returns slot index integer > 0 if scribed)
    local ok, res = pcall(function() return mq.TLO.Me.Book(nm)() end)
    if ok and type(res) == 'number' and res > 0 then return true end

    if cleaned ~= "" then
        local okC, resC = pcall(function() return mq.TLO.Me.Book(cleaned)() end)
        if okC and type(resC) == 'number' and resC > 0 then return true end
    end

    -- 3. RankName lookup via TLO Spell
    local okR, rName = pcall(function() return mq.TLO.Spell(nm).RankName() end)
    if okR and type(rName) == 'string' and rName ~= "" and rName ~= nm then
        if sbSet[rName] or sbSet[rName:lower()] then return true end
        local okRB, resRB = pcall(function() return mq.TLO.Me.Book(rName)() end)
        if okRB and type(resRB) == 'number' and resRB > 0 then return true end
    end

    return false
end

local hasAACache = {}
local function hasAA(nm)
    if not nm or nm == "" or tonumber(nm) ~= nil then return false end
    local now = os.clock()
    if hasAACache[nm] ~= nil and (now - (hasAACache[nm].time or 0)) < 5.0 then
        return hasAACache[nm].val
    end
    local ok, res = pcall(function() return mq.TLO.Me.AltAbility(nm).Rank() end)
    local hasIt = (ok and res ~= nil and res > 0)
    hasAACache[nm] = { val = hasIt, time = now }
    return hasIt
end

local knownDiscSet = nil
local function scanKnownDiscs()
    knownDiscSet = {}
    pcall(function()
        local count = mq.TLO.Me.CombatAbilityCount() or 0 ---@diagnostic disable-line: undefined-field
        for i = 1, count do
            local name = mq.TLO.Me.CombatAbility(i).Name()
            if name and name ~= "" then
                knownDiscSet[name] = true
                knownDiscSet[name:lower()] = true
            end
        end
    end)
end

local function isDiscKnown(discName)
    if not discName or discName == "" then return false end
    if not knownDiscSet then scanKnownDiscs() end
    local kSet = knownDiscSet or {}
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

local function classesFromTitle(loud)
    local ok, title = pcall(function() return mq.TLO.MacroQuest.Title() end) ---@diagnostic disable-line: undefined-field
    if not ok or type(title) ~= 'string' or title == '' then return nil end
    local found = {}
    for word in title:gmatch('%a+') do
        local up = word:upper()
        if MQSHORT[up] then
            local abbr = MQSHORT[up]
            local duplicate = false
            for _, existing in ipairs(found) do
                if existing == abbr then
                    duplicate = true; break
                end
            end
            if not duplicate then found[#found + 1] = abbr end
        end
    end
    if #found > 0 then
        if loud then
            print(string.format('\127[33m[Triune]\127[r Detected %d class(es) from MacroQuest Title: %s', #found,
                table.concat(found, ', ')))
        end
        return found
    end
    return nil
end

local function classesFromInventoryWindow(loud, force)
    local wasOpen = false
    pcall(function() wasOpen = mq.TLO.Window('InventoryWindow').Open() end)

    if not wasOpen and force then
        mq.cmd('/windowstate InventoryWindow open')
        mq.delay(200)
    end

    local found = {}
    pcall(function()
        for i = 1, 3 do
            local text = mq.TLO.Window('InventoryWindow').Child('IW_ClassList').List(i)()
            if text and text ~= '' then
                local firstWord = text:match('^(%a+)')
                if firstWord then
                    local up = firstWord:upper()
                    if MQSHORT[up] then
                        found[#found + 1] = MQSHORT[up]
                    end
                end
            end
        end
    end)

    if not wasOpen and force then
        mq.cmd('/windowstate InventoryWindow close')
    end

    if #found > 0 then
        if loud then
            print(string.format('\127[33m[Triune]\127[r Detected %d class(es) from InventoryWindow: %s', #found,
                table.concat(found, ', ')))
        end
        return found
    end
    return nil
end

local function detectClasses(loud)
    local found = classesFromTitle(loud)
    if found and #found > 0 then return found end

    found = classesFromInventoryWindow(loud, false)
    if found and #found > 0 then return found end

    local ok, mainClass = pcall(function() return mq.TLO.Me.Class.ShortName() end)
    if ok and mainClass and mainClass ~= '' and mainClass ~= 'NULL' then
        if loud then
            print(string.format('\127[33m[Triune]\127[r Single-class character detected (%s).', mainClass))
        end
        return { mainClass }
    end

    return nil
end

local function isSpawnAlive(id)
    if not id or id <= 0 then return false end
    local ok, s = pcall(function() return mq.TLO.Spawn(id) end)
    if not ok or not s or not s() then return false end
    local dead, tp, hp = false, '', 100
    pcall(function() dead = s.Dead() end)
    pcall(function() tp = s.Type() end)
    pcall(function() hp = s.PctHPs() end)
    return (not dead) and (tp ~= 'Corpse') and ((hp or 0) > 0)
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
    local ok, loaded = pcall(function() return mq.TLO.Plugin('mq2nav').IsLoaded() or false end)
    return ok and loaded
end

local function stickLoaded()
    local ok, loaded = pcall(function() return mq.TLO.Plugin('mq2moveutils').IsLoaded() or false end)
    return ok and loaded
end

local function isMoveActive()
    local navActive, moveActive = false, false
    if navLoaded() then
        pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
    end
    if stickLoaded() then
        pcall(function() moveActive = mq.TLO.Stick.Active() or false end)
    end
    return navActive or moveActive
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
    pcall(function() mq.cmd('/keypress back') end)
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
end

local function findFirstNPCXtarget(unmezzedOnly, isIgnoredFn, isUnreachableFn)
    local chosenId, lowestHp = nil, 101
    pcall(function()
        local count = mq.TLO.Me.XTarget() or 0
        for i = 1, count do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) then
                    local s = mq.TLO.Spawn(id)
                    if s() then
                        local stype = s.Type() or ''
                        local cname = s.CleanName() or ''
                        if (stype == 'NPC' or stype == 'Pet')
                            and (s.PctHPs() or 0) > 0 and not s.Dead()
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

    local function recordFailure(spellName, maxRetries, lockoutSec)
        if not spellName then return end
        failureCount[spellName] = (failureCount[spellName] or 0) + 1
        if failureCount[spellName] >= (maxRetries or 2) then
            lockouts[spellName] = os.clock() + (lockoutSec or 30)
            failureCount[spellName] = 0
            print(string.format('\127[31m[Triune]\127[r Lockout applied for "%s" (%ds)', spellName, lockoutSec or 30))
        end
    end

    local function isLockedOut(spellName)
        if not spellName then return false end
        local untilTime = lockouts[spellName]
        if not untilTime then return false end
        if os.clock() < untilTime then return true end
        lockouts[spellName] = nil
        return false
    end

    local function onFailureEvent(reason, maxRetries, lockoutSec)
        local castingName = nil
        pcall(function() castingName = mq.TLO.Me.Casting.Name() end)
        if castingName and castingName ~= '' then
            recordFailure(castingName, maxRetries, lockoutSec)
        end
    end

    local function recordSuccess(spellName)
        if not spellName then return end
        failureCount[spellName] = 0
        lockouts[spellName] = nil
    end

    return {
        recordFailure = recordFailure,
        recordSuccess = recordSuccess,
        isLockedOut = isLockedOut,
        onFailureEvent = onFailureEvent,
        clear = function()
            failureCount = {}; lockouts = {}
        end
    }
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
    local current = nil
    pcall(function() current = mq.TLO.Me.Gem(slot).Name() end)
    if current == name then return true end

    clearCursor()
    pcall(function()
        mq.cmdf('/memspell %d "%s"', slot, name)
        mq.delay(2000, function() return (mq.TLO.Me.Gem(slot).Name() or '') == name end)
    end)
    local landed = false
    pcall(function() landed = (mq.TLO.Me.Gem(slot).Name() or '') == name end)
    clearCursor()
    return landed
end

local ALIAS_CLASS_MAP = {
    SK = 'SK',
    SHD = 'SK',
    BST = 'Bst',
    Bst = 'Bst',
    SHM = 'Shm',
    Shm = 'Shm'
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

local filteredSpellsCache = {}
local lastFilteredCacheTime = 0
local lastFilterState = {}

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

    -- Check specific pet subcategories/categories, pet spell names, or pet buff spells (e.g. Burnout, Pet Haste, Pet Power)
    if subcatStr:find('pet') or (catStr:find('pet') and not catStr:find('utility'))
        or subcatStr:find('burnout') or nmLower:find('burnout')
        or nmLower:find('elemental') or nmLower:find('companion') or nmLower:find('minion') or nmLower:find('servant')
        or subcatStr:find('companion') or catStr:find('companion') or subcatStr:find('minion') or catStr:find('minion') then
        return 'pet'
    end

    -- Extract Beneficial status early
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

    -- Check player buffs / damage shields / haste spells (Celerity, Alacrity, Haste, Swift, Shield of Lava, etc.)
    if bene then
        if catStr:find('buff') or catStr:find('stat') or catStr:find('resist') or catStr:find('shield')
            or subcatStr:find('buff') or catStr:find('aura') or subcatStr:find('aura') or subcatStr:find('shield')
            or subcatStr:find('haste') or catStr:find('haste')
            or nmLower:find('shield') or nmLower:find('celerity') or nmLower:find('alacrity') or nmLower:find('haste') or nmLower:find('swift') then
            return 'buff'
        end
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
    if checkHasSPA(tloSpell, name, sp, 103) then return 'pet' end
    if checkHasSPA(tloSpell, name, sp, 32) or checkHasSPA(tloSpell, name, sp, 108) or checkHasSPA(tloSpell, name, sp, 33) then return
        'util' end
    if checkHasSPA(tloSpell, name, sp, 83) or checkHasSPA(tloSpell, name, sp, 88) or checkHasSPA(tloSpell, name, sp, 12) or checkHasSPA(tloSpell, name, sp, 41) or checkHasSPA(tloSpell, name, sp, 29) or checkHasSPA(tloSpell, name, sp, 30) then return
        'util' end
    if checkHasSPA(tloSpell, name, sp, 81) or checkHasSPA(tloSpell, name, sp, 91) then return 'util' end
    if checkHasSPA(tloSpell, name, sp, 18) or checkHasSPA(tloSpell, name, sp, 22) or checkHasSPA(tloSpell, name, sp, 31) then return
        'util' end
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

local KIND_LABEL = { dd = 'DD', dot = 'DoT', heal = 'Heal', buff = 'Buff', pet = 'Pet', util = 'Util', debuff = 'Debuff' }

local function filteredSpells(abbr)
    if not abbr then
        return {}, {}
    end
    local now = os.clock()
    local scribedOnly = ctrl and ctrl.scribed_only or false
    local myClassAbbr = nil
    pcall(function() myClassAbbr = mq.TLO.Me.Class.ShortName() end)
    local isMyClass = myClassAbbr and (abbr:upper() == myClassAbbr:upper())

    if filteredSpellsCache[abbr] and (now - lastFilteredCacheTime) < 2.0
        and lastFilterState.lvlMin == lvlMin
        and lastFilterState.lvlMax == lvlMax
        and lastFilterState.scribedOnly == scribedOnly then
        return filteredSpellsCache[abbr].names, filteredSpellsCache[abbr].lookup
    end

    local names, lookup = {}, {}
    local src = lookupSpells(abbr)
    for _, row in ipairs(src) do
        local nm, lv, bene, dbKind = row[1], row[2], row[3], row[4]
        local checkScribed = scribedOnly and isMyClass
        if not isDisciplineSpell(abbr, nm) then
            if lv >= lvlMin and lv <= lvlMax and (not checkScribed or isScribed(nm)) then
                local kind = mapTLOCategoryToKind(nil, nm)
                if not kind or kind == 'other' then kind = dbKind or 'other' end
                local label       = KIND_LABEL[kind]
                names[#names + 1] = label and string.format('%s  (L%d) [%s]', nm, lv, label)
                    or string.format('%s  (L%d)', nm, lv)
                lookup[#names]    = { name = nm, level = lv, bene = (bene == 1), kind = kind }
            end
        end
    end

    filteredSpellsCache[abbr] = { names = names, lookup = lookup }
    lastFilteredCacheTime = now
    lastFilterState = { lvlMin = lvlMin, lvlMax = lvlMax, scribedOnly = scribedOnly }
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
local SPECIAL_SKILLS = {
    Mnk = { 'Mend', 'Feign Death' },
}
local function isSpecialSkill(name)
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
local gemSyncWarned = {}
local lastGemSyncCheckAt = 0
local lastStuckRecoveryAt = nil       -- for the status panel: "recovered from being stuck Ns ago"
local lastCombatStallRecoveryAt = nil -- for the status panel: "recovered from a combat stall Ns ago"
local function checkGemMemSync()
    local now = os.clock()
    if (now - lastGemSyncCheckAt) < 10.0 then return end
    lastGemSyncCheckAt = now
    if mq.TLO.Window('SpellBookWnd').Open() then return end -- actively memming right now -- don't check mid-swap
    local activeGems = ctrl.buff_mode and loadout.buffGems or loadout.gems
    for i = 1, NUM_GEMS do
        local g = activeGems[i]
        if g and g.spell and g.spell ~= '' and not runtime.pendingMem[i] then
            local memmed
            pcall(function() memmed = mq.TLO.Me.Gem(i).Name() end)
            if memmed and memmed ~= '' and memmed ~= 'NULL' and memmed ~= g.spell then
                if not gemSyncWarned[i] then
                    gemSyncWarned[i] = true
                    print(string.format(
                        '\ay[Triune]\ax gem %d mismatch -- configured for "%s" but the bar actually has "%s" memmed there. '
                        .. 'It will never successfully cast/detect correctly like this -- use Mem All to Bar, or re-pick the spell for this gem.',
                        i, g.spell, memmed))
                end
            else
                gemSyncWarned[i] = nil -- resolved (or slot empty) -- allow a future mismatch to warn again
            end
        else
            gemSyncWarned[i] = nil
        end
    end
end

local function collectEntry()
    return {
        classes = myClasses,
        lvlMin = lvlMin,
        lvlMax = lvlMax,
        gems = loadout.gems,
        buffGems = loadout.buffGems,
        aas = loadout.aas,
        discs = loadout.discs,
        control = ctrl
    }
end
local function applyEntry(e)
    if type(e) ~= 'table' then return end
    if type(e.classes) == 'table' and #e.classes > 0 then myClasses = e.classes end
    lvlMin           = e.lvlMin or lvlMin; lvlMax = e.lvlMax or lvlMax
    loadout.gems     = e.gems or {}
    loadout.buffGems = e.buffGems or {}
    loadout.aas      = {}
    if type(e.aas) == 'table' then
        for k, v in pairs(e.aas) do
            if not tonumber(k) and type(v) == 'table' then
                loadout.aas[k] = v
            end
        end
    end
    loadout.discs = e.discs or {}
    if type(e.control) == 'table' then
        for k, v in pairs(e.control) do ctrl[k] = v end
        -- Migrate pre-3.6 saves (separate use_melee/use_ranged checkboxes) to the
        -- single combat_style radio -- old saves have no combat_style field at all.
        if not e.control.combat_style then
            ctrl.combat_style = e.control.use_ranged and 'Ranged' or 'Melee'
        end
        -- The combat anchor is a zone-specific position (like camp_loc): never
        -- restore it from a saved file because the player will almost certainly
        -- be in a different location or zone. They can set a new one in-game.
        ctrl.hunter_combat_loc    = nil
        ctrl.hunter_combat_radius = 0
    end
end

local function loadAll()
    local fn = loadfile(cfg .. '/triune_loadout.lua')
    if not fn then return end
    local ok, t = pcall(fn)
    if ok and type(t) == 'table' then
        ALLDATA = t
        if type(ALLDATA.__ignore) == 'table' then ignoreList = ALLDATA.__ignore end
    end
end

local function saveLoadout(silent)
    if myName then ALLDATA[myName] = collectEntry() end
    ALLDATA.__ignore = ignoreList
    local f = io.open(cfg .. '/triune_loadout.lua', 'w')
    if not f then return end
    f:write('return '); serialize(ALLDATA, f, 1); f:close()
    if not silent then print('\ag[Triune]\ax saved loadout for ' .. tostring(myName or '?') .. '.') end
end

-- ignore-list helpers: applies only to Hunter/Puller AUTO-targeting (see findRoamTarget
-- below); Assist and anything you target yourself are never filtered.
local function isIgnored(name)
    if not name or name == '' then return false end
    for _, n in ipairs(ignoreList) do if n == name then return true end end
    return false
end
local function addIgnore(name)
    if not name or name == '' or isIgnored(name) then return end
    table.insert(ignoreList, name)
    table.sort(ignoreList)
    saveLoadout(true)
    print('\ag[Triune]\ax added to ignore list: ' .. name)
end
local function removeIgnore(name)
    for i, n in ipairs(ignoreList) do
        if n == name then
            table.remove(ignoreList, i); break
        end
    end
    saveLoadout(true)
    print('\ag[Triune]\ax removed from ignore list: ' .. name)
end

-- lightweight signature of the loadout, for auto-save change detection
local function loadoutSig()
    local p = { table.concat(myClasses or {}, ','), tostring(lvlMin), tostring(lvlMax) }
    for i = 1, NUM_GEMS do
        local g = loadout.gems[i]
        p[#p + 1] = g and (tostring(g.cls) .. '~' .. tostring(g.spell) .. '~' .. tostring(g.target)
            .. '~' .. tostring(g.when) .. '~' .. tostring(g.pct) .. '~' .. tostring(g.burn_only)) or '-'
    end
    for i = 1, NUM_GEMS do
        local g = loadout.buffGems[i]
        p[#p + 1] = g and (tostring(g.cls) .. '~' .. tostring(g.spell) .. '~' .. tostring(g.target)
            .. '~' .. tostring(g.when) .. '~' .. tostring(g.pct) .. '~' .. tostring(g.burn_only)) or '-'
    end
    local keys = {}
    for nm in pairs(loadout.aas or {}) do keys[#keys + 1] = tostring(nm) end
    table.sort(keys)
    for _, nm in ipairs(keys) do
        local a = loadout.aas and loadout.aas[nm]
        if type(a) == 'table' then
            p[#p + 1] = nm ..
                '~' ..
                tostring(a.enabled) .. '~' .. tostring(a.target) .. '~' .. tostring(a.when) .. '~' .. tostring(a.pct)
                .. '~' .. tostring(a.burn_only)
        end
    end
    local dkeys = {}
    for nm in pairs(loadout.discs or {}) do dkeys[#dkeys + 1] = tostring(nm) end
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
    local c = ctrl.camp_loc
    local a = ctrl.hunter_combat_loc
    p[#p + 1] = table.concat({ ctrl.mode, tostring(ctrl.combat_style),
        tostring(ctrl.ranged_dist), tostring(ctrl.ma_name), tostring(ctrl.assist_at),
        tostring(ctrl.chase), tostring(ctrl.chase_dist), tostring(ctrl.automem),
        tostring(ctrl.hunter_radius), tostring(ctrl.hunter_z), tostring(ctrl
        .camp_radius), tostring(ctrl.camp_z),
        tostring(ctrl.pet_assist_at), tostring(ctrl.pet_hold_enabled), tostring(ctrl.show_map_radius),
        tostring(ctrl.nav_fallback_stick), tostring(ctrl.debug_mode), tostring(ctrl.buff_mode), tostring(ctrl.burn),
        tostring(ctrl
            .scribed_only),
        tostring(ctrl.aa_purchased_only), tostring(ctrl.disc_trained_only),
        tostring(ctrl.medbreak_enabled),
        tostring(ctrl.medbreak_hp_on), tostring(ctrl.medbreak_hp_start), tostring(ctrl.medbreak_hp_stop),
        tostring(ctrl.medbreak_mana_on), tostring(ctrl.medbreak_mana_start), tostring(ctrl.medbreak_mana_stop),
        tostring(ctrl.medbreak_end_on), tostring(ctrl.medbreak_end_start), tostring(ctrl.medbreak_end_stop),
        tostring(ctrl.cast_max_retries), tostring(ctrl.cast_lockout_sec), tostring(ctrl.min_mana_pct),
        c and string.format('%.1f,%.1f,%.1f', c.x, c.y, c.z) or 'nocamp',
        a and string.format('%.1f,%.1f,%.1f,r%d', a.x, a.y, a.z, ctrl.hunter_combat_radius or 0) or 'noanchor' }, '~')
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
    loadout = { gems = {}, buffGems = {}, aas = {}, discs = {} }
    ctrl = defaultCtrl()
    runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
    lvlMin, lvlMax = 1, 65
    if ALLDATA[myName] then
        applyEntry(ALLDATA[myName])
        scanKnownDiscs()
        local ok, prim = pcall(function() return mq.TLO.Me.Class.ShortName() end)
        local primAbbr = (ok and prim) and MQSHORT[tostring(prim):upper()] or nil
        -- Self-heal: discard any saved class slot that isn't the game-reported
        -- primary AND has zero supporting evidence -- catches the old bad
        -- fallback ('Rng'/'Brd') left over in a save from before this fix,
        -- without needing the user to remember to click Re-detect. Gated on
        -- DATA_OK -- classPlausible() reads DATA.spells/discs/aas, which are
        -- empty tables if triune_data.lua failed to load, so it would return
        -- false for EVERY class with no data present and this loop would
        -- wipe every non-primary class slot for the wrong reason (missing
        -- data, not an actually-bad save) and blame it on a stale save.
        if DATA_OK then
            for i = 1, 3 do
                if myClasses[i] and myClasses[i] ~= primAbbr and not classPlausible(myClasses[i]) then
                    print('\ay[Triune]\ax discarding saved class "' ..
                        myClasses[i] ..
                        '" -- no evidence found for it (likely a stale/incorrect save). Set it manually in Character Classes if it does not get redetected on its own.')
                    myClasses[i] = nil
                end
            end
        end
    else
        local detected = detectClasses()
        if detected then myClasses = detected end
        importCurrentGems() -- new character: seed the loadout from the current bar
    end
    -- Fallback to live inventory read only if no classes were loaded or detected
    if not myClasses or #myClasses == 0 then
        local liveClasses = classesFromInventoryWindow(false, true)
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
local function accent(c, txt) ImGui.TextColored(c[1], c[2], c[3], c[4], txt) end

-- UI: theme and style helpers
local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    local ImGuiColType = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiColType and ImGuiColType(id) or id
    if pcall(ImGui.PushStyleColor, enumVal, r, g, b, a) then _colN = _colN + 1 end
end
local function pushVar(id, a, b)
    if id == nil then return end
    local ok
    local ImGuiSVType = (mq.imgui and mq.imgui.StyleVar) or _G
        .ImGuiStyleVar ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiSVType and ImGuiSVType(id) or id
    if b ~= nil then
        local ImVec2Type = _G.ImVec2 or ImVec2
        if type(ImVec2Type) == 'function' then
            ok = pcall(ImGui.PushStyleVar, enumVal, ImVec2Type(a, b))
        else
            ok = pcall(ImGui.PushStyleVar, enumVal, a, b)
        end
    else
        ok = pcall(ImGui.PushStyleVar, enumVal, a)
    end
    if ok then _varN = _varN + 1 end
end

local function pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol or ImGuiCol ---@diagnostic disable-line: undefined-field
    local ImGuiStyleVar = (mq.imgui and mq.imgui.StyleVar) or _G.ImGuiStyleVar or
        ImGuiStyleVar ---@diagnostic disable-line: undefined-field
    if ImGuiCol then
        pushCol(ImGuiCol.WindowBg, 0.059, 0.086, 0.133, 1)
        pushCol(ImGuiCol.ChildBg, 0.055, 0.082, 0.125, 1)
        pushCol(ImGuiCol.PopupBg, 0.047, 0.075, 0.118, 1)
        pushCol(ImGuiCol.Border, 0.157, 0.251, 0.345, 1)
        pushCol(ImGuiCol.Text, 0.851, 0.898, 0.953, 1)
        pushCol(ImGuiCol.TextDisabled, 0.490, 0.561, 0.651, 1)
        pushCol(ImGuiCol.TitleBg, 0.043, 0.067, 0.106, 1)
        pushCol(ImGuiCol.TitleBgActive, 0.047, 0.078, 0.125, 1)
        pushCol(ImGuiCol.FrameBg, 0.047, 0.078, 0.125, 1)
        pushCol(ImGuiCol.FrameBgHovered, 0.090, 0.150, 0.220, 1)
        pushCol(ImGuiCol.FrameBgActive, 0.120, 0.190, 0.270, 1)
        pushCol(ImGuiCol.Button, 0.086, 0.125, 0.196, 1)
        pushCol(ImGuiCol.ButtonHovered, 0.300, 0.700, 1.000, 0.35)
        pushCol(ImGuiCol.ButtonActive, 0.300, 0.700, 1.000, 0.60)
        pushCol(ImGuiCol.Header, 0.078, 0.129, 0.204, 1)
        pushCol(ImGuiCol.HeaderHovered, 0.160, 0.440, 0.700, 0.50)
        pushCol(ImGuiCol.HeaderActive, 0.160, 0.500, 0.750, 0.70)
        pushCol(ImGuiCol.Tab, 0.043, 0.067, 0.098, 1)
        pushCol(ImGuiCol.TabHovered, 0.300, 0.700, 1.000, 0.40)
        pushCol(ImGuiCol.TabSelected, 0.075, 0.125, 0.200, 1)
        pushCol(ImGuiCol.CheckMark, 0.370, 0.880, 0.640, 1)
        pushCol(ImGuiCol.SliderGrab, 1.000, 0.700, 0.540, 1)
        pushCol(ImGuiCol.SliderGrabActive, 1.000, 0.550, 0.300, 1)
        pushCol(ImGuiCol.Separator, 0.157, 0.251, 0.345, 1)
        pushCol(ImGuiCol.ScrollbarBg, 0.031, 0.051, 0.078, 1)
        pushCol(ImGuiCol.ScrollbarGrab, 0.157, 0.251, 0.345, 1)
    end
    if ImGuiStyleVar then
        local ImGuiSV = ImGuiStyleVar
        pushVar(ImGuiSV.WindowRounding, 6)
        pushVar(ImGuiSV.ChildRounding, 5)
        pushVar(ImGuiSV.FrameRounding, 4)
        pushVar(ImGuiSV.PopupRounding, 4)
        pushVar(ImGuiSV.TabRounding, 4)
        pushVar(ImGuiSV.GrabRounding, 3)
        pushVar(ImGuiSV.ScrollbarRounding, 6)

        pushVar(ImGuiSV.FrameBorderSize, 1)
        pushVar(ImGuiSV.FramePadding, 7, 4)
        pushVar(ImGuiSV.ItemSpacing, 8, 6)
        pushVar(ImGuiSV.WindowPadding, 12, 10)
    end
end

local function popTheme()
    if _varN > 0 then
        pcall(ImGui.PopStyleVar, _varN); _varN = 0
    end
    if _colN > 0 then
        pcall(ImGui.PopStyleColor, _colN); _colN = 0
    end
end

-- Renders the Triune sigil (outer ring + inner triangle + three class-colored
-- nodes) at the cursor, matching the site emblem: top node = slot 1 (arcane),
-- bottom-right = slot 2 (ember), bottom-left = slot 3 (jade). Node colors track
-- your actual gestalt trio via SLOT_COLORS/classColor. Every draw call is
-- pcall-guarded so an unsupported binding can't take the header down with it.
-- UI: header emblem
local function drawEmblem(size)
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

local UI = {}

function UI.drawHeaderBar()
    drawEmblem(22)
    ImGui.SameLine()
    accent(GOLD, 'TRIUNE')
    ImGui.SameLine(); accent(MUTED, '> AutoCombat')
    ImGui.SameLine(); accent(ARC, myName or '(no character)')
    ImGui.SameLine(); ImGui.TextDisabled(string.format('| %s / %s / %s',
        myClasses[1] or '?', myClasses[2] or '?', myClasses[3] or '?'))
    ImGui.SameLine(); ImGui.TextDisabled(string.format('| PoP exp %d | v%s',
        DATA.era_expansion or 5, VERSION))
    ImGui.SameLine()
    if ImGui.Button('Open Spellbook##hdrBook') then
        local s = mq.TLO.Lua.Script('triune_spellbook')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/lua stop triune_spellbook')
        else
            mq.cmd('/lua run triune_spellbook')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Spellbook interface.')
    end
    ImGui.SameLine()
    if ImGui.Button('Cursor Manager##hdrCursor') then
        local s = mq.TLO.Lua.Script('triune_cursor')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/lua stop triune_cursor')
        else
            mq.cmd('/lua run triune_cursor')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or closes the standalone Triune Cursor Item Manager.')
    end
    ImGui.SameLine()
    if ImGui.Button('DPS Parser##hdrDPS') then
        local s = mq.TLO.Lua.Script('triune_dps')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/dps toggle')
        else
            mq.cmd('/lua run triune_dps')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Launches or toggles the standalone Triune DPS Parser window.')
    end
    if not DATA_OK then
        accent(WARN,
            'No triune_data.lua found in your MQ config folder -- run extract_spells.py and copy it there. Spell/AA lists will be empty.')
    end
    ImGui.Separator()
end

function UI.drawClassPicker()
    if ImGui.CollapsingHeader('Character Classes & Loadout') then
        ImGui.TextDisabled('Auto-detected on login; adjust if needed (saved per character):')
        for i = 1, 3 do
            ImGui.SetNextItemWidth(90)
            local defaultClass = myClasses[1] or 'War'
            local currentVal = myClasses[i]
            local idx = currentVal and idxOf(ALL_ABBR, currentVal) or (i == 1 and idxOf(ALL_ABBR, defaultClass) or nil)
            if idx then
                local newIdx = ImGui.Combo('##cls' .. i, idx, ALL_ABBR)
                myClasses[i] = ALL_ABBR[newIdx]
            else
                -- If slot i is unassigned (e.g. single-class or 2-class toon), show empty/selectable combo without defaulting to War/Rng/Brd
                local newIdx = ImGui.Combo('##cls' .. i, 1, ALL_ABBR)
                if currentVal then myClasses[i] = ALL_ABBR[newIdx] end
            end
            ImGui.SameLine()
        end
        if ImGui.Button('Re-detect') then reDetectRequested = true end
        ImGui.Dummy(0, 4)
        if ImGui.Button('Save Loadout', 140, 24) then saveLoadout() end
        ImGui.SameLine(); ImGui.TextDisabled('-> triune_loadout.lua (auto-saves on changes)')
        accent(MUTED,
            'Detected from your scribed spells, trained discs, AND AAs. Run the full extractor (all 16 classes) so every class -- including melee -- can be matched.')
        ImGui.Dummy(0, 2)
    end
end

-- "Up top" so it's reachable from any tab -- if Hunter/Puller swings on a
-- friendly NPC, one click stops it and remembers forever (shared across all
-- your characters).
function UI.drawIgnoreTab()
    if not ImGui.BeginTabItem('Ignore List') then return end
    ImGui.Dummy(0, 4)
    accent(MUTED, 'Hunter / Puller will never auto-target these names.')
    accent(MUTED, 'Only filters auto-targeting -- Assist and anything you target yourself are never blocked.')
    ImGui.Dummy(0, 4)

    if ImGui.Button('Ignore Current Target', 200, 26) then
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
    ImGui.SetNextItemWidth(220)
    ignoreInput = ImGui.InputText('##ignoreAdd', ignoreInput)
    ImGui.SameLine()
    if ImGui.Button('Add##ignoreAddBtn') then
        if ignoreInput ~= '' then
            addIgnore(ignoreInput); ignoreInput = ''
        end
    end
    ImGui.Dummy(0, 6)
    ImGui.Separator()

    if #ignoreList == 0 then
        ImGui.TextDisabled('(empty)')
    else
        for i, nm in ipairs(ignoreList) do
            ImGui.PushID('ig' .. i)
            if ImGui.Button('x') then removeIgnore(nm) end
            ImGui.SameLine(); ImGui.Text(nm)
            ImGui.PopID()
        end
    end
    ImGui.EndTabItem()
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
                { cmd = '/ac run',              desc = 'Start / unpause auto-combat execution' },
                { cmd = '/ac pause / /ac stop', desc = 'Pause auto-combat execution & halt movement' },
                { cmd = '/ac burn [on|off]',    desc = 'Toggle burn mode (enables "Burn Only" spells, AAs, discs)' },
                { cmd = '/ac status',           desc = 'Print current running state and combat mode to chat' },
                { cmd = '/ac spellbook',        desc = 'Toggle the standalone spellbook & auto-memorization queue window' },
                { cmd = '/ac cursorui',         desc = 'Toggle the standalone cursor item manager window' },
                { cmd = '/ac clearcursor',      desc = 'Clear item on cursor (autoinventory / drop / destroy per rules)' },
                { cmd = '/ac dps / /dps',       desc = 'Toggle or launch the standalone DPS Parser window' },
                { cmd = '/dps compact',         desc = 'Toggle auto-resizing Compact Mini-Window HUD mode' },
                { cmd = '/dps report [chan]',   desc = 'Report combat statistics to /group, /say, /guild, or /raid' },
                { cmd = '/dps reset',           desc = 'Reset active combat damage counters' },
                { cmd = '/ac <mode>',           desc = 'Switch combat mode (e.g. /ac assist, /ac hunter, /ac tank)' },
                { cmd = '/triunerun',           desc = 'Quick keybind command to toggle run / pause' },
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
            ImGui.TableSetupColumn('Mode', ImGuiTableColumnFlags.WidthFixed, 140)
            ImGui.TableSetupColumn('Behavior Description', ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            for _, modeName in ipairs(MODES) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                accent(GOOD, modeName)
                ImGui.TableNextColumn()
                ImGui.TextWrapped(MODE_DESC[modeName] or '')
            end
            ImGui.EndTable()
        end
    end

    ImGui.EndTabItem()
end

-- Shared row-rendering for both the Spell Gems tab and the Buff Loadout tab --
-- same class -> spell -> target -> when -> percent picker either way, just
-- pointed at a different 12-slot table. isActiveSet gates auto-mem-on-pick so
-- editing the INACTIVE set (planning ahead) never clobbers whatever's actually
-- memmed right now; only editing the currently-active set mems immediately.
-- UI: spell/gem list editor
function UI.drawGemList(gemsTable, idPrefix, isActiveSet, allowBurn)
    if allowBurn == nil then allowBurn = true end
    if ImGui.BeginChild('gemlist_' .. idPrefix, ImVec2(0, 0), nil, 0) then
        for i = 1, NUM_GEMS do
            ImGui.PushID(idPrefix .. i)
            local g = gemsTable[i]
            local cls = g and g.cls or nil

            ImGui.Text(string.format('%2d', i)); ImGui.SameLine()

            -- class combo (none + trio)
            local classOpts = { '--' }
            for _, c in ipairs(myClasses) do classOpts[#classOpts + 1] = c end
            local curCi = cls and idxOf(classOpts, cls) or 1
            ImGui.SetNextItemWidth(64)
            local ci = ImGui.Combo('##c', curCi, classOpts)
            local newCls = (ci > 1) and classOpts[ci] or nil
            if newCls ~= cls then
                if newCls then
                    gemsTable[i] = { cls = newCls, spell = nil, target = 'F: Myself', when = 'always', pct = 0 }
                else
                    gemsTable[i] = nil
                end
                g = gemsTable[i]; cls = newCls
            end

            if cls then
                if not classHasSpells(cls) then
                    ImGui.SameLine(); accent(MUTED, '  ' .. cls .. ' has no gem spells (melee) -> Abilities tab')
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
                    g.target = TARGETS[ti]

                    -- when
                    ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                    local wi = ImGui.Combo('##w', idxOf(WHENS, g.when or 'always'), WHENS)
                    g.when = WHENS[wi]

                    -- percent: draggable slider that shows the value (only meaningful
                    -- for %-based triggers; harmless otherwise)
                    ImGui.SameLine(); ImGui.SetNextItemWidth(80)
                    g.pct = ImGui.SliderInt('##p', g.pct or 0, 0, 100, '%d%%')
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

-- Header controls shared by both gem tabs: level band, auto-mem, import, and the
-- "Mem All to Bar" button that both memorizes this set AND makes it the active
-- one (ctrl.buff_mode follows whichever tab you last hit that button on).
function UI.drawGemTabHeader(gemsTable, isBuffSet)
    ImGui.Dummy(0, 4)
    ImGui.TextDisabled('Level band:')
    ImGui.SameLine(); ImGui.SetNextItemWidth(110)
    lvlMin = ImGui.InputInt('##lmin' .. (isBuffSet and 'b' or ''), lvlMin); if lvlMin < 1 then lvlMin = 1 end
    ImGui.SameLine(); ImGui.Text('to'); ImGui.SameLine(); ImGui.SetNextItemWidth(110)
    lvlMax = ImGui.InputInt('##lmax' .. (isBuffSet and 'b' or ''), lvlMax); if lvlMax > 65 then lvlMax = 65 end
    if lvlMin > lvlMax then lvlMin = lvlMax end
    ImGui.SameLine(); ImGui.TextDisabled('(spells learned in this band)')
    ctrl.scribed_only = ImGui.Checkbox('Scribed Only', ctrl.scribed_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show spells actually in your spellbook, not every spell your\nclass could ever learn in this level range. Updates live the moment\nyou scribe something new. Turn off to browse/plan ahead.')
    end
    ImGui.SameLine()
    ctrl.automem = ImGui.Checkbox('Auto-mem on pick', ctrl.automem)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'When on, choosing a spell for a gem in the ACTIVE set immediately /memspell-s it into that slot (out of combat).')
    end
    ImGui.SameLine()
    if ImGui.Button('Import Memmed Gems') then
        if ctrl.buff_mode ~= isBuffSet then
            print(
                '\ay[Triune]\ax warning: your bar right now is memmed for the OTHER loadout -- imported that instead of this one.')
        end
        importCurrentGems(gemsTable)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Read the spells already on your gem bar into this loadout -- no re-memming. Only accurate if this is the currently active/memmed set.')
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
            ctrl.buff_mode = isBuffSet
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Memorizes every gem in THIS list onto your bar and makes it the active loadout the combat engine casts from. Takes a few seconds per gem -- out of combat only.')
    end
    if pendingCount > 0 then
        ImGui.SameLine(); accent(WARN, string.format('memming... %d queued', pendingCount))
    end
    local activeName = ctrl.buff_mode and 'Buff Loadout' or 'Spell Gems'
    accent(ctrl.buff_mode == isBuffSet and GOOD or MUTED,
        (ctrl.buff_mode == isBuffSet) and ('ACTIVE -- the engine is currently casting from ' .. activeName)
        or ('inactive -- currently casting from ' .. activeName .. " (this tab's spells aren't memmed right now)"))
    ImGui.Separator()
end

function UI.drawGemTab()
    if not ImGui.BeginTabItem('Spell Gems') then return end
    UI.drawGemTabHeader(loadout.gems, false)
    UI.drawGemList(loadout.gems, 'gem', not ctrl.buff_mode, true)
    ImGui.EndTabItem()
end

function UI.drawBuffTab()
    if not ImGui.BeginTabItem('Buff Loadout') then return end
    accent(MUTED,
        'A second gem set for pet summons / buffs that don\'t fit alongside your combat spells -- e.g. Nec/Mag pet summons, Bst buffs. Build it here, hit Mem All to Bar to swap it onto your bar, buff up, then switch back on the Spell Gems tab.')
    UI.drawGemTabHeader(loadout.buffGems, true)
    UI.drawGemList(loadout.buffGems, 'bgem', ctrl.buff_mode, false)
    ImGui.EndTabItem()
end

local TIER_LABEL = { short = 'Short  (<= 1 min)', mid = 'Sustained  (1-5 min)', burn = 'Burn  (5 min+)' }
local TIER_ORDER = { 'short', 'mid', 'burn' }

-- UI: activated AAs tab
function UI.drawAATab()
    if not ImGui.BeginTabItem('Abilities & AAs') then return end
    ImGui.Dummy(0, 4)
    ImGui.TextWrapped('Activated AAs (each has its own timer -- all fire when ready). Grouped by cooldown.')
    ctrl.aa_purchased_only = ImGui.Checkbox('Purchased Only', ctrl.aa_purchased_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show AAs you\'ve actually bought a rank in, not every AA your\nclass could ever train. Updates live as you spend AA points. Turn\noff to browse/plan ahead.')
    end
    ImGui.Separator()

    if ImGui.BeginChild('aalist', ImVec2(0, 0), nil, 0) then
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
                                ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls) ---@diagnostic disable-line: param-type-mismatch
                                ImGui.SameLine(); ImGui.Text(nm)
                                ImGui.SameLine(); ImGui.TextDisabled('(' .. fmtSec(secNum) .. ')')
                                if entry.enabled then
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                                    local ti = ImGui.Combo('##aat', idxOf(TARGETS, entry.target), TARGETS)
                                    entry.target = TARGETS[ti]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                                    local wi = ImGui.Combo('##aaw', idxOf(WHENS, entry.when), WHENS)
                                    entry.when = WHENS[wi]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(80)
                                    entry.pct = ImGui.SliderInt('##aap', entry.pct or 30, 0, 100, '%d%%')
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(45)
                                    local curXt = tonumber(entry.min_xtar) or 1
                                    if curXt < 1 then curXt = 1 end
                                    if curXt > 10 then curXt = 10 end
                                    local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                                    local xti = ImGui.Combo('##aamxt', curXt, xtOpts)
                                    entry.min_xtar = xti
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip('Minimum number of active NPCs on XTarget required for this AA to fire.')
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
    ctrl.disc_trained_only = ImGui.Checkbox('Trained Only', ctrl.disc_trained_only)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Only show disciplines you\'ve actually trained, not every disc your\nclass could ever learn. Updates live as you train new ones. Turn\noff to browse/plan ahead.')
    end
    ImGui.Separator()
    if ImGui.BeginChild('disclist', ImVec2(0, 0), nil, 0) then
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
                    ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls) ---@diagnostic disable-line: param-type-mismatch
                    ImGui.SameLine(); ImGui.Text(nm)
                    ImGui.SameLine(); ImGui.TextDisabled('(L' .. lv .. ')')
                    if entry.enabled then
                        ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                        local ti = ImGui.Combo('##dt', idxOf(TARGETS, entry.target), TARGETS)
                        entry.target = TARGETS[ti]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                        local wi = ImGui.Combo('##dw', idxOf(WHENS, entry.when), WHENS)
                        entry.when = WHENS[wi]
                        ImGui.SameLine(); ImGui.SetNextItemWidth(80)
                        local dpVal = ImGui.SliderInt('##dp', entry.pct or 30, 0, 100, '%d%%')
                        entry.pct = dpVal
                        ImGui.SameLine(); ImGui.SetNextItemWidth(45)
                        local curXt = tonumber(entry.min_xtar) or 1
                        if curXt < 1 then curXt = 1 end
                        if curXt > 10 then curXt = 10 end
                        local xtOpts = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
                        local xti = ImGui.Combo('##dmxt', curXt, xtOpts)
                        entry.min_xtar = xti
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Minimum number of active NPCs on XTarget required for this discipline to fire.')
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
        if not anyDisc then ImGui.TextDisabled('  (none for your classes)') end
    end
    ImGui.EndChild()
    ImGui.EndTabItem()
end

local function setManualHunterPetHold(on, force)
    if on then
        if force or petState.manualHunterHold ~= true then
            mq.cmd('/say #petcmd ghold on')
            petState.manualHunterHold = true
        end
    else
        if force or petState.manualHunterHold ~= false then
            mq.cmd('/say #petcmd ghold off')
            petState.manualHunterHold = false
        end
    end
end

local isCombat -- forward declaration; defined in the engine section below

-- UI: control/settings tab
function UI.drawControlTab()
    if not ImGui.BeginTabItem('Control') then return end
    if ctrl.running then
        local ImGuiColType = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
        local getCol = function(id) return ImGuiColType and ImGuiColType(id) or id end
        local pCount = 0
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Button), 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonHovered), 0.18, 0.70, 0.28, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonActive), 0.08, 0.40, 0.15, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Text), 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

        if ImGui.Button('PAUSE', 150, 30) then
            if ctrl.mode == 'Manual Hunter' then
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
        local ImGuiColType = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
        local getCol = function(id) return ImGuiColType and ImGuiColType(id) or id end
        local pCount = 0
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Button), 0.65, 0.15, 0.15, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonHovered), 0.80, 0.22, 0.22, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonActive), 0.50, 0.10, 0.10, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Text), 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

        if ImGui.Button('START', 150, 30) then ctrl.running = true end

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

        local ImGuiColType = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
        local getCol = function(id) return ImGuiColType and ImGuiColType(id) or id end
        local pCount = 0
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Button), r, g, b, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonHovered), rH, gH, bH, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.ButtonActive), 0.70, 0.00, 0.00, 1.0) then pCount = pCount + 1 end
        if pcall(ImGui.PushStyleColor, getCol(ImGuiCol.Text), 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end

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
    accent(GOLD, 'Mode')
    ImGui.SetNextItemWidth(220)
    local modeIdx = ImGui.Combo('##mode', idxOf(MODES, ctrl.mode), MODES)
    local newMode = MODES[modeIdx]
    if newMode ~= ctrl.mode then
        if ctrl.mode == 'Manual Hunter' and newMode ~= 'Manual Hunter' then
            setManualHunterPetHold(false)
        elseif newMode == 'Manual Hunter' then
            if not ctrl.running or not isCombat() then
                setManualHunterPetHold(true, true)
            end
        end
        ctrl.mode = newMode
    end
    accent(MUTED, MODE_DESC[ctrl.mode] or '')

    local usesMA   = (ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist'
        or ctrl.mode == 'Backline' or ctrl.mode == 'Tank')
    local usesCamp = (ctrl.mode == 'Puller' or ctrl.mode == 'Pull & Assist' or ctrl.mode == 'Garrison'
        or ctrl.mode == 'Assist' or ctrl.mode == 'Tank')

    if ctrl.mode == 'Hunter' or ctrl.mode == 'Pet Tank' then
        accent(ARC, ctrl.mode)
        ImGui.SetNextItemWidth(180)
        ctrl.hunter_radius = ImGui.SliderInt('Search Radius', ctrl.hunter_radius or 1500, 50, 2000)
        ImGui.SetNextItemWidth(180)
        ctrl.hunter_z = ImGui.SliderInt('Max Height Diff (Z)', ctrl.hunter_z or 75, 10, 300)
        ImGui.SetNextItemWidth(180)
        ctrl.hunter_min_level = ImGui.SliderInt('Min NPC Level', ctrl.hunter_min_level or 1, 1, 100)
        ImGui.SameLine()
        ImGui.SetNextItemWidth(180)
        ctrl.hunter_max_level = ImGui.SliderInt('Max NPC Level', ctrl.hunter_max_level or 100, 1, 100)
        if ctrl.hunter_min_level > ctrl.hunter_max_level then ctrl.hunter_min_level = ctrl.hunter_max_level end

        ctrl.check_closer_mobs = ImGui.Checkbox('Check for Closer NPCs while Traveling##hunter', ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('While traveling to a distant target, check once for newly visible or spawning NPCs\nthat are significantly closer and switch to them.')
        end

        -- Combat Radius anchor -- keeps Hunter from roaming the whole world
        ImGui.Dummy(0, 2)
        accent(GOLD, 'Combat Radius (optional)')
        if ctrl.hunter_combat_loc then
            ImGui.Text(string.format('Anchor: %.1f, %.1f, %.1f',
                ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.y, ctrl.hunter_combat_loc.z))
        else
            accent(MUTED, 'No anchor set -- Hunter roams freely.')
        end

        if ImGui.Button('Set Anchor##hunter') then
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
            ImGui.SetTooltip(
                'Saves your current position as the anchor.\nHunter will only wander and find mobs within the Combat Radius of this point.')
        end
        ImGui.SameLine()
        if ImGui.Button('Clear Anchor##hunter') then
            ctrl.hunter_combat_loc = nil
            pursuit.wanderLoc = nil -- ditch any wander-point that might be outside the old zone
            if updateMapRadiusVisuals then updateMapRadiusVisuals() end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Remove the anchor -- Hunter will roam freely again.')
        end

        -- Radius slider (editable whether an anchor is set or not)
        ImGui.SetNextItemWidth(220)
        local curRadius = (ctrl.hunter_combat_radius and ctrl.hunter_combat_radius > 0) and ctrl.hunter_combat_radius or
        250
        local newRadius, changed = ImGui.SliderInt('Combat Radius##hunter', curRadius, 1, 2000)
        if changed then
            ctrl.hunter_combat_radius = newRadius
            if updateMapRadiusVisuals then updateMapRadiusVisuals() end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Maximum distance from the anchor the Hunter will roam\n'
                .. 'and search for targets. Mobs outside this radius are ignored.\n'
                .. 'Takes effect whenever an anchor location is set.')
        end
    end

    if usesMA then
        accent(GOLD, 'Main Assist')
        ImGui.SetNextItemWidth(160)
        ctrl.ma_name = ImGui.InputText('MA Name', ctrl.ma_name or '')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Character to assist. Leave blank to assist group leader.') end
        ImGui.SetNextItemWidth(160)
        local assistVal = ImGui.SliderInt('Assist At %', ctrl.assist_at or 98, 1, 100, '%d%%')
        ctrl.assist_at = assistVal

        ctrl.chase = ImGui.Checkbox('Chase MA', ctrl.chase)
        if ctrl.chase then
            ImGui.SameLine(); ImGui.SetNextItemWidth(140)
            ctrl.chase_dist = ImGui.SliderInt('Chase Range', ctrl.chase_dist or 15, 5, 100)
        end
    end

    if usesCamp then
        accent(GOLD, 'Camp Location')
        if ctrl.camp_loc then
            ImGui.Text(string.format('Camp set at: %.1f, %.1f, %.1f',
                ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z))
        else
            accent(WARN, 'No camp location set.')
        end

        if ImGui.Button('Set Here') then
            local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
            if mx and my and mz then ctrl.camp_loc = { x = mx, y = my, z = mz } end
        end
        ImGui.SameLine()
        if ImGui.Button('Clear Camp') then
            ctrl.camp_loc = nil; runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Also wipes any other map circles (e.g. an old one\nleft over from before camp-clearing was fixed).')
        end

        if ctrl.mode == 'Garrison' then
            accent(MUTED,
                'Garrison holds this camp spot and reactively tanks whatever aggros. It returns here whenever idle.')
        end

        if ctrl.mode == 'Puller' or ctrl.mode == 'Pull & Assist' then
            ImGui.SetNextItemWidth(180)
            ctrl.camp_radius = ImGui.SliderInt('Pull Radius', ctrl.camp_radius or 100, 10, 500)

            ImGui.SetNextItemWidth(180)
            ctrl.camp_z = ImGui.SliderInt('Pull Height Diff (Z)', ctrl.camp_z or 75, 10, 300)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Ignores mobs more than this far above or below camp --\nkeeps it from dragging back something from another\nfloor, ledge, or balcony.')
            end

            ImGui.SetNextItemWidth(180)
            ctrl.pull_min_level = ImGui.SliderInt('Min NPC Level', ctrl.pull_min_level or 1, 1, 100)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(180)
            ctrl.pull_max_level = ImGui.SliderInt('Max NPC Level', ctrl.pull_max_level or 100, 1, 100)
            if ctrl.pull_min_level > ctrl.pull_max_level then ctrl.pull_min_level = ctrl.pull_max_level end

            ctrl.check_closer_mobs = ImGui.Checkbox('Check for Closer NPCs while Traveling##puller', ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('While traveling out to pull a mob, check once for newly visible or spawning NPCs\nthat are significantly closer and switch to them.')
            end
        end
    end

    ImGui.EndTabItem()
end

function UI.drawSettingsTab()
    if not ImGui.BeginTabItem('Settings') then return end
    ImGui.Dummy(0, 4)

    accent(GOLD, 'Combat Style')
    if ImGui.RadioButton('Melee', ctrl.combat_style == 'Melee') then ctrl.combat_style = 'Melee' end
    ImGui.SameLine()
    if ImGui.RadioButton('Ranged (bow)', ctrl.combat_style == 'Ranged') then ctrl.combat_style = 'Ranged' end
    ImGui.SameLine()
    if ImGui.RadioButton('Spell', ctrl.combat_style == 'Spell') then ctrl.combat_style = 'Spell' end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Spell: stand off at the range below and never auto-attack (no\n'
            .. '/attack, no /autofire) -- your Spell Gems loadout does all the\n'
            .. 'damage. For pure caster trios that don\'t melee or carry a bow.')
    end
    if ctrl.combat_style ~= 'Melee' then
        ImGui.SameLine(); ImGui.SetNextItemWidth(140)
        ctrl.ranged_dist = ImGui.SliderInt('Range##ranged', ctrl.ranged_dist or 40, 15, 200)
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
    local lockoutVal = ImGui.SliderInt('Lockout Time (s)##cls', ctrl.cast_lockout_sec or 30, 5, 300, '%d s')
    ctrl.cast_lockout_sec = lockoutVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('How many seconds to wait before trying a locked-out spell again.\nDefault: 30 seconds.')
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Mana Management')
    ImGui.SetNextItemWidth(180)
    local minManaVal = ImGui.SliderInt('Min Mana %##mmp', ctrl.min_mana_pct or 0, 0, 95, '%d%%')
    ctrl.min_mana_pct = minManaVal
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Prevents automatic spell casting if current mana drops below this percentage.\n'
            .. 'Ignored during Burn Mode (0 = disabled / cast at any mana level).')
    end

    ImGui.Dummy(0, 4)
    -- Pet Settings: shown only when the trio has a pet class
    if trioHasPetClass() then
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

local function draw()
    if not open then return end
    pushTheme()
    ImGui.SetNextWindowSize(720, 640, ImGuiCond.FirstUseEver)
    local show
    open, show = ImGui.Begin('Triune AutoCombat##triune', open)
    if not show then
        ImGui.End(); popTheme(); return
    end

    UI.drawHeaderBar()
    UI.drawClassPicker()

    if ImGui.BeginTabBar('triuneTabs') then
        UI.drawControlTab()
        UI.drawSettingsTab()
        UI.drawGemTab()
        UI.drawBuffTab()
        UI.drawAATab()
        UI.drawDiscTab()
        UI.drawIgnoreTab()
        UI.drawHelpTab()
        ImGui.EndTabBar()
    end

    ImGui.End()
    popTheme()
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
    if s.Type() == 'NPC' and (s.PctHPs() or 0) <= 0 then return false end
    if mq.TLO.Target.ID() == id then return true end
    mq.cmdf('/target id %d', id)
    local t = 0
    while mq.TLO.Target.ID() ~= id and t < 300 do
        mq.delay(20); t = t + 20
    end
    return mq.TLO.Target.ID() == id
end


isCombat = function()
    if mq.TLO.Me.Combat() then return true end
    if mq.TLO.Me.CombatState() == 'COMBAT' then return true end
    local t = mq.TLO.Target
    if t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0 and not t.Dead() then return true end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' and (xt.PctHPs() or 0) > 0 and not xt.Dead() then return true end
    end
    return false
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
        print('\ao[Triune debug]\ax looking for buff "' ..
            tostring(name) .. '" -- ' .. (isMe and 'MyBuffCount' or 'BuffCount') .. '=' .. cnt
            ..
            ' active=[' ..
            table.concat(activeNames, ', ') ..
            '] Buff("name")=' .. directName)
    end
    return found
end
local function buffActive(id, name)
    if not id or id == 0 then return false end
    if id == mq.TLO.Me.ID() then
        if hasNamedBuff(mq.TLO.Me, name, true) then return true end
        if tloTrue(function() return mq.TLO.Me.Song(name)() end) then return true end
        return false
    end
    local total = mq.TLO.Group.Members() or 0
    for i = 0, total do
        local m = mq.TLO.Group.Member(i)
        if m and m() and m.ID() == id then
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
    return false
end

local function lowestHpAlly()
    local bestId, bestHp = mq.TLO.Me.ID(), (mq.TLO.Me.PctHPs() or 100)
    local total = mq.TLO.Group.Members() or 0
    for i = 0, total do
        local m = mq.TLO.Group.Member(i)
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

local function firstNPCXtarget(unmezzedOnly)
    return findFirstNPCXtarget(unmezzedOnly, isIgnored, isUnreachable)
end

-- Returns count of live (PctHPs > 0), non-ignored, reachable NPCs occupying XTarget slots.
local function countNPCXtarget()
    local cnt = 0
    pcall(function()
        local count = mq.TLO.Me.XTarget() or 0
        for i = 1, count do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() then
                local id = xt.ID() or 0
                if id > 0 and isSpawnAlive(id) then
                    local s = mq.TLO.Spawn(id)
                    local stype = (s() and s.Type()) or ''
                    if (stype == 'NPC' or stype == 'Pet')
                        and (s.PctHPs() or 0) > 0 and not s.Dead()
                        and not isIgnored(s.CleanName())
                        and not isUnreachable(id) then
                        cnt = cnt + 1
                    end
                end
            end
        end
    end)
    -- Fallback: if XTarget list is unpopulated or empty, but we have a valid live NPC target, count as at least 1
    if cnt == 0 then
        pcall(function()
            local t = mq.TLO.Target
            if t() and (t.ID() or 0) > 0 then
                local stype = t.Type() or ''
                if (stype == 'NPC' or stype == 'Pet') and (t.PctHPs() or 0) > 0 and not t.Dead()
                    and not isIgnored(t.CleanName()) and not isUnreachable(t.ID()) then
                    cnt = 1
                end
            end
        end)
    end
    return cnt
end

-- Returns true if any live (PctHPs > 0), non-ignored, reachable NPC occupies
-- an XTarget slot. Used by Hunter mode to decide whether it is safe to roam
-- for a fresh mob: if the XTarget list still has live hostiles from the
-- current or recent fight, Hunter must finish those before wandering away.
local function anyXtarAlive()
    return countNPCXtarget() > 0
end

local function isXTargetId(id)
    if not id or id <= 0 then return false end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) == id
            and (xt.PctHPs() or 0) > 0 and not xt.Dead()
            and not isIgnored(xt.CleanName())
            and not isUnreachable(id) then
            local stype = xt.Type() or ''
            if stype == 'NPC' or stype == 'Pet' then
                return true
            end
        end
    end
    return false
end

-- Returns true if spawn ID is self, player pet, group member pet, player character, or pet of a master
local function isSpawnPetOrPlayer(id)
    if not id or id <= 0 then return false end
    if id == mq.TLO.Me.ID() then return true end
    if id == (mq.TLO.Me.Pet.ID() or 0) then return true end
    for _, petId in pairs(petState.myPets) do
        if petId == id then return true end
    end
    local s = mq.TLO.Spawn(id)
    if not s() then return false end
    local stype = s.Type() or ''
    if stype == 'PC' then return true end
    local hasMaster = false
    pcall(function() hasMaster = s.Master() and (s.Master.ID() or 0) > 0 end)
    if hasMaster then return true end
    return false
end

-- Returns true when the given spawn ID is a confirmed hostile target that
-- should receive offensive actions (spells, AAs, discs, auto-attack).
-- Prevents the engine from accidentally casting on friendly NPCs (merchants,
-- quest givers, guards, bankers) that happen to be targeted.
local function isHostileTarget(id)
    if not id or id <= 0 then return false end
    -- On XTarget list (mob is aggroed on us or group)
    if isXTargetId(id) then return true end
    -- Player is actively attacking this target
    local curTargetId = mq.TLO.Target.ID() or 0
    if curTargetId == id then
        if isSpawnPetOrPlayer(id) then return false end
        if mq.TLO.Me.Combat() then return true end
        if mq.TLO.Me.AutoFire() then return true end
        -- Player has aggro on this target (target-of-target points back at us)
        local myId = mq.TLO.Me.ID() or 0
        if myId > 0 then
            local totId = 0
            pcall(function() totId = mq.TLO.Target.TargetOfTarget.ID() or 0 end)
            if totId == myId then return true end
        end
    end
    -- NPC is already damaged (being fought by someone), but not a pet or player
    if not isSpawnPetOrPlayer(id) then
        local hp = pctHP(id) or 100
        if hp < 100 then return true end
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

local function maPcId()
    return findMaPcId(ctrl and ctrl.ma_name)
end

local function targetIsEngaged(id)
    if not id then return false end
    local s = mq.TLO.Spawn(id)
    if not s() then return false end
    return (s.PctHPs() or 100) < 100
end

local function anyNearbyEngagedNpc(radius)
    local filt = string.format('npc radius %d', radius or 150)
    local n = mq.TLO.SpawnCount(filt)() or 0
    for i = 1, n do
        local s = mq.TLO.NearestSpawn(i, filt)
        if s() and (s.PctHPs() or 100) < 100 then return true end
    end
    return false
end

local function maTargetId()
    local maId = maPcId()
    if not maId then return nil end
    local gated = (ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist' or ctrl.mode == 'Backline')
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
            if gated and mq.TLO.Me.Combat() then
                local nt = mq.TLO.Target
                if not (nt() and nt.Type() == 'NPC' and targetIsEngaged(nt.ID())) then
                    mq.cmd('/attack off')
                end
            end
        end
    end
    local t = mq.TLO.Target
    if not (t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0 and not t.Dead()) then return nil end
    if gated and not targetIsEngaged(t.ID()) then
        return nil
    end
    return t.ID()
end

local function resolveTargetId(token, cls)
    local b = baseTok(token)
    local id
    if b == 'Myself' or b == 'Whole Group' then
        id = mq.TLO.Me.ID()
    elseif b == 'Main Assist' or b == 'Tank' then
        id = maPcId()
    elseif b == 'Lowest-HP Ally' then
        id = lowestHpAlly()
    elseif b == 'Pet' then
        local p = (cls and petState.myPets[cls] and isSpawnAlive(petState.myPets[cls]) and petState.myPets[cls]) or
            (mq.TLO.Me.Pet.ID() or 0)
        id = (p and p > 0) and p or nil
    elseif b == 'Current Target' then
        id = mq.TLO.Target.ID()
    elseif b == 'Assist Target' then
        id = maTargetId()
    elseif b == 'Unmezzed Add' then
        id = firstNPCXtarget(true)
    elseif b == 'Nearest Add' or b == 'All Enemies' then
        id = firstNPCXtarget(false)
        if not id then
            local s = mq.TLO.NearestSpawn(1, 'npc targetable')
            id = (s() and s.Type() == 'NPC' and (s.PctHPs() or 0) > 0 and not s.Dead()) and s.ID() or nil
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
    if (stype == 'NPC' or stype == 'Pet') and hp <= 0 then return nil end
    local cname = ''
    pcall(function() cname = s.CleanName() or '' end)
    if cname ~= '' and isIgnored(cname) then return nil end
    if (stype == 'NPC' or stype == 'Pet') and (ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist' or ctrl.mode == 'Backline')
        and not targetIsEngaged(id) then
        return nil
    end
    return id
end

mq.event('TriuneZone', 'You have entered #*#', function()
    runtime.sungBuffs = {}; onZoned()
end)

local function reconcileSungBuffs()
    local found = 0
    local function scanGemTable(gemsTable)
        for i = 1, NUM_GEMS do
            local g = gemsTable[i]
            if g and g.cls == 'Brd' and g.spell and g.spell ~= '' then
                local bene = false
                pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                if bene then
                    local id = resolveTargetId(g.target, g.cls)
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
    scanGemTable(loadout.buffGems)
    if found > 0 then
        print('\ag[Triune]\ax found ' .. found .. ' bard buff(s) already active -- wont re-sing them.')
    end
end

local function reconcilePets()
    local petClassList = {}
    for _, c in ipairs(myClasses) do if PET_CLASSES[c] then petClassList[#petClassList + 1] = c end end
    if #petClassList == 0 then return end
    local n = mq.TLO.SpawnCount('pet radius 100')() or 0
    local assigned = 0
    for i = 1, math.min(n, #petClassList) do
        local s = mq.TLO.NearestSpawn(i, 'pet radius 100')
        if s() and s.ID() then
            petState.myPets[petClassList[i]] = s.ID()
            petState.lastObservedId = s.ID()
            assigned = assigned + 1
        end
    end
    if assigned > 0 then
        print('\ag[Triune]\ax found ' .. assigned .. ' existing pet(s) on load -- wont re-summon them.')
    end
end

local function conditionMet(when, pct, spellName, targetId, cls)
    pct = tonumber(pct) or 0
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
        if runtime.sungBuffs[sungKey(spellName, targetId)] then return false end -- already sung this life
        return not buffActive(targetId, spellName)
    end
    -- For pet-summon gems (Nec/Mag/Bst warder/pet lines, etc.): this server keeps
    -- a separate simultaneous pet per pet class, so this checks THIS gem's OWN
    -- class's tracked pet specifically (myPets), not the single-slot Me.Pet --
    -- otherwise summoning class A's pet would make class B's gem think it
    -- already has one too, per class C never gets cast ("cast one, gave up").
    if when == 'missing pet' then
        if not cls then
            local petId = mq.TLO.Me.Pet.ID()
            return not petId or petId == 0
        end
        return not isSpawnAlive(petState.myPets[cls])
    end
    if when == 'ally is Dead' then
        local s = mq.TLO.Spawn(targetId); return s() and s.Dead()
    end
    if when == 'has Poison/Disease' then
        local s = mq.TLO.Spawn(targetId)
        return s() and (s.Poisoned() ~= nil and s.Poisoned()() ~= nil or s.Diseased() ~= nil and s.Diseased()() ~= nil) or ---@diagnostic disable-line: undefined-field
            false
    end
    if when == 'add is loose' then return firstNPCXtarget(true) ~= nil end
    return true
end

local function isCasting()
    local cid = mq.TLO.Me.Casting.ID()
    return cid ~= nil and cid > 0
end

-- ============================================================================
-- Spell Fail-Count & Lockout System (2-try limit -> 30s lockout)
-- ============================================================================
local castTracker = createCastTracker()

local function onFailureEvent(reason)
    castTracker.onFailureEvent(reason, ctrl and ctrl.cast_max_retries or 2, ctrl and ctrl.cast_lockout_sec or 30)
end

mq.event('TriuneFizzle', '#*#fizzle#*#', function() onFailureEvent('fizzled') end)
mq.event('TriuneInterrupt', '#*#interrupted#*#', function() onFailureEvent('interrupted') end)
mq.event('TriuneOutOfRangeSpell', '#*#out of range#*#', function() onFailureEvent('out of range') end)
mq.event('TriuneCannotSeeSpell', '#*#see your target#*#', function() onFailureEvent('cannot see target') end)
mq.event('TriuneNoTakeHold', '#*#take hold#*#', function() onFailureEvent('did not take hold') end)
mq.event('TriuneImmuneSpell', '#*#immune#*#', function() onFailureEvent('target immune') end)
mq.event('TriuneDeadTargetSpell', '#*#dead target#*#', function() onFailureEvent('dead target') end)
mq.event('TriuneCantCast', '#*#cast spells while#*#', function() onFailureEvent('cannot cast') end)
mq.event('TriuneResisted1', '#*#resisted your#*#', function() onFailureEvent('resisted') end)
mq.event('TriuneResisted2', '#*#resisted the#*#', function() onFailureEvent('resisted') end)
mq.event('TriuneNotReady', '#*#not ready#*#', function() onFailureEvent('not ready') end)
mq.event('TriuneNoMana', '#*#enough mana#*#', function() onFailureEvent('insufficient mana') end)

local function castGem(i, g, id)
    if castTracker.isLockedOut(g.spell) then return false end
    local key = 'g' .. i
    if (os.clock() - (runtime.lastCast[key] or 0)) < 1.2 then return false end
    local sp = mq.TLO.Spell(g.spell)
    if not sp() then return false end
    local isMemmed = false
    pcall(function()
        local gemName = mq.TLO.Me.Gem(i).Name()
        if gemName == g.spell then
            isMemmed = true
        else
            isMemmed = (mq.TLO.Me.Gem(g.spell)() ~= nil)
        end
    end)
    if not isMemmed then return false end -- not memmed
    if (mq.TLO.Me.CurrentMana() or 0) < (sp.Mana() or 0) then return false end
    if not ctrl.burn and (ctrl.min_mana_pct or 0) > 0 and (mq.TLO.Me.PctMana() or 100) < (ctrl.min_mana_pct or 0) then return false end
    if not mq.TLO.Me.SpellReady(g.spell)() then return false end

    local dur = 0
    pcall(function() dur = tonumber(sp.Duration()) or 0 end)
    dur = tonumber(dur) or 0
    if dur > 0 and buffActive(id, g.spell) then
        return false
    end

    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    if not selfCast and not setTarget(id) then return false end

    castTracker.lastSpell   = g.spell
    castTracker.lastTime    = os.clock()
    castTracker.failed      = false
    castTracker.activeSpell = g.spell
    clearCursor()
    mq.cmdf('/cast "%s"', g.spell)
    runtime.lastCast[key] = os.clock()
    petState.lastCastCls = g.cls
    if g.cls == 'Brd' then
        if sp.Beneficial() then
            local waited = 0
            while waited < 4000 do
                mq.delay(200); waited = waited + 200
                if buffActive(id, g.spell) then break end
                if not mq.TLO.Me.Casting.ID() then break end
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
            if castMs <= 0 or castMs > 6000 then castMs = 2000 end
            mq.delay(castMs + 300)
            mq.cmd('/stopsong')
        end
    end
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    return true
end

local function fireAA(name, a, id)
    local key = 'a' .. name
    if (os.clock() - (runtime.lastCast[key] or 0)) < 1.5 then return false end
    local aa = mq.TLO.Me.AltAbility(name)
    if not aa() then return false end
    if (aa.Rank() or 0) <= 0 then return false end
    if not mq.TLO.Me.AltAbilityReady(name)() then return false end
    local ok, sp = pcall(function() return aa.Spell end)
    if ok and sp and sp() then
        local endCost = sp.EnduranceCost() or 0
        local manaCost = sp.Mana() or 0
        if endCost > 0 and (mq.TLO.Me.CurrentEndurance() or 0) < endCost then return false end
        if manaCost > 0 and (mq.TLO.Me.CurrentMana() or 0) < manaCost then return false end
    end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    if not selfCast and not setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/alt act %d', aa.ID())
    runtime.lastCast[key] = os.clock()
    petState.lastCastCls = a.cls
    print('\ag[Triune]\ax AA fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    return true
end

local function fireDisc(name, a, id)
    local key = 'd' .. name
    if (os.clock() - (runtime.lastCast[key] or 0)) < 1.5 then return false end
    if not mq.TLO.Me.CombatAbility(name)() then return false end
    if not mq.TLO.Me.CombatAbilityReady(name)() then return false end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    if not selfCast and not setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/disc "%s"', name)
    runtime.lastCast[key] = os.clock()
    petState.lastCastCls = a.cls
    print('\ag[Triune]\ax discipline fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
    end
    return true
end

local function fireSkill(name, a, id)
    local key = 's' .. name
    if (os.clock() - (runtime.lastCast[key] or 0)) < 1.5 then return false end
    if not mq.TLO.Me.AbilityReady(name)() then return false end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    if not selfCast and not setTarget(id) then return false end
    clearCursor()
    mq.cmdf('/doability "%s"', name)
    runtime.lastCast[key] = os.clock()
    petState.lastCastCls = a.cls
    print('\ag[Triune]\ax skill fired: ' .. name)
    if not selfCast and orig ~= id then
        mq.delay(60)
        if orig > 0 and mq.TLO.Target.ID() ~= orig then mq.cmdf('/target id %d', orig) end
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
local function desiredRange()
    return (ctrl.combat_style ~= 'Melee') and (ctrl.ranged_dist or 40) or MELEE_RANGE
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


local lastCombatFaceAt = 0
local function moveToward(id, dist, followOnly)
    local d = distToId(id)
    -- Already actively fighting this exact target AND actually close enough
    -- for that to be believable -- never let a flaky/transient LoS raycast
    -- (common at melee range on stairs/uneven terrain/prop geometry) restart
    -- pursuit tracking. Without this, a mob you're literally standing next to
    -- and meleeing could still fail the range+LoS check below on some ticks,
    -- "improvement" stops accumulating (you're already as close as you'll
    -- get), and after PURSUIT_STALL_TIMEOUT it gets marked unreachable and
    -- abandoned mid-fight -- exactly the "moves on before killing it" bug.
    --
    -- The distance guard is required now that combatTick can flag /attack on
    -- (eager melee -- see combatTick) the instant a target is picked, well
    -- before actually reaching it. Without it, Me.Combat()==true stopped
    -- being proof of arrival: confirmed live via debug output showing
    -- dist=734.9, engage=true, combat=true, navActive=false -- this bypass
    -- fired from 700+ units away, called stopMoving(), and froze the
    -- character in place, never actually approaching the target at all.
    if mq.TLO.Me.Combat() and mq.TLO.Target.ID() == id and d <= dist + 15 and hasLoS(id) then
        stopMoving()
        pursuit.id = 0
        if (os.clock() - (lastCombatFaceAt or 0)) > 1.0 then
            lastCombatFaceAt = os.clock()
            mq.cmd('/face fast')
        end
        return true
    end

    if pursuit.id ~= id then
        pursuit.id = id; pursuit.bestDist = d; pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0; pursuit.wasNavActive = false
        pursuit.lastLoSAt = 0
    elseif d < pursuit.bestDist - 2 then -- meaningfully closer than our best so far this pursuit
        pursuit.bestDist = d; pursuit.improvedAt = os.clock()
        pursuit.navStalls = 0
    end

    local losNow = hasLoS(id)
    if losNow then pursuit.lastLoSAt = os.clock() end
    local losOk = losNow or (pursuit.lastLoSAt > 0 and (os.clock() - pursuit.lastLoSAt) < LOS_FLICKER_GRACE)

    if d <= dist and (losOk or d <= LOS_TRUST_RANGE) then
        stopMoving()
        if not followOnly then
            if mq.TLO.Target.ID() ~= id then setTarget(id) end
            mq.cmd('/face fast') -- keep facing the mob once in range, even if it drifts
        end
        pursuit.lastNavTargetId = 0
        pursuit.id = 0
        return true
    end

    if (os.clock() - pursuit.improvedAt) > PURSUIT_STALL_TIMEOUT or pursuit.navStalls >= 3 then
        if d <= dist + 12 and losOk then
            stopMoving()
            if not followOnly then
                if mq.TLO.Target.ID() ~= id then setTarget(id) end
                mq.cmd('/face fast')
            end
            pursuit.lastNavTargetId = 0
            pursuit.id = 0
            return true
        end
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
                mq.cmdf('/nav id %d distance=%d', id, dist); pursuit.lastNavTargetId = id
            end
            return false
        end
        if not ctrl.nav_fallback_stick then
            markUnreachable(id)
            stopMoving()
            return false
        end
    end
    if stickLoaded() then
        local stickActive = false
        pcall(function() stickActive = (mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON') or false end)
        if pursuit.lastNavTargetId ~= id or not stickActive then
            mq.cmdf('/stick id %d %d', id, dist); pursuit.lastNavTargetId = id
        end
        return false
    end
    return false -- no movement plugin loaded; stand and fight from here
end

-- ============================================================================
-- Reposition / Close-in Handler for "Too far away" combat events
-- ============================================================================
local function repositionCloser()
    if not isCombat() then return end
    local tgt = mq.TLO.Target
    if not (tgt() and tgt.Type() == 'NPC' and not tgt.Dead()) then return end
    local tid = tgt.ID()
    if not tid or tid <= 0 then return end

    if (os.clock() - pursuit.lastTooFarRepositionAt) < 1.0 then return end
    pursuit.lastTooFarRepositionAt = os.clock()

    local currentDist = distToId(tid)
    local targetDist = 6
    if ctrl.combat_style ~= 'Melee' then
        targetDist = math.max(15, math.floor(currentDist - 15))
    end

    print(string.format(
        '\ay[Triune]\ax Target too far away (dist %.1f) -- repositioning closer (%d units) on target #%d.', currentDist,
        targetDist, tid))

    -- Reset pursuit tracking so moveToward doesn't short-circuit on stale arrival flags
    pursuit.id = 0
    pursuit.lastNavTargetId = 0

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
        mq.cmdf('/stick %d id %d', targetDist, tid)
    else
        mq.cmd('/keypress forward hold')
        mq.delay(200)
        mq.cmd('/keypress forward')
    end
end

mq.event('TriuneTooFar1', '#*#too far away#*#', function() repositionCloser() end)
mq.event('TriuneTooFar2', '#*#get closer#*#', function() repositionCloser() end)
mq.event('TriuneTooFar3', '#*#cannot reach#*#', function() repositionCloser() end)

-- Same idea for a fixed camp location (used returning from a pull).
local function moveTowardLoc(x, y, z, dist)
    if distToLoc(x, y, z) <= dist then
        stopMoving(); pursuit.lastNavLoc = nil; return true
    end
    if navLoaded() then
        local locStr = string.format('loc %.2f %.2f %.2f', y, x, z) -- Y X Z, matches autocombat.lua
        local ok = false
        pcall(function() ok = mq.TLO.Navigation.PathExists(locStr)() end)
        if ok then
            if pursuit.lastNavLoc ~= locStr or not mq.TLO.Navigation.Active() then
                mq.cmdf('/nav %s', locStr); pursuit.lastNavLoc = locStr
            end
            return false
        end
    end
    return false -- /stick has no raw-location form; camp return needs MQ2Nav
end

-- Stuck detection/recovery, ported from autocombat.lua's proven perform_unstuck_maneuver.
-- triune's movement had NO recovery at all: if nav/stick got blocked by a wall or a
-- door the mesh doesn't route around, it would just sit there re-issuing the same
-- command forever (this is what "stops on walls" was). Same fix: notice we haven't
-- actually displaced while nav/stick claims to be active, then back up + strafe +
-- jump to break free.

-- Movement: stuck/recovery helpers


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
    if not ok or not dist or dist > 20 then return false end
    mq.cmd('/doortarget')
    mq.delay(50)
    mq.cmd('/click left target')
    stuckState.lastDoorClickAt = now
    return true
end

local function performUnstuck()
    stuckState.lastStuckRecoveryAt = os.clock()
    if tryOpenNearbyDoor(true) then
        print('\ay[Triune]\ax stuck -- tried opening a nearby door.')
        mq.delay(600)
        stuckState.counter = 0
        pursuit.id = 0; pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil
        return
    end
    -- Report the target distance at the moment of firing -- if this still
    -- fires right next to a live mob despite the checkStuck deferral above,
    -- this number is what tells us so instead of guessing again.
    local tgt = mq.TLO.Target
    local tgtNote = (tgt() and tgt.Type() == 'NPC') and
        string.format(' (target dist %.0f, desired %.0f)', distToId(tgt.ID()), desiredRange()) or ''
    print('\ay[Triune]\ax stuck -- backing up and pivoting.' .. tgtNote)
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
    mq.cmd('/keypress back hold')
    mq.delay(1200)
    mq.cmd('/keypress back')
    if math.random(2) == 1 then
        mq.cmd('/keypress strafe_left hold'); mq.delay(400); mq.cmd('/keypress strafe_left')
    else
        mq.cmd('/keypress strafe_right hold'); mq.delay(400); mq.cmd('/keypress strafe_right')
    end
    mq.cmd('/keypress jump')
    stuckState.counter = 0
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

    -- If casting, sitting, medding, or immobilized (stunned/rooted), do not count as stuck
    local me = mq.TLO.Me
    if me() then
        if me.Casting.ID() or me.Sitting() or me.Stunned() or me.Rooted() or runtime.medBreakActive then
            stuckState.counter = 0
            stuckState.lastX, stuckState.lastY = me.X() or 0, me.Y() or 0
            return
        end
    end

    -- If we have a target (NPC or PC player like MA in chase mode) and are within range, we are not stuck
    local nt = mq.TLO.Target
    if nt() and (nt.PctHPs() or 0) > 0 and not nt.Dead() then
        local reqDist = (nt.Type() == 'PC' and (ctrl.chase_dist or 15) or desiredRange()) + 12
        if distToId(nt.ID()) <= reqDist then
            stuckState.counter = 0
            stuckState.lastX, stuckState.lastY = me.X() or 0, me.Y() or 0
            return
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
    if ctrl.mode == 'Manual' or ctrl.mode == 'Backline' or ctrl.mode == 'Pet Tank' then
        stuckState.combatStallSince = nil
        return
    end
    local t = mq.TLO.Target
    local haveLiveNPC = t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0 and not t.Dead()
    local notPursuingThis = (pursuit.id == 0) or not (haveLiveNPC and pursuit.id == t.ID())
    local closeEnough = haveLiveNPC and distToId(t.ID()) <= (desiredRange() + 10)
    local stationary = not isMoveActive()
    local notFighting = not mq.TLO.Me.Combat() and not mq.TLO.Me.AutoFire() and not mq.TLO.Me.Casting.ID()
    if haveLiveNPC and notPursuingThis and closeEnough and stationary and notFighting then
        if not stuckState.combatStallSince then
            stuckState.combatStallSince = os.clock()
        elseif (os.clock() - stuckState.combatStallSince) > 3.0 then
            print('\ay[Triune]\ax in range but combat never started -- resetting to retry.')
            stuckState.lastCombatStallRecoveryAt = os.clock()
            pursuit.id = 0
            pursuit.lastNavTargetId = 0
            mq.cmd('/face fast')
            stuckState.combatStallSince = os.clock() -- don't re-spam every tick
        end
    else
        stuckState.combatStallSince = nil
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
    local minLv        = minLevel or 1
    local maxLv        = maxLevel or 100
    -- Hunter combat anchor: if set and radius > 0, reject any candidate outside the circle.
    local anchorLoc    = ctrl.hunter_combat_loc
    local anchorRadius = anchorLoc and (ctrl.hunter_combat_radius or 0) or 0
    local function outsideAnchor(sx, sy)
        if anchorRadius <= 0 or not anchorLoc then return false end
        local dx = sx - anchorLoc.x
        local dy = sy - anchorLoc.y
        return (dx * dx + dy * dy) > (anchorRadius * anchorRadius)
    end
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' and (xt.PctHPs() or 0) > 0 and not xt.Dead()
            and not isIgnored(xt.CleanName()) and not isUnreachable(xt.ID()) then
            local lvl = xt.Level() or 0
            if lvl >= minLv and lvl <= maxLv then
                return xt.ID()
            end
        end
    end
    local radius = searchRadius or ctrl.hunter_radius or 200
    local maxZ = searchMaxZ or ctrl.hunter_z or 75
    local myZ = mq.TLO.Me.Z() or 0
    local search = string.format('npc targetable radius %d', radius)
    for i = 1, 30 do
        local s = mq.TLO.NearestSpawn(i, search)
        if not s() then break end -- ran out of candidates
        if s.Type() == 'NPC' and (s.PctHPs() or 0) > 0 and not s.Dead() and not isIgnored(s.CleanName())
            and not isUnreachable(s.ID()) then
            local lvl = s.Level() or 0
            if lvl >= minLv and lvl <= maxLv then
                local sz = s.Z() or myZ
                if math.abs(sz - myZ) <= maxZ then
                    local sx, sy = s.X() or 0, s.Y() or 0
                    if not outsideAnchor(sx, sy) then return s.ID() end
                end
            end
        end
    end
    return nil
end

local function checkCloserTarget(curTargetId, searchRadius, searchMaxZ, minLevel, maxLevel)
    if not curTargetId or curTargetId <= 0 then return nil end
    if ctrl.check_closer_mobs == false then return nil end
    if pursuit.hasRetargeted then return nil end

    local curDist = distToId(curTargetId)
    if curDist <= 35 then return nil end

    local candId = findRoamTarget(searchRadius, searchMaxZ, minLevel, maxLevel)
    if candId and candId ~= curTargetId then
        local candDist = distToId(candId)
        if candDist <= (curDist - 25) and candDist <= (curDist * 0.75) then
            return candId, candDist, curDist
        end
    end
    return nil
end


-- Puller: IDLE (find a mob) -> TO_MOB (close in, tag it) -> TO_CAMP (drag it home)
-- -> FIGHTING (normal combat loop takes over via the target already being set).
local function pullerTick()
    if not ctrl.camp_loc then return end

    if runtime.pullState == 'IDLE' then
        if mq.TLO.Me.Combat() then return end -- already fighting something; don't pull yet
        local id = findRoamTarget(ctrl.camp_radius, ctrl.camp_z, ctrl.pull_min_level, ctrl.pull_max_level)
        if id and setTarget(id) then
            runtime.pullTargetId = id; runtime.pullState = 'TO_MOB'
            pursuit.hasRetargeted = false
        end
        return
    end

    -- If another mob attacks while heading out to pull (TO_MOB state), switch to incoming aggro immediately and pull back
    if runtime.pullState == 'TO_MOB' then
        local aggroId = firstNPCXtarget(false)
        if aggroId and aggroId ~= runtime.pullTargetId then
            stopMoving()
            if setTarget(aggroId) then
                print(string.format(
                    '\ay[Triune]\ax Puller aggro on path to mob -- switching to XTarget #%d (%s) and pulling back',
                    aggroId, tostring(mq.TLO.Target.CleanName())))
                runtime.pullTargetId = aggroId
                runtime.pullState = 'TO_CAMP'
            end
        elseif (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
            local closerId, candDist, curDist = checkCloserTarget(runtime.pullTargetId, ctrl.camp_radius, ctrl.camp_z, ctrl.pull_min_level, ctrl.pull_max_level)
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
    local alive = s() and s.Type() == 'NPC' and (s.PctHPs() or 0) > 0 and not s.Dead()
    if not alive then
        runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving(); return
    end

    if runtime.pullState == 'TO_MOB' then
        if isUnreachable(runtime.pullTargetId) then
            print('\ay[Triune]\ax pull target unreachable -- picking a different mob.')
            runtime.pullState = 'IDLE'; runtime.pullTargetId = 0; stopMoving()
        elseif moveToward(runtime.pullTargetId, desiredRange()) then
            if ctrl.combat_style == 'Melee' and not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
            runtime.pullState = 'TO_CAMP'
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
    local cur = mq.TLO.Target
    local curId = (cur() and cur.Type() == 'NPC') and cur.ID() or 0
    local curDist = (curId > 0) and (cur.Distance3D() or 999) or 999
    local bestId, bestDist = 0, 999
    local bestIsHittingMe = false
    local myId = mq.TLO.Me.ID() or 0

    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.ID() ~= curId and xt.Type() == 'NPC' and not isUnreachable(xt.ID())
            and not isIgnored(xt.CleanName()) then
            local d = xt.Distance3D() or 999
            local isHittingMe = false
            pcall(function()
                if xt.TargetOfTarget.ID() == myId or xt.AggroHolder.ID() == myId or (xt.PctAggro() or 0) >= 100 then ---@diagnostic disable-line: undefined-field
                    isHittingMe = true
                end
            end)
            -- NPC is directly hitting us: no distance cap — always consider it.
            -- Otherwise: Hunter/Manual Hunter/Pet Tank use 60, other modes use 25.
            local maxRange = isHittingMe and 999 or ((ctrl.mode == 'Hunter' or ctrl.mode == 'Manual Hunter' or ctrl.mode == 'Pet Tank') and 60 or 25)
            if d < maxRange and d < bestDist then
                bestDist = d
                bestId = xt.ID()
                bestIsHittingMe = isHittingMe
            end
        end
    end
    if bestId == 0 then return false end
    -- Always switch when the new NPC is directly hitting us, or when the
    -- current target isn't on XTarget, or when the new NPC is closer.
    if bestIsHittingMe or curId == 0 or not isXTargetId(curId) or (curDist > 20 and bestDist < curDist) then
        if setTarget(bestId) then
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
    if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
    if mq.TLO.Me.Casting.ID() then mq.cmd('/stopsong') end
    if ctrl.mode ~= 'Manual Hunter' then setManualHunterPetHold(false) end
    pursuit.id = 0
    pursuit.lastNavTargetId = 0
    pursuit.lastNavLoc = nil
    pursuit.wanderLoc = nil
    runtime.pullState = 'IDLE'
    runtime.pullTargetId = 0
    if runtime.medBreakActive then
        runtime.medBreakActive = false; if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
    end
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

local function combatTick()
    if mq.TLO.Me.Dead() then
        if not runtime.deathGuardFired then
            runtime.deathGuardFired = true
            fullStop()
            runtime.sungBuffs = {}
            petState.myPets = {}; petState.lastObservedId = 0; petState.lastCastCls = nil
            print('\ar[Triune]\ax character is dead -- paused. Will resume automatically once alive again.')
        end
        return
    end
    runtime.deathGuardFired = false

    if not ctrl.medbreak_enabled then
        if runtime.medBreakActive then
            runtime.medBreakActive = false
            if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
        end
    else
        local myHp = pctHP(mq.TLO.Me.ID())
        local myMana = mq.TLO.Me.PctMana() or 100
        local myEnd = mq.TLO.Me.PctEndurance() or 100
        if not runtime.medBreakActive then
            if (ctrl.medbreak_hp_on and myHp <= ctrl.medbreak_hp_start)
                or (ctrl.medbreak_mana_on and myMana <= ctrl.medbreak_mana_start)
                or (ctrl.medbreak_end_on and myEnd <= ctrl.medbreak_end_start) then
                fullStop()
                runtime.medBreakActive = true
                print('\ay[Triune]\ax Med Break -- resting to recover.')
            end
        else
            local hpOk = not ctrl.medbreak_hp_on or myHp >= ctrl.medbreak_hp_stop
            local manaOk = not ctrl.medbreak_mana_on or myMana >= ctrl.medbreak_mana_stop
            local endOk = not ctrl.medbreak_end_on or myEnd >= ctrl.medbreak_end_stop
            if hpOk and manaOk and endOk then
                runtime.medBreakActive = false
                if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
                print('\ag[Triune]\ax Med Break over -- resuming.')
            end
        end
    end
    if runtime.medBreakActive then
        if not mq.TLO.Me.Sitting() and not mq.TLO.Me.Combat() then mq.cmd('/sit') end
        return
    end

    local curPetId = mq.TLO.Me.Pet.ID() or 0
    if curPetId ~= 0 and curPetId ~= petState.lastObservedId then
        if petState.lastCastCls then petState.myPets[petState.lastCastCls] = curPetId end
        petState.lastObservedId = curPetId
    elseif curPetId == 0 then
        petState.lastObservedId = 0
    end

    checkStuck()
    checkCombatStall()
    checkGemMemSync()
    if ctrl.mode == 'Hunter' or ctrl.mode == 'Manual Hunter' or ctrl.mode == 'Puller' or ctrl.mode == 'Pull & Assist'
        or ctrl.mode == 'Garrison' or ctrl.mode == 'Pet Tank' then
        checkAggroSwitch()
    end

    local t = mq.TLO.Target
    local haveNPC = t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0 and not t.Dead()
    if haveNPC and (ctrl.mode == 'Hunter' or ctrl.mode == 'Manual Hunter' or ctrl.mode == 'Puller' or ctrl.mode == 'Pull & Assist'
            or ctrl.mode == 'Garrison' or ctrl.mode == 'Pet Tank') and isIgnored(t.CleanName()) then
        haveNPC = false
    end
    local engage = false

    if ctrl.mode == 'Manual' then
        if haveNPC then engage = true end
    elseif ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist' then
        local id = maTargetId()
        local closingOnMob = false
        if id then
            if mq.TLO.Target.ID() ~= id then setTarget(id) end
            haveNPC = true
            if pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id) then
                closingOnMob = true
                if moveToward(id, desiredRange()) then engage = true end
            end
        else
            haveNPC = false
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        end
        if not closingOnMob then
            if ctrl.mode == 'Assist' then idleReturn() else chaseMA() end
        end
    elseif ctrl.mode == 'Backline' then
        local id = maTargetId()
        if id then
            if mq.TLO.Target.ID() ~= id then setTarget(id) end
            haveNPC = true
            if pctHP(id) <= (ctrl.assist_at or 100) and targetIsEngaged(id) and distToId(id) <= desiredRange() and hasLoS(id) then
                engage = true
            end
        else
            haveNPC = false
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        end
    elseif ctrl.mode == 'Tank' then
        local id = maTargetId()
        local closingOnMob = false
        if id then
            if mq.TLO.Target.ID() ~= id then setTarget(id) end
            haveNPC = true
            closingOnMob = true
            if moveToward(id, MELEE_RANGE) then engage = true end
        else
            haveNPC = false
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        end
        if not closingOnMob then idleReturn() end
    elseif ctrl.mode == 'Hunter' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then
            haveNPC = false
        end

        local xtarId = firstNPCXtarget(false)
        if xtarId then
            local curId = haveNPC and mq.TLO.Target.ID() or 0
            if curId == 0 or not isXTargetId(curId) then
                if curId ~= xtarId then
                    stopMoving()
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    if setTarget(xtarId) then
                        print(string.format('\ay[Triune]\ax Hunter aggro -- switching to XTarget #%d (%s)',
                            xtarId, tostring(mq.TLO.Target.CleanName())))
                    end
                end
                haveNPC = true
            end
        end

        if haveNPC then
            if not isXTargetId(mq.TLO.Target.ID()) and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
                local curId = mq.TLO.Target.ID()
                local closerId, candDist, curDist = checkCloserTarget(curId, nil, nil, ctrl.hunter_min_level, ctrl.hunter_max_level)
                if closerId and setTarget(closerId) then
                    stopMoving()
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    pursuit.hasRetargeted = true
                    print(string.format('\ay[Triune]\ax Hunter: Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f]',
                        closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist))
                end
            end
        else
            local id = findRoamTarget(nil, nil, ctrl.hunter_min_level, ctrl.hunter_max_level)
            if id and setTarget(id) then
                haveNPC = true
                pursuit.wanderLoc = nil
                pursuit.hasRetargeted = false
                runtime.lastHunterMsgKey = nil -- reset missing mob log state on finding a target
                print(string.format('\ay[Triune]\ax Hunter target acquired: #%d (%s) dist %.1f',
                    id, tostring(mq.TLO.Target.CleanName()), distToId(id)))
            elseif not anyXtarAlive() then
                -- No NPCs found and xtar is clean: stop moving/sit and log diagnostic message.
                -- Clear wander location so player doesn't keep running to a previous random location.
                if pursuit.wanderLoc then
                    pursuit.wanderLoc = nil
                    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
                    if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
                end

                local radius = ctrl.hunter_radius or 1500
                local minLv = ctrl.hunter_min_level or 1
                local maxLv = ctrl.hunter_max_level or 100
                local zDiff = ctrl.hunter_z or 75
                local anchorKey = ''
                if ctrl.hunter_combat_loc and (ctrl.hunter_combat_radius or 0) > 0 then
                    anchorKey = string.format('; anchor R%d @ %.0f,%.0f,%.0f',
                        ctrl.hunter_combat_radius, ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.y,
                        ctrl.hunter_combat_loc.z)
                end
                local currentKey = string.format('%d-%d-%d-%d-%s', minLv, maxLv, radius, zDiff, anchorKey)

                if runtime.lastHunterMsgKey ~= currentKey then
                    runtime.lastHunterMsgKey = currentKey
                    print(string.format(
                        '\ay[Triune]\ax Hunter: No NPCs found (Lvl %d-%d, Radius %d, Z %d%s). Waiting...',
                        minLv, maxLv, radius, zDiff, anchorKey))
                end
            end
        end

        if haveNPC then
            local id = mq.TLO.Target.ID()
            if moveToward(id, desiredRange()) then engage = true end
        end
    elseif ctrl.mode == 'Manual Hunter' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then
            haveNPC = false
        end

        if not haveNPC then
            local xtarId = firstNPCXtarget(false)
            if xtarId and setTarget(xtarId) then
                haveNPC = true
                stopMoving()
                pursuit.id = 0
                pursuit.lastNavTargetId = 0
                print(string.format('\ay[Triune]\ax Manual Hunter target acquired: #%d (%s)',
                    xtarId, tostring(mq.TLO.Target.CleanName())))
            end
        end

        if haveNPC then
            local id = mq.TLO.Target.ID()
            if moveToward(id, desiredRange()) then engage = true end
        end
    elseif ctrl.mode == 'Pet Tank' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then
            haveNPC = false
        end
        if not haveNPC then
            local id = findRoamTarget()
            if id and setTarget(id) then
                haveNPC = true
                pursuit.hasRetargeted = false
            end
        end
        if haveNPC then
            if not isXTargetId(mq.TLO.Target.ID()) and (ctrl.check_closer_mobs == nil or ctrl.check_closer_mobs) then
                local curId = mq.TLO.Target.ID()
                local closerId, candDist, curDist = checkCloserTarget(curId)
                if closerId and setTarget(closerId) then
                    stopMoving()
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    pursuit.hasRetargeted = true
                    print(string.format('\ay[Triune]\ax Pet Tank: Found closer NPC while traveling -- retargeting #%d (%s) [dist %.1f vs %.1f]',
                        closerId, tostring(mq.TLO.Target.CleanName()), candDist, curDist))
                end
            end
            local id = mq.TLO.Target.ID()
            if moveToward(id, ctrl.ranged_dist or 40) then engage = true end
        end
    elseif ctrl.mode == 'Puller' or ctrl.mode == 'Pull & Assist' then
        pullerTick()
        local pt = mq.TLO.Target
        haveNPC = pt() and pt.Type() == 'NPC' and (pt.PctHPs() or 0) > 0
        engage = (runtime.pullState == 'FIGHTING' and ctrl.mode == 'Puller')
    elseif ctrl.mode == 'Garrison' then
        if haveNPC and isUnreachable(mq.TLO.Target.ID()) then haveNPC = false end
        if not haveNPC then
            local id = firstNPCXtarget(false)
            if id and setTarget(id) then haveNPC = true end
        end
        if haveNPC then
            local id = mq.TLO.Target.ID()
            if moveToward(id, MELEE_RANGE) then engage = true end
        elseif ctrl.camp_loc then
            moveTowardLoc(ctrl.camp_loc.x, ctrl.camp_loc.y, ctrl.camp_loc.z, 15)
        end
    end

    if ctrl.debug_mode and ctrl.mode ~= 'Manual' and ctrl.mode ~= 'Assist' and ctrl.mode ~= 'Chase Assist'
        and ctrl.mode ~= 'Backline' and (os.clock() - (runtime.lastHunterDiagAt or 0)) > 3.0 then
        runtime.lastHunterDiagAt = os.clock()
        local t = mq.TLO.Target
        local tid = (t() and t.ID()) or 0
        local tname = (t() and t.CleanName()) or 'none'
        local dist = (tid > 0) and distToId(tid) or -1
        local los = (tid > 0) and hasLoS(tid) or false
        local navActive = navLoaded() and mq.TLO.Navigation.Active()
        local unreach = (tid > 0) and isUnreachable(tid) or false
        print(string.format(
            '\ao[Triune debug]\ax mode=%s target=%s(%d) dist=%.1f los=%s navActive=%s haveNPC=%s engage=%s unreachable=%s combat=%s autofire=%s pursuitId=%d navStalls=%d bestDist=%.1f',
            ctrl.mode, tname, tid, dist, tostring(los), tostring(navActive), tostring(haveNPC), tostring(engage),
            tostring(unreach), tostring(mq.TLO.Me.Combat()), tostring(mq.TLO.Me.AutoFire()),
            pursuit.id, pursuit.navStalls, pursuit.bestDist))
    end

    -- Auto-attack / Auto-fire handling:
    -- Engage autoattack/autofire only when target exists, engage=true (within range),
    -- and target is within desired range / melee range.
    -- Turn off autoattack/autofire whenever out of range or when no NPCs remain on XTarget list.
    -- For player-directed modes (Manual, Manual Hunter, Assist, Chase Assist,
    -- Backline, Tank), also require the NPC to be confirmed hostile before
    -- initiating auto-attack — prevents hitting friendly NPCs (merchants, etc.).
    local xtarActive = anyXtarAlive()
    local autoAttackOk = true
    if haveNPC and engage then
        local engineMode = ctrl.mode == 'Hunter' or ctrl.mode == 'Puller'
            or ctrl.mode == 'Pull & Assist' or ctrl.mode == 'Pet Tank'
            or ctrl.mode == 'Garrison'
        if not engineMode then
            local tid = mq.TLO.Target.ID() or 0
            if not isHostileTarget(tid) then autoAttackOk = false end
        end
    end
    if ctrl.combat_style == 'Melee' and ctrl.mode ~= 'Pet Tank' then
        if autoAttackOk and haveNPC and engage and distToId(mq.TLO.Target.ID()) <= MELEE_RANGE then
            if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
        elseif not xtarActive or not haveNPC or not engage then
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        end
    elseif ctrl.combat_style == 'Ranged' then
        if autoAttackOk and haveNPC and engage and distToId(mq.TLO.Target.ID()) <= (ctrl.ranged_dist or 40) then
            if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
        elseif not xtarActive or not haveNPC or not engage then
            if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
        end
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    else
        -- Spell style or Pet Tank: turn off auto-attack
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
    end
    if not xtarActive then
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        if mq.TLO.Me.AutoFire() then mq.cmd('/autofire off') end
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
    local petHoldEnabled = (ctrl.pet_hold_enabled ~= false) and trioHasPetClass()

    if petHoldEnabled and not (haveNPC and engage) then
        if not petState.petHoldActive then
            mq.cmd('/say #petcmd hold all')
            petState.petHoldActive = true
        end
    end

    if haveNPC and engage and trioHasPetClass() then
        if ctrl.mode == 'Manual Hunter' then
            setManualHunterPetHold(false)
        end
        local tid = t.ID() or 0
        local dueForRetry = (os.clock() - (petState.lastCmdAt or 0)) > 5.0
        if (tid ~= petState.lastCmdTargetId or dueForRetry) and not mq.TLO.Me.Casting.ID() then
            local tgtHp = pctHP(tid) or 100
            -- Self-directed modes: character is leading combat directly, skip external MA aggro gate.
            -- Assist modes: require player/tank has started hitting AND HP threshold met.
            local selfDirected = (ctrl.mode == 'Pet Tank' or ctrl.mode == 'Hunter' or ctrl.mode == 'Manual Hunter'
                or ctrl.mode == 'Garrison' or ctrl.mode == 'Tank' or ctrl.mode == 'Puller')
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
        -- No active NPC target: reset command tracking.
        petState.lastCmdTargetId = 0
        if ctrl.mode == 'Manual Hunter' and not mq.TLO.Me.Combat() then
            setManualHunterPetHold(true)
        end
    end

    -- Auto-turn off Burn Mode when extended target list becomes clear
    if ctrl.burn and not xtarActive then
        ctrl.burn = false
        print('\ag[Triune]\ax Burn mode auto-disabled (XTarget clear).')
    end

    local numXtar = countNPCXtarget()

    -- Universal hostile-target gate: only allow offensive actions (spells, AAs,
    -- discs, auto-attack) when the NPC target is confirmed hostile. Prevents
    -- the engine from casting on friendly NPCs (merchants, quest givers,
    -- guards, bankers) that the player happens to click on.
    -- Engine-auto-targeting modes (Hunter, Puller, Pull & Assist, Pet Tank,
    -- Garrison) are exempt: their own findRoamTarget/firstNPCXtarget selection
    -- is the safety gate, and they need to initiate combat on fresh targets.
    local ENGINE_TARGETS_MODE = {
        ['Hunter'] = true, ['Puller'] = true, ['Pull & Assist'] = true,
        ['Pet Tank'] = true, ['Garrison'] = true,
    }
    local combatReady = true
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
            if a.enabled and (not a.burn_only or ctrl.burn) and (numXtar >= (tonumber(a.min_xtar) or 1)) then
                local id = resolveTargetId(a.target, a.cls)
                if id and conditionMet(a.when, a.pct, name, id, a.cls) then
                    local isDet = isDetrimentalAction(name, a.target, a)
                    if not isDet or isXTargetId(id) or (ctrl.mode == 'Puller' and id == runtime.pullTargetId) then
                        fireAA(name, a, id)
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
            if d.enabled and (not d.burn_only or ctrl.burn) and (numXtar >= (tonumber(d.min_xtar) or 1)) then
                local id = resolveTargetId(d.target, d.cls)
                if id and conditionMet(d.when, d.pct, name, id, d.cls) then
                    local bossOk = true
                    if d.boss_only then
                        local s = mq.TLO.Spawn(id)
                        bossOk = not not (s() and s.Named())
                    end
                    if bossOk then
                        local isDet = isDetrimentalAction(name, d.target, d)
                        if not isDet or isXTargetId(id) or (ctrl.mode == 'Puller' and id == runtime.pullTargetId) then
                            eligibleDiscs[#eligibleDiscs + 1] = { name = name, entry = d, id = id }
                        end
                    end
                end
            end
        end
        table.sort(eligibleDiscs, function(a, b) return (a.entry.priority or 50) < (b.entry.priority or 50) end)
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
        if not castTracker.failed then
            castTracker.recordSuccess(castTracker.activeSpell or castTracker.lastSpell)
        end
        castTracker.activeSpell = nil
        clearCursor()
    end

    if not isCasting() and not isMoveActive() then
        local activeGems = ctrl.buff_mode and loadout.buffGems or loadout.gems
        for i = 1, NUM_GEMS do
            local g = activeGems[i]
            if g and g.spell and g.spell ~= '' then
                local minXt = tonumber(g.min_xtar) or 1
                local xtOk = ctrl.buff_mode or (numXtar >= minXt)
                local burnOk = (not g.burn_only or ctrl.burn)
                local lockedOut = castTracker.isLockedOut(g.spell)
                if burnOk and xtOk and not lockedOut then
                    local id = resolveTargetId(g.target, g.cls)
                    local condOk = id and conditionMet(g.when, g.pct, g.spell, id, g.cls)
                    if condOk then
                        local isDet = isDetrimentalAction(g.spell, g.target, g)
                        local targetValid = not isDet or isXTargetId(id) or (ctrl.mode == 'Puller' and id == runtime.pullTargetId)
                        if targetValid and castGem(i, g, id) then
                            if g.when == 'missing buff' then
                                local bene = false
                                pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                                if bene then runtime.sungBuffs[sungKey(g.spell, id)] = true end
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
                            i, g.spell, tostring(g.target), tostring(baseTok(g.target)), tostring(id), tid, ttype, thp, tostring(condOk), tostring(xtOk), numXtar, minXt))
                    end
                elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                    runtime.lastGemDiagAt = os.clock()
                    print(string.format(
                        '\ao[Triune debug]\ax gem %d "%s" gate failed -- xtOk=%s(%d>=%d) burnOk=%s lockedOut=%s',
                        i, g.spell, tostring(xtOk), numXtar, minXt, tostring(burnOk), tostring(lockedOut)))
                end
            end
        end
    elseif ctrl.debug_mode and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
        runtime.lastGemDiagAt = os.clock()
        local stickOn = false
        pcall(function() stickOn = stickLoaded() and mq.TLO.Stick.Status() == 'ON' end)
        print(string.format('\ao[Triune debug]\ax all gems blocked -- casting=%s navActive=%s stickOn=%s',
            tostring(mq.TLO.Me.Casting.ID()), tostring(navLoaded() and mq.TLO.Navigation.Active()), tostring(stickOn)))
    end
end

local MODE_ALIASES = {}
local function normalizeCommandKey(text)
    return tostring(text):lower():gsub('[^%w]', '')
end

do
    for _, m in ipairs(MODES) do
        MODE_ALIASES[normalizeCommandKey(m)] = m
    end
end

local function setTriuneMode(modeKey)
    local newMode = MODE_ALIASES[normalizeCommandKey(modeKey)]
    if not newMode then return nil end
    if ctrl.mode == 'Manual Hunter' and newMode ~= 'Manual Hunter' then
        setManualHunterPetHold(false, false)
    end
    if ctrl.mode == newMode then
        print('\ay[Triune]\ax mode already set to ' .. newMode .. '.')
        return true
    end
    ctrl.mode = newMode
    print('\ag[Triune]\ax mode set to ' .. newMode .. '.')
    return true
end

local triuneToggle
local function triuneCommand(...)
    local args = { ... }
    local cmd = ''
    if #args > 0 then
        cmd = normalizeCommandKey(table.concat(args, ''))
    end
    if cmd == '' then
        triuneToggle()
        return
    end
    if cmd == 'run' or cmd == 'start' then
        if ctrl.running then
            print('\ay[Triune]\ax already running.')
        else
            ctrl.running = true
            print('\ag[Triune]\ax running.')
        end
    elseif cmd == 'pause' or cmd == 'stop' then
        if not ctrl.running then
            print('\ay[Triune]\ax already paused.')
        else
            if ctrl.mode == 'Manual Hunter' then
                setManualHunterPetHold(true, true)
            else
                setManualHunterPetHold(false, true)
            end
            ctrl.running = false
            fullStop()
            print('\ag[Triune]\ax paused.')
        end
    elseif cmd == 'status' then
        print(string.format('\ag[Triune]\ax status: %s, mode: %s, burn: %s', ctrl.running and 'running' or 'paused',
            ctrl.mode, ctrl.burn and 'ON' or 'OFF'))
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
    elseif cmd == 'spellbook' or cmd == 'book' then
        local s = mq.TLO.Lua.Script('triune_spellbook')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/lua stop triune_spellbook')
            print('\ag[Triune]\ax stopping spellbook engine...')
        else
            mq.cmd('/lua run triune_spellbook')
            print('\ag[Triune]\ax launching spellbook engine...')
        end
    elseif cmd == 'cursorui' or cmd == 'cursorwin' or cmd == 'cursormgr' then
        local s = mq.TLO.Lua.Script('triune_cursor')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/lua stop triune_cursor')
            print('\ag[Triune]\ax stopping cursor manager...')
        else
            mq.cmd('/lua run triune_cursor')
            print('\ag[Triune]\ax launching cursor manager...')
        end
    elseif cmd == 'dps' or cmd == 'dpsui' or cmd == 'dpsparser' then
        local s = mq.TLO.Lua.Script('triune_dps')
        if s() and s.Status() == 'RUNNING' then
            mq.cmd('/dps toggle')
            print('\ag[Triune]\ax toggling DPS parser window...')
        else
            mq.cmd('/lua run triune_dps')
            print('\ag[Triune]\ax launching DPS parser window...')
        end
    elseif cmd == 'clearcursor' or cmd == 'autoinv' or cmd == 'cursor' then
        clearCursor()
    elseif setTriuneMode(cmd) then
        -- mode command handled
    else
        print('\ay[Triune]\ax usage: /ac [run|pause|burn [on|off]|status|spellbook|cursorui|dps|clearcursor|<mode>]')
    end
end

triuneToggle = function()
    if ctrl.running then
        if ctrl.mode == 'Manual Hunter' then
            setManualHunterPetHold(true, true)
        else
            setManualHunterPetHold(false, true)
        end
        ctrl.running = false
        fullStop()
        print('\ag[Triune]\ax paused.')
    else
        ctrl.running = true
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
local updateMapRadiusVisuals

local function clearMapRadiusVisuals()
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
    local drawType = nil
    local radius = 0
    local loc = nil
    local label = ''

    if mode == 'Puller' or mode == 'Pull & Assist' or mode == 'Manual Puller' then
        radius = ctrl.camp_radius or 100
        if ctrl.camp_loc then
            drawType = 'maploc'
            loc = ctrl.camp_loc
            label = 'Camp'
        else
            drawType = 'pullradius'
        end
    elseif mode == 'Hunter' or mode == 'Manual Hunter' then
        if ctrl.hunter_combat_loc and (ctrl.hunter_combat_radius or 0) > 0 then
            drawType = 'maploc'
            radius = ctrl.hunter_combat_radius
            loc = ctrl.hunter_combat_loc
            label = 'Anchor'
        else
            drawType = 'castradius'
            radius = ctrl.hunter_radius or 1500
        end
    end

    if not drawType or radius <= 0 then
        if runtime.lastMapDraw and runtime.lastMapDraw.active then
            clearMapRadiusVisuals()
        end
        return
    end

    local key = string.format('%s|%d|%s|%s', drawType, radius, label,
        loc and string.format('%.1f,%.1f,%.1f', loc.x or 0, loc.y or 0, loc.z or 0) or 'noloc')

    if runtime.lastMapDraw and runtime.lastMapDraw.active and runtime.lastMapDraw.key == key then
        return -- State unchanged; do nothing
    end

    -- Clear all previous map overlays before applying new one
    clearMapRadiusVisuals()

    if drawType == 'maploc' and loc then
        mq.cmdf('/maploc %f %f %f radius %d rcolor 0 255 0 color 0 255 0 label %s',
            loc.y, loc.x, loc.z, radius, label)
    elseif drawType == 'pullradius' then
        mq.cmd('/mapfilter pullradius color 0 255 0')
        mq.cmd('/mapfilter pullradius show')
        mq.cmdf('/mapfilter pullradius %d', radius)
    elseif drawType == 'castradius' then
        mq.cmd('/mapfilter castradius color 255 0 0')
        mq.cmd('/mapfilter castradius show')
        mq.cmdf('/mapfilter castradius %d', radius)
    end

    runtime.lastMapDraw = {
        active = true,
        type = drawType,
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
            -- camp restored from a save; no map circle is drawn
            reconcileSungBuffs()                                      -- don't re-sing bard buffs that are already up
            reconcilePets()                                           -- don't re-summon pets that are already out
            runtime.lastSig = loadoutSig(); runtime.autoDirty = false -- baseline; don't save what we just loaded
        end
        if reDetectRequested then
            reDetectRequested = false
            local detected = detectClasses(true) -- safe here -- main loop coroutine can yield/delay
            if detected then myClasses = detected end
        end
        -- (Cursor items are cleared on-demand prior to actions/mems or post-cast completion)
        updateMapRadiusVisuals()
        -- drain one queued spell-mem per pass, out of combat and while not casting
        local memmed = false
        if not mq.TLO.Me.Casting.ID() then
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
