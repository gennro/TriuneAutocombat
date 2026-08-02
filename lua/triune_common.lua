-- ============================================================================
-- Triune AutoCombat -- Common Utilities & Helpers Module
-- ----------------------------------------------------------------------------
-- Shared reusable functions for math, UI formatting, EQ spawn queries,
-- navigation, target resolution, and spell failure/lockout tracking.
-- ============================================================================

local mq = require('mq')

local common = {}

-- ----------------------------------------------------------------------------
-- 1. General & UI Utilities
-- ----------------------------------------------------------------------------

function common.idxOf(tbl, val)
    for i, v in ipairs(tbl or {}) do
        if v == val then return i end
    end
    return 1
end

-- ----------------------------------------------------------------------------
-- Theme & Color Palette
-- ----------------------------------------------------------------------------

common.GOOD  = { 0.370, 0.880, 0.640, 1.0 }
common.WARN  = { 1.000, 0.700, 0.540, 1.0 }
common.ERR   = { 1.000, 0.400, 0.400, 1.0 }
common.ARC   = { 0.300, 0.700, 1.000, 1.0 }
common.GOLD  = { 0.950, 0.750, 0.300, 1.0 }
common.MUTED = { 0.490, 0.561, 0.651, 1.0 }

local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    if pcall(mq.imgui.PushStyleColor, id, r, g, b, a) then _colN = _colN + 1 end
end
local function pushVar(id, a, b)
    if id == nil then return end
    local ok = (b ~= nil) and pcall(mq.imgui.PushStyleVar, id, a, b) or pcall(mq.imgui.PushStyleVar, id, a)
    if ok then _varN = _varN + 1 end
end

function common.pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = mq.imgui.Col or _G.ImGuiCol       ---@diagnostic disable-line: undefined-field
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
        pushCol(ImGuiCol.TabActive, 0.075, 0.125, 0.200, 1)
        pushCol(ImGuiCol.TabSelected, 0.075, 0.125, 0.200, 1)
        pushCol(ImGuiCol.CheckMark, 0.370, 0.880, 0.640, 1)
        pushCol(ImGuiCol.SliderGrab, 1.000, 0.700, 0.540, 1)
        pushCol(ImGuiCol.SliderGrabActive, 1.000, 0.550, 0.300, 1)
        pushCol(ImGuiCol.Separator, 0.157, 0.251, 0.345, 1)
        pushCol(ImGuiCol.ScrollbarBg, 0.031, 0.051, 0.078, 1)
        pushCol(ImGuiCol.ScrollbarGrab, 0.157, 0.251, 0.345, 1)
    end
    if ImGuiStyleVar then
        pushVar(ImGuiStyleVar.WindowRounding, 6)
        pushVar(ImGuiStyleVar.ChildRounding, 5)
        pushVar(ImGuiStyleVar.FrameRounding, 4)
        pushVar(ImGuiStyleVar.PopupRounding, 4)
        pushVar(ImGuiStyleVar.TabRounding, 4)
        pushVar(ImGuiStyleVar.GrabRounding, 3)
        pushVar(ImGuiStyleVar.ScrollbarRounding, 6)
        pushVar(ImGuiStyleVar.FrameBorderSize, 1)
        pushVar(ImGuiStyleVar.FramePadding, 7, 4)
        pushVar(ImGuiStyleVar.ItemSpacing, 8, 6)
        pushVar(ImGuiStyleVar.WindowPadding, 12, 10)
    end
end

function common.popTheme()
    if _varN > 0 then
        pcall(mq.imgui.PopStyleVar, _varN); _varN = 0
    end
    if _colN > 0 then
        pcall(mq.imgui.PopStyleColor, _colN); _colN = 0
    end
end

local SLOT_COLORS = {
    { 0.157, 0.573, 0.847, 1 }, -- slot 1: arcane blue
    { 0.941, 0.384, 0.122, 1 }, -- slot 2: ember
    { 0.122, 0.659, 0.471, 1 }, -- slot 3: jade
}
common.SLOT_COLORS = SLOT_COLORS

