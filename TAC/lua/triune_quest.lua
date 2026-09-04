---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TRIUNE QUEST GUIDE v1.0 (Standalone ImGui Script)
-- ----------------------------------------------------------------------------
-- Comprehensive in-game quest catalog and walkthrough assistant.
-- Features:
--   - Auto-zone detection & on-demand zone quest package loading
--   - Global quest search across all 32 expansions (2,600+ quests)
--   - Live NPC spawn radar, distance/direction calculation, and /nav dispatch
--   - Interactive click-to-say dialogue triggers
--   - Live inventory turn-in item scanner (bags & bank item counts)
--   - Per-character quest completion persistence (triune_quest_<Server>_<Char>.ini)
--
-- Compatible with MacroQuest LuaJIT (Lua 5.1 safe).
-- Run via: /lua run triune_quest
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')
local bit = require('bit')

-- Theme & style helpers (Unified Dark Cyan/Blue Theme)
local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    local ImGuiColType = mq.imgui.Col or _G.ImGuiCol
    local enumVal = ImGuiColType and ImGuiColType(id) or id
    if pcall(mq.imgui.PushStyleColor, enumVal, r, g, b, a) then _colN = _colN + 1 end
end

local function pushVar(id, a, b)
    if id == nil then return end
    local ok
    local ImGuiSVType = mq.imgui.StyleVar or _G.ImGuiStyleVar
    local enumVal = ImGuiSVType and ImGuiSVType(id) or id
    if b ~= nil then
        local ImVec2Type = _G.ImVec2
        if type(ImVec2Type) == 'function' then
            ok = pcall(mq.imgui.PushStyleVar, enumVal, ImVec2Type(a, b))
        else
            ok = pcall(mq.imgui.PushStyleVar, enumVal, a, b)
        end
    else
        ok = pcall(mq.imgui.PushStyleVar, enumVal, a)
    end
    if ok then _varN = _varN + 1 end
end

local function pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = mq.imgui.Col or _G.ImGuiCol
    local ImGuiStyleVar = mq.imgui.StyleVar or _G.ImGuiStyleVar
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
    end
end

local function popTheme()
    while _colN > 0 do
        pcall(mq.imgui.PopStyleColor)
        _colN = _colN - 1
    end
    while _varN > 0 do
        pcall(mq.imgui.PopStyleVar)
        _varN = _varN - 1
    end
end

-- Visual palette constants
local C_GOOD   = { 0.37, 0.88, 0.64, 1.0 }
local C_WARN   = { 1.00, 0.82, 0.40, 1.0 }
local C_ERR    = { 0.95, 0.38, 0.38, 1.0 }
local C_CYAN   = { 0.40, 0.80, 1.00, 1.0 }
local C_GOLD   = { 1.00, 0.75, 0.20, 1.0 }
local C_MUTED  = { 0.55, 0.65, 0.75, 1.0 }
local C_BRIGHT = { 0.92, 0.95, 1.00, 1.0 }

-- Structured state table to respect Lua 5.1 local variable limits
local state = {
    open            = true,
    isRunning       = true,
    basePath        = nil,
    catalog         = {},
    expansions      = {},
    currentZone     = "",
    currentZoneName = "",
    zonePackages    = {}, -- cached zone packages: { [shortname] = data }
    activeQuests    = {}, -- list of quests currently shown in left pane
    selectedId      = nil,
    selectedQuest   = nil,
    
    -- Filter and search options
    searchTerm      = "",
    selectedExpIdx  = 0,  -- 0 = All
    filterZoneOnly  = true,
    filterLevel     = false,
    minLvl          = 1,
    maxLvl          = 125,
    hideCompleted   = false,
    autoZoneSync    = true,
    limitServerEra  = true,
    maxExpansionCap = 5,
    detectedCap     = 5,
    
    -- Lookup and Atlas Browser state
    requestTab          = nil,
    lookupMode          = "zone", -- "zone" or "quests"
    lookupZoneSearch    = "",
    lookupQuestSearch   = "",
    selectedLookupZone  = nil,
    zoneList            = {},
    
    -- Completed and tracked quests
    completedQuests = {}, -- { [qid_str] = true }
    trackedQuests   = {},
    walkthroughViewMode = "formatted", -- "formatted" or "raw"
    
    -- Coroutine queue
    pendingAction   = nil,
}

local UI = {}
local DB = {}

-- ---------------------------------------------------------------------------
-- Persistence: Completed Quests INI
-- ---------------------------------------------------------------------------
function DB.getIniPath()
    local srv = "Default"
    local chr = "Character"
    pcall(function()
        srv = mq.TLO.MacroQuest.Server() or srv
        chr = mq.TLO.Me.CleanName() or chr
    end)
    local cfg = mq.configDir or "."
    return string.format("%s/triune_quest_%s_%s.ini", cfg, srv, chr)
end

function DB.loadPersistence()
    local p = DB.getIniPath()
    local f = io.open(p, "r")
    if not f then return end
    local currentSec = nil
    for line in f:lines() do
        local sec = line:match("^%[([^%]]+)%]")
        if sec then
            currentSec = sec
        else
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                if currentSec == "Completed" and v == "1" then
                    state.completedQuests[k] = true
                elseif currentSec == "Tracked" and v == "1" then
                    state.trackedQuests[k] = true
                elseif currentSec == "Settings" then
                    if k == "limit_server_era" then
                        state.limitServerEra = (v == "1" or v == "true")
                    elseif k == "max_expansion_cap" and tonumber(v) then
                        state.maxExpansionCap = tonumber(v)
                    end
                end
            end
        end
    end
    f:close()
end

function DB.savePersistence()
    local p = DB.getIniPath()
    local f = io.open(p, "w")
    if not f then return end
    f:write("[Settings]\n")
    f:write(string.format("limit_server_era=%d\n", state.limitServerEra and 1 or 0))
    f:write(string.format("max_expansion_cap=%d\n", state.maxExpansionCap or 32))
    f:write("\n[Completed]\n")
    for qid, _ in pairs(state.completedQuests) do
        f:write(string.format("%s=1\n", qid))
    end
    f:write("\n[Tracked]\n")
    for qid, _ in pairs(state.trackedQuests) do
        f:write(string.format("%s=1\n", qid))
    end
    f:close()
end

