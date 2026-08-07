---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune Buffbot v1.0 (Standalone MacroQuest ImGui Script)
-- ----------------------------------------------------------------------------
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- Run with:  /lua run triune_buffbot
--
-- Features:
-- - Saves current spell gems on startup / start, memorizes selected buff list.
-- - Restores original spell gems on stop / script exit via mq.atexit().
-- - Monitors incoming /tell messages, verifies distance to requester.
-- - Interactive two-stage tell confirmation ("Would you like buffs? Reply 'yes'").
-- - Casts selected buff spells and sends a completion /tell when finished.
-- - Dropdown combo boxes for selecting buff spells per slot from scribed spellbook.
-- - Theme styling adhering to Triune dark design system.
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library

local scriptDir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path = scriptDir .. "?.lua;" .. package.path

local VERSION = '1.0'
local cfg = mq.configDir

-- ============================================================================
-- Theme & Styling Setup
-- ============================================================================
local GOLD  = { 1.00, 0.70, 0.54, 1 }
local ARC   = { 0.30, 0.70, 1.00, 1 }
local MUTED = { 0.49, 0.56, 0.65, 1 }
local GOOD  = { 0.37, 0.88, 0.64, 1 }
local WARN  = { 1.00, 0.72, 0.30, 1 }
local ERR   = { 0.95, 0.35, 0.35, 1 }

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

-- ============================================================================
-- Structured State Tables
-- ============================================================================
local NUM_GEMS = 12

local ctrl = {
    enabled       = false,
    maxRange      = 100,
    timeoutSec    = 30,
    cooldownSec   = 60,
    minManaPct    = 15,
    promptMsg     = "Would you like buffs? Reply 'yes' within 30 seconds.",
    completionMsg = "All buffs cast! Enjoy!",
    buffSlots     = {} -- buffSlots[slot] = spellName
}

local runtime = {
    openGUI             = true,
    state               = 'STOPPED', -- STOPPED, IDLE, MEMMING, CASTING, RESTORING
    savedGems           = {},        -- savedGems[slot] = originalSpellName or nil
    pendingOffers       = {},        -- sender -> { timestamp = os.time(), spawnID = id }
    cooldowns           = {},        -- sender -> timestamp
    activeQueue         = {},        -- array of { sender = name, spawnID = id }
    currentRequester    = nil,
    currentSpellIndex   = 0,
    log                 = {},
    scribedSpells       = {},        -- list of scribed spell names for dropdown
    scribedSpellsLoaded = false,
    pendingAction       = nil        -- queued thread-safe UI actions
}

local function logMsg(msg, isWarn, isErr)
    local prefix = os.date("[%H:%M:%S] ")
    table.insert(runtime.log, 1, { time = prefix, msg = msg, isWarn = isWarn, isErr = isErr })
    if #runtime.log > 100 then table.remove(runtime.log) end
end

