---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TRIUNE SPELLBOOK ENGINE (Standalone ImGui Script)
-- ----------------------------------------------------------------------------
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library
-- Theme & style helpers for spellbook window
local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    local ImGuiColType = mq.imgui.Col or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiColType and ImGuiColType(id) or id
    if pcall(mq.imgui.PushStyleColor, enumVal, r, g, b, a) then _colN = _colN + 1 end ---@diagnostic disable-line: undefined-field
end
local function pushVar(id, a, b)
    if id == nil then return end
    local ok
    local ImGuiSVType = mq.imgui.StyleVar or _G.ImGuiStyleVar ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiSVType and ImGuiSVType(id) or id
    if b ~= nil then
        local ImVec2Type = _G.ImVec2
        if type(ImVec2Type) == 'function' then
            ok = pcall(mq.imgui.PushStyleVar, enumVal, ImVec2Type(a, b)) ---@diagnostic disable-line: undefined-field
        else
            ok = pcall(mq.imgui.PushStyleVar, enumVal, a, b) ---@diagnostic disable-line: undefined-field
        end
    else
        ok = pcall(mq.imgui.PushStyleVar, enumVal, a) ---@diagnostic disable-line: undefined-field
    end
    if ok then _varN = _varN + 1 end
end

local function pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = mq.imgui.Col or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
    local ImGuiStyleVar = mq.imgui.StyleVar or _G.ImGuiStyleVar ---@diagnostic disable-line: undefined-field
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
        pcall(mq.imgui.PopStyleVar, _varN); _varN = 0 ---@diagnostic disable-line: undefined-field
    end
    if _colN > 0 then
        pcall(mq.imgui.PopStyleColor, _colN); _colN = 0 ---@diagnostic disable-line: undefined-field
    end
end


-- Script Control State
local openGUI = true
local isRunning = true

local KIND_LABELS = { dd = 'DD', dot = 'DoT', debuff = 'Debuff', buff = 'Buff', heal = 'Heal', pet = 'Pet', util = 'Util' }

-- Global State & Data Store
local state = {
    myClasses = { 'WAR', 'CLR', 'PAL' }, -- Default fallback trio (uppercase to match MQSHORT keys)
    activeClassTab = 1,                  -- Selected class tab index
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
    bypassScribedCheck = false,

    -- Loadout Presets Store
    presetNames = { "Solo / DPS", "Group Healing", "Buff Suite" },
    presets = {
        ["Solo / DPS"] = {},
        ["Group Healing"] = {},
        ["Buff Suite"] = {}
    }
}

-- ============================================================================
-- Spellbook Functions (defined locally in this file)
-- ============================================================================

local spellbookMapCache = nil
local lastCacheTime = 0

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

local function getSpellbookMap()
    local now = os.time()
    if spellbookMapCache and (now - lastCacheTime) < 3 then
        return spellbookMapCache
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
    spellbookMapCache = map
    lastCacheTime = now
    return map
end

local function checkBook(name)
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

local function getSpellBookSlot(spellName)
    if not spellName or spellName == '' then return nil end

    local sbMap = getSpellbookMap()
    local targetLower = spellName:lower()
    local cleaned = cleanSpellName(spellName)
    local targetCleanLower = cleaned:lower()
    local targetNorm = normalizeSpellName(spellName)

    if sbMap.exact[targetLower] then return sbMap.exact[targetLower] end
    if sbMap.exact[targetCleanLower] then return sbMap.exact[targetCleanLower] end
    if targetNorm ~= "" and sbMap.norm[targetNorm] then return sbMap.norm[targetNorm] end

    local slot = checkBook(spellName)
    if slot then return slot end

    if cleaned ~= spellName then
        slot = checkBook(cleaned)
        if slot then return slot end
    end

    pcall(function()
        local rName = mq.TLO.Spell(spellName).RankName()
        if rName and rName ~= '' and rName ~= spellName then
            slot = checkBook(rName)
        end
    end)
    if slot then return slot end

    pcall(function()
        local rName = mq.TLO.Spell(cleaned).RankName()
        if rName and rName ~= '' and rName ~= cleaned and rName ~= spellName then
            slot = checkBook(rName)
        end
    end)
    if slot then return slot end

    return nil
end

local function isScribed(spellName)
    if not spellName or spellName == '' then return false end
    return getSpellBookSlot(spellName) ~= nil
end

-- ============================================================================
-- Cursor management (needed by tryMem before its definition)
-- ============================================================================
local function clearCursor()
    local item = mq.TLO.Cursor
    if not item() or (item.ID() or 0) <= 0 then return false end

    local count = 0
    local firstName = tostring(item.Name() or 'Item')

    while mq.TLO.Cursor() and (mq.TLO.Cursor.ID() or 0) > 0 and count < 255 do
        mq.cmd('/autoinventory')
        count = count + 1
        mq.delay(50)
    end

    if count > 0 then
        print(string.format('\ay[Spellbook]\ax Cleared %d item(s) from cursor (first: [%s]).', count, firstName))
        return true
    end
    return false