-- ---------------------------------------------------------------------------
-- Server Era Detection
-- ---------------------------------------------------------------------------
function DB.detectServerExpansion()
    -- 1. Check Me.HaveExpansion TLO in MQ
    local detected = nil
    pcall(function()
        if mq.TLO.Me.HaveExpansion then
            local maxExp = 0
            for i = 1, 32 do
                local ok, has = pcall(function() return mq.TLO.Me.HaveExpansion(i)() end)
                if ok and has == true then
                    maxExp = i
                end
            end
            if maxExp > 0 then
                detected = maxExp
            end
        end
    end)
    if detected then return detected end
    
    -- 2. Check triune_data.lua era_expansion
    local cfg = mq.configDir or "."
    local paths = {
        cfg .. "/triune_data.lua",
        (mq.luaDir and mq.luaDir .. "/../config/triune_data.lua") or nil,
        (mq.luaDir and mq.luaDir .. "/triune_data.lua") or nil,
        "config/triune_data.lua",
        "TAC/config/triune_data.lua",
    }
    for _, p in ipairs(paths) do
        if p then
            local fn = loadfile(p)
            if fn then
                local ok, res = pcall(fn)
                if ok and type(res) == "table" and res.era_expansion then
                    return tonumber(res.era_expansion) or 5
                end
            end
        end
    end
    
    return 5 -- Default to era 5 (LoY/PoP on NMS)
end

-- ---------------------------------------------------------------------------
-- Data Directory Discovery & Module Loading
-- ---------------------------------------------------------------------------
function DB.findResourcePath()
    local candidates = {
        (mq.luaDir and (mq.luaDir .. "/../resources/triune_quest")) or nil,
        (mq.luaDir and (mq.luaDir .. "/triune_quest")) or nil,
        (mq.configDir and (mq.configDir .. "/../resources/triune_quest")) or nil,
        "resources/triune_quest",
        "TAC/resources/triune_quest",
        "triune_quest",
    }
    for _, c in ipairs(candidates) do
        if c then
            local testF = io.open(c .. "/catalog.lua", "r")
            if testF then
                testF:close()
                return c
            end
        end
    end
    return nil
end

