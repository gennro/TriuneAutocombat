---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/auto_accept.lua — Triune Auto-Accept Plugin
-- ============================================================================
-- Automatically handles incoming group invites, trade requests, and expedition /
-- dynamic-zone invites from authorized players. Authorization is decided by the
-- rules stored on ctrl (accept from anyone / group members / guild members) plus
-- the persisted whitelist in ctrl.auto_accept_names.
--
-- This plugin is the sole owner of the feature: the whitelist helpers, the chat
-- event handlers, the window poll, and the Auto-Accept popout window
-- (ctrl.show_auto_accept; header button, /ac autoaccept, Window Layout manager)
-- all live here. The core only keeps the ctrl defaults so saved loadouts round-trip.
--
-- Chat events fire from mq.doevents() on the main loop regardless of combat, so
-- group / DZ invites are still caught mid-fight; only the window poll sleeps.
-- ============================================================================

local plugin = {
    id                 = 'auto_accept',
    name               = 'Auto-Accept Invites',
    version            = '1.1.0',
    author             = 'Triune',
    description        = 'Automatically accepts group, trade, and expedition/DZ invites from whitelisted, group, or guild players.',
    defaultEnabled     = true,
    tickInterval       = 0.3,
    runOutOfCombatOnly = true,
    hasThread          = true,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Auto-Accept', tooltip = 'Toggles the Auto-Accept invites / trades / DZ window (auto_accept plugin).', flag = 'show_auto_accept', desc = 'Auto-accept rules & player whitelist', headerButton = true, order = 115 },
}

local core = nil
local registeredEvents = {}

-- Debounce timestamps so a lingering dialog does not spam accept commands.
local lastGroupAcceptAt = nil
local lastTradeAcceptAt = nil
local lastDzAcceptAt = nil

-- Settings-page scratch state
local inputName = ''
local selectedPlayer = nil

local function ctrl()
    return core and core.ctrl or nil
end

local function saveLoadout()
    if core and core.saveLoadout then core.saveLoadout(true) end
end

-- ----------------------------------------------------------------------------
-- Whitelist helpers
-- ----------------------------------------------------------------------------
local function getPlayerInfo(entry)
    if type(entry) == 'table' then
        return tostring(entry.name or ''), tonumber(entry.id) or 0
    end
    return tostring(entry or ''), 0
end

local function ensureList()
    local c = ctrl()
    if not c then return nil end
    if type(c.auto_accept_names) ~= 'table' then c.auto_accept_names = {} end
    return c.auto_accept_names
end

local function isListed(nameOrId)
    if not nameOrId or nameOrId == '' or nameOrId == 0 then return false end
    local list = ensureList()
    if not list then return false end
    local targetNum = tonumber(nameOrId)
    local targetStr = tostring(nameOrId):lower():gsub('^%s+', ''):gsub('%s+$', '')
    for _, entry in ipairs(list) do
        local eName, eId = getPlayerInfo(entry)
        if targetNum and targetNum > 0 and eId > 0 and eId == targetNum then return true end
        if targetStr ~= '' and eName ~= '' and eName:lower() == targetStr then return true end
    end
    return false
end

local function resolveSpawn(name, id)
    local mq = core and core.mq
    if not (mq and mq.TLO and mq.TLO.Spawn) then return nil end
    local sp = nil
    pcall(function()
        if id and id > 0 then
            sp = mq.TLO.Spawn(string.format('id %d', id))
        end
        if not (sp and sp() and (sp.ID() or 0) > 0) and name and name ~= '' then
            sp = mq.TLO.Spawn(string.format('pc =%s', name))
            if not (sp and sp() and (sp.ID() or 0) > 0) then
                sp = mq.TLO.Spawn(string.format('pc %s', name))
            end
        end
    end)
    if sp and sp() and (sp.ID() or 0) > 0 then return sp end
    return nil
end

