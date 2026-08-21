---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune DPS Parser v4.0 (Standalone MacroQuest ImGui Script)
-- ----------------------------------------------------------------------------
-- Compatible with MQ LuaJIT (Lua 5.1 syntax safe)
-- Run with:  /lua run triune_dps
--
-- Features:
-- - Dual Top-Level Window Architecture: Independent auto-resizing Mini HUD window (`TriuneDPSMiniWindow`) and Full Parser window (`TriuneDPSWindow`).
-- - Fixed Compact Layout & Spacing: Spacious Mini HUD widget with dedicated target banner, progress bar, and [Full Window] expand button.
-- - Sequential Toolbar Alignment: Clean non-overlapping action buttons across all window states.
-- - Config Persistence: Saves compact mode preference per character across sessions.
-- - First-Person Verb Engine: Supports first-person melee/skills starting directly with a verb (e.g. "punch a cleric...", "kick a cleric...").
-- - Dedicated Critical Hit Engine: Captures `#1# scores a critical hit! (#2#)` and `#1# delivers a critical blast! (#2#)#3#`.
-- - Server Short Combat Log Parser: Supports `#1# for #2#` short damage format (e.g. "Tenekis crushes mob for 204").
-- - Abbreviated Miss Format Handler: Supports `#1# missed #2#` (e.g. "Grimrorik missed a forlorn revenant").
-- - Dynamic Category Calculator: Calculates category metrics directly from attack breakdown tables.
-- - Plaintext space-bounded verb matching: 100% reliable Lua 5.1 parsing for Melee & Skills.
-- - Bulletproof sentence verb parser for Player & Pet Melee / Special Skills (Kick, Bash, Backstab, etc.).
-- - Complete Damage Category Tracking: Melee, Special Skills, Spells (DD), DoTs, Procs/DS.
-- - Detailed Fight History Metrics: Categorized damage tracking logged per encounter (max 25 fights).
-- - Real-time tracking of Player & Multi-Pet damage in EverQuest.
-- - Bulletproof mob target name filtering (fixes "by non-melee" target name bug).
-- - Explicit handler for "was hit by non-melee" environmental/DS combat lines.
-- - Dual-mode Encounter Inspector: Seamless In-Tab Inspection + Forced Focus Modal Popup.
-- - 100% responsive buttons & titlebar close (resolves MQ Lua secondary window focus locking).
-- - Rich chat reporting (/group, /say, /guild, /raid) with category percentages.
-- - Exact player resolution: prevents (Owner: Name) & Swarm pets from misclassifying.
-- - Clean pet name parser: strips (Owner: Name) to group pet melee & spells under one tab.
-- - Chat-driven mob death detection ("has been slain", "You have slain").
-- - Multi-Pet Detailed Breakdown: supports several primary, swarm & trio pets.
-- - Per-pet breakdown tabs (All Pets Combined, Glidequill, Tenekis, Grimrorik, Swarm Pets).
-- - Bulletproof encounter archiving: logs every individual mob fight cleanly.
-- - Comma-stripping damage number parser (handles 1,000+ damage hits cleanly).
-- - Dual singular ("point") & plural ("points") event pattern registration.
-- - Expanded combat verb matrix (headbutt, maul, pummel, rend, rip, sweep).
-- - Handles Player Melee, Spells, DoTs, DS & Pet damage without event shadowing.
-- - Clean script termination via mq.exit() and mq.imgui.destroy on window close.
-- - Configurable combat inactivity timeout, channel reporting (/dps report).
-- - Theme styling adhering to Triune dark design system.
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit') -- LuaJIT bitwise library

local scriptDir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path = scriptDir .. "?.lua;" .. package.path

local VERSION = '4.3'
local cfg = mq.configDir
local MAX_HISTORY = 25

-- ============================================================================
-- Theme & Styling Setup
-- ============================================================================
local GOLD  = { 1.00, 0.70, 0.54, 1 }
local ARC   = { 0.30, 0.70, 1.00, 1 }
local MUTED = { 0.49, 0.56, 0.65, 1 }
local GOOD  = { 0.37, 0.88, 0.64, 1 }
local WARN  = { 1.00, 0.72, 0.30, 1 }
local ERR   = { 0.95, 0.35, 0.35, 1 }
local PURPLE = { 0.75, 0.45, 0.95, 1 }

local MELEE_VERBS = {
    ['hit'] = true, ['hits'] = true,
    ['slash'] = true, ['slashes'] = true,
    ['pierce'] = true, ['pierces'] = true,
    ['crush'] = true, ['crushes'] = true,
    ['bite'] = true, ['bites'] = true,
    ['claw'] = true, ['claws'] = true,
    ['strike'] = true, ['strikes'] = true,
    ['slice'] = true, ['slices'] = true,
    ['gore'] = true, ['gores'] = true,
    ['punch'] = true, ['punches'] = true,
    ['shoot'] = true, ['shoots'] = true,
    ['hand to hand'] = true,
}

local SKILL_VERBS = {
    ['bash'] = true, ['bashes'] = true,
    ['kick'] = true, ['kicks'] = true,
    ['backstab'] = true, ['backstabs'] = true,
    ['frenzy'] = true, ['frenzies'] = true,
    ['flying kick'] = true, ['flying kicks'] = true,
    ['dragon punch'] = true, ['dragon punches'] = true,
    ['eagle strike'] = true, ['eagle strikes'] = true,
    ['tiger claw'] = true, ['tiger claws'] = true,
    ['roundhouse kick'] = true, ['roundhouse kicks'] = true,
    ['slam'] = true, ['slams'] = true,
    ['headbutt'] = true, ['headbutts'] = true,
    ['maul'] = true, ['mauls'] = true,
    ['pummel'] = true, ['pummels'] = true,
    ['rend'] = true, ['rends'] = true,
    ['rip'] = true, ['rips'] = true,
    ['sweep'] = true, ['sweeps'] = true,
    ['finishing blow'] = true, ['finishing blows'] = true,
}

local COMBAT_VERBS = {}
for k, v in pairs(MELEE_VERBS) do COMBAT_VERBS[k] = v end
for k, v in pairs(SKILL_VERBS) do COMBAT_VERBS[k] = v end

-- Sorted list of verbs by length descending to match multi-word verbs first
local SORTED_COMBAT_VERB_LIST = {}
for verb in pairs(COMBAT_VERBS) do
    table.insert(SORTED_COMBAT_VERB_LIST, verb)
