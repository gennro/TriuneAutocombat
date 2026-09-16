---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ============================================================================
-- TAC/lua/tac/inventory.lua — Triune Inventory & Bank Manager Plugin
-- ============================================================================
-- In-process replacement for the old standalone triune_inv.lua script.
-- Comprehensive inventory, worn equipment, bank, and shared bank search,
-- container grid visualizer, and organization assistant with offline bank
-- cache persistence (triune_inv_bank_<char>.lua in the MQ config folder).
--
-- The bag-move / stack-combine / sort workflows are sequential and wait on
-- the game between clicks, so they run inside the plugin fiber and use the
-- core's cooperative `delay` (yields to the main loop instead of blocking
-- it). Window visibility is ctrl.show_inv (header button, Settings ->
-- External Tools, /ac inv, and the Window Layout manager flip it); the first
-- scan runs when the window is opened.
--
-- Box Inventories (needs the boxnet plugin): the "Box Inventories" tab shows
-- every other Triune box's bags / bank / worn gear and can move items between
-- characters through the game's trade window.
--   * Pull model: a box asks a peer with `inv:request`; the peer answers with
--     `inv:page` messages (packed items, INV_PAGE_SIZE per page, see
--     invLogic.packItem) so one message never carries a whole bank. Nothing
--     is sent unless someone is looking. `inv:changed` is a broadcast hint
--     that a box's items moved, so open viewers refresh.
--   * Give: `inv:give` asks the box that HOLDS the item to hand it to another
--     character (the giver may be this box, a remote box, and the requester a
--     third one). The giver picks the item up, targets the receiver, opens the
--     trade with /click left target, clicks Trade, and tells the receiver
--     (`inv:trade_accept`) to click its own Trade button; the outcome goes
--     back to the requester as `inv:give_result`. Both boxes must be in the
--     same zone within cfg.tradeRange, checked on the giver.
--   * Remote requests honour boxnet's trust settings (core.boxnet.trusted) and
--     the plugin's own Share / Accept Gives switches.
-- ============================================================================

local plugin = {
    id                 = 'inventory',
    name               = 'Inventory & Bank Manager',
    version            = '2.1.0',
    author             = 'Triune',
    description        = 'Inventory / bank / shared bank search, container visualizer, organization assistant with an offline bank cache, and every other box\'s inventory with item transfers between characters.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = true,
    uses               = {
        gamedb = 'Database lines in item tooltips, Shift+Right-click / list right-click item cards',
        boxnet = 'Box Inventories tab: view other boxes\' items and move items between characters',
    },
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Inv Manager', tooltip = 'Toggles the Inventory & Bank Manager window (inventory plugin).', flag = 'show_inv', desc = 'Inventory / bank search, visualizer & organizer', headerButton = true, order = 110 },
}

-- Populated by refresh() on every entry point; typed so the language server
-- does not treat them as permanently nil.
local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

-- Version shown in the window header (kept in step with plugin.version)
local VERSION = plugin.version

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

-- Cooperative wait (yields the plugin fiber; see pm.delay in triune.lua)
local function delay(ms, cond)
    return core.delay(ms, cond)
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
    str = tostring(str or '')
    if ImGui and ImGui.CalcTextSize then
        local ok, w = pcall(ImGui.CalcTextSize, str)
        if ok and type(w) == 'number' then return w end
    end
    return #str * 7
end

-- Visualizer slot colors (ImU32), computed once instead of per slot per frame.
local SLOT_COL = {
    invBgActive   = col32(0.35, 0.55, 0.85, 0.9),
    invBgHover    = col32(0.20, 0.40, 0.65, 0.8),
    invBg         = col32(0.08, 0.12, 0.18, 0.85),
    invEmptyHover = col32(0.12, 0.16, 0.22, 0.6),
    invEmpty      = col32(0.04, 0.06, 0.09, 0.5),
    invBdrPlace   = col32(1.0, 0.85, 0.30, 1.0),
    invBdrHover   = col32(0.50, 0.70, 1.0, 0.9),
    invBdr        = col32(0.25, 0.40, 0.60, 0.7),
    invBdrEmpty   = col32(0.18, 0.22, 0.28, 0.5),
    invNum        = col32(0.85, 0.90, 0.95, 0.9),
    bankBgActive   = col32(0.55, 0.45, 0.15, 0.9),
    bankBgHover    = col32(0.40, 0.30, 0.10, 0.8),
    bankBg         = col32(0.16, 0.13, 0.07, 0.85),
    bankEmptyHover = col32(0.12, 0.12, 0.14, 0.6),
    bankEmpty      = col32(0.05, 0.05, 0.07, 0.5),
    bankBdrPlace   = col32(1.0, 0.90, 0.40, 1.0),
    bankBdrHover   = col32(0.90, 0.75, 0.30, 0.9),
    bankBdr        = col32(0.60, 0.45, 0.20, 0.7),
    bankBdrEmpty   = col32(0.20, 0.18, 0.15, 0.5),
    bankNum        = col32(0.95, 0.90, 0.80, 0.9),
    numEmpty       = col32(0.35, 0.40, 0.45, 0.5),
    badgeBg        = col32(0, 0, 0, 0.75),
    badgeText      = col32(1.0, 0.95, 0.5, 1.0),
}

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
    combineAllActive = false,
    combineMoveCount = 0,
    combineNoProgress = 0,
    combineLastKey = nil,
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
    -- Organizer tab results (duplicate stacks / heaviest items), recomputed
    -- only when the item data changes (dataGen) or the bank goes live/cached.
    orgCache = { gen = -1, bankLive = nil, dups = {}, heavies = {}, canCombineAny = false },
    dataGen = 0,          -- bumped whenever state.items / containers change
    lastScanTime = 0,
    autoScan = false,
    autoScanInterval = 15, -- seconds (slider range 5..60)
    -- Box Inventories (boxnet). Settings live in cfg below; this is runtime.
    net = {
        peers = {},          -- [lowerName] = peer snapshot record (see netPeerRecord)
        selected = 'ALL',    -- 'ALL' | lowerName of the box whose items are shown
        view = 'list',       -- 'list' | 'grid'
        search = '',
        loc = 'ALL',         -- ALL | INVENTORY | BANK | WORN
        pendingRequests = {},-- names that asked for our snapshot; served on the tick
        gives = {},          -- queued give jobs on THIS box (we hold the item)
        activeGive = nil,    -- the job being executed
        acceptTrades = {},   -- [lowerName] = { until = sec, item = name }: click Trade for this giver
        log = {},            -- newest first: { time, text, level }
        givePopup = nil,     -- item the Give popup is open for
        subGen = -1,         -- boxnet generation the subscriptions belong to
        unsubs = {},
        lastAutoRefresh = 0,
        served = {},         -- [lowerName] = true once a box has asked us (gets inv:changed hints)
        lastChangedGen = -1, -- contentGen last announced with inv:changed
        tableCache = { key = '', rows = {} },
        status = '',
    },
}

-- Persisted settings (onSaveSettings / onLoadSettings).
local cfg = {
    share          = true,  -- answer other boxes' inventory requests
    acceptGives    = true,  -- execute give requests from other boxes (also gated by boxnet trust)
    tradeRange     = 15,    -- max distance to the receiver for a trade (game refuses beyond ~15)
    autoRefreshSec = 30,    -- re-request open box snapshots this often (0 = manual)
    announce       = true,  -- print transfers to chat
}

-- Box Inventories helpers the item list uses; defined in that section below.
local boxnet, openGivePopup, drawGivePopup

local INV_PAGE_SIZE      = 80    -- packed items per inv:page message
local NET_REQUEST_MIN_SEC = 2.0  -- never ask the same box more often than this
local NET_SNAPSHOT_MAX_AGE = 3   -- rescan before serving when our data is older (seconds)
local NET_LOG_MAX        = 40
local TRADE_ACCEPT_SEC   = 25    -- receiver waits this long for the giver's trade window

-- Marks the filtered table and organizer caches stale.
local function markDirty()
    state.tableCache.dirty = true
    state.dataGen = (state.dataGen or 0) + 1
end


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

function invLogic.formatAugs(item)
    if not item or type(item.augs) ~= 'table' or #item.augs == 0 then
        return ''
    end
    local names = {}
    for _, a in ipairs(item.augs) do
        if type(a) == 'table' and a.name and a.name ~= '' then
            table.insert(names, a.name)
        elseif type(a) == 'string' and a ~= '' then
            table.insert(names, a)
        end
    end
    return table.concat(names, ', ')
end

-- Display strings the item list shows per row, computed once per item
-- (at scan time / cache load) instead of per visible row per frame.
function invLogic.decorateItem(it)
    if not it then return it end
    it.augText = invLogic.formatAugs(it)
    it.valueText = invLogic.formatMoney(it.value or 0)
    it.weightText = string.format('%.1f', tonumber(it.weight) or 0)
    if it.stackable then
        it.qtyText = string.format('%d/%d', it.count or 1, it.stackSize or 1)
    else
        it.qtyText = nil
    end
    return it
end

function invLogic.parseAugs(value)
    if type(value) == 'table' then
        return value
    end
    if type(value) ~= 'string' or value == '' then
        return {}
    end
    local list = {}
    local i = 0
    for name in string.gmatch(value, '[^|]+') do
        i = i + 1
        table.insert(list, { slot = i, name = name })
    end
    return list
end

function invLogic.planBagAlphaSort(bag, packKind, mode)
    if not bag or (bag.capacity or 0) < 2 then return {} end
    local function cmd(sub)
        if packKind == 'bank' then
            return string.format('in bank%d %d', bag.slot, sub)
        end
        return string.format('in pack%d %d', bag.slot, sub)
    end

    local layout = {}
    local items = {}
    for s = 1, bag.capacity do
        local it = bag.slots and bag.slots[s]
        if it then
            layout[s] = it
            table.insert(items, it)
        else
            layout[s] = false
        end
    end
    if #items < 2 then return {} end

    table.sort(items, function(a, b)
        if mode == 'type' then
            local ta = string.lower(tostring(a.type or a.category or ''))
            local tb = string.lower(tostring(b.type or b.category or ''))
            if ta ~= tb then return ta < tb end
        end
        local na = string.lower(tostring(a.name or ''))
        local nb = string.lower(tostring(b.name or ''))
        if na == nb then
            return (tonumber(a.subSlot) or 0) < (tonumber(b.subSlot) or 0)
        end
        return na < nb
    end)

    local moves = {}
    for dest = 1, #items do
        local wanted = items[dest]
        local src = nil
        for s = 1, bag.capacity do
            if layout[s] == wanted then
                src = s
                break
            end
        end
        if src and src ~= dest then
            local destOccupied = layout[dest] and true or false
            table.insert(moves, {
                fromCmd = cmd(src),
                toCmd = cmd(dest),
                completeSwap = destOccupied,
                fromId = tonumber(wanted.id) or nil,
                destId = destOccupied and tonumber(layout[dest].id) or nil,
            })
            layout[src], layout[dest] = layout[dest], layout[src]
            if not destOccupied then
                layout[src] = false
            end
        end
    end
    return moves
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
        local hayAugs = ''
        if type(item.augs) == 'table' then
            local parts = {}
            for _, a in ipairs(item.augs) do
                if type(a) == 'table' then
                    table.insert(parts, tostring(a.name or ''))
                elseif type(a) == 'string' then
                    table.insert(parts, a)
                end
            end
            hayAugs = string.lower(table.concat(parts, ', '))
        end

        if not (string.find(hayName, needle, 1, true) or
                string.find(hayLoc, needle, 1, true) or
                string.find(hayType, needle, 1, true) or
                string.find(hayClicky, needle, 1, true) or
                string.find(hayCat, needle, 1, true) or
                string.find(hayAugs, needle, 1, true)) then
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

-- allowBank: pass false while the bank window is closed so cached BANK stacks
-- (which cannot be clicked) are never selected. Defaults to true for callers
-- that do not know about the bank state.
function invLogic.findNextCombineMove(item, allowBank)
    if not item or not item.stacks or #item.stacks < 2 then return nil end
    if allowBank == nil then allowBank = true end
    local stacks = {}
    for _, s in ipairs(item.stacks) do
        if allowBank or s.location ~= 'BANK' then
            table.insert(stacks, s)
        end
    end
    if #stacks < 2 then return nil end
    table.sort(stacks, function(a, b) return (a.count or 1) > (b.count or 1) end)
    local stackSize = item.stackSize or 1
    for i = 2, #stacks do
        local src = stacks[i]
        local srcCount = src.count or 1
        local srcCmd = tostring(src.notifyCmd or '')
        if srcCount < stackSize and srcCmd ~= '' then
            for j = 1, i - 1 do
                local dst = stacks[j]
                local dstCount = dst.count or 1
                local dstCmd = tostring(dst.notifyCmd or '')
                if dstCount < stackSize
                    and dstCmd ~= ''
                    and dstCmd ~= srcCmd
                    and dst.location == src.location then
                    return { fromCmd = srcCmd, toCmd = dstCmd, from = src, to = dst }
                end
            end
        end
    end
    return nil
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

-- ----------------------------------------------------------------------------
-- Location strings: the label the list shows and the /itemnotify address of a
-- slot, from its type / bag / sub-slot. Used by the scanner and to rebuild
-- items from a peer's packed snapshot.
-- ----------------------------------------------------------------------------
function invLogic.describeLocation(locType, slotIdx, subIdx)
    slotIdx = tonumber(slotIdx) or 0
    subIdx = tonumber(subIdx)
    if subIdx and subIdx <= 0 then subIdx = nil end
    if locType == 'WORN' then
        return string.format('Worn [%s]', WORN_SLOTS[slotIdx] or tostring(slotIdx)), string.format('%d', slotIdx)
    elseif locType == 'INVENTORY' then
        if subIdx then
            return string.format('Bag %d [Slot %d]', slotIdx, subIdx), string.format('in pack%d %d', slotIdx, subIdx)
        end
        return string.format('Pack Slot %d', slotIdx), string.format('pack%d', slotIdx)
    elseif locType == 'BANK' then
        if subIdx then
            return string.format('Bank %d [Slot %d]', slotIdx, subIdx), string.format('in bank%d %d', slotIdx, subIdx)
        end
        return string.format('Bank Slot %d', slotIdx), string.format('bank%d', slotIdx)
    elseif locType == 'SHAREDBANK' then
        if subIdx then
            return string.format('SharedBank %d [Slot %d]', slotIdx, subIdx), string.format('in sharedbank%d %d', slotIdx, subIdx)
        end
        return string.format('SharedBank Slot %d', slotIdx), string.format('sharedbank%d', slotIdx)
    elseif locType == 'CURSOR' then
        return 'Cursor', ''
    end
    return tostring(locType or ''), ''
end

-- ----------------------------------------------------------------------------
-- Box snapshot codec. An item travels as a positional array (about half the
-- bytes of a keyed table once serialized) in this order:
--   1 id, 2 icon, 3 name, 4 location code, 5 slotIndex, 6 subSlot (0 = none),
--   7 count, 8 stackSize, 9 weight, 10 value, 11 type, 12 category, 13 flags,
--   14 clicky spell, 15 aug names
-- flags is a bit set: 1 lore, 2 nodrop, 4 tradeskill, 8 stackable, 16 magic,
-- 32 norent, 64 attunable.
-- ----------------------------------------------------------------------------
local LOC_CODE = { INVENTORY = 'I', BANK = 'B', SHAREDBANK = 'S', WORN = 'W', CURSOR = 'C' }
local CODE_LOC = { I = 'INVENTORY', B = 'BANK', S = 'SHAREDBANK', W = 'WORN', C = 'CURSOR' }
local FLAG = { lore = 1, nodrop = 2, tradeskill = 4, stackable = 8, magic = 16, norent = 32, attunable = 64 }
invLogic.FLAG = FLAG

local function hasFlag(bits, bit)
    return (math.floor((tonumber(bits) or 0) / bit) % 2) == 1
end

function invLogic.packItem(it)
    if not it then return nil end
    local flags = 0
    for name, bit in pairs(FLAG) do
        if it[name] then flags = flags + bit end
    end
    return {
        tonumber(it.id) or 0,
        tonumber(it.icon) or 0,
        tostring(it.name or ''),
        LOC_CODE[it.location] or 'I',
        tonumber(it.slotIndex) or 0,
        tonumber(it.subSlot) or 0,
        tonumber(it.count) or 1,
        tonumber(it.stackSize) or 1,
        tonumber(it.weight) or 0,
        tonumber(it.value) or 0,
        tostring(it.type or ''),
        tostring(it.category or 'Misc'),
        flags,
        tostring(it.clicky or ''),
        (invLogic.formatAugs(it):gsub(', ', '|')),   -- parseAugs splits on '|'
    }
end