local function addName(nameOrId, optionalId)
    if not nameOrId then return end
    local s = tostring(nameOrId):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return end
    local list = ensureList()
    if not list then return end

    local name = s
    local id = tonumber(optionalId) or 0
    local num = tonumber(s)
    if num and num > 0 and id == 0 then
        id = num
        name = ''
    end

    -- Fill in whichever half (name / id) we were not given from the zone.
    local sp = resolveSpawn(name, id)
    if sp then
        pcall(function()
            if sp.Type() == 'PC' then
                if name == '' then name = sp.CleanName() or '' end
                if id == 0 then id = sp.ID() or 0 end
            end
        end)
    end

    if name == '' and id > 0 then name = string.format('Player_%d', id) end
    if name == '' and id == 0 then return end

    local found = false
    for _, entry in ipairs(list) do
        local eName, eId = getPlayerInfo(entry)
        if (id > 0 and eId > 0 and eId == id) or (name ~= '' and eName ~= '' and eName:lower() == name:lower()) then
            if type(entry) == 'table' then
                if id > 0 then entry.id = id end
                if name ~= '' and (entry.name == '' or entry.name:find('^Player_')) then entry.name = name end
            end
            found = true
            break
        end
    end

    if not found then
        table.insert(list, { name = name, id = id })
        table.sort(list, function(a, b)
            local aName = getPlayerInfo(a)
            local bName = getPlayerInfo(b)
            return aName:lower() < bName:lower()
        end)
    end

    saveLoadout()
    if id > 0 then
        print(string.format('\ag[Triune Auto-Accept]\ax Added to auto-accept list: \ay%s\ax (ID: \at%d\ax)', name, id))
    else
        print(string.format('\ag[Triune Auto-Accept]\ax Added to auto-accept list: \ay%s\ax', name))
    end
end

local function removeName(nameOrIdOrEntry)
    local list = ensureList()
    if not nameOrIdOrEntry or not list then return false end
    local targetNum, targetStr
    if type(nameOrIdOrEntry) == 'table' then
        targetNum = tonumber(nameOrIdOrEntry.id)
        targetStr = nameOrIdOrEntry.name and tostring(nameOrIdOrEntry.name):lower():gsub('^%s+', ''):gsub('%s+$', '')
    else
        targetNum = tonumber(nameOrIdOrEntry)
        targetStr = tostring(nameOrIdOrEntry):lower():gsub('^%s+', ''):gsub('%s+$', '')
    end

    for i, entry in ipairs(list) do
        local eName, eId = getPlayerInfo(entry)
        if (targetNum and targetNum > 0 and eId > 0 and eId == targetNum) or
           (targetStr and targetStr ~= '' and eName ~= '' and eName:lower() == targetStr) then
            table.remove(list, i)
            saveLoadout()
            if eId > 0 then
                print(string.format('\ag[Triune Auto-Accept]\ax Removed from auto-accept list: \ay%s\ax (ID: \at%d\ax)', eName, eId))
            else
                print(string.format('\ag[Triune Auto-Accept]\ax Removed from auto-accept list: \ay%s\ax', eName))
            end
            return true
        end
    end
    return false
end

local function clearNames()
    local c = ctrl()
    if not c then return end
    c.auto_accept_names = {}
    saveLoadout()
    print('\ag[Triune Auto-Accept]\ax Cleared all names from auto-accept list.')
end

