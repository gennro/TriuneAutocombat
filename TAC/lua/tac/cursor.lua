---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/cursor.lua — Triune Cursor Item Manager Plugin
-- ============================================================================
-- In-process replacement for the old standalone triune_cursor.lua script.
-- Inspects the item currently held on the cursor, auto-inventories or destroys
-- it on request, optionally auto-clears anything that lands on the cursor, and
-- keeps a session log of every item it processed.
--
-- The old script looped `/autoinventory` with 50ms sleeps on its own thread;
-- the plugin issues one command per tick instead so it never blocks the core.
-- Visibility is ctrl.show_cursor (header button, Mini HUD, /ac cursorui, and
-- the Window Layout manager all flip it).
-- ============================================================================

local plugin = {
    id                 = 'cursor',
    name               = 'Cursor Item Manager',
    version            = '2.0.0',
    author             = 'Triune',
    description        = 'Inspect, auto-inventory, or destroy the item on your cursor with a session history log.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Cursor Manager', tooltip = 'Toggles the Cursor Item Manager window (cursor plugin).', flag = 'show_cursor', desc = 'Inspect / auto-inventory / destroy the cursor item', headerButton = true, order = 40 },
}

local core = nil
local ctrl, ImGui, mq = nil, nil, nil

local MAX_CLEAR_ATTEMPTS = 255
local MAX_HISTORY = 50

local state = {
    confirmDestroy  = false,
    autoClearOnPick = false,
    pendingAction   = nil, -- 'clear' | 'destroy'
    statusMsg       = '',
    sessionHistory  = {},  -- newest first: { time, name, qty, action }
    -- In-flight /autoinventory sequence (one command per tick)
    clearing        = nil, -- { name, qty, action, attempts }
}

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

local function cursorItem()
    local item = mq.TLO.Cursor
    if item() and (item.ID() or 0) > 0 then return item end
    return nil
end

local function logSession(name, qty, action)
    local t = os.date('%H:%M:%S')
    table.insert(state.sessionHistory, 1, { time = t, name = name, qty = qty, action = action })
    while #state.sessionHistory > MAX_HISTORY do
        table.remove(state.sessionHistory)
    end
end

-- Starts a non-blocking auto-inventory sequence for whatever is on the cursor.
local function beginClear(action)
    local item = cursorItem()
    if not item then return false end
    state.clearing = {
        name     = tostring(item.Name() or 'Item'),
        qty      = item.Stack() or 1,
        action   = action,
        attempts = 0,
    }
    return true
end

-- One step of the auto-inventory sequence; returns true when finished.
local function stepClear()
    local c = state.clearing
    if not c then return true end
    if not cursorItem() then
        state.clearing = nil
        if c.attempts > 0 then
            print(string.format('\ay[Triune Cursor]\ax Cleared %d item(s) from cursor (first: [%s]).', c.attempts, c.name))
            logSession(c.name, c.qty, c.action)
            if c.action == 'Auto Inventoried' then
                state.statusMsg = string.format('Cleared [%s] to inventory.', c.name)
            end
        else
            state.statusMsg = 'Failed or cursor empty.'
        end
        return true
    end
    if c.attempts >= MAX_CLEAR_ATTEMPTS then
        state.clearing = nil
        state.statusMsg = 'Failed or cursor empty.'
        return true
    end
    c.attempts = c.attempts + 1
    mq.cmd('/autoinventory')
    return false
end

local function destroyCursor()
    local item = cursorItem()
    if not item then
        state.statusMsg = 'Cursor is empty.'
        return false
    end
    local itemName = tostring(item.Name() or 'Item')
    local qty = item.Stack() or 1
    print(string.format('\ar[Triune Cursor]\ax Destroyed [%s] from cursor.', itemName))
    mq.cmd('/destroy')
    state.statusMsg = string.format('Destroyed [%s].', itemName)
    logSession(itemName, qty, 'Destroyed')
    return true
