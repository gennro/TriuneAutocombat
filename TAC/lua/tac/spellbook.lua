---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/spellbook.lua — Triune Spellbook Browser Plugin
-- ============================================================================
-- In-process replacement for the old standalone triune_spellbook.lua script.
-- Browses the era spell database per Gestalt class with live scribed status,
-- category / level / text filters, spell inspection, and a 1-click "mem to gem"
-- queue that memorizes through the core's spellbook-aware runtime.tryMem.
--
-- Everything the standalone script duplicated from the core (theme, data
-- loading, spellbook map, memorization, class detection) now comes from the
-- plugin API, so there is one source of truth for all of it. Visibility is
-- driven by ctrl.show_spellbook (header button, Mini HUD, /ac spellbook, and
-- the Window Layout manager all flip that flag).
-- ============================================================================

local plugin = {
    id                 = 'spellbook',
    name               = 'Spellbook Browser',
    version            = '2.0.0',
    author             = 'Triune',
    description        = 'Per-class spell database browser with scribed status, filters, spell info, and a mem-to-gem queue.',
    defaultEnabled     = true,
    tickInterval       = 0.1,
    runOutOfCombatOnly = false, -- queue processing has its own combat / casting gates
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Open Spellbook', tooltip = 'Toggles the Spellbook Browser window (spellbook plugin).', flag = 'show_spellbook', desc = 'Per-class spell database browser & mem queue', headerButton = true, order = 10 },
}

local core = nil
local rt, ctrl, ImGui, mq = nil, nil, nil, nil

local KIND_LABELS = { dd = 'DD', dot = 'DoT', debuff = 'Debuff', buff = 'Buff', heal = 'Heal', pet = 'Pet', util = 'Util' }

-- Pure melee classes have no spellbook; they never get a class tab.
local NON_CASTER = { WAR = true, MNK = true, ROG = true, BER = true }

-- Global State & Data Store
local state = {
    myClasses = {},                      -- mirrored from core.myClasses each frame
    casterClasses = {},                  -- myClasses minus pure melee (the classes that actually get tabs)
    activeClassTab = 1,                  -- Selected index into casterClasses
    lvlMin = 1,
    lvlMax = 125,
    scribedOnly = true,
    searchFilter = '',
    selectedCategory = 'ALL', -- Filter: ALL, dd, dot, heal, buff, pet, util, other
    selectedSpell = nil,

    -- Gem & Queue Management
    pendingQueue = {}, -- [gemSlot] = "Spell Name"
    statusMsg = "System Ready.",
    debugLogging = true,
    bypassScribedCheck = false
}

-- ============================================================================
-- Spellbook Functions (defined locally in this file)
-- ============================================================================