function DB.init()
    state.detectedCap = DB.detectServerExpansion()
    state.maxExpansionCap = state.detectedCap

    state.basePath = DB.findResourcePath()
    if not state.basePath then
        print("\ar[TriuneQuest]\ax Could not locate triune_quest resource directory!")
        return false
    end
    
    -- Load Catalog
    local catFn, err = loadfile(state.basePath .. "/catalog.lua")
    if catFn then
        local ok, res = pcall(catFn)
        if ok and type(res) == "table" then
            state.catalog = res
        end
    else
        print("\ar[TriuneQuest]\ax Error loading catalog.lua: " .. tostring(err))
    end
    
    -- Load Expansions
    local expFn = loadfile(state.basePath .. "/expansions.lua")
    if expFn then
        local ok, res = pcall(expFn)
        if ok and type(res) == "table" then
            state.expansions = res
        end
    end
    
    -- Build zone directory list from catalog
    local zoneMap = {}
    state.zoneList = {}
    for _, q in ipairs(state.catalog) do
        local z = q.zone and q.zone:lower() or "unknown"
        if not zoneMap[z] then
            local zObj = {
                shortname = z,
                name = q.zone_name or z,
                exp = tonumber(q.exp) or 0,
                exp_name = q.exp_name or "",
                count = 0,
            }
            zoneMap[z] = zObj
            table.insert(state.zoneList, zObj)
        end
        zoneMap[z].count = zoneMap[z].count + 1
        local qExp = tonumber(q.exp) or 0
        if qExp < zoneMap[z].exp then
            zoneMap[z].exp = qExp
            zoneMap[z].exp_name = q.exp_name
        end
    end
    table.sort(state.zoneList, function(a, b)
        return (a.name or a.shortname) < (b.name or b.shortname)
    end)
    
    DB.loadPersistence()
    print(string.format("\ag[TriuneQuest]\ax Loaded %d quests across %d zones. Server era detected: Exp %02d (Limit Active: %s).", #state.catalog, #state.zoneList, state.detectedCap, state.limitServerEra and "Yes" or "No"))
    return true
end

function DB.getZonePackage(zoneShort)
    if not zoneShort or zoneShort == "" then return nil end
    zoneShort = zoneShort:lower()
    if state.zonePackages[zoneShort] then
        return state.zonePackages[zoneShort]
    end
    
    if not state.basePath then return nil end
    local zpath = string.format("%s/zones/%s.lua", state.basePath, zoneShort)
    local zfn = loadfile(zpath)
    if zfn then
        local ok, res = pcall(zfn)
        if ok and type(res) == "table" then
            state.zonePackages[zoneShort] = res
            return res
        end
    end
    return nil
end

-- Refresh left pane quest list according to active filters
function DB.refreshActiveQuests()
    local list = {}
    local term = (type(state.searchTerm) == "string") and state.searchTerm:lower() or ""
    local curZ = (type(state.currentZone) == "string") and state.currentZone:lower() or ""
    
    for _, q in ipairs(state.catalog) do
        local match = true
        local expNum = tonumber(q.exp) or 0
        
        -- Server Era Limit filter
        if state.limitServerEra and state.maxExpansionCap then
            if expNum > state.maxExpansionCap then
                match = false
            end
        end
        
        -- Zone filter
        if match and state.filterZoneOnly then
            if q.zone ~= curZ then
                match = false
            end
        end
        
        -- Expansion filter
        if match and state.selectedExpFilterId then
            if q.exp ~= state.selectedExpFilterId then
                match = false
            end
        end
        
        -- Level filter
        if match and state.filterLevel then
            if q.max_lvl < state.minLvl or q.min_lvl > state.maxLvl then
                match = false
            end
        end
        
        -- Hide completed
        if match and state.hideCompleted then
            if state.completedQuests[q.id] then
                match = false
            end
        end
        
        -- Search term
        if match and term ~= "" then
            local tMatch = q.title:lower():find(term, 1, true) ~= nil
            local nMatch = q.npc:lower():find(term, 1, true) ~= nil
            local zMatch = q.zone_name:lower():find(term, 1, true) ~= nil
            if not (tMatch or nMatch or zMatch) then
                match = false
            end
        end
        
        if match then
            table.insert(list, q)
        end
    end
    
    state.activeQuests = list
end

function DB.selectQuest(qid)
    state.selectedId = qid
    state.selectedQuest = nil
    if not qid then return end
    
    -- Find in catalog to get zone
    local zoneShort = nil
    for _, q in ipairs(state.catalog) do
        if q.id == qid then
            zoneShort = q.zone
            break
        end
    end
    
    if zoneShort then
        local pkg = DB.getZonePackage(zoneShort)
        if pkg and pkg.quests then
            for _, q in ipairs(pkg.quests) do
                if q.id == qid then
                    state.selectedQuest = q
                    break
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Engine Helpers: Spawn Radar, Navigation, & Inventory
-- ---------------------------------------------------------------------------
local Engine = {}

function Engine.getNPCStatus(npcName)
    if not npcName or npcName == "" or npcName == "Unknown" then
        return false, nil, 0, ""
    end
    local ok, spawn = pcall(function()
        return mq.TLO.Spawn(string.format('npc "%s"', npcName))
    end)
    if ok and spawn and spawn() and spawn.ID() and spawn.ID() > 0 then
        local dist = math.floor(spawn.Distance() or 0)
        local heading = spawn.Heading.ShortName() or ""
        return true, spawn.ID(), dist, heading
    end
    return false, nil, 0, ""
end

function Engine.getInventoryCount(itemName)
    if not itemName or itemName == "" then return 0, 0 end
    local inBags = 0
    local inBank = 0
    pcall(function()
        inBags = mq.TLO.FindItemCount(string.format('=%s', itemName))() or 0
        inBank = mq.TLO.FindItemBankCount(string.format('=%s', itemName))() or 0
    end)
    return inBags, inBank
end

function Engine.queueNavToNPC(npcName, loc)
    state.pendingAction = function()
        local ok, spawn = pcall(function()
            return mq.TLO.Spawn(string.format('npc "%s"', npcName))
        end)
        if ok and spawn and spawn() and spawn.ID() and spawn.ID() > 0 then
            mq.cmdf('/nav spawn npc "%s"', npcName)
        elseif loc and loc.x and loc.y then
            mq.cmdf('/nav loc %0.1f %0.1f %0.1f', loc.y, loc.x, loc.z or 0)
        else
            print(string.format("\ay[TriuneQuest]\ax Cannot navigate: %s is not spawned and has no coordinates.", npcName))
        end
    end
end

function Engine.queueSay(phrase, npcName)
    state.pendingAction = function()
        if npcName and npcName ~= "" and npcName ~= "Unknown" then
            local ok, spawn = pcall(function() return mq.TLO.Spawn(string.format('npc "%s"', npcName)) end)
            if ok and spawn and spawn() and spawn.ID() and spawn.ID() > 0 then
                mq.cmdf('/target id %d', spawn.ID())
                mq.delay(100)
            end
        end
        mq.cmdf('/say %s', phrase)
    end
end

-- ---------------------------------------------------------------------------
-- UI Drawing
-- ---------------------------------------------------------------------------
function UI.renderWindowContent()
    
    -- Header Toolbar
    ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "Current Zone:")
    ImGui.SameLine()
    local zTitle = state.currentZoneName ~= "" and string.format("%s (%s)", state.currentZoneName, state.currentZone) or "Unknown"
    ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], zTitle)
    
    ImGui.SameLine()
    local newSync, changedSync = ImGui.Checkbox("Auto-Sync Zone##Quest", state.autoZoneSync == true)
    if changedSync then state.autoZoneSync = newSync end
    
    ImGui.SameLine(0, 20)
    local newHide, changedHide = ImGui.Checkbox("Hide Completed##Quest", state.hideCompleted == true)
    if changedHide then
        state.hideCompleted = newHide
        DB.refreshActiveQuests()
    end
    
    ImGui.SameLine(0, 20)
    local newZoneOnly, changedZoneOnly = ImGui.Checkbox("Current Zone Only##Quest", state.filterZoneOnly == true)
    if changedZoneOnly then
        state.filterZoneOnly = newZoneOnly
        DB.refreshActiveQuests()
    end
    
    ImGui.SameLine(0, 20)
    local newEraLimit, changedEraLimit = ImGui.Checkbox("Server Era Limit##Quest", state.limitServerEra == true)
    if changedEraLimit then
        state.limitServerEra = newEraLimit
        DB.savePersistence()
        DB.refreshActiveQuests()
    end
    
    if state.limitServerEra then
        ImGui.SameLine(0, 6)
        ImGui.SetNextItemWidth(170)
        local capNames = {}
        for _, ex in ipairs(state.expansions) do
            table.insert(capNames, string.format("[%s] %s", ex.id, ex.name))
        end
        local curCapIdx = math.min(#capNames, (state.maxExpansionCap or 5) + 1)
        local newCapIdx, capChanged = ImGui.Combo("##ServerEraCapCombo", curCapIdx, capNames)
        if capChanged and newCapIdx then
            state.maxExpansionCap = newCapIdx - 1
            DB.savePersistence()
            DB.refreshActiveQuests()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Limits visible quests to this server expansion cap.")
            ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], string.format("Detected server era: Exp %02d", state.detectedCap or 5))
            ImGui.EndTooltip()
        end
    end
    
    ImGui.Separator()
    
    -- Main Navigation Tabs
    if ImGui.BeginTabBar("QuestGuideMainTabBar") then
        local guideFlags = (state.requestTab == "guide" and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
        if state.requestTab == "guide" then state.requestTab = nil end
        if ImGui.BeginTabItem("Zone Guide###ZoneGuideTab", nil, guideFlags) then
            UI.drawZoneGuideTab()
            ImGui.EndTabItem()
        end
        
        local lookupFlags = (state.requestTab == "lookup" and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
        if state.requestTab == "lookup" then state.requestTab = nil end
        if ImGui.BeginTabItem("Zone & Quest Lookup###LookupTab", nil, lookupFlags) then
            UI.drawLookupTab()
            ImGui.EndTabItem()
        end
        
        ImGui.EndTabBar()
    end
end

-- ---------------------------------------------------------------------------
-- Walkthrough Narrative Cleaner & Rich Formatter
-- ---------------------------------------------------------------------------
function UI.cleanPreambleAndTags(raw)
    if not raw or raw == "" then return "" end
    
    -- Strip infobox table preamble if present
    local pos = raw:find("Modified:[^\n|]+|%s*|%s*") or raw:find("Entered:[^\n|]+|%s*|%s*")
    local body = raw
    if pos then
        local after = raw:sub(pos):match("^[^\n|]+|%s*|%s*(.*)$")
        if after and after ~= "" then
            body = after
        end
    else
        -- If no Modified/Entered pipe divider, scan and strip leading infobox lines
        local lines = {}
        for line in raw:gmatch("[^\r\n]+") do table.insert(lines, line) end
        local idx = 1
        while idx <= #lines and idx <= 60 do
            local l = lines[idx]:match("^%s*(.-)%s*$")
            local isMeta = false
            if l == "" or l:find("^Quest Started By:") or l:find("^Description:") or
               l:find("^Rating:") or l:find("^Information:") or l:find("^Recommended:") or
               l:find("^%*%*Level:") or l:find("^%*%*Maximum Level:") or l:find("^%*%*Monster Mission:") or
               l:find("^%*%*Repeatable:") or l:find("^%*%*Can Be Shrouded") or l:find("^%*%*Quest Type:") or
               l:find("^%*%*Quest Goal:") or l:find("^%*%*Time Limit:") or l:find("^%*%*Time:") or
               l:find("^%*%*Success Lockout") or l:find("^%*%*Where:") or l:find("^%*%*Who:") or
               l:find("^%*%*Group Size:") or l:find("^%*%*Min%. # of Players:") or l:find("^%*%*Max%. # of Players:") or
               l:find("^Appropriate Classes:") or l:find("^Appropriate Races:") or l:find("^%*%*Related Zones:") or
               l:find("^%*%*Related Creatures:") or l:find("^%*%*Related Quests:") or l:find("^%*%*Quest Items:") or
               l:find("^%*%*Era:") or l:find("^Entered:") or l:find("^Modified:") or
               l:find("^%d+/%d+%*%*_?%*") or (l:find("^%-%s+[A-Z]") and idx < 40) then
                isMeta = true
            end
            if not isMeta then break end
            idx = idx + 1
        end
        local rest = {}
        for k = idx, #lines do table.insert(rest, lines[k]) end
        body = table.concat(rest, "\n")
    end
    
    -- Strip trailing wiki submission / rewards junk
    local subPos = body:find("Submitted by:") or body:find("%*%*Submitted by:")
    if subPos then
        body = body:sub(1, subPos - 1)
    end
    
    -- Clean wiki tag brackets and escape artifacts
    body = body:gsub("%[item=%d+%]", "")
    body = body:gsub("%[npc=%d+%]", "")
    body = body:gsub("%[zone=%d+%]", "")
    body = body:gsub("%[quest=%d+%]", "")
    body = body:gsub("\\%_", "_")
    body = body:gsub("\\%-", "-")
    body = body:gsub("\\%*", "*")
    body = body:gsub("\\%.", ".")
    
    -- Personalize player character name
    local charName = "Adventurer"
    pcall(function()
        if mq and mq.TLO and mq.TLO.Me and mq.TLO.Me.CleanName then
            local cn = mq.TLO.Me.CleanName()
            if cn and cn ~= "" then charName = cn end
        end
    end)
    body = body:gsub("____+", charName)
    body = body:gsub("your name", charName)
    
    -- Remove wiki nav headers
    body = body:gsub("%*%*[^%*]+Info & Guides:[^\n]+%*%*", "")
    body = body:gsub("%*%*Click here%*%*[^\n]+", "")
    
    return body:match("^%s*(.-)%s*$") or ""
end

function UI.parseWalkthrough(q)
    if q._parsedWalkthrough then return q._parsedWalkthrough end
    local clean = UI.cleanPreambleAndTags(q.walkthrough)
    local tokens = {}
    if clean == "" then
        q._parsedWalkthrough = tokens
        return tokens
    end
    
    for line in clean:gmatch("[^\r\n]+") do
        local l = line:match("^%s*(.-)%s*$")
        if l and l ~= "" then
            if l == "---" or l:find("^%-%-%-%-+$") or l:find("^%=%=%=+$") then
                table.insert(tokens, { type = "divider" })
            elseif l:find("^[Yy]ou say") then
                local sayPhrase = l:match("^[Yy]ou say,?%s*['\"](.-)['\"]%s*$") or l:match("^[Yy]ou say,?%s*['\"](.-)['\"]")
                if sayPhrase then
                    table.insert(tokens, { type = "player_say", phrase = sayPhrase, raw = l, npc = q.npc })
                else
                    table.insert(tokens, { type = "text", text = l:gsub("%*%*", "") })
                end
            elseif l:find("^[Yy]our faction standing with") then
                local isNeg = l:find("adjusted by %-") ~= nil
                table.insert(tokens, { type = "faction", text = l, isNeg = isNeg })
            elseif l:find("^[Yy]ou gain") or l:find("^[Yy]ou receive") or l:find("^[Yy]ou get") or l:find("^Reward%(s%):") then
                table.insert(tokens, { type = "reward", text = l })
            elseif l:find("^[Nn][Oo][Tt][Ee]:") or l:find("^%*%*_?NOTE:") or l:find("^[Ww]arning:") or l:find("^[Ff]ailure Mechanics") then
                local cleanNote = l:gsub("^%*%*_?", ""):gsub("_?%*%*$", "")
                table.insert(tokens, { type = "note", text = cleanNote })
            elseif l:match("^%d+[%.)]%s+") or l:match("^[Kk]ill%s+") or l:match("^[Ll]oot%s+") or l:match("^[Hh]and in%s+") or l:match("^[Dd]eliver%s+") or l:match("^[Cc]ombine%s+") then
                table.insert(tokens, { type = "step", text = l:gsub("%*%*", "") })
            elseif l:match("^[Ff]ind%s+") or l:match("^[Ss]peak with%s+") or l:match("^Go back%s+") or l:match("is located") then
                table.insert(tokens, { type = "direction", text = l:gsub("%*%*", "") })
            elseif l:find(" says") then
                local speaker, speech = l:match("^([%w%s%-%_%.%`']+)[%s,]+says?,?%s*['\"](.-)['\"]%s*$")
                if speaker and speech and not speaker:lower():find("^you") then
                    table.insert(tokens, { type = "npc_say", speaker = speaker, text = speech })
                else
                    table.insert(tokens, { type = "text", text = l:gsub("%*%*", "") })
                end
            elseif l:match("^%*%*(.-)%*%*$") or l:match("^Task Steps") or l:match("^Task Details") or l:match("^The Phases") or l:match("^Types of Armor") then
                local h = l:match("^%*%*(.-)%*%*$") or l
                table.insert(tokens, { type = "header", text = h })
            else
                local cleanText = l:gsub("%*%*", "")
                table.insert(tokens, { type = "text", text = cleanText })
            end
        end
    end
    q._parsedWalkthrough = tokens
    return tokens
end

function UI.drawFormattedWalkthrough(q)
    local tokens = UI.parseWalkthrough(q)
    if #tokens == 0 then
        ImGui.Dummy(10, 20)
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "  No walkthrough text recorded for this quest.")
        return
    end
    
    for idx, tok in ipairs(tokens) do
        if tok.type == "header" then
            ImGui.Spacing()
            ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], string.format("◆  %s", tok.text))
            ImGui.Separator()
        elseif tok.type == "player_say" then
            ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], "💬 You say:")
            ImGui.SameLine()
            ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], string.format("'%s'", tok.phrase))
            ImGui.SameLine()
            local btnId = string.format("Say##Line_%d", idx)
            if ImGui.SmallButton(btnId) then
                Engine.queueSay(tok.phrase, q.npc)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Click to target %s and say: '%s'", q.npc or "NPC", tok.phrase)
            end
            ImGui.Spacing()
        elseif tok.type == "npc_say" then
            ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], string.format("👤 %s says:", tok.speaker))
            ImGui.Indent(16)
            ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], string.format("\"%s\"", tok.text))
            ImGui.Unindent(16)
            ImGui.Spacing()
        elseif tok.type == "step" then
            ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "▶")
            ImGui.SameLine()
            ImGui.TextWrapped("%s", tok.text)
        elseif tok.type == "direction" then
            ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "📍")
            ImGui.SameLine()
            ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "%s", tok.text)
        elseif tok.type == "faction" then
            if tok.isNeg then
                ImGui.TextColored(C_ERR[1], C_ERR[2], C_ERR[3], C_ERR[4], string.format("  ▼ %s", tok.text))
            else
                ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], string.format("  ▲ %s", tok.text))
            end
        elseif tok.type == "reward" then
            ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], string.format("★ %s", tok.text))
        elseif tok.type == "note" then
            ImGui.TextColored(C_WARN[1], C_WARN[2], C_WARN[3], C_WARN[4], string.format("⚠ %s", tok.text))
        elseif tok.type == "divider" then
            ImGui.Separator()
        else
            ImGui.TextWrapped("%s", tok.text)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tab 1: Zone Guide View (Active Zone Walkthrough, Radar, Turn-Ins)