-- The inverse: a plain item table in the shape the list / tooltip / filters
-- expect, tagged with the owning character.
function invLogic.unpackItem(p, owner)
    if type(p) ~= 'table' then return nil end
    local loc = CODE_LOC[p[4]] or 'INVENTORY'
    local slot = tonumber(p[5]) or 0
    local sub = tonumber(p[6]) or 0
    if sub <= 0 then sub = nil end
    local flags = tonumber(p[13]) or 0
    local disp, cmd = invLogic.describeLocation(loc, slot, sub)
    local it = {
        id = tonumber(p[1]) or 0,
        icon = tonumber(p[2]) or 0,
        name = tostring(p[3] or ''),
        location = loc,
        slotIndex = slot,
        subSlot = sub,
        wornSlot = loc == 'WORN' and (WORN_SLOTS[slot] or tostring(slot)) or nil,
        displayLocation = disp,
        notifyCmd = cmd,
        count = tonumber(p[7]) or 1,
        stackSize = tonumber(p[8]) or 1,
        weight = tonumber(p[9]) or 0,
        value = tonumber(p[10]) or 0,
        type = tostring(p[11] or ''),
        category = tostring(p[12] or 'Misc'),
        clicky = (p[14] ~= nil and p[14] ~= '') and tostring(p[14]) or nil,
        augs = invLogic.parseAugs(p[15]),
        owner = owner,
        remote = true,
    }
    for name, bit in pairs(FLAG) do it[name] = hasFlag(flags, bit) end
    return invLogic.decorateItem(it)
end

