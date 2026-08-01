-- ============================================================================
-- TRIUNE SPELLBOOK ENGINE (Standalone ImGui Script)
-- ----------------------------------------------------------------------------
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library
local common = require('triune_common')

-- Script Control State
local openGUI = true
local isRunning = true

local KIND_LABELS = { dd = 'DD', dot = 'DoT', heal = 'Heal', buff = 'Buff', pet = 'Pet', util = 'Util', other = 'Other' }

-- Global State & Data Store
local state = {
    myClasses = { 'War', 'Clr', 'Pal' }, -- Default fallback trio (mixed-case to match triune_data.lua keys)
    activeClassTab = 1,                  -- Selected class tab index
    lvlMin = 1,
    lvlMax = 125,
    scribedOnly = false,
    searchFilter = '',
    selectedCategory = 'ALL', -- Filter: ALL, dd, dot, heal, buff, pet, util, other
    selectedSpell = nil,

    -- Gem & Queue Management
    pendingQueue = {}, -- [gemSlot] = "Spell Name"
    statusMsg = "System Ready.",
    debugLogging = true,
    bypassScribedCheck = false,

    -- Loadout Presets Store
    presetNames = { "Solo / DPS", "Group Healing", "Buff Suite" },
    presets = {
        ["Solo / DPS"] = {},
        ["Group Healing"] = {},
        ["Buff Suite"] = {}
    }
}

-- Spell Database Store
local DATA = { spells = {} }