end
table.sort(SORTED_COMBAT_VERB_LIST, function(a, b) return #a > #b end)

local function getVerbCategory(verb)
    local lowerV = (verb or ''):lower()
    if SKILL_VERBS[lowerV] then
        return 'Skill'
    elseif MELEE_VERBS[lowerV] then
        return 'Melee'
    end
    return 'Melee'
end

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
    local ImGuiCol = (mq.imgui and mq.imgui.Col) or _G.ImGuiCol or ImGuiCol ---@diagnostic disable-line: undefined-field
    local ImGuiStyleVar = (mq.imgui and mq.imgui.StyleVar) or _G.ImGuiStyleVar or ImGuiStyleVar ---@diagnostic disable-line: undefined-field
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
-- State Tables (Project Standard: ctrl, runtime, petState)
-- ============================================================================
local ctrl = {
    open = true,
    paused = false,
    compact = false,      -- Mini Compact Window mode flag
    combatTimeout = 6.0,   -- Inactivity seconds to auto-end fight
    reportChannel = 'group', -- default channel: 'group', 'say', 'guild', 'raid'
    autoResetOnZone = true,
    showPetBreakdown = true,
}

local runtime = {
    activeTab = 1,
    guiOpen = true,
    inFight = false,
    fightStartTime = 0,
    lastDamageTime = 0,
    currentTargetId = 0,
    currentTargetName = 'None',
    
    -- Current Fight Overall Totals
    playerDamage = 0,
    petDamage = 0,
    totalDamage = 0,
    
    -- Hit / Miss / Crit Counters for Current Fight
    playerHits = 0,
    playerMisses = 0,
    playerCrits = 0,
    petHits = 0,
    petMisses = 0,
    petCrits = 0,
    
    -- Attack Type Breakdown Maps
    playerBreakdown = {},
    petBreakdown = {},
    selectedPetTab = 'All Pets',
    
    -- History of Completed Fights
    history = {},
    nextHistoryId = 1,
    selectedHistoryIndex = 1,
    
    -- Encounter Inspector State
    inspectorOpen = false,
    inspectedFight = nil,
    shouldOpenModal = false,
}

local petState = {
    name = '',
}

-- ============================================================================
-- Dynamic Category Totals Calculator
-- ============================================================================
local function calculateCategoryTotals(playerBreakdown, petBreakdown)
    local totals = { melee = 0, skill = 0, spell = 0, dot = 0, ds = 0 }
    
    local function processTable(tbl)
        if type(tbl) ~= 'table' then return end
        for _, data in pairs(tbl) do
            if type(data) == 'table' then
                local cat = data.category or 'Melee'
                local dmg = data.totalDmg or 0
                if cat == 'Skill' then
                    totals.skill = totals.skill + dmg
                elseif cat == 'Spell' then
                    totals.spell = totals.spell + dmg
                elseif cat == 'DoT' then
                    totals.dot = totals.dot + dmg
                elseif cat == 'Proc/DS' then
                    totals.ds = totals.ds + dmg
                else
                    totals.melee = totals.melee + dmg
                end
            end
        end
    end
    
    processTable(playerBreakdown)
    
    if type(petBreakdown) == 'table' then
        for _, pData in pairs(petBreakdown) do
            if type(pData) == 'table' and type(pData.attacks) == 'table' then
                processTable(pData.attacks)
            end
        end
    end
    
    return totals
end

-- ============================================================================
-- String Utilities & Target Name Filters
-- ============================================================================
local function cleanLine(str)
    if not str then return "" end
    -- Strip ASCII 7 BEL (0x07) MQ color tags like \ax, \ar, \ag, \a-y, etc.
    local s = str:gsub("\a[-%w]*", "")
    -- Strip literal \a string color tags
    s = s:gsub("\\a[-%w]*", "")
    -- Strip ASCII 127 (0x7F) MQ color codes
    s = s:gsub("\127%d*", "")
    -- Strip literal \127 string color codes
    s = s:gsub("\\127%d*", "")
    -- Trim leading/trailing whitespace
    return s:match("^%s*(.-)%s*$") or s
end

local function parseDamageValue(dmgStrRaw)
    if not dmgStrRaw then return nil end
    local cleanStr = dmgStrRaw:gsub(",", "")
    local num = cleanStr:match("(%-?%d+)")
    return tonumber(num)
end

local function isValidMobName(name)
    if not name or name == '' then return false end
    local lower = name:lower()
    if lower:find("non%-melee") or lower:find("nonmelee") or lower:sub(1,3) == 'by '
       or lower:find("healed") or lower:find("been") or lower:find("taken") or lower:find("mana") 
       or lower == 'target' or lower == 'none' or lower == 'unknown' then
        return false
    end
    return true
end

local function isValidCombatTarget(targetStr)
    return isValidMobName(targetStr)
end

local function getMyPlayerName()
    local ok, name = pcall(function() return mq.TLO.Me.CleanName() end)
    if ok and name and name ~= '' then
        return name:lower()
    end
    return ''
end

local function isPlayerActor(actorStr)
    if not actorStr or actorStr == '' then return false end
    -- If string contains (Owner: ...) it is EXPLICITLY a pet belonging to an owner!
    if actorStr:find("%([Oo]wner:") then
        return false
    end
    local cleanActor = actorStr:gsub("%W", ""):lower()
    if cleanActor == 'you' then
        return true
    end
    local myName = getMyPlayerName()
    if myName and myName ~= '' then
        local cleanMyName = myName:gsub("%W", ""):lower()
        if cleanMyName ~= '' and cleanActor == cleanMyName then
            return true
        end
    end
    return false
end

-- ============================================================================
-- Sentence Verb Parser for Melee & Skills (First-Person & Space-Bounded)
-- ============================================================================
local function parseMeleeSentence(sentence)
    if not sentence or sentence == '' then return nil, nil, nil end
    local cleanS = cleanLine(sentence)
    local lowerS = cleanS:lower()
    
    for _, verb in ipairs(SORTED_COMBAT_VERB_LIST) do
        -- Tier 1: Check if line starts directly with the verb (e.g. "punch a cleric...", "kick a cleric...")
        local vPattern = "^" .. verb:gsub("%s+", "%%s+") .. "%s+"
        local sStart, sEnd = lowerS:find(vPattern)
        if sStart then
            local actor = "You"
            local matchedVerb = cleanS:sub(sStart, sEnd):match("^%s*(.-)%s*$")
            local target = cleanS:sub(sEnd + 1):match("^%s*(.-)%s*$")
            if actor and target and target ~= '' then
                return actor, matchedVerb, target
            end
        else
            -- Tier 2: Check for " verb " with leading space (e.g. "Tenekis crushes a forlorn revenant")
            local searchStr = " " .. verb .. " "
            local sStart2, sEnd2 = lowerS:find(searchStr, 1, true)
            if sStart2 then
                local actor = cleanS:sub(1, sStart2 - 1):match("^%s*(.-)%s*$")
                local matchedVerb = cleanS:sub(sStart2 + 1, sEnd2 - 1)
                local target = cleanS:sub(sEnd2 + 1):match("^%s*(.-)%s*$")
                if actor and actor ~= '' and target and target ~= '' then
                    return actor, matchedVerb, target
                end
            end
        end
    end
    
    return nil, nil, nil
end

-- ============================================================================
-- Config Persistence Helper
-- ============================================================================
local function getConfigFilePath()
    local myName = 'Default'
    local ok, name = pcall(function() return mq.TLO.Me.CleanName() end)
    if ok and name and name ~= '' then myName = name end
    return string.format("%s/triune_dps_%s.lua", cfg, myName)
end

local function saveConfig()
    local path = getConfigFilePath()
    local file, err = io.open(path, "w")
    if not file then return end
    file:write("-- Triune DPS Parser Config\nreturn {\n")
    file:write(string.format("    compact = %s,\n", tostring(ctrl.compact)))
    file:write(string.format("    combatTimeout = %.1f,\n", ctrl.combatTimeout))
    file:write(string.format("    reportChannel = %q,\n", ctrl.reportChannel))
    file:write(string.format("    autoResetOnZone = %s,\n", tostring(ctrl.autoResetOnZone)))
    file:write(string.format("    showPetBreakdown = %s,\n", tostring(ctrl.showPetBreakdown)))
    file:write("}\n")
    file:close()
end

local function loadConfig()
    local path = getConfigFilePath()
    local chunk, err = loadfile(path)
    if chunk then
        local ok, data = pcall(chunk)
        if ok and type(data) == 'table' then
            if data.compact ~= nil then ctrl.compact = data.compact end
            if data.combatTimeout then ctrl.combatTimeout = tonumber(data.combatTimeout) or 6.0 end
            if data.reportChannel then ctrl.reportChannel = data.reportChannel end
            if data.autoResetOnZone ~= nil then ctrl.autoResetOnZone = data.autoResetOnZone end
            if data.showPetBreakdown ~= nil then ctrl.showPetBreakdown = data.showPetBreakdown end
        end
    end
end

-- ============================================================================
-- Helper & Calculation Functions
-- ============================================================================
local function getPetName()
    local ok, name = pcall(function() return mq.TLO.Pet.CleanName() end)
    if ok and name and name ~= '' and name ~= 'NULL' then
        petState.name = name
        return name
    end
    return petState.name
end

local function getCleanPetName(actorStr)
    local cleaned = cleanLine(actorStr)
    -- Strip "(Owner: Gennro)" or similar owner brackets
    cleaned = cleaned:gsub("%s*%([Oo]wner:.-%)", "")
    if cleaned:sub(1,5):lower() == 'your ' then
        local pName = getPetName()
        if pName and pName ~= '' and pName ~= 'NULL' then
            return pName
        end
        return "Your Pet"
    end
    return cleaned ~= '' and cleaned or "Pet"
end

local function isPetActor(actorStr)
    if not actorStr or actorStr == '' then return false end
    if isPlayerActor(actorStr) then return false end
    
    -- Explicit owner tag indicates a pet
    if actorStr:find("%([Oo]wner:") then
        return true
    end
    
    local cleanActor = actorStr:gsub("%W", ""):lower()
    
    -- Matches "Your pet" / "your pet"
    if cleanActor == 'yourpet' or cleanActor:find('yourpet') or actorStr:sub(1,8):lower() == 'your pet' then
        return true
    end
    
    -- Check Active Pet Clean Name
    local pName = getPetName()
    if pName and pName ~= '' and pName ~= 'NULL' then
        local cleanPName = pName:gsub("%W", ""):lower()
        if cleanPName ~= '' and (cleanActor == cleanPName or cleanActor:find(cleanPName, 1, true)) then
            return true
        end
    end
    
    -- Check Pet TLO ID & CleanName
    local ok, petId = pcall(function() return mq.TLO.Pet.ID() end)
    if ok and petId and petId > 0 then
        local ok2, cName = pcall(function() return mq.TLO.Pet.CleanName() end)
        if ok2 and cName and cName ~= '' and cName ~= 'NULL' then
            local cleanCName = cName:gsub("%W", ""):lower()
            if cleanCName ~= '' and (cleanActor == cleanCName or cleanActor:find(cleanCName, 1, true)) then
                return true
            end
        end
    end
    
    -- Matches swarm pets / generic pet suffixes (e.g. "...'s pet" or "... pet") or Animated Corpse
    if cleanActor:sub(-3) == 'pet' or cleanActor:find('corpse') or cleanActor:find('animated') then
        return true
    end
    
    -- Any non-player actor that is not a mob target hit is treated as pet/ally
    return true
end

local function getCurrentFightDuration()
    if runtime.fightStartTime == 0 then return 0 end
    local now = mq.gettime()
    local endT = now
    if not runtime.inFight then
        endT = (runtime.lastDamageTime > 0) and runtime.lastDamageTime or now
    end
    local dur = (endT - runtime.fightStartTime) / 1000.0
    return dur > 0 and dur or 0.1
end

local function getFightDPS(dmg, dur)
    if dur <= 0 then return 0 end
    return math.floor((dmg / dur) + 0.5)
end

local function recordHit(sourceTable, attackName, damage, isCrit, isMiss, isPetFlag, category)
    if not sourceTable[attackName] then
        sourceTable[attackName] = {
            count = 0,
            totalDmg = 0,
            minDmg = damage,
            maxDmg = damage,
            crits = 0,
            misses = 0,
            isPet = isPetFlag or false,
            category = category or 'Melee',
        }
    end
    local item = sourceTable[attackName]
    if isMiss then
        item.misses = item.misses + 1
    else
        item.count = item.count + 1
        item.totalDmg = item.totalDmg + damage
        if damage < item.minDmg or item.minDmg == 0 then item.minDmg = damage end
        if damage > item.maxDmg then item.maxDmg = damage end
        if isCrit then item.crits = item.crits + 1 end
    end
end

local function recordPetHit(actorRaw, attackName, damage, isCrit, isMiss, category)
    local petName = getCleanPetName(actorRaw)
    if not runtime.petBreakdown[petName] then
        runtime.petBreakdown[petName] = {
            totalDmg = 0,
            hits = 0,
            misses = 0,
            crits = 0,
            attacks = {},
        }
    end
    local petData = runtime.petBreakdown[petName]
    if isMiss then
        petData.misses = petData.misses + 1
    else
        petData.hits = petData.hits + 1
        petData.totalDmg = petData.totalDmg + damage
        if isCrit then petData.crits = petData.crits + 1 end
    end
    recordHit(petData.attacks, attackName, damage, isCrit, isMiss, true, category or 'Melee')
end

local function deepCopyBreakdown(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = {
            count = v.count,
            totalDmg = v.totalDmg,
            minDmg = v.minDmg,
            maxDmg = v.maxDmg,
            crits = v.crits,
            misses = v.misses,
            isPet = v.isPet,
            category = v.category or 'Melee',
        }
    end
    return copy
end

local function deepCopyMultiPetBreakdown(petMap)
    local copy = {}
    for pName, pData in pairs(petMap) do
        copy[pName] = {
            totalDmg = pData.totalDmg,
            hits = pData.hits,
            misses = pData.misses,
            crits = pData.crits,
            attacks = deepCopyBreakdown(pData.attacks),
        }
    end
    return copy
end

local function resetCurrentFight()
    runtime.inFight = false
    runtime.fightStartTime = 0
    runtime.lastDamageTime = 0
    runtime.currentTargetId = 0
    runtime.currentTargetName = 'None'
    runtime.playerDamage = 0
    runtime.petDamage = 0
    runtime.totalDamage = 0
    runtime.playerHits = 0
    runtime.playerMisses = 0
    runtime.playerCrits = 0
    runtime.petHits = 0
    runtime.petMisses = 0
    runtime.petCrits = 0
    runtime.playerBreakdown = {}
    runtime.petBreakdown = {}
end

local function endFightSession()
    if not runtime.inFight or runtime.totalDamage == 0 then
        runtime.inFight = false
        return
    end
    
    local dur = getCurrentFightDuration()
    local totalDps = getFightDPS(runtime.totalDamage, dur)
    local timestamp = os.date("%H:%M:%S")
    local totals = calculateCategoryTotals(runtime.playerBreakdown, runtime.petBreakdown)
    
    table.insert(runtime.history, 1, {
        id = runtime.nextHistoryId,
        targetName = (isValidMobName(runtime.currentTargetName)) and runtime.currentTargetName or 'Unknown',
        duration = dur,
        totalDmg = runtime.totalDamage,
        playerDmg = runtime.playerDamage,
        petDmg = runtime.petDamage,
        peakDps = totalDps,
        
        -- Categorized Damage Metrics calculated dynamically from breakdown tables
        meleeDmg = totals.melee,
        skillDmg = totals.skill,
        spellDmg = totals.spell,
        dotDmg = totals.dot,
        dsDmg = totals.ds,
        
        playerHits = runtime.playerHits,
        playerMisses = runtime.playerMisses,
        playerCrits = runtime.playerCrits,
        petHits = runtime.petHits,
        petMisses = runtime.petMisses,
        petCrits = runtime.petCrits,
        playerBreakdown = deepCopyBreakdown(runtime.playerBreakdown),
        petBreakdown = deepCopyMultiPetBreakdown(runtime.petBreakdown),
        timestamp = timestamp,
    })
    
    runtime.nextHistoryId = runtime.nextHistoryId + 1
    if #runtime.history > MAX_HISTORY then
        table.remove(runtime.history)
    end
    
    runtime.inFight = false
    runtime.currentTargetId = 0
end

local function startFightIfNeeded(targetName)
    local now = mq.gettime()
    local ok, tid = pcall(function() return mq.TLO.Target.ID() end)
    local targetId = (ok and tid and tid > 0) and tid or 0
    
    local cleanTarget = isValidMobName(targetName) and cleanLine(targetName) or nil
    local tloTargetName = nil
    local ok2, tar = pcall(function() return mq.TLO.Target.CleanName() end)
    if ok2 and tar and isValidMobName(tar) then
        tloTargetName = tar
    end
    
    local validTargetName = cleanTarget or tloTargetName or 'Target'
    
    if not runtime.inFight then
        runtime.inFight = true
        runtime.fightStartTime = now
        runtime.lastDamageTime = now
        runtime.currentTargetId = targetId
        runtime.currentTargetName = validTargetName
        runtime.playerDamage = 0
        runtime.petDamage = 0
        runtime.totalDamage = 0
        runtime.playerHits = 0
        runtime.playerMisses = 0
        runtime.playerCrits = 0
        runtime.petHits = 0
        runtime.petMisses = 0
        runtime.petCrits = 0
        runtime.playerBreakdown = {}
        runtime.petBreakdown = {}
    else
        -- If we are in a fight, but this hit is for a DIFFERENT valid mob target (e.g. Mob A died and we hit Mob B)
        if cleanTarget and isValidMobName(runtime.currentTargetName) and cleanTarget ~= runtime.currentTargetName then
            local timeSinceLastDmg = (now - runtime.lastDamageTime) / 1000.0
            if timeSinceLastDmg > 1.5 then
                endFightSession()
                startFightIfNeeded(targetName)
                return
            end
        end
        
        runtime.lastDamageTime = now
        if targetId > 0 and runtime.currentTargetId == 0 then
            runtime.currentTargetId = targetId
        end
        if isValidMobName(validTargetName) and (not isValidMobName(runtime.currentTargetName)) then
            runtime.currentTargetName = validTargetName
        end
    end
end

-- ============================================================================
-- Unified Event Handlers (Dispatches Player & Pet damage without shadowing)
-- ============================================================================

-- 1. Unified Melee & Special Skill Hit Handler: "#1# for #2#" or "#1# for #2# points of damage#3#"
local function onUnifiedMeleeHit(line, sentenceRaw, dmgStrRaw, extraRaw)
    if ctrl.paused then return end
    
    -- Filter out non-melee spell lines
    if sentenceRaw:find("non%-melee") or (extraRaw and extraRaw:find("non%-melee")) then
        return
    end
    
    local actor, verb, target = parseMeleeSentence(sentenceRaw)
    if not actor or not verb or not target then return end
    if not isValidCombatTarget(target) then return end
    
    local dmg = parseDamageValue(dmgStrRaw)
    if not dmg or dmg <= 0 then return end
    
    local cat = getVerbCategory(verb)
    local extra = cleanLine(extraRaw or '')
    local isCrit = (extra:find("Critical") or extra:find("Crippling") or line:find("Critical") or line:find("Crippling")) and true or false
    
    if isPlayerActor(actor) then
        -- Player Hit
        startFightIfNeeded(target)
        if isCrit then runtime.playerCrits = runtime.playerCrits + 1 end
        runtime.playerHits = runtime.playerHits + 1
        runtime.playerDamage = runtime.playerDamage + dmg
        runtime.totalDamage = runtime.totalDamage + dmg
        
        local attackName = verb:sub(1,1):upper() .. verb:sub(2):lower()
        recordHit(runtime.playerBreakdown, attackName, dmg, isCrit, false, false, cat)
    elseif isPetActor(actor) then
        -- Pet Hit
        startFightIfNeeded(target)
        if isCrit then runtime.petCrits = runtime.petCrits + 1 end
        runtime.petHits = runtime.petHits + 1
        runtime.petDamage = runtime.petDamage + dmg
        runtime.totalDamage = runtime.totalDamage + dmg
        
        local attackName = verb:sub(1,1):upper() .. verb:sub(2):lower()
        recordPetHit(actor, attackName, dmg, isCrit, false, cat)
    end
end

-- 2. Unified Non-Melee / Spell Hit Handler: "#1# hit #2# for #3# points of non-melee damage#4#"
local function onUnifiedSpellHit(line, actorRaw, targetRaw, dmgStrRaw, extraRaw)
    if ctrl.paused then return end
    local actor = cleanLine(actorRaw)
    local target = cleanLine(targetRaw)
    local extra = cleanLine(extraRaw)
    
    if isValidCombatTarget(target) then
        local dmg = parseDamageValue(dmgStrRaw)
        if dmg then
            if isPlayerActor(actor) then
                -- Player Direct Damage Hit ("You hit a mob for X non-melee damage")
                startFightIfNeeded(target)
                local isCrit = extra:find("Critical") and true or false
                if isCrit then runtime.playerCrits = runtime.playerCrits + 1 end
                runtime.playerHits = runtime.playerHits + 1
                runtime.playerDamage = runtime.playerDamage + dmg
                runtime.totalDamage = runtime.totalDamage + dmg
                local spellName = extra:match("%((.-)%)") or 'Spell DD'
                recordHit(runtime.playerBreakdown, spellName, dmg, isCrit, false, false, 'Spell')
            elseif isPetActor(actor) then
                -- Pet Spell Hit ("Glidequill (Owner: Gennro) hit a mob for X non-melee damage. (Spell)")
                startFightIfNeeded(target)
                runtime.petHits = runtime.petHits + 1
                runtime.petDamage = runtime.petDamage + dmg
                runtime.totalDamage = runtime.totalDamage + dmg
                local spellName = extra:match("%((.-)%)") or 'Pet Spell'
                recordPetHit(actor, spellName, dmg, false, false, 'Spell')
            end
        end
    end
end

-- 3. Player DoT Hit: "#1# has taken #2# points of damage from your #3#."
local function onPlayerDoTHit(line, targetRaw, dmgStrRaw, spellRaw)
    if ctrl.paused then return end
    local target = cleanLine(targetRaw)
    local spell = cleanLine(spellRaw)
    
    if isValidCombatTarget(target) then
        local dmg = parseDamageValue(dmgStrRaw)
        if dmg then
            startFightIfNeeded(target)
            runtime.playerHits = runtime.playerHits + 1
            runtime.playerDamage = runtime.playerDamage + dmg
            runtime.totalDamage = runtime.totalDamage + dmg
            local attackName = spell .. " (DoT)"
            recordHit(runtime.playerBreakdown, attackName, dmg, false, false, false, 'DoT')
        end
    end
end

-- 4. Player Damage Shield: "#1# is #2# by your #3# for #4# points of damage."
local function onPlayerDSHit(line, targetRaw, verbRaw, dsTypeRaw, dmgStrRaw)
    if ctrl.paused then return end
    local target = cleanLine(targetRaw)
    
    if isValidCombatTarget(target) then
        local dmg = parseDamageValue(dmgStrRaw)
        if dmg then
            startFightIfNeeded(target)
            runtime.playerHits = runtime.playerHits + 1
            runtime.playerDamage = runtime.playerDamage + dmg
            runtime.totalDamage = runtime.totalDamage + dmg
            recordHit(runtime.playerBreakdown, 'Damage Shield', dmg, false, false, false, 'Proc/DS')
        end
    end
end

-- 5. Dedicated Critical Hit & Critical Blast Event Handlers
local function onCriticalHit(line, actorRaw, dmgStrRaw)
    if ctrl.paused then return end
    local actor = cleanLine(actorRaw)
    local dmg = parseDamageValue(dmgStrRaw)
    
    if isPlayerActor(actor) then
        runtime.playerCrits = runtime.playerCrits + 1
        for _, item in pairs(runtime.playerBreakdown) do
            if dmg == nil or item.maxDmg == dmg or item.minDmg == dmg or item.totalDmg >= (dmg or 0) then
                item.crits = item.crits + 1
                break
            end
        end
    elseif isPetActor(actor) then
        runtime.petCrits = runtime.petCrits + 1
        local petName = getCleanPetName(actor)
        local petData = runtime.petBreakdown[petName]
        if petData then
            petData.crits = petData.crits + 1
            for _, item in pairs(petData.attacks) do
                if dmg == nil or item.maxDmg == dmg or item.minDmg == dmg or item.totalDmg >= (dmg or 0) then
                    item.crits = item.crits + 1
                    break
                end
            end
        end
    end
end

local function onCriticalBlast(line, actorRaw, dmgStrRaw, spellRaw)
    if ctrl.paused then return end
    local actor = cleanLine(actorRaw)
    local dmg = parseDamageValue(dmgStrRaw)
    local spell = cleanLine(spellRaw or '')
    spell = spell:match("%((.-)%)") or spell
    
    if isPlayerActor(actor) then
        runtime.playerCrits = runtime.playerCrits + 1
        if spell ~= '' and runtime.playerBreakdown[spell] then
            runtime.playerBreakdown[spell].crits = runtime.playerBreakdown[spell].crits + 1
        end
    elseif isPetActor(actor) then
        runtime.petCrits = runtime.petCrits + 1
        local petName = getCleanPetName(actor)
        local petData = runtime.petBreakdown[petName]
        if petData then
            petData.crits = petData.crits + 1
            if spell ~= '' and petData.attacks[spell] then
                petData.attacks[spell].crits = petData.attacks[spell].crits + 1
            end
        end
    end
end

-- 6. Unified Miss Handler: "You try to #1# #2#, but miss!" / "#1# missed #2#"
local function onUnifiedMiss(line, actorRaw, verbOrTargetRaw, targetRaw)
    if ctrl.paused then return end
    
    if targetRaw and targetRaw ~= '' then
        -- Full format: "You try to kick mob, but miss!" or "Pet tried to kick mob, but missed!"
        local actor = cleanLine(actorRaw)
        local verb = cleanLine(verbOrTargetRaw)
        local target = cleanLine(targetRaw)
        
        if isValidCombatTarget(target) and runtime.inFight then
            local cat = getVerbCategory(verb)
            local attackName = verb:sub(1,1):upper() .. verb:sub(2):lower()
            if isPlayerActor(actor) then
                runtime.playerMisses = runtime.playerMisses + 1
                recordHit(runtime.playerBreakdown, attackName, 0, false, true, false, cat)
            elseif isPetActor(actor) then
                runtime.petMisses = runtime.petMisses + 1
                recordPetHit(actor, attackName, 0, false, true, cat)
            end
        end
    else
        -- Abbreviated format: "Grimrorik missed a forlorn revenant"
        local sentence = cleanLine(actorRaw)
        local actor, target = sentence:match("^%s*(.-)%s+missed%s+(.-)%s*$")
        if actor and target and isValidCombatTarget(target) and runtime.inFight then
            if isPlayerActor(actor) then
                runtime.playerMisses = runtime.playerMisses + 1
                recordHit(runtime.playerBreakdown, 'Miss', 0, false, true, false, 'Melee')
            elseif isPetActor(actor) then
                runtime.petMisses = runtime.petMisses + 1
                recordPetHit(actor, 'Miss', 0, false, true, 'Melee')
            end
        end
    end
end

-- 7. Chat-driven Mob Slain Event Handler
local function onMobSlain(line, targetRaw)
    if not runtime.inFight then return end
    local target = cleanLine(targetRaw)
    target = target:gsub("[!%.%?]+$", "")
    if isValidMobName(target) then
        endFightSession()
    end
end

-- 8. Mob Damaged by DS / Environmental Non-Melee
local function onMobHitByNonMelee(line, mobRaw, dmgStrRaw, extraRaw)
    if ctrl.paused then return end
    local mob = cleanLine(mobRaw)
    if isValidMobName(mob) then
        local dmg = parseDamageValue(dmgStrRaw)
        if dmg then
            startFightIfNeeded(mob)
            runtime.playerHits = runtime.playerHits + 1
            runtime.playerDamage = runtime.playerDamage + dmg
            runtime.totalDamage = runtime.totalDamage + dmg
            recordHit(runtime.playerBreakdown, 'Damage Shield / Non-Melee', dmg, false, false, false, 'Proc/DS')
        end
    end
end

-- Register Event Listeners
local function registerEvents()
    -- Standard & Server Abbreviated Melee & Skill Hit Patterns
    -- Matches "Tenekis crushes a forlorn revenant for 204" and "punch a cleric of hate for 607"
    mq.event('DPS_MeleeHitShort', '#1# for #2#', onUnifiedMeleeHit)
    
    -- Dedicated Critical Hit & Critical Blast Event Patterns
    mq.event('DPS_CritHit', '#1# scores a critical hit! (#2#)', onCriticalHit)
    mq.event('DPS_CritBlast', '#1# delivers a critical blast! (#2#)#3#', onCriticalBlast)
    
    -- Spell / Non-Melee Patterns (Plural & Singular)
    mq.event('DPS_SpellHitPlural', '#1# hit #2# for #3# points of non-melee damage#4#', onUnifiedSpellHit)
    mq.event('DPS_SpellHitSingular', '#1# hit #2# for #3# point of non-melee damage#4#', onUnifiedSpellHit)
    mq.event('DPS_ProcHitPlural', '#1# is struck by #2# for #3# points of damage#4#', onUnifiedSpellHit)
    mq.event('DPS_ProcHitSingular', '#1# is struck by #2# for #3# point of damage#4#', onUnifiedSpellHit)
    
    -- Non-Melee DS / Environmental Patterns
    mq.event('DPS_MobNonMeleePlural', '#1# was hit by non-melee for #2# points of damage#3#', onMobHitByNonMelee)
    mq.event('DPS_MobNonMeleeSingular', '#1# was hit by non-melee for #2# point of damage#3#', onMobHitByNonMelee)
    
    -- DoT Patterns
    mq.event('DPS_PlayerDoT1', '#1# has taken #2# points of damage from your #3#.', onPlayerDoTHit)
    mq.event('DPS_PlayerDoT2', '#1# has taken #2# point of damage from your #3#.', onPlayerDoTHit)
    mq.event('DPS_PlayerDoT3', '#1# has taken #2# damage from your #3#.', onPlayerDoTHit)
    
    -- Damage Shield Patterns
    mq.event('DPS_PlayerDSPlural', '#1# is #2# by your #3# for #4# points of damage.', onPlayerDSHit)
    mq.event('DPS_PlayerDSSingular', '#1# is #2# by your #3# for #4# point of damage.', onPlayerDSHit)
    
    -- Standard & Abbreviated Miss Patterns
    mq.event('DPS_PlayerMissStandard', 'You try to #1# #2#, but miss!', onUnifiedMiss)
    mq.event('DPS_PetMissStandard', '#1# tried to #2# #3#, but missed!', onUnifiedMiss)
    mq.event('DPS_MissShort', '#1# missed #2#', onUnifiedMiss)
    
    -- Chat-driven Mob Slain Events
    mq.event('DPS_MobSlain1', '#1# has been slain#*#', onMobSlain)
    mq.event('DPS_MobSlain2', 'You have slain #1#!', onMobSlain)
    
    -- Zone Change Auto-Reset
    mq.event('DPS_Zone', 'You have entered #*#', function()
        if ctrl.autoResetOnZone then
            resetCurrentFight()
        end
    end)
end

-- ============================================================================
-- Report Generator
-- ============================================================================
local function reportDPS(channelOverride)
    local channel = channelOverride or ctrl.reportChannel or 'group'
    local dur = getCurrentFightDuration()
    local totalDps = getFightDPS(runtime.totalDamage, dur)
    local playerDps = getFightDPS(runtime.playerDamage, dur)
    local petDps = getFightDPS(runtime.petDamage, dur)
    
    local playerPct = runtime.totalDamage > 0 and math.floor((runtime.playerDamage / runtime.totalDamage * 100) + 0.5) or 0
    local petPct = runtime.totalDamage > 0 and math.floor((runtime.petDamage / runtime.totalDamage * 100) + 0.5) or 0
    
    local target = (runtime.currentTargetName ~= '' and runtime.currentTargetName ~= 'None') and runtime.currentTargetName or 'Combat'
    
    local msg = string.format("[Triune DPS] Target: %s | Dur: %.0fs | Combined: %d DPS (%s dmg)",
        target, dur, totalDps, tostring(runtime.totalDamage))
        
    local totals = calculateCategoryTotals(runtime.playerBreakdown, runtime.petBreakdown)
    local mPct = runtime.totalDamage > 0 and math.floor((totals.melee / runtime.totalDamage * 100) + 0.5) or 0
    local skPct = runtime.totalDamage > 0 and math.floor((totals.skill / runtime.totalDamage * 100) + 0.5) or 0
    local spPct = runtime.totalDamage > 0 and math.floor((totals.spell / runtime.totalDamage * 100) + 0.5) or 0
    local dotPct = runtime.totalDamage > 0 and math.floor((totals.dot / runtime.totalDamage * 100) + 0.5) or 0
    
    msg = msg .. string.format(" | Types: Melee %d%%, Skill %d%%, Spell %d%%, DoT %d%%", mPct, skPct, spPct, dotPct)
    
    if runtime.petDamage > 0 then
        msg = msg .. string.format(" | Player: %d DPS (%d%%) | Pet: %d DPS (%d%%)", playerDps, playerPct, petDps, petPct)
    else
        msg = msg .. string.format(" | Player: %d DPS", playerDps)
    end
    
    local cmd = '/' .. channel .. ' ' .. msg
    mq.cmd(cmd)
end

local function reportHistoricalFight(h, channelOverride)
    if not h then return end
    local channel = channelOverride or ctrl.reportChannel or 'group'
    local playerDps = getFightDPS(h.playerDmg, h.duration)
    local petDps = getFightDPS(h.petDmg, h.duration)
    
    local playerPct = h.totalDmg > 0 and math.floor((h.playerDmg / h.totalDmg * 100) + 0.5) or 0
    local petPct = h.totalDmg > 0 and math.floor((h.petDmg / h.totalDmg * 100) + 0.5) or 0
    
    local mPct = h.totalDmg > 0 and math.floor(((h.meleeDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local skPct = h.totalDmg > 0 and math.floor(((h.skillDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local spPct = h.totalDmg > 0 and math.floor(((h.spellDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local dotPct = h.totalDmg > 0 and math.floor(((h.dotDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    
    local msg = string.format("[Triune DPS Log] Target: %s | Dur: %.0fs | Combined: %d DPS (%s dmg)",
        h.targetName, h.duration, h.peakDps, tostring(h.totalDmg))
        
    msg = msg .. string.format(" | Types: Melee %d%%, Skill %d%%, Spell %d%%, DoT %d%%", mPct, skPct, spPct, dotPct)
        
    if h.petDmg > 0 then
        msg = msg .. string.format(" | Player: %d DPS (%d%%) | Pet: %d DPS (%d%%)", playerDps, playerPct, petDps, petPct)
    else
        msg = msg .. string.format(" | Player: %d DPS", playerDps)
    end
    
    local cmd = '/' .. channel .. ' ' .. msg
    mq.cmd(cmd)
end

-- ============================================================================
-- ImGui Rendering Engine (Guaranteed Unique IDs Across Windows)
-- ============================================================================
local function renderBreakdownTable(breakdownMap, showSourceColumn, tableId)
    local tId = tableId or "BreakdownTable"
    if not ImGui.BeginTable(tId, showSourceColumn and 10 or 9, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)) then
        return
    end
    
    if showSourceColumn then
        ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 55)
    end
    ImGui.TableSetupColumn("Category", ImGuiTableColumnFlags.WidthFixed, 65)
    ImGui.TableSetupColumn("Attack / Spell Name", ImGuiTableColumnFlags.WidthStretch, 2.0)
    ImGui.TableSetupColumn("Hits", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Total Dmg", ImGuiTableColumnFlags.WidthFixed, 70)
    ImGui.TableSetupColumn("Min", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Max", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Avg", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Crits", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Crit %", ImGuiTableColumnFlags.WidthFixed, 50)
    ImGui.TableHeadersRow()
    
    local sortedKeys = {}
    for name in pairs(breakdownMap) do table.insert(sortedKeys, name) end
    table.sort(sortedKeys, function(a,b) return breakdownMap[a].totalDmg > breakdownMap[b].totalDmg end)
    
    for _, name in ipairs(sortedKeys) do
        local data = breakdownMap[name]
        local avg = data.count > 0 and math.floor((data.totalDmg / data.count) + 0.5) or 0
        local critPct = data.count > 0 and math.floor((data.crits / data.count * 100) + 0.5) or 0
        local cat = data.category or 'Melee'
        
        ImGui.TableNextRow()
        if showSourceColumn then
            ImGui.TableNextColumn()
            if data.isPet then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "[Pet]")
            else
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "[Player]")
            end
        end
        
        -- Category Badge Column
        ImGui.TableNextColumn()
        if cat == 'Skill' then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "[Skill]")
        elseif cat == 'Spell' then
            ImGui.TextColored(PURPLE[1], PURPLE[2], PURPLE[3], PURPLE[4], "[Spell]")
        elseif cat == 'DoT' then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], "[DoT]")
        elseif cat == 'Proc/DS' then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "[DS/Proc]")
        else
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "[Melee]")
        end
        
        ImGui.TableNextColumn()
        local labelCol = data.isPet and ARC or (showSourceColumn and GOLD or ARC)
        ImGui.TextColored(labelCol[1], labelCol[2], labelCol[3], labelCol[4], name)
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.count))
        ImGui.TableNextColumn()
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], tostring(data.totalDmg))
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.minDmg))
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.maxDmg))
        ImGui.TableNextColumn()
        ImGui.Text(tostring(avg))
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.crits))
        ImGui.TableNextColumn()
        ImGui.Text(string.format("%d%%", critPct))
    end
    
    ImGui.EndTable()