-- Splits a list into pages of `size`; page tables are new arrays.
function invLogic.paginate(list, size)
    size = math.max(1, tonumber(size) or INV_PAGE_SIZE)
    local pages = {}
    local n = #(list or {})
    if n == 0 then return { {} } end
    for i = 1, n, size do
        local page = {}
        for j = i, math.min(n, i + size - 1) do page[#page + 1] = list[j] end
        pages[#pages + 1] = page
    end
    return pages
end

-- The snapshot a box sends about itself: meta (counts, containers without
-- their slot maps, bank status) and packed items. `containers` is only the
-- bag list (slot, name, capacity, used) - the viewer rebuilds slot maps from
-- the items' slot / subSlot.
function invLogic.buildSnapshot(st, scanAt)
    local function bagList(list)
        local out = {}
        for _, c in ipairs(list or {}) do
            out[#out + 1] = { slot = c.slot, name = tostring(c.name or ''), capacity = tonumber(c.capacity) or 0, used = tonumber(c.used) or 0 }
        end
        return out
    end
    local items = {}
    for _, it in ipairs(st.items or {}) do items[#items + 1] = invLogic.packItem(it) end
    local counts = {}
    for k, v in pairs(st.counts or {}) do
        if type(v) == 'number' then counts[k] = v end
    end
    return {
        meta = {
            counts = counts,
            inventory = bagList(st.containers and st.containers.inventory),
            bank = bagList(st.containers and st.containers.bank),
            sharedBank = bagList(st.containers and st.containers.sharedBank),
            bankLive = st.bankLive == true,
            bankSync = tostring(st.bankLastSync or ''),
            scanAt = tonumber(scanAt) or 0,
        },
        items = items,
    }
end

-- Rebuilds a peer's bag lists (with slot maps) from its meta + unpacked items.
function invLogic.rebuildContainers(meta, items)
    local function withSlots(list, loc)
        local out = {}
        local bySlot = {}
        for _, c in ipairs(list or {}) do
            local bag = { slot = c.slot, name = c.name, capacity = c.capacity or 0, used = c.used or 0, slots = {} }
            out[#out + 1] = bag
            bySlot[c.slot] = bag
        end
        for _, it in ipairs(items or {}) do
            if it.location == loc then
                local bag = bySlot[it.slotIndex]
                if bag then
                    if it.subSlot then
                        bag.slots[it.subSlot] = it
                    elseif (bag.capacity or 0) <= 1 then
                        bag.slots[1] = it
                    end
                end
            end
        end
        table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
        return out
    end
    meta = meta or {}
    return {
        inventory = withSlots(meta.inventory, 'INVENTORY'),
        bank = withSlots(meta.bank, 'BANK'),
        sharedBank = withSlots(meta.sharedBank, 'SHAREDBANK'),
    }
end

-- Applies one inv:page to a peer record. A page from a different snapshot
-- generation than the partial one restarts the assembly. Returns true when
-- the snapshot is complete (rec.items / containers / meta / at are then set).
function invLogic.mergePage(rec, data, nowSecs)
    if type(rec) ~= 'table' or type(data) ~= 'table' then return false end
    local gen = tonumber(data.gen) or 0
    local page = tonumber(data.page) or 1
    local pages = math.max(1, tonumber(data.pages) or 1)
    local part = rec.partial
    if not part or part.gen ~= gen or part.pages ~= pages then
        part = { gen = gen, pages = pages, got = 0, seen = {}, items = {}, meta = nil }
        rec.partial = part
    end
    if part.seen[page] then return false end
    part.seen[page] = true
    part.got = part.got + 1
    if type(data.meta) == 'table' then part.meta = data.meta end
    part.items[page] = {}
    for _, p in ipairs(data.items or {}) do
        local it = invLogic.unpackItem(p, rec.name)
        if it then part.items[page][#part.items[page] + 1] = it end
    end
    if part.got < pages then return false end
    local items = {}
    for i = 1, pages do
        for _, it in ipairs(part.items[i] or {}) do items[#items + 1] = it end
    end
    rec.items = items
    rec.meta = part.meta or {}
    rec.containers = invLogic.rebuildContainers(rec.meta, items)
    rec.gen = gen
    rec.at = tonumber(nowSecs) or 0
    rec.stale = false
    rec.pendingSince = nil
    rec.refused = nil
    rec.partial = nil
    return true
end

-- A string that changes when any item, stack count or slot changes: what
-- the Box Inventories "changed" hint and the snapshot generation key off, so
-- a periodic rescan that finds everything in place announces nothing.
function invLogic.contentSignature(items)
    local parts = {}
    for _, it in ipairs(items or {}) do
        parts[#parts + 1] = string.format('%s:%s:%s', tostring(it.id or 0), tostring(it.count or 1), tostring(it.notifyCmd or it.location or ''))
    end
    table.sort(parts)
    return table.concat(parts, ',')
end

-- 3D distance between two { x, y, z } tables (nil when either is missing).
function invLogic.dist3(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return nil end
    local ax, ay, az = tonumber(a.x), tonumber(a.y), tonumber(a.z) or 0
    local bx, by, bz = tonumber(b.x), tonumber(b.y), tonumber(b.z) or 0
    if not (ax and ay and bx and by) then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Filters + sorts a list of (remote or local) items for the Box tab: search
-- text, location filter, owner ('ALL' or a lowercase name). Rows sort by
-- owner, then name, then location.
function invLogic.filterBoxItems(items, search, locFilter, owner)
    local out = {}
    local needle = search and search ~= '' and string.lower(search) or nil
    for _, it in ipairs(items or {}) do
        local ok = true
        if owner and owner ~= 'ALL' and string.lower(tostring(it.owner or '')) ~= owner then ok = false end
        if ok and locFilter and locFilter ~= 'ALL' then
            local loc = string.upper(it.location or '')
            if locFilter == 'BANK' then
                if loc ~= 'BANK' and loc ~= 'SHAREDBANK' then ok = false end
            elseif loc ~= locFilter then
                ok = false
            end
        end
        if ok and needle then
            ok = invLogic.matchesFilter(it, search, 'ALL', 'ALL', nil)
        end
        if ok then out[#out + 1] = it end
    end
    table.sort(out, function(a, b)
        local oa, ob = string.lower(tostring(a.owner or '')), string.lower(tostring(b.owner or ''))
        if oa ~= ob then return oa < ob end
        local na, nb = string.lower(a.name or ''), string.lower(b.name or '')
        if na ~= nb then return na < nb end
        return (a.notifyCmd or '') < (b.notifyCmd or '')
    end)
    return out
end

-- Why an item cannot be given (nil when it can). `bankLive` is the giver's.
function invLogic.giveBlocker(it)
    if not it then return 'no item' end
    if it.nodrop then return 'NO TRADE item' end
    if it.location == 'BANK' or it.location == 'SHAREDBANK' then return 'in the bank - move it to a bag first' end
    if it.location == 'CURSOR' then return 'on the cursor' end
    if (tonumber(it.id) or 0) <= 0 then return 'unknown item id' end
    return nil
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

function scanner.saveBankCache(bankItems, bankContainers, force, sharedContainers)
    inMemoryBankCache = {
        syncTime = os.date('%Y-%m-%d %H:%M:%S'),
        items = bankItems,
        containers = bankContainers,
        sharedContainers = sharedContainers or {},
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
        local augStr = invLogic.formatAugs(it):gsub(', ', '|')
        f:write(string.format('    { id=%d, icon=%d, name=%q, location=%q, slotIndex=%d, subSlot=%s, displayLocation=%q, notifyCmd=%q, count=%d, stackable=%s, stackSize=%d, weight=%.2f, value=%d, type=%q, category=%q, lore=%s, nodrop=%s, tradeskill=%s, clicky=%q, ac=%d, hp=%d, mana=%d, damage=%d, delay=%d, augs=%q },\n',
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
            it.delay or 0,
            augStr
        ))
    end
    f:write('  },\n  containers = {\n')
    for _, c in ipairs(bankContainers) do
        f:write(string.format('    { slot=%d, name=%q, capacity=%d, used=%d },\n',
            c.slot, c.name or '', c.capacity or 0, c.used or 0))
    end
    f:write('  },\n  sharedContainers = {\n')
    for _, c in ipairs(sharedContainers or {}) do
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
                it.augs = invLogic.parseAugs(it.augs)
                invLogic.decorateItem(it)
                if it.id and it.id > 0 and not state.itemDefs[it.id] then
                    state.itemDefs[it.id] = it
                end
            end
        end
        return data
    end
    return nil
end

-- Item instances share their static definition: the returned table holds only
-- the per-instance fields (location, slot, count, augs, display strings) and
-- resolves everything else (stats, flags, name, icon, ...) through
-- `__index = def`, so the ~90 definition fields are not copied per stack.
local ITEM_INSTANCE_MT_CACHE = setmetatable({}, { __mode = 'k' })
local function instanceMeta(def)
    local mt = ITEM_INSTANCE_MT_CACHE[def]
    if not mt then
        mt = { __index = def }
        ITEM_INSTANCE_MT_CACHE[def] = mt
    end
    return mt
end

-- `knownId` lets scanAll pass the id it already read for the presence check.
local function extractItemData(itemObj, locType, slotIdx, subIdx, containerName, notifyPrefix, knownId)
    if not itemObj then return nil end
    local itemId = tonumber(knownId) or 0
    if itemId <= 0 then
        local okId = pcall(function()
            if not itemObj() then return end
            itemId = tonumber(itemObj.ID()) or 0
        end)
        if not okId or itemId <= 0 then return nil end
    end

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
        local acVal, hpVal, manaVal, dmgVal, dlyVal, augTypeVal = 0, 0, 0, 0, 0, 0

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
            augTypeVal = tonumber(itemObj.AugType()) or 0
        end)

        -- Collect extended stats in a second pcall to avoid aborting on missing members
        local ext = {}
        pcall(function()
            ext.endurance = tonumber(itemObj.Endurance()) or 0
            ext.norent = itemObj.NoRent() or false
            ext.magic = itemObj.Magic() or false
            ext.attunable = itemObj.Attunable() or false
            ext.range = tonumber(itemObj.Range()) or 0
            ext.str = tonumber(itemObj.STR()) or 0
            ext.sta = tonumber(itemObj.STA()) or 0
            ext.agi = tonumber(itemObj.AGI()) or 0
            ext.dex = tonumber(itemObj.DEX()) or 0
            ext.wis = tonumber(itemObj.WIS()) or 0
            ext.int = tonumber(itemObj.INT()) or 0
            ext.cha = tonumber(itemObj.CHA()) or 0
            ext.heroicStr = tonumber(itemObj.HeroicSTR()) or 0
            ext.heroicSta = tonumber(itemObj.HeroicSTA()) or 0
            ext.heroicAgi = tonumber(itemObj.HeroicAGI()) or 0
            ext.heroicDex = tonumber(itemObj.HeroicDEX()) or 0
            ext.heroicWis = tonumber(itemObj.HeroicWIS()) or 0
            ext.heroicInt = tonumber(itemObj.HeroicINT()) or 0
            ext.heroicCha = tonumber(itemObj.HeroicCHA()) or 0
            ext.svMagic = tonumber(itemObj.svMagic()) or 0
            ext.svFire = tonumber(itemObj.svFire()) or 0
            ext.svCold = tonumber(itemObj.svCold()) or 0
            ext.svDisease = tonumber(itemObj.svDisease()) or 0
            ext.svPoison = tonumber(itemObj.svPoison()) or 0
            ext.svCorruption = tonumber(itemObj.svCorruption()) or 0
            ext.hpRegen = tonumber(itemObj.HPRegen()) or 0
            ext.manaRegen = tonumber(itemObj.ManaRegen()) or 0
            ext.endRegen = tonumber(itemObj.EnduranceRegen()) or 0
            ext.attack = tonumber(itemObj.Attack()) or 0
            ext.haste = tonumber(itemObj.Haste()) or 0
            ext.accuracy = tonumber(itemObj.Accuracy()) or 0
            ext.avoidance = tonumber(itemObj.Avoidance()) or 0
            ext.combatEffects = tonumber(itemObj.CombatEffects()) or 0
            ext.shielding = tonumber(itemObj.Shielding()) or 0
            ext.spellShield = tonumber(itemObj.SpellShield()) or 0
            ext.strikeThrough = tonumber(itemObj.StrikeThrough()) or 0
            ext.stunResist = tonumber(itemObj.StunResist()) or 0
            ext.damShield = tonumber(itemObj.DamShield()) or 0
            ext.dotShielding = tonumber(itemObj.DoTShielding()) or 0
            ext.dsm = tonumber(itemObj.DamageShieldMitigation()) or 0
            ext.healAmount = tonumber(itemObj.HealAmount()) or 0
            ext.spellDamage = tonumber(itemObj.SpellDamage()) or 0
            ext.clairvoyance = tonumber(itemObj.Clairvoyance()) or 0
            ext.purity = tonumber(itemObj.Purity()) or 0
            ext.requiredLevel = tonumber(itemObj.RequiredLevel()) or 0
            ext.instrumentMod = tonumber(itemObj.InstrumentMod()) or 0
            ext.tribute = tonumber(itemObj.Tribute()) or 0
            local dbt = itemObj.DMGBonusType()
            if dbt and dbt ~= '' and dbt ~= 'None' then ext.dmgBonusType = tostring(dbt) end
            local onWorn = itemObj.Worn
            if onWorn and type(onWorn) == 'function' then onWorn = onWorn() end
            if onWorn then
                pcall(function()
                    local sp = onWorn.Spell
                    if sp and sp() then
                        local sn = sp.Name()
                        if sn and sn ~= '' then ext.wornEffect = tostring(sn) end
                    end
                end)
            end
            local onFocus = itemObj.Focus
            if onFocus and type(onFocus) == 'function' then onFocus = onFocus() end
            if onFocus then
                pcall(function()
                    local sp = onFocus.Spell
                    if sp and sp() then
                        local sn = sp.Name()
                        if sn and sn ~= '' then ext.focusEffect = tostring(sn) end
                    end
                end)
            end
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
            augType = augTypeVal,
            -- Extended stats from second pcall
            endurance = ext.endurance or 0,
            norent = ext.norent or false,
            magic = ext.magic or false,
            attunable = ext.attunable or false,
            range = ext.range or 0,
            str = ext.str or 0, sta = ext.sta or 0, agi = ext.agi or 0, dex = ext.dex or 0,
            wis = ext.wis or 0, int = ext.int or 0, cha = ext.cha or 0,
            heroicStr = ext.heroicStr or 0, heroicSta = ext.heroicSta or 0,
            heroicAgi = ext.heroicAgi or 0, heroicDex = ext.heroicDex or 0,
            heroicWis = ext.heroicWis or 0, heroicInt = ext.heroicInt or 0, heroicCha = ext.heroicCha or 0,
            svMagic = ext.svMagic or 0, svFire = ext.svFire or 0, svCold = ext.svCold or 0,
            svDisease = ext.svDisease or 0, svPoison = ext.svPoison or 0, svCorruption = ext.svCorruption or 0,
            hpRegen = ext.hpRegen or 0, manaRegen = ext.manaRegen or 0, endRegen = ext.endRegen or 0,
            attack = ext.attack or 0, haste = ext.haste or 0,
            accuracy = ext.accuracy or 0, avoidance = ext.avoidance or 0,
            combatEffects = ext.combatEffects or 0, shielding = ext.shielding or 0,
            spellShield = ext.spellShield or 0, strikeThrough = ext.strikeThrough or 0,
            stunResist = ext.stunResist or 0, damShield = ext.damShield or 0,
            dotShielding = ext.dotShielding or 0, dsm = ext.dsm or 0,
            healAmount = ext.healAmount or 0, spellDamage = ext.spellDamage or 0,
            clairvoyance = ext.clairvoyance or 0, purity = ext.purity or 0,
            requiredLevel = ext.requiredLevel or 0,
            instrumentMod = ext.instrumentMod or 0, tribute = ext.tribute or 0,
            dmgBonusType = ext.dmgBonusType,
            wornEffect = ext.wornEffect,
            focusEffect = ext.focusEffect,
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

    local dispLoc, notifyCmd = invLogic.describeLocation(locType, slotIdx, subIdx)

    -- Augment slots: only walked when the item can actually hold augments
    -- (Augs() > 0 on the accessor; items with no aug slots skip the 6-slot loop).
    local augs = {}
    local augSlots = 0
    pcall(function()
        local a = itemObj.Augs
        if a then
            local n = (type(a) == 'function' or type(a) == 'userdata') and a() or a
            augSlots = tonumber(n) or 0
        end
    end)
    if augSlots > 0 then
        pcall(function()
            for i = 1, math.min(6, augSlots) do
                local slot = itemObj.AugSlot(i)
                if slot then
                    local n = nil
                    pcall(function()
                        if slot.Empty and slot.Empty() then return end
                        n = slot.Name()
                    end)
                    if (not n or n == '') and slot.Item then
                        pcall(function()
                            local augItem = slot.Item
                            if augItem and augItem() then
                                n = augItem.Name()
                            end
                        end)
                    end
                    if n and n ~= '' then
                        table.insert(augs, { slot = i, name = tostring(n) })
                    end
                end
            end
        end)
    end

    local it = setmetatable({
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
        augs = augs,
    }, instanceMeta(def))
    return invLogic.decorateItem(it)
end

-- opts.yield: true when called from the plugin fiber (onTick); the scan then
-- yields back to the main loop (core.delay) whenever one time slice of
-- container reads exceeds SCAN_SLICE_SEC so a big bank never stalls a tick.
local SCAN_SLICE_SEC = 0.02
function scanner.scanAll(opts)
    local canYield = (type(opts) == 'table' and opts.yield == true) and plugin.hasThread and core and core.delay
    local sliceStart = os.clock()
    local function breathe()
        if not canYield then return end
        if (os.clock() - sliceStart) >= SCAN_SLICE_SEC then
            delay(1)
            sliceStart = os.clock()
        end
    end

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
        local wornId = (ok and itemObj and itemObj() and itemObj.ID()) or 0
        if wornId > 0 then
            local it = extractItemData(itemObj, 'WORN', slot, nil, 'Worn', nil, wornId)
            if it then
                table.insert(scannedItems, it)
                wornCount = wornCount + 1
            end
        end
    end

    breathe()

    -- 2. Scan Inventory Bags (pack1..pack10, slots 23..32)
    local invCount = 0
    for p = 1, 10 do
        local ok, packObj = pcall(function() return mq.TLO.Me.Inventory('pack' .. p) end)
        local packId = (ok and packObj and packObj() and packObj.ID()) or 0
        if packId > 0 then
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
                    local subId = (okSub and subItem and subItem() and subItem.ID()) or 0
                    if subId > 0 then
                        local it = extractItemData(subItem, 'INVENTORY', p, s, bagName, 'pack' .. p, subId)
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
                local it = extractItemData(packObj, 'INVENTORY', p, nil, 'Pack Slot', 'pack' .. p, packId)
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
        breathe()
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
            local bBagId = (ok and bBag and bBag() and bBag.ID()) or 0
            if bBagId > 0 then
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
                        local subId = (okSub and subItem and subItem() and subItem.ID()) or 0
                        if subId > 0 then
                            local it = extractItemData(subItem, 'BANK', b, s, bagName, 'bank' .. b, subId)
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
                    local it = extractItemData(bBag, 'BANK', b, nil, 'Bank Slot', 'bank' .. b, bBagId)
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
            breathe()
        end

        -- Shared Bank (containers shown under the bank in the visualizer)
        for sb = 1, 4 do
            local ok, sbBag = pcall(function() return mq.TLO.Me.SharedBank(sb) end)
            local sbBagId = (ok and sbBag and sbBag() and sbBag.ID()) or 0
            if sbBagId > 0 then
                local bagCap = 0
                pcall(function() bagCap = sbBag.Container() or 0 end)
                local bagName = 'Shared Bank Container'
                pcall(function() bagName = tostring(sbBag.Name() or 'Shared Bank Container') end)

                if bagCap > 0 then
                    local usedInBag = 0
                    local bagSlots = {}
                    for s = 1, bagCap do
                        local okSub, subItem = pcall(function() return sbBag.Item(s) end)
                        local subId = (okSub and subItem and subItem() and subItem.ID()) or 0
                        if subId > 0 then
                            local it = extractItemData(subItem, 'SHAREDBANK', sb, s, bagName, 'sharedbank' .. sb, subId)
                            if it then
                                table.insert(liveBankItems, it)
                                bankItemCount = bankItemCount + 1
                                usedInBag = usedInBag + 1
                                bagSlots[s] = it
                            end
                        end
                    end
                    table.insert(sharedContainers, { slot = sb, name = bagName, capacity = bagCap, used = usedInBag, slots = bagSlots })
                else
                    local it = extractItemData(sbBag, 'SHAREDBANK', sb, nil, 'Shared Bank Slot', 'sharedbank' .. sb, sbBagId)
                    if it then
                        table.insert(liveBankItems, it)
                        bankItemCount = bankItemCount + 1
                    end
                    table.insert(sharedContainers, { slot = sb, name = it and it.name or 'Item', capacity = 1, used = 1, slots = { [1] = it } })
                end
            end
            breathe()
        end

        -- Persist live bank scan
        scanner.saveBankCache(liveBankItems, bankContainers, false, sharedContainers)
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
                local bankSlotsByBag, sharedSlotsByBag = {}, {}
                if cached.items then
                    for _, it in ipairs(cached.items) do
                        local byBag = (it.location == 'BANK' and bankSlotsByBag) or (it.location == 'SHAREDBANK' and sharedSlotsByBag) or nil
                        if byBag and it.slotIndex then
                            if not byBag[it.slotIndex] then byBag[it.slotIndex] = {} end
                            byBag[it.slotIndex][it.subSlot or 1] = it
                        end
                    end
                end
                for _, c in ipairs(cached.containers) do
                    c.slots = bankSlotsByBag[c.slot] or {}
                    table.insert(bankContainers, c)
                    totalBankCapacity = totalBankCapacity + (c.capacity or 0)
                    totalBankUsed = totalBankUsed + (c.used or 0)
                end
                for _, c in ipairs(cached.sharedContainers or {}) do
                    c.slots = sharedSlotsByBag[c.slot] or {}
                    table.insert(sharedContainers, c)
                end
            end
        end
    end

    -- 4. Scan Cursor
    local cursorCount = 0
    local okCur, curItem = pcall(function() return mq.TLO.Cursor end)
    local curId = (okCur and curItem and curItem() and curItem.ID()) or 0
    if curId > 0 then
        local it = extractItemData(curItem, 'CURSOR', 0, nil, 'Cursor', nil, curId)
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
    local sig = invLogic.contentSignature(scannedItems)
    if sig ~= state.contentSig then
        state.contentSig = sig
        state.contentGen = (state.contentGen or 0) + 1
    end
    markDirty()
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
    ImGui.Dummy(0, core.px(2))

    -- Stats summary row
    local freeInv = state.counts.freeInvSlots
    local invCol = freeInv > 10 and GOOD or (freeInv > 0 and WARN or ERR)
    ImGui.TextDisabled("Bags Free:")
    ImGui.SameLine()
    ImGui.TextColored(invCol[1], invCol[2], invCol[3], invCol[4], string.format("%d / %d", freeInv, state.counts.totalInvSlots))

    ImGui.SameLine(0, core.px(16))
    ImGui.TextDisabled("Bank Free:")
    ImGui.SameLine()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("%d / %d", state.counts.freeBankSlots, state.counts.totalBankSlots))

    ImGui.SameLine(0, core.px(16))
    local wtCol = (state.counts.maxWeight > 0 and state.counts.invWeight > state.counts.maxWeight) and ERR or GOOD
    ImGui.TextDisabled("Weight:")
    ImGui.SameLine()
    ImGui.TextColored(wtCol[1], wtCol[2], wtCol[3], wtCol[4], string.format("%d / %d lbs", state.counts.invWeight, state.counts.maxWeight))

    ImGui.SameLine(0, core.px(16))
    ImGui.TextDisabled("Cash:")
    ImGui.SameLine()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format("%dp (Bank: %dp)", state.counts.invPlat, state.counts.bankPlat))

    if state.counts.cursor > 0 then
        ImGui.SameLine(0, core.px(16))
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "[Item on Cursor!]")
        ImGui.SameLine()
        if ImGui.Button("Auto-Inv##hdrAutoInv", core.px(70), core.px(20)) then
            state.pendingAction = { type = 'autoinv' }
        end
    end

    ImGui.Dummy(0, core.px(4))

    -- Search and Filter Controls
    ImGui.PushItemWidth(core.px(220))
    local newSearch, searchChanged = ImGui.InputTextWithHint("##InvSearch", "Search item, type, clicky...", state.searchFilter or '')
    if searchChanged and type(newSearch) == 'string' then
        state.searchFilter = newSearch
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("X##clearSearch", core.px(22), core.px(22)) then
        state.searchFilter = ''
    end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', "Clear search filter") end

    ImGui.SameLine(0, core.px(12))
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
    ImGui.PushItemWidth(core.px(120))
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

    ImGui.SameLine(0, core.px(12))
    state.filterTradeskill = ImGui.Checkbox("Tradeskill##fltTS", state.filterTradeskill)
    ImGui.SameLine()
    state.filterLore = ImGui.Checkbox("Lore##fltLore", state.filterLore)
    ImGui.SameLine()
    state.filterNoDrop = ImGui.Checkbox("No-Drop##fltND", state.filterNoDrop)
    ImGui.SameLine()
    state.filterClicky = ImGui.Checkbox("Clicky##fltClk", state.filterClicky)

    ImGui.SameLine(0, core.px(16))
    if ImGui.Button("Refresh Scan##hdrScanBtn", core.px(100), core.px(22)) then
        state.pendingAction = { type = 'rescan' }
    end

    ImGui.Separator()
end

-- The Game Database plugin (tac/gamedb.lua) when it is loaded and enabled.
local function gamedbPlugin()
    local pm = core and core.runtime and core.runtime.pluginManager
    local p = pm and pm.plugins and pm.plugins.gamedb
    if p and p.enabled and p.instance and p.instance.popout then return p.instance end
    return nil
end

-- Opens the database card for an inventory item; false when unavailable.
local function openDatabaseCard(it)
    local db = gamedbPlugin()
    if not db or not it or not it.id or it.id <= 0 then return false end
    return db.popout('items', it.id) == true
end

local function shiftHeld()
    local held = false
    local okIO, io = pcall(ImGui.GetIO)
    if okIO and io then pcall(function() if io.KeyShift then held = true end end) end
    return held
end

function UI.drawTooltip(it, hint)
    ImGui.BeginTooltip()

    -- Item name in gold
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], it.name or 'Item')
    if it.owner then
        ImGui.TextDisabled(string.format("ID: %d | Type: %s | %s's %s", it.id or 0, it.type or 'Misc', tostring(it.owner), it.displayLocation or ''))
    else
        ImGui.TextDisabled(string.format("ID: %d | Type: %s | Location: %s", it.id or 0, it.type or 'Misc', it.displayLocation or ''))
    end

    -- Tags line
    local tags = {}
    if it.magic then table.insert(tags, 'MAGIC ITEM') end
    if it.lore then table.insert(tags, 'LORE ITEM') end
    if it.nodrop then table.insert(tags, 'NO TRADE') end
    if it.norent then table.insert(tags, 'NO RENT') end
    if it.attunable then table.insert(tags, 'ATTUNEABLE') end
    if it.tradeskill then table.insert(tags, 'TRADESKILL') end
    if it.stackable then table.insert(tags, string.format('STACKABLE (%d/%d)', it.count or 1, it.stackSize or 1)) end
    if #tags > 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], table.concat(tags, '  '))
    end

    -- Required level
    if (it.requiredLevel or 0) > 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('Required Level: %d', it.requiredLevel))
    end

    ImGui.Separator()

    -- Weapon stats
    if (it.damage or 0) > 0 then
        local dmgLine = string.format('Damage: %d    Delay: %d', it.damage, it.delay or 0)
        if (it.range or 0) > 0 then dmgLine = dmgLine .. string.format('    Range: %d', it.range) end
        ImGui.Text(dmgLine)
        if it.dmgBonusType then
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'DMG Type: ' .. it.dmgBonusType)
        end
    end

    -- AC
    if (it.ac or 0) > 0 then
        ImGui.Text(string.format('AC: %d', it.ac))
    end

    -- HP / Mana / End
    local hasPool = ((it.hp or 0) ~= 0) or ((it.mana or 0) ~= 0) or ((it.endurance or 0) ~= 0)
    if hasPool then
        local poolParts = {}
        if (it.hp or 0) ~= 0 then table.insert(poolParts, string.format('HP: %+d', it.hp)) end
        if (it.mana or 0) ~= 0 then table.insert(poolParts, string.format('Mana: %+d', it.mana)) end
        if (it.endurance or 0) ~= 0 then table.insert(poolParts, string.format('End: %+d', it.endurance)) end
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], table.concat(poolParts, '   '))
    end

    -- Base stats
    local statNames = { 'STR', 'STA', 'AGI', 'DEX', 'WIS', 'INT', 'CHA' }
    local statKeys = { 'str', 'sta', 'agi', 'dex', 'wis', 'int', 'cha' }
    local heroicKeys = { 'heroicStr', 'heroicSta', 'heroicAgi', 'heroicDex', 'heroicWis', 'heroicInt', 'heroicCha' }
    local hasAnyStat = false
    for i = 1, #statKeys do
        if (it[statKeys[i]] or 0) ~= 0 or (it[heroicKeys[i]] or 0) ~= 0 then hasAnyStat = true break end
    end
    if hasAnyStat then
        local statParts = {}
        for i = 1, #statKeys do
            local base = it[statKeys[i]] or 0
            local hero = it[heroicKeys[i]] or 0
            if base ~= 0 or hero ~= 0 then
                local s = string.format('%s: %+d', statNames[i], base)
                if hero ~= 0 then s = s .. string.format(' (+%d)', hero) end
                table.insert(statParts, s)
            end
        end
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], table.concat(statParts, '   '))
    end

    -- Resists
    local resNames = { 'Magic', 'Fire', 'Cold', 'Disease', 'Poison', 'Corrupt' }
    local resKeys = { 'svMagic', 'svFire', 'svCold', 'svDisease', 'svPoison', 'svCorruption' }
    local hasAnyRes = false
    for i = 1, #resKeys do
        if (it[resKeys[i]] or 0) ~= 0 then hasAnyRes = true break end
    end
    if hasAnyRes then
        local resParts = {}
        for i = 1, #resKeys do
            local v = it[resKeys[i]] or 0
            if v ~= 0 then table.insert(resParts, string.format('SV %s: %+d', resNames[i], v)) end
        end
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], table.concat(resParts, '   '))
    end

    -- Regen
    local hasRegen = ((it.hpRegen or 0) ~= 0) or ((it.manaRegen or 0) ~= 0) or ((it.endRegen or 0) ~= 0)
    if hasRegen then
        local regenParts = {}
        if (it.hpRegen or 0) ~= 0 then table.insert(regenParts, string.format('HP Regen: %+d', it.hpRegen)) end
        if (it.manaRegen or 0) ~= 0 then table.insert(regenParts, string.format('Mana Regen: %+d', it.manaRegen)) end
        if (it.endRegen or 0) ~= 0 then table.insert(regenParts, string.format('End Regen: %+d', it.endRegen)) end
        ImGui.Text(table.concat(regenParts, '   '))
    end

    -- Combat modifiers
    local combatMods = {}
    if (it.attack or 0) ~= 0 then table.insert(combatMods, string.format('Attack: %+d', it.attack)) end
    if (it.haste or 0) ~= 0 then table.insert(combatMods, string.format('Haste: %+d%%', it.haste)) end
    if (it.accuracy or 0) ~= 0 then table.insert(combatMods, string.format('Accuracy: %+d', it.accuracy)) end
    if (it.avoidance or 0) ~= 0 then table.insert(combatMods, string.format('Avoidance: %+d', it.avoidance)) end
    if (it.combatEffects or 0) ~= 0 then table.insert(combatMods, string.format('Combat Effects: %+d', it.combatEffects)) end
    if (it.strikeThrough or 0) ~= 0 then table.insert(combatMods, string.format('Strikethrough: %+d', it.strikeThrough)) end
    if (it.stunResist or 0) ~= 0 then table.insert(combatMods, string.format('Stun Resist: %+d', it.stunResist)) end
    if #combatMods > 0 then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], table.concat(combatMods, '   '))
    end

    -- Defensive modifiers
    local defMods = {}
    if (it.shielding or 0) ~= 0 then table.insert(defMods, string.format('Shielding: %+d', it.shielding)) end
    if (it.spellShield or 0) ~= 0 then table.insert(defMods, string.format('Spell Shield: %+d', it.spellShield)) end
    if (it.dotShielding or 0) ~= 0 then table.insert(defMods, string.format('DoT Shield: %+d', it.dotShielding)) end
    if (it.damShield or 0) ~= 0 then table.insert(defMods, string.format('Dam Shield: %+d', it.damShield)) end
    if (it.dsm or 0) ~= 0 then table.insert(defMods, string.format('DS Mit: %+d', it.dsm)) end
    if #defMods > 0 then
        ImGui.Text(table.concat(defMods, '   '))
    end

    -- Caster modifiers
    local castMods = {}
    if (it.healAmount or 0) ~= 0 then table.insert(castMods, string.format('Heal Amt: %+d', it.healAmount)) end
    if (it.spellDamage or 0) ~= 0 then table.insert(castMods, string.format('Spell Dmg: %+d', it.spellDamage)) end
    if (it.clairvoyance or 0) ~= 0 then table.insert(castMods, string.format('Clairvoyance: %+d', it.clairvoyance)) end
    if #castMods > 0 then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], table.concat(castMods, '   '))
    end

    -- Purity / Instrument
    local miscMods = {}
    if (it.purity or 0) > 0 then table.insert(miscMods, string.format('Purity: %d', it.purity)) end
    if (it.instrumentMod or 0) > 0 then table.insert(miscMods, string.format('Instrument: %d', it.instrumentMod)) end
    if #miscMods > 0 then
        ImGui.Text(table.concat(miscMods, '   '))
    end

    -- Spell Effects
    if it.clicky or it.wornEffect or it.focusEffect then
        ImGui.Separator()
        if it.clicky then ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Click: ' .. it.clicky) end
        if it.wornEffect then ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Worn: ' .. it.wornEffect) end
        if it.focusEffect then ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Focus: ' .. it.focusEffect) end
    end

    -- Augments
    local augText = invLogic.formatAugs(it)
    if augText ~= '' then
        ImGui.Separator()
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Augs: ' .. augText)
    end

    -- Weight / Value / Tribute
    ImGui.Separator()
    local footer = string.format('Weight: %.1f | Value: %s', it.weight or 0, invLogic.formatMoney(it.value or 0))
    if (it.tribute or 0) > 0 then footer = footer .. string.format(' | Tribute: %d', it.tribute) end
    ImGui.TextDisabled(footer)

    -- Game Database: tiers, top drop, quest NPCs, recipes (nil while loading)
    local db = gamedbPlugin()
    local dbLines = db and db.itemSummary and db.itemSummary(it.id) or nil
    if dbLines then
        ImGui.Separator()
        for _, line in ipairs(dbLines) do
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], line)
        end
    end

    -- Interaction hint
    if it.remote then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Click: Give to a character' .. (db and ' | Shift+Right-Click: Database card' or ''))
    else
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Left-Click: Pick up / Place | Right-Click: Inspect | Drag: Move' .. (db and ' | Shift+Right-Click: Database card' or ''))
    end
    if hint then ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], hint) end
    ImGui.EndTooltip()
