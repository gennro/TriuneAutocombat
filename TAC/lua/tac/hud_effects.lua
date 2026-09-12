---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_effects.lua — Triune Popout Effects & Songs Window Plugin
-- ============================================================================
-- Unified view of active buffs, songs & disciplines: full spell names, native
-- spell icons, remaining-time progress bars, multi-criteria sorting, and a
-- per-row right-click menu (Remove Buff, Block Buff, Display Spell Info).
--
-- Render-only plugin driven by ctrl.show_effects_window; the header buttons,
-- Mini HUD, window manager, and /ac eff keep working unchanged.
-- ============================================================================

local plugin = {
    id                 = 'hud_effects',
    name               = 'Effects & Songs HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout buffs, songs & disciplines window with spell icons, time-left bars, sorting, and right-click actions.',
    defaultEnabled     = true,
    tickInterval       = 1.0,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Effects', tooltip = 'Toggles the popout Effects & Songs window.', flag = 'show_effects_window', key = 'effects', lockFlag = 'eff_lock', desc = 'Popout Effects & Songs with timers', headerButton = true, order = 80 },
}

local core = nil

local sortModes = {
    'Time Left (Ascending)',
    'Time Left (Descending)',
    'Name (A-Z)',
    'Buff Type',
    'Slot Order',
}

function plugin.onInit(coreApi)
    core = coreApi
    local ctrl = core and core.ctrl
    if ctrl then
        if ctrl.show_effects_window == nil then ctrl.show_effects_window = false end
        if ctrl.eff_lock == nil then ctrl.eff_lock = false end
        if ctrl.eff_alpha == nil then ctrl.eff_alpha = 0.85 end
        if ctrl.eff_bar_height == nil then ctrl.eff_bar_height = 18 end
        if ctrl.eff_sort_by == nil then ctrl.eff_sort_by = 'Time Left (Ascending)' end
        if ctrl.eff_show_buffs == nil then ctrl.eff_show_buffs = true end
        if ctrl.eff_show_songs == nil then ctrl.eff_show_songs = true end
        if ctrl.eff_show_detrimental == nil then ctrl.eff_show_detrimental = true end
    end
end

function plugin.onDestroy()
end

