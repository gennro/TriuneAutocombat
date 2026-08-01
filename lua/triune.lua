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

local mq = require('mq')
local ImGui = require('ImGui')
local scriptDir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path = scriptDir .. "?.lua;" .. package.path
local common = require('triune_common')

local VERSION = '3.25-commonmod'
local open = true
local cfg = mq.configDir

-- ============================================================================
-- Constants / class data
-- ============================================================================
local ALL_ABBR = { 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm',
    'Nec', 'Wiz', 'Mag', 'Enc', 'Bst', 'Ber' }

-- the character's gestalt trio (editable). Declared here, before classColor,
-- so slot colors below can be looked up by position in this list.
local myClasses = { 'War', 'Rng', 'Brd' }

-- Set by the "Re-detect" button (drawClassPicker runs inside the ImGui render
-- callback, a non-yieldable thread) and drained in the main loop below. Do
-- NOT call detectClasses()/classesFromInventoryWindow() directly from a UI
-- button handler -- they contain mq.delay() calls (forcing the Inventory
-- window open and waiting for it), and delaying from the ImGui thread is a
-- hard crash: "Cannot delay from non-yieldable thread", which also corrupts
-- ImGui's Begin/End stack and pauses the whole overlay until /mqoverlay
-- resume. Confirmed via a real crash report from a tester.
local reDetectRequested = false

-- Validated categorical slot colors (dataviz palette check, dark surface) --
-- one per TRIO SLOT, not per class, so the emblem/tags always show three
-- distinct, colorblind-safe hues no matter which 3 of the 16 classes you play.
local function classColor(abbr)
    return common.classColor(abbr, myClasses)
end

-- theme accents (r,g,b,a 0-1)
local GOLD    = { 1.0, 0.70, 0.54, 1 }
local ARC     = { 0.30, 0.70, 1.0, 1 }
local MUTED   = { 0.49, 0.56, 0.65, 1 }
local GOOD    = { 0.37, 0.88, 0.64, 1 }
local WARN    = { 1.0, 0.72, 0.30, 1 }

-- ============================================================================
-- Data loading
-- ============================================================================
local DATA    = { era_expansion = 5, spells = {}, discs = {}, aas = {} }
local DATA_OK = false
do
    local f = loadfile(cfg .. '/triune_data.lua')
    if f then
        local ok, t = pcall(f)
        if ok and type(t) == 'table' and t.spells then
            DATA = t; DATA_OK = true
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
        running = false,
        mode = 'Assist',
        combat_style = 'Melee',
        ranged_dist = 40,
        ma_name = '',
        assist_at = 98,
        chase = true,
        chase_dist = 15,
        automem = true,
        camp_loc = nil,
        camp_radius = 100,
        camp_z = 75,
        hunter_radius = 1500,
        hunter_z = 75,
        hunter_min_level = 1,
        hunter_max_level = 100,
        hunter_combat_radius = 0,    -- 0 = disabled; >0 = max roam distance from anchor
        hunter_combat_loc = nil,     -- {x,y,z} anchor; nil = no constraint
        pull_min_level = 1,
        pull_max_level = 100,
        nav_fallback_stick = false,
        debug_mode = false,
        buff_mode = false,
        scribed_only = true,
        aa_purchased_only = true,
        disc_trained_only = true,
        medbreak_enabled = false,
        medbreak_hp_on = false,
        medbreak_hp_start = 20,
        medbreak_hp_stop = 90,
        medbreak_mana_on = false,
        medbreak_mana_start = 20,
        medbreak_mana_stop = 90,
        medbreak_end_on = false,
        medbreak_end_start = 20,
        medbreak_end_stop = 90,
        cast_max_retries = 2,
        cast_lockout_sec = 30,
        pet_assist_at    = 100
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
    lastGemDiagAt = 0,
    lastAssistCmdAt = 0,
    sungBuffs = {}
}

