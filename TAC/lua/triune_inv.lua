---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ============================================================================
-- TRIUNE INVENTORY & BANK MANAGER (Standalone ImGui Script)
-- ----------------------------------------------------------------------------
-- Comprehensive inventory, worn equipment, bank, and shared bank search,
-- container grid visualizer, and organization assistant with offline bank
-- cache persistence for EverQuest / MacroQuest.
--
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library

-- Version
local VERSION = '1.0.0'

-- Theme & style helpers for inventory window
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
    if _varN > 0 then pcall(mq.imgui.PopStyleVar, _varN); _varN = 0 end ---@diagnostic disable-line: undefined-field
    if _colN > 0 then pcall(mq.imgui.PopStyleColor, _colN); _colN = 0 end ---@diagnostic disable-line: undefined-field
end

-- Color constants
local GOOD  = { 0.40, 0.85, 0.50, 1.0 }
local WARN  = { 0.95, 0.75, 0.30, 1.0 }
local ERR   = { 0.95, 0.40, 0.40, 1.0 }
local MUTED = { 0.55, 0.60, 0.65, 1.0 }
local ARC   = { 0.30, 0.80, 1.00, 1.0 }
local GOLD  = { 1.00, 0.85, 0.35, 1.0 }

-- Worn slot names (0 to 22)
local WORN_SLOTS = {
    [0] = 'Charm',
    [1] = 'Left Ear',
    [2] = 'Head',
    [3] = 'Face',
    [4] = 'Right Ear',
    [5] = 'Neck',
    [6] = 'Shoulders',
    [7] = 'Arms',
    [8] = 'Back',
    [9] = 'Left Wrist',
    [10] = 'Right Wrist',
    [11] = 'Ranged',
    [12] = 'Hands',
    [13] = 'Main Hand',
    [14] = 'Off Hand',
    [15] = 'Left Finger',
    [16] = 'Right Finger',
    [17] = 'Chest',
    [18] = 'Legs',
    [19] = 'Feet',
    [20] = 'Waist',
    [21] = 'Power Source',
    [22] = 'Ammo',
}

-- ImU32 (0xAABBGGRR) builder for draw list colors
local function col32(r, g, b, a)
    local R = math.min(255, math.max(0, math.floor((r or 0) * 255 + 0.5)))
    local G = math.min(255, math.max(0, math.floor((g or 0) * 255 + 0.5)))
    local B = math.min(255, math.max(0, math.floor((b or 0) * 255 + 0.5)))
    local A = math.min(255, math.max(0, math.floor((a or 1) * 255 + 0.5)))
    return (A * 16777216) + (B * 65536) + (G * 256) + R
end

local function textWidth(str)
    return #(tostring(str or '')) * 7
end

-- ============================================================================
-- Icon textures (EQ texture animations via 'A_DragItem' / 'eq' / TextureAnimation)
-- ============================================================================
local EQ_ICON_OFFSET = 500
local iconCache = {}
local iconMode  = 'probe'
local sharedTex = nil
local lastCell  = nil
local isDragItem = false

local function probeIconMode()
    if iconMode ~= 'probe' then return end
    if mq.TextureAnimation then
        local ok, res = pcall(mq.TextureAnimation, 'triuneinv_probe')
        if ok and res then
            iconMode = 'dedicated'
            return
        end
    end
    local ok1, res1 = pcall(mq.FindTextureAnimation, 'A_DragItem')
    if ok1 and res1 then
        iconMode = 'shared'
        sharedTex = res1
        isDragItem = true
        return
    end
    local ok2, res2 = pcall(mq.FindTextureAnimation, 'eq')
    if ok2 and res2 then
        iconMode  = 'shared'
        sharedTex = res2
        isDragItem = false
        return
    end
    iconMode = 'none'
end

local function iconFor(iconId)
    local id = tonumber(iconId)
    if not id or id <= 0 then return nil end
    probeIconMode()

    if iconMode == 'dedicated' then
        local key = tostring(id)
        local ta = iconCache[key]
        if not ta then
            local ok, res = pcall(mq.TextureAnimation, 'triuneinv_' .. key)
            if ok and res then
                local cell = (id >= EQ_ICON_OFFSET) and (id - EQ_ICON_OFFSET) or id
                pcall(function() res:SetTextureCell(cell) end)
                iconCache[key] = res
                ta = res
            end
        end
        return ta
    elseif iconMode == 'shared' and sharedTex then
        local cell = (isDragItem and id >= EQ_ICON_OFFSET) and (id - EQ_ICON_OFFSET) or id
        if lastCell ~= cell then
            if not pcall(function() sharedTex:SetTextureCell(cell) end) then
                return nil
            end
            lastCell = cell
        end
        return sharedTex
    end
    return nil
end

local function renderSlotIcon(iconId, startX, startY, endX, endY, dl, size)
    local anim = iconFor(iconId)
    if not anim then return false end

    size = size or 30
    local pad = 2

    if dl and dl.AddTextureAnimation then
        local ok = pcall(function()
            dl:AddTextureAnimation(anim, ImVec2(startX + pad, startY + pad), ImVec2(size, size))
        end)
        if ok then return true end
    end

    if ImGui.DrawTextureAnimation then
        local ok = pcall(function()
            ImGui.SetCursorScreenPos(startX + pad, startY + pad)
            ImGui.DrawTextureAnimation(anim, size, size)
            ImGui.SetCursorScreenPos(endX, endY)
        end)
        if ok then return true end
    end

    return false
end

local function drawTableItemIcon(iconId, size)
    local anim = iconFor(iconId)
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
            dl:AddTextureAnimation(anim, ImVec2(pX, pY), ImVec2(size, size))
        end)
        if ok then
            ImGui.Dummy(size + 2, size)
            return true
        end
    end

    return false
end

-- Application State
local state = {
    items = {},
    containers = {
        inventory = {},
        bank = {},
        sharedBank = {},
    },
    counts = {
        total = 0,
        inventory = 0,
        bank = 0,
        worn = 0,
        cursor = 0,
        freeInvSlots = 0,
        totalInvSlots = 0,
        freeBankSlots = 0,
        totalBankSlots = 0,
        invWeight = 0,
        maxWeight = 0,
        invPlat = 0,
        bankPlat = 0,
    },
    searchFilter = '',
    locFilter = 'ALL', -- ALL, INVENTORY, BANK, WORN, CURSOR
    catFilter = 'ALL', -- ALL, Weapon, Armor, Jewelry, Bag, Consumable, Tradeskill, Spell, Gem, Aug, Misc
    filterLore = false,
    filterNoDrop = false,
    filterTradeskill = false,
    filterClicky = false,
    sortCol = 'Name',
    sortAsc = true,
    bankLive = false,
    bankLastSync = 'Never',
    statusMsg = 'System Ready.',
    pendingAction = nil, -- Table: { type = '...', ... }
    dragSource = nil,
    itemDefs = {},
    tableCache = {
        dirty = true,
        lastItemsCount = 0,
        lastSearch = '',
        lastLoc = '',
        lastCat = '',
        lastLore = false,
        lastNoDrop = false,
        lastTS = false,
        lastClicky = false,
        lastSortCol = '',
        lastSortAsc = true,
        filtered = {},
    },
    lastScanTime = 0,
    autoScan = false,
    autoScanInterval = 15, -- seconds
}

local openGUI = true
local isRunning = true

-- Module for pure logic functions
local invLogic = {}

