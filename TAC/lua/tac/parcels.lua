---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ============================================================================
-- TAC/lua/tac/parcels.lua — Triune Parcel Helper Plugin
-- ============================================================================
-- Two jobs:
--
--  1. Parcel notifier. ${Me.ParcelStatus} is the exact field that drives the
--     client's PW_ParcelsIcon / PW_ParcelsOverLimitIcon on the player window
--     (0 = none, 1 = parcels waiting, 2 = over the mailbox limit). The server
--     pushes it on zone-in, when a parcel arrives while online, and after every
--     send / retrieve. The client is never told a count, only the status, so
--     the count shown comes from the server's chat lines ("You have N parcels
--     in your mailbox...") and is decremented per successful retrieve.
--     The Unit Frames HUD reads plugin.getStatus() for its badge.
--
--  2. Collect All. The Merchant TLO only sees the buy page, so parcels are
--     driven through the Window TLO: MerchantWnd/MW_MerchantSubwindows is the
--     tab box (page 3 = "Parcels"), MW_ItemListMail the parcel list and
--     MW_Retrieve_Button the retrieve button. One retrieve per loop step,
--     waiting for the row to leave the list or for the server's failure line
--     (inventory full / duplicate lore), so a stuck parcel never spins forever.
--
-- Runs on its own fiber (hasThread) so the retrieve loop can core.delay()
-- between clicks without stalling the combat loop.
-- ============================================================================

local plugin = {
    id                 = 'parcels',
    name               = 'Parcel Helper',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Parcel delivery notifier (HUD badge) and one-click Collect All at parcel merchants.',
    defaultEnabled     = true,
    tickInterval       = 0.1,
    runOutOfCombatOnly = false,
    hasThread          = true,
    window             = { label = 'Parcels', tooltip = 'Toggles the Parcel Helper window (parcels plugin).', flag = 'show_parcels', key = 'parcels', desc = 'Parcel deliveries notifier & Collect All at parcel merchants', headerButton = false, order = 95 },
}

local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

-- Window TLO paths (EQUI_MerchantWnd.xml / EQUI_PlayerWindow.xml ScreenIDs)
local MERCHANT_WND   = 'MerchantWnd'
local TAB_BOX        = 'MerchantWnd/MW_MerchantSubwindows'
local PARCEL_LIST    = 'MerchantWnd/MW_ItemListMail'
local RETRIEVE_BTN   = 'MerchantWnd/MW_Retrieve_Button'
local PARCEL_TAB_IDX = 3          -- MW_PurchasePage, MW_RecoveryPage, MW_MailPage
local PARCEL_TAB_NAME = 'Parcels'

-- MW_ItemListMail columns (1-based). The XML defines 6 columns with no
-- labels; the names here are the working assumption and are only used for
-- headers/keys, never for logic.
local LIST_COLS = { { 2, 'Item' }, { 3, 'Qty' }, { 4, 'Price' }, { 5, 'From' }, { 6, 'Note' } }
local COL_NAME, COL_QTY, COL_PRICE, COL_FROM, COL_NOTE = 2, 3, 4, 5, 6

-- Client string ids the server uses (eqstr_us.txt):
--   6465 You have received a new parcel delivery!
--   6471 %1 hands you the %2 that was sent from %3.
--   6472 %1 hands you the stack of %2 %3 that was sent from %4.
--    790 %1 tells you, 'Your inventory appears full!  Unable to retrieve parceled item.'
--    290 Duplicate lore items are not allowed.
--    737 Duplicate lore items are not allowed! Your duplicate %1 has been deleted!
--   5433/5434 You currently have %1 parcels in your mail and are ... over the limit ...
-- plus EQEmu's own: "You have N parcels in your mailbox. Please visit a parcel
-- merchant soon." and "You have reached the limit of N parcels in your mailbox."

local STATUS_NONE, STATUS_HAS, STATUS_OVER = 0, 1, 2
local STATUS_POLL_SEC = 0.5
local MERCHANT_POLL_SEC = 0.25
local NEAREST_POLL_SEC = 2.0
local NEAREST_SCAN_MAX = 40       -- NearestSpawn(n, 'npc merchant') rows walked
local RETRIEVE_TIMEOUT_MS = 3000
local TAB_SWITCH_TIMEOUT_MS = 750
local LIST_POPULATE_TIMEOUT_MS = 1500
local BETWEEN_RETRIEVES_MS = 200
local MAX_RETRIEVES_PER_RUN = 250
local MAX_LOG = 60

