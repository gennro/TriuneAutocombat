---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/gamedb.lua — Triune Game Database Plugin (items / NPCs / spells)
-- ============================================================================
-- An offline, in-game copy of the Project Triune database: every item with
-- its stats, effects and tiers (Base / Enchanted / Legendary), where it drops
-- (NPC, zone, server-accurate chance), which quest NPCs reward or take it,
-- and the tradeskill recipes that make or use it; every NPC with its stats,
-- spawn zones, loot, spells, faction and vendor list; every spell with its
-- classes, costs, decoded effects and the items / NPCs that carry it.
--
-- No network, no plugins, no LuaRocks. The data is plain text under
-- resources/gamedb/, built from the server's SQL dump and quest scripts by
-- tools/build_gamedb.py:
--   <kind>.idx      one line per searchable entry (id, chunk:offset, name)
--   <kind>.N.dat    one "key=value|key=value" line per record
-- The index is read into memory in slices across ticks (no hitch), search is
-- one plain string.find over a lowercased name blob, and opening a record is
-- one seek + one line read. Cross-reference lists carry ids only; names come
-- from the loaded indexes.
--
-- Window: ctrl.show_gamedb (header button "Database", /ac db, Window Layout).
-- Commands: /ac db [text] | /ac item <text> | /ac npc <text> | /ac spell <text>
-- Other plugins: plugin.open(kind, id), plugin.search(kind, text),
-- plugin.popout(kind, id) for a floating card (chat item links, targets),
-- plugin.lookupCursor(), plugin.lookupTarget(), plugin.npcIdForSpawn(id),
-- plugin.itemSummary(id) -> tooltip lines (tiers, top drop, quests, recipes),
-- plugin.spellIdByName(name, level), plugin.spellSummary(id) (effects, scrolls).
-- Loot Advisor: while the loot window is open, a small window lists the
-- corpse's items with drop chance on that NPC, value and quest / recipe notes.
-- Combat loop: the plugin installs core.castTracker.knownImmunity so mez /
-- slow / snare / charm / fear / stun / dispel casts are skipped on NPCs whose
-- special abilities make them immune, before the first wasted cast.
-- ============================================================================

local plugin = {
    id                 = 'gamedb',
    name               = 'Game Database',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Offline item, NPC and spell database: stats, tiers, drops, quests, recipes, spawns, loot and spell effects.',
    defaultEnabled     = true,
    tickInterval       = 0.02,
    runOutOfCombatOnly = false,
    hasThread          = false,
    window             = { label = 'Database', tooltip = 'Toggles the Game Database window (items, NPCs, spells).', flag = 'show_gamedb', desc = 'Item / NPC / spell lookup (offline database)', headerButton = true, order = 22 },
    uses               = { map = 'Map button on NPC spawn rows (opens the Zone Atlas on that zone)' },
}

local core = nil
local ctrl, ImGui, mq = nil, nil, nil

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

local function echo(msg)
    print('\ag[Triune DB]\ax ' .. tostring(msg))
end

-- ----------------------------------------------------------------------------
-- Encoding (mirror of tools/build_gamedb.py)
-- ----------------------------------------------------------------------------
local ENC = {}
local UNESC = { ['\\'] = '\\', p = '|', s = ';', t = '~', c = ',', k = ':', n = '\n' }

function ENC.unescape(s)
    if not s or s == '' then return '' end
    if not s:find('\\', 1, true) then return s end
    return (s:gsub('\\(.)', UNESC))
end

-- Splits on a raw separator (escaped separators never appear raw).
function ENC.split(s, sep)
    local out = {}
    if not s or s == '' then return out end
    local start = 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            break
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return out
end

-- "k=v|k=v" -> { k = v } (values still escaped; use ENC.str / ENC.num)
function ENC.parseRecord(line)
    local rec = {}
    if not line then return rec end
    for k, v in line:gmatch('([%w_]+)=([^|]*)') do rec[k] = v end
    return rec
end

function ENC.num(rec, k, default)
    local v = rec and rec[k]
    if v == nil then return default or 0 end
    return tonumber(v) or default or 0
end

function ENC.str(rec, k)
    local v = rec and rec[k]
    if not v then return '' end
    return ENC.unescape(v)
end

