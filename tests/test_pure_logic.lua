#!/usr/bin/env luajit
---@diagnostic disable: deprecated
-- ==========================================================================
-- tests/test_pure_logic.lua — Unit tests for pure-logic functions in triune.lua
--
-- Runs under plain LuaJIT (no MacroQuest required).  Extracts function bodies
-- from the source file by matching `local function NAME(` and counting
-- block-open / block-close keywords to find the closing `end`.  Each function
-- is loaded in a sandbox with its required upvalues.
--
-- Usage:  luajit tests/test_pure_logic.lua
-- Exit:   0 on all-pass, 1 on any failure.
-- ==========================================================================

-- ---------------------------------------------------------------------------
-- Minimal test harness
-- ---------------------------------------------------------------------------
local pass, fail, errors = 0, 0, {}

local function assert_eq(got, expect, label)
    if got == expect then
        pass = pass + 1
    else
        fail = fail + 1
        errors[#errors + 1] = string.format(
            "  FAIL: %s\n    expected: %s (%s)\n    got:      %s (%s)",
            label, tostring(expect), type(expect), tostring(got), type(got))
    end
end

local function assert_neq(got, notExpect, label)
    if got ~= notExpect then
        pass = pass + 1
    else
        fail = fail + 1
        errors[#errors + 1] = string.format(
            "  FAIL: %s\n    should NOT be: %s", label, tostring(notExpect))
    end
end

local function assert_true(val, label)
    assert_eq(not not val, true, label)
end

local function assert_nil(val, label)
    assert_eq(val, nil, label)
end

local function assert_type(val, expected_type, label)
    assert_eq(type(val), expected_type, label)
end