function invLogic.formatMoney(coppers)
    local c = tonumber(coppers) or 0
    if c <= 0 then return '0c' end
    local p = math.floor(c / 1000)
    local rem = c % 1000
    local g = math.floor(rem / 100)
    rem = rem % 100
    local s = math.floor(rem / 10)
    local copper = rem % 10

    local parts = {}
    if p > 0 then parts[#parts + 1] = string.format('%dp', p) end
    if g > 0 then parts[#parts + 1] = string.format('%dg', g) end
    if s > 0 then parts[#parts + 1] = string.format('%ds', s) end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = string.format('%dc', copper) end
    return table.concat(parts, ' ')
end

function invLogic.classifyItem(itemData)
    if not itemData then return 'Misc' end
    if (itemData.container or 0) > 0 then return 'Bag' end
    if (itemData.augType or 0) > 0 then return 'Aug' end

    local name = string.lower(itemData.name or '')
    local itemType = string.lower(itemData.type or '')

    if itemData.scroll or string.find(name, '^spell:') or string.find(name, '^song:') or string.find(name, '^tome of') or itemType == 'scroll' then
        return 'Spell'
    end

    if itemData.tradeskill then
        return 'Tradeskill'
    end

    if (itemData.damage or 0) > 0 or string.find(itemType, 'slashing') or string.find(itemType, 'blunt') or string.find(itemType, 'piercing') or string.find(itemType, 'archery') or string.find(itemType, 'bow') or string.find(itemType, 'hand to hand') then
        return 'Weapon'
    end

    local loc = tostring(itemData.location or '')
    if loc == 'WORN' or loc == 'Worn' then
        local slot = tostring(itemData.wornSlot or '')
        if slot == 'Neck' or slot == 'Left Ear' or slot == 'Right Ear' or slot == 'Left Finger' or slot == 'Right Finger' then
            return 'Jewelry'
        end
        return 'Armor'
    end

    if (itemData.ac or 0) > 0 then
        return 'Armor'
    end

    if string.find(itemType, 'potion') or string.find(itemType, 'food') or string.find(itemType, 'drink') or itemData.clicky then
        return 'Consumable'
    end

    if string.find(name, 'diamond') or string.find(name, 'emerald') or string.find(name, 'ruby') or string.find(name, 'sapphire') or string.find(name, 'pearl') or string.find(name, 'peridot') or string.find(name, 'opal') or string.find(name, 'topaz') or string.find(name, 'jacinth') or string.find(name, 'garnet') then
        return 'Gem'
    end

    return 'Misc'
end

function invLogic.matchesFilter(item, searchStr, locFilter, catFilter, flags)
    if not item then return false end

    -- Location filter
    if locFilter and locFilter ~= 'ALL' then
        if string.upper(item.location or '') ~= locFilter then
            return false
        end
    end

    -- Category filter
    if catFilter and catFilter ~= 'ALL' then
        if (item.category or 'Misc') ~= catFilter then
            return false
        end
    end

    -- Attribute flags
    if flags then
        if flags.lore and not item.lore then return false end
        if flags.nodrop and not item.nodrop then return false end
        if flags.tradeskill and not item.tradeskill then return false end
        if flags.clicky and not item.clicky then return false end
    end

    -- Text search filter
    if searchStr and searchStr ~= '' then
        local needle = string.lower(searchStr)
        local hayName = string.lower(item.name or '')
        local hayLoc = string.lower(item.displayLocation or '')
        local hayType = string.lower(item.type or '')
        local hayClicky = string.lower(item.clicky or '')
        local hayCat = string.lower(item.category or '')

        if not (string.find(hayName, needle, 1, true) or
                string.find(hayLoc, needle, 1, true) or
                string.find(hayType, needle, 1, true) or
                string.find(hayClicky, needle, 1, true) or
                string.find(hayCat, needle, 1, true)) then
            return false
        end
    end

    return true
end

function invLogic.findDuplicateStacks(items)
    local byId = {}
    for _, it in ipairs(items) do
        if it.stackable and (it.stackSize or 1) > 1 and it.location ~= 'WORN' then
            local key = tostring(it.id or it.name)
            if not byId[key] then
                byId[key] = { name = it.name, id = it.id, stackSize = it.stackSize, stacks = {} }
            end
            table.insert(byId[key].stacks, it)
        end
    end

    local consolidations = {}
    for _, group in pairs(byId) do
        if #group.stacks > 1 then
            local hasPartial = false
            local totalCount = 0
            for _, s in ipairs(group.stacks) do
                totalCount = totalCount + (s.count or 1)
                if (s.count or 1) < group.stackSize then
                    hasPartial = true
                end
            end
            if hasPartial then
                table.insert(consolidations, {
                    name = group.name,
                    id = group.id,
                    stackSize = group.stackSize,
                    totalCount = totalCount,
                    numStacks = #group.stacks,
                    stacks = group.stacks,
                })
            end
        end
    end

    table.sort(consolidations, function(a, b) return a.name < b.name end)
    return consolidations
end

function invLogic.findHeaviestItems(items, limit)
    local bagItems = {}
    for _, it in ipairs(items) do
        if it.location == 'INVENTORY' then
            local totalWeight = (tonumber(it.weight) or 0) * (it.stackable and (tonumber(it.count) or 1) or 1)
            table.insert(bagItems, {
                name = it.name,
                location = it.displayLocation,
                count = it.count or 1,
                weight = it.weight or 0,
                totalWeight = totalWeight,
                category = it.category,
            })
        end
    end

    table.sort(bagItems, function(a, b) return a.totalWeight > b.totalWeight end)

    local res = {}
    local maxN = math.min(limit or 10, #bagItems)
    for i = 1, maxN do
        res[i] = bagItems[i]
    end
    return res
end

-- Scanner Engine
local scanner = {}

local function getBankCachePath()
    local ok, server = pcall(function() return mq.TLO.MacroQuest.Server() end)
    local ok2, charName = pcall(function() return mq.TLO.Me.CleanName() end)
    if not ok or not server or server == '' then server = 'DefaultServer' end
    if not ok2 or not charName or charName == '' then charName = 'DefaultChar' end
    local cfg = mq.configDir or '.'
    return string.format('%s/triune_inv_bank_%s_%s.lua', cfg, server, charName)
end

local inMemoryBankCache = nil
local lastSavedBankCount = -1

function scanner.saveBankCache(bankItems, bankContainers, force)
    inMemoryBankCache = {
        syncTime = os.date('%Y-%m-%d %H:%M:%S'),
        items = bankItems,
        containers = bankContainers,
    }
    if not force and lastSavedBankCount == #bankItems then
        return true
    end
    lastSavedBankCount = #bankItems
    local path = getBankCachePath()
    local f = io.open(path, 'w')
    if not f then return false end

    f:write('-- Triune Inventory Bank Cache\n')
    f:write(string.format('return {\n  syncTime = %q,\n  items = {\n', os.date('%Y-%m-%d %H:%M:%S')))
    for _, it in ipairs(bankItems) do
        f:write(string.format('    { id=%d, icon=%d, name=%q, location=%q, slotIndex=%d, subSlot=%s, displayLocation=%q, notifyCmd=%q, count=%d, stackable=%s, stackSize=%d, weight=%.2f, value=%d, type=%q, category=%q, lore=%s, nodrop=%s, tradeskill=%s, clicky=%q, ac=%d, hp=%d, mana=%d, damage=%d, delay=%d },\n',
            it.id or 0,
            it.icon or 0,
            it.name or 'Unknown',
            it.location or 'BANK',
            it.slotIndex or 0,
            it.subSlot and tostring(it.subSlot) or 'nil',
            it.displayLocation or '',
            it.notifyCmd or '',
            it.count or 1,
            it.stackable and 'true' or 'false',
            it.stackSize or 1,
            it.weight or 0,
            it.value or 0,
            it.type or '',
            it.category or 'Misc',
            it.lore and 'true' or 'false',
            it.nodrop and 'true' or 'false',
            it.tradeskill and 'true' or 'false',
            it.clicky or '',
            it.ac or 0,
            it.hp or 0,
            it.mana or 0,
            it.damage or 0,
            it.delay or 0
        ))
    end
    f:write('  },\n  containers = {\n')
    for _, c in ipairs(bankContainers) do
        f:write(string.format('    { slot=%d, name=%q, capacity=%d, used=%d },\n',
            c.slot, c.name or '', c.capacity or 0, c.used or 0))
    end
    f:write('  }\n}\n')
    f:close()
    return true
end

function scanner.loadBankCache()
    if inMemoryBankCache then return inMemoryBankCache end
    local path = getBankCachePath()
    local fn = loadfile(path)
    if not fn then return nil end
    local ok, data = pcall(fn)
    if ok and type(data) == 'table' then
        inMemoryBankCache = data
        lastSavedBankCount = #(data.items or {})
        if data.items then
            for _, it in ipairs(data.items) do
                if it.id and it.id > 0 and not state.itemDefs[it.id] then
                    state.itemDefs[it.id] = it
                end
            end
        end
        return data
    end
    return nil
end

local function extractItemData(itemObj, locType, slotIdx, subIdx, containerName, notifyPrefix)
    if not itemObj then return nil end
    local itemId = 0
    local okId = pcall(function()
        if not itemObj() then return end
        itemId = tonumber(itemObj.ID()) or 0
    end)
    if not okId or itemId <= 0 then return nil end

    local def = state.itemDefs[itemId]
    if not def then
        local name = 'Unknown'
        local iconId = 0
        local isStackable = false
        local maxStack = 1
        local containerSlots = 0
        local wt = 0
        local val = 0
        local iType = ''
        local isLore = false
        local isNoDrop = false
        local isTS = false
        local clickySpell = nil
        local acVal, hpVal, manaVal, dmgVal, dlyVal = 0, 0, 0, 0, 0

        pcall(function()
            name = tostring(itemObj.Name() or 'Unknown')
            iconId = tonumber(itemObj.Icon()) or 0
            isStackable = itemObj.Stackable() or false
            maxStack = tonumber(itemObj.StackSize()) or 1
            containerSlots = tonumber(itemObj.Container()) or 0
            wt = tonumber(itemObj.Weight()) or 0
            val = tonumber(itemObj.Value()) or 0
            iType = tostring(itemObj.Type() or '')
            isLore = itemObj.Lore() or false
            isNoDrop = itemObj.NoDrop() or false
            isTS = itemObj.Tradeskills() or false

            local c = itemObj.Clicky
            if c and c() then
                local sp = c.Spell
                if sp and sp() then
                    local sn = sp.Name()
                    if sn and sn ~= '' then clickySpell = tostring(sn) end
                end
            end

            acVal = tonumber(itemObj.AC()) or 0
            hpVal = tonumber(itemObj.HP()) or 0
            manaVal = tonumber(itemObj.Mana()) or 0
            dmgVal = tonumber(itemObj.Damage()) or 0
            dlyVal = tonumber(itemObj.ItemDelay()) or 0
        end)

        def = {
            id = itemId,
            icon = iconId,
            name = name,
            stackable = isStackable,
            stackSize = maxStack,
            container = containerSlots,
            weight = wt,
            value = val,
            type = iType,
            lore = isLore,
            nodrop = isNoDrop,
            tradeskill = isTS,
            clicky = clickySpell,
            ac = acVal,
            hp = hpVal,
            mana = manaVal,
            damage = dmgVal,
            delay = dlyVal,
        }
        def.category = invLogic.classifyItem(def)
        state.itemDefs[itemId] = def
    end

    local stackCount = 1
    if def.stackable then
        pcall(function()
            stackCount = tonumber(itemObj.Stack()) or 1
        end)
    end

    local dispLoc = ''
    local notifyCmd = ''
    if locType == 'WORN' then
        dispLoc = string.format('Worn [%s]', WORN_SLOTS[slotIdx] or tostring(slotIdx))
        notifyCmd = string.format('%d', slotIdx)
    elseif locType == 'INVENTORY' then
        if subIdx then
            dispLoc = string.format('Bag %d [Slot %d]', slotIdx, subIdx)
            notifyCmd = string.format('in pack%d %d', slotIdx, subIdx)
        else
            dispLoc = string.format('Pack Slot %d', slotIdx)
            notifyCmd = string.format('pack%d', slotIdx)
        end
    elseif locType == 'BANK' then
        if subIdx then
            dispLoc = string.format('Bank %d [Slot %d]', slotIdx, subIdx)
            notifyCmd = string.format('in bank%d %d', slotIdx, subIdx)
        else
            dispLoc = string.format('Bank Slot %d', slotIdx)
            notifyCmd = string.format('bank%d', slotIdx)
        end
    elseif locType == 'SHAREDBANK' then
        if subIdx then
            dispLoc = string.format('SharedBank %d [Slot %d]', slotIdx, subIdx)
            notifyCmd = string.format('in sharedbank%d %d', slotIdx, subIdx)
        else
            dispLoc = string.format('SharedBank Slot %d', slotIdx)
            notifyCmd = string.format('sharedbank%d', slotIdx)
        end
    elseif locType == 'CURSOR' then
        dispLoc = 'Cursor'
        notifyCmd = ''
    end

    return {
        id = def.id,
        icon = def.icon,
        name = def.name,
        location = locType,
        slotIndex = slotIdx,
        subSlot = subIdx,
        wornSlot = locType == 'WORN' and (WORN_SLOTS[slotIdx] or tostring(slotIdx)) or nil,
        containerName = containerName,
        displayLocation = dispLoc,
        notifyCmd = notifyCmd,
        count = stackCount,
        stackable = def.stackable,
        stackSize = def.stackSize,
        container = def.container,
        weight = def.weight,
        value = def.value,
        type = def.type,
        category = def.category,
        lore = def.lore,
        nodrop = def.nodrop,
        tradeskill = def.tradeskill,
        clicky = def.clicky,
        ac = def.ac,
        hp = def.hp,
        mana = def.mana,
        damage = def.damage,
        delay = def.delay,
    }
end

function scanner.scanAll()
    local scannedItems = {}
    local invContainers = {}
    local bankContainers = {}
    local sharedContainers = {}

    local totalInvCapacity = 0
    local totalInvUsed = 0
    local totalBankCapacity = 0
    local totalBankUsed = 0

    -- 1. Scan Worn Equipment (0..22)
    local wornCount = 0
    for slot = 0, 22 do
        local ok, itemObj = pcall(function() return mq.TLO.Me.Inventory(slot) end)
        if ok and itemObj and itemObj() and (itemObj.ID() or 0) > 0 then
            local it = extractItemData(itemObj, 'WORN', slot, nil, 'Worn', nil)
            if it then
                table.insert(scannedItems, it)
                wornCount = wornCount + 1
            end
        end
    end

    -- 2. Scan Inventory Bags (pack1..pack10, slots 23..32)
    local invCount = 0
    for p = 1, 10 do
        local ok, packObj = pcall(function() return mq.TLO.Me.Inventory('pack' .. p) end)
        if ok and packObj and packObj() and (packObj.ID() or 0) > 0 then
            local bagCap = 0
            pcall(function() bagCap = packObj.Container() or 0 end)
            local bagName = 'Backpack'
            pcall(function() bagName = tostring(packObj.Name() or 'Backpack') end)

            if bagCap > 0 then
                totalInvCapacity = totalInvCapacity + bagCap
                local usedInBag = 0
                local bagSlots = {}

                for s = 1, bagCap do
                    local okSub, subItem = pcall(function() return packObj.Item(s) end)
                    if okSub and subItem and subItem() and (subItem.ID() or 0) > 0 then
                        local it = extractItemData(subItem, 'INVENTORY', p, s, bagName, 'pack' .. p)
                        if it then
                            table.insert(scannedItems, it)
                            invCount = invCount + 1
                            usedInBag = usedInBag + 1
                            bagSlots[s] = it
                        end
                    else
                        bagSlots[s] = nil
                    end
                end

                totalInvUsed = totalInvUsed + usedInBag
                table.insert(invContainers, {
                    slot = p,
                    name = bagName,
                    capacity = bagCap,
                    used = usedInBag,
                    slots = bagSlots,
                })
            else
                -- Loose item directly in pack slot (not a bag)
                totalInvCapacity = totalInvCapacity + 1
                totalInvUsed = totalInvUsed + 1
                local it = extractItemData(packObj, 'INVENTORY', p, nil, 'Pack Slot', 'pack' .. p)
                if it then
                    table.insert(scannedItems, it)
                    invCount = invCount + 1
                end
                table.insert(invContainers, {
                    slot = p,
                    name = it and it.name or 'Item',
                    capacity = 1,
                    used = 1,
                    slots = { [1] = it },
                })
            end
        else
            -- Empty pack slot
            table.insert(invContainers, {
                slot = p,
                name = '(Empty Pack Slot)',
                capacity = 0,
                used = 0,
                slots = {},
            })
        end
    end

    -- 3. Scan Bank & Shared Bank
    local bankOpen = false
    pcall(function()
        local w1 = mq.TLO.Window('BigBankWnd')
        local w2 = mq.TLO.Window('BankWnd')
        bankOpen = (w1 and w1() and w1.Open and w1.Open()) or (w2 and w2() and w2.Open and w2.Open()) or false
    end)

    local liveBankItems = {}
    local bankItemCount = 0
    local maxBankSlots = 24
    pcall(function()
        local bSlots = mq.TLO.Bank.BagSlots()
        if bSlots and bSlots > 0 then maxBankSlots = bSlots end
    end)

    local liveBankAvailable = bankOpen

    if liveBankAvailable then
        state.bankLive = true
        state.bankLastSync = os.date('%H:%M:%S')

        for b = 1, maxBankSlots do
            local ok, bBag = pcall(function() return mq.TLO.Me.Bank(b) end)
            if ok and bBag and bBag() and (bBag.ID() or 0) > 0 then
                local bagCap = 0
                pcall(function() bagCap = bBag.Container() or 0 end)
                local bagName = 'Bank Container'
                pcall(function() bagName = tostring(bBag.Name() or 'Bank Container') end)

                if bagCap > 0 then
                    totalBankCapacity = totalBankCapacity + bagCap
                    local usedInBank = 0
                    local bagSlots = {}

                    for s = 1, bagCap do
                        local okSub, subItem = pcall(function() return bBag.Item(s) end)
                        if okSub and subItem and subItem() and (subItem.ID() or 0) > 0 then
                            local it = extractItemData(subItem, 'BANK', b, s, bagName, 'bank' .. b)
                            if it then
                                table.insert(liveBankItems, it)
                                bankItemCount = bankItemCount + 1
                                usedInBank = usedInBank + 1
                                bagSlots[s] = it
                            end
                        else
                            bagSlots[s] = nil
                        end
                    end

                    totalBankUsed = totalBankUsed + usedInBank
                    table.insert(bankContainers, {
                        slot = b,
                        name = bagName,
                        capacity = bagCap,
                        used = usedInBank,
                        slots = bagSlots,
                    })
                else
                    totalBankCapacity = totalBankCapacity + 1
                    totalBankUsed = totalBankUsed + 1
                    local it = extractItemData(bBag, 'BANK', b, nil, 'Bank Slot', 'bank' .. b)
                    if it then
                        table.insert(liveBankItems, it)
                        bankItemCount = bankItemCount + 1
                    end
                    table.insert(bankContainers, {
                        slot = b,
                        name = it and it.name or 'Item',
                        capacity = 1,
                        used = 1,
                        slots = { [1] = it },
                    })
                end
            end
        end

        -- Shared Bank
        for sb = 1, 4 do
            local ok, sbBag = pcall(function() return mq.TLO.Me.SharedBank(sb) end)
            if ok and sbBag and sbBag() and (sbBag.ID() or 0) > 0 then
                local bagCap = 0
                pcall(function() bagCap = sbBag.Container() or 0 end)
                local bagName = 'Shared Bank Container'
                pcall(function() bagName = tostring(sbBag.Name() or 'Shared Bank Container') end)

                if bagCap > 0 then
                    for s = 1, bagCap do
                        local okSub, subItem = pcall(function() return sbBag.Item(s) end)
                        if okSub and subItem and subItem() and (subItem.ID() or 0) > 0 then
                            local it = extractItemData(subItem, 'SHAREDBANK', sb, s, bagName, 'sharedbank' .. sb)
                            if it then
                                table.insert(liveBankItems, it)
                                bankItemCount = bankItemCount + 1
                            end
                        end
                    end
                else
                    local it = extractItemData(sbBag, 'SHAREDBANK', sb, nil, 'Shared Bank Slot', 'sharedbank' .. sb)
                    if it then
                        table.insert(liveBankItems, it)
                        bankItemCount = bankItemCount + 1
                    end
                end
            end
        end

        -- Persist live bank scan
        scanner.saveBankCache(liveBankItems, bankContainers)
        for _, it in ipairs(liveBankItems) do
            table.insert(scannedItems, it)
        end
    else
        -- Load from Bank Cache
        state.bankLive = false
        local cached = scanner.loadBankCache()
        if cached then
            state.bankLastSync = cached.syncTime or 'Cached'
            if cached.items then
                for _, it in ipairs(cached.items) do
                    table.insert(scannedItems, it)
                    bankItemCount = bankItemCount + 1
                end
            end
            if cached.containers then
                local bankSlotsByBag = {}
                if cached.items then
                    for _, it in ipairs(cached.items) do
                        if it.location == 'BANK' and it.slotIndex and it.subSlot then
                            if not bankSlotsByBag[it.slotIndex] then bankSlotsByBag[it.slotIndex] = {} end
                            bankSlotsByBag[it.slotIndex][it.subSlot] = it
                        end
                    end
                end
                for _, c in ipairs(cached.containers) do
                    c.slots = bankSlotsByBag[c.slot] or {}
                    table.insert(bankContainers, c)
                    totalBankCapacity = totalBankCapacity + (c.capacity or 0)
                    totalBankUsed = totalBankUsed + (c.used or 0)
                end
            end
        end
    end

    -- 4. Scan Cursor
    local cursorCount = 0
    local okCur, curItem = pcall(function() return mq.TLO.Cursor end)
    if okCur and curItem and curItem() and (curItem.ID() or 0) > 0 then
        local it = extractItemData(curItem, 'CURSOR', 0, nil, 'Cursor', nil)
        if it then
            table.insert(scannedItems, it)
            cursorCount = cursorCount + 1
        end
    end

    -- 5. Currency & Stats
    local myPlat, bPlat = 0, 0
    pcall(function()
        myPlat = mq.TLO.Me.Platinum() or 0
        bPlat = mq.TLO.Me.PlatinumBank() or 0
    end)

    local curWt, maxWt = 0, 0
    pcall(function()
        curWt = mq.TLO.Me.Weight() or 0
        maxWt = mq.TLO.Me.MaxWeight() or 0
    end)

    -- Update state
    state.items = scannedItems
    state.containers.inventory = invContainers
    state.containers.bank = bankContainers
    state.containers.sharedBank = sharedContainers

    state.counts.total = #scannedItems
    state.counts.inventory = invCount
    state.counts.bank = bankItemCount
    state.counts.worn = wornCount
    state.counts.cursor = cursorCount
    state.counts.totalInvSlots = totalInvCapacity
    state.counts.freeInvSlots = math.max(0, totalInvCapacity - totalInvUsed)
    state.counts.totalBankSlots = totalBankCapacity
    state.counts.freeBankSlots = math.max(0, totalBankCapacity - totalBankUsed)
    state.counts.invWeight = curWt
    state.counts.maxWeight = maxWt
    state.counts.invPlat = myPlat
    state.counts.bankPlat = bPlat
    state.lastScanTime = os.time()
    state.tableCache.dirty = true
end

-- UI Drawing Helpers
local UI = {}

function UI.drawHeader()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "TRIUNE INVENTORY & BANK")
    ImGui.SameLine()
    ImGui.TextDisabled(string.format("v%s | Universal Item Manager", VERSION))

    ImGui.SameLine()
    local availWidth = ImGui.GetContentRegionAvail()
    if availWidth > 220 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + availWidth - 220)
    end

    -- Bank Status Pill
    if state.bankLive then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "● Bank: Live")
    else
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "○ Bank: Cached (" .. tostring(state.bankLastSync) .. ")")
    end

    ImGui.Separator()
    ImGui.Dummy(0, 2)

    -- Stats summary row
    local freeInv = state.counts.freeInvSlots
    local invCol = freeInv > 10 and GOOD or (freeInv > 0 and WARN or ERR)
    ImGui.TextDisabled("Bags Free:")
    ImGui.SameLine()
    ImGui.TextColored(invCol[1], invCol[2], invCol[3], invCol[4], string.format("%d / %d", freeInv, state.counts.totalInvSlots))

    ImGui.SameLine(0, 16)
    ImGui.TextDisabled("Bank Free:")
    ImGui.SameLine()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("%d / %d", state.counts.freeBankSlots, state.counts.totalBankSlots))

    ImGui.SameLine(0, 16)
    local wtCol = (state.counts.maxWeight > 0 and state.counts.invWeight > state.counts.maxWeight) and ERR or GOOD
    ImGui.TextDisabled("Weight:")
    ImGui.SameLine()
    ImGui.TextColored(wtCol[1], wtCol[2], wtCol[3], wtCol[4], string.format("%d / %d lbs", state.counts.invWeight, state.counts.maxWeight))

    ImGui.SameLine(0, 16)
    ImGui.TextDisabled("Cash:")
    ImGui.SameLine()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format("%dp (Bank: %dp)", state.counts.invPlat, state.counts.bankPlat))

    if state.counts.cursor > 0 then
        ImGui.SameLine(0, 16)
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "[Item on Cursor!]")
        ImGui.SameLine()
        if ImGui.Button("Auto-Inv##hdrAutoInv", 70, 20) then
            state.pendingAction = { type = 'autoinv' }
        end
    end

    ImGui.Dummy(0, 4)

    -- Search and Filter Controls
    ImGui.PushItemWidth(220)
    local newSearch, searchChanged = ImGui.InputTextWithHint("##InvSearch", "Search item, type, clicky...", state.searchFilter or '')
    if searchChanged and type(newSearch) == 'string' then
        state.searchFilter = newSearch
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("X##clearSearch", 22, 22) then
        state.searchFilter = ''
    end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', "Clear search filter") end

    ImGui.SameLine(0, 12)
    -- Location Filter buttons
    local locs = {
        { id = 'ALL', label = string.format("All (%d)", state.counts.total) },
        { id = 'INVENTORY', label = string.format("Bags (%d)", state.counts.inventory) },
        { id = 'BANK', label = string.format("Bank (%d)", state.counts.bank) },
        { id = 'WORN', label = string.format("Worn (%d)", state.counts.worn) },
    }

    for _, l in ipairs(locs) do
        local isSel = state.locFilter == l.id
        if isSel then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.16, 0.50, 0.75, 0.8)
        end
        if ImGui.Button(l.label .. "##locBtn" .. l.id) then
            state.locFilter = l.id
        end
        if isSel then
            ImGui.PopStyleColor(1)
        end
        ImGui.SameLine()
    end

    -- Category Dropdown
    ImGui.PushItemWidth(120)
    local cats = { 'ALL', 'Weapon', 'Armor', 'Jewelry', 'Bag', 'Consumable', 'Tradeskill', 'Spell', 'Gem', 'Aug', 'Misc' }
    if ImGui.BeginCombo("##CatCombo", state.catFilter) then
        for _, c in ipairs(cats) do
            local isSel = state.catFilter == c
            if ImGui.Selectable(c, isSel) then
                state.catFilter = c
            end
            if isSel then ImGui.SetItemDefaultFocus() end
        end
        ImGui.EndCombo()
    end
    ImGui.PopItemWidth()

    ImGui.SameLine(0, 12)
    state.filterTradeskill = ImGui.Checkbox("Tradeskill##fltTS", state.filterTradeskill)
    ImGui.SameLine()
    state.filterLore = ImGui.Checkbox("Lore##fltLore", state.filterLore)
    ImGui.SameLine()
    state.filterNoDrop = ImGui.Checkbox("No-Drop##fltND", state.filterNoDrop)
    ImGui.SameLine()
    state.filterClicky = ImGui.Checkbox("Clicky##fltClk", state.filterClicky)

    ImGui.SameLine(0, 16)
    if ImGui.Button("Refresh Scan##hdrScanBtn", 100, 22) then
        scanner.scanAll()
    end

    ImGui.Separator()
