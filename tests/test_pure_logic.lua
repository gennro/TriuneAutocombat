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
            for k, v in pairs(t) do parts[#parts+1] = tostring(k)..'='..tostring(v) end
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
            if line:match('^local function ' .. funcName .. '%s*%(') then
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
-- The extracted code is a `local function X(...) ... end` block;
-- we append `return X` so `loadstring` returns the function itself.
local function loadFunc(src, funcName, env)
    local code = extractFunction(src, funcName)
    code = code .. '\nreturn ' .. funcName

    local chunk, err = loadstring(code, funcName)
    if not chunk then error('loadstring failed for ' .. funcName .. ': ' .. err) end

    -- Merge env onto a copy of _G so standard library is available
    local sandbox = {}
    for k, v in pairs(_G) do sandbox[k] = v end
    if env then
        for k, v in pairs(env) do sandbox[k] = v end
    end
    setfenv(chunk, sandbox)

    local ok, fn = pcall(chunk)
    if not ok then error('pcall failed for ' .. funcName .. ': ' .. tostring(fn)) end
    return fn
end

-- ---------------------------------------------------------------------------
-- Source file path (relative to repo root)
-- ---------------------------------------------------------------------------
local srcPath = 'mq2triune/lua/triune.lua'
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

-- The MQSHORT lookup table (used inside toCanonicalClassAbbr as a local, and
-- referenced by parseClassLine as an upvalue that SHOULD be module-level).
local MQSHORT = {
    WARRIOR = 'War', WAR = 'War', WARRIORS = 'War',
    CLERIC = 'Clr', CLR = 'Clr', CLERICS = 'Clr',
    PALADIN = 'Pal', PAL = 'Pal', PALADINS = 'Pal',
    RANGER = 'Rng', RNG = 'Rng', RANGERS = 'Rng',
    SHADOWKNIGHT = 'SK', SHADOW = 'SK', SHD = 'SK', SK = 'SK', SHADOWKNIGHTS = 'SK',
    DRUID = 'Dru', DRU = 'Dru', DRUIDS = 'Dru',
    MONK = 'Mnk', MNK = 'Mnk', MONKS = 'Mnk',
    BARD = 'Brd', BRD = 'Brd', BARDS = 'Brd',
    ROGUE = 'Rog', ROG = 'Rog', ROGUES = 'Rog',
    SHAMAN = 'Shm', SHM = 'Shm', SHAMANS = 'Shm',
    NECROMANCER = 'Nec', NEC = 'Nec', NECROMANCERS = 'Nec',
    WIZARD = 'Wiz', WIZ = 'Wiz', WIZARDS = 'Wiz',
    MAGICIAN = 'Mag', MAG = 'Mag', MAGICIANS = 'Mag',
    ENCHANTER = 'Enc', ENC = 'Enc', ENCHANTERS = 'Enc',
    BEASTLORD = 'Bst', BST = 'Bst', BEASTLORDS = 'Bst',
    BERSERKER = 'Ber', BER = 'Ber', BERSERKERS = 'Ber',
}

-- ============================================================================
-- 1.  idxOf(tbl, val)
-- ============================================================================
print('--- idxOf ---')
local idxOf = loadFunc(src, 'idxOf', {})

assert_eq(idxOf({'a','b','c'}, 'b'), 2,   'idxOf: find middle element')
assert_eq(idxOf({'a','b','c'}, 'a'), 1,   'idxOf: find first element')
assert_eq(idxOf({'a','b','c'}, 'c'), 3,   'idxOf: find last element')
assert_eq(idxOf({'a','b','c'}, 'z'), 1,   'idxOf: not found returns 1')
assert_eq(idxOf(nil, 'x'),            1,   'idxOf: nil table returns 1')
assert_eq(idxOf({}, 'x'),             1,   'idxOf: empty table returns 1')

-- ============================================================================
-- 2.  toCanonicalClassAbbr(str)
-- ============================================================================
print('--- toCanonicalClassAbbr ---')
local toCanonicalClassAbbr = loadFunc(src, 'toCanonicalClassAbbr',
    { ALL_ABBR = ALL_ABBR, MQSHORT = MQSHORT, idxOf = idxOf })

-- Full names (case-insensitive)
assert_eq(toCanonicalClassAbbr('warrior'),      'War', 'canon: lowercase warrior')
assert_eq(toCanonicalClassAbbr('WARRIOR'),      'War', 'canon: uppercase WARRIOR')
assert_eq(toCanonicalClassAbbr('Warrior'),      'War', 'canon: mixed Warrior')
assert_eq(toCanonicalClassAbbr('Shadow Knight'),'SK',  'canon: Shadow Knight (space)')
assert_eq(toCanonicalClassAbbr('shadowknight'), 'SK',  'canon: shadowknight')
assert_eq(toCanonicalClassAbbr('Necromancer'),  'Nec', 'canon: Necromancer')
assert_eq(toCanonicalClassAbbr('Beastlord'),    'Bst', 'canon: Beastlord')
assert_eq(toCanonicalClassAbbr('Berserker'),    'Ber', 'canon: Berserker')

-- MQ-style 3-letter abbreviations
assert_eq(toCanonicalClassAbbr('WAR'), 'War', 'canon: WAR')
assert_eq(toCanonicalClassAbbr('CLR'), 'Clr', 'canon: CLR')
assert_eq(toCanonicalClassAbbr('PAL'), 'Pal', 'canon: PAL')
assert_eq(toCanonicalClassAbbr('RNG'), 'Rng', 'canon: RNG')
assert_eq(toCanonicalClassAbbr('SHD'), 'SK',  'canon: SHD → SK')
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
assert_eq(toCanonicalClassAbbr('SK'),  'SK',  'canon: SK')

-- Mixed-case canonical form (should pass through if in ALL_ABBR)
assert_eq(toCanonicalClassAbbr('War'), 'War', 'canon: War pass-through')
assert_eq(toCanonicalClassAbbr('Clr'), 'Clr', 'canon: Clr pass-through')

-- Plurals
assert_eq(toCanonicalClassAbbr('Warriors'), 'War', 'canon: Warriors plural')
assert_eq(toCanonicalClassAbbr('Clerics'),  'Clr', 'canon: Clerics plural')

-- Edge cases
assert_nil(toCanonicalClassAbbr(nil),    'canon: nil input')
assert_nil(toCanonicalClassAbbr(''),     'canon: empty string')
assert_nil(toCanonicalClassAbbr('NULL'), 'canon: NULL string')
assert_nil(toCanonicalClassAbbr('nil'),  'canon: "nil" string')

-- ============================================================================
-- 3.  cleanSpellName(name)
-- ============================================================================
print('--- cleanSpellName ---')
local cleanSpellName = loadFunc(src, 'cleanSpellName', {})

assert_eq(cleanSpellName('Complete Heal'),              'Complete Heal',     'clean: no parens')
assert_eq(cleanSpellName('Chloroplast (Group)'),        'Chloroplast',       'clean: strip (Group)')
assert_eq(cleanSpellName('Spirit of Wolf (Spell)'),     'Spirit of Wolf',    'clean: strip (Spell)')
assert_eq(cleanSpellName('  Heal  '),                   'Heal',              'clean: trim whitespace')
assert_eq(cleanSpellName(nil),                          '',                  'clean: nil → empty')
assert_eq(cleanSpellName(42),                           '',                  'clean: number → empty')
assert_eq(cleanSpellName(''),                           '',                  'clean: empty → empty')

-- ============================================================================
-- 4.  normalizeSpellName(name)
-- ============================================================================
print('--- normalizeSpellName ---')
local normalizeSpellName = loadFunc(src, 'normalizeSpellName', {})

assert_eq(normalizeSpellName('Complete Heal'),           'completeheal',      'norm: basic')
assert_eq(normalizeSpellName('Complete Heal Rk. II'),    'completeheal',      'norm: strip Rk. II')
assert_eq(normalizeSpellName('Chloroplast (Group)'),     'chloroplast',       'norm: strip parens')
assert_eq(normalizeSpellName('Spirit of Wolf'),          'spiritofwolf',      'norm: spaces removed')
assert_eq(normalizeSpellName('Nuke Rk.III'),             'nuke',              'norm: Rk.III variant')
assert_eq(normalizeSpellName('Heal (Rk II)'),            'heal',              'norm: (Rk II) in parens')
assert_eq(normalizeSpellName(nil),                       '',                  'norm: nil → empty')
assert_eq(normalizeSpellName(42),                        '',                  'norm: number → empty')
assert_eq(normalizeSpellName(''),                        '',                  'norm: empty → empty')

-- ============================================================================
-- 5.  defaultsForKind(kind, bene)
-- ============================================================================
print('--- defaultsForKind ---')
local defaultsForKind = loadFunc(src, 'defaultsForKind', {})

local function check_defaults(kind, bene, expTarget, expWhen, expPct, label)
    local t, w, p = defaultsForKind(kind, bene)
    assert_eq(t, expTarget, label .. ' target')
    assert_eq(w, expWhen,   label .. ' when')
    assert_eq(p, expPct,    label .. ' pct')
end

check_defaults('heal',     nil,  'F: Myself',           'my HP <=',       75,  'defaults: heal')
check_defaults('buff',     nil,  'F: Myself',           'missing buff',   100, 'defaults: buff')
check_defaults('pet_buff', nil,  'F: Pet',              'missing buff',   100, 'defaults: pet_buff')
check_defaults('pet',      nil,  'F: Myself',           'missing pet',    100, 'defaults: pet')
check_defaults('util',     nil,  'F: Myself',           'always',         100, 'defaults: util')
check_defaults('debuff',   nil,  'E: Current Target',   'target HP <=',   98,  'defaults: debuff')
check_defaults('dot',      nil,  'E: Current Target',   'target HP <=',   98,  'defaults: dot')
check_defaults('dd',       nil,  'E: Current Target',   'target HP <=',   95,  'defaults: dd')
check_defaults(nil,        true, 'F: Myself',           'missing buff',   100, 'defaults: bene=true')
check_defaults(nil,        nil,  'E: Current Target',   'target HP <=',   95,  'defaults: unknown')
check_defaults('bogus',    nil,  'E: Current Target',   'target HP <=',   95,  'defaults: bogus kind')

-- ============================================================================
-- 6.  sanitizeModeConfig(c)
-- ============================================================================
print('--- sanitizeModeConfig ---')
local sanitizeModeConfig = loadFunc(src, 'sanitizeModeConfig',
    { PULL_CON_LIST = PULL_CON_LIST, ctrl = nil })

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
assert_eq(s, 'Hunt',   'sanitize: Hunter → Hunt')

-- Manual Hunter → Manual/Hunt
m, s = smc('Manual Hunter', nil)
assert_eq(m, 'Manual', 'sanitize: Manual Hunter → Manual')
assert_eq(s, 'Hunt',   'sanitize: Manual Hunter → Hunt')

-- Pet Tank → Puller/Hunt
m, s = smc('Pet Tank', nil)
assert_eq(m, 'Puller', 'sanitize: Pet Tank → Puller')
assert_eq(s, 'Hunt',   'sanitize: Pet Tank → Hunt')

-- Pull & Assist → Puller/Camp
m, s = smc('Pull & Assist', nil)
assert_eq(m, 'Puller', 'sanitize: Pull & Assist → Puller')
assert_eq(s, 'Camp',   'sanitize: Pull & Assist → Camp')

-- Chase Assist → Assist/Chase
m, s = smc('Chase Assist', nil)
assert_eq(m, 'Assist', 'sanitize: Chase Assist → Assist')
assert_eq(s, 'Chase',  'sanitize: Chase Assist → Chase')

-- Garrison → Assist/Camp
m, s = smc('Garrison', nil)
assert_eq(m, 'Assist', 'sanitize: Garrison → Assist')
assert_eq(s, 'Camp',   'sanitize: Garrison → Camp')

-- Tank → Assist/Camp
m, s = smc('Tank', nil)
assert_eq(m, 'Assist', 'sanitize: Tank → Assist')
assert_eq(s, 'Camp',   'sanitize: Tank → Camp')

-- Unknown mode → Manual
m, s = smc('BogusMode', nil)
assert_eq(m, 'Manual', 'sanitize: unknown → Manual')
assert_eq(s, 'Hunt',   'sanitize: unknown → default submode Hunt')

-- Valid modes pass through
m, s = smc('Manual', 'Hunt')
assert_eq(m, 'Manual', 'sanitize: Manual stays')

m, s = smc('Puller', 'Hunt')
assert_eq(m, 'Puller', 'sanitize: Puller stays')
assert_eq(s, 'Hunt',   'sanitize: Puller/Hunt stays')

m, s = smc('Puller', 'Camp')
assert_eq(m, 'Puller', 'sanitize: Puller/Camp stays')
assert_eq(s, 'Camp',   'sanitize: Puller/Camp submode stays')

m, s = smc('Assist', 'Chase')
assert_eq(m, 'Assist', 'sanitize: Assist stays')
assert_eq(s, 'Chase',  'sanitize: Assist/Chase stays')

m, s = smc('Assist', 'Backline')
assert_eq(m, 'Assist',   'sanitize: Assist/Backline stays')
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

-- ============================================================================
-- 7.  parseClassLine(text)  — loaded with MQSHORT in scope
-- ============================================================================
print('--- parseClassLine ---')
local parseClassLine = loadFunc(src, 'parseClassLine', { MQSHORT = MQSHORT })

-- Numbered lines (e.g. from inventory window list items)
assert_eq(parseClassLine('1. Warrior'),     'War', 'parse: "1. Warrior"')
assert_eq(parseClassLine('2: Cleric'),      'Clr', 'parse: "2: Cleric"')
assert_eq(parseClassLine('  3  Paladin'),   'Pal', 'parse: "  3  Paladin"')

-- Plain class names
assert_eq(parseClassLine('Ranger'),         'Rng', 'parse: "Ranger"')
assert_eq(parseClassLine('Shadow Knight'),  'SK',  'parse: "Shadow Knight"')
assert_eq(parseClassLine('Necromancer'),    'Nec', 'parse: "Necromancer"')

-- 3-letter codes
assert_eq(parseClassLine('WAR'),            'War', 'parse: "WAR" 3-letter')
assert_eq(parseClassLine('CLR'),            'Clr', 'parse: "CLR" 3-letter')
assert_eq(parseClassLine('SHD'),            'SK',  'parse: "SHD" 3-letter')

-- 2-letter code
assert_eq(parseClassLine('SK'),             'SK',  'parse: "SK" 2-letter')

-- Lines that should return nil
assert_nil(parseClassLine(nil),             'parse: nil')
assert_nil(parseClassLine(''),              'parse: empty')
assert_nil(parseClassLine('NULL'),          'parse: NULL')
assert_nil(parseClassLine('Level 60'),      'parse: "Level 60" filtered')
assert_nil(parseClassLine('LVL 50'),        'parse: "LVL 50" filtered')

-- ============================================================================
-- 8.  defaultCtrl() — shape validation
-- ============================================================================
print('--- defaultCtrl ---')
local defaultCtrl = loadFunc(src, 'defaultCtrl', { PULL_CON_LIST = PULL_CON_LIST })
local dc = defaultCtrl()

-- Check required fields exist and have correct types
local EXPECTED_FIELDS = {
    -- field name            expected type
    { 'running',             'boolean' },
    { 'mode',                'string'  },
    { 'submode',             'string'  },
    { 'pull_style',          'string'  },
    { 'pull_spell',          'string'  },
    { 'pull_spell_gem',      'number'  },
    { 'pull_engage_dist',    'number'  },
    { 'xtar_nav_dist',       'number'  },
    { 'combat_style',        'string'  },
    { 'melee_dist',          'number'  },
    { 'ranged_dist',         'number'  },
    { 'ma_name',             'string'  },
    { 'assist_at',           'number'  },
    { 'chase',               'boolean' },
    { 'chase_dist',          'number'  },
    { 'automem',             'boolean' },
    { 'camp_radius',         'number'  },
    { 'camp_z',              'number'  },
    { 'camp_z_plane',        'number'  },
    { 'hunter_radius',       'number'  },
    { 'hunter_z_plane',      'number'  },
    { 'hunter_z',            'number'  },
    { 'hunter_min_level',    'number'  },
    { 'hunter_max_level',    'number'  },
    { 'hunter_combat_radius','number'  },
    { 'pull_min_level',      'number'  },
    { 'pull_max_level',      'number'  },
    { 'pull_con_filter',     'table'   },
    { 'check_closer_mobs',   'boolean' },
    { 'debug_mode',          'boolean' },
    { 'scribed_only',        'boolean' },
    { 'aa_purchased_only',   'boolean' },
    { 'disc_trained_only',   'boolean' },
    { 'medbreak_enabled',    'boolean' },
    { 'cast_max_retries',    'number'  },
    { 'cast_lockout_sec',    'number'  },
    { 'min_mana_pct',        'number'  },
    { 'pull_min_hp_pct',     'number'  },
    { 'pet_assist_at',       'number'  },
    { 'pet_hold_enabled',    'boolean' },
    { 'show_map_radius',     'boolean' },
    { 'burn',                'boolean' },
    { 'compact',             'boolean' },
    { 'use_waypoints',       'boolean' },
    { 'waypoint_radius',     'number'  },
    { 'waypoint_scan_radius','number'  },
    { 'waypoint_direction',  'number'  },
    { 'waypoint_loop',       'boolean' },
    { 'current_waypoint_idx','number'  },
    { 'waypoints',           'table'   },
}

for _, spec in ipairs(EXPECTED_FIELDS) do
    local field, etype = spec[1], spec[2]
    assert_neq(dc[field], nil, 'defaultCtrl: ' .. field .. ' exists')
    assert_type(dc[field], etype, 'defaultCtrl: ' .. field .. ' is ' .. etype)
end

-- Specific default values
assert_eq(dc.running,  false,   'defaultCtrl: running=false')
assert_eq(dc.mode,     'Manual','defaultCtrl: mode=Manual')
assert_eq(dc.submode,  'Hunt',  'defaultCtrl: submode=Hunt')

-- ============================================================================
-- 9.  isSpecialSkill(name)
-- ============================================================================
print('--- isSpecialSkill ---')
-- SPECIAL_SKILLS is module-level (used as an upvalue by isSpecialSkill AND
-- by UI.drawDiscTab's Special Skills section), so it must be supplied via
-- env here -- same pattern as MQSHORT above.
local SPECIAL_SKILLS = {
    Mnk = { 'Mend' },
}
local isSpecialSkill = loadFunc(src, 'isSpecialSkill', { SPECIAL_SKILLS = SPECIAL_SKILLS })

assert_true(isSpecialSkill('Mend'),        'special: Mend')
assert_eq(isSpecialSkill('Feign Death'), false, 'special: Feign Death is not yet exposed')
assert_eq(isSpecialSkill('Kick'), false,    'special: Kick is not special')
assert_eq(isSpecialSkill(nil), false,       'special: nil')
assert_eq(isSpecialSkill(''), false,        'special: empty')

-- ============================================================================
-- 10. aaTier(sec)
-- ============================================================================
print('--- aaTier ---')
local aaTier = loadFunc(src, 'aaTier', {})

assert_eq(aaTier(5),   'short', 'aaTier: 5s → short')
assert_eq(aaTier(60),  'short', 'aaTier: 60s → short')
assert_eq(aaTier(61),  'mid',   'aaTier: 61s → mid')
assert_eq(aaTier(300), 'mid',   'aaTier: 300s → mid')
assert_eq(aaTier(301), 'burn',  'aaTier: 301s → burn')
assert_eq(aaTier(3600),'burn',  'aaTier: 3600s → burn')

-- ============================================================================
-- 11. fmtSec(s)
-- ============================================================================
print('--- fmtSec ---')
local fmtSec = loadFunc(src, 'fmtSec', {})

assert_eq(fmtSec(5),   '5s',       'fmtSec: 5s')
assert_eq(fmtSec(59),  '59s',      'fmtSec: 59s')
assert_eq(fmtSec(60),  '1m',       'fmtSec: 60s → 1m')
assert_eq(fmtSec(90),  '1m 30s',   'fmtSec: 90s → 1m 30s')
assert_eq(fmtSec(120), '2m',       'fmtSec: 120s → 2m')
assert_eq(fmtSec(3661),'61m 1s',   'fmtSec: 3661s')

-- ============================================================================
-- 12. baseTok(token) — target token normalization
-- ============================================================================
print('--- baseTok ---')
local baseTok = loadFunc(src, 'baseTok', {})

assert_eq(baseTok('F: Myself'),        'Myself',         'baseTok: F: Myself')
assert_eq(baseTok('E: Current Target'),'Current Target',  'baseTok: E: Current Target')
assert_eq(baseTok('F: Pet'),           'Pet',             'baseTok: F: Pet')
assert_eq(baseTok('Target'),           'Current Target',  'baseTok: Target alias')
assert_eq(baseTok('Current Target'),   'Current Target',  'baseTok: Current Target')
assert_eq(baseTok('Self'),             'Myself',          'baseTok: Self alias')
assert_eq(baseTok('Myself'),           'Myself',          'baseTok: Myself')
assert_eq(baseTok(nil),                '',                'baseTok: nil')
assert_eq(baseTok(''),                 '',                'baseTok: empty')

-- ============================================================================
-- 13. normalizeCommandKey(text) — slash command argument normalization
-- ============================================================================
print('--- normalizeCommandKey ---')
local normalizeCommandKey = loadFunc(src, 'normalizeCommandKey', {})

assert_eq(normalizeCommandKey('Manual'),     'manual',     'cmdKey: Manual')
assert_eq(normalizeCommandKey('PULLER'),      'puller',     'cmdKey: PULLER')
assert_eq(normalizeCommandKey('Chase Assist'),'chaseassist','cmdKey: Chase Assist')
assert_eq(normalizeCommandKey('pull & assist'),'pullassist','cmdKey: pull & assist')
assert_eq(normalizeCommandKey(nil),           '',           'cmdKey: nil')
assert_eq(normalizeCommandKey(''),            '',           'cmdKey: empty')

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
    manual = {'Manual','Hunt'}, manualhunter = {'Manual','Hunt'},
    puller = {'Puller',nil},
    hunter = {'Puller','Hunt'}, pethunter = {'Puller','Hunt'}, pettank = {'Puller','Hunt'},
    pull = {'Puller','Camp'}, pullassist = {'Puller','Camp'},
    assist = {'Assist',nil},
    chase = {'Assist','Chase'}, chaseassist = {'Assist','Chase'},
    garrison = {'Assist','Camp'}, tank = {'Assist','Camp'},
    backline = {'Assist','Backline'}, ranged = {'Assist','Backline'},
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

assert_eq(sungKey('Heal', 123),     '123_Heal', 'sungKey: basic')
assert_eq(sungKey('Buff', 0),       '0_Buff',   'sungKey: id 0')
assert_eq(sungKey('Spell', nil),    '0_Spell',  'sungKey: nil id')

-- ============================================================================
-- 16. classPlausible(abbr) — checks if a class abbreviation is valid
-- ============================================================================
print('--- classPlausible ---')
local classPlausible = loadFunc(src, 'classPlausible',
    { ALL_ABBR = ALL_ABBR, DATA = { spells = {} } })

assert_true(classPlausible('War'),  'plausible: War')
assert_true(classPlausible('SK'),   'plausible: SK')
assert_true(classPlausible('Ber'),  'plausible: Ber')
assert_eq(classPlausible('Xyz'), false, 'plausible: Xyz invalid')
assert_eq(classPlausible(nil), false,   'plausible: nil')
assert_eq(classPlausible(42), false,    'plausible: number')

-- ============================================================================
-- 17. serialize(o, f, indent) — round-trip persistence
-- ============================================================================
print('--- serialize ---')
local serialize = loadFunc(src, 'serialize', {})

-- Helper: serialize to string
local function serializeToString(o)
    local buf = {}
    local fakefile = {
        write = function(_, s) buf[#buf+1] = s end
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
assert_eq(extractConName('Guard Hanlon glares at you'),  'Guard Hanlon',  'con: glares')
assert_eq(extractConName('a moss snake regards you'),    'a moss snake',  'con: regards')
assert_eq(extractConName('Merchant looks at you'),       'Merchant',      'con: looks')
assert_eq(extractConName('a_gnoll judges you'),          'a_gnoll',       'con: judges')
assert_nil(extractConName(nil), 'con: nil')
assert_nil(extractConName(''),  'con: empty')

-- ============================================================================
-- 19. createCastTracker — failure counting and lockout system
-- ============================================================================
print('--- createCastTracker ---')

-- We can't extract createCastTracker (it references `mq` internally for
-- onFailureEvent), but the core inner functions (recordFailure, isLockedOut,
-- recordSuccess) are pure logic.  We re-implement a minimal version here to
-- test the algorithm.

local function testCastTracker()
    local failureCount = {}
    local lockouts = {}
    local mockClock = 100  -- fake os.clock()

    local function recordFailure(spellName, maxRetries, lockoutSec)
        if not spellName then return end
        local mRetries = tonumber(maxRetries) or 2
        local lSec = tonumber(lockoutSec) or 30
        failureCount[spellName] = (tonumber(failureCount[spellName]) or 0) + 1
        if failureCount[spellName] >= mRetries then
            lockouts[spellName] = mockClock + lSec
            failureCount[spellName] = 0
        end
    end

    local function isLockedOut(spellName)
        if not spellName then return false end
        local untilTime = tonumber(lockouts[spellName])
        if not untilTime then return false end
        if mockClock < untilTime then return true end
        lockouts[spellName] = nil
        return false
    end

    local function recordSuccess(spellName)
        if not spellName then return end
        failureCount[spellName] = 0
        lockouts[spellName] = nil
    end

    -- Test: not locked out initially
    assert_eq(isLockedOut('Heal'), false, 'tracker: not locked initially')

    -- Test: single failure doesn't lock out (default max_retries=2)
    recordFailure('Heal', 2, 30)
    assert_eq(isLockedOut('Heal'), false, 'tracker: 1 failure, not locked')

    -- Test: second failure triggers lockout
    recordFailure('Heal', 2, 30)
    assert_eq(isLockedOut('Heal'), true, 'tracker: 2 failures, locked out')

    -- Test: lockout expires after time passes
    mockClock = 131  -- 100 + 30 + 1
    assert_eq(isLockedOut('Heal'), false, 'tracker: lockout expired')

    -- Test: recordSuccess clears everything
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    recordSuccess('Nuke')
    recordFailure('Nuke', 3, 60)
    recordFailure('Nuke', 3, 60)
    -- Only 2 failures after reset, need 3 for lockout
    assert_eq(isLockedOut('Nuke'), false, 'tracker: success resets count')

    -- Test: custom max_retries
    mockClock = 200
    recordFailure('Dot', 1, 10)  -- 1 retry = lock on first fail
    assert_eq(isLockedOut('Dot'), true, 'tracker: max_retries=1 locks immediately')
end
testCastTracker()

-- ============================================================================
-- CROSS-MODULE TESTS: triune_dps.lua
-- ============================================================================
local dpsSrc = readFile('mq2triune/lua/triune_dps.lua')

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

local getVerbCategory = loadFunc(dpsSrc, 'getVerbCategory',
    { SKILL_VERBS = SKILL_VERBS, MELEE_VERBS = MELEE_VERBS })

assert_eq(getVerbCategory('hits'),       'Melee', 'verbCat: hits → Melee')
assert_eq(getVerbCategory('slashes'),    'Melee', 'verbCat: slashes → Melee')
assert_eq(getVerbCategory('crush'),      'Melee', 'verbCat: crush → Melee')
assert_eq(getVerbCategory('kick'),       'Skill', 'verbCat: kick → Skill')
assert_eq(getVerbCategory('backstabs'),  'Skill', 'verbCat: backstabs → Skill')
assert_eq(getVerbCategory('flying kick'),'Skill', 'verbCat: flying kick → Skill')
assert_eq(getVerbCategory('dragon punch'),'Skill','verbCat: dragon punch → Skill')
assert_eq(getVerbCategory('unknown'),    'Melee', 'verbCat: unknown → Melee fallback')
assert_eq(getVerbCategory(nil),          'Melee', 'verbCat: nil → Melee fallback')

-- ============================================================================
-- 24. calculateCategoryTotals (DPS) — damage category aggregation
-- ============================================================================
print('--- calculateCategoryTotals (dps) ---')
local calculateCategoryTotals = loadFunc(dpsSrc, 'calculateCategoryTotals', {})

local playerBD = {
    ['Slash']    = { category = 'Melee', totalDmg = 1000 },
    ['Kick']     = { category = 'Skill', totalDmg = 500 },
    ['Ice Comet']= { category = 'Spell', totalDmg = 2000 },
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
assert_eq(totals.skill, 500,  'catTotals: skill')
assert_eq(totals.spell, 2000, 'catTotals: spell')
assert_eq(totals.dot,   0,    'catTotals: dot (none)')
assert_eq(totals.ds,    0,    'catTotals: ds (none)')

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
assert_eq(getFightDPS(0, 10),    0,   'dps: 0 dmg = 0')
assert_eq(getFightDPS(1000, 0),  0,   'dps: 0 duration = 0')
-- Rounding test
assert_eq(getFightDPS(100, 3), 33, 'dps: 100/3 rounds to 33')
assert_eq(getFightDPS(200, 3), 67, 'dps: 200/3 rounds to 67')

-- ============================================================================
-- CROSS-MODULE TESTS: triune_buffbot.lua
-- ============================================================================
local bbSrc = readFile('mq2triune/lua/triune_buffbot.lua')

-- ============================================================================
-- 26. parseBuffRequest (buffbot) — tell message parsing
-- ============================================================================
print('--- parseBuffRequest (buffbot) ---')
local parseBuffRequest = loadFunc(bbSrc, 'parseBuffRequest', {})

-- Gem list for testing
local testGems = {
    { name = 'Virtue', gem = 1 },
    { name = 'Symbol of Marzin', gem = 2 },
    { name = 'Aegolism', gem = 3 },
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
assert_true(isThankYou('ty'),              'thx: ty')
assert_true(isThankYou('TY'),              'thx: TY')
assert_true(isThankYou('ty!'),             'thx: ty!')
assert_true(isThankYou('tyvm'),            'thx: tyvm')
assert_true(isThankYou('tysm'),            'thx: tysm')
assert_true(isThankYou('thx'),             'thx: thx')
assert_true(isThankYou('thanks'),          'thx: thanks')
assert_true(isThankYou('Thanks!'),         'thx: Thanks!')
assert_true(isThankYou('thank you'),       'thx: thank you')
assert_true(isThankYou('Thank You!'),      'thx: Thank You!')
assert_true(isThankYou('thank u'),         'thx: thank u')
assert_true(isThankYou('thankyou'),        'thx: thankyou')
assert_true(isThankYou('much appreciated'),'thx: much appreciated')
assert_true(isThankYou('appreciate it'),   'thx: appreciate it')
assert_true(isThankYou('ty for the buffs'),'thx: ty for the buffs')

-- Negative cases
assert_eq(isThankYou('buffs please'), false, 'thx: buffs please → false')
assert_eq(isThankYou('hello'), false,        'thx: hello → false')
assert_eq(isThankYou('1 3'), false,          'thx: 1 3 → false')
assert_eq(isThankYou(nil), false,            'thx: nil → false')
assert_eq(isThankYou(''), false,             'thx: empty → false')

-- ============================================================================
-- 28. triune_data.lua — structural validation
-- ============================================================================
print('--- triune_data.lua validation ---')
local dataFile = assert(loadfile('mq2triune/config/triune_data.lua'))
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
