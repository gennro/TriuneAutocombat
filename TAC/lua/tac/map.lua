---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/map.lua — Triune Map, Norrath Atlas & NPC Tracker Plugin
-- ============================================================================
-- In-process replacement for the old standalone triune_map.lua script (v1.1).
-- Live 2D EverQuest map replacement and zone tracker:
--   - Auto-loads map line and label files from the EverQuest maps directory (Layers 0-3).
--   - Interactive 2D map viewport: smooth pan, zoom, follow-player, and Z-filtering.
--   - Entity overlays for Player, Group, Raid, Pets, Corpses, and all Zone NPCs.
--   - Real-time Navmesh Reachability: NPCs drawn Green (pathable) or Red (unreachable).
--   - Map Click-to-Move: click terrain or double-click an NPC to navigate.
--   - Norrath Zone Atlas with connection routing and POI drawer.
--   - Dedicated NPC Tracking tab with live search, consideration, and pathability filters.
--
-- Camp / hunter anchor / waypoint / hazard overlays are mirrored from the
-- core's live ctrl table (the script used to re-parse triune_loadout.lua
-- from disk every 2.5s). Map settings persist in triune_map_config.lua as
-- before. Window visibility is ctrl.show_map (header Map button, Mini HUD,
-- /ac map, and the Window Layout manager flip it); the engine tick (zone
-- detection, spawn scan chunks, navmesh batches, queued nav actions) runs
-- only while the window is open.
-- ============================================================================

local plugin = {
    id                 = 'map',
    name               = 'Map & NPC Tracker',
    version            = '1.1.0',
    author             = 'Triune',
    description        = '2D in-game map with navmesh-aware NPC tracking, click-to-move, Norrath zone atlas, and Triune camp / waypoint overlays.',
    defaultEnabled     = true,
    tickInterval       = 0.1,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Map', tooltip = 'Toggles the Map, Zone Atlas & NPC Tracker window (map plugin).', flag = 'show_map', desc = '2D zone map, Norrath atlas & NPC tracker', headerButton = true, order = 20 },
}

local core = nil
local ctrl, ImGui, mq = nil, nil, nil

local VERSION = '1.1'

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
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

local UNKNOWN_CON_STYLE = { r = 0.70, g = 0.70, b = 0.70, badge = '[UNK]' }

local function getConStyle(conStr)
    local upper = string.upper(tostring(conStr or ''))
    return CON_COLOR_MAP[upper] or UNKNOWN_CON_STYLE
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
    activeTab           = 1, -- 1: Map View, 2: Zone Atlas, 3: NPC Tracker, 4: Settings & Layers
    requestedTab        = nil, -- When set, forces ImGui to switch active tab via SetSelected
    currentZoneId       = 0,
    currentZoneShort    = '',
    currentZoneName     = 'Unknown Zone',
    statusMsg           = 'Ready',
    lastScanTime        = 0,
    scanIntervalMs      = 500,
    lastZoneCheckTime   = 0,

    -- Per-tick cached gameplay fields (refreshed once per main-loop pass).
    -- lastPlayer is the fallback for the draw callback and the footer; the
    -- callback itself samples the live position every frame (see
    -- state.smoothPlayer) because the host loop only ticks at ~5-7Hz.
    lastPlayer          = { x = 0, y = 0, z = 0, heading = 0, updatedAt = 0 },
    lastTargetId        = 0,

    -- Per-frame smoothed player sample owned by the draw callback. Live TLO
    -- reads are filtered with a frame-time-based exponential lerp so the marker,
    -- camera-follow and heading arrow glide at render rate instead of stepping.
    smoothPlayer        = { x = 0, y = 0, z = 0, heading = 0, seeded = false },

    -- Throttled Line-of-Sight cache for NPCs, [id] = { los = bool, ts = time }
    losCache            = {},

    -- Rolling Line-of-Sight refresh cursor. The spawn list itself is fetched
    -- in one native pass per scan cycle; only the LoS raycasts are spread
    -- across ticks (see refreshLosChunk).
    scanChunk           = { losIdx = 1 },

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
    poiMatchCache       = { q = nil, labels = nil, list = {} }, -- POI filter result, rebuilt only when the query or loaded zone changes
    atlasRouteCache     = { key = nil, path = nil, hops = 0 },   -- last BFS route keyed on "cur>target"
    savedMapFolderName  = nil,    -- folder name restored from config once the folder scan has run
    pendingShowZone     = nil,    -- zone short requested via plugin.showZone before/outside the tick
    customMapsDirInput  = nil,    -- edit buffer for the Base Path field (applied on Enter / Apply)

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
    mapCanvasInitScroll = false,
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
        loadoutPath         = nil, -- resolved triune_loadout.lua path
        campLoc             = nil, -- { x = 0, y = 0, z = 0 }
        campRadius          = 100,
        hunterRadius        = 1500,
        hunterAnchor        = nil, -- { x = 0, y = 0, z = 0 } hunter/puller combat anchor
        hunterCombatRadius  = 250,
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
        manualZ             = nil, -- Manual-mode label cache key (effZ, range, offset)
        manualR             = nil,
        manualOff           = nil,
    },
}

local cfg = {
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
    showAnchor          = true,

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
    -- Coarse world-space spatial buckets per layer (built once per parsed
    -- zone, see buildLineBuckets) so the canvas only walks the cells that
    -- overlap the viewport instead of AABB-testing every segment per frame.
    grid                = nil,
}

local spawns = {
    allNPCs             = {},
    filteredNPCs        = {},
    groupMembers        = {},
    totalCount          = 0,
}

