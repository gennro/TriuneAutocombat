---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune Buffbot v1.1 (Standalone MacroQuest ImGui Script)
-- ----------------------------------------------------------------------------
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- Run with:  /lua run triune_buffbot
--
-- Features:
-- - Interactive Tell Menu: Responds to incoming /tells with a numbered list of
--   currently memorized spell gems and an [all] option.
-- - Flexible Requester Selection: Requesters can reply with 'all' or specific
--   spell numbers (e.g. '1 3' or '1, 2') to receive only their desired buffs.
-- - Direct Memorized Spell Gem Casting: Casts selected buffs directly from the
--   active spell bar without gem-swapping or book scanning overhead.
-- - Range, Cooldown & Low-Mana Protections.
-- - Self-test compatible: Allows testing from the local character.
-- - Configuration persistence per character (triune_buffbot_config.lua).
-- - Theme styling adhering to Triune dark design system.
-- ============================================================================

local mq           = require('mq')
local ImGui        = require('ImGui')
local bit          = require('bit') -- LuaJIT bitwise library

local scriptDir    = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path       = scriptDir .. "?.lua;" .. package.path

local VERSION      = '1.1'
local cfg          = mq.configDir

-- ============================================================================
-- Theme & Styling Setup
-- ============================================================================
local GOLD         = { 1.00, 0.70, 0.54, 1 }
local ARC          = { 0.30, 0.70, 1.00, 1 }
local MUTED        = { 0.49, 0.56, 0.65, 1 }
local GOOD         = { 0.37, 0.88, 0.64, 1 }
local WARN         = { 1.00, 0.72, 0.30, 1 }
local ERR          = { 0.95, 0.35, 0.35, 1 }

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
    if _varN > 0 then
        pcall(mq.imgui.PopStyleVar, _varN); _varN = 0
    end ---@diagnostic disable-line: undefined-field
    if _colN > 0 then
        pcall(mq.imgui.PopStyleColor, _colN); _colN = 0
    end ---@diagnostic disable-line: undefined-field
end

-- ============================================================================
-- Structured State Tables
-- ============================================================================
local ctrl = {
    enabled       = true,
    autoMed       = true,
    maxRange      = 100,
    timeoutSec    = 30,
    cooldownSec   = 60,
    minManaPct    = 15,
    completionMsg = "All buffs cast! Enjoy!"
}

local runtime = {
    openGUI           = true,
    state             = 'IDLE', -- STOPPED, IDLE, CASTING, MEDDING
    pendingOffers     = {},     -- sender -> { timestamp = os.time(), spawnID = id, gems = list }
    cooldowns         = {},     -- sender -> timestamp
    activeQueue       = {},     -- array of { sender = name, spawnID = id, gems = list }
    currentRequester  = nil,
    currentSpellsText = "",
    log               = {},
    pendingAction     = nil -- queued thread-safe UI actions
}

local function logMsg(msg, isWarn, isErr)
    local prefix = os.date("[%H:%M:%S] ")
    table.insert(runtime.log, 1, { time = prefix, msg = msg, isWarn = isWarn, isErr = isErr })
    if #runtime.log > 100 then table.remove(runtime.log) end
end

local function getMyPctMana()
    local maxMana = 0
    local pctMana = 100
    pcall(function()
        maxMana = mq.TLO.Me.MaxMana() or 0
        pctMana = mq.TLO.Me.PctMana() or 100
    end)
    if maxMana == 0 then return 100 end
    return pctMana
end

-- ============================================================================
-- Gem Discovery Helper
-- ============================================================================
local function getAvailableGems()
    local list = {}
    local numGems = 8
    pcall(function() numGems = mq.TLO.Me.NumGems() or 8 end)
    for gemNum = 1, numGems do
        local name = nil
        pcall(function()
            local gem = mq.TLO.Me.Gem(gemNum)
            if gem() then name = gem.Name() end
        end)
        if name and name ~= '' then
            table.insert(list, { gem = gemNum, name = name })
        end
    end
    return list
end