end

local function tick()
    if state.clearing then
        stepClear()
        return
    end
    local action = state.pendingAction
    if action == 'clear' then
        state.pendingAction = nil
        if beginClear('Auto Inventoried') then
            stepClear()
        else
            state.statusMsg = 'Cursor is empty.'
        end
    elseif action == 'destroy' then
        state.pendingAction = nil
        destroyCursor()
    elseif state.autoClearOnPick then
        if beginClear('Auto-Cleared (Auto)') then stepClear() end
    end
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
local function drawWindow()
    if not ctrl.show_cursor then return end
    local colors = core.colors or {}
    local GOOD  = colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    local WARN  = colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    local ERR   = colors.ERR or { 0.95, 0.40, 0.40, 1.0 }
    local MUTED = colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    local ARC   = colors.ARC or { 0.30, 0.80, 1.00, 1.0 }

    core.pushTheme()

    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(560, 360, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('cursor')
    local open, draw = ImGui.Begin('Triune Cursor Manager###TriuneCursorManager', ctrl.show_cursor, windowFlags)
    if not open then
        ctrl.show_cursor = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not draw then
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('cursor')

    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'CURSOR ITEM MANAGER')
    ImGui.SameLine()
    ImGui.TextDisabled('| Live Cursor & Session History')
    ImGui.Separator()
    ImGui.Dummy(0, 4)

    -- Current active cursor item inspection
    local item = cursorItem()
    local hasItem = item ~= nil
    local itemName = hasItem and tostring(item.Name() or 'Unknown Item') or nil
    local itemId = hasItem and (item.ID() or 0) or 0
    local stackQty = hasItem and (item.Stack() or 1) or 0

    local flags = {}
    if hasItem then
        if item.Lore() then table.insert(flags, 'Lore') end
        if item.NoDrop() then table.insert(flags, 'NoDrop') end
    end

    ImGui.TextDisabled('Active Cursor Item:')
    ImGui.SameLine()
    if hasItem then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('%s (ID: %d, Qty: %d)', itemName, itemId, stackQty))
        if #flags > 0 then
            ImGui.SameLine()
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], '[' .. table.concat(flags, ', ') .. ']')
        end
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(No item on cursor)')
    end

    ImGui.Dummy(0, 6)

    -- Action buttons (queued; executed on the plugin tick)
    if not hasItem then ImGui.BeginDisabled() end
    if ImGui.Button('Auto Inventory Item', 150, 26) then
        state.pendingAction = 'clear'
    end
    if ImGui.IsItemHovered() and hasItem then
        ImGui.SetTooltip('Place this item into inventory bags.')
    end

    ImGui.SameLine()

    local destroyAllowed = hasItem and state.confirmDestroy
    if not destroyAllowed then ImGui.BeginDisabled() end
    ImGui.PushStyleColor(ImGuiCol.Button, 0.75, 0.20, 0.20, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.90, 0.30, 0.30, 1.0)
    if ImGui.Button('Destroy Item', 130, 26) then
        state.pendingAction = 'destroy'
    end
    ImGui.PopStyleColor(2)
    if ImGui.IsItemHovered() and hasItem then
        if not state.confirmDestroy then
            ImGui.SetTooltip("Check 'Confirm Destroy' box to enable.")
        else
            ImGui.SetTooltip('Permanently destroy this item!')
        end
    end
    if not destroyAllowed then ImGui.EndDisabled() end
    if not hasItem then ImGui.EndDisabled() end

    ImGui.SameLine()
    state.confirmDestroy = ImGui.Checkbox('Confirm Destroy', state.confirmDestroy)

    ImGui.Dummy(0, 4)
    local autoVal = ImGui.Checkbox('Auto-Clear Items on Pick (Continuous)', state.autoClearOnPick)
    if autoVal ~= state.autoClearOnPick then
        state.autoClearOnPick = autoVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('When checked, automatically inventories any item that lands on the cursor.')
    end

    if state.statusMsg ~= '' then
        ImGui.SameLine()
        ImGui.TextDisabled('   ' .. state.statusMsg)
    end

    ImGui.Dummy(0, 6)
    ImGui.Separator()
    ImGui.TextDisabled('SESSION ITEM HISTORY (PROCESSED ITEMS)')
    ImGui.Dummy(0, 2)

    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if ImGui.BeginTable('SessionCursorHistory', 5, tableFlags, ImVec2(0, 140)) then
        ImGui.TableSetupColumn('#', ImGuiTableColumnFlags.WidthFixed, 25)
        ImGui.TableSetupColumn('Time', ImGuiTableColumnFlags.WidthFixed, 65)
        ImGui.TableSetupColumn('Item Name', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, 50)
        ImGui.TableSetupColumn('Action Taken', ImGuiTableColumnFlags.WidthFixed, 130)
        ImGui.TableHeadersRow()

        if #state.sessionHistory > 0 then
            for idx, entry in ipairs(state.sessionHistory) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.TextDisabled(tostring(idx))
                ImGui.TableSetColumnIndex(1); ImGui.TextDisabled(entry.time)
                ImGui.TableSetColumnIndex(2); ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], entry.name)
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(entry.qty))
                ImGui.TableSetColumnIndex(4)
                if entry.action == 'Destroyed' then
                    ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], entry.action)
                else
                    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], entry.action)
                end
            end
        else
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.TextDisabled('-')
            ImGui.TableSetColumnIndex(1); ImGui.TextDisabled('-')
            ImGui.TableSetColumnIndex(2); ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(No history yet -- process an item above)')
            ImGui.TableSetColumnIndex(3); ImGui.TextDisabled('-')
            ImGui.TableSetColumnIndex(4); ImGui.TextDisabled('-')
        end

        ImGui.EndTable()
    end

    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_cursor == nil then ctrl.show_cursor = false end
    state.pendingAction = nil
    state.clearing = nil
    state.statusMsg = ''