local navState = {
    meshLoaded          = false,
    navActive           = false,
    cache               = {}, -- [id] = { hasPath = bool, length = num, checkedAt = time, lengthAt = time }
    checkQueue          = {}, -- array of IDs needing path checks (entries are never nil'd; see queueHead/queueTail)
    queueHead           = 1,  -- O(1) dequeue pointer (next index to process)
    queueTail           = 0,  -- index of the last enqueued entry
    queueSet            = {}, -- lookup set to prevent queue duplicates
    batchSize           = 6,  -- PathExists checks per nav batch (tick is ~100ms, so ~60/s)
    cacheFreshMs        = 15000,
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
-- PLUGIN DEPENDENCY HELPERS & AUTOLOAD
-- ============================================================================
local function navLoaded()
    local ok, loaded = pcall(function()
        if mq.TLO.Navigation and (mq.TLO.Navigation() ~= nil or mq.TLO.Navigation.MeshLoaded() ~= nil) then
            return true
        end
        local p = mq.TLO.Plugin('mq2nav') or mq.TLO.Plugin('MQ2Nav') or mq.TLO.Plugin('nav')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end

local function navMeshLoaded()
    if not navLoaded() then return false end
    local ok, loaded = pcall(function()
        return mq.TLO.Navigation.MeshLoaded() or false
    end)
    return ok and (loaded == true)
end

local function stickLoaded()
    local ok, loaded = pcall(function()
        if mq.TLO.Stick and (mq.TLO.Stick() ~= nil or mq.TLO.Stick.Status() ~= nil) then
            return true
        end
        local p = mq.TLO.Plugin('mq2moveutils') or mq.TLO.Plugin('MQ2MoveUtils') or mq.TLO.Plugin('moveutils')
        if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        return false
    end)
    return ok and (loaded == true)
end

local function autoloadRequiredPlugins()
    local needWait = false
    if not navLoaded() then
        mq.cmd('/plugin mq2nav')
        needWait = true
    end
    if not stickLoaded() then
        mq.cmd('/plugin mq2moveutils')
        needWait = true
    end
    -- No blocking wait: navLoaded()/stickLoaded() are re-checked on use.
    return needWait
end

-- ============================================================================
-- PERSISTENCE & CONFIGURATION (triune_map_config.lua in mq.configDir)
-- ============================================================================
local CONFIG_FILE = nil -- resolved in onInit once mq is bound

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

-- Resolved once per onInit and reused until onDestroy: after a character swap
-- the core restarts plugins (onDestroy -> onInit) while the TLOs already report
-- the new character, so saving under a freshly-computed key would file the old
-- character's settings under the new name.
local cachedCharKey = nil
local function charKey()
    if cachedCharKey then return cachedCharKey end
    local myName, myServer = nil, nil
    pcall(function()
        myName   = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    cachedCharKey = (myServer or 'default') .. '_' .. (myName or 'default')
    return cachedCharKey
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
        followPlayer        = cfg.followPlayer,

        -- Display & Layer Toggles
        showLabels          = cfg.showLabels,
        showGrid            = cfg.showGrid,
        showNPCs            = cfg.showNPCs,
        showPCs             = cfg.showPCs,
        showGroup           = cfg.showGroup,
        showRaid            = cfg.showRaid,
        showPets            = cfg.showPets,
        showCorpses         = cfg.showCorpses,
        showNPCNames        = cfg.showNPCNames,
        showNavLine         = cfg.showNavLine,
        colorModeIndex      = cfg.colorModeIndex,

        -- Triune Overlays
        showSearchRadius    = cfg.showSearchRadius,
        showCampRadius      = cfg.showCampRadius,
        showPullRadius      = cfg.showPullRadius,
        showWaypoints       = cfg.showWaypoints,
        showHazards         = cfg.showHazards,
        showAnchor          = cfg.showAnchor,

        -- Map Layers 0-3
        layer0              = cfg.layer0,
        layer1              = cfg.layer1,
        layer2              = cfg.layer2,
        layer3              = cfg.layer3,
        layerLabels         = cfg.layerLabels,

        -- Z-Height Filtering & Smart Auto-Z
        zFilterMode         = cfg.zFilterMode,
        zDepthFading        = cfg.zDepthFading,
        zFilterRange        = cfg.zFilterRange,

        -- Visual Geometry
        lineThickness       = cfg.lineThickness,
        npcNodeRadius       = cfg.npcNodeRadius,
        playerNodeRadius    = cfg.playerNodeRadius,
        boostDarkLines      = cfg.boostDarkLines,
        scanIntervalMs      = state.scanIntervalMs,

        -- Tracker & Atlas Filters
        conFilterIndex      = state.conFilterIndex,
        sortIndex           = state.sortIndex,
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
        if cData.followPlayer ~= nil then cfg.followPlayer = (cData.followPlayer == true) end

        if cData.showLabels ~= nil then cfg.showLabels = (cData.showLabels == true) end
        if cData.showGrid ~= nil then cfg.showGrid = (cData.showGrid == true) end
        if cData.showNPCs ~= nil then cfg.showNPCs = (cData.showNPCs == true) end
        if cData.showPCs ~= nil then cfg.showPCs = (cData.showPCs == true) end
        if cData.showGroup ~= nil then cfg.showGroup = (cData.showGroup == true) end
        if cData.showRaid ~= nil then cfg.showRaid = (cData.showRaid == true) end
        if cData.showPets ~= nil then cfg.showPets = (cData.showPets == true) end
        if cData.showCorpses ~= nil then cfg.showCorpses = (cData.showCorpses == true) end
        if cData.showNPCNames ~= nil then cfg.showNPCNames = (cData.showNPCNames == true) end
        if cData.showNavLine ~= nil then cfg.showNavLine = (cData.showNavLine == true) end
        if cData.colorModeIndex ~= nil then cfg.colorModeIndex = tonumber(cData.colorModeIndex) or 1 end

        if cData.showSearchRadius ~= nil then cfg.showSearchRadius = (cData.showSearchRadius == true) end
        if cData.showCampRadius ~= nil then cfg.showCampRadius = (cData.showCampRadius == true) end
        if cData.showPullRadius ~= nil then cfg.showPullRadius = (cData.showPullRadius == true) end
        if cData.showWaypoints ~= nil then cfg.showWaypoints = (cData.showWaypoints == true) end
        if cData.showHazards ~= nil then cfg.showHazards = (cData.showHazards == true) end
        if cData.showAnchor ~= nil then cfg.showAnchor = (cData.showAnchor == true) end

        if cData.layer0 ~= nil then cfg.layer0 = (cData.layer0 == true) end
        if cData.layer1 ~= nil then cfg.layer1 = (cData.layer1 == true) end
        if cData.layer2 ~= nil then cfg.layer2 = (cData.layer2 == true) end
        if cData.layer3 ~= nil then cfg.layer3 = (cData.layer3 == true) end
        if cData.layerLabels ~= nil then cfg.layerLabels = (cData.layerLabels == true) end

        if cData.zFilterMode ~= nil then
            cfg.zFilterMode = tonumber(cData.zFilterMode) or 1
        elseif cData.useZFilter ~= nil then
            cfg.zFilterMode = cData.useZFilter and 2 or 3
        end
        if cData.zDepthFading ~= nil then cfg.zDepthFading = (cData.zDepthFading == true) end
        if cData.zFilterRange ~= nil then cfg.zFilterRange = tonumber(cData.zFilterRange) or 45 end

        if cData.lineThickness ~= nil then cfg.lineThickness = tonumber(cData.lineThickness) or 1.0 end
        if cData.npcNodeRadius ~= nil then cfg.npcNodeRadius = tonumber(cData.npcNodeRadius) or 4.5 end
        if cData.playerNodeRadius ~= nil then cfg.playerNodeRadius = tonumber(cData.playerNodeRadius) or 6.0 end
        if cData.boostDarkLines ~= nil then cfg.boostDarkLines = (cData.boostDarkLines == true) end
        if cData.scanIntervalMs ~= nil then
            state.scanIntervalMs = math.max(250, math.min(3000, tonumber(cData.scanIntervalMs) or 500))
        end

        if cData.conFilterIndex ~= nil then state.conFilterIndex = tonumber(cData.conFilterIndex) or 1 end
        if cData.sortIndex ~= nil then
            local si = math.floor(tonumber(cData.sortIndex) or 1)
            if si < 1 or si > #SORT_OPTIONS then si = 1 end
            state.sortIndex = si
        end
        if cData.pathableOnly ~= nil then state.pathableOnly = (cData.pathableOnly == true) end
        if cData.losOnly ~= nil then state.losOnly = (cData.losOnly == true) end
        if cData.atlasEraFilterIdx ~= nil then state.atlasEraFilterIdx = tonumber(cData.atlasEraFilterIdx) or 1 end
        if cData.atlasTypeFilterIdx ~= nil then state.atlasTypeFilterIdx = tonumber(cData.atlasTypeFilterIdx) or 1 end
        if cData.showPoiDrawer ~= nil then state.showPoiDrawer = (cData.showPoiDrawer == true) end

        -- The folder list is only known after scanMapFolders() (which itself
        -- depends on customMapsDir loaded above), so remember the name and
        -- let applySavedMapFolder() resolve it once the scan has run.
        local savedFolder = cData.activeMapFolder or (allData.__global and allData.__global.selectedMapFolder)
        if savedFolder and savedFolder ~= '' then
            state.savedMapFolderName = savedFolder
        end
    end
end

-- Selects the map folder saved in the config, if it exists in the scanned
-- folder list. Safe to call before the scan (no-op) and again after it.
local function applySavedMapFolder()
    local savedFolder = state.savedMapFolderName
    if not savedFolder or savedFolder == '' then return false end
    for idx, fName in ipairs(state.mapFolderNames or {}) do
        if fName == savedFolder then
            state.selectedFolderIndex = idx
            state.activeMapsDirectory = state.mapFolders[idx] and state.mapFolders[idx].fullPath or state.activeMapsDirectory
            return true
        end
    end
    return false
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

-- Zone travel graph (built once per registry change, see rebuildAtlasGraph):
--   lookup[shortLower] = zone entry, adj[shortLower] = { [nbrLower] = true }
local atlasGraph = { lookup = nil, adj = nil }

-- Pre-lowercases the strings the per-frame Atlas scans compare against so the
-- draw callback never calls :lower() per row.
local function decorateAtlasEntry(z)
    z.shortLower = (z.short or ''):lower()
    z.nameLower  = (z.name or ''):lower()
    z.eraLower   = (z.era or ''):lower()
    z.contLower  = (z.continent or ''):lower()
    local cl = {}
    for i, c in ipairs(z.connections or {}) do cl[i] = tostring(c):lower() end
    z.connLower = cl
    return z
end

local function rebuildAtlasGraph()
    local lookup, adj = {}, {}
    local function addEdge(u, v)
        if not u or not v or u == '' or v == '' then return end
        if not adj[u] then adj[u] = {} end
        if not adj[v] then adj[v] = {} end
        adj[u][v] = true
        adj[v][u] = true
    end
    for _, z in ipairs(state.atlasAllZones or {}) do
        if not z.shortLower then decorateAtlasEntry(z) end
        lookup[z.shortLower] = z
        for _, c in ipairs(z.connLower) do addEdge(z.shortLower, c) end
    end
    atlasGraph.lookup = lookup
    atlasGraph.adj = adj
    state.atlasRouteCache.key = nil
    state.atlasRouteCache.path = nil
    state.atlasRouteCache.hops = 0
end

local function atlasZoneByShort(shortLower)
    if not atlasGraph.lookup then rebuildAtlasGraph() end
    return atlasGraph.lookup[shortLower]
end

local function initAtlasRegistry()
    state.atlasAllZones = {}
    for _, z in ipairs(NORRATH_ZONE_REGISTRY) do
        local entry = decorateAtlasEntry({
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
        })
        state.atlasAllZones[#state.atlasAllZones + 1] = entry
    end
    rebuildAtlasGraph()
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

    -- Method 2: Comprehensive Community Map Pack Probe Dictionary (Instant non-blocking file probing)
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
        if not z.shortLower then decorateAtlasEntry(z) end
        zoneLookup[z.shortLower] = z
    end

    local discoveredShorts = {}

    -- Method 1: lfs (if available)
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

    -- Method 2: Instant direct zone probe for registered zones (<1ms total)
    if not next(discoveredShorts) then
        for _, z in ipairs(state.atlasAllZones) do
            local f = io.open(baseDir .. '/' .. z.short .. '.txt', 'r')
            if f then
                f:close()
                z.hasMap = true
                discoveredShorts[z.shortLower] = true
            else
                z.hasMap = false
            end
        end
    else
        for _, z in ipairs(state.atlasAllZones) do
            z.hasMap = (discoveredShorts[z.shortLower] == true)
        end
    end

    -- Add any custom on-disk zones not in the built-in registry
    for s, _ in pairs(discoveredShorts) do
        if not zoneLookup[s] then
            local cleanName = s:gsub('^%l', string.upper)
            local okZ, zName = pcall(function() return mq.TLO.Zone(s).Name() end)
            if okZ and zName and zName ~= '' then cleanName = zName end

            local entry = decorateAtlasEntry({
                short       = s,
                name        = cleanName,
                era         = 'Custom / Other',
                continent   = 'Custom / Other',
                level       = 'Unknown',
                type        = 'Outdoor',
                connections = {},
                hasMap      = true,
                isCustom    = true,
            })
            state.atlasAllZones[#state.atlasAllZones + 1] = entry
            zoneLookup[s] = entry
        end
    end

    -- Registry contents may have changed (custom zones / hasMap flags):
    -- rebuild the travel graph once here rather than per frame in the Atlas tab.
    rebuildAtlasGraph()
end

local function filterAtlasZones()
    local q = (state.atlasSearchText or ''):lower():match('^%s*(.-)%s*$')
    local eraFilter = ATLAS_ERA_OPTIONS[state.atlasEraFilterIdx] or 'All Expansions'
    local typeFilter = ATLAS_TYPE_OPTIONS[state.atlasTypeFilterIdx] or 'All Zone Types'

    local out = {}
    for _, z in ipairs(state.atlasAllZones) do
        local matchQuery = true
        if q ~= '' then
            if not z.shortLower then decorateAtlasEntry(z) end
            local inName  = (z.nameLower:find(q, 1, true) ~= nil)
            local inShort = (z.shortLower:find(q, 1, true) ~= nil)
            local inEra   = (z.eraLower:find(q, 1, true) ~= nil)
            local inCont  = (z.contLower:find(q, 1, true) ~= nil)
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

-- Zone Map In-Memory Cache (Instant switching between visited zones).
-- Bounded LRU: a parsed zone (lines + labels + buckets) can be several MB,
-- so only the most recently viewed ZONE_CACHE_MAX zones are retained.
local ZONE_CACHE_MAX = 5
local zoneMapCache = {}
local zoneMapCacheOrder = {} -- cache keys, oldest first

local function clearZoneMapCache()
    zoneMapCache = {}
    zoneMapCacheOrder = {}
end

local function touchZoneCacheKey(cacheKey)
    for i = #zoneMapCacheOrder, 1, -1 do
        if zoneMapCacheOrder[i] == cacheKey then
            table.remove(zoneMapCacheOrder, i)
            break
        end
    end
    zoneMapCacheOrder[#zoneMapCacheOrder + 1] = cacheKey
end

local function putZoneCache(cacheKey, entry)
    zoneMapCache[cacheKey] = entry
    touchZoneCacheKey(cacheKey)
    while #zoneMapCacheOrder > ZONE_CACHE_MAX do
        local oldest = table.remove(zoneMapCacheOrder, 1)
        if oldest ~= cacheKey then zoneMapCache[oldest] = nil end
    end
end

-- Coarse spatial buckets for the line layers. Each segment is inserted into
-- every LINE_BUCKET_SIZE-yard cell its AABB overlaps and remembers its minimum
-- cell (cx0/cy0) so the canvas can draw a multi-cell segment exactly once
-- per frame (from the first visible cell it touches) without a per-frame
-- stamp write. Built once per parsed zone and stored on the cache entry.
local LINE_BUCKET_SIZE = 250

local function buildLineBuckets(layers)
    local grid = { cell = LINE_BUCKET_SIZE, layers = {} }
    local inv = 1 / LINE_BUCKET_SIZE
    for lId = 0, 3 do
        local lines = layers[lId] or {}
        local cells = {}
        local gMinX, gMaxX, gMinY, gMaxY = math.huge, -math.huge, math.huge, -math.huge
        for i = 1, #lines do
            local seg = lines[i]
            local cx0 = math.floor(seg.minX * inv)
            local cx1 = math.floor(seg.maxX * inv)
            local cy0 = math.floor(seg.minY * inv)
            local cy1 = math.floor(seg.maxY * inv)
            -- Degenerate guard: a corrupt segment spanning the whole map would
            -- otherwise be copied into thousands of cells.
            if (cx1 - cx0) > 64 then cx1 = cx0 + 64 end
            if (cy1 - cy0) > 64 then cy1 = cy0 + 64 end
            seg.cx0 = cx0
            seg.cy0 = cy0
            if cx0 < gMinX then gMinX = cx0 end
            if cx1 > gMaxX then gMaxX = cx1 end
            if cy0 < gMinY then gMinY = cy0 end
            if cy1 > gMaxY then gMaxY = cy1 end
            for cy = cy0, cy1 do
                local row = cells[cy]
                if not row then row = {}; cells[cy] = row end
                for cx = cx0, cx1 do
                    local bucket = row[cx]
                    if not bucket then bucket = {}; row[cx] = bucket end
                    bucket[#bucket + 1] = seg
                end
            end
        end
        grid.layers[lId] = { cells = cells, minCX = gMinX, maxCX = gMaxX, minCY = gMinY, maxCY = gMaxY, count = #lines }
    end
    return grid
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

    -- Auto-brighten near-black geometry so it is visible on the dark canvas
    -- (Settings > "Auto-Brighten Black / Dark Map Lines"). Applied at parse
    -- time, so toggling it clears zoneMapCache and re-parses.
    local boost = (cfg.boostDarkLines ~= false)

    -- Fast single-pass line parser (supports space and comma delimited coordinates).
    -- The character class accepts tokens like "-" or "1.2.3" that tonumber
    -- rejects, so every coordinate is guarded with `or 0`: a malformed line
    -- degrades to a zero-length segment instead of erroring the plugin.
    for x1, y1, z1, x2, y2, z2, r, g, b in content:gmatch('[Ll]%s+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)') do
        local nx1 = -(tonumber(x1) or 0)
        local ny1 = -(tonumber(y1) or 0)
        local nz1 = tonumber(z1) or 0
        local nx2 = -(tonumber(x2) or 0)
        local ny2 = -(tonumber(y2) or 0)
        local nz2 = tonumber(z2) or 0
        local nr = (tonumber(r) or 180) * 0.003921568627
        local ng = (tonumber(g) or 180) * 0.003921568627
        local nb = (tonumber(b) or 180) * 0.003921568627

        if boost then
            local lum = nr * 0.299 + ng * 0.587 + nb * 0.114
            if lum < 0.25 then
                nr = 0.72
                ng = 0.76
                nb = 0.82
            end
        end

        local segMinX = nx1 < nx2 and nx1 or nx2
        local segMaxX = nx1 > nx2 and nx1 or nx2
        local segMinY = ny1 < ny2 and ny1 or ny2
        local segMaxY = ny1 > ny2 and ny1 or ny2

        if segMinX < bMinX then bMinX = segMinX end
        if segMaxX > bMaxX then bMaxX = segMaxX end
        if segMinY < bMinY then bMinY = segMinY end
        if segMaxY > bMaxY then bMaxY = segMaxY end

        local segMinZ = nz1 < nz2 and nz1 or nz2
        local segMaxZ = nz1 > nz2 and nz1 or nz2
        if segMinZ < bMinZ then bMinZ = segMinZ end
        if segMaxZ > bMaxZ then bMaxZ = segMaxZ end

        linesAdded = linesAdded + 1
        local dxS, dyS = nx2 - nx1, ny2 - ny1
        targetLines[#targetLines + 1] = {
            x1 = nx1, y1 = ny1, z1 = nz1,
            x2 = nx2, y2 = ny2, z2 = nz2,
            r = nr, g = ng, b = nb,
            avgZ = (nz1 + nz2) * 0.5,
            minX = segMinX, maxX = segMaxX,
            minY = segMinY, maxY = segMaxY,
            len  = math.sqrt(dxS * dxS + dyS * dyS), -- 2D world length (sub-pixel cull at low zoom)
        }
    end

    -- Fast single-pass label parser
    for x, y, z, r, g, b, size, text in content:gmatch('[Pp]%s+([%d.-]+)[,%s]+([%d.-]+)[,%s]+([%d.-]+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+(%d+)[,%s]+([^\r\n]+)') do
        local nx = -(tonumber(x) or 0)
        local ny = -(tonumber(y) or 0)
        local nz = tonumber(z) or 0
        local nr = (tonumber(r) or 255) * 0.003921568627
        local ng = (tonumber(g) or 255) * 0.003921568627
        local nb = (tonumber(b) or 255) * 0.003921568627

        if boost then
            local lum = nr * 0.299 + ng * 0.587 + nb * 0.114
            if lum < 0.25 then
                nr = 0.88
                ng = 0.92
                nb = 0.96
            end
        end

        local cleanText = text:gsub('_', ' ')
        labelsAdded = labelsAdded + 1
        targetLabels[#targetLabels + 1] = {
            x = nx, y = ny, z = nz,
            r = nr, g = ng, b = nb,
            size = tonumber(size) or 1,
            text = cleanText,
            textLower = cleanText:lower(), -- POI drawer / Atlas filter compare against this
        }
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
        touchZoneCacheKey(cacheKey)
        mapData.zoneShort   = zoneShort
        mapData.layers      = cached.layers
        mapData.labels      = cached.labels
        mapData.totalLines  = cached.totalLines
        mapData.totalLabels = cached.totalLabels
        mapData.bounds      = cached.bounds
        mapData.grid        = cached.grid
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
    mapData.grid = nil
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
        mapData.grid = buildLineBuckets(mapData.layers)
        putZoneCache(cacheKey, {
            layers      = mapData.layers,
            labels      = mapData.labels,
            totalLines  = mapData.totalLines,
            totalLabels = mapData.totalLabels,
            bounds      = mapData.bounds,
            grid        = mapData.grid,
        })

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
    cfg.followPlayer = false

    local found = atlasZoneByShort(zoneShort:lower())
    if not found then
        found = decorateAtlasEntry({ short = zoneShort, name = zoneShort, era = 'Custom / Other', continent = 'Unknown', level = '?', type = 'Outdoor', connections = {}, hasMap = true })
    end
    state.atlasSelectedZone = found
    state.atlasZoneName = found.name

    loadZoneMap(zoneShort, true)
end

local function returnToLiveZone()
    state.viewMode = 'LIVE'
    state.atlasZoneShort = ''
    state.atlasZoneName = ''
    cfg.followPlayer = true
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
    cfg.followPlayer = false
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

    -- Per-frame callers (Atlas tab) hit this cache; the BFS below only runs
    -- when the start/target pair changes or the graph was rebuilt.
    local rc = state.atlasRouteCache
    local key = sStart .. '>' .. sTarget
    if rc.key == key then
        return rc.path, rc.hops
    end

    if not atlasGraph.lookup or not atlasGraph.adj then rebuildAtlasGraph() end
    local zoneLookup = atlasGraph.lookup
    local adj = atlasGraph.adj

    local startEntry = zoneLookup[sStart] or { short = sStart, name = sStart, era = 'Unknown', type = 'Zone', level = '?' }

    local path, hops = nil, 0
    if sStart == sTarget then
        path, hops = { startEntry }, 0
    else
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

            local neighbors = adj[curr]
            if neighbors then
                for nbr, _ in pairs(neighbors) do
                    if not visited[nbr] then
                        visited[nbr] = true
                        parent[nbr] = curr
                        queue[#queue + 1] = nbr
                    end
                end
            end
        end

        if found then
            -- Reconstruct path by backtracking from target to start
            path = {}
            local curr = sTarget
            while curr do
                local zInfo = zoneLookup[curr] or { short = curr, name = curr, era = 'Unknown', type = 'Zone', level = '?' }
                table.insert(path, 1, zInfo)
                curr = parent[curr]
            end
            hops = math.max(0, #path - 1)
        end
    end

    rc.key = key
    rc.path = path
    rc.hops = hops
    return path, hops
end

-- ============================================================================
-- TRIUNE COMBAT RADIUS / WAYPOINTS SYNC (live core config)
-- ============================================================================
-- The standalone script re-parsed triune_loadout.lua from disk every 2.5s and
-- searched a dozen candidate paths for it. As a plugin we mirror the core's
-- live cfg table straight into state.triuneData, so overlays always match
-- what the combat loop is actually using (camp, hunter anchor, waypoints,
-- zone hazards) with no file I/O.
local function syncTriuneLoadout(verbose)
    local td = state.triuneData
    local charCtrl = ctrl
    if type(charCtrl) ~= 'table' then
        td.isLoaded = false
        if verbose then print('\ar[Triune Map]\ax Core config not available yet.') end
        return
    end

    local myName = nil
    local okName, nameVal = pcall(function() return mq.TLO.Me.CleanName() end)
    if okName and nameVal and nameVal ~= '' then myName = nameVal end

    td.charName = myName or 'Unknown'
    td.isLoaded = true
    td.loadoutPath = 'live core config'
    td.lastSyncTime = mq.gettime()

    -- Camp & Combat Radii
    td.campRadius          = tonumber(charCtrl.camp_radius or 100) or 100
    td.hunterRadius        = tonumber(charCtrl.hunter_radius or 1500) or 1500
    td.waypointScanRadius  = tonumber(charCtrl.waypoint_scan_radius or 100) or 100

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

    -- Hunter / Puller Combat Anchor (roam point)
    td.hunterCombatRadius = tonumber(charCtrl.hunter_combat_radius or 250) or 250
    if type(charCtrl.hunter_combat_loc) == 'table' and charCtrl.hunter_combat_loc.x and charCtrl.hunter_combat_loc.y then
        td.hunterAnchor = {
            x = tonumber(charCtrl.hunter_combat_loc.x) or 0,
            y = tonumber(charCtrl.hunter_combat_loc.y) or 0,
            z = tonumber(charCtrl.hunter_combat_loc.z) or 0,
        }
    else
        td.hunterAnchor = nil
    end

    -- Waypoints: Character-level vs Zone-level
    local wps = {}
    local zShort = state.currentZoneShort or ''
    local zoneWpObj = (type(charCtrl.zone_waypoints) == 'table') and charCtrl.zone_waypoints[zShort]

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
    else
        td.useWaypoints = false
    end
    td.waypoints = wps

    -- Zone Hazards (anti-stuck hotspots)
    local hazards = {}
    local zoneHazardsObj = (type(charCtrl.zone_hazards) == 'table') and charCtrl.zone_hazards[zShort]
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

    if verbose then
        print(string.format('\ag[Triune Map]\ax Triune data synced from core -- WPs: %d | Camp: %s | Anchor: %s | Hazards: %d',
            #td.waypoints,
            ((td.campLoc and td.campLoc.x) and 'set' or 'none'),
            ((td.hunterAnchor and td.hunterAnchor.x) and 'set' or 'none'),
            #td.zoneHazards))
    end
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
    if cfg.zFilterMode == 2 then
        local r = cfg.zFilterRange or 45
        sf.minZ = effZ - r
        sf.maxZ = effZ + r
        sf.activeZ = effZ
        -- The label only shows whole yards: rebuild it when the rounded Z,
        -- range or peek offset actually change instead of every call.
        local zRound = math.floor(effZ + 0.5)
        if sf.manualZ ~= zRound or sf.manualR ~= r or sf.manualOff ~= sf.overrideOffset then
            sf.manualZ, sf.manualR, sf.manualOff = zRound, r, sf.overrideOffset
            if sf.overrideOffset ~= 0 then
                sf.floorLabel = string.format('Manual: Z %d (±%dyd, %+d)', zRound, r, sf.overrideOffset)
            else
                sf.floorLabel = string.format('Manual: Z %d (±%dyd)', zRound, r)
            end
        end
        sf.isMultiFloor = true
        return
    elseif cfg.zFilterMode == 3 then
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

local function getZAlphaMultiplier(avgZ, minZ, maxZ, zFilterMode, zDepthFading)
    local filterMode = (zFilterMode ~= nil) and zFilterMode or (cfg and cfg.zFilterMode)
    if filterMode == 3 then
        return 1.0, true
    end

    local depthFading = (zDepthFading ~= nil) and zDepthFading or (cfg and cfg.zDepthFading)

    if avgZ < minZ or avgZ > maxZ then
        if depthFading then
            local d = (avgZ < minZ) and (minZ - avgZ) or (avgZ - maxZ)
            if d <= 10 then
                local alpha = 0.22 * (1.0 - (d / 10))
                return alpha, true
            end
        end
        return 0.0, false
    end

    if not depthFading then
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
-- Spawn scan sizing. The NPC list is fetched in ONE native pass per cycle
-- (mq.getFilteredSpawns) so positions are never mixed across ticks; only the
-- Line-of-Sight raycasts are spread across ticks in SCAN_LOS_CHUNK slices.
local SCAN_MAX_NPCS    = 150 -- nearest NPCs kept per cycle (was 120 via NearestSpawn)
local SCAN_LOS_CHUNK   = 8   -- raycasts per tick from the rolling LoS cursor
local SCAN_LOS_BUDGET  = 24  -- raycasts run synchronously on init / zone change
local LOS_STALE_MS     = 5000

-- Player marker smoothing. The draw callback samples Me.X/Y/Z/Heading live every
-- frame (the host main loop only reaches the plugin tick every ~150ms, far too
-- slow to drive movement) and runs the sample through a frame-time-based
-- exponential filter. PLAYER_SMOOTH_TAU is the filter time constant in seconds:
-- small enough that the marker tracks the live position with no visible lag,
-- large enough to hide the client's per-frame position quantisation.
-- PLAYER_SNAP_DIST is the world-unit jump (zone / gate / succor) beyond which the
-- filter snaps instead of sliding the marker across the map.
local PLAYER_SMOOTH_TAU  = 0.06
local PLAYER_SNAP_DIST   = 150.0

-- Frame-rate-independent exponential approach: returns the blend factor to move
-- a smoothed value toward its target for a frame of dt seconds.
local function smoothAlpha(dt, tau)
    if dt <= 0 then return 1 end
    return 1 - math.exp(-dt / tau)
end

-- Shortest-arc lerp between two headings in degrees (handles the 359 -> 0 wrap).
local function lerpHeading(from, to, alpha)
    local delta = (to - from + 540) % 360 - 180
    return (from + delta * alpha) % 360
end

-- Samples the live player position/heading and advances the smoothed sample by
-- one frame. Falls back to the per-tick cache when a live read fails so the
-- marker never drops to world origin. Returns x, y, z, heading.
local function samplePlayerSmoothed(dt)
    local sp = state.smoothPlayer
    local lp = state.lastPlayer

    local tx, ty, tz, th = lp.x, lp.y, lp.z, lp.heading
    local okP, vX, vY, vZ, vH = pcall(function()
        local me = mq.TLO.Me
        return me.X(), me.Y(), me.Z(), me.Heading.Degrees()
    end)
    if okP then
        if vX then tx = vX end
        if vY then ty = vY end
        if vZ then tz = vZ end
        if vH then th = vH end
    end

    if not sp.seeded then
        sp.x, sp.y, sp.z, sp.heading = tx, ty, tz, th
        sp.seeded = true
        return sp.x, sp.y, sp.z, sp.heading
    end

    local dx, dy = tx - sp.x, ty - sp.y
    if (dx * dx + dy * dy) > (PLAYER_SNAP_DIST * PLAYER_SNAP_DIST) then
        -- Zone / teleport: snap rather than glide across the whole map.
        sp.x, sp.y, sp.z, sp.heading = tx, ty, tz, th
        return sp.x, sp.y, sp.z, sp.heading
    end

    local a = smoothAlpha(dt, PLAYER_SMOOTH_TAU)
    sp.x = sp.x + dx * a
    sp.y = sp.y + dy * a
    sp.z = sp.z + (tz - sp.z) * a
    sp.heading = lerpHeading(sp.heading, th, a)
    return sp.x, sp.y, sp.z, sp.heading
end

-- Reads the per-spawn fields the map needs into a plain record. cleanName /
-- level / distance strings and the ImGui id suffixes are precomputed here so
-- the tracker table and canvas never string.format per row per frame.
local function buildMobRecord(s, id, dist)
    local ok, cleanName, level, classShort, conColor, sx, sy, sz, pctHPs, kos = pcall(function()
        return s.CleanName(), s.Level(), s.Class.ShortName(), s.ConColor(), s.X(), s.Y(), s.Z(), s.PctHPs(), s.Aggressive()
    end)
    if not ok then return nil end
    local losCacheEntry = state.losCache[id]
    local name = cleanName or 'Unknown NPC'
    local lvl = level or 0
    local idStr = tostring(id)
    return {
        id          = id,
        idStr       = idStr,
        pushId      = 'tm' .. idStr,
        cleanName   = name,
        nameLower   = name:lower(),
        rowLabel    = name .. '##TrackMob_' .. idStr,
        rowLabelSel = '> ' .. name .. '##TrackMob_' .. idStr,
        level       = lvl,
        levelStr    = tostring(lvl),
        class       = classShort or 'WAR',
        conColor    = string.upper(tostring(conColor or 'GREY')),
        distance    = dist,
        distStr     = string.format('%.1fy', dist),
        lineOfSight = (losCacheEntry and losCacheEntry.los) or false,
        x           = sx or 0,
        y           = sy or 0,
        z           = sz or 0,
        pctHPs      = pctHPs or 100,
        -- Spawn.Aggressive is the KOS flag (would attack on sight), NOT
        -- "currently has aggro on me"; the canvas ring and tooltip say so.
        isKos       = (kos == true),
    }
end

-- One-pass NPC fetch: every NPC spawn in one native call, deduped by spawn ID,
-- trimmed to the SCAN_MAX_NPCS nearest. Returns the record list and the total
-- NPC count in the zone.
local function fetchZoneNPCs()
    local list = nil
    if type(mq.getFilteredSpawns) == 'function' then
        local okList, res = pcall(mq.getFilteredSpawns, function(sp)
            return sp.Type() == 'NPC'
        end)
        if okList and type(res) == 'table' then list = res end
    end
    if not list then
        -- Fallback for hosts without getFilteredSpawns: still a single pass,
        -- so the ordering cannot shift between ticks.
        list = {}
        local okCount, count = pcall(function() return mq.TLO.SpawnCount('npc')() end)
        count = (okCount and tonumber(count)) or 0
        for i = 1, math.min(count, SCAN_MAX_NPCS) do
            local okS, sp = pcall(function() return mq.TLO.NearestSpawn(i, 'npc') end)
            if okS and sp and sp() then list[#list + 1] = sp end
        end
    end

    -- Cheap first pass (ID / distance / dead) so the field reads below only
    -- run for the NPCs we actually keep.
    local seen, cand = {}, {}
    for i = 1, #list do
        local sp = list[i]
        local okId, id, dist, dead = pcall(function() return sp.ID(), sp.Distance3D(), sp.Dead() end)
        if okId and id and id > 0 and not dead and not seen[id] then
            seen[id] = true
            cand[#cand + 1] = { s = sp, id = id, dist = dist or 99999 }
        end
    end
    if #cand > SCAN_MAX_NPCS then
        table.sort(cand, function(a, b) return a.dist < b.dist end)
        for i = #cand, SCAN_MAX_NPCS + 1, -1 do cand[i] = nil end
    end

    local out = {}
    for i = 1, #cand do
        local c = cand[i]
        local rec = buildMobRecord(c.s, c.id, c.dist)
        if rec then out[#out + 1] = rec end
    end
    return out, #list
end

-- Rolling Line-of-Sight refresh: walks spawns.allNPCs from the saved cursor,
-- re-raycasting at most `budget` stale entries (older than LOS_STALE_MS, or
-- all of them when forceAll). Runs every tick; never on the draw thread.
local function refreshLosChunk(budget, forceAll)
    local list = spawns.allNPCs
    local n = #list
    if n == 0 then return end
    local cs = state.scanChunk
    local now = mq.gettime()
    local spent, visited = 0, 0
    while spent < budget and visited < n do
        if cs.losIdx > n or cs.losIdx < 1 then cs.losIdx = 1 end
        local mob = list[cs.losIdx]
        cs.losIdx = cs.losIdx + 1
        visited = visited + 1
        local losE = state.losCache[mob.id]
        if forceAll or not losE or (now - losE.ts) > LOS_STALE_MS then
            local losVal = false
            local okSp, spawnObj = pcall(function() return mq.TLO.Spawn(mob.id) end)
            if okSp and spawnObj and spawnObj() then
                local okLos, los = pcall(function() return spawnObj.LineOfSight() end)
                losVal = (okLos and los) or false
            end
            state.losCache[mob.id] = { los = losVal, ts = now }
            mob.lineOfSight = losVal
            spent = spent + 1
        elseif losE then
            mob.lineOfSight = losE.los
        end
    end
end

-- Spawn scan cycle: refreshes nav/zone state, fetches every NPC in one pass,
-- then filters, sorts and snapshots the group. Runs on the engine tick only.
-- forceComplete (init / zone change) also runs a synchronous LoS burst so the
-- tracker has LoS data immediately.
local function scanZoneSpawns(forceComplete)
    navState.meshLoaded = navMeshLoaded()
    local okNavAct, isNavAct = pcall(function() return mq.TLO.Navigation.Active() end)
    navState.navActive = (okNavAct and isNavAct) or false

    local okZone, zoneName = pcall(function() return mq.TLO.Zone.Name() end)
    if okZone and zoneName then state.currentZoneName = zoneName end

    local nowTime = mq.gettime()

    local npcs, total = fetchZoneNPCs()
    spawns.allNPCs = npcs
    spawns.totalCount = total
    if #npcs == 0 then
        spawns.filteredNPCs = {}
        spawns.groupMembers = {}
        state.scanChunk.losIdx = 1
    end

    if forceComplete then
        state.scanChunk.losIdx = 1
        refreshLosChunk(SCAN_LOS_BUDGET, true)
    end

    -- Filtering, sorting and group snapshot (in-memory, cheap).
    local filtered = {}
    local searchLower = string.lower(state.searchText or '')
    local filterIdx = state.conFilterIndex
    local sf = state.smartFloor
    local applyZ = (cfg.zFilterMode ~= 3)
    local wantNavChecks = (state.viewMode ~= 'ATLAS')

    for _, mob in ipairs(npcs) do
        local keep = true
        if searchLower ~= '' then
            local nameMatch = mob.nameLower:find(searchLower, 1, true)
            local idMatch = mob.idStr:find(searchLower, 1, true)
            if not nameMatch and not idMatch then keep = false end
        end
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
        if keep and (mob.level < state.minLevel or mob.level > state.maxLevel) then keep = false end
        if keep and (mob.distance > state.maxDistance) then keep = false end
        if keep and state.losOnly and not mob.lineOfSight then keep = false end
        if keep and applyZ then
            if mob.z < sf.minZ or mob.z > sf.maxZ then keep = false end
        end

        local wantOnMap = keep
        if keep and state.pathableOnly then
            local c = navState.cache[mob.id]
            if not c or not c.hasPath then keep = false end
        end
        if keep then filtered[#filtered + 1] = mob end

        if wantOnMap and wantNavChecks then
            local cached = navState.cache[mob.id]
            if not cached or (nowTime - cached.checkedAt) > navState.cacheFreshMs then
                if not navState.queueSet[mob.id] then
                    navState.queueTail = navState.queueTail + 1
                    navState.checkQueue[navState.queueTail] = mob.id
                    navState.queueSet[mob.id] = true
                end
            end
        end
    end

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
            return a.nameLower < b.nameLower
        end
        return a.distance < b.distance
    end)
    spawns.filteredNPCs = filtered

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
-- Drops every queued-but-unprocessed path check and clears their queueSet
-- marks so the next scan can re-queue them (otherwise an ID stays marked as
-- queued forever and its tracker row is stuck on "[CHECKING]").
local function resetNavQueue()
    navState.checkQueue = {}
    navState.queueSet = {}
    navState.queueHead = 1
    navState.queueTail = 0
end

local function processNavBatch()
    if not navState.meshLoaded then return end
    if navState.queueHead > navState.queueTail then return end

    local now = mq.gettime()
    local count = 0
    local maxBatch = navState.batchSize
    local q = navState.checkQueue

    -- Entries are never nil'd: the head/tail pointers define the live window,
    -- so `#q` (undefined on tables with holes) is never consulted.
    while navState.queueHead <= navState.queueTail and count < maxBatch do
        local mobId = q[navState.queueHead]
        navState.queueHead = navState.queueHead + 1

        if mobId and mobId > 0 then
            navState.queueSet[mobId] = nil
            -- Only ask for path existence here; the expensive PathLength is
            -- resolved lazily on hover (see hover tooltip) and cached.
            local okPath, hasPath = pcall(function()
                return mq.TLO.Navigation.PathExists(string.format('id %d', mobId))()
            end)

            local cached = navState.cache[mobId]
            navState.cache[mobId] = {
                hasPath   = (okPath and hasPath) or false,
                length    = (cached and cached.length) or 0,
                lengthAt  = (cached and cached.lengthAt) or 0,
                checkedAt = now,
            }
            count = count + 1
        end
    end

    if navState.queueHead > navState.queueTail then
        -- Fully drained: every dequeued ID was processed, so nothing is left
        -- marked in queueSet.
        navState.checkQueue = {}
        navState.queueHead = 1
        navState.queueTail = 0
    elseif navState.queueHead > 128 then
        -- Compact the processed prefix away; the remaining IDs keep their
        -- queueSet marks because they are still queued.
        local compact = {}
        for i = navState.queueHead, navState.queueTail do
            compact[#compact + 1] = q[i]
        end
        navState.checkQueue = compact
        navState.queueHead = 1
        navState.queueTail = #compact
    end
end

-- Spawn IDs are reused per zone, so every per-ID cache and the active nav /
-- POI markers must be dropped when the character zones.
local function resetZoneRuntimeState()
    navState.cache = {}
    resetNavQueue()
    state.losCache = {}
    state.activeNavLoc = nil
    state.activeNavSpawnId = 0
    state.activeNavCommandTime = 0
    state.highlightedPoi = nil
    state.hoveredMobId = 0
    state.scanChunk.losIdx = 1
    spawns.allNPCs = {}
    spawns.filteredNPCs = {}
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

local triuneOverlaysErrorAt = 0

local function drawTriuneOverlays(drawList, cX, cY, availW, availH, playerX, playerY)
    local td = state.triuneData

    -- Draw Triune Patrol Waypoints & Connecting Paths
    if cfg.showWaypoints and td.waypoints and #td.waypoints > 0 then
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
                if cfg.showSearchRadius then
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
                    local wpPulse = math.sin(mq.gettime() * 0.005) * 2.0
                    drawList:AddCircle(ImVec2(wsx, wsy), 8.0 + wpPulse, ImGui.GetColorU32(1.0, 0.85, 0.15, 0.8), 0, 1.8)
                    drawList:AddCircleFilled(ImVec2(wsx, wsy), 5.5, ImGui.GetColorU32(1.0, 0.85, 0.15, 1.0), 0)
                else
                    drawList:AddCircleFilled(ImVec2(wsx, wsy), 4.5, ImGui.GetColorU32(0.15, 0.75, 0.90, 0.9), 0)
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
    if cfg.showCampRadius and td.campLoc and td.campLoc.x and td.campLoc.y then
        local csx, csy = worldToScreen(td.campLoc.x, td.campLoc.y, cX, cY, availW, availH)
        local campRadScreen = (td.campRadius or 50) * viewport.zoom

        if campRadScreen > 2.0 then
            drawList:AddCircleFilled(ImVec2(csx, csy), campRadScreen, ImGui.GetColorU32(0.10, 0.70, 0.85, 0.08), 0)
            drawList:AddCircle(ImVec2(csx, csy), campRadScreen, ImGui.GetColorU32(0.20, 0.85, 1.00, 0.60), 0, 1.8)

            -- Camp Anchor center pin
            drawList:AddCircleFilled(ImVec2(csx, csy), 5.0, ImGui.GetColorU32(0.20, 0.90, 1.00, 1.0), 0)
            drawList:AddCircle(ImVec2(csx, csy), 8.0, ImGui.GetColorU32(1.0, 1.0, 1.0, 0.8), 0, 1.5)

            local campText = string.format('Camp (Radius: %dyd)', td.campRadius or 50)
            drawList:AddText(ImVec2(csx + 10, csy - 8), ImGui.GetColorU32(0, 0, 0, 0.9), campText)
            drawList:AddText(ImVec2(csx + 9, csy - 9), ImGui.GetColorU32(0.3, 0.9, 1.0, 1.0), campText)
        end
    end

    -- Draw Hunter / Puller Combat Anchor (Roam Point)
    if cfg.showAnchor and td.hunterAnchor and td.hunterAnchor.x and td.hunterAnchor.y then
        local hax, hay = worldToScreen(td.hunterAnchor.x, td.hunterAnchor.y, cX, cY, availW, availH)
        local haRadScreen = (td.hunterCombatRadius or 250) * viewport.zoom

        if haRadScreen > 2.0 then
            drawList:AddCircleFilled(ImVec2(hax, hay), haRadScreen, ImGui.GetColorU32(0.85, 0.30, 0.90, 0.05), 0)
            drawList:AddCircle(ImVec2(hax, hay), haRadScreen, ImGui.GetColorU32(0.85, 0.40, 0.95, 0.55), 0, 1.4)
        end

        drawList:AddCircleFilled(ImVec2(hax, hay), 6.0, ImGui.GetColorU32(0.90, 0.35, 1.00, 1.0), 0)
        drawList:AddCircle(ImVec2(hax, hay), 9.0, ImGui.GetColorU32(1.0, 0.9, 1.0, 0.85), 0, 1.5)

        local haText = string.format('Anchor (Roam R: %dyd)', td.hunterCombatRadius or 250)
        drawList:AddText(ImVec2(hax + 10, hay - 8), ImGui.GetColorU32(0, 0, 0, 0.9), haText)
        drawList:AddText(ImVec2(hax + 9, hay - 9), ImGui.GetColorU32(0.9, 0.5, 1.0, 1.0), haText)
    end

    -- Draw Search / Pull / Roam Radius Circle (anchored at the player so it is
    -- always visible around the toon, independent of where camp/anchor sit)
    if cfg.showSearchRadius or cfg.showPullRadius then
        local anchorX, anchorY = playerX or 0, playerY or 0

        if anchorX and anchorY then
            local asx, asy = worldToScreen(anchorX, anchorY, cX, cY, availW, availH)
            local searchYards = td.hunterRadius or 1500
            local searchRadScreen = searchYards * viewport.zoom

            if searchRadScreen > 2.0 then
                -- Subtle amber fill + ring
                drawList:AddCircleFilled(ImVec2(asx, asy), searchRadScreen, ImGui.GetColorU32(1.00, 0.80, 0.20, 0.03), 0)
                drawList:AddCircle(ImVec2(asx, asy), searchRadScreen, ImGui.GetColorU32(1.00, 0.75, 0.20, 0.65), 0, 1.5)

                local labelText = string.format('Search / Pull / Roam Radius (%dyd)', searchYards)
                drawList:AddText(ImVec2(asx - 45, asy - searchRadScreen - 14), ImGui.GetColorU32(0, 0, 0, 0.95), labelText)
                drawList:AddText(ImVec2(asx - 46, asy - searchRadScreen - 15), ImGui.GetColorU32(1.0, 0.85, 0.3, 1.0), labelText)
            end
        end
    end

    -- Draw Triune Hazard Avoidance Hotspots (Stuck Memory)
    if cfg.showHazards and td.zoneHazards and #td.zoneHazards > 0 then
        for _, hz in ipairs(td.zoneHazards) do
            local hsx, hsy = worldToScreen(hz.x, hz.y, cX, cY, availW, availH)
            if hsx >= cX - 40 and hsx <= cX + availW + 40 and hsy >= cY - 40 and hsy <= cY + availH + 40 then
                local hzRadScreen = math.max(12.0 * viewport.zoom, 7.0)
                drawList:AddCircleFilled(ImVec2(hsx, hsy), hzRadScreen, ImGui.GetColorU32(0.95, 0.20, 0.20, 0.20), 0)
                drawList:AddCircle(ImVec2(hsx, hsy), hzRadScreen, ImGui.GetColorU32(0.95, 0.25, 0.25, 0.75), 0, 1.5)
                local hzText = string.format('Hazard (%d hits)', hz.hits or 1)
                drawList:AddText(ImVec2(hsx + 8, hsy - 6), ImGui.GetColorU32(0, 0, 0, 0.9), hzText)
                drawList:AddText(ImVec2(hsx + 7, hsy - 7), ImGui.GetColorU32(1.0, 0.4, 0.4, 0.9), hzText)
            end
        end
    end
end

-- ImVec2 reuse for the line walk: the MQ binding exposes ImVec2.x/y as
-- writable fields, so two scratch vectors can be reused for every segment
-- instead of allocating two userdata per visible line per frame. Probed once;
-- if the binding turns out to be immutable we fall back to allocation.
local imVec2Mutable = nil
local scratchA, scratchB = nil, nil

local function probeImVec2Mutable()
    if imVec2Mutable ~= nil then return imVec2Mutable end
    local ok = pcall(function()
        local v = ImVec2(1, 2)
        v.x = 3
        v.y = 4
        if v.x ~= 3 or v.y ~= 4 then error('immutable') end
    end)
    imVec2Mutable = ok and true or false
    if imVec2Mutable then
        scratchA = ImVec2(0, 0)
        scratchB = ImVec2(0, 0)
    end
    return imVec2Mutable
end

-- Con-color U32 cache for fully opaque nodes (alphaMult == 1): one
-- GetColorU32 marshal per con color for the life of the plugin instead of one
-- per visible NPC per frame.
local conColU32Cache = {}

local function getConColU32(conUpper)
    local col = conColU32Cache[conUpper]
    if col then return col end
    local st = getConStyle(conUpper)
    col = ImGui.GetColorU32(st.r, st.g, st.b, 1.0)
    conColU32Cache[conUpper] = col
    return col
end

local function DrawMapCanvas(availW, availH)
    local sf = state.smartFloor

    -- Enclose canvas in a dedicated child window to capture native ImGui mouse wheel scrolling
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0, 0, 0, 0)
    local canvasChildFlags = bit.bor(ImGuiWindowFlags.NoScrollbar or 0, ImGuiWindowFlags.NoMove or 0)
    local baseScroll = 500
    ImGui.SetNextWindowContentSize(availW, availH + (baseScroll * 2))
    local openChild = ImGui.BeginChild('##MapCanvasScrollRegion', ImVec2(availW, availH), false, canvasChildFlags)
    if not openChild then
        ImGui.EndChild()
        ImGui.PopStyleColor(1)
        ImGui.PopStyleVar(1)
        return
    end

    local currentScroll = ImGui.GetScrollY()
    if not state.mapCanvasInitScroll then
        ImGui.SetScrollY(baseScroll)
        state.mapCanvasInitScroll = true
        currentScroll = baseScroll
    end
    local scrollDelta = baseScroll - currentScroll
    ImGui.SetScrollY(baseScroll)

    local drawList = ImGui.GetWindowDrawList()
    local canvasPos = ImGui.GetWindowPosVec()
    local cX = canvasPos.x
    local cY = canvasPos.y

    -- Widget dimensions & hitbox exclusions
    local navW = (sf and sf.overrideOffset ~= 0) and 290 or 220
    local navH = 30
    local badgeX = cX + availW - navW - 10
    local badgeY = cY + 10

    local zoomBtnSize = 28
    local zoomPanelW = (state.viewMode == 'ATLAS') and 250 or 255
    local zoomPanelH = 72
    local zoomX = cX + availW - zoomPanelW - 10
    local zoomY = cY + availH - zoomPanelH - 10

    -- Invisible button to capture mouse inputs over canvas
    ImGui.SetCursorScreenPos(canvasPos)
    ImGui.InvisibleButton('##MapCanvasHitbox', availW, availH)
    local isItemHovered = ImGui.IsItemHovered()
    local isItemActive = ImGui.IsItemActive()

    -- Coordinate under cursor. Interaction (hit-testing, click-to-move,
    -- drag) is gated on the InvisibleButton's own hover so an overlapping
    -- window (tooltip, popup, another plugin window) blocks it; the raw
    -- rectangle test is only used for the mouse-wheel zoom.
    local mousePos = ImGui.GetMousePosVec()
    local isMouseOverCanvas = (mousePos.x >= cX and mousePos.x <= cX + availW and mousePos.y >= cY and mousePos.y <= cY + availH)
    local isHovered = isItemHovered

    if isHovered then
        state.cursorWorldX, state.cursorWorldY = screenToWorld(mousePos.x, mousePos.y, cX, cY, availW, availH)
    end

    local isOverFloorPill = (cfg.zFilterMode ~= 3 and mousePos.x >= badgeX - 4 and mousePos.x <= badgeX + navW + 4 and mousePos.y >= badgeY - 4 and mousePos.y <= badgeY + navH + 4)
    local isOverZoomWidget = (mousePos.x >= zoomX - 6 and mousePos.x <= zoomX + zoomPanelW + 6 and mousePos.y >= zoomY - 6 and mousePos.y <= zoomY + zoomPanelH + 6)

    -- Safe IO check for KeyCtrl (named imIO so the io library is not shadowed)
    local hasCtrl = false
    local okIO, imIO = pcall(ImGui.GetIO)
    if okIO and imIO then
        pcall(function() if imIO.KeyCtrl then hasCtrl = true end end)
    end

    -- Handle Drag Panning (Only on held down left click, ignored when clicking overlay widgets)
    if isHovered and not isOverFloorPill and not isOverZoomWidget then
        if isItemActive and ImGui.IsMouseDown(0) and not hasCtrl then
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
        if ImGui.IsMouseDown(0) then
            local dx = mousePos.x - viewport.dragStartMouseX
            local dy = mousePos.y - viewport.dragStartMouseY
            local z = math.max(viewport.zoom, 0.001)
            viewport.centerEqX = viewport.dragStartCenterEqX + (dx / z)
            viewport.centerEqY = viewport.dragStartCenterEqY + (dy / z)
            cfg.followPlayer = false -- Temporarily suspend follow-player while manually panning
        else
            viewport.isDragging = false
        end
    end

    -- Handle Mouse Wheel Zoom (Centering zoom on mouse cursor)
    if isMouseOverCanvas and scrollDelta ~= 0 and not isOverFloorPill and not isOverZoomWidget then
        local oldZoom = viewport.zoom
        local factor = (scrollDelta > 0) and 1.20 or 0.80
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
    drawList:AddRectFilled(canvasPos, ImVec2(cX + availW, cY + availH), bgCol, 0.0)

    -- Draw Grid Lines (if enabled)
    if cfg.showGrid then
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
            if sy >= cY and sy <= cY + availH then
                drawList:AddLine(ImVec2(cX, sy), ImVec2(cX + availW, sy), gridCol, 1.0)
                drawList:AddText(ImVec2(cX + 3, sy + 3), textCol, string.format('Y:%d', gy))
            end
        end
    end

    -- Player position for Z-filtering, Smart Auto-Z, camera follow & the player
    -- marker. Sampled live every frame and smoothed with the frame delta so the
    -- marker and camera-pan move at render rate; the per-tick cache is only the
    -- fallback inside samplePlayerSmoothed when a live read fails.
    local frameDt = 1 / 60
    if okIO and imIO then
        pcall(function()
            local d = imIO.DeltaTime
            if d and d > 0 and d < 0.5 then frameDt = d end
        end)
    end
    local playerX, playerY, playerZ, playerHeading = samplePlayerSmoothed(frameDt)

    -- Smart floor bounds are recomputed on the engine tick (histogram pass
    -- over the map geometry); the draw thread only reads the result.
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
        [0] = cfg.layer0,
        [1] = cfg.layer1,
        [2] = cfg.layer2,
        [3] = cfg.layer3,
    }

    local lineThick = cfg.lineThickness
    local sfMinZ, sfMaxZ = sf.minZ, sf.maxZ
    local zFading = cfg.zDepthFading
    local zFilterMode = cfg.zFilterMode
    local zoomNow = viewport.zoom
    -- Segments shorter than one screen pixel at this zoom are invisible
    -- anyway; skipping them is the bulk of the saving when zoomed out.
    local minLenWorld = 1.0 / math.max(0.0001, zoomNow)
    local reuseVec = probeImVec2Mutable()
    local pA, pB = scratchA, scratchB

    -- Screen transform inlined for the hot loop (same math as worldToScreen).
    local originSX = cX + availW * 0.5 + viewport.centerEqX * zoomNow
    local originSY = cY + availH * 0.5 + viewport.centerEqY * zoomNow

    local function drawSegment(seg)
        if seg.len < minLenWorld then return end
        local alphaMult, isVis = 1.0, true
        if zFilterMode ~= 3 then
            alphaMult, isVis = getZAlphaMultiplier(seg.avgZ, sfMinZ, sfMaxZ, zFilterMode, zFading)
        end
        if not isVis or alphaMult <= 0.01 then return end

        local sx1 = originSX - seg.x1 * zoomNow
        local sy1 = originSY - seg.y1 * zoomNow
        local sx2 = originSX - seg.x2 * zoomNow
        local sy2 = originSY - seg.y2 * zoomNow
        local col
        if alphaMult >= 0.999 then
            -- Lazily precompute the opaque color once per segment, then
            -- cache it so steady-state frames skip the GetColorU32 marshal.
            if not seg.colBase then seg.colBase = ImGui.GetColorU32(seg.r, seg.g, seg.b, 1.0) end
            col = seg.colBase
        else
            col = ImGui.GetColorU32(seg.r, seg.g, seg.b, alphaMult)
        end
        if reuseVec then
            pA.x = sx1; pA.y = sy1
            pB.x = sx2; pB.y = sy2
            drawList:AddLine(pA, pB, col, lineThick)
        else
            drawList:AddLine(ImVec2(sx1, sy1), ImVec2(sx2, sy2), col, lineThick)
        end
    end

    local grid = mapData.grid
    if grid and grid.cell then
        -- Walk only the bucket cells overlapping the viewport. A segment that
        -- spans several cells is drawn from the first visible cell it touches
        -- (max of its min cell and the visible min cell) so it is emitted
        -- exactly once per frame.
        local inv = 1 / grid.cell
        local vcx0 = math.floor(vpMinX * inv)
        local vcx1 = math.floor(vpMaxX * inv)
        local vcy0 = math.floor(vpMinY * inv)
        local vcy1 = math.floor(vpMaxY * inv)
        for lId = 0, 3 do
            local layerGrid = layerEnabled[lId] and grid.layers[lId]
            if layerGrid and layerGrid.count > 0 then
                local cells = layerGrid.cells
                local cy0 = math.max(vcy0, layerGrid.minCY)
                local cy1 = math.min(vcy1, layerGrid.maxCY)
                local cx0 = math.max(vcx0, layerGrid.minCX)
                local cx1 = math.min(vcx1, layerGrid.maxCX)
                for cy = cy0, cy1 do
                    local row = cells[cy]
                    if row then
                        for cx = cx0, cx1 do
                            local bucket = row[cx]
                            if bucket then
                                for i = 1, #bucket do
                                    local seg = bucket[i]
                                    local ownX = seg.cx0 > vcx0 and seg.cx0 or vcx0
                                    local ownY = seg.cy0 > vcy0 and seg.cy0 or vcy0
                                    if ownX == cx and ownY == cy
                                        and seg.maxX >= vpMinX and seg.minX <= vpMaxX
                                        and seg.maxY >= vpMinY and seg.minY <= vpMaxY then
                                        drawSegment(seg)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        -- No buckets (map loaded without the grid): linear AABB walk.
        for lId = 0, 3 do
            if layerEnabled[lId] then
                local lines = mapData.layers[lId] or {}
                for i = 1, #lines do
                    local seg = lines[i]
                    if seg.maxX >= vpMinX and seg.minX <= vpMaxX and seg.maxY >= vpMinY and seg.minY <= vpMaxY then
                        drawSegment(seg)
                    end
                end
            end
        end
    end

    -- Draw Map Labels
    if cfg.showLabels and cfg.layerLabels then
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
                    local col
                    if alphaMult >= 0.999 then
                        if not lb.colBase90 then lb.colBase90 = ImGui.GetColorU32(lb.r, lb.g, lb.b, 0.90) end
                        col = lb.colBase90
                    else
                        col = ImGui.GetColorU32(lb.r, lb.g, lb.b, 0.90 * alphaMult)
                    end
                    drawList:AddText(ImVec2(sx, sy), col, lb.text)
                end
            end
        end
    end

    -- Draw Triune Overlays (Waypoints, Camp/Pull/Anchor radii, Hazards) guarded
    -- so a single bad overlay datum can never abort the rest of the canvas frame.
    local okTriuneOv, triuneOvErr = pcall(drawTriuneOverlays, drawList, cX, cY, availW, availH, playerX, playerY)
    if not okTriuneOv and triuneOvErr then
        local nowTriEr = mq.gettime()
        if (nowTriEr - triuneOverlaysErrorAt) >= 5000 then
            triuneOverlaysErrorAt = nowTriEr
            print('\ar[Triune Map]\ax Overlay draw error: ' .. tostring(triuneOvErr))
        end
    end

    -- Draw Highlighted POI Marker (if active)
    local poi = state.highlightedPoi
    if poi ~= nil then
        local pTime = (poi.time ~= nil and poi.time) or 0
        local px    = (poi.x ~= nil and poi.x) or 0
        local py    = (poi.y ~= nil and poi.y) or 0
        local pText = (poi.text ~= nil and poi.text) or 'Point of Interest'
local now = mq.gettime()

        if (now - pTime) < 20000 then
            local psx, psy = worldToScreen(px, py, cX, cY, availW, availH)
            if psx >= cX - 50 and psx <= cX + availW + 50 and psy >= cY - 50 and psy <= cY + availH + 50 then
                local pulse = math.sin((now - pTime) * 0.008) * 5.0
                local rRad = math.max(10.0, 16.0 + pulse)
                drawList:AddCircle(ImVec2(psx, psy), rRad, ImGui.GetColorU32(1.0, 0.85, 0.2, 0.9), 0, 2.5)
                drawList:AddCircleFilled(ImVec2(psx, psy), 5.0, ImGui.GetColorU32(1.0, 0.85, 0.2, 1.0), 0)
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
        if cfg.showGroup then
            local grpCol = ImGui.GetColorU32(0.20, 0.90, 0.80, 1.0)
            for _, gm in ipairs(spawns.groupMembers) do
                local sx, sy = worldToScreen(gm.x, gm.y, cX, cY, availW, availH)
                if sx >= cX and sx <= cX + availW and sy >= cY and sy <= cY + availH then
                    drawList:AddCircleFilled(ImVec2(sx, sy), 4.5, grpCol, 0)
                    drawList:AddText(ImVec2(sx + 6, sy - 6), grpCol, gm.name)
                end
            end
        end

        -- Current Target ID (from per-tick cache)
        local targetId = state.lastTargetId
        if targetId == 0 then
            local okTarg, tId = pcall(function() return mq.TLO.Target.ID() end)
            if okTarg and tId then targetId = tId end
        end

        -- Draw NPCs and Process Click Hit-Testing
        local clickedMob = nil
        local doubleClickedMob = nil

        if cfg.showNPCs then
            -- Constant colors hoisted out of the per-NPC loop; the opaque
            -- (alphaMult == 1) con / nav colors come from small caches.
            local meshUp = navState.meshLoaded
            local colorMode = cfg.colorModeIndex
            local nodeRadius = cfg.npcNodeRadius
            local ringBlack = ImGui.GetColorU32(0, 0, 0, 0.8)
            local targetRingCol = ImGui.GetColorU32(1.0, 0.85, 0.20, 1.0)
            local kosRingCol = ImGui.GetColorU32(1.0, 0.1, 0.1, 0.9)
            local hoverRingCol = ImGui.GetColorU32(1, 1, 1, 0.9)
            local navGreen = ImGui.GetColorU32(0.15, 0.95, 0.35, 1.0)
            local navRed = ImGui.GetColorU32(0.95, 0.20, 0.20, 1.0)
            local navGrey = ImGui.GetColorU32(0.6, 0.6, 0.6, 0.8)
            local hitRadius = nodeRadius + 4.0
            local hitRadiusSq = hitRadius * hitRadius
            local showNames = cfg.showNPCNames

            for _, mob in ipairs(spawns.filteredNPCs) do
                local alphaMult, isVis = getZAlphaMultiplier(mob.z, sf.minZ, sf.maxZ)

                if isVis and alphaMult > 0.01 then
                    local sx, sy = worldToScreen(mob.x, mob.y, cX, cY, availW, availH)

                    if sx >= cX - 10 and sx <= cX + availW + 10 and sy >= cY - 10 and sy <= cY + availH + 10 then
                        -- Determine Colors
                        local opaque = (alphaMult >= 0.999)
                        local conColU32
                        if opaque then
                            conColU32 = getConColU32(mob.conColor)
                        else
                            local conStyle = getConStyle(mob.conColor)
                            conColU32 = ImGui.GetColorU32(conStyle.r, conStyle.g, conStyle.b, alphaMult)
                        end

                        local cNav = navState.cache[mob.id]
                        local isPathable = cNav and cNav.hasPath
                        local navColU32
                        if not meshUp then
                            navColU32 = opaque and navGrey or ImGui.GetColorU32(0.6, 0.6, 0.6, 0.8 * alphaMult)
                        elseif isPathable then
                            navColU32 = opaque and navGreen or ImGui.GetColorU32(0.15, 0.95, 0.35, alphaMult)
                        else
                            navColU32 = opaque and navRed or ImGui.GetColorU32(0.95, 0.20, 0.20, alphaMult)
                        end

                        local isTarget = (mob.id == targetId)

                        -- Draw Node by Color Mode
                        if colorMode == 1 then
                            -- Dual Mode: Con fill with Nav halo
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, conColU32, 0)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.5, navColU32, 0, 1.5)
                        elseif colorMode == 2 then
                            -- Navmesh Reachability Only
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, navColU32, 0)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.0, ringBlack, 0, 1.0)
                        else
                            -- Con Colors Only
                            drawList:AddCircleFilled(ImVec2(sx, sy), nodeRadius, conColU32, 0)
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 1.0, ringBlack, 0, 1.0)
                        end

                        -- Target Highlight Ring
                        if isTarget then
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 4.0, targetRingCol, 0, 2.0)
                        end

                        -- Aggressive (KOS) Indicator: Spawn.Aggressive is the
                        -- "will attack on sight" flag, not live hate on us.
                        if mob.isKos then
                            drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 6.0, kosRingCol, 0, 1.5)
                        end

                        -- Optional Name Tag on Map
                        if showNames then
                            drawList:AddText(ImVec2(sx + 6, sy - 6), conColU32, mob.cleanName)
                        end

                        -- Hit Testing
                        if isHovered then
                            local mdx, mdy = mousePos.x - sx, mousePos.y - sy
                            if (mdx * mdx + mdy * mdy) <= hitRadiusSq then
                                hoveredMob = mob
                                drawList:AddCircle(ImVec2(sx, sy), nodeRadius + 5.0, hoverRingCol, 0, 2.0)

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
        if isHovered and not hoveredMob and not isOverFloorPill and not isOverZoomWidget then
            if ImGui.IsMouseDoubleClicked(0) or (ImGui.IsMouseClicked(0) and hasCtrl) then
                local clickX, clickY = screenToWorld(mousePos.x, mousePos.y, cX, cY, availW, availH)
                actionQueue.pendingNavLoc = { y = clickY, x = clickX, z = playerZ }
                state.activeNavLoc = { y = clickY, x = clickX, z = playerZ }
                state.activeNavSpawnId = 0
                state.activeNavCommandTime = mq.gettime()
                state.statusMsg = string.format('Navigating to ground loc: Y:%.1f, X:%.1f, Z:%.1f', clickY, clickX, playerZ)
            end
        end

        -- Query Real-Time Navigation Status (cached from scan)
        local isNavActive = navState.navActive and navState.meshLoaded or false

        -- Draw Active Destination / Waypoint Marker & Path Line
        local navRecentlyTriggered = state.activeNavCommandTime and ((mq.gettime() - state.activeNavCommandTime) < 5000)
        local hasPendingNav = (actionQueue.pendingNavLoc ~= nil) or (actionQueue.pendingNavId > 0)
        local shouldDrawNav = cfg.showNavLine and (isNavActive or navRecentlyTriggered or hasPendingNav or state.activeNavLoc ~= nil or (state.activeNavSpawnId and state.activeNavSpawnId > 0))

        if shouldDrawNav then
            local meX, meY = playerX, playerY
            if state.smoothPlayer.seeded then
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
                        local pulse = math.sin(mq.gettime() * 0.005) * 2.0
                        drawList:AddCircle(ImVec2(dSx, dSy), 11.0 + pulse, ImGui.GetColorU32(1.0, 0.85, 0.15, 0.6), 0, 2.0)
                        drawList:AddCircleFilled(ImVec2(dSx, dSy), 5.0, ImGui.GetColorU32(1.0, 0.85, 0.15, 1.0), 0)
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
        local meX, meY = playerX, playerY
        local meHeading = playerHeading

        if state.smoothPlayer.seeded then
            local psx, psy = worldToScreen(meX, meY, cX, cY, availW, availH)

            -- Auto-follow player
            if cfg.followPlayer and not viewport.isDragging then
                viewport.centerEqX = meX
                viewport.centerEqY = meY
            end

            -- Calculate Heading Triangle
            local heading = meHeading or 0
            local rad = math.rad(heading)
            local arrowLen = cfg.playerNodeRadius + 7.0
            local baseLen = cfg.playerNodeRadius + 2.0
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
            drawList:AddCircleFilled(ImVec2(psx, psy), 3.5, ImGui.GetColorU32(1.0, 1.0, 1.0, 1.0), 0)
            drawList:AddCircle(ImVec2(psx, psy), 3.5, ImGui.GetColorU32(0.0, 0.0, 0.0, 0.9), 0, 1.0)
        end
    end

    -- Pop Clipping Rectangle
    drawList:PopClipRect()

    -- On-Canvas Floor Navigation Widget (Top Right Pill)
    if cfg.zFilterMode ~= 3 then
        ImGui.SetCursorScreenPos(ImVec2(badgeX, badgeY))
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.04, 0.07, 0.12, 0.90)
        ImGui.PushStyleColor(ImGuiCol.Border, 0.20, 0.40, 0.60, 0.80)
        ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4.0)
        ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 3)
        local floorNavFlags = bit.bor(ImGuiWindowFlags.NoScrollbar or 0, ImGuiWindowFlags.NoScrollWithMouse or 0)
        if ImGui.BeginChild('##FloorNavOverlayChild', ImVec2(navW, navH), true, floorNavFlags) then
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

    -- On-Canvas Floating Control Widget (Bottom-Right)
    ImGui.SetCursorScreenPos(ImVec2(zoomX, zoomY))
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.04, 0.07, 0.12, 0.90)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.20, 0.40, 0.60, 0.80)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 4.0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    local overlayFlags = bit.bor(ImGuiWindowFlags.NoScrollbar or 0, ImGuiWindowFlags.NoScrollWithMouse or 0)
    if ImGui.BeginChild('##MapControlOverlayChild', ImVec2(zoomPanelW, zoomPanelH), true, overlayFlags) then
        if state.viewMode == 'LIVE' then
            -- Row 1: Zoom In, Zoom Out, Reset, Auto-Z, Follow Checkbox
            if ImGui.Button('+##CanvasZoomIn', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.zoom = math.min(viewport.maxZoom, viewport.zoom * 1.25)
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom In (+25%)\n(Or roll Mouse Wheel Up)') end

            ImGui.SameLine()
            if ImGui.Button('-##CanvasZoomOut', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.zoom = math.max(viewport.minZoom, viewport.zoom * 0.80)
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom Out (-20%)\n(Or roll Mouse Wheel Down)') end

            ImGui.SameLine()
            if ImGui.Button('⟲##CanvasZoomReset', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.zoom = 1.0
                local okX, meX = pcall(function() return mq.TLO.Me.X() end)
                local okY, meY = pcall(function() return mq.TLO.Me.Y() end)
                if okX and okY and meX and meY then
                    viewport.centerEqX = meX
                    viewport.centerEqY = meY
                    cfg.followPlayer = true
                end
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Reset Zoom & Center on Player') end

            ImGui.SameLine()
            local isAutoZ = (cfg.zFilterMode ~= 3)
            if isAutoZ then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.25, 0.95, 0.40, 1.0)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.12, 0.32, 0.22, 0.85)
            else
                ImGui.PushStyleColor(ImGuiCol.Text, 0.60, 0.60, 0.65, 0.70)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.18, 0.18, 0.22, 0.70)
            end
            if ImGui.Button('AZ##CanvasToggleAutoZ', ImVec2(zoomBtnSize, zoomBtnSize)) then
                if cfg.zFilterMode == 3 then
                    cfg.zFilterMode = 1
                else
                    cfg.zFilterMode = 3
                end
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            ImGui.PopStyleColor(2)
            if ImGui.IsItemHovered() then
                local modeDesc = (cfg.zFilterMode == 1 and 'Auto-Z (Smart Floor Isolation: ON)')
                    or (cfg.zFilterMode == 2 and 'Manual Z-Window: ON')
                    or 'Disabled (Show All Elevations)'
                ImGui.SetTooltip('%s', string.format('Auto-Z Floor Filtering: %s\nMode: %s\n[Click] %s',
                    (cfg.zFilterMode ~= 3 and 'ON' or 'OFF'),
                    modeDesc,
                    (cfg.zFilterMode ~= 3 and 'Turn Auto-Z OFF (Show All Elevations)' or 'Turn Auto-Z ON (Smart Floor Isolation)')
                ))
            end

            ImGui.SameLine()
            local fp, cfp = ImGui.Checkbox('Follow##CanvasFollowCheck', cfg.followPlayer)
            if cfp then cfg.followPlayer = fp end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Auto-follow player location while moving') end

            -- Row 2: Center Me, POIs Drawer, Stop Nav
            if ImGui.Button('Center Me##CanvasCenterMe', ImVec2(80, 26)) then
                local okX, meX = pcall(function() return mq.TLO.Me.X() end)
                local okY, meY = pcall(function() return mq.TLO.Me.Y() end)
                if okX and okY and meX and meY then
                    viewport.centerEqX = meX
                    viewport.centerEqY = meY
                    cfg.followPlayer = true
                end
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Center map on player location and enable follow') end

            ImGui.SameLine()
            local poiBtnText = state.showPoiDrawer and 'POIs [ON]##CanvasTogglePoi' or 'POIs##CanvasTogglePoi'
            local isPoiOpen = state.showPoiDrawer
            if isPoiOpen then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.15, 0.35, 0.50, 0.90)
            end
            if ImGui.Button(poiBtnText, ImVec2(72, 26)) then
                state.showPoiDrawer = not state.showPoiDrawer
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if isPoiOpen then ImGui.PopStyleColor(1) end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Toggle side drawer for Points of Interest & Map Labels') end

            ImGui.SameLine()
            local isNavActive = (state.activeNavLoc ~= nil) or (state.activeNavSpawnId and state.activeNavSpawnId > 0)
            if isNavActive then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.55, 0.15, 0.15, 0.90)
            end
            if ImGui.Button('Stop Nav##CanvasStopNav', ImVec2(80, 26)) then
                actionQueue.pendingStopNav = true
                state.activeNavLoc = nil
                state.activeNavSpawnId = 0
                state.activeNavCommandTime = 0
                state.statusMsg = 'Navigation stopped.'
            end
            if isNavActive then ImGui.PopStyleColor(1) end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Halt active navigation and stick routing') end

        else
            -- ATLAS MODE
            -- Row 1: Zoom In, Zoom Out, Reset, Auto-Z, History Back, History Forward
            if ImGui.Button('+##CanvasZoomIn', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.zoom = math.min(viewport.maxZoom, viewport.zoom * 1.25)
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom In (+25%)\n(Or roll Mouse Wheel Up)') end

            ImGui.SameLine()
            if ImGui.Button('-##CanvasZoomOut', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.zoom = math.max(viewport.minZoom, viewport.zoom * 0.80)
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Zoom Out (-20%)\n(Or roll Mouse Wheel Down)') end

            ImGui.SameLine()
            if ImGui.Button('⟲##CanvasZoomReset', ImVec2(zoomBtnSize, zoomBtnSize)) then
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
                local spanX = math.abs(mapData.bounds.maxX - mapData.bounds.minX)
                local spanY = math.abs(mapData.bounds.maxY - mapData.bounds.minY)
                local maxSpan = math.max(spanX, spanY)
                if maxSpan > 50 then
                    viewport.zoom = math.max(viewport.minZoom, math.min(1.2, 700 / maxSpan))
                end
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Reset View & Zoom to Full Zone Bounds') end

            ImGui.SameLine()
            local isAutoZ = (cfg.zFilterMode ~= 3)
            if isAutoZ then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.25, 0.95, 0.40, 1.0)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.12, 0.32, 0.22, 0.85)
            else
                ImGui.PushStyleColor(ImGuiCol.Text, 0.60, 0.60, 0.65, 0.70)
                ImGui.PushStyleColor(ImGuiCol.Button, 0.18, 0.18, 0.22, 0.70)
            end
            if ImGui.Button('AZ##CanvasToggleAutoZ', ImVec2(zoomBtnSize, zoomBtnSize)) then
                if cfg.zFilterMode == 3 then
                    cfg.zFilterMode = 1
                else
                    cfg.zFilterMode = 3
                end
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            ImGui.PopStyleColor(2)
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Toggle Auto-Z Floor Filtering') end

            ImGui.SameLine()
            local canBack = (state.atlasHistoryIdx > 1)
            if not canBack then ImGui.BeginDisabled() end
            if ImGui.Button('<##CanvasAtlasBack', ImVec2(zoomBtnSize, zoomBtnSize)) then
                atlasHistoryBack()
            end
            if not canBack then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Previous zone in Atlas history') end

            ImGui.SameLine()
            local canFwd = (state.atlasHistoryIdx < #state.atlasHistory)
            if not canFwd then ImGui.BeginDisabled() end
            if ImGui.Button('>##CanvasAtlasFwd', ImVec2(zoomBtnSize, zoomBtnSize)) then
                atlasHistoryForward()
            end
            if not canFwd then ImGui.EndDisabled() end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Next zone in Atlas history') end

            -- Row 2: Center Map, POIs Drawer, Live Zone
            if ImGui.Button('Center Map##CanvasCenterAtlas', ImVec2(80, 26)) then
                viewport.centerEqX = (mapData.bounds.minX + mapData.bounds.maxX) * 0.5
                viewport.centerEqY = (mapData.bounds.minY + mapData.bounds.maxY) * 0.5
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Center map on full zone bounds') end

            ImGui.SameLine()
            local poiBtnText = state.showPoiDrawer and 'POIs [ON]##CanvasTogglePoi' or 'POIs##CanvasTogglePoi'
            local isPoiOpen = state.showPoiDrawer
            if isPoiOpen then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.15, 0.35, 0.50, 0.90)
            end
            if ImGui.Button(poiBtnText, ImVec2(72, 26)) then
                state.showPoiDrawer = not state.showPoiDrawer
                state.dirtySettings = true
                state.dirtySettingsTime = mq.gettime()
            end
            if isPoiOpen then ImGui.PopStyleColor(1) end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Toggle side drawer for Points of Interest & Map Labels') end

            ImGui.SameLine()
            if ImGui.Button('Live Zone##CanvasReturnLive', ImVec2(80, 26)) then
                returnToLiveZone()
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Return to active zone and resume live player tracking') end
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)
    ImGui.PopStyleColor(2)



    -- Hover Tooltip for NPC
    if hoveredMob then
        local hid = hoveredMob.id
        local cNav = navState.cache[hid]
        local pathStr = 'Unchecked'
        if not navState.meshLoaded then
            pathStr = 'Mesh Not Loaded'
        elseif cNav then
            -- Resolve the (expensive) exact path length on demand for the
            -- hovered mob only, and only when a path exists, throttled to
            -- ~1 refresh/sec on its own timestamp. checkedAt belongs to the
            -- PathExists verification and is left alone so re-checks are
            -- not suppressed by hovering.
            if cNav.hasPath then
                local nowT = mq.gettime()
                if cNav.length == 0 or (nowT - (cNav.lengthAt or 0)) > 1000 then
                    local okLen, pathLen = pcall(function()
                        return mq.TLO.Navigation.PathLength(string.format('id %d', hid))()
                    end)
                    if okLen and pathLen then
                        cNav.length = pathLen
                    end
                    cNav.lengthAt = nowT
                end
                pathStr = string.format('Valid Path (%.1f yds)', cNav.length or 0)
            else
                pathStr = 'NO PATH (Unreachable)'
            end
        end

        -- Lazily refresh hovered mob's LoS so the tooltip stays accurate
        local hoverLos = hoveredMob.lineOfSight
        local hoverLosE = state.losCache[hid]
        local loom = mq.gettime()
        if not hoverLosE or (loom - hoverLosE.ts) > 5000 then
            local losVal = false
            local okSp, spawnObj = pcall(function() return mq.TLO.Spawn(hid) end)
            if okSp and spawnObj and spawnObj() then
                local okLos, los = pcall(function() return spawnObj.LineOfSight() end)
                losVal = (okLos and los) or false
            end
            state.losCache[hid] = { los = losVal, ts = loom }
            hoverLos = losVal
        end

        local tt = string.format(
            'Name: %s\n' ..
            'Level: %d  |  Class: %s  |  Con: %s\n' ..
            'Distance: %.1f yds  |  LoS: %s  |  Z-Diff: %.1f yds\n' ..
            'HP: %d%%  |  Aggressive (KOS): %s\n' ..
            'Navmesh Status: %s\n\n' ..
            '[Left-Click] Target  |  [Double-Click] Navigate',
            hoveredMob.cleanName,
            hoveredMob.level,
            hoveredMob.class,
            hoveredMob.conColor,
            hoveredMob.distance,
            hoverLos and 'YES' or 'NO',
            math.abs(hoveredMob.z - playerZ),
            hoveredMob.pctHPs,
            hoveredMob.isKos and 'YES' or 'NO',
            pathStr
        )
        ImGui.SetTooltip('%s', tt)
    end

    ImGui.EndChild()
    ImGui.PopStyleColor(1)
    ImGui.PopStyleVar(1)