-- ----------------------------------------------------------------------------
-- Authorization
-- ----------------------------------------------------------------------------
local function isAllowed(senderName, senderId)
    local c = ctrl()
    if not c then return false end
    if (not senderName or senderName == '') and (not senderId or senderId == 0) then return false end
    if senderName then
        senderName = tostring(senderName):gsub('^%s+', ''):gsub('%s+$', '')
    end

    -- 1. Accept from anyone
    if c.auto_accept_anyone then return true end

    -- 2. Whitelist match (by ID or case-insensitive name)
    if senderId and senderId > 0 and isListed(senderId) then return true end
    if senderName and senderName ~= '' and isListed(senderName) then return true end

    local sLower = senderName and senderName:lower() or ''
    local sIdNum = tonumber(senderId) or 0
    local mq = core and core.mq

    -- Resolve the sender's ID from the zone when only a name was given.
    if sIdNum == 0 and senderName and senderName ~= '' then
        local sp = resolveSpawn(senderName, 0)
        if sp then
            pcall(function() sIdNum = sp.ID() or 0 end)
            if isListed(sIdNum) then return true end
        end
    end

    -- 3. Group member match
    if c.auto_accept_group and mq and mq.TLO and mq.TLO.Group then
        local isGrp = false
        pcall(function()
            local memCount = mq.TLO.Group.Members() or 0
            for i = 1, memCount do
                local mem = mq.TLO.Group.Member(i)
                if mem and mem() then
                    local mId = mem.ID and mem.ID() or 0
                    local mName = mem.CleanName and mem.CleanName() or ''
                    if (sIdNum > 0 and mId > 0 and mId == sIdNum) or
                       (sLower ~= '' and mName ~= '' and mName:lower() == sLower) then
                        isGrp = true
                        break
                    end
                end
            end
        end)
        if isGrp then return true end
    end

    -- 4. Guild member match
    if c.auto_accept_guild and mq and mq.TLO and mq.TLO.Me then
        local isGld = false
        pcall(function()
            local myG = mq.TLO.Me.Guild
            local myGuild = (myG and myG() and myG() ~= '' and myG() ~= 'NULL') and myG() or nil
            if not myGuild then return end
            local sp = resolveSpawn(senderName, sIdNum)
            if sp and sp.Guild then
                local theirG = sp.Guild()
                if theirG and theirG ~= '' and theirG:lower() == myGuild:lower() then
                    isGld = true
                end
            end
        end)
        if isGld then return true end
    end

    return false
end

