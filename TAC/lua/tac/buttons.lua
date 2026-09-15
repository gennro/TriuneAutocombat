---@diagnostic disable: undefined-global, undefined-field, deprecated, need-check-nil
-- ============================================================================
-- TAC/lua/tac/buttons.lua — Triune Hot Buttons Plugin (Button Master-style)
-- ============================================================================
-- Replacement for EverQuest's hot button bars, modelled on Derple's Button
-- Master (https://github.com/DerpleDude/buttonmaster) but living inside
-- Triune as a plugin: no second script, no second ImGui loop, Triune theme,
-- Window Layout integration, and Box Network sync.
--
-- Data model (one shared file, <configDir>/triune_buttons.lua):
--   * buttons    - a library of hot buttons shared by every character
--                  (label, commands, icon, colours, cooldown timer, Lua hooks)
--   * sets       - named, sparse lists of button keys (slot index -> key)
--   * characters - per-character hotbar windows: each hotbar shows one or more
--                  sets as tabs (or a single set in compact mode) and keeps
--                  its own size, font, lock, title-bar and search options.
--
-- Buttons fire the moment they are clicked: command buttons issue their
-- `/` lines right away (mq.cmd only queues to the game's command handler),
-- and `--lua` script buttons run as their own coroutine pumped every frame,
-- so delay() inside a script yields instead of stalling the combat loop.
-- Nothing waits for the core's 150 ms main-loop pass. Share strings use Button Master's
-- format, so buttons and sets can be swapped with Button Master users, and
-- an existing ButtonMaster.lua config can be imported in one click.
-- ============================================================================

local plugin = {
    id                 = 'buttons',
    name               = 'Hot Buttons',
    version            = '1.0.0',
    author             = 'Triune',
    uses               = { boxnet = 'hotbar library sync across boxes (Sync Boxes option)' },
    description        = 'Button Master-style hot button bars: shared button library, tabbed sets, multiple hotbars, cooldown overlays, cursor capture, drag-and-drop, share strings, and Button Master import.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = false,
}

-- Populated by refresh() on every entry point; typed so the language server
-- does not treat them as permanently nil.
local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------
local CONFIG_NAME     = 'triune_buttons.lua'
local BM_CONFIG_NAME  = 'ButtonMaster.lua'
local DB_VERSION      = 1
local MAX_SLOTS       = 100      -- slots per set (matches Button Master)
local GRID_SPACING    = 2
local MIN_BUTTON_SIZE = 3        -- x10 px
local MAX_BUTTON_SIZE = 12
local DEFAULT_RATE    = 0.1      -- seconds between cooldown / label evaluations
local BAK_SUFFIX      = '.bak'

-- Internal timer ids <-> editor labels <-> Button Master names.
local TIMER_TYPES = {
    { id = 'None',    label = 'None',          bm = nil },
    { id = 'Seconds', label = 'Seconds Timer', bm = 'Seconds Timer' },
    { id = 'Item',    label = 'Item',          bm = 'Item' },
    { id = 'Gem',     label = 'Spell Gem',     bm = 'Spell Gem' },
    { id = 'AA',      label = 'AA',            bm = 'AA' },
    { id = 'Ability', label = 'Ability',       bm = 'Ability' },
    { id = 'Disc',    label = 'Disc',          bm = 'Disc' },
    { id = 'Lua',     label = 'Custom Lua',    bm = 'Custom Lua' },
}
local TIMER_LABELS = {}
for i, t in ipairs(TIMER_TYPES) do TIMER_LABELS[i] = t.label end

local UPDATE_RATES = {
    { label = 'Default (10 per second)', value = nil },
    { label = 'Every frame',             value = 0 },
    { label = '1 per second',            value = 1 },
    { label = '2 per second',            value = 0.5 },
    { label = '4 per second',            value = 0.25 },
    { label = '10 per second',           value = 0.1 },
    { label = '20 per second',           value = 0.05 },
}
local RATE_LABELS = {}
for i, r in ipairs(UPDATE_RATES) do RATE_LABELS[i] = r.label end

local FONT_SCALES = { 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5 }

-- Per-button font size choices (nil = the hotbar's font scale).
local BUTTON_FONT_SCALES = { 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0 }
local BUTTON_FONT_LABELS = { 'Hotbar default' }
for _, fs in ipairs(BUTTON_FONT_SCALES) do BUTTON_FONT_LABELS[#BUTTON_FONT_LABELS + 1] = string.format('%d%%', math.floor(fs * 100 + 0.5)) end

-- Swatch palettes for the editor (stored as {r,g,b} 0-255, so share strings
-- and Button Master imports keep working). The first entry means "default".
local BUTTON_PALETTE = {
    { name = 'Default', rgb = nil },
    { name = 'Red',     rgb = { 150, 35, 35 } },
    { name = 'Orange',  rgb = { 175, 90, 25 } },
    { name = 'Yellow',  rgb = { 165, 140, 25 } },
    { name = 'Green',   rgb = { 40, 125, 55 } },
    { name = 'Teal',    rgb = { 30, 120, 120 } },
    { name = 'Blue',    rgb = { 35, 80, 160 } },
    { name = 'Purple',  rgb = { 105, 50, 150 } },
    { name = 'Pink',    rgb = { 165, 55, 115 } },
    { name = 'Brown',   rgb = { 110, 75, 45 } },
    { name = 'Gray',    rgb = { 95, 100, 110 } },
    { name = 'Black',   rgb = { 20, 20, 25 } },
    { name = 'White',   rgb = { 215, 215, 220 } },
}
local TEXT_PALETTE = {
    { name = 'Default', rgb = nil },
    { name = 'White',   rgb = { 255, 255, 255 } },
    { name = 'Black',   rgb = { 0, 0, 0 } },
    { name = 'Gray',    rgb = { 170, 175, 185 } },
    { name = 'Red',     rgb = { 255, 90, 90 } },
    { name = 'Orange',  rgb = { 255, 165, 60 } },
    { name = 'Yellow',  rgb = { 255, 225, 80 } },
    { name = 'Green',   rgb = { 100, 230, 120 } },
    { name = 'Teal',    rgb = { 90, 220, 220 } },
    { name = 'Blue',    rgb = { 110, 170, 255 } },
    { name = 'Purple',  rgb = { 190, 130, 255 } },
    { name = 'Pink',    rgb = { 255, 130, 200 } },
}

-- Alphabetic groups for long "assign" / "delete" menus.
local ALPHA_GROUPS = {
    { name = 'A - F', test = function(c) return c >= 'A' and c <= 'F' end },
    { name = 'G - L', test = function(c) return c >= 'G' and c <= 'L' end },
    { name = 'M - R', test = function(c) return c >= 'M' and c <= 'R' end },
    { name = 'S - Z', test = function(c) return c >= 'S' and c <= 'Z' end },
    { name = 'Other', test = function() return true end },
}

local GOLD  = { 1.00, 0.70, 0.54, 1 }
local MUTED = { 0.49, 0.56, 0.65, 1 }
local GOOD  = { 0.37, 0.88, 0.64, 1 }
local WARN  = { 0.95, 0.75, 0.30, 1 }
local ERR   = { 0.90, 0.35, 0.35, 1 }

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------
-- The shared library. Replaced wholesale by loadDb().
local db = nil

-- Per-button runtime cache (never saved): evaluated label / cooldown, the
-- last evaluation time, the largest remaining time seen (used as the total
-- when the game has no "total" for a timer), and manual-timer fire times.
local cache = {}

local state = {
    charKey        = nil,
    loaded         = false,
    scripts        = {},        -- running `--lua` button coroutines
    statusMsg      = '',
    statusAt       = 0,
    dnd            = nil,       -- { hb = id, set = name, index = n }
    activeSet      = {},        -- hotbar id -> selected tab index
    search         = {},        -- hotbar id -> search text
    newSetName     = {},        -- hotbar id -> "create set" text
    titleEdit      = {},        -- hotbar id -> title being edited
    renameSet      = nil,       -- { from = name, text = name }
    boxnetUnsub    = nil,
    reloadPending  = false,
    lastBroadcast  = 0,
    bindsBound     = {},
    bmImportResult = nil,
    frame          = 0,         -- onDrawUI counter ("Every frame" buttons evaluate once per frame)
}

-- Edit Button window
local edit = {
    open      = false,
    hbId      = 0,
    setName   = nil,
    index     = 0,
    key       = nil,   -- existing button key, nil when creating
    tmp       = nil,   -- working copy
    dirty     = false,
    timerIdx  = 1,
    rateIdx   = 1,
    advanced  = false,
}

-- Icon Picker window
local picker = { open = false, page = 1, tab = 'Spell', maxSpell = 2243, maxItem = 12599, perPage = 500, size = 40,
                 pageKey = nil, pageAnims = nil, spellDedicated = nil }

-- Import Button / Set window
local imp = { open = false, hbId = 0, text = '', decoded = nil, valid = false, err = nil }

-- "Add From Game" browser: AAs / spell gems / abilities / discs / item clickies
-- the character actually has, one click to make a button out of any of them.
local browser = {
    open    = false,
    tab     = 'AA',        -- 'AA' | 'Gem' | 'Ability' | 'Disc' | 'Item'
    mode    = 'assign',    -- 'assign' (create + place) | 'editor' (fill the open editor)
    target  = nil,         -- { hbId = n, setName = s, index = n | nil }
    search  = '',
    lists   = {},          -- tab -> { entries }
    scanAt  = {},          -- tab -> os.clock() of the last scan
    boxScope = 'bar',      -- Box Control tab: bar (hotbar switch) | all | zone | group
    scanRequest = {},      -- tab -> true: the draw thread wants onTick to (re)scan it
    gemFp   = nil,         -- memorized-gem fingerprint the Gem list was built from
    gemFpAt = 0,
}
local BROWSER_TABS = {
    { id = 'AA',      label = 'AAs' },
    { id = 'Gem',     label = 'Spell Gems' },
    { id = 'Ability', label = 'Abilities' },
    { id = 'Disc',    label = 'Discs' },
    { id = 'Item',    label = 'Items' },
    { id = 'Box',     label = 'Box Control' },
    { id = 'Cmd',     label = 'Commands' },
}
-- Triune slash commands as a pick list. Entries with a placeholder
-- (<...> / [...]) open the editor pre-filled so the argument can be typed;
-- the rest become buttons as-is. Plugin help lines are appended live.
local CORE_COMMANDS = {
    -- Control
    { group = 'Control', name = 'Run',                cmd = '/ac run',              desc = 'Start / unpause auto-combat' },
    { group = 'Control', name = 'Pause',              cmd = '/ac pause',            desc = 'Pause auto-combat, halt movement, disengage pet' },
    { group = 'Control', name = 'Run / Pause',        cmd = '/triunerun',           desc = 'Toggle run / pause' },
    { group = 'Control', name = 'Burn On',            cmd = '/ac burn on',          desc = 'Enable burn mode (Burn Only spells, AAs, discs)' },
    { group = 'Control', name = 'Burn Off',           cmd = '/ac burn off',         desc = 'Disable burn mode' },
    { group = 'Control', name = 'Burn Toggle',        cmd = '/ac burn',             desc = 'Toggle burn mode' },
    { group = 'Control', name = 'Status',             cmd = '/ac status',           desc = 'Print running state and combat mode to chat' },
    { group = 'Control', name = 'Mem All',            cmd = '/ac memall',           desc = 'Queue all missing / mismatched priority spells for memorization' },
    { group = 'Control', name = 'Import Bar',         cmd = '/ac importbar',        desc = 'Auto-populate spell lines from the memorized gems' },
    { group = 'Control', name = 'Clear Lockouts',     cmd = '/ac clear lockouts',   desc = 'Clear spell lockouts, buff backoffs, and mob immunities' },
    { group = 'Control', name = 'Clear Cursor',       cmd = '/ac clearcursor',      desc = 'Clear the item on the cursor per the cursor rules' },
    -- Modes
    { group = 'Mode', name = 'Manual',                cmd = '/ac manual',           desc = 'Manual mode: you drive, Triune fights' },
    { group = 'Mode', name = 'Puller (Hunt)',         cmd = '/ac puller hunt',      desc = 'Puller mode, roam and hunt' },
    { group = 'Mode', name = 'Puller (Camp)',         cmd = '/ac puller camp',      desc = 'Puller mode, pull back to camp' },
    { group = 'Mode', name = 'Assist (Chase)',        cmd = '/ac assist chase',     desc = 'Assist mode, follow the Main Assist' },
    { group = 'Mode', name = 'Assist (Camp)',         cmd = '/ac assist camp',      desc = 'Assist mode, hold the camp' },
    { group = 'Mode', name = 'Assist (Backline)',     cmd = '/ac assist backline',  desc = 'Assist mode, stay back from the fight' },
    { group = 'Mode', name = 'Tank',                  cmd = '/ac tank',             desc = 'Alias of Assist (Camp): hold the camp as the tank' },
    -- Main Assist
    { group = 'Main Assist', name = 'MA = Target',    cmd = '/ac ma target',        desc = 'Set the Main Assist from your current PC target' },
    { group = 'Main Assist', name = 'MA Clear',       cmd = '/ac ma clear',         desc = 'Clear the Main Assist' },
    { group = 'Main Assist', name = 'MA by Name',     cmd = '/ac ma <name>',        desc = 'Set the Main Assist by name' },
    -- Combat style & toggles
    { group = 'Style', name = 'Style: Melee',         cmd = '/ac style melee',      desc = '/attack at melee reach' },
    { group = 'Style', name = 'Style: Ranged',        cmd = '/ac style ranged',     desc = 'Bow via server #attackmode' },
    { group = 'Style', name = 'Style: Spell',         cmd = '/ac style spell',      desc = 'Never auto-attack' },
    { group = 'Toggle', name = 'Self Defense On',     cmd = '/ac selfdefense on',   desc = 'Assist mode: fight back when attacked while the MA has no target' },
    { group = 'Toggle', name = 'Self Defense Off',    cmd = '/ac selfdefense off',  desc = 'Assist mode: no self-defense' },
    { group = 'Toggle', name = 'Assist Behind On',    cmd = '/ac assistbehind on',  desc = 'Position behind the NPC in combat' },
    { group = 'Toggle', name = 'Assist Behind Off',   cmd = '/ac assistbehind off', desc = 'Do not reposition behind the NPC' },
    { group = 'Toggle', name = 'Manual Stick On',     cmd = '/ac manualstick on',   desc = 'Manual mode: stick to the NPC being fought' },
    { group = 'Toggle', name = 'Manual Stick Off',    cmd = '/ac manualstick off',  desc = 'Manual mode: you drive' },
    { group = 'Toggle', name = 'Manual Nav On',       cmd = '/ac manualnav on',     desc = 'Manual mode: auto-navigate to a selected hostile NPC' },
    { group = 'Toggle', name = 'Manual Nav Off',      cmd = '/ac manualnav off',    desc = 'Manual mode: no auto-navigation' },
    { group = 'Toggle', name = 'Waypoints On',        cmd = '/ac wp on',            desc = 'Enable the Puller waypoint patrol loop' },
    { group = 'Toggle', name = 'Waypoints Off',       cmd = '/ac wp off',           desc = 'Disable the waypoint patrol loop' },
    { group = 'Toggle', name = 'Waypoint Add',        cmd = '/ac wp add',           desc = 'Add your location as a patrol waypoint' },
    { group = 'Toggle', name = 'Waypoints Clear',     cmd = '/ac wp clear',         desc = 'Remove every patrol waypoint' },
    -- Windows
    { group = 'Window', name = 'Compact / Mini HUD',  cmd = '/ac compact',          desc = 'Toggle the Compact Mini-Window mode' },
    { group = 'Window', name = 'Unit Frames',         cmd = '/ac hud',              desc = 'Toggle the Target & Player HUD' },
    { group = 'Window', name = 'Cooldowns',           cmd = '/ac cd',               desc = 'Toggle the Cooldown & Ability Monitor' },
    { group = 'Window', name = 'Spell Gems',          cmd = '/ac gems',             desc = 'Toggle the popout Spell Gem bar' },
    { group = 'Window', name = 'Spellbook',           cmd = '/ac spellbook',        desc = 'Toggle the Spellbook Browser' },
    { group = 'Window', name = 'Cursor Manager',      cmd = '/ac cursorui',         desc = 'Toggle the Cursor Item Manager' },
    { group = 'Window', name = 'Map',                 cmd = '/ac map',              desc = 'Toggle the Map, Zone Atlas & NPC Tracker' },
    { group = 'Window', name = 'Inventory',           cmd = '/ac inv',              desc = 'Toggle the Inventory & Bank Manager' },
    { group = 'Window', name = 'DPS Parser',          cmd = '/ac dps',              desc = 'Toggle the DPS Parser' },
    { group = 'Window', name = 'Box Net',             cmd = '/ac net',              desc = 'Toggle the Box Network window' },
    { group = 'Window', name = 'Buffbot Window',      cmd = '/ac buffbot',          desc = 'Toggle the Buffbot window' },
    { group = 'Window', name = 'Buffbot On',          cmd = '/ac buffbot on',       desc = 'Start the buffbot station' },
    { group = 'Window', name = 'Buffbot Off',         cmd = '/ac buffbot off',      desc = 'Stop the buffbot station' },
    { group = 'Window', name = 'Auto AA',             cmd = '/ac aawin',            desc = 'Toggle the Auto AA spender window' },
    { group = 'Window', name = 'Auto-Accept',         cmd = '/ac autoaccept',       desc = 'Toggle the Auto-Accept window' },
    { group = 'Window', name = 'Hot Buttons',         cmd = '/ac btn',              desc = 'Toggle the hotbars' },
    { group = 'Window', name = 'Help',                cmd = '/ac help',             desc = 'Print the slash command help to chat' },
    -- Settings with an argument (open the editor)
    { group = 'Setting', name = 'Range',              cmd = '/ac range <dist>',         desc = 'Engagement distance for the active style' },
    { group = 'Setting', name = 'XTarget Distance',   cmd = '/ac xtardist <25-300>',    desc = 'Max XTarget / assist chase distance' },
    { group = 'Setting', name = 'Chase Distance',     cmd = '/ac chasedist <5-100>',    desc = 'Following distance from the Main Assist' },
    { group = 'Setting', name = 'Pull Min HP',        cmd = '/ac pullhp <0-95>',        desc = 'Minimum HP % before pulling pauses to rest' },
    { group = 'Setting', name = 'Hunter Z Plane',     cmd = '/ac zplane <5-100>',       desc = 'Same-floor height threshold' },
    { group = 'Setting', name = 'Hunter Max Z',       cmd = '/ac huntz <10-300>',       desc = 'Max vertical height difference' },
    { group = 'Setting', name = 'UI Scale',           cmd = '/ac scale <0.75-2.0>',     desc = 'UI scale for every Triune window' },
    { group = 'Setting', name = 'Pull Con Preset',    cmd = '/ac pullcon preset <all|hostile|indifferent|none>', desc = 'Puller faction filter preset' },
    { group = 'Setting', name = 'Load Preset',        cmd = '/ac preset load <name>',   desc = 'Load a saved spell-set preset' },
    { group = 'Setting', name = 'Save Preset',        cmd = '/ac preset save <name>',   desc = 'Save the current spell set as a preset' },
}
-- Box Control presets: the Box Net window's quick actions as buttons. `%s` is
-- the scope: a fixed one (all | zone | group) baked into the command, or the
-- `{scope}` placeholder ('bar'), which runButton resolves at press time from
-- the hotbar's own Group / Zone / All switch (hb.boxScope) so one set of
-- buttons serves every scope. ${Me.CleanName} is expanded by the command
-- parser on the character that presses the button, so the shared library
-- works for every box.
local BOX_SCOPE_TOKEN = '{scope}'
local BOX_SCOPES = {
    { id = 'bar',   label = 'Hotbar switch' },
    { id = 'all',   label = 'All boxes' },
    { id = 'zone',  label = 'Same zone' },
    { id = 'group', label = 'My group' },
}
-- The live scopes a hotbar switch can be set to (what `{scope}` becomes).
local BAR_SCOPES = {
    { id = 'group', label = 'Group', desc = 'My group' },
    { id = 'zone',  label = 'Zone',  desc = 'Same zone' },
    { id = 'all',   label = 'All',   desc = 'All boxes' },
}
local BOX_PRESETS = {
    { name = 'Run',          desc = 'Start auto-combat on the boxes',                cmd = '/ac net %s run',                                          color = { 40, 125, 55 } },
    { name = 'Pause',        desc = 'Pause auto-combat on the boxes',                cmd = '/ac net %s pause',                                        color = { 150, 35, 35 } },
    { name = 'Burn On',      desc = 'Turn burn mode on',                             cmd = '/ac net %s burn on',                                      color = { 175, 90, 25 } },
    { name = 'Burn Off',     desc = 'Turn burn mode off',                            cmd = '/ac net %s burn off',                                     color = { 110, 75, 45 } },
    { name = 'Follow Me',    desc = 'Make me their Main Assist and switch them to Assist (Chase)', cmd = '/ac net %s ma ${Me.CleanName}\n/ac net %s assist chase', color = { 35, 80, 160 } },
    { name = 'Assist Me',    desc = 'Make me their Main Assist and switch them to Assist (Camp)',  cmd = '/ac net %s ma ${Me.CleanName}\n/ac net %s assist camp',  color = { 30, 120, 120 } },
    { name = 'Set Me as MA', desc = 'Make me their Main Assist (mode unchanged)',    cmd = '/ac net %s ma ${Me.CleanName}',                           color = { 105, 50, 150 } },
    { name = 'Buff Me',      desc = 'Ask the boxes for the loadout buffs I am missing', cmd = '/ac net buffme %s',                                    color = { 165, 55, 115 } },
    { name = 'Camp Here',    desc = 'Push my location as their camp anchor',         cmd = '/ac net camp %s',                                         color = { 165, 140, 25 } },
}
local AA_ID_RANGES = { { 1, 1500 }, { 4000, 4060 }, { 5000, 5050 }, { 8120, 8140 }, { 17780, 17800 } }

-- Loadout-persisted preferences (onSaveSettings / onLoadSettings)
local prefs = {
    syncBoxes   = true,   -- reload when another box saves (Box Network)
    announceRun = false,  -- print each button execution to chat
}

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------
local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

local function log(fmt, ...)
    local msg = select('#', ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    print('\ag[Triune Buttons]\ax ' .. msg)
end

local function setStatus(fmt, ...)
    state.statusMsg = select('#', ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    state.statusAt = os.clock()
end

local function tlo(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function trim(s)
    return (tostring(s or ''):match('^%s*(.-)%s*$'))
end

local function split(text, sep)
    local out = {}
    text = tostring(text or '')
    if text == '' then return out end
    local pattern = '([^' .. sep .. ']*)' .. sep .. '?'
    local pos = 1
    while pos <= #text do
        local s, e, piece = text:find(pattern, pos)
        if not s or e < pos then break end
        out[#out + 1] = piece
        pos = e + 1
    end
    if text:sub(-1) == sep then out[#out + 1] = '' end
    return out
end

-- Splits on newlines keeping empty lines, so reported line numbers match the
-- editor; a single trailing empty line is dropped.
local function lines(text)
    local out = {}
    for line in (tostring(text or '') .. '\n'):gmatch('(.-)\r?\n') do out[#out + 1] = line end
    if #out > 0 and out[#out] == '' then out[#out] = nil end
    return out
end

local function deepcopy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[deepcopy(k, seen)] = deepcopy(val, seen) end
    return out
end

local function tableSize(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function sortedKeys(t, cmp)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, cmp or function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return out
end

local function fmtTime(sec)
    sec = math.max(0, math.floor((tonumber(sec) or 0) + 0.5))
    if sec >= 3600 then return string.format('%dh%02dm', math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
    if sec >= 60 then return string.format('%d:%02d', math.floor(sec / 60), sec % 60) end
    return tostring(sec)
end

local function alphaGroupFor(label)
    local c = tostring(label or ''):sub(1, 1):upper()
    for _, g in ipairs(ALPHA_GROUPS) do
        if g.test(c) then return g.name end
    end
    return 'Other'
end

-- Deterministic, readable Lua serializer for the config file and share strings.
local function serialize(val, indent)
    indent = indent or ''
    local t = type(val)
    if t == 'string' then return string.format('%q', val) end
    if t == 'number' then
        if val ~= val or val == math.huge or val == -math.huge then return '0' end
        if math.floor(val) == val then return string.format('%d', val) end
        return string.format('%.4f', val)
    end
    if t == 'boolean' then return tostring(val) end
    if t ~= 'table' then return 'nil' end
    local keys = {}
    for k in pairs(val) do
        if type(k) == 'string' or type(k) == 'number' then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == 'number'
    end)
    if #keys == 0 then return '{}' end
    local inner = indent .. '  '
    local parts = {}
    for _, k in ipairs(keys) do
        local v = val[k]
        local vt = type(v)
        if vt == 'string' or vt == 'number' or vt == 'boolean' or vt == 'table' then
            local ks
            if type(k) == 'number' then
                ks = string.format('[%d]', k)
            elseif k:match('^[%a_][%w_]*$') then
                ks = k
            else
                ks = string.format('[%q]', k)
            end
            parts[#parts + 1] = inner .. ks .. ' = ' .. serialize(v, inner)
        end
    end
    return '{\n' .. table.concat(parts, ',\n') .. ',\n' .. indent .. '}'
end

-- base64 (standard alphabet) - compatible with Button Master's share strings.
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64enc(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return B64:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function b64dec(data)
    data = tostring(data or ''):gsub('[^' .. B64 .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (B64:find(x, 1, true) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

-- Compile a Lua chunk with a sandboxed environment (LuaJIT: loadstring +
-- setfenv; Lua 5.2+: load with env).
local function compile(src, name, env)
    if type(src) ~= 'string' or src == '' then return nil, 'empty chunk' end
    if setfenv and loadstring then
        local fn, err = loadstring(src, name)
        if not fn then return nil, err end
        setfenv(fn, env)
        return fn
    end
    return load(src, name, 't', env)
end

-- ----------------------------------------------------------------------------
-- Character / paths
-- ----------------------------------------------------------------------------
local function computeCharKey()
    local server = tlo(function() return mq.TLO.EverQuest.Server() end)
    local name = tlo(function() return mq.TLO.Me.DisplayName() end)
    if not name or name == '' then name = tlo(function() return mq.TLO.Me.CleanName() end) end
    if not name or name == '' then name = tlo(function() return mq.TLO.Me.Name() end) end
    if not name or name == '' then return 'default' end
    return tostring(server or 'local') .. '_' .. tostring(name)
end

local function charKey()
    if not state.charKey then state.charKey = computeCharKey() end
    return state.charKey
end

local function configDir()
    local d = (mq and mq.configDir) or 'config'
    return (tostring(d):gsub('[/\\]+$', ''))
end

function plugin.configPath()
    if plugin.configPathOverride then return plugin.configPathOverride end
    return configDir() .. '/' .. CONFIG_NAME
end

function plugin.bmConfigPath()
    if plugin.bmConfigPathOverride then return plugin.bmConfigPathOverride end
    return configDir() .. '/' .. BM_CONFIG_NAME
end

-- ----------------------------------------------------------------------------
-- Icons (spell icons via the core helper, item icons via A_DragItem)
-- ----------------------------------------------------------------------------
local EQ_ICON_OFFSET = 500
-- cache: cell -> { ta = TextureAnimation, at = use counter }; capped at
-- `max` by evicting the least recently used quarter (the Icon Picker can
-- browse thousands of item cells).
local itemIcon = { mode = 'probe', shared = nil, lastCell = nil, cache = {}, count = 0, tick = 0, max = 600 }

local function probeItemIcons()
    if itemIcon.mode ~= 'probe' then return end
    if mq and mq.TextureAnimation then
        local ok, res = pcall(mq.TextureAnimation, 'triunebtn_probe')
        if ok and res then
            itemIcon.mode = 'dedicated'
            return
        end
    end
    if mq and mq.FindTextureAnimation then
        local ok, res = pcall(mq.FindTextureAnimation, 'A_DragItem')
        if ok and res then
            itemIcon.mode = 'shared'
            itemIcon.shared = res
            return
        end
    end
    itemIcon.mode = 'none'
end

-- `cell` is the A_DragItem cell (item Icon - 500), as Button Master stores it.
function itemIcon.evict()
    local entries = {}
    for k, e in pairs(itemIcon.cache) do entries[#entries + 1] = { k, e.at } end
    table.sort(entries, function(a, b) return a[2] < b[2] end)
    local drop = math.max(1, math.floor(#entries / 4))
    for i = 1, drop do itemIcon.cache[entries[i][1]] = nil end
    itemIcon.count = math.max(0, itemIcon.count - drop)
end

local function itemIconAnim(cell)
    local id = tonumber(cell)
    if not id or id < 0 then return nil end
    probeItemIcons()
    if itemIcon.mode == 'dedicated' then
        itemIcon.tick = itemIcon.tick + 1
        local ent = itemIcon.cache[id]
        if ent then
            ent.at = itemIcon.tick
            return ent.ta
        end
        local ok, res = pcall(mq.TextureAnimation, 'triunebtn_' .. id)
        if ok and res then
            pcall(function() res:SetTextureCell(id) end)
            if itemIcon.count >= itemIcon.max then itemIcon.evict() end
            itemIcon.cache[id] = { ta = res, at = itemIcon.tick }
            itemIcon.count = itemIcon.count + 1
            return res
        end
        return nil
    elseif itemIcon.mode == 'shared' and itemIcon.shared then
        if itemIcon.lastCell ~= id then
            if not pcall(function() itemIcon.shared:SetTextureCell(id) end) then return nil end
            itemIcon.lastCell = id
        end
        return itemIcon.shared
    end
    return nil
end

local function iconAnim(iconId, iconType)
    if iconType == 'Item' then return itemIconAnim(iconId) end
    if core and core.getSpellIconAnimation then
        local ok, res = pcall(core.getSpellIconAnimation, iconId)
        if ok then return res end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Lua evaluation (labels, icons, timers, --lua command buttons)
-- ----------------------------------------------------------------------------
local function luaEnv(delayFn)
    local env = setmetatable({}, { __index = _G })
    -- mq.delay inside a button script must not block the core: script buttons
    -- get a yielding delay (see runLuaButton); everything else (labels, timers)
    -- runs synchronously and gets the cooperative core delay.
    delayFn = delayFn or function(ms, cond) return core.delay(ms, cond) end
    env.mq = setmetatable({ delay = delayFn }, { __index = mq })
    env.delay = delayFn
    env.ImGui = ImGui
    env.core = core
    env.ctrl = ctrl
    env.print = print
    return env
end

-- Label / icon / timer chunks run synchronously, so one sandbox per button
-- (kept on its cache entry) is enough; the old code built two tables and two
-- metatables per evaluation, up to five times per button per 100 ms. The
-- environment is rebuilt (and the compiled chunks dropped) when the core
-- handles change, e.g. when the plugin is re-initialised with a fresh mock.
local function buttonEnv(c)
    local env = c.env
    if not env or c.envMq ~= mq or c.envImGui ~= ImGui or c.envCore ~= core or c.envCtrl ~= ctrl then
        env = luaEnv()
        c.env = env
        c.envMq, c.envImGui, c.envCore, c.envCtrl = mq, ImGui, core, ctrl
        c.fns = nil
    end
    return env
end

-- Compiles `src` once per (cache entry, field) and runs it. The chunk name
-- is only built when compiling, never per call; cacheFor() drops the entry
-- (and so the compiled chunks) whenever the button is edited or reloaded.
local function evalCached(c, field, src, label)
    local env = buttonEnv(c)
    local fns = c.fns
    if not fns then
        fns = {}
        c.fns = fns
    end
    local slot = fns[field]
    if not slot or slot.src ~= src then
        local fn, err = compile(src, field .. ':' .. tostring(label or ''), env)
        slot = { src = src, fn = fn, err = err }
        fns[field] = slot
    end
    if not slot.fn then return false, slot.err end
    return pcall(slot.fn)
end

-- ----------------------------------------------------------------------------
-- Database: defaults, load, save, character section
-- ----------------------------------------------------------------------------
local function newHotbar(title)
    return {
        title         = title or 'Hot Buttons',
        visible       = true,
        locked        = false,
        hideTitleBar  = false,
        hideScrollbar = false,
        compact       = false,
        perCharPos    = false,
        showSearch    = false,
        advTooltips   = false,
        boxScope      = 'all',  -- live scope for `{scope}` box-control buttons: group | zone | all
        showScopeBar  = true,   -- draw the Group / Zone / All switch when the bar has such buttons
        buttonSize    = 6,      -- x10 px
        fontScale     = 1.0,
        alpha         = 1.0,
        sets          = {},     -- ordered set names shown as tabs
    }
end

local function defaultDb()
    return {
        version = DB_VERSION,
        buttons = {
            Button_1 = { label = 'Run',        cmd = '/ac run',           timerType = 'None' },
            Button_2 = { label = 'Pause',      cmd = '/ac pause',         timerType = 'None' },
            Button_3 = { label = 'Burn',       cmd = '/ac burn',          timerType = 'None' },
            Button_4 = { label = 'Nav Target', cmd = '/nav id ${Target.ID}', timerType = 'None' },
        },
        sets = {
            Primary  = { [1] = 'Button_1', [2] = 'Button_2', [3] = 'Button_3' },
            Movement = { [1] = 'Button_4' },
        },
        characters = {},
    }
end

local function normalizeButton(b)
    if type(b) ~= 'table' then return nil end
    b.label = tostring(b.label or '')
    b.cmd = tostring(b.cmd or '')
    if b.icon ~= nil then b.icon = tonumber(b.icon) end
    if b.iconType ~= 'Item' then b.iconType = 'Spell' end
    if b.showLabel == nil then b.showLabel = true end
    local valid = false
    for _, t in ipairs(TIMER_TYPES) do if t.id == b.timerType then valid = true end end
    if not valid then b.timerType = 'None' end
    if b.updateRate ~= nil then
        b.updateRate = tonumber(b.updateRate)
        -- a negative interval means "as often as possible", i.e. every frame
        if b.updateRate and b.updateRate < 0 then b.updateRate = 0 end
    end
    if b.fontScale ~= nil then
        b.fontScale = tonumber(b.fontScale)
        if b.fontScale then b.fontScale = math.max(0.4, math.min(3.0, b.fontScale)) end
    end
    return b
end

local function normalizeDb(d)
    if type(d) ~= 'table' then d = defaultDb() end
    d.version = DB_VERSION
    if type(d.buttons) ~= 'table' then d.buttons = {} end
    if type(d.sets) ~= 'table' then d.sets = {} end
    if type(d.characters) ~= 'table' then d.characters = {} end
    for k, b in pairs(d.buttons) do
        if not normalizeButton(b) then d.buttons[k] = nil end
    end
    for name, set in pairs(d.sets) do
        if type(set) ~= 'table' then
            d.sets[name] = {}
        else
            for idx, key in pairs(set) do
                if type(idx) ~= 'number' or not d.buttons[key] then set[idx] = nil end
            end
        end
    end
    for ck, c in pairs(d.characters) do
        if type(c) ~= 'table' then
            d.characters[ck] = nil
        else
            if type(c.hotbars) ~= 'table' then c.hotbars = {} end
            for i = #c.hotbars, 1, -1 do
                if type(c.hotbars[i]) ~= 'table' then table.remove(c.hotbars, i) end
            end
            for i, hb in ipairs(c.hotbars) do
                local def = newHotbar()
                for k, v in pairs(def) do
                    if hb[k] == nil then hb[k] = v end
                end
                hb.buttonSize = math.max(MIN_BUTTON_SIZE, math.min(MAX_BUTTON_SIZE, math.floor(tonumber(hb.buttonSize) or 6)))
                hb.fontScale = tonumber(hb.fontScale) or 1.0
                hb.alpha = math.max(0.1, math.min(1.0, tonumber(hb.alpha) or 1.0))
                if hb.boxScope ~= 'group' and hb.boxScope ~= 'zone' and hb.boxScope ~= 'all' then hb.boxScope = 'all' end
                if hb.title == '' then hb.title = 'Hot Buttons ' .. i end
                local keep = {}
                if type(hb.sets) ~= 'table' then hb.sets = {} end
                for _, s in ipairs(hb.sets) do
                    if d.sets[s] then keep[#keep + 1] = s end
                end
                hb.sets = keep
            end
        end
    end
    return d
end

local function myChar()
    local key = charKey()
    local c = db.characters[key]
    if not c then
        c = { hotbars = {} }
        db.characters[key] = c
    end
    if #c.hotbars == 0 then
        local hb = newHotbar('Hot Buttons')
        if db.sets.Primary then hb.sets[#hb.sets + 1] = 'Primary' end
        if db.sets.Movement then hb.sets[#hb.sets + 1] = 'Movement' end
        c.hotbars[1] = hb
    end
    return c
end

local function hotbars() return myChar().hotbars end

local function readFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

local function loadDb()
    local path = plugin.configPath()
    local loaded = nil
    local fn = loadfile(path)
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == 'table' then loaded = t end
    end
    local fresh = (loaded == nil)
    db = normalizeDb(loaded or defaultDb())
    cache = {}
    myChar()
    state.loaded = true
    return not fresh
end

local function saveDb(opts)
    opts = opts or {}
    if not db then return false end
    local path = plugin.configPath()
    local old = readFile(path)
    if old and #old > 0 then
        local bak = io.open(path .. BAK_SUFFIX, 'w')
        if bak then
            bak:write(old)
            bak:close()
        end
    end
    local f, err = io.open(path, 'w')
    if not f then
        log('\arCould not write %s: %s', path, tostring(err))
        return false
    end
    f:write('-- Triune Hot Buttons library (buttons plugin). Shared by every character.\n')
    f:write('return ' .. serialize(db) .. '\n')
    f:close()
    if not opts.silent then setStatus('Saved.') end
    -- Tell the other boxes on this computer to reload the shared file.
    if prefs.syncBoxes and not opts.noBroadcast and core and core.boxnet and core.boxnet.broadcast then
        pcall(core.boxnet.broadcast, 'buttons_saved', { at = os.time() })
        state.lastBroadcast = os.clock()
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Button Master compatibility (share strings + config import)
-- ----------------------------------------------------------------------------
local function timerFromBm(name)
    for _, t in ipairs(TIMER_TYPES) do
        if t.bm == name then return t.id end
    end
    return 'None'
end

local function timerToBm(id)
    for _, t in ipairs(TIMER_TYPES) do
        if t.id == id then return t.bm end
    end
    return nil
end

local function rgbFromBm(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local parts = split(s, ',')
    local r, g, b = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
    if not (r and g and b) then return nil end
    return { math.floor(r), math.floor(g), math.floor(b) }
end

local function rgbToBm(t)
    if type(t) ~= 'table' or #t < 3 then return nil end
    return string.format('%d,%d,%d', math.floor(t[1]), math.floor(t[2]), math.floor(t[3]))
end

-- Button Master button table -> Triune button.
local function buttonFromBm(bm)
    if type(bm) ~= 'table' then return nil end
    local b = {
        label         = tostring(bm.Label or ''),
        cmd           = tostring(bm.Cmd or ''),
        icon          = tonumber(bm.Icon),
        iconType      = (bm.IconType == 'Item') and 'Item' or 'Spell',
        buttonColor   = rgbFromBm(bm.ButtonColorRGB),
        textColor     = rgbFromBm(bm.TextColorRGB),
        showLabel     = (bm.ShowLabel ~= false),
        evaluateLabel = (bm.EvaluateLabel == true),
        iconLua       = (type(bm.IconLua) == 'string' and bm.IconLua ~= '') and bm.IconLua or nil,
        timerType     = timerFromBm(bm.TimerType),
        updateRate    = tonumber(bm.UpdateRate),
        fontScale     = tonumber(bm.FontScale),   -- Triune extension; Button Master ignores it
    }
    if b.timerType == 'Lua' then
        b.timerLua = type(bm.Timer) == 'string' and bm.Timer or ''
        b.cooldownLua = type(bm.Cooldown) == 'string' and bm.Cooldown or ''
        b.toggleLua = type(bm.ToggleCheck) == 'string' and bm.ToggleCheck or ''
    elseif b.timerType ~= 'None' then
        b.timerKey = bm.Cooldown ~= nil and tostring(bm.Cooldown) or ''
    end
    if b.updateRate == 0 then b.updateRate = nil end
    return normalizeButton(b)
end

-- Triune button -> Button Master button table (for share strings).
local function buttonToBm(b)
    local bm = {
        Label          = b.label or '',
        Cmd            = b.cmd or '',
        Icon           = b.icon and tostring(b.icon) or nil,
        IconType       = b.icon and (b.iconType or 'Spell') or nil,
        ButtonColorRGB = rgbToBm(b.buttonColor),
        TextColorRGB   = rgbToBm(b.textColor),
        ShowLabel      = (b.showLabel ~= false),
        EvaluateLabel  = b.evaluateLabel and true or nil,
        IconLua        = (b.iconLua and b.iconLua ~= '') and b.iconLua or nil,
        TimerType      = timerToBm(b.timerType),
        UpdateRate     = b.updateRate or 0,
        FontScale      = b.fontScale,
    }
    if b.timerType == 'Lua' then
        bm.Timer = b.timerLua or ''
        bm.Cooldown = b.cooldownLua or ''
        bm.ToggleCheck = b.toggleLua or ''
    elseif b.timerType == 'Seconds' then
        bm.Cooldown = tonumber(b.timerKey) or 0
    elseif b.timerType == 'Gem' then
        bm.Cooldown = tonumber(b.timerKey) or 1
    elseif b.timerType ~= 'None' then
        bm.Cooldown = b.timerKey or ''
    end
    return bm
end

local function encodeShare(tbl)
    return b64enc('return ' .. serialize(tbl))
end

local function decodeShare(str)
    str = trim(str)
    if str == '' then return nil, 'empty' end
    local src = b64dec(str)
    if not src or src == '' then return nil, 'not base64' end
    local fn, err = compile(src, 'share', {})
    if not fn then return nil, err end
    local ok, t = pcall(fn)
    if not ok or type(t) ~= 'table' then return nil, 'not a share table' end
    if t.Type ~= 'Button' and t.Type ~= 'Set' then return nil, 'not a Button or Set share' end
    return t
end

-- ----------------------------------------------------------------------------
-- Button / set / hotbar operations
-- ----------------------------------------------------------------------------
local function nextButtonKey()
    local i = 1
    while db.buttons['Button_' .. i] do i = i + 1 end
    return 'Button_' .. i
end

local function uniqueSetName(base)
    base = trim(base)
    if base == '' then base = 'Set' end
    if not db.sets[base] then return base end
    local i = 2
    while db.sets[base .. ' ' .. i] do i = i + 1 end
    return base .. ' ' .. i
end

local function getSet(name)
    local set = db.sets[name]
    if not set then
        set = {}
        db.sets[name] = set
    end
    return set
end

local function buttonAt(setName, index)
    local set = db.sets[setName]
    local key = set and set[index]
    if key and db.buttons[key] then return db.buttons[key], key end
    return nil, nil
end

local function lastAssignedIndex(setName)
    local last = 0
    for idx, key in pairs(db.sets[setName] or {}) do
        if type(idx) == 'number' and db.buttons[key] and idx > last then last = idx end
    end
    return last
end

local function addButton(b, save)
    local key = nextButtonKey()
    db.buttons[key] = normalizeButton(b)
    cache[key] = nil
    if save then saveDb() end
    return key
end

local function assignButton(setName, index, key)
    getSet(setName)[index] = key
    saveDb()
end

local function unassignButton(setName, index)
    local set = db.sets[setName]
    if set then set[index] = nil end
    saveDb()
end

-- Remove a button from the library and every set that references it.
local function deleteButton(key)
    if not db.buttons[key] then return end
    for _, set in pairs(db.sets) do
        for idx, k in pairs(set) do
            if k == key then set[idx] = nil end
        end
    end
    db.buttons[key] = nil
    cache[key] = nil
    saveDb()
end

local function swapSlots(setA, idxA, setB, idxB)
    if setA == setB and idxA == idxB then return end
    local a, b = getSet(setA), getSet(setB)
    a[idxA], b[idxB] = b[idxB], a[idxA]
    saveDb()
end

local function createSet(name)
    name = uniqueSetName(name)
    db.sets[name] = {}
    return name
end

local function deleteSet(name)
    db.sets[name] = nil
    for _, c in pairs(db.characters) do
        for _, hb in ipairs(c.hotbars or {}) do
            for i = #hb.sets, 1, -1 do
                if hb.sets[i] == name then table.remove(hb.sets, i) end
            end
        end
    end
    saveDb()
end

local function renameSet(from, to)
    to = trim(to)
    if to == '' or to == from or not db.sets[from] then return false end
    if db.sets[to] then return false end
    db.sets[to] = db.sets[from]
    db.sets[from] = nil
    for _, c in pairs(db.characters) do
        for _, hb in ipairs(c.hotbars or {}) do
            for i, s in ipairs(hb.sets) do
                if s == from then hb.sets[i] = to end
            end
        end
    end
    saveDb()
    return true
end

local function hotbarHasSet(hb, name)
    for _, s in ipairs(hb.sets) do
        if s == name then return true end
    end
    return false
end

local function addSetToHotbar(hb, name)
    if not db.sets[name] or hotbarHasSet(hb, name) then return end
    hb.sets[#hb.sets + 1] = name
    saveDb()
end

local function removeSetFromHotbar(hb, name)
    for i = #hb.sets, 1, -1 do
        if hb.sets[i] == name then table.remove(hb.sets, i) end
    end
    saveDb()
end

local function moveSetInHotbar(hb, idx, dir)
    local j = idx + dir
    if idx < 1 or idx > #hb.sets or j < 1 or j > #hb.sets then return end
    hb.sets[idx], hb.sets[j] = hb.sets[j], hb.sets[idx]
    saveDb()
end

local function newHotbarForMe()
    local hbs = hotbars()
    local hb = newHotbar('Hot Buttons ' .. (#hbs + 1))
    hbs[#hbs + 1] = hb
    ctrl.show_buttons = true
    saveDb()
    return #hbs
end

-- Per-hotbar UI state is keyed by hotbar index; removing hotbar `id` shifts
-- every later hotbar down by one, so the maps have to follow.
local function shiftHotbarKeys(t, id)
    local out = {}
    for k, v in pairs(t or {}) do
        if type(k) ~= 'number' or k < id then
            out[k] = v
        elseif k > id then
            out[k - 1] = v
        end
    end
    return out
end

local function deleteHotbar(id)
    local hbs = hotbars()
    if #hbs <= 1 or not hbs[id] then return false end
    table.remove(hbs, id)
    state.activeSet = shiftHotbarKeys(state.activeSet, id)
    state.search = shiftHotbarKeys(state.search, id)
    state.newSetName = shiftHotbarKeys(state.newSetName, id)
    state.titleEdit = shiftHotbarKeys(state.titleEdit, id)
    if edit.hbId > id then edit.hbId = edit.hbId - 1 end
    if imp.hbId > id then imp.hbId = imp.hbId - 1 end
    if browser.target and (browser.target.hbId or 0) > id then browser.target.hbId = browser.target.hbId - 1 end
    saveDb()
    return true
end

local function anyHotbarVisible()
    for _, hb in ipairs(hotbars()) do
        if hb.visible then return true end
    end
    return false
end

-- Copy every hotbar of another character into this one (Button Master's
-- "Copy Local Set").
local function copyHotbarsFrom(otherKey)
    local other = db.characters[otherKey]
    if not other or otherKey == charKey() then return false end
    db.characters[charKey()] = deepcopy(other)
    state.activeSet = {}
    saveDb()
    return true
end

-- Share helpers ---------------------------------------------------------------
local function shareButton(key)
    local b = db.buttons[key]
    if not b then return nil end
    return encodeShare({ Type = 'Button', Button = buttonToBm(b) })
end

local function shareSet(name)
    local set = db.sets[name]
    if not set then return nil end
    local out = { Type = 'Set', Key = name, Set = {}, Buttons = {} }
    for idx, key in pairs(set) do
        if db.buttons[key] then
            out.Set[idx] = key
            out.Buttons[key] = buttonToBm(db.buttons[key])
        end
    end
    return encodeShare(out)
end

local function importShare(t, hb)
    if type(t) ~= 'table' then return false, 'invalid' end
    if t.Type == 'Button' then
        local b = buttonFromBm(t.Button)
        if not b then return false, 'invalid button' end
        local key = addButton(b, false)
        saveDb()
        log('Imported button \at%s\ax as %s. Assign it from a slot\'s right-click menu.', b.label, key)
        return true, key
    elseif t.Type == 'Set' then
        local name = uniqueSetName(tostring(t.Key or 'Imported'))
        if name ~= t.Key then log('Set \at%s\ax already exists; importing as \at%s\ax.', tostring(t.Key), name) end
        local set = {}
        local count = 0
        for idx, oldKey in pairs(t.Set or {}) do
            local b = buttonFromBm(t.Buttons and t.Buttons[oldKey])
            if b and tonumber(idx) then
                set[tonumber(idx)] = addButton(b, false)
                count = count + 1
            end
        end
        db.sets[name] = set
        if hb and not hotbarHasSet(hb, name) then hb.sets[#hb.sets + 1] = name end
        saveDb()
        log('Imported set \at%s\ax with %d button(s).', name, count)
        return true, name
    end
    return false, 'unknown share type'
end

-- Import a whole ButtonMaster.lua (buttons, sets, and this character's windows).
local function importButtonMasterConfig(path)
    path = path or plugin.bmConfigPath()
    local fn = loadfile(path)
    if not fn then return false, 'Could not read ' .. tostring(path) end
    local ok, bm = pcall(fn)
    if not ok or type(bm) ~= 'table' then return false, 'Not a Button Master config' end
    if (tonumber(bm.Version) or 0) < 5 or type(bm.Buttons) ~= 'table' or type(bm.Sets) ~= 'table' then
        return false, 'Unsupported Button Master config (run `/lua run buttonmaster upgrade` first)'
    end
    local keyMap = {}
    local nButtons, nSets, nBars = 0, 0, 0
    for oldKey, bmBtn in pairs(bm.Buttons) do
        local b = buttonFromBm(bmBtn)
        if b then
            keyMap[oldKey] = addButton(b, false)
            nButtons = nButtons + 1
        end
    end
    local setMap = {}
    for oldName, bmSet in pairs(bm.Sets) do
        local name = uniqueSetName(tostring(oldName))
        local set = {}
        for idx, oldKey in pairs(bmSet or {}) do
            if tonumber(idx) and keyMap[oldKey] then set[tonumber(idx)] = keyMap[oldKey] end
        end
        db.sets[name] = set
        setMap[oldName] = name
        nSets = nSets + 1
    end
    local bmChar = bm.Characters and bm.Characters[charKey()]
    if bmChar and type(bmChar.Windows) == 'table' then
        local hbs = hotbars()
        for _, w in ipairs(bmChar.Windows) do
            local hb = newHotbar(tostring(w.Title or ('Hot Buttons ' .. (#hbs + 1))))
            hb.visible = (w.Visible ~= false)
            hb.locked = (w.Locked == true)
            hb.hideTitleBar = (w.HideTitleBar == true)
            hb.hideScrollbar = (w.HideScrollbar == true)
            hb.compact = (w.CompactMode == true)
            hb.perCharPos = (w.PerCharacterPositioning == true)
            hb.showSearch = (w.ShowSearch == true)
            hb.advTooltips = (w.AdvTooltips == true)
            hb.buttonSize = math.max(MIN_BUTTON_SIZE, math.min(MAX_BUTTON_SIZE, math.floor(tonumber(w.ButtonSize) or 6)))
            hb.fontScale = (tonumber(w.Font) or 10) / 10
            for _, s in ipairs(w.Sets or {}) do
                if setMap[s] then hb.sets[#hb.sets + 1] = setMap[s] end
            end
            hbs[#hbs + 1] = hb
            nBars = nBars + 1
        end
    end
    saveDb()
    local msg = string.format('Imported %d button(s), %d set(s), %d hotbar(s) from Button Master.', nButtons, nSets, nBars)
    log(msg)
    state.bmImportResult = msg
    return true, msg
end

-- ----------------------------------------------------------------------------
-- Cooldowns / labels / icons (cached per button, evaluated at updateRate)
-- ----------------------------------------------------------------------------
local function cacheFor(key)
    local c = cache[key]
    if not c then
        c = { label = nil, remaining = 0, total = 0, locked = false, seenMax = 0, lastEval = -1, icon = nil, iconType = nil }
        cache[key] = c
    end
    return c
end

local function num(v)
    local n = tonumber(v)
    if n == nil or n ~= n then return 0 end
    return n
end

-- Timer readers as named functions: pcall(fn, arg) allocates nothing per
-- call, unlike the tlo(function() ... end) closure pattern, and the cooldown
-- poll runs for every cooling button at 10 Hz (or every frame).
local TIMER = {
    gemTimer     = function(gem) return mq.TLO.Me.GemTimer(gem)() end,
    gemRecast    = function(gem) return mq.TLO.Me.Gem(gem).RecastTime() end,
    aaTimer      = function(key) return mq.TLO.Me.AltAbilityTimer(key)() end,
    aaReuse      = function(key) return mq.TLO.Me.AltAbility(key).MyReuseTime() end,
    discTimer    = function(name) return mq.TLO.Me.CombatAbilityTimer(name).TotalSeconds() end,
    spellRecast  = function(name) return mq.TLO.Spell(name).RecastTime() end,
    abilityTimer = function(name) return mq.TLO.Me.AbilityTimer(name)() end,
    abilityTotal = function(name) return mq.TLO.Me.AbilityTimerTotal(name)() end,
    itemTimer    = function(name) return mq.TLO.FindItem(name).TimerReady() end,
    -- Full duration of a game timer (gem recast, AA reuse, disc recast) is
    -- static: read it once per button and refresh it every TOTAL_TTL seconds
    -- (sooner while it reads as 0, e.g. a gem that is not memorized yet).
    -- Editing the button drops its cache entry and so the value.
    TOTAL_TTL    = 30,
    TOTAL_RETRY  = 5,
}

function TIMER.call(fn, arg)
    local ok, v = pcall(fn, arg)
    if ok then return v end
    return nil
end

function TIMER.staticTotal(c, tt, arg, now)
    if c.totalKind == tt and c.totalArg == arg and c.totalAt then
        local ttl = (c.staticTotal or 0) > 0 and TIMER.TOTAL_TTL or TIMER.TOTAL_RETRY
        if (now - c.totalAt) < ttl then return c.staticTotal end
    end
    local total = 0
    if tt == 'Gem' then
        total = num(TIMER.call(TIMER.gemRecast, arg)) / 1000
    elseif tt == 'AA' then
        total = num(TIMER.call(TIMER.aaReuse, arg))
    elseif tt == 'Disc' then
        total = num(TIMER.call(TIMER.spellRecast, arg)) / 1000
    end
    c.totalKind, c.totalArg, c.totalAt, c.staticTotal = tt, arg, now, total
    return total
end

-- Trimmed timer key, cached on the entry (trim() allocates per call).
function TIMER.keyOf(b, c)
    if c.keySrc ~= b.timerKey or c.keyTrim == nil then
        c.keySrc = b.timerKey
        c.keyTrim = trim(b.timerKey)
    end
    return c.keyTrim
end

-- Returns remaining seconds, total seconds, toggle-locked.
local function readCooldown(b, c)
    local tt = b.timerType or 'None'
    local key = b.timerKey
    local remaining, total, locked = 0, 0, false
    if tt == 'None' then
        return 0, 0, false
    elseif tt == 'Seconds' then
        total = num(key)
        if c.firedAt and total > 0 then
            remaining = total - (os.clock() - c.firedAt)
            if remaining <= 0 then
                remaining = 0
                c.firedAt = nil
            end
        end
    elseif tt == 'Gem' then
        local gem = math.floor(num(key))
        if gem >= 1 then
            remaining = num(TIMER.call(TIMER.gemTimer, gem)) / 1000
            total = TIMER.staticTotal(c, tt, gem, os.clock())
        end
    elseif tt == 'AA' then
        local name = TIMER.keyOf(b, c)
        if name ~= '' then
            local arg = tonumber(name) or name
            remaining = num(TIMER.call(TIMER.aaTimer, arg)) / 1000
            total = TIMER.staticTotal(c, tt, arg, os.clock())
        end
    elseif tt == 'Disc' then
        local name = TIMER.keyOf(b, c)
        if name ~= '' then
            remaining = num(TIMER.call(TIMER.discTimer, name))
            total = TIMER.staticTotal(c, tt, name, os.clock())
        end
    elseif tt == 'Ability' then
        local name = TIMER.keyOf(b, c)
        if name ~= '' then
            remaining = num(TIMER.call(TIMER.abilityTimer, name)) / 1000
            total = num(TIMER.call(TIMER.abilityTotal, name)) / 1000
        end
    elseif tt == 'Item' then
        local name = TIMER.keyOf(b, c)
        if name ~= '' then
            remaining = num(TIMER.call(TIMER.itemTimer, name))
        end
    elseif tt == 'Lua' then
        if b.timerLua and b.timerLua ~= '' then
            local ok, res = evalCached(c, 'timer', b.timerLua, b.label)
            if ok then remaining = num(res) elseif not c.warnedTimer then
                c.warnedTimer = true
                log('\arTimer Lua failed for [%s]: %s', b.label or '?', tostring(res))
            end
        end
        if b.cooldownLua and b.cooldownLua ~= '' then
            local ok, res = evalCached(c, 'cooldown', b.cooldownLua, b.label)
            if ok then total = num(res) elseif not c.warnedCooldown then
                c.warnedCooldown = true
                log('\arCooldown Lua failed for [%s]: %s', b.label or '?', tostring(res))
            end
        end
        if b.toggleLua and b.toggleLua ~= '' then
            local ok, res = evalCached(c, 'toggle', b.toggleLua, b.label)
            if ok then locked = (res == true) elseif not c.warnedToggle then
                c.warnedToggle = true
                log('\arToggle Lua failed for [%s]: %s', b.label or '?', tostring(res))
            end
        end
    end
    remaining = math.max(0, remaining)
    if remaining > c.seenMax then c.seenMax = remaining end
    if remaining <= 0 then c.seenMax = 0 end
    if total <= 0 or total < remaining then total = c.seenMax end
    return remaining, total, locked
end

local function evaluateButton(b, key, force)
    local c = cacheFor(key)
    local now = os.clock()
    local rate = b.updateRate
    if rate == nil then rate = DEFAULT_RATE end
    if rate < 0 then rate = 0 end
    if not force and c.lastEval >= 0 then
        if rate > 0 then
            if (now - c.lastEval) < rate then return c end
        elseif c.lastFrame == state.frame then
            -- "Every frame": at most once per drawn frame, even when the
            -- button sits in several sets or hotbars.
            return c
        end
    end
    c.lastEval = now
    c.lastFrame = state.frame
    c.remaining, c.total, c.locked = readCooldown(b, c)
    -- Label
    local label = b.label or ''
    if b.evaluateLabel and label ~= '' then
        local ok, res = evalCached(c, 'label', label, label)
        if ok and res ~= nil then label = tostring(res) elseif not ok and not c.warnedLabel then
            c.warnedLabel = true
            log('\arLabel Lua failed for [%s]: %s', b.label or '?', tostring(res))
        end
    end
    c.label = label
    -- Icon
    c.icon, c.iconType = b.icon, b.iconType
    if b.iconLua and b.iconLua ~= '' then
        local ok, id, typ = evalCached(c, 'icon', b.iconLua, b.label)
        if ok and tonumber(id) then
            c.icon = tonumber(id)
            c.iconType = (typ == 'Item') and 'Item' or 'Spell'
        end
    end
    return c
end

-- ----------------------------------------------------------------------------
-- Execution (immediate on click; `--lua` buttons run as pumped coroutines)
-- ----------------------------------------------------------------------------
local function isLuaButton(cmd)
    local first = lines(cmd)[1]
    return first ~= nil and first:match('^%-%-%s?lua') ~= nil
end

local MAX_SCRIPTS = 16

-- Inside a script coroutine: wait `ms` (or until cond() is true) by yielding
-- back to the pump every frame. Returns true when the condition fired.
local function scriptDelay(ms, cond)
    local deadline = os.clock() + (tonumber(ms) or 0) / 1000
    while true do
        if cond then
            local ok, res = pcall(cond)
            if ok and res then return true end
        end
        if os.clock() >= deadline then return false end
        coroutine.yield()
    end
end

local function runLuaButton(b, key)
    if #state.scripts >= MAX_SCRIPTS then
        log('\arButton [%s] not started: %d scripts are already running.', b.label or key or '?', #state.scripts)
        return false
    end
    local fn, err = compile(b.cmd or '', 'button:' .. (b.label or ''), luaEnv(scriptDelay))
    if not fn then
        log('\arButton [%s] Lua error: %s', b.label or '?', tostring(err))
        return false
    end
    state.scripts[#state.scripts + 1] = { co = coroutine.create(fn), label = b.label or key or '?', startedAt = os.clock() }
    return true
end

-- Resumes every running script once. Called each frame from onDrawUI and
-- each core pass from onTick, so scripts keep moving even with no window.
local function pumpScripts()
    if #state.scripts == 0 then return end
    for i = #state.scripts, 1, -1 do
        local sc = state.scripts[i]
        local ok, err = coroutine.resume(sc.co)
        if not ok then
            log('\arButton [%s] Lua error: %s', sc.label, tostring(err))
            table.remove(state.scripts, i)
        elseif coroutine.status(sc.co) == 'dead' then
            table.remove(state.scripts, i)
        end
    end
end

-- Box-control buttons made with the "Hotbar switch" scope carry `{scope}`;
-- the hotbar's own Group / Zone / All switch decides where they go.
local function usesBoxScope(cmd)
    return type(cmd) == 'string' and cmd:find(BOX_SCOPE_TOKEN, 1, true) ~= nil
end

local function hotbarUsesBoxScope(hb)
    for _, setName in ipairs(hb and hb.sets or {}) do
        for _, key in pairs(db.sets[setName] or {}) do
            local b = db.buttons[key]
            if b and usesBoxScope(b.cmd) then return true end
        end
    end
    return false
end

local function hotbarBoxScope(hb)
    local sc = hb and hb.boxScope
    if sc ~= 'group' and sc ~= 'zone' and sc ~= 'all' then sc = 'all' end
    return sc
end

local function barScopeLabel(scope)
    for _, sc in ipairs(BAR_SCOPES) do
        if sc.id == scope then return sc.desc end
    end
    return scope
end

-- The hotbar whose switch a set answers to: the one passed in, else the first
-- of this character's hotbars showing the set, else the first hotbar (so
-- /ac btn exec and the /btnexec bind resolve the same way a click does).
local function hotbarForSet(setName, hb)
    if hb then return hb end
    local hbs = hotbars()
    for _, h in ipairs(hbs) do
        if setName and hotbarHasSet(h, setName) then return h end
    end
    return hbs[1]
end

local function resolveBoxScope(cmd, hb)
    if not usesBoxScope(cmd) then return cmd end
    return (cmd:gsub('{scope}', hotbarBoxScope(hb)))   -- the token has no pattern magic
end

local function setHotbarBoxScope(hb, scope, hbId)
    if not hb or hotbarBoxScope(hb) == scope then return false end
    if scope ~= 'group' and scope ~= 'zone' and scope ~= 'all' then return false end
    hb.boxScope = scope
    saveDb({ silent = true })
    setStatus('%s: box-control buttons now send to %s.', hb.title or ('Hotbar ' .. tostring(hbId or '')), barScopeLabel(scope):lower())
    return true
end

local function runButton(b, key, hb)
    if not b then return end
    local cmd = resolveBoxScope(b.cmd or '', hb)
    if prefs.announceRun then log('Running \at%s\ax', b.label or key or '?') end
    if isLuaButton(cmd) then
        if runLuaButton(b, key) then pumpScripts() end
    else
        for i, line in ipairs(lines(cmd)) do
            local l = trim(line)
            if l ~= '' and not l:match('^#') and not l:match('^%-%-') and not l:match('^|') then
                if l:sub(1, 1) == '/' then
                    mq.cmd(l)
                else
                    log('\arInvalid command on line %d of [%s]: %s', i, b.label or '?', l)
                end
            end
        end
    end
    if b.timerType == 'Seconds' and key then
        local c = cacheFor(key)
        c.firedAt = os.clock()
        c.lastEval = -1
    end
end

-- Fires the button in a slot right now. Returns false for an empty slot.
-- `hb` is the hotbar that was clicked; without one, a `{scope}` button asks
-- the first hotbar showing the set.
local function fireButton(setName, index, hb)
    local b, key = buttonAt(setName, index)
    if not b then return false end
    if usesBoxScope(b.cmd) then hb = hotbarForSet(setName, hb) end
    runButton(b, key, hb)
    return true
end

local function execBySetIndex(setName, index)
    index = tonumber(index)
    if not setName or not index or not db.sets[setName] then return false end
    return fireButton(setName, math.floor(index))
end

-- Per core pass: shared-file reloads, the Box Network subscription, and a
-- script pump for when no frame is being drawn.
local function tick()
    if state.reloadPending then
        state.reloadPending = false
        loadDb()
        setStatus('Reloaded (another box saved).')
    end
    if not state.boxnetUnsub and prefs.syncBoxes and core.boxnet and core.boxnet.subscribe then
        local ok, unsub = pcall(core.boxnet.subscribe, 'buttons_saved', function()
            -- Our own broadcast is dropped by boxnet; anything else means reload.
            state.reloadPending = true
        end)
        if ok and type(unsub) == 'function' then state.boxnetUnsub = unsub end
    end
    pumpScripts()
    browser.processScans()
end

-- ----------------------------------------------------------------------------
-- Cursor capture (spell gem / item / ability / disc / AA / social / command)
-- ----------------------------------------------------------------------------
local function cursorAttachmentType()
    local typ = tlo(function() return mq.TLO.CursorAttachment.Type() end)
    if typ == nil or tostring(typ) == '' or tostring(typ):upper() == 'NULL' then return nil end
    return tostring(typ):lower()
end

local function buttonFromCursor()
    local t = cursorAttachmentType()
    if not t then return nil end
    local ca = mq.TLO.CursorAttachment
    local b = normalizeButton({ label = '', cmd = '', timerType = 'None' })
    local buttonText = tostring(tlo(function() return ca.ButtonText() end) or ''):gsub('\n', ' ')

    if t == 'item' or t == 'item_link' then
        local name = tlo(function() return ca.Item.Name() end) or tlo(function() return ca.Item() end)
        if not name or tostring(name) == '' then return nil end
        name = tostring(name)
        b.label = name
        b.cmd = string.format('/useitem "%s"', name)
        local ic = tonumber(tlo(function() return ca.Item.Icon() end)) or 0
        if ic >= EQ_ICON_OFFSET then
            b.icon, b.iconType = ic - EQ_ICON_OFFSET, 'Item'
        end
        b.timerType, b.timerKey = 'Item', name
    elseif t == 'spell_gem' then
        local rank = tlo(function() return ca.Spell.RankName() end)
        local spellName = (rank and tostring(rank) ~= '') and tostring(rank) or tostring(tlo(function() return ca.Spell.Name() end) or '')
        if spellName == '' then return nil end
        local gem = tonumber(tlo(function() return mq.TLO.Me.Gem(spellName)() end)) or 0
        if gem <= 0 then gem = (tonumber(tlo(function() return ca.Index() end)) or 0) + 1 end
        if gem <= 0 then gem = 1 end
        b.label = spellName
        b.cmd = string.format('/cast %d', gem)
        local ic = tonumber(tlo(function() return ca.Spell.SpellIcon() end))
        if ic and ic > 0 then b.icon, b.iconType = ic, 'Spell' end
        b.timerType, b.timerKey = 'Gem', tostring(gem)
    elseif t == 'skill' or t == 'ability' then
        if buttonText == '' then return nil end
        b.label = buttonText
        b.cmd = string.format('/doability "%s"', buttonText)
        b.timerType, b.timerKey = 'Ability', buttonText
    elseif t == 'melee_ability' or t == 'combat_ability' then
        if buttonText == '' then return nil end
        b.label = buttonText
        b.cmd = string.format('/disc %s', buttonText)
        local ic = tonumber(tlo(function() return mq.TLO.Spell(buttonText).SpellIcon() end))
        if ic and ic > 0 then b.icon, b.iconType = ic, 'Spell' end
        b.timerType, b.timerKey = 'Disc', buttonText
    elseif t == 'social' then
        local idx = tonumber(tlo(function() return ca.Index() end)) or 0
        b.label = buttonText ~= '' and buttonText or 'Social'
        if idx + 1 > 120 then
            -- AA hot buttons live past the social range
            b.cmd = string.format('/alt act %d', idx - 120)
            b.timerType, b.timerKey = 'AA', buttonText
        else
            local parts = {}
            for ci = 0, 4 do
                local c = tlo(function() return mq.TLO.Social(idx + 1).Cmd(ci)() end)
                if c and tostring(c) ~= '' and tostring(c):upper() ~= 'NULL' then parts[#parts + 1] = tostring(c) end
            end
            if #parts == 0 then return nil end
            b.cmd = table.concat(parts, '\n')
        end
    elseif t == 'memorize_spell' then
        local nm = tlo(function() return ca.Spell.Name() end)
        if not nm or tostring(nm) == '' then return nil end
        b.label = tostring(nm)
        b.cmd = string.format('/memorize "%s"', b.label)
        local ic = tonumber(tlo(function() return ca.Spell.SpellIcon() end))
        if ic and ic > 0 then b.icon, b.iconType = ic, 'Spell' end
    elseif t == 'command' then
        if buttonText == '' then return nil end
        b.label = buttonText:match('^/(%S+)') or 'Command'
        b.cmd = buttonText
    else
        return nil
    end
    return b
end

-- ----------------------------------------------------------------------------
-- Editor / picker / import window state helpers
-- ----------------------------------------------------------------------------
local function timerIdxFor(id)
    for i, t in ipairs(TIMER_TYPES) do
        if t.id == id then return i end
    end
    return 1
end

local function rateIdxFor(rate)
    for i, r in ipairs(UPDATE_RATES) do
        if r.value == rate then return i end
    end
    return 1
end

local function openEditor(hbId, setName, index, prefill)
    local b, key = buttonAt(setName, index)
    edit.open = true
    edit.hbId = hbId
    edit.setName = setName
    edit.index = index
    edit.key = key
    edit.tmp = prefill and deepcopy(prefill) or (b and deepcopy(b)) or normalizeButton({ label = '', cmd = '', timerType = 'None' })
    edit.dirty = (prefill ~= nil)
    edit.timerIdx = timerIdxFor(edit.tmp.timerType)
    edit.rateIdx = rateIdxFor(edit.tmp.updateRate)
    edit.advanced = (edit.tmp.evaluateLabel == true) or (edit.tmp.iconLua ~= nil and edit.tmp.iconLua ~= '')
end

local function closeEditor()
    edit.open = false
    edit.tmp = nil
    edit.dirty = false
    picker.open = false
end

local function saveEditor()
    local t = edit.tmp
    if not t then return false end
    if trim(t.label) == '' then
        setStatus('Save failed: the label cannot be empty.')
        return false
    end
    t.timerType = TIMER_TYPES[edit.timerIdx] and TIMER_TYPES[edit.timerIdx].id or 'None'
    t.updateRate = UPDATE_RATES[edit.rateIdx] and UPDATE_RATES[edit.rateIdx].value or nil
    normalizeButton(t)
    if edit.key and db.buttons[edit.key] then
        db.buttons[edit.key] = deepcopy(t)
        cache[edit.key] = nil
    else
        edit.key = addButton(deepcopy(t), false)
    end
    if edit.setName and edit.index and edit.index > 0 then
        getSet(edit.setName)[edit.index] = edit.key
    end
    saveDb()
    edit.dirty = false
    return true
end

local function slotClicked(hbId, setName, index)
    if fireButton(setName, index, hotbars()[hbId]) then return end
    local fromCursor = buttonFromCursor()
    openEditor(hbId, setName, index, fromCursor)
    if fromCursor then setStatus('Captured %s from the cursor - review and Save.', fromCursor.label) end
end

-- ----------------------------------------------------------------------------
-- "Add From Game" browser: scans
-- ----------------------------------------------------------------------------
-- Every entry: { name, sub (rank / gem / level text), icon, iconType, button }
-- where `button` is the ready-to-save Triune button.
local function scanAAs()
    local out, seen = {}, {}
    for _, range in ipairs(AA_ID_RANGES) do
        for idx = range[1], range[2] do
            pcall(function()
                local ma = mq.TLO.Me.AltAbility(idx)
                if not (ma and ma()) then return end
                local name = ma.Name and ma.Name()
                if not name or name == '' or seen[name] then return end
                local rank = tonumber(ma.Rank and ma.Rank() or 0) or 0
                if rank <= 0 then return end
                -- Activatable AAs carry a spell; passives do not.
                local spellId = tonumber(ma.Spell and ma.Spell.ID and ma.Spell.ID() or 0) or 0
                if spellId <= 0 then return end
                local id = tonumber(ma.ID and ma.ID() or idx) or idx
                local maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0
                local icon = tonumber(ma.Spell.SpellIcon and ma.Spell.SpellIcon() or 0) or 0
                seen[name] = true
                out[#out + 1] = {
                    name = tostring(name),
                    sub = maxRank > 0 and string.format('Rank %d/%d', rank, maxRank) or string.format('Rank %d', rank),
                    icon = icon > 0 and icon or nil, iconType = 'Spell',
                    button = { label = tostring(name), cmd = string.format('/alt act %d', id), icon = icon > 0 and icon or nil, iconType = 'Spell', timerType = 'AA', timerKey = tostring(name) },
                }
            end)
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

local function scanGems()
    local out = {}
    local n = (core.getNumGems and core.getNumGems()) or tonumber(tlo(function() return mq.TLO.Me.NumGems() end)) or 8
    for g = 1, n do
        local name = tlo(function() return mq.TLO.Me.Gem(g).Name() end)
        name = (name and tostring(name) ~= '' and tostring(name):upper() ~= 'NULL') and tostring(name) or nil
        local icon = name and tonumber(tlo(function() return mq.TLO.Me.Gem(g).SpellIcon() end)) or nil
        out[#out + 1] = {
            name = name or '(empty gem)',
            sub = string.format('Gem %d', g),
            icon = icon and icon > 0 and icon or nil, iconType = 'Spell',
            empty = (name == nil),
            button = { label = name or ('Gem ' .. g), cmd = string.format('/cast %d', g), icon = icon and icon > 0 and icon or nil, iconType = 'Spell', timerType = 'Gem', timerKey = tostring(g) },
        }
    end
    return out
end

local function scanAbilities()
    local out = {}
    local list = nil
    if core.runtime and core.runtime.getClientAbilities then
        local ok, res = pcall(core.runtime.getClientAbilities)
        if ok and type(res) == 'table' then list = res end
    end
    for _, a in ipairs(list or {}) do
        if type(a) == 'table' and type(a.name) == 'string' and a.name ~= '' and a.isTrained ~= false then
            out[#out + 1] = {
                name = a.name,
                sub = (a.currentSkill and a.currentSkill > 0) and string.format('Skill %d', a.currentSkill) or '',
                icon = nil, iconType = 'Spell',
                button = { label = a.name, cmd = string.format('/doability "%s"', a.name), timerType = 'Ability', timerKey = a.name },
            }
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- Me.CombatAbilityCount is not available on every client, so the disc list
-- probes Me.CombatAbility(i) slot by slot and stops after a long run of
-- empty slots (the list is dense on live and emu alike).
local DISC_MAX_SLOTS   = 400
local DISC_EMPTY_LIMIT = 60

local function scanDiscs()
    local out, seen = {}, {}
    local count = tonumber(tlo(function() return mq.TLO.Me.CombatAbilityCount() end)) or 0
    local limit = (count > 0) and count or DISC_MAX_SLOTS
    local emptyRun = 0
    for i = 1, limit do
        local found = false
        pcall(function()
            local ca = mq.TLO.Me.CombatAbility(i)
            if not ca then return end
            local name = ca.Name and ca.Name()
            if (name == nil or name == '' or tostring(name):upper() == 'NULL') and type(ca) == 'function' then name = ca() end
            if not name or name == '' or tostring(name):upper() == 'NULL' then return end
            name = tostring(name)
            found = true
            if seen[name] then return end
            seen[name] = true
            local level = tonumber(ca.Level and ca.Level() or 0) or 0
            local icon = tonumber(ca.SpellIcon and ca.SpellIcon() or 0) or 0
            out[#out + 1] = {
                name = tostring(name),
                sub = level > 0 and string.format('Level %d', level) or '',
                icon = icon > 0 and icon or nil, iconType = 'Spell',
                button = { label = tostring(name), cmd = string.format('/disc %s', name), icon = icon > 0 and icon or nil, iconType = 'Spell', timerType = 'Disc', timerKey = tostring(name) },
            }
        end)
        if found then
            emptyRun = 0
        else
            emptyRun = emptyRun + 1
            if count <= 0 and emptyRun >= DISC_EMPTY_LIMIT then break end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

local function scanItems()
    local out, seen = {}, {}
    local function consider(itemObj, where)
        pcall(function()
            if not (itemObj and itemObj()) or (tonumber(itemObj.ID() or 0) or 0) <= 0 then return end
            local c = itemObj.Clicky
            if not (c and c()) then return end
            local spellName = c.Spell and c.Spell() and c.Spell.Name and c.Spell.Name() or nil
            local name = tostring(itemObj.Name() or '')
            if name == '' or seen[name] then return end
            seen[name] = true
            local icon = tonumber(itemObj.Icon() or 0) or 0
            local cell = icon >= EQ_ICON_OFFSET and (icon - EQ_ICON_OFFSET) or nil
            out[#out + 1] = {
                name = name,
                sub = (spellName and spellName ~= '') and (tostring(spellName) .. ' - ' .. where) or where,
                icon = cell, iconType = 'Item',
                button = { label = name, cmd = string.format('/useitem "%s"', name), icon = cell, iconType = 'Item', timerType = 'Item', timerKey = name },
            }
        end)
    end
    for slot = 0, 22 do
        consider(tlo(function() return mq.TLO.Me.Inventory(slot) end), 'Worn')
    end
    for p = 1, 10 do
        local pack = tlo(function() return mq.TLO.Me.Inventory('pack' .. p) end)
        if pack and tlo(function() return pack() end) then
            consider(pack, 'Pack ' .. p)
            local cap = tonumber(tlo(function() return pack.Container() end)) or 0
            for j = 1, cap do
                consider(tlo(function() return pack.Item(j) end), 'Pack ' .. p)
            end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

local function boxScopeLabel(scope)
    for _, sc in ipairs(BOX_SCOPES) do
        if sc.id == scope then return sc.label end
    end
    return scope
end

local function boxPresetButton(preset, scope)
    scope = scope or 'bar'
    local live = scope == 'bar'
    local cmd = preset.cmd:gsub('%%s', live and BOX_SCOPE_TOKEN or scope)
    local suffix = ({ all = 'all', zone = 'zone', group = 'grp' })[scope] or scope
    return {
        -- Live-scope buttons keep the bare name: the switch on the bar says where they go.
        label = live and preset.name or string.format('%s (%s)', preset.name, suffix),
        cmd = cmd,
        buttonColor = preset.color and deepcopy(preset.color) or nil,
        timerType = 'None',
    }
end

local function scanBoxControl()
    local out = {}
    local scope = browser.boxScope or 'bar'
    for _, preset in ipairs(BOX_PRESETS) do
        local b = boxPresetButton(preset, scope)
        out[#out + 1] = { name = preset.name, sub = preset.desc, icon = nil, iconType = 'Spell', button = b }
    end
    return out
end

local function commandNeedsEdit(cmd)
    return tostring(cmd or ''):find('[<%[]') ~= nil
end

local function commandEntry(group, name, cmd, desc)
    return {
        name = name,
        sub = string.format('[%s] %s', group, desc or ''),
        icon = nil, iconType = 'Spell',
        needsEdit = commandNeedsEdit(cmd),
        button = { label = name, cmd = cmd, timerType = 'None' },
    }
end

-- Plugin help lines ('  \ag/ac cursorui | cursorwin\ax - Toggle ...') -> entries.
local function parseHelpLine(line)
    local text = tostring(line or ''):gsub('\a%-?.', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local out = {}
    -- Several "cmd - desc" pairs may share one line (separated by 3+ spaces).
    for part in (text .. '   '):gmatch('(.-)%s%s%s+') do
        local cmd, desc = part:match('^(/%S.-)%s+%-%s+(.+)$')
        if cmd then
            -- "/ac a | b | c" alternatives: keep the first one
            local first = cmd:match('^(.-)%s*|') or cmd
            first = first:gsub('%s+$', '')
            local word = first:match('^/ac%s+(%S+)') or first:match('^/(%S+)') or first
            local name = word:gsub('^%l', string.upper)
            out[#out + 1] = commandEntry('Plugin', name, first, desc)
        end
    end
    return out
end

local function scanCommands()
    local out, seen = {}, {}
    for _, c in ipairs(CORE_COMMANDS) do
        seen[c.cmd] = true
        out[#out + 1] = commandEntry(c.group, c.name, c.cmd, c.desc)
    end
    local pm = core.runtime and core.runtime.pluginManager
    if pm and type(pm.helpLines) == 'function' then
        local ok, helpLines = pcall(pm.helpLines)
        if ok and type(helpLines) == 'table' then
            for _, hl in ipairs(helpLines) do
                for _, e in ipairs(parseHelpLine(hl)) do
                    if not seen[e.button.cmd] then
                        seen[e.button.cmd] = true
                        out[#out + 1] = e
                    end
                end
            end
        end
    end
    return out
end

local SCANNERS = { AA = scanAAs, Gem = scanGems, Ability = scanAbilities, Disc = scanDiscs, Item = scanItems, Box = scanBoxControl, Cmd = scanCommands }

-- Synchronous scan (onTick, tests, the /ac btn add command path). The AA
-- scan alone is ~1,650 ids x up to 8 TLO calls, so the draw thread never
-- calls this: see browserListCached / requestScan.
local function browserList(tab, force)
    if force or not browser.lists[tab] then
        local ok, res = pcall(SCANNERS[tab] or function() return {} end)
        browser.lists[tab] = ok and res or {}
        browser.scanAt[tab] = os.clock()
        browser.scanRequest[tab] = nil
    end
    return browser.lists[tab]
end

function browser.requestScan(tab)
    browser.scanRequest[tab] = true
end

-- Draw-thread view of a tab's list: the cached entries, or nil (with a scan
-- requested for the next tick) while the tab has not been scanned yet.
function browser.listCached(tab)
    local list = browser.lists[tab]
    if list then return list end
    browser.requestScan(tab)
    return nil
end

-- Memorized gems as one string; the Gem list is rebuilt when it changes
-- instead of on every open of the browser (12 cheap TLO calls, on the tick).
function browser.gemFingerprint()
    local n = (core.getNumGems and core.getNumGems()) or tonumber(tlo(function() return mq.TLO.Me.NumGems() end)) or 8
    local parts = {}
    for g = 1, n do
        local name = tlo(function() return mq.TLO.Me.Gem(g).Name() end)
        parts[g] = tostring(name or '')
    end
    return table.concat(parts, '|')
end

-- onTick: one requested scan per pass, plus the gem change check while the
-- browser is open on the Gem tab.
function browser.processScans()
    local tab = next(browser.scanRequest)
    if tab then
        browser.scanRequest[tab] = nil
        browserList(tab, true)
        if tab == 'Gem' then
            browser.gemFp = browser.gemFingerprint()
            browser.gemFpAt = os.clock()
        end
        return
    end
    if browser.open and browser.tab == 'Gem' and browser.lists.Gem then
        local now = os.clock()
        if (now - (browser.gemFpAt or 0)) >= 2.0 then
            browser.gemFpAt = now
            local fp = browser.gemFingerprint()
            -- nil: unknown since the list was built (first open, zoned): rescan once
            if fp ~= browser.gemFp then
                browser.gemFp = fp
                browserList('Gem', true)
            end
        end
    end
end

-- mode 'assign': create the button and place it in target (slot index or the
-- first free slot of the set); mode 'editor': fill the open editor instead.
-- Lists are cached until Refresh, a zone change (items) or a change of the
-- memorized gems (see processBrowserScans).
local function openBrowser(tab, mode, target)
    browser.open = true
    browser.tab = tab or browser.tab
    browser.forceTab = browser.tab
    browser.mode = mode or 'assign'
    browser.target = target
    browser.search = ''
    browser.gemFpAt = 0
end

local function firstFreeSlot(setName)
    local set = getSet(setName)
    for i = 1, MAX_SLOTS do
        if not set[i] then return i end
    end
    return nil
end

local function pickBrowserEntry(entry)
    if not entry or not entry.button then return false end
    local b = normalizeButton(deepcopy(entry.button))
    -- A command with a placeholder argument is finished in the editor.
    if entry.needsEdit and not (browser.mode == 'editor' and edit.open and edit.tmp) then
        local target = browser.target
        if not target or not target.setName or not db.sets[target.setName] then
            setStatus('No set to add to - open the browser from a hotbar.')
            return false
        end
        local index = target.index or firstFreeSlot(target.setName)
        if not index then
            setStatus('Set %s is full (%d slots).', target.setName, MAX_SLOTS)
            return false
        end
        openEditor(target.hbId, target.setName, index, b)
        setStatus('Fill in the <argument> for %s, then Save.', b.label)
        return true
    end
    if browser.mode == 'editor' and edit.open and edit.tmp then
        for k, v in pairs(b) do edit.tmp[k] = v end
        edit.tmp.showLabel = (edit.tmp.icon == nil)
        edit.timerIdx = timerIdxFor(edit.tmp.timerType)
        edit.dirty = true
        setStatus('Filled the editor from %s.', b.label)
        return true
    end
    local target = browser.target
    if not target or not target.setName or not db.sets[target.setName] then
        setStatus('No set to add to - open the browser from a hotbar.')
        return false
    end
    local index = target.index or firstFreeSlot(target.setName)
    if not index then
        setStatus('Set %s is full (%d slots).', target.setName, MAX_SLOTS)
        return false
    end
    -- Icon buttons read better without the label on top.
    if b.icon then b.showLabel = false end
    local key = addButton(b, false)
    getSet(target.setName)[index] = key
    saveDb()
    setStatus('Added %s to %s slot %d.', b.label, target.setName, index)
    -- Placing into a chosen slot is a one-shot; the right-click-menu flow keeps going.
    if target.index then
        browser.open = false
    else
        browser.target = { hbId = target.hbId, setName = target.setName }
    end
    return true
end

-- Creates a "Box Control" set holding every preset for the chosen scope and
-- adds it to the target hotbar. Returns the set name.
local function addBoxControlSet(scope, hb)
    scope = scope or browser.boxScope or 'bar'
    local name = uniqueSetName('Box Control' .. (scope ~= 'bar' and (' (' .. scope .. ')') or ''))
    local set = {}
    for i, preset in ipairs(BOX_PRESETS) do
        set[i] = addButton(boxPresetButton(preset, scope), false)
    end
    db.sets[name] = set
    if hb and not hotbarHasSet(hb, name) then hb.sets[#hb.sets + 1] = name end
    saveDb()
    setStatus('Added set %s with %d box-control buttons.', name, #BOX_PRESETS)
    return name
end

-- ----------------------------------------------------------------------------
-- Rendering helpers
-- ----------------------------------------------------------------------------
local function xy(x, y)
    if type(x) == 'userdata' or (type(x) == 'table' and x.x) then return x.x, x.y end
    return tonumber(x) or 0, tonumber(y) or 0
end

local function textSize(s)
    local ok, w, h = pcall(ImGui.CalcTextSize, s)
    if not ok then return 0, 0 end
    if type(w) ~= 'number' then
        local vx, vy = xy(w)
        return vx, vy
    end
    return w or 0, h or 0
end

local function contentAvail()
    local ok, w, h = pcall(ImGui.GetContentRegionAvail)
    if not ok then return 300, 200 end
    if type(w) ~= 'number' then return xy(w) end
    return w or 0, h or 0
end

local function rgbTo01(t, fallback)
    if type(t) == 'table' and #t >= 3 then
        return (tonumber(t[1]) or 0) / 255, (tonumber(t[2]) or 0) / 255, (tonumber(t[3]) or 0) / 255
    end
    return fallback[1], fallback[2], fallback[3]
end

local function pushSlider(id, val, mn, mx, fmt)
    local ok, res = pcall(ImGui.SliderFloat, id, val, mn, mx, fmt)
    if ok and type(res) == 'number' then return res end
    return val
end

-- Push a style var only when the enum exists (the sandboxed test harness has
-- no ImGui globals); returns 1 when something was pushed.
local function pushStyleVarSafe(name, a, b)
    local SV = ImGuiStyleVar
    if not SV or SV[name] == nil then return 0 end
    local ok = pcall(ImGui.PushStyleVar, SV[name], a, b)
    return ok and 1 or 0
end

local function popStyleVarsSafe(n)
    if n and n > 0 then pcall(ImGui.PopStyleVar, n) end
end

-- Defined after the grid (it needs the slot renderer's neighbours); the slot
-- context menu embeds it as a submenu.
local drawHotbarMenu

-- Grid geometry for one set inside the current content region.
local function gridLayout(hb, setName, availW, availH)
    local size = core.px((hb.buttonSize or 6) * 10)
    local cols = math.max(1, math.floor((availW + GRID_SPACING) / (size + GRID_SPACING)))
    local rows = math.max(1, math.floor((availH + GRID_SPACING) / (size + GRID_SPACING)))
    local count = math.min(MAX_SLOTS, cols * rows)
    local last = lastAssignedIndex(setName)
    if last % cols ~= 0 then last = last + (cols - (last % cols)) end
    count = math.min(MAX_SLOTS, math.max(count, last, cols))
    return size, cols, count
end

-- Cooldown sweep: a pie over the remaining fraction, clipped to the slot.
-- A named function so the per-frame pcall allocates no closure.
local SLOT = {}

function SLOT.sweep(dl, p1, p2, center, radius, aMin, aMax, col)
    dl:PushClipRect(p1, p2, true)
    dl:PathLineTo(center)
    dl:PathArcTo(center, radius, aMin, aMax, 0)
    dl:PathFillConvex(col)
    dl:PopClipRect()
end

-- Label layout (words stacked as lines, merged into the last line when they
-- do not fit) with each word measured once. Cached on the button's entry and
-- rebuilt only when the label, the font scale or the slot size changes;
-- must be computed with the slot's font scale active.
function SLOT.layoutLabel(label, scale, size)
    local words = split(label, ' ')
    local _, lineH = textSize('Ag')
    lineH = math.max(1, lineH)
    local maxLines = math.max(1, math.floor((size - 4) / lineH))
    if #words > maxLines then
        local merged = {}
        for i = 1, maxLines do merged[i] = words[i] end
        merged[maxLines] = merged[maxLines] .. ' ' .. table.concat(words, ' ', maxLines + 1)
        words = merged
    end
    local widths = {}
    for i = 1, #words do widths[i] = (textSize(words[i])) end
    return { label = label, scale = scale, size = size, words = words, widths = widths, lineH = lineH, blockH = #words * lineH }
end

-- Draws one slot. Returns true when clicked.
local function drawSlot(hb, hbId, setName, index, size, dimmed)
    local b, key = buttonAt(setName, index)
    local c = b and evaluateButton(b, key) or nil
    local toV = core.toVec
    local col32 = core.col32

    ImGui.PushID(index)
    local clicked = ImGui.InvisibleButton('##slot', size, size)
    local hovered = ImGui.IsItemHovered()
    local active = ImGui.IsItemActive()
    local mnX, mnY = xy(ImGui.GetItemRectMin())
    local mxX, mxY = xy(ImGui.GetItemRectMax())
    local dl = ImGui.GetWindowDrawList()
    local p1, p2 = toV(mnX, mnY), toV(mxX, mxY)
    local alphaMul = dimmed and 0.35 or 1.0

    if dl and p1 and p2 then
        -- Background
        local br, bg, bb = rgbTo01(b and b.buttonColor, { 0.13, 0.18, 0.25 })
        local bgA = b and 0.95 or 0.45
        if hovered and b then br, bg, bb = math.min(1, br + 0.12), math.min(1, bg + 0.12), math.min(1, bb + 0.12) end
        if active and b then br, bg, bb = math.min(1, br + 0.2), math.min(1, bg + 0.2), math.min(1, bb + 0.2) end
        dl:AddRectFilled(p1, p2, col32(br, bg, bb, bgA * alphaMul), 4)

        -- Icon
        if b and c.icon and dl.AddTextureAnimation then
            local anim = iconAnim(c.icon, c.iconType)
            if anim then
                local pad = 2
                local ip = toV(mnX + pad, mnY + pad)
                local isz = toV(size - pad * 2, size - pad * 2)
                if ip and isz then pcall(dl.AddTextureAnimation, dl, anim, ip, isz) end
            end
        end

        -- Cooldown sweep (dark pie over the remaining fraction) + timer text
        if b and c.total > 0 and c.remaining > 0.05 then
            local frac = math.max(0, math.min(1, c.remaining / c.total))
            local drewArc = false
            if dl.PathArcTo and dl.PathFillConvex and dl.PathLineTo then
                local center = toV((mnX + mxX) / 2, (mnY + mxY) / 2)
                local aMin = -math.pi / 2 + 2 * math.pi * (1 - frac)
                local aMax = 1.5 * math.pi
                drewArc = pcall(SLOT.sweep, dl, p1, p2, center, size * 0.8, aMin, aMax, col32(0, 0, 0, 0.62 * alphaMul))
            end
            if not drewArc then
                local oh = (mxY - mnY) * frac
                local q2 = toV(mxX, mnY + oh)
                if q2 then dl:AddRectFilled(p1, q2, col32(0, 0, 0, 0.62 * alphaMul), 4) end
            end
            -- Timer text formats to whole seconds: measure it once per second.
            local secs = math.floor(c.remaining + 0.5)
            if c.tsSec ~= secs or c.tsText == nil then
                c.tsSec = secs
                c.tsText = fmtTime(c.remaining)
                c.tsW, c.tsH = textSize(c.tsText)
            end
            local ts, tw, th = c.tsText, c.tsW, c.tsH
            local tp = toV(mnX + (size - tw) / 2, mnY + (size - th) / 2)
            local tp2 = toV(mnX + (size - tw) / 2 + 1, mnY + (size - th) / 2 + 1)
            if tp2 then dl:AddText(tp2, col32(0, 0, 0, 0.9 * alphaMul), ts) end
            if tp then dl:AddText(tp, col32(1, 1, 1, alphaMul), ts) end
        end

        -- Toggle-locked (Custom Lua toggle check true): gold frame + tint
        if b and c.locked then
            dl:AddRectFilled(p1, p2, col32(1.0, 0.72, 0.25, 0.18 * alphaMul), 4)
            local goldCol = col32(1.0, 0.72, 0.25, 0.95 * alphaMul)
            if not pcall(dl.AddRect, dl, p1, p2, goldCol, 4, 0, 2) then
                dl:AddRect(p1, p2, goldCol, 4)
            end
        elseif hovered then
            dl:AddRect(p1, p2, col32(0.9, 0.9, 0.9, 0.5 * alphaMul), 4)
        else
            dl:AddRect(p1, p2, col32(0.16, 0.25, 0.35, 1.0 * alphaMul), 4)
        end

        -- Label (words stacked as lines, centred) or slot number
        local winScale = core.currentWindowScale and core.currentWindowScale() or 1.0
        local fontScale = ((b and b.fontScale) or hb.fontScale or 1.0) * winScale
        pcall(ImGui.SetWindowFontScale, fontScale)
        if b then
            if b.showLabel ~= false and c.label and c.label ~= '' and not (c.total > 0 and c.remaining > 0.05) then
                local tr, tg, tb = rgbTo01(b.textColor, { 1, 1, 1 })
                local lay = c.layout
                if not lay or lay.label ~= c.label or lay.scale ~= fontScale or lay.size ~= size then
                    lay = SLOT.layoutLabel(c.label, fontScale, size)
                    c.layout = lay
                end
                local words, widths, lineH = lay.words, lay.widths, lay.lineH
                local y = mnY + (size - lay.blockH) / 2
                local shadow, textCol = col32(0, 0, 0, 0.85 * alphaMul), col32(tr, tg, tb, alphaMul)
                pcall(dl.PushClipRect, dl, p1, p2, true)
                for i = 1, #words do
                    local w = words[i]
                    local tx = mnX + math.max(0, (size - widths[i]) / 2)
                    local sp = toV(tx + 1, y + 1)
                    local lp = toV(tx, y)
                    if sp then dl:AddText(sp, shadow, w) end
                    if lp then dl:AddText(lp, textCol, w) end
                    y = y + lineH
                end
                pcall(dl.PopClipRect, dl)
            end
        else
            local ns = tostring(index)
            local tw, th = textSize(ns)
            local np = toV(mnX + (size - tw) / 2, mnY + (size - th) / 2)
            if np then dl:AddText(np, col32(0.5, 0.58, 0.68, 0.7 * alphaMul), ns) end
        end
        pcall(ImGui.SetWindowFontScale, winScale)
    end

    -- Tooltip
    if hovered and not active then
        if b then
            local tip = c.label ~= '' and c.label or (b.label or '')
            if c.remaining > 0.05 then tip = tip .. '\nReady in ' .. fmtTime(c.remaining) end
            if c.locked then tip = tip .. '\n(active)' end
            local liveScope = usesBoxScope(b.cmd)
            if liveScope then tip = tip .. '\nBoxes: ' .. barScopeLabel(hotbarBoxScope(hb)) .. ' (hotbar switch)' end
            if hb.advTooltips and b.cmd and b.cmd ~= '' then
                local shown = lines(liveScope and resolveBoxScope(b.cmd, hb) or b.cmd)
                local extra = ''
                if #shown > 6 then
                    extra = string.format('\n... (%d more lines)', #shown - 6)
                    local cut = {}
                    for i = 1, 6 do cut[i] = shown[i] end
                    shown = cut
                end
                tip = tip .. '\n\n' .. table.concat(shown, '\n') .. extra
            end
            core.setTooltip(tip)
        else
            core.setTooltip(string.format('Slot %d (empty)\nLeft-click: create a button (captures what is on your cursor)\nRight-click: assign an existing button, add from game, hotbar options', index))
        end
    end

    -- Drag and drop: swap the two slots (works across hotbars)
    if b and not clicked then
        local okSrc, src = pcall(ImGui.BeginDragDropSource)
        if okSrc and src then
            state.dnd = { hb = hbId, set = setName, index = index }
            -- The payload only tags the drag; the source slot lives in state.dnd
            -- (set names may contain any character, so nothing is parsed back).
            pcall(ImGui.SetDragDropPayload, 'TRIUNE_BTN', 'slot')
            ImGui.Text(c.label ~= '' and c.label or (b.label or 'Button'))
            pcall(ImGui.EndDragDropSource)
        end
    end
    local okTgt, tgt = pcall(ImGui.BeginDragDropTarget)
    if okTgt and tgt then
        local payload = ImGui.AcceptDragDropPayload('TRIUNE_BTN')
        if payload then
            local src = state.dnd
            if src and src.set and src.index and db.sets[src.set] then
                swapSlots(src.set, src.index, setName, index)
            end
            state.dnd = nil
        end
        pcall(ImGui.EndDragDropTarget)
    end

    -- Context menu
    if ImGui.BeginPopupContextItem('##slotCtx') then
        -- Assign an existing (unassigned-in-this-set) button
        local inSet = {}
        for _, k in pairs(db.sets[setName] or {}) do inSet[k] = true end
        local groups, any = {}, false
        for k, btn in pairs(db.buttons) do
            if not inSet[k] then
                local g = alphaGroupFor(btn.label)
                groups[g] = groups[g] or {}
                table.insert(groups[g], { key = k, label = btn.label ~= '' and btn.label or k })
                any = true
            end
        end
        if any and ImGui.BeginMenu('Assign Button') then
            for _, g in ipairs(ALPHA_GROUPS) do
                local items = groups[g.name]
                if items and #items > 0 then
                    table.sort(items, function(a, bb) return a.label:lower() < bb.label:lower() end)
                    if ImGui.BeginMenu(g.name .. '##assign_' .. g.name) then
                        for _, it in ipairs(items) do
                            if ImGui.MenuItem(it.label .. '##assign_' .. it.key) then
                                assignButton(setName, index, it.key)
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
            end
            ImGui.EndMenu()
        end
        if b then
            if ImGui.MenuItem('Edit') then openEditor(hbId, setName, index) end
            if ImGui.MenuItem('Duplicate') then
                local copy = deepcopy(b)
                copy.label = (b.label or 'Button') .. ' (copy)'
                local nk = addButton(copy, false)
                local set = getSet(setName)
                local free = index
                for i = 1, MAX_SLOTS do
                    if not set[i] then
                        free = i
                        break
                    end
                end
                set[free] = nk
                saveDb()
            end
            if ImGui.MenuItem('Unassign') then unassignButton(setName, index) end
            if ImGui.MenuItem('Delete Button') then deleteButton(key) end
            ImGui.Separator()
            if ImGui.MenuItem('Copy Share String') then
                local s = shareButton(key)
                if s then
                    pcall(ImGui.SetClipboardText, s)
                    setStatus('Button [%s] copied to the clipboard.', b.label)
                end
            end
        else
            if ImGui.MenuItem('Create New Button') then openEditor(hbId, setName, index) end
            if cursorAttachmentType() and ImGui.MenuItem('Create From Cursor') then
                slotClicked(hbId, setName, index)
            end
            ImGui.Separator()
            for _, tab in ipairs(BROWSER_TABS) do
                if ImGui.MenuItem('Add ' .. tab.label .. '...##addfrom_' .. tab.id) then
                    openBrowser(tab.id, 'assign', { hbId = hbId, setName = setName, index = index })
                end
            end
        end
        ImGui.Separator()
        if ImGui.BeginMenu('Hotbar Options') then
            drawHotbarMenu(hb, hbId)
            ImGui.EndMenu()
        end
        ImGui.EndPopup()
    end
    ImGui.PopID()

    return clicked and not dimmed
end

local function drawGrid(hb, hbId, setName, searchText)
    local availW, availH = contentAvail()
    local size, cols, count = gridLayout(hb, setName, availW, availH)
    local search = trim(searchText or ''):lower()
    local pushed = pushStyleVarSafe('ItemSpacing', GRID_SPACING, GRID_SPACING)
    for index = 1, count do
        if index > 1 and (index - 1) % cols ~= 0 then
            ImGui.SameLine(0, GRID_SPACING)
        end
        local dimmed = false
        if search ~= '' then
            local b, key = buttonAt(setName, index)
            if not b then
                dimmed = true
            else
                local c = cacheFor(key)
                local hay = ((c.label or b.label or '') .. '\n' .. (b.cmd or '')):lower()
                dimmed = (hay:find(search, 1, true) == nil)
            end
        end
        if drawSlot(hb, hbId, setName, index, size, dimmed) then
            slotClicked(hbId, setName, index)
        end
    end
    popStyleVarsSafe(pushed)
end

-- Hotbar options menu (window right-click / "Hotbar Options" submenu) ------------------------------------------------------------
local function drawSetSubmenus(hb, hbId)
    -- Add Set
    local addable = {}
    for _, name in ipairs(sortedKeys(db.sets)) do
        if not hotbarHasSet(hb, name) then addable[#addable + 1] = name end
    end
    if #addable > 0 and ImGui.BeginMenu('Add Set') then
        for _, name in ipairs(addable) do
            if ImGui.MenuItem(name .. '##add_' .. name) then addSetToHotbar(hb, name) end
        end
        ImGui.EndMenu()
    end
    if #hb.sets > 0 and ImGui.BeginMenu('Remove Set From Hotbar') then
        for _, name in ipairs(deepcopy(hb.sets)) do
            if ImGui.MenuItem(name .. '##rm_' .. name) then removeSetFromHotbar(hb, name) end
        end
        ImGui.EndMenu()
    end
    if tableSize(db.sets) > 0 and ImGui.BeginMenu('Delete Set (everywhere)') then
        for _, name in ipairs(sortedKeys(db.sets)) do
            if ImGui.MenuItem(name .. '##del_' .. name) then deleteSet(name) end
        end
        ImGui.EndMenu()
    end
    -- Create New Set
    if ImGui.BeginMenu('Create New Set') then
        local cur = state.newSetName[hbId] or ''
        ImGui.SetNextItemWidth(core.px(160))
        local txt = ImGui.InputText('##newSet_' .. hbId, cur)
        if type(txt) == 'string' then state.newSetName[hbId] = txt end
        ImGui.SameLine()
        if ImGui.Button('Create##newSetBtn_' .. hbId) and trim(state.newSetName[hbId] or '') ~= '' then
            local name = createSet(state.newSetName[hbId])
            hb.sets[#hb.sets + 1] = name
            state.newSetName[hbId] = ''
            saveDb()
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndMenu()
    end
    -- Delete button from the library
    if tableSize(db.buttons) > 0 and ImGui.BeginMenu('Delete Button (library)') then
        local groups = {}
        for k, btn in pairs(db.buttons) do
            local g = alphaGroupFor(btn.label)
            groups[g] = groups[g] or {}
            table.insert(groups[g], { key = k, label = btn.label ~= '' and btn.label or k })
        end
        for _, g in ipairs(ALPHA_GROUPS) do
            local items = groups[g.name]
            if items and #items > 0 then
                table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
                if ImGui.BeginMenu(g.name .. '##delbtn_' .. g.name) then
                    for _, it in ipairs(items) do
                        if ImGui.MenuItem(it.label .. '##delbtn_' .. it.key) then deleteButton(it.key) end
                    end
                    ImGui.EndMenu()
                end
            end
        end
        ImGui.EndMenu()
    end
end

drawHotbarMenu = function(hb, hbId)
    core.accent(GOLD, hb.title or ('Hotbar ' .. hbId))
    ImGui.Separator()
    local lockVal = ImGui.Checkbox('Lock Window Position & Size##hbLock_' .. hbId, hb.locked == true)
    if lockVal ~= (hb.locked == true) then
        hb.locked = lockVal
        saveDb({ silent = true })
    end
    if hb.compact and #hb.sets > 1 and ImGui.BeginMenu('Active Set') then
        for i, name in ipairs(hb.sets) do
            if ImGui.MenuItem(name .. '##active_' .. i, nil, (state.activeSet[hbId] or 1) == i) then
                state.activeSet[hbId] = i
            end
        end
        ImGui.EndMenu()
    end
    if ImGui.BeginMenu('Box Control Scope') then
        local cur = hotbarBoxScope(hb)
        for _, sc in ipairs(BAR_SCOPES) do
            if ImGui.MenuItem(sc.desc .. '##hbScopeMenu_' .. hbId .. '_' .. sc.id, nil, cur == sc.id) then
                setHotbarBoxScope(hb, sc.id, hbId)
            end
        end
        ImGui.Separator()
        ImGui.TextDisabled('Applies to Box Control buttons made with the "Hotbar switch" scope.')
        ImGui.EndMenu()
    end
    ImGui.Separator()
    drawSetSubmenus(hb, hbId)
    ImGui.Separator()

    if ImGui.BeginMenu('Button Size') then
        for s = MIN_BUTTON_SIZE, MAX_BUTTON_SIZE do
            if ImGui.MenuItem(string.format('%d px##bs_%d', s * 10, s), nil, hb.buttonSize == s) and hb.buttonSize ~= s then
                hb.buttonSize = s
                saveDb({ silent = true })
            end
        end
        ImGui.EndMenu()
    end
    if ImGui.BeginMenu('Font Scale') then
        for _, fs in ipairs(FONT_SCALES) do
            local isCur = math.abs((hb.fontScale or 1) - fs) < 0.01
            if ImGui.MenuItem(string.format('%.0f%%##fs_%d', fs * 100, math.floor(fs * 100)), nil, isCur) and not isCur then
                hb.fontScale = fs
                saveDb({ silent = true })
            end
        end
        ImGui.EndMenu()
    end
    if ImGui.BeginMenu('Display') then
        if ImGui.MenuItem((hb.hideTitleBar and 'Show' or 'Hide') .. ' Title Bar') then
            hb.hideTitleBar = not hb.hideTitleBar
            saveDb({ silent = true })
        end
        -- The shared ghost fade (core window options, keyed by this hotbar's window key).
        if core.drawWindowMenuItems then
            core.drawWindowMenuItems((hbId == 1) and 'buttons' or ('buttons_' .. hbId), { header = false, titleBar = false, lock = false, scale = false, layout = false, close = false })
        end
        if ImGui.MenuItem(hb.compact and 'Normal Mode (tabs)' or 'Compact Mode (one set, no tabs)') then
            hb.compact = not hb.compact
            saveDb({ silent = true })
        end
        if ImGui.MenuItem((hb.hideScrollbar and 'Show' or 'Hide') .. ' Scrollbar') then
            hb.hideScrollbar = not hb.hideScrollbar
            saveDb({ silent = true })
        end
        if ImGui.MenuItem((hb.showSearch and 'Disable' or 'Enable') .. ' Search Box') then
            hb.showSearch = not hb.showSearch
            saveDb({ silent = true })
        end
        if ImGui.MenuItem((hb.advTooltips and 'Disable' or 'Enable') .. ' Advanced Tooltips (show commands)') then
            hb.advTooltips = not hb.advTooltips
            saveDb({ silent = true })
        end
        if ImGui.MenuItem((hb.showScopeBar ~= false and 'Hide' or 'Show') .. ' Box Scope Switch (Group / Zone / All row)') then
            hb.showScopeBar = not (hb.showScopeBar ~= false)
            saveDb({ silent = true })
        end
        if ImGui.IsItemHovered() then core.setTooltip('The row only appears while this bar holds Box Control buttons made with the "Hotbar switch" scope.') end
        if ImGui.MenuItem(hb.perCharPos and 'Global Window Position' or 'Per-Character Window Position') then
            hb.perCharPos = not hb.perCharPos
            saveDb({ silent = true })
        end
        ImGui.SetNextItemWidth(core.px(140))
        local a = pushSlider('Opacity##hbAlpha_' .. hbId, hb.alpha or 1.0, 0.1, 1.0, '%.2f')
        -- Update live so the hotbar reflects the drag, but only write the DB
        -- (file + .bak + boxnet broadcast) once the slider is released.
        local okDone, done = pcall(ImGui.IsItemDeactivatedAfterEdit)
        local changed = math.abs(a - (hb.alpha or 1.0)) > 0.001
        if changed then hb.alpha = a end
        if (okDone and done) or (changed and not okDone) then
            saveDb({ silent = true })
        end
        ImGui.Separator()
        ImGui.Text('Title:')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(160))
        local cur = state.titleEdit[hbId]
        if cur == nil then cur = hb.title or '' end
        local txt = ImGui.InputText('##hbTitle_' .. hbId, cur)
        if type(txt) == 'string' then state.titleEdit[hbId] = txt end
        ImGui.SameLine()
        if ImGui.Button('Rename##hbRename_' .. hbId) then
            local nt = trim(state.titleEdit[hbId] or '')
            if nt ~= '' then
                hb.title = nt
                saveDb({ silent = true })
            end
            state.titleEdit[hbId] = nil
        end
        ImGui.EndMenu()
    end
    ImGui.Separator()

    if ImGui.MenuItem('Add From Game... (AAs, gems, abilities, discs, items)') then
        local activeIdx = state.activeSet[hbId] or 1
        local setName = hb.sets[activeIdx] or hb.sets[1]
        openBrowser(browser.tab, 'assign', { hbId = hbId, setName = setName })
    end
    if ImGui.IsItemHovered() then core.setTooltip('Browse what your character has and click to add it as a button in the first free slot of the current set.') end
    if ImGui.BeginMenu('Share Set') then
        for _, name in ipairs(sortedKeys(db.sets)) do
            if ImGui.MenuItem(name .. '##share_' .. name) then
                local s = shareSet(name)
                if s then
                    pcall(ImGui.SetClipboardText, s)
                    setStatus('Set [%s] copied to the clipboard.', name)
                end
            end
        end
        ImGui.EndMenu()
    end
    if ImGui.MenuItem('Import Button or Set...') then
        imp.open = true
        imp.hbId = hbId
        imp.text = ''
        imp.decoded = nil
        imp.valid = false
    end
    local others = {}
    for k in pairs(db.characters) do
        if k ~= charKey() then others[#others + 1] = k end
    end
    table.sort(others)
    if #others > 0 and ImGui.BeginMenu('Copy Hotbars From Character') then
        for _, k in ipairs(others) do
            if ImGui.MenuItem(k .. '##copyfrom_' .. k) then
                if copyHotbarsFrom(k) then setStatus('Copied hotbars from %s.', k) end
            end
        end
        ImGui.EndMenu()
    end
    ImGui.Separator()

    if ImGui.MenuItem('Create New Hotbar') then newHotbarForMe() end
    local hbs = hotbars()
    if ImGui.BeginMenu('Show / Hide Hotbar') then
        for i, other in ipairs(hbs) do
            local vis = ImGui.Checkbox(string.format('%s##vis_%d', other.title or ('Hotbar ' .. i), i), other.visible == true)
            if vis ~= (other.visible == true) then
                other.visible = vis
                saveDb({ silent = true })
            end
        end
        ImGui.EndMenu()
    end
    if #hbs > 1 and ImGui.MenuItem('Delete This Hotbar') then
        deleteHotbar(hbId)
    end
end

-- Group / Zone / All row at the top of a hotbar that holds live-scope box
-- control buttons. One click retargets every `{scope}` button on the bar.
local function drawScopeSwitch(hb, hbId)
    local cur = hotbarBoxScope(hb)
    ImGui.TextDisabled('Boxes:')
    if ImGui.IsItemHovered() then core.setTooltip('Where the Box Control buttons on this bar send their commands.\nAlso: /ac btn scope <group|zone|all> [hotbar].') end
    for _, sc in ipairs(BAR_SCOPES) do
        ImGui.SameLine()
        if ImGui.RadioButton(sc.label .. '##hbScope_' .. hbId .. '_' .. sc.id, cur == sc.id) then
            setHotbarBoxScope(hb, sc.id, hbId)
        end
        if ImGui.IsItemHovered() then core.setTooltip('Send to ' .. sc.desc:lower() .. ' (/ac net ' .. sc.id .. ' ...).') end
    end
end

-- One hotbar window -----------------------------------------------------------
local function windowFlags(hb)
    local flags = 0
    local WF = ImGuiWindowFlags
    if not WF then return 0 end
    if WF.NoFocusOnAppearing then flags = bit.bor(flags, WF.NoFocusOnAppearing) end
    if hb.hideTitleBar and WF.NoTitleBar then flags = bit.bor(flags, WF.NoTitleBar) end
    if hb.locked then flags = bit.bor(flags, WF.NoMove, WF.NoResize) end
    if hb.hideScrollbar and WF.NoScrollbar then flags = bit.bor(flags, WF.NoScrollbar) end
    return flags
end

local function drawHotbar(hb, hbId)
    if not hb.visible then return end
    local winKey = (hbId == 1) and 'buttons' or ('buttons_' .. hbId)
    local title = (hb.title or ('Hot Buttons ' .. hbId)) .. '###triuneHotbar_' .. hbId
    if hb.perCharPos then title = title .. '_' .. charKey() end

    core.pushTheme()
    if hb.alpha and hb.alpha < 1 then pcall(ImGui.SetNextWindowBgAlpha, core.windowBgAlpha and core.windowBgAlpha(winKey, hb.alpha) or hb.alpha) end
    pcall(ImGui.SetNextWindowSize, core.px(300), core.px(90), ImGuiCond and ImGuiCond.FirstUseEver or 4)
    core.preBeginWindow(winKey)
    -- Same tight chrome as the Spell Gem bar: 2px padding, 1px frames (pushed
    -- after preBeginWindow so it wins over the scaled theme padding).
    local pushed = pushStyleVarSafe('WindowPadding', core.px(2), core.px(2)) + pushStyleVarSafe('ItemSpacing', core.px(2), core.px(2)) + pushStyleVarSafe('FramePadding', core.px(1), core.px(1))
    local open, show = ImGui.Begin(title, true, core.windowFlags and core.windowFlags(winKey, windowFlags(hb)) or windowFlags(hb))
    if open == false then
        hb.visible = false
        saveDb({ silent = true })
        log('Hotbar %d hidden. Use /btn %d or the header button to bring it back.', hbId, hbId)
    end
    if show then
        core.postBeginWindow(winKey)
        ImGui.PushID('hotbar_' .. hbId)

        -- Options live on the window background's right-click menu (and under
        -- "Hotbar Options" in every slot's menu), like the other popouts.
        -- Declared before the slots so a slot's own menu wins when both open.
        if ImGui.BeginPopupContextWindow('##hbWinMenu') then
            drawHotbarMenu(hb, hbId)
            ImGui.EndPopup()
        end

        -- Group / Zone / All switch for `{scope}` box-control buttons, shown
        -- only while the bar actually holds some (and the option is on).
        if hb.showScopeBar ~= false and hotbarUsesBoxScope(hb) then
            drawScopeSwitch(hb, hbId)
        end

        if hb.compact then
            local activeIdx = state.activeSet[hbId] or 1
            if activeIdx > #hb.sets then activeIdx = 1 end
            local setName = hb.sets[activeIdx]
            if setName and db.sets[setName] then
                drawGrid(hb, hbId, setName, '')
            else
                ImGui.TextDisabled('No set. Right-click for options.')
            end
        else
            if hb.showSearch then
                ImGui.SetNextItemWidth(-1)
                local txt = ImGui.InputText('##search', state.search[hbId] or '')
                if type(txt) == 'string' then state.search[hbId] = txt end
                if ImGui.IsItemHovered() then core.setTooltip('Filter buttons by label or command') end
            end
            if #hb.sets == 0 then
                ImGui.TextDisabled('No sets. Right-click for options -> Add Set / Create New Set.')
            elseif ImGui.BeginTabBar('##hbTabs') then
                for i, setName in ipairs(hb.sets) do
                    if db.sets[setName] and ImGui.BeginTabItem(setName .. '##tab_' .. i) then
                        state.activeSet[hbId] = i
                        -- Tab context menu
                        if ImGui.BeginPopupContextItem('##tabCtx_' .. i) then
                            if ImGui.MenuItem('Rename Set...') then state.renameSet = { from = setName, text = setName } end
                            if i > 1 and ImGui.MenuItem('Move Left') then moveSetInHotbar(hb, i, -1) end
                            if i < #hb.sets and ImGui.MenuItem('Move Right') then moveSetInHotbar(hb, i, 1) end
                            if ImGui.MenuItem('Remove From Hotbar') then removeSetFromHotbar(hb, setName) end
                            if ImGui.MenuItem('Copy Share String') then
                                local str = shareSet(setName)
                                if str then
                                    pcall(ImGui.SetClipboardText, str)
                                    setStatus('Set [%s] copied to the clipboard.', setName)
                                end
                            end
                            ImGui.Separator()
                            if ImGui.BeginMenu('Hotbar Options') then
                                drawHotbarMenu(hb, hbId)
                                ImGui.EndMenu()
                            end
                            ImGui.EndPopup()
                        end
                        if ImGui.BeginChild('##grid_' .. i, 0, 0, false) then
                            drawGrid(hb, hbId, setName, state.search[hbId])
                        end
                        ImGui.EndChild()
                        ImGui.EndTabItem()
                    end
                end
                ImGui.EndTabBar()
            end
        end

        -- Rename-set inline popup (shared by every hotbar)
        if state.renameSet and state.renameSet.owner == nil then state.renameSet.owner = hbId end
        if state.renameSet and state.renameSet.owner == hbId then
            ImGui.OpenPopup('Rename Set##renameSet')
            if ImGui.BeginPopup('Rename Set##renameSet') then
                ImGui.Text('Rename set "' .. state.renameSet.from .. '"')
                ImGui.SetNextItemWidth(core.px(200))
                local txt = ImGui.InputText('##renameSetText', state.renameSet.text)
                if type(txt) == 'string' then state.renameSet.text = txt end
                if ImGui.Button('Rename##renameSetOk') then
                    if renameSet(state.renameSet.from, state.renameSet.text) then
                        setStatus('Renamed set to %s.', trim(state.renameSet.text))
                    else
                        setStatus('Rename failed: name empty or already used.')
                    end
                    state.renameSet = nil
                    ImGui.CloseCurrentPopup()
                end
                ImGui.SameLine()
                if ImGui.Button('Cancel##renameSetCancel') then
                    state.renameSet = nil
                    ImGui.CloseCurrentPopup()
                end
                ImGui.EndPopup()
            else
                state.renameSet = nil
            end
        end
        ImGui.PopID()
    end
    if core.preEndWindow then core.preEndWindow(winKey, true) end
    ImGui.End()
    popStyleVarsSafe(pushed)
    core.popTheme()
end

-- Edit Button window ----------------------------------------------------------
local function sameRgb(a, b)
    if a == nil or b == nil then return a == b end
    return math.floor(a[1] or -1) == math.floor(b[1] or -2) and math.floor(a[2] or -1) == math.floor(b[2] or -2) and math.floor(a[3] or -1) == math.floor(b[3] or -2)
end

-- A row of colour swatches. Returns the picked {r,g,b} (or nil for Default)
-- and true when one was clicked.
local function drawSwatches(idPrefix, palette, current, fallback)
    local picked, changed = current, false
    local Col = ImGuiCol
    local toV, col32 = core.toVec, core.col32
    for i, sw in ipairs(palette) do
        if i > 1 then ImGui.SameLine(0, core.px(3)) end
        local r, g, b = rgbTo01(sw.rgb, fallback)
        local pushed = 0
        if Col then
            if pcall(ImGui.PushStyleColor, Col.Button, r, g, b, 1.0) then pushed = pushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.ButtonHovered, math.min(1, r + 0.12), math.min(1, g + 0.12), math.min(1, b + 0.12), 1.0) then pushed = pushed + 1 end
            if pcall(ImGui.PushStyleColor, Col.ButtonActive, math.min(1, r + 0.2), math.min(1, g + 0.2), math.min(1, b + 0.2), 1.0) then pushed = pushed + 1 end
        end
        if ImGui.Button('##' .. idPrefix .. '_' .. sw.name, core.px(20), core.px(20)) then
            picked, changed = sw.rgb and deepcopy(sw.rgb) or nil, true
        end
        if pushed > 0 then pcall(ImGui.PopStyleColor, pushed) end
        if ImGui.IsItemHovered() then core.setTooltip(sw.name) end
        local isCur = sameRgb(sw.rgb, current)
        local dl = ImGui.GetWindowDrawList()
        if dl then
            local mnX, mnY = xy(ImGui.GetItemRectMin())
            local mxX, mxY = xy(ImGui.GetItemRectMax())
            local p1, p2 = toV(mnX, mnY), toV(mxX, mxY)
            if p1 and p2 then
                if isCur then
                    if not pcall(function() dl:AddRect(p1, p2, col32(1.0, 0.85, 0.3, 1), 3, 0, 2) end) then dl:AddRect(p1, p2, col32(1.0, 0.85, 0.3, 1), 3) end
                elseif sw.rgb == nil then
                    -- "Default" swatch: a diagonal so it reads as "no colour"
                    local q1, q2 = toV(mnX + 3, mxY - 3), toV(mxX - 3, mnY + 3)
                    if q1 and q2 and dl.AddLine then pcall(function() dl:AddLine(q1, q2, col32(0.9, 0.9, 0.9, 0.8), 1) end) end
                end
            end
        end
    end
    return picked, changed
end

local function drawEditor()
    if not edit.open or not edit.tmp then return end
    local t = edit.tmp
    core.pushTheme()
    if core.pushWindowScale then core.pushWindowScale(nil) end
    pcall(ImGui.SetNextWindowSize, core.px(580), core.px(540), ImGuiCond and ImGuiCond.FirstUseEver or 4)
    local flags = 0
    if edit.dirty and ImGuiWindowFlags and ImGuiWindowFlags.UnsavedDocument then flags = ImGuiWindowFlags.UnsavedDocument end
    local open, show = ImGui.Begin('Edit Hot Button###triuneBtnEdit', true, flags)
    if open == false then
        closeEditor()
        ImGui.End()
        core.popTheme()
        return
    end
    if show then
        if core.applyWindowScale then core.applyWindowScale(nil) end
        -- Row 1: preview + colours + icon + reset + advanced
        local col32 = core.col32
        local toV = core.toVec
        ImGui.InvisibleButton('##preview', core.px(40), core.px(40))
        do
            local mnX, mnY = xy(ImGui.GetItemRectMin())
            local mxX, mxY = xy(ImGui.GetItemRectMax())
            local dl = ImGui.GetWindowDrawList()
            local p1, p2 = toV(mnX, mnY), toV(mxX, mxY)
            if dl and p1 and p2 then
                local br, bg, bb = rgbTo01(t.buttonColor, { 0.13, 0.18, 0.25 })
                dl:AddRectFilled(p1, p2, col32(br, bg, bb, 0.95), 4)
                local anim = t.icon and iconAnim(t.icon, t.iconType) or nil
                if anim and dl.AddTextureAnimation then
                    local ip, isz = toV(mnX + 2, mnY + 2), toV(36, 36)
                    if ip and isz then pcall(function() dl:AddTextureAnimation(anim, ip, isz) end) end
                end
                dl:AddRect(p1, p2, col32(0.16, 0.25, 0.35, 1), 4)
            end
        end
        if ImGui.IsItemHovered() then core.setTooltip('Preview. Click to pick an icon.') end
        if ImGui.IsItemClicked and ImGui.IsItemClicked() then picker.open = true end
        ImGui.SameLine()
        ImGui.BeginGroup()
        ImGui.Text('Button:')
        ImGui.SameLine(0, core.px(6))
        local newBC, chB = drawSwatches('bc', BUTTON_PALETTE, t.buttonColor, { 0.13, 0.18, 0.25 })
        if chB then t.buttonColor = newBC; edit.dirty = true end
        ImGui.Text('Text:  ')
        ImGui.SameLine(0, core.px(6))
        local newTC, chT = drawSwatches('tc', TEXT_PALETTE, t.textColor, { 1, 1, 1 })
        if chT then t.textColor = newTC; edit.dirty = true end
        if ImGui.Button('Pick Icon##pickIcon') then picker.open = true end
        if t.icon then
            ImGui.SameLine()
            if ImGui.Button('Clear Icon##clearIcon') then
                t.icon, t.iconType = nil, 'Spell'
                edit.dirty = true
            end
        end
        if ImGui.Button('Icon From Cursor##iconCursor') then
            local fc = buttonFromCursor()
            if fc and fc.icon then
                t.icon, t.iconType = fc.icon, fc.iconType
                edit.dirty = true
            else
                setStatus('Nothing with an icon is on the cursor.')
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Fill From Cursor##fillCursor') then
            local fc = buttonFromCursor()
            if fc then
                for k, v in pairs(fc) do t[k] = v end
                edit.timerIdx = timerIdxFor(t.timerType)
                edit.dirty = true
            else
                setStatus('Nothing is attached to the cursor.')
            end
        end
        if ImGui.IsItemHovered() then core.setTooltip('Pick up a spell gem, item, ability, discipline, or social button and click to fill in this button.') end
        ImGui.SameLine()
        if ImGui.Button('Fill From Game...##fillGame') then openBrowser(browser.tab, 'editor', nil) end
        if ImGui.IsItemHovered() then core.setTooltip('Pick an AA, spell gem, ability, discipline, or item clicky to fill in this button.') end
        ImGui.SameLine()
        if ImGui.Button('Reset Style##resetStyle') then
            t.buttonColor, t.textColor, t.icon, t.iconType, t.iconLua, t.evaluateLabel, t.fontScale = nil, nil, nil, 'Spell', nil, nil, nil
            edit.dirty = true
        end
        ImGui.EndGroup()

        -- Label
        ImGui.SetNextItemWidth(-150)
        local lbl = ImGui.InputText('Label##btnLabel', t.label or '')
        if type(lbl) == 'string' and lbl ~= t.label then
            t.label = lbl
            edit.dirty = true
        end
        ImGui.SameLine()
        local sl = ImGui.Checkbox('Show Label##showLabel', t.showLabel ~= false)
        if sl ~= (t.showLabel ~= false) then
            t.showLabel = sl
            edit.dirty = true
        end
        local curFont = 1
        for i, fs in ipairs(BUTTON_FONT_SCALES) do
            if t.fontScale and math.abs(t.fontScale - fs) < 0.001 then curFont = i + 1 end
        end
        ImGui.SetNextItemWidth(-150)
        local nf = ImGui.Combo('Font Size##btnFont', curFont, BUTTON_FONT_LABELS)
        if type(nf) == 'number' and nf ~= curFont then
            t.fontScale = (nf > 1) and BUTTON_FONT_SCALES[nf - 1] or nil
            edit.dirty = true
        end
        if ImGui.IsItemHovered() then core.setTooltip('Label size for this button only. "Hotbar default" follows the hotbar\'s Font Scale menu.') end

        local adv = ImGui.Checkbox('Advanced##advToggle', edit.advanced)
        if adv ~= edit.advanced then edit.advanced = adv end
        if edit.advanced then
            local ev = ImGui.Checkbox('Label is Lua (must return a string)##evalLabel', t.evaluateLabel == true)
            if ev ~= (t.evaluateLabel == true) then
                t.evaluateLabel = ev
                edit.dirty = true
            end
            if ImGui.IsItemHovered() then core.setTooltip('Example: return string.format("HP %d%%", mq.TLO.Me.PctHPs())') end
            ImGui.SetNextItemWidth(-150)
            local il = ImGui.InputText('Icon Lua##iconLua', t.iconLua or '')
            if type(il) == 'string' and il ~= (t.iconLua or '') then
                t.iconLua = il ~= '' and il or nil
                edit.dirty = true
            end
            if ImGui.IsItemHovered() then core.setTooltip('Lua returning iconId, iconType ("Spell" or "Item") - overrides the picked icon.') end
            ImGui.SetNextItemWidth(-150)
            local ri = ImGui.Combo('Update Rate##rate', edit.rateIdx, RATE_LABELS)
            if type(ri) == 'number' and ri ~= edit.rateIdx then
                edit.rateIdx = ri
                edit.dirty = true
            end
        end

        ImGui.Separator()
        -- Timer
        ImGui.SetNextItemWidth(-150)
        local ti = ImGui.Combo('Cooldown Timer##timerType', edit.timerIdx, TIMER_LABELS)
        if type(ti) == 'number' and ti ~= edit.timerIdx then
            edit.timerIdx = ti
            t.timerType = TIMER_TYPES[ti] and TIMER_TYPES[ti].id or 'None'
            edit.dirty = true
        end
        local tt = TIMER_TYPES[edit.timerIdx] and TIMER_TYPES[edit.timerIdx].id or 'None'
        local hint = ({
            Seconds = 'Seconds to show the overlay after the button fires',
            Item    = 'Item name whose clicky timer to track',
            Gem     = 'Spell gem number (1-' .. tostring(core.getNumGems and (core.getNumGems() or 12) or 12) .. ')',
            AA      = 'Alternate ability name or ID',
            Ability = 'Ability name (e.g. Taunt, Kick)',
            Disc    = 'Discipline name',
        })[tt]
        if hint then
            ImGui.SetNextItemWidth(-150)
            local tk = ImGui.InputText('Timer Key##timerKey', t.timerKey or '')
            if type(tk) == 'string' and tk ~= (t.timerKey or '') then
                t.timerKey = tk
                edit.dirty = true
            end
            if ImGui.IsItemHovered() then core.setTooltip(hint) end
            ImGui.SameLine()
            ImGui.TextDisabled('(?)')
            if ImGui.IsItemHovered() then core.setTooltip(hint) end
        elseif tt == 'Lua' then
            for _, f in ipairs({
                { key = 'timerLua',    label = 'Remaining Lua##timerLua',   tip = 'Lua returning seconds left, e.g. return mq.TLO.FindItem("Potion").TimerReady()' },
                { key = 'cooldownLua', label = 'Total Lua##cooldownLua',    tip = 'Lua returning the full cooldown in seconds' },
                { key = 'toggleLua',   label = 'Active Check Lua##toggleLua', tip = 'Lua returning true while the button should show as active (gold frame)' },
            }) do
                ImGui.SetNextItemWidth(-150)
                local v = ImGui.InputText(f.label, t[f.key] or '')
                if type(v) == 'string' and v ~= (t[f.key] or '') then
                    t[f.key] = v
                    edit.dirty = true
                end
                if ImGui.IsItemHovered() then core.setTooltip(f.tip) end
            end
        end

        ImGui.Separator()
        ImGui.Text('Commands (one per line; start the first line with "--lua" for a Lua script):')
        local availW, availH = contentAvail()
        local editH = math.max(80, availH - 40)
        local okM, cmdText = pcall(ImGui.InputTextMultiline, '##btnCmd', t.cmd or '', availW, editH)
        if not okM or type(cmdText) ~= 'string' then
            okM, cmdText = pcall(ImGui.InputTextMultiline, '##btnCmd', t.cmd or '')
        end
        if not okM or type(cmdText) ~= 'string' then
            ImGui.SetNextItemWidth(-1)
            cmdText = ImGui.InputText('##btnCmdFallback', t.cmd or '')
        end
        if type(cmdText) == 'string' and cmdText ~= (t.cmd or '') then
            t.cmd = cmdText
            edit.dirty = true
        end

        local ctrlS = false
        if ImGuiMod and ImGuiKey and ImGui.IsKeyChordPressed then
            local okK, pressed = pcall(ImGui.IsKeyChordPressed, bit.bor(ImGuiMod.Ctrl, ImGuiKey.S))
            ctrlS = okK and pressed == true
        end
        if ImGui.Button('Save##btnSave', core.px(90), core.px(24)) or ctrlS then
            if saveEditor() then setStatus('Saved button [%s].', t.label) end
        end
        ImGui.SameLine()
        if ImGui.Button('Save & Close##btnSaveClose', core.px(110), core.px(24)) then
            if saveEditor() then closeEditor() end
        end
        ImGui.SameLine()
        if ImGui.Button('Close##btnClose', core.px(90), core.px(24)) then closeEditor() end
        if ImGui.IsItemHovered() then core.setTooltip('Close without saving') end
        if state.statusMsg ~= '' and (os.clock() - state.statusAt) < 6 then
            ImGui.SameLine()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], state.statusMsg)
        end
    end
    ImGui.End()
    core.popTheme()
end

-- Icon Picker window ----------------------------------------------------------
-- True when iconAnim() hands out one object per icon id for this tab (so a
-- page of animations can be cached); false for the shared-texture fallbacks.
function picker.pageCacheable(tabName)
    if tabName == 'Item' then
        probeItemIcons()
        return itemIcon.mode == 'dedicated'
    end
    if picker.spellDedicated == nil then
        local a, b = iconAnim(1, 'Spell'), iconAnim(2, 'Spell')
        picker.spellDedicated = (a ~= nil and b ~= nil and a ~= b)
    end
    return picker.spellDedicated
end

local function drawPicker()
    if not picker.open then return end
    core.pushTheme()
    if core.pushWindowScale then core.pushWindowScale(nil) end
    pcall(ImGui.SetNextWindowSize, core.px(560), core.px(420), ImGuiCond and ImGuiCond.FirstUseEver or 4)
    local open, show = ImGui.Begin('Icon Picker###triuneBtnIconPicker', true, 0)
    if open == false then
        picker.open = false
        ImGui.End()
        core.popTheme()
        return
    end
    if show then
        if core.applyWindowScale then core.applyWindowScale(nil) end
        local maxIcon = (picker.tab == 'Item') and picker.maxItem or picker.maxSpell
        local maxPage = math.max(1, math.ceil((maxIcon + 1) / picker.perPage))
        ImGui.SetNextItemWidth(core.px(120))
        local pg = ImGui.InputInt('Page##iconPage', picker.page)
        if type(pg) == 'number' then picker.page = math.max(1, math.min(maxPage, pg)) end
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('of %d', maxPage))
        ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(120))
        local idIn = ImGui.InputInt('Icon ID##iconId', picker.manual or 0)
        if type(idIn) == 'number' then picker.manual = math.max(0, idIn) end
        ImGui.SameLine()
        if ImGui.Button('Use ID##useIconId') and edit.tmp then
            edit.tmp.icon = picker.manual or 0
            edit.tmp.iconType = picker.tab
            edit.dirty = true
            picker.open = false
        end
        if ImGui.BeginTabBar('##iconTabs') then
            for _, tabName in ipairs({ 'Spell', 'Item' }) do
                if ImGui.BeginTabItem(tabName .. ' Icons##' .. tabName) then
                    if picker.tab ~= tabName then
                        picker.tab = tabName
                        picker.page = 1
                    end
                    if ImGui.BeginChild('##iconGrid', 0, 0, false) then
                        local availW = contentAvail()
                        local cols = math.max(1, math.floor((availW + 4) / (picker.size + 4)))
                        local startId = (picker.page - 1) * picker.perPage
                        local endId = math.min(maxIcon, startId + picker.perPage - 1)
                        local dl = ImGui.GetWindowDrawList()
                        local n = 0
                        local pushedSp = pushStyleVarSafe('ItemSpacing', 4, 4)
                        -- One animation object per icon id (the "dedicated" modes)
                        -- can be resolved once per page instead of 500 times per
                        -- frame; a shared animation has its cell set per draw and
                        -- must be resolved every time.
                        local anims = nil
                        if picker.pageCacheable(tabName) then
                            local pageKey = tabName .. ':' .. picker.page
                            if picker.pageKey ~= pageKey or not picker.pageAnims then
                                picker.pageKey = pageKey
                                picker.pageAnims = {}
                            end
                            anims = picker.pageAnims
                        end
                        local isz = core.toVec(picker.size, picker.size)
                        for id = startId, endId do
                            if n > 0 and n % cols ~= 0 then ImGui.SameLine(0, core.px(4)) end
                            n = n + 1
                            ImGui.PushID(id)
                            local clicked = ImGui.InvisibleButton('##icon', picker.size, picker.size)
                            local mnX, mnY = xy(ImGui.GetItemRectMin())
                            local anim
                            if anims then
                                anim = anims[id]
                                if anim == nil then
                                    anim = iconAnim(id, tabName) or false
                                    anims[id] = anim
                                end
                            else
                                anim = iconAnim(id, tabName)
                            end
                            if anim and dl and dl.AddTextureAnimation then
                                local ip = core.toVec(mnX, mnY)
                                if ip and isz then pcall(dl.AddTextureAnimation, dl, anim, ip, isz) end
                            end
                            if ImGui.IsItemHovered() then
                                core.setTooltip(string.format('%s icon %d', tabName, id))
                                local p1, p2 = core.toVec(mnX, mnY), core.toVec(mnX + picker.size, mnY + picker.size)
                                if dl and p1 and p2 then dl:AddRect(p1, p2, core.col32(1, 0.85, 0.3, 1), 3) end
                            end
                            if clicked and edit.tmp then
                                edit.tmp.icon = id
                                edit.tmp.iconType = tabName
                                edit.dirty = true
                                picker.open = false
                            end
                            ImGui.PopID()
                        end
                        popStyleVarsSafe(pushedSp)
                    end
                    ImGui.EndChild()
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
    end
    ImGui.End()
    core.popTheme()
end

-- Import window ----------------------------------------------------------------
local function drawImport()
    if not imp.open then return end
    core.pushTheme()
    if core.pushWindowScale then core.pushWindowScale(nil) end
    pcall(ImGui.SetNextWindowSize, core.px(520), core.px(140), ImGuiCond and ImGuiCond.FirstUseEver or 4)
    local open, show = ImGui.Begin('Import Button or Set###triuneBtnImport', true, 0)
    if open == false then
        imp.open = false
        ImGui.End()
        core.popTheme()
        return
    end
    if show and core.applyWindowScale then core.applyWindowScale(nil) end
    if show then
        ImGui.TextDisabled('Paste a Triune / Button Master share string:')
        if ImGui.Button('Paste From Clipboard##impPaste') then
            local ok, txt = pcall(ImGui.GetClipboardText)
            if ok and type(txt) == 'string' then
                imp.text = txt
                imp.decoded, imp.err = decodeShare(imp.text)
                imp.valid = imp.decoded ~= nil
            end
        end
        ImGui.SetNextItemWidth(-1)
        local txt, changed = ImGui.InputText('##impText', imp.text)
        if type(txt) == 'string' and (changed or txt ~= imp.text) then
            imp.text = txt
            imp.decoded, imp.err = decodeShare(imp.text)
            imp.valid = imp.decoded ~= nil
        end
        if imp.valid and imp.decoded then
            local what = imp.decoded.Type == 'Set'
                and string.format('Set "%s" (%d buttons)', tostring(imp.decoded.Key), tableSize(imp.decoded.Buttons))
                or string.format('Button "%s"', tostring(imp.decoded.Button and imp.decoded.Button.Label))
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], what)
            if ImGui.Button('Import##impGo', core.px(120), core.px(24)) then
                local hb = hotbars()[imp.hbId]
                local ok = importShare(imp.decoded, hb)
                if ok then
                    imp.open = false
                    imp.text = ''
                    imp.decoded = nil
                end
            end
        elseif imp.text ~= '' then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Not a valid share string' .. (imp.err and (': ' .. tostring(imp.err)) or ''))
        end
    end
    ImGui.End()
    core.popTheme()
end

-- "Add From Game" browser window --------------------------------------------
local function drawBrowser()
    if not browser.open then return end
    core.pushTheme()
    if core.pushWindowScale then core.pushWindowScale(nil) end
    pcall(ImGui.SetNextWindowSize, core.px(460), core.px(420), ImGuiCond and ImGuiCond.FirstUseEver or 4)
    local open, show = ImGui.Begin('Add From Game###triuneBtnBrowser', true, 0)
    if open == false then
        browser.open = false
        ImGui.End()
        core.popTheme()
        return
    end
    if show then
        if core.applyWindowScale then core.applyWindowScale(nil) end
        if browser.mode == 'editor' then
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Click an entry to fill the open editor.')
        elseif browser.target and browser.target.setName then
            local where = browser.target.index and string.format('slot %d of %s', browser.target.index, browser.target.setName)
                or string.format('the first free slot of %s', browser.target.setName)
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Click an entry to add it to ' .. where .. '.')
        else
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'No set selected - open this from a hotbar slot or the hotbar right-click menu.')
        end
        ImGui.SetNextItemWidth(-90)
        local txt = ImGui.InputText('##browserSearch', browser.search)
        if type(txt) == 'string' then browser.search = txt end
        ImGui.SameLine()
        if ImGui.Button('Refresh##browserRefresh', core.px(80), 0) then
            browser.lists[browser.tab] = nil
            browser.requestScan(browser.tab)
        end
        if ImGui.IsItemHovered() then core.setTooltip('Rescan this tab (lists are scanned in the background and cached; items rescan on zone change, gems when your memorized spells change).') end

        if ImGui.BeginTabBar('##browserTabs') then
            for _, tab in ipairs(BROWSER_TABS) do
                local flags = 0
                if browser.forceTab == tab.id and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected then
                    flags = ImGuiTabItemFlags.SetSelected
                end
                local okTab, tabOpen = false, false
                if flags ~= 0 then okTab, tabOpen = pcall(ImGui.BeginTabItem, tab.label .. '##btab_' .. tab.id, nil, flags) end
                if not okTab then tabOpen = ImGui.BeginTabItem(tab.label .. '##btab_' .. tab.id) end
                if tabOpen then
                    browser.tab = tab.id
                    if tab.id == 'Box' then
                        ImGui.TextDisabled('Box Net quick actions as buttons (needs the Box Network plugin).')
                        ImGui.Text('Scope:')
                        ImGui.SameLine()
                        for _, sc in ipairs(BOX_SCOPES) do
                            if ImGui.RadioButton(sc.label .. '##boxScope_' .. sc.id, browser.boxScope == sc.id) and browser.boxScope ~= sc.id then
                                browser.boxScope = sc.id
                                browser.lists.Box = nil
                            end
                            if sc.id == 'bar' and ImGui.IsItemHovered() then
                                core.setTooltip('The buttons follow a Group / Zone / All switch shown on the hotbar (right-click -> Box Control Scope, or /ac btn scope), so one set serves every scope.')
                            end
                            ImGui.SameLine()
                        end
                        ImGui.NewLine()
                        if browser.mode == 'assign' and browser.target and browser.target.hbId then
                            if ImGui.Button('Add All as a Set##boxAddAll', core.px(150), core.px(22)) then
                                addBoxControlSet(browser.boxScope, hotbars()[browser.target.hbId])
                            end
                            if ImGui.IsItemHovered() then
                                local who = browser.boxScope == 'bar' and 'that follow the hotbar\'s Group / Zone / All switch' or ('for ' .. boxScopeLabel(browser.boxScope))
                                core.setTooltip('Creates a "Box Control" set with every preset ' .. who .. ' and adds it as a tab on this hotbar.')
                            end
                        end
                        ImGui.Separator()
                    elseif tab.id == 'Cmd' then
                        ImGui.TextDisabled('Triune slash commands. Entries with an <argument> open the editor to fill it in.')
                    end
                    local list = browser.listCached(tab.id)
                    local needle = trim(browser.search):lower()
                    if ImGui.BeginChild('##browserList', 0, 0, false) then
                        local shown = 0
                        local dl = ImGui.GetWindowDrawList()
                        if not list then
                            ImGui.TextDisabled('Scanning...')
                            shown = -1
                        end
                        for i, e in ipairs(list or {}) do
                            local hay = (e.name .. ' ' .. (e.sub or '')):lower()
                            if needle == '' or hay:find(needle, 1, true) then
                                shown = shown + 1
                                ImGui.PushID(i)
                                local rowH = 22
                                local cx, cy = xy(ImGui.GetCursorScreenPos())
                                if e.icon and dl and dl.AddTextureAnimation then
                                    local anim = iconAnim(e.icon, e.iconType)
                                    local ip, isz = core.toVec(cx, cy), core.toVec(rowH - 2, rowH - 2)
                                    if anim and ip and isz then pcall(function() dl:AddTextureAnimation(anim, ip, isz) end) end
                                end
                                ImGui.Dummy(rowH - 2, rowH - 2)
                                ImGui.SameLine(0, core.px(6))
                                local label = e.name .. (e.sub and e.sub ~= '' and ('   ' .. e.sub) or '')
                                if e.empty then
                                    ImGui.TextDisabled(label)
                                else
                                    local okSel, sel = pcall(ImGui.Selectable, label .. '##row', false, 0, 0, rowH - 2)
                                    if not okSel then sel = ImGui.Selectable(label .. '##row', false) end
                                    if sel then pickBrowserEntry(e) end
                                    if ImGui.IsItemHovered() then core.setTooltip(e.button.cmd) end
                                end
                                ImGui.PopID()
                            end
                        end
                        if shown == 0 then
                            ImGui.TextDisabled(#list == 0 and 'Nothing found. Click Refresh.' or 'No matches.')
                        end
                    end
                    ImGui.EndChild()
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
        browser.forceTab = nil
    end
    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Commands
-- ----------------------------------------------------------------------------
local function setAllVisible(val)
    ctrl.show_buttons = (val == true)
    if val and not anyHotbarVisible() then
        for _, hb in ipairs(hotbars()) do hb.visible = true end
        saveDb({ silent = true })
    end
    core.saveLoadout(true)
end

local function toggleHotbar(n)
    local hb = hotbars()[n]
    if not hb then
        log('No hotbar %d. You have %d hotbar(s).', n, #hotbars())
        return false
    end
    hb.visible = not hb.visible
    if hb.visible then
        ctrl.show_buttons = true
        core.saveLoadout(true)
    end
    saveDb({ silent = true })
    log('Hotbar %d (%s) %s.', n, hb.title or '', hb.visible and 'shown' or 'hidden')
    return true
end

local function listLibrary()
    log('Sets:')
    for _, name in ipairs(sortedKeys(db.sets)) do
        local set = db.sets[name]
        local idxs = {}
        for idx in pairs(set) do idxs[#idxs + 1] = idx end
        table.sort(idxs)
        log('  \at%s\ax (%d button(s))', name, #idxs)
        for _, idx in ipairs(idxs) do
            local b = db.buttons[set[idx]]
            if b then log('    [%d] %s', idx, b.label) end
        end
    end
    log('Hotbars for %s: %d', charKey(), #hotbars())
end

-- Shared by /ac btn ... and the /btn* binds. `args` excludes the command word.
local function handleCommand(args)
    args = args or {}
    local sub = (args[1] or ''):lower()
    if sub == '' or sub == 'toggle' then
        local isOpen = ctrl.show_buttons and anyHotbarVisible()
        setAllVisible(not isOpen)
        log('Hot Buttons %s.', ctrl.show_buttons and 'OPENED' or 'CLOSED')
    elseif sub == 'show' or sub == 'on' then
        setAllVisible(true)
    elseif sub == 'hide' or sub == 'off' then
        setAllVisible(false)
    elseif tonumber(sub) then
        toggleHotbar(math.floor(tonumber(sub)))
    elseif sub == 'new' or sub == 'create' then
        local n = newHotbarForMe()
        log('Created hotbar %d.', n)
    elseif sub == 'exec' or sub == 'run' then
        local setName, idx = args[2], tonumber(args[3])
        if not setName or not idx then
            log('usage: /ac btn exec <set> <index>   (or /btnexec "<set>" <index>)')
        elseif not db.sets[setName] then
            log('\arNo set named "%s".', setName)
        elseif not execBySetIndex(setName, idx) then
            log('\arSet "%s" has no button at slot %d.', setName, idx)
        end
    elseif sub == 'add' or sub == 'browse' then
        local want = (args[2] or ''):lower()
        local tab = ({ aa = 'AA', aas = 'AA', gem = 'Gem', gems = 'Gem', spell = 'Gem', spells = 'Gem', ability = 'Ability', abilities = 'Ability', skill = 'Ability',
            disc = 'Disc', discs = 'Disc', item = 'Item', items = 'Item', clicky = 'Item', box = 'Box', boxes = 'Box', net = 'Box', boxnet = 'Box', cmd = 'Cmd', cmds = 'Cmd', command = 'Cmd', commands = 'Cmd', slash = 'Cmd', triune = 'Cmd' })[want] or browser.tab
        -- Target the active set of the first hotbar that has one.
        local target = nil
        for i, hb in ipairs(hotbars()) do
            local setName = hb.sets[state.activeSet[i] or 1] or hb.sets[1]
            if setName and db.sets[setName] then
                target = { hbId = i, setName = setName }
                break
            end
        end
        openBrowser(tab, 'assign', target)
        ctrl.show_buttons = true
    elseif sub == 'scope' then
        -- /ac btn scope [group|zone|all|next] [hotbar]: the live scope for
        -- `{scope}` box-control buttons. Without a hotbar number, the first
        -- bar holding such buttons is used (else hotbar 1).
        local want, hbs = (args[2] or ''):lower(), hotbars()
        local hbId = tonumber(args[3])
        if not hbId then
            for i, h in ipairs(hbs) do
                if hotbarUsesBoxScope(h) then hbId = i break end
            end
            hbId = hbId or 1
        end
        hbId = math.floor(hbId)
        local hb = hbs[hbId]
        if not hb then
            log('\arNo hotbar %d.', hbId)
        elseif want == '' then
            log('Hotbar %d (%s) box-control scope: %s.', hbId, hb.title or '', barScopeLabel(hotbarBoxScope(hb)))
        else
            if want == 'next' or want == 'cycle' then
                local cur = hotbarBoxScope(hb)
                for i, sc in ipairs(BAR_SCOPES) do
                    if sc.id == cur then want = BAR_SCOPES[(i % #BAR_SCOPES) + 1].id break end
                end
            end
            want = ({ grp = 'group', group = 'group', zone = 'zone', all = 'all' })[want]
            if not want then
                log('usage: /ac btn scope [group|zone|all|next] [hotbar]')
            elseif not setHotbarBoxScope(hb, want, hbId) then
                log('Hotbar %d already sends to %s.', hbId, barScopeLabel(want):lower())
            else
                log('Hotbar %d box-control buttons now send to %s.', hbId, barScopeLabel(want):lower())
            end
        end
    elseif sub == 'list' then
        listLibrary()
    elseif sub == 'reload' then
        loadDb()
        log('Reloaded %s.', plugin.configPath())
    elseif sub == 'import' then
        local what = (args[2] or ''):lower()
        if what == 'bm' or what == 'buttonmaster' then
            local ok, msg = importButtonMasterConfig()
            if not ok then log('\ar%s', tostring(msg)) end
        else
            imp.open = true
            imp.hbId = 1
            log('Import window opened (paste a share string). Use /ac btn import bm to import ButtonMaster.lua.')
        end
    elseif sub == 'copy' then
        local server, name = args[2], args[3]
        if not server or not name then
            log('usage: /ac btn copy <server> <character>')
        else
            local key = server .. '_' .. name:sub(1, 1):upper() .. name:sub(2)
            if copyHotbarsFrom(key) then
                log('Copied hotbars from %s.', key)
            else
                log('\arNo hotbars saved for %s.', key)
            end
        end
    elseif sub == 'help' then
        for _, h in ipairs(plugin.help) do print(h) end
    else
        log('usage: /ac btn [toggle|show|hide|<n>|new|add [aa|gem|ability|disc|item|box|cmd]|exec <set> <index>|scope [group|zone|all|next] [hotbar]|list|reload|import [bm]|copy <server> <char>]')
    end
    return true
end

local function splitArgs(line)
    local out = {}
    for token in tostring(line or ''):gmatch('%S+') do out[#out + 1] = token end
    return out
end

-- /btn [n], /btnexec "<set>" <index>, /btncopy <server> <char> (Button Master parity)
local function bindBtn(...)
    local a = { ... }
    if a[1] == nil or a[1] == '' then
        handleCommand({})
    else
        handleCommand({ tostring(a[1]) })
    end
end

local function bindBtnExec(...)
    local a = { ... }
    handleCommand({ 'exec', a[1], a[2] })
end

local function bindBtnCopy(...)
    local a = { ... }
    handleCommand({ 'copy', a[1], a[2] })
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    local colors = core.colors or {}
    GOLD = colors.GOLD or GOLD
    MUTED = colors.MUTED or MUTED
    GOOD = colors.GOOD or GOOD
    WARN = colors.WARN or WARN
    ERR = colors.ERR or ERR
    if ctrl and ctrl.show_buttons == nil then ctrl.show_buttons = true end
    state.charKey = nil
    state.scripts = {}
    state.activeSet = {}
    state.reloadPending = false
    loadDb()
    if mq and mq.bind then
        for _, b in ipairs({ { '/btn', bindBtn }, { '/btnexec', bindBtnExec }, { '/btncopy', bindBtnCopy } }) do
            if mq.unbind then pcall(mq.unbind, b[1]) end
            local ok = pcall(mq.bind, b[1], b[2])
            if ok then state.bindsBound[#state.bindsBound + 1] = b[1] end
        end
    end
end

function plugin.onDestroy()
    if state.boxnetUnsub then
        pcall(state.boxnetUnsub)
        state.boxnetUnsub = nil
    end
    if mq and mq.unbind then
        for _, b in ipairs(state.bindsBound) do pcall(mq.unbind, b) end
    end
    state.bindsBound = {}
    state.scripts = {}
    closeEditor()
    imp.open = false
    browser.open = false
    browser.lists = {}
end

function plugin.onTick()
    if not core or not state.loaded then return end
    refresh()
    tick()
end

function plugin.onDrawUI()
    if not core or not state.loaded then return end
    refresh()
    state.frame = state.frame + 1
    pumpScripts()
    if ctrl.show_buttons then
        for i, hb in ipairs(hotbars()) do drawHotbar(hb, i) end
    end
    drawEditor()
    drawPicker()
    drawImport()
    drawBrowser()
end

-- Zoning changes what the character carries; the item list rescans on the
-- next look (the gem list follows the memorized-gem fingerprint).
function plugin.onZoned()
    browser.lists.Item = nil
    browser.gemFp = nil
end

function plugin.onSaveSettings()
    return { syncBoxes = prefs.syncBoxes == true, announceRun = prefs.announceRun == true }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.syncBoxes ~= nil then prefs.syncBoxes = (s.syncBoxes == true) end
    if s.announceRun ~= nil then prefs.announceRun = (s.announceRun == true) end
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    core.accent(GOLD, 'Hot Buttons (Button Master-style hotbars)')
    local isOpen = ctrl.show_buttons == true and anyHotbarVisible()
    if ImGui.Button((isOpen and 'Hotbars: Visible (Click to Hide)' or 'Hotbars: Hidden (Click to Show)') .. '##btnToggleWin', core.px(250), core.px(24)) then
        setAllVisible(not isOpen)
    end
    ImGui.SameLine()
    if ImGui.Button('New Hotbar##btnNewHb', core.px(110), core.px(24)) then newHotbarForMe() end
    ImGui.TextDisabled(string.format('%d button(s), %d set(s) in the shared library; %d hotbar(s) for this character.',
        tableSize(db and db.buttons), tableSize(db and db.sets), #hotbars()))
    ImGui.TextDisabled('Library file: ' .. plugin.configPath())

    local sync = ImGui.Checkbox('Sync with other boxes (reload when another Triune box saves; needs Box Network)##btnSync', prefs.syncBoxes)
    if sync ~= prefs.syncBoxes then
        prefs.syncBoxes = sync
        core.saveLoadout(true)
    end
    local ann = ImGui.Checkbox('Announce button executions in chat##btnAnnounce', prefs.announceRun)
    if ann ~= prefs.announceRun then
        prefs.announceRun = ann
        core.saveLoadout(true)
    end

    ImGui.Separator()
    core.accent(GOLD, 'Import')
    if ImGui.Button('Import Button Master Config##btnImportBm', core.px(220), core.px(24)) then
        local ok, msg = importButtonMasterConfig()
        if not ok then state.bmImportResult = tostring(msg) end
    end
    if ImGui.IsItemHovered() then core.setTooltip('Reads ' .. plugin.bmConfigPath() .. ' and adds its buttons, sets, and this character\'s hotbars.') end
    ImGui.SameLine()
    if ImGui.Button('Import Share String...##btnImportShare', core.px(180), core.px(24)) then
        imp.open = true
        imp.hbId = 1
    end
    ImGui.SameLine()
    if ImGui.Button('Reload Library##btnReload', core.px(120), core.px(24)) then
        loadDb()
        setStatus('Reloaded.')
    end
    if state.bmImportResult then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], state.bmImportResult)
    end
    ImGui.TextDisabled('Hotbar options (sets, size, font, title bar, compact mode, search, share) live in each hotbar\'s right-click menu (window background, a slot, or a tab).')
    ImGui.TextDisabled('Commands: /ac btn, /btn [n], /btnexec "<set>" <index>, /btncopy <server> <char>')
    if state.statusMsg ~= '' and (os.clock() - state.statusAt) < 6 then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], state.statusMsg)
    end
end

-- /ac btn | buttons | hotbar | hotbars
function plugin.onCommand(cmd, args)
    if cmd ~= 'btn' and cmd ~= 'buttons' and cmd ~= 'hotbar' and cmd ~= 'hotbars' then return false end
    refresh()
    local rest = {}
    for i = 2, #(args or {}) do rest[#rest + 1] = args[i] end
    return handleCommand(rest)
end

plugin.help = {
    '  \ag/ac btn | buttons\ax - Toggle the Hot Buttons hotbars (Button Master-style)',
    '  \ag/ac btn <n>\ax - Show / hide hotbar n     \ag/ac btn new\ax - Create a hotbar',
    '  \ag/ac btn add [aa|gem|ability|disc|item|box|cmd]\ax - Browse your AAs / gems / abilities / discs / clickies and add one as a button',
    '  \ag/ac btn exec <set> <index>\ax - Fire a button   \ag/ac btn import bm\ax - Import ButtonMaster.lua',
    '  \ag/ac btn scope [group|zone|all|next] [hotbar]\ax - Where a hotbar\'s Box Control buttons send (its Group / Zone / All switch)',
    '  \ag/btn [n]\ax, \ag/btnexec "<set>" <index>\ax, \ag/btncopy <server> <char>\ax - Button Master-compatible binds',
}

-- The plugin window: the header button / Window Layout entry toggles every
-- hotbar of this character (ctrl.show_buttons); each hotbar also has its own
-- visible flag in the shared file so /btn <n> can hide one bar.
plugin.window = {
    label = 'Buttons',
    tooltip = 'Toggles the Hot Buttons hotbars (buttons plugin): Button Master-style button bars.',
    flag = 'show_buttons',
    key = 'buttons',
    desc = 'Hot button bars (Button Master-style)',
    headerButton = true,
    order = 105,
    isOpen = function()
        return ctrl ~= nil and ctrl.show_buttons == true and db ~= nil and anyHotbarVisible()
    end,
    setOpen = function(val)
        if not ctrl or not db then return end
        setAllVisible(val == true)
    end,
}

-- Exposed for tests
plugin._ = {
    state = state, edit = edit, imp = imp, prefs = prefs, cacheFor = cacheFor, browser = browser,
    scanAAs = scanAAs, scanGems = scanGems, scanAbilities = scanAbilities, scanDiscs = scanDiscs, scanItems = scanItems,
    browserList = browserList, openBrowser = openBrowser, pickBrowserEntry = pickBrowserEntry, firstFreeSlot = firstFreeSlot,
    scanCommands = scanCommands, parseHelpLine = parseHelpLine, commandNeedsEdit = commandNeedsEdit, CORE_COMMANDS = CORE_COMMANDS,
    scanBoxControl = scanBoxControl, boxPresetButton = boxPresetButton, addBoxControlSet = addBoxControlSet, BOX_PRESETS = BOX_PRESETS, BOX_SCOPES = BOX_SCOPES,
    BAR_SCOPES = BAR_SCOPES, BOX_SCOPE_TOKEN = BOX_SCOPE_TOKEN, usesBoxScope = usesBoxScope, hotbarUsesBoxScope = hotbarUsesBoxScope,
    hotbarBoxScope = hotbarBoxScope, resolveBoxScope = resolveBoxScope, setHotbarBoxScope = setHotbarBoxScope, hotbarForSet = hotbarForSet,
    getDb = function() return db end,
    setDb = function(d) db = normalizeDb(d) cache = {} end,
    loadDb = loadDb, saveDb = saveDb, defaultDb = defaultDb, normalizeDb = normalizeDb,
    charKey = charKey, myChar = myChar, hotbars = hotbars, newHotbar = newHotbar,
    serialize = serialize, b64enc = b64enc, b64dec = b64dec,
    buttonFromBm = buttonFromBm, buttonToBm = buttonToBm, encodeShare = encodeShare, decodeShare = decodeShare,
    shareButton = shareButton, shareSet = shareSet, importShare = importShare, importButtonMasterConfig = importButtonMasterConfig,
    nextButtonKey = nextButtonKey, uniqueSetName = uniqueSetName, buttonAt = buttonAt, lastAssignedIndex = lastAssignedIndex,
    addButton = addButton, assignButton = assignButton, unassignButton = unassignButton, deleteButton = deleteButton,
    swapSlots = swapSlots, createSet = createSet, deleteSet = deleteSet, renameSet = renameSet,
    addSetToHotbar = addSetToHotbar, removeSetFromHotbar = removeSetFromHotbar, moveSetInHotbar = moveSetInHotbar,
    newHotbarForMe = newHotbarForMe, deleteHotbar = deleteHotbar, copyHotbarsFrom = copyHotbarsFrom, anyHotbarVisible = anyHotbarVisible,
    readCooldown = readCooldown, evaluateButton = evaluateButton, isLuaButton = isLuaButton, runButton = runButton,
    fireButton = fireButton, execBySetIndex = execBySetIndex, tick = tick, pumpScripts = pumpScripts, buttonFromCursor = buttonFromCursor,
    gridLayout = gridLayout, alphaGroupFor = alphaGroupFor, fmtTime = fmtTime, split = split, lines = lines,
    openEditor = openEditor, saveEditor = saveEditor, closeEditor = closeEditor, slotClicked = slotClicked,
    handleCommand = handleCommand, splitArgs = splitArgs, setAllVisible = setAllVisible, toggleHotbar = toggleHotbar,
    TIMER_TYPES = TIMER_TYPES, MAX_SLOTS = MAX_SLOTS, BUTTON_PALETTE = BUTTON_PALETTE, TEXT_PALETTE = TEXT_PALETTE,
    BUTTON_FONT_SCALES = BUTTON_FONT_SCALES, sameRgb = sameRgb,
}

return plugin