end

function UI.drawTooltip(it)
    ImGui.BeginTooltip()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], it.name or 'Item')
    ImGui.TextDisabled(string.format("ID: %d | Type: %s | Location: %s", it.id or 0, it.type or 'Misc', it.displayLocation or ''))
    ImGui.Separator()

    if it.damage and it.damage > 0 then
        ImGui.Text(string.format("Damage: %d   Delay: %d", it.damage, it.delay or 0))
    end
    if it.ac and it.ac > 0 then
        ImGui.Text(string.format("AC: %d", it.ac))
    end
    if (it.hp and it.hp > 0) or (it.mana and it.mana > 0) then
        ImGui.Text(string.format("HP: +%d   Mana: +%d", it.hp or 0, it.mana or 0))
    end

    if it.clicky and it.clicky ~= '' then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Effect: " .. it.clicky)
    end

    local tags = {}
    if it.lore then table.insert(tags, "LORE") end
    if it.nodrop then table.insert(tags, "NO TRADE") end
    if it.tradeskill then table.insert(tags, "TRADESKILL") end
    if it.stackable then table.insert(tags, string.format("STACKABLE (%d/%d)", it.count or 1, it.stackSize or 1)) end
    if #tags > 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], table.concat(tags, " | "))
    end

    ImGui.TextDisabled(string.format("Weight: %.1f | Value: %s", it.weight or 0, invLogic.formatMoney(it.value or 0)))
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Left-Click: Pick up / Place | Right-Click: Inspect | Drag: Move")
    ImGui.EndTooltip()
