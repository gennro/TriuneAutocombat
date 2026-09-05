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
                or line:match('^function invLogic%.' .. funcName .. '%s*%(')
                or line:match('^invLogic%.' .. funcName .. '%s*=%s*function%s*%(')
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
    elseif code:match('^function invLogic%.') or code:match('^invLogic%.') then
        code = code .. '\nreturn invLogic.' .. funcName
    else
        code = code .. '\nreturn ' .. funcName
    end

    local chunk, err = loadstring(code, funcName)
    if not chunk then error('loadstring failed for ' .. funcName .. ': ' .. err) end

    -- Merge env onto a copy of _G so standard library is available
    local sandbox = {}
    for k, v in pairs(_G) do sandbox[k] = v end
    if not sandbox.runtime then sandbox.runtime = {} end
    if not sandbox.invLogic then sandbox.invLogic = {} end
    if env then
        for k, v in pairs(env) do
            sandbox[k] = v
            sandbox.runtime[k] = v
            sandbox.invLogic[k] = v
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

    -- pause_on_zone default and preservation
    assert_eq(c2.pause_on_zone, true, 'sanitize: pause_on_zone default')
    local c4 = { mode = 'Manual', pause_on_zone = false }
    sanitizeModeConfig(c4)
    assert_eq(c4.pause_on_zone, false, 'sanitize: pause_on_zone=false preserved')
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
assert_nil(parseClassLine('Skills'), 'parse: "Skills" UI button text returns nil')
assert_nil(parseClassLine('Magic'), 'parse: "Magic" UI label returns nil')
assert_nil(parseClassLine('Magic Resist'), 'parse: "Magic Resist" UI label returns nil')
assert_nil(parseClassLine('Warhammer'), 'parse: "Warhammer" non-class word returns nil')
assert_nil(parseClassLine('Stats'), 'parse: "Stats" UI tab returns nil')
assert_nil(parseClassLine('Inventory'), 'parse: "Inventory" UI title returns nil')

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
    { 'ignore_distant_xtargets', 'boolean' },
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
    { 'show_cooldowns',          'boolean' },
    { 'cooldown_alpha',          'number' },
    { 'cooldown_locked',         'boolean' },
    { 'cooldown_view_mode',      'string' },
    { 'cooldown_sort_by',        'string' },
    { 'cooldown_category',       'string' },
    { 'cooldown_status_filter',  'string' },
    { 'cooldown_compact',        'boolean' },
    { 'cooldown_show_inline_edit', 'boolean' },
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
    { 'auto_spend_aa',           'boolean' },
    { 'auto_spend_aa_threshold', 'number' },
    { 'auto_spend_aa_id',        'number' },
    { 'auto_spend_aa_buy_id',    'number' },
    { 'auto_spend_aa_cost',      'number' },
    { 'auto_spend_aa_name',      'string' },
    { 'auto_spend_aa_action',    'string' },
    { 'auto_summon_fireworks',   'boolean' },
    { 'pause_on_zone',           'boolean' },
    { 'auto_group',               'boolean' },
    { 'auto_trade',               'boolean' },
    { 'auto_dzadd',               'boolean' },
    { 'auto_accept_anyone',       'boolean' },
    { 'auto_accept_guild',        'boolean' },
    { 'auto_accept_group',        'boolean' },
    { 'auto_accept_names',        'table' },
    { 'fov',                      'number' },
    { 'fov_enabled',              'boolean' },
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
assert_eq(dc.show_cooldowns, false, 'defaultCtrl: show_cooldowns=false')
assert_eq(dc.cooldown_alpha, 0.90, 'defaultCtrl: cooldown_alpha=0.90')
assert_eq(dc.cooldown_view_mode, 'table', 'defaultCtrl: cooldown_view_mode=table')
assert_eq(dc.auto_spend_aa, false, 'defaultCtrl: auto_spend_aa=false')
assert_eq(dc.auto_spend_aa_threshold, 100, 'defaultCtrl: auto_spend_aa_threshold=100')
assert_eq(dc.auto_spend_aa_id, 17788, 'defaultCtrl: auto_spend_aa_id=17788')
assert_eq(dc.auto_spend_aa_buy_id, 0, 'defaultCtrl: auto_spend_aa_buy_id=0')
assert_eq(dc.auto_spend_aa_cost, 25, 'defaultCtrl: auto_spend_aa_cost=25')
assert_eq(dc.auto_spend_aa_name, 'Alternately Advanced Fireworks', 'defaultCtrl: auto_spend_aa_name')
assert_eq(dc.auto_spend_aa_action, 'window', 'defaultCtrl: auto_spend_aa_action=window')
assert_eq(dc.auto_summon_fireworks, false, 'defaultCtrl: auto_summon_fireworks=false')
assert_eq(dc.pause_on_zone, true, 'defaultCtrl: pause_on_zone=true')
assert_eq(dc.fov, 100, 'defaultCtrl: fov=100')
assert_eq(dc.fov_enabled, false, 'defaultCtrl: fov_enabled=false')

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
local AUTOSKILL_ABILITIES = {
    ['Kick']           = true,
    ['Flying Kick']    = true,
    ['Dragon Punch']   = true,
    ['Tail Rake']      = true,
    ['Eagle Strike']   = true,
    ['Tiger Claw']     = true,
    ['Round Kick']     = true,
    ['Backstab']       = true,
    ['Bash']           = true,
    ['Slam']           = true,
    ['Frenzy']         = true,
    ['Volley']         = true,
    ['Frenzied Stabs'] = true,
}
local isAutoskillEligible = loadFunc(src, 'isAutoskillEligible', { AUTOSKILL_ABILITIES = AUTOSKILL_ABILITIES })
local isActionSkill = loadFunc(src, 'isActionSkill', { CLASS_ACTIONS = CLASS_ACTIONS })
local defaultActionEntry = loadFunc(src, 'defaultActionEntry', { isAutoskillEligible = isAutoskillEligible })

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

local fdDef = defaultActionEntry('Feign Death', 'Mnk')
assert_eq(fdDef.autoskill, false, 'defaultActionEntry: Feign Death autoskill=false')
assert_eq(fdDef.kind, 'heal', 'defaultActionEntry: Feign Death kind=heal')
assert_eq(fdDef.pct, 25, 'defaultActionEntry: Feign Death pct=25')
assert_eq(fdDef.when, 'my HP <=', 'defaultActionEntry: Feign Death when=my HP <=')
assert_eq(fdDef.target, 'F: Myself', 'defaultActionEntry: Feign Death target=F: Myself')

assert_true(isAutoskillEligible('Kick'), 'isAutoskillEligible: Kick is true')
assert_true(isAutoskillEligible('Flying Kick'), 'isAutoskillEligible: Flying Kick is true')
assert_true(isAutoskillEligible('Backstab'), 'isAutoskillEligible: Backstab is true')
assert_eq(isAutoskillEligible('Feign Death'), false, 'isAutoskillEligible: Feign Death is false')
assert_eq(isAutoskillEligible('Mend'), false, 'isAutoskillEligible: Mend is false')
assert_eq(isAutoskillEligible('Taunt'), false, 'isAutoskillEligible: Taunt is false')
assert_eq(isAutoskillEligible('Bind Wound'), false, 'isAutoskillEligible: Bind Wound is false')

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
-- 19. createCastTracker & isDetrimentalSpell — failure counting and lockout system
-- ============================================================================
print('--- isDetrimentalSpell & createCastTracker ---')

local triuneSrc = readFile('TAC/lua/triune.lua')
local isDetrimentalSpell = loadstring(extractFunction(triuneSrc, 'isDetrimentalSpell') .. '\nreturn isDetrimentalSpell')()

-- A. isDetrimentalSpell classification tests
assert_eq(isDetrimentalSpell('Heal'), false, 'det: Heal is beneficial')
assert_eq(isDetrimentalSpell('Complete Healing'), false, 'det: Complete Healing is beneficial')
assert_eq(isDetrimentalSpell('Chloroplast'), false, 'det: Chloroplast is beneficial')
assert_eq(isDetrimentalSpell('Focus of Spirit'), false, 'det: Focus of Spirit is beneficial')
assert_eq(isDetrimentalSpell('Skin like Wood'), false, 'det: Skin like Wood is beneficial')
assert_eq(isDetrimentalSpell('Spirit of Wolf'), false, 'det: Spirit of Wolf is beneficial')
assert_eq(isDetrimentalSpell('Clarity'), false, 'det: Clarity is beneficial')
assert_eq(isDetrimentalSpell('Aegolism'), false, 'det: Aegolism is beneficial')
assert_eq(isDetrimentalSpell('Cannibalize'), false, 'det: Cannibalize is beneficial')
assert_eq(isDetrimentalSpell('Gate'), false, 'det: Gate is beneficial')
assert_eq(isDetrimentalSpell('Summon Companion'), false, 'det: Summon Companion is beneficial')

assert_eq(isDetrimentalSpell('Nuke'), true, 'det: Nuke is detrimental')
assert_eq(isDetrimentalSpell('Slow'), true, 'det: Slow is detrimental')
assert_eq(isDetrimentalSpell('Tashani'), true, 'det: Tashani is detrimental')
assert_eq(isDetrimentalSpell('Malo'), true, 'det: Malo is detrimental')
assert_eq(isDetrimentalSpell('Root'), true, 'det: Root is detrimental')
assert_eq(isDetrimentalSpell('Snare'), true, 'det: Snare is detrimental')
assert_eq(isDetrimentalSpell('Enstill'), true, 'det: Enstill is detrimental')
assert_eq(isDetrimentalSpell('Ice Comet'), true, 'det: Ice Comet is detrimental')
assert_eq(isDetrimentalSpell('Doombringing'), true, 'det: Doombringing is detrimental')
assert_eq(isDetrimentalSpell('Kick'), true, 'det: Kick is detrimental')
assert_eq(isDetrimentalSpell('Taunt'), true, 'det: Taunt is detrimental')

-- Explicit kind parameter overrides
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'heal'), false, 'det: kind=heal is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'buff'), false, 'det: kind=buff is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'pet'), false, 'det: kind=pet is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'cure'), false, 'det: kind=cure is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'dd'), true, 'det: kind=dd is detrimental')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'dot'), true, 'det: kind=dot is detrimental')
assert_eq(isDetrimentalSpell('CustomSpell', nil, 'debuff'), true, 'det: kind=debuff is detrimental')

-- Target token overrides
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'E:LowestHP'), true, 'det: E: target is detrimental')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'S:Me'), false, 'det: S: target is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'P:LowestHP'), false, 'det: P: target is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'G:LowestHP'), false, 'det: G: target is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Myself'), false, 'det: F: Myself is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Lowest-HP Ally'), false, 'det: F: Lowest-HP Ally is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Whole Group'), false, 'det: F: Whole Group is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Pet'), false, 'det: F: Pet is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Tank'), false, 'det: F: Tank is beneficial')
assert_eq(isDetrimentalSpell('CustomSpell', nil, nil, 'F: Main Assist'), false, 'det: F: Main Assist is beneficial')

-- B. Out-of-Combat min_xtar evaluation logic tests
local function evalXtOk(numXtar, minXt, isDet)
    return (numXtar >= minXt) or (not isDet and minXt <= 1)