end

-- Items table columns (index -> sort field on the item) for the sortable header.
local SORT_COLUMNS = { [0] = 'Location', [1] = 'Name', [2] = 'Augs', [3] = 'Qty', [4] = 'Wt', [5] = 'Value' }
local SORT_KEYS = { Location = 'displayLocation', Name = 'name', Augs = 'augText', Qty = 'count', Wt = 'weight', Value = 'value' }
local SORT_NUMERIC = { count = true, weight = true, value = true }

-- Reads the table's sort specs (when the binding exposes them) into
-- state.sortCol / state.sortAsc. Tolerates the two shapes MQ's ImGui Lua
-- binding has used (Specs[i] table indexing or Specs(i) call).
local function applyTableSortSpecs()
    pcall(function()
        if not ImGui.TableGetSortSpecs then return end
        local specs = ImGui.TableGetSortSpecs()
        if not specs or not specs.SpecsDirty then return end
        local spec = nil
        local okIdx, v = pcall(function() return specs.Specs[1] end)
        if okIdx and v then
            spec = v
        else
            local okCall, v2 = pcall(function() return specs:Specs(1) end)
            if okCall and v2 then spec = v2 end
        end
        if spec then
            local colIdx = tonumber(spec.ColumnIndex)
            local dir = spec.SortDirection
            local col = colIdx and SORT_COLUMNS[colIdx]
            if col then
                state.sortCol = col
                local sortEnum = rawget(_G, 'ImGuiSortDirection')
                local descVal = (sortEnum and sortEnum.Descending) or 2
                state.sortAsc = (dir ~= descVal)
            end
        end
        specs.SpecsDirty = false
    end)
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

        local colKey = SORT_KEYS[state.sortCol] or string.lower(state.sortCol)
        local numeric = SORT_NUMERIC[colKey] == true
        local asc = state.sortAsc
        table.sort(filt, function(a, b)
            local valA, valB
            if numeric then
                valA = tonumber(a[colKey]) or 0
                valB = tonumber(b[colKey]) or 0
            else
                valA = string.lower(tostring(a[colKey] or a.name or ''))
                valB = string.lower(tostring(b[colKey] or b.name or ''))
            end
            if valA == valB then
                -- Stable tie-break so equal keys keep a deterministic order
                local na, nb = string.lower(a.name or ''), string.lower(b.name or '')
                if na ~= nb then return na < nb end
                return (a.notifyCmd or '') < (b.notifyCmd or '')
            end
            if asc then
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
    local bn = boxnet()
    local hasBoxPeers = bn ~= nil and bn.available() and #bn.peers() > 0

    ImGui.TextDisabled(string.format("Showing %d matching items", #filtered))
    ImGui.Dummy(0, core.px(2))

    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Sortable
    if ImGui.BeginTable("InvItemsTable", 7, tableFlags, ImVec2(0, 0)) then
        ImGui.TableSetupColumn("Location##colLoc", ImGuiTableColumnFlags.WidthFixed, core.px(110))
        ImGui.TableSetupColumn("Item Name##colName", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Augs##colAugs", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Qty##colQty", ImGuiTableColumnFlags.WidthFixed, core.px(55))
        ImGui.TableSetupColumn("Wt##colWt", ImGuiTableColumnFlags.WidthFixed, core.px(45))
        ImGui.TableSetupColumn("Value##colVal", ImGuiTableColumnFlags.WidthFixed, core.px(75))
        ImGui.TableSetupColumn("Actions##colAct", ImGuiTableColumnFlags.WidthFixed, core.px(180))
        ImGui.TableHeadersRow()
        applyTableSortSpecs()

        local clipper = nil
        local ClipperClass = ImGui.ListClipper or (mq.imgui and mq.imgui.ListClipper) or _G['ImGuiListClipper']
        if ClipperClass and ClipperClass.new then
            local okC, c = pcall(ClipperClass.new)
            if okC and c then clipper = c end
        end

        local function drawRow(idx, it)
            ImGui.TableNextRow()
            ImGui.PushID(idx)

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
                if ImGui.IsItemClicked(1) then openDatabaseCard(it) end
            end

            -- Col 2: Augs (precomputed per item)
            ImGui.TableSetColumnIndex(2)
            local augText = it.augText or invLogic.formatAugs(it)
            if augText ~= '' then
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], augText)
            else
                ImGui.TextDisabled("-")
            end

            -- Col 3: Qty
            ImGui.TableSetColumnIndex(3)
            if it.stackable then
                ImGui.Text(it.qtyText or string.format("%d/%d", it.count or 1, it.stackSize or 1))
            else
                ImGui.TextDisabled("1")
            end

            -- Col 4: Weight
            ImGui.TableSetColumnIndex(4)
            ImGui.Text(it.weightText or string.format("%.1f", it.weight or 0))

            -- Col 5: Value
            ImGui.TableSetColumnIndex(5)
            ImGui.TextDisabled(it.valueText or invLogic.formatMoney(it.value or 0))

            -- Col 6: Actions (PushID(idx) above keeps the labels unique)
            ImGui.TableSetColumnIndex(6)
            local inBank = it.location == 'BANK' or it.location == 'SHAREDBANK'
            local canInspect = not inBank or state.bankLive
            if not canInspect then ImGui.BeginDisabled() end
            if ImGui.SmallButton("Inspect") then
                state.pendingAction = { type = 'inspect', item = it }
            end
            if not canInspect then
                ImGui.EndDisabled()
                if ImGui.IsItemHovered() then core.setTooltip('Bank is closed: cached bank items cannot be inspected.') end
            end
            ImGui.SameLine()
            if it.location == 'INVENTORY' and it.subSlot then
                if ImGui.SmallButton("Open") then
                    state.pendingAction = { type = 'open_bag', slot = it.slotIndex }
                end
                ImGui.SameLine()
                if ImGui.SmallButton("Pick") then
                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                end
            elseif (it.location == 'WORN' or (inBank and state.bankLive)) and it.notifyCmd ~= '' then
                if ImGui.SmallButton("Pick") then
                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                end
            end
            if hasBoxPeers and not invLogic.giveBlocker(it) then
                ImGui.SameLine()
                if ImGui.SmallButton("Give") then openGivePopup(it) end
                if ImGui.IsItemHovered() then core.setTooltip('Hand this item to one of your other boxes (Box Inventories).') end
            end
            ImGui.PopID()
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
    drawGivePopup()
end

local function optimisticTakeSlot(bag, s)
    if not bag or not bag.slots then return nil end
    local it = bag.slots[s]
    if not it then return nil end
    bag.slots[s] = nil
    bag.used = math.max(0, (bag.used or 1) - 1)
    markDirty()
    return it
end

local function findContainerBag(location, slotIndex)
    local list = (location == 'BANK') and state.containers.bank
        or (location == 'SHAREDBANK') and state.containers.sharedBank
        or state.containers.inventory
    for _, bag in ipairs(list or {}) do
        if bag.slot == slotIndex then return bag end
    end
    return nil
end

local function optimisticSwapToSlot(destBag, destSlot, destItem, destCmd, destLocation)
    local src = state.dragSource
    if not src or not src.slotIndex or not src.subSlot then return end
    local srcBag = findContainerBag(src.location, src.slotIndex)
    if not srcBag or not srcBag.slots then return end
    srcBag.slots[src.subSlot] = destItem
    if destItem then
        destItem.slotIndex = src.slotIndex
        destItem.subSlot = src.subSlot
        destItem.location = src.location
        destItem.notifyCmd = src.notifyCmd
    else
        srcBag.used = math.max(0, (srcBag.used or 1) - 1)
        destBag.used = (destBag.used or 0) + 1
    end
    destBag.slots[destSlot] = src
    src.slotIndex = destBag.slot
    src.subSlot = destSlot
    src.notifyCmd = destCmd
    src.location = destLocation
        or (destCmd:find('sharedbank', 1, true) and 'SHAREDBANK')
        or (destCmd:find('bank', 1, true) and 'BANK')
        or 'INVENTORY'
    markDirty()
end

-- ----------------------------------------------------------------------------
-- Bag grid: one bag's slots as icon tiles. Shared by the local bags, the bank
-- (live or cached), the shared bank and a peer's snapshot. ctx:
--   palette       'inv' | 'bank'            colour set
--   idPrefix      unique per grid            ('b', 'bk', 'sb', 'r'...)
--   interactive   clicks / drags drive the game (false: cached bank, peers)
--   cursorHasItem, cursorItemName            place-mode hints
--   emptyCmd(bag, s)                         /itemnotify address of slot s
--   location      'INVENTORY' | 'BANK' | 'SHAREDBANK' (optimistic moves)
--   onClick(it, bag, s, button)              read-only grids: 0 left, 1 right
--   hint          tooltip line for read-only grids
-- ----------------------------------------------------------------------------
local function slotColors(palette)
    if palette == 'bank' then
        return SLOT_COL.bankBgActive, SLOT_COL.bankBgHover, SLOT_COL.bankBg, SLOT_COL.bankEmptyHover, SLOT_COL.bankEmpty,
            SLOT_COL.bankBdrPlace, SLOT_COL.bankBdrHover, SLOT_COL.bankBdr, SLOT_COL.bankBdrEmpty, SLOT_COL.bankNum
    end
    return SLOT_COL.invBgActive, SLOT_COL.invBgHover, SLOT_COL.invBg, SLOT_COL.invEmptyHover, SLOT_COL.invEmpty,
        SLOT_COL.invBdrPlace, SLOT_COL.invBdrHover, SLOT_COL.invBdr, SLOT_COL.invBdrEmpty, SLOT_COL.invNum
end

local function readDragPayload(payload)
    local fromCmd = (type(payload) == 'table' and payload.Data)
        or (type(payload) == 'userdata' and payload.Data)
        or (state.dragSource and state.dragSource.notifyCmd)
        or payload
    return tostring(fromCmd or '')
end

function UI.drawBagGrid(bag, ctx)
    local cap = tonumber(bag and bag.capacity) or 0
    if cap <= 0 then return end
    local cols = math.min(cap, 10)
    local SZ = core.px(34)
    local ICON = core.px(30)
    local bgActive, bgHover, bgItem, bgEmptyHover, bgEmpty, bdrPlace, bdrHover, bdrItem, bdrEmpty, numCol = slotColors(ctx.palette)
    local btnIds = bag.btnIds
    if not btnIds or btnIds.prefix ~= ctx.idPrefix then
        btnIds = { prefix = ctx.idPrefix }
        bag.btnIds = btnIds
    end
    local interactive = ctx.interactive == true
    local placeMode = interactive and ctx.cursorHasItem == true

    for s = 1, cap do
        local it = bag.slots and bag.slots[s]
        local btnId = btnIds[s]
        if not btnId then
            btnId = string.format('##%s%ds%d', ctx.idPrefix, bag.slot, s)
            btnIds[s] = btnId
        end
        local startX, startY = ImGui.GetCursorScreenPos()
        local clicked = ImGui.InvisibleButton(btnId, SZ, SZ)
        local hovered = ImGui.IsItemHovered()
        local active  = ImGui.IsItemActive()
        local endX, endY = ImGui.GetCursorScreenPos()
        local dl = ImGui.GetWindowDrawList()

        local bgCol
        if it then
            bgCol = active and bgActive or (hovered and bgHover or bgItem)
        else
            bgCol = hovered and bgEmptyHover or bgEmpty
        end
        dl:AddRectFilled(ImVec2(startX, startY), ImVec2(startX + SZ, startY + SZ), bgCol, 3)
        local bdrCol
        if hovered then
            bdrCol = placeMode and bdrPlace or bdrHover
        else
            bdrCol = it and bdrItem or bdrEmpty
        end
        dl:AddRect(ImVec2(startX, startY), ImVec2(startX + SZ, startY + SZ), bdrCol, 3)

        local iconDrawn = false
        if it and it.icon and it.icon > 0 then
            iconDrawn = renderSlotIcon(it.icon, startX, startY, endX, endY, dl, ICON)
        end
        if not iconDrawn then
            local sStr = tostring(s)
            local sw = textWidth(sStr)
            dl:AddText(ImVec2(startX + math.max(0, (SZ - sw) / 2), startY + SZ * 0.3), it and numCol or SLOT_COL.numEmpty, sStr)
        end
        if it and it.stackable and it.count and it.count > 1 then
            local cStr = tostring(it.count)
            local cw = textWidth(cStr)
            dl:AddRectFilled(ImVec2(startX + SZ - cw - 4, startY + SZ - 12), ImVec2(startX + SZ - 1, startY + SZ - 1), SLOT_COL.badgeBg, 2)
            dl:AddText(ImVec2(startX + SZ - cw - 2, startY + SZ - 13), SLOT_COL.badgeText, cStr)
        end

        if hovered then
            if it then
                UI.drawTooltip(it, ctx.hint)
            elseif placeMode then
                ImGui.SetTooltip('%s', string.format('%s %d Slot %d: Click to place %s', ctx.label or 'Bag', bag.slot, s, ctx.cursorItemName or 'item'))
            else
                ImGui.SetTooltip('%s', string.format('%s %d Slot %d: Empty', ctx.label or 'Bag', bag.slot, s))
            end
        end

        if interactive then
            if it and ImGui.BeginDragDropSource() then
                ImGui.SetDragDropPayload('TRIUNE_INV_SLOT', it.notifyCmd)
                state.dragSource = it
                ImGui.Text(string.format('Moving: %s', it.name or 'Item'))
                ImGui.EndDragDropSource()
            end
            if ImGui.BeginDragDropTarget() then
                local payload = ImGui.AcceptDragDropPayload('TRIUNE_INV_SLOT')
                if payload then
                    local fromCmd = readDragPayload(payload)
                    local toCmd = it and it.notifyCmd or ctx.emptyCmd(bag, s)
                    if fromCmd ~= '' and toCmd ~= '' and fromCmd ~= toCmd then
                        optimisticSwapToSlot(bag, s, it, toCmd, ctx.location)
                        state.pendingAction = { type = 'move', fromCmd = fromCmd, toCmd = toCmd,
                            fromId = state.dragSource and state.dragSource.id or nil }
                    end
                    state.dragSource = nil
                end
                ImGui.EndDragDropTarget()
            end
        end

        local rClicked = ImGui.IsItemClicked(1)
        if interactive then
            if clicked and not state.pendingAction then
                if ctx.cursorHasItem then
                    state.pendingAction = { type = 'pickup', notifyCmd = it and it.notifyCmd or ctx.emptyCmd(bag, s) }
                elseif it then
                    optimisticTakeSlot(bag, s)
                    state.pendingAction = { type = 'pickup', notifyCmd = it.notifyCmd }
                end
            elseif rClicked and it and not state.pendingAction then
                if not (shiftHeld() and openDatabaseCard(it)) then
                    state.pendingAction = { type = 'inspect', item = it }
                end
            end
        elseif it and ctx.onClick then
            if clicked then ctx.onClick(it, bag, s, 0)
            elseif rClicked then ctx.onClick(it, bag, s, 1) end
        elseif it and rClicked and shiftHeld() then
            openDatabaseCard(it)
        end

        if s % cols ~= 0 and s < cap then
            ImGui.SameLine(0, core.px(4))
        end
    end
end

-- Bag title line: "<Label> N: name (used/cap)" coloured by fill level.
local function drawBagTitle(label, bag)
    local pct = bag.capacity > 0 and (bag.used / bag.capacity) or 0
    local barCol = pct >= 1.0 and ERR or (pct >= 0.75 and WARN or GOOD)
    ImGui.TextColored(barCol[1], barCol[2], barCol[3], barCol[4], string.format('%s %d: %s', label, bag.slot, bag.name))
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(%d/%d slots)', bag.used, bag.capacity))
end

local function drawSortButtons(bag, packKind, idSuffix)
    local canSort = (bag.used or 0) >= 2
    if not canSort then ImGui.BeginDisabled() end
    if ImGui.SmallButton('Sort A-Z##sort' .. idSuffix) then
        local moves = invLogic.planBagAlphaSort(bag, packKind)
        if #moves > 0 then state.pendingAction = { type = 'sort_bag', moves = moves, index = 1 } end
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Sort Type##sortType' .. idSuffix) then
        local moves = invLogic.planBagAlphaSort(bag, packKind, 'type')
        if #moves > 0 then state.pendingAction = { type = 'sort_bag', moves = moves, index = 1 } end
    end
    if not canSort then ImGui.EndDisabled() end
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
        ImGui.BeginChild("CursorBanner", ImVec2(0, core.px(32)), true)
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
        ImGui.Dummy(0, core.px(2))
    else
        ImGui.TextDisabled("Visual Container Overview — Left-Click: Pick up / Place | Right-Click: Inspect | Drag & Drop to Move")
        ImGui.Dummy(0, core.px(4))
    end

    local availWidth = ImGui.GetContentRegionAvail()
    local halfWidth = math.floor((availWidth - core.px(16)) / 2)

    -- Left Child: Inventory Bags
    ImGui.BeginChild("InvVisualizerChild", ImVec2(halfWidth, 0), true)
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "PERSONAL INVENTORY BAGS (1..10)")
    ImGui.Separator()
    ImGui.Dummy(0, core.px(4))

    local invCtx = {
        palette = 'inv', idPrefix = 'b', label = 'Bag', location = 'INVENTORY', interactive = true,
        cursorHasItem = cursorHasItem, cursorItemName = cursorItemName,
        emptyCmd = function(bag, s) return string.format('in pack%d %d', bag.slot, s) end,
    }
    for bIdx, bag in ipairs(state.containers.inventory) do
        if bag.capacity > 0 then
            drawBagTitle('Bag', bag)
            ImGui.SameLine()
            if ImGui.SmallButton("Open##openBag" .. bIdx) then
                state.pendingAction = { type = 'open_bag', slot = bag.slot }
            end
            ImGui.SameLine()
            drawSortButtons(bag, 'pack', 'Bag' .. bIdx)
            UI.drawBagGrid(bag, invCtx)
            ImGui.Dummy(0, core.px(6))
        end
    end
    ImGui.EndChild()

    ImGui.SameLine(0, core.px(16))

    -- Right Child: Bank + Shared Bank Containers
    ImGui.BeginChild("BankVisualizerChild", ImVec2(halfWidth, 0), true)
    local bankTitle = state.bankLive and "BANK STORAGE (LIVE)" or "BANK STORAGE (CACHED)"
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], bankTitle)
    ImGui.Separator()
    ImGui.Dummy(0, core.px(4))

    if #state.containers.bank == 0 and #state.containers.sharedBank == 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "No bank data available.\nVisit a banker in any major city to sync your bank inventory!")
    else
        local bankHint = (not state.bankLive) and '(Bank is closed — visit a banker to move bank items)' or nil
        local bankCtx = {
            palette = 'bank', idPrefix = 'bk', label = 'Bank', location = 'BANK', interactive = state.bankLive == true,
            cursorHasItem = cursorHasItem, cursorItemName = cursorItemName, hint = bankHint,
            emptyCmd = function(bag, s) return string.format('in bank%d %d', bag.slot, s) end,
            onClick = function(it, _, _, button)
                if button == 1 then
                    if not (shiftHeld() and openDatabaseCard(it)) then state.statusMsg = 'Bank is closed: ' .. it.name .. ' cannot be inspected from the cache.' end
                end
            end,
        }
        for _, bag in ipairs(state.containers.bank) do
            if bag.capacity > 0 then
                drawBagTitle('Bank', bag)
                if state.bankLive then
                    ImGui.SameLine()
                    drawSortButtons(bag, 'bank', 'Bank' .. tostring(bag.slot))
                end
                UI.drawBagGrid(bag, bankCtx)
                ImGui.Dummy(0, core.px(6))
            end
        end
        if #state.containers.sharedBank > 0 then
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "SHARED BANK")
            ImGui.Separator()
            local sharedCtx = {
                palette = 'bank', idPrefix = 'sb', label = 'Shared', location = 'SHAREDBANK', interactive = state.bankLive == true,
                cursorHasItem = cursorHasItem, cursorItemName = cursorItemName, hint = bankHint,
                emptyCmd = function(bag, s) return string.format('in sharedbank%d %d', bag.slot, s) end,
                onClick = bankCtx.onClick,
            }
            for _, bag in ipairs(state.containers.sharedBank) do
                if bag.capacity > 0 then
                    drawBagTitle('Shared', bag)
                    UI.drawBagGrid(bag, sharedCtx)
                    ImGui.Dummy(0, core.px(6))
                end
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
    ImGui.Dummy(0, core.px(6))

    -- Quick Utilities Toolbar
    ImGui.TextDisabled("Quick Bag Controls:")
    ImGui.SameLine()
    if ImGui.Button("Open All Bags##orgOpenAll", core.px(120), core.px(24)) then
        state.pendingAction = { type = 'open_all_bags' }
    end
    ImGui.SameLine()
    if ImGui.Button("Close All Bags##orgCloseAll", core.px(120), core.px(24)) then
        state.pendingAction = { type = 'close_all_bags' }
    end
    ImGui.SameLine()
    if ImGui.Button("Auto-Inventory Cursor##orgAutoInv", core.px(160), core.px(24)) then
        state.pendingAction = { type = 'autoinv' }
    end
    -- Duplicate stacks / heaviest items are recomputed only when the item
    -- data changed (dataGen) or the bank flipped between live and cached.
    local oc = state.orgCache
    if oc.gen ~= state.dataGen or oc.bankLive ~= state.bankLive then
        oc.gen = state.dataGen
        oc.bankLive = state.bankLive
        oc.dups = invLogic.findDuplicateStacks(state.items)
        oc.heavies = invLogic.findHeaviestItems(state.items, 10)
        -- Only enable when at least one duplicate can actually be moved right now
        -- (bank stacks are unmovable while the bank window is closed).
        oc.canCombineAny = false
        for _, d in ipairs(oc.dups) do
            if invLogic.findNextCombineMove(d, state.bankLive) then
                oc.canCombineAny = true
                break
            end
        end
    end
    local dups = oc.dups
    local canCombineAny = oc.canCombineAny
    ImGui.SameLine()
    if not canCombineAny then ImGui.BeginDisabled() end
    if ImGui.Button("Combine All Stacks##orgCombineAll", core.px(160), core.px(24)) then
        if canCombineAny then
            state.combineAllActive = true
            state.combineMoveCount = 0
            state.combineNoProgress = 0
            state.combineLastKey = nil
            state.pendingAction = { type = 'combine_stacks' }
        end
    end
    if not canCombineAny then ImGui.EndDisabled() end

    ImGui.Dummy(0, core.px(10))

    -- Section 1: Fragmented Stacks
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "FRAGMENTED STACKS (STACK CONSOLIDATION OPPORTUNITIES)")
    ImGui.TextDisabled("Items below are stackable and have multiple partial stacks scattered across your bags or bank.")
    ImGui.Dummy(0, core.px(2))
    if #dups == 0 then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "✓ All stackable items are fully consolidated! No fragmented stacks found.")
    else
        if ImGui.BeginTable("DupStacksTable", 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Stacks", ImGuiTableColumnFlags.WidthFixed, core.px(60))
            ImGui.TableSetupColumn("Total Count", ImGuiTableColumnFlags.WidthFixed, core.px(90))
            ImGui.TableSetupColumn("Locations & Partial Counts", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, core.px(70))
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
                ImGui.TableSetColumnIndex(4)
                if (d.numStacks or #d.stacks) > 1 then
                    if ImGui.SmallButton("Combine##" .. tostring(d.id or d.name)) then
                        state.combineAllActive = false
                        state.combineMoveCount = 0
                        state.combineNoProgress = 0
                        state.combineLastKey = nil
                        state.pendingAction = { type = 'combine_stacks', item = d }
                    end
                else
                    ImGui.TextDisabled("-")
                end
            end
            ImGui.EndTable()
        end
    end

    ImGui.Dummy(0, core.px(14))

    -- Section 2: Heaviest Carried Items
    ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "WEIGHT WATCHER (HEAVIEST ITEMS IN BAGS)")
    ImGui.TextDisabled("Items below contribute the most weight to your character. Useful for Monks or managing encumbrance.")
    ImGui.Dummy(0, core.px(2))

    local heavies = oc.heavies
    if #heavies == 0 then
        ImGui.TextDisabled("No items found in bags.")
    else
        if ImGui.BeginTable("HeavyItemsTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthFixed, core.px(140))
            ImGui.TableSetupColumn("Category", ImGuiTableColumnFlags.WidthFixed, core.px(90))
            ImGui.TableSetupColumn("Total Weight", ImGuiTableColumnFlags.WidthFixed, core.px(90))
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
    ImGui.Dummy(0, core.px(6))

    ImGui.Text("Bank Cache Status:")
    ImGui.SameLine()
    if state.bankLive then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Live banker window open (Automatic real-time sync active)")
    else
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format("Using offline cached bank snapshot (Last updated: %s)", state.bankLastSync))
    end

    ImGui.Dummy(0, core.px(4))
    if ImGui.Button("Force Full Scan Now##forceScan", core.px(160), core.px(26)) then
        state.pendingAction = { type = 'rescan', statusMsg = "Full scan completed." }
    end
    ImGui.SameLine()
    if ImGui.Button("Clear Offline Bank Cache##clearBank", core.px(180), core.px(26)) then
        state.pendingAction = { type = 'clear_bank_cache' }
    end

    ImGui.Dummy(0, core.px(10))
    ImGui.Separator()
    ImGui.Dummy(0, core.px(6))

    local autoScan = ImGui.Checkbox("Enable Background Auto-Scan##autoScan", state.autoScan)
    if autoScan ~= state.autoScan then
        state.autoScan = autoScan
        core.saveLoadout(true)
    end
    if state.autoScan then
        ImGui.PushItemWidth(core.px(180))
        local newInterval, intChanged = ImGui.SliderInt("Scan Interval (sec)##scanInt", tonumber(state.autoScanInterval) or 15, 5, 60)
        if intChanged and type(newInterval) == 'number' then
            state.autoScanInterval = newInterval
            core.saveLoadout(true)
        end
        ImGui.PopItemWidth()
    end

    ImGui.Dummy(0, core.px(10))
    ImGui.Separator()
    ImGui.Dummy(0, core.px(6))
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "BOX INVENTORIES (BOX NETWORK)")
    ImGui.Dummy(0, core.px(4))
    UI.drawNetSettings()

    if state.statusMsg ~= '' then
        ImGui.Dummy(0, core.px(8))
        ImGui.TextDisabled("Status: " .. state.statusMsg)
    end