end

local function tryMem(slot, spellName, bypassCheck)
    if not spellName or spellName == '' then return false end
    local cleanName = cleanSpellName(spellName)

    clearCursor()

    if mq.TLO.Me.Combat() then
        print('\ay[Spellbook]\ax cannot memorize in combat: ' .. cleanName)
        return false
    end

    local currentInGem = mq.TLO.Me.Gem(slot).Name()
    if currentInGem == cleanName or currentInGem == spellName then
        return true
    end

    if currentInGem and currentInGem ~= '' then
        mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', slot - 1)
        mq.delay(200)
        local clearWait = 0
        while mq.TLO.Me.Gem(slot).Name() and clearWait < 1000 do
            mq.delay(100)
            clearWait = clearWait + 100
        end
    end

    local bookSlot = getSpellBookSlot(spellName)
    if not bookSlot and not bypassCheck then
        print('\ay[Spellbook]\ax "' .. cleanName .. '" is not scribed in your spellbook -- scribe it first.')
        return false
    end
    bookSlot = bookSlot or 1

    if mq.TLO.Me.Sitting() then
        mq.cmd('/stand')
        mq.delay(400)
    end

    if mq.TLO.Me.Moving() then
        print('\ay[Spellbook]\ax stand still to memorize ' .. cleanName)
        return false
    end

    local SBW = function() return mq.TLO.Window('SpellBookWnd') end

    if not SBW().Open() then mq.cmd('/book') end
    local t = 0
    while not SBW().Open() and t < 2500 do
        mq.delay(100)
        t = t + 100
    end
    if not SBW().Open() then
        print('\ar[Spellbook]\ax could not open the spellbook.')
        return false
    end

    local per = 0
    for i = 0, 24 do
        local nm
        pcall(function() nm = SBW().Child('SBW_Spell' .. i).Name() end)
        if nm then per = per + 1 else break end
    end
    if per == 0 then per = 8 end

    local curPage, inferred = 1, false
    for i = 0, per - 1 do
        local txt
        pcall(function() txt = SBW().Child('SBW_Spell' .. i).Text() end)
        if txt and txt ~= '' then
            txt = txt:match('^%s*(.-)%s*$')
            local bs = getSpellBookSlot(txt)
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
        end
        curPage = 1
    end

    local targetPage = math.ceil(bookSlot / per)
    if curPage ~= targetPage then
        local diff = targetPage - curPage
        local btn = (diff > 0) and 'SBW_PageUp_Button' or 'SBW_PageDown_Button'
        for _ = 1, math.abs(diff) do
            mq.cmdf('/notify SpellBookWnd %s leftmouseup', btn)
            mq.delay(math.random(150, 300))
        end
    end

    mq.cmdf('/notify SpellBookWnd SBW_Spell%d leftmouseup', (bookSlot - 1) % per)
    mq.delay(math.random(300, 500))
    mq.cmdf('/notify CastSpellWnd CSPW_Spell%d leftmouseup', slot - 1)

    local w = 0
    while not mq.TLO.Window('CastingWindow').Open() and w < 3000 do
        mq.delay(100)
        w = w + 100
    end
    while mq.TLO.Window('CastingWindow').Open() do
        mq.delay(100)
    end
    mq.delay(400)

    if SBW().Open() then
        mq.cmd('/notify SpellBookWnd SBW_DoneButton leftmouseup')
    end

    local finalGem = mq.TLO.Me.Gem(slot).Name()
    clearCursor()
    if finalGem == cleanName or finalGem == spellName then
        print('\ag[Spellbook]\ax memorized ' .. cleanName .. ' -> gem ' .. slot)
        return true
    elseif mq.TLO.Me.Gem(cleanName)() or mq.TLO.Me.Gem(spellName)() then
        print('\ag[Spellbook]\ax ' .. cleanName .. ' is on the bar.')
        return true
    else
        print('\ar[Spellbook]\ax mem may have failed for "' .. cleanName .. '" (gem ' .. slot .. ').')
        return false
    end