local state = {
    -- notifier
    status        = STATUS_NONE,
    statusAt      = 0,          -- os.clock of last status change
    count         = nil,        -- parcels waiting when the server told us; nil = unknown
    limit         = nil,        -- mailbox limit when the server mentioned it
    lastArrivalAt = 0,
    -- merchant window snapshot
    merchantOpen  = false,
    merchantName  = '',
    isParcelMerchant = false,
    tabIndex      = 0,
    tabCount      = 0,
    rows          = {},         -- { key, name, qty, from, note }
    listCount     = 0,
    lastMerchantPollAt = 0,
    -- nearest parcel merchant (out of the merchant window)
    nearest       = nil,        -- { name, id, dist }
    lastNearestAt = 0,
    -- collector
    collecting    = false,
    stopRequested = false,
    progress      = '',
    current       = nil,        -- row being retrieved
    retrieved     = 0,
    skipped       = 0,
    lastResult    = nil,        -- 'delivered' | 'invfull' | 'duplore' (set by chat events)
    lastDelivered = nil,        -- { item, from } from the last delivered line
    lastRunSummary = '',
    log           = {},         -- newest first: { time, text, kind }
    -- window auto-open bookkeeping
    autoOpened    = false,
    registeredEvents = {},
    debug         = false,
}

local settings = {
    autoOpenAtMerchant = true,   -- pop the window when a parcel merchant window opens
    hudBadge           = true,   -- Unit Frames badge (read by hud_unitframes)
    chatSummary        = true,   -- one chat line at the end of a Collect All run
    announceArrivals   = false,  -- extra chat line on status change (the client already prints one)
}

local function refresh()
    if not core then return end
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

local function timeStr()
    return os.date('%H:%M:%S')
end

local function addLog(text, kind)
    table.insert(state.log, 1, { time = timeStr(), text = text, kind = kind or 'info' })
    while #state.log > MAX_LOG do table.remove(state.log) end
end

local function say(fmt, ...)
    print(string.format('\ag[Triune Parcels]\ax ' .. fmt, ...))
end

local function windowOpen(path)
    local open = false
    pcall(function()
        local w = mq.TLO.Window(path)
        open = (w and w.Open()) == true
    end)
    return open
end

local function windowInt(path, member)
    local v = 0
    pcall(function()
        local w = mq.TLO.Window(path)
        if w and w[member] then v = tonumber(w[member]()) or 0 end
    end)
    return v
end

local function listCell(row, col)
    local s = ''
    pcall(function()
        local v = mq.TLO.Window(PARCEL_LIST).List(row, col)()
        if v ~= nil then s = tostring(v) end
    end)
    return s
end

local function rowKey(name, qty, from, note)
    return table.concat({ name or '', qty or '', from or '', note or '' }, '|')
end

-- ---------------------------------------------------------------------------
-- Notifier: Me.ParcelStatus + chat-derived count
-- ---------------------------------------------------------------------------
local lastStatusPollAt = 0

local function statusLabel(st, count)
    if st == STATUS_OVER then
        return count and string.format('%d parcels - OVER LIMIT', count) or 'Parcels OVER LIMIT'
    elseif st == STATUS_HAS then
        if count and count > 0 then
            return string.format('%d parcel%s waiting', count, count == 1 and '' or 's')
        end
        return 'Parcels waiting'
    end
    return 'No parcels'
end

local function setStatus(st)
    st = tonumber(st) or STATUS_NONE
    if st == state.status then return end
    local prev = state.status
    state.status = st
    state.statusAt = os.clock()
    if st == STATUS_NONE then state.count = 0 end
    if state.debug then core.log.debug('parcels', 'ParcelStatus %d -> %d', prev, st) end
    if settings.announceArrivals and st > prev then
        say('%s. Visit a parcel merchant to collect.', statusLabel(st, state.count))
    end
end

local function pollStatus(force)
    local now = os.clock()
    if not force and (now - lastStatusPollAt) < STATUS_POLL_SEC then return end
    lastStatusPollAt = now
    pcall(function()
        local v = mq.TLO.Me.ParcelStatus
        if v then setStatus(v()) end
    end)
