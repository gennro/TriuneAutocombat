---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_group.lua — Triune Popout Group Window Plugin
-- ============================================================================
-- Modern, compact party vitals: auto-scaling HP / Mana / Endurance bars,
-- leader + role badges, member pet tracking, click-to-target, Invite / Disband
-- toolbar, and a right-click context menu for options.
--
-- Render-only plugin: everything happens in onDrawUI on the ImGui thread, so
-- there is no fiber and nothing for the main combat loop to do. Visibility is
-- driven by ctrl.show_group_window so the header buttons, Mini HUD, window
-- manager, and /ac group all keep working unchanged.
-- ============================================================================

local plugin = {
    id                 = 'hud_group',
    name               = 'Group Window HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout group window with vitals bars, role badges, member pets, invite/disband, and click-to-target.',
    defaultEnabled     = true,
    tickInterval       = 1.0,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Group', tooltip = 'Toggles the popout Group Window.', flag = 'show_group_window', key = 'group', lockFlag = 'gw_lock', desc = 'Popout Party members HP/Mana/End bars', headerButton = true, order = 70 },
}

local core = nil

function plugin.onInit(coreApi)
    core = coreApi
    local ctrl = core and core.ctrl
    if ctrl then
        if ctrl.show_group_window == nil then ctrl.show_group_window = false end
        if ctrl.gw_lock == nil then ctrl.gw_lock = false end
        if ctrl.gw_alpha == nil then ctrl.gw_alpha = 0.85 end
        if ctrl.gw_bar_height == nil then ctrl.gw_bar_height = 14 end
        if ctrl.gw_include_self == nil then ctrl.gw_include_self = true end
        if ctrl.gw_show_mana == nil then ctrl.gw_show_mana = true end
        if ctrl.gw_show_endurance == nil then ctrl.gw_show_endurance = false end
        if ctrl.gw_show_pets == nil then ctrl.gw_show_pets = true end
        if ctrl.gw_show_roles == nil then ctrl.gw_show_roles = true end
    end
end

function plugin.onDestroy()
end