-- ---------------------------------------------------------------------------
function UI.drawZoneGuideTab()
    -- Filter Bar (Search, Expansions, Level, Current Zone Only)
    ImGui.SetNextItemWidth(200)
    local curSearch = (type(state.searchTerm) == "string") and state.searchTerm or ""
    local newSearch, changedSearch = ImGui.InputTextWithHint("##QuestSearch", "Search quest, NPC, or zone...", curSearch)
    if changedSearch and type(newSearch) == "string" then
        state.searchTerm = newSearch
        DB.refreshActiveQuests()
    end
    
    ImGui.SameLine()
    ImGui.SetNextItemWidth(170)
    local expNames = { "All Allowed Expansions" }
    local expIdxMap = { [0] = nil }
    local curIdx = 0
    for _, ex in ipairs(state.expansions) do
        local eNum = tonumber(ex.id) or 0
        if not state.limitServerEra or eNum <= (state.maxExpansionCap or 32) then
            table.insert(expNames, string.format("[%s] %s", ex.id, ex.name))
            local comboIdx = #expNames - 1
            expIdxMap[comboIdx] = ex.id
            if state.selectedExpFilterId == ex.id then
                curIdx = comboIdx
            end
        end
    end
    local newExpIdx, expChanged = ImGui.Combo("##ExpCombo", curIdx, expNames)
    if expChanged and newExpIdx then
        state.selectedExpFilterId = expIdxMap[newExpIdx]
        DB.refreshActiveQuests()
    end
    
    ImGui.SameLine()
    local newZoneOnly, changedZoneOnly = ImGui.Checkbox("Current Zone Only##QuestGuide", state.filterZoneOnly == true)
    if changedZoneOnly then
        state.filterZoneOnly = newZoneOnly
        DB.refreshActiveQuests()
    end
    
    ImGui.SameLine()
    local newLvlFilter, changedLvlFilter = ImGui.Checkbox("Level Range##Quest", state.filterLevel == true)
    if changedLvlFilter then
        state.filterLevel = newLvlFilter
        DB.refreshActiveQuests()
    end
    
    if state.filterLevel then
        ImGui.SameLine()
        ImGui.SetNextItemWidth(60)
        local newMin, minChanged = ImGui.SliderInt("##LvlMin", state.minLvl or 1, 1, 125, "Lvl %d")
        if minChanged then
            state.minLvl = newMin
            DB.refreshActiveQuests()
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(60)
        local newMax, maxChanged = ImGui.SliderInt("##LvlMax", state.maxLvl or 125, 1, 125, "to %d")
        if maxChanged then
            state.maxLvl = newMax
            DB.refreshActiveQuests()
        end
    end
    
    ImGui.Separator()
    
    -- Split Layout: Left pane list (380px), Right pane details (Remaining)
    local availX, availY = ImGui.GetContentRegionAvail()
    local leftWidth = 380
    
    -- Left Pane: Quest Table
    ImGui.BeginChild("QuestListChild##Left", leftWidth, availY - 10, true)
    ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], string.format("Quests (%d available)", #state.activeQuests))
    ImGui.Separator()
    
    local flags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
    if ImGui.BeginTable("QuestListTable##Left", 4, flags) then
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 30)
        ImGui.TableSetupColumn("Title", ImGuiTableColumnFlags.WidthStretch, 2)
        ImGui.TableSetupColumn("Lvl", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Exp", ImGuiTableColumnFlags.WidthFixed, 35)
        ImGui.TableHeadersRow()
        
        for _, q in ipairs(state.activeQuests) do
            ImGui.TableNextRow()
            
            local isDone = state.completedQuests[q.id] == true
            local isSel = state.selectedId == q.id
            
            -- Status Column
            ImGui.TableNextColumn()
            if isDone then
                ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], "[X]")
            else
                ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "[ ]")
            end
            
            -- Title Column (Selectable)
            ImGui.TableNextColumn()
            local titleLabel = string.format("%s##Select_%s", q.title, q.id)
            if ImGui.Selectable(titleLabel, isSel, ImGuiSelectableFlags.SpanAllColumns) then
                DB.selectQuest(q.id)
            end
            
            -- Tooltip
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "%s", q.title)
                ImGui.Text("Zone: %s", q.zone_name)
                ImGui.Text("Quest Giver: %s", q.npc ~= "" and q.npc or "Unknown")
                ImGui.Text("Expansion: %s", q.exp_name)
                ImGui.EndTooltip()
            end
            
            -- Level Column
            ImGui.TableNextColumn()
            ImGui.Text("%d", q.min_lvl)
            
            -- Expansion Column
            ImGui.TableNextColumn()
            ImGui.Text("%s", q.exp)
        end
        ImGui.EndTable()
    end
    ImGui.EndChild()
    
    ImGui.SameLine()
    
    -- Right Pane: Selected Quest Walkthrough & Controls
    ImGui.BeginChild("QuestDetailChild##Right", 0, availY - 10, true)
    local q = state.selectedQuest
    if not q then
        ImGui.Dummy(10, 80)
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "  <-- Select a quest from the list to view its complete walkthrough,")
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "      interactive dialogue triggers, required turn-in items, and rewards.")
    else
        -- Quest Title Header
        ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], q.title)
        ImGui.SameLine(0, 15)
        ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], string.format("[%s]", q.exp_name))
        ImGui.SameLine(0, 10)
        ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], string.format("Level %d - %d", q.min_lvl, q.max_lvl))
        
        -- Badges & Completion Toggle
        local isCompleted = state.completedQuests[q.id] == true
        local btnLabel = isCompleted and "Mark Incomplete##Btn" or "Mark Completed##Btn"
        if ImGui.Button(btnLabel) then
            if isCompleted then
                state.completedQuests[q.id] = nil
            else
                state.completedQuests[q.id] = true
            end
            DB.savePersistence()
            DB.refreshActiveQuests()
        end
        
        ImGui.SameLine()
        if q.repeatable then
            ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], "[Repeatable]")
        else
            ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "[One-Time]")
        end
        
        ImGui.SameLine()
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], string.format("[%s]", q.group_size or "Solo"))
        
        ImGui.Separator()
        
        -- Quest Giver & Radar Box
        ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Quest Giver:")
        ImGui.SameLine()
        ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], q.npc)
        
        ImGui.SameLine(0, 15)
        ImGui.Text("Zone: %s", q.zone_name)
        
        if q.loc then
            ImGui.SameLine(0, 15)
            ImGui.Text("Loc: (%0.1f, %0.1f, %0.1f)", q.loc.y, q.loc.x, q.loc.z or 0)
        end
        
        -- Live Radar
        local isSpawned, spawnId, dist, heading = Engine.getNPCStatus(q.npc)
        if isSpawned then
            ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], string.format("Radar: [Spawned] %d meters away (%s)", dist, heading))
            ImGui.SameLine()
            if ImGui.Button("Target##NPC") then
                state.pendingAction = function() mq.cmdf('/target id %d', spawnId) end
            end
        else
            ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "Radar: [Not spawned / Out of range]")
        end
        
        ImGui.SameLine()
        if ImGui.Button("Navigate to NPC##Nav") then
            Engine.queueNavToNPC(q.npc, q.loc)
        end
        
        ImGui.Separator()
        
        -- Dialogue Triggers
        if q.triggers and #q.triggers > 0 then
            ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Dialogue Triggers:")
            
            -- Quick Hail button
            if ImGui.Button("Hail Quest Giver##Hail") then
                Engine.queueSay("Hail", q.npc)
            end
            
            for idx, tr in ipairs(q.triggers) do
                ImGui.SameLine()
                local bText = string.format("Say: \"%s\"##Trig_%d", tr, idx)
                if ImGui.Button(bText) then
                    Engine.queueSay(tr, q.npc)
                end
            end
            ImGui.Separator()
        end
        
        -- Required Items / Turn-Ins
        if q.items_required and #q.items_required > 0 then
            ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Required Turn-In Items:")
            for idx, item in ipairs(q.items_required) do
                local inBags, inBank = Engine.getInventoryCount(item.name)
                local countReq = item.count or 1
                local hasEnough = inBags >= countReq
                
                if hasEnough then
                    ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], string.format("  [OK] %dx %s (In Bags: %d, Bank: %d)", countReq, item.name, inBags, inBank))
                else
                    ImGui.TextColored(C_ERR[1], C_ERR[2], C_ERR[3], C_ERR[4], string.format("  [MISSING] %dx %s (In Bags: %d/%d, Bank: %d)", countReq, item.name, inBags, countReq, inBank))
                end
            end
            ImGui.Separator()
        end
        
        -- Rewards
        if (q.rewards and #q.rewards > 0) or (q.factions and #q.factions > 0) then
            ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Rewards:")
            if q.rewards then
                for _, rw in ipairs(q.rewards) do
                    ImGui.BulletText("%s", rw.name)
                end
            end
            if q.factions then
                for _, fc in ipairs(q.factions) do
                    local sign = fc.change > 0 and "+" or ""
                    local c = fc.change > 0 and C_GOOD or C_ERR
                    ImGui.TextColored(c[1], c[2], c[3], c[4], string.format("  Faction: %s%d with %s", sign, fc.change, fc.name))
                end
            end
            ImGui.Separator()
        end
        
        -- Walkthrough Narrative
        ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Walkthrough & Narrative Guide:")
        ImGui.SameLine()
        if ImGui.RadioButton("Formatted View##ViewFmt", state.walkthroughViewMode ~= "raw") then
            state.walkthroughViewMode = "formatted"
        end
        ImGui.SameLine(0, 15)
        if ImGui.RadioButton("Raw Text##ViewRaw", state.walkthroughViewMode == "raw") then
            state.walkthroughViewMode = "raw"
        end
        
        ImGui.BeginChild("WalkthroughTextChild", 0, 0, true)
        if state.walkthroughViewMode == "raw" then
            ImGui.TextWrapped("%s", q.walkthrough or "No walkthrough text recorded.")
        else
            UI.drawFormattedWalkthrough(q)
        end
        ImGui.EndChild()
    end
    
    ImGui.EndChild()
end

-- ---------------------------------------------------------------------------
-- Tab 2: Zone & Quest Lookup (Atlas Directory & Global Search)
-- ---------------------------------------------------------------------------
function UI.drawLookupTab()
    ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], "Lookup Mode:")
    ImGui.SameLine()
    if ImGui.RadioButton("Browse Zones & Quests##ModeZone", state.lookupMode == "zone") then
        state.lookupMode = "zone"
    end
    ImGui.SameLine(0, 20)
    if ImGui.RadioButton("Global Quest Search##ModeQuest", state.lookupMode == "quests") then
        state.lookupMode = "quests"
    end
    
    ImGui.Separator()
    
    if state.lookupMode == "zone" then
        UI.drawBrowseZonesView()
    else
        UI.drawGlobalQuestSearchView()
    end