end

function UI.drawItemsTable()
    local tc = state.tableCache
    local isDirty = tc.dirty
        or tc.lastItemsCount ~= #state.items
        or tc.lastSearch ~= state.searchFilter
        or tc.lastLoc ~= state.locFilter
        or tc.lastCat ~= state.catFilter
        or tc.lastLore ~= state.filterLore
        or tc.lastNoDrop ~= state.filterNoDrop
        or tc.lastTS ~= state.filterTradeskill
        or tc.lastClicky ~= state.filterClicky
        or tc.lastSortCol ~= state.sortCol
        or tc.lastSortAsc ~= state.sortAsc

    if isDirty then
        local flags = {
            lore = state.filterLore,
            nodrop = state.filterNoDrop,
            tradeskill = state.filterTradeskill,
            clicky = state.filterClicky,
        }

        local filt = {}
        for _, it in ipairs(state.items) do
            if invLogic.matchesFilter(it, state.searchFilter, state.locFilter, state.catFilter, flags) then
                table.insert(filt, it)
            end
        end

        local colKey = string.lower(state.sortCol)
        table.sort(filt, function(a, b)
            local valA = a[colKey] or a.name or ''
            local valB = b[colKey] or b.name or ''
            if type(valA) == 'string' then valA = string.lower(valA) end
            if type(valB) == 'string' then valB = string.lower(valB) end
            if state.sortAsc then
                return valA < valB
            else
                return valA > valB
            end
        end)

        tc.filtered = filt
        tc.dirty = false
        tc.lastItemsCount = #state.items
        tc.lastSearch = state.searchFilter
        tc.lastLoc = state.locFilter
        tc.lastCat = state.catFilter
        tc.lastLore = state.filterLore
        tc.lastNoDrop = state.filterNoDrop
        tc.lastTS = state.filterTradeskill
        tc.lastClicky = state.filterClicky
        tc.lastSortCol = state.sortCol
        tc.lastSortAsc = state.sortAsc
    end

    local filtered = tc.filtered

    ImGui.TextDisabled(string.format("Showing %d matching items", #filtered))
    ImGui.Dummy(0, 2)

    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Sortable
    if ImGui.BeginTable("InvItemsTable", 8, tableFlags, ImVec2(0, 0)) then
        ImGui.TableSetupColumn("Location##colLoc", ImGuiTableColumnFlags.WidthFixed, 110)
        ImGui.TableSetupColumn("Item Name##colName", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Category##colCat", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableSetupColumn("Qty##colQty", ImGuiTableColumnFlags.WidthFixed, 55)
        ImGui.TableSetupColumn("Wt##colWt", ImGuiTableColumnFlags.WidthFixed, 45)
        ImGui.TableSetupColumn("Value##colVal", ImGuiTableColumnFlags.WidthFixed, 75)
        ImGui.TableSetupColumn("Flags##colFlags", ImGuiTableColumnFlags.WidthFixed, 85)
        ImGui.TableSetupColumn("Actions##colAct", ImGuiTableColumnFlags.WidthFixed, 140)
        ImGui.TableHeadersRow()

        local clipper = nil
        local ClipperClass = ImGui.ListClipper or (mq.imgui and mq.imgui.ListClipper) or _G['ImGuiListClipper']
        if ClipperClass and ClipperClass.new then
            local okC, c = pcall(ClipperClass.new)
            if okC and c then clipper = c end
        end

        local function drawRow(idx, it)
            ImGui.TableNextRow()

            -- Col 0: Location
            ImGui.TableSetColumnIndex(0)
            local locColor = it.location == 'INVENTORY' and ARC or (it.location == 'BANK' and GOLD or (it.location == 'WORN' and GOOD or WARN))
            ImGui.TextColored(locColor[1], locColor[2], locColor[3], locColor[4], it.displayLocation or '')

            -- Col 1: Name & Icon
            ImGui.TableSetColumnIndex(1)
            if drawTableItemIcon(it.icon, 18) then
                ImGui.SameLine()
            end
            local nameCol = it.clicky and GOLD or (it.tradeskill and ARC or GOOD)
            ImGui.TextColored(nameCol[1], nameCol[2], nameCol[3], nameCol[4], it.name or 'Unknown')
            if ImGui.IsItemHovered() then
                UI.drawTooltip(it)
            end

            -- Col 2: Category
            ImGui.TableSetColumnIndex(2)
            ImGui.TextDisabled(it.category or 'Misc')

            -- Col 3: Qty
            ImGui.TableSetColumnIndex(3)
            if it.stackable then
                ImGui.Text(string.format("%d/%d", it.count or 1, it.stackSize or 1))
            else
                ImGui.TextDisabled("1")
            end

            -- Col 4: Weight
            ImGui.TableSetColumnIndex(4)
            ImGui.Text(string.format("%.1f", it.weight or 0))

            -- Col 5: Value
            ImGui.TableSetColumnIndex(5)
            ImGui.TextDisabled(invLogic.formatMoney(it.value or 0))

            -- Col 6: Flags
            ImGui.TableSetColumnIndex(6)
            local fStr = ""
            if it.lore then fStr = fStr .. "L " end
            if it.nodrop then fStr = fStr .. "ND " end
            if it.tradeskill then fStr = fStr .. "TS " end
            if it.clicky then fStr = fStr .. "CLK" end
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], fStr)

            -- Col 7: Actions
            ImGui.TableSetColumnIndex(7)
            if ImGui.SmallButton("Inspect##ins" .. idx) then
                state.pendingAction = { type = 'inspect', item = it }
            end
            ImGui.SameLine()
            if it.location == 'INVENTORY' and it.subSlot then
                if ImGui.SmallButton("Open##opn" .. idx) then
                    state.pendingAction = { type = 'open_bag', slot = it.slotIndex }
                end
                ImGui.SameLine()
                if ImGui.SmallButton("Pick##pck" .. idx) then
                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                end
            elseif it.location == 'BANK' and state.bankLive and it.subSlot then
                if ImGui.SmallButton("Pick##pckB" .. idx) then
                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                end
            end
        end

        if clipper then
            clipper:Begin(#filtered)
            while clipper:Step() do
                for idx = clipper.DisplayStart + 1, clipper.DisplayEnd do
                    local it = filtered[idx]
                    if it then
                        drawRow(idx, it)
                    end
                end
            end
            clipper:End()
        else
            for idx, it in ipairs(filtered) do
                drawRow(idx, it)
            end
        end

        ImGui.EndTable()
    end
end

function UI.drawVisualizer()
    local cursorHasItem = false
    local cursorItemName = ''
    local cursorItemCount = 1
    local okCur, curId = pcall(function() return mq.TLO.Cursor.ID() end)
    if okCur and curId and curId > 0 then
        cursorHasItem = true
        pcall(function()
            cursorItemName = mq.TLO.Cursor.Name() or 'Unknown Item'
            cursorItemCount = mq.TLO.Cursor.Stack() or 1
        end)
    end

    if cursorHasItem then
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.14, 0.11, 0.05, 0.85)
        ImGui.PushStyleColor(ImGuiCol.Border, 0.75, 0.60, 0.20, 0.90)
        ImGui.BeginChild("CursorBanner", ImVec2(0, 32), true)
        local cText = string.format("CURSOR: %s%s", cursorItemName, cursorItemCount > 1 and string.format(" (x%d)", cursorItemCount) or "")
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], cText)
        ImGui.SameLine()
        ImGui.TextDisabled("— Click any slot below to place/swap, or:")
        ImGui.SameLine()
        if ImGui.SmallButton("Auto-Inventory##visAutoInv") then
            state.pendingAction = { type = 'autoinv' }
        end
        ImGui.EndChild()
        ImGui.PopStyleColor(2)
        ImGui.Dummy(0, 2)
    else
        ImGui.TextDisabled("Visual Container Overview — Left-Click: Pick up / Place | Right-Click: Inspect | Drag & Drop to Move")
        ImGui.Dummy(0, 4)
    end

    local availWidth = ImGui.GetContentRegionAvail()
    local halfWidth = math.floor((availWidth - 16) / 2)

    -- Left Child: Inventory Bags
    ImGui.BeginChild("InvVisualizerChild", ImVec2(halfWidth, 0), true)
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "PERSONAL INVENTORY BAGS (1..10)")
    ImGui.Separator()
    ImGui.Dummy(0, 4)

    for bIdx, bag in ipairs(state.containers.inventory) do
        if bag.capacity > 0 then
            local pct = bag.capacity > 0 and (bag.used / bag.capacity) or 0
            local barCol = pct >= 1.0 and ERR or (pct >= 0.75 and WARN or GOOD)

            ImGui.TextColored(barCol[1], barCol[2], barCol[3], barCol[4], string.format("Bag %d: %s", bag.slot, bag.name))
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("(%d/%d slots)", bag.used, bag.capacity))
            ImGui.SameLine()
            if ImGui.SmallButton("Open##openBag" .. bIdx) then
                state.pendingAction = { type = 'open_bag', slot = bag.slot }
            end

            -- Slot grid (up to 10 columns)
            local cols = math.min(bag.capacity, 10)
            if cols > 0 then
                for s = 1, bag.capacity do
                    local it = bag.slots and bag.slots[s]
                    local btnId = string.format("##b%ds%d", bag.slot, s)
                    local startX, startY = ImGui.GetCursorScreenPos()

                    local clicked = ImGui.InvisibleButton(btnId, 34, 34)
                    local hovered = ImGui.IsItemHovered()
                    local active  = ImGui.IsItemActive()
                    local endX, endY = ImGui.GetCursorScreenPos()

                    local dl = ImGui.GetWindowDrawList()

                    -- Slot background
                    local bgCol
                    if it then
                        bgCol = active and col32(0.35, 0.55, 0.85, 0.9)
                             or (hovered and col32(0.20, 0.40, 0.65, 0.8)
                             or col32(0.08, 0.12, 0.18, 0.85))
                    else
                        bgCol = hovered and col32(0.12, 0.16, 0.22, 0.6)
                             or col32(0.04, 0.06, 0.09, 0.5)
                    end
                    dl:AddRectFilled(ImVec2(startX, startY), ImVec2(startX + 34, startY + 34), bgCol, 3)

                    -- Slot border
                    local bdrCol
                    if hovered then
                        bdrCol = cursorHasItem and col32(1.0, 0.85, 0.30, 1.0) or col32(0.50, 0.70, 1.0, 0.9)
                    else
                        bdrCol = it and col32(0.25, 0.40, 0.60, 0.7) or col32(0.18, 0.22, 0.28, 0.5)
                    end
                    dl:AddRect(ImVec2(startX, startY), ImVec2(startX + 34, startY + 34), bdrCol, 3)

                    -- Item icon or fallback slot number
                    local iconDrawn = false
                    if it and it.icon and it.icon > 0 then
                        iconDrawn = renderSlotIcon(it.icon, startX, startY, endX, endY, dl, 30)
                    end

                    if not iconDrawn then
                        local sStr = tostring(s)
                        local sw = textWidth(sStr)
                        local numCol = it and col32(0.85, 0.90, 0.95, 0.9) or col32(0.35, 0.40, 0.45, 0.5)
                        dl:AddText(ImVec2(startX + math.max(0, (34 - sw) / 2), startY + 10), numCol, sStr)
                    end

                    -- Stack count badge
                    if it and it.stackable and it.count and it.count > 1 then
                        local cStr = tostring(it.count)
                        local cw = textWidth(cStr)
                        dl:AddRectFilled(ImVec2(startX + 34 - cw - 4, startY + 34 - 12), ImVec2(startX + 34 - 1, startY + 34 - 1), col32(0, 0, 0, 0.75), 2)
                        dl:AddText(ImVec2(startX + 34 - cw - 2, startY + 34 - 13), col32(1.0, 0.95, 0.5, 1.0), cStr)
                    end

                    -- Tooltip
                    if hovered then
                        if it then
                            UI.drawTooltip(it)
                        elseif cursorHasItem then
                            ImGui.SetTooltip('%s', string.format("Bag %d Slot %d: Click to place %s", bag.slot, s, cursorItemName))
                        else
                            ImGui.SetTooltip('%s', string.format("Bag %d Slot %d: Empty", bag.slot, s))
                        end
                    end

                    -- Drag & Drop Source
                    if it and ImGui.BeginDragDropSource() then
                        ImGui.SetDragDropPayload("TRIUNE_INV_SLOT", it.notifyCmd)
                        state.dragSource = it
                        ImGui.Text(string.format("Moving: %s", it.name or "Item"))
                        ImGui.EndDragDropSource()
                    end

                    -- Drag & Drop Target
                    if ImGui.BeginDragDropTarget() then
                        local payload = ImGui.AcceptDragDropPayload("TRIUNE_INV_SLOT")
                        if payload then
                            local fromCmd = (type(payload) == 'table' and payload.Data)
                                or (type(payload) == 'userdata' and payload.Data)
                                or (state.dragSource and state.dragSource.notifyCmd)
                                or payload
                            fromCmd = tostring(fromCmd or '')
                            local toCmd = it and it.notifyCmd or string.format('in pack%d %d', bag.slot, s)
                            if fromCmd ~= '' and toCmd ~= '' and fromCmd ~= toCmd then
                                state.pendingAction = { type = 'move', fromCmd = fromCmd, toCmd = toCmd }
                            end
                            state.dragSource = nil
                        end
                        ImGui.EndDragDropTarget()
                    end

                    -- Click handling (Left: Pickup/Place/Swap, Right: Inspect)
                    local rClicked = ImGui.IsItemClicked(1)
                    if clicked and not state.pendingAction then
                        if cursorHasItem then
                            local targetCmd = it and it.notifyCmd or string.format('in pack%d %d', bag.slot, s)
                            state.pendingAction = { type = 'pickup', notifyCmd = targetCmd }
                        elseif it then
                            state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                        end
                    elseif rClicked and it and not state.pendingAction then
                        state.pendingAction = { type = 'inspect', item = it }
                    end

                    if s % cols ~= 0 and s < bag.capacity then
                        ImGui.SameLine(0, 4)
                    end
                end
            end
            ImGui.Dummy(0, 6)
        end
    end

    ImGui.EndChild()

    ImGui.SameLine(0, 16)

    -- Right Child: Bank Containers
    ImGui.BeginChild("BankVisualizerChild", ImVec2(halfWidth, 0), true)
    local bankTitle = state.bankLive and "BANK STORAGE (LIVE)" or "BANK STORAGE (CACHED)"
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], bankTitle)
    ImGui.Separator()
    ImGui.Dummy(0, 4)

    if #state.containers.bank == 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "No bank data available.\nVisit a banker in any major city to sync your bank inventory!")
    else
        for _, bag in ipairs(state.containers.bank) do
            if bag.capacity > 0 then
                local pct = bag.capacity > 0 and (bag.used / bag.capacity) or 0
                local barCol = pct >= 1.0 and ERR or (pct >= 0.75 and WARN or GOOD)

                ImGui.TextColored(barCol[1], barCol[2], barCol[3], barCol[4], string.format("Bank %d: %s", bag.slot, bag.name))
                ImGui.SameLine()
                ImGui.TextDisabled(string.format("(%d/%d slots)", bag.used, bag.capacity))

                local cols = math.min(bag.capacity, 10)
                if cols > 0 then
                    for s = 1, bag.capacity do
                        local it = bag.slots and bag.slots[s]
                        local btnId = string.format("##bk%ds%d", bag.slot, s)
                        local startX, startY = ImGui.GetCursorScreenPos()

                        local clicked = ImGui.InvisibleButton(btnId, 34, 34)
                        local hovered = ImGui.IsItemHovered()
                        local active  = ImGui.IsItemActive()
                        local endX, endY = ImGui.GetCursorScreenPos()

                        local dl = ImGui.GetWindowDrawList()

                        -- Slot background
                        local bgCol
                        if it then
                            bgCol = active and col32(0.55, 0.45, 0.15, 0.9)
                                 or (hovered and col32(0.40, 0.30, 0.10, 0.8)
                                 or col32(0.16, 0.13, 0.07, 0.85))
                        else
                            bgCol = hovered and col32(0.12, 0.12, 0.14, 0.6)
                                 or col32(0.05, 0.05, 0.07, 0.5)
                        end
                        dl:AddRectFilled(ImVec2(startX, startY), ImVec2(startX + 34, startY + 34), bgCol, 3)

                        -- Slot border
                        local bdrCol
                        if hovered then
                            bdrCol = (cursorHasItem and state.bankLive) and col32(1.0, 0.90, 0.40, 1.0) or col32(0.90, 0.75, 0.30, 0.9)
                        else
                            bdrCol = it and col32(0.60, 0.45, 0.20, 0.7) or col32(0.20, 0.18, 0.15, 0.5)
                        end
                        dl:AddRect(ImVec2(startX, startY), ImVec2(startX + 34, startY + 34), bdrCol, 3)

                        -- Item icon or fallback slot number
                        local iconDrawn = false
                        if it and it.icon and it.icon > 0 then
                            iconDrawn = renderSlotIcon(it.icon, startX, startY, endX, endY, dl, 30)
                        end

                        if not iconDrawn then
                            local sStr = tostring(s)
                            local sw = textWidth(sStr)
                            local numCol = it and col32(0.95, 0.90, 0.80, 0.9) or col32(0.35, 0.40, 0.45, 0.5)
                            dl:AddText(ImVec2(startX + math.max(0, (34 - sw) / 2), startY + 10), numCol, sStr)
                        end

                        -- Stack count badge
                        if it and it.stackable and it.count and it.count > 1 then
                            local cStr = tostring(it.count)
                            local cw = textWidth(cStr)
                            dl:AddRectFilled(ImVec2(startX + 34 - cw - 4, startY + 34 - 12), ImVec2(startX + 34 - 1, startY + 34 - 1), col32(0, 0, 0, 0.75), 2)
                            dl:AddText(ImVec2(startX + 34 - cw - 2, startY + 34 - 13), col32(1.0, 0.95, 0.5, 1.0), cStr)
                        end

                        -- Tooltip
                        if hovered then
                            if it then
                                UI.drawTooltip(it)
                                if not state.bankLive then
                                    ImGui.BeginTooltip()
                                    ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "(Bank is closed — Visit a banker to move bank items)")
                                    ImGui.EndTooltip()
                                end
                            elseif cursorHasItem and state.bankLive then
                                ImGui.SetTooltip('%s', string.format("Bank %d Slot %d: Click to place %s", bag.slot, s, cursorItemName))
                            else
                                ImGui.SetTooltip('%s', string.format("Bank %d Slot %d: Empty", bag.slot, s))
                            end
                        end

                        -- Bank Drag & Drop (only when bank is live)
                        if state.bankLive then
                            if it and ImGui.BeginDragDropSource() then
                                ImGui.SetDragDropPayload("TRIUNE_INV_SLOT", it.notifyCmd)
                                state.dragSource = it
                                ImGui.Text(string.format("Moving: %s", it.name or "Item"))
                                ImGui.EndDragDropSource()
                            end

                            if ImGui.BeginDragDropTarget() then
                                local payload = ImGui.AcceptDragDropPayload("TRIUNE_INV_SLOT")
                                if payload then
                                    local fromCmd = (type(payload) == 'table' and payload.Data)
                                        or (type(payload) == 'userdata' and payload.Data)
                                        or (state.dragSource and state.dragSource.notifyCmd)
                                        or payload
                                    fromCmd = tostring(fromCmd or '')
                                    local toCmd = it and it.notifyCmd or string.format('in bank%d %d', bag.slot, s)
                                    if fromCmd ~= '' and toCmd ~= '' and fromCmd ~= toCmd then
                                        state.pendingAction = { type = 'move', fromCmd = fromCmd, toCmd = toCmd }
                                    end
                                    state.dragSource = nil
                                end
                                ImGui.EndDragDropTarget()
                            end
                        end

                        -- Click handling
                        local rClicked = ImGui.IsItemClicked(1)
                        if clicked and not state.pendingAction then
                            if state.bankLive then
                                if cursorHasItem then
                                    local targetCmd = it and it.notifyCmd or string.format('in bank%d %d', bag.slot, s)
                                    state.pendingAction = { type = 'pickup', notifyCmd = targetCmd }
                                elseif it then
                                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                                end
                            elseif it then
                                -- Bank cached: clicking inspects
                                state.pendingAction = { type = 'inspect', item = it }
                            end
                        elseif rClicked and it and not state.pendingAction then
                            state.pendingAction = { type = 'inspect', item = it }
                        end

                        if s % cols ~= 0 and s < bag.capacity then
                            ImGui.SameLine(0, 4)
                        end
                    end
                end
                ImGui.Dummy(0, 6)
            end
        end
    end

    ImGui.EndChild()