end

-- ============================================================================
-- POI SIDE DRAWER (Map Canvas Overlay)
-- ============================================================================
-- Returns the labels matching the POI search text. The filtered list is
-- rebuilt only when the (trimmed, lowercased) query or the loaded label set
-- changes; per-frame callers get the cached table back.
local function getPoiMatches()
    local labels = mapData.labels or {}
    local q = (state.poiSearchText or ''):lower():match('^%s*(.-)%s*$')
    local pc = state.poiMatchCache
    if pc.q == q and pc.labels == labels then
        return pc.list, labels
    end
    local matching = {}
    if q == '' then
        for i = 1, #labels do matching[i] = labels[i] end
    else
        for i = 1, #labels do
            local lb = labels[i]
            local tl = lb.textLower
            if not tl then tl = lb.text:lower(); lb.textLower = tl end
            if tl:find(q, 1, true) ~= nil then
                matching[#matching + 1] = lb
            end
        end
    end
    pc.q = q
    pc.labels = labels
    pc.list = matching
    return matching, labels
end

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

        -- Filter POIs from mapData.labels (cached; see getPoiMatches)
        local matching, labels = getPoiMatches()

        ImGui.TextColored(0.65, 0.72, 0.82, 0.8, string.format('Matches: %d of %d labels', #matching, #labels))

        local listH = availH - 72
        if ImGui.BeginChild('##PoiListScroll', ImVec2(0, listH), true) then
            if #matching == 0 then
                ImGui.TextColored(0.6, 0.6, 0.6, 0.8, 'No points of interest match.')
            else
                local tableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0, ImGuiTableFlags.ScrollY or 0)
                if ImGui.BeginTable('##PoiDrawerTable', 3, tableFlags) then
                    ImGui.TableSetupColumn('Landmark / Label', ImGuiTableColumnFlags.WidthStretch or 0)
                    ImGui.TableSetupColumn('Location (Y, X)', ImGuiTableColumnFlags.WidthFixed or 0, core.px(125))
                    ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed or 0, core.px(56))
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
    -- Lowercased once per frame; zone entries carry their own shortLower.
    local curShortLower = (state.currentZoneShort or ''):lower()
    local atlasShortLower = (state.atlasZoneShort or ''):lower()
    local loadedShortLower = (mapData.zoneShort or ''):lower()

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
                ImGui.TableSetupColumn('Era / Type', ImGuiTableColumnFlags.WidthFixed or 0, core.px(100))
                ImGui.TableSetupColumn('Map', ImGuiTableColumnFlags.WidthFixed or 0, core.px(42))
                ImGui.TableHeadersRow()

                for _, z in ipairs(state.atlasZoneList) do
                    ImGui.TableNextRow()
                    local isSelected = (state.atlasSelectedZone and state.atlasSelectedZone.short == z.short)
                    local isCurrent = (curShortLower == z.shortLower)

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
            if not z.shortLower then decorateAtlasEntry(z) end
            local isCurrent = (curShortLower == z.shortLower)
            local isViewedInAtlas = (state.viewMode == 'ATLAS' and atlasShortLower == z.shortLower)

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

            local curShort = curShortLower:match('^%s*(.-)%s*$')
            local targetShort = z.shortLower:match('^%s*(.-)%s*$')

            if curShort == '' or curShort == 'unknown' then
                ImGui.TextColored(0.7, 0.7, 0.7, 0.8, 'Current zone not detected in game.')
            elseif curShort == targetShort then
                ImGui.TextColored(0.2, 0.95, 0.4, 1.0, string.format('✓ You are already in this zone (%s).', z.name))
            else
                local curZoneInfo = atlasZoneByShort(curShort)
                local curName = curZoneInfo and curZoneInfo.name or (state.currentZoneName ~= '' and state.currentZoneName) or curShort

                -- Cached on (curShort, targetShort); BFS only reruns on change.
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
                        ImGui.TableSetupColumn('Step', ImGuiTableColumnFlags.WidthFixed or 0, core.px(52))
                        ImGui.TableSetupColumn('Zone Name', ImGuiTableColumnFlags.WidthStretch or 0)
                        ImGui.TableSetupColumn('Era / Type', ImGuiTableColumnFlags.WidthFixed or 0, core.px(120))
                        ImGui.TableSetupColumn('Map View', ImGuiTableColumnFlags.WidthFixed or 0, core.px(65))
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
                                local az = atlasZoneByShort(stepZone.shortLower or stepZone.short:lower())
                                if az then state.atlasSelectedZone = az end
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

                local connLower = z.connLower or {}
                for idx, cShort in ipairs(conns) do
                    local cZone = atlasZoneByShort(connLower[idx] or cShort:lower())

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
            local currentViewingThis = (loadedShortLower == z.shortLower and mapData.isLoaded)

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

                local matching = getPoiMatches()

                if #matching > 0 then
                    local poiTableH = math.max(120, availH - 330)
                    if ImGui.BeginChild('##AtlasPoiSubScroll', ImVec2(0, poiTableH), true) then
                        local pTableFlags = bit.bor(ImGuiTableFlags.RowBg or 0, ImGuiTableFlags.BordersOuter or 0, ImGuiTableFlags.ScrollY or 0)
                        if ImGui.BeginTable('##AtlasPoiTable', 3, pTableFlags) then
                            ImGui.TableSetupColumn('Landmark / Label', ImGuiTableColumnFlags.WidthStretch or 0)
                            ImGui.TableSetupColumn('Location (Y, X, Z)', ImGuiTableColumnFlags.WidthFixed or 0, core.px(160))
                            ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed or 0, core.px(56))
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
    end
    ImGui.PopItemWidth()

    if state.searchText ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X##ClearSearchBtn') then
            state.searchText = ''
        end
    end

    ImGui.SameLine()
    ImGui.PushItemWidth(140)
    local conIdx, conChanged = ImGui.Combo('Con##TrackCon', state.conFilterIndex, CON_OPTIONS)
    if conChanged then
        state.conFilterIndex = conIdx
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    ImGui.PushItemWidth(140)
    local sortIdx, sortChanged = ImGui.Combo('Sort##TrackSort', state.sortIndex, SORT_OPTIONS)
    if sortChanged then
        state.sortIndex = sortIdx
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    local pathOnly, pathChanged = ImGui.Checkbox('Pathable Only##PathCheck', state.pathableOnly)
    if pathChanged then
        state.pathableOnly = pathOnly
    end

    ImGui.SameLine()
    local losOnly, losChanged = ImGui.Checkbox('LoS Only##LoSCheck', state.losOnly)
    if losChanged then
        state.losOnly = losOnly
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
        ImGui.TableSetupColumn('Lvl', ImGuiTableColumnFlags.WidthFixed, core.px(38))
        ImGui.TableSetupColumn('Con', ImGuiTableColumnFlags.WidthFixed, core.px(55))
        ImGui.TableSetupColumn('Dist', ImGuiTableColumnFlags.WidthFixed, core.px(65))
        ImGui.TableSetupColumn('Nav Path', ImGuiTableColumnFlags.WidthFixed, core.px(90))
        ImGui.TableSetupColumn('LoS', ImGuiTableColumnFlags.WidthFixed, core.px(40))
        ImGui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, core.px(55))
        ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, core.px(140))
        ImGui.TableHeadersRow()

        local currentTargetId = state.lastTargetId
        if currentTargetId == 0 then
            local okTarg, targId = pcall(function() return mq.TLO.Target.ID() end)
            if okTarg and targId then currentTargetId = targId end
        end

        for _, mob in ipairs(spawns.filteredNPCs) do
            ImGui.TableNextRow()
            local isSelected = (mob.id == currentTargetId)

            -- Column 1: Clean Name (Interactive row selectable). Labels and
            -- the ##id suffixes are precomputed on the record at scan time.
            ImGui.TableSetColumnIndex(0)
            local conStyle = getConStyle(mob.conColor)
            local nameLabel = isSelected and mob.rowLabelSel or mob.rowLabel
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
            ImGui.Text(mob.levelStr)

            -- Column 3: Consideration
            ImGui.TableSetColumnIndex(2)
            ImGui.TextColored(conStyle.r, conStyle.g, conStyle.b, 1.0, conStyle.badge)

            -- Column 4: Distance
            ImGui.TableSetColumnIndex(3)
            ImGui.Text(mob.distStr)

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
            ImGui.TextDisabled(mob.idStr)

            -- Column 8: Actions ([Tar], [Nav], [Map]) scoped by PushID so the
            -- button labels are constant strings.
            ImGui.TableSetColumnIndex(7)
            ImGui.PushID(mob.pushId)

            if ImGui.SmallButton('Tar') then
                actionQueue.pendingTargetId = mob.id
                state.statusMsg = string.format('Targeted: %s (ID: %d)', mob.cleanName, mob.id)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Target %s (ID: %d)', mob.cleanName, mob.id)) end

            ImGui.SameLine()
            if ImGui.SmallButton('Nav') then
                actionQueue.pendingTargetId = mob.id
                actionQueue.pendingNavId = mob.id
                state.activeNavSpawnId = mob.id
                state.activeNavLoc = nil
                state.activeNavCommandTime = mq.gettime()
                state.statusMsg = string.format('Navigating to: %s (ID: %d)', mob.cleanName, mob.id)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Navigate to %s (ID: %d)', mob.cleanName, mob.id)) end

            ImGui.SameLine()
            if ImGui.SmallButton('Map') then
                viewport.centerEqX = mob.x
                viewport.centerEqY = mob.y
                cfg.followPlayer = false
                switchToTab(1)
                state.statusMsg = string.format('Focused map on: %s (Y: %.1f, X: %.1f)', mob.cleanName, mob.y, mob.x)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', string.format('Center 2D map on %s (Y: %.1f, X: %.1f)', mob.cleanName, mob.y, mob.x)) end
            ImGui.PopID()
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
        -- Edits go to a buffer; the folder rescan + map reload only run when
        -- the user presses Enter or clicks Apply (not per keystroke).
        ImGui.PushItemWidth(320)
        local enterFlag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
        local custDir, entered = ImGui.InputText('Base Path##CustDirInput', state.customMapsDirInput or state.customMapsDir or '', enterFlag)
        if type(custDir) == 'string' then state.customMapsDirInput = custDir end
        ImGui.PopItemWidth()
        ImGui.SameLine()
        local applyClicked = ImGui.Button('Apply##ApplyBaseBtn')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Apply the base path (or press Enter in the field), rescan folders and reload the map') end
        if entered == true or applyClicked then
            state.customMapsDir = (state.customMapsDirInput or ''):match('^%s*(.-)%s*$')
            state.customMapsDirInput = state.customMapsDir
            clearZoneMapCache()
            scanMapFolders()
            scanMapFiles()
            loadZoneMap(state.currentZoneShort)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        ImGui.SameLine()
        if ImGui.Button('Reset to Auto##ResetAutoBaseBtn') then
            state.customMapsDir = ''
            state.customMapsDirInput = ''
            clearZoneMapCache()
            scanMapFolders()
            scanMapFiles()
            loadZoneMap(state.currentZoneShort)
            state.dirtySettings = true
            state.dirtySettingsTime = mq.gettime()
        end
        ImGui.TreePop()
    end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Map Layers Visibility')
    ImGui.Separator()

    local l0, c0 = ImGui.Checkbox('Layer 0 (Base Terrain / Geometry)##L0', cfg.layer0)
    if c0 then cfg.layer0 = l0; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local l1, c1 = ImGui.Checkbox('Layer 1 (Structures / Buildings)##L1', cfg.layer1)
    if c1 then cfg.layer1 = l1; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local l2, c2 = ImGui.Checkbox('Layer 2 (Objects / Details)##L2', cfg.layer2)
    if c2 then cfg.layer2 = l2; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local l3, c3 = ImGui.Checkbox('Layer 3 (Waypoints / Triune Lines)##L3', cfg.layer3)
    if c3 then cfg.layer3 = l3; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local lb, cl = ImGui.Checkbox('Labels (Map Text & POIs)##LabelsCheck', cfg.layerLabels)
    if cl then cfg.layerLabels = lb; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local grid, cg = ImGui.Checkbox('Grid Coordinate Lines##GridCheck', cfg.showGrid)
    if cg then cfg.showGrid = grid; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Entity & Visual Options')
    ImGui.Separator()

    local sn, csn = ImGui.Checkbox('Show NPCs on Map##ShowNPCCheck', cfg.showNPCs)
    if csn then cfg.showNPCs = sn; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sg, csg = ImGui.Checkbox('Show Group Members##ShowGrpCheck', cfg.showGroup)
    if csg then cfg.showGroup = sg; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local snn, csnn = ImGui.Checkbox('Show NPC Name Labels on Map##ShowNpcNamesCheck', cfg.showNPCNames)
    if csnn then cfg.showNPCNames = snn; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local snl, csnl = ImGui.Checkbox('Show Active Nav Path Line##ShowNavLineCheck', cfg.showNavLine)
    if csnl then cfg.showNavLine = snl; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.PushItemWidth(220)
    local cmIdx, cmChanged = ImGui.Combo('Node Color Mode##ColorModeCombo', cfg.colorModeIndex, COLOR_MODE_OPTIONS)
    if cmChanged then cfg.colorModeIndex = cmIdx; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local scanVal, scanChanged = ImGui.SliderInt('Spawn Scan Interval (ms)##ScanIntervalSlider', state.scanIntervalMs, 250, 3000, '%d ms')
    if scanChanged then
        state.scanIntervalMs = scanVal
        state.dirtySettings = true
        state.dirtySettingsTime = mq.gettime()
    end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'How often NPC positions/status are rescanned. Lower = fresher map, higher = lighter CPU load.') end
    ImGui.PopItemWidth()

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Triune Combat & Waypoint Overlays')
    ImGui.Separator()

    local td = state.triuneData
    if td.isLoaded then
        ImGui.TextColored(0.2, 0.95, 0.35, 1.0, string.format('Triune Status: Synchronized (%s)', td.charName))
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('| WPs: %d | Hazards: %d | Anchor: %s', #td.waypoints, #td.zoneHazards,
            ((td.hunterAnchor and td.hunterAnchor.x and td.hunterAnchor.y) and 'set' or 'none')))
        if td.loadoutPath then
            ImGui.TextDisabled(string.format('Source: %s', td.loadoutPath))
        end
    else
        ImGui.TextColored(1.0, 0.7, 0.2, 1.0, 'Triune Status: core config not synced yet')
    end

    ImGui.SameLine()
    if ImGui.Button('Sync Triune Data##SyncTriuneBtn') then
        syncTriuneLoadout(true)
    end

    local ss, css = ImGui.Checkbox('Show Search / Roam Radius##ShowSearchRadiusCheck', cfg.showSearchRadius)
    if css then cfg.showSearchRadius = ss; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sa, csa = ImGui.Checkbox('Show Anchor / Roam Point##ShowAnchorCheck', cfg.showAnchor)
    if csa then cfg.showAnchor = sa; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sc, csc = ImGui.Checkbox('Show Camp / Combat Radius##ShowCampRadiusCheck', cfg.showCampRadius)
    if csc then cfg.showCampRadius = sc; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local sw, csw = ImGui.Checkbox('Show Patrol Waypoints & Paths##ShowWaypointsCheck', cfg.showWaypoints)
    if csw then cfg.showWaypoints = sw; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.SameLine()
    local sh, csh = ImGui.Checkbox('Show Navigation Hazard Hotspots##ShowHazardsCheck', cfg.showHazards)
    if csh then cfg.showHazards = sh; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Multi-Level Z-Height & Smart Auto-Z')
    ImGui.Separator()

    ImGui.PushItemWidth(260)
    local zmIdx, zmChanged = ImGui.Combo('Z-Filter Mode##ZFilterModeCombo', cfg.zFilterMode, Z_FILTER_MODE_OPTIONS)
    if zmChanged then
        cfg.zFilterMode = zmIdx
        state.dirtySettings = true
        state.dirtySettingsTime = mq.gettime()
    end
    ImGui.PopItemWidth()

    if cfg.zFilterMode == 1 then
        ImGui.TextColored(0.2, 0.95, 0.35, 1.0, string.format('Active Floor Bounds: %s', state.smartFloor.floorLabel))
        local df, cdf = ImGui.Checkbox('Smooth Alpha Depth Fading (Fade Stairs/Ramps)##ZDepthFadeCheck', cfg.zDepthFading)
        if cdf then cfg.zDepthFading = df; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    elseif cfg.zFilterMode == 2 then
        local df, cdf = ImGui.Checkbox('Smooth Alpha Depth Fading##ZDepthFadeCheck', cfg.zDepthFading)
        if cdf then cfg.zDepthFading = df; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
        ImGui.PushItemWidth(250)
        local zRangeVal, zChanged = ImGui.SliderInt('Manual Z Window (± yards)##ZRangeSlider', cfg.zFilterRange, 10, 250)
        if zChanged then cfg.zFilterRange = zRangeVal; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
        ImGui.PopItemWidth()
    else
        ImGui.TextDisabled('Z-filtering disabled. All vertical floors and elevations are rendered.')
    end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Display Scaling & Geometry')
    ImGui.Separator()

    ImGui.PushItemWidth(250)
    local lt, clt = ImGui.SliderFloat('Map Line Thickness##LineThickSlider', cfg.lineThickness, 0.5, 3.5, '%.1f')
    if clt then cfg.lineThickness = lt; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end

    local nr, cnr = ImGui.SliderFloat('NPC Node Radius##NodeRadSlider', cfg.npcNodeRadius, 2.0, 9.0, '%.1f')
    if cnr then cfg.npcNodeRadius = nr; state.dirtySettings = true; state.dirtySettingsTime = mq.gettime() end
    ImGui.PopItemWidth()

    local bd, cbd = ImGui.Checkbox('Auto-Brighten Black / Dark Map Lines (High Contrast)##BoostDarkLinesCheck', cfg.boostDarkLines)
    if cbd and bd ~= cfg.boostDarkLines then
        cfg.boostDarkLines = bd
        state.dirtySettings = true
        state.dirtySettingsTime = mq.gettime()
        -- The brighten is applied at parse time: drop the parsed cache and
        -- re-parse the zone on view, keeping the current viewport.
        clearZoneMapCache()
        local keepX, keepY, keepZoom = viewport.centerEqX, viewport.centerEqY, viewport.zoom
        local isAtlas = (state.viewMode == 'ATLAS')
        loadZoneMap(isAtlas and state.atlasZoneShort or state.currentZoneShort, isAtlas)
        viewport.centerEqX, viewport.centerEqY, viewport.zoom = keepX, keepY, keepZoom
    end
    if ImGui.IsItemHovered() then ImGui.SetTooltip('%s', 'Automatically converts black (0,0,0) and dark map lines/labels to crisp visible silver/white against dark backgrounds') end

    ImGui.Spacing()
    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Navigation & Plugin Subsystem')
    ImGui.Separator()

    if navLoaded() then
        if navMeshLoaded() then
            ImGui.TextColored(0.2, 0.95, 0.35, 1.0, string.format('• MQ2Nav: Loaded (Mesh: %s)', state.currentZoneShort or 'current zone'))
        else
            ImGui.TextColored(0.95, 0.85, 0.20, 1.0, string.format('• MQ2Nav: Loaded (NO MESH: %s)', state.currentZoneShort or 'current zone'))
            ImGui.SameLine()
            if ImGui.Button('Reload Mesh##mapSettingsReloadMesh') then
                mq.cmd('/nav reload')
            end
        end
    else
        ImGui.TextColored(0.95, 0.25, 0.25, 1.0, '• MQ2Nav: NOT LOADED')
        ImGui.SameLine()
        if ImGui.Button('Load MQ2Nav##mapSettingsLoadNav') then
            mq.cmd('/plugin mq2nav')
        end
    end

    if stickLoaded() then
        ImGui.TextColored(0.2, 0.95, 0.35, 1.0, '• MQ2MoveUtils: Loaded')
    else
        ImGui.TextColored(0.95, 0.85, 0.20, 1.0, '• MQ2MoveUtils: NOT LOADED')
        ImGui.SameLine()
        if ImGui.Button('Load MQ2MoveUtils##mapSettingsLoadMoveUtils') then
            mq.cmd('/plugin mq2moveutils')
        end
    end

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
-- Set by initialize() (engine tick only); the draw callback shows a
-- "Loading..." placeholder until then.
local initialized = false