end


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
        dbLookup[normalizeSpellName(dName)] = {
            level = tonumber(dLvl) or 1,
            bene = (dBene == 1 or dBene == true),
            kind = dKind or 'other'
        }
        dbLookup[dName:lower()] = dbLookup[normalizeSpellName(dName)]
        dbLookup[cleanSpellName(dName):lower()] = dbLookup[normalizeSpellName(dName)]
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
                dbEntry = dbLookup[normalizeSpellName(name)]
                    or dbLookup[name:lower()]
                    or dbLookup[cleanSpellName(name):lower()]
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

                local normName = normalizeSpellName(name)
                scribedNormMap[normName] = true
                scribedNormMap[name:lower()] = true
                scribedNormMap[cleanSpellName(name):lower()] = true

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
        local dNorm = normalizeSpellName(dName)
        local dLower = dName:lower()
        local dCleanLower = cleanSpellName(dName):lower()

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

local function processQueue()
    for slot, spellName in pairs(state.pendingQueue) do
        if spellName then
            local cleanName = cleanSpellName(spellName)
            local currentGem = mq.TLO.Me.Gem(slot).Name() or ""
            if currentGem == cleanName or currentGem == spellName then
                state.pendingQueue[slot] = nil
                state.statusMsg = "Finished memming " .. cleanName
            else
                local ok = tryMem(slot, spellName, state.bypassScribedCheck)
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
                            if existing == norm then dup = true; break end
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
                        if existing == norm then dup = true; break end
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

local function detectClasses()
    -- 1. Try saved classes from mq.configDir/triune_loadout.lua
    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    if myName and myName ~= '' and myName ~= 'NULL' then
        local cfg = mq.configDir or '.'
        local fn = loadfile(cfg .. '/triune_loadout.lua')
        if fn then
            local ok, t = pcall(fn)
            if ok and type(t) == 'table' and type(t[myName]) == 'table' then
                local saved = t[myName].classes
                if type(saved) == 'table' and #saved > 0 then
                    return saved
                end
            end
        end
    end

    -- 2. Live InventoryWindow scan
    local wasOpen = false
    pcall(function() wasOpen = mq.TLO.Window('InventoryWindow').Open() end)
    if not wasOpen then
        mq.cmd('/windowstate InventoryWindow open')
        mq.delay(250)
    end

    local foundInv = {}

    -- Check IW_ClassAbbr ("SHD\nMAG\nBST")
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
                        for _, existing in ipairs(foundInv) do
                            if existing == norm then dup = true; break end
                        end
                        if not dup then foundInv[#foundInv + 1] = norm end
                    end
                end
            end
        end
    end)

    -- Check IW_Class ("DreadLord\nArchConvoker\nFeralLord")
    if #foundInv == 0 then
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
                            for _, existing in ipairs(foundInv) do
                                if existing == norm then dup = true; break end
                            end
                            if not dup then foundInv[#foundInv + 1] = norm end
                        end
                    end
                end
            end
        end)
    end

    -- Tree walk fallback
    if #foundInv == 0 then
        pcall(function()
            local invWin = mq.TLO.Window('InventoryWindow')
            if invWin and invWin() then
                walkChildTree(invWin, foundInv, 0)
            end
        end)
    end

    if not wasOpen then
        mq.cmd('/windowstate InventoryWindow close')
    end

    if #foundInv > 0 then return foundInv end

    -- 3. Fallback to single primary class
    local ok, mainClass = pcall(function() return mq.TLO.Me.Class.ShortName() end)
    if ok and mainClass and mainClass ~= '' and mainClass ~= 'NULL' then
        return { mainClass }
    end
    return { 'Wiz' }
end

local function DrawTriuneUI()
    if not openGUI then
        isRunning = false
        return
    end

    pushTheme()

    ImGui.SetNextWindowSize(820, 560, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding, ImGuiWindowFlags.MenuBar) ---@diagnostic disable-line: deprecated
    end
    local open, draw = ImGui.Begin('Triune Spellbook Engine##Main', openGUI, windowFlags)
    if not open then
        openGUI = false
        isRunning = false
        ImGui.End()
        popTheme()
        return
    end

    if ImGui.BeginMenuBar() then
        if ImGui.BeginMenu("Gestalt Options") then
            if ImGui.MenuItem("Re-detect Classes") then
                state.myClasses = detectClasses()
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
                        local slotFound = getSpellBookSlot(sName)
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

    if ImGui.BeginTabBar("MainWorkspaceTabs") then
        if ImGui.BeginTabItem("Spellbook Browser##Tab") then
            local cats = { 'ALL', 'dd', 'dot', 'debuff', 'buff', 'heal', 'pet', 'util' }
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

    ImGui.Separator()

    if next(state.pendingQueue) then
        ImGui.TextColored(1.0, 0.7, 0.0, 1.0, "MEMORIZING QUEUE ACTIVE...")
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Status:")
    end

    ImGui.SameLine()
    ImGui.Text(state.statusMsg)

    ImGui.End()
    popTheme()
end

loadData()
state.myClasses = detectClasses()

mq.imgui.init('TriuneSpellbookUI', DrawTriuneUI)

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