-- ----------------------------------------------------------------------------
-- Accept actions (shared by chat events and the window poll)
-- ----------------------------------------------------------------------------
local function acceptGroupInvite(inviter, inviterId)
    local now = os.clock()
    if lastGroupAcceptAt and (now - lastGroupAcceptAt) <= 2.0 then return end
    lastGroupAcceptAt = now
    local mq = core and core.mq
    if not mq then return end
    mq.cmd('/timed 5 /invite')
    if inviterId and inviterId > 0 then
        print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax (ID: \at%d\ax).', inviter, inviterId))
    else
        print(string.format('\ag[Triune Auto-Accept]\ax Accepted group invite from \ay%s\ax.', inviter))
    end
    local confOpen = false
    pcall(function() confOpen = mq.TLO.Window('ConfirmationDialogBox').Open() end)
    if confOpen then
        pcall(function() mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup') end)
    end
end

local function acceptDzInvite(who, label)
    local now = os.clock()
    if lastDzAcceptAt and (now - lastDzAcceptAt) <= 1.5 then return end
    lastDzAcceptAt = now
    local mq = core and core.mq
    if not mq then return end
    local confOpen = false
    pcall(function() confOpen = mq.TLO.Window('ConfirmationDialogBox').Open() end)
    if confOpen then
        mq.cmd('/notify ConfirmationDialogBox Yes_Button leftmouseup')
    end
    mq.cmd('/dzaccept')
    print(string.format('\ag[Triune Auto-Accept]\ax Accepted %s invite from \ay%s\ax.', label or 'expedition / dynamic zone', who or 'sender'))
end

-- ----------------------------------------------------------------------------
-- Window poll (Me.Invited, TradeWnd, ConfirmationDialogBox)
-- ----------------------------------------------------------------------------
local function pollGroupInvite(c, mq)
    if not (c.auto_group and mq.TLO.Me) then return end
    local isInvited = false
    pcall(function() isInvited = mq.TLO.Me.Invited() end)
    if not isInvited then return end
    local inviter = nil
    pcall(function() inviter = mq.TLO.Me.Inviter() end)
    if not inviter or inviter == '' then return end
    local inviterId = 0
    local sp = resolveSpawn(inviter, 0)
    if sp then pcall(function() inviterId = sp.ID() or 0 end) end
    if isAllowed(inviter, inviterId) then
        acceptGroupInvite(inviter, inviterId)
    end
end

local function pollTrade(c, mq, now)
    if not (c.auto_trade and mq.TLO.Window) then return end
    local tradeOpen = false
    pcall(function() tradeOpen = mq.TLO.Window('TradeWnd').Open() end)
    if not tradeOpen then return end

    local hisReady, myReady = false, false
    pcall(function()
        hisReady = mq.TLO.Window('TradeWnd').HisTradeReady()
        myReady = mq.TLO.Window('TradeWnd').MyTradeReady()
    end)
    if not hisReady or myReady then return end

    local traderName, traderId = nil, 0
    pcall(function()
        local lbl = mq.TLO.Window('TradeWnd').Child('TRDW_HisName')
        if lbl and lbl() then traderName = lbl.Text() end
    end)
    pcall(function()
        local tgt = mq.TLO.Target
        if tgt and tgt() and tgt.Type() == 'PC' then
            if not traderName or traderName == '' then traderName = tgt.CleanName() end
            traderId = tgt.ID() or 0
        end
    end)
    if traderName and traderName ~= '' and traderId == 0 then
        local sp = resolveSpawn(traderName, 0)
        if sp then pcall(function() traderId = sp.ID() or 0 end) end
    end

    if not ((traderName and traderName ~= '') or traderId > 0) then return end
    if not isAllowed(traderName, traderId) then return end
    if lastTradeAcceptAt and (now - lastTradeAcceptAt) <= 1.5 then return end
    lastTradeAcceptAt = now
    mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
    if traderId > 0 then
        print(string.format('\ag[Triune Auto-Accept]\ax Accepted trade from \ay%s\ax (ID: \at%d\ax).', traderName or 'Unknown', traderId))
    else
        print(string.format('\ag[Triune Auto-Accept]\ax Accepted trade from \ay%s\ax.', traderName))
    end
end

local function pollDzConfirmation(c, mq)
    if not (c.auto_dzadd and mq.TLO.Window) then return end
    local confOpen = false
    pcall(function() confOpen = mq.TLO.Window('ConfirmationDialogBox').Open() end)
    if not confOpen then return end

    local text = ''
    pcall(function()
        local out = mq.TLO.Window('ConfirmationDialogBox').Child('CD_TextOutput')
        if out and out() then text = out.Text() or '' end
    end)
    local tLower = text:lower()
    -- Ignore rez prompts or fellowship removals
    if tLower:find('percent') or tLower:find('corpse') or tLower:find('resurrect') or tLower:find('remove') then return end
    if not (tLower:find('expedition') or tLower:find('dynamic zone') or tLower:find('task') or tLower:find('dzadd') or tLower:find('dz')) then return end

    local candidateName = text:match('^([%a%d]+)%s+has%s+invited%s+you') or text:match('^([%a%d]+)%s+invites%s+you')
    local candidateId = 0
    if candidateName and candidateName ~= '' then
        local sp = resolveSpawn(candidateName, 0)
        if sp then pcall(function() candidateId = sp.ID() or 0 end) end
    end

    local allowed = false
    if c.auto_accept_anyone then
        allowed = true
    elseif candidateName and candidateName ~= '' then
        allowed = isAllowed(candidateName, candidateId)
    else
        -- No sender in the dialog text: fall back to scanning it for a whitelisted name / id.
        for _, n in ipairs(ensureList() or {}) do
            local eName, eId = getPlayerInfo(n)
            if (eName ~= '' and tLower:find(eName:lower(), 1, true)) or
               (eId > 0 and tLower:find(tostring(eId), 1, true)) then
                allowed = true
                candidateName = eName
                candidateId = eId
                break
            end
        end
    end

    if allowed then
        acceptDzInvite(candidateName or (candidateId > 0 and tostring(candidateId)) or 'sender', 'expedition / dynamic zone')
    end
end

function plugin.onTick()
    local c = ctrl()
    local mq = core and core.mq
    if not c or not mq or not mq.TLO then return end
    if not (c.auto_group or c.auto_trade or c.auto_dzadd) then return end
    local now = os.clock()
    pollGroupInvite(c, mq)
    pollTrade(c, mq, now)
    pollDzConfirmation(c, mq)
end

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    local c = ctrl()
    if c then
        if c.auto_group == nil then c.auto_group = false end
        if c.auto_trade == nil then c.auto_trade = false end
        if c.auto_dzadd == nil then c.auto_dzadd = false end
        if c.auto_accept_anyone == nil then c.auto_accept_anyone = false end
        if c.auto_accept_guild == nil then c.auto_accept_guild = false end
        if c.auto_accept_group == nil then c.auto_accept_group = false end
        if c.show_auto_accept == nil then c.show_auto_accept = false end
        ensureList()
    end

    local mq = core.mq
    if not (mq and mq.event) then return end

    local function reg(name, pattern, handler)
        if mq.unevent then pcall(mq.unevent, name) end
        mq.event(name, pattern, handler)
        table.insert(registeredEvents, name)
    end

    local function onGroupInvite(_, inviter)
        local cc = ctrl()
        if cc and cc.auto_group and inviter and isAllowed(inviter) then
            acceptGroupInvite(inviter)
        end
    end
    local function onDzInvite(label)
        return function(_, inviter)
            local cc = ctrl()
            if cc and cc.auto_dzadd and inviter and isAllowed(inviter) then
                acceptDzInvite(inviter, label)
            end
        end
    end

    reg('TacAutoGroupInvite1', '#1# invites you to join a group#*#', onGroupInvite)
    reg('TacAutoGroupInvite2', '#1# has invited you to join a group#*#', onGroupInvite)
    reg('TacAutoDZInvite1', '#1# has invited you to join #*# expedition#*#', onDzInvite('expedition'))
    reg('TacAutoDZInvite2', '#1# invites you to join an expedition#*#', onDzInvite('expedition'))
    reg('TacAutoDZInvite3', '#1# has invited you to join a Dynamic Zone#*#', onDzInvite('Dynamic Zone'))
end

function plugin.onDestroy()
    local mq = core and core.mq
    if mq and mq.unevent then
        for _, name in ipairs(registeredEvents) do
            pcall(mq.unevent, name)
        end
    end
    registeredEvents = {}
end

-- ----------------------------------------------------------------------------
-- Settings page (rendered by Settings -> Auto-Accept and the Plugins tab modal)
-- ----------------------------------------------------------------------------
local function checkbox(label, key, tooltip)
    local c = ctrl()
    local ImGui = core and core.ImGui
    if not c or not ImGui then return end
    local cur = c[key] or false
    local val = ImGui.Checkbox(label, cur)
    if val ~= cur then
        c[key] = val
        saveLoadout()
    end
    if tooltip and ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', tooltip)
    end
end

local function currentPcTarget()
    local mq = core and core.mq
    local tName, tId = nil, 0
    if not mq then return tName, tId end
    pcall(function()
        local tgt = mq.TLO.Target
        if tgt and tgt() and tgt.Type() == 'PC' then
            tName = tgt.CleanName()
            tId = tgt.ID() or 0
        end
    end)
    return tName, tId
end

-- Full Auto-Accept panel (rules, whitelist editor). Rendered in the popout window.
local function drawPanel()
    local c = ctrl()
    if not core or not core.ImGui or not c then return end
    local ImGui = core.ImGui
    local accent = core.accent
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    local ARC = colors.ARC or { 0.30, 0.70, 1.0, 1 }
    local MUTED = colors.MUTED or { 0.49, 0.56, 0.65, 1 }

    accent(GOLD, 'Social & Group Automation')
    ImGui.TextDisabled('Automatically accept group invites, trades, and expedition (DZ) requests based on configured rules.')
    ImGui.Separator()

    accent(GOLD, 'Automation Actions:')
    checkbox('Auto-Accept Group Invites##aaGrp', 'auto_group',
        'Automatically joins group when invited by an authorized player.')
    checkbox('Auto-Accept Trades##aaTrd', 'auto_trade',
        'Automatically clicks trade accept when incoming trade partner has clicked their trade button and is authorized.')
    checkbox('Auto-Accept Dynamic Zone / Expedition Invites (DZAdd)##aaDz', 'auto_dzadd',
        'Automatically accepts expedition (/dzaccept), dynamic zone, and task addition invites from authorized players.')

    ImGui.Separator()

    accent(GOLD, 'Authorization Rules (Who to accept from):')
    checkbox('Accept from Anyone##aaAnyone', 'auto_accept_anyone',
        'Accept requests from ANY player unconditionally (bypasses group, guild, and whitelist checks).')
    checkbox('Always accept from Group Members##aaGrpMem', 'auto_accept_group',
        'Accept trades and expedition requests from current group members.')
    checkbox('Accept from all Guild Members##aaGuild', 'auto_accept_guild',
        'Accept requests from players in the same guild as your character.')

    ImGui.Separator()

    accent(GOLD, 'Whitelisted Players:')
    ImGui.TextDisabled('Specific character names and player IDs allowed to trigger auto-accept (case-insensitive):')

    ImGui.SetNextItemWidth(170)
    local enteredText, enterPressed = ImGui.InputTextWithHint('##autoAcceptAddInput', 'Player Name or ID', inputName,
        (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0)
    if enteredText ~= nil then inputName = enteredText end
    ImGui.SameLine()
    if ImGui.Button('Add##autoAcceptAddBtn') or enterPressed then
        if inputName:gsub('%s+', '') ~= '' then
            addName(inputName)
            inputName = ''
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Add the entered player name or ID to the auto-accept whitelist.')
    end

    ImGui.SameLine()
    if ImGui.Button('+ Add Target##autoAcceptAddTargetBtn') then
        local tName, tId = currentPcTarget()
        if tName and tName ~= '' then
            addName(tName, tId)
        else
            print('\ar[Triune Auto-Accept]\ax Target is not a player character.')
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Target a player character (PC) in-game and click to add their Name and Player ID.')
    end

    local tgtName, tgtId = currentPcTarget()
    local targetListed = (tgtId > 0 and isListed(tgtId)) or (tgtName and tgtName ~= '' and isListed(tgtName))
    local canRemove = (selectedPlayer and selectedPlayer ~= '') or targetListed

    ImGui.SameLine()
    if not canRemove then ImGui.BeginDisabled() end
    if ImGui.Button('Remove##autoAcceptRemoveBtn') then
        if selectedPlayer and selectedPlayer ~= '' then
            removeName(selectedPlayer)
            selectedPlayer = nil
        elseif tgtId > 0 and isListed(tgtId) then
            removeName(tgtId)
        elseif tgtName and tgtName ~= '' then
            removeName(tgtName)
        end
    end
    if not canRemove then ImGui.EndDisabled() end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Remove the selected player from the whitelist (or target a whitelisted player to remove them).')
    end

    local names = ensureList() or {}
    if #names > 0 then
        ImGui.SameLine()
        if ImGui.Button('Clear All##autoAcceptClearBtn') then
            clearNames()
            selectedPlayer = nil
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s', 'Remove all players from the auto-accept whitelist.')
        end
    end

    if #names == 0 then
        accent(MUTED, 'No whitelisted players configured.')
        return
    end

    local tableFlags = bit.bor(
        (ImGuiTableFlags and ImGuiTableFlags.Borders) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.RowBg) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.ScrollY) or 0
    )
    if ImGui.BeginTable('autoAcceptWhitelistTable', 3, tableFlags, 0, 180) then
        ImGui.TableSetupColumn('Player Name', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthStretch) or 0)
        ImGui.TableSetupColumn('Player ID', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 95)
        ImGui.TableSetupColumn('Action', (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0, 75)
        ImGui.TableHeadersRow()

        local toRemove = nil
        for i, entry in ipairs(names) do
            local eName, eId = getPlayerInfo(entry)
            local isSelected = (selectedPlayer and selectedPlayer:lower() == eName:lower())
            ImGui.TableNextRow()

            ImGui.TableSetColumnIndex(0)
            ImGui.PushID('aa_row_name_' .. i)
            if ImGui.Selectable(eName, isSelected, (ImGuiSelectableFlags and ImGuiSelectableFlags.SpanAllColumns) or 0) then
                selectedPlayer = eName
            end
            ImGui.PopID()

            ImGui.TableSetColumnIndex(1)
            if eId > 0 then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(eId))
            else
                ImGui.TextDisabled('--')
            end

            ImGui.TableSetColumnIndex(2)
            ImGui.PushID('aa_btn_remove_' .. i)
            if ImGui.Button('Remove', 60, 20) then
                toRemove = entry
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', string.format('Remove %s from the whitelist.', eName))
            end
            ImGui.PopID()
        end

        ImGui.EndTable()

        if toRemove then
            local rName = getPlayerInfo(toRemove)
            removeName(toRemove)
            if selectedPlayer and rName:lower() == selectedPlayer:lower() then
                selectedPlayer = nil
            end
        end
    end
    ImGui.TextDisabled(string.format('%d whitelisted player(s) configured', #names))
    if selectedPlayer then
        ImGui.SameLine()
        accent(GOLD, string.format('Selected: %s', selectedPlayer))
    end
end

-- Popout window (was the Settings -> Auto-Accept sub-tab)
function plugin.onDrawUI()
    local c = ctrl()
    if not core or not core.ImGui or not c or not c.show_auto_accept then return end
    local ImGui = core.ImGui
    core.pushTheme()
    ImGui.SetNextWindowSize(620, 520, ImGuiCond.FirstUseEver)
    core.preBeginWindow('auto_accept')
    local open, show = ImGui.Begin('Triune Auto-Accept v' .. (core.VERSION or '') .. '###triuneAutoAccept', c.show_auto_accept)
    if not open then
        c.show_auto_accept = false
        ImGui.End()
        core.popTheme()
        saveLoadout()
        return
    end
    if show then
        core.postBeginWindow('auto_accept')
        drawPanel()
    end
    ImGui.End()
    core.popTheme()
end

-- Plugin settings panel (Settings -> Plugins -> Configure): window toggle + quick actions
function plugin.onDrawSettings()
    local c = ctrl()
    if not core or not core.ImGui or not c then return end
    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Auto-Accept Invites')
    local isWinOpen = (c.show_auto_accept == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##aaAccToggleWin', 250, 24) then
        c.show_auto_accept = not isWinOpen
        saveLoadout()
    end
    ImGui.TextDisabled('Rules and the player whitelist live in the Auto-Accept window (header button or /ac autoaccept). Quick toggles:')
    checkbox('Auto-Accept Group Invites##aaGrpQ', 'auto_group', 'Automatically joins group when invited by an authorized player.')
    checkbox('Auto-Accept Trades##aaTrdQ', 'auto_trade', 'Automatically clicks trade accept when incoming trade partner has clicked their trade button and is authorized.')
    checkbox('Auto-Accept Dynamic Zone / Expedition Invites (DZAdd)##aaDzQ', 'auto_dzadd', 'Automatically accepts expedition (/dzaccept), dynamic zone, and task addition invites from authorized players.')
end

-- /ac autoaccept | acceptwin toggles the window
function plugin.onCommand(cmd)
    if cmd ~= 'autoaccept' and cmd ~= 'acceptwin' and cmd ~= 'acceptui' then return false end
    local c = ctrl()
    if not c then return true end
    c.show_auto_accept = not c.show_auto_accept
    saveLoadout()
    print(string.format('\ag[Triune]\ax Auto-Accept window %s.', c.show_auto_accept and 'OPENED' or 'CLOSED'))
    return true
end

plugin.help = {
    '  \ag/ac autoaccept | acceptwin\ax - Toggle the Auto-Accept invites / whitelist window',
}

-- Exposed for tests and for other plugins / slash commands that want to reuse
-- the whitelist without duplicating it.
plugin.isAutoAcceptListed = isListed
plugin.isAutoAcceptAllowed = isAllowed
plugin.addAutoAcceptName = addName
plugin.removeAutoAcceptName = removeName
plugin.clearAutoAcceptNames = clearNames
plugin.getAutoAcceptPlayerInfo = getPlayerInfo
plugin.drawPanel = drawPanel

return plugin