function common.classColor(abbr, myClasses)
    for i, c in ipairs(myClasses or {}) do
        if c == abbr then
            local s = SLOT_COLORS[i]
            return s[1], s[2], s[3], s[4]
        end
    end
    return 0.49, 0.56, 0.65, 1 -- muted: not one of your trio classes
end

function common.defaultsForKind(kind, bene)
    if kind == 'dot' then
        return 'E: Current Target', 'missing buff', 95
    elseif kind == 'buff' then
        return 'F: Myself', 'missing buff', 70
    elseif kind == 'heal' then
        return 'F: Myself', 'HP <=', 70
    elseif kind == 'pet' then
        return 'F: Myself', 'missing pet', 100
    elseif kind == 'dd' then
        return 'E: Current Target', 'target HP <=', 95
    elseif bene then
        return 'F: Myself', 'HP <=', 70
    end
    return 'E: Current Target', 'target HP <=', 95
end

-- ----------------------------------------------------------------------------
-- Class Abbreviation Mappings
-- ----------------------------------------------------------------------------

common.MQSHORT = {
    WAR = 'War',
    CLR = 'Clr',
    PAL = 'Pal',
    RNG = 'Rng',
    SHD = 'SK',
    SK  = 'SK',
    DRU = 'Dru',
    MNK = 'Mnk',
    BRD = 'Brd',
    ROG = 'Rog',
    SHM = 'Shm',
    NEC = 'Nec',
    WIZ = 'Wiz',
    MAG = 'Mag',
    ENC = 'Enc',
    BST = 'Bst',
    BER = 'Ber'
}

-- ----------------------------------------------------------------------------
-- Spellbook & Scribed Inspection Utilities
-- ----------------------------------------------------------------------------

function common.cleanSpellName(name)
    if not name or type(name) ~= 'string' then return "" end
    local cleaned = name:gsub('%s*%([%w%s/]+%)$', '')
    return (cleaned:gsub('^%s*(.-)%s*$', '%1'))
end

function common.normalizeSpellName(name)
    if not name or type(name) ~= 'string' then return "" end
    local s = name:lower()
    s = s:gsub('%s*%(?%s*rk%.?%s*[%ivxlc%d]+%s*%)?', '')
    s = s:gsub('%s*%([^%)]+%)', '')
    s = s:gsub('[%p%s]', '')
    return s
end

local spellbookMapCache = nil
local lastCacheTime = 0

function common.getSpellbookMap()
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
            local cleanName = common.cleanSpellName(bName):lower()
            local normName = common.normalizeSpellName(bName)

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

function common.checkBook(name)
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

function common.getSpellBookSlot(spellName)
    if not spellName or spellName == '' then return nil end

    -- 1. Fast cached spellbook map lookup (O(1) Lua table read)
    local sbMap = common.getSpellbookMap()
    local targetLower = spellName:lower()
    local cleaned = common.cleanSpellName(spellName)
    local targetCleanLower = cleaned:lower()
    local targetNorm = common.normalizeSpellName(spellName)

    if sbMap.exact[targetLower] then return sbMap.exact[targetLower] end
    if sbMap.exact[targetCleanLower] then return sbMap.exact[targetCleanLower] end
    if targetNorm ~= "" and sbMap.norm[targetNorm] then return sbMap.norm[targetNorm] end

    -- 2. Fallback to direct live TLO checks if not found in map
    local slot = common.checkBook(spellName)
    if slot then return slot end

    if cleaned ~= spellName then
        slot = common.checkBook(cleaned)
        if slot then return slot end
    end

    pcall(function()
        local rName = mq.TLO.Spell(spellName).RankName()
        if rName and rName ~= '' and rName ~= spellName then
            slot = common.checkBook(rName)
        end
    end)
    if slot then return slot end

    pcall(function()
        local rName = mq.TLO.Spell(cleaned).RankName()
        if rName and rName ~= '' and rName ~= cleaned and rName ~= spellName then
            slot = common.checkBook(rName)
        end
    end)
    if slot then return slot end

    return nil
end

function common.isScribed(spellName)
    if not spellName or spellName == '' then return false end
    return common.getSpellBookSlot(spellName) ~= nil