end

function UI.drawOrganizer()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "INVENTORY CLEANUP & ORGANIZATION ASSISTANT")
    ImGui.SameLine()
    ImGui.TextDisabled("| Stack Consolidation & Weight Analysis")
    ImGui.Separator()
    ImGui.Dummy(0, 6)

    -- Quick Utilities Toolbar
    ImGui.TextDisabled("Quick Bag Controls:")
    ImGui.SameLine()
    if ImGui.Button("Open All Bags##orgOpenAll", 120, 24) then
        state.pendingAction = { type = 'open_all_bags' }
    end
    ImGui.SameLine()
    if ImGui.Button("Close All Bags##orgCloseAll", 120, 24) then
        state.pendingAction = { type = 'close_all_bags' }
    end
    ImGui.SameLine()
    if ImGui.Button("Auto-Inventory Cursor##orgAutoInv", 160, 24) then
        state.pendingAction = { type = 'autoinv' }
    end

    ImGui.Dummy(0, 10)

    -- Section 1: Fragmented Stacks
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "FRAGMENTED STACKS (STACK CONSOLIDATION OPPORTUNITIES)")
    ImGui.TextDisabled("Items below are stackable and have multiple partial stacks scattered across your bags or bank.")
    ImGui.Dummy(0, 2)

    local dups = invLogic.findDuplicateStacks(state.items)
    if #dups == 0 then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "✓ All stackable items are fully consolidated! No fragmented stacks found.")
    else
        if ImGui.BeginTable("DupStacksTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Stacks", ImGuiTableColumnFlags.WidthFixed, 60)
            ImGui.TableSetupColumn("Total Count", ImGuiTableColumnFlags.WidthFixed, 90)
            ImGui.TableSetupColumn("Locations & Partial Counts", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableHeadersRow()

            for _, d in ipairs(dups) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], d.name)
                ImGui.TableSetColumnIndex(1); ImGui.Text(string.format("%d stacks", d.numStacks))
                ImGui.TableSetColumnIndex(2); ImGui.Text(string.format("%d (max %d)", d.totalCount, d.stackSize))
                ImGui.TableSetColumnIndex(3)
                local locParts = {}
                for _, st in ipairs(d.stacks) do
                    table.insert(locParts, string.format("%s (%dx)", st.displayLocation, st.count or 1))
                end
                ImGui.TextDisabled(table.concat(locParts, ", "))
            end
            ImGui.EndTable()
        end
    end

    ImGui.Dummy(0, 14)

    -- Section 2: Heaviest Carried Items
    ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "WEIGHT WATCHER (HEAVIEST ITEMS IN BAGS)")
    ImGui.TextDisabled("Items below contribute the most weight to your character. Useful for Monks or managing encumbrance.")
    ImGui.Dummy(0, 2)

    local heavies = invLogic.findHeaviestItems(state.items, 10)
    if #heavies == 0 then
        ImGui.TextDisabled("No items found in bags.")
    else
        if ImGui.BeginTable("HeavyItemsTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthFixed, 140)
            ImGui.TableSetupColumn("Category", ImGuiTableColumnFlags.WidthFixed, 90)
            ImGui.TableSetupColumn("Total Weight", ImGuiTableColumnFlags.WidthFixed, 90)
            ImGui.TableHeadersRow()

            for _, h in ipairs(heavies) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text(h.name)
                ImGui.TableSetColumnIndex(1); ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], h.location)
                ImGui.TableSetColumnIndex(2); ImGui.TextDisabled(h.category or 'Misc')
                ImGui.TableSetColumnIndex(3); ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format("%.1f lbs", h.totalWeight))
            end
            ImGui.EndTable()
        end
    end
