---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/buffbot.lua — Triune Buffbot Plugin
-- ============================================================================
-- In-process replacement for the old standalone triune_buffbot.lua script (v1.7).
-- Interactive tell-menu buffbot: replies to /tells with the memorized spell
-- gems, casts the requested buffs on the requester and/or their pets, with
-- guild priority / guild-only policies, ignore list, low-mana meditation,
-- anti-AFK upkeep, and per-character config (triune_buffbot_config.lua).
--
-- The casting workflow is sequential (target, wait for readiness, cast, wait
-- for the cast bar) so it runs inside the plugin fiber and waits through the
-- core's cooperative `delay`, which yields to the main loop instead of
-- blocking it. Incoming tells are pumped by the core's mq.doevents.
--
-- The station is OFF until switched on (window button or /ac buffbot on) -
-- the standalone script was implicitly "on" while it ran. While a buff job
-- is being cast the plugin holds the combat loop (wantsCombatHold).
-- Window visibility is ctrl.show_buffbot (/ac buffbot, Settings ->
-- External Tools, and the Window Layout manager flip it).
-- ============================================================================

local plugin = {
    id                 = 'buffbot',
    name               = 'Buffbot Station',
    version            = '1.7.0',
    author             = 'Triune',
    description        = 'Tell-driven buffbot: numbered spell menu, pet buffing, guild priority, ignore list, auto-med and anti-AFK.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = true,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Buffbot', tooltip = 'Toggles the Buffbot Station window (buffbot plugin).', flag = 'show_buffbot', desc = 'Tell-driven buffbot controls, ignore list & activity log', headerButton = false, order = 120 },
}

local core = nil
local ctrl, ImGui, mq = nil, nil, nil

local VERSION      = '1.7'

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

-- Cooperative wait (yields the plugin fiber; see pm.delay in triune.lua)
local function delay(ms, cond)
    return core.delay(ms, cond)
end

local function configPath()
    return (mq.configDir or 'config') .. '/triune_buffbot_config.lua'
end

local GOLD         = { 1.00, 0.70, 0.54, 1 }
local ARC          = { 0.30, 0.70, 1.00, 1 }
local MUTED        = { 0.49, 0.56, 0.65, 1 }
local GOOD         = { 0.37, 0.88, 0.64, 1 }
local WARN         = { 1.00, 0.72, 0.30, 1 }
local ERR          = { 0.95, 0.35, 0.35, 1 }

local cfg = {
    enabled                = true,
    allowPets              = true,
    autoMed                = true,
    antiAfk                = true,
    guildMode              = 'Off', -- 'Off', 'Guild Priority', 'Guild Only'
    guildOnly              = false, -- backward compatibility sync
    maxRange               = 100,
    timeoutSec             = 30,
    cooldownSec            = 3,
    tellDelayMs            = 2500,
    minManaPct             = 15,
    completionMsg          = "All buffs cast! Enjoy!",
    banMsg                 = "You are banned from getting buffs.",
    guildOnlyMsg           = "Buffing is currently restricted to guild members only.",
    guildPriorityPauseMsg  = "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!",
    guildPriorityResumeMsg = "Resuming your remaining buffs now! Thank you for waiting.",
    allowLowLevel          = {}, -- [spellName] = true/false (true = can cast on level <= 46 players)
    ignoreList             = {}  -- array of ignored/banned player names
}

local rt = {
    state              = 'IDLE', -- STOPPED, IDLE, CASTING, MEDDING
    pendingOffers      = {},     -- sender -> { timestamp = os.time(), spawnID = id, gems = list }
    cooldowns          = {},     -- sender -> timestamp
    activeQueue        = {},     -- array of { sender = name, targetName = name, targetID = id, isPet = bool, petName = str, gems = list, remainingGems = list, isGuild = bool, isResumed = bool }
    outgoingTells      = {},     -- array of { target = name, msg = text }
    lastTellSendTime   = 0,
    lastAntiAfkTime    = os.time(),
    lastSitAttemptTime = 0,
    lastTablePruneTime = os.time(),
    currentRequester   = nil,
    currentJob         = nil,    -- currently active request being cast
    preemptRequested   = false,  -- flag: set to true when guild priority interrupts non-guild casting
    currentSpellsText  = "",
    newIgnorePlayerName= "",
    log                = {},
    pendingAction      = nil -- queued thread-safe UI actions
}

local function logMsg(msg, isWarn, isErr)
    local prefix = os.date("[%H:%M:%S] ")
    table.insert(rt.log, 1, { time = prefix, msg = msg, isWarn = isWarn, isErr = isErr })
    if #rt.log > 100 then table.remove(rt.log) end
end

local function queueTell(target, msg)
    if not target or target == '' or not msg or msg == '' then return end
    table.insert(rt.outgoingTells, { target = target, msg = msg })
end

local function processOutgoingTells()
    if #rt.outgoingTells == 0 then return end
    local nowMs = 0
    pcall(function() nowMs = mq.gettime() end)
    if nowMs == 0 then nowMs = os.time() * 1000 end

    local delayMs = cfg.tellDelayMs or 2500
    if (nowMs - rt.lastTellSendTime) < delayMs then return end

    local out = table.remove(rt.outgoingTells, 1)
    if out and out.target and out.msg then
        pcall(function()
            mq.cmdf('/tell %s %s', out.target, out.msg)
        end)
        rt.lastTellSendTime = nowMs
    end
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
-- Spell Cooldown, Target Verification & Gem Discovery Helpers
-- ============================================================================
local function getSpellCooldownSec(gemNum, spellName)
    local sec = 0
    pcall(function()
        if gemNum and gemNum > 0 then
            local gt = mq.TLO.Me.GemTimer(gemNum)
            if gt and gt() then
                local ts = gt.TotalSeconds()
                if ts and ts > 0 then
                    sec = ts
                else
                    local ms = gt() or 0
                    if ms > 0 then sec = math.ceil(ms / 1000) end
                end
            end
        end
        if sec == 0 and spellName and spellName ~= '' then
            local gt = mq.TLO.Me.GemTimer(spellName)
            if gt and gt() then
                local ts = gt.TotalSeconds()
                if ts and ts > 0 then
                    sec = ts
                else
                    local ms = gt() or 0
                    if ms > 0 then sec = math.ceil(ms / 1000) end
                end
            end
        end
    end)
    return sec
end

local function canCastOnPlayer(spellName, playerLevel)
    if not playerLevel or playerLevel > 46 then
        return true
    end
    -- Target is level 46 or below: allow if user checked the box for this spell
    if cfg.allowLowLevel and cfg.allowLowLevel[spellName] == true then
        return true
    end
    return false
end

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
            local allowLow = (cfg.allowLowLevel and cfg.allowLowLevel[name] == true)
            local cdRemaining = getSpellCooldownSec(gemNum, name)
            table.insert(list, {
                gem           = gemNum,
                name          = name,
                allowLowLevel = allowLow,
                cooldownSec   = cdRemaining
            })
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