-- ============================================================================
-- Persistence (Save / Load Config per Character)
-- ============================================================================
local function serializeValue(val)
    if type(val) == 'string' then
        return string.format("%q", val)
    elseif type(val) == 'number' or type(val) == 'boolean' then
        return tostring(val)
    elseif type(val) == 'table' then
        local parts = {}
        for k, v in pairs(val) do
            local keyStr = (type(k) == 'number') and string.format("[%d]", k) or string.format("[%q]", tostring(k))
            local valStr = serializeValue(v)
            if valStr then
                table.insert(parts, keyStr .. " = " .. valStr)
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "nil"
end

local function saveConfig(silent)
    local myName, myServer = nil, nil
    pcall(function()
        myName = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    local charKey = (myServer or 'default') .. '_' .. (myName or 'default')

    local allData = {}
    local fn = loadfile(cfg .. '/triune_buffbot_config.lua')
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == 'table' then allData = t end
    end

    allData[charKey] = {
        enabled       = ctrl.enabled,
        autoMed       = ctrl.autoMed,
        maxRange      = ctrl.maxRange,
        timeoutSec    = ctrl.timeoutSec,
        cooldownSec   = ctrl.cooldownSec,
        minManaPct    = ctrl.minManaPct,
        completionMsg = ctrl.completionMsg
    }

    local f = io.open(cfg .. '/triune_buffbot_config.lua', 'w')
    if f then
        f:write("return " .. serializeValue(allData) .. "\n")
        f:close()
        if not silent then logMsg("Saved buffbot configuration.") end
    end
end

local function loadConfig()
    local myName, myServer = nil, nil
    pcall(function()
        myName = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    local charKey = (myServer or 'default') .. '_' .. (myName or 'default')

    local fn = loadfile(cfg .. '/triune_buffbot_config.lua')
    if not fn then return end
    local ok, allData = pcall(fn)
    if not ok or type(allData) ~= 'table' then return end

    local charData = allData[charKey] or allData['default']
    if charData and type(charData) == 'table' then
        if charData.enabled ~= nil then ctrl.enabled = charData.enabled end
        if charData.autoMed ~= nil then ctrl.autoMed = charData.autoMed end
        if charData.maxRange then ctrl.maxRange = charData.maxRange end
        if charData.timeoutSec then ctrl.timeoutSec = charData.timeoutSec end
        if charData.cooldownSec then ctrl.cooldownSec = charData.cooldownSec end
        if charData.minManaPct then ctrl.minManaPct = charData.minManaPct end
        if charData.completionMsg then ctrl.completionMsg = charData.completionMsg end
        logMsg("Loaded saved buffbot configuration for " .. charKey .. ".")
    end
end

-- ============================================================================
-- Tell Menu & Choice Parsing
-- ============================================================================
local function sendMenuTells(target, gemList)
    if #gemList == 0 then
        pcall(function() mq.cmdf('/tell %s I currently have no buff spells memorized.', target) end)
        return
    end

    local items = {}
    for idx, item in ipairs(gemList) do
        table.insert(items, string.format("[%d] %s", idx, item.name))
    end
    table.insert(items, "[all] All")

    local fullStr = "Buffs: " .. table.concat(items, ", ") .. " | Reply with # (e.g. 1 3) or 'all'."
    if #fullStr <= 300 then
        pcall(function() mq.cmdf('/tell %s %s', target, fullStr) end)
    else
        local mid = math.ceil(#items / 2)
        local p1, p2 = {}, {}
        for i = 1, mid do table.insert(p1, items[i]) end
        for i = mid + 1, #items do table.insert(p2, items[i]) end
        pcall(function() mq.cmdf('/tell %s Buffs (1/2): %s', target, table.concat(p1, ", ")) end)
        pcall(function() mq.cmdf('/tell %s Buffs (2/2): %s (Reply with # or \'all\')', target, table.concat(p2, ", ")) end)
    end
end

local function parseRequestedGems(msg, gemList)
    if not gemList or #gemList == 0 then return nil end

    local trimmed = tostring(msg):lower():gsub("^%s*(.-)%s*$", "%1")

    -- 1. Check for explicit 'all' keyword
    if trimmed == 'all' or trimmed == 'all buffs' or trimmed == 'buff all' then
        local allGems = {}
        for _, item in ipairs(gemList) do
            table.insert(allGems, item)
        end
        return allGems
    end

    -- 2. Check for specific numbers (e.g. '1', '2', '1 3', '1, 2', '1 2 3')
    local selected = {}
    local seen = {}
    for numStr in trimmed:gmatch("%d+") do
        local idx = tonumber(numStr)
        if idx and gemList[idx] and not seen[idx] then
            seen[idx] = true
            table.insert(selected, gemList[idx])
        end
    end

    if #selected > 0 then
        return selected
    end

    return nil
end

-- ============================================================================
-- Interactive Tell Event Handler
-- ============================================================================
local lastTellLine = ""
local lastTellTime = 0

local function isThankYou(msg)
    if not msg or msg == '' then return false end
    local text = tostring(msg):lower():gsub("[%p%c]", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    if text == '' then return false end

    if text == 'ty' or text:find('^ty%s') or text == 'tyvm' or text == 'tysm' or text:find('^tyvm%s') or text:find('^tysm%s') then
        return true
    end
    if text == 'thx' or text:find('^thx%s') or text == 'thanks' or text:find('^thanks%s') then
        return true
    end
    if text == 'thank you' or text:find('^thank you%s') or text == 'thank u' or text:find('^thank u%s') or text == 'thankyou' or text:find('^thankyou%s') then
        return true
    end
    if text:find('^much appreciated') or text:find('^appreciate it') or text:find('^appreciate you') then
        return true
    end
    return false
end

local function onTellReceived(line, sender, msg)
    if not ctrl.enabled then return end
    if not sender or sender == '' or not msg then return end

    local now = os.time()
    if line == lastTellLine and (now - lastTellTime) < 1 then
        return -- Deduplicate multiple event pattern triggers on same line
    end
    lastTellLine = line
    lastTellTime = now

    -- Strip timestamps, channel prefixes, or server names from sender
    local cleanSender = tostring(sender):gsub("%b[]", ""):gsub("%b()", ""):match("([%a%d]+)")
    if not cleanSender or cleanSender == '' then
        cleanSender = tostring(sender):match("([%a%d]+)")
    end
    if not cleanSender or cleanSender == '' then return end

    -- Ignore outbound / echo tells and ignore tells from self
    if cleanSender:lower() == 'you' then return end
    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    if myName and cleanSender:lower() == myName:lower() then return end

    -- Clean quotes/whitespace from message
    local cleanMsg = tostring(msg):gsub("^['\"%s]+", ""):gsub("['\"%s]+$", "")

    -- Log detection to UI and MQ console
    logMsg(string.format("Incoming tell from %s: '%s'", cleanSender, cleanMsg))
    print(string.format('\ay[Triune Buffbot]\ax Incoming tell from \aw%s\ax: \ag"%s"\ax', cleanSender, cleanMsg))

    -- Check for Thank You / Gratitude
    if isThankYou(cleanMsg) then
        logMsg(string.format("Received thank-you tell from '%s'. Replying with 'You're welcome!'.", cleanSender))
        pcall(function()
            mq.cmdf("/tell %s You're welcome!", cleanSender)
        end)
        return
    end

    -- Check Cooldown
    local cd = runtime.cooldowns[cleanSender]
    if cd and (now - cd) < ctrl.cooldownSec then
        local rem = ctrl.cooldownSec - (now - cd)
        pcall(function()
            mq.cmdf('/tell %s You were recently buffed! Please wait %d seconds.', cleanSender, rem)
        end)
        logMsg(string.format("Rejected request from '%s' (Cooldown: %ds remaining)", cleanSender, rem), true, false)
        return
    end

    -- Query requester spawn
    local spawn = nil
    pcall(function() spawn = mq.TLO.Spawn(string.format('pc =%s', cleanSender)) end)
    if not spawn or not spawn() or (spawn.ID() or 0) <= 0 then
        pcall(function() spawn = mq.TLO.Spawn(string.format('pc %s', cleanSender)) end)
    end

    local myLocStr = "0, 0, 0"
    pcall(function()
        local y = mq.TLO.Me.Y() or 0
        local x = mq.TLO.Me.X() or 0
        local z = mq.TLO.Me.Z() or 0
        myLocStr = string.format("%.0f, %.0f, %.0f", y, x, z)
    end)

    if not spawn or not spawn() or (spawn.ID() or 0) <= 0 then
        pcall(function()
            mq.cmdf(
                '/tell %s Unable to locate you in this zone for buffing. My location is /loc %s. Please come closer!',
                cleanSender, myLocStr)
        end)
        logMsg(string.format("Unable to locate spawn for '%s' in zone (My Loc: %s).", cleanSender, myLocStr), true, false)
        return
    end

    local dist = 9999
    pcall(function() dist = spawn.Distance() or 9999 end)
    if dist > ctrl.maxRange then
        pcall(function()
            mq.cmdf(
                '/tell %s You are out of range for buffing (%.0f > %d). My location is /loc %s. Please come closer!',
                cleanSender, dist, ctrl.maxRange, myLocStr)
        end)
        logMsg(
            string.format("Requester '%s' out of range (%.0f > %d). Sent /loc %s.", cleanSender, dist, ctrl.maxRange,
                myLocStr), true, false)
        return
    end

    local currentGems = getAvailableGems()
    if #currentGems == 0 then
        pcall(function()
            mq.cmdf('/tell %s I currently have no buff spells memorized.', cleanSender)
        end)
        logMsg("No spells memorized on gem bar to offer.", true, false)
        return
    end

    -- Check if requester already has an active menu offer
    local pending = runtime.pendingOffers[cleanSender]
    local gemListForReply = (pending and pending.gems and #pending.gems > 0) and pending.gems or currentGems

    local requestedGems = parseRequestedGems(cleanMsg, gemListForReply)

    if requestedGems and #requestedGems > 0 then
        -- Requester made a valid spell selection (or replied 'all')
        runtime.pendingOffers[cleanSender] = nil

        -- Remove any stale prior entries for this sender in queue
        for i = #runtime.activeQueue, 1, -1 do
            if runtime.activeQueue[i].sender:lower() == cleanSender:lower() then
                table.remove(runtime.activeQueue, i)
            end
        end

        local currentTargetID = 0
        pcall(function() currentTargetID = spawn.ID() or 0 end)

        table.insert(runtime.activeQueue, {
            sender  = cleanSender,
            spawnID = currentTargetID,
            gems    = requestedGems
        })
        local queuePos = #runtime.activeQueue
        local totalAhead = queuePos - 1
        if runtime.currentRequester and runtime.currentRequester ~= '' then
            totalAhead = totalAhead + 1
        end
        local lineNum = totalAhead + 1

        local namesList = {}
        for _, sp in ipairs(requestedGems) do table.insert(namesList, string.format("[%d] %s", sp.gem, sp.name)) end
        logMsg(string.format("Requester '%s' selected %d buff(s) (Line #%d): %s", cleanSender, #requestedGems, lineNum,
            table.concat(namesList, ", ")))
        print(string.format('\ag[Triune Buffbot]\ax Queued %d buff(s) for \aw%s\ax (Line #%d): %s', #requestedGems, cleanSender, lineNum,
            table.concat(namesList, ", ")))
        local pctMana = getMyPctMana()
        pcall(function()
            if totalAhead > 0 then
                if pctMana < ctrl.minManaPct then
                    mq.cmdf('/tell %s Queued %d buff(s)! You are #%d in line (%d ahead). Mana is low (%d%% < %d%%) - meditating before buffing.', cleanSender, #requestedGems, lineNum, totalAhead, pctMana, ctrl.minManaPct)
                else
                    mq.cmdf('/tell %s Queued %d buff(s)! You are #%d in line (%d ahead). Please stand by!', cleanSender, #requestedGems, lineNum, totalAhead)
                end
            else
                if pctMana < ctrl.minManaPct then
                    mq.cmdf('/tell %s Queued %d buff(s)! You are #1 in line. Mana is low (%d%% < %d%%) - meditating for a moment before buffing.', cleanSender, #requestedGems, pctMana, ctrl.minManaPct)
                elseif #requestedGems == 1 then
                    mq.cmdf('/tell %s Stand by, casting %s! (You are #1 in line)', cleanSender, requestedGems[1].name)
                else
                    mq.cmdf('/tell %s Stand by, preparing to cast %d selected buffs! (You are #1 in line)', cleanSender, #requestedGems)
                end
            end
        end)
    else
        -- If requester sent a tell that wasn't a choice, send the numbered menu
        runtime.pendingOffers[cleanSender] = { timestamp = now, spawnID = spawn.ID(), gems = currentGems }
        logMsg(string.format("Sent numbered buff menu to '%s'.", cleanSender))
        sendMenuTells(cleanSender, currentGems)
    end
end

-- ============================================================================
-- Interactive Hail Event Handler
-- ============================================================================
local lastHailTimes = {}
local lastGlobalHailTime = 0

local function onHailReceived(line, sender, targetName)
    if not ctrl.enabled then return end
    if not sender or sender == '' then return end

    local cleanSender = tostring(sender):gsub("%b[]", ""):gsub("%b()", ""):match("([%a%d]+)")
    if not cleanSender or cleanSender == '' then
        cleanSender = tostring(sender):match("([%a%d]+)")
    end
    if not cleanSender or cleanSender == '' then return end
    if cleanSender:lower() == 'you' then return end

    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    if not myName or myName == '' then return end
    if cleanSender:lower() == myName:lower() then return end

    -- If target was specified, verify it was directed at this buffbot
    if targetName and targetName ~= '' then
        local cleanTarget = tostring(targetName):gsub("%b[]", ""):gsub("%b()", ""):match("([%a%d]+)")
        if cleanTarget and cleanTarget:lower() ~= myName:lower() then
            return
        end
    else
        -- Untargeted hail: only reply if requester is nearby
        local dist = 9999
        pcall(function()
            local sp = mq.TLO.Spawn(string.format('pc =%s', cleanSender))
            if sp() then dist = sp.Distance() or 9999 end
        end)
        if dist > 35 then return end
    end

    local now = os.time()
    local lastHail = lastHailTimes[cleanSender:lower()] or 0
    if (now - lastHail) < 3 or (now - lastGlobalHailTime) < 2 then
        return -- Rate limit 3 seconds per player, 2 seconds globally to avoid spam
    end
    lastHailTimes[cleanSender:lower()] = now
    lastGlobalHailTime = now

    logMsg(string.format("Hail from '%s' received. Replying in /say.", cleanSender))
    pcall(function()
        mq.cmdf('/say %s, send tell to me to receive buffs!', cleanSender)
    end)
end

-- Register tell and hail events
mq.event('BuffbotTell1', '#*##1# tells you, \'#2#\'', onTellReceived)
mq.event('BuffbotTell2', '#*##1# tells you, "#2#"', onTellReceived)
mq.event('BuffbotTell3', '#*##1# tells you, #2#', onTellReceived)
mq.event('BuffbotHail1', '#*##1# says, \'Hail, #2#\'', onHailReceived)
mq.event('BuffbotHail2', '#*##1# says, "#2#"', onHailReceived)
mq.event('BuffbotHail3', '#*##1# says, \'Hail, #2#!\'', onHailReceived)
mq.event('BuffbotHail4', '#*##1# says, "#2#!"', onHailReceived)
mq.event('BuffbotHail5', '#*##1# says, \'Hail, #2#.\'', onHailReceived)
mq.event('BuffbotHail6', '#*##1# says, "#2#."', onHailReceived)
mq.event('BuffbotHailPlain1', '#*##1# says, \'Hail\'', function(line, sender) onHailReceived(line, sender, nil) end)
mq.event('BuffbotHailPlain2', '#*##1# says, \'Hail!\'', function(line, sender) onHailReceived(line, sender, nil) end)
mq.event('BuffbotHailPlain3', '#*##1# says, "Hail"', function(line, sender) onHailReceived(line, sender, nil) end)
mq.event('BuffbotHailPlain4', '#*##1# says, "Hail!"', function(line, sender) onHailReceived(line, sender, nil) end)

-- ============================================================================
-- Target Acquisition & Verification Helper
-- ============================================================================
local function acquireTarget(targetID, targetName)
    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    local isSelf = myName and (targetName:lower() == myName:lower())

    if isSelf then
        pcall(function() mq.cmdf('/target id %d', mq.TLO.Me.ID() or 0) end)
        mq.delay(200, function() return (mq.TLO.Target.ID() or 0) == (mq.TLO.Me.ID() or 0) end)
        return true
    end

    -- Try targeting by spawn ID first
    if targetID and targetID > 0 then
        pcall(function() mq.cmdf('/target id %d', targetID) end)
        mq.delay(250, function() return (mq.TLO.Target.ID() or 0) == targetID end)
    end

    -- Fallback: Target by PC name if ID targeting failed or was lost
    local currentId = 0
    pcall(function() currentId = mq.TLO.Target.ID() or 0 end)
    if currentId ~= targetID and targetName and targetName ~= '' then
        pcall(function() mq.cmdf('/target pc =%s', targetName) end)
        mq.delay(250, function() return (mq.TLO.Target.CleanName() or ''):lower() == targetName:lower() end)
        if (mq.TLO.Target.CleanName() or ''):lower() ~= targetName:lower() then
            pcall(function() mq.cmdf('/target "%s"', targetName) end)
            mq.delay(250, function() return (mq.TLO.Target.CleanName() or ''):lower() == targetName:lower() end)
        end
    end

    -- Verify target is valid, alive, and matches requester
    local valid = false
    pcall(function()
        local tid = mq.TLO.Target.ID() or 0
        local tName = mq.TLO.Target.CleanName() or ''
        valid = tid > 0 and (tName:lower() == targetName:lower() or (targetID > 0 and tid == targetID)) and
            not mq.TLO.Target.Dead()
    end)
    return valid
end

-- ============================================================================
-- Spell Cooldown & Recovery Helpers
-- ============================================================================
local function isSpellReady(gemNum, spellName)
    local ready = false
    pcall(function()
        if gemNum and gemNum > 0 then
            ready = mq.TLO.Me.SpellReady(gemNum)() or false
        end
        if not ready and spellName and spellName ~= '' then
            ready = mq.TLO.Me.SpellReady(spellName)() or false
        end
    end)
    return ready
end

local function waitForSpellReady(gemNum, spellName, maxWaitSec)
    maxWaitSec = maxWaitSec or 30
    local start = os.time()
    while not isSpellReady(gemNum, spellName) and ctrl.enabled do
        mq.doevents()
        mq.delay(100)
        if (os.time() - start) >= maxWaitSec then
            break
        end
    end
    return isSpellReady(gemNum, spellName)
end

-- ============================================================================
-- Buff Casting Loop
-- ============================================================================
local function processBuffQueue()
    if #runtime.activeQueue == 0 then
        if runtime.state ~= 'STOPPED' and runtime.state ~= 'MEDDING' then
            runtime.state = 'IDLE'
        end
        return
    end

    local request = table.remove(runtime.activeQueue, 1)
    local targetName = request.sender
    local targetID = request.spawnID
    local gemsToCast = request.gems or {}

    if #gemsToCast == 0 then
        runtime.state = 'IDLE'
        return
    end

    runtime.state = 'CASTING'
    runtime.currentRequester = targetName

    local spellSummaryList = {}
    for _, sp in ipairs(gemsToCast) do table.insert(spellSummaryList, string.format("[%d] %s", sp.gem, sp.name)) end
    logMsg(string.format("Buffing '%s' with %d spell(s): %s", targetName, #gemsToCast,
        table.concat(spellSummaryList, ", ")))
    print(string.format('\ag[Triune Buffbot]\ax Casting %d buff(s) on \aw%s\ax: %s', #gemsToCast, targetName,
        table.concat(spellSummaryList, ", ")))

    -- Check Mana % before starting sequence
    local pctMana = getMyPctMana()
    if pctMana < ctrl.minManaPct then
        logMsg(string.format("Mana low (%d%% < %d%%). Meditating before buffing '%s'...", pctMana, ctrl.minManaPct, targetName), true, false)
        pcall(function()
            mq.cmdf('/tell %s Mana is low (%d%%). Meditating until %d%% before buffing you, please stand by!', targetName, pctMana, ctrl.minManaPct)
        end)
        local isSit = false
        pcall(function() isSit = mq.TLO.Me.Sitting() or false end)
        if not isSit then
            pcall(function() mq.cmd('/sit') end)
        end
        while pctMana < ctrl.minManaPct and ctrl.enabled do
            mq.doevents()
            mq.delay(500)
            pctMana = getMyPctMana()
        end
    end

    -- Initial target lock
    local targetValid = acquireTarget(targetID, targetName)
    if not targetValid then
        logMsg(string.format("Target '%s' lost or unavailable in zone. Aborting buff sequence.", targetName), true, false)
        runtime.currentRequester = nil
        runtime.state = 'IDLE'
        return
    end

    for _, spellInfo in ipairs(gemsToCast) do
        if not ctrl.enabled then break end
        mq.doevents()

        local gemNum = spellInfo.gem
        local expectedName = spellInfo.name

        -- Re-verify gem slot index by spell name in case spell bar changed
        local currentGemSpell = nil
        pcall(function() currentGemSpell = mq.TLO.Me.Gem(gemNum).Name() end)
        if currentGemSpell ~= expectedName then
            pcall(function() gemNum = mq.TLO.Me.Gem(expectedName)() end)
        end

        if gemNum and gemNum > 0 then
            -- Re-verify and enforce target lock on the requester before each cast
            if not acquireTarget(targetID, targetName) then
                logMsg(string.format("Target '%s' lost during casting. Aborting remaining buffs.", targetName), true,
                    false)
                break
            end

            -- Face the requester
            pcall(function() mq.cmd('/face fast') end)
            mq.delay(100)
            mq.doevents()

            -- Ensure standing before cast
            local isSitOrDuck = false
            pcall(function() isSitOrDuck = mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() end)
            if isSitOrDuck then
                mq.cmd('/stand')
                mq.delay(200)
            end

            -- Verify spell has recovered from cooldown before attempting cast
            if not isSpellReady(gemNum, expectedName) then
                logMsg(string.format("Waiting for [%s] (Gem %d) to recover from cooldown...", expectedName, gemNum))
                waitForSpellReady(gemNum, expectedName, 30)
            end

            if isSpellReady(gemNum, expectedName) then
                -- Final pre-cast target lock & LoS facing
                acquireTarget(targetID, targetName)
                pcall(function() mq.cmd('/face fast') end)
                mq.delay(100)
                mq.doevents()

                -- Cast the spell on the requester
                logMsg(string.format("Casting [%s] on %s (Gem %d)", expectedName, targetName, gemNum))
                pcall(function() mq.cmdf('/cast %d', gemNum) end)
                mq.delay(300)
                mq.doevents()

                -- Wait for casting to complete while processing incoming tells
                local isCasting = true
                local attempts = 0
                while isCasting and attempts < 150 do
                    mq.doevents()
                    pcall(function() isCasting = mq.TLO.Me.Casting() ~= nil end)
                    if isCasting then
                        mq.delay(100)
                        attempts = attempts + 1
                    end
                end

                -- Recovery delay between casts while servicing events
                for _ = 1, 8 do
                    mq.doevents()
                    mq.delay(100)
                end
            else
                logMsg(string.format("Spell [%s] (Gem %d) timed out waiting for cooldown recovery. Skipping.", expectedName, gemNum), true, false)
            end
        end
    end

    -- Send Completion Tell to Requester
    logMsg(string.format("Completed buffs for '%s'. Sending completion tell.", targetName))
    pcall(function()
        mq.cmdf('/tell %s %s', targetName, ctrl.completionMsg)
    end)

    -- Set Cooldown
    runtime.cooldowns[targetName] = os.time()
    runtime.currentRequester = nil

    -- Auto-meditate if mana is not at 100%
    local endMana = getMyPctMana()
    if ctrl.autoMed and endMana < 100 then
        local isSit = false
        pcall(function() isSit = mq.TLO.Me.Sitting() or false end)
        if not isSit then
            pcall(function() mq.cmd('/sit') end)
            mq.delay(200)
        end
        runtime.state = 'MEDDING'
        logMsg(string.format("Buffs completed. Auto-meditating (%d%% / 100%%)...", endMana))
    else
        runtime.state = 'IDLE'
    end
end

-- ============================================================================
-- ImGui UI Rendering
-- ============================================================================
local function drawControlTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Buffbot Control Surface")
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4],
        "Listens for /tells, replies with numbered spell options, and casts choices.")
    ImGui.Separator()

    -- Status Indicator
    if runtime.state == 'IDLE' then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Status: LISTENING FOR TELLS")
    elseif runtime.state == 'CASTING' then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4],
            string.format("Status: BUFFING %s...", runtime.currentRequester or ''))
    elseif runtime.state == 'MEDDING' then
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4],
            string.format("Status: MEDITATING (%d%% / 100%%)", getMyPctMana()))
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format("Status: %s", runtime.state))
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Active Memorized Buff Spells (Tell Menu)")

    local gems = getAvailableGems()
    if #gems == 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "No spells currently memorized on your spell bar!")
    else
        for idx, g in ipairs(gems) do
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("  [%d]", idx))
            ImGui.SameLine()
            ImGui.Text(string.format("%s (Gem %d)", g.name, g.gem))
        end
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "  [all]")
        ImGui.SameLine()
        ImGui.Text("Cast All Memorized Buffs")
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Configuration Options")

    local autoMedVal, autoMedChanged = ImGui.Checkbox("Auto Meditate to 100% Mana", ctrl.autoMed)
    if autoMedChanged then
        ctrl.autoMed = autoMedVal
        saveConfig(true)
    end

    local rangeVal, rangeChanged = ImGui.SliderInt("Max Requester Range", ctrl.maxRange, 20, 300)
    if rangeChanged then
        ctrl.maxRange = rangeVal; saveConfig(true)
    end

    local timeoutVal, timeoutChanged = ImGui.SliderInt("Offer Expiration (sec)", ctrl.timeoutSec, 10, 120)
    if timeoutChanged then
        ctrl.timeoutSec = timeoutVal; saveConfig(true)
    end

    local cdVal, cdChanged = ImGui.SliderInt("Player Cooldown (sec)", ctrl.cooldownSec, 10, 300)
    if cdChanged then
        ctrl.cooldownSec = cdVal; saveConfig(true)
    end

    local manaVal, manaChanged = ImGui.SliderInt("Min Mana % Threshold", ctrl.minManaPct, 5, 50)
    if manaChanged then
        ctrl.minManaPct = manaVal; saveConfig(true)
    end

    ImGui.Spacing()
    ImGui.Text("Completion Tell (Sent after all selected buffs cast):")
    local newComp, compChanged = ImGui.InputText("##completionMsg", ctrl.completionMsg, 256)
    if compChanged then
        ctrl.completionMsg = newComp; saveConfig(true)
    end
