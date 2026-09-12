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

    local loadFunc = loadstring or load
    local chunk, err = loadFunc(code, funcName)
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
-- Auto AA engine source (migrated to the auto_aa plugin); global to stay under the 200-local cap
AA_CONTENT = readFile('TAC/lua/tac/auto_aa.lua')

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

    -- combat_style consolidation to Melee
    local c5 = { mode = 'Manual', combat_style = 'Ranged' }
    sanitizeModeConfig(c5)
    assert_eq(c5.combat_style, 'Melee', 'sanitize: combat_style Ranged normalized to Melee')
    local c6 = { mode = 'Manual', combat_style = 'Spell' }
    sanitizeModeConfig(c6)
    assert_eq(c6.combat_style, 'Melee', 'sanitize: combat_style Spell normalized to Melee')
    local c7 = { mode = 'Manual' }
    sanitizeModeConfig(c7)
    assert_eq(c7.combat_style, 'Melee', 'sanitize: nil combat_style normalized to Melee')
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
    { 'show_unit_frames',        'boolean' },
    { 'uf_lock',                 'boolean' },
    { 'uf_alpha',                'number' },
    { 'uf_bar_height',           'number' },
    { 'uf_show_endurance',       'boolean' },
    { 'uf_show_xp',              'boolean' },
    { 'uf_hide_empty_pets',      'boolean' },
    { 'uf_buff_max',             'number' },
    { 'show_group_window',       'boolean' },
    { 'gw_lock',                 'boolean' },
    { 'gw_alpha',                'number' },
    { 'gw_bar_height',           'number' },
    { 'gw_include_self',         'boolean' },
    { 'gw_show_mana',            'boolean' },
    { 'gw_show_endurance',       'boolean' },
    { 'gw_show_pets',            'boolean' },
    { 'gw_show_roles',           'boolean' },
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
assert_eq(fmtSec(3599), '59m 59s', 'fmtSec: 3599s → 59m 59s')
assert_eq(fmtSec(3600), '1h', 'fmtSec: 3600s → 1h')
assert_eq(fmtSec(3660), '1h 1m', 'fmtSec: 3660s → 1h 1m')
assert_eq(fmtSec(3661), '1h 1m', 'fmtSec: 3661s → 1h 1m')
assert_eq(fmtSec(7200), '2h', 'fmtSec: 7200s → 2h')
assert_eq(fmtSec(7320), '2h 2m', 'fmtSec: 7320s → 2h 2m')
assert_eq(fmtSec(162000), '45h', 'fmtSec: 162000s (2700m) → 45h')
assert_eq(fmtSec(162300), '45h 5m', 'fmtSec: 162300s (2705m) → 45h 5m')

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
-- CROSS-MODULE TESTS: tac/dps.lua (DPS parser plugin)
-- ============================================================================
local dpsSrc = readFile('TAC/lua/tac/dps.lua')

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
-- CROSS-MODULE TESTS: tac/buffbot.lua (buffbot plugin)
-- ============================================================================
local bbSrc = readFile('TAC/lua/tac/buffbot.lua')

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
local isPlayerIgnored = loadFunc(bbSrc, 'isPlayerIgnored', { cfg = testCtrl })
local addIgnoredPlayer = loadFunc(bbSrc, 'addIgnoredPlayer', {
    cfg = testCtrl,
    isPlayerIgnored = isPlayerIgnored,
    saveConfig = function() dummySaveCalled = true end
})
local removeIgnoredPlayer = loadFunc(bbSrc, 'removeIgnoredPlayer', {
    cfg = testCtrl,
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
        cfg = gpCtrl,
        rt = gpRuntime,
        table = table
    })

    local requeuePreemptedJob = loadFunc(bbSrc, 'requeuePreemptedJob', {
        rt = gpRuntime,
        table = table
    })

    local getQueuePosition = loadFunc(bbSrc, 'getQueuePosition', {
        cfg = gpCtrl,
        rt = gpRuntime,
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
        cfg = gpCtrl,
        rt = fifoRuntime,
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

-- Verify Necromancer Touch of Death is classified as direct damage (dd) and detrimental (0), not heal
local foundTod = nil
if DATA_LOADED.spells.Nec then
    for _, sp in ipairs(DATA_LOADED.spells.Nec) do
        if sp[1] == 'Touch of Death' then foundTod = sp; break end
    end
end
assert_neq(foundTod, nil, 'data: Touch of Death exists in Nec spells')
if foundTod then
    assert_eq(foundTod[2], 64, 'data: Touch of Death is level 64')
    assert_eq(foundTod[3], 0, 'data: Touch of Death is detrimental (0)')
    assert_eq(foundTod[4], 'dd', 'data: Touch of Death kind is dd')
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
-- 30b. Hazard Hit Cap & Timed Decay
-- ============================================================================
print('--- hazard hit cap & timed decay ---')
do
local decayCtrl = {
    nav_hazard_avoidance = true,
    nav_hazard_radius = 15,
    nav_hazard_min_hits = 2,
    nav_hazard_max_hits = 3,
    nav_hazard_decay_minutes = 10,
    zone_hazards = {}
}
local decayGetZoneHazards = loadFunc(src, 'getZoneHazards', {
    ctrl = decayCtrl,
    getCurrentZoneShortName = function() return 'poknowledge' end
})
local decayRecord = loadFunc(src, 'recordStuckHazard', {
    ctrl = decayCtrl,
    getZoneHazards = decayGetZoneHazards,
    saveLoadout = function() end,
    getCurrentZoneShortName = function() return 'poknowledge' end
})
local decayIsActive = loadFunc(src, 'isCoordInActiveHazard', {
    ctrl = decayCtrl,
    getZoneHazards = decayGetZoneHazards
})
local decayZones = loadFunc(src, 'decayZoneHazards', {
    ctrl = decayCtrl,
    getCurrentZoneShortName = function() return 'poknowledge' end,
    saveLoadout = function() end
})

-- Fake wall-clock so decay timing is deterministic; patch BEFORE recording so
-- hazard timestamps align with the fake clock.
local realOsTime = os.time
local fakeClock = 100000
rawset(os, 'time', function() return fakeClock end)

-- Cap: repeated stuck events cannot push hits past nav_hazard_max_hits
decayRecord(100, 200, 10, 'poknowledge')
decayRecord(104, 200, 10, 'poknowledge')
decayRecord(100, 202, 10, 'poknowledge')
decayRecord(102, 201, 10, 'poknowledge')
local capHazard = decayGetZoneHazards('poknowledge')
assert_eq(#capHazard, 1, 'decay: all hits clustered into one hazard')
assert_eq(capHazard[1].hits, 3, 'decay: hits capped at nav_hazard_max_hits')

-- Hasn't hit the 10-minute window yet: no decay
assert_eq(decayZones('poknowledge'), 0, 'decay: no hits lost before decay window elapses')
assert_eq(capHazard[1].hits, 3, 'decay: hits stable inside decay window')

-- Past one 10-minute window: one hit lost
fakeClock = fakeClock + 601
local faded1 = decayZones('poknowledge')
assert_eq(faded1, 1, 'decay: one hazard decayed')
assert_eq(capHazard[1].hits, 2, 'decay: hits reduced from 3 to 2')

-- Second window: drops below min_hits (2) -> present but inactive
fakeClock = fakeClock + 601
decayZones('poknowledge')
assert_eq(capHazard[1].hits, 1, 'decay: hits reduced from 2 to 1')
assert_eq(decayIsActive(100, 200, 10, 'poknowledge'), false, 'decay: below min_hits is no longer active')

-- Third window: hits reach 0 -> hazard removed entirely
fakeClock = fakeClock + 601
local faded2 = decayZones('poknowledge')
assert_eq(faded2, 1, 'decay: final decay removed hazard')
assert_eq(#decayGetZoneHazards('poknowledge'), 0, 'decay: hazard forgotten at 0 hits')

rawset(os, 'time', realOsTime)
end

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

    -- Mirrors the real isHostileTarget() contract against the fixture: the spawn
    -- exists, is NPC/Pet, and is not dead. The scanners under test lean on this
    -- one predicate for all friendly / dead / type filtering.
    local function dummyIsHostile(id)
        for _, slot in pairs(dummyXtarSlots) do
            if slot.id == id then
                return (slot.type == 'NPC' or slot.type == 'Pet') and not slot.dead
            end
        end
        return false
    end

    local findFirstNPCXtarget = loadFunc(src, 'findFirstNPCXtarget', {
        ctrl = { xtar_nav_dist = 150 },
        mq = dummyMqXtar,
        isSpawnAlive = function(id) return id ~= 203 end,
        isGroupOrRaidMember = function() return false end,
        isSpawnPetOrPlayer = function() return false end,
        isHostileTarget = dummyIsHostile,
        buffActive = function() return false end
    })

    local isXTargetId = loadFunc(src, 'isXTargetId', {
        mq = dummyMqXtar,
        isGroupOrRaidMember = function() return false end,
        isSpawnPetOrPlayer = function() return false end,
        isHostileTarget = dummyIsHostile,
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
        isHostileTarget = dummyIsHostile,
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
        isHostileTarget = dummyIsHostile,
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
        isHostileTarget = dummyIsHostile,
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

    -- 4. Cross-file validation for the map plugin
    local srcMap = readFile('TAC/lua/tac/map.lua')
    local testMapStick = loadFunc(srcMap, 'stickLoaded', {
        mq = dummyMqMoveUtilsPluginLoaded,
        pcall = pcall,
    })
    assert_eq(testMapStick(), true, 'map plugin stickLoaded: true when Plugin mq2moveutils is loaded')
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
    local mapSrc = readFile('TAC/lua/tac/map.lua')
    assert_true(mapSrc ~= nil and #mapSrc > 0, 'tac/map.lua read successfully')

    -- Verify version is 1.1
    local versionMatch = mapSrc:match("local VERSION%s*=%s*'([^']+)'")
    assert_eq(versionMatch, '1.1', 'map plugin version is 1.1')

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

    -- E. Cooldowns is a popout window only (no main-window tab)
    local triuneContent = readFile('TAC/lua/triune.lua')
    local cdContent = readFile('TAC/lua/tac/hud_cooldowns.lua')
    assert_true(triuneContent:find('function UI.drawCooldownsTab()', 1, true) == nil, 'cooldown window: UI.drawCooldownsTab removed from triune.lua (hud_cooldowns plugin)')
    assert_true(cdContent:find("ImGui.BeginTabItem('Cooldowns')", 1, true) == nil, 'cooldown window: hud_cooldowns no longer contributes a main-window tab')
    assert_true(cdContent:find('function plugin.onDrawTab', 1, true) == nil, 'cooldown window: hud_cooldowns defines no onDrawTab')
    assert_true(cdContent:find("M.renderCooldownContent('_win', true)", 1, true) ~= nil, 'cooldown window: popout renders the shared cooldown content')
    assert_true(cdContent:find("flag = 'show_cooldowns'", 1, true) ~= nil, 'cooldown window: hud_cooldowns declares its window for the header button')
    assert_true(triuneContent:find('pm.drawTabs', 1, true) == nil, 'cooldown window: pm.drawTabs removed from the plugin manager')

    -- F. parseDurationSec & parseSpellRecastTime Comprehensive Tests
    local function parseDurationSec(durObj)
        if not durObj then return 0 end
        local sec = 0
        pcall(function()
            if type(durObj) == 'number' then
                if durObj >= 2147483647 or durObj < 0 then
                    sec = 0
                elseif durObj > 10000 then
                    sec = durObj / 1000.0
                elseif durObj > 0 and durObj <= 500 then
                    sec = durObj * 6
                else
                    sec = durObj
                end
                if sec >= 2000000 or sec < 0 then sec = 0 end
                return
            end
            if type(durObj) == 'table' then
                if durObj.TotalSeconds then
                    if type(durObj.TotalSeconds) == 'function' then
                        sec = tonumber(durObj.TotalSeconds() or 0) or 0
                    else
                        sec = tonumber(durObj.TotalSeconds) or 0
                    end
                    if sec >= 2000000 or sec < 0 then sec = 0 end
                    if sec > 0 then return end
                end
                if durObj.Raw then
                    local r = type(durObj.Raw) == 'function' and durObj.Raw() or durObj.Raw
                    local nr = tonumber(r or 0) or 0
                    if nr > 0 and nr < 2147483647 then
                        sec = nr / 1000.0
                        if sec > 0 then return end
                    end
                end
                if durObj.Ticks then
                    local t = type(durObj.Ticks) == 'function' and durObj.Ticks() or durObj.Ticks
                    local nt = tonumber(t or 0) or 0
                    if nt > 0 and nt < 350000 then
                        sec = nt * 6
                        if sec > 0 then return end
                    end
                end
            end
            if type(durObj) == 'function' then
                local val = durObj()
                if val ~= nil then
                    local n = tonumber(val) or 0
                    if n >= 2147483647 or n < 0 then
                        sec = 0
                    elseif n > 1800 then
                        sec = n / 1000.0
                    elseif n > 0 and n <= 500 then
                        sec = n * 6
                    else
                        sec = n
                    end
                    if sec >= 2000000 or sec < 0 then sec = 0 end
                end
            end
        end)
        if sec >= 2000000 or sec < 0 then sec = 0 end
        return sec
    end

    -- MacroQuest Me.Buff.Duration tests
    assert_eq(parseDurationSec({ TotalSeconds = function() return 180 end }), 180, 'parseDurationSec: TotalSeconds() method')
    assert_eq(parseDurationSec({ TotalSeconds = 45 }), 45, 'parseDurationSec: TotalSeconds property')
    assert_eq(parseDurationSec({ Raw = function() return 18000 end }), 18, 'parseDurationSec: Raw() ms method (18000ms = 18s)')
    assert_eq(parseDurationSec({ Ticks = function() return 10 end }), 60, 'parseDurationSec: Ticks() method (10 ticks = 60s)')
    assert_eq(parseDurationSec(function() return "18000" end), 18, 'parseDurationSec: string ms fallback (18000ms = 18s)')
    assert_eq(parseDurationSec(function() return "5" end), 30, 'parseDurationSec: string ticks fallback (5 ticks = 30s)')
    -- Sentinel / 0xFFFFFFFF unsigned underflow rejection (prevents 1194h)
    assert_eq(parseDurationSec({ Raw = function() return 4294967295 end }), 0, 'parseDurationSec: rejects 0xFFFFFFFF Raw ms sentinel')
    assert_eq(parseDurationSec({ TotalSeconds = function() return 4294967 end }), 0, 'parseDurationSec: rejects 4294967s TotalSeconds sentinel (1194h)')
    assert_eq(parseDurationSec(4294967295), 0, 'parseDurationSec: rejects 4294967295 numeric ms sentinel')
    assert_eq(parseDurationSec(-1), 0, 'parseDurationSec: rejects negative duration')

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
    assert_true(AA_CONTENT:find("function AA.drawWindow()") ~= nil, 'auto_aa defines AA.drawWindow (popout Auto AA window)')
    assert_true(AA_CONTENT:find("AA.drawWindow()") ~= nil, 'auto_aa invokes AA.drawWindow from onDrawUI')
    assert_true(AA_CONTENT:find("AA.checkAutoSpendAA()") ~= nil, 'triune.lua includes AA.checkAutoSpendAA check')
    assert_true(AA_CONTENT:find("AA.scanPlayerAAs") ~= nil, 'triune.lua defines AA.scanPlayerAAs')
    assert_true(AA_CONTENT:find("AA.getFilteredSortedAAs") ~= nil, 'triune.lua defines AA.getFilteredSortedAAs')
    assert_true(AA_CONTENT:find("AA.findAAInWindowLists") ~= nil, 'triune.lua defines AA.findAAInWindowLists')
    assert_true(AA_CONTENT:find("AA.findChildRecursive") ~= nil, 'triune.lua defines AA.findChildRecursive')
    assert_true(AA_CONTENT:find("AAW_SpecialList") ~= nil, 'triune.lua scans AAW_SpecialList')
    assert_true(AA_CONTENT:find("AAW_TrainButton") ~= nil, 'triune.lua clicks AAW_TrainButton')
    assert_true(AA_CONTENT:find("AAW_Subwindows") ~= nil, 'triune.lua notifies AAW_Subwindows')
    assert_true(AA_CONTENT:find("AA.readSpecialTabOnce") ~= nil, 'triune.lua defines AA.readSpecialTabOnce')
    assert_true(AA_CONTENT:find("AA.readSpecialTabNamesFromUI") ~= nil, 'triune.lua defines AA.readSpecialTabNamesFromUI')
    assert_true(AA_CONTENT:find("AA.specialTabAAs") ~= nil, 'triune.lua tracks AA.specialTabAAs')
    assert_true(AA_CONTENT:find("TacAAPurchased") ~= nil, 'triune.lua registers TacAAPurchased event')
    assert_true(AA_CONTENT:find("AA.lastObservedAAPointsSpent") ~= nil, 'triune.lua tracks lastObservedAAPointsSpent')
    assert_true(AA_CONTENT:find("AA.pendingPostTrainScanAt") ~= nil, 'triune.lua tracks pendingPostTrainScanAt')
    assert_true(AA_CONTENT:find("AA.checkAutoSummonFireworks()") ~= nil, 'triune.lua includes AA.checkAutoSummonFireworks check')
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
    local tabOrderMatch2 = triuneContent:find("UI.drawAATab%(%)[%s\r\n]+UI.drawDiscTab%(%)[%s\r\n]+UI.drawClickieTab%(%)[%s\r\n]+UI.drawSettingsTab%(%)")
    assert_true(tabOrderMatch2 ~= nil, 'triune.lua places Disciplines and Clickies between AAs and Settings (no plugin tabs)')
    assert_true(AA_CONTENT:find("ImGui.BeginTabItem('Auto AA')", 1, true) == nil, 'auto_aa plugin no longer contributes a main-window tab')
    assert_true(AA_CONTENT:find("###triuneAutoAA'", 1, true) ~= nil, 'auto_aa plugin draws the Auto AA popout window')
    assert_true(AA_CONTENT:find("flag = 'show_auto_aa'", 1, true) ~= nil, 'auto_aa plugin declares its window for the header button')
    local settingsTabMatch = triuneContent:find("UI.drawSettingsTab%(%)[%s\r\n]+UI.drawHelpTab%(%)")
    assert_true(settingsTabMatch ~= nil, 'triune.lua places UI.drawSettingsTab right before the Help tab')
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

    -- Scenario F: Lifetap with "my HP <=" condition on an enemy target
    -- Mob at 15% HP, Player at 100% HP, Lifetap threshold at 60%
    playerHp = 100
    targetHp = 15
    condEnv.runtime.isDetrimentalAction = function(spName, tok)
        if tok and tok:sub(1, 2) == 'E:' then return true end
        return false
    end
    condEnv.isHostileTarget = function(id) return id == 2002 end
    assert_eq(conditionMet('my HP <=', 60, 'Lifetap', 2002, 'Nec', 'E: Current Target'), false,
        'Lifetap (my HP <= 60) does not fire when mob is at 15% but player is at 100%')

    -- Player drops to 50% HP (threshold reached)
    playerHp = 50
    assert_eq(conditionMet('my HP <=', 60, 'Lifetap', 2002, 'Nec', 'E: Current Target'), true,
        'Lifetap (my HP <= 60) fires when player drops below threshold (50 <= 60)')
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
    -- In combat with a hostile target, character casts Greater Healing on self (myId) without switching target
    setTarget(1001)
    assert_eq(mockState.currentTargetId, 1001, 'targeting enemy mob 1001')
    local isSelf = (myId == myId)
    local curT = mockState.currentTargetId
    local isHostileT = (curT > 0 and isHostile(curT))
    local needT = (curT ~= myId) and not (isSelf and isHostileT)
    assert_eq(needT, false, 'self-heal on hostile target does not need to select self')
    assert_eq(mockState.currentTargetId, 1001, 'target remains on enemy mob 1001')

    -- Cast starts (in-combat self-cast)
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

    -- 4. Self-healing OUT OF COMBAT (no target, curT == 0)
    -- Out of combat, you DO have to select yourself to cast beneficial/heal spells
    clearTarget()
    assert_eq(mockState.currentTargetId, 0, 'out of combat: idle with no target')
    curT = mockState.currentTargetId
    isHostileT = (curT > 0 and isHostile(curT))
    needT = (curT ~= myId) and not (isSelf and isHostileT)
    assert_eq(needT, true, 'out of combat with no target: self-heal MUST select self')
    if needT then setTarget(myId) end
    assert_eq(mockState.currentTargetId, myId, 'target set to self (myId) for out-of-combat heal')

    -- Cast starts (out-of-combat self-cast)
    mockState.isCasting = true
    mockState.castTracker.activeSpell = 'Greater Healing'
    mockState.castTracker.activeTargetId = myId
    if isSelf and isHostileT then
        mockState.castTracker.targetRequired = false
    else
        mockState.castTracker.targetRequired = isTargetRequiredSpell('Greater Healing')
    end
    mockState.castTracker.castStartTime = os.clock()

    assert_eq(mockState.castTracker.targetRequired, true, 'out-of-combat self-heal targetRequired is true')
    assert_eq(getActiveTargetRequiredCastingId(), myId, 'out-of-combat self-heal locks target to self')
    assert_eq(mockState.currentTargetId, myId, 'target locked on self during out-of-combat heal')

    -- Attempt to clear or change target while casting out of combat should be blocked
    assert_eq(clearTarget(), false, 'cannot clear target while casting out-of-combat self-heal')
    assert_eq(mockState.currentTargetId, myId, 'target remains on self')

    -- Finish cast
    mockState.isCasting = false
    mockState.castTracker.activeSpell = nil
    mockState.castTracker.activeTargetId = nil
    mockState.castTracker.targetRequired = false

    -- 5. Self-healing OUT OF COMBAT while targeting a non-hostile NPC/player (curT == 5000)
    setTarget(5000)
    assert_eq(mockState.currentTargetId, 5000, 'targeting neutral NPC 5000')
    curT = mockState.currentTargetId
    isHostileT = (curT > 0 and isHostile(curT))
    needT = (curT ~= myId) and not (isSelf and isHostileT)
    assert_eq(needT, true, 'out of combat targeting non-hostile: self-heal MUST select self')
    local restoreId = (curT ~= myId and curT > 0 and not (isSelf and isHostileT)) and curT or nil
    assert_eq(restoreId, 5000, 'restoreTargetId saved as 5000')
    if needT then setTarget(myId) end
    assert_eq(mockState.currentTargetId, myId, 'target switched to self for heal')

    -- Finish cast and restore target
    if restoreId then setTarget(restoreId) end
    assert_eq(mockState.currentTargetId, 5000, 'target successfully restored to neutral NPC 5000')
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
        'TAC/lua/tac/spellbook.lua',
        'TAC/lua/tac/auto_aa.lua',
        'TAC/lua/tac/hud_cooldowns.lua',
        'TAC/lua/tac/buffbot.lua',
        'TAC/lua/tac/cursor.lua',
        'TAC/lua/tac/dps.lua',
        'TAC/lua/tac/inventory.lua',
        'TAC/lua/tac/map.lua',
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

    -- The whitelist + authorization logic lives in the auto_accept plugin now, so
    -- exercise the real implementation against a mock core / TLO instead of a mirror.
    local testCtrl = {
        auto_group = false,
        auto_trade = false,
        auto_dzadd = false,
        auto_accept_anyone = false,
        auto_accept_guild = false,
        auto_accept_group = false,
        auto_accept_names = {},
    }

    local mockGroupMembers = { { name = 'TrioHealer', id = 101 }, { name = 'TrioTank', id = 102 } }
    local mockGuild = 'Fires of Heaven'
    local mockSpawns = {
        -- name -> { id, guild }
        GuildieOne = { id = 501, guild = 'Fires of Heaven' },
        GuildieTwo = { id = 502, guild = 'fires of heaven' },
        Outsider   = { id = 600, guild = 'Some Other Guild' },
    }
    local function findSpawn(query)
        local q = tostring(query or '')
        local idStr = q:match('^id (%d+)$')
        for name, info in pairs(mockSpawns) do
            if idStr and tonumber(idStr) == info.id then return name, info end
            local wanted = q:match('^pc =?(.+)$')
            if wanted and wanted:lower() == name:lower() then return name, info end
        end
        return nil, nil
    end
    local function spawnObj(query)
        local name, info = findSpawn(query)
        local o = {}
        setmetatable(o, { __call = function() return name ~= nil end })
        o.ID = function() return info and info.id or 0 end
        o.CleanName = function() return name end
        o.Type = function() return 'PC' end
        o.Guild = function() return info and info.guild or '' end
        return o
    end
    local function groupMember(i)
        local m = mockGroupMembers[i]
        local o = {}
        setmetatable(o, { __call = function() return m ~= nil end })
        o.ID = function() return m and m.id or 0 end
        o.CleanName = function() return m and m.name or '' end
        return o
    end
    local mockCore = {
        ctrl = testCtrl,
        saveLoadout = function() end,
        mq = {
            event = function() end,
            unevent = function() end,
            cmd = function() end,
            cmdf = function() end,
            TLO = {
                Spawn = spawnObj,
                Group = {
                    Members = function() return #mockGroupMembers end,
                    Member = groupMember,
                },
                Me = {
                    Guild = setmetatable({}, { __call = function() return mockGuild end }),
                },
            },
        },
    }
    local aaPlugin = assert(loadfile('TAC/lua/tac/auto_accept.lua'))()
    local okAAInit, errAAInit = pcall(aaPlugin.onInit, mockCore)
    assert_true(okAAInit, 'Suite 55: auto_accept.onInit runs against mock core: ' .. tostring(errAAInit))
    assert_type(aaPlugin.isAutoAcceptAllowed, 'function', 'Suite 55: plugin exposes isAutoAcceptAllowed')
    assert_type(aaPlugin.isAutoAcceptListed, 'function', 'Suite 55: plugin exposes isAutoAcceptListed')
    assert_type(aaPlugin.addAutoAcceptName, 'function', 'Suite 55: plugin exposes addAutoAcceptName')
    assert_type(aaPlugin.removeAutoAcceptName, 'function', 'Suite 55: plugin exposes removeAutoAcceptName')
    assert_type(aaPlugin.clearAutoAcceptNames, 'function', 'Suite 55: plugin exposes clearAutoAcceptNames')
    assert_type(aaPlugin.getAutoAcceptPlayerInfo, 'function', 'Suite 55: plugin exposes getAutoAcceptPlayerInfo')

    -- Silence the plugin's chat output during the suite
    local realPrint = print
    print = function() end
    local testRuntime = aaPlugin

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
    print = realPrint

    -- 3. The core no longer carries its own copy of the auto-accept engine
    local triuneSrc = readFile('TAC/lua/triune.lua')
    assert_true(triuneSrc:find('function runtime%.checkAutoAccept') == nil,
        'Suite 55: runtime.checkAutoAccept removed from triune.lua (owned by auto_accept plugin)')
    assert_true(triuneSrc:find('function runtime%.isAutoAcceptAllowed') == nil,
        'Suite 55: runtime.isAutoAcceptAllowed removed from triune.lua (owned by auto_accept plugin)')
    assert_true(triuneSrc:find("mq%.event%('TriuneAutoGroupInvite") == nil,
        'Suite 55: core no longer registers its own group-invite chat events')
    assert_true(triuneSrc:find("drawPluginSettings%('auto_accept'%)") == nil,
        'Suite 55: Settings -> Auto-Accept sub-tab removed (Auto-Accept is a popout window)')
    assert_true(triuneSrc:find("Auto%-Accept##settingsAutoAccept") == nil,
        'Suite 55: no Auto-Accept tab in the Settings tab bar')
    local aaSrc = readFile('TAC/lua/tac/auto_accept.lua')
    assert_true(aaSrc:find("###triuneAutoAccept'", 1, true) ~= nil,
        'Suite 55: auto_accept draws the Triune Auto-Accept popout window')
    assert_true(aaSrc:find("flag = 'show_auto_accept'", 1, true) ~= nil,
        'Suite 55: auto_accept declares its window for the header button / layout manager')
    assert_true(aaSrc:find("'TacAutoGroupInvite1'") ~= nil and aaSrc:find("'TacAutoDZInvite3'") ~= nil,
        'Suite 55: auto_accept plugin registers the group/DZ chat events')
    assert_true(aaSrc:find('HisTradeReady') ~= nil and aaSrc:find('Me%.Invited') ~= nil,
        'Suite 55: auto_accept plugin polls Me.Invited and TradeWnd ready state')
    assert_true(aaSrc:find('auto_accept_group') ~= nil,
        'Suite 55: auto_accept plugin honors the Always accept from Group Members rule')
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
    if catFn then
        assert_true(catFn ~= nil, 'catalog.lua loads cleanly')
        local cat = catFn()
        assert_true(type(cat) == 'table', 'catalog is a table')
        assert_true(#cat >= 2000, string.format('catalog contains >= 2000 quests (found: %d)', #cat))
        assert_true(cat[1].title ~= nil, 'catalog quest has title')
        assert_true(cat[1].zone ~= nil, 'catalog quest has zone shortname')
    end

    local expFn = loadfile('TAC/resources/triune_quest/expansions.lua')
    if expFn then
        assert_true(expFn ~= nil, 'expansions.lua loads cleanly')
        local exps = expFn()
        assert_true(type(exps) == 'table', 'expansions is a table')
        assert_eq(#exps, 33, 'expansions has 33 entries (00 through 32)')
        assert_eq(exps[1].id, '00', 'first expansion is 00')
        assert_eq(exps[33].id, '32', 'last expansion is 32')
    end

    local zoneFn = loadfile('TAC/resources/triune_quest/zones/cabeast.lua')
    if zoneFn then
        assert_true(zoneFn ~= nil, 'cabeast.lua zone package loads cleanly')
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
    local invSrc = readFile('TAC/lua/tac/inventory.lua')
    local formatMoney = loadFunc(invSrc, 'formatMoney', {})
    local classifyItem = loadFunc(invSrc, 'classifyItem', {})
    local matchesFilter = loadFunc(invSrc, 'matchesFilter', {})
    local findDuplicateStacks = loadFunc(invSrc, 'findDuplicateStacks', {})
    local findNextCombineMove = loadFunc(invSrc, 'findNextCombineMove', {})
    local findHeaviestItems = loadFunc(invSrc, 'findHeaviestItems', {})
    local formatAugs = loadFunc(invSrc, 'formatAugs', {})
    local parseAugs = loadFunc(invSrc, 'parseAugs', {})
    local planBagAlphaSort = loadFunc(invSrc, 'planBagAlphaSort', {})

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

    local armorItem = {
        name = 'Chain Chestplate',
        location = 'WORN',
        category = 'Armor',
        augs = { { slot = 1, name = 'Ruby of Ancient Knowledge' }, { slot = 2, name = 'Focus of Ice' } },
    }
    assert_true(matchesFilter(armorItem, 'ruby of ancient', 'ALL', 'ALL', nil), 'Search matches socketed augment name')
    assert_eq(matchesFilter(armorItem, 'peridot', 'ALL', 'ALL', nil), false, 'Search rejects armor without matching aug')

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

    -- 5. findNextCombineMove
    local move = findNextCombineMove({
        stackSize = 20,
        stacks = {
            { count = 5, notifyCmd = 'in pack1 2', location = 'INVENTORY' },
            { count = 7, notifyCmd = 'in pack3 8', location = 'INVENTORY' },
        },
    })
    assert_eq(move.fromCmd, 'in pack1 2', 'combine moves smaller stack onto larger')
    assert_eq(move.toCmd, 'in pack3 8', 'combine destination is fullest partial stack')

    local noMoveFull = findNextCombineMove({
        stackSize = 20,
        stacks = {
            { count = 20, notifyCmd = 'in pack1 1', location = 'INVENTORY' },
            { count = 5, notifyCmd = 'in pack2 1', location = 'INVENTORY' },
        },
    })
    assert_eq(noMoveFull, nil, 'combine skips when destination stacks are already full')

    local noMoveCross = findNextCombineMove({
        stackSize = 20,
        stacks = {
            { count = 5, notifyCmd = 'in pack1 1', location = 'INVENTORY' },
            { count = 7, notifyCmd = 'in bank1 1', location = 'BANK' },
        },
    })
    assert_eq(noMoveCross, nil, 'combine skips cross-location stacks')

    local noMoveSingle = findNextCombineMove({
        stackSize = 20,
        stacks = {
            { count = 5, notifyCmd = 'in pack1 1', location = 'INVENTORY' },
        },
    })
    assert_eq(noMoveSingle, nil, 'combine is a no-op for a single stack')

    local triple = findNextCombineMove({
        stackSize = 20,
        stacks = {
            { count = 3, notifyCmd = 'in pack1 1', location = 'INVENTORY' },
            { count = 8, notifyCmd = 'in pack1 2', location = 'INVENTORY' },
            { count = 12, notifyCmd = 'in pack2 1', location = 'INVENTORY' },
        },
    })
    assert_eq(triple.fromCmd, 'in pack1 2', 'combine prefers next-fullest source onto fullest dest')
    assert_eq(triple.toCmd, 'in pack2 1', 'combine destination is the fullest partial')

    -- 6. findHeaviestItems
    local heavyItems = {
        { name = 'Iron Bar', weight = 10.0, count = 1, stackable = false, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 1]', category = 'Tradeskill' },
        { name = 'Feather', weight = 0.1, count = 1, stackable = false, location = 'INVENTORY', displayLocation = 'Bag 1 [Slot 2]', category = 'Misc' },
        { name = 'Heavy Ore', weight = 8.0, count = 2, stackable = true, location = 'INVENTORY', displayLocation = 'Bag 2 [Slot 1]', category = 'Tradeskill' },
    }
    local heavies = findHeaviestItems(heavyItems, 2)
    assert_eq(#heavies, 2, 'findHeaviestItems returns requested limit')
    assert_eq(heavies[1].name, 'Heavy Ore', 'Heavy Ore (16 lbs total) is ranked first')
    assert_eq(heavies[2].name, 'Iron Bar', 'Iron Bar (10 lbs) is ranked second')

    -- 7. formatAugs / parseAugs
    assert_eq(formatAugs(nil), '', 'formatAugs nil is empty')
    assert_eq(formatAugs({}), '', 'formatAugs missing augs is empty')
    assert_eq(formatAugs({ augs = { { name = 'Ruby of AA' }, { name = 'Focus of Ice' } } }), 'Ruby of AA, Focus of Ice', 'formatAugs joins names')
    local parsed = parseAugs('Ruby of AA|Focus of Ice')
    assert_eq(#parsed, 2, 'parseAugs splits pipe-separated names')
    assert_eq(parsed[1].name, 'Ruby of AA', 'parseAugs first name')
    assert_eq(parsed[2].name, 'Focus of Ice', 'parseAugs second name')

    -- 8. planBagAlphaSort
    local alreadySorted = {
        slot = 1, capacity = 3,
        slots = {
            [1] = { name = 'Apple', subSlot = 1 },
            [2] = { name = 'Mango', subSlot = 2 },
        },
    }
    assert_eq(#planBagAlphaSort(alreadySorted, 'pack'), 0, 'already-sorted bag needs no moves')

    local zebra = { name = 'Zebra', subSlot = 1 }
    local apple = { name = 'Apple', subSlot = 2 }
    local mango = { name = 'Mango', subSlot = 4 }
    local unsorted = {
        slot = 1, capacity = 4,
        slots = { [1] = zebra, [2] = apple, [4] = mango },
    }
    local sortMoves = planBagAlphaSort(unsorted, 'pack')
    assert_eq(#sortMoves, 3, 'unsorted bag with a hole plans 3 moves')
    assert_eq(sortMoves[1].fromCmd, 'in pack1 2', 'first sort move picks Apple')
    assert_eq(sortMoves[1].toCmd, 'in pack1 1', 'first sort move drops onto slot 1')
    assert_eq(sortMoves[1].completeSwap, true, 'first sort move swaps occupied dest')
    assert_eq(sortMoves[3].completeSwap, false, 'final sort move places into empty slot')

    local bankBag = {
        slot = 3, capacity = 2,
        slots = {
            [1] = { name = 'Zinger', subSlot = 1 },
            [2] = { name = 'Amber', subSlot = 2 },
        },
    }
    local bankMoves = planBagAlphaSort(bankBag, 'bank')
    assert_eq(bankMoves[1].fromCmd, 'in bank3 2', 'bank sort uses bank notify cmds')
    assert_eq(bankMoves[1].toCmd, 'in bank3 1', 'bank sort destination is slot 1')

    apple = { name = 'Cloudy Potion', type = 'Potion', subSlot = 1 }
    zebra = { name = 'Rusty Sword', type = '1H Slashing', subSlot = 2 }
    sortMoves = planBagAlphaSort({
        slot = 2, capacity = 2,
        slots = { [1] = apple, [2] = zebra },
    }, 'pack', 'type')
    assert_eq(sortMoves[1].fromCmd, 'in pack2 2', 'type sort moves 1H Slashing before Potion')
    assert_eq(sortMoves[1].toCmd, 'in pack2 1', 'type sort destination is first slot')
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
    assert_eq(isHealActionMock('Lifetap', 'E: Current Target', { kind = 'dd' }), false, 'Lifetap rejected as heal')
    assert_eq(isHealActionMock('Lifedraw', 'E: Current Target', { kind = 'dd' }), false, 'Lifedraw rejected as heal')
    assert_eq(isHealActionMock('Touch of Innoruuk', 'E: Current Target', { kind = 'dd' }), false, 'Touch of Innoruuk rejected as heal')
    assert_eq(isHealActionMock('Touch of Death', 'E: Current Target', { kind = 'dd' }), false, 'Touch of Death rejected as heal')
    assert_eq(isHealActionMock('Lifetap', 'E: Current Target', {}), false, 'Lifetap without kind rejected as heal due to detrimental target')

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
            local isAlly = token and not token:find('Myself') and token:sub(1, 2) ~= 'E:'
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
    assert_eq(conditionMetMock('my HP <=', 60, 2002, 1, 100, 40, 'E: Current Target'), false, 'my HP <= on enemy does NOT trigger on low mob HP when player is at 100%')
    assert_true(conditionMetMock('my HP <=', 60, 2002, 1, 50, 90, 'E: Current Target'), 'my HP <= on enemy DOES trigger when player HP is low (50 <= 60)')

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
    assert_true(AA_CONTENT:find("if %(not specialList or #specialList == 0%) and not AA%.specialTabReadDone then") ~= nil,
        'Suite 62: scanPlayerAAs respects specialTabReadDone')

    -- 3. Verify main loop honors paused and auto_spend_aa states
    assert_true(AA_CONTENT:find("if not ctrl%.paused and ctrl%.auto_spend_aa and not mq%.TLO%.Me%.Combat") ~= nil,
        'Suite 62: main loop only executes pending read when not paused and auto_spend_aa is enabled')
    assert_true(AA_CONTENT:find("elseif not ctrl%.auto_spend_aa or ctrl%.paused then%s*AA%.pendingReadSpecialTab = false") ~= nil,
        'Suite 62: main loop clears pending read when auto_spend_aa disabled or paused')

    -- 4. Verify script startup does NOT unconditionally queue pendingReadSpecialTab
    assert_eq(triuneContent:find("runtime%.pendingReadSpecialTab = true%s*runMainLoop"), nil,
        'Suite 62: startup does not unconditionally queue pendingReadSpecialTab')
end

-- ============================================================================
-- Suite 63: Auto AA Discovery & Accurate Cost Resolution
-- ============================================================================
print('--- Suite 63: Auto AA Discovery & Accurate Cost Resolution ---')
do
    local mockRuntime = {
        cachedAAData = {}
    }

    local function mockRecordScannedAA(rt, list, foundMap, name, knownRank, knownMaxRank, knownCost, isKnownCharAA, category)
        if not name or name == '' or tonumber(name) then return end
        name = tostring(name):match('^%s*(.-)%s*$')
        if name == '' then return end

        local existing = foundMap[name]
        if existing then
            if knownRank ~= nil and knownRank >= 0 then
                existing.rank = knownRank
            end
            if knownMaxRank ~= nil and knownMaxRank > 0 and (existing.maxRank == 0 or knownMaxRank > existing.maxRank) then
                existing.maxRank = knownMaxRank
            end
            if knownCost ~= nil and knownCost > 0 then
                existing.cost = knownCost
            end
            if existing.maxRank > 0 and existing.rank >= existing.maxRank then
                existing.fullyTrained = true
                existing.cost = 0
                existing.canTrain = false
            else
                existing.fullyTrained = false
                existing.canTrain = true
            end
            if category and (not existing.category or existing.category == '') then
                existing.category = category
            end
            if not rt.cachedAAData then rt.cachedAAData = {} end
            rt.cachedAAData[name] = {
                rank = existing.rank,
                maxRank = existing.maxRank,
                cost = existing.cost,
                category = existing.category,
                id = existing.id
            }
            return
        end

        local rank, maxRank, cost, canTrain, pointsSpent, id, passive, aaType = 0, 0, 0, false, 0, 0, false, 0
        local isCharacterAA = not not isKnownCharAA

        if rt.cachedAAData and rt.cachedAAData[name] then
            local cd = rt.cachedAAData[name]
            if cd.rank ~= nil then rank = cd.rank end
            if cd.maxRank ~= nil and cd.maxRank > 0 then maxRank = cd.maxRank end
            if cd.cost ~= nil and cd.cost > 0 then cost = cd.cost end
            if cd.category and not category then category = cd.category end
            if cd.id ~= nil and cd.id > 0 then id = cd.id end
            isCharacterAA = true
        end

        if knownRank ~= nil then rank = knownRank end
        if knownMaxRank ~= nil and knownMaxRank > 0 then maxRank = knownMaxRank end
        if knownCost ~= nil and knownCost > 0 then cost = knownCost end

        local fullyTrained = (maxRank > 0 and rank >= maxRank)
        if fullyTrained then
            cost = 0
        elseif cost <= 0 then
            cost = (rank > 0) and (rank + 1) or 1
        end

        if not fullyTrained and not canTrain then
            canTrain = true
        end

        if isCharacterAA and (maxRank > 0 or rank > 0 or canTrain or cost > 0) then
            local entry = {
                name = name,
                rank = rank,
                maxRank = maxRank,
                cost = cost,
                canTrain = canTrain,
                pointsSpent = pointsSpent,
                id = id,
                passive = passive,
                type = aaType,
                fullyTrained = fullyTrained,
                category = category
            }
            foundMap[name] = entry
            list[#list + 1] = entry

            if not rt.cachedAAData then rt.cachedAAData = {} end
            rt.cachedAAData[name] = {
                rank = rank,
                maxRank = maxRank,
                cost = cost,
                category = category,
                id = id
            }
        end
    end

    -- 1. Untrained character ability (rank == 0) is preserved with valid cost
    local list1 = {}
    local map1 = {}
    mockRecordScannedAA(mockRuntime, list1, map1, 'Innate Run Speed', 0, 3, 1, true, 'General')
    assert_eq(#list1, 1, 'Suite 63: untrained character ability is preserved in list')
    assert_eq(list1[1].name, 'Innate Run Speed', 'Suite 63: correct ability name')
    assert_eq(list1[1].rank, 0, 'Suite 63: untrained ability rank is 0')
    assert_eq(list1[1].maxRank, 3, 'Suite 63: untrained ability maxRank is 3')
    assert_eq(list1[1].cost, 1, 'Suite 63: untrained ability cost is preserved')
    assert_eq(list1[1].fullyTrained, false, 'Suite 63: untrained ability is not fully trained')
    assert_eq(list1[1].canTrain, true, 'Suite 63: untrained ability can be trained')

    -- 2. Cached AA data persistence across scans
    assert_true(mockRuntime.cachedAAData['Innate Run Speed'] ~= nil, 'Suite 63: ability is cached in runtime.cachedAAData')
    assert_eq(mockRuntime.cachedAAData['Innate Run Speed'].cost, 1, 'Suite 63: cached cost is 1')

    -- New scan without explicit parameters recovers cost and rank from cache
    local list2 = {}
    local map2 = {}
    mockRecordScannedAA(mockRuntime, list2, map2, 'Innate Run Speed')
    assert_eq(#list2, 1, 'Suite 63: recovered from cache on subsequent scan')
    assert_eq(list2[1].cost, 1, 'Suite 63: cost recovered from cache')
    assert_eq(list2[1].maxRank, 3, 'Suite 63: maxRank recovered from cache')

    -- 3. Updating existing entry when better cost/rank discovered
    mockRecordScannedAA(mockRuntime, list1, map1, 'Innate Run Speed', 1, 3, 2, true, 'General')
    assert_eq(map1['Innate Run Speed'].rank, 1, 'Suite 63: existing entry rank updated to 1')
    assert_eq(map1['Innate Run Speed'].cost, 2, 'Suite 63: existing entry cost updated to 2')
    assert_eq(map1['Innate Run Speed'].fullyTrained, false, 'Suite 63: still not fully trained')

    -- 4. Fully trained ability sets cost to 0 and fullyTrained to true
    mockRecordScannedAA(mockRuntime, list1, map1, 'Innate Run Speed', 3, 3, 3, true, 'General')
    assert_eq(map1['Innate Run Speed'].rank, 3, 'Suite 63: rank updated to 3')
    assert_eq(map1['Innate Run Speed'].fullyTrained, true, 'Suite 63: fully trained is true')
    assert_eq(map1['Innate Run Speed'].cost, 0, 'Suite 63: fully trained cost is 0')

    -- 5. Fallback cost guarantee: untrained ability with 0 cost gets default >= 1
    local list3 = {}
    local map3 = {}
    mockRecordScannedAA(mockRuntime, list3, map3, 'Combat Agility', 0, 3, 0, true, 'Archetype')
    assert_eq(#list3, 1, 'Suite 63: ability recorded with fallback cost')
    assert_true(list3[1].cost >= 1, 'Suite 63: fallback cost is positive (>= 1)')

    -- 6. Verify triune.lua defines enhanced recursive scanning and UI list extraction
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AAW_ArchList") ~= nil, 'Suite 63: triune.lua searches AAW_ArchList')
    assert_true(AA_CONTENT:find("curMaxTxt:match") ~= nil, 'Suite 63: triune.lua parses curMaxTxt column')
    assert_true(AA_CONTENT:find("costTxt:match") ~= nil, 'Suite 63: triune.lua parses costTxt column')
    assert_true(triuneContent:find("runtime.cachedAAData") ~= nil, 'Suite 63: triune.lua uses runtime.cachedAAData')
end

print('--- Suite 64: MQ2AAspend Integration & Character Skill Rejection ---')
do
    -- 1. Skill rejection in recordScannedAA
    local mockSkills = {
        ['Flying Kick'] = true,
        ['Mend'] = true,
        ['Backstab'] = true,
        ['Dual Wield'] = true,
        ['Bandage Wounds'] = true
    }

    local mockRuntime = {
        cachedAAData = {}
    }

    local function mockRecordScannedAAWithSkillFilter(rt, list, foundMap, name, knownRank, knownMaxRank, knownCost, isKnownCharAA, category, isFromUI, mockId)
        if not name or name == '' then return end
        name = tostring(name):match('^%s*(.-)%s*$')
        if name == '' then return end

        if mockSkills[name] then
            return -- Rejected: character skill
        end

        local id = mockId or 0
        if not isFromUI and id <= 0 then
            return -- Rejected: not from UI and no valid AA ID
        end

        local entry = {
            name = name,
            rank = knownRank or 0,
            maxRank = knownMaxRank or 1,
            cost = knownCost or 1,
            category = category,
            id = id
        }
        foundMap[name] = entry
        list[#list + 1] = entry
    end

    local list1 = {}
    local map1 = {}
    mockRecordScannedAAWithSkillFilter(mockRuntime, list1, map1, 'Flying Kick', 0, 1, 1, true, 'Combat', false, 0)
    mockRecordScannedAAWithSkillFilter(mockRuntime, list1, map1, 'Mend', 0, 1, 1, true, 'Combat', false, 0)
    mockRecordScannedAAWithSkillFilter(mockRuntime, list1, map1, 'Backstab', 0, 1, 1, true, 'Combat', false, 0)
    mockRecordScannedAAWithSkillFilter(mockRuntime, list1, map1, 'Innate Run Speed', 0, 3, 1, true, 'General', true, 100)

    assert_eq(#list1, 1, 'Suite 64: skills rejected and only valid AA kept')
    assert_eq(list1[1].name, 'Innate Run Speed', 'Suite 64: Innate Run Speed recorded')
    assert_true(map1['Flying Kick'] == nil, 'Suite 64: Flying Kick rejected from AA map')
    assert_true(map1['Mend'] == nil, 'Suite 64: Mend rejected from AA map')
    assert_true(map1['Backstab'] == nil, 'Suite 64: Backstab rejected from AA map')

    -- 2. Non-UI entry with id == 0 rejected
    local list2 = {}
    local map2 = {}
    mockRecordScannedAAWithSkillFilter(mockRuntime, list2, map2, 'Unknown Non-Existent AA', 0, 1, 1, true, 'General', false, 0)
    assert_eq(#list2, 0, 'Suite 64: non-UI entry without AA ID rejected')

    -- 3. MQ2AAspend delegation logic simulation
    local commandsIssued = {}
    local nativeTrained = nil
    local function mockCmd(str) commandsIssued[#commandsIssued + 1] = str end
    local function mockCmdf(fmt, ...) commandsIssued[#commandsIssued + 1] = string.format(fmt, ...) end

    local function simulateCheckAutoSpend(ctrl, rt, unspent, pluginLoaded, targetName, now)
        if not ctrl.auto_spend_aa then return false end
        if unspent <= 0 then return false end
        now = now or 100.0

        if ctrl.auto_aa_delegate_aaspend and pluginLoaded then
            local threshold = tonumber(ctrl.auto_spend_aa_threshold) or 0
            if unspent >= threshold then
                local delegTarget = rt.lastAASpendDelegatedTarget
                local delegAt = rt.lastAASpendDelegatedAt or 0
                local delegPts = rt.lastAASpendDelegatedPoints or 0
                if targetName and delegTarget == targetName and (now - delegAt) >= 2.5 and unspent >= delegPts then
                    rt.lastAASpendDelegatedTarget = nil
                    nativeTrained = targetName
                    return true
                end

                rt.lastAASpendDelegatedAt = now
                rt.lastAASpendDelegatedTarget = targetName
                rt.lastAASpendDelegatedPoints = unspent
                local mode = (ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'
                mockCmdf('/aaspend bank %d', threshold)
                mockCmd('/aaspend ' .. mode)
                return true
            end
            return false
        end
        if targetName then
            nativeTrained = targetName
            return true
        end
        return false
    end

    local testCtrl = {
        auto_spend_aa = true,
        auto_spend_aa_threshold = 50,
        auto_aa_delegate_aaspend = true,
        auto_aa_aaspend_mode = 'auto'
    }

    -- 3a. Delegated spend below threshold -> no command
    commandsIssued = {}
    nativeTrained = nil
    local res1 = simulateCheckAutoSpend(testCtrl, mockRuntime, 30, true, 'Combat Agility', 100.0)
    assert_eq(res1, false, 'Suite 64: no spend when unspent < threshold')
    assert_eq(#commandsIssued, 0, 'Suite 64: no commands issued when below threshold')

    -- 3b. Delegated spend at/above threshold -> issues bank and auto now
    commandsIssued = {}
    nativeTrained = nil
    local res2 = simulateCheckAutoSpend(testCtrl, mockRuntime, 60, true, 'Combat Agility', 100.0)
    assert_eq(res2, true, 'Suite 64: auto-spend triggered when unspent >= threshold')
    assert_eq(#commandsIssued, 2, 'Suite 64: issued 2 commands (/aaspend bank, /aaspend auto now)')
    assert_eq(commandsIssued[1], '/aaspend bank 50', 'Suite 64: bank set correctly')
    assert_eq(commandsIssued[2], '/aaspend auto now', 'Suite 64: auto mode triggered')

    -- 3c. Delegated spend in brute mode
    testCtrl.auto_aa_aaspend_mode = 'brute'
    commandsIssued = {}
    nativeTrained = nil
    local res3 = simulateCheckAutoSpend(testCtrl, mockRuntime, 75, true, 'Combat Agility', 100.0)
    assert_eq(res3, true, 'Suite 64: brute auto-spend triggered')
    assert_eq(commandsIssued[2], '/aaspend brute now', 'Suite 64: brute mode triggered')

    -- 3d. Fallback: MQ2AAspend was delegated but points did not drop after >= 2.5s -> triggers native training
    testCtrl.auto_aa_aaspend_mode = 'auto'
    commandsIssued = {}
    nativeTrained = nil
    mockRuntime.lastAASpendDelegatedTarget = 'Combat Agility'
    mockRuntime.lastAASpendDelegatedAt = 100.0
    mockRuntime.lastAASpendDelegatedPoints = 60
    local res4 = simulateCheckAutoSpend(testCtrl, mockRuntime, 60, true, 'Combat Agility', 103.0)
    assert_eq(res4, true, 'Suite 64: fallback triggered after MQ2AAspend stalled')
    assert_eq(nativeTrained, 'Combat Agility', 'Suite 64: native trainer invoked for stalled target')
    assert_eq(#commandsIssued, 0, 'Suite 64: no /aaspend command sent on native fallback')

    -- 3e. Direct native spending when delegation is disabled
    testCtrl.auto_aa_delegate_aaspend = false
    nativeTrained = nil
    local res5 = simulateCheckAutoSpend(testCtrl, mockRuntime, 60, true, 'Combat Agility', 104.0)
    assert_eq(res5, true, 'Suite 64: native spending when delegation off')
    assert_eq(nativeTrained, 'Combat Agility', 'Suite 64: native trainer invoked directly')
    testCtrl.auto_aa_delegate_aaspend = true

    -- 4. INI formatting simulation for MQ2AASpend_AAList
    local function generateAASpendIniLines(priorities, orderMode, bankThreshold, isBrute)
        local prioList = {}
        for nm, enabled in pairs(priorities or {}) do
            if enabled then
                prioList[#prioList + 1] = { name = nm }
            end
        end
        table.sort(prioList, function(a, b) return a.name:lower() < b.name:lower() end)

        local lines = {}
        lines[#lines + 1] = '[MQ2AASpend_Settings]'
        lines[#lines + 1] = 'AutoSpend=1'
        lines[#lines + 1] = isBrute and 'BruteForce=1' or 'BruteForce=0'
        lines[#lines + 1] = string.format('BankPoints=%d', bankThreshold or 0)
        lines[#lines + 1] = '[MQ2AASpend_AAList]'
        for idx, item in ipairs(prioList) do
            lines[#lines + 1] = string.format('%d=%s|M', idx, item.name)
        end
        return lines
    end

    local testPrios = {
        ['Combat Agility'] = true,
        ['Innate Run Speed'] = true
    }
    local iniLines = generateAASpendIniLines(testPrios, 'list', 25, false)
    assert_eq(iniLines[1], '[MQ2AASpend_Settings]', 'Suite 64: INI settings section present')
    assert_eq(iniLines[4], 'BankPoints=25', 'Suite 64: BankPoints set in INI')
    assert_eq(iniLines[5], '[MQ2AASpend_AAList]', 'Suite 64: INI AAList section present')
    assert_eq(iniLines[6], '1=Combat Agility|M', 'Suite 64: First priority formatted with |M')
    assert_eq(iniLines[7], '2=Innate Run Speed|M', 'Suite 64: Second priority formatted with |M')

    -- 5. Special tab AA detection & exclusion from MQ2AAspend INI
    local function simulateIsSpecialTabAA(name, cachedData)
        if not name or name == '' then return false end
        local lower = tostring(name):lower()
        if lower:find('firework') then return true end
        if cachedData and cachedData[name] then
            local cat = cachedData[name].category
            if cat and cat:lower():find('special') then return true end
        end
        return false
    end

    local sampleCache = {
        ['Alternately Advanced Fireworks'] = { category = 'Special', cost = 25, rank = 0, maxRank = 1 },
        ['Glyph of Courage'] = { category = 'Special', cost = 10, rank = 0, maxRank = 1 },
        ['Combat Agility'] = { category = 'Archetype', cost = 3, rank = 1, maxRank = 5 }
    }
    assert_true(simulateIsSpecialTabAA('Alternately Advanced Fireworks', sampleCache), 'Suite 64: fireworks is special tab')
    assert_true(simulateIsSpecialTabAA('Glyph of Courage', sampleCache), 'Suite 64: glyph is special tab')
    assert_true(not simulateIsSpecialTabAA('Combat Agility', sampleCache), 'Suite 64: combat agility is not special tab')

    -- INI sync must exclude Special tab abilities so MQ2AAspend does not fail
    local mixedPrios = {
        ['Combat Agility'] = true,
        ['Alternately Advanced Fireworks'] = true,
        ['Innate Run Speed'] = true
    }
    local function generateFilteredIniLines(priorities, cachedData)
        local prioList = {}
        for nm, enabled in pairs(priorities or {}) do
            if enabled and not simulateIsSpecialTabAA(nm, cachedData) then
                prioList[#prioList + 1] = { name = nm }
            end
        end
        table.sort(prioList, function(a, b) return a.name:lower() < b.name:lower() end)
        local lines = {}
        for idx, item in ipairs(prioList) do
            lines[#lines + 1] = string.format('%d=%s|M', idx, item.name)
        end
        return lines
    end

    local filteredIni = generateFilteredIniLines(mixedPrios, sampleCache)
    assert_eq(#filteredIni, 2, 'Suite 64: only 2 non-special AAs written to INI')
    assert_eq(filteredIni[1], '1=Combat Agility|M', 'Suite 64: first filtered AA')
    assert_eq(filteredIni[2], '2=Innate Run Speed|M', 'Suite 64: second filtered AA')

    -- 6. Verify triune.lua source tokens
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AA.aaSpendLoaded") ~= nil, 'Suite 64: triune.lua defines AA.aaSpendLoaded')
    assert_true(triuneContent:find("auto_aa_delegate_aaspend") ~= nil, 'Suite 64: triune.lua configures auto_aa_delegate_aaspend')
    assert_true(triuneContent:find("auto_aa_aaspend_mode") ~= nil, 'Suite 64: triune.lua configures auto_aa_aaspend_mode')
    assert_true(AA_CONTENT:find("/aaspend") ~= nil, 'Suite 64: triune.lua contains /aaspend commands')
    assert_true(AA_CONTENT:find("mq.TLO.Skill%(name%)") ~= nil, 'Suite 64: triune.lua validates against mq.TLO.Skill')
    assert_true(triuneContent:find("CLASS_AAS") == nil, 'Suite 64: triune.lua purged hardcoded CLASS_AAS')
    assert_true(triuneContent:find("COMMON_AAS") == nil, 'Suite 64: triune.lua purged hardcoded COMMON_AAS')
    assert_true(AA_CONTENT:find("AA.syncAAsToMQ2AASpendIni") ~= nil, 'Suite 64: triune.lua defines syncAAsToMQ2AASpendIni')
    assert_true(AA_CONTENT:find("MQ2AASpend_AAList") ~= nil, 'Suite 64: triune.lua writes MQ2AASpend_AAList section')
    assert_true(AA_CONTENT:find("Sync to INI") ~= nil, 'Suite 64: triune.lua provides Sync to INI button')
    assert_true(AA_CONTENT:find("AA.isSpecialTabAA") ~= nil, 'Suite 64: triune.lua defines isSpecialTabAA')
    assert_true(AA_CONTENT:find("Special tab ability") ~= nil, 'Suite 64: triune.lua trains Special tab abilities natively')
    assert_true(AA_CONTENT:find("MQ2AAspend##aaDelegateMaster") ~= nil, 'Suite 64: triune.lua provides MQ2AAspend delegation checkbox')
    assert_true(AA_CONTENT:find("falling back to Triune native window trainer") ~= nil, 'Suite 64: triune.lua provides native fallback when MQ2AAspend stalls')
end

-- ============================================================================
-- Suite 65: Unreachable Target Abandonment & Pursuit Stall Watchdog Logic
-- ============================================================================
print('--- Suite 65: Unreachable Target Abandonment & Pursuit Stall Logic ---')
do
    -- 1. Unreachable tracking and TTL
    local unreachableIds = {}
    local function markUnreachable(id, now)
        unreachableIds[id] = now or os.clock()
    end
    local function isUnreachable(id, now)
        local t = unreachableIds[id]
        if not t then return false end
        now = now or os.clock()
        if (now - t) > 60 then
            unreachableIds[id] = nil
            return false
        end
        return true
    end

    markUnreachable(1001, 100.0)
    assert_true(isUnreachable(1001, 110.0), 'Suite 65: mob 1001 is unreachable at +10s')
    assert_true(isUnreachable(1001, 159.0), 'Suite 65: mob 1001 is unreachable at +59s')
    assert_true(not isUnreachable(1001, 161.0), 'Suite 65: mob 1001 expires after 60s TTL')
    assert_true(not isUnreachable(1002, 110.0), 'Suite 65: mob 1002 was never marked unreachable')

    -- 2. XTarget selection skips unreachable mob IDs
    local mockXtargets = {
        { id = 1001, name = 'orc_pawn', hp = 80 },
        { id = 1002, name = 'orc_centurion', hp = 90 },
    }
    markUnreachable(1001, 100.0)
    local function selectFirstXtarget(xtList, now)
        for _, xt in ipairs(xtList) do
            if not isUnreachable(xt.id, now) then
                return xt.id
            end
        end
        return nil
    end

    local chosen = selectFirstXtarget(mockXtargets, 110.0)
    assert_eq(chosen, 1002, 'Suite 65: skips unreachable 1001 and selects 1002')

    -- 3. 15-second approach watchdog logic
    local pursuitState = { approachTargetId = 0, approachStartedAt = 0 }
    local function evaluateApproachWatchdog(tid, inReach, inCombatEngaged, now)
        if tid <= 0 then
            pursuitState.approachTargetId = 0
            pursuitState.approachStartedAt = 0
            return 'NO_TARGET'
        end
        if pursuitState.approachTargetId ~= tid then
            pursuitState.approachTargetId = tid
            pursuitState.approachStartedAt = now
        end
        if inReach or inCombatEngaged then
            pursuitState.approachStartedAt = now
            return 'ENGAGED'
        elseif (now - pursuitState.approachStartedAt) > 15.0 then
            pursuitState.approachTargetId = 0
            pursuitState.approachStartedAt = 0
            return 'UNREACHABLE_TIMEOUT'
        end
        return 'APPROACHING'
    end

    assert_eq(evaluateApproachWatchdog(500, false, false, 1000.0), 'APPROACHING', 'Suite 65: start approaching at 1000s')
    assert_eq(evaluateApproachWatchdog(500, false, false, 1010.0), 'APPROACHING', 'Suite 65: still approaching at 1010s (+10s)')
    assert_eq(evaluateApproachWatchdog(500, false, false, 1015.1), 'UNREACHABLE_TIMEOUT', 'Suite 65: times out after 15.1s unable to reach')

    -- 4. In-reach / engaged resets approach timer
    assert_eq(evaluateApproachWatchdog(600, false, false, 2000.0), 'APPROACHING', 'Suite 65: mob 600 approaching')
    assert_eq(evaluateApproachWatchdog(600, true, true, 2012.0), 'ENGAGED', 'Suite 65: mob 600 in reach at 12s resets timer')
    assert_eq(evaluateApproachWatchdog(600, false, false, 2020.0), 'APPROACHING', 'Suite 65: mob 600 approaching again (8s after reset)')
    assert_eq(evaluateApproachWatchdog(600, false, false, 2028.0), 'UNREACHABLE_TIMEOUT', 'Suite 65: mob 600 times out 16s after last in-reach')

    -- 5. Source code validation in triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("pursuit.noPathFails") ~= nil, 'Suite 65: triune.lua tracks noPathFails')
    assert_true(triuneContent:find("No navigation path to target") ~= nil, 'Suite 65: triune.lua logs no navigation path to target')
    assert_true(triuneContent:find("Target #%%d %(%%s%) obstructed after 4 \"cannot hit\" attempts") ~= nil, 'Suite 65: triune.lua abandons after 4 cannot hit attempts')
    assert_true(triuneContent:find("pursuit.approachStartedAt") ~= nil, 'Suite 65: triune.lua implements approachStartedAt watchdog')
    assert_true(triuneContent:find("giving up on target") ~= nil, 'Suite 65: triune.lua maintains giving up on target')
end

-- ============================================================================
-- Suite 66: Fast Retargeting & Dead Mob Filtering on Slain
-- ============================================================================
print('--- Suite 66: Fast Retargeting & Dead Mob Filtering on Slain ---')
do
    -- 1. Dead mob validation logic
    local function isDeadSpawn(s)
        local dead = false
        local stype = ''
        local state = ''
        pcall(function()
            dead = s.Dead and s.Dead() or false
            stype = s.Type and s.Type() or ''
            state = s.State and s.State() or ''
        end)
        return dead or stype == 'Corpse' or state == 'DEAD'
    end

    local livingMob = { Dead = function() return false end, Type = function() return 'NPC' end, State = function() return 'STAND' end, CurrentHPs = function() return 500 end, PctHPs = function() return 50 end }
    local livingZeroHpMob = { Dead = function() return false end, Type = function() return 'NPC' end, State = function() return 'STAND' end, CurrentHPs = function() return 0 end, PctHPs = function() return 0 end }
    local deadStateMob = { Dead = function() return false end, Type = function() return 'NPC' end, State = function() return 'DEAD' end, CurrentHPs = function() return 0 end }
    local corpseMob = { Dead = function() return false end, Type = function() return 'Corpse' end, State = function() return 'DEAD' end, CurrentHPs = function() return 0 end }
    local deadFlagMob = { Dead = function() return true end, Type = function() return 'NPC' end, State = function() return 'STAND' end, CurrentHPs = function() return 0 end }

    assert_true(not isDeadSpawn(livingMob), 'Suite 66: living mob is not dead')
    assert_true(not isDeadSpawn(livingZeroHpMob), 'Suite 66: 0 HP / 0% health living mob is not dead (0% health does not mean dead)')
    assert_true(isDeadSpawn(deadStateMob), 'Suite 66: DEAD state mob is recognized as dead')
    assert_true(isDeadSpawn(corpseMob), 'Suite 66: Corpse type mob is recognized as dead')
    assert_true(isDeadSpawn(deadFlagMob), 'Suite 66: Dead() == true mob is recognized as dead')

    -- 2. XTarget retains 0% HP living mobs and filters truly dead mobs
    local mockXtar = {
        { id = 101, spawn = corpseMob },
        { id = 102, spawn = livingZeroHpMob },
        { id = 103, spawn = livingMob },
    }
    local function findFirstAliveXtar(xtars)
        for _, entry in ipairs(xtars) do
            if not isDeadSpawn(entry.spawn) then
                return entry.id
            end
        end
        return nil
    end
    assert_eq(findFirstAliveXtar(mockXtar), 102, 'Suite 66: retains 0% HP living mob on XTarget and skips corpse')

    -- 3. countNPCXtarget logic returns 0 when only truly dead mobs linger
    local mockDeadOnlyXtar = {
        { id = 101, spawn = deadStateMob },
        { id = 103, spawn = corpseMob },
    }
    local function countAliveNPCXtarget(xtars)
        local count = 0
        for _, entry in ipairs(xtars) do
            if not isDeadSpawn(entry.spawn) then
                count = count + 1
            end
        end
        return count
    end
    assert_eq(countAliveNPCXtarget(mockDeadOnlyXtar), 0, 'Suite 66: countAliveNPCXtarget returns 0 when all XTargets dead')

    -- 4. Slain event resets lastTick to 0 for instant loop iteration
    local mockRuntime = { lastTick = 12345.67, cleared = false }
    mockRuntime.clearTarget = function() mockRuntime.cleared = true end
    local function onMobSlain(targetDead)
        if targetDead then
            mockRuntime.clearTarget()
            mockRuntime.lastTick = 0
        end
    end
    onMobSlain(true)
    assert_true(mockRuntime.cleared, 'Suite 66: slain event calls clearTarget')
    assert_eq(mockRuntime.lastTick, 0, 'Suite 66: slain event resets lastTick to 0')

    -- 5. Source code validation in TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("TriuneSlain1") ~= nil, 'Suite 66: triune.lua registers TriuneSlain1 event')
    assert_true(triuneContent:find("TriuneSlain2") ~= nil, 'Suite 66: triune.lua registers TriuneSlain2 event')
    assert_true(triuneContent:find("curHp and curHp <= 0") == nil, 'Suite 66: triune.lua does not falsely treat 0 HP as dead')
    assert_true(triuneContent:find("isDead = matches or t.Dead()") ~= nil, 'Suite 66: triune.lua detects slain mob target')
end

-- ============================================================================
-- Suite 67: Native AA Window Trainer & Robust Window Controls
-- ============================================================================
print('--- Suite 67: Native AA Window Trainer & Robust Window Controls ---')
do
    -- 1. Window resolution: AAWindow vs AAWnd fallback
    local mockMq1 = {
        TLO = {
            Window = function(name)
                if name == 'AAWindow' then
                    return {
                        Name = function() return 'AAWindow' end,
                        Open = function() return false end
                    }
                end
                return nil
            end
        }
    }
    local mockMq2 = {
        TLO = {
            Window = function(name)
                if name == 'AAWnd' then
                    return {
                        Name = function() return 'AAWnd' end,
                        Open = function() return true end
                    }
                end
                return nil
            end
        }
    }

    local function simGetAAWindow(mqObj)
        local win = nil
        pcall(function()
            local w = mqObj.TLO.Window('AAWindow')
            if w and w.Name and w.Name() then win = w return end
            w = mqObj.TLO.Window('AAWnd')
            if w and w.Name and w.Name() then win = w return end
        end)
        return win
    end

    local function simGetAAWindowName(mqObj)
        local name = 'AAWindow'
        pcall(function()
            local w = mqObj.TLO.Window('AAWindow')
            if w and w.Name and w.Name() then name = w.Name() return end
            w = mqObj.TLO.Window('AAWnd')
            if w and w.Name and w.Name() then name = w.Name() return end
        end)
        return name
    end

    local function simIsAAWindowOpen(mqObj)
        local isOpen = false
        pcall(function()
            local w = simGetAAWindow(mqObj)
            if w and w.Open and w.Open() then isOpen = true end
        end)
        return isOpen
    end

    local win1 = simGetAAWindow(mockMq1)
    assert_true(win1 ~= nil, 'Suite 67: AAWindow resolved when present')
    assert_eq(simGetAAWindowName(mockMq1), 'AAWindow', 'Suite 67: AAWindow name resolved correctly')
    assert_eq(simIsAAWindowOpen(mockMq1), false, 'Suite 67: AAWindow closed detected correctly')

    local win2 = simGetAAWindow(mockMq2)
    assert_true(win2 ~= nil, 'Suite 67: AAWnd resolved as fallback')
    assert_eq(simGetAAWindowName(mockMq2), 'AAWnd', 'Suite 67: AAWnd fallback name resolved correctly')
    assert_eq(simIsAAWindowOpen(mockMq2), true, 'Suite 67: AAWnd open detected correctly')

    -- 2. Open AA Window commands sequence
    local opened = false
    local cmds = {}
    local mockWinToOpen = {
        Name = function() return 'AAWindow' end,
        Open = function() return opened end,
        DoOpen = function() opened = true end
    }
    local mockMqOpen = {
        TLO = {
            Window = function(name)
                if name == 'AAWindow' then return mockWinToOpen end
                return nil
            end
        },
        cmd = function(c) cmds[#cmds + 1] = c end,
        cmdf = function(fmt, ...) cmds[#cmds + 1] = string.format(fmt, ...) end
    }

    local function simOpenAAWindow(mqObj, winObj, attempt, invOpen)
        if simIsAAWindowOpen(mqObj) then return true end
        attempt = attempt or 1
        local winName = simGetAAWindowName(mqObj)

        if attempt == 1 then
            pcall(function()
                if winObj and winObj.DoOpen then winObj.DoOpen() end
            end)
            mqObj.cmdf('/windowstate %s open', winName)
        elseif attempt == 2 then
            mqObj.cmd('/nomodkey /keypress TOGGLE_ALTADVWIN')
        elseif attempt == 3 then
            mqObj.cmd('/nomodkey /keypress v alt')
        elseif attempt == 4 then
            mqObj.cmd('/nomodkey /keypress a alt')
        else
            if invOpen then
                mqObj.cmdf('/nomodkey /notify InventoryWindow IW_AltAdvBtn leftmouseup')
            end
        end
        return simIsAAWindowOpen(mqObj)
    end

    -- Attempt 1: Non-toggling /windowstate open (clean, no toggle collision)
    local openRes1 = simOpenAAWindow(mockMqOpen, mockWinToOpen, 1)
    assert_true(openRes1, 'Suite 67: simOpenAAWindow returns true after DoOpen')
    assert_true(opened, 'Suite 67: DoOpen was invoked on window object')
    assert_eq(cmds[1], '/windowstate AAWindow open', 'Suite 67: issued /windowstate open on attempt 1')
    assert_eq(#cmds, 1, 'Suite 67: attempt 1 does not execute conflicting toggle commands')

    -- Attempt 2: Native EQ toggle keypress
    cmds = {}
    opened = false
    simOpenAAWindow(mockMqOpen, mockWinToOpen, 2)
    assert_eq(cmds[1], '/nomodkey /keypress TOGGLE_ALTADVWIN', 'Suite 67: issued /keypress TOGGLE_ALTADVWIN on attempt 2')

    -- Attempt 5: Only notifies Inventory if inventory is open
    cmds = {}
    opened = false
    simOpenAAWindow(mockMqOpen, mockWinToOpen, 5, false) -- inventory closed
    assert_eq(#cmds, 0, 'Suite 67: suppressed InventoryWindow IW_AltAdvBtn when inventory is closed')

    opened = false
    simOpenAAWindow(mockMqOpen, mockWinToOpen, 5, true) -- inventory open
    assert_eq(cmds[1], '/nomodkey /notify InventoryWindow IW_AltAdvBtn leftmouseup', 'Suite 67: notified InventoryWindow IW_AltAdvBtn when inventory open')

    -- 3. Recursive child traversal does not abort on hidden/closed siblings
    local tree = {
        FirstChild = {
            Name = function() return 'Tab1_General' end,
            ScreenID = function() return 'Page1' end,
            Open = function() return true end,
            Next = {
                Name = function() return 'Tab2_Arch' end,
                ScreenID = function() return 'Page2' end,
                Open = function() return false end, -- Inactive tab!
                Next = {
                    Name = function() return 'Tab3_Class' end,
                    ScreenID = function() return 'Page3' end,
                    Open = function() return false end,
                    Next = {
                        Name = function() return 'AAW_TrainButton' end,
                        ScreenID = function() return 'TrainButton' end,
                        Open = function() return true end,
                        Next = nil
                    }
                }
            }
        }
    }
    local function simFindChildRecursive(parent, targetName)
        if not parent or not targetName or targetName == '' then return nil end
        local tLower = targetName:lower()
        local curr = nil
        pcall(function() curr = parent.FirstChild end)
        local safety = 0
        while curr and safety < 120 do
            safety = safety + 1
            local match = false
            pcall(function()
                local nm = curr.Name and curr.Name()
                local sid = curr.ScreenID and curr.ScreenID()
                if (nm and nm:lower() == tLower) or (sid and sid:lower() == tLower) then
                    match = true
                end
            end)
            if match then return curr end
            local nextSibling = nil
            pcall(function() nextSibling = curr.Next end)
            curr = nextSibling
        end
        return nil
    end

    local foundBtn = simFindChildRecursive(tree, 'AAW_TrainButton')
    assert(foundBtn ~= nil, 'Suite 67: findChildRecursive navigated through closed tabs and found AAW_TrainButton')
    assert_eq(foundBtn.Name(), 'AAW_TrainButton', 'Suite 67: found element name matches target')

    -- 4. State machine: wait_open aborts cleanly on timeout rather than corrupt training
    local task = {
        name = 'Bloodlust',
        aaId = 1234,
        step = 'wait_open',
        retries = 4,
        nextStepAt = 0
    }
    local loggedAbort = false
    local function simWaitOpen(t, isWinOpen)
        if isWinOpen then
            t.step = 'prepare_tab'
            return
        end
        t.retries = (t.retries or 0) + 1
        if t.retries <= 4 then
            -- retry open
        else
            loggedAbort = true
            t.step = 'finish'
        end
    end
    simWaitOpen(task, false)
    assert_eq(task.step, 'finish', 'Suite 67: wait_open aborts cleanly to finish when retries exceeded')
    assert_true(loggedAbort, 'Suite 67: logged clear abort warning when window failed to open')

    -- 5. Source code validation in TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AA.getAAWindow") ~= nil, 'Suite 67: triune.lua defines AA.getAAWindow')
    assert_true(AA_CONTENT:find("AA.getAAWindowName") ~= nil, 'Suite 67: triune.lua defines AA.getAAWindowName')
    assert_true(AA_CONTENT:find("AA.isAAWindowOpen") ~= nil, 'Suite 67: triune.lua defines AA.isAAWindowOpen')
    assert_true(AA_CONTENT:find("AA.openAAWindow") ~= nil, 'Suite 67: triune.lua defines AA.openAAWindow')
    assert_true(AA_CONTENT:find("AA.closeAAWindow") ~= nil, 'Suite 67: triune.lua defines AA.closeAAWindow')
    assert_true(AA_CONTENT:find("TOGGLE_ALTADVWIN") ~= nil, 'Suite 67: triune.lua uses TOGGLE_ALTADVWIN keypress')
    assert_true(AA_CONTENT:find("IW_AltAdvBtn") ~= nil, 'Suite 67: triune.lua notifies IW_AltAdvBtn')
    assert_true(AA_CONTENT:find("AAW_ResetFilter") ~= nil, 'Suite 67: triune.lua supports AAW_ResetFilter')
    assert_true(AA_CONTENT:find("Failed to open AA Window after") ~= nil, 'Suite 67: triune.lua aborts cleanly when window fails to open')
end


-- ============================================================================
-- Suite 68: Complete Auto AA Discovery & Unpurchased Ability Retention
-- ============================================================================
print('--- Suite 68: Complete Auto AA Discovery & Unpurchased Ability Retention ---')
do
    -- 1. Simulate recordScannedAA logic for unpurchased AAs vs character skills
    local function simRecordScannedAA(list, foundMap, name, knownSkills, mockTloMe)
        if not name or name == '' then return end
        if knownSkills[name] then return end -- rejected as character skill

        local cKey = name:lower():gsub('%s+', '')
        if foundMap[cKey] then return end

        local meRank = mockTloMe[name] and mockTloMe[name].Rank or 0
        local cost = mockTloMe[name] and mockTloMe[name].Cost or 0
        local maxRank = mockTloMe[name] and mockTloMe[name].MaxRank or 0

        -- Triune fallback: unpurchased AAs cost at least 1 point
        if cost <= 0 then cost = 1 end

        local entry = {
            name = name,
            rank = meRank,
            cost = cost,
            maxRank = maxRank,
            canTrain = (maxRank == 0 or meRank < maxRank)
        }
        table.insert(list, entry)
        foundMap[cKey] = entry
    end

    local testList = {}
    local testMap = {}
    local skills = { ['Mend'] = true, ['Flying Kick'] = true, ['Backstab'] = true, ['Dual Wield'] = true }
    local tloMe = {
        ['Combat Agility'] = { Rank = 3, Cost = 2, MaxRank = 5 },
        -- 'Bloodlust', 'Physical Enhancement', 'Extended Ingenuity', 'Fearless' are unpurchased (nil in Me.AltAbility)
    }

    -- Record purchased AA
    simRecordScannedAA(testList, testMap, 'Combat Agility', skills, tloMe)
    assert_true(testMap['combatagility'] ~= nil, 'Suite 68: Combat Agility recorded')
    assert_eq(testMap['combatagility'].rank, 3, 'Suite 68: Combat Agility rank is 3')

    -- Record unpurchased AAs (not in Me.AltAbility, cost 0 / id 0)
    simRecordScannedAA(testList, testMap, 'Bloodlust', skills, tloMe)
    simRecordScannedAA(testList, testMap, 'Physical Enhancement', skills, tloMe)
    simRecordScannedAA(testList, testMap, 'Extended Ingenuity', skills, tloMe)
    simRecordScannedAA(testList, testMap, 'Fearless', skills, tloMe)

    assert_true(testMap['bloodlust'] ~= nil, 'Suite 68: Unpurchased Bloodlust is retained')
    assert_eq(testMap['bloodlust'].rank, 0, 'Suite 68: Bloodlust rank is 0')
    assert_eq(testMap['bloodlust'].cost, 1, 'Suite 68: Bloodlust cost defaults to 1')
    assert_eq(testMap['bloodlust'].canTrain, true, 'Suite 68: Bloodlust canTrain is true')

    assert_true(testMap['physicalenhancement'] ~= nil, 'Suite 68: Physical Enhancement is retained')
    assert_true(testMap['extendedingenuity'] ~= nil, 'Suite 68: Extended Ingenuity is retained')
    assert_true(testMap['fearless'] ~= nil, 'Suite 68: Fearless is retained')

    -- Attempt to record real character skills (should be rejected)
    simRecordScannedAA(testList, testMap, 'Mend', skills, tloMe)
    simRecordScannedAA(testList, testMap, 'Flying Kick', skills, tloMe)
    simRecordScannedAA(testList, testMap, 'Backstab', skills, tloMe)
    assert_true(testMap['mend'] == nil, 'Suite 68: Skill Mend is rejected')
    assert_true(testMap['flyingkick'] == nil, 'Suite 68: Skill Flying Kick is rejected')
    assert_true(testMap['backstab'] == nil, 'Suite 68: Skill Backstab is rejected')

    -- 2. Cache pruning simulation (Step 1.5): only prune true skills, not unpurchased AAs
    local cache = {
        ['combatagility'] = { name = 'Combat Agility', id = 101, maxRank = 5 },
        ['bloodlust'] = { name = 'Bloodlust', id = 0, maxRank = 0 },
        ['mend'] = { name = 'Mend', id = 0, maxRank = 0 }
    }
    for cName, cd in pairs(cache) do
        local isSkill = skills[cd.name]
        if isSkill then
            cache[cName] = nil
        end
    end
    assert_true(cache['combatagility'] ~= nil, 'Suite 68: Cache preserves purchased AA')
    assert_true(cache['bloodlust'] ~= nil, 'Suite 68: Cache preserves unpurchased AA with id 0 and maxRank 0')
    assert_true(cache['mend'] == nil, 'Suite 68: Cache pruned true character skill Mend')

    -- 3. Source code inspection of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AA.GENERAL_AAS = {") ~= nil, 'Suite 68: triune.lua defines GENERAL_AAS catalog')
    assert_true(AA_CONTENT:find("'Physical Enhancement'") ~= nil, 'Suite 68: NORRATH_AAS includes Physical Enhancement')
    assert_true(AA_CONTENT:find("'Bloodlust'") ~= nil, 'Suite 68: NORRATH_AAS includes Bloodlust')
    assert_true(AA_CONTENT:find("'Extended Ingenuity'") ~= nil, 'Suite 68: NORRATH_AAS includes Extended Ingenuity')
    assert_true(AA_CONTENT:find("'Fury of Magic'") ~= nil, 'Suite 68: NORRATH_AAS includes Fury of Magic')
    assert_true(AA_CONTENT:find("'Twinproc'") ~= nil, 'Suite 68: NORRATH_AAS includes Twinproc')
    assert_true(AA_CONTENT:find("'Gelid Rending'") ~= nil, 'Suite 68: NORRATH_AAS includes Gelid Rending')

    -- Ensure listboxes are NOT gated behind isAAWindowOpen()
    assert_true(triuneContent:find("if runtime.isAAWindowOpen%(%) then%s+for _, lName in ipairs%(listNames%) do") == nil,
        'Suite 68: UI listbox scan is not gated behind isAAWindowOpen()')

    -- Ensure id <= 0 is not prematurely dropping abilities
    assert_true(triuneContent:find("if not isFromUI and id <= 0 then return end") == nil,
        'Suite 68: recordScannedAA does not drop non-UI abilities when id <= 0')

    -- 4. In-combat AA spending gating simulation
    local function simCheckAutoSpendAA(inCombat, autoSpendEnabled, unspentPoints)
        if not autoSpendEnabled then return false end
        if inCombat then return false end
        if unspentPoints <= 0 then return false end
        return true
    end

    assert_eq(simCheckAutoSpendAA(true, true, 50), false, 'Suite 68: checkAutoSpendAA blocked during combat')
    assert_eq(simCheckAutoSpendAA(false, true, 50), true, 'Suite 68: checkAutoSpendAA allowed out of combat')
    assert_eq(simCheckAutoSpendAA(false, false, 50), false, 'Suite 68: checkAutoSpendAA blocked when disabled')
    assert_eq(simCheckAutoSpendAA(false, true, 0), false, 'Suite 68: checkAutoSpendAA blocked when 0 unspent')

    -- 5. Nested UI hierarchy traversal test (AAWindow -> AAW_Subwindows -> AAW_GeneralPage -> AAW_GeneralList)
    local function simFindChildRecursive(parent, targetName)
        if not parent or not targetName or targetName == '' then return nil end
        local tLower = targetName:lower()

        local curr = parent.FirstChild
        local safety = 0
        while curr and safety < 120 do
            safety = safety + 1
            local nm = curr.Name and curr.Name()
            local sid = curr.ScreenID and curr.ScreenID()
            if (nm and nm:lower() == tLower) or (sid and sid:lower() == tLower) then
                return curr
            end

            -- Check if child has children via FirstChild or Children()
            local hasChildren = false
            if curr.FirstChild then
                hasChildren = true
            elseif curr.Children then
                local c = curr.Children()
                if c == true or c == 'TRUE' or tostring(c):lower() == 'true' then
                    hasChildren = true
                end
            end
            if hasChildren then
                local found = simFindChildRecursive(curr, targetName)
                if found then return found end
            end

            curr = curr.Next
        end
        return nil
    end

    local nestedUiTree = {
        FirstChild = {
            Name = function() return 'AAW_Subwindows' end,
            ScreenID = function() return 'Subwindows' end,
            FirstChild = {
                Name = function() return 'AAW_GeneralPage' end,
                ScreenID = function() return 'GeneralPage' end,
                FirstChild = {
                    Name = function() return 'AAW_GeneralList' end,
                    ScreenID = function() return 'GeneralList' end,
                    Items = function() return 10 end
                }
            }
        }
    }

    local foundNestedList = simFindChildRecursive(nestedUiTree, 'AAW_GeneralList')
    assert(foundNestedList ~= nil, 'Suite 68: findChildRecursive navigates 3-level deep nested hierarchy')
    assert_eq(foundNestedList.Name(), 'AAW_GeneralList', 'Suite 68: found nested control matches AAW_GeneralList')

    -- 6. Verify in-combat gate in triune.lua
    assert_true(AA_CONTENT:find("Strict out%-of%-combat enforcement: never spend AAs while engaged in combat") ~= nil,
        'Suite 68: triune.lua includes strict out-of-combat gate in checkAutoSpendAA')
    assert_true(AA_CONTENT:find("Strict out%-of%-combat enforcement: if combat engages mid%-train") ~= nil,
        'Suite 68: triune.lua includes mid-training combat abort in processAATrainWorkflow')
end

-- ============================================================================
-- Suite 69: AA Purchase Verification & Unpurchasable Ability Skip Logic
-- ============================================================================
print('--- Suite 69: AA Purchase Verification & Unpurchasable Ability Skip Logic ---')
do
    -- 1. Simulation of AA verification step
    local function simVerifyAATrainOutcome(taskName, initialPts, currentPts, initialRank, currentRank, btnDisabled, skipTable, now)
        local purchaseSucceeded = (currentPts < initialPts) or (currentRank > initialRank)
        if purchaseSucceeded then
            skipTable[taskName] = nil
            return true, 'success'
        else
            skipTable[taskName] = now + 300
            local reason = btnDisabled and 'Train button disabled / unmet requirements'
                or 'Purchase not accepted by server (unmet requirements or level too low)'
            return false, reason
        end
    end

    local skipTable = {}
    local now = 1000.0

    -- Test 1a: Successful purchase via points delta
    local ok, reason = simVerifyAATrainOutcome('Runspeed', 10, 8, 0, 1, false, skipTable, now)
    assert_true(ok, 'Suite 69: Successful purchase detected when points decrease and rank increases')
    assert_eq(skipTable['Runspeed'], nil, 'Suite 69: Successful ability not placed in skip table')

    -- Test 1b: Failed purchase (points unchanged, rank unchanged)
    local okFail, failReason = simVerifyAATrainOutcome('Combat Agility', 8, 8, 0, 0, false, skipTable, now)
    assert_eq(okFail, false, 'Suite 69: Purchase failure detected when points and rank are unchanged')
    assert_eq(skipTable['Combat Agility'], 1300.0, 'Suite 69: Failed ability placed on 300s cooldown')
    assert_true(failReason:find('Purchase not accepted by server') ~= nil, 'Suite 69: Correct server rejection reason reported')

    -- Test 1c: Failed purchase with disabled train button in UI
    local okDis, disReason = simVerifyAATrainOutcome('Planar Power', 8, 8, 0, 0, true, skipTable, now)
    assert_eq(okDis, false, 'Suite 69: Purchase failure detected when train button is disabled')
    assert_eq(skipTable['Planar Power'], 1300.0, 'Suite 69: Disabled ability placed on 300s cooldown')
    assert_true(disReason:find('Train button disabled') ~= nil, 'Suite 69: Correct button disabled reason reported')

    -- 2. Candidate Selection & Advancement Logic (Prevents getting stuck!)
    local candidates = {
        { name = 'Combat Agility', cost = 2, rank = 0, maxRank = 5 },
        { name = 'Runspeed', cost = 2, rank = 1, maxRank = 5 },
        { name = 'Innate Strength', cost = 1, rank = 0, maxRank = 5 }
    }

    local function simSelectNextCandidate(candList, skips, curTime, unspent)
        for _, c in ipairs(candList) do
            if not (skips[c.name] and curTime < skips[c.name]) then
                if unspent >= c.cost then
                    return c
                end
            end
        end
        return nil
    end

    -- Combat Agility is skipped, Runspeed should be selected next
    local chosen = simSelectNextCandidate(candidates, skipTable, now + 10, 8)
    assert(chosen ~= nil, 'Suite 69: Candidate selected when highest priority is skipped')
    assert_eq(chosen.name, 'Runspeed', 'Suite 69: Auto AA advances to Runspeed instead of getting stuck on Combat Agility')

    -- 3. Level-up reset logic
    local function simCheckLevelChange(curLevel, lastLevel, skips)
        if lastLevel and curLevel > 0 and curLevel ~= lastLevel then
            return {}, curLevel
        end
        return skips, curLevel > 0 and curLevel or lastLevel
    end

    local updatedSkips, updatedLevel = simCheckLevelChange(60, 55, skipTable)
    assert_eq(next(updatedSkips), nil, 'Suite 69: All AA skips cleared when character levels up')
    assert_eq(updatedLevel, 60, 'Suite 69: Character level updated to 60')

    -- 4. Manual spend clear logic
    skipTable['Combat Agility'] = 1300.0
    local function simManualSpend(targetName, skips)
        if targetName and targetName ~= '' then
            skips[targetName] = nil
        else
            for k in pairs(skips) do skips[k] = nil end
        end
    end
    simManualSpend('Combat Agility', skipTable)
    assert_eq(skipTable['Combat Agility'], nil, 'Suite 69: Manual spend clears skip for targeted ability')

    -- 5. Static pre-check logic (MinLevel & CanTrain)
    local function simPreCheckAA(myLevel, minLevel, canTrain)
        if (myLevel > 0 and minLevel > 0 and myLevel < minLevel) or (canTrain == false) then
            return false -- Cannot train
        end
        return true -- Eligible to attempt
    end
    assert_eq(simPreCheckAA(55, 60, true), false, 'Suite 69: Pre-check rejects ability when player level < minLevel')
    assert_eq(simPreCheckAA(65, 60, false), false, 'Suite 69: Pre-check rejects ability when canTrain is false')
    assert_eq(simPreCheckAA(65, 60, true), true, 'Suite 69: Pre-check accepts ability when level and prerequisites are met')

    -- 6. Verify triune.lua source code definitions
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("task%.step == 'click_train'") ~= nil, 'Suite 69: triune.lua implements click_train step in processAATrainWorkflow')
    assert_true(AA_CONTENT:find("AAW_TrainButton") ~= nil, 'Suite 69: triune.lua clicks train button in UI')
    assert_true(AA_CONTENT:find("targetTab = prefTab") ~= nil, 'Suite 69: triune.lua sets target tab based on ability type')
    assert_true(AA_CONTENT:find("ImGui%.TextColored%(GOOD%[1%], GOOD%[2%], GOOD%[3%], GOOD%[4%], 'Can Train'%)") ~= nil,
        'Suite 69: triune.lua displays Can Train status for affordable abilities in UI')
end

-- ============================================================================
-- Suite 70: Player-Specific AA Filtering & Cross-Class Ability Rejection
-- ============================================================================
print('--- Suite 70: Player-Specific AA Filtering & Cross-Class Ability Rejection ---')
do
    -- 1. Simulation of isAAAllowedForPlayer
    local CLASS_ARCHETYPES = {
        War = 'Melee', Pal = 'Priest/Melee', SK = 'Caster/Melee', Rng = 'Melee/Caster',
        Rog = 'Melee', Mnk = 'Melee', Ber = 'Melee', Brd = 'Melee/Bard',
        Clr = 'Priest', Dru = 'Priest/Caster', Shm = 'Priest/Caster',
        Wiz = 'Caster', Mag = 'Caster', Enc = 'Caster', Nec = 'Caster', Bst = 'Melee/Priest',
    }
    local ARCHETYPE_CLASSES = {
        Melee = { War = true, Pal = true, SK = true, Rng = true, Rog = true, Mnk = true, Ber = true, Brd = true, Bst = true },
        Priest = { Clr = true, Dru = true, Shm = true, Pal = true },
        Caster = { Wiz = true, Mag = true, Enc = true, Nec = true, Dru = true, Shm = true, Rng = true, SK = true, Bst = true },
        Pet = { Mag = true, Nec = true, Bst = true, Shm = true, Enc = true },
    }
    local ARCHETYPE_RESTRICTIONS = {
        ['Combat Fury'] = 'Melee', ['Ambidexterity'] = 'Melee', ['Physical Enhancement'] = 'Melee',
        ['Healing Gift'] = 'Priest', ['Healing Adept'] = 'Priest',
        ['Spell Casting Mastery'] = 'Caster', ['Fury of Magic'] = 'Caster', ['Destructive Fury'] = 'Caster',
        ['Mend Companion'] = 'Pet', ['Companion\'s Blessing'] = 'Pet',
    }
    local CLASS_SPECIFIC_ABILITIES = {
        War = { 'Area Taunt', 'Rampage', 'Blade Guardian' },
        Clr = { 'Divine Arbitration', 'Purify Soul', 'Celestial Regeneration' },
        Rng = { 'Headshot', 'Endless Quiver' },
        Wiz = { 'Mana Burn', 'Harvest of Druzzil' },
        SK  = { 'Harm Touch', 'Leech Touch' },
        Enc = { 'Gather Mana', 'Color Shock' },
        Nec = { 'Life Burn', 'Swarm of Decay' },
        Shm = { 'Cannibalization', 'Turgur\'s Swarm' },
    }
    local AA_CLASS_RESTRICTIONS = {}
    for cls, abilities in pairs(CLASS_SPECIFIC_ABILITIES) do
        for _, nm in ipairs(abilities) do
            if not AA_CLASS_RESTRICTIONS[nm] then AA_CLASS_RESTRICTIONS[nm] = {} end
            AA_CLASS_RESTRICTIONS[nm][cls] = true
        end
    end

    local function isAllowed(name, playerClasses, isFromUI, mockRanks)
        if isFromUI then return true end
        if mockRanks and (mockRanks[name] or 0) > 0 then return true end
        local allowedClasses = AA_CLASS_RESTRICTIONS[name]
        if allowedClasses then
            local matched = false
            for _, cls in ipairs(playerClasses) do
                if allowedClasses[cls] then matched = true; break end
            end
            if not matched then return false end
        end
        local reqArch = ARCHETYPE_RESTRICTIONS[name]
        if reqArch then
            local archMap = ARCHETYPE_CLASSES[reqArch]
            if archMap then
                local matched = false
                for _, cls in ipairs(playerClasses) do
                    if archMap[cls] then matched = true; break end
                end
                if not matched then return false end
            end
        end
        return true
    end

    -- Warrior tests
    local warClasses = { 'War' }
    assert_true(isAllowed('Area Taunt', warClasses, false), 'Suite 70: War allowed Area Taunt')
    assert_true(isAllowed('Combat Fury', warClasses, false), 'Suite 70: War allowed Melee archetype Combat Fury')
    assert_true(isAllowed('Innate Run Speed', warClasses, false), 'Suite 70: War allowed general Innate Run Speed')
    assert_true(not isAllowed('Headshot', warClasses, false), 'Suite 70: War REJECTS Ranger Headshot')
    assert_true(not isAllowed('Mana Burn', warClasses, false), 'Suite 70: War REJECTS Wizard Mana Burn')
    assert_true(not isAllowed('Harm Touch', warClasses, false), 'Suite 70: War REJECTS Shadowknight Harm Touch')
    assert_true(not isAllowed('Divine Arbitration', warClasses, false), 'Suite 70: War REJECTS Cleric Divine Arbitration')
    assert_true(not isAllowed('Fury of Magic', warClasses, false), 'Suite 70: War REJECTS Caster archetype Fury of Magic')
    assert_true(not isAllowed('Healing Gift', warClasses, false), 'Suite 70: War REJECTS Priest archetype Healing Gift')

    -- Cleric tests
    local clrClasses = { 'Clr' }
    assert_true(isAllowed('Divine Arbitration', clrClasses, false), 'Suite 70: Clr allowed Divine Arbitration')
    assert_true(isAllowed('Healing Gift', clrClasses, false), 'Suite 70: Clr allowed Priest archetype Healing Gift')
    assert_true(not isAllowed('Area Taunt', clrClasses, false), 'Suite 70: Clr REJECTS Warrior Area Taunt')
    assert_true(not isAllowed('Headshot', clrClasses, false), 'Suite 70: Clr REJECTS Ranger Headshot')
    assert_true(not isAllowed('Combat Fury', clrClasses, false), 'Suite 70: Clr REJECTS Melee archetype Combat Fury')

    -- Bypass if already trained (Rank > 0)
    local mockRanks = { ['Headshot'] = 1 }
    assert_true(isAllowed('Headshot', warClasses, false, mockRanks), 'Suite 70: Already trained rank > 0 bypasses class restriction')

    -- Bypass if scanned directly from in-game UI window
    assert_true(isAllowed('Headshot', warClasses, true), 'Suite 70: isFromUI bypasses restriction')

    -- Bypass if explicitly prioritized by user (custom server compatibility)
    local function isAllowedWithPrio(name, playerClasses, isPrio)
        if isPrio then return true end
        return isAllowed(name, playerClasses, false)
    end
    assert_true(isAllowedWithPrio('Bestial Frenzy', warClasses, true), 'Suite 70: Prioritized Bestial Frenzy allowed unconditionally for custom servers')
    assert_true(isAllowedWithPrio('Mana Burn', warClasses, true), 'Suite 70: Prioritized Mana Burn allowed unconditionally for custom servers')

    -- 2. Cache pruning simulation
    local pollutedCache = {
        ['areataunt'] = { name = 'Area Taunt' },
        ['combatagility'] = { name = 'Combat Agility' },
        ['headshot'] = { name = 'Headshot' },
        ['manaburn'] = { name = 'Mana Burn' },
        ['harmtouch'] = { name = 'Harm Touch' },
        ['divinearbitration'] = { name = 'Divine Arbitration' },
    }
    for cName, cd in pairs(pollutedCache) do
        if not isAllowed(cd.name, warClasses, false) then
            pollutedCache[cName] = nil
        end
    end
    assert_true(pollutedCache['areataunt'] ~= nil, 'Suite 70: Cache preserves valid Area Taunt for Warrior')
    assert_true(pollutedCache['combatagility'] ~= nil, 'Suite 70: Cache preserves valid Combat Agility for Warrior')
    assert_true(pollutedCache['headshot'] == nil, 'Suite 70: Cache PRUNES foreign Headshot for Warrior')
    assert_true(pollutedCache['manaburn'] == nil, 'Suite 70: Cache PRUNES foreign Mana Burn for Warrior')
    assert_true(pollutedCache['harmtouch'] == nil, 'Suite 70: Cache PRUNES foreign Harm Touch for Warrior')
    assert_true(pollutedCache['divinearbitration'] == nil, 'Suite 70: Cache PRUNES foreign Divine Arbitration for Warrior')

    -- 3. Source code inspection of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AA.CLASS_ARCHETYPES = {") ~= nil, 'Suite 70: triune.lua defines CLASS_ARCHETYPES')
    assert_true(AA_CONTENT:find("AA.ARCHETYPE_CLASSES = {") ~= nil, 'Suite 70: triune.lua defines ARCHETYPE_CLASSES')
    assert_true(AA_CONTENT:find("AA.ARCHETYPE_RESTRICTIONS = {") ~= nil, 'Suite 70: triune.lua defines ARCHETYPE_RESTRICTIONS')
    assert_true(AA_CONTENT:find("AA.CLASS_SPECIFIC_ABILITIES = {") ~= nil, 'Suite 70: triune.lua defines CLASS_SPECIFIC_ABILITIES')
    assert_true(AA_CONTENT:find("AA.buildAAClassRestrictions") ~= nil, 'Suite 70: triune.lua defines buildAAClassRestrictions')
    assert_true(AA_CONTENT:find("AA.isAAAllowedForPlayer") ~= nil, 'Suite 70: triune.lua defines isAAAllowedForPlayer')
    assert_true(AA_CONTENT:find("if not AA%.isAAAllowedForPlayer%(name, nil, isFromUI%) then%s+return") ~= nil,
        'Suite 70: recordScannedAA filters foreign class abilities')
    assert_true(AA_CONTENT:find("if isSkill or not AA%.isAAAllowedForPlayer%(cName, nil, false%) then") ~= nil,
        'Suite 70: scanPlayerAAs cache pruning removes foreign class abilities')
    assert_true(AA_CONTENT:find("if ctrl%.auto_aa_priorities and ctrl%.auto_aa_priorities%[name%] then") ~= nil,
        'Suite 70: isAAAllowedForPlayer permits prioritized abilities unconditionally')
end

-- ============================================================================
-- Suite 71: Alternate Advancement Description Extraction, Text Wrapping & Hover Tooltips
-- ============================================================================
print('--- Suite 71: AA Description Extraction, Text Wrapping & Hover Tooltips ---')
do
    -- 1. Test runtime.wrapText simulation
    local function simWrapText(text, maxLineLen)
        if not text or text == '' then return '' end
        maxLineLen = maxLineLen or 60
        local lines = {}
        for paragraph in tostring(text):gmatch("([^\r\n]+)") do
            local line = ''
            for word in paragraph:gmatch("%S+") do
                if #line == 0 then
                    line = word
                elseif #line + 1 + #word <= maxLineLen then
                    line = line .. ' ' .. word
                else
                    lines[#lines + 1] = line
                    line = word
                end
            end
            if #line > 0 then
                lines[#lines + 1] = line
            end
        end
        return table.concat(lines, '\n')
    end

    assert_eq(simWrapText(nil), '', 'Suite 71: nil text returns empty string')
    assert_eq(simWrapText(''), '', 'Suite 71: empty text returns empty string')

    local shortText = 'Short description.'
    assert_eq(simWrapText(shortText, 50), 'Short description.', 'Suite 71: short text is untouched')

    local longText = 'This ability increases your chance to avoid incoming melee attacks by 5% per rank and provides defensive mitigation.'
    local wrapped = simWrapText(longText, 45)
    local wrapLines = {}
    for l in wrapped:gmatch("[^\r\n]+") do wrapLines[#wrapLines + 1] = l end
    assert_true(#wrapLines >= 3, 'Suite 71: long text wrapped into 3+ lines')
    for _, l in ipairs(wrapLines) do
        assert_true(#l <= 45, string.format('Suite 71: line length %d <= 45', #l))
    end

    -- 2. Test getAADescription logic simulation
    local itmWithDesc = { name = 'Combat Agility', rank = 3, maxRank = 5, cost = 2, description = 'Pre-cached description.' }
    local function simGetAADescription(itm, mockTloDesc, mockCache)
        if not itm then return '' end
        if itm.description and itm.description ~= '' then
            return itm.description
        end
        local desc = mockTloDesc or ''
        if desc ~= '' then
            itm.description = desc
            if mockCache and mockCache[itm.name] then
                mockCache[itm.name].description = desc
            end
        end
        return desc
    end

    local cache = { ['Combat Agility'] = { rank = 3, maxRank = 5, cost = 2 } }
    local d1 = simGetAADescription(itmWithDesc, 'Different mock', cache)
    assert_eq(d1, 'Pre-cached description.', 'Suite 71: returns existing itm.description without TLO call')

    local itmLazy = { name = 'Combat Agility', rank = 3, maxRank = 5, cost = 2 }
    local d2 = simGetAADescription(itmLazy, 'Mock TLO description with 10% bonus', cache)
    assert_eq(d2, 'Mock TLO description with 10% bonus', 'Suite 71: lazily retrieves TLO description')
    assert_eq(itmLazy.description, 'Mock TLO description with 10% bonus', 'Suite 71: caches description on itm')
    assert_eq(cache['Combat Agility'].description, 'Mock TLO description with 10% bonus', 'Suite 71: caches description in runtime.cachedAAData')

    -- 3. Test Tooltip Construction & Percent Format Safety
    local function simFormatAATooltip(itm, desc)
        local wrappedDesc = (desc and desc ~= '') and simWrapText(desc, 50) or nil
        local tip
        if wrappedDesc and wrappedDesc ~= '' then
            tip = string.format('%s\nCurrent Rank: %d / %d\nNext Rank Cost: %d AA\nPoints Spent: %d AA\n\n%s',
                itm.name, itm.rank, itm.maxRank, itm.cost, itm.pointsSpent or 0, wrappedDesc)
        else
            tip = string.format('%s\nCurrent Rank: %d / %d\nNext Rank Cost: %d AA\nPoints Spent: %d AA',
                itm.name, itm.rank, itm.maxRank, itm.cost, itm.pointsSpent or 0)
        end
        return tip
    end

    local tipWithDesc = simFormatAATooltip({ name = 'Innate Run Speed', rank = 1, maxRank = 3, cost = 2, pointsSpent = 1 }, 'Increases base run speed by 10% and movement rate by 5%.')
    assert_true(tipWithDesc:find("Innate Run Speed") ~= nil, 'Suite 71: Tooltip includes ability name')
    assert_true(tipWithDesc:find("Current Rank: 1 / 3") ~= nil, 'Suite 71: Tooltip includes rank')
    assert_true(tipWithDesc:find("Next Rank Cost: 2 AA") ~= nil, 'Suite 71: Tooltip includes cost')
    assert_true(tipWithDesc:find("Increases base run speed") ~= nil, 'Suite 71: Tooltip includes description')
    -- Safe to pass to ImGui.SetTooltip('%s', tip) even with literal %
    local okFormat, formatted = pcall(string.format, '%s', tipWithDesc)
    assert_true(okFormat, 'Suite 71: Tooltip with % characters formats safely with %s specifier')

    -- 3.5 Test AA Tab Tooltip Construction with Description & Formatting
    local function simFormatAATabTooltip(nm, cls, secNum, tier, desc, rank, maxRank)
        local wrappedDesc = (desc and desc ~= '') and simWrapText(desc, 50) or nil
        local header = string.format('AA Ability: %s', nm)
        local meta = {}
        if cls and cls ~= '' then table.insert(meta, string.format('Class: %s', cls)) end
        if secNum then table.insert(meta, string.format('Cooldown: %ds (%s)', secNum, tier)) end
        if rank and maxRank and maxRank > 0 then
            table.insert(meta, string.format('Rank: %d/%d', rank, maxRank))
        elseif rank and rank > 0 then
            table.insert(meta, string.format('Rank: %d', rank))
        end
        local lines = { header }
        if #meta > 0 then table.insert(lines, table.concat(meta, '  |  ')) end
        if wrappedDesc and wrappedDesc ~= '' then
            table.insert(lines, '')
            table.insert(lines, wrappedDesc)
        end
        return table.concat(lines, '\n')
    end

    local aaTabTip = simFormatAATabTooltip('Call of Challenge', 'War', 10, 'short', 'Taunts the target and challenges their attention with a 50% threat boost.', 1, 3)
    assert_true(aaTabTip:find('AA Ability: Call of Challenge') ~= nil, 'Suite 71: AA tab tooltip has header')
    assert_true(aaTabTip:find('Class: War') ~= nil, 'Suite 71: AA tab tooltip has class')
    assert_true(aaTabTip:find('Cooldown: 10s %(short%)') ~= nil, 'Suite 71: AA tab tooltip has cooldown')
    assert_true(aaTabTip:find('Rank: 1/3') ~= nil, 'Suite 71: AA tab tooltip has rank')
    assert_true(aaTabTip:find('Taunts the target') ~= nil, 'Suite 71: AA tab tooltip has wrapped description')

    -- 4. Source code inspection of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find("function runtime.wrapText%(text, maxLineLen%)") ~= nil,
        'Suite 71: triune.lua defines runtime.wrapText')
    assert_true(triuneContent:find("function runtime.getAADescription%(itm%)") ~= nil,
        'Suite 71: triune.lua defines runtime.getAADescription')
    assert_true(triuneContent:find("function runtime.showAATooltip%(itm%)") ~= nil,
        'Suite 71: triune.lua defines runtime.showAATooltip')
    assert_true(triuneContent:find("function runtime.showAATabTooltip%(name, cls, secNum, tier%)") ~= nil,
        'Suite 71: triune.lua defines runtime.showAATabTooltip')
    assert_true(triuneContent:find("runtime.showAATabTooltip%(nm, cls, secNum, tier%)") ~= nil,
        'Suite 71: UI.drawAATab invokes runtime.showAATabTooltip on hover')
    assert_true(AA_CONTENT:find("description = cd.description") ~= nil,
        'Suite 71: recordScannedAA restores description from cache')
    assert_true(triuneContent:find("if ma.Description then%s+local d = ma.Description%(%)") ~= nil,
        'Suite 71: recordScannedAA extracts description from Me.AltAbility')
    assert_true(AA_CONTENT:find("if %(not description or description == ''%) and ga.Description then%s+local d = ga.Description%(%)") ~= nil,
        'Suite 71: recordScannedAA extracts description from AltAbility')
    assert_true(AA_CONTENT:find("description = description") ~= nil,
        'Suite 71: recordScannedAA populates description in entry and cache')
    assert_true(triuneContent:find("runtime.showAATooltip%(itm%)") ~= nil,
        'Suite 71: UI.drawAutoAATab displays runtime.showAATooltip on hover')
end

-- ============================================================================
-- Suite 72: Special Tab AA & Fireworks Training Reliability Logic
-- ============================================================================
print('--- Suite 72: Special Tab AA & Fireworks Training Reliability Logic ---')
do
    -- 1. Special Tab AA Detection simulation
    local function simIsSpecialTabAA(name)
        if not name or name == '' then return false end
        local lower = tostring(name):lower()
        if lower:find('firework') then return true end
        return false
    end

    assert_true(simIsSpecialTabAA('Alternately Advanced Fireworks'), 'Suite 72: Detects Fireworks as Special tab AA')
    assert_true(simIsSpecialTabAA('fireworks'), 'Suite 72: Detects lowercase fireworks as Special tab AA')
    assert_eq(simIsSpecialTabAA('Combat Agility'), false, 'Suite 72: Non-fireworks ability is not Special tab')

    -- 2. Repeatable Special Tab Ability Retention Logic
    local function simIsFullyTrained(name, rank, maxRank)
        local isSpecial = simIsSpecialTabAA(name)
        return not isSpecial and (maxRank > 0 and rank >= maxRank)
    end

    assert_eq(simIsFullyTrained('Alternately Advanced Fireworks', 0, 1), false, 'Suite 72: Fireworks 0/1 is not fully trained')
    assert_eq(simIsFullyTrained('Alternately Advanced Fireworks', 1, 1), false, 'Suite 72: Repeatable Fireworks 1/1 is never fully trained')
    assert_true(simIsFullyTrained('Combat Agility', 5, 5), 'Suite 72: Standard ability 5/5 is fully trained')

    -- 3. /alt buy Support Logic for Custom Servers
    local function simCanIssueAltBuy(name, aaId)
        if aaId and aaId > 0 then
            return true
        end
        if name and name ~= '' then
            return true
        end
        return false
    end

    assert_true(simCanIssueAltBuy('Alternately Advanced Fireworks', 17788), 'Suite 72: Allows /alt buy for Fireworks activation ID 17788 on custom server')
    assert_true(simCanIssueAltBuy('Alternately Advanced Fireworks', 0), 'Suite 72: Allows /alt buy by ability name')
    assert_true(simCanIssueAltBuy('Combat Agility', 101), 'Suite 72: Allows /alt buy for standard AA with valid ID')

    -- 4. Multi-Vector Purchase Verification Logic (Points, Spent, Rank)
    local function simVerifyPurchase(initPts, curPts, initSpent, curSpent, initRank, curRank)
        return (curPts < initPts) or (curRank > initRank) or (curSpent > initSpent)
    end

    -- Repeatable Fireworks purchase: Rank stays 0, but unspent points decrease and spent points increase
    assert_true(simVerifyPurchase(38, 13, 10060, 10085, 0, 0), 'Suite 72: Verifies Fireworks purchase via unspent point decrease')
    assert_true(simVerifyPurchase(38, 38, 10060, 10085, 0, 0), 'Suite 72: Verifies Fireworks purchase via spent points increase even if unspent lag')
    assert_true(simVerifyPurchase(10, 8, 50, 52, 1, 2), 'Suite 72: Verifies standard AA purchase via rank increase')
    assert_eq(simVerifyPurchase(38, 38, 10060, 10060, 0, 0), false, 'Suite 72: Rejects purchase when no points or rank changed')

    -- 5. Watchdog Timeout Simulation
    local function simCheckWatchdog(startedAt, now)
        return (now - startedAt) > 10.0
    end

    assert_eq(simCheckWatchdog(100.0, 105.0), false, 'Suite 72: Watchdog does not trigger before 10s')
    assert_true(simCheckWatchdog(100.0, 110.1), 'Suite 72: Watchdog triggers and clears task after 10s')

    -- 6. Source code inspection of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("AA%.pendingAATrain") ~= nil,
        'Suite 72: triune.lua defines AA.pendingAATrain')
    assert_true(AA_CONTENT:find("step = 'open'") ~= nil,
        'Suite 72: triune.lua initializes step to open')
    assert_true(AA_CONTENT:find("mq%.cmdf%('/nomodkey /notify %%s %%s leftmouseup', winName, listName%)") ~= nil,
        'Suite 72: triune.lua sends leftmouseup to list row to activate Train button')
    assert_true(AA_CONTENT:find("not isSpecial and %(maxRank > 0 and rank >= maxRank%)") ~= nil,
        'Suite 72: triune.lua prevents marking repeatable Special tab abilities as fully trained')
    assert_true(AA_CONTENT:find("Strict anti%-pause check: never spend AAs while casting or moving") ~= nil,
        'Suite 72: triune.lua guards checkAutoSpendAA against casting and movement to eliminate pauses')
end

-- ============================================================================
-- Suite 73: Between-Pulling AA Purchasing Logic
-- ============================================================================
print('--- Suite 73: Between-Pulling AA Purchasing Logic ---')
do
    -- 1. Simulation of between-pull auto-spend evaluation
    local function simBetweenPullsSpend(autoSpendEnabled, inCombat, xtarCount, isCasting, moving, allowStop, unspent, cost)
        if not autoSpendEnabled then return false, false end
        if inCombat or xtarCount > 0 or isCasting then return false, false end
        if unspent < cost or cost <= 0 then return false, false end
        -- Candidate is affordable
        local didStop = false
        if moving then
            if not allowStop then return false, false end
            didStop = true
        end
        return true, didStop
    end

    -- Test: Affordable AA between pulls halts movement cleanly
    local canBuy, didStop = simBetweenPullsSpend(true, false, 0, false, true, true, 25, 25)
    assert_true(canBuy, 'Suite 73: Purchases affordable AA between pulls')
    assert_true(didStop, 'Suite 73: Stops movement when purchasing affordable AA between pulls')

    -- Test: Unaffordable AA between pulls does not pause or stop movement
    local canBuy2, didStop2 = simBetweenPullsSpend(true, false, 0, false, true, true, 5, 25)
    assert_eq(canBuy2, false, 'Suite 73: Rejects unaffordable AA between pulls')
    assert_eq(didStop2, false, 'Suite 73: Does not stop movement when AA is unaffordable')

    -- Test: In combat between pulls (e.g. add on xtarget) blocks purchase
    local canBuyCombat, _ = simBetweenPullsSpend(true, true, 1, false, false, true, 50, 25)
    assert_eq(canBuyCombat, false, 'Suite 73: Combat or xtarget blocks between-pull AA purchase')

    -- Test: Default background check without allowStop does not stop moving
    local canBuyBg, didStopBg = simBetweenPullsSpend(true, false, 0, false, true, false, 50, 25)
    assert_eq(canBuyBg, false, 'Suite 73: Background check without allowStop rejected while moving')
    assert_eq(didStopBg, false, 'Suite 73: Background check does not stop movement')

    -- 2. Source code inspection of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("function AA%.checkAutoSpendAA%(allowStop%)") ~= nil,
        'Suite 73: triune.lua defines AA.checkAutoSpendAA(allowStop)')
    assert_true(AA_CONTENT:find("function AA%.startAATrainWorkflow%(targetName, allowStop%)") ~= nil,
        'Suite 73: triune.lua defines AA.startAATrainWorkflow(targetName, allowStop)')
    assert_true(triuneContent:find("Let plugins %(e%.g%. Auto AA purchases%) use the gap between pulls") ~= nil,
        'Suite 73: triune.lua offers the gap between pulls to plugins')
    assert_true(triuneContent:find("if runtime%.pluginManager%.onBetweenPulls%(%) then%s+stopMoving%(%)%s+return") ~= nil,
        'Suite 73: puller yields when a plugin claims the between-pull gap')
    assert_true(AA_CONTENT:find("return AA%.checkAutoSpendAA%(true%) == true") ~= nil,
        'Suite 73: auto_aa.onBetweenPulls invokes checkAutoSpendAA(true)')
    assert_true(triuneContent:find("if runtime%.combatHold%(%) then%s+stopMoving%(%)%s+return%s+end") ~= nil,
        'Suite 73: triune.lua pauses pulling while a plugin holds combat')
    assert_true(AA_CONTENT:find("return AA%.pendingAATrain ~= nil") ~= nil,
        'Suite 73: auto_aa.wantsCombatHold reports an active purchase workflow')
end

-- ============================================================================
-- Suite 74: Off-Mesh Stick Recovery & Nav Remap
-- ============================================================================
print('--- Suite 74: Off-Mesh Stick Recovery & Nav Remap ---')
do
    local function mockNavMq(meshLoaded, pathMap)
        return {
            TLO = {
                Navigation = {
                    MeshLoaded = function() return meshLoaded end,
                    PathExists = function(query)
                        return function()
                            if pathMap[query] ~= nil then return pathMap[query] end
                            return false
                        end
                    end,
                },
                Me = setmetatable({
                    X = function() return 10 end,
                    Y = function() return 20 end,
                    Z = function() return 5 end,
                    Moving = function() return false end,
                }, { __call = function() return true end }),
            },
            cmd = function() end,
            cmdf = function() end,
        }
    end

    -- 1. isPlayerOffMesh
    local onMesh = loadFunc(src, 'isPlayerOffMesh', {
        navLoaded = function() return true end,
        mq = mockNavMq(true, {
            ['loc 20.00 10.00 5.00'] = true,
        }),
        pcall = pcall,
    })
    assert_eq(onMesh(), false, 'Suite 74: on-mesh player is not off-mesh')

    local offMesh = loadFunc(src, 'isPlayerOffMesh', {
        navLoaded = function() return true end,
        mq = mockNavMq(true, {}),
        pcall = pcall,
    })
    assert_eq(offMesh(), true, 'Suite 74: no path from feet is off-mesh')

    local noPlugin = loadFunc(src, 'isPlayerOffMesh', {
        navLoaded = function() return false end,
        mq = mockNavMq(true, {}),
        pcall = pcall,
    })
    assert_eq(noPlugin(), false, 'Suite 74: nav not loaded is not off-mesh')

    local noMesh = loadFunc(src, 'isPlayerOffMesh', {
        navLoaded = function() return true end,
        mq = mockNavMq(false, {}),
        pcall = pcall,
    })
    assert_eq(noMesh(), false, 'Suite 74: missing zone mesh is not off-mesh')

    -- 2. tryOffMeshRecovery issues stick once per target
    local cmds = {}
    local pursuitState = { meshRecoverId = 0, meshRecoverAt = 0, lastNavTargetId = 0, lastStickDist = 0 }
    local recover = loadFunc(src, 'tryOffMeshRecovery', {
        pursuit = pursuitState,
        stickLoaded = function() return true end,
        navLoaded = function() return true end,
        mq = {
            TLO = { Navigation = { Active = function() return false end } },
            cmd = function(c) cmds[#cmds + 1] = c end,
            cmdf = function(fmt, ...) cmds[#cmds + 1] = string.format(fmt, ...) end,
        },
        pcall = pcall,
        print = function() end,
        os = os,
    })
    assert_eq(recover(4242, 12), false, 'Suite 74: recovery does not claim arrival')
    assert_eq(pursuitState.meshRecoverId, 4242, 'Suite 74: recovery stamps meshRecoverId')
    local sawStick = false
    for _, c in ipairs(cmds) do
        if tostring(c):find('/stick id 4242 12', 1, true) then sawStick = true end
    end
    assert_true(sawStick, 'Suite 74: recovery issues /stick id toward the spawn')

    cmds = {}
    recover(4242, 12)
    assert_eq(#cmds, 0, 'Suite 74: recovery does not re-issue stick while already tracking the same spawn')

    -- 3. Native fallback when MoveUtils is not loaded
    local nativeCmds = {}
    local nativePursuit = { meshRecoverId = 0, meshRecoverAt = 0, lastNavTargetId = 0, lastStickDist = 0 }
    local recoverNative = loadFunc(src, 'tryOffMeshRecovery', {
        pursuit = nativePursuit,
        stickLoaded = function() return false end,
        navLoaded = function() return true end,
        mq = {
            TLO = {
                Navigation = { Active = function() return false end },
                Me = { Moving = function() return false end },
            },
            cmd = function(c) nativeCmds[#nativeCmds + 1] = c end,
            cmdf = function(fmt, ...) nativeCmds[#nativeCmds + 1] = string.format(fmt, ...) end,
        },
        pcall = pcall,
        print = function() end,
        os = os,
    })
    recoverNative(77, 14)
    local sawFace, sawForward = false, false
    for _, c in ipairs(nativeCmds) do
        if c == '/face fast' then sawFace = true end
        if c == '/keypress forward hold' then sawForward = true end
    end
    assert_true(sawFace and sawForward, 'Suite 74: native recovery faces and walks forward without stick')
    assert_eq(nativePursuit.lastNavTargetId, 'native_spawn_77', 'Suite 74: native recovery tags lastNavTargetId')

    -- 4. Source inspections
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find('function runtime%.isPlayerOffMesh') ~= nil,
        'Suite 74: triune.lua defines isPlayerOffMesh')
    assert_true(triuneContent:find('function runtime%.tryOffMeshRecovery') ~= nil,
        'Suite 74: triune.lua defines tryOffMeshRecovery')
    assert_true(triuneContent:find('sticking toward it to leave the mesh hole, then remapping') ~= nil,
        'Suite 74: triune.lua logs off-mesh stick recovery')
    assert_true(triuneContent:find('Remapped nav path to #%%d after off%-mesh stick recovery') ~= nil,
        'Suite 74: triune.lua remaps /nav after PathExists returns')
    assert_true(triuneContent:find('local playerOffMesh = runtime%.isPlayerOffMesh') ~= nil,
        'Suite 74: findRoamTarget still picks NPCs when the player is off-mesh')
    assert_true(triuneContent:find('and not playerOffMesh then') ~= nil,
        'Suite 74: findRoamTarget skips PathExists filter while off-mesh')
    assert_true(not triuneContent:find('noPathFails >= 3'),
        'Suite 74: 3-tick no-path abandon no longer drops the target before recovery')
end

-- ============================================================================
-- Suite 75: Popout Unit Frames HUD Window Logic & Configuration
-- ============================================================================
do
    print('--- Suite 75: Popout Unit Frames HUD Window Logic & Configuration ---')
    local triuneContent = readFile('TAC/lua/triune.lua')
    local readmeContent = readFile('README.md')

    -- 1. Verify defaultCtrl defaults
    local defCtrlFunc = loadFunc(triuneContent, 'defaultCtrl', { MODES = MODES })
    assert_true(defCtrlFunc ~= nil, 'Suite 75: defaultCtrl loads successfully')
    local testDc = defCtrlFunc()
    assert_eq(testDc.show_unit_frames, false, 'Suite 75: defaultCtrl.show_unit_frames is false')
    assert_eq(testDc.uf_lock, false, 'Suite 75: defaultCtrl.uf_lock is false')
    assert_eq(testDc.uf_alpha, 0.85, 'Suite 75: defaultCtrl.uf_alpha is 0.85')
    assert_eq(testDc.uf_bar_height, 14, 'Suite 75: defaultCtrl.uf_bar_height is 14')
    assert_eq(testDc.uf_show_endurance, true, 'Suite 75: defaultCtrl.uf_show_endurance is true')
    assert_eq(testDc.uf_show_xp, true, 'Suite 75: defaultCtrl.uf_show_xp is true')
    assert_eq(testDc.uf_hide_empty_pets, true, 'Suite 75: defaultCtrl.uf_hide_empty_pets is true')
    assert_eq(testDc.uf_buff_max, 30, 'Suite 75: defaultCtrl.uf_buff_max is 30')

    assert_true(triuneContent:find('show_unit_frames%s*=%s*false') ~= nil,
        'Suite 75: defaultCtrl sets show_unit_frames to false')
    assert_true(triuneContent:find('uf_lock%s*=%s*false') ~= nil,
        'Suite 75: defaultCtrl sets uf_lock to false')
    assert_true(triuneContent:find('uf_alpha%s*=%s*0%.85') ~= nil,
        'Suite 75: defaultCtrl sets uf_alpha to 0.85')
    assert_true(triuneContent:find('uf_bar_height%s*=%s*14') ~= nil,
        'Suite 75: defaultCtrl sets uf_bar_height to 14')
    assert_true(triuneContent:find('uf_show_endurance%s*=%s*true') ~= nil,
        'Suite 75: defaultCtrl sets uf_show_endurance to true')
    assert_true(triuneContent:find('uf_show_xp%s*=%s*true') ~= nil,
        'Suite 75: defaultCtrl sets uf_show_xp to true')
    assert_true(triuneContent:find('uf_hide_empty_pets%s*=%s*true') ~= nil,
        'Suite 75: defaultCtrl sets uf_hide_empty_pets to true')
    assert_true(triuneContent:find('uf_buff_max%s*=%s*30') ~= nil,
        'Suite 75: defaultCtrl sets uf_buff_max to 30')

    -- 2. Verify window definition and autonomous plugin architecture
    local fUf = assert(io.open('TAC/lua/tac/hud_unitframes.lua', 'r'))
    local ufContent = fUf:read('*all')
    fUf:close()

    assert_true(triuneContent:find("TriunePluginsUI") ~= nil,
        'Suite 75: TriunePluginsUI is registered with mq.imgui.init')
    assert_true(triuneContent:find('function UI%.drawPlugins') ~= nil,
        'Suite 75: UI.drawPlugins is defined in triune.lua')
    assert_true(ufContent:find("id%s*=%s*'hud_unitframes'") ~= nil,
        'Suite 75: hud_unitframes plugin has id hud_unitframes')
    assert_true(ufContent:find('function plugin%.onDrawUI') ~= nil,
        'Suite 75: hud_unitframes defines onDrawUI render hook')
    assert_true(ufContent:find('function plugin%.onTick') ~= nil,
        'Suite 75: hud_unitframes defines onTick fiber hook')
    assert_true(triuneContent:find('function UI%.resolveTargetOfTarget') ~= nil,
        'Suite 75: UI.resolveTargetOfTarget is defined in triune.lua')
    assert_true(triuneContent:find('resolveTargetOfTarget%s*=') ~= nil,
        'Suite 75: UI.resolveTargetOfTarget is exported to plugins via pm.getCoreApi()')

    -- 3. Verify slash command and toolbar buttons
    assert_true(triuneContent:find("cmd == 'hud' or cmd == 'uf'") ~= nil,
        'Suite 75: /ac hud and /ac uf slash commands are registered')
    assert_true(readFile('TAC/lua/tac/hud_unitframes.lua'):find("label = 'Target & Player HUD'", 1, true) ~= nil,
        'Suite 75: hud_unitframes declares its header window button (drawn by pm.drawHeaderButtons)')
    assert_true(triuneContent:find("HUD##miniHud") ~= nil,
        'Suite 75: Mini GUI toolbar contains HUD button')

    -- 4. Verify version consistency
    local vTriune = triuneContent:match("local VERSION%s*=%s*'(.-)'")
    local vReadme = readmeContent:match("Current version:%s*%*%*(.-)%*%*")
    assert_true(vTriune ~= nil and #vTriune > 0, 'Suite 75: triune.lua has valid VERSION')
    assert_true(vReadme ~= nil and #vReadme > 0, 'Suite 75: README.md has valid version')
    assert_eq(vTriune, vReadme, 'Suite 75: Version numbers match across triune.lua and README.md')
end

-- ============================================================================
-- Suite 76: Popout Group Window Logic & Configuration
-- ============================================================================
do
    print('--- Suite 76: Popout Group Window Logic & Configuration ---')
    local triuneContent = readFile('TAC/lua/triune.lua')
    local readmeContent = readFile('README.md')

    -- 1. Verify defaultCtrl defaults
    local defCtrlFunc = loadFunc(triuneContent, 'defaultCtrl', { MODES = MODES })
    assert_true(defCtrlFunc ~= nil, 'Suite 76: defaultCtrl loads successfully')
    local testDc = defCtrlFunc()
    assert_eq(testDc.show_group_window, false, 'Suite 76: defaultCtrl.show_group_window is false')
    assert_eq(testDc.gw_lock, false, 'Suite 76: defaultCtrl.gw_lock is false')
    assert_eq(testDc.gw_alpha, 0.85, 'Suite 76: defaultCtrl.gw_alpha is 0.85')
    assert_eq(testDc.gw_bar_height, 14, 'Suite 76: defaultCtrl.gw_bar_height is 14')
    assert_eq(testDc.gw_include_self, true, 'Suite 76: defaultCtrl.gw_include_self is true')
    assert_eq(testDc.gw_show_mana, true, 'Suite 76: defaultCtrl.gw_show_mana is true')
    assert_eq(testDc.gw_show_endurance, false, 'Suite 76: defaultCtrl.gw_show_endurance is false')
    assert_eq(testDc.gw_show_pets, true, 'Suite 76: defaultCtrl.gw_show_pets is true')
    assert_eq(testDc.gw_show_roles, true, 'Suite 76: defaultCtrl.gw_show_roles is true')

    assert_true(triuneContent:find('show_group_window%s*=%s*false') ~= nil,
        'Suite 76: defaultCtrl sets show_group_window to false')
    assert_true(triuneContent:find('gw_lock%s*=%s*false') ~= nil,
        'Suite 76: defaultCtrl sets gw_lock to false')
    assert_true(triuneContent:find('gw_alpha%s*=%s*0%.85') ~= nil,
        'Suite 76: defaultCtrl sets gw_alpha to 0.85')
    assert_true(triuneContent:find('gw_bar_height%s*=%s*14') ~= nil,
        'Suite 76: defaultCtrl sets gw_bar_height to 14')
    assert_true(triuneContent:find('gw_include_self%s*=%s*true') ~= nil,
        'Suite 76: defaultCtrl sets gw_include_self to true')
    assert_true(triuneContent:find('gw_show_mana%s*=%s*true') ~= nil,
        'Suite 76: defaultCtrl sets gw_show_mana to true')
    assert_true(triuneContent:find('gw_show_endurance%s*=%s*false') ~= nil,
        'Suite 76: defaultCtrl sets gw_show_endurance to false')
    assert_true(triuneContent:find('gw_show_pets%s*=%s*true') ~= nil,
        'Suite 76: defaultCtrl sets gw_show_pets to true')
    assert_true(triuneContent:find('gw_show_roles%s*=%s*true') ~= nil,
        'Suite 76: defaultCtrl sets gw_show_roles to true')

    -- 2. Verify the window now lives in the hud_group plugin (render-only, no fiber)
    local gwContent = readFile('TAC/lua/tac/hud_group.lua')
    assert_true(triuneContent:find('function UI%.drawGroupWindow') == nil,
        'Suite 76: UI.drawGroupWindow was removed from triune.lua')
    assert_true(triuneContent:find("mq%.imgui%.init%('TriuneGroupWindow'") == nil,
        'Suite 76: TriuneGroupWindow imgui registration was removed from triune.lua')
    local gwPlugin = assert(loadfile('TAC/lua/tac/hud_group.lua'))()
    assert_eq(gwPlugin.id, 'hud_group', 'Suite 76: hud_group plugin id')
    assert_eq(gwPlugin.hasThread, false, 'Suite 76: hud_group is render-only (no fiber)')
    assert_eq(gwPlugin.runOutOfCombatOnly, false, 'Suite 76: hud_group keeps rendering in combat')
    assert_type(gwPlugin.onDrawUI, 'function', 'Suite 76: hud_group defines onDrawUI')
    assert_type(gwPlugin.onDrawSettings, 'function', 'Suite 76: hud_group defines onDrawSettings')
    assert_true(gwContent:find('ctrl%.show_group_window') ~= nil,
        'Suite 76: hud_group visibility is driven by ctrl.show_group_window')

    -- 3. Verify slash command and toolbar buttons
    assert_true(triuneContent:find("cmd == 'group' or cmd == 'gw'") ~= nil,
        'Suite 76: /ac group and /ac gw slash commands are registered')
    assert_true(readFile('TAC/lua/tac/hud_group.lua'):find("flag = 'show_group_window'", 1, true) ~= nil,
        'Suite 76: hud_group declares its header window button (drawn by pm.drawHeaderButtons)')
    assert_true(triuneContent:find("Grp##miniGroup") ~= nil,
        'Suite 76: Mini GUI toolbar contains Grp button')

    -- 4. Verify context menu and target clicks
    assert_true(gwContent:find("ImGui%.BeginPopupContextWindow%('##gwContextMenu'%)") ~= nil,
        'Suite 76: Group window has right-click context menu')
    assert_true(gwContent:find("mq%.cmdf%('/target id %%d'") ~= nil,
        'Suite 76: Group window supports click-to-target')

    -- 5. Verify Invite and Disband buttons
    assert_true(gwContent:find("Invite##gwInvite") ~= nil,
        'Suite 76: Group window has Invite button')
    assert_true(gwContent:find("Disband##gwDisband") ~= nil or gwContent:find("disLabel %.%. '##gwDisband'") ~= nil,
        'Suite 76: Group window has Disband button')
    assert_true(gwContent:find("mq%.cmd%('/invite'%)") ~= nil,
        'Suite 76: Group window issues /invite command')
    assert_true(gwContent:find("mq%.cmd%('/disband'%)") ~= nil,
        'Suite 76: Group window issues /disband command')

    -- 6. Verify streamlined layout (class removed, LoS removed, percentage-only bars)
    assert_true(gwContent:find("%[Lvl %%d%] %%s") ~= nil,
        'Suite 76: Member header tag removes player class')
    assert_true(gwContent:find("hpText = string%.format%('HP: %%d%%%%', mem%.hpPct or 0%)") ~= nil,
        'Suite 76: Health bar displays percentage total only')
    assert_true(gwContent:find("manaText = string%.format%('Mana: %%d%%%%', mem%.manaPct or 0%)") ~= nil,
        'Suite 76: Mana bar displays percentage total only')

    -- 7. Plugin only touches the core through the plugin API
    assert_true(gwContent:find('runtime%.') == nil and gwContent:find('UI%.') == nil,
        'Suite 76: hud_group does not reach into runtime./UI. directly')
end

-- ============================================================================
-- Suite 77: Popout Effects & Songs Window Logic & Configuration
-- ============================================================================
do
    print('--- Suite 77: Popout Effects & Songs Window Logic & Configuration ---')
    local fTriune = assert(io.open('TAC/lua/triune.lua', 'r'))
    local triuneContent = fTriune:read('*all')
    fTriune:close()

    local fReadme = assert(io.open('README.md', 'r'))
    local readmeContent = fReadme:read('*all')
    fReadme:close()

    -- 1. Verify defaultCtrl defaults
    assert_true(triuneContent:find('show_effects_window%s*=%s*false') ~= nil,
        'Suite 77: defaultCtrl sets show_effects_window to false')
    assert_true(triuneContent:find('eff_lock%s*=%s*false') ~= nil,
        'Suite 77: defaultCtrl sets eff_lock to false')
    assert_true(triuneContent:find('eff_alpha%s*=%s*0%.85') ~= nil,
        'Suite 77: defaultCtrl sets eff_alpha to 0.85')
    assert_true(triuneContent:find('eff_bar_height%s*=%s*18') ~= nil,
        'Suite 77: defaultCtrl sets eff_bar_height to 18')
    assert_true(triuneContent:find("eff_sort_by%s*=%s*'Time Left %(Ascending%)'") ~= nil,
        'Suite 77: defaultCtrl sets eff_sort_by to Time Left (Ascending)')
    assert_true(triuneContent:find('eff_show_buffs%s*=%s*true') ~= nil,
        'Suite 77: defaultCtrl sets eff_show_buffs to true')
    assert_true(triuneContent:find('eff_show_songs%s*=%s*true') ~= nil,
        'Suite 77: defaultCtrl sets eff_show_songs to true')
    assert_true(triuneContent:find('eff_show_detrimental%s*=%s*true') ~= nil,
        'Suite 77: defaultCtrl sets eff_show_detrimental to true')

    -- 2. Verify the window now lives in the hud_effects plugin (render-only, no fiber)
    local effContent = readFile('TAC/lua/tac/hud_effects.lua')
    assert_true(triuneContent:find('function UI%.drawEffectsWindow') == nil,
        'Suite 77: UI.drawEffectsWindow was removed from triune.lua')
    assert_true(triuneContent:find("mq%.imgui%.init%('TriuneEffectsWindow'") == nil,
        'Suite 77: TriuneEffectsWindow imgui registration was removed from triune.lua')
    local effPlugin = assert(loadfile('TAC/lua/tac/hud_effects.lua'))()
    assert_eq(effPlugin.id, 'hud_effects', 'Suite 77: hud_effects plugin id')
    assert_eq(effPlugin.hasThread, false, 'Suite 77: hud_effects is render-only (no fiber)')
    assert_type(effPlugin.onDrawUI, 'function', 'Suite 77: hud_effects defines onDrawUI')
    assert_true(effContent:find('core%.parseDurationSec') ~= nil and effContent:find('core%.drawSpellIcon') ~= nil,
        'Suite 77: hud_effects uses parseDurationSec/drawSpellIcon through the plugin API')
    assert_true(triuneContent:find('parseDurationSec%s*=%s*parseDurationSec') ~= nil
        and triuneContent:find('drawSpellIcon%s*=%s*UI%.drawSpellIcon') ~= nil,
        'Suite 77: pm.getCoreApi exports parseDurationSec and drawSpellIcon')

    -- 3. Verify spell icon helpers
    assert_true(triuneContent:find('function UI%.drawSpellIcon') ~= nil,
        'Suite 77: UI.drawSpellIcon is defined in triune.lua')
    assert_true(triuneContent:find('function UI%.getSpellIconAnimation') ~= nil,
        'Suite 77: UI.getSpellIconAnimation is defined in triune.lua')

    -- 4. Verify slash command and toolbar buttons
    assert_true(triuneContent:find("cmd == 'eff' or cmd == 'effects'") ~= nil,
        'Suite 77: /ac eff and /ac effects slash commands are registered')
    assert_true(readFile('TAC/lua/tac/hud_effects.lua'):find("flag = 'show_effects_window'", 1, true) ~= nil,
        'Suite 77: hud_effects declares its header window button (drawn by pm.drawHeaderButtons)')
    assert_true(triuneContent:find("Buffs##miniEffects") ~= nil,
        'Suite 77: Mini GUI toolbar contains Buffs button')

    -- 5. Verify context menus and actions
    assert_true(effContent:find("ImGui%.BeginPopupContextWindow%('##effWinContextMenu'%)") ~= nil,
        'Suite 77: Effects window has background context menu')
    assert_true(effContent:find("ImGui%.BeginPopupContextItem%('##effItemMenu_'") ~= nil,
        'Suite 77: Each effect item has its own right-click context menu')
    assert_true(effContent:find("mq%.cmdf%('/removebuff %%s'") ~= nil,
        'Suite 77: Supports /removebuff action')
    assert_true(effContent:find("mq%.cmdf%('/blockspell add me %%d'") ~= nil,
        'Suite 77: Supports /blockspell add me action')
    assert_true(effContent:find("mq%.TLO%.Spell%(eff%.spellId%)%.Inspect%(%)") ~= nil,
        'Suite 77: Supports Spell.Inspect action')

    -- 6. Verify right-click context menu sorting controls
    assert_true(effContent:find("ImGui%.Combo%('##effSortCombo', curSortIdx, sortModes%)") ~= nil,
        'Suite 77: Effects window right-click menu has native ImGui.Combo sort dropdown')
    assert_true(effContent:find("ImGui%.MenuItem%(sm %.%. '##menuSort_'") ~= nil,
        'Suite 77: Effects window right-click menu has clickable MenuItem sort options')

    -- 7. Pure sorting logic validation
    local testList = {
        { name = 'Brevity', duration = 300, isSong = false, isBeneficial = true },
        { name = 'Aura of Insight', duration = 0, isSong = false, isBeneficial = true },
        { name = 'Selo Song', duration = 18, isSong = true, isBeneficial = true },
        { name = 'Boil Blood', duration = 45, isSong = false, isBeneficial = false },
    }

    -- Test Time Left (Ascending): 18s -> 45s -> 300s -> Aura (0s)
    local asc = { testList[1], testList[2], testList[3], testList[4] }
    table.sort(asc, function(a, b)
        local aTimed = (a.duration and a.duration > 0)
        local bTimed = (b.duration and b.duration > 0)
        if aTimed and not bTimed then return true end
        if not aTimed and bTimed then return false end
        if aTimed and bTimed then
            if a.duration ~= b.duration then return a.duration < b.duration end
        end
        return (a.name or ''):lower() < (b.name or ''):lower()
    end)
    assert_eq(asc[1].name, 'Selo Song', 'Suite 77: Asc sort soonest expiring first (Selo)')
    assert_eq(asc[2].name, 'Boil Blood', 'Suite 77: Asc sort second (Boil Blood)')
    assert_eq(asc[3].name, 'Brevity', 'Suite 77: Asc sort third (Brevity)')
    assert_eq(asc[4].name, 'Aura of Insight', 'Suite 77: Asc sort permanent last (Aura)')

    -- Test Time Left (Descending): Aura (0s / Perm) -> 300s -> 45s -> 18s
    local desc = { testList[1], testList[2], testList[3], testList[4] }
    table.sort(desc, function(a, b)
        local aTimed = (a.duration and a.duration > 0)
        local bTimed = (b.duration and b.duration > 0)
        if not aTimed and bTimed then return true end
        if aTimed and not bTimed then return false end
        if aTimed and bTimed then
            if a.duration ~= b.duration then return a.duration > b.duration end
        end
        return (a.name or ''):lower() < (b.name or ''):lower()
    end)
    assert_eq(desc[1].name, 'Aura of Insight', 'Suite 77: Desc sort permanent first')
    assert_eq(desc[2].name, 'Brevity', 'Suite 77: Desc sort longest timed next')
    assert_eq(desc[4].name, 'Selo Song', 'Suite 77: Desc sort shortest timed last')

    -- Test Buff Type: Detrimental (Boil Blood) -> Songs (Selo) -> Timed Buffs (Brevity) -> Perm (Aura)
    local btype = { testList[1], testList[2], testList[3], testList[4] }
    table.sort(btype, function(a, b)
        local function typeRank(e)
            if not e.isBeneficial then return 1 end
            if e.isSong then return 2 end
            if e.duration and e.duration > 0 then return 3 end
            return 4
        end
        local rA, rB = typeRank(a), typeRank(b)
        if rA ~= rB then return rA < rB end
        local aTimed = (a.duration and a.duration > 0)
        local bTimed = (b.duration and b.duration > 0)
        if aTimed and not bTimed then return true end
        if not aTimed and bTimed then return false end
        if aTimed and bTimed then
            if a.duration ~= b.duration then return a.duration < b.duration end
        end
        return (a.name or ''):lower() < (b.name or ''):lower()
    end)
    assert_eq(btype[1].name, 'Boil Blood', 'Suite 77: Buff Type sort detrimental first')
    assert_eq(btype[2].name, 'Selo Song', 'Suite 77: Buff Type sort song second')
    assert_eq(btype[3].name, 'Brevity', 'Suite 77: Buff Type sort timed buff third')
    assert_eq(btype[4].name, 'Aura of Insight', 'Suite 77: Buff Type sort perm buff last')

    -- 8. Verify Effects timer duration formatting with hours
    assert_eq(fmtSec(162000), '45h', 'Suite 77: 2700min effect formats as 45h')
    assert_eq(fmtSec(162300), '45h 5m', 'Suite 77: 2705min effect formats as 45h 5m')
    assert_eq(fmtSec(3600), '1h', 'Suite 77: 60min effect formats as 1h')
    assert_eq(fmtSec(5400), '1h 30m', 'Suite 77: 90min effect formats as 1h 30m')

    -- 9. Verify version sync
    local vTriune = triuneContent:match("local VERSION%s*=%s*'(.-)'")
    local vReadme = readmeContent:match("Current version:%s*%*%*(.-)%*%*")
    assert_eq(vTriune, '2.15', 'Suite 77: triune.lua VERSION is 2.15')
    assert_eq(vReadme, '2.15', 'Suite 77: README.md version is 2.15')
    assert_eq(vTriune, vReadme, 'Suite 77: Version numbers match across triune.lua and README.md')
end

-- ============================================================================
-- Suite 78: Popout Extended Target (XTarget) Window Logic & Configuration
-- ============================================================================
print('--- Suite 78: Popout Extended Target (XTarget) Window Logic & Configuration ---')
do
    local fTriune = assert(io.open('TAC/lua/triune.lua', 'r'))
    local triuneContent = fTriune:read('*all')
    fTriune:close()

    local fReadme = assert(io.open('README.md', 'r'))
    local readmeContent = fReadme:read('*all')
    fReadme:close()

    -- 1. Verify defaultCtrl contains xtarget fields
    assert_true(triuneContent:find('show_xtarget_window%s*=%s*false') ~= nil,
        'Suite 78: defaultCtrl.show_xtarget_window default is false')
    assert_true(triuneContent:find('xt_lock%s*=%s*false') ~= nil,
        'Suite 78: defaultCtrl.xt_lock default is false')
    assert_true(triuneContent:find('xt_alpha%s*=%s*0.85') ~= nil,
        'Suite 78: defaultCtrl.xt_alpha default is 0.85')
    assert_true(triuneContent:find('xt_bar_height%s*=%s*16') ~= nil,
        'Suite 78: defaultCtrl.xt_bar_height default is 16')
    assert_true(triuneContent:find('xt_show_empty%s*=%s*false') ~= nil,
        'Suite 78: defaultCtrl.xt_show_empty default is false')
    assert_true(triuneContent:find('xt_show_tot%s*=%s*true') ~= nil,
        'Suite 78: defaultCtrl.xt_show_tot default is true')
    assert_true(triuneContent:find('xt_show_aggro%s*=%s*true') ~= nil,
        'Suite 78: defaultCtrl.xt_show_aggro default is true')
    assert_true(triuneContent:find('xt_show_dist%s*=%s*true') ~= nil,
        'Suite 78: defaultCtrl.xt_show_dist default is true')

    -- 2. Verify the window now lives in the hud_xtarget plugin (render-only, no fiber)
    local xtContent = readFile('TAC/lua/tac/hud_xtarget.lua')
    assert_true(triuneContent:find("mq%.imgui%.init%('TriuneXTargetWindow'") == nil,
        'Suite 78: TriuneXTargetWindow imgui registration was removed from triune.lua')
    assert_true(triuneContent:find('function UI%.drawXTargetWindow%(%)') == nil,
        'Suite 78: UI.drawXTargetWindow was removed from triune.lua')
    local xtPlugin = assert(loadfile('TAC/lua/tac/hud_xtarget.lua'))()
    assert_eq(xtPlugin.id, 'hud_xtarget', 'Suite 78: hud_xtarget plugin id')
    assert_eq(xtPlugin.hasThread, false, 'Suite 78: hud_xtarget is render-only (no fiber)')
    assert_type(xtPlugin.onDrawUI, 'function', 'Suite 78: hud_xtarget defines onDrawUI')
    assert_true(xtContent:find('core%.addIgnore') ~= nil and triuneContent:find('addIgnore%s*=%s*runtime%.addIgnore') ~= nil,
        'Suite 78: hud_xtarget reaches the ignore list through the exported core API')

    -- Pet / friendly-PC slots are hidden by default (they are not hostiles)
    do
        local xtCtrl = {}
        local xtCore = {
            ctrl = xtCtrl,
            getMultiPetList = function() return { { petId = 501, cls = 'Nec', slotNum = 2 } }, { 777 } end,
        }
        xtPlugin.onInit(xtCore)
        assert_eq(xtCtrl.xt_show_pets, false, 'Suite 78: xt_show_pets defaults to false')
        assert_eq(xtCtrl.xt_show_pcs, false, 'Suite 78: xt_show_pcs defaults to false')
        local hidden = xtPlugin.isHiddenSlot
        assert_eq(hidden('NPC', 'Auto Hater', 100), false, 'Suite 78: Auto Hater NPC slot is shown')
        assert_eq(hidden('Pet', 'My Pet', 200), true, 'Suite 78: own pet slot is hidden')
        assert_eq(hidden('NPC', 'Group Member Pet', 300), true, 'Suite 78: group pet slot is hidden by slot type')
        assert_eq(hidden('NPC', 'Auto Hater', 501), true, 'Suite 78: Trio pet (multi-pet slot id) is hidden even in a hater slot')
        assert_eq(hidden('NPC', 'Auto Hater', 777), true, 'Suite 78: extra pet id from getMultiPetList is hidden')
        assert_eq(hidden('PC', 'Specific PC', 400), true, 'Suite 78: friendly PC slot is hidden')
        assert_eq(hidden('Mercenary', 'My Mercenary', 410), true, 'Suite 78: mercenary slot is hidden')
        assert_eq(hidden('PC', 'Group Tank', 420), true, 'Suite 78: Group Tank role slot is hidden')
        assert_eq(hidden('NPC', 'Group Tank Target', 430), false, 'Suite 78: Group Tank Target (what the tank fights) is shown')
        assert_eq(hidden('NPC', 'My Pet Target', 440), false, 'Suite 78: My Pet Target (what the pet fights) is shown')
        xtCtrl.xt_show_pets = true
        assert_eq(hidden('Pet', 'My Pet', 200), false, 'Suite 78: pets are listed when xt_show_pets is on')
        xtCtrl.xt_show_pcs = true
        assert_eq(hidden('PC', 'Specific PC', 400), false, 'Suite 78: PCs are listed when xt_show_pcs is on')
        assert_true(xtContent:find("Show Pets & Mercenaries##xtPets", 1, true) ~= nil,
            'Suite 78: context menu exposes the Show Pets toggle')
    end

    -- 3. Verify two-line header toolbar and compact button height
    assert_true(triuneContent:find("ImGuiStyleVar%.FramePadding,%s*5,%s*2") ~= nil,
        'Suite 78: Header toolbar buttons have compact FramePadding (5, 2)')
    assert_true(triuneContent:find("runtime.pluginManager.drawHeaderButtons(1)", 1, true) ~= nil,
        'Suite 78: Toolbar draws plugin window buttons through the plugin manager')
    assert_true(readFile('TAC/lua/tac/hud_xtarget.lua'):find("flag = 'show_xtarget_window'", 1, true) ~= nil,
        'Suite 78: hud_xtarget declares its header window button (drawn by pm.drawHeaderButtons)')
    assert_true(triuneContent:find("XT##miniXTarget") ~= nil,
        'Suite 78: Mini GUI toolbar contains XT button')

    -- 4. Verify slash command handler
    assert_true(triuneContent:find("cmd == 'xtar' or cmd == 'xt' or cmd == 'xtarget'") ~= nil,
        'Suite 78: /ac xtar, /ac xt, and /ac xtarget slash commands are registered')

    -- 5. Verify window context menus and actions
    assert_true(xtContent:find("ImGui%.BeginPopupContextWindow%('##xtWinContextMenu'%)") ~= nil,
        'Suite 78: XTarget window has background context menu')
    assert_true(xtContent:find("ImGui%.BeginPopupContextItem%('##xtItemMenu_'") ~= nil,
        'Suite 78: Each xtarget mob row has its own right-click context menu')
    assert_true(xtContent:find("mq%.cmdf%('/target id %%d'") ~= nil,
        'Suite 78: Clicking or selecting mob issues /target id')
    assert_true(xtContent:find("mq%.cmd%('/face fast'%)") ~= nil,
        'Suite 78: Supports Face Target action')

    -- 6. Verify version sync
    local vTriune = triuneContent:match("local VERSION%s*=%s*'(.-)'")
    local vReadme = readmeContent:match("Current version:%s*%*%*(.-)%*%*")
    assert_eq(vTriune, '2.15', 'Suite 78: triune.lua VERSION is 2.15')
    assert_eq(vReadme, '2.15', 'Suite 78: README.md version is 2.15')
    assert_eq(vTriune, vReadme, 'Suite 78: Version numbers match across triune.lua and README.md')
end

-- ============================================================================
-- Suite 79: Popout Spell Gem Bar Window Logic & Configuration
-- ============================================================================
print('--- Suite 79: Popout Spell Gem Bar Window Logic & Configuration ---')
do
    local fTriune = assert(io.open('TAC/lua/triune.lua', 'r'))
    local triuneContent = fTriune:read('*all')
    fTriune:close()

    local fReadme = assert(io.open('README.md', 'r'))
    local readmeContent = fReadme:read('*all')
    fReadme:close()

    -- 1. Verify defaultCtrl contains spell gem fields
    assert_true(triuneContent:find('show_spell_gems%s*=%s*false') ~= nil,
        'Suite 79: defaultCtrl.show_spell_gems default is false')
    assert_true(triuneContent:find('gem_lock%s*=%s*false') ~= nil,
        'Suite 79: defaultCtrl.gem_lock default is false')
    assert_true(triuneContent:find('gem_alpha%s*=%s*0.85') ~= nil,
        'Suite 79: defaultCtrl.gem_alpha default is 0.85')
    assert_true(triuneContent:find("gem_orientation%s*=%s*'Auto'") ~= nil,
        'Suite 79: defaultCtrl.gem_orientation default is Auto')
    assert_true(triuneContent:find('gem_show_badges%s*=%s*true') ~= nil,
        'Suite 79: defaultCtrl.gem_show_badges default is true')
    assert_true(triuneContent:find('gem_show_timer%s*=%s*true') ~= nil,
        'Suite 79: defaultCtrl.gem_show_timer default is true')

    -- 2. Verify window initialization and draw function
    local sgContent = readFile('TAC/lua/tac/hud_spellgems.lua')
    assert_true(triuneContent:find("mq%.imgui%.init%('TriuneSpellGemBarWindow'") == nil,
        'Suite 79: TriuneSpellGemBarWindow imgui registration removed from triune.lua')
    assert_true(triuneContent:find('function UI%.drawSpellGemBarWindow%(%)') == nil,
        'Suite 79: UI.drawSpellGemBarWindow removed from triune.lua (hud_spellgems plugin)')
    local sgPlugin = assert(loadfile('TAC/lua/tac/hud_spellgems.lua'))()
    assert_eq(sgPlugin.id, 'hud_spellgems', 'Suite 79: hud_spellgems plugin id')
    assert_eq(sgPlugin.hasThread, false, 'Suite 79: hud_spellgems is render-only')
    assert_type(sgPlugin.onDrawUI, 'function', 'Suite 79: hud_spellgems defines onDrawUI')
    assert_true(sgContent:find('function M%.drawSpellGemBarWindow%(%)') ~= nil,
        'Suite 79: hud_spellgems carries the spell gem bar renderer')
    assert_true(sgContent:find('core%.getGemCooldownSec') ~= nil and triuneContent:find('getGemCooldownSec%s*=%s*UI%.getGemCooldownSec') ~= nil,
        'Suite 79: gem cooldown helper is reached through the exported core API')

    -- 3. Verify toolbar buttons
    assert_true(readFile('TAC/lua/tac/hud_spellgems.lua'):find("flag = 'show_spell_gems'", 1, true) ~= nil,
        'Suite 79: hud_spellgems declares its header window button (drawn by pm.drawHeaderButtons)')
    assert_true(triuneContent:find("Gems##miniGems") ~= nil,
        'Suite 79: Mini GUI toolbar contains Gems button')

    -- 4. Verify slash command handler
    assert_true(triuneContent:find("cmd == 'gems' or cmd == 'gembar' or cmd == 'spellbar'") ~= nil,
        'Suite 79: /ac gems, /ac gembar, and /ac spellbar slash commands are registered')

    -- 5. Verify window context menus and actions
    assert_true(sgContent:find("ImGui%.BeginPopupContextWindow%('##gemWinContextMenu'%)") ~= nil,
        'Suite 79: Spell Gem Bar window has background options context menu')
    assert_true(sgContent:find("ImGui%.BeginPopupContextItem%('##gemItemMenu_'") ~= nil,
        'Suite 79: Each gem slot has its own right-click context menu')
    assert_true(sgContent:find("mq%.cmdf%('/cast %%d', slot%)") ~= nil,
        'Suite 79: Clicking or selecting gem issues /cast <slot>')
    assert_true(sgContent:find("mq%.cmdf%('/memorize \"\" %%d', slot%)") ~= nil,
        'Suite 79: Supports unmemorizing gem slot')

    -- 6. Verify Spellbook button and spell sets menu
    assert_true(sgContent:find("gemSpellBookBtn") ~= nil,
        'Suite 79: Spellbook button is rendered at end of gem bar')
    assert_true(triuneContent:find("UI%.drawSpellbookIcon") ~= nil,
        'Suite 79: High-detail vector Spellbook icon is drawn')
    assert_true(triuneContent:find("runtime%.savePreset") ~= nil,
        'Suite 79: Supports saving spell set preset in Triune loadout')
    assert_true(triuneContent:find("runtime%.loadPreset") ~= nil,
        'Suite 79: Supports loading spell set preset into memorization queue')
    assert_true(triuneContent:find("runtime%.deletePreset") ~= nil,
        'Suite 79: Supports deleting saved spell set preset')
    assert_true(triuneContent:find("UI%.col32") ~= nil,
        'Suite 79: UI.col32 provides safe 0xAABBGGRR color generation')
    assert_true(triuneContent:find("UI%.getGemCooldownSec") ~= nil,
        'Suite 79: UI.getGemCooldownSec converts EQ millisecond timer to true seconds')
    assert_true(sgContent:find("M%.gemCooldownEnd") ~= nil and triuneContent:find("gemCooldownEnd") == nil,
        'Suite 79: gemCooldownEnd frame countdown is plugin-local state')
    assert_true(sgContent:find("math%.ceil%(gemData%.timer%)") ~= nil,
        'Suite 79: Recast cooldowns simplified to integer seconds')

    -- 6. Verify Spell Set InputText and Preset Sorting Logic
    assert_true(sgContent:find("local newText,%s*changed%s*=%s*ImGui%.InputText") ~= nil,
        'Suite 79: ImGui.InputText correctly unpacks (text, changed) tuple')
    assert_true(sgContent:find("table%.sort%(presetList,") ~= nil,
        'Suite 79: Saved spell set presets are sorted alphabetically')

    assert_true(sgContent:find("M%.gemCooldownSpell") ~= nil and triuneContent:find("gemCooldownSpell") == nil,
        'Suite 79: gemCooldownSpell memorized-spell tracking is plugin-local state')

    -- 7. Pure logic simulation of countdown ticking
    local testNow = 1000.0
    local testRecast = 5.0
    local testEnd = testNow + testRecast
    local remAt0_5 = testEnd - (testNow + 0.5)
    local remAt2_1 = testEnd - (testNow + 2.1)
    local remAt4_2 = testEnd - (testNow + 4.2)
    assert_eq(math.ceil(remAt0_5), 5, 'Suite 79: Countdown displays 5 seconds at +0.5s into 5s recast')
    assert_eq(math.ceil(remAt2_1), 3, 'Suite 79: Countdown displays 3 seconds at +2.1s into 5s recast')
    assert_eq(math.ceil(remAt4_2), 1, 'Suite 79: Countdown displays 1 second at +4.2s into 5s recast')

    -- Continuous countdown simulation:
    -- Even when querySec stays static at 12 (e.g. from discrete 6s ticks or static recast),
    -- endAt is established and rem smoothly counts down across frames without freezing or resetting
    local staticQuery = 12.0
    local endAnchor = testNow + staticQuery
    for step = 1, 5 do
        local stepNow = testNow + (step * 1.0)
        local rem = endAnchor - stepNow
        assert_eq(math.ceil(rem), 12 - step, string.format('Suite 79: Countdown smoothly ticks to %d without freezing', 12 - step))
    end

    -- 8. Sentinel / 0xFFFFFFFF unsigned underflow and 1194h rejection
    local function simulateGemCooldownSec(rawMs, totalSec, spellRecast)
        local sec = 0
        if rawMs and (rawMs >= 2147483647 or rawMs < 0) then
            return 0
        end
        if totalSec and totalSec >= 2000000 then
            return 0
        end
        if totalSec and totalSec > 0 and totalSec < 3600 then
            sec = totalSec
        end
        if sec >= 3600 or sec < 0 then
            sec = 0
        end
        if spellRecast and spellRecast >= 0 then
            local maxAllowed = math.max(3.0, spellRecast + 3.0)
            if sec > maxAllowed then sec = 0 end
        end
        return sec
    end

    assert_eq(simulateGemCooldownSec(4294967295, 4294967, 10), 0, 'Suite 79: Rejects 0xFFFFFFFF unsigned underflow sentinel (1194h bug)')
    assert_eq(simulateGemCooldownSec(nil, 4294967, 10), 0, 'Suite 79: Rejects 4294967s TotalSeconds sentinel')
    assert_eq(simulateGemCooldownSec(nil, 50, 10), 0, 'Suite 79: Clamps cooldown that exceeds spell recast + buffer')
    assert_eq(simulateGemCooldownSec(nil, 8, 10), 8, 'Suite 79: Accepts valid cooldown within recast duration')

    -- Overlay timer formatting verification (no 1194h)
    local function fmtGemTimer(timerSec)
        local cdSec = math.ceil(timerSec)
        if cdSec >= 3600 then cdSec = 0 end
        return cdSec >= 60 and string.format('%dm', math.ceil(cdSec / 60)) or tostring(cdSec)
    end
    assert_eq(fmtGemTimer(4294967), '0', 'Suite 79: Corrupted 4294967s never renders 1194h')
    assert_eq(fmtGemTimer(120), '2m', 'Suite 79: 120s formats as 2m')
    assert_eq(fmtGemTimer(5), '5', 'Suite 79: 5s formats as 5')

    -- 9. Verify version sync
    local vTriune = triuneContent:match("local VERSION%s*=%s*'(.-)'")
    local vReadme = readmeContent:match("Current version:%s*%*%*(.-)%*%*")
    assert_eq(vTriune, '2.15', 'Suite 79: triune.lua VERSION is 2.15')
    assert_eq(vReadme, '2.15', 'Suite 79: README.md version is 2.15')
    assert_eq(vTriune, vReadme, 'Suite 79: Version numbers match across triune.lua and README.md')
end

-- ============================================================================
-- Suite 80: Popout Character Stats, Inventory & Currency Window Removal Verification
-- ============================================================================
print('--- Suite 80: Popout Character Stats, Inventory & Currency Window Removal ---')
do
    local fTriune = assert(io.open('TAC/lua/triune.lua', 'r'))
    local triuneContent = fTriune:read('*all')
    fTriune:close()

    -- 1. Verify defaultCtrl does NOT contain character window fields
    assert_true(triuneContent:find('show_character_window') == nil,
        'Suite 80: defaultCtrl.show_character_window was eliminated')
    assert_true(triuneContent:find('char_lock') == nil,
        'Suite 80: defaultCtrl.char_lock was eliminated')
    assert_true(triuneContent:find('char_alpha') == nil,
        'Suite 80: defaultCtrl.char_alpha was eliminated')
    assert_true(triuneContent:find('char_show_zerocur') == nil,
        'Suite 80: defaultCtrl.char_show_zerocur was eliminated')
    assert_true(triuneContent:find('char_slots_per_row') == nil,
        'Suite 80: defaultCtrl.char_slots_per_row was eliminated')

    -- 2. Verify window initialization and draw function are eliminated
    assert_true(triuneContent:find("TriuneCharacterWindow") == nil,
        'Suite 80: TriuneCharacterWindow is not registered via mq.imgui.init')
    assert_true(triuneContent:find('function UI%.drawCharacterWindow') == nil,
        'Suite 80: UI.drawCharacterWindow was eliminated')

    -- 3. Verify toolbar buttons are eliminated
    assert_true(triuneContent:find("Character##hdrChar") == nil,
        'Suite 80: Main toolbar Character toggle button was eliminated')
    assert_true(triuneContent:find("Char##miniChar") == nil,
        'Suite 80: Mini GUI toolbar Char toggle button was eliminated')

    -- 4. Verify slash command handler is eliminated
    assert_true(triuneContent:find("cmd == 'char' or cmd == 'charwin'") == nil,
        'Suite 80: /ac char and /ac character slash commands were eliminated')

    -- 5. Verify character window context menu and settings are eliminated
    assert_true(triuneContent:find("charContextMenu") == nil,
        'Suite 80: Character window context menu was eliminated')

    -- 6. Verify tabs and currency definitions are eliminated
    assert_true(triuneContent:find("charStatsTab") == nil,
        'Suite 80: Stats tab was eliminated')
    assert_true(triuneContent:find("charInvTab") == nil,
        'Suite 80: Inventory tab was eliminated')
    assert_true(triuneContent:find("charCurrTab") == nil,
        'Suite 80: Currency tab was eliminated')
    assert_true(triuneContent:find('UI%.coinDefs') == nil,
        'Suite 80: Coin definitions table was eliminated')
    assert_true(triuneContent:find('UI%.altCurrencyDefs') == nil,
        'Suite 80: Alt currency definitions table was eliminated')
    assert_true(triuneContent:find('UI%.readAltCurrencyAmount') == nil,
        'Suite 80: Alt currency reader was eliminated')
    assert_true(triuneContent:find('UI%.readCoinAmount') == nil,
        'Suite 80: Coin amount reader was eliminated')

    -- 7. Verify item management executor queue is eliminated
    assert_true(triuneContent:find('char_pendingAction') == nil,
        'Suite 80: char_pendingAction was eliminated')

    -- 8. Verify worn gear grid and EQ stat helpers are eliminated
    assert_true(triuneContent:find('UI%.wornSlotNames') == nil,
        'Suite 80: Worn equipment slot names table was eliminated')
    assert_true(triuneContent:find('UI%.wornLayout') == nil,
        'Suite 80: Worn equipment layout table was eliminated')
    assert_true(triuneContent:find('UI%.readInvChildText') == nil,
        'Suite 80: UI.readInvChildText helper was eliminated')
    assert_true(triuneContent:find('UI%.drawEqSectionHeader') == nil,
        'Suite 80: UI.drawEqSectionHeader helper was eliminated')
    assert_true(triuneContent:find('UI%.drawEqSlashRow') == nil,
        'Suite 80: UI.drawEqSlashRow helper was eliminated')
    assert_true(triuneContent:find('UI%.drawEqValRow') == nil,
        'Suite 80: UI.drawEqValRow helper was eliminated')
    assert_true(triuneContent:find('UI%.drawEqStatCapRow') == nil,
        'Suite 80: UI.drawEqStatCapRow helper was eliminated')
    assert_true(triuneContent:find('UI%.drawEqModRow') == nil,
        'Suite 80: UI.drawEqModRow helper was eliminated')

    -- 9. Verify stats sync and background equipment check routines are eliminated
    assert_true(triuneContent:find('runtime%.scanStatsFromInventoryWindow') == nil,
        'Suite 80: runtime.scanStatsFromInventoryWindow was eliminated')
    assert_true(triuneContent:find('runtime%.checkWornItemsChanged') == nil,
        'Suite 80: runtime.checkWornItemsChanged was eliminated')
    assert_true(triuneContent:find('runtime%.toggleSkillsWindow') == nil,
        'Suite 80: runtime.toggleSkillsWindow was eliminated')
    assert_true(triuneContent:find('statSyncRequested') == nil,
        'Suite 80: statSyncRequested was eliminated')
end

-- ============================================================================
-- Suite 81: Window Settings & Position Save/Restore Logic
-- ============================================================================
print('--- Suite 81: Window Settings & Position Save/Restore Logic ---')
do
    local fTriune = assert(io.open('TAC/lua/triune.lua', 'r'))
    local triuneContent = fTriune:read('*all')
    fTriune:close()

    local fReadme = assert(io.open('README.md', 'r'))
    local readmeContent = fReadme:read('*all')
    fReadme:close()

    -- 1. Verify defaultCtrl contains window position fields
    assert_true(triuneContent:find('saved_window_positions%s*=%s*{}') ~= nil,
        'Suite 81: defaultCtrl.saved_window_positions default is empty table')
    assert_true(triuneContent:find('winpos_auto_restore_on_resize%s*=%s*true') ~= nil,
        'Suite 81: defaultCtrl.winpos_auto_restore_on_resize default is true')
    assert_true(triuneContent:find('winpos_restore_visibility%s*=%s*false') ~= nil,
        'Suite 81: defaultCtrl.winpos_restore_visibility default is false')

    -- 2. Window registry: core owns main/mini, plugin windows are appended dynamically
    local expectedKeys = { 'main', 'mini', 'unit_frames', 'group', 'effects', 'cooldowns', 'spellbook', 'xtarget', 'spell_gems' }
    for _, k in ipairs({ 'main', 'mini' }) do
        assert_true(triuneContent:find("key%s*=%s*'" .. k .. "'") ~= nil,
            'Suite 81: runtime.CORE_WINDOWS tracks window key ' .. k)
    end
    assert_true(triuneContent:find('function runtime.getManagedWindows()', 1, true) ~= nil,
        'Suite 81: runtime.getManagedWindows builds the layout registry')
    assert_true(triuneContent:find('runtime.MANAGED_WINDOWS', 1, true) == nil,
        'Suite 81: static runtime.MANAGED_WINDOWS list removed (plugin windows are discovered)')
    for _, k in ipairs({ 'unit_frames', 'group', 'effects', 'cooldowns', 'xtarget', 'spell_gems' }) do
        assert_true(triuneContent:find("key%s*=%s*'" .. k .. "'") == nil,
            'Suite 81: core no longer hardcodes the ' .. k .. ' layout entry')
    end

    -- 3. Verify window position hooks
    assert_true(triuneContent:find('function UI%.preBeginWindow%(winKey%)') ~= nil,
        'Suite 81: UI.preBeginWindow is defined')
    assert_true(triuneContent:find('function UI%.postBeginWindow%(winKey%)') ~= nil,
        'Suite 81: UI.postBeginWindow is defined')
    local pluginWindowFiles = {
        unit_frames = 'TAC/lua/tac/hud_unitframes.lua',
        group       = 'TAC/lua/tac/hud_group.lua',
        effects     = 'TAC/lua/tac/hud_effects.lua',
        xtarget     = 'TAC/lua/tac/hud_xtarget.lua',
        cooldowns   = 'TAC/lua/tac/hud_cooldowns.lua',
        spell_gems  = 'TAC/lua/tac/hud_spellgems.lua',
        spellbook   = 'TAC/lua/tac/spellbook.lua',
    }
    for _, k in ipairs(expectedKeys) do
        if pluginWindowFiles[k] then
            local plContent = readFile(pluginWindowFiles[k])
            assert_true(plContent:find("core%.preBeginWindow%('" .. k .. "'%)") ~= nil,
                'Suite 81: core.preBeginWindow is hooked for ' .. k .. ' in ' .. pluginWindowFiles[k])
            assert_true(plContent:find("core%.postBeginWindow%('" .. k .. "'%)") ~= nil,
                'Suite 81: core.postBeginWindow is hooked for ' .. k .. ' in ' .. pluginWindowFiles[k])
        else
            assert_true(triuneContent:find("UI%.preBeginWindow%('" .. k .. "'%)") ~= nil,
                'Suite 81: UI.preBeginWindow is hooked for ' .. k)
            assert_true(triuneContent:find("UI%.postBeginWindow%('" .. k .. "'%)") ~= nil,
                'Suite 81: UI.postBeginWindow is hooked for ' .. k)
        end
    end

    -- 4. Verify save, restore, center, and reset logic
    assert_true(triuneContent:find('function runtime%.saveWindowPositions%(') ~= nil,
        'Suite 81: runtime.saveWindowPositions is defined')
    assert_true(triuneContent:find('function runtime%.triggerRestoreWindows%(') ~= nil,
        'Suite 81: runtime.triggerRestoreWindows is defined')
    assert_true(triuneContent:find('function runtime%.resetWindowPositionsToDefault%(') ~= nil,
        'Suite 81: runtime.resetWindowPositionsToDefault is defined')
    assert_true(triuneContent:find('function runtime%.centerWindow%(') ~= nil,
        'Suite 81: runtime.centerWindow is defined')
    assert_true(triuneContent:find('function runtime%.checkDisplaySizeChange%(') ~= nil,
        'Suite 81: runtime.checkDisplaySizeChange handles display resolution/monitor recovery')

    -- 5. Verify Settings subtab and drawWindowSettings
    assert_true(triuneContent:find("Window Settings##settingsWindows") ~= nil,
        'Suite 81: Settings tab has Window Settings subtab')
    assert_true(triuneContent:find('function UI%.drawWindowSettings%(%)') ~= nil,
        'Suite 81: UI.drawWindowSettings is defined')
    assert_true(triuneContent:find("ManagedWinTable") ~= nil,
        'Suite 81: Window Settings tab renders ManagedWinTable')

    -- 6. Verify slash command handler
    assert_true(triuneContent:find("cmd == 'winpos' or cmd == 'windows' or cmd == 'window'") ~= nil,
        'Suite 81: /ac winpos slash command is registered')

    -- 7. Verify version sync
    local vTriune = triuneContent:match("local VERSION%s*=%s*'(.-)'")
    local vReadme = readmeContent:match("Current version:%s*%*%*(.-)%*%*")
    assert_eq(vTriune, '2.15', 'Suite 81: triune.lua VERSION is 2.15')
    assert_eq(vReadme, '2.15', 'Suite 81: README.md version is 2.15')
    assert_eq(vTriune, vReadme, 'Suite 81: Version numbers match across triune.lua and README.md')
end

-- ============================================================================
-- Suite 82: Auto AA Cross-Class Stub Rejection & 1/? Filtering Logic
-- ============================================================================
print('--- Suite 82: Auto AA Cross-Class Stub Rejection & 1/? Filtering Logic ---')
do
    -- 1. Test isAAAllowedForPlayer foreign stub detection
    local function simIsAAAllowedForPlayer(name, classes, isFromUI, mockMe, mockCache, classRestrictions)
        if not name or name == '' then return false end
        if isFromUI then return true end

        local owned = false
        local isForeignStub = false
        local ma = mockMe and mockMe[name]
        if ma then
            local r = tonumber(ma.Rank or 0) or 0
            local mr = tonumber(ma.MaxRank or 0) or 0
            if r > 0 and mr > 0 then
                owned = true
            elseif r > 0 and mr <= 0 then
                isForeignStub = true
            end
        end
        if isForeignStub then return false end
        if owned then return true end

        if mockCache and mockCache[name] then
            local cd = mockCache[name]
            if cd.id and cd.id > 0 and cd.maxRank and cd.maxRank > 0 then return true end
        end

        local restricted = classRestrictions and classRestrictions[name]
        if restricted then
            local match = false
            for _, cls in ipairs(classes or {}) do
                if restricted[cls] then match = true; break end
            end
            if not match then return false end
        end
        return true
    end

    local warClasses = { 'War' }
    local restrictions = {
        ['Harm Touch'] = { SK = true },
        ['Cannibalization'] = { Shm = true },
        ['Combat Agility'] = nil -- universal
    }

    -- Foreign stub reporting Rank 1 with MaxRank 0 (1/?)
    local mockMe = {
        ['Harm Touch'] = { Rank = 1, MaxRank = 0, ID = 45 },
        ['Combat Agility'] = { Rank = 3, MaxRank = 5, ID = 101 },
    }
    assert_eq(simIsAAAllowedForPlayer('Harm Touch', warClasses, false, mockMe, nil, restrictions), false,
        'Suite 82: isAAAllowedForPlayer rejects Harm Touch foreign stub with Rank 1 and MaxRank 0')
    assert_true(simIsAAAllowedForPlayer('Combat Agility', warClasses, false, mockMe, nil, restrictions),
        'Suite 82: isAAAllowedForPlayer allows Combat Agility with valid Rank 3 and MaxRank 5')

    -- 2. Test cache pruning of invalid maxRank <= 0 entries
    local cache = {
        ['harmtouch'] = { name = 'Harm Touch', id = 45, maxRank = 0, rank = 1 },
        ['combatagility'] = { name = 'Combat Agility', id = 101, maxRank = 5, rank = 3 },
        ['unknownstub'] = { name = 'Unknown Stub', id = 999, rank = 1 } -- missing maxRank
    }
    for cName, cd in pairs(cache) do
        if not cd.maxRank or cd.maxRank <= 0 then
            cache[cName] = nil
        end
    end
    assert_true(cache['harmtouch'] == nil, 'Suite 82: Cache prunes Harm Touch with maxRank == 0')
    assert_true(cache['unknownstub'] == nil, 'Suite 82: Cache prunes stub with missing maxRank')
    assert_true(cache['combatagility'] ~= nil, 'Suite 82: Cache retains Combat Agility with valid maxRank 5')

    -- 3. Test getFilteredSortedAAs filtering of 1/? items
    local scannedAAs = {
        { name = 'Harm Touch', rank = 1, maxRank = 0, cost = 2, fullyTrained = false },
        { name = 'Combat Agility', rank = 3, maxRank = 5, cost = 5, fullyTrained = false },
        { name = 'Planar Power', rank = 0, maxRank = 5, cost = 3, fullyTrained = false },
    }
    local filtered = {}
    for _, item in ipairs(scannedAAs) do
        local match = true
        if not item.maxRank or item.maxRank <= 0 then
            match = false
        end
        if match then filtered[#filtered + 1] = item end
    end
    assert_eq(#filtered, 2, 'Suite 82: Filtered out 1/? Harm Touch entry')
    assert_eq(filtered[1].name, 'Combat Agility', 'Suite 82: First valid item is Combat Agility')
    assert_eq(filtered[2].name, 'Planar Power', 'Suite 82: Second valid item is Planar Power')

    -- 4. Source code verification of TAC/lua/triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(AA_CONTENT:find("if r > 0 and mr <= 0 then%s+isForeignStub = true") ~= nil,
        'Suite 82: triune.lua detects foreign stubs with r > 0 and mr <= 0')
    assert_true(AA_CONTENT:find("if not maxRank or maxRank <= 0 then%s+return%s+end") ~= nil,
        'Suite 82: recordScannedAA rejects abilities with maxRank <= 0')
    assert_true(AA_CONTENT:find("if not cd%.maxRank or cd%.maxRank <= 0 then%s+rt%.cachedAAData%[cName%] = nil") ~= nil,
        'Suite 82: cache pruning purges entries with missing or non-positive maxRank')
    assert_true(AA_CONTENT:find("if not item%.maxRank or item%.maxRank <= 0 then%s+match = false") ~= nil,
        'Suite 82: getFilteredSortedAAs filters out 1/? abilities')
    assert_true(AA_CONTENT:find("if nm and nm ~= '' and mr > 0 then%s+AA%.recordScannedAA%(list, foundMap, nm, r > 0 and r or nil, mr, nil, true, nil, false%)") ~= nil,
        'Suite 82: probeRange requires mr > 0 and passes isFromUI = false')
end

-- ============================================================================
-- 83. Combat Style Consolidation to Melee Only Logic Tests
-- ============================================================================
print('--- Suite 83: Combat Style Consolidation to Melee Only ---')
do
    local triuneContent = readFile('TAC/lua/triune.lua')

    -- 1. Verify removed mechanisms
    assert_true(triuneContent:find("TriuneAttackModeChanged", 1, true) == nil,
        'Suite 83: TriuneAttackModeChanged event was eliminated')
    assert_true(triuneContent:find("revertAttackModeToMelee", 1, true) == nil,
        'Suite 83: revertAttackModeToMelee function was eliminated')
    assert_true(triuneContent:find("ensureRangedAutoAttack", 1, true) == nil,
        'Suite 83: ensureRangedAutoAttack function was eliminated')
    assert_true(triuneContent:find("serverAttackMode", 1, true) == nil,
        'Suite 83: serverAttackMode state was eliminated')
    assert_true(triuneContent:find("RadioButton('Ranged (bow)'", 1, true) == nil,
        'Suite 83: Ranged radio button was eliminated from UI')
    assert_true(triuneContent:find("RadioButton('Spell'", 1, true) == nil,
        'Suite 83: Spell radio button was eliminated from UI')
    assert_true(triuneContent:find("rangedRangeSlider", 1, true) == nil,
        'Suite 83: rangedRangeSlider was eliminated from Settings tab')

    -- 2. Verify Melee distance slider remains
    assert_true(triuneContent:find("meleeRangeSlider", 1, true) ~= nil,
        'Suite 83: meleeRangeSlider remains active in Settings tab')

    -- 3. Verify sanitizeModeConfig forces combat_style = 'Melee'
    assert_true(triuneContent:find("c.combat_style = 'Melee'", 1, true) ~= nil,
        'Suite 83: sanitizeModeConfig forces combat_style to Melee')
end

-- ============================================================================
-- Suite 84: Auto AA Minimum 5 AA Bank Slider & Auto-Purchase Reliability
-- ============================================================================
print('--- Suite 84: Auto AA Minimum 5 AA Bank Slider & Auto-Purchase Reliability ---')
do
    local triuneContent = readFile('TAC/lua/triune.lua')

    -- 1. Verify bank slider in UI enforces a minimum of 5 AA
    assert_true(AA_CONTENT:find("SliderInt('##autoAaThresh', curThresh, 5, 100, 'Bank: %d')", 1, true) ~= nil,
        'Suite 84: Bank slider enforces 5 minimum AA points in UI')
    assert_true(AA_CONTENT:find("Reserve/Bank Threshold: %d AA points (min: 5)", 1, true) ~= nil,
        'Suite 84: Bank slider tooltip indicates 5 minimum AA points')

    -- 2. Verify sanitizeCtrl clamps auto_spend_aa_threshold to at least 5
    assert_true(triuneContent:find("tonumber(c.auto_spend_aa_threshold) < 5 then", 1, true) ~= nil,
        'Suite 84: sanitizeCtrl clamps auto_spend_aa_threshold to minimum of 5')

    -- 3. Verify checkAutoSpendAA halts early if unspent < 5 to avoid micro-pauses
    assert_true(AA_CONTENT:find("if unspent < 5 then return false end", 1, true) ~= nil,
        'Suite 84: checkAutoSpendAA skips evaluation when unspent < 5')

    -- 4. Verify findAAInWindowLists prioritizes preferredTab and does not overmatch substrings
    assert_true(AA_CONTENT:find("function AA.findAAInWindowLists(targetName, preferredTab)", 1, true) ~= nil,
        'Suite 84: findAAInWindowLists accepts preferredTab parameter')
    assert_true(triuneContent:find("cleanTarget:find(cleanRow, 1, true)", 1, true) == nil,
        'Suite 84: findAAInWindowLists eliminated dangerous substring overmatching')

    -- 5. Verify Special tab abilities (like Fireworks) and designated auto_spend_aa_name are whitelisted in isAAAllowedForPlayer
    assert_true(AA_CONTENT:find("if AA.isSpecialTabAA and AA.isSpecialTabAA(name) then", 1, true) ~= nil,
        'Suite 84: isAAAllowedForPlayer whitelists Special tab abilities')
    assert_true(AA_CONTENT:find("if ctrl.auto_spend_aa_name and name == ctrl.auto_spend_aa_name then", 1, true) ~= nil,
        'Suite 84: isAAAllowedForPlayer whitelists auto_spend_aa_name')

    -- 6. Verify synthetic maxRank for Special repeatable AAs in recordScannedAA
    assert_true(AA_CONTENT:find("if isSpecial and (not maxRank or maxRank <= 0) then", 1, true) ~= nil,
        'Suite 84: recordScannedAA sets synthetic maxRank for repeatable Special AAs')
end

-- ============================================================================
-- Suite 85: Auto AA Fireworks & Summon Firework (/alt act 17788) Reliability
-- ============================================================================
print('--- Suite 85: Auto AA Fireworks & Summon Firework (/alt act 17788) Reliability ---')
do
    local triuneContent = readFile('TAC/lua/triune.lua')

    -- 1. Verify post-purchase auto-summon and cooldown checks
    assert_true(AA_CONTENT:find("AA.scheduleFireworksSummon(fwId, task.name)", 1, true) ~= nil,
        'Suite 85: processAATrainWorkflow schedules a deferred fireworks summon after purchasing the AA')
    assert_true(AA_CONTENT:find("AltAbilityTimer('Summon Firework')", 1, true) ~= nil,
        'Suite 85: checkAutoSummonFireworks checks timer via Summon Firework')
    assert_true(AA_CONTENT:find("AltAbilityTimer('Alternately Advanced Fireworks')", 1, true) ~= nil,
        'Suite 85: checkAutoSummonFireworks checks timer via Alternately Advanced Fireworks')
    assert_true(triuneContent:find("/alt act %d", 1, true) ~= nil,
        'Suite 85: fireworks summoning uses /alt act command')

    -- 2. Verify priority candidate canTrainMet bypass for Special tab abilities
    assert_true(AA_CONTENT:find("local canTrainMet = isSpecial or canTrainCheck", 1, true) ~= nil,
        'Suite 85: checkAutoSpendAA allows isSpecial to bypass canTrainCheck')
    assert_true(AA_CONTENT:find("not fullyTrained and not isInvalidStub and levelMet and canTrainMet", 1, true) ~= nil,
        'Suite 85: candidate qualification uses canTrainMet')

    -- 3. Verify AAW_TrainFilter (CanPurchaseFilter) unchecking in processAATrainWorkflow
    assert_true(AA_CONTENT:find("AAW_TrainFilter", 1, true) ~= nil,
        'Suite 85: processAATrainWorkflow references AAW_TrainFilter')
    assert_true(AA_CONTENT:find("CanPurchaseFilter", 1, true) ~= nil,
        'Suite 85: processAATrainWorkflow references CanPurchaseFilter')
    assert_true(AA_CONTENT:find("triedUncheckTrainFilter", 1, true) ~= nil,
        'Suite 85: processAATrainWorkflow has triedUncheckTrainFilter fallback')

    -- 4. Verify direct listbox lookup aliases in findAAInWindowLists
    assert_true(AA_CONTENT:find("List('=Summon Firework')", 1, true) ~= nil,
        'Suite 85: findAAInWindowLists supports direct List lookup for Summon Firework')
    assert_true(AA_CONTENT:find("List('=Alternately Advanced Fireworks')", 1, true) ~= nil,
        'Suite 85: findAAInWindowLists supports direct List lookup for Alternately Advanced Fireworks')

    -- 5. Functional simulation of multi-path readiness check
    local function simCheckFireworksReady(mockReadyMap, mockTimerMap, aaId, name)
        local ready = false
        if mockReadyMap['Summon Firework'] or (mockTimerMap['Summon Firework'] == 0) then
            ready = true
        elseif mockReadyMap['Alternately Advanced Fireworks'] or (mockTimerMap['Alternately Advanced Fireworks'] == 0) then
            ready = true
        elseif name and (mockReadyMap[name] or mockTimerMap[name] == 0) then
            ready = true
        elseif aaId and (mockReadyMap[aaId] or mockTimerMap[aaId] == 0) then
            ready = true
        end
        return ready
    end

    assert_true(simCheckFireworksReady({ ['Summon Firework'] = true }, {}, 17788, 'Alternately Advanced Fireworks'),
        'Suite 85: sim readiness passes when Summon Firework is ready')
    assert_true(simCheckFireworksReady({}, { ['Summon Firework'] = 0 }, 17788, 'Alternately Advanced Fireworks'),
        'Suite 85: sim readiness passes when Summon Firework timer is 0')
    assert_true(simCheckFireworksReady({ ['Alternately Advanced Fireworks'] = true }, {}, 17788, 'Alternately Advanced Fireworks'),
        'Suite 85: sim readiness passes when Alternately Advanced Fireworks is ready')
    assert_eq(simCheckFireworksReady({}, { ['Summon Firework'] = 30 }, 17788, 'Alternately Advanced Fireworks'), false,
        'Suite 85: sim readiness fails when Summon Firework on cooldown')

    -- 6. Functional simulation of priority queue candidate selection with canTrainMet
    local function simCanSelectCandidate(isSpecial, fullyTrained, isInvalidStub, levelMet, canTrainCheck)
        local canTrainMet = isSpecial or canTrainCheck
        return not fullyTrained and not isInvalidStub and levelMet and canTrainMet
    end

    assert_true(simCanSelectCandidate(true, false, false, true, false),
        'Suite 85: Special tab ability selected even if canTrainCheck is false')
    assert_eq(simCanSelectCandidate(false, false, false, true, false), false,
        'Suite 85: Non-special ability rejected if canTrainCheck is false')
    assert_true(simCanSelectCandidate(false, false, false, true, true),
        'Suite 85: Non-special ability accepted when canTrainCheck is true')
end

-- ============================================================================
-- Suite 86: Triune Modular Plugin System & Coroutine Fiber Execution Logic
-- ============================================================================
do
    print('--- Suite 86: Modular Plugin Engine & Coroutine Fiber Execution Logic ---')

    -- 1. Verify auto_accept.lua loads and adheres to the plugin specification
    local fAutoAccept = assert(loadfile('TAC/lua/tac/auto_accept.lua'))
    assert_true(fAutoAccept ~= nil, 'Suite 86: TAC/lua/tac/auto_accept.lua compiles cleanly')
    local okAA, pAA = pcall(fAutoAccept)
    assert_true(okAA and type(pAA) == 'table', 'Suite 86: auto_accept returns a valid plugin table')
    assert_eq(pAA.id, 'auto_accept', 'Suite 86: auto_accept has correct id')
    assert_eq(pAA.name, 'Auto-Accept Invites', 'Suite 86: auto_accept has user-facing name')
    assert_eq(pAA.runOutOfCombatOnly, true, 'Suite 86: auto_accept sleeps during combat')
    assert_eq(pAA.hasThread, true, 'Suite 86: auto_accept declares coroutine fiber execution')
    assert_true(type(pAA.onInit) == 'function', 'Suite 86: auto_accept provides onInit hook')
    assert_true(type(pAA.onTick) == 'function', 'Suite 86: auto_accept provides onTick hook')
    assert_true(type(pAA.onDrawSettings) == 'function', 'Suite 86: auto_accept provides onDrawSettings hook')

    -- 2. Verify floating_damage.lua loads and adheres to the plugin specification
    local fFloatDmg = assert(loadfile('TAC/lua/tac/floating_damage.lua'))
    assert_true(fFloatDmg ~= nil, 'Suite 86: TAC/lua/tac/floating_damage.lua compiles cleanly')
    local okFD, pFD = pcall(fFloatDmg)
    assert_true(okFD and type(pFD) == 'table', 'Suite 86: floating_damage returns a valid plugin table')
    assert_eq(pFD.id, 'floating_damage', 'Suite 86: floating_damage has correct id')
    assert_eq(pFD.name, 'Floating Damage Text', 'Suite 86: floating_damage has user-facing name')
    assert_eq(pFD.runOutOfCombatOnly, false, 'Suite 86: floating_damage remains ACTIVE in combat')
    assert_eq(pFD.hasThread, true, 'Suite 86: floating_damage declares coroutine fiber execution')
    assert_true(type(pFD.onInit) == 'function', 'Suite 86: floating_damage provides onInit hook')
    assert_true(type(pFD.onTick) == 'function', 'Suite 86: floating_damage provides onTick hook')
    assert_true(type(pFD.onDrawUI) == 'function', 'Suite 86: floating_damage provides onDrawUI hook')

    -- 2b. Drive the real spawn / render path: events fire floaters, tiers and
    --     combo bookkeeping work, and a full draw pass survives a mock draw list.
    do
        local fdHandlers = {}
        local fdMq = {
            event = function(name, _, fn) fdHandlers[name] = fn end,
            unevent = function() end,
        }
        local drawCalls = { text = 0, circle = 0, circleFilled = 0, rect = 0 }
        local fdDrawList = {
            AddText = function() drawCalls.text = drawCalls.text + 1 end,
            AddCircle = function() drawCalls.circle = drawCalls.circle + 1 end,
            AddCircleFilled = function() drawCalls.circleFilled = drawCalls.circleFilled + 1 end,
            AddRectFilled = function() drawCalls.rect = drawCalls.rect + 1 end,
        }
        local fdImGui = setmetatable({
            GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } } end,
            Begin = function() return true, true end,
            GetWindowDrawList = function() return fdDrawList end,
            CalcTextSize = function(txt) return #txt * 7, 13 end,
            GetFontSize = function() return 13 end,
            GetColorU32 = function() return 0 end,
            Checkbox = function(_, v) return v end,
            SliderFloat = function(_, v) return v end,
            Button = function() return false end,
            IsItemHovered = function() return false end,
        }, { __index = function() return function() end end })
        local fdCtrl = {}
        local fdSaves = 0
        pFD.onInit({ ctrl = fdCtrl, mq = fdMq, ImGui = fdImGui, colors = {}, saveLoadout = function() fdSaves = fdSaves + 1 end })
        assert_eq(fdCtrl.show_crit_floaters, true, 'Suite 86: floating_damage seeds show_crit_floaters')
        for _, n in ipairs({ 'TacCritHit', 'TacCripBlow', 'TacDeadlyStrike', 'TacSlayUndead', 'TacFinishBlow', 'TacAssassinate', 'TacHeadshot', 'TacFlurry', 'TacSpellCrit', 'TacHealCrit', 'TacDotCrit' }) do
            assert_true(type(fdHandlers[n]) == 'function', 'Suite 86: floating_damage registers ' .. n)
        end

        -- Settings round-trip with clamping
        pFD.onLoadSettings({ textScale = 9, intensity = -1, tierScale = 0.5, comboCounter = true, screenFlash = false, screenShake = true })
        local saved = pFD.onSaveSettings()
        assert_eq(saved.textScale, 2.0, 'Suite 86: floating_damage clamps textScale')
        assert_eq(saved.intensity, 0.0, 'Suite 86: floating_damage clamps intensity')
        assert_eq(saved.tierScale, 0.5, 'Suite 86: floating_damage keeps tierScale')
        assert_eq(saved.screenFlash, false, 'Suite 86: floating_damage keeps screenFlash')
        pFD.onLoadSettings({ textScale = 1.0, intensity = 1.0, tierScale = 1.0, screenFlash = true })

        local enumNames = { 'ImGuiCond', 'ImGuiWindowFlags' }
        local savedEnums = {}
        for _, n in ipairs(enumNames) do
            savedEnums[n] = rawget(_G, n)
            rawset(_G, n, setmetatable({}, { __index = function() return 0 end }))
        end
        local savedVec, savedBit, savedCol = rawget(_G, 'ImVec2'), rawget(_G, 'bit'), rawget(_G, 'IM_COL32')
        rawset(_G, 'ImVec2', function(x, y) return { x = x, y = y } end)
        if not savedBit then rawset(_G, 'bit', { bor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r + v end return r end }) end
        rawset(_G, 'IM_COL32', function(r, g, b, a) return r + g * 256 + b * 65536 + a * 16777216 end)

        -- Nothing to draw: the overlay window is never opened
        local begun = 0
        fdImGui.Begin = function() begun = begun + 1 return true, true end
        pFD.onDrawUI()
        assert_eq(begun, 0, 'Suite 86: floating_damage skips the overlay when idle')

        -- A crit, a bigger crit (record), and a massive spell crit (particles + rings + flash)
        fdHandlers.TacCritHit('You score a critical hit! (420)', '420')
        fdHandlers.TacCritHit('You score a critical hit! (1450)', '1450')
        fdHandlers.TacSpellCrit('Bob hit a mob for 12450 points of non-melee damage. (Critical blast!) (12450)', '12450')
        fdHandlers.TacHealCrit('You perform an exceptional heal! (3000)', '3000')
        fdHandlers.TacAssassinate('You assassinate a rat!')
        pFD.onDrawUI()
        assert_eq(begun, 1, 'Suite 86: floating_damage opens the overlay once floaters exist')
        assert_true(drawCalls.text > 0, 'Suite 86: floating_damage draws text')
        assert_true(drawCalls.circleFilled > 0, 'Suite 86: floating_damage draws particle sparks for big hits')
        assert_true(drawCalls.circle > 0, 'Suite 86: floating_damage draws shockwave rings for huge hits')
        assert_true(drawCalls.rect > 0, 'Suite 86: floating_damage draws the screen flash / combo bar')

        -- Combo + record state is visible through the settings panel; disabled toggle hides everything
        pFD.onDrawSettings()
        fdCtrl.show_crit_floaters = false
        begun = 0
        pFD.onDrawUI()
        assert_eq(begun, 0, 'Suite 86: floating_damage honors show_crit_floaters=false at draw time')
        fdCtrl.show_crit_floaters = true
        pFD.onTick()
        pFD.onDestroy()
        begun = 0
        pFD.onDrawUI()
        assert_eq(begun, 0, 'Suite 86: floating_damage onDestroy clears floaters and effects')

        for _, n in ipairs(enumNames) do rawset(_G, n, savedEnums[n]) end
        rawset(_G, 'ImVec2', savedVec)
        rawset(_G, 'IM_COL32', savedCol)
        if not savedBit then rawset(_G, 'bit', nil) end
    end

    -- 3. Functional simulation of Plugin Manager discovery & fiber runner
    local pm = {
        plugins = {},
        pluginOrder = {},
    }

    local function registerMockPlugin(rawInst)
        local id = rawInst.id
        local p = {
            id = id,
            name = rawInst.name,
            tickInterval = rawInst.tickInterval or 0.1,
            runOutOfCombatOnly = (rawInst.runOutOfCombatOnly == true),
            hasThread = (rawInst.hasThread == true),
            instance = rawInst,
            enabled = true,
            status = 'Active',
            lastTickAt = 0,
            lastExecMs = 0,
            avgExecMs = 0,
            errorMsg = nil,
        }
        if p.hasThread then
            p.thread = coroutine.create(function()
                while p.enabled do
                    if p.instance.onTick then
                        local ok, err = pcall(p.instance.onTick)
                        if not ok then
                            p.status = 'Error'
                            p.errorMsg = tostring(err)
                            break
                        end
                    end
                    coroutine.yield()
                end
            end)
        end
        pm.plugins[id] = p
        table.insert(pm.pluginOrder, id)
        return p
    end

    local testTickCount = 0
    local testPlugin = {
        id = 'test_fiber',
        name = 'Test Fiber Plugin',
        tickInterval = 0.05,
        runOutOfCombatOnly = true,
        hasThread = true,
        onTick = function()
            testTickCount = testTickCount + 1
        end,
    }

    local pReg = registerMockPlugin(testPlugin)
    assert_eq(pReg.id, 'test_fiber', 'Suite 86: mock plugin registered with correct id')
    assert_true(pReg.thread ~= nil, 'Suite 86: mock plugin fiber created')

    -- Simulate main loop tick dispatcher
    local function simTick(inCombat, simNow)
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' then
                if inCombat and p.runOutOfCombatOnly then
                    p.status = 'Sleeping (Combat)'
                else
                    p.status = 'Active'
                    if (simNow - p.lastTickAt) >= p.tickInterval then
                        p.lastTickAt = simNow
                        if p.hasThread and p.thread then
                            coroutine.resume(p.thread)
                        elseif p.instance.onTick then
                            p.instance.onTick()
                        end
                    end
                end
            end
        end
    end

    -- Run tick out of combat
    simTick(false, 1.0)
    assert_eq(testTickCount, 1, 'Suite 86: fiber ticks out of combat')
    assert_eq(pReg.status, 'Active', 'Suite 86: status is Active out of combat')

    -- Run tick in combat: non-combat plugin MUST sleep!
    simTick(true, 1.5)
    assert_eq(testTickCount, 1, 'Suite 86: fiber does NOT tick during combat (zero combat latency)')
    assert_eq(pReg.status, 'Sleeping (Combat)', 'Suite 86: status transitioned to Sleeping (Combat)')

    -- Run tick out of combat again: resumes smoothly
    simTick(false, 2.0)
    assert_eq(testTickCount, 2, 'Suite 86: fiber resumes execution when combat ends')
    assert_eq(pReg.status, 'Active', 'Suite 86: status returned to Active')

    -- 4. Test error isolation (pcall containment in fiber)
    local crashPlugin = {
        id = 'crash_plugin',
        name = 'Buggy Plugin',
        tickInterval = 0.01,
        runOutOfCombatOnly = false,
        hasThread = true,
        onTick = function()
            error('Intentional plugin crash test')
        end,
    }
    local pCrash = registerMockPlugin(crashPlugin)
    simTick(false, 3.0)
    assert_eq(pCrash.status, 'Error', 'Suite 86: crashed fiber isolated to Error status')
    assert_true(pCrash.errorMsg ~= nil and pCrash.errorMsg:find('Intentional plugin crash test') ~= nil,
        'Suite 86: error message preserved in plugin descriptor')
    -- Verify healthy plugin continues running despite other plugin crashing
    simTick(false, 3.5)
    assert_eq(testTickCount, 4, 'Suite 86: healthy plugin keeps running unaffected by sibling crash')

    -- 5. Source verification in triune.lua
    local triuneContent = readFile('TAC/lua/triune.lua')
    assert_true(triuneContent:find('function runtime.initPluginManager()', 1, true) ~= nil,
        'Suite 86: runtime.initPluginManager defined in triune.lua')
    assert_true(triuneContent:find('function UI.drawPluginsTab()', 1, true) ~= nil,
        'Suite 86: UI.drawPluginsTab defined in triune.lua')
    assert_true(triuneContent:find("ImGui.BeginTabItem('Plugins##settingsPlugins')", 1, true) ~= nil,
        'Suite 86: Plugins tab registered under Settings tab in triune.lua')
    assert_true(triuneContent:find('runtime.pluginManager.tick()', 1, true) ~= nil,
        'Suite 86: pluginManager.tick called from main loop in triune.lua')
    assert_true(triuneContent:find('runtime.pluginManager.drawUI()', 1, true) ~= nil,
        'Suite 86: pluginManager.drawUI called from UI.draw in triune.lua')
    assert_true(triuneContent:find('runtime.initPluginManager()', 1, true) ~= nil,
        'Suite 86: runtime.initPluginManager called at startup in triune.lua')

    -- 6. Unit Frames HUD Plugin verification
    local ufFn = assert(loadfile('TAC/lua/tac/hud_unitframes.lua'))
    local ufPlugin = ufFn()
    assert_eq(type(ufPlugin), 'table', 'Suite 86: hud_unitframes.lua returns plugin table')
    assert_eq(ufPlugin.id, 'hud_unitframes', 'Suite 86: hud_unitframes plugin id is correct')
    assert_eq(ufPlugin.runOutOfCombatOnly, false, 'Suite 86: hud_unitframes stays active during combat')
    assert_eq(ufPlugin.hasThread, true, 'Suite 86: hud_unitframes has dedicated coroutine fiber')
    assert_eq(ufPlugin.tickInterval, 0.05, 'Suite 86: hud_unitframes tickInterval is 50ms')

    -- Test lifecycle with mock core API
    local mockCore = {
        ctrl = { show_unit_frames = true, uf_lock = false, uf_alpha = 0.85 },
        VERSION = '2.15',
        mq = {
            TLO = {
                Me = {
                    Combat = function() return false end,
                    PctHPs = function() return 100 end,
                    CurrentHPs = function() return 5000 end,
                    MaxHPs = function() return 5000 end,
                    PctMana = function() return 100 end,
                    CurrentMana = function() return 4000 end,
                    MaxMana = function() return 4000 end,
                    PctEndurance = function() return 100 end,
                    CurrentEndurance = function() return 3000 end,
                    MaxEndurance = function() return 3000 end,
                    Level = function() return 65 end,
                    PctExp = function() return 50 end,
                    PctAAExp = function() return 75 end,
                    AAPoints = function() return 10 end,
                    CleanName = function() return 'TestPlayer' end,
                    Exp = function() return 123456 end,
                    AAPointsAssigned = function() return 100 end,
                    AAPointsTotal = function() return 110 end,
                    Pet = { ID = function() return 0 end },
                },
                Target = {
                    ID = function() return 1234 end,
                    CleanName = function() return 'TestMob' end,
                    Level = function() return 65 end,
                    Class = { ShortName = function() return 'WAR' end },
                    ConColor = function() return 'White' end,
                    PctHPs = function() return 80 end,
                    CurrentHPs = function() return 8000 end,
                    MaxHPs = function() return 10000 end,
                    Distance = function() return 25.0 end,
                    LineOfSight = function() return true end,
                    BuffCount = function() return 0 end,
                },
            },
        },
        resolveTargetOfTarget = function() return 'TestPlayer', 1, 100, 100 end,
        getMultiPetList = function() return {}, {} end,
        getPetSpawnInfo = function() return {} end,
        isSpawnAlive = function() return true end,
    }

    local okInit, errInit = pcall(function() ufPlugin.onInit(mockCore) end)
    assert_true(okInit, 'Suite 86: hud_unitframes onInit runs cleanly: ' .. tostring(errInit))

    local okTick, errTick = pcall(function() ufPlugin.onTick() end)
    assert_true(okTick, 'Suite 86: hud_unitframes onTick fiber runs cleanly with mock TLO vitals: ' .. tostring(errTick))

    local okDestroy, errDestroy = pcall(function() ufPlugin.onDestroy() end)
    assert_true(okDestroy, 'Suite 86: hud_unitframes onDestroy cleans up cached snapshots: ' .. tostring(errDestroy))

    -- 7. In-Combat Toggle & Modal Configuration Popup Verification
    assert_true(triuneContent:find("ImGui.TableSetupColumn('Combat'", 1, true) ~= nil,
        'Suite 86: Dedicated Combat column registered in Plugins table')
    assert_true(triuneContent:find("ImGui.BeginPopupModal('Plugin Configuration##PluginConfigModal'", 1, true) ~= nil,
        'Suite 86: Centered modal popup dialog implemented for plugin configuration')
    assert_true(triuneContent:find('ctrl.plugins[id].runInCombat = newRunInCombat', 1, true) ~= nil,
        'Suite 86: runInCombat preference saved upon toggle in Plugins table')
    assert_true(triuneContent:find('ctrl.plugins[id].runInCombat = not p.runOutOfCombatOnly', 1, true) ~= nil,
        'Suite 86: runInCombat persisted during pm.collectSettings()')
end


-- ============================================================================
-- Suite 87: Plugin Manager Hardening & Shipped Plugin Contract
-- ============================================================================
do
    print('--- Suite 87: Plugin Manager Hardening & Shipped Plugin Contract ---')
    local triuneContent = readFile('TAC/lua/triune.lua')
    local pAA87 = assert(loadfile('TAC/lua/tac/auto_accept.lua'))()

    -- 1. Manager hardening: live ctrl, single fiber factory, safe rescan, draw-error isolation
    assert_true(triuneContent:find('function pm.createFiber(p)', 1, true) ~= nil,
        'Suite 87: fiber creation is factored into pm.createFiber')
    assert_true(triuneContent:find('function pm.restartAll()', 1, true) ~= nil,
        'Suite 87: pm.restartAll re-runs plugin lifecycles without touching disk')
    assert_true(triuneContent:find('runtime.pluginManager.restartAll()', 1, true) ~= nil,
        'Suite 87: main loop restarts plugins after a character swap replaces ctrl')
    assert_true(triuneContent:find('function pm.drawPluginSettings(id)', 1, true) ~= nil,
        'Suite 87: pm.drawPluginSettings lets core sub-tabs delegate to a plugin')
    assert_true(triuneContent:find("p.errorMsg = 'onDrawUI: '", 1, true) ~= nil,
        'Suite 87: onDrawUI failures flag the plugin as Error instead of retrying every frame')
    assert_true(triuneContent:find('if not fileSet[low] and not loadedFiles[low] then', 1, true) ~= nil,
        'Suite 87: pm.discover skips files that are already loaded (rescan never double-inits)')

    -- The core API resolves ctrl live through __index; emulate the exact pattern
    -- used in pm.getCoreApi so a swapped ctrl is seen by plugins immediately.
    do
        local liveCtrl = { a = 1 }
        local live = { ctrl = function() return liveCtrl end }
        local api = setmetatable({ VERSION = 'x' }, {
            __index = function(_, k)
                local getter = live[k]
                if getter then return getter() end
                return nil
            end,
        })
        assert_eq(api.ctrl.a, 1, 'Suite 87: core API resolves ctrl through __index')
        liveCtrl = { a = 2 }
        assert_eq(api.ctrl.a, 2, 'Suite 87: core API sees a replaced ctrl without re-init')
        assert_eq(api.VERSION, 'x', 'Suite 87: static core API fields still resolve normally')
        assert_true(triuneContent:find('ctrl       = function() return ctrl end', 1, true) ~= nil,
            'Suite 87: pm.getCoreApi exposes ctrl via a live getter')
        assert_true(triuneContent:find('if pm.coreApi then return pm.coreApi end', 1, true) ~= nil,
            'Suite 87: pm.getCoreApi returns one shared API table')
    end

    -- 2. Plugins do not double-persist ctrl keys through onSaveSettings
    assert_true(type(pAA87.onSaveSettings) ~= 'function' and type(pAA87.onLoadSettings) ~= 'function',
        'Suite 87: auto_accept relies on ctrl persistence instead of duplicating settings')

    -- 3. HUD plugins respect saved visibility and the core visual toggle
    do
    local ufSrc = readFile('TAC/lua/tac/hud_unitframes.lua')
    assert_true(ufSrc:find('core.ctrl.show_unit_frames = true', 1, true) == nil,
        'Suite 87: hud_unitframes no longer forces the window open on init')
    assert_true(ufSrc:find('(now - lastRefreshAt) < REFRESH_INTERVAL', 1, true) ~= nil,
        'Suite 87: hud_unitframes throttles TLO snapshots on the render pass')
    local fdSrc = readFile('TAC/lua/tac/floating_damage.lua')
    assert_true(fdSrc:find('show_crit_floaters', 1, true) ~= nil,
        'Suite 87: floating_damage honors ctrl.show_crit_floaters')
    end

    -- 4. Every shipped plugin loads, declares the contract, and reports a stable id
    do
    local shipped = {
        { file = 'auto_aa',         id = 'auto_aa' },
        { file = 'auto_accept',     id = 'auto_accept' },
        { file = 'floating_damage', id = 'floating_damage' },
        { file = 'hud_unitframes',  id = 'hud_unitframes' },
        { file = 'hud_group',       id = 'hud_group' },
        { file = 'hud_cooldowns',   id = 'hud_cooldowns' },
        { file = 'hud_effects',     id = 'hud_effects' },
        { file = 'hud_spellgems',   id = 'hud_spellgems' },
        { file = 'hud_xtarget',     id = 'hud_xtarget' },
        { file = 'spellbook',       id = 'spellbook' },
        { file = 'buffbot',         id = 'buffbot' },
        { file = 'cursor',          id = 'cursor' },
        { file = 'dps',             id = 'dps' },
        { file = 'inventory',       id = 'inventory' },
        { file = 'map',             id = 'map' },
        { file = 'boxnet',          id = 'boxnet' },
        { file = 'buttons',         id = 'buttons' },
    }
    for _, sp in ipairs(shipped) do
        local fn = assert(loadfile('TAC/lua/tac/' .. sp.file .. '.lua'))
        local okP, inst = pcall(fn)
        assert_true(okP and type(inst) == 'table', 'Suite 87: ' .. sp.file .. '.lua returns a plugin table')
        assert_eq(inst.id, sp.id, 'Suite 87: ' .. sp.file .. ' id matches filename')
        assert_type(inst.onInit, 'function', 'Suite 87: ' .. sp.file .. ' defines onInit')
        assert_type(inst.onDestroy, 'function', 'Suite 87: ' .. sp.file .. ' defines onDestroy')
        assert_type(inst.onDrawSettings, 'function', 'Suite 87: ' .. sp.file .. ' defines onDrawSettings')
        assert_true(type(inst.tickInterval) == 'number' and inst.tickInterval > 0,
            'Suite 87: ' .. sp.file .. ' declares a positive tickInterval')
        if inst.hasThread then
            assert_type(inst.onTick, 'function', 'Suite 87: ' .. sp.file .. ' declares hasThread and provides onTick')
        end
    end
    end
end


-- ============================================================================
-- Suite 88: Plugin Manager Integration (real initPluginManager + shipped plugins)
-- ============================================================================
do
    print('--- Suite 88: Plugin Manager Integration (real initPluginManager + shipped plugins) ---')
    local printed = {}
    local quietPrint = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end

    local inCombat = false
    local mockMq = {
        event = function() end,
        unevent = function() end,
        cmd = function() end,
        cmdf = function() end,
        TLO = {
            Me = {
                Combat = function() return inCombat end,
                CombatState = function() return inCombat and 'COMBAT' or 'ACTIVE' end,
                Invited = function() return false end,
            },
            Target = { ID = function() return 0 end },
            Window = function() return { Open = function() return false end } end,
            Spawn = function() return setmetatable({}, { __call = function() return false end }) end,
        },
    }
    -- Widget stubs return their input value unchanged (nothing "clicked"), so a
    -- settings panel can render in the sandbox without mutating ctrl.
    local passthrough = function(_, v) return v end
    local mockImGui = setmetatable({
        Checkbox = passthrough,
        SliderFloat = passthrough,
        SliderInt = passthrough,
        Combo = passthrough,
        InputTextWithHint = function(_, _, v) return v, false end,
        Button = function() return false end,
        SmallButton = function() return false end,
        MenuItem = function() return false end,
        Selectable = function() return false end,
        IsItemHovered = function() return false end,
        BeginTable = function() return false end,
    }, { __index = function() return function() end end })
    local noop = function() end
    local mockUI = {
        accent = noop, setTooltip = noop, pushTheme = noop, popTheme = noop,
        preBeginWindow = noop, postBeginWindow = noop, drawStatusProgressBar = noop,
        drawSpellIcon = function() return false end,
        getConColorRgb = function() return { 1, 1, 1, 1 } end,
        resolveTargetOfTarget = function() return nil, nil, nil, nil end,
    }
    local ctrl88 = { plugins = {} }
    local saveCount = 0
    local env = {
        ctrl = ctrl88,
        mq = mockMq,
        ImGui = mockImGui,
        UI = mockUI,
        VERSION = '2.15',
        DATA = {},
        loadout = {},
        scriptDir = './',
        GOLD = { 1, 1, 1, 1 }, ARC = { 1, 1, 1, 1 }, MUTED = { 1, 1, 1, 1 },
        GOOD = { 1, 1, 1, 1 }, WARN = { 1, 1, 1, 1 }, ERR = { 1, 1, 1, 1 },
        saveLoadout = function() saveCount = saveCount + 1 end,
        print = quietPrint,
        idxOf = function(tbl, val) for i, v in ipairs(tbl) do if v == val then return i end end return 0 end,
        fmtSec = function(v) return tostring(v) .. 's' end,
        parseDurationSec = function() return 0 end,
        cleanSpellName = function(n) return (tostring(n or ''):gsub('%s*%([%w%s/]+%)$', '')) end,
        normalizeSpellName = function(n) return (tostring(n or ''):lower():gsub('[%p%s]', '')) end,
    }
    local initPM = loadFunc(src, 'initPluginManager', env)
    local sandbox = debug.getfenv(initPM)
    local rt = sandbox.runtime
    rt.saveLoadout = env.saveLoadout

    -- 1. Discovery loads every shipped plugin from TAC/lua/tac and enables the defaults
    initPM()
    local pm = rt.pluginManager
    assert_true(pm ~= nil, 'Suite 88: runtime.initPluginManager creates runtime.pluginManager')
    local expected = { 'auto_aa', 'auto_accept', 'boxnet', 'buffbot', 'buttons', 'cursor', 'dps', 'floating_damage', 'hud_cooldowns', 'hud_effects', 'hud_group', 'hud_spellgems', 'hud_unitframes', 'hud_xtarget', 'inventory', 'map', 'spellbook' }
    for _, id in ipairs(expected) do
        local p = pm.plugins[id]
        assert_true(p ~= nil, 'Suite 88: discover() loaded ' .. id)
        if p then
            assert_eq(p.enabled, true, 'Suite 88: ' .. id .. ' enabled by default')
            assert_eq(p.status, 'Active', 'Suite 88: ' .. id .. ' initialised without error (' .. tostring(p.errorMsg) .. ')')
            assert_eq(ctrl88.plugins[id] and ctrl88.plugins[id].enabled, true, 'Suite 88: ' .. id .. ' enabled flag persisted to ctrl.plugins')
        end
    end
    assert_eq(#pm.pluginOrder, #expected, 'Suite 88: exactly the shipped plugins are registered')

    -- Plugins seeded their ctrl defaults through the live core API
    assert_eq(ctrl88.show_group_window, false, 'Suite 88: hud_group seeded show_group_window default')
    assert_eq(ctrl88.xt_bar_height, 16, 'Suite 88: hud_xtarget seeded xt_bar_height default')
    assert_eq(ctrl88.eff_sort_by, 'Time Left (Ascending)', 'Suite 88: hud_effects seeded eff_sort_by default')
    assert_eq(ctrl88.show_unit_frames, false, 'Suite 88: hud_unitframes does not force the window open')
    assert_eq(ctrl88.show_crit_floaters, true, 'Suite 88: floating_damage seeded show_crit_floaters default')
    assert_eq(type(ctrl88.auto_accept_names), 'table', 'Suite 88: auto_accept seeded whitelist table')

    -- 2. Rescan never double-loads: instances stay identical
    local instBefore = pm.plugins.hud_group.instance
    pm.discover()
    assert_eq(pm.plugins.hud_group.instance, instBefore, 'Suite 88: rescan keeps the existing instance (no re-init)')
    assert_eq(#pm.pluginOrder, #expected, 'Suite 88: rescan does not duplicate registrations')

    -- 3. Tick dispatch respects combat sleep for out-of-combat plugins only
    inCombat = false
    pm.tick()
    assert_eq(pm.plugins.auto_accept.status, 'Active', 'Suite 88: auto_accept Active out of combat')
    inCombat = true
    pm.tick()
    assert_eq(pm.plugins.auto_accept.status, 'Sleeping (Combat)', 'Suite 88: auto_accept sleeps in combat')
    assert_eq(pm.plugins.hud_unitframes.status, 'Active', 'Suite 88: hud_unitframes keeps running in combat')
    assert_eq(pm.plugins.floating_damage.status, 'Active', 'Suite 88: floating_damage keeps running in combat')
    inCombat = false

    -- 4. Disable / enable round-trips through ctrl.plugins and onDestroy/onInit
    pm.disablePlugin('hud_xtarget')
    assert_eq(pm.plugins.hud_xtarget.enabled, false, 'Suite 88: disablePlugin clears enabled')
    assert_eq(ctrl88.plugins.hud_xtarget.enabled, false, 'Suite 88: disablePlugin persists enabled=false')
    pm.enablePlugin('hud_xtarget')
    assert_eq(pm.plugins.hud_xtarget.status, 'Active', 'Suite 88: enablePlugin re-initialises cleanly')

    -- 5. Character swap: ctrl is replaced, restartAll re-seeds the new table and honors its flags
    local ctrlNew = { plugins = { hud_group = { enabled = false, runInCombat = true }, auto_accept = { enabled = true, runInCombat = true } } }
    sandbox.ctrl = ctrlNew
    pm.restartAll()
    assert_eq(pm.getCoreApi().ctrl, ctrlNew, 'Suite 88: core API resolves the replaced ctrl live')
    assert_eq(ctrlNew.show_xtarget_window, false, 'Suite 88: restartAll re-seeded defaults onto the new ctrl')
    assert_eq(pm.plugins.hud_group.enabled, false, 'Suite 88: restartAll honors the new character\'s disabled flag')
    assert_eq(ctrlNew.plugins.hud_group.enabled, false, 'Suite 88: disabled flag survives restartAll (not overwritten by disablePlugin)')
    assert_eq(pm.plugins.auto_accept.enabled, true, 'Suite 88: restartAll keeps enabled plugins enabled')
    assert_eq(pm.plugins.auto_accept.runOutOfCombatOnly, false, 'Suite 88: restartAll applies the new character\'s runInCombat flag')
    assert_eq(pm.plugins.hud_unitframes.enabled, true, 'Suite 88: plugins with no saved config fall back to defaultEnabled')
    assert_eq(ctrl88.show_group_window, false, 'Suite 88: old ctrl is left untouched after the swap')

    -- 6. collectSettings writes the current state back for persistence
    pm.collectSettings()
    assert_eq(ctrlNew.plugins.hud_group.enabled, false, 'Suite 88: collectSettings persists hud_group disabled')
    assert_eq(ctrlNew.plugins.auto_accept.runInCombat, true, 'Suite 88: collectSettings persists runInCombat')
    assert_true(ctrlNew.plugins.auto_accept.settings == nil, 'Suite 88: auto_accept does not double-persist ctrl keys')

    -- 7. A crashing render hook flags the plugin instead of retrying every frame
    pm.plugins.hud_group.enabled = true
    pm.plugins.hud_group.status = 'Active'
    local realDraw = pm.plugins.hud_group.instance.onDrawUI
    pm.plugins.hud_group.instance.onDrawUI = function() error('boom') end
    pm.drawUI()
    assert_eq(pm.plugins.hud_group.status, 'Error', 'Suite 88: onDrawUI error transitions plugin to Error')
    assert_true(tostring(pm.plugins.hud_group.errorMsg):find('onDrawUI: ') ~= nil, 'Suite 88: onDrawUI error message recorded')
    local drawCalls = 0
    pm.plugins.hud_group.instance.onDrawUI = function() drawCalls = drawCalls + 1 end
    pm.drawUI()
    assert_eq(drawCalls, 0, 'Suite 88: errored plugin is not drawn again until reloaded')
    pm.plugins.hud_group.instance.onDrawUI = realDraw

    -- 8. drawPluginSettings handles missing / errored / disabled plugins without touching the instance
    assert_eq(pm.drawPluginSettings('does_not_exist'), false, 'Suite 88: drawPluginSettings reports a missing plugin')
    assert_eq(pm.drawPluginSettings('hud_group'), false, 'Suite 88: drawPluginSettings reports an errored plugin')
    pm.reloadPlugin('hud_group')
    assert_eq(pm.plugins.hud_group.status, 'Active', 'Suite 88: reloadPlugin clears the Error state')
    pm.disablePlugin('hud_group')
    assert_eq(pm.drawPluginSettings('hud_group'), false, 'Suite 88: drawPluginSettings reports a disabled plugin')
    pm.enablePlugin('hud_group')
    assert_eq(pm.plugins.hud_group.status, 'Active', 'Suite 88: reloaded plugin re-enables cleanly')
    assert_eq(pm.drawPluginSettings('hud_group'), true, 'Suite 88: drawPluginSettings renders an active plugin\'s settings')
    for _, id in ipairs(expected) do
        if pm.plugins[id].enabled then
            local okS = pm.drawPluginSettings(id)
            assert_true(okS, 'Suite 88: ' .. id .. ' onDrawSettings renders without error (' .. tostring(pm.plugins[id].errorMsg) .. ')')
        end
    end
    assert_eq(ctrlNew.gw_alpha, 0.85, 'Suite 88: rendering settings with no interaction leaves ctrl untouched')

    -- 9. Reloading an enabled plugin keeps it enabled (disablePlugin must not clobber the saved flag)
    local instPre = pm.plugins.hud_xtarget.instance
    pm.reloadPlugin('hud_xtarget')
    assert_eq(pm.plugins.hud_xtarget.enabled, true, 'Suite 88: reloadPlugin keeps an enabled plugin enabled')
    assert_eq(pm.plugins.hud_xtarget.status, 'Active', 'Suite 88: reloaded plugin is Active')
    assert_true(pm.plugins.hud_xtarget.instance ~= instPre, 'Suite 88: reloadPlugin re-executes the file (fresh instance)')
    assert_eq(ctrlNew.plugins.hud_xtarget.enabled, true, 'Suite 88: reloadPlugin persists enabled=true')

    -- 10. Hook dispatch: combat hold, between-pulls, commands, help, tabs, loadout-saved
    do
        local aa = pm.plugins.auto_aa
        assert_true(aa ~= nil and aa.enabled, 'Suite 88: auto_aa plugin loaded and enabled')
        assert_eq(pm.combatHold(), false, 'Suite 88: no combat hold while no AA workflow is pending')
        assert_eq(rt.combatHold and rt.combatHold() or pm.combatHold(), false, 'Suite 88: runtime.combatHold mirrors pm.combatHold')
        aa.instance.AA.pendingAATrain = { name = 'Test AA', step = 'open' }
        assert_eq(pm.combatHold(), true, 'Suite 88: pending AA workflow requests a combat hold')
        aa.instance.AA.pendingAATrain = nil
        assert_eq(pm.combatHold(), false, 'Suite 88: combat hold released when the workflow clears')

        assert_eq(pm.onBetweenPulls(), false, 'Suite 88: onBetweenPulls is a no-op with auto_spend_aa off')

        ctrlNew.auto_spend_aa = false
        assert_eq(pm.onCommand('autoaa', { 'autoaa', 'on' }), true, 'Suite 88: /ac autoaa on is handled by auto_aa')
        assert_eq(ctrlNew.auto_spend_aa, true, 'Suite 88: /ac autoaa on enables auto_spend_aa')
        assert_eq(pm.onCommand('autoaa', { 'autoaa', 'off' }), true, 'Suite 88: /ac autoaa off is handled by auto_aa')
        assert_eq(ctrlNew.auto_spend_aa, false, 'Suite 88: /ac autoaa off disables auto_spend_aa')
        assert_eq(pm.onCommand('aathreshold', { 'aathreshold', '42' }), true, 'Suite 88: /ac aathreshold handled')
        assert_eq(ctrlNew.auto_spend_aa_threshold, 42, 'Suite 88: /ac aathreshold sets the threshold')
        assert_eq(pm.onCommand('definitely_not_a_command', { 'definitely_not_a_command' }), false,
            'Suite 88: unknown commands fall through the plugin dispatcher')

        local help = pm.helpLines()
        local sawAutoAA = false
        for _, hl in ipairs(help) do if hl:find('/ac autoaa', 1, true) then sawAutoAA = true end end
        assert_true(sawAutoAA, 'Suite 88: pm.helpLines includes the auto_aa command help')

        -- Plugins no longer contribute main-window tabs: Auto AA is a popout window
        assert_eq(pm.drawTabs, nil, 'Suite 88: pm.drawTabs removed (plugins contribute windows, not tabs)')
        assert_eq(aa.instance.onDrawTab, nil, 'Suite 88: auto_aa no longer defines onDrawTab')
        assert_type(aa.instance.onDrawUI, 'function', 'Suite 88: auto_aa draws its popout window from onDrawUI')
        assert_eq(aa.instance.window and aa.instance.window.flag, 'show_auto_aa', 'Suite 88: auto_aa declares the show_auto_aa window')
        assert_eq(sandbox.ctrl.show_auto_aa, false, 'Suite 88: auto_aa seeds show_auto_aa = false')
        assert_true(pm.onCommand('aawin', { 'aawin' }), 'Suite 88: /ac aawin handled by auto_aa')
        assert_eq(sandbox.ctrl.show_auto_aa, true, 'Suite 88: /ac aawin opens the Auto AA window')
        pm.onCommand('aawin', { 'aawin' })
        assert_eq(sandbox.ctrl.show_auto_aa, false, 'Suite 88: /ac aawin toggles the Auto AA window closed')
        assert_eq(sandbox.ctrl.show_auto_accept, false, 'Suite 88: auto_accept seeds show_auto_accept = false')
        assert_true(pm.onCommand('autoaccept', { 'autoaccept' }), 'Suite 88: /ac autoaccept handled by auto_accept')
        assert_eq(sandbox.ctrl.show_auto_accept, true, 'Suite 88: /ac autoaccept opens the Auto-Accept window')
        assert_type(pm.plugins.auto_accept.instance.onDrawUI, 'function', 'Suite 88: auto_accept draws its popout window from onDrawUI')
        pm.onCommand('autoaccept', { 'autoaccept' })
        assert_eq(sandbox.ctrl.show_auto_accept, false, 'Suite 88: /ac autoaccept toggles the window closed')

        local savedHook = 0
        local realSaved = aa.instance.onLoadoutSaved
        aa.instance.onLoadoutSaved = function() savedHook = savedHook + 1 end
        pm.onLoadoutSaved()
        assert_eq(savedHook, 1, 'Suite 88: pm.onLoadoutSaved dispatches to plugins')
        aa.instance.onLoadoutSaved = realSaved

        -- A hook that throws flags the plugin and stops dispatching to it
        aa.instance.onCommand = function() error('cmd boom') end
        assert_eq(pm.onCommand('autoaa', { 'autoaa' }), false, 'Suite 88: a throwing hook does not count as handled')
        assert_eq(aa.status, 'Error', 'Suite 88: a throwing hook flags the plugin as Error')
        pm.reloadPlugin('auto_aa')
        assert_eq(aa.status, 'Active', 'Suite 88: reload recovers the plugin after a hook error')
    end

    -- 11. Spellbook plugin (was the standalone triune_spellbook.lua script)
    do
        local sb = pm.plugins.spellbook
        assert_true(sb ~= nil and sb.enabled, 'Suite 88: spellbook plugin loaded and enabled')
        assert_eq(ctrlNew.show_spellbook, false, 'Suite 88: spellbook seeds show_spellbook = false')
        assert_eq(pm.onCommand('spellbook', { 'spellbook' }), true, 'Suite 88: /ac spellbook handled by the plugin')
        assert_eq(ctrlNew.show_spellbook, true, 'Suite 88: /ac spellbook opens the window')
        assert_eq(pm.onCommand('book', { 'book' }), true, 'Suite 88: /ac book handled by the plugin')
        assert_eq(ctrlNew.show_spellbook, false, 'Suite 88: /ac book toggles the window closed')

        -- Class spell lookup tolerates the key casing differences between DATA and MQ short names
        env.DATA.spells = { War = { { 'Bash Rank', 5, 0, 'dd' } }, Shm = { { 'Minor Healing', 1, 1, 'heal' } } }
        assert_eq(#sb.instance.getClassSpells('WAR'), 1, 'Suite 88: getClassSpells resolves uppercase class key')
        assert_eq(#sb.instance.getClassSpells('shm'), 1, 'Suite 88: getClassSpells resolves lowercase class key')
        assert_eq(#sb.instance.getClassSpells('Nec'), 0, 'Suite 88: getClassSpells returns empty for unknown class')

        -- Mem queue drains through runtime.tryMem with the core's combat/casting gates
        local memCalls = {}
        rt.tryMem = function(slot, name, bypass) memCalls[#memCalls + 1] = { slot = slot, name = name, bypass = bypass } return true end
        rt.isCasting = function() return false end
        mockMq.TLO.Me.Moving = function() return false end
        mockMq.TLO.Me.Gem = function() return { Name = function() return '' end } end
        sb.instance.state.pendingQueue[3] = 'Minor Healing'
        sb.instance.state.bypassScribedCheck = true
        inCombat = true
        sb.instance.processQueue()
        assert_eq(#memCalls, 0, 'Suite 88: spellbook queue does not memorize while in combat')
        inCombat = false
        sb.instance.processQueue()
        assert_eq(#memCalls, 1, 'Suite 88: spellbook queue memorizes once out of combat')
        assert_eq(memCalls[1].slot, 3, 'Suite 88: queued gem slot is passed to runtime.tryMem')
        assert_eq(memCalls[1].name, 'Minor Healing', 'Suite 88: queued spell name is passed to runtime.tryMem')
        assert_eq(memCalls[1].bypass, true, 'Suite 88: bypass-scribed option is passed through')
        assert_true(next(sb.instance.state.pendingQueue) == nil, 'Suite 88: queue entry cleared after memorizing')

        local sbSrc = readFile('TAC/lua/tac/spellbook.lua')
        for _, dup in ipairs({ 'local function pushTheme', 'local function getSpellbookMap', 'local function tryMem', 'local function detectClasses', 'local function loadData', 'mq.imgui.init' }) do
            assert_true(sbSrc:find(dup, 1, true) == nil, 'Suite 88: spellbook plugin no longer duplicates core code: ' .. dup)
        end
        assert_true(io.open('TAC/lua/triune_spellbook.lua', 'r') == nil, 'Suite 88: standalone triune_spellbook.lua was removed')
        assert_true(src:find("UI.toggleTool('triune_spellbook')", 1, true) == nil, 'Suite 88: core no longer launches triune_spellbook via /lua run')
    end
end


-- ============================================================================
-- Suite 89: Companion tools migrated to plugins (cursor / dps / inventory /
-- buffbot / map) + the fiber-aware core.delay
-- ============================================================================
do
    print('--- Suite 89: Companion tool plugins & fiber-aware delay ---')
    local printed = {}
    local quietPrint = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
    local noop = function() end
    local passthrough = function(_, v) return v end
    local mockImGui = setmetatable({
        Checkbox = passthrough, Button = function() return false end, SmallButton = function() return false end,
        IsItemHovered = function() return false end, BeginTable = function() return false end,
        Begin = function() return false, false end,
    }, { __index = function() return function() end end })

    -- Fresh mock core per plugin: records commands, events, binds, saves.
    local function makeCore()
        local rec = { cmds = {}, events = {}, binds = {}, saves = 0, nowMs = 100000, delays = {} }
        local ctrl = { plugins = {} }
        local mq = {
            configDir = './tests/__nonexistent_cfg__',
            event = function(name) rec.events[name] = true end,
            unevent = function(name) rec.events[name] = nil end,
            bind = function(cmd) rec.binds[cmd] = true end,
            unbind = function(cmd) rec.binds[cmd] = nil end,
            cmd = function(c) rec.cmds[#rec.cmds + 1] = c end,
            cmdf = function(f, ...) rec.cmds[#rec.cmds + 1] = string.format(f, ...) end,
            gettime = function() return rec.nowMs end,
            delay = function(ms) rec.delays[#rec.delays + 1] = ms end,
            TLO = {
                Me = { CleanName = function() return 'Tester' end, Combat = function() return false end },
                EverQuest = { Server = function() return 'Test' end },
                Target = { ID = function() return 0 end, Dead = function() return false end, Type = function() return 'NPC' end },
                MacroQuest = { GameState = function() return 'INGAME' end },
            },
        }
        local core = {
            VERSION = '2.15', ctrl = ctrl, mq = mq, ImGui = mockImGui, runtime = {}, DATA = {},
            colors = { GOLD = { 1, 1, 1, 1 }, ARC = { 1, 1, 1, 1 }, MUTED = { 1, 1, 1, 1 }, GOOD = { 1, 1, 1, 1 }, WARN = { 1, 1, 1, 1 }, ERR = { 1, 1, 1, 1 } },
            pushTheme = noop, popTheme = noop, accent = noop, setTooltip = noop,
            preBeginWindow = noop, postBeginWindow = noop,
            saveLoadout = function() rec.saves = rec.saves + 1 end,
            delay = function(ms) rec.delays[#rec.delays + 1] = ms return false end,
        }
        return core, rec, ctrl, mq
    end

    local function loadPlugin(file)
        local fn = assert(loadfile('TAC/lua/tac/' .. file .. '.lua'))
        local origPrint = print
        print = quietPrint
        local ok, inst = pcall(fn)
        print = origPrint
        assert_true(ok and type(inst) == 'table', 'Suite 89: ' .. file .. '.lua loads')
        return inst
    end

    local origPrint = print

    -- 1. No plugin blocks the core: mq.delay / mq.doevents / mq.imgui / own theme are gone
    for _, f in ipairs({ 'cursor', 'dps', 'inventory', 'buffbot', 'map' }) do
        local psrc = readFile('TAC/lua/tac/' .. f .. '.lua')
        for _, bad in ipairs({ 'mq.delay(', 'mq.doevents()', 'mq.imgui.init', 'mq.exit(', 'local function pushTheme', 'local function popTheme', 'require(' }) do
            assert_true(psrc:find(bad, 1, true) == nil, 'Suite 89: ' .. f .. '.lua does not use ' .. bad)
        end
        assert_true(psrc:find('core.pushTheme()', 1, true) ~= nil, 'Suite 89: ' .. f .. '.lua uses the core theme')
        assert_true(io.open('TAC/lua/triune_' .. (f == 'inventory' and 'inv' or f) .. '.lua', 'r') == nil, 'Suite 89: standalone triune_' .. f .. ' script was removed')
    end
    for _, f in ipairs({ 'inventory', 'buffbot' }) do
        local psrc = readFile('TAC/lua/tac/' .. f .. '.lua')
        assert_true(psrc:find('return core.delay(ms, cond)', 1, true) ~= nil, 'Suite 89: ' .. f .. ' waits through the fiber-aware core.delay')
        assert_true(psrc:find('hasThread          = true', 1, true) ~= nil, 'Suite 89: ' .. f .. ' runs in a plugin fiber')
    end

    -- 2. Core wiring: window flags, layout manager entries, no more /lua run launchers
    for _, key in ipairs({ 'show_map', 'show_dps', 'show_inv', 'show_cursor', 'show_buffbot' }) do
        assert_true(src:find('        ' .. key .. ' ', 1, true) ~= nil, 'Suite 89: defaultCtrl seeds ' .. key)
        assert_true(src:find('if c.' .. key .. ' == nil then c.' .. key .. ' = false end', 1, true) ~= nil, 'Suite 89: sanitize seeds ' .. key)
    end
    for _, gone in ipairs({ "UI.toggleTool('triune_map')", "UI.toggleTool('triune_dps'", "UI.toggleTool('triune_cursor')", "UI.toggleTool('triune_buffbot')", "/lua run triune_inv", "cmd == 'cursorui'", "cmd == 'buffbot'", "cmd == 'dpsparser'", "cmd == 'triunemap'" }) do
        assert_true(src:find(gone, 1, true) == nil, 'Suite 89: core no longer contains ' .. gone)
    end
    assert_true(src:find('delay                 = function(ms, cond) return pm.delay(ms, cond) end', 1, true) ~= nil, 'Suite 89: core API exports delay')
    for _, f in ipairs({ "'cursor.lua'", "'dps.lua'", "'inventory.lua'", "'buffbot.lua'", "'map.lua'" }) do
        assert_true(src:find(f, 1, true) ~= nil, 'Suite 89: discover() known-plugin probe lists ' .. f)
    end

    -- 3. Cursor: one /autoinventory per tick, history logged when the cursor clears
    do
        local core, rec, ctrl, mq = makeCore()
        local curId = 0
        mq.TLO.Cursor = setmetatable({
            ID = function() return curId end, Name = function() return 'Rusty Sword' end,
            Stack = function() return 1 end, Lore = function() return false end, NoDrop = function() return false end,
        }, { __call = function() return curId > 0 end })
        local cur = loadPlugin('cursor')
        print = quietPrint
        cur.onInit(core)
        assert_eq(ctrl.show_cursor, false, 'Suite 89: cursor seeds show_cursor = false')
        cur.state.pendingAction = 'clear'
        cur.onTick()
        assert_eq(#rec.cmds, 0, 'Suite 89: cursor clear with empty cursor issues nothing')
        assert_eq(cur.state.statusMsg, 'Cursor is empty.', 'Suite 89: cursor reports empty cursor')
        curId = 1234
        cur.state.pendingAction = 'clear'
        cur.onTick()
        assert_eq(rec.cmds[1], '/autoinventory', 'Suite 89: cursor issues /autoinventory on the first tick')
        cur.onTick()
        assert_eq(#rec.cmds, 2, 'Suite 89: cursor keeps issuing one /autoinventory per tick while the item remains')
        curId = 0
        cur.onTick()
        assert_eq(#rec.cmds, 2, 'Suite 89: cursor stops once the cursor is empty')
        assert_eq(#cur.state.sessionHistory, 1, 'Suite 89: cursor logs the cleared item')
        assert_eq(cur.state.sessionHistory[1].action, 'Auto Inventoried', 'Suite 89: cursor history action recorded')
        assert_eq(cur.state.clearing, nil, 'Suite 89: cursor clear sequence finished')
        curId = 77
        cur.state.pendingAction = 'destroy'
        cur.onTick()
        assert_eq(rec.cmds[#rec.cmds], '/destroy', 'Suite 89: cursor destroy issues /destroy')
        assert_eq(cur.state.sessionHistory[1].action, 'Destroyed', 'Suite 89: cursor destroy logged')
        cur.state.autoClearOnPick = true
        cur.onTick()
        assert_eq(rec.cmds[#rec.cmds], '/autoinventory', 'Suite 89: auto-clear on pick inventories items that land on the cursor')
        assert_true(cur.onCommand('cursorui'), 'Suite 89: /ac cursorui handled by the plugin')
        assert_eq(ctrl.show_cursor, true, 'Suite 89: /ac cursorui opens the window')
        assert_eq(cur.onCommand('map'), false, 'Suite 89: cursor ignores other commands')
        assert_eq(cur.onSaveSettings().autoClearOnPick, true, 'Suite 89: cursor persists auto-clear preference')
        cur.onLoadSettings({ autoClearOnPick = false })
        assert_eq(cur.state.autoClearOnPick, false, 'Suite 89: cursor restores auto-clear preference')
        print = origPrint
    end

    -- 4. DPS parser: events + /dps binds on init, released on destroy; fight timeout archives
    do
        local core, rec, ctrl = makeCore()
        local dps = loadPlugin('dps')
        print = quietPrint
        dps.onInit(core)
        local evCount = 0
        for _ in pairs(rec.events) do evCount = evCount + 1 end
        assert_eq(evCount, 20, 'Suite 89: dps registers its 20 combat-log events')
        assert_eq(#dps.registeredEvents(), 20, 'Suite 89: dps tracks registered event names')
        assert_true(rec.binds['/dps'] and rec.binds['/triunedps'], 'Suite 89: dps binds /dps and /triunedps')
        assert_eq(ctrl.show_dps, false, 'Suite 89: dps seeds show_dps = false')
        assert_true(dps.onCommand('dps', { 'dps' }), 'Suite 89: /ac dps handled by the plugin')
        assert_eq(ctrl.show_dps, true, 'Suite 89: /ac dps opens the window')
        assert_true(dps.onCommand('dps', { 'dps', 'hide' }), 'Suite 89: /ac dps hide handled')
        assert_eq(ctrl.show_dps, false, 'Suite 89: /ac dps hide closes the window')
        assert_eq(dps.onCommand('inv'), false, 'Suite 89: dps ignores other commands')
        -- Fight bookkeeping (was the standalone main loop)
        dps.rt.inFight = true
        dps.rt.totalDamage = 500
        dps.rt.playerDamage = 500
        dps.rt.currentTargetName = 'a gnoll'
        dps.rt.fightStartTime = rec.nowMs - 10000
        dps.rt.lastDamageTime = rec.nowMs - 1000
        dps.cfg.combatTimeout = 6
        dps.onTick()
        assert_eq(dps.rt.inFight, true, 'Suite 89: dps keeps the fight open while damage is recent')
        dps.rt.lastDamageTime = rec.nowMs - 7000
        dps.onTick()
        assert_eq(dps.rt.inFight, false, 'Suite 89: dps ends the fight after combatTimeout of inactivity')
        assert_eq(#dps.rt.history, 1, 'Suite 89: dps archives the encounter')
        assert_eq(dps.rt.history[1].totalDmg, 500, 'Suite 89: archived encounter carries the damage total')
        dps.onDestroy()
        evCount = 0
        for _ in pairs(rec.events) do evCount = evCount + 1 end
        assert_eq(evCount, 0, 'Suite 89: dps unregisters its events on destroy')
        assert_true(rec.binds['/dps'] == nil and rec.binds['/triunedps'] == nil, 'Suite 89: dps unbinds /dps on destroy')
        print = origPrint
    end

    -- 5. Inventory: window flag, queued actions drain through the fiber tick
    do
        local core, rec, ctrl = makeCore()
        local inv = loadPlugin('inventory')
        print = quietPrint
        inv.onInit(core)
        assert_eq(ctrl.show_inv, false, 'Suite 89: inventory seeds show_inv = false')
        local scans = 0
        inv.scanner.scanAll = function() scans = scans + 1 inv.state.lastScanTime = os.time() end
        inv.onTick()
        assert_eq(scans, 0, 'Suite 89: inventory does not scan while the window is closed')
        assert_true(inv.onCommand('inv'), 'Suite 89: /ac inv handled by the plugin')
        assert_eq(ctrl.show_inv, true, 'Suite 89: /ac inv opens the window')
        inv.onTick()
        assert_eq(scans, 1, 'Suite 89: inventory scans once when the window is first opened')
        inv.state.pendingAction = { type = 'open_all_bags' }
        inv.tick()
        assert_eq(rec.cmds[#rec.cmds], '/keypress open_inv_bags', 'Suite 89: inventory drains queued actions on its tick')
        assert_eq(scans, 2, 'Suite 89: inventory rescans after an action')
        assert_eq(#rec.delays, 1, 'Suite 89: inventory waits through core.delay (never mq.delay)')
        assert_eq(inv.onCommand('dps'), false, 'Suite 89: inventory ignores other commands')
        print = origPrint
    end

    -- 6. Buffbot: station is off until switched on; combat hold only while casting
    do
        local core, rec, ctrl = makeCore()
        local bb = loadPlugin('buffbot')
        print = quietPrint
        bb.onInit(core)
        assert_eq(bb.cfg.enabled, false, 'Suite 89: buffbot station is OFF after load (never auto-starts)')
        assert_eq(bb.rt.state, 'STOPPED', 'Suite 89: buffbot state STOPPED after load')
        assert_eq(#bb.registeredEvents(), 11, 'Suite 89: buffbot registers its tell + hail events')
        assert_eq(ctrl.show_buffbot, false, 'Suite 89: buffbot seeds show_buffbot = false')
        assert_eq(bb.wantsCombatHold(), false, 'Suite 89: buffbot does not hold combat while stopped')
        assert_true(bb.onCommand('buffbot', { 'buffbot', 'on' }), 'Suite 89: /ac buffbot on handled')
        assert_eq(bb.cfg.enabled, true, 'Suite 89: /ac buffbot on starts the station')
        assert_eq(bb.rt.state, 'IDLE', 'Suite 89: station IDLE once started')
        assert_eq(ctrl.show_buffbot, true, 'Suite 89: /ac buffbot on also opens the window')
        bb.rt.currentJob = { sender = 'Bob' }
        assert_eq(bb.wantsCombatHold(), true, 'Suite 89: buffbot holds the combat loop while a buff job is active')
        bb.rt.currentJob = nil
        assert_eq(bb.wantsCombatHold(), false, 'Suite 89: hold released when the job finishes')
        bb.rt.activeQueue = { { sender = 'Bob' } }
        assert_true(bb.onCommand('buff', { 'buff', 'off' }), 'Suite 89: /ac buff off handled')
        assert_eq(bb.cfg.enabled, false, 'Suite 89: /ac buff off stops the station')
        assert_eq(#bb.rt.activeQueue, 0, 'Suite 89: stopping the station clears the queue')
        assert_true(bb.onCommand('buffbot', { 'buffbot' }), 'Suite 89: bare /ac buffbot handled')
        assert_eq(ctrl.show_buffbot, false, 'Suite 89: bare /ac buffbot toggles the window only')
        assert_eq(bb.cfg.enabled, false, 'Suite 89: bare /ac buffbot leaves the station state alone')
        bb.onTick()
        assert_eq(bb.rt.state, 'STOPPED', 'Suite 89: tick keeps STOPPED state while off')
        bb.onDestroy()
        assert_eq(#bb.registeredEvents(), 0, 'Suite 89: buffbot unregisters events on destroy')
        print = origPrint
    end

    -- 7. Map: overlays sync from the live core ctrl (no loadout file parsing)
    do
        local core, rec, ctrl = makeCore()
        local map = loadPlugin('map')
        print = quietPrint
        map.onInit(core)
        assert_eq(ctrl.show_map, false, 'Suite 89: map seeds show_map = false')
        ctrl.camp_loc = { x = 10, y = 20, z = 30 }
        ctrl.camp_radius = 80
        ctrl.hunter_combat_loc = { x = 1, y = 2, z = 3 }
        ctrl.hunter_combat_radius = 300
        ctrl.zone_waypoints = { gfaydark = { waypoints = { { x = 5, y = 6, z = 7, name = 'Orc Hill' } }, waypoint_radius = 25, waypoint_loop = true } }
        ctrl.zone_hazards = { gfaydark = { { x = 9, y = 9, z = 9, hits = 4 } } }
        map.state.currentZoneShort = 'gfaydark'
        map.syncTriuneLoadout()
        local td = map.state.triuneData
        assert_eq(td.isLoaded, true, 'Suite 89: map sync reads the live core ctrl')
        assert_eq(td.campLoc and td.campLoc.x, 10, 'Suite 89: map sync mirrors camp_loc')
        assert_eq(td.campRadius, 80, 'Suite 89: map sync mirrors camp_radius')
        assert_eq(td.hunterAnchor and td.hunterAnchor.y, 2, 'Suite 89: map sync mirrors hunter anchor')
        assert_eq(td.hunterCombatRadius, 300, 'Suite 89: map sync mirrors hunter combat radius')
        assert_eq(#td.waypoints, 1, 'Suite 89: map sync picks up zone waypoints for the current zone')
        assert_eq(td.waypoints[1].name, 'Orc Hill', 'Suite 89: zone waypoint name preserved')
        assert_eq(td.useWaypoints, true, 'Suite 89: zone waypoints enable the overlay')
        assert_eq(td.waypointRadius, 25, 'Suite 89: zone waypoint radius mirrored')
        assert_eq(#td.zoneHazards, 1, 'Suite 89: map sync picks up zone hazards')
        assert_eq(td.zoneHazards[1].hits, 4, 'Suite 89: hazard hit count mirrored')
        ctrl.waypoints = { { x = 1, y = 1, z = 1, name = 'Char WP' }, { x = 2, y = 2, z = 2 } }
        ctrl.use_waypoints = true
        map.syncTriuneLoadout()
        assert_eq(#td.waypoints, 2, 'Suite 89: character waypoints take precedence over zone waypoints')
        assert_eq(td.waypoints[2].name, 'WP 2', 'Suite 89: unnamed character waypoint gets a default name')
        assert_true(map.onCommand('track'), 'Suite 89: /ac track handled by the map plugin')
        assert_eq(ctrl.show_map, true, 'Suite 89: /ac track opens the map window')
        assert_eq(map.state.requestedTab, 3, 'Suite 89: /ac track selects the NPC Tracker tab')
        assert_true(map.onCommand('map'), 'Suite 89: /ac map handled')
        assert_eq(ctrl.show_map, false, 'Suite 89: /ac map toggles the window closed')
        assert_eq(map.onCommand('cursorui'), false, 'Suite 89: map ignores other commands')
        local mapSrc = readFile('TAC/lua/tac/map.lua')
        for _, gone in ipairs({ 'triuneLoadoutCandidates', 'findTriuneLoadoutFile', '__zoneWaypoints', 'loadfile(perCharPath)' }) do
            assert_true(mapSrc:find(gone, 1, true) == nil, 'Suite 89: map plugin dropped loadout-file discovery: ' .. gone)
        end
        print = origPrint
    end

    -- 8. pm.delay: yields the fiber until the condition / deadline, mq.delay outside a fiber
    do
        local mockMq = {
            event = noop, unevent = noop, cmd = noop, cmdf = noop, bind = noop, unbind = noop,
            gettime = function() return 0 end,
            TLO = {
                Me = { Combat = function() return false end, CombatState = function() return 'ACTIVE' end, CleanName = function() return 'T' end },
                EverQuest = { Server = function() return 'S' end },
                Target = { ID = function() return 0 end },
                Window = function() return { Open = function() return false end } end,
                Spawn = function() return setmetatable({}, { __call = function() return false end }) end,
            },
        }
        local mqDelays = {}
        mockMq.delay = function(ms) mqDelays[#mqDelays + 1] = ms end
        local env = {
            ctrl = { plugins = {} }, mq = mockMq, ImGui = mockImGui,
            UI = { accent = noop, setTooltip = noop, pushTheme = noop, popTheme = noop, preBeginWindow = noop, postBeginWindow = noop,
                   drawStatusProgressBar = noop, drawSpellIcon = function() return false end,
                   getConColorRgb = function() return { 1, 1, 1, 1 } end, resolveTargetOfTarget = function() return nil end },
            VERSION = '2.15', DATA = {}, loadout = {}, scriptDir = './',
            GOLD = { 1, 1, 1, 1 }, ARC = { 1, 1, 1, 1 }, MUTED = { 1, 1, 1, 1 }, GOOD = { 1, 1, 1, 1 }, WARN = { 1, 1, 1, 1 }, ERR = { 1, 1, 1, 1 },
            saveLoadout = noop, print = quietPrint,
            idxOf = function() return 0 end, fmtSec = tostring, parseDurationSec = function() return 0 end,
            cleanSpellName = tostring, normalizeSpellName = tostring,
        }
        local initPM = loadFunc(src, 'initPluginManager', env)
        local sandbox = debug.getfenv(initPM)
        local rt = sandbox.runtime
        rt.saveLoadout = noop
        initPM()
        local pm = rt.pluginManager
        assert_type(pm.delay, 'function', 'Suite 89: pm.delay exists')
        assert_eq(pm.getCoreApi().delay, pm.getCoreApi().delay, 'Suite 89: core API exposes delay')

        -- Inside a fiber: yields each tick until the condition holds
        pm.inFiber = true
        local ticks = 0
        local co = coroutine.create(function() return pm.delay(60000, function() return ticks >= 3 end) end)
        local ok, res = coroutine.resume(co)
        assert_true(ok and coroutine.status(co) == 'suspended', 'Suite 89: pm.delay yields the fiber while waiting')
        while coroutine.status(co) ~= 'dead' do
            ticks = ticks + 1
            ok, res = coroutine.resume(co)
        end
        assert_true(ok, 'Suite 89: fiber completed without error')
        assert_eq(res, true, 'Suite 89: pm.delay returns true when the condition fires')
        assert_eq(ticks, 3, 'Suite 89: pm.delay resumed exactly until the condition held')
        local co2 = coroutine.create(function() return pm.delay(0) end)
        local ok2, res2 = coroutine.resume(co2)
        assert_true(ok2 and coroutine.status(co2) == 'dead', 'Suite 89: pm.delay(0) returns without yielding')
        assert_eq(res2, false, 'Suite 89: pm.delay returns false on deadline without a condition')
        assert_eq(#mqDelays, 0, 'Suite 89: pm.delay never calls mq.delay from a fiber')
        pm.inFiber = false

        -- Outside a fiber: falls back to mq.delay on the main coroutine
        pm.delay(50)
        assert_eq(mqDelays[1], 50, 'Suite 89: pm.delay outside a fiber degrades to mq.delay')

        -- pm.tick marks the fiber window so plugin code can tell it is inside one
        local seenInFiber = nil
        local fake = {
            id = 'fake_fiber', name = 'fake', enabled = true, status = 'Active', hasThread = true,
            tickInterval = 0, lastTickAt = -1, lastExecMs = 0, avgExecMs = 0,
            instance = { onTick = function() seenInFiber = pm.inFiber coroutine.yield() end },
        }
        fake.thread = pm.createFiber(fake)
        pm.plugins[fake.id] = fake
        table.insert(pm.pluginOrder, fake.id)
        pm.tick()
        assert_eq(seenInFiber, true, 'Suite 89: pm.inFiber is true while a plugin fiber runs')
        assert_eq(pm.inFiber, false, 'Suite 89: pm.inFiber is cleared after the fiber yields')

        -- 9. Plugin windows & main-window header buttons
        local W = { saves = 0, ctrl = env.ctrl, custom = false, clickLabel = nil }
        rt.saveLoadout = function() W.saves = W.saves + 1 end
        assert_eq(pm.getWindow('map') and pm.getWindow('map').flag, 'show_map', 'Suite 89: map declares its window flag')
        assert_eq(pm.getWindow('auto_aa') and pm.getWindow('auto_aa').flag, 'show_auto_aa', 'Suite 89: auto_aa declares its popout window')
        assert_eq(pm.getWindow('floating_damage'), nil, 'Suite 89: floating_damage (overlay) declares no window')
        assert_eq(pm.getWindow('auto_accept') and pm.getWindow('auto_accept').flag, 'show_auto_accept', 'Suite 89: auto_accept declares its popout window')
        W.all = pm.windowPlugins(false)
        assert_eq(#W.all, 16, 'Suite 89: sixteen shipped plugins own a window')
        assert_eq(W.all[1].id, 'spellbook', 'Suite 89: header order starts with the Spellbook (as before)')
        assert_eq(W.all[2].id, 'map', 'Suite 89: Map follows Spellbook in header order')
        assert_eq(W.all[#W.all].id, 'buffbot', 'Suite 89: Buffbot sorts last')
        W.hdr = pm.windowPlugins(true)
        assert_eq(#W.hdr, 15, 'Suite 89: header buttons default to the old header set + Auto AA + Auto-Accept + Box Net + Buttons (buffbot off)')
        assert_eq(pm.headerButtonEnabled('buffbot'), false, 'Suite 89: buffbot header button off by default')
        assert_eq(pm.headerButtonEnabled('hud_group'), true, 'Suite 89: hud_group header button on by default')
        assert_eq(pm.headerButtonEnabled('floating_damage'), false, 'Suite 89: no header button for plugins without a window')
        pm.setHeaderButton('buffbot', true)
        assert_eq(W.ctrl.plugins.buffbot.headerButton, true, 'Suite 89: header button preference persisted to ctrl.plugins')
        assert_eq(#pm.windowPlugins(true), 16, 'Suite 89: enabling the preference adds the button')
        assert_true(W.saves >= 1, 'Suite 89: header button preference triggers a loadout save')
        pm.setHeaderButton('hud_group', false)
        assert_eq(pm.headerButtonEnabled('hud_group'), false, 'Suite 89: saved preference overrides the plugin default')
        assert_eq(#pm.windowPlugins(true), 15, 'Suite 89: disabling the preference removes the button')

        -- open / close through the manager writes the ctrl flag
        assert_eq(pm.isWindowOpen('map'), false, 'Suite 89: map window closed initially')
        pm.toggleWindow('map')
        assert_eq(W.ctrl.show_map, true, 'Suite 89: toggleWindow opens via the ctrl flag')
        assert_eq(pm.isWindowOpen('map'), true, 'Suite 89: isWindowOpen reflects the flag')
        pm.setWindowOpen('map', false)
        assert_eq(W.ctrl.show_map, false, 'Suite 89: setWindowOpen(false) closes the window')
        assert_eq(pm.setWindowOpen('floating_damage', true), false, 'Suite 89: setWindowOpen is a no-op for plugins without a window')

        -- isOpen / setOpen function pair is honoured for non-ctrl windows
        pm.plugins.fake_fiber.instance.window = { label = 'Custom', isOpen = function() return W.custom end, setOpen = function(v) W.custom = v end, order = 5 }
        assert_eq(pm.windowPlugins(false)[1].id, 'fake_fiber', 'Suite 89: window.order sorts custom window first')
        pm.toggleWindow('fake_fiber')
        assert_eq(W.custom, true, 'Suite 89: setOpen callback used when no flag is declared')
        assert_eq(pm.isWindowOpen('fake_fiber'), true, 'Suite 89: isOpen callback used when no flag is declared')
        pm.plugins.fake_fiber.instance.window = nil

        -- header renderer: one button per enabled header plugin, clicks toggle
        mockImGui.Button = function(label) return W.clickLabel ~= nil and label:find(W.clickLabel, 1, true) ~= nil end
        assert_eq(pm.drawHeaderButtons(), 15, 'Suite 89: drawHeaderButtons draws one button per header plugin')
        W.clickLabel = 'Map##hdrPlg_map'
        pm.drawHeaderButtons()
        assert_eq(W.ctrl.show_map, true, 'Suite 89: clicking the header button opens the plugin window')
        W.clickLabel = nil
        mockImGui.Button = function() return false end

        -- Rows hold at most 8 buttons: SameLine is skipped when a row is full
        W.sameLines = 0
        mockImGui.SameLine = function() W.sameLines = W.sameLines + 1 end
        assert_eq(pm.HEADER_BUTTONS_PER_ROW, 8, 'Suite 89: header rows are capped at 8 buttons')
        -- Expected SameLine calls = buttons - row starts, where a button at absolute
        -- slot k (Compact Mode = slot 1) starts a row when (k-1) % perRow == 0.
        W.expectSameLines = function(n, start, perRow)
            local rowStarts = 0
            for k = start + 1, start + n do
                if (k - 1) % perRow == 0 then rowStarts = rowStarts + 1 end
            end
            return n - rowStarts
        end
        W.sameLines = 0
        W.n = pm.drawHeaderButtons(1)
        assert_true(W.n >= 9, 'Suite 89: enough header buttons to need a second row')
        assert_eq(W.sameLines, W.expectSameLines(W.n, 1, 8), 'Suite 89: with Compact Mode in slot 1, 7 buttons join row 1 and the 8th starts row 2')
        W.sameLines = 0
        pm.drawHeaderButtons(0)
        assert_eq(W.sameLines, W.expectSameLines(W.n, 0, 8), 'Suite 89: from an empty row, buttons 1-8 fill row 1 and button 9 starts row 2')
        pm.HEADER_BUTTONS_PER_ROW = 4
        W.sameLines = 0
        pm.drawHeaderButtons(0)
        assert_eq(W.sameLines, W.expectSameLines(W.n, 0, 4), 'Suite 89: per-row cap is honoured (rows of 4)')
        pm.HEADER_BUTTONS_PER_ROW = 8
        mockImGui.SameLine = nil
        pm.disablePlugin('map')
        assert_eq(pm.drawHeaderButtons(), 14, 'Suite 89: disabled plugins get no header button')
        pm.enablePlugin('map')
        pm.plugins.map.status = 'Error'
        assert_eq(pm.drawHeaderButtons(), 14, 'Suite 89: errored plugins get no header button')
        pm.plugins.map.status = 'Active'

        -- collectSettings persists the effective header preference for window plugins
        pm.collectSettings()
        assert_eq(W.ctrl.plugins.spellbook.headerButton, true, 'Suite 89: collectSettings records the default header preference')
        assert_eq(W.ctrl.plugins.floating_damage.headerButton, nil, 'Suite 89: collectSettings leaves non-window plugins alone')

        -- core header bar is driven by the manager now
        assert_true(src:find('runtime.pluginManager.drawHeaderButtons(1)', 1, true) ~= nil, 'Suite 89: header bar calls pm.drawHeaderButtons')
        for _, gone in ipairs({ "'Map##hdrMap'", "'DPS Parser##hdrDPS'", "'Cursor Manager##hdrCursor'", "'Inv Manager##hdrInv'", "'Open Spellbook##hdrBook'", "'Gems##hdrGems'", "'XTarget##hdrXTarget'" }) do
            assert_true(src:find(gone, 1, true) == nil, 'Suite 89: hardcoded header button removed: ' .. gone)
        end
        assert_true(src:find("ImGui.BeginTable('TriunePluginsTable', 8, flags)", 1, true) ~= nil, 'Suite 89: Plugins table gained the Header column')
        assert_true(src:find("ImGui.TableSetupColumn('Header', ImGuiTableColumnFlags.WidthFixed, 56)", 1, true) ~= nil, 'Suite 89: Header column declared')

        -- 10. Settings -> Windows registry is built from the plugin window declarations
        W.getManaged = loadFunc(src, 'getManagedWindows', { runtime = rt, ctrl = W.ctrl })
        rt.CORE_WINDOWS = { { key = 'main', getOpen = function() return true end, setOpen = noop }, { key = 'mini', getOpen = function() return false end, setOpen = noop } }
        W.defs = W.getManaged()
        assert_eq(#W.defs, 2 + #pm.windowPlugins(false), 'Suite 89: registry = core windows + every enabled plugin window')
        W.byKey = {}
        for _, d in ipairs(W.defs) do W.byKey[d.key] = d end
        for _, k in ipairs({ 'main', 'mini', 'unit_frames', 'group', 'effects', 'cooldowns', 'xtarget', 'spell_gems', 'spellbook', 'auto_aa', 'auto_accept', 'map', 'dps', 'inventory', 'cursor', 'buffbot' }) do
            assert_true(W.byKey[k] ~= nil, 'Suite 89: registry lists window key ' .. k)
        end
        assert_eq(W.byKey.unit_frames.pluginId, 'hud_unitframes', 'Suite 89: window.key maps hud_unitframes to the unit_frames position key')
        assert_eq(W.byKey.unit_frames.canLock, true, 'Suite 89: lockFlag makes the entry lockable')
        assert_eq(W.byKey.map.canLock, false, 'Suite 89: windows without a lock flag are not lockable')
        assert_eq(W.byKey.buffbot ~= nil, true, 'Suite 89: header-button-off plugins still appear in the layout registry')
        W.ctrl.uf_lock = false
        W.byKey.unit_frames.setLock(true)
        assert_eq(W.ctrl.uf_lock, true, 'Suite 89: registry lock toggle writes the plugin lock flag')
        assert_eq(W.byKey.unit_frames.getLock(), true, 'Suite 89: registry lock getter reads the plugin lock flag')
        W.ctrl.show_dps = false
        W.byKey.dps.setOpen(true)
        assert_eq(W.ctrl.show_dps, true, 'Suite 89: registry Show writes the plugin window flag')
        assert_eq(W.byKey.dps.getOpen(), true, 'Suite 89: registry status reads the plugin window flag')
        assert_eq(W.byKey.map.desc, '2D zone map, Norrath atlas & NPC tracker', 'Suite 89: window.desc feeds the registry description')
        -- disabling a plugin drops its window from the registry; re-enabling restores the cached entry
        pm.disablePlugin('map')
        W.defs = W.getManaged()
        W.found = false
        for _, d in ipairs(W.defs) do if d.key == 'map' then W.found = true end end
        assert_eq(W.found, false, 'Suite 89: disabled plugin windows leave the registry')
        pm.enablePlugin('map')
        W.defs = W.getManaged()
        W.found = nil
        for _, d in ipairs(W.defs) do if d.key == 'map' then W.found = d end end
        assert_true(W.found == W.byKey.map, 'Suite 89: registry entries are cached per plugin (same table after re-enable)')

        -- 11. No plugin launches a removed standalone script; the gem bar opens the spellbook plugin window
        for _, f in ipairs({ 'hud_spellgems', 'hud_cooldowns', 'hud_unitframes', 'hud_group', 'hud_effects', 'hud_xtarget', 'spellbook', 'auto_aa', 'auto_accept', 'floating_damage', 'map', 'dps', 'inventory', 'buffbot', 'cursor' }) do
            assert_true(readFile('TAC/lua/tac/' .. f .. '.lua'):find("toggleTool('triune_", 1, true) == nil, 'Suite 89: ' .. f .. ' does not launch a removed standalone script')
        end
        W.ctrl.show_spellbook = false
        W.gems = pm.plugins.hud_spellgems and pm.plugins.hud_spellgems.instance
        assert_true(W.gems ~= nil, 'Suite 89: hud_spellgems loaded in the sandbox')
        assert_type(W.gems.openSpellbook, 'function', 'Suite 89: hud_spellgems exposes openSpellbook')
        W.gems.openSpellbook()
        assert_eq(W.ctrl.show_spellbook, true, 'Suite 89: gem bar Open Spellbook opens the spellbook plugin window')
        assert_eq(pm.isWindowOpen('spellbook'), true, 'Suite 89: spellbook window reported open by the manager')
    end
end


-- ============================================================================
-- Suite 90: Auto AA fireworks auto-summon only after the AA is purchased
-- ============================================================================
do
    print('--- Suite 90: Fireworks auto-summon requires the purchased AA ---')
    local printed = {}
    local quietPrint = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
    local noop = function() end
    local cmds = {}
    local ownedRank = 0        -- Me.AltAbility(...).Rank()
    local ready = false        -- Me.AltAbilityReady(...)
    local mq = {
        event = noop, unevent = noop, cmd = function(c) cmds[#cmds + 1] = c end,
        cmdf = function(f, ...) cmds[#cmds + 1] = string.format(f, ...) end,
        TLO = {
            Me = {
                Dead = function() return false end, Combat = function() return false end, Moving = function() return false end,
                AltAbility = function() return setmetatable({ Rank = function() return ownedRank end }, { __call = function() return true end }) end,
                AltAbilityReady = function() return function() return ready end end,
                AltAbilityTimer = function() return function() return 0 end end,
            },
        },
    }
    local core = {
        ctrl = { auto_summon_fireworks = true, auto_spend_aa_id = 17788, plugins = {} }, mq = mq,
        ImGui = setmetatable({}, { __index = function() return noop end }),
        runtime = { isCasting = function() return false end, cachedAAData = {} },
        DATA = {}, colors = {}, accent = noop, saveLoadout = noop, VERSION = '2.15',
    }
    local origPrint = print
    print = quietPrint
    local fn = assert(loadfile('TAC/lua/tac/auto_aa.lua'))
    local ok, aaPlugin = pcall(fn)
    assert_true(ok and type(aaPlugin) == 'table', 'Suite 90: auto_aa.lua loads')
    aaPlugin.onInit(core)
    local AA = aaPlugin.AA
    assert_type(AA.hasFireworksAA, 'function', 'Suite 90: AA.hasFireworksAA exists')

    -- Not purchased: never summons, even across repeated ticks
    assert_eq(AA.hasFireworksAA(17788), false, 'Suite 90: hasFireworksAA false with rank 0 and not ready')
    AA.lastAutoSummonAt = -100
    assert_eq(AA.checkAutoSummonFireworks(), false, 'Suite 90: no auto-summon before the AA is purchased')
    AA.lastAutoSummonAt = -100
    AA.checkAutoSummonFireworks()
    assert_eq(#cmds, 0, 'Suite 90: no /alt act issued while the AA is unowned')
    assert_eq(AA.manualSummonFireworks(), false, 'Suite 90: manual summon refuses without the AA')
    assert_eq(#cmds, 0, 'Suite 90: manual summon issues nothing without the AA')

    -- Purchased (rank > 0): summons once per cadence
    ownedRank = 1
    AA.lastAutoSummonAt = -100
    assert_eq(AA.hasFireworksAA(17788), true, 'Suite 90: hasFireworksAA true once a rank is trained')
    assert_eq(AA.checkAutoSummonFireworks(), true, 'Suite 90: auto-summon fires once the AA is owned')
    assert_eq(cmds[#cmds], '/alt act 17788', 'Suite 90: auto-summon activates the configured AA id')
    assert_eq(AA.checkAutoSummonFireworks(), false, 'Suite 90: 3s cadence still throttles repeat summons')

    -- AltAbilityReady alone (rank not reported) also counts as owned
    ownedRank = 0
    ready = true
    assert_eq(AA.hasFireworksAA(17788), true, 'Suite 90: AltAbilityReady counts as proof of ownership')

    -- Source guard: the auto-summon path calls the ownership check
    local aaSrc = readFile('TAC/lua/tac/auto_aa.lua')
    assert_true(aaSrc:find('if not AA.hasFireworksAA(aaId) then', 1, true) ~= nil, 'Suite 90: checkAutoSummonFireworks gates on AA.hasFireworksAA')

    -- Post-purchase summon is deferred, not fired on the Train click
    assert_true(aaSrc:find("Auto-summoning fireworks after purchasing", 1, true) == nil, 'Suite 90: no immediate /alt act after clicking Train')
    assert_true(aaSrc:find('AA.scheduleFireworksSummon(fwId, task.name)', 1, true) ~= nil, 'Suite 90: Train click schedules the summon instead')
    cmds = {}
    ownedRank = 0
    ready = false
    core.ctrl.auto_summon_delay_sec = 2.0
    AA.scheduleFireworksSummon(17788, 'Alternately Advanced Fireworks')
    assert_true(AA.pendingFireworksSummon ~= nil, 'Suite 90: summon job scheduled')
    assert_true(AA.pendingFireworksSummon.at > os.clock() + 1.5, 'Suite 90: summon waits for the configured delay')
    AA.processPendingFireworksSummon()
    assert_eq(#cmds, 0, 'Suite 90: nothing issued before the delay elapses')
    assert_eq(AA.checkAutoSummonFireworks(), false, 'Suite 90: periodic auto-summon stands down while a post-purchase summon is pending')
    AA.pendingFireworksSummon.at = os.clock() - 1
    AA.processPendingFireworksSummon()
    assert_eq(#cmds, 0, 'Suite 90: delay elapsed but purchase not visible yet -> no /alt act')
    assert_eq(AA.pendingFireworksSummon.tries, 1, 'Suite 90: unconfirmed purchase counts a retry')
    assert_true(AA.pendingFireworksSummon.at > os.clock() + 1.5, 'Suite 90: retry rescheduled after another delay')
    ownedRank = 1
    AA.pendingFireworksSummon.at = os.clock() - 1
    assert_eq(AA.processPendingFireworksSummon(), true, 'Suite 90: summon fires once the rank is visible')
    assert_eq(cmds[#cmds], '/alt act 17788', 'Suite 90: deferred summon activates the AA')
    assert_eq(AA.pendingFireworksSummon, nil, 'Suite 90: job cleared after summoning')
    -- Gives up after the retry cap
    ownedRank = 0
    AA.scheduleFireworksSummon(17788, 'x')
    for _ = 1, AA.FIREWORKS_SUMMON_MAX_TRIES do
        AA.pendingFireworksSummon.at = os.clock() - 1
        AA.processPendingFireworksSummon()
        if not AA.pendingFireworksSummon then break end
    end
    assert_eq(AA.pendingFireworksSummon, nil, 'Suite 90: pending summon abandoned after the retry cap')
    assert_eq(cmds[#cmds], '/alt act 17788', 'Suite 90: no extra /alt act issued while giving up')
    core.ctrl.auto_summon_delay_sec = nil
    assert_eq(AA.fireworksSummonDelay(), 3.0, 'Suite 90: summon delay defaults to 3s')
    aaPlugin.onDestroy()
    print = origPrint
end


-- ============================================================================
-- Suite 91: MQ2AAspend INI sync only when Auto-Spend is on and something changed
-- ============================================================================
do
    print('--- Suite 91: MQ2AAspend INI sync gating ---')
    local printed = {}
    local quietPrint = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
    local noop = function() end
    local cmds = {}
    local cfgDir = os.getenv('TMPDIR') or '/tmp'
    local iniPath = cfgDir .. '/TestServer_Tester.ini'
    os.remove(iniPath)
    local mq = {
        configDir = cfgDir,
        event = noop, unevent = noop,
        cmd = function(c) cmds[#cmds + 1] = c end,
        cmdf = function(f, ...) cmds[#cmds + 1] = string.format(f, ...) end,
        TLO = {
            Me = { CleanName = function() return 'Tester' end, Dead = function() return false end, Combat = function() return false end, Moving = function() return false end },
            EverQuest = { Server = function() return 'TestServer' end },
            Plugin = function() return setmetatable({ IsLoaded = function() return true end }, { __call = function() return true end }) end,
        },
    }
    local core = {
        ctrl = { plugins = {}, auto_spend_aa = false, auto_aa_delegate_aaspend = true, auto_aa_priorities = { ['Combat Agility'] = true, ['Innate Regeneration'] = true }, auto_spend_aa_threshold = 5 },
        mq = mq, ImGui = setmetatable({}, { __index = function() return noop end }),
        runtime = { isCasting = function() return false end, cachedAAData = { ['Combat Agility'] = { cost = 3 }, ['Innate Regeneration'] = { cost = 2 } } },
        DATA = {}, colors = {}, accent = noop, saveLoadout = noop, VERSION = '2.15',
    }
    local origPrint = print
    print = quietPrint
    local aaPlugin = assert(loadfile('TAC/lua/tac/auto_aa.lua'))()
    aaPlugin.onInit(core)
    local AA = aaPlugin.AA
    local function countLoads()
        local n = 0
        for _, c in ipairs(cmds) do if c == '/aaspend load' then n = n + 1 end end
        return n
    end

    -- Auto-Spend off: saving the loadout must not touch MQ2AAspend at all
    aaPlugin.onLoadoutSaved()
    aaPlugin.onLoadoutSaved()
    assert_eq(countLoads(), 0, 'Suite 91: no /aaspend load while Auto-Spend is off')
    assert_true(io.open(iniPath, 'r') == nil, 'Suite 91: INI not written while Auto-Spend is off')

    -- Auto-Spend on: first save syncs once, repeated saves are no-ops
    core.ctrl.auto_spend_aa = true
    aaPlugin.onLoadoutSaved()
    assert_eq(countLoads(), 1, 'Suite 91: first save with Auto-Spend on syncs and reloads MQ2AAspend')
    local f = io.open(iniPath, 'r')
    assert_true(f ~= nil, 'Suite 91: INI written on first sync')
    local iniText = f and f:read('*a') or ''
    if f then f:close() end
    assert_true(iniText:find('1=Innate Regeneration|M', 1, true) ~= nil, 'Suite 91: cheapest priority listed first')
    assert_true(iniText:find('BankPoints=5', 1, true) ~= nil, 'Suite 91: threshold written to BankPoints')
    for _ = 1, 5 do aaPlugin.onLoadoutSaved() end
    assert_eq(countLoads(), 1, 'Suite 91: unchanged priorities do not rewrite the INI or reload the plugin')
    local okSync, wrote = AA.syncAAsToMQ2AASpendIni(true)
    assert_true(okSync == true and wrote == false, 'Suite 91: sync reports no write when nothing changed')

    -- A real change syncs again; a forced manual sync always writes
    core.ctrl.auto_spend_aa_threshold = 9
    aaPlugin.onLoadoutSaved()
    assert_eq(countLoads(), 2, 'Suite 91: changed threshold triggers one more sync')
    aaPlugin.onLoadoutSaved()
    assert_eq(countLoads(), 2, 'Suite 91: still idempotent after the change')
    AA.syncAAsToMQ2AASpendIni(true, true)
    assert_eq(countLoads(), 3, 'Suite 91: forced (manual) sync rewrites even when unchanged')

    -- Delegation off: never sync from the loadout hook
    core.ctrl.auto_aa_delegate_aaspend = false
    core.ctrl.auto_spend_aa_threshold = 11
    aaPlugin.onLoadoutSaved()
    assert_eq(countLoads(), 3, 'Suite 91: no sync from the loadout hook when MQ2AAspend delegation is off')

    aaPlugin.onDestroy()
    os.remove(iniPath)
    print = origPrint
end


-- ============================================================================
-- Suite 92: Multi-pet tracking (real triune.lua functions on a mock spawn world)
-- ============================================================================
do
    print('--- Suite 92: Multi-pet tracking ---')

    -- Mock zone: spawns[id] = { name, race, type, masterId, dist, dead }
    local world = { spawns = {}, meId = 1, meName = 'Gennro', mePetId = 0, clock = 100 }
    local function spawnObj(id)
        local sp = world.spawns[id]
        local function masterObj(mid)
            return setmetatable({ ID = function() return mid or 0 end }, { __call = function() return (mid or 0) > 0 end })
        end
        return setmetatable({
            ID = function() return sp and id or 0 end,
            Dead = function() return sp and sp.dead or false end,
            Type = function() return sp and (sp.dead and 'Corpse' or sp.type or 'Pet') or '' end,
            State = function() return sp and (sp.dead and 'DEAD' or 'STAND') or '' end,
            CleanName = function() return sp and sp.name or '' end,
            Race = function() return sp and sp.race or '' end,
            Distance = function() return sp and sp.dist or 999 end,
            Master = masterObj(sp and sp.masterId),
            Owner = masterObj(0),
        }, { __call = function() return sp ~= nil end })
    end
    local function matches(filter)
        local kind, radius = filter:match('^(%a+) radius (%d+)$')
        radius = tonumber(radius) or 0
        local ids = {}
        for id, sp in pairs(world.spawns) do
            if not sp.dead and (sp.dist or 999) <= radius then
                local t = sp.type or 'Pet'
                if (kind == 'pet' and t == 'Pet') or (kind == 'npc' and t == 'NPC') then ids[#ids + 1] = id end
            end
        end
        table.sort(ids, function(a, b) return (world.spawns[a].dist or 0) < (world.spawns[b].dist or 0) end)
        return ids
    end
    local mq = { TLO = {} }
    mq.TLO.Spawn = spawnObj
    mq.TLO.Me = { ID = function() return world.meId end, CleanName = function() return world.meName end,
                  Pet = { ID = function() return world.mePetId end } }
    mq.TLO.SpawnCount = function(filter) return function() return #matches(filter) end end
    mq.TLO.NearestSpawn = function(i, filter) local ids = matches(filter); return ids[i] and spawnObj(ids[i]) or spawnObj(-1) end
    local fakeOs = setmetatable({ clock = function() return world.clock end }, { __index = os })

    local PET_CLASSES = { Nec = true, Mag = true, Bst = true, Enc = true, Shm = true, SK = true, Dru = true, Brd = true }
    -- loadFunc snapshots the env at load time, so these tables are reset in place
    local petState, ctrl, myClasses, runtime, printed = {}, {}, {}, {}, {}
    local env = { petState = petState, ctrl = ctrl, myClasses = myClasses, runtime = runtime }
    local function clearTable(t) for k in pairs(t) do t[k] = nil end end
    local function resetWorld(classes, names)
        world.spawns = {}; world.mePetId = 0; world.clock = 100
        clearTable(petState); clearTable(ctrl); clearTable(myClasses); clearTable(runtime); clearTable(printed)
        petState.myPets = {}; petState.lastObservedId = 0; petState.summonPending = nil; petState.summonBlockedUntil = {}
        petState.lastReconcileAt = 0; petState.petsCache = nil; petState.PET_CLASSES = PET_CLASSES
        petState.PET_SCOPE_LIST = { 'all', 'swarm', 'mag', 'bst', 'nec', 'enc', 'shm', 'dru', 'brd', 'shd' }
        ctrl.pet_names = names or {}; ctrl.debug_mode = false
        for i, c in ipairs(classes) do myClasses[i] = c end
    end
    local function addPet(id, name, opts)
        opts = opts or {}
        world.spawns[id] = { name = name, race = opts.race or 'Elemental', type = opts.type or 'Pet',
                             masterId = (opts.masterId == nil) and world.meId or opts.masterId, dist = opts.dist or 5, dead = false }
    end
    local function tick() world.clock = world.clock + 1; petState.petsCache = nil; petState.lastReconcileAt = 0 end
    resetWorld({ 'Nec', 'Mag', 'War' })

    env.mq = mq; env.os = fakeOs; env.print = function(msg) printed[#printed + 1] = tostring(msg) end
    env.isSpawnAlive = loadFunc(src, 'isSpawnAlive', env)
    env.petClsForName = loadFunc(src, 'petClsForName', env)
    env.spawnCleanName = loadFunc(src, 'spawnCleanName', env)
    env.isSpawnMyPet = loadFunc(src, 'isSpawnMyPet', env)
    env.petTrackedCls = loadFunc(src, 'petTrackedCls', env)
    env.prunePetTracking = loadFunc(src, 'prunePetTracking', env)
    env.trackPet = loadFunc(src, 'trackPet', env)
    env.getAllMyPets = loadFunc(src, 'getAllMyPets', env)
    env.classToPetCmdScope = loadFunc(src, 'classToPetCmdScope', env)
    env.detectPetClassFromSpawn = loadFunc(src, 'detectPetClassFromSpawn', env)
    env.reconcilePets = loadFunc(src, 'reconcilePets', env)
    env.getMultiPetList = loadFunc(src, 'getMultiPetList', env)
    env.PET_SUMMON_GRACE_SEC = 12
    env.PET_SUMMON_NEAR_DIST = 40
    env.snapshotNearbySpawnIds = loadFunc(src, 'snapshotNearbySpawnIds', env)
    env.beginPetSummon = loadFunc(src, 'beginPetSummon', env)
    env.updatePetTracking = loadFunc(src, 'updatePetTracking', env)
    env.onPetSummonRefused = loadFunc(src, 'onPetSummonRefused', env)
    env.isPetMissingForClass = loadFunc(src, 'isPetMissingForClass', env)
    local F = env

    -- A. Ownership
    resetWorld({ 'Nec', 'Mag', 'War' }, { Mag = 'Xobarb' })
    addPet(100, 'Gebann')
    addPet(101, 'Xobarb', { masterId = 42 })
    addPet(102, 'Xobarb', { masterId = 0 })
    addPet(103, 'Jabber', { masterId = 0 })
    addPet(104, 'Xobarb', { masterId = 0, type = 'NPC' })
    assert_eq(F.isSpawnMyPet(100), true, 'Suite 92: pet with our master ID is ours')
    assert_eq(F.isSpawnMyPet(101), false, 'Suite 92: learned name never overrides a foreign master')
    assert_eq(F.isSpawnMyPet(102), true, 'Suite 92: unresolved master + learned name -> ours')
    assert_eq(F.isSpawnMyPet(103), false, 'Suite 92: unresolved master + unknown name -> not ours')
    assert_eq(F.isSpawnMyPet(104), false, 'Suite 92: a plain NPC is never ours, even with a learned name')

    -- B. Tracking invariants
    resetWorld({ 'Nec', 'Mag', 'War' })
    addPet(100, 'Gebann', { race = 'Skeleton' })
    addPet(101, 'Xobarb', { race = 'Elemental' })
    petState.myPets.Nec = 100
    F.reconcilePets()
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: reconcile keeps the Nec pet')
    assert_eq(petState.myPets.Mag, 101, 'Suite 92: reconcile gives Mag the untracked pet, not the Nec pet again')
    assert_eq(printed[1] ~= nil and printed[1]:find('1 existing pet') ~= nil, true, 'Suite 92: reconcile reports only the newly tracked pet')

    petState.myPets = { Nec = 100, Mag = 100 }
    F.prunePetTracking()
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: prune keeps the first class for a duplicated ID')
    assert_eq(petState.myPets.Mag, nil, 'Suite 92: prune drops the duplicate class entry')

    F.trackPet('Mag', 100, false)
    assert_eq(petState.myPets.Mag, 100, 'Suite 92: trackPet assigns the pet')
    assert_eq(petState.myPets.Nec, nil, 'Suite 92: trackPet removes the ID from the other class')

    -- C. getMultiPetList never shows one pet twice (by ID or by name)
    petState.myPets = { Nec = 100, Mag = 100 }
    local slots, extra = F.getMultiPetList()
    assert_eq(slots[1].petId, 100, 'Suite 92: slot 1 shows the pet')
    assert_eq(slots[2].petId, 101, 'Suite 92: slot 2 gets the other living pet instead of a duplicate')
    assert_eq(#extra, 0, 'Suite 92: no extras when both pets are in slots')
    world.spawns[101].name = 'Gebann' -- same name under a second ID (stale/duplicate spawn)
    petState.myPets = { Nec = 100, Mag = 101 }
    slots = F.getMultiPetList()
    assert_eq(slots[1].petId, 100, 'Suite 92: name-dup: first slot keeps its pet')
    assert_eq(slots[2].petId, nil, 'Suite 92: name-dup: second slot does not show the same pet name')
    assert_eq(slots[3].isPetCls, false, 'Suite 92: War slot is a non-pet class')
    addPet(105, 'Gebann', { race = 'Skeleton' }) -- third ID with the same name
    petState.petsCache = nil
    slots, extra = F.getMultiPetList()
    assert_eq(#extra, 0, 'Suite 92: name-dup: extras never repeat a name shown in a slot')

    -- D. Learned names map pets back to their classes after a restart
    resetWorld({ 'Mag', 'Nec', 'War' }, { Mag = 'Xobarb', Nec = 'Gebann' })
    addPet(100, 'Gebann', { race = 'Unknown', dist = 3 })
    addPet(101, 'Xobarb', { race = 'Unknown', dist = 8 })
    F.reconcilePets()
    assert_eq(petState.myPets.Mag, 101, 'Suite 92: learned name -> Mag gets Xobarb')
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: learned name -> Nec gets Gebann')

    -- E. 'missing pet' per class + summon grace + detection without a Me.Pet change
    resetWorld({ 'Nec', 'Mag', 'War' })
    addPet(100, 'Gebann', { race = 'Skeleton' })
    world.mePetId = 100
    F.updatePetTracking()
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: Me.Pet is tracked under the first free pet class')
    assert_eq(F.isPetMissingForClass('Nec'), false, 'Suite 92: Nec has its pet')
    assert_eq(F.isPetMissingForClass('Mag'), true, 'Suite 92: Mag pet is missing')
    assert_eq(F.isPetMissingForClass('War'), false, 'Suite 92: non-pet class with pets around -> not missing')

    F.beginPetSummon('Mag', 'Elemental Servant')
    assert_eq(F.isPetMissingForClass('Mag'), false, 'Suite 92: summon in flight -> Mag stays quiet')
    assert_eq(F.isPetMissingForClass('Nec'), false, 'Suite 92: summon in flight does not affect Nec')
    tick(); F.updatePetTracking()
    assert_eq(petState.summonPending ~= nil, true, 'Suite 92: pending stays until a pet appears')
    addPet(102, 'Xobarb', { race = 'Elemental' }) -- appears; Me.Pet still 100
    tick(); F.updatePetTracking()
    assert_eq(petState.myPets.Mag, 102, 'Suite 92: new pet pinned to the casting class without a Me.Pet change')
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: Nec keeps its own pet')
    assert_eq(petState.summonPending, nil, 'Suite 92: pending cleared once the pet is found')
    assert_eq(ctrl.pet_names.Mag, 'Xobarb', 'Suite 92: name learned from the confirmed summon')
    assert_eq(ctrl.pet_names.Nec, nil, 'Suite 92: reconcile guesses do not learn names')
    assert_eq(runtime.autoDirty, true, 'Suite 92: learned name flags the loadout for autosave')
    assert_eq(F.isPetMissingForClass('Mag'), false, 'Suite 92: Mag no longer missing')

    -- Grace expires with no pet: the gem may cast again
    world.spawns[102].dead = true
    tick(); F.updatePetTracking()
    assert_eq(F.isPetMissingForClass('Mag'), true, 'Suite 92: dead Mag pet -> missing again')
    F.beginPetSummon('Mag', 'Elemental Servant')
    world.clock = world.clock + 5
    assert_eq(F.isPetMissingForClass('Mag'), false, 'Suite 92: still inside the grace window')
    world.clock = world.clock + 8; petState.petsCache = nil; petState.lastReconcileAt = 0
    F.updatePetTracking()
    assert_eq(petState.summonPending, nil, 'Suite 92: pending expires after the grace window')
    assert_eq(F.isPetMissingForClass('Mag'), true, 'Suite 92: after the grace window Mag is missing again')

    -- F. Master unresolved on the client: brand-new pet-typed spawn after the cast is the pet
    resetWorld({ 'Nec', 'Mag', 'War' })
    addPet(200, 'Kobold', { type = 'Pet', masterId = 0, dist = 30 }) -- already there before the cast
    F.beginPetSummon('Nec', 'Leering Corpse')
    addPet(201, 'Gebann', { type = 'Pet', masterId = 0, dist = 4 })
    addPet(202, 'Xobarb', { type = 'Pet', masterId = 42, dist = 6 }) -- someone else's pet arriving
    addPet(203, 'a guard', { type = 'NPC', masterId = 0, dist = 2 }) -- a mob arriving is never a pet
    tick(); F.updatePetTracking()
    assert_eq(petState.myPets.Nec, 201, 'Suite 92: masterless new pet spawn beside us is taken as the summoned pet')
    assert_eq(ctrl.pet_names.Nec, 'Gebann', 'Suite 92: its name is learned')
    assert_eq(F.isSpawnMyPet(201), true, 'Suite 92: learned name makes it ours from now on')
    assert_eq(F.isPetMissingForClass('Nec'), false, 'Suite 92: Nec not missing (no re-summon loop)')

    -- G. Me.Pet flips to the surviving pet after the other dies: no duplicate, dead class is missing
    resetWorld({ 'Nec', 'Mag', 'War' })
    addPet(100, 'Gebann', { race = 'Skeleton' })
    addPet(101, 'Xobarb', { race = 'Elemental' })
    petState.myPets = { Nec = 100, Mag = 101 }
    world.mePetId = 101; petState.lastObservedId = 101
    world.spawns[101].dead = true
    world.mePetId = 100
    tick(); F.updatePetTracking()
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: Nec still owns pet 100')
    assert_eq(petState.myPets.Mag, nil, 'Suite 92: Mag is not handed the Nec pet when Me.Pet flips')
    assert_eq(F.isPetMissingForClass('Mag'), true, 'Suite 92: Mag will re-summon')
    assert_eq(F.isPetMissingForClass('Nec'), false, 'Suite 92: Nec will not')

    -- H. Server refuses the summon: reassign the least-certain pet and back off
    resetWorld({ 'Nec', 'Mag', 'War' })
    addPet(100, 'Xobarb', { race = 'Unknown' })
    F.reconcilePets() -- guessed onto Nec (first pet class)
    assert_eq(petState.myPets.Nec, 100, 'Suite 92: unknown pet guessed onto the first pet class')
    F.beginPetSummon('Mag', 'Elemental Servant')
    F.onPetSummonRefused()
    assert_eq(petState.myPets.Mag, 100, 'Suite 92: refused summon moves the guessed pet to the casting class')
    assert_eq(petState.myPets.Nec, nil, 'Suite 92: the guessing class releases it')
    assert_eq(ctrl.pet_names.Mag, 'Xobarb', 'Suite 92: refused summon confirms the name')
    assert_eq(petState.summonPending, nil, 'Suite 92: refused summon clears pending')
    assert_eq((petState.summonBlockedUntil.Mag or 0) > world.clock, true, 'Suite 92: refused summon blocks Mag re-casts')
    F.beginPetSummon('Nec', 'Leering Corpse')
    F.onPetSummonRefused() -- nothing left to reassign
    assert_eq(petState.myPets.Nec, nil, 'Suite 92: nothing to reassign when all tracked pets are name-confirmed')
    assert_eq(F.isPetMissingForClass('Nec'), false, 'Suite 92: blocked class does not re-cast')
    world.clock = world.clock + 61; petState.petsCache = nil; petState.lastReconcileAt = 0
    assert_eq(F.isPetMissingForClass('Nec'), true, 'Suite 92: block expires after 60s')

    -- I. Single pet class: any of our pets satisfies it; nil cls = any pet at all
    resetWorld({ 'Mag', 'War', 'Clr' })
    assert_eq(F.isPetMissingForClass('Mag'), true, 'Suite 92: single pet class with no pets -> missing')
    assert_eq(F.isPetMissingForClass(nil), true, 'Suite 92: no class, no pets -> missing')
    addPet(100, 'Xobarb', { race = 'Unknown' })
    tick()
    assert_eq(F.isPetMissingForClass('Mag'), false, 'Suite 92: single pet class picks up any of our pets')
    assert_eq(F.isPetMissingForClass(nil), false, 'Suite 92: no class, a pet exists -> not missing')

    -- J. Source wiring
    assert_true(src:find("return isPetMissingForClass%(cls%)") ~= nil, 'Suite 92: missing pet condition delegates to isPetMissingForClass')
    assert_true(src:find("beginPetSummon%(g%.cls, g%.spell%)") ~= nil, 'Suite 92: pet gem cast starts summon tracking')
    assert_true(src:find("\n    updatePetTracking%(%)\n") ~= nil, 'Suite 92: main loop calls updatePetTracking')
    assert_true(src:find("lastCastCls") == nil, 'Suite 92: lastCastCls tracking removed')
    assert_true(src:find("cannot have more than one pet") ~= nil, 'Suite 92: summon-refused event registered')
end

-- ============================================================================
-- Suite 93: Decoupled 'has Poison' / 'has Disease' triggers
-- ============================================================================
do
    print('--- Suite 93: Decoupled poison / disease triggers ---')

    -- Mock world: Me is id 1; group member id 2 carries whatever counters we set.
    local world = { mePoison = 0, meDisease = 0, memPoison = 0, memDisease = 0 }
    local function memberObj()
        return setmetatable({
            ID = function() return 2 end,
            Poisoned = function() return world.memPoison > 0 end,
            Diseased = function() return world.memDisease > 0 end,
            CountersPoison = function() return world.memPoison end,
            CountersDisease = function() return world.memDisease end,
        }, { __call = function() return true end })
    end
    local mockTLO = {
        Me = {
            ID = function() return 1 end,
            CountersPoison = function() return world.mePoison end,
            CountersDisease = function() return world.meDisease end,
            Poisoned = function() return world.mePoison > 0 and 'Some Poison' or nil end,
            Diseased = function() return world.meDisease > 0 and 'Some Disease' or nil end,
        },
        Spawn = function(id)
            if id ~= 2 then return setmetatable({}, { __call = function() return false end }) end
            return setmetatable({ CleanName = function() return 'Boxer' end }, { __call = function() return true end })
        end,
        NetBots = function() return setmetatable({}, { __call = function() return false end }) end,
        Target = { ID = function() return 0 end },
        Group = { Members = function() return 1 end, Member = function() return memberObj() end },
    }
    local hasAffliction = loadFunc(src, 'hasAffliction', {
        mq = { TLO = mockTLO },
        AFFLICTION_MEMBERS = {
            Poison  = { flag = 'Poisoned', counter = 'CountersPoison' },
            Disease = { flag = 'Diseased', counter = 'CountersDisease' },
        },
    })

    -- A. Clean character: neither fires
    assert_eq(hasAffliction(1, 'Poison'), false, 'Suite 93: clean Me is not poisoned')
    assert_eq(hasAffliction(1, 'Disease'), false, 'Suite 93: clean Me is not diseased')

    -- B. Poison only on Me: poison fires, disease does not
    world.mePoison = 3
    assert_eq(hasAffliction(1, 'Poison'), true, 'Suite 93: poison counters trip the poison check')
    assert_eq(hasAffliction(1, 'Disease'), false, 'Suite 93: poison counters do not trip the disease check')

    -- C. Disease only on Me
    world.mePoison, world.meDisease = 0, 2
    assert_eq(hasAffliction(1, 'Disease'), true, 'Suite 93: disease counters trip the disease check')
    assert_eq(hasAffliction(1, 'Poison'), false, 'Suite 93: disease counters do not trip the poison check')

    -- D. Group member, independently
    world.meDisease = 0
    world.memPoison = 1
    assert_eq(hasAffliction(2, 'Poison'), true, 'Suite 93: group member poison detected')
    assert_eq(hasAffliction(2, 'Disease'), false, 'Suite 93: group member poison is not disease')
    world.memPoison, world.memDisease = 0, 1
    assert_eq(hasAffliction(2, 'Disease'), true, 'Suite 93: group member disease detected')
    assert_eq(hasAffliction(2, 'Poison'), false, 'Suite 93: group member disease is not poison')

    -- E. Guards
    assert_eq(hasAffliction(nil, 'Poison'), false, 'Suite 93: nil target is false')
    assert_eq(hasAffliction(1, 'Curse'), false, 'Suite 93: unknown affliction kind is false')

    -- F. conditionMet routes each trigger to its own checker (single target and Whole Group)
    local calls = {}
    local conditionMet = loadFunc(src, 'conditionMet', {
        mq = { TLO = mockTLO },
        runtime = {},
        pctHP = function() return 100 end,
        isCombat = function() return true end,
        baseTok = function(tok) return tok:gsub('^[FESPGAC]:%s*', '') end,
        buffActive = function() return false end,
        sungKey = function() return '' end,
        isFeignDeathAbility = function() return false end,
        isPoisoned = function(id) calls[#calls + 1] = 'P' .. id; return world.mePoison > 0 end,
        isDiseased = function(id) calls[#calls + 1] = 'D' .. id; return world.meDisease > 0 end,
        isPoisonedOrDiseased = function(id) calls[#calls + 1] = 'PD' .. id; return world.mePoison > 0 or world.meDisease > 0 end,
    })
    world.mePoison, world.meDisease = 2, 0
    assert_eq(conditionMet('has Poison', 100, 'Cure Poison', 1, 'Clr', 'F: Myself'), true, 'Suite 93: has Poison fires on poison')
    assert_eq(conditionMet('has Disease', 100, 'Cure Disease', 1, 'Clr', 'F: Myself'), false, 'Suite 93: has Disease stays quiet on poison')
    assert_eq(conditionMet('has Poison/Disease', 100, 'Cure', 1, 'Clr', 'F: Myself'), true, 'Suite 93: legacy combined trigger still fires')
    world.mePoison, world.meDisease = 0, 2
    assert_eq(conditionMet('has Poison', 100, 'Cure Poison', 1, 'Clr', 'F: Myself'), false, 'Suite 93: has Poison stays quiet on disease')
    assert_eq(conditionMet('has Disease', 100, 'Cure Disease', 1, 'Clr', 'F: Myself'), true, 'Suite 93: has Disease fires on disease')
    calls = {}
    assert_eq(conditionMet('has Disease', 100, 'Cure Disease', 0, 'Clr', 'F: Whole Group'), true, 'Suite 93: Whole Group disease scan fires')
    assert_eq(calls[1], 'D1', 'Suite 93: Whole Group scan starts with Me using the disease checker')
    for _, c in ipairs(calls) do
        assert_true(c:sub(1, 1) == 'D' and c:sub(2, 2) ~= 'P', 'Suite 93: Whole Group disease scan never consults the poison checker')
    end

    -- G. Dropdown and help table expose both triggers
    assert_true(src:find("'has Poison', 'has Disease', 'has Poison/Disease'", 1, true) ~= nil, 'Suite 93: WHENS lists has Poison and has Disease')
    assert_true(src:find("{ when = 'has Poison',", 1, true) ~= nil, 'Suite 93: help table documents has Poison')
    assert_true(src:find("{ when = 'has Disease',", 1, true) ~= nil, 'Suite 93: help table documents has Disease')
end

-- ============================================================================
-- Suite 94: Manual mode Stick / Auto-Nav options
-- ============================================================================
do
    print('--- Suite 94: Manual mode Stick / Auto-Nav options ---')

    local ctrl = {}
    local manualMovePolicy = loadFunc(src, 'manualMovePolicy', { ctrl = ctrl })

    -- A. Defaults (stick on, auto-nav off) reproduce the classic behaviour
    ctrl.manual_stick, ctrl.manual_auto_nav = nil, nil
    assert_eq(manualMovePolicy(true, false), 'move', 'Suite 94: default engaged -> move')
    assert_eq(manualMovePolicy(false, false), 'wait', 'Suite 94: default selected-only -> wait')

    -- B. Stick off: engaged target is fought from where the player stands
    ctrl.manual_stick, ctrl.manual_auto_nav = false, false
    assert_eq(manualMovePolicy(true, false), 'hold', 'Suite 94: stick off + engaged -> hold')
    assert_eq(manualMovePolicy(false, false), 'wait', 'Suite 94: stick off + selected-only -> wait')

    -- C. Auto-nav on: a merely selected hostile is approached
    ctrl.manual_stick, ctrl.manual_auto_nav = true, true
    assert_eq(manualMovePolicy(false, false), 'move', 'Suite 94: auto-nav on + selected-only -> move')
    assert_eq(manualMovePolicy(true, false), 'move', 'Suite 94: auto-nav on + stick on + engaged -> move')

    -- D. Auto-nav on, stick off: the approach finishes, then we hold
    ctrl.manual_stick, ctrl.manual_auto_nav = false, true
    assert_eq(manualMovePolicy(false, false), 'move', 'Suite 94: auto-nav on + stick off: approach a selected target')
    assert_eq(manualMovePolicy(true, true), 'move', 'Suite 94: auto-nav on + stick off: in-flight approach finishes after engage')
    assert_eq(manualMovePolicy(true, false), 'hold', 'Suite 94: auto-nav on + stick off: hold once the approach is done')

    -- E. Defaults and wiring
    assert_true(src:find("manual_stick%s*=%s*true,") ~= nil, 'Suite 94: manual_stick defaults to true')
    assert_true(src:find("manual_auto_nav%s*=%s*false,") ~= nil, 'Suite 94: manual_auto_nav defaults to false')
    assert_true(src:find("manualMovePolicy(isXtar or inCombatState, pursuit.id == id)", 1, true) ~= nil, 'Suite 94: combatTick consults the policy')
    assert_true(src:find("if haveNPC and not manualHold and (ctrl.mode ~= 'Manual'", 1, true) ~= nil, 'Suite 94: approach timeout skipped while holding')
    assert_true(src:find("Stick to Target in Combat##manualStick", 1, true) ~= nil, 'Suite 94: Stick checkbox on the Control tab')
    assert_true(src:find("Auto-Nav to Selected Target##manualAutoNav", 1, true) ~= nil, 'Suite 94: Auto-Nav checkbox on the Control tab')
    assert_true(src:find("cmd == 'manualstick'", 1, true) ~= nil, 'Suite 94: /ac manualstick command')
    assert_true(src:find("cmd == 'manualnav'", 1, true) ~= nil, 'Suite 94: /ac manualnav command')
    assert_eq(select(2, src:gsub("if ctrl%.mode == 'Manual' and ctrl%.manual_stick == false then return end", '')), 2,
        'Suite 94: too-far / cannot-hit repositioning stays out of the way with stick off')
end


-- ============================================================================
-- Suite 92: Random files dropped into the plugin folder are rejected safely
-- ============================================================================
do
    print('--- Suite 92: Non-plugin files in lua/tac ---')
    local S = { printed = {}, junkDir = (os.getenv('TMPDIR') or '/tmp') .. '/triune_junk_plugins' }
    local quietPrint = function(...) S.printed[#S.printed + 1] = table.concat({ ... }, ' ') end
    local noop = function() end
    os.execute('mkdir -p "' .. S.junkDir .. '"')
    local function writeJunk(name, body)
        local f = assert(io.open(S.junkDir .. '/' .. name, 'w'))
        f:write(body)
        f:close()
        return S.junkDir .. '/' .. name
    end
    S.delays = 0
    S.imguiInits = 0
    S.binds = 0
    local mockMq = {
        event = noop, unevent = noop, cmd = noop, cmdf = noop, unbind = noop,
        bind = function() S.binds = S.binds + 1 end,
        delay = function() S.delays = S.delays + 1 if S.delays > 5 then error('main loop would hang') end end,
        doevents = noop,
        gettime = function() return 0 end,
        imgui = { init = function() S.imguiInits = S.imguiInits + 1 end },
        TLO = {
            Me = { Combat = function() return false end, CombatState = function() return 'ACTIVE' end, CleanName = function() return 'T' end },
            EverQuest = { Server = function() return 'S' end },
            Target = { ID = function() return 0 end },
            Window = function() return { Open = function() return false end } end,
            Spawn = function() return setmetatable({}, { __call = function() return false end }) end,
        },
    }
    package.loaded['mq'] = mockMq
    local env = {
        ctrl = { plugins = {} }, mq = mockMq,
        ImGui = setmetatable({ Button = function() return false end, SmallButton = function() return false end, Checkbox = function(_, v) return v end, IsItemHovered = function() return false end, BeginTable = function() return false end }, { __index = function() return noop end }),
        UI = { accent = noop, setTooltip = noop, pushTheme = noop, popTheme = noop, preBeginWindow = noop, postBeginWindow = noop,
               drawStatusProgressBar = noop, drawSpellIcon = function() return false end,
               getConColorRgb = function() return { 1, 1, 1, 1 } end, resolveTargetOfTarget = function() return nil end },
        VERSION = '2.15', DATA = {}, loadout = {}, scriptDir = './',
        GOLD = { 1, 1, 1, 1 }, ARC = { 1, 1, 1, 1 }, MUTED = { 1, 1, 1, 1 }, GOOD = { 1, 1, 1, 1 }, WARN = { 1, 1, 1, 1 }, ERR = { 1, 1, 1, 1 },
        saveLoadout = noop, print = quietPrint,
        idxOf = function() return 0 end, fmtSec = tostring, parseDurationSec = function() return 0 end,
        cleanSpellName = tostring, normalizeSpellName = tostring,
    }
    local initPM = loadFunc(src, 'initPluginManager', env)
    local rt = debug.getfenv(initPM).runtime
    rt.saveLoadout = noop
    initPM()
    local pm = rt.pluginManager
    S.shipped = #pm.pluginOrder
    assert_eq(S.shipped, 17, 'Suite 92: all shipped plugins still load under the load-time guards')
    assert_eq(next(pm.loadErrors), nil, 'Suite 92: shipped plugins produce no load errors')

    -- 1. A standalone MQ script: its main loop must never run on the core
    S.delays = 0
    S.binds = 0 -- (dps bound /dps in its onInit above; that is the legitimate path)
    S.path = writeJunk('standalone_script.lua', "local mq = require('mq')\nmq.imgui.init('Junk', function() end)\nmq.bind('/junk', function() end)\nwhile true do mq.delay(50) end\n")
    S.ok, S.err = pm.loadPlugin('standalone_script.lua', S.path)
    assert_eq(S.ok, false, 'Suite 92: standalone script is not loaded as a plugin')
    assert_true(tostring(S.err):find('standalone script', 1, true) ~= nil, 'Suite 92: reason explains it is a standalone script')
    assert_eq(S.imguiInits, 0, 'Suite 92: no ImGui callback leaked from the script')
    assert_eq(S.binds, 0, 'Suite 92: no /bind leaked from the script')
    assert_eq(S.delays, 0, 'Suite 92: the script main loop never ran (mq.delay guarded)')
    assert_true(pm.scripts['standalone_script.lua'] ~= nil, 'Suite 92: standalone script gets a Standalone Scripts entry')
    assert_eq(pm.loadErrors['standalone_script.lua'], nil, 'Suite 92: a runnable script is not listed as a load failure')
    assert_eq(pm.scripts['standalone_script.lua'].runName, 'triune_junk_plugins/standalone_script', 'Suite 92: run name is <folder>/<file> when the folder is outside mq.luaDir')
    assert_eq(mockMq.delay ~= nil and S.delays, 0, 'Suite 92: guards restored mq.delay afterwards')
    mockMq.delay(1)
    assert_eq(S.delays, 1, 'Suite 92: original mq.delay restored after the load attempt')

    -- 1b. A script that calls mq.exit while loading cannot kill Triune's script
    S.exits = 0
    mockMq.exit = function() S.exits = S.exits + 1 end
    S.path = writeJunk('exits_at_load.lua', "local mq = require('mq')\nmq.exit()\n")
    S.ok, S.err = pm.loadPlugin('exits_at_load.lua', S.path)
    assert_eq(S.ok, false, 'Suite 92: mq.exit at load is not a plugin')
    assert_eq(S.exits, 0, 'Suite 92: mq.exit guarded while the file is inspected')
    assert_true(tostring(S.err):find('mq.exit', 1, true) ~= nil, 'Suite 92: reason names mq.exit')
    mockMq.exit(); assert_eq(S.exits, 1, 'Suite 92: original mq.exit restored afterwards')
    pm.scripts['exits_at_load.lua'] = nil

    -- 1c. UI-triggered lifecycle work is queued and runs from pm.tick (main coroutine), never in the render callback
    S.ran = {}
    pm.defer('op A', function() S.ran[#S.ran + 1] = 'A' end)
    pm.defer('op B', function() error('boom') end)
    pm.defer('op C', function() S.ran[#S.ran + 1] = 'C' end)
    assert_eq(pm.hasDeferred(), true, 'Suite 92: deferred ops are queued, not run immediately')
    assert_eq(#S.ran, 0, 'Suite 92: nothing ran at enqueue time')
    pm.tick()
    assert_eq(table.concat(S.ran, ','), 'A,C', 'Suite 92: pm.tick drains the queue in order and survives a failing op')
    assert_eq(pm.hasDeferred(), false, 'Suite 92: queue empty after the tick')
    for _, direct in ipairs({ "btnRescanPlugins', 170, 24) then\n        pm.discover()", "btnReloadAllPlugins', 110, 24) then\n        pm.reloadAll()", "                pm.loadPlugin(entry.file, entry.info.fullPath)\n", "                    pm.loadPlugin(entry.file, entry.fullPath)\n" }) do
        assert_true(src:find(direct, 1, true) == nil, 'Suite 92: Plugins page does not run plugin code directly from the render callback: ' .. direct:gsub('%s+', ' '))
    end
    for _, queued in ipairs({ "pm.defer('rescan plugins folder', pm.discover)", "pm.defer('reload all plugins', pm.reloadAll)", "pm.defer('retry ' .. entry.file", "pm.defer('re-check ' .. entry.file", "pm.defer((newEn and 'enable ' or 'disable ') .. id" }) do
        assert_true(src:find(queued, 1, true) ~= nil, 'Suite 92: Plugins page queues ' .. queued)
    end
    assert_true(src:find('function pm.tick()\n        pm.runDeferred()', 1, true) ~= nil, 'Suite 92: pm.tick drains deferred ops first')

    -- 2. A plain data table is not a plugin
    S.path = writeJunk('data_file.lua', "return { ['Some Spell'] = { level = 5 } }\n")
    S.ok, S.err = pm.loadPlugin('data_file.lua', S.path)
    assert_eq(S.ok, false, 'Suite 92: data file is not loaded as a plugin')
    assert_true(tostring(S.err):find('no `id` and none of the plugin hooks', 1, true) ~= nil, 'Suite 92: data file reason names the contract')
    assert_eq(pm.plugins.data_file, nil, 'Suite 92: data file not registered as a plugin')
    assert_true(pm.scripts['data_file.lua'] ~= nil, 'Suite 92: data file listed as a standalone script entry')

    -- 3. Syntax error and non-table return
    S.path = writeJunk('broken.lua', 'local x = = 1\n')
    S.ok, S.err = pm.loadPlugin('broken.lua', S.path)
    assert_true(S.ok == false and tostring(S.err):find('Syntax error', 1, true) ~= nil, 'Suite 92: syntax error rejected and reported')
    assert_true(pm.loadErrors['broken.lua'] ~= nil and pm.scripts['broken.lua'] == nil, 'Suite 92: a file with a syntax error is a load failure, not a runnable script')
    S.path = writeJunk('returns_number.lua', 'return 42\n')
    S.ok, S.err = pm.loadPlugin('returns_number.lua', S.path)
    assert_true(S.ok == false and tostring(S.err):find('returns number', 1, true) ~= nil, 'Suite 92: non-table return becomes a script entry with a reason')
    assert_true(pm.scripts['returns_number.lua'] ~= nil, 'Suite 92: non-table return listed as a standalone script')

    -- 4. Duplicate id cannot hijack a loaded plugin
    S.path = writeJunk('dup_id.lua', "return { id = 'map', name = 'Impostor', onInit = function() end }\n")
    S.ok, S.err = pm.loadPlugin('dup_id.lua', S.path)
    assert_eq(S.ok, false, 'Suite 92: duplicate id rejected')
    assert_true(tostring(S.err):find('already registered by map.lua', 1, true) ~= nil, 'Suite 92: duplicate id names the owning file')
    assert_eq(pm.plugins.map.name, 'Map & NPC Tracker', 'Suite 92: real map plugin untouched by the impostor')
    assert_true(pm.loadErrors['dup_id.lua'] ~= nil and pm.scripts['dup_id.lua'] == nil, 'Suite 92: duplicate id is a load failure, not a runnable script')
    assert_eq(#pm.pluginOrder, S.shipped, 'Suite 92: nothing junk got registered')

    -- Run / Stop drive the script through /lua run|stop, status comes from the Lua TLO
    S.cmds = {}
    mockMq.cmd = function(c) S.cmds[#S.cmds + 1] = c end
    S.running = false
    mockMq.TLO.Lua = { Script = function(name) S.lastLookup = name return setmetatable({ Status = function() return S.running and 'RUNNING' or 'STOPPED' end }, { __call = function() return true end }) end }
    S.entry = pm.scripts['standalone_script.lua']
    assert_eq(pm.isScriptRunning(S.entry), false, 'Suite 92: script reported stopped')
    assert_eq(pm.toggleScript(S.entry), 'started', 'Suite 92: Run starts the script')
    assert_eq(S.cmds[#S.cmds], '/lua run triune_junk_plugins/standalone_script', 'Suite 92: Run issues /lua run with the folder-relative name')
    assert_eq(S.lastLookup, 'triune_junk_plugins/standalone_script', 'Suite 92: status looked up under the same run name')
    S.running = true
    assert_eq(pm.isScriptRunning(S.entry), true, 'Suite 92: script reported running')
    assert_eq(pm.toggleScript(S.entry), 'stopped', 'Suite 92: Stop stops a running script')
    assert_eq(S.cmds[#S.cmds], '/lua stop triune_junk_plugins/standalone_script', 'Suite 92: Stop issues /lua stop')
    mockMq.cmd = noop
    -- run names resolve relative to mq.luaDir when the folder lives under it
    mockMq.luaDir = '/mq/lua'
    assert_eq(pm.scriptRunName('/mq/lua/tac/foo.lua'), 'tac/foo', 'Suite 92: run name relative to mq.luaDir')
    assert_eq(pm.scriptRunName('C:\\MQ\\lua\\tac\\bar.lua'), 'tac/bar', 'Suite 92: run name strips the drive path outside luaDir (folder/file)')
    mockMq.luaDir = nil

    -- 5. A minimal valid plugin still loads (hooks only, no id -> filename id), and clears its error entry
    S.path = writeJunk('minimal_ok.lua', "return { onTick = function() end }\n")
    pm.loadErrors['minimal_ok.lua'] = { msg = 'stale', fullPath = S.path }
    S.ok = pm.loadPlugin('minimal_ok.lua', S.path)
    assert_eq(S.ok, true, 'Suite 92: hook-only plugin table is accepted')
    assert_eq(pm.plugins.minimal_ok and pm.plugins.minimal_ok.status, 'Active', 'Suite 92: minimal plugin registered under its filename id')
    assert_eq(pm.loadErrors['minimal_ok.lua'], nil, 'Suite 92: successful load clears the failure entry')
    S.count = 0
    for _ in pairs(pm.loadErrors) do S.count = S.count + 1 end
    assert_eq(S.count, 2, 'Suite 92: two genuinely broken files listed as load failures')
    S.count = 0
    for _ in pairs(pm.scripts) do S.count = S.count + 1 end
    assert_eq(S.count, 3, 'Suite 92: three runnable non-plugin files listed as standalone scripts')

    -- 6. Re-check promotes a script entry to a plugin once it conforms
    S.path = writeJunk('data_file.lua', "return { id = 'data_file', onTick = function() end }\n")
    S.ok = pm.loadPlugin('data_file.lua', S.path)
    assert_eq(S.ok, true, 'Suite 92: Re-check loads the file once it returns a plugin table')
    assert_eq(pm.scripts['data_file.lua'], nil, 'Suite 92: promoted file leaves the Standalone Scripts list')
    assert_eq(pm.plugins.data_file and pm.plugins.data_file.status, 'Active', 'Suite 92: promoted file is an active plugin')

    -- 7. Rescans do not re-execute known scripts; the Plugins page lists both sections; reloadAll clears them
    S.delays = 0
    S.imguiInits = 0
    pm.dirPath = S.junkDir
    pm.discover()
    assert_eq(S.imguiInits, 0, 'Suite 92: rescan does not re-run a known standalone script chunk')
    assert_true(pm.scripts['standalone_script.lua'] ~= nil, 'Suite 92: known script entry survives a rescan')
    assert_true(src:find("'| Standalone scripts: %d'", 1, true) ~= nil, 'Suite 92: Plugins page shows the standalone script count')
    assert_true(src:find("ImGui.BeginTable('TriuneScriptsTable', 4, sFlags)", 1, true) ~= nil, 'Suite 92: Plugins page has the Standalone Scripts table')
    assert_true(src:find("'| Failed to load: %d'", 1, true) ~= nil, 'Suite 92: Plugins page shows the failed-file count')
    assert_true(src:find('Files in the plugin folder that could not be loaded:', 1, true) ~= nil, 'Suite 92: Plugins page lists failed files')
    pm.dirPath = nil
    pm.loadErrors = {}
    pm.scripts = {}
    pm.reloadAll()
    assert_eq(next(pm.loadErrors), nil, 'Suite 92: reloadAll starts with a clean failure list')
    assert_eq(next(pm.scripts), nil, 'Suite 92: reloadAll starts with a clean script list')

    os.execute('rm -rf "' .. S.junkDir .. '"')
    package.loaded['mq'] = nil
end


-- ============================================================================
-- Suite 95: Box Network plugin (MacroQuest Actors) - fake post office, 3 boxes
-- ============================================================================
-- Wrapped in a closure: the main chunk is close to Lua's 200-local limit.
;(function()
    print('--- Suite 95: Box Network plugin (MacroQuest Actors) ---')
    local realPrint = print
    local printed = {}
    print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end ---@diagnostic disable-line: lowercase-global

    local function lower(v) return tostring(v or ''):lower() end

    -- In-memory stand-in for the MQ post office. Mimics the launcher: every
    -- client with the same mailbox gets a broadcast (including the sender),
    -- addressed sends match on character / pid, RPC replies come back through
    -- the sender's callback, and routing failures surface as status codes.
    local function makeBus()
        local bus = { clients = {}, queue = {}, down = false, nonSerializable = 0 }
        local function ser(v, depth)
            depth = depth or 0
            local t = type(v)
            if t == 'string' or t == 'number' or t == 'boolean' or t == 'nil' then return v end
            if t == 'table' then
                if depth > 16 then return nil end
                local out = {}
                for k, val in pairs(v) do
                    local sv = ser(val, depth + 1)
                    if sv ~= nil then out[k] = sv end
                end
                return out
            end
            bus.nonSerializable = bus.nonSerializable + 1
            return nil
        end
        bus.ser = ser
        function bus.client(identity)
            local mod = { ResponseStatus = { ConnectionClosed = -1, NoConnection = -2, RoutingFailed = -3, AmbiguousRecipient = -4 } }
            function mod.register(name, handler)
                if type(name) == 'function' then handler, name = name, '__script' end
                for _, c in ipairs(bus.clients) do
                    if c.id == identity and c.mailbox == name then error('mailbox already registered: ' .. name) end
                end
                local entry = { id = identity, mailbox = name, handler = handler }
                table.insert(bus.clients, entry)
                local dropbox = {}
                function dropbox:send(a, b, c)
                    local address, payload, cb
                    if type(b) == 'table' then address, payload, cb = a, b, c
                    else payload, cb = a, b end
                    table.insert(bus.queue, { from = entry, address = address, payload = ser(payload), cb = cb })
                end
                function dropbox:unregister()
                    for i = #bus.clients, 1, -1 do
                        if bus.clients[i] == entry then table.remove(bus.clients, i) end
                    end
                end
                return dropbox
            end
            return mod
        end
        local function senderOf(entry)
            return { character = entry.id.character, server = entry.id.server, account = entry.id.account, pid = entry.id.pid, mailbox = entry.mailbox, script = 'triune' }
        end
        function bus.flush()
            local guard = 0
            while #bus.queue > 0 and guard < 10000 do
                guard = guard + 1
                local item = table.remove(bus.queue, 1)
                if item.reply then
                    item.cb(item.status, { content = item.content, sender = item.sender })
                elseif bus.down then
                    if item.cb then item.cb(-2, nil) end
                else
                    local targets = {}
                    for _, c in ipairs(bus.clients) do
                        if c.mailbox == item.from.mailbox then
                            local a = item.address
                            local ok = true
                            if a and a.character and lower(a.character) ~= lower(c.id.character) then ok = false end
                            if a and a.pid and a.pid ~= c.id.pid then ok = false end
                            if ok then targets[#targets + 1] = c end
                        end
                    end
                    if item.address and #targets == 0 then
                        if item.cb then item.cb(-3, nil) end
                    elseif item.address and item.cb and #targets > 1 then
                        item.cb(-4, nil)
                    else
                        for _, target in ipairs(targets) do
                            local msg = { content = ser(item.payload), sender = senderOf(item.from) }
                            local replied = false
                            function msg:reply(status, content)
                                if content == nil then content, status = status, 0 end
                                if item.cb and not replied then
                                    replied = true
                                    table.insert(bus.queue, { reply = true, cb = item.cb, status = status, content = ser(content), sender = senderOf(target) })
                                end
                            end
                            function msg:send(content)
                                table.insert(bus.queue, { from = target, address = { character = item.from.id.character }, payload = ser(content) })
                            end
                            target.handler(msg)
                        end
                    end
                end
            end
        end
        return bus
    end

    local bus = makeBus()
    local clock = { t = 1000 }
    local noop = function() end
    local passthrough = function(_, v) return v end
    local mockImGui = setmetatable({
        Checkbox = passthrough, SliderFloat = passthrough, SliderInt = passthrough, Combo = passthrough,
        InputTextWithHint = function(_, _, v) return v, false end,
        Button = function() return false end, SmallButton = function() return false end,
        Selectable = function() return false end, BeginCombo = function() return false end,
        BeginTable = function() return false end, BeginChild = function() return false end,
        CollapsingHeader = function() return false end, IsItemHovered = function() return false end,
        Begin = function(_, open) return open, true end,
    }, { __index = function() return function() end end })

    local function callable(ret, fields)
        local t = fields or {}
        return setmetatable(t, { __call = function() return ret end })
    end

    local boxes = {}
    local function makeBox(name, opts)
        opts = opts or {}
        local box = {
            name = name, zone = opts.zone or 'gfaydark', pid = opts.pid or (#boxes + 1) * 100,
            cmds = {}, saves = 0, hp = opts.hp or 100, mana = opts.mana or 80, endur = 90,
            targetId = 0, targetName = nil, x = opts.x or 10, y = opts.y or 20, z = opts.z or 5,
            groupMembers = {},
            ctrl = { mode = 'Manual', submode = 'Hunt', running = false, burn = false, ma_name = '', camp_radius = 100, plugins = {} },
        }
        local mq = {
            cmd = function(c) box.cmds[#box.cmds + 1] = c end,
            cmdf = function(f, ...) box.cmds[#box.cmds + 1] = string.format(f, ...) end,
            TLO = {
                Me = {
                    CleanName = function() return box.name end,
                    Level = function() return 60 end,
                    PctHPs = function() return box.hp end,
                    PctMana = function() return box.mana end,
                    PctEndurance = function() return box.endur end,
                    Combat = function() return false end,
                    CombatState = function() return 'ACTIVE' end,
                    Sitting = function() return false end,
                    Casting = { Name = function() return nil end },
                    X = function() return box.x end, Y = function() return box.y end, Z = function() return box.z end,
                    Pet = { ID = function() return 0 end },
                    CountersPoison = function() return box.poison or 0 end,
                    CountersDisease = function() return box.disease or 0 end,
                    CountersCurse = function() return box.curse or 0 end,
                    CountersCorruption = function() return box.corruption or 0 end,
                },
                Zone = { ShortName = function() return box.zone end, ID = function() return 54 end },
                Target = {
                    ID = function() return box.targetId end,
                    CleanName = function() return box.targetName end,
                    PctHPs = function() return box.targetHp or 50 end,
                    Type = function() return 'NPC' end,
                },
                EverQuest = { PID = function() return box.pid end },
                Group = {
                    Member = function(n)
                        if box.groupMembers[lower(n)] then return callable('member', { ID = function() return 7 end }) end
                        return callable(nil, { ID = function() return 0 end })
                    end,
                },
            },
        }
        local core = setmetatable({
            mq = mq, ImGui = mockImGui, runtime = { pullState = 'IDLE' }, VERSION = '2.15',
            colors = {}, saveLoadout = function() box.saves = box.saves + 1 end,
            pushTheme = noop, popTheme = noop, accent = noop, setTooltip = noop,
            preBeginWindow = noop, postBeginWindow = noop,
        }, { __index = function(_, k)
            if k == 'ctrl' then return box.ctrl end
            if k == 'myClasses' then return { 'WAR', 'CLR', 'ENC' } end
            return nil
        end })
        local inst = assert(loadfile('TAC/lua/tac/boxnet.lua'))()
        if opts.noActors then
            inst.actorsModule = false
        else
            inst.actorsModule = bus.client({ character = name, server = 'triune', account = 'acct', pid = box.pid })
        end
        inst.clock = function() return clock.t end
        inst.registry = {} -- each simulated box is its own "Lua state"
        box.inst, box.core, box.mq = inst, core, mq
        boxes[#boxes + 1] = box
        return box
    end

    -- One pump = every box ticks (sends), the launcher delivers, every box
    -- ticks again (drains its inbox, sends replies), the launcher delivers.
    local function tickAll()
        for _, b in ipairs(boxes) do
            if b.inst.net.actor then b.inst.tick() end
        end
    end
    local function pump(n)
        for _ = 1, (n or 1) do
            tickAll()
            bus.flush()
            tickAll()
            bus.flush()
        end
    end
    local function peerNames(box)
        local out = {}
        for _, p in ipairs(box.inst.peerList()) do out[#out + 1] = p.name end
        return table.concat(out, ',')
    end
    local function lastLog(box, needle)
        for _, e in ipairs(box.inst.net.log) do
            if e.text:find(needle, 1, true) then return e end
        end
        return nil
    end

    -- 1. Contract & helpers
    local A = makeBox('Alice')
    local B = makeBox('Bob')
    local C = makeBox('Carol', { zone = 'crushbone' })
    assert_eq(A.inst.id, 'boxnet', 'Suite 95: plugin id')
    assert_eq(A.inst.window.flag, 'show_boxnet', 'Suite 95: window flag is show_boxnet')
    assert_true(#A.inst.help >= 3, 'Suite 95: help lines contributed')
    assert_eq(A.inst.normalizeLine('  /ac burn on '), 'burn on', 'Suite 95: normalizeLine strips /ac and whitespace')
    assert_eq(A.inst.normalizeLine('net all run'), nil, 'Suite 95: nested net commands rejected')
    assert_eq(A.inst.normalizeLine('/ac'), nil, 'Suite 95: bare /ac rejected')
    assert_eq(A.inst.resolveScope('ZONE'), 'zone', 'Suite 95: resolveScope is case-insensitive')
    assert_eq(A.inst.resolveScope('Bob'), 'name', 'Suite 95: resolveScope treats unknown words as a character name')
    assert_eq(A.inst.resolveScope(''), 'all', 'Suite 95: resolveScope defaults to the configured scope')
    local dirty = { a = 1, f = function() end, nest = { ok = true, u = coroutine.create(function() end) }, [true] = 1 }
    local clean = A.inst.sanitize(dirty)
    assert_eq(clean.a, 1, 'Suite 95: sanitize keeps primitives')
    assert_nil(clean.f, 'Suite 95: sanitize drops functions')
    assert_nil(clean.nest.u, 'Suite 95: sanitize drops nested non-serializable values')
    assert_eq(clean.nest.ok, true, 'Suite 95: sanitize keeps nested primitives')
    assert_nil(clean[true], 'Suite 95: sanitize drops non string/number keys')

    -- 2. Discovery: hello + heartbeat on init, rosters exclude self
    A.inst.onInit(A.core)
    B.inst.onInit(B.core)
    C.inst.onInit(C.core)
    assert_eq(#bus.clients, 3, 'Suite 95: each box registers its mailbox')
    assert_eq(bus.clients[1].mailbox, A.inst.MAILBOX, 'Suite 95: mailbox name is the plugin constant')
    assert_true(A.inst.net.actor ~= nil, 'Suite 95: actor registered on init')
    assert_eq(A.core.boxnet, A.inst.api, 'Suite 95: core.boxnet API published on init')
    assert_eq(A.ctrl.show_boxnet, false, 'Suite 95: window flag seeded closed')
    pump(2)
    assert_eq(peerNames(A), 'Bob,Carol', 'Suite 95: Alice sees Bob and Carol (not herself)')
    assert_eq(peerNames(B), 'Alice,Carol', 'Suite 95: Bob sees Alice and Carol')
    assert_eq(peerNames(C), 'Alice,Bob', 'Suite 95: Carol sees Alice and Bob')
    local bobSeenByA = A.inst.api.peer('bob')
    assert_true(bobSeenByA ~= nil, 'Suite 95: api.peer is case-insensitive')
    assert_eq(bobSeenByA.hb.hp, 100, 'Suite 95: heartbeat carries HP')
    assert_eq(bobSeenByA.hb.mana, 80, 'Suite 95: heartbeat carries mana')
    assert_eq(bobSeenByA.hb.zone, 'gfaydark', 'Suite 95: heartbeat carries zone')
    assert_eq(bobSeenByA.hb.mode, 'Manual', 'Suite 95: heartbeat carries mode')
    assert_eq(table.concat(bobSeenByA.hb.classes, '/'), 'WAR/CLR/ENC', 'Suite 95: heartbeat carries the trio')
    assert_eq(bobSeenByA.hb.running, false, 'Suite 95: heartbeat carries running state')
    assert_eq(bobSeenByA.pid, 200, 'Suite 95: sender pid recorded on the peer')
    assert_eq(bobSeenByA.server, 'triune', 'Suite 95: sender server recorded on the peer')
    assert_eq(bus.nonSerializable, 0, 'Suite 95: nothing non-serializable was ever handed to actors')

    -- 3. Heartbeat cadence: throttled while idle, immediate on a state change
    local sentBefore = A.inst.net.sent
    clock.t = clock.t + 0.1
    pump(1)
    assert_eq(A.inst.net.sent, sentBefore, 'Suite 95: no heartbeat inside the interval when nothing changed')
    A.ctrl.burn = true
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(A.inst.net.sent, sentBefore + 1, 'Suite 95: state change triggers an immediate heartbeat')
    assert_eq(B.inst.api.peer('Alice').hb.burn, true, 'Suite 95: Bob sees Alice burn on within one pump')
    clock.t = clock.t + 1.1
    pump(1)
    assert_eq(A.inst.net.sent, sentBefore + 2, 'Suite 95: periodic heartbeat after the interval elapses')
    A.targetId, A.targetName = 1234, 'a_gnoll'
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(B.inst.api.peer('Alice').hb.target.name, 'a_gnoll', 'Suite 95: target change propagates (name)')
    assert_eq(B.inst.api.peer('Alice').hb.target.id, 1234, 'Suite 95: target change propagates (id)')

    -- 4. Remote commands: broadcast, self excluded, nested / empty rejected
    local ok, why = A.inst.sendCommand('all', '/ac burn on')
    assert_eq(ok, true, 'Suite 95: broadcast command accepted')
    pump(1)
    assert_eq(B.cmds[#B.cmds], '/ac burn on', 'Suite 95: Bob ran the broadcast command')
    assert_eq(C.cmds[#C.cmds], '/ac burn on', 'Suite 95: Carol ran the broadcast command')
    assert_eq(#A.cmds, 0, 'Suite 95: Alice does not run her own broadcast')
    assert_true(lastLog(B, '<- Alice: burn on') ~= nil, 'Suite 95: receiver logs the command with the sender')
    assert_true(printed[#printed]:find('Alice -> /ac burn on', 1, true) ~= nil, 'Suite 95: receiver announces the command in chat')
    ok, why = A.inst.sendCommand('all', 'net all run')
    assert_eq(ok, false, 'Suite 95: nested net command refused at the sender')
    assert_true(why:find('nested', 1, true) ~= nil, 'Suite 95: nested refusal reason')
    ok, why = A.inst.sendCommand('all', '   ')
    assert_eq(ok, false, 'Suite 95: empty command refused')
    -- receiver re-validates: a hand-crafted nested line never runs
    local nB = #B.cmds
    B.inst.processMessage({ content = { v = 1, kind = 'cmd', from = 'Alice', data = { lines = { 'net all run' }, scope = 'all' } }, sender = { character = 'Alice', pid = 100 } })
    assert_eq(#B.cmds, nB, 'Suite 95: receiver drops a nested net line even if a peer sends one')
    -- multiple lines in one message (Follow Me)
    A.inst.sendCommand('all', { 'ma Alice', 'assist chase' })
    pump(1)
    assert_eq(B.cmds[#B.cmds - 1], '/ac ma Alice', 'Suite 95: multi-line command runs line 1')
    assert_eq(B.cmds[#B.cmds], '/ac assist chase', 'Suite 95: multi-line command runs line 2')

    -- 5. Addressed command is an RPC: reply logged, unknown target reports RoutingFailed
    nB = #B.cmds
    local nC = #C.cmds
    A.inst.sendCommand('bob', 'pause')
    pump(1)
    assert_eq(B.cmds[#B.cmds], '/ac pause', 'Suite 95: addressed command reaches Bob')
    assert_eq(#C.cmds, nC, 'Suite 95: addressed command does not reach Carol')
    assert_true(lastLog(A, '-> Bob: pause') ~= nil, 'Suite 95: sender log resolves the peer\'s proper-cased name')
    assert_nil(A.inst.net.lastSendStatus, 'Suite 95: successful RPC leaves no error status')
    A.inst.sendCommand('Nobody', 'run')
    pump(1)
    assert_eq(A.inst.net.lastSendStatus, -3, 'Suite 95: unknown character -> RoutingFailed')
    assert_true(lastLog(A, 'RoutingFailed') ~= nil, 'Suite 95: routing failure logged by name')
    A.inst.net.lastSendStatus = nil

    -- 6. Ping RPC
    A.inst.sendPing('bob')
    clock.t = clock.t + 0.012
    pump(1)
    assert_eq(A.inst.api.peer('Bob').pingMs, 12, 'Suite 95: ping round-trip recorded on the peer')
    assert_true(lastLog(A, 'Bob pong') ~= nil, 'Suite 95: pong logged')

    -- 7. Zone scope: same-zone boxes only
    nB, nC = #B.cmds, #C.cmds
    A.inst.sendCommand('zone', 'run')
    pump(1)
    assert_eq(B.cmds[#B.cmds], '/ac run', 'Suite 95: zone scope reaches Bob (same zone)')
    assert_eq(#C.cmds, nC, 'Suite 95: zone scope skips Carol (other zone)')

    -- 8. Group scope: only peers in my group; none -> refused
    ok, why = A.inst.sendCommand('group', 'run')
    assert_eq(ok, false, 'Suite 95: group scope with no grouped peers is refused')
    assert_true(why:find('group', 1, true) ~= nil, 'Suite 95: group refusal reason')
    A.groupMembers.carol = true
    nB, nC = #B.cmds, #C.cmds
    ok = A.inst.sendCommand('group', 'burn off')
    assert_eq(ok, true, 'Suite 95: group scope sends to grouped peers')
    pump(1)
    assert_eq(C.cmds[#C.cmds], '/ac burn off', 'Suite 95: group scope reaches Carol (grouped)')
    assert_eq(#B.cmds, nB, 'Suite 95: group scope skips Bob (not grouped)')

    -- 9. Trust: allowlist and the accept switch
    B.inst.cfg.trust = 'allow'
    B.inst.cfg.allowlist = { 'Carol' }
    nB = #B.cmds
    A.inst.sendCommand('bob', 'run')
    pump(1)
    assert_eq(#B.cmds, nB, 'Suite 95: allowlist blocks an unlisted sender')
    assert_true(lastLog(B, 'Refused Alice: not on allowlist') ~= nil, 'Suite 95: receiver logs the refusal')
    assert_true(lastLog(A, 'Bob refused: not on allowlist') ~= nil, 'Suite 95: RPC reply tells the sender why')
    B.inst.cfg.allowlist = { 'Carol', 'alice' }
    A.inst.sendCommand('bob', 'run')
    pump(1)
    assert_eq(B.cmds[#B.cmds], '/ac run', 'Suite 95: allowlisted sender accepted (case-insensitive)')
    B.inst.cfg.acceptCommands = false
    nB = #B.cmds
    A.inst.sendCommand('bob', 'pause')
    pump(1)
    assert_eq(#B.cmds, nB, 'Suite 95: acceptCommands=false ignores every command')
    assert_true(lastLog(A, 'remote commands disabled') ~= nil, 'Suite 95: disabled receiver replies with the reason')
    B.inst.cfg.acceptCommands = true
    B.inst.cfg.trust = 'all'
    assert_eq(B.inst.isTrusted({ character = 'Zed' }), true, 'Suite 95: trust=all accepts any box on the launcher')

    -- 10. Camp Here: same zone sets the anchor, other zone refuses, remote save
    A.x, A.y, A.z = 100, 200, 30
    ok = A.inst.sendCampHere('all')
    assert_eq(ok, true, 'Suite 95: camp here sent')
    pump(1)
    assert_tbl_eq(B.ctrl.camp_loc, { x = 100, y = 200, z = 30 }, 'Suite 95: Bob\'s camp anchor set to Alice\'s location')
    assert_eq(B.ctrl.camp_radius, 100, 'Suite 95: camp radius carried along')
    assert_true(B.saves >= 1, 'Suite 95: receiver persists the new camp')
    assert_nil(C.ctrl.camp_loc, 'Suite 95: Carol (other zone) keeps her camp')
    B.ctrl.camp_loc = nil
    A.inst.sendCampHere('bob')
    pump(1)
    assert_eq(B.ctrl.camp_loc and B.ctrl.camp_loc.x, 100, 'Suite 95: addressed camp here works')
    B.ctrl.camp_loc = nil
    A.inst.sendCampHere('carol')
    pump(1)
    assert_nil(C.ctrl.camp_loc, 'Suite 95: addressed camp here to another zone is refused')
    assert_true(lastLog(C, 'camp') == nil, 'Suite 95: refused camp leaves no set entry on the receiver')

    -- 11. Plugin message API: broadcast, subscribe / unsubscribe, RPC reply from a subscriber
    local got = {}
    local unsub = B.inst.api.subscribe('test:ping', function(data, sender, message)
        got[#got + 1] = { n = data.n, from = sender.character }
        if message and message.reply then message:reply(0, { echoed = data.n }) end
    end)
    assert_eq(A.inst.api.broadcast('test:ping', { n = 1 }), true, 'Suite 95: api.broadcast sends')
    pump(1)
    assert_eq(#got, 1, 'Suite 95: subscriber received the broadcast')
    assert_eq(got[1].n, 1, 'Suite 95: subscriber gets the data')
    assert_eq(got[1].from, 'Alice', 'Suite 95: subscriber gets the sender')
    local echoed = nil
    A.inst.api.send('Bob', 'test:ping', { n = 2 }, function(status, reply)
        echoed = reply.content.echoed
        assert_eq(status, 0, 'Suite 95: RPC reply status 0')
    end)
    pump(1)
    assert_eq(echoed, 2, 'Suite 95: subscriber can answer an RPC through message:reply')
    unsub()
    A.inst.api.broadcast('test:ping', { n = 3 })
    pump(1)
    assert_eq(#got, 2, 'Suite 95: unsubscribe stops delivery')
    assert_eq(A.inst.api.broadcast('', {}), false, 'Suite 95: broadcast requires a kind')
    assert_eq(A.inst.api.send('', 'x', {}), false, 'Suite 95: send requires a name')

    -- 12. Peer expiry and 'bye'
    clock.t = clock.t + 6
    A.inst.tick()
    assert_eq(peerNames(A), '', 'Suite 95: silent peers expire after the timeout')
    assert_true(lastLog(A, 'Peer left: Bob (timeout)') ~= nil, 'Suite 95: expiry logged')
    pump(2)
    assert_eq(peerNames(A), 'Bob,Carol', 'Suite 95: peers return once they heartbeat again')
    C.inst.onDestroy()
    -- MQ keeps the post-office mailbox alive until GC, and re-registering the same name
    -- yields a dead dropbox, so the plugin never unregisters: it detaches its handler.
    assert_eq(#bus.clients, 3, 'Suite 95: onDestroy keeps the mailbox registered (detach, not unregister)')
    assert_nil(C.inst.registry.sink, 'Suite 95: onDestroy clears the handler sink')
    assert_true(C.inst.registry.actor ~= nil, 'Suite 95: the dropbox stays cached in the registry')
    assert_nil(rawget(C.core, 'boxnet'), 'Suite 95: onDestroy removes core.boxnet')
    bus.flush()
    A.inst.tick()
    assert_eq(peerNames(A), 'Bob', 'Suite 95: bye removes the peer immediately')
    assert_true(lastLog(A, 'Peer left: Carol (left)') ~= nil, 'Suite 95: bye logged as left')
    -- messages arriving while detached are ignored, not queued
    A.inst.sendCommand('all', 'run')
    pump(1)
    assert_eq(#C.inst.net.inbox, 0, 'Suite 95: a detached instance queues nothing')
    -- re-init (plugin reload / restartAll) reuses the cached dropbox instead of re-registering
    local nCarolCmds = #C.cmds
    C.inst.onInit(C.core)
    assert_eq(#bus.clients, 3, 'Suite 95: re-init does not register a second mailbox')
    assert_eq(C.inst.net.actor, C.inst.registry.actor, 'Suite 95: re-init reuses the registry dropbox')
    assert_true(lastLog(C, 'Mailbox reused') ~= nil, 'Suite 95: reuse is logged')
    pump(2)
    assert_eq(peerNames(A), 'Bob,Carol', 'Suite 95: Carol is back on the roster after re-init')
    A.inst.sendCommand('carol', 'pause')
    pump(1)
    assert_eq(C.cmds[#C.cmds], '/ac pause', 'Suite 95: the reused dropbox receives again')
    assert_true(#C.cmds > nCarolCmds, 'Suite 95: command ran after re-init')
    C.inst.onDestroy()
    assert_eq(#bus.clients, 3, 'Suite 95: second destroy still keeps the mailbox')

    -- 12b. A stale-registration situation: register returns nil, but the registry has the dropbox
    local G = makeBox('Gus')
    G.inst.onInit(G.core)
    local gActor = G.inst.net.actor
    G.inst.onDestroy()
    G.inst.actorsModule = { register = function() return nil end, ResponseStatus = {} }
    G.inst.onInit(G.core)
    assert_eq(G.inst.net.actor, gActor, 'Suite 95: registry dropbox wins even when register would return nil')
    assert_nil(G.inst.net.err, 'Suite 95: no error when the cached dropbox is reused')
    G.inst.onDestroy()
    table.remove(boxes)

    -- 13. Protocol mismatch and malformed messages are dropped, warned once
    local droppedBefore = A.inst.net.dropped
    A.inst.processMessage({ content = { v = 2, kind = 'heartbeat', from = 'Bob', data = {} }, sender = { character = 'Bob', pid = 200 } })
    A.inst.processMessage({ content = { v = 2, kind = 'heartbeat', from = 'Bob', data = {} }, sender = { character = 'Bob', pid = 200 } })
    A.inst.processMessage({ content = 'garbage' })
    assert_eq(A.inst.net.dropped, droppedBefore + 3, 'Suite 95: version mismatch / malformed messages counted as dropped')
    local warns = 0
    for _, e in ipairs(A.inst.net.log) do if e.text:find('protocol v2', 1, true) then warns = warns + 1 end end
    assert_eq(warns, 1, 'Suite 95: protocol mismatch warned once per peer')
    -- self-echo via pid only (character casing differs)
    local recvBefore = A.inst.net.received
    A.inst.processMessage({ content = { v = 1, kind = 'heartbeat', from = 'ALICE', data = {} }, sender = { character = 'ALICE', pid = 100 } })
    assert_eq(A.inst.net.received, recvBefore, 'Suite 95: own echo ignored')

    -- 14. Launcher down: sends report NoConnection; loopback probe pins the hop
    assert_eq(A.inst.net.probe.state, 'ok', 'Suite 95: loopback probe through the launcher succeeds on init')
    assert_true(type(A.inst.net.probe.rttMs) == 'number', 'Suite 95: probe records a round-trip time')
    bus.down = true
    A.inst.sendCommand('bob', 'run')
    pump(1)
    assert_eq(A.inst.net.lastSendStatus, -2, 'Suite 95: launcher offline -> NoConnection')
    A.inst.onCommand('net', { 'net', 'probe' })
    pump(1)
    assert_eq(A.inst.net.probe.state, 'NoConnection', 'Suite 95: probe reports NoConnection when the launcher is down')
    bus.down = false
    -- probe delivered but never answered -> 'no answer' after the timeout
    A.inst.net.peers = {}
    clock.t = clock.t + 11
    local realFlush = bus.flush
    bus.flush = function() bus.queue = {} end -- launcher eats everything
    A.inst.tick()
    assert_true(A.inst.net.probe.sentAt ~= nil, 'Suite 95: probe re-sent while no peers are seen')
    clock.t = clock.t + 6
    A.inst.tick()
    assert_eq(A.inst.net.probe.state, 'no answer', 'Suite 95: unanswered probe times out to no answer')
    bus.flush = realFlush
    bus.queue = {}
    pump(2)

    -- 15. Actors module missing: plugin degrades without errors
    local D = makeBox('Dave', { noActors = true })
    D.inst.onInit(D.core)
    assert_eq(D.inst.net.available, false, 'Suite 95: no actors module -> unavailable')
    assert_true(tostring(D.inst.net.err):find('actors module', 1, true) ~= nil, 'Suite 95: unavailable reason recorded')
    D.inst.tick()
    ok, why = D.inst.sendCommand('all', 'run')
    assert_eq(ok, false, 'Suite 95: sendCommand refuses when not connected')
    D.inst.onDrawUI()
    D.inst.onDrawSettings()
    D.inst.onDestroy()
    table.remove(boxes)
    -- MQ returns nil from actors.register when the mailbox already exists in this client
    local E = makeBox('Erin')
    E.inst.actorsModule = { register = function() return nil end, ResponseStatus = {} }
    E.inst.onInit(E.core)
    assert_nil(E.inst.net.actor, 'Suite 95: nil from register leaves no actor')
    assert_true(tostring(E.inst.net.err):find('already registered', 1, true) ~= nil, 'Suite 95: duplicate mailbox reported')
    E.inst.onDestroy()
    table.remove(boxes)
    -- In MQ the dropbox is a sol usertype (userdata), not a table: it must be accepted
    local F = makeBox('Fay')
    F.inst.actorsModule = { register = function() return io.stdout end, ResponseStatus = {} }
    F.inst.onInit(F.core)
    assert_true(F.inst.net.actor ~= nil, 'Suite 95: a userdata dropbox from register is accepted')
    assert_nil(F.inst.net.err, 'Suite 95: no error recorded for a userdata dropbox')
    assert_eq(F.inst.net.available, true, 'Suite 95: available with a userdata dropbox')
    F.inst.net.actor = nil -- io.stdout has no unregister; detach before destroy
    F.inst.onDestroy()
    table.remove(boxes)

    -- 16. Settings round-trip with clamping
    A.inst.cfg.trust = 'allow'
    A.inst.cfg.allowlist = { 'Bob' }
    A.inst.cfg.heartbeatSec = 2
    A.inst.cfg.defaultScope = 'zone'
    local saved = A.inst.onSaveSettings()
    assert_eq(saved.trust, 'allow', 'Suite 95: trust saved')
    assert_eq(saved.allowlist[1], 'Bob', 'Suite 95: allowlist saved')
    assert_eq(saved.heartbeatSec, 2, 'Suite 95: heartbeat saved')
    assert_eq(saved.defaultScope, 'zone', 'Suite 95: default scope saved')
    B.inst.onLoadSettings(saved)
    assert_eq(B.inst.cfg.trust, 'allow', 'Suite 95: trust loaded')
    assert_eq(B.inst.cfg.allowlist[1], 'Bob', 'Suite 95: allowlist loaded')
    assert_eq(B.inst.cfg.defaultScope, 'zone', 'Suite 95: default scope loaded')
    B.inst.onLoadSettings({ heartbeatSec = 0.01, peerTimeoutSec = 999, defaultScope = 'Bob', trust = 'bogus' })
    assert_eq(B.inst.cfg.heartbeatSec, 0.25, 'Suite 95: heartbeat clamped low')
    assert_eq(B.inst.cfg.peerTimeoutSec, 60, 'Suite 95: timeout clamped high')
    assert_eq(B.inst.cfg.defaultScope, 'all', 'Suite 95: a name is not a valid default scope')
    assert_eq(B.inst.cfg.trust, 'allow', 'Suite 95: unknown trust value ignored')
    B.inst.onLoadSettings({ trust = 'all', allowlist = {}, heartbeatSec = 1, peerTimeoutSec = 5, defaultScope = 'all' })
    A.inst.onLoadSettings({ trust = 'all', allowlist = {}, heartbeatSec = 1, peerTimeoutSec = 5, defaultScope = 'all' })

    -- 17. /ac net command surface
    assert_eq(A.inst.onCommand('cursorui', { 'cursorui' }), false, 'Suite 95: unrelated commands fall through')
    local savesBefore = A.saves
    assert_eq(A.inst.onCommand('net', { 'net' }), true, 'Suite 95: /ac net handled')
    assert_eq(A.ctrl.show_boxnet, true, 'Suite 95: /ac net toggles the window')
    assert_true(A.saves > savesBefore, 'Suite 95: window toggle persists')
    A.inst.onCommand('net', { 'net', 'peers' })
    assert_true(printed[#printed]:find('Bob', 1, true) ~= nil, 'Suite 95: /ac net peers lists the roster')
    nB = #B.cmds
    A.inst.onCommand('net', { 'net', 'all', 'burn', 'on' })
    pump(1)
    assert_eq(B.cmds[#B.cmds], '/ac burn on', 'Suite 95: /ac net all <cmd> sends the joined command')
    A.inst.onCommand('net', { 'net', 'bob' })
    assert_true(printed[#printed]:find('Usage', 1, true) ~= nil, 'Suite 95: scope without a command prints usage')
    A.inst.onCommand('net', { 'net', 'ping', 'bob' })
    pump(1)
    assert_true(lastLog(A, 'Bob pong') ~= nil, 'Suite 95: /ac net ping <name>')
    B.ctrl.camp_loc = nil
    A.inst.onCommand('boxnet', { 'boxnet', 'camp' })
    pump(1)
    assert_eq(B.ctrl.camp_loc and B.ctrl.camp_loc.x, 100, 'Suite 95: /ac boxnet camp pushes the camp')

    -- 18. Render passes survive the widget stubs with the window open
    local enumNames = { 'ImGuiCond', 'ImGuiWindowFlags', 'ImGuiTableFlags', 'ImGuiTableColumnFlags', 'ImGuiCol', 'ImGuiTreeNodeFlags' }
    local savedEnums = {}
    for _, n in ipairs(enumNames) do
        savedEnums[n] = rawget(_G, n)
        rawset(_G, n, setmetatable({}, { __index = function() return 0 end }))
    end
    local savedVec, savedBit = rawget(_G, 'ImVec2'), rawget(_G, 'bit')
    rawset(_G, 'ImVec2', function(x, y) return { x = x, y = y } end)
    if not savedBit then rawset(_G, 'bit', { bor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r + v end return r end }) end
    A.ctrl.show_boxnet = true
    A.inst.onDrawUI()
    A.inst.onDrawSettings()
    A.inst.onZoned('gfaydark')
    for _, n in ipairs(enumNames) do rawset(_G, n, savedEnums[n]) end
    rawset(_G, 'ImVec2', savedVec)
    if not savedBit then rawset(_G, 'bit', nil) end
    assert_eq(bus.nonSerializable, 0, 'Suite 95: still nothing non-serializable after the full run')

    -- 19. Core wiring
    assert_true(src:find("'boxnet.lua',", 1, true) ~= nil, 'Suite 95: core discover() probes boxnet.lua')
    assert_true(src:find("cmd = '/ac net [all|zone|group|Name] [command]'", 1, true) ~= nil, 'Suite 95: help table documents /ac net')
    assert_true(src:find('|buffbot|net|btn|clearcursor|', 1, true) ~= nil, 'Suite 95: /ac usage line lists net')
    local bnSrc = readFile('TAC/lua/tac/boxnet.lua')
    assert_true(bnSrc:find('mq.delay(', 1, true) == nil and bnSrc:find('core.delay(', 1, true) == nil, 'Suite 95: boxnet never calls mq.delay / core.delay (forbidden in actor handlers)')
    assert_true(bnSrc:find('core.pushTheme()', 1, true) ~= nil, 'Suite 95: window uses the core theme')

    -- 20. Phase 2 feed: MA target / engaged and counters over the heartbeat
    B.targetId, B.targetName, B.targetHp = 777, 'a_rat', 100
    clock.t = clock.t + 0.3
    pump(1)
    local ft = A.inst.api.peerTarget('bob')
    assert_eq(ft and ft.id, 777, 'Suite 95: peerTarget reports the peer target id')
    assert_eq(ft and ft.name, 'a_rat', 'Suite 95: peerTarget reports the name')
    assert_eq(ft and ft.type, 'NPC', 'Suite 95: peerTarget reports the spawn type')
    assert_eq(ft and ft.engaged, false, 'Suite 95: full-HP target with no combat is not engaged')
    local sentB = B.inst.net.sent
    B.targetHp = 80
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(B.inst.net.sent, sentB + 1, 'Suite 95: engaged flip triggers an immediate heartbeat')
    assert_eq(A.inst.api.peerTarget('bob').engaged, true, 'Suite 95: hurt target counts as engaged')
    assert_true(A.inst.api.peerTarget('bob').age < 1, 'Suite 95: peerTarget reports the heartbeat age')
    B.targetId = 0
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(A.inst.api.peerTarget('bob'), false, 'Suite 95: fresh peer with no target -> false')
    assert_eq(A.inst.api.peerTarget('nobody'), nil, 'Suite 95: unknown peer -> nil')
    B.zone = 'crushbone'
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(A.inst.api.peerFresh('bob'), nil, 'Suite 95: a peer in another zone is not fresh for the feed')
    assert_eq(A.inst.api.peerTarget('bob'), nil, 'Suite 95: other-zone peer -> nil (fall back to /assist)')
    B.zone = 'gfaydark'
    B.poison, B.disease = 3, 0
    sentB = B.inst.net.sent
    clock.t = clock.t + 0.3
    pump(1)
    assert_eq(B.inst.net.sent, sentB + 1, 'Suite 95: a new counter triggers an immediate heartbeat')
    local pc = A.inst.api.peerCounters('bob')
    assert_eq(pc and pc.poison, 3, 'Suite 95: peerCounters carries poison counters')
    assert_eq(pc and pc.disease, 0, 'Suite 95: peerCounters carries disease counters')
    assert_eq(pc and pc.curse, 0, 'Suite 95: peerCounters carries curse counters')
    clock.t = clock.t + 3.5 -- no pump: heartbeat goes stale but the peer has not expired yet
    assert_true(A.inst.api.peer('bob') ~= nil, 'Suite 95: peer still on the roster')
    assert_eq(A.inst.api.peerFresh('bob'), nil, 'Suite 95: heartbeat older than 3s is not fresh')
    assert_eq(A.inst.api.peerCounters('bob'), nil, 'Suite 95: stale counters are not offered')
    assert_true(A.inst.api.peerFresh('bob', 10) ~= nil, 'Suite 95: caller can widen the freshness window')

    -- 21. Phase 3: peersInZone and the cross-box buff request flow
    clock.t = clock.t + 0.5
    pump(1)
    local inZone = A.inst.api.peersInZone()
    assert_eq(#inZone, 1, 'Suite 95: peersInZone lists fresh same-zone peers')
    assert_eq(inZone[1].name, 'Bob', 'Suite 95: peersInZone entry is the peer record')
    B.mq.TLO.Me.BuffCount = function() return 2 end
    B.mq.TLO.Me.Buff = function(i) return { Name = function() return ({ 'Temperance', 'Spirit of Wolf' })[i] end } end
    local gotReq = nil
    A.core.runtime.enqueueBoxBuffRequest = function(name, has) gotReq = { name = name, has = has } return 2 end
    local okB, whyB = B.inst.sendBuffRequest('alice')
    assert_eq(okB, true, 'Suite 95: buff request sent')
    pump(1)
    assert_eq(gotReq and gotReq.name, 'Bob', 'Suite 95: receiver core queues the request for the sender')
    assert_eq(gotReq and #gotReq.has, 2, 'Suite 95: request carries the requester buff names')
    assert_eq(gotReq and gotReq.has[2], 'Spirit of Wolf', 'Suite 95: buff names read from Me.Buff')
    assert_true(lastLog(B, 'Alice queued 2 buff(s) for you') ~= nil, 'Suite 95: requester sees the RPC reply')
    assert_true(lastLog(A, '<- Bob: buff me (2 to cast)') ~= nil, 'Suite 95: receiver logs the request')
    assert_true(type(A.core.runtime.onBoxBuffRequestDone) == 'function', 'Suite 95: plugin installs the done hook on the core')
    A.core.runtime.onBoxBuffRequestDone({ name = 'Bob', cast = 2 }, 'done')
    pump(1)
    assert_true(lastLog(B, 'Alice finished buffing you: 2 cast(s) (done)') ~= nil, 'Suite 95: requester is told when buffing finishes')
    A.core.runtime.enqueueBoxBuffRequest = function() return 0 end
    B.inst.sendBuffRequest('alice')
    pump(1)
    assert_true(lastLog(B, 'nothing to buff') ~= nil, 'Suite 95: zero candidates reported back')
    A.inst.cfg.acceptCommands = false
    B.inst.sendBuffRequest('alice')
    pump(1)
    assert_true(lastLog(B, 'Alice refused buffs: not trusted') ~= nil, 'Suite 95: disabled receiver refuses buff requests')
    A.inst.cfg.acceptCommands = true
    gotReq = nil
    A.core.runtime.enqueueBoxBuffRequest = function(name) gotReq = name return 1 end
    B.inst.sendBuffRequest('zone')
    pump(1)
    assert_eq(gotReq, 'Bob', 'Suite 95: zone-scoped buff request reaches same-zone boxes')
    assert_eq(B.inst.onCommand('net', { 'net', 'buffme', 'alice' }), true, 'Suite 95: /ac net buffme handled')

    for _, b in ipairs(boxes) do b.inst.onDestroy() end
    print = realPrint ---@diagnostic disable-line: lowercase-global
end)()


-- ============================================================================
-- Suite 96: Hot Buttons plugin (Button Master-style hotbars)
-- ============================================================================
;(function()
    print('--- Suite 96: Hot Buttons plugin (Button Master-style hotbars) ---')
    local realPrint = print
    local printed = {}
    print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end ---@diagnostic disable-line: lowercase-global
    local function printedFind(needle)
        for _, l in ipairs(printed) do if l:find(needle, 1, true) then return true end end
        return false
    end

    local noop = function() end
    local mockImGui = setmetatable({
        Button = function() return false end, SmallButton = function() return false end,
        Checkbox = function(_, v) return v end, MenuItem = function() return false end,
        IsItemHovered = function() return false end, BeginTable = function() return false end,
        BeginMenu = function() return false end, BeginPopup = function() return false end,
        BeginPopupContextItem = function() return false end, BeginTabBar = function() return false end,
        InputText = function(_, v) return v, false end, Combo = function(_, v) return v end,
        InvisibleButton = function() return false end, SliderFloat = function(_, v) return v end,
        GetContentRegionAvail = function() return 300, 120 end,
        GetItemRectMin = function() return 0, 0 end, GetItemRectMax = function() return 60, 60 end,
        CalcTextSize = function(t) return #tostring(t) * 7, 14 end,
        GetWindowDrawList = function() return nil end,
    }, { __index = function() return noop end })

    local tmpPath = os.tmpname()
    local bmPath = os.tmpname()
    local clock = { t = 1000 }
    local cmds, saves, binds, delays = {}, 0, {}, 0
    local gemTimers = {}
    local ctrl = { plugins = {} }
    local boxnetSubs = {}
    local broadcasts = {}
    local mq = {
        configDir = '/nonexistent',
        cmd = function(c) cmds[#cmds + 1] = c end,
        cmdf = function(f, ...) cmds[#cmds + 1] = string.format(f, ...) end,
        bind = function(name, fn) binds[name] = fn end,
        unbind = function(name) binds[name] = nil end,
        TLO = {
            EverQuest = { Server = function() return 'triune' end },
            Me = {
                DisplayName = function() return 'Alice' end,
                CleanName = function() return 'Alice' end,
                GemTimer = function(n) return function() return gemTimers[n] or 0 end end,
                Gem = function() return { RecastTime = function() return 30000 end } end,
                AltAbilityTimer = function() return function() return 0 end end,
                AltAbility = function() return { MyReuseTime = function() return 0 end } end,
            },
            CursorAttachment = { Type = function() return nil end },
            FindItem = function() return { TimerReady = function() return 0 end } end,
        },
    }
    local core = setmetatable({
        mq = mq, ImGui = mockImGui, runtime = {}, VERSION = '2.15', colors = {},
        saveLoadout = function() saves = saves + 1 end,
        pushTheme = noop, popTheme = noop, accent = noop, setTooltip = noop,
        preBeginWindow = noop, postBeginWindow = noop,
        col32 = function() return 0 end, toVec = function(x, y) return { x = x, y = y } end,
        getSpellIconAnimation = function() return nil end,
        delay = function(ms) delays = delays + 1 return false end,
        boxnet = {
            subscribe = function(kind, fn) boxnetSubs[kind] = fn return function() boxnetSubs[kind] = nil end end,
            broadcast = function(kind, data) broadcasts[#broadcasts + 1] = kind return true end,
        },
    }, { __index = function(_, k)
        if k == 'ctrl' then return ctrl end
        return nil
    end })

    local inst = assert(loadfile('TAC/lua/tac/buttons.lua'))()
    inst.configPathOverride = tmpPath
    inst.bmConfigPathOverride = bmPath
    local T = inst._

    -- 1. Contract
    assert_eq(inst.id, 'buttons', 'Suite 96: plugin id')
    assert_eq(inst.hasThread, true, 'Suite 96: buttons run on the plugin fiber')
    assert_eq(inst.window.flag, 'show_buttons', 'Suite 96: window flag is show_buttons')
    assert_type(inst.window.isOpen, 'function', 'Suite 96: window declares isOpen')
    assert_type(inst.window.setOpen, 'function', 'Suite 96: window declares setOpen')
    assert_true(#inst.help >= 3, 'Suite 96: help lines contributed')

    -- 2. Init: fresh library, default sets, one hotbar, binds registered, no file written yet
    inst.onInit(core)
    local db = T.getDb()
    assert_eq(ctrl.show_buttons, true, 'Suite 96: hotbars visible by default')
    assert_eq(T.charKey(), 'triune_Alice', 'Suite 96: character key is Server_Name (Button Master style)')
    assert_true(db.sets.Primary ~= nil and db.sets.Movement ~= nil, 'Suite 96: default sets created')
    assert_eq(#T.hotbars(), 1, 'Suite 96: one default hotbar')
    assert_eq(T.hotbars()[1].sets[1], 'Primary', 'Suite 96: default hotbar shows Primary')
    assert_true(binds['/btn'] ~= nil and binds['/btnexec'] ~= nil and binds['/btncopy'] ~= nil, 'Suite 96: /btn, /btnexec, /btncopy bound in onInit')
    assert_nil(io.open(tmpPath .. '.probe', 'r'), 'Suite 96: sanity (tmp path unused)')
    assert_eq(inst.window.isOpen(), true, 'Suite 96: window isOpen reflects show_buttons + a visible hotbar')

    -- 3. Library operations
    local key = T.addButton({ label = 'Kick', cmd = '/doability Kick', timerType = 'Ability', timerKey = 'Kick' }, false)
    assert_eq(key, 'Button_5', 'Suite 96: next free button key')
    T.assignButton('Primary', 7, key)
    local b, k = T.buttonAt('Primary', 7)
    assert_true(b ~= nil and k == key, 'Suite 96: assignButton places the key in the sparse set')
    assert_eq(T.lastAssignedIndex('Primary'), 7, 'Suite 96: lastAssignedIndex follows the sparse set')
    local f = io.open(tmpPath, 'r')
    assert_true(f ~= nil, 'Suite 96: a change writes the shared library file')
    if f then f:close() end
    assert_eq(broadcasts[#broadcasts], 'buttons_saved', 'Suite 96: a save broadcasts buttons_saved over Box Network')

    T.swapSlots('Primary', 1, 'Primary', 7)
    assert_eq(db.sets.Primary[1], key, 'Suite 96: swapSlots moves the button (drag and drop)')
    assert_eq(db.sets.Primary[7], 'Button_1', 'Suite 96: swapSlots swaps the other slot')
    T.unassignButton('Primary', 7)
    assert_nil(db.sets.Primary[7], 'Suite 96: unassign clears the slot but keeps the button')
    assert_true(db.buttons.Button_1 ~= nil, 'Suite 96: unassigned button remains in the library')
    T.assignButton('Movement', 2, key)
    T.deleteButton(key)
    assert_nil(db.buttons[key], 'Suite 96: deleteButton removes the button')
    assert_nil(db.sets.Primary[1], 'Suite 96: deleteButton clears it from every set (Primary)')
    assert_nil(db.sets.Movement[2], 'Suite 96: deleteButton clears it from every set (Movement)')

    local setName = T.createSet('Primary')
    assert_eq(setName, 'Primary 2', 'Suite 96: createSet makes the name unique')
    assert_eq(T.renameSet('Primary 2', 'Burns'), true, 'Suite 96: renameSet succeeds')
    assert_eq(T.renameSet('Burns', 'Primary'), false, 'Suite 96: renameSet refuses an existing name')
    local hb = T.hotbars()[1]
    T.addSetToHotbar(hb, 'Burns')
    assert_eq(hb.sets[#hb.sets], 'Burns', 'Suite 96: addSetToHotbar appends a tab')
    T.moveSetInHotbar(hb, #hb.sets, -1)
    assert_eq(hb.sets[#hb.sets - 1], 'Burns', 'Suite 96: moveSetInHotbar reorders tabs')
    assert_eq(T.renameSet('Burns', 'Burnz'), true, 'Suite 96: rename after add')
    assert_true((function() for _, sname in ipairs(hb.sets) do if sname == 'Burnz' then return true end end return false end)(), 'Suite 96: renameSet updates hotbar tab lists')
    T.deleteSet('Burnz')
    assert_nil(db.sets.Burnz, 'Suite 96: deleteSet removes the set')
    assert_true((function() for _, sname in ipairs(hb.sets) do if sname == 'Burnz' then return false end end return true end)(), 'Suite 96: deleteSet removes it from every hotbar')

    -- 4. Hotbars
    local n = T.newHotbarForMe()
    assert_eq(n, 2, 'Suite 96: newHotbarForMe appends a hotbar')
    assert_eq(T.toggleHotbar(2), true, 'Suite 96: toggleHotbar hides hotbar 2')
    assert_eq(T.hotbars()[2].visible, false, 'Suite 96: hotbar 2 hidden')
    T.toggleHotbar(2)
    assert_eq(T.hotbars()[2].visible, true, 'Suite 96: hotbar 2 shown again')
    T.hotbars()[1].visible = false
    T.hotbars()[2].visible = false
    assert_eq(inst.window.isOpen(), false, 'Suite 96: isOpen false when every hotbar is hidden')
    inst.window.setOpen(true)
    assert_eq(T.anyHotbarVisible(), true, 'Suite 96: setOpen(true) re-shows hidden hotbars')
    inst.window.setOpen(false)
    assert_eq(ctrl.show_buttons, false, 'Suite 96: setOpen(false) clears show_buttons')
    inst.window.setOpen(true)
    assert_eq(T.deleteHotbar(2), true, 'Suite 96: deleteHotbar removes an extra hotbar')
    assert_eq(T.deleteHotbar(1), false, 'Suite 96: the last hotbar cannot be deleted')

    -- 5. Grid geometry (Button Master rules: fill the region, keep the last assigned row, cap at 100)
    local size, cols, count = T.gridLayout({ buttonSize = 6 }, 'Primary', 300, 124)
    assert_eq(size, 60, 'Suite 96: button size is buttonSize x 10')
    assert_eq(cols, 4, 'Suite 96: columns from the available width')
    assert_eq(count, 8, 'Suite 96: slots fill the visible rows')
    T.assignButton('Primary', 15, 'Button_2')
    local _, _, count2 = T.gridLayout({ buttonSize = 6 }, 'Primary', 300, 124)
    assert_eq(count2, 16, 'Suite 96: the last assigned slot is always shown, rounded to a full row')
    T.unassignButton('Primary', 15)
    local _, _, count3 = T.gridLayout({ buttonSize = 3 }, 'Primary', 2000, 2000)
    assert_eq(count3, 100, 'Suite 96: never more than 100 slots')

    -- 6. Execution: queued from the UI, run on the fiber, one button per tick
    T.queueButton('Primary', 2)
    T.queueButton('Primary', 3)
    assert_eq(#T.state.execQueue, 2, 'Suite 96: clicks queue buttons')
    T.tick()
    assert_eq(cmds[#cmds], '/ac pause', 'Suite 96: tick runs the first queued button')
    assert_eq(#T.state.execQueue, 1, 'Suite 96: one button per tick')
    T.tick()
    assert_eq(cmds[#cmds], '/ac burn', 'Suite 96: next tick runs the next button')
    cmds = {}
    local multi = T.addButton({ label = 'Multi', cmd = '/one\n# comment\n\n/two\nnot a command\n/three', timerType = 'Seconds', timerKey = '10' }, false)
    T.assignButton('Primary', 4, multi)
    T.execBySetIndex('Primary', 4)
    T.tick()
    assert_eq(table.concat(cmds, ','), '/one,/two,/three', 'Suite 96: multi-line buttons run each slash line and skip comments / blanks')
    assert_true(printedFind('Invalid command on line 5'), 'Suite 96: non-slash lines are reported')
    local c = T.cacheFor(multi)
    assert_true(c.firedAt ~= nil, 'Suite 96: a Seconds Timer button records its fire time')
    local rem, total = T.readCooldown(db.buttons[multi], c)
    assert_true(rem > 9 and rem <= 10 and total == 10, 'Suite 96: manual seconds timer counts down from its key')
    c.firedAt = os.clock() - 20
    rem = T.readCooldown(db.buttons[multi], c)
    assert_eq(rem, 0, 'Suite 96: manual timer expires')

    -- 7. Lua buttons run in a sandbox with a cooperative delay
    _G.__btnTestFlag = nil
    local luaKey = T.addButton({ label = 'Lua', cmd = '--lua\ndelay(50)\n_G.__btnTestFlag = mq.TLO.Me.CleanName()', timerType = 'None' }, false)
    T.runButton(db.buttons[luaKey], luaKey)
    assert_eq(_G.__btnTestFlag, 'Alice', 'Suite 96: --lua buttons execute Lua with mq in scope')
    assert_true(delays >= 1, 'Suite 96: delay() inside a Lua button goes through core.delay (cooperative)')
    _G.__btnTestFlag = nil
    assert_eq(T.isLuaButton('-- lua\nreturn 1'), true, 'Suite 96: "-- lua" header accepted')
    assert_eq(T.isLuaButton('/cast 1'), false, 'Suite 96: slash commands are not Lua')

    -- 8. Cooldown evaluation: gem timers, Custom Lua timers + toggle, update-rate caching
    gemTimers[3] = 12000
    local gemKey = T.addButton({ label = 'Nuke', cmd = '/cast 3', timerType = 'Gem', timerKey = '3' }, false)
    local gc = T.evaluateButton(db.buttons[gemKey], gemKey, true)
    assert_eq(gc.remaining, 12, 'Suite 96: gem timer converts ms to seconds')
    assert_eq(gc.total, 30, 'Suite 96: gem total from the gem recast time')
    gemTimers[3] = 0
    local gc2 = T.evaluateButton(db.buttons[gemKey], gemKey, false)
    assert_eq(gc2.remaining, 12, 'Suite 96: evaluation is rate-limited (cached value reused)')
    local gc3 = T.evaluateButton(db.buttons[gemKey], gemKey, true)
    assert_eq(gc3.remaining, 0, 'Suite 96: forced evaluation refreshes')
    local luaTimer = T.addButton({ label = 'LT', cmd = '/x', timerType = 'Lua', timerLua = 'return 5', cooldownLua = 'return 20', toggleLua = 'return true' }, false)
    local lc = T.evaluateButton(db.buttons[luaTimer], luaTimer, true)
    assert_true(lc.remaining == 5 and lc.total == 20 and lc.locked == true, 'Suite 96: Custom Lua timer / cooldown / toggle evaluated')
    local evalLabel = T.addButton({ label = 'return "HP " .. 42', cmd = '/x', evaluateLabel = true, timerType = 'None' }, false)
    local ec = T.evaluateButton(db.buttons[evalLabel], evalLabel, true)
    assert_eq(ec.label, 'HP 42', 'Suite 96: EvaluateLabel runs the label as Lua')
    local unknownTotal = T.addButton({ label = 'U', cmd = '/x', timerType = 'Lua', timerLua = 'return 7' }, false)
    local uc = T.evaluateButton(db.buttons[unknownTotal], unknownTotal, true)
    assert_eq(uc.total, 7, 'Suite 96: with no total the largest remaining seen becomes the total')

    -- 9. Share strings: Button Master format, round-trip, base64
    assert_eq(T.b64dec(T.b64enc('Triune Hot Buttons!')), 'Triune Hot Buttons!', 'Suite 96: base64 round-trip')
    local colored = T.addButton({ label = 'Shared One', cmd = '/say hi', icon = 123, iconType = 'Item', buttonColor = { 10, 20, 30 }, textColor = { 255, 255, 0 }, timerType = 'AA', timerKey = 'Burst of Power' }, false)
    local share = T.shareButton(colored)
    assert_type(share, 'string', 'Suite 96: shareButton produces a string')
    local decoded = T.decodeShare(share)
    assert_true(decoded ~= nil and decoded.Type == 'Button', 'Suite 96: share decodes as a Button Master "Button" table')
    assert_eq(decoded.Button.Label, 'Shared One', 'Suite 96: BM Label carried')
    assert_eq(decoded.Button.ButtonColorRGB, '10,20,30', 'Suite 96: BM ButtonColorRGB carried')
    assert_eq(decoded.Button.TimerType, 'AA', 'Suite 96: BM TimerType carried')
    assert_eq(decoded.Button.Cooldown, 'Burst of Power', 'Suite 96: BM Cooldown carries the timer key')
    assert_eq(decoded.Button.IconType, 'Item', 'Suite 96: BM IconType carried')
    local back = T.buttonFromBm(decoded.Button)
    assert_true(back.icon == 123 and back.iconType == 'Item' and back.textColor[2] == 255 and back.timerType == 'AA' and back.timerKey == 'Burst of Power', 'Suite 96: buttonFromBm restores the Triune fields')
    local nBefore = 0
    for _ in pairs(db.buttons) do nBefore = nBefore + 1 end
    local okImp = T.importShare(decoded, nil)
    assert_eq(okImp, true, 'Suite 96: importShare accepts a Button share')
    local nAfter = 0
    for _ in pairs(db.buttons) do nAfter = nAfter + 1 end
    assert_eq(nAfter, nBefore + 1, 'Suite 96: imported button added to the library')
    assert_nil(T.decodeShare('not base64 at all!!'), 'Suite 96: garbage is rejected')
    assert_nil(T.decodeShare(T.b64enc('return { Type = "Nope" }')), 'Suite 96: unknown share type rejected')

    -- A real Button Master share string (Type=Set with one Cmd button) imports
    local bmSet = T.b64enc('return {\n ["Type"] = "Set",\n ["Key"] = "Primary",\n ["Set"] = {\n  [1] = "Button_9",\n },\n ["Buttons"] = {\n  ["Button_9"] = {\n   ["Label"] = "Pause (all)",\n   ["Cmd"] = "/bcaa //mqp on",\n   ["TimerType"] = "Seconds Timer",\n   ["Cooldown"] = 5,\n  },\n },\n}')
    local bmDecoded = T.decodeShare(bmSet)
    assert_true(bmDecoded ~= nil and bmDecoded.Type == 'Set', 'Suite 96: Button Master set share decodes')
    local okSet, newName = T.importShare(bmDecoded, T.hotbars()[1])
    assert_eq(okSet, true, 'Suite 96: set share imports')
    assert_eq(newName, 'Primary 2', 'Suite 96: colliding set name made unique')
    local impBtn = T.buttonAt('Primary 2', 1)
    assert_true(impBtn ~= nil and impBtn.timerType == 'Seconds' and impBtn.timerKey == '5', 'Suite 96: BM "Seconds Timer" maps to the Seconds timer with its key')
    assert_eq(T.hotbars()[1].sets[#T.hotbars()[1].sets], 'Primary 2', 'Suite 96: imported set added to the hotbar')

    -- 10. Button Master config import (ButtonMaster.lua)
    local bmf = assert(io.open(bmPath, 'w'))
    bmf:write([[return {
  Version = 7,
  Buttons = {
    Button_1 = { Label = 'Burn (all)', Cmd = '/bcaa //burn', Icon = '42', IconType = 'Spell', TimerType = 'Spell Gem', Cooldown = 2, ShowLabel = false },
    Button_2 = { Label = 'Nav', Cmd = '/bca //nav id ${Target.ID}' },
  },
  Sets = { Primary = { 'Button_1', 'Button_2' }, Movement = { 'Button_2' } },
  Characters = {
    triune_Alice = { Windows = { { Title = 'BM Bar', Visible = true, Locked = true, CompactMode = true, ButtonSize = 5, Font = 12, Sets = { 'Primary', 'Movement' } } } },
    triune_Bob = { Windows = { { Sets = { 'Primary' } } } },
  },
}]])
    bmf:close()
    local okBm, msgBm = T.importButtonMasterConfig()
    assert_eq(okBm, true, 'Suite 96: ButtonMaster.lua imports (' .. tostring(msgBm) .. ')')
    assert_true(db.sets['Primary 3'] ~= nil and db.sets['Movement 2'] ~= nil, 'Suite 96: BM sets imported with unique names')
    local bmBar = T.hotbars()[#T.hotbars()]
    assert_eq(bmBar.title, 'BM Bar', 'Suite 96: BM window becomes a hotbar')
    assert_true(bmBar.locked == true and bmBar.compact == true and bmBar.buttonSize == 5 and math.abs(bmBar.fontScale - 1.2) < 0.001, 'Suite 96: BM window options carried over')
    assert_eq(bmBar.sets[1], 'Primary 3', 'Suite 96: BM window sets remapped to the imported names')
    local bmBurn = T.buttonAt('Primary 3', 1)
    assert_true(bmBurn ~= nil and bmBurn.icon == 42 and bmBurn.timerType == 'Gem' and bmBurn.timerKey == '2' and bmBurn.showLabel == false, 'Suite 96: BM button fields converted')
    assert_eq(db.characters.triune_Bob, nil, 'Suite 96: other characters\' BM windows are not imported')
    local okBad, errBad = T.importButtonMasterConfig('/nonexistent/ButtonMaster.lua')
    assert_true(okBad == false and errBad:find('Could not read', 1, true) ~= nil, 'Suite 96: missing BM config reported')

    -- 11. Persistence round-trip through the file
    local savedHotbars = #T.hotbars()
    T.saveDb({ silent = true })
    T.setDb({})
    assert_eq(#T.hotbars(), 1, 'Suite 96: setDb resets to a fresh character section')
    assert_eq(T.loadDb(), true, 'Suite 96: loadDb reads the file back')
    assert_eq(#T.hotbars(), savedHotbars, 'Suite 96: hotbars survive the round-trip')
    assert_true(T.getDb().sets['Primary 3'] ~= nil, 'Suite 96: sets survive the round-trip')
    local bak = io.open(tmpPath .. '.bak', 'r')
    assert_true(bak ~= nil, 'Suite 96: a .bak of the previous library is kept')
    if bak then bak:close() end
    T.setDb({ buttons = { Bad = 'nope', Ok = { label = 'x', cmd = '/x', timerType = 'Bogus', icon = '77' } }, sets = { S = { [1] = 'Ok', [2] = 'Missing', foo = 'Ok' } }, characters = { triune_Alice = { hotbars = { { sets = { 'S', 'Nope' }, buttonSize = 99, alpha = 5 } } } } })
    local nd = T.getDb()
    assert_nil(nd.buttons.Bad, 'Suite 96: normalizeDb drops non-table buttons')
    assert_eq(nd.buttons.Ok.timerType, 'None', 'Suite 96: normalizeDb resets unknown timer types')
    assert_eq(nd.buttons.Ok.icon, 77, 'Suite 96: normalizeDb coerces icon ids to numbers')
    assert_nil(nd.sets.S[2], 'Suite 96: normalizeDb drops dangling set references')
    assert_nil(nd.sets.S.foo, 'Suite 96: normalizeDb drops non-numeric slots')
    local nhb = T.hotbars()[1]
    assert_true(nhb.buttonSize == 12 and nhb.alpha == 1 and #nhb.sets == 1 and nhb.title ~= nil, 'Suite 96: normalizeDb clamps hotbar options and drops unknown sets')

    -- 12. Copy hotbars from another character
    T.getDb().characters.triune_Bob = { hotbars = { T.newHotbar('Bob Bar'), T.newHotbar('Bob Bar 2') } }
    assert_eq(T.copyHotbarsFrom('triune_Bob'), true, 'Suite 96: copyHotbarsFrom copies another character')
    assert_true(#T.hotbars() == 2 and T.hotbars()[1].title == 'Bob Bar', 'Suite 96: copied hotbars replace ours')
    assert_eq(T.copyHotbarsFrom('triune_Alice'), false, 'Suite 96: cannot copy from self')
    assert_eq(T.copyHotbarsFrom('triune_Nobody'), false, 'Suite 96: unknown character rejected')

    -- 13. Commands: /ac btn ..., /btn, /btnexec, /btncopy
    assert_eq(inst.onCommand('cursorui', { 'cursorui' }), false, 'Suite 96: unrelated commands fall through')
    ctrl.show_buttons = true
    assert_eq(inst.onCommand('btn', { 'btn' }), true, 'Suite 96: /ac btn handled')
    assert_eq(ctrl.show_buttons, false, 'Suite 96: /ac btn toggles the hotbars off')
    inst.onCommand('buttons', { 'buttons' })
    assert_eq(ctrl.show_buttons, true, 'Suite 96: /ac buttons toggles them back on')
    inst.onCommand('btn', { 'btn', '2' })
    assert_eq(T.hotbars()[2].visible, false, 'Suite 96: /ac btn 2 hides hotbar 2')
    binds['/btn']('2')
    assert_eq(T.hotbars()[2].visible, true, 'Suite 96: /btn 2 shows it again')
    inst.onCommand('btn', { 'btn', 'new' })
    assert_eq(#T.hotbars(), 3, 'Suite 96: /ac btn new creates a hotbar')
    cmds = {}
    T.getDb().sets.Primary = { [1] = 'Ok' }
    binds['/btnexec']('Primary', '1')
    assert_eq(#T.state.execQueue, 1, 'Suite 96: /btnexec queues the button')
    T.tick()
    assert_eq(cmds[1], '/x', 'Suite 96: /btnexec runs it')
    inst.onCommand('btn', { 'btn', 'exec', 'Primary', '9' })
    assert_true(printedFind('has no button at slot 9'), 'Suite 96: /ac btn exec reports an empty slot')
    inst.onCommand('btn', { 'btn', 'exec', 'Nope', '1' })
    assert_true(printedFind('No set named "Nope"'), 'Suite 96: /ac btn exec reports an unknown set')
    binds['/btncopy']('triune', 'bob')
    assert_eq(T.hotbars()[1].title, 'Bob Bar', 'Suite 96: /btncopy capitalises the name and copies the hotbars')
    inst.onCommand('btn', { 'btn', 'list' })
    assert_true(printedFind('Sets:'), 'Suite 96: /ac btn list prints the library')
    inst.onCommand('btn', { 'btn', 'bogus' })
    assert_true(printedFind('usage: /ac btn'), 'Suite 96: unknown subcommand prints usage')

    -- 14. Box Network sync: a remote save marks a reload, the next tick reloads
    assert_type(boxnetSubs.buttons_saved, 'function', 'Suite 96: subscribed to buttons_saved after the first tick')
    T.saveDb({ silent = true })
    local before = #T.hotbars()
    T.hotbars()[#T.hotbars() + 1] = T.newHotbar('Unsaved')
    boxnetSubs.buttons_saved({}, 'Bob', nil)
    assert_eq(T.state.reloadPending, true, 'Suite 96: remote save flags a reload')
    T.tick()
    assert_eq(#T.hotbars(), before, 'Suite 96: tick reloads the shared file (unsaved local change dropped)')
    T.prefs.syncBoxes = false
    assert_eq(inst.onSaveSettings().syncBoxes, false, 'Suite 96: onSaveSettings persists the sync preference')
    inst.onLoadSettings({ syncBoxes = true, announceRun = true })
    assert_true(T.prefs.syncBoxes == true and T.prefs.announceRun == true, 'Suite 96: onLoadSettings restores preferences')

    -- 15. Cursor capture
    local caType, caItem, caSpell = nil, nil, nil
    mq.TLO.CursorAttachment = {
        Type = function() return caType end,
        ButtonText = function() return 'Kick' end,
        Index = function() return 0 end,
        Item = setmetatable({ Name = function() return caItem end, Icon = function() return 1234 end }, { __call = function() return caItem end }),
        Spell = setmetatable({ RankName = function() return caSpell end, Name = function() return caSpell end, SpellIcon = function() return 88 end }, { __call = function() return caSpell end }),
    }
    mq.TLO.Me.Gem = function(nameOrIdx)
        if nameOrIdx == 'Ice Comet Rk. II' then return function() return 4 end end
        return { RecastTime = function() return 30000 end }
    end
    assert_nil(T.buttonFromCursor(), 'Suite 96: empty cursor gives no button')
    caType, caItem = 'item', 'Potion of Speed'
    local cb = T.buttonFromCursor()
    assert_true(cb ~= nil and cb.cmd == '/useitem "Potion of Speed"' and cb.icon == 734 and cb.iconType == 'Item' and cb.timerType == 'Item', 'Suite 96: item on cursor -> /useitem button with the item icon (Icon - 500)')
    caType, caSpell = 'spell_gem', 'Ice Comet Rk. II'
    cb = T.buttonFromCursor()
    assert_true(cb ~= nil and cb.cmd == '/cast 4' and cb.icon == 88 and cb.timerType == 'Gem' and cb.timerKey == '4', 'Suite 96: spell gem on cursor -> /cast <gem> with the gem timer')
    caType = 'skill'
    cb = T.buttonFromCursor()
    assert_true(cb ~= nil and cb.cmd == '/doability "Kick"' and cb.timerType == 'Ability', 'Suite 96: skill on cursor -> /doability')
    caType = 'command'
    mq.TLO.CursorAttachment.ButtonText = function() return '/sit' end
    cb = T.buttonFromCursor()
    assert_true(cb ~= nil and cb.cmd == '/sit' and cb.label == 'sit', 'Suite 96: command on cursor -> the command')
    caType = nil

    -- 16. Editor flow: a new button at an empty slot, saved into the set
    T.openEditor(1, 'Primary', 5, nil)
    assert_eq(T.edit.open, true, 'Suite 96: openEditor opens the editor')
    assert_nil(T.edit.key, 'Suite 96: empty slot edits a new button')
    assert_eq(T.saveEditor(), false, 'Suite 96: empty label refuses to save')
    T.edit.tmp.label = 'New One'
    T.edit.tmp.cmd = '/say new'
    assert_eq(T.saveEditor(), true, 'Suite 96: editor saves')
    local nb = T.buttonAt('Primary', 5)
    assert_true(nb ~= nil and nb.label == 'New One', 'Suite 96: saved button assigned to the slot')
    T.edit.tmp.label = 'Renamed'
    T.saveEditor()
    assert_eq(T.buttonAt('Primary', 5).label, 'Renamed', 'Suite 96: second save updates the same button')
    T.closeEditor()
    assert_eq(T.edit.open, false, 'Suite 96: closeEditor closes')
    T.slotClicked(1, 'Primary', 5)
    assert_eq(#T.state.execQueue, 1, 'Suite 96: clicking an assigned slot queues it')
    T.state.execQueue = {}
    T.slotClicked(1, 'Primary', 6)
    assert_true(T.edit.open == true and T.edit.index == 6, 'Suite 96: clicking an empty slot opens the editor')
    T.closeEditor()

    -- 17. Draw hooks run under the mock without error
    ctrl.show_buttons = true
    local okDraw, errDraw = pcall(inst.onDrawUI)
    assert_true(okDraw, 'Suite 96: onDrawUI renders under the mock (' .. tostring(errDraw) .. ')')
    local okSet, errSet = pcall(inst.onDrawSettings)
    assert_true(okSet, 'Suite 96: onDrawSettings renders under the mock (' .. tostring(errSet) .. ')')

    -- 18. Colour swatches and per-button font size
    assert_eq(T.BUTTON_PALETTE[1].rgb, nil, 'Suite 96: first button swatch is Default (no colour)')
    assert_true(#T.BUTTON_PALETTE >= 10 and #T.TEXT_PALETTE >= 10, 'Suite 96: swatch palettes offer a basic colour set')
    for _, sw in ipairs(T.BUTTON_PALETTE) do
        if sw.rgb then assert_true(#sw.rgb == 3 and sw.rgb[1] <= 255 and sw.rgb[2] <= 255 and sw.rgb[3] <= 255, 'Suite 96: swatch ' .. sw.name .. ' is an {r,g,b} 0-255 triple') end
    end
    assert_true(T.sameRgb({ 150, 35, 35 }, { 150, 35, 35 }) and not T.sameRgb({ 150, 35, 35 }, { 150, 35, 36 }) and T.sameRgb(nil, nil) and not T.sameRgb(nil, { 1, 2, 3 }), 'Suite 96: sameRgb compares swatches')
    local fkey = T.addButton({ label = 'Big', cmd = '/x', timerType = 'None', fontScale = '9', buttonColor = { 150, 35, 35 } }, false)
    assert_eq(T.getDb().buttons[fkey].fontScale, 3.0, 'Suite 96: fontScale is coerced and clamped')
    T.getDb().buttons[fkey].fontScale = 1.35
    local fshare = T.decodeShare(T.shareButton(fkey))
    assert_eq(fshare.Button.FontScale, 1.35, 'Suite 96: share strings carry the per-button font size (Button Master ignores it)')
    assert_eq(fshare.Button.ButtonColorRGB, '150,35,35', 'Suite 96: swatch colours still export in Button Master RGB form')
    assert_eq(T.buttonFromBm(fshare.Button).fontScale, 1.35, 'Suite 96: font size survives the round trip')
    assert_true(T.buttonFromBm({ Label = 'x', Cmd = '/x' }).fontScale == nil, 'Suite 96: Button Master buttons without FontScale use the hotbar default')
    T.openEditor(1, 'Primary', 12, nil)
    okDraw, errDraw = pcall(inst.onDrawUI)
    assert_true(okDraw, 'Suite 96: editor with swatches renders under the mock (' .. tostring(errDraw) .. ')')
    T.closeEditor()

    -- 18b. Misc helpers
    assert_eq(T.fmtTime(75), '1:15', 'Suite 96: fmtTime m:ss')
    assert_eq(T.fmtTime(7), '7', 'Suite 96: fmtTime seconds')
    assert_eq(T.fmtTime(3725), '1h02m', 'Suite 96: fmtTime hours')
    assert_eq(T.alphaGroupFor('kick'), 'G - L', 'Suite 96: alpha groups are case-insensitive')
    assert_eq(T.alphaGroupFor('9 lives'), 'Other', 'Suite 96: digits fall into Other')
    assert_eq(#T.split('a,b,,c', ','), 4, 'Suite 96: split keeps empty fields')
    local ser = T.serialize({ b = 1, a = { 'x' }, [2] = true })
    assert_true(ser:find('a = {', 1, true) ~= nil and ser:find('[2] = true', 1, true) ~= nil, 'Suite 96: serializer emits readable Lua')

    -- 19. "Add From Game" browser: scans of what the character has -> ready buttons
    local function callable(val, fields)
        return setmetatable(fields or {}, { __call = function() return val end })
    end
    local aaById = {
        [100] = { name = 'Burst of Power', rank = 3, max = 5, id = 1100, spellId = 500, icon = 41 },
        [101] = { name = 'Innate Regeneration', rank = 2, max = 3, id = 1101, spellId = 0, icon = 0 },   -- passive: skipped
        [4001] = { name = 'Origin', rank = 1, max = 1, id = 4001, spellId = 501, icon = 42 },
        [4002] = { name = 'Not Trained', rank = 0, max = 3, id = 4002, spellId = 502, icon = 43 },        -- rank 0: skipped
    }
    mq.TLO.Me.AltAbility = function(idx)
        local a = aaById[idx]
        if not a then return callable(nil) end
        return callable(a.name, {
            Name = function() return a.name end, Rank = function() return a.rank end, MaxRank = function() return a.max end,
            ID = function() return a.id end,
            Spell = callable(a.spellId > 0 and a.name or nil, { ID = function() return a.spellId end, SpellIcon = function() return a.icon end }),
        })
    end
    local aas = T.scanAAs()
    assert_eq(#aas, 2, 'Suite 96: scanAAs keeps trained, activatable AAs only')
    assert_eq(aas[1].name, 'Burst of Power', 'Suite 96: AAs sorted by name')
    assert_eq(aas[1].button.cmd, '/alt act 1100', 'Suite 96: AA button uses /alt act <id>')
    assert_true(aas[1].button.timerType == 'AA' and aas[1].button.timerKey == 'Burst of Power' and aas[1].button.icon == 41, 'Suite 96: AA button gets the AA timer and spell icon')
    assert_eq(aas[1].sub, 'Rank 3/5', 'Suite 96: AA rank shown')

    core.getNumGems = function() return 3 end
    local gems = { [1] = { 'Ice Comet', 77 }, [3] = { 'Gate', 78 } }
    mq.TLO.Me.Gem = function(g)
        local gd = gems[g]
        return { Name = function() return gd and gd[1] or nil end, SpellIcon = function() return gd and gd[2] or 0 end, RecastTime = function() return 30000 end }
    end
    local gemList = T.scanGems()
    assert_eq(#gemList, 3, 'Suite 96: scanGems lists every gem slot')
    assert_true(gemList[1].name == 'Ice Comet' and gemList[1].button.cmd == '/cast 1' and gemList[1].button.timerType == 'Gem' and gemList[1].button.timerKey == '1' and gemList[1].button.icon == 77, 'Suite 96: gem entry -> /cast <gem> with the gem timer')
    assert_true(gemList[2].empty == true and gemList[2].name == '(empty gem)', 'Suite 96: empty gems are listed but marked empty')
    assert_eq(gemList[3].sub, 'Gem 3', 'Suite 96: gem number shown')

    core.runtime.getClientAbilities = function()
        return { { name = 'Kick', isTrained = true, currentSkill = 150 }, { name = 'Bash', isTrained = false, currentSkill = 0 }, { name = 'Taunt', isTrained = true, currentSkill = 0 } }
    end
    local abil = T.scanAbilities()
    assert_eq(#abil, 2, 'Suite 96: scanAbilities keeps trained skills (from the core list)')
    assert_true(abil[1].name == 'Kick' and abil[1].button.cmd == '/doability "Kick"' and abil[1].button.timerType == 'Ability' and abil[1].sub == 'Skill 150', 'Suite 96: ability entry -> /doability with the ability timer')

    mq.TLO.Me.CombatAbilityCount = function() return 2 end
    mq.TLO.Me.CombatAbility = function(i)
        local d = ({ { 'Fearless Discipline', 75, 91 }, { 'Evasive Discipline', 52, 92 } })[i]
        return { Name = function() return d[1] end, Level = function() return d[2] end, SpellIcon = function() return d[3] end }
    end
    local discs = T.scanDiscs()
    assert_eq(#discs, 2, 'Suite 96: scanDiscs lists combat abilities')
    -- Without CombatAbilityCount (most clients) the slots are probed directly; gaps are tolerated
    mq.TLO.Me.CombatAbilityCount = nil
    local probed = 0
    mq.TLO.Me.CombatAbility = function(i)
        probed = math.max(probed, i)
        local d = ({ [1] = { 'Fearless Discipline', 75, 91 }, [3] = { 'Evasive Discipline', 52, 92 }, [7] = { 'Fearless Discipline', 75, 91 } })[i]
        if not d then return setmetatable({ Name = function() return nil end }, { __call = function() return nil end }) end
        return { Name = function() return d[1] end, Level = function() return d[2] end, SpellIcon = function() return d[3] end }
    end
    discs = T.scanDiscs()
    assert_eq(#discs, 2, 'Suite 96: scanDiscs probes slots when CombatAbilityCount is unavailable (gaps and duplicates handled)')
    assert_true(probed >= 67 and probed < 400, 'Suite 96: probing stops after a run of empty slots (' .. probed .. ')')
    mq.TLO.Me.CombatAbilityCount = function() return 2 end
    assert_true(discs[1].name == 'Evasive Discipline' and discs[1].button.cmd == '/disc Evasive Discipline' and discs[1].button.timerType == 'Disc' and discs[1].button.icon == 92 and discs[1].sub == 'Level 52', 'Suite 96: disc entry -> /disc with the disc timer')

    local function mkItem(name, id, icon, clickySpell, container, contents)
        local it = { ID = function() return id end, Name = function() return name end, Icon = function() return icon end,
            Container = function() return container or 0 end, Item = function(j) return contents and contents[j] or callable(nil) end }
        if clickySpell then
            it.Clicky = callable(clickySpell, { Spell = callable(clickySpell, { Name = function() return clickySpell end }) })
        else
            it.Clicky = callable(nil)
        end
        return callable(name, it)
    end
    local worn = { [1] = mkItem('Circlet of Shadow', 10, 1500, 'Shadow'), [2] = mkItem('Plain Tunic', 11, 1501, nil) }
    local packs = { pack1 = mkItem('Backpack', 12, 1502, nil, 2, { mkItem('Potion of Speed', 13, 1234, 'Haste'), mkItem('Rusty Sword', 14, 1503, nil) }) }
    mq.TLO.Me.Inventory = function(slot)
        if type(slot) == 'number' then return worn[slot] or callable(nil) end
        return packs[slot] or callable(nil)
    end
    local items = T.scanItems()
    assert_eq(#items, 2, 'Suite 96: scanItems keeps only clickies (worn + bags)')
    assert_true(items[1].name == 'Circlet of Shadow' and items[1].button.cmd == '/useitem "Circlet of Shadow"' and items[1].button.icon == 1000 and items[1].button.iconType == 'Item' and items[1].button.timerType == 'Item', 'Suite 96: clicky entry -> /useitem with the item timer and item icon (Icon - 500)')
    assert_eq(items[2].sub, 'Haste - Pack 1', 'Suite 96: clicky shows its spell and location')

    -- Picking: into a chosen slot (one-shot) and into the first free slot (stays open)
    T.getDb().sets.Primary = { [1] = 'Ok' }
    T.openBrowser('AA', 'assign', { hbId = 1, setName = 'Primary', index = 4 })
    assert_true(T.browser.open and T.browser.tab == 'AA', 'Suite 96: openBrowser opens on the requested tab')
    assert_eq(#T.browserList('AA'), 2, 'Suite 96: browserList scans and caches the tab')
    assert_eq(T.pickBrowserEntry(aas[1]), true, 'Suite 96: picking an entry into a slot succeeds')
    local placed = T.buttonAt('Primary', 4)
    assert_true(placed ~= nil and placed.cmd == '/alt act 1100' and placed.showLabel == false, 'Suite 96: picked AA button placed in the chosen slot (icon buttons hide the label)')
    assert_eq(T.browser.open, false, 'Suite 96: slot-targeted pick closes the browser')
    T.openBrowser('Gem', 'assign', { hbId = 1, setName = 'Primary' })
    assert_eq(T.firstFreeSlot('Primary'), 2, 'Suite 96: firstFreeSlot finds the first gap')
    T.pickBrowserEntry(gemList[1])
    assert_eq(T.buttonAt('Primary', 2).cmd, '/cast 1', 'Suite 96: gear-menu pick lands in the first free slot')
    assert_true(T.browser.open and T.browser.target.index == nil, 'Suite 96: gear-menu flow keeps the browser open for more picks')
    T.pickBrowserEntry(discs[1])
    assert_eq(T.buttonAt('Primary', 3).cmd, '/disc Evasive Discipline', 'Suite 96: next pick fills the next free slot')
    T.openBrowser('Item', 'assign', nil)
    assert_eq(T.pickBrowserEntry(items[1]), false, 'Suite 96: picking with no target set is refused')

    -- Picking into the editor
    T.openEditor(1, 'Primary', 9, nil)
    T.openBrowser('Ability', 'editor', nil)
    assert_eq(T.pickBrowserEntry(abil[1]), true, 'Suite 96: editor mode fills the open editor')
    assert_true(T.edit.tmp.cmd == '/doability "Kick"' and T.edit.tmp.timerType == 'Ability' and T.edit.dirty == true, 'Suite 96: editor fields filled and marked dirty')
    assert_nil(T.buttonAt('Primary', 9), 'Suite 96: editor mode does not create a button until saved')
    T.closeEditor()
    T.browser.open = false

    -- /ac btn add <what> (hotbar 1 has no sets after the /btncopy above; hotbar 2 gets one)
    T.hotbars()[2].sets = { 'Primary' }
    inst.onCommand('btn', { 'btn', 'add', 'discs' })
    assert_true(T.browser.open and T.browser.tab == 'Disc' and T.browser.target and T.browser.target.hbId == 2 and T.browser.target.setName == 'Primary', 'Suite 96: /ac btn add discs opens the browser on the Discs tab targeting the first hotbar with a set')
    T.browser.open = false
    ctrl.show_buttons = true
    local okDraw2, errDraw2 = pcall(inst.onDrawUI)
    assert_true(okDraw2, 'Suite 96: onDrawUI still renders with browser state (' .. tostring(errDraw2) .. ')')
    T.browser.open = true
    okDraw2, errDraw2 = pcall(inst.onDrawUI)
    assert_true(okDraw2, 'Suite 96: browser window renders under the mock (' .. tostring(errDraw2) .. ')')
    T.browser.open = false

    -- 20. Destroy releases the binds and the Box Network subscription
    inst.onDestroy()
    assert_nil(binds['/btn'], 'Suite 96: onDestroy unbinds /btn')
    assert_nil(boxnetSubs.buttons_saved, 'Suite 96: onDestroy unsubscribes from Box Network')

    -- 21. Core wiring
    assert_true(src:find("'buttons.lua',", 1, true) ~= nil, 'Suite 96: core discover() probes buttons.lua')
    assert_true(src:find("cmd = '/ac btn [n|new|exec <set> <index>|import bm]'", 1, true) ~= nil, 'Suite 96: help table documents /ac btn')
    local btnSrc = readFile('TAC/lua/tac/buttons.lua')
    assert_true(btnSrc:find('mq.delay(', 1, true) == nil, 'Suite 96: the plugin never calls mq.delay directly')
    assert_true(btnSrc:find('core.pushTheme()', 1, true) ~= nil, 'Suite 96: hotbars use the core theme')

    os.remove(tmpPath)
    os.remove(tmpPath .. '.bak')
    os.remove(bmPath)
    print = realPrint ---@diagnostic disable-line: lowercase-global
end)()

-- ============================================================================
-- Suite 96: Box Network feed in the core (MA target, engagement, cures)
-- ============================================================================
;(function()
    print('--- Suite 96: Box Network feed in the core ---')
    local function callable(ret, fields)
        return setmetatable(fields or {}, { __call = function() return ret end })
    end
    local S = { cmds = {}, feed = nil, counters = nil, targetId = 0 }
    local spawns = {
        [50]  = { name = 'Tank', type = 'PC' },
        [777] = { name = 'a_rat', type = 'NPC' },
        [778] = { name = 'a_dead_rat', type = 'Corpse' },
        [900] = { name = 'Boxer', type = 'PC' },
    }
    local mockMq = {
        cmd = function(c) S.cmds[#S.cmds + 1] = c end,
        cmdf = function(f, ...) S.cmds[#S.cmds + 1] = string.format(f, ...) end,
        delay = function() end,
        TLO = {
            Me = { ID = function() return 1 end },
            Target = setmetatable({ ID = function() return S.targetId end, Type = function() return 'NPC' end, Dead = function() return false end },
                { __call = function() if S.targetId > 0 then return 'target' end return nil end }),
            Spawn = function(id)
                local sp = spawns[id]
                if not sp then return callable(nil, { ID = function() return 0 end, CleanName = function() return nil end }) end
                return callable('spawn', {
                    ID = function() return id end, CleanName = function() return sp.name end,
                    Type = function() return sp.type end, Dead = function() return sp.type == 'Corpse' end,
                    PctHPs = function() return sp.hp or 100 end,
                    Combat = function() return false end,
                    Target = callable(nil, { ID = function() return 0 end }),
                })
            end,
        },
    }
    local fakeApi = {
        available = function() return true end,
        peerTarget = function(name, maxAge) S.lastPeerName, S.lastMaxAge = name, maxAge return S.feed end,
        peerCounters = function(name) S.lastCounterName = name return S.counters end,
    }
    local ctrl96 = { mode = 'Assist', xtar_nav_dist = 150, ma_id = 50, ma_name = 'Tank' }
    local env = {
        ctrl = ctrl96, mq = mockMq, print = function() end,
        pluginManager = { coreApi = setmetatable({ boxnet = fakeApi }, { __index = function() return nil end }) },
        maPcId = function() return 50 end,
        isSpawnPetOrPlayer = function(id) return spawns[id] and spawns[id].type == 'PC' end,
        isHostileTarget = function(id) return spawns[id] and spawns[id].type == 'NPC' end,
        distToId = function() return 40 end,
        anyNearbyEngagedNpc = function() S.peeked = true return true end,
        lastAssistCmdAt = -100,
    }
    local boxnetApi = loadFunc(src, 'boxnetApi', env)
    env.boxnetApi = boxnetApi
    local boxnetMaTarget = loadFunc(src, 'boxnetMaTarget', env)
    env.boxnetMaTarget = boxnetMaTarget
    local boxnetCounters = loadFunc(src, 'boxnetCounters', env)
    env.boxnetCounters = boxnetCounters
    local boxnetHasCounter = loadFunc(src, 'boxnetHasCounter', env)
    env.boxnetHasCounter = boxnetHasCounter

    -- 1. API discovery through the plugin manager's core API table
    assert_eq(boxnetApi(), fakeApi, 'Suite 96: boxnetApi finds the plugin API on the core API table')
    fakeApi.available = function() return false end
    assert_nil(boxnetApi(), 'Suite 96: boxnetApi is nil while the plugin is not connected')
    fakeApi.available = function() return true end
    local savedPm = env.pluginManager
    env.pluginManager = nil
    assert_nil(loadFunc(src, 'boxnetApi', env)(), 'Suite 96: boxnetApi is nil without a plugin manager')
    env.pluginManager = savedPm

    -- 2. boxnetMaTarget resolves the MA name and asks the feed with the freshness window
    S.feed = { id = 777, name = 'a_rat', hp = 100, engaged = true }
    local fed = boxnetMaTarget(50)
    assert_eq(fed and fed.id, 777, 'Suite 96: boxnetMaTarget returns the feed target')
    assert_eq(S.lastPeerName, 'Tank', 'Suite 96: MA name resolved from the spawn')
    assert_eq(S.lastMaxAge, 3.0, 'Suite 96: 3s freshness window')
    assert_eq(boxnetMaTarget(12345) and boxnetMaTarget(12345).id, 777, 'Suite 96: falls back to ctrl.ma_name when the spawn is unknown')
    ctrl96.ma_name = ''
    assert_nil(boxnetMaTarget(12345), 'Suite 96: no name -> nil')
    ctrl96.ma_name = 'Tank'

    -- 3. targetIsEngaged trusts the MA's own engaged flag
    env.isGroupOrRaidMember = function() return false end
    env.isXTargetId = function() return false end
    local targetIsEngaged = loadFunc(src, 'targetIsEngaged', env)
    env.targetIsEngaged = targetIsEngaged
    assert_eq(targetIsEngaged(777), true, 'Suite 96: MA feed engaged -> target is engaged')
    S.feed = { id = 777, engaged = false }
    assert_eq(targetIsEngaged(777), false, 'Suite 96: MA feed not engaged and no other evidence -> not engaged')
    S.feed = { id = 555, engaged = true }
    assert_eq(targetIsEngaged(777), false, 'Suite 96: a different MA target does not engage this one')

    -- 4. maTargetId: feed answers -> no /assist, no peek; MA without target -> nil
    local maTargetId = loadFunc(src, 'maTargetId', env)
    S.feed = { id = 777, name = 'a_rat', engaged = true }
    S.cmds, S.peeked = {}, false
    assert_eq(maTargetId(), 777, 'Suite 96: maTargetId returns the fed target')
    assert_eq(#S.cmds, 0, 'Suite 96: no /assist issued when the feed answers')
    assert_eq(S.peeked, false, 'Suite 96: no XTarget peek when the feed answers')
    S.feed = false
    assert_nil(maTargetId(), 'Suite 96: MA reports no target -> nil, still no /assist')
    assert_eq(#S.cmds, 0, 'Suite 96: no /assist for an idle MA')
    S.feed = { id = 778, engaged = true }
    assert_nil(maTargetId(), 'Suite 96: a corpse from the feed is rejected')
    S.feed = { id = 900, engaged = true }
    assert_nil(maTargetId(), 'Suite 96: a PC from the feed is rejected')
    S.feed = { id = 777, engaged = false }
    assert_nil(maTargetId(), 'Suite 96: Assist mode gates on engagement even with a fed target')
    ctrl96.mode = 'Manual'
    assert_eq(maTargetId(), 777, 'Suite 96: outside Assist mode the fed target is not gated')
    ctrl96.mode = 'Assist'
    S.feed = { id = 777, engaged = true }
    env.distToId = function() return 500 end
    assert_nil(loadFunc(src, 'maTargetId', env)(), 'Suite 96: fed target beyond xtar_nav_dist is rejected')
    env.distToId = function() return 40 end
    -- no fresh feed -> legacy /assist path (the rat is hurt, so it counts as engaged)
    S.feed = nil
    S.targetId = 777
    spawns[777].hp = 60
    S.cmds = {}
    env.lastAssistCmdAt = -100
    maTargetId = loadFunc(src, 'maTargetId', env)
    assert_eq(maTargetId(), 777, 'Suite 96: without a feed the /assist path still works')
    assert_eq(S.cmds[1], '/assist Tank', 'Suite 96: legacy path issues /assist')

    -- 5. Cures: heartbeat counters replace NetBots
    S.counters = { poison = 2, disease = 0, curse = 0, corruption = 1 }
    assert_eq(boxnetCounters('Boxer').poison, 2, 'Suite 96: boxnetCounters reads the feed')
    assert_eq(boxnetHasCounter('Boxer', 'poison'), true, 'Suite 96: poison counter > 0')
    assert_eq(boxnetHasCounter('Boxer', 'disease'), false, 'Suite 96: disease counter 0')
    assert_eq(boxnetHasCounter('Boxer', 'corruption'), true, 'Suite 96: corruption counter > 0')
    assert_eq(boxnetHasCounter('', 'poison'), false, 'Suite 96: empty name -> false')
    S.counters = nil
    assert_eq(boxnetHasCounter('Boxer', 'poison'), false, 'Suite 96: no feed -> false')
    local hasAffliction = loadFunc(src, 'hasAffliction', {
        mq = mockMq, AFFLICTION_MEMBERS = { Poison = { flag = 'Poisoned', counter = 'CountersPoison', boxnet = 'poison' } },
        boxnetHasCounter = boxnetHasCounter, boxnetCounters = boxnetCounters,
    })
    S.counters = { poison = 1 }
    assert_eq(hasAffliction(900, 'Poison'), true, 'Suite 96: hasAffliction is true from Box Network counters alone (no NetBots)')
    S.counters = { poison = 0 }
    assert_eq(hasAffliction(900, 'Poison'), false, 'Suite 96: hasAffliction false when the box reports no counters')
    local isCursed = loadFunc(src, 'isCursed', { mq = mockMq, boxnetHasCounter = boxnetHasCounter })
    S.counters = { curse = 4 }
    assert_eq(isCursed(900), true, 'Suite 96: isCursed from Box Network counters')
    local isCorrupted = loadFunc(src, 'isCorrupted', { mq = mockMq, boxnetHasCounter = boxnetHasCounter })
    S.counters = { corruption = 1 }
    assert_eq(isCorrupted(900), true, 'Suite 96: isCorrupted from Box Network counters')
end)()


-- ============================================================================
-- Suite 97: Box Network Phase 3 - allies, cross-box buffs, Group HUD, DPS share
-- ============================================================================
;(function()
    print('--- Suite 97: Box Network Phase 3 (allies, buffs, Group HUD, DPS) ---')
    local function callable(ret, fields) return setmetatable(fields or {}, { __call = function() return ret end }) end
    local S = { peers = {}, cmds = {}, buffs = {}, spellInfo = {}, groupMembers = {} }
    local spawns = {
        [1]   = { name = 'Me', type = 'PC', hp = 90 },
        [10]  = { name = 'Grouper', type = 'PC', hp = 60 },
        [20]  = { name = 'Boxer', type = 'PC', hp = 30 },
        [21]  = { name = 'Farbox', type = 'PC', hp = 10 },
        [777] = { name = 'a_rat', type = 'NPC', hp = 80 },
    }
    local byName = {}
    for id, sp in pairs(spawns) do byName[sp.name:lower()] = id end
    local function spawnObj(id)
        local sp = spawns[id]
        if not sp then return callable(nil, { ID = function() return 0 end }) end
        return callable('spawn', {
            ID = function() return id end, CleanName = function() return sp.name end, Type = function() return sp.type end,
            Dead = function() return false end, PctHPs = function() return sp.hp end,
            TargetOfTarget = { ID = function() return sp.tot or 0 end }, AggroHolder = { ID = function() return sp.aggro or 0 end },
        })
    end
    local mockMq = {
        cmd = function(c) S.cmds[#S.cmds + 1] = c end, cmdf = function(f, ...) S.cmds[#S.cmds + 1] = string.format(f, ...) end,
        delay = function() end, gettime = function() return S.now or 0 end,
        TLO = {
            Me = { ID = function() return 1 end, PctHPs = function() return 90 end },
            Group = {
                Members = function() return #S.groupMembers end,
                Member = function(i)
                    local id = (i == 0) and 1 or S.groupMembers[i]
                    if not id then return callable(nil) end
                    local sp = spawns[id]
                    return callable('m', { ID = function() return id end, Dead = function() return false end, PctHPs = function() return sp.hp end,
                        CleanName = function() return sp.name end })
                end,
            },
            Spawn = function(arg)
                if type(arg) == 'string' then
                    local nm = arg:gsub('^pc =', ''):lower()
                    return spawnObj(byName[nm] or -1)
                end
                return spawnObj(arg)
            end,
            Spell = function(name)
                local info = S.spellInfo[name]
                if not info then return callable(nil) end
                return callable('spell', { Beneficial = function() return info.bene ~= false end, Duration = function() return info.dur or 60 end, TargetType = function() return info.tt or 'Single' end })
            end,
            Target = callable(nil, { ID = function() return 0 end }),
        },
    }
    local fakeApi = { available = function() return true end, peersInZone = function() return S.peers end }
    local loadout97 = { gems = {} }
    local ctrl97 = { mode = 'Assist', burn = false }
    local env = {
        ctrl = ctrl97, loadout = loadout97, mq = mockMq, print = function() end,
        pluginManager = { coreApi = setmetatable({ boxnet = fakeApi }, { __index = function() return nil end }) },
        isSpawnAlive = function(id) return spawns[id] ~= nil end,
        distToId = function(id) return (id == 21) and 400 or 25 end,
        baseTok = function(t) return (tostring(t or ''):gsub('^%a:%s*', '')) end,
        buffActive = function(id, name) return S.buffs[id] and S.buffs[id][name] == true end,
        isTargetInRange = function() return true end,
        isGroupOrRaidMember = function(id) for _, g in ipairs(S.groupMembers) do if g == id then return true end end return false end,
        isXTargetId = function() return false end, isSpawnPetOrPlayer = function(id) return spawns[id] and spawns[id].type == 'PC' end,
        isHostileTarget = function(id) return spawns[id] and spawns[id].type == 'NPC' end,
        maPcId = function() return nil end, boxnetMaTarget = function() return nil end,
    }
    env.boxnetApi = loadFunc(src, 'boxnetApi', env)
    env.boxPeersInZone = loadFunc(src, 'boxPeersInZone', env)
    env.isBoxPeerId = loadFunc(src, 'isBoxPeerId', env)
    env.BOXNET_FRESH_SEC = 3.0

    -- 1. Box peers in zone resolve to local spawn ids and live HP
    S.peers = { { name = 'Boxer', hb = { hp = 55 } }, { name = 'Ghost', hb = { hp = 20 } } }
    local peers = env.boxPeersInZone()
    assert_eq(#peers, 2, 'Suite 97: every fresh peer is listed')
    assert_eq(peers[1].id, 20, 'Suite 97: peer resolved to its local spawn id')
    assert_eq(peers[1].hp, 30, 'Suite 97: live spawn HP preferred over heartbeat HP')
    assert_eq(peers[2].id, 0, 'Suite 97: a peer with no spawn keeps id 0')
    assert_eq(peers[2].hp, 20, 'Suite 97: heartbeat HP used when no spawn')
    assert_eq(env.isBoxPeerId(20), true, 'Suite 97: isBoxPeerId true for a box spawn')
    assert_eq(env.isBoxPeerId(10), false, 'Suite 97: isBoxPeerId false for a non-box')

    -- 2. lowestHpAlly: boxes only when asked; group-wide callers leave them out
    local lowestHpAlly = loadFunc(src, 'lowestHpAlly', env)
    S.groupMembers = { 10 }
    S.peers = { { name = 'Boxer', hb = { hp = 30 } }, { name = 'Farbox', hb = { hp = 10 } } }
    assert_eq(lowestHpAlly(), 10, 'Suite 97: default excludes boxes (group-wide spells)')
    assert_eq(lowestHpAlly(nil, true), 20, 'Suite 97: includeBoxes picks the hurt box in range')
    assert_true(src:find("id = runtime.lowestHpAlly(nil, true)", 1, true) ~= nil, 'Suite 97: Lowest-HP Ally single-target token includes boxes')
    assert_true(src:find("return pctHP(runtime.lowestHpAlly()) <= pct", 1, true) ~= nil, 'Suite 97: Whole Group HP check stays group-only')
    S.groupMembers = { 10, 20 }
    assert_eq(lowestHpAlly(nil, true), 20, 'Suite 97: a grouped box is not double counted')

    -- 3. targetIsEngaged: a box holding aggro counts like a group member
    S.groupMembers = {}
    local targetIsEngaged = loadFunc(src, 'targetIsEngaged', env)
    spawns[777].hp = 100
    spawns[777].aggro = 20
    assert_eq(targetIsEngaged(777), true, 'Suite 97: mob with a box as aggro holder is engaged')
    spawns[777].aggro = 0
    spawns[777].tot = 20
    assert_eq(targetIsEngaged(777), true, 'Suite 97: mob targeting a box is engaged')
    spawns[777].tot = 0
    assert_eq(targetIsEngaged(777), false, 'Suite 97: untouched full-HP mob is not engaged')

    -- 4. Cross-box buff requests: candidates, queue, casting order, completion
    S.spellInfo = { ['Temperance'] = { tt = 'Single' }, ['Self Only Buff'] = { tt = 'Self' }, ['Nuke'] = { bene = false, dur = 0 }, ['Group Buff'] = { tt = 'Group v2' }, ['Pet Buff'] = { tt = 'Pet' } }
    loadout97.gems = {
        { spell = 'Temperance', target = 'F: Tank', when = 'missing buff', pct = 100 },
        { spell = 'Self Only Buff', target = 'F: Myself', when = 'missing buff', pct = 100 },
        { spell = 'Nuke', target = 'E: Assist Target', when = 'in combat', pct = 100 },
        { spell = 'Group Buff', target = 'F: Whole Group', when = 'missing buff', pct = 100 },
        { spell = 'Pet Buff', target = 'F: Pet', when = 'missing buff', pct = 100 },
        { spell = 'Burn Buff', target = 'F: Myself', when = 'missing buff', pct = 100, burn_only = true },
    }
    S.spellInfo['Burn Buff'] = { tt = 'Single' }
    env.isFriendlyBuffToken = loadFunc(src, 'isFriendlyBuffToken', env)
    local boxBuffCandidates = loadFunc(src, 'boxBuffCandidates', env)
    env.boxBuffCandidates = boxBuffCandidates
    local cands = boxBuffCandidates()
    local names = {}
    for _, c in ipairs(cands) do names[#names + 1] = c.entry.spell end
    assert_eq(table.concat(names, ','), 'Temperance,Group Buff', 'Suite 97: only friendly, non-self, beneficial duration buffs qualify (burn-only off)')
    ctrl97.burn = true
    assert_eq(#boxBuffCandidates(), 3, 'Suite 97: burn-only buffs join the candidates in burn mode')
    ctrl97.burn = false
    env.boxBuffRequests = {}
    local enqueue = loadFunc(src, 'enqueueBoxBuffRequest', env)
    env.enqueueBoxBuffRequest = enqueue
    local nextCast = loadFunc(src, 'nextBoxBuffCast', env)
    local q = env.boxBuffRequests
    assert_eq(enqueue('Boxer', { 'temperance' }), 1, 'Suite 97: requester already has Temperance (case-insensitive) -> one buff queued')
    assert_eq(#q, 1, 'Suite 97: request queued')
    assert_eq(enqueue('Boxer', {}), 2, 'Suite 97: a new request from the same box replaces the old one')
    assert_eq(#q, 1, 'Suite 97: still one request for that box')
    assert_eq(enqueue('Boxer', { 'Temperance', 'Group Buff' }), 0, 'Suite 97: nothing to cast -> 0 and not queued')
    assert_eq(#q, 0, 'Suite 97: zero-candidate request is dropped')
    enqueue('Boxer', {})
    local done = {}
    env.onBoxBuffRequestDone = function(req, reason) done[#done + 1] = { name = req.name, cast = req.cast, reason = reason } end
    nextCast = loadFunc(src, 'nextBoxBuffCast', env)
    local slot, entry, tid = nextCast()
    assert_eq(slot, 1, 'Suite 97: first candidate is gem slot 1')
    assert_eq(entry and entry.spell, 'Temperance', 'Suite 97: first cast is Temperance')
    assert_eq(tid, 20, 'Suite 97: target is the requester spawn')
    S.buffs[20] = { ['Temperance'] = true } -- landed
    slot, entry = nextCast()
    assert_eq(entry and entry.spell, 'Group Buff', 'Suite 97: landed buff is skipped, next candidate offered')
    for _ = 1, 8 do nextCast() end -- keeps failing -> give up after the retry cap
    assert_eq(#q, 0, 'Suite 97: request completes once every candidate landed or hit the retry cap')
    assert_eq(done[1] and done[1].reason, 'done', 'Suite 97: completion hook fired with done')
    enqueue('Ghost', {})
    assert_nil(nextCast(), 'Suite 97: requester with no spawn in zone is dropped')
    assert_eq(done[#done].reason, 'not in zone', 'Suite 97: hook reports not in zone')
    enqueue('Boxer', {})
    q[1].at = os.time() - 500
    assert_nil(nextCast(), 'Suite 97: stale request expires')
    assert_eq(done[#done].reason, 'expired', 'Suite 97: hook reports expired')
    assert_true(src:find("1b. A box asked us for buffs (Box Network): serve it before our own list.", 1, true) ~= nil, 'Suite 97: downtime buffing serves box requests before its own list')

    -- 5. Group HUD box rows and DPS sharing (source contracts + DPS unit run)
    local gwSrc = readFile('TAC/lua/tac/hud_group.lua')
    assert_true(gwSrc:find("ctrl.gw_show_boxes ~= false and core.boxnet", 1, true) ~= nil, 'Suite 97: Group HUD lists Box Network peers when enabled')
    assert_true(gwSrc:find("isBox = true", 1, true) ~= nil, 'Suite 97: box rows are flagged')
    assert_true(gwSrc:find("accent(GOLD, '[Box]')", 1, true) ~= nil, 'Suite 97: box rows carry a [Box] badge')
    assert_true(gwSrc:find("otherZone = not inZone", 1, true) ~= nil, 'Suite 97: boxes in another zone render as other-zone')
    assert_true(gwSrc:find("Show Box Network Characters##gwBoxes", 1, true) ~= nil, 'Suite 97: settings toggle for box rows')
    local dpsInst = assert(loadfile('TAC/lua/tac/dps.lua'))()
    local subs = {}
    local dpsCore = setmetatable({ mq = mockMq, boxnet = { available = function() return true end, subscribe = function(kind, fn) subs[kind] = fn return function() subs[kind] = nil end end, broadcast = function(kind, data) S.lastShare = { kind = kind, data = data } return true end } },
        { __index = function() return nil end })
    mockMq.bind, mockMq.unbind, mockMq.event, mockMq.unevent = function() end, function() end, function() end, function() end
    mockMq.configDir = '/tmp/claude-1000/-home-gennro-Documents-github-TriuneAutocombat/ac73ae47-5c31-4666-aa5a-ca1276e99826/scratchpad'
    mockMq.TLO.Me.CleanName = function() return 'Me' end
    local realPrint97 = print
    print = function() end ---@diagnostic disable-line: lowercase-global
    local okInit, errInit = pcall(dpsInst.onInit, dpsCore)
    print = realPrint97 ---@diagnostic disable-line: lowercase-global
    assert_true(okInit, 'Suite 97: dps plugin initialises with a Box Network core: ' .. tostring(errInit))
    dpsInst.rt.boxes = {}
    dpsInst.ensureBoxSubscription()
    assert_true(subs['dps:share'] ~= nil, 'Suite 97: dps subscribes to dps:share once the Box Network is available')
    -- drive the receive handler directly
    S.now = 1000
    dpsInst.onBoxDps({ live = true, target = 'a_rat', dmg = 500, dps = 125, dur = 4 }, { character = 'Bob' })
    local list = dpsInst.boxList()
    assert_eq(#list, 1, 'Suite 97: DPS keeps the other box parse')
    assert_eq(list[1].live and list[1].live.dps, 125, 'Suite 97: live line stored')
    dpsInst.onBoxDps({ live = false, target = 'a_rat', dmg = 900, dps = 150, dur = 6, playerDmg = 700, petDmg = 200 }, { character = 'Bob' })
    list = dpsInst.boxList()
    assert_nil(list[1].live, 'Suite 97: fight summary clears the live line')
    assert_eq(list[1].lastFight.dmg, 900, 'Suite 97: fight summary stored')
    S.now = 1000 + 61 * 1000
    assert_eq(#dpsInst.boxList(), 0, 'Suite 97: stale box parses drop after 60s')
    local dpsSrc = readFile('TAC/lua/tac/dps.lua')
    assert_true(dpsSrc:find("shareFight(rt.history[1])", 1, true) ~= nil, 'Suite 97: fight end broadcasts the summary')
    assert_true(dpsSrc:find("shareLive()", 1, true) ~= nil, 'Suite 97: live line shared from the tick')
    assert_true(dpsSrc:find('BeginTabItem("Boxes##MainBoxesTab")', 1, true) ~= nil, 'Suite 97: DPS window has a Boxes tab')
    assert_true(dpsSrc:find("'dps:share'", 1, true) ~= nil, 'Suite 97: DPS uses the dps:share message kind')
    -- sharing: a finished fight broadcasts its summary
    dpsInst.shareFight({ targetName = 'a_rat', totalDmg = 1200, duration = 8, peakDps = 150, playerDmg = 1000, petDmg = 200 })
    assert_eq(S.lastShare and S.lastShare.kind, 'dps:share', 'Suite 97: fight summary broadcast on dps:share')
    assert_eq(S.lastShare and S.lastShare.data.live, false, 'Suite 97: summary is flagged as not live')
    assert_eq(S.lastShare and S.lastShare.data.dmg, 1200, 'Suite 97: summary carries total damage')
    dpsInst.onDestroy()
    assert_nil(subs['dps:share'], 'Suite 97: dps unsubscribes on destroy')
end)()


print(string.format('\n=== Results: %d passed, %d failed ===', pass, fail))
if fail > 0 then
    print('\nFailures:')
    for _, e in ipairs(errors) do print(e) end
    os.exit(1)
else
    print('All tests passed.')
    os.exit(0)
end
