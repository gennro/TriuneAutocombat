-- ============================================================================
-- Triune Cursor Manager v1.4
-- Standalone ImGui window for inspecting, auto-inventorying, and destroying
-- items currently held on the character's cursor with live session logging.
-- Action handlers are queued and executed on the yieldable main thread to prevent
-- "Cannot delay from non-yieldable thread" errors.
-- Uses shared routines from triune_common.lua.
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')

-- Multi-path search for triune_common.lua
local common = nil
local pathsToTry = {
    'triune_common',
    mq.configDir .. '/triune_common.lua',
    mq.luaDir .. '/triune/triune_common.lua',
    mq.luaDir .. '/triune_common.lua'
}

for _, p in ipairs(pathsToTry) do
    local ok, mod = pcall(require, p)
    if ok and type(mod) == 'table' then
        common = mod
        break
    end
end

if not common then
    print('\ar[Triune Cursor]\ax Failed to load triune_common.lua!')
    return
end

local openGUI = true
local isRunning = true
local confirmDestroy = false
local autoClearOnPick = false
local pendingAction = nil -- 'clear' or 'destroy'
local statusMsg = ""
local sessionHistory = {} -- Array of { time, name, qty, action }

-- Bind ImGui colors
local GOOD  = { 0.40, 0.85, 0.50, 1.0 }
local WARN  = { 0.95, 0.75, 0.30, 1.0 }
local ERR   = { 0.95, 0.40, 0.40, 1.0 }
local MUTED = { 0.55, 0.60, 0.65, 1.0 }
local ARC   = { 0.30, 0.80, 1.00, 1.0 }

local function logSession(name, qty, action)
    local t = os.date("%H:%M:%S")
    table.insert(sessionHistory, 1, { time = t, name = name, qty = qty, action = action })
    if #sessionHistory > 50 then
        table.remove(sessionHistory)
    end
end

local function DrawCursorManagerUI()
    if not openGUI then
        isRunning = false
        return
    end

    common.pushTheme()

    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(560, 360, ImGuiCond.FirstUseEver)
    local open, draw = ImGui.Begin("Triune Cursor Manager##Main", openGUI)
    if not open then
        openGUI = false
        isRunning = false
        ImGui.End()
        common.popTheme()
        return
    end

    if draw then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "CURSOR ITEM MANAGER")
        ImGui.SameLine()
        ImGui.TextDisabled("| Live Cursor & Session History")
        ImGui.Separator()
        ImGui.Dummy(0, 4)

        -- Current active cursor item inspection
        local cursorItem = mq.TLO.Cursor
        local hasItem = cursorItem() and (cursorItem.ID() or 0) > 0
        local itemName = hasItem and tostring(cursorItem.Name() or 'Unknown Item') or nil
        local itemId = hasItem and (cursorItem.ID() or 0) or 0
        local stackQty = hasItem and (cursorItem.Stack() or 1) or 0

        -- Flags
        local flags = {}
        if hasItem then
            if cursorItem.Lore() then table.insert(flags, "Lore") end
            if cursorItem.NoDrop() then table.insert(flags, "NoDrop") end
        end

        ImGui.TextDisabled("Active Cursor Item:")
        ImGui.SameLine()
        if hasItem then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%s (ID: %d, Qty: %d)", itemName, itemId, stackQty))
            if #flags > 0 then
                ImGui.SameLine()
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "[" .. table.concat(flags, ", ") .. "]")
            end
        else
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "(No item on cursor)")
        end

        ImGui.Dummy(0, 6)

        -- Action Buttons (queue actions to main yieldable thread)
        if not hasItem then ImGui.BeginDisabled() end
        if ImGui.Button("Auto Inventory Item", 150, 26) then
            pendingAction = 'clear'
        end
        if ImGui.IsItemHovered() and hasItem then
            ImGui.SetTooltip("Place this item into inventory bags.")
        end

        ImGui.SameLine()

        local destroyAllowed = hasItem and confirmDestroy
        if not destroyAllowed then ImGui.BeginDisabled() end
        ImGui.PushStyleColor(ImGuiCol.Button, 0.75, 0.20, 0.20, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.90, 0.30, 0.30, 1.0)
        if ImGui.Button("Destroy Item", 130, 26) then
            pendingAction = 'destroy'
        end
        ImGui.PopStyleColor(2)
        if ImGui.IsItemHovered() and hasItem then
            if not confirmDestroy then
                ImGui.SetTooltip("Check 'Confirm Destroy' box to enable.")
            else
                ImGui.SetTooltip("Permanently destroy this item!")
            end
        end
        if not destroyAllowed then ImGui.EndDisabled() end
        if not hasItem then ImGui.EndDisabled() end

        ImGui.SameLine()
        confirmDestroy = ImGui.Checkbox("Confirm Destroy", confirmDestroy)

        ImGui.Dummy(0, 4)
        autoClearOnPick = ImGui.Checkbox("Auto-Clear Items on Pick (Continuous)", autoClearOnPick)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("When checked, automatically inventories any item that lands on the cursor.")
        end

        if statusMsg ~= "" then
            ImGui.SameLine()
            ImGui.TextDisabled("   " .. statusMsg)
        end

        ImGui.Dummy(0, 6)
        ImGui.Separator()
        ImGui.TextDisabled("SESSION ITEM HISTORY (PROCESSED ITEMS)")
        ImGui.Dummy(0, 2)

        -- Session History Table
        local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
        if ImGui.BeginTable("SessionCursorHistory", 5, tableFlags, ImVec2(0, 140)) then
            ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, 25)
            ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthFixed, 65)
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 50)
            ImGui.TableSetupColumn("Action Taken", ImGuiTableColumnFlags.WidthFixed, 130)
            ImGui.TableHeadersRow()

            if #sessionHistory > 0 then
                for idx, entry in ipairs(sessionHistory) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0); ImGui.TextDisabled(tostring(idx))
                    ImGui.TableSetColumnIndex(1); ImGui.TextDisabled(entry.time)
                    ImGui.TableSetColumnIndex(2); ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], entry.name)
                    ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(entry.qty))
                    ImGui.TableSetColumnIndex(4)
                    if entry.action == "Destroyed" then
                        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], entry.action)
                    else
                        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], entry.action)
                    end
                end
            else
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.TextDisabled("-")
                ImGui.TableSetColumnIndex(1); ImGui.TextDisabled("-")
                ImGui.TableSetColumnIndex(2); ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "(No history yet -- process an item above)")
                ImGui.TableSetColumnIndex(3); ImGui.TextDisabled("-")
                ImGui.TableSetColumnIndex(4); ImGui.TextDisabled("-")
            end

            ImGui.EndTable()
        end
    end

    ImGui.End()
    common.popTheme()