end

local function getCombinedPetAttackMap(petMap)
    local combined = {}
    for pName, pData in pairs(petMap) do
        for atkName, atkData in pairs(pData.attacks) do
            if not combined[atkName] then
                combined[atkName] = {
                    count = atkData.count,
                    totalDmg = atkData.totalDmg,
                    minDmg = atkData.minDmg,
                    maxDmg = atkData.maxDmg,
                    crits = atkData.crits,
                    misses = atkData.misses,
                    isPet = true,
                    category = atkData.category or 'Melee',
                }
            else
                local c = combined[atkName]
                c.count = c.count + atkData.count
                c.totalDmg = c.totalDmg + atkData.totalDmg
                if atkData.minDmg < c.minDmg or c.minDmg == 0 then c.minDmg = atkData.minDmg end
                if atkData.maxDmg > c.maxDmg then c.maxDmg = atkData.maxDmg end
                c.crits = c.crits + atkData.crits
                c.misses = c.misses + atkData.misses
            end
        end
    end
    return combined
end

local function getCombinedOverviewBreakdownMap()
    local combined = {}
    for name, data in pairs(runtime.playerBreakdown) do
        combined[name] = data
    end
    for pName, pData in pairs(runtime.petBreakdown) do
        for atkName, atkData in pairs(pData.attacks) do
            local keyName = pName .. " (" .. atkName .. ")"
            combined[keyName] = atkData
        end
    end
    return combined