end

-- ----------------------------------------------------------------------------
-- Character Item & Ability Ownership Inspection
-- ----------------------------------------------------------------------------

local knownDiscSet = nil

function common.scanKnownDiscs()
    knownDiscSet = {}
    local i = 1
    while i <= 500 do
        local disc = mq.TLO.Me.CombatAbility(i)
        if not disc() then break end
        local nm = disc.Name()
        if nm then knownDiscSet[nm] = true end
        i = i + 1
    end
end

function common.hasSpell(nm)
    local h = false
    pcall(function() h = mq.TLO.Me.Book(nm)() ~= nil end)
    return h
end

function common.hasDisc(nm)
    if not knownDiscSet then common.scanKnownDiscs() end
    if (knownDiscSet or {})[nm] then return true end
    local h = false
    pcall(function() h = mq.TLO.Me.CombatAbility(nm)() ~= nil end)
    return h
end

local aaCache = {}
local lastAACacheTime = 0

function common.hasAA(nm)
    if not nm or nm == '' then return false end
    local now = os.time()
    if (now - lastAACacheTime) > 5 then
        aaCache = {}
        lastAACacheTime = now
    end
    if aaCache[nm] ~= nil then
        return aaCache[nm]
    end
    local h = false
    pcall(function()
        local a = mq.TLO.Me.AltAbility(nm)
        h = a() ~= nil and (a.Rank() or 0) > 0
    end)
    aaCache[nm] = h
    return h
end

function common.knownItem(nm, kind)
    if kind == 'spell' then return common.hasSpell(nm) end
    if kind == 'disc' then return common.hasDisc(nm) end
    return common.hasAA(nm)
end

function common.classPlausible(abbr, dataTable)
    if not abbr or not dataTable then return false end
    for _, pk in ipairs({ { dataTable.spells and dataTable.spells[abbr], 'spell' }, { dataTable.discs and dataTable.discs[abbr], 'disc' }, { dataTable.aas and dataTable.aas[abbr], 'aa' } }) do
        if pk[1] then
            for _, item in ipairs(pk[1]) do
                if common.knownItem(item[1], pk[2]) then return true end
            end
        end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Class Trio Detection Engine
-- ----------------------------------------------------------------------------