-- List field: entries split on ';', fields on '~'. Leaves are unescaped.
-- A trailing "+N" entry (overflow marker) is returned as list.more = N.
function ENC.list(rec, k)
    local out = {}
    local raw = rec and rec[k]
    if not raw or raw == '' then return out end
    for _, entry in ipairs(ENC.split(raw, ';')) do
        local more = entry:match('^%+(%d+)$')
        if more then
            out.more = tonumber(more)
        else
            local fields = ENC.split(entry, '~')
            for i = 1, #fields do fields[i] = ENC.unescape(fields[i]) end
            out[#out + 1] = fields
        end
    end
    return out
end

-- Nested list inside one '~' field: "a:b:c,a:b:c" -> { {a,b,c}, ... }
function ENC.nested(field)
    local out = {}
    if not field or field == '' then return out end
    for _, entry in ipairs(ENC.split(field, ',')) do
        local parts = ENC.split(entry, ':')
        for i = 1, #parts do parts[i] = ENC.unescape(parts[i]) end
        out[#out + 1] = parts
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Decode tables
-- ----------------------------------------------------------------------------
local D = {}

-- { [start] = list[1], [start+1] = list[2], ... } - avoids Lua's mixed
-- constructor trap where positional entries ignore explicit keys.
local function seq(start, list, extra)
    local t = {}
    for i, v in ipairs(list) do t[start + i - 1] = v end
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

D.CLASSES = { 'WAR', 'CLR', 'PAL', 'RNG', 'SHD', 'DRU', 'MNK', 'BRD', 'ROG', 'SHM', 'NEC', 'WIZ', 'MAG', 'ENC', 'BST', 'BER' }
D.CLASS_NAMES = { 'Warrior', 'Cleric', 'Paladin', 'Ranger', 'Shadow Knight', 'Druid', 'Monk', 'Bard', 'Rogue', 'Shaman', 'Necromancer', 'Wizard', 'Magician', 'Enchanter', 'Beastlord', 'Berserker' }
D.RACES = { 'HUM', 'BAR', 'ERU', 'ELF', 'HIE', 'DEF', 'HEF', 'DWF', 'TRL', 'OGR', 'HFL', 'GNM', 'IKS', 'VAH', 'FRG', 'DRK' }
D.SLOTS = { 'Charm', 'Ear', 'Head', 'Face', 'Ear', 'Neck', 'Shoulders', 'Arms', 'Back', 'Wrist', 'Wrist', 'Range', 'Hands', 'Primary', 'Secondary', 'Finger', 'Finger', 'Chest', 'Legs', 'Feet', 'Waist', 'Power Source', 'Ammo' }
D.SIZES = seq(0, { 'Tiny', 'Small', 'Medium', 'Large', 'Giant' })

D.ITEM_TYPES = seq(0, { '1H Slashing', '2H Slashing', 'Piercing', '1H Blunt', '2H Blunt', 'Archery' }, {
    [7] = 'Throwing', [8] = 'Shield', [10] = 'Armor', [11] = 'Misc', [12] = 'Lockpicks', [14] = 'Food', [15] = 'Drink', [16] = 'Light',
    [17] = 'Combinable', [18] = 'Bandage', [19] = 'Throwing', [20] = 'Scroll', [21] = 'Potion', [22] = 'Fletched Arrow', [23] = 'Wind Instrument',
    [24] = 'Stringed Instrument', [25] = 'Brass Instrument', [26] = 'Percussion Instrument', [27] = 'Arrow', [29] = 'Jewelry', [30] = 'Skull',
    [31] = 'Book', [32] = 'Note', [33] = 'Key', [34] = 'Coin', [35] = '2H Piercing', [36] = 'Fishing Pole', [37] = 'Fishing Bait', [38] = 'Alcohol',
    [39] = 'Key', [40] = 'Compass', [42] = 'Poison', [45] = 'Martial', [52] = 'Charm', [53] = 'Augmentation Distiller', [54] = 'Augmentation',
    [55] = 'Augmentation Sealer', [56] = 'Charm', [58] = 'Collectible', [59] = 'Powersource', [60] = 'Mount', [62] = 'Illusion', [63] = 'Familiar',
    [64] = 'Mount', [68] = 'Bandolier',
})

D.SKILLS = seq(0, {
    '1H Blunt', '1H Slashing', '2H Blunt', '2H Slashing', 'Abjuration', 'Alteration', 'Apply Poison', 'Archery', 'Backstab', 'Bind Wound',
    'Bash', 'Block', 'Brass Instruments', 'Channeling', 'Conjuration', 'Defense', 'Disarm', 'Disarm Traps', 'Divination', 'Dodge',
    'Double Attack', 'Dragon Punch', 'Dual Wield', 'Eagle Strike', 'Evocation', 'Feign Death', 'Flying Kick', 'Forage', 'Hand to Hand', 'Hide',
    'Kick', 'Meditate', 'Mend', 'Offense', 'Parry', 'Pick Lock', '1H Piercing', 'Riposte', 'Round Kick', 'Safe Fall',
    'Sense Heading', 'Singing', 'Sneak', 'Specialize Abjure', 'Specialize Alteration', 'Specialize Conjuration', 'Specialize Divination', 'Specialize Evocation', 'Pick Pockets', 'Stringed Instruments',
    'Swimming', 'Throwing', 'Tiger Claw', 'Tracking', 'Wind Instruments', 'Fishing', 'Make Poison', 'Tinkering', 'Research', 'Alchemy',
    'Baking', 'Tailoring', 'Sense Traps', 'Blacksmithing', 'Fletching', 'Brewing', 'Alcohol Tolerance', 'Begging', 'Jewelry Making', 'Pottery',
    'Percussion Instruments', 'Intimidation', 'Berserking', 'Taunt', 'Frenzy', 'Remove Traps', 'Triple Attack', '2H Piercing',
}, { [100] = 'Quest Combine' })

D.AUG_TYPES = {
    'General: Single Stat', 'General: Multiple Stat', 'General: Spell Effect', 'Weapon: General', 'Weapon: Elem Damage', 'Weapon: Base Damage',
    'General: Group', 'General: Raid', 'General: Dragons Points', 'Crafted: Common', 'Crafted: Group', 'Crafted: Raid', 'Energeiac: Group',
    'Energeiac: Raid', 'Emblem', 'Crafted: Group / Raid', 'Ornamentation', 'Special Ornamentation', 'Type 19', 'Type 20', 'Type 21', 'Type 22',
    'Type 23', 'Type 24', 'Type 25', 'Type 26', 'Type 27', 'Type 28', 'Type 29', 'Type 30',
}

D.DEITIES = { 'Agnostic', 'Bertoxxulous', 'Brell Serilis', 'Cazic Thule', 'Erollisi Marr', 'Bristlebane', 'Innoruuk', 'Karana', 'Mithaniel Marr',
    'Prexus', 'Quellious', 'Rallos Zek', 'Rodcet Nife', 'Solusek Ro', 'The Tribunal', 'Tunare', 'Veeshan' }

D.CLICK_TYPES = seq(0, { '', 'Any slot', 'Any slot', 'Expendable', 'Must equip', 'Class/Race/Level', 'Bard', 'Any slot' })

D.BODY_TYPES = seq(1, {
    'Humanoid', 'Lycanthrope', 'Undead', 'Giant', 'Construct', 'Extraplanar', 'Magical', 'Summoned Undead', 'Raid Giant', 'Raid Coldain',
    'Untargetable', 'Vampire', 'Atenha Ra', 'Greater Akheva', 'Khati Sha', 'Seru', 'Grieg Veneficus', 'Draz Nurakk', 'Zek', 'Luggald',
    'Animal', 'Insect', 'Monster', 'Summoned', 'Plant', 'Dragon', 'Summoned 2', 'Summoned 3', 'Dragon 2', 'Velious Dragon',
}, { [32] = 'Dragon 3', [33] = 'Boxes', [34] = 'Muramite', [60] = 'Untargetable', [63] = 'Swarm Pet', [64] = 'Monster Summon', [65] = 'Trap',
     [66] = 'Timer', [67] = 'Trigger', [100] = 'Invisible Man', [101] = 'Special', [102] = 'Herbivore', [103] = 'Carnivore' })

D.NPC_CLASSES = seq(20, {
    'Warrior GM', 'Cleric GM', 'Paladin GM', 'Ranger GM', 'Shadow Knight GM', 'Druid GM', 'Monk GM', 'Bard GM', 'Rogue GM', 'Shaman GM',
    'Necromancer GM', 'Wizard GM', 'Magician GM', 'Enchanter GM', 'Beastlord GM', 'Berserker GM',
}, { [40] = 'Banker', [41] = 'Merchant', [59] = 'Discord Merchant', [60] = 'Adventure Recruiter', [61] = 'Adventure Merchant', [63] = 'Tribute Master',
     [64] = 'Guild Tribute Master', [66] = 'Guild Banker', [67] = 'Radiant Crystal Merchant', [68] = 'Ebon Crystal Merchant', [69] = 'Fellowship Master',
     [70] = 'Alternate Currency Merchant', [71] = 'Mercenary Liaison', [72] = 'Real Estate', [73] = 'Norrath\'s Keepers', [74] = 'Dark Reign' })

D.RACE_NAMES = seq(1, {
    'Human', 'Barbarian', 'Erudite', 'Wood Elf', 'High Elf', 'Dark Elf', 'Half Elf', 'Dwarf', 'Troll', 'Ogre', 'Halfling', 'Gnome', 'Aviak',
    'Werewolf', 'Brownie', 'Centaur', 'Golem', 'Giant', 'Trakanon', 'Venril Sathir', 'Evil Eye', 'Beetle', 'Kerran', 'Fish', 'Fairy', 'Froglok',
    'Froglok Ghoul', 'Fungusman', 'Gargoyle', 'Gasbag', 'Gelatinous Cube', 'Ghost', 'Ghoul', 'Giant Bat', 'Giant Eel', 'Giant Rat', 'Giant Snake',
    'Giant Spider', 'Gnoll', 'Goblin', 'Gorilla', 'Harpy', 'Hill Giant', 'Imp', 'Zombie', 'Qeynos Citizen', 'Unknown',
})
for id, name in pairs({
    [14] = 'Werewolf', [15] = 'Brownie', [16] = 'Centaur', [17] = 'Golem', [18] = 'Giant', [24] = 'Fish', [26] = 'Froglok', [27] = 'Froglok Ghoul',
    [45] = 'Zombie', [46] = 'Qeynos Citizen', [48] = 'Kobold', [49] = 'Lava Dragon', [50] = 'Lion', [51] = 'Lizard Man', [52] = 'Mimic', [53] = 'Minotaur',
    [54] = 'Orc', [55] = 'Human Beggar', [56] = 'Pixie', [57] = 'Drachnid', [58] = 'Solusek Ro', [59] = 'Goblin', [60] = 'Skeleton', [61] = 'Shark',
    [62] = 'Tunare', [63] = 'Tiger', [64] = 'Treant', [65] = 'Vampire', [66] = 'Rallos Zek', [67] = 'Highpass Citizen', [68] = 'Tentacle Terror',
    [69] = 'Will-O-Wisp', [70] = 'Zombie', [71] = 'Qeynos Citizen', [72] = 'Ship', [73] = 'Launch', [74] = 'Piranha', [75] = 'Elemental', [76] = 'Puma',
    [77] = 'Neriak Citizen', [78] = 'Erudite Citizen', [79] = 'Bixie', [80] = 'Reanimated Hand', [81] = 'Rivervale Citizen', [82] = 'Scarecrow',
    [83] = 'Skunk', [84] = 'Snake Elemental', [85] = 'Spectre', [86] = 'Sphinx', [87] = 'Armadillo', [88] = 'Clockwork Gnome', [89] = 'Drake',
    [90] = 'Halas Citizen', [91] = 'Alligator', [92] = 'Grobb Citizen', [93] = 'Oggok Citizen', [94] = 'Kaladim Citizen', [95] = 'Cazic Thule',
    [96] = 'Cockatrice', [97] = 'Daisy Man', [98] = 'Elf Vampire', [99] = 'Denizen', [100] = 'Dervish', [101] = 'Efreeti', [102] = 'Froglok Tadpole',
    [103] = 'Kedge', [104] = 'Leech', [105] = 'Swordfish', [106] = 'Felguard', [107] = 'Mammoth', [108] = 'Eye of Zomm', [109] = 'Wasp', [110] = 'Mermaid',
    [111] = 'Harpie', [112] = 'Fayguard', [113] = 'Drixie', [114] = 'Ghost Ship', [115] = 'Clam', [116] = 'Sea Horse', [117] = 'Dwarf Ghost',
    [118] = 'Erudite Ghost', [119] = 'Sabertooth Cat', [120] = 'Wolf Elemental', [121] = 'Gorgon', [122] = 'Dragon Skeleton', [123] = 'Innoruuk',
    [124] = 'Unicorn', [125] = 'Pegasus', [126] = 'Djinn', [127] = 'Invisible Man', [128] = 'Iksar', [129] = 'Scorpion', [130] = 'Vah Shir',
    [131] = 'Sarnak', [132] = 'Draglock', [133] = 'Drolvarg', [134] = 'Mosquito', [135] = 'Rhino', [136] = 'Xalgoz', [137] = 'Kunark Goblin',
    [138] = 'Yeti', [139] = 'Iksar Citizen', [140] = 'Forest Giant', [141] = 'Boat', [144] = 'Burynai', [145] = 'Goo', [146] = 'Spectral Sarnak',
    [147] = 'Spectral Iksar', [148] = 'Kunark Fish', [149] = 'Iksar Scorpion', [150] = 'Erollisi', [151] = 'Tribunal', [152] = 'Bertoxxulous',
    [153] = 'Bristlebane', [154] = 'Fay Drake', [155] = 'Sarnak Skeleton', [156] = 'Ratman', [157] = 'Wyvern', [158] = 'Wurm', [159] = 'Devourer',
    [160] = 'Iksar Golem', [161] = 'Iksar Skeleton', [162] = 'Man-Eating Plant', [163] = 'Raptor', [164] = 'Sarnak Golem', [165] = 'Water Dragon',
    [166] = 'Iksar Hand', [167] = 'Succulent', [168] = 'Flying Monkey', [169] = 'Brontotherium', [170] = 'Snow Dervish', [171] = 'Dire Wolf',
    [172] = 'Manticore', [173] = 'Totem', [174] = 'Cold Spectre', [175] = 'Enchanted Armor', [176] = 'Snow Bunny', [177] = 'Walrus', [178] = 'Rock-Gem Men',
    [181] = 'Yak Man', [183] = 'Coldain', [184] = 'Velious Dragon', [185] = 'Hag', [186] = 'Hippogriff', [187] = 'Siren', [188] = 'Frost Giant',
    [189] = 'Storm Giant', [190] = 'Otterman', [191] = 'Walrus Man', [192] = 'Clockwork Dragon', [193] = 'Abhorrent', [194] = 'Sea Turtle',
    [195] = 'Black and White Dragon', [196] = 'Ghost Dragon', [197] = 'Ronnie Test', [198] = 'Prismatic Dragon', [199] = 'Shik\'Nar', [200] = 'Rockhopper',
    [201] = 'Underbulk', [202] = 'Grimling', [203] = 'Vacuum Worm', [204] = 'Evan Test', [205] = 'Kahli Shah', [206] = 'Owlbear', [207] = 'Rhino Beetle',
    [208] = 'Vampyre', [209] = 'Earth Elemental', [210] = 'Air Elemental', [211] = 'Water Elemental', [212] = 'Fire Elemental', [213] = 'Wetfang Minnow',
    [214] = 'Thought Horror', [215] = 'Tegi', [216] = 'Horse', [217] = 'Shissar', [218] = 'Fungal Fiend', [219] = 'Vampire Volatalis', [220] = 'Stonegrabber',
    [221] = 'Scarlet Cheetah', [222] = 'Zelniak', [223] = 'Lightcrawler', [224] = 'Shade', [225] = 'Sunflower', [226] = 'Sun Revenant', [227] = 'Shrieker',
    [228] = 'Galorian', [229] = 'Netherbian', [230] = 'Akheva', [231] = 'Grieg Veneficus', [232] = 'Sonic Wolf', [233] = 'Ground Shaker', [234] = 'Vah Shir Skeleton',
    [235] = 'Wretch', [236] = 'Seru', [237] = 'Recuso', [238] = 'Vah Shir King', [239] = 'Vah Shir Guard', [240] = 'Teleport Man', [241] = 'Werewolf',
    [242] = 'Nymph', [243] = 'Dryad', [244] = 'Treant', [245] = 'Fly', [246] = 'Tarew Marr', [247] = 'Solusek Ro', [248] = 'Clockwork Golem', [249] = 'Clockwork Brain',
    [250] = 'Banshee', [251] = 'Guard of Justice', [252] = 'Mini POM', [253] = 'Diseased Fiend', [254] = 'Solusek Ro Guard', [255] = 'Bertoxxulous',
    [256] = 'The Tribunal', [257] = 'Terris Thule', [258] = 'Vegerog', [259] = 'Crocodile', [260] = 'Bat', [261] = 'Hraquis', [262] = 'Tranquilion',
    [263] = 'Tin Soldier', [264] = 'Nightmare Wraith', [265] = 'Malarian', [266] = 'Knight of Pestilence', [267] = 'Lepertoloth', [268] = 'Bubonian',
    [269] = 'Bubonian Underling', [270] = 'Pusling', [271] = 'Water Mephit', [272] = 'Stormrider', [273] = 'Junk Beast', [274] = 'Broken Clockwork',
    [275] = 'Giant Clockwork', [276] = 'Clockwork Beetle', [277] = 'Nightmare Goblin', [278] = 'Karana', [279] = 'Blood Raven', [280] = 'Nightmare Gargoyle',
    [281] = 'Mouth of Insanity', [282] = 'Skeletal Horse', [283] = 'Saryrn', [284] = 'Fennin Ro', [285] = 'Tormentor', [286] = 'Soul Devourer', [287] = 'Nightmare',
    [288] = 'Rallos Zek', [289] = 'Vallon Zek', [290] = 'Tallon Zek', [291] = 'Air Mephit', [292] = 'Earth Mephit', [293] = 'Fire Mephit', [294] = 'Nightmare Mephit',
    [295] = 'Zebuxoruk', [296] = 'Mithaniel Marr', [297] = 'Undead Knight', [298] = 'The Rathe', [299] = 'Xegony', [300] = 'Fiend', [301] = 'Test Object',
    [302] = 'Crab', [303] = 'Phoenix', [304] = 'Dragon', [305] = 'Bear', [306] = 'Earth Golem', [307] = 'Iron Golem', [308] = 'Storm Golem', [309] = 'Air Golem',
    [310] = 'Wood Golem', [311] = 'Fire Golem', [312] = 'Water Golem', [313] = 'War Wraith', [314] = 'Wrulon', [315] = 'Kraken', [316] = 'Poison Frog',
    [317] = 'Nilborien', [318] = 'Valorian', [319] = 'War Boar', [320] = 'Efreeti', [321] = 'War Boar', [322] = 'Black Knight', [323] = 'Animated Armor',
    [324] = 'Undead Footman', [325] = 'Rallos Zek Minion', [326] = 'Arcanist of Hate', [327] = 'Wyvern', [328] = 'Wyvern', [329] = 'Wyvern', [330] = 'Froglok',
    [331] = 'Werewolf', [332] = 'Ghoul', [333] = 'Zombie', [334] = 'Innoruuk', [335] = 'Scarecrow', [336] = 'Shade', [337] = 'Sarnak', [338] = 'Zombie',
    [339] = 'Human', [340] = 'Human', [341] = 'Human', [342] = 'Mad Toon', [343] = 'Stone Worker', [344] = 'Kerran', [345] = 'Kerran', [346] = 'Kerran',
    [347] = 'Tricorn', [348] = 'Kerran', [349] = 'Kerran', [350] = 'Kerran', [351] = 'Kerran', [352] = 'Yeti', [353] = 'Sarnak Ghost', [354] = 'Chimera',
    [355] = 'Dragorn', [356] = 'Murkglider', [357] = 'Rat', [358] = 'Bat', [359] = 'Gelidran', [360] = 'Discordling', [361] = 'Girplan', [362] = 'Minotaur',
    [363] = 'Dragorn Box', [364] = 'Runed Orb', [365] = 'Dragon Bones', [366] = 'Muramite Armor Pile', [367] = 'Crystal Shard', [368] = 'Portal', [369] = 'Coin Purse',
    [370] = 'Rock Pile', [371] = 'Murkglider Egg Sack', [372] = 'Drake', [373] = 'Dervish', [374] = 'Drake', [375] = 'Goblin', [376] = 'Kirin', [377] = 'Dragon',
    [378] = 'Basilisk', [379] = 'Dragon', [380] = 'Dragon', [381] = 'Puma', [382] = 'Spider', [383] = 'Spider Queen', [384] = 'Animated Statue', [385] = 'Unknown',
    [386] = 'Unknown', [387] = 'Dragon Egg', [388] = 'Dragon Statue', [389] = 'Lava Rock', [390] = 'Animated Statue', [391] = 'Spider Egg Sack', [392] = 'Lava Spider',
    [393] = 'Lava Spider Queen', [394] = 'Dragon', [395] = 'Giant', [396] = 'Golem', [397] = 'Dragon', [398] = 'Drakkin', [399] = 'Unknown', [400] = 'Hynid',
    [401] = 'Turepta', [402] = 'Cragbeast', [403] = 'Stonemite', [404] = 'Ulthork', [405] = 'Dragon', [406] = 'Bear', [407] = 'Mortabus', [408] = 'Ogre',
    [409] = 'Vampire', [410] = 'Kirin', [411] = 'Nightmare', [412] = 'Wolf', [413] = 'Wolf', [414] = 'Wyvern', [415] = 'Snake', [416] = 'Dark Elf',
    [417] = 'Elemental', [418] = 'Elemental', [419] = 'Pyrilen', [420] = 'Chimera', [421] = 'Rhino', [422] = 'Tortoise', [423] = 'Tortoise', [424] = 'Undead',
    [425] = 'Bloodgorge', [426] = 'Lightcrawler', [427] = 'Manticore', [428] = 'Gnome', [429] = 'Human', [430] = 'Dwarf', [431] = 'Sarnak', [432] = 'Shade',
    [433] = 'Blob', [434] = 'Alligator', [435] = 'Golem', [436] = 'Snake', [437] = 'Dragon', [438] = 'Weapon Rack', [439] = 'Tunare', [440] = 'Skeleton',
    [441] = 'Trophy', [442] = 'Elf', [443] = 'Corathus', [444] = 'Coral', [445] = 'Drachnid', [446] = 'Drachnid Cocoon', [447] = 'Fungus Patch', [448] = 'Gargoyle',
    [449] = 'Witheran', [450] = 'Dark Lord', [451] = 'Shiliskin', [452] = 'Snake', [453] = 'Evil Eye', [454] = 'Minotaur', [455] = 'Zombie', [456] = 'Clockwork Boar',
    [457] = 'Fairy', [458] = 'Witheran', [459] = 'Air Elemental', [460] = 'Earth Elemental', [461] = 'Fire Elemental', [462] = 'Water Elemental', [463] = 'Alligator',
    [464] = 'Bear', [465] = 'Scaled Wolf', [466] = 'Wolf', [467] = 'Spirit Wolf', [468] = 'Skeleton', [469] = 'Spectre', [470] = 'Bolvirk', [471] = 'Banshee',
    [472] = 'Banshee', [473] = 'Elddar', [474] = 'Forest Giant', [475] = 'Bone Golem', [476] = 'Horse', [477] = 'Pegasus', [478] = 'Shambling Mound', [479] = 'Scrykin',
    [480] = 'Treant', [481] = 'Vampire', [482] = 'Ayonae Ro', [483] = 'Sullon Zek', [484] = 'Banner', [485] = 'Flag', [486] = 'Rowboat', [487] = 'Bear Trap',
    [488] = 'Clockwork Bomb', [489] = 'Dynamite Keg', [490] = 'Pressure Plate', [491] = 'Puffer Spore', [492] = 'Stone Ring', [493] = 'Root Trap', [494] = 'Book',
    [495] = 'Skeleton', [496] = 'Rat', [497] = 'Human', [498] = 'Snail', [499] = 'Wraith', [500] = 'Ogre', [501] = 'Snake', [502] = 'Human', [503] = 'Chimera',
    [504] = 'Unknown', [505] = 'Efreeti', [506] = 'Unknown', [507] = 'Dragon', [508] = 'Bugbear', [509] = 'Dragon', [510] = 'Scrykin', [511] = 'Snake',
    [512] = 'Spider', [513] = 'Human', [514] = 'Fairy', [515] = 'Human', [516] = 'Nymph', [517] = 'Dragon', [518] = 'Spider', [519] = 'Drakkin', [520] = 'Scrykin',
    [521] = 'Efreeti', [522] = 'Brownie', [523] = 'Half Elf', [524] = 'Unknown', [525] = 'Human', [526] = 'Human', [527] = 'Unknown', [528] = 'Goblin',
    [529] = 'Bear', [530] = 'Ratman', [531] = 'Gnoll', [532] = 'Gnome', [533] = 'Skeleton', [534] = 'Aviak', [535] = 'Elf', [536] = 'Human', [537] = 'Vampire',
    [538] = 'Snake', [539] = 'Basilisk', [540] = 'Wurm', [541] = 'Ogre', [542] = 'Dragon', [543] = 'Wraith', [544] = 'Brownie', [545] = 'Lion', [546] = 'Rockhopper',
    [547] = 'Ratman', [548] = 'Fungus Patch', [549] = 'Tree', [550] = 'Fairy', [551] = 'Aviak', [552] = 'Blob', [553] = 'Ogre', [554] = 'Dwarf', [555] = 'Golem',
    [556] = 'Scrykin', [557] = 'Human', [558] = 'Sabertooth', [559] = 'Bear', [560] = 'Puma', [561] = 'Dragon', [562] = 'Gnoll', [563] = 'Elemental', [564] = 'Boar',
    [565] = 'Dark Elf', [566] = 'Beetle', [567] = 'Human', [568] = 'Ogre', [569] = 'Human', [570] = 'Nightmare', [571] = 'Griffin', [572] = 'Wolf', [573] = 'Human',
    [574] = 'Wolf', [575] = 'Bear', [576] = 'Ogre', [577] = 'Dragon', [578] = 'Human', [579] = 'Beetle', [580] = 'Human', [581] = 'Dryad', [582] = 'Cliknar',
    [583] = 'Spider', [584] = 'Human', [585] = 'Aviak', [586] = 'Human', [587] = 'Werewolf', [588] = 'Goblin', [589] = 'Human', [590] = 'Golem', [591] = 'Wolf',
    [592] = 'Ratman', [593] = 'Unknown', [594] = 'Coldain', [595] = 'Skeleton', [596] = 'Human', [597] = 'Frost Giant', [598] = 'Alaran', [599] = 'Bear', [600] = 'Skeleton',
}) do D.RACE_NAMES[id] = name end

D.TARGET_TYPES = {
    [1] = 'Line of Sight', [3] = 'Group v1', [4] = 'PB AE', [5] = 'Single', [6] = 'Self', [8] = 'Targeted AE', [9] = 'Animal', [10] = 'Undead',
    [11] = 'Summoned', [13] = 'Lifetap', [14] = 'Pet', [15] = 'Corpse', [16] = 'Plant', [17] = 'Uber Giants', [18] = 'Uber Dragons', [20] = 'Targeted AE Lifetap',
    [24] = 'AE Undead', [25] = 'AE Summoned', [32] = 'AE Caster', [33] = 'NPC Hate List', [34] = 'Dungeon Object', [35] = 'Muramite', [36] = 'AE PC',
    [37] = 'AE NPC', [38] = 'Summoned 3', [39] = 'Group No Pets', [40] = 'AE PC v2', [41] = 'Group v2', [42] = 'Directional', [43] = 'Group With Pets',
    [44] = 'Beam', [45] = 'Ring', [46] = 'Target of Target', [47] = 'Pet Owner', [50] = 'AE Undead 2', [52] = 'Single in Group',
}
D.RESIST_TYPES = seq(0, { 'None', 'Magic', 'Fire', 'Cold', 'Poison', 'Disease', 'Chromatic', 'Prismatic', 'Physical', 'Corruption' })
D.NPC_SPELL_TYPES = { [1] = 'Nuke', [2] = 'Heal', [4] = 'Root', [8] = 'Buff', [16] = 'Escape', [32] = 'Pet', [64] = 'Lifetap', [128] = 'Snare',
    [256] = 'DoT', [512] = 'Dispel', [1024] = 'In-Combat Buff', [2048] = 'Mez', [4096] = 'Charm', [8192] = 'Slow', [16384] = 'Debuff', [32768] = 'Cure',
    [65536] = 'Resurrect', [131072] = 'Hate Reduction', [262144] = 'In-Combat Buff Song', [524288] = 'Fear', [1048576] = 'Stun' }

D.SPECIAL_ABILITIES = seq(1, {
    'Summons', 'Enrages', 'Rampages', 'AE Rampages', 'Flurries', 'Triple Attacks', 'Quad Attacks', 'Dual Wields', 'Bane Attack', 'Magical Attack',
    'Ranged Attack', 'Unslowable', 'Unmezzable', 'Uncharmable', 'Unstunable', 'Unsnareable', 'Unfearable', 'Immune to Dispel', 'Immune to Melee',
    'Immune to Magic', 'Immune to Fleeing', 'Immune to Melee (except Bane)', 'Immune to Melee (except Magical)', 'Immune to Aggro', 'Immune to Being Aggroed',
    'Resists Ranged Spells', 'Sees Through Feign Death', 'Immune to Taunt', 'Tunnel Vision', 'Does Not Buff/Heal Friends', 'Immune to Pacify', 'Leashed',
    'Tethered', 'Destructible Object', 'No Harm From Players', 'Always Flees', 'Flee Percent', 'Allows Beneficial', 'Disables Melee', 'Chase Distance',
    'Allow Tank', 'Ignore Root Aggro', 'Casting Resist Diff', 'Counter Avoid Damage', 'Proximity Aggro', 'Immune to Ranged Attacks', 'Immune to Client Damage',
    'Immune to NPC Damage', 'Immune to Client Aggro', 'Immune to NPC Aggro', 'Modify Avoid Damage', 'Immune to Fading Memories', 'Immune to Open',
    'Immune to Assassinate', 'Immune to Headshot', 'Immune to Bot Damage', 'Immune to Bot Aggro', 'Immune to Bots',
})

-- ----------------------------------------------------------------------------
-- Decoders (pure functions, unit-tested)
-- ----------------------------------------------------------------------------
local function hasBit(mask, bitIndex) -- bitIndex 0-based, no `bit` library needed
    return math.floor((mask or 0) / (2 ^ bitIndex)) % 2 >= 1
end

function D.maskNames(mask, names, allText)
    mask = tonumber(mask) or 0
    local out = {}
    local all = true
    for i, n in ipairs(names) do
        if hasBit(mask, i - 1) then
            out[#out + 1] = n
        else
            all = false
        end
    end
    if all and #names > 0 then return allText or 'ALL' end
    if #out == 0 then return 'NONE' end
    return table.concat(out, ' ')
end

function D.classesText(mask) return D.maskNames(mask, D.CLASSES, 'ALL') end
function D.racesText(mask) return D.maskNames(mask, D.RACES, 'ALL') end

function D.slotsText(mask)
    mask = tonumber(mask) or 0
    local out, seen = {}, {}
    for i, n in ipairs(D.SLOTS) do
        if hasBit(mask, i - 1) and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    return table.concat(out, ' ')
end

function D.augTypesText(mask)
    mask = tonumber(mask) or 0
    local out = {}
    for i = 1, 30 do
        if hasBit(mask, i - 1) then out[#out + 1] = tostring(i) end
    end
    return table.concat(out, ', ')
end

function D.itemTypeName(t) return D.ITEM_TYPES[tonumber(t) or -1] or ('Type ' .. tostring(t)) end
function D.skillName(s) return D.SKILLS[tonumber(s) or -1] or ('Skill ' .. tostring(s)) end
function D.sizeName(s) return D.SIZES[tonumber(s) or -1] or tostring(s) end
function D.raceName(r) return D.RACE_NAMES[tonumber(r) or -1] or ('Race ' .. tostring(r)) end
function D.bodyTypeName(b) return D.BODY_TYPES[tonumber(b) or -1] or ('Body ' .. tostring(b)) end
function D.targetTypeName(t) return D.TARGET_TYPES[tonumber(t) or -1] or ('Target ' .. tostring(t)) end
function D.resistTypeName(r) return D.RESIST_TYPES[tonumber(r) or -1] or ('Resist ' .. tostring(r)) end
-- items.deity is a bitmask (bit 0 Agnostic, bit 1 Bertoxxulous, ... bit 16 Veeshan)
function D.deityName(mask)
    mask = tonumber(mask) or 0
    if mask == 0 then return 'All' end
    local out = {}
    for i, n in ipairs(D.DEITIES) do
        if hasBit(mask, i - 1) then out[#out + 1] = n end
    end
    if #out == #D.DEITIES then return 'All' end
    if #out == 0 then return 'Deity ' .. mask end
    return table.concat(out, ', ')
end

function D.className(c)
    c = tonumber(c) or 0
    return D.CLASS_NAMES[c] or D.NPC_CLASSES[c] or ('Class ' .. c)
end

-- "1,1^10,1" -> { 'Summons', 'Magical Attack' }
function D.specialAbilitiesText(s)
    local out = {}
    if not s or s == '' then return out end
    for part in (s .. '^'):gmatch('([^%^]*)%^') do
        local id = tonumber(part:match('^(%d+)'))
        if id then
            local name = D.SPECIAL_ABILITIES[id] or ('Ability ' .. id)
            local params = part:match('^%d+,(.*)$')
            if id == 37 and params then name = name .. ' ' .. params:match('^(%d+)') .. '%' end
            if id == 40 and params then name = name .. ' ' .. params:match('^(%d+)') end
            out[#out + 1] = name
        end
    end
    return out
end

function D.npcSpellTypes(mask)
    mask = tonumber(mask) or 0
    local out = {}
    for bitv, name in pairs(D.NPC_SPELL_TYPES) do
        local idx = math.floor(math.log(bitv) / math.log(2) + 0.5)
        if hasBit(mask, idx) then out[#out + 1] = name end
    end
    table.sort(out)
    return table.concat(out, ', ')
end

-- copper -> "12pp 3gp 4sp 5cp"
function D.moneyText(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return '' end
    local pp = math.floor(copper / 1000); copper = copper % 1000
    local gp = math.floor(copper / 100); copper = copper % 100
    local sp = math.floor(copper / 10); copper = copper % 10
    local out = {}
    if pp > 0 then out[#out + 1] = pp .. 'pp' end
    if gp > 0 then out[#out + 1] = gp .. 'gp' end
    if sp > 0 then out[#out + 1] = sp .. 'sp' end
    if copper > 0 then out[#out + 1] = copper .. 'cp' end
    return table.concat(out, ' ')
end

function D.secondsText(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return '0s' end
    if sec < 60 then return string.format('%ds', sec) end
    if sec < 3600 then return string.format('%dm %ds', math.floor(sec / 60), sec % 60) end
    if sec < 86400 then return string.format('%dh %dm', math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
    return string.format('%dd %dh', math.floor(sec / 86400), math.floor((sec % 86400) / 3600))
end

function D.weightText(w)
    w = tonumber(w) or 0
    return string.format('%.1f', w / 10)
end

-- Item tier suffix. Enchanted = +1,000,000, Legendary = +2,000,000.
function D.tierOf(id)
    id = tonumber(id) or 0
    if id >= 2000000 then return 'L', id - 2000000 end
    if id >= 1000000 then return 'E', id - 1000000 end
    return 'B', id
end
D.TIER_NAMES = { B = 'Base', E = 'Enchanted', L = 'Legendary' }
D.TIER_OFFSET = { B = 0, E = 1000000, L = 2000000 }

-- ----------------------------------------------------------------------------
-- Spell effect (SPA) text. Covers the common effects; the rest print raw.
-- ----------------------------------------------------------------------------
local SPA = {}
local function incdec(v) return (tonumber(v) or 0) < 0 and 'Decrease' or 'Increase' end
local function absv(v) return math.abs(tonumber(v) or 0) end
local function stat(name)
    return function(b, _, m)
        local s = string.format('%s %s by %d', incdec(b), name, absv(b))
        if (tonumber(m) or 0) > 0 and absv(m) ~= absv(b) then s = s .. string.format(' (up to %d)', absv(m)) end
        return s
    end
end
local function pct(name)
    return function(b, _, m)
        local s = string.format('%s %s by %d%%', incdec(b), name, absv(b))
        if (tonumber(m) or 0) > 0 and absv(m) ~= absv(b) then s = s .. string.format(' (up to %d%%)', absv(m)) end
        return s
    end
end
local function fixed(text) return function() return text end end

SPA[0] = function(b, _, m)
    b = tonumber(b) or 0
    local s = (b < 0) and string.format('Decrease Hitpoints by %d', -b) or string.format('Increase Hitpoints by %d', b)
    if (tonumber(m) or 0) > 0 and absv(m) ~= absv(b) then s = s .. string.format(' (up to %d)', absv(m)) end
    return s
end
SPA[1] = stat('AC'); SPA[2] = stat('ATK'); SPA[3] = pct('Movement Speed'); SPA[4] = stat('STR'); SPA[5] = stat('DEX'); SPA[6] = stat('AGI')
SPA[7] = stat('STA'); SPA[8] = stat('INT'); SPA[9] = stat('WIS'); SPA[10] = stat('CHA')
SPA[11] = function(b) b = tonumber(b) or 0; if b >= 100 then return string.format('Increase Attack Speed by %d%%', b - 100) end return string.format('Decrease Attack Speed by %d%%', 100 - b) end
SPA[12] = fixed('Invisibility'); SPA[13] = fixed('See Invisible'); SPA[14] = fixed('Water Breathing'); SPA[15] = stat('Mana')
SPA[18] = fixed('Pacify'); SPA[19] = stat('Faction'); SPA[20] = fixed('Blindness'); SPA[21] = function(b) return string.format('Stun (%.1fs)', (tonumber(b) or 0) / 1000) end
SPA[22] = function(_, _, m) return string.format('Charm (up to level %d)', tonumber(m) or 0) end
SPA[23] = function(_, _, m) return string.format('Fear (up to level %d)', tonumber(m) or 0) end
SPA[24] = stat('Endurance'); SPA[25] = fixed('Bind Affinity'); SPA[26] = fixed('Gate'); SPA[27] = function(b) return string.format('Cancel Magic (%d)', tonumber(b) or 0) end
SPA[28] = fixed('Invisibility vs Undead'); SPA[29] = fixed('Invisibility vs Animals'); SPA[30] = function(b, _, m) return string.format('Reaction Radius (%d / %d)', tonumber(b) or 0, tonumber(m) or 0) end
SPA[31] = function(_, _, m) return string.format('Mesmerize (up to level %d)', tonumber(m) or 0) end
SPA[32] = function(b, _, m) return string.format('Summon Item: [item %d] x%d', tonumber(b) or 0, math.max(tonumber(m) or 1, 1)) end
SPA[33] = fixed('Summon Pet'); SPA[35] = stat('Disease Counter'); SPA[36] = stat('Poison Counter'); SPA[40] = fixed('Invulnerability')
SPA[41] = fixed('Destroy'); SPA[42] = fixed('Shadowstep'); SPA[44] = fixed('Delayed Heal Marker'); SPA[46] = stat('Fire Resist'); SPA[47] = stat('Cold Resist')
SPA[48] = stat('Poison Resist'); SPA[49] = stat('Disease Resist'); SPA[50] = stat('Magic Resist'); SPA[52] = fixed('Sense Undead'); SPA[53] = fixed('Sense Summoned')
SPA[54] = fixed('Sense Animals'); SPA[55] = function(b) return string.format('Absorb Damage: %d (Rune)', tonumber(b) or 0) end; SPA[56] = fixed('True North')
SPA[57] = fixed('Levitate'); SPA[58] = function(b) return string.format('Illusion: %s', D.raceName(b)) end; SPA[59] = function(b) return string.format('Damage Shield (%d)', -(tonumber(b) or 0)) end
SPA[61] = fixed('Identify'); SPA[63] = function(b) return string.format('Memory Blur (%d%%)', tonumber(b) or 0) end; SPA[64] = function(b) return string.format('Spin Stun (%.1fs)', (tonumber(b) or 0) / 1000) end
SPA[65] = fixed('Infravision'); SPA[66] = fixed('Ultravision'); SPA[67] = fixed('Eye of Zomm'); SPA[68] = fixed('Reclaim Energy'); SPA[69] = stat('Max Hitpoints')
SPA[71] = fixed('Summon Undead Pet'); SPA[73] = fixed('Bind Sight'); SPA[74] = fixed('Feign Death'); SPA[75] = fixed('Voice Graft'); SPA[76] = fixed('Sentinel')
SPA[77] = fixed('Locate Corpse'); SPA[78] = function(b) return string.format('Absorb Spell Damage: %d', tonumber(b) or 0) end
SPA[79] = function(b, _, m) b = tonumber(b) or 0; local s = (b < 0) and string.format('Decrease Hitpoints by %d (instant)', -b) or string.format('Increase Hitpoints by %d (instant)', b); if (tonumber(m) or 0) > 0 and absv(m) ~= absv(b) then s = s .. string.format(' (up to %d)', absv(m)) end return s end
SPA[81] = function(b) return string.format('Resurrect (%d%% exp)', tonumber(b) or 0) end; SPA[82] = fixed('Summon Player'); SPA[83] = fixed('Teleport')
SPA[85] = function(b) return string.format('Add Proc: [spell %d]', tonumber(b) or 0) end; SPA[86] = function(b) return string.format('Reaction Radius (%d)', tonumber(b) or 0) end
SPA[87] = pct('Magnification'); SPA[88] = fixed('Evacuate'); SPA[89] = pct('Player Size'); SPA[91] = fixed('Summon Corpse'); SPA[92] = stat('Hate')
SPA[93] = fixed('Stop Rain'); SPA[94] = fixed('Make Fragile'); SPA[95] = fixed('Sacrifice'); SPA[96] = fixed('Silence'); SPA[97] = stat('Max Mana')
SPA[98] = SPA[11]; SPA[99] = fixed('Root'); SPA[100] = function(b) return string.format('%s Hitpoints by %d per tick', incdec(b), absv(b)) end
SPA[101] = fixed('Complete Heal (with duration)'); SPA[102] = fixed('Fearless'); SPA[103] = fixed('Call Pet'); SPA[104] = fixed('Translocate'); SPA[105] = fixed('Anti-Gate')
SPA[106] = fixed('Summon Warder'); SPA[108] = fixed('Summon Familiar'); SPA[109] = function(b, _, m) return string.format('Summon Item into Bag: [item %d] x%d', tonumber(b) or 0, math.max(tonumber(m) or 1, 1)) end
SPA[111] = stat('All Resists'); SPA[112] = stat('Casting Level'); SPA[113] = fixed('Summon Mount'); SPA[114] = pct('Hate Generated'); SPA[115] = fixed('Food / Water')
SPA[116] = stat('Curse Counter'); SPA[117] = fixed('Make Weapons Magical'); SPA[118] = stat('Singing Skill'); SPA[119] = SPA[11]; SPA[120] = pct('Healing Taken')
SPA[121] = function(b) return string.format('Reverse Damage Shield (%d)', -(tonumber(b) or 0)) end; SPA[123] = fixed('Screech'); SPA[124] = pct('Spell Damage')
SPA[125] = pct('Spell Healing'); SPA[126] = pct('Spell Resist Rate'); SPA[127] = pct('Spell Haste'); SPA[128] = pct('Spell Duration'); SPA[129] = pct('Spell Range')
SPA[130] = pct('Spell Hate'); SPA[131] = pct('Chance of Using Reagent'); SPA[132] = pct('Spell Mana Cost'); SPA[134] = function(b) return string.format('Limit: Max Level %d', tonumber(b) or 0) end
SPA[135] = function(b) return string.format('Limit: Resist %s', D.resistTypeName(b)) end; SPA[136] = function(b) return string.format('Limit: Target %s', D.targetTypeName(absv(b))) end
SPA[137] = function(b) return string.format('Limit: Effect %d', tonumber(b) or 0) end; SPA[138] = function(b) return (tonumber(b) or 0) == 0 and 'Limit: Detrimental Only' or 'Limit: Beneficial Only' end
SPA[139] = function(b) b = tonumber(b) or 0; return string.format('Limit: %s [spell %d]', b < 0 and 'Exclude' or 'Spell', math.abs(b)) end
SPA[140] = function(b) return string.format('Limit: Min Duration %ds', (tonumber(b) or 0) * 6) end; SPA[141] = fixed('Limit: Instant Only'); SPA[142] = function(b) return string.format('Limit: Min Level %d', tonumber(b) or 0) end
SPA[143] = function(b) return string.format('Limit: Min Cast Time %.1fs', (tonumber(b) or 0) / 1000) end; SPA[144] = function(b) return string.format('Limit: Max Cast Time %.1fs', (tonumber(b) or 0) / 1000) end
SPA[147] = function(b, _, m) return string.format('Heal %d%% (up to %d)', tonumber(b) or 0, tonumber(m) or 0) end; SPA[148] = function(b, _, m) return string.format('Stacking: Block SPA %d (%d)', tonumber(m) or 0, tonumber(b) or 0) end
SPA[149] = function(b, _, m) return string.format('Stacking: Overwrite SPA %d (%d)', tonumber(m) or 0, tonumber(b) or 0) end; SPA[150] = fixed('Death Save'); SPA[151] = fixed('Suspend Pet')
SPA[152] = function(b) return string.format('Summon Temporary Pets (%d)', tonumber(b) or 0) end; SPA[153] = fixed('Balance Group HP'); SPA[154] = function(b) return string.format('Dispel Detrimental (%d)', tonumber(b) or 0) end
SPA[156] = fixed('Illusion: Other'); SPA[157] = function(b) return string.format('Spell Damage Shield (%d)', -(tonumber(b) or 0)) end; SPA[158] = function(b) return string.format('Spell Reflect (%d%%)', tonumber(b) or 0) end
SPA[159] = stat('All Stats'); SPA[160] = fixed('Make Drunk'); SPA[161] = function(b, _, m) return string.format('Mitigate Spell Damage %d%% (up to %d)', tonumber(b) or 0, tonumber(m) or 0) end
SPA[162] = function(b, _, m) return string.format('Mitigate Melee Damage %d%% (up to %d)', tonumber(b) or 0, tonumber(m) or 0) end; SPA[163] = function(b) return string.format('Negate Attacks (%d)', tonumber(b) or 0) end
SPA[167] = stat('Pet Power'); SPA[168] = pct('Melee Mitigation'); SPA[169] = pct('Critical Hit Chance'); SPA[170] = pct('Spell Critical Chance'); SPA[171] = pct('Crippling Blow Chance')
SPA[172] = pct('Avoidance'); SPA[173] = pct('Riposte'); SPA[174] = pct('Dodge'); SPA[175] = pct('Parry'); SPA[176] = pct('Dual Wield'); SPA[177] = pct('Double Attack')
SPA[178] = pct('Melee Lifetap'); SPA[179] = stat('All Instrument Modifiers'); SPA[180] = pct('Resist Spell Chance'); SPA[181] = pct('Fear Resist'); SPA[182] = pct('Weapon Delay')
SPA[184] = pct('Hit Chance'); SPA[185] = pct('Damage Modifier'); SPA[186] = stat('Minimum Damage'); SPA[187] = fixed('Balance Group Mana'); SPA[188] = pct('Block Chance')
SPA[189] = stat('Endurance per tick'); SPA[190] = stat('Max Endurance'); SPA[191] = fixed('Amnesia'); SPA[192] = stat('Hate (instant)'); SPA[193] = function(b) return string.format('Skill Attack (%d)', tonumber(b) or 0) end
SPA[194] = fixed('Fade'); SPA[195] = pct('Stun Resist'); SPA[196] = pct('Strikethrough'); SPA[197] = pct('Skill Damage Taken'); SPA[198] = stat('Endurance (instant)')
SPA[199] = fixed('Taunt'); SPA[200] = pct('Proc Chance'); SPA[201] = fixed('Ranged Proc'); SPA[202] = fixed('Illusion: Other'); SPA[203] = fixed('Mass Group Buff')
SPA[204] = fixed('Group Fear Immunity'); SPA[205] = fixed('Rampage'); SPA[206] = fixed('AE Taunt'); SPA[207] = fixed('Flesh to Bone'); SPA[209] = function(b) return string.format('Dispel Beneficial (%d)', tonumber(b) or 0) end
SPA[210] = fixed('Pet Shield'); SPA[211] = fixed('AE Melee'); SPA[213] = pct('Pet Max HP'); SPA[214] = pct('Max HP'); SPA[215] = pct('Pet Avoidance'); SPA[216] = pct('Accuracy')
SPA[217] = fixed('Headshot'); SPA[218] = pct('Pet Critical Melee'); SPA[219] = pct('Slay Undead'); SPA[220] = stat('Skill Damage'); SPA[221] = pct('Weight Reduction')
SPA[222] = pct('Block Behind'); SPA[223] = pct('Double Riposte'); SPA[224] = pct('Additional Riposte'); SPA[225] = pct('Double Attack (give)'); SPA[227] = pct('Skill Timer Reduction')
SPA[228] = pct('Fall Damage Reduction'); SPA[229] = fixed('Cast Through Stun'); SPA[230] = stat('Shielding Distance'); SPA[231] = pct('Stun Bash Chance'); SPA[232] = fixed('Divine Save')
SPA[233] = pct('Metabolism'); SPA[235] = pct('Channeling'); SPA[236] = fixed('Free Pet'); SPA[237] = fixed('Pet Affinity'); SPA[238] = fixed('Permanent Illusion'); SPA[239] = fixed('Stonewall')
SPA[243] = pct('Charm Break Chance'); SPA[244] = pct('Root Break Chance'); SPA[246] = stat('Lung Capacity'); SPA[247] = stat('Skill Cap'); SPA[250] = pct('Spell Proc Chance')
SPA[252] = pct('Frontal Backstab Chance'); SPA[253] = fixed('Frontal Backstab Min Damage'); SPA[255] = stat('Shield Duration'); SPA[256] = fixed('Shroud of Stealth')
SPA[258] = pct('Triple Backstab'); SPA[259] = stat('AC Soft Cap'); SPA[262] = stat('Stat Cap'); SPA[263] = stat('Tradeskill Mastery'); SPA[264] = pct('AA Timer Reduction')
SPA[265] = fixed('No Fizzle'); SPA[266] = pct('Extra Attack Chance (2H)'); SPA[268] = pct('Tradeskill Failure Reduction'); SPA[269] = pct('Bandage'); SPA[270] = pct('Song Range')
SPA[271] = pct('Base Run Speed'); SPA[273] = pct('Critical DoT Chance'); SPA[274] = pct('Critical Heal Chance'); SPA[275] = pct('Critical Mend'); SPA[276] = pct('Dual Wield Amount')
SPA[278] = pct('Finishing Blow'); SPA[279] = pct('Flurry Chance'); SPA[280] = pct('Pet Flurry Chance'); SPA[281] = fixed('Pet Feign Death'); SPA[282] = pct('Bandage Amount')
SPA[286] = stat('Spell Damage (flat)'); SPA[287] = stat('Spell Duration (ticks)'); SPA[289] = function(b) return string.format('Cast on Fade: [spell %d]', tonumber(b) or 0) end
SPA[291] = function(b) return string.format('Purify (%d)', tonumber(b) or 0) end; SPA[292] = pct('Strikethrough v2'); SPA[293] = pct('Frontal Stun Resist'); SPA[294] = pct('Critical Spell Damage')
SPA[296] = pct('Spell Damage Taken'); SPA[297] = stat('Spell Damage Taken (flat)'); SPA[298] = pct('Pet Size'); SPA[299] = fixed('Wake the Dead'); SPA[300] = fixed('Doppelganger')
SPA[301] = pct('Ranged Damage'); SPA[302] = pct('Critical Damage'); SPA[303] = stat('Critical Damage (flat)'); SPA[305] = pct('Damage Shield Taken'); SPA[309] = fixed('Gate to Bind')
SPA[310] = pct('Reuse Timer Reduction'); SPA[311] = fixed('Limit: Combat Skills'); SPA[312] = fixed('Sanctuary'); SPA[313] = pct('Forage'); SPA[314] = fixed('Improved Invisibility')
SPA[315] = fixed('Improved Invisibility vs Undead'); SPA[316] = fixed('Improved Invisibility vs Animals'); SPA[319] = pct('Critical HoT'); SPA[320] = pct('Shield Block')
SPA[321] = stat('Target Hate Reduction'); SPA[322] = fixed('Gate to Home City'); SPA[323] = function(b) return string.format('Defensive Proc: [spell %d]', tonumber(b) or 0) end
SPA[324] = stat('HP for Mana'); SPA[326] = stat('Spell Slots'); SPA[327] = stat('Buff Slots'); SPA[329] = pct('Mana Absorb'); SPA[330] = pct('Critical Damage Modifier')
SPA[331] = pct('Salvage Chance'); SPA[332] = fixed('Summon to Corpse'); SPA[333] = function(b) return string.format('Cast on Rune Fade: [spell %d]', tonumber(b) or 0) end
SPA[335] = fixed('Block Next Spell'); SPA[337] = pct('Pet Critical Damage'); SPA[339] = function(b, _, m) return string.format('Trigger on Cast: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end
SPA[340] = function(b, _, m) return string.format('Chance to Cast: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end; SPA[342] = fixed('Immune to Fleeing'); SPA[343] = fixed('Interrupt Casting')
SPA[344] = pct('Channeling Chance'); SPA[345] = stat('Assassinate Level Cap'); SPA[346] = stat('Headshot Level Cap'); SPA[347] = pct('Double Ranged Attack'); SPA[348] = function(b) return string.format('Limit: Min Mana %d', tonumber(b) or 0) end
SPA[349] = pct('Shield Damage'); SPA[350] = fixed('Mana Burn'); SPA[351] = fixed('Persistent Effect'); SPA[353] = stat('Aura Slots'); SPA[358] = stat('Mana (instant)'); SPA[359] = fixed('Sense Trap')
SPA[360] = function(b, _, m) return string.format('Proc on Kill: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end; SPA[361] = function(b, _, m) return string.format('Proc on Death: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end
SPA[364] = pct('Triple Attack'); SPA[365] = function(b, _, m) return string.format('Proc on Spell Kill: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end; SPA[366] = fixed('Group Shielding')
SPA[367] = function(b) return string.format('Body Type: %s', D.bodyTypeName(b)) end; SPA[368] = stat('Faction'); SPA[369] = stat('Corruption Counter'); SPA[370] = stat('Corruption Resist')
SPA[371] = pct('Melee Slow'); SPA[373] = function(b) return string.format('Cast on Fade: [spell %d]', tonumber(b) or 0) end; SPA[374] = function(b, _, m) return string.format('Trigger Spell: [spell %d] (%d%%)', tonumber(m) or 0, tonumber(b) or 0) end
SPA[375] = pct('Critical DoT Damage'); SPA[376] = fixed('Fling'); SPA[377] = function(b) return string.format('Cast on Fade (Doom): [spell %d]', tonumber(b) or 0) end; SPA[378] = pct('Spell Effect Resist')
SPA[379] = fixed('Shadowstep (directional)'); SPA[380] = fixed('Knockback'); SPA[381] = fixed('Fling to Self'); SPA[382] = function(b) return string.format('Negate SPA %d', tonumber(b) or 0) end
SPA[383] = function(b, _, m) return string.format('Sympathetic Proc: [spell %d] (%d)', tonumber(m) or 0, tonumber(b) or 0) end; SPA[384] = fixed('Leap'); SPA[385] = function(b) return string.format('Limit: Spell Group %d', tonumber(b) or 0) end
SPA[386] = function(b) return string.format('Cast on Curer: [spell %d]', tonumber(b) or 0) end; SPA[387] = function(b) return string.format('Cast on Cure: [spell %d]', tonumber(b) or 0) end; SPA[388] = fixed('Summon All Corpses')
SPA[389] = fixed('Reset Reuse Timer'); SPA[391] = function(b) return string.format('Limit: Max Mana %d', tonumber(b) or 0) end; SPA[392] = stat('Healing (flat)'); SPA[393] = pct('Healing Taken'); SPA[394] = stat('Healing Taken (flat)')
SPA[395] = pct('Critical Heal'); SPA[396] = stat('Healing (flat)'); SPA[397] = stat('Pet AC'); SPA[398] = stat('Pet Duration'); SPA[399] = pct('Twincast Chance'); SPA[400] = fixed('Heal Group from Mana')
SPA[403] = function(b) return string.format('Limit: Spell Class %d', tonumber(b) or 0) end; SPA[404] = function(b) return string.format('Limit: Spell Subclass %d', tonumber(b) or 0) end; SPA[405] = pct('Staff Block')
SPA[406] = function(b) return string.format('Cast on Numhits Fade: [spell %d]', tonumber(b) or 0) end; SPA[407] = function(b) return string.format('Cast on Focus: [spell %d]', tonumber(b) or 0) end
SPA[408] = function(b) return string.format('Limit HP %d%%', tonumber(b) or 0) end; SPA[409] = function(b) return string.format('Limit Mana %d%%', tonumber(b) or 0) end; SPA[410] = function(b) return string.format('Limit Endurance %d%%', tonumber(b) or 0) end
SPA[411] = function(b) return string.format('Limit: Class %s', D.classesText(b)) end; SPA[412] = function(b) return string.format('Limit: Race %s', D.racesText(b)) end
SPA[413] = pct('Base Effects (Song)'); SPA[414] = function(b) return string.format('Limit: Casting Skill %s', D.skillName(b)) end; SPA[416] = stat('AC v2'); SPA[417] = stat('Mana per tick v2')
SPA[418] = stat('Skill Damage v2'); SPA[419] = function(b) return string.format('Add Melee Proc: [spell %d]', tonumber(b) or 0) end; SPA[420] = function(b) return string.format('Limit: Use %d', tonumber(b) or 0) end
SPA[421] = stat('Numhits'); SPA[424] = fixed('Gravitate'); SPA[425] = fixed('Fly'); SPA[427] = function(b) return string.format('Skill Proc: [spell %d]', tonumber(b) or 0) end
SPA[428] = function(b) return string.format('Limit: Skill %s', D.skillName(b)) end; SPA[429] = function(b) return string.format('Skill Proc (success): [spell %d]', tonumber(b) or 0) end
SPA[434] = pct('Critical Heal v2'); SPA[435] = pct('Critical HoT v2'); SPA[436] = fixed('Beneficial Countdown Hold'); SPA[437] = fixed('Teleport to Anchor'); SPA[438] = fixed('Translocate to Anchor')
SPA[439] = pct('Assassinate'); SPA[440] = stat('Finishing Blow Level'); SPA[441] = fixed('Distance Removal'); SPA[442] = function(b) return string.format('Trigger on Target Value: [spell %d]', tonumber(b) or 0) end
SPA[444] = pct('Improved Taunt'); SPA[450] = function(b) return string.format('DoT Guard (%d)', tonumber(b) or 0) end; SPA[451] = function(b) return string.format('Melee Threshold Guard (%d)', tonumber(b) or 0) end
SPA[452] = function(b) return string.format('Spell Threshold Guard (%d)', tonumber(b) or 0) end; SPA[455] = pct('Hate'); SPA[456] = pct('Hate over Time'); SPA[457] = fixed('Resource Tap')
SPA[458] = pct('Faction'); SPA[459] = pct('Skill Damage v2'); SPA[461] = pct('Spell Damage v2'); SPA[462] = pct('Healing v2'); SPA[467] = stat('Damage Shield v2')
SPA[469] = function(b) return string.format('Trigger Best in Spell Group: [spell %d]', tonumber(b) or 0) end; SPA[470] = function(b) return string.format('Trigger Best in Spell Group v2: [spell %d]', tonumber(b) or 0) end
SPA[471] = pct('Repeat Melee Round'); SPA[494] = stat('Pet Attack'); SPA[495] = function(b) return string.format('Limit: Max Duration %d ticks', tonumber(b) or 0) end
SPA[496] = pct('Critical Melee Damage'); SPA[498] = stat('Base Damage'); SPA[499] = stat('Resistance (all)')

-- Immunity rules: NPC special ability id -> the SPAs it makes pointless.
-- 20 (Immune to Magic) blocks every detrimental spell.
D.IMMUNITY_RULES = {
    { ability = 20, spas = nil,          reason = 'Immune to Magic' },
    { ability = 13, spas = { 31 },       reason = 'Unmezzable' },
    { ability = 12, spas = { 11, 371 },  reason = 'Unslowable' },
    { ability = 16, spas = { 3 },        reason = 'Unsnareable' },
    { ability = 14, spas = { 22 },       reason = 'Uncharmable' },
    { ability = 17, spas = { 23 },       reason = 'Unfearable' },
    { ability = 15, spas = { 21, 64 },   reason = 'Unstunable' },
    { ability = 18, spas = { 27, 209 },  reason = 'Immune to Dispel' },
    { ability = 31, spas = { 18, 86 },   reason = 'Immune to Pacify' },
    { ability = 52, spas = { 63 },       reason = 'Immune to Fading Memories' },
}

-- abilities: set { [abilityId] = param }; hasSPA(spa) -> boolean for the
-- (detrimental) spell being considered. Returns the reason the cast would
-- be wasted, or nil.
function D.immunityReason(abilities, hasSPA)
    if type(abilities) ~= 'table' then return nil end
    for _, rule in ipairs(D.IMMUNITY_RULES) do
        if abilities[rule.ability] then
            if not rule.spas then return rule.reason end
            for _, spa in ipairs(rule.spas) do
                if hasSPA(spa) then return rule.reason end
            end
        end
    end
    return nil
end

-- Returns the display line for one effect slot.
function D.spaText(spaId, base, limit, max)
    local fn = SPA[tonumber(spaId) or -1]
    if fn then
        local ok, txt = pcall(fn, base, limit, max)
        if ok and txt then return txt end
    end
    local s = string.format('SPA %s: base %s', tostring(spaId), tostring(base))
    if (tonumber(limit) or 0) ~= 0 then s = s .. ', limit ' .. tostring(limit) end
    if (tonumber(max) or 0) ~= 0 then s = s .. ', max ' .. tostring(max) end
    return s
end

-- ----------------------------------------------------------------------------
-- Data layer
-- ----------------------------------------------------------------------------
local DB = {
    dir      = nil,
    kinds    = {},   -- kind -> index state
    handles  = {},   -- "kind.chunk" -> file handle
    cache    = {},   -- "kind:ref" -> parsed record
    cacheN   = 0,
    loadQueue = {},
    loading  = nil,
    error    = nil,
    manifest = nil,
}
-- Index loading is sliced per *frame* (onDrawUI runs every frame; the core
-- only ticks plugins every 150-200 ms, which would make a load crawl): a
-- small slice in the background from plugin init, a bigger one while the
-- window is open and someone is waiting on the progress bar.
DB.BUDGET_IDLE = 0.002
DB.BUDGET_OPEN = 0.009
DB.BUDGET = DB.BUDGET_IDLE
DB.MAX_RESULTS = 300

local function newIndex(kind)
    return { kind = kind, loaded = false, count = 0, n = 0, ids = {}, names = {}, refs = {}, byId = {}, pieces = {}, starts = {}, pos = 1, lower = nil,
             extra = {},            -- items: tier letters; spells: "class:level,..." string
             refE = {}, refL = {},  -- items: enchanted / legendary record refs (false when absent)
             lvl = {}, zone = {} }  -- npcs
end

function DB.setDir(dir)
    if dir and dir ~= '' and dir:sub(-1) ~= '/' and dir:sub(-1) ~= '\\' then dir = dir .. '/' end
    DB.dir = dir
    DB.kinds = {}
    DB.cache = {}
    DB.cacheN = 0
    for _, f in pairs(DB.handles) do pcall(function() f:close() end) end
    DB.handles = {}
    DB.loadQueue = {}
    DB.loading = nil
    DB.error = nil
    DB.manifest = nil
end

function DB.resolveDir()
    if DB.dir then return DB.dir end
    local base = nil
    pcall(function()
        if mq and mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path then
            local p = mq.TLO.MacroQuest.Path('resources')
            base = p and p() or nil
            if (not base or base == '') and mq.TLO.MacroQuest.Path() then
                local root = mq.TLO.MacroQuest.Path()()
                if root and root ~= '' then base = root .. '/resources' end
            end
        end
    end)
    if not base or base == '' then base = 'resources' end
    base = base:gsub('\\', '/')
    -- Only the path is set here: setDir() would also drop the index tables
    -- and the load queue, which the caller (the loader itself) is using.
    DB.dir = base .. '/gamedb/'
    return DB.dir
end

function DB.readManifest()
    if DB.manifest then return DB.manifest end
    local f = io.open(DB.resolveDir() .. 'manifest.txt', 'r')
    local m = {}
    if f then
        for line in f:lines() do
            local k, v = line:match('^(%w+)=(.*)$')
            if k then m[k] = v end
        end
        f:close()
        m.present = true
    else
        m.present = false
    end
    DB.manifest = m
    return m
end

function DB.index(kind)
    local ix = DB.kinds[kind]
    if not ix then
        ix = newIndex(kind)
        DB.kinds[kind] = ix
    end
    return ix
end

function DB.isLoaded(kind)
    local ix = DB.kinds[kind]
    return ix ~= nil and ix.loaded
end

-- Queue an index for loading (no-op if loaded / queued).
function DB.ensure(kind)
    local ix = DB.index(kind)
    if ix.loaded or ix.failed then return end
    if DB.loading == ix then return end
    for _, q in ipairs(DB.loadQueue) do
        if q == ix then return end
    end
    DB.loadQueue[#DB.loadQueue + 1] = ix
end

-- "chunk:offset" -> one number (chunk * 2^32 + offset, exact in a double)
local REF_BASE = 4294967296
local function packRef(ref)
    if not ref or ref == '' then return false end
    local chunk, off = ref:match('^(%d+):(%d+)$')
    if not chunk then return false end
    return tonumber(chunk) * REF_BASE + tonumber(off)
end

local function addEntry(ix, id, ref, name)
    local n = ix.n + 1
    ix.n = n
    ix.ids[n] = id
    ix.refs[n] = packRef(ref)
    ix.names[n] = name
    ix.byId[id] = n
    local low = name:lower()
    ix.pieces[n] = low
    ix.starts[n] = ix.pos
    ix.pos = ix.pos + #low + 1
    return n
end

local PARSERS = {}
PARSERS.items = function(ix, line)
    local id, tiers, rb, re_, rl, name = line:match('^(%d+)|(%a*)|([^|]*)|([^|]*)|([^|]*)|(.*)$')
    if not id then return end
    -- refs[n] is the base row, or the enchanted / legendary row when no base exists
    local n = addEntry(ix, tonumber(id), rb ~= '' and rb or (re_ ~= '' and re_ or rl), ENC.unescape(name))
    ix.extra[n] = tiers
    ix.refE[n] = packRef(re_)
    ix.refL[n] = packRef(rl)
end
PARSERS.npcs = function(ix, line)
    local id, ref, lvl, zone, name = line:match('^(%d+)|([^|]*)|(%-?%d+)|([^|]*)|(.*)$')
    if not id then return end
    name = ENC.unescape(name)
    local n = addEntry(ix, tonumber(id), ref, name)
    ix.lvl[n] = tonumber(lvl) or 0
    ix.zone[n] = ENC.unescape(zone)
    -- name -> entries, for resolving a live spawn to its database NPC
    ix.byName = ix.byName or {}
    local low = ix.pieces[n]
    local list = ix.byName[low]
    if not list then
        ix.byName[low] = n
    elseif type(list) == 'number' then
        ix.byName[low] = { list, n }
    else
        list[#list + 1] = n
    end
end
PARSERS.spells = function(ix, line)
    local id, ref, classes, name = line:match('^(%d+)|([^|]*)|([^|]*)|(.*)$')
    if not id then return end
    local n = addEntry(ix, tonumber(id), ref, ENC.unescape(name))
    ix.extra[n] = classes
end
PARSERS.zones = function(ix, line)
    local short, long = line:match('^([^|]*)|(.*)$')
    if not short then return end
    addEntry(ix, ENC.unescape(short), '', ENC.unescape(long))
end

local function finishLoad(ix)
    ix.lower = table.concat(ix.pieces, '\n')
    ix.pieces = nil
    ix.loaded = true
    ix.count = ix.n
end

-- One slice of index loading; returns true while there is more to do.
function DB.stepLoad(budget)
    budget = budget or DB.BUDGET
    local deadline = os.clock() + budget
    while true do
        local ix = DB.loading
        if not ix then
            local dir = DB.resolveDir()
            ix = table.remove(DB.loadQueue, 1)
            if not ix then return false end
            local path = dir .. ix.kind .. '.idx'
            local f = io.open(path, 'rb')
            if not f then
                ix.failed = true
                DB.error = DB.error or ('missing ' .. path)
                return #DB.loadQueue > 0
            end
            local header = f:read('*l') or ''
            ix.expected = tonumber(header:match('count=(%d+)')) or 0
            ix.file = f
            DB.loading = ix
        end
        local parse = PARSERS[ix.kind]
        local f = ix.file
        local lines = 0
        while true do
            local line = f:read('*l')
            if not line then
                f:close()
                ix.file = nil
                finishLoad(ix)
                DB.loading = nil
                break
            end
            if line:sub(-1) == '\r' then line = line:sub(1, -2) end
            if line:sub(1, 1) ~= '#' then parse(ix, line) end
            lines = lines + 1
            if lines % 512 == 0 and os.clock() >= deadline then
                return true
            end
        end
        if os.clock() >= deadline then return DB.loading ~= nil or #DB.loadQueue > 0 end
    end
end

-- Blocking load (tests / command-line use); in game the tick slices it.
function DB.loadNow(kind)
    DB.ensure(kind)
    while DB.stepLoad(1000) do end
    return DB.isLoaded(kind)
end

function DB.progress()
    local ix = DB.loading
    if not ix then return nil end
    local total = ix.expected or 0
    if total <= 0 then return ix.kind, 0 end
    return ix.kind, math.min(1, ix.n / total)
end

-- Largest i with starts[i] <= pos.
local function entryAt(ix, pos)
    local starts = ix.starts
    local lo, hi = 1, ix.n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if starts[mid] <= pos then lo = mid else hi = mid - 1 end
    end
    return lo
end

-- Search an index by name. Returns array of entry numbers, best first:
-- exact name, then names starting with the query, then a word starting with
-- it, then any substring. `filter(ix, n)` may reject entries; `limit` caps
-- the result count. Ranks come from match positions alone, so scanning every
-- match of a common word stays cheap; only small rank buckets are name-sorted.
function DB.search(kind, query, filter, limit)
    local ix = DB.kinds[kind]
    if not ix or not ix.loaded then return {} end
    limit = limit or DB.MAX_RESULTS
    query = (query or ''):lower():gsub('_', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local out = {}
    local idNum = tonumber(query)
    if idNum and ix.byId[idNum] then
        local n = ix.byId[idNum]
        if not filter or filter(ix, n) then out[1] = n end
        return out
    end
    if query == '' then
        if not filter then return out end
        for n = 1, ix.n do
            if filter(ix, n) then
                out[#out + 1] = n
                if #out >= limit then break end
            end
        end
        return out
    end
    local words = {}
    for w in query:gmatch('%S+') do words[#words + 1] = w end
    local first = words[1]
    local lower = ix.lower
    local starts = ix.starts
    local buckets = { {}, {}, {}, {} }
    local seen = {}
    local qlen = #query
    local maxCollect = limit * 4
    -- Accepts entry n (after word / filter checks) into a rank bucket.
    local function accept(n, lineStart, lineEnd, s)
        if seen[n] then return end
        seen[n] = true
        local lname = nil
        if #words > 1 then
            lname = lower:sub(lineStart, lineEnd)
            for wi = 2, #words do
                if not lname:find(words[wi], 1, true) then return end
            end
        end
        if filter and not filter(ix, n) then return end
        local rank
        if #words > 1 then
            if lname == query then rank = 1
            elseif lname:sub(1, qlen) == query then rank = 2
            elseif s == lineStart then rank = 3
            else rank = 4 end
        elseif s == lineStart then
            rank = (lineEnd - lineStart + 1 == qlen) and 1 or 2
        elseif lower:sub(s - 1, s - 1) == ' ' then
            rank = 3
        else
            rank = 4
        end
        local b = buckets[rank]
        b[#b + 1] = n
        return true
    end
    -- Pass 1: matches at the start of a name (exact / prefix ranks). Few hits
    -- even for common words, so this pass sees the whole index.
    local collected = 0
    if lower:sub(1, #first) == first then
        if accept(1, 1, (starts[2] or (#lower + 2)) - 2, 1) then collected = collected + 1 end
    end
    local needle = '\n' .. first
    local init = 1
    while collected < maxCollect do
        local s = lower:find(needle, init, true)
        if not s then break end
        s = s + 1
        local n = entryAt(ix, s)
        local lineEnd = (starts[n + 1] or (#lower + 2)) - 2
        if accept(n, starts[n], lineEnd, s) then collected = collected + 1 end
        init = lineEnd + 2
        if init > #lower then break end
    end
    -- Pass 2: substring matches anywhere, bounded so a one-letter query
    -- cannot stall the frame.
    collected = 0
    init = 1
    while collected < maxCollect do
        local s = lower:find(first, init, true)
        if not s then break end
        local n = entryAt(ix, s)
        local lineStart = starts[n]
        local lineEnd = (starts[n + 1] or (#lower + 2)) - 2
        if accept(n, lineStart, lineEnd, s) then collected = collected + 1 end
        init = lineEnd + 2
        if init > #lower then break end
    end
    local names = ix.names
    for r = 1, 4 do
        local b = buckets[r]
        if #out >= limit then break end
        if #b <= 2000 then
            table.sort(b, function(x, y)
                local nx, ny = names[x], names[y]
                if nx ~= ny then return nx < ny end
                return x < y
            end)
        end
        for i = 1, #b do
            out[#out + 1] = b[i]
            if #out >= limit then break end
        end
    end
    return out
end

-- Raw record line for a packed ref (see packRef) or a "chunk:offset" string.
function DB.readLine(kind, ref)
    if type(ref) == 'string' then ref = packRef(ref) end
    if not ref then return nil end
    local chunk = math.floor(ref / REF_BASE)
    local off = ref - chunk * REF_BASE
    local key = kind .. '.' .. chunk
    local f = DB.handles[key]
    if not f then
        f = io.open(DB.resolveDir() .. key .. '.dat', 'rb')
        if not f then return nil end
        DB.handles[key] = f
    end
    if not f:seek('set', off) then return nil end
    local line = f:read('*l')
    if line and line:sub(-1) == '\r' then line = line:sub(1, -2) end
    return line
end

function DB.record(kind, ref)
    if not ref or ref == '' then return nil end
    local key = kind .. ':' .. tostring(ref)
    local rec = DB.cache[key]
    if rec then return rec end
    local line = DB.readLine(kind, ref)
    if not line then return nil end
    rec = ENC.parseRecord(line)
    if DB.cacheN >= 200 then
        DB.cache = {}
        DB.cacheN = 0
    end
    DB.cache[key] = rec
    DB.cacheN = DB.cacheN + 1
    return rec
end

-- ---- lookups by id --------------------------------------------------------
function DB.itemEntry(id)
    local ix = DB.kinds.items
    if not ix or not ix.loaded then return nil end
    local _, base = D.tierOf(id)
    local n = ix.byId[base]
    return n, ix
end

function DB.itemName(id)
    local tier, base = D.tierOf(id)
    local n, ix = DB.itemEntry(base)
    if not n then return 'Item ' .. tostring(id) end
    local name = ix.names[n]
    if tier == 'E' then return name .. ' (Enchanted)' end
    if tier == 'L' then return name .. ' (Legendary)' end
    return name
end

function DB.itemTiers(id)
    local n, ix = DB.itemEntry(id)
    if not n then return '' end
    return ix.extra[n] or ''
end

-- Record of one tier of an item; falls back to nil when the tier is missing.
function DB.itemRecord(baseId, tier)
    local n, ix = DB.itemEntry(baseId)
    if not n then return nil end
    tier = tier or 'B'
    local ref
    if tier == 'E' then ref = ix.refE[n]
    elseif tier == 'L' then ref = ix.refL[n]
    else ref = (ix.extra[n] or ''):find('B', 1, true) and ix.refs[n] or nil end
    if not ref then return nil end
    return DB.record('items', ref)
end

function DB.npcName(id)
    local ix = DB.kinds.npcs
    local n = ix and ix.loaded and ix.byId[tonumber(id) or -1]
    if not n then return 'NPC ' .. tostring(id) end
    return ix.names[n]
end

function DB.npcInfo(id)
    local ix = DB.kinds.npcs
    local n = ix and ix.loaded and ix.byId[tonumber(id) or -1]
    if not n then return nil end
    return { name = ix.names[n], lvl = ix.lvl[n], zone = ix.zone[n], ref = ix.refs[n] }
end

function DB.npcRecord(id)
    local info = DB.npcInfo(id)
    return info and DB.record('npcs', info.ref) or nil
end

function DB.spellName(id)
    local ix = DB.kinds.spells
    local n = ix and ix.loaded and ix.byId[tonumber(id) or -1]
    if not n then
        local nm = nil
        pcall(function() nm = mq and mq.TLO and mq.TLO.Spell(tonumber(id)).Name() end)
        if nm and nm ~= '' and nm ~= 'NULL' then return nm end
        return 'Spell ' .. tostring(id)
    end
    return ix.names[n]
end

function DB.spellRecord(id)
    local ix = DB.kinds.spells
    local n = ix and ix.loaded and ix.byId[tonumber(id) or -1]
    if not n then return nil end
    return DB.record('spells', ix.refs[n])
end

function DB.spellClasses(n)
    local ix = DB.kinds.spells
    return ix and ix.extra[n] or ''
end

-- Database NPC for a live spawn: same name (case-insensitive, underscores as
-- spaces, no leading '#'), preferring an entry in `zone` and then the closest
-- level. Returns the NPC id or nil.
function DB.npcIdFor(name, zone, level)
    local ix = DB.kinds.npcs
    if not ix or not ix.loaded or not ix.byName or not name then return nil end
    local key = tostring(name):gsub('^#', ''):gsub('_', ' '):lower()
    local hit = ix.byName[key]
    if not hit then return nil end
    if type(hit) == 'number' then return ix.ids[hit] end
    zone = (zone or ''):lower()
    level = tonumber(level) or 0
    local best, bestScore = nil, -1
    for _, n in ipairs(hit) do
        local score = 0
        if zone ~= '' and ix.zone[n]:lower() == zone then score = score + 1000 end
        if level > 0 then score = score + math.max(0, 100 - math.abs(ix.lvl[n] - level)) end
        if score > bestScore then best, bestScore = n, score end
    end
    return best and ix.ids[best] or nil
end

-- Special ability ids of an NPC record as a set { [id] = param }.
function DB.npcAbilities(npcId)
    local rec = DB.npcRecord(npcId)
    if not rec then return nil end
    local out = {}
    local raw = ENC.str(rec, 'special_abilities')
    for part in (raw .. '^'):gmatch('([^%^]*)%^') do
        local id, param = part:match('^(%d+),?(%d*)')
        if id and param ~= '0' then out[tonumber(id)] = tonumber(param) or 1 end
    end
    return out, rec
end

function DB.zoneName(short)
    if not short or short == '' then return '' end
    local ix = DB.kinds.zones
    local n = ix and ix.loaded and ix.byId[short]
    if not n then return short end
    return ix.names[n]
end

-- ----------------------------------------------------------------------------
-- UI state and navigation
-- ----------------------------------------------------------------------------
local S = {
    tab      = 'items',
    items    = { query = '', results = {}, sel = nil, tier = 'B', dirty = false, scroll = false },
    npcs     = { query = '', results = {}, sel = nil, zone = '', minLvl = 0, maxLvl = 0, dirty = false },
    spells   = { query = '', results = {}, sel = nil, class = 0, minLvl = 0, maxLvl = 0, dirty = false },
    history  = {},
    histPos  = 0,
    pendingTab = nil,
    status   = '',
    lastCursorId = 0,
    popouts  = {},   -- floating item cards: { key, kind, sel, tier, title }
    popoutSeq = 0,
    linkOpensWindow = false,
    -- Loot Advisor: rows for the corpse being looted
    lootAdvisor = true,
    loot = { open = false, corpseId = 0, npcId = nil, npcName = '', rows = {}, lastScan = 0 },
}
local MAX_POPOUTS = 8

local KINDS = { 'items', 'npcs', 'spells' }
local KIND_LABELS = { items = 'Items', npcs = 'NPCs', spells = 'Spells' }

local function queueAll()
    DB.ensure('zones')
    for _, k in ipairs(KINDS) do DB.ensure(k) end
end

local function stepLoading()
    if DB.loading or #DB.loadQueue > 0 then
        DB.stepLoad(ctrl and ctrl.show_gamedb and DB.BUDGET_OPEN or DB.BUDGET_IDLE)
    end
end


local function pushHistory(kind, id)
    -- drop forward entries, append, cap
    for i = #S.history, S.histPos + 1, -1 do table.remove(S.history, i) end
    S.history[#S.history + 1] = { kind = kind, id = id }
    if #S.history > 100 then table.remove(S.history, 1) end
    S.histPos = #S.history
end

local function showEntry(kind, id, noHistory)
    if not KIND_LABELS[kind] then return false end
    id = tonumber(id)
    if not id then return false end
    S.tab = kind
    S.pendingTab = kind
    if kind == 'items' then
        local tier, base = D.tierOf(id)
        S.items.sel = base
        S.items.tier = tier
        local tiers = DB.itemTiers(base)
        if tiers ~= '' and not tiers:find(tier, 1, true) then S.items.tier = tiers:sub(1, 1) end
    else
        S[kind].sel = id
    end
    if not noHistory then pushHistory(kind, id) end
    if S.linkOpensWindow and ctrl then ctrl.show_gamedb = true end
    return true
end

-- A floating card for one item (chat links, other plugins). Returns the
-- popout entry, or nil when the item is unknown. Re-opening an item that
-- already has a card just brings that card to the front.
local function openPopout(kind, id)
    if not KIND_LABELS[kind] then return nil end
    id = tonumber(id)
    if not id then return nil end
    local tier = 'B'
    if kind == 'items' then
        local base
        tier, base = D.tierOf(id)
        if not DB.itemEntry(base) then return nil end
        local tiers = DB.itemTiers(base)
        if tiers ~= '' and not tiers:find(tier, 1, true) then tier = tiers:sub(1, 1) end
        id = base
    elseif kind == 'npcs' then
        if not DB.npcInfo(id) then return nil end
    elseif not DB.spellRecord(id) then
        return nil
    end
    for _, pop in ipairs(S.popouts) do
        if pop.kind == kind and pop.sel == id then
            pop.tier = tier
            pop.focus = true
            return pop
        end
    end
    while #S.popouts >= MAX_POPOUTS do table.remove(S.popouts, 1) end
    S.popoutSeq = S.popoutSeq + 1
    local pop = { key = S.popoutSeq, kind = kind, sel = id, tier = tier, focus = true, showSources = false }
    S.popouts[#S.popouts + 1] = pop
    return pop
end

local function runSearch(kind)
    local st = S[kind]
    st.dirty = false
    local filter = nil
    if kind == 'npcs' then
        local zone = (st.zone or ''):lower()
        local minL, maxL = st.minLvl or 0, st.maxLvl or 0
        if zone ~= '' or minL > 0 or maxL > 0 then
            filter = function(ix, n)
                local z, l = ix.zone[n], ix.lvl[n]
                if zone ~= '' and not (z:lower():find(zone, 1, true) or DB.zoneName(z):lower():find(zone, 1, true)) then return false end
                if minL > 0 and l < minL then return false end
                if maxL > 0 and l > maxL then return false end
                return true
            end
        end
    elseif kind == 'spells' then
        local cls, minL, maxL = st.class or 0, st.minLvl or 0, st.maxLvl or 0
        if cls > 0 or minL > 0 or maxL > 0 then
            filter = function(ix, n)
                local classes = ix.extra[n] or ''
                if classes == '' then return false end
                if cls > 0 then
                    local lvl = tonumber(classes:match('%f[%d]' .. cls .. ':(%d+)'))
                    if not lvl then return false end
                    if minL > 0 and lvl < minL then return false end
                    if maxL > 0 and lvl > maxL then return false end
                    return true
                end
                for lvlStr in classes:gmatch(':(%d+)') do
                    local lvl = tonumber(lvlStr)
                    if (minL == 0 or lvl >= minL) and (maxL == 0 or lvl <= maxL) then return true end
                end
                return false
            end
        end
    end
    st.results = DB.search(kind, st.query, filter, DB.MAX_RESULTS)
end

-- Public entry points -------------------------------------------------------
function plugin.open(kind, id)
    if not core then return false end
    refresh()
    queueAll()
    ctrl.show_gamedb = true
    return showEntry(kind, id)
end

function plugin.search(kind, text)
    if not core then return false end
    refresh()
    kind = KIND_LABELS[kind] and kind or 'items'
    queueAll()
    S.tab = kind
    S.pendingTab = kind
    S[kind].query = tostring(text or '')
    S[kind].dirty = true
    ctrl.show_gamedb = true
    return true
end

-- Opens a floating card for an item id (tier offsets honoured). Loads the
-- indexes if needed; until they are ready the card shows a loading note.
function plugin.popout(kind, id)
    if not core then return false end
    refresh()
    queueAll()
    kind = KIND_LABELS[kind] and kind or 'items'
    if not DB.isLoaded(kind) then
        -- remember it; the card resolves once the index is in
        id = tonumber(id)
        if not id or id <= 0 then return false end
        S.popoutSeq = S.popoutSeq + 1
        while #S.popouts >= MAX_POPOUTS do table.remove(S.popouts, 1) end
        S.popouts[#S.popouts + 1] = { key = S.popoutSeq, kind = kind, sel = id, tier = 'B', pending = id, focus = true, showSources = false }
        return true
    end
    return openPopout(kind, id) ~= nil
end

function plugin.closePopouts()
    S.popouts = {}
end

-- Live spawn -> database NPC id (nil when the NPC index is not loaded or the
-- spawn is unknown). Cached per spawn id for the session.
local spawnNpcCache = {}
function plugin.npcIdForSpawn(spawnId)
    spawnId = tonumber(spawnId)
    if not spawnId or spawnId <= 0 or not mq then return nil end
    local cached = spawnNpcCache[spawnId]
    if cached ~= nil then return cached or nil end
    if not DB.isLoaded('npcs') then return nil end
    local name, level, zone = nil, 0, ''
    pcall(function()
        local sp = mq.TLO.Spawn(spawnId)
        if sp and sp() then
            name = sp.CleanName() or sp.Name()
            level = sp.Level() or 0
        end
        zone = mq.TLO.Zone.ShortName() or ''
    end)
    local id = name and DB.npcIdFor(name, zone, level) or nil
    if next(spawnNpcCache) and (spawnNpcCache.n or 0) > 500 then spawnNpcCache = {} end
    spawnNpcCache[spawnId] = id or false
    spawnNpcCache.n = (spawnNpcCache.n or 0) + 1
    return id
end

-- Cast tracker hook: reason a detrimental spell is wasted on this spawn, or
-- nil. Installed on core.castTracker.knownImmunity while the plugin runs.
function plugin.immunityReason(spellName, spawnId)
    local npcId = plugin.npcIdForSpawn(spawnId)
    if not npcId then return nil end
    local abilities = DB.npcAbilities(npcId)
    if not abilities or not next(abilities) then return nil end
    local function hasSPA(spa)
        local hit = false
        pcall(function()
            local res = mq.TLO.Spell(spellName).HasSPA(spa)
            if res == true or res == 1 then hit = true end
        end)
        return hit
    end
    return D.immunityReason(abilities, hasSPA)
end

-- Short "what the game does not tell you" lines for an item id, for other
-- plugins' tooltips (Inventory). Cached per base id. nil until the indexes
-- are loaded or when the item is unknown.
local summaryCache, summaryCount = {}, 0
function plugin.itemSummary(id)
    local _, base = D.tierOf(tonumber(id) or 0)
    if base <= 0 or not DB.isLoaded('items') or not DB.isLoaded('npcs') then return nil end
    local cached = summaryCache[base]
    if cached ~= nil then return cached or nil end
    local rec = DB.itemRecord(base, 'B')
    local lines = nil
    if rec then
        lines = {}
        local tiers = DB.itemTiers(base)
        if #tiers > 1 then
            local names = {}
            for t in tiers:gmatch('%a') do names[#names + 1] = D.TIER_NAMES[t] end
            lines[#lines + 1] = 'Tiers: ' .. table.concat(names, ' / ')
        end
        local drops = ENC.list(rec, 'drops')
        if #drops > 0 then
            local nid = tonumber(drops[1][1]) or 0
            local info = DB.npcInfo(nid)
            local total = #drops + (drops.more or 0)
            lines[#lines + 1] = string.format('Drops from: %s (%s) %s%%%s', info and info.name or ('NPC ' .. nid),
                info and DB.zoneName(info.zone) or '?', drops[1][2] or '?', total > 1 and string.format(', +%d more', total - 1) or '')
        end
        local quests = ENC.list(rec, 'quests')
        for i, q in ipairs(quests) do
            if i > 2 then
                lines[#lines + 1] = string.format('  +%d more quest NPCs', #quests - 2)
                break
            end
            local nid = tonumber(q[1]) or 0
            local who = nid > 0 and DB.npcName(nid) or (q[2] ~= '' and q[2] or 'Unknown NPC')
            lines[#lines + 1] = string.format('%s: %s (%s)', q[4] == 'R' and 'Quest reward from' or 'Quest turn-in to', who,
                q[3] == 'global' and 'Global' or DB.zoneName(q[3]))
        end
        local made = ENC.list(rec, 'made')
        local usedin = ENC.list(rec, 'usedin')
        if #made > 0 or #usedin > 0 then
            local parts = {}
            if #made > 0 then
                parts[#parts + 1] = string.format('made by %s (trivial %s)', D.skillName(tonumber(made[1][3]) or 0), made[1][5] ~= '' and made[1][5] or '?')
            end
            if #usedin > 0 then parts[#parts + 1] = string.format('used in %d recipe%s', #usedin + (usedin.more or 0), (#usedin + (usedin.more or 0)) == 1 and '' or 's') end
            lines[#lines + 1] = 'Tradeskill: ' .. table.concat(parts, '; ')
        end
        local sold = ENC.list(rec, 'sold')
        if #sold > 0 then lines[#lines + 1] = string.format('Sold by %d vendor%s', #sold + (sold.more or 0), (#sold + (sold.more or 0)) == 1 and '' or 's') end
        if #lines == 0 then lines[#lines + 1] = 'No known drop, quest or tradeskill source' end
    end
    if summaryCount >= 300 then
        summaryCache = {}
        summaryCount = 0
    end
    summaryCache[base] = lines or false
    summaryCount = summaryCount + 1
    return lines
end

-- Spell id for a spell name (exact, case-insensitive); when several spells
-- share the name, prefers one a class learns at `level`. nil when unknown.
function plugin.spellIdByName(name, level)
    local ix = DB.kinds.spells
    if not ix or not ix.loaded or not name or name == '' then return nil end
    local hits = DB.search('spells', name, nil, 20)
    local want = tostring(name):lower()
    level = tonumber(level) or 0
    local best = nil
    for _, n in ipairs(hits) do
        if ix.names[n]:lower() == want then
            if level > 0 and (ix.extra[n] or ''):find(':' .. level .. '%f[%D]') then return ix.ids[n] end
            best = best or ix.ids[n]
        end
    end
    return best
end

-- Tooltip lines for a spell: decoded effects (up to six) and where its
-- scrolls come from (through itemSummary). Cached per spell id.
local spellSummaryCache, spellSummaryCount = {}, 0
function plugin.spellSummary(id)
    id = tonumber(id)
    if not id or not DB.isLoaded('spells') or not DB.isLoaded('items') or not DB.isLoaded('npcs') then return nil end
    local cached = spellSummaryCache[id]
    if cached ~= nil then return cached or nil end
    local rec = DB.spellRecord(id)
    local lines = nil
    if rec then
        lines = {}
        local effects = ENC.list(rec, 'effects')
        for i, e in ipairs(effects) do
            if i > 6 then
                lines[#lines + 1] = string.format('  +%d more effects', #effects - 6)
                break
            end
            local text = D.spaText(tonumber(e[2]) or 0, e[3], e[4], e[5])
            text = text:gsub('%[spell (%d+)%]', function(sid) return DB.spellName(tonumber(sid)) end)
            text = text:gsub('%[item (%d+)%]', function(iid) return DB.itemName(tonumber(iid)) end)
            lines[#lines + 1] = text
        end
        local scrolls = 0
        for _, it in ipairs(ENC.list(rec, 'items')) do
            if it[1] == 'scroll' then
                scrolls = scrolls + 1
                if scrolls > 3 then break end
                local iid = tonumber(it[2]) or 0
                lines[#lines + 1] = 'Scroll: ' .. DB.itemName(iid)
                for _, l in ipairs(plugin.itemSummary(iid) or {}) do
                    if not l:find('^Tiers') then lines[#lines + 1] = '  ' .. l end
                end
            end
        end
        if scrolls == 0 then lines[#lines + 1] = 'No scroll item teaches this spell' end
    end
    if spellSummaryCount >= 300 then
        spellSummaryCache = {}
        spellSummaryCount = 0
    end
    spellSummaryCache[id] = lines or false
    spellSummaryCount = spellSummaryCount + 1
    return lines
end

-- Opens a popout card for the current target's database NPC.
function plugin.lookupTarget()
    if not core then return false end
    refresh()
    queueAll()
    local tid = 0
    pcall(function() tid = mq.TLO.Target.ID() or 0 end)
    if tid <= 0 then
        echo('No target.')
        return false
    end
    local npcId = plugin.npcIdForSpawn(tid)
    if not npcId then
        echo(DB.isLoaded('npcs') and 'Target not found in the database.' or 'NPC index still loading - try again in a moment.')
        return false
    end
    return plugin.popout('npcs', npcId)
end

function plugin.lookupCursor()
    if not core then return false end
    refresh()
    local id = 0
    pcall(function()
        local c = mq.TLO.Cursor
        if c() then id = c.ID() or 0 end
    end)
    if id <= 0 then
        echo('Nothing on the cursor.')
        return false
    end
    return plugin.open('items', id)
end

-- ----------------------------------------------------------------------------
-- Drawing helpers
-- ----------------------------------------------------------------------------
local C = {}   -- colors, filled on draw

local function txt(s) ImGui.Text(tostring(s)) end
local function muted(s) ImGui.TextColored(C.MUTED[1], C.MUTED[2], C.MUTED[3], C.MUTED[4], tostring(s)) end
local function good(s) ImGui.TextColored(C.GOOD[1], C.GOOD[2], C.GOOD[3], C.GOOD[4], tostring(s)) end
local function warn(s) ImGui.TextColored(C.WARN[1], C.WARN[2], C.WARN[3], C.WARN[4], tostring(s)) end
local function gold(s) ImGui.TextColored(C.GOLD[1], C.GOLD[2], C.GOLD[3], C.GOLD[4], tostring(s)) end

local function labelled(label, value)
    if value == nil or value == '' or value == 0 then return end
    muted(label .. ':')
    ImGui.SameLine()
    txt(value)
end

local function header(s)
    ImGui.Dummy(0, core.px(4))
    ImGui.TextColored(C.GOLD[1], C.GOLD[2], C.GOLD[3], C.GOLD[4], s)
    ImGui.Separator()
end

-- A clickable cross-reference drawn as inline text (so it can share a line).
-- Returns true when clicked.
local function link(label, _)
    ImGui.TextColored(C.ARC[1], C.ARC[2], C.ARC[3], C.ARC[4], tostring(label))
    local hovered = ImGui.IsItemHovered()
    if hovered then
        if ImGuiMouseCursor then pcall(function() ImGui.SetMouseCursor(ImGuiMouseCursor.Hand) end) end
    end
    return hovered and ImGui.IsItemClicked()
end

-- Item icon via the shared A_DragItem animation (cell = icon - 500).
local ICON = { mode = 'probe', shared = nil, lastCell = nil }
local function itemIconAnim(iconId)
    local id = tonumber(iconId)
    if not id or id <= 0 or not mq then return nil end
    if ICON.mode == 'probe' then
        ICON.mode = 'none'
        if mq.FindTextureAnimation then
            local ok, res = pcall(mq.FindTextureAnimation, 'A_DragItem')
            if ok and res then
                ICON.mode = 'shared'
                ICON.shared = res
            end
        end
    end
    if ICON.mode ~= 'shared' then return nil end
    local cell = (id >= 500) and (id - 500) or id
    if ICON.lastCell ~= cell then
        if not pcall(function() ICON.shared:SetTextureCell(cell) end) then return nil end
        ICON.lastCell = cell
    end
    return ICON.shared
end

local function drawIcon(anim, size)
    if anim and ImGui.DrawTextureAnimation then
        local ok = pcall(function() ImGui.DrawTextureAnimation(anim, size, size) end)
        if ok then return true end
    end
    ImGui.Dummy(size, size)
    return false
end

local function fmtSigned(v)
    v = tonumber(v) or 0
    if v > 0 then return '+' .. v end
    return tostring(v)
end

local function fmtStatHeroic(v, h)
    v = tonumber(v) or 0
    h = tonumber(h) or 0
    if v == 0 and h == 0 then return nil end
    if h ~= 0 then return string.format('%s (+%d)', fmtSigned(v), h) end
    return fmtSigned(v)
end

-- ----------------------------------------------------------------------------
-- Item card
-- ----------------------------------------------------------------------------
local function spellLinkLine(label, spellId, extra)
    if (tonumber(spellId) or 0) <= 0 then return end
    muted(label .. ':')
    ImGui.SameLine()
    if link(DB.spellName(spellId), 'spell' .. label .. spellId) then showEntry('spells', spellId) end
    if extra and extra ~= '' then
        ImGui.SameLine()
        muted(extra)
    end
end

local function drawItemStats(rec)
    local n = function(k) return ENC.num(rec, k) end
    local flags = {}
    if n('magic') > 0 then flags[#flags + 1] = 'MAGIC' end
    if n('loregroup') ~= 0 then flags[#flags + 1] = 'LORE' end
    if n('NODROP') > 0 then flags[#flags + 1] = 'NO DROP' end
    if n('NORENT') > 0 then flags[#flags + 1] = 'NO RENT' end
    if n('attuneable') > 0 then flags[#flags + 1] = 'ATTUNEABLE' end
    if n('questitemflag') > 0 then flags[#flags + 1] = 'QUEST' end
    if n('heirloom') > 0 then flags[#flags + 1] = 'HEIRLOOM' end
    if n('artifactflag') > 0 then flags[#flags + 1] = 'ARTIFACT' end
    if n('placeable') > 0 then flags[#flags + 1] = 'PLACEABLE' end
    if n('fvnodrop') > 0 then flags[#flags + 1] = 'FV NO DROP' end
    if n('notransfer') > 0 then flags[#flags + 1] = 'NO TRANSFER' end
    if n('nopet') > 0 then flags[#flags + 1] = 'NO PET' end
    if n('epicitem') > 0 then flags[#flags + 1] = 'EPIC' end
    if n('augdistiller') > 0 then flags[#flags + 1] = 'AUG DISTILLER' end
    if #flags > 0 then warn(table.concat(flags, '  ')) end

    local itemtype = n('itemtype')
    local isAug = itemtype == 54
    local isWeapon = (itemtype <= 5) or itemtype == 7 or itemtype == 18 or itemtype == 27 or itemtype == 35 or itemtype == 45
    local slots = D.slotsText(n('slots'))
    labelled('Slot', slots ~= '' and slots or nil)
    local typeText = D.itemTypeName(itemtype)
    if isWeapon and n('damage') > 0 then typeText = typeText .. string.format('  Atk Delay: %d', n('delay')) end
    labelled('Type', typeText)
    if n('recskill') > 0 then labelled('Skill', D.skillName(n('recskill'))) end
    labelled('Size', D.sizeName(n('size')) .. '   Weight: ' .. D.weightText(n('weight')))
    if n('reqlevel') > 0 or n('reclevel') > 0 then
        local s = ''
        if n('reqlevel') > 0 then s = 'Required Level: ' .. n('reqlevel') end
        if n('reclevel') > 0 then s = s .. (s ~= '' and '   ' or '') .. 'Recommended Level: ' .. n('reclevel') end
        txt(s)
    end
    labelled('Class', D.classesText(n('classes')))
    labelled('Race', D.racesText(n('races')))
    if n('deity') > 0 then labelled('Deity', D.deityName(n('deity'))) end

    -- combat + stats table
    local tableFlags = ImGuiTableFlags.SizingFixedFit
    if ImGui.BeginTable('##itemstats', 6, tableFlags) then
        local rows = {}
        local function add(col, label, value) rows[#rows + 1] = { col, label, value } end
        if n('ac') ~= 0 then add(1, 'AC', n('ac')) end
        if isWeapon and n('damage') > 0 then
            add(1, 'Damage', n('damage'))
            add(1, 'Delay', n('delay'))
            if n('delay') > 0 then add(1, 'Ratio', string.format('%.3f', n('damage') / n('delay'))) end
        end
        if n('range') > 0 then add(1, 'Range', n('range')) end
        if n('backstabdmg') > 0 then add(1, 'Backstab Dmg', n('backstabdmg')) end
        if n('elemdmgamt') > 0 then add(1, ({ [1] = 'Magic', [2] = 'Fire', [3] = 'Cold', [4] = 'Poison', [5] = 'Disease', [6] = 'Chromatic', [7] = 'Prismatic', [8] = 'Physical', [9] = 'Corruption' })[n('elemdmgtype')] or 'Elem', n('elemdmgamt')) end
        if n('banedmgamt') > 0 then add(1, 'Bane ' .. D.bodyTypeName(n('banedmgbody')), n('banedmgamt')) end
        if n('banedmgraceamt') > 0 then add(1, 'Bane ' .. D.raceName(n('banedmgrace')), n('banedmgraceamt')) end
        if n('hp') ~= 0 then add(1, 'HP', fmtSigned(n('hp'))) end
        if n('mana') ~= 0 then add(1, 'Mana', fmtSigned(n('mana'))) end
        if n('endur') ~= 0 then add(1, 'Endurance', fmtSigned(n('endur'))) end
        for _, s in ipairs({ { 'astr', 'heroic_str', 'STR' }, { 'asta', 'heroic_sta', 'STA' }, { 'aagi', 'heroic_agi', 'AGI' }, { 'adex', 'heroic_dex', 'DEX' },
                             { 'awis', 'heroic_wis', 'WIS' }, { 'aint', 'heroic_int', 'INT' }, { 'acha', 'heroic_cha', 'CHA' } }) do
            local v = fmtStatHeroic(n(s[1]), n(s[2]))
            if v then add(2, s[3], v) end
        end
        for _, s in ipairs({ { 'mr', 'heroic_mr', 'Magic' }, { 'fr', 'heroic_fr', 'Fire' }, { 'cr', 'heroic_cr', 'Cold' }, { 'dr', 'heroic_dr', 'Disease' },
                             { 'pr', 'heroic_pr', 'Poison' }, { 'svcorruption', 'heroic_svcorrup', 'Corruption' } }) do
            local v = fmtStatHeroic(n(s[1]), n(s[2]))
            if v then add(3, s[3], v) end
        end
        for _, s in ipairs({ { 'attack', 'Attack' }, { 'haste', 'Haste', '%' }, { 'regen', 'HP Regen' }, { 'manaregen', 'Mana Regen' }, { 'enduranceregen', 'End Regen' },
                             { 'accuracy', 'Accuracy' }, { 'avoidance', 'Avoidance' }, { 'shielding', 'Shielding', '%' }, { 'spellshield', 'Spell Shield', '%' },
                             { 'strikethrough', 'Strikethrough', '%' }, { 'stunresist', 'Stun Resist', '%' }, { 'dotshielding', 'DoT Shielding', '%' },
                             { 'damageshield', 'Damage Shield' }, { 'dsmitigation', 'DS Mitigation' }, { 'combateffects', 'Combat Effects' },
                             { 'healamt', 'Heal Amount' }, { 'spelldmg', 'Spell Dmg' }, { 'clairvoyance', 'Clairvoyance' } }) do
            local v = n(s[1])
            if v ~= 0 then add(3, s[2], fmtSigned(v) .. (s[3] or '')) end
        end
        if n('skillmodvalue') ~= 0 then add(3, D.skillName(n('skillmodtype')), fmtSigned(n('skillmodvalue')) .. '%') end
        -- lay out: three column pairs
        local cols = { {}, {}, {} }
        for _, r in ipairs(rows) do table.insert(cols[r[1]], r) end
        local maxRows = math.max(#cols[1], #cols[2], #cols[3])
        for i = 1, maxRows do
            ImGui.TableNextRow()
            for c = 1, 3 do
                local r = cols[c][i]
                ImGui.TableSetColumnIndex((c - 1) * 2)
                if r then muted(r[2] .. ':') end
                ImGui.TableSetColumnIndex((c - 1) * 2 + 1)
                if r then txt(r[3]) end
            end
        end
        ImGui.EndTable()
    end

    -- effects
    local effects = false
    local function eff(label, idKey, typeKey, lvlKey, extraFn)
        local sid = n(idKey)
        if sid <= 0 then return end
        effects = true
        local extra = {}
        if typeKey and n(typeKey) > 0 and D.CLICK_TYPES[n(typeKey)] and D.CLICK_TYPES[n(typeKey)] ~= '' and label == 'Effect' then extra[#extra + 1] = D.CLICK_TYPES[n(typeKey)] end
        if lvlKey and n(lvlKey) > 0 then extra[#extra + 1] = 'Level ' .. n(lvlKey) end
        if extraFn then
            local e = extraFn()
            if e and e ~= '' then extra[#extra + 1] = e end
        end
        spellLinkLine(label, sid, #extra > 0 and ('(' .. table.concat(extra, ', ') .. ')') or '')
    end
    eff('Effect', 'clickeffect', 'clicktype', 'clicklevel2', function()
        local parts = {}
        if n('casttime') > 0 then parts[#parts + 1] = string.format('Cast %.1fs', n('casttime') / 1000) end
        if n('recastdelay') > 0 then parts[#parts + 1] = 'Recast ' .. D.secondsText(n('recastdelay')) end
        if n('maxcharges') > 0 then parts[#parts + 1] = 'Charges ' .. n('maxcharges') elseif n('maxcharges') < 0 then parts[#parts + 1] = 'Unlimited charges' end
        return table.concat(parts, ', ')
    end)
    eff('Proc', 'proceffect', nil, 'proclevel2', function() return n('procrate') ~= 0 and ('Rate ' .. fmtSigned(n('procrate')) .. '%') or '' end)
    eff('Worn', 'worneffect', nil, 'wornlevel2')
    eff('Focus', 'focuseffect', nil, 'focuslevel2')
    eff('Scroll', 'scrolleffect', nil, 'scrolllevel2')
    eff('Bard', 'bardeffect', nil, 'bardlevel2')
    if n('bardtype') > 0 then labelled('Instrument', string.format('%s (+%d%%)', D.skillName(n('bardtype')), n('bardvalue'))) end

    -- augment slots
    local augSlots = {}
    for i = 1, 6 do
        local t = n('augslot' .. i .. 'type')
        if t > 0 then augSlots[#augSlots + 1] = string.format('%d (%s)', t, D.AUG_TYPES[t] or ('Type ' .. t)) end
    end
    if #augSlots > 0 then labelled('Aug Slots', table.concat(augSlots, ', ')) end
    if isAug then
        labelled('Aug Type', D.augTypesText(n('augtype')))
        if n('augrestrict') > 0 then labelled('Aug Restriction', tostring(n('augrestrict'))) end
    end
    if n('bagslots') > 0 then
        labelled('Container', string.format('%d slots, up to %s items, %d%% weight reduction', n('bagslots'), D.sizeName(n('bagsize')), n('bagwr')))
    end
    if n('stackable') > 0 and n('stacksize') > 1 then labelled('Stack', tostring(n('stacksize'))) end
    if n('price') > 0 then labelled('Value', D.moneyText(n('price'))) end
    if n('ldonprice') > 0 then labelled('LDoN', string.format('%d points (theme %d)', n('ldonprice'), n('ldontheme'))) end
    if n('tradeskills') > 0 then muted('Tradeskill item') end
    local lore = ENC.str(rec, 'lore')
    if lore ~= '' then
        ImGui.PushStyleColor(ImGuiCol.Text, C.MUTED[1], C.MUTED[2], C.MUTED[3], C.MUTED[4])
        ImGui.TextWrapped(lore)
        ImGui.PopStyleColor()
    end
    if not effects and n('book') > 0 then muted('Book') end
end

local function drawItemSources(base)
    local drops = ENC.list(base, 'drops')
    local quests = ENC.list(base, 'quests')
    local made = ENC.list(base, 'made')
    local usedin = ENC.list(base, 'usedin')
    local src = ENC.list(base, 'src')
    local sold = ENC.list(base, 'sold')
    local any = #drops + #quests + #made + #usedin + #src + #sold
    if any == 0 then
        header('Sources')
        muted('No known drop, quest, tradeskill or vendor source.')
        return
    end

    if #drops > 0 then
        header(string.format('Drops From (%d%s)', #drops, drops.more and (' of ' .. (#drops + drops.more)) or ''))
        if ImGui.BeginTable('##drops', 4, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
            ImGui.TableSetupColumn('NPC', ImGuiTableColumnFlags.WidthStretch, 3)
            ImGui.TableSetupColumn('Lvl', ImGuiTableColumnFlags.WidthFixed, core.px(36))
            ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthStretch, 3)
            ImGui.TableSetupColumn('Chance', ImGuiTableColumnFlags.WidthFixed, core.px(60))
            ImGui.TableHeadersRow()
            for _, d in ipairs(drops) do
                local nid = tonumber(d[1]) or 0
                local info = DB.npcInfo(nid)
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                if link(info and info.name or ('NPC ' .. nid), 'drop' .. nid) then showEntry('npcs', nid) end
                ImGui.TableSetColumnIndex(1); txt(info and info.lvl or '')
                ImGui.TableSetColumnIndex(2); txt(info and DB.zoneName(info.zone) or '')
                ImGui.TableSetColumnIndex(3); txt((d[2] or '') .. '%')
            end
            ImGui.EndTable()
        end
    end

    if #quests > 0 then
        header('Quests')
        if ImGui.BeginTable('##quests', 3, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
            ImGui.TableSetupColumn('NPC', ImGuiTableColumnFlags.WidthStretch, 3)
            ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthStretch, 3)
            ImGui.TableSetupColumn('Role', ImGuiTableColumnFlags.WidthFixed, core.px(70))
            ImGui.TableHeadersRow()
            for _, q in ipairs(quests) do
                local nid = tonumber(q[1]) or 0
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                if nid > 0 then
                    if link(DB.npcName(nid), 'q' .. nid .. q[4]) then showEntry('npcs', nid) end
                else
                    txt(q[2] ~= '' and q[2] or 'Unknown NPC')
                end
                ImGui.TableSetColumnIndex(1); txt(q[3] == 'global' and 'Global' or DB.zoneName(q[3]))
                ImGui.TableSetColumnIndex(2)
                if q[4] == 'R' then good('Reward') else warn('Turn-in') end
            end
            ImGui.EndTable()
        end
    end

    if #made > 0 then
        header('Tradeskill: Made By')
        for i, r in ipairs(made) do
            local skill = D.skillName(tonumber(r[3]) or 0)
            local line = string.format('%s  -  %s', r[2] ~= '' and r[2] or ('Recipe ' .. r[1]), skill)
            local reqs = {}
            if (tonumber(r[4]) or 0) > 0 then reqs[#reqs + 1] = 'skill ' .. r[4] end
            if (tonumber(r[5]) or 0) > 0 then reqs[#reqs + 1] = 'trivial ' .. r[5] end
            if r[6] == '1' then reqs[#reqs + 1] = 'no fail' end
            if r[7] == '1' then reqs[#reqs + 1] = 'must learn' end
            if r[9] == '1' then reqs[#reqs + 1] = 'quest' end
            if #reqs > 0 then line = line .. ' (' .. table.concat(reqs, ', ') .. ')' end
            good(line)
            if (tonumber(r[8]) or 0) > 0 then
                ImGui.Indent(core.px(12))
                muted('Learned from:')
                ImGui.SameLine()
                if link(DB.itemName(tonumber(r[8])), 'learn' .. i .. r[8]) then showEntry('items', tonumber(r[8])) end
                ImGui.Unindent(core.px(12))
            end
            local comps = ENC.nested(r[10])
            local conts = ENC.nested(r[11])
            local results = ENC.nested(r[12])
            ImGui.Indent(core.px(12))
            if #conts > 0 then
                local names = {}
                for _, c in ipairs(conts) do
                    local cid = tonumber(c[1]) or 0
                    names[#names + 1] = cid > 0 and DB.itemName(cid) or (c[2] or 'container')
                end
                muted('In: ' .. table.concat(names, ' / '))
            end
            for ci, c in ipairs(comps) do
                local cid = tonumber(c[1]) or 0
                local cnt = tonumber(c[2]) or 1
                if link(string.format('%s x%d', DB.itemName(cid), cnt), 'comp' .. i .. '_' .. ci) then showEntry('items', cid) end
            end
            if #results > 1 then
                local names = {}
                for _, rr in ipairs(results) do names[#names + 1] = DB.itemName(tonumber(rr[1]) or 0) end
                muted('Yields: ' .. table.concat(names, ', '))
            end
            ImGui.Unindent(core.px(12))
        end
    end

    if #usedin > 0 then
        header(string.format('Tradeskill: Used In (%d%s)', #usedin, usedin.more and (' of ' .. (#usedin + usedin.more)) or ''))
        if ImGui.BeginTable('##usedin', 3, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
            ImGui.TableSetupColumn('Result', ImGuiTableColumnFlags.WidthStretch, 4)
            ImGui.TableSetupColumn('Tradeskill', ImGuiTableColumnFlags.WidthStretch, 2)
            ImGui.TableSetupColumn('Trivial', ImGuiTableColumnFlags.WidthFixed, core.px(50))
            ImGui.TableHeadersRow()
            for i, u in ipairs(usedin) do
                local rid = tonumber(u[4]) or 0
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                if rid > 0 then
                    if link(DB.itemName(rid), 'use' .. i) then showEntry('items', rid) end
                else
                    txt('Recipe ' .. u[1])
                end
                ImGui.TableSetColumnIndex(1); txt(D.skillName(tonumber(u[2]) or 0))
                ImGui.TableSetColumnIndex(2); txt(u[3])
            end
            ImGui.EndTable()
        end
    end

    if #src > 0 then
        header('Gathered')
        for _, s in ipairs(src) do
            local kind = ({ F = 'Foraged in', W = 'Fished in', G = 'Ground spawn in' })[s[1]] or s[1]
            local zone = DB.zoneName(s[2])
            local chance = (s[3] and s[3] ~= '') and (' (' .. s[3] .. '%)') or ''
            txt(string.format('%s %s%s', kind, zone, chance))
        end
    end

    if #sold > 0 then
        header(string.format('Sold By (%d%s)', #sold, sold.more and (' of ' .. (#sold + sold.more)) or ''))
        for _, v in ipairs(sold) do
            local nid = tonumber(v[1]) or 0
            local info = DB.npcInfo(nid)
            if link(string.format('%s  -  %s', info and info.name or ('NPC ' .. nid), info and DB.zoneName(info.zone) or ''), 'sold' .. nid) then showEntry('npcs', nid) end
        end
    end
end

-- Item card body for a state table { sel = baseId, tier = 'B'|'E'|'L' }:
-- the main pane passes S.items, a popout passes its own entry. `compact`
-- collapses the sources behind a header.
local function drawItemCardFor(st, compact)
    local base = st.sel
    if not base then
        muted('Search for an item, or click Cursor Item.')
        return
    end
    local tiers = DB.itemTiers(base)
    if tiers ~= '' and not tiers:find(st.tier or 'B', 1, true) then st.tier = tiers:sub(1, 1) end
    local rec = DB.itemRecord(base, st.tier)
    local baseRec = DB.itemRecord(base, 'B') or rec
    if not rec then
        warn('Item ' .. base .. ' is not in the database.')
        return
    end
    local id = base + D.TIER_OFFSET[st.tier]
    local name = DB.itemName(id)

    -- header: icon, name, tier buttons
    local anim = itemIconAnim(ENC.num(rec, 'icon'))
    drawIcon(anim, core.px(40))
    ImGui.SameLine()
    ImGui.BeginGroup()
    gold(name)
    muted('ID ' .. id .. (tiers ~= '' and ('   Tiers: ' .. tiers:gsub('B', 'Base '):gsub('E', 'Enchanted '):gsub('L', 'Legendary ')) or ''))
    ImGui.EndGroup()
    if #tiers > 1 then
        for _, t in ipairs({ 'B', 'E', 'L' }) do
            if tiers:find(t, 1, true) then
                local active = st.tier == t
                if active then ImGui.PushStyleColor(ImGuiCol.Button, C.GOLD[1] * 0.6, C.GOLD[2] * 0.6, C.GOLD[3] * 0.6, 1.0) end
                if ImGui.SmallButton(D.TIER_NAMES[t] .. '##tier' .. t) then st.tier = t end
                if active then ImGui.PopStyleColor() end
                ImGui.SameLine()
            end
        end
        ImGui.NewLine()
    end
    ImGui.Separator()
    drawItemStats(rec)
    if compact then
        ImGui.Dummy(0, core.px(4))
        if ImGui.SmallButton('Open in Database##pop' .. tostring(st.key)) then
            showEntry('items', id)
            ctrl.show_gamedb = true
        end
        ImGui.SameLine()
        local label = st.showSources and 'Hide sources' or 'Show sources'
        if ImGui.SmallButton(label .. '##popsrc' .. tostring(st.key)) then st.showSources = not st.showSources end
        if st.showSources then drawItemSources(baseRec) end
    else
        drawItemSources(baseRec)
    end
end

local function drawItemCard()
    drawItemCardFor(S.items, false)
end

-- The Map plugin (tac/map.lua) when it is loaded and enabled.
local function mapPlugin()
    local pm = core and core.runtime and core.runtime.pluginManager
    local p = pm and pm.plugins and pm.plugins.map
    if p and p.enabled and p.instance and p.instance.showZone then return p.instance end
    return nil
end

-- ----------------------------------------------------------------------------
-- NPC card
-- ----------------------------------------------------------------------------
local function drawNpcCardFor(st)
    local id = st.sel
    if not id then
        muted('Search for an NPC by name (filter by zone or level on the left).')
        return
    end
    local rec = DB.npcRecord(id)
    if not rec then
        warn('NPC ' .. id .. ' is not in the database.')
        return
    end
    local n = function(k) return ENC.num(rec, k) end
    local name = ENC.str(rec, 'name')
    local last = ENC.str(rec, 'lastname')
    gold(name .. (last ~= '' and (' (' .. last .. ')') or ''))
    local lvl = n('level')
    if n('maxlevel') > lvl then lvl = lvl .. '-' .. n('maxlevel') end
    muted(string.format('ID %d   Level %s   %s %s   %s', id, tostring(lvl), D.raceName(n('race')), D.className(n('class')), D.bodyTypeName(n('bodytype'))))
    local tags = {}
    if n('raid_target') > 0 then tags[#tags + 1] = 'RAID TARGET' end
    if n('rare_spawn') > 0 then tags[#tags + 1] = 'RARE' end
    if n('quest') > 0 or n('isquest') > 0 then tags[#tags + 1] = 'QUEST NPC' end
    if n('merchant_id') > 0 then tags[#tags + 1] = 'MERCHANT' end
    if n('trackable') == 0 then tags[#tags + 1] = 'UNTRACKABLE' end
    if n('untargetable') > 0 then tags[#tags + 1] = 'UNTARGETABLE' end
    if #tags > 0 then warn(table.concat(tags, '  ')) end
    ImGui.Separator()

    if ImGui.BeginTable('##npcstats', 6, ImGuiTableFlags.SizingFixedFit) then
        local cols = { {}, {}, {} }
        local function add(c, l, v) if v ~= nil and v ~= 0 and v ~= '' then table.insert(cols[c], { l, v }) end end
        add(1, 'HP', n('hp'))
        add(1, 'Mana', n('mana'))
        add(1, 'AC', n('AC'))
        if n('maxdmg') > 0 then add(1, 'Damage', string.format('%d - %d', n('mindmg'), n('maxdmg'))) end
        if n('attack_delay') > 0 then add(1, 'Attack Delay', n('attack_delay')) end
        if n('attack_count') > 0 then add(1, 'Attacks', n('attack_count')) end
        if n('attack_speed') ~= 0 then add(1, 'Attack Speed', fmtSigned(n('attack_speed')) .. '%') end
        if n('runspeed') > 0 then add(1, 'Run Speed', string.format('%.2f', n('runspeed'))) end
        if n('hp_regen_rate') > 0 then add(1, 'HP Regen', n('hp_regen_rate')) end
        if n('mana_regen_rate') > 0 then add(1, 'Mana Regen', n('mana_regen_rate')) end
        for _, s in ipairs({ { 'MR', 'Magic' }, { 'FR', 'Fire' }, { 'CR', 'Cold' }, { 'DR', 'Disease' }, { 'PR', 'Poison' }, { 'Corrup', 'Corruption' }, { 'PhR', 'Physical' } }) do
            add(2, s[2], n(s[1]))
        end
        for _, s in ipairs({ { 'STR', 'STR' }, { 'STA', 'STA' }, { 'AGI', 'AGI' }, { 'DEX', 'DEX' }, { 'WIS', 'WIS' }, { '_INT', 'INT' }, { 'CHA', 'CHA' }, { 'ATK', 'ATK' }, { 'Accuracy', 'Accuracy' }, { 'Avoidance', 'Avoidance' } }) do
            add(3, s[2], n(s[1]))
        end
        if n('aggroradius') > 0 then add(3, 'Aggro Radius', n('aggroradius')) end
        if n('assistradius') > 0 then add(3, 'Assist Radius', n('assistradius')) end
        if n('exp_mod') > 0 and n('exp_mod') ~= 100 then add(3, 'XP Mod', n('exp_mod') .. '%') end
        if n('slow_mitigation') > 0 then add(3, 'Slow Mitigation', n('slow_mitigation') .. '%') end
        local maxRows = math.max(#cols[1], #cols[2], #cols[3])
        for i = 1, maxRows do
            ImGui.TableNextRow()
            for c = 1, 3 do
                local r = cols[c][i]
                ImGui.TableSetColumnIndex((c - 1) * 2)
                if r then muted(r[1] .. ':') end
                ImGui.TableSetColumnIndex((c - 1) * 2 + 1)
                if r then txt(r[2]) end
            end
        end
        ImGui.EndTable()
    end

    local abilities = D.specialAbilitiesText(ENC.str(rec, 'special_abilities'))
    local sees = {}
    if n('see_invis') > 0 then sees[#sees + 1] = 'Sees Invisible' end
    if n('see_invis_undead') > 0 then sees[#sees + 1] = 'Sees Invis vs Undead' end
    if n('see_hide') > 0 then sees[#sees + 1] = 'Sees Hide' end
    if n('see_improved_hide') > 0 then sees[#sees + 1] = 'Sees Improved Hide' end
    if n('npc_aggro') > 0 then sees[#sees + 1] = 'Aggro' end
    for _, s in ipairs(sees) do abilities[#abilities + 1] = s end
    if #abilities > 0 then
        muted('Abilities:')
        ImGui.SameLine()
        ImGui.TextWrapped(table.concat(abilities, ', '))
    end
    local faction = ENC.str(rec, 'faction')
    if faction ~= '' then labelled('Faction', faction) end
    local hits = ENC.list(rec, 'fachits')
    if #hits > 0 then
        local parts = {}
        for _, h in ipairs(hits) do parts[#parts + 1] = string.format('%s %s', h[1], fmtSigned(h[2])) end
        muted('Faction hits:')
        ImGui.SameLine()
        ImGui.TextWrapped(table.concat(parts, ', '))
    end

    local spawns = ENC.list(rec, 'spawns')
    header(#spawns > 0 and string.format('Spawns In (%d zone%s)', #spawns, #spawns == 1 and '' or 's') or 'Spawns')
    if #spawns == 0 then
        muted('No spawn point (summoned, pet, or scripted).')
    elseif ImGui.BeginTable('##spawns', 5, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
        local map = mapPlugin()
        ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthStretch, 4)
        ImGui.TableSetupColumn('Points', ImGuiTableColumnFlags.WidthFixed, core.px(50))
        ImGui.TableSetupColumn('Respawn', ImGuiTableColumnFlags.WidthFixed, core.px(80))
        ImGui.TableSetupColumn('Chance', ImGuiTableColumnFlags.WidthFixed, core.px(60))
        ImGui.TableSetupColumn('##map', ImGuiTableColumnFlags.WidthFixed, core.px(44))
        ImGui.TableHeadersRow()
        for i, s in ipairs(spawns) do
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); txt(DB.zoneName(s[1]) .. '  (' .. s[1] .. ')')
            ImGui.TableSetColumnIndex(1); txt(s[2])
            ImGui.TableSetColumnIndex(2); txt(D.secondsText(tonumber(s[3]) or 0))
            ImGui.TableSetColumnIndex(3); txt((s[4] or '') .. '%')
            ImGui.TableSetColumnIndex(4)
            if map then
                if ImGui.SmallButton('Map##sp' .. i .. tostring(st.key or '')) then map.showZone(s[1]) end
                if ImGui.IsItemHovered() then ImGui.SetTooltip('Open the Zone Atlas on ' .. DB.zoneName(s[1])) end
            end
        end
        ImGui.EndTable()
    end

    local drops = ENC.list(rec, 'drops')
    if #drops > 0 then
        header(string.format('Drops (%d%s)', #drops, drops.more and (' of ' .. (#drops + drops.more)) or ''))
        if ImGui.BeginTable('##npcdrops', 2, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
            ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch, 5)
            ImGui.TableSetupColumn('Chance', ImGuiTableColumnFlags.WidthFixed, core.px(60))
            ImGui.TableHeadersRow()
            for i, d in ipairs(drops) do
                local iid = tonumber(d[1]) or 0
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                if link(DB.itemName(iid), 'nd' .. i) then showEntry('items', iid) end
                ImGui.TableSetColumnIndex(1); txt((d[2] or '') .. '%')
            end
            ImGui.EndTable()
        end
    end

    local casts = ENC.list(rec, 'casts')
    if #casts > 0 then
        header(string.format('Casts (%d)', #casts))
        for i, c in ipairs(casts) do
            local sid = tonumber(c[1]) or 0
            if link(DB.spellName(sid), 'nc' .. i) then showEntry('spells', sid) end
            local t = D.npcSpellTypes(tonumber(c[2]) or 0)
            if t ~= '' then
                ImGui.SameLine()
                muted('(' .. t .. ')')
            end
        end
    end

    if n('quest') > 0 then
        local rewards = ENC.list(rec, 'qrewards')
        local handins = ENC.list(rec, 'qhandins')
        if #rewards > 0 or #handins > 0 then
            header('Quest')
            if #handins > 0 then
                muted('Accepts:')
                for i, h in ipairs(handins) do
                    local iid = tonumber(h[1]) or 0
                    if link(DB.itemName(iid), 'qh' .. i) then showEntry('items', iid) end
                end
            end
            if #rewards > 0 then
                muted('Rewards:')
                for i, r in ipairs(rewards) do
                    local iid = tonumber(r[1]) or 0
                    if link(DB.itemName(iid), 'qr' .. i) then showEntry('items', iid) end
                end
            end
        end
    end

    local sells = ENC.list(rec, 'sells')
    if #sells > 0 then
        header(string.format('Sells (%d%s)', #sells, sells.more and (' of ' .. (#sells + sells.more)) or ''))
        for i, s in ipairs(sells) do
            local iid = tonumber(s[1]) or 0
            if link(DB.itemName(iid), 'ns' .. i) then showEntry('items', iid) end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Spell card
-- ----------------------------------------------------------------------------
local function spellClassesText(classes)
    local out = {}
    for c, l in (classes or ''):gmatch('(%d+):(%d+)') do
        out[#out + 1] = string.format('%s %s', D.CLASSES[tonumber(c)] or ('C' .. c), l)
    end
    return table.concat(out, '  ')
end

local function drawSpellCardFor(st)
    local id = st.sel
    if not id then
        muted('Search for a spell by name (filter by class and level on the left).')
        return
    end
    local rec = DB.spellRecord(id)
    if not rec then
        warn('Spell ' .. id .. ' is not in the database.')
        return
    end
    local n = function(k) return ENC.num(rec, k) end
    local name = ENC.str(rec, 'name')
    local anim = core.getSpellIconAnimation and core.getSpellIconAnimation(n('new_icon') > 0 and n('new_icon') or n('icon')) or nil
    drawIcon(anim, core.px(32))
    ImGui.SameLine()
    ImGui.BeginGroup()
    gold(name)
    local classes = spellClassesText(rec.classes)
    muted('ID ' .. id .. '   ' .. (classes ~= '' and classes or 'Not player castable'))
    ImGui.EndGroup()
    ImGui.Separator()

    -- live client values (duration at your level, description)
    local duration, desc = nil, nil
    pcall(function()
        local sp = mq.TLO.Spell(id)
        if sp and sp() then
            local d = sp.Duration and sp.Duration.TotalSeconds and sp.Duration.TotalSeconds() or nil
            if d and d > 0 then duration = d end
            if sp.Description then desc = sp.Description() end
        end
    end)

    if ImGui.BeginTable('##spellstats', 4, ImGuiTableFlags.SizingFixedFit) then
        local rows = { {}, {} }
        local function add(c, l, v) if v ~= nil and v ~= 0 and v ~= '' then table.insert(rows[c], { l, v }) end end
        add(1, 'Mana', n('mana'))
        add(1, 'Endurance', n('EndurCost'))
        if n('EndurUpkeep') > 0 then add(1, 'End Upkeep', n('EndurUpkeep')) end
        add(1, 'Cast Time', string.format('%.2fs', n('cast_time') / 1000))
        if n('recast_time') > 0 then add(1, 'Recast', D.secondsText(n('recast_time') / 1000)) end
        if n('recovery_time') > 0 then add(1, 'Recovery', string.format('%.2fs', n('recovery_time') / 1000)) end
        if duration then
            add(1, 'Duration', D.secondsText(duration) .. ' (at your level)')
        elseif n('buffduration') > 0 then
            add(1, 'Duration', string.format('%d ticks max (formula %d)', n('buffduration'), n('buffdurationformula')))
        end
        add(2, 'Target', D.targetTypeName(n('targettype')))
        if n('range') > 0 then add(2, 'Range', n('range')) end
        if n('aoerange') > 0 then add(2, 'AE Range', n('aoerange')) end
        if n('maxtargets') > 0 then add(2, 'Max Targets', n('maxtargets')) end
        add(2, 'Resist', D.resistTypeName(n('resisttype')) .. (n('basediff') ~= 0 and (' (' .. fmtSigned(n('basediff')) .. ')') or ''))
        add(2, 'Skill', D.skillName(n('skill')))
        if n('HateAdded') ~= 0 then add(2, 'Hate', fmtSigned(n('HateAdded'))) end
        if n('numhits') > 0 then add(2, 'Hits', n('numhits')) end
        if n('IsDiscipline') > 0 then add(2, 'Discipline', 'yes') end
        local maxRows = math.max(#rows[1], #rows[2])
        for i = 1, maxRows do
            ImGui.TableNextRow()
            for c = 1, 2 do
                local r = rows[c][i]
                ImGui.TableSetColumnIndex((c - 1) * 2)
                if r then muted(r[1] .. ':') end
                ImGui.TableSetColumnIndex((c - 1) * 2 + 1)
                if r then txt(r[2]) end
            end
        end
        ImGui.EndTable()
    end
    local tele = ENC.str(rec, 'teleport_zone')
    if tele ~= '' then labelled('Teleports to', DB.zoneName(tele)) end
    local flags = {}
    if n('uninterruptable') > 0 then flags[#flags + 1] = 'Uninterruptable' end
    if n('nodispell') > 0 then flags[#flags + 1] = 'Cannot be dispelled' end
    if n('can_mgb') > 0 then flags[#flags + 1] = 'MGB-able' end
    if n('reflectable') > 0 then flags[#flags + 1] = 'Reflectable' end
    if n('cast_not_standing') > 0 then flags[#flags + 1] = 'Castable while not standing' end
    if n('goodEffect') > 0 then flags[#flags + 1] = 'Beneficial' end
    if #flags > 0 then muted(table.concat(flags, ', ')) end

    local comps = {}
    for i = 1, 4 do
        local cid = n('components' .. i)
        if cid > 0 then comps[#comps + 1] = { cid, n('component_counts' .. i) } end
    end
    if #comps > 0 then
        muted('Components:')
        for i, c in ipairs(comps) do
            ImGui.SameLine()
            if link(string.format('%s x%d', DB.itemName(c[1]), math.max(c[2], 1)), 'comp' .. i) then showEntry('items', c[1]) end
        end
    end

    header('Effects')
    local effects = ENC.list(rec, 'effects')
    if #effects == 0 then muted('None') end
    for _, e in ipairs(effects) do
        local spa = tonumber(e[2]) or 0
        local text = D.spaText(spa, e[3], e[4], e[5])
        local ref = text:match('%[spell (%d+)%]')
        local iref = text:match('%[item (%d+)%]')
        txt(string.format('%d: ', tonumber(e[1]) or 0))
        ImGui.SameLine()
        if ref then
            local before = text:gsub('%[spell %d+%]', '')
            txt(before)
            ImGui.SameLine()
            if link(DB.spellName(tonumber(ref)), 'spa' .. e[1]) then showEntry('spells', tonumber(ref)) end
        elseif iref then
            local before = text:gsub('%[item %d+%]', '')
            txt(before)
            ImGui.SameLine()
            if link(DB.itemName(tonumber(iref)), 'spai' .. e[1]) then showEntry('items', tonumber(iref)) end
        else
            txt(text)
        end
    end

    if desc and desc ~= '' then
        header('Description')
        ImGui.TextWrapped(desc)
    end

    local items = ENC.list(rec, 'items')
    if #items > 0 then
        header(string.format('Items (%d%s)', #items, items.more and (' of ' .. (#items + items.more)) or ''))
        for i, it in ipairs(items) do
            local iid = tonumber(it[2]) or 0
            local kind = ({ click = 'Click', proc = 'Proc', worn = 'Worn', focus = 'Focus', scroll = 'Scroll', bard = 'Bard' })[it[1]] or it[1]
            if link(DB.itemName(iid), 'si' .. i) then showEntry('items', iid) end
            ImGui.SameLine()
            muted('(' .. kind .. ')')
        end
    end
    local npcs = ENC.list(rec, 'npcs')
    if #npcs > 0 then
        header(string.format('Cast By (%d%s)', #npcs, npcs.more and (' of ' .. (#npcs + npcs.more)) or ''))
        for i, np in ipairs(npcs) do
            local nid = tonumber(np[1]) or 0
            local info = DB.npcInfo(nid)
            local label = info and string.format('%s  (%d, %s)', info.name, info.lvl, DB.zoneName(info.zone)) or ('NPC ' .. nid)
            if link(label, 'sn' .. i) then showEntry('npcs', nid) end
        end
    end
end

local function drawNpcCard() drawNpcCardFor(S.npcs) end
local function drawSpellCard() drawSpellCardFor(S.spells) end

local function drawPopoutBody(pop)
    if pop.kind == 'items' then
        drawItemCardFor(pop, true)
        return
    end
    if ImGui.SmallButton('Open in Database##pop' .. tostring(pop.key)) then
        showEntry(pop.kind, pop.sel)
        ctrl.show_gamedb = true
    end
    if pop.kind == 'npcs' then drawNpcCardFor(pop) else drawSpellCardFor(pop) end
end

local function popoutTitle(pop)
    if pop.pending then return KIND_LABELS[pop.kind]:sub(1, -2) .. ' (loading...)' end
    if pop.kind == 'items' then return DB.itemName(pop.sel + D.TIER_OFFSET[pop.tier or 'B']) end
    if pop.kind == 'npcs' then return DB.npcName(pop.sel) end
    return DB.spellName(pop.sel)
end

-- Floating cards (items, NPCs, spells). Drawn even while the main window is closed.
local function drawPopouts()
    if #S.popouts == 0 then return end
    local colors = core.colors or {}
    C.GOOD = C.GOOD or colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    C.WARN = C.WARN or colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    C.ERR = C.ERR or colors.ERR or { 0.95, 0.40, 0.40, 1.0 }
    C.MUTED = C.MUTED or colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    C.ARC = C.ARC or colors.ARC or { 0.30, 0.80, 1.00, 1.0 }
    C.GOLD = C.GOLD or colors.GOLD or { 1.0, 0.70, 0.54, 1.0 }
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.pushTheme()
    S.linkOpensWindow = true
    local i = 1
    while i <= #S.popouts do
        local pop = S.popouts[i]
        local remove = false
        if pop.pending and DB.isLoaded(pop.kind) then
            local resolved = openPopout(pop.kind, pop.pending)
            pop.pending = nil
            if resolved ~= pop then remove = true end
        end
        if not remove then
            local title = popoutTitle(pop)
            ImGui.SetNextWindowSize(core.px(430), core.px(480), ImGuiCond.FirstUseEver)
            if pop.focus then
                pcall(ImGui.SetNextWindowFocus)
                pop.focus = false
            end
            local open, draw = ImGui.Begin(title .. '###TriuneGameDBPop' .. pop.key, true, windowFlags)
            if not open then
                remove = true
            elseif draw then
                if pop.pending then
                    muted('Loading the ' .. pop.kind .. ' index...')
                else
                    local ok, err = pcall(drawPopoutBody, pop)
                    if not ok then warn('Card error: ' .. tostring(err)) end
                end
            end
            ImGui.End()
        end
        if remove then table.remove(S.popouts, i) else i = i + 1 end
    end
    S.linkOpensWindow = false
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Search panes
-- ----------------------------------------------------------------------------
local function drawResults(kind, height)
    local st = S[kind]
    local ix = DB.kinds[kind]
    if not ix or not ix.loaded then
        local lk, prog = DB.progress()
        if lk == kind and prog then
            ImGui.ProgressBar(prog, -1, core.px(18), string.format('Loading %s... %d%%', KIND_LABELS[kind], math.floor(prog * 100)))
        elseif ix and ix.failed then
            warn('No ' .. kind .. '.idx under resources/gamedb.')
            muted('Run tools/build_gamedb.py (see README) or install the full release.')
        else
            muted('Waiting to load ' .. KIND_LABELS[kind] .. '...')
        end
        return
    end
    if st.dirty then runSearch(kind) end
    local results = st.results
    muted(string.format('%d result%s%s', #results, #results == 1 and '' or 's', #results >= DB.MAX_RESULTS and ' (capped)' or ''))
    if ImGui.BeginChild('##results' .. kind, ImVec2(0, height), true) then
        for i, n in ipairs(results) do
            local id = ix.ids[n]
            local label = ix.names[n]
            if kind == 'npcs' then
                local z = ix.zone[n]
                label = string.format('%s  (%d, %s)', label, ix.lvl[n], z ~= '' and z or '-')
            elseif kind == 'spells' then
                local cls = ix.extra[n] or ''
                local first = cls:match('^(%d+):(%d+)')
                if first then
                    local cnt = select(2, cls:gsub(':', ''))
                    label = string.format('%s  (%s)', label, cnt > 3 and (cnt .. ' classes') or spellClassesText(cls))
                end
            elseif kind == 'items' then
                local tiers = ix.extra[n] or ''
                if tiers:find('L', 1, true) then label = label .. '  [B/E/L]' elseif tiers:find('E', 1, true) then label = label .. '  [B/E]' end
            end
            local selected = (st.sel == id)
            -- MQ's binding returns (selected, pressed): the first value is the
            -- selection state, true every frame for the selected row.
            local _, pressed = ImGui.Selectable(label .. '##r' .. i, selected)
            if pressed then showEntry(kind, id) end
        end
        if #results == 0 and st.query ~= '' then muted('No matches.') end
    end
    ImGui.EndChild()
end

local function drawSearchPane(kind)
    local st = S[kind]
    ImGui.SetNextItemWidth(-1)
    local q, changed = ImGui.InputTextWithHint('##q' .. kind, 'Search ' .. KIND_LABELS[kind] .. ' by name or ID...', st.query)
    if changed then
        st.query = q
        st.dirty = true
    end
    if kind == 'items' then
        if ImGui.SmallButton('Cursor Item') then plugin.lookupCursor() end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Look up the item on your cursor.') end
    elseif kind == 'npcs' then
        ImGui.SetNextItemWidth(core.px(110))
        local z, zc = ImGui.InputTextWithHint('##zone', 'zone', st.zone)
        if zc then st.zone = z; st.dirty = true end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(50))
        local a, ac = ImGui.InputInt('##minl', st.minLvl, 0, 0)
        if ac then st.minLvl = math.max(0, a); st.dirty = true end
        ImGui.SameLine(); muted('-'); ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(50))
        local b, bc = ImGui.InputInt('##maxl', st.maxLvl, 0, 0)
        if bc then st.maxLvl = math.max(0, b); st.dirty = true end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Level range (0 = any)') end
    elseif kind == 'spells' then
        ImGui.SetNextItemWidth(core.px(90))
        local label = st.class > 0 and D.CLASSES[st.class] or 'Any class'
        if ImGui.BeginCombo('##cls', label) then
            local _, anyPressed = ImGui.Selectable('Any class', st.class == 0)
            if anyPressed then st.class = 0; st.dirty = true end
            for i, c in ipairs(D.CLASSES) do
                local _, pressed = ImGui.Selectable(c .. ' - ' .. D.CLASS_NAMES[i], st.class == i)
                if pressed then st.class = i; st.dirty = true end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(50))
        local a, ac = ImGui.InputInt('##sminl', st.minLvl, 0, 0)
        if ac then st.minLvl = math.max(0, a); st.dirty = true end
        ImGui.SameLine(); muted('-'); ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(50))
        local b, bc = ImGui.InputInt('##smaxl', st.maxLvl, 0, 0)
        if bc then st.maxLvl = math.max(0, b); st.dirty = true end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Level range (0 = any)') end
        if st.class > 0 and st.query == '' and #st.results == 0 and not st.dirty then st.dirty = true end
    end
    drawResults(kind, -1)
end

-- ----------------------------------------------------------------------------
-- Loot Advisor: while the loot window is open, one row per corpse item with
-- the drop chance on this NPC, value, tiers and quest / recipe / vendor facts.
-- ----------------------------------------------------------------------------
local function scanLoot()
    local L = S.loot
    local open = false
    pcall(function()
        local w = mq.TLO.Window('LootWnd')
        open = w and w.Open and w.Open() == true
    end)
    L.open = open
    if not open then
        L.rows = {}
        L.corpseId = 0
        return
    end
    if not DB.isLoaded('items') or not DB.isLoaded('npcs') then return end
    local corpseId, count = 0, 0
    pcall(function()
        corpseId = mq.TLO.Corpse.ID() or 0
        count = mq.TLO.Corpse.Items() or 0
    end)
    if corpseId ~= L.corpseId then
        L.corpseId = corpseId
        L.rows = {}
        L.npcId = nil
        L.npcName = ''
        if corpseId > 0 then
            local name = nil
            pcall(function() name = mq.TLO.Spawn(corpseId).CleanName() end)
            if name then
                name = name:gsub("'s corpse$", ''):gsub(' corpse$', '')
                L.npcName = name
                local level, zone = 0, ''
                pcall(function()
                    level = mq.TLO.Spawn(corpseId).Level() or 0
                    zone = mq.TLO.Zone.ShortName() or ''
                end)
                L.npcId = DB.npcIdFor(name, zone, level)
            end
        end
    end
    -- drop chances on this NPC
    local chance = {}
    if L.npcId then
        local rec = DB.npcRecord(L.npcId)
        for _, d in ipairs(rec and ENC.list(rec, 'drops') or {}) do chance[tonumber(d[1]) or 0] = d[2] end
    end
    local rows = {}
    for i = 1, count do
        local id, name, value = 0, '', 0
        pcall(function()
            local it = mq.TLO.Corpse.Item(i)
            if it and it() then
                id = it.ID() or 0
                name = it.Name() or ''
                value = it.Value() or 0
            end
        end)
        if id > 0 then
            local _, base = D.tierOf(id)
            local row = { id = id, name = name ~= '' and name or DB.itemName(id), value = value, chance = chance[id] or chance[base], lines = plugin.itemSummary(id) or {} }
            local rec = DB.itemRecord(base, 'B')
            row.quest = rec and ENC.num(rec, 'questitemflag') > 0
            row.tags = {}
            for _, l in ipairs(row.lines) do
                if l:find('^Quest turn%-in') then row.tags[#row.tags + 1] = 'TURN-IN' end
                if l:find('^Tradeskill') then row.tags[#row.tags + 1] = 'RECIPE' end
            end
            rows[#rows + 1] = row
        end
    end
    L.rows = rows
end

local function drawLootAdvisor()
    local L = S.loot
    if not S.lootAdvisor or not L.open or #L.rows == 0 then return end
    local colors = core.colors or {}
    C.GOOD = C.GOOD or colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    C.WARN = C.WARN or colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    C.MUTED = C.MUTED or colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    C.ARC = C.ARC or colors.ARC or { 0.30, 0.80, 1.00, 1.0 }
    C.GOLD = C.GOLD or colors.GOLD or { 1.0, 0.70, 0.54, 1.0 }
    core.pushTheme()
    ImGui.SetNextWindowSize(core.px(520), core.px(220), ImGuiCond.FirstUseEver)
    core.preBeginWindow('gamedb_loot')
    local open, draw = ImGui.Begin('Loot Advisor###TriuneGameDBLoot', true, 0)
    if not open then
        S.lootAdvisor = false
        core.saveLoadout(true)
    elseif draw then
        core.postBeginWindow('gamedb_loot')
        if L.npcName ~= '' then
            muted('Looting ' .. L.npcName .. (L.npcId and '' or '  (not in the database)'))
        end
        if ImGui.BeginTable('##loot', 4, ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingStretchProp) then
            ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch, 4)
            ImGui.TableSetupColumn('Drop', ImGuiTableColumnFlags.WidthFixed, core.px(52))
            ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.WidthFixed, core.px(90))
            ImGui.TableSetupColumn('Notes', ImGuiTableColumnFlags.WidthStretch, 4)
            ImGui.TableHeadersRow()
            for i, row in ipairs(L.rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                if link(row.name, 'loot' .. i) then openPopout('items', row.id) end
                if ImGui.IsItemHovered() and #row.lines > 0 then ImGui.SetTooltip(table.concat(row.lines, '\n')) end
                ImGui.TableSetColumnIndex(1)
                local ch = tonumber(row.chance)
                if ch then
                    if ch <= 5 then warn(string.format('%.1f%%', ch)) else txt(string.format('%.1f%%', ch)) end
                else
                    muted('-')
                end
                ImGui.TableSetColumnIndex(2); txt(D.moneyText(row.value))
                ImGui.TableSetColumnIndex(3)
                local notes = {}
                if ch and ch <= 5 then notes[#notes + 1] = 'RARE' end
                if row.quest then notes[#notes + 1] = 'QUEST' end
                for _, t in ipairs(row.tags) do notes[#notes + 1] = t end
                for _, l in ipairs(row.lines) do
                    if l:find('^Tiers') then notes[#notes + 1] = l:gsub('^Tiers: ', ''):gsub('Base / ', ''); break end
                end
                if #notes > 0 then gold(table.concat(notes, '  ')) else muted('-') end
            end
            ImGui.EndTable()
        end
    end
    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
local function drawWindow()
    if not ctrl.show_gamedb then return end
    local colors = core.colors or {}
    C.GOOD = colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    C.WARN = colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    C.ERR = colors.ERR or { 0.95, 0.40, 0.40, 1.0 }
    C.MUTED = colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    C.ARC = colors.ARC or { 0.30, 0.80, 1.00, 1.0 }
    C.GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1.0 }

    queueAll()

    core.pushTheme()
    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(core.px(940), core.px(620), ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('gamedb')
    local open, draw = ImGui.Begin('Triune Database###TriuneGameDB', ctrl.show_gamedb, windowFlags)
    if not open then
        ctrl.show_gamedb = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not draw then
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('gamedb')

    -- toolbar: history + status
    local canBack = S.histPos > 1
    local canFwd = S.histPos < #S.history
    if not canBack then ImGui.BeginDisabled() end
    if ImGui.SmallButton('< Back') then
        S.histPos = S.histPos - 1
        local h = S.history[S.histPos]
        showEntry(h.kind, h.id, true)
    end
    if not canBack then ImGui.EndDisabled() end
    ImGui.SameLine()
    if not canFwd then ImGui.BeginDisabled() end
    if ImGui.SmallButton('Forward >') then
        S.histPos = S.histPos + 1
        local h = S.history[S.histPos]
        showEntry(h.kind, h.id, true)
    end
    if not canFwd then ImGui.EndDisabled() end
    ImGui.SameLine()
    local m = DB.readManifest()
    if m.present then
        muted(string.format('Database built %s  -  %s items, %s NPCs, %s spells', m.built or '?', m.item_index or '?', m.npcs or '?', m.spells or '?'))
    else
        warn('resources/gamedb not found - install the full release or run tools/build_gamedb.py')
    end

    if ImGui.BeginTabBar('##gamedbtabs') then
        for _, kind in ipairs(KINDS) do
            local flags = 0
            if S.pendingTab == kind and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected then
                flags = ImGuiTabItemFlags.SetSelected
            end
            local okTab, tabOpen = false, false
            if flags ~= 0 then okTab, tabOpen = pcall(ImGui.BeginTabItem, KIND_LABELS[kind] .. '##tab' .. kind, nil, flags) end
            if not okTab then tabOpen = ImGui.BeginTabItem(KIND_LABELS[kind] .. '##tab' .. kind) end
            if tabOpen then
                if S.pendingTab ~= kind then S.tab = kind end
                local leftW = core.px(310)
                if ImGui.BeginChild('##left' .. kind, ImVec2(leftW, 0), false) then
                    drawSearchPane(kind)
                end
                ImGui.EndChild()
                ImGui.SameLine()
                if ImGui.BeginChild('##card' .. kind, ImVec2(0, 0), true) then
                    if kind == 'items' then drawItemCard()
                    elseif kind == 'npcs' then drawNpcCard()
                    else drawSpellCard() end
                end
                ImGui.EndChild()
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar()
    end
    S.pendingTab = nil

    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_gamedb == nil then ctrl.show_gamedb = false end
    -- Preload in the background so the window is ready when first opened.
    queueAll()
    -- Let the combat loop skip casts the database knows are wasted.
    local tracker = core.castTracker
    if type(tracker) == 'table' then tracker.knownImmunity = plugin.immunityReason end
end

function plugin.onDestroy()
    S.popouts = {}
    spawnNpcCache = {}
    local tracker = core and core.castTracker
    if type(tracker) == 'table' and tracker.knownImmunity == plugin.immunityReason then tracker.knownImmunity = nil end
    DB.setDir(DB.dir)
end

function plugin.onTick()
    if not core then return end
    refresh()
    stepLoading()
    if S.lootAdvisor then
        local now = os.clock()
        if now - (S.loot.lastScan or 0) >= 0.5 then
            S.loot.lastScan = now
            pcall(scanLoot)
        end
    end
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    stepLoading()
    drawWindow()
    drawPopouts()
    drawLootAdvisor()
end

function plugin.onSaveSettings()
    return { tab = S.tab, lootAdvisor = S.lootAdvisor == true }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if KIND_LABELS[s.tab] then S.tab = s.tab end
    if s.lootAdvisor ~= nil then S.lootAdvisor = (s.lootAdvisor == true) end
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Game Database')
    local isWinOpen = (ctrl.show_gamedb == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##gdbToggleWin', core.px(250), core.px(24)) then
        ctrl.show_gamedb = not isWinOpen
        core.saveLoadout(true)
    end
    local la = ImGui.Checkbox('Loot Advisor while looting (drop chance, value, quest / recipe notes)##gdbLoot', S.lootAdvisor == true)
    if la ~= (S.lootAdvisor == true) then
        S.lootAdvisor = la
        core.saveLoadout(true)
    end
    local m = DB.readManifest()
    if m.present then
        ImGui.TextDisabled(string.format('Data built %s: %s items, %s NPCs, %s spells (%s)', m.built or '?', m.item_index or '?', m.npcs or '?', m.spells or '?', m.source or ''))
    else
        ImGui.TextDisabled('No database files found under resources/gamedb.')
    end
    for _, k in ipairs(KINDS) do
        local ix = DB.kinds[k]
        ImGui.TextDisabled(string.format('  %s: %s', KIND_LABELS[k], ix and ix.loaded and (ix.count .. ' loaded') or (ix and ix.failed and 'missing' or 'not loaded')))
    end
end

-- /ac db [text] | /ac item <text> | /ac npc <text> | /ac spell <text> | /ac dbcursor
function plugin.onCommand(cmd, args)
    local text = ''
    if type(args) == 'table' then
        local rest = {}
        for i = 2, #args do rest[#rest + 1] = tostring(args[i]) end
        text = table.concat(rest, ' ')
    elseif args ~= nil then
        text = tostring(args)
    end
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if cmd == 'db' or cmd == 'gamedb' or cmd == 'database' then
        refresh()
        if text ~= '' then
            plugin.search('items', text)
        else
            ctrl.show_gamedb = not ctrl.show_gamedb
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Database %s.', ctrl.show_gamedb and 'OPENED' or 'CLOSED'))
        end
        return true
    end
    if cmd == 'item' then plugin.search('items', text); return true end
    if cmd == 'npc' then plugin.search('npcs', text); return true end
    if cmd == 'spell' then plugin.search('spells', text); return true end
    if cmd == 'dbcursor' then plugin.lookupCursor(); return true end
    if cmd == 'dbtarget' then plugin.lookupTarget(); return true end
    if cmd == 'lootadvisor' then
        S.lootAdvisor = not S.lootAdvisor
        core.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Loot Advisor %s.', S.lootAdvisor and 'ON' or 'OFF'))
        return true
    end
    return false
end

plugin.help = {
    '  \ag/ac db\ax - Toggle the Game Database window (items / NPCs / spells)',
    '  \ag/ac item <name|id>\ax, \ag/ac npc <name|id>\ax, \ag/ac spell <name|id>\ax - Search the database',
    '  \ag/ac dbcursor\ax - Look up the item on your cursor',
    '  \ag/ac dbtarget\ax - Open a card for your current target (stats, abilities, loot)',
    '  \ag/ac lootadvisor\ax - Toggle the Loot Advisor shown while looting a corpse',
}

-- Exposed for tests and other plugins
plugin.ENC = ENC
plugin.D = D
plugin.DB = DB
plugin.state = S
plugin.showEntry = showEntry
plugin.runSearch = runSearch
plugin.scanLoot = scanLoot

return plugin