local function refresh()
    ctrl = core.ctrl
    rt = core.runtime
    ImGui = core.ImGui
    mq = core.mq
    -- Mirror the core's live class list (core owns detection / persistence).
    local mine = core.myClasses
    if type(mine) == 'table' and #mine > 0 then
        state.myClasses = mine
    end
    -- Only classes with a spellbook get a tab; melee-only classes are dropped.
    local casters = {}
    for _, cls in ipairs(state.myClasses) do
        if not NON_CASTER[tostring(cls):upper()] then
            table.insert(casters, cls)
        end
    end
    state.casterClasses = casters
    if state.activeClassTab > #casters then
        state.activeClassTab = math.max(1, #casters)
        state.selectedSpell = nil
    end
end

-- ============================================================================
-- Spell database helpers & categorisation (kept verbatim from the standalone script)
-- ============================================================================
local function getClassSpells(cls)
    if not cls or type(cls) ~= 'string' or not core.DATA or not core.DATA.spells then return {} end
    if core.DATA.spells[cls] then return core.DATA.spells[cls] end

    local u = cls:upper()
    if core.DATA.spells[u] then return core.DATA.spells[u] end

    -- Try title-case (first letter upper, rest lower) which is how most keys are stored
    local titleCase = u:sub(1, 1) .. u:sub(2):lower()
    if core.DATA.spells[titleCase] then return core.DATA.spells[titleCase] end

    local aliasMap = {
        SK = 'SHD',
        SHD = 'SK',
        BST = 'Bst',
        Bst = 'BST',
        SHM = 'Shm',
        Shm = 'SHM'
    }
    local alt = aliasMap[u] or aliasMap[cls]
    if alt and core.DATA.spells[alt] then return core.DATA.spells[alt] end
    if alt then
        local altTitle = alt:sub(1, 1):upper() .. alt:sub(2):lower()
        if core.DATA.spells[altTitle] then return core.DATA.spells[altTitle] end
    end

    -- Brute force: case-insensitive scan
    for k, v in pairs(core.DATA.spells) do
        if type(k) == 'string' and k:upper() == u then
            return v
        end
        if alt and type(k) == 'string' and k:upper() == alt:upper() then
            return v
        end
    end
    return {}
end

-- ============================================================================
-- Core Character Inspection Utilities
-- ============================================================================

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
            local cl = core.cleanSpellName(name)
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
    -- SPA 103: SE_SummonPet
    if checkHasSPA(tloSpell, name, sp, 103) then
        return 'pet'
    end

    -- Item summoning SPAs: 32 (SE_SummonItem), 108 (SE_SummonItem3), 33 (SE_SummonItem2)
    if checkHasSPA(tloSpell, name, sp, 32) or checkHasSPA(tloSpell, name, sp, 108) or checkHasSPA(tloSpell, name, sp, 33) then
        return 'util'
    end

    -- Teleport / Gate / Evac SPAs: 83 (SE_Teleport), 88 (SE_Evacuate), 12 (SE_Invisibility), 41 (SE_Invisibility2), 29 (SE_InvisVsUndead), 30 (SE_InvisVsAnimals)
    if checkHasSPA(tloSpell, name, sp, 83) or checkHasSPA(tloSpell, name, sp, 88) or checkHasSPA(tloSpell, name, sp, 12) or checkHasSPA(tloSpell, name, sp, 41) or checkHasSPA(tloSpell, name, sp, 29) or checkHasSPA(tloSpell, name, sp, 30) then
        return 'util'
    end

    -- Resurrection / Corpse SPAs: 81 (SE_Resurrect), 91 (SE_SummonCorpse)
    if checkHasSPA(tloSpell, name, sp, 81) or checkHasSPA(tloSpell, name, sp, 91) then
        return 'util'
    end

    -- Crowd Control / Charm SPAs: 18 (SE_Pacify), 22 (SE_Charm), 31 (SE_Mez)
    if checkHasSPA(tloSpell, name, sp, 18) or checkHasSPA(tloSpell, name, sp, 22) or checkHasSPA(tloSpell, name, sp, 31) then
        return 'util'
    end

    -- Debuff SPAs: 11 (SE_AttackSpeed/Slow), 46 (SE_Resist debuff/Tash/Malo), 23 (SE_ArmorClass debuff), 4 (SE_STR debuff), 5 (SE_DEX debuff), 6 (SE_AGI debuff), 7 (SE_STA debuff), 8 (SE_INT debuff), 9 (SE_WIS debuff), 10 (SE_CHA debuff)
    if not bene then
        if checkHasSPA(tloSpell, name, sp, 11) or checkHasSPA(tloSpell, name, sp, 46) or checkHasSPA(tloSpell, name, sp, 23)
            or checkHasSPA(tloSpell, name, sp, 4) or checkHasSPA(tloSpell, name, sp, 5) or checkHasSPA(tloSpell, name, sp, 6) or checkHasSPA(tloSpell, name, sp, 7) then
            return 'debuff'
        end
    end

    -- 3. Match non-beneficial attack / damage / buff categories
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

-- Maps both mixed-case (data keys) and uppercase class abbreviations to EQ class IDs
local CLASS_SHORT_TO_ID = {
    War = 1,
    WAR = 1,
    Clr = 2,
    CLR = 2,
    Pal = 3,
    PAL = 3,
    Rng = 4,
    RNG = 4,
    SK = 5,
    SHD = 5,
    Dru = 6,
    DRU = 6,
    Mnk = 7,
    MNK = 7,
    Brd = 8,
    BRD = 8,
    Rog = 9,
    ROG = 9,
    Shm = 10,
    SHM = 10,
    Nec = 11,
    NEC = 11,
    Wiz = 12,
    WIZ = 12,
    Mag = 13,
    MAG = 13,
    Enc = 14,
    ENC = 14,
    Bst = 15,
    BST = 15,
    Ber = 16,
    BER = 16
}

local function getSpellLevelForClassID(sp, name, cls)
    local classId = CLASS_SHORT_TO_ID[cls]
    local myClassShort = nil
    pcall(function() myClassShort = mq.TLO.Me.Class.ShortName() end)
    local isMyClassTab = (myClassShort and myClassShort:upper() == cls:upper())

    local lvl = 0
    pcall(function()
        local tloS = nil
        if sp and sp.ID and sp.ID() > 0 then tloS = mq.TLO.Spell(sp.ID()) end
        tloS = tloS or mq.TLO.Spell(name)

        if tloS then
            if classId then
                local l = tloS.Level(classId) ---@diagnostic disable-line
                if type(l) == 'function' or type(l) == 'userdata' then l = l() end
                if type(l) == 'number' and l > 0 and l <= 125 then
                    lvl = l
                end
            end

            -- Fallback if querying current character's class tab
            if lvl == 0 and isMyClassTab then
                local l = tloS.Level
                if type(l) == 'function' or type(l) == 'userdata' then l = l() end
                if type(l) == 'number' and l > 0 and l <= 125 then
                    lvl = l
                end
            end
        end
    end)

    if lvl == 0 and sp and isMyClassTab then
        pcall(function()
            local l = sp.Level
            if type(l) == 'function' or type(l) == 'userdata' then l = l() end
            if type(l) == 'number' and l > 0 and l <= 125 then
                lvl = l
            end
        end)
    end

    return lvl
end

local activeSpellsCache = {}
local lastActiveSpellsTime = 0
local lastActiveSpellsClass = ""

local function getActiveClassSpells(cls)
    local now = os.time()
    if lastActiveSpellsClass == cls and (now - lastActiveSpellsTime) < 3 and #activeSpellsCache > 0 then
        return activeSpellsCache
    end

    local outList = {}
    local scribedNormMap = {}

    local dbSpells = getClassSpells(cls) or {}
    local dbLookup = {}
    for _, row in ipairs(dbSpells) do
        local dName, dLvl, dBene, dKind = row[1], row[2], row[3], row[4]
        dbLookup[core.normalizeSpellName(dName)] = {
            level = tonumber(dLvl) or 1,
            bene = (dBene == 1 or dBene == true),
            kind = dKind or 'other'
        }
        dbLookup[dName:lower()] = dbLookup[core.normalizeSpellName(dName)]
        dbLookup[core.cleanSpellName(dName):lower()] = dbLookup[core.normalizeSpellName(dName)]
    end

    for slot = 1, 720 do
        local sp = mq.TLO.Me.Book(slot)
        local name = nil

        pcall(function()
            local res = sp()
            if type(res) == "string" and res ~= "" and res ~= "NULL" then name = res end
        end)
        if not name then
            pcall(function()
                local rawName = sp.Name
                local res = (type(rawName) == 'function' or type(rawName) == 'userdata') and rawName() or rawName
                if type(res) == "string" and res ~= "" and res ~= "NULL" then name = res end
            end)
        end

        if name and name ~= "" and name ~= "NULL" then
            local lvl = getSpellLevelForClassID(sp, name, cls)

            local dbEntry = nil
            if lvl == 0 then
                dbEntry = dbLookup[core.normalizeSpellName(name)]
                    or dbLookup[name:lower()]
                    or dbLookup[core.cleanSpellName(name):lower()]
                if dbEntry then lvl = dbEntry.level end
            end

            if lvl > 0 then
                local bene = true
                if dbEntry then
                    bene = dbEntry.bene
                else
                    pcall(function()
                        local tloS = (sp and sp.ID and sp.ID() > 0) and mq.TLO.Spell(sp.ID()) or mq.TLO.Spell(name)
                        if tloS then
                            local b = tloS.Beneficial
                            if type(b) == 'function' or type(b) == 'userdata' then b = b() end
                            if type(b) == 'boolean' then bene = b end
                        end
                    end)
                end

                local kind = mapTLOCategoryToKind(sp, name)
                if not kind or kind == 'other' then kind = (dbEntry and dbEntry.kind) or 'other' end

                local normName = core.normalizeSpellName(name)
                scribedNormMap[normName] = true
                scribedNormMap[name:lower()] = true
                scribedNormMap[core.cleanSpellName(name):lower()] = true

                table.insert(outList, {
                    name = name,
                    level = lvl,
                    bene = bene,
                    kind = kind or 'other',
                    scribed = true,
                    slot = slot
                })
            end
        end
    end

    for _, row in ipairs(dbSpells) do
        local dName, dLvl, dBene, dKind = row[1], row[2], row[3], row[4]
        local dNorm = core.normalizeSpellName(dName)
        local dLower = dName:lower()
        local dCleanLower = core.cleanSpellName(dName):lower()

        if not scribedNormMap[dNorm] and not scribedNormMap[dLower] and not scribedNormMap[dCleanLower] then
            local dynamicKind = mapTLOCategoryToKind(nil, dName)
            if dynamicKind == 'other' or not dynamicKind then dynamicKind = dKind or 'other' end
            table.insert(outList, {
                name = dName,
                level = tonumber(dLvl) or 1,
                bene = (dBene == 1 or dBene == true),
                kind = dynamicKind,
                scribed = false,
                slot = nil
            })
        end
    end

    table.sort(outList, function(a, b)
        local lvlA = tonumber(a.level) or 1
        local lvlB = tonumber(b.level) or 1
        if lvlA == lvlB then
            return a.name < b.name
        end
        return lvlA < lvlB
    end)

    activeSpellsCache = outList
    lastActiveSpellsTime = now
    lastActiveSpellsClass = cls
    return outList
end

local function showSpellInfo(name)
    if not name or name == "" then return end
    local inspected = false
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then
            sp.Inspect()
            inspected = true
            return
        end
        local clean = core.cleanSpellName(name)
        if clean ~= "" and clean ~= name then
            sp = mq.TLO.Spell(clean)
            if sp and sp() then
                sp.Inspect()
                inspected = true
                return
            end
        end
        local bookSlot = rt.getSpellBookSlot(name) or (clean ~= "" and rt.getSpellBookSlot(clean))
        if bookSlot and bookSlot > 0 then
            local bsp = mq.TLO.Me.Book(bookSlot)
            if bsp and bsp() then
                bsp.Inspect()
                inspected = true
                return
            end
        end
    end)
    if inspected then
        state.statusMsg = "Showing spell info: " .. name
        if state.debugLogging then
            print(string.format("\ag[Spellbook DBG]\ax Inspected spell [%s]", name))
        end
    else
        state.statusMsg = "Could not inspect: " .. name
    end