-- ============================================================================
-- Scribed Spellbook Inspection
-- ============================================================================
local function refreshScribedSpells()
    local spells = {}
    pcall(function()
        for i = 1, 720 do
            local spell = mq.TLO.Me.Book(i)
            if spell() then
                local name = spell.Name()
                if name and name ~= '' then
                    table.insert(spells, name)
                end
            end
        end
    end)
    table.sort(spells)
    runtime.scribedSpells = spells
    runtime.scribedSpellsLoaded = true
    logMsg(string.format("Loaded %d scribed spells from spellbook.", #spells))
end

-- ============================================================================
-- Gem Save / Restore / Memorize Logic
-- ============================================================================
local function clearCursor()
    pcall(function()
        local count = 0
        while (mq.TLO.Cursor.ID() or 0) > 0 and count < 255 do
            mq.cmd('/autoinventory')
            mq.delay(50)
            count = count + 1
        end
    end)
end

local function saveCurrentGems()
    runtime.savedGems = {}
    local numGems = 8
    pcall(function() numGems = mq.TLO.Me.NumGems() or 8 end)
    for slot = 1, numGems do
        local spellName = nil
        pcall(function()
            local gem = mq.TLO.Me.Gem(slot)
            if gem() then spellName = gem.Name() end
        end)
        runtime.savedGems[slot] = spellName
    end
    logMsg(string.format("Saved snapshot of %d spell gems.", numGems))
end

local function restoreSavedGems()
    if not runtime.savedGems or next(runtime.savedGems) == nil then return end
    runtime.state = 'RESTORING'
    logMsg("Restoring original spell gems...")
    local numGems = 8
    pcall(function() numGems = mq.TLO.Me.NumGems() or 8 end)

    clearCursor()
    for slot = 1, numGems do
        local orig = runtime.savedGems[slot]
        local current = nil
        pcall(function() current = mq.TLO.Me.Gem(slot).Name() end)

        if orig and orig ~= '' then
            if current ~= orig then
                pcall(function()
                    mq.cmdf('/memspell %d "%s"', slot, orig)
                    mq.delay(3000, function() return (mq.TLO.Me.Gem(slot).Name() or '') == orig end)
                end)
            end
        else
            if current then
                pcall(function()
                    mq.cmdf('/unmemspell %d', slot)
                    mq.delay(1000, function() return mq.TLO.Me.Gem(slot).Name() == nil end)
                end)
            end
        end
    end
    runtime.state = 'STOPPED'
    logMsg("Original spell gems successfully restored.")
end

local function memorizeBuffSlots()
    runtime.state = 'MEMMING'
    logMsg("Memorizing configured buff spell slots...")
    clearCursor()

    for slot = 1, NUM_GEMS do
        local targetSpell = ctrl.buffSlots[slot]
        if targetSpell and targetSpell ~= '' then
            local current = nil
            pcall(function() current = mq.TLO.Me.Gem(slot).Name() end)
            if current ~= targetSpell then
                pcall(function()
                    mq.cmdf('/memspell %d "%s"', slot, targetSpell)
                    mq.delay(4000, function() return (mq.TLO.Me.Gem(slot).Name() or '') == targetSpell end)
                end)
            end
        end
    end

    -- Wait briefly for spell gems to finish memorizing/charging
    mq.delay(2000)
    runtime.state = 'IDLE'
    logMsg("Buff spell memorization complete. Listening for tells.")
end

-- Ensure gems are restored if script terminates via /lua stop
mq.atexit(function()
    if runtime.savedGems and next(runtime.savedGems) ~= nil then
        restoreSavedGems()
    end
end)

-- ============================================================================
-- Interactive Tell Event Handler
-- ============================================================================
local function onTellReceived(line, sender, msg)
    if not ctrl.enabled then return end
    if not sender or sender == '' or not msg then return end

    -- Check if sender is current character
    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    if myName and sender:lower() == myName:lower() then return end

    local trimmedMsg = msg:gsub("^%s*(.-)%s*$", "%1"):lower()
    local now = os.time()

    -- Check Cooldown
    local cd = runtime.cooldowns[sender]
    if cd and (now - cd) < ctrl.cooldownSec then
        local rem = ctrl.cooldownSec - (now - cd)
        pcall(function()
            mq.cmdf('/tell %s You were recently buffed! Please wait %d seconds.', sender, rem)
        end)
        return
    end

    -- Query requester spawn
    local spawn = nil
    pcall(function() spawn = mq.TLO.Spawn(string.format('pc =%s', sender)) end)
    if not spawn or not spawn() or (spawn.ID() or 0) <= 0 then
        pcall(function()
            mq.cmdf('/tell %s Unable to locate you in this zone for buffing.', sender)
        end)
        return
    end

    local dist = 9999
    pcall(function() dist = spawn.Distance() or 9999 end)
    if dist > ctrl.maxRange then
        pcall(function()
            mq.cmdf('/tell %s You are out of range for buffing (%.0f > %d). Please move closer.', sender, dist, ctrl.maxRange)
        end)
        return
    end

    -- Check existing pending offer for sender
    local pending = runtime.pendingOffers[sender]

    if pending and (now - pending.timestamp) <= ctrl.timeoutSec then
        -- Sender is replying to our offer prompt
        if trimmedMsg == 'yes' or trimmedMsg == 'y' or trimmedMsg:find('yes') then
            logMsg(string.format("Requester '%s' accepted buff offer. Queuing request.", sender))
            runtime.pendingOffers[sender] = nil
            table.insert(runtime.activeQueue, { sender = sender, spawnID = spawn.ID() })
            pcall(function()
                mq.cmdf('/tell %s Stand by, preparing to cast your buffs!', sender)
            end)
        else
            logMsg(string.format("Requester '%s' sent follow-up tell: '%s'", sender, msg))
        end
    else
        -- Initial tell or expired offer: send prompt tell asking if they want buffs
        runtime.pendingOffers[sender] = { timestamp = now, spawnID = spawn.ID() }
        logMsg(string.format("Received tell from '%s'. Prompting for buff confirmation.", sender))
        pcall(function()
            mq.cmdf('/tell %s %s', sender, ctrl.promptMsg)
        end)
    end
end

mq.event('BuffbotTell', '#1# tells you, \'#2#\'', onTellReceived)

-- ============================================================================
-- Buff Casting Loop
-- ============================================================================
local function processBuffQueue()
    if #runtime.activeQueue == 0 then
        if runtime.state ~= 'MEMMING' and runtime.state ~= 'RESTORING' and runtime.state ~= 'STOPPED' then
            runtime.state = 'IDLE'
        end
        return
    end

    local request = table.remove(runtime.activeQueue, 1)
    local targetName = request.sender
    local targetID = request.spawnID

    runtime.state = 'CASTING'
    runtime.currentRequester = targetName
    logMsg(string.format("Starting buff sequence for '%s'...", targetName))

    -- Target the requester
    pcall(function() mq.cmdf('/target id %d', targetID) end)
    mq.delay(500, function() return (mq.TLO.Target.ID() or 0) == targetID end)

    local targetValid = false
    pcall(function() targetValid = (mq.TLO.Target.ID() or 0) == targetID and not mq.TLO.Target.Dead() end)
    if not targetValid then
        logMsg(string.format("Target '%s' lost or out of range. Aborting buff sequence.", targetName), true, false)
        runtime.currentRequester = nil
        return
    end

    -- Sequence through configured buff slots
    for slot = 1, NUM_GEMS do
        if not ctrl.enabled then break end

        local spellName = ctrl.buffSlots[slot]
        if spellName and spellName ~= '' then
            -- Verify spell is memorized in a gem slot
            local gemNum = nil
            pcall(function() gemNum = mq.TLO.Me.Gem(spellName)() end)
            if not gemNum then
                pcall(function() gemNum = mq.TLO.Me.Gem(slot).Name() == spellName and slot or nil end)
            end

            if gemNum then
                -- Check Mana %
                local pctMana = 100
                pcall(function() pctMana = mq.TLO.Me.PctMana() or 100 end)
                if pctMana < ctrl.minManaPct then
                    logMsg(string.format("Mana low (%d%% < %d%%). Medding brief moment...", pctMana, ctrl.minManaPct), true, false)
                    mq.delay(3000)
                end

                -- Wait for gem readiness
                logMsg(string.format("Casting slot %d: '%s' on %s", slot, spellName, targetName))
                local ready = false
                pcall(function() ready = mq.TLO.Me.SpellReady(gemNum)() end)
                if not ready then
                    mq.delay(3000, function() return mq.TLO.Me.SpellReady(gemNum)() end)
                end

                -- Re-target if target dropped
                pcall(function()
                    if (mq.TLO.Target.ID() or 0) ~= targetID then
                        mq.cmdf('/target id %d', targetID)
                    end
                end)

                -- Cast the spell
                pcall(function() mq.cmdf('/cast %d', gemNum) end)
                mq.delay(500)

                -- Wait for casting to complete
                local isCasting = true
                local attempts = 0
                while isCasting and attempts < 100 do
                    pcall(function() isCasting = mq.TLO.Me.Casting() ~= nil end)
                    if isCasting then
                        mq.delay(200)
                        attempts = attempts + 1
                    end
                end
                mq.delay(800) -- recovery delay between casts
            end
        end
    end

    -- Send Completion Tell to Requester
    logMsg(string.format("Completed buff sequence for '%s'. Sending completion tell.", targetName))
    pcall(function()
        mq.cmdf('/tell %s %s', targetName, ctrl.completionMsg)
    end)

    -- Set Cooldown
    runtime.cooldowns[targetName] = os.time()
    runtime.currentRequester = nil
end

-- ============================================================================
-- ImGui UI Rendering
-- ============================================================================
local function drawControlTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Buffbot Control Surface")
    ImGui.Separator()

    -- Start / Stop Toggle Button
    if not ctrl.enabled then
        if ImGui.Button("  START BUFFBOT  ", 180, 32) then
            runtime.pendingAction = 'START'
        end
        ImGui.SameLine()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Status: STOPPED")
    else
        if ImGui.Button("  STOP BUFFBOT  ", 180, 32) then
            runtime.pendingAction = 'STOP'
        end
        ImGui.SameLine()
        if runtime.state == 'IDLE' then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Status: LISTENING FOR TELLS")
        elseif runtime.state == 'MEMMING' then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "Status: MEMORIZING BUFFS...")
        elseif runtime.state == 'CASTING' then
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("Status: BUFFING %s...", runtime.currentRequester or ''))
        elseif runtime.state == 'RESTORING' then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "Status: RESTORING ORIGINAL GEMS...")
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Configuration Options")

    local rangeVal, rangeChanged = ImGui.SliderInt("Max Requester Range", ctrl.maxRange, 20, 300)
    if rangeChanged then ctrl.maxRange = rangeVal end

    local timeoutVal, timeoutChanged = ImGui.SliderInt("Offer Expiration (sec)", ctrl.timeoutSec, 10, 120)
    if timeoutChanged then ctrl.timeoutSec = timeoutVal end

    local cdVal, cdChanged = ImGui.SliderInt("Player Cooldown (sec)", ctrl.cooldownSec, 10, 300)
    if cdChanged then ctrl.cooldownSec = cdVal end

    local manaVal, manaChanged = ImGui.SliderInt("Min Mana % Threshold", ctrl.minManaPct, 5, 50)
    if manaChanged then ctrl.minManaPct = manaVal end

    ImGui.Spacing()
    ImGui.Text("Prompt Tell (Sent on initial tell):")
    local newPrompt, promptChanged = ImGui.InputText("##promptMsg", ctrl.promptMsg, 256)
    if promptChanged then ctrl.promptMsg = newPrompt end

    ImGui.Text("Completion Tell (Sent after all buffs cast):")
    local newComp, compChanged = ImGui.InputText("##completionMsg", ctrl.completionMsg, 256)
    if compChanged then ctrl.completionMsg = newComp end