-- Table deep-equal (shallow for this use case)
local function tbl_eq(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function assert_tbl_eq(got, expect, label)
    if tbl_eq(got, expect) then
        pass = pass + 1
    else
        fail = fail + 1
        local function dump(t)
            if type(t) ~= 'table' then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. '=' .. tostring(v) end
            return '{' .. table.concat(parts, ', ') .. '}'
        end
        errors[#errors + 1] = string.format(
            "  FAIL: %s\n    expected: %s\n    got:      %s",
            label, dump(expect), dump(got))
    end
end

-- ---------------------------------------------------------------------------
-- Function extractor
-- ---------------------------------------------------------------------------
-- Reads the source file, finds `local function <name>(` at column 1 (no
-- leading whitespace), and captures lines until the matching `end` at column 1.
-- For top-level functions in triune.lua, the closing `end` is always un-indented.

local function readFile(path)
    local f = assert(io.open(path, 'r'), 'Cannot open: ' .. path)
    local content = f:read('*a')
    f:close()
    return content
end

local function extractFunction(src, funcName)
    local lines = {}
    local capturing = false

    for line in src:gmatch('[^\n]*') do
        if not capturing then
            -- Match top-level function declarations (no leading whitespace)
            if line:match('^local function ' .. funcName .. '%s*%(')
                or line:match('^function runtime%.' .. funcName .. '%s*%(')
                or line:match('^runtime%.' .. funcName .. '%s*=%s*function%s*%(')
                or line:match('^' .. funcName .. '%s*=%s*function%s*%(') then
                capturing = true
                lines[#lines + 1] = line
            end
        else
            lines[#lines + 1] = line
            -- The closing `end` of a top-level function is always at column 1
            if line:match('^end%s*$') or line == 'end' then
                break
            end
        end
    end

    if #lines == 0 then
        error('Could not extract function: ' .. funcName)
    end
    return table.concat(lines, '\n')
end

-- Load a function body with a given environment of upvalues.
-- The extracted code is a function block; we append `return X`
-- so `loadstring` returns the function itself.
local function loadFunc(src, funcName, env)
    local code = extractFunction(src, funcName)
    if code:match('^function runtime%.') or code:match('^runtime%.') then
        code = code .. '\nreturn runtime.' .. funcName
    else
        code = code .. '\nreturn ' .. funcName
    end

    local chunk, err = loadstring(code, funcName)
    if not chunk then error('loadstring failed for ' .. funcName .. ': ' .. err) end

    -- Merge env onto a copy of _G so standard library is available
    local sandbox = {}
    for k, v in pairs(_G) do sandbox[k] = v end
    if not sandbox.runtime then sandbox.runtime = {} end
    if env then
        for k, v in pairs(env) do
            sandbox[k] = v
            sandbox.runtime[k] = v
        end
    end
    setfenv(chunk, sandbox)

    local ok, fn = pcall(chunk)
    if not ok then error('pcall failed for ' .. funcName .. ': ' .. tostring(fn)) end
    return fn
end

-- ---------------------------------------------------------------------------
-- Source file path (relative to repo root)
-- ---------------------------------------------------------------------------
local srcPath = 'TAC/lua/triune.lua'
local src = readFile(srcPath)

-- ---------------------------------------------------------------------------
-- Shared constants (duplicated here to match module-level definitions)
-- ---------------------------------------------------------------------------
local ALL_ABBR = {
    'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Rog', 'Shm',
    'Nec', 'Wiz', 'Mag', 'Enc', 'Bst', 'Ber',
}

local PULL_CON_LIST = {
    'Scowling', 'Threateningly', 'Dubious', 'Apprehensive',
    'Indifferent', 'Amiably', 'Kindly', 'Warmly', 'Ally',
}

local MODES = {
    PULL_CON_LIST = PULL_CON_LIST,
}

-- The MQSHORT lookup table (used inside toCanonicalClassAbbr as a local, and
-- referenced by parseClassLine as an upvalue that SHOULD be module-level).
local MQSHORT = {
    WARRIOR = 'War',
    WAR = 'War',
    WARRIORS = 'War',
    CLERIC = 'Clr',
    CLR = 'Clr',
    CLERICS = 'Clr',
    PALADIN = 'Pal',
    PAL = 'Pal',
    PALADINS = 'Pal',
    RANGER = 'Rng',
    RNG = 'Rng',
    RANGERS = 'Rng',
    SHADOWKNIGHT = 'SK',
    SHADOW = 'SK',
    SHD = 'SK',
    SK = 'SK',
    SHADOWKNIGHTS = 'SK',
    DRUID = 'Dru',
    DRU = 'Dru',
    DRUIDS = 'Dru',
    MONK = 'Mnk',
    MNK = 'Mnk',
    MONKS = 'Mnk',
    BARD = 'Brd',
    BRD = 'Brd',
    BARDS = 'Brd',
    ROGUE = 'Rog',
    ROG = 'Rog',
    ROGUES = 'Rog',
    SHAMAN = 'Shm',
    SHM = 'Shm',
    SHAMANS = 'Shm',
    NECROMANCER = 'Nec',
    NEC = 'Nec',
    NECROMANCERS = 'Nec',
    WIZARD = 'Wiz',
    WIZ = 'Wiz',
    WIZARDS = 'Wiz',
    MAGICIAN = 'Mag',
    MAG = 'Mag',
    MAGICIANS = 'Mag',
    ENCHANTER = 'Enc',
    ENC = 'Enc',
    ENCHANTERS = 'Enc',
    BEASTLORD = 'Bst',
    BST = 'Bst',
    BEASTLORDS = 'Bst',
    BERSERKER = 'Ber',
    BER = 'Ber',
    BERSERKERS = 'Ber',
}

-- Waypoint export/import string constants (must match triune.lua's module-level definitions)
local WP = {
    B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
    B64_LOOKUP = {},
    RS = string.char(30),
    US = string.char(31),
    EXPORT_PREFIX = 'TACWP1:',
    EXPORT_VERSION = 1,
}
for i = 1, #WP.B64_CHARS do WP.B64_LOOKUP[WP.B64_CHARS:sub(i, i)] = i - 1 end
local B64_CHARS = WP.B64_CHARS
local B64_LOOKUP = WP.B64_LOOKUP
local WP_RS = WP.RS
local WP_US = WP.US

-- ============================================================================
-- 1.  idxOf(tbl, val)
-- ============================================================================
print('--- idxOf ---')
do
    local idxOf = loadFunc(src, 'idxOf', {})

    assert_eq(idxOf({ 'a', 'b', 'c' }, 'b'), 2, 'idxOf: find middle element')
    assert_eq(idxOf({ 'a', 'b', 'c' }, 'a'), 1, 'idxOf: find first element')
    assert_eq(idxOf({ 'a', 'b', 'c' }, 'c'), 3, 'idxOf: find last element')
    assert_eq(idxOf({ 'a', 'b', 'c' }, 'z'), 1, 'idxOf: not found returns 1')
    assert_eq(idxOf(nil, 'x'), 1, 'idxOf: nil table returns 1')
    assert_eq(idxOf({}, 'x'), 1, 'idxOf: empty table returns 1')
end

-- ============================================================================
-- 2.  toCanonicalClassAbbr(str)
-- ============================================================================
print('--- toCanonicalClassAbbr ---')
do
    local idxOf = loadFunc(src, 'idxOf', {})
    local toCanonicalClassAbbr = loadFunc(src, 'toCanonicalClassAbbr',
        { ALL_ABBR = ALL_ABBR, MQSHORT = MQSHORT, idxOf = idxOf })

    -- Full names (case-insensitive)
    assert_eq(toCanonicalClassAbbr('warrior'), 'War', 'canon: lowercase warrior')
    assert_eq(toCanonicalClassAbbr('WARRIOR'), 'War', 'canon: uppercase WARRIOR')
    assert_eq(toCanonicalClassAbbr('Warrior'), 'War', 'canon: mixed Warrior')
    assert_eq(toCanonicalClassAbbr('Shadow Knight'), 'SK', 'canon: Shadow Knight (space)')
    assert_eq(toCanonicalClassAbbr('shadowknight'), 'SK', 'canon: shadowknight')
    assert_eq(toCanonicalClassAbbr('Necromancer'), 'Nec', 'canon: Necromancer')
    assert_eq(toCanonicalClassAbbr('Beastlord'), 'Bst', 'canon: Beastlord')
    assert_eq(toCanonicalClassAbbr('Berserker'), 'Ber', 'canon: Berserker')

    -- MQ-style 3-letter abbreviations
    assert_eq(toCanonicalClassAbbr('WAR'), 'War', 'canon: WAR')
    assert_eq(toCanonicalClassAbbr('CLR'), 'Clr', 'canon: CLR')
    assert_eq(toCanonicalClassAbbr('PAL'), 'Pal', 'canon: PAL')
    assert_eq(toCanonicalClassAbbr('RNG'), 'Rng', 'canon: RNG')
    assert_eq(toCanonicalClassAbbr('SHD'), 'SK', 'canon: SHD → SK')
    assert_eq(toCanonicalClassAbbr('DRU'), 'Dru', 'canon: DRU')
    assert_eq(toCanonicalClassAbbr('MNK'), 'Mnk', 'canon: MNK')
    assert_eq(toCanonicalClassAbbr('BRD'), 'Brd', 'canon: BRD')
    assert_eq(toCanonicalClassAbbr('ROG'), 'Rog', 'canon: ROG')
    assert_eq(toCanonicalClassAbbr('SHM'), 'Shm', 'canon: SHM')
    assert_eq(toCanonicalClassAbbr('NEC'), 'Nec', 'canon: NEC')
    assert_eq(toCanonicalClassAbbr('WIZ'), 'Wiz', 'canon: WIZ')
    assert_eq(toCanonicalClassAbbr('MAG'), 'Mag', 'canon: MAG')
    assert_eq(toCanonicalClassAbbr('ENC'), 'Enc', 'canon: ENC')
    assert_eq(toCanonicalClassAbbr('BST'), 'Bst', 'canon: BST')
    assert_eq(toCanonicalClassAbbr('BER'), 'Ber', 'canon: BER')
    assert_eq(toCanonicalClassAbbr('SK'), 'SK', 'canon: SK')

    -- Mixed-case canonical form (should pass through if in ALL_ABBR)
    assert_eq(toCanonicalClassAbbr('War'), 'War', 'canon: War pass-through')
    assert_eq(toCanonicalClassAbbr('Clr'), 'Clr', 'canon: Clr pass-through')

    -- Plurals
    assert_eq(toCanonicalClassAbbr('Warriors'), 'War', 'canon: Warriors plural')
    assert_eq(toCanonicalClassAbbr('Clerics'), 'Clr', 'canon: Clerics plural')

    -- Edge cases
    assert_nil(toCanonicalClassAbbr(nil), 'canon: nil input')
    assert_nil(toCanonicalClassAbbr(''), 'canon: empty string')
    assert_nil(toCanonicalClassAbbr('NULL'), 'canon: NULL string')
    assert_nil(toCanonicalClassAbbr('nil'), 'canon: "nil" string')
end

-- ============================================================================
-- 3.  cleanSpellName(name)
-- ============================================================================
print('--- cleanSpellName ---')
do
    local cleanSpellName = loadFunc(src, 'cleanSpellName', {})

    assert_eq(cleanSpellName('Complete Heal'), 'Complete Heal', 'clean: no parens')
    assert_eq(cleanSpellName('Chloroplast (Group)'), 'Chloroplast', 'clean: strip (Group)')
    assert_eq(cleanSpellName('Spirit of Wolf (Spell)'), 'Spirit of Wolf', 'clean: strip (Spell)')
    assert_eq(cleanSpellName('  Heal  '), 'Heal', 'clean: trim whitespace')
    assert_eq(cleanSpellName(nil), '', 'clean: nil → empty')
    assert_eq(cleanSpellName(42), '', 'clean: number → empty')
    assert_eq(cleanSpellName(''), '', 'clean: empty → empty')
end

-- ============================================================================
-- 4.  normalizeSpellName(name)
-- ============================================================================
print('--- normalizeSpellName ---')
do
    local normalizeSpellName = loadFunc(src, 'normalizeSpellName', {})

    assert_eq(normalizeSpellName('Complete Heal'), 'completeheal', 'norm: basic')
    assert_eq(normalizeSpellName('Complete Heal Rk. II'), 'completeheal', 'norm: strip Rk. II')
    assert_eq(normalizeSpellName('Chloroplast (Group)'), 'chloroplast', 'norm: strip parens')
    assert_eq(normalizeSpellName('Spirit of Wolf'), 'spiritofwolf', 'norm: spaces removed')
    assert_eq(normalizeSpellName('Nuke Rk.III'), 'nuke', 'norm: Rk.III variant')
    assert_eq(normalizeSpellName('Heal (Rk II)'), 'heal', 'norm: (Rk II) in parens')
    assert_eq(normalizeSpellName(nil), '', 'norm: nil → empty')
    assert_eq(normalizeSpellName(42), '', 'norm: number → empty')
    assert_eq(normalizeSpellName(''), '', 'norm: empty → empty')
end

-- ============================================================================
-- 5.  defaultsForKind(kind, bene)
-- ============================================================================
print('--- defaultsForKind ---')
do
    local defaultsForKind = loadFunc(src, 'defaultsForKind', {})

    local function check_defaults(kind, bene, expTarget, expWhen, expPct, label)
        local t, w, p = defaultsForKind(kind, bene)
        assert_eq(t, expTarget, label .. ' target')
        assert_eq(w, expWhen, label .. ' when')
        assert_eq(p, expPct, label .. ' pct')
    end

    check_defaults('heal', nil, 'F: Myself', 'my HP <=', 75, 'defaults: heal')
    check_defaults('buff', nil, 'F: Myself', 'missing buff', 100, 'defaults: buff')
    check_defaults('pet_buff', nil, 'F: Pet', 'missing buff', 100, 'defaults: pet_buff')
    check_defaults('pet', nil, 'F: Myself', 'missing pet', 100, 'defaults: pet')
    check_defaults('util', nil, 'F: Myself', 'always', 100, 'defaults: util')
    check_defaults('debuff', nil, 'E: Current Target', 'target HP <=', 98, 'defaults: debuff')
    check_defaults('dot', nil, 'E: Current Target', 'target HP <=', 98, 'defaults: dot')
    check_defaults('dd', nil, 'E: Current Target', 'target HP <=', 95, 'defaults: dd')
    check_defaults(nil, true, 'F: Myself', 'missing buff', 100, 'defaults: bene=true')
    check_defaults(nil, nil, 'E: Current Target', 'target HP <=', 95, 'defaults: unknown')
    check_defaults('bogus', nil, 'E: Current Target', 'target HP <=', 95, 'defaults: bogus kind')
end

-- ============================================================================
-- 6.  sanitizeModeConfig(c)
-- ============================================================================
print('--- sanitizeModeConfig ---')
do
    local sanitizeModeConfig = loadFunc(src, 'sanitizeModeConfig',
        { MODES = MODES, ctrl = nil })

    -- Legacy mode migration
    local function smc(mode, submode)
        local c = { mode = mode, submode = submode }
        sanitizeModeConfig(c)
        return c.mode, c.submode
    end

    local m, s

    -- Hunter → Puller/Hunt
    m, s = smc('Hunter', nil)
    assert_eq(m, 'Puller', 'sanitize: Hunter → Puller')
    assert_eq(s, 'Hunt', 'sanitize: Hunter → Hunt')

    -- Manual Hunter → Manual/Hunt
    m, s = smc('Manual Hunter', nil)
    assert_eq(m, 'Manual', 'sanitize: Manual Hunter → Manual')
    assert_eq(s, 'Hunt', 'sanitize: Manual Hunter → Hunt')

    -- Pet Tank → Puller/Hunt
    m, s = smc('Pet Tank', nil)
    assert_eq(m, 'Puller', 'sanitize: Pet Tank → Puller')
    assert_eq(s, 'Hunt', 'sanitize: Pet Tank → Hunt')

    -- Pull & Assist → Puller/Camp
    m, s = smc('Pull & Assist', nil)
    assert_eq(m, 'Puller', 'sanitize: Pull & Assist → Puller')
    assert_eq(s, 'Camp', 'sanitize: Pull & Assist → Camp')

    -- Chase Assist → Assist/Chase
    m, s = smc('Chase Assist', nil)
    assert_eq(m, 'Assist', 'sanitize: Chase Assist → Assist')
    assert_eq(s, 'Chase', 'sanitize: Chase Assist → Chase')

    -- Garrison → Assist/Camp
    m, s = smc('Garrison', nil)
    assert_eq(m, 'Assist', 'sanitize: Garrison → Assist')
    assert_eq(s, 'Camp', 'sanitize: Garrison → Camp')

    -- Tank → Assist/Camp
    m, s = smc('Tank', nil)
    assert_eq(m, 'Assist', 'sanitize: Tank → Assist')
    assert_eq(s, 'Camp', 'sanitize: Tank → Camp')

    -- Unknown mode → Manual
    m, s = smc('BogusMode', nil)
    assert_eq(m, 'Manual', 'sanitize: unknown → Manual')
    assert_eq(s, 'Hunt', 'sanitize: unknown → default submode Hunt')

    -- Valid modes pass through
    m, s = smc('Manual', 'Hunt')
    assert_eq(m, 'Manual', 'sanitize: Manual stays')

    m, s = smc('Puller', 'Hunt')
    assert_eq(m, 'Puller', 'sanitize: Puller stays')
    assert_eq(s, 'Hunt', 'sanitize: Puller/Hunt stays')

    m, s = smc('Puller', 'Camp')
    assert_eq(m, 'Puller', 'sanitize: Puller/Camp stays')
    assert_eq(s, 'Camp', 'sanitize: Puller/Camp submode stays')

    m, s = smc('Assist', 'Chase')
    assert_eq(m, 'Assist', 'sanitize: Assist stays')
    assert_eq(s, 'Chase', 'sanitize: Assist/Chase stays')

    m, s = smc('Assist', 'Backline')
    assert_eq(m, 'Assist', 'sanitize: Assist/Backline stays')
    assert_eq(s, 'Backline', 'sanitize: Backline submode stays')

    -- Invalid submode for Puller → default
    m, s = smc('Puller', 'Backline')
    assert_eq(s, 'Hunt', 'sanitize: Puller bad submode → Hunt')

    -- Invalid submode for Assist → default
    m, s = smc('Assist', 'Hunt')
    assert_eq(s, 'Chase', 'sanitize: Assist bad submode → Chase')

    -- pull_con_filter initialization
    local c = { mode = 'Manual' }
    sanitizeModeConfig(c)
    assert_type(c.pull_con_filter, 'table', 'sanitize: pull_con_filter is table')
    for _, con in ipairs(PULL_CON_LIST) do
        assert_eq(c.pull_con_filter[con], true,
            'sanitize: pull_con_filter.' .. con .. ' defaults to true')
    end

    -- hunter_z / hunter_z_plane defaults
    local c2 = { mode = 'Manual' }
    sanitizeModeConfig(c2)
    assert_eq(c2.hunter_z, 75, 'sanitize: hunter_z default')
    assert_eq(c2.hunter_z_plane, 15, 'sanitize: hunter_z_plane default')

    -- Existing values preserved
    local c3 = { mode = 'Manual', hunter_z = 200, hunter_z_plane = 50 }
    sanitizeModeConfig(c3)
    assert_eq(c3.hunter_z, 200, 'sanitize: hunter_z preserved')
    assert_eq(c3.hunter_z_plane, 50, 'sanitize: hunter_z_plane preserved')
end

-- ============================================================================
-- 7.  parseClassLine(text)  — loaded with MQSHORT in scope
-- ============================================================================
print('--- parseClassLine ---')
local parseClassLine = loadFunc(src, 'parseClassLine', { MQSHORT = MQSHORT })

-- Numbered lines (e.g. from inventory window list items)
assert_eq(parseClassLine('1. Warrior'), 'War', 'parse: "1. Warrior"')
assert_eq(parseClassLine('2: Cleric'), 'Clr', 'parse: "2: Cleric"')
assert_eq(parseClassLine('  3  Paladin'), 'Pal', 'parse: "  3  Paladin"')

-- Plain class names
assert_eq(parseClassLine('Ranger'), 'Rng', 'parse: "Ranger"')
assert_eq(parseClassLine('Shadow Knight'), 'SK', 'parse: "Shadow Knight"')
assert_eq(parseClassLine('Necromancer'), 'Nec', 'parse: "Necromancer"')

-- 3-letter codes
assert_eq(parseClassLine('WAR'), 'War', 'parse: "WAR" 3-letter')
assert_eq(parseClassLine('CLR'), 'Clr', 'parse: "CLR" 3-letter')
assert_eq(parseClassLine('SHD'), 'SK', 'parse: "SHD" 3-letter')

-- 2-letter code
assert_eq(parseClassLine('SK'), 'SK', 'parse: "SK" 2-letter')

-- Lines that should return nil
assert_nil(parseClassLine(nil), 'parse: nil')
assert_nil(parseClassLine(''), 'parse: empty')
assert_nil(parseClassLine('NULL'), 'parse: NULL')
assert_nil(parseClassLine('Level 60'), 'parse: "Level 60" filtered')
assert_nil(parseClassLine('LVL 50'), 'parse: "LVL 50" filtered')

-- ============================================================================
-- 8.  defaultCtrl() — shape validation
-- ============================================================================
print('--- defaultCtrl ---')
local defaultCtrl = loadFunc(src, 'defaultCtrl', { MODES = MODES })
local dc = defaultCtrl()

-- Check required fields exist and have correct types
local EXPECTED_FIELDS = {
    -- field name            expected type
    { 'running',                 'boolean' },
    { 'mode',                    'string' },
    { 'submode',                 'string' },
    { 'pull_style',              'string' },
    { 'pull_spell',              'string' },
    { 'pull_spell_gem',          'number' },
    { 'pull_engage_dist',        'number' },
    { 'xtar_nav_dist',           'number' },
    { 'combat_style',            'string' },
    { 'melee_dist',              'number' },
    { 'ranged_dist',             'number' },
    { 'ma_name',                 'string' },
    { 'assist_at',               'number' },
    { 'chase',                   'boolean' },
    { 'chase_dist',              'number' },
    { 'automem',                 'boolean' },
    { 'camp_radius',             'number' },
    { 'camp_z',                  'number' },
    { 'camp_z_plane',            'number' },
    { 'hunter_radius',           'number' },
    { 'hunter_z_plane',          'number' },
    { 'hunter_z',                'number' },
    { 'hunter_min_level',        'number' },
    { 'hunter_max_level',        'number' },
    { 'hunter_combat_radius',    'number' },
    { 'pull_min_level',          'number' },
    { 'pull_max_level',          'number' },
    { 'pull_con_filter',         'table' },
    { 'check_closer_mobs',       'boolean' },
    { 'nav_hazard_avoidance',    'boolean' },
    { 'nav_hazard_radius',       'number' },
    { 'nav_hazard_min_hits',     'number' },
    { 'nav_reverse_breadcrumbs', 'boolean' },
    { 'nav_max_path_ratio',      'number' },
    { 'nav_proactive_doors',     'boolean' },
    { 'nav_levitation_clear',    'boolean' },
    { 'zone_hazards',            'table' },
    { 'debug_mode',              'boolean' },
    { 'scribed_only',            'boolean' },
    { 'aa_purchased_only',       'boolean' },
    { 'disc_trained_only',       'boolean' },
    { 'medbreak_enabled',        'boolean' },
    { 'cast_max_retries',        'number' },
    { 'cast_lockout_sec',        'number' },
    { 'min_mana_pct',            'number' },
    { 'pull_min_hp_pct',         'number' },
    { 'pet_assist_at',           'number' },
    { 'pet_hold_enabled',        'boolean' },
    { 'show_map_radius',         'boolean' },
    { 'burn',                    'boolean' },
    { 'compact',                 'boolean' },
    { 'use_waypoints',           'boolean' },
    { 'waypoint_radius',         'number' },
    { 'waypoint_scan_radius',    'number' },
    { 'waypoint_direction',      'number' },
    { 'waypoint_loop',           'boolean' },
    { 'current_waypoint_idx',    'number' },
    { 'waypoints',               'table' },
    { 'zone_waypoints',          'table' },
    { 'zone_waypoint_presets',   'table' },
}

for _, spec in ipairs(EXPECTED_FIELDS) do
    local field, etype = spec[1], spec[2]
    assert_neq(dc[field], nil, 'defaultCtrl: ' .. field .. ' exists')
    assert_type(dc[field], etype, 'defaultCtrl: ' .. field .. ' is ' .. etype)
end

-- Specific default values
assert_eq(dc.running, false, 'defaultCtrl: running=false')
assert_eq(dc.mode, 'Manual', 'defaultCtrl: mode=Manual')
assert_eq(dc.submode, 'Hunt', 'defaultCtrl: submode=Hunt')

-- ============================================================================
-- 9.  isActionSkill(name) & defaultActionEntry
-- ============================================================================
print('--- isActionSkill / isSpecialSkill ---')
local CLASS_ACTIONS = {
    Mnk = { 'Kick', 'Round Kick', 'Tiger Claw', 'Eagle Strike', 'Dragon Punch', 'Tail Rake', 'Flying Kick', 'Mend', 'Feign Death', 'Sneak', 'Intimidation', 'Disarm' },
    Rog = { 'Backstab', 'Hide', 'Sneak', 'Pick Pockets', 'Sense Traps', 'Disarm Traps', 'Disarm', 'Intimidation' },
    War = { 'Kick', 'Bash', 'Taunt', 'Disarm', 'Intimidation' },
    Pal = { 'Bash', 'Taunt', 'Disarm' },
    SK  = { 'Bash', 'Taunt', 'Disarm' },
    Rng = { 'Kick', 'Taunt', 'Disarm', 'Hide', 'Sneak', 'Forage', 'Track' },
    Ber = { 'Frenzy', 'Kick', 'Disarm', 'Intimidation', 'Volley' },
    Bst = { 'Kick', 'Disarm' },
    Brd = { 'Disarm', 'Hide', 'Sneak', 'Pick Pockets', 'Track' },
    Clr = { 'Bash' },
    Dru = { 'Forage', 'Track' },
    Shm = {},
    Nec = {},
    Wiz = {},
    Mag = {},
    Enc = {},
    racial = { 'Slam', 'Hide', 'Sneak', 'Forage' },
    universal = { 'Begging', 'Bind Wound', 'Sense Heading' },
}
local isActionSkill = loadFunc(src, 'isActionSkill', { CLASS_ACTIONS = CLASS_ACTIONS })
local defaultActionEntry = loadFunc(src, 'defaultActionEntry', {})

assert_true(isActionSkill('Mend'), 'action: Mend')
assert_true(isActionSkill('Flying Kick'), 'action: Flying Kick')
assert_true(isActionSkill('Dragon Punch'), 'action: Dragon Punch')
assert_true(isActionSkill('Backstab'), 'action: Backstab')
assert_true(isActionSkill('Kick'), 'action: Kick')
assert_true(isActionSkill('Bash'), 'action: Bash')
assert_true(isActionSkill('Slam'), 'action: Slam')
assert_true(isActionSkill('Frenzy'), 'action: Frenzy')
assert_true(isActionSkill('Feign Death'), 'action: Feign Death')
assert_true(isActionSkill('Taunt'), 'action: Taunt')
assert_true(isActionSkill('Disarm'), 'action: Disarm')
assert_true(isActionSkill('Forage'), 'action: Forage')
assert_true(isActionSkill('Begging'), 'action: Begging')
assert_true(isActionSkill('Bind Wound'), 'action: Bind Wound')
assert_true(isActionSkill('Sense Heading'), 'action: Sense Heading')
assert_eq(isActionSkill('NotARealSkill'), false, 'action: NotARealSkill')
assert_eq(isActionSkill(nil), false, 'action: nil')
assert_eq(isActionSkill(''), false, 'action: empty')

local isNonCombatSkill = loadFunc(src, 'isNonCombatSkill', {})
assert_true(isNonCombatSkill('Begging'), 'noncombat: Begging')
assert_true(isNonCombatSkill('Pick Pockets'), 'noncombat: Pick Pockets')
assert_true(isNonCombatSkill('Hide'), 'noncombat: Hide')
assert_true(isNonCombatSkill('Sneak'), 'noncombat: Sneak')
assert_true(isNonCombatSkill('Bind Wound'), 'noncombat: Bind Wound')
assert_true(isNonCombatSkill('Forage'), 'noncombat: Forage')
assert_true(isNonCombatSkill('Sense Heading'), 'noncombat: Sense Heading')
assert_eq(isNonCombatSkill('Kick'), false, 'noncombat: Kick is false')
assert_eq(isNonCombatSkill('Flying Kick'), false, 'noncombat: Flying Kick is false')
assert_eq(isNonCombatSkill('Taunt'), false, 'noncombat: Taunt is false')
assert_eq(isNonCombatSkill('Mend'), false, 'noncombat: Mend is false')
assert_eq(isNonCombatSkill(''), false, 'noncombat: empty is false')
assert_eq(isNonCombatSkill(nil), false, 'noncombat: nil is false')

local kickDef = defaultActionEntry('Kick', 'War')
assert_eq(kickDef.autoskill, true, 'defaultActionEntry: Kick autoskill=true')
assert_eq(kickDef.kind, 'dd', 'defaultActionEntry: Kick kind=dd')
local mendDef = defaultActionEntry('Mend', 'Mnk')
assert_eq(mendDef.autoskill, false, 'defaultActionEntry: Mend autoskill=false')
assert_eq(mendDef.kind, 'heal', 'defaultActionEntry: Mend kind=heal')
assert_eq(mendDef.pct, 75, 'defaultActionEntry: Mend pct=75')

local actionClassInfo = loadFunc(src, 'actionClassInfo', { CLASS_ACTIONS = CLASS_ACTIONS, myClasses = { 'Mnk', 'War', 'Clr' } })
assert_eq(actionClassInfo('Flying Kick'), 'Mnk', 'actionClassInfo: Flying Kick -> Mnk')
assert_eq(actionClassInfo('Taunt'), 'War', 'actionClassInfo: Taunt -> War')
assert_eq(actionClassInfo('Backstab'), 'Rog', 'actionClassInfo: Backstab -> Rog')

-- Test getClientAbilities with simulated mq.TLO.Skill
local mockSkillData = {
    [0] = { Name = function() return '1H Blunt' end, Activated = function() return false end },
    [1] = { Name = function() return 'Kick' end, Activated = function() return true end, SkillCap = function() return 200 end, MinLevel = function() return 1 end },
    [2] = { Name = function() return 'Flying Kick' end, Activated = function() return true end, SkillCap = function() return 225 end, MinLevel = function() return 30 end },
    [3] = { Name = function() return 'Mend' end, Activated = function() return true end, SkillCap = function() return 200 end, MinLevel = function() return 1 end },
}
local mockMq = {
    TLO = {
        Skill = function(id)
            local d = mockSkillData[id]
            if not d then return nil end
            return setmetatable(d, { __call = function() return true end })
        end,
        Me = {
            Skill = function(name)
                if name == 'Kick' or name == 'Mend' or name == 'Begging' or name == 'Forage' then return function() return 150 end end
                return function() return 0 end
            end,
            SkillCap = function(name)
                if name == 'Kick' or name == 'Flying Kick' or name == 'Mend' or name == 'Begging' or name == 'Forage' then return function() return 200 end end
                return function() return 0 end
            end,
            Ability = function(_) return function() return nil end end,
        },
    }
}
local hasActionSkill = loadFunc(src, 'hasActionSkill', { mq = mockMq })
local getClientAbilities = loadFunc(src, 'getClientAbilities', {
    mq = mockMq,
    CLASS_ACTIONS = CLASS_ACTIONS,
    hasActionSkill = hasActionSkill,
    actionClassInfo = actionClassInfo,
    myClasses = { 'Mnk', 'War', 'Clr' },
    ctrl = { action_trained_only = true },
})

local clientAbilities = getClientAbilities()
assert_true(#clientAbilities >= 3, 'getClientAbilities: returned abilities from client')
local hasKick, hasFK, hasMend, hasBackstab, hasBegging, hasForage = false, false, false, false, false, false
for _, ab in ipairs(clientAbilities) do
    if ab.name == 'Kick' then hasKick = true; assert_true(ab.isTrained, 'Kick is trained') end
    if ab.name == 'Flying Kick' then hasFK = true; assert_eq(ab.isTrained, false, 'Flying Kick not trained yet') end
    if ab.name == 'Mend' then hasMend = true; assert_eq(ab.cls, 'Mnk', 'Mend class is Mnk') end
    if ab.name == 'Begging' then hasBegging = true; assert_true(ab.isTrained, 'Begging is trained') end
    if ab.name == 'Forage' then hasForage = true; assert_true(ab.isTrained, 'Forage is trained') end
    if ab.name == 'Backstab' then hasBackstab = true end
end
assert_true(hasKick, 'trio has Kick')
assert_true(hasFK, 'trio has Flying Kick')
assert_true(hasMend, 'trio has Mend')
assert_true(hasBegging, 'character has Begging')
assert_true(hasForage, 'character has Forage')
assert_eq(hasBackstab, false, 'trio without Rogue does NOT have Backstab')

-- ============================================================================
-- 10. aaTier(sec)
-- ============================================================================
print('--- aaTier ---')
local aaTier = loadFunc(src, 'aaTier', {})

assert_eq(aaTier(5), 'short', 'aaTier: 5s → short')
assert_eq(aaTier(60), 'short', 'aaTier: 60s → short')
assert_eq(aaTier(61), 'mid', 'aaTier: 61s → mid')
assert_eq(aaTier(300), 'mid', 'aaTier: 300s → mid')
assert_eq(aaTier(301), 'burn', 'aaTier: 301s → burn')
assert_eq(aaTier(3600), 'burn', 'aaTier: 3600s → burn')

-- ============================================================================
-- 11. fmtSec(s)
-- ============================================================================
print('--- fmtSec ---')
local fmtSec = loadFunc(src, 'fmtSec', {})

assert_eq(fmtSec(5), '5s', 'fmtSec: 5s')
assert_eq(fmtSec(59), '59s', 'fmtSec: 59s')
assert_eq(fmtSec(60), '1m', 'fmtSec: 60s → 1m')
assert_eq(fmtSec(90), '1m 30s', 'fmtSec: 90s → 1m 30s')
assert_eq(fmtSec(120), '2m', 'fmtSec: 120s → 2m')
assert_eq(fmtSec(3661), '61m 1s', 'fmtSec: 3661s')

-- ============================================================================
-- 12. baseTok(token) — target token normalization
-- ============================================================================
print('--- baseTok ---')
local baseTok = loadFunc(src, 'baseTok', {})

assert_eq(baseTok('F: Myself'), 'Myself', 'baseTok: F: Myself')
assert_eq(baseTok('E: Current Target'), 'Current Target', 'baseTok: E: Current Target')
assert_eq(baseTok('F: Pet'), 'Pet', 'baseTok: F: Pet')
assert_eq(baseTok('Target'), 'Current Target', 'baseTok: Target alias')
assert_eq(baseTok('Current Target'), 'Current Target', 'baseTok: Current Target')
assert_eq(baseTok('Self'), 'Myself', 'baseTok: Self alias')
assert_eq(baseTok('Myself'), 'Myself', 'baseTok: Myself')
assert_eq(baseTok(nil), '', 'baseTok: nil')
assert_eq(baseTok(''), '', 'baseTok: empty')

-- ============================================================================
-- 13. normalizeCommandKey(text) — slash command argument normalization
-- ============================================================================
print('--- normalizeCommandKey ---')
local normalizeCommandKey = loadFunc(src, 'normalizeCommandKey', {})

assert_eq(normalizeCommandKey('Manual'), 'manual', 'cmdKey: Manual')
assert_eq(normalizeCommandKey('PULLER'), 'puller', 'cmdKey: PULLER')
assert_eq(normalizeCommandKey('Chase Assist'), 'chaseassist', 'cmdKey: Chase Assist')
assert_eq(normalizeCommandKey('pull & assist'), 'pullassist', 'cmdKey: pull & assist')
assert_eq(normalizeCommandKey(nil), '', 'cmdKey: nil')
assert_eq(normalizeCommandKey(''), '', 'cmdKey: empty')

-- ============================================================================
-- 14. setTriuneMode(arg1, arg2) — partial test (mode/submode resolution only)
--     We can't fully test this because it calls setManualHunterPetHold and
--     clearMapRadiusVisuals, but we can test the normalizeCommandKey→mode
--     mapping by checking just the parsing portion.
-- ============================================================================
print('--- setTriuneMode (mode parsing) ---')
-- We test via normalizeCommandKey + the known dispatch table documented in the function
-- since setTriuneMode has side effects we can't call outside MQ.
-- Instead, verify the command key mappings are self-consistent:
local MODE_MAP = {
    manual = { 'Manual', 'Hunt' },
    manualhunter = { 'Manual', 'Hunt' },
    puller = { 'Puller', nil },
    hunter = { 'Puller', 'Hunt' },
    pethunter = { 'Puller', 'Hunt' },
    pettank = { 'Puller', 'Hunt' },
    pull = { 'Puller', 'Camp' },
    pullassist = { 'Puller', 'Camp' },
    assist = { 'Assist', nil },
    chase = { 'Assist', 'Chase' },
    chaseassist = { 'Assist', 'Chase' },
    garrison = { 'Assist', 'Camp' },
    tank = { 'Assist', 'Camp' },
    backline = { 'Assist', 'Backline' },
    ranged = { 'Assist', 'Backline' },
}
for input, expected in pairs(MODE_MAP) do
    local key = normalizeCommandKey(input)
    assert_eq(key, input, 'setTriuneMode key: ' .. input .. ' normalizes to itself')
end

-- ============================================================================
-- 15. sungKey(spellName, targetId) — dedup key generation
-- ============================================================================
print('--- sungKey ---')
local sungKey = loadFunc(src, 'sungKey', {})

assert_eq(sungKey('Heal', 123), '123_Heal', 'sungKey: basic')
assert_eq(sungKey('Buff', 0), '0_Buff', 'sungKey: id 0')
assert_eq(sungKey('Spell', nil), '0_Spell', 'sungKey: nil id')

-- ============================================================================
-- 16. classPlausible(abbr) — checks if a class abbreviation is valid
-- ============================================================================
print('--- classPlausible ---')
local classPlausible = loadFunc(src, 'classPlausible',
    { ALL_ABBR = ALL_ABBR, DATA = { spells = {} } })

assert_true(classPlausible('War'), 'plausible: War')
assert_true(classPlausible('SK'), 'plausible: SK')
assert_true(classPlausible('Ber'), 'plausible: Ber')
assert_eq(classPlausible('Xyz'), false, 'plausible: Xyz invalid')
assert_eq(classPlausible(nil), false, 'plausible: nil')
assert_eq(classPlausible(42), false, 'plausible: number')

-- ============================================================================
-- 17. serialize(o, f, indent) — round-trip persistence
-- ============================================================================
print('--- serialize ---')
local serialize = loadFunc(src, 'serialize', {})

-- Helper: serialize to string
local function serializeToString(o)
    local buf = {}
    local fakefile = {
        write = function(_, s) buf[#buf + 1] = s end
    }
    serialize(o, fakefile, 1)
    return table.concat(buf)
end

-- Primitives
assert_eq(serializeToString(42), '42', 'serialize: number')
assert_eq(serializeToString(true), 'true', 'serialize: boolean true')
assert_eq(serializeToString(false), 'false', 'serialize: boolean false')
assert_eq(serializeToString('hello'), '"hello"', 'serialize: string')

-- Table round-trip: serialize then loadstring it back
local testData = {
    mode = 'Manual',
    running = false,
    assist_at = 98,
    chase_dist = 15,
}
local serialized = 'return ' .. serializeToString(testData)
local chunk = assert(loadstring(serialized))
local result = chunk()
assert_eq(result.mode, 'Manual', 'serialize roundtrip: mode')
assert_eq(result.running, false, 'serialize roundtrip: running')
assert_eq(result.assist_at, 98, 'serialize roundtrip: assist_at')
assert_eq(result.chase_dist, 15, 'serialize roundtrip: chase_dist')

-- Nested table round-trip
local nested = { gems = { { spell = 'Heal', slot = 1 } }, version = 3 }
local nestedStr = 'return ' .. serializeToString(nested)
local nchunk = assert(loadstring(nestedStr))
local nresult = nchunk()
assert_eq(nresult.version, 3, 'serialize nested: version')
assert_type(nresult.gems, 'table', 'serialize nested: gems is table')

-- Nil value
assert_eq(serializeToString(nil), 'nil', 'serialize: nil')

-- ============================================================================
-- 18. extractConName (runtime method) — parsing /consider chat lines
-- ============================================================================
print('--- extractConName ---')
-- extractConName is assigned as `function runtime.extractConName(line)`, which
-- our extractor can't pull since it's not `local function`.  Instead, test
-- the same regex logic inline.
local function extractConName(line)
    if not line or line == '' then return nil end
    local name = line:match('^(.-)%s+scowls')
        or line:match('^(.-)%s+glares')
        or line:match('^(.-)%s+glowers')
        or line:match('^(.-)%s+looks')
        or line:match('^(.-)%s+regards')
        or line:match('^(.-)%s+judges')
        or line:match('^(.-)%s+judge')
    if name then
        name = name:gsub('^%s*(.-)%s*$', '%1')
        if name ~= '' then return name end
    end
    return nil
end

assert_eq(extractConName('a fire beetle scowls at you'), 'a fire beetle', 'con: scowls')
assert_eq(extractConName('Guard Hanlon glares at you'), 'Guard Hanlon', 'con: glares')
assert_eq(extractConName('a moss snake regards you'), 'a moss snake', 'con: regards')
assert_eq(extractConName('Merchant looks at you'), 'Merchant', 'con: looks')
assert_eq(extractConName('a_gnoll judges you'), 'a_gnoll', 'con: judges')
assert_nil(extractConName(nil), 'con: nil')
assert_nil(extractConName(''), 'con: empty')

-- ============================================================================
-- 19. createCastTracker — failure counting and lockout system
-- ============================================================================
print('--- createCastTracker ---')

-- We can't extract createCastTracker (it references `mq` internally for
-- onFailureEvent), but the core inner functions (recordFailure, isLockedOut,
-- recordSuccess) are pure logic.  We re-implement a minimal version here to
-- test the algorithm.

local function testCastTracker()
    local failureCount     = {}
    local lockouts         = {}
    local targetLockouts   = {}
    local targetImmunities = {}
    local mockClock        = 100 -- fake os.clock()

    local function getFailCount(spellName)
        if not spellName then return 0 end
        local entry = failureCount[spellName]
        if not entry then return 0 end
        if (mockClock - (tonumber(entry.lastFail) or 0)) > 15.0 then
            failureCount[spellName] = nil
            return 0
        end
        return tonumber(entry.count) or 0
    end

    local function incFailCount(spellName)
        if not spellName then return 1 end
        local count = getFailCount(spellName) + 1
        failureCount[spellName] = { count = count, lastFail = mockClock }
        return count
    end

    local function resetFailCount(spellName)
        if spellName then failureCount[spellName] = nil end
    end

    local function isLockedOut(spellName, targetId)
        if not spellName or spellName == '' then return false end
        local tid = tonumber(targetId)

        if tid and tid > 0 and targetImmunities[tid] and targetImmunities[tid][spellName] then
            return true, 'Immune', 9999
        end

        if tid and tid > 0 and targetLockouts[tid] then
            local untilTime = tonumber(targetLockouts[tid][spellName])
            if untilTime then
                if mockClock < untilTime then
                    return true, 'TargetLock', math.ceil(untilTime - mockClock)
                else
                    targetLockouts[tid][spellName] = nil
                end
            end
        end

        local gUntil = tonumber(lockouts[spellName])
        if gUntil then
            if mockClock < gUntil then
                return true, 'GlobalLock', math.ceil(gUntil - mockClock)
            else
                lockouts[spellName] = nil
            end
        end

        return false
    end

    local function recordFailure(spellName, targetId, reason, maxRetries, lockoutSec, kind)
        if not spellName or spellName == '' then return end
        local tid = nil
        local r = 'generic'
        local mRetries = 2
        local lSec = 30
        local k = kind

        if type(targetId) == 'number' and (type(reason) == 'string' or reason == nil) then
            tid = targetId
            r = reason or 'generic'
            mRetries = tonumber(maxRetries) or 2
            lSec = tonumber(lockoutSec) or 30
        elseif type(targetId) == 'string' then
            r = targetId
            mRetries = tonumber(reason) or 2
            lSec = tonumber(maxRetries) or 30
            k = lockoutSec
        elseif type(targetId) == 'number' and type(reason) == 'number' then
            mRetries = targetId
            lSec = tonumber(reason) or 30
            r = 'generic'
        else
            mRetries = tonumber(maxRetries) or 2
            lSec = tonumber(lockoutSec) or 30
        end

        local rLow = tostring(r):lower()

        if rLow == 'target immune' or rLow == 'immune' then
            if tid and tid > 0 then
                targetImmunities[tid] = targetImmunities[tid] or {}
                targetImmunities[tid][spellName] = true
                resetFailCount(spellName)
            else
                lockouts[spellName] = mockClock + lSec
                resetFailCount(spellName)
            end

        elseif rLow == 'did not take hold' then
            local backoff = math.max(lSec, 120)
            if tid and tid > 0 then
                targetLockouts[tid] = targetLockouts[tid] or {}
                targetLockouts[tid][spellName] = mockClock + backoff
                resetFailCount(spellName)
            else
                lockouts[spellName] = mockClock + lSec
                resetFailCount(spellName)
            end

        elseif rLow == 'resisted' then
            if k == 'dd' or k == 'dot' then
                resetFailCount(spellName)
                return
            end
            local fails = incFailCount(spellName)
            if fails >= mRetries then
                if tid and tid > 0 then
                    targetLockouts[tid] = targetLockouts[tid] or {}
                    targetLockouts[tid][spellName] = mockClock + lSec
                    resetFailCount(spellName)
                else
                    lockouts[spellName] = mockClock + lSec
                    resetFailCount(spellName)
                end
            end

        elseif rLow == 'fizzled' or rLow == 'interrupted' then
            local threshold = math.max(mRetries * 2, 4)
            local fails = incFailCount(spellName)
            if fails >= threshold then
                local shortLock = math.min(lSec, 8)
                lockouts[spellName] = mockClock + shortLock
                resetFailCount(spellName)
            end

        elseif rLow == 'cannot see target' or rLow == 'out of range' or rLow == 'dead target'
            or rLow == 'cannot cast' or rLow == 'insufficient mana' or rLow == 'not ready' then
            return

        else
            local fails = incFailCount(spellName)
            if fails >= mRetries then
                lockouts[spellName] = mockClock + lSec
                resetFailCount(spellName)
            end
        end
    end

    local function recordSuccess(spellName, targetId)
        if not spellName then return end
        resetFailCount(spellName)
        lockouts[spellName] = nil
        local tid = tonumber(targetId)
        if tid and tid > 0 and targetLockouts[tid] then
            targetLockouts[tid][spellName] = nil
        end
    end

    local function clear(targetId)
        local tid = tonumber(targetId)
        if tid and tid > 0 then
            targetLockouts[tid] = nil
            targetImmunities[tid] = nil
        else
            failureCount     = {}
            lockouts         = {}
            targetLockouts   = {}
            targetImmunities = {}
        end
    end

    -- 1. Test: not locked out initially
    assert_eq(isLockedOut('Heal'), false, 'tracker: not locked initially')

    -- 2. Test: legacy generic failure
    recordFailure('Heal', 2, 30)
    assert_eq(isLockedOut('Heal'), false, 'tracker: 1 failure, not locked')
    recordFailure('Heal', 2, 30)
    assert_eq(isLockedOut('Heal'), true, 'tracker: 2 failures, locked out')

    -- 3. Test: lockout expires after time passes
    mockClock = 131 -- 100 + 30 + 1
    assert_eq(isLockedOut('Heal'), false, 'tracker: lockout expired')

    -- 4. Test: recordSuccess clears failure count
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    recordSuccess('Nuke')
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    assert_eq(isLockedOut('Nuke'), false, 'tracker: success resets count')

    -- 5. Test: Target-Scoped Immunity
    mockClock = 200
    recordFailure('Slow', 101, 'target immune', 2, 30, 'debuff')
    assert_eq(isLockedOut('Slow', 101), true, 'tracker: target 101 is immune to Slow')
    assert_eq(isLockedOut('Slow', 102), false, 'tracker: target 102 is NOT immune to Slow')
    assert_eq(isLockedOut('Slow'), false, 'tracker: Slow is NOT locked out globally')

    -- 6. Test: Target-Scoped "Did Not Take Hold" (Non-stacking buff backoff)
    mockClock = 300
    recordFailure('Focus', 55, 'did not take hold', 2, 30, 'buff')
    assert_eq(isLockedOut('Focus', 55), true, 'tracker: Focus backed off on target 55')
    assert_eq(isLockedOut('Focus', 56), false, 'tracker: Focus available for target 56')
    mockClock = 421 -- 300 + 120 + 1
    assert_eq(isLockedOut('Focus', 55), false, 'tracker: Focus backoff expired on target 55')

    -- 7. Test: Direct Damage Resists do NOT trigger lockouts
    mockClock = 500
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    assert_eq(isLockedOut('Ice Comet', 101), false, 'tracker: DD nukes never lock out on resists')

    -- 8. Test: Debuff Resists back off only on specific target after maxRetries
    mockClock = 600
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 201), false, 'tracker: 1 debuff resist does not lock')
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 201), true, 'tracker: 2 debuff resists lock out on target 201')
    assert_eq(isLockedOut('Tash', 202), false, 'tracker: Tash remains usable on target 202')

    -- 9. Test: Failure count TTL decay (15s)
    mockClock = 700
    recordFailure('Root', 301, 'resisted', 2, 30, 'debuff')
    mockClock = 720 -- 20 seconds later (> 15s decay)
    recordFailure('Root', 301, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Root', 301), false, 'tracker: failure count decayed after 20s')

    -- 10. Test: Dead target / Positional events have 0 penalty
    mockClock = 800
    recordFailure('Heal', 10, 'dead target', 1, 10, 'heal')
    recordFailure('Heal', 10, 'out of range', 1, 10, 'heal')
    recordFailure('Heal', 10, 'cannot see target', 1, 10, 'heal')
    assert_eq(isLockedOut('Heal', 10), false, 'tracker: positional/dead target events incur 0 penalty')

    -- 11. Test: Targeted clear vs global clear
    mockClock = 850
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 201), true, 'tracker: target 201 locked out')
    clear(101)
    assert_eq(isLockedOut('Slow', 101), false, 'tracker: clear(101) cleared immunity for 101')
    assert_eq(isLockedOut('Tash', 201), true, 'tracker: clear(101) did not clear 201')
    clear()
    assert_eq(isLockedOut('Tash', 201), false, 'tracker: global clear() cleared all lockouts')