end

-- Browse Zones View: Left zone directory, Right quests in selected zone
function UI.drawBrowseZonesView()
    local availX, availY = ImGui.GetContentRegionAvail()
    local leftWidth = 360
    
    -- Left Pane: Zone Directory
    ImGui.BeginChild("LookupZoneListChild##Left", leftWidth, availY - 10, true)
    ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "Norrath Zone Directory")
    
    -- Zone search input
    local curZSearch = (type(state.lookupZoneSearch) == "string") and state.lookupZoneSearch or ""
    local newZSearch, changedZSearch = ImGui.InputTextWithHint("##LookupZoneSearch", "Filter zones by name or short...", curZSearch)
    if changedZSearch and type(newZSearch) == "string" then
        state.lookupZoneSearch = newZSearch
    end
    ImGui.Separator()
    
    local flags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
    if ImGui.BeginTable("LookupZoneTable", 3, flags) then
        ImGui.TableSetupColumn("Zone Name", ImGuiTableColumnFlags.WidthStretch, 2)
        ImGui.TableSetupColumn("Exp", ImGuiTableColumnFlags.WidthFixed, 35)
        ImGui.TableSetupColumn("Quests", ImGuiTableColumnFlags.WidthFixed, 45)
        ImGui.TableHeadersRow()
        
        local filterText = (type(state.lookupZoneSearch) == "string") and state.lookupZoneSearch:lower() or ""
        for _, z in ipairs(state.zoneList) do
            local matchesEra = not state.limitServerEra or (z.exp <= (state.maxExpansionCap or 32))
            if matchesEra then
                local matchesSearch = true
                if filterText ~= "" then
                    local zn = z.name and z.name:lower() or ""
                    local zs = z.shortname and z.shortname:lower() or ""
                    if not zn:find(filterText, 1, true) and not zs:find(filterText, 1, true) then
                        matchesSearch = false
                    end
                end
                
                if matchesSearch then
                    ImGui.TableNextRow()
                    local isSel = state.selectedLookupZone == z.shortname
                    
                    -- Zone Name Column
                    ImGui.TableNextColumn()
                    local label = string.format("%s##Zone_%s", z.name, z.shortname)
                    if ImGui.Selectable(label, isSel, ImGuiSelectableFlags.SpanAllColumns) then
                        state.selectedLookupZone = z.shortname
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "%s", z.name)
                        ImGui.Text("Shortname: %s", z.shortname)
                        ImGui.Text("Expansion: %s (Exp %02d)", z.exp_name, z.exp)
                        ImGui.Text("Total Quests: %d", z.count)
                        ImGui.EndTooltip()
                    end
                    
                    -- Exp Column
                    ImGui.TableNextColumn()
                    ImGui.Text("%02d", z.exp)
                    
                    -- Quests Count Column
                    ImGui.TableNextColumn()
                    ImGui.Text("%d", z.count)
                end
            end
        end
        ImGui.EndTable()
    end
    ImGui.EndChild()
    
    ImGui.SameLine()
    
    -- Right Pane: Quests in Selected Zone
    ImGui.BeginChild("LookupZoneQuestsChild##Right", 0, availY - 10, true)
    
    local selShort = state.selectedLookupZone
    if not selShort or selShort == "" then
        selShort = (state.currentZone ~= "") and state.currentZone or (state.zoneList[1] and state.zoneList[1].shortname)
        state.selectedLookupZone = selShort
    end
    
    local selZoneObj = nil
    if selShort then
        for _, z in ipairs(state.zoneList) do
            if z.shortname == selShort then
                selZoneObj = z
                break
            end
        end
    end
    
    if selZoneObj then
        ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], selZoneObj.name)
        ImGui.SameLine()
        ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], string.format("[%s] (Exp %02d)", selZoneObj.exp_name, selZoneObj.exp))
        ImGui.SameLine()
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], string.format("(short: %s)", selZoneObj.shortname))
        
        ImGui.SameLine(0, 20)
        if ImGui.Button("Load in Zone Guide##Btn") then
            state.currentZone = selZoneObj.shortname
            state.currentZoneName = selZoneObj.name
            state.autoZoneSync = false
            DB.refreshActiveQuests()
            state.requestTab = "guide"
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Switches the Zone Guide tab to display this zone and disengages Auto-Sync.")
            ImGui.EndTooltip()
        end
        
        ImGui.Separator()
        
        -- Get all catalog quests for this zone
        local zoneQuests = {}
        for _, q in ipairs(state.catalog) do
            if q.zone:lower() == selShort:lower() then
                local expNum = tonumber(q.exp) or 0
                local eraMatch = not state.limitServerEra or (expNum <= (state.maxExpansionCap or 32))
                local hideDone = state.hideCompleted and (state.completedQuests[q.id] == true)
                if eraMatch and not hideDone then
                    table.insert(zoneQuests, q)
                end
            end
        end
        
        ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], string.format("Quests in Zone: %d", #zoneQuests))
        
        local qflags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
        if ImGui.BeginTable("LookupZoneQuestsTable", 5, qflags) then
            ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 30)
            ImGui.TableSetupColumn("Quest Title", ImGuiTableColumnFlags.WidthStretch, 2)
            ImGui.TableSetupColumn("Quest Giver", ImGuiTableColumnFlags.WidthFixed, 140)
            ImGui.TableSetupColumn("Lvl", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 75)
            ImGui.TableHeadersRow()
            
            for _, q in ipairs(zoneQuests) do
                ImGui.TableNextRow()
                local isDone = state.completedQuests[q.id] == true
                
                -- Status
                ImGui.TableNextColumn()
                if isDone then
                    ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], "[X]")
                else
                    ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "[ ]")
                end
                
                -- Title
                ImGui.TableNextColumn()
                ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], "%s", q.title)
                
                -- NPC Giver
                ImGui.TableNextColumn()
                ImGui.Text("%s", (q.npc and q.npc ~= "") and q.npc or "Unknown")
                
                -- Level
                ImGui.TableNextColumn()
                ImGui.Text("%d", q.min_lvl or 1)
                
                -- Action: Open Guide
                ImGui.TableNextColumn()
                local btnId = string.format("Guide##Q_%s", q.id)
                if ImGui.Button(btnId) then
                    state.currentZone = selZoneObj.shortname
                    state.currentZoneName = selZoneObj.name
                    state.autoZoneSync = false
                    DB.selectQuest(q.id)
                    DB.refreshActiveQuests()
                    state.requestTab = "guide"
                end
            end
            ImGui.EndTable()
        end
    else
        ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "Select a zone from the directory on the left.")
    end
    
    ImGui.EndChild()