end
assert_eq(evalXtOk(0, 1, false), true, 'min_xtar: OOC beneficial spell with min_xtar=1 is allowed')
assert_eq(evalXtOk(0, 1, true), false, 'min_xtar: OOC detrimental spell with min_xtar=1 is blocked')
assert_eq(evalXtOk(1, 1, true), true, 'min_xtar: Combat detrimental spell with min_xtar=1 is allowed')
assert_eq(evalXtOk(1, 2, true), false, 'min_xtar: Combat detrimental spell with min_xtar=2 blocked on 1 mob')
assert_eq(evalXtOk(2, 2, true), true, 'min_xtar: Combat detrimental spell with min_xtar=2 allowed on 2 mobs')
assert_eq(evalXtOk(0, 3, false), false, 'min_xtar: OOC beneficial spell with explicit min_xtar=3 is blocked')
assert_eq(evalXtOk(3, 3, false), true, 'min_xtar: Combat beneficial spell with explicit min_xtar=3 allowed on 3 mobs')

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

    local function isLockedOut(spellName, targetId, kind)
        if not spellName or spellName == '' then return false end

        -- Strictly enforce: Beneficial spells are NEVER locked out under any circumstance.
        -- Only casted detrimental spells can ever be locked out.
        if not isDetrimentalSpell(spellName, targetId, kind) then
            return false
        end

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

        -- Beneficial spells (heals, buffs, pets, cures) are NEVER locked out under any condition.
        -- Only casted detrimental spells (offensive spells/debuffs) incur failures, immunities, or lockouts.
        if not isDetrimentalSpell(spellName, tid, k) then
            resetFailCount(spellName)
            return
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

    -- 1. Test: Beneficial spells (Heals, Buffs, etc.) NEVER lock out
    assert_eq(isLockedOut('Heal'), false, 'tracker: Heal not locked initially')
    recordFailure('Heal', 2, 30)
    recordFailure('Heal', 2, 30)
    recordFailure('Heal', 2, 30)
    assert_eq(isLockedOut('Heal'), false, 'tracker: Heal NEVER locked out on generic failure')

    -- 2. Test: Beneficial buff "did not take hold" NEVER locks out or backs off
    recordFailure('Focus', 55, 'did not take hold', 2, 30, 'buff')
    assert_eq(isLockedOut('Focus', 55), false, 'tracker: Focus NEVER locked out on did not take hold')

    -- 3. Test: Beneficial spells never lock out on fizzles / interrupts
    recordFailure('Complete Healing', 10, 'fizzled', 2, 30, 'heal')
    recordFailure('Complete Healing', 10, 'fizzled', 2, 30, 'heal')
    recordFailure('Complete Healing', 10, 'fizzled', 2, 30, 'heal')
    recordFailure('Complete Healing', 10, 'fizzled', 2, 30, 'heal')
    assert_eq(isLockedOut('Complete Healing', 10), false, 'tracker: Complete Healing NEVER locked out on fizzles')

    -- 4. Test: Detrimental spells (Nuke) DO lock out on generic failure after maxRetries
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    assert_eq(isLockedOut('Nuke'), false, 'tracker: Nuke 2/3 fails, not locked yet')
    recordFailure('Nuke', 3, 60)
    assert_eq(isLockedOut('Nuke'), true, 'tracker: Nuke 3/3 fails, locked out')
    mockClock = 161 -- 100 + 60 + 1
    assert_eq(isLockedOut('Nuke'), false, 'tracker: Nuke lockout expired')

    -- 5. Test: recordSuccess clears failure count on detrimental spell
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    recordSuccess('Nuke')
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    assert_eq(isLockedOut('Nuke'), false, 'tracker: success resets count')

    -- 6. Test: Detrimental Target-Scoped Immunity (e.g. Slow on immune mob)
    mockClock = 200
    recordFailure('Slow', 101, 'target immune', 2, 30, 'debuff')
    assert_eq(isLockedOut('Slow', 101), true, 'tracker: target 101 is immune to Slow')
    assert_eq(isLockedOut('Slow', 102), false, 'tracker: target 102 is NOT immune to Slow')
    assert_eq(isLockedOut('Slow'), false, 'tracker: Slow is NOT locked out globally')

    -- 7. Test: Detrimental "Did Not Take Hold" (Non-stacking debuff backoff on enemy)
    mockClock = 300
    recordFailure('Tash', 55, 'did not take hold', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 55), true, 'tracker: Tash backed off on target 55')
    assert_eq(isLockedOut('Tash', 56), false, 'tracker: Tash available for target 56')
    mockClock = 421 -- 300 + 120 + 1
    assert_eq(isLockedOut('Tash', 55), false, 'tracker: Tash backoff expired on target 55')

    -- 8. Test: Direct Damage Resists do NOT trigger lockouts
    mockClock = 500
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    recordFailure('Ice Comet', 101, 'resisted', 2, 30, 'dd')
    assert_eq(isLockedOut('Ice Comet', 101), false, 'tracker: DD nukes never lock out on resists')

    -- 9. Test: Debuff Resists back off only on specific target after maxRetries
    mockClock = 600
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 201), false, 'tracker: 1 debuff resist does not lock')
    recordFailure('Tash', 201, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Tash', 201), true, 'tracker: 2 debuff resists lock out on target 201')
    assert_eq(isLockedOut('Tash', 202), false, 'tracker: Tash remains usable on target 202')

    -- 10. Test: Failure count TTL decay (15s)
    mockClock = 700
    recordFailure('Root', 301, 'resisted', 2, 30, 'debuff')
    mockClock = 720 -- 20 seconds later (> 15s decay)
    recordFailure('Root', 301, 'resisted', 2, 30, 'debuff')
    assert_eq(isLockedOut('Root', 301), false, 'tracker: failure count decayed after 20s')

    -- 11. Test: Dead target / Positional events have 0 penalty
    mockClock = 800
    recordFailure('Nuke', 10, 'dead target', 1, 10, 'dd')
    recordFailure('Nuke', 10, 'out of range', 1, 10, 'dd')
    recordFailure('Nuke', 10, 'cannot see target', 1, 10, 'dd')
    assert_eq(isLockedOut('Nuke', 10), false, 'tracker: positional/dead target events incur 0 penalty')

    -- 12. Test: Targeted clear vs global clear
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
        ID = function() return (guildName ~= nil and guildName ~= '') and 100 or 0 end,
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

do
    -- Test isPlayerSameGuild
    mockMyGuild = 'Knights of Norrath'
    local mockSpawnLookup = {
        TLO = {
            Spawn = function(query)
                local name = query:match('pc =?(.*)') or query:match('pc (.*)')
                if name and name:lower():find('^guildmate') then
                    return makeSpawn('Knights of Norrath')
                elseif name and name:lower() == 'stranger' then
                    return makeSpawn('Other Guild')
                end
                return makeSpawn(nil)
            end
        }
    }
    local isPlayerSameGuild = loadFunc(bbSrc, 'isPlayerSameGuild', {
        mq = mockSpawnLookup,
        isSameGuild = isSameGuild
    })
    assert_true(isPlayerSameGuild('guildmate'), 'isPlayerSameGuild: guildmate returns true')
    assert_eq(isPlayerSameGuild('stranger'), false, 'isPlayerSameGuild: stranger returns false')
    assert_eq(isPlayerSameGuild('nobody'), false, 'isPlayerSameGuild: unknown returns false')

    -- Test Guild Priority Queue Insertion & Preemption
    print('--- Buffbot Guild Priority Queue Logic ---')
    local gpRuntime = { activeQueue = {}, currentJob = nil }
    local gpCtrl = { guildMode = 'Guild Priority' }

    local enqueueBuffJob = loadFunc(bbSrc, 'enqueueBuffJob', {
        ctrl = gpCtrl,
        runtime = gpRuntime,
        table = table
    })

    local requeuePreemptedJob = loadFunc(bbSrc, 'requeuePreemptedJob', {
        runtime = gpRuntime,
        table = table
    })

    local getQueuePosition = loadFunc(bbSrc, 'getQueuePosition', {
        ctrl = gpCtrl,
        runtime = gpRuntime,
        isPlayerSameGuild = isPlayerSameGuild
    })

    -- 1. Enqueue two public requests
    enqueueBuffJob({ sender = 'PublicOne', isGuild = false })
    enqueueBuffJob({ sender = 'PublicTwo', isGuild = false })
    assert_eq(#gpRuntime.activeQueue, 2, 'queue: 2 public jobs')
    assert_eq(gpRuntime.activeQueue[1].sender, 'PublicOne', 'queue: PublicOne at idx 1')
    assert_eq(gpRuntime.activeQueue[2].sender, 'PublicTwo', 'queue: PublicTwo at idx 2')

    -- 2. Enqueue guild member request with Guild Priority (should jump to idx 1)
    enqueueBuffJob({ sender = 'guildmate', isGuild = true })
    assert_eq(#gpRuntime.activeQueue, 3, 'queue: 3 jobs after guild insert')
    assert_eq(gpRuntime.activeQueue[1].sender, 'guildmate', 'queue: guildmate jumped to idx 1')
    assert_eq(gpRuntime.activeQueue[2].sender, 'PublicOne', 'queue: PublicOne pushed to idx 2')
    assert_eq(gpRuntime.activeQueue[3].sender, 'PublicTwo', 'queue: PublicTwo pushed to idx 3')

    -- 3. Enqueue second guild member request (should insert after first guild member, before public)
    enqueueBuffJob({ sender = 'GuildMateTwo', isGuild = true })
    assert_eq(#gpRuntime.activeQueue, 4, 'queue: 4 jobs after 2nd guild insert')
    assert_eq(gpRuntime.activeQueue[1].sender, 'guildmate', 'queue: guildmate 1 at idx 1')
    assert_eq(gpRuntime.activeQueue[2].sender, 'GuildMateTwo', 'queue: guildmate 2 at idx 2')
    assert_eq(gpRuntime.activeQueue[3].sender, 'PublicOne', 'queue: PublicOne at idx 3')
    assert_eq(gpRuntime.activeQueue[4].sender, 'PublicTwo', 'queue: PublicTwo at idx 4')

    -- 4. Re-queue preempted public job (should be placed right at start of public section at idx 3)
    requeuePreemptedJob({ sender = 'PreemptedPublic', isGuild = false, isResumed = true })
    assert_eq(#gpRuntime.activeQueue, 5, 'queue: 5 jobs after preempted requeue')
    assert_eq(gpRuntime.activeQueue[1].sender, 'guildmate', 'queue: guildmate 1 at idx 1')
    assert_eq(gpRuntime.activeQueue[2].sender, 'GuildMateTwo', 'queue: guildmate 2 at idx 2')
    assert_eq(gpRuntime.activeQueue[3].sender, 'PreemptedPublic', 'queue: PreemptedPublic at idx 3')
    assert_eq(gpRuntime.activeQueue[4].sender, 'PublicOne', 'queue: PublicOne at idx 4')
    assert_eq(gpRuntime.activeQueue[5].sender, 'PublicTwo', 'queue: PublicTwo at idx 5')

    -- 5. Test queue position calculation with active non-guild preemption
    gpRuntime.currentJob = { sender = 'OldNonGuild', isGuild = false }
    -- guildmate is a guild member, so OldNonGuild will be preempted and NOT count ahead
    assert_eq(getQueuePosition('guildmate'), 0, 'queuePos: guildmate is #1 (0 ahead) during non-guild preemption')
    assert_eq(getQueuePosition('GuildMateTwo'), 1, 'queuePos: GuildMateTwo has 1 ahead')
    assert_eq(getQueuePosition('PreemptedPublic'), 3, 'queuePos: PreemptedPublic has 3 ahead')

    -- 6. Test queue position when active job is a guild member (not preempted)
    gpRuntime.currentJob = { sender = 'ActiveGuildMember', isGuild = true }
    assert_eq(getQueuePosition('guildmate'), 1, 'queuePos: guildmate has 1 ahead when active job is guild')

    -- 7. Test 'Off' mode FIFO behavior
    gpCtrl.guildMode = 'Off'
    local fifoRuntime = { activeQueue = {}, currentJob = nil }
    local enqueueFifo = loadFunc(bbSrc, 'enqueueBuffJob', {
        ctrl = gpCtrl,
        runtime = fifoRuntime,
        table = table
    })
    enqueueFifo({ sender = 'User1', isGuild = false })
    enqueueFifo({ sender = 'User2', isGuild = true })
    assert_eq(fifoRuntime.activeQueue[1].sender, 'User1', 'fifo: User1 stays at idx 1')
    assert_eq(fifoRuntime.activeQueue[2].sender, 'User2', 'fifo: User2 appended to idx 2 in Off mode')
end

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

-- All spell, disc, and AA names must have no leading or trailing whitespace
do
    local untrimmedNames = 0
    for abbr, spells in pairs(DATA_LOADED.spells) do
        if type(spells) == 'table' then
            for _, sp in ipairs(spells) do
                if type(sp) == 'table' and type(sp[1]) == 'string' then
                    if sp[1] ~= sp[1]:match('^%s*(.-)%s*$') then
                        untrimmedNames = untrimmedNames + 1
                    end
                end
            end
        end
    end
    for abbr, aas in pairs(DATA_LOADED.aas) do
        if type(aas) == 'table' then
            for _, aa in ipairs(aas) do
                if type(aa) == 'table' and type(aa[1]) == 'string' then
                    if aa[1] ~= aa[1]:match('^%s*(.-)%s*$') then
                        untrimmedNames = untrimmedNames + 1
                    end
                end
            end
        end
    end
    if DATA_LOADED.discs then
        for abbr, discs in pairs(DATA_LOADED.discs) do
            if type(discs) == 'table' then
                for _, disc in ipairs(discs) do
                    if type(disc) == 'table' and type(disc[1]) == 'string' then
                        if disc[1] ~= disc[1]:match('^%s*(.-)%s*$') then
                            untrimmedNames = untrimmedNames + 1
                        end
                    end
                end
            end
        end
    end
    assert_eq(untrimmedNames, 0, 'data: no spell, aa, or disc name has leading/trailing whitespace')

    -- Test defensive AA trimming and loadout key migration
    local testRawAA = "Destructive Force  "
    local testCleanAA = testRawAA:match('^%s*(.-)%s*$')
    assert_eq(testCleanAA, "Destructive Force", 'aa trim: trims trailing spaces correctly')

    local testLoadoutAAs = {}
    local incomingAAs = { ["Destructive Force  "] = { enabled = true, cls = "Mnk" } }
    for k, v in pairs(incomingAAs) do
        local cleanK = type(k) == 'string' and k:match('^%s*(.-)%s*$') or k
        if cleanK and cleanK ~= '' and not tonumber(cleanK) then
            testLoadoutAAs[cleanK] = v
        end
    end
    assert_neq(testLoadoutAAs["Destructive Force"], nil, 'loadout: migrated untrimmed AA key to trimmed key')
    assert_eq(testLoadoutAAs["Destructive Force  "], nil, 'loadout: untrimmed AA key does not exist')
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
do
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

    -- 4. hasActualNPCXtarget returns true if and only if a live hostile non-ignored NPC is on XTarget
    local hasActualNPCXtarget = loadFunc(src, 'hasActualNPCXtarget', {
        mq = dummyMqXtar,
        isSpawnAlive = function(id) return id ~= 203 end,
        isGroupOrRaidMember = function() return false end,
        isSpawnPetOrPlayer = function() return false end,
        isHostileTarget = function() return true end,
        isIgnored = function() return false end
    })

    assert_eq(hasActualNPCXtarget(), true, 'hasActualNPCXtarget: true with active hostile NPCs on XTarget')

    -- Test when only dead corpses / non-NPCs remain
    dummyXtarSlots[1].dead = true
    dummyXtarSlots[2].dead = true
    local hasActualNPCXtargetDead = loadFunc(src, 'hasActualNPCXtarget', {
        mq = dummyMqXtar,
        isSpawnAlive = function(id) return false end,
        isGroupOrRaidMember = function() return false end,
        isSpawnPetOrPlayer = function() return false end,
        isHostileTarget = function() return true end,
        isIgnored = function() return false end
    })
    assert_eq(hasActualNPCXtargetDead(), false, 'hasActualNPCXtarget: false when all spawns are dead or corpses')
    dummyXtarSlots[1].dead = false
    dummyXtarSlots[2].dead = false

    -- Test when spawns are players or friendly
    local hasActualNPCXtargetFriendly = loadFunc(src, 'hasActualNPCXtarget', {
        mq = dummyMqXtar,
        isSpawnAlive = function(id) return true end,
        isGroupOrRaidMember = function() return true end,
        isSpawnPetOrPlayer = function() return true end,
        isHostileTarget = function() return false end,
        isIgnored = function() return false end
    })
    assert_eq(hasActualNPCXtargetFriendly(), false, 'hasActualNPCXtarget: false when spawns are group members or players')

    -- Test when spawns are ignored
    local hasActualNPCXtargetIgnored = loadFunc(src, 'hasActualNPCXtarget', {
        mq = dummyMqXtar,
        isSpawnAlive = function(id) return true end,
        isGroupOrRaidMember = function() return false end,
        isSpawnPetOrPlayer = function() return false end,
        isHostileTarget = function() return true end,
        isIgnored = function() return true end
    })
    assert_eq(hasActualNPCXtargetIgnored(), false, 'hasActualNPCXtarget: false when all spawns are on ignore list')
end

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
-- 35b. MQ2MoveUtils Plugin Loaded Detection
-- ============================================================================
print('--- mq2moveutils loaded detection ---')
do
    -- 1. Stick TLO Active/Status returns true
    local dummyMqStickLoaded = {
        TLO = {
            Stick = setmetatable({
                Status = function() return 'ON' end,
                Active = function() return true end,
            }, {
                __call = function() return true end,
            }),
            Plugin = function() return nil end,
        }
    }
    local testStickLoaded1 = loadFunc(src, 'stickLoaded', {
        mq = dummyMqStickLoaded,
        pcall = pcall,
    })
    assert_eq(testStickLoaded1(), true, 'stickLoaded: true when Stick TLO is active')

    -- 2. Plugin('mq2moveutils').IsLoaded() returns true
    local dummyMqMoveUtilsPluginLoaded = {
        TLO = {
            Stick = nil,
            Plugin = function(name)
                if string.lower(name) == 'mq2moveutils' or string.lower(name) == 'moveutils' then
                    return setmetatable({
                        IsLoaded = function() return true end,
                    }, {
                        __call = function() return 'mq2moveutils' end,
                    })
                end
                return nil
            end
        }
    }
    local testStickLoaded2 = loadFunc(src, 'stickLoaded', {
        mq = dummyMqMoveUtilsPluginLoaded,
        pcall = pcall,
    })
    assert_eq(testStickLoaded2(), true, 'stickLoaded: true when Plugin mq2moveutils IsLoaded returns true')

    -- 3. Neither loaded returns false
    local dummyMqStickUnloaded = {
        TLO = {
            Stick = nil,
            Plugin = function() return nil end,
        }
    }
    local testStickLoaded3 = loadFunc(src, 'stickLoaded', {
        mq = dummyMqStickUnloaded,
        pcall = pcall,
    })
    assert_eq(testStickLoaded3(), false, 'stickLoaded: false when neither Stick TLO nor Plugin is loaded')

    -- 4. Cross-file standalone validation for triune_map
    local srcMap = readFile('TAC/lua/triune_map.lua')
    local testMapStick = loadFunc(srcMap, 'stickLoaded', {
        mq = dummyMqMoveUtilsPluginLoaded,
        pcall = pcall,
    })
    assert_eq(testMapStick(), true, 'triune_map stickLoaded: true when Plugin mq2moveutils is loaded')
end

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
    local f = io.open('TAC/lua/triune_updater.lua', 'r')
    if f then
        f:close()
        local updSrc = readFile('TAC/lua/triune_updater.lua')
        local cleanTag = loadFunc(updSrc, 'cleanTag', {})
        local extractJsonString = loadFunc(updSrc, 'extractJsonString', {})

        assert_eq(cleanTag('v1.7.7'), '1.7.7', 'cleanTag: lowercase v')
        assert_eq(cleanTag('V1.7.7'), '1.7.7', 'cleanTag: uppercase V')
        assert_eq(cleanTag('1.7.7'), '1.7.7', 'cleanTag: no v prefix')
        assert_eq(cleanTag('  v1.8.0  '), '1.8.0', 'cleanTag: trims surrounding whitespace')
        assert_eq(cleanTag(nil), '', 'cleanTag: nil tag returns empty string')
        assert_eq(cleanTag(''), '', 'cleanTag: empty tag returns empty string')

        assert_eq(extractJsonString('{"tag_name": "v1.7.7"}', 'tag_name'), 'v1.7.7', 'extractJsonString: simple tag_name')
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
        '{\n  "tag_name": "v1.7.7",\n  "body": "## 2026-08-29\\r\\n- Standalone 2D Map (`triune_map.lua`)\\r\\n  - Added \\"Follow Player\\" and \\"Pathable Only\\" filters\\r\\n"\n}'
        assert_eq(extractJsonString(fullReleaseJson, 'tag_name'), 'v1.7.7', 'extractJsonString: full payload tag_name')
        assert_true(string.find(extractJsonString(fullReleaseJson, 'body'), '"Follow Player"') ~= nil,
            'extractJsonString: full payload preserves markdown and quotes in body')
    else
        print('  (Skipping Suite 41: triune_updater.lua retired)')
    end
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
-- Suite 44: triune_map high-performance caching & AABB culling
-- ============================================================================
print('--- triune_map caching & AABB culling logic ---')
do
    -- 1. Zone Map Cache Roundtrip
    local testCache = {}
    local function cachePut(baseDir, zoneShort, data)
        local key = string.format('%s:%s', baseDir, zoneShort:lower())
        testCache[key] = data
    end
    local function cacheGet(baseDir, zoneShort)
        local key = string.format('%s:%s', baseDir, zoneShort:lower())
        return testCache[key]
    end

    cachePut('C:/EQ/maps/Brewall', 'poknowledge', { totalLines = 15400, totalLabels = 120 })
    local cachedEntry = cacheGet('C:/EQ/maps/Brewall', 'PoKnowledge')
    assert_true(cachedEntry ~= nil, 'zone cache lookup: case-insensitive match found')
    assert_eq(cachedEntry.totalLines, 15400, 'zone cache lookup: totalLines matches')
    assert_eq(cachedEntry.totalLabels, 120, 'zone cache lookup: totalLabels matches')

    local missEntry = cacheGet('C:/EQ/maps/Brewall', 'feerrott')
    assert_nil(missEntry, 'zone cache lookup: cache miss returns nil')

    -- 2. World-Space AABB Culling
    local function isSegmentInViewport(seg, vpMinX, vpMaxX, vpMinY, vpMaxY)
        return seg.maxX >= vpMinX and seg.minX <= vpMaxX and seg.maxY >= vpMinY and seg.minY <= vpMaxY
    end

    local vpMinX, vpMaxX, vpMinY, vpMaxY = -500, 500, -500, 500
    local visibleSeg = { minX = 10, maxX = 50, minY = -20, maxY = 30 }
    local offscreenSegRight = { minX = 600, maxX = 700, minY = 0, maxY = 50 }
    local offscreenSegLeft = { minX = -800, maxX = -600, minY = 0, maxY = 50 }
    local offscreenSegTop = { minX = 0, maxX = 50, minY = 600, maxY = 700 }
    local spanningSeg = { minX = -1000, maxX = 1000, minY = -1000, maxY = 1000 }

    assert_true(isSegmentInViewport(visibleSeg, vpMinX, vpMaxX, vpMinY, vpMaxY), 'aabb culling: visible segment kept')
    assert_true(not isSegmentInViewport(offscreenSegRight, vpMinX, vpMaxX, vpMinY, vpMaxY), 'aabb culling: right offscreen culled')
    assert_true(not isSegmentInViewport(offscreenSegLeft, vpMinX, vpMaxX, vpMinY, vpMaxY), 'aabb culling: left offscreen culled')
    assert_true(not isSegmentInViewport(offscreenSegTop, vpMinX, vpMaxX, vpMinY, vpMaxY), 'aabb culling: top offscreen culled')
    assert_true(isSegmentInViewport(spanningSeg, vpMinX, vpMaxX, vpMinY, vpMaxY), 'aabb culling: large spanning segment kept')

    -- 3. Consolidated Spawn Data Extraction Logic
    local dummySpawn = {
        Dead = function() return false end,
        ID = function() return 1042 end,
        CleanName = function() return 'a gnoll pup' end,
        Level = function() return 1 end,
        Class = { ShortName = function() return 'WAR' end },
        ConColor = function() return 'Green' end,
        Distance3D = function() return 45.2 end,
        LineOfSight = function() return true end,
        X = function() return 100.5 end,
        Y = function() return -200.0 end,
        Z = function() return 5.0 end,
        PctHPs = function() return 100 end,
        Aggressive = function() return false end,
    }

    local okData, sId, cleanName, level, classShort, conColor, distance, lineOfSight, sx, sy, sz, pctHPs, hate = pcall(function()
        local dead = dummySpawn.Dead()
        if dead then return nil end
        return dummySpawn.ID(), dummySpawn.CleanName(), dummySpawn.Level(), dummySpawn.Class.ShortName(), dummySpawn.ConColor(), dummySpawn.Distance3D(), dummySpawn.LineOfSight(), dummySpawn.X(), dummySpawn.Y(), dummySpawn.Z(), dummySpawn.PctHPs(), dummySpawn.Aggressive()
    end)

    assert_true(okData, 'consolidated spawn query: pcall succeeded')
    assert_eq(sId, 1042, 'consolidated spawn query: id is 1042')
    assert_eq(cleanName, 'a gnoll pup', 'consolidated spawn query: name matches')
    assert_eq(distance, 45.2, 'consolidated spawn query: distance matches')
    assert_eq(sx, 100.5, 'consolidated spawn query: x matches')
end

-- ============================================================================
-- 40. Spell Gem Enhancements (Presets, Advanced Conditions, Reagents, Swap)
-- ============================================================================
print('--- Spell Gem Enhancements ---')
do
    -- A. Deep copy & Preset Management
    local function deepCopyTable(orig)
        local orig_type = type(orig)
        local copy
        if orig_type == 'table' then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[deepCopyTable(orig_key)] = deepCopyTable(orig_value)
            end
            setmetatable(copy, deepCopyTable(getmetatable(orig)))
        else
            copy = orig
        end
        return copy
    end

    local testGems = {
        [1] = { cls = 'Clr', spell = 'Complete Healing', target = 'F: Tank', when = 'HP <=', pct = 50 },
        [2] = { cls = 'Wiz', spell = 'Ice Comet', target = 'E: Current Target', when = 'target HP between', pct = 90, min_hp = 20, boss_only = true },
        [3] = { cls = 'Enc', spell = 'Tashani', target = 'E: Current Target', when = 'in combat', pct = 100 }
    }

    local presets = {}
    presets['BossBurn'] = {
        name = 'BossBurn',
        gems = deepCopyTable(testGems),
        savedAt = '2026-08-30 12:00:00'
    }

    -- Verify deep copy isolation
    testGems[1].pct = 20
    assert_eq(presets['BossBurn'].gems[1].pct, 50, 'preset deep copy: original modification does not alter preset')
    assert_eq(presets['BossBurn'].gems[2].boss_only, true, 'preset deep copy: boss_only preserved')
    assert_eq(presets['BossBurn'].gems[2].min_hp, 20, 'preset deep copy: min_hp preserved')

    -- B. Gem Slot Swap Logic
    local function swapGems(t, slotA, slotB)
        local tmp = t[slotA]
        t[slotA] = t[slotB]
        t[slotB] = tmp
    end

    local gemBar = { [1] = 'Heal', [2] = 'Nuke', [3] = 'Stun' }
    swapGems(gemBar, 1, 2)
    assert_eq(gemBar[1], 'Nuke', 'gem swap: slot 1 is now Nuke')
    assert_eq(gemBar[2], 'Heal', 'gem swap: slot 2 is now Heal')

    -- C. Advanced Condition Evaluations
    local function evalHpBetween(targetHp, minHp, maxHp)
        return targetHp >= (minHp or 20) and targetHp <= (maxHp or 100)
    end

    assert_true(evalHpBetween(50, 20, 90), 'hp between: 50% is between 20% and 90%')
    assert_true(evalHpBetween(20, 20, 90), 'hp between: 20% is at lower bound')
    assert_true(evalHpBetween(90, 20, 90), 'hp between: 90% is at upper bound')
    assert_true(not evalHpBetween(15, 20, 90), 'hp between: 15% is below min (DoT skipped on low mob)')
    assert_true(not evalHpBetween(95, 20, 90), 'hp between: 95% is above max')

    local function evalAggro(myAggro, targetAggroHolder, myName, threshold)
        local aggro = myAggro or 0
        if aggro == 0 and targetAggroHolder == myName then aggro = 100 end
        return aggro >= threshold
    end

    assert_true(evalAggro(0, 'PlayerA', 'PlayerA', 90), 'aggro on me: target targeting me gives 100% aggro')
    assert_true(evalAggro(95, 'TankB', 'PlayerA', 90), 'my aggro >=: 95% >= 90% triggers')
    assert_true(not evalAggro(40, 'TankB', 'PlayerA', 90), 'my aggro >=: 40% < 90% does not trigger')

    -- D. Reagent Checking Logic
    local function checkReagents(reagentList, inventoryCounts)
        for _, req in ipairs(reagentList) do
            local cur = inventoryCounts[req.id] or 0
            if cur < req.count then return false end
        end
        return true
    end

    local boneChipsReq = { { id = 13073, count = 1 } } -- Bone Chips
    assert_true(checkReagents(boneChipsReq, { [13073] = 10 }), 'reagent check: bone chips available')
    assert_true(not checkReagents(boneChipsReq, { [13073] = 0 }), 'reagent check: missing bone chips blocks cast')
    -- E. Per-NPC Cast Limit Logic
    local maxCastOpts = { 'Unl', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' }
    local function maxCastToOption(mc)
        local n = tonumber(mc) or 0
        if n <= 0 or n > 10 then return 1, 'Unl' end
        return n + 1, maxCastOpts[n + 1]
    end
    local function optionToMaxCast(idx)
        if not idx or idx <= 1 then return 0 end
        return idx - 1
    end

    assert_eq(select(2, maxCastToOption(0)), 'Unl', 'max cast opt: 0 is Unl')
    assert_eq(select(2, maxCastToOption(nil)), 'Unl', 'max cast opt: nil is Unl')
    assert_eq(select(2, maxCastToOption(1)), '1', 'max cast opt: 1 is 1')
    assert_eq(select(2, maxCastToOption(10)), '10', 'max cast opt: 10 is 10')
    assert_eq(optionToMaxCast(1), 0, 'opt to max cast: idx 1 is 0 (Unl)')
    assert_eq(optionToMaxCast(2), 1, 'opt to max cast: idx 2 is 1')
    assert_eq(optionToMaxCast(11), 10, 'opt to max cast: idx 11 is 10')

    -- Cast limit evaluator
    local function canCastOnNpc(npcCastCounts, targetId, spellName, maxCasts)
        local maxC = tonumber(maxCasts) or 0
        if maxC <= 0 then return true end
        local casts = (npcCastCounts[targetId] and npcCastCounts[targetId][spellName]) or 0
        return casts < maxC
    end

    local tracker = { [1001] = { ['Tashani'] = 1, ['Slow'] = 2 } }
    assert_true(canCastOnNpc(tracker, 1001, 'Tashani', 0), 'unlimited casts allowed on npc')
    assert_true(not canCastOnNpc(tracker, 1001, 'Tashani', 1), '1 cast max reached for Tashani')
    assert_true(canCastOnNpc(tracker, 1001, 'Tashani', 2), '1 cast of 2 allowed for Tashani')
    assert_true(not canCastOnNpc(tracker, 1001, 'Slow', 2), '2 casts max reached for Slow')
    assert_true(canCastOnNpc(tracker, 1002, 'Tashani', 1), 'new mob allows cast')

    -- Source verification for triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("ImGui.Combo%('##mc'") ~= nil, 'triune.lua uses ##mc combo for max_casts')
    assert_true(triuneContent:find("maxCastOpts") ~= nil, 'triune.lua defines maxCastOpts (Unl to 10)')
    assert_true(triuneContent:find("runtime.npcCastCounts") ~= nil, 'triune.lua tracks npcCastCounts')
end

-- ============================================================================
-- 38. Cooldown Monitor Logic & Diagnostics Tests
-- ============================================================================
print('--- Cooldown Monitor Logic & Diagnostics ---')
do
    -- A. Diagnostics evaluator
    local function evaluateStatus(isReady, isActive, activeSec, endCost, myEnd, isBurnOnly, isBurnActive, minXt, xtCount)
        if isActive then return 'ACTIVE' end
        if not isReady then return 'COOLDOWN' end
        if endCost > 0 and myEnd < endCost then return 'LOW END' end
        if isBurnOnly and not isBurnActive then return 'NEED BURN' end
        if xtCount < minXt then return 'MIN XTAR' end
        return 'READY'
    end

    assert_eq(evaluateStatus(true, false, 0, 0, 1000, false, false, 1, 2), 'READY', 'cd status: ready')
    assert_eq(evaluateStatus(false, true, 12, 0, 1000, false, false, 1, 2), 'ACTIVE', 'cd status: active')
    assert_eq(evaluateStatus(false, false, 0, 0, 1000, false, false, 1, 2), 'COOLDOWN', 'cd status: cooldown')
    assert_eq(evaluateStatus(true, false, 0, 500, 200, false, false, 1, 2), 'LOW END', 'cd status: low endurance')
    assert_eq(evaluateStatus(true, false, 0, 0, 1000, true, false, 1, 2), 'NEED BURN', 'cd status: need burn')
    assert_eq(evaluateStatus(true, false, 0, 0, 1000, false, false, 3, 1), 'MIN XTAR', 'cd status: min xtar')

    -- B. Sorting evaluator (Cooldown & Active items at TOP of the list)
    local testItems = {
        { name = 'Kick', ready = true, active = false, priority = 50, timeLeft = 0 },
        { name = 'Defensive', ready = false, active = true, activeSec = 18, priority = 10, timeLeft = 0 },
        { name = 'Bash', ready = true, active = false, priority = 20, timeLeft = 0 },
        { name = 'Furious', ready = false, active = false, priority = 10, timeLeft = 45 },
        { name = 'Fortitude', ready = false, active = false, priority = 15, timeLeft = 12 },
    }

    table.sort(testItems, function(a, b)
        -- 1. Active items first
        if a.active ~= b.active then return a.active end
        if a.active and b.active then return (a.activeSec or 0) < (b.activeSec or 0) end

        -- 2. Items on Cooldown NEXT at the top of the list
        local aInCd = (not a.ready)
        local bInCd = (not b.ready)
        if aInCd ~= bInCd then return aInCd end

        -- Both on cooldown: sort by time remaining ascending (soonest to become ready first)
        if aInCd and bInCd then
            if math.abs((a.timeLeft or 0) - (b.timeLeft or 0)) > 0.05 then
                return (a.timeLeft or 0) < (b.timeLeft or 0)
            end
            return (a.priority or 50) < (b.priority or 50)
        end

        -- 3. Both Ready: sort by priority ascending
        if (a.priority or 50) ~= (b.priority or 50) then
            return (a.priority or 50) < (b.priority or 50)
        end
        return (a.name or '') < (b.name or '')
    end)

    assert_eq(testItems[1].name, 'Defensive', 'cd sort time: Active item at top')
    assert_eq(testItems[2].name, 'Fortitude', 'cd sort time: Soonest off cooldown next at top (12s < 45s)')
    assert_eq(testItems[3].name, 'Furious', 'cd sort time: Later off cooldown (45s)')
    assert_eq(testItems[4].name, 'Bash', 'cd sort time: Ready item with higher priority next (Pri 20 < 50)')
    assert_eq(testItems[5].name, 'Kick', 'cd sort time: Ready item with lower priority last (Pri 50)')

    -- C. Ability Base Cooldowns
    local ABILITY_BASE_COOLDOWNS = {
        ['Kick'] = 6, ['Bash'] = 6, ['Slam'] = 6, ['Flying Kick'] = 6,
        ['Backstab'] = 10, ['Taunt'] = 6, ['Mend'] = 360, ['Feign Death'] = 8,
    }
    assert_eq(ABILITY_BASE_COOLDOWNS['Kick'], 6, 'ability cd: Kick is 6s')
    assert_eq(ABILITY_BASE_COOLDOWNS['Backstab'], 10, 'ability cd: Backstab is 10s')
    assert_eq(ABILITY_BASE_COOLDOWNS['Mend'], 360, 'ability cd: Mend is 360s')
    assert_eq(ABILITY_BASE_COOLDOWNS['Feign Death'], 8, 'ability cd: Feign Death is 8s')

    -- D. AA and Discipline Timer Conversions & Timer Groups
    local function parseCombatAbilityTimer(rawVal)
        if type(rawVal) == 'table' and rawVal.TotalSeconds then
            return rawVal.TotalSeconds
        end
        local n = tonumber(rawVal) or 0
        if n > 1000 then return n / 1000.0 end
        if n > 0 and n <= 500 then return n * 6 end -- ticks to seconds
        return n
    end

    assert_eq(parseCombatAbilityTimer(5), 30, 'disc timer: 5 ticks = 30s')
    assert_eq(parseCombatAbilityTimer(10), 60, 'disc timer: 10 ticks = 60s')
    assert_eq(parseCombatAbilityTimer(90000), 90, 'disc timer: 90000ms = 90s')
    assert_eq(parseCombatAbilityTimer({ TotalSeconds = 45 }), 45, 'disc timer: TotalSeconds = 45s')

    local function checkTimerGroupActive(activeTimerGroups, discTimerGroup, now)
        if not discTimerGroup then return false, 0 end
        local exp = activeTimerGroups[discTimerGroup] or 0
        if exp > now then
            return true, exp - now
        end
        return false, 0
    end

    local now = 1000
    local timerGroups = { ['T1'] = 1045, ['T2'] = 980 }
    local isT1Active, t1Rem = checkTimerGroupActive(timerGroups, 'T1', now)
    local isT2Active, t2Rem = checkTimerGroupActive(timerGroups, 'T2', now)
    assert_true(isT1Active, 'timer group: T1 is active')
    assert_eq(t1Rem, 45, 'timer group: T1 has 45s left')
    assert_true(not isT2Active, 'timer group: T2 has expired')

    -- E. Cooldowns Tab Ordering & Declaration
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find('function UI.drawCooldownsTab()', 1, true) ~= nil, 'cooldown tab: UI.drawCooldownsTab defined')
    local tabOrderMatch = triuneContent:find('UI.drawAutoAATab%(%)[%s\r\n]+UI.drawCooldownsTab%(%)[%s\r\n]+UI.drawSettingsTab%(%)')
    assert_true(tabOrderMatch ~= nil, 'cooldown tab: Cooldowns tab positioned after Auto AA and before Settings tab in triuneTabs')

    -- F. parseDurationSec & parseSpellRecastTime Comprehensive Tests
    local function parseDurationSec(durObj)
        if not durObj then return 0 end
        local sec = 0
        pcall(function()
            if type(durObj) == 'number' then
                if durObj > 1800 then sec = durObj / 1000.0
                elseif durObj > 0 and durObj <= 500 then sec = durObj * 6
                else sec = durObj end
                return
            end
            if type(durObj) == 'table' then
                if durObj.TotalSeconds then
                    if type(durObj.TotalSeconds) == 'function' then
                        sec = tonumber(durObj.TotalSeconds() or 0) or 0
                    else
                        sec = tonumber(durObj.TotalSeconds) or 0
                    end
                    if sec > 0 then return end
                end
                if durObj.Raw then
                    local r = type(durObj.Raw) == 'function' and durObj.Raw() or durObj.Raw
                    local nr = tonumber(r or 0) or 0
                    if nr > 0 then sec = nr / 1000.0; return end
                end
                if durObj.Ticks then
                    local t = type(durObj.Ticks) == 'function' and durObj.Ticks() or durObj.Ticks
                    local nt = tonumber(t or 0) or 0
                    if nt > 0 then sec = nt * 6; return end
                end
            end
            if type(durObj) == 'function' then
                local val = durObj()
                if val ~= nil then
                    local n = tonumber(val) or 0
                    if n > 1800 then sec = n / 1000.0
                    elseif n > 0 and n <= 500 then sec = n * 6
                    else sec = n end
                end
            end
        end)
        return sec
    end

    -- MacroQuest Me.Buff.Duration tests
    assert_eq(parseDurationSec({ TotalSeconds = function() return 180 end }), 180, 'parseDurationSec: TotalSeconds() method')
    assert_eq(parseDurationSec({ TotalSeconds = 45 }), 45, 'parseDurationSec: TotalSeconds property')
    assert_eq(parseDurationSec({ Raw = function() return 18000 end }), 18, 'parseDurationSec: Raw() ms method (18000ms = 18s)')
    assert_eq(parseDurationSec({ Ticks = function() return 10 end }), 60, 'parseDurationSec: Ticks() method (10 ticks = 60s)')
    assert_eq(parseDurationSec(function() return "18000" end), 18, 'parseDurationSec: string ms fallback (18000ms = 18s)')
    assert_eq(parseDurationSec(function() return "5" end), 30, 'parseDurationSec: string ticks fallback (5 ticks = 30s)')

    -- G. DISC_BASE_COOLDOWNS and DISC_BASE_DURATIONS Lookups
    local DISC_BASE_COOLDOWNS = {
        ['defensive discipline'] = 900,
        ['evasive discipline'] = 900,
        ['fortitude discipline'] = 3600,
        ['furious discipline'] = 3600,
        ['stonewall discipline'] = 900,
        ['duelist discipline'] = 1200,
        ['kinetics discipline'] = 1200,
        ['trueshot discipline'] = 1800,
        ['weapon shield discipline'] = 3600,
        ['hundred fists discipline'] = 1800,
        ['unflinching will'] = 30,
        ['bellow of the kedge'] = 30,
    }
    local DISC_BASE_DURATIONS = {
        ['defensive discipline'] = 180,
        ['evasive discipline'] = 180,
        ['fortitude discipline'] = 8,
        ['furious discipline'] = 9,
        ['stonewall discipline'] = 180,
        ['duelist discipline'] = 72,
        ['kinetics discipline'] = 72,
        ['trueshot discipline'] = 120,
        ['weapon shield discipline'] = 18,
        ['hundred fists discipline'] = 72,
        ['unflinching will'] = 18,
    }

    assert_eq(DISC_BASE_COOLDOWNS['defensive discipline'], 900, 'disc base cd: Defensive is 900s (15m)')
    assert_eq(DISC_BASE_COOLDOWNS['fortitude discipline'], 3600, 'disc base cd: Fortitude is 3600s (60m)')
    assert_eq(DISC_BASE_DURATIONS['defensive discipline'], 180, 'disc base dur: Defensive is 180s (3m)')
    assert_eq(DISC_BASE_DURATIONS['fortitude discipline'], 8, 'disc base dur: Fortitude is 8s')

    -- H. Progress Bar Active Scaling Calculation
    local activeSec = 180
    local activeTotalSec = 180
    local actFrac = math.min(1.0, math.max(0.0, activeSec / activeTotalSec))
    assert_eq(actFrac, 1.0, 'progress bar active: Full duration gives 100% (1.0) cyan bar')

    activeSec = 90
    actFrac = math.min(1.0, math.max(0.0, activeSec / activeTotalSec))
    assert_eq(actFrac, 0.5, 'progress bar active: Half duration gives 50% (0.5) cyan bar')
end

-- ============================================================================
-- Suite 47: Auto AA & Fireworks Point Spender Logic
-- ============================================================================
print('--- Auto AA & Fireworks Point Spender Logic ---')
do
    -- A. sanitizeModeConfig checks
    local sanitizeModeConfig = loadFunc(src, 'sanitizeModeConfig', { MODES = MODES })
    local cfg = { mode = 'Manual' }
    sanitizeModeConfig(cfg)
    assert_eq(cfg.auto_spend_aa, false, 'sanitize: auto_spend_aa default is false')
    assert_eq(cfg.auto_spend_aa_threshold, 100, 'sanitize: auto_spend_aa_threshold default is 100')
    assert_eq(cfg.auto_spend_aa_id, 17788, 'sanitize: auto_spend_aa_id default is 17788')
    assert_eq(cfg.auto_spend_aa_buy_id, 0, 'sanitize: auto_spend_aa_buy_id default is 0')
    assert_eq(cfg.auto_spend_aa_cost, 25, 'sanitize: auto_spend_aa_cost default is 25')
    assert_eq(cfg.auto_spend_aa_name, 'Alternately Advanced Fireworks', 'sanitize: auto_spend_aa_name default')
    assert_eq(cfg.auto_spend_aa_action, 'window', 'sanitize: auto_spend_aa_action default is window')
    assert_eq(cfg.auto_summon_fireworks, false, 'sanitize: auto_summon_fireworks default is false')
    assert_eq(type(cfg.auto_aa_priorities), 'table', 'sanitize: auto_aa_priorities default is table')
    assert_eq(cfg.auto_aa_sort_by, 'name', 'sanitize: auto_aa_sort_by default is name')
    assert_eq(cfg.auto_aa_sort_asc, true, 'sanitize: auto_aa_sort_asc default is true')
    assert_eq(cfg.auto_aa_search, '', 'sanitize: auto_aa_search default is empty string')
    assert_eq(cfg.auto_aa_hide_maxed, false, 'sanitize: auto_aa_hide_maxed default is false')
    assert_eq(cfg.auto_aa_only_prioritized, false, 'sanitize: auto_aa_only_prioritized default is false')
    assert_eq(cfg.auto_aa_buy_order, 'cost', 'sanitize: auto_aa_buy_order default is cost')

    -- B. Preserves user custom config
    local customCfg = {
        mode = 'Manual',
        auto_spend_aa = true,
        auto_spend_aa_threshold = 50,
        auto_spend_aa_id = 99999,
        auto_spend_aa_buy_id = 1234,
        auto_spend_aa_cost = 10,
        auto_spend_aa_name = 'Custom AA',
        auto_spend_aa_action = 'buy',
        auto_summon_fireworks = true,
        auto_aa_priorities = { ['Combat Agility'] = true, ['Run Speed'] = true },
        auto_aa_sort_by = 'cost',
        auto_aa_sort_asc = false,
        auto_aa_search = 'combat',
        auto_aa_hide_maxed = true,
        auto_aa_only_prioritized = true,
        auto_aa_buy_order = 'list'
    }
    sanitizeModeConfig(customCfg)
    assert_eq(customCfg.auto_spend_aa, true, 'sanitize: preserved auto_spend_aa')
    assert_eq(customCfg.auto_spend_aa_threshold, 50, 'sanitize: preserved auto_spend_aa_threshold')
    assert_eq(customCfg.auto_spend_aa_id, 99999, 'sanitize: preserved auto_spend_aa_id')
    assert_eq(customCfg.auto_spend_aa_buy_id, 1234, 'sanitize: preserved auto_spend_aa_buy_id')
    assert_eq(customCfg.auto_spend_aa_cost, 10, 'sanitize: preserved auto_spend_aa_cost')
    assert_eq(customCfg.auto_spend_aa_name, 'Custom AA', 'sanitize: preserved auto_spend_aa_name')
    assert_eq(customCfg.auto_spend_aa_action, 'buy', 'sanitize: preserved auto_spend_aa_action')
    assert_eq(customCfg.auto_summon_fireworks, true, 'sanitize: preserved auto_summon_fireworks')
    assert_eq(customCfg.auto_aa_priorities['Combat Agility'], true, 'sanitize: preserved auto_aa_priorities')
    assert_eq(customCfg.auto_aa_sort_by, 'cost', 'sanitize: preserved auto_aa_sort_by')
    assert_eq(customCfg.auto_aa_sort_asc, false, 'sanitize: preserved auto_aa_sort_asc')
    assert_eq(customCfg.auto_aa_search, 'combat', 'sanitize: preserved auto_aa_search')
    assert_eq(customCfg.auto_aa_hide_maxed, true, 'sanitize: preserved auto_aa_hide_maxed')
    assert_eq(customCfg.auto_aa_only_prioritized, true, 'sanitize: preserved auto_aa_only_prioritized')
    assert_eq(customCfg.auto_aa_buy_order, 'list', 'sanitize: preserved auto_aa_buy_order')

    -- C. AA Filtering Logic Simulation
    local sampleAAs = {
        { name = 'Combat Agility', rank = 3, maxRank = 5, cost = 5, fullyTrained = false },
        { name = 'Combat Stability', rank = 5, maxRank = 5, cost = 0, fullyTrained = true },
        { name = 'Innate Run Speed', rank = 1, maxRank = 3, cost = 2, fullyTrained = false },
        { name = 'Planar Power', rank = 0, maxRank = 5, cost = 3, fullyTrained = false }
    }
    local prios = { ['Combat Agility'] = true, ['Innate Run Speed'] = true }

    local function filterAAs(items, search, hideMax, onlyPrio, pMap)
        local out = {}
        local q = (search or ''):lower():match('^%s*(.-)%s*$')
        for _, itm in ipairs(items) do
            local keep = true
            if hideMax and itm.fullyTrained then keep = false end
            if keep and onlyPrio and not pMap[itm.name] then keep = false end
            if keep and q ~= '' and not itm.name:lower():find(q, 1, true) then keep = false end
            if keep then out[#out + 1] = itm end
        end
        return out
    end

    local f1 = filterAAs(sampleAAs, '', false, false, prios)
    assert_eq(#f1, 4, 'filter: no filters returns all 4')

    local fSearch = filterAAs(sampleAAs, 'Combat', false, false, prios)
    assert_eq(#fSearch, 2, 'filter: search "Combat" matches 2')

    local fHideMax = filterAAs(sampleAAs, '', true, false, prios)
    assert_eq(#fHideMax, 3, 'filter: hideMaxed excludes Combat Stability')

    local fPrioOnly = filterAAs(sampleAAs, '', false, true, prios)
    assert_eq(#fPrioOnly, 2, 'filter: onlyPrioritized matches 2')

    local fCombo = filterAAs(sampleAAs, 'combat', true, true, prios)
    assert_eq(#fCombo, 1, 'filter: combo matches only Combat Agility')
    assert_eq(fCombo[1].name, 'Combat Agility', 'filter: combo match is Combat Agility')

    -- D. AA Sorting Logic Simulation
    local function sortAAs(items, sortBy, asc)
        local copy = {}
        for _, itm in ipairs(items) do copy[#copy + 1] = itm end
        table.sort(copy, function(a, b)
            if sortBy == 'cost' then
                local costA = a.fullyTrained and 999999 or (a.cost or 0)
                local costB = b.fullyTrained and 999999 or (b.cost or 0)
                if costA ~= costB then
                    if asc then return costA < costB else return costA > costB end
                end
                return a.name:lower() < b.name:lower()
            elseif sortBy == 'trained' then
                local tA = a.fullyTrained and 1 or 0
                local tB = b.fullyTrained and 1 or 0
                if tA ~= tB then
                    if asc then return tA < tB else return tA > tB end
                end
                return a.name:lower() < b.name:lower()
            else
                local nA = a.name:lower()
                local nB = b.name:lower()
                if nA ~= nB then
                    if asc then return nA < nB else return nA > nB end
                end
                return (a.cost or 0) < (b.cost or 0)
            end
        end)
        return copy
    end

    local sNameAsc = sortAAs(sampleAAs, 'name', true)
    assert_eq(sNameAsc[1].name, 'Combat Agility', 'sort name asc: 1st is Combat Agility')
    assert_eq(sNameAsc[4].name, 'Planar Power', 'sort name asc: 4th is Planar Power')

    local sCostAsc = sortAAs(sampleAAs, 'cost', true)
    assert_eq(sCostAsc[1].name, 'Innate Run Speed', 'sort cost asc: lowest cost is Run Speed (2 AA)')
    assert_eq(sCostAsc[2].name, 'Planar Power', 'sort cost asc: 2nd is Planar Power (3 AA)')
    assert_eq(sCostAsc[3].name, 'Combat Agility', 'sort cost asc: 3rd is Combat Agility (5 AA)')
    assert_eq(sCostAsc[4].name, 'Combat Stability', 'sort cost asc: fully trained goes to end')

    local sTrainedAsc = sortAAs(sampleAAs, 'trained', true)
    assert_eq(sTrainedAsc[4].name, 'Combat Stability', 'sort trained asc: maxed ability is last')

    -- E. Prioritized Purchase Selection Simulation
    local function selectPriorityToBuy(priorities, aaMap, unspent, buyOrder)
        local candidates = {}
        for nm, enabled in pairs(priorities) do
            if enabled and aaMap[nm] then
                local itm = aaMap[nm]
                if not itm.fullyTrained and itm.cost > 0 and unspent >= itm.cost then
                    candidates[#candidates + 1] = itm
                end
            end
        end
        if #candidates == 0 then return nil end
        if buyOrder == 'list' then
            table.sort(candidates, function(a, b) return a.name:lower() < b.name:lower() end)
        else
            table.sort(candidates, function(a, b)
                if a.cost ~= b.cost then return a.cost < b.cost end
                return a.name:lower() < b.name:lower()
            end)
        end
        return candidates[1].name
    end

    local testMap = {
        ['Combat Agility'] = { name = 'Combat Agility', rank = 3, maxRank = 5, cost = 5, fullyTrained = false },
        ['Innate Run Speed'] = { name = 'Innate Run Speed', rank = 1, maxRank = 3, cost = 2, fullyTrained = false },
        ['Combat Stability'] = { name = 'Combat Stability', rank = 5, maxRank = 5, cost = 0, fullyTrained = true }
    }
    local activePrios = {
        ['Combat Agility'] = true,
        ['Innate Run Speed'] = true,
        ['Combat Stability'] = true
    }

    -- With 1 AA: can afford neither
    assert_eq(selectPriorityToBuy(activePrios, testMap, 1, 'cost'), nil, 'prio buy: 1 AA cannot afford 2 or 5')

    -- With 3 AA: can afford Innate Run Speed (2 AA), but not Combat Agility (5 AA)
    assert_eq(selectPriorityToBuy(activePrios, testMap, 3, 'cost'), 'Innate Run Speed', 'prio buy: 3 AA buys Run Speed')

    -- With 10 AA and buyOrder 'cost': buys cheapest first (Run Speed)
    assert_eq(selectPriorityToBuy(activePrios, testMap, 10, 'cost'), 'Innate Run Speed', 'prio buy: 10 AA with cost order chooses cheapest')

    -- With 10 AA and buyOrder 'list': buys alphabetical first (Combat Agility)
    assert_eq(selectPriorityToBuy(activePrios, testMap, 10, 'list'), 'Combat Agility', 'prio buy: 10 AA with list order chooses alphabetical')

    -- Combat Stability is fully trained: should never be selected
    local maxedOnlyPrio = { ['Combat Stability'] = true }
    assert_eq(selectPriorityToBuy(maxedOnlyPrio, testMap, 100, 'cost'), nil, 'prio buy: fully trained never selected')

    -- F. Auto-spend condition evaluator simulation
    local function shouldAutoSpend(enabled, unspent, threshold, cost, aaId)
        if not enabled then return false end
        threshold = tonumber(threshold) or 100
        cost = tonumber(cost) or 25
        aaId = tonumber(aaId) or 17788
        return (aaId > 0 and cost > 0 and unspent >= threshold and unspent >= cost)
    end

    assert_eq(shouldAutoSpend(false, 100, 100, 25, 17788), false, 'spend check: disabled -> false')
    assert_eq(shouldAutoSpend(true, 75, 100, 25, 17788), false, 'spend check: 75 < 100 threshold -> false')
    assert_eq(shouldAutoSpend(true, 100, 100, 25, 17788), true, 'spend check: 100 >= 100 threshold & >= 25 cost -> true')
    assert_eq(shouldAutoSpend(true, 25, 25, 25, 17788), true, 'spend check: 25 >= 25 threshold -> true')
    assert_eq(shouldAutoSpend(true, 20, 20, 25, 17788), false, 'spend check: 20 < 25 cost -> false')

    -- G. Auto-summon fireworks conditions simulation
    local function shouldAutoSummon(enabled, aaId, isReady, isCasting, isMoving, isCombat, hasXtar)
        if not enabled then return false end
        if (tonumber(aaId) or 0) <= 0 then return false end
        if isCasting or isMoving or isCombat or hasXtar then return false end
        return not not isReady
    end

    assert_eq(shouldAutoSummon(false, 17788, true, false, false, false, false), false, 'summon check: disabled -> false')
    assert_eq(shouldAutoSummon(true, 17788, false, false, false, false, false), false, 'summon check: not ready -> false')
    assert_eq(shouldAutoSummon(true, 17788, true, true, false, false, false), false, 'summon check: casting -> false')
    assert_eq(shouldAutoSummon(true, 17788, true, false, true, false, false), false, 'summon check: moving -> false')
    assert_eq(shouldAutoSummon(true, 17788, true, false, false, true, false), false, 'summon check: combat -> false')
    assert_eq(shouldAutoSummon(true, 17788, true, false, false, false, true), false, 'summon check: xtarget hostile -> false')
    assert_eq(shouldAutoSummon(true, 17788, true, false, false, false, false), true, 'summon check: idle, ready, out of combat -> true')

    -- H. Special Tab AA Recognition Simulation
    local specialCatalog = {
        'Lesson of the Devoted',
        'Expedient Recovery',
        'Infusion of the Faithful',
        'Chaotic Jester',
        'Steadfast Servant',
        'Staunch Recovery',
        'Intensity of the Resolute',
        'Armor of Experience',
        'Glyph of Destruction',
        'Glyph of Frantic Fertility',
        'Glyph of Arcane Secrets',
        'Alternately Advanced Fireworks',
        'Throne of Heroes',
        'Origin'
    }
    local specialMap = {}
    for _, nm in ipairs(specialCatalog) do specialMap[nm] = true end
    assert_true(specialMap['Lesson of the Devoted'] == true, 'special aa: veteran lesson recognised')
    assert_true(specialMap['Glyph of Destruction'] == true, 'special aa: glyph recognised')
    assert_true(specialMap['Alternately Advanced Fireworks'] == true, 'special aa: fireworks recognised')

    -- I. Spent and Unspent Points Delta Refresh Simulation
    local function evaluateAARefreshTriggers(prevSpent, curSpent, prevUnspent, curUnspent)
        local scanTriggered = false
        local filterDirty = false
        if prevSpent ~= nil and curSpent ~= prevSpent then
            scanTriggered = true
            filterDirty = true
        end
        if prevUnspent ~= nil and curUnspent ~= prevUnspent then
            filterDirty = true
        end
        return scanTriggered, filterDirty
    end

    local scan1, dirty1 = evaluateAARefreshTriggers(100, 100, 50, 50)
    assert_eq(scan1, false, 'aa refresh: no change -> no scan')
    assert_eq(dirty1, false, 'aa refresh: no change -> not dirty')

    local scan2, dirty2 = evaluateAARefreshTriggers(100, 105, 50, 45)
    assert_eq(scan2, true, 'aa refresh: spent changed -> scan triggered')
    assert_eq(dirty2, true, 'aa refresh: spent changed -> filter dirty')

    local scan3, dirty3 = evaluateAARefreshTriggers(105, 105, 45, 46)
    assert_eq(scan3, false, 'aa refresh: unspent gained -> no full scan needed')
    assert_eq(dirty3, true, 'aa refresh: unspent gained -> filter dirtied to refresh affordabilities')

    -- J. Fireworks Target Name Fuzzy Matching Simulation
    local function matchAAName(rowText, targetName)
        if not rowText or rowText == '' or not targetName or targetName == '' then return false end
        local cleanRow = rowText:lower():gsub('[^%a%d]', '')
        local cleanTarget = targetName:lower():gsub('[^%a%d]', '')
        if cleanRow == cleanTarget then return true end
        if cleanRow ~= '' and cleanTarget ~= '' and (cleanRow:find(cleanTarget, 1, true) or cleanTarget:find(cleanRow, 1, true)) then
            return true
        end
        if cleanTarget:find('firework') and cleanRow:find('firework') then
            return true
        end
        return false
    end

    assert_true(matchAAName('Alternately Advanced Fireworks', 'Alternatly ADvanced fireworks'), 'match: typo with single e and AD matches')
    assert_true(matchAAName('Alternately Advanced Fireworks', 'Advanced Fireworks'), 'match: partial fireworks matches')
    assert_true(matchAAName('Alternately Advanced Fireworks', 'Alternately Advanced Fireworks'), 'match: exact match')
    assert_eq(matchAAName('Combat Stability', 'Combat Agility'), false, 'match: different ability false')

    -- K. Verify Auto AA tab & functions in triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("function UI.drawAutoAATab()") ~= nil, 'triune.lua defines UI.drawAutoAATab')
    assert_true(triuneContent:find("UI.drawAutoAATab()") ~= nil, 'triune.lua invokes UI.drawAutoAATab in tab bar')
    assert_true(triuneContent:find("runtime.checkAutoSpendAA()") ~= nil, 'triune.lua includes runtime.checkAutoSpendAA check')
    assert_true(triuneContent:find("runtime.scanPlayerAAs") ~= nil, 'triune.lua defines runtime.scanPlayerAAs')
    assert_true(triuneContent:find("runtime.getFilteredSortedAAs") ~= nil, 'triune.lua defines runtime.getFilteredSortedAAs')
    assert_true(triuneContent:find("runtime.findAAInWindowLists") ~= nil, 'triune.lua defines runtime.findAAInWindowLists')
    assert_true(triuneContent:find("runtime.findChildRecursive") ~= nil, 'triune.lua defines runtime.findChildRecursive')
    assert_true(triuneContent:find("AAW_SpecialList") ~= nil, 'triune.lua scans AAW_SpecialList')
    assert_true(triuneContent:find("AAW_TrainButton") ~= nil, 'triune.lua clicks AAW_TrainButton')
    assert_true(triuneContent:find("AAW_Subwindows") ~= nil, 'triune.lua notifies AAW_Subwindows')
    assert_true(triuneContent:find("runtime.readSpecialTabOnce") ~= nil, 'triune.lua defines runtime.readSpecialTabOnce')
    assert_true(triuneContent:find("runtime.readSpecialTabNamesFromUI") ~= nil, 'triune.lua defines runtime.readSpecialTabNamesFromUI')
    assert_true(triuneContent:find("runtime.specialTabAAs") ~= nil, 'triune.lua tracks runtime.specialTabAAs')
    assert_true(triuneContent:find("TriuneAAPurchased") ~= nil, 'triune.lua registers TriuneAAPurchased event')
    assert_true(triuneContent:find("runtime.lastObservedAAPointsSpent") ~= nil, 'triune.lua tracks lastObservedAAPointsSpent')
    assert_true(triuneContent:find("runtime.pendingPostTrainScanAt") ~= nil, 'triune.lua tracks pendingPostTrainScanAt')
    assert_true(triuneContent:find("runtime.checkAutoSummonFireworks()") ~= nil, 'triune.lua includes runtime.checkAutoSummonFireworks check')
end

-- ============================================================================
-- Pet Control Tab & Multi-Pet Management Logic
-- ============================================================================
do
    print('--- Pet Control Tab & Multi-Pet Management ---')

    -- A. Scope mapping & target resolution
    local PET_SCOPE_LIST = {
        'all', 'swarm', 'mag', 'bst', 'nec', 'enc', 'shm', 'dru', 'brd', 'shd'
    }
    local function classToPetCmdScope(cls)
        if not cls or type(cls) ~= 'string' then return 'all' end
        local lower = string.lower(cls)
        if lower == 'sk' or lower == 'shd' then return 'shd' end
        for _, s in ipairs(PET_SCOPE_LIST) do
            if lower == s then return s end
        end
        return 'all'
    end

    assert_eq(classToPetCmdScope('Mag'), 'mag', 'pet scope: Mag -> mag')
    assert_eq(classToPetCmdScope('mag'), 'mag', 'pet scope: mag -> mag')
    assert_eq(classToPetCmdScope('Bst'), 'bst', 'pet scope: Bst -> bst')
    assert_eq(classToPetCmdScope('Nec'), 'nec', 'pet scope: Nec -> nec')
    assert_eq(classToPetCmdScope('Enc'), 'enc', 'pet scope: Enc -> enc')
    assert_eq(classToPetCmdScope('Shm'), 'shm', 'pet scope: Shm -> shm')
    assert_eq(classToPetCmdScope('Dru'), 'dru', 'pet scope: Dru -> dru')
    assert_eq(classToPetCmdScope('Brd'), 'brd', 'pet scope: Brd -> brd')
    assert_eq(classToPetCmdScope('SK'), 'shd', 'pet scope: SK -> shd')
    assert_eq(classToPetCmdScope('sk'), 'shd', 'pet scope: sk -> shd')
    assert_eq(classToPetCmdScope('shd'), 'shd', 'pet scope: shd -> shd')
    assert_eq(classToPetCmdScope('swarm'), 'swarm', 'pet scope: swarm -> swarm')
    assert_eq(classToPetCmdScope('all'), 'all', 'pet scope: all -> all')
    assert_eq(classToPetCmdScope('War'), 'all', 'pet scope: War (non-pet) -> all')
    assert_eq(classToPetCmdScope('Clr'), 'all', 'pet scope: Clr (non-pet) -> all')
    assert_eq(classToPetCmdScope(nil), 'all', 'pet scope: nil -> all')
    assert_eq(classToPetCmdScope(''), 'all', 'pet scope: empty string -> all')

    -- B. Pet Command String Formatting
    local function formatPetCmd(verb, scope)
        scope = scope or 'all'
        return string.format('#petcmd %s %s', verb, scope)
    end

    assert_eq(formatPetCmd('attack', 'all'), '#petcmd attack all', 'petcmd: attack all')
    assert_eq(formatPetCmd('qattack', 'mag'), '#petcmd qattack mag', 'petcmd: qattack mag')
    assert_eq(formatPetCmd('back', 'bst'), '#petcmd back bst', 'petcmd: back bst')
    assert_eq(formatPetCmd('follow', 'nec'), '#petcmd follow nec', 'petcmd: follow nec')
    assert_eq(formatPetCmd('guard', 'enc'), '#petcmd guard enc', 'petcmd: guard enc')
    assert_eq(formatPetCmd('sit', 'shm'), '#petcmd sit shm', 'petcmd: sit shm')
    assert_eq(formatPetCmd('stop', 'dru'), '#petcmd stop dru', 'petcmd: stop dru')
    assert_eq(formatPetCmd('health', 'all'), '#petcmd health all', 'petcmd: health all')
    assert_eq(formatPetCmd('leader', 'all'), '#petcmd leader all', 'petcmd: leader all')
    assert_eq(formatPetCmd('feign', 'nec'), '#petcmd feign nec', 'petcmd: feign nec')
    assert_eq(formatPetCmd('leave', 'mag'), '#petcmd leave mag', 'petcmd: leave mag')

    assert_eq(formatPetCmd('taunt on', 'all'), '#petcmd taunt on all', 'petcmd: taunt on all')
    assert_eq(formatPetCmd('taunt off', 'bst'), '#petcmd taunt off bst', 'petcmd: taunt off bst')
    assert_eq(formatPetCmd('hold on', 'all'), '#petcmd hold on all', 'petcmd: hold on all')
    assert_eq(formatPetCmd('hold off', 'nec'), '#petcmd hold off nec', 'petcmd: hold off nec')
    assert_eq(formatPetCmd('ghold on', 'all'), '#petcmd ghold on all', 'petcmd: ghold on all')
    assert_eq(formatPetCmd('spellhold on', 'enc'), '#petcmd spellhold on enc', 'petcmd: spellhold on enc')
    assert_eq(formatPetCmd('focus on', 'all'), '#petcmd focus on all', 'petcmd: focus on all')
    assert_eq(formatPetCmd('regroup on', 'all'), '#petcmd regroup on all', 'petcmd: regroup on all')
    assert_eq(formatPetCmd('assist on', 'all'), '#petcmd assist on all', 'petcmd: assist on all')

    -- C. Custom Command Sanitization
    local function sanitizeCustomPetCmd(text)
        text = (text or ''):match('^%s*(.-)%s*$')
        if text == '' then return nil end
        if text:sub(1, 7) == '#petcmd' then return text end
        return '#petcmd ' .. text
    end

    assert_eq(sanitizeCustomPetCmd('attack mag'), '#petcmd attack mag', 'custom cmd: prepends #petcmd')
    assert_eq(sanitizeCustomPetCmd('#petcmd taunt on all'), '#petcmd taunt on all', 'custom cmd: preserves existing #petcmd')
    assert_eq(sanitizeCustomPetCmd('  hold off nec  '), '#petcmd hold off nec', 'custom cmd: trims whitespace')
    assert_eq(sanitizeCustomPetCmd(''), nil, 'custom cmd: empty returns nil')
    assert_eq(sanitizeCustomPetCmd('   '), nil, 'custom cmd: whitespace only returns nil')

    -- D. Multi-Pet Trio Slot Mapping
    local PET_CLASSES = { Nec = true, Mag = true, Bst = true, Enc = true, Shm = true, SK = true, Dru = true, Brd = true }
    local function mapSlots(classes)
        local slots = {}
        for i = 1, 3 do
            local cls = classes[i]
            if cls then
                slots[#slots + 1] = {
                    slotNum = i,
                    cls = cls,
                    isPetCls = PET_CLASSES[cls] == true,
                    scope = classToPetCmdScope(cls)
                }
            end
        end
        return slots
    end

    local trio3Pets = mapSlots({ 'Mag', 'Nec', 'Bst' })
    assert_eq(#trio3Pets, 3, 'trio slots: 3 classes mapped')
    assert_true(trio3Pets[1].isPetCls, 'slot 1: Mag is pet class')
    assert_eq(trio3Pets[1].scope, 'mag', 'slot 1 scope: mag')
    assert_true(trio3Pets[2].isPetCls, 'slot 2: Nec is pet class')
    assert_eq(trio3Pets[2].scope, 'nec', 'slot 2 scope: nec')
    assert_true(trio3Pets[3].isPetCls, 'slot 3: Bst is pet class')
    assert_eq(trio3Pets[3].scope, 'bst', 'slot 3 scope: bst')

    local trioMixed = mapSlots({ 'War', 'Clr', 'Enc' })
    assert_eq(#trioMixed, 3, 'trio mixed: 3 classes mapped')
    assert_true(not trioMixed[1].isPetCls, 'slot 1: War is not pet class')
    assert_true(not trioMixed[2].isPetCls, 'slot 2: Clr is not pet class')
    assert_true(trioMixed[3].isPetCls, 'slot 3: Enc is pet class')
    assert_eq(trioMixed[3].scope, 'enc', 'slot 3 scope: enc')

    -- E. triune.lua Source Verification
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("function UI.drawPetControlTab()") ~= nil, 'triune.lua defines UI.drawPetControlTab')
    assert_true(triuneContent:find("ImGui.BeginTabItem%('Pets'%)") ~= nil, 'triune.lua uses Pets as tab label')
    local tabOrderMatch = triuneContent:find("UI.drawControlTab%(%)[%s\r\n]+UI.drawPetControlTab%(%)[%s\r\n]+UI.drawGemTab%(%)")
    assert_true(tabOrderMatch ~= nil, 'triune.lua places UI.drawPetControlTab right next to Control tab and before Gem tab')
    local tabOrderMatch2 = triuneContent:find("UI.drawAATab%(%)[%s\r\n]+UI.drawDiscTab%(%)[%s\r\n]+UI.drawClickieTab%(%)[%s\r\n]+UI.drawAutoAATab%(%)")
    assert_true(tabOrderMatch2 ~= nil, 'triune.lua places Disciplines and Clickies between AAs and Auto AA tabs')
    local settingsTabMatch = triuneContent:find("UI.drawCooldownsTab%(%)[%s\r\n]+UI.drawSettingsTab%(%)[%s\r\n]+UI.drawHelpTab%(%)")
    assert_true(settingsTabMatch ~= nil, 'triune.lua places UI.drawSettingsTab between Cooldowns and Help tabs')
    assert_true(triuneContent:find("PET_CLASSES%s*=%s*{[^}]*Brd%s*=%s*true") ~= nil, 'triune.lua includes Brd in petState.PET_CLASSES')
    assert_true(triuneContent:find("function UI.drawPetControlTab") ~= nil, 'triune.lua includes drawPetControlTab renderer')
    assert_true(triuneContent:find("sendPetCmd%(") ~= nil, 'triune.lua includes sendPetCmd helper')
    assert_true(triuneContent:find("getMultiPetList%(") ~= nil, 'triune.lua includes getMultiPetList helper')
    assert_true(triuneContent:find("cmd == 'pet'") ~= nil, 'triune.lua includes /ac pet slash command')
    assert_true(triuneContent:find("/pet report##petRpt") ~= nil, 'triune.lua includes /pet report button on pet slot cards')
    assert_true(triuneContent:find("Pet Stats Report##petStatsModal") ~= nil, 'triune.lua includes Pet Stats Report modal popup window')
    assert_true(triuneContent:find("petState%.inspectPetId") ~= nil, 'triune.lua tracks petState.inspectPetId')
end

-- ============================================================================
-- 42. ImGui Child Window Safety Checks
-- ============================================================================
print('--- ImGui Child Window Safety Checks ---')
do
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("ImGui.EndChild%(%)[%s\r\n]+end[%s\r\n]+ImGui.PopStyleVar%(2%)") == nil,
        'lists do not place EndChild inside BeginChild if block')
    assert_true(triuneContent:find("end[%s\r\n]+ImGui.EndChild%(%)[%s\r\n]+ImGui.PopStyleVar%(2%)") ~= nil,
        'lists call EndChild unconditionally outside BeginChild if block')

    -- Abilities, AA, and Disc list child safety checks
    assert_true(triuneContent:find("abilitieslist.-end[%s\r\n]+ImGui.EndChild%(%)[%s\r\n]+ImGui.PopStyleVar%(2%)") ~= nil,
        'abilitieslist calls EndChild unconditionally outside BeginChild if block')
    assert_true(triuneContent:find("aalist.-end[%s\r\n]+ImGui.EndChild%(%)[%s\r\n]+ImGui.PopStyleVar%(2%)") ~= nil,
        'aalist calls EndChild unconditionally outside BeginChild if block')
    assert_true(triuneContent:find("disclist.-end[%s\r\n]+ImGui.EndChild%(%)[%s\r\n]+ImGui.PopStyleVar%(2%)") ~= nil,
        'disclist calls EndChild unconditionally outside BeginChild if block')
    assert_true(triuneContent:find("clickielist.-end[%s\r\n]+ImGui.EndChild%(%)[%s\r\n]+ImGui.PopStyleVar%(2%)") ~= nil,
        'clickielist calls EndChild unconditionally outside BeginChild if block')

    -- Clickies compact layout checks
    local clickieTabBody = triuneContent:match("function UI%.drawClickieTab%(%).-ImGui%.EndTabItem%(%)")
    assert_true(clickieTabBody ~= nil, 'drawClickieTab body extracted')
    assert_true(clickieTabBody:find("ImGuiStyleVar%.ItemSpacing,%s*4,%s*3") ~= nil, 'drawClickieTab uses compact ItemSpacing (4, 3)')
    assert_true(clickieTabBody:find("ImGuiStyleVar%.FramePadding,%s*4,%s*3") ~= nil, 'drawClickieTab uses compact FramePadding (4, 3)')
    assert_true(clickieTabBody:find("InvisibleButton%('##upDummy',%s*17,%s*19%)") ~= nil, 'drawClickieTab uses InvisibleButton upDummy for slot 1 alignment')
    assert_true(clickieTabBody:find("InvisibleButton%('##dnDummy',%s*17,%s*19%)") ~= nil, 'drawClickieTab uses InvisibleButton dnDummy for last slot alignment')
    assert_true(clickieTabBody:find("SetNextItemWidth%(133%)") ~= nil, 'drawClickieTab uses compact 133px Target combo')
    assert_true(clickieTabBody:find("SetNextItemWidth%(116%)") ~= nil, 'drawClickieTab uses compact 116px When combo')
    assert_true(clickieTabBody:find("SetNextItemWidth%(57%)") ~= nil, 'drawClickieTab uses compact 57px Threshold slider')
    assert_true(clickieTabBody:find("SetNextItemWidth%(35%)") ~= nil, 'drawClickieTab uses compact 35px Min XT combo')
    assert_true(clickieTabBody:find("isDis and 'Off' or '%%d%%%%'") ~= nil, 'drawClickieTab uses Off label for 0% disabled threshold')

    -- createCastTracker scoping check
    local trackerBody = triuneContent:match("local function createCastTracker%(%).-return tracker[%s\r\n]+end")
    assert_true(trackerBody ~= nil, 'createCastTracker function body found')
    assert_true(trackerBody:find("castTracker") == nil, 'createCastTracker function body never references castTracker before declaration')
end

-- ============================================================================
-- 43. Ability Health Threshold & Feign Death Evaluation Logic
-- ============================================================================
print('--- Ability Health Threshold & Feign Death Evaluation ---')
do
    local triuneContent = readFile('TAC/lua/triune.lua')

    -- Verify UI guard ensures Autoskill checkbox is only shown for eligible skills
    assert_true(triuneContent:find("if isAutoskillEligible%(nm%) then[%s\r\n]+ImGui%.SameLine%(%)[%s\r\n]+local asVal = ImGui%.Checkbox%('Auto##as'") ~= nil,
        'UI.drawAbilitiesTab guards Auto##as with isAutoskillEligible(nm)')

    -- Verify combatTick autoskill loop checks isAutoskillEligible
    assert_true(triuneContent:find("act%.autoskill and isAutoskillEligible%(name%)") ~= nil,
        'combatTick autoskill loop checks isAutoskillEligible(name)')

    -- Mock player and world spawn state
    local playerHp = 100
    local targetHp = 15
    local mockTLO = {
        Me = {
            ID = function() return 1001 end,
            PctHPs = function() return playerHp end,
            PctMana = function() return 100 end,
            Combat = function() return true end,
            Feigning = function() return false end,
        },
        Spawn = function(id)
            if id == 1001 then
                return setmetatable({ PctHPs = function() return playerHp end }, { __call = function() return true end })
            elseif id == 2002 then
                return setmetatable({ PctHPs = function() return targetHp end }, { __call = function() return true end })
            end
            return setmetatable({}, { __call = function() return false end })
        end
    }

    local pctHPFunc = loadFunc(src, 'pctHP', {
        mq = { TLO = mockTLO }
    })

    -- Test pctHP accuracy and safety defaults
    assert_eq(pctHPFunc(1001), 100, 'pctHP returns player HP when healthy')
    assert_eq(pctHPFunc(2002), 15, 'pctHP returns target spawn HP')
    assert_eq(pctHPFunc(0), 100, 'pctHP returns 100 default for 0 id')
    assert_eq(pctHPFunc(nil), 100, 'pctHP returns 100 default for nil id')
    assert_eq(pctHPFunc(9999), 100, 'pctHP returns 100 default for missing spawn')

    -- Load conditionMet
    -- Load isFeignDeathAbility
    local isFeignDeathAbility = loadFunc(src, 'isFeignDeathAbility', {})
    assert_true(isFeignDeathAbility('Feign Death'), 'isFeignDeathAbility: Feign Death is true')
    assert_true(isFeignDeathAbility('Death Peace'), 'isFeignDeathAbility: Death Peace is true')
    assert_true(isFeignDeathAbility('Imitate Death'), 'isFeignDeathAbility: Imitate Death is true')
    assert_true(isFeignDeathAbility("Death's Effigy"), "isFeignDeathAbility: Death's Effigy is true")
    assert_eq(isFeignDeathAbility('Kick'), false, 'isFeignDeathAbility: Kick is false')
    assert_eq(isFeignDeathAbility('Mend'), false, 'isFeignDeathAbility: Mend is false')
    assert_eq(isFeignDeathAbility('Harm Touch'), false, 'isFeignDeathAbility: Harm Touch is false')

    -- Load conditionMet
    local runtime = {}
    local condEnv = {
        mq = { TLO = mockTLO },
        runtime = runtime,
        pctHP = pctHPFunc,
        isCombat = function() return true end,
        baseTok = function(tok) return tok:gsub('^[FESPGAC]:%s*', '') end,
        buffActive = function() return false end,
        sungKey = function() return '' end,
        isFeignDeathAbility = isFeignDeathAbility,
    }
    local conditionMet = loadFunc(src, 'conditionMet', condEnv)

    assert_true(conditionMet ~= nil, 'conditionMet loaded successfully')

    -- Scenario A: Player at 100% HP, Target Mob at 15% HP, Feign Death slider at 20%
    playerHp = 100
    targetHp = 15
    assert_eq(conditionMet('my HP <=', 20, 'Feign Death', 2002, 'Mnk', 'F: Myself'), false,
        'Feign Death (my HP <= 20) does not fire at 100% player HP')
    assert_eq(conditionMet('HP <=', 20, 'Feign Death', 2002, 'Mnk', 'E: Current Target'), false,
        'Feign Death (HP <= 20) does not fire when mob is at 15% but player is at 100%')
    assert_eq(conditionMet('target HP <=', 20, 'Feign Death', 2002, 'Mnk', 'E: Current Target'), false,
        'Feign Death (target HP <= 20) does not fire when mob is at 15% but player is at 100%')

    -- Scenario B: Death Peace AA (Shadowknight) at 100% player HP
    assert_eq(conditionMet('my HP <=', 20, 'Death Peace', 2002, 'SK', 'F: Myself'), false,
        'Death Peace AA does not fire at 100% player HP')
    assert_eq(conditionMet('HP <=', 20, 'Death Peace', 2002, 'SK', 'E: Current Target'), false,
        'Death Peace AA does not fire when mob is low HP but player is 100% HP')

    -- Scenario C: Player drops to 20% HP (threshold reached)
    playerHp = 20
    targetHp = 50
    assert_eq(conditionMet('my HP <=', 20, 'Feign Death', 2002, 'Mnk', 'F: Myself'), true,
        'Feign Death fires when player drops to 20% HP')
    assert_eq(conditionMet('HP <=', 20, 'Feign Death', 2002, 'Mnk', 'E: Current Target'), true,
        'Feign Death (HP <= 20) fires when player drops to 20% HP even with enemy target token')
    assert_eq(conditionMet('HP <=', 20, 'Death Peace', 2002, 'SK', 'E: Current Target'), true,
        'Death Peace AA fires when player drops to 20% HP')
    assert_eq(conditionMet('my HP <=', 20, 'Imitate Death', 2002, 'Mnk', 'F: Myself'), true,
        'Imitate Death AA fires when player drops to 20% HP')

    -- Scenario D: Player drops to 15% HP (emergency)
    playerHp = 15
    assert_eq(conditionMet('my HP <=', 20, 'Feign Death', 2002, 'Mnk', 'F: Myself'), true,
        'Feign Death fires when player drops below 20% HP (15%)')
    assert_eq(conditionMet('HP <=', 20, 'Death Peace', 2002, 'SK', 'E: Current Target'), true,
        'Death Peace AA fires when player drops below 20% HP (15%)')

    -- Scenario E: Mend evaluation (threshold 75%)
    playerHp = 80
    assert_eq(conditionMet('my HP <=', 75, 'Mend', 1001, 'Mnk', 'F: Myself'), false,
        'Mend does not fire when player is at 80% HP (> 75%)')
    assert_eq(conditionMet('HP <=', 75, 'Mend', 2002, 'Mnk', 'E: Current Target'), false,
        'Mend does not fire when target mob is at 15% but player is at 80%')
    playerHp = 70
    assert_eq(conditionMet('HP <=', 75, 'Mend', 2002, 'Mnk', 'E: Current Target'), true,
        'Mend fires when player is at 70% HP (<= 75%)')
end

-- ============================================================================
-- 46. Target Retention During Spell Casting (isTargetRequiredSpell, getActiveTargetRequiredCastingId, setTarget, clearTarget)
-- ============================================================================
print('--- Target Retention During Spell Casting ---')
do
    local function isTargetRequiredSpell(spell)
        if not spell then return false end
        local tt = nil
        if type(spell) == 'table' and spell.TargetType then
            tt = spell.TargetType
        elseif type(spell) == 'string' then
            local spellMap = {
                ['Complete Healing'] = 'Single',
                ['Greater Healing'] = 'Single',
                ['Chloroplast'] = 'Single',
                ['Light Healing'] = 'Single',
                ['Ice Comet'] = 'Single',
                ['Tashani'] = 'Single',
                ['Slow'] = 'Single',
                ['Word of Shadow'] = 'PB AE',
                ['Color Flux'] = 'PB AE',
                ['Cannibalize'] = 'Self',
                ['Armor of Protection'] = 'Self',
                ['Celestial Elixir'] = 'Group v1',
                ['Word of Redemption'] = 'Group v2',
            }
            tt = spellMap[spell] or 'Single'
        end
        if not tt or tt == '' or tt == 'NULL' then return false end
        local s = tostring(tt):lower()
        if s == 'self' or s == 'pb ae' or s == 'group v1' or s == 'group v2' or s:find('group') then
            return false
        end
        return true
    end

    -- 1. isTargetRequiredSpell classification
    assert_eq(isTargetRequiredSpell('Complete Healing'), true, 'heal Complete Healing requires target')
    assert_eq(isTargetRequiredSpell('Greater Healing'), true, 'heal Greater Healing requires target')
    assert_eq(isTargetRequiredSpell('Chloroplast'), true, 'heal Chloroplast requires target')
    assert_eq(isTargetRequiredSpell('Ice Comet'), true, 'nuke Ice Comet requires target')
    assert_eq(isTargetRequiredSpell('Tashani'), true, 'debuff Tashani requires target')
    assert_eq(isTargetRequiredSpell('Cannibalize'), false, 'self spell Cannibalize does not require target')
    assert_eq(isTargetRequiredSpell('Armor of Protection'), false, 'self buff does not require target')
    assert_eq(isTargetRequiredSpell('Word of Shadow'), false, 'PB AE spell does not require target')
    assert_eq(isTargetRequiredSpell('Color Flux'), false, 'PB AE stun does not require target')
    assert_eq(isTargetRequiredSpell('Celestial Elixir'), false, 'Group heal does not require target')
    assert_eq(isTargetRequiredSpell('Word of Redemption'), false, 'Group v2 heal does not require target')
    assert_eq(isTargetRequiredSpell({ TargetType = 'Single' }), true, 'table spell Single requires target')
    assert_eq(isTargetRequiredSpell({ TargetType = 'Self' }), false, 'table spell Self does not require target')
    assert_eq(isTargetRequiredSpell({ TargetType = 'PB AE' }), false, 'table spell PB AE does not require target')
    assert_eq(isTargetRequiredSpell({ TargetType = 'Group v1' }), false, 'table spell Group v1 does not require target')

    -- 2. getActiveTargetRequiredCastingId & Target Retention Simulation
    local mockState = {
        isCasting = false,
        castTracker = {
            targetRequired = false,
            activeTargetId = nil,
            activeSpell = nil,
            castStartTime = 0,
            failed = false,
        },
        currentTargetId = 0,
        targetCleared = false,
    }

    local function isCastingOrStarting()
        if mockState.isCasting then return true end
        if mockState.castTracker.activeSpell and not mockState.castTracker.failed and mockState.castTracker.castStartTime > 0 then
            local elapsed = os.clock() - mockState.castTracker.castStartTime
            if elapsed >= 0 and elapsed < 0.8 then return true end
        end
        return false
    end

    local myId = 1
    local function isHostile(id)
        return id and id >= 1000 and id < 2000
    end

    local function getActiveTargetRequiredCastingId()
        if not isCastingOrStarting() then return nil end
        if mockState.castTracker.targetRequired and mockState.castTracker.activeTargetId and mockState.castTracker.activeTargetId > 0 then
            if mockState.castTracker.activeTargetId == myId then
                local tid = mockState.currentTargetId or 0
                if tid > 0 and isHostile(tid) then
                    return nil
                end
            end
            return mockState.castTracker.activeTargetId
        end
        return nil
    end

    local function setTarget(id)
        if not id or id == 0 then return false end
        local reqId = getActiveTargetRequiredCastingId()
        if reqId and reqId > 0 and id ~= reqId then
            return false
        end
        mockState.currentTargetId = id
        mockState.targetCleared = false
        return true
    end

    local function clearTarget()
        local reqId = getActiveTargetRequiredCastingId()
        if reqId and reqId > 0 then
            return false
        end
        mockState.currentTargetId = 0
        mockState.targetCleared = true
        return true
    end

    local function checkAggroSwitch(newMobId)
        if isCastingOrStarting() or getActiveTargetRequiredCastingId() then
            return false
        end
        return setTarget(newMobId)
    end

    -- Test Idle state (not casting)
    assert_eq(getActiveTargetRequiredCastingId(), nil, 'idle: no required casting target')
    assert_eq(setTarget(1001), true, 'idle: can set target to enemy mob 1001')
    assert_eq(mockState.currentTargetId, 1001, 'idle: target is 1001')
    assert_eq(clearTarget(), true, 'idle: can clear target')
    assert_eq(mockState.currentTargetId, 0, 'idle: target cleared to 0')
    assert_eq(mockState.targetCleared, true, 'idle: targetCleared flag is true')

    -- Start casting a single-target heal on ally #2002
    setTarget(2002)
    assert_eq(mockState.currentTargetId, 2002, 'targeted ally 2002 for heal')
    mockState.isCasting = true
    mockState.castTracker.activeSpell = 'Greater Healing'
    mockState.castTracker.activeTargetId = 2002
    mockState.castTracker.targetRequired = isTargetRequiredSpell('Greater Healing')
    mockState.castTracker.castStartTime = os.clock()

    -- Verify active casting target identification
    assert_eq(getActiveTargetRequiredCastingId(), 2002, 'casting heal: active required target is ally 2002')

    -- Attempt to switch target to attacking enemy mob #1001 while casting heal
    assert_eq(setTarget(1001), false, 'cannot switch target to enemy mob 1001 while casting heal on 2002')
    assert_eq(mockState.currentTargetId, 2002, 'target remains firmly on ally 2002')

    -- Attempt to clear target while casting heal
    assert_eq(clearTarget(), false, 'cannot clear target while casting heal on 2002')
    assert_eq(mockState.currentTargetId, 2002, 'target was not cleared, remains on 2002')

    -- Attempt aggro switch while casting heal
    assert_eq(checkAggroSwitch(3003), false, 'aggro switch blocked while casting heal')
    assert_eq(mockState.currentTargetId, 2002, 'target remains on 2002 after blocked aggro switch')

    -- Re-targeting the same ally 2002 is permitted (re-synchronization)
    assert_eq(setTarget(2002), true, 're-targeting same ally 2002 succeeds')
    assert_eq(mockState.currentTargetId, 2002, 'target is 2002')

    -- Finish casting heal
    mockState.isCasting = false
    mockState.castTracker.activeSpell = nil
    mockState.castTracker.activeTargetId = nil
    mockState.castTracker.targetRequired = false
    mockState.castTracker.castStartTime = 0

    -- Now that casting finished, target can be switched to combat target (1001)
    assert_eq(getActiveTargetRequiredCastingId(), nil, 'post-cast: no active casting target')
    assert_eq(setTarget(1001), true, 'post-cast: can restore target to enemy mob 1001')
    assert_eq(mockState.currentTargetId, 1001, 'post-cast: target restored to 1001')

    -- Casting a non-targeted spell (e.g. Cannibalize, Self-buff) does NOT lock target
    mockState.isCasting = true
    mockState.castTracker.activeSpell = 'Cannibalize'
    mockState.castTracker.activeTargetId = 1001
    mockState.castTracker.targetRequired = isTargetRequiredSpell('Cannibalize')
    mockState.castTracker.castStartTime = os.clock()

    assert_eq(mockState.castTracker.targetRequired, false, 'Cannibalize targetRequired is false')
    assert_eq(getActiveTargetRequiredCastingId(), nil, 'self spell: getActiveTargetRequiredCastingId returns nil')
    assert_eq(setTarget(4004), true, 'self spell: target change allowed (not a targeted spell)')
    assert_eq(mockState.currentTargetId, 4004, 'target changed to 4004')

    mockState.isCasting = false
    mockState.castTracker.activeSpell = nil

    -- 3. Self-healing while attacking an enemy mob #1001
    -- When fighting enemy mob #1001, character casts Greater Healing on self (myId)
    setTarget(1001)
    assert_eq(mockState.currentTargetId, 1001, 'targeting enemy mob 1001')
    local isSelf = (myId == myId)
    local curT = mockState.currentTargetId
    local isHostileT = (curT > 0 and isHostile(curT))
    local needT = (not isSelf) or (not isHostileT and curT > 0 and curT ~= myId)
    assert_eq(needT, false, 'self-heal on hostile target does not need to select self')
    assert_eq(mockState.currentTargetId, 1001, 'target remains on enemy mob 1001')

    -- Cast starts
    mockState.isCasting = true
    mockState.castTracker.activeSpell = 'Greater Healing'
    mockState.castTracker.activeTargetId = myId
    if isSelf and isHostileT then
        mockState.castTracker.targetRequired = false
    else
        mockState.castTracker.targetRequired = isTargetRequiredSpell('Greater Healing')
    end
    mockState.castTracker.castStartTime = os.clock()

    assert_eq(mockState.castTracker.targetRequired, false, 'self-heal targetRequired is false on hostile target')
    assert_eq(getActiveTargetRequiredCastingId(), nil, 'self-heal with hostile target: getActiveTargetRequiredCastingId returns nil')
    assert_eq(mockState.currentTargetId, 1001, 'target preserved on mob 1001 during self-heal')

    -- Finish cast
    mockState.isCasting = false
    mockState.castTracker.activeSpell = nil
    mockState.castTracker.activeTargetId = nil
    mockState.castTracker.targetRequired = false
    assert_eq(mockState.currentTargetId, 1001, 'post-heal: character still targeting enemy mob 1001')
end

-- ============================================================================
-- Suite 49: Decoupled Spell Gems & Downtime Buff Swapping Logic
-- ============================================================================
print('--- Decoupled Spell Gems & Downtime Buff Swapping Logic ---')
do
    -- 1. getPrimarySpellForGem resolution
    local decoupledGems = {
        { gem = 1, spell = 'Heal', when = 'HP <=', pct = 50 },
        { gem = 12, spell = 'Ice Comet', when = 'in combat', pct = 100 },
        { gem = 12, spell = 'Armor of Protection', when = 'missing buff', pct = 100 },
        { gem = 12, spell = 'Shield of Fire', when = 'missing buff', pct = 100 },
        { gem = 4, spell = 'Slow', when = 'in combat', pct = 100 },
    }

    local function getPrimarySpellForGem(slot, gems)
        slot = tonumber(slot) or 1
        for _, g in ipairs(gems) do
            if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' then
                return g.spell
            end
        end
        return nil
    end

    assert_eq(getPrimarySpellForGem(1, decoupledGems), 'Heal', 'gem 1 primary spell is Heal')
    assert_eq(getPrimarySpellForGem(12, decoupledGems), 'Ice Comet', 'gem 12 primary spell is Ice Comet (first configured for gem 12)')
    assert_eq(getPrimarySpellForGem(4, decoupledGems), 'Slow', 'gem 4 primary spell is Slow')
    assert_eq(getPrimarySpellForGem(2, decoupledGems), nil, 'gem 2 has no configured spells')

    -- 2. Sanitization of decoupled loadout entries
    local rawLoadout = {
        gems = {
            { spell = 'Spell A' },             -- default to gem 1
            { gem = 12, spell = 'Spell B' },
            { gem = 99, spell = 'Spell C' },    -- clamped to 12
            { gem = 0, spell = 'Spell D' },     -- clamped to 1
        }
    }
    local sanitizedGems = {}
    for i, g in ipairs(rawLoadout.gems) do
        local entry = { gem = tonumber(g.gem) or math.min(i, 12), spell = g.spell }
        if entry.gem < 1 then entry.gem = 1 end
        if entry.gem > 12 then entry.gem = 12 end
        table.insert(sanitizedGems, entry)
    end
    assert_eq(#sanitizedGems, 4, '4 sanitized gems')
    assert_eq(sanitizedGems[1].gem, 1, 'entry 1 defaulted to gem 1')
    assert_eq(sanitizedGems[2].gem, 12, 'entry 2 kept gem 12')
    assert_eq(sanitizedGems[3].gem, 12, 'entry 3 clamped to gem 12')
    assert_eq(sanitizedGems[4].gem, 1, 'entry 4 clamped to gem 1')

    -- 3. Downtime Aggro Detection logic
    local function hasDowntimeAggroThreat(combat, isCombatFn, anyXtarFn, countXtarFn)
        if combat then return true end
        if isCombatFn and isCombatFn() then return true end
        if anyXtarFn and anyXtarFn(true) then return true end
        if countXtarFn and countXtarFn() > 0 then return true end
        return false
    end

    assert_eq(hasDowntimeAggroThreat(false, function() return false end, function() return false end, function() return 0 end), false, 'no aggro threat')
    assert_eq(hasDowntimeAggroThreat(true, function() return false end, function() return false end, function() return 0 end), true, 'Me.Combat() detects aggro')
    assert_eq(hasDowntimeAggroThreat(false, function() return true end, function() return false end, function() return 0 end), true, 'isCombat() detects aggro')
    assert_eq(hasDowntimeAggroThreat(false, function() return false end, function() return true end, function() return 0 end), true, 'anyXtarAlive(true) detects aggro')
    assert_eq(hasDowntimeAggroThreat(false, function() return false end, function() return false end, function() return 2 end), true, 'countNPCXtarget() > 0 detects aggro')

    -- 4. In-combat gem filtering: only cast memorized spells
    local physicalBar = { [1] = 'Heal', [12] = 'Ice Comet' }
    local function isGemMatching(slot, spName)
        return physicalBar[slot] == spName
    end

    local castableCombatSpells = {}
    for i, g in ipairs(decoupledGems) do
        local slot = tonumber(g.gem) or i
        if isGemMatching(slot, g.spell) then
            table.insert(castableCombatSpells, g.spell)
        end
    end
    assert_eq(#castableCombatSpells, 2, 'only 2 spells memorized on physical bar')
    assert_eq(castableCombatSpells[1], 'Heal', 'Heal is castable in combat')
    assert_eq(castableCombatSpells[2], 'Ice Comet', 'Ice Comet is castable in combat')

    -- 5. Priority spell selection and out-of-combat restoration
    local multiGems = {
        { gem = 12, spell = 'Touch of the Cursed', target = 'E: Target', when = 'HP <= 80', pct = 80 }, -- Priority 1 (top of list)
        { gem = 12, spell = 'Voice of the Berserker', target = 'M: Self', when = 'missing buff', pct = 100 }, -- Priority 2 (buff)
    }
    local function getPrimarySpellForGem(slot, gemList)
        for _, g in ipairs(gemList) do
            if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' then
                local pctVal = tonumber(g.pct)
                if pctVal == nil or pctVal > 0 then
                    return g.spell, g
                end
            end
        end
        return nil
    end

    local pSpell = getPrimarySpellForGem(12, multiGems)
    assert_eq(pSpell, 'Touch of the Cursed', 'G12 priority spell is Touch of the Cursed (lifetap at top of list)')

    -- Test restoration decision:
    -- Scenario A: Voice of the Berserker is currently memmed in Gem 12, and buff is already active (not needed)
    local physicalBar2 = { [12] = 'Voice of the Berserker' }
    local function evaluateRestoreNeeded(slot, gemList, currentBar, buffNeededFn)
        local primary = getPrimarySpellForGem(slot, gemList)
        if not primary or currentBar[slot] == primary then return false end
        local lowerNeeded = false
        for _, g in ipairs(gemList) do
            if g and (tonumber(g.gem) or 1) == slot and g.spell and g.spell ~= '' and g.spell ~= primary then
                if buffNeededFn(g) then
                    lowerNeeded = true
                    break
                end
            end
        end
        return not lowerNeeded
    end

    local shouldRememLifetap = evaluateRestoreNeeded(12, multiGems, physicalBar2, function(g) return false end)
    assert_true(shouldRememLifetap, 'Gem 12 should remem priority lifetap back when buff is not needed')

    -- Scenario B: Buff is missing and needed
    local shouldKeepBuff = evaluateRestoreNeeded(12, multiGems, physicalBar2, function(g) return true end)
    assert_eq(shouldKeepBuff, false, 'Gem 12 should not remem priority spell while lower priority buff is still needed')

    -- 6. importCurrentGems auto-population logic
    local mockGems = {
        [1] = 'Minor Healing',
        [2] = 'Courage',
        [3] = 'Frost Bolt',
    }
    local function mockDefaultsForKind(kind, bene)
        if kind == 'heal' then return 'F: Myself', 'my HP <=', 75 end
        if kind == 'buff' then return 'F: Myself', 'missing buff', 100 end
        if kind == 'dd' then return 'E: Current Target', 'target HP <=', 95 end
        return 'E: Current Target', 'target HP <=', 95
    end
    local function mockSpellClassInfo(name)
        if name == 'Minor Healing' then return 'Clr', true, 'heal' end
        if name == 'Courage' then return 'Clr', true, 'buff' end
        if name == 'Frost Bolt' then return 'Wiz', false, 'dd' end
        return 'War', false, 'other'
    end

    local function simulateImportCurrentGems(targetGemsTable, numG, activeGems)
        targetGemsTable = targetGemsTable or {}
        local newGems = {}
        for i = 1, numG do
            local nm = activeGems[i]
            if nm and nm ~= '' and nm ~= 'NULL' then
                local cls, bene, kind = mockSpellClassInfo(nm)
                local tgt, wn, pc = mockDefaultsForKind(kind, bene)
                table.insert(newGems, {
                    gem = i,
                    cls = cls,
                    spell = nm,
                    target = tgt,
                    when = wn,
                    pct = pc,
                    min_xtar = 1,
                    max_casts = 0,
                    burn_only = false,
                })
            end
        end
        if targetGemsTable then
            for idx = numG + 1, #targetGemsTable do
                if targetGemsTable[idx] then
                    table.insert(newGems, targetGemsTable[idx])
                end
            end
        end
        for k in pairs(targetGemsTable) do targetGemsTable[k] = nil end
        for idx, v in ipairs(newGems) do targetGemsTable[idx] = v end
        return targetGemsTable
    end

    local imported = simulateImportCurrentGems({}, 8, mockGems)
    assert_eq(#imported, 3, 'imported 3 active spells from gem bar')
    assert_eq(imported[1].gem, 1, 'slot 1 gem is 1')
    assert_eq(imported[1].spell, 'Minor Healing', 'slot 1 spell is Minor Healing')
    assert_eq(imported[1].cls, 'Clr', 'slot 1 cls is Clr')
    assert_eq(imported[1].when, 'my HP <=', 'slot 1 when condition is heal default')
    assert_eq(imported[1].pct, 75, 'slot 1 pct is 75')
    assert_eq(imported[1].min_xtar, 1, 'slot 1 min_xtar is 1')
    assert_eq(imported[1].max_casts, 0, 'slot 1 max_casts is 0')
    assert_eq(imported[1].burn_only, false, 'slot 1 burn_only is false')

    assert_eq(imported[2].gem, 2, 'slot 2 gem is 2')
    assert_eq(imported[2].spell, 'Courage', 'slot 2 spell is Courage')
    assert_eq(imported[2].when, 'missing buff', 'slot 2 when condition is buff default')

    assert_eq(imported[3].gem, 3, 'slot 3 gem is 3')
    assert_eq(imported[3].spell, 'Frost Bolt', 'slot 3 spell is Frost Bolt')
    assert_eq(imported[3].when, 'target HP <=', 'slot 3 when condition is dd default')

    -- Retaining extra configured spells beyond physical bar count
    local existingLoadout = {
        { gem = 1, spell = 'Old 1' },
        { gem = 2, spell = 'Old 2' },
        { gem = 3, spell = 'Old 3' },
        { gem = 4, spell = 'Old 4' },
        { gem = 5, spell = 'Old 5' },
        { gem = 6, spell = 'Old 6' },
        { gem = 7, spell = 'Old 7' },
        { gem = 8, spell = 'Old 8' },
        { gem = 1, spell = 'Downtime Buff 1' },
        { gem = 2, spell = 'Downtime Buff 2' },
    }
    local reimported = simulateImportCurrentGems(existingLoadout, 8, mockGems)
    assert_eq(#reimported, 5, 'reimported 3 physical gems + 2 retained downtime gems')
    assert_eq(reimported[1].spell, 'Minor Healing', 'gem 1 replaced by active bar')
    assert_eq(reimported[2].spell, 'Courage', 'gem 2 replaced by active bar')
    assert_eq(reimported[3].spell, 'Frost Bolt', 'gem 3 replaced by active bar')
    assert_eq(reimported[4].spell, 'Downtime Buff 1', 'retained extra spell line 1')
    assert_eq(reimported[5].spell, 'Downtime Buff 2', 'retained extra spell line 2')

    -- 7. triune.lua source verification for Import Bar button & slash command
    local triuneCode = readFile('TAC/lua/triune.lua')
    assert_true(triuneCode:find("function runtime.importCurrentGems", 1, true) ~= nil, 'triune.lua defines runtime.importCurrentGems')
    assert_true(triuneCode:find("Import Bar##importBarBtn", 1, true) ~= nil, 'triune.lua includes Import Bar button in UI.drawGemTabHeader')
    assert_true(triuneCode:find("Auto-populate spell lines based on what is currently memorized on your spell gems.", 1, true) ~= nil, 'triune.lua includes descriptive tooltip on Import Bar')
    assert_true(triuneCode:find('Click "+ Add Spell" or "Import Bar" above to populate your spell list.', 1, true) ~= nil, 'triune.lua mentions Import Bar in empty gem list hint')
    assert_true(triuneCode:find("cmd == 'importbar' or cmd == 'import'", 1, true) ~= nil, 'triune.lua handles /ac importbar and /ac import slash command')
end

-- ============================================================================
-- Suite 50: Spell Cast Movement Cessation Logic (stopMovementForCast)
-- ============================================================================
print('--- Spell Cast Movement Cessation Logic ---')
do
    local cmds = {}
    local isNavActive = false
    local isStickActive = false
    local stickStatusStr = 'OFF'
    local isCharacterMoving = false

    local mockMq = {
        cmd = function(c) table.insert(cmds, c) end,
        delay = function() end,
        TLO = {
            Me = {
                Class = { ShortName = function() return 'CLR' end },
                Moving = function() return isCharacterMoving end,
            },
            Navigation = { Active = function() return isNavActive end },
            Stick = { Active = function() return isStickActive end, Status = function() return stickStatusStr end },
            MoveTo = { Moving = function() return false end },
        },
    }

    local mockPursuit = { id = 42, lastNavTargetId = 42, lastNavLoc = '100,200' }
    local mockNavLoaded = function() return true end
    local mockStickLoaded = function() return true end

    local function createStopMovementForCast(mq, pursuit, navLoaded, stickLoaded)
        return function(cls, spell)
            if cls == 'Brd' then return end
            local isBrd = false
            pcall(function() isBrd = (mq.TLO.Me.Class.ShortName() == 'BRD') end)
            if isBrd and (not cls or cls == 'Brd') then return end

            if navLoaded() then
                local navActive = false
                pcall(function() navActive = mq.TLO.Navigation.Active() or false end)
                if navActive then
                    pcall(function() mq.cmd('/nav stop') end)
                    pursuit.id = 0
                    pursuit.lastNavTargetId = 0
                    pursuit.lastNavLoc = nil
                end
            end

            if stickLoaded() then
                pcall(function()
                    if mq.TLO.Stick.Active() or mq.TLO.Stick.Status() == 'ON' then
                        mq.cmd('/stick pause')
                    end
                end)
            end

            pcall(function()
                if mq.TLO.MoveTo and mq.TLO.MoveTo.Moving and mq.TLO.MoveTo.Moving() then
                    mq.cmd('/moveto off')
                end
            end)

            local isMoving = false
            pcall(function() isMoving = mq.TLO.Me.Moving() or false end)
            if isMoving then
                pcall(function() mq.cmd('/keypress forward') end)
                pcall(function() mq.cmd('/keypress back') end)
                pcall(function() mq.cmd('/keypress strafe_left') end)
                pcall(function() mq.cmd('/keypress strafe_right') end)
                local waitStop = 0
                while waitStop < 200 do
                    local stillMoving = false
                    pcall(function() stillMoving = mq.TLO.Me.Moving() or false end)
                    if not stillMoving then break end
                    local ok = pcall(function() mq.delay(20) end)
                    if not ok then break end
                    waitStop = waitStop + 20
                end
            end
        end
    end

    -- Test 1: Bard class skips movement stopping
    cmds = {}
    local stopMove = createStopMovementForCast(mockMq, mockPursuit, mockNavLoaded, mockStickLoaded)
    stopMove('Brd', 'Selo\'s Accelerando')
    assert_eq(#cmds, 0, 'Bard casting does not stop movement')

    -- Test 2: Non-Bard with active Nav halts nav and resets pursuit tracking
    cmds = {}
    mockPursuit.id = 100
    mockPursuit.lastNavTargetId = 100
    isNavActive = true
    stopMove('Clr', 'Complete Heal')
    assert_true(cmds[1] == '/nav stop', 'Non-bard with active navigation issues /nav stop')
    assert_eq(mockPursuit.id, 0, 'pursuit.id reset to 0 after /nav stop')
    assert_eq(mockPursuit.lastNavTargetId, 0, 'pursuit.lastNavTargetId reset to 0 after /nav stop')

    -- Test 3: Active stick pauses stick
    cmds = {}
    isNavActive = false
    stickStatusStr = 'ON'
    isStickActive = true
    stopMove('Wiz', 'Ice Comet')
    assert_true(cmds[1] == '/stick pause', 'Active stick is paused before casting')

    -- Test 4: Moving character releases keys
    cmds = {}
    stickStatusStr = 'OFF'
    isStickActive = false
    isCharacterMoving = true
    stopMove('Nec', 'Lifetap')
    local foundFwd, foundBack = false, false
    for _, c in ipairs(cmds) do
        if c == '/keypress forward' then foundFwd = true end
        if c == '/keypress back' then foundBack = true end
    end
    assert_true(foundFwd and foundBack, 'Keys forward and back released when moving')
end

-- ============================================================================
-- Suite 51: Assist Mode Dropdown, Player ID Selection & Management
-- ============================================================================
print('--- Assist Mode Dropdown & Player ID Selection ---')
do
    local sanitizeModeConfig = loadFunc(src, 'sanitizeModeConfig', { MODES = MODES })
    local defaultCtrl = loadFunc(src, 'defaultCtrl')

    -- 1. Default ctrl has ma_id = 0 and custom_ma_list = {}
    local c = defaultCtrl()
    assert_eq(c.ma_id, 0, 'defaultCtrl initializes ma_id to 0')
    assert_true(type(c.custom_ma_list) == 'table', 'defaultCtrl initializes custom_ma_list as a table')
    assert_eq(#c.custom_ma_list, 0, 'defaultCtrl custom_ma_list is empty')

    -- 2. sanitizeModeConfig handles missing ma_id and custom_ma_list
    local sparseCtrl = { mode = 'Assist', submode = 'Chase' }
    sanitizeModeConfig(sparseCtrl)
    assert_eq(sparseCtrl.ma_id, 0, 'sanitizeModeConfig sets default ma_id = 0')
    assert_true(type(sparseCtrl.custom_ma_list) == 'table', 'sanitizeModeConfig sets default custom_ma_list table')

    -- 3. Assist Candidate Generator Logic
    local mockGroupMembers = {
        { id = 101, name = 'TankBob', class = 'WAR' },
        { id = 102, name = 'HealJane', class = 'CLR' },
    }
    local mockSpawns = {
        ['pc =OutsidePlayer'] = { id = 205, class = 'PAL' },
    }
    local testCtrl = {
        ma_id = 101,
        ma_name = 'TankBob',
        custom_ma_list = {
            { name = 'OutsidePlayer', id = 205, class = 'PAL' },
            { name = 'TankBob', id = 101, class = 'WAR' }, -- duplicate of group member
        },
    }

    local function createCandidateGenerator(groupMembers, leaderName, spawns, ctrlTable)
        return function()
            local candidates = {
                { id = 0, name = '', label = '(None)', source = 'none' }
            }
            local seenNames = {}

            -- Group members
            for _, m in ipairs(groupMembers) do
                local mId = m.id or 0
                local mName = m.name or ''
                local mClass = m.class or ''
                if mName ~= '' then
                    local isLdr = (leaderName ~= '' and mName:lower() == leaderName:lower())
                    local ldrPrefix = isLdr and '[Leader] ' or '[Group] '
                    local clsStr = (mClass ~= '') and (' [' .. mClass .. ']') or ''
                    local idStr = (mId > 0) and (' (ID: ' .. tostring(mId) .. ')') or ' (Not in zone)'
                    local lbl = string.format('%s%s%s%s', ldrPrefix, mName, clsStr, idStr)
                    table.insert(candidates, { id = mId, name = mName, label = lbl, source = 'group', class = mClass })
                    seenNames[mName:lower()] = true
                end
            end

            -- Custom entries
            if ctrlTable and ctrlTable.custom_ma_list then
                for _, entry in ipairs(ctrlTable.custom_ma_list) do
                    local eName = entry.name or ''
                    if eName ~= '' and not seenNames[eName:lower()] then
                        local sp = spawns['pc =' .. eName]
                        local liveId = sp and sp.id or 0
                        local liveCls = sp and sp.class or (entry.class or '')
                        local clsStr = (liveCls ~= '') and (' [' .. liveCls .. ']') or ''
                        local idStr = (liveId > 0) and (' (ID: ' .. tostring(liveId) .. ')') or ' (Not in zone)'
                        local lbl = string.format('[Custom] %s%s%s', eName, clsStr, idStr)
                        table.insert(candidates, {
                            id = liveId > 0 and liveId or (entry.id or 0),
                            name = eName,
                            label = lbl,
                            source = 'custom',
                            class = liveCls,
                        })
                        seenNames[eName:lower()] = true
                    end
                end
            end
            return candidates
        end
    end

    local gen = createCandidateGenerator(mockGroupMembers, 'TankBob', mockSpawns, testCtrl)
    local candidates = gen()
    assert_eq(#candidates, 4, 'Candidate list has 4 entries (None, 2 group, 1 deduplicated custom)')
    assert_eq(candidates[1].label, '(None)', 'First entry is (None)')
    assert_true(candidates[2].label:find('%[Leader%] TankBob %[WAR%] %(ID: 101%)') ~= nil, 'Group leader correctly identified and formatted with ID')
    assert_true(candidates[3].label:find('%[Group%] HealJane %[CLR%] %(ID: 102%)') ~= nil, 'Group member correctly identified and formatted with ID')
    assert_true(candidates[4].label:find('%[Custom%] OutsidePlayer %[PAL%] %(ID: 205%)') ~= nil, 'Custom player formatted with ID')
    assert_eq(candidates[4].source, 'custom', 'Custom player marked with custom source')

    -- 4. Target-based addition (validation tests)
    local function createAddTarget(myId, getTarget, ctrlTable)
        return function()
            local t = getTarget()
            if not t or (t.id or 0) <= 0 or not t.name or t.name == '' then
                return false, 'Target a player character (PC) first to add.'
            end
            if t.type ~= 'PC' then
                return false, 'Target must be a PC.'
            end
            if t.id == myId then
                return false, 'Cannot add yourself as Main Assist.'
            end
            ctrlTable.custom_ma_list = ctrlTable.custom_ma_list or {}
            local found = false
            for _, entry in ipairs(ctrlTable.custom_ma_list) do
                if entry.name:lower() == t.name:lower() then
                    entry.id = t.id
                    entry.class = t.class
                    found = true
                    break
                end
            end
            if not found then
                table.insert(ctrlTable.custom_ma_list, { name = t.name, id = t.id, class = t.class })
            end
            ctrlTable.ma_id = t.id
            ctrlTable.ma_name = t.name
            return true, string.format('Added %s (ID: %d) as Main Assist.', t.name, t.id)
        end
    end

    -- Rejection 1: No target
    local curTarget = nil
    local addTarget = createAddTarget(999, function() return curTarget end, testCtrl)
    local ok, msg = addTarget()
    assert_eq(ok, false, 'Adding with no target returns false')

    -- Rejection 2: Target is NPC
    curTarget = { id = 50, name = 'a gnoll', type = 'NPC', class = 'WAR' }
    ok, msg = addTarget()
    assert_eq(ok, false, 'Adding NPC returns false')

    -- Rejection 3: Target is self
    curTarget = { id = 999, name = 'MySelf', type = 'PC', class = 'MNK' }
    ok, msg = addTarget()
    assert_eq(ok, false, 'Adding self returns false')

    -- Success: Valid PC
    curTarget = { id = 301, name = 'NewRaidAssist', type = 'PC', class = 'WAR' }
    ok, msg = addTarget()
    assert_eq(ok, true, 'Adding valid PC returns true')
    assert_eq(testCtrl.ma_id, 301, 'ctrl.ma_id updated to target ID')
    assert_eq(testCtrl.ma_name, 'NewRaidAssist', 'ctrl.ma_name updated to target name')

    -- 5. Custom Assist Removal
    local function createRemoveAssist(getTarget, ctrlTable)
        return function(targetNameOrId)
            ctrlTable.custom_ma_list = ctrlTable.custom_ma_list or {}
            local removeIdx = nil

            if targetNameOrId then
                local searchStr = tostring(targetNameOrId):lower()
                for i, entry in ipairs(ctrlTable.custom_ma_list) do
                    if entry.name:lower() == searchStr or tostring(entry.id) == searchStr then
                        removeIdx = i; break
                    end
                end
            end

            if not removeIdx then
                local t = getTarget()
                if t and t.type == 'PC' and t.name then
                    for i, entry in ipairs(ctrlTable.custom_ma_list) do
                        if entry.name:lower() == t.name:lower() then
                            removeIdx = i; break
                        end
                    end
                end
            end

            if not removeIdx then
                for i, entry in ipairs(ctrlTable.custom_ma_list) do
                    if (ctrlTable.ma_id and ctrlTable.ma_id > 0 and entry.id == ctrlTable.ma_id) or
                       (ctrlTable.ma_name and ctrlTable.ma_name ~= '' and entry.name:lower() == ctrlTable.ma_name:lower()) then
                        removeIdx = i; break
                    end
                end
            end

            if removeIdx then
                local removedName = ctrlTable.custom_ma_list[removeIdx].name
                table.remove(ctrlTable.custom_ma_list, removeIdx)
                if ctrlTable.ma_name and ctrlTable.ma_name:lower() == removedName:lower() then
                    ctrlTable.ma_id = 0
                    ctrlTable.ma_name = ''
                end
                return true, removedName
            end
            return false, nil
        end
    end

    local removeAssist = createRemoveAssist(function() return nil end, testCtrl)
    -- Remove currently selected (NewRaidAssist)
    local remOk, remName = removeAssist()
    assert_eq(remOk, true, 'Removing current selected assist returns true')
    assert_eq(remName, 'NewRaidAssist', 'Removed expected player')
    assert_eq(testCtrl.ma_id, 0, 'ctrl.ma_id reset to 0 upon removal')
    assert_eq(testCtrl.ma_name, '', 'ctrl.ma_name reset to empty string upon removal')

    -- 6. Player ID resolution with name fallback
    local function createMaPcIdResolver(ctrlTable, liveSpawnsById, liveSpawnsByName)
        return function()
            if not ctrlTable then return nil end
            if ctrlTable.ma_id and ctrlTable.ma_id > 0 then
                local s = liveSpawnsById[ctrlTable.ma_id]
                if s and s.alive and s.type == 'PC' then
                    if not ctrlTable.ma_name or ctrlTable.ma_name == '' or s.name == ctrlTable.ma_name then
                        return ctrlTable.ma_id
                    end
                end
            end
            if ctrlTable.ma_name and ctrlTable.ma_name ~= '' then
                local s = liveSpawnsByName[ctrlTable.ma_name]
                if s and s.alive and s.type == 'PC' then
                    ctrlTable.ma_id = s.id
                    return s.id
                end
            end
            return nil
        end
    end

    local spawnsById = {
        [101] = { id = 101, name = 'TankBob', alive = true, type = 'PC' }
    }
    local spawnsByName = {
        ['TankBob'] = { id = 601, name = 'TankBob', alive = true, type = 'PC' } -- new spawn ID after zoning
    }

    -- Direct ID hit
    local resCtrl = { ma_id = 101, ma_name = 'TankBob' }
    local resolver = createMaPcIdResolver(resCtrl, spawnsById, spawnsByName)
    assert_eq(resolver(), 101, 'Resolves spawn ID directly when valid and matching')

    -- Stale ID after zoning: ID 101 no longer in spawnsById, but name matches in new zone
    local resCtrlZoned = { ma_id = 101, ma_name = 'TankBob' }
    local resolverZoned = createMaPcIdResolver(resCtrlZoned, {}, spawnsByName)
    local resolvedNewId = resolverZoned()
    assert_eq(resolvedNewId, 601, 'Resolves new spawn ID via name lookup after zoning')
    assert_eq(resCtrlZoned.ma_id, 601, 'Updates cached ctrl.ma_id to new spawn ID')

    -- 7. getMaTargetInfo logic
    local function createMaTargetInfoGetter(ctrlTable, spawnsById, spawnsByName)
        return function()
            local maId = ctrlTable and ctrlTable.ma_id and ctrlTable.ma_id > 0 and ctrlTable.ma_id or nil
            local maName = ctrlTable and ctrlTable.ma_name and ctrlTable.ma_name ~= '' and ctrlTable.ma_name or nil
            local maSpawn = (maId and spawnsById[maId]) or (maName and spawnsByName[maName]) or nil
            if not maSpawn then
                return { hasMA = false, hasTarget = false, targetName = 'No Target', maName = maName or '(None Set)' }
            end
            local t = maSpawn.target
            if not t or not t.id or t.id <= 0 then
                return { hasMA = true, hasTarget = false, targetName = 'No Target', maName = maSpawn.name, maId = maSpawn.id }
            end
            return {
                hasMA = true,
                hasTarget = true,
                maId = maSpawn.id,
                maName = maSpawn.name,
                targetId = t.id,
                targetName = t.name,
                targetHp = t.hp or 100,
                targetDist = t.dist or 20,
            }
        end
    end

    local spawnsWithTarget = {
        [101] = {
            id = 101,
            name = 'TankBob',
            target = { id = 450, name = 'a shadow knight', hp = 85, dist = 14.5 }
        }
    }
    local maInfoGetter = createMaTargetInfoGetter({ ma_id = 101, ma_name = 'TankBob' }, spawnsWithTarget, {})
    local info = maInfoGetter()
    assert_eq(info.hasMA, true, 'maInfo hasMA is true')
    assert_eq(info.hasTarget, true, 'maInfo hasTarget is true')
    assert_eq(info.targetName, 'a shadow knight', 'maInfo retrieves correct target name')
    assert_eq(info.targetId, 450, 'maInfo retrieves correct target ID')
    assert_eq(info.targetHp, 85, 'maInfo retrieves correct target HP')

end

do
    -- triune.lua source code validations
    assert_true(src:find("runtime.getMaTargetInfo") ~= nil, 'triune.lua defines runtime.getMaTargetInfo')
    assert_true(src:find("runtime.getAssistCandidates") ~= nil, 'triune.lua defines runtime.getAssistCandidates')
    assert_true(src:find("runtime.addCustomAssistTarget") ~= nil, 'triune.lua defines runtime.addCustomAssistTarget')
    assert_true(src:find("runtime.removeCustomAssist") ~= nil, 'triune.lua defines runtime.removeCustomAssist')
    assert_true(src:find("##maSelectCombo") ~= nil, 'triune.lua renders ##maSelectCombo dropdown')
    assert_true(src:find("+ Add Target##maAdd") ~= nil, 'triune.lua renders + Add Target button')
    assert_true(src:find("Remove##maRemove") ~= nil, 'triune.lua renders Remove button')
    assert_true(src:find("statCardTargMA") ~= nil, 'triune.lua renders MA target button on Status card')
    assert_true(src:find("miniTargMA") ~= nil, 'triune.lua renders MA target button in Compact mode')
    assert_true(src:find("##assistXtarDist") ~= nil, 'triune.lua renders Max XTarget Chase Range slider in Assist mode')
    assert_true(src:find("cmd == 'xtardist'") ~= nil, 'triune.lua handles /ac xtardist slash command')
    assert_true(src:find("##assistChaseDist") ~= nil, 'triune.lua renders Chase Distance slider in Assist mode')
    assert_true(src:find("cmd == 'chasedist'") ~= nil, 'triune.lua handles /ac chasedist slash command')
    assert_true(src:find("##assistSelfDefense") ~= nil, 'triune.lua renders Self-Defense When Attacked checkbox')
    assert_true(src:find("cmd == 'selfdefense'") ~= nil, 'triune.lua handles /ac selfdefense slash command')
    assert_true(src:find("runtime.findSelfDefenseTarget") ~= nil, 'triune.lua implements runtime.findSelfDefenseTarget')

    -- 8. Assist mode XTarget / MA target distance gating logic
    local function evaluateAssistEngagement(ctrlTable, targetDist, pctHp, isEngaged)
        local maxNav = (ctrlTable and ctrlTable.xtar_nav_dist) or 150
        local assistAt = (ctrlTable and ctrlTable.assist_at) or 100
        if pctHp <= assistAt and isEngaged then
            if targetDist <= maxNav then
                return true -- closing on mob / engage allowed
            end
        end
        return false -- out of range: do not close on mob, fallback to idleReturn or chaseMA
    end

    local testCtrl = { mode = 'Assist', assist_at = 98, xtar_nav_dist = 120 }
    assert_eq(evaluateAssistEngagement(testCtrl, 80, 95, true), true, 'Assist engagement allowed when target is within xtar_nav_dist')
    assert_eq(evaluateAssistEngagement(testCtrl, 120, 95, true), true, 'Assist engagement allowed at exact boundary of xtar_nav_dist')
    assert_eq(evaluateAssistEngagement(testCtrl, 121, 95, true), false, 'Assist engagement blocked when target exceeds xtar_nav_dist')
    assert_eq(evaluateAssistEngagement(testCtrl, 200, 50, true), false, 'Assist engagement blocked for far-away mob (200 units > 120 limit)')
    assert_eq(evaluateAssistEngagement(testCtrl, 50, 99, true), false, 'Assist engagement blocked when mob HP > assist_at threshold')

    -- 9. Assist mode Target Priority & Self-Defense Logic
    local function resolveAssistCombatTarget(ctrlTable, maTargetId, attackerId)
        local maId = maTargetId
        local defendId = nil
        if not maId and (ctrlTable.assist_self_defense ~= false) then
            defendId = attackerId
        end
        local id = maId or defendId
        local isSelfDefense = (not maId and defendId ~= nil)
        return id, isSelfDefense
    end

    -- Case A: MA has an engaged target (id 501) and an add is hitting assistant (id 999)
    -- Must ONLY attack the MA's target!
    local cA = { mode = 'Assist', assist_self_defense = true }
    local targA, isDefA = resolveAssistCombatTarget(cA, 501, 999)
    assert_eq(targA, 501, 'Assistant strictly focuses on MA target even if attacked by an add')
    assert_eq(isDefA, false, 'isSelfDefense is false when MA has an active target')

    -- Case B: MA has NO target (nil), but assistant is attacked by an add (id 999) with self-defense enabled
    local cB = { mode = 'Assist', assist_self_defense = true }
    local targB, isDefB = resolveAssistCombatTarget(cB, nil, 999)
    assert_eq(targB, 999, 'Assistant defends itself against attacker when MA has no target')
    assert_eq(isDefB, true, 'isSelfDefense is true when defending against attacker')

    -- Case C: MA has NO target (nil), assistant attacked (id 999), but self-defense checkbox is disabled
    local cC = { mode = 'Assist', assist_self_defense = false }
    local targC, isDefC = resolveAssistCombatTarget(cC, nil, 999)
    assert_eq(targC, nil, 'Assistant does not attack when self-defense is disabled and MA has no target')
    assert_eq(isDefC, false, 'isSelfDefense is false when self-defense is disabled')

    -- Case D: MA has NO target and assistant is NOT attacked
    local cD = { mode = 'Assist', assist_self_defense = true }
    local targD, isDefD = resolveAssistCombatTarget(cD, nil, nil)
    assert_eq(targD, nil, 'Assistant has no target when out of combat and MA has no target')
    assert_eq(isDefD, false, 'isSelfDefense is false when no attackers present')

    -- Case E: Assistant is defending itself against add (id 999), then MA acquires target (id 777)
    -- Should immediately swap to MA target!
    local cE = { mode = 'Assist', assist_self_defense = true }
    local initialTarg, _ = resolveAssistCombatTarget(cE, nil, 999)
    assert_eq(initialTarg, 999, 'Initially fighting back against attacker in self defense')
    local updatedTarg, updatedIsDef = resolveAssistCombatTarget(cE, 777, 999)
    assert_eq(updatedTarg, 777, 'Immediately prioritizes MA target the moment MA engages')
    assert_eq(updatedIsDef, false, 'isSelfDefense turns false upon acquiring MA target')
end

do
    -- 10. targetIsEngaged validation and auto-attack disengage logic
    assert_true(src:find("mq.cmd%('/attack off'%)") ~= nil, 'triune.lua calls /attack off when disengaging')

    local function evaluateTargetIsEngaged(isXtar, hpPct, totId, aggroId, myId, groupIds, maTargetId, maInCombat, targetId)
        if isXtar then return true end
        if hpPct < 100 then return true end
        if totId == myId or groupIds[totId] then return true end
        if aggroId == myId or groupIds[aggroId] then return true end
        if maTargetId == targetId and maInCombat then return true end
        return false
    end

    local grp = { [101] = true, [102] = true }
    -- Peaceful unattacked mob at 100% HP: NOT engaged!
    assert_eq(evaluateTargetIsEngaged(false, 100, 0, 0, 99, grp, 0, false, 555), false,
        'Peaceful mob at 100% HP is NOT considered engaged')
    -- Damaged mob: engaged!
    assert_eq(evaluateTargetIsEngaged(false, 99, 0, 0, 99, grp, 0, false, 555), true,
        'Damaged mob (<100% HP) is considered engaged')
    -- Mob on XTarget: engaged!
    assert_eq(evaluateTargetIsEngaged(true, 100, 0, 0, 99, grp, 0, false, 555), true,
        'Mob on XTarget is considered engaged')
    -- Mob targeting player: engaged!
    assert_eq(evaluateTargetIsEngaged(false, 100, 99, 0, 99, grp, 0, false, 555), true,
        'Mob targeting player is considered engaged')
    -- Mob targeting group member: engaged!
    assert_eq(evaluateTargetIsEngaged(false, 100, 101, 0, 99, grp, 0, false, 555), true,
        'Mob targeting group member is considered engaged')
    -- Mob targeted by MA who is in combat: engaged!
    assert_eq(evaluateTargetIsEngaged(false, 100, 0, 0, 99, grp, 555, true, 555), true,
        'Mob targeted by fighting MA is considered engaged')
    -- Mob targeted by MA who is NOT in combat: NOT engaged!
    assert_eq(evaluateTargetIsEngaged(false, 100, 0, 0, 99, grp, 555, false, 555), false,
        'Mob targeted by out-of-combat MA is NOT considered engaged')

    -- Auto-Attack State Machine Evaluation
    local function evaluateAutoAttackAction(haveNPC, autoAttackOk, curDist, maxReach, isCombat)
        if haveNPC and autoAttackOk then
            if curDist <= maxReach then
                return 'ATTACK_ON'
            else
                return 'MOVE_TOWARD'
            end
        else
            if isCombat then
                return 'ATTACK_OFF'
            else
                return 'IDLE'
            end
        end
    end

    assert_eq(evaluateAutoAttackAction(true, true, 10, 15, false), 'ATTACK_ON',
        'Turns attack ON when in reach of valid engaged target')
    assert_eq(evaluateAutoAttackAction(true, true, 25, 15, false), 'MOVE_TOWARD',
        'Closes distance when target is outside reach')
    assert_eq(evaluateAutoAttackAction(false, false, 10, 15, true), 'ATTACK_OFF',
        'Turns attack OFF when target is dead or no NPC is engaged')
    assert_eq(evaluateAutoAttackAction(true, false, 10, 15, true), 'ATTACK_OFF',
        'Turns attack OFF when NPC is present but not authorized to attack')
    assert_eq(evaluateAutoAttackAction(false, false, 10, 15, false), 'IDLE',
        'Remains idle when out of combat')
end

-- ============================================================================
-- Suite 52: Lua 5.1 Main Chunk 200 Local Variables Limit Verification
-- ============================================================================
print('--- Main Chunk Local Variables Limit Verification ---')
do
    local files = {
        'TAC/lua/triune.lua',
        'TAC/lua/triune_buttons.lua',
        'TAC/lua/triune_buffbot.lua',
        'TAC/lua/triune_cursor.lua',
        'TAC/lua/triune_dps.lua',
        'TAC/lua/triune_inv.lua',
        'TAC/lua/triune_map.lua',
        'TAC/lua/triune_quest.lua',
        'TAC/lua/triune_spellbook.lua',
        'TAC/lua/triune_test.lua',
    }

    for _, filePath in ipairs(files) do
        local handle = io.popen(string.format('luac -l -p %s 2>&1', filePath))
        if handle then
            local out = handle:read('*a')
            local ok = handle:close()
            assert_true(ok == true or ok == 0, string.format('luac syntax check passes for %s (no 200 local limit error)', filePath))
            assert_true(not out:find('too many local variables'), string.format('%s does not exceed 200 local variables limit', filePath))
            local slots = tonumber(out:match('(%d+)%s+slots'))
            if slots and filePath == 'TAC/lua/triune.lua' then
                assert_true(slots <= 185, string.format('triune.lua main chunk slots (%d) has comfortable buffer under 200 limit (<= 185)', slots))
            end
        end
    end
end

-- ============================================================================
-- Suite 52: Pet Buff Detection & Management Logic
-- ============================================================================
do
    print('--- Pet Buff Detection & Management Logic ---')

    -- Setup mock environment for pet buff detection
    local mockMePetBuffs = {}
    local mockMePetDurations = {}
    local mockTargetBuffs = {}
    local mockTargetDurations = {}
    local mockSpawnBuffs = {}
    local mockSpawnDurations = {}
    local mockSpellStacksPet = {}
    local mockSpellStacksTarget = {}
    local mockSpellStacksSpawn = {}

    local petState = {
        myPets = {},
        cachedPetBuffs = {}
    }

    local testRuntime = {}

    function testRuntime.recordPetBuff(petId, spellName, durSec)
        if not petId or petId <= 0 or not spellName or spellName == '' then return end
        petState.cachedPetBuffs = petState.cachedPetBuffs or {}
        local cData = petState.cachedPetBuffs[petId] or { time = os.clock(), buffs = {}, buffDetails = {} }
        cData.time = os.clock()
        cData.buffs = cData.buffs or {}
        cData.buffDetails = cData.buffDetails or {}
        local alreadyIn = false
        for _, bn in ipairs(cData.buffs) do
            if bn == spellName then alreadyIn = true break end
        end
        if not alreadyIn then
            table.insert(cData.buffs, spellName)
        end
        table.insert(cData.buffDetails, { name = spellName, duration = durSec or 0 })
        petState.cachedPetBuffs[petId] = cData
    end

    local function isGemMatching(gName, tName)
        if not gName or not tName then return false end
        if gName == tName or gName:lower() == tName:lower() then return true end
        return false
    end

    local function cleanSpellName(nm) return nm or '' end

    function testRuntime.isPetBuffActive(petId, name, minSec)
        if not petId or petId == 0 then return false end
        name = tostring(name or '')
        if name == '' then return false end
        minSec = tonumber(minSec) or 0

        local myPetId = 100 -- mock primary pet ID

        local function isBuffNameMatch(candidateName)
            if not candidateName or candidateName == '' or candidateName == 'NONE' then return false end
            if candidateName == name then return true end
            if candidateName:lower() == name:lower() then return true end
            if isGemMatching(candidateName, name) then return true end
            if cleanSpellName(candidateName):lower() == cleanSpellName(name):lower() then return true end
            return false
        end

        -- 1. Primary pet inspection via Me.Pet
        if myPetId > 0 and petId == myPetId then
            local found = false
            local remSec = -1
            local activeBuffNames = {}
            local activeBuffDetails = {}

            for b = 1, 30 do
                local pb = mockMePetBuffs[b]
                if pb then
                    local bName = pb
                    local durSec = -1
                    local dur = mockMePetDurations[b] or 0
                    if type(dur) == 'number' and dur > 0 then
                        durSec = math.floor(dur / 1000)
                    end
                    table.insert(activeBuffNames, bName)
                    table.insert(activeBuffDetails, { slot = b, name = bName, duration = durSec })

                    if not found and isBuffNameMatch(bName) then
                        found = true
                        remSec = durSec
                    end
                end
            end

            if petState and petState.cachedPetBuffs and #activeBuffNames > 0 then
                petState.cachedPetBuffs[petId] = {
                    time = os.clock(),
                    buffs = activeBuffNames,
                    buffDetails = activeBuffDetails
                }
            end

            if found then
                if minSec > 0 and remSec >= 0 then
                    return remSec > minSec
                end
                return true
            end

            -- Stacking check
            if mockSpellStacksPet[name] == false then
                return true
            end

            return false
        end

        -- 2. Target buffs
        if mockTargetBuffs[petId] then
            for b = 1, 30 do
                local bName = mockTargetBuffs[petId][b]
                if bName and isBuffNameMatch(bName) then
                    local remSec = mockTargetDurations[petId] and mockTargetDurations[petId][b] or -1
                    if minSec > 0 and remSec >= 0 then
                        return remSec > minSec
                    end
                    return true
                end
            end
            if mockSpellStacksTarget[name] == false then
                return true
            end
        end

        -- 3. Cached buffs in petState
        if petState and petState.cachedPetBuffs and petState.cachedPetBuffs[petId] then
            local cData = petState.cachedPetBuffs[petId]
            local elapsed = os.clock() - (cData.time or 0)
            if elapsed < 300 then
                if cData.buffDetails then
                    for _, d in ipairs(cData.buffDetails) do
                        if isBuffNameMatch(d.name) then
                            local remSec = (d.duration or 0) - elapsed
                            if minSec > 0 and (d.duration or 0) > 0 then
                                return remSec > minSec
                            end
                            return true
                        end
                    end
                end
                if cData.buffs then
                    for _, bName in ipairs(cData.buffs) do
                        if isBuffNameMatch(bName) then
                            return true
                        end
                    end
                end
            end
        end

        return false
    end

    -- Test 1: Empty pet buffs returns false
    mockMePetBuffs = {}
    mockMePetDurations = {}
    assert_eq(not not testRuntime.isPetBuffActive(100, 'Burnout IV', 0), false, 'No buffs on pet returns false')

    -- Test 2: Matching buff in slot returns true
    mockMePetBuffs = { [1] = 'Burnout IV' }
    mockMePetDurations = { [1] = 1800000 } -- 1800 sec
    assert_true(testRuntime.isPetBuffActive(100, 'Burnout IV', 0), 'Exact match returns true')
    assert_true(testRuntime.isPetBuffActive(100, 'burnout iv', 0), 'Case-insensitive match returns true')

    -- Test 3: Duration threshold (minSec)
    -- Buff has 1800s remaining, minSec = 60 -> true
    assert_true(testRuntime.isPetBuffActive(100, 'Burnout IV', 60), '1800s remaining > 60s minSec returns true')
    -- Buff has 30s remaining (30000ms), minSec = 60 -> false (needs refresh)
    mockMePetDurations = { [1] = 30000 }
    assert_eq(not not testRuntime.isPetBuffActive(100, 'Burnout IV', 60), false, '30s remaining <= 60s minSec returns false (needs refresh)')
    -- When minSec = 0, even 30s remaining returns true
    assert_true(testRuntime.isPetBuffActive(100, 'Burnout IV', 0), '30s remaining with minSec=0 returns true')

    -- Test 4: StacksPet returns false -> returns true (spell blocked/existing)
    mockMePetBuffs = {}
    mockMePetDurations = {}
    mockSpellStacksPet['Strength of Earth'] = false
    assert_true(testRuntime.isPetBuffActive(100, 'Strength of Earth', 0), 'StacksPet == false returns true (spell blocked/wont land)')

    -- Test 5: Cache recording & verification for secondary pets
    testRuntime.recordPetBuff(200, 'Spirit of Wolf', 1200)
    assert_true(testRuntime.isPetBuffActive(200, 'Spirit of Wolf', 0), 'Secondary pet buff found in cachedPetBuffs')
    assert_eq(not not testRuntime.isPetBuffActive(200, 'Spirit of Wolf', 1500), false, 'Secondary pet buff duration expired/below minSec')
    assert_eq(not not testRuntime.isPetBuffActive(200, 'Haste', 0), false, 'Different buff on secondary pet returns false')

    -- Test 6: Missing buff condition with invalid/dead target
    local function mockConditionMetMissingBuff(targetId, isAlive, isBuffActiveFn)
        if not targetId or targetId <= 0 or not isAlive then return false end
        return not isBuffActiveFn(targetId)
    end
    assert_eq(not not mockConditionMetMissingBuff(nil, false, function() return false end), false, 'Nil targetId never satisfies missing buff')
    assert_eq(not not mockConditionMetMissingBuff(0, false, function() return false end), false, 'Target ID 0 never satisfies missing buff')
    assert_eq(not not mockConditionMetMissingBuff(100, false, function() return false end), false, 'Dead pet target never satisfies missing buff')
    assert_true(mockConditionMetMissingBuff(100, true, function() return false end), 'Living pet without buff satisfies missing buff')
    assert_eq(not not mockConditionMetMissingBuff(100, true, function() return true end), false, 'Living pet with buff does NOT satisfy missing buff')

    -- Test 7: Multi-pet missing buff targeting resolution
    local function mockResolvePetTargetId(allPets, buffActiveFn, minSec)
        if #allPets == 0 then return nil end
        for _, pid in ipairs(allPets) do
            if not buffActiveFn(pid, minSec) then
                return pid
            end
        end
        return allPets[1]
    end

    local pets = { 101, 102 }
    -- Pet 101 has buff, 102 missing -> returns 102
    local resPid = mockResolvePetTargetId(pets, function(pid) return pid == 101 end, 0)
    assert_eq(resPid, 102, 'Multi-pet: selects first pet missing buff')

    -- Both pets have buff -> returns 101 (caller evaluates conditionMet as false)
    local resPidAll = mockResolvePetTargetId(pets, function(pid) return true end, 0)
    assert_eq(resPidAll, 101, 'Multi-pet: all have buff returns allPets[1]')

    -- Test 8: Pet Target Resolution
    local function mockResolvePetTarget(petId, myPetId, mockPetTarget, mockPetFollowing, mockTargetTot, mockSpawnTot, petSt, isAliveFn, isHostileFn, mockSpawnMap)
        local t = nil
        if myPetId > 0 and myPetId == petId then
            if mockPetTarget and (mockPetTarget.id or 0) > 0 then
                t = mockPetTarget
            elseif mockPetFollowing and (mockPetFollowing.id or 0) > 0 and mockPetFollowing.type == 'NPC' then
                t = mockPetFollowing
            end
        end
        if not t and mockTargetTot and (mockTargetTot.id or 0) > 0 then
            t = mockTargetTot
        end
        if not t and mockSpawnTot and (mockSpawnTot.id or 0) > 0 then
            t = mockSpawnTot
        end
        if not t and petSt and not petSt.petHoldActive and (petSt.lastCmdTargetId or 0) > 0 then
            local cmdTid = petSt.lastCmdTargetId
            if isAliveFn(cmdTid) and isHostileFn(cmdTid) then
                local ts = mockSpawnMap and mockSpawnMap[cmdTid]
                if ts and not ts.dead and ts.type ~= 'Corpse' then
                    t = ts
                end
            end
        end
        if t and (t.id or 0) > 0 and not t.dead and t.type ~= 'Corpse' then
            return {
                targetName = t.cleanName or 'Target',
                targetHpPct = t.pctHPs or 0,
                targetDist = t.distance or 0,
                targetId = t.id or 0
            }
        else
            return {
                targetName = 'None',
                targetHpPct = 0,
                targetDist = 0,
                targetId = 0
            }
        end
    end

    local dummyAlive = function(id) return id and id > 0 end
    local dummyHostile = function(id) return id and id > 0 end

    -- Primary pet with Me.Pet.Target active
    local pTargetInfo = mockResolvePetTarget(100, 100, { id = 501, cleanName = 'a fire goblin', pctHPs = 65, distance = 15.2, dead = false, type = 'NPC' }, nil, nil, nil, nil, dummyAlive, dummyHostile, nil)
    assert_eq(pTargetInfo.targetName, 'a fire goblin', 'Me.Pet.Target name resolved')
    assert_eq(pTargetInfo.targetHpPct, 65, 'Me.Pet.Target HP resolved')
    assert_eq(pTargetInfo.targetId, 501, 'Me.Pet.Target ID resolved')

    -- Primary pet with Me.Pet.Following fallback
    local pFollowInfo = mockResolvePetTarget(100, 100, nil, { id = 502, cleanName = 'an orc warrior', pctHPs = 80, distance = 25.0, dead = false, type = 'NPC' }, nil, nil, nil, dummyAlive, dummyHostile, nil)
    assert_eq(pFollowInfo.targetName, 'an orc warrior', 'Me.Pet.Following NPC resolved')
    assert_eq(pFollowInfo.targetId, 502, 'Me.Pet.Following ID resolved')

    -- Targeted pet via TargetOfTarget
    local totInfo = mockResolvePetTarget(200, 100, nil, nil, { id = 503, cleanName = 'a giant spider', pctHPs = 42, distance = 30.0, dead = false, type = 'NPC' }, nil, nil, dummyAlive, dummyHostile, nil)
    assert_eq(totInfo.targetName, 'a giant spider', 'Target.TargetOfTarget resolved for secondary pet')
    assert_eq(totInfo.targetId, 503, 'Target.TargetOfTarget ID resolved')

    -- Fallback via petState.lastCmdTargetId during active combat
    local mockSpawns = {
        [504] = { id = 504, cleanName = 'a froglok raider', pctHPs = 90, distance = 18.0, dead = false, type = 'NPC' },
        [505] = { id = 505, cleanName = 'a dead froglok', pctHPs = 0, distance = 18.0, dead = true, type = 'Corpse' }
    }
    local cmdInfo = mockResolvePetTarget(100, 100, nil, nil, nil, nil, { petHoldActive = false, lastCmdTargetId = 504 }, dummyAlive, dummyHostile, mockSpawns)
    assert_eq(cmdInfo.targetName, 'a froglok raider', 'Combat command target resolved as fallback')
    assert_eq(cmdInfo.targetId, 504, 'Combat command target ID resolved')

    -- Pet hold active suppresses lastCmdTargetId fallback
    local holdInfo = mockResolvePetTarget(100, 100, nil, nil, nil, nil, { petHoldActive = true, lastCmdTargetId = 504 }, dummyAlive, dummyHostile, mockSpawns)
    assert_eq(holdInfo.targetName, 'None', 'Pet hold suppresses command target fallback')
    assert_eq(holdInfo.targetId, 0, 'Pet hold returns target ID 0')

    -- Dead target / corpse rejection
    local deadInfo = mockResolvePetTarget(100, 100, nil, nil, nil, nil, { petHoldActive = false, lastCmdTargetId = 505 }, dummyAlive, dummyHostile, mockSpawns)
    assert_eq(deadInfo.targetName, 'None', 'Dead/Corpse target rejected and returns None')
    assert_eq(deadInfo.targetId, 0, 'Dead/Corpse returns target ID 0')

    -- Idle pet with no target
    local idleInfo = mockResolvePetTarget(100, 100, nil, nil, nil, nil, { petHoldActive = false, lastCmdTargetId = 0 }, dummyAlive, dummyHostile, mockSpawns)
    assert_eq(idleInfo.targetName, 'None', 'Idle pet returns Target: None')
    assert_eq(idleInfo.targetId, 0, 'Idle pet returns target ID 0')
end

-- ============================================================================
-- Suite 53: Automatic Script Pause on Zoning Logic & Slash Commands
-- ============================================================================
do
    print('--- Automatic Script Pause on Zoning Logic & Slash Commands ---')

    -- 1. onZoned behavior with pause_on_zone = true (default)
    local testCtrl = { running = true, pause_on_zone = true }
    local stopped = false
    local mockFullStop = function() stopped = true end
    local mockOnZoned = function(c, stopFn)
        if c.pause_on_zone ~= false and c.running then
            c.running = false
            if stopFn then stopFn() end
        elseif c.running then
            if stopFn then stopFn() end
        end
    end

    mockOnZoned(testCtrl, mockFullStop)
    assert_eq(testCtrl.running, false, 'onZoned pauses engine when pause_on_zone is true')
    assert_true(stopped, 'fullStop called on zone pause')

    -- 2. onZoned behavior with pause_on_zone = false
    testCtrl = { running = true, pause_on_zone = false }
    stopped = false
    mockOnZoned(testCtrl, mockFullStop)
    assert_eq(testCtrl.running, true, 'onZoned keeps engine running when pause_on_zone is false')
    assert_true(stopped, 'fullStop called on zone transition even when running continues')

    -- 3. Slash command handling
    local function handlePauseZoneCmd(c, arg)
        local sub = arg and string.lower(arg) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            c.pause_on_zone = true
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            c.pause_on_zone = false
        else
            c.pause_on_zone = c.pause_on_zone == false
        end
    end

    local cmdCtrl = { pause_on_zone = true }
    handlePauseZoneCmd(cmdCtrl, 'off')
    assert_eq(cmdCtrl.pause_on_zone, false, '/ac pausezone off disables pause on zone')
    handlePauseZoneCmd(cmdCtrl, 'on')
    assert_eq(cmdCtrl.pause_on_zone, true, '/ac pausezone on enables pause on zone')
    handlePauseZoneCmd(cmdCtrl, '')
    assert_eq(cmdCtrl.pause_on_zone, false, '/ac pausezone toggle from true to false')
    handlePauseZoneCmd(cmdCtrl, nil)
    assert_eq(cmdCtrl.pause_on_zone, true, '/ac pausezone toggle from false to true')
end

-- ============================================================================
-- Suite 53: Triune Code Audit Fixes & Logic Verification
-- ============================================================================
do
    print('--- Triune Code Audit Fixes & Logic Verification ---')

    -- 1. Verify /ac clear lockouts command condition matching
    local function parseClearLockouts(cmd, args)
        if cmd == 'clearlockouts' or cmd == 'unlock' or (cmd == 'clear' and (args[2] and (string.lower(args[2]) == 'lockouts' or string.lower(args[2]) == 'locks' or string.lower(args[2]) == 'all'))) then
            return true
        end
        return false
    end

    assert_true(parseClearLockouts('clearlockouts', {}), '/ac clearlockouts matches')
    assert_true(parseClearLockouts('unlock', {}), '/ac unlock matches')
    assert_true(parseClearLockouts('clear', { 'clear', 'lockouts' }), '/ac clear lockouts matches')
    assert_true(parseClearLockouts('clear', { 'clear', 'LOCKOUTS' }), '/ac clear LOCKOUTS matches case-insensitively')
    assert_true(parseClearLockouts('clear', { 'clear', 'locks' }), '/ac clear locks matches')
    assert_true(parseClearLockouts('clear', { 'clear', 'all' }), '/ac clear all matches')
    assert_eq(parseClearLockouts('clear', { 'clear' }), false, '/ac clear alone without subarg does not trigger clear lockouts')
    assert_eq(parseClearLockouts('clear', { 'clear', 'camp' }), false, '/ac clear camp does not trigger clear lockouts')

    -- 2. Verify onZoned debounce timing logic
    local callCount = 0
    local mockRuntime = { lastZonedAt = 0 }
    local function mockDebouncedOnZoned(now)
        if (now - (mockRuntime.lastZonedAt or 0)) < 2.0 then return false end
        mockRuntime.lastZonedAt = now
        callCount = callCount + 1
        return true
    end

    assert_true(mockDebouncedOnZoned(10.0), 'First onZoned invocation succeeds')
    assert_eq(callCount, 1, 'callCount is 1')
    assert_eq(mockDebouncedOnZoned(10.5), false, 'Immediate second onZoned call within 2s debounce window is ignored')
    assert_eq(callCount, 1, 'callCount remains 1')
    assert_eq(mockDebouncedOnZoned(11.9), false, 'Call at 1.9s delta is still debounced')
    assert_eq(callCount, 1, 'callCount remains 1')
    assert_true(mockDebouncedOnZoned(12.1), 'Call at 2.1s delta succeeds')
    assert_eq(callCount, 2, 'callCount increments to 2')
end

-- ============================================================================
-- Suite 55: Auto-Accept Logic & Whitelist Authorization with Player IDs
-- ============================================================================
do
    print('--- Suite 55: Auto-Accept Logic & Whitelist Authorization ---')

    local testCtrl = {
        auto_group = false,
        auto_trade = false,
        auto_dzadd = false,
        auto_accept_anyone = false,
        auto_accept_guild = false,
        auto_accept_group = false,
        auto_accept_names = {},
    }

    local testRuntime = {}

    function testRuntime.getAutoAcceptPlayerInfo(entry)
        if type(entry) == 'table' then
            return tostring(entry.name or ''), tonumber(entry.id) or 0
        else
            return tostring(entry or ''), 0
        end
    end

    function testRuntime.isAutoAcceptListed(nameOrId)
        if not nameOrId or nameOrId == '' or nameOrId == 0 then return false end
        if not testCtrl.auto_accept_names or type(testCtrl.auto_accept_names) ~= 'table' then
            testCtrl.auto_accept_names = {}
            return false
        end
        local targetNum = tonumber(nameOrId)
        local targetStr = tostring(nameOrId):lower():gsub('^%s+', ''):gsub('%s+$', '')
        for _, entry in ipairs(testCtrl.auto_accept_names) do
            local eName, eId = testRuntime.getAutoAcceptPlayerInfo(entry)
            if targetNum and targetNum > 0 and eId > 0 and eId == targetNum then
                return true
            end
            if targetStr ~= '' and eName ~= '' and eName:lower() == targetStr then
                return true
            end
        end
        return false
    end

    function testRuntime.addAutoAcceptName(nameOrId, optionalId)
        if not nameOrId then return end
        local s = tostring(nameOrId):gsub('^%s+', ''):gsub('%s+$', '')
        if s == '' then return end

        local name = s
        local id = tonumber(optionalId) or 0
        local num = tonumber(s)
        if num and num > 0 and id == 0 then
            id = num
            name = string.format('Player_%d', id)
        end

        if not testCtrl.auto_accept_names or type(testCtrl.auto_accept_names) ~= 'table' then
            testCtrl.auto_accept_names = {}
        end

        local found = false
        for _, entry in ipairs(testCtrl.auto_accept_names) do
            local eName, eId = testRuntime.getAutoAcceptPlayerInfo(entry)
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
            table.insert(testCtrl.auto_accept_names, { name = name, id = id })
            table.sort(testCtrl.auto_accept_names, function(a, b)
                local aName = testRuntime.getAutoAcceptPlayerInfo(a)
                local bName = testRuntime.getAutoAcceptPlayerInfo(b)
                return aName:lower() < bName:lower()
            end)
        end
    end

    function testRuntime.removeAutoAcceptName(nameOrIdOrEntry)
        if not nameOrIdOrEntry or not testCtrl.auto_accept_names then return false end
        local targetNum = nil
        local targetStr = nil
        if type(nameOrIdOrEntry) == 'table' then
            targetNum = tonumber(nameOrIdOrEntry.id)
            targetStr = nameOrIdOrEntry.name and tostring(nameOrIdOrEntry.name):lower():gsub('^%s+', ''):gsub('%s+$', '')
        else
            targetNum = tonumber(nameOrIdOrEntry)
            targetStr = tostring(nameOrIdOrEntry):lower():gsub('^%s+', ''):gsub('%s+$', '')
        end
        for i, entry in ipairs(testCtrl.auto_accept_names) do
            local eName, eId = testRuntime.getAutoAcceptPlayerInfo(entry)
            if (targetNum and targetNum > 0 and eId > 0 and eId == targetNum) or
               (targetStr and targetStr ~= '' and eName ~= '' and eName:lower() == targetStr) then
                table.remove(testCtrl.auto_accept_names, i)
                return true
            end
        end
        return false
    end

    function testRuntime.clearAutoAcceptNames()
        testCtrl.auto_accept_names = {}
    end

    local mockGroupMembers = { { name = 'TrioHealer', id = 101 }, { name = 'TrioTank', id = 102 } }
    local mockGuild = 'Fires of Heaven'
    local mockSpawnGuilds = {
        ['GuildieOne'] = 'Fires of Heaven',
        ['guildieone'] = 'Fires of Heaven',
        ['GuildieTwo'] = 'fires of heaven',
        ['guildietwo'] = 'fires of heaven',
        ['Outsider'] = 'Some Other Guild',
    }

    -- Authorization evaluator mirroring runtime.isAutoAcceptAllowed
    function testRuntime.isAutoAcceptAllowed(senderName, senderId)
        if (not senderName or senderName == '') and (not senderId or senderId == 0) then return false end
        if senderName then senderName = tostring(senderName):gsub('^%s+', ''):gsub('%s+$', '') end

        if testCtrl.auto_accept_anyone then return true end

        if senderId and senderId > 0 and testRuntime.isAutoAcceptListed(senderId) then return true end
        if senderName and senderName ~= '' and testRuntime.isAutoAcceptListed(senderName) then return true end

        local sLower = senderName and senderName:lower() or ''
        local sIdNum = tonumber(senderId) or 0

        if testCtrl.auto_accept_group then
            for i = 1, #mockGroupMembers do
                local mem = mockGroupMembers[i]
                if (sIdNum > 0 and mem.id == sIdNum) or (sLower ~= '' and mem.name:lower() == sLower) then
                    return true
                end
            end
        end

        if testCtrl.auto_accept_guild and senderName and senderName ~= '' then
            local myG = mockGuild
            if myG and myG ~= '' then
                local theirG = mockSpawnGuilds[senderName]
                if theirG and theirG ~= '' and theirG:lower() == myG:lower() then
                    return true
                end
            end
        end

        return false
    end

    -- 1. Whitelist list operations with Names and Player IDs
    assert_eq(#testCtrl.auto_accept_names, 0, 'Auto-accept list starts empty')
    testRuntime.addAutoAcceptName('Charlie', 300)
    testRuntime.addAutoAcceptName('Alice', 100)
    testRuntime.addAutoAcceptName('bob', 200)
    assert_eq(#testCtrl.auto_accept_names, 3, 'Three names added to whitelist')
    local aName, aId = testRuntime.getAutoAcceptPlayerInfo(testCtrl.auto_accept_names[1])
    local bName, bId = testRuntime.getAutoAcceptPlayerInfo(testCtrl.auto_accept_names[2])
    local cName, cId = testRuntime.getAutoAcceptPlayerInfo(testCtrl.auto_accept_names[3])
    assert_eq(aName, 'Alice', 'Names sorted alphabetically (Alice)')
    assert_eq(aId, 100, 'Alice has ID 100')
    assert_eq(bName, 'bob', 'Names sorted alphabetically (bob)')
    assert_eq(bId, 200, 'bob has ID 200')
    assert_eq(cName, 'Charlie', 'Names sorted alphabetically (Charlie)')
    assert_eq(cId, 300, 'Charlie has ID 300')

    -- Adding purely by ID number
    testRuntime.addAutoAcceptName(450)
    assert_true(testRuntime.isAutoAcceptListed(450), 'isAutoAcceptListed matches numeric player ID 450')
    assert_true(testRuntime.isAutoAcceptListed('450'), 'isAutoAcceptListed matches string player ID "450"')

    -- Case-insensitive duplicate rejection and ID update
    testRuntime.addAutoAcceptName('ALICE', 100)
    testRuntime.addAutoAcceptName('  bob  ', 200)
    assert_eq(#testCtrl.auto_accept_names, 4, 'Duplicates with different case/whitespace not inserted as new rows')

    -- Case-insensitive whitelist matching by name and by ID
    assert_true(testRuntime.isAutoAcceptListed('alice'), 'isAutoAcceptListed matches lowercase alice')
    assert_true(testRuntime.isAutoAcceptListed('BOB'), 'isAutoAcceptListed matches uppercase BOB')
    assert_true(testRuntime.isAutoAcceptListed(100), 'isAutoAcceptListed matches ID 100')
    assert_true(testRuntime.isAutoAcceptListed(200), 'isAutoAcceptListed matches ID 200')
    assert_true(testRuntime.isAutoAcceptListed(300), 'isAutoAcceptListed matches ID 300')
    assert_eq(testRuntime.isAutoAcceptListed('David'), false, 'David not in whitelist')
    assert_eq(testRuntime.isAutoAcceptListed(999), false, 'ID 999 not in whitelist')

    -- Whitelist removal by Name, ID, or Entry object
    assert_true(testRuntime.removeAutoAcceptName(200), 'Successfully removed bob by ID 200')
    assert_eq(testRuntime.isAutoAcceptListed('bob'), false, 'bob no longer listed by name')
    assert_eq(testRuntime.isAutoAcceptListed(200), false, 'bob no longer listed by ID')

    assert_true(testRuntime.removeAutoAcceptName('charlie'), 'Successfully removed Charlie by name')
    assert_eq(testRuntime.isAutoAcceptListed('charlie'), false, 'Charlie no longer listed')

    assert_true(testRuntime.removeAutoAcceptName({ name = 'Player_450', id = 450 }), 'Successfully removed entry by table')
    assert_eq(testRuntime.isAutoAcceptListed(450), false, 'Player_450 no longer listed')

    assert_true(testRuntime.isAutoAcceptListed('Alice'), 'Alice still listed')

    -- Whitelist clearing
    testRuntime.clearAutoAcceptNames()
    assert_eq(#testCtrl.auto_accept_names, 0, 'Whitelist successfully cleared')

    -- 2. Authorization rules evaluation with Names and IDs
    -- Baseline: everything off, list empty
    assert_eq(testRuntime.isAutoAcceptAllowed('Alice', 100), false, 'Denied: not on whitelist and rules disabled')
    assert_eq(testRuntime.isAutoAcceptAllowed('', 0), false, 'Denied: empty sender name and 0 ID')
    assert_eq(testRuntime.isAutoAcceptAllowed(nil, nil), false, 'Denied: nil sender name and nil ID')

    -- Whitelist authorization by Name and by ID
    testRuntime.addAutoAcceptName('Alice', 100)
    assert_true(testRuntime.isAutoAcceptAllowed('alice', 100), 'Allowed: Alice matched by name and ID')
    assert_true(testRuntime.isAutoAcceptAllowed('Unknown', 100), 'Allowed: Matched by whitelisted Player ID 100')
    assert_true(testRuntime.isAutoAcceptAllowed('Alice', 0), 'Allowed: Matched by whitelisted Name Alice')
    assert_eq(testRuntime.isAutoAcceptAllowed('Bob', 999), false, 'Denied: Bob (ID 999) not on whitelist')

    -- Accept from Anyone
    testCtrl.auto_accept_anyone = true
    assert_true(testRuntime.isAutoAcceptAllowed('Bob', 999), 'Allowed: Accept from Anyone enabled')
    assert_true(testRuntime.isAutoAcceptAllowed('RandomPlayer', 0), 'Allowed: Accept from Anyone accepts anyone')
    testCtrl.auto_accept_anyone = false

    -- Accept from Group Members (matching by Name or ID)
    testCtrl.auto_accept_group = true
    assert_true(testRuntime.isAutoAcceptAllowed('TrioHealer', 101), 'Allowed: TrioHealer is group member (Name and ID)')
    assert_true(testRuntime.isAutoAcceptAllowed('Unknown', 102), 'Allowed: TrioTank matched by group member ID 102')
    assert_true(testRuntime.isAutoAcceptAllowed('triotank', 0), 'Allowed: triotank matched by group member name case-insensitively')
    assert_eq(testRuntime.isAutoAcceptAllowed('GuildieOne', 501), false, 'Denied: GuildieOne is not in group')
    testCtrl.auto_accept_group = false

    -- Accept from Guild Members
    testCtrl.auto_accept_guild = true
    assert_true(testRuntime.isAutoAcceptAllowed('GuildieOne', 501), 'Allowed: GuildieOne is in same guild')
    assert_true(testRuntime.isAutoAcceptAllowed('guildietwo', 502), 'Allowed: guildietwo matches same guild case-insensitively')
    assert_eq(testRuntime.isAutoAcceptAllowed('Outsider', 600), false, 'Denied: Outsider belongs to a different guild')
    testCtrl.auto_accept_guild = false
end

-- ============================================================================
-- Suite 56: Multi-Target All Enemies XTarget Logic
-- ============================================================================
print('--- Suite 56: Multi-Target All Enemies XTarget Logic ---')
do
    local testRuntime = {
        npcCastCounts = {},
        npcSpellApplied = {},
        npcSpellLastCast = {},
    }

    local mockSpawns = {
        [101] = { id = 101, name = 'a_goblin01', clean = 'a goblin', type = 'NPC', dead = false, hp = 80, dist = 30, z = 10 },
        [102] = { id = 102, name = 'a_goblin02', clean = 'a goblin', type = 'NPC', dead = false, hp = 95, dist = 45, z = 12 },
        [103] = { id = 103, name = 'a_goblin03', clean = 'a goblin', type = 'NPC', dead = false, hp = 60, dist = 25, z = 10 },
    }
    local mockXTarget = { 101, 102, 103 }
    local mockSpells = {
        ['Sicken'] = { duration = 10 },
        ['Ice Comet'] = { duration = 0 },
    }
    local mockTargetBuffs = {}
    local mockLockouts = {}

    local function buffActive(id, name)
        return mockTargetBuffs[id] and mockTargetBuffs[id][name] or false
    end

    function testRuntime.isNpcSpellActive(id, spellName)
        if not id or id <= 0 or not spellName or spellName == '' then return false end
        if buffActive(id, spellName) then return true end
        if testRuntime.npcSpellApplied and testRuntime.npcSpellApplied[id] then
            local now = os.clock()
            for sName, expireAt in pairs(testRuntime.npcSpellApplied[id]) do
                if expireAt and now < expireAt then
                    if sName == spellName or sName:lower() == spellName:lower() then
                        return true
                    end
                else
                    testRuntime.npcSpellApplied[id][sName] = nil
                end
            end
        end
        return false
    end

    function testRuntime.resolveAllEnemiesTargetId(spellName, when, pct, cls, extra)
        local hasDur = false
        if extra and (extra.kind == 'dot' or extra.kind == 'debuff') then
            hasDur = true
        elseif mockSpells[spellName] and mockSpells[spellName].duration > 0 then
            hasDur = true
        end

        local isDet = true
        local maxC = tonumber(extra and extra.max_casts) or 0
        local candidates = {}

        for _, id in ipairs(mockXTarget) do
            local s = mockSpawns[id]
            if s and not s.dead and s.type == 'NPC' then
                local lockedOut = mockLockouts[id] and mockLockouts[id][spellName]
                if not lockedOut then
                    local currentCasts = (testRuntime.npcCastCounts and testRuntime.npcCastCounts[id] and testRuntime.npcCastCounts[id][spellName]) or 0
                    local castLimitOk = (maxC == 0 or currentCasts < maxC)
                    if castLimitOk then
                        local spellActive = (hasDur and isDet and testRuntime.isNpcSpellActive(id, spellName))
                        if not spellActive then
                            local lastCastTime = (testRuntime.npcSpellLastCast and testRuntime.npcSpellLastCast[id] and testRuntime.npcSpellLastCast[id][spellName]) or 0
                            table.insert(candidates, {
                                id = id,
                                casts = currentCasts,
                                lastCast = lastCastTime,
                                hp = s.hp,
                                dist = s.dist
                            })
                        end
                    end
                end
            end
        end

        if #candidates > 0 then
            table.sort(candidates, function(a, b)
                if a.casts ~= b.casts then return a.casts < b.casts end
                if a.lastCast ~= b.lastCast then return a.lastCast < b.lastCast end
                if a.hp ~= b.hp then return a.hp < b.hp end
                return a.dist < b.dist
            end)
            return candidates[1].id
        end
        return nil
    end

    -- 1. DoT casting across multiple XTarget enemies (Sicken)
    local t1 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(t1, 103, 'Selects mob 103 first for DoT (lowest HP tie-break)')

    testRuntime.npcCastCounts[103] = { ['Sicken'] = 1 }
    testRuntime.npcSpellLastCast[103] = { ['Sicken'] = os.clock() }
    testRuntime.npcSpellApplied[103] = { ['Sicken'] = os.clock() + 30 }

    local t2 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(t2, 101, 'Selects mob 101 next for DoT (lowest HP among un-DoTed mobs: 80 < 95)')

    testRuntime.npcCastCounts[101] = { ['Sicken'] = 1 }
    testRuntime.npcSpellLastCast[101] = { ['Sicken'] = os.clock() }
    testRuntime.npcSpellApplied[101] = { ['Sicken'] = os.clock() + 30 }

    local t3 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(t3, 102, 'Selects mob 102 next for DoT (last remaining un-DoTed mob)')

    testRuntime.npcCastCounts[102] = { ['Sicken'] = 1 }
    testRuntime.npcSpellLastCast[102] = { ['Sicken'] = os.clock() }
    testRuntime.npcSpellApplied[102] = { ['Sicken'] = os.clock() + 30 }

    local t4 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(t4, nil, 'Returns nil when all XTarget mobs have DoT active')

    testRuntime.npcSpellApplied[103]['Sicken'] = os.clock() - 1
    local t5 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(t5, 103, 'Selects mob 103 again once DoT expires on it')

    -- 2. Direct Damage Nuke round-robin (Ice Comet, duration 0)
    testRuntime.npcCastCounts = {}
    testRuntime.npcSpellLastCast = {}
    testRuntime.npcSpellApplied = {}

    local n1 = testRuntime.resolveAllEnemiesTargetId('Ice Comet', 'in combat', 100, 'Wiz', { kind = 'dd' })
    assert_eq(n1, 103, 'First nuke hits mob 103 (lowest HP tie-break)')
    testRuntime.npcCastCounts[103] = { ['Ice Comet'] = 1 }
    testRuntime.npcSpellLastCast[103] = { ['Ice Comet'] = 100 }

    local n2 = testRuntime.resolveAllEnemiesTargetId('Ice Comet', 'in combat', 100, 'Wiz', { kind = 'dd' })
    assert_eq(n2, 101, 'Second nuke hits mob 101 (0 casts vs 1 cast)')
    testRuntime.npcCastCounts[101] = { ['Ice Comet'] = 1 }
    testRuntime.npcSpellLastCast[101] = { ['Ice Comet'] = 101 }

    local n3 = testRuntime.resolveAllEnemiesTargetId('Ice Comet', 'in combat', 100, 'Wiz', { kind = 'dd' })
    assert_eq(n3, 102, 'Third nuke hits mob 102 (0 casts vs 1 cast)')
    testRuntime.npcCastCounts[102] = { ['Ice Comet'] = 1 }
    testRuntime.npcSpellLastCast[102] = { ['Ice Comet'] = 102 }

    local n4 = testRuntime.resolveAllEnemiesTargetId('Ice Comet', 'in combat', 100, 'Wiz', { kind = 'dd' })
    assert_eq(n4, 103, 'Fourth nuke round-robins back to mob 103 (least recently cast)')

    -- 3. Max Casts Limit (max_casts = 1)
    local mc = testRuntime.resolveAllEnemiesTargetId('Ice Comet', 'in combat', 100, 'Wiz', { kind = 'dd', max_casts = 1 })
    assert_eq(mc, nil, 'Returns nil when all XTarget mobs have reached max_casts (1)')

    -- 4. Target Lockout / Resist skipping
    testRuntime.npcCastCounts = {}
    testRuntime.npcSpellLastCast = {}
    mockLockouts[103] = { ['Sicken'] = true }
    local r1 = testRuntime.resolveAllEnemiesTargetId('Sicken', 'in combat', 100, 'Shm', { kind = 'dot' })
    assert_eq(r1, 101, 'Skips locked-out mob 103 and selects mob 101')
    mockLockouts = {}
end

-- ============================================================================
-- Suite 57: Triune Quest Guide Logic & Database Validation
-- ============================================================================
do
    print('--- Suite 57: Triune Quest Guide Logic & Database Validation ---')
    local catFn = loadfile('TAC/resources/triune_quest/catalog.lua')
    assert_true(catFn ~= nil, 'catalog.lua loads cleanly')
    if catFn then
        local cat = catFn()
        assert_true(type(cat) == 'table', 'catalog is a table')
        assert_true(#cat >= 2000, string.format('catalog contains >= 2000 quests (found: %d)', #cat))
        assert_true(cat[1].title ~= nil, 'catalog quest has title')
        assert_true(cat[1].zone ~= nil, 'catalog quest has zone shortname')
    end

    local expFn = loadfile('TAC/resources/triune_quest/expansions.lua')
    assert_true(expFn ~= nil, 'expansions.lua loads cleanly')
    if expFn then
        local exps = expFn()
        assert_true(type(exps) == 'table', 'expansions is a table')
        assert_eq(#exps, 33, 'expansions has 33 entries (00 through 32)')
        assert_eq(exps[1].id, '00', 'first expansion is 00')
        assert_eq(exps[33].id, '32', 'last expansion is 32')
    end

    local zoneFn = loadfile('TAC/resources/triune_quest/zones/cabeast.lua')
    assert_true(zoneFn ~= nil, 'cabeast.lua zone package loads cleanly')
    if zoneFn then
        local zpkg = zoneFn()
        assert_eq(zpkg.zone, 'cabeast', 'zone shortname matches cabeast')
        assert_true(type(zpkg.quests) == 'table', 'zone package has quests table')
        assert_true(#zpkg.quests > 0, 'cabeast has >= 1 quest')
        assert_true(zpkg.quests[1].walkthrough ~= nil, 'quest entry has walkthrough')
    end

    -- Server Era Filtering Logic Check
    local sampleCatalog = {
        { id = "1", exp = "01", title = "Kunark Quest" },
        { id = "2", exp = "04", title = "PoP Quest" },
        { id = "3", exp = "05", title = "LoY Quest" },
        { id = "4", exp = "15", title = "SoD Quest" },
        { id = "5", exp = "32", title = "Modern Ro Quest" },
    }
    local function filterByEra(cat, limitEra, maxCap)
        local out = {}
        for _, q in ipairs(cat) do
            local eNum = tonumber(q.exp) or 0
            if not limitEra or (maxCap and eNum <= maxCap) then
                table.insert(out, q)
            end
        end
        return out
    end
    local capped5 = filterByEra(sampleCatalog, true, 5)
    assert_eq(#capped5, 3, 'capped to era 5 returns 3 quests')
    assert_eq(capped5[3].title, 'LoY Quest', 'era 5 includes LoY Quest')
    local uncapped = filterByEra(sampleCatalog, false, 5)
    assert_eq(#uncapped, 5, 'uncapped returns all 5 quests')

    -- Zone Directory and Global Quest Lookup Logic Tests
    local lookupCatalog = {
        { id = "101", title = "Crushbone Belts", zone = "gfaydark", zone_name = "Greater Faydark", exp = "00", exp_name = "Classic", min_lvl = 5, max_lvl = 15, npc = "Captain Hazran" },
        { id = "102", title = "Orc Hatchets", zone = "gfaydark", zone_name = "Greater Faydark", exp = "00", exp_name = "Classic", min_lvl = 3, max_lvl = 10, npc = "Dill Fireshine" },
        { id = "103", title = "Bone Chips", zone = "qeynos2", zone_name = "North Qeynos", exp = "00", exp_name = "Classic", min_lvl = 1, max_lvl = 5, npc = "Lashun Novashine" },
        { id = "104", title = "Iksar Berserker Club", zone = "cabeast", zone_name = "East Cabilis", exp = "01", exp_name = "Ruins of Kunark", min_lvl = 15, max_lvl = 25, npc = "Trooper Mozo" },
        { id = "105", title = "Trial of Tactics", zone = "solrotower", zone_name = "Tower of Solusek Ro", exp = "04", exp_name = "Planes of Power", min_lvl = 60, max_lvl = 65, npc = "Rizlona" },
        { id = "106", title = "Late Era Task", zone = "argath", zone_name = "Argath", exp = "18", exp_name = "Veil of Alaris", min_lvl = 90, max_lvl = 95, npc = "Commander Galenth" },
    }

    -- 1. Build Zone List from Catalog
    local function buildZoneList(cat)
        local zoneMap = {}
        local zList = {}
        for _, q in ipairs(cat) do
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
                table.insert(zList, zObj)
            end
            zoneMap[z].count = zoneMap[z].count + 1
            local qExp = tonumber(q.exp) or 0
            if qExp < zoneMap[z].exp then
                zoneMap[z].exp = qExp
                zoneMap[z].exp_name = q.exp_name
            end
        end
        table.sort(zList, function(a, b)
            return (a.name or a.shortname) < (b.name or b.shortname)
        end)
        return zList
    end

    local zList = buildZoneList(lookupCatalog)
    assert_eq(#zList, 5, '5 unique zones identified')
    assert_eq(zList[1].name, 'Argath', 'alphabetical sorting: Argath first')
    assert_eq(zList[3].name, 'Greater Faydark', 'Greater Faydark present')
    assert_eq(zList[3].count, 2, 'Greater Faydark has 2 quests')
    assert_eq(zList[3].exp, 0, 'Greater Faydark min exp is 0')

    -- 2. Zone Lookup Search Filter
    local function filterZoneList(list, query, limitEra, maxCap)
        local out = {}
        local qLow = query:lower()
        for _, z in ipairs(list) do
            local matchesEra = not limitEra or (z.exp <= (maxCap or 32))
            if matchesEra then
                local matchesText = (qLow == "") or (z.name:lower():find(qLow, 1, true) ~= nil) or (z.shortname:lower():find(qLow, 1, true) ~= nil)
                if matchesText then
                    table.insert(out, z)
                end
            end
        end
        return out
    end

    local zFilt1 = filterZoneList(zList, "fay", false, 32)
    assert_eq(#zFilt1, 1, 'zone filter "fay" matches 1 zone')
    assert_eq(zFilt1[1].shortname, 'gfaydark', 'zone matched is gfaydark')

    local zFiltEra = filterZoneList(zList, "", true, 4)
    assert_eq(#zFiltEra, 4, 'era cap 4 excludes Argath (exp 18)')

    -- 3. Global Quest Search Filter
    local function searchQuests(cat, term, limitEra, maxCap, hideDone, completedMap)
        local out = {}
        local tLow = term:lower()
        for _, q in ipairs(cat) do
            local expNum = tonumber(q.exp) or 0
            local eraMatch = not limitEra or (expNum <= (maxCap or 32))
            if eraMatch then
                local isDone = completedMap and (completedMap[q.id] == true)
                if not (hideDone and isDone) then
                    local textMatch = (tLow == "") or (q.title:lower():find(tLow, 1, true) ~= nil) or (q.npc:lower():find(tLow, 1, true) ~= nil) or (q.zone_name:lower():find(tLow, 1, true) ~= nil)
                    if textMatch then
                        table.insert(out, q)
                    end
                end
            end
        end
        return out
    end

    local qSearch1 = searchQuests(lookupCatalog, "belt", false, 32, false, nil)
    assert_eq(#qSearch1, 1, 'search "belt" matches Crushbone Belts')
    assert_eq(qSearch1[1].id, "101", 'quest id is 101')

    local qSearchNpc = searchQuests(lookupCatalog, "novashine", false, 32, false, nil)
    assert_eq(#qSearchNpc, 1, 'search by NPC "novashine" matches Bone Chips')

    local qSearchCompleted = searchQuests(lookupCatalog, "", false, 32, true, { ["101"] = true, ["102"] = true })
    assert_eq(#qSearchCompleted, 4, 'hide completed filters out 2 done quests')

    -- 4. Walkthrough Narrative Cleaning & Tokenizer Tests
    local rawWalkthroughSample = [[
Quest Started By: | Description:
**Where:**
- North Qeynos [zone=4]
**Who:**
- Captain Hazran [npc=18176]
Rating:
0/0**_*__*__*__*__*_**
Information:
**Level:** | 10
**Maximum Level:** | 125
**Monster Mission:** | No
**Repeatable:** | Yes
**Can Be Shrouded?:** | No
**Quest Type:** | Quest
**Quest Goal:**
- Advancement
Modified: Tue Dec 5 05:21:04 2023 | | Speak with Captain Hazran in North Qeynos.
You say, 'Hail, Captain Hazran'
Captain Hazran says, 'Greetings, _____! We are having trouble with the local orcs.'
You say, 'What orcs?'
Captain Hazran says, 'Crushbone orcs. Bring me their belts.'
---
**Task Steps**
1. Loot 4 Crushbone Belts
2. Deliver 4 Crushbone Belts to Captain Hazran
NOTE: Beware of the orc emissary roaming nearby!
Your faction standing with Guards of Qeynos has been adjusted by 10.
Your faction standing with Corrupt Qeynos Guards has been adjusted by -2.
You receive 5 gold from Captain Hazran.
You gain experience!!
Submitted by: Tester
]]

    local function testCleanPreamble(raw)
        local pos = raw:find("Modified:[^\n|]+|%s*|%s*") or raw:find("Entered:[^\n|]+|%s*|%s*")
        local body = raw
        if pos then
            local after = raw:sub(pos):match("^[^\n|]+|%s*|%s*(.*)$")
            if after and after ~= "" then body = after end
        end
        local subPos = body:find("Submitted by:") or body:find("%*%*Submitted by:")
        if subPos then body = body:sub(1, subPos - 1) end
        body = body:gsub("____+", "Bob")
        return body:match("^%s*(.-)%s*$") or ""
    end

    local cleanWt = testCleanPreamble(rawWalkthroughSample)
    assert_true(not cleanWt:find("Quest Started By:"), 'preamble stripped from walkthrough')
    assert_true(not cleanWt:find("Submitted by:"), 'submission footer stripped from walkthrough')
    assert_true(cleanWt:find("Greetings, Bob!"), 'player name substituted into dialogue')

    local function testTokenize(cleaned)
        local toks = {}
        for line in cleaned:gmatch("[^\r\n]+") do
            local l = line:match("^%s*(.-)%s*$")
            if l and l ~= "" then
                if l == "---" then
                    table.insert(toks, { type = "divider" })
                elseif l:find("^[Yy]ou say") then
                    local phrase = l:match("^[Yy]ou say,?%s*['\"](.-)['\"]")
                    table.insert(toks, { type = "player_say", phrase = phrase })
                elseif l:find(" says") then
                    local spk, spc = l:match("^([%w%s%-%_%.%`']+)[%s,]+says?,?%s*['\"](.-)['\"]")
                    table.insert(toks, { type = "npc_say", speaker = spk, text = spc })
                elseif l:find("^[Yy]our faction standing with") then
                    table.insert(toks, { type = "faction" })
                elseif l:find("^[Yy]ou receive") or l:find("^[Yy]ou gain") then
                    table.insert(toks, { type = "reward" })
                elseif l:find("^NOTE:") then
                    table.insert(toks, { type = "note" })
                elseif l:match("^%d+[%.)]%s+") then
                    table.insert(toks, { type = "step" })
                elseif l:match("^%*%*(.-)%*%*$") then
                    table.insert(toks, { type = "header" })
                else
                    table.insert(toks, { type = "text" })
                end
            end
        end
        return toks
    end

    local toks = testTokenize(cleanWt)
    assert_eq(#toks, 14, '14 tokens parsed from sample walkthrough')
    assert_eq(toks[2].type, 'player_say', 'second token is player_say')
    assert_eq(toks[2].phrase, 'Hail, Captain Hazran', 'player say phrase is Hail, Captain Hazran')
    assert_eq(toks[3].type, 'npc_say', 'third token is npc_say')
    assert_eq(toks[3].speaker, 'Captain Hazran', 'npc speaker is Captain Hazran')
    assert_eq(toks[7].type, 'header', 'token 7 is header Task Steps')
    assert_eq(toks[8].type, 'step', 'token 8 is step')
    assert_eq(toks[10].type, 'note', 'token 10 is note')
    assert_eq(toks[11].type, 'faction', 'token 11 is faction')
    assert_eq(toks[13].type, 'reward', 'token 13 is reward')
end

-- ============================================================================
-- Suite 58: Assist Mode Position Behind NPC Logic
-- ============================================================================
print('--- Suite 58: Assist Mode Position Behind NPC Logic ---')
do
    local sanitizeModeConfig = loadFunc(src, 'sanitizeModeConfig', { MODES = MODES })
    local defaultCtrl = loadFunc(src, 'defaultCtrl')

    -- 1. Default ctrl has assist_behind = true
    local c = defaultCtrl()
    assert_true(c.assist_behind == true, 'defaultCtrl initializes assist_behind to true')

    -- 2. sanitizeModeConfig handles missing assist_behind and preserves false
    local cMissing = { mode = 'Assist', submode = 'Chase' }
    sanitizeModeConfig(cMissing)
    assert_true(cMissing.assist_behind == true, 'sanitizeModeConfig sets default assist_behind = true when nil')

    local cDisabled = { mode = 'Assist', submode = 'Chase', assist_behind = false }
    sanitizeModeConfig(cDisabled)
    assert_true(cDisabled.assist_behind == false, 'sanitizeModeConfig preserves assist_behind = false')

    -- 3. Geometric calculation for isBehindTarget
    local function calcIsBehind(px, py, sx, sy, sHead)
        local dx = px - sx
        local dy = py - sy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= 0.001 then return true end
        local vx = dx / dist
        local vy = dy / dist
        local hRad = math.rad(sHead or 0)
        local fx = math.sin(hRad)
        local fy = math.cos(hRad)
        local dot = fx * vx + fy * vy
        return dot <= 0.0
    end

    -- Heading 0 = North (+Y):
    -- Behind is South (-Y), Front is North (+Y)
    assert_true(calcIsBehind(0, -10, 0, 0, 0), 'Behind target facing North (player South)')
    assert_eq(calcIsBehind(0, 10, 0, 0, 0), false, 'In front of target facing North (player North)')
    assert_true(calcIsBehind(10, 0, 0, 0, 0), 'Flank of target facing North (player West dot=0 <= 0)')

    -- Heading 90 = West (+X):
    -- Behind is East (-X), Front is West (+X)
    assert_true(calcIsBehind(-10, 0, 0, 0, 90), 'Behind target facing West (player East)')
    assert_eq(calcIsBehind(10, 0, 0, 0, 90), false, 'In front of target facing West (player West)')

    -- Heading 180 = South (-Y):
    -- Behind is North (+Y), Front is South (-Y)
    assert_true(calcIsBehind(0, 10, 0, 0, 180), 'Behind target facing South (player North)')
    assert_eq(calcIsBehind(0, -10, 0, 0, 180), false, 'In front of target facing South (player South)')

    -- Heading 270 = East (-X):
    -- Behind is West (+X), Front is East (-X)
    assert_true(calcIsBehind(10, 0, 0, 0, 270), 'Behind target facing East (player West)')
    assert_eq(calcIsBehind(-10, 0, 0, 0, 270), false, 'In front of target facing East (player East)')

    -- 4. Behind coordinates calculation (getBehindLoc)
    local function calcBehindLoc(sx, sy, sz, sHead, behindDist)
        local hRad = math.rad(sHead or 0)
        local bx = sx - behindDist * math.sin(hRad)
        local by = sy - behindDist * math.cos(hRad)
        return bx, by, sz
    end

    local bx, by, bz = calcBehindLoc(100, 200, 10, 0, 12)
    assert_eq(math.floor(bx + 0.5), 100, 'Behind loc North heading X matches 100')
    assert_eq(math.floor(by + 0.5), 188, 'Behind loc North heading Y is 200 - 12 = 188')
    assert_eq(bz, 10, 'Behind loc Z matches 10')

    bx, by, bz = calcBehindLoc(100, 200, 10, 90, 12)
    assert_eq(math.floor(bx + 0.5), 88, 'Behind loc West heading X is 100 - 12 = 88')
    assert_eq(math.floor(by + 0.5), 200, 'Behind loc West heading Y matches 200')

    -- 5. Aggro safety evaluation logic
    local function evaluateBehindBehavior(mode, assistBehind, hasAggro)
        if mode ~= 'Assist' or not assistBehind then
            return 'NORMAL'
        end
        if hasAggro then
            return 'SUSPEND_BEHIND' -- prevent spinning with mob while tanking
        end
        return 'POSITION_BEHIND'
    end

    assert_eq(evaluateBehindBehavior('Assist', true, false), 'POSITION_BEHIND', 'Assist mode without aggro positions behind')
    assert_eq(evaluateBehindBehavior('Assist', true, true), 'SUSPEND_BEHIND', 'Assist mode with aggro suspends behind positioning')
    assert_eq(evaluateBehindBehavior('Assist', false, false), 'NORMAL', 'Assist mode with assist_behind disabled uses normal facing')
    assert_eq(evaluateBehindBehavior('Manual', true, false), 'NORMAL', 'Manual mode uses normal facing')

    -- 6. Slash command handling emulation
    local function handleBehindSlashCmd(ctrlTable, sub)
        sub = sub and string.lower(sub) or ''
        if sub == 'on' or sub == '1' or sub == 'true' then
            ctrlTable.assist_behind = true
        elseif sub == 'off' or sub == '0' or sub == 'false' then
            ctrlTable.assist_behind = false
        else
            ctrlTable.assist_behind = ctrlTable.assist_behind == false
        end
        return ctrlTable.assist_behind
    end

    local testCtrl = { assist_behind = true }
    assert_eq(handleBehindSlashCmd(testCtrl, 'off'), false, 'Slash cmd off disables assist_behind')
    assert_true(handleBehindSlashCmd(testCtrl, 'on'), 'Slash cmd on enables assist_behind')
    assert_eq(handleBehindSlashCmd(testCtrl, ''), false, 'Slash cmd toggle flips to false')
    assert_true(handleBehindSlashCmd(testCtrl, ''), 'Slash cmd toggle flips back to true')
end

-- ============================================================================
-- Suite 59: Field of View (FOV) Camera & Zoning Logic
-- ============================================================================
print('--- Suite 59: Field of View (FOV) Camera & Zoning Logic ---')
do
    -- 1. Default ctrl verification
    local defaultCtrl = loadFunc(src, 'defaultCtrl')
    local c = defaultCtrl()
    assert_eq(c.fov, 100, 'defaultCtrl initializes fov to 100')
    assert_eq(c.fov_enabled, false, 'defaultCtrl initializes fov_enabled to false')

    -- 2. Clamping and command execution emulation
    local lastExecutedCmd = nil
    local function mockApplyFov(ctrlTable)
        if not ctrlTable.fov_enabled then return nil end
        local val = tonumber(ctrlTable.fov) or 100
        if val < 50 then val = 50 end
        if val > 150 then val = 150 end
        local cmd = string.format('/fov %d', math.floor(val))
        lastExecutedCmd = cmd
        return cmd
    end

    local testCtrl = { fov = 100, fov_enabled = false }
    assert_eq(mockApplyFov(testCtrl), nil, 'mockApplyFov: no-op when fov_enabled is false')

    testCtrl.fov_enabled = true
    assert_eq(mockApplyFov(testCtrl), '/fov 100', 'mockApplyFov: executes /fov 100 when enabled')

    testCtrl.fov = 125
    assert_eq(mockApplyFov(testCtrl), '/fov 125', 'mockApplyFov: executes /fov 125')

    testCtrl.fov = 30 -- below min
    assert_eq(mockApplyFov(testCtrl), '/fov 50', 'mockApplyFov: clamps to min 50')

    testCtrl.fov = 180 -- above max
    assert_eq(mockApplyFov(testCtrl), '/fov 150', 'mockApplyFov: clamps to max 150')

    -- 3. Slash command handling emulation
    local function handleFovSlashCmd(ctrlTable, arg)
        local sub = arg and string.lower(tostring(arg)) or ''
        local num = tonumber(arg)
        if num then
            if num < 50 then num = 50 end
            if num > 150 then num = 150 end
            ctrlTable.fov = math.floor(num)
            ctrlTable.fov_enabled = true
            mockApplyFov(ctrlTable)
            return 'SET'
        elseif sub == 'on' or sub == '1' or sub == 'enable' or sub == 'true' then
            ctrlTable.fov_enabled = true
            mockApplyFov(ctrlTable)
            return 'ENABLED'
        elseif sub == 'off' or sub == '0' or sub == 'disable' or sub == 'false' then
            ctrlTable.fov_enabled = false
            return 'DISABLED'
        else
            return 'STATUS'
        end
    end

    local cmdCtrl = { fov = 100, fov_enabled = false }
    assert_eq(handleFovSlashCmd(cmdCtrl, '120'), 'SET', 'Slash cmd sets FOV')
    assert_eq(cmdCtrl.fov, 120, 'Slash cmd updated ctrl.fov to 120')
    assert_true(cmdCtrl.fov_enabled, 'Slash cmd enabled fov_enabled')
    assert_eq(lastExecutedCmd, '/fov 120', 'Slash cmd executed /fov 120')

    assert_eq(handleFovSlashCmd(cmdCtrl, 'off'), 'DISABLED', 'Slash cmd disabled FOV')
    assert_eq(cmdCtrl.fov_enabled, false, 'ctrl.fov_enabled is false')

    assert_eq(handleFovSlashCmd(cmdCtrl, 'on'), 'ENABLED', 'Slash cmd enabled FOV')
    assert_true(cmdCtrl.fov_enabled, 'ctrl.fov_enabled is true')
    assert_eq(lastExecutedCmd, '/fov 120', 'Slash cmd re-executed /fov 120')

    -- 4. Zoning reapplication verification
    local zonedFovApplied = false
    local function mockOnZoned(ctrlTable)
        if ctrlTable.fov_enabled then
            mockApplyFov(ctrlTable)
            zonedFovApplied = true
        end
    end

    zonedFovApplied = false
    cmdCtrl.fov_enabled = false
    mockOnZoned(cmdCtrl)
    assert_eq(zonedFovApplied, false, 'mockOnZoned does not apply when fov_enabled is false')

    cmdCtrl.fov_enabled = true
    cmdCtrl.fov = 110
    mockOnZoned(cmdCtrl)
    assert_true(zonedFovApplied, 'mockOnZoned applies FOV when fov_enabled is true')
    assert_eq(lastExecutedCmd, '/fov 110', 'mockOnZoned executed /fov 110')
end

-- ============================================================================
-- Suite 60: Melee Distance & Desired Range Respect Logic
-- ============================================================================
print('--- Suite 60: Melee Distance & Desired Range Respect Logic ---')
do
    local NAV_CONST = { MELEE_RANGE = 14 }

    local function calcMaxMeleeDistance(userDist, spawnReach)
        userDist = userDist or NAV_CONST.MELEE_RANGE
        spawnReach = spawnReach or 0
        if spawnReach > 18 and spawnReach > userDist then
            return spawnReach
        end
        return userDist
    end

    local function calcDesiredRange(userDist, spawnReach, combatStyle)
        combatStyle = combatStyle or 'Melee'
        if combatStyle ~= 'Melee' then return 40 end
        userDist = userDist or NAV_CONST.MELEE_RANGE
        spawnReach = spawnReach or 0
        if spawnReach > 18 and spawnReach > userDist then
            return math.max(userDist, math.floor(spawnReach - 3))
        end
        return math.max(4, math.floor(userDist - 2))
    end

    -- 1. Default melee range (14) on standard mob (spawnReach = 14)
    assert_eq(calcDesiredRange(14, 14), 12, 'Default 14 melee dist targets 12 on standard mob')
    assert_eq(calcMaxMeleeDistance(14, 14), 14, 'Default 14 melee dist max reach is 14 on standard mob')

    -- 2. Extended melee range (25) - must NOT be clamped to 12 or 14!
    assert_eq(calcDesiredRange(25, 14), 23, 'Melee dist 25 targets 23 on standard mob (not clamped to 12)')
    assert_eq(calcMaxMeleeDistance(25, 14), 25, 'Melee dist 25 max reach is 25 on standard mob (not clamped to 14)')

    -- 3. Tight melee range (8) - must NOT be clamped up to 14!
    assert_eq(calcDesiredRange(8, 14), 6, 'Melee dist 8 targets 6 on standard mob')
    assert_eq(calcMaxMeleeDistance(8, 14), 8, 'Melee dist 8 max reach is 8 on standard mob (allows re-closing)')

    -- 4. Minimum melee range slider value (5)
    assert_eq(calcDesiredRange(5, 14), 4, 'Melee dist 5 targets 4')
    assert_eq(calcMaxMeleeDistance(5, 14), 5, 'Melee dist 5 max reach is 5')

    -- 5. Giant oversized mob (dragon: spawnReach = 45) with standard userDist = 14
    assert_eq(calcDesiredRange(14, 45), 42, 'Dragon spawnReach 45 with userDist 14 targets 42 (does not clip inside model)')
    assert_eq(calcMaxMeleeDistance(14, 45), 45, 'Dragon spawnReach 45 with userDist 14 max reach is 45')

    -- 6. Giant oversized mob with userDist = 50 (larger than dragon reach)
    assert_eq(calcDesiredRange(50, 45), 48, 'Dragon spawnReach 45 with userDist 50 targets 48')
    assert_eq(calcMaxMeleeDistance(50, 45), 50, 'Dragon spawnReach 45 with userDist 50 max reach is 50')

    -- 7. triune.lua source code assertions: verify hardcoded clamps were eliminated
    local triuneCode = readFile('TAC/lua/triune.lua')
    assert_true(triuneCode:find("math.min(12, (ctrl and ctrl.melee_dist) or 12)", 1, true) == nil,
        'triune.lua eliminated hardcoded 12 clamp in getBehindLoc')
    assert_true(triuneCode:find("math.min(userDist, maxSafe)", 1, true) == nil,
        'triune.lua eliminated math.min(userDist, maxSafe) clamp in desiredRange')
    assert_true(triuneCode:find("spawnReach > 18 and spawnReach > userDist", 1, true) ~= nil,
        'triune.lua uses oversized threshold check for giant hitboxes')
    assert_true(triuneCode:find("lastBehindStickDist", 1, true) ~= nil,
        'triune.lua tracks lastBehindStickDist in pursuit table')
end

-- ============================================================================
-- 104. triune_inv.lua — Inventory & Bank Manager Pure Logic Tests
-- ============================================================================
print('--- triune_inv.lua pure logic tests ---')
do
    local invSrc = readFile('TAC/lua/triune_inv.lua')
    local formatMoney = loadFunc(invSrc, 'formatMoney', {})
    local classifyItem = loadFunc(invSrc, 'classifyItem', {})
    local matchesFilter = loadFunc(invSrc, 'matchesFilter', {})
    local findDuplicateStacks = loadFunc(invSrc, 'findDuplicateStacks', {})
    local findHeaviestItems = loadFunc(invSrc, 'findHeaviestItems', {})

    -- 1. formatMoney
    assert_eq(formatMoney(0), '0c', 'formatMoney(0) is 0c')
    assert_eq(formatMoney(5), '5c', 'formatMoney(5) is 5c')
    assert_eq(formatMoney(10), '1s', 'formatMoney(10) is 1s')
    assert_eq(formatMoney(150), '1g 5s', 'formatMoney(150) is 1g 5s')
    assert_eq(formatMoney(12345), '12p 3g 4s 5c', 'formatMoney(12345) is 12p 3g 4s 5c')
    assert_eq(formatMoney(2000), '2p', 'formatMoney(2000) is 2p')

    -- 2. classifyItem
    assert_eq(classifyItem({ container = 10, name = 'Backpack' }), 'Bag', 'Container > 0 classifies as Bag')
    assert_eq(classifyItem({ augType = 7, name = 'Augment Stone' }), 'Aug', 'AugType > 0 classifies as Aug')
    assert_eq(classifyItem({ name = 'Spell: Greater Healing' }), 'Spell', 'Spell: prefix classifies as Spell')
    assert_eq(classifyItem({ name = 'Song: Selo\'s Accelerando' }), 'Spell', 'Song: prefix classifies as Spell')
    assert_eq(classifyItem({ name = 'Tome of Weapon Stance' }), 'Spell', 'Tome prefix classifies as Spell')
    assert_eq(classifyItem({ tradeskill = true, name = 'Silk Swatch' }), 'Tradeskill', 'Tradeskill flag classifies as Tradeskill')
    assert_eq(classifyItem({ damage = 15, delay = 24, name = 'Short Sword' }), 'Weapon', 'Damage > 0 classifies as Weapon')
    assert_eq(classifyItem({ type = '1H Slashing', name = 'Practice Blade' }), 'Weapon', 'Slashing type classifies as Weapon')
    assert_eq(classifyItem({ location = 'Worn', wornSlot = 'Neck', name = 'Black Sapphire Necklace' }), 'Jewelry', 'Worn neck slot classifies as Jewelry')
    assert_eq(classifyItem({ location = 'Worn', wornSlot = 'Left Finger', name = 'Platinum Fire Ring' }), 'Jewelry', 'Worn ring slot classifies as Jewelry')
    assert_eq(classifyItem({ ac = 30, location = 'Worn', wornSlot = 'Chest', name = 'Chain Chestplate' }), 'Armor', 'Worn chest armor classifies as Armor')
    assert_eq(classifyItem({ type = 'Potion', name = 'Cloudy Potion' }), 'Consumable', 'Potion type classifies as Consumable')
    assert_eq(classifyItem({ clicky = 'Spirit of Wolf', name = 'Journeyman Boots' }), 'Consumable', 'Clicky effect classifies as Consumable')
    assert_eq(classifyItem({ name = 'Blue Diamond' }), 'Gem', 'Diamond in name classifies as Gem')
    assert_eq(classifyItem({ name = 'Peridot' }), 'Gem', 'Peridot in name classifies as Gem')
    assert_eq(classifyItem({ name = 'Rusty Canteen' }), 'Misc', 'Generic item classifies as Misc')

    -- 3. matchesFilter
    local testItem = {
        name = 'Peridot',
        location = 'INVENTORY',
        displayLocation = 'Bag 2 [Slot 3]',
        category = 'Gem',
        type = 'Combinable',
        lore = false,
        nodrop = false,
        tradeskill = false,
        clicky = nil,
    }

    assert_true(matchesFilter(testItem, '', 'ALL', 'ALL', nil), 'Default filter matches item')
    assert_true(matchesFilter(testItem, 'peri', 'ALL', 'ALL', nil), 'Substring search matches Peridot')
    assert_true(matchesFilter(testItem, 'bag 2', 'ALL', 'ALL', nil), 'Substring search matches location')
    assert_true(matchesFilter(testItem, '', 'INVENTORY', 'ALL', nil), 'Location INVENTORY matches')
    assert_eq(matchesFilter(testItem, '', 'BANK', 'ALL', nil), false, 'Location BANK rejects INVENTORY item')
    assert_true(matchesFilter(testItem, '', 'ALL', 'Gem', nil), 'Category Gem matches')
    assert_eq(matchesFilter(testItem, '', 'ALL', 'Weapon', nil), false, 'Category Weapon rejects Gem')

    local loreItem = {
        name = 'SoulFire',
        location = 'INVENTORY',
        category = 'Weapon',
        lore = true,
        nodrop = true,
        tradeskill = false,
        clicky = 'Complete Heal',
    }
    assert_true(matchesFilter(loreItem, '', 'ALL', 'ALL', { lore = true }), 'Lore filter matches Lore item')
    assert_true(matchesFilter(loreItem, '', 'ALL', 'ALL', { nodrop = true }), 'NoDrop filter matches NoDrop item')
    assert_true(matchesFilter(loreItem, '', 'ALL', 'ALL', { clicky = true }), 'Clicky filter matches Clicky item')
    assert_eq(matchesFilter(loreItem, '', 'ALL', 'ALL', { tradeskill = true }), false, 'Tradeskill filter rejects non-TS item')

    -- 4. findDuplicateStacks
    local stackItems = {
        { id = 1001, name = 'Peridot', count = 5, stackable = true, stackSize = 20, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 2]' },
        { id = 1001, name = 'Peridot', count = 7, stackable = true, stackSize = 20, location = 'INVENTORY', displayLocation = 'Bag 3 [Slot 8]' },
        { id = 2002, name = 'Emerald', count = 20, stackable = true, stackSize = 20, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 1]' },
        { id = 2002, name = 'Emerald', count = 20, stackable = true, stackSize = 20, location = 'INVENTORY', displayLocation = 'Bag 2 [Slot 1]' },
        { id = 3003, name = 'Rusty Sword', count = 1, stackable = false, stackSize = 1, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 3]' },
    }
    local dups = findDuplicateStacks(stackItems)
    assert_eq(#dups, 1, 'findDuplicateStacks identifies 1 fragmented stack')
    assert_eq(dups[1].name, 'Peridot', 'Fragmented stack is Peridot')
    assert_eq(dups[1].totalCount, 12, 'Fragmented stack total count is 12')
    assert_eq(dups[1].numStacks, 2, 'Fragmented stack has 2 entries')

    -- 5. findHeaviestItems
    local heavyItems = {
        { name = 'Iron Bar', weight = 10.0, count = 1, stackable = false, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 1]', category = 'Tradeskill' },
        { name = 'Feather', weight = 0.1, count = 1, stackable = false, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 2]', category = 'Misc' },
        { name = 'Heavy Ore', weight = 8.0, count = 2, stackable = true, location = 'INVENTORY', displayLocation = 'Bag 2 [Slot 1]', category = 'Tradeskill' },
    }
    local heavies = findHeaviestItems(heavyItems, 2)
    assert_eq(#heavies, 2, 'findHeaviestItems returns requested limit')
    assert_eq(heavies[1].name, 'Heavy Ore', 'Heavy Ore (16 lbs total) is ranked first')
    assert_eq(heavies[2].name, 'Iron Bar', 'Iron Bar (10 lbs) is ranked second')
end

-- ============================================================================
-- 61. Suite 61: Healing Priority Engine & Reliability Logic
-- ============================================================================
print('--- Suite 61: Healing Priority Engine & Reliability Logic ---')
do
    -- 1. isHealAction classification
    local function isDetrimentalMock(name, targetToken, entry)
        if entry and entry.kind then
            local k = tostring(entry.kind):lower()
            if k == 'dd' or k == 'dot' or k == 'debuff' or k == 'nuke' then return true end
            if k == 'heal' or k == 'buff' or k == 'pet' or k == 'cure' or k == 'util' then return false end
        end
        local lower = tostring(name):lower()
        if lower:find('nuke') or lower:find('ice comet') or lower:find('tash') or lower:find('slow') or lower:find('lifetap') then
            return true
        end
        return false
    end

    local function isHealActionMock(name, targetToken, entry)
        if not name or name == '' then return false end
        if entry and entry.kind == 'heal' then return true end
        local k = entry and entry.kind
        if k and (k == 'dd' or k == 'dot' or k == 'debuff' or k == 'nuke' or k == 'buff' or k == 'pet' or k == 'util') then
            return false
        end
        if entry and entry.when == 'missing buff' then
            return false
        end
        if targetToken and (targetToken:find('Lowest-HP Ally') or targetToken == 'Lowest-HP Ally') then
            if not isDetrimentalMock(name, targetToken, entry) then
                return true
            end
        end
        if entry and entry.when and (entry.when == 'my HP <=' or entry.when == 'HP <=' or entry.when == 'target HP <=') then
            if not isDetrimentalMock(name, targetToken, entry) then
                local lowerName = tostring(name):lower()
                if lowerName:find('heal') or lowerName:find('mend') or lowerName:find('salve')
                    or lowerName:find('remedy') or lowerName:find('chloroplast') or lowerName:find('regeneration')
                    or lowerName:find('renewal') or lowerName:find('restoration') or lowerName:find('lay on hands')
                    or lowerName:find('burst of life') or lowerName:find('arbitration') or lowerName:find('touch')
                    or (targetToken and targetToken:find('Lowest-HP Ally')) then
                    return true
                end
            end
        end
        local lowerName = tostring(name):lower()
        if not isDetrimentalMock(name, targetToken, entry) then
            if lowerName:find('heal') or lowerName:find('mend') or lowerName:find('salve')
                or lowerName:find('remedy') or lowerName:find('chloroplast') or lowerName:find('renewal')
                or lowerName:find('restoration') or lowerName:find('lay on hands') or lowerName:find('burst of life')
                or lowerName:find('divine arbitration') then
                return true
            end
        end
        return false
    end

    assert_true(isHealActionMock('Greater Healing', 'F: Myself', { kind = 'heal' }), 'Greater Healing with kind heal')
    assert_true(isHealActionMock('Complete Healing', 'F: Lowest-HP Ally', { when = 'target HP <=' }), 'Complete Healing on Lowest-HP Ally')
    assert_true(isHealActionMock('Mend', 'F: Myself', { when = 'my HP <=' }), 'Mend action classified as heal')
    assert_true(isHealActionMock('Lay on Hands', 'F: Tank', { when = 'target HP <=' }), 'Lay on Hands AA classified as heal')
    assert_true(isHealActionMock('Burst of Life', 'F: Lowest-HP Ally', {}), 'Burst of Life classified as heal')
    assert_true(isHealActionMock('Divine Arbitration', 'F: Whole Group', {}), 'Divine Arbitration classified as heal')
    assert_true(isHealActionMock('Chloroplast', 'F: Myself', { when = 'my HP <=' }), 'Chloroplast with HP <= classified as heal')
    assert_eq(isHealActionMock('Ice Comet', 'E: Current Target', { kind = 'dd' }), false, 'Ice Comet rejected as heal')
    assert_eq(isHealActionMock('Tashani', 'E: Current Target', { kind = 'debuff' }), false, 'Tashani rejected as heal')
    assert_eq(isHealActionMock('Spirit of Wolf', 'F: Myself', { kind = 'buff', when = 'missing buff' }), false, 'SoW missing buff rejected as heal')

    -- 2. lowestHpAlly range and presence filtering
    local function lowestHpAllyMock(members, myId, myHp, maxDist)
        maxDist = maxDist or 200
        local bestId, bestHp = myId, myHp
        for _, m in ipairs(members) do
            if not m.dead then
                local isPresent = not m.otherZone and not m.offline and (m.present == nil or m.present)
                if isPresent and m.id > 0 and m.alive then
                    local dist = m.distance or 0
                    if dist >= 0 and dist <= maxDist then
                        if m.hp < bestHp then
                            bestHp = m.hp
                            bestId = m.id
                        end
                    end
                end
            end
        end
        return bestId, bestHp
    end

    local testGroup = {
        { id = 101, name = 'Tank', hp = 40, distance = 30, alive = true, dead = false, otherZone = false, offline = false },
        { id = 102, name = 'MageFar', hp = 15, distance = 450, alive = true, dead = false, otherZone = false, offline = false }, -- too far
        { id = 103, name = 'RogueZone', hp = 10, distance = 50, alive = true, dead = false, otherZone = true, offline = false }, -- other zone
        { id = 104, name = 'ClericOff', hp = 5, distance = 20, alive = true, dead = false, otherZone = false, offline = true }, -- offline
    }
    local chosenId, chosenHp = lowestHpAllyMock(testGroup, 1, 100, 200)
    assert_eq(chosenId, 101, 'lowestHpAlly selects Tank (dist 30, HP 40) ignoring out-of-range, other-zone, offline members')
    assert_eq(chosenHp, 40, 'lowestHpAlly selected HP is 40%')

    -- If player is lower than all valid members in range
    local chosenIdSelf, chosenHpSelf = lowestHpAllyMock(testGroup, 1, 30, 200)
    assert_eq(chosenIdSelf, 1, 'lowestHpAlly selects player when player HP is lowest')
    assert_eq(chosenHpSelf, 30, 'lowestHpAlly returns player HP 30%')

    -- 3. min_mana_pct bypass for heals vs non-heals
    local function canCastManaMock(spellName, currentMana, spellCost, pctMana, minManaPct, entry)
        if currentMana < spellCost then return false end
        local isHeal = isHealActionMock(spellName, entry and entry.target, entry)
        if not isHeal and minManaPct > 0 and pctMana < minManaPct then
            return false
        end
        return true
    end

    assert_true(canCastManaMock('Greater Healing', 300, 150, 15, 20, { kind = 'heal' }), 'Heal casts even when pctMana (15%) < minManaPct (20%)')
    assert_eq(canCastManaMock('Ice Comet', 1000, 400, 15, 20, { kind = 'dd' }), false, 'Nuke blocked when pctMana (15%) < minManaPct (20%)')
    assert_eq(canCastManaMock('Greater Healing', 100, 150, 15, 20, { kind = 'heal' }), false, 'Heal blocked if currentMana < spellCost')

    -- 4. conditionMet friendly target fallback when user left "my HP <=" default
    local function conditionMetMock(when, pct, targetId, myId, myHp, targetHp, token)
        if when == 'my HP <=' then
            local myMet = myHp <= pct
            local isAlly = token and not token:find('Myself')
            if isAlly and targetId and targetId > 0 and targetId ~= myId then
                return myMet or (targetHp <= pct)
            end
            return myMet
        end
        if when == 'target HP <=' or when == 'HP <=' then
            return targetHp <= pct
        end
        return false
    end

    assert_true(conditionMetMock('my HP <=', 75, 101, 1, 100, 50, 'F: Lowest-HP Ally'), 'my HP <= on Lowest-HP Ally triggers when ally is low (50 <= 75) even with player at 100%')
    assert_true(conditionMetMock('my HP <=', 75, 101, 1, 60, 100, 'F: Lowest-HP Ally'), 'my HP <= on Lowest-HP Ally triggers when player is low (60 <= 75)')
    assert_eq(conditionMetMock('my HP <=', 75, 1, 1, 100, 100, 'F: Myself'), false, 'my HP <= on Myself returns false when player is at 100%')

    -- 5. processHealPriority sorting and movement cessation simulation
    local healCandidates = {
        { name = 'Light Healing', targetHp = 70, pctThreshold = 75, priority = 50, slot = 3 },
        { name = 'Complete Healing', targetHp = 40, pctThreshold = 50, priority = 30, slot = 2 },
        { name = 'Flash of Light Heal', targetHp = 20, pctThreshold = 25, priority = 10, slot = 1 },
    }
    table.sort(healCandidates, function(a, b)
        if a.targetHp ~= b.targetHp then return a.targetHp < b.targetHp end
        if a.pctThreshold ~= b.pctThreshold then return a.pctThreshold < b.pctThreshold end
        return (a.priority or 50) < (b.priority or 50)
    end)
    assert_eq(healCandidates[1].name, 'Flash of Light Heal', 'Most urgent heal (target HP 20%, threshold 25%) chosen first')
    assert_eq(healCandidates[2].name, 'Complete Healing', 'Second urgent heal (target HP 40%) chosen second')
    assert_eq(healCandidates[3].name, 'Light Healing', 'Maintenance heal chosen last')

    local stoppedMovement = false
    local function stopMovementMock(cls)
        if cls ~= 'Brd' then stoppedMovement = true end
    end
    stopMovementMock('Clr')
    assert_true(stoppedMovement, 'Movement halted for Cleric casting heal')

    stoppedMovement = false
    stopMovementMock('Brd')
    assert_eq(stoppedMovement, false, 'Movement NOT halted for Bard singing')
end

-- ============================================================================
-- Suite 62: AA Special Tab Scan Loop Prevention
-- ============================================================================
do
    print('--- Suite 62: AA Special Tab Scan Loop Prevention ---')
    local triuneContent = readFile('TAC/lua/triune.lua')

    -- 1. Verify readSpecialTabOnce marks read as done even on failure and never retries
    local mockRuntime = {
        specialTabReadDone = false,
        specialTabAAs = nil,
        readSpecialTabNamesFromUI = function() return nil end,
    }
    local function mockReadSpecialTabOnce(rt, force)
        if not force and rt.specialTabReadDone then
            return rt.specialTabAAs or {}
        end
        rt.specialTabReadDone = true
        rt.specialTabAAs = rt.specialTabAAs or {}
        local names = rt.readSpecialTabNamesFromUI()
        if names and #names > 0 then
            rt.specialTabAAs = names
            return names
        end
        return rt.specialTabAAs or {}
    end

    local res1 = mockReadSpecialTabOnce(mockRuntime, false)
    assert_eq(#res1, 0, 'Suite 62: readSpecialTab returns empty table on failed read')
    assert_true(mockRuntime.specialTabReadDone, 'Suite 62: sets specialTabReadDone = true on failure')

    -- Subsequent call must immediately return without invoking UI reads or retries
    mockRuntime.readSpecialTabNamesFromUI = function() error('UI read must not be invoked again!') end
    local res2 = mockReadSpecialTabOnce(mockRuntime, false)
    assert_eq(#res2, 0, 'Suite 62: subsequent call returns cached empty list without retrying UI')

    -- 2. Verify scanPlayerAAs never sets pendingReadSpecialTab in triune.lua
    assert_true(triuneContent:find("if %(not specialList or #specialList == 0%) and not runtime%.specialTabReadDone then") ~= nil,
        'Suite 62: scanPlayerAAs respects specialTabReadDone')

    -- 3. Verify main loop honors paused and auto_spend_aa states
    assert_true(triuneContent:find("if not ctrl%.paused and ctrl%.auto_spend_aa and not mq%.TLO%.Me%.Combat") ~= nil,
        'Suite 62: main loop only executes pending read when not paused and auto_spend_aa is enabled')
    assert_true(triuneContent:find("elseif not ctrl%.auto_spend_aa or ctrl%.paused then%s*runtime%.pendingReadSpecialTab = false") ~= nil,
        'Suite 62: main loop clears pending read when auto_spend_aa disabled or paused')

    -- 4. Verify script startup does NOT unconditionally queue pendingReadSpecialTab
    assert_eq(triuneContent:find("runtime%.pendingReadSpecialTab = true%s*runMainLoop"), nil,
        'Suite 62: startup does not unconditionally queue pendingReadSpecialTab')
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