end

local function getHistoricalOverviewBreakdownMap(h)
    local combined = {}
    if not h then return combined end
    for name, data in pairs(h.playerBreakdown or {}) do
        combined[name] = data
    end
    if type(h.petBreakdown) == 'table' then
        for pName, pData in pairs(h.petBreakdown) do
            if type(pData) == 'table' and pData.attacks then
                for atkName, atkData in pairs(pData.attacks) do
                    local keyName = pName .. " (" .. atkName .. ")"
                    combined[keyName] = atkData
                end
            end
        end
    end
    return combined
end

local function renderMultiPetDetails(petMap, tabBarId, tableIdPrefix, fightPetDmg)
    local petNames = {}
    for name in pairs(petMap) do
        table.insert(petNames, name)
    end
    table.sort(petNames)
    
    if #petNames == 0 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "No Active Pet Damage Recorded")
        return
    end
    
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Pet Damage Breakdown:")
    ImGui.Spacing()
    
    local tbId = tabBarId or "MultiPetTabBar"
    local tPrefix = tableIdPrefix or "PetTable"
    local totalPetDmg = fightPetDmg or runtime.petDamage
    
    if ImGui.BeginTabBar(tbId) then
        -- Tab 1: All Pets Combined
        if ImGui.BeginTabItem("All Pets Combined##" .. tbId) then
            local combinedAttacks = getCombinedPetAttackMap(petMap)
            renderBreakdownTable(combinedAttacks, false, tPrefix .. "_Combined")
            ImGui.EndTabItem()
        end
        
        -- Individual Tabs per Pet Name
        for _, pName in ipairs(petNames) do
            local pData = petMap[pName]
            local petPct = totalPetDmg > 0 and math.floor((pData.totalDmg / totalPetDmg * 100) + 0.5) or 0
            local tabLabel = string.format("%s (%d Dmg - %d%%)##%s_%s", pName, pData.totalDmg, petPct, tbId, pName)
            
            if ImGui.BeginTabItem(tabLabel) then
                local petTotalAttacks = pData.hits + pData.misses
                local petAcc = petTotalAttacks > 0 and math.floor((pData.hits / petTotalAttacks * 100) + 0.5) or 0
                
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("Pet Name: %s", pName))
                ImGui.SameLine(200)
                ImGui.Text(string.format("Hits: %d | Misses: %d | Accuracy: %d%%", pData.hits, pData.misses, petAcc))
                ImGui.Spacing()
                
                renderBreakdownTable(pData.attacks, false, tPrefix .. "_" .. pName:gsub("%W",""))
                ImGui.EndTabItem()
            end
        end
        
        ImGui.EndTabBar()
    end
