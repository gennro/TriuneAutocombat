---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_xtarget.lua — Triune Popout Extended Target Window Plugin
-- ============================================================================
-- Compact, auto-scaling replacement for EverQuest's Extended Target window:
-- con-colored names, HP bars, aggro %, distance / LoS, target-of-target, and a
-- per-row right-click menu (Target, Face, Add to Ignore List).
--
-- No fiber: onTick (every 0.25 s) snapshots the XTarget slots into a cache
-- (static facts per slot/spawn id are cached; only HP, distance, LoS, aggro
-- and ToT are re-read) and onDrawUI renders that cache. The same throttled
-- refresh also runs from the render pass so the window stays live while the
-- main loop is blocked. Visibility is ctrl.show_xtarget_window; the header
-- buttons, Mini HUD, window manager, and /ac xtar keep working unchanged.
-- ============================================================================

local plugin = {
    id                 = 'hud_xtarget',
    name               = 'Extended Target HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout Extended Target window with HP bars, aggro %, distance/LoS, ToT, and right-click actions.',
    defaultEnabled     = true,
    tickInterval       = 0.25,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'XTarget', tooltip = 'Toggles the popout Extended Target (XTarget) window.', flag = 'show_xtarget_window', key = 'xtarget', lockFlag = 'xt_lock', desc = 'Popout Extended Target (XTarget) vitals', headerButton = true, order = 90 },
}

local core = nil

-- ---------------------------------------------------------------------------
-- TLO snapshot cache (same throttle pattern as hud_unitframes.refreshVitals).
-- refreshXTargets() is shared by onTick and onDrawUI; whichever runs first
-- inside a REFRESH_INTERVAL window walks the XTarget slots and the render
-- pass only reads `snap`. Static facts (TargetType, Type, Class, Level,
-- ConColor) are cached per (slot, spawn id) in `slotStatic`; only HP,
-- distance, LoS, aggro and target-of-target are re-read each refresh.
-- ---------------------------------------------------------------------------
local REFRESH_INTERVAL = 0.25
local lastRefreshAt = 0
local snap = { slots = {}, slotCount = 0, activeCount = 0, currentTargetId = 0 }
-- slotStatic[slot] = { id = <spawn id>, name, level, class, con, targetType, spawnType }
local slotStatic = {}

-- Set of pet spawn ids (own, group and Trio extra pets) from
-- core.getMultiPetList(), built once per refresh instead of per slot.
local function buildPetIdSet()
    local set = {}
    if not core or not core.getMultiPetList then return set end
    local okList, petSlots, extraPets = pcall(core.getMultiPetList)
    if not okList then return set end
    for _, ps in ipairs(petSlots or {}) do
        if ps.petId and ps.petId > 0 then set[ps.petId] = true end
    end
    for _, pid in ipairs(extraPets or {}) do
        if pid and pid > 0 then set[pid] = true end
    end
    return set
end

function plugin.onInit(coreApi)
    core = coreApi
    lastRefreshAt = 0
    slotStatic = {}
    local ctrl = core and core.ctrl
    if ctrl then
        if ctrl.show_xtarget_window == nil then ctrl.show_xtarget_window = false end
        if ctrl.xt_lock == nil then ctrl.xt_lock = false end
        if ctrl.xt_alpha == nil then ctrl.xt_alpha = 0.85 end
        if ctrl.xt_bar_height == nil then ctrl.xt_bar_height = 16 end
        if ctrl.xt_show_empty == nil then ctrl.xt_show_empty = false end
        if ctrl.xt_show_tot == nil then ctrl.xt_show_tot = true end
        if ctrl.xt_show_aggro == nil then ctrl.xt_show_aggro = true end
        if ctrl.xt_show_dist == nil then ctrl.xt_show_dist = true end
        if ctrl.xt_show_pets == nil then ctrl.xt_show_pets = false end
        if ctrl.xt_show_pcs == nil then ctrl.xt_show_pcs = false end
    end
end