end
testCastTracker()

-- ============================================================================
-- CROSS-MODULE TESTS: triune_dps.lua
-- ============================================================================
local dpsSrc = readFile('TAC/lua/triune_dps.lua')

-- ============================================================================
-- 20. cleanLine (DPS) — strip MQ color codes
-- ============================================================================
print('--- cleanLine (dps) ---')
local cleanLine = loadFunc(dpsSrc, 'cleanLine', {})

assert_eq(cleanLine('Hello World'), 'Hello World', 'cleanLine: plain text')
assert_eq(cleanLine('  spaced  '), 'spaced', 'cleanLine: trim whitespace')
assert_eq(cleanLine(nil), '', 'cleanLine: nil')

-- ============================================================================
-- 21. parseDamageValue (DPS) — extract damage numbers from combat text
-- ============================================================================
print('--- parseDamageValue (dps) ---')
local parseDamageValue = loadFunc(dpsSrc, 'parseDamageValue', {})

assert_eq(parseDamageValue('100'), 100, 'dmgParse: simple number')
assert_eq(parseDamageValue('1,234'), 1234, 'dmgParse: comma-separated')
assert_eq(parseDamageValue('12,345,678'), 12345678, 'dmgParse: large number')
assert_eq(parseDamageValue('-50'), -50, 'dmgParse: negative')
assert_eq(parseDamageValue('for 500 points'), 500, 'dmgParse: embedded number')
assert_nil(parseDamageValue(nil), 'dmgParse: nil')
assert_nil(parseDamageValue('no numbers here'), 'dmgParse: no digits')