end

local function drawBuffSlotsTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Buff Spell Selection")
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Select which scribed spells to memorize and cast on requesters.")
    ImGui.Separator()

    if not runtime.scribedSpellsLoaded then
        if ImGui.Button("Load Scribed Spells from Spellbook") then
            refreshScribedSpells()
        end
        ImGui.Spacing()
    end

    for slot = 1, NUM_GEMS do
        ImGui.PushID(slot)
        ImGui.Text(string.format("Buff Slot %2d:", slot))
        ImGui.SameLine()

        local currentSpell = ctrl.buffSlots[slot] or ""
        local preview = (currentSpell ~= "") and currentSpell or "-- (None) --"

        if ImGui.BeginCombo("##buffCombo", preview) then
            if ImGui.Selectable("-- (None) --", currentSpell == "") then
                ctrl.buffSlots[slot] = nil
            end

            for _, spellName in ipairs(runtime.scribedSpells) do
                local isSelected = (currentSpell == spellName)
                if ImGui.Selectable(spellName, isSelected) then
                    ctrl.buffSlots[slot] = spellName
                end
                if isSelected then
                    ImGui.SetItemDefaultFocus()
                end
            end
            ImGui.EndCombo()
        end

        ImGui.PopID()
    end
end

local function drawActivityTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Active Queue & Event Log")
    ImGui.Separator()

    ImGui.Text(string.format("Active Request Queue: %d pending", #runtime.activeQueue))
    if #runtime.activeQueue > 0 then
        if ImGui.BeginTable("##queueTable", 2, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn("Requester", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Spawn ID", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableHeadersRow()

            for _, req in ipairs(runtime.activeQueue) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                ImGui.Text(req.sender)
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(tostring(req.spawnID))
            end
            ImGui.EndTable()
        end
    end

    ImGui.Spacing()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Activity Log")
    if ImGui.BeginChild("LogChild", 0, 220, true) then
        for _, entry in ipairs(runtime.log) do
            if entry.isErr then
                ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], entry.time .. entry.msg)
            elseif entry.isWarn then
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], entry.time .. entry.msg)
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], entry.time .. entry.msg)
            end
        end
        ImGui.EndChild()
    end