end

-- ---------------------------------------------------------------------------
-- Merchant window snapshot
-- ---------------------------------------------------------------------------
local function readRows()
    local rows = {}
    local n = windowInt(PARCEL_LIST, 'Items')
    for r = 1, n do
        local name = listCell(r, COL_NAME)
        local qty = listCell(r, COL_QTY)
        local price = listCell(r, COL_PRICE)
        local from = listCell(r, COL_FROM)
        local note = listCell(r, COL_NOTE)
        rows[#rows + 1] = { row = r, name = name, qty = qty, price = price, from = from, note = note, key = rowKey(name, qty, from, note) }
    end
    return rows, n
end

local function merchantSurname()
    local s = ''
    pcall(function()
        local m = mq.TLO.Merchant
        if m and m.Surname then s = tostring(m.Surname() or '') end
    end)
    if s == '' or s == 'NULL' then
        pcall(function()
            local t = mq.TLO.Target
            if t and t.ID() and t.ID() > 0 and t.Surname then s = tostring(t.Surname() or '') end
        end)
    end
    return s
end

local function pollMerchant(force)
    local now = os.clock()
    if not force and (now - state.lastMerchantPollAt) < MERCHANT_POLL_SEC then return end
    state.lastMerchantPollAt = now

    local open = windowOpen(MERCHANT_WND)
    local wasOpen = state.merchantOpen
    state.merchantOpen = open
    if not open then
        state.rows, state.listCount = {}, 0
        state.isParcelMerchant = false
        state.tabIndex, state.tabCount = 0, 0
        state.merchantName = ''
        if wasOpen and state.autoOpened and ctrl then
            ctrl.show_parcels = false
            state.autoOpened = false
            core.saveLoadout(true)
        end
        return
    end

    pcall(function()
        local m = mq.TLO.Merchant
        if m and m.CleanName then state.merchantName = tostring(m.CleanName() or '') end
        if state.merchantName == '' or state.merchantName == 'NULL' then
            state.merchantName = tostring(mq.TLO.Target.CleanName() or '')
        end
    end)
    state.tabIndex = windowInt(TAB_BOX, 'CurrentTabIndex')
    state.tabCount = windowInt(TAB_BOX, 'TabCount')
    state.rows, state.listCount = readRows()

    -- NMS parcel merchants carry the surname "Parcel"/"Parcels"; a populated
    -- parcel list is proof either way (the server only sends the list when the
    -- NPC is flagged as a parcel merchant).
    local surname = merchantSurname():lower()
    state.isParcelMerchant = (surname:find('parcel', 1, true) ~= nil) or state.listCount > 0

    if not wasOpen and settings.autoOpenAtMerchant and ctrl and not ctrl.show_parcels and state.isParcelMerchant then
        ctrl.show_parcels = true
        state.autoOpened = true
        core.saveLoadout(true)
    end
end

-- Nearest merchant NPC whose surname mentions parcels; nil when none nearby.
local function pollNearest(force)
    local now = os.clock()
    if not force and (now - state.lastNearestAt) < NEAREST_POLL_SEC then return end
    state.lastNearestAt = now
    local best = nil
    pcall(function()
        for i = 1, NEAREST_SCAN_MAX do
            local sp = mq.TLO.NearestSpawn(i, 'npc merchant')
            if not sp or not sp.ID() or sp.ID() == 0 then break end
            local sur = tostring(sp.Surname() or ''):lower()
            if sur:find('parcel', 1, true) then
                best = { name = tostring(sp.CleanName() or '?'), id = sp.ID(), dist = tonumber(sp.Distance()) or 0 }
                break
            end
        end
    end)
    state.nearest = best
end

-- ---------------------------------------------------------------------------
-- Chat events (pumped by the core's mq.doevents on the main loop)
-- ---------------------------------------------------------------------------
local function onDelivered(_, merchant, item, from)
    -- "X hands you the stack of 5 Y that was sent from Z." matches this
    -- pattern too (#2# = "stack of 5 Y"); the stack event owns those.
    if type(item) == 'string' and item:find('^stack of %d+ ') then return end
    state.lastResult = 'delivered'
    state.lastDelivered = { item = item, from = from }
    if state.count and state.count > 0 then state.count = state.count - 1 end
end

local function onDeliveredStack(_, merchant, qty, item, from)
    onDelivered(nil, merchant, string.format('%s x%s', item, qty), from)
end

local function onInvFull()
    state.lastResult = 'invfull'
end

local function onDupLore()
    state.lastResult = 'duplore'
end

local function onArrived()
    state.lastArrivalAt = os.clock()
    pollStatus(true)
end

local function onCount(_, n)
    n = tonumber(n)
    if n then state.count = n end
    pollStatus(true)
end

local function onAtLimit(_, n)
    n = tonumber(n)
    if n then state.count = n; state.limit = n end
    pollStatus(true)
end

local function onOverLimit(_, n)
    n = tonumber(n)
    if n then state.count = n end
    pollStatus(true)
end

local function registerEvents()
    if not (mq and mq.event) then return end
    local function reg(name, pattern, handler)
        if mq.unevent then pcall(mq.unevent, name) end
        mq.event(name, pattern, handler)
        table.insert(state.registeredEvents, name)
    end
    reg('TacParcelDeliveredStack', '#1# hands you the stack of #2# #3# that was sent from #4#.', onDeliveredStack)
    reg('TacParcelDelivered', '#1# hands you the #2# that was sent from #3#.', onDelivered)
    reg('TacParcelInvFull', "#*#Your inventory appears full!#*#Unable to retrieve parceled item#*#", onInvFull)
    reg('TacParcelDupLore', 'Duplicate lore items are not allowed#*#', onDupLore)
    reg('TacParcelArrived', 'You have received a new parcel delivery!#*#', onArrived)
    reg('TacParcelCount', 'You have #1# parcels in your mailbox#*#', onCount)
    reg('TacParcelAtLimit', 'You have reached the limit of #1# parcels in your mailbox#*#', onAtLimit)
    reg('TacParcelOverLimit', 'You currently have #1# parcels in your mail#*#', onOverLimit)
end

local function unregisterEvents()
    if mq and mq.unevent then
        for _, name in ipairs(state.registeredEvents) do pcall(mq.unevent, name) end
    end
    state.registeredEvents = {}
end

-- ---------------------------------------------------------------------------
-- Collect All (runs inside onTick on the plugin fiber; core.delay yields)
-- ---------------------------------------------------------------------------
local function switchToParcelTab()
    if windowInt(TAB_BOX, 'CurrentTabIndex') == PARCEL_TAB_IDX then return true end
    pcall(function() mq.TLO.Window(TAB_BOX).SetCurrentTab(PARCEL_TAB_NAME) end)
    local ok = core.delay(TAB_SWITCH_TIMEOUT_MS, function() return windowInt(TAB_BOX, 'CurrentTabIndex') == PARCEL_TAB_IDX end)
    if not ok then
        pcall(function() mq.TLO.Window(TAB_BOX).SetCurrentTab(PARCEL_TAB_IDX) end)
        ok = core.delay(TAB_SWITCH_TIMEOUT_MS, function() return windowInt(TAB_BOX, 'CurrentTabIndex') == PARCEL_TAB_IDX end)
    end
    return ok
end

local function finishRun(reason, kind)
    state.collecting = false
    state.current = nil
    state.progress = ''
    local summary = string.format('Collected %d parcel%s%s%s', state.retrieved, state.retrieved == 1 and '' or 's',
        state.skipped > 0 and string.format(', skipped %d', state.skipped) or '',
        reason and reason ~= '' and (' - ' .. reason) or '')
    state.lastRunSummary = summary
    addLog(summary, kind or 'info')
    if settings.chatSummary then say('%s', summary) end
    core.log.info('parcels', '%s', summary)
    pollStatus(true)
    pollMerchant(true)
end

local function runCollect()
    state.retrieved, state.skipped = 0, 0
    state.stopRequested = false
    local skippedKeys = {}
    local timeouts = 0

    if not windowOpen(MERCHANT_WND) then
        return finishRun('merchant window is not open', 'warn')
    end
    state.progress = 'Switching to the Parcels tab...'
    if not switchToParcelTab() then
        return finishRun('could not switch to the Parcels tab (not a parcel merchant?)', 'warn')
    end
    -- The server streams the mailbox after the tab opens; give it a moment.
    core.delay(LIST_POPULATE_TIMEOUT_MS, function() return windowInt(PARCEL_LIST, 'Items') > 0 end)

    for _ = 1, MAX_RETRIEVES_PER_RUN do
        if state.stopRequested then return finishRun('stopped', 'warn') end
        if not windowOpen(MERCHANT_WND) then return finishRun('merchant window closed', 'warn') end

        local rows, count = readRows()
        state.rows, state.listCount = rows, count
        if count == 0 then return finishRun(state.retrieved > 0 and 'mailbox empty' or 'no parcels in the mailbox') end

        local pick = nil
        for _, r in ipairs(rows) do
            if not skippedKeys[r.key] then pick = r; break end
        end
        if not pick then return finishRun('remaining parcels could not be retrieved') end

        state.current = pick
        state.progress = string.format('Retrieving %s%s (%d left)', pick.name ~= '' and pick.name or ('row ' .. pick.row),
            pick.from ~= '' and (' from ' .. pick.from) or '', count)

        pcall(function() mq.TLO.Window(PARCEL_LIST).Select(pick.row) end)
        core.delay(300, function() return windowInt(PARCEL_LIST, 'GetCurSel') == pick.row end)

        state.lastResult = nil
        pcall(function() mq.TLO.Window(RETRIEVE_BTN).LeftMouseUp() end)

        local before = count
        local done = core.delay(RETRIEVE_TIMEOUT_MS, function()
            if state.lastResult ~= nil then return true end
            return windowInt(PARCEL_LIST, 'Items') < before
        end)

        local result = state.lastResult
        if result == 'delivered' then
            core.delay(1000, function() return windowInt(PARCEL_LIST, 'Items') < before end)
        end
        if result == 'invfull' then
            addLog(string.format('Inventory full - could not retrieve %s', pick.name), 'warn')
            return finishRun('inventory full, free some slots and run again', 'warn')
        elseif result == 'duplore' then
            state.skipped = state.skipped + 1
            skippedKeys[pick.key] = true
            addLog(string.format('Skipped %s (duplicate lore item)', pick.name), 'warn')
        elseif result == 'delivered' or (done and windowInt(PARCEL_LIST, 'Items') < before) then
            state.retrieved = state.retrieved + 1
            timeouts = 0
            local d = state.lastDelivered
            addLog(string.format('Retrieved %s%s', (d and d.item) or pick.name, (d and d.from) and (' from ' .. d.from) or ''), 'good')
        else
            timeouts = timeouts + 1
            state.skipped = state.skipped + 1
            skippedKeys[pick.key] = true
            addLog(string.format('No response retrieving %s - skipped', pick.name), 'warn')
            if timeouts >= 3 then return finishRun('the merchant stopped responding', 'warn') end
        end
        core.delay(BETWEEN_RETRIEVES_MS)
    end
    return finishRun('hit the per-run retrieve cap')
end

-- ---------------------------------------------------------------------------
-- Public API (Unit Frames badge, /ac parcels)
-- ---------------------------------------------------------------------------
function plugin.getStatus()
    return {
        status  = state.status,
        count   = state.count,
        limit   = state.limit,
        label   = statusLabel(state.status, state.count),
        badge   = settings.hudBadge ~= false,
        merchantOpen = state.merchantOpen,
        collecting = state.collecting,
        listCount = state.listCount,
    }
end

function plugin.isCollecting() return state.collecting == true end

function plugin.canCollect()
    return state.merchantOpen and not state.collecting
end

function plugin.startCollect()
    refresh()
    if state.collecting then return false end
    if not windowOpen(MERCHANT_WND) then
        say('Open a parcel merchant first (hail / right-click one), then Collect All.')
        return false
    end
    state.collecting = true
    state.progress = 'Starting...'
    addLog('Collect All started at ' .. (state.merchantName ~= '' and state.merchantName or 'merchant'), 'info')
    return true
end

function plugin.stopCollect()
    if not state.collecting then return false end
    state.stopRequested = true
    return true
end

function plugin.openWindow(val)
    refresh()
    if not ctrl then return end
    if val == nil then val = not ctrl.show_parcels end
    ctrl.show_parcels = (val == true)
    state.autoOpened = false
    core.saveLoadout(true)
end

-- Badge click on the HUD: collect when standing at a merchant, otherwise
-- show the window.
function plugin.onBadgeClick()
    refresh()
    if state.merchantOpen and not state.collecting then
        plugin.startCollect()
    else
        plugin.openWindow(true)
    end
end

-- ---------------------------------------------------------------------------
-- Plugin hooks
-- ---------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_parcels == nil then ctrl.show_parcels = false end
    registerEvents()
end

function plugin.onDestroy()
    unregisterEvents()
    state.collecting = false
    state.stopRequested = false
    state.current = nil
    state.progress = ''
end

function plugin.onSaveSettings()
    return {
        autoOpenAtMerchant = settings.autoOpenAtMerchant == true,
        hudBadge           = settings.hudBadge ~= false,
        chatSummary        = settings.chatSummary ~= false,
        announceArrivals   = settings.announceArrivals == true,
    }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.autoOpenAtMerchant ~= nil then settings.autoOpenAtMerchant = (s.autoOpenAtMerchant == true) end
    if s.hudBadge ~= nil then settings.hudBadge = (s.hudBadge ~= false) end
    if s.chatSummary ~= nil then settings.chatSummary = (s.chatSummary ~= false) end
    if s.announceArrivals ~= nil then settings.announceArrivals = (s.announceArrivals == true) end
end

function plugin.onZoned()
    state.count = nil          -- the server re-sends the mailbox line on zone-in
    state.nearest = nil
    state.lastNearestAt = 0
    pollStatus(true)
end

function plugin.onTick()
    refresh()
    if not mq then return end
    pollStatus(false)
    pollMerchant(false)
    if ctrl and ctrl.show_parcels and not state.merchantOpen then pollNearest(false) end
    if state.collecting then
        local ok, err = xpcall(runCollect, debug.traceback)
        if not ok then
            state.collecting = false
            state.progress = ''
            addLog('Collect All failed: ' .. tostring(err):match('^[^\n]*'), 'warn')
            core.log.error('parcels', 'Collect All failed:\n%s', tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function drawSettingsBody()
    local v
    v = ImGui.Checkbox('Show badge on the Target & Player HUD##parcelBadge', settings.hudBadge ~= false)
    if v ~= (settings.hudBadge ~= false) then settings.hudBadge = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('Parcels waiting / over limit badge on the Unit Frames player section, like the client player window icon.') end

    v = ImGui.Checkbox('Open this window at parcel merchants##parcelAuto', settings.autoOpenAtMerchant == true)
    if v ~= (settings.autoOpenAtMerchant == true) then settings.autoOpenAtMerchant = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('Pops the Parcel Helper when a parcel merchant window opens and hides it again when it closes.') end

    v = ImGui.Checkbox('Chat summary after Collect All##parcelChat', settings.chatSummary ~= false)
    if v ~= (settings.chatSummary ~= false) then settings.chatSummary = v; core.saveLoadout(true) end

    v = ImGui.Checkbox('Chat line when parcel status changes##parcelAnnounce', settings.announceArrivals == true)
    if v ~= (settings.announceArrivals == true) then settings.announceArrivals = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('The client already prints "You have received a new parcel delivery!"; this adds a Triune line with the count.') end
end

local function drawStatusLine(colors)
    local GOOD, WARN, ERR, MUTED = colors.GOOD, colors.WARN, colors.ERR, colors.MUTED
    local st = state.status
    ImGui.TextDisabled('Mailbox:')
    ImGui.SameLine()
    if st == STATUS_OVER then
        local pulse = 0.65 + 0.35 * math.sin(os.clock() * 6)
        ImGui.TextColored(ERR[1] * pulse + 0.3, ERR[2] * pulse, ERR[3] * pulse, 1.0, statusLabel(st, state.count))
        if state.limit then
            ImGui.SameLine()
            ImGui.TextDisabled(string.format('(limit %d)', state.limit))
        end
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'Retrieve the excess ones soon or risk losing them!')
    elseif st == STATUS_HAS then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], statusLabel(st, state.count))
        if state.count == nil then
            ImGui.SameLine()
            ImGui.TextDisabled('(count unknown until the server reports it)')
        end
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'No parcels waiting')
    end
