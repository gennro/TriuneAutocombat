---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_xtarget.lua — Triune Popout Extended Target Window Plugin
-- ============================================================================
-- Compact, auto-scaling replacement for EverQuest's Extended Target window:
-- con-colored names, HP bars, aggro %, distance / LoS, target-of-target, and a
-- per-row right-click menu (Target, Face, Add to Ignore List).
--
-- Render-only plugin driven by ctrl.show_xtarget_window; the header buttons,
-- Mini HUD, window manager, and /ac xtar keep working unchanged.
-- ============================================================================

local plugin = {
    id                 = 'hud_xtarget',
    name               = 'Extended Target HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout Extended Target window with HP bars, aggro %, distance/LoS, ToT, and right-click actions.',
    defaultEnabled     = true,
    tickInterval       = 1.0,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'XTarget', tooltip = 'Toggles the popout Extended Target (XTarget) window.', flag = 'show_xtarget_window', key = 'xtarget', lockFlag = 'xt_lock', desc = 'Popout Extended Target (XTarget) vitals', headerButton = true, order = 90 },
}

local core = nil

function plugin.onInit(coreApi)
    core = coreApi
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
-- the extended target list unless the user opts in.
local function isHiddenSlot(spawnType, targetType, spawnId)
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
    if not isPet and spawnId and spawnId > 0 and core.getMultiPetList then
        local okList, petSlots, extraPets = pcall(core.getMultiPetList)
        if okList then
            for _, ps in ipairs(petSlots or {}) do
                if ps.petId == spawnId then isPet = true break end
            end
            if not isPet then
                for _, pid in ipairs(extraPets or {}) do
                    if pid == spawnId then isPet = true break end
                end
            end
        end
    end
    local ctrl = core.ctrl
    if isPet and not ctrl.xt_show_pets then return true end
    if isPc and not ctrl.xt_show_pcs then return true end
    return false
end

function plugin.onDestroy()
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
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##xtToggleWin', 250, 24) then
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

    ImGui.SetNextItemWidth(120)
    local newAlpha = ImGui.SliderFloat('Opacity##xtAlpha', ctrl.xt_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.xt_alpha or 0.85) then
        ctrl.xt_alpha = newAlpha
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(120)
    local newH = ImGui.SliderInt('Bar Height##xtHeight', ctrl.xt_bar_height or 16, 10, 24)
    if newH ~= (ctrl.xt_bar_height or 16) then
        ctrl.xt_bar_height = newH
        core.saveLoadout(true)
    end
end

function plugin.onDrawSettings()
    renderXtSettingsContent()
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
    ImGui.SetNextWindowSize(260, 320, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.xt_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 2, 1)

    core.preBeginWindow('xtarget')
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
        local barH = ctrl.xt_bar_height or 16

        if ImGui.BeginPopupContextWindow('##xtWinContextMenu') then
            renderXtSettingsContent()
            ImGui.EndPopup()
        end

        -- Query XTarget Slots
        local xtarSlots = 13
        pcall(function() xtarSlots = mq.TLO.Me.XTargetSlots() or 13 end)

        local currentTargetId = 0
        pcall(function() currentTargetId = mq.TLO.Target.ID() or 0 end)

        local activeCount = 0

        for slot = 1, xtarSlots do
            local xtData = nil
            pcall(function()
                local xt = mq.TLO.Me.XTarget(slot)
                if xt and xt() and (xt.ID() or 0) > 0 then
                    local xtId = xt.ID()
                    local xtName = xt.CleanName() or 'Unknown'
                    local xtLvl = xt.Level() or 0
                    local xtCls = (xt.Class and xt.Class.ShortName and xt.Class.ShortName()) or '?'
                    local xtDist = math.floor(xt.Distance() or 0)
                    local xtHp = xt.PctHPs() or 0
                    local xtCon = xt.ConColor() or 'White'
                    local xtAggro = 0
                    pcall(function() xtAggro = xt.PctAggro() or 0 end)
                    local xtLoS = true
                    pcall(function() xtLoS = xt.LineOfSight() ~= false end)
                    local xtTotName = nil
                    pcall(function()
                        local tot = xt.TargetOfTarget
                        if tot and tot() and (tot.ID() or 0) > 0 then
                            xtTotName = tot.CleanName() or ''
                        end
                    end)
                    local ttype = ''
                    pcall(function() ttype = xt.TargetType() or '' end)
                    local sType = ''
                    pcall(function() sType = xt.Type() or '' end)
                    if isHiddenSlot(sType, ttype, xtId) then return end

                    xtData = {
                        slot = slot,
                        id = xtId,
                        name = xtName,
                        level = xtLvl,
                        class = xtCls,
                        dist = xtDist,
                        hpPct = xtHp,
                        con = xtCon,
                        aggroPct = xtAggro,
                        los = xtLoS,
                        tot = xtTotName,
                        targetType = ttype,
                    }
                end
            end)

            if xtData then
                activeCount = activeCount + 1
                local rowKey = 'xt_' .. tostring(slot) .. '_' .. tostring(xtData.id)
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
                        mq.cmdf('/target %s', xtData.tot)
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