end

-- Init ImGui subscription
mq.imgui.init('TriuneCursorManager', DrawCursorManagerUI)

print('\ag[Triune Cursor]\ax UI initialized. Close window or type /lua stop triune_cursor to exit.')

-- Main loop (yieldable coroutine thread -- mq.delay allowed here)
while isRunning do
    if pendingAction == 'clear' then
        pendingAction = nil
        local cursorItem = mq.TLO.Cursor
        if cursorItem() and (cursorItem.ID() or 0) > 0 then
            local targetName = tostring(cursorItem.Name() or 'Unknown Item')
            local qty = cursorItem.Stack() or 1
            local cleared = common.clearCursor()
            if cleared then
                statusMsg = string.format("Cleared [%s] to inventory.", targetName)
                logSession(targetName, qty, "Auto Inventoried")
            else
                statusMsg = "Failed or cursor empty."
            end
        else
            statusMsg = "Cursor is empty."
        end
    elseif pendingAction == 'destroy' then
        pendingAction = nil
        local cursorItem = mq.TLO.Cursor
        if cursorItem() and (cursorItem.ID() or 0) > 0 then
            local targetName = tostring(cursorItem.Name() or 'Unknown Item')
            local qty = cursorItem.Stack() or 1
            local destroyed = common.destroyCursor()
            if destroyed then
                statusMsg = string.format("Destroyed [%s].", targetName)
                logSession(targetName, qty, "Destroyed")
            else
                statusMsg = "Failed to destroy item."
            end
        else
            statusMsg = "Cursor is empty."
        end
    elseif autoClearOnPick then
        local cursorItem = mq.TLO.Cursor
        if cursorItem() and (cursorItem.ID() or 0) > 0 then
            local name = tostring(cursorItem.Name() or 'Item')
            local qty = cursorItem.Stack() or 1
            if common.clearCursor() then
                logSession(name, qty, "Auto-Cleared (Auto)")
            end
        end
    end
    mq.delay(50)
end

print('\ag[Triune Cursor]\ax Manager closed.')