end

function UI.drawSettings()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "SETTINGS & BANK CACHE MANAGEMENT")
    ImGui.Separator()
    ImGui.Dummy(0, 6)

    ImGui.Text("Bank Cache Status:")
    ImGui.SameLine()
    if state.bankLive then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Live banker window open (Automatic real-time sync active)")
    else
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format("Using offline cached bank snapshot (Last updated: %s)", state.bankLastSync))
    end

    ImGui.Dummy(0, 4)
    if ImGui.Button("Force Full Scan Now##forceScan", 160, 26) then
        scanner.scanAll()
        state.statusMsg = "Full scan completed."
    end
    ImGui.SameLine()
    if ImGui.Button("Clear Offline Bank Cache##clearBank", 180, 26) then
        local p = getBankCachePath()
        pcall(os.remove, p)
        scanner.scanAll()
        state.statusMsg = "Bank cache removed."
    end

    ImGui.Dummy(0, 10)
    ImGui.Separator()
    ImGui.Dummy(0, 6)

    state.autoScan = ImGui.Checkbox("Enable Background Auto-Scan##autoScan", state.autoScan)
    if state.autoScan then
        ImGui.PushItemWidth(180)
        local newInterval, intChanged = ImGui.SliderInt("Scan Interval (sec)##scanInt", tonumber(state.autoScanInterval) or 3, 1, 10)
        if intChanged and type(newInterval) == 'number' then
            state.autoScanInterval = newInterval
        end
        ImGui.PopItemWidth()
    end

    if state.statusMsg ~= '' then
        ImGui.Dummy(0, 8)
        ImGui.TextDisabled("Status: " .. state.statusMsg)
    end