end

local function drawNearest(colors)
    local ARC, MUTED = colors.ARC, colors.MUTED
    ImGui.TextDisabled('Nearest parcel merchant:')
    ImGui.SameLine()
    local n = state.nearest
    if n then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('%s (%.0f ft)', n.name, n.dist))
        ImGui.SameLine()
        if ImGui.SmallButton('Target##parcelTargetNearest') then
            core.mq.cmdf('/target id %d', n.id)
        end
        local hasNav = false
        pcall(function() hasNav = mq.TLO.Navigation and mq.TLO.Navigation.MeshLoaded() == true end)
        if hasNav then
            ImGui.SameLine()
            if ImGui.SmallButton('Nav##parcelNavNearest') then
                core.mq.cmdf('/nav id %d', n.id)
            end
        end
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'none in range')
    end
end

local function drawMerchantSection(colors)
    local GOOD, WARN, ERR, MUTED, ARC, GOLD = colors.GOOD, colors.WARN, colors.ERR, colors.MUTED, colors.ARC, colors.GOLD

    if not state.merchantOpen then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Open a parcel merchant to collect. Parcel merchants carry the surname "Parcels".')
        return
    end

    ImGui.TextDisabled('Merchant:')
    ImGui.SameLine()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], state.merchantName ~= '' and state.merchantName or '?')
    ImGui.SameLine()
    if state.isParcelMerchant then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('- %d parcel%s listed', state.listCount, state.listCount == 1 and '' or 's'))
    else
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], '- not a parcel merchant?')
    end
    if state.debug then
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('[tab %d/%d]', state.tabIndex, state.tabCount))
    end

    local btnW = core.px(180)
    if state.collecting then
        if ImGui.Button('Stop##parcelStop', btnW, core.px(26)) then plugin.stopCollect() end
        ImGui.SameLine()
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], state.progress ~= '' and state.progress or 'Working...')
    else
        if ImGui.Button('Collect All Parcels##parcelCollect', btnW, core.px(26)) then
            plugin.startCollect()
        end
        if ImGui.IsItemHovered() then core.setTooltip('Switches to the Parcels tab and retrieves every parcel one at a time.\nStops on a full inventory; skips duplicate lore items.') end
        if state.lastRunSummary ~= '' then
            ImGui.SameLine()
            ImGui.TextDisabled(state.lastRunSummary)
        end
    end

    local rows = state.rows
    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp + ImGuiTableFlags.ScrollY
    local h = math.min(core.px(220), core.px(24) + core.px(20) * math.max(1, #rows))
    if ImGui.BeginTable('TriuneParcelList', #LIST_COLS, tableFlags, ImVec2(0, h)) then
        for _, c in ipairs(LIST_COLS) do
            local flags = (c[2] == 'Item' or c[2] == 'Note') and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            ImGui.TableSetupColumn(c[2], flags, c[2] == 'Item' and 3 or (c[2] == 'Note' and 3 or core.px(60)))
        end
        ImGui.TableHeadersRow()
        if #rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], state.tabIndex == PARCEL_TAB_IDX and '(mailbox is empty)' or '(list fills once the Parcels tab is open)')
        else
            for _, r in ipairs(rows) do
                ImGui.TableNextRow()
                local isCur = state.current and state.current.key == r.key
                ImGui.TableSetColumnIndex(0)
                if isCur then
                    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], r.name)
                else
                    ImGui.Text(r.name)
                end
                ImGui.TableSetColumnIndex(1); ImGui.TextDisabled(r.qty)
                ImGui.TableSetColumnIndex(2); ImGui.TextDisabled(r.price or '')
                ImGui.TableSetColumnIndex(3); ImGui.Text(r.from)
                ImGui.TableSetColumnIndex(4); ImGui.TextDisabled(r.note)
            end
        end
        ImGui.EndTable()
    end
end

local function drawLog(colors)
    local GOOD, WARN, MUTED = colors.GOOD, colors.WARN, colors.MUTED
    ImGui.TextDisabled('SESSION LOG')
    if ImGui.BeginChild('##parcelLog', 0, core.px(110), true) then
        if #state.log == 0 then
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(nothing yet)')
        else
            for _, e in ipairs(state.log) do
                ImGui.TextDisabled(e.time)
                ImGui.SameLine()
                if e.kind == 'good' then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], e.text)
                elseif e.kind == 'warn' then
                    ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], e.text)
                else
                    ImGui.Text(e.text)
                end
            end
        end
    end
    ImGui.EndChild()