-- Settings popup renderer (right-click anywhere in window, and Plugins tab)
local function renderGwSettingsContent()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local accent = core.accent
    local GOLD = core.colors.GOLD

    accent(GOLD, 'Group Window Settings')
    ImGui.Separator()
    local isWinOpen = (ctrl.show_group_window == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##gwToggleWin', 250, 24) then
        ctrl.show_group_window = not isWinOpen
        core.saveLoadout(true)
    end
    local lockVal = ImGui.Checkbox('Lock Window Position & Size##gwLock', ctrl.gw_lock or false)
    if lockVal ~= (ctrl.gw_lock or false) then
        ctrl.gw_lock = lockVal
        core.saveLoadout(true)
    end
    local selfVal = ImGui.Checkbox('Include Self in Group##gwSelf', ctrl.gw_include_self ~= false)
    if selfVal ~= (ctrl.gw_include_self ~= false) then
        ctrl.gw_include_self = selfVal
        core.saveLoadout(true)
    end
    local manaVal = ImGui.Checkbox('Show Mana Bars##gwMana', ctrl.gw_show_mana ~= false)
    if manaVal ~= (ctrl.gw_show_mana ~= false) then
        ctrl.gw_show_mana = manaVal
        core.saveLoadout(true)
    end
    local endVal = ImGui.Checkbox('Show Endurance Bars##gwEnd', ctrl.gw_show_endurance or false)
    if endVal ~= (ctrl.gw_show_endurance or false) then
        ctrl.gw_show_endurance = endVal
        core.saveLoadout(true)
    end
    local boxVal = ImGui.Checkbox('Show Box Network Characters##gwBoxes', ctrl.gw_show_boxes ~= false)
    if boxVal ~= (ctrl.gw_show_boxes ~= false) then
        ctrl.gw_show_boxes = boxVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Also list your other boxed characters (Box Network) that are not in this group, with live vitals from their heartbeat.') end
    local petVal = ImGui.Checkbox('Show Pet Bars##gwPets', ctrl.gw_show_pets ~= false)
    if petVal ~= (ctrl.gw_show_pets ~= false) then
        ctrl.gw_show_pets = petVal
        core.saveLoadout(true)
    end
    local roleVal = ImGui.Checkbox('Show Role Badges##gwRoles', ctrl.gw_show_roles ~= false)
    if roleVal ~= (ctrl.gw_show_roles ~= false) then
        ctrl.gw_show_roles = roleVal
        core.saveLoadout(true)
    end
    ImGui.SetNextItemWidth(120)
    local newAlpha = ImGui.SliderFloat('Opacity##gwAlpha', ctrl.gw_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.gw_alpha or 0.85) then
        ctrl.gw_alpha = newAlpha
        core.saveLoadout(true)
    end
    ImGui.SetNextItemWidth(120)
    local newH = ImGui.SliderInt('Bar Height##gwHeight', ctrl.gw_bar_height or 14, 10, 24)
    if newH ~= (ctrl.gw_bar_height or 14) then
        ctrl.gw_bar_height = newH
        core.saveLoadout(true)
    end
end

function plugin.onDrawSettings()
    renderGwSettingsContent()
end

function plugin.onDrawUI()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local mq = core.mq
    local accent = core.accent
    local GOLD, ARC, MUTED, WARN, ERR = core.colors.GOLD, core.colors.ARC, core.colors.MUTED, core.colors.WARN, core.colors.ERR
    if not ctrl.show_group_window then return end
    core.pushTheme()

    if ctrl.gw_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.gw_alpha)
    end
    ImGui.SetNextWindowSize(280, 320, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.gw_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 2, 1)

    core.preBeginWindow('group')
    local show
    ctrl.show_group_window, show = ImGui.Begin('Triune Group v' .. (core.VERSION or '') .. '###triuneGroupWindow', ctrl.show_group_window, winFlags)
    if not ctrl.show_group_window then
        ImGui.End()
        ImGui.PopStyleVar(3)
        core.popTheme()
        return
    end

    if show then
        core.postBeginWindow('group')
        local barH = ctrl.gw_bar_height or 14

        -- Right-click anywhere in window for options
        if ImGui.BeginPopupContextWindow('##gwContextMenu') then
            renderGwSettingsContent()
            ImGui.EndPopup()
        end

        -- Retrieve Group Roles and Leadership
        local grpSize = 0
        local leaderName, mtName, maName, pullerName = '', '', '', ''
        pcall(function()
            grpSize = mq.TLO.Group.GroupSize() or 0
            if mq.TLO.Group.Leader and mq.TLO.Group.Leader() then
                leaderName = mq.TLO.Group.Leader.CleanName() or ''
            end
            if mq.TLO.Group.MainTank and mq.TLO.Group.MainTank() then
                mtName = mq.TLO.Group.MainTank.CleanName() or ''
            end
            if mq.TLO.Group.MainAssist and mq.TLO.Group.MainAssist() then
                maName = mq.TLO.Group.MainAssist.CleanName() or ''
            end
            if mq.TLO.Group.Puller and mq.TLO.Group.Puller() then
                pullerName = mq.TLO.Group.Puller.CleanName() or ''
            end
        end)

        local _ = (grpSize and grpSize > 0) -- isGrouped (reserved for future use)
        local members = {}

        -- Include Self (Member 0)
        if ctrl.gw_include_self ~= false then
            local myName, myId, myLvl, myCls = 'Myself', 0, 1, '?'
            local myHpPct, myCurHp, myMaxHp = 100, 0, 0
            local myManaPct, myCurMana, myMaxMana = 0, 0, 0
            local myEndPct, myCurEnd, myMaxEnd = 0, 0, 0
            local myPetId, myPetName, myPetHpPct = 0, 'Pet', 0
            pcall(function()
                myName = mq.TLO.Me.CleanName() or 'Myself'
                myId = mq.TLO.Me.ID() or 0
                myLvl = mq.TLO.Me.Level() or 1
                myCls = mq.TLO.Me.Class.ShortName() or '?'
                myHpPct = mq.TLO.Me.PctHPs() or 0
                myCurHp = mq.TLO.Me.CurrentHPs() or 0
                myMaxHp = mq.TLO.Me.MaxHPs() or 0
                myManaPct = mq.TLO.Me.PctMana() or 0
                myCurMana = mq.TLO.Me.CurrentMana() or 0
                myMaxMana = mq.TLO.Me.MaxMana() or 0
                myEndPct = mq.TLO.Me.PctEndurance() or 0
                myCurEnd = mq.TLO.Me.CurrentEndurance() or 0
                myMaxEnd = mq.TLO.Me.MaxEndurance() or 0
                if mq.TLO.Me.Pet and mq.TLO.Me.Pet() and (mq.TLO.Me.Pet.ID() or 0) > 0 then
                    myPetId = mq.TLO.Me.Pet.ID()
                    myPetName = mq.TLO.Me.Pet.CleanName() or 'Pet'
                    myPetHpPct = mq.TLO.Me.Pet.PctHPs() or 0
                end
            end)

            table.insert(members, {
                isSelf = true,
                index = 0,
                id = myId,
                name = myName,
                level = myLvl,
                cls = myCls,
                hpPct = myHpPct,
                curHp = myCurHp,
                maxHp = myMaxHp,
                manaPct = myManaPct,
                curMana = myCurMana,
                maxMana = myMaxMana,
                endPct = myEndPct,
                curEnd = myCurEnd,
                maxEnd = myMaxEnd,
                distance = 0,
                los = true,
                isLeader = (leaderName ~= '' and leaderName == myName),
                isMT = (mtName ~= '' and mtName == myName),
                isMA = (maName ~= '' and maName == myName),
                isPuller = (pullerName ~= '' and pullerName == myName),
                isMerc = false,
                offline = false,
                otherZone = false,
                petId = myPetId,
                petName = myPetName,
                petHpPct = myPetHpPct,
            })
        end

        -- Query Other Group Members (1 .. Members)
        local otherCount = 0
        pcall(function() otherCount = mq.TLO.Group.Members() or 0 end)
        for i = 1, otherCount do
            pcall(function()
                local m = mq.TLO.Group.Member(i)
                if m and m() then
                    local mName = m.CleanName() or ('Member ' .. i)
                    local mId = m.ID() or 0
                    local mLvl = m.Level() or 0
                    local mCls = (m.Class and m.Class.ShortName and m.Class.ShortName()) or '?'
                    local mHpPct = m.PctHPs() or 0
                    local mCurHp = m.CurrentHPs() or 0
                    local mMaxHp = m.MaxHPs() or 0
                    local mManaPct = m.PctMana() or 0
                    local mCurMana = m.CurrentMana() or 0
                    local mMaxMana = m.MaxMana() or 0
                    local mEndPct = m.PctEndurance() or 0
                    local mCurEnd = m.CurrentEndurance() or 0
                    local mMaxEnd = m.MaxEndurance() or 0
                    local mDist = m.Distance() or 0
                    local mLoS = m.LineOfSight() or false
                    local mOtherZone = m.OtherZone() or false
                    local mOffline = m.Offline() or false
                    local mMerc = m.Mercenary() or false
                    local mLeader = (leaderName ~= '' and leaderName == mName) or (m.Leader and m.Leader()) or false
                    local mMT = (mtName ~= '' and mtName == mName)
                    local mMA = (maName ~= '' and maName == mName)
                    local mPuller = (pullerName ~= '' and pullerName == mName)

                    local mPetId, mPetName, mPetHpPct = 0, 'Pet', 0
                    if m.Pet and m.Pet() and (m.Pet.ID() or 0) > 0 then
                        mPetId = m.Pet.ID()
                        mPetName = m.Pet.CleanName() or 'Pet'
                        mPetHpPct = m.Pet.PctHPs() or 0
                    end

                    table.insert(members, {
                        isSelf = false,
                        index = i,
                        id = mId,
                        name = mName,
                        level = mLvl,
                        cls = mCls,
                        hpPct = mHpPct,
                        curHp = mCurHp,
                        maxHp = mMaxHp,
                        manaPct = mManaPct,
                        curMana = mCurMana,
                        maxMana = mMaxMana,
                        endPct = mEndPct,
                        curEnd = mCurEnd,
                        maxEnd = mMaxEnd,
                        distance = mDist,
                        los = mLoS,
                        isLeader = mLeader,
                        isMT = mMT,
                        isMA = mMA,
                        isPuller = mPuller,
                        isMerc = mMerc,
                        offline = mOffline,
                        otherZone = mOtherZone,
                        petId = mPetId,
                        petName = mPetName,
                        petHpPct = mPetHpPct,
                    })
                end
            end)
        end

        -- Box Network: this computer's other Triune characters that are not in
        -- the group (vitals from their heartbeat; spawn looked up locally so the
        -- row can be targeted and shows distance).
        if ctrl.gw_show_boxes ~= false and core.boxnet and type(core.boxnet.peers) == 'function' then
            local okB, peers = pcall(core.boxnet.peers)
            if okB and type(peers) == 'table' then
                local seenNames = {}
                for _, m in ipairs(members) do seenNames[tostring(m.name):lower()] = true end
                local myZone = ''
                pcall(function() myZone = tostring(mq.TLO.Zone.ShortName() or ''):lower() end)
                for _, p in ipairs(peers) do
                    local hb = p.hb
                    if hb and p.name and not seenNames[tostring(p.name):lower()] then
                        local inZone = tostring(hb.zone or ''):lower() == myZone
                        local bId, bDist, bLoS = 0, 0, false
                        if inZone then
                            pcall(function()
                                local sp = mq.TLO.Spawn('pc =' .. p.name)
                                if sp and sp() and (sp.ID() or 0) > 0 then
                                    bId = sp.ID() or 0
                                    bDist = sp.Distance() or 0
                                    bLoS = sp.LineOfSight() or false
                                end
                            end)
                        end
                        table.insert(members, {
                            isSelf = false,
                            isBox = true,
                            index = 100 + #members,
                            id = bId,
                            name = p.name,
                            level = tonumber(hb.level) or 0,
                            cls = type(hb.classes) == 'table' and table.concat(hb.classes, '/') or '?',
                            hpPct = tonumber(hb.hp) or 0,
                            curHp = 0, maxHp = 0,
                            manaPct = tonumber(hb.mana) or 0,
                            curMana = 0, maxMana = 0,
                            endPct = tonumber(hb.endur) or 0,
                            curEnd = 0, maxEnd = 0,
                            distance = bDist,
                            los = bLoS,
                            isLeader = false,
                            isMT = false,
                            isMA = (maName ~= '' and maName == p.name),
                            isPuller = false,
                            isMerc = false,
                            offline = false,
                            otherZone = not inZone,
                            petId = (type(hb.pet) == 'table' and tonumber(hb.pet.id)) or 0,
                            petName = (type(hb.pet) == 'table' and hb.pet.name) or 'Pet',
                            petHpPct = (type(hb.pet) == 'table' and tonumber(hb.pet.hp)) or 0,
                            boxMode = hb.mode, boxRunning = hb.running == true,
                        })
                    end
                end
            end
        end

        -- Query current target in EverQuest
        local curTargId = 0
        local curTargName = ''
        local curTargType = ''
        pcall(function()
            curTargId = mq.TLO.Target.ID() or 0
            curTargName = mq.TLO.Target.CleanName() or ''
            curTargType = mq.TLO.Target.Type() or ''
        end)

        -- Determine currently selected group member
        local selectedMember = nil
        for _, m in ipairs(members) do
            if curTargId > 0 and m.id == curTargId then
                selectedMember = m
                break
            elseif curTargName ~= '' and m.name == curTargName then
                selectedMember = m
                break
            end
        end
        if not selectedMember and ctrl.gw_selected_member_id then
            for _, m in ipairs(members) do
                if (m.id and m.id == ctrl.gw_selected_member_id) or (m.name and m.name == ctrl.gw_selected_member_name) then
                    selectedMember = m
                    break
                end
            end
        end

        -- Invite & Disband Toolbar
        local availW = ImGui.GetContentRegionAvail()
        local halfW = math.max(60, math.floor((availW - 4) / 2))
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)

        -- 1. Invite Button: invites current target to the group
        local invPushed = 0
        if Col then
            if pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.38, 0.22, 0.85) then invPushed = invPushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.18, 0.52, 0.30, 0.95) then invPushed = invPushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.Text, 0.75, 0.98, 0.75, 1.0) then invPushed = invPushed + 1 end
        end
        if ImGui.Button('Invite##gwInvite', halfW, 20) then
            if curTargId > 0 then
                mq.cmdf('/target id %d', curTargId)
            end
            if curTargName ~= '' and (curTargType == 'PC' or curTargType == 'Mercenary') then
                mq.cmdf('/invite %s', curTargName)
            else
                mq.cmd('/invite')
            end
        end
        if invPushed > 0 then pcall(ImGui.PopStyleColor, invPushed) end
        if ImGui.IsItemHovered() then
            if curTargName ~= '' then
                core.setTooltip('%s', string.format('Invite current target %s (ID %d) to group (/invite)', curTargName, curTargId))
            else
                core.setTooltip('Invite currently targeted player to group (/invite)')
            end
        end

        ImGui.SameLine()

        -- 2. Disband Button: removes selected/targeted group member, or self
        local disPushed = 0
        if Col then
            if pcall(ImGui.PushStyleColor, Col.Button, 0.42, 0.16, 0.16, 0.85) then disPushed = disPushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.58, 0.22, 0.22, 0.95) then disPushed = disPushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.Text, 1.0, 0.75, 0.75, 1.0) then disPushed = disPushed + 1 end
        end
        local disLabel = selectedMember and (selectedMember.isSelf and 'Disband (Self)' or string.format('Disband: %s', selectedMember.name)) or 'Disband'
        if ImGui.Button(disLabel .. '##gwDisband', halfW, 20) then
            if selectedMember then
                if selectedMember.isSelf then
                    mq.cmd('/disband')
                else
                    if selectedMember.id and selectedMember.id > 0 then
                        mq.cmdf('/target id %d', selectedMember.id)
                    elseif selectedMember.name then
                        mq.cmdf('/target %s', selectedMember.name)
                    end
                    mq.cmd('/disband')
                    if selectedMember.name and selectedMember.name ~= '' then
                        mq.cmdf('/kickgroup %s', selectedMember.name)
                    end
                end
            else
                mq.cmd('/disband')
            end
        end
        if disPushed > 0 then pcall(ImGui.PopStyleColor, disPushed) end
        if ImGui.IsItemHovered() then
            if selectedMember then
                if selectedMember.isSelf then
                    core.setTooltip('Leave group (/disband)')
                else
                    core.setTooltip('%s', string.format('Disband / remove %s from group (/disband, /kickgroup)', selectedMember.name))
                end
            else
                core.setTooltip('Disband selected / targeted group member (/disband)')
            end
        end

        ImGui.Separator()

        if #members == 0 then
            accent(MUTED, 'Not currently in a group.')
        else
            for idx, mem in ipairs(members) do
                if idx > 1 then
                    ImGui.Separator()
                end

                -- Con Color calculation
                local conR, conG, conB = 1.0, 1.0, 1.0  -- luacheck: ignore 311
                if mem.offline then
                    conR, conG, conB = 0.5, 0.5, 0.5
                elseif mem.otherZone then
                    conR, conG, conB = 0.85, 0.65, 0.25
                else
                    local myLevel = 1
                    pcall(function() myLevel = mq.TLO.Me.Level() or 1 end)
                    local delta = (mem.level or 1) - myLevel
                    if delta >= 3 then
                        conR, conG, conB = 1.0, 0.25, 0.25
                    elseif delta >= 1 then
                        conR, conG, conB = 1.0, 0.85, 0.25
                    elseif delta >= -3 then
                        conR, conG, conB = 1.0, 1.0, 1.0
                    elseif delta >= -8 then
                        conR, conG, conB = 0.25, 0.60, 1.0
                    else
                        conR, conG, conB = 0.35, 0.85, 0.35
                    end
                end

                -- Member header button: click targets and selects member
                local isSelected = (selectedMember and selectedMember.name == mem.name)
                local tag = string.format('[Lvl %d] %s', mem.level or 0, mem.name)
                local pushedCols = 0
                if Col then
                    if isSelected then
                        if pcall(ImGui.PushStyleColor, Col.Button, 0.18, 0.35, 0.52, 0.90) then pushedCols = pushedCols + 1 end
                    else
                        if pcall(ImGui.PushStyleColor, Col.Button, 0.15, 0.15, 0.18, 0.50) then pushedCols = pushedCols + 1 end
                    end
                    if pcall(ImGui.PushStyleColor, Col.Text, conR, conG, conB, 1.0) then pushedCols = pushedCols + 1 end
                end
                if ImGui.SmallButton(tag .. '##gwTgt' .. idx) then
                    ctrl.gw_selected_member_id = mem.id
                    ctrl.gw_selected_member_name = mem.name
                    if mem.id and mem.id > 0 then
                        mq.cmdf('/target id %d', mem.id)
                    elseif mem.name then
                        mq.cmdf('/target %s', mem.name)
                    end
                end
                if pushedCols > 0 then pcall(ImGui.PopStyleColor, pushedCols) end
                if ImGui.IsItemHovered() then
                    core.setTooltip('%s', string.format('Click to target %s\nLevel: %d\nClass: %s\nID: %d%s%s',
                        mem.name, mem.level or 0, mem.cls or '?', mem.id or 0,
                        mem.offline and '\nStatus: OFFLINE' or '',
                        mem.otherZone and '\nStatus: OTHER ZONE' or ''))
                end

                if isSelected then
                    ImGui.SameLine()
                    accent(ARC, '[SEL]')
                    if ImGui.IsItemHovered() then core.setTooltip('Selected member') end
                end

                -- Badges (Leader, Roles, Merc)
                if ctrl.gw_show_roles ~= false then
                    if mem.isLeader then
                        ImGui.SameLine()
                        accent(GOLD, '[L]')
                        if ImGui.IsItemHovered() then core.setTooltip('Group Leader') end
                    end
                    if mem.isMT then
                        ImGui.SameLine()
                        accent(ARC, '[MT]')
                        if ImGui.IsItemHovered() then core.setTooltip('Main Tank') end
                    end
                    if mem.isMA then
                        ImGui.SameLine()
                        accent(ARC, '[MA]')
                        if ImGui.IsItemHovered() then core.setTooltip('Main Assist') end
                    end
                    if mem.isPuller then
                        ImGui.SameLine()
                        accent(ARC, '[Puller]')
                        if ImGui.IsItemHovered() then core.setTooltip('Group Puller') end
                    end
                    if mem.isMerc then
                        ImGui.SameLine()
                        accent(MUTED, '[Merc]')
                        if ImGui.IsItemHovered() then core.setTooltip('Mercenary') end
                    end
                end
                if mem.isBox then
                    ImGui.SameLine()
                    accent(GOLD, '[Box]')
                    if ImGui.IsItemHovered() then
                        core.setTooltip('%s', string.format('One of your boxes (Box Network, not in this group)\nTrio: %s\nMode: %s (%s)',
                            mem.cls or '?', tostring(mem.boxMode or '?'), mem.boxRunning and 'running' or 'paused'))
                    end
                end

                -- Distance (if not self and in zone)
                if not mem.isSelf and not mem.offline and not mem.otherZone then
                    ImGui.SameLine()
                    accent(ARC, string.format('%.0fft', mem.distance or 0))
                elseif mem.offline then
                    ImGui.SameLine()
                    accent(ERR, '[OFFLINE]')
                elseif mem.otherZone then
                    ImGui.SameLine()
                    accent(WARN, '[ZONE]')
                end

                -- Member Health Bar
                local hr, hg, hb = 0.25, 0.80, 0.35
                if mem.offline then
                    hr, hg, hb = 0.40, 0.40, 0.40
                elseif mem.otherZone then
                    hr, hg, hb = 0.70, 0.55, 0.25
                elseif (mem.hpPct or 0) <= 25 then
                    hr, hg, hb = 0.90, 0.20, 0.20
                elseif (mem.hpPct or 0) <= 50 then
                    hr, hg, hb = 0.95, 0.75, 0.20
                end

                local hpText
                if mem.offline then
                    hpText = string.format('%s: OFFLINE', mem.name)
                elseif mem.otherZone then
                    hpText = string.format('%s: OTHER ZONE', mem.name)
                else
                    hpText = string.format('HP: %d%%', mem.hpPct or 0)
                end
                local hpFrac = (mem.offline or mem.otherZone) and 0.0 or ((mem.hpPct or 0) / 100.0)
                core.drawStatusProgressBar(hpFrac, -1, barH, hpText, hr, hg, hb, 1.0)
                if ImGui.IsItemClicked() then
                    ctrl.gw_selected_member_id = mem.id
                    ctrl.gw_selected_member_name = mem.name
                    if mem.id and mem.id > 0 then
                        mq.cmdf('/target id %d', mem.id)
                    elseif mem.name then
                        mq.cmdf('/target %s', mem.name)
                    end
                end
                if ImGui.IsItemHovered() then
                    core.setTooltip('%s', string.format('%s\nHealth: %d%%\nCurrent: %s / Max: %s\nClick bar to target',
                        mem.name, mem.hpPct or 0,
                        (mem.curHp and mem.curHp > 0) and tostring(mem.curHp) or '?',
                        (mem.maxHp and mem.maxHp > 0) and tostring(mem.maxHp) or '?'))
                end

                -- Mana Bar (if enabled & caster/hybrid)
                local isCaster = (mem.maxMana and mem.maxMana > 0) or (mem.manaPct and mem.manaPct > 0)
                if ctrl.gw_show_mana ~= false and isCaster and not mem.offline and not mem.otherZone then
                    local manaText = string.format('Mana: %d%%', mem.manaPct or 0)
                    core.drawStatusProgressBar((mem.manaPct or 0) / 100.0, -1, math.max(8, barH - 3), manaText, 0.25, 0.60, 0.95, 1.0)
                    if ImGui.IsItemClicked() then
                        if mem.id and mem.id > 0 then mq.cmdf('/target id %d', mem.id) end
                    end
                end

                -- Endurance Bar (if enabled)
                if ctrl.gw_show_endurance == true and (mem.maxEnd or 0) > 0 and not mem.offline and not mem.otherZone then
                    local endText = string.format('End: %d%%', mem.endPct or 0)
                    core.drawStatusProgressBar((mem.endPct or 0) / 100.0, -1, math.max(8, barH - 3), endText, 0.95, 0.60, 0.25, 1.0)
                    if ImGui.IsItemClicked() then
                        if mem.id and mem.id > 0 then mq.cmdf('/target id %d', mem.id) end
                    end
                end

                -- Pet Bar (if enabled & has pet)
                if ctrl.gw_show_pets ~= false and mem.petId and mem.petId > 0 and not mem.offline and not mem.otherZone then
                    local petR, petG, petB = 0.25, 0.80, 0.35
                    local pHp = mem.petHpPct or 0
                    if pHp <= 25 then
                        petR, petG, petB = 0.90, 0.20, 0.20
                    elseif pHp <= 50 then
                        petR, petG, petB = 0.95, 0.75, 0.20
                    end
                    local petText = string.format('Pet (%s): %d%%', mem.petName or 'Pet', pHp)
                    core.drawStatusProgressBar(pHp / 100.0, -1, math.max(8, barH - 3), petText, petR, petG, petB, 1.0)
                    if ImGui.IsItemClicked() then
                        mq.cmdf('/target id %d', mem.petId)
                    end
                    if ImGui.IsItemHovered() then
                        core.setTooltip('%s', string.format('Pet: %s\nOwner: %s\nHP: %d%%\nClick to target pet',
                            mem.petName or 'Pet', mem.name, pHp))
                    end
                end
            end
        end
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    core.popTheme()
end

return plugin