end

-- Box Inventories switches (Settings tab and the Plugins page).
function UI.drawNetSettings()
    local function check(label, key, tip)
        local v = ImGui.Checkbox(label, cfg[key] == true)
        if v ~= (cfg[key] == true) then
            cfg[key] = v
            core.saveLoadout(true)
        end
        if tip and ImGui.IsItemHovered() then core.setTooltip(tip) end
    end
    check('Share my inventory with my other boxes##invNetShare', 'share',
        'Answer snapshot requests from the other boxes on this MacroQuest launcher. Off: they see "sharing is off".')
    check('Accept give requests from my other boxes##invNetGives', 'acceptGives',
        'Let another box ask this character to hand an item to someone (through the trade window).\nAlso gated by Box Network -> Accept remote commands / allowlist.')
    check('Print transfers to chat##invNetAnnounce', 'announce', nil)
    ImGui.SetNextItemWidth(core.px(160))
    local range, rangeChanged = ImGui.SliderInt('Trade range##invNetRange', tonumber(cfg.tradeRange) or 15, 5, 50)
    if rangeChanged and type(range) == 'number' then
        cfg.tradeRange = range
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('A give is refused when the receiver is farther than this (the game itself refuses trades beyond about 15).') end
end

-- ============================================================================
-- Click helpers shared by the queued actions and the give workflow
-- ============================================================================
local function quantityWndOpen()
    local open = false
    pcall(function()
        local w = mq.TLO.Window('QuantityWnd')
        open = w and w() and w.Open()
    end)
    return open
end

local function acceptQuantityWnd()
    if not quantityWndOpen() then
        delay(15)
        if not quantityWndOpen() then return end
    end
    pcall(function()
        mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
    end)
    delay(20)
    if quantityWndOpen() then
        -- Retry the Accept button once; never send a blind /yes (it would
        -- answer whatever unrelated confirmation happens to be open).
        pcall(function()
            mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
        end)
        delay(20)
    end
end

local function notifyLeft(cmd)
    if not cmd or cmd == '' then return end
    pcall(function()
        mq.cmdf('/nomodkey /itemnotify %s leftmouseup', cmd)
    end)
    acceptQuantityWnd()
end

-- After a pickup click, confirm the cursor holds the expected item id before
-- the next click in a chain. Returns true when the cursor matches (or when no
-- expected id is known and the cursor holds something). On mismatch, drops
-- whatever is on the cursor back into inventory and returns false so the
-- caller aborts the chain.
local function cursorMatches(expectedId)
    expectedId = tonumber(expectedId)
    local curId = 0
    pcall(function()
        if mq.TLO.Cursor() then curId = tonumber(mq.TLO.Cursor.ID()) or 0 end
    end)
    if not expectedId or expectedId <= 0 then
        return curId > 0
    end
    if curId == expectedId then return true end
    if curId > 0 then
        pcall(function() mq.cmd('/autoinventory') end)
        delay(100)
    end
    state.statusMsg = string.format('Aborted move: cursor held item %d, expected %d', curId, expectedId)
    return false
end

-- ============================================================================
-- Box Inventories: snapshots of the other boxes and item transfers
-- ============================================================================
local function nowSec()
    if mq and mq.gettime then
        local ok, ms = pcall(mq.gettime)
        if ok and type(ms) == 'number' then return ms / 1000 end
    end
    return os.clock()
end

local function lower(s) return tostring(s or ''):lower() end

-- The boxnet API when the plugin is loaded and connected; nil otherwise.
function boxnet()
    local bn = core and rawget(core, 'boxnet')
    if type(bn) ~= 'table' or type(bn.available) ~= 'function' then return nil end
    return bn
end

local function myName()
    local bn = boxnet()
    if bn and bn.myName then
        local ok, n = pcall(bn.myName)
        if ok and type(n) == 'string' and n ~= '' then return n end
    end
    local ok, n = pcall(function() return mq.TLO.Me.CleanName() end)
    if ok and n then return tostring(n) end
    return ''
end

local function netLog(text, level)
    local log = state.net.log
    table.insert(log, 1, { time = os.date('%H:%M:%S'), text = tostring(text), level = level or 'info' })
    while #log > NET_LOG_MAX do table.remove(log) end
    state.net.status = tostring(text)
end

local function chat(fmt, ...)
    if not cfg.announce then return end
    print(string.format('\ag[Triune Inv]\ax ' .. fmt, ...))
end

-- Game reads the give workflow depends on, in one table so tests can drive a
-- scripted client through plugin.probe.
local probe = {}

function probe.cursorId()
    local id = 0
    pcall(function()
        if mq.TLO.Cursor() then id = tonumber(mq.TLO.Cursor.ID()) or 0 end
    end)
    return id
end

function probe.targetId()
    local id = 0
    pcall(function() id = tonumber(mq.TLO.Target.ID()) or 0 end)
    return id
end

-- A player spawn by name: { id, dist } or nil when not in this zone.
function probe.spawn(name)
    if not name or name == '' then return nil end
    local out = nil
    pcall(function()
        local sp = mq.TLO.Spawn('pc =' .. name)
        if not (sp and sp() and (sp.ID() or 0) > 0) then sp = mq.TLO.Spawn('pc ' .. name) end
        if sp and sp() and (sp.ID() or 0) > 0 then
            local dist = nil
            pcall(function() dist = tonumber(sp.Distance3D()) end)
            if not dist then pcall(function() dist = tonumber(sp.Distance()) end) end
            out = { id = sp.ID() or 0, dist = dist or 0 }
        end
    end)
    return out
end

function probe.tradeOpen()
    local open = false
    pcall(function()
        local w = mq.TLO.Window('TradeWnd')
        open = (w and w() and w.Open()) == true
    end)
    return open