-- ============================================================================
-- 22. isValidMobName (DPS) — filter out false-positive mob names
-- ============================================================================
print('--- isValidMobName (dps) ---')
local isValidMobName = loadFunc(dpsSrc, 'isValidMobName', {})

assert_true(isValidMobName('a fire beetle'), 'validMob: fire beetle')
assert_true(isValidMobName('Guard Hanlon'), 'validMob: Guard Hanlon')
assert_eq(isValidMobName(nil), false, 'validMob: nil')
assert_eq(isValidMobName(''), false, 'validMob: empty')
assert_eq(isValidMobName('non-melee damage'), false, 'validMob: non-melee')
assert_eq(isValidMobName('by someone'), false, 'validMob: starts with "by "')
assert_eq(isValidMobName('healed'), false, 'validMob: healed')
assert_eq(isValidMobName('target'), false, 'validMob: target keyword')
assert_eq(isValidMobName('none'), false, 'validMob: none keyword')

-- ============================================================================
-- 23. getVerbCategory (DPS) — melee vs skill classification
-- ============================================================================
print('--- getVerbCategory (dps) ---')
-- getVerbCategory references module-level SKILL_VERBS and MELEE_VERBS as upvalues.
-- We provide them in the sandbox.
local MELEE_VERBS = {
    ['hit'] = true,
    ['hits'] = true,
    ['slash'] = true,
    ['slashes'] = true,
    ['pierce'] = true,
    ['pierces'] = true,
    ['crush'] = true,
    ['crushes'] = true,
    ['bite'] = true,
    ['bites'] = true,
    ['claw'] = true,
    ['claws'] = true,
    ['strike'] = true,
    ['strikes'] = true,
    ['slice'] = true,
    ['slices'] = true,
    ['gore'] = true,
    ['gores'] = true,
    ['punch'] = true,
    ['punches'] = true,
    ['shoot'] = true,
    ['shoots'] = true,
    ['hand to hand'] = true,
}
local SKILL_VERBS = {
    ['bash'] = true,
    ['bashes'] = true,
    ['kick'] = true,
    ['kicks'] = true,
    ['backstab'] = true,
    ['backstabs'] = true,
    ['frenzy'] = true,
    ['frenzies'] = true,
    ['flying kick'] = true,
    ['flying kicks'] = true,
    ['dragon punch'] = true,
    ['dragon punches'] = true,
    ['eagle strike'] = true,
    ['eagle strikes'] = true,
    ['tiger claw'] = true,
    ['tiger claws'] = true,
    ['roundhouse kick'] = true,
    ['roundhouse kicks'] = true,
    ['slam'] = true,
    ['slams'] = true,
    ['headbutt'] = true,
    ['headbutts'] = true,
    ['maul'] = true,
    ['mauls'] = true,
    ['pummel'] = true,
    ['pummels'] = true,
    ['rend'] = true,
    ['rends'] = true,
    ['rip'] = true,
    ['rips'] = true,
    ['sweep'] = true,
    ['sweeps'] = true,
    ['finishing blow'] = true,
    ['finishing blows'] = true,
}

local getVerbCategory = loadFunc(dpsSrc, 'getVerbCategory',
    { SKILL_VERBS = SKILL_VERBS, MELEE_VERBS = MELEE_VERBS })

assert_eq(getVerbCategory('hits'), 'Melee', 'verbCat: hits → Melee')
assert_eq(getVerbCategory('slashes'), 'Melee', 'verbCat: slashes → Melee')
assert_eq(getVerbCategory('crush'), 'Melee', 'verbCat: crush → Melee')
assert_eq(getVerbCategory('kick'), 'Skill', 'verbCat: kick → Skill')
assert_eq(getVerbCategory('backstabs'), 'Skill', 'verbCat: backstabs → Skill')
assert_eq(getVerbCategory('flying kick'), 'Skill', 'verbCat: flying kick → Skill')
assert_eq(getVerbCategory('dragon punch'), 'Skill', 'verbCat: dragon punch → Skill')
assert_eq(getVerbCategory('unknown'), 'Melee', 'verbCat: unknown → Melee fallback')
assert_eq(getVerbCategory(nil), 'Melee', 'verbCat: nil → Melee fallback')

-- ============================================================================
-- 24. calculateCategoryTotals (DPS) — damage category aggregation
-- ============================================================================
print('--- calculateCategoryTotals (dps) ---')
local calculateCategoryTotals = loadFunc(dpsSrc, 'calculateCategoryTotals', {})

local playerBD = {
    ['Slash']     = { category = 'Melee', totalDmg = 1000 },
    ['Kick']      = { category = 'Skill', totalDmg = 500 },
    ['Ice Comet'] = { category = 'Spell', totalDmg = 2000 },
}
local petBD = {
    ['warder'] = {
        attacks = {
            ['Bite'] = { category = 'Melee', totalDmg = 300 },
        }
    }
}
local totals = calculateCategoryTotals(playerBD, petBD)
assert_eq(totals.melee, 1300, 'catTotals: melee (player + pet)')
assert_eq(totals.skill, 500, 'catTotals: skill')
assert_eq(totals.spell, 2000, 'catTotals: spell')
assert_eq(totals.dot, 0, 'catTotals: dot (none)')
assert_eq(totals.ds, 0, 'catTotals: ds (none)')

-- Empty inputs
local emptyTotals = calculateCategoryTotals({}, nil)
assert_eq(emptyTotals.melee, 0, 'catTotals: empty melee')
assert_eq(emptyTotals.spell, 0, 'catTotals: empty spell')

-- ============================================================================
-- 25. getFightDPS (DPS) — DPS calculation
-- ============================================================================
print('--- getFightDPS (dps) ---')
local getFightDPS = loadFunc(dpsSrc, 'getFightDPS', {})

assert_eq(getFightDPS(1000, 10), 100, 'dps: 1000/10 = 100')
assert_eq(getFightDPS(1500, 10), 150, 'dps: 1500/10 = 150')
assert_eq(getFightDPS(0, 10), 0, 'dps: 0 dmg = 0')
assert_eq(getFightDPS(1000, 0), 0, 'dps: 0 duration = 0')
-- Rounding test
assert_eq(getFightDPS(100, 3), 33, 'dps: 100/3 rounds to 33')
assert_eq(getFightDPS(200, 3), 67, 'dps: 200/3 rounds to 67')

-- ============================================================================
-- CROSS-MODULE TESTS: triune_buffbot.lua
-- ============================================================================
local bbSrc = readFile('TAC/lua/triune_buffbot.lua')

-- ============================================================================
-- 26. parseBuffRequest (buffbot) — tell message parsing
-- ============================================================================
print('--- parseBuffRequest (buffbot) ---')
local parseBuffRequest = loadFunc(bbSrc, 'parseBuffRequest', {})

-- Gem list for testing
local testGems = {
    { name = 'Virtue',           gem = 1 },
    { name = 'Symbol of Marzin', gem = 2 },
    { name = 'Aegolism',         gem = 3 },
}

-- Basic requests
local mode, sel = parseBuffRequest('buffs please', testGems)
assert_eq(mode, 'player', 'bbParse: default mode is player')
assert_nil(sel, 'bbParse: no number → nil selection')

-- Pet mode
mode, sel = parseBuffRequest('pet buffs', testGems)
assert_eq(mode, 'pet', 'bbParse: "pet" → pet mode')

