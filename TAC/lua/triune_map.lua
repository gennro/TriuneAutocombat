---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TRIUNE MAP v1.0 (Standalone In-Game Map & NPC Tracker)
-- ----------------------------------------------------------------------------
-- Live 2D EverQuest map replacement and zone tracker for MacroQuest ImGui.
-- Features:
--   - Auto-loads map line and label files from EverQuest maps directory (Layers 0-3).
--   - Interactive 2D map viewport: smooth pan, zoom, follow-player, and Z-filtering.
--   - Entity overlays for Player, Group, Raid, Pets, Corpses, and all Zone NPCs.
--   - Real-time Navmesh Reachability: Visualizes NPCs as Green (Pathable) or Red (Unreachable).
--   - Map Click-to-Move: Click on any terrain location or double-click an NPC to navigate.
--   - Dedicated NPC Tracking tab with live search, consideration, and pathability filters.
-- Compatible with MacroQuest LuaJIT (Lua 5.1 safe).
-- Run via:  /lua run triune_map
-- Stop via: /lua stop triune_map
-- ============================================================================

local mq    = require('mq')
local ImGui = require('ImGui')
local bit   = require('bit') -- LuaJIT bitwise library

local VERSION = '1.1'

-- ============================================================================
-- THEME & STYLE HELPERS (Unified Dark Cyan/Blue Theme)
-- ============================================================================
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

-- Consideration Colors & Badges
local CON_COLOR_MAP = {
    ['DARK RED']   = { r = 0.85, g = 0.10, b = 0.10, badge = '[DRK]' },
    ['RED']        = { r = 0.95, g = 0.25, b = 0.25, badge = '[RED]' },
    ['YELLOW']     = { r = 1.00, g = 0.90, b = 0.20, badge = '[YEL]' },
    ['WHITE']      = { r = 0.95, g = 0.95, b = 0.95, badge = '[WHT]' },
    ['BLUE']       = { r = 0.30, g = 0.60, b = 1.00, badge = '[BLU]' },
    ['LIGHT BLUE'] = { r = 0.40, g = 0.80, b = 1.00, badge = '[LBL]' },
    ['GREEN']      = { r = 0.20, g = 0.90, b = 0.35, badge = '[GRN]' },
    ['GREY']       = { r = 0.60, g = 0.60, b = 0.60, badge = '[GRY]' },
    ['GRAY']       = { r = 0.60, g = 0.60, b = 0.60, badge = '[GRY]' },
}

local function getConStyle(conStr)
    local upper = string.upper(tostring(conStr or ''))
    return CON_COLOR_MAP[upper] or { r = 0.70, g = 0.70, b = 0.70, badge = '[UNK]' }
end

local CON_OPTIONS = {
    'All Considerations',
    'Red / Dark Red',
    'Yellow',
    'White',
    'Blue',
    'Light Blue',
    'Green',
    'Grey',
}

local SORT_OPTIONS = {
    'Nearest First',
    'Farthest First',
    'Level (High -> Low)',
    'Level (Low -> High)',
    'Name (A - Z)',
}

local COLOR_MODE_OPTIONS = {
    'Dual (Con Dot + Nav Halo)',
    'Navmesh Validity (Green/Red)',
    'Consideration Colors Only',
}

local ATLAS_ERA_OPTIONS = {
    'All Expansions',
    'Classic',
    'Kunark',
    'Velious',
    'Luclin',
    'Planes of Power',
    'Legacy of Ykesha',
    'Gates of Discord',
    'Omens of War',
    'The Serpent\'s Spine',
    'Hubs & Special',
    'Custom / Other',
}

local ATLAS_TYPE_OPTIONS = {
    'All Zone Types',
    'Cities & Hubs',
    'Outdoor & Wilderness',
    'Dungeons',
    'Planes',
    'Raid Zones',
}

-- ============================================================================
-- STRUCTURED STATE TABLES (Prevents hitting Lua 200 local limit)
-- ============================================================================
local state = {
    openGUI             = true,
    isRunning           = true,
    activeTab           = 1, -- 1: Map View, 2: Zone Atlas, 3: NPC Tracker, 4: Settings & Layers
    requestedTab        = nil, -- When set, forces ImGui to switch active tab via SetSelected
    currentZoneId       = 0,
    currentZoneShort    = '',
    currentZoneName     = 'Unknown Zone',
    statusMsg           = 'Ready',
    lastScanTime        = 0,
    scanIntervalMs      = 300,
    lastZoneCheckTime   = 0,
    -- Maps Directory & Subfolder Management
    baseMapsDirectory   = nil,
    activeMapsDirectory = nil,
    mapFolders          = {},   -- list of { name = string, relPath = string, fullPath = string }
    mapFolderNames      = { '[Root] Default (maps/)' },
    selectedFolderIndex = 1,
    customMapsDir       = '',

    -- Atlas Explorer & POI Navigator State
    viewMode            = 'LIVE', -- 'LIVE' or 'ATLAS'
    atlasZoneShort      = '',
    atlasZoneName       = '',
    atlasHistory        = {},     -- list of zoneShort strings
    atlasHistoryIdx     = 0,
    atlasSearchText     = '',
    atlasEraFilterIdx   = 1,      -- Index into ATLAS_ERA_OPTIONS
    atlasTypeFilterIdx  = 1,      -- Index into ATLAS_TYPE_OPTIONS
    atlasSelectedZone   = nil,    -- table pointer to current selected zone in atlas catalog
    atlasZoneList       = {},     -- filtered list of zones for UI table
    atlasAllZones       = {},     -- master registry of built-in + discovered zones
    poiSearchText       = '',
    showPoiDrawer       = false,
    highlightedPoi      = nil,    -- { x = num, y = num, z = num, text = string, time = num }

    -- UI tracking filter controls
    searchText          = '',
    conFilterIndex      = 1,
    minLevel            = 1,
    maxLevel            = 150,
    maxDistance         = 5000,
    sortIndex           = 1,
    pathableOnly        = false,
    losOnly             = false,

    -- Settings Persistence State
    dirtySettings       = false,
    dirtySettingsTime   = 0,

    -- Tooltip & Mouse Hover State
    hoveredMobId        = 0,
    cursorWorldX        = 0,
    cursorWorldY        = 0,
    cursorWorldZ        = 0,

    -- Active Navigation Target / Ground Loc
    activeNavLoc        = nil,
    activeNavSpawnId    = 0,
    activeNavCommandTime = 0,

    -- Triune Loadout & Combat / Waypoint Data
    triuneData = {
        isLoaded            = false,
        lastSyncTime        = 0,
        charName            = '',
        campLoc             = nil, -- { x = 0, y = 0, z = 0 }
        campRadius          = 50,
        combatRadius        = 100,
        hunterRadius        = 250,
        pullRadius          = 200,
        useWaypoints        = false,
        waypoints           = {},
        waypointRadius      = 20,
        waypointScanRadius  = 100,
        waypointLoop        = false,
        currentWaypointIdx  = 1,
        zoneHazards         = {},
    },

    -- Smart Auto-Z & Floor Level State
    smartFloor = {
        minZ                = -99999,
        maxZ                = 99999,
        activeZ             = 0,
        overrideOffset      = 0, -- User floor peek offset (+25, -25, etc.)
        lastCalcTime        = 0,
        lastCalcX           = 0,
        lastCalcY           = 0,
        lastCalcZ           = 0,
        lastOffset          = 0,
        floorLabel          = 'Level Ground',
        isMultiFloor        = false,
    },
}

local ctrl = {
    -- Map Viewport Settings
    followPlayer        = true,
    showLabels          = true,
    showGrid            = true,
    showNPCs            = true,
    showPCs             = true,
    showGroup           = true,
    showRaid            = true,
    showPets            = false,
    showCorpses         = false,
    showNPCNames        = false,
    showNavLine         = true,
    colorModeIndex      = 1, -- 1: Dual, 2: Navmesh Only, 3: Con Only

    -- Triune Combat & Waypoint Overlays
    showSearchRadius    = true,
    showCampRadius      = true,
    showPullRadius      = true,
    showWaypoints       = true,
    showHazards         = true,
    customSearchRadius  = 200,

    -- Layer Visibility Toggles (Layer 0, 1, 2, 3, Labels)
    layer0              = true,
    layer1              = true,
    layer2              = true,
    layer3              = true,
    layerLabels         = true,

    -- Z-Height Filtering (Smart Auto-Z / Multi-floor Dungeons)
    zFilterMode         = 1, -- 1: Auto-Z (Smart Floor Isolation), 2: Manual Window, 3: Disabled
    zDepthFading        = true, -- Smooth alpha depth fading on stairs/ramps
    zFilterRange        = 45, -- +/- yards in Manual Mode

    -- Visual Display Scaling & Contrast
    boostDarkLines      = true, -- Auto-brighten black/dark map lines & labels for high contrast on dark backgrounds
    lineThickness       = 1.0,
    npcNodeRadius       = 4.5,
    playerNodeRadius    = 6.0,
    labelFontSize       = 12,
}

local viewport = {
    centerEqX           = 0,
    centerEqY           = 0,
    zoom                = 0.5,   -- Pixels per EQ yard
    minZoom             = 0.05,
    maxZoom             = 10.0,
    isDragging          = false,
    dragStartMouseX     = 0,
    dragStartMouseY     = 0,
    dragStartCenterEqX  = 0,
    dragStartCenterEqY  = 0,
}

local mapData = {
    isLoaded            = false,
    zoneShort           = '',
    layers              = { [0] = {}, [1] = {}, [2] = {}, [3] = {} },
    labels              = {},
    totalLines          = 0,
    totalLabels         = 0,
    bounds              = { minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0 },
}

local spawns = {
    allNPCs             = {},
    filteredNPCs        = {},
    allPCs              = {},
    groupMembers        = {},
    totalCount          = 0,
}

local navState = {
    meshLoaded          = false,
    navActive           = false,
    cache               = {}, -- [id] = { hasPath = bool, length = num, checkedAt = time }
    checkQueue          = {}, -- array of IDs needing path checks
    queueSet            = {}, -- lookup set to prevent queue duplicates
    batchSize           = 4,
    lastQueueProcessTime = 0,
}

local actionQueue = {
    pendingTargetId     = 0,
    pendingNavId        = 0,
    pendingNavLoc       = nil, -- { y = num, x = num, z = num }
    pendingStopNav      = false,
    pendingZoneReload   = false,
}

-- ============================================================================
-- PERSISTENCE & CONFIGURATION (triune_map_config.lua in mq.configDir)
-- ============================================================================
local CONFIG_FILE = mq.configDir and (mq.configDir .. '/triune_map_config.lua') or 'triune_map_config.lua'