end

function probe.tradeHisName()
    local name = ''
    pcall(function()
        local lbl = mq.TLO.Window('TradeWnd').Child('TRDW_HisName')
        if lbl and lbl() then name = tostring(lbl.Text() or '') end
    end)
    return name:match('^%S+') or ''
end

function probe.myPos()
    local pos = nil
    pcall(function()
        pos = { x = mq.TLO.Me.X() or 0, y = mq.TLO.Me.Y() or 0, z = mq.TLO.Me.Z() or 0, zone = tostring(mq.TLO.Zone.ShortName() or '') }
    end)
    return pos
end

-- Where item `id` is right now: prefers the slot the snapshot named when it
-- still holds that id, else FindItem. Returns { cmd, name, count, stackable,
-- nodrop } or nil when the item is not in the bags / worn slots.
function probe.locate(id, preferredCmd)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    local function describe(itemObj, cmd)
        local out = nil
        pcall(function()
            if not (itemObj and itemObj() and (tonumber(itemObj.ID()) or 0) == id) then return end
            out = {
                cmd = cmd,
                name = tostring(itemObj.Name() or ''),
                count = tonumber(itemObj.Stack()) or 1,
                stackable = itemObj.Stackable() == true,
                nodrop = itemObj.NoDrop() == true,
            }
        end)
        return out
    end
    local cmd = tostring(preferredCmd or '')
    if cmd ~= '' then
        local pack, sub = cmd:match('^in pack(%d+) (%d+)$')
        local found = nil
        if pack then
            found = describe(mq.TLO.Me.Inventory('pack' .. pack).Item(tonumber(sub)), cmd)
        elseif cmd:match('^pack%d+$') then
            found = describe(mq.TLO.Me.Inventory(cmd), cmd)
        elseif cmd:match('^%d+$') then
            found = describe(mq.TLO.Me.Inventory(tonumber(cmd)), cmd)
        end
        if found then return found end
    end
    local found = nil
    pcall(function()
        local fi = mq.TLO.FindItem(id)
        if not (fi and fi() and (tonumber(fi.ID()) or 0) == id) then return end
        local slot = tonumber(fi.ItemSlot()) or -1
        local sub = tonumber(fi.ItemSlot2()) or -1
        local c
        if slot >= 23 and slot <= 32 then
            c = (sub >= 0) and string.format('in pack%d %d', slot - 22, sub + 1) or string.format('pack%d', slot - 22)
        elseif slot >= 0 and slot <= 22 then
            c = tostring(slot)
        else
            return -- bank / elsewhere
        end
        found = describe(fi, c)
    end)
    return found
end

-- Peer snapshot record for a box (created on demand).
local function netPeerRecord(name, create)
    local key = lower(name)
    if key == '' then return nil end
    local rec = state.net.peers[key]
    if not rec and create then
        rec = { name = name, items = nil, containers = nil, meta = nil, at = 0, gen = 0 }
        state.net.peers[key] = rec
    end
    if rec and name and name ~= '' then rec.name = name end
    return rec
end

-- The roster entry (heartbeat) for a box, nil when it is not on the network.
local function onlinePeer(name)
    local bn = boxnet()
    if not bn or not bn.peer then return nil end
    local ok, p = pcall(bn.peer, name)
    if ok and type(p) == 'table' then return p end
    return nil
end

local function peerPos(name)
    if lower(name) == lower(myName()) then return probe.myPos() end
    local p = onlinePeer(name)
    local hb = p and p.hb
    if type(hb) ~= 'table' then return nil end
    return { x = hb.x, y = hb.y, z = hb.z, zone = tostring(hb.zone or '') }
end

-- Distance between two characters from their reported positions: dist,
-- sameZone. dist is nil when a position is unknown or the zones differ.
local function charDistance(a, b)
    local pa, pb = peerPos(a), peerPos(b)
    if not pa or not pb then return nil, false end
    if lower(pa.zone) ~= lower(pb.zone) then return nil, false end
    return invLogic.dist3(pa, pb), true
end

