---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/auto_aa.lua — Triune Auto AA Plugin
-- ============================================================================
-- Automatic Alternate Advancement spending: scans the character's AA window,
-- ranks abilities by the user's priority list, purchases them natively through
-- the AA window (or delegates to MQ2AAspend with a native fallback), handles
-- the Fireworks / Special-tab cap spender, auto-summons fireworks, and owns the
-- "Auto AA" popout window (ctrl.show_auto_aa, header button) plus the /ac autoaa
-- family of commands.
--
-- Combat coupling is expressed through two plugin hooks rather than shared
-- runtime state:
--   * wantsCombatHold() -> true while an AA-window purchase workflow is running,
--     so the combat loop stops moving / pulling until the window is closed.
--   * onBetweenPulls()  -> lets the puller buy an AA between pulls; returns true
--     when a purchase started so the puller yields this tick.
--
-- The scanned rank / description cache is left on core.runtime.cachedAAData
-- because the core's AA loadout tab tooltips read it too.
-- ============================================================================

local plugin = {
    id                 = 'auto_aa',
    name               = 'Auto AA Spender',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Automatically spends AA points by priority (native AA window or MQ2AAspend), Fireworks cap spender, auto-summon, and the Auto AA window.',
    defaultEnabled     = true,
    tickInterval       = 0.15,
    runOutOfCombatOnly = false, -- has its own combat gates; the purchase workflow must be able to finish/abort mid-fight
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Auto AA', tooltip = 'Toggles the Auto AA spender & AA progression window (auto_aa plugin).', flag = 'show_auto_aa', desc = 'AA point spender, priorities & AA progression', headerButton = true, order = 45 },
}

local core = nil
local rt = nil      -- core.runtime (shared helpers + cachedAAData)
local mq = nil
local ImGui = nil
local ctrl = nil    -- refreshed from core.ctrl on every entry point
local DATA = nil
local accent = nil
local GOLD, GOOD, WARN, ERR = nil, nil, nil, nil
local registeredEvents = {}

-- All state and helpers hang off this table (keeps the chunk under the 200-local limit).
local AA = {}

local function resetState()
    AA.lastAutoSpendAAAt = 0
    AA.lastAutoSummonAt = 0
    AA.pendingFireworksSummon = nil
    AA.lastAASpendIniFingerprint = nil
    AA.scannedAAs = nil
    AA.scannedAAMap = nil
    AA.lastAAScanAt = 0
    AA.filteredSortedAAs = nil
    AA.aaFilterDirty = true
    AA.lastObservedAAPointsSpent = nil
    AA.lastObservedAAPoints = nil
    AA.pendingPostTrainScanAt = nil
    AA.lastAATrainAttempt = {}
    AA.lastObservedAutoSpendPts = nil
    AA.lastCharLevel = nil
    AA.specialTabAAs = nil
    AA.specialTabReadDone = false
    AA.pendingReadSpecialTab = false
    AA.pendingAATrain = nil
    AA.lastAASpendDelegatedTarget = nil
    AA.lastAASpendDelegatedAt = nil
    AA.lastAASpendDelegatedPoints = nil
    AA.lastAACapDelegatedTarget = nil
    AA.lastAACapDelegatedAt = nil
    AA.lastAACapDelegatedPoints = nil
    AA.lastAASpendAutoloadAttempt = nil
    AA.scanRequestAt = nil          -- os.clock() when the next deferred scan is due (nil = none)
    AA.scanning = false             -- set while a scan runs (the window shows "scanning...")
    AA.scanCtx = nil                -- per-scan TLO lookup caches (see scanPlayerAAs)
    AA.trainBackoff = {}            -- AA name -> os.clock() until which it is not retried
    AA.trainFailLogged = {}         -- AA name -> true once the failure was reported
    AA.aaSpendLoadedCache = nil
    AA.aaSpendLoadedAt = 0
end
resetState()

-- One bank / reserve threshold default for every path (slider, cap spender,
-- MQ2AAspend delegation, command output). nil is the only "unset" value:
-- a user-picked 100 is a real threshold, not a default to second-guess.
AA.DEFAULT_THRESHOLD = 25
AA.MIN_THRESHOLD = 5
AA.TRAIN_FAIL_BACKOFF = 300.0     -- seconds before an AA whose purchase did not land is retried
AA.SCAN_MIN_INTERVAL = 10.0       -- unforced scans are skipped inside this window

function AA.threshold()
    return math.max(AA.MIN_THRESHOLD, tonumber(ctrl.auto_spend_aa_threshold) or AA.DEFAULT_THRESHOLD)
end

-- Ask the tick to (re)scan; several triggers of one purchase (Train click,
-- "You have purchased" event, AAPointsSpent change, window refresh) fold
-- into the earliest pending request, so a purchase costs one scan.
function AA.requestScan(delay)
    local due = os.clock() + (tonumber(delay) or 0)
    if AA.scanRequestAt == nil or due < AA.scanRequestAt then AA.scanRequestAt = due end
end

-- ----------------------------------------------------------------------------
-- MQ2AAspend detection
-- ----------------------------------------------------------------------------
-- Probes each plugin name in turn (a TLO object is truthy even for an
-- unloaded plugin, so `a or b` never reached the second name). The answer
-- is cached for two seconds: the window asks every frame.
AA.AASPEND_NAMES = { 'mq2aaspend', 'MQ2AASpend', 'aaspend' }
function AA.aaSpendLoaded()
    local now = os.clock()
    if AA.aaSpendLoadedCache ~= nil and (now - (AA.aaSpendLoadedAt or 0)) < 2.0 then
        return AA.aaSpendLoadedCache
    end
    local ok, loaded = pcall(function()
        for _, nm in ipairs(AA.AASPEND_NAMES) do
            local p = mq.TLO.Plugin(nm)
            if p and p() and p.IsLoaded and p.IsLoaded() then return true end
        end
        return false
    end)
    AA.aaSpendLoadedCache = ok and (loaded == true)
    AA.aaSpendLoadedAt = now
    return AA.aaSpendLoadedCache
end

function AA.findChildRecursive(parent, targetName)
    if not parent or not targetName or targetName == '' then return nil end
    local tLower = targetName:lower()

    -- Try direct Child lookup first
    local direct = nil
    pcall(function() direct = parent.Child(targetName) end)
    if direct then return direct end

    -- Check immediate children by iterating FirstChild -> Next
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

        -- Recurse into child if it has children
        local hasChildren = false
        pcall(function()
            if curr.FirstChild then
                hasChildren = true
            elseif curr.Children then
                local c = curr.Children()
                if c == true or c == 'TRUE' or tostring(c):lower() == 'true' then
                    hasChildren = true
                end
            end
        end)
        if hasChildren then
            local found = AA.findChildRecursive(curr, targetName)
            if found then return found end
        end

        local nextSibling = nil
        pcall(function() nextSibling = curr.Next end)
        curr = nextSibling
    end
    return nil
end

function AA.getAAWindow()
    local win = nil
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w.Name and w.Name() then win = w return end
        w = mq.TLO.Window('AAWnd')
        if w and w.Name and w.Name() then win = w return end
    end)
    return win
end

function AA.getAAWindowName()
    local name = 'AAWindow'
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w.Name and w.Name() then name = w.Name() return end
        w = mq.TLO.Window('AAWnd')
        if w and w.Name and w.Name() then name = w.Name() return end
    end)
    return name
end

function AA.isAAWindowOpen()
    local isOpen = false
    pcall(function()
        local w = mq.TLO.Window('AAWindow')
        if w and w.Open and w.Open() then isOpen = true return end
        w = mq.TLO.Window('AAWnd')
        if w and w.Open and w.Open() then isOpen = true return end
        local win = AA.getAAWindow()
        if win and win.Open and win.Open() then isOpen = true return end
    end)
    return isOpen
end

function AA.openAAWindow(attempt)
    if AA.isAAWindowOpen() then return true end
    attempt = attempt or 1
    local win = AA.getAAWindow()
    local winName = AA.getAAWindowName()

    if attempt == 1 then
        pcall(function()
            if win and win.DoOpen then win.DoOpen() end
        end)
        mq.cmdf('/windowstate %s open', winName)
        if winName ~= 'AAWindow' then
            mq.cmd('/windowstate AAWindow open')
        end
        mq.cmd('/windowstate AAWnd open')
    elseif attempt == 2 then
        mq.cmd('/nomodkey /keypress TOGGLE_ALTADVWIN')
    elseif attempt == 3 then
        mq.cmd('/nomodkey /keypress v alt')
    elseif attempt == 4 then
        mq.cmd('/nomodkey /keypress a alt')
    else
        local invWin = nil
        local invOpen = false
        pcall(function()
            invWin = mq.TLO.Window('InventoryWindow')
            if invWin and invWin() and invWin.Open and invWin.Open() then
                invOpen = true
            else
                invWin = mq.TLO.Window('InventoryWnd')
                if invWin and invWin() and invWin.Open and invWin.Open() then
                    invOpen = true
                end
            end
        end)
        if invOpen and invWin then
            local invName = 'InventoryWindow'
            pcall(function() if invWin.Name then invName = invWin.Name() end end)
            mq.cmdf('/nomodkey /notify %s IW_AltAdvBtn leftmouseup', invName)
        end
    end
    return AA.isAAWindowOpen()
end

function AA.closeAAWindow()
    if not AA.isAAWindowOpen() then return true end
    local win = AA.getAAWindow()
    local winName = AA.getAAWindowName()
    pcall(function()
        if win and win.DoClose then win.DoClose() end
    end)
    mq.cmdf('/nomodkey /notify %s AAW_DoneButton leftmouseup', winName)
    mq.cmdf('/nomodkey /notify %s DoneButton leftmouseup', winName)
    mq.cmdf('/windowstate %s close', winName)
    if winName ~= 'AAWindow' then
        mq.cmd('/windowstate AAWindow close')
    end
    mq.cmd('/windowstate AAWnd close')
    return not AA.isAAWindowOpen()
end

function AA.isSpecialTabAA(name)
    if not name or name == '' then return false end
    local lower = tostring(name):lower()
    if lower:find('firework') then return true end
    if rt.cachedAAData and rt.cachedAAData[name] then
        local cat = rt.cachedAAData[name].category
        if cat and cat:lower():find('special') then return true end
    end
    -- The entry map of the running scan, else of the last completed one
    -- (a linear walk of scannedAAs here made every scan O(n^2)).
    local map = (AA.scanCtx and AA.scanCtx.foundMap) or AA.scannedAAMap
    local itm = map and map[name]
    if itm then
        if itm.category and itm.category:lower():find('special') then return true end
        if itm.type == 4 then return true end
    end
    return false
end

