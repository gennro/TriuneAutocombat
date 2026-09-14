---@diagnostic disable: undefined-global, undefined-field, need-check-nil
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
    tickInterval       = 0.25,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Effects', tooltip = 'Toggles the popout Effects & Songs window.', flag = 'show_effects_window', key = 'effects', lockFlag = 'eff_lock', desc = 'Popout Effects & Songs with timers', headerButton = true, order = 80 },
}

-- Populated from the plugin entry points; typed so the language server
-- does not treat it as permanently nil.
local core = nil  ---@type table

local sortModes = {
    'Time Left (Ascending)',
    'Time Left (Descending)',
    'Name (A-Z)',
    'Buff Type',
    'Slot Order',
}

-- ---------------------------------------------------------------------------
-- TLO snapshot cache (same throttle pattern as hud_unitframes.refreshVitals).
-- refreshEffects() is shared by onTick and onDrawUI; whichever runs first
-- inside a REFRESH_INTERVAL window does the buff/song slot scan, and the
-- render pass only reads `snap`. Per-effect static facts (spell ID, icon, max
-- duration, level, description, beneficial flag, caster) are cached per slot
-- while the same spell name stays in that slot; only Duration / TotalCounters
-- are re-read each refresh. Each entry stores an `expiresAt` timestamp so the
-- remaining-time text and bar keep counting down smoothly between refreshes.
-- ---------------------------------------------------------------------------
local REFRESH_INTERVAL = 0.25
local lastRefreshAt = 0
local snap = { list = {}, sortMode = nil }
-- slotStatic[kind][slot] = { name = <spell name>, ...static facts... }
local slotStatic = { buff = {}, song = {} }
-- spellLookup[name] = { id, icon, maxDur, level, desc, ben } or false (negative
-- result memoized so permanent buffs are not re-queried via Spell(name) forever).
local spellLookup = {}
-- Song slot upper bound: Me.Song(i) is slot-indexed and slots can have gaps,
-- so we walk the whole slot range and skip empties (CountSongs is only a
-- count). Resolved once from Me.MaxSongSlots when the binding has it.
local SONG_SLOT_FALLBACK = 30
local songSlotMax = nil

local function invalidateEffects()
    lastRefreshAt = 0
end

-- Mark the snapshot list dirty when a display filter changes so the next
-- refresh (tick or draw) rebuilds immediately instead of waiting a cycle.
local function onFilterChanged()
    core.saveLoadout(true)
    invalidateEffects()
end

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
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##effToggleWin', core.px(250), core.px(24)) then
        ctrl.show_effects_window = not isWinOpen
        core.saveLoadout(true)
    end

    local curSort = ctrl.eff_sort_by or 'Time Left (Ascending)'
    local curSortIdx = core.idxOf(sortModes, curSort)
    if curSortIdx < 1 then curSortIdx = 1 end

    ImGui.Text('Sort Order:')
    ImGui.SetNextItemWidth(core.px(180))
    local newSortIdx = ImGui.Combo('##effSortCombo', curSortIdx, sortModes)
    if newSortIdx ~= curSortIdx and sortModes[newSortIdx] then
        ctrl.eff_sort_by = sortModes[newSortIdx]
        onFilterChanged()
    end

    for idx, sm in ipairs(sortModes) do
        local isSel = (curSort == sm)
        if ImGui.MenuItem(sm .. '##menuSort_' .. idx, nil, isSel) then
            ctrl.eff_sort_by = sm
            onFilterChanged()
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
        onFilterChanged()
    end

    local sVal = ImGui.Checkbox('Show Songs & Disciplines##effSongs', ctrl.eff_show_songs ~= false)
    if sVal ~= (ctrl.eff_show_songs ~= false) then
        ctrl.eff_show_songs = sVal
        onFilterChanged()
    end

    local dVal = ImGui.Checkbox('Show Detrimental (Debuffs)##effDet', ctrl.eff_show_detrimental ~= false)
    if dVal ~= (ctrl.eff_show_detrimental ~= false) then
        ctrl.eff_show_detrimental = dVal
        onFilterChanged()
    end

    if core.drawWindowScaleControl then core.drawWindowScaleControl('effects', 'Scale', 120) end
    ImGui.SetNextItemWidth(core.px(120))
    local newAlpha = ImGui.SliderFloat('Opacity##effAlpha', ctrl.eff_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.eff_alpha or 0.85) then
        ctrl.eff_alpha = newAlpha
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(core.px(120))
    local newH = ImGui.SliderInt('Bar Height##effHeight', ctrl.eff_bar_height or 18, 12, 28)
    if newH ~= (ctrl.eff_bar_height or 18) then
        ctrl.eff_bar_height = newH
        core.saveLoadout(true)
    end
end

function plugin.onDrawSettings()
    renderEffSettingsContent()
end

-- ---------------------------------------------------------------------------
-- Scan helpers
-- ---------------------------------------------------------------------------