end

-- ----------------------------------------------------------------------------
-- Mem queue (drained one gem per tick on the main coroutine, like the old loop)
-- ----------------------------------------------------------------------------
local function processQueue()
    if not next(state.pendingQueue) then return end
    local busy = false
    pcall(function()
        busy = mq.TLO.Me.Combat() or mq.TLO.Me.Moving() or (rt.isCasting and rt.isCasting())
    end)
    if busy then return end
    for slot, spellName in pairs(state.pendingQueue) do
        if spellName then
            local cleanName = core.cleanSpellName(spellName)
            local currentGem = mq.TLO.Me.Gem(slot).Name() or ""
            if currentGem == cleanName or currentGem == spellName then
                state.pendingQueue[slot] = nil
                state.statusMsg = "Finished memming " .. cleanName
            else
                local ok = rt.tryMem(slot, spellName, state.bypassScribedCheck)
                if ok then
                    state.statusMsg = "Finished memming " .. cleanName
                else
                    state.statusMsg = "Mem failed for " .. cleanName
                end
                state.pendingQueue[slot] = nil
            end
            break
        end
    end
end

-- ============================================================================
-- Window
-- ============================================================================
local function drawWindow()
    if not ctrl.show_spellbook then return end

    core.pushTheme()

    ImGui.SetNextWindowSize(880, 580, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(
            ImGuiWindowFlags.AlwaysUseWindowPadding or 0,
            ImGuiWindowFlags.HorizontalScrollbar or 0
        ) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('spellbook')
    local open, show = ImGui.Begin('Triune Spellbook Engine v' .. (core.VERSION or '') .. '###triuneSpellbook', ctrl.show_spellbook, windowFlags)
    if not open then
        ctrl.show_spellbook = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not show then
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('spellbook')

    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "ACTIVE GESTALT TRIO:")
    ImGui.SameLine()

    local tabs = state.casterClasses
    if #tabs == 0 then
        ImGui.TextDisabled("No caster classes detected")
        ImGui.SameLine()
    end
    for i = 1, #tabs do
        local clsName = tabs[i]
        local isSelected = (state.activeClassTab == i)

        if isSelected then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.15, 0.18, 0.22, 1.0)
        end

        if ImGui.Button(clsName .. "##Tab_" .. i, 110, 26) then
            state.activeClassTab = i
            state.selectedSpell = nil
        end
        ImGui.PopStyleColor()

        ImGui.SameLine()
    end

    if ImGui.SmallButton("Re-detect##Classes") then
        if core.requestClassRedetect then core.requestClassRedetect() end
        state.statusMsg = "Re-detecting character classes..."
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', "Re-scan player gestalt classes from inventory or config")
    end

    ImGui.Separator()

    local availW, availH = ImGui.GetContentRegionAvail()
    local bottomBarH = 26
    local contentH = math.max(100, availH - bottomBarH)
    local rightW = 280
    local leftW = math.max(260, availW - rightW - 8)

    -- Left Pane: Spellbook Browser
    if ImGui.BeginChild('##SpellbookBrowserPane', leftW, contentH, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        local cats = { 'ALL', 'dd', 'dot', 'debuff', 'buff', 'heal', 'pet', 'util' }
        for i, c in ipairs(cats) do
            local isCat = (state.selectedCategory == c)
            if isCat then ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.6, 0.9, 1.0) end

            if ImGui.Button((KIND_LABELS[c] or c:upper()) .. "##cat_" .. c, 56, 22) then
                state.selectedCategory = c
            end

            if isCat then ImGui.PopStyleColor() end
            if i < #cats then ImGui.SameLine() end
        end

        ImGui.Spacing()

        ImGui.SetNextItemWidth(65)
        state.lvlMin = ImGui.SliderInt("Min##Lvl", state.lvlMin or 1, 1, 125)
        ImGui.SameLine()

        ImGui.SetNextItemWidth(65)
        state.lvlMax = ImGui.SliderInt("Max##Lvl", state.lvlMax or 125, 1, 125)
        ImGui.SameLine()

        state.scribedOnly = ImGui.Checkbox("Scribed Only", state.scribedOnly)
        ImGui.SameLine()

        ImGui.Text("Search:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(-1)
        state.searchFilter = ImGui.InputText("##SearchFilter", state.searchFilter or '')

        local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
        if ImGui.BeginTable("SpellTable", 4, tableFlags, 0, 0) then
            ImGui.TableSetupColumn("Level", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 55)
            ImGui.TableSetupColumn("Spell Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 85)
            ImGui.TableHeadersRow()

            local activeClass = state.casterClasses[state.activeClassTab]
            local classSpells = activeClass and getActiveClassSpells(activeClass) or {}

            local minLvl = tonumber(state.lvlMin) or 1
            local maxLvl = tonumber(state.lvlMax) or 125
            local currentFilter = tostring(state.searchFilter or ''):lower()

            for _, item in ipairs(classSpells) do
                local name = item.name
                local lvl = item.level
                local bene = item.bene
                local kind = item.kind
                local scribed = item.scribed

                local passCat = (state.selectedCategory == 'ALL')
                    or (kind == state.selectedCategory)
                    or (state.selectedCategory == 'other' and (not kind or kind == '' or not KIND_LABELS[kind]))
                local passLvl = (type(lvl) == 'number' and lvl >= minLvl and lvl <= maxLvl)
                local passScribed = (not state.scribedOnly or scribed)
                local passText = (currentFilter == '' or name:lower():find(currentFilter, 1, true) ~= nil)

                if passCat and passLvl and passScribed and passText then
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    ImGui.Text(tostring(lvl))

                    ImGui.TableSetColumnIndex(1)
                    ImGui.TextColored(0.8, 0.8, 0.2, 1.0,
                        KIND_LABELS[kind] or (kind and kind ~= '' and kind:upper()) or 'Other')

                    ImGui.TableSetColumnIndex(2)
                    local isSel = (state.selectedSpell and state.selectedSpell.name == name)
                    if ImGui.Selectable(name .. "##sel_" .. name, isSel, ImGuiSelectableFlags.SpanAllColumns) then
                        state.selectedSpell = { name = name, level = lvl, kind = kind, bene = bene }
                    end
                    if ImGui.IsItemClicked(1) then
                        showSpellInfo(name)
                    end
                    if ImGui.IsItemHovered() then
                        local tip = string.format("%s (Level %s %s)\n- Left-click: Select for memorizing\n- Right-click: Show spell info in EQ",
                            name, tostring(lvl), KIND_LABELS[kind] or (kind and kind ~= '' and kind:upper()) or 'Spell')
                        ImGui.SetTooltip('%s', tip)
                    end

                    ImGui.TableSetColumnIndex(3)
                    if scribed then
                        ImGui.TextColored(0.2, 0.9, 0.3, 1.0, "[Scribed]")
                    else
                        ImGui.TextDisabled("[Unscribed]")
                    end
                end
            end
            ImGui.EndTable()
        end
    end
    ImGui.EndChild()

    ImGui.SameLine(0, 8)

    -- Right Pane: Current Gem Loadout
    if ImGui.BeginChild('##SpellGemsPane', rightW, contentH, true, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
        local numGems = 8
        pcall(function() numGems = mq.TLO.Me.NumGems() or 8 end)

        ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "SPELL GEMS")
        ImGui.SameLine()
        ImGui.TextDisabled(string.format("(%d Slots)", numGems))

        ImGui.Separator()

        if state.selectedSpell then
            ImGui.TextColored(1.0, 0.85, 0.3, 1.0, "Selected:")
            ImGui.SameLine()
            if ImGui.SmallButton("Clear##ClearSel") then
                state.selectedSpell = nil
            end
            ImGui.TextColored(0.2, 0.9, 0.4, 1.0, tostring(state.selectedSpell.name))
            ImGui.TextDisabled("Click a gem slot below to memorize.")
        else
            ImGui.TextDisabled("Click spell to assign, or")
            ImGui.TextDisabled("right-click gem to inspect.")
        end

        ImGui.Separator()

        for g = 1, numGems do
            local currentSpell = "Empty"
            pcall(function()
                local val = mq.TLO.Me.Gem(g).Name()
                if val and val ~= "" and val ~= "NULL" then
                    currentSpell = val
                end
            end)

            local pendingSpell = state.pendingQueue[g]
            local isPending = (pendingSpell ~= nil)

            local displayLabel
            if isPending then
                displayLabel = string.format("G%d: %s (Memming)", g, pendingSpell)
            elseif currentSpell ~= "Empty" then
                displayLabel = string.format("G%d: %s", g, currentSpell)
            else
                displayLabel = string.format("G%d: <Empty>", g)
            end

            if isPending then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.1, 0.85)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.6, 0.2, 1.0)
            elseif currentSpell ~= "Empty" then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.12, 0.38, 0.22, 0.85)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.18, 0.50, 0.30, 1.0)
            else
                ImGui.PushStyleColor(ImGuiCol.Button, 0.18, 0.20, 0.24, 0.60)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.25, 0.28, 0.32, 0.80)
            end

            local btnW = ImGui.GetContentRegionAvail()
            if ImGui.Button(displayLabel .. "##GemSlot_" .. g, btnW, 28) then
                if state.selectedSpell then
                    state.pendingQueue[g] = state.selectedSpell.name
                    if state.debugLogging then
                        print(string.format("\ag[Spellbook DBG]\ax Queued [%s] for Gem %d", state.selectedSpell.name, g))
                    end
                else
                    mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', g - 1)
                end
            end

            if ImGui.IsItemClicked(1) then
                mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', g - 1)
            end

            ImGui.PopStyleColor(2)

            if ImGui.IsItemHovered() then
                local tip
                if isPending then
                    tip = string.format("Gem %d: Queued for memorization: %s", g, pendingSpell)
                elseif currentSpell ~= "Empty" then
                    tip = string.format("Gem %d: %s\n- Left-click with selected spell to replace\n- Right-click to inspect/unmem in EQ", g, currentSpell)
                else
                    tip = string.format("Gem %d: (Empty)\n- Select a spell on the left, then click here to memorize", g)
                end
                ImGui.SetTooltip('%s', tip)
            end

            if g < numGems then
                ImGui.Spacing()
            end
        end
    end
    ImGui.EndChild()

    ImGui.Separator()

    if next(state.pendingQueue) then
        ImGui.TextColored(1.0, 0.7, 0.0, 1.0, "MEMORIZING QUEUE ACTIVE...")
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Status:")
    end

    ImGui.SameLine()
    ImGui.Text(state.statusMsg)

    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_spellbook == nil then ctrl.show_spellbook = false end
    state.pendingQueue = {}
    state.selectedSpell = nil
    state.statusMsg = "System Ready."