function common.classesFromInventoryWindow(loud, force)
    local iw = mq.TLO.Window('InventoryWindow')
    local openedIt = false
    if force and not iw.Open() then
        pcall(function() mq.cmd('/windowstate InventoryWindow open') end)
        local t = 0
        while not iw.Open() and t < 2000 do
            mq.delay(100); t = t + 100
        end
        openedIt = true
    end
    local ok, txt
    if iw.Open() then
        local attempts = force and 12 or 1
        for attempt = 1, attempts do
            ok, txt = pcall(function() return iw.Child('IW_ClassAbbr').Text() end)
            if ok and txt and txt ~= '' then break end
            if attempt < attempts and force then mq.delay(400) end
        end
    else
        ok, txt = false, 'InventoryWindow not open'
    end
    if loud then
        print('\ay[Triune debug]\ax IW_ClassAbbr raw = ' ..
            (ok and ('"' .. tostring(txt) .. '"') or ('failed: ' .. tostring(txt))))
    end
    if openedIt then pcall(function() mq.cmd('/windowstate InventoryWindow close') end) end
    if not ok or not txt or txt == '' then return nil end
    local out = {}
    for tok in txt:gmatch('%a+') do
        local abbr = common.MQSHORT[tok:upper()]
        if abbr then out[#out + 1] = abbr end
    end
    if loud then print('\ay[Triune debug]\ax IW_ClassAbbr parsed = ' .. table.concat(out, ',')) end
    if #out > 0 then return out end
    return nil
end

function common.classesFromTitle(loud)
    local ok, title = pcall(function() return mq.TLO.EverQuest.WinTitle() end)
    if loud then
        print('\ay[Triune debug]\ax WinTitle raw = ' ..
            (ok and ('"' .. tostring(title) .. '"') or ('pcall failed: ' .. tostring(title))))
    end
    if not ok or not title or title == '' then return nil end
    local bracket = title:match('%[(.-)%]')
    if loud then print('\ay[Triune debug]\ax bracket match = ' .. tostring(bracket)) end
    if not bracket then return nil end
    local out = {}
    for tok in bracket:gmatch('[^/]+') do
        local abbr = common.MQSHORT[(tok:match('^%s*(.-)%s*$') or ''):upper()]
        if abbr then out[#out + 1] = abbr end
    end
    if loud then print('\ay[Triune debug]\ax parsed classes = ' .. table.concat(out, ',')) end
    if #out > 0 then return out end
    return nil
end

function common.detectClasses(loud)
    local fromInv = common.classesFromInventoryWindow(loud, true)
    if fromInv then
        if loud then print('\ag[Triune debug]\ax using Inventory window trio.') end
        return fromInv
    end
    local fromTitle = common.classesFromTitle(loud)
    if fromTitle then
        if loud then print('\ag[Triune debug]\ax using window-title trio.') end
        return fromTitle
    end
    if loud then print('\ay[Triune debug]\ax falling back to primary class.') end
    local ok, prim = pcall(function() return mq.TLO.Me.Class.ShortName() end)
    local primAbbr = (ok and prim) and common.MQSHORT[tostring(prim):upper()] or 'War'
    return { primAbbr }
end

function common.clearCursor()
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
        print(string.format('\ay[Triune]\ax Cleared %d item(s) from cursor (first: [%s]).', count, firstName))
        return true
    end
    return false
end

function common.destroyCursor()
    local item = mq.TLO.Cursor
    if item() and (item.ID() or 0) > 0 then
        local itemName = tostring(item.Name() or 'Item')
        print(string.format('\ar[Triune]\ax Destroyed [%s] from cursor.', itemName))
        mq.cmd('/destroy')
        mq.delay(100)
        return true
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Auto-Memorization Engine
-- ----------------------------------------------------------------------------

function common.SBW() return mq.TLO.Window('SpellBookWnd') end

function common.tryMem(slot, spellName, bypassCheck)
    if not spellName or spellName == '' then return false end
    local cleanName = common.cleanSpellName(spellName)

    common.clearCursor()

    if mq.TLO.Me.Combat() then
        print('\ay[Triune]\ax cannot memorize in combat: ' .. cleanName)
        return false
    end

    local currentInGem = mq.TLO.Me.Gem(slot).Name()
    if currentInGem == cleanName or currentInGem == spellName then
        return true
    end

    -- Clear target gem slot if currently occupied by another spell
    if currentInGem and currentInGem ~= '' then
        mq.cmdf('/notify CastSpellWnd CSPW_Spell%d rightmouseup', slot - 1)
        mq.delay(200)
        local clearWait = 0
        while mq.TLO.Me.Gem(slot).Name() and clearWait < 1000 do
            mq.delay(100)
            clearWait = clearWait + 100
        end
    end

    local bookSlot = common.getSpellBookSlot(spellName)
    if not bookSlot and not bypassCheck then
        print('\ay[Triune]\ax "' .. cleanName .. '" is not scribed in your spellbook -- scribe it first.')
        return false
    end
    bookSlot = bookSlot or 1

    if mq.TLO.Me.Sitting() then
        mq.cmd('/stand')
        mq.delay(400)
    end

    if mq.TLO.Me.Moving() then
        print('\ay[Triune]\ax stand still to memorize ' .. cleanName)
        return false
    end

    if not common.SBW().Open() then mq.cmd('/book') end
    local t = 0
    while not common.SBW().Open() and t < 2500 do
        mq.delay(100)
        t = t + 100
    end
    if not common.SBW().Open() then
        print('\ar[Triune]\ax could not open the spellbook.')
        return false
    end

    local per = 0
    for i = 0, 24 do
        local nm
        pcall(function() nm = common.SBW().Child('SBW_Spell' .. i).Name() end)
        if nm then per = per + 1 else break end
    end
    if per == 0 then per = 8 end

    local curPage, inferred = 1, false
    for i = 0, per - 1 do
        local txt
        pcall(function() txt = common.SBW().Child('SBW_Spell' .. i).Text() end)
        if txt and txt ~= '' then
            txt = txt:match('^%s*(.-)%s*$')
            local bs = common.getSpellBookSlot(txt)
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

    if common.SBW().Open() then
        mq.cmd('/notify SpellBookWnd SBW_DoneButton leftmouseup')
    end

    local finalGem = mq.TLO.Me.Gem(slot).Name()
    if finalGem == cleanName or finalGem == spellName then
        print('\ag[Triune]\ax memorized ' .. cleanName .. ' -> gem ' .. slot)
        return true
    elseif mq.TLO.Me.Gem(cleanName)() or mq.TLO.Me.Gem(spellName)() then
        print('\ag[Triune]\ax ' .. cleanName .. ' is on the bar.')
        return true
    else
        print('\ar[Triune]\ax mem may have failed for "' .. cleanName .. '" (gem ' .. slot .. ').')
        return false
    end
end

-- ----------------------------------------------------------------------------
-- 2. EQ & World Queries
-- ----------------------------------------------------------------------------

function common.isCasting()
    local cid = mq.TLO.Me.Casting.ID()
    return cid ~= nil and cid > 0
end

function common.isSpawnAlive(id)
    if not id or id == 0 then return false end
    local s = mq.TLO.Spawn(id)
    if not s() or s.Dead() or s.Type() == 'Corpse' then return false end
    if s.Type() == 'NPC' and (s.PctHPs() or 0) <= 0 then return false end
    return true
end

function common.distToId(id)
    local s = mq.TLO.Spawn(id)
    return (s() and s.Distance3D()) or 9999
end

function common.distToLoc(x, y, z)
    local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    if not (mx and my and mz) then return 9999 end
    return math.sqrt((mx - x) ^ 2 + (my - y) ^ 2 + (mz - z) ^ 2)
end

function common.hasLoS(id)
    local s = mq.TLO.Spawn(id)
    return (s() and s.LineOfSight()) or false
end

function common.pctHP(id)
    if not id or id == 0 then return 100 end
    local s = mq.TLO.Spawn(id)
    return (s() and s.PctHPs()) or 100
end

function common.buffActive(targetId, spellName)
    local s = mq.TLO.Spawn(targetId)
    if not s() then return false end
    if targetId == mq.TLO.Me.ID() then
        local b = mq.TLO.Me.Buff(spellName)
        if b() then return true end
        local song = mq.TLO.Me.Song(spellName)
        return song() ~= nil
    end
    local b = s.Buff(spellName)
    return b() ~= nil
end

function common.sungKey(spellName, targetId)
    return string.format('%s@%d', tostring(spellName), tonumber(targetId) or 0)
end

-- ----------------------------------------------------------------------------
-- 3. Navigation & Movement Primitives
-- ----------------------------------------------------------------------------

function common.navLoaded()
    return mq.TLO.Plugin('MQ2Nav').IsLoaded()
end

function common.stickLoaded()
    return mq.TLO.Plugin('MQ2MoveUtils').IsLoaded()
end

function common.isMoveActive()
    if common.navLoaded() and mq.TLO.Navigation.Active() then return true end
    if common.stickLoaded() then
        local st = 'OFF'
        pcall(function() st = mq.TLO.Stick.Status() or 'OFF' end)
        if st == 'ON' then return true end
    end
    return false
end

function common.stopMoving()
    if common.navLoaded() and mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    if common.stickLoaded() then
        local status = 'OFF'
        pcall(function() status = mq.TLO.Stick.Status() or 'OFF' end)
        if status == 'ON' then mq.cmd('/stick off') end
    end
end

-- ----------------------------------------------------------------------------
-- 4. Target Resolution & XTarget Helpers
-- ----------------------------------------------------------------------------

function common.maPcId(maName)
    local nm = (maName or ''):match('^%s*(.-)%s*$')
    if nm ~= '' then
        local s = mq.TLO.Spawn('pc =' .. nm)
        if s() then return s.ID() end
    end
    local l = mq.TLO.Group.Leader
    if l and l() then return l.ID() end
    return nil
end

function common.firstNPCXtarget(unmezzedOnly, isIgnoredFn, isUnreachableFn)
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' and (xt.PctHPs() or 0) > 0 and not xt.Dead() then
            local cleanName = xt.CleanName() or ''
            local id = xt.ID()
            local ign = isIgnoredFn and isIgnoredFn(cleanName) or false
            local unreach = isUnreachableFn and isUnreachableFn(id) or false
            if not ign and not unreach then
                if not unmezzedOnly or not xt.Mezzed() then return id end
            end
        end
    end
    return nil
end

function common.lowestHpNPCXtarget(unmezzedOnly, isIgnoredFn, isUnreachableFn)
    local bestId = nil
    local lowestHp = 999

    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' and (xt.PctHPs() or 0) > 0 and not xt.Dead() then
            local cleanName = xt.CleanName() or ''
            local id = xt.ID()
            local ign = isIgnoredFn and isIgnoredFn(cleanName) or false
            local unreach = isUnreachableFn and isUnreachableFn(id) or false
            if not ign and not unreach and not xt.Mezzed() then
                local hp = xt.PctHPs() or 100
                if hp < lowestHp then
                    lowestHp = hp
                    bestId = id
                end
            end
        end
    end

    if bestId then return bestId end
    if unmezzedOnly then return nil end

    lowestHp = 999
    for i = 1, 13 do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and (xt.ID() or 0) > 0 and xt.Type() == 'NPC' then
            local cleanName = xt.CleanName() or ''
            local id = xt.ID()
            local ign = isIgnoredFn and isIgnoredFn(cleanName) or false
            local unreach = isUnreachableFn and isUnreachableFn(id) or false
            if not ign and not unreach then
                local hp = xt.PctHPs() or 100
                if hp < lowestHp then
                    lowestHp = hp
                    bestId = id
                end
            end
        end
    end

    return bestId
end

-- ----------------------------------------------------------------------------
-- 5. Cast Failure & Lockout Tracker Factory
-- ----------------------------------------------------------------------------

function common.createCastTracker()
    local tracker = {
        counts = {},
        lockouts = {},
        lastSpell = nil,
        lastTime = 0,
        activeSpell = nil,
        wasCasting = false,
        failed = false
    }

    function tracker.isLockedOut(spellName)
        if not spellName or spellName == '' then return false end
        local expires = tracker.lockouts[spellName]
        if expires then
            if os.clock() < expires then
                return true
            else
                tracker.lockouts[spellName] = nil
            end
        end
        return false
    end

    function tracker.recordFailure(spellName, reason, maxRetries, lockoutSec)
        spellName = spellName or tracker.lastSpell
        if not spellName or spellName == '' then return end

        if tracker.failed and tracker.lastSpell == spellName then return end
        tracker.failed = true

        maxRetries = maxRetries or 2
        lockoutSec = lockoutSec or 30

        local cnt = (tracker.counts[spellName] or 0) + 1
        tracker.counts[spellName] = cnt

        if cnt >= maxRetries then
            tracker.lockouts[spellName] = os.clock() + lockoutSec
            tracker.counts[spellName] = 0
            print(string.format('\ar[Triune]\ax spell "%s" failed %d tries (%s) -- waiting %ds before trying again.',
                spellName, maxRetries, tostring(reason or 'failed'), lockoutSec))
        else
            print(string.format('\ay[Triune]\ax spell "%s" failed attempt %d/%d (%s).', spellName, cnt, maxRetries,
                tostring(reason or 'failed')))
        end
    end

    function tracker.recordSuccess(spellName)
        spellName = spellName or tracker.lastSpell
        if spellName and spellName ~= '' then
            tracker.counts[spellName] = 0
            tracker.lockouts[spellName] = nil
            tracker.failed = false
        end
    end

    function tracker.onFailureEvent(reason, maxRetries, lockoutSec)
        if tracker.lastSpell and (os.clock() - tracker.lastTime) < 10.0 then
            tracker.recordFailure(tracker.lastSpell, reason, maxRetries, lockoutSec)
        end
    end

    return tracker
end

return common
