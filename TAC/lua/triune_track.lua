---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TRIUNE ZONE TRACKER v1.0 (Standalone ImGui Script)
-- ----------------------------------------------------------------------------
-- Live NPC tracking, filtering, consideration inspection, and target navigation.
-- Compatible with MacroQuest LuaJIT (Lua 5.1 safe).
-- Run via: /lua run triune_track
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library

-- Theme & style helpers for tracker window (Unified Dark Cyan/Blue Theme)
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

-- State Management Table
local state = {
    openGUI = true,
    isRunning = true,

    -- Search & Filter Controls
    searchText = '',
    conFilterIndex = 1,     -- 1: All, 2: Red/DarkRed, 3: Yellow, 4: White, 5: Blue, 6: LightBlue, 7: Green, 8: Grey
    minLevel = 1,
    maxLevel = 125,
    maxDistance = 5000,
    sortBy = 'NEAREST',     -- 'NEAREST', 'FARTHEST', 'LEVEL_DESC', 'LEVEL_ASC', 'NAME_ASC'
    sortIndex = 1,          -- 1: Nearest, 2: Farthest, 3: Level (High->Low), 4: Level (Low->High), 5: Name (A-Z)

    -- Data Storage
    spawns = {},
    filteredSpawns = {},
    totalNPCs = 0,
    currentZone = 'Unknown Zone',
    lastScanTime = 0,
    scanIntervalMs = 300,

    -- Thread Safety Action Queues (executed in main coroutine loop)
    pendingTargetId = 0,
    pendingNavId = 0,
    activeNavId = 0,
    activeNavTargetName = '',
    statusMsg = 'Ready',
}

-- Filter Options Constants
local CON_OPTIONS = {
    'All Considerations',
    'Red / Dark Red',
    'Yellow',
    'White',
    'Blue',
    'Light Blue',
    'Green',
    'Grey',
}

local SORT_OPTIONS = {
    'Nearest First',
    'Farthest First',
    'Level (High -> Low)',
    'Level (Low -> High)',
    'Name (A - Z)',
}

-- Consideration Colors and Badge Map
local CON_COLOR_MAP = {
    ['DARK RED']   = { r = 0.85, g = 0.10, b = 0.10, badge = '[DRK]' },
    ['RED']        = { r = 0.95, g = 0.25, b = 0.25, badge = '[RED]' },
    ['YELLOW']     = { r = 1.00, g = 0.90, b = 0.20, badge = '[YEL]' },
    ['WHITE']      = { r = 0.95, g = 0.95, b = 0.95, badge = '[WHT]' },
    ['BLUE']       = { r = 0.30, g = 0.60, b = 1.00, badge = '[BLU]' },
    ['LIGHT BLUE'] = { r = 0.40, g = 0.80, b = 1.00, badge = '[LBL]' },
    ['GREEN']      = { r = 0.20, g = 0.90, b = 0.35, badge = '[GRN]' },
    ['GREY']       = { r = 0.60, g = 0.60, b = 0.60, badge = '[GRY]' },
    ['GRAY']       = { r = 0.60, g = 0.60, b = 0.60, badge = '[GRY]' },
}

local function getConStyle(conStr)
    local upper = string.upper(tostring(conStr or ''))
    return CON_COLOR_MAP[upper] or { r = 0.70, g = 0.70, b = 0.70, badge = '[UNK]' }
end