end

local function DrawInventoryManagerUI()
    if not openGUI then
        isRunning = false
        return
    end

    pushTheme()

    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(780, 520, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end

    local open, draw = ImGui.Begin("Triune Inventory & Bank Manager##Main", openGUI, windowFlags)
    if not open then
        openGUI = false
        isRunning = false
        ImGui.End()
        popTheme()
        return
    end

    if draw then
        UI.drawHeader()

        if ImGui.BeginTabBar("InvMainTabBar", ImGuiTabBarFlags.None) then
            if ImGui.BeginTabItem("Items List##tabItems") then
                UI.drawItemsTable()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Container Visualizer##tabVis") then
                UI.drawVisualizer()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Organization Assistant##tabOrg") then
                UI.drawOrganizer()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Settings & Cache##tabSet") then
                UI.drawSettings()
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end
    end

    ImGui.End()
    popTheme()
end

-- Initialize ImGui callback
mq.imgui.init('TriuneInventoryManager', DrawInventoryManagerUI)

-- Initial scan
scanner.scanAll()

print(string.format('\ag[Triune Inventory] v%s\ax initialized. Close window or /lua stop triune_inv to exit.', VERSION))

-- Main loop (coroutine thread: yields via mq.delay)
while isRunning do
    -- Process queued action
    local act = state.pendingAction
    if act then
        state.pendingAction = nil
        local actType = tostring(act.type or '')

        if actType == 'inspect' and act.item then
            local it = act.item
            local cmd = it.notifyCmd
            if (it.location == 'INVENTORY' or it.location == 'WORN' or it.location == 'BANK') and cmd and cmd ~= '' then
                pcall(function()
                    mq.cmdf('/nomodkey /itemnotify %s inspect', cmd)
                end)
            end
        elseif actType == 'open_bag' and act.slot then
            local s = tonumber(act.slot)
            if s then
                pcall(function()
                    mq.cmdf('/nomodkey /itemnotify pack%d rightmouseup', s)
                end)
            end
        elseif actType == 'open_all_bags' then
            pcall(function()
                mq.cmd('/keypress open_inv_bags')
            end)
        elseif actType == 'close_all_bags' then
            pcall(function()
                mq.cmd('/keypress close_inv_bags')
            end)
        elseif actType == 'pickup' and act.notifyCmd then
            local cmd = tostring(act.notifyCmd)
            if cmd ~= '' then
                pcall(function()
                    mq.cmdf('/nomodkey /itemnotify %s leftmouseup', cmd)
                end)
            end
        elseif actType == 'move' and act.fromCmd and act.toCmd then
            pcall(function()
                mq.cmdf('/nomodkey /itemnotify %s leftmouseup', act.fromCmd)
            end)
            mq.delay(120)
            pcall(function()
                mq.cmdf('/nomodkey /itemnotify %s leftmouseup', act.toCmd)
            end)
        elseif actType == 'autoinv' then
            pcall(function()
                mq.cmd('/autoinventory')
            end)
        end
        mq.delay(100)
        scanner.scanAll()
    end

    -- Periodic background scan
    if state.autoScan then
        local now = os.time()
        local interval = tonumber(state.autoScanInterval) or 3
        if (now - (tonumber(state.lastScanTime) or 0)) >= interval then
            scanner.scanAll()
        end
    end

    mq.delay(50)
end

print('\ag[Triune Inventory]\ax Closed.')