end

local function drawActivityTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Active Queue & Event Log")
    ImGui.Separator()

    ImGui.Text(string.format("Active Request Queue: %d pending", #runtime.activeQueue))
    if #runtime.activeQueue > 0 then
        if ImGui.BeginTable("##queueTable", 3, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn("Requester", ImGuiTableColumnFlags.WidthFixed, 130)
            ImGui.TableSetupColumn("Spawn ID", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableSetupColumn("Spells", ImGuiTableColumnFlags.WidthStretch, 200)
            ImGui.TableHeadersRow()

            for _, req in ipairs(runtime.activeQueue) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                ImGui.Text(req.sender)
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(tostring(req.spawnID))
                ImGui.TableSetColumnIndex(2)
                local names = {}
                for _, sp in ipairs(req.gems or {}) do table.insert(names, sp.name) end
                ImGui.Text(#names > 0 and table.concat(names, ", ") or "(None)")
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
    ctrl.enabled = true
    runtime.state = 'IDLE'
    loadConfig()
    logMsg("Triune Buffbot script initialized and active.")
    print('\ag[Triune Buffbot]\ax v' .. VERSION .. ' initialized and \agACTIVE\ax. Listening for tells...')
end

init()

while runtime.openGUI do
    mq.doevents()

    -- Clean up expired pending offers
    local now = os.time()
    for sender, offer in pairs(runtime.pendingOffers) do
        if (now - offer.timestamp) > ctrl.timeoutSec then
            runtime.pendingOffers[sender] = nil
            logMsg(string.format("Offer for '%s' expired.", sender))
        end
    end

    -- Auto-meditate idle upkeep
    if ctrl.enabled and ctrl.autoMed and #runtime.activeQueue == 0 and runtime.state ~= 'CASTING' and runtime.state ~= 'STOPPED' then
        local pctMana = getMyPctMana()
        if pctMana < 100 then
            local isSitting = false
            pcall(function() isSitting = mq.TLO.Me.Sitting() or false end)
            local isMoving = false
            pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
            if not isSitting and not isMoving then
                pcall(function() mq.cmd('/sit') end)
            end
            runtime.state = 'MEDDING'
        elseif pctMana >= 100 and runtime.state == 'MEDDING' then
            runtime.state = 'IDLE'
        end
    end

    -- Process queue if buffbot enabled
    if ctrl.enabled and #runtime.activeQueue > 0 and runtime.state ~= 'STOPPED' then
        processBuffQueue()
    end

    mq.delay(100)
end