-- ============================================================================
-- ZONE SPAWN SCANNER & FILTER ENGINE
-- ============================================================================
local function scanZoneSpawns()
    local okZone, zoneName = pcall(function() return mq.TLO.Zone.Name() end)
    if okZone and zoneName then
        state.currentZone = zoneName
    end

    local okCount, count = pcall(function() return mq.TLO.SpawnCount('npc')() end)
    if not okCount or not count or count <= 0 then
        state.spawns = {}
        state.filteredSpawns = {}
        state.totalNPCs = 0
        return
    end

    state.totalNPCs = count
    local newList = {}
    local maxFetch = math.min(count, 600) -- Safety cap for large zones

    for i = 1, maxFetch do
        local okSpawn, s = pcall(function() return mq.TLO.NearestSpawn(i, 'npc') end)
        if okSpawn and s and s() then
            local okId, sId = pcall(function() return s.ID() end)
            local okDead, isDead = pcall(function() return s.Dead() end)

            if okId and sId and sId > 0 and (not okDead or not isDead) then
                local _, cleanName = pcall(function() return s.CleanName() end)
                local _, level = pcall(function() return s.Level() end)
                local _, conColor = pcall(function() return s.ConColor() end)
                local _, distance = pcall(function() return s.Distance3D() end)
                local _, lineOfSight = pcall(function() return s.LineOfSight() end)
                local _, x = pcall(function() return s.X() end)
                local _, y = pcall(function() return s.Y() end)
                local _, z = pcall(function() return s.Z() end)

                newList[#newList + 1] = {
                    id = sId,
                    cleanName = cleanName or 'Unknown NPC',
                    level = level or 0,
                    conColor = string.upper(tostring(conColor or 'GREY')),
                    distance = distance or 99999,
                    lineOfSight = lineOfSight or false,
                    x = x or 0,
                    y = y or 0,
                    z = z or 0,
                }
            end
        end
    end

    state.spawns = newList

    -- Apply Filters
    local filtered = {}
    local searchLower = string.lower(state.searchText or '')
    local filterIdx = state.conFilterIndex

    for _, mob in ipairs(newList) do
        local keep = true

        -- Search text filter
        if searchLower ~= '' then
            local nameMatch = string.lower(mob.cleanName):find(searchLower, 1, true)
            local idMatch = tostring(mob.id):find(searchLower, 1, true)
            if not nameMatch and not idMatch then
                keep = false
            end
        end

        -- Consideration filter
        if keep and filterIdx > 1 then
            local con = mob.conColor
            if filterIdx == 2 and con ~= 'RED' and con ~= 'DARK RED' then keep = false
            elseif filterIdx == 3 and con ~= 'YELLOW' then keep = false
            elseif filterIdx == 4 and con ~= 'WHITE' then keep = false
            elseif filterIdx == 5 and con ~= 'BLUE' then keep = false
            elseif filterIdx == 6 and con ~= 'LIGHT BLUE' then keep = false
            elseif filterIdx == 7 and con ~= 'GREEN' then keep = false
            elseif filterIdx == 8 and con ~= 'GREY' and con ~= 'GRAY' then keep = false
            end
        end

        -- Level filter
        if keep then
            if mob.level < state.minLevel or mob.level > state.maxLevel then
                keep = false
            end
        end

        -- Distance filter
        if keep then
            if mob.distance > state.maxDistance then
                keep = false
            end
        end

        if keep then
            filtered[#filtered + 1] = mob
        end
    end

    -- Apply Sort Order
    local sIdx = state.sortIndex
    table.sort(filtered, function(a, b)
        if sIdx == 1 then
            return a.distance < b.distance
        elseif sIdx == 2 then
            return a.distance > b.distance
        elseif sIdx == 3 then
            if a.level == b.level then return a.distance < b.distance end
            return a.level > b.level
        elseif sIdx == 4 then
            if a.level == b.level then return a.distance < b.distance end
            return a.level < b.level
        elseif sIdx == 5 then
            return a.cleanName:lower() < b.cleanName:lower()
        end
        return a.distance < b.distance
    end)

    state.filteredSpawns = filtered
end

-- ============================================================================
-- IMGUI DRAW CALLBACK
-- ============================================================================
local function DrawTrackerUI()
    if not state.openGUI then
        state.isRunning = false
        return
    end

    pushTheme()

    local windowFlags = bit.bor(
        ImGuiWindowFlags.MenuBar or 0,
        ImGuiWindowFlags.NoCollapse or 0
    )
    -- Omit NoCollapse flag so WindowRounding token applies rounded corners cleanly
    windowFlags = bit.band(windowFlags, bit.bnot(ImGuiWindowFlags.NoCollapse or 0))

    local open, draw = ImGui.Begin('Triune Zone Tracker v1.0##TrackWindow', state.openGUI, windowFlags)
    state.openGUI = open

    if not open then
        ImGui.End()
        popTheme()
        state.isRunning = false
        return
    end

    if draw then
        -- Top Info Bar & Zone Metrics
        ImGui.TextColored(0.3, 0.8, 1.0, 1.0, "Zone:")
        ImGui.SameLine()
        ImGui.Text(state.currentZone)
        ImGui.SameLine()
        ImGui.TextDisabled(string.format("(Showing %d of %d NPCs)", #state.filteredSpawns, state.totalNPCs))

        ImGui.SameLine()
        if ImGui.Button("Stop Nav##NavStopBtn") then
            pcall(function() mq.cmd('/nav stop') end)
            pcall(function() mq.cmd('/stick off') end)
            state.statusMsg = "Navigation halted by user."
            state.activeNavTargetName = ""
            state.activeNavId = 0
        end
        ImGui.SameLine()
        if ImGui.Button("Refresh List##RefreshBtn") then
            scanZoneSpawns()
        end

        ImGui.Separator()

        -- Filter Controls Bar
        ImGui.PushItemWidth(180)
        local searchVal, searchChanged = ImGui.InputText("Search##SearchBox", state.searchText)
        if searchChanged then
            state.searchText = searchVal
            scanZoneSpawns()
        end
        ImGui.PopItemWidth()

        if state.searchText ~= '' then
            ImGui.SameLine()
            if ImGui.Button("X##ClearSearch") then
                state.searchText = ''
                scanZoneSpawns()
            end
        end

        ImGui.SameLine()
        ImGui.PushItemWidth(150)
        local conIdx, conChanged = ImGui.Combo("Con Filter##ConCombo", state.conFilterIndex, CON_OPTIONS)
        if conChanged then
            state.conFilterIndex = conIdx
            scanZoneSpawns()
        end
        ImGui.PopItemWidth()

        ImGui.SameLine()
        ImGui.PushItemWidth(160)
        local sortIdx, sortChanged = ImGui.Combo("Sort By##SortCombo", state.sortIndex, SORT_OPTIONS)
        if sortChanged then
            state.sortIndex = sortIdx
            scanZoneSpawns()
        end
        ImGui.PopItemWidth()

        ImGui.Separator()

        -- Target Table
        local tableFlags = bit.bor(
            ImGuiTableFlags.Resizable or 0,
            ImGuiTableFlags.RowBg or 0,
            ImGuiTableFlags.BordersOuter or 0,
            ImGuiTableFlags.BordersV or 0,
            ImGuiTableFlags.ScrollY or 0,
            ImGuiTableFlags.SizingFixedFit or 0
        )

        local availWidth, availHeight = ImGui.GetContentRegionAvail()
        local tableHeight = availHeight - 32 -- leave room for status bar footer

        if ImGui.BeginTable("##NPCTable", 7, tableFlags, availWidth, tableHeight) then
            -- Set up Column headers with Clean Name FIRST
            ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 2.0)
            ImGui.TableSetupColumn("Lvl", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn("Dist", ImGuiTableColumnFlags.WidthFixed, 70)
            ImGui.TableSetupColumn("Con", ImGuiTableColumnFlags.WidthFixed, 65)
            ImGui.TableSetupColumn("ID", ImGuiTableColumnFlags.WidthFixed, 60)
            ImGui.TableSetupColumn("LoS", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 115)
            ImGui.TableHeadersRow()

            local currentTargetId = 0
            local okTarg, targId = pcall(function() return mq.TLO.Target.ID() end)
            if okTarg and targId then currentTargetId = targId end

            for idx, mob in ipairs(state.filteredSpawns) do
                ImGui.TableNextRow()

                local isSelected = (mob.id == currentTargetId)

                -- Column 1: Clean Name (Interactive row selectable)
                ImGui.TableSetColumnIndex(0)
                local conStyle = getConStyle(mob.conColor)
                local namePrefix = isSelected and "> " or ""
                local nameLabel = string.format("%s%s##TrackMob_%d_%d", namePrefix, mob.cleanName, mob.id, idx)
                if isSelected then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.9, 1.0, 1.0)
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, conStyle.r, conStyle.g, conStyle.b, 1.0)
                end
                if ImGui.Selectable(nameLabel, isSelected, ImGuiSelectableFlags.AllowDoubleClick or 0) then
                    if ImGui.IsMouseDoubleClicked(0) then
                        state.pendingTargetId = mob.id
                        state.pendingNavId = mob.id
                        state.activeNavTargetName = mob.cleanName
                        state.statusMsg = string.format("Queued Target & Nav to: %s (ID: %d)", mob.cleanName, mob.id)
                    else
                        state.pendingTargetId = mob.id
                        state.statusMsg = string.format("Queued Target: %s (ID: %d)", mob.cleanName, mob.id)
                    end
                end
                ImGui.PopStyleColor()
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("%s", string.format("%s (Level %d %s)\n[Click] Target  |  [Double-Click] Navigate", mob.cleanName, mob.level, mob.class))
                end

                -- Column 2: Level
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(tostring(mob.level))

                -- Column 3: Distance
                ImGui.TableSetColumnIndex(2)
                ImGui.Text(string.format("%.1fy", mob.distance))

                -- Column 4: Con Badge
                ImGui.TableSetColumnIndex(3)
                ImGui.TextColored(conStyle.r, conStyle.g, conStyle.b, 1.0, conStyle.badge)

                -- Column 5: Spawn ID
                ImGui.TableSetColumnIndex(4)
                ImGui.TextDisabled(tostring(mob.id))

                -- Column 6: Line of Sight
                ImGui.TableSetColumnIndex(5)
                if mob.lineOfSight then
                    ImGui.TextColored(0.2, 0.9, 0.3, 1.0, "YES")
                else
                    ImGui.TextDisabled("NO")
                end

                -- Column 7: Actions ([Target] & [Nav] buttons)
                ImGui.TableSetColumnIndex(6)
                local targBtnId = string.format("Targ##%d", mob.id)
                local navBtnId = string.format("Nav##%d", mob.id)

                if ImGui.SmallButton(targBtnId) then
                    state.pendingTargetId = mob.id
                    state.statusMsg = string.format("Queued Target: %s (ID: %d)", mob.cleanName, mob.id)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(navBtnId) then
                    state.pendingTargetId = mob.id
                    state.pendingNavId = mob.id
                    state.activeNavTargetName = mob.cleanName
                    state.statusMsg = string.format("Queued Nav to: %s (ID: %d)", mob.cleanName, mob.id)
                end
            end

            ImGui.EndTable()
        end

        ImGui.Separator()

        -- Footer Status Bar
        if state.activeNavTargetName ~= '' then
            ImGui.TextColored(0.2, 0.9, 0.4, 1.0, "NAV ACTIVE:")
            ImGui.SameLine()
            ImGui.Text(string.format("%s | %s", state.activeNavTargetName, state.statusMsg))
        else
            ImGui.TextDisabled("Status:")
            ImGui.SameLine()
            ImGui.Text(state.statusMsg)
        end
    end

    ImGui.End()
    popTheme()
end

-- ============================================================================
-- MAIN ENGINE INITIALIZATION & YIELDABLE LOOP
-- ============================================================================
scanZoneSpawns()
mq.imgui.init('TriuneZoneTrackerUI', DrawTrackerUI)

print('\ag[Triune Track]\ax Loaded -- Monitoring zone NPCs. Run with /lua run triune_track')

while state.isRunning do
    mq.doevents()

    local now = mq.gettime()
    if (now - state.lastScanTime) >= state.scanIntervalMs then
        state.lastScanTime = now
        scanZoneSpawns()
    end

    -- Process Non-Yieldable ImGui Actions in Coroutine Thread
    if state.pendingTargetId > 0 then
        local tid = state.pendingTargetId
        state.pendingTargetId = 0
        pcall(function() mq.cmdf('/target id %d', tid) end)
    end

    if state.pendingNavId > 0 then
        local nid = state.pendingNavId
        state.pendingNavId = 0
        state.activeNavId = nid
        local meshOk, meshLoaded = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
        if meshOk and meshLoaded then
            pcall(function() mq.cmdf('/nav id %d', nid) end)
        else
            pcall(function() mq.cmdf('/stick 10 id %d', nid) end)
        end
    end

    -- Auto-stop navigation upon arrival or if target died/invalidated
    if state.activeNavId > 0 then
        local okSp, sp = pcall(function() return mq.TLO.Spawn(state.activeNavId) end)
        if okSp and sp and sp() then
            local okDist, dist = pcall(function() return sp.Distance3D() end)
            local okDead, isDead = pcall(function() return sp.Dead() end)
            if (okDist and dist and dist <= 12) or (okDead and isDead) then
                pcall(function() mq.cmd('/nav stop') end)
                pcall(function() mq.cmd('/stick off') end)
                state.activeNavId = 0
                state.activeNavTargetName = ''
                state.statusMsg = (okDead and isDead) and 'Nav target died -- stopped.' or 'Arrived at destination.'
            end
        else
            pcall(function() mq.cmd('/nav stop') end)
            pcall(function() mq.cmd('/stick off') end)
            state.activeNavId = 0
            state.activeNavTargetName = ''
        end
    end

    mq.delay(50)
end

print('\ag[Triune Track]\ax Unloaded cleanly.')