-- Settings renderer (right-click on window background, and Plugins tab)
local function renderEffSettingsContent()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local accent = core.accent
    local GOLD = core.colors.GOLD

    accent(GOLD, 'Effects & Songs Options')
    ImGui.Separator()

    local isWinOpen = (ctrl.show_effects_window == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##effToggleWin', 250, 24) then
        ctrl.show_effects_window = not isWinOpen
        core.saveLoadout(true)
    end

    local curSort = ctrl.eff_sort_by or 'Time Left (Ascending)'
    local curSortIdx = core.idxOf(sortModes, curSort)
    if curSortIdx < 1 then curSortIdx = 1 end

    ImGui.Text('Sort Order:')
    ImGui.SetNextItemWidth(180)
    local newSortIdx = ImGui.Combo('##effSortCombo', curSortIdx, sortModes)
    if newSortIdx ~= curSortIdx and sortModes[newSortIdx] then
        ctrl.eff_sort_by = sortModes[newSortIdx]
        core.saveLoadout(true)
    end

    for idx, sm in ipairs(sortModes) do
        local isSel = (curSort == sm)
        if ImGui.MenuItem(sm .. '##menuSort_' .. idx, nil, isSel) then
            ctrl.eff_sort_by = sm
            core.saveLoadout(true)
        end
    end

    ImGui.Separator()
    local lockVal = ImGui.Checkbox('Lock Window Position & Size##effLock', ctrl.eff_lock or false)
    if lockVal ~= (ctrl.eff_lock or false) then
        ctrl.eff_lock = lockVal
        core.saveLoadout(true)
    end

    local bVal = ImGui.Checkbox('Show Long Buffs##effBuffs', ctrl.eff_show_buffs ~= false)
    if bVal ~= (ctrl.eff_show_buffs ~= false) then
        ctrl.eff_show_buffs = bVal
        core.saveLoadout(true)
    end

    local sVal = ImGui.Checkbox('Show Songs & Disciplines##effSongs', ctrl.eff_show_songs ~= false)
    if sVal ~= (ctrl.eff_show_songs ~= false) then
        ctrl.eff_show_songs = sVal
        core.saveLoadout(true)
    end

    local dVal = ImGui.Checkbox('Show Detrimental (Debuffs)##effDet', ctrl.eff_show_detrimental ~= false)
    if dVal ~= (ctrl.eff_show_detrimental ~= false) then
        ctrl.eff_show_detrimental = dVal
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(120)
    local newAlpha = ImGui.SliderFloat('Opacity##effAlpha', ctrl.eff_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.eff_alpha or 0.85) then
        ctrl.eff_alpha = newAlpha
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(120)
    local newH = ImGui.SliderInt('Bar Height##effHeight', ctrl.eff_bar_height or 18, 12, 28)
    if newH ~= (ctrl.eff_bar_height or 18) then
        ctrl.eff_bar_height = newH
        core.saveLoadout(true)
    end
end

function plugin.onDrawSettings()
    renderEffSettingsContent()
end

function plugin.onDrawUI()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local mq = core.mq
    local accent = core.accent
    local GOLD, MUTED = core.colors.GOLD, core.colors.MUTED
    if not ctrl.show_effects_window then return end
    core.pushTheme()

    if ctrl.eff_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.eff_alpha)
    end
    ImGui.SetNextWindowSize(280, 420, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.eff_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 2, 1)

    core.preBeginWindow('effects')
    local show
    ctrl.show_effects_window, show = ImGui.Begin('Triune Effects & Songs v' .. (core.VERSION or '') .. '###triuneEffectsWindow', ctrl.show_effects_window, winFlags)
    if not ctrl.show_effects_window then
        ImGui.End()
        ImGui.PopStyleVar(3)
        core.popTheme()
        return
    end

    if show then
        core.postBeginWindow('effects')
        local barH = ctrl.eff_bar_height or 18

        if ImGui.BeginPopupContextWindow('##effWinContextMenu') then
            renderEffSettingsContent()
            ImGui.EndPopup()
        end

        -- Collect Active Buffs and Songs
        local effectsList = {}
        local maxBuffs = 42
        pcall(function() maxBuffs = mq.TLO.Me.MaxBuffSlots() or 42 end)

        -- 1. Long Buffs
        if ctrl.eff_show_buffs ~= false then
            for i = 1, maxBuffs do
                pcall(function()
                    local b = mq.TLO.Me.Buff(i)
                    if b and b() then
                        local bName = b.Name() or b()
                        if bName and bName ~= '' then
                            local bId = 0
                            local iconId = 0
                            local dur = 0
                            local maxDur = 0
                            local isBen = true
                            local caster = 'Unknown'
                            local lvl = 0
                            local desc = ''
                            local counters = 0

                            pcall(function() bId = b.Spell.ID() or b.ID() or 0 end)
                            pcall(function() iconId = b.Spell.SpellIcon() or b.SpellIcon() or 0 end)
                            pcall(function() dur = core.parseDurationSec(b.Duration) end)
                            if dur <= 0 then
                                pcall(function()
                                    if b.DurationTicks then dur = (tonumber(b.DurationTicks()) or 0) * 6 end
                                end)
                            end
                            pcall(function()
                                if b.Spell and b.Spell.Duration then
                                    maxDur = core.parseDurationSec(b.Spell.Duration)
                                end
                                if maxDur <= 0 and b.Spell and b.Spell.MyDuration then
                                    maxDur = core.parseDurationSec(b.Spell.MyDuration)
                                end
                            end)
                            pcall(function() isBen = b.Beneficial() ~= false end)
                            pcall(function() caster = b.Caster() or 'Unknown' end)
                            pcall(function() lvl = (b.Spell and b.Spell.Level and b.Spell.Level()) or 0 end)
                            pcall(function() desc = (b.Spell and b.Spell.Description and b.Spell.Description()) or '' end)
                            pcall(function() counters = b.TotalCounters() or 0 end)

                            if (bId == 0 or iconId == 0 or maxDur == 0) and bName ~= '' then
                                pcall(function()
                                    local sp = mq.TLO.Spell(bName)
                                    if sp and sp() then
                                        if bId == 0 then bId = sp.ID() or 0 end
                                        if iconId == 0 then iconId = sp.SpellIcon() or 0 end
                                        if maxDur == 0 then maxDur = core.parseDurationSec(sp.Duration) end
                                        if maxDur == 0 then maxDur = core.parseDurationSec(sp.MyDuration) end
                                        if lvl == 0 then lvl = sp.Level() or 0 end
                                        if desc == '' and sp.Description then desc = sp.Description() or '' end
                                        if isBen then isBen = sp.Beneficial() ~= false end
                                    end
                                end)
                            end
                            if maxDur < dur then maxDur = dur end

                            if ctrl.eff_show_detrimental ~= false or isBen then
                                table.insert(effectsList, {
                                    slot = i,
                                    name = bName,
                                    spellId = bId,
                                    iconId = iconId,
                                    duration = dur,
                                    maxDuration = maxDur,
                                    isSong = false,
                                    isBeneficial = isBen,
                                    caster = caster,
                                    level = lvl,
                                    description = desc,
                                    counters = counters,
                                })
                            end
                        end
                    end
                end)
            end
        end

        -- 2. Short Buffs / Songs & Disciplines
        if ctrl.eff_show_songs ~= false then
            local maxSongs = 30
            pcall(function() maxSongs = mq.TLO.Me.CountSongs() or 30 end)
            for i = 1, maxSongs do
                pcall(function()
                    local s = mq.TLO.Me.Song(i)
                    if s and s() then
                        local sName = s.Name() or s()
                        if sName and sName ~= '' then
                            local sId = 0
                            local iconId = 0
                            local dur = 0
                            local maxDur = 0
                            local isBen = true
                            local caster = 'Unknown'
                            local lvl = 0
                            local desc = ''
                            local counters = 0

                            pcall(function() sId = s.Spell.ID() or s.ID() or 0 end)
                            pcall(function() iconId = s.Spell.SpellIcon() or s.SpellIcon() or 0 end)
                            pcall(function() dur = core.parseDurationSec(s.Duration) end)
                            if dur <= 0 then
                                pcall(function()
                                    if s.DurationTicks then dur = (tonumber(s.DurationTicks()) or 0) * 6 end
                                end)
                            end
                            pcall(function()
                                if s.Spell and s.Spell.Duration then
                                    maxDur = core.parseDurationSec(s.Spell.Duration)
                                end
                                if maxDur <= 0 and s.Spell and s.Spell.MyDuration then
                                    maxDur = core.parseDurationSec(s.Spell.MyDuration)
                                end
                            end)
                            pcall(function() isBen = s.Beneficial() ~= false end)
                            pcall(function() caster = s.Caster() or 'Unknown' end)
                            pcall(function() lvl = (s.Spell and s.Spell.Level and s.Spell.Level()) or 0 end)
                            pcall(function() desc = (s.Spell and s.Spell.Description and s.Spell.Description()) or '' end)
                            pcall(function() counters = s.TotalCounters() or 0 end)

                            if (sId == 0 or iconId == 0 or maxDur == 0) and sName ~= '' then
                                pcall(function()
                                    local sp = mq.TLO.Spell(sName)
                                    if sp and sp() then
                                        if sId == 0 then sId = sp.ID() or 0 end
                                        if iconId == 0 then iconId = sp.SpellIcon() or 0 end
                                        if maxDur == 0 then maxDur = core.parseDurationSec(sp.Duration) end
                                        if maxDur == 0 then maxDur = core.parseDurationSec(sp.MyDuration) end
                                        if lvl == 0 then lvl = sp.Level() or 0 end
                                        if desc == '' and sp.Description then desc = sp.Description() or '' end
                                        if isBen then isBen = sp.Beneficial() ~= false end
                                    end
                                end)
                            end
                            if maxDur < dur then maxDur = dur end

                            if ctrl.eff_show_detrimental ~= false or isBen then
                                table.insert(effectsList, {
                                    slot = i,
                                    name = sName,
                                    spellId = sId,
                                    iconId = iconId,
                                    duration = dur,
                                    maxDuration = maxDur,
                                    isSong = true,
                                    isBeneficial = isBen,
                                    caster = caster,
                                    level = lvl,
                                    description = desc,
                                    counters = counters,
                                })
                            end
                        end
                    end
                end)
            end
        end

        -- Sort Effects List
        local sortMode = ctrl.eff_sort_by or 'Time Left (Ascending)'
        if sortMode == 'Name (A-Z)' then
            table.sort(effectsList, function(a, b)
                return (a.name or ''):lower() < (b.name or ''):lower()
            end)
        elseif sortMode == 'Time Left (Ascending)' then
            table.sort(effectsList, function(a, b)
                local aTimed = (a.duration and a.duration > 0)
                local bTimed = (b.duration and b.duration > 0)
                -- Timed buffs come first (expiring soonest first), permanent buffs at bottom
                if aTimed and not bTimed then return true end
                if not aTimed and bTimed then return false end
                if aTimed and bTimed then
                    if a.duration ~= b.duration then return a.duration < b.duration end
                end
                return (a.name or ''):lower() < (b.name or ''):lower()
            end)
        elseif sortMode == 'Time Left (Descending)' then
            table.sort(effectsList, function(a, b)
                local aTimed = (a.duration and a.duration > 0)
                local bTimed = (b.duration and b.duration > 0)
                -- Permanent buffs have most time (at top), then longest duration
                if not aTimed and bTimed then return true end
                if aTimed and not bTimed then return false end
                if aTimed and bTimed then
                    if a.duration ~= b.duration then return a.duration > b.duration end
                end
                return (a.name or ''):lower() < (b.name or ''):lower()
            end)
        elseif sortMode == 'Buff Type' then
            table.sort(effectsList, function(a, b)
                -- 1 = Detrimental, 2 = Songs/Discs, 3 = Timed Buffs, 4 = Permanent Buffs
                local function typeRank(e)
                    if not e.isBeneficial then return 1 end
                    if e.isSong then return 2 end
                    if e.duration and e.duration > 0 then return 3 end
                    return 4
                end
                local rA, rB = typeRank(a), typeRank(b)
                if rA ~= rB then return rA < rB end
                local aTimed = (a.duration and a.duration > 0)
                local bTimed = (b.duration and b.duration > 0)
                if aTimed and not bTimed then return true end
                if not aTimed and bTimed then return false end
                if aTimed and bTimed then
                    if a.duration ~= b.duration then return a.duration < b.duration end
                end
                return (a.name or ''):lower() < (b.name or ''):lower()
            end)
        elseif sortMode == 'Slot Order' then
            table.sort(effectsList, function(a, b)
                if a.isSong ~= b.isSong then
                    return not a.isSong
                end
                return (a.slot or 0) < (b.slot or 0)
            end)
        end

        -- Render Effects List
        if #effectsList == 0 then
            accent(MUTED, 'No active spells or effects.')
        else
            for _, eff in ipairs(effectsList) do
                local rowKey = (eff.isSong and 's_' or 'b_') .. tostring(eff.slot) .. '_' .. tostring(eff.spellId)
                local barFrac = 1.0
                if eff.maxDuration > 0 and eff.duration > 0 then
                    barFrac = math.min(1.0, math.max(0.0, eff.duration / eff.maxDuration))
                end

                -- Dynamic Color Palette
                local br, bg, bb = 0.22, 0.55, 0.85
                if not eff.isBeneficial then
                    br, bg, bb = 0.88, 0.20, 0.20
                elseif eff.isSong then
                    br, bg, bb = 0.85, 0.60, 0.20
                end

                -- Time Left Text
                local timeStr = 'Perm'
                if eff.duration > 0 then
                    timeStr = core.fmtSec(eff.duration)
                end

                -- Draw Spell Icon if available
                local iconDrawn = false  -- luacheck: ignore 311
                if eff.iconId and eff.iconId > 0 then
                    iconDrawn = core.drawSpellIcon(eff.iconId, barH)
                    if iconDrawn then
                        ImGui.SameLine()
                    end
                end

                -- Progress bar with full spell name and remaining time
                local fullLabel = string.format('%s  [%s]', eff.name, timeStr)
                core.drawStatusProgressBar(barFrac, -1, barH, fullLabel, br, bg, bb, 0.85)

                -- Right-click context menu on the buff row (Remove, Block, Spell Info)
                if ImGui.BeginPopupContextItem('##effItemMenu_' .. rowKey) then
                    accent(GOLD, eff.name)
                    if eff.caster and eff.caster ~= '' and eff.caster ~= 'Unknown' then
                        ImGui.TextDisabled('Caster: ' .. eff.caster)
                    end
                    ImGui.Separator()
                    if ImGui.MenuItem('Remove Buff##rm_' .. rowKey) then
                        mq.cmdf('/removebuff %s', eff.name)
                    end
                    if eff.spellId and eff.spellId > 0 then
                        if ImGui.MenuItem('Add to Block Buff List##blk_' .. rowKey) then
                            mq.cmdf('/blockspell add me %d', eff.spellId)
                            print(string.format('\ag[Triune]\ax Added %s (ID %d) to blocked buffs.', eff.name, eff.spellId))
                        end
                        if ImGui.MenuItem('Display Spell Info##insp_' .. rowKey) then
                            pcall(function() mq.TLO.Spell(eff.spellId).Inspect() end)
                        end
                    end
                    ImGui.EndPopup()
                end

                -- Hover Tooltip
                if ImGui.IsItemHovered() then
                    local lines = {
                        string.format('%s (%s)', eff.name, eff.isSong and 'Song / Disc' or 'Buff'),
                        string.format('Slot: %d  |  ID: %d', eff.slot, eff.spellId),
                        eff.duration > 0 and string.format('Time Left: %s (Total: %s)', core.fmtSec(eff.duration), core.fmtSec(eff.maxDuration)) or 'Duration: Permanent / Aura',
                    }
                    if eff.caster and eff.caster ~= '' and eff.caster ~= 'Unknown' then
                        table.insert(lines, 'Caster: ' .. eff.caster)
                    end
                    if eff.level and eff.level > 0 then
                        table.insert(lines, string.format('Spell Level: %d', eff.level))
                    end
                    if eff.counters and eff.counters > 0 then
                        table.insert(lines, string.format('Counters: %d', eff.counters))
                    end
                    if eff.description and eff.description ~= '' then
                        table.insert(lines, '---')
                        table.insert(lines, eff.description)
                    end
                    table.insert(lines, 'Right-click for options (Remove, Block, Info)')
                    core.setTooltip('%s', table.concat(lines, '\n'))
                end
            end
        end
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    core.popTheme()
end

return plugin