local function serializeValue(val, indent)
    indent = indent or 1
    local indStr = string.rep('  ', indent)
    if type(val) == 'string' then
        return string.format("%q", val)
    elseif type(val) == 'number' or type(val) == 'boolean' then
        return tostring(val)
    elseif type(val) == 'table' then
        local parts = {}
        for k, v in pairs(val) do
            local keyStr = (type(k) == 'number') and string.format("[%d]", k) or string.format("[%q]", tostring(k))
            local valStr = serializeValue(v, indent + 1)
            if valStr then
                parts[#parts + 1] = indStr .. keyStr .. " = " .. valStr
            end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep('  ', indent - 1) .. "}"
    end
    return "nil"
end

local function charKey()
    local myName, myServer = nil, nil
    pcall(function()
        myName   = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    return (myServer or 'default') .. '_' .. (myName or 'default')
end

local function saveConfig(silent)
    if not CONFIG_FILE then return end
    local allData = {}
    local fn = loadfile(CONFIG_FILE)
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == 'table' then allData = t end
    end

    allData.__global = {
        customMapsDir       = state.customMapsDir or '',
        selectedMapFolder   = state.mapFolderNames[state.selectedFolderIndex] or '',
    }

    local activeFolder = state.mapFolderNames[state.selectedFolderIndex] or ''

    allData[charKey()] = {
        -- Viewport & Zoom
        zoom                = viewport.zoom,
        followPlayer        = ctrl.followPlayer,

        -- Display & Layer Toggles
        showLabels          = ctrl.showLabels,
        showGrid            = ctrl.showGrid,
        showNPCs            = ctrl.showNPCs,
        showPCs             = ctrl.showPCs,
        showGroup           = ctrl.showGroup,
        showRaid            = ctrl.showRaid,
        showPets            = ctrl.showPets,
        showCorpses         = ctrl.showCorpses,
        showNPCNames        = ctrl.showNPCNames,
        showNavLine         = ctrl.showNavLine,
        colorModeIndex      = ctrl.colorModeIndex,

        -- Triune Overlays
        showSearchRadius    = ctrl.showSearchRadius,
        showCampRadius      = ctrl.showCampRadius,
        showPullRadius      = ctrl.showPullRadius,
        showWaypoints       = ctrl.showWaypoints,
        showHazards         = ctrl.showHazards,
        customSearchRadius  = ctrl.customSearchRadius,

        -- Map Layers 0-3
        layer0              = ctrl.layer0,
        layer1              = ctrl.layer1,
        layer2              = ctrl.layer2,
        layer3              = ctrl.layer3,
        layerLabels         = ctrl.layerLabels,

        -- Z-Height Filtering & Smart Auto-Z
        zFilterMode         = ctrl.zFilterMode,
        zDepthFading        = ctrl.zDepthFading,
        zFilterRange        = ctrl.zFilterRange,

        -- Visual Geometry
        lineThickness       = ctrl.lineThickness,
        npcNodeRadius       = ctrl.npcNodeRadius,
        playerNodeRadius    = ctrl.playerNodeRadius,

        -- Tracker & Atlas Filters
        conFilterIndex      = state.conFilterIndex,
        sortColumn          = state.sortColumn,
        sortAsc             = state.sortAsc,
        pathableOnly        = state.pathableOnly,
        losOnly             = state.losOnly,
        atlasEraFilterIdx   = state.atlasEraFilterIdx,
        atlasTypeFilterIdx  = state.atlasTypeFilterIdx,
        showPoiDrawer       = state.showPoiDrawer,
        activeMapFolder     = activeFolder,
    }

    local f = io.open(CONFIG_FILE, 'w')
    if f then
        f:write("return " .. serializeValue(allData) .. "\n")
        f:close()
        if not silent then
            print('\ag[Triune Map]\ax Settings and zoom saved to ' .. tostring(CONFIG_FILE))
        end
    end
end

local function loadConfig()
    if not CONFIG_FILE then return end
    local fn = loadfile(CONFIG_FILE)
    if not fn then return end
    local ok, allData = pcall(fn)
    if not ok or type(allData) ~= 'table' then return end

    -- 1. Global settings
    if type(allData.__global) == 'table' then
        if allData.__global.customMapsDir ~= nil then
            state.customMapsDir = allData.__global.customMapsDir
        end
    end

    -- 2. Character settings
    local cData = allData[charKey()]
    if type(cData) ~= 'table' then
        cData = allData['default_default'] or {}
    end

    if type(cData) == 'table' then
        if cData.zoom ~= nil then
            local zVal = tonumber(cData.zoom) or viewport.zoom
            viewport.zoom = math.max(viewport.minZoom, math.min(viewport.maxZoom, zVal))
        end
        if cData.followPlayer ~= nil then ctrl.followPlayer = (cData.followPlayer == true) end

        if cData.showLabels ~= nil then ctrl.showLabels = (cData.showLabels == true) end
        if cData.showGrid ~= nil then ctrl.showGrid = (cData.showGrid == true) end
        if cData.showNPCs ~= nil then ctrl.showNPCs = (cData.showNPCs == true) end
        if cData.showPCs ~= nil then ctrl.showPCs = (cData.showPCs == true) end
        if cData.showGroup ~= nil then ctrl.showGroup = (cData.showGroup == true) end
        if cData.showRaid ~= nil then ctrl.showRaid = (cData.showRaid == true) end
        if cData.showPets ~= nil then ctrl.showPets = (cData.showPets == true) end
        if cData.showCorpses ~= nil then ctrl.showCorpses = (cData.showCorpses == true) end
        if cData.showNPCNames ~= nil then ctrl.showNPCNames = (cData.showNPCNames == true) end
        if cData.showNavLine ~= nil then ctrl.showNavLine = (cData.showNavLine == true) end
        if cData.colorModeIndex ~= nil then ctrl.colorModeIndex = tonumber(cData.colorModeIndex) or 1 end

        if cData.showSearchRadius ~= nil then ctrl.showSearchRadius = (cData.showSearchRadius == true) end
        if cData.showCampRadius ~= nil then ctrl.showCampRadius = (cData.showCampRadius == true) end
        if cData.showPullRadius ~= nil then ctrl.showPullRadius = (cData.showPullRadius == true) end
        if cData.showWaypoints ~= nil then ctrl.showWaypoints = (cData.showWaypoints == true) end
        if cData.showHazards ~= nil then ctrl.showHazards = (cData.showHazards == true) end
        if cData.customSearchRadius ~= nil then ctrl.customSearchRadius = tonumber(cData.customSearchRadius) or 200 end

        if cData.layer0 ~= nil then ctrl.layer0 = (cData.layer0 == true) end
        if cData.layer1 ~= nil then ctrl.layer1 = (cData.layer1 == true) end
        if cData.layer2 ~= nil then ctrl.layer2 = (cData.layer2 == true) end
        if cData.layer3 ~= nil then ctrl.layer3 = (cData.layer3 == true) end
        if cData.layerLabels ~= nil then ctrl.layerLabels = (cData.layerLabels == true) end

        if cData.zFilterMode ~= nil then
            ctrl.zFilterMode = tonumber(cData.zFilterMode) or 1
        elseif cData.useZFilter ~= nil then
            ctrl.zFilterMode = cData.useZFilter and 2 or 3
        end
        if cData.zDepthFading ~= nil then ctrl.zDepthFading = (cData.zDepthFading == true) end
        if cData.zFilterRange ~= nil then ctrl.zFilterRange = tonumber(cData.zFilterRange) or 45 end

        if cData.lineThickness ~= nil then ctrl.lineThickness = tonumber(cData.lineThickness) or 1.0 end
        if cData.npcNodeRadius ~= nil then ctrl.npcNodeRadius = tonumber(cData.npcNodeRadius) or 4.5 end
        if cData.playerNodeRadius ~= nil then ctrl.playerNodeRadius = tonumber(cData.playerNodeRadius) or 6.0 end

        if cData.conFilterIndex ~= nil then state.conFilterIndex = tonumber(cData.conFilterIndex) or 1 end
        if cData.sortColumn ~= nil then state.sortColumn = cData.sortColumn end
        if cData.sortAsc ~= nil then state.sortAsc = (cData.sortAsc == true) end
        if cData.pathableOnly ~= nil then state.pathableOnly = (cData.pathableOnly == true) end
        if cData.losOnly ~= nil then state.losOnly = (cData.losOnly == true) end
        if cData.atlasEraFilterIdx ~= nil then state.atlasEraFilterIdx = tonumber(cData.atlasEraFilterIdx) or 1 end
        if cData.atlasTypeFilterIdx ~= nil then state.atlasTypeFilterIdx = tonumber(cData.atlasTypeFilterIdx) or 1 end
        if cData.showPoiDrawer ~= nil then state.showPoiDrawer = (cData.showPoiDrawer == true) end

        local savedFolder = cData.activeMapFolder or (allData.__global and allData.__global.selectedMapFolder)
        if savedFolder and savedFolder ~= '' then
            for idx, fName in ipairs(state.mapFolderNames) do
                if fName == savedFolder then
                    state.selectedFolderIndex = idx
                    state.activeMapsDirectory = state.mapFolders[idx] and state.mapFolders[idx].fullPath
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- NORRATH ZONE REGISTRY & ATLAS DATABASE
-- ============================================================================
local NORRATH_ZONE_REGISTRY = {
    -- CLASSIC: ANTONICA
    { short = 'qeynos',       name = 'South Qeynos',                   era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'qeynos2', 'qrg', 'erudsxing'} },
    { short = 'qeynos2',      name = 'North Qeynos',                   era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'qeynos', 'qeytoqrg'} },
    { short = 'qeytoqrg',     name = 'Qeynos Hills',                   era = 'Classic',          continent = 'Antonica',             level = '1-15',  type = 'Outdoor', connections = {'qeynos2', 'blackburrow', 'qrg', 'northkarana'} },
    { short = 'qrg',          name = 'Surefall Glade',                 era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'qeytoqrg'} },
    { short = 'blackburrow',  name = 'Blackburrow',                    era = 'Classic',          continent = 'Antonica',             level = '5-20',  type = 'Dungeon', connections = {'qeytoqrg', 'everfrost'} },
    { short = 'everfrost',    name = 'Everfrost Peaks',                era = 'Classic',          continent = 'Antonica',             level = '1-25',  type = 'Outdoor', connections = {'blackburrow', 'halas', 'permafrost'} },
    { short = 'halas',        name = 'Halas',                          era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'everfrost'} },
    { short = 'permafrost',   name = 'Permafrost Keep',                era = 'Classic',          continent = 'Antonica',             level = '20-50', type = 'Dungeon', connections = {'everfrost'} },
    { short = 'northkarana',  name = 'Northern Plains of Karana',      era = 'Classic',          continent = 'Antonica',             level = '10-30', type = 'Outdoor', connections = {'qeytoqrg', 'southkarana', 'eastkarana'} },
    { short = 'southkarana',  name = 'Southern Plains of Karana',      era = 'Classic',          continent = 'Antonica',             level = '20-35', type = 'Outdoor', connections = {'northkarana', 'lakerathe', 'paw'} },
    { short = 'eastkarana',   name = 'Eastern Plains of Karana',       era = 'Classic',          continent = 'Antonica',             level = '15-30', type = 'Outdoor', connections = {'northkarana', 'beholder', 'highpass'} },
    { short = 'beholder',     name = 'Gorge of King Xorbb',            era = 'Classic',          continent = 'Antonica',             level = '15-25', type = 'Outdoor', connections = {'eastkarana', 'runnyeye'} },
    { short = 'runnyeye',     name = 'Clan RunnyEye',                  era = 'Classic',          continent = 'Antonica',             level = '15-30', type = 'Dungeon', connections = {'beholder', 'misty'} },
    { short = 'highpass',     name = 'Highpass Hold',                  era = 'Classic',          continent = 'Antonica',             level = '15-25', type = 'Outdoor', connections = {'eastkarana', 'highkeep', 'kithicor'} },
    { short = 'highkeep',     name = 'High Keep',                      era = 'Classic',          continent = 'Antonica',             level = '20-40', type = 'Dungeon', connections = {'highpass'} },
    { short = 'kithicor',     name = 'Kithicor Forest',                era = 'Classic',          continent = 'Antonica',             level = '20-50', type = 'Outdoor', connections = {'highpass', 'wcommons', 'rivervale'} },
    { short = 'wcommons',     name = 'West Commonlands',               era = 'Classic',          continent = 'Antonica',             level = '5-20',  type = 'Outdoor', connections = {'ecommons', 'kithicor', 'befallen'} },
    { short = 'ecommons',     name = 'East Commonlands',               era = 'Classic',          continent = 'Antonica',             level = '1-15',  type = 'Outdoor', connections = {'nektulos', 'nro', 'wcommons', 'freportw'} },
    { short = 'freportw',     name = 'West Freeport',                  era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'ecommons', 'freporte', 'freportn'} },
    { short = 'freporte',     name = 'East Freeport',                  era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'freportw', 'freportn', 'nro', 'oceanoftears'} },
    { short = 'freportn',     name = 'North Freeport',                 era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'freporte', 'freportw'} },
    { short = 'befallen',     name = 'Befallen',                       era = 'Classic',          continent = 'Antonica',             level = '10-25', type = 'Dungeon', connections = {'wcommons'} },
    { short = 'nro',          name = 'Northern Desert of Ro',          era = 'Classic',          continent = 'Antonica',             level = '10-25', type = 'Outdoor', connections = {'freporte', 'ecommons', 'oasis'} },
    { short = 'oasis',        name = 'Oasis of Marr',                  era = 'Classic',          continent = 'Antonica',             level = '10-35', type = 'Outdoor', connections = {'nro', 'sro', 'timorous'} },
    { short = 'sro',          name = 'Southern Desert of Ro',          era = 'Classic',          continent = 'Antonica',             level = '20-35', type = 'Outdoor', connections = {'oasis', 'innothule', 'guktop'} },
    { short = 'innothule',    name = 'Innothule Swamp',                era = 'Classic',          continent = 'Antonica',             level = '1-15',  type = 'Outdoor', connections = {'sro', 'grobb', 'feerrott', 'guktop'} },
    { short = 'grobb',        name = 'Grobb',                          era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'innothule'} },
    { short = 'feerrott',     name = 'The Feerrott',                   era = 'Classic',          continent = 'Antonica',             level = '1-25',  type = 'Outdoor', connections = {'innothule', 'oggok', 'cazicthule', 'rathemtn'} },
    { short = 'oggok',        name = 'Oggok',                          era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'feerrott'} },
    { short = 'cazicthule',   name = 'Lost Temple of Cazic-Thule',     era = 'Classic',          continent = 'Antonica',             level = '45-60', type = 'Dungeon', connections = {'feerrott'} },
    { short = 'rathemtn',     name = 'Mountains of Rathe',             era = 'Classic',          continent = 'Antonica',             level = '10-35', type = 'Outdoor', connections = {'feerrott', 'lakerathe'} },
    { short = 'lakerathe',    name = 'Lake Rathetear',                 era = 'Classic',          continent = 'Antonica',             level = '10-30', type = 'Outdoor', connections = {'rathemtn', 'southkarana', 'arena'} },
    { short = 'arena',        name = 'The Arena',                      era = 'Classic',          continent = 'Antonica',             level = '1-65',  type = 'City',    connections = {'lakerathe'} },
    { short = 'paw',          name = 'Infected Paw',                   era = 'Classic',          continent = 'Antonica',             level = '25-50', type = 'Dungeon', connections = {'southkarana'} },
    { short = 'guktop',       name = 'Upper Guk',                      era = 'Classic',          continent = 'Antonica',             level = '10-30', type = 'Dungeon', connections = {'innothule', 'gukbottom'} },
    { short = 'gukbottom',    name = 'The Ruins of Old Guk',           era = 'Classic',          continent = 'Antonica',             level = '30-50', type = 'Dungeon', connections = {'guktop'} },
    { short = 'lavastorm',    name = 'Lavastorm Mountains',            era = 'Classic',          continent = 'Antonica',             level = '10-35', type = 'Outdoor', connections = {'nektulos', 'soldunga', 'soldungb', 'soltemple', 'najena'} },
    { short = 'soldunga',     name = 'Solusek\'s Eye (Sol A)',         era = 'Classic',          continent = 'Antonica',             level = '20-40', type = 'Dungeon', connections = {'lavastorm', 'soldungb'} },
    { short = 'soldungb',     name = 'Nagafen\'s Lair (Sol B)',        era = 'Classic',          continent = 'Antonica',             level = '35-55', type = 'Dungeon', connections = {'lavastorm', 'soldunga'} },
    { short = 'soltemple',    name = 'Temple of Solusek Ro',           era = 'Classic',          continent = 'Antonica',             level = '1-65',  type = 'Dungeon', connections = {'lavastorm'} },
    { short = 'najena',       name = 'Najena',                         era = 'Classic',          continent = 'Antonica',             level = '15-35', type = 'Dungeon', connections = {'lavastorm'} },
    { short = 'nektulos',     name = 'Nektulos Forest',                era = 'Classic',          continent = 'Antonica',             level = '1-20',  type = 'Outdoor', connections = {'lavastorm', 'neriakb', 'ecommons'} },
    { short = 'neriaka',      name = 'Neriak - Foreign Quarter',       era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'nektulos', 'neriakb'} },
    { short = 'neriakb',      name = 'Neriak - Commons',               era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'neriaka', 'neriakc'} },
    { short = 'neriakc',      name = 'Neriak - Third Gate',            era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'neriakb'} },
    { short = 'rivervale',    name = 'Rivervale',                      era = 'Classic',          continent = 'Antonica',             level = '1-10',  type = 'City',    connections = {'kithicor', 'misty'} },
    { short = 'misty',        name = 'Misty Thicket',                  era = 'Classic',          continent = 'Antonica',             level = '1-15',  type = 'Outdoor', connections = {'rivervale', 'runnyeye'} },
    -- CLASSIC: FAYDWER & ODUS
    { short = 'gfaydark',     name = 'Greater Faydark',                era = 'Classic',          continent = 'Faydwer',              level = '1-15',  type = 'Outdoor', connections = {'felwithea', 'crushbone', 'kelethin', 'lfaydark', 'butcher'} },
    { short = 'felwithea',    name = 'Northern Felwithe',              era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'gfaydark', 'felwitheb'} },
    { short = 'felwitheb',    name = 'Southern Felwithe',              era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'felwithea'} },
    { short = 'kelethin',     name = 'Kelethin',                       era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'gfaydark'} },
    { short = 'crushbone',    name = 'Crushbone',                      era = 'Classic',          continent = 'Faydwer',              level = '5-20',  type = 'Dungeon', connections = {'gfaydark'} },
    { short = 'lfaydark',     name = 'Lesser Faydark',                 era = 'Classic',          continent = 'Faydwer',              level = '10-30', type = 'Outdoor', connections = {'gfaydark', 'steamfont', 'mistmoore'} },
    { short = 'mistmoore',    name = 'Castle Mistmoore',               era = 'Classic',          continent = 'Faydwer',              level = '20-45', type = 'Dungeon', connections = {'lfaydark'} },
    { short = 'steamfont',    name = 'Steamfont Mountains',            era = 'Classic',          continent = 'Faydwer',              level = '1-20',  type = 'Outdoor', connections = {'lfaydark', 'akanon'} },
    { short = 'akanon',       name = 'Ak\'Anon',                       era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'steamfont'} },
    { short = 'butcher',      name = 'Butcherblock Mountains',         era = 'Classic',          continent = 'Faydwer',              level = '1-20',  type = 'Outdoor', connections = {'gfaydark', 'kaladima', 'dagnor', 'oceanoftears'} },
    { short = 'kaladima',     name = 'South Kaladim',                  era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'butcher', 'kaladimb'} },
    { short = 'kaladimb',     name = 'North Kaladim',                  era = 'Classic',          continent = 'Faydwer',              level = '1-10',  type = 'City',    connections = {'kaladima'} },
    { short = 'dagnor',       name = 'Dagnor\'s Cauldron',             era = 'Classic',          continent = 'Faydwer',              level = '15-35', type = 'Outdoor', connections = {'butcher', 'unrest', 'kedge'} },
    { short = 'unrest',       name = 'Estate of Unrest',               era = 'Classic',          continent = 'Faydwer',              level = '15-35', type = 'Dungeon', connections = {'dagnor'} },
    { short = 'kedge',        name = 'Kedge Keep',                     era = 'Classic',          continent = 'Faydwer',              level = '30-50', type = 'Dungeon', connections = {'dagnor'} },
    { short = 'oceanoftears', name = 'Ocean of Tears',                 era = 'Classic',          continent = 'Antonica',             level = '10-40', type = 'Outdoor', connections = {'freporte', 'butcher'} },
    { short = 'erudin',       name = 'Erudin',                         era = 'Classic',          continent = 'Odus',                 level = '1-10',  type = 'City',    connections = {'tox', 'erudnext'} },
    { short = 'erudnext',     name = 'Erudin Palace',                  era = 'Classic',          continent = 'Odus',                 level = '1-10',  type = 'City',    connections = {'erudin'} },
    { short = 'tox',          name = 'Toxxulia Forest',                era = 'Classic',          continent = 'Odus',                 level = '1-15',  type = 'Outdoor', connections = {'erudin', 'kerra', 'hole'} },
    { short = 'kerra',        name = 'Kerra Isle',                     era = 'Classic',          continent = 'Odus',                 level = '10-25', type = 'Outdoor', connections = {'tox'} },
    { short = 'hole',         name = 'The Hole',                       era = 'Classic',          continent = 'Odus',                 level = '40-60', type = 'Dungeon', connections = {'tox', 'erudsxing'} },
    { short = 'erudsxing',    name = 'Erud\'s Crossing',               era = 'Classic',          continent = 'Odus',                 level = '5-20',  type = 'Outdoor', connections = {'erudin', 'qeynos'} },
    -- CLASSIC PLANES
    { short = 'hateplane',    name = 'The Plane of Hate',              era = 'Classic',          continent = 'Planes',               level = '50-60', type = 'Raid',    connections = {'poknowledge', 'potranquility'} },
    { short = 'fearplane',    name = 'The Plane of Fear',              era = 'Classic',          continent = 'Planes',               level = '50-60', type = 'Raid',    connections = {'feerrott', 'potranquility'} },
    { short = 'sky',          name = 'The Plane of Sky (Air)',         era = 'Classic',          continent = 'Planes',               level = '50-60', type = 'Raid',    connections = {'freporte', 'potranquility'} },
    -- KUNARK
    { short = 'dreadlands',   name = 'Dreadlands',                     era = 'Kunark',           continent = 'Kunark',               level = '35-50', type = 'Outdoor', connections = {'firiona', 'burningwood', 'karnor', 'frontiermtns', 'lakeofillomen'} },
    { short = 'karnor',       name = 'Karnor\'s Castle',               era = 'Kunark',           continent = 'Kunark',               level = '45-55', type = 'Dungeon', connections = {'dreadlands'} },
    { short = 'firiona',      name = 'Firiona Vie',                    era = 'Kunark',           continent = 'Kunark',               level = '1-35',  type = 'City',    connections = {'dreadlands', 'lakeofillomen', 'swampofnohope', 'timorous'} },
    { short = 'lakeofillomen',name = 'Lake of Ill Omen',               era = 'Kunark',           continent = 'Kunark',               level = '1-30',  type = 'Outdoor', connections = {'cabilisw', 'firiona', 'dreadlands', 'overthere', 'droga', 'veksar'} },
    { short = 'cabilisw',     name = 'West Cabilis',                   era = 'Kunark',           continent = 'Kunark',               level = '1-10',  type = 'City',    connections = {'lakeofillomen', 'cabilise', 'warslikswood'} },
    { short = 'cabilise',     name = 'East Cabilis',                   era = 'Kunark',           continent = 'Kunark',               level = '1-10',  type = 'City',    connections = {'lakeofillomen', 'cabilisw', 'swampofnohope', 'fieldofbone'} },
    { short = 'fieldofbone',  name = 'The Field of Bone',              era = 'Kunark',           continent = 'Kunark',               level = '1-15',  type = 'Outdoor', connections = {'cabilise', 'kurn', 'kaesora', 'emeraldjungle', 'swampofnohope'} },
    { short = 'kurn',         name = 'Kurn\'s Tower',                  era = 'Kunark',           continent = 'Kunark',               level = '10-25', type = 'Dungeon', connections = {'fieldofbone'} },
    { short = 'kaesora',      name = 'Kaesora',                        era = 'Kunark',           continent = 'Kunark',               level = '30-45', type = 'Dungeon', connections = {'fieldofbone'} },
    { short = 'swampofnohope',name = 'Swamp of No Hope',               era = 'Kunark',           continent = 'Kunark',               level = '1-30',  type = 'Outdoor', connections = {'cabilise', 'fieldofbone', 'firiona', 'trakanon'} },
    { short = 'trakanon',     name = 'Trakanon\'s Teeth',              era = 'Kunark',           continent = 'Kunark',               level = '40-55', type = 'Outdoor', connections = {'swampofnohope', 'emeraldjungle', 'sebilis'} },
    { short = 'sebilis',      name = 'The Ruins of Sebilis',           era = 'Kunark',           continent = 'Kunark',               level = '45-60', type = 'Dungeon', connections = {'trakanon'} },
    { short = 'emeraldjungle',name = 'The Emerald Jungle',             era = 'Kunark',           continent = 'Kunark',               level = '35-50', type = 'Outdoor', connections = {'fieldofbone', 'trakanon', 'citymist'} },
    { short = 'citymist',     name = 'City of Mist',                   era = 'Kunark',           continent = 'Kunark',               level = '40-55', type = 'Dungeon', connections = {'emeraldjungle'} },
    { short = 'skyfire',      name = 'Skyfire Mountains',              era = 'Kunark',           continent = 'Kunark',               level = '40-55', type = 'Outdoor', connections = {'burningwood', 'overthere', 'veeshan'} },
    { short = 'veeshan',      name = 'Veeshan\'s Peak',                era = 'Kunark',           continent = 'Kunark',               level = '55-60', type = 'Raid',    connections = {'skyfire'} },
    { short = 'burningwood',  name = 'The Burning Wood',               era = 'Kunark',           continent = 'Kunark',               level = '35-50', type = 'Outdoor', connections = {'dreadlands', 'skyfire', 'frontiermtns', 'chardok'} },
    { short = 'chardok',      name = 'Chardok',                        era = 'Kunark',           continent = 'Kunark',               level = '45-60', type = 'Dungeon', connections = {'burningwood'} },
    { short = 'frontiermtns', name = 'Frontier Mountains',             era = 'Kunark',           continent = 'Kunark',               level = '25-40', type = 'Outdoor', connections = {'dreadlands', 'burningwood', 'overthere', 'droga'} },
    { short = 'overthere',    name = 'The Overthere',                  era = 'Kunark',           continent = 'Kunark',               level = '15-40', type = 'Outdoor', connections = {'frontiermtns', 'skyfire', 'warslikswood', 'timorous', 'charasis'} },
    { short = 'charasis',     name = 'Howling Stones (Charasis)',      era = 'Kunark',           continent = 'Kunark',               level = '45-60', type = 'Dungeon', connections = {'overthere'} },
    { short = 'warslikswood', name = 'Warsliks Wood',                  era = 'Kunark',           continent = 'Kunark',               level = '1-30',  type = 'Outdoor', connections = {'cabilisw', 'overthere', 'dalnir'} },
    { short = 'dalnir',       name = 'Crypt of Dalnir',                era = 'Kunark',           continent = 'Kunark',               level = '25-40', type = 'Dungeon', connections = {'warslikswood'} },
    { short = 'droga',        name = 'Temple of Droga',                era = 'Kunark',           continent = 'Kunark',               level = '35-50', type = 'Dungeon', connections = {'frontiermtns', 'nurga'} },
    { short = 'nurga',        name = 'Mines of Nurga',                 era = 'Kunark',           continent = 'Kunark',               level = '35-50', type = 'Dungeon', connections = {'droga'} },
    { short = 'timorous',     name = 'Timorous Deep',                  era = 'Kunark',           continent = 'Kunark',               level = '1-45',  type = 'Outdoor', connections = {'firiona', 'overthere', 'oasis', 'butcher'} },
    { short = 'veksar',       name = 'Veksar',                         era = 'Kunark',           continent = 'Kunark',               level = '45-60', type = 'Dungeon', connections = {'lakeofillomen'} },
    -- VELIOUS
    { short = 'iceclad',      name = 'Iceclad Ocean',                  era = 'Velious',          continent = 'Velious',              level = '30-45', type = 'Outdoor', connections = {'eastwastes'} },
    { short = 'eastwastes',   name = 'Eastern Wastes',                 era = 'Velious',          continent = 'Velious',              level = '35-50', type = 'Outdoor', connections = {'iceclad', 'greatdivide', 'crystal', 'sleeper', 'kael'} },
    { short = 'greatdivide',  name = 'Great Divide',                   era = 'Velious',          continent = 'Velious',              level = '35-50', type = 'Outdoor', connections = {'eastwastes', 'thurgadina', 'velketor', 'sirens'} },
    { short = 'thurgadina',   name = 'Thurgadin',                      era = 'Velious',          continent = 'Velious',              level = '1-60',  type = 'City',    connections = {'greatdivide', 'thurgadinb'} },
    { short = 'thurgadinb',   name = 'Icewell Keep',                   era = 'Velious',          continent = 'Velious',              level = '50-60', type = 'Dungeon', connections = {'thurgadina'} },
    { short = 'kael',         name = 'Kael Drakkel',                   era = 'Velious',          continent = 'Velious',              level = '45-60', type = 'Dungeon', connections = {'eastwastes', 'wakening'} },
    { short = 'wakening',     name = 'The Wakening Land',              era = 'Velious',          continent = 'Velious',              level = '40-55', type = 'Outdoor', connections = {'kael', 'skyshrine', 'growthplane'} },
    { short = 'skyshrine',    name = 'Skyshrine',                      era = 'Velious',          continent = 'Velious',              level = '45-60', type = 'Dungeon', connections = {'wakening', 'cobaltscar'} },
    { short = 'cobaltscar',   name = 'Cobalt Scar',                    era = 'Velious',          continent = 'Velious',              level = '40-55', type = 'Outdoor', connections = {'skyshrine', 'sirens', 'mischiefplane'} },
    { short = 'sirens',       name = 'Siren\'s Grotto',                era = 'Velious',          continent = 'Velious',              level = '50-60', type = 'Dungeon', connections = {'cobaltscar', 'westernwastes'} },
    { short = 'westernwastes',name = 'Western Wastes',                 era = 'Velious',          continent = 'Velious',              level = '45-60', type = 'Outdoor', connections = {'sirens', 'necropolis', 'templeveeshan'} },
    { short = 'necropolis',   name = 'Dragon Necropolis',              era = 'Velious',          continent = 'Velious',              level = '50-60', type = 'Dungeon', connections = {'westernwastes'} },
    { short = 'templeveeshan',name = 'Temple of Veeshan',              era = 'Velious',          continent = 'Velious',              level = '55-60', type = 'Raid',    connections = {'westernwastes'} },
    { short = 'velketor',     name = 'Velketor\'s Labyrinth',          era = 'Velious',          continent = 'Velious',              level = '45-60', type = 'Dungeon', connections = {'greatdivide'} },
    { short = 'crystal',      name = 'Crystal Caverns',                era = 'Velious',          continent = 'Velious',              level = '30-45', type = 'Dungeon', connections = {'eastwastes'} },
    { short = 'sleeper',      name = 'Sleeper\'s Tomb',                era = 'Velious',          continent = 'Velious',              level = '60',    type = 'Raid',    connections = {'eastwastes'} },
    { short = 'growthplane',  name = 'Plane of Growth',                era = 'Velious',          continent = 'Planes',               level = '55-60', type = 'Raid',    connections = {'wakening'} },
    { short = 'mischiefplane',name = 'Plane of Mischief',              era = 'Velious',          continent = 'Planes',               level = '50-60', type = 'Dungeon', connections = {'cobaltscar'} },
    -- LUCLIN
    { short = 'shadowhaven',  name = 'Shadow Haven',                   era = 'Luclin',           continent = 'Luclin',               level = '1-60',  type = 'City',    connections = {'nexus', 'bazaar', 'paludal', 'sharvahl', 'echo'} },
    { short = 'bazaar',       name = 'The Bazaar',                     era = 'Luclin',           continent = 'Luclin',               level = '1-65',  type = 'City',    connections = {'nexus', 'shadowhaven', 'poknowledge'} },
    { short = 'nexus',        name = 'The Nexus',                      era = 'Luclin',           continent = 'Luclin',               level = '1-65',  type = 'City',    connections = {'bazaar', 'shadowhaven', 'netherbian'} },
    { short = 'netherbian',   name = 'Netherbian Lair',                era = 'Luclin',           continent = 'Luclin',               level = '10-25', type = 'Dungeon', connections = {'nexus', 'dawnshroud', 'marus'} },
    { short = 'paludal',      name = 'Paludal Caverns',                era = 'Luclin',           continent = 'Luclin',               level = '5-25',  type = 'Dungeon', connections = {'shadowhaven', 'shadeweaver', 'hollowshade'} },
    { short = 'sharvahl',     name = 'Shar Vahl',                      era = 'Luclin',           continent = 'Luclin',               level = '1-15',  type = 'City',    connections = {'shadeweaver'} },
    { short = 'shadeweaver',  name = 'Shadeweaver\'s Thicket',         era = 'Luclin',           continent = 'Luclin',               level = '1-20',  type = 'Outdoor', connections = {'sharvahl', 'paludal'} },
    { short = 'hollowshade',  name = 'Hollowshade Moor',               era = 'Luclin',           continent = 'Luclin',               level = '15-35', type = 'Outdoor', connections = {'paludal', 'grimling'} },
    { short = 'grimling',     name = 'Grimling Forest',                era = 'Luclin',           continent = 'Luclin',               level = '25-45', type = 'Outdoor', connections = {'hollowshade', 'tenebrous', 'acrylia'} },
    { short = 'tenebrous',    name = 'Tenebrous Mountains',            era = 'Luclin',           continent = 'Luclin',               level = '35-50', type = 'Outdoor', connections = {'grimling', 'katta'} },
    { short = 'katta',        name = 'Katta Castellum',                era = 'Luclin',           continent = 'Luclin',               level = '40-60', type = 'City',    connections = {'tenebrous', 'twilight'} },
    { short = 'twilight',     name = 'The Twilight Sea',               era = 'Luclin',           continent = 'Luclin',               level = '25-45', type = 'Outdoor', connections = {'katta', 'fungusgrove', 'thedeep'} },
    { short = 'fungusgrove',  name = 'Fungus Grove',                   era = 'Luclin',           continent = 'Luclin',               level = '35-55', type = 'Dungeon', connections = {'twilight', 'echo'} },
    { short = 'echo',         name = 'Echo Caverns',                   era = 'Luclin',           continent = 'Luclin',               level = '20-40', type = 'Dungeon', connections = {'fungusgrove', 'shadowhaven'} },
    { short = 'dawnshroud',   name = 'Dawnshroud Peaks',               era = 'Luclin',           continent = 'Luclin',               level = '25-45', type = 'Outdoor', connections = {'netherbian', 'griegsend', 'themaiden'} },
    { short = 'griegsend',    name = 'Grieg\'s End',                   era = 'Luclin',           continent = 'Luclin',               level = '45-60', type = 'Dungeon', connections = {'dawnshroud'} },
    { short = 'sseru',        name = 'Sanctus Seru',                   era = 'Luclin',           continent = 'Luclin',               level = '35-60', type = 'City',    connections = {'marus'} },
    { short = 'marus',        name = 'Marus Seru',                     era = 'Luclin',           continent = 'Luclin',               level = '20-35', type = 'Outdoor', connections = {'netherbian', 'sseru', 'monsletalis'} },
    { short = 'monsletalis',  name = 'Mons Letalis',                   era = 'Luclin',           continent = 'Luclin',               level = '35-50', type = 'Outdoor', connections = {'marus', 'thegrey'} },
    { short = 'thegrey',      name = 'The Grey',                       era = 'Luclin',           continent = 'Luclin',               level = '40-55', type = 'Outdoor', connections = {'monsletalis', 'ssratemple'} },
    { short = 'ssratemple',   name = 'Ssraeshirhian Temple',           era = 'Luclin',           continent = 'Luclin',               level = '50-60', type = 'Dungeon', connections = {'thegrey'} },
    { short = 'thedeep',      name = 'The Deep',                       era = 'Luclin',           continent = 'Luclin',               level = '45-60', type = 'Dungeon', connections = {'twilight', 'ssratemple'} },
    { short = 'acrylia',      name = 'Acrylia Caverns',                era = 'Luclin',           continent = 'Luclin',               level = '40-55', type = 'Dungeon', connections = {'grimling'} },
    { short = 'themaiden',    name = 'The Maiden\'s Eye',              era = 'Luclin',           continent = 'Luclin',               level = '45-60', type = 'Outdoor', connections = {'dawnshroud', 'akheva', 'umbral'} },
    { short = 'akheva',       name = 'Akheva Ruins',                   era = 'Luclin',           continent = 'Luclin',               level = '50-60', type = 'Dungeon', connections = {'themaiden'} },
    { short = 'umbral',       name = 'Umbral Plains',                  era = 'Luclin',           continent = 'Luclin',               level = '50-60', type = 'Outdoor', connections = {'themaiden', 'vexthal'} },
    { short = 'vexthal',      name = 'Vex Thal',                       era = 'Luclin',           continent = 'Luclin',               level = '60',    type = 'Raid',    connections = {'umbral'} },
    -- PLANES OF POWER
    { short = 'poknowledge',  name = 'Plane of Knowledge',             era = 'Planes of Power',  continent = 'Planes',               level = '1-125', type = 'City',    connections = {'potranquility', 'bazaar', 'guildlobby', 'freportw', 'qeynos2', 'halas', 'rivervale', 'erudnext', 'gfaydark', 'felwithea', 'akanon', 'kaladima', 'neriakb', 'grobb', 'oggok', 'cabilisw', 'firiona', 'overthere', 'thurgadina', 'greatdivide', 'sharvahl', 'shadeweaver', 'nexus', 'dranik', 'natimbi', 'crescent', 'tox', 'nedaria'} },
    { short = 'potranquility',name = 'Plane of Tranquility',           era = 'Planes of Power',  continent = 'Planes',               level = '45-65', type = 'City',    connections = {'poknowledge', 'pojustice', 'ponightmare', 'podisease', 'poinnovation', 'postorms', 'povalor', 'potorment', 'potactics', 'solrotower', 'pofire', 'powater', 'poearthA', 'poair', 'potimeA', 'hateplane', 'fearplane', 'sky'} },
    { short = 'pojustice',    name = 'Plane of Justice',               era = 'Planes of Power',  continent = 'Planes',               level = '45-60', type = 'Dungeon', connections = {'potranquility'} },
    { short = 'ponightmare',  name = 'Plane of Nightmare',             era = 'Planes of Power',  continent = 'Planes',               level = '45-60', type = 'Outdoor', connections = {'potranquility', 'nightmareb'} },
    { short = 'nightmareb',   name = 'Lair of Terris Thule',           era = 'Planes of Power',  continent = 'Planes',               level = '55-65', type = 'Raid',    connections = {'ponightmare'} },
    { short = 'podisease',    name = 'Plane of Disease',               era = 'Planes of Power',  continent = 'Planes',               level = '45-60', type = 'Outdoor', connections = {'potranquility', 'codecay'} },
    { short = 'codecay',      name = 'Crypt of Decay',                 era = 'Planes of Power',  continent = 'Planes',               level = '55-65', type = 'Dungeon', connections = {'podisease'} },
    { short = 'poinnovation', name = 'Plane of Innovation',            era = 'Planes of Power',  continent = 'Planes',               level = '45-60', type = 'Dungeon', connections = {'potranquility'} },
    { short = 'postorms',     name = 'Plane of Storms',                era = 'Planes of Power',  continent = 'Planes',               level = '55-65', type = 'Outdoor', connections = {'potranquility', 'bastion'} },
    { short = 'bastion',      name = 'Bastion of Thunder',             era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Dungeon', connections = {'postorms'} },
    { short = 'povalor',      name = 'Plane of Valor',                 era = 'Planes of Power',  continent = 'Planes',               level = '55-65', type = 'Outdoor', connections = {'potranquility', 'hohonora'} },
    { short = 'hohonora',     name = 'Halls of Honor',                 era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Dungeon', connections = {'povalor', 'hohonorb'} },
    { short = 'hohonorb',     name = 'Temple of Marr',                 era = 'Planes of Power',  continent = 'Planes',               level = '62-65', type = 'Raid',    connections = {'hohonora'} },
    { short = 'potorment',    name = 'Plane of Torment',               era = 'Planes of Power',  continent = 'Planes',               level = '55-65', type = 'Dungeon', connections = {'potranquility'} },
    { short = 'potactics',    name = 'Drunder, Fortress of Zek',       era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Dungeon', connections = {'potranquility'} },
    { short = 'solrotower',   name = 'Tower of Solusek Ro',            era = 'Planes of Power',  continent = 'Planes',               level = '62-65', type = 'Dungeon', connections = {'potranquility'} },
    { short = 'pofire',       name = 'Doomfire, the Burning Lands',    era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Outdoor', connections = {'potranquility'} },
    { short = 'powater',      name = 'Reef of Trials (Water)',         era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Outdoor', connections = {'potranquility'} },
    { short = 'poearthA',     name = 'Vegarlson, Earthen Badlands',    era = 'Planes of Power',  continent = 'Planes',               level = '60-65', type = 'Outdoor', connections = {'potranquility', 'poearthB'} },
    { short = 'poearthB',     name = 'Stronghold of Heights',          era = 'Planes of Power',  continent = 'Planes',               level = '62-65', type = 'Raid',    connections = {'poearthA'} },
    { short = 'poair',        name = 'Eryslai, Kingdom of Wind',       era = 'Planes of Power',  continent = 'Planes',               level = '62-65', type = 'Outdoor', connections = {'potranquility'} },
    { short = 'potimeA',      name = 'Plane of Time (A)',              era = 'Planes of Power',  continent = 'Planes',               level = '65',    type = 'Raid',    connections = {'potranquility', 'potimeB'} },
    { short = 'potimeB',      name = 'Plane of Time (B)',              era = 'Planes of Power',  continent = 'Planes',               level = '65',    type = 'Raid',    connections = {'potimeA'} },
    -- LEGACY OF YKESHA & LDON
    { short = 'gunthak',      name = 'Gulf of Gunthak',                era = 'Legacy of Ykesha', continent = 'Broken Skull Rock',     level = '35-50', type = 'Outdoor', connections = {'dulak', 'torgiran', 'hatefury', 'nadox'} },
    { short = 'dulak',        name = 'Dulak\'s Harbor',                era = 'Legacy of Ykesha', continent = 'Broken Skull Rock',     level = '40-55', type = 'Outdoor', connections = {'gunthak'} },
    { short = 'torgiran',     name = 'Torgiran Mines',                 era = 'Legacy of Ykesha', continent = 'Broken Skull Rock',     level = '45-60', type = 'Dungeon', connections = {'gunthak', 'nadox'} },
    { short = 'nadox',        name = 'Crypt of Nadox',                 era = 'Legacy of Ykesha', continent = 'Broken Skull Rock',     level = '50-65', type = 'Dungeon', connections = {'gunthak', 'torgiran', 'hatefury'} },
    { short = 'hatefury',     name = 'Hate\'s Fury',                   era = 'Legacy of Ykesha', continent = 'Broken Skull Rock',     level = '55-65', type = 'Dungeon', connections = {'gunthak', 'nadox'} },
    { short = 'nedaria',      name = 'Nedaria\'s Landing',             era = 'Legacy of Ykesha', continent = 'Antonica',             level = '20-40', type = 'Outdoor', connections = {'jaggedpine', 'nro', 'butcher', 'natimbi'} },
    { short = 'jaggedpine',   name = 'Jaggedpine Forest',              era = 'Legacy of Ykesha', continent = 'Antonica',             level = '20-45', type = 'Outdoor', connections = {'nedaria', 'qeytoqrg', 'blackburrow'} },
    -- GATES OF DISCORD
    { short = 'natimbi',      name = 'Natimbi, The Broken Shores',     era = 'Gates of Discord', continent = 'Taelosia',             level = '50-65', type = 'Outdoor', connections = {'nedaria', 'barindu', 'qinimi', 'ferubi'} },
    { short = 'barindu',      name = 'Barindu, Hanging Gardens',       era = 'Gates of Discord', continent = 'Taelosia',             level = '55-65', type = 'Outdoor', connections = {'natimbi', 'riwwi', 'ferubi'} },
    { short = 'riwwi',        name = 'Riwwi, Coliseum of Games',       era = 'Gates of Discord', continent = 'Taelosia',             level = '55-65', type = 'Outdoor', connections = {'barindu'} },
    { short = 'qinimi',       name = 'Qinimi, Court of Nihilia',       era = 'Gates of Discord', continent = 'Taelosia',             level = '55-65', type = 'Outdoor', connections = {'natimbi', 'kodtaz'} },
    { short = 'ferubi',       name = 'Ferubi, Sanctuary of Tshill',    era = 'Gates of Discord', continent = 'Taelosia',             level = '55-65', type = 'Dungeon', connections = {'natimbi', 'barindu'} },
    { short = 'kodtaz',       name = 'Kod\'Taz, Broken Trial Grounds', era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Outdoor', connections = {'qinimi', 'yxtta', 'ikkinz'} },
    { short = 'yxtta',        name = 'Yxtta, Pulpit of Yxunxtei',      era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Dungeon', connections = {'kodtaz', 'uqua', 'qvic'} },
    { short = 'uqua',         name = 'Uqua, Ocean God Chantry',        era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Raid',    connections = {'yxtta', 'qvic'} },
    { short = 'qvic',         name = 'Qvic, Grounds of Calling',       era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Outdoor', connections = {'yxtta', 'uqua', 'inktuta', 'txevu'} },
    { short = 'inktuta',      name = 'Inktuta, Refracted Reach',       era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Raid',    connections = {'qvic'} },
    { short = 'txevu',        name = 'Txevu, Lair of the Elite',       era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Dungeon', connections = {'qvic', 'tacvi'} },
    { short = 'tacvi',        name = 'Tacvi, Broken Amphitheater',     era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Raid',    connections = {'txevu'} },
    { short = 'ikkinz',       name = 'Ikkinz, Chambers of Destruction',era = 'Gates of Discord', continent = 'Taelosia',             level = '65',    type = 'Raid',    connections = {'kodtaz'} },
    -- OMENS OF WAR
    { short = 'dranik',       name = 'Dranik\'s Scar',                 era = 'Omens of War',     continent = 'Kuua',                 level = '55-65', type = 'Outdoor', connections = {'poknowledge', 'bloodfields', 'nobles', 'wallofslaughter'} },
    { short = 'bloodfields',  name = 'The Bloodfields',                era = 'Omens of War',     continent = 'Kuua',                 level = '60-70', type = 'Outdoor', connections = {'dranik'} },
    { short = 'nobles',       name = 'Nobles\' Causeway',              era = 'Omens of War',     continent = 'Kuua',                 level = '60-70', type = 'Outdoor', connections = {'dranik', 'wallofslaughter', 'harbingers'} },
    { short = 'wallofslaughter', name = 'Wall of Slaughter',           era = 'Omens of War',     continent = 'Kuua',                 level = '65-70', type = 'Outdoor', connections = {'nobles', 'dranik', 'riftseekers', 'anguish'} },
    { short = 'riftseekers',  name = 'Riftseekers\' Sanctum',          era = 'Omens of War',     continent = 'Kuua',                 level = '68-70', type = 'Dungeon', connections = {'wallofslaughter'} },
    { short = 'harbingers',   name = 'Harbingers\' Spire',             era = 'Omens of War',     continent = 'Kuua',                 level = '65-70', type = 'Dungeon', connections = {'nobles'} },
    { short = 'anguish',      name = 'Anguish, the Fallen Palace',     era = 'Omens of War',     continent = 'Kuua',                 level = '70',    type = 'Raid',    connections = {'wallofslaughter'} },
    -- THE SERPENT'S SPINE & HUBS
    { short = 'crescent',     name = 'Crescent Reach',                 era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '1-20', type = 'City',    connections = {'moors', 'poknowledge'} },
    { short = 'moors',        name = 'Blightfire Moors',               era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '15-35', type = 'Outdoor', connections = {'crescent', 'stonehive', 'gorukar'} },
    { short = 'stonehive',    name = 'Stone Hive',                     era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '20-40', type = 'Dungeon', connections = {'moors'} },
    { short = 'gorukar',      name = 'Goru`kar Mesa',                  era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '30-50', type = 'Outdoor', connections = {'moors', 'blackfeather', 'steppes'} },
    { short = 'blackfeather', name = 'Blackfeather Roost',             era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '45-60', type = 'Dungeon', connections = {'gorukar'} },
    { short = 'steppes',      name = 'The Steppes',                    era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '45-65', type = 'Outdoor', connections = {'gorukar', 'icefall', 'sunderock'} },
    { short = 'icefall',      name = 'Icefall Glacier',                era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '55-70', type = 'Outdoor', connections = {'steppes', 'valdeholm'} },
    { short = 'valdeholm',    name = 'Valdeholm',                      era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '65-75', type = 'Dungeon', connections = {'icefall', 'frostcrypt'} },
    { short = 'frostcrypt',   name = 'Frostcrypt, Shade King',         era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '70-75', type = 'Raid',    connections = {'valdeholm'} },
    { short = 'sunderock',    name = 'Sunderock Springs',              era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '55-70', type = 'Outdoor', connections = {'steppes', 'vergalid', 'direwind'} },
    { short = 'vergalid',     name = 'Vergalid Mines',                 era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '65-75', type = 'Dungeon', connections = {'sunderock'} },
    { short = 'direwind',     name = 'Direwind Cliffs',                era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '65-75', type = 'Outdoor', connections = {'sunderock', 'ashengate'} },
    { short = 'ashengate',    name = 'Ashengate, Reliquary of Scale',  era = 'The Serpent\'s Spine', continent = 'The Serpent\'s Spine', level = '70-75', type = 'Raid',    connections = {'direwind'} },
    { short = 'guildlobby',   name = 'Guild Lobby',                    era = 'Hubs & Special',   continent = 'Hubs',                 level = '1-125', type = 'City',    connections = {'poknowledge', 'guildhall'} },
    { short = 'guildhall',    name = 'Guild Hall',                     era = 'Hubs & Special',   continent = 'Hubs',                 level = '1-125', type = 'City',    connections = {'guildlobby'} },
}

local function initAtlasRegistry()
    state.atlasAllZones = {}
    for _, z in ipairs(NORRATH_ZONE_REGISTRY) do
        local entry = {
            short       = z.short,
            name        = z.name,
            era         = z.era,
            continent   = z.continent,
            level       = z.level or '1-65',
            type        = z.type or 'Outdoor',
            connections = z.connections or {},
            hasMap      = false,
            lineCount   = 0,
            labelCount  = 0,
            isCustom    = false,
        }
        state.atlasAllZones[#state.atlasAllZones + 1] = entry
    end
end

-- ============================================================================
-- MAP DIRECTORY DISCOVERY & FILE PARSER
-- ============================================================================
local function isDirectoryAccessible(dir)
    if not dir or dir == '' then return false end
    local okLfs, lfs = pcall(require, 'lfs')
    if okLfs and lfs and lfs.attributes then
        local mode = lfs.attributes(dir, 'mode')
        return mode == 'directory'
    end
    -- Probe common zone map files
    local probeNames = {
        state.currentZoneShort or 'poknowledge',
        'poknowledge', 'qeynos', 'freporte', 'bazaar', 'nexus',
        'planeofknowledge', 'arena', 'guildlobby', 'crescent',
        'poearthA', 'potranquility', 'shadowhaven', 'sharvahl', 'gfaydark'
    }
    for _, z in ipairs(probeNames) do
        local f1 = io.open(dir .. '/' .. z .. '.txt', 'r')
        if f1 then f1:close(); return true end
        local f2 = io.open(dir .. '/' .. z .. '_labels.txt', 'r')
        if f2 then f2:close(); return true end
    end
    local f = io.open(dir, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

local function getBaseMapsDirectory()
    if state.customMapsDir and state.customMapsDir ~= '' then
        if isDirectoryAccessible(state.customMapsDir) then
            return state.customMapsDir
        end
    end

    local candidates = {
        'maps',
        '../maps',
        '../../maps',
    }

    local okEq, eqPath = pcall(function() return mq.TLO.EverQuest.Path() end)
    if okEq and eqPath and eqPath ~= '' then
        candidates[#candidates + 1] = eqPath .. '/maps'
        candidates[#candidates + 1] = eqPath .. '/Maps'
    end

    if mq.configDir then
        candidates[#candidates + 1] = mq.configDir .. '/../maps'
        candidates[#candidates + 1] = mq.configDir .. '/../../maps'
    end
    if mq.luaDir then
        candidates[#candidates + 1] = mq.luaDir .. '/../maps'
        candidates[#candidates + 1] = mq.luaDir .. '/../../maps'
    end

    for _, dir in ipairs(candidates) do
        if isDirectoryAccessible(dir) then
            return dir
        end
    end

    return nil
end

local function scanMapFolders()
    local baseDir = getBaseMapsDirectory()
    state.baseMapsDirectory = baseDir

    if not baseDir then
        state.mapFolders = { { name = '[Root] (Not Found)', relPath = '', fullPath = '' } }
        state.mapFolderNames = { 'No maps directory found' }
        state.selectedFolderIndex = 1
        state.activeMapsDirectory = nil
        return
    end

    local folders = {}
    local names = {}
    local seen = {}

    -- Option 1: Root maps directory
    folders[1] = { name = '[Root] Default (maps/)', relPath = '', fullPath = baseDir }
    names[1] = '[Root] Default (maps/)'
    seen[''] = true

    -- Method 1: LuaFileSystem (if available in environment)
    local okLfs, lfs = pcall(require, 'lfs')
    if okLfs and lfs and lfs.dir and lfs.attributes then
        pcall(function()
            for file in lfs.dir(baseDir) do
                if file ~= '.' and file ~= '..' and not seen[file] then
                    local full = baseDir .. '/' .. file
                    local mode = lfs.attributes(full, 'mode')
                    if mode == 'directory' then
                        seen[file] = true
                        folders[#folders + 1] = { name = file, relPath = file, fullPath = full }
                        names[#names + 1] = file
                    end
                end
            end
        end)
    end

    -- Method 2: Fast Windows Shell Directory Query (dir /a:d /b)
    if #folders == 1 and io.popen then
        pcall(function()
            local winPath = baseDir:gsub('/', '\\')
            local pipe = io.popen('cmd /c dir /a:d /b "' .. winPath .. '" 2>nul')
            if pipe then
                for line in pipe:lines() do
                    local trimmed = line:match('^%s*(.-)%s*$')
                    if trimmed and trimmed ~= '' and trimmed ~= '.' and trimmed ~= '..' and not seen[trimmed] then
                        seen[trimmed] = true
                        folders[#folders + 1] = { name = trimmed, relPath = trimmed, fullPath = baseDir .. '/' .. trimmed }
                        names[#names + 1] = trimmed
                    end
                end
                pipe:close()
            end
        end)
    end

    -- Method 3: POSIX / Linux / Wine fallback
    if #folders == 1 and io.popen then
        pcall(function()
            local pipe = io.popen('find "' .. baseDir .. '" -mindepth 1 -maxdepth 1 -type d -exec basename {} \\; 2>/dev/null')
            if pipe then
                for line in pipe:lines() do
                    local trimmed = line:match('^%s*(.-)%s*$')
                    if trimmed and trimmed ~= '' and trimmed ~= '.' and trimmed ~= '..' and not seen[trimmed] then
                        seen[trimmed] = true
                        folders[#folders + 1] = { name = trimmed, relPath = trimmed, fullPath = baseDir .. '/' .. trimmed }
                        names[#names + 1] = trimmed
                    end
                end
                pipe:close()
            end
        end)
    end

    -- Method 4: Comprehensive Community Map Pack Probe Dictionary (Only if directory discovery found nothing)
    if #folders == 1 then
        local knownPacks = {
            'Brewall', 'brewall', 'Brewalls', 'brewalls', 'BrewallMaps', 'brewallmaps', 'Brewall_RoF2', 'Brewall_Live',
            'Goodurden', 'goodurden', 'Goods', 'goods', 'GoodUrden', 'GoodsMaps', 'goodsmaps', 'Good_Maps', 'GoodurdenMaps',
            'MyMaps', 'mymaps', 'Custom', 'custom', 'CustomMaps', 'custommaps', 'UserMaps', 'usermaps', 'Maps', 'maps',
            'RoF2', 'rof2', 'Underfoot', 'underfoot', 'Titanium', 'titanium', 'P99', 'p99', 'Project1999', 'project1999',
            'EQClassic', 'eqclassic', 'Classic', 'classic', 'Live', 'live', 'Beta', 'beta',
            'Cartography', 'cartography', 'Atlas', 'atlas', 'MapPack', 'mappack', 'ZoneMaps', 'zonemaps', 'Downloaded', 'NewMaps',
            'TLP', 'tlp', 'EverQuest', 'everquest', 'Default', 'default'
        }
        for _, pack in ipairs(knownPacks) do
            if not seen[pack] then
                local subPath = baseDir .. '/' .. pack
                if isDirectoryAccessible(subPath) then
                    seen[pack] = true
                    folders[#folders + 1] = { name = pack, relPath = pack, fullPath = subPath }
                    names[#names + 1] = pack
                end
            end
        end
    end

    state.mapFolders = folders
    state.mapFolderNames = names

    if state.selectedFolderIndex > #folders or state.selectedFolderIndex < 1 then
        state.selectedFolderIndex = 1
    end

    state.activeMapsDirectory = folders[state.selectedFolderIndex] and folders[state.selectedFolderIndex].fullPath or baseDir
end

local function scanMapFiles()
    local baseDir = state.activeMapsDirectory or state.baseMapsDirectory or getBaseMapsDirectory()
    if not baseDir or baseDir == '' then return end

    if not state.atlasAllZones or #state.atlasAllZones == 0 then
        initAtlasRegistry()
    end

    local zoneLookup = {}
    for _, z in ipairs(state.atlasAllZones) do
        zoneLookup[z.short:lower()] = z
    end

    local discoveredShorts = {}

    -- Method 1: lfs
    local okLfs, lfs = pcall(require, 'lfs')
    if okLfs and lfs and lfs.dir then
        pcall(function()
            for file in lfs.dir(baseDir) do
                local zShort = file:match('^([%w_]+)%.txt$')
                if zShort and not zShort:match('_%d$') and not zShort:match('_labels$') then
                    discoveredShorts[zShort:lower()] = true
                end
            end
        end)
    end

    -- Method 2: Windows cmd dir /b *.txt
    if io.popen and not next(discoveredShorts) then
        pcall(function()
            local winPath = baseDir:gsub('/', '\\')
            local pipe = io.popen('cmd /c dir /b "' .. winPath .. '\\*.txt" 2>nul')
            if pipe then
                for line in pipe:lines() do
                    local zShort = line:match('^([%w_]+)%.txt$')
                    if zShort and not zShort:match('_%d$') and not zShort:match('_labels$') then
                        discoveredShorts[zShort:lower()] = true
                    end
                end
                pipe:close()
            end
        end)
    end

    -- Method 3: POSIX find
    if io.popen and not next(discoveredShorts) then
        pcall(function()
            local pipe = io.popen('find "' .. baseDir .. '" -maxdepth 1 -name "*.txt" -exec basename {} \\; 2>/dev/null')
            if pipe then
                for line in pipe:lines() do
                    local zShort = line:match('^([%w_]+)%.txt$')
                    if zShort and not zShort:match('_%d$') and not zShort:match('_labels$') then
                        discoveredShorts[zShort:lower()] = true
                    end
                end
                pipe:close()
            end
        end)
    end

    -- Probe check for registered zones ONLY if directory listing was empty
    if not next(discoveredShorts) then
        for _, z in ipairs(state.atlasAllZones) do
            local f = io.open(baseDir .. '/' .. z.short .. '.txt', 'r')
            if f then
                f:close()
                z.hasMap = true
                discoveredShorts[z.short:lower()] = true
            else
                z.hasMap = false
            end
        end
    else
        for _, z in ipairs(state.atlasAllZones) do
            z.hasMap = (discoveredShorts[z.short:lower()] == true)
        end
    end

    -- Add any custom on-disk zones not in the built-in registry
    for s, _ in pairs(discoveredShorts) do
        if not zoneLookup[s] then
            local cleanName = s:gsub('^%l', string.upper)
            local okZ, zName = pcall(function() return mq.TLO.Zone(s).Name() end)
            if okZ and zName and zName ~= '' then cleanName = zName end

            local entry = {
                short       = s,
                name        = cleanName,
                era         = 'Custom / Other',
                continent   = 'Custom / Other',
                level       = 'Unknown',
                type        = 'Outdoor',
                connections = {},
                hasMap      = true,
                isCustom    = true,
            }
            state.atlasAllZones[#state.atlasAllZones + 1] = entry
            zoneLookup[s] = entry
        end
    end
end

local function filterAtlasZones()
    local q = (state.atlasSearchText or ''):lower():match('^%s*(.-)%s*$')
    local eraFilter = ATLAS_ERA_OPTIONS[state.atlasEraFilterIdx] or 'All Expansions'
    local typeFilter = ATLAS_TYPE_OPTIONS[state.atlasTypeFilterIdx] or 'All Zone Types'

    local out = {}
    for _, z in ipairs(state.atlasAllZones) do
        local matchQuery = true
        if q ~= '' then
            local inName  = (z.name:lower():find(q, 1, true) ~= nil)
            local inShort = (z.short:lower():find(q, 1, true) ~= nil)
            local inEra   = (z.era:lower():find(q, 1, true) ~= nil)
            local inCont  = (z.continent:lower():find(q, 1, true) ~= nil)
            matchQuery    = (inName or inShort or inEra or inCont)
        end

        local matchEra = true
        if eraFilter ~= 'All Expansions' then
            matchEra = (z.era == eraFilter)
        end

        local matchType = true
        if typeFilter ~= 'All Zone Types' then
            if typeFilter == 'Cities & Hubs' then
                matchType = (z.type == 'City')
            elseif typeFilter == 'Outdoor & Wilderness' then
                matchType = (z.type == 'Outdoor')
            elseif typeFilter == 'Dungeons' then
                matchType = (z.type == 'Dungeon')
            elseif typeFilter == 'Planes' then
                matchType = (z.type == 'Planar' or z.type == 'Planes' or z.era == 'Planes of Power')
            elseif typeFilter == 'Raid Zones' then
                matchType = (z.type == 'Raid')
            end
        end

        if matchQuery and matchEra and matchType then
            out[#out + 1] = z
        end
    end

    table.sort(out, function(a, b)
        if a.hasMap ~= b.hasMap then
            return a.hasMap == true
        end
        return a.name < b.name
    end)

    state.atlasZoneList = out
    if not state.atlasSelectedZone and #out > 0 then
        state.atlasSelectedZone = out[1]
    end
end

-- Zone Map In-Memory Cache (Instant switching between visited zones)
local zoneMapCache = {}

local function clearZoneMapCache()
    zoneMapCache = {}
end

local function parseMapFile(filePath, layerId)
    local f = io.open(filePath, 'r')
    if not f then return 0, 0 end
    local content = f:read('*a')
    f:close()
    if not content or content == '' then return 0, 0 end

    local linesAdded = 0
    local labelsAdded = 0
    local targetLines = mapData.layers[layerId] or {}
    local targetLabels = mapData.labels
    local bMinX, bMaxX = mapData.bounds.minX, mapData.bounds.maxX
    local bMinY, bMaxY = mapData.bounds.minY, mapData.bounds.maxY
    local bMinZ, bMaxZ = mapData.bounds.minZ, mapData.bounds.maxZ

    -- Fast line iterator using gmatch
    for line in content:gmatch('[^\r\n]+') do
        local b1 = line:byte(1)
        if b1 == 76 or b1 == 108 then
            -- Line format: L x1, y1, z1, x2, y2, z2, r, g, b
            local x1, y1, z1, x2, y2, z2, r, g, b = line:match('^[Ll]%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+)')
            if not x1 then
                x1, y1, z1, x2, y2, z2, r, g, b = line:match('^%a%s+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)')
            end
            if x1 and y1 and z1 and x2 and y2 and z2 then
                local nx1 = -tonumber(x1)
                local ny1 = -tonumber(y1)
                local nz1 = tonumber(z1)
                local nx2 = -tonumber(x2)
                local ny2 = -tonumber(y2)
                local nz2 = tonumber(z2)
                local nr = (tonumber(r) or 180) / 255.0
                local ng = (tonumber(g) or 180) / 255.0
                local nb = (tonumber(b) or 180) / 255.0

                -- High-contrast brightness correction:
                local lum = nr * 0.299 + ng * 0.587 + nb * 0.114
                if lum < 0.25 then
                    nr = 0.72
                    ng = 0.76
                    nb = 0.82
                end

                local segMinX = nx1 < nx2 and nx1 or nx2
                local segMaxX = nx1 > nx2 and nx1 or nx2
                local segMinY = ny1 < ny2 and ny1 or ny2
                local segMaxY = ny1 > ny2 and ny1 or ny2

                targetLines[#targetLines + 1] = {
                    x1 = nx1, y1 = ny1, z1 = nz1,
                    x2 = nx2, y2 = ny2, z2 = nz2,
                    r = nr, g = ng, b = nb,
                    avgZ = (nz1 + nz2) * 0.5,
                    minX = segMinX, maxX = segMaxX,
                    minY = segMinY, maxY = segMaxY,
                }
                linesAdded = linesAdded + 1

                if segMinX < bMinX then bMinX = segMinX end
                if segMaxX > bMaxX then bMaxX = segMaxX end
                if segMinY < bMinY then bMinY = segMinY end
                if segMaxY > bMaxY then bMaxY = segMaxY end

                local segMinZ = nz1 < nz2 and nz1 or nz2
                local segMaxZ = nz1 > nz2 and nz1 or nz2
                if segMinZ < bMinZ then bMinZ = segMinZ end
                if segMaxZ > bMaxZ then bMaxZ = segMaxZ end
            end
        elseif b1 == 80 or b1 == 112 then
            -- Label format: P x, y, z, r, g, b, size, label_text
            local x, y, z, r, g, b, size, text = line:match('^[Pp]%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+),?%s+(.+)')
            if not x then
                x, y, z, r, g, b, size, text = line:match('^%a%s+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(.+)')
            end
            if x and y and z and text then
                local nx = -tonumber(x)
                local ny = -tonumber(y)
                local nz = tonumber(z)
                local nr = (tonumber(r) or 255) / 255.0
                local ng = (tonumber(g) or 255) / 255.0
                local nb = (tonumber(b) or 255) / 255.0
                local cleanText = text:gsub('_', ' ')

                local lum = nr * 0.299 + ng * 0.587 + nb * 0.114
                if lum < 0.25 then
                    nr = 0.88
                    ng = 0.92
                    nb = 0.96
                end

                targetLabels[#targetLabels + 1] = {
                    x = nx, y = ny, z = nz,
                    r = nr, g = ng, b = nb,
                    size = tonumber(size) or 1,
                    text = cleanText,
                }
                labelsAdded = labelsAdded + 1
            end
        end
    end

    mapData.bounds.minX, mapData.bounds.maxX = bMinX, bMaxX
    mapData.bounds.minY, mapData.bounds.maxY = bMinY, bMaxY
    mapData.bounds.minZ, mapData.bounds.maxZ = bMinZ, bMaxZ
    mapData.layers[layerId] = targetLines
    return linesAdded, labelsAdded
end

local function loadZoneMap(zoneShort, isAtlas)
    if not zoneShort or zoneShort == '' then return false end

    if not state.mapFolders or #state.mapFolders == 0 or not state.activeMapsDirectory then
        scanMapFolders()
    end

    local baseDir = state.activeMapsDirectory or state.baseMapsDirectory or getBaseMapsDirectory()
    if not baseDir or baseDir == '' then
        state.statusMsg = 'EverQuest map directory not found.'
        mapData.isLoaded = false
        return false
    end

    local folderDisplay = (state.mapFolders[state.selectedFolderIndex] and state.mapFolders[state.selectedFolderIndex].name) or baseDir
    local cacheKey = string.format('%s:%s', baseDir, zoneShort:lower())
    local cached = zoneMapCache[cacheKey]

    if cached then
        mapData.zoneShort   = zoneShort
        mapData.layers      = cached.layers
        mapData.labels      = cached.labels
        mapData.totalLines  = cached.totalLines
        mapData.totalLabels = cached.totalLabels
        mapData.bounds      = cached.bounds
        mapData.isLoaded    = (cached.totalLines > 0 or cached.totalLabels > 0)
        local modeStr = isAtlas and 'Atlas' or 'Live'
        state.statusMsg = string.format('[%s] Loaded (Cached): %s (%d lines, %d labels)', modeStr, zoneShort, mapData.totalLines, mapData.totalLabels)

        if not isAtlas then
            local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
            local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
            if okMeX and okMeY and meX and meY then
                viewport.centerEqX = meX
                viewport.centerEqY = meY
            else
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            end
        else
            viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
            viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            local spanX = math.abs(mapData.bounds.maxX - mapData.bounds.minX)
            local spanY = math.abs(mapData.bounds.maxY - mapData.bounds.minY)
            local maxSpan = math.max(spanX, spanY)
            if maxSpan > 50 then
                viewport.zoom = math.max(viewport.minZoom, math.min(1.2, 700 / maxSpan))
            end
        end
        return true
    end

    mapData.zoneShort = zoneShort
    mapData.layers = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
    mapData.labels = {}
    mapData.totalLines = 0
    mapData.totalLabels = 0
    mapData.bounds = {
        minX = 999999, maxX = -999999,
        minY = 999999, maxY = -999999,
        minZ = 999999, maxZ = -999999,
    }

    local layerFiles = {
        [0] = string.format('%s/%s.txt', baseDir, zoneShort),
        [1] = string.format('%s/%s_1.txt', baseDir, zoneShort),
        [2] = string.format('%s/%s_2.txt', baseDir, zoneShort),
        [3] = string.format('%s/%s_3.txt', baseDir, zoneShort),
    }
    local labelsFile = string.format('%s/%s_labels.txt', baseDir, zoneShort)

    for lId = 0, 3 do
        local lCount, lbCount = parseMapFile(layerFiles[lId], lId)
        mapData.totalLines = mapData.totalLines + lCount
        mapData.totalLabels = mapData.totalLabels + lbCount
    end

    local _, lbCount2 = parseMapFile(labelsFile, 0)
    mapData.totalLabels = mapData.totalLabels + lbCount2

    if mapData.totalLines > 0 or mapData.totalLabels > 0 then
        mapData.isLoaded = true
        zoneMapCache[cacheKey] = {
            layers      = mapData.layers,
            labels      = mapData.labels,
            totalLines  = mapData.totalLines,
            totalLabels = mapData.totalLabels,
            bounds      = mapData.bounds,
        }

        local modeStr = isAtlas and 'Atlas' or 'Live'
        state.statusMsg = string.format('[%s] Loaded [%s]: %s (%d lines, %d labels)', modeStr, folderDisplay, zoneShort, mapData.totalLines, mapData.totalLabels)

        if not isAtlas then
            -- Live mode auto-center on player position
            local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
            local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
            if okMeX and okMeY and meX and meY then
                viewport.centerEqX = meX
                viewport.centerEqY = meY
            else
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            end
        else
            -- Atlas mode center on map bounding box center & adjust zoom comfortably
            viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
            viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            local spanX = math.abs(mapData.bounds.maxX - mapData.bounds.minX)
            local spanY = math.abs(mapData.bounds.maxY - mapData.bounds.minY)
            local maxSpan = math.max(spanX, spanY)
            if maxSpan > 50 then
                viewport.zoom = math.max(viewport.minZoom, math.min(1.2, 700 / maxSpan))
            end
        end
        return true
    else
        mapData.isLoaded = false
        state.statusMsg = string.format('No map files for "%s" in [%s]', zoneShort, folderDisplay)
        return false
    end
end

local function navigateToAtlasZone(zoneShort, pushHistory)
    if not zoneShort or zoneShort == '' then return end

    if pushHistory ~= false then
        if state.atlasHistoryIdx < #state.atlasHistory then
            for i = #state.atlasHistory, state.atlasHistoryIdx + 1, -1 do
                state.atlasHistory[i] = nil
            end
        end
        state.atlasHistory[#state.atlasHistory + 1] = zoneShort
        state.atlasHistoryIdx = #state.atlasHistory
    end

    state.viewMode = 'ATLAS'
    state.atlasZoneShort = zoneShort
    ctrl.followPlayer = false

    local found = nil
    for _, z in ipairs(state.atlasAllZones) do
        if z.short:lower() == zoneShort:lower() then
            found = z
            break
        end
    end
    if not found then
        found = { short = zoneShort, name = zoneShort, era = 'Custom / Other', continent = 'Unknown', level = '?', type = 'Outdoor', connections = {}, hasMap = true }
    end
    state.atlasSelectedZone = found
    state.atlasZoneName = found.name

    loadZoneMap(zoneShort, true)
end

local function returnToLiveZone()
    state.viewMode = 'LIVE'
    state.atlasZoneShort = ''
    state.atlasZoneName = ''
    ctrl.followPlayer = true
    loadZoneMap(state.currentZoneShort, false)
    state.statusMsg = string.format('Returned to Live View: %s (%s)', state.currentZoneName, state.currentZoneShort)
end

local function atlasHistoryBack()
    if state.atlasHistoryIdx > 1 then
        state.atlasHistoryIdx = state.atlasHistoryIdx - 1
        local prevShort = state.atlasHistory[state.atlasHistoryIdx]
        navigateToAtlasZone(prevShort, false)
    end
end

local function atlasHistoryForward()
    if state.atlasHistoryIdx < #state.atlasHistory then
        state.atlasHistoryIdx = state.atlasHistoryIdx + 1
        local nextShort = state.atlasHistory[state.atlasHistoryIdx]
        navigateToAtlasZone(nextShort, false)
    end
end

local function switchToTab(tabIdx)
    state.activeTab = tabIdx
    state.requestedTab = tabIdx
end

local function focusPoi(poi)
    if not poi then return end
    viewport.centerEqX = poi.x
    viewport.centerEqY = poi.y
    ctrl.followPlayer = false
    state.highlightedPoi = {
        x = poi.x,
        y = poi.y,
        z = poi.z or 0,
        text = poi.text or 'Point of Interest',
        time = mq.gettime(),
    }
    switchToTab(1)
    state.statusMsg = string.format('Focused on POI: %s (Y:%.1f, X:%.1f, Z:%.1f)', poi.text, poi.y, poi.x, poi.z or 0)
end

-- ============================================================================
-- NORRATH SHORTEST TRAVEL ROUTE FINDER (BFS Graph Search)
-- ============================================================================
local function findZoneRoute(startShort, targetShort)
    if not startShort or startShort == '' or not targetShort or targetShort == '' then
        return nil, 0
    end
    local sStart = startShort:lower():match('^%s*(.-)%s*$')
    local sTarget = targetShort:lower():match('^%s*(.-)%s*$')
    if sStart == '' or sTarget == '' then return nil, 0 end

    -- Build zone lookup map for rich metadata
    local zoneLookup = {}
    for _, z in ipairs(state.atlasAllZones or {}) do
        if z.short then
            zoneLookup[z.short:lower()] = z
        end
    end

    local startEntry = zoneLookup[sStart] or { short = sStart, name = sStart, era = 'Unknown', type = 'Zone', level = '?' }

    if sStart == sTarget then
        return { startEntry }, 0
    end

    -- Build symmetric bidirectional adjacency graph
    local adj = {}
    local function addEdge(u, v)
        if not u or not v or u == '' or v == '' then return end
        u = u:lower()
        v = v:lower()
        if not adj[u] then adj[u] = {} end
        if not adj[v] then adj[v] = {} end
        adj[u][v] = true
        adj[v][u] = true
    end

    for _, z in ipairs(state.atlasAllZones or {}) do
        local u = z.short:lower()
        for _, c in ipairs(z.connections or {}) do
            addEdge(u, c)
        end
    end

    -- Breadth-First Search (guaranteed shortest unweighted hop path)
    local queue = { sStart }
    local visited = { [sStart] = true }
    local parent = {}

    local found = false
    local qHead = 1
    while qHead <= #queue do
        local curr = queue[qHead]
        qHead = qHead + 1

        if curr == sTarget then
            found = true
            break
        end

        local neighbors = adj[curr] or {}
        for nbr, _ in pairs(neighbors) do
            if not visited[nbr] then
                visited[nbr] = true
                parent[nbr] = curr
                queue[#queue + 1] = nbr
            end
        end
    end

    if not found then
        return nil, 0
    end

    -- Reconstruct path by backtracking from target to start
    local path = {}
    local curr = sTarget
    while curr do
        local zInfo = zoneLookup[curr] or { short = curr, name = curr, era = 'Unknown', type = 'Zone', level = '?' }
        table.insert(path, 1, zInfo)
        curr = parent[curr]
    end

    local hops = math.max(0, #path - 1)
    return path, hops
end

-- ============================================================================
-- TRIUNE LOADOUT & COMBAT RADIUS / WAYPOINTS SYNC
-- ============================================================================
local function syncTriuneLoadout()
    local cfgDir = mq.configDir
    if not cfgDir then return end

    local fn = loadfile(cfgDir .. '/triune_loadout.lua')
    if not fn then
        state.triuneData.isLoaded = false
        return
    end

    local ok, allData = pcall(fn)
    if not ok or type(allData) ~= 'table' then
        state.triuneData.isLoaded = false
        return
    end

    local myName = nil
    local okName, nameVal = pcall(function() return mq.TLO.Me.CleanName() end)
    if okName and nameVal and nameVal ~= '' then myName = nameVal end

    local charData = myName and allData[myName]
    local charCtrl = (type(charData) == 'table' and type(charData.control) == 'table') and charData.control or {}

    local td = state.triuneData
    td.charName = myName or 'Unknown'
    td.isLoaded = true
    td.lastSyncTime = mq.gettime()

    -- Camp & Combat Radii
    td.campRadius          = tonumber(charCtrl.camp_radius or 50) or 50
    td.combatRadius        = tonumber(charCtrl.combat_radius or 100) or 100
    td.hunterRadius        = tonumber(charCtrl.hunter_radius or 250) or 250
    td.pullRadius          = tonumber(charCtrl.pull_radius or 200) or 200
    td.waypointScanRadius  = tonumber(charCtrl.waypoint_scan_radius or 100) or 100

    if charCtrl.pull_radius or charCtrl.hunter_radius or charCtrl.combat_radius then
        ctrl.customSearchRadius = tonumber(charCtrl.pull_radius or charCtrl.hunter_radius or charCtrl.combat_radius) or 200
    end

    -- Camp Location
    if type(charCtrl.camp_loc) == 'table' and charCtrl.camp_loc.x and charCtrl.camp_loc.y then
        td.campLoc = {
            x = tonumber(charCtrl.camp_loc.x) or 0,
            y = tonumber(charCtrl.camp_loc.y) or 0,
            z = tonumber(charCtrl.camp_loc.z) or 0,
        }
    else
        td.campLoc = nil
    end

    -- Waypoints: Character-level vs Zone-level
    local wps = {}
    local zShort = state.currentZoneShort or ''
    local zoneWpObj = (type(allData.__zoneWaypoints) == 'table') and allData.__zoneWaypoints[zShort]

    if type(charCtrl.waypoints) == 'table' and #charCtrl.waypoints > 0 then
        for _, wp in ipairs(charCtrl.waypoints) do
            if type(wp) == 'table' and wp.x and wp.y then
                wps[#wps + 1] = {
                    name = tostring(wp.name or string.format('WP %d', #wps + 1)),
                    x    = tonumber(wp.x) or 0,
                    y    = tonumber(wp.y) or 0,
                    z    = tonumber(wp.z) or 0,
                }
            end
        end
        td.useWaypoints        = (charCtrl.use_waypoints == true)
        td.waypointRadius      = tonumber(charCtrl.waypoint_radius or 20) or 20
        td.waypointScanRadius  = tonumber(charCtrl.waypoint_scan_radius or 100) or 100
        td.waypointLoop        = (charCtrl.waypoint_loop == true)
        td.currentWaypointIdx  = tonumber(charCtrl.current_waypoint_idx or 1) or 1
    elseif type(zoneWpObj) == 'table' and type(zoneWpObj.waypoints) == 'table' and #zoneWpObj.waypoints > 0 then
        for _, wp in ipairs(zoneWpObj.waypoints) do
            if type(wp) == 'table' and wp.x and wp.y then
                wps[#wps + 1] = {
                    name = tostring(wp.name or string.format('WP %d', #wps + 1)),
                    x    = tonumber(wp.x) or 0,
                    y    = tonumber(wp.y) or 0,
                    z    = tonumber(wp.z) or 0,
                }
            end
        end
        td.useWaypoints        = true
        td.waypointRadius      = tonumber(zoneWpObj.waypoint_radius or 20) or 20
        td.waypointScanRadius  = tonumber(zoneWpObj.waypoint_scan_radius or 100) or 100
        td.waypointLoop        = (zoneWpObj.waypoint_loop == true)
        td.currentWaypointIdx  = 1
    end
    td.waypoints = wps

    -- Zone Hazards (anti-stuck hotspots)
    local hazards = {}
    local zoneHazardsObj = (type(allData.__zoneHazards) == 'table') and allData.__zoneHazards[zShort]
    if type(zoneHazardsObj) == 'table' then
        for _, hz in ipairs(zoneHazardsObj) do
            if type(hz) == 'table' and hz.x and hz.y then
                hazards[#hazards + 1] = {
                    x    = tonumber(hz.x) or 0,
                    y    = tonumber(hz.y) or 0,
                    z    = tonumber(hz.z) or 0,
                    hits = tonumber(hz.hits or 1) or 1,
                }
            end
        end
    end
    td.zoneHazards = hazards
end

local Z_FILTER_MODE_OPTIONS = {
    '1: Auto-Z (Smart Floor Isolation)',
    '2: Manual Window (± Range Slider)',
    '3: Disabled (Show All Elevations)',
}

-- ============================================================================
-- SMART AUTO-Z & FLOOR DETECTION ENGINE
-- ============================================================================
local function updateSmartFloorBounds(pX, pY, pZ)
    local sf = state.smartFloor
    local now = mq.gettime()
    local effZ = pZ + sf.overrideOffset

    -- Mode 2: Manual Window
    if ctrl.zFilterMode == 2 then
        local r = ctrl.zFilterRange or 45
        sf.minZ = effZ - r
        sf.maxZ = effZ + r
        sf.activeZ = effZ
        if sf.overrideOffset ~= 0 then
            sf.floorLabel = string.format('Manual: Z %.0f (±%dyd, %+d)', effZ, r, sf.overrideOffset)
        else
            sf.floorLabel = string.format('Manual: Z %.0f (±%dyd)', effZ, r)
        end
        sf.isMultiFloor = true
        return
    elseif ctrl.zFilterMode == 3 then
        -- Mode 3: Disabled (all elevations)
        sf.minZ = -99999
        sf.maxZ = 99999
        sf.activeZ = effZ
        sf.floorLabel = 'All Elevations'
        sf.isMultiFloor = false
        return
    end

    -- Mode 1: Auto-Z (Smart Floor Isolation)
    local distSq = (pX - sf.lastCalcX)^2 + (pY - sf.lastCalcY)^2
    local zDiff = math.abs(pZ - sf.lastCalcZ)
    if (now - sf.lastCalcTime) < 400 and distSq < 400 and zDiff < 4 and sf.lastOffset == sf.overrideOffset then
        return
    end

    sf.lastCalcTime = now
    sf.lastCalcX = pX
    sf.lastCalcY = pY
    sf.lastCalcZ = pZ
    sf.lastOffset = sf.overrideOffset
    sf.activeZ = effZ

    -- Sample Z-distribution of geometry within local radius (200yd)
    local sampleRadiusSq = 200 * 200
    local binSize = 4 -- 4-yard vertical histogram bins
    local histogram = {}
    local totalSamples = 0
    local minObservedZ = 99999
    local maxObservedZ = -99999

    for lId = 0, 3 do
        local lines = mapData.layers[lId] or {}
        local step = (#lines > 2000) and 3 or 1
        for i = 1, #lines, step do
            local seg = lines[i]
            local midX = (seg.x1 + seg.x2) * 0.5
            local midY = (seg.y1 + seg.y2) * 0.5
            local dSq = (midX - pX)^2 + (midY - pY)^2
            if dSq <= sampleRadiusSq then
                local avgZ = (seg.z1 + seg.z2) * 0.5
                local bin = math.floor(avgZ / binSize)
                histogram[bin] = (histogram[bin] or 0) + 1
                totalSamples = totalSamples + 1
                if avgZ < minObservedZ then minObservedZ = avgZ end
                if avgZ > maxObservedZ then maxObservedZ = avgZ end
            end
        end
    end

    -- If few samples in local radius, fallback to comfortable default
    if totalSamples < 10 then
        sf.minZ = effZ - 30
        sf.maxZ = effZ + 45
        if sf.overrideOffset ~= 0 then
            sf.floorLabel = string.format('Peek: Z %.0f..%.0f (%+dyd)', sf.minZ, sf.maxZ, sf.overrideOffset)
        else
            sf.floorLabel = string.format('Auto-Z: Z %.0f..%.0f', sf.minZ, sf.maxZ)
        end
        sf.isMultiFloor = false
        return
    end

    local playerBin = math.floor(effZ / binSize)

    -- 1. Scan upwards to find ceiling void / upper floor separation
    local upperCutoffBin = playerBin + 12 -- default +48yd
    local emptyCountUp = 0
    for b = playerBin + 1, playerBin + 35 do
        local count = histogram[b] or 0
        if count == 0 then
            emptyCountUp = emptyCountUp + 1
            if emptyCountUp >= 3 then -- 3 consecutive empty bins (12yd void)
                upperCutoffBin = b - 1
                break
            end
        else
            emptyCountUp = 0
        end
    end

    -- 2. Scan downwards to find floor drop void
    local lowerCutoffBin = playerBin - 8 -- default -32yd
    local emptyCountDown = 0
    for b = playerBin - 1, playerBin - 30, -1 do
        local count = histogram[b] or 0
        if count == 0 then
            emptyCountDown = emptyCountDown + 1
            if emptyCountDown >= 3 then -- 3 consecutive empty bins (12yd void)
                lowerCutoffBin = b + 1
                break
            end
        else
            emptyCountDown = 0
        end
    end

    local calcMinZ = lowerCutoffBin * binSize - 2
    local calcMaxZ = (upperCutoffBin + 1) * binSize + 3

    -- Ensure a minimum floor height buffer (at least 12yd below, 18yd above)
    sf.minZ = math.min(calcMinZ, effZ - 12)
    sf.maxZ = math.max(calcMaxZ, effZ + 18)

    local zSpan = maxObservedZ - minObservedZ
    sf.isMultiFloor = (zSpan > 45)

    if sf.overrideOffset ~= 0 then
        sf.floorLabel = string.format('Peek: Z %.0f..%.0f (%+dyd)', sf.minZ, sf.maxZ, sf.overrideOffset)
    else
        sf.floorLabel = string.format('Auto-Z: Z %.0f..%.0f', sf.minZ, sf.maxZ)
    end
end

local function getZAlphaMultiplier(avgZ, minZ, maxZ)
    if ctrl.zFilterMode == 3 then
        return 1.0, true
    end

    if avgZ < minZ or avgZ > maxZ then
        if ctrl.zDepthFading then
            local d = (avgZ < minZ) and (minZ - avgZ) or (avgZ - maxZ)
            if d <= 10 then
                local alpha = 0.22 * (1.0 - (d / 10))
                return alpha, true
            end
        end
        return 0.0, false
    end

    if not ctrl.zDepthFading then
        return 1.0, true
    end

    -- Smooth linear fade at floor boundary edges (within 6 yards of minZ/maxZ)
    local fadeEdge = 6.0
    local distToMin = avgZ - minZ
    local distToMax = maxZ - avgZ
    local edgeDist = math.min(distToMin, distToMax)

    if edgeDist < fadeEdge then
        local factor = 0.35 + 0.65 * (math.max(0, edgeDist) / fadeEdge)
        return factor, true
    end

    return 1.0, true
end

-- ============================================================================
-- SPAWN SCANNER & FILTER ENGINE
-- ============================================================================
local function scanZoneSpawns()
    local okZone, zoneName = pcall(function() return mq.TLO.Zone.Name() end)
    if okZone and zoneName then state.currentZoneName = zoneName end

    local okMesh, isMesh = pcall(function() return mq.TLO.Navigation.MeshLoaded() end)
    navState.meshLoaded = (okMesh and isMesh) or false

    local okNavAct, isNavAct = pcall(function() return mq.TLO.Navigation.Active() end)
    navState.navActive = (okNavAct and isNavAct) or false

    local okCount, count = pcall(function() return mq.TLO.SpawnCount('npc')() end)
    if not okCount or not count or count <= 0 then
        spawns.allNPCs = {}
        spawns.filteredNPCs = {}
        spawns.totalCount = 0
        return
    end

    spawns.totalCount = count
    local nowTime = mq.gettime()
    local isInitial = (#spawns.allNPCs == 0)
    local maxFetch = isInitial and math.min(count, 120) or math.min(count, 350)
    local newNpcList = {}

    local myX, myY, myZ = 0, 0, 0
    local okMeX, pX = pcall(function() return mq.TLO.Me.X() end)
    local okMeY, pY = pcall(function() return mq.TLO.Me.Y() end)
    local okMeZ, pZ = pcall(function() return mq.TLO.Me.Z() end)
    if okMeX and pX then myX = pX end
    if okMeY and pY then myY = pY end
    if okMeZ and pZ then myZ = pZ end

    updateSmartFloorBounds(myX, myY, myZ)
    local sf = state.smartFloor

    for i = 1, maxFetch do
        local okSpawn, s = pcall(function() return mq.TLO.NearestSpawn(i, 'npc') end)
        if okSpawn and s and s() then
            local okData, sId, cleanName, level, classShort, conColor, distance, lineOfSight, sx, sy, sz, pctHPs, hate = pcall(function()
                local dead = s.Dead()
                if dead then return nil end
                return s.ID(), s.CleanName(), s.Level(), s.Class.ShortName(), s.ConColor(), s.Distance3D(), s.LineOfSight(), s.X(), s.Y(), s.Z(), s.PctHPs(), s.Aggressive()
            end)

            if okData and sId and sId > 0 then
                local mobEntry = {
                    id          = sId,
                    cleanName   = cleanName or 'Unknown NPC',
                    level       = level or 0,
                    class       = classShort or 'WAR',
                    conColor    = string.upper(tostring(conColor or 'GREY')),
                    distance    = distance or 99999,
                    lineOfSight = lineOfSight or false,
                    x           = sx or 0,
                    y           = sy or 0,
                    z           = sz or 0,
                    pctHPs      = pctHPs or 100,
                    isAggro     = hate or false,
                }
                newNpcList[#newNpcList + 1] = mobEntry

                -- Enqueue for background navmesh validation if not in cache
                local cached = navState.cache[sId]
                if not cached or (nowTime - cached.checkedAt) > 6000 then
                    if not navState.queueSet[sId] then
                        navState.checkQueue[#navState.checkQueue + 1] = sId
                        navState.queueSet[sId] = true
                    end
                end
            end
        end
    end

    spawns.allNPCs = newNpcList

    -- Apply Filters
    local filtered = {}
    local searchLower = string.lower(state.searchText or '')
    local filterIdx = state.conFilterIndex

    for _, mob in ipairs(newNpcList) do
        local keep = true

        -- Search text filter
        if searchLower ~= '' then
            local nameMatch = string.lower(mob.cleanName):find(searchLower, 1, true)
            local idMatch = tostring(mob.id):find(searchLower, 1, true)
            if not nameMatch and not idMatch then keep = false end
        end

        -- Consideration filter
        if keep and filterIdx > 1 then
            local con = mob.conColor
            if filterIdx == 2 and con ~= 'RED' and con ~= 'DARK RED' then keep = false
            elseif filterIdx == 3 and con ~= 'YELLOW' then keep = false
            elseif filterIdx == 4 and con ~= 'WHITE' then keep = false
            elseif filterIdx == 5 and con ~= 'BLUE' then keep = false
            elseif filterIdx == 6 and con ~= 'LIGHT BLUE' then keep = false
            elseif filterIdx == 7 and con ~= 'GREEN' then keep = false
            elseif filterIdx == 8 and con ~= 'GREY' and con ~= 'GRAY' then keep = false
            end
        end

        -- Level filter
        if keep and (mob.level < state.minLevel or mob.level > state.maxLevel) then
            keep = false
        end

        -- Distance filter
        if keep and (mob.distance > state.maxDistance) then
            keep = false
        end

        -- Line of Sight filter
        if keep and state.losOnly and not mob.lineOfSight then
            keep = false
        end

        -- Z-Height & Smart Auto-Z filter
        if keep and ctrl.zFilterMode ~= 3 then
            if mob.z < sf.minZ or mob.z > sf.maxZ then
                keep = false
            end
        end

        -- Pathable only filter
        if keep and state.pathableOnly then
            local c = navState.cache[mob.id]
            if not c or not c.hasPath then keep = false end
        end

        if keep then
            filtered[#filtered + 1] = mob
        end
    end

    -- Sort filtered list
    local sIdx = state.sortIndex
    table.sort(filtered, function(a, b)
        if sIdx == 1 then return a.distance < b.distance
        elseif sIdx == 2 then return a.distance > b.distance
        elseif sIdx == 3 then
            if a.level == b.level then return a.distance < b.distance end
            return a.level > b.level
        elseif sIdx == 4 then
            if a.level == b.level then return a.distance < b.distance end
            return a.level < b.level
        elseif sIdx == 5 then
            return a.cleanName:lower() < b.cleanName:lower()
        end
        return a.distance < b.distance
    end)

    spawns.filteredNPCs = filtered

    -- Scan Group Members
    local groupList = {}
    local okGrp, grpCount = pcall(function() return mq.TLO.Group.Members() end)
    if okGrp and grpCount and grpCount > 0 then
        for g = 1, grpCount do
            local okMem, mem = pcall(function() return mq.TLO.Group.Member(g) end)
            if okMem and mem and mem() then
                local okMData, mName, mX, mY, mZ, mHp = pcall(function()
                    return mem.CleanName(), mem.X(), mem.Y(), mem.Z(), mem.PctHPs()
                end)
                if okMData and mX and mY then
                    groupList[#groupList + 1] = {
                        name = mName or ('Group ' .. g),
                        x = mX, y = mY, z = mZ or 0,
                        pctHPs = mHp or 100,
                    }
                end
            end
        end
    end
    spawns.groupMembers = groupList
end

-- ============================================================================
-- NAVMESH PATH ENGINE (Throttled Background Batch Verification)
-- ============================================================================
local function processNavBatch()
    if not navState.meshLoaded then return end
    if #navState.checkQueue == 0 then return end

    local now = mq.gettime()
    local count = 0
    local maxBatch = navState.batchSize

    while #navState.checkQueue > 0 and count < maxBatch do
        local mobId = table.remove(navState.checkQueue, 1)
        navState.queueSet[mobId] = nil

        if mobId and mobId > 0 then
            local okPath, hasPath = pcall(function()
                return mq.TLO.Navigation.PathExists(string.format('id %d', mobId))()
            end)
            local okLen, pathLen = pcall(function()
                return mq.TLO.Navigation.PathLength(string.format('id %d', mobId))()
            end)

            navState.cache[mobId] = {
                hasPath   = (okPath and hasPath) or false,
                length    = (okLen and pathLen) or 0,
                checkedAt = now,
            }
            count = count + 1
        end
    end
end

-- ============================================================================
-- 2D COORDINATE TRANSFORMS (World Space <-> Canvas Screen Space)
-- ============================================================================
-- In EverQuest:
--   +Y is North (Screen Up)
--   -Y is South (Screen Down)
--   +X is West  (Screen Left)
--   -X is East  (Screen Right)
local function worldToScreen(eqX, eqY, canvasOriginX, canvasOriginY, canvasW, canvasH)
    local cx = canvasOriginX + canvasW * 0.5
    local cy = canvasOriginY + canvasH * 0.5
    local z = viewport.zoom

    local sx = cx - (eqX - viewport.centerEqX) * z
    local sy = cy - (eqY - viewport.centerEqY) * z
    return sx, sy
end

local function screenToWorld(sx, sy, canvasOriginX, canvasOriginY, canvasW, canvasH)
    local cx = canvasOriginX + canvasW * 0.5
    local cy = canvasOriginY + canvasH * 0.5
    local z = math.max(viewport.zoom, 0.001)

    local eqX = viewport.centerEqX - (sx - cx) / z
    local eqY = viewport.centerEqY - (sy - cy) / z
    return eqX, eqY
end

-- ============================================================================
-- 2D MAP CANVAS RENDERING
-- ============================================================================
local function DrawMapCanvas(availW, availH)
    local drawList = ImGui.GetWindowDrawList()
    local canvasPos = ImGui.GetCursorScreenPosVec()
    local cX = canvasPos.x
    local cY = canvasPos.y
    local sf = state.smartFloor

    -- Widget dimensions & hitbox exclusions
    local navW = (sf and sf.overrideOffset ~= 0) and 290 or 220
    local navH = 30
    local badgeX = cX + availW - navW - 10
    local badgeY = cY + 10

    local zoomBtnSize = 24
    local zoomPanelW = zoomBtnSize + 10
    local zoomPanelH = (zoomBtnSize * 4) + 20
    local zoomX = cX + availW - zoomPanelW - 10
    local zoomY = cY + availH - zoomPanelH - 10

    -- Invisible button to capture mouse inputs over canvas
    ImGui.InvisibleButton('##MapCanvasHitbox', availW, availH)
    local isItemHovered = ImGui.IsItemHovered()
    local isItemActive = ImGui.IsItemActive()

    -- Coordinate under cursor
    local mousePos = ImGui.GetMousePosVec()
    local isMouseOverCanvas = (mousePos.x >= cX and mousePos.x <= cX + availW and mousePos.y >= cY and mousePos.y <= cY + availH)
    local isHovered = isItemHovered or isMouseOverCanvas

    if isHovered then
        state.cursorWorldX, state.cursorWorldY = screenToWorld(mousePos.x, mousePos.y, cX, cY, availW, availH)
    end

    local isOverFloorPill = (ctrl.zFilterMode ~= 3 and mousePos.x >= badgeX and mousePos.x <= badgeX + navW and mousePos.y >= badgeY and mousePos.y <= badgeY + navH)
    local isOverZoomWidget = (mousePos.x >= zoomX and mousePos.x <= zoomX + zoomPanelW and mousePos.y >= zoomY and mousePos.y <= zoomY + zoomPanelH)

    -- Safe IO check for MouseWheel & KeyCtrl
    local hasCtrl = false
    local wheelVal = 0
    local okIO, io = pcall(ImGui.GetIO)
    if okIO and io then
        pcall(function() if io.KeyCtrl then hasCtrl = true end end)
        local okW, w = pcall(function() return io.MouseWheel end)
        if okW and type(w) == 'number' and w ~= 0 then
            wheelVal = w
        end
    end

    -- Handle Drag Panning (Ignored when clicking overlay widgets)
    if isHovered and not isOverFloorPill and not isOverZoomWidget then
        if ImGui.IsMouseClicked(1) then
            -- Right click starts pan
            viewport.isDragging = true
            viewport.dragStartMouseX = mousePos.x
            viewport.dragStartMouseY = mousePos.y
            viewport.dragStartCenterEqX = viewport.centerEqX
            viewport.dragStartCenterEqY = viewport.centerEqY
        elseif isItemActive and ImGui.IsMouseDown(0) and not hasCtrl then
            -- Left click drag also pans if not clicking entity or overlay
            if not viewport.isDragging then
                viewport.isDragging = true
                viewport.dragStartMouseX = mousePos.x
                viewport.dragStartMouseY = mousePos.y
                viewport.dragStartCenterEqX = viewport.centerEqX
                viewport.dragStartCenterEqY = viewport.centerEqY
            end
        end
    end

    if viewport.isDragging then
        if ImGui.IsMouseDown(0) or ImGui.IsMouseDown(1) then
            local dx = mousePos.x - viewport.dragStartMouseX
            local dy = mousePos.y - viewport.dragStartMouseY
            local z = math.max(viewport.zoom, 0.001)
            viewport.centerEqX = viewport.dragStartCenterEqX + (dx / z)
            viewport.centerEqY = viewport.dragStartCenterEqY + (dy / z)
            ctrl.followPlayer = false -- Temporarily suspend follow-player while manually panning
        else
            viewport.isDragging = false
        end
    end

    -- Handle Mouse Wheel Zoom (Centering zoom on mouse cursor)
    if isMouseOverCanvas and wheelVal ~= 0 then
        local oldZoom = viewport.zoom
        local factor = (wheelVal > 0) and 1.20 or 0.80
        local newZoom = math.max(viewport.minZoom, math.min(viewport.maxZoom, oldZoom * factor))

        if newZoom ~= oldZoom then
            -- Keep world coordinate under mouse fixed during zoom
            local mWorldX, mWorldY = screenToWorld(mousePos.x, mousePos.y, cX, cY, availW, availH)
            viewport.zoom = newZoom
            local cx = cX + availW * 0.5
            local cy = cY + availH * 0.5
            viewport.centerEqX = mWorldX + (mousePos.x - cx) / newZoom
            viewport.centerEqY = mWorldY + (mousePos.y - cy) / newZoom

            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
    end

    -- Push Clipping Rectangle to strictly contain map canvas
    drawList:PushClipRect(canvasPos, ImVec2(cX + availW, cY + availH), true)

    -- Canvas Background (Dark charcoal / navy)
    local bgCol = ImGui.GetColorU32(0.035, 0.050, 0.075, 1.0)
    drawList:AddRectFilled(canvasPos, ImVec2(cX + availW, cY + availH), bgCol)

    -- Draw Grid Lines (if enabled)
    if ctrl.showGrid then
        local gridSpacing = 500 -- 500 yard grid lines
        if viewport.zoom > 1.2 then gridSpacing = 100
        elseif viewport.zoom < 0.25 then gridSpacing = 1000 end

        local gridCol = ImGui.GetColorU32(0.12, 0.18, 0.25, 0.5)
        local textCol = ImGui.GetColorU32(0.35, 0.45, 0.55, 0.6)

        local minWx, maxWy = screenToWorld(cX, cY, cX, cY, availW, availH)
        local maxWx, minWy = screenToWorld(cX + availW, cY + availH, cX, cY, availW, availH)

        local startGx = math.floor(math.min(minWx, maxWx) / gridSpacing) * gridSpacing
        local endGx = math.ceil(math.max(minWx, maxWx) / gridSpacing) * gridSpacing
        local startGy = math.floor(math.min(minWy, maxWy) / gridSpacing) * gridSpacing
        local endGy = math.ceil(math.max(minWy, maxWy) / gridSpacing) * gridSpacing

        -- Vertical grid lines (constant X)
        for gx = startGx, endGx, gridSpacing do
            local sx, _ = worldToScreen(gx, 0, cX, cY, availW, availH)
            if sx >= cX and sx <= cX + availW then
                drawList:AddLine(ImVec2(sx, cY), ImVec2(sx, cY + availH), gridCol, 1.0)
                drawList:AddText(ImVec2(sx + 3, cY + 3), textCol, string.format('X:%d', gx))
            end
        end

        -- Horizontal grid lines (constant Y)
        for gy = startGy, endGy, gridSpacing do
            local _, sy = worldToScreen(0, gy, cX, cY, availW, availH)
            if sy >= cY and sy <= cX + availW then
                drawList:AddLine(ImVec2(cX, sy), ImVec2(cX + availW, sy), gridCol, 1.0)
                drawList:AddText(ImVec2(cX + 3, sy + 3), textCol, string.format('Y:%d', gy))
            end
        end
    end

    -- Player altitude for Z-filtering & Smart Auto-Z
    local playerX, playerY, playerZ = 0, 0, 0
    local okPX, pXVal = pcall(function() return mq.TLO.Me.X() end)
    local okPY, pYVal = pcall(function() return mq.TLO.Me.Y() end)
    local okPZ, pZVal = pcall(function() return mq.TLO.Me.Z() end)
    if okPX and pXVal then playerX = pXVal end
    if okPY and pYVal then playerY = pYVal end
    if okPZ and pZVal then playerZ = pZVal end

    updateSmartFloorBounds(playerX, playerY, playerZ)
    sf = state.smartFloor

    -- Viewport World-Space Bounds for 0-allocation Frustum Culling
    local minWx, maxWy = screenToWorld(cX, cY, cX, cY, availW, availH)
    local maxWx, minWy = screenToWorld(cX + availW, cY + availH, cX, cY, availW, availH)
    local vpMinX = math.min(minWx, maxWx)
    local vpMaxX = math.max(minWx, maxWx)
    local vpMinY = math.min(minWy, maxWy)
    local vpMaxY = math.max(minWy, maxWy)

    -- Margin buffer to avoid clipping at viewport edges
    local vpPad = 15.0 / math.max(0.01, viewport.zoom)
    vpMinX = vpMinX - vpPad
    vpMaxX = vpMaxX + vpPad
    vpMinY = vpMinY - vpPad
    vpMaxY = vpMaxY + vpPad

    -- Draw Map Lines (Layers 0, 1, 2, 3)
    local layerEnabled = {
        [0] = ctrl.layer0,
        [1] = ctrl.layer1,
        [2] = ctrl.layer2,
        [3] = ctrl.layer3,
    }

    local lineThick = ctrl.lineThickness
    local sfMinZ, sfMaxZ = sf.minZ, sf.maxZ
    local zFading = ctrl.zDepthFading
    local zFilterMode = ctrl.zFilterMode

    for lId = 0, 3 do
        if layerEnabled[lId] then
            local lines = mapData.layers[lId] or {}
            for i = 1, #lines do
                local seg = lines[i]
                -- Fast world-space AABB culling
                if seg.maxX >= vpMinX and seg.minX <= vpMaxX and seg.maxY >= vpMinY and seg.minY <= vpMaxY then
                    local alphaMult, isVis = 1.0, true
                    if zFilterMode ~= 3 then
                        alphaMult, isVis = getZAlphaMultiplier(seg.avgZ, sfMinZ, sfMaxZ, zFilterMode, zFading)
                    end

                    if isVis and alphaMult > 0.01 then
                        local sx1, sy1 = worldToScreen(seg.x1, seg.y1, cX, cY, availW, availH)
                        local sx2, sy2 = worldToScreen(seg.x2, seg.y2, cX, cY, availW, availH)
                        local col = ImGui.GetColorU32(seg.r, seg.g, seg.b, alphaMult)
                        drawList:AddLine(ImVec2(sx1, sy1), ImVec2(sx2, sy2), col, lineThick)
                    end
                end
            end
        end
    end

    -- Draw Map Labels
    if ctrl.showLabels and ctrl.layerLabels then
        local labels = mapData.labels or {}
        for i = 1, #labels do
            local lb = labels[i]
            if lb.x >= vpMinX and lb.x <= vpMaxX and lb.y >= vpMinY and lb.y <= vpMaxY then
                local alphaMult, isVis = 1.0, true
                if zFilterMode ~= 3 then
                    alphaMult, isVis = getZAlphaMultiplier(lb.z, sfMinZ, sfMaxZ, zFilterMode, zFading)
                end
                if isVis and alphaMult > 0.01 then
                    local sx, sy = worldToScreen(lb.x, lb.y, cX, cY, availW, availH)
                    local col = ImGui.GetColorU32(lb.r, lb.g, lb.b, 0.90 * alphaMult)
                    drawList:AddText(ImVec2(sx, sy), col, lb.text)
                end
            end
        end
    end

    -- Draw Triune Patrol Waypoints & Connecting Paths
    local td = state.triuneData
    if ctrl.showWaypoints and td.waypoints and #td.waypoints > 0 then
        local wps = td.waypoints
        -- Draw Connecting Path Lines
        local wpLineCol = ImGui.GetColorU32(0.20, 0.85, 0.95, 0.75)
        for i = 1, #wps - 1 do
            local wsx1, wsy1 = worldToScreen(wps[i].x, wps[i].y, cX, cY, availW, availH)
            local wsx2, wsy2 = worldToScreen(wps[i + 1].x, wps[i + 1].y, cX, cY, availW, availH)
            drawList:AddLine(ImVec2(wsx1, wsy1), ImVec2(wsx2, wsy2), ImGui.GetColorU32(0, 0, 0, 0.6), 3.0)
            drawList:AddLine(ImVec2(wsx1, wsy1), ImVec2(wsx2, wsy2), wpLineCol, 1.8)
        end
        if td.waypointLoop and #wps > 1 then
            local wsxN, wsyN = worldToScreen(wps[#wps].x, wps[#wps].y, cX, cY, availW, availH)
            local wsx1, wsy1 = worldToScreen(wps[1].x, wps[1].y, cX, cY, availW, availH)
            drawList:AddLine(ImVec2(wsxN, wsyN), ImVec2(wsx1, wsy1), ImGui.GetColorU32(0, 0, 0, 0.6), 2.5)
            drawList:AddLine(ImVec2(wsxN, wsyN), ImVec2(wsx1, wsy1), ImGui.GetColorU32(0.35, 0.90, 0.75, 0.55), 1.5)
        end

        -- Draw Waypoint Nodes, Arrival Radius & Scan Radius
        for i, wp in ipairs(wps) do
            local wsx, wsy = worldToScreen(wp.x, wp.y, cX, cY, availW, availH)
            if wsx >= cX - 100 and wsx <= cX + availW + 100 and wsy >= cY - 100 and wsy <= cY + availH + 100 then
                local isCurrentWp = (i == (td.currentWaypointIdx or 1))

                -- Waypoint Scan / Search Radius (e.g. 100yd)
                if ctrl.showSearchRadius then
                    local scanRadScreen = (td.waypointScanRadius or 100) * viewport.zoom
                    if scanRadScreen > 4.0 then
                        local scanCol = isCurrentWp and ImGui.GetColorU32(1.0, 0.85, 0.20, 0.30) or ImGui.GetColorU32(0.20, 0.75, 0.90, 0.15)
                        drawList:AddCircle(ImVec2(wsx, wsy), scanRadScreen, scanCol, 0, 1.2)
                    end
                end

                -- Waypoint Arrival Radius Circle (e.g. 20yd)
                local wpRadScreen = (td.waypointRadius or 20) * viewport.zoom
                if wpRadScreen > 3.0 then
                    drawList:AddCircle(ImVec2(wsx, wsy), wpRadScreen, ImGui.GetColorU32(0.2, 0.85, 0.95, 0.35), 0, 1.0)
                end

                if isCurrentWp then
                    local wpPulse = math.sin(os.clock() * 5.0) * 2.0
                    drawList:AddCircle(ImVec2(wsx, wsy), 8.0 + wpPulse, ImGui.GetColorU32(1.0, 0.85, 0.15, 0.8), 0, 1.8)
                    drawList:AddCircleFilled(ImVec2(wsx, wsy), 5.5, ImGui.GetColorU32(1.0, 0.85, 0.15, 1.0))
                else
                    drawList:AddCircleFilled(ImVec2(wsx, wsy), 4.5, ImGui.GetColorU32(0.15, 0.75, 0.90, 0.9))
                    drawList:AddCircle(ImVec2(wsx, wsy), 4.5, ImGui.GetColorU32(0, 0, 0, 0.8), 0, 1.0)
                end

                -- Label text
                local wpLabel = string.format('#%d %s', i, wp.name)
                drawList:AddText(ImVec2(wsx + 7, wsy - 7), ImGui.GetColorU32(0, 0, 0, 0.9), wpLabel)
                drawList:AddText(ImVec2(wsx + 6, wsy - 8), ImGui.GetColorU32(0.4, 0.9, 1.0, 0.95), wpLabel)
            end
        end
    end

    -- Draw Triune Camp & Combat Radius
    if ctrl.showCampRadius and td.campLoc and td.campLoc.x and td.campLoc.y then
        local csx, csy = worldToScreen(td.campLoc.x, td.campLoc.y, cX, cY, availW, availH)
        local campRadScreen = (td.campRadius or 50) * viewport.zoom

        if campRadScreen > 2.0 then
            drawList:AddCircleFilled(ImVec2(csx, csy), campRadScreen, ImGui.GetColorU32(0.10, 0.70, 0.85, 0.08))
            drawList:AddCircle(ImVec2(csx, csy), campRadScreen, ImGui.GetColorU32(0.20, 0.85, 1.00, 0.60), 0, 1.8)

            -- Camp Anchor center pin
            drawList:AddCircleFilled(ImVec2(csx, csy), 5.0, ImGui.GetColorU32(0.20, 0.90, 1.00, 1.0))
            drawList:AddCircle(ImVec2(csx, csy), 8.0, ImGui.GetColorU32(1.0, 1.0, 1.0, 0.8), 0, 1.5)

            local campText = string.format('Camp (Radius: %dyd)', td.campRadius or 50)
            drawList:AddText(ImVec2(csx + 10, csy - 8), ImGui.GetColorU32(0, 0, 0, 0.9), campText)
            drawList:AddText(ImVec2(csx + 9, csy - 9), ImGui.GetColorU32(0.3, 0.9, 1.0, 1.0), campText)
        end
    end

    -- Draw Search / Pull / Roam Radius Circle (Anchored to Camp if set, otherwise anchored to Player!)
    if ctrl.showSearchRadius or ctrl.showPullRadius then
        local anchorX, anchorY = nil, nil
        local isCampAnchor = false

        if td.campLoc and td.campLoc.x and td.campLoc.y then
            anchorX, anchorY = td.campLoc.x, td.campLoc.y
            isCampAnchor = true
        else
            local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
            local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
            if okMeX and okMeY and meX and meY then
                anchorX, anchorY = meX, meY
            end
        end

        if anchorX and anchorY then
            local asx, asy = worldToScreen(anchorX, anchorY, cX, cY, availW, availH)
            local searchYards = ctrl.customSearchRadius or td.pullRadius or td.hunterRadius or td.combatRadius or 200
            local searchRadScreen = searchYards * viewport.zoom

            if searchRadScreen > 2.0 then
                -- Subtle amber fill + ring
                drawList:AddCircleFilled(ImVec2(asx, asy), searchRadScreen, ImGui.GetColorU32(1.00, 0.80, 0.20, 0.03))
                drawList:AddCircle(ImVec2(asx, asy), searchRadScreen, ImGui.GetColorU32(1.00, 0.75, 0.20, 0.65), 0, 1.5)

                local labelText = isCampAnchor and string.format('Pull Radius (%dyd)', searchYards) or string.format('Search / Roam Radius (%dyd)', searchYards)
                drawList:AddText(ImVec2(asx - 45, asy - searchRadScreen - 14), ImGui.GetColorU32(0, 0, 0, 0.95), labelText)
                drawList:AddText(ImVec2(asx - 46, asy - searchRadScreen - 15), ImGui.GetColorU32(1.0, 0.85, 0.3, 1.0), labelText)
            end
        end
    end

    -- Draw Triune Hazard Avoidance Hotspots (Stuck Memory)
    if ctrl.showHazards and td.zoneHazards and #td.zoneHazards > 0 then
        for _, hz in ipairs(td.zoneHazards) do
            local hsx, hsy = worldToScreen(hz.x, hz.y, cX, cY, availW, availH)
            if hsx >= cX - 40 and hsx <= cX + availW + 40 and hsy >= cY - 40 and hsy <= cY + availH + 40 then
                local hzRadScreen = math.max(12.0 * viewport.zoom, 7.0)
                drawList:AddCircleFilled(ImVec2(hsx, hsy), hzRadScreen, ImGui.GetColorU32(0.95, 0.20, 0.20, 0.20))
                drawList:AddCircle(ImVec2(hsx, hsy), hzRadScreen, ImGui.GetColorU32(0.95, 0.25, 0.25, 0.75), 0, 1.5)
                local hzText = string.format('Hazard (%d hits)', hz.hits or 1)
                drawList:AddText(ImVec2(hsx + 8, hsy - 6), ImGui.GetColorU32(0, 0, 0, 0.9), hzText)
                drawList:AddText(ImVec2(hsx + 7, hsy - 7), ImGui.GetColorU32(1.0, 0.4, 0.4, 0.9), hzText)
            end
        end
    end

    -- Draw Highlighted POI Marker (if active)
    local poi = state.highlightedPoi
    if poi ~= nil then
        local pTime = (poi.time ~= nil and poi.time) or 0
        local px    = (poi.x ~= nil and poi.x) or 0
        local py    = (poi.y ~= nil and poi.y) or 0
        local pText = (poi.text ~= nil and poi.text) or 'Point of Interest'
        local now   = mq.gettime()

        if (now - pTime) < 20000 then
            local psx, psy = worldToScreen(px, py, cX, cY, availW, availH)
            if psx >= cX - 50 and psx <= cX + availW + 50 and psy >= cY - 50 and psy <= cY + availH + 50 then
                local pulse = math.sin((now - pTime) * 0.008) * 5.0
                local rRad = math.max(10.0, 16.0 + pulse)
                drawList:AddCircle(ImVec2(psx, psy), rRad, ImGui.GetColorU32(1.0, 0.85, 0.2, 0.9), 0, 2.5)
                drawList:AddCircleFilled(ImVec2(psx, psy), 5.0, ImGui.GetColorU32(1.0, 0.85, 0.2, 1.0))
                drawList:AddCircle(ImVec2(psx, psy), 5.0, ImGui.GetColorU32(0, 0, 0, 0.9), 0, 1.5)
                drawList:AddLine(ImVec2(psx - rRad - 4, psy), ImVec2(psx + rRad + 4, psy), ImGui.GetColorU32(1.0, 0.85, 0.2, 0.7), 1.5)
                drawList:AddLine(ImVec2(psx, psy - rRad - 4), ImVec2(psx, psy + rRad + 4), ImGui.GetColorU32(1.0, 0.85, 0.2, 0.7), 1.5)
                local pLabel = string.format('[POI] %s', pText)
                drawList:AddText(ImVec2(psx + 8, psy - 14), ImGui.GetColorU32(0, 0, 0, 0.95), pLabel)
                drawList:AddText(ImVec2(psx + 7, psy - 15), ImGui.GetColorU32(1.0, 0.9, 0.3, 1.0), pLabel)
            end
        else
            state.highlightedPoi = nil
        end
    end

    local isAtlasRemote = (state.viewMode == 'ATLAS' and state.atlasZoneShort ~= '' and state.atlasZoneShort:lower() ~= state.currentZoneShort:lower())
    local hoveredMob = nil

    if isAtlasRemote then
        local aName = (state.atlasSelectedZone and state.atlasSelectedZone.name) or state.atlasZoneShort
        drawList:AddText(ImVec2(cX + 12, cY + 12), ImGui.GetColorU32(1.0, 0.8, 0.25, 0.95), string.format('[ATLAS VIEW] %s (%s)', aName, state.atlasZoneShort))
        drawList:AddText(ImVec2(cX + 12, cY + 28), ImGui.GetColorU32(0.65, 0.72, 0.82, 0.8), 'Entity tracking inactive for remote zone. Click "Return to Live" on toolbar to track character.')
    else
        -- Draw Group Members
        if ctrl.showGroup then
            local grpCol = ImGui.GetColorU32(0.20, 0.90, 0.80, 1.0)
            for _, gm in ipairs(spawns.groupMembers) do
                local sx, sy = worldToScreen(gm.x, gm.y, cX, cY, availW, availH)
                if sx >= cX and sx <= cX + availW and sy >= cY and sy <= cY + availH then
                    drawList:AddCircleFilled(ImVec2(sx, sy), 4.5, grpCol)
                    drawList:AddText(ImVec2(sx + 6, sy - 6), grpCol, gm.name)
                end
            end
        end

        -- Current Target ID
        local targetId = 0
        local okTarg, tId = pcall(function() return mq.TLO.Target.ID() end)
        if okTarg and tId then targetId = tId end

        -- Draw NPCs and Process Click Hit-Testing
        local clickedMob = nil
        local doubleClickedMob = nil

        if ctrl.showNPCs then
            for _, mob in ipairs(spawns.filteredNPCs) do
                local alphaMult, isVis = getZAlphaMultiplier(mob.z, sf.minZ, sf.maxZ)

                if isVis and alphaMult > 0.01 then
                    local sx, sy = worldToScreen(mob.x, mob.y, cX, cY, availW, availH)

                    if sx >= cX - 10 and sx <= cX + availW + 10 and sy >= cY - 10 and sy <= cY + availH + 10 then
                        -- Determine Colors
                        local conStyle = getConStyle(mob.conColor)
                        local conColU32 = ImGui.GetColorU32(conStyle.r, conStyle.g, conStyle.b, alphaMult)

                        local cNav = navState.cache[mob.id]
                        local isPathable = cNav and cNav.hasPath
                        local navColU32 = (isPathable and ImGui.GetColorU32(0.15, 0.95, 0.35, alphaMult)) or ImGui.GetColorU32(0.95, 0.20, 0.20, alphaMult)
                        if not navState.meshLoaded then
                            navColU32 = ImGui.GetColorU32(0.6, 0.6, 0.6, 0.8 * alphaMult)
                        end

                        local nodeRadius = ctrl.npcNodeRadius
                        local isTarget = (mob.id == targetId)

                        -- Draw Node by Color Mode
                        if ctrl.colorModeIndex == 1 then
                            -- Dual Mode: Con fill with Nav halo
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, conColU32)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.5, navColU32, 0, 1.5)
                        elseif ctrl.colorModeIndex == 2 then
                            -- Navmesh Reachability Only
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, navColU32)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.0, ImGui.GetColorU32(0, 0, 0, 0.8), 0, 1.0)
                        else
                            -- Con Colors Only
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, conColU32)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.0, ImGui.GetColorU32(0, 0, 0, 0.8), 0, 1.0)
                        end

                        -- Target Highlight Ring
                        if isTarget then
                            local pulseCol = ImGui.GetColorU32(1.0, 0.85, 0.20, 1.0)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 4.0, pulseCol, 0, 2.0)
                        end

                        -- Aggro / Hate Indicator
                        if mob.isAggro then
                            local hateCol = ImGui.GetColorU32(1.0, 0.1, 0.1, 0.9)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 6.0, hateCol, 0, 1.5)
                        end

                        -- Optional Name Tag on Map
                        if ctrl.showNPCNames then
                            drawList:AddText(ImVec2(sx + 6, sy - 6), conColU32, mob.cleanName)
                        end

                        -- Hit Testing
                        if isHovered then
                            local mDist = math.sqrt((mousePos.x - sx)^2 + (mousePos.y - sy)^2)
                            if mDist <= (nodeRadius + 4.0) then
                                hoveredMob = mob
                                drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 5.0, ImGui.GetColorU32(1, 1, 1, 0.9), 0, 2.0)

                                if ImGui.IsMouseClicked(0) then
                                    clickedMob = mob
                                end
                                if ImGui.IsMouseDoubleClicked(0) then
                                    doubleClickedMob = mob
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Process Clicked NPC Actions
        if doubleClickedMob then
            actionQueue.pendingTargetId = doubleClickedMob.id
            actionQueue.pendingNavId = doubleClickedMob.id
            state.activeNavSpawnId = doubleClickedMob.id
            state.activeNavLoc = nil
            state.activeNavCommandTime = mq.gettime()
            state.statusMsg = string.format('Navigating to: %s (ID: %d)', doubleClickedMob.cleanName, doubleClickedMob.id)
        elseif clickedMob then
            actionQueue.pendingTargetId = clickedMob.id
            state.statusMsg = string.format('Selected: %s (ID: %d, Lvl: %d)', clickedMob.cleanName, clickedMob.id, clickedMob.level)
        end

        -- Ground Click-to-Move Navigation (Double-click or Ctrl+Left click on empty terrain)
        if isHovered and not hoveredMob then
            if ImGui.IsMouseDoubleClicked(0) or (ImGui.IsMouseClicked(0) and hasCtrl) then
                local clickX, clickY = screenToWorld(mousePos.x, mousePos.y, cX, cY, availW, availH)
                actionQueue.pendingNavLoc = { y = clickY, x = clickX, z = playerZ }
                state.activeNavLoc = { y = clickY, x = clickX, z = playerZ }
                state.activeNavSpawnId = 0
                state.activeNavCommandTime = mq.gettime()
                state.statusMsg = string.format('Navigating to ground loc: Y:%.1f, X:%.1f, Z:%.1f', clickY, clickX, playerZ)
            end
        end

        -- Query Real-Time Navigation Status
        local isNavActive = false
        local okNav, act = pcall(function() return mq.TLO.Navigation.Active() end)
        if okNav and act then isNavActive = true end

        -- Draw Active Destination / Waypoint Marker & Path Line
        local navRecentlyTriggered = state.activeNavCommandTime and ((mq.gettime() - state.activeNavCommandTime) < 5000)
        local hasPendingNav = (actionQueue.pendingNavLoc ~= nil) or (actionQueue.pendingNavId > 0)
        local shouldDrawNav = ctrl.showNavLine and (isNavActive or navRecentlyTriggered or hasPendingNav or state.activeNavLoc ~= nil or (state.activeNavSpawnId and state.activeNavSpawnId > 0))

        if shouldDrawNav then
            local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
            local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
            if okMeX and okMeY and meX and meY then
                local pSx, pSy = worldToScreen(meX, meY, cX, cY, availW, availH)
                local destX, destY = nil, nil

                if state.activeNavLoc and state.activeNavLoc.x and state.activeNavLoc.y then
                    destX = state.activeNavLoc.x
                    destY = state.activeNavLoc.y
                else
                    local effSpawnId = (state.activeNavSpawnId and state.activeNavSpawnId > 0 and state.activeNavSpawnId) or targetId
                    if effSpawnId and effSpawnId > 0 then
                        local okSp, sp = pcall(function() return mq.TLO.Spawn(effSpawnId) end)
                        if okSp and sp and sp() then
                            local okSx, sX = pcall(function() return sp.X() end)
                            local okSy, sY = pcall(function() return sp.Y() end)
                            if okSx and okSy and sX and sY then
                                destX, destY = sX, sY
                            end
                        end
                    end
                end

                if destX and destY then
                    local pDist = math.sqrt((meX - destX)^2 + (meY - destY)^2)
                    if not isNavActive and pDist < 12 and not hasPendingNav and (mq.gettime() - (state.activeNavCommandTime or 0) > 1500) then
                        -- Arrived at destination
                        state.activeNavLoc = nil
                        state.activeNavSpawnId = 0
                    else
                        local dSx, dSy = worldToScreen(destX, destY, cX, cY, availW, availH)

                        -- Path Line: Solid Emerald with Dark Shadow for visibility
                        drawList:AddLine(ImVec2(pSx, pSy), ImVec2(dSx, dSy), ImGui.GetColorU32(0.0, 0.0, 0.0, 0.75), 3.5)
                        drawList:AddLine(ImVec2(pSx, pSy), ImVec2(dSx, dSy), ImGui.GetColorU32(0.15, 0.95, 0.40, 0.95), 2.0)

                        -- Destination Waypoint Marker (Pulsing Bullseye)
                        local pulse = math.sin(os.clock() * 5.0) * 2.0
                        drawList:AddCircle(ImVec2(dSx, dSy), 11.0 + pulse, ImGui.GetColorU32(1.0, 0.85, 0.15, 0.6), 0, 2.0)
                        drawList:AddCircleFilled(ImVec2(dSx, dSy), 5.0, ImGui.GetColorU32(1.0, 0.85, 0.15, 1.0))
                        drawList:AddCircle(ImVec2(dSx, dSy), 5.0, ImGui.GetColorU32(0.0, 0.0, 0.0, 0.9), 0, 1.2)

                        -- Distance Text Label
                        local distStr = string.format('%.0fyd', pDist)
                        drawList:AddText(ImVec2(dSx + 8, dSy - 8), ImGui.GetColorU32(0.0, 0.0, 0.0, 1.0), distStr)
                        drawList:AddText(ImVec2(dSx + 7, dSy - 9), ImGui.GetColorU32(1.0, 0.9, 0.3, 1.0), distStr)
                    end
                end
            end
        else
            if not isNavActive and not hasPendingNav and (mq.gettime() - (state.activeNavCommandTime or 0) > 4000) then
                state.activeNavLoc = nil
                state.activeNavSpawnId = 0
            end
        end

        -- Draw Player Marker (Arrow pointing in Heading direction)
        local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
        local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
        local _, meHeading = pcall(function() return mq.TLO.Me.Heading.Degrees() end)

        if okMeX and okMeY and meX and meY then
            local psx, psy = worldToScreen(meX, meY, cX, cY, availW, availH)

            -- Auto-follow player
            if ctrl.followPlayer and not viewport.isDragging then
                viewport.centerEqX = meX
                viewport.centerEqY = meY
            end

            -- Calculate Heading Triangle
            local heading = meHeading or 0
            local rad = math.rad(heading)
            local arrowLen = ctrl.playerNodeRadius + 7.0
            local baseLen = ctrl.playerNodeRadius + 2.0
            local wingAngle = math.rad(140)

            local dirX = math.sin(rad)
            local dirY = -math.cos(rad)

            local tipX = psx + dirX * arrowLen
            local tipY = psy + dirY * arrowLen

            local leftRad = rad - wingAngle
            local rightRad = rad + wingAngle

            local leftX = psx + math.sin(leftRad) * baseLen
            local leftY = psy + (-math.cos(leftRad)) * baseLen

            local rightX = psx + math.sin(rightRad) * baseLen
            local rightY = psy + (-math.cos(rightRad)) * baseLen

            local playerCol = ImGui.GetColorU32(0.25, 0.85, 1.00, 1.0)
            local playerFillCol = ImGui.GetColorU32(0.10, 0.40, 0.85, 0.85)

            drawList:AddTriangleFilled(ImVec2(tipX, tipY), ImVec2(leftX, leftY), ImVec2(rightX, rightY), playerFillCol)
            drawList:AddTriangle(ImVec2(tipX, tipY), ImVec2(leftX, leftY), ImVec2(rightX, rightY), playerCol, 1.5)
            drawList:AddCircleFilled(ImVec2(psx, psy), 3.5, ImGui.GetColorU32(1.0, 1.0, 1.0, 1.0))
            drawList:AddCircle(ImVec2(psx, psy), 3.5, ImGui.GetColorU32(0.0, 0.0, 0.0, 0.9), 0, 1.0)
        end
    end

    -- Pop Clipping Rectangle
    drawList:PopClipRect()

    -- On-Canvas Floor Navigation Widget (Top Right Pill)
    if ctrl.zFilterMode ~= 3 then
        ImGui.SetCursorScreenPos(ImVec2(badgeX, badgeY))
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.04, 0.07, 0.12, 0.90)
        ImGui.PushStyleColor(ImGuiCol.Border, 0.20, 0.40, 0.60, 0.80)
        ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4.0)
        ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 3)
        local childFlags = bit.bor(ImGuiWindowFlags.NoScrollbar or 0, ImGuiWindowFlags.NoScrollWithMouse or 0)
        if ImGui.BeginChild('##FloorNavOverlayChild', ImVec2(navW, navH), true, childFlags) then
            local labelCol = (sf.overrideOffset ~= 0) and {1.0, 0.85, 0.2, 1.0} or {0.3, 0.85, 1.0, 1.0}
            ImGui.TextColored(labelCol[1], labelCol[2], labelCol[3], labelCol[4], sf.floorLabel)
            ImGui.SameLine()

            if ImGui.SmallButton('▲##FloorUp') then
                sf.overrideOffset = sf.overrideOffset + 25
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Peek Upper Floor (+25yd)') end

            ImGui.SameLine()
            if ImGui.SmallButton('▼##FloorDown') then
                sf.overrideOffset = sf.overrideOffset - 25
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Peek Lower Floor (-25yd)') end

            if sf.overrideOffset ~= 0 then
                ImGui.SameLine()
                if ImGui.SmallButton('↺##ResetFloor') then
                    sf.overrideOffset = 0
                end
                if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Reset to Live Player Floor') end
            end
        end
        ImGui.EndChild()
        ImGui.PopStyleVar(2)
        ImGui.PopStyleColor(2)
    end

    -- On-Canvas Floating Zoom Control Widget (Bottom-Right)
    ImGui.SetCursorScreenPos(ImVec2(zoomX, zoomY))
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.04, 0.07, 0.12, 0.90)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.20, 0.40, 0.60, 0.80)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4.0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    local childFlags = bit.bor(ImGuiWindowFlags.NoScrollbar or 0, ImGuiWindowFlags.NoScrollWithMouse or 0)
    if ImGui.BeginChild('##MapZoomOverlayChild', ImVec2(zoomPanelW, zoomPanelH), true, childFlags) then
        if ImGui.Button('+##CanvasZoomIn', ImVec2(zoomBtnSize, zoomBtnSize)) then
            viewport.zoom = math.min(viewport.maxZoom, viewport.zoom * 1.25)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom In (+25%)\n(Or roll Mouse Wheel Up)') end

        if ImGui.Button('-##CanvasZoomOut', ImVec2(zoomBtnSize, zoomBtnSize)) then
            viewport.zoom = math.max(viewport.minZoom, viewport.zoom * 0.80)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom Out (-20%)\n(Or roll Mouse Wheel Down)') end

        if ImGui.Button('⟲##CanvasZoomReset', ImVec2(zoomBtnSize, zoomBtnSize)) then
            if state.viewMode == 'LIVE' then
                viewport.zoom = 1.0
                local okX, meX = pcall(function() return mq.TLO.Me.X() end)
                local okY, meY = pcall(function() return mq.TLO.Me.Y() end)
                if okX and okY and meX and meY then
                    viewport.centerEqX = meX
                    viewport.centerEqY = meY
                    ctrl.followPlayer = true
                end
            else
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
                local spanX = math.abs(mapData.bounds.maxX - mapData.bounds.minX)
                local spanY = math.abs(mapData.bounds.maxY - mapData.bounds.minY)
                local maxSpan = math.max(spanX, spanY)
                if maxSpan > 50 then
                    viewport.zoom = math.max(viewport.minZoom, math.min(1.2, 700 / maxSpan))
                end
            end
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Reset View & Zoom to Default Center') end

        -- Auto-Z Floor Filtering Toggle Button (AZ)
        local isAutoZ = (ctrl.zFilterMode ~= 3)
        if isAutoZ then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.25, 0.95, 0.40, 1.0)
            ImGui.PushStyleColor(ImGuiCol.Button, 0.12, 0.32, 0.22, 0.85)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.60, 0.60, 0.65, 0.70)
            ImGui.PushStyleColor(ImGuiCol.Button, 0.18, 0.18, 0.22, 0.70)
        end
        if ImGui.Button('AZ##CanvasToggleAutoZ', ImVec2(zoomBtnSize, zoomBtnSize)) then
            if ctrl.zFilterMode == 3 then
                ctrl.zFilterMode = 1
            else
                ctrl.zFilterMode = 3
            end
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        ImGui.PopStyleColor(2)
        if ImGui.IsItemHovered() then
            local modeDesc = (ctrl.zFilterMode == 1 and 'Auto-Z (Smart Floor Isolation: ON)')
                or (ctrl.zFilterMode == 2 and 'Manual Z-Window: ON')
                or 'Disabled (Show All Elevations)'
            ImGui.SetTooltip('%s', string.format('Auto-Z Floor Filtering: %s\nMode: %s\n[Click] %s',
                (ctrl.zFilterMode ~= 3 and 'ON' or 'OFF'),
                modeDesc,
                (ctrl.zFilterMode ~= 3 and 'Turn Auto-Z OFF (Show All Elevations)' or 'Turn Auto-Z ON (Smart Floor Isolation)')
            ))
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.PopStyleColor(2)



    -- Hover Tooltip for NPC
    if hoveredMob then
        local cNav = navState.cache[hoveredMob.id]
        local pathStr = 'Unchecked'
        if not navState.meshLoaded then
            pathStr = 'Mesh Not Loaded'
        elseif cNav then
            pathStr = cNav.hasPath and string.format('Valid Path (%.1f yds)', cNav.length) or 'NO PATH (Unreachable)'
        end

        local tt = string.format(
            'Name: %s\n' ..
            'Level: %d  |  Class: %s  |  Con: %s\n' ..
            'Distance: %.1f yds  |  LoS: %s  |  Z-Diff: %.1f yds\n' ..
            'HP: %d%%\n' ..
            'Navmesh Status: %s\n\n' ..
            '[Left-Click] Target  |  [Double-Click] Navigate',
            hoveredMob.cleanName,
            hoveredMob.level,
            hoveredMob.class,
            hoveredMob.conColor,
            hoveredMob.distance,
            hoveredMob.lineOfSight and 'YES' or 'NO',
            math.abs(hoveredMob.z - playerZ),
            hoveredMob.pctHPs,
            pathStr
        )
        ImGui.SetTooltip('%s', tt)
    end
end

-- ============================================================================
-- POI SIDE DRAWER (Map Canvas Overlay)
-- ============================================================================
local function DrawPoiDrawer(availW, availH)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4.0)
    if ImGui.BeginChild('##PoiDrawerPanel', ImVec2(availW, availH), true, ImGuiWindowFlags.MenuBar or 0) then
        if ImGui.BeginMenuBar() then
            ImGui.TextColored(0.3, 0.9, 1.0, 1.0, 'Points of Interest')
            ImGui.SameLine()
            local closeX = availW - 32
            if closeX > 100 then
                ImGui.SetCursorPosX(closeX)
            end
            if ImGui.SmallButton('X##ClosePoiDrawer') then
                state.showPoiDrawer = false
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Close POI Drawer') end
            ImGui.EndMenuBar()
        end

        -- Search Bar (Full Width)
        ImGui.PushItemWidth(availW - 44)
        local pSearch, pChanged = ImGui.InputTextWithHint('##PoiSearchFilter', 'Filter labels / landmarks...', state.poiSearchText or '')
        if pChanged then
            state.poiSearchText = pSearch
        end
        ImGui.PopItemWidth()
        if (state.poiSearchText or '') ~= '' then
            ImGui.SameLine()
            if ImGui.SmallButton('X##ClearPoiFilter') then
                state.poiSearchText = ''
            end
        end

        ImGui.Separator()

        -- Filter POIs from mapData.labels
        local q = (state.poiSearchText or ''):lower():match('^%s*(.-)%s*$')
        local labels = mapData.labels or {}
        local matching = {}

        for _, lb in ipairs(labels) do
            if q == '' or lb.text:lower():find(q, 1, true) ~= nil then
                matching[#matching + 1] = lb
            end
        end

        ImGui.TextColored(0.65, 0.72, 0.82, 0.8, string.format('Matches: %d of %d labels', #matching, #labels))

        local listH = availH - 72
        if ImGui.BeginChild('##PoiListScroll', ImVec2(0, listH), true) then
            if #matching == 0 then
                ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'No points of interest match.')
            else
                local tableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0, ImGuiTableFlags.ScrollY or 0)
                if ImGui.BeginTable('##PoiDrawerTable', 3, tableFlags) then
                    ImGui.TableSetupColumn('Landmark / Label', ImGuiTableColumnFlags.WidthStretch or 0)
                    ImGui.TableSetupColumn('Location (Y, X)', ImGuiTableColumnFlags.WidthFixed or 0, 125)
                    ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed or 0, 56)
                    ImGui.TableHeadersRow()

                    for idx, poi in ipairs(matching) do
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        local pr, pg, pb = poi.r or 0.88, poi.g or 0.92, poi.b or 0.96
                        if (pr * 0.299 + pg * 0.587 + pb * 0.114) < 0.25 then
                            pr, pg, pb = 0.88, 0.92, 0.96
                        end
                        local isHighlighted = (state.highlightedPoi and state.highlightedPoi.text == poi.text and state.highlightedPoi.x == poi.x and state.highlightedPoi.y == poi.y)
                        if isHighlighted then
                            ImGui.TextColored(1.0, 0.85, 0.2, 1.0, string.format('★ %s', poi.text))
                        else
                            ImGui.TextColored(pr, pg, pb, 1.0, poi.text)
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('Y: %.1f, X: %.1f, Z: %.1f\nClick "Focus" to center map and pulse locator pin.', poi.y, poi.x, poi.z or 0)
                        end

                        ImGui.TableNextColumn()
                        ImGui.TextColored(0.65, 0.72, 0.82, 0.85, string.format('%.1f, %.1f', poi.y, poi.x))

                        ImGui.TableNextColumn()
                        if ImGui.SmallButton(string.format('Focus##PoiF_%d', idx)) then
                            focusPoi(poi)
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip('%s', 'Center map on this POI and highlight with animated pin')
                        end
                    end
                    ImGui.EndTable()
                end
            end
        end
        ImGui.EndChild()
    end
    ImGui.EndChild()
    ImGui.PopStyleVar()
end

-- ============================================================================
-- ZONE ATLAS TAB (Interactive Norrath Map Browser & Travel Explorer)
-- ============================================================================
local function DrawAtlasTab()
    local availW, availH = ImGui.GetContentRegionAvail()
    local leftW = math.max(340, math.min(480, availW * 0.40))
    local rightW = availW - leftW - 12

    -- Left Pane: Zone Catalog & Filter Surface
    if ImGui.BeginChild('##AtlasCatalogPane', ImVec2(leftW, availH), true) then
        -- Search Bar
        ImGui.TextColored(0.3, 0.85, 1.0, 1.0, 'Norrath Zone Catalog')
        ImGui.PushItemWidth(leftW - 50)
        local sVal, sChanged = ImGui.InputTextWithHint('##AtlasSearchInput', 'Search zone, era, continent...', state.atlasSearchText or '')
        if sChanged then
            state.atlasSearchText = sVal
            filterAtlasZones()
        end
        ImGui.PopItemWidth()
        if (state.atlasSearchText or '') ~= '' then
            ImGui.SameLine()
            if ImGui.SmallButton('X##ClearAtlasSearch') then
                state.atlasSearchText = ''
                filterAtlasZones()
            end
        end

        -- Era Combo Filter
        ImGui.PushItemWidth(leftW - 20)
        local curEra = ATLAS_ERA_OPTIONS[state.atlasEraFilterIdx] or ATLAS_ERA_OPTIONS[1]
        if ImGui.BeginCombo('##AtlasEraCombo', curEra) then
            for idx, opt in ipairs(ATLAS_ERA_OPTIONS) do
                local isSel = (idx == state.atlasEraFilterIdx)
                if ImGui.Selectable(opt, isSel) then
                    state.atlasEraFilterIdx = idx
                    filterAtlasZones()
                end
                if isSel then ImGui.SetItemDefaultFocus() end
            end
            ImGui.EndCombo()
        end

        -- Type Combo Filter
        local curType = ATLAS_TYPE_OPTIONS[state.atlasTypeFilterIdx] or ATLAS_TYPE_OPTIONS[1]
        if ImGui.BeginCombo('##AtlasTypeCombo', curType) then
            for idx, opt in ipairs(ATLAS_TYPE_OPTIONS) do
                local isSel = (idx == state.atlasTypeFilterIdx)
                if ImGui.Selectable(opt, isSel) then
                    state.atlasTypeFilterIdx = idx
                    filterAtlasZones()
                end
                if isSel then ImGui.SetItemDefaultFocus() end
            end
            ImGui.EndCombo()
        end
        ImGui.PopItemWidth()

        ImGui.Separator()

        -- Scan / Reload Buttons
        if ImGui.SmallButton('Rescan Map Files##RescanBtn') then
            scanMapFiles()
            filterAtlasZones()
        end
        ImGui.SameLine()
        ImGui.TextColored(0.65, 0.72, 0.82, 0.8, string.format('%d zones (%d shown)', #state.atlasAllZones, #state.atlasZoneList))

        -- Zone List Table
        local listHeight = availH - 125
        if ImGui.BeginChild('##AtlasZoneListTableScroll', ImVec2(0, listHeight), true) then
            local tableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0, ImGuiTableFlags.ScrollY or 0, ImGuiTableFlags.SelectionHighlight or 0)
            if ImGui.BeginTable('##AtlasZoneListTable', 3, tableFlags) then
                ImGui.TableSetupColumn('Zone Name', ImGuiTableColumnFlags.WidthStretch or 0)
                ImGui.TableSetupColumn('Era / Type', ImGuiTableColumnFlags.WidthFixed or 0, 100)
                ImGui.TableSetupColumn('Map', ImGuiTableColumnFlags.WidthFixed or 0, 42)
                ImGui.TableHeadersRow()

                for _, z in ipairs(state.atlasZoneList) do
                    ImGui.TableNextRow()
                    local isSelected = (state.atlasSelectedZone and state.atlasSelectedZone.short == z.short)
                    local isCurrent = (state.currentZoneShort:lower() == z.short:lower())

                    ImGui.TableNextColumn()
                    local prefix = isCurrent and '▶ ' or ''
                    local label = string.format('%s%s##z_%s', prefix, z.name, z.short)
                    if ImGui.Selectable(label, isSelected, ImGuiSelectableFlags.SpanAllColumns or 0) then
                        state.atlasSelectedZone = z
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Short: %s\nContinent: %s\nLevels: %s\nConnections: %d\n[Click] Select Zone Details', z.short, z.continent, z.level, #(z.connections or {}))
                    end

                    ImGui.TableNextColumn()
                    local typeBadge = z.era
                    if z.era == 'Classic' or z.era == 'Kunark' or z.era == 'Velious' then
                        ImGui.TextColored(0.4, 0.8, 0.9, 0.9, typeBadge)
                    elseif z.era == 'Luclin' or z.era == 'Planes of Power' then
                        ImGui.TextColored(0.8, 0.6, 1.0, 0.9, typeBadge)
                    else
                        ImGui.TextColored(0.7, 0.7, 0.7, 0.85, typeBadge)
                    end

                    ImGui.TableNextColumn()
                    if z.hasMap then
                        ImGui.TextColored(0.2, 0.9, 0.35, 1.0, 'OK')
                    else
                        ImGui.TextColored(0.5, 0.5, 0.5, 0.5, '—')
                    end
                end
                ImGui.EndTable()
            end
        end
        ImGui.EndChild()
    end
    ImGui.EndChild()

    ImGui.SameLine()

    -- Right Pane: Selected Zone Detail, Quick View & Travel Graph
    if ImGui.BeginChild('##AtlasDetailPane', ImVec2(rightW, availH), true) then
        local z = state.atlasSelectedZone
        if not z then
            ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'Select a zone from the catalog on the left.')
        else
            -- Zone Header Banner
            local isCurrent = (state.currentZoneShort:lower() == z.short:lower())
            local isViewedInAtlas = (state.viewMode == 'ATLAS' and state.atlasZoneShort:lower() == z.short:lower())

            ImGui.TextColored(0.25, 0.85, 1.0, 1.0, string.format('%s', z.name))
            if isCurrent then
                ImGui.SameLine()
                ImGui.TextColored(0.2, 0.95, 0.4, 1.0, '(Current Zone)')
            end
            ImGui.TextColored(0.65, 0.72, 0.82, 0.85, string.format('Shortname: %s  |  Era: %s  |  Continent: %s  |  Level: %s  |  Type: %s', z.short, z.era, z.continent, z.level, z.type))

            ImGui.Separator()

            -- Actions Toolbar
            if isViewedInAtlas then
                ImGui.TextColored(1.0, 0.85, 0.2, 1.0, '★ Currently Active in Map View (Atlas Mode)')
                ImGui.SameLine()
                if ImGui.Button('Switch to Map Tab##GoMapTab') then
                    switchToTab(1)
                end
            else
                if ImGui.Button(string.format('Open Map in Atlas View: %s##OpenAtlasBtn', z.name)) then
                    navigateToAtlasZone(z.short, true)
                    switchToTab(1)
                end
            end

            if state.viewMode == 'ATLAS' then
                ImGui.SameLine()
                if ImGui.Button('Return to Live View##AtlasRetLive') then
                    returnToLiveZone()
                    switchToTab(1)
                end
            end

            ImGui.Spacing()
            ImGui.Separator()

            -- Travel Route from Current Zone
            ImGui.TextColored(0.3, 0.85, 1.0, 1.0, 'Travel Route from Current Zone')

            local curShort = (state.currentZoneShort or ''):lower():match('^%s*(.-)%s*$')
            local targetShort = z.short:lower():match('^%s*(.-)%s*$')

            if curShort == '' or curShort == 'unknown' then
                ImGui.TextColored(0.7, 0.7, 0.7, 0.8, 'Current zone not detected in game.')
            elseif curShort == targetShort then
                ImGui.TextColored(0.2, 0.95, 0.4, 1.0, string.format('✓ You are already in this zone (%s).', z.name))
            else
                local curZoneInfo = nil
                for _, cz in ipairs(state.atlasAllZones) do
                    if cz.short:lower() == curShort then curZoneInfo = cz break end
                end
                local curName = curZoneInfo and curZoneInfo.name or (state.currentZoneName ~= '' and state.currentZoneName) or curShort

                local path, hops = findZoneRoute(curShort, targetShort)
                if not path or #path == 0 then
                    ImGui.TextColored(0.9, 0.7, 0.3, 1.0, string.format('No connected route found between %s and %s.', curName, z.name))
                    ImGui.TextColored(0.6, 0.6, 0.6, 0.8, '(May require Teleportation, Druid/Wizard Spire, planar translocator, or Call of the Hero).')
                else
                    ImGui.TextColored(0.2, 0.95, 0.4, 1.0, string.format('Shortest Path: %d zone transition%s (%d zones total)', hops, (hops == 1 and '' or 's'), #path))
                    ImGui.Spacing()

                    -- Visual Step-by-Step Pathway Table
                    local routeTableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0)
                    if ImGui.BeginTable('##AtlasRouteStepsTable', 4, routeTableFlags) then
                        ImGui.TableSetupColumn('Step', ImGuiTableColumnFlags.WidthFixed or 0, 52)
                        ImGui.TableSetupColumn('Zone Name', ImGuiTableColumnFlags.WidthStretch or 0)
                        ImGui.TableSetupColumn('Era / Type', ImGuiTableColumnFlags.WidthFixed or 0, 120)
                        ImGui.TableSetupColumn('Map View', ImGuiTableColumnFlags.WidthFixed or 0, 65)
                        ImGui.TableHeadersRow()

                        for stepIdx, stepZone in ipairs(path) do
                            ImGui.TableNextRow()

                            local isStepStart = (stepIdx == 1)
                            local isStepDest = (stepIdx == #path)

                            ImGui.TableNextColumn()
                            if isStepStart then
                                ImGui.TextColored(0.4, 0.9, 0.5, 1.0, 'START')
                            elseif isStepDest then
                                ImGui.TextColored(1.0, 0.85, 0.2, 1.0, 'DEST')
                            else
                                ImGui.TextColored(0.7, 0.8, 0.9, 0.9, string.format('Step %d', stepIdx))
                            end

                            ImGui.TableNextColumn()
                            local stepLabel = string.format('%s (%s)', stepZone.name, stepZone.short)
                            if isStepStart then
                                ImGui.TextColored(0.4, 0.9, 0.5, 1.0, stepLabel .. ' [Current Zone]')
                            elseif isStepDest then
                                ImGui.TextColored(1.0, 0.85, 0.2, 1.0, stepLabel .. ' [Target]')
                            else
                                ImGui.TextColored(0.9, 0.9, 0.9, 1.0, '➔ ' .. stepLabel)
                            end

                            ImGui.TableNextColumn()
                            ImGui.TextColored(0.65, 0.75, 0.85, 0.85, string.format('%s / %s', stepZone.type or 'Zone', stepZone.era or 'Classic'))

                            ImGui.TableNextColumn()
                            if ImGui.SmallButton(string.format('View##RStep_%d', stepIdx)) then
                                for _, az in ipairs(state.atlasAllZones) do
                                    if az.short:lower() == stepZone.short:lower() then
                                        state.atlasSelectedZone = az
                                        break
                                    end
                                end
                                navigateToAtlasZone(stepZone.short, true)
                                switchToTab(1)
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip('Switch to Map View to inspect %s (%s)', stepZone.name, stepZone.short)
                            end
                        end
                        ImGui.EndTable()
                    end
                end
            end

            ImGui.Spacing()
            ImGui.Separator()

            -- Travel & Connected Zones Section
            ImGui.TextColored(0.3, 0.85, 1.0, 1.0, 'Connected Zones & Travel Routes')
            local conns = z.connections or {}
            if #conns == 0 then
                ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'No direct connected zone links recorded in registry.')
            else
                ImGui.TextColored(0.65, 0.72, 0.82, 0.8, string.format('Directly connected to %d zones (Click to inspect / view map):', #conns))
                ImGui.Spacing()

                for idx, cShort in ipairs(conns) do
                    local cZone = nil
                    for _, cz in ipairs(state.atlasAllZones) do
                        if cz.short:lower() == cShort:lower() then
                            cZone = cz
                            break
                        end
                    end

                    local cName = cZone and cZone.name or cShort
                    local cEra = cZone and cZone.era or 'Classic'
                    local cHasMap = cZone and cZone.hasMap

                    ImGui.Bullet()
                    if ImGui.SmallButton(string.format('%s (%s)##Conn_%d', cName, cShort, idx)) then
                        if cZone then
                            state.atlasSelectedZone = cZone
                        end
                        navigateToAtlasZone(cShort, true)
                        switchToTab(1)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Click to navigate to %s in Atlas Map View\nEra: %s', cName, cEra)
                    end

                    ImGui.SameLine()
                    ImGui.TextColored(0.5, 0.75, 0.85, 0.75, string.format('[%s]', cEra))
                    if cHasMap then
                        ImGui.SameLine()
                        ImGui.TextColored(0.2, 0.85, 0.35, 0.8, '(Map Available)')
                    end
                end
            end

            ImGui.Spacing()
            ImGui.Separator()

            -- Zone Points of Interest (if currently loaded or active)
            ImGui.TextColored(0.3, 0.85, 1.0, 1.0, 'Zone Points of Interest & Key Labels')
            local currentViewingThis = (mapData.zoneShort:lower() == z.short:lower() and mapData.isLoaded)

            if not currentViewingThis then
                ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'Open this zone\'s map to inspect its points of interest and labels.')
                if ImGui.SmallButton('Load Zone Map for POI Inspection##LoadPoiBtn') then
                    navigateToAtlasZone(z.short, true)
                end
            else
                local labels = mapData.labels or {}
                ImGui.TextColored(0.65, 0.72, 0.82, 0.8, string.format('Loaded: %d map labels & landmarks in %s', #labels, z.name))

                -- POI Search
                ImGui.PushItemWidth(math.max(280, math.min(450, rightW - 50)))
                local pSearch, pChanged = ImGui.InputTextWithHint('##AtlasPoiSearch', 'Filter landmarks...', state.poiSearchText or '')
                if pChanged then
                    state.poiSearchText = pSearch
                end
                ImGui.PopItemWidth()
                if (state.poiSearchText or '') ~= '' then
                    ImGui.SameLine()
                    if ImGui.SmallButton('X##ClearAtlasPoiSearch') then
                        state.poiSearchText = ''
                    end
                end

                local q = (state.poiSearchText or ''):lower():match('^%s*(.-)%s*$')
                local matching = {}
                for _, lb in ipairs(labels) do
                    if q == '' or lb.text:lower():find(q, 1, true) ~= nil then
                        matching[#matching + 1] = lb
                    end
                end

                if #matching > 0 then
                    local poiTableH = math.max(120, availH - 330)
                    if ImGui.BeginChild('##AtlasPoiSubScroll', ImVec2(0, poiTableH), true) then
                        local pTableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0, ImGuiTableFlags.ScrollY or 0)
                        if ImGui.BeginTable('##AtlasPoiTable', 3, pTableFlags) then
                            ImGui.TableSetupColumn('Landmark / Label', ImGuiTableColumnFlags.WidthStretch or 0)
                            ImGui.TableSetupColumn('Location (Y, X, Z)', ImGuiTableColumnFlags.WidthFixed or 0, 160)
                            ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed or 0, 56)
                            ImGui.TableHeadersRow()

                            for pIdx, poi in ipairs(matching) do
                                ImGui.TableNextRow()
                                ImGui.TableNextColumn()
                                local pr, pg, pb = poi.r or 0.88, poi.g or 0.92, poi.b or 0.96
                                if (pr * 0.299 + pg * 0.587 + pb * 0.114) < 0.25 then
                                    pr, pg, pb = 0.88, 0.92, 0.96
                                end
                                ImGui.TextColored(pr, pg, pb, 1.0, poi.text)

                                ImGui.TableNextColumn()
                                ImGui.TextColored(0.7, 0.7, 0.7, 0.8, string.format('%.1f, %.1f, %.1f', poi.y, poi.x, poi.z))

                                ImGui.TableNextColumn()
                                if ImGui.SmallButton(string.format('Focus##APoi_%d', pIdx)) then
                                    focusPoi(poi)
                                end
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip('%s', 'Switch to Map Tab, center viewport on this POI and highlight with animated pin')
                                end
                            end
                            ImGui.EndTable()
                        end
                    end
                    ImGui.EndChild()
                else
                    ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'No landmarks match filter.')
                end
            end
        end
    end
    ImGui.EndChild()
end

-- ============================================================================
-- NPC TRACKER TAB (Dedicated Search & Interactive Sortable Table)
-- ============================================================================
local function DrawNPCTrackerTab()
    -- Filter Bar
    ImGui.PushItemWidth(160)
    local searchVal, searchChanged = ImGui.InputText('Search##TrackSearch', state.searchText)
    if searchChanged then
        state.searchText = searchVal
        scanZoneSpawns()
    end
    ImGui.PopItemWidth()

    if state.searchText ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X##ClearSearchBtn') then
            state.searchText = ''
            scanZoneSpawns()
        end
    end

    ImGui.SameLine()
    ImGui.PushItemWidth(140)
    local conIdx, conChanged = ImGui.Combo('Con##TrackCon', state.conFilterIndex, CON_OPTIONS)
    if conChanged then
        state.conFilterIndex = conIdx
        scanZoneSpawns()
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    ImGui.PushItemWidth(140)
    local sortIdx, sortChanged = ImGui.Combo('Sort##TrackSort', state.sortIndex, SORT_OPTIONS)
    if sortChanged then
        state.sortIndex = sortIdx
        scanZoneSpawns()
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    local pathOnly, pathChanged = ImGui.Checkbox('Pathable Only##PathCheck', state.pathableOnly)
    if pathChanged then
        state.pathableOnly = pathOnly
        scanZoneSpawns()
    end

    ImGui.SameLine()
    local losOnly, losChanged = ImGui.Checkbox('LoS Only##LoSCheck', state.losOnly)
    if losChanged then
        state.losOnly = losOnly
        scanZoneSpawns()
    end

    ImGui.Separator()

    -- Spawn List Table
    local tableFlags = bit.bor(
        ImGuiTableFlags.Resizable or 0,
        ImGuiTableFlags.RowBg or 0,
        ImGuiTableFlags.BordersOuter or 0,
        ImGuiTableFlags.BordersV or 0,
        ImGuiTableFlags.ScrollY or 0,
        ImGuiTableFlags.SizingFixedFit or 0
    )

    local availW, availH = ImGui.GetContentRegionAvail()
    local tableHeight = math.max(80, availH - 32)

    if ImGui.BeginTable('##TriuneMapTrackerTable', 8, tableFlags, availW, tableHeight) then
        ImGui.TableSetupColumn('Name', ImGuiTableColumnFlags.WidthStretch, 2.2)
        ImGui.TableSetupColumn('Lvl', ImGuiTableColumnFlags.WidthFixed, 38)
        ImGui.TableSetupColumn('Con', ImGuiTableColumnFlags.WidthFixed, 55)
        ImGui.TableSetupColumn('Dist', ImGuiTableColumnFlags.WidthFixed, 65)
        ImGui.TableSetupColumn('Nav Path', ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableSetupColumn('LoS', ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 55)
        ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 140)
        ImGui.TableHeadersRow()

        local currentTargetId = 0
        local okTarg, targId = pcall(function() return mq.TLO.Target.ID() end)
        if okTarg and targId then currentTargetId = targId end

        for idx, mob in ipairs(spawns.filteredNPCs) do
            ImGui.TableNextRow()
            local isSelected = (mob.id == currentTargetId)

            -- Column 1: Clean Name (Interactive row selectable)
            ImGui.TableSetColumnIndex(0)
            local conStyle = getConStyle(mob.conColor)
            local namePrefix = isSelected and '> ' or ''
            local nameLabel = string.format('%s%s##TrackMob_%d_%d', namePrefix, mob.cleanName, mob.id, idx)
            if isSelected then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.9, 1.0, 1.0)
            else
                ImGui.PushStyleColor(ImGuiCol.Text, conStyle.r, conStyle.g, conStyle.b, 1.0)
            end
            if ImGui.Selectable(nameLabel, isSelected, ImGuiSelectableFlags.AllowDoubleClick or 0) then
                if ImGui.IsMouseDoubleClicked(0) then
                    actionQueue.pendingTargetId = mob.id
                    actionQueue.pendingNavId = mob.id
                    state.activeNavSpawnId = mob.id
                    state.activeNavLoc = nil
                    state.activeNavCommandTime = mq.gettime()
                    state.statusMsg = string.format('Navigating to: %s (ID: %d)', mob.cleanName, mob.id)
                else
                    actionQueue.pendingTargetId = mob.id
                    state.statusMsg = string.format('Targeted: %s (ID: %d)', mob.cleanName, mob.id)
                end
            end
            ImGui.PopStyleColor()
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', string.format('%s (Level %d %s)\n[Click] Target  |  [Double-Click] Navigate', mob.cleanName, mob.level, mob.class))
            end

            -- Column 2: Level
            ImGui.TableSetColumnIndex(1)
            ImGui.Text(tostring(mob.level))

            -- Column 3: Consideration
            ImGui.TableSetColumnIndex(2)
            ImGui.TextColored(conStyle.r, conStyle.g, conStyle.b, 1.0, conStyle.badge)

            -- Column 4: Distance
            ImGui.TableSetColumnIndex(3)
            ImGui.Text(string.format('%.1fy', mob.distance))

            -- Column 5: Navmesh Status Badge
            ImGui.TableSetColumnIndex(4)
            local cNav = navState.cache[mob.id]
            if not navState.meshLoaded then
                ImGui.TextDisabled('[NO MESH]')
            elseif cNav then
                if cNav.hasPath then
                    ImGui.TextColored(0.2, 0.95, 0.35, 1.0, '[PATHABLE]')
                else
                    ImGui.TextColored(0.95, 0.25, 0.25, 1.0, '[NO PATH]')
                end
            else
                ImGui.TextDisabled('[CHECKING]')
            end

            -- Column 6: Line of Sight
            ImGui.TableSetColumnIndex(5)
            if mob.lineOfSight then
                ImGui.TextColored(0.2, 0.9, 0.3, 1.0, 'YES')
            else
                ImGui.TextDisabled('NO')
            end

            -- Column 7: Spawn ID
            ImGui.TableSetColumnIndex(6)
            ImGui.TextDisabled(tostring(mob.id))

            -- Column 8: Actions ([Tar], [Nav], [Map])
            ImGui.TableSetColumnIndex(7)
            local targBtnId = string.format('Tar##%d_%d', mob.id, idx)
            local navBtnId  = string.format('Nav##%d_%d', mob.id, idx)
            local mapBtnId  = string.format('Map##%d_%d', mob.id, idx)

            if ImGui.SmallButton(targBtnId) then
                actionQueue.pendingTargetId = mob.id
                state.statusMsg = string.format('Targeted: %s (ID: %d)', mob.cleanName, mob.id)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Target %s (ID: %d)', mob.cleanName, mob.id)) end

            ImGui.SameLine()
            if ImGui.SmallButton(navBtnId) then
                actionQueue.pendingTargetId = mob.id
                actionQueue.pendingNavId = mob.id
                state.activeNavSpawnId = mob.id
                state.activeNavLoc = nil
                state.activeNavCommandTime = mq.gettime()
                state.statusMsg = string.format('Navigating to: %s (ID: %d)', mob.cleanName, mob.id)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Navigate to %s (ID: %d)', mob.cleanName, mob.id)) end

            ImGui.SameLine()
            if ImGui.SmallButton(mapBtnId) then
                viewport.centerEqX = mob.x
                viewport.centerEqY = mob.y
                ctrl.followPlayer = false
                switchToTab(1)
                state.statusMsg = string.format('Focused map on: %s (Y: %.1f, X: %.1f)', mob.cleanName, mob.y, mob.x)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Center 2D map on %s (Y: %.1f, X: %.1f)', mob.cleanName, mob.y, mob.x)) end
        end

        ImGui.EndTable()
    end
end

-- ============================================================================
-- SETTINGS & LAYERS TAB
-- ============================================================================
local function DrawSettingsTab()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Map Folders & Pack Selection')
    ImGui.Separator()

    -- Active Folder Status Display
    local activeFolderObj = state.mapFolders[state.selectedFolderIndex]
    local activeFolderLabel = activeFolderObj and activeFolderObj.name or '[None]'
    local activeFullPath = activeFolderObj and activeFolderObj.fullPath or (state.activeMapsDirectory or 'NOT FOUND')

    ImGui.Text('Active Map Pack:')
    ImGui.SameLine()
    ImGui.TextColored(0.2, 0.95, 0.35, 1.0, activeFolderLabel)
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(%s)', activeFullPath))

    -- Map Pack Folder Dropdown Selector
    ImGui.PushItemWidth(280)
    local fIdx, fChanged = ImGui.Combo('Select Map Folder##MapFolderCombo', state.selectedFolderIndex, state.mapFolderNames)
    if fChanged then
        state.selectedFolderIndex = fIdx
        if state.mapFolders[fIdx] then
            clearZoneMapCache()
            state.activeMapsDirectory = state.mapFolders[fIdx].fullPath
            loadZoneMap(state.currentZoneShort)
        end
        state.dirtySettings = true
        state.dirtySettingsTime = mq.gettime()
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button('Scan / Refresh Folders##ScanFoldersBtn') then
        clearZoneMapCache()
        scanMapFolders()
        scanMapFiles()
        loadZoneMap(state.currentZoneShort)
    end
    ImGui.SameLine()
    if ImGui.Button('Reload Map##ReloadMapBtn') then
        clearZoneMapCache()
        loadZoneMap(state.currentZoneShort)
    end

    -- Loaded Map Metrics for Current Zone
    if mapData.isLoaded then
        ImGui.TextColored(0.4, 0.8, 1.0, 1.0, string.format('Zone Map Status: %d lines, %d labels parsed from %s', mapData.totalLines, mapData.totalLabels, activeFolderLabel))
    else
        ImGui.TextColored(1.0, 0.7, 0.2, 1.0, string.format('Zone Map Status: No files found for "%s" in %s', state.currentZoneShort, activeFolderLabel))
    end

    ImGui.Spacing()
    -- Quick Custom Subfolder Entry
    ImGui.PushItemWidth(220)
    local subInput, subChanged = ImGui.InputText('Add Subfolder Name##CustomSubInput', state.customSubfolderInput or '')
    if subChanged then
        state.customSubfolderInput = subInput
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button('Add / Select Folder##AddCustomSubBtn') then
        local trimmed = (state.customSubfolderInput or ''):match('^%s*(.-)%s*$')
        if trimmed and trimmed ~= '' then
            local baseDir = state.baseMapsDirectory or getBaseMapsDirectory()
            local full = baseDir and (baseDir .. '/' .. trimmed) or trimmed
            local found = false
            for i, f in ipairs(state.mapFolders) do
                if f.name == trimmed or f.relPath == trimmed then
                    state.selectedFolderIndex = i
                    state.activeMapsDirectory = f.fullPath
                    found = true
                    break
                end
            end
            if not found then
                state.mapFolders[#state.mapFolders + 1] = { name = trimmed, relPath = trimmed, fullPath = full }
                state.mapFolderNames[#state.mapFolderNames + 1] = trimmed
                state.selectedFolderIndex = #state.mapFolders
                state.activeMapsDirectory = full
            end
            loadZoneMap(state.currentZoneShort)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
            state.statusMsg = string.format('Selected map pack "%s"', trimmed)
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Manually adds any custom subfolder name under maps/ (e.g. "Brewall_RoF2" or "MyMaps") and loads it.')
    end

    ImGui.Spacing()
    -- Optional Advanced Custom Base Path
    if ImGui.TreeNodeEx('Advanced Custom Base Path##AdvPathTree', ImGuiTreeNodeFlags.None or 0) then
        ImGui.TextDisabled('Override the root directory to search for maps/')
        ImGui.PushItemWidth(320)
        local custDir, custChanged = ImGui.InputText('Base Path##CustDirInput', state.customMapsDir)
        if custChanged then
            state.customMapsDir = custDir
            scanMapFolders()
            loadZoneMap(state.currentZoneShort)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        ImGui.PopItemWidth()
        ImGui.SameLine()
        if ImGui.Button('Reset to Auto##ResetAutoBaseBtn') then
            state.customMapsDir = ''
            scanMapFolders()
            loadZoneMap(state.currentZoneShort)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        ImGui.TreePop()
    end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Map Layers Visibility')
    ImGui.Separator()

    local l0, c0 = ImGui.Checkbox('Layer 0 (Base Terrain / Geometry)##L0', ctrl.layer0)
    if c0 then ctrl.layer0 = l0; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local l1, c1 = ImGui.Checkbox('Layer 1 (Structures / Buildings)##L1', ctrl.layer1)
    if c1 then ctrl.layer1 = l1; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local l2, c2 = ImGui.Checkbox('Layer 2 (Objects / Details)##L2', ctrl.layer2)
    if c2 then ctrl.layer2 = l2; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local l3, c3 = ImGui.Checkbox('Layer 3 (Waypoints / Triune Lines)##L3', ctrl.layer3)
    if c3 then ctrl.layer3 = l3; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local lb, cl = ImGui.Checkbox('Labels (Map Text & POIs)##LabelsCheck', ctrl.layerLabels)
    if cl then ctrl.layerLabels = lb; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local grid, cg = ImGui.Checkbox('Grid Coordinate Lines##GridCheck', ctrl.showGrid)
    if cg then ctrl.showGrid = grid; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Entity & Visual Options')
    ImGui.Separator()

    local sn, csn = ImGui.Checkbox('Show NPCs on Map##ShowNPCCheck', ctrl.showNPCs)
    if csn then ctrl.showNPCs = sn; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sg, csg = ImGui.Checkbox('Show Group Members##ShowGrpCheck', ctrl.showGroup)
    if csg then ctrl.showGroup = sg; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local snn, csnn = ImGui.Checkbox('Show NPC Name Labels on Map##ShowNpcNamesCheck', ctrl.showNPCNames)
    if csnn then ctrl.showNPCNames = snn; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local snl, csnl = ImGui.Checkbox('Show Active Nav Path Line##ShowNavLineCheck', ctrl.showNavLine)
    if csnl then ctrl.showNavLine = snl; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.PushItemWidth(220)
    local cmIdx, cmChanged = ImGui.Combo('Node Color Mode##ColorModeCombo', ctrl.colorModeIndex, COLOR_MODE_OPTIONS)
    if cmChanged then ctrl.colorModeIndex = cmIdx; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.PopItemWidth()

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Triune Combat & Waypoint Overlays')
    ImGui.Separator()

    local td = state.triuneData
    if td.isLoaded then
        ImGui.TextColored(0.2, 0.95, 0.35, 1.0, string.format('Triune Status: Synchronized (%s)', td.charName))
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('| WPs: %d | Hazards: %d', #td.waypoints, #td.zoneHazards))
    else
        ImGui.TextColored(1.0, 0.7, 0.2, 1.0, 'Triune Status: Loadout not yet detected (triune_loadout.lua)')
    end

    ImGui.SameLine()
    if ImGui.Button('Sync Triune Data##SyncTriuneBtn') then
        syncTriuneLoadout()
    end

    local ss, css = ImGui.Checkbox('Show Search / Roam Radius##ShowSearchRadiusCheck', ctrl.showSearchRadius)
    if css then ctrl.showSearchRadius = ss; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sc, csc = ImGui.Checkbox('Show Camp / Combat Radius##ShowCampRadiusCheck', ctrl.showCampRadius)
    if csc then ctrl.showCampRadius = sc; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local sw, csw = ImGui.Checkbox('Show Patrol Waypoints & Paths##ShowWaypointsCheck', ctrl.showWaypoints)
    if csw then ctrl.showWaypoints = sw; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sh, csh = ImGui.Checkbox('Show Navigation Hazard Hotspots##ShowHazardsCheck', ctrl.showHazards)
    if csh then ctrl.showHazards = sh; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.PushItemWidth(250)
    local srVal, srChanged = ImGui.SliderInt('Search / Pull Radius (yards)##SearchRadSlider', ctrl.customSearchRadius, 25, 600)
    if srChanged then ctrl.customSearchRadius = srVal; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.PopItemWidth()

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Multi-Level Z-Height & Smart Auto-Z')
    ImGui.Separator()

    ImGui.PushItemWidth(260)
    local zmIdx, zmChanged = ImGui.Combo('Z-Filter Mode##ZFilterModeCombo', ctrl.zFilterMode, Z_FILTER_MODE_OPTIONS)
    if zmChanged then
        ctrl.zFilterMode = zmIdx
        state.dirtySettings = true
        state.dirtySettingsTime = mq.gettime()
    end
    ImGui.PopItemWidth()

    if ctrl.zFilterMode == 1 then
        ImGui.TextColored(0.2, 0.95, 0.35, 1.0, string.format('Active Floor Bounds: %s', state.smartFloor.floorLabel))
        local df, cdf = ImGui.Checkbox('Smooth Alpha Depth Fading (Fade Stairs/Ramps)##ZDepthFadeCheck', ctrl.zDepthFading)
        if cdf then ctrl.zDepthFading = df; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    elseif ctrl.zFilterMode == 2 then
        local df, cdf = ImGui.Checkbox('Smooth Alpha Depth Fading##ZDepthFadeCheck', ctrl.zDepthFading)
        if cdf then ctrl.zDepthFading = df; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
        ImGui.PushItemWidth(250)
        local zRangeVal, zChanged = ImGui.SliderInt('Manual Z Window (± yards)##ZRangeSlider', ctrl.zFilterRange, 10, 250)
        if zChanged then ctrl.zFilterRange = zRangeVal; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
        ImGui.PopItemWidth()
    else
        ImGui.TextDisabled('Z-filtering disabled. All vertical floors and elevations are rendered.')
    end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Display Scaling & Geometry')
    ImGui.Separator()

    ImGui.PushItemWidth(250)
    local lt, clt = ImGui.SliderFloat('Map Line Thickness##LineThickSlider', ctrl.lineThickness, 0.5, 3.5, '%.1f')
    if clt then ctrl.lineThickness = lt; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local nr, cnr = ImGui.SliderFloat('NPC Node Radius##NodeRadSlider', ctrl.npcNodeRadius, 2.0, 9.0, '%.1f')
    if cnr then ctrl.npcNodeRadius = nr; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.PopItemWidth()

    local bd, cbd = ImGui.Checkbox('Auto-Brighten Black / Dark Map Lines (High Contrast)##BoostDarkLinesCheck', ctrl.boostDarkLines)
    if cbd then ctrl.boostDarkLines = bd; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Automatically converts black (0,0,0) and dark map lines/labels to crisp visible silver/white against dark backgrounds') end

    ImGui.Spacing()
    ImGui.Separator()
    if ImGui.Button('Save Settings & Zoom Now##ManualSaveSettingsBtn') then
        saveConfig(false)
        state.dirtySettings = false
    end
    ImGui.SameLine()
    ImGui.TextDisabled('(Settings & zoom auto-save on change and on exit)')
end

-- ============================================================================
-- MAIN IMGUI DRAW CALLBACK
-- ============================================================================
local function DrawTriuneMapUI()
    if not state.openGUI then
        state.isRunning = false
        return
    end

    pushTheme()

    local windowFlags = bit.bor(
        ImGuiWindowFlags.NoScrollbar or 0,
        ImGuiWindowFlags.NoScrollWithMouse or 0
    )
    -- Omit NoCollapse so WindowRounding token applies rounded corners cleanly
    windowFlags = bit.band(windowFlags, bit.bnot(ImGuiWindowFlags.NoCollapse or 0))

    local zoneDisplay = (state.viewMode == 'ATLAS') and string.format('Atlas: %s', (state.atlasSelectedZone and state.atlasSelectedZone.name) or state.atlasZoneShort) or state.currentZoneName
    local title = string.format('Triune Map v%s — %s###TriuneMapMainWindow', VERSION, zoneDisplay)
    local open, draw = ImGui.Begin(title, state.openGUI, windowFlags)
    state.openGUI = open

    if not open then
        ImGui.End()
        popTheme()
        state.isRunning = false
        return
    end

    if draw then
        -- Top Toolbar & Navigation Bar
        if state.viewMode == 'ATLAS' then
            ImGui.TextColored(1.0, 0.85, 0.20, 1.0, '[ATLAS MODE]')
            ImGui.SameLine()
            local canBack = (state.atlasHistoryIdx > 1)
            if not canBack then ImGui.BeginDisabled() end
            if ImGui.SmallButton('<##AtlasBackBtn') then
                atlasHistoryBack()
            end
            if not canBack then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Previous zone in Atlas history') end

            ImGui.SameLine()
            local canFwd = (state.atlasHistoryIdx < #state.atlasHistory)
            if not canFwd then ImGui.BeginDisabled() end
            if ImGui.SmallButton('>##AtlasFwdBtn') then
                atlasHistoryForward()
            end
            if not canFwd then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Next zone in Atlas history') end

            ImGui.SameLine()
            ImGui.TextColored(0.3, 0.85, 1.0, 1.0, 'Zone:')
            ImGui.SameLine()
            local aName = (state.atlasSelectedZone and state.atlasSelectedZone.name) or state.atlasZoneShort
            ImGui.Text(string.format('%s (%s)', aName, state.atlasZoneShort))

            ImGui.SameLine()
            if ImGui.Button('Return to Live##ReturnLiveBtn') then
                returnToLiveZone()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Return to active zone and resume live player tracking') end

            local _, rHops = findZoneRoute(state.currentZoneShort, state.atlasZoneShort)
            if rHops and rHops > 0 then
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Route: %d hops##AtlasRouteHopsBtn', rHops)) then
                    switchToTab(2)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('Click to view full step-by-step travel route in Atlas Tab\nFrom %s to %s (%d zone transitions)', state.currentZoneName, aName, rHops))
                end
            end
        else
            ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Zone:')
            ImGui.SameLine()
            ImGui.Text(string.format('%s (%s)', state.currentZoneName, state.currentZoneShort))
        end

        ImGui.SameLine()
        if state.viewMode == 'LIVE' then
            ImGui.TextDisabled(string.format('| NPCs: %d (Visible: %d)', spawns.totalCount, #spawns.filteredNPCs))
            ImGui.SameLine()
            if navState.meshLoaded then
                ImGui.TextColored(0.2, 0.95, 0.35, 1.0, '| Mesh: LOADED')
            else
                ImGui.TextColored(0.95, 0.3, 0.3, 1.0, '| Mesh: NONE')
            end
            ImGui.SameLine()
            if ImGui.Button('Stop Nav##NavHaltBtn') then
                actionQueue.pendingStopNav = true
                state.activeNavLoc = nil
                state.activeNavSpawnId = 0
                state.activeNavCommandTime = 0
                state.statusMsg = 'Navigation stopped.'
            end
            ImGui.SameLine()
            if ImGui.Button('Center on Me##CenterMeBtn') then
                local okX, meX = pcall(function() return mq.TLO.Me.X() end)
                local okY, meY = pcall(function() return mq.TLO.Me.Y() end)
                if okX and okY and meX and meY then
                    viewport.centerEqX = meX
                    viewport.centerEqY = meY
                    ctrl.followPlayer = true
                end
            end
            ImGui.SameLine()
            local fp, cfp = ImGui.Checkbox('Follow##FollowPlayerCheck', ctrl.followPlayer)
            if cfp then ctrl.followPlayer = fp end
        else
            if ImGui.Button('Center Map##CenterAtlasBtn') then
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            end
        end

        ImGui.SameLine()
        local poiBtnText = state.showPoiDrawer and 'POIs [ON]##TogglePoiDrawer' or 'POIs##TogglePoiDrawer'
        if ImGui.Button(poiBtnText) then
            state.showPoiDrawer = not state.showPoiDrawer
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Toggle side drawer for searching Points of Interest & Map Labels') end



        ImGui.Separator()

        -- Tab Bar
        local tabFlags = ImGuiTabBarFlags.None or 0
        if ImGui.BeginTabBar('##TriuneMapMainTabs', tabFlags) then
            local mapFlags = (state.requestedTab == 1 and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
            if ImGui.BeginTabItem('Map View##MapTab', nil, mapFlags) then
                state.activeTab = 1
                local availW, availH = ImGui.GetContentRegionAvail()
                local canvasHeight = math.max(80, availH - 26)
                local tabStartPos = ImGui.GetCursorScreenPosVec()
                local tabX = tabStartPos.x
                local tabY = tabStartPos.y

                if state.showPoiDrawer then
                    local drawerW = math.max(340, math.min(520, availW * 0.38))
                    local canvasW = availW - drawerW - 8
                    DrawMapCanvas(canvasW, canvasHeight)
                    ImGui.SetCursorScreenPos(ImVec2(tabX + canvasW + 8, tabY))
                    DrawPoiDrawer(drawerW, canvasHeight)
                    ImGui.SetCursorScreenPos(ImVec2(tabX, tabY + canvasHeight + 4))
                else
                    DrawMapCanvas(availW, canvasHeight)
                    ImGui.SetCursorScreenPos(ImVec2(tabX, tabY + canvasHeight + 4))
                end
                ImGui.EndTabItem()
            end

            local atlasFlags = (state.requestedTab == 2 and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
            if ImGui.BeginTabItem('Zone Atlas##AtlasTab', nil, atlasFlags) then
                state.activeTab = 2
                DrawAtlasTab()
                ImGui.EndTabItem()
            end

            local trackFlags = (state.requestedTab == 3 and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
            if ImGui.BeginTabItem('NPC Tracker##TrackerTab', nil, trackFlags) then
                state.activeTab = 3
                DrawNPCTrackerTab()
                ImGui.EndTabItem()
            end

            local setFlags = (state.requestedTab == 4 and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected) or 0
            if ImGui.BeginTabItem('Settings & Layers##SettingsTab', nil, setFlags) then
                state.activeTab = 4
                DrawSettingsTab()
                ImGui.EndTabItem()
            end

            state.requestedTab = nil
            ImGui.EndTabBar()
        end

        ImGui.Separator()

        -- Footer Status Bar
        local okMeX, meX = pcall(function() return mq.TLO.Me.X() end)
        local okMeY, meY = pcall(function() return mq.TLO.Me.Y() end)
        local _, meZ     = pcall(function() return mq.TLO.Me.Z() end)

        if okMeX and meX and okMeY and meY then
            ImGui.TextColored(0.4, 0.7, 0.9, 1.0, string.format('Loc: Y:%.1f, X:%.1f, Z:%.1f', meY, meX, meZ or 0))
            ImGui.SameLine()
        end

        if state.activeTab == 1 then
            ImGui.TextDisabled(string.format('| Cursor: Y:%.1f, X:%.1f | Zoom: %.2fx', state.cursorWorldY, state.cursorWorldX, viewport.zoom))
            ImGui.SameLine()
        end

        ImGui.TextDisabled('| Status:')
        ImGui.SameLine()
        ImGui.Text(state.statusMsg)
    end

    ImGui.End()
    popTheme()
end

-- ============================================================================
-- INITIALIZATION & MAIN YIELDABLE ENGINE LOOP
-- ============================================================================
initAtlasRegistry()
scanMapFolders()
loadConfig()
scanMapFiles()
filterAtlasZones()

local okZoneShort, zShort = pcall(function() return mq.TLO.Zone.ShortName() end)
if okZoneShort and zShort then
    state.currentZoneShort = zShort
    local okZId, zId = pcall(function() return mq.TLO.Zone.ID() end)
    state.currentZoneId = (okZId and zId) or 0
    local okZName, zName = pcall(function() return mq.TLO.Zone.Name() end)
    state.currentZoneName = (okZName and zName) or zShort
    loadZoneMap(zShort, false)
end

syncTriuneLoadout()
scanZoneSpawns()
mq.imgui.init('TriuneMapUIWindow', DrawTriuneMapUI)

print(string.format('\ag[Triune Map]\ax v%s Loaded -- In-Game Map, Norrath Atlas & NPC Tracker active. Run with /lua run triune_map', VERSION))

while state.isRunning do
    mq.doevents()

    local now = mq.gettime()

    -- Zone Change Detector
    if (now - state.lastZoneCheckTime) >= 1000 then
        state.lastZoneCheckTime = now
        local okCurShort, curShort = pcall(function() return mq.TLO.Zone.ShortName() end)
        if okCurShort and curShort and curShort ~= state.currentZoneShort and curShort ~= '' then
            state.currentZoneShort = curShort
            local okZId, zId = pcall(function() return mq.TLO.Zone.ID() end)
            state.currentZoneId = (okZId and zId) or 0
            local okZName, zName = pcall(function() return mq.TLO.Zone.Name() end)
            state.currentZoneName = (okZName and zName) or curShort
            if state.viewMode == 'LIVE' then
                loadZoneMap(curShort, false)
            end
            syncTriuneLoadout()
            scanZoneSpawns()
        end
    end

    -- Periodic Triune Loadout Sync (every 2.5s)
    if (now - state.triuneData.lastSyncTime) >= 2500 then
        syncTriuneLoadout()
    end

    -- Periodic Settings Auto-Save (when marked dirty and quiet for 1.5s)
    if state.dirtySettings and (now - state.dirtySettingsTime) >= 1500 then
        saveConfig(true)
        state.dirtySettings = false
    end

    -- Regular Spawn Scanning
    if (now - state.lastScanTime) >= state.scanIntervalMs then
        state.lastScanTime = now
        scanZoneSpawns()
    end

    -- Process Throttled Background Navmesh Batch
    if (now - navState.lastQueueProcessTime) >= 80 then
        navState.lastQueueProcessTime = now
        processNavBatch()
    end

    -- Process Queued Actions from UI Callback
    if actionQueue.pendingTargetId > 0 then
        local tid = actionQueue.pendingTargetId
        actionQueue.pendingTargetId = 0
        pcall(function() mq.cmdf('/target id %d', tid) end)
    end

    if actionQueue.pendingNavId > 0 then
        local nid = actionQueue.pendingNavId
        actionQueue.pendingNavId = 0
        if navState.meshLoaded then
            pcall(function() mq.cmdf('/nav id %d', nid) end)
        else
            pcall(function() mq.cmdf('/stick 10 id %d', nid) end)
        end
    end

    -- Auto-stop fallback stick navigation upon arrival or if target dead
    if state.activeNavSpawnId and state.activeNavSpawnId > 0 and not navState.meshLoaded then
        local okSp, sp = pcall(function() return mq.TLO.Spawn(state.activeNavSpawnId) end)
        if okSp and sp and sp() then
            local okDist, dist = pcall(function() return sp.Distance3D() end)
            local okDead, isDead = pcall(function() return sp.Dead() end)
            if (okDist and dist and dist <= 12) or (okDead and isDead) then
                pcall(function() mq.cmd('/stick off') end)
                state.activeNavSpawnId = 0
                state.statusMsg = (okDead and isDead) and 'Nav target died -- stopped.' or 'Arrived at destination.'
            end
        else
            pcall(function() mq.cmd('/stick off') end)
            state.activeNavSpawnId = 0
        end
    end

    if actionQueue.pendingNavLoc then
        local loc = actionQueue.pendingNavLoc
        actionQueue.pendingNavLoc = nil
        if navState.meshLoaded and loc and loc.y and loc.x and loc.z then
            local ly, lx, lz = loc.y, loc.x, loc.z
            pcall(function() mq.cmdf('/nav loc %f %f %f', ly, lx, lz) end)
        end
    end

    if actionQueue.pendingStopNav then
        actionQueue.pendingStopNav = false
        pcall(function() mq.cmd('/nav stop') end)
        pcall(function() mq.cmd('/stick off') end)
    end

    mq.delay(40)
end

saveConfig(true)
print('\ag[Triune Map]\ax Unloaded cleanly.')