end

-- ============================================================================
-- Shared Historical Encounter Inspector Renderer
-- ============================================================================
local function renderHistoricalInspector(h, inTabMode)
    if not h then return end
    
    -- Header Toolbar
    if inTabMode then
        if ImGui.Button("< Back to Fight List##InspectBackBtn", 140, 24) then
            runtime.inspectedFight = nil
            runtime.inspectorOpen = false
            return
        end
        ImGui.SameLine()
        if ImGui.Button("Report Fight##InspectReportBtnTab", 100, 24) then
            reportHistoricalFight(h)
        end
        ImGui.SameLine()
        if ImGui.Button("Pop Out Window##InspectPopOutBtn", 120, 24) then
            runtime.inspectorOpen = true
            runtime.shouldOpenModal = true
        end
        ImGui.Spacing()
    else
        if ImGui.Button("Report Fight##InspectReportBtnModal", 100, 24) then
            reportHistoricalFight(h)
        end
        ImGui.SameLine()
        if ImGui.Button("Close Inspector##InspectCloseBtnModal", 110, 24) then
            runtime.inspectorOpen = false
            runtime.inspectedFight = nil
            ImGui.CloseCurrentPopup()
            return
        end
        ImGui.Spacing()
    end
    
    -- Stats Banner
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Target:")
    ImGui.SameLine()
    ImGui.TextColored(1, 1, 1, 1, h.targetName)
    ImGui.SameLine(220)
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Time:")
    ImGui.SameLine()
    ImGui.Text(h.timestamp)
    ImGui.SameLine(360)
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Duration:")
    ImGui.SameLine()
    ImGui.Text(string.format("%.1fs", h.duration))
    
    ImGui.Separator()
    
    -- Key Performance Summary Cards
    local cardChildId = inTabMode and "InspectTabSummaryCards" or "InspectModalSummaryCards"
    ImGui.BeginChild(cardChildId, 0, 65, true)
    
    local totalDps = h.peakDps
    local playerDps = getFightDPS(h.playerDmg, h.duration)
    local petDps = getFightDPS(h.petDmg, h.duration)
    local playerPct = h.totalDmg > 0 and math.floor((h.playerDmg / h.totalDmg * 100) + 0.5) or 0
    local petPct = h.totalDmg > 0 and math.floor((h.petDmg / h.totalDmg * 100) + 0.5) or 0
    
    -- Combined DPS Card
    ImGui.BeginGroup()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "COMBINED DPS")
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(totalDps))
    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Total Dmg", h.totalDmg))
    ImGui.EndGroup()
    
    ImGui.SameLine(160)
    -- Player DPS Card
    ImGui.BeginGroup()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "PLAYER DPS")
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], tostring(playerDps))
    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Dmg (%d%%)", h.playerDmg, playerPct))
    ImGui.EndGroup()
    
    ImGui.SameLine(320)
    -- Pet DPS Card
    ImGui.BeginGroup()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "PET DPS")
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(petDps))
    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Dmg (%d%%)", h.petDmg, petPct))
    ImGui.EndGroup()
    
    ImGui.EndChild()
    
    -- Contribution Progress Bar
    local pFrac = h.totalDmg > 0 and (h.playerDmg / h.totalDmg) or 0
    ImGui.ProgressBar(pFrac, -1, 14, string.format("Player %d%%  |  Pet %d%%", playerPct, petPct))
    
    ImGui.Spacing()
    
    -- Damage Type Category Metric Badges Summary
    local mPct = h.totalDmg > 0 and math.floor(((h.meleeDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local skPct = h.totalDmg > 0 and math.floor(((h.skillDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local spPct = h.totalDmg > 0 and math.floor(((h.spellDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local dotPct = h.totalDmg > 0 and math.floor(((h.dotDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    local dsPct = h.totalDmg > 0 and math.floor(((h.dsDmg or 0) / h.totalDmg * 100) + 0.5) or 0
    
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Category Metrics:")
    ImGui.SameLine()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format("Melee: %d (%d%%) | Skills: %d (%d%%) | Spells: %d (%d%%) | DoTs: %d (%d%%) | DS: %d (%d%%)",
        h.meleeDmg or 0, mPct, h.skillDmg or 0, skPct, h.spellDmg or 0, spPct, h.dotDmg or 0, dotPct, h.dsDmg or 0, dsPct))
        
    ImGui.Spacing()
    
    -- Navigation Tabs inside Inspector
    local mainTbId = inTabMode and "InspectTabMainTabBar" or "InspectModalMainTabBar"
    local tPrefix = inTabMode and "InspectTab" or "InspectModal"
    
    if ImGui.BeginTabBar(mainTbId) then
        
        -- Overview Breakdown
        if ImGui.BeginTabItem("Overview##" .. tPrefix .. "OverviewTab") then
            ImGui.Spacing()
            local combinedMap = getHistoricalOverviewBreakdownMap(h)
            renderBreakdownTable(combinedMap, true, tPrefix .. "OverviewTable")
            ImGui.EndTabItem()
        end
        
        -- Player Details
        if ImGui.BeginTabItem("Player Details##" .. tPrefix .. "PlayerTab") then
            ImGui.Spacing()
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Historical Player Damage Breakdown:")
            renderBreakdownTable(h.playerBreakdown or {}, false, tPrefix .. "PlayerTable")
            ImGui.EndTabItem()
        end
        
        -- Pet Details
        if ImGui.BeginTabItem("Pet Details##" .. tPrefix .. "PetTab") then
            ImGui.Spacing()
            renderMultiPetDetails(h.petBreakdown or {}, tPrefix .. "MultiPetTabBar", tPrefix .. "PetTable", h.petDmg)
            ImGui.EndTabItem()
        end
        
        ImGui.EndTabBar()
    end
end

-- ============================================================================
-- Standalone Compact Mini HUD Window Renderer
-- ============================================================================
local function drawMiniDpsGui()
    if not ctrl.open or not ctrl.compact then return end
    
    pushTheme()
    local open, draw = ImGui.Begin("Triune DPS Mini v" .. VERSION .. "###TriuneDPSMiniWindow", ctrl.open, ImGuiWindowFlags.AlwaysAutoResize)
    ctrl.open = open
    if not open then
        ctrl.open = false
        runtime.guiOpen = false
        ctrl.compact = false
        ImGui.End()
        popTheme()
        return
    end
    
    if draw then
        local dur = getCurrentFightDuration()
        local totalDps = getFightDPS(runtime.totalDamage, dur)
        local playerDps = getFightDPS(runtime.playerDamage, dur)
        local petDps = getFightDPS(runtime.petDamage, dur)
        local playerPct = runtime.totalDamage > 0 and math.floor((runtime.playerDamage / runtime.totalDamage * 100) + 0.5) or 0
        local petPct = runtime.totalDamage > 0 and math.floor((runtime.petDamage / runtime.totalDamage * 100) + 0.5) or 0
        
        -- Header Row: Target & Duration
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Target:")
        ImGui.SameLine()
        local targetDisp = (runtime.currentTargetName ~= '' and runtime.currentTargetName ~= 'None') and runtime.currentTargetName or 'Idle'
        ImGui.TextColored(1, 1, 1, 1, targetDisp)
        ImGui.SameLine(180)
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Time:")
        ImGui.SameLine()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format("%.1fs", dur))
        
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        
        -- Row 2: Combined DPS
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Combined:")
        ImGui.SameLine()
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("%d DPS", totalDps))
        ImGui.SameLine()
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("(%d Dmg)", runtime.totalDamage))
        
        ImGui.Spacing()
        
        -- Row 3: Player / Pet Split
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format("Player: %d DPS", playerDps))
        if runtime.petDamage > 0 or runtime.petHits > 0 then
            ImGui.SameLine(150)
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format("Pet: %d DPS", petDps))
        end
        
        ImGui.Spacing()
        
        -- Row 4: Contribution Bar
        local pFrac = runtime.totalDamage > 0 and (runtime.playerDamage / runtime.totalDamage) or 0
        ImGui.ProgressBar(pFrac, 260, 14, string.format("Player %d%% | Pet %d%%", playerPct, petPct))
        
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        
        -- Row 5: Action Controls
        if ImGui.Button(ctrl.paused and "Resume##MiniPauseBtn" or "Pause##MiniPauseBtn", 60, 22) then
            ctrl.paused = not ctrl.paused
        end
        ImGui.SameLine()
        if ImGui.Button("Reset##MiniResetBtn", 52, 22) then
            resetCurrentFight()
        end
        ImGui.SameLine()
        if ImGui.Button("Report##MiniReportBtn", 58, 22) then
            reportDPS()
        end
        ImGui.SameLine()
        if ImGui.Button("Full Window##MiniFullBtn", 80, 22) then
            ctrl.compact = false
            saveConfig()
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Close mini view and expand into full DPS Parser window")
        end
    end
    
    ImGui.End()
    popTheme()
end

-- ============================================================================
-- Main Full DPS Window Renderer
-- ============================================================================
local function drawDpsGui()
    if not ctrl.open or ctrl.compact then return end
    
    pushTheme()
    local open, draw = ImGui.Begin("Triune DPS Parser v" .. VERSION .. "###TriuneDPSWindow", ctrl.open)
    ctrl.open = open
    if not open then
        ctrl.open = false
        runtime.guiOpen = false
        runtime.inspectorOpen = false
        ImGui.End()
        popTheme()
        return
    end
    if draw then
        local dur = getCurrentFightDuration()
        local totalDps = getFightDPS(runtime.totalDamage, dur)
        local playerDps = getFightDPS(runtime.playerDamage, dur)
        local petDps = getFightDPS(runtime.petDamage, dur)
        local playerPct = runtime.totalDamage > 0 and math.floor((runtime.playerDamage / runtime.totalDamage * 100) + 0.5) or 0
        local petPct = runtime.totalDamage > 0 and math.floor((runtime.petDamage / runtime.totalDamage * 100) + 0.5) or 0
        
        -- Header Stats Banner
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Target:")
        ImGui.SameLine()
        ImGui.TextColored(1, 1, 1, 1, runtime.currentTargetName)
        ImGui.SameLine(220)
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Status:")
        ImGui.SameLine()
        if ctrl.paused then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], "PAUSED")
        elseif runtime.inFight then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], "COMBAT")
        else
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "IDLE")
        end
        ImGui.SameLine(360)
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Duration:")
        ImGui.SameLine()
        ImGui.Text(string.format("%.1fs", dur))
        
        ImGui.Separator()
        
        -- Control Action Toolbar (Sequential SameLine without hardcoded offsets to prevent overlaps)
        if ImGui.Button(ctrl.paused and "Resume" or "Pause", 70, 24) then
            ctrl.paused = not ctrl.paused
        end
        ImGui.SameLine()
        if ImGui.Button("End Fight", 75, 24) then
            endFightSession()
        end
        ImGui.SameLine()
        if ImGui.Button("Reset", 65, 24) then
            resetCurrentFight()
        end
        ImGui.SameLine()
        if ImGui.Button("Report", 70, 24) then
            reportDPS()
        end
        ImGui.SameLine()
        if ImGui.Button("Compact Mode", 95, 24) then
            ctrl.compact = true
            saveConfig()
        end
        ImGui.SameLine()
        if ImGui.Button("Clear History", 95, 24) then
            runtime.history = {}
            runtime.inspectorOpen = false
            runtime.inspectedFight = nil
        end
        
        ImGui.Separator()
        
        -- Key Performance Metrics Summary Cards
        ImGui.BeginChild("MainDpsSummaryCards", 0, 65, true)
        
        -- Combined DPS Card
        ImGui.BeginGroup()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "COMBINED DPS")
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(totalDps))
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Total Dmg", runtime.totalDamage))
        ImGui.EndGroup()
        
        ImGui.SameLine(160)
        -- Player DPS Card
        ImGui.BeginGroup()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "PLAYER DPS")
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], tostring(playerDps))
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Dmg (%d%%)", runtime.playerDamage, playerPct))
        ImGui.EndGroup()
        
        ImGui.SameLine(320)
        -- Pet DPS Card
        ImGui.BeginGroup()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "PET DPS")
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(petDps))
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format("%d Dmg (%d%%)", runtime.petDamage, petPct))
        ImGui.EndGroup()
        
        ImGui.EndChild()
        
        -- Contribution Progress Bar
        local pFrac = runtime.totalDamage > 0 and (runtime.playerDamage / runtime.totalDamage) or 0
        ImGui.ProgressBar(pFrac, -1, 14, string.format("Player %d%%  |  Pet %d%%", playerPct, petPct))
        
        ImGui.Spacing()
        
        -- Category Breakdown Metric Bar Calculated Dynamically
        local liveTotals = calculateCategoryTotals(runtime.playerBreakdown, runtime.petBreakdown)
        local mPct = runtime.totalDamage > 0 and math.floor((liveTotals.melee / runtime.totalDamage * 100) + 0.5) or 0
        local skPct = runtime.totalDamage > 0 and math.floor((liveTotals.skill / runtime.totalDamage * 100) + 0.5) or 0
        local spPct = runtime.totalDamage > 0 and math.floor((liveTotals.spell / runtime.totalDamage * 100) + 0.5) or 0
        local dotPct = runtime.totalDamage > 0 and math.floor((liveTotals.dot / runtime.totalDamage * 100) + 0.5) or 0
        local dsPct = runtime.totalDamage > 0 and math.floor((liveTotals.ds / runtime.totalDamage * 100) + 0.5) or 0
        
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Live Categories:")
        ImGui.SameLine()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format("Melee: %d (%d%%) | Skills: %d (%d%%) | Spells: %d (%d%%) | DoTs: %d (%d%%) | DS: %d (%d%%)",
            liveTotals.melee, mPct, liveTotals.skill, skPct, liveTotals.spell, spPct, liveTotals.dot, dotPct, liveTotals.ds, dsPct))
            
        ImGui.Spacing()
        
        -- Navigation Tabs
        if ImGui.BeginTabBar("MainDpsTabBar") then
            
            -- TAB 1: Live Overview
            if ImGui.BeginTabItem("Live Overview##MainOverviewTab") then
                runtime.activeTab = 1
                ImGui.Spacing()
                
                local playerTotalAttacks = runtime.playerHits + runtime.playerMisses
                local playerAcc = playerTotalAttacks > 0 and math.floor((runtime.playerHits / playerTotalAttacks * 100) + 0.5) or 0
                local petTotalAttacks = runtime.petHits + runtime.petMisses
                local petAcc = petTotalAttacks > 0 and math.floor((runtime.petHits / petTotalAttacks * 100) + 0.5) or 0
                
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Player Hits:")
                ImGui.SameLine(100)
                ImGui.Text(string.format("%d hits / %d misses (Accuracy: %d%%)", runtime.playerHits, runtime.playerMisses, playerAcc))
                
                if runtime.petDamage > 0 or runtime.petHits > 0 then
                    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], "Pet Hits:")
                    ImGui.SameLine(100)
                    ImGui.Text(string.format("%d hits / %d misses (Accuracy: %d%%)", runtime.petHits, runtime.petMisses, petAcc))
                end
                
                ImGui.Spacing()
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Current Encounter Attack Breakdown:")
                local combinedMap = getCombinedOverviewBreakdownMap()
                renderBreakdownTable(combinedMap, true, "MainOverviewTable")
                
                ImGui.EndTabItem()
            end
            
            -- TAB 2: Player Details
            if ImGui.BeginTabItem("Player Details##MainPlayerTab") then
                runtime.activeTab = 2
                ImGui.Spacing()
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], "Player Damage Breakdown:")
                renderBreakdownTable(runtime.playerBreakdown, false, "MainPlayerTable")
                ImGui.EndTabItem()
            end
            
            -- TAB 3: Multi-Pet Details
            if ImGui.BeginTabItem("Pet Details##MainPetTab") then
                runtime.activeTab = 3
                ImGui.Spacing()
                renderMultiPetDetails(runtime.petBreakdown, "MainMultiPetTabBar", "MainPetTable")
                ImGui.EndTabItem()
            end
            
            -- TAB 4: History Log with In-Tab Encounter Inspection & Category Breakdown
            if ImGui.BeginTabItem("Fight History##MainHistoryTab") then
                runtime.activeTab = 4
                ImGui.Spacing()
                
                if runtime.inspectedFight ~= nil then
                    -- Render In-Tab Encounter Inspector for the selected fight
                    renderHistoricalInspector(runtime.inspectedFight, true)
                else
                    -- Render History List Table
                    if #runtime.history == 0 then
                        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "No past encounters logged in this session.")
                    else
                        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], "Click any fight target name or Inspect button to view full fight details.")
                        ImGui.Spacing()
                        
                        if ImGui.BeginTable("HistoryTable", 10, bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)) then
                            ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthFixed, 55)
                            ImGui.TableSetupColumn("Target", ImGuiTableColumnFlags.WidthStretch, 1.5)
                            ImGui.TableSetupColumn("Dur", ImGuiTableColumnFlags.WidthFixed, 35)
                            ImGui.TableSetupColumn("Total Dmg", ImGuiTableColumnFlags.WidthFixed, 65)
                            ImGui.TableSetupColumn("DPS", ImGuiTableColumnFlags.WidthFixed, 45)
                            ImGui.TableSetupColumn("Melee Dmg", ImGuiTableColumnFlags.WidthFixed, 65)
                            ImGui.TableSetupColumn("Skill Dmg", ImGuiTableColumnFlags.WidthFixed, 60)
                            ImGui.TableSetupColumn("Spell/DoT", ImGuiTableColumnFlags.WidthFixed, 65)
                            ImGui.TableSetupColumn("Player/Pet", ImGuiTableColumnFlags.WidthFixed, 70)
                            ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 105)
                            ImGui.TableHeadersRow()
                            
                            for i, h in ipairs(runtime.history) do
                                ImGui.TableNextRow()
                                ImGui.TableNextColumn()
                                ImGui.Text(h.timestamp)
                                
                                -- Selectable Target Name
                                ImGui.TableNextColumn()
                                if ImGui.Selectable(h.targetName .. "##HistTar_" .. tostring(h.id), false) then
                                    runtime.inspectedFight = h
                                end
                                
                                ImGui.TableNextColumn()
                                ImGui.Text(string.format("%.0fs", h.duration))
                                ImGui.TableNextColumn()
                                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], tostring(h.totalDmg))
                                ImGui.TableNextColumn()
                                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], tostring(h.peakDps))
                                
                                -- Categorized Damage Columns
                                ImGui.TableNextColumn()
                                ImGui.Text(tostring(h.meleeDmg or 0))
                                ImGui.TableNextColumn()
                                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], tostring(h.skillDmg or 0))
                                ImGui.TableNextColumn()
                                local magicDmg = (h.spellDmg or 0) + (h.dotDmg or 0)
                                ImGui.TextColored(PURPLE[1], PURPLE[2], PURPLE[3], PURPLE[4], tostring(magicDmg))
                                
                                ImGui.TableNextColumn()
                                local pPct = h.totalDmg > 0 and math.floor((h.playerDmg / h.totalDmg * 100) + 0.5) or 0
                                local petPct = h.totalDmg > 0 and math.floor((h.petDmg / h.totalDmg * 100) + 0.5) or 0
                                ImGui.Text(string.format("%d%% / %d%%", pPct, petPct))
                                
                                -- Action Buttons
                                ImGui.TableNextColumn()
                                if ImGui.Button("Inspect##HistInsp_" .. tostring(h.id), 50, 18) then
                                    runtime.inspectedFight = h
                                end
                                ImGui.SameLine()
                                if ImGui.Button("Report##HistRpt_" .. tostring(h.id), 48, 18) then
                                    reportHistoricalFight(h)
                                end
                            end
                            
                            ImGui.EndTable()
                        end
                    end
                end
                
                ImGui.EndTabItem()
            end
            
            -- TAB 5: Settings
            if ImGui.BeginTabItem("Settings##MainSettingsTab") then
                runtime.activeTab = 5
                ImGui.Spacing()
                
                local changed = false
                
                local newCompact, cChanged = ImGui.Checkbox("Compact Mini-Window Mode", ctrl.compact)
                if cChanged then
                    ctrl.compact = newCompact
                    changed = true
                end
                
                local newTimeout, tChanged = ImGui.SliderFloat("Combat Timeout (sec)", ctrl.combatTimeout, 2.0, 20.0, "%.1f sec")
                if tChanged then
                    ctrl.combatTimeout = newTimeout
                    changed = true
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Seconds of damage inactivity before automatically ending the current fight.")
                end
                
                local channels = { 'group', 'say', 'guild', 'raid' }
                local currentIdx = 1
                for idx, ch in ipairs(channels) do
                    if ch == ctrl.reportChannel then currentIdx = idx break end
                end
                
                if ImGui.BeginCombo("Default Report Channel", channels[currentIdx]) then
                    for idx, ch in ipairs(channels) do
                        local isSel = (idx == currentIdx)
                        if ImGui.Selectable(ch, isSel) then
                            ctrl.reportChannel = ch
                            changed = true
                        end
                    end
                    ImGui.EndCombo()
                end
                
                local newReset, rChanged = ImGui.Checkbox("Auto-Reset on Zone Change", ctrl.autoResetOnZone)
                if rChanged then
                    ctrl.autoResetOnZone = newReset
                    changed = true
                end
                
                local newPetShow, pChanged = ImGui.Checkbox("Show Pet Breakdown Tab", ctrl.showPetBreakdown)
                if pChanged then
                    ctrl.showPetBreakdown = newPetShow
                    changed = true
                end
                
                if changed then
                    saveConfig()
                end
                
                ImGui.EndTabItem()
            end
            
            ImGui.EndTabBar()
        end
        
        -- Modal Popup Window Handling (Forced ImGui Focus)
        if runtime.shouldOpenModal then
            runtime.shouldOpenModal = false
            ImGui.OpenPopup("Encounter Inspector##InspectModalWin")
        end
        
        local modalOpen, modalDraw = ImGui.BeginPopupModal("Encounter Inspector##InspectModalWin", true, bit.bor(ImGuiWindowFlags.AlwaysAutoResize))
        if modalDraw then
            if runtime.inspectedFight then
                renderHistoricalInspector(runtime.inspectedFight, false)
            else
                ImGui.Text("No fight selected.")
                if ImGui.Button("Close", 80, 22) then
                    ImGui.CloseCurrentPopup()
                end
            end
            ImGui.EndPopup()
        end
    end
    
    ImGui.End()
    popTheme()