end

local function drawWindow()
    if not ctrl or not ctrl.show_parcels then return end
    local c = core.colors or {}
    local colors = {
        GOOD  = c.GOOD or { 0.40, 0.85, 0.50, 1.0 },
        WARN  = c.WARN or { 0.95, 0.75, 0.30, 1.0 },
        ERR   = c.ERR or { 0.95, 0.40, 0.40, 1.0 },
        MUTED = c.MUTED or { 0.55, 0.60, 0.65, 1.0 },
        ARC   = c.ARC or { 0.30, 0.80, 1.00, 1.0 },
        GOLD  = c.GOLD or { 1.0, 0.70, 0.54, 1.0 },
    }

    core.pushTheme()
    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(core.px(520), core.px(400), ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('parcels')
    local open, draw = ImGui.Begin('Triune Parcels###TriuneParcels', ctrl.show_parcels, core.windowFlags and core.windowFlags('parcels', windowFlags) or windowFlags)
    if not open then
        ctrl.show_parcels = false
        state.autoOpened = false
        if core.preEndWindow then core.preEndWindow('parcels', false) end
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not draw then
        if core.preEndWindow then core.preEndWindow('parcels', false) end
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('parcels')

    if ImGui.BeginPopupContextWindow('##parcelsContextMenu') then
        if core.applyWindowScale then core.applyWindowScale('parcels') end
        if core.drawWindowMenuItems then
            core.drawWindowMenuItems('parcels', { header = false, close = false })
            ImGui.Separator()
        end
        drawSettingsBody()
        ImGui.Separator()
        local dbg = ImGui.Checkbox('Debug info##parcelDbg', state.debug == true)
        if dbg ~= (state.debug == true) then state.debug = dbg end
        ImGui.EndPopup()
    end

    ImGui.TextColored(colors.ARC[1], colors.ARC[2], colors.ARC[3], colors.ARC[4], 'PARCEL HELPER')
    ImGui.SameLine()
    ImGui.TextDisabled('| Mailbox status & Collect All')
    ImGui.Separator()
    ImGui.Dummy(0, core.px(2))

    drawStatusLine(colors)
    if not state.merchantOpen then drawNearest(colors) end
    ImGui.Dummy(0, core.px(4))
    ImGui.Separator()
    drawMerchantSection(colors)
    ImGui.Dummy(0, core.px(4))
    drawLog(colors)

    if core.preEndWindow then core.preEndWindow('parcels', false) end
    ImGui.End()
    core.popTheme()
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
    core.accent(GOLD, 'Parcel Helper')
    local isWinOpen = (ctrl.show_parcels == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##parcelToggleWin', core.px(250), core.px(24)) then
        plugin.openWindow(not isWinOpen)
    end
    ImGui.Spacing()
    ImGui.TextDisabled('Status: ' .. statusLabel(state.status, state.count))
    ImGui.Spacing()
    drawSettingsBody()
end

-- /ac parcels            toggle the window
-- /ac parcels collect    Collect All at the open merchant
-- /ac parcels stop       stop a running collect
-- /ac parcels status     print the mailbox status
function plugin.onCommand(cmd, args)
    if cmd ~= 'parcels' and cmd ~= 'parcel' then return false end
    refresh()
    local sub = (args and args[2]) and string.lower(args[2]) or ''
    if sub == 'collect' or sub == 'all' or sub == 'get' then
        plugin.startCollect()
    elseif sub == 'stop' then
        if plugin.stopCollect() then say('Stopping Collect All.') else say('Collect All is not running.') end
    elseif sub == 'status' then
        pollStatus(true)
        say('%s%s', statusLabel(state.status, state.count), state.limit and string.format(' (limit %d)', state.limit) or '')
    else
        plugin.openWindow()
        say('Parcel Helper %s.', ctrl.show_parcels and 'OPENED' or 'CLOSED')
    end
    return true
end

plugin.help = {
    '  \ag/ac parcels\ax - Toggle the Parcel Helper window',
    '  \ag/ac parcels collect | stop | status\ax - Collect All at the open parcel merchant / stop / print mailbox status',
}

-- Exposed for tests
plugin.state = state
plugin.settings = settings
plugin.statusLabel = statusLabel

return plugin