end

function plugin.onDestroy()
    state.pendingAction = nil
    state.clearing = nil
end

function plugin.onTick()
    if not core then return end
    refresh()
    tick()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    drawWindow()
end

-- Auto-clear is the only preference worth keeping across sessions.
function plugin.onSaveSettings()
    return { autoClearOnPick = state.autoClearOnPick == true }
end

function plugin.onLoadSettings(s)
    if type(s) == 'table' and s.autoClearOnPick ~= nil then
        state.autoClearOnPick = (s.autoClearOnPick == true)
    end
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Cursor Item Manager')
    local isWinOpen = (ctrl.show_cursor == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##curToggleWin', 250, 24) then
        ctrl.show_cursor = not isWinOpen
        core.saveLoadout(true)
    end
    local autoVal = ImGui.Checkbox('Auto-Clear Items on Pick (Continuous)##curAuto', state.autoClearOnPick)
    if autoVal ~= state.autoClearOnPick then
        state.autoClearOnPick = autoVal
        core.saveLoadout(true)
    end
    ImGui.TextDisabled(string.format('Session history: %d item(s)', #state.sessionHistory))
end

-- /ac cursorui | cursorwin | cursormgr toggles the window (was: /lua run triune_cursor)
function plugin.onCommand(cmd)
    if cmd ~= 'cursorui' and cmd ~= 'cursorwin' and cmd ~= 'cursormgr' then return false end
    refresh()
    ctrl.show_cursor = not ctrl.show_cursor
    core.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Cursor Manager %s.', ctrl.show_cursor and 'OPENED' or 'CLOSED'))
    return true
end

plugin.help = {
    '  \ag/ac cursorui | cursorwin | cursormgr\ax - Toggle the Cursor Item Manager window',
}

-- Exposed for tests
plugin.state = state
plugin.tick = tick
plugin.stepClear = stepClear

return plugin