-- Memoized mq.TLO.Spell(name) fallback (positive and negative results) used
-- when the buff/song object itself reports no ID / icon / max duration.
local function lookupSpellByName(mq, name)
    local hit = spellLookup[name]
    if hit ~= nil then return hit end
    local res = false  ---@type table|false
    pcall(function()
        local sp = mq.TLO.Spell(name)
        if sp and sp() then
            local r = { id = 0, icon = 0, maxDur = 0, level = 0, desc = '', ben = nil }
            pcall(function() r.id = sp.ID() or 0 end)
            pcall(function() r.icon = sp.SpellIcon() or 0 end)
            pcall(function()
                r.maxDur = core.parseDurationSec(sp.Duration)
                if r.maxDur == 0 then r.maxDur = core.parseDurationSec(sp.MyDuration) end
            end)
            pcall(function() r.level = sp.Level() or 0 end)
            pcall(function() if sp.Description then r.desc = sp.Description() or '' end end)
            pcall(function() r.ben = (sp.Beneficial() ~= false) end)
            res = r
        end
    end)
    spellLookup[name] = res
    return res
end

-- Static per-(slot, spellName) facts. Re-queried only when the spell name in
-- that slot changes; `obj` is the Me.Buff(i) / Me.Song(i) accessor.
local function readStaticFacts(mq, obj, name)
    local st = { name = name, spellId = 0, iconId = 0, maxDur = 0, isBen = true, caster = 'Unknown', level = 0, desc = '' }
    pcall(function() st.spellId = obj.Spell.ID() or obj.ID() or 0 end)
    pcall(function() st.iconId = obj.Spell.SpellIcon() or obj.SpellIcon() or 0 end)
    pcall(function()
        if obj.Spell and obj.Spell.Duration then
            st.maxDur = core.parseDurationSec(obj.Spell.Duration)
        end
        if st.maxDur <= 0 and obj.Spell and obj.Spell.MyDuration then
            st.maxDur = core.parseDurationSec(obj.Spell.MyDuration)
        end
    end)
    pcall(function() st.isBen = obj.Beneficial() ~= false end)
    pcall(function() st.caster = obj.Caster() or 'Unknown' end)
    pcall(function() st.level = (obj.Spell and obj.Spell.Level and obj.Spell.Level()) or 0 end)
    pcall(function() st.desc = (obj.Spell and obj.Spell.Description and obj.Spell.Description()) or '' end)

    if st.spellId == 0 or st.iconId == 0 or st.maxDur == 0 then
        local sp = lookupSpellByName(mq, name)
        if sp then
            if st.spellId == 0 then st.spellId = sp.id end
            if st.iconId == 0 then st.iconId = sp.icon end
            if st.maxDur == 0 then st.maxDur = sp.maxDur end
            if st.level == 0 then st.level = sp.level end
            if st.desc == '' then st.desc = sp.desc end
            if st.isBen and sp.ben ~= nil then st.isBen = sp.ben end
        end
    end
    return st
end

-- Per-refresh dynamic facts: remaining duration and counters.
local function readDynamicFacts(obj)
    local dur, counters = 0, 0
    pcall(function() dur = core.parseDurationSec(obj.Duration) end)
    if dur <= 0 then
        pcall(function()
            if obj.DurationTicks then dur = (tonumber(obj.DurationTicks()) or 0) * 6 end
        end)
    end
    pcall(function() counters = obj.TotalCounters() or 0 end)
    return dur, counters
end

-- Walks one slot range (buffs or songs) into `list`, using / refreshing the
-- static cache for that kind. `getter(i)` returns mq.TLO.Me.Buff(i) / Me.Song(i).
local function scanSlots(mq, ctrl, kind, getter, maxSlots, isSong, now, list)
    local statics = slotStatic[kind]
    local showDet = (ctrl.eff_show_detrimental ~= false)
    for i = 1, maxSlots do
        local present = false
        pcall(function()
            local obj = getter(i)
            if obj and obj() then
                local name = obj.Name() or obj()
                if name and name ~= '' then
                    present = true
                    local st = statics[i]
                    if not st or st.name ~= name then
                        st = readStaticFacts(mq, obj, name)
                        statics[i] = st
                    end
                    local dur, counters = readDynamicFacts(obj)
                    local maxDur = st.maxDur
                    if maxDur < dur then maxDur = dur end
                    if showDet or st.isBen then
                        list[#list + 1] = {
                            slot = i,
                            name = name,
                            spellId = st.spellId,
                            iconId = st.iconId,
                            duration = dur,
                            expiresAt = (dur > 0) and (now + dur) or nil,
                            maxDuration = maxDur,
                            isSong = isSong,
                            isBeneficial = st.isBen,
                            caster = st.caster,
                            level = st.level,
                            description = st.desc,
                            counters = counters,
                        }
                    end
                end
            end
        end)
        if not present then statics[i] = nil end
    end