end

-- Global Quest Search View: Search across all 2,600+ quests in Norrath
function UI.drawGlobalQuestSearchView()
    local availX, availY = ImGui.GetContentRegionAvail()
    
    -- Global Search Input Bar
    ImGui.SetNextItemWidth(350)
    local curSearch = (type(state.lookupQuestSearch) == "string") and state.lookupQuestSearch or ""
    local newSearch, changedSearch = ImGui.InputTextWithHint("##GlobalQuestSearchInput", "Search 2,600+ quests by title, NPC, or zone...", curSearch)
    if changedSearch and type(newSearch) == "string" then
        state.lookupQuestSearch = newSearch
    end
    
    ImGui.SameLine()
    local qterm = (type(state.lookupQuestSearch) == "string") and state.lookupQuestSearch:lower() or ""
    if qterm ~= "" and ImGui.Button("Clear##ClearLookupSearch") then
        state.lookupQuestSearch = ""
        qterm = ""
    end
    
    ImGui.Separator()
    
    -- Results Table Child
    ImGui.BeginChild("GlobalQuestResultsChild", 0, availY - 10, true)
    
    -- Filter results from catalog
    local results = {}
    local totalMatches = 0
    for _, q in ipairs(state.catalog) do
        local expNum = tonumber(q.exp) or 0
        local eraMatch = not state.limitServerEra or (expNum <= (state.maxExpansionCap or 32))
        if eraMatch then
            local isDone = state.completedQuests[q.id] == true
            local hideDone = state.hideCompleted and isDone
            if not hideDone then
                local textMatch = true
                if qterm ~= "" then
                    local t = q.title and q.title:lower() or ""
                    local n = q.npc and q.npc:lower() or ""
                    local z = q.zone and q.zone:lower() or ""
                    local zn = q.zone_name and q.zone_name:lower() or ""
                    if not t:find(qterm, 1, true) and not n:find(qterm, 1, true) and not z:find(qterm, 1, true) and not zn:find(qterm, 1, true) then
                        textMatch = false
                    end
                end
                
                if textMatch then
                    totalMatches = totalMatches + 1
                    if #results < 200 then
                        table.insert(results, q)
                    end
                end
            end
        end
    end
    
    local countMsg = string.format("Found %d matching quest%s", totalMatches, totalMatches == 1 and "" or "s")
    if totalMatches > #results then
        countMsg = countMsg .. string.format(" (displaying top %d)", #results)
    end
    ImGui.TextColored(C_GOLD[1], C_GOLD[2], C_GOLD[3], C_GOLD[4], countMsg)
    
    local flags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
    if ImGui.BeginTable("GlobalQuestSearchTable", 6, flags) then
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 30)
        ImGui.TableSetupColumn("Title", ImGuiTableColumnFlags.WidthStretch, 2)
        ImGui.TableSetupColumn("Zone", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableSetupColumn("Quest Giver", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableSetupColumn("Exp", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableHeadersRow()
        
        for _, q in ipairs(results) do
            ImGui.TableNextRow()
            local isDone = state.completedQuests[q.id] == true
            
            -- Status
            ImGui.TableNextColumn()
            if isDone then
                ImGui.TextColored(C_GOOD[1], C_GOOD[2], C_GOOD[3], C_GOOD[4], "[X]")
            else
                ImGui.TextColored(C_MUTED[1], C_MUTED[2], C_MUTED[3], C_MUTED[4], "[ ]")
            end
            
            -- Title
            ImGui.TableNextColumn()
            ImGui.TextColored(C_BRIGHT[1], C_BRIGHT[2], C_BRIGHT[3], C_BRIGHT[4], "%s", q.title)
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.TextColored(C_CYAN[1], C_CYAN[2], C_CYAN[3], C_CYAN[4], "%s", q.title)
                ImGui.Text("Zone: %s (%s)", q.zone_name, q.zone)
                ImGui.Text("Quest Giver: %s", (q.npc and q.npc ~= "") and q.npc or "Unknown")
                ImGui.Text("Expansion: %s (Exp %s)", q.exp_name, q.exp)
                ImGui.Text("Level Range: %d - %d", q.min_lvl, q.max_lvl)
                ImGui.EndTooltip()
            end
            
            -- Zone
            ImGui.TableNextColumn()
            ImGui.Text("%s", q.zone_name)
            
            -- NPC
            ImGui.TableNextColumn()
            ImGui.Text("%s", (q.npc and q.npc ~= "") and q.npc or "Unknown")
            
            -- Exp
            ImGui.TableNextColumn()
            ImGui.Text("%s", q.exp)
            
            -- Action
            ImGui.TableNextColumn()
            local btnLabel = string.format("Guide##GlobalQ_%s", q.id)
            if ImGui.Button(btnLabel) then
                state.currentZone = q.zone
                state.currentZoneName = q.zone_name
                state.autoZoneSync = false
                DB.selectQuest(q.id)
                DB.refreshActiveQuests()
                state.requestTab = "guide"
            end
        end
        
        ImGui.EndTable()
    end
    
    ImGui.EndChild()
end

function UI.drawQuestGuide()
    if not state.open then return end
    
    pushTheme()
    
    ImGui.SetNextWindowSize(980, 680, ImGuiCond.FirstUseEver)
    local openFlag, draw = ImGui.Begin("Triune Quest Guide##MainWindow", state.open)
    if not openFlag then
        state.open = false
        ImGui.End()
        popTheme()
        return
    end
    
    if draw then
        local ok, err = pcall(UI.renderWindowContent)
        if not ok then
            ImGui.TextColored(C_ERR[1], C_ERR[2], C_ERR[3], C_ERR[4], "Render error: " .. tostring(err))
        end
    end
    
    ImGui.End()
    popTheme()
end

-- ---------------------------------------------------------------------------
-- Main Initialization and Execution Loop
-- ---------------------------------------------------------------------------
local function main()
    print("\ag[TriuneQuest]\ax Starting Triune Quest Guide...")
    if not DB.init() then
        return
    end
    
    -- Setup current zone
    pcall(function()
        state.currentZone = mq.TLO.Zone.ShortName() or ""
        state.currentZoneName = mq.TLO.Zone.Name() or ""
    end)
    
    DB.refreshActiveQuests()
    
    -- Register ImGui render callback
    mq.imgui.init("TriuneQuestGuide", UI.drawQuestGuide)
    
    local lastZoneCheck = 0
    while state.isRunning and state.open do
        -- Handle zone transitions
        local now = os.time()
        if state.autoZoneSync and (now - lastZoneCheck >= 2) then
            lastZoneCheck = now
            local zShort = ""
            local zName = ""
            pcall(function()
                zShort = mq.TLO.Zone.ShortName() or ""
                zName = mq.TLO.Zone.Name() or ""
            end)
            if zShort ~= "" and zShort ~= state.currentZone then
                state.currentZone = zShort
                state.currentZoneName = zName
                DB.refreshActiveQuests()
            end
        end
        
        -- Execute any queued action in main coroutine thread
        if state.pendingAction then
            local act = state.pendingAction
            state.pendingAction = nil
            pcall(act)
        end
        
        mq.delay(50)
    end
    
    print("\ay[TriuneQuest]\ax Exited.")
end

main()