local function fmtAge(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec < 60 then return string.format('%ds ago', sec) end
    if sec < 3600 then return string.format('%dm ago', math.floor(sec / 60)) end
    return string.format('%dh ago', math.floor(sec / 3600))
end

-- Asks a box for its snapshot (rate limited; `force` bypasses the limit).
local function requestSnapshot(name, force)
    local bn = boxnet()
    if not bn or not bn.available() then return false, 'Box Network not connected' end
    if lower(name) == lower(myName()) then return false, 'that is this character' end
    local rec = netPeerRecord(name, true)
    local t = nowSec()
    if not force and rec.pendingSince and (t - rec.pendingSince) < 10 then return false, 'request in flight' end
    if not force and (t - (rec.requestedAt or -1e9)) < NET_REQUEST_MIN_SEC then return false, 'asked a moment ago' end
    rec.requestedAt = t
    rec.pendingSince = t
    rec.refused = nil
    local ok = bn.send(rec.name, 'inv:request', { want = 'all' })
    if not ok then rec.pendingSince = nil end
    return ok == true
end

local function requestAllSnapshots(force)
    local bn = boxnet()
    if not bn then return 0 end
    local n = 0
    for _, p in ipairs(bn.peers()) do
        if requestSnapshot(p.name, force) then n = n + 1 end
    end
    return n
end

-- Answers queued inv:request messages (tick, fiber): rescans when our data
-- is stale, then streams the packed snapshot in pages.
local function serveRequests()
    local queue = state.net.pendingRequests
    if #queue == 0 then return end
    state.net.pendingRequests = {}
    local bn = boxnet()
    if not bn then return end
    if not cfg.share then
        for _, name in ipairs(queue) do
            bn.send(name, 'inv:page', { refused = true, reason = 'sharing is off on ' .. myName() })
        end
        return
    end
    if (os.time() - (tonumber(state.lastScanTime) or 0)) >= NET_SNAPSHOT_MAX_AGE then
        scanner.scanAll({ yield = true })
    end
    local snap = invLogic.buildSnapshot(state, state.lastScanTime)
    local pages = invLogic.paginate(snap.items, INV_PAGE_SIZE)
    local seen = {}
    for _, name in ipairs(queue) do
        local key = lower(name)
        if not seen[key] then
            seen[key] = true
            state.net.served[key] = true
            for i, page in ipairs(pages) do
                bn.send(name, 'inv:page', {
                    gen = state.contentGen or 0, page = i, pages = #pages,
                    meta = (i == 1) and snap.meta or nil,
                    items = page,
                })
            end
            state.net.lastChangedGen = state.contentGen or 0
        end
    end
end

-- Broadcast "my items changed" once per data generation, only when some box
-- has asked for our snapshot before (viewers refresh; nobody else cares).
local function announceChanged()
    if next(state.net.served) == nil then return end
    local gen = state.contentGen or 0
    if state.net.lastChangedGen == gen then return end
    local bn = boxnet()
    if not bn or not bn.available() then return end
    state.net.lastChangedGen = gen
    bn.broadcast('inv:changed', { gen = gen })
end

-- ----------------------------------------------------------------------------
-- Give: this box hands an item to another character through the trade window
-- ----------------------------------------------------------------------------
local function tradeCleanup()
    if probe.tradeOpen() then
        pcall(function() mq.cmd('/notify TradeWnd TRDW_Cancel_Button leftmouseup') end)
        delay(400)
    end
    if probe.cursorId() > 0 then
        pcall(function() mq.cmd('/autoinventory') end)
        delay(150)
    end
end

-- Runs one give job on the fiber. Returns ok, reason.
local function runGive(job)
    local to = tostring(job.to or '')
    if to == '' then return false, 'no receiver' end
    if lower(to) == lower(myName()) then return false, 'cannot give to yourself' end
    local sp = probe.spawn(to)
    if not sp then return false, to .. ' is not in this zone' end
    if sp.dist > cfg.tradeRange then
        return false, string.format('%s is %.0f away (trade range %d)', to, sp.dist, cfg.tradeRange)
    end
    if probe.cursorId() > 0 then return false, 'the cursor is already holding an item' end
    local loc = probe.locate(job.itemId, job.notifyCmd)
    if not loc then return false, (job.name or 'item') .. ' is not in the bags any more' end
    if loc.nodrop then return false, loc.name .. ' is NO TRADE' end
    local name = loc.name ~= '' and loc.name or (job.name or 'item')

    -- Pick it up: whole stack (shift), one (ctrl) or a quantity via the dialog.
    local want = tonumber(job.count)
    local have = tonumber(loc.count) or 1
    if not loc.stackable or not want or want >= have then
        mq.cmdf('/shiftkey /itemnotify %s leftmouseup', loc.cmd)
        acceptQuantityWnd()
    elseif want <= 1 then
        mq.cmdf('/ctrlkey /itemnotify %s leftmouseup', loc.cmd)
    else
        mq.cmdf('/nomodkey /itemnotify %s leftmouseup', loc.cmd)
        if delay(600, quantityWndOpen) then
            mq.cmdf('/notify QuantityWnd QTYW_SliderInput newvalue %d', want)
            delay(100)
            mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
        end
    end
    if not delay(1500, function() return probe.cursorId() == job.itemId end) then
        tradeCleanup()
        return false, 'could not pick up ' .. name
    end

    mq.cmdf('/target id %d', sp.id)
    if not delay(1500, function() return probe.targetId() == sp.id end) then
        tradeCleanup()
        return false, 'could not target ' .. to
    end

    -- The receiver box clicks its Trade button once our window reaches it.
    local bn = boxnet()
    if bn and bn.available() then bn.send(to, 'inv:trade_accept', { name = name, count = want or have }) end

    mq.cmd('/click left target')
    if not delay(3000, probe.tradeOpen) then
        tradeCleanup()
        return false, 'the trade window did not open (out of range, or ' .. to .. ' is busy)'
    end
    delay(250)
    mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
    if not delay(12000, function() return not probe.tradeOpen() end) then
        tradeCleanup()
        return false, to .. ' did not accept the trade'
    end
    delay(300)
    if probe.cursorId() == job.itemId then
        tradeCleanup()
        return false, 'the trade was cancelled (' .. to .. ' may be full)'
    end
    return true, name
end

local function reportGive(job, ok, detail)
    local me = myName()
    local itemName = ok and detail or (job.name or 'item')
    local text
    if ok then
        text = string.format('Gave %s to %s', itemName, job.to)
    else
        text = string.format('Could not give %s to %s: %s', itemName, job.to, tostring(detail))
    end
    netLog(text, ok and 'info' or 'warn')
    chat('%s', text)
    local bn = boxnet()
    local requester = job.requestedBy
    if requester and lower(requester) ~= lower(me) and bn and bn.available() then
        bn.send(requester, 'inv:give_result', { ok = ok, reason = (not ok) and tostring(detail) or nil, name = itemName, to = job.to })
    end
end

-- Queues a give on THIS box (we hold the item). Returns ok, reason.
local function enqueueGive(job)
    local blocker = invLogic.giveBlocker(job.item or { id = job.itemId, location = job.location or 'INVENTORY', nodrop = job.nodrop })
    if blocker then return false, blocker end
    job.item = nil
    job.queuedAt = nowSec()
    table.insert(state.net.gives, job)
    netLog(string.format('Queued: %s -> %s%s', job.name or ('item ' .. tostring(job.itemId)), job.to,
        job.requestedBy and (' (asked by ' .. job.requestedBy .. ')') or ''))
    return true
end

-- Asks for `it` (mine or a peer's) to be handed to `toName`. Returns ok, why.
local function requestGive(it, toName, count)
    if not it then return false, 'no item' end
    local blocker = invLogic.giveBlocker(it)
    if blocker then return false, blocker end
    local me = myName()
    local owner = it.owner or me
    if lower(toName) == lower(owner) then return false, owner .. ' already has it' end
    local job = { itemId = it.id, notifyCmd = it.notifyCmd, name = it.name, count = count, to = toName, location = it.location, nodrop = it.nodrop }
    if lower(owner) == lower(me) then
        return enqueueGive(job)
    end
    local bn = boxnet()
    if not bn or not bn.available() then return false, 'Box Network not connected' end
    if not onlinePeer(owner) then return false, owner .. ' is not on the Box Network' end
    job.location, job.nodrop = nil, nil
    local ok = bn.send(owner, 'inv:give', job)
    if ok then netLog(string.format('Asked %s to give %s to %s', owner, it.name or 'item', toName)) end
    return ok == true, (not ok) and 'send failed' or nil
end

local function processGives()
    if state.net.activeGive then return end
    local job = table.remove(state.net.gives, 1)
    if not job then return end
    state.net.activeGive = job
    local ok, detail = runGive(job)
    state.net.activeGive = nil
    reportGive(job, ok, detail)
    scanner.scanAll({ yield = true })
    announceChanged()
    -- The receiver's snapshot (when we hold one) is out of date now.
    local rec = netPeerRecord(job.to, false)
    if rec and rec.items then rec.stale = true end
end

-- Receiver side: click Trade when the giver's window reaches us.
local function processTradeAccepts()
    local accepts = state.net.acceptTrades
    if next(accepts) == nil then return end
    local t = nowSec()
    local open = probe.tradeOpen()
    for key, a in pairs(accepts) do
        if a.lastClick and not open then
            accepts[key] = nil
            netLog(string.format('Received %s from %s', a.item or 'an item', a.from))
            chat('Received %s from %s.', a.item or 'an item', a.from)
        elseif t > a.expires then
            accepts[key] = nil
            netLog(string.format('%s never opened a trade (%s)', a.from, a.item or 'item'), 'warn')
        end
    end
    if not open then return end
    local his = lower(probe.tradeHisName())
    local a = his ~= '' and accepts[his] or nil
    if not a then return end
    if (t - (a.lastClick or -1e9)) < 1.0 then return end
    a.lastClick = t
    pcall(function() mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup') end)
end

-- ----------------------------------------------------------------------------
-- Subscriptions (handlers run in boxnet's tick: queue, never delay)
-- ----------------------------------------------------------------------------
local function senderName(sender, data)
    local n = sender and sender.character
    if type(n) ~= 'string' or n == '' then n = data and data.from end
    return type(n) == 'string' and n or ''
end

local function onRequest(data, sender)
    local from = senderName(sender, data)
    if from == '' then return end
    table.insert(state.net.pendingRequests, from)
end

local function onPage(data, sender)
    local from = senderName(sender, data)
    if from == '' or type(data) ~= 'table' then return end
    local rec = netPeerRecord(from, true)
    if data.refused then
        rec.pendingSince = nil
        rec.refused = tostring(data.reason or 'refused')
        netLog(from .. ': ' .. rec.refused, 'warn')
        return
    end
    if invLogic.mergePage(rec, data, nowSec()) then
        state.net.tableCache.key = ''
    end
end

local function onGive(data, sender)
    local from = senderName(sender, data)
    local bn = boxnet()
    if from == '' or type(data) ~= 'table' or not bn then return end
    local function refuse(reason)
        netLog(string.format('Refused give from %s: %s', from, reason), 'warn')
        bn.send(from, 'inv:give_result', { ok = false, reason = reason, name = data.name, to = data.to })
    end
    if not cfg.acceptGives then return refuse('gives are off on ' .. myName()) end
    if bn.trusted and not bn.trusted(sender, data) then return refuse('not trusted') end
    local ok, why = enqueueGive({
        itemId = tonumber(data.itemId) or 0, notifyCmd = tostring(data.notifyCmd or ''), name = tostring(data.name or ''),
        count = tonumber(data.count), to = tostring(data.to or ''), requestedBy = from,
    })
    if not ok then refuse(why or 'cannot give') end
end

local function onTradeAccept(data, sender)
    local from = senderName(sender, data)
    if from == '' then return end
    state.net.acceptTrades[lower(from)] = { from = from, item = data and data.name or nil, expires = nowSec() + TRADE_ACCEPT_SEC }
end

local function onGiveResult(data, sender)
    local from = senderName(sender, data)
    if type(data) ~= 'table' then return end
    local text
    if data.ok then
        text = string.format('%s gave %s to %s', from, tostring(data.name or 'item'), tostring(data.to or '?'))
    else
        text = string.format('%s could not give %s to %s: %s', from, tostring(data.name or 'item'), tostring(data.to or '?'), tostring(data.reason or '?'))
    end
    netLog(text, data.ok and 'info' or 'warn')
    chat('%s', text)
    for _, n in ipairs({ from, data.to }) do
        local rec = n and netPeerRecord(n, false)
        if rec and rec.items then rec.stale = true end
    end
end

local function onChanged(data, sender)
    local from = senderName(sender, data)
    local rec = from ~= '' and netPeerRecord(from, false)
    if rec and rec.items then rec.stale = true end
end

local NET_HANDLERS = {
    ['inv:request']      = onRequest,
    ['inv:page']         = onPage,
    ['inv:give']         = onGive,
    ['inv:trade_accept'] = onTradeAccept,
    ['inv:give_result']  = onGiveResult,
    ['inv:changed']      = onChanged,
}

local function dropSubscriptions()
    for _, unsub in ipairs(state.net.unsubs) do pcall(unsub) end
    state.net.unsubs = {}
    state.net.subGen = -1
end

-- (Re)subscribes whenever the boxnet plugin (re)loads.
local function ensureSubscriptions()
    local bn = boxnet()
    if not bn or type(bn.subscribe) ~= 'function' then return end
    local gen = bn.generation and bn.generation() or 0
    if state.net.subGen == gen then return end
    dropSubscriptions()
    for kind, fn in pairs(NET_HANDLERS) do
        local ok, unsub = pcall(bn.subscribe, kind, fn)
        if ok and type(unsub) == 'function' then table.insert(state.net.unsubs, unsub) end
    end
    state.net.subGen = gen
end

-- Stale / auto-refresh maintenance for the Box tab (tick).
local function refreshSnapshots()
    local bn = boxnet()
    if not bn or not ctrl.show_inv then return end
    local t = nowSec()
    if (t - (state.net.lastRefreshCheck or -1e9)) < 1.0 then return end
    state.net.lastRefreshCheck = t
    for _, p in ipairs(bn.peers()) do
        local rec = netPeerRecord(p.name, false)
        if rec and rec.items and rec.stale then
            requestSnapshot(p.name, false)
        elseif rec and rec.items and cfg.autoRefreshSec > 0 and (t - (rec.at or 0)) >= cfg.autoRefreshSec then
            requestSnapshot(p.name, false)
        end
    end
end

-- Items of every box (mine included) for the All boxes view; peers' lists are
-- shared by reference, mine are thin proxies tagged with the owner.
local function allBoxItems()
    local me = myName()
    local out = {}
    local mine = state.net.myRows
    if not mine or mine.gen ~= state.dataGen or mine.owner ~= me then
        mine = { gen = state.dataGen, owner = me, rows = {} }
        for _, it in ipairs(state.items) do
            mine.rows[#mine.rows + 1] = setmetatable({ owner = me }, { __index = it })
        end
        state.net.myRows = mine
    end
    for _, it in ipairs(mine.rows) do out[#out + 1] = it end
    for _, rec in pairs(state.net.peers) do
        for _, it in ipairs(rec.items or {}) do out[#out + 1] = it end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Box Inventories tab
-- ----------------------------------------------------------------------------
-- The popup is opened by drawGivePopup() in the scope that draws it (the
-- ImGui id stack differs between a table row and the tab that owns the popup).
function openGivePopup(it)
    state.net.givePopup = { item = it, count = tonumber(it.count) or 1, openedAt = nowSec(), dists = nil, pendingOpen = true }
end

-- Candidate receivers for the popup, with distances from the giver
-- (refreshed once a second).
local function giveCandidates(pop)
    local it = pop.item
    local me = myName()
    local owner = it.owner or me
    local t = nowSec()
    if pop.dists and (t - (pop.distsAt or 0)) < 1.0 then return pop.dists end
    local out = {}
    local names = {}
    if lower(owner) ~= lower(me) then names[#names + 1] = me end
    local bn = boxnet()
    if bn then
        for _, p in ipairs(bn.peers()) do
            if lower(p.name) ~= lower(owner) then names[#names + 1] = p.name end
        end
    end
    for _, n in ipairs(names) do
        local dist, sameZone
        if lower(owner) == lower(me) then
            local sp = probe.spawn(n)
            if sp then dist, sameZone = sp.dist, true else dist, sameZone = nil, false end
        else
            dist, sameZone = charDistance(owner, n)
        end
        out[#out + 1] = { name = n, dist = dist, sameZone = sameZone, inRange = dist ~= nil and dist <= cfg.tradeRange }
    end
    pop.dists, pop.distsAt = out, t
    return out
end

function drawGivePopup()
    local pop = state.net.givePopup
    if not pop then return end
    if pop.pendingOpen then
        pop.pendingOpen = nil
        ImGui.OpenPopup('##invGivePopup')
    end
    if not ImGui.BeginPopup('##invGivePopup') then
        state.net.givePopup = nil
        return
    end
    local it = pop.item
    local me = myName()
    local owner = it.owner or me
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], tostring(it.name or 'Item'))
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('%s | %s', owner, it.displayLocation or ''))
    local blocker = invLogic.giveBlocker(it)
    if blocker then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Cannot give: ' .. blocker)
        ImGui.EndPopup()
        return
    end
    if it.stackable and (tonumber(it.count) or 1) > 1 then
        ImGui.SetNextItemWidth(core.px(90))
        local q = ImGui.InputInt('Quantity##invGiveQty', pop.count)
        if type(q) == 'number' and q ~= pop.count then pop.count = math.max(1, math.min(tonumber(it.count) or 1, q)) end
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('of %d', it.count))
    end
    ImGui.Separator()
    ImGui.TextDisabled(string.format('Give to (trade range %d):', cfg.tradeRange))
    local cands = giveCandidates(pop)
    if #cands == 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'No other box on the network.')
    end
    for i, c in ipairs(cands) do
        ImGui.PushID(i)
        local label = c.name
        if c.dist then
            label = string.format('%s  (%.0f ft%s)', c.name, c.dist, c.inRange and '' or ', too far')
        elseif not c.sameZone then
            label = c.name .. '  (other zone / unknown)'
        end
        local col = c.inRange and GOOD or (c.sameZone and WARN or MUTED)
        if ImGui.Button('Give##give', core.px(50), core.px(20)) then
            local count = (it.stackable and (tonumber(it.count) or 1) > 1) and pop.count or nil
            local ok, why = requestGive(it, c.name, count)
            if not ok then netLog('Give not started: ' .. tostring(why), 'warn') end
            ImGui.CloseCurrentPopup()
        end
        ImGui.SameLine()
        ImGui.TextColored(col[1], col[2], col[3], col[4], label)
        if c.sameZone and not c.inRange then
            ImGui.SameLine()
            if ImGui.SmallButton('Come to ' .. owner .. '##come') then
                local bn = boxnet()
                if bn and bn.command then pcall(bn.command, c.name, 'cometo ' .. owner) end
            end
            if ImGui.IsItemHovered() then core.setTooltip(string.format('Send %s to %s with /ac cometo (MQ2Nav).', c.name, owner)) end
        end
        ImGui.PopID()
    end
    ImGui.EndPopup()
end

local function drawBoxList()
    local bn = boxnet()
    local me = myName()
    local n = state.net
    local function row(key, label, sub, tooltip)
        local sel = n.selected == key
        if ImGui.Selectable(label .. '##box' .. key, sel) then
            n.selected = key
            n.tableCache.key = ''
            -- Selecting a box fetches what we do not have yet.
            if key == 'ALL' then
                for _, p in ipairs(bn and bn.peers() or {}) do
                    local r = netPeerRecord(p.name, true)
                    if not r.items then requestSnapshot(p.name, false) end
                end
            elseif key ~= lower(me) then
                local r = netPeerRecord(key, false)
                if r and not r.items then requestSnapshot(r.name, false) end
            end
        end
        if tooltip and ImGui.IsItemHovered() then core.setTooltip(tooltip) end
        if sub then ImGui.TextDisabled('   ' .. sub) end
    end
    row('ALL', 'All boxes', string.format('%d character(s)', 1 + #(bn and bn.peers() or {})), 'Every box in one list - search across all inventories.')
    row(lower(me), me .. ' (me)', string.format('%d items | %d free', state.counts.total or 0, state.counts.freeInvSlots or 0))
    local peers = bn and bn.peers() or {}
    for _, p in ipairs(peers) do
        local rec = netPeerRecord(p.name, true)
        local hb = p.hb or {}
        local dist = charDistance(me, p.name)
        local sub
        if rec.items then
            local c = rec.meta and rec.meta.counts or {}
            sub = string.format('%d items | %d free | %s%s', #rec.items, c.freeInvSlots or 0, fmtAge(nowSec() - (rec.at or 0)), rec.stale and ' *' or '')
        elseif rec.refused then
            sub = rec.refused
        elseif rec.pendingSince then
            sub = 'fetching...'
        else
            sub = 'no snapshot yet'
        end
        local where = tostring(hb.zone or '?') .. (dist and string.format(' | %.0f ft', dist) or '')
        row(lower(p.name), p.name, where .. '\n   ' .. sub,
            string.format('%s - %s\n%s\nClick to view; Refresh asks the box for a fresh snapshot.', p.name,
                type(hb.classes) == 'table' and table.concat(hb.classes, '/') or '?', sub))
    end
    -- Boxes we have a snapshot of but that are offline now
    for key, rec in pairs(n.peers) do
        local online = false
        for _, p in ipairs(peers) do if lower(p.name) == key then online = true break end end
        if not online and rec.items then
            row(key, rec.name .. ' (offline)', string.format('%d items | %s', #rec.items, fmtAge(nowSec() - (rec.at or 0))))
        end
    end
end

local function boxTableRows()
    local n = state.net
    local gens = {}
    for key, rec in pairs(n.peers) do gens[#gens + 1] = key .. '=' .. tostring(rec.gen or 0) .. (rec.items and #rec.items or 0) end
    table.sort(gens)
    local key = table.concat({ n.selected, n.search, n.loc, tostring(state.dataGen), table.concat(gens, ',') }, '|')
    if n.tableCache.key == key then return n.tableCache.rows end
    local rows = invLogic.filterBoxItems(allBoxItems(), n.search, n.loc, n.selected)
    n.tableCache.key = key
    n.tableCache.rows = rows
    return rows
end

local function drawBoxItemsTable(rows, showOwner)
    local cols = showOwner and 7 or 6
    local flags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if not ImGui.BeginTable('BoxItemsTable', cols, flags, ImVec2(0, -core.px(96))) then return end
    if showOwner then ImGui.TableSetupColumn('Character', ImGuiTableColumnFlags.WidthFixed, core.px(90)) end
    ImGui.TableSetupColumn('Location', ImGuiTableColumnFlags.WidthFixed, core.px(110))
    ImGui.TableSetupColumn('Item Name', ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, core.px(55))
    ImGui.TableSetupColumn('Wt', ImGuiTableColumnFlags.WidthFixed, core.px(45))
    ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.WidthFixed, core.px(75))
    ImGui.TableSetupColumn('Give', ImGuiTableColumnFlags.WidthFixed, core.px(50))
    ImGui.TableHeadersRow()

    local function drawRow(idx, it)
        ImGui.TableNextRow()
        ImGui.PushID(idx)
        local col = 0
        if showOwner then
            ImGui.TableSetColumnIndex(0)
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(it.owner or ''))
            col = 1
        end
        ImGui.TableSetColumnIndex(col)
        local locColor = it.location == 'INVENTORY' and ARC or ((it.location == 'BANK' or it.location == 'SHAREDBANK') and GOLD or (it.location == 'WORN' and GOOD or WARN))
        ImGui.TextColored(locColor[1], locColor[2], locColor[3], locColor[4], it.displayLocation or '')
        ImGui.TableSetColumnIndex(col + 1)
        if drawTableItemIcon(it.icon, 18) then ImGui.SameLine() end
        local nameCol = it.nodrop and MUTED or (it.clicky and GOLD or (it.tradeskill and ARC or GOOD))
        ImGui.TextColored(nameCol[1], nameCol[2], nameCol[3], nameCol[4], it.name or 'Unknown')
        if ImGui.IsItemHovered() then
            UI.drawTooltip(it)
            if ImGui.IsItemClicked(1) then openDatabaseCard(it) end
        end
        ImGui.TableSetColumnIndex(col + 2)
        if it.stackable then ImGui.Text(it.qtyText or tostring(it.count or 1)) else ImGui.TextDisabled('1') end
        ImGui.TableSetColumnIndex(col + 3)
        ImGui.Text(it.weightText or string.format('%.1f', it.weight or 0))
        ImGui.TableSetColumnIndex(col + 4)
        ImGui.TextDisabled(it.valueText or invLogic.formatMoney(it.value or 0))
        ImGui.TableSetColumnIndex(col + 5)
        local blocker = invLogic.giveBlocker(it)
        if blocker then ImGui.BeginDisabled() end
        if ImGui.SmallButton('Give') then openGivePopup(it) end
        if blocker then
            ImGui.EndDisabled()
        elseif ImGui.IsItemHovered() then
            core.setTooltip('Hand this item to another character on the Box Network.')
        end
        ImGui.PopID()
    end

    local clipper = nil
    local ClipperClass = ImGui.ListClipper or (mq.imgui and mq.imgui.ListClipper) or _G['ImGuiListClipper']
    if ClipperClass and ClipperClass.new then
        local okC, c = pcall(ClipperClass.new)
        if okC and c then clipper = c end
    end
    if clipper then
        clipper:Begin(#rows)
        while clipper:Step() do
            for idx = clipper.DisplayStart + 1, clipper.DisplayEnd do
                if rows[idx] then drawRow(idx, rows[idx]) end
            end
        end
        clipper:End()
    else
        for idx, it in ipairs(rows) do drawRow(idx, it) end
    end
    ImGui.EndTable()
end

-- A peer's bags / bank as grids (read-only; click a slot to give).
local function drawPeerGrid(rec)
    local ctx = {
        palette = 'inv', idPrefix = 'r' .. lower(rec.name), label = 'Bag', interactive = false,
        onClick = function(it, _, _, button)
            if button == 1 and shiftHeld() then openDatabaseCard(it) return end
            openGivePopup(it)
        end,
    }
    ImGui.BeginChild('PeerGrid', ImVec2(0, -core.px(96)), true)
    local c = rec.containers or {}
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("%s'S BAGS", string.upper(rec.name)))
    ImGui.Separator()
    for _, bag in ipairs(c.inventory or {}) do
        if (bag.capacity or 0) > 0 then
            drawBagTitle('Bag', bag)
            UI.drawBagGrid(bag, ctx)
            ImGui.Dummy(0, core.px(6))
        end
    end
    if #(c.bank or {}) > 0 or #(c.sharedBank or {}) > 0 then
        ImGui.Dummy(0, core.px(4))
        local meta = rec.meta or {}
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format('BANK (%s)', meta.bankLive and 'live' or ('cached ' .. tostring(meta.bankSync or '?'))))
        ImGui.Separator()
        local bankCtx = { palette = 'bank', idPrefix = 'rb' .. lower(rec.name), label = 'Bank', interactive = false, hint = 'Bank items must be moved to a bag before they can be given.', onClick = ctx.onClick }
        for _, bag in ipairs(c.bank or {}) do
            if (bag.capacity or 0) > 0 then
                drawBagTitle('Bank', bag)
                UI.drawBagGrid(bag, bankCtx)
                ImGui.Dummy(0, core.px(6))
            end
        end
        local sharedCtx = { palette = 'bank', idPrefix = 'rs' .. lower(rec.name), label = 'Shared', interactive = false, hint = bankCtx.hint, onClick = ctx.onClick }
        for _, bag in ipairs(c.sharedBank or {}) do
            if (bag.capacity or 0) > 0 then
                drawBagTitle('Shared', bag)
                UI.drawBagGrid(bag, sharedCtx)
                ImGui.Dummy(0, core.px(6))
            end
        end
    end
    ImGui.EndChild()
end

local function drawTransferLog()
    local n = state.net
    ImGui.Separator()
    local queued = #n.gives + (n.activeGive and 1 or 0)
    if n.activeGive then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('Giving %s to %s...', n.activeGive.name or 'item', n.activeGive.to))
        ImGui.SameLine()
    elseif queued > 0 then
        ImGui.TextDisabled(string.format('%d give(s) queued', queued))
        ImGui.SameLine()
    end
    if queued > 0 then
        if ImGui.SmallButton('Clear queue##invGiveClear') then n.gives = {} end
        ImGui.SameLine()
    end
    ImGui.TextDisabled('Transfers:')
    ImGui.BeginChild('InvNetLog', ImVec2(0, core.px(60)), false)
    for i, e in ipairs(n.log) do
        if i > 12 then break end
        local col = e.level == 'warn' and WARN or (e.level == 'error' and ERR or MUTED)
        ImGui.TextColored(col[1], col[2], col[3], col[4], string.format('[%s] %s', e.time, e.text))
    end
    if #n.log == 0 then ImGui.TextDisabled('No transfers yet.') end
    ImGui.EndChild()
end

function UI.drawBoxTab()
    local bn = boxnet()
    if not bn then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'The Box Network plugin (boxnet) is not loaded or is disabled.')
        ImGui.TextDisabled('Enable it on Settings -> Plugins to see your other characters\' inventories here.')
        return
    end
    if not bn.available() then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'Box Network is not connected (open the Box Net window for details).')
        return
    end
    local n = state.net
    local me = myName()
    -- First look at the tab: ask every box once.
    if not n.tabSeen then
        n.tabSeen = true
        requestAllSnapshots(false)
    end

    -- Toolbar
    if ImGui.Button('Refresh##invNetRefresh', core.px(70), core.px(22)) then
        if n.selected == 'ALL' then requestAllSnapshots(true)
        elseif n.selected ~= lower(me) then requestSnapshot(n.selected, true) end
    end
    if ImGui.IsItemHovered() then core.setTooltip('Ask the selected box (or every box) for a fresh inventory snapshot.') end
    ImGui.SameLine()
    if ImGui.Button('Refresh All##invNetRefreshAll', core.px(80), core.px(22)) then requestAllSnapshots(true) end
    ImGui.SameLine(0, core.px(12))
    ImGui.SetNextItemWidth(core.px(140))
    local auto, autoChanged = ImGui.SliderInt('Auto-refresh (s)##invNetAuto', cfg.autoRefreshSec, 0, 120)
    if autoChanged and type(auto) == 'number' then
        cfg.autoRefreshSec = auto
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Re-request open snapshots this often while this window is open. 0 = only on Refresh (boxes still announce their changes).') end
    ImGui.SameLine(0, core.px(12))
    ImGui.SetNextItemWidth(core.px(200))
    local newSearch, searchChanged = ImGui.InputTextWithHint('##invNetSearch', 'Search every box...', n.search or '')
    if searchChanged and type(newSearch) == 'string' then n.search = newSearch end
    ImGui.SameLine()
    if ImGui.Button('X##invNetClear', core.px(22), core.px(22)) then n.search = '' end
    ImGui.SameLine(0, core.px(12))
    for _, l in ipairs({ { 'ALL', 'All' }, { 'INVENTORY', 'Bags' }, { 'BANK', 'Bank' }, { 'WORN', 'Worn' } }) do
        local sel = n.loc == l[1]
        if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.16, 0.50, 0.75, 0.8) end
        if ImGui.Button(l[2] .. '##invNetLoc' .. l[1]) then n.loc = l[1] end
        if sel then ImGui.PopStyleColor(1) end
        ImGui.SameLine()
    end
    ImGui.SameLine(0, core.px(12))
    local canGrid = n.selected ~= 'ALL' and n.selected ~= lower(me)
    if not canGrid then n.view = 'list' end
    if not canGrid then ImGui.BeginDisabled() end
    if ImGui.RadioButton('List##invNetList', n.view == 'list') then n.view = 'list' end
    ImGui.SameLine()
    if ImGui.RadioButton('Bags##invNetGrid', n.view == 'grid') then n.view = 'grid' end
    if not canGrid then ImGui.EndDisabled() end
    ImGui.Separator()

    -- Left: boxes; right: items
    ImGui.BeginChild('InvBoxList', ImVec2(core.px(230), 0), true)
    drawBoxList()
    ImGui.EndChild()
    ImGui.SameLine()
    ImGui.BeginChild('InvBoxItems', ImVec2(0, 0), false)
    local rec = (n.selected ~= 'ALL' and n.selected ~= lower(me)) and netPeerRecord(n.selected, false) or nil
    if rec and not rec.items then
        if rec.pendingSince then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'Waiting for ' .. rec.name .. '\'s snapshot...')
        elseif rec.refused then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], rec.name .. ': ' .. rec.refused)
        else
            ImGui.TextDisabled('No snapshot from ' .. rec.name .. ' yet.')
            ImGui.SameLine()
            if ImGui.SmallButton('Fetch##invNetFetch') then requestSnapshot(rec.name, true) end
        end
        if onlinePeer(rec.name) == nil then ImGui.TextDisabled(rec.name .. ' is not on the network right now.') end
        ImGui.Dummy(0, core.px(4))
    elseif rec then
        local meta = rec.meta or {}
        local c = meta.counts or {}
        ImGui.TextDisabled(string.format('%s: %d items | bags %d/%d free | bank %s | %s%s', rec.name, #rec.items,
            c.freeInvSlots or 0, c.totalInvSlots or 0, meta.bankLive and 'live' or ('cached ' .. tostring(meta.bankSync or '?')),
            fmtAge(nowSec() - (rec.at or 0)), rec.stale and ' (changed since - refreshing)' or ''))
    end
    if n.view == 'grid' and rec and rec.items then
        drawPeerGrid(rec)
    else
        local rows = boxTableRows()
        ImGui.TextDisabled(string.format('Showing %d item(s)', #rows))
        drawBoxItemsTable(rows, n.selected == 'ALL')
    end
    drawTransferLog()
    drawGivePopup()
    ImGui.EndChild()
end

local function DrawInventoryManagerUI()
    if not ctrl.show_inv then return end

    core.pushTheme()

    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(core.px(780), core.px(520), ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end

    core.preBeginWindow('inventory')
    local open, draw = ImGui.Begin("Triune Inventory & Bank Manager###TriuneInventoryManager", ctrl.show_inv, core.windowFlags and core.windowFlags('inventory', windowFlags) or windowFlags)
    if not open then
        ctrl.show_inv = false
        if core.preEndWindow then core.preEndWindow('inventory', false) end
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end

    if draw then
        core.postBeginWindow('inventory')
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

            if ImGui.BeginTabItem("Box Inventories##tabBoxes") then
                UI.drawBoxTab()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Settings & Cache##tabSet") then
                UI.drawSettings()
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end
    end

    if core.preEndWindow then core.preEndWindow('inventory', false) end
    ImGui.End()
    core.popTheme()
end

-- ============================================================================
-- Fiber body: one pass of the old main loop (queued action + background scan)
-- ============================================================================
local function tick()
    -- Process queued action
    local act = state.pendingAction
    if act then
        state.pendingAction = nil
        local actType = tostring(act.type or '')

        if actType == 'rescan' then
            if act.statusMsg then state.statusMsg = act.statusMsg end
        elseif actType == 'clear_bank_cache' then
            local p = getBankCachePath()
            pcall(os.remove, p)
            inMemoryBankCache = nil
            lastSavedBankCount = -1
            state.statusMsg = "Bank cache removed."
        elseif actType == 'inspect' and act.item then
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
            notifyLeft(tostring(act.notifyCmd))
        elseif actType == 'move' and act.fromCmd and act.toCmd then
            notifyLeft(act.fromCmd)
            delay(40)
            if cursorMatches(act.fromId) then
                notifyLeft(act.toCmd)
            end
        elseif actType == 'autoinv' then
            pcall(function()
                mq.cmd('/autoinventory')
            end)
        elseif actType == 'combine_stacks' then
            local dups = invLogic.findDuplicateStacks(state.items)
            local item = nil
            if act.item then
                local key = tostring(act.item.id or act.item.name)
                for _, d in ipairs(dups) do
                    if tostring(d.id or d.name) == key then
                        item = d
                        break
                    end
                end
            end
            if not item and state.combineAllActive and #dups > 0 then
                item = dups[1]
            end

            local allowBank = state.bankLive == true
            local move = invLogic.findNextCombineMove(item, allowBank)
            if not move and state.combineAllActive then
                for _, d in ipairs(dups) do
                    move = invLogic.findNextCombineMove(d, allowBank)
                    if move then
                        item = d
                        break
                    end
                end
            end

            -- Attempt cap: stop after 50 moves, or 3 consecutive cycles that
            -- keep producing the same move (nothing is actually merging).
            local MAX_COMBINE_MOVES, MAX_NO_PROGRESS = 50, 3
            if move then
                local key = tostring(move.fromCmd) .. '>' .. tostring(move.toCmd)
                if key == state.combineLastKey then
                    state.combineNoProgress = (state.combineNoProgress or 0) + 1
                else
                    state.combineNoProgress = 0
                end
                state.combineLastKey = key
                state.combineMoveCount = (state.combineMoveCount or 0) + 1
                if state.combineMoveCount > MAX_COMBINE_MOVES or state.combineNoProgress >= MAX_NO_PROGRESS then
                    state.statusMsg = 'Combine stopped: no progress or move limit reached'
                    move = nil
                end
            end

            if move then
                local expectedId = (move.from and move.from.id) or (item and item.id) or nil
                notifyLeft(move.fromCmd)
                delay(80)
                local proceed = cursorMatches(expectedId)
                if proceed then
                    notifyLeft(move.toCmd)
                    delay(80)
                end
                local hasCursor = false
                pcall(function()
                    hasCursor = mq.TLO.Cursor() and (mq.TLO.Cursor.ID() or 0) > 0
                end)
                if hasCursor then
                    pcall(function() mq.cmd('/autoinventory') end)
                    delay(100)
                end
                if not proceed then
                    state.combineAllActive = false
                elseif state.combineAllActive then
                    state.pendingAction = { type = 'combine_stacks' }
                else
                    state.pendingAction = { type = 'combine_stacks', item = item }
                end
            else
                state.combineAllActive = false
            end
        elseif actType == 'sort_bag' then
            local moves = act.moves or {}
            local idx = tonumber(act.index) or 1
            local step = moves[idx]
            if step and step.fromCmd and step.toCmd then
                local aborted = false
                notifyLeft(step.fromCmd)
                delay(80)
                if cursorMatches(step.fromId) then
                    notifyLeft(step.toCmd)
                    if step.completeSwap then
                        delay(80)
                        -- After swapping onto an occupied slot the cursor should now
                        -- hold the displaced item; only place it back if it does.
                        if cursorMatches(step.destId) then
                            notifyLeft(step.fromCmd)
                        else
                            aborted = true
                        end
                    end
                else
                    aborted = true
                end
                delay(80)
                local hasCursor = false
                pcall(function()
                    hasCursor = mq.TLO.Cursor() and (mq.TLO.Cursor.ID() or 0) > 0
                end)
                if hasCursor then
                    pcall(function() mq.cmd('/autoinventory') end)
                    delay(100)
                end
                if not aborted and idx < #moves then
                    state.pendingAction = { type = 'sort_bag', moves = moves, index = idx + 1 }
                end
            end
        end
        if actType == 'pickup' or actType == 'move' then
            delay(20)
        elseif actType ~= 'rescan' and actType ~= 'clear_bank_cache' then
            delay(100)
        end
        scanner.scanAll({ yield = true })
    end

    -- Periodic background scan
    if state.autoScan then
        local now = os.time()
        local interval = tonumber(state.autoScanInterval) or 15
        if (now - (tonumber(state.lastScanTime) or 0)) >= interval then
            scanner.scanAll({ yield = true })
        end
    end

    -- Box Inventories: serve snapshot requests, run queued gives, accept the
    -- trades we were told about, keep open snapshots fresh.
    ensureSubscriptions()
    if boxnet() then
        serveRequests()
        processTradeAccepts()
        processGives()
        announceChanged()
        refreshSnapshots()
    end
end

-- ============================================================================
-- Plugin lifecycle
-- ============================================================================
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_inv == nil then ctrl.show_inv = false end
    state.pendingAction = nil
    state.combineAllActive = false
    state.lastScanTime = 0
end

function plugin.onDestroy()
    state.pendingAction = nil
    state.combineAllActive = false
    state.net.gives = {}
    state.net.activeGive = nil
    state.net.pendingRequests = {}
    dropSubscriptions()
end

function plugin.onSaveSettings()
    return {
        autoScan         = state.autoScan == true,
        autoScanInterval = tonumber(state.autoScanInterval) or 15,
        share            = cfg.share == true,
        acceptGives      = cfg.acceptGives == true,
        tradeRange       = tonumber(cfg.tradeRange) or 15,
        autoRefreshSec   = tonumber(cfg.autoRefreshSec) or 30,
        announce         = cfg.announce == true,
    }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.autoScan ~= nil then state.autoScan = (s.autoScan == true) end
    if type(s.autoScanInterval) == 'number' then state.autoScanInterval = math.max(5, math.min(60, math.floor(s.autoScanInterval))) end
    if s.share ~= nil then cfg.share = (s.share == true) end
    if s.acceptGives ~= nil then cfg.acceptGives = (s.acceptGives == true) end
    if type(s.tradeRange) == 'number' then cfg.tradeRange = math.max(5, math.min(50, math.floor(s.tradeRange))) end
    if type(s.autoRefreshSec) == 'number' then cfg.autoRefreshSec = math.max(0, math.min(120, math.floor(s.autoRefreshSec))) end
    if s.announce ~= nil then cfg.announce = (s.announce == true) end
end

function plugin.onTick()
    if not core then return end
    refresh()
    -- First scan happens lazily when the window is opened (the standalone
    -- script scanned at launch); background auto-scan keeps it fresh after.
    if ctrl.show_inv and (tonumber(state.lastScanTime) or 0) == 0 then
        scanner.scanAll({ yield = true })
    end
    tick()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    DrawInventoryManagerUI()
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    core.accent(GOLD, 'Inventory & Bank Manager')
    local isWinOpen = (ctrl.show_inv == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##invToggleWin', core.px(250), core.px(24)) then
        ctrl.show_inv = not isWinOpen
        core.saveLoadout(true)
    end
    if ImGui.Button('Rescan Now##invRescan', core.px(120), core.px(22)) then
        state.pendingAction = { type = 'rescan' }
    end
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('%d items | Bank: %s | %s', state.counts.total or 0,
        state.bankLive and 'live' or ('cached ' .. tostring(state.bankLastSync)), tostring(state.statusMsg or '')))
    UI.drawNetSettings()
end

-- Finds one of my items by id or (partial, case-insensitive) name for the
-- give command: exact name first, then a unique prefix / substring match.
local function findMyItem(text)
    text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return nil, 'no item named' end
    local id = tonumber(text)
    local exact, partial = nil, {}
    for _, it in ipairs(state.items) do
        if it.location == 'INVENTORY' or it.location == 'WORN' then
            if id and it.id == id then return it end
            local n = lower(it.name)
            if n == lower(text) then exact = exact or it
            elseif n:find(lower(text), 1, true) then partial[#partial + 1] = it end
        end
    end
    if exact then return exact end
    if #partial == 1 then return partial[1] end
    if #partial > 1 then return nil, #partial .. ' items match "' .. text .. '" - be more specific' end
    return nil, 'no item matching "' .. text .. '" in the bags'
end

-- /ac inv                              -> toggle the window
-- /ac inv give <Name> <item|id> [qty]   -> hand one of my items to a box
-- /ac inv find <text>                   -> search every box's snapshot
-- /ac inv refresh [Name]                -> ask the boxes for fresh snapshots
function plugin.onCommand(cmd, args)
    if cmd ~= 'inv' and cmd ~= 'inventory' and cmd ~= 'invui' and cmd ~= 'bank' then return false end
    refresh()
    local sub = lower(args and args[2] or '')
    if sub == 'give' then
        local to = tostring(args[3] or '')
        -- A trailing number is the quantity only when something precedes it
        -- (so "give Bob 1234" is item id 1234, "give Bob Peridot 5" is five).
        local qty = (#args >= 5) and tonumber(args[#args]) or nil
        local last = qty and (#args - 1) or #args
        local text = table.concat(args, ' ', 4, last)
        if to == '' or text == '' then
            print('\ay[Triune Inv]\ax usage: /ac inv give <Name> <item name|id> [quantity]')
            return true
        end
        if (tonumber(state.lastScanTime) or 0) == 0 then scanner.scanAll() end
        local it, why = findMyItem(text)
        if not it then
            print('\ar[Triune Inv]\ax ' .. tostring(why))
            return true
        end
        local ok, err = requestGive(it, to, qty)
        if ok then
            print(string.format('\ag[Triune Inv]\ax Giving %s to %s.', it.name, to))
        else
            print(string.format('\ar[Triune Inv]\ax Cannot give %s: %s', it.name, tostring(err)))
        end
        return true
    elseif sub == 'find' then
        local text = table.concat(args, ' ', 3)
        if text == '' then
            print('\ay[Triune Inv]\ax usage: /ac inv find <text>')
            return true
        end
        if (tonumber(state.lastScanTime) or 0) == 0 then scanner.scanAll() end
        local rows = invLogic.filterBoxItems(allBoxItems(), text, 'ALL', 'ALL')
        print(string.format('\ag[Triune Inv]\ax %d match(es) for "%s" across %d box snapshot(s):', #rows, text, 1 + (function() local n = 0 for _, r in pairs(state.net.peers) do if r.items then n = n + 1 end end return n end)()))
        for i, it in ipairs(rows) do
            if i > 25 then print('  ...') break end
            print(string.format('  \ay%s\ax  %s  \at%s\ax%s', it.owner or '?', it.displayLocation or '', it.name or '?', it.stackable and (' x' .. tostring(it.count or 1)) or ''))
        end
        return true
    elseif sub == 'refresh' then
        local name = args[3]
        local n = name and (requestSnapshot(name, true) and 1 or 0) or requestAllSnapshots(true)
        print(string.format('\ag[Triune Inv]\ax Asked %d box(es) for a fresh inventory snapshot.', n))
        return true
    end
    ctrl.show_inv = not ctrl.show_inv
    core.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Inventory & Bank Manager %s.', ctrl.show_inv and 'OPENED' or 'CLOSED'))
    return true
end

plugin.help = {
    '  \ag/ac inv | inventory | bank\ax - Toggle the Inventory & Bank Manager window',
    '  \ag/ac inv give <Name> <item|id> [qty]\ax - Hand one of your items to another box (trade window)',
    '  \ag/ac inv find <text>\ax - Search every box\'s inventory snapshot for an item',
    '  \ag/ac inv refresh [Name]\ax - Ask your other boxes for fresh inventory snapshots',
}

-- Exposed for tests
plugin.state = state
plugin.cfg = cfg
plugin.invLogic = invLogic
plugin.scanner = scanner
plugin.tick = tick
plugin.probe = probe
plugin.net = {
    handlers = NET_HANDLERS,
    requestSnapshot = requestSnapshot,
    requestGive = requestGive,
    enqueueGive = enqueueGive,
    runGive = runGive,
    processGives = processGives,
    processTradeAccepts = processTradeAccepts,
    serveRequests = serveRequests,
    announceChanged = announceChanged,
    ensureSubscriptions = ensureSubscriptions,
    allBoxItems = allBoxItems,
}

return plugin