local function loadData()
    -- Try multiple locations for triune_data.lua
    local paths = {
        mq.configDir .. '/triune_data.lua',
    }
    -- Also try the lua scripts directory (where the spellbook itself lives)
    pcall(function()
        if mq.luaDir then
            table.insert(paths, mq.luaDir .. '/triune_data.lua')
        end
    end)

    for _, path in ipairs(paths) do
        local f = loadfile(path)
        if f then
            local ok, t = pcall(f)
            if ok and type(t) == 'table' and t.spells then
                DATA = t
                -- Count how many class keys we got
                local classCount = 0
                local classKeys = {}
                for k, _ in pairs(DATA.spells) do
                    classCount = classCount + 1
                    classKeys[#classKeys + 1] = tostring(k)
                end
                print(string.format('\\ag[Spellbook]\\ax Loaded triune_data.lua from: %s (%d class keys: %s)',
                    path, classCount, table.concat(classKeys, ', ')))
                state.statusMsg = string.format("Loaded data: %d classes", classCount)
                return
            else
                print(string.format('\\ar[Spellbook]\\ax Found %s but failed to parse: ok=%s type=%s',
                    path, tostring(ok), type(t)))
            end
        end
    end
    print('\\ar[Spellbook]\\ax triune_data.lua not found in any of: ' .. table.concat(paths, ', '))
    state.statusMsg = "triune_data.lua not found!"
end

local function getClassSpells(cls)
    if not cls or type(cls) ~= 'string' or not DATA.spells then return {} end
    if DATA.spells[cls] then return DATA.spells[cls] end

    local u = cls:upper()
    if DATA.spells[u] then return DATA.spells[u] end

    -- Try title-case (first letter upper, rest lower) which is how most keys are stored
    local titleCase = u:sub(1, 1) .. u:sub(2):lower()
    if DATA.spells[titleCase] then return DATA.spells[titleCase] end

    local aliasMap = {
        SK = 'SHD',
        SHD = 'SK',
        BST = 'Bst',
        Bst = 'BST',
        SHM = 'Shm',
        Shm = 'SHM'
    }
    local alt = aliasMap[u] or aliasMap[cls]
    if alt and DATA.spells[alt] then return DATA.spells[alt] end
    if alt then
        local altTitle = alt:sub(1, 1):upper() .. alt:sub(2):lower()
        if DATA.spells[altTitle] then return DATA.spells[altTitle] end
    end

    -- Brute force: case-insensitive scan
    for k, v in pairs(DATA.spells) do
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


-- Note: cleanSpellName, normalizeSpellName, checkBook, getSpellbookMap, getSpellBookSlot, and isScribed are provided by triune_common.lua

local function checkHasSPA103(name, sp)
    local isPet = false
    pcall(function()
        if sp and sp.ID and sp.ID() > 0 then
            local res = mq.TLO.Spell(sp.ID()).HasSPA(103)
            if res == true or res == 1 then isPet = true end
            if not isPet and (type(res) == 'function' or type(res) == 'userdata') then
                local ok, r2 = pcall(res)
                if ok and (r2 == true or r2 == 1) then isPet = true end
            end
        end
    end)
    if not isPet and name and name ~= "" then
        pcall(function()
            local res = mq.TLO.Spell(name).HasSPA(103)
            if res == true or res == 1 then isPet = true end
            if not isPet and (type(res) == 'function' or type(res) == 'userdata') then
                local ok, r2 = pcall(res)
                if ok and (r2 == true or r2 == 1) then isPet = true end
            end
        end)
    end
    return isPet
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
            local cl = common.cleanSpellName(name)
            if cl ~= name then tloSpell = mq.TLO.Spell(cl) end
        end)
    end
    if not tloSpell and type(sp) == 'userdata' then
        tloSpell = sp
    end

    -- 1. Check SPA 103 (SE_SummonPet) for 100% accurate pet spell classification
    if checkHasSPA103(name, sp) then
        return 'pet'
    end

    -- 2. Extract Category and Subcategory strings safely
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

    -- 3. Match category strings
    if catStr:find('pet') or subcatStr:find('pet') or catStr:find('summon') or subcatStr:find('summon') then
        return 'pet'
    elseif catStr:find('heal') or subcatStr:find('heal') or catStr:find('restore') or subcatStr:find('restore') then
        return 'heal'
    elseif catStr:find('dot') or catStr:find('damage over time') or subcatStr:find('dot') or subcatStr:find('damage over time') then
        return 'dot'
    elseif catStr:find('direct damage') or catStr:find('nuke') or catStr:find('dd') or subcatStr:find('direct damage') or subcatStr:find('nuke') then
        return 'dd'
    elseif catStr:find('buff') or catStr:find('stat') or catStr:find('resist') or subcatStr:find('buff') or catStr:find('aura') or subcatStr:find('aura') then
        return 'buff'
    elseif catStr:find('transport') or catStr:find('travel') or catStr:find('utility') or catStr:find('misc') or catStr:find('teleport') or catStr:find('gate') or catStr:find('illusion') then
        return 'util'
    end

    -- 4. Beneficial check fallback
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
    local myClassShort = mq.TLO.Me.Class.ShortName()
    local isMyClassTab = (myClassShort and myClassShort:upper() == cls:upper())

    local lvl = 0
    pcall(function()
        local tloS = nil
        if sp and sp.ID and sp.ID() > 0 then tloS = mq.TLO.Spell(sp.ID()) end
        tloS = tloS or mq.TLO.Spell(name)

        if tloS then
            if classId then
                local l = tloS.Level(classId)
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

    -- Pre-build a lookup from triune_data.lua for this class so we can fall
    -- back when Spell.Level(classId) returns 0 (common on multi-class servers
    -- where MQ only recognises the "primary" class).
    local dbSpells = getClassSpells(cls)
    local dbLookup = {} -- normalizedName -> { level, bene, kind }
    for _, row in ipairs(dbSpells) do
        local dName, dLvl, dBene, dKind = row[1], row[2], row[3], row[4]
        dbLookup[common.normalizeSpellName(dName)] = {
            level = tonumber(dLvl) or 1,
            bene = (dBene == 1 or dBene == true),
            kind =
                dKind or 'other'
        }
        dbLookup[dName:lower()] = dbLookup[common.normalizeSpellName(dName)]
        dbLookup[common.cleanSpellName(dName):lower()] = dbLookup[common.normalizeSpellName(dName)]
    end

    -- 1. For scribed spells: query live Me.Book(slot), then try Level(classId),
    --    then fall back to the triune_data DB lookup.
    for slot = 1, 720 do
        local sp = mq.TLO.Me.Book(slot)
        local name = nil

        pcall(function()
            local res = sp()
            if type(res) == "string" and res ~= "" and res ~= "NULL" then name = res end
        end)
        if not name then
            pcall(function()
                local res = sp.Name
                if type(res) == 'function' or type(res) == 'userdata' then res = res() end
                if type(res) == "string" and res ~= "" and res ~= "NULL" then name = res end
            end)
        end

        if name and name ~= "" and name ~= "NULL" then
            local lvl = getSpellLevelForClassID(sp, name, cls)

            -- Fallback: if TLO couldn't determine level for this class,
            -- check our triune_data DB for a match.
            local dbEntry = nil
            if lvl == 0 then
                dbEntry = dbLookup[common.normalizeSpellName(name)]
                    or dbLookup[name:lower()]
                    or dbLookup[common.cleanSpellName(name):lower()]
                if dbEntry then lvl = dbEntry.level end
            end

            -- If lvl > 0, this scribed spell IS usable by class `cls`!
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

                local kind = (dbEntry and dbEntry.kind) or mapTLOCategoryToKind(sp, name)

                local normName = common.normalizeSpellName(name)
                scribedNormMap[normName] = true
                scribedNormMap[name:lower()] = true
                scribedNormMap[common.cleanSpellName(name):lower()] = true

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

    -- 2. For unscribed spells: ONLY pull from triune_data.lua if spell is NOT scribed
    -- (dbSpells already fetched above for the fallback lookup)
    for _, row in ipairs(dbSpells) do
        local dName, dLvl, dBene, dKind = row[1], row[2], row[3], row[4]
        local dNorm = common.normalizeSpellName(dName)
        local dLower = dName:lower()
        local dCleanLower = common.cleanSpellName(dName):lower()

        if not scribedNormMap[dNorm] and not scribedNormMap[dLower] and not scribedNormMap[dCleanLower] then
            table.insert(outList, {
                name = dName,
                level = tonumber(dLvl) or 1,
                bene = (dBene == 1 or dBene == true),
                kind = dKind or 'other',
                scribed = false,
                slot = nil
            })
        end
    end

    -- Sort by Level ascending, then Name
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

-- ============================================================================
-- Anti-Cheat Safe Auto-Memorization Engine
-- ============================================================================

local function processQueue()
    for slot, spellName in pairs(state.pendingQueue) do
        if spellName then
            local cleanName = common.cleanSpellName(spellName)
            local currentGem = mq.TLO.Me.Gem(slot).Name() or ""
            if currentGem == cleanName or currentGem == spellName then
                state.pendingQueue[slot] = nil
                state.statusMsg = "Finished memming " .. cleanName
            else
                local ok = common.tryMem(slot, spellName, state.bypassScribedCheck)
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
-- ImGui Rendering Dashboard
-- ============================================================================

local function DrawTriuneUI()
    if not openGUI then
        isRunning = false
        return
    end

    common.pushTheme()

    ImGui.SetNextWindowSize(820, 560, ImGuiCond.FirstUseEver)
    local open, draw = ImGui.Begin('Triune Spellbook Engine##Main', openGUI, ImGuiWindowFlags.MenuBar)
    if not open then
        openGUI = false
        isRunning = false
        ImGui.End()
        common.popTheme()
        return
    end

    -- Menu Bar
    if ImGui.BeginMenuBar() then
        if ImGui.BeginMenu("Gestalt Options") then
            if ImGui.MenuItem("Re-detect Classes") then
                state.myClasses = common.detectClasses()
            end
            if ImGui.MenuItem("Clear Pending Queue") then
                state.pendingQueue = {}
                state.statusMsg = "Queue cleared."
            end
            ImGui.Separator()
            state.debugLogging = ImGui.MenuItem("Enable Console Debug Logging", nil, state.debugLogging)
            state.bypassScribedCheck = ImGui.MenuItem("Bypass Scribed Book Check", nil, state.bypassScribedCheck)
            ImGui.Separator()
            if ImGui.MenuItem("Dump Diagnostics to MQ Console") then
                print("\ay================ SPELLBOOK DIAGNOSTICS ================\ax")
                print(string.format("Character: %s | Level: %s | Class: %s", tostring(mq.TLO.Me.CleanName()),
                    tostring(mq.TLO.Me.Level()), tostring(mq.TLO.Me.Class.ShortName())))
                print(string.format("Detected Trio Classes: %s", table.concat(state.myClasses, ", ")))
                print(string.format("Num Gems: %s", tostring(mq.TLO.Me.NumGems())))
                for g = 1, mq.TLO.Me.NumGems() or 8 do
                    print(string.format("  Gem %d: %s", g, tostring(mq.TLO.Me.Gem(g).Name())))
                end
                print("Pending Queue:")
                for k, v in pairs(state.pendingQueue) do
                    print(string.format("  Gem %d => %s", k, tostring(v)))
                end
                print("\ay========================================================\ax")
            end
            if ImGui.MenuItem("Dump Spellbook Reading to MQ Console") then
                print("\ay================ SPELLBOOK READ DUMP ================\ax")
                print(string.format("Character: %s | Level: %s | Class: %s", tostring(mq.TLO.Me.CleanName()),
                    tostring(mq.TLO.Me.Level()), tostring(mq.TLO.Me.Class.ShortName())))
                print(string.format("Detected Trio Classes: %s", table.concat(state.myClasses or {}, ", ")))

                print("\ay--- DATABASE & CLASS KEYS --- \ax")
                if DATA and DATA.spells then
                    local keys = {}
                    for k, v in pairs(DATA.spells) do
                        table.insert(keys, string.format("%s (%d spells)", tostring(k), type(v) == 'table' and #v or 0))
                    end
                    print("Class Keys in DATA.spells: " .. table.concat(keys, ", "))
                else
                    print("\arDATA.spells is nil or not loaded!\ax")
                end

                local bstSpells = getClassSpells('BST')
                print(string.format("Beastlord (BST) Spells in DB: %d", #bstSpells))

                print("\ay--- LIVE SPELLBOOK SLOTS (1..720) --- \ax")
                local count = 0
                for slot = 1, 720 do
                    local name = nil
                    local id = nil
                    local lvl = nil
                    pcall(function() name = mq.TLO.Me.Book(slot).Name() end)
                    pcall(function() id = mq.TLO.Me.Book(slot).ID() end)
                    pcall(function() lvl = mq.TLO.Me.Book(slot).Level() end)
                    if not name or name == "" or name == "NULL" then
                        pcall(function()
                            local res = mq.TLO.Me.Book(slot)()
                            if type(res) == "string" and res ~= "" and res ~= "NULL" then name = res end
                        end)
                    end
                    if name and name ~= "" and name ~= "NULL" then
                        count = count + 1
                        local sp = mq.TLO.Me.Book(slot)
                        local cat, subcat, kind = "-", "-", "-"
                        pcall(function() cat = tostring(sp.Category() or '-') end)
                        pcall(function() subcat = tostring(sp.Subcategory() or '-') end)
                        pcall(function() kind = mapTLOCategoryToKind(sp) end)

                        print(string.format("  [Slot %3d] %-30s (ID: %-5s, Lvl: %-2s, Cat: %s / %s, Kind: %s)",
                            slot, tostring(name), tostring(id or '-'), tostring(lvl or '-'), cat, subcat, kind:upper()))
                    end
                end
                print(string.format("Total Scribed Spells Found: %d", count))

                print("\ay--- BST SPELL SCRIBED CHECK DIAGNOSTICS --- \ax")
                if #bstSpells == 0 then
                    print("\arNo Beastlord (BST) spells found in DATA.spells to test!\ax")
                else
                    for idx, row in ipairs(bstSpells) do
                        local sName, sLvl, sBene, sKind = row[1], row[2], row[3], row[4]
                        local slotFound = common.getSpellBookSlot(sName)
                        local scribedStatus = slotFound and string.format("\ag[Scribed in Slot %d]\ax", slotFound) or
                            "\ar[Unscribed]\ax"
                        print(string.format("  Lvl %3d [%-4s] %-30s => %s", tonumber(sLvl) or 0, tostring(sKind or ""),
                            tostring(sName), scribedStatus))
                    end
                end
                print("\ay========================================================\ax")
                state.statusMsg = "Dumped spellbook reading diagnostics to console."
            end
            ImGui.EndMenu()
        end
        ImGui.EndMenuBar()
    end

    -- Gestalt Class Selector Tabs
    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "ACTIVE GESTALT TRIO:")
    ImGui.SameLine()

    for i = 1, 3 do
        local clsName = state.myClasses[i] or ("Slot " .. i)
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

        if i < 3 then ImGui.SameLine() end
    end

    ImGui.SameLine(ImGui.GetWindowWidth() - 140)
    if ImGui.Button("Unmem All Gems", 125, 26) then
        mq.cmd('/clearspellsauto')
        state.statusMsg = "Cleared all spell gems."
    end

    ImGui.Separator()

    -- Visual Spell Gem Rack
    ImGui.TextDisabled("CURRENT GEM LOADOUT (CLICK SLOT TO ASSIGN SELECTED SPELL)")

    local numGems = mq.TLO.Me.NumGems() or 8
    local availWidth = ImGui.GetContentRegionAvail()
    local gemBtnWidth = math.floor((availWidth - ((numGems - 1) * 4)) / numGems)

    for g = 1, numGems do
        local currentSpell = mq.TLO.Me.Gem(g).Name() or "Empty"
        local isPending = state.pendingQueue[g] ~= nil
        local displayLabel = isPending and "Memming..." or currentSpell

        if isPending then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.1, 0.8)
        elseif currentSpell ~= "Empty" then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.1, 0.4, 0.2, 0.8)
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.2, 0.2, 0.6)
        end

        if ImGui.Button(string.format("G%d\n%s##GemBar_%d", g, displayLabel:sub(1, 9), g), gemBtnWidth, 42) then
            if state.selectedSpell then
                state.pendingQueue[g] = state.selectedSpell.name
                if state.debugLogging then
                    print(string.format("\ag[Spellbook DBG]\ax Queued [%s] for Gem %d", state.selectedSpell.name, g))
                end
            else
                mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', g - 1)
            end
        end
        ImGui.PopStyleColor()

        if g < numGems then ImGui.SameLine(0, 4) end
    end

    ImGui.Spacing()
    ImGui.Separator()

    -- Main Workspace Tabs
    if ImGui.BeginTabBar("MainWorkspaceTabs") then
        -- Tab 1: Spellbook Browser
        if ImGui.BeginTabItem("Spellbook Browser##Tab") then
            -- Category Filters
            local cats = { 'ALL', 'dd', 'dot', 'heal', 'buff', 'pet', 'util', 'other' }
            for _, c in ipairs(cats) do
                local isCat = (state.selectedCategory == c)
                if isCat then ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.6, 0.9, 1.0) end

                if ImGui.Button((KIND_LABELS[c] or c:upper()) .. "##cat_" .. c, 60, 22) then
                    state.selectedCategory = c
                end

                if isCat then ImGui.PopStyleColor() end
                ImGui.SameLine()
            end

            ImGui.Spacing()

            -- Level & Text Filters
            ImGui.SetNextItemWidth(120)
            state.lvlMin = ImGui.SliderInt("Min Lvl", state.lvlMin or 1, 1, 125)
            ImGui.SameLine()

            ImGui.SetNextItemWidth(120)
            state.lvlMax = ImGui.SliderInt("Max Lvl", state.lvlMax or 125, 1, 125)
            ImGui.SameLine()

            state.scribedOnly = ImGui.Checkbox("Scribed Only", state.scribedOnly)
            ImGui.SameLine()

            ImGui.SetNextItemWidth(180)
            state.searchFilter = ImGui.InputText("Search##Filter", state.searchFilter or '')

            -- Spell Table (Fixed with bit.bor flags)
            local tableFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
            if ImGui.BeginTable("SpellTable", 4, tableFlags, 0, -35) then
                ImGui.TableSetupColumn("Level", ImGuiTableColumnFlags.WidthFixed, 50)
                ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 60)
                ImGui.TableSetupColumn("Spell Name", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 90)
                ImGui.TableHeadersRow()

                local activeClass = state.myClasses[state.activeClassTab] or 'WAR'
                local classSpells = getActiveClassSpells(activeClass)

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

            ImGui.EndTabItem()
        end

        -- Tab 2: Loadouts / Presets
        if ImGui.BeginTabItem("Loadouts / Presets##Tab") then
            ImGui.Text("Save or load full gem set loadouts for quick switching:")
            ImGui.Spacing()

            for _, presetName in ipairs(state.presetNames) do
                local savedGems = state.presets[presetName] or {}
                if ImGui.CollapsingHeader(presetName .. "##Header") then
                    if ImGui.Button("Load Preset: " .. presetName) then
                        local loadedCount = 0
                        local gemCount = mq.TLO.Me.NumGems() or 8
                        for g = 1, gemCount do
                            local s = savedGems[g]
                            if s and s ~= "" and s ~= "Empty" then
                                state.pendingQueue[g] = s
                                loadedCount = loadedCount + 1
                            end
                        end
                        state.statusMsg = string.format("Queued %d spells from preset: %s", loadedCount, presetName)
                    end
                    ImGui.SameLine()
                    if ImGui.Button("Save Current Gems to " .. presetName) then
                        local gemCount = mq.TLO.Me.NumGems() or 8
                        state.presets[presetName] = {}
                        local savedCount = 0
                        for g = 1, gemCount do
                            local gemSpell = mq.TLO.Me.Gem(g).Name()
                            if gemSpell and gemSpell ~= "Empty" then
                                state.presets[presetName][g] = gemSpell
                                savedCount = savedCount + 1
                            end
                        end
                        state.statusMsg = string.format("Saved %d gems to preset: %s", savedCount, presetName)
                    end

                    -- Preview saved preset gems
                    if next(savedGems) then
                        ImGui.TextDisabled("Saved Loadout:")
                        local gemCount = mq.TLO.Me.NumGems() or 8
                        for g = 1, gemCount do
                            if savedGems[g] then
                                ImGui.BulletText(string.format("Gem %d: %s", g, savedGems[g]))
                            end
                        end
                    else
                        ImGui.TextDisabled("No spells saved in this preset yet.")
                    end
                end
            end

            ImGui.EndTabItem()
        end

        ImGui.EndTabBar()
    end

    -- Status Bar
    ImGui.Separator()

    if next(state.pendingQueue) then
        ImGui.TextColored(1.0, 0.7, 0.0, 1.0, "MEMORIZING QUEUE ACTIVE...")
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Status:")
    end

    ImGui.SameLine()
    ImGui.Text(state.statusMsg)

    ImGui.End()
    common.popTheme()
end

-- ============================================================================
-- Main Script Execution Loop
-- ============================================================================

loadData()
state.myClasses = common.detectClasses()

mq.imgui.init('TriuneSpellbookUI', DrawTriuneUI)

-- Startup summary
local clsStr = table.concat(state.myClasses, ' / ')
local spellCounts = {}
for _, cls in ipairs(state.myClasses) do
    local spells = getClassSpells(cls)
    spellCounts[#spellCounts + 1] = string.format('%s=%d', cls, #spells)
end
print(string.format('\ag[Triune Spellbook]\ax Loaded -- Classes: [%s]  DB spells: %s',
    clsStr, table.concat(spellCounts, ', ')))

while isRunning do
    processQueue()
    mq.delay(50)
end