local petState = {
    myPets = {},
    lastObservedId = 0,
    lastCastCls = nil,
    lastCmdTargetId = 0,
    lastCmdAt = 0,
    manualHunterHold = nil
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
    lastTooFarRepositionAt = 0
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
-- Helpers (Delegated to triune_common)
-- ============================================================================
local H = common
local idxOf, defaultsForKind, isCasting, isSpawnAlive = H.idxOf, H.defaultsForKind, H.isCasting, H.isSpawnAlive
local distToId, distToLoc, hasLoS, pctHP = H.distToId, H.distToLoc, H.hasLoS, H.pctHP
local buffActive, sungKey, navLoaded, stickLoaded = H.buffActive, H.sungKey, H.navLoaded, H.stickLoaded
local isMoveActive, stopMoving = H.isMoveActive, H.stopMoving

local function classHasSpells(abbr)
    local s = DATA.spells[abbr]
    return s ~= nil and #s > 0
end

-- Checked live every time the spell picker renders (not cached), so the list
-- naturally updates the moment you scribe something new -- no separate
-- refresh mechanism needed.
local function isScribed(nm)
    return common.isScribed(nm)
end

-- kind tag (4th field the extractor writes: dd/dot/heal/buff, classified from
-- goodEffect + whether the spell has a duration -- verified against known
-- spells: Flame Bolt=dd, Immolate/Heat Blood=dot, Minor Healing=heal, Spirit
-- of Wolf=buff). Shown in the picker so a low-level player isn't left
-- guessing what an unfamiliar spell name actually does.
local KIND_LABEL = { dd = 'DD', dot = 'DoT', heal = 'Heal', buff = 'Buff', pet = 'Pet' }

-- spells for a class within the level band; returns name list + lookup by name.
-- ctrl.scribed_only (default on) additionally filters to spells actually in
-- your spellbook -- without it, a lower-level character sees every spell
-- their class could EVER learn in that level range, most of which they may
-- not have scribed yet, which reads as "the tool doesn't know what I have".
local filteredSpellsCache = {}
local lastFilteredCacheTime = 0
local lastFilterState = {}

local function filteredSpells(abbr)
    local now = os.clock()
    local scribedOnly = ctrl and ctrl.scribed_only or false
    if filteredSpellsCache[abbr] and (now - lastFilteredCacheTime) < 2.0
        and lastFilterState.lvlMin == lvlMin
        and lastFilterState.lvlMax == lvlMax
        and lastFilterState.scribedOnly == scribedOnly then
        return filteredSpellsCache[abbr].names, filteredSpellsCache[abbr].lookup
    end

    local names, lookup = {}, {}
    local src = DATA.spells[abbr] or {}
    for _, row in ipairs(src) do
        local nm, lv, bene, kind = row[1], row[2], row[3], row[4]
        if lv >= lvlMin and lv <= lvlMax and (not scribedOnly or isScribed(nm)) then
            local label       = KIND_LABEL[kind]
            names[#names + 1] = label and string.format('%s  (L%d) [%s]', nm, lv, label)
                or string.format('%s  (L%d)', nm, lv)
            lookup[#names]    = { name = nm, level = lv, bene = (bene == 1), kind = kind }
        end
    end

    filteredSpellsCache[abbr] = { names = names, lookup = lookup }
    lastFilteredCacheTime = now
    lastFilterState = { lvlMin = lvlMin, lvlMax = lvlMax, scribedOnly = scribedOnly }
    return names, lookup
end

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
local MQSHORT = common.MQSHORT
local ALLDATA = {} -- character name -> saved entry

local function detectClasses(loud)
    return common.detectClasses(loud)
end

-- Which of the character's classes owns a spell, whether it's beneficial, and
-- its kind tag (dd/dot/heal/buff) -- all three feed defaultsForKind.
local function spellClassInfo(name)
    for _, abbr in ipairs(myClasses) do
        local list = DATA.spells[abbr]
        if list then for _, it in ipairs(list) do if it[1] == name then return abbr, (it[3] == 1), it[4] end end end
    end
    return myClasses[1] or 'War', true, nil
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
    loadout.aas      = e.aas or {}
    loadout.discs    = e.discs or {}
    if type(e.control) == 'table' then
        for k, v in pairs(e.control) do ctrl[k] = v end
        -- Migrate pre-3.6 saves (separate use_melee/use_ranged checkboxes) to the
        -- single combat_style radio -- old saves have no combat_style field at all.
        if not e.control.combat_style then
            ctrl.combat_style = e.control.use_ranged and 'Ranged' or 'Melee'
        end
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
            .. '~' .. tostring(g.when) .. '~' .. tostring(g.pct)) or '-'
    end
    for i = 1, NUM_GEMS do
        local g = loadout.buffGems[i]
        p[#p + 1] = g and (tostring(g.cls) .. '~' .. tostring(g.spell) .. '~' .. tostring(g.target)
            .. '~' .. tostring(g.when) .. '~' .. tostring(g.pct)) or '-'
    end
    local keys = {}
    for nm in pairs(loadout.aas) do keys[#keys + 1] = tostring(nm) end
    table.sort(keys)
    for _, nm in ipairs(keys) do
        local a = loadout.aas[nm]
        p[#p + 1] = nm ..
            '~' .. tostring(a.enabled) .. '~' .. tostring(a.target) .. '~' .. tostring(a.when) .. '~' .. tostring(a.pct)
    end
    local dkeys = {}
    for nm in pairs(loadout.discs) do dkeys[#dkeys + 1] = tostring(nm) end
    table.sort(dkeys)
    for _, nm in ipairs(dkeys) do
        local d = loadout.discs[nm]
        p[#p + 1] = nm ..
            '~' .. tostring(d.enabled) .. '~' .. tostring(d.target) .. '~' .. tostring(d.when) .. '~' .. tostring(d.pct)
            .. '~' .. tostring(d.boss_only) .. '~' .. tostring(d.priority)
    end
    local c = ctrl.camp_loc
    p[#p + 1] = table.concat({ ctrl.mode, tostring(ctrl.combat_style),
        tostring(ctrl.ranged_dist), tostring(ctrl.ma_name), tostring(ctrl.assist_at),
        tostring(ctrl.chase), tostring(ctrl.chase_dist), tostring(ctrl.automem),
        tostring(ctrl.hunter_radius), tostring(ctrl.hunter_z), tostring(ctrl.camp_radius), tostring(ctrl.camp_z),
        tostring(ctrl.pet_assist_at),
        tostring(ctrl.nav_fallback_stick), tostring(ctrl.debug_mode), tostring(ctrl.buff_mode), tostring(ctrl
        .scribed_only),
        tostring(ctrl.aa_purchased_only), tostring(ctrl.disc_trained_only),
        tostring(ctrl.medbreak_enabled),
        tostring(ctrl.medbreak_hp_on), tostring(ctrl.medbreak_hp_start), tostring(ctrl.medbreak_hp_stop),
        tostring(ctrl.medbreak_mana_on), tostring(ctrl.medbreak_mana_start), tostring(ctrl.medbreak_mana_stop),
        tostring(ctrl.medbreak_end_on), tostring(ctrl.medbreak_end_start), tostring(ctrl.medbreak_end_stop),
        tostring(ctrl.cast_max_retries), tostring(ctrl.cast_lockout_sec),
        c and string.format('%.1f,%.1f,%.1f', c.x, c.y, c.z) or 'nocamp' }, '~')
    return table.concat(p, '|')
end

-- Does this character own ANY item at all (spell/disc/AA, shared or unique) from
-- abbr's full pool? A much lower bar than the UNIQUE-only ranking score used by
-- detectClasses -- this is for VALIDATING an already-saved class slot, not for
-- competitively ranking candidates. A real Bard, at any level, knows at least
-- one Bard song/spell/disc/AA ever; a class name that's only in the save because
-- of a past bug (detectClasses used to hardcode 'Rng'/'Brd' when it couldn't
-- find a real 2nd/3rd class) will show zero.
local function classPlausible(abbr)
    return common.classPlausible(abbr, DATA)
end

-- Called when the logged-in character changes: load that toon's saved setup, or
-- detect classes fresh if it's new.
local function onCharacterChanged()
    loadout = { gems = {}, buffGems = {}, aas = {}, discs = {} }
    ctrl = defaultCtrl()
    runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
    lvlMin, lvlMax = 1, 65
    if ALLDATA[myName] then
        applyEntry(ALLDATA[myName])
        common.scanKnownDiscs()
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
        myClasses = detectClasses()
        importCurrentGems() -- new character: seed the loadout from the current bar
    end
    -- Authoritative live read always wins, even over a saved/heuristic value --
    -- catches a stale save immediately on login without waiting on self-heal or
    -- a manual Re-detect click.
    local liveClasses = common.classesFromInventoryWindow(false, true)
    if liveClasses then myClasses = liveClasses end
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
local function tryMem(slot, name)
    return common.tryMem(slot, name)
end

-- ============================================================================
-- UI
-- ============================================================================
local function accent(c, txt) ImGui.TextColored(c[1], c[2], c[3], c[4], txt) end

-- UI: theme and style helpers
-- ---- NMS theme (pushed each frame; every push is pcall-guarded so any enum this
--      MQ build doesn't expose is skipped instead of breaking the window) --------
local function pushTheme()
    common.pushTheme()
end
local function popTheme()
    common.popTheme()
end

-- Renders the Triune sigil (outer ring + inner triangle + three class-colored
-- nodes) at the cursor, matching the site emblem: top node = slot 1 (arcane),
-- bottom-right = slot 2 (ember), bottom-left = slot 3 (jade). Node colors track
-- your actual gestalt trio via SLOT_COLORS/classColor. Every draw call is
-- pcall-guarded so an unsupported binding can't take the header down with it.
-- UI: header emblem
local function drawEmblem(size)
    pcall(function()
        local dl = ImGui.GetWindowDrawList()
        local p = ImGui.GetCursorScreenPosVec()
        local r = size / 2
        local cx, cy = p.x + r, p.y + r

        dl:AddCircle(ImVec2(cx, cy), r - 1, IM_COL32(143, 208, 255, 160), 24, 1.2)

        local tri_r = r * 0.62
        local top   = ImVec2(cx, cy - tri_r)
        local right = ImVec2(cx + tri_r * 0.87, cy + tri_r * 0.55)
        local left  = ImVec2(cx - tri_r * 0.87, cy + tri_r * 0.55)
        dl:AddTriangle(top, right, left, IM_COL32(143, 165, 235, 150), 1.1)

        local function node(pt, slot)
            local c = common.SLOT_COLORS[slot]
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
            local newIdx = ImGui.Combo('##cls' .. i, idxOf(ALL_ABBR, myClasses[i] or 'War'), ALL_ABBR)
            myClasses[i] = ALL_ABBR[newIdx]
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

-- Shared row-rendering for both the Spell Gems tab and the Buff Loadout tab --
-- same class -> spell -> target -> when -> percent picker either way, just
-- pointed at a different 12-slot table. isActiveSet gates auto-mem-on-pick so
-- editing the INACTIVE set (planning ahead) never clobbers whatever's actually
-- memmed right now; only editing the currently-active set mems immediately.
-- UI: spell/gem list editor
function UI.drawGemList(gemsTable, idPrefix, isActiveSet)
    if ImGui.BeginChild('gemlist_' .. idPrefix, 0, 0, false) then
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
                ImGui.SameLine()
                if ImGui.Button('x') then gemsTable[i] = nil end
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
    UI.drawGemList(loadout.gems, 'gem', not ctrl.buff_mode)
    ImGui.EndTabItem()
end

function UI.drawBuffTab()
    if not ImGui.BeginTabItem('Buff Loadout') then return end
    accent(MUTED,
        'A second gem set for pet summons / buffs that don\'t fit alongside your combat spells -- e.g. Nec/Mag pet summons, Bst buffs. Build it here, hit Mem All to Bar to swap it onto your bar, buff up, then switch back on the Spell Gems tab.')
    UI.drawGemTabHeader(loadout.buffGems, true)
    UI.drawGemList(loadout.buffGems, 'bgem', ctrl.buff_mode)
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

    if ImGui.BeginChild('aalist', 0, 0, false) then
        for _, tier in ipairs(TIER_ORDER) do
            local any = false
            for _, cls in ipairs(myClasses) do
                for sec, list in pairs(DATA.aas[cls] or {}) do
                    if aaTier(sec) == tier then
                        for _, nm in ipairs(list) do
                            if not ctrl.aa_purchased_only or common.hasAA(nm) then
                                any = true
                                ImGui.PushID(cls .. nm)
                                local entry = loadout.aas[nm] or
                                    { cls = cls, target = 'F: Myself', when = 'in combat', enabled = false, pct = 30 }
                                entry.enabled = ImGui.Checkbox('##en', entry.enabled)
                                ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls)
                                ImGui.SameLine(); ImGui.Text(nm)
                                ImGui.SameLine(); ImGui.TextDisabled('(' .. fmtSec(sec) .. ')')
                                if entry.enabled then
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(150)
                                    local ti = ImGui.Combo('##aat', idxOf(TARGETS, entry.target), TARGETS)
                                    entry.target = TARGETS[ti]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(140)
                                    local wi = ImGui.Combo('##aaw', idxOf(WHENS, entry.when), WHENS)
                                    entry.when = WHENS[wi]
                                    ImGui.SameLine(); ImGui.SetNextItemWidth(80)
                                    entry.pct = ImGui.SliderInt('##aap', entry.pct or 30, 0, 100, '%d%%')
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
    if ImGui.BeginChild('disclist', 0, 0, false) then
        local anyDisc = false
        for _, cls in ipairs(myClasses) do
            for _, row in ipairs(DATA.discs[cls] or {}) do
                local nm, lv = row[1], row[2]
                if not ctrl.disc_trained_only or common.hasDisc(nm) then
                    anyDisc = true
                    ImGui.PushID('disc' .. cls .. nm)
                    local entry = loadout.discs[nm] or
                        { cls = cls, target = 'F: Myself', when = 'HP <=', enabled = false, pct = 30, boss_only = false, priority = 50 }
                    entry.enabled = ImGui.Checkbox('##en', entry.enabled)
                    ImGui.SameLine(); local r, gc, b, a = classColor(cls); ImGui.TextColored(r, gc, b, a, cls)
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
                        entry.pct = ImGui.SliderInt('##dp', entry.pct or 30, 0, 100, '%d%%')
                        ImGui.SameLine(); entry.boss_only = ImGui.Checkbox('Boss Only##bo', entry.boss_only)
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip(
                                'Only fires if the resolved target is a Named mob.')
                        end
                        ImGui.SameLine(); ImGui.SetNextItemWidth(80)
                        entry.priority = ImGui.SliderInt('##pri', entry.priority or 50, 1, 99, 'Pri %d')
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
    ImGui.Dummy(0, 4)

    if ctrl.running then
        accent(GOOD, 'STATUS:  RUNNING')
    else
        ImGui.TextColored(1, 0.42, 0.32, 1, 'STATUS:  PAUSED')
    end
    ImGui.SameLine(); ImGui.Dummy(20, 0); ImGui.SameLine()
    if ctrl.running then
        if ImGui.Button('PAUSE', 220, 30) then
            if ctrl.mode == 'Manual Hunter' then
                setManualHunterPetHold(true)
            end
            ctrl.running = false
        end
    else
        if ImGui.Button('START', 220, 30) then ctrl.running = true end
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
                if (ctrl.hunter_combat_radius or 0) == 0 then
                    ctrl.hunter_combat_radius = 500  -- sensible default on first Set
                end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Saves your current position as the anchor.\nHunter will only wander and find mobs within the Combat Radius of this point.')
        end
        ImGui.SameLine()
        if ImGui.Button('Clear Anchor##hunter') then
            ctrl.hunter_combat_loc = nil
            ctrl.hunter_combat_radius = 0
            pursuit.wanderLoc = nil  -- ditch any wander-point that might be outside the old zone
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Remove the anchor -- Hunter will roam freely again.')
        end

        -- Radius slider (greyed out / clamped to 1 min when no anchor)
        local hasAnchor = ctrl.hunter_combat_loc ~= nil
        if not hasAnchor then ImGui.BeginDisabled() end
        ImGui.SetNextItemWidth(220)
        local displayRadius = math.max(1, ctrl.hunter_combat_radius or 0)
        local newRadius = ImGui.SliderInt('Combat Radius##hunter', displayRadius, 1, 2000)
        if hasAnchor then ctrl.hunter_combat_radius = newRadius end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Maximum distance from the anchor the Hunter will roam\n'
                .. 'and search for targets. Mobs outside this radius are ignored.\n'
                .. 'Greyed out until an anchor is set.')
        end
        if not hasAnchor then ImGui.EndDisabled() end
    end

    if usesMA then
        accent(GOLD, 'Main Assist')
        ImGui.SetNextItemWidth(160)
        ctrl.ma_name = ImGui.InputText('MA Name', ctrl.ma_name or '')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Character to assist. Leave blank to assist group leader.') end
        ImGui.SetNextItemWidth(160)
        ctrl.assist_at = ImGui.SliderInt('Assist At %', ctrl.assist_at or 98, 1, 100, '%d%%')

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
            ..'/attack, no /autofire) -- your Spell Gems loadout does all the\n'
            ..'damage. For pure caster trios that don\'t melee or carry a bow.')
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
            ..'try to close on it in a straight line -- which walks\n'
            ..'straight at whatever wall is blocking the path.\n'
            ..'Off by default: unreachable targets are dropped instead.')
    end
    ctrl.debug_mode = ImGui.Checkbox('Debug Mode', ctrl.debug_mode)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Prints extra diagnostic lines (e.g. Hunter\'s full targeting\n'
            ..'state every few seconds) to help track down a stuck/frozen\n'
            ..'report. Off by default -- noisy for normal use.')
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Spell Failures & Lockout')
    ImGui.SetNextItemWidth(140)
    ctrl.cast_max_retries = ImGui.SliderInt('Max Retries##cmr', ctrl.cast_max_retries or 2, 1, 10)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Consecutive failed cast attempts allowed before temporarily locking out a spell.\nDefault: 2 tries.')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(140)
    ctrl.cast_lockout_sec = ImGui.SliderInt('Lockout Time (s)##cls', ctrl.cast_lockout_sec or 30, 5, 300, '%d s')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('How many seconds to wait before trying a locked-out spell again.\nDefault: 30 seconds.')
    end

    ImGui.Dummy(0, 4)
    -- Pet Settings: shown only when the trio has a pet class
    if trioHasPetClass() then
        accent(ARC, 'Pet Settings')
        ImGui.SetNextItemWidth(180)
        ctrl.pet_assist_at = ImGui.SliderInt('Pet Assist At %##pa',
            ctrl.pet_assist_at or 100, 1, 100, '%d%%')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Send pets to attack once the target drops to or below\n'
                ..'this HP%% AND the player has started hitting the mob.\n'
                ..'100%% = send as soon as the first hit connects (default).')
        end
    end

    ImGui.Dummy(0, 4)
    accent(GOLD, 'Med Break')
    ctrl.medbreak_enabled = ImGui.Checkbox('Enable Med Break', ctrl.medbreak_enabled)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Stops everything and sits to recover once any enabled\n'
            ..'resource below drops to its "at" %%; resumes once ALL enabled\n'
            ..'resources have recovered up to their "until" %%.')
    end
    if ctrl.medbreak_enabled then
        ctrl.medbreak_hp_on = ImGui.Checkbox('HP##mbhp', ctrl.medbreak_hp_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_hp_start = ImGui.SliderInt('##mbhpstart', ctrl.medbreak_hp_start or 20, 0, 100, '%d%%')
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_hp_stop  = ImGui.SliderInt('##mbhpstop',  ctrl.medbreak_hp_stop  or 90, 0, 100, '%d%%')

        ctrl.medbreak_mana_on = ImGui.Checkbox('Mana##mbmana', ctrl.medbreak_mana_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_mana_start = ImGui.SliderInt('##mbmanastart', ctrl.medbreak_mana_start or 20, 0, 100, '%d%%')
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_mana_stop  = ImGui.SliderInt('##mbmanastop',  ctrl.medbreak_mana_stop  or 90, 0, 100, '%d%%')

        ctrl.medbreak_end_on = ImGui.Checkbox('Endurance##mbend', ctrl.medbreak_end_on)
        ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_end_start = ImGui.SliderInt('##mbendstart', ctrl.medbreak_end_start or 20, 0, 100, '%d%%')
        ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(120)
        ctrl.medbreak_end_stop  = ImGui.SliderInt('##mbendstop',  ctrl.medbreak_end_stop  or 90, 0, 100, '%d%%')
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
local function baseTok(token) return (tostring(token or '')):gsub('^[FE]: ', '') end


local function setTarget(id)
    if not id or id == 0 then return false end
    if mq.TLO.Target.ID() == id then return true end
    mq.cmdf('/target id %d', id)
    local t = 0
    while mq.TLO.Target.ID() ~= id and t < 300 do
        mq.delay(20); t = t + 20
    end
    return mq.TLO.Target.ID() == id
end


isCombat = function()
    if mq.TLO.Me.CombatState() == 'COMBAT' then return true end
    if ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist' or ctrl.mode == 'Backline' or ctrl.mode == 'Tank' then
        for i = 1, 13 do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' then return true end
        end
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
            if tloTrue(function() return m.Song(name)() end) then return true end
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
    return common.firstNPCXtarget(unmezzedOnly, isIgnored, isUnreachable)
end

-- Returns true if any live (PctHPs > 0), non-ignored, reachable NPC occupies
-- an XTarget slot. Used by Hunter mode to decide whether it is safe to roam
-- for a fresh mob: if the XTarget list still has live hostiles from the
-- current or recent fight, Hunter must finish those before wandering away.
local function anyXtarAlive()
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC'
            and (xt.PctHPs() or 0) > 0
            and not isIgnored(xt.CleanName())
            and not isUnreachable(xt.ID()) then
            return true
        end
    end
    return false
end

local function maPcId()
    return common.maPcId(ctrl and ctrl.ma_name)
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
    if not (t() and t.Type() == 'NPC') then return nil end
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
            local s = mq.TLO.NearestSpawn(1, 'npc'); id = s() and s.ID() or nil
        end
    else
        id = mq.TLO.Target.ID()
    end
    if not id or id <= 0 then return nil end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Type() == 'Corpse' then return nil end
    if isIgnored(s.CleanName()) then return nil end
    if s.Type() == 'NPC' and (ctrl.mode == 'Assist' or ctrl.mode == 'Chase Assist' or ctrl.mode == 'Backline')
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
        return s() and (s.Poisoned() ~= nil and s.Poisoned()() ~= nil or s.Diseased() ~= nil and s.Diseased()() ~= nil) or
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
local castTracker = common.createCastTracker()

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
    if not mq.TLO.Me.Gem(g.spell)() then return false end -- not memmed
    if (mq.TLO.Me.CurrentMana() or 0) < (sp.Mana() or 0) then return false end
    if not mq.TLO.Me.SpellReady(g.spell)() then return false end
    local selfCast = (id == mq.TLO.Me.ID())
    local orig = mq.TLO.Target.ID() or 0
    if not selfCast and not setTarget(id) then return false end

    castTracker.lastSpell   = g.spell
    castTracker.lastTime    = os.clock()
    castTracker.failed      = false
    castTracker.activeSpell = g.spell
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
-- Movement: plugin and distance helpers (Delegated to triune_common)
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
        mq.cmdf('/stick id %d %d', id, dist); pursuit.lastNavTargetId = id
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
        pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil
        return
    end
    -- Report the target distance at the moment of firing -- if this still
    -- fires right next to a live mob despite the checkStuck deferral above,
    -- this number is what tells us so instead of guessing again.
    local tgt = mq.TLO.Target
    local tgtNote = (tgt() and tgt.Type() == 'NPC') and
        string.format(' (target dist %.0f, desired %.0f)', distToId(tgt.ID()), desiredRange()) or ''
    print('\ay[Triune]\ax stuck -- backing up and pivoting.' .. tgtNote)
    mq.cmd('/nav stop'); mq.cmd('/stick off')
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
    pursuit.lastNavTargetId = 0; pursuit.lastNavLoc = nil -- force a fresh /nav command next tick
end

local function checkStuck()
    local now = os.clock()
    if (now - stuckState.checkAt) < 1.0 then return end
    stuckState.checkAt = now
    local trying = isMoveActive() or pursuit.id ~= 0
    local nt = mq.TLO.Target
    if nt() and nt.Type() == 'NPC' and (nt.PctHPs() or 0) > 0 and distToId(nt.ID()) <= (desiredRange() + 12) then
        trying = false
    end
    if not trying then
        stuckState.counter = 0; stuckState.lastX, stuckState.lastY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0; return
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
    local haveLiveNPC = t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0
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
    local minLv = minLevel or 1
    local maxLv = maxLevel or 100
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
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' and not isIgnored(xt.CleanName())
            and not isUnreachable(xt.ID()) then
            local lvl = xt.Level() or 0
            if lvl >= minLv and lvl <= maxLv then
                local sx, sy = xt.X() or 0, xt.Y() or 0
                if not outsideAnchor(sx, sy) then
                    return xt.ID()
                end
            end
        end
    end
    local radius = searchRadius or ctrl.hunter_radius or 200
    local maxZ = searchMaxZ or ctrl.hunter_z or 75
    local myZ = mq.TLO.Me.Z() or 0
    local search = string.format('npc targetable radius %d', radius)
    for i = 1, 10 do
        local s = mq.TLO.NearestSpawn(i, search)
        if not s() then break end -- ran out of candidates
        if s.Type() == 'NPC' and (s.PctHPs() or 0) > 0 and not isIgnored(s.CleanName())
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


-- Puller: IDLE (find a mob) -> TO_MOB (close in, tag it) -> TO_CAMP (drag it home)
-- -> FIGHTING (normal combat loop takes over via the target already being set).
local function pullerTick()
    if not ctrl.camp_loc then return end

    if not ctrl.camp_loc then return end

    if runtime.pullState == 'IDLE' then
        if mq.TLO.Me.Combat() then return end -- already fighting something; don't pull yet
        local id = findRoamTarget(ctrl.camp_radius, ctrl.camp_z, ctrl.pull_min_level, ctrl.pull_max_level)
        if id and setTarget(id) then
            runtime.pullTargetId = id; runtime.pullState = 'TO_MOB'
        end
        return
    end

    local s = mq.TLO.Spawn(runtime.pullTargetId)
    local alive = s() and s.Type() == 'NPC' and (s.PctHPs() or 0) > 0
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
            pcall(function() ahId = s.AggroHolder.ID() or 0 end)
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
    if mq.TLO.Me.Combat()   then return true end  -- melee /attack on
    if mq.TLO.Me.AutoFire() then return true end  -- ranged autofire on
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
    local myId = mq.TLO.Me.ID() or 0

    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.ID() ~= curId and xt.Type() == 'NPC' and not isUnreachable(xt.ID())
            and not isIgnored(xt.CleanName()) then
            local d = xt.Distance3D() or 999
            local isHittingMe = false
            pcall(function()
                if xt.TargetOfTarget.ID() == myId or xt.AggroHolder.ID() == myId or (xt.PctAggro() or 0) >= 100 then
                    isHittingMe = true
                end
            end)
            local maxRange = isHittingMe and 40 or 15
            if d < maxRange and d < bestDist then
                bestDist = d
                bestId = xt.ID()
            end
        end
    end
    if bestId == 0 then return false end
    if curId == 0 or curDist > 20 then
        if setTarget(bestId) then
            mq.cmd('/face fast')
            print('\ay[Triune]\ax aggro switch -> ' .. tostring(mq.TLO.Target.CleanName()))
            return true
        end
    end
    return false
end

fullStop = function()
    if navLoaded() and mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    if stickLoaded() then mq.cmd('/stick off') end
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
    local detected = common.classesFromInventoryWindow(false, true)
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
    local haveNPC = t() and t.Type() == 'NPC' and (t.PctHPs() or 0) > 0
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

        if haveNPC then
            local curId = mq.TLO.Target.ID()
            local curDist = distToId(curId)
            -- Only opportunistically swap to a closer fresh mob when xtar is
            -- fully clear. checkAggroSwitch() already handles in-fight adds,
            -- so this path is purely for "current mob is far and there's
            -- something closer" -- which must not fire mid-fight.
            if curDist > desiredRange() and curDist > 20 and not anyXtarAlive() then
                local betterId = findRoamTarget(nil, nil, ctrl.hunter_min_level, ctrl.hunter_max_level)
                if betterId and betterId ~= curId and distToId(betterId) < curDist - 10 then
                    if setTarget(betterId) then curId = betterId end
                end
            end
        else
            local id = findRoamTarget(nil, nil, ctrl.hunter_min_level, ctrl.hunter_max_level)
            if id and setTarget(id) then
                haveNPC = true
                pursuit.wanderLoc = nil
            elseif not anyXtarAlive() then
                -- Only wander out to seek fresh mobs when xtar is clear.
                -- If live xtar NPCs remain but findRoamTarget returned nil
                -- (e.g. all ignored/unreachable), do nothing this tick --
                -- they will either die, leave xtar, or be picked up once
                -- checkAggroSwitch moves them into target range.
                local arrived = pursuit.wanderLoc and
                    moveTowardLoc(pursuit.wanderLoc.x, pursuit.wanderLoc.y, pursuit.wanderLoc.z, 15)
                if not pursuit.wanderLoc or arrived or (os.clock() - (pursuit.wanderSince or 0)) > 8.0 then
                    local ang = math.random() * 2 * math.pi
                    if ctrl.hunter_combat_loc and (ctrl.hunter_combat_radius or 0) > 0 then
                        -- Anchor-bounded wander: pick a random point inside the combat circle
                        local maxR = ctrl.hunter_combat_radius
                        local minR = math.max(10, math.floor(maxR * 0.3))
                        local r    = minR + math.random(math.floor(maxR * 0.6))
                        local ax, ay = ctrl.hunter_combat_loc.x, ctrl.hunter_combat_loc.y
                        pursuit.wanderLoc = {
                            x = ax + r * math.cos(ang),
                            y = ay + r * math.sin(ang),
                            z = ctrl.hunter_combat_loc.z,
                        }
                    else
                        -- Unbounded wander: pick a random point near current position
                        local dist = 100 + math.random(150)
                        pursuit.wanderLoc = {
                            x = (mq.TLO.Me.X() or 0) + dist * math.cos(ang),
                            y = (mq.TLO.Me.Y() or 0) + dist * math.sin(ang),
                            z = mq.TLO.Me.Z() or 0,
                        }
                    end
                    pursuit.wanderSince = os.clock()
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
            if id and setTarget(id) then haveNPC = true end
        end
        if haveNPC then
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

    -- Tank/Garrison are inherently melee/tanking roles regardless of Combat
    -- Style. These, plus Hunter/Puller when actually set to Melee, flag
    -- /attack the instant a live target is picked (haveNPC) instead of
    -- waiting for moveToward to confirm "arrived in range" (engage) -- EQ's
    -- own auto-attack simply won't connect until truly in weapon range
    -- anyway, so flagging it early costs nothing, and it removes the need to
    -- get engage/distance state exactly right before combat can even start,
    -- which was the root of several race-condition bugs already fixed this
    -- session (checkStuck vs. moveToward, checkCombatStall vs. moveToward).
    -- Assist-family modes (Assist/Chase Assist/Backline) are deliberately
    -- excluded -- they wait for Assist At % on purpose, not by accident.
    local eagerMelee = (ctrl.mode == 'Tank' or ctrl.mode == 'Garrison')
        or ((ctrl.mode == 'Hunter' or ctrl.mode == 'Puller') and ctrl.combat_style == 'Melee')
    if eagerMelee then
        if haveNPC then
            if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
        elseif mq.TLO.Me.Combat() then
            mq.cmd('/attack off')
        end
    elseif ctrl.combat_style == 'Ranged' then
        if haveNPC and engage then
            if not mq.TLO.Me.AutoFire() then mq.cmd('/autofire on') end
        elseif mq.TLO.Me.AutoFire() then
            mq.cmd('/autofire off')
        end
        -- Spell style (and Pet Tank, regardless of style -- pets do the melee,
        -- that's the entire point of the mode) never auto-attacks at all; the
        -- Spell Gems loadout is the only source of damage.
    elseif ctrl.combat_style == 'Spell' or ctrl.mode == 'Pet Tank' then
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    elseif haveNPC and engage and not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
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
    if ctrl.mode == 'Manual Hunter' and haveNPC and engage and trioHasPetClass() then
        setManualHunterPetHold(false)
        local tid = t.ID() or 0
        local dueForRetry = (os.clock() - (petState.lastCmdAt or 0)) > 5.0
        if (tid ~= petState.lastCmdTargetId or dueForRetry) and not mq.TLO.Me.Casting.ID() then
            local tgtHp = pctHP(tid) or 100
            if playerHasAggro(tid) and playerIsEngagingTarget(tid)
                and tgtHp <= (ctrl.pet_assist_at or 100) then
                mq.cmd('/say #petcmd attack all')
                petState.lastCmdTargetId = tid
                petState.lastCmdAt = os.clock()
            end
        end
    elseif haveNPC and engage and trioHasPetClass() then
        local tid = t.ID() or 0
        local dueForRetry = (os.clock() - (petState.lastCmdAt or 0)) > 5.0
        if (tid ~= petState.lastCmdTargetId or dueForRetry) and not mq.TLO.Me.Casting.ID() then
            local tgtHp = pctHP(tid) or 100
            -- Pet Tank: pets ARE the tank; skip engagement gate, only apply HP threshold.
            -- All other modes: require player has started hitting AND HP threshold met.
            local readyToSend = (ctrl.mode == 'Pet Tank' and tgtHp <= (ctrl.pet_assist_at or 100))
                or (playerHasAggro(tid) and playerIsEngagingTarget(tid)
                    and tgtHp <= (ctrl.pet_assist_at or 100))
            if readyToSend then
                mq.cmd('/say #petcmd attack all')
                petState.lastCmdTargetId = tid
                petState.lastCmdAt = os.clock()
            end
        end
    else
        petState.lastCmdTargetId = 0
        if ctrl.mode == 'Manual Hunter' and not mq.TLO.Me.Combat() then
            setManualHunterPetHold(true)
        end
    end

    -- activated AAs are instant and off the spell timer: fire every eligible one,
    -- and don't let them block (or be blocked by) the spell cast below
    for name, a in pairs(loadout.aas) do
        if a.enabled then
            local id = resolveTargetId(a.target, a.cls)
            if id and conditionMet(a.when, a.pct, name, id, a.cls) then fireAA(name, a, id) end
        end
    end
    -- Gather every enabled disc/skill whose condition (and Boss Only gate, if
    -- set) is currently satisfied, then try them in priority order (lowest
    -- first) and stop at the first one that actually fires. fireDisc/fireSkill
    -- return false if the ability's own cooldown isn't up, so this is what
    -- lets "try the next disc down the list if the top one is still on
    -- cooldown" work -- exactly the same pattern gems already use (try slot
    -- 1..12 in order, break on success).
    local eligibleDiscs = {}
    for name, d in pairs(loadout.discs) do
        if d.enabled then
            local id = resolveTargetId(d.target, d.cls)
            if id and conditionMet(d.when, d.pct, name, id, d.cls) then
                local bossOk = true
                if d.boss_only then
                    local s = mq.TLO.Spawn(id)
                    bossOk = s() and s.Named()
                end
                if bossOk then
                    eligibleDiscs[#eligibleDiscs + 1] = { name = name, entry = d, id = id }
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
    end

    if not isCasting() and not isMoveActive() then
        local activeGems = ctrl.buff_mode and loadout.buffGems or loadout.gems
        for i = 1, NUM_GEMS do
            local g = activeGems[i]
            if g and g.spell and g.spell ~= '' and not castTracker.isLockedOut(g.spell) then
                local id = resolveTargetId(g.target, g.cls)
                local condOk = id and conditionMet(g.when, g.pct, g.spell, id, g.cls)
                if condOk and castGem(i, g, id) then
                    -- Durable "already applied this life" mark for beneficial
                    -- "missing buff" casts. Self-buff DETECTION is entirely
                    -- broken on this build -- confirmed live for a buff that
                    -- IS up: MyBuffCount=0, BuffCount=0, Buff("name")=nil,
                    -- index enumeration empty -- so "missing buff" reads true
                    -- forever and respams every cast (reported live: Pious
                    -- Might / Vampiric Embrace / Frenzied Strength etc. cast
                    -- endlessly, never settling). The bard code already solved
                    -- this exact problem the same way (see sungBuffs): self
                    -- buffs are PERMANENT on this server, so once cast,
                    -- remember it and don't recheck until zone/death (sungBuffs
                    -- is cleared by both). conditionMet's "missing buff" branch
                    -- already consults sungBuffs first, so marking here closes
                    -- the loop. ONLY for beneficial spells -- a detrimental DoT
                    -- on "missing buff" legitimately needs reapplying when it
                    -- wears off, and uses target-side detection, a separate
                    -- concern; and "missing pet" has working spawn detection
                    -- (isSpawnAlive) so it must NOT be marked either.
                    if g.when == 'missing buff' then
                        local bene = false
                        pcall(function() bene = mq.TLO.Spell(g.spell).Beneficial() end)
                        if bene then runtime.sungBuffs[sungKey(g.spell, id)] = true end
                    end
                    break
                elseif ctrl.debug_mode and id and condOk and (os.clock() - runtime.lastGemDiagAt) > 3.0 then
                    runtime.lastGemDiagAt = os.clock()
                    local sp = mq.TLO.Spell(g.spell)
                    local memmed, ready = false, false
                    pcall(function() memmed = mq.TLO.Me.Gem(g.spell)() ~= nil end)
                    pcall(function() ready = mq.TLO.Me.SpellReady(g.spell)() end)
                    print(string.format(
                        '\ao[Triune debug]\ax gem %d "%s" not cast -- target=%s condMet=%s memmed=%s ready=%s mana=%s/%s',
                        i, g.spell, tostring(id), tostring(condOk), tostring(memmed), tostring(ready),
                        tostring(mq.TLO.Me.CurrentMana()), tostring(sp() and sp.Mana() or '?')))
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
        print(string.format('\ag[Triune]\ax status: %s, mode: %s', ctrl.running and 'running' or 'paused', ctrl.mode))
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
    elseif cmd == 'clearcursor' or cmd == 'autoinv' or cmd == 'cursor' then
        common.clearCursor()
    elseif setTriuneMode(cmd) then
        -- mode command handled
    else
        print('\ay[Triune]\ax usage: /ac [run|pause|status|spellbook|clearcursor|<mode>]')
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
-- Main loop
-- ============================================================================
local function runMainLoop()
    while open do
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
            myClasses = detectClasses(true) -- safe here -- main loop coroutine can yield/delay
        end
        if ctrl.running then
            common.clearCursor()
        end
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
        -- combat engine: act on the loadout when running (slice 1: casting + AAs)
        if ctrl.running and not memmed and (os.clock() - runtime.lastTick) > 0.4 then
            pcall(combatTick)
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