end

-- ============================================================================
-- Slash Command Bindings (/dps and /triunedps)
-- ============================================================================
local function dpsCommandHandler(cmd, arg1, arg2)
    local sub = (cmd or ''):lower()
    if sub == '' or sub == 'toggle' or sub == 'ui' then
        ctrl.open = not ctrl.open
        if not ctrl.open then
            runtime.guiOpen = false
            runtime.inspectorOpen = false
            saveConfig()
            print("\127300000[Triune DPS]\127777777 Window Closed.")
        else
            ctrl.open = true
            runtime.guiOpen = true
            print(string.format("\127300000[Triune DPS]\127777777 Window Opened."))
        end
    elseif sub == 'show' or sub == 'open' then
        ctrl.open = true
        runtime.guiOpen = true
    elseif sub == 'hide' or sub == 'close' then
        ctrl.open = false
        runtime.guiOpen = false
        runtime.inspectorOpen = false
        saveConfig()
        print("\127300000[Triune DPS]\127777777 Window Closed.")
    elseif sub == 'compact' or sub == 'mini' then
        ctrl.compact = not ctrl.compact
        saveConfig()
        print(string.format("\127300000[Triune DPS]\127777777 Compact mode: %s.", ctrl.compact and "ON" or "OFF"))
    elseif sub == 'reset' or sub == 'clear' then
        resetCurrentFight()
        print("\127300000[Triune DPS]\127777777 Current fight statistics reset.")
    elseif sub == 'pause' then
        ctrl.paused = true
        print("\127300000[Triune DPS]\127777777 DPS tracking paused.")
    elseif sub == 'resume' or sub == 'start' then
        ctrl.paused = false
        print("\127300000[Triune DPS]\127777777 DPS tracking resumed.")
    elseif sub == 'report' then
        local channel = (arg1 and arg1 ~= '') and arg1:lower() or nil
        reportDPS(channel)
    else
        print("\127300000[Triune DPS]\127777777 Commands: /dps [show|hide|toggle|compact|reset|pause|resume|report <channel>]")
    end