-- Resolved once per onInit and reused until onDestroy: after a character swap
-- the core restarts plugins (onDestroy -> onInit) while the TLOs already report
-- the new character, so saving under a freshly-computed key would file the old
-- character's settings under the new name.
local cachedCharKey = nil
local function charKey()
    if cachedCharKey then return cachedCharKey end
    local myName, myServer = nil, nil
    pcall(function()
        myName = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    cachedCharKey = (myServer or 'default') .. '_' .. (myName or 'default')
    return cachedCharKey
end

local function saveConfig(silent)
    local key = charKey()

    local allData = {}
    local fn = loadfile(configPath())
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == 'table' then allData = t end
    end

    allData[key] = {
        enabled                = cfg.enabled,
        allowPets              = cfg.allowPets,
        autoMed                = cfg.autoMed,
        antiAfk                = cfg.antiAfk,
        guildMode              = cfg.guildMode or 'Off',
        guildOnly              = (cfg.guildMode == 'Guild Only'),
        maxRange               = cfg.maxRange,
        timeoutSec             = cfg.timeoutSec,
        cooldownSec            = cfg.cooldownSec,
        tellDelayMs            = cfg.tellDelayMs,
        minManaPct             = cfg.minManaPct,
        completionMsg          = cfg.completionMsg,
        banMsg                 = cfg.banMsg,
        guildOnlyMsg           = cfg.guildOnlyMsg,
        guildPriorityPauseMsg  = cfg.guildPriorityPauseMsg,
        guildPriorityResumeMsg = cfg.guildPriorityResumeMsg,
        allowLowLevel          = cfg.allowLowLevel or {},
        ignoreList             = cfg.ignoreList or {}
    }

    local f = io.open(configPath(), 'w')
    if f then
        f:write("return " .. serializeValue(allData) .. "\n")
        f:close()
        if not silent then logMsg("Saved buffbot configuration.") end
    end
end

local function loadConfig()
    local key = charKey()

    local fn = loadfile(configPath())
    if not fn then return end
    local ok, allData = pcall(fn)
    if not ok or type(allData) ~= 'table' then return end

    local charData = allData[key] or allData['default']
    if charData and type(charData) == 'table' then
        if charData.enabled ~= nil then cfg.enabled = charData.enabled end
        if charData.allowPets ~= nil then cfg.allowPets = charData.allowPets end
        if charData.autoMed ~= nil then cfg.autoMed = charData.autoMed end
        if charData.antiAfk ~= nil then cfg.antiAfk = charData.antiAfk end
        if charData.guildMode ~= nil then
            cfg.guildMode = charData.guildMode
        elseif charData.guildOnly ~= nil then
            cfg.guildMode = charData.guildOnly and 'Guild Only' or 'Off'
        else
            cfg.guildMode = 'Off'
        end
        cfg.guildOnly = (cfg.guildMode == 'Guild Only')
        if charData.maxRange then cfg.maxRange = charData.maxRange end
        if charData.timeoutSec then cfg.timeoutSec = charData.timeoutSec end
        if charData.cooldownSec then cfg.cooldownSec = charData.cooldownSec else cfg.cooldownSec = 3 end
        if charData.tellDelayMs then cfg.tellDelayMs = charData.tellDelayMs else cfg.tellDelayMs = 2500 end
        if charData.minManaPct then cfg.minManaPct = charData.minManaPct end
        if charData.completionMsg then cfg.completionMsg = charData.completionMsg end
        if charData.banMsg then cfg.banMsg = charData.banMsg else cfg.banMsg = "You are banned from getting buffs." end
        if charData.guildOnlyMsg then cfg.guildOnlyMsg = charData.guildOnlyMsg else cfg.guildOnlyMsg = "Buffing is currently restricted to guild members only." end
        if charData.guildPriorityPauseMsg then
            cfg.guildPriorityPauseMsg = charData.guildPriorityPauseMsg
        else
            cfg.guildPriorityPauseMsg = "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!"
        end
        if charData.guildPriorityResumeMsg then
            cfg.guildPriorityResumeMsg = charData.guildPriorityResumeMsg
        else
            cfg.guildPriorityResumeMsg = "Resuming your remaining buffs now! Thank you for waiting."
        end
        if charData.allowLowLevel and type(charData.allowLowLevel) == 'table' then
            cfg.allowLowLevel = charData.allowLowLevel
        else
            cfg.allowLowLevel = {}
        end
        if charData.ignoreList and type(charData.ignoreList) == 'table' then
            cfg.ignoreList = charData.ignoreList
        else
            cfg.ignoreList = {}
        end
        logMsg("Loaded saved buffbot configuration for " .. key .. ".")
    end
end

-- ============================================================================
-- Player Ignore / Ban List Helpers
-- ============================================================================
local function isPlayerIgnored(name)
    if not name or name == '' or not cfg.ignoreList then return false end
    local lower = tostring(name):lower():gsub("^%s*(.-)%s*$", "%1")
    if lower == '' then return false end
    for k, v in pairs(cfg.ignoreList) do
        if type(v) == 'string' and v:lower():gsub("^%s*(.-)%s*$", "%1") == lower then
            return true
        end
        if type(k) == 'string' and k:lower():gsub("^%s*(.-)%s*$", "%1") == lower and v == true then
            return true
        end
    end
    return false
end

local function addIgnoredPlayer(name)
    if not name or name == '' then return false end
    local clean = tostring(name):gsub("^%s*(.-)%s*$", "%1")
    if clean == '' then return false end
    if isPlayerIgnored(clean) then return false end
    if not cfg.ignoreList or type(cfg.ignoreList) ~= 'table' then
        cfg.ignoreList = {}
    end
    table.insert(cfg.ignoreList, clean)
    saveConfig(true)
    return true
end

local function removeIgnoredPlayer(name)
    if not name or not cfg.ignoreList then return false end
    local lower = tostring(name):lower():gsub("^%s*(.-)%s*$", "%1")
    if lower == '' then return false end
    local found = false
    for i = #cfg.ignoreList, 1, -1 do
        local v = cfg.ignoreList[i]
        if type(v) == 'string' and v:lower():gsub("^%s*(.-)%s*$", "%1") == lower then
            table.remove(cfg.ignoreList, i)
            found = true
        end
    end
    for k, _ in pairs(cfg.ignoreList) do
        if type(k) == 'string' and k:lower():gsub("^%s*(.-)%s*$", "%1") == lower then
            cfg.ignoreList[k] = nil
            found = true
        end
    end
    if found then
        saveConfig(true)
    end
    return found
end

-- ============================================================================
-- Guild Verification & Priority Helpers
-- ============================================================================
local function getMyGuild()
    local myGuild = nil
    pcall(function()
        local g = mq.TLO.Me.Guild
        if g and g() and g() ~= '' then
            myGuild = g()
        end
    end)
    return myGuild
end

local function getSpawnGuild(spawn)
    if not spawn or not spawn() then return nil end
    local gName = nil
    pcall(function()
        local g = spawn.Guild
        if g and g() and g() ~= '' then
            gName = g()
        end
    end)
    return gName
end

local function isSameGuild(spawn)
    local myGuild = getMyGuild()
    if not myGuild or myGuild == '' then return false end
    local theirGuild = getSpawnGuild(spawn)
    if not theirGuild or theirGuild == '' then return false end
    return myGuild:lower() == theirGuild:lower()
end

local function isPlayerSameGuild(nameOrSpawn)
    if not nameOrSpawn then return false end
    if type(nameOrSpawn) == 'string' then
        local sp = nil
        pcall(function() sp = mq.TLO.Spawn(string.format('pc =%s', nameOrSpawn)) end)
        local valid = false
        pcall(function()
            if sp and sp() and (sp.ID() or 0) > 0 then
                valid = true
            end
        end)
        if not valid then
            pcall(function() sp = mq.TLO.Spawn(string.format('pc %s', nameOrSpawn)) end)
        end
        return isSameGuild(sp)
    else
        return isSameGuild(nameOrSpawn)
    end
end

local function enqueueBuffJob(job)
    if not job then return end
    if cfg.guildMode == 'Guild Priority' and job.isGuild then
        -- Find position after the last guild job in the active queue
        local insertIdx = 1
        for i = 1, #rt.activeQueue do
            if rt.activeQueue[i].isGuild then
                insertIdx = i + 1
            else
                break
            end
        end
        table.insert(rt.activeQueue, insertIdx, job)
        return insertIdx
    else
        table.insert(rt.activeQueue, job)
        return #rt.activeQueue
    end
end

local function requeuePreemptedJob(job)
    if not job then return end
    -- Insert at the first non-guild position (right after all queued guild jobs)
    local insertIdx = 1
    for i = 1, #rt.activeQueue do
        if rt.activeQueue[i].isGuild then
            insertIdx = i + 1
        else
            break
        end
    end
    table.insert(rt.activeQueue, insertIdx, job)
    return insertIdx
end

local function getQueuePosition(senderName)
    local totalAhead = 0
    if not senderName or senderName == '' then return 0 end
    local lower = senderName:lower()

    -- Check if currently active job is ahead
    if rt.currentJob and rt.currentJob.sender and rt.currentJob.sender:lower() ~= lower then
        -- If current job is non-guild, and sender is a guild member under Guild Priority,
        -- the current job is immediately preempted, so it's NOT ahead!
        local currentIsPreempted = (cfg.guildMode == 'Guild Priority' and isPlayerSameGuild(senderName) and not rt.currentJob.isGuild)
        if not currentIsPreempted then
            totalAhead = totalAhead + 1
        end
    end

    -- Count jobs ahead of the first job for senderName in activeQueue
    for _, job in ipairs(rt.activeQueue) do
        if job.sender:lower() == lower then
            break
        else
            totalAhead = totalAhead + 1
        end
    end

    return totalAhead
end

-- ============================================================================
-- Tell Menu & Choice Parsing
-- ============================================================================
local function sendMenuTells(target, gemList, requesterLevel)
    if not target or target == '' then return end

    -- Prune any pending un-sent tells already queued for this target
    for idx = #rt.outgoingTells, 1, -1 do
        if rt.outgoingTells[idx].target:lower() == target:lower() then
            table.remove(rt.outgoingTells, idx)
        end
    end

    if not gemList or #gemList == 0 then
        queueTell(target, 'I currently have no buff spells memorized.')
        return
    end

    local items = {}
    local isLowLevel = requesterLevel and requesterLevel > 0 and requesterLevel <= 46
    for idx, item in ipairs(gemList) do
        local tag = ""
        if isLowLevel and not item.allowLowLevel then
            tag = " (47+/Pet)"
        end
        if item.cooldownSec and item.cooldownSec > 30 then
            local cdText = (item.cooldownSec >= 60) and string.format("CD %dm", math.ceil(item.cooldownSec / 60)) or string.format("CD %ds", item.cooldownSec)
            tag = (tag ~= "") and (tag .. ", " .. cdText) or (" (" .. cdText .. ")")
        end
        table.insert(items, string.format("[%d] %s%s", idx, item.name, tag))
    end

    -- Pack items into clean chunks of <= 100 characters so tell count is minimized
    local lines = {}
    local currentLine = ""

    for _, item in ipairs(items) do
        if currentLine == "" then
            currentLine = item
        else
            if #(currentLine .. ", " .. item) <= 100 then
                currentLine = currentLine .. ", " .. item
            else
                table.insert(lines, currentLine)
                currentLine = item
            end
        end
    end
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end

    -- Queue chunked tells for spaced dispatch
    for i, line in ipairs(lines) do
        if #lines == 1 then
            queueTell(target, string.format("Buffs: %s", line))
        else
            queueTell(target, string.format("Buffs (%d/%d): %s", i, #lines, line))
        end
    end
    queueTell(target, "Reply with numbers (e.g. 1 3). Add 'pet' for pet only (pet 1 3) or 'both' for you and your pet (both 1 3)!")
end

local function parseBuffRequest(msg, gemList)
    if not gemList or #gemList == 0 then return 'player', nil end

    local lowerMsg = tostring(msg):lower()

    -- Detect target mode keywords
    local mode = 'player'
    if lowerMsg:match("%f[%a]both%f[%A]") or lowerMsg:match("%f[%a]b%f[%A]") then
        mode = 'both'
    elseif lowerMsg:match("%f[%a]pet%f[%A]") or lowerMsg:match("%f[%a]p%f[%A]") or lowerMsg:match("%f[%a]pets%f[%A]") then
        mode = 'pet'
    end

    -- Check for specific numbers (e.g. '1', '2', '1 3', '1, 2', '1 2 3')
    local selected = {}
    local seen = {}
    for numStr in lowerMsg:gmatch("%d+") do
        local idx = tonumber(numStr)
        if idx and gemList[idx] and not seen[idx] then
            seen[idx] = true
            table.insert(selected, gemList[idx])
        end
    end

    if #selected > 0 then
        return mode, selected
    end

    return mode, nil
end

-- ============================================================================
-- Pet Discovery Helper (Supports up to 3 pets per character)
-- ============================================================================
local function getRequesterPets(requesterSpawn)
    local pets = {}
    if not requesterSpawn or not requesterSpawn() then return pets end

    local reqId = 0
    local reqName = ""
    pcall(function()
        reqId = requesterSpawn.ID() or 0
        reqName = requesterSpawn.CleanName() or ''
    end)
    if reqId <= 0 and reqName == '' then return pets end

    local seenPetIDs = {}

    -- 1. Check direct .Pet TLO property
    pcall(function()
        local p = requesterSpawn.Pet
        if p and p() and (p.ID() or 0) > 0 and not p.Dead() then
            local pid = p.ID()
            local pname = p.CleanName() or 'Pet'
            local pdist = p.Distance() or 9999
            if not seenPetIDs[pid] then
                seenPetIDs[pid] = true
                table.insert(pets, { id = pid, name = pname, distance = pdist })
            end
        end
    end)

    -- 2. Scan pet spawns within range to discover secondary and tertiary pets
    local count = 0
    local searchStr = string.format('pet radius %d', cfg.maxRange or 100)
    pcall(function() count = mq.TLO.SpawnCount(searchStr)() or 0 end)
    count = math.min(count, 15) -- Cap search to 15 nearby pets to prevent O(N^2) frame lag in hub zones
    for i = 1, count do
        local s = nil
        pcall(function() s = mq.TLO.NearestSpawn(i, searchStr) end)
        if s and s() and (s.ID() or 0) > 0 and not s.Dead() then
            local sid = s.ID()
            if not seenPetIDs[sid] then
                local isMine = false
                pcall(function()
                    local m = s.Master
                    if m and m() and ((m.ID() or 0) == reqId or (reqName ~= '' and (m.CleanName() or ''):lower() == reqName:lower())) then
                        isMine = true
                    end
                    if not isMine then
                        local o = s.Owner
                        if o and o() and ((o.ID() or 0) == reqId or (reqName ~= '' and (o.CleanName() or ''):lower() == reqName:lower())) then
                            isMine = true
                        end
                    end
                    if not isMine and reqName ~= '' then
                        local cname = s.CleanName() or ''
                        if cname:find(reqName .. "'s ", 1, true) or
                           cname:find(reqName .. "`s ", 1, true) or
                           cname:find('(Owner: ' .. reqName .. ')', 1, true) or
                           cname:find(reqName .. "s pet", 1, true) then
                            isMine = true
                        end
                    end
                end)

                if isMine then
                    seenPetIDs[sid] = true
                    local sname = s.CleanName() or 'Pet'
                    local sdist = s.Distance() or 9999
                    table.insert(pets, { id = sid, name = sname, distance = sdist })
                end
            end
        end
    end

    return pets
end

-- ============================================================================
-- Interactive Tell Event Handler
-- ============================================================================
local lastTellBySender = {} -- cleanSender -> { msg = str, time = ms }

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
    if not cfg.enabled then return end
    if not sender or sender == '' or not msg then return end

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

    -- Check if sender is in player ignore list
    if isPlayerIgnored(cleanSender) then
        local now = os.time()
        local cd = rt.cooldowns[cleanSender:lower()]
        if cd and (now - cd) < cfg.cooldownSec then
            return
        end
        rt.cooldowns[cleanSender:lower()] = now

        local banMsg = (cfg.banMsg and cfg.banMsg ~= '') and cfg.banMsg or "You are banned from getting buffs."
        queueTell(cleanSender, banMsg)
        logMsg(string.format("Blocked request from banned player '%s'. Sent ban notice.", cleanSender), true, false)
        print(string.format('\ay[Triune Buffbot]\ax Blocked tell from banned player \aw%s\ax: \ar"%s"\ax', cleanSender, banMsg))
        return
    end

    -- Clean quotes/whitespace from message
    local cleanMsg = tostring(msg):gsub("^['\"%s]+", ""):gsub("['\"%s]+$", "")
    if cleanMsg == '' then return end

    -- Deduplicate rapid identical tells from same sender (< 1000ms)
    local nowMs = 0
    pcall(function() nowMs = mq.gettime() end)
    if nowMs == 0 then nowMs = os.time() * 1000 end

    local prev = lastTellBySender[cleanSender:lower()]
    if prev and (nowMs - prev.time) < 1000 and prev.msg == cleanMsg then
        return -- Skip duplicate event trigger on same message
    end
    lastTellBySender[cleanSender:lower()] = { msg = cleanMsg, time = nowMs }

    -- Log detection to UI and MQ console
    logMsg(string.format("Incoming tell from %s: '%s'", cleanSender, cleanMsg))
    print(string.format('\ay[Triune Buffbot]\ax Incoming tell from \aw%s\ax: \ag"%s"\ax', cleanSender, cleanMsg))

    -- Check for Thank You / Gratitude
    if isThankYou(cleanMsg) then
        logMsg(string.format("Received thank-you tell from '%s'. Replying with 'You're welcome!'.", cleanSender))
        queueTell(cleanSender, "You're welcome!")
        return
    end

    -- Check 1-second rapid request delay (silent ignore to prevent tell spam)
    local now = os.time()
    local cd = rt.cooldowns[cleanSender:lower()]
    if cd and (now - cd) < cfg.cooldownSec then
        logMsg(string.format("Ignored rapid repeat request from '%s' (< %ds).", cleanSender, cfg.cooldownSec))
        return
    end
    rt.cooldowns[cleanSender:lower()] = now

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
        queueTell(cleanSender,
            string.format('Unable to locate you in this zone for buffing. My location is /loc %s. Please come closer!',
                myLocStr))
        logMsg(string.format("Unable to locate spawn for '%s' in zone (My Loc: %s).", cleanSender, myLocStr), true, false)
        return
    end

    -- Check Guild-Only restriction if enabled
    if cfg.guildMode == 'Guild Only' then
        if not isSameGuild(spawn) then
            local guildMsg = (cfg.guildOnlyMsg and cfg.guildOnlyMsg ~= '') and cfg.guildOnlyMsg or "Buffing is currently restricted to guild members only."
            queueTell(cleanSender, guildMsg)
            local myGuild = getMyGuild() or "Unguilded"
            local requesterGuild = getSpawnGuild(spawn) or "None"
            logMsg(string.format("Blocked request from non-guild player '%s' (Guild: '%s', Bot Guild: '%s'). Sent guild notice.", cleanSender, requesterGuild, myGuild), true, false)
            print(string.format('\ay[Triune Buffbot]\ax Blocked tell from non-guild player \aw%s\ax (Guild: %s, Bot: %s): \ar"%s"\ax', cleanSender, requesterGuild, myGuild, guildMsg))
            return
        end
    end

    local dist = 9999
    pcall(function() dist = spawn.Distance() or 9999 end)
    if dist > cfg.maxRange then
        queueTell(cleanSender,
            string.format('You are out of range for buffing (%.0f > %d). My location is /loc %s. Please come closer!',
                dist, cfg.maxRange, myLocStr))
        logMsg(
            string.format("Requester '%s' out of range (%.0f > %d). Sent /loc %s.", cleanSender, dist, cfg.maxRange,
                myLocStr), true, false)
        return
    end

    local currentGems = getAvailableGems()
    if #currentGems == 0 then
        queueTell(cleanSender, 'I currently have no buff spells memorized.')
        logMsg("No spells memorized on gem bar to offer.", true, false)
        return
    end

    -- Check if requester already has an active menu offer
    local pending = rt.pendingOffers[cleanSender]
    local gemListForReply = (pending and pending.gems and #pending.gems > 0) and pending.gems or currentGems

    local mode, requestedGems = parseBuffRequest(cleanMsg, gemListForReply)

    if requestedGems and #requestedGems > 0 then
        -- Requester made a valid spell selection
        rt.pendingOffers[cleanSender] = nil

        -- Remove any stale prior entries for this sender in queue
        for i = #rt.activeQueue, 1, -1 do
            if rt.activeQueue[i].sender:lower() == cleanSender:lower() then
                table.remove(rt.activeQueue, i)
            end
        end

        local requesterLevel = 1
        pcall(function() requesterLevel = spawn.Level() or 1 end)

        local currentTargetID = 0
        pcall(function() currentTargetID = spawn.ID() or 0 end)

        local pctMana = getMyPctMana()
        local isGuildMember = isSameGuild(spawn)

        if mode == 'pet' then
            if not cfg.allowPets then
                queueTell(cleanSender, 'Pet buffing is currently disabled on this buffbot.')
                logMsg(string.format("Pet buff request from '%s' rejected (pet buffing disabled).", cleanSender), true, false)
                return
            end

            local allPets = getRequesterPets(spawn)
            if #allPets == 0 then
                queueTell(cleanSender, 'You do not currently have any active summoned pets in this zone. Please summon your pet(s) and try again!')
                logMsg(string.format("Requester '%s' requested pet buffs, but no active pets were found.", cleanSender), true, false)
                return
            end

            local inRangePets = {}
            for _, p in ipairs(allPets) do
                if p.distance <= cfg.maxRange then
                    table.insert(inRangePets, p)
                end
            end

            if #inRangePets == 0 then
                queueTell(cleanSender, string.format('All of your pets (%d) are out of range for buffing (Max: %d). Please bring your pets closer!', #allPets, cfg.maxRange))
                logMsg(string.format("All %d pet(s) for '%s' are out of range (> %d).", #allPets, cleanSender, cfg.maxRange), true, false)
                return
            end

            local namesList = {}
            for _, sp in ipairs(requestedGems) do table.insert(namesList, string.format("[%d] %s", sp.gem, sp.name)) end
            local spellsText = table.concat(namesList, ", ")

            for _, pet in ipairs(inRangePets) do
                enqueueBuffJob({
                    sender     = cleanSender,
                    targetName = pet.name,
                    targetID   = pet.id,
                    isPet      = true,
                    petName    = pet.name,
                    gems       = requestedGems,
                    isGuild    = isGuildMember,
                    isResumed  = false,
                })
            end

            -- Check Guild Priority Preemption: if a non-guild player is currently being buffed
            if cfg.guildMode == 'Guild Priority' and isGuildMember then
                if rt.currentJob and not rt.currentJob.isGuild and not rt.preemptRequested then
                    rt.preemptRequested = true
                    pcall(function()
                        mq.cmd('/stopcast')
                        mq.cmd('/interrupt')
                    end)
                    local pauseMsg = (cfg.guildPriorityPauseMsg and cfg.guildPriorityPauseMsg ~= '')
                        and cfg.guildPriorityPauseMsg
                        or "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!"
                    queueTell(rt.currentJob.sender, pauseMsg)
                    logMsg(string.format("Preempting active buffs on non-guild player '%s' for guild member '%s'.", rt.currentJob.sender, cleanSender), true, false)
                    print(string.format('\ay[Triune Buffbot]\ax Preempting non-guild player \aw%s\ax for guild member \ag%s\ax...', rt.currentJob.sender, cleanSender))
                end
            end

            local totalAhead = getQueuePosition(cleanSender)
            local lineNum = totalAhead + 1

            local petNamesList = {}
            for _, p in ipairs(inRangePets) do table.insert(petNamesList, p.name) end
            local petNamesStr = table.concat(petNamesList, ", ")
            local petDesc = (#inRangePets == 1) and string.format("your pet (%s)", petNamesStr) or string.format("your %d pets (%s)", #inRangePets, petNamesStr)

            logMsg(string.format("Requester '%s' queued %d buff(s) for %s (%s, Line #%d): %s", cleanSender, #requestedGems, petDesc, isGuildMember and "Guild" or "Public", lineNum, spellsText))
            print(string.format('\ag[Triune Buffbot]\ax Queued %d buff(s) for \aw%s\ax (%s, %s) (Line #%d): %s', #requestedGems, cleanSender, petDesc, isGuildMember and "Guild" or "Public", lineNum, spellsText))

            if totalAhead > 0 then
                if pctMana < cfg.minManaPct then
                    queueTell(cleanSender, string.format('Queued %d buff(s) for %s! You are #%d in line (%d ahead). Mana is low (%d%% < %d%%) - meditating before buffing.', #requestedGems, petDesc, lineNum, totalAhead, pctMana, cfg.minManaPct))
                else
                    queueTell(cleanSender, string.format('Queued %d buff(s) for %s! You are #%d in line (%d ahead). Please stand by!', #requestedGems, petDesc, lineNum, totalAhead))
                end
            else
                if pctMana < cfg.minManaPct then
                    queueTell(cleanSender, string.format('Queued %d buff(s) for %s! You are #1 in line. Mana is low (%d%% < %d%%) - meditating for a moment before buffing.', #requestedGems, petDesc, pctMana, cfg.minManaPct))
                elseif isGuildMember and cfg.guildMode == 'Guild Priority' then
                    queueTell(cleanSender, string.format('Stand by, prioritizing your guild request! Preparing to cast %d buff(s) on %s! (You are #1 in line)', #requestedGems, petDesc))
                else
                    queueTell(cleanSender, string.format('Stand by, preparing to cast %d buff(s) on %s! (You are #1 in line)', #requestedGems, petDesc))
                end
            end

        elseif mode == 'both' then
            -- Validate level restrictions for player character (<= 46 check), while allowing all requested buffs for pet
            local playerGems = {}
            local skippedForPlayer = {}
            for _, sp in ipairs(requestedGems) do
                if not canCastOnPlayer(sp.name, requesterLevel) then
                    table.insert(skippedForPlayer, sp.name)
                else
                    table.insert(playerGems, sp)
                end
            end

            if #skippedForPlayer > 0 then
                local skippedListStr = table.concat(skippedForPlayer, ", ")
                queueTell(cleanSender, string.format("Note: Skipped %s for you (requires level 47+), but casting on your pet!", skippedListStr))
                logMsg(string.format("Skipped level-restricted buffs for player '%s' in 'both' mode (Lvl %d): %s", cleanSender, requesterLevel, skippedListStr), true, false)
            end

            local inRangePets = {}
            if cfg.allowPets then
                local allPets = getRequesterPets(spawn)
                for _, p in ipairs(allPets) do
                    if p.distance <= cfg.maxRange then
                        table.insert(inRangePets, p)
                    end
                end
            end

            local totalJobs = 0

            -- Queue player buffs if player has eligible spells
            if #playerGems > 0 then
                enqueueBuffJob({
                    sender     = cleanSender,
                    targetName = cleanSender,
                    targetID   = currentTargetID,
                    isPet      = false,
                    gems       = playerGems,
                    isGuild    = isGuildMember,
                    isResumed  = false,
                })
                totalJobs = totalJobs + 1
            end

            -- Queue each pet's buffs (pets receive all requested spells)
            for _, pet in ipairs(inRangePets) do
                enqueueBuffJob({
                    sender     = cleanSender,
                    targetName = pet.name,
                    targetID   = pet.id,
                    isPet      = true,
                    petName    = pet.name,
                    gems       = requestedGems,
                    isGuild    = isGuildMember,
                    isResumed  = false,
                })
                totalJobs = totalJobs + 1
            end

            if totalJobs == 0 then
                queueTell(cleanSender, string.format("Cannot cast: requested spells cannot land on you at Level %d and no active pets were found in range.", requesterLevel))
                logMsg(string.format("Request 'both' from '%s' rejected: no eligible player buffs and no pets in range.", cleanSender), true, false)
                return
            end

            -- Check Guild Priority Preemption: if a non-guild player is currently being buffed
            if cfg.guildMode == 'Guild Priority' and isGuildMember then
                if rt.currentJob and not rt.currentJob.isGuild and not rt.preemptRequested then
                    rt.preemptRequested = true
                    pcall(function()
                        mq.cmd('/stopcast')
                        mq.cmd('/interrupt')
                    end)
                    local pauseMsg = (cfg.guildPriorityPauseMsg and cfg.guildPriorityPauseMsg ~= '')
                        and cfg.guildPriorityPauseMsg
                        or "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!"
                    queueTell(rt.currentJob.sender, pauseMsg)
                    logMsg(string.format("Preempting active buffs on non-guild player '%s' for guild member '%s'.", rt.currentJob.sender, cleanSender), true, false)
                    print(string.format('\ay[Triune Buffbot]\ax Preempting non-guild player \aw%s\ax for guild member \ag%s\ax...', rt.currentJob.sender, cleanSender))
                end
            end

            local totalAhead = getQueuePosition(cleanSender)
            local lineNum = totalAhead + 1

            local allNamesList = {}
            for _, sp in ipairs(requestedGems) do table.insert(allNamesList, string.format("[%d] %s", sp.gem, sp.name)) end
            local spellsText = table.concat(allNamesList, ", ")

            if #inRangePets > 0 then
                local petNamesList = {}
                for _, p in ipairs(inRangePets) do table.insert(petNamesList, p.name) end
                local petNamesStr = table.concat(petNamesList, ", ")
                local petDesc = (#inRangePets == 1) and string.format("pet (%s)", petNamesStr) or string.format("%d pets (%s)", #inRangePets, petNamesStr)

                if #playerGems > 0 then
                    logMsg(string.format("Requester '%s' queued buffs for self (%d) AND %s (%d) (%s, Line #%d): %s", cleanSender, #playerGems, petDesc, #requestedGems, isGuildMember and "Guild" or "Public", lineNum, spellsText))
                    print(string.format('\ag[Triune Buffbot]\ax Queued buffs for \aw%s\ax AND %s (%s, Line #%d): %s', cleanSender, petDesc, isGuildMember and "Guild" or "Public", lineNum, spellsText))
                else
                    logMsg(string.format("Requester '%s' queued %d buff(s) for %s only (player level restricted) (%s, Line #%d): %s", cleanSender, #requestedGems, petDesc, isGuildMember and "Guild" or "Public", lineNum, spellsText))
                    print(string.format('\ag[Triune Buffbot]\ax Queued %d buff(s) for %s (%s, %s, Line #%d): %s', #requestedGems, cleanSender, petDesc, isGuildMember and "Guild" or "Public", lineNum, spellsText))
                end

                if totalAhead > 0 then
                    if pctMana < cfg.minManaPct then
                        queueTell(cleanSender, string.format('Queued buffs for you AND your %s! You are #%d in line (%d ahead). Mana is low (%d%% < %d%%) - meditating before buffing.', petDesc, lineNum, totalAhead, pctMana, cfg.minManaPct))
                    else
                        queueTell(cleanSender, string.format('Queued buffs for you AND your %s! You are #%d in line (%d ahead). Please stand by!', petDesc, lineNum, totalAhead))
                    end
                else
                    if pctMana < cfg.minManaPct then
                        queueTell(cleanSender, string.format('Queued buffs for you AND your %s! You are #1 in line. Mana is low (%d%% < %d%%) - meditating for a moment before buffing.', petDesc, pctMana, cfg.minManaPct))
                    elseif isGuildMember and cfg.guildMode == 'Guild Priority' then
                        queueTell(cleanSender, string.format('Stand by, prioritizing your guild request! Preparing to cast buffs on you and your %s! (You are #1 in line)', petDesc))
                    else
                        queueTell(cleanSender, string.format('Stand by, preparing to cast buffs on you and your %s! (You are #1 in line)', petDesc))
                    end
                end
            else
                logMsg(string.format("Requester '%s' requested both, but no pet found in range. Queued player buffs only (%s, Line #%d): %s", cleanSender, isGuildMember and "Guild" or "Public", lineNum, spellsText), true, false)
                print(string.format('\ag[Triune Buffbot]\ax Queued %d buff(s) for \aw%s\ax (No pet in range, %s, Line #%d): %s', #playerGems, cleanSender, isGuildMember and "Guild" or "Public", lineNum, spellsText))

                if totalAhead > 0 then
                    queueTell(cleanSender, string.format('No active pet in range found, but queued %d buff(s) for you! You are #%d in line (%d ahead).', #playerGems, lineNum, totalAhead))
                else
                    if isGuildMember and cfg.guildMode == 'Guild Priority' then
                        queueTell(cleanSender, string.format('No active pet in range found, but prioritizing %d buff(s) for you! Stand by, casting now.', #playerGems))
                    else
                        queueTell(cleanSender, string.format('No active pet in range found, but queued %d buff(s) for you! Stand by, casting now.', #playerGems))
                    end
                end
            end

        else -- mode == 'player'
            -- Filter requested spells by requester's level (<= 46 check)
            local validGems = {}
            local skippedGems = {}
            for _, sp in ipairs(requestedGems) do
                if not canCastOnPlayer(sp.name, requesterLevel) then
                    table.insert(skippedGems, sp.name)
                else
                    table.insert(validGems, sp)
                end
            end

            if #validGems == 0 then
                local skippedListStr = table.concat(skippedGems, ", ")
                queueTell(cleanSender, string.format("Cannot cast: %s cannot land on you at Level %d. (Hint: High-level buffs land on pets with 'pet <num>')", skippedListStr, requesterLevel))
                logMsg(string.format("All requested buffs for '%s' rejected due to level restriction (Level %d): %s", cleanSender, requesterLevel, skippedListStr), true, false)
                return
            end

            if #skippedGems > 0 then
                local skippedListStr = table.concat(skippedGems, ", ")
                queueTell(cleanSender, string.format("Note: Skipped %s (requires higher level for players; lands on pets with 'pet <num>').", skippedListStr))
                logMsg(string.format("Skipped level-restricted buffs for player '%s' (Level %d): %s", cleanSender, requesterLevel, skippedListStr), true, false)
            end

            requestedGems = validGems

            local namesList = {}
            for _, sp in ipairs(requestedGems) do table.insert(namesList, string.format("[%d] %s", sp.gem, sp.name)) end
            local spellsText = table.concat(namesList, ", ")

            enqueueBuffJob({
                sender     = cleanSender,
                targetName = cleanSender,
                targetID   = currentTargetID,
                isPet      = false,
                gems       = requestedGems,
                isGuild    = isGuildMember,
                isResumed  = false,
            })

            -- Check Guild Priority Preemption: if a non-guild player is currently being buffed
            if cfg.guildMode == 'Guild Priority' and isGuildMember then
                if rt.currentJob and not rt.currentJob.isGuild and not rt.preemptRequested then
                    rt.preemptRequested = true
                    pcall(function()
                        mq.cmd('/stopcast')
                        mq.cmd('/interrupt')
                    end)
                    local pauseMsg = (cfg.guildPriorityPauseMsg and cfg.guildPriorityPauseMsg ~= '')
                        and cfg.guildPriorityPauseMsg
                        or "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!"
                    queueTell(rt.currentJob.sender, pauseMsg)
                    logMsg(string.format("Preempting active buffs on non-guild player '%s' for guild member '%s'.", rt.currentJob.sender, cleanSender), true, false)
                    print(string.format('\ay[Triune Buffbot]\ax Preempting non-guild player \aw%s\ax for guild member \ag%s\ax...', rt.currentJob.sender, cleanSender))
                end
            end

            local totalAhead = getQueuePosition(cleanSender)
            local lineNum = totalAhead + 1

            logMsg(string.format("Requester '%s' (Lvl %d) selected %d buff(s) (%s, Line #%d): %s", cleanSender, requesterLevel, #requestedGems, isGuildMember and "Guild" or "Public", lineNum, spellsText))
            print(string.format('\ag[Triune Buffbot]\ax Queued %d buff(s) for \aw%s\ax (Lvl %d, %s, Line #%d): %s', #requestedGems, cleanSender, requesterLevel, isGuildMember and "Guild" or "Public", lineNum, spellsText))

            if totalAhead > 0 then
                if pctMana < cfg.minManaPct then
                    queueTell(cleanSender,
                        string.format(
                            'Queued %d buff(s)! You are #%d in line (%d ahead). Mana is low (%d%% < %d%%) - meditating before buffing.',
                            #requestedGems, lineNum, totalAhead, pctMana, cfg.minManaPct))
                else
                    queueTell(cleanSender,
                        string.format('Queued %d buff(s)! You are #%d in line (%d ahead). Please stand by!',
                            #requestedGems, lineNum, totalAhead))
                end
            else
                if pctMana < cfg.minManaPct then
                    queueTell(cleanSender,
                        string.format(
                            'Queued %d buff(s)! You are #1 in line. Mana is low (%d%% < %d%%) - meditating for a moment before buffing.',
                            #requestedGems, pctMana, cfg.minManaPct))
                elseif isGuildMember and cfg.guildMode == 'Guild Priority' then
                    if #requestedGems == 1 then
                        queueTell(cleanSender,
                            string.format('Stand by, prioritizing your guild request! Casting %s! (You are #1 in line)', requestedGems[1].name))
                    else
                        queueTell(cleanSender,
                            string.format('Stand by, prioritizing your guild request! Preparing to cast %d selected buffs! (You are #1 in line)', #requestedGems))
                    end
                elseif #requestedGems == 1 then
                    queueTell(cleanSender,
                        string.format('Stand by, casting %s! (You are #1 in line)', requestedGems[1].name))
                else
                    queueTell(cleanSender,
                        string.format('Stand by, preparing to cast %d selected buffs! (You are #1 in line)', #requestedGems))
                end
            end
        end
    else
        -- If requester sent a tell that wasn't a choice, send the numbered menu with level annotations
        local requesterLevel = 1
        pcall(function() requesterLevel = spawn.Level() or 1 end)
        rt.pendingOffers[cleanSender] = { timestamp = now, spawnID = spawn.ID(), gems = currentGems, level = requesterLevel }
        logMsg(string.format("Sent numbered buff menu to '%s' (Lvl %d).", cleanSender, requesterLevel))
        sendMenuTells(cleanSender, currentGems, requesterLevel)
    end
end

-- ============================================================================
-- Interactive Hail Event Handler
-- ============================================================================
local lastHailTimes = {}
local lastGlobalHailTime = 0

local function onHailReceived(line, sender, targetName)
    if not cfg.enabled then return end
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

    -- Silently ignore hails from banned players
    if isPlayerIgnored(cleanSender) then
        return
    end

    -- Silently ignore hails from non-guild players if guild-only is enabled
    if cfg.guildMode == 'Guild Only' then
        local hSpawn = nil
        pcall(function() hSpawn = mq.TLO.Spawn(string.format('pc =%s', cleanSender)) end)
        if not hSpawn or not hSpawn() or (hSpawn.ID() or 0) <= 0 then
            pcall(function() hSpawn = mq.TLO.Spawn(string.format('pc %s', cleanSender)) end)
        end
        if not isSameGuild(hSpawn) then
            return
        end
    end

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
    if (now - lastHail) < 5 or (now - lastGlobalHailTime) < 3 then
        return -- Rate limit 5 seconds per player, 3 seconds globally to avoid chat packet flood
    end
    lastHailTimes[cleanSender:lower()] = now
    lastGlobalHailTime = now

    logMsg(string.format("Hail from '%s' received. Replying in /say.", cleanSender))
    pcall(function()
        mq.cmdf('/say %s, send tell to me to receive buffs!', cleanSender)
    end)
end

-- Register tell and hail events
local registeredEvents = {}
local function regEvent(name, pattern, handler)
    if mq.unevent then pcall(mq.unevent, name) end
    mq.event(name, pattern, handler)
    table.insert(registeredEvents, name)
end

local function unregisterEvents()
    if mq and mq.unevent then
        for _, name in ipairs(registeredEvents) do pcall(mq.unevent, name) end
    end
    registeredEvents = {}
end

local function registerEvents()
    regEvent('BuffbotTell', '#*##1# tells you, #2#', onTellReceived)
    regEvent('BuffbotHail1', '#*##1# says, \'Hail, #2#\'', onHailReceived)
    regEvent('BuffbotHail2', '#*##1# says, "#2#"', onHailReceived)
    regEvent('BuffbotHail3', '#*##1# says, \'Hail, #2#!\'', onHailReceived)
    regEvent('BuffbotHail4', '#*##1# says, "#2#!"', onHailReceived)
    regEvent('BuffbotHail5', '#*##1# says, \'Hail, #2#.\'', onHailReceived)
    regEvent('BuffbotHail6', '#*##1# says, "#2#."', onHailReceived)
    regEvent('BuffbotHailPlain1', '#*##1# says, \'Hail\'', function(line, sender) onHailReceived(line, sender, nil) end)
    regEvent('BuffbotHailPlain2', '#*##1# says, \'Hail!\'', function(line, sender) onHailReceived(line, sender, nil) end)
    regEvent('BuffbotHailPlain3', '#*##1# says, "Hail"', function(line, sender) onHailReceived(line, sender, nil) end)
    regEvent('BuffbotHailPlain4', '#*##1# says, "Hail!"', function(line, sender) onHailReceived(line, sender, nil) end)
end

-- ============================================================================
-- Target Acquisition & Verification Helper
-- ============================================================================
local function acquireTarget(targetID, targetName, isPet, ownerName)
    local myName = nil
    pcall(function() myName = mq.TLO.Me.CleanName() end)
    local isSelf = myName and not isPet and (targetName:lower() == myName:lower())

    if isSelf then
        pcall(function() mq.cmdf('/target id %d', mq.TLO.Me.ID() or 0) end)
        delay(200, function() return (mq.TLO.Target.ID() or 0) == (mq.TLO.Me.ID() or 0) end)
        return true
    end

    -- Try targeting by spawn ID first
    if targetID and targetID > 0 then
        pcall(function() mq.cmdf('/target id %d', targetID) end)
        delay(250, function() return (mq.TLO.Target.ID() or 0) == targetID end)
    end

    -- Fallback if target ID failed or was lost
    local currentId = 0
    pcall(function() currentId = mq.TLO.Target.ID() or 0 end)
    if currentId ~= targetID then
        if isPet and ownerName and ownerName ~= '' then
            pcall(function()
                local ownerSpawn = mq.TLO.Spawn(string.format('pc =%s', ownerName))
                if ownerSpawn and ownerSpawn() then
                    local ownerPets = getRequesterPets(ownerSpawn)
                    for _, op in ipairs(ownerPets) do
                        if (targetName and op.name:lower() == targetName:lower()) or targetID == op.id then
                            targetID = op.id
                            mq.cmdf('/target id %d', targetID)
                            break
                        end
                    end
                end
            end)
            delay(250, function() return (mq.TLO.Target.ID() or 0) == targetID end)
        elseif not isPet and targetName and targetName ~= '' then
            pcall(function() mq.cmdf('/target pc =%s', targetName) end)
            delay(250, function() return (mq.TLO.Target.CleanName() or ''):lower() == targetName:lower() end)
            if (mq.TLO.Target.CleanName() or ''):lower() ~= targetName:lower() then
                pcall(function() mq.cmdf('/target "%s"', targetName) end)
                delay(250, function() return (mq.TLO.Target.CleanName() or ''):lower() == targetName:lower() end)
            end
        end
    end

    -- Verify target is valid, alive
    local valid = false
    pcall(function()
        local tid = mq.TLO.Target.ID() or 0
        local tName = mq.TLO.Target.CleanName() or ''
        if isPet then
            valid = tid > 0 and not mq.TLO.Target.Dead() and
                ((targetID > 0 and tid == targetID) or (targetName and tName:lower() == targetName:lower()))
        else
            valid = tid > 0 and not mq.TLO.Target.Dead() and
                (tName:lower() == targetName:lower() or (targetID > 0 and tid == targetID))
        end
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

-- ============================================================================
-- Buff Casting Loop
-- ============================================================================
local function processBuffQueue()
    if #rt.activeQueue == 0 then
        if rt.state ~= 'STOPPED' and rt.state ~= 'MEDDING' then
            rt.state = 'IDLE'
        end
        return
    end

    local request = table.remove(rt.activeQueue, 1)
    rt.currentJob = request
    rt.preemptRequested = false

    local isPet = request.isPet or false
    local targetName = request.targetName or request.sender
    local targetID = request.targetID or request.spawnID
    local gemsToCast = request.gems or {}
    local ownerName = request.sender
    local petName = request.petName or targetName
    local isGuild = request.isGuild or false

    if #gemsToCast == 0 then
        rt.currentJob = nil
        rt.state = 'IDLE'
        return
    end

    -- Create remainingGems tracking list (shallow copy of gemsToCast)
    request.remainingGems = {}
    for _, sp in ipairs(gemsToCast) do
        table.insert(request.remainingGems, sp)
    end

    rt.state = 'CASTING'
    local targetLabel = isPet and string.format("%s's Pet (%s)", ownerName, petName) or targetName
    rt.currentRequester = targetLabel

    local spellSummaryList = {}
    for _, sp in ipairs(gemsToCast) do table.insert(spellSummaryList, string.format("[%d] %s", sp.gem, sp.name)) end

    if request.isResumed then
        logMsg(string.format("Resuming buffs for %s (%s) with %d remaining spell(s): %s", targetLabel, isGuild and "Guild" or "Public", #gemsToCast, table.concat(spellSummaryList, ", ")))
        print(string.format('\ag[Triune Buffbot]\ax Resuming %d buff(s) on \aw%s\ax: %s', #gemsToCast, targetLabel, table.concat(spellSummaryList, ", ")))
        if cfg.guildPriorityResumeMsg and cfg.guildPriorityResumeMsg ~= '' then
            queueTell(ownerName, cfg.guildPriorityResumeMsg)
        end
    else
        logMsg(string.format("Buffing %s (%s) with %d spell(s): %s", targetLabel, isGuild and "Guild" or "Public", #gemsToCast, table.concat(spellSummaryList, ", ")))
        print(string.format('\ag[Triune Buffbot]\ax Casting %d buff(s) on \aw%s\ax (%s): %s', #gemsToCast, targetLabel, isGuild and "Guild" or "Public", table.concat(spellSummaryList, ", ")))
    end

    -- Check Mana % before starting sequence
    local pctMana = getMyPctMana()
    if pctMana < cfg.minManaPct then
        logMsg(string.format("Mana low (%d%% < %d%%). Meditating before buffing %s...", pctMana, cfg.minManaPct, targetLabel), true, false)
        queueTell(ownerName, string.format('Mana is low (%d%%). Meditating until %d%% before buffing %s, please stand by!', pctMana, cfg.minManaPct, isPet and ("your pet (" .. petName .. ")") or "you"))
        local isSit = false
        pcall(function() isSit = mq.TLO.Me.Sitting() or false end)
        if not isSit and (os.time() - (rt.lastSitAttemptTime or 0)) >= 2 then
            rt.lastSitAttemptTime = os.time()
            pcall(function() mq.cmd('/sit') end)
        end
        while pctMana < cfg.minManaPct and cfg.enabled do
            local inGame = false
            pcall(function() inGame = mq.TLO.MacroQuest.GameState() == 'INGAME' end)
            if not inGame then break end
            processOutgoingTells()
            if rt.preemptRequested then break end
            delay(500)
            pctMana = getMyPctMana()
        end
    end

    -- If preempted during mana wait:
    if rt.preemptRequested then
        requeuePreemptedJob(request)
        rt.preemptRequested = false
        rt.currentJob = nil
        rt.currentRequester = nil
        return
    end

    -- Initial target lock
    local targetValid = acquireTarget(targetID, targetName, isPet, ownerName)
    if not targetValid then
        if isPet then
            logMsg(string.format("Pet target '%s' for '%s' lost or unavailable in zone. Skipping.", petName, ownerName), true, false)
            queueTell(ownerName, string.format("Your pet (%s) was unavailable or lost in zone. Skipping.", petName))
        else
            logMsg(string.format("Target '%s' lost or unavailable in zone. Aborting buff sequence.", targetName), true, false)
        end
        rt.currentJob = nil
        rt.currentRequester = nil
        rt.state = 'IDLE'
        return
    end

    -- Ensure standing before sequence starts
    local isSitOrDuck = false
    pcall(function() isSitOrDuck = mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() end)
    if isSitOrDuck then
        mq.cmd('/stand')
        delay(50)
    end

    for _, spellInfo in ipairs(gemsToCast) do
        if not cfg.enabled or rt.preemptRequested then break end
        processOutgoingTells()
        if rt.preemptRequested then break end

        local gemNum = spellInfo.gem
        local expectedName = spellInfo.name

        -- Re-verify gem slot index by spell name in case spell bar changed
        local currentGemSpell = nil
        pcall(function() currentGemSpell = mq.TLO.Me.Gem(gemNum).Name() end)
        if currentGemSpell ~= expectedName then
            pcall(function() gemNum = mq.TLO.Me.Gem(expectedName)() end)
        end

        local castSuccess = false

        if gemNum and gemNum > 0 then
            -- Pre-cast landing check for player targets
            if not isPet then
                local targetLvl = 1
                pcall(function()
                    local sp = mq.TLO.Spawn(string.format('pc =%s', targetName))
                    if sp and sp() then targetLvl = sp.Level() or 1 end
                end)
                if targetLvl > 0 and not canCastOnPlayer(expectedName, targetLvl) then
                    logMsg(string.format("Skipping [%s] on player '%s' (Target Level %d <= 46 and spell is not allowed for low-level players).", expectedName, targetName, targetLvl), true, false)
                    queueTell(ownerName, string.format("[%s] skipped: restricted to level 47+ (you are level %d).", expectedName, targetLvl))
                    gemNum = 0 -- Skip this spell cast
                    castSuccess = true -- Mark as handled
                end
            end
        end

        if gemNum and gemNum > 0 then
            -- Pre-cast cooldown check: skip immediately if spell is on cooldown > 30s
            local cdRemaining = getSpellCooldownSec(gemNum, expectedName)
            if cdRemaining > 30 then
                logMsg(string.format("Skipping [%s] on %s: on cooldown for %ds (> 30s limit).", expectedName, targetLabel, cdRemaining), true, false)
                queueTell(ownerName, string.format("[%s] skipped: currently on cooldown (%ds remaining > 30s limit).", expectedName, cdRemaining))
                gemNum = 0 -- Skip this spell cast
                castSuccess = true -- Mark as handled
            end
        end

        if gemNum and gemNum > 0 then
            -- Verify target lock on requester; only re-target if lost
            local curTargetID = 0
            pcall(function() curTargetID = mq.TLO.Target.ID() or 0 end)
            if curTargetID ~= targetID then
                if not acquireTarget(targetID, targetName, isPet, ownerName) then
                    logMsg(string.format("Target '%s' lost during casting. Aborting remaining buffs.", targetLabel), true, false)
                    break
                end
            end

            -- Ensure standing and facing target
            pcall(function()
                if mq.TLO.Me.Sitting() or mq.TLO.Me.Ducking() then mq.cmd('/stand') end
                mq.cmd('/face fast')
            end)

            -- Wait for spell cooldown / global recovery (up to 30 seconds max)
            if not isSpellReady(gemNum, expectedName) then
                local startWait = os.time()
                while not isSpellReady(gemNum, expectedName) and cfg.enabled do
                    processOutgoingTells()
                    if rt.preemptRequested then break end
                    delay(50)
                    if (os.time() - startWait) >= 30 then break end
                end
            end

            if rt.preemptRequested then break end

            if isSpellReady(gemNum, expectedName) then
                -- Cast the spell on the target
                logMsg(string.format("Casting [%s] on %s (Gem %d)", expectedName, targetLabel, gemNum))
                pcall(function() mq.cmdf('/cast %d', gemNum) end)

                -- Wait for casting to register on client
                local castStarted = false
                local waitStart = 0
                pcall(function() waitStart = mq.gettime() end)
                if waitStart == 0 then waitStart = os.time() * 1000 end

                while (mq.gettime() - waitStart) < 600 do
                    if rt.preemptRequested then
                        pcall(function()
                            mq.cmd('/stopcast')
                            mq.cmd('/interrupt')
                        end)
                        break
                    end
                    pcall(function() castStarted = mq.TLO.Me.Casting() ~= nil end)
                    if castStarted then break end
                    delay(25)
                end

                -- Wait for casting to complete while servicing incoming tells
                if castStarted and not rt.preemptRequested then
                    local attempts = 0
                    local isCasting = true
                    while isCasting and attempts < 400 do
                        processOutgoingTells()
                        if rt.preemptRequested then
                            pcall(function()
                                mq.cmd('/stopcast')
                                mq.cmd('/interrupt')
                            end)
                            break
                        end
                        pcall(function() isCasting = mq.TLO.Me.Casting() ~= nil end)
                        if isCasting then
                            delay(50)
                            attempts = attempts + 1
                        end
                    end
                    if not rt.preemptRequested then
                        castSuccess = true
                    end
                elseif not castStarted and not rt.preemptRequested then
                    castSuccess = true
                end

                if rt.preemptRequested then break end

                -- Reactive recovery wait for global recovery / spell readiness
                local gcdWait = 0
                pcall(function() gcdWait = mq.gettime() end)
                if gcdWait == 0 then gcdWait = os.time() * 1000 end
                while (mq.gettime() - gcdWait) < 3000 do
                    processOutgoingTells()
                    if rt.preemptRequested then break end
                    if isSpellReady(gemNum, expectedName) then break end
                    delay(50)
                end
            else
                logMsg(string.format("Spell [%s] (Gem %d) timed out waiting for cooldown recovery (> 30s). Skipping.", expectedName, gemNum), true, false)
                queueTell(ownerName, string.format("[%s] skipped: cooldown exceeded 30s wait limit.", expectedName))
                castSuccess = true
            end
        end

        if castSuccess then
            -- Remove this spell from remainingGems
            for idx, remSp in ipairs(request.remainingGems) do
                if remSp.name == expectedName and remSp.gem == gemNum then
                    table.remove(request.remainingGems, idx)
                    break
                end
            end
        end
    end

    -- Handle preemption interruption
    if rt.preemptRequested then
        if #request.remainingGems > 0 then
            request.gems = request.remainingGems
            request.isResumed = true
            requeuePreemptedJob(request)
            logMsg(string.format("Buff sequence for '%s' paused for guild priority. Re-queued %d remaining spell(s).", targetLabel, #request.gems))
        end
        rt.preemptRequested = false
        rt.currentJob = nil
        rt.currentRequester = nil
        return
    end

    -- Sequence finished normally!
    rt.currentJob = nil

    -- Check if there are more pending jobs in queue for this sender (e.g. multi-pet buff sequence)
    local hasMoreJobsForSender = false
    for _, qJob in ipairs(rt.activeQueue) do
        if qJob.sender:lower() == ownerName:lower() then
            hasMoreJobsForSender = true
            break
        end
    end

    if not hasMoreJobsForSender then
        if isPet then
            logMsg(string.format("Completed all buffs for '%s' (last pet '%s'). Sending completion tell.", ownerName, petName))
            queueTell(ownerName, string.format("All buffs cast on your pet (%s)! Enjoy!", petName))
        else
            logMsg(string.format("Completed buffs for '%s'. Sending completion tell.", targetName))
            queueTell(ownerName, cfg.completionMsg)
        end
        rt.cooldowns[ownerName:lower()] = os.time()
    else
        if isPet then
            logMsg(string.format("Completed buffs on pet '%s' for '%s'. Moving to next queued target...", petName, ownerName))
        else
            logMsg(string.format("Completed buffs on '%s'. Moving to next queued target (pet)...", targetName))
        end
    end

    rt.currentRequester = nil

    -- Auto-meditate if mana is not at 100%
    local endMana = getMyPctMana()
    if cfg.autoMed and endMana < 100 then
        local isSit = false
        pcall(function() isSit = mq.TLO.Me.Sitting() or false end)
        if not isSit and (os.time() - (rt.lastSitAttemptTime or 0)) >= 2 then
            rt.lastSitAttemptTime = os.time()
            pcall(function() mq.cmd('/sit') end)
            delay(200)
        end
        rt.state = 'MEDDING'
        logMsg(string.format("Buffs completed. Auto-meditating (%d%% / 100%%)...", endMana))
    else
        rt.state = 'IDLE'
    end
end

-- Engine on/off (window visibility is separate: ctrl.show_buffbot)
local function setEnabled(on)
    on = (on == true)
    if cfg.enabled == on then return end
    cfg.enabled = on
    if on then
        rt.state = 'IDLE'
        logMsg("Buffbot station ACTIVE. Listening for tells...")
        print('\ag[Triune Buffbot]\ax station \agACTIVE\ax. Listening for tells...')
    else
        rt.state = 'STOPPED'
        rt.activeQueue = {}
        rt.pendingOffers = {}
        rt.currentJob = nil
        rt.currentRequester = nil
        rt.preemptRequested = false
        logMsg("Buffbot station STOPPED.", true, false)
        print('\ag[Triune Buffbot]\ax station \arSTOPPED\ax.')
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

    -- Station switch (the standalone script was "on" whenever it ran; as a
    -- plugin the engine only answers tells while this is ACTIVE).
    if cfg.enabled then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.15, 0.45, 0.25, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.20, 0.55, 0.30, 1.0)
        if ImGui.Button("Buffbot Station: ACTIVE (click to stop)##bbStation", 300, 26) then
            setEnabled(false)
        end
    else
        ImGui.PushStyleColor(ImGuiCol.Button, 0.45, 0.15, 0.15, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.55, 0.20, 0.20, 1.0)
        if ImGui.Button("Buffbot Station: STOPPED (click to start)##bbStation", 300, 26) then
            setEnabled(true)
        end
    end
    ImGui.PopStyleColor(2)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Toggle the buffbot engine. Also: /ac buffbot on|off")
    end
    ImGui.Spacing()

    -- Status Indicator
    local myGuild = getMyGuild()
    local guildStatusTag = ""
    if cfg.guildMode == 'Guild Only' then
        if myGuild and myGuild ~= '' then
            guildStatusTag = string.format(" [GUILD ONLY: %s]", myGuild)
        else
            guildStatusTag = " [GUILD ONLY: UNGUILDED!]"
        end
    elseif cfg.guildMode == 'Guild Priority' then
        if myGuild and myGuild ~= '' then
            guildStatusTag = string.format(" [GUILD PRIORITY: %s]", myGuild)
        else
            guildStatusTag = " [GUILD PRIORITY: UNGUILDED!]"
        end
    end

    if rt.state == 'IDLE' then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Status: LISTENING FOR TELLS" .. guildStatusTag)
    elseif rt.state == 'CASTING' then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4],
            string.format("Status: BUFFING %s...%s", rt.currentRequester or '', guildStatusTag))
    elseif rt.state == 'MEDDING' then
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4],
            string.format("Status: MEDITATING (%d%% / 100%%)%s", getMyPctMana(), guildStatusTag))
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format("Status: %s%s", rt.state, guildStatusTag))
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Active Memorized Buff Spells (Tell Menu)")

    local gems = getAvailableGems()
    if #gems == 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "No spells currently memorized on your spell bar!")
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Check the box next to any spell to allow casting on Level <= 46 players (unchecked = 47+ / pets only):")
        ImGui.Spacing()
        for idx, g in ipairs(gems) do
            local chkVal = (cfg.allowLowLevel and cfg.allowLowLevel[g.name] == true)
            local newChk, chkChanged = ImGui.Checkbox(string.format("##allowLow_%d", idx), chkVal)
            if chkChanged then
                if not cfg.allowLowLevel then cfg.allowLowLevel = {} end
                cfg.allowLowLevel[g.name] = newChk
                saveConfig(true)
            end
            ImGui.SameLine()
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("[%d]", idx))
            ImGui.SameLine()
            ImGui.Text(string.format("%s (Gem %d)", g.name, g.gem))
            ImGui.SameLine()
            if chkVal then
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "[Allowed on Lvl <= 46]")
            else
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "[Lvl 47+ / Pet Only]")
            end
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Configuration Options")

    local autoMedVal, autoMedChanged = ImGui.Checkbox("Auto Meditate to 100% Mana", cfg.autoMed)
    if autoMedChanged then
        cfg.autoMed = autoMedVal
        saveConfig(true)
    end

    ImGui.SameLine()
    local antiAfkVal, antiAfkChanged = ImGui.Checkbox("Anti-AFK Keep-Alive", cfg.antiAfk)
    if antiAfkChanged then
        cfg.antiAfk = antiAfkVal
        saveConfig(true)
    end

    local allowPetsVal, allowPetsChanged = ImGui.Checkbox("Allow Pet Buffing", cfg.allowPets)
    if allowPetsChanged then
        cfg.allowPets = allowPetsVal
        saveConfig(true)
    end

    ImGui.Spacing()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Guild Policy:")
    ImGui.SameLine()
    if myGuild and myGuild ~= '' then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("(Your Guild: %s)", myGuild))
    else
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "(Unguilded - Guild modes inactive)")
    end

    local isOff = (cfg.guildMode == 'Off' or not cfg.guildMode or cfg.guildMode == '')
    local isPriority = (cfg.guildMode == 'Guild Priority')
    local isOnly = (cfg.guildMode == 'Guild Only')

    local radOff = ImGui.RadioButton("Off (All Requesters)", isOff)
    if radOff and not isOff then
        cfg.guildMode = 'Off'
        cfg.guildOnly = false
        saveConfig(true)
    end

    ImGui.SameLine()
    local radPri = ImGui.RadioButton("Guild Priority (Preempt & Jump Queue)", isPriority)
    if radPri and not isPriority then
        cfg.guildMode = 'Guild Priority'
        cfg.guildOnly = false
        saveConfig(true)
    end

    ImGui.SameLine()
    local radOnly = ImGui.RadioButton("Guild Only", isOnly)
    if radOnly and not isOnly then
        cfg.guildMode = 'Guild Only'
        cfg.guildOnly = true
        saveConfig(true)
    end

    ImGui.Spacing()
    local rangeVal, rangeChanged = ImGui.SliderInt("Max Requester Range", cfg.maxRange, 20, 300)
    if rangeChanged then
        cfg.maxRange = rangeVal; saveConfig(true)
    end

    local timeoutVal, timeoutChanged = ImGui.SliderInt("Offer Expiration (sec)", cfg.timeoutSec, 10, 120)
    if timeoutChanged then
        cfg.timeoutSec = timeoutVal; saveConfig(true)
    end

    local manaVal, manaChanged = ImGui.SliderInt("Min Mana % Threshold", cfg.minManaPct, 5, 50)
    if manaChanged then
        cfg.minManaPct = manaVal; saveConfig(true)
    end

    local delayVal, delayChanged = ImGui.SliderInt("Tell Dispatch Delay (ms)", cfg.tellDelayMs or 2500, 1000, 5000)
    if delayChanged then
        cfg.tellDelayMs = delayVal; saveConfig(true)
    end

    ImGui.Spacing()
    ImGui.Text("Completion Tell (Sent after all selected buffs cast):")
    local newComp, compChanged = ImGui.InputText("##completionMsg", cfg.completionMsg or "All buffs cast! Enjoy!", 256)
    if compChanged then
        cfg.completionMsg = newComp; saveConfig(true)
    end

    if cfg.guildMode == 'Guild Only' then
        ImGui.Spacing()
        ImGui.Text("Guild Restriction Tell (Sent when non-guild member requests buffs):")
        local newGuildMsg, guildMsgChanged = ImGui.InputText("##guildOnlyMsg", cfg.guildOnlyMsg or "Buffing is currently restricted to guild members only.", 256)
        if guildMsgChanged then
            cfg.guildOnlyMsg = newGuildMsg; saveConfig(true)
        end
    elseif cfg.guildMode == 'Guild Priority' then
        ImGui.Spacing()
        ImGui.Text("Guild Priority Pause Tell (Sent to non-guild player when paused for guild member):")
        local newPauseMsg, pauseMsgChanged = ImGui.InputText("##guildPriorityPauseMsg", cfg.guildPriorityPauseMsg or "Pausing your buffs momentarily for a guild member priority request. Will resume shortly!", 256)
        if pauseMsgChanged then
            cfg.guildPriorityPauseMsg = newPauseMsg; saveConfig(true)
        end

        ImGui.Spacing()
        ImGui.Text("Guild Priority Resume Tell (Sent when resuming paused non-guild player):")
        local newResumeMsg, resumeMsgChanged = ImGui.InputText("##guildPriorityResumeMsg", cfg.guildPriorityResumeMsg or "Resuming your remaining buffs now! Thank you for waiting.", 256)
        if resumeMsgChanged then
            cfg.guildPriorityResumeMsg = newResumeMsg; saveConfig(true)
        end
    end

    ImGui.Spacing()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4],
        "Tell Commands: Requesters reply with numbers (e.g. '1 3').\n" ..
        "Add 'pet' (e.g. 'pet 1 3') for pet only, or 'both' (e.g. 'both 1 3') for both.\n" ..
        "Note: Spells have level restrictions on players, but land on pets of any level.")
end

local function drawActivityTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Active Queue & Event Log")
    ImGui.Separator()

    ImGui.Text(string.format("Active Request Queue: %d pending", #rt.activeQueue))
    if #rt.activeQueue > 0 then
        if ImGui.BeginTable("##queueTable", 5, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn("Requester", ImGuiTableColumnFlags.WidthFixed, 110)
            ImGui.TableSetupColumn("Target", ImGuiTableColumnFlags.WidthFixed, 120)
            ImGui.TableSetupColumn("Tier", ImGuiTableColumnFlags.WidthFixed, 75)
            ImGui.TableSetupColumn("Spawn ID", ImGuiTableColumnFlags.WidthFixed, 70)
            ImGui.TableSetupColumn("Spells", ImGuiTableColumnFlags.WidthStretch, 200)
            ImGui.TableHeadersRow()

            for _, req in ipairs(rt.activeQueue) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                ImGui.Text(req.sender)
                ImGui.TableSetColumnIndex(1)
                if req.isPet then
                    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format("Pet (%s)", req.petName or req.targetName or 'Pet'))
                else
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Self (Player)")
                end
                ImGui.TableSetColumnIndex(2)
                if req.isGuild then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "Guild")
                else
                    if req.isResumed then
                        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "Resuming")
                    else
                        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Public")
                    end
                end
                ImGui.TableSetColumnIndex(3)
                ImGui.Text(tostring(req.targetID or req.spawnID or 0))
                ImGui.TableSetColumnIndex(4)
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
        for _, entry in ipairs(rt.log) do
            if entry.isErr then
                ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], entry.time .. entry.msg)
            elseif entry.isWarn then
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], entry.time .. entry.msg)
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], entry.time .. entry.msg)
            end
        end
    end
    ImGui.EndChild()
end

local function drawIgnoreTab()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Player Ignore & Ban Management")
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4],
        "Players on this list will be refused buffs and sent a ban notification message.")
    ImGui.Separator()

    ImGui.Text("Ban Notification Tell Message:")
    local newBanMsg, banMsgChanged = ImGui.InputText("##banMsg", cfg.banMsg or "You are banned from getting buffs.", 256)
    if banMsgChanged then
        cfg.banMsg = newBanMsg
        saveConfig(true)
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Add Player to Ignore List")

    if not rt.newIgnorePlayerName then rt.newIgnorePlayerName = "" end
    local newName, nameChanged = ImGui.InputText("##newIgnoreName", rt.newIgnorePlayerName, 64)
    if nameChanged then
        rt.newIgnorePlayerName = newName
    end

    ImGui.SameLine()
    if ImGui.Button("Add Player##addIgnoreBtn") then
        if rt.newIgnorePlayerName and rt.newIgnorePlayerName ~= "" then
            if addIgnoredPlayer(rt.newIgnorePlayerName) then
                logMsg(string.format("Added '%s' to player ignore list.", rt.newIgnorePlayerName))
                rt.newIgnorePlayerName = ""
            end
        end
    end

    ImGui.SameLine()
    local targetPcName = nil
    pcall(function()
        if mq.TLO.Target() and mq.TLO.Target.Type() == 'PC' then
            targetPcName = mq.TLO.Target.CleanName()
        end
    end)
    if targetPcName and targetPcName ~= '' then
        if ImGui.Button(string.format("Add Target (%s)##addTarIgnoreBtn", targetPcName)) then
            if addIgnoredPlayer(targetPcName) then
                logMsg(string.format("Added target '%s' to player ignore list.", targetPcName))
            end
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Current Ignored Players")

    local list = {}
    if cfg.ignoreList and type(cfg.ignoreList) == 'table' then
        for k, v in pairs(cfg.ignoreList) do
            if type(v) == 'string' and v ~= '' then
                table.insert(list, v)
            elseif type(k) == 'string' and k ~= '' and v == true then
                table.insert(list, k)
            end
        end
    end

    if #list == 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "No players currently on ignore list.")
    else
        table.sort(list, function(a, b) return a:lower() < b:lower() end)
        if ImGui.BeginTable("##ignoreTable", 3, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn("#", ImGuiTableColumnFlags.WidthFixed, 35)
            ImGui.TableSetupColumn("Player Name", ImGuiTableColumnFlags.WidthStretch, 200)
            ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableHeadersRow()

            local toRemove = nil
            for idx, pName in ipairs(list) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                ImGui.Text(tostring(idx))

                ImGui.TableSetColumnIndex(1)
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], pName)

                ImGui.TableSetColumnIndex(2)
                if ImGui.Button(string.format("Remove##ign_%d", idx)) then
                    toRemove = pName
                end
            end
            ImGui.EndTable()

            if toRemove then
                removeIgnoredPlayer(toRemove)
                logMsg(string.format("Removed '%s' from player ignore list.", toRemove))
            end
        end

        ImGui.Spacing()
        if ImGui.Button("Clear All Ignored Players##clearIgnoreBtn") then
            cfg.ignoreList = {}
            saveConfig(true)
            logMsg("Cleared all players from ignore list.")
        end
    end
end

local function renderGUI()
    if not ctrl.show_buffbot then return end

    core.pushTheme()
    core.preBeginWindow('buffbot')
    local visible, open = ImGui.Begin(string.format("Triune Buffbot v%s###TriuneBuffbotWin", VERSION), ctrl.show_buffbot)
    if not open then
        ctrl.show_buffbot = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end

    if visible then
        core.postBeginWindow('buffbot')
        if ImGui.BeginTabBar("BuffbotTabBar") then
            if ImGui.BeginTabItem("Controls") then
                drawControlTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Ignore List") then
                drawIgnoreTab()
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
    core.popTheme()
end

-- ============================================================================
-- Fiber body: one pass of the old main loop
-- ============================================================================
local function tick()
    local inGame = false
    pcall(function() inGame = mq.TLO.MacroQuest.GameState() == 'INGAME' end)
    if inGame then
        processOutgoingTells()

        local now = os.time()

        -- Clean up expired pending offers
        for sender, offer in pairs(rt.pendingOffers) do
            if (now - offer.timestamp) > cfg.timeoutSec then
                rt.pendingOffers[sender] = nil
                logMsg(string.format("Offer for '%s' expired.", sender))
            end
        end

        -- Periodic memory maintenance for tracking tables (every 10 minutes)
        if (now - (rt.lastTablePruneTime or 0)) >= 600 then
            rt.lastTablePruneTime = now
            for sender, timestamp in pairs(rt.cooldowns) do
                if (now - timestamp) > 3600 then rt.cooldowns[sender] = nil end
            end
            for sender, entry in pairs(lastTellBySender) do
                if (now - math.floor(entry.time / 1000)) > 3600 then lastTellBySender[sender] = nil end
            end
            for sender, hailTime in pairs(lastHailTimes) do
                if (now - hailTime) > 3600 then lastHailTimes[sender] = nil end
            end
        end

        -- Auto-meditate idle upkeep (throttled to avoid rapid /sit packet spam)
        if cfg.enabled and cfg.autoMed and #rt.activeQueue == 0 and rt.state ~= 'CASTING' and rt.state ~= 'STOPPED' then
            local pctMana = getMyPctMana()
            if pctMana < 100 then
                local isSitting = false
                pcall(function() isSitting = mq.TLO.Me.Sitting() or false end)
                local isMoving = false
                pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
                if not isSitting and not isMoving and (now - (rt.lastSitAttemptTime or 0)) >= 3 then
                    rt.lastSitAttemptTime = now
                    pcall(function() mq.cmd('/sit') end)
                end
                rt.state = 'MEDDING'
            elseif pctMana >= 100 and rt.state == 'MEDDING' then
                rt.state = 'IDLE'
            end
        end

        -- Anti-AFK upkeep: simulates hardware keypress to reset EQ native idle timer without disturbing sit state
        if cfg.enabled and cfg.antiAfk and #rt.activeQueue == 0 and rt.state ~= 'CASTING' and rt.state ~= 'STOPPED' then
            local isAfk = false
            pcall(function() isAfk = mq.TLO.Me.AFK() or false end)
            if isAfk then
                pcall(function() mq.cmd('/afk off') end)
                logMsg("Cleared AFK status.")
            end

            if (now - rt.lastAntiAfkTime) >= 120 then
                rt.lastAntiAfkTime = now
                local isCast = false
                pcall(function() isCast = mq.TLO.Me.Casting() ~= nil end)
                if not isCast then
                    pcall(function()
                        -- /nomodkey /keypress HOME generates a direct Windows/DirectInput key event
                        -- which resets EverQuest's internal idle timer without breaking sitting or casting
                        mq.cmd('/nomodkey /keypress HOME')
                        if mq.TLO.Me.AFK() then mq.cmd('/afk off') end
                    end)
                    logMsg("Anti-AFK keep-alive pulse performed (idle timer reset).")
                end
            end
        end

        -- Process queue if buffbot enabled
        if cfg.enabled and #rt.activeQueue > 0 and rt.state ~= 'STOPPED' then
            processBuffQueue()
        end
    end
end

-- ============================================================================
-- Plugin lifecycle
-- ============================================================================
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_buffbot == nil then ctrl.show_buffbot = false end
    cachedCharKey = nil
    loadConfig()
    -- Never auto-start buffing on login: the station is switched on explicitly.
    cfg.enabled = false
    rt.state = 'STOPPED'
    rt.activeQueue = {}
    rt.pendingOffers = {}
    rt.outgoingTells = {}
    rt.currentJob = nil
    rt.currentRequester = nil
    rt.preemptRequested = false
    registerEvents()
    logMsg("Triune Buffbot plugin loaded (station stopped).")
end

function plugin.onDestroy()
    if cfg.enabled then setEnabled(false) end
    unregisterEvents()
    saveConfig(true)
    cachedCharKey = nil
end

function plugin.onTick()
    if not core then return end
    refresh()
    tick()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    renderGUI()
end

-- Hold the puller / assist loop still while a buff job is being cast.
function plugin.wantsCombatHold()
    return cfg.enabled == true and rt.currentJob ~= nil
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    core.accent(GOLD, 'Buffbot Station')
    local isWinOpen = (ctrl.show_buffbot == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##bbToggleWin', 250, 24) then
        ctrl.show_buffbot = not isWinOpen
        core.saveLoadout(true)
    end
    local on = ImGui.Checkbox('Buffbot station active (answer tells & cast)##bbEnabled', cfg.enabled == true)
    if on ~= (cfg.enabled == true) then setEnabled(on) end
    ImGui.TextDisabled(string.format('State: %s | Queue: %d | Mode: %s', tostring(rt.state), #rt.activeQueue, tostring(cfg.guildMode or 'Off')))
end

-- /ac buffbot [on|off|toggle|start|stop] ; bare /ac buffbot toggles the window
-- (was: /lua run triune_buffbot)
function plugin.onCommand(cmd, args)
    if cmd ~= 'buff' and cmd ~= 'buffbot' and cmd ~= 'buffui' then return false end
    refresh()
    local sub = args and args[2] and tostring(args[2]):lower() or nil
    if sub == 'on' or sub == 'start' or sub == 'enable' then
        setEnabled(true)
        ctrl.show_buffbot = true
    elseif sub == 'off' or sub == 'stop' or sub == 'disable' then
        setEnabled(false)
    elseif sub == 'toggle' then
        setEnabled(not cfg.enabled)
    else
        ctrl.show_buffbot = not ctrl.show_buffbot
        print(string.format('\ag[Triune]\ax Buffbot window %s (station %s).', ctrl.show_buffbot and 'OPENED' or 'CLOSED', cfg.enabled and 'ACTIVE' or 'STOPPED'))
    end
    core.saveLoadout(true)
    return true
end

plugin.help = {
    '  \ag/ac buffbot [on|off|toggle]\ax - Buffbot window (no arg) or start / stop the buffbot station',
}

-- Exposed for tests
plugin.cfg = cfg
plugin.rt = rt
plugin.tick = tick
plugin.setEnabled = setEnabled
plugin.processBuffQueue = processBuffQueue
plugin.registeredEvents = function() return registeredEvents end

return plugin