function AA.findAAInWindowLists(targetName, preferredTab)
    local win = AA.getAAWindow()
    if not win then return nil, nil, nil, nil end

    local listCandidates = {
        { name = 'AAW_SpecialList', tab = 4 },
        { name = 'AAW_Special_List', tab = 4 },
        { name = 'AAW_SpecList', tab = 4 },
        { name = 'AA_SpecialList', tab = 4 },
        { name = 'AA_SpecList', tab = 4 },
        { name = 'SpecialList', tab = 4 },
        { name = 'Special_List', tab = 4 },
        { name = 'List4', tab = 4 },
        { name = 'AAW_ClassList', tab = 3 },
        { name = 'AA_ClassList', tab = 3 },
        { name = 'ClassList', tab = 3 },
        { name = 'List3', tab = 3 },
        { name = 'AAW_ArchList', tab = 2 },
        { name = 'AA_ArchList', tab = 2 },
        { name = 'AA_ArchetypeList', tab = 2 },
        { name = 'ArchList', tab = 2 },
        { name = 'List2', tab = 2 },
        { name = 'AAW_GeneralList', tab = 1 },
        { name = 'AA_GeneralList', tab = 1 },
        { name = 'GeneralList', tab = 1 },
        { name = 'List1', tab = 1 },
        { name = 'AAW_List', tab = 1 },
        { name = 'AA_List', tab = 1 },
        { name = 'AAW_SearchResultList', tab = 1 },
        { name = 'AA_SearchResultList', tab = 1 }
    }

    local cleanTarget = tostring(targetName or ''):lower():gsub('[^%a%d]', '')
    local isSpecial = cleanTarget:find('firework') ~= nil or (AA.isSpecialTabAA and AA.isSpecialTabAA(targetName))

    -- If a preferred/active tab is specified, check that tab's lists first; otherwise prioritize Special tab if special
    if preferredTab and preferredTab >= 1 and preferredTab <= 4 then
        table.sort(listCandidates, function(a, b)
            if a.tab == preferredTab and b.tab ~= preferredTab then return true end
            if b.tab == preferredTab and a.tab ~= preferredTab then return false end
            return a.tab > b.tab
        end)
    elseif isSpecial then
        table.sort(listCandidates, function(a, b)
            if a.tab == 4 and b.tab ~= 4 then return true end
            if b.tab == 4 and a.tab ~= 4 then return false end
            return a.tab > b.tab
        end)
    end

    local tabParents = { 'AAW_Subwindows', 'Subwindows', 'AA_Subwindows', 'AA_SubWnd', 'AAW_SpecialTabPage', 'AA_SpecialTabPage' }

    for _, cand in ipairs(listCandidates) do
        local child = nil
        pcall(function() child = win.Child(cand.name) end)
        if not child then
            for _, tp in ipairs(tabParents) do
                pcall(function()
                    local p = win.Child(tp)
                    if p then
                        local sc = p.Child(cand.name)
                        if sc then child = sc end
                    end
                end)
                if child then break end
            end
        end
        if not child then
            child = AA.findChildRecursive(win, cand.name)
        end
        if child and child.Items then
            -- 1. Try native MacroQuest List text lookup first
            pcall(function()
                if targetName and targetName ~= '' and child.List then
                    local dIdx = tonumber(child.List('=' .. targetName) or 0) or 0
                    if dIdx <= 0 then dIdx = tonumber(child.List(targetName) or 0) or 0 end
                    if dIdx <= 0 and isSpecial then
                        dIdx = tonumber(child.List('=Summon Firework') or 0) or 0
                        if dIdx <= 0 then dIdx = tonumber(child.List('Summon Firework') or 0) or 0 end
                        if dIdx <= 0 then dIdx = tonumber(child.List('=Alternately Advanced Fireworks') or 0) or 0 end
                        if dIdx <= 0 then dIdx = tonumber(child.List('Alternately Advanced Fireworks') or 0) or 0 end
                    end
                    if dIdx > 0 then
                        child = child -- retain
                        cand.directIdx = dIdx
                    end
                end
            end)
            if cand.directIdx and cand.directIdx > 0 then
                return cand.name, cand.directIdx, cand.tab, child
            end

            -- 2. Fallback to iterating rows: an exact match (after stripping
            -- everything but letters and digits) wins; a row that merely
            -- starts with the target is remembered as a fallback; a row that
            -- only contains it somewhere ("Innate Run Speed" for "Run
            -- Speed") never matches. For the Special-tab fireworks AA (whose
            -- row text varies by server) a row naming fireworks is the last
            -- resort.
            local count = 0
            pcall(function() count = tonumber(child.Items() or 0) or 0 end)
            if count > 0 and count <= 500 then
                local prefixRow, fireworkRow = nil, nil
                for row = 1, count do
                    local rowText = nil
                    pcall(function()
                        local v = child.List(row, 1)
                        if type(v) == 'string' then
                            rowText = v
                        elseif type(v) == 'userdata' or type(v) == 'table' then
                            local ok, r = pcall(function() return v() end)
                            if ok and r ~= nil then rowText = tostring(r) else rowText = tostring(v) end
                        elseif type(v) == 'function' then
                            rowText = tostring(v())
                        end
                    end)
                    if not rowText or rowText == '' then
                        pcall(function()
                            local v = child.List(row)
                            if type(v) == 'string' then
                                rowText = v
                            elseif type(v) == 'userdata' or type(v) == 'table' then
                                local ok, r = pcall(function() return v() end)
                                if ok and r ~= nil then rowText = tostring(r) else rowText = tostring(v) end
                            elseif type(v) == 'function' then
                                rowText = tostring(v())
                            end
                        end)
                    end
                    if rowText and type(rowText) == 'string' and rowText ~= '' then
                        local cleanRow = rowText:lower():gsub('[^%a%d]', '')
                        if cleanRow ~= '' and cleanRow == cleanTarget then
                            return cand.name, row, cand.tab, child
                        elseif not prefixRow and cleanTarget ~= '' and cleanRow:sub(1, #cleanTarget) == cleanTarget then
                            prefixRow = row
                        elseif not fireworkRow and isSpecial and cleanRow:find('firework', 1, true) then
                            fireworkRow = row
                        end
                    end
                end
                if prefixRow or fireworkRow then
                    return cand.name, prefixRow or fireworkRow, cand.tab, child
                end
            end
        end
    end
    return nil, nil, nil, nil
end

AA.CLASS_ARCHETYPES = {
    War = { Melee = true, Tank = true, DualWield = true },
    Pal = { Melee = true, Tank = true, Hybrid = true, Priest = true },
    SK  = { Melee = true, Tank = true, Hybrid = true, Caster = true, Pet = true },
    Rng = { Melee = true, Hybrid = true, DualWield = true },
    Mnk = { Melee = true, PureMelee = true, DualWield = true },
    Rog = { Melee = true, PureMelee = true, DualWield = true },
    Brd = { Melee = true, Hybrid = true, DualWield = true },
    Bst = { Melee = true, Hybrid = true, DualWield = true, Pet = true },
    Ber = { Melee = true, PureMelee = true },
    Clr = { Priest = true, Caster = true },
    Dru = { Priest = true, Caster = true },
    Shm = { Priest = true, Caster = true, Pet = true },
    Nec = { Caster = true, Pet = true },
    Wiz = { Caster = true },
    Mag = { Caster = true, Pet = true },
    Enc = { Caster = true, Pet = true },
}

AA.ARCHETYPE_CLASSES = {
    Caster = { Wiz = true, Mag = true, Nec = true, Enc = true },
    Priest = { Clr = true, Dru = true, Shm = true, Pal = true },
    CasterPriest = { Wiz = true, Mag = true, Nec = true, Enc = true, Clr = true, Dru = true, Shm = true, Pal = true, Rng = true, SK = true, Brd = true, Bst = true },
    PriestCaster = { Wiz = true, Mag = true, Nec = true, Enc = true, Clr = true, Dru = true, Shm = true, Pal = true, Rng = true, Bst = true },
    Melee = { War = true, Pal = true, SK = true, Rng = true, Mnk = true, Rog = true, Brd = true, Bst = true, Ber = true },
    DualWield = { War = true, Rng = true, Mnk = true, Rog = true, Brd = true, Bst = true },
    Hybrid = { Pal = true, SK = true, Rng = true, Brd = true, Bst = true },
    Pet = { Mag = true, Nec = true, Bst = true, Shm = true, Enc = true, SK = true },
}

AA.ARCHETYPE_RESTRICTIONS = {
    ['Fury of Magic'] = 'Caster',
    ['Fury of Magic Mastery'] = 'Caster',
    ['Destructive Fury'] = 'Caster',
    ['Critical Affliction'] = 'Caster',
    ['Spell Casting Mastery'] = 'CasterPriest',
    ['Spell Casting Reinforcement'] = 'CasterPriest',
    ['Spell Casting Reinforcement Mastery'] = 'CasterPriest',
    ['Spell Casting Subtlety'] = 'CasterPriest',
    ['Spell Casting Fury'] = 'CasterPriest',
    ['Spell Casting Fury Mastery'] = 'CasterPriest',
    ['Mental Clarity'] = 'CasterPriest',
    ['Expanded Mental Clarity'] = 'CasterPriest',
    ['Body and Mind'] = 'CasterPriest',
    ['Advanced Spell Casting Mastery'] = 'Caster',
    ['Arcane Tongues'] = 'Caster',
    ['Mastery of the Past'] = 'Caster',
    ['Quick Damage'] = 'Caster',
    ['Quick Evacuation'] = 'Caster',
    ['Secondary Recall'] = 'Caster',
    ['Focus of Arcanum'] = 'CasterPriest',

    ['Healing Adept'] = 'Priest',
    ['Healing Gift'] = 'Priest',
    ['Radiant Cure'] = 'Priest',
    ['Purification'] = 'Priest',
    ['Hastened Purification'] = 'Priest',
    ['Hastened Curing'] = 'Priest',
    ['Quick Buff'] = 'Priest',
    ['Mass Group Buff'] = 'PriestCaster',

    ['Combat Fury'] = 'Melee',
    ['Veterancy'] = 'Melee',
    ['Weapon Affinity'] = 'Melee',
    ['Ferocity'] = 'Melee',
    ['Punishing Blow'] = 'Melee',
    ['Stun Resistance'] = 'Melee',
    ['Tactics'] = 'Melee',
    ['Ambidexterity'] = 'DualWield',
    ['Twinproc'] = 'DualWield',
    ['Sinister Strikes'] = 'DualWield',
    ['Chaotic Stab'] = 'DualWield',
    ['Extended Ingenuity'] = 'Hybrid',
    ['Fearless'] = 'Melee',

    ['Pet Affinity'] = 'Pet',
    ['Companion\'s Fury'] = 'Pet',
    ['Companion\'s Strength'] = 'Pet',
    ['Companion\'s Durability'] = 'Pet',
    ['Companion\'s Agility'] = 'Pet',
    ['Companion\'s Alacrity'] = 'Pet',
    ['Suspended Minion'] = 'Pet',
    ['Mend Companion'] = 'Pet',
    ['Summon Companion'] = 'Pet',
}

AA.CLASS_SPECIFIC_ABILITIES = {
    War = {
        'Area Taunt', 'Rampage', 'War Cry', 'Blade Guardian', 'Warlord\'s Tenacity',
        'Warlord\'s Resurgence', 'Hold the Line', 'Vehement Rage', 'Mark of the Mage Hunter',
        'Call of Challenge', 'Infused by Rage', 'Grappling Strike', 'Gut Punch',
        'Press the Attack', 'Battle Leap', 'Rage of Rallos Zek', 'Warlord\'s Fury',
        'Blast of Anger', 'Imperator\'s Command'
    },
    Clr = {
        'Divine Arbitration', 'Divine Resurrection', 'Celestial Regeneration', 'Turn Undead',
        'Bestow Divine Aura', 'Purify Soul', 'Sanctuary', 'Exquisite Benediction',
        'Celestial Hammer', 'Divine Retribution', 'Silent Casting', 'Ward of Purity',
        'Battle Frenzy', 'Divine Avatar', 'Improved Twincast', 'Innate Invis to Undead'
    },
    Pal = {
        'Lay on Hands', 'Hand of Piety', 'Divine Stun', 'Holy Steed', 'Valiant Steed',
        'Cloak of Light', 'Hand of Disruption', 'Beacon of the Righteous', 'Armor of the Inquisitor',
        'Act of Valor'
    },
    Rng = {
        'Headshot', 'Endless Quiver', 'Archery Mastery', 'Flaming Arrows', 'Frost Arrows',
        'Guardian of the Forest', 'Auspice of the Hunter', 'Entrap', 'Innate Camouflage',
        'Shared Camouflage', 'Protection of the Spirit Wolf'
    },
    SK = {
        'Harm Touch', 'Leech Touch', 'Death Peace', 'Touch of the Cursed', 'Soul Abrasion',
        'Explosion of Spite', 'Vicious Bite of Chaos', 'Abyssal Steed', 'Unholy Steed',
        'Cloak of Shadows'
    },
    Dru = {
        'Spirit of the Wood', 'Wrath of the Wild', 'Nature\'s Boon', 'Nature\'s Guardian',
        'Exodus', 'Convergence of Spirits', 'Paralytic Spores', 'Spirit of the Bear',
        'Teleport Bind', 'Call of the Wild', 'Nature\'s Blessing', 'Spirit of the Black Wolf',
        'Spirit of the White Wolf', 'Dire Charm (Animal)'
    },
    Mnk = {
        'Purify Body', 'Destructive Force', 'Imitate Death', 'Stunning Kick', 'Eye Gouge',
        'Crippling Strike', 'Distant Strike'
    },
    Rog = {
        'Escape', 'Purge Poison', 'Dirty Fighting', 'Twisted Shank', 'Ligament Slice',
        'Envenomed Blades', 'Appraisal', 'Tumble', 'Stealthy Getaway'
    },
    Shm = {
        'Cannibalization', 'Rabid Bear', 'Call of the Ancients', 'Ancestral Aid',
        'Spiritual Channeling', 'Union of Spirits', 'Turgur\'s Swarm', 'Malosinete',
        'Virulent Paralysis', 'Pact of the Wolf', 'Group Shrink', 'Languid Bite',
        'Spirit Guardian', 'Spiritual Blessing', 'Spirit Call', 'Ancestral Guard'
    },
    Nec = {
        'Life Burn', 'Dead Mesmerization', 'Death Bloom', 'Swarm of Decay', 'Wake the Dead',
        'Army of the Dead', 'Scent of Terris', 'Flesh to Bone', 'Blood Magic',
        'Pestilent Paralysis', 'Convergence', 'Hand of Death', 'Funeral Pyre',
        'Call to Corpse', 'Fear Storm', 'Dire Charm', 'Second Wind Ward', 'Replenish Companion'
    },
    Wiz = {
        'Mana Burn', 'Mana Blast', 'Mana Blaze', 'Frenzied Devastation', 'Call of Xuzl',
        'Harvest of Druzzil', 'Gelid Rending', 'Ro\'s Flaming Familiar', 'E\'ci\'s Icy Familiar',
        'Druzzil\'s Mystical Familiar', 'Improved Familiar', 'Strong Root', 'Nexus Gate',
        'Cryomancy', 'Pyromancy', 'Dimensional Shield', 'Translocational Anchor',
        'Mind Crash', 'Volatile Mana Blaze', 'Ward of Destruction', 'Prolonged Destruction'
    },
    Mag = {
        'Host of the Elements', 'Servant of Ro', 'Frenzied Burnout', 'Turn Summoned',
        'Heart of Flames', 'Heart of Ice', 'Heart of Stone', 'Heart of Vapor',
        'Dimensional Armory', 'Elemental Form: Air', 'Elemental Form: Earth',
        'Elemental Form: Fire', 'Elemental Form: Water', 'Host in the Shell',
        'Fire Core', 'Ice Core', 'Stone Core', 'Vapor Core', 'Shared Health'
    },
    Enc = {
        'Gather Mana', 'Color Shock', 'Eldritch Rune', 'Doppelganger', 'Soothing Words',
        'Bite of Tashani', 'Project Illusion', 'Edict of Command', 'Stasis',
        'Beam of Slumber', 'Azure Mind Crystal', 'Sanguine Mind Crystal',
        'Illusions of Grandeur', 'Mental Contortion', 'Veil of Mindshadow',
        'Mind Over Matter', 'Mana Draw', 'Nightmare Stasis'
    },
    Bst = {
        'Feral Swipe', 'Chameleon Strike', 'Bloodlust', 'Bite of the Asp', 'Bestial Alignment',
        'Frenzy of Spirit', 'Paragon of Spirit', 'Hobble of Spirits', 'Taste of Blood',
        'Frenzied Swipes', 'Roar of Thunder'
    },
    Ber = {
        'Cry of Battle', 'Desperation', 'Savage Spirit', 'Untamed Rage', 'Blood Pact',
        'Uncanny Resilience', 'Cascading Rage', 'Blinding Fury', 'Distraction Attack',
        'Tireless Sprint'
    },
    Brd = {
        'Fading Memories', 'Selo\'s Sonata', 'Boastful Bellow', 'Dance of Blades',
        'Song of Stone', 'Shield of Notes', 'Cacophony', 'Hymn of the Last Stand',
        'Bladed Song', 'Funeral Dirge'
    }
}

function AA.buildAAClassRestrictions()
    local map = {}
    for cls, aaNames in pairs(AA.CLASS_SPECIFIC_ABILITIES) do
        for _, nm in ipairs(aaNames) do
            if not map[nm] then map[nm] = {} end
            map[nm][cls] = true
        end
    end
    return map
end
AA.AA_CLASS_RESTRICTIONS = AA.buildAAClassRestrictions()

function AA.isAAAllowedForPlayer(name, classes, isFromUI)
    if not name or name == '' then return false end
    if isFromUI then return true end

    -- Special tab abilities (such as Fireworks) and designated cap spender are always allowed
    if AA.isSpecialTabAA and AA.isSpecialTabAA(name) then
        return true
    end
    if ctrl.auto_spend_aa_name and name == ctrl.auto_spend_aa_name then
        return true
    end

    -- 1. If player explicitly prioritized this ability, always allow it
    if ctrl.auto_aa_priorities and ctrl.auto_aa_priorities[name] then
        return true
    end

    -- 2. If character currently owns ranks in this ability, it belongs to the player
    local owned = false
    local isForeignStub = false
    local ctx = AA.scanCtx
    local probe = ctx and ctx.owned[name]
    if probe then
        owned, isForeignStub = probe[1], probe[2]
    else
        pcall(function()
            local ma = mq.TLO.Me.AltAbility(name)
            if ma and ma() then
                local r = tonumber(ma.Rank and ma.Rank() or 0) or 0
                local mr = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0
                if r > 0 and mr > 0 then
                    owned = true
                elseif r > 0 and mr <= 0 then
                    isForeignStub = true
                end
            end
        end)
        if ctx then ctx.owned[name] = { owned, isForeignStub } end
    end
    if isForeignStub then return false end
    if owned then return true end

    -- 3. If present in cached AA data with an ID and valid maxRank, it was discovered from the client
    if rt.cachedAAData and rt.cachedAAData[name] then
        local cd = rt.cachedAAData[name]
        if cd.id and cd.id > 0 and cd.maxRank and cd.maxRank > 0 then return true end
    end

    classes = classes or core.myClasses or {}

    -- 2. Class-specific restrictions check: reject if restricted to other classes
    local restrictedClasses = AA.AA_CLASS_RESTRICTIONS[name]
    if restrictedClasses then
        local match = false
        for _, cls in ipairs(classes) do
            if restrictedClasses[cls] then
                match = true
                break
            end
        end
        if not match then return false end
    end

    -- 3. Archetype restrictions check: reject if restricted to other archetypes
    local archReq = AA.ARCHETYPE_RESTRICTIONS[name]
    if archReq then
        local allowedClasses = AA.ARCHETYPE_CLASSES[archReq]
        if allowedClasses then
            local match = false
            for _, cls in ipairs(classes) do
                if allowedClasses[cls] then
                    match = true
                    break
                end
            end
            if not match then return false end
        end
    end

    return true
end

-- Cost of the next rank of `name`. Me.AltAbility(name).Cost is the cost of
-- the rank the character owns (or of rank 1 when untrained); the next rank
-- is a separate AltAbility record reached through NextIndex, and its Cost
-- is the real price. Neither member exists on every client build, so both
-- are probed under pcall. Fallback: the old "rank + 1" guess, which holds
-- for the General / Archetype lines whose ranks cost 1, 2, 3, ... but not
-- for flat-cost class lines - hence the probe first.
function AA.nextRankCost(name, rank)
    rank = tonumber(rank) or 0
    local cost = 0
    pcall(function()
        local ma = mq.TLO.Me.AltAbility(name)
        if not (ma and ma()) then return end
        if rank <= 0 and ma.Cost then
            cost = tonumber(ma.Cost() or 0) or 0
            if cost > 0 then return end
        end
        if ma.NextIndex then
            local nextIdx = tonumber(ma.NextIndex() or 0) or 0
            if nextIdx > 0 then
                local nx = mq.TLO.AltAbility(nextIdx)
                if nx and nx() and nx.Cost then cost = tonumber(nx.Cost() or 0) or 0 end
            end
        end
    end)
    if cost > 0 then return cost end
    return (rank > 0) and (rank + 1) or 1
end

function AA.recordScannedAA(list, foundMap, name, knownRank, knownMaxRank, knownCost, isKnownCharAA, category, isFromUI)
    if not name or name == '' or tonumber(name) then return end
    name = tostring(name):match('^%s*(.-)%s*$')
    if name == '' then return end

    -- Explicitly reject normal character skills (e.g. Mend, Flying Kick, Backstab, Dual Wield, Bandage Wounds)
    local ctx = AA.scanCtx
    local isSkill = ctx and ctx.skill[name]
    if isSkill == nil then
        isSkill = false
        pcall(function()
            if mq.TLO.Skill and mq.TLO.Skill(name) and mq.TLO.Skill(name)() ~= nil then
                isSkill = true
            end
        end)
        if ctx then ctx.skill[name] = isSkill end
    end
    if isSkill then return end

    -- Strictly reject abilities that do not belong to the player's class or archetype
    if not AA.isAAAllowedForPlayer(name, nil, isFromUI) then
        return
    end

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
        local isSpecial = (AA.isSpecialTabAA and AA.isSpecialTabAA(name))
        if not isSpecial and existing.maxRank > 0 and existing.rank >= existing.maxRank then
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
        local old = rt.cachedAAData[name]
        rt.cachedAAData[name] = {
            rank = existing.rank,
            maxRank = existing.maxRank,
            cost = existing.cost,
            category = existing.category,
            id = existing.id,
            minLevel = existing.minLevel or (old and old.minLevel),
            description = existing.description or (old and old.description)
        }
        return
    end

    local rank, maxRank, cost, canTrain, pointsSpent, id, passive, aaType, minLevel = 0, 0, 0, false, 0, 0, false, 0, 0
    local isCharacterAA = not not isKnownCharAA
    local description = ''

    if rt.cachedAAData and rt.cachedAAData[name] then
        local cd = rt.cachedAAData[name]
        if cd.rank ~= nil then rank = cd.rank end
        if cd.maxRank ~= nil and cd.maxRank > 0 then maxRank = cd.maxRank end
        if cd.cost ~= nil and cd.cost > 0 then cost = cd.cost end
        if cd.category and not category then category = cd.category end
        if cd.id ~= nil and cd.id > 0 then id = cd.id end
        if cd.minLevel ~= nil and cd.minLevel > 0 then minLevel = cd.minLevel end
        if cd.description and cd.description ~= '' then description = cd.description end
        isCharacterAA = true
    end

    pcall(function()
        local ma = mq.TLO.Me.AltAbility(name)
        if ma and ma() then
            local mid = tonumber(ma.ID and ma.ID() or 0) or 0
            if mid > 0 then
                id = mid
                isCharacterAA = true
                if rank == 0 then rank = tonumber(ma.Rank and ma.Rank() or 0) or 0 end
                if maxRank == 0 then maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0 end
                if cost == 0 then cost = tonumber(ma.Cost and ma.Cost() or 0) or 0 end
                if minLevel == 0 and ma.MinLevel then minLevel = tonumber(ma.MinLevel() or 0) or 0 end
                canTrain = (ma.CanTrain and ma.CanTrain() == true)
                pointsSpent = tonumber(ma.PointsSpent and ma.PointsSpent() or 0) or 0
                passive = (ma.Passive and ma.Passive() == true)
                aaType = tonumber(ma.Type and ma.Type() or 0) or 0
                if ma.Description then
                    local d = ma.Description()
                    if d and d ~= '' then description = tostring(d) end
                end
            end
        end
    end)

    pcall(function()
        if maxRank == 0 or cost == 0 or id == 0 or aaType == 0 or minLevel == 0 or not description or description == '' then
            local ga = mq.TLO.AltAbility(name)
            if ga and ga() then
                if id == 0 then id = tonumber(ga.ID and ga.ID() or 0) or 0 end
                if maxRank == 0 then maxRank = tonumber(ga.MaxRank and ga.MaxRank() or 0) or 0 end
                if cost == 0 then cost = tonumber(ga.Cost and ga.Cost() or 0) or 0 end
                if minLevel == 0 and ga.MinLevel then minLevel = tonumber(ga.MinLevel() or 0) or 0 end
                if not canTrain and ga.CanTrain then canTrain = (ga.CanTrain() == true) end
                if aaType == 0 and ga.Type then aaType = tonumber(ga.Type() or 0) or 0 end
                if not passive and ga.Passive then passive = (ga.Passive() == true) end
                if (not description or description == '') and ga.Description then
                    local d = ga.Description()
                    if d and d ~= '' then description = tostring(d) end
                end
            end
        end
    end)

    if knownRank ~= nil then rank = knownRank end
    if knownMaxRank ~= nil and knownMaxRank > 0 then maxRank = knownMaxRank end
    if knownCost ~= nil and knownCost > 0 then cost = knownCost end

    if not isCharacterAA and AA.specialTabAAs then
        for _, sName in ipairs(AA.specialTabAAs) do
            if sName == name then isCharacterAA = true; break end
        end
    end
    if not isCharacterAA and ctrl.auto_aa_priorities and ctrl.auto_aa_priorities[name] then
        isCharacterAA = true
    end

    local isSpecial = (AA.isSpecialTabAA and AA.isSpecialTabAA(name))
    local fullyTrained = not isSpecial and (maxRank > 0 and rank >= maxRank)
    if fullyTrained then
        cost = 0
    elseif cost <= 0 then
        if isSpecial then
            cost = tonumber(ctrl.auto_spend_aa_cost) or 25
        else
            cost = AA.nextRankCost(name, rank)
        end
    end

    if not fullyTrained and not canTrain then
        canTrain = true
    end

    -- Special tab repeatable abilities (such as Fireworks) have no positive fixed maxRank; assign synthetic maxRank = 1
    if isSpecial and (not maxRank or maxRank <= 0) then
        maxRank = 1
    end

    -- Strictly reject abilities that report rank without a valid max rank ("1/?") or have maxRank <= 0.
    -- In EQ/MQ, abilities showing 1/? are cross-class or unowned stubs that do not belong to the player.
    if not maxRank or maxRank <= 0 then
        return
    end

    if isCharacterAA and (maxRank > 0 or rank > 0 or canTrain or cost > 0) then
        local entry = {
            name = name,
            rank = rank,
            maxRank = maxRank,
            cost = cost,
            canTrain = canTrain,
            minLevel = minLevel,
            pointsSpent = pointsSpent,
            id = id,
            passive = passive,
            type = aaType,
            fullyTrained = fullyTrained,
            category = category,
            description = description
        }
        foundMap[name] = entry
        list[#list + 1] = entry

        if not rt.cachedAAData then rt.cachedAAData = {} end
        rt.cachedAAData[name] = {
            rank = rank,
            maxRank = maxRank,
            cost = cost,
            category = category,
            id = id,
            minLevel = minLevel,
            description = description
        }
    end
end

function AA.readSpecialTabNamesFromUI()
    local win = AA.getAAWindow()
    if not win then return nil end

    local specialCandidates = {
        'AAW_SpecialList', 'AA_SpecialList', 'SpecialList', 'Special_List',
        'AAW_Special_List', 'AAW_SpecList', 'AA_SpecList'
    }
    local tabParents = { 'AAW_Subwindows', 'AA_Subwindows', 'AA_SubWnd', 'AAW_SpecialTabPage', 'AA_SpecialTabPage' }

    for _, lName in ipairs(specialCandidates) do
        local child = nil
        pcall(function()
            child = win.Child(lName)
            if not child then
                for _, tp in ipairs(tabParents) do
                    local p = win.Child(tp)
                    if p then
                        local sc = p.Child(lName)
                        if sc then child = sc; break end
                    end
                end
            end
            if not child then
                child = AA.findChildRecursive(win, lName)
            end
        end)

        if child and child.Items then
            local count = 0
            pcall(function() count = tonumber(child.Items() or 0) or 0 end)
            if count > 0 and count <= 1000 then
                local names = {}
                local seen = {}
                for row = 1, count do
                    local rowTxt = nil
                    pcall(function() rowTxt = child.List(row, 1)() or child.List(row)() end)
                    if rowTxt and type(rowTxt) == 'string' and rowTxt ~= '' then
                        local trimmed = rowTxt:match('^%s*(.-)%s*$')
                        if trimmed and trimmed ~= '' and not seen[trimmed] then
                            seen[trimmed] = true
                            names[#names + 1] = trimmed
                        end
                    end
                end
                if #names > 0 then
                    return names
                end
            end
        end
    end
    return nil
end

function AA.readSpecialTabOnce(force)
    if not force and AA.specialTabReadDone and AA.specialTabAAs and #AA.specialTabAAs > 0 then
        return AA.specialTabAAs
    end
    AA.specialTabAAs = AA.specialTabAAs or {}

    -- 1. Try non-blocking read if already populated in UI
    local names = AA.readSpecialTabNamesFromUI()
    if names and #names > 0 then
        AA.specialTabAAs = names
        AA.specialTabReadDone = true
        return names
    end

    -- 2. If AAWindow is already open, try selecting Tab 4 (Special) safely
    local wasOpen = AA.isAAWindowOpen()
    if wasOpen then
        local win = AA.getAAWindow()
        local winName = AA.getAAWindowName()
        mq.cmdf('/nomodkey /notify %s AAW_Subwindows tabselect 4', winName)
        mq.cmdf('/nomodkey /notify %s Subwindows tabselect 4', winName)
        pcall(function()
            if win then
                local sub = win.Child('AAW_Subwindows') or AA.findChildRecursive(win, 'AAW_Subwindows')
                if sub and sub.SetCurrentTab then sub.SetCurrentTab(4) end
            end
        end)
        mq.delay(50)
        names = AA.readSpecialTabNamesFromUI()
        if names and #names > 0 then
            AA.specialTabAAs = names
            AA.specialTabReadDone = true
            print(string.format('\ag[Triune]\ax Read %d abilities from AA Special tab.', #names))
        end
    end

    return AA.specialTabAAs or {}
end

-- Full rescan: ~1,640 AltAbility ids by index plus name lookups for every
-- catalogued AA. Runs on the tick only (never from a draw hook): the window
-- and the purchase workflow queue it through AA.requestScan. Name-keyed TLO
-- results (skill check, ownership probe) are cached in AA.scanCtx for the
-- duration of one scan, since most names are recorded several times.
function AA.scanPlayerAAs(force)
    local now = os.clock()
    if not force and AA.lastAAScanAt and (now - AA.lastAAScanAt) < AA.SCAN_MIN_INTERVAL and AA.scannedAAs and #AA.scannedAAs > 0 then
        return AA.scannedAAs
    end
    AA.lastAAScanAt = now
    AA.scanRequestAt = nil
    AA.scanning = true

    local foundMap = {}
    local list = {}
    AA.scanCtx = { foundMap = foundMap, skill = {}, owned = {} }

    -- 1. Scan in-game AAWindow lists if present in UI memory
    pcall(function()
        local win = AA.getAAWindow()
        if win then
            local listCandidates = {
                'AAW_GeneralList', 'AAW_ArchList', 'AAW_ArchetypeList', 'AAW_ClassList', 'AAW_SpecialList',
                'AA_GeneralList', 'AA_ArchList', 'AA_ArchetypeList', 'AA_ClassList', 'AA_SpecialList',
                'GeneralList', 'ArchList', 'ClassList', 'SpecialList',
                'List1', 'List2', 'List3', 'List4',
                'AAW_List', 'AA_List', 'AAW_SearchResultList', 'AA_SearchResultList'
            }
            local scannedChildren = {}
            for _, lName in ipairs(listCandidates) do
                local child = nil
                pcall(function() child = win.Child(lName) end)
                if not child then
                    child = AA.findChildRecursive(win, lName)
                end
                if child and child.Items and not scannedChildren[child] then
                    scannedChildren[child] = true
                    local count = 0
                    pcall(function() count = tonumber(child.Items() or 0) or 0 end)
                    if count > 0 and count <= 1000 then
                        for row = 1, count do
                            local nameTxt = nil
                            local curMaxTxt = nil
                            local costTxt = nil
                            local catTxt = nil
                            pcall(function()
                                nameTxt = child.List(row, 1)() or child.List(row)()
                                curMaxTxt = child.List(row, 2)()
                                costTxt = child.List(row, 3)()
                                catTxt = child.List(row, 4)()
                            end)
                            if nameTxt and type(nameTxt) == 'string' and nameTxt ~= '' then
                                local trimmed = nameTxt:match('^%s*(.-)%s*$')
                                if trimmed and trimmed ~= '' and not tonumber(trimmed) then
                                    local curRank, maxRank = nil, nil
                                    if curMaxTxt and type(curMaxTxt) == 'string' then
                                        local c, m = curMaxTxt:match('(%d+)%s*/%s*(%d+)')
                                        if c and m then
                                            curRank = tonumber(c)
                                            maxRank = tonumber(m)
                                        end
                                    end
                                    local costVal = nil
                                    if costTxt and type(costTxt) == 'string' then
                                        local c = costTxt:match('%d+')
                                        if c then costVal = tonumber(c) end
                                    end
                                    AA.recordScannedAA(list, foundMap, trimmed, curRank, maxRank, costVal, true, catTxt, true)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- 1.5 Load previously cached AAWindow abilities into current scan (pruning skills and invalid 1/? entries)
    if rt.cachedAAData then
        for cName, cd in pairs(rt.cachedAAData) do
            local isSkill = false
            pcall(function()
                if mq.TLO.Skill and mq.TLO.Skill(cName) and mq.TLO.Skill(cName)() ~= nil then
                    isSkill = true
                end
            end)
            if not cd.maxRank or cd.maxRank <= 0 then
                rt.cachedAAData[cName] = nil
            elseif isSkill or not AA.isAAAllowedForPlayer(cName, nil, false) then
                rt.cachedAAData[cName] = nil
            elseif not foundMap[cName] then
                AA.recordScannedAA(list, foundMap, cName, cd.rank, cd.maxRank, cd.cost, true, cd.category, false)
            end
        end
    end

    -- 2. Scan known DATA.aas combat abilities for character's classes
    if DATA and DATA.aas then
        for _, cls in ipairs(core.myClasses or {}) do
            for _, item in ipairs(DATA.aas[cls] or {}) do
                local nm = type(item) == 'table' and (item[1] or item.name) or tostring(item)
                if type(nm) == 'string' then nm = nm:match('^%s*(.-)%s*$') end
                if nm and nm ~= '' and not tonumber(nm) then
                    AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true, cls, false)
                end
            end
        end
    end

    -- 3. Scan common general AAs (universal to all classes)
    AA.GENERAL_AAS = {
        'Run Speed', 'Innate Run Speed', 'Combat Agility', 'Combat Stability', 'Natural Durability',
        'Physical Enhancement', 'Planar Power', 'Planar Durability', 'First Aid',
        'Innate Strength', 'Innate Stamina', 'Innate Agility', 'Innate Dexterity', 'Innate Intelligence',
        'Innate Wisdom', 'Innate Charisma', 'Delay Death', 'New Tanaan Crafting Mastery', 'Baking Mastery',
        'Blacksmithing Mastery', 'Brewing Mastery', 'Fletching Mastery', 'Jewelcraft Mastery',
        'Pottery Mastery', 'Tailoring Mastery', 'Salvage', 'Origin'
    }
    for _, nm in ipairs(AA.GENERAL_AAS) do
        AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true, 'General', false)
    end

    -- 3.5 Scan archetype and class AAs strictly matching the character's classes
    for nm in pairs(AA.ARCHETYPE_RESTRICTIONS) do
        if AA.isAAAllowedForPlayer(nm, nil, false) then
            AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true, 'Archetype', false)
        end
    end

    for _, cls in ipairs(core.myClasses or {}) do
        local classAAList = AA.CLASS_SPECIFIC_ABILITIES and AA.CLASS_SPECIFIC_ABILITIES[cls]
        if classAAList then
            for _, nm in ipairs(classAAList) do
                AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true, cls, false)
            end
        end
    end

    -- 4. Scan Special tab abilities (from one-time read of the Special tab)
    local specialList = AA.specialTabAAs
    if (not specialList or #specialList == 0) and not AA.specialTabReadDone then
        local uiNames = AA.readSpecialTabNamesFromUI()
        if uiNames and #uiNames > 0 then
            AA.specialTabAAs = uiNames
            AA.specialTabReadDone = true
            specialList = uiNames
        end
    end
    if specialList and #specialList > 0 then
        for _, nm in ipairs(specialList) do
            AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true, 'Special', true)
        end
    end
    if ctrl.auto_spend_aa_name and ctrl.auto_spend_aa_name ~= '' then
        AA.recordScannedAA(list, foundMap, ctrl.auto_spend_aa_name, nil, nil, nil, true, nil, false)
    end

    -- 5. Scan character AltAbility indices across known ID ranges
    pcall(function()
        local function probeRange(startId, endId)
            for idx = startId, endId do
                local ma = mq.TLO.Me.AltAbility(idx)
                if ma and ma() then
                    local nm = ma.Name and ma.Name()
                    local r = tonumber(ma.Rank and ma.Rank() or 0) or 0
                    local mr = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0
                    if nm and nm ~= '' and mr > 0 then
                        AA.recordScannedAA(list, foundMap, nm, r > 0 and r or nil, mr, nil, true, nil, false)
                    end
                end
            end
        end
        probeRange(1, 1500)
        probeRange(4000, 4060)
        probeRange(5000, 5050)
        probeRange(8120, 8140)
        probeRange(17780, 17800)
    end)

    -- 6. Saved priorities
    if ctrl.auto_aa_priorities then
        for nm in pairs(ctrl.auto_aa_priorities) do
            AA.recordScannedAA(list, foundMap, nm, nil, nil, nil, true)
        end
    end

    AA.scannedAAs = list
    AA.scannedAAMap = foundMap
    AA.scanCtx = nil
    AA.scanning = false
    AA.aaFilterDirty = true
    return list
end

-- Tick side of AA.requestScan.
function AA.runPendingScan()
    if AA.scanRequestAt and os.clock() >= AA.scanRequestAt then
        AA.scanRequestAt = nil
        AA.lastAAScanAt = 0
        AA.aaFilterDirty = true
        local ok, err = pcall(AA.scanPlayerAAs, true)
        AA.scanning = false
        AA.scanCtx = nil
        if not ok then print(string.format('\ar[Triune]\ax AA scan failed: %s', tostring(err))) end
    end
end

function AA.getFilteredSortedAAs()
    if not AA.scannedAAs or #AA.scannedAAs == 0 then
        -- Runs from the window (draw thread): only ask for a scan.
        AA.requestScan(0)
        return AA.filteredSortedAAs or {}
    end

    if not AA.aaFilterDirty and AA.filteredSortedAAs then
        return AA.filteredSortedAAs
    end

    local result = {}
    local rawQuery = ctrl.auto_aa_search or ''
    local query = rawQuery:lower():match('^%s*(.-)%s*$')
    local hideMaxed = ctrl.auto_aa_hide_maxed or false
    local onlyPrio = ctrl.auto_aa_only_prioritized or false
    local priorities = ctrl.auto_aa_priorities or {}

    for _, item in ipairs(AA.scannedAAs or {}) do
        local match = true
        -- Filter out foreign/invalid abilities displaying as 1/? (missing or non-positive maxRank)
        if not item.maxRank or item.maxRank <= 0 then
            match = false
        end
        if hideMaxed and item.fullyTrained then
            match = false
        end
        if match and onlyPrio and not priorities[item.name] then
            match = false
        end
        if match and query and query ~= '' then
            if not item.name:lower():find(query, 1, true) then
                match = false
            end
        end
        if match then
            result[#result + 1] = item
        end
    end

    local sortBy = ctrl.auto_aa_sort_by or 'name'
    local asc = (ctrl.auto_aa_sort_asc ~= false)

    table.sort(result, function(a, b)
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
        else -- 'name'
            local nA = a.name:lower()
            local nB = b.name:lower()
            if nA ~= nB then
                if asc then return nA < nB else return nA > nB end
            end
            return (a.cost or 0) < (b.cost or 0)
        end
    end)

    AA.filteredSortedAAs = result
    AA.aaFilterDirty = false
    return result
end

function AA.startAATrainWorkflow(targetName, allowStop)
    if AA.pendingAATrain then return false end
    targetName = targetName or ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
    if type(targetName) == 'string' then targetName = targetName:match('^%s*(.-)%s*$') end

    local aaId = 0
    local aaType = 0
    pcall(function()
        local ma = mq.TLO.Me.AltAbility(targetName)
        if ma and ma() then
            if ma.ID then aaId = tonumber(ma.ID() or 0) or 0 end
            if ma.Type then aaType = tonumber(ma.Type() or 0) or 0 end
        end
        if aaId == 0 or aaType == 0 then
            local ga = mq.TLO.AltAbility(targetName)
            if ga and ga() then
                if aaId == 0 and ga.ID then aaId = tonumber(ga.ID() or 0) or 0 end
                if aaType == 0 and ga.Type then aaType = tonumber(ga.Type() or 0) or 0 end
            end
        end
    end)
    if aaId == 0 and (targetName:lower():find('firework') or targetName == (ctrl.auto_spend_aa_name or '')) then
        aaId = tonumber(ctrl.auto_spend_aa_id or 17788) or 17788
        aaType = 4
    end

    local prefTab = 1
    local cat = nil
    if rt.cachedAAData and rt.cachedAAData[targetName] and rt.cachedAAData[targetName].category then
        cat = tostring(rt.cachedAAData[targetName].category):lower()
    end
    if not cat and AA.scannedAAMap then
        local itm = AA.scannedAAMap[targetName]
        if itm and itm.category then cat = tostring(itm.category):lower() end
    end
    local isClass = false
    if cat then
        local catUpper = cat:upper()
        local catTitle = cat:sub(1,1):upper() .. cat:sub(2):lower()
        if AA.CLASS_SPECIFIC_ABILITIES and (AA.CLASS_SPECIFIC_ABILITIES[catUpper] or AA.CLASS_SPECIFIC_ABILITIES[catTitle]) then
            isClass = true
        elseif AA.CLASS_ARCHETYPES and (AA.CLASS_ARCHETYPES[catUpper] or AA.CLASS_ARCHETYPES[catTitle]) then
            isClass = true
        elseif cat:find('class') then
            isClass = true
        end
    end

    if cat then
        if cat:find('special') then prefTab = 4
        elseif isClass then prefTab = 3
        elseif cat:find('arch') then prefTab = 2
        elseif cat:find('gen') then prefTab = 1
        elseif aaType == 4 or (AA.isSpecialTabAA and AA.isSpecialTabAA(targetName)) then prefTab = 4
        elseif aaType == 3 then prefTab = 3
        elseif aaType == 2 then prefTab = 2
        elseif aaType == 1 then prefTab = 1
        end
    elseif aaType == 4 or targetName:lower():find('firework') or (AA.isSpecialTabAA and AA.isSpecialTabAA(targetName)) then
        prefTab = 4
    elseif aaType == 3 then
        prefTab = 3
    elseif aaType == 2 then
        prefTab = 2
    elseif aaType == 1 then
        prefTab = 1
    end

    AA.pendingAATrain = {
        name = targetName,
        aaId = aaId,
        aaType = aaType,
        targetTab = prefTab,
        prefTab = prefTab,
        step = 'open',
        tab = prefTab,
        maxTabs = 4,
        tabsTried = 0,               -- tabs searched so far (wraps around from prefTab)
        toggledTrainFilter = false,  -- we clicked AAW_TrainFilter; finish/abort clicks it back
        pointsBefore = nil,          -- Me.AAPoints before the Train click (purchase check)
        openedByUs = false,
        allowStop = allowStop or false,
        startedAt = os.clock(),
        nextStepAt = os.clock() + 0.5,
        retries = 0
    }
    print(string.format('\ag[Triune]\ax Initiating AA Window train sequence for "%s" (ID: %d, Tab: %d)...', targetName, aaId, prefTab))
    return true
end

-- AAW_TrainFilter ("Can Purchase") is a toggle: clicking it flips it.
function AA.clickTrainFilter(winName)
    winName = winName or AA.getAAWindowName()
    mq.cmdf('/nomodkey /notify %s AAW_TrainFilter leftmouseup', winName)
    mq.cmdf('/nomodkey /notify %s CanPurchaseFilter leftmouseup', winName)
end

-- Puts the AA window back the way the workflow found it: the train filter
-- we toggled, and the window itself when we opened it.
function AA.restoreAAWindow(task)
    if not task then return end
    if task.toggledTrainFilter then
        task.toggledTrainFilter = false
        if AA.isAAWindowOpen() then AA.clickTrainFilter(AA.getAAWindowName()) end
    end
    if task.openedByUs then AA.closeAAWindow() end
end

function AA.abortAATrain(task)
    AA.restoreAAWindow(task)
    AA.pendingAATrain = nil
end

function AA.processAATrainWorkflow()
    local task = AA.pendingAATrain
    if not task then return end

    local now = os.clock()

    -- Strict anti-pause check: abort immediately if player is moving, navigating, or casting
    local moving = false
    pcall(function()
        if mq.TLO.Me.Moving and mq.TLO.Me.Moving() then moving = true end
        if rt.isMoveActive and rt.isMoveActive() then moving = true end
        if mq.TLO.Navigation and mq.TLO.Navigation.Active and mq.TLO.Navigation.Active() then moving = true end
    end)
    if moving then
        if task.allowStop and (now - (task.startedAt or now)) < 0.35 then
            if rt.stopMoving then rt.stopMoving() end
            task.nextStepAt = now + 0.1
            return
        end
        AA.abortAATrain(task)
        return
    end
    if rt.isCasting() then
        AA.abortAATrain(task)
        return
    end

    -- Strict out-of-combat enforcement: if combat engages mid-train, close window immediately and abort
    local inCombat = false
    pcall(function()
        if mq.TLO.Me.Combat and mq.TLO.Me.Combat() then inCombat = true return end
        if mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT' then inCombat = true return end
        if mq.TLO.Me.AutoFire and mq.TLO.Me.AutoFire() then inCombat = true return end
        if rt.isCombat and rt.isCombat() then inCombat = true return end
        if rt.anyXtarAlive and rt.anyXtarAlive(true) then inCombat = true return end
    end)
    if inCombat then
        AA.abortAATrain(task)
        return
    end

    if now < (task.nextStepAt or 0) then return end

    if task.step == 'open' then
        if AA.isAAWindowOpen() then
            task.openedByUs = false
            task.step = 'prepare_tab'
            task.nextStepAt = now + 0.05
            return
        else
            task.openedByUs = true
            task.retries = 0
            AA.openAAWindow(1)
            task.nextStepAt = now + 0.35
            task.step = 'wait_open'
            return
        end

    elseif task.step == 'wait_open' then
        if AA.isAAWindowOpen() then
            task.step = 'prepare_tab'
            task.nextStepAt = now + 0.1
            return
        end

        task.retries = (task.retries or 0) + 1
        if task.retries <= 4 then
            AA.openAAWindow(task.retries + 1)
            task.nextStepAt = now + 0.35
            return
        else
            -- Nothing to click on: fail the task (the 30 s per-AA retry
            -- spacing applies) rather than driving a window that is closed.
            print(string.format('\ar[Triune]\ax Failed to open AA Window after %d attempts. Aborting AA train sequence for "%s".', task.retries, task.name))
            task.failed = 'window'
            task.step = 'finish'
            task.nextStepAt = now + 0.05
            return
        end

    elseif task.step == 'prepare_tab' then
        local win = AA.getAAWindow()
        local winName = AA.getAAWindowName()
        local targetTab = task.targetTab or task.tab or 1

        -- Clear leftover search filter text if present so abilities are not hidden
        pcall(function()
            if win then
                local sb = win.Child('AAW_SearchBox') or win.Child('SearchBox')
                if sb and sb.Text then
                    local txt = sb.Text()
                    if txt and txt ~= '' then
                        if sb.SetText then sb.SetText('') end
                        mq.cmdf('/nomodkey /notify %s AAW_SearchBox settext ""', winName)
                        mq.cmdf('/nomodkey /notify %s SearchBox settext ""', winName)
                        local sbtn = win.Child('AAW_SearchBtn') or win.Child('SearchBtn') or win.Child('AAW_SearchButton') or win.Child('SearchButton')
                        if sbtn then
                            mq.cmdf('/nomodkey /notify %s %s leftmouseup', winName, sbtn.Name and sbtn.Name() or 'SearchBtn')
                        end
                    end
                end
            end
        end)

        -- Select the target tab page first so its listbox is active
        mq.cmdf('/nomodkey /notify %s AAW_Subwindows tabselect %d', winName, targetTab)
        mq.cmdf('/nomodkey /notify %s Subwindows tabselect %d', winName, targetTab)
        pcall(function()
            if win then
                local sub = win.Child('AAW_Subwindows') or win.Child('Subwindows')
                if not sub then sub = AA.findChildRecursive(win, 'AAW_Subwindows') or AA.findChildRecursive(win, 'Subwindows') end
                if sub and sub.SetCurrentTab then sub.SetCurrentTab(targetTab) end
            end
        end)

        -- For Special tab or special repeatable abilities, ensure AAW_TrainFilter ("Can Purchase") is unchecked so completed/repeatable abilities appear
        if targetTab == 4 or (AA.isSpecialTabAA and AA.isSpecialTabAA(task.name)) then
            pcall(function()
                if win then
                    local tf = win.Child('AAW_TrainFilter') or win.Child('CanPurchaseFilter')
                    if not tf then tf = AA.findChildRecursive(win, 'AAW_TrainFilter') or AA.findChildRecursive(win, 'CanPurchaseFilter') end
                    if tf and tf.Checked and tf.Checked() then
                        AA.clickTrainFilter(winName)
                        task.toggledTrainFilter = not task.toggledTrainFilter
                    end
                end
            end)
        end

        task.step = 'select_item'
        task.nextStepAt = now + 0.25
        return

    elseif task.step == 'select_item' then
        local winName = AA.getAAWindowName()
        local listName, listIdx, foundTab, listObj = AA.findAAInWindowLists(task.name, task.targetTab or task.tab)

        if (task.targetTab == 4 or foundTab == 4) and (not AA.specialTabAAs or #AA.specialTabAAs == 0) then
            pcall(function()
                local sNames = AA.readSpecialTabNamesFromUI()
                if sNames and #sNames > 0 then
                    AA.specialTabAAs = sNames
                    AA.specialTabReadDone = true
                end
            end)
        end

        if listName and listIdx and listIdx > 0 then
            -- Found the ability row! If found on a different tab, switch to that tab first
            if foundTab and foundTab ~= task.targetTab then
                mq.cmdf('/nomodkey /notify %s AAW_Subwindows tabselect %d', winName, foundTab)
                mq.cmdf('/nomodkey /notify %s Subwindows tabselect %d', winName, foundTab)
                pcall(function()
                    local win = AA.getAAWindow()
                    if win then
                        local sub = win.Child('AAW_Subwindows') or win.Child('Subwindows')
                        if not sub then sub = AA.findChildRecursive(win, 'AAW_Subwindows') or AA.findChildRecursive(win, 'Subwindows') end
                        if sub and sub.SetCurrentTab then sub.SetCurrentTab(foundTab) end
                    end
                end)
                task.targetTab = foundTab
                task.nextStepAt = now + 0.15
                return
            end
            pcall(function()
                if listObj and listObj.Select then
                    listObj.Select(listIdx)
                end
                if listObj and listObj.LeftMouseUp then
                    listObj.LeftMouseUp()
                end
            end)
            mq.cmdf('/nomodkey /notify %s %s listselect %d', winName, listName, listIdx)
            mq.cmdf('/nomodkey /notify %s %s leftmouseup', winName, listName)
            task.step = 'click_train'
            task.nextStepAt = now + 0.25
            return
        else
            -- Not on this tab: try the next one, wrapping around so every
            -- tab is searched once no matter which one we started on.
            task.tabsTried = (task.tabsTried or 0) + 1
            if task.tabsTried < (task.maxTabs or 4) then
                task.tab = ((task.tab or 1) % (task.maxTabs or 4)) + 1
                task.targetTab = task.tab
                task.step = 'prepare_tab'
                task.nextStepAt = now + 0.15
                return
            elseif not task.triedUncheckTrainFilter then
                -- Try unchecking CanPurchase/Train filter in case completed/repeatable ability is hidden
                task.triedUncheckTrainFilter = true
                local checked = nil
                pcall(function()
                    local win = AA.getAAWindow()
                    local tf = win and (win.Child('AAW_TrainFilter') or win.Child('CanPurchaseFilter'))
                    if tf and tf.Checked then checked = (tf.Checked() == true) end
                end)
                if checked ~= false then
                    -- toggle it (and remember to toggle it back) unless it is known to be off already
                    AA.clickTrainFilter(winName)
                    task.toggledTrainFilter = not task.toggledTrainFilter
                end
                task.tabsTried = 0
                task.tab = task.prefTab or 1
                task.targetTab = task.tab
                task.step = 'prepare_tab'
                task.nextStepAt = now + 0.15
                return
            elseif not task.triedResetFilter then
                -- Try resetting window filters in case a filter hid the ability
                task.triedResetFilter = true
                mq.cmdf('/nomodkey /notify %s AAW_ResetFilter leftmouseup', winName)
                mq.cmdf('/nomodkey /notify %s ResetFilter leftmouseup', winName)
                task.tabsTried = 0
                task.tab = task.prefTab or 1
                task.targetTab = task.tab
                task.step = 'prepare_tab'
                task.nextStepAt = now + 0.15
                return
            else
                -- AA not found in any window list; record attempt and close
                if task.aaId and task.aaId > 0 then
                    print(string.format('\ay[Triune]\ax Could not locate "%s" in AA Window lists (ID: %d). Recording attempt.', task.name, task.aaId))
                end
                task.failed = 'notfound'
                task.step = 'finish'
                task.nextStepAt = now + 0.4
                return
            end
        end

    elseif task.step == 'click_train' then
        local win = AA.getAAWindow()
        local winName = AA.getAAWindowName()
        local trainButtons = { 'AAW_TrainButton', 'TrainButton', 'AA_TrainButton' }
        local clicked = false
        task.pointsBefore = nil
        pcall(function() task.pointsBefore = tonumber(mq.TLO.Me.AAPoints() or 0) or 0 end)
        if win then
            for _, btnName in ipairs(trainButtons) do
                local btn = nil
                pcall(function() btn = win.Child(btnName) end)
                if not btn then
                    btn = AA.findChildRecursive(win, btnName)
                end
                if btn then
                    pcall(function()
                        if btn.LeftMouseDown then btn.LeftMouseDown() end
                        if btn.LeftMouseUp then btn.LeftMouseUp() end
                    end)
                    mq.cmdf('/nomodkey /notify %s %s leftmousedown', winName, btnName)
                    mq.cmdf('/nomodkey /notify %s %s leftmouseup', winName, btnName)
                    clicked = true
                    break
                end
            end
        end
        if not clicked then
            mq.cmdf('/nomodkey /notify %s AAW_TrainButton leftmousedown', winName)
            mq.cmdf('/nomodkey /notify %s AAW_TrainButton leftmouseup', winName)
            mq.cmdf('/nomodkey /notify %s TrainButton leftmousedown', winName)
            mq.cmdf('/nomodkey /notify %s TrainButton leftmouseup', winName)
        end

        print(string.format('\ag[Triune]\ax Clicked Train Button in AA Window for "%s".', task.name))
        local isFw = task.name and (task.name:lower():find('firework') ~= nil or task.name == (ctrl.auto_spend_aa_name or ''))
        if isFw then
            -- The purchase has to round-trip the server before the AA can be
            -- activated; /alt act right after the click was a no-op. Schedule
            -- the summon instead (see AA.processPendingFireworksSummon).
            local fwId = tonumber(ctrl.auto_spend_aa_id or task.aaId or 17788) or 17788
            AA.scheduleFireworksSummon(fwId, task.name)
        end
        task.step = 'verify'
        task.verifyUntil = now + 2.5
        task.nextStepAt = now + 0.3
        return

    elseif task.step == 'verify' then
        -- The purchase round-trips the server: wait (up to ~2.5 s) for the
        -- unspent total to drop below what it was before the Train click.
        local after = nil
        pcall(function() after = tonumber(mq.TLO.Me.AAPoints() or 0) or 0 end)
        if task.pointsBefore ~= nil and after ~= nil and after < task.pointsBefore then
            task.purchased = true
            task.step = 'finish'
            task.nextStepAt = now + 0.1
            return
        end
        if now < (task.verifyUntil or 0) then
            task.nextStepAt = now + 0.25
            return
        end
        task.purchased = false
        task.step = 'finish'
        task.nextStepAt = now + 0.05
        return

    elseif task.step == 'finish' then
        AA.restoreAAWindow(task)
        AA.lastAATrainAttempt = AA.lastAATrainAttempt or {}
        AA.lastAATrainAttempt[task.name] = now
        AA.pendingAATrain = nil
        AA.lastAASpendDelegatedTarget = nil
        AA.lastAASpendDelegatedAt = nil
        AA.lastAACapDelegatedAt = nil
        AA.lastAACapDelegatedTarget = nil
        if task.purchased then
            AA.trainBackoff[task.name] = nil
            AA.trainFailLogged[task.name] = nil
            -- One deferred scan once the client has the new rank (the
            -- purchase event and the AAPointsSpent change fold into it).
            AA.requestScan(1.2)
            AA.pendingPostTrainScanAt = nil
            core.saveLoadout(true)
        elseif task.failed == 'window' then
            -- could not even open the window: the 30 s per-AA spacing applies
            AA.aaFilterDirty = true
        else
            -- Clicked (or could not find) the row and no points were spent:
            -- back this AA off instead of running the whole window cycle
            -- again every 30 s. Log it once until it succeeds.
            AA.trainBackoff[task.name] = now + AA.TRAIN_FAIL_BACKOFF
            if not AA.trainFailLogged[task.name] then
                AA.trainFailLogged[task.name] = true
                print(string.format('\ay[Triune]\ax AA purchase of "%s" did not go through (%s); not retrying it for %d minutes.',
                    task.name, task.failed == 'notfound' and 'not found in the AA window' or 'no points were spent after Train', math.floor(AA.TRAIN_FAIL_BACKOFF / 60)))
            end
            AA.requestScan(1.0)
        end
        return
    end
end

-- Writes the [MQ2AASpend_Settings] / [MQ2AASpend_AAList] sections of
-- Server_Character.ini and asks MQ2AAspend to reload them. The INI is only
-- rewritten (and the plugin only reloaded) when the generated sections differ
-- from what was last written; `force` bypasses that check (manual Sync).
function AA.syncAAsToMQ2AASpendIni(silent, force)
    local server, cleanName
    pcall(function()
        server = mq.TLO.EverQuest.Server()
        cleanName = mq.TLO.Me.CleanName()
    end)
    if not server or server == '' or not cleanName or cleanName == '' then return false end

    local iniFile = string.format('%s/%s_%s.ini', (mq.configDir or 'config'), server, cleanName)

    local prioList = {}
    if ctrl.auto_aa_priorities then
        for nm, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled and (not AA.isSpecialTabAA or not AA.isSpecialTabAA(nm)) then
                local cost = 0
                if rt.cachedAAData and rt.cachedAAData[nm] then
                    cost = rt.cachedAAData[nm].cost or 0
                end
                prioList[#prioList + 1] = { name = nm, cost = cost }
            end
        end
    end

    if ctrl.auto_aa_buy_order == 'list' then
        table.sort(prioList, function(a, b) return a.name:lower() < b.name:lower() end)
    else
        table.sort(prioList, function(a, b)
            if a.cost ~= b.cost then return a.cost < b.cost end
            return a.name:lower() < b.name:lower()
        end)
    end

    local section = {}
    section[#section + 1] = '[MQ2AASpend_Settings]'
    section[#section + 1] = 'AutoSpend=1'
    section[#section + 1] = (ctrl.auto_aa_aaspend_mode == 'brute') and 'BruteForce=1' or 'BruteForce=0'
    section[#section + 1] = 'BruteForceBonusFirst=0'
    section[#section + 1] = string.format('BankPoints=%d', ctrl.auto_spend_aa_threshold or 0)
    section[#section + 1] = 'SpendOrder=35214'
    section[#section + 1] = ''
    section[#section + 1] = '[MQ2AASpend_AAList]'
    for idx, item in ipairs(prioList) do
        section[#section + 1] = string.format('%d=%s|M', idx, item.name)
    end

    -- Skip the file read, the write and /aaspend load when nothing that
    -- feeds the INI changed (this runs on every loadout save).
    local fingerprint = iniFile .. '\n' .. table.concat(section, '\n')
    if not force and AA.lastAASpendIniFingerprint == fingerprint then
        return true, false
    end

    local lines = {}
    local f = io.open(iniFile, 'r')
    if f then
        for line in f:lines() do
            lines[#lines + 1] = line
        end
        f:close()
    end

    local newLines = {}
    local inTargetSection = false
    for _, line in ipairs(lines) do
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed:find('^%[') then
            local lowerHeader = trimmed:lower()
            if lowerHeader == '[mq2aaspend_aalist]' or lowerHeader == '[mq2aaspend_settings]' then
                inTargetSection = true
            else
                inTargetSection = false
                newLines[#newLines + 1] = line
            end
        elseif not inTargetSection then
            newLines[#newLines + 1] = line
        end
    end

    while #newLines > 0 and newLines[#newLines]:match('^%s*$') do
        table.remove(newLines)
    end

    if #newLines > 0 then newLines[#newLines + 1] = '' end
    for _, line in ipairs(section) do newLines[#newLines + 1] = line end

    local out = io.open(iniFile, 'w')
    if out then
        for _, line in ipairs(newLines) do
            out:write(line .. '\n')
        end
        out:close()
        AA.lastAASpendIniFingerprint = fingerprint
        if not silent then
            print(string.format('\ag[Triune]\ax Synced %d prioritized AAs to %s_%s.ini [MQ2AASpend_AAList].',
                #prioList, server, cleanName))
        end
        if AA.aaSpendLoaded and AA.aaSpendLoaded() then
            mq.cmd('/aaspend load')
        end
        return true, true
    end
    return false
end

function AA.checkAutoSpendAA(allowStop)
    if not ctrl.auto_spend_aa then return false end
    if AA.pendingAATrain then return false end

    -- Strict anti-pause check: never spend AAs while casting or moving
    if rt.isCasting() then return false end
    if not allowStop then
        local moving = false
        pcall(function()
            if mq.TLO.Me.Moving and mq.TLO.Me.Moving() then moving = true return end
            if rt.isMoveActive and rt.isMoveActive() then moving = true return end
            if mq.TLO.Navigation and mq.TLO.Navigation.Active and mq.TLO.Navigation.Active() then moving = true return end
        end)
        if moving then return false end
    end

    -- Strict out-of-combat enforcement: never spend AAs while engaged in combat to avoid pauses
    local inCombat = false
    pcall(function()
        if mq.TLO.Me.Combat and mq.TLO.Me.Combat() then inCombat = true return end
        if mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT' then inCombat = true return end
        if mq.TLO.Me.AutoFire and mq.TLO.Me.AutoFire() then inCombat = true return end
        if rt.isCombat and rt.isCombat() then inCombat = true return end
        if rt.anyXtarAlive and rt.anyXtarAlive(true) then inCombat = true return end
        if mq.TLO.Me.XTHaterCount and (mq.TLO.Me.XTHaterCount() or 0) > 0 then inCombat = true return end
    end)
    if inCombat then return false end

    local now = os.clock()
    if (now - (AA.lastAutoSpendAAAt or 0)) < 2.0 then return false end

    -- Reset unpurchasable skips if character level changed
    local myLevel = 0
    pcall(function() myLevel = tonumber(mq.TLO.Me.Level() or 0) or 0 end)
    if AA.lastCharLevel and myLevel > 0 and myLevel ~= AA.lastCharLevel then
        AA.lastAATrainAttempt = {}
        AA.trainBackoff = {}
        AA.trainFailLogged = {}
    end
    if myLevel > 0 then AA.lastCharLevel = myLevel end

    local unspent = 0
    pcall(function()
        local raw = mq.TLO.Me.AAPoints()
        unspent = tonumber(raw or 0) or 0
    end)
    -- Enforce minimum of 5 AA points before evaluating auto-spending to eliminate constant pauses
    if unspent < 5 then return false end

    -- Clear train attempt cooldowns if unspent points changed (e.g. gained points or purchased)
    if AA.lastObservedAutoSpendPts and unspent ~= AA.lastObservedAutoSpendPts then
        AA.lastAATrainAttempt = {}
    end
    AA.lastObservedAutoSpendPts = unspent

    -- Autoload MQ2AAspend plugin if missing and auto_spend is active
    if AA.aaSpendLoaded and not AA.aaSpendLoaded() then
        if not AA.lastAASpendAutoloadAttempt or (now - AA.lastAASpendAutoloadAttempt) > 15.0 then
            AA.lastAASpendAutoloadAttempt = now
            mq.cmd('/plugin mq2aaspend load')
        end
    end

    -- 1. Check prioritized AAs
    if ctrl.auto_aa_priorities and next(ctrl.auto_aa_priorities) then
        local candidates = {}
        for nm, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled then
                local lastAttempt = (AA.lastAATrainAttempt and AA.lastAATrainAttempt[nm]) or 0
                local backoff = (AA.trainBackoff and AA.trainBackoff[nm]) or 0
                if (now - lastAttempt) >= 30.0 and now >= backoff then
                    local rank, maxRank, cost = 0, 0, 0
                    local minLevel = 0
                    if rt.cachedAAData and rt.cachedAAData[nm] then
                        local cd = rt.cachedAAData[nm]
                        if cd.rank ~= nil then rank = cd.rank end
                        if cd.maxRank ~= nil and cd.maxRank > 0 then maxRank = cd.maxRank end
                        if cd.cost ~= nil and cd.cost > 0 then cost = cd.cost end
                        if cd.minLevel ~= nil and cd.minLevel > 0 then minLevel = cd.minLevel end
                    end
                    if (rank == 0 or maxRank == 0 or cost == 0) and AA.scannedAAMap then
                        local itm = AA.scannedAAMap[nm]
                        if itm then
                            if rank == 0 and itm.rank then rank = itm.rank end
                            if maxRank == 0 and itm.maxRank then maxRank = itm.maxRank end
                            if cost == 0 and itm.cost then cost = itm.cost end
                            if minLevel == 0 and itm.minLevel then minLevel = itm.minLevel end
                        end
                    end
                    pcall(function()
                        local ma = mq.TLO.Me.AltAbility(nm)
                        if ma and ma() then
                            if rank == 0 then rank = tonumber(ma.Rank and ma.Rank() or 0) or 0 end
                            if maxRank == 0 then maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0 end
                            if cost == 0 then cost = tonumber(ma.Cost and ma.Cost() or 0) or 0 end
                            if minLevel == 0 and ma.MinLevel then minLevel = tonumber(ma.MinLevel() or 0) or 0 end
                        end
                    end)
                    pcall(function()
                        if maxRank == 0 or cost == 0 or minLevel == 0 then
                            local ga = mq.TLO.AltAbility(nm)
                            if ga and ga() then
                                if maxRank == 0 then maxRank = tonumber(ga.MaxRank and ga.MaxRank() or 0) or 0 end
                                if cost == 0 then cost = tonumber(ga.Cost and ga.Cost() or 0) or 0 end
                                if minLevel == 0 and ga.MinLevel then minLevel = tonumber(ga.MinLevel() or 0) or 0 end
                            end
                        end
                    end)
                    local levelMet = (myLevel == 0 or minLevel == 0 or myLevel >= minLevel)
                    local canTrainCheck = true
                    pcall(function()
                        local ma = mq.TLO.Me.AltAbility(nm)
                        if ma and ma() and ma.CanTrain ~= nil then
                            if ma.CanTrain() == false then canTrainCheck = false end
                        else
                            local ga = mq.TLO.AltAbility(nm)
                            if ga and ga() and ga.CanTrain ~= nil then
                                if ga.CanTrain() == false then canTrainCheck = false end
                            end
                        end
                    end)

                    local isSpecial = (AA.isSpecialTabAA and AA.isSpecialTabAA(nm))
                    local fullyTrained = not isSpecial and (maxRank > 0 and rank >= maxRank)
                    local isInvalidStub = not isSpecial and (not maxRank or maxRank <= 0)
                    if isSpecial and cost <= 0 then
                        cost = tonumber(ctrl.auto_spend_aa_cost) or 25
                    end
                    if isSpecial and (not maxRank or maxRank <= 0) then
                        maxRank = 1
                    end
                    local canTrainMet = isSpecial or canTrainCheck
                    if not fullyTrained and not isInvalidStub and levelMet and canTrainMet then
                        if cost <= 0 then cost = AA.nextRankCost(nm, rank) end
                        if unspent >= cost then
                            candidates[#candidates + 1] = { name = nm, cost = cost, rank = rank, maxRank = maxRank }
                        end
                    end
                end
            end
        end

        if #candidates > 0 then
            -- Movement check: if moving and allowStop is true, cleanly stop movement before purchasing
            local moving = false
            pcall(function()
                if mq.TLO.Me.Moving and mq.TLO.Me.Moving() then moving = true return end
                if rt.isMoveActive and rt.isMoveActive() then moving = true return end
                if mq.TLO.Navigation and mq.TLO.Navigation.Active and mq.TLO.Navigation.Active() then moving = true return end
            end)
            if moving then
                if not allowStop then return false end
                if rt.stopMoving then rt.stopMoving() end
            end

            if ctrl.auto_aa_buy_order == 'list' then
                table.sort(candidates, function(a, b) return a.name:lower() < b.name:lower() end)
            else
                table.sort(candidates, function(a, b)
                    if a.cost ~= b.cost then return a.cost < b.cost end
                    return a.name:lower() < b.name:lower()
                end)
            end
            local target = candidates[1]

            -- If candidate is a Special tab ability (such as Fireworks), MQ2AAspend cannot purchase it.
            -- Train it directly via Triune's native window workflow!
            if AA.isSpecialTabAA and AA.isSpecialTabAA(target.name) then
                AA.lastAutoSpendAAAt = now
                print(string.format('\ag[Triune]\ax Auto-spending AA on Special tab ability "%s" (Rank %d/%d, Cost: %d AA, Unspent: %d AA)...',
                    target.name, target.rank, target.maxRank, target.cost, unspent))
                return AA.startAATrainWorkflow(target.name, allowStop)
            end

            -- For regular general/class abilities, if MQ2AAspend is active, delegate with native fallback:
            if ctrl.auto_aa_delegate_aaspend and AA.aaSpendLoaded and AA.aaSpendLoaded() then
                local threshold = AA.threshold()
                if unspent >= threshold then
                    local delegTarget = AA.lastAASpendDelegatedTarget
                    local delegAt = AA.lastAASpendDelegatedAt or 0
                    local delegPts = AA.lastAASpendDelegatedPoints or 0
                    if delegTarget == target.name and (now - delegAt) >= 2.5 and unspent >= delegPts then
                        AA.lastAutoSpendAAAt = now
                        AA.lastAASpendDelegatedTarget = nil
                        print(string.format('\ay[Triune]\ax MQ2AAspend did not purchase prioritized ability "%s" (unspent: %d AA); falling back to Triune native window trainer...',
                            target.name, unspent))
                        return AA.startAATrainWorkflow(target.name, allowStop)
                    end

                    AA.lastAutoSpendAAAt = now
                    AA.lastAASpendDelegatedAt = now
                    AA.lastAASpendDelegatedTarget = target.name
                    AA.lastAASpendDelegatedPoints = unspent
                    local mode = (ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'
                    mq.cmdf('/aaspend bank %d', threshold)
                    mq.cmd('/aaspend ' .. mode)
                    print(string.format('\ag[Triune]\ax Delegated Auto-Spend to MQ2AAspend (/aaspend %s, unspent: %d, bank: %d).',
                        mode, unspent, threshold))
                    return true
                end
                return false
            end

            -- Otherwise, train via Triune's native workflow
            AA.lastAutoSpendAAAt = now
            print(string.format('\ag[Triune]\ax Auto-spending AA on prioritized ability "%s" (Rank %d/%d, Cost: %d AA, Unspent: %d AA)...',
                target.name, target.rank, target.maxRank, target.cost, unspent))
            return AA.startAATrainWorkflow(target.name, allowStop)
        end
    end

    -- 2. Fallback: Cap threshold spender (Fireworks or general delegation)
    local threshold = AA.threshold()
    local cost = tonumber(ctrl.auto_spend_aa_cost) or 25
    local effectiveName = ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
    local isSpecialCap = (AA.isSpecialTabAA and AA.isSpecialTabAA(effectiveName)) or effectiveName:lower():find('firework')

    local lastCapAttempt = (AA.lastAATrainAttempt and AA.lastAATrainAttempt[effectiveName]) or 0
    local capBackoff = (AA.trainBackoff and AA.trainBackoff[effectiveName]) or 0
    local effectiveThreshold = threshold
    -- With no threshold ever set, a Fireworks cap spender may spend as soon
    -- as the points cover its cost; any saved threshold (100 included) is the
    -- user's choice and is honoured.
    if isSpecialCap and ctrl.auto_spend_aa_threshold == nil and unspent >= cost then
        effectiveThreshold = cost
    elseif isSpecialCap and unspent >= cost and unspent >= threshold then
        effectiveThreshold = threshold
    end
    if unspent >= effectiveThreshold and (now - lastCapAttempt) >= 30.0 and now >= capBackoff then
        -- Movement check: if moving and allowStop is true, cleanly stop movement before purchasing
        local moving = false
        pcall(function()
            if mq.TLO.Me.Moving and mq.TLO.Me.Moving() then moving = true return end
            if rt.isMoveActive and rt.isMoveActive() then moving = true return end
            if mq.TLO.Navigation and mq.TLO.Navigation.Active and mq.TLO.Navigation.Active() then moving = true return end
        end)
        if moving then
            if not allowStop then return false end
            if rt.stopMoving then rt.stopMoving() end
        end

        -- If user has Fireworks / Special tab ability configured as cap spender, buy it natively:
        if (AA.isSpecialTabAA and AA.isSpecialTabAA(effectiveName)) and unspent >= cost then
            AA.lastAutoSpendAAAt = now
            print(string.format('\ag[Triune]\ax Auto-spending AA cap protection on Special tab "%s" (Threshold: %d AA, Cost: %d AA, Unspent: %d AA)...',
                effectiveName, threshold, cost, unspent))
            return AA.startAATrainWorkflow(effectiveName, allowStop)
        end

        -- Delegation to MQ2AAspend plugin for cap dumping if loaded
        if ctrl.auto_aa_delegate_aaspend and AA.aaSpendLoaded and AA.aaSpendLoaded() then
            local delegCapAt = AA.lastAACapDelegatedAt or 0
            local delegCapPts = AA.lastAACapDelegatedPoints or 0
            local delegCapTarget = AA.lastAACapDelegatedTarget
            if delegCapTarget == effectiveName and (now - delegCapAt) >= 3.0 and unspent >= delegCapPts and cost > 0 and unspent >= cost then
                AA.lastAutoSpendAAAt = now
                AA.lastAACapDelegatedTarget = nil
                print(string.format('\ay[Triune]\ax MQ2AAspend did not spend cap protection points; falling back to Triune native trainer on "%s"...',
                    effectiveName))
                return AA.startAATrainWorkflow(effectiveName, allowStop)
            end

            AA.lastAutoSpendAAAt = now
            AA.lastAACapDelegatedAt = now
            AA.lastAACapDelegatedTarget = effectiveName
            AA.lastAACapDelegatedPoints = unspent
            local mode = (ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'
            mq.cmdf('/aaspend bank %d', threshold)
            mq.cmd('/aaspend ' .. mode)
            print(string.format('\ag[Triune]\ax Delegated Auto-Spend to MQ2AAspend (/aaspend %s, unspent: %d, bank: %d).',
                mode, unspent, threshold))
            return true
        end

        if cost > 0 and unspent >= cost then
            AA.lastAutoSpendAAAt = now
            print(string.format('\ag[Triune]\ax Auto-spending AA cap protection on "%s" (Threshold: %d AA, Cost: %d AA, Unspent: %d AA)...',
                effectiveName, threshold, cost, unspent))
            return AA.startAATrainWorkflow(effectiveName, allowStop)
        end
    end
    return false
end

function AA.manualSpendAA(targetName)
    -- If a specific ability is being trained, always train that specific ability natively!
    if targetName and targetName ~= '' then
        if AA.lastAATrainAttempt then AA.lastAATrainAttempt[targetName] = nil end
        AA.trainBackoff[targetName] = nil
        AA.trainFailLogged[targetName] = nil
        return AA.startAATrainWorkflow(targetName)
    end

    -- Generic spend clicked (e.g. from Spend Now button)
    AA.lastAATrainAttempt = {}
    AA.trainBackoff = {}
    AA.trainFailLogged = {}
    local unspent = 0
    pcall(function()
        local raw = mq.TLO.Me.AAPoints()
        unspent = tonumber(raw or 0) or 0
    end)

    -- Check prioritized abilities
    local topPrioritized = nil
    if ctrl.auto_aa_priorities and next(ctrl.auto_aa_priorities) then
        local candidates = {}
        for nm, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled then
                local rank, maxRank, cost = 0, 0, 0
                if rt.cachedAAData and rt.cachedAAData[nm] then
                    local cd = rt.cachedAAData[nm]
                    if cd.rank ~= nil then rank = cd.rank end
                    if cd.maxRank ~= nil and cd.maxRank > 0 then maxRank = cd.maxRank end
                    if cd.cost ~= nil and cd.cost > 0 then cost = cd.cost end
                end
                if (rank == 0 or maxRank == 0 or cost == 0) and AA.scannedAAMap then
                    local itm = AA.scannedAAMap[nm]
                    if itm then
                        if rank == 0 and itm.rank then rank = itm.rank end
                        if maxRank == 0 and itm.maxRank then maxRank = itm.maxRank end
                        if cost == 0 and itm.cost then cost = itm.cost end
                    end
                end
                pcall(function()
                    local ma = mq.TLO.Me.AltAbility(nm)
                    if ma and ma() then
                        if rank == 0 then rank = tonumber(ma.Rank and ma.Rank() or 0) or 0 end
                        if maxRank == 0 then maxRank = tonumber(ma.MaxRank and ma.MaxRank() or 0) or 0 end
                        if cost == 0 then cost = tonumber(ma.Cost and ma.Cost() or 0) or 0 end
                    end
                end)
                pcall(function()
                    if maxRank == 0 or cost == 0 then
                        local ga = mq.TLO.AltAbility(nm)
                        if ga and ga() then
                            if maxRank == 0 then maxRank = tonumber(ga.MaxRank and ga.MaxRank() or 0) or 0 end
                            if cost == 0 then cost = tonumber(ga.Cost and ga.Cost() or 0) or 0 end
                        end
                    end
                end)
                local isSpecial = (AA.isSpecialTabAA and AA.isSpecialTabAA(nm))
                local fullyTrained = not isSpecial and (maxRank > 0 and rank >= maxRank)
                if not fullyTrained then
                    if cost <= 0 then cost = AA.nextRankCost(nm, rank) end
                    if unspent >= cost then
                        candidates[#candidates + 1] = { name = nm, cost = cost, rank = rank, maxRank = maxRank }
                    end
                end
            end
        end

        if #candidates > 0 then
            if ctrl.auto_aa_buy_order == 'list' then
                table.sort(candidates, function(a, b) return a.name:lower() < b.name:lower() end)
            else
                table.sort(candidates, function(a, b)
                    if a.cost ~= b.cost then return a.cost < b.cost end
                    return a.name:lower() < b.name:lower()
                end)
            end
            topPrioritized = candidates[1]
        end
    end

    if topPrioritized then
        -- Special tab abilities always train natively
        if AA.isSpecialTabAA and AA.isSpecialTabAA(topPrioritized.name) then
            return AA.startAATrainWorkflow(topPrioritized.name)
        end

        -- If MQ2AAspend is active, try delegation first unless already delegated or disabled
        if ctrl.auto_aa_delegate_aaspend and AA.aaSpendLoaded and AA.aaSpendLoaded() then
            local threshold = AA.threshold()
            local now = os.clock()
            local delegTarget = AA.lastAASpendDelegatedTarget
            local delegAt = AA.lastAASpendDelegatedAt or 0
            local delegPts = AA.lastAASpendDelegatedPoints or 0
            -- If previously delegated for this target and didn't purchase after >= 2.5s, fall back immediately to native!
            if delegTarget == topPrioritized.name and (now - delegAt) >= 2.5 and unspent >= delegPts then
                AA.lastAASpendDelegatedTarget = nil
                print(string.format('\ay[Triune]\ax MQ2AAspend did not purchase prioritized ability "%s"; falling back to Triune native window trainer...',
                    topPrioritized.name))
                return AA.startAATrainWorkflow(topPrioritized.name)
            end

            local mode = (ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'
            AA.lastAASpendDelegatedAt = now
            AA.lastAASpendDelegatedTarget = topPrioritized.name
            AA.lastAASpendDelegatedPoints = unspent
            mq.cmdf('/aaspend bank %d', threshold)
            mq.cmd('/aaspend ' .. mode)
            print(string.format('\ag[Triune]\ax Issued MQ2AAspend manual command (/aaspend %s).', mode))
            return true
        end

        -- Native workflow
        return AA.startAATrainWorkflow(topPrioritized.name)
    end

    -- If Fireworks is configured cap spender and no other prios:
    local fallbackName = ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
    if AA.isSpecialTabAA and AA.isSpecialTabAA(fallbackName) and (not ctrl.auto_aa_priorities or not next(ctrl.auto_aa_priorities)) then
        return AA.startAATrainWorkflow(fallbackName)
    end

    if ctrl.auto_aa_delegate_aaspend and AA.aaSpendLoaded and AA.aaSpendLoaded() then
        local threshold = AA.threshold()
        local mode = (ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'
        mq.cmdf('/aaspend bank %d', threshold)
        mq.cmd('/aaspend ' .. mode)
        print(string.format('\ag[Triune]\ax Issued MQ2AAspend manual command (/aaspend %s).', mode))
        return true
    end

    local cost = 0
    if rt.cachedAAData and rt.cachedAAData[fallbackName] and rt.cachedAAData[fallbackName].cost then
        cost = tonumber(rt.cachedAAData[fallbackName].cost) or 0
    end
    if cost == 0 and AA.scannedAAMap then
        local itm = AA.scannedAAMap[fallbackName]
        if itm and itm.cost and itm.cost > 0 then cost = itm.cost end
    end
    if cost == 0 then
        pcall(function()
            local ma = mq.TLO.Me.AltAbility(fallbackName)
            if ma and ma() and ma.Cost then
                cost = tonumber(ma.Cost() or 0) or 0
            end
        end)
    end
    if cost == 0 then
        pcall(function()
            local ga = mq.TLO.AltAbility(fallbackName)
            if ga and ga() and ga.Cost then
                cost = tonumber(ga.Cost() or 0) or 0
            end
        end)
    end
    if cost == 0 then
        if not targetName or targetName == '' or targetName:lower():find('firework') then
            cost = tonumber(ctrl.auto_spend_aa_cost) or 25
        else
            cost = 1
        end
    end

    if unspent < cost then
        print(string.format('\ay[Triune]\ax Cannot purchase %s: have %d unspent AA, need %d AA.', fallbackName, unspent, cost))
        return false
    end

    return AA.startAATrainWorkflow(fallbackName)
end

-- True only once the character has actually purchased a rank of the fireworks
-- AA (by the configured cap-spender name, the summon hotkey name, or the AA
-- id). Me.AltAbility only carries a positive Rank for trained abilities, and
-- AltAbilityReady is only ever true for owned ones, so either is proof of
-- ownership. Without this the auto-summon spammed /alt act every 3s on
-- characters that had not bought the AA yet.
function AA.hasFireworksAA(aaId)
    local owned = false
    pcall(function()
        local keys = { ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks', 'Alternately Advanced Fireworks', 'Summon Firework' }
        if aaId and aaId > 0 then keys[#keys + 1] = aaId end
        for _, key in ipairs(keys) do
            local ma = mq.TLO.Me.AltAbility(key)
            if ma and ma() then
                local r = tonumber(ma.Rank and ma.Rank() or 0) or 0
                if r > 0 then owned = true return end
            end
            local ready = mq.TLO.Me.AltAbilityReady and mq.TLO.Me.AltAbilityReady(key)
            if ready and ready() == true then owned = true return end
        end
    end)
    return owned
end

-- Deferred post-purchase summon. Fires /alt act once the configured delay has
-- passed (ctrl.auto_summon_delay_sec, default 3s), the character is idle, and
-- Me.AltAbility confirms the rank landed; retries a few times on the same
-- cadence if the client has not caught up yet.
AA.FIREWORKS_SUMMON_DEFAULT_DELAY = 3.0
AA.FIREWORKS_SUMMON_MAX_TRIES = 5

function AA.fireworksSummonDelay()
    local d = tonumber(ctrl.auto_summon_delay_sec)
    if not d or d < 0.5 then d = AA.FIREWORKS_SUMMON_DEFAULT_DELAY end
    return d
end

function AA.scheduleFireworksSummon(fwId, reason)
    local delay = AA.fireworksSummonDelay()
    AA.pendingFireworksSummon = { id = tonumber(fwId) or 17788, at = os.clock() + delay, tries = 0, reason = reason }
    AA.lastAutoSummonAt = os.clock() -- keep the periodic auto-summon from racing this one
    print(string.format('\ag[Triune]\ax Fireworks summon scheduled in %.1fs (/alt act %d) after purchasing "%s".',
        delay, AA.pendingFireworksSummon.id, tostring(reason or 'fireworks AA')))
end

function AA.processPendingFireworksSummon()
    local job = AA.pendingFireworksSummon
    if not job then return false end
    local now = os.clock()
    if now < (job.at or 0) then return false end
    -- Wait for an idle moment; the schedule simply slides while busy.
    if rt.isCasting() or mq.TLO.Me.Dead() or mq.TLO.Me.Combat() or mq.TLO.Me.Moving() then return false end
    if AA.hasFireworksAA(job.id) then
        AA.pendingFireworksSummon = nil
        AA.lastAutoSummonAt = now
        mq.cmdf('/alt act %d', job.id)
        rt.pendingCursorClearAt = now + 0.4
        print(string.format('\ag[Triune]\ax Summoning fireworks (/alt act %d).', job.id))
        return true
    end
    job.tries = (job.tries or 0) + 1
    if job.tries >= AA.FIREWORKS_SUMMON_MAX_TRIES then
        AA.pendingFireworksSummon = nil
        print(string.format('\ay[Triune]\ax Fireworks AA still not reported as purchased after %d checks; skipping the post-purchase summon.', job.tries))
        return false
    end
    job.at = now + AA.fireworksSummonDelay()
    return false
end

function AA.checkAutoSummonFireworks()
    if not ctrl.auto_summon_fireworks then return false end
    if AA.pendingFireworksSummon then return false end
    local now = os.clock()
    if (now - (AA.lastAutoSummonAt or 0)) < math.max(3.0, AA.fireworksSummonDelay()) then return false end

    if rt.isCasting() then return false end
    if mq.TLO.Me.Dead() or mq.TLO.Me.Combat() then return false end
    if rt.anyXtarAlive and rt.anyXtarAlive(true) then return false end

    local aaId = tonumber(ctrl.auto_spend_aa_id) or 17788
    if aaId <= 0 then return false end

    -- Never try to summon before the AA has been bought (nothing to activate).
    if not AA.hasFireworksAA(aaId) then
        AA.lastAutoSummonAt = now -- re-check on the normal 3s cadence, no spam
        return false
    end

    -- Check if timer is on active cooldown (only block if EQ explicitly reports a positive cooldown timer)
    local coolingDown = false
    pcall(function()
        local t1 = mq.TLO.Me.AltAbilityTimer('Summon Firework')
        if t1 and tonumber(t1() or 0) and tonumber(t1() or 0) > 0 then coolingDown = true return end
        local t2 = mq.TLO.Me.AltAbilityTimer('Alternately Advanced Fireworks')
        if t2 and tonumber(t2() or 0) and tonumber(t2() or 0) > 0 then coolingDown = true return end
        local t3 = mq.TLO.Me.AltAbilityTimer(aaId)
        if t3 and tonumber(t3() or 0) and tonumber(t3() or 0) > 0 then coolingDown = true return end
    end)
    if coolingDown then return false end

    AA.lastAutoSummonAt = now
    mq.cmdf('/alt act %d', aaId)
    print(string.format('\ag[Triune]\ax Auto-summoning fireworks via /alt act %d.', aaId))
    rt.pendingCursorClearAt = os.clock() + 0.4
    return true
end

function AA.manualSummonFireworks()
    local aaId = tonumber(ctrl.auto_spend_aa_id) or 17788
    if not AA.hasFireworksAA(aaId) then
        print(string.format('\ay[Triune]\ax Cannot summon fireworks: the "%s" AA has not been purchased yet.', ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'))
        return false
    end
    mq.cmdf('/alt act %d', aaId)
    print(string.format('\ag[Triune]\ax Summoning fireworks via /alt act %d (Summon Firework)...', aaId))
    rt.pendingCursorClearAt = os.clock() + 0.4
    return true
end


-- ----------------------------------------------------------------------------
-- Auto AA popout window (was a main-window tab)
-- ----------------------------------------------------------------------------
-- UI: Auto AA / Point Spender & AA Progression window
function AA.drawWindow()
    if not ctrl.show_auto_aa then return end
    core.pushTheme()
    ImGui.SetNextWindowSize(core.px(760), core.px(560), ImGuiCond.FirstUseEver)
    core.preBeginWindow('auto_aa')
    local open, show = ImGui.Begin('Triune Auto AA v' .. (core.VERSION or '') .. '###triuneAutoAA', ctrl.show_auto_aa)
    if not open then
        ctrl.show_auto_aa = false
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not show then
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('auto_aa')

    local unspentAA = 0
    local spentAA = 0
    local totalAA = 0
    pcall(function()
        unspentAA = tonumber(mq.TLO.Me.AAPoints() or 0) or 0
        spentAA = tonumber(mq.TLO.Me.AAPointsSpent() or 0) or 0
        totalAA = tonumber(mq.TLO.Me.AAPointsTotal() or 0) or (unspentAA + spentAA)
    end)

    if AA.lastObservedAAPointsSpent ~= nil and spentAA ~= AA.lastObservedAAPointsSpent then
        AA.lastObservedAAPointsSpent = spentAA
        AA.aaFilterDirty = true
        AA.requestScan(1.0)
    else
        AA.lastObservedAAPointsSpent = spentAA
    end

    if AA.lastObservedAAPoints ~= nil and unspentAA ~= AA.lastObservedAAPoints then
        AA.lastObservedAAPoints = unspentAA
        AA.aaFilterDirty = true
    else
        AA.lastObservedAAPoints = unspentAA
    end

    accent(GOLD, 'Alternate Advancement (AA) Progression & Auto-Training')

    -- Compact Row 1: Live AA Pool Status & Master Automation Controls
    ImGui.Text('Unspent:')
    ImGui.SameLine()
    if unspentAA >= 100 then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('%d/100 [CAP!]', unspentAA))
    elseif unspentAA >= AA.threshold() then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('%d [THRESHOLD]', unspentAA))
    else
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('%d AA', unspentAA))
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', string.format('Unspent: %d AA\nSpent: %d AA\nTotal: %d AA', unspentAA, spentAA, totalAA))
    end

    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(Spent: %d)', spentAA))

    ImGui.SameLine()
    ImGui.TextDisabled('|')
    ImGui.SameLine()

    local spendVal = ImGui.Checkbox('Auto-Spend AA##aaAutoSpendMaster', ctrl.auto_spend_aa or false)
    if spendVal ~= (ctrl.auto_spend_aa or false) then
        ctrl.auto_spend_aa = spendVal
        if spendVal then
            if AA.aaSpendLoaded and not AA.aaSpendLoaded() then
                mq.cmd('/plugin mq2aaspend load')
            end
            if AA.syncAAsToMQ2AASpendIni then
                AA.syncAAsToMQ2AASpendIni(true)
            end
        end
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically purchases prioritized Alternate Advancements via MQ2AAspend in the background as points are earned.')
    end

    ImGui.SameLine()
    local aaSpendAvail = AA.aaSpendLoaded and AA.aaSpendLoaded()
    if aaSpendAvail then
        local delVal = ImGui.Checkbox('MQ2AAspend##aaDelegateMaster', ctrl.auto_aa_delegate_aaspend ~= false)
        if delVal ~= (ctrl.auto_aa_delegate_aaspend ~= false) then
            ctrl.auto_aa_delegate_aaspend = delVal
            if delVal and AA.syncAAsToMQ2AASpendIni then
                AA.syncAAsToMQ2AASpendIni(true)
            end
            core.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s', 'Delegate AA purchasing to MQ2AAspend plugin.\n• Checked: MQ2AAspend attempts purchases first; Triune automatically falls back to native window training if MQ2AAspend fails.\n• Unchecked: Triune trains all prioritized AAs directly via native window training.')
        end
    else
        if ImGui.SmallButton('Load MQ2AAspend##btnLoadAASpend') then
            mq.cmd('/plugin mq2aaspend load')
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s', 'MQ2AAspend is not loaded. Click to execute /plugin mq2aaspend load.\n(Triune trains AAs natively using its built-in window trainer when MQ2AAspend is not loaded).')
        end
    end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(90))
    local curThresh = AA.threshold()
    local newThresh = ImGui.SliderInt('##autoAaThresh', curThresh, 5, 100, 'Bank: %d')
    if newThresh ~= curThresh then
        ctrl.auto_spend_aa_threshold = newThresh
    end
    if ImGui.IsItemDeactivatedAfterEdit() then core.saveLoadout(true) end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', string.format('Reserve/Bank Threshold: %d AA points (min: 5).\nAuto-spending begins once your unspent points reach this number.', curThresh))
    end

    ImGui.SameLine()
    if ImGui.Button('Spend Now##btnAASpendNow') then
        if AA.manualSpendAA then AA.manualSpendAA() end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Manually trigger an immediate purchase of prioritized AAs right now.')
    end

    ImGui.SameLine()
    if ImGui.Button('Sync to INI##btnSyncIni') then
        if AA.syncAAsToMQ2AASpendIni then
            AA.syncAAsToMQ2AASpendIni(false, true)
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Manually syncs prioritized AAs to Server_Character.ini [MQ2AASpend_AAList] and reloads the plugin.\n(Note: Triune also syncs this automatically in the background!)')
    end

    ImGui.SameLine()
    if ImGui.Button('↻ Refresh##autoAaRefreshBtn') then
        AA.specialTabReadDone = false
        AA.pendingReadSpecialTab = true
        AA.requestScan(0)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Re-scans all character Alternate Advancement abilities (runs in the background).')
    end
    if AA.scanning or AA.scanRequestAt then
        ImGui.SameLine()
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'scanning...')
    end

    ImGui.SameLine()
    if ImGui.Button('Clear Prios##autoAaClearPrioBtn') then
        ctrl.auto_aa_priorities = {}
        AA.aaFilterDirty = true
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Unchecks all prioritized abilities.')
    end

    ImGui.Separator()

    -- Compact Row 2: Search, Sort & View Filter Toggles
    local allItems = AA.getFilteredSortedAAs and AA.getFilteredSortedAAs() or {}
    local prioCount = 0
    if ctrl.auto_aa_priorities then
        for _, enabled in pairs(ctrl.auto_aa_priorities) do
            if enabled then prioCount = prioCount + 1 end
        end
    end

    ImGui.SetNextItemWidth(core.px(130))
    local curSearch = ctrl.auto_aa_search or ''
    local newSearch = ImGui.InputTextWithHint('##autoAaSearchBox', 'Search AAs...', curSearch, 64)
    if newSearch ~= curSearch then
        ctrl.auto_aa_search = newSearch
        AA.aaFilterDirty = true
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Filter abilities by name in real-time.')
    end

    ImGui.SameLine()
    if ImGui.Button('X##clearAaSearch') then
        ctrl.auto_aa_search = ''
        AA.aaFilterDirty = true
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Clear search text.')
    end

    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(105))
    local sortNames = { 'Name', 'Cost', 'Trained' }
    local sortKeys = { 'name', 'cost', 'trained' }
    local curSortIdx = 1
    for idx, sk in ipairs(sortKeys) do
        if ctrl.auto_aa_sort_by == sk then curSortIdx = idx; break end
    end
    local newSortIdx = ImGui.Combo('##autoAaSortCombo', curSortIdx, sortNames)
    if newSortIdx ~= curSortIdx then
        ctrl.auto_aa_sort_by = sortKeys[newSortIdx]
        AA.aaFilterDirty = true
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Sort by ability name, point cost to buy next rank, or training status.')
    end

    ImGui.SameLine()
    local isAsc = (ctrl.auto_aa_sort_asc ~= false)
    local dirBtnText = isAsc and '▲ Asc' or '▼ Desc'
    if ImGui.Button(dirBtnText .. '##autoAaSortDir') then
        ctrl.auto_aa_sort_asc = not isAsc
        AA.aaFilterDirty = true
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Toggle sort direction: Ascending vs Descending.')
    end

    ImGui.SameLine()
    local hideVal = ImGui.Checkbox('Hide Maxed##autoAaHideMax', ctrl.auto_aa_hide_maxed or false)
    if hideVal ~= (ctrl.auto_aa_hide_maxed or false) then
        ctrl.auto_aa_hide_maxed = hideVal
        AA.aaFilterDirty = true
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Hide abilities that have reached maximum rank.')
    end

    ImGui.SameLine()
    local prioOnlyVal = ImGui.Checkbox('Prio Only##autoAaPrioOnly', ctrl.auto_aa_only_prioritized or false)
    if prioOnlyVal ~= (ctrl.auto_aa_only_prioritized or false) then
        ctrl.auto_aa_only_prioritized = prioOnlyVal
        AA.aaFilterDirty = true
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Show only AAs that are checked for priority auto-purchase.')
    end

    ImGui.SameLine()
    ImGui.TextDisabled(string.format('(%d listed | %d prio)', #allItems, prioCount))

    -- 3. Scrollable Table (Dynamically Sized to Window)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4, 2)
    local childFlags = bit.bor(ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0)
    local tableChildOpen = ImGui.BeginChild('auto_aa_table_scroll', 0, 0, false, childFlags)
    if tableChildOpen then
        local tableFlags = bit.bor(
            ImGuiTableFlags.RowBg,
            ImGuiTableFlags.Borders,
            ImGuiTableFlags.Resizable,
            ImGuiTableFlags.SizingStretchProp
        )
        if ImGui.BeginTable('##AutoAABrowserTable', 6, tableFlags) then
            ImGui.TableSetupColumn('Prio', ImGuiTableColumnFlags.WidthFixed, core.px(32))
            ImGui.TableSetupColumn('Ability Name', ImGuiTableColumnFlags.WidthStretch, 200)
            ImGui.TableSetupColumn('Rank', ImGuiTableColumnFlags.WidthFixed, core.px(55))
            ImGui.TableSetupColumn('Cost', ImGuiTableColumnFlags.WidthFixed, core.px(55))
            ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, core.px(95))
            ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, core.px(55))
            ImGui.TableHeadersRow()

            -- Per-row strings are formatted once per scan (the entries are
            -- rebuilt by every scan); only the rows the clipper shows draw.
            local function drawRow(i, itm)
                ImGui.TableNextRow()
                ImGui.PushID(i)
                local ui = itm.ui
                if not ui then
                    ui = {
                        rank = (itm.maxRank and itm.maxRank > 0) and string.format('%d/%d', itm.rank, itm.maxRank) or string.format('%d/?', itm.rank),
                        cost = (itm.cost and itm.cost > 0) and string.format('%d AA', itm.cost) or '-',
                        prioTip = string.format('Prioritize "%s" for automatic training when points are available.', itm.name),
                        trainTip = string.format('Click to train next rank of "%s" (%d AA).', itm.name, itm.cost or 0),
                    }
                    itm.ui = ui
                end

                -- Col 1: Priority Checkbox
                ImGui.TableNextColumn()
                local isPrio = not not (ctrl.auto_aa_priorities and ctrl.auto_aa_priorities[itm.name])
                local newPrio = ImGui.Checkbox('##prioCheck', isPrio)
                if newPrio ~= isPrio then
                    if not ctrl.auto_aa_priorities then ctrl.auto_aa_priorities = {} end
                    ctrl.auto_aa_priorities[itm.name] = newPrio and true or nil
                    AA.aaFilterDirty = true
                    core.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', ui.prioTip)
                end

                -- Col 2: Ability Name
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], itm.name)
                else
                    ImGui.Text(itm.name)
                end
                if ImGui.IsItemHovered() then
                    rt.showAATooltip(itm)
                end

                -- Col 3: Rank
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], ui.rank)
                elseif itm.maxRank and itm.maxRank > 0 then
                    ImGui.Text(ui.rank)
                else
                    ImGui.TextDisabled(ui.rank)
                end
                if ImGui.IsItemHovered() then
                    rt.showAATooltip(itm)
                end

                -- Col 4: Cost
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextDisabled('-')
                elseif itm.cost and itm.cost > 0 then
                    if unspentAA >= itm.cost then
                        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], ui.cost)
                    else
                        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], ui.cost)
                    end
                else
                    ImGui.TextDisabled('-')
                end

                -- Col 5: Status
                ImGui.TableNextColumn()
                if itm.fullyTrained then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Max Rank')
                elseif itm.cost and itm.cost > 0 and unspentAA >= itm.cost then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Can Train')
                elseif itm.cost and itm.cost > 0 then
                    ImGui.TextDisabled(string.format('Need %d AA', itm.cost - unspentAA))
                elseif itm.rank > 0 then
                    ImGui.TextDisabled('In Progress')
                else
                    ImGui.TextDisabled('Untrained')
                end

                -- Col 6: Action (Train button)
                ImGui.TableNextColumn()
                if not itm.fullyTrained and itm.cost > 0 then
                    local canAfford = (unspentAA >= itm.cost)
                    if not canAfford then ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5) end
                    if ImGui.Button('Train##btn') then
                        if AA.manualSpendAA then AA.manualSpendAA(itm.name) end
                    end
                    if not canAfford then ImGui.PopStyleVar() end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', ui.trainTip)
                    end
                else
                    ImGui.TextDisabled('---')
                end

                ImGui.PopID()
            end

            local clipper = nil
            local ClipperClass = ImGui.ListClipper or (mq.imgui and mq.imgui.ListClipper) or _G['ImGuiListClipper']
            if type(ClipperClass) == 'table' and ClipperClass.new then
                local okC, c = pcall(ClipperClass.new)
                if okC and c then clipper = c end
            end
            if clipper then
                clipper:Begin(#allItems)
                while clipper:Step() do
                    for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                        local itm = allItems[i]
                        if itm then drawRow(i, itm) end
                    end
                end
                clipper:End()
            else
                for i, itm in ipairs(allItems) do drawRow(i, itm) end
            end

            ImGui.EndTable()
        end

        -- 4. Fireworks & Utility Actions Collapsible Section
        ImGui.Spacing()
        if ImGui.CollapsingHeader('Fireworks Spender & Utility Actions##autoAaFwHeader', false) then
            ImGui.Indent(10)
            local curName = ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'
            local curId = ctrl.auto_spend_aa_id or 17788

            local summonVal = ImGui.Checkbox('Enable Auto-Summon Fireworks (/alt act)', ctrl.auto_summon_fireworks or false)
            if summonVal ~= (ctrl.auto_summon_fireworks or false) then
                ctrl.auto_summon_fireworks = summonVal
                core.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'When ready (out of combat & stationary) and once the fireworks AA has been purchased, automatically activates it\n(/alt act 17788 or Summon Firework) and clears the cursor into inventory via /autoinventory.')
            end
            ImGui.SameLine()
            ImGui.PushItemWidth(140)
            local curDelay = AA.fireworksSummonDelay()
            local newDelay = ImGui.SliderFloat('Summon delay (s)##fwSummonDelay', curDelay, 0.5, 15.0, '%.1f')
            ImGui.PopItemWidth()
            if newDelay and math.abs(newDelay - curDelay) > 0.01 then
                ctrl.auto_summon_delay_sec = newDelay
            end
            if ImGui.IsItemDeactivatedAfterEdit() then core.saveLoadout(true) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'How long to wait after buying the fireworks AA before /alt act is issued (the purchase must reach the server first).\nAlso the minimum spacing between automatic summons. Default 3s.')
            end

            ImGui.SameLine()
            local summonLabel = string.format('Summon Fireworks (/alt act %d)##manualSummonBtn', curId)
            if ImGui.Button(summonLabel) then
                if AA.manualSummonFireworks then AA.manualSummonFireworks() end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', string.format('Manually triggers /alt act %d (Summon Firework) to summon fireworks and puts them into your inventory.', curId))
            end

            ImGui.SameLine()
            if ImGui.Button('Clear Cursor (/autoinv)##clearCursorAutoAaBtn') then
                rt.pendingCursorClearAt = os.clock()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'Clears any item currently on cursor into your inventory bags.')
            end

            ImGui.SetNextItemWidth(core.px(260))
            local newName = ImGui.InputText('Cap Spender AA Name##autoAaCapName', curName, 128)
            if newName and newName ~= curName and newName ~= '' then
                ctrl.auto_spend_aa_name = newName
            end
            if ImGui.IsItemDeactivatedAfterEdit() then core.saveLoadout(true) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'The fallback AA Ability name used for point dumping when cap is reached (e.g. Alternately Advanced Fireworks).')
            end

            ImGui.SameLine()
            ImGui.SetNextItemWidth(core.px(120))
            local newId = ImGui.InputInt('Activation ID##autoAaActId', curId)
            if newId ~= curId and newId > 0 then
                ctrl.auto_spend_aa_id = newId
            end
            if ImGui.IsItemDeactivatedAfterEdit() then core.saveLoadout(true) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', 'The Spell / Ability ID used for fireworks summoning (default: 17788, hotkey: Summon Firework).')
            end
            ImGui.Unindent(10)
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(2)

    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Per-tick driver (was inline in the core main loop)
-- ----------------------------------------------------------------------------
function AA.tick()
    ctrl = core.ctrl
    rt = core.runtime
    if AA.pendingAATrain and AA.processAATrainWorkflow then
        AA.processAATrainWorkflow()
    end
    if AA.pendingPostTrainScanAt and os.clock() >= AA.pendingPostTrainScanAt then
        AA.pendingPostTrainScanAt = nil
        AA.requestScan(0)
    end
    if AA.pendingReadSpecialTab then
        if not ctrl.paused and ctrl.auto_spend_aa and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() and not rt.isCasting() then
            AA.pendingReadSpecialTab = false
            if AA.readSpecialTabOnce then AA.readSpecialTabOnce(false) end
            AA.requestScan(0)
        elseif not ctrl.auto_spend_aa or ctrl.paused then
            AA.pendingReadSpecialTab = false
        end
    end
    local currentSpentAA = nil
    pcall(function() currentSpentAA = tonumber(mq.TLO.Me.AAPointsSpent() or 0) or 0 end)
    if currentSpentAA and AA.lastObservedAAPointsSpent ~= nil and currentSpentAA ~= AA.lastObservedAAPointsSpent then
        AA.lastObservedAAPointsSpent = currentSpentAA
        AA.aaFilterDirty = true
        AA.requestScan(1.0)
    end
    -- The one place a scan actually runs (window refresh, purchases, the
    -- purchase event and the spent-points change all queue through here).
    AA.runPendingScan()
    if ctrl.auto_spend_aa and AA.checkAutoSpendAA and not rt.isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() then
        AA.checkAutoSpendAA()
    end
    if AA.pendingFireworksSummon then
        AA.processPendingFireworksSummon()
    end
    if ctrl.auto_summon_fireworks and AA.checkAutoSummonFireworks and not rt.isCasting() and not mq.TLO.Me.Combat() and not mq.TLO.Me.Moving() then
        AA.checkAutoSummonFireworks()
    end
end

-- ----------------------------------------------------------------------------
-- /ac commands
-- ----------------------------------------------------------------------------
function AA.onCommand(cmd, args)
    ctrl = core.ctrl
    if cmd == 'aawin' or cmd == 'aaui' or cmd == 'autoaawin' then
        ctrl.show_auto_aa = not ctrl.show_auto_aa
        core.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Auto AA window %s.', ctrl.show_auto_aa and 'OPENED' or 'CLOSED'))
        return true
    elseif cmd == 'autoaa' or cmd == 'autospendaa' or cmd == 'autospend' or cmd == 'fireworks' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.auto_spend_aa = true
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.auto_spend_aa = false
        else
            ctrl.auto_spend_aa = not ctrl.auto_spend_aa
        end
        core.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Auto-Spend AA Points %s (Threshold: %d AA, Cost: %d AA, ID: %d).',
            ctrl.auto_spend_aa and '\agENABLED\ax' or '\arDISABLED\ax',
            AA.threshold(), ctrl.auto_spend_aa_cost or 25, ctrl.auto_spend_aa_id or 17788))
    elseif cmd == 'autofw' or cmd == 'summonfw' or cmd == 'auto_summon_fireworks' or cmd == 'autofireworks' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.auto_summon_fireworks = true
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.auto_summon_fireworks = false
        else
            ctrl.auto_summon_fireworks = not ctrl.auto_summon_fireworks
        end
        core.saveLoadout(true)
        print(string.format('\ag[Triune]\ax Auto-Summon Fireworks %s (/alt act %d / Summon Firework).',
            ctrl.auto_summon_fireworks and '\agENABLED\ax' or '\arDISABLED\ax', ctrl.auto_spend_aa_id or 17788))
    elseif cmd == 'aaspend' or cmd == 'mq2aaspend' then
        local sub = args[2] and string.lower(args[2]) or ''
        if sub == 'on' or sub == '1' or sub == 'enable' then
            ctrl.auto_aa_delegate_aaspend = true
            core.saveLoadout(true)
            print('\ag[Triune]\ax Delegated AA spending to MQ2AAspend \agENABLED\ax.')
        elseif sub == 'off' or sub == '0' or sub == 'disable' then
            ctrl.auto_aa_delegate_aaspend = false
            core.saveLoadout(true)
            print('\ag[Triune]\ax Delegated AA spending to MQ2AAspend \arDISABLED\ax.')
        elseif sub == 'auto' or sub == 'brute' then
            ctrl.auto_aa_aaspend_mode = sub
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax MQ2AAspend Mode set to: %s.', sub))
        elseif sub == 'sync' or sub == 'inisync' then
            if AA.syncAAsToMQ2AASpendIni then
                AA.syncAAsToMQ2AASpendIni(false, true)
            end
        elseif sub == 'now' then
            if AA.aaSpendLoaded and AA.aaSpendLoaded() then
                mq.cmdf('/aaspend bank %d', AA.threshold())
                mq.cmd('/aaspend ' .. ((ctrl.auto_aa_aaspend_mode == 'brute') and 'brute now' or 'auto now'))
                print(string.format('\ag[Triune]\ax Triggered: /aaspend %s now', ctrl.auto_aa_aaspend_mode or 'auto'))
            else
                print('\ar[Triune]\ax MQ2AAspend is not loaded. Type /plugin mq2aaspend load.')
            end
        else
            ctrl.auto_aa_delegate_aaspend = not ctrl.auto_aa_delegate_aaspend
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Delegated AA spending to MQ2AAspend: %s.',
                ctrl.auto_aa_delegate_aaspend and '\agENABLED\ax' or '\arDISABLED\ax'))
        end
    elseif cmd == 'aatrain' or cmd == 'trainwindow' or cmd == 'trainaa' or cmd == 'spendnow' or cmd == 'spendaa' or cmd == 'spendpoints' then
        if AA.manualSpendAA then AA.manualSpendAA() end
    elseif cmd == 'summonnow' or cmd == 'summonfireworks' then
        if AA.manualSummonFireworks then AA.manualSummonFireworks() end
    elseif cmd == 'aathreshold' or cmd == 'spendthreshold' or cmd == 'aathresh' then
        local val = tonumber(args[2])
        if val then
            ctrl.auto_spend_aa_threshold = math.max(1, math.min(500, math.floor(val)))
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Trigger Threshold set to %d AA.', ctrl.auto_spend_aa_threshold))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Threshold: %d AA. (usage: /ac aathreshold [25-100])', AA.threshold()))
        end
    elseif cmd == 'aacost' or cmd == 'spendcost' then
        local val = tonumber(args[2])
        if val then
            ctrl.auto_spend_aa_cost = math.max(1, math.min(500, math.floor(val)))
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Cost Per Rank set to %d AA.', ctrl.auto_spend_aa_cost))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Cost: %d AA. (usage: /ac aacost [1-50])', ctrl.auto_spend_aa_cost or 25))
        end
    elseif cmd == 'aaid' or cmd == 'spendaaid' then
        local val = tonumber(args[2])
        if val and val > 0 then
            ctrl.auto_spend_aa_id = math.floor(val)
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend Activation Spell ID set to %d.', ctrl.auto_spend_aa_id))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend Activation ID: %d. (usage: /ac aaid [id])', ctrl.auto_spend_aa_id or 17788))
        end
    elseif cmd == 'aaname' or cmd == 'setaaname' then
        local newName = table.concat(args, ' ', 2)
        if newName and newName ~= '' then
            ctrl.auto_spend_aa_name = newName
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax Auto-Spend AA Ability Name set to "%s".', ctrl.auto_spend_aa_name))
        else
            print(string.format('\ag[Triune]\ax Current Auto-Spend AA Ability Name: "%s". (usage: /ac aaname [name])', ctrl.auto_spend_aa_name or 'Alternately Advanced Fireworks'))
        end
    elseif cmd == 'aascan' or cmd == 'scanaa' or cmd == 'aarefresh' then
        AA.specialTabReadDone = false
        AA.pendingReadSpecialTab = true
        if AA.scanPlayerAAs then
            AA.scanPlayerAAs(true)
            local count = AA.scannedAAs and #AA.scannedAAs or 0
            print(string.format('\ag[Triune]\ax Scanned character Alternate Advancements: %d abilities found.', count))
        end
    elseif cmd == 'aaprio' or cmd == 'prioritizeaa' then
        local aaName = table.concat(args, ' ', 2)
        if aaName and aaName ~= '' then
            if not ctrl.auto_aa_priorities then ctrl.auto_aa_priorities = {} end
            ctrl.auto_aa_priorities[aaName] = not ctrl.auto_aa_priorities[aaName]
            AA.aaFilterDirty = true
            core.saveLoadout(true)
            print(string.format('\ag[Triune]\ax AA priority for "%s" set to %s.',
                aaName, ctrl.auto_aa_priorities[aaName] and '\agENABLED\ax' or '\arDISABLED\ax'))
        else
            print('\ag[Triune]\ax usage: /ac aaprio <Ability Name>')
        end
    else
        return false
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle & hooks
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    rt = core.runtime
    mq = core.mq
    ImGui = core.ImGui
    ctrl = core.ctrl
    DATA = core.DATA
    accent = core.accent
    local colors = core.colors or {}
    GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    GOOD = colors.GOOD or { 0.37, 0.88, 0.64, 1 }
    WARN = colors.WARN or { 1.0, 0.72, 0.30, 1 }
    ERR  = colors.ERR  or { 0.95, 0.35, 0.35, 1 }
    resetState()
    if ctrl and ctrl.show_auto_aa == nil then ctrl.show_auto_aa = false end
    if rt and not rt.cachedAAData then rt.cachedAAData = {} end

    if not (mq and mq.event) then return end
    local function reg(name, pattern, handler)
        if mq.unevent then pcall(mq.unevent, name) end
        mq.event(name, pattern, handler)
        table.insert(registeredEvents, name)
    end
    local function onPurchased()
        -- folds into the scan the Train workflow already queued
        AA.aaFilterDirty = true
        AA.requestScan(1.0)
    end
    reg('TacAAPurchased1', '#*#You have purchased #*#', onPurchased)
    reg('TacAAPurchased2', '#*#You have improved #*#', onPurchased)
    reg('TacAAPurchased3', '#*#You have mastered #*#', onPurchased)
end

function plugin.onDestroy()
    if mq and mq.unevent then
        for _, name in ipairs(registeredEvents) do pcall(mq.unevent, name) end
    end
    registeredEvents = {}
    if AA.pendingAATrain then AA.abortAATrain(AA.pendingAATrain) end
    resetState()
end

function plugin.onTick()
    if not core then return end
    AA.tick()
end

-- Popout window (toggled by the header button, /ac aawin, or the Window Layout manager)
function plugin.onDrawUI()
    if not core then return end
    ctrl = core.ctrl
    rt = core.runtime
    AA.drawWindow()
end

function plugin.onDrawSettings()
    if not core or not ImGui then return end
    ctrl = core.ctrl
    accent(GOLD, 'Auto AA Spender')
    local isWinOpen = (ctrl.show_auto_aa == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##aaToggleWin', core.px(250), core.px(24)) then
        ctrl.show_auto_aa = not isWinOpen
        core.saveLoadout(true)
    end
    ImGui.TextWrapped('Full configuration lives in the Auto AA window (header button or /ac aawin). Quick toggles:')
    local spendVal = ImGui.Checkbox('Auto-Spend AA##aaPlgSpend', ctrl.auto_spend_aa or false)
    if spendVal ~= (ctrl.auto_spend_aa or false) then
        ctrl.auto_spend_aa = spendVal
        core.saveLoadout(true)
    end
    local fwVal = ImGui.Checkbox('Auto-Summon Fireworks##aaPlgFw', ctrl.auto_summon_fireworks or false)
    if fwVal ~= (ctrl.auto_summon_fireworks or false) then
        ctrl.auto_summon_fireworks = fwVal
        core.saveLoadout(true)
    end
    local delVal = ImGui.Checkbox('Delegate to MQ2AAspend##aaPlgDel', ctrl.auto_aa_delegate_aaspend ~= false)
    if delVal ~= (ctrl.auto_aa_delegate_aaspend ~= false) then
        ctrl.auto_aa_delegate_aaspend = delVal
        core.saveLoadout(true)
    end
    if AA.pendingAATrain then
        accent(WARN, string.format('Purchase workflow active: %s (step: %s)', tostring(AA.pendingAATrain.name), tostring(AA.pendingAATrain.step)))
    end
end

-- Combat loop integration
function plugin.wantsCombatHold()
    return AA.pendingAATrain ~= nil
end

function plugin.onBetweenPulls()
    if not core then return false end
    ctrl = core.ctrl
    rt = core.runtime
    if not ctrl.auto_spend_aa then return false end
    return AA.checkAutoSpendAA(true) == true
end

-- Keep MQ2AAspend's INI in step with the priority list whenever the loadout saves.
-- Keep MQ2AAspend's INI in step with the loadout, but only while Auto-Spend
-- is actually on and delegated to MQ2AAspend - and even then the sync is a
-- no-op unless the priorities / mode / threshold changed. saveLoadout runs on
-- every settings click, so this used to rewrite the INI and /aaspend load
-- constantly even with Auto AA idle.
function plugin.onLoadoutSaved()
    if not core then return end
    ctrl = core.ctrl
    if ctrl.auto_spend_aa and ctrl.auto_aa_delegate_aaspend then
        AA.syncAAsToMQ2AASpendIni(true)
    end
end

-- /ac command family
function plugin.onCommand(cmd, args)
    if not core then return false end
    return AA.onCommand(cmd, args)
end

plugin.help = {
    '  \ag/ac autoaa | autospendaa [on|off]\ax - Toggle automatic AA point spending',
    '  \ag/ac aawin | aaui\ax - Toggle the Auto AA spender & AA progression window',
    '  \ag/ac autofw | summonfw [on|off]\ax - Toggle automatic fireworks summoning',
    '  \ag/ac spendnow | spendaa\ax - Instantly purchase 1 rank of fireworks AA',
    '  \ag/ac summonnow\ax - Instantly activate fireworks summon AA',
    '  \ag/ac aathreshold [25-100]\ax - Set AA auto-spend trigger threshold',
    '  \ag/ac aacost [1-50]\ax - Set AA point cost per rank',
    '  \ag/ac aaid [id]\ax - Set AA ability ID to purchase/activate (default 17788)',
    '  \ag/ac aaname [name]\ax - Set the cap-spender AA ability name',
    '  \ag/ac aascan\ax - Force a rescan of purchasable AAs',
    '  \ag/ac aaprio [name]\ax - Toggle an AA on the priority list',
    '  \ag/ac aaspend [on|off|auto|brute|sync|now]\ax - MQ2AAspend delegation controls',
}

-- Exposed for tests and other plugins
plugin.AA = AA

return plugin