local function DrawTriuneMapUI()
    if not ctrl.show_map then return end

    core.pushTheme()

    local windowFlags = bit.bor(
        ImGuiWindowFlags.NoScrollbar or 0
    )
    -- Omit NoCollapse so WindowRounding token applies rounded corners cleanly
    windowFlags = bit.band(windowFlags, bit.bnot(ImGuiWindowFlags.NoCollapse or 0))

    local zoneDisplay = (state.viewMode == 'ATLAS') and string.format('Atlas: %s', (state.atlasSelectedZone and state.atlasSelectedZone.name) or state.atlasZoneShort) or state.currentZoneName
    local title = string.format('Triune Map v%s — %s###TriuneMapMainWindow', VERSION, zoneDisplay)
    core.preBeginWindow('map')
    local open, draw = ImGui.Begin(title, ctrl.show_map, windowFlags)

    if not open then
        ctrl.show_map = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end

    if draw and not initialized then
        -- Folder scan, file parse and the first spawn scan run from the engine
        -- tick (see initialize); the draw thread never does that work.
        core.postBeginWindow('map')
        ImGui.TextColored(0.65, 0.72, 0.82, 0.9, 'Loading map data...')
    elseif draw then
        core.postBeginWindow('map')
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

        -- Footer Status Bar (from per-tick player cache)
        local lp = state.lastPlayer
        local meX, meY, meZ = lp.x, lp.y, lp.z
        if lp.updatedAt == 0 then
            local okMeX, vX = pcall(function() return mq.TLO.Me.X() end)
            local okMeY, vY = pcall(function() return mq.TLO.Me.Y() end)
            local okMeZ, vZ = pcall(function() return mq.TLO.Me.Z() end)
            if okMeX and vX then meX = vX end
            if okMeY and vY then meY = vY end
            if okMeZ and vZ then meZ = vZ end
        end

        if meX and meY then
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
    core.popTheme()