end

function plugin.onDestroy()
    state.pendingQueue = {}
end

function plugin.onTick()
    if not core then return end
    refresh()
    processQueue()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    drawWindow()
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Spellbook Browser')
    local isWinOpen = (ctrl.show_spellbook == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##sbToggleWin', 250, 24) then
        ctrl.show_spellbook = not isWinOpen
        core.saveLoadout(true)
    end
    local dbg = ImGui.Checkbox('Debug logging##sbDebug', state.debugLogging == true)
    if dbg ~= (state.debugLogging == true) then state.debugLogging = dbg end
    local byp = ImGui.Checkbox('Bypass scribed check when memorizing##sbBypass', state.bypassScribedCheck == true)
    if byp ~= (state.bypassScribedCheck == true) then state.bypassScribedCheck = byp end
    ImGui.TextDisabled(string.format('Classes: %s | Queue: %d pending', table.concat(state.myClasses or {}, ' / '), (function() local n = 0 for _ in pairs(state.pendingQueue) do n = n + 1 end return n end)()))
end

-- /ac spellbook | book toggles the window (was: /lua run triune_spellbook)
function plugin.onCommand(cmd)
    if cmd ~= 'spellbook' and cmd ~= 'book' then return false end
    refresh()
    ctrl.show_spellbook = not ctrl.show_spellbook
    core.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Spellbook Browser %s.', ctrl.show_spellbook and 'OPENED' or 'CLOSED'))
    return true
end

plugin.help = {
    '  \ag/ac spellbook | book\ax - Toggle the Spellbook Browser window',
}

-- Exposed for tests
plugin.state = state
plugin.getClassSpells = getClassSpells
plugin.getActiveClassSpells = getActiveClassSpells
plugin.processQueue = processQueue

return plugin