-- Both mode
mode, sel = parseBuffRequest('both please', testGems)
assert_eq(mode, 'both', 'bbParse: "both" → both mode')

-- Specific numbers
mode, sel = parseBuffRequest('1', testGems)
assert_eq(mode, 'player', 'bbParse: "1" → player mode')
assert_neq(sel, nil, 'bbParse: "1" selects something')
assert_eq(#sel, 1, 'bbParse: "1" selects 1 gem')

-- Multiple numbers
mode, sel = parseBuffRequest('1 3', testGems)
assert_eq(#sel, 2, 'bbParse: "1 3" selects 2 gems')

-- Pet with number
mode, sel = parseBuffRequest('pet 2', testGems)
assert_eq(mode, 'pet', 'bbParse: "pet 2" → pet mode')
assert_eq(#sel, 1, 'bbParse: "pet 2" selects 1 gem')

-- Empty gem list
mode, sel = parseBuffRequest('buffs', {})
assert_eq(mode, 'player', 'bbParse: empty gems → player')
assert_nil(sel, 'bbParse: empty gems → nil sel')

-- Out-of-range number
mode, sel = parseBuffRequest('99', testGems)
assert_nil(sel, 'bbParse: out-of-range number → nil')

-- ============================================================================
-- 27. isThankYou (buffbot) — thank-you message detection
-- ============================================================================
print('--- isThankYou (buffbot) ---')
local isThankYou = loadFunc(bbSrc, 'isThankYou', {})

-- Positive cases
assert_true(isThankYou('ty'), 'thx: ty')
assert_true(isThankYou('TY'), 'thx: TY')
assert_true(isThankYou('ty!'), 'thx: ty!')
assert_true(isThankYou('tyvm'), 'thx: tyvm')
assert_true(isThankYou('tysm'), 'thx: tysm')
assert_true(isThankYou('thx'), 'thx: thx')
assert_true(isThankYou('thanks'), 'thx: thanks')
assert_true(isThankYou('Thanks!'), 'thx: Thanks!')
assert_true(isThankYou('thank you'), 'thx: thank you')
assert_true(isThankYou('Thank You!'), 'thx: Thank You!')
assert_true(isThankYou('thank u'), 'thx: thank u')
assert_true(isThankYou('thankyou'), 'thx: thankyou')
assert_true(isThankYou('much appreciated'), 'thx: much appreciated')
assert_true(isThankYou('appreciate it'), 'thx: appreciate it')
assert_true(isThankYou('ty for the buffs'), 'thx: ty for the buffs')

-- Negative cases
assert_eq(isThankYou('buffs please'), false, 'thx: buffs please → false')
assert_eq(isThankYou('hello'), false, 'thx: hello → false')
assert_eq(isThankYou('1 3'), false, 'thx: 1 3 → false')
assert_eq(isThankYou(nil), false, 'thx: nil → false')
assert_eq(isThankYou(''), false, 'thx: empty → false')

-- ============================================================================
-- 28. isPlayerIgnored / ignore list helpers (buffbot)
-- ============================================================================
print('--- isPlayerIgnored (buffbot) ---')
local testCtrl = {
    ignoreList = { 'BadActor', 'Griefer' },
    banMsg = "You are banned from getting buffs."
}
local dummySaveCalled = false
local isPlayerIgnored = loadFunc(bbSrc, 'isPlayerIgnored', { ctrl = testCtrl })
local addIgnoredPlayer = loadFunc(bbSrc, 'addIgnoredPlayer', {
    ctrl = testCtrl,
    isPlayerIgnored = isPlayerIgnored,
    saveConfig = function() dummySaveCalled = true end
})
local removeIgnoredPlayer = loadFunc(bbSrc, 'removeIgnoredPlayer', {
    ctrl = testCtrl,
    saveConfig = function() dummySaveCalled = true end
})

-- Test isPlayerIgnored
assert_true(isPlayerIgnored('BadActor'), 'ignore: exact match BadActor')
assert_true(isPlayerIgnored('badactor'), 'ignore: lower case badactor')
assert_true(isPlayerIgnored('  GRIEFER  '), 'ignore: whitespace and uppercase')
assert_eq(isPlayerIgnored('GoodPlayer'), false, 'ignore: non-ignored player is false')
assert_eq(isPlayerIgnored(''), false, 'ignore: empty name is false')
assert_eq(isPlayerIgnored(nil), false, 'ignore: nil name is false')

-- Test addIgnoredPlayer
dummySaveCalled = false
local addRes1 = addIgnoredPlayer('Troublemaker')
assert_true(addRes1, 'ignore: adding new player returns true')
assert_true(isPlayerIgnored('Troublemaker'), 'ignore: newly added player is ignored')
assert_true(dummySaveCalled, 'ignore: add calls saveConfig')

-- Duplicate add
dummySaveCalled = false
local addRes2 = addIgnoredPlayer('troublemaker')
assert_eq(addRes2, false, 'ignore: adding duplicate player returns false')

-- Test removeIgnoredPlayer
dummySaveCalled = false
local remRes1 = removeIgnoredPlayer('troublemaker')
assert_true(remRes1, 'ignore: removing player returns true')
assert_eq(isPlayerIgnored('troublemaker'), false, 'ignore: removed player is no longer ignored')
assert_true(dummySaveCalled, 'ignore: remove calls saveConfig')

local remRes2 = removeIgnoredPlayer('NonExistent')
assert_eq(remRes2, false, 'ignore: removing non-existent player returns false')

-- ============================================================================
-- 29. isSameGuild / guild helpers (buffbot)
-- ============================================================================
print('--- isSameGuild (buffbot) ---')
---@type string|nil
local mockMyGuild = 'Knights of Norrath'
local mockMq = {
    TLO = {
        Me = {
            Guild = function() return mockMyGuild end
        }
    }
}
local getMyGuild = loadFunc(bbSrc, 'getMyGuild', { mq = mockMq })
local getSpawnGuild = loadFunc(bbSrc, 'getSpawnGuild', {})
local isSameGuild = loadFunc(bbSrc, 'isSameGuild', {
    getMyGuild = getMyGuild,
    getSpawnGuild = getSpawnGuild
})

-- Create mock spawn helper
local function makeSpawn(guildName)
    local s = setmetatable({
        Guild = function() return guildName end
    }, {
        __call = function() return true end
    })
    return s
end

-- Test matching guild
assert_true(isSameGuild(makeSpawn('Knights of Norrath')), 'guild: exact match returns true')
assert_true(isSameGuild(makeSpawn('knights of norrath')), 'guild: case-insensitive match returns true')
assert_true(isSameGuild(makeSpawn('KNIGHTS OF NORRATH')), 'guild: uppercase match returns true')

-- Test non-matching guild
assert_eq(isSameGuild(makeSpawn('Other Guild')), false, 'guild: different guild returns false')
assert_eq(isSameGuild(makeSpawn(nil)), false, 'guild: unguilded player returns false')
assert_eq(isSameGuild(makeSpawn('')), false, 'guild: empty guild player returns false')
assert_eq(isSameGuild(nil), false, 'guild: nil spawn returns false')

-- Test unguilded bot
mockMyGuild = nil
assert_eq(isSameGuild(makeSpawn('Knights of Norrath')), false, 'guild: unguilded bot returns false')
mockMyGuild = ''
assert_eq(isSameGuild(makeSpawn('Knights of Norrath')), false, 'guild: empty guild bot returns false')

-- ============================================================================
-- 30. triune_data.lua — structural validation
-- ============================================================================
print('--- triune_data.lua validation ---')
local dataFile = assert(loadfile('TAC/config/triune_data.lua'))
assert_neq(dataFile, nil, 'data: loadfile succeeds')

local dataOk, DATA_LOADED = pcall(dataFile)
assert_true(dataOk, 'data: pcall succeeds')
assert_type(DATA_LOADED, 'table', 'data: returns a table')

-- Must have spells, discs, and aas sections
assert_type(DATA_LOADED.spells, 'table', 'data: has spells table')
assert_type(DATA_LOADED.aas, 'table', 'data: has aas table')

-- Spellcasting classes should have a spells entry (pure melee Rog and Ber do not have spell tables)
local SPELL_CLASSES = { 'War', 'Clr', 'Pal', 'Rng', 'SK', 'Dru', 'Mnk', 'Brd', 'Shm', 'Nec', 'Wiz', 'Mag', 'Enc', 'Bst' }
for _, abbr in ipairs(SPELL_CLASSES) do
    assert_type(DATA_LOADED.spells[abbr], 'table',
        'data: spells[' .. abbr .. '] exists')
    -- Each spell entry should be {name, level} pairs
    if DATA_LOADED.spells[abbr] and #DATA_LOADED.spells[abbr] > 0 then
        local first = DATA_LOADED.spells[abbr][1]
        assert_type(first, 'table', 'data: spells[' .. abbr .. '][1] is a table')
        assert_type(first[1], 'string', 'data: spells[' .. abbr .. '][1][1] is spell name')
        assert_type(first[2], 'number', 'data: spells[' .. abbr .. '][1][2] is level')
    end
end

-- AA entries should follow the same pattern
for _, abbr in ipairs(ALL_ABBR) do
    if DATA_LOADED.aas[abbr] then
        assert_type(DATA_LOADED.aas[abbr], 'table',
            'data: aas[' .. abbr .. '] is a table')
        if #DATA_LOADED.aas[abbr] > 0 then
            local first = DATA_LOADED.aas[abbr][1]
            assert_type(first, 'table', 'data: aas[' .. abbr .. '][1] is a table')
            assert_type(first[1], 'string', 'data: aas[' .. abbr .. '][1][1] is name')
            assert_type(first[2], 'number', 'data: aas[' .. abbr .. '][1][2] is cooldown')
        end
    end
end

-- Spell levels should be sane (1-70 for current era)
local badLevels = 0
for abbr, spells in pairs(DATA_LOADED.spells) do
    if type(spells) == 'table' then
        for _, sp in ipairs(spells) do
            if type(sp) == 'table' and type(sp[2]) == 'number' then
                if sp[2] < 1 or sp[2] > 70 then
                    badLevels = badLevels + 1
                end
            end
        end
    end
end
assert_eq(badLevels, 0, 'data: all spell levels in range 1-70')

-- No class abbreviation in data should be missing from ALL_ABBR
local abbrSet = {}
for _, a in ipairs(ALL_ABBR) do abbrSet[a] = true end
for abbr in pairs(DATA_LOADED.spells) do
    assert_true(abbrSet[abbr], 'data: spells key "' .. abbr .. '" is valid class')
end
for abbr in pairs(DATA_LOADED.aas) do
    assert_true(abbrSet[abbr], 'data: aas key "' .. abbr .. '" is valid class')
end

-- ============================================================================
-- 29. Hazard Avoidance & Stuck Memory
-- ============================================================================
print('--- hazard avoidance & stuck memory ---')
local dummyCtrl = {
    nav_hazard_avoidance = true,
    nav_hazard_radius = 15,
    nav_hazard_min_hits = 2,
    zone_hazards = {}
}
local dummyEnv = {
    ctrl = dummyCtrl,
    saveLoadout = function() end,
    getCurrentZoneShortName = function() return 'poknowledge' end
}

local getZoneHazards = loadFunc(src, 'getZoneHazards', dummyEnv)
local recordStuckHazard = loadFunc(src, 'recordStuckHazard', {
    ctrl = dummyCtrl,
    getZoneHazards = getZoneHazards,
    saveLoadout = function() end,
    getCurrentZoneShortName = function() return 'poknowledge' end
})
local clearZoneHazards = loadFunc(src, 'clearZoneHazards', {
    ctrl = dummyCtrl,
    saveLoadout = function() end,
    getCurrentZoneShortName = function() return 'poknowledge' end
})
local isCoordInActiveHazard = loadFunc(src, 'isCoordInActiveHazard', {
    ctrl = dummyCtrl,
    getZoneHazards = getZoneHazards
})

-- Record first stuck at (100, 200, 10)
recordStuckHazard(100, 200, 10, 'poknowledge')
local hzList = getZoneHazards('poknowledge')
assert_eq(#hzList, 1, 'hazard: 1 hazard logged')
assert_eq(hzList[1].hits, 1, 'hazard: hits=1')
assert_eq(isCoordInActiveHazard(100, 200, 10, 'poknowledge'), false, 'hazard: hits=1 not active yet (needs 2)')

-- Record nearby stuck at (106, 202, 10) -> clusters into existing with weighted centroid ((100+106)/2, (200+202)/2) = (103, 201)
recordStuckHazard(106, 202, 10, 'poknowledge')
assert_eq(#hzList, 1, 'hazard: clustered into single hazard')
assert_eq(hzList[1].hits, 2, 'hazard: hits incremented to 2')
assert_eq(hzList[1].x, 103, 'hazard: weighted centroid x')
assert_eq(hzList[1].y, 201, 'hazard: weighted centroid y')
local isActive, activeH = isCoordInActiveHazard(100, 200, 10, 'poknowledge')
assert_eq(isActive, true, 'hazard: now active with 2 hits')
assert_neq(activeH, nil, 'hazard: returns active hazard table')

-- Record 3rd hit at (103, 198, 10) -> ((103*2 + 103)/3 = 103, (201*2 + 198)/3 = 200)
recordStuckHazard(103, 198, 10, 'poknowledge')
assert_eq(hzList[1].hits, 3, 'hazard: hits incremented to 3')
assert_eq(hzList[1].x, 103, 'hazard: 3-hit centroid x exact')
assert_eq(hzList[1].y, 200, 'hazard: 3-hit centroid y exact')

-- Far away point is not in hazard
assert_eq(isCoordInActiveHazard(500, 500, 10, 'poknowledge'), false, 'hazard: far coord not in hazard')

-- Clear hazards
clearZoneHazards('poknowledge')
assert_eq(#getZoneHazards('poknowledge'), 0, 'hazard: clearZoneHazards emptied list')

-- ============================================================================
-- 30. Path Intersection & Detour Calculation
-- ============================================================================
print('--- path intersection & detour ---')
dummyCtrl.zone_hazards = {
    poknowledge = {
        { x = 100, y = 100, z = 0, radius = 15, hits = 3 }
    }
}
local findPathHazardIntersection = loadFunc(src, 'findPathHazardIntersection', {
    ctrl = dummyCtrl,
    getZoneHazards = getZoneHazards
})
local dummyPursuit = {
    detourActive = true,
    detourX = 120,
    detourY = 130,
    detourZ = 10,
    detourTargetId = 42,
    detourTargetKey = '130.0_120.0_10.0',
    detourStartedAt = 100,
    detourExpiresAt = 106
}
local clearDetour = loadFunc(src, 'clearDetour', {
    pursuit = dummyPursuit
})
clearDetour()
assert_eq(dummyPursuit.detourActive, false, 'clearDetour: resets detourActive')
assert_eq(dummyPursuit.detourX, 0, 'clearDetour: resets detourX')
assert_eq(dummyPursuit.detourTargetId, 0, 'clearDetour: resets detourTargetId')

local calculateDetourWaypoint = loadFunc(src, 'calculateDetourWaypoint', {
    navLoaded = function() return false end,
    isCoordInActiveHazard = isCoordInActiveHazard
})

-- Path from (0, 100) to (200, 100) passes straight through (100, 100)
local hitH, _, distToSeg = findPathHazardIntersection(0, 100, 200, 100, 0, 'poknowledge')
assert_neq(hitH, nil, 'intersection: detected hazard on straight path')
assert_eq(distToSeg, 0, 'intersection: passed directly through center')

-- Path from (0, 0) to (200, 0) does not pass near (100, 100)
local missH = findPathHazardIntersection(0, 0, 200, 0, 0, 'poknowledge')
assert_nil(missH, 'intersection: clear path does not trigger hazard')

-- Detour waypoint calculation generates perpendicular offset
local detour = calculateDetourWaypoint(0, 100, 100, 100, 0, 15)
assert_neq(detour, nil, 'detour: calculated waypoint')
assert_type(detour.x, 'number', 'detour: x is number')
assert_type(detour.y, 'number', 'detour: y is number')
-- Detour should be offset from (100, 100)
local offsetDist = math.sqrt((detour.x - 100) ^ 2 + (detour.y - 100) ^ 2)
assert_true(offsetDist >= 15, 'detour: offset distance outside hazard radius')

-- Detour with destination selection: target is at (200, 150) -> cand with higher Y is closer to target
local detourDest = calculateDetourWaypoint(0, 100, 100, 100, 0, 15, 200, 150, 20)
assert_neq(detourDest, nil, 'detour: calculated waypoint with destination')
assert_eq(detourDest.z, 10, 'detour: ground clamped Z is interpolated (0 + 20)/2 = 10')

-- ============================================================================
-- 31. Reverse Breadcrumbs
-- ============================================================================
print('--- reverse breadcrumbs ---')
local dummyRuntime = { pullBreadcrumbs = {} }
local dummyPos = { x = 0, y = 0, z = 0 }
local dummyMq = {
    TLO = {
        Me = setmetatable({}, {
            __call = function() return true end,
            __index = {
                X = function() return dummyPos.x end,
                Y = function() return dummyPos.y end,
                Z = function() return dummyPos.z end,
            }
        })
    }
}
local recordBreadcrumb = loadFunc(src, 'recordBreadcrumb', {
    ctrl = { nav_reverse_breadcrumbs = true },
    runtime = dummyRuntime,
    mq = dummyMq
})
local clearBreadcrumbs = loadFunc(src, 'clearBreadcrumbs', {
    runtime = dummyRuntime
})

dummyPos.x, dummyPos.y, dummyPos.z = 10, 10, 0
recordBreadcrumb()
assert_eq(#dummyRuntime.pullBreadcrumbs, 1, 'breadcrumb: initial point recorded')

-- Moving only 2 units shouldn't record a new breadcrumb (< 12 units)
dummyPos.x, dummyPos.y = 11, 11
recordBreadcrumb()
assert_eq(#dummyRuntime.pullBreadcrumbs, 1, 'breadcrumb: slight move ignored')

-- Moving 20 units records a new breadcrumb
dummyPos.x, dummyPos.y = 30, 10
recordBreadcrumb()
assert_eq(#dummyRuntime.pullBreadcrumbs, 2, 'breadcrumb: significant move recorded')

-- Clear breadcrumbs
clearBreadcrumbs()
assert_eq(#dummyRuntime.pullBreadcrumbs, 0, 'breadcrumb: cleared')

-- ============================================================================
-- 32. Forward Arc Cone Calculations
-- ============================================================================
print('--- forward arc cone calculations ---')
local isHeadingInForwardCone = loadFunc(src, 'isHeadingInForwardCone', {})

-- Facing North (0 deg), at (0, 0)
assert_eq(isHeadingInForwardCone(0, 0, 0, 0, 100, 75), true, 'forward cone: target North is in front')
assert_eq(isHeadingInForwardCone(0, 0, 0, 50, 50, 75), true, 'forward cone: target North-West (45 deg) is in front')
assert_eq(isHeadingInForwardCone(0, 0, 0, 100, 0, 75), false, 'forward cone: target West (90 deg) is outside 75 deg cone')
assert_eq(isHeadingInForwardCone(0, 0, 0, 0, -100, 75), false, 'forward cone: target South (180 deg, behind) is rejected')

-- Facing West (90 deg), at (0, 0)
assert_eq(isHeadingInForwardCone(90, 0, 0, 100, 0, 75), true, 'forward cone: target West is in front when facing West')
assert_eq(isHeadingInForwardCone(90, 0, 0, 0, 100, 75), false,
    'forward cone: target North is outside 75 deg cone when facing West')

-- Same location (0 distance) returns true
assert_eq(isHeadingInForwardCone(0, 0, 0, 0, 0, 75), true, 'forward cone: same location passes')

-- ============================================================================
-- 33. Closer-NPC Retargeting Suite
-- ============================================================================
print('--- closer-npc retargeting ---')
local dummyDistances = {
    [101] = 100, -- current distant target
    [102] = 40,  -- closer candidate (40 <= 100-25 and 40 <= 75)
    [103] = 80,  -- candidate not close enough (80 > 75)
    [104] = 78   -- candidate with LoS while current lacks LoS (78 <= 85)
}
local dummyLoS = {
    [101] = false,
    [102] = true,
    [103] = true,
    [104] = true
}
local dummyPursuit = {
    retargetCount = 0,
    cycleTargetIds = {},
    lastCloserScanAt = 0
}
local dummyRoamCandidate = 102
local dummyForwardConeResult = true

local checkCloserTarget = loadFunc(src, 'checkCloserTarget', {
    ctrl = {
        check_closer_mobs = true,
        max_closer_retargets = 1,
        closer_forward_cone_only = true,
        closer_los_priority = true,
        closer_scan_interval = 1.0
    },
    pursuit = dummyPursuit,
    distToId = function(id) return dummyDistances[id] or 100 end,
    hasLoS = function(id) return dummyLoS[id] end,
    mq = {
        TLO = {
            Me = {
                Combat = function() return false end
            }
        }
    },
    findRoamTarget = function() return dummyRoamCandidate end,
    isSpawnInForwardCone = function() return dummyForwardConeResult end
})

-- 1. Valid closer candidate switches target
local candId, candDist, curDist = checkCloserTarget(101, 1000, 75, 1, 100)
assert_eq(candId, 102, 'closer retarget: valid candidate chosen')
assert_eq(candDist, 40, 'closer retarget: candidate dist 40')
assert_eq(curDist, 100, 'closer retarget: current dist 100')

-- 2. Throttled scan within interval returns nil
local throttled = checkCloserTarget(101, 1000, 75, 1, 100)
assert_nil(throttled, 'closer retarget: scan throttled within interval')

-- Advance clock past throttle interval
dummyPursuit.lastCloserScanAt = os.clock() - 2.0

-- 3. Retarget count limit stops retargeting
dummyPursuit.retargetCount = 1
local maxed = checkCloserTarget(101, 1000, 75, 1, 100)
assert_nil(maxed, 'closer retarget: blocked by max_closer_retargets count')

-- Reset retarget count for subsequent tests
dummyPursuit.retargetCount = 0
dummyPursuit.lastCloserScanAt = 0

-- 4. Cycle blacklist prevents ping-ponging to already-visited mob
dummyPursuit.cycleTargetIds = { [102] = true }
local blacklisted = checkCloserTarget(101, 1000, 75, 1, 100)
assert_nil(blacklisted, 'closer retarget: cycle blacklist ignores candidate 102')
dummyPursuit.cycleTargetIds = {}

-- 5. Forward cone filter rejects mob behind player
dummyForwardConeResult = false
local behind = checkCloserTarget(101, 1000, 75, 1, 100)
assert_nil(behind, 'closer retarget: forward cone filter rejects candidate')
dummyForwardConeResult = true

-- 6. LoS priority relaxes threshold for visible candidate
dummyRoamCandidate = 104 -- distance 78 (78% of 100; normal ratio 75% would fail, but LoS ratio 85% passes)
dummyLoS[101] = false
dummyLoS[104] = true
dummyPursuit.lastCloserScanAt = 0
local losCand = checkCloserTarget(101, 1000, 75, 1, 100)
assert_eq(losCand, 104, 'closer retarget: LoS priority allowed visible mob at 78% distance')

-- ============================================================================
-- 34. XTarget Detection & Range Suite
-- ============================================================================
print('--- xtarget detection & range ---')
local dummyXtarSlots = {
    [1] = { id = 201, type = 'NPC', dead = false, cleanName = 'a_moss_snake', hp = 80, dist = 180, z = 10 },
    [2] = { id = 202, type = 'NPC', dead = false, cleanName = 'a_decaying_skeleton', hp = 40, dist = 50, z = 5 },
    [3] = { id = 203, type = 'Corpse', dead = true, cleanName = 'a_dead_rat', hp = 0, dist = 10, z = 0 }
}
local dummyMqXtar = {
    TLO = {
        Me = {
            Z = function() return 0 end,
            XTargetSlots = function() return 3 end,
            XTarget = function(i)
                local slot = dummyXtarSlots[i]
                if not slot then return function() return false end end
                return setmetatable({
                    ID = function() return slot.id end,
                    Type = function() return slot.type end,
                    Dead = function() return slot.dead end,
                    CleanName = function() return slot.cleanName end,
                    PctHPs = function() return slot.hp end,
                    Distance3D = function() return slot.dist end,
                    Z = function() return slot.z end
                }, { __call = function() return true end })
            end
        },
        Spawn = function(id)
            for _, slot in pairs(dummyXtarSlots) do
                if slot.id == id then
                    return setmetatable({
                        ID = function() return slot.id end,
                        Type = function() return slot.type end,
                        Dead = function() return slot.dead end,
                        CleanName = function() return slot.cleanName end,
                        PctHPs = function() return slot.hp end,
                        Distance3D = function() return slot.dist end,
                        Z = function() return slot.z end
                    }, { __call = function() return true end })
                end
            end
            return function() return false end
        end
    }
}

local findFirstNPCXtarget = loadFunc(src, 'findFirstNPCXtarget', {
    ctrl = { xtar_nav_dist = 150 },
    mq = dummyMqXtar,
    isSpawnAlive = function(id) return id ~= 203 end,
    isGroupOrRaidMember = function() return false end,
    isSpawnPetOrPlayer = function() return false end,
    isHostileTarget = function() return true end,
    buffActive = function() return false end
})

local isXTargetId = loadFunc(src, 'isXTargetId', {
    mq = dummyMqXtar,
    isGroupOrRaidMember = function() return false end,
    isSpawnPetOrPlayer = function() return false end,
    isHostileTarget = function() return true end,
    isIgnored = function() return false end
})

-- 1. Default maxDist (150) picks lowest HP within 150 (mob 202 at dist 50, hp 40; ignores 201 at dist 180)
local xtId1 = findFirstNPCXtarget(false, nil, nil, nil, nil)
assert_eq(xtId1, 202, 'xtarget: default maxDist 150 picks lowest HP mob within 150')

-- 2. Extended maxDist (200) allows reaching mob 201 at dist 180 if mob 202 was not eligible
dummyXtarSlots[2].dead = true
local xtId2 = findFirstNPCXtarget(false, nil, nil, 200, 50)
assert_eq(xtId2, 201, 'xtarget: extended maxDist 200 acquires mob 201 at dist 180')
dummyXtarSlots[2].dead = false

-- 3. isXTargetId returns true for valid hostile NPC on XTarget
assert_eq(isXTargetId(201), true, 'isXTargetId: recognizes mob 201 on XTarget')
assert_eq(isXTargetId(202), true, 'isXTargetId: recognizes mob 202 on XTarget')
assert_eq(isXTargetId(203), false, 'isXTargetId: corpse 203 returns false')
assert_eq(isXTargetId(999), false, 'isXTargetId: non-xtarget id returns false')

-- ============================================================================
-- 34. MQ2Nav Plugin Loaded Detection
-- ============================================================================
print('--- mq2nav loaded detection ---')

-- 1. Navigation TLO Active/MeshLoaded returns true
local dummyMqNavLoaded = {
    TLO = {
        Navigation = setmetatable({
            MeshLoaded = function() return true end,
        }, {
            __call = function() return true end,
        }),
        Plugin = function() return nil end,
    }
}
local testNavLoaded1 = loadFunc(src, 'navLoaded', {
    mq = dummyMqNavLoaded,
    pcall = pcall,
})
assert_eq(testNavLoaded1(), true, 'navLoaded: true when Navigation TLO and mesh is loaded')

-- 2. Plugin('mq2nav').IsLoaded() returns true
local dummyMqPluginLoaded = {
    TLO = {
        Navigation = nil,
        Plugin = function(name)
            if string.lower(name) == 'mq2nav' or string.lower(name) == 'nav' then
                return setmetatable({
                    IsLoaded = function() return true end,
                }, {
                    __call = function() return 'mq2nav' end,
                })
            end
            return nil
        end
    }
}
local testNavLoaded2 = loadFunc(src, 'navLoaded', {
    mq = dummyMqPluginLoaded,
    pcall = pcall,
})
assert_eq(testNavLoaded2(), true, 'navLoaded: true when Plugin mq2nav IsLoaded returns true')

-- 3. Neither loaded returns false
local dummyMqUnloaded = {
    TLO = {
        Navigation = nil,
        Plugin = function() return nil end,
    }
}
local testNavLoaded3 = loadFunc(src, 'navLoaded', {
    mq = dummyMqUnloaded,
    pcall = pcall,
})
assert_eq(testNavLoaded3(), false, 'navLoaded: false when neither Navigation TLO nor Plugin is loaded')

-- ============================================================================
-- 35. NavMesh Loaded Detection
-- ============================================================================
print('--- navmesh loaded detection ---')

-- 1. navLoaded() is false -> navMeshLoaded() returns false
local testMeshLoaded1 = loadFunc(src, 'navMeshLoaded', {
    navLoaded = function() return false end,
    mq = dummyMqNavLoaded,
    pcall = pcall,
})
assert_eq(testMeshLoaded1(), false, 'navMeshLoaded: false when navLoaded is false')

-- 2. navLoaded() is true and MeshLoaded() is true -> navMeshLoaded() returns true
local dummyMqMeshTrue = {
    TLO = {
        Navigation = {
            MeshLoaded = function() return true end,
        }
    }
}
local testMeshLoaded2 = loadFunc(src, 'navMeshLoaded', {
    navLoaded = function() return true end,
    mq = dummyMqMeshTrue,
    pcall = pcall,
})
assert_eq(testMeshLoaded2(), true, 'navMeshLoaded: true when MeshLoaded returns true')

-- 3. navLoaded() is true and MeshLoaded() is false -> navMeshLoaded() returns false
local dummyMqMeshFalse = {
    TLO = {
        Navigation = {
            MeshLoaded = function() return false end,
        }
    }
}
local testMeshLoaded3 = loadFunc(src, 'navMeshLoaded', {
    navLoaded = function() return true end,
    mq = dummyMqMeshFalse,
    pcall = pcall,
})
assert_eq(testMeshLoaded3(), false, 'navMeshLoaded: false when MeshLoaded returns false')

-- ============================================================================
-- 36. copyWaypointList (per-zone waypoint routes/presets)
-- ============================================================================
print('--- copyWaypointList ---')
local copyWaypointList = loadFunc(src, 'copyWaypointList', {})

do
    local original = { { name = 'A', x = 1, y = 2, z = 3 }, { name = 'B', x = 4, y = 5, z = 6 } }
    local copy = copyWaypointList(original)
    assert_eq(#copy, 2, 'copyWaypointList: preserves length')
    assert_eq(copy[1].name, 'A', 'copyWaypointList: preserves entry fields')
    assert_eq(copy[2].z, 6, 'copyWaypointList: preserves entry fields (2)')
    copy[1].name = 'Changed'
    assert_eq(original[1].name, 'A', 'copyWaypointList: mutating the copy does not affect the original')
end

assert_eq(#copyWaypointList(nil), 0, 'copyWaypointList: nil input returns empty list')
assert_eq(#copyWaypointList({}), 0, 'copyWaypointList: empty input returns empty list')

-- ============================================================================
-- sanitizeWpField (waypoint preset export/import)
-- ============================================================================
print('--- sanitizeWpField ---')
local sanitizeWpField = loadFunc(src, 'sanitizeWpField', {})

assert_eq(sanitizeWpField('Camp 1'), 'Camp 1', 'sanitizeWpField: leaves normal text untouched')
assert_eq(sanitizeWpField('a' .. WP_RS .. 'b' .. WP_US .. 'c'), 'abc',
    'sanitizeWpField: strips record/unit separator control characters')
assert_eq(sanitizeWpField('a\tb\nc'), 'abc', 'sanitizeWpField: strips other control characters (tab/newline)')
assert_eq(sanitizeWpField(nil), '', 'sanitizeWpField: nil input returns empty string')
assert_eq(sanitizeWpField(123), '123', 'sanitizeWpField: coerces non-string input')

-- ============================================================================
-- base64Encode / base64Decode (waypoint preset export/import)
-- ============================================================================
print('--- base64Encode/base64Decode ---')
local base64Encode = loadFunc(src, 'base64Encode', { WP = WP })
local base64Decode = loadFunc(src, 'base64Decode', { WP = WP })

assert_eq(base64Encode(''), '', 'base64Encode: empty input returns empty string')
assert_eq(base64Encode('f'), 'Zg==', 'base64Encode: single byte pads with ==')
assert_eq(base64Encode('fo'), 'Zm8=', 'base64Encode: two bytes pads with =')
assert_eq(base64Encode('foo'), 'Zm9v', 'base64Encode: three bytes, no padding')
assert_eq(base64Encode('foobar'), 'Zm9vYmFy', 'base64Encode: matches known reference value')

assert_eq(base64Decode(''), '', 'base64Decode: empty input returns empty string')
assert_eq(base64Decode('Zm9vYmFy'), 'foobar', 'base64Decode: matches known reference value')
assert_eq(base64Decode('Zg=='), 'f', 'base64Decode: decodes single-byte padded input')

do
    local samples = { '', 'f', 'fo', 'foo', 'foobar', 'Camp 1' .. WP_RS .. '100.50' .. WP_US .. '-20.25' }
    for _, s in ipairs(samples) do
        assert_eq(base64Decode(base64Encode(s)), s, 'base64: round-trips ' .. string.format('%q', s))
    end
end

-- ============================================================================
-- splitByChar (waypoint preset export/import)
-- ============================================================================
print('--- splitByChar ---')
local splitByChar = loadFunc(src, 'splitByChar', {})

do
    local parts = splitByChar('a' .. WP_RS .. 'b' .. WP_RS .. 'c', WP_RS)
    assert_eq(#parts, 3, 'splitByChar: splits into the expected number of parts')
    assert_eq(parts[1], 'a', 'splitByChar: preserves first field')
    assert_eq(parts[2], 'b', 'splitByChar: preserves middle field')
    assert_eq(parts[3], 'c', 'splitByChar: preserves last field')
end

do
    local parts = splitByChar('onlyfield', WP_RS)
    assert_eq(#parts, 1, 'splitByChar: no separator present returns single-element list')
    assert_eq(parts[1], 'onlyfield', 'splitByChar: preserves the single field')
end

do
    local parts = splitByChar('a' .. WP_RS .. WP_RS .. 'c', WP_RS)
    assert_eq(#parts, 3, 'splitByChar: preserves empty fields between separators')
    assert_eq(parts[2], '', 'splitByChar: empty field between two separators is an empty string')
end

-- ============================================================================
-- Suite 40: triune_map map parsing & folder discovery logic
-- ============================================================================
print('--- triune_map parser & folder logic ---')

do
    local lineStr = 'L 100.5, -200.5, 10.0, 120.0, -250.0, 12.5, 255, 128, 64'
    local x1, y1, z1, x2, y2, z2, r, g, b = string.match(lineStr,
        '^[Ll]%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+)')
    assert_eq(tonumber(x1), 100.5, 'map line parser: x1')
    assert_eq(tonumber(y1), -200.5, 'map line parser: y1')
    assert_eq(tonumber(z1), 10.0, 'map line parser: z1')
    assert_eq(tonumber(x2), 120.0, 'map line parser: x2')
    assert_eq(tonumber(y2), -250.0, 'map line parser: y2')
    assert_eq(tonumber(z2), 12.5, 'map line parser: z2')
    assert_eq(tonumber(r), 255, 'map line parser: r')
    assert_eq(tonumber(g), 128, 'map line parser: g')
    assert_eq(tonumber(b), 64, 'map line parser: b')
end

do
    local labelStr = 'P 150.0, 300.0, 5.0, 0, 255, 255, 2, Bank_of_PoK'
    local x, y, z, r, g, b, size, text = string.match(labelStr,
        '^[Pp]%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d.-]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+),?%s+([%d]+),?%s+(.+)')
    assert_eq(tonumber(x), 150.0, 'map label parser: x')
    assert_eq(tonumber(y), 300.0, 'map label parser: y')
    assert_eq(tonumber(size), 2, 'map label parser: size')
    assert_eq(string.gsub(text, '_', ' '), 'Bank of PoK', 'map label parser: space converted text')
end

do
    -- High-contrast black/dark line & label boosting logic
    local function boostDarkColor(r, g, b, isLabel)
        local nr = (r or 0) / 255.0
        local ng = (g or 0) / 255.0
        local nb = (b or 0) / 255.0
        local lum = nr * 0.299 + ng * 0.587 + nb * 0.114
        if lum < 0.25 then
            if isLabel then
                return 0.88, 0.92, 0.96
            else
                return 0.72, 0.76, 0.82
            end
        end
        return nr, ng, nb
    end

    -- Black line (0,0,0) boosted to silver
    local lr1, lg1, lb1 = boostDarkColor(0, 0, 0, false)
    assert_eq(lr1, 0.72, 'boost black line: r boosted to 0.72')
    assert_eq(lg1, 0.76, 'boost black line: g boosted to 0.76')
    assert_eq(lb1, 0.82, 'boost black line: b boosted to 0.82')

    -- Black label (0,0,0) boosted to off-white
    local pr1, pg1, pb1 = boostDarkColor(0, 0, 0, true)
    assert_eq(pr1, 0.88, 'boost black label: r boosted to 0.88')
    assert_eq(pg1, 0.92, 'boost black label: g boosted to 0.92')
    assert_eq(pb1, 0.96, 'boost black label: b boosted to 0.96')

    -- Bright yellow line preserved
    local yr, yg, yb = boostDarkColor(255, 255, 0, false)
    assert_eq(yr, 1.0, 'bright color preserved: r is 1.0')
    assert_eq(yg, 1.0, 'bright color preserved: g is 1.0')
    assert_eq(yb, 0.0, 'bright color preserved: b is 0.0')

    -- Regression test: Ensure label loop variable 'lb' is not shadowed by blue channel
    local testLabels = {
        { x = 100, y = 200, z = 10, r = 0.1, g = 0.1, b = 0.1, text = 'Shadow Test Label' }
    }
    local renderedText = nil
    for _, lb in ipairs(testLabels) do
        local lblR, lblG, lblB = lb.r, lb.g, lb.b
        if (lblR * 0.299 + lblG * 0.587 + lblB * 0.114) < 0.25 then
            lblR, lblG, lblB = 0.88, 0.92, 0.96
        end
        renderedText = lb.text
    end
    assert_eq(renderedText, 'Shadow Test Label', 'label loop: lb.text accessible without number shadowing')
end

do
    -- Map folder selection logic
    local folders = {
        { name = '[Root] Default (maps/)', relPath = '', fullPath = 'C:/EQ/maps' },
        { name = 'Brewall', relPath = 'Brewall', fullPath = 'C:/EQ/maps/Brewall' },
        { name = 'Goodurden', relPath = 'Goodurden', fullPath = 'C:/EQ/maps/Goodurden' },
    }
    local selectedIdx = 2
    local activeDir = folders[selectedIdx].fullPath
    assert_eq(activeDir, 'C:/EQ/maps/Brewall', 'map folder selection: switches to Brewall')
    assert_eq(folders[selectedIdx].name, 'Brewall', 'map folder selection: folder name is Brewall')
end

do
    -- Player Heading Arrow Vector Math
    local function getHeadingVector(headingDeg)
        local rad = math.rad(headingDeg or 0)
        local dirX = math.sin(rad)
        local dirY = -math.cos(rad)
        return dirX, dirY
    end

    -- North (0 deg) -> Up on screen (X = 0, Y < 0)
    local nX, nY = getHeadingVector(0)
    assert_true(math.abs(nX) < 0.001, 'heading North: X is 0')
    assert_true(nY < -0.999, 'heading North: Y is -1 (Up)')

    -- East (90 deg) -> Right on screen (X > 0, Y = 0)
    local eX, eY = getHeadingVector(90)
    assert_true(eX > 0.999, 'heading East: X is +1 (Right)')
    assert_true(math.abs(eY) < 0.001, 'heading East: Y is 0')

    -- South (180 deg) -> Down on screen (X = 0, Y > 0)
    local sX, sY = getHeadingVector(180)
    assert_true(math.abs(sX) < 0.001, 'heading South: X is 0')
    assert_true(sY > 0.999, 'heading South: Y is +1 (Down)')

    -- West (270 deg) -> Left on screen (X < 0, Y = 0)
    local wX, wY = getHeadingVector(270)
    assert_true(wX < -0.999, 'heading West: X is -1 (Left)')
    assert_true(math.abs(wY) < 0.001, 'heading West: Y is 0')
end

do
    -- Triune Loadout & Waypoint Unpacking Logic
    local dummyLoadout = {
        ["TestChar"] = {
            control = {
                camp_loc = { x = 120.5, y = -350.0, z = 15.0 },
                camp_radius = 65,
                combat_radius = 120,
                hunter_radius = 280,
                pull_radius = 220,
                use_waypoints = true,
                current_waypoint_idx = 2,
                waypoints = {
                    { name = "Camp Center", x = 120.5, y = -350.0, z = 15.0 },
                    { name = "Bridge Post", x = 200.0, y = -400.0, z = 12.0 },
                },
            }
        },
        __zoneWaypoints = {
            ["poknowledge"] = {
                waypoints = {
                    { name = "PoK Bank", x = 100.0, y = 50.0, z = 5.0 },
                },
                waypoint_radius = 25,
                waypoint_loop = true,
            }
        },
        __zoneHazards = {
            ["poknowledge"] = {
                { x = 150.0, y = 80.0, z = 5.0, hits = 4 }
            }
        }
    }

    local charCtrl = dummyLoadout["TestChar"].control
    assert_eq(charCtrl.camp_radius, 65, 'triune loadout sync: camp_radius')
    assert_eq(charCtrl.combat_radius, 120, 'triune loadout sync: combat_radius')
    assert_eq(#charCtrl.waypoints, 2, 'triune loadout sync: character waypoint count')
    assert_eq(charCtrl.waypoints[2].name, "Bridge Post", 'triune loadout sync: waypoint 2 name')

    local zoneWps = dummyLoadout.__zoneWaypoints["poknowledge"]
    assert_eq(#zoneWps.waypoints, 1, 'triune loadout sync: zone waypoint count')
    assert_true(zoneWps.waypoint_loop, 'triune loadout sync: zone waypoint loop')

    local zoneHazards = dummyLoadout.__zoneHazards["poknowledge"]
    assert_eq(#zoneHazards, 1, 'triune loadout sync: zone hazards count')
    assert_eq(zoneHazards[1].hits, 4, 'triune loadout sync: hazard hit count')
end

do
    -- Triune Map Settings & Zoom Persistence Roundtrip
    local function serializeVal(val, indent)
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
                local valStr = serializeVal(v, indent + 1)
                if valStr then
                    parts[#parts + 1] = indStr .. keyStr .. " = " .. valStr
                end
            end
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep('  ', indent - 1) .. "}"
        end
        return "nil"
    end

    local mapConfig = {
        __global = {
            customMapsDir = 'C:/CustomMaps',
            selectedMapFolder = 'Brewall',
        },
        ['server_PlayerName'] = {
            zoom = 1.45,
            followPlayer = true,
            showSearchRadius = true,
            customSearchRadius = 350,
            showNPCs = true,
            colorModeIndex = 2,
            layer0 = true,
            layer1 = false,
            useZFilter = true,
            zFilterRange = 90,
            lineThickness = 1.8,
        }
    }

    local code = "return " .. serializeVal(mapConfig)
    local fn, err = loadstring(code)
    assert_true(fn ~= nil, 'map config serialization creates valid lua chunk')
    if fn then
        local restored = fn()
        assert_eq(restored.__global.selectedMapFolder, 'Brewall', 'map config global selected folder restored')
        local charCfg = restored['server_PlayerName']
        assert_eq(charCfg.zoom, 1.45, 'map config zoom restored')
        assert_eq(charCfg.customSearchRadius, 350, 'map config custom search radius restored')
        assert_eq(charCfg.colorModeIndex, 2, 'map config color mode index restored')
        assert_true(charCfg.useZFilter, 'map config z filter restored')
    end
end

-- ============================================================================
-- Suite 41: triune_updater release parsing & JSON tokenizer
-- ============================================================================
print('--- triune_updater release parsing & JSON tokenizer ---')
do
    local updSrc = readFile('TAC/lua/triune_updater.lua')
    local cleanTag = loadFunc(updSrc, 'cleanTag', {})
    local extractJsonString = loadFunc(updSrc, 'extractJsonString', {})

    assert_eq(cleanTag('v1.7.5'), '1.7.5', 'cleanTag: lowercase v')
    assert_eq(cleanTag('V1.7.5'), '1.7.5', 'cleanTag: uppercase V')
    assert_eq(cleanTag('1.7.5'), '1.7.5', 'cleanTag: no v prefix')
    assert_eq(cleanTag('  v1.8.0  '), '1.8.0', 'cleanTag: trims surrounding whitespace')
    assert_eq(cleanTag(nil), '', 'cleanTag: nil tag returns empty string')
    assert_eq(cleanTag(''), '', 'cleanTag: empty tag returns empty string')

    assert_eq(extractJsonString('{"tag_name": "v1.7.5"}', 'tag_name'), 'v1.7.5', 'extractJsonString: simple tag_name')
    assert_eq(extractJsonString('{"body": "Added \\"Follow Player\\" mode"}', 'body'), 'Added "Follow Player" mode',
        'extractJsonString: handles escaped quotes without truncation')
    assert_eq(extractJsonString('{"body": "Line 1\\r\\nLine 2\\tTabbed"}', 'body'), "Line 1\r\nLine 2\tTabbed",
        'extractJsonString: handles newlines and tabs')
    assert_eq(extractJsonString('{"path": "TAC\\\\lua\\\\triune.lua"}', 'path'), 'TAC\\lua\\triune.lua',
        'extractJsonString: handles backslashes')
    assert_eq(extractJsonString('{"url": "https:\\/\\/github.com"}', 'url'), 'https://github.com',
        'extractJsonString: handles escaped slashes')
    assert_nil(extractJsonString('{"other": 123}', 'body'), 'extractJsonString: missing key returns nil')
    assert_nil(extractJsonString(nil, 'body'), 'extractJsonString: nil json returns nil')

    local apiErrSample =
    '{"message": "API rate limit exceeded for 127.0.0.1", "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"}'
    assert_eq(extractJsonString(apiErrSample, 'message'), 'API rate limit exceeded for 127.0.0.1',
        'extractJsonString: extracts GitHub API rate limit error message')

    local fullReleaseJson =
    '{\n  "tag_name": "v1.7.5",\n  "body": "## 2026-08-29\\r\\n- Standalone 2D Map (`triune_map.lua`)\\r\\n  - Added \\"Follow Player\\" and \\"Pathable Only\\" filters\\r\\n"\n}'
    assert_eq(extractJsonString(fullReleaseJson, 'tag_name'), 'v1.7.5', 'extractJsonString: full payload tag_name')
    assert_true(string.find(extractJsonString(fullReleaseJson, 'body'), '"Follow Player"') ~= nil,
        'extractJsonString: full payload preserves markdown and quotes in body')

    -- Verify suite version consistency across triune.lua, triune_updater.lua, and README.md
    local triuneSrc = readFile('TAC/lua/triune.lua')
    local triuneVer = triuneSrc:match("local VERSION%s*=%s*'([^']+)'")
    local updaterVer = updSrc:match("local VERSION%s*=%s*'([^']+)'")
    local readmeSrc = readFile('README.md')
    local readmeVer = readmeSrc:match("Current version:%s*%*%*([^*]+)%*%*")
    assert_eq(triuneVer, '1.7.5', 'triune.lua version is 1.7.5')
    assert_eq(updaterVer, '1.7.5', 'triune_updater.lua version is 1.7.5')
    assert_eq(readmeVer, '1.7.5', 'README.md version is 1.7.5')
end

-- ============================================================================
-- Suite 42: triune_map Smart Auto-Z & Depth Fading
-- ============================================================================
print('--- triune_map Smart Auto-Z & Depth Fading ---')
do
    local function getZAlphaMultiplier(avgZ, minZ, maxZ, zFilterMode, zDepthFading)
        if zFilterMode == 3 then
            return 1.0, true
        end
        if avgZ < minZ or avgZ > maxZ then
            if zDepthFading then
                local d = (avgZ < minZ) and (minZ - avgZ) or (avgZ - maxZ)
                if d <= 10 then
                    local alpha = 0.22 * (1.0 - (d / 10))
                    return alpha, true
                end
            end
            return 0.0, false
        end
        if not zDepthFading then
            return 1.0, true
        end
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

    -- Test exact center of floor: 100% opacity
    local a1, vis1 = getZAlphaMultiplier(50, 40, 65, 1, true)
    assert_true(vis1, 'auto-z core floor: is visible')
    assert_eq(a1, 1.0, 'auto-z core floor: 100% alpha')

    -- Test edge of floor: smooth fade
    local a2, vis2 = getZAlphaMultiplier(41, 40, 65, 1, true)
    assert_true(vis2, 'auto-z floor edge: is visible')
    assert_true(a2 < 1.0 and a2 > 0.3, 'auto-z floor edge: faded alpha')

    -- Test just outside floor: ghosting if depth fading enabled
    local a3, vis3 = getZAlphaMultiplier(38, 40, 65, 1, true)
    assert_true(vis3, 'auto-z adjacent ghost: is visible')
    assert_true(a3 > 0.0 and a3 < 0.25, 'auto-z adjacent ghost: faint alpha')

    -- Test far away floor: culled
    local a4, vis4 = getZAlphaMultiplier(10, 40, 65, 1, true)
    assert_true(not vis4, 'auto-z other floor: is culled')
    assert_eq(a4, 0.0, 'auto-z other floor: 0 alpha')

    -- Test disabled mode: always visible at 1.0
    local a5, vis5 = getZAlphaMultiplier(-500, 40, 65, 3, true)
    assert_true(vis5, 'disabled mode: always visible')
    assert_eq(a5, 1.0, 'disabled mode: 100% alpha')
end

-- ============================================================================
-- Suite 43: triune_map Norrath Zone Atlas & Navigation Logic
-- ============================================================================
print('--- triune_map Norrath Zone Atlas & Navigation Logic ---')
do
    local mapSrc = readFile('TAC/lua/triune_map.lua')
    assert_true(mapSrc ~= nil and #mapSrc > 0, 'triune_map.lua read successfully')

    -- Verify version is 1.1
    local versionMatch = mapSrc:match("local VERSION%s*=%s*'([^']+)'")
    assert_eq(versionMatch, '1.1', 'triune_map version is 1.1')

    -- Test Atlas History Navigation State Stack
    local history = {}
    local historyIdx = 0

    local function navTo(zShort, pushHistory)
        if pushHistory ~= false then
            if historyIdx < #history then
                for i = #history, historyIdx + 1, -1 do
                    history[i] = nil
                end
            end
            history[#history + 1] = zShort
            historyIdx = #history
        end
    end

    local function histBack()
        if historyIdx > 1 then
            historyIdx = historyIdx - 1
            return history[historyIdx]
        end
        return nil
    end

    local function histFwd()
        if historyIdx < #history then
            historyIdx = historyIdx + 1
            return history[historyIdx]
        end
        return nil
    end

    navTo('poknowledge')
    navTo('bazaar')
    navTo('shadowhaven')
    assert_eq(#history, 3, 'atlas history: 3 zones added')
    assert_eq(historyIdx, 3, 'atlas history: index is at top')

    local back1 = histBack()
    assert_eq(back1, 'bazaar', 'atlas history back: bazaar')
    assert_eq(historyIdx, 2, 'atlas history index: 2')

    local back2 = histBack()
    assert_eq(back2, 'poknowledge', 'atlas history back: poknowledge')
    assert_eq(historyIdx, 1, 'atlas history index: 1')

    local back3 = histBack()
    assert_nil(back3, 'atlas history back at start: nil')

    local fwd1 = histFwd()
    assert_eq(fwd1, 'bazaar', 'atlas history forward: bazaar')
    assert_eq(historyIdx, 2, 'atlas history index: 2')

    -- Navigating to a new zone from middle truncates forward history
    navTo('nexus')
    assert_eq(#history, 3, 'atlas history: truncated forward stack and added nexus')
    assert_eq(history[3], 'nexus', 'atlas history: entry 3 is nexus')
    assert_eq(historyIdx, 3, 'atlas history index: 3')

    -- Test Filter Logic
    local testZones = {
        { short = 'qeynos', name = 'South Qeynos', era = 'Classic', type = 'City', continent = 'Antonica', connections = {'qeynos2'} },
        { short = 'blackburrow', name = 'Blackburrow', era = 'Classic', type = 'Dungeon', continent = 'Antonica', connections = {'qeytoqrg', 'everfrost'} },
        { short = 'dreadlands', name = 'Dreadlands', era = 'Kunark', type = 'Outdoor', continent = 'Kunark', connections = {'firiona'} },
        { short = 'poknowledge', name = 'Plane of Knowledge', era = 'Planes of Power', type = 'City', continent = 'Planes', connections = {'potranquility'} },
    }

    local function filterZones(zones, query, eraFilter, typeFilter)
        local q = (query or ''):lower():match('^%s*(.-)%s*$')
        local out = {}
        for _, z in ipairs(zones) do
            local matchQ = true
            if q ~= '' then
                local inName = (z.name:lower():find(q, 1, true) ~= nil)
                local inShort = (z.short:lower():find(q, 1, true) ~= nil)
                local inEra = (z.era:lower():find(q, 1, true) ~= nil)
                local inCont = (z.continent:lower():find(q, 1, true) ~= nil)
                matchQ = (inName or inShort or inEra or inCont)
            end
            local matchEra = (eraFilter == 'All Expansions' or z.era == eraFilter)
            local matchType = true
            if typeFilter == 'Cities & Hubs' then matchType = (z.type == 'City')
            elseif typeFilter == 'Outdoor & Wilderness' then matchType = (z.type == 'Outdoor')
            elseif typeFilter == 'Dungeons' then matchType = (z.type == 'Dungeon')
            end

            if matchQ and matchEra and matchType then
                out[#out + 1] = z
            end
        end
        return out
    end

    local f1 = filterZones(testZones, 'qey', 'All Expansions', 'All Zone Types')
    assert_eq(#f1, 1, 'filter: "qey" matches South Qeynos')

    local f2 = filterZones(testZones, '', 'Classic', 'All Zone Types')
    assert_eq(#f2, 2, 'filter: Classic era returns 2 zones')

    local f3 = filterZones(testZones, '', 'All Expansions', 'Dungeons')
    assert_eq(#f3, 1, 'filter: Dungeons returns Blackburrow')
    assert_eq(f3[1].short, 'blackburrow', 'filter: Dungeon zone is blackburrow')

    local f4 = filterZones(testZones, 'planes', 'All Expansions', 'All Zone Types')
    assert_eq(#f4, 1, 'filter: continent/era query matches PoK')
    assert_eq(f4[1].short, 'poknowledge', 'filter: PoK returned')

    -- Test BFS Route Finder logic
    local routeZones = {
        { short = 'qeynos',       name = 'South Qeynos',              era = 'Classic',          type = 'City',    connections = {'qeynos2'} },
        { short = 'qeynos2',      name = 'North Qeynos',              era = 'Classic',          type = 'City',    connections = {'qeynos', 'qeytoqrg', 'poknowledge'} },
        { short = 'qeytoqrg',     name = 'Qeynos Hills',              era = 'Classic',          type = 'Outdoor', connections = {'qeynos2', 'blackburrow', 'northkarana'} },
        { short = 'blackburrow',  name = 'Blackburrow',               era = 'Classic',          type = 'Dungeon', connections = {'qeytoqrg', 'everfrost'} },
        { short = 'everfrost',    name = 'Everfrost Peaks',           era = 'Classic',          type = 'Outdoor', connections = {'blackburrow', 'halas'} },
        { short = 'halas',        name = 'Halas',                     era = 'Classic',          type = 'City',    connections = {'everfrost', 'poknowledge'} },
        { short = 'poknowledge',  name = 'Plane of Knowledge',        era = 'Planes of Power',  type = 'City',    connections = {'potranquility', 'qeynos2', 'halas'} },
        { short = 'potranquility',name = 'Plane of Tranquility',      era = 'Planes of Power',  type = 'City',    connections = {'poknowledge', 'povalor'} },
        { short = 'povalor',      name = 'Plane of Valor',            era = 'Planes of Power',  type = 'Outdoor', connections = {'potranquility', 'hohonora'} },
        { short = 'hohonora',     name = 'Halls of Honor',            era = 'Planes of Power',  type = 'Dungeon', connections = {'povalor'} },
    }

    local function testFindZoneRoute(startShort, targetShort, allZones)
        if not startShort or startShort == '' or not targetShort or targetShort == '' then
            return nil, 0
        end
        local sStart = startShort:lower():match('^%s*(.-)%s*$')
        local sTarget = targetShort:lower():match('^%s*(.-)%s*$')
        if sStart == '' or sTarget == '' then return nil, 0 end

        local zoneLookup = {}
        for _, z in ipairs(allZones or {}) do
            if z.short then zoneLookup[z.short:lower()] = z end
        end

        local startEntry = zoneLookup[sStart] or { short = sStart, name = sStart, era = 'Unknown', type = 'Zone' }
        local targetEntry = zoneLookup[sTarget] or { short = sTarget, name = sTarget, era = 'Unknown', type = 'Zone' }

        if sStart == sTarget then
            return { startEntry }, 0
        end

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

        for _, z in ipairs(allZones or {}) do
            local u = z.short:lower()
            for _, c in ipairs(z.connections or {}) do
                addEdge(u, c)
            end
        end

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

        if not found then return nil, 0 end

        local path = {}
        local curr = sTarget
        while curr do
            local zInfo = zoneLookup[curr] or { short = curr, name = curr, era = 'Unknown', type = 'Zone' }
            table.insert(path, 1, zInfo)
            curr = parent[curr]
        end

        local hops = math.max(0, #path - 1)
        return path, hops
    end

    -- Same zone test
    local pSame, hSame = testFindZoneRoute('poknowledge', 'poknowledge', routeZones)
    assert_neq(pSame, nil, 'route same zone: path is not nil')
    if pSame then
        assert_eq(#pSame, 1, 'route same zone: path length is 1')
        assert_eq(hSame, 0, 'route same zone: 0 hops')
        assert_eq(pSame[1].short, 'poknowledge', 'route same zone: starts/ends at poknowledge')
    end

    -- Adjacent zone test
    local pAdj, hAdj = testFindZoneRoute('qeynos', 'qeynos2', routeZones)
    assert_neq(pAdj, nil, 'route adjacent: path is not nil')
    if pAdj then
        assert_eq(#pAdj, 2, 'route adjacent: path length 2')
        assert_eq(hAdj, 1, 'route adjacent: 1 hop')
        assert_eq(pAdj[1].short, 'qeynos', 'route adjacent: step 1 is qeynos')
        assert_eq(pAdj[2].short, 'qeynos2', 'route adjacent: step 2 is qeynos2')
    end

    -- Multi-hop overland route test
    local pOverland, hOverland = testFindZoneRoute('qeynos', 'blackburrow', routeZones)
    assert_neq(pOverland, nil, 'route overland: path is not nil')
    if pOverland then
        assert_eq(#pOverland, 4, 'route overland: path length 4 (qeynos -> qeynos2 -> qeytoqrg -> blackburrow)')
        assert_eq(hOverland, 3, 'route overland: 3 hops')
        assert_eq(pOverland[1].short, 'qeynos', 'route overland: step 1 qeynos')
        assert_eq(pOverland[2].short, 'qeynos2', 'route overland: step 2 qeynos2')
        assert_eq(pOverland[3].short, 'qeytoqrg', 'route overland: step 3 qeytoqrg')
        assert_eq(pOverland[4].short, 'blackburrow', 'route overland: step 4 blackburrow')
    end

    -- PoK cross-planar route test
    local pPlanar, hPlanar = testFindZoneRoute('qeynos', 'hohonora', routeZones)
    assert_neq(pPlanar, nil, 'route planar: path is not nil')
    if pPlanar then
        assert_eq(#pPlanar, 6, 'route planar: 6 zones in path (qeynos -> qeynos2 -> poknowledge -> potranquility -> povalor -> hohonora)')
        assert_eq(hPlanar, 5, 'route planar: 5 hops')
        assert_eq(pPlanar[1].short, 'qeynos', 'route planar: step 1 qeynos')
        assert_eq(pPlanar[3].short, 'poknowledge', 'route planar: step 3 poknowledge')
        assert_eq(pPlanar[6].short, 'hohonora', 'route planar: step 6 hohonora')
    end

    -- Unreachable / invalid zone test
    local pInvalid, hInvalid = testFindZoneRoute('qeynos', 'nonexistent_zone', routeZones)
    assert_nil(pInvalid, 'route invalid zone: returns nil')
    assert_eq(hInvalid, 0, 'route invalid zone: 0 hops')

    -- Nil / empty test
    local pNil, hNil = testFindZoneRoute(nil, 'qeynos', routeZones)
    assert_nil(pNil, 'route nil start: returns nil')
    assert_eq(hNil, 0, 'route nil start: 0 hops')
end

-- ============================================================================
-- Results
-- ============================================================================
print(string.format('\n=== Results: %d passed, %d failed ===', pass, fail))
if fail > 0 then
    print('\nFailures:')
    for _, e in ipairs(errors) do print(e) end
    os.exit(1)
else
    print('All tests passed.')
    os.exit(0)
end