end

-- ============================================================================
-- Main Loop & Initialization
-- ============================================================================
local function main()
    loadConfig()
    registerEvents()
    
    mq.bind('/dps', dpsCommandHandler)
    mq.bind('/triunedps', dpsCommandHandler)
    
    mq.imgui.init('TriuneDPSWindow', drawDpsGui)
    mq.imgui.init('TriuneDPSMiniWindow', drawMiniDpsGui)
    
    print(string.format("\127300000[Triune DPS]\127777777 v%s loaded! Use /dps to toggle window.", VERSION))
    
    if type(mq.atexit) == 'function' then
        mq.atexit(function()
            saveConfig()
            print("\127300000[Triune DPS]\127777777 Unloaded cleanly.")
        end)
    end
    
    while runtime.guiOpen and ctrl.open do
        mq.delay(50)
        mq.doevents()
        
        -- Check Target state for automatic encounter archiving on target death or combat inactivity
        if runtime.inFight then
            local okId, tId = pcall(function() return mq.TLO.Target.ID() end)
            local okDead, tDead = pcall(function() return mq.TLO.Target.Dead() or mq.TLO.Target.Type() == 'Corpse' end)
            local targetId = (okId and tId and tId > 0) and tId or 0
            local isDead = (okDead and tDead == true)
            
            -- If active targeted mob died
            if isDead and targetId > 0 and targetId == runtime.currentTargetId then
                endFightSession()
            elseif runtime.lastDamageTime > 0 then
                local inactiveSec = (mq.gettime() - runtime.lastDamageTime) / 1000.0
                if inactiveSec >= ctrl.combatTimeout then
                    endFightSession()
                end
            end
        end
    end

    saveConfig()
    pcall(function() mq.imgui.destroy('TriuneDPSWindow') end)
    pcall(function() mq.imgui.destroy('TriuneDPSMiniWindow') end)
    print("\127300000[Triune DPS]\127777777 Unloaded cleanly.")
    mq.exit()
end

main()