end

-- ============================================================================
-- INITIALIZATION & ENGINE TICK (was the standalone main loop)
-- ============================================================================
local function initialize()
    if initialized then return end
    initialized = true
    CONFIG_FILE = mq.configDir and (mq.configDir .. '/triune_map_config.lua') or 'triune_map_config.lua'
    initAtlasRegistry()
    -- Config first: the saved custom base path decides where scanMapFolders
    -- looks, and the saved folder name is applied once the scan has run.
    loadConfig()
    scanMapFolders()
    applySavedMapFolder()
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

    autoloadRequiredPlugins()

    if not navLoaded() then
        print('\ar[Triune Map WARNING]\ax MQ2Nav plugin is not loaded! Map click-to-move and path distance require MQ2Nav (/plugin mq2nav).')
    elseif not navMeshLoaded() then
        local curZone = mq.TLO.Zone.ShortName() or 'current zone'
        print(string.format('\ar[Triune Map WARNING]\ax No NavMesh loaded for zone "%s"! Map pathing requires a valid zone mesh (/nav reload).', curZone))
    end
    if not stickLoaded() then
        print('\ar[Triune Map WARNING]\ax MQ2MoveUtils plugin is not loaded! Target stick movement requires MQ2MoveUtils (/plugin mq2moveutils).')
    end

    syncTriuneLoadout()
    local okP, pX, pY, pZ = pcall(function()
        local me = mq.TLO.Me
        return me.X(), me.Y(), me.Z()
    end)
    if okP then updateSmartFloorBounds(pX or 0, pY or 0, pZ or 0) end
    scanZoneSpawns(true)

    print(string.format('\ag[Triune Map]\ax v%s loaded -- In-Game Map, Norrath Atlas & NPC Tracker (plugin). Toggle with /ac map.', VERSION))