end

local function renderGUI()
    if not runtime.openGUI then return end

    pushTheme()
    local visible, open = ImGui.Begin(string.format("Triune Buffbot v%s###TriuneBuffbotWin", VERSION), runtime.openGUI)
    runtime.openGUI = open

    if visible then
        if ImGui.BeginTabBar("BuffbotTabBar") then
            if ImGui.BeginTabItem("Controls") then
                drawControlTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Buff Spells") then
                drawBuffSlotsTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Activity Log") then
                drawActivityTab()
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end

    ImGui.End()
    popTheme()
end

-- ============================================================================
-- Main Loop & Initialization
-- ============================================================================
local function init()
    mq.imgui.init('TriuneBuffbotWin', renderGUI)
    refreshScribedSpells()
    logMsg("Triune Buffbot script initialized.")
end

init()

while runtime.openGUI do
    mq.doevents()

    -- Process pending UI actions queued from ImGui thread
    if runtime.pendingAction == 'START' then
        runtime.pendingAction = nil
        ctrl.enabled = true
        saveCurrentGems()
        memorizeBuffSlots()
    elseif runtime.pendingAction == 'STOP' then
        runtime.pendingAction = nil
        ctrl.enabled = false
        restoreSavedGems()
    end

    -- Clean up expired pending offers
    local now = os.time()
    for sender, offer in pairs(runtime.pendingOffers) do
        if (now - offer.timestamp) > ctrl.timeoutSec then
            runtime.pendingOffers[sender] = nil
            logMsg(string.format("Offer for '%s' expired.", sender))
        end
    end

    -- Process queue if buffbot enabled
    if ctrl.enabled and (runtime.state == 'IDLE' or runtime.state == 'CASTING') then
        processBuffQueue()
    end

    mq.delay(100)
end

-- Cleanup on UI close
if ctrl.enabled or (runtime.savedGems and next(runtime.savedGems) ~= nil) then
    restoreSavedGems()
end