end

local function resolveSongSlotMax(mq)
    if songSlotMax then return songSlotMax end
    local n = nil
    pcall(function()
        local v = mq.TLO.Me.MaxSongSlots
        if v then n = tonumber(v()) end
    end)
    if n and n > 0 and n <= 60 then
        songSlotMax = n
    else
        songSlotMax = SONG_SLOT_FALLBACK
    end
    return songSlotMax
end

local function sortEffects(list, sortMode)
    if sortMode == 'Name (A-Z)' then
        table.sort(list, function(a, b)
            return (a.name or ''):lower() < (b.name or ''):lower()
        end)
    elseif sortMode == 'Time Left (Ascending)' then
        table.sort(list, function(a, b)
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
        table.sort(list, function(a, b)
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
        -- 1 = Detrimental, 2 = Songs/Discs, 3 = Timed Buffs, 4 = Permanent Buffs
        local function typeRank(e)
            if not e.isBeneficial then return 1 end
            if e.isSong then return 2 end
            if e.duration and e.duration > 0 then return 3 end
            return 4
        end
        table.sort(list, function(a, b)
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
        table.sort(list, function(a, b)
            if a.isSong ~= b.isSong then
                return not a.isSong
            end
            return (a.slot or 0) < (b.slot or 0)
        end)
    end
end

-- Snapshot every buff / song slot the window needs. Shared by onTick and the
-- render pass; the throttle makes whichever runs first do the work.
local function refreshEffects(force)
    if not core or not core.mq or not core.ctrl then return end
    local ctrl = core.ctrl
    if not ctrl.show_effects_window then
        if #snap.list > 0 then snap.list = {} end
        return
    end
    local now = os.clock()
    if not force and (now - lastRefreshAt) < REFRESH_INTERVAL then return end
    lastRefreshAt = now

    local mq = core.mq
    local list = {}

    -- 1. Long Buffs
    if ctrl.eff_show_buffs ~= false then
        local maxBuffs = 42
        pcall(function() maxBuffs = mq.TLO.Me.MaxBuffSlots() or 42 end)
        scanSlots(mq, ctrl, 'buff', function(i) return mq.TLO.Me.Buff(i) end, maxBuffs, false, now, list)
    end

    -- 2. Short Buffs / Songs & Disciplines (slot-indexed; gaps are skipped)
    if ctrl.eff_show_songs ~= false then
        scanSlots(mq, ctrl, 'song', function(i) return mq.TLO.Me.Song(i) end, resolveSongSlotMax(mq), true, now, list)
    end

    local sortMode = ctrl.eff_sort_by or 'Time Left (Ascending)'
    sortEffects(list, sortMode)
    snap.list = list
    snap.sortMode = sortMode
end

function plugin.onTick()
    refreshEffects(false)
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
    ImGui.SetNextWindowSize(core.px(280), core.px(420), ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.eff_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    core.preBeginWindow('effects')
    -- Pushed after preBeginWindow so this tight chrome wins over the scaled theme padding.
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, core.px(4), core.px(4))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, core.px(3), core.px(2))
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, core.px(2), core.px(1))
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
        local barH = core.px(ctrl.eff_bar_height or 18)

        if ImGui.BeginPopupContextWindow('##effWinContextMenu') then
            if core.applyWindowScale then core.applyWindowScale('effects') end
            renderEffSettingsContent()
            ImGui.EndPopup()
        end

        -- Throttled; normally a no-op because onTick already refreshed this cycle.
        refreshEffects(false)
        local effectsList = snap.list
        -- Sort mode changed since the last scan: re-sort the cached list (no TLOs).
        local sortMode = ctrl.eff_sort_by or 'Time Left (Ascending)'
        if snap.sortMode ~= sortMode then
            sortEffects(effectsList, sortMode)
            snap.sortMode = sortMode
        end
        local now = os.clock()

        -- Render Effects List
        if #effectsList == 0 then
            accent(MUTED, 'No active spells or effects.')
        else
            for _, eff in ipairs(effectsList) do
                local rowKey = (eff.isSong and 's_' or 'b_') .. tostring(eff.slot) .. '_' .. tostring(eff.spellId)
                -- Live remaining time from the cached expiry timestamp
                local duration = 0
                if eff.expiresAt then
                    duration = math.max(0, eff.expiresAt - now)
                end
                local isTimed = (eff.expiresAt ~= nil)
                local barFrac = 1.0
                if eff.maxDuration > 0 and isTimed then
                    barFrac = math.min(1.0, math.max(0.0, duration / eff.maxDuration))
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
                if isTimed then
                    timeStr = core.fmtSec(duration)
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
                        isTimed and string.format('Time Left: %s (Total: %s)', core.fmtSec(duration), core.fmtSec(eff.maxDuration)) or 'Duration: Permanent / Aura',
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