end

local function tick()
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
            -- Spawn IDs restart per zone: drop every per-ID cache, the nav
            -- queue and the active nav / POI markers before rescanning.
            resetZoneRuntimeState()
            if state.viewMode == 'LIVE' then
                loadZoneMap(curShort, false)
            end
            syncTriuneLoadout()
            scanZoneSpawns(true)
        end
    end

    -- Deferred plugin.showZone request (may have arrived from another
    -- plugin's draw callback before we were initialized).
    if state.pendingShowZone then
        local zs = state.pendingShowZone
        state.pendingShowZone = nil
        navigateToAtlasZone(zs, true)
        switchToTab(2)
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

    -- Player cache: refreshed every main-loop pass. The host loop only reaches
    -- this tick every ~150ms (see the mq.delay at the bottom of triune.lua's
    -- main loop), so this is NOT what drives the marker -- the draw callback
    -- samples the live position per frame. This cache is the footer's source
    -- and the fallback for samplePlayerSmoothed when a live read fails. Target
    -- ID rides a slower 100ms gate since it needs no per-loop freshness.
    local lp = state.lastPlayer
    local okP, vX, vY, vZ, vH = pcall(function()
        local me = mq.TLO.Me
        return me.X(), me.Y(), me.Z(), me.Heading.Degrees()
    end)
    if okP then
        if vX then lp.x = vX end
        if vY then lp.y = vY end
        if vZ then lp.z = vZ end
        if vH then lp.heading = vH end
    end
    if (now - lp.updatedAt) >= 100 then
        local okT, vT = pcall(function() return mq.TLO.Target.ID() end)
        if okT and vT then state.lastTargetId = vT end
    end
    lp.updatedAt = now

    -- Smart Auto-Z floor bounds (histogram over the map geometry) belong on
    -- the engine tick; the canvas only reads state.smartFloor.
    updateSmartFloorBounds(lp.x, lp.y, lp.z)

    -- Spawn scanning: one native fetch per interval (positions are never
    -- mixed across ticks), plus a small rolling LoS raycast slice every tick.
    if (now - state.lastScanTime) >= state.scanIntervalMs then
        state.lastScanTime = now
        scanZoneSpawns()
    end
    refreshLosChunk(SCAN_LOS_CHUNK, false)

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
        elseif stickLoaded() then
            pcall(function() mq.cmdf('/stick 10 id %d', nid) end)
        else
            state.activeNavSpawnId = 0
            state.statusMsg = 'Nav failed: missing plugins.'
            print('\ar[Triune Map WARNING]\ax Neither MQ2Nav nor MQ2MoveUtils is loaded! Cannot navigate to target. Load via \ay/plugin mq2nav\ax or \ay/plugin mq2moveutils\ax.')
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
        elseif not navState.meshLoaded then
            state.statusMsg = 'Nav failed: navmesh missing.'
            print('\ar[Triune Map WARNING]\ax MQ2Nav navmesh not loaded! Cannot navigate to map coordinate (/nav reload).')
        end
    end

    if actionQueue.pendingStopNav then
        actionQueue.pendingStopNav = false
        pcall(function() mq.cmd('/nav stop') end)
        pcall(function() mq.cmd('/stick off') end)
    end
end

-- ============================================================================
-- Plugin lifecycle
-- ============================================================================
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    cachedCharKey = nil
    if ctrl and ctrl.show_map == nil then ctrl.show_map = false end
    -- Map files / atlas are loaded lazily the first time the window opens so
    -- the core start-up is not delayed by scanning the maps folder.
    if ctrl and ctrl.show_map then initialize() end
end

function plugin.onDestroy()
    if initialized then saveConfig(true) end
    -- A later onInit (character swap) must reload this character's map config.
    initialized = false
    cachedCharKey = nil
end

function plugin.onTick()
    if not core then return end
    refresh()
    if not ctrl.show_map then return end
    if not initialized then initialize() end
    tick()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    if not ctrl.show_map then return end
    -- initialize() runs from onTick only; the window shows "Loading..." until then.
    DrawTriuneMapUI()
end

-- Zone change from the core: force an immediate map reload / rescan.
function plugin.onZoned()
    if initialized then state.lastZoneCheckTime = 0 end
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Map & NPC Tracker')
    local isWinOpen = (ctrl.show_map == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##mapToggleWin', core.px(250), core.px(24)) then
        ctrl.show_map = not isWinOpen
        core.saveLoadout(true)
    end
    ImGui.TextDisabled(string.format('Zone: %s | NPCs tracked: %d | Nav: %s',
        tostring(state.currentZoneName or '?'), tonumber(spawns.totalCount) or 0,
        (initialized and navState.meshLoaded) and 'mesh loaded' or 'no mesh'))
end

-- /ac map | mapui | triunemap | track | tracker | trackui | zone toggles the
-- window (was: /lua run triune_map). `track` variants open on the NPC Tracker tab.
function plugin.onCommand(cmd)
    if cmd ~= 'map' and cmd ~= 'mapui' and cmd ~= 'triunemap' and cmd ~= 'track' and cmd ~= 'tracker' and cmd ~= 'trackui' and cmd ~= 'zone' then
        return false
    end
    refresh()
    ctrl.show_map = not ctrl.show_map
    if ctrl.show_map and (cmd == 'track' or cmd == 'tracker' or cmd == 'trackui') then
        state.requestedTab = 3
    end
    core.saveLoadout(true)
    print(string.format('\ag[Triune]\ax Map & NPC Tracker %s.', ctrl.show_map and 'OPENED' or 'CLOSED'))
    return true
end

plugin.help = {
    '  \ag/ac map | track | zone\ax - Toggle the 2D Map, Zone Atlas & NPC Tracker window',
}

-- Opens the map window on the Zone Atlas showing `zoneShort` (used by the
-- Game Database plugin's NPC cards: "where does this spawn").
function plugin.showZone(zoneShort)
    if not core or not zoneShort or zoneShort == '' then return false end
    refresh()
    ctrl.show_map = true
    -- Callers are other plugins' draw callbacks; the atlas navigation (file
    -- parse) is handed to the engine tick, which also initializes first.
    state.pendingShowZone = zoneShort
    switchToTab(2)
    return true
end

-- Exposed for tests
plugin.state = state
plugin.cfg = cfg
plugin.syncTriuneLoadout = syncTriuneLoadout
plugin.tick = tick

return plugin