-- Friendly XTarget slot types (pets, mercenaries, group/raid role slots that
-- point at players). Matched case-insensitively against XTarget.TargetType.
local FRIENDLY_SLOT_PATTERNS = { 'pet', 'mercenary', 'group tank', 'group assist', 'group puller', 'raid assist', 'specific pc' }

-- Returns true when this slot should be hidden: pets (own, group, and the
-- Trio's extra pets) and friendly PCs are not hostiles, so they only clutter
-- the extended target list unless the user opts in. `petIds` is the pet id
-- set from buildPetIdSet() (built once per refresh); when nil it is looked
-- up on the spot.
local function isHiddenSlot(spawnType, targetType, spawnId, petIds)
    local sType = tostring(spawnType or ''):lower()
    local tType = tostring(targetType or ''):lower()
    local isPet = (sType == 'pet')
    local isPc = (sType == 'pc' or sType == 'mercenary')
    if not isPet and not isPc then
        for _, pat in ipairs(FRIENDLY_SLOT_PATTERNS) do
            -- "... Target" slot types (e.g. "Group Tank Target") point at what the
            -- friendly is fighting, which is usually a hostile: keep those.
            if tType:find(pat, 1, true) and not tType:find(' target', 1, true) then
                if pat == 'pet' or pat == 'mercenary' then isPet = true else isPc = true end
                break
            end
        end
    end
    if not isPet and spawnId and spawnId > 0 then
        if petIds == nil then petIds = buildPetIdSet() end
        if petIds[spawnId] then isPet = true end
    end
    local ctrl = core.ctrl
    if isPet and not ctrl.xt_show_pets then return true end
    if isPc and not ctrl.xt_show_pcs then return true end
    return false
end

function plugin.onDestroy()
    snap.slots = {}
    snap.activeCount = 0
    slotStatic = {}
    lastRefreshAt = 0
end

-- Settings renderer (right-click on window background, and Plugins tab)
local function renderXtSettingsContent()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local accent = core.accent
    local GOLD = core.colors.GOLD

    accent(GOLD, 'Extended Target Options')
    ImGui.Separator()

    local isWinOpen = (ctrl.show_xtarget_window == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##xtToggleWin', core.px(250), core.px(24)) then
        ctrl.show_xtarget_window = not isWinOpen
        core.saveLoadout(true)
    end

    local lockVal = ImGui.Checkbox('Lock Window Position & Size##xtLock', ctrl.xt_lock or false)
    if lockVal ~= (ctrl.xt_lock or false) then
        ctrl.xt_lock = lockVal
        core.saveLoadout(true)
    end

    local empVal = ImGui.Checkbox('Show Empty Slots##xtEmpty', ctrl.xt_show_empty or false)
    if empVal ~= (ctrl.xt_show_empty or false) then
        ctrl.xt_show_empty = empVal
        core.saveLoadout(true)
    end

    local totVal = ImGui.Checkbox('Show Target of Target##xtTot', ctrl.xt_show_tot ~= false)
    if totVal ~= (ctrl.xt_show_tot ~= false) then
        ctrl.xt_show_tot = totVal
        core.saveLoadout(true)
    end

    local aggVal = ImGui.Checkbox('Show Aggro %##xtAggro', ctrl.xt_show_aggro ~= false)
    if aggVal ~= (ctrl.xt_show_aggro ~= false) then
        ctrl.xt_show_aggro = aggVal
        core.saveLoadout(true)
    end

    local dstVal = ImGui.Checkbox('Show Distance & LoS##xtDist', ctrl.xt_show_dist ~= false)
    if dstVal ~= (ctrl.xt_show_dist ~= false) then
        ctrl.xt_show_dist = dstVal
        core.saveLoadout(true)
    end

    local petVal = ImGui.Checkbox('Show Pets & Mercenaries##xtPets', ctrl.xt_show_pets or false)
    if petVal ~= (ctrl.xt_show_pets or false) then
        ctrl.xt_show_pets = petVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Include your own pets, group pets, and mercenaries in the list (hidden by default).') end

    local pcVal = ImGui.Checkbox('Show Friendly Players##xtPcs', ctrl.xt_show_pcs or false)
    if pcVal ~= (ctrl.xt_show_pcs or false) then
        ctrl.xt_show_pcs = pcVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Include PC slots (Specific PC, Group Tank/Assist/Puller, Raid Assist) in the list (hidden by default).') end

    if core.drawWindowScaleControl then core.drawWindowScaleControl('xtarget', 'Scale', 120) end
    ImGui.SetNextItemWidth(core.px(120))
    local newAlpha = ImGui.SliderFloat('Opacity##xtAlpha', ctrl.xt_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.xt_alpha or 0.85) then
        ctrl.xt_alpha = newAlpha
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(core.px(120))
    local newH = ImGui.SliderInt('Bar Height##xtHeight', ctrl.xt_bar_height or 16, 10, 24)
    if newH ~= (ctrl.xt_bar_height or 16) then
        ctrl.xt_bar_height = newH
        core.saveLoadout(true)
    end
end

function plugin.onDrawSettings()
    renderXtSettingsContent()
end

-- Snapshot every XTarget slot the window needs. Shared by onTick and the
-- render pass; the throttle makes whichever runs first do the work.
local function refreshXTargets(force)
    if not core or not core.mq or not core.ctrl then return end
    local ctrl = core.ctrl
    if not ctrl.show_xtarget_window then
        if snap.activeCount > 0 or #snap.slots > 0 then
            snap.slots = {}
            snap.activeCount = 0
        end
        return
    end
    local now = os.clock()
    if not force and (now - lastRefreshAt) < REFRESH_INTERVAL then return end
    lastRefreshAt = now
    local mq = core.mq

    local xtarSlots = 13
    pcall(function() xtarSlots = mq.TLO.Me.XTargetSlots() or 13 end)
    local currentTargetId = 0
    pcall(function() currentTargetId = mq.TLO.Target.ID() or 0 end)
    local petIds = buildPetIdSet()

    local slots = {}
    local activeCount = 0
    for slot = 1, xtarSlots do
        local xtData = nil
        pcall(function()
            local xt = mq.TLO.Me.XTarget(slot)
            if xt and xt() and (xt.ID() or 0) > 0 then
                local xtId = xt.ID()
                local st = slotStatic[slot]
                if not st or st.id ~= xtId then
                    st = { id = xtId, name = 'Unknown', level = 0, class = '?', con = 'White', targetType = '', spawnType = '' }
                    pcall(function() st.name = xt.CleanName() or 'Unknown' end)
                    pcall(function() st.level = xt.Level() or 0 end)
                    pcall(function() st.class = (xt.Class and xt.Class.ShortName and xt.Class.ShortName()) or '?' end)
                    pcall(function() st.con = xt.ConColor() or 'White' end)
                    pcall(function() st.targetType = xt.TargetType() or '' end)
                    pcall(function() st.spawnType = xt.Type() or '' end)
                    slotStatic[slot] = st
                end
                if isHiddenSlot(st.spawnType, st.targetType, xtId, petIds) then return end

                local xtDist = 0
                pcall(function() xtDist = math.floor(xt.Distance() or 0) end)
                local xtHp = 0
                pcall(function() xtHp = xt.PctHPs() or 0 end)
                local xtAggro = 0
                pcall(function() xtAggro = xt.PctAggro() or 0 end)
                local xtLoS = true
                pcall(function() xtLoS = xt.LineOfSight() ~= false end)
                local xtTotName, xtTotId = nil, 0
                pcall(function()
                    local tot = xt.TargetOfTarget
                    if tot and tot() then
                        local tid = tot.ID() or 0
                        if tid > 0 then
                            xtTotId = tid
                            xtTotName = tot.CleanName() or ''
                        end
                    end
                end)

                xtData = {
                    slot = slot,
                    id = xtId,
                    name = st.name,
                    level = st.level,
                    class = st.class,
                    dist = xtDist,
                    hpPct = xtHp,
                    con = st.con,
                    aggroPct = xtAggro,
                    los = xtLoS,
                    tot = xtTotName,
                    totId = xtTotId,
                    targetType = st.targetType,
                    rowKey = 'xt_' .. tostring(slot) .. '_' .. tostring(xtId),
                }
            else
                slotStatic[slot] = nil
            end
        end)
        if xtData then activeCount = activeCount + 1 end
        slots[slot] = xtData or false
    end
    for slot = xtarSlots + 1, #slotStatic do slotStatic[slot] = nil end

    snap.slots = slots
    snap.slotCount = xtarSlots
    snap.activeCount = activeCount
    snap.currentTargetId = currentTargetId
end

function plugin.onTick()
    refreshXTargets(false)
end

function plugin.onDrawUI()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local mq = core.mq
    local accent = core.accent
    local GOLD, MUTED, GOOD, WARN, ERR = core.colors.GOLD, core.colors.MUTED, core.colors.GOOD, core.colors.WARN, core.colors.ERR
    if not ctrl.show_xtarget_window then return end
    core.pushTheme()

    if ctrl.xt_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.xt_alpha)
    end
    ImGui.SetNextWindowSize(core.px(260), core.px(320), ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.xt_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    core.preBeginWindow('xtarget')
    -- Pushed after preBeginWindow so this tight chrome wins over the scaled theme padding.
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, core.px(4), core.px(4))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, core.px(3), core.px(2))
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, core.px(2), core.px(1))
    local show
    ctrl.show_xtarget_window, show = ImGui.Begin('Triune Extended Target v' .. (core.VERSION or '') .. '###triuneXTargetWindow', ctrl.show_xtarget_window, winFlags)
    if not ctrl.show_xtarget_window then
        ImGui.End()
        ImGui.PopStyleVar(3)
        core.popTheme()
        return
    end

    if show then
        core.postBeginWindow('xtarget')
        local barH = core.px(ctrl.xt_bar_height or 16)

        if ImGui.BeginPopupContextWindow('##xtWinContextMenu') then
            if core.applyWindowScale then core.applyWindowScale('xtarget') end
            renderXtSettingsContent()
            ImGui.EndPopup()
        end

        -- Throttled; normally a no-op because onTick already refreshed this cycle.
        refreshXTargets(false)
        local currentTargetId = snap.currentTargetId or 0
        local activeCount = snap.activeCount or 0

        for slot = 1, (snap.slotCount or 0) do
            local xtData = snap.slots[slot] or nil

            if xtData then
                local rowKey = xtData.rowKey
                local isCurrentTarget = (currentTargetId > 0 and currentTargetId == xtData.id)

                -- Visual highlight if current target
                local stylePushed = 0
                if isCurrentTarget then
                    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                    if Col and Col.Border then
                        ImGui.PushStyleColor(Col.Border, 0.20, 0.85, 1.0, 1.0)
                        stylePushed = stylePushed + 1
                    end
                end

                -- Badges row
                local slotCol = isCurrentTarget and GOLD or MUTED
                accent(slotCol, string.format('#%d', slot))
                if ImGui.IsItemClicked() then
                    mq.cmdf('/target id %d', xtData.id)
                end

                ImGui.SameLine()
                local conRgb = core.getConColorRgb(xtData.con)
                accent(conRgb, xtData.name)
                if ImGui.IsItemClicked() then
                    mq.cmdf('/target id %d', xtData.id)
                end

                ImGui.SameLine()
                ImGui.TextDisabled(string.format('%d %s', xtData.level, xtData.class))

                if isCurrentTarget then
                    ImGui.SameLine()
                    accent(GOOD, '[TARGET]')
                end

                if ctrl.xt_show_dist ~= false then
                    ImGui.SameLine()
                    ImGui.TextDisabled(string.format("%d'", xtData.dist))
                    ImGui.SameLine()
                    if xtData.los then
                        accent(GOOD, 'LoS')
                    else
                        accent(WARN, 'No LoS')
                    end
                end

                if ctrl.xt_show_aggro ~= false and xtData.aggroPct > 0 then
                    ImGui.SameLine()
                    local aggCol = xtData.aggroPct >= 100 and ERR or WARN
                    accent(aggCol, string.format('%d%% Aggro', xtData.aggroPct))
                end

                if ctrl.xt_show_tot ~= false and xtData.tot and xtData.tot ~= '' then
                    ImGui.SameLine()
                    ImGui.TextDisabled('->')
                    ImGui.SameLine()
                    accent(GOLD, xtData.tot)
                    if ImGui.IsItemClicked() then
                        if (xtData.totId or 0) > 0 then
                            mq.cmdf('/target id %d', xtData.totId)
                        else
                            mq.cmdf('/target %s', xtData.tot)
                        end
                    end
                end

                -- Health progress bar
                local hp = xtData.hpPct or 0
                local hr, hg, hb = 0.25, 0.75, 0.35
                if hp <= 25 then
                    hr, hg, hb = 0.90, 0.20, 0.20
                elseif hp <= 50 then
                    hr, hg, hb = 0.95, 0.75, 0.20
                end
                local hpLabel = string.format('%d%%', hp)
                core.drawStatusProgressBar(hp / 100.0, -1, barH, hpLabel, hr, hg, hb, 1.0)
                if ImGui.IsItemClicked() then
                    mq.cmdf('/target id %d', xtData.id)
                end

                -- Right-click menu on target item
                if ImGui.BeginPopupContextItem('##xtItemMenu_' .. rowKey) then
                    accent(conRgb, xtData.name)
                    ImGui.TextDisabled(string.format('Level %d %s | Slot #%d', xtData.level, xtData.class, slot))
                    ImGui.Separator()
                    if ImGui.MenuItem('Target##tgt_' .. rowKey) then
                        mq.cmdf('/target id %d', xtData.id)
                    end
                    if ImGui.MenuItem('Face Target##face_' .. rowKey) then
                        mq.cmdf('/target id %d', xtData.id)
                        mq.cmd('/face fast')
                    end
                    if ImGui.MenuItem('Add to Ignore List##ign_' .. rowKey) then
                        if core.addIgnore then
                            core.addIgnore(xtData.name)
                        end
                        print(string.format('\ag[Triune]\ax Added %s to ignore list.', xtData.name))
                    end
                    ImGui.EndPopup()
                end

                -- Hover tooltip
                if ImGui.IsItemHovered() then
                    local lines = {
                        string.format('Slot #%d: %s', slot, xtData.name),
                        string.format('Level: %d  |  Class: %s  |  Con: %s', xtData.level, xtData.class, xtData.con),
                        string.format("HP: %d%%  |  Distance: %d'  |  LoS: %s", hp, xtData.dist, xtData.los and 'Yes' or 'No'),
                    }
                    if xtData.aggroPct > 0 then
                        table.insert(lines, string.format('Aggro Threat: %d%%', xtData.aggroPct))
                    end
                    if xtData.tot and xtData.tot ~= '' then
                        table.insert(lines, string.format('Targeting: %s', xtData.tot))
                    end
                    if xtData.targetType and xtData.targetType ~= '' then
                        table.insert(lines, string.format('Slot Role: %s', xtData.targetType))
                    end
                    table.insert(lines, 'Click to target | Right-click for options')
                    core.setTooltip('%s', table.concat(lines, '\n'))
                end

                if stylePushed > 0 then
                    ImGui.PopStyleColor(stylePushed)
                end
            elseif ctrl.xt_show_empty then
                accent(MUTED, string.format('#%d [Empty Slot]', slot))
            end
        end

        if activeCount == 0 and not ctrl.xt_show_empty then
            accent(MUTED, 'No hostile extended targets.')
        end
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    core.popTheme()
end

-- Exposed for tests
plugin.isHiddenSlot = isHiddenSlot

return plugin
