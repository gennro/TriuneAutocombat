---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ============================================================================
-- TAC/lua/tac/nmsloot.lua — Triune NMS Loot Plugin (personal loot console)
-- ============================================================================
-- The server's personal loot system ("NMS loot") offers each kill's items to
-- the group's *active looter*: one character holds that slot and decides,
-- item by item, whether to keep / sell / tribute / bank / vault / destroy /
-- pass. The loot window does all of that; the server also exposes it as a
-- typed command:
--
--   #nms claim                            take the active looter slot
--   #nms status                           who holds it, and what you may loot
--   #nms list [handle]                    what is offered to you
--   #nms loot <action> "Item" [handle]    act on one offered item by name
--   #nms loot coin [handle]               take the coin
--   #nms echo on|off                      print every loot offer to chat, one line per item
--   actions: keep, sell, tribute, bank, vault, destroy, pass <player>
--
-- This plugin is that typed command with a memory and a network:
--   * It sends the #nms commands (`/say #nms ...`, the way the core sends
--     every other server command) and reads the server's replies from chat,
--     so it knows who the active looter is, whether echo is on, and which
--     items are currently offered to this character.
--   * Over the Box Network (boxnet plugin) every box shares that knowledge:
--     the window shows which of your boxes holds the slot, a Claim button per
--     box moves it, and any box's offered items can be listed and acted on
--     from here. Remote requests honour boxnet's trust settings and only ever
--     build a #nms line from a fixed sub-command list, so a peer can never
--     make this box type arbitrary text.
--   * Nothing here does anything the loot window cannot; it only types.
--
-- Server reply parsing. Replies are chat lines prefixed "[NMS] " or
-- "[NMS Loot] ", seen so far:
--   [NMS] Active looter: you.
--   [NMS] Offers waiting: 0 (0 items).
--   [NMS] Loot echo on. Each offer prints one line per item.
--   [NMS] Loot echo off.
--   [NMS Loot] offer 1748 slot 65535 id 12428 qty 1 "Iksar Bandit Mask"
-- (one per offered item: the offer handle #nms loot takes, the loot slot,
-- the item id, the quantity and the quoted name) and a bare "#nms" prints
-- the usage text above (no prefix). parseLine()
-- (plugin.logic) works from the words a reply must contain - "looter" plus
-- a name / "you" / a nobody word, "echo" plus on or off, "Offers waiting",
-- an item link or [Item] on an offer line - rather than exact sentences, so
-- the lines not yet seen (a list with items, an offer echo, a claim while
-- someone else holds the slot) have a fair chance of being read; every line
-- the plugin looked at lands in the window's log so a miss is visible.
-- Tighten LOOTER_PATTERNS / NOBODY_PHRASES / parseOffer as they turn up.
--
-- Chat lines reach the plugin through one catch-all mq.event (keepLinks, so
-- item names come from the link itself). The handler does one lower-case
-- scan per line and returns at once unless the line mentions loot / looter /
-- nms / offer / echo or a #nms reply window is open, so the cost on ordinary
-- chat is negligible. Our own prints are tagged and skipped, otherwise
-- "Active looter: Bob" printed here would be parsed as a server line.
-- ============================================================================

local plugin = {
    id                 = 'nmsloot',
    name               = 'NMS Loot',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Personal loot (#nms) console: shows which box holds the active looter slot, moves it between boxes over the Box Network, lists and acts on the items offered to any box.',
    defaultEnabled     = true,
    tickInterval       = 0.1,
    runOutOfCombatOnly = false,
    hasThread          = false,
    uses               = { boxnet = 'active looter roster across boxes and remote #nms commands' },
    window             = { label = 'NMS Loot', tooltip = 'Toggles the NMS Loot window (nmsloot plugin): active looter, Claim per box, offered items.', flag = 'show_nmsloot', desc = 'Active looter slot across boxes & personal loot offers', headerButton = true, order = 96 },
}
-- The compact window has its own layout key so its position, scale and
-- title-bar / ghost options are kept apart from the full window's.
plugin.windows = {
    { key = 'nmsloot_compact', label = 'NMS Loot (compact)', desc = 'Compact NMS Loot window: looter, one chip per box, top offers', headerButton = false,
      isOpen = function() return plugin.isCompactOpen() end, setOpen = function(v) plugin.setCompactOpen(v) end },
}

-- Populated by refresh() on every entry point; typed so the language server
-- does not treat them as permanently nil.
local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------
local TAG               = '[Triune NMS]'   -- our own chat prints (the server's prefixes are below)
local NMS_PREFIXES      = { '[NMS Loot]', '[NMS]' }   -- every server reply starts with one of these (longest first)
local HANDLE_MAX        = 32
local LINK              = string.char(18)   -- \x12 wraps EQ links
local ITEM_LINK_PAYLOAD = 77                -- fixed-width item link body before the item name
local CAPTURE_SEC       = 2.0               -- chat lines this soon after a #nms send belong to its reply
local HOLDER_REBROADCAST_SEC = 20.0         -- the slot holder re-announces this often (late joiners)
local BROADCAST_MIN_SEC = 0.5               -- state changes are batched at least this far apart
local WHO_MIN_SEC       = 5.0               -- answer a peer's "who" at most this often
local LOG_MAX           = 80
local OFFERS_MAX        = 100
local OFFERS_SHARED     = 50                -- offers included in a state broadcast
local ITEM_NAME_MAX     = 64
local MSG_STATE         = 'nmsloot:state'
local MSG_WHO           = 'nmsloot:who'
local MSG_RUN           = 'nmsloot:run'

-- #nms loot <action>: the loot window's choices, nothing more.
local ACTIONS    = { 'keep', 'sell', 'tribute', 'bank', 'vault', 'destroy', 'pass' }
local ACTION_SET = {}
for _, a in ipairs(ACTIONS) do ACTION_SET[a] = true end
-- Words the server uses once the item is handled ("You kept ...").
local RESOLVED_WORDS = { 'keep', 'kept', 'sell', 'sold', 'tribute', 'tributed', 'bank', 'banked', 'vault', 'vaulted', 'destroy', 'destroyed', 'pass', 'passed' }
local RESOLVED_SET = {}
for _, w in ipairs(RESOLVED_WORDS) do RESOLVED_SET[w] = true end

-- /ac nms sub-commands (also the words a peer may ask this box to run).
local SUBS = { claim = true, status = true, list = true, echo = true, loot = true, who = true, help = true, window = true, win = true, ui = true, compact = true, mini = true, full = true }

-- ----------------------------------------------------------------------------
-- Persisted settings
-- ----------------------------------------------------------------------------
local cfg = {
    announce      = true,   -- chat line when the active looter changes
    statusOnInit  = true,   -- one #nms status when the plugin starts (fills the window)
    pollSec       = 0,      -- periodic #nms status (0 = off)
    acceptRemote  = true,   -- run #nms requests from other boxes (also gated by boxnet trust)
    compact       = false,  -- show the compact window instead of the full one
    compactRows   = 4,      -- offers shown in the compact window
    armDestroy    = false,  -- Destroy buttons stay disabled until this is on (never saved)
}
local COMPACT_ROWS_MAX = 10
local COMPACT_WIDTH = 300

-- ----------------------------------------------------------------------------
-- Runtime state
-- ----------------------------------------------------------------------------
local state = {
    looter      = nil,      -- who holds the slot: a name, '' for nobody, nil while unknown
    looterAsOf  = 0,        -- os.time() the server said so (shared across boxes to pick the freshest report)
    looterAt    = 0,        -- nowSec() we learned it (for "Ns ago")
    looterFrom  = nil,      -- 'server' or the peer that told us
    echo        = nil,      -- nil unknown, true / false once the server confirmed
    offers      = {},       -- items offered to this character: { name, qty, handle, line, at }
    offersAt    = 0,
    offerCount  = nil,      -- "[NMS] Offers waiting: N (M items)." from the last status
    itemCount   = nil,
    wantList    = false,    -- a status reported offers we have not listed: run #nms list next
    pending     = nil,      -- { spec, sentAt, lines, offers, gotEmpty, from } reply window of the last #nms send
    peers       = {},       -- [lowerName] = { name, looter, known, echo, offers, offersAt, at, asOf }
    log         = {},       -- newest first: { time, text, level }
    net         = { unsubs = {}, subGen = -1, lastBroadcastAt = -1e9, lastWhoReplyAt = -1e9, askWho = false, dirty = false },
    registeredEvents = {},
    lastPollAt  = -1e9,
    initQuery   = false,    -- one #nms status on the first tick (cfg.statusOnInit)
    me          = nil,
    -- window
    view        = nil,      -- whose offers the window shows (nil = this box)
    itemInput   = '',
    handleInput = '',
    passTo      = '',       -- player name the Pass buttons pass to
}

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

-- Wall-clock seconds; tests override plugin.clock.
local function nowSec()
    if plugin.clock then return plugin.clock() end
    if mq and mq.gettime then
        local ok, ms = pcall(mq.gettime)
        if ok and type(ms) == 'number' then return ms / 1000 end
    end
    return os.clock()
end

local function wallTime()
    if plugin.wallClock then return plugin.wallClock() end
    return os.time()
end

local function lower(s) return tostring(s or ''):lower() end

local function logEvent(text, level)
    table.insert(state.log, 1, { time = os.date('%H:%M:%S'), text = tostring(text), level = level or 'info' })
    while #state.log > LOG_MAX do table.remove(state.log) end
end

local function say(fmt, ...)
    print(string.format('\ag' .. TAG .. '\ax ' .. fmt, ...))
end

local function warn(fmt, ...)
    print(string.format('\ay' .. TAG .. '\ax ' .. fmt, ...))
end

-- The boxnet API when the plugin is loaded and connected; nil otherwise.
local function boxnet()
    local bn = core and rawget(core, 'boxnet')
    if type(bn) ~= 'table' or type(bn.available) ~= 'function' then return nil end
    return bn
end

local function myName()
    if state.me and state.me ~= '' then return state.me end
    local bn = boxnet()
    if bn and bn.myName then
        local ok, n = pcall(bn.myName)
        if ok and type(n) == 'string' and n ~= '' then state.me = n return n end
    end
    local ok, n = pcall(function() return mq.TLO.Me.CleanName() end)
    if ok and n and tostring(n) ~= '' then state.me = tostring(n) end
    return state.me or ''
end

local function isMe(name)
    return name ~= nil and name ~= '' and lower(name) == lower(myName())
end

-- ----------------------------------------------------------------------------
-- Pure logic (plugin.logic; exercised by the test-suite)
-- ----------------------------------------------------------------------------
local logic = {}
logic.ACTIONS = ACTIONS
logic.ACTION_SET = ACTION_SET

-- Replaces \x12 links with their readable text. Returns the plain line and
-- the item names that came from item links (in order).
function logic.resolveLinks(s)
    local items = {}
    if type(s) ~= 'string' then return '', items end
    if not s:find(LINK, 1, true) then return s, items end
    local out = s:gsub(LINK .. '(.-)' .. LINK, function(payload)
        if payload:sub(1, 1) == '1' and #payload > 1 and #payload < ITEM_LINK_PAYLOAD then
            return payload:sub(2)               -- player link: \x12 1 Name \x12
        end
        if #payload > ITEM_LINK_PAYLOAD then
            local name = payload:sub(ITEM_LINK_PAYLOAD + 1)
            items[#items + 1] = name
            return name
        end
        return payload
    end)
    return out, items
end

-- Phrases that mean the slot is empty.
local NOBODY_PHRASES = { 'no one', 'noone', 'nobody', 'no active looter', 'not claimed', 'unclaimed', 'no looter', 'no current looter', 'is open', 'is free', 'is empty', 'is available', 'no longer', 'released', 'gave up', 'nobody has' }
-- Capitalised words that can sit where a name would but are not one.
local NOT_NAMES = { You = true, Your = true, The = true, Active = true, Current = true, Looter = true, Loot = true, Slot = true, No = true, Nobody = true, Only = true, Nms = true, NMS = true, Personal = true, Group = true, There = true, This = true, That = true, Now = true, Already = true, Someone = true }
-- Name patterns tried in order on the plain line (Lua has no alternation).
-- The first group names the holder after the word "looter" and is trusted
-- even in a negated sentence ("You are not the active looter, Bob is" says
-- nothing usable, but "The active looter is Bob" always does); the second
-- group puts the name first and is skipped when the sentence is negated
-- ("Bob is not the active looter").
local LOOTER_PATTERNS_AFTER = {
    '[Ll]ooter slot[%s:]+is[%s:]+n?o?w?%s*(%u%l+)',
    '[Ll]ooter slot[%s:]+(%u%l+)',
    '[Ll]ooter[%s:]+is[%s:]+n?o?w?%s*(%u%l+)',
    '[Ll]ooter[%s:]+(%u%l+)',
    '[Ll]ooter.-held by (%u%l+)',
    '[Ll]ooter.-belongs to (%u%l+)',
    '[Ll]ooter.-claimed by (%u%l+)',
    '[Ll]ooter.-taken by (%u%l+)',
    '[Ll]ooter.-goes to (%u%l+)',
}
local LOOTER_PATTERNS_BEFORE = {
    '(%u%l+) is [%a ]-looter',
    '(%u%l+) has [%a ]-looter',
    '(%u%l+) holds [%a ]-looter',
    '(%u%l+) already has',
    '(%u%l+) already holds',
    '(%u%l+) claimed',
    '(%u%l+) claims',
    '(%u%l+) took',
    '(%u%l+) takes',
}

local function containsAny(low, list)
    for _, p in ipairs(list) do
        if low:find(p, 1, true) then return true end
    end
    return false
end

-- A "looter" line -> the holder's name, 'You' for this character, '' for
-- nobody, or nil when the line says nothing definite (a refusal, a hint).
function logic.parseLooter(plain)
    local low = plain:lower()
    if not low:find('looter', 1, true) then return nil end
    -- "Active looter: you." / "Active looter: none." (the status reply)
    local who = low:match('looter[%s:]+(%a+)')
    if who == 'you' then return 'You' end
    if who == 'none' or who == 'nobody' or who == 'noone' or who == 'unclaimed' or who == 'open' then return '' end
    for _, pat in ipairs(LOOTER_PATTERNS_AFTER) do
        local name = plain:match(pat)
        if name and not NOT_NAMES[name] then return name end
    end
    if containsAny(low, NOBODY_PHRASES) then return '' end
    local negated = low:find(' not ', 1, true) or low:find("n't", 1, true) or low:find('cannot', 1, true) or low:find('unable', 1, true) or low:find('only ', 1, true)
    if not negated then
        for _, pat in ipairs(LOOTER_PATTERNS_BEFORE) do
            local name = plain:match(pat)
            if name and not NOT_NAMES[name] then return name end
        end
        if low:find('%f[%a]yours%f[%A]') then return 'You' end
        if low:find('^you ') or low:find('^you\'re') then
            if low:find('are the', 1, true) or low:find('are now', 1, true) or low:find('now the', 1, true) or low:find('claim', 1, true) or low:find('have the', 1, true) or low:find('hold', 1, true) or low:find('took', 1, true) or low:find('take', 1, true) then
                return 'You'
            end
        end
    end
    return nil
end

-- An "echo" line -> true / false, nil when it is not a loot echo line.
function logic.parseEcho(plain)
    local low = plain:lower()
    if not low:find('echo', 1, true) then return nil end
    if not (low:find('loot', 1, true) or low:find('nms', 1, true) or low:find('offer', 1, true)) then return nil end
    local off = low:find('%f[%a]off%f[%A]') or low:find('disabled', 1, true) or low:find('no longer', 1, true)
    local on = low:find('%f[%a]on%f[%A]') or low:find('enabled', 1, true)
    if on and off then return nil end          -- "echo on|off" is the usage text
    if off then return false end
    if on then return true end
    return nil
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- Item name and quantity from an offer / list line. The name comes from the
-- item link when there is one, else [brackets], else the text after a list
-- number ("1. Rusty Sword x3"). Quantity from "x3", "(x3)", "(3)" or "3 x".
function logic.parseOffer(plain, items)
    local name = items and items[1]
    local qty
    if not name then name = plain:match('%[(.-)%]') end
    if not name then name = plain:match('^%s*%d+[%.%):%-]%s+(.-)%s*$') end
    if not name then return nil end
    name = trim(name)
    qty = tonumber(plain:match('%(x(%d+)%)')) or tonumber(plain:match('%(%s*(%d+)%s*%)')) or tonumber(plain:match('%f[%w]x(%d+)%f[%W]')) or tonumber(plain:match('(%d+)%s*x%f[%W]'))
    -- A bare numbered-list name may carry the quantity itself: "Peridot x3".
    name = trim(name:gsub('%s*%(x?%d+%)%s*$', ''):gsub('%s+x%d+%s*$', ''))
    if name == '' or #name > ITEM_NAME_MAX then return nil end
    return name, qty
end

-- One chat line -> an event table or nil. `capturing` is the sub-command
-- whose reply window is open ('list' loosens the offer gate: while a list is
-- being printed any line that yields an item name is an offer).
--   { kind = 'looter', name = 'Bob' | 'You' | '' }
--   { kind = 'echo', on = bool }
--   { kind = 'offer', name, qty }
--   { kind = 'resolved', name }        the server handled an item
--   { kind = 'empty' }                 nothing is offered
--   { kind = 'count', offers, items }  "[NMS] Offers waiting: N (M items)."
-- Every event carries `server = true` when the line wore the [NMS] prefix.
function logic.parseLine(raw, capturing)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local plain, items = logic.resolveLinks(raw)
    plain = trim(plain)
    local server = false
    for _, prefix in ipairs(NMS_PREFIXES) do
        if plain:sub(1, #prefix) == prefix then
            server = true
            plain = trim(plain:sub(#prefix + 1))
            break
        end
    end
    local low = plain:lower()
    -- The usage text ("#nms claim - claim the active looter slot") describes
    -- the commands; it never states anything.
    if low:sub(1, 1) == '#' or low:find('^usage') or low:find('^actions:') then return nil end
    local ev = logic.parseLineBody(plain, low, items, capturing, server)
    if ev then ev.server = server end
    return ev
end

-- The list / echo line: offer <handle> slot <n> id <itemId> qty <n> "<Name>"
function logic.parseOfferLine(plain)
    local handle, slot, id, qty, name = plain:match('^offer (%d+) slot (%d+) id (%d+) qty (%d+) "(.-)"')
    if not handle then return nil end
    name = trim(name)
    if name == '' then return nil end
    return { kind = 'offer', name = name, qty = tonumber(qty), handle = handle, itemId = tonumber(id), slot = tonumber(slot), plain = plain }
end

-- A server line about an item that is no longer offered: the auto-loot
-- rules selling / banking / keeping it ("[NMS] Ruby Crown sold for 200
-- platinum."), or a #nms loot action done. A handled-word plus the name -
-- the text before the word, a quoted name, an item link - or an offer handle.
function logic.parseResolvedLine(plain, low, items)
    local hit = nil
    for _, w in ipairs(RESOLVED_WORDS) do
        if low:find('%f[%a]' .. w .. '%f[%A]') then hit = w break end
    end
    if not hit then return nil end
    local handle = plain:match('%f[%a]offer (%d+)')
    local name = items and items[1] or plain:match('"(.-)"') or plain:match('%[(.-)%]')
    if not name and not handle then
        -- "<Name> sold for 200 platinum." - the name is everything before the word.
        name = plain:match('^(.-)%s+' .. hit .. '%f[%A]')
        if name and (name == '' or name:lower() == 'you' or name:lower():find('^you ')) then name = nil end
    end
    if name then name = trim(name) end
    if (not name or name == '') and not handle then return nil end
    return { kind = 'resolved', name = name, handle = handle, plain = plain }
end

function logic.parseLineBody(plain, low, items, capturing, server)
    local offer = logic.parseOfferLine(plain)
    if offer then return offer end
    if server then
        -- The server's other item lines (auto-sold, kept, banked...) are
        -- never offers: the offer line has its own exact format above.
        local done = logic.parseResolvedLine(plain, low, items)
        if done then return done end
    end
    local nOffers = low:match('offers waiting[:%s]+(%d+)')
    if nOffers then
        return { kind = 'count', offers = tonumber(nOffers), items = tonumber(low:match('%((%d+)%s+items?%)')), plain = plain }
    end
    if low:find('looter', 1, true) then
        local name = logic.parseLooter(plain)
        if name ~= nil then return { kind = 'looter', name = name, plain = plain } end
    end
    local echoOn = logic.parseEcho(plain)
    if echoOn ~= nil then return { kind = 'echo', on = echoOn, plain = plain } end
    local lootish = #items > 0 or low:find('offer', 1, true) or low:find('loot', 1, true) or low:find('nms', 1, true)
    if lootish and (low:find('nothing', 1, true) or low:find('no items', 1, true) or low:find('no item ', 1, true) or low:find('none ', 1, true)) then
        return { kind = 'empty', plain = plain }
    end
    -- Lines a player typed ("Bob tells the group, '...'") never carry offers.
    local playerChat = low:find(", '", 1, true) ~= nil
    if low:find('^you ') then
        for _, w in ipairs(RESOLVED_WORDS) do
            if low:find('^you ' .. w .. '%f[%A]') then
                local name = logic.parseOffer(plain, items)
                if not name then
                    name = trim((plain:match('^You %a+ (.-)%.?$') or ''):gsub('^the ', ''):gsub('"', ''))
                    if name == '' or #name > ITEM_NAME_MAX then name = nil end
                end
                if name then return { kind = 'resolved', name = name, plain = plain } end
            end
        end
    end
    -- Offers come only from the server's exact "offer ..." line above. The
    -- loose form (a bracketed or numbered name) is kept for a #nms list
    -- reply printed without the prefix - never from a server line that is
    -- something else, another script's "[Tag] ..." line, or player chat.
    if not playerChat and not server and capturing == 'list' then
        local name, qty = logic.parseOffer(plain, items)
        if name then return { kind = 'offer', name = name, qty = qty, plain = plain } end
    end
    return nil
end

-- The text after "#nms " for a request spec, or nil + reason. This is the
-- only place a #nms line is built, so a remote request can never smuggle
-- anything past the fixed sub-command list.
-- Syntax (from the server's usage text): `list [handle]`,
-- `loot <action> "item name" [handle]`, `loot coin [handle]`, and the pass
-- action takes the player: `loot pass <player> "item name" [handle]`.
function logic.nmsLine(spec)
    if type(spec) ~= 'table' then return nil, 'no request' end
    local sub = lower(spec.sub)
    local handle = trim(tostring(spec.handle or ''))
    if handle ~= '' and (#handle > HANDLE_MAX or not handle:match('^[%w_%-]+$')) then return nil, 'bad handle' end
    local suffix = handle ~= '' and (' ' .. handle) or ''
    if sub == 'claim' or sub == 'status' then return sub end
    if sub == 'list' then return 'list' .. suffix end
    if sub == 'echo' then
        if spec.on == true then return 'echo on' end
        if spec.on == false then return 'echo off' end
        return nil, 'echo needs on or off'
    end
    if sub == 'loot' then
        local action = lower(spec.action)
        if action == 'coin' then return 'loot coin' .. suffix end
        if not ACTION_SET[action] then return nil, 'unknown loot action "' .. tostring(spec.action) .. '"' end
        local item = trim(tostring(spec.item or ''):gsub('"', ''))
        if item == '' then return nil, 'no item name' end
        if #item > ITEM_NAME_MAX then return nil, 'item name too long' end
        if action == 'pass' then
            local player = trim(tostring(spec.player or ''))
            if player == '' or not player:match('^%a+$') then return nil, 'pass needs a player name' end
            return string.format('loot pass %s "%s"%s', player, item, suffix)
        end
        return string.format('loot %s "%s"%s', action, item, suffix)
    end
    return nil, 'unknown sub-command "' .. tostring(spec.sub) .. '"'
end

-- /ac nms [Name|me] <sub> [...] -> { target, sub, action, item, on } or
-- nil + usage text. `isPeer(name)` says whether a word is a known box.
function logic.parseArgs(args, isPeer)
    args = args or {}
    local i = 2
    local target = nil
    local w = args[i] and lower(args[i]) or nil
    if w and not SUBS[w] and not ACTION_SET[w] and w ~= 'coin' then
        if w == 'me' or w == 'here' then
            i = i + 1
        elseif isPeer and isPeer(args[i]) then
            target = args[i]
            i = i + 1
        else
            return nil, string.format('"%s" is not a box on the network or a sub-command', tostring(args[i]))
        end
        w = args[i] and lower(args[i]) or nil
    end
    if not w then return { target = target, sub = target and 'status' or 'window' } end
    if w == 'win' or w == 'ui' then w = 'window' end
    if w == 'mini' then w = 'compact' end
    if w == 'claim' or w == 'status' or w == 'who' or w == 'help' or w == 'window' or w == 'compact' or w == 'full' then
        return { target = target, sub = w }
    end
    if w == 'list' then
        -- `/ac nms list Bob` reads as naturally as `/ac nms Bob list`.
        local nxt = args[i + 1]
        if nxt and not target and isPeer and isPeer(nxt) then return { target = nxt, sub = 'list' } end
        return { target = target, sub = 'list', handle = nxt }
    end
    if w == 'echo' then
        local v = lower(args[i + 1])
        if v == 'on' or v == '1' or v == 'true' then return { target = target, sub = 'echo', on = true } end
        if v == 'off' or v == '0' or v == 'false' then return { target = target, sub = 'echo', on = false } end
        return nil, 'usage: /ac nms echo on|off'
    end
    local action, first
    if w == 'loot' then
        action = lower(args[i + 1])
        first = i + 2
    elseif ACTION_SET[w] or w == 'coin' then
        action = w
        first = i + 1
    else
        return nil, 'unknown sub-command "' .. tostring(args[i]) .. '"'
    end
    if action == 'coin' then return { target = target, sub = 'loot', action = 'coin', handle = args[first] } end
    if not ACTION_SET[action] then return nil, 'usage: /ac nms loot <' .. table.concat(ACTIONS, '|') .. '|coin> "Item Name" [handle]' end
    local player
    if action == 'pass' then
        player = args[first]
        first = first + 1
        if not player or not player:match('^%a+$') then return nil, 'usage: /ac nms loot pass <Player> "Item Name" [handle]' end
    end
    local parts = {}
    for k = first, #args do parts[#parts + 1] = tostring(args[k]) end
    local rest = trim(table.concat(parts, ' '))
    -- A quoted item may be followed by the offer handle; an unquoted one is
    -- the whole rest of the line.
    local item, handle = rest:match('^"(.-)"%s*(%S*)$')
    if not item then item, handle = rest:gsub('"', ''), nil end
    item = trim(item)
    if handle == '' then handle = nil end
    if item == '' then return nil, 'usage: /ac nms loot ' .. action .. ' "Item Name" [handle]' end
    return { target = target, sub = 'loot', action = action, item = item, player = player, handle = handle }
end

-- Which report wins: the one the server confirmed most recently.
function logic.newer(asOf, than)
    return (tonumber(asOf) or 0) > (tonumber(than) or 0)
end

-- ----------------------------------------------------------------------------
-- Belief: who holds the slot, what is offered
-- ----------------------------------------------------------------------------
local function looterLabel(name)
    if name == nil then return 'unknown' end
    if name == '' then return 'nobody' end
    if isMe(name) then return name .. ' (this box)' end
    return name
end

-- Adopt a holder report. `from` is 'server' or the reporting peer's name.
local function setLooter(name, asOf, from)
    if name == nil then return false end
    if name == 'You' then name = myName() end
    if from ~= 'server' and not logic.newer(asOf, state.looterAsOf) then return false end
    local changed = (state.looter ~= name)
    state.looter = name
    state.looterAsOf = asOf or wallTime()
    state.looterAt = nowSec()
    state.looterFrom = from
    if changed then
        logEvent(string.format('Active looter: %s (%s)', looterLabel(name), from == 'server' and 'server' or 'via ' .. tostring(from)))
        if cfg.announce then say('Active looter is now \ag%s\ax%s.', looterLabel(name), from == 'server' and '' or (' (reported by ' .. tostring(from) .. ')')) end
        state.net.dirty = true
    end
    return changed
end

local function setOffers(list)
    state.offers = list or {}
    while #state.offers > OFFERS_MAX do table.remove(state.offers) end
    state.offersAt = nowSec()
    state.net.dirty = true
end

local function addOffer(name, qty, line, handle, itemId)
    for _, o in ipairs(state.offers) do
        if lower(o.name) == lower(name) and (handle == nil or o.handle == nil or o.handle == handle) then
            o.qty = qty or o.qty
            o.line = line or o.line
            o.handle = handle or o.handle
            o.itemId = itemId or o.itemId
            o.at = nowSec()
            state.offersAt = o.at
            return false
        end
    end
    table.insert(state.offers, { name = name, qty = qty, line = line, handle = handle, itemId = itemId, at = nowSec() })
    while #state.offers > OFFERS_MAX do table.remove(state.offers, 1) end
    state.offersAt = nowSec()
    state.net.dirty = true
    return true
end

local function removeOffer(name, handle)
    local removed = false
    for i = #state.offers, 1, -1 do
        local o = state.offers[i]
        local match
        if handle and o.handle then
            match = (o.handle == handle)
        else
            match = name ~= nil and name ~= '' and lower(o.name) == lower(name)
        end
        if match then
            table.remove(state.offers, i)
            removed = true
        end
    end
    if removed then
        state.offersAt = nowSec()
        state.net.dirty = true
    end
    return removed
end

-- ----------------------------------------------------------------------------
-- Sending #nms
-- ----------------------------------------------------------------------------
-- Runs one request here. `from` names the peer that asked (nil = local).
local function sendNms(spec, from)
    local line, why = logic.nmsLine(spec)
    if not line then return false, why end
    if not (mq and mq.cmdf) then return false, 'not in game' end
    mq.cmdf('/say #nms %s', line)
    state.pending = { spec = spec, sentAt = nowSec(), lines = {}, offers = {}, gotEmpty = false, from = from }
    logEvent(string.format('-> #nms %s%s', line, from and (' (asked by ' .. from .. ')') or ''))
    return true
end

local function finishPending(force)
    local p = state.pending
    if not p or (not force and (nowSec() - p.sentAt) < CAPTURE_SEC) then return end
    state.pending = nil
    local sub = lower(p.spec.sub)
    if sub == 'list' then
        if #p.offers > 0 or p.gotEmpty then
            setOffers(p.offers)
        elseif #p.lines == 0 then
            logEvent('#nms list: no reply within ' .. CAPTURE_SEC .. 's', 'warn')
        end
    elseif sub == 'status' or sub == 'claim' then
        if #p.lines == 0 then logEvent('#nms ' .. sub .. ': no reply within ' .. CAPTURE_SEC .. 's', 'warn') end
    end
    if p.from and #p.lines == 0 then
        -- The asking box only sees state broadcasts; say when the server stayed silent.
        state.net.dirty = true
    end
end

-- ----------------------------------------------------------------------------
-- Chat lines
-- ----------------------------------------------------------------------------
-- Lines that are not the server talking: our own tagged prints, any other
-- MQ plugin's / script's "[Tag] ..." output (MQ2Nav, BoxNet, Triune...; the
-- server's own prefix is [NMS]) and the echo of the /say that carried the
-- command. print() output is delivered to events too (\a colour codes
-- stripped), so this is what keeps "[MQ2Nav] ... loot ..." out of the offers.
local function serverLine(low)
    for _, prefix in ipairs(NMS_PREFIXES) do
        if low:find(lower(prefix), 1, true) == 1 then return true end
    end
    return false
end

local function ownLine(low)
    if low:sub(1, 1) == '[' then return not serverLine(low) end
    return low:find('you say,', 1, true) == 1
end

local function handleEvent(ev, raw)
    local p = state.pending
    if ev.kind == 'looter' then
        setLooter(ev.name, wallTime(), 'server')
    elseif ev.kind == 'echo' then
        if state.echo ~= ev.on then
            state.echo = ev.on
            logEvent('Loot echo is ' .. (ev.on and 'on' or 'off'))
            state.net.dirty = true
        end
    elseif ev.kind == 'offer' then
        if p and lower(p.spec.sub) == 'list' then
            table.insert(p.offers, { name = ev.name, qty = ev.qty, handle = ev.handle, itemId = ev.itemId, line = ev.plain, at = nowSec() })
        else
            if addOffer(ev.name, ev.qty, ev.plain, ev.handle, ev.itemId) then logEvent('Offered: ' .. ev.name .. (ev.qty and (' x' .. ev.qty) or '') .. (ev.handle and (' [' .. ev.handle .. ']') or '')) end
        end
    elseif ev.kind == 'resolved' then
        if removeOffer(ev.name, ev.handle) then logEvent('Handled: ' .. tostring(ev.name or ('offer ' .. tostring(ev.handle)))) end
        if p and lower(p.spec.sub) == 'list' and ev.handle then
            for i = #p.offers, 1, -1 do
                if p.offers[i].handle == ev.handle then table.remove(p.offers, i) end
            end
        end
    elseif ev.kind == 'empty' then
        if p and lower(p.spec.sub) == 'list' then p.gotEmpty = true else setOffers({}) end
        logEvent('Nothing offered')
    elseif ev.kind == 'count' then
        state.offerCount, state.itemCount = ev.offers, ev.items
        if ev.offers == 0 then
            if p and lower(p.spec.sub) == 'list' then p.gotEmpty = true elseif #state.offers > 0 then setOffers({}) end
        elseif not (p and lower(p.spec.sub) == 'list') then
            -- Something is waiting and this was not a list: fetch it.
            state.wantList = true
        end
    end
end

local function processLine(line)
    if type(line) ~= 'string' or line == '' then return end
    local low = line:lower()
    local p = state.pending
    if not p then
        -- Cheap gate for ordinary chat: the words a #nms line must contain,
        -- or "You <kept/sold/...>" for an item just handled.
        local interesting = serverLine(low) or low:find('loot', 1, true) or low:find('offer', 1, true) or low:find('echo', 1, true) or low:find('nms', 1, true)
        if not interesting then
            local verb = low:match('^you (%a+) ')
            if not (verb and RESOLVED_SET[verb]) then return end
        end
    end
    if ownLine(low) then return end
    if p then
        table.insert(p.lines, line)
        if #p.lines <= 12 then logEvent('<- ' .. (logic.resolveLinks(line))) end
    end
    local ev = logic.parseLine(line, p and lower(p.spec.sub) or nil)
    if not ev then
        if not p and (low:find('looter', 1, true) or low:find('nms', 1, true)) then logEvent('<- ' .. (logic.resolveLinks(line))) end
        return
    end
    handleEvent(ev, line)
end

local function onAnyLine(line)
    local ok, err = pcall(processLine, line)
    if not ok then logEvent('line error: ' .. tostring(err), 'error') end
end

local function registerEvents()
    if not (mq and mq.event) then return end
    local name = 'TacNmsLootAll'
    if mq.unevent then pcall(mq.unevent, name) end
    local ok = pcall(mq.event, name, '#*#', onAnyLine, { keepLinks = true })
    if not ok then ok = pcall(mq.event, name, '#*#', onAnyLine) end
    if ok then table.insert(state.registeredEvents, name) end
end

local function unregisterEvents()
    if mq and mq.unevent then
        for _, name in ipairs(state.registeredEvents) do pcall(mq.unevent, name) end
    end
    state.registeredEvents = {}
end

-- ----------------------------------------------------------------------------
-- Box Network
-- ----------------------------------------------------------------------------
local function senderName(sender, data)
    local n = sender and sender.character
    if type(n) ~= 'string' or n == '' then n = data and data.from end
    return type(n) == 'string' and n or ''
end

local function statePayload()
    local offers = {}
    for i, o in ipairs(state.offers) do
        if i > OFFERS_SHARED then break end
        offers[#offers + 1] = { n = o.name, q = o.qty, h = o.handle, i = o.itemId }
    end
    return {
        looter = state.looter or '', known = state.looter ~= nil, asOf = state.looterAsOf,
        echo = state.echo, offers = offers, at = wallTime(),
    }
end

local function broadcastState()
    local bn = boxnet()
    if not bn then return false end
    state.net.lastBroadcastAt = nowSec()
    local ok = bn.broadcast(MSG_STATE, statePayload()) == true
    -- A failed send (boxnet not connected yet) keeps the state dirty so the
    -- next tick tries again.
    state.net.dirty = not ok
    return ok
end

local function peerRecord(name, create)
    local key = lower(name)
    local rec = state.peers[key]
    if not rec and create then
        rec = { name = name, offers = {}, offersAt = 0, at = 0 }
        state.peers[key] = rec
    end
    return rec
end

local function onState(data, sender)
    local from = senderName(sender, data)
    if from == '' or type(data) ~= 'table' then return end
    local rec = peerRecord(from, true)
    rec.name = from
    rec.at = nowSec()
    rec.echo = data.echo
    rec.known = data.known == true
    rec.looter = data.known and tostring(data.looter or '') or nil
    rec.asOf = tonumber(data.asOf) or 0
    local offers = {}
    for _, o in ipairs(type(data.offers) == 'table' and data.offers or {}) do
        if type(o) == 'table' and type(o.n) == 'string' and o.n ~= '' then
            offers[#offers + 1] = { name = o.n, qty = tonumber(o.q), handle = type(o.h) == 'string' and o.h or nil, itemId = tonumber(o.i) }
        end
    end
    rec.offers = offers
    rec.offersAt = nowSec()
    if type(data.refused) == 'string' then
        logEvent(from .. ' refused: ' .. data.refused, 'warn')
        warn('%s refused the request: %s', from, data.refused)
    end
    if rec.known then setLooter(rec.looter, rec.asOf, from) end
end

local function onWho(data, sender)
    local from = senderName(sender, data)
    if from == '' then return end
    if (nowSec() - state.net.lastWhoReplyAt) < WHO_MIN_SEC then return end
    state.net.lastWhoReplyAt = nowSec()
    broadcastState()
end

local function onRun(data, sender)
    local from = senderName(sender, data)
    if from == '' or type(data) ~= 'table' then return end
    local bn = boxnet()
    local function refuse(reason)
        logEvent(string.format('Refused %s: %s', from, reason), 'warn')
        if bn then
            local p = statePayload()
            p.refused = reason
            bn.send(from, MSG_STATE, p)
        end
    end
    if not cfg.acceptRemote then return refuse('remote #nms requests are off on ' .. myName()) end
    if bn and bn.trusted and not bn.trusted(sender, data) then return refuse('not trusted') end
    local spec = { sub = data.sub, action = data.action, item = data.item, on = data.on, handle = data.handle, player = data.player }
    local line = logic.nmsLine(spec)
    if not line then return refuse('bad request') end
    -- One reply window at a time: close the current one with what it has.
    finishPending(true)
    local ok, why = sendNms(spec, from)
    if not ok then return refuse(why or 'cannot send') end
    if cfg.announce then say('%s asked this box to run \ag#nms %s\ax.', from, line) end
end

local NET_HANDLERS = {
    [MSG_STATE] = onState,
    [MSG_WHO]   = onWho,
    [MSG_RUN]   = onRun,
}

local function dropSubscriptions()
    for _, unsub in ipairs(state.net.unsubs) do pcall(unsub) end
    state.net.unsubs = {}
    state.net.subGen = -1
end

-- (Re)subscribes whenever the boxnet plugin (re)loads, then asks the boxes
-- what they know.
local function ensureSubscriptions()
    local bn = boxnet()
    if not bn or type(bn.subscribe) ~= 'function' then return end
    local gen = bn.generation and bn.generation() or 0
    if state.net.subGen == gen then return end
    dropSubscriptions()
    for kind, fn in pairs(NET_HANDLERS) do
        local ok, unsub = pcall(bn.subscribe, kind, fn)
        if ok and type(unsub) == 'function' then table.insert(state.net.unsubs, unsub) end
    end
    state.net.subGen = gen
    state.net.askWho = true
end

-- Runs `spec` on `target` (nil / this character = here). Returns ok, why.
local function runOn(target, spec)
    if not target or target == '' or isMe(target) then
        return sendNms(spec, nil)
    end
    local bn = boxnet()
    if not bn then return false, 'the Box Network plugin is not loaded' end
    local peer = bn.peer and bn.peer(target)
    if not peer then return false, target .. ' is not on the Box Network' end
    local line, why = logic.nmsLine(spec)
    if not line then return false, why end
    local ok = bn.send(peer.name, MSG_RUN, { sub = spec.sub, action = spec.action, item = spec.item, on = spec.on, handle = spec.handle, player = spec.player })
    if ok then logEvent(string.format('-> %s: #nms %s', peer.name, line)) end
    return ok, ok and nil or 'send failed'
end

local function askWho()
    local bn = boxnet()
    if not bn then return false end
    local ok = bn.broadcast(MSG_WHO, {}) == true
    state.net.askWho = not ok
    return ok
end

-- ----------------------------------------------------------------------------
-- Tick
-- ----------------------------------------------------------------------------
local function tick()
    ensureSubscriptions()
    finishPending()
    local now = nowSec()
    if state.initQuery then
        -- Deferred past onLoadSettings so the saved switch is honoured.
        state.initQuery = false
        if cfg.statusOnInit then sendNms({ sub = 'status' }, nil) end
    end
    if state.wantList and not state.pending then
        state.wantList = false
        sendNms({ sub = 'list' }, nil)
    end
    if cfg.pollSec > 0 and not state.pending and (now - state.lastPollAt) >= cfg.pollSec then
        state.lastPollAt = now
        sendNms({ sub = 'status' }, nil)
    end
    local bn = boxnet()
    if not bn then return end
    if state.net.askWho then askWho() end
    if state.net.dirty and not state.pending and (now - state.net.lastBroadcastAt) >= BROADCAST_MIN_SEC then
        broadcastState()
    elseif state.looter and isMe(state.looter) and (now - state.net.lastBroadcastAt) >= HOLDER_REBROADCAST_SEC then
        broadcastState()
    end
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
local function fmtAge(sec)
    if sec < 1 then return '<1s' end
    if sec < 60 then return string.format('%ds', math.floor(sec)) end
    if sec < 3600 then return string.format('%dm', math.floor(sec / 60)) end
    return string.format('%dh', math.floor(sec / 3600))
end

local function peerRows()
    local out = {}
    local bn = boxnet()
    local seen = {}
    if bn then
        for _, p in ipairs(bn.peers()) do
            local rec = peerRecord(p.name, false)
            out[#out + 1] = { name = p.name, online = true, rec = rec }
            seen[lower(p.name)] = true
        end
    end
    for key, rec in pairs(state.peers) do
        if not seen[key] then out[#out + 1] = { name = rec.name, online = false, rec = rec } end
    end
    table.sort(out, function(a, b) return lower(a.name) < lower(b.name) end)
    return out
end

local function drawSettingsBody()
    local v = ImGui.Checkbox('Compact window##nmsCompact', cfg.compact)
    if v ~= cfg.compact then cfg.compact = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('A small always-fitting window: who holds the slot, one chip per box (click = claim there), the first offers with one-letter action buttons. Right-click it for these settings; Full brings the big window back.') end
    ImGui.SetNextItemWidth(core.px(160))
    local rows = ImGui.SliderInt('Compact offers shown##nmsCompactRows', math.floor(cfg.compactRows or 4), 1, COMPACT_ROWS_MAX)
    if rows ~= cfg.compactRows then cfg.compactRows = rows; core.saveLoadout(true) end
    v = ImGui.Checkbox('Announce looter changes in chat##nmsAnnounce', cfg.announce)
    if v ~= cfg.announce then cfg.announce = v; core.saveLoadout(true) end
    v = ImGui.Checkbox('Ask the server who holds the slot when Triune loads##nmsInit', cfg.statusOnInit)
    if v ~= cfg.statusOnInit then cfg.statusOnInit = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('One #nms status right after the plugin starts, so the window is filled without a click.') end
    v = ImGui.Checkbox('Run #nms requests sent by other boxes##nmsAccept', cfg.acceptRemote)
    if v ~= cfg.acceptRemote then cfg.acceptRemote = v; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('Claim / list / loot requests from your other boxes. Also gated by the Box Network trust settings.') end
    ImGui.SetNextItemWidth(core.px(160))
    local poll = ImGui.SliderInt('Status poll (s, 0 = off)##nmsPoll', math.floor(cfg.pollSec or 0), 0, 300)
    if poll ~= cfg.pollSec then cfg.pollSec = poll; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('Send #nms status this often. Off by default: claims and status replies already keep every box informed.') end
end

local function drawStatusLine(colors)
    local GOOD, WARN, MUTED, ARC = colors.GOOD, colors.WARN, colors.MUTED, colors.ARC
    ImGui.TextDisabled('Active looter:')
    ImGui.SameLine()
    if state.looter == nil then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'unknown')
    elseif state.looter == '' then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'nobody')
    elseif isMe(state.looter) then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], state.looter .. ' (this box)')
    else
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], state.looter)
    end
    if state.looter ~= nil then
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('%s ago via %s', fmtAge(nowSec() - state.looterAt), tostring(state.looterFrom or '?')))
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Claim here##nmsClaimHere') then sendNms({ sub = 'claim' }, nil) end
    if ImGui.IsItemHovered() then core.setTooltip('#nms claim on this character.') end
    ImGui.SameLine()
    if ImGui.SmallButton('Status##nmsStatus') then sendNms({ sub = 'status' }, nil) end
    if ImGui.IsItemHovered() then core.setTooltip('#nms status - ask the server who holds the slot.') end
    ImGui.SameLine()
    if ImGui.SmallButton('Ask boxes##nmsWho') then askWho() end
    if ImGui.IsItemHovered() then core.setTooltip('Ask every box on the network what it knows.') end

    ImGui.TextDisabled('Loot echo:')
    ImGui.SameLine()
    if state.echo == nil then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'unknown')
    elseif state.echo then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'on')
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'off')
    end
    ImGui.SameLine()
    if ImGui.SmallButton('On##nmsEchoOn') then sendNms({ sub = 'echo', on = true }, nil) end
    ImGui.SameLine()
    if ImGui.SmallButton('Off##nmsEchoOff') then sendNms({ sub = 'echo', on = false }, nil) end
    if ImGui.IsItemHovered() then core.setTooltip('#nms echo on|off - print every loot offer to chat, one line per item. Same as the loot window checkbox.') end
    if state.offerCount ~= nil then
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('  Offers waiting: %d (%s item%s)', state.offerCount, tostring(state.itemCount or '?'), state.itemCount == 1 and '' or 's'))
    end
    if state.pending then
        ImGui.SameLine()
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('waiting for #nms %s...', tostring(state.pending.spec.sub)))
    end
end

local function drawBoxTable(colors)
    local GOOD, WARN, MUTED, ARC = colors.GOOD, colors.WARN, colors.MUTED, colors.ARC
    local bn = boxnet()
    if not bn then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'The Box Network plugin (boxnet) is not loaded or is disabled - only this character is shown.')
    end
    local rows = peerRows()
    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable
    local height = core.px(28) * (#rows + 2) + core.px(8)
    if not ImGui.BeginTable('NmsLootBoxes', 5, tableFlags, ImVec2(0, height)) then return end
    ImGui.TableSetupColumn('Box', ImGuiTableColumnFlags.WidthFixed, core.px(120))
    ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, core.px(90))
    ImGui.TableSetupColumn('Offers', ImGuiTableColumnFlags.WidthFixed, core.px(60))
    ImGui.TableSetupColumn('Reported', ImGuiTableColumnFlags.WidthFixed, core.px(80))
    ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableHeadersRow()

    local function actionCells(name, isSelf, holder, offersN)
        ImGui.TableSetColumnIndex(4)
        if holder then ImGui.BeginDisabled() end
        if ImGui.SmallButton('Claim##nmsClaim' .. name) then runOn(isSelf and nil or name, { sub = 'claim' }) end
        if holder then ImGui.EndDisabled() end
        if ImGui.IsItemHovered() then core.setTooltip(holder and 'Already holds the slot.' or ('#nms claim on ' .. name)) end
        ImGui.SameLine()
        if ImGui.SmallButton('Status##nmsSt' .. name) then runOn(isSelf and nil or name, { sub = 'status' }) end
        ImGui.SameLine()
        if ImGui.SmallButton('List##nmsLs' .. name) then
            runOn(isSelf and nil or name, { sub = 'list' })
            state.view = isSelf and nil or name
        end
        if ImGui.IsItemHovered() then core.setTooltip('#nms list on ' .. name .. ' and show the items below.') end
        if offersN > 0 then
            ImGui.SameLine()
            if ImGui.SmallButton('Show##nmsShow' .. name) then state.view = isSelf and nil or name end
        end
    end

    -- This character first
    local me = myName()
    ImGui.TableNextRow()
    ImGui.TableSetColumnIndex(0)
    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], (me ~= '' and me or '(me)') .. ' *')
    ImGui.TableSetColumnIndex(1)
    local meHolder = state.looter ~= nil and isMe(state.looter)
    if meHolder then ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'LOOTER') else ImGui.TextDisabled('-') end
    ImGui.TableSetColumnIndex(2)
    ImGui.Text(tostring(#state.offers))
    ImGui.TableSetColumnIndex(3)
    ImGui.TextDisabled(state.looter ~= nil and fmtAge(nowSec() - state.looterAt) or '-')
    actionCells(me ~= '' and me or 'me', true, meHolder, #state.offers)

    for _, row in ipairs(rows) do
        local rec = row.rec
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        if row.online then ImGui.Text(row.name) else ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], row.name .. ' (offline)') end
        ImGui.TableSetColumnIndex(1)
        local holder = state.looter ~= nil and state.looter ~= '' and lower(state.looter) == lower(row.name)
        if holder then
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'LOOTER')
        elseif rec and rec.known == false then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'unknown')
        else
            ImGui.TextDisabled('-')
        end
        ImGui.TableSetColumnIndex(2)
        ImGui.Text(tostring(rec and #rec.offers or 0))
        ImGui.TableSetColumnIndex(3)
        ImGui.TextDisabled(rec and rec.at > 0 and fmtAge(nowSec() - rec.at) or 'never')
        actionCells(row.name, false, holder, rec and #rec.offers or 0)
    end
    ImGui.EndTable()
end

local function drawOffers(colors)
    local GOOD, MUTED = colors.GOOD, colors.MUTED
    local viewName = state.view
    local offers, target, offersAt
    if viewName and not isMe(viewName) then
        local rec = peerRecord(viewName, false)
        offers = rec and rec.offers or {}
        offersAt = rec and rec.offersAt or 0
        target = viewName
    else
        offers = state.offers
        offersAt = state.offersAt
        target = nil
        state.view = nil
    end

    ImGui.TextDisabled('Offered to:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(140))
    if ImGui.BeginCombo('##nmsView', target or (myName() ~= '' and myName() or 'this box')) then
        if ImGui.Selectable(myName() ~= '' and myName() or 'this box', target == nil) then state.view = nil end
        for _, row in ipairs(peerRows()) do
            if ImGui.Selectable(row.name, target ~= nil and lower(row.name) == lower(target)) then state.view = row.name end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Refresh list##nmsRefresh') then runOn(target, { sub = 'list' }) end
    if ImGui.IsItemHovered() then core.setTooltip('#nms list on ' .. (target or 'this box')) end
    ImGui.SameLine()
    ImGui.TextDisabled(offersAt > 0 and ('updated ' .. fmtAge(nowSec() - offersAt) .. ' ago') or 'not listed yet')
    ImGui.SameLine()
    if ImGui.SmallButton('Take coin##nmsCoin') then runOn(target, { sub = 'loot', action = 'coin', handle = trim(state.handleInput) }) end
    if ImGui.IsItemHovered() then core.setTooltip('#nms loot coin' .. (trim(state.handleInput) ~= '' and (' ' .. trim(state.handleInput)) or '') .. ' on ' .. (target or 'this box')) end
    ImGui.SameLine()
    local arm = ImGui.Checkbox('Arm Destroy##nmsArm', cfg.armDestroy)
    if arm ~= cfg.armDestroy then cfg.armDestroy = arm end
    if ImGui.IsItemHovered() then core.setTooltip('Destroy buttons stay disabled until this is ticked.') end
    ImGui.SameLine()
    ImGui.TextDisabled('Pass to:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(110))
    local passTxt = ImGui.InputTextWithHint('##nmsPassTo', 'player', state.passTo or '')
    if type(passTxt) == 'string' then state.passTo = passTxt end
    if ImGui.IsItemHovered() then core.setTooltip('Pass buttons run #nms loot pass <player> "Item". Pick a box from the arrow or type any player name.') end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(20))
    if ImGui.BeginCombo('##nmsPassPick', '', ImGuiComboFlags and ImGuiComboFlags.NoPreview or 0) then
        for _, row in ipairs(peerRows()) do
            if ImGui.Selectable(row.name, lower(row.name) == lower(state.passTo)) then state.passTo = row.name end
        end
        ImGui.EndCombo()
    end

    local passTo = trim(state.passTo)
    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if ImGui.BeginTable('NmsLootOffers', 4, tableFlags, ImVec2(0, core.px(150))) then
        ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, core.px(40))
        ImGui.TableSetupColumn('Handle', ImGuiTableColumnFlags.WidthFixed, core.px(70))
        ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, core.px(330))
        ImGui.TableHeadersRow()
        if #offers == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(nothing listed - Refresh list runs #nms list, or turn loot echo on)')
        end
        for i, o in ipairs(offers) do
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], o.name)
            if ImGui.IsItemHovered() then core.setTooltip((o.itemId and ('item id ' .. o.itemId .. '\n') or '') .. (o.line or o.name)) end
            ImGui.TableSetColumnIndex(1)
            ImGui.Text(o.qty and tostring(o.qty) or '-')
            ImGui.TableSetColumnIndex(2)
            ImGui.TextDisabled(o.handle or '-')
            ImGui.TableSetColumnIndex(3)
            for k, action in ipairs(ACTIONS) do
                if k > 1 then ImGui.SameLine() end
                local disabled = (action == 'destroy' and not cfg.armDestroy) or (action == 'pass' and passTo == '')
                if disabled then ImGui.BeginDisabled() end
                if action == 'destroy' then ImGui.PushStyleColor(ImGuiCol.Button, 0.60, 0.20, 0.20, 1.0) end
                local label = action:sub(1, 1):upper() .. action:sub(2)
                if ImGui.SmallButton(label .. '##nmsAct' .. i .. action) then
                    runOn(target, { sub = 'loot', action = action, item = o.name, handle = o.handle, player = passTo })
                end
                if action == 'destroy' then ImGui.PopStyleColor(1) end
                if disabled then ImGui.EndDisabled() end
                if ImGui.IsItemHovered() then
                    if action == 'pass' and passTo == '' then
                        core.setTooltip('Type or pick a player in "Pass to" first.')
                    else
                        core.setTooltip(string.format('#nms %s%s', (logic.nmsLine({ sub = 'loot', action = action, item = o.name, handle = o.handle, player = passTo })) or '?', target and (' on ' .. target) or ''))
                    end
                end
            end
        end
        ImGui.EndTable()
    end

    -- By name, for an item the list did not catch
    ImGui.TextDisabled('Item name:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(220))
    local txt = ImGui.InputTextWithHint('##nmsItem', 'exact item name', state.itemInput or '')
    if type(txt) == 'string' then state.itemInput = txt end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(70))
    local htxt = ImGui.InputTextWithHint('##nmsHandle', 'handle', state.handleInput or '')
    if type(htxt) == 'string' then state.handleInput = htxt end
    if ImGui.IsItemHovered() then core.setTooltip('Optional offer handle, as #nms list prints it.') end
    local item = trim(state.itemInput)
    local handle = trim(state.handleInput)
    for _, action in ipairs(ACTIONS) do
        ImGui.SameLine()
        local disabled = item == '' or (action == 'destroy' and not cfg.armDestroy) or (action == 'pass' and passTo == '')
        if disabled then ImGui.BeginDisabled() end
        local label = action:sub(1, 1):upper() .. action:sub(2)
        if ImGui.SmallButton(label .. '##nmsMan' .. action) then
            runOn(target, { sub = 'loot', action = action, item = item, handle = handle ~= '' and handle or nil, player = passTo })
        end
        if disabled then ImGui.EndDisabled() end
    end
end

local function drawLog(colors)
    local MUTED, WARN, ERR = colors.MUTED, colors.WARN, colors.ERR
    if not ImGui.CollapsingHeader('Server replies & log##nmsLog') then return end
    if ImGui.BeginChild('##nmsLogChild', 0, core.px(110), true) then
        if #state.log == 0 then ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(no #nms traffic yet)') end
        for _, e in ipairs(state.log) do
            local c = MUTED
            if e.level == 'warn' then c = WARN elseif e.level == 'error' then c = ERR end
            ImGui.TextColored(c[1], c[2], c[3], c[4], e.time)
            ImGui.SameLine()
            ImGui.TextWrapped(e.text)
        end
    end
    ImGui.EndChild()
end

-- ----------------------------------------------------------------------------
-- Compact window
-- ----------------------------------------------------------------------------
local function rightText(text, c, width)
    local w = nil
    pcall(function() w = ImGui.CalcTextSize(text) end)
    if type(w) == 'number' then ImGui.SameLine(width - w) else ImGui.SameLine() end
    ImGui.TextColored(c[1], c[2], c[3], c[4], text)
end

-- One-letter action buttons for a compact offer row. `id` keeps the ImGui
-- ids apart; `target` is the box the item is offered to.
local COMPACT_ACTIONS = { { 'keep', 'K' }, { 'sell', 'S' }, { 'tribute', 'T' }, { 'bank', 'B' }, { 'vault', 'V' }, { 'destroy', 'D' }, { 'pass', 'P' } }
local function drawCompactActions(offer, target, id)
    local passTo = trim(state.passTo)
    for k, a in ipairs(COMPACT_ACTIONS) do
        local action, letter = a[1], a[2]
        if k > 1 then ImGui.SameLine(0, core.px(2)) end
        local disabled = (action == 'destroy' and not cfg.armDestroy) or (action == 'pass' and passTo == '')
        if disabled then ImGui.BeginDisabled() end
        if action == 'destroy' then ImGui.PushStyleColor(ImGuiCol.Button, 0.60, 0.20, 0.20, 1.0) end
        if ImGui.SmallButton(letter .. '##nmsC' .. id .. action) then
            runOn(target, { sub = 'loot', action = action, item = offer.name, handle = offer.handle, player = passTo })
        end
        if action == 'destroy' then ImGui.PopStyleColor(1) end
        if disabled then ImGui.EndDisabled() end
        if ImGui.IsItemHovered() then
            if action == 'pass' and passTo == '' then
                core.setTooltip('Pass: set "Pass to" first (right-click menu or the full window).')
            elseif action == 'destroy' and not cfg.armDestroy then
                core.setTooltip('Destroy: tick Arm Destroy first (right-click menu or the full window).')
            else
                core.setTooltip(string.format('#nms %s%s', (logic.nmsLine({ sub = 'loot', action = action, item = offer.name, handle = offer.handle, player = passTo })) or '?', target and (' on ' .. target) or ''))
            end
        end
    end
end

local function drawCompactMenu()
    if not ImGui.BeginPopupContextWindow('##nmsCompactMenu') then return end
    if core.applyWindowScale then core.applyWindowScale('nmsloot_compact') end
    if core.drawWindowMenuItems then
        core.drawWindowMenuItems('nmsloot_compact', { header = false, close = false })
        ImGui.Separator()
    end
    if ImGui.MenuItem('Full window##nmsCompactFull') then cfg.compact = false; core.saveLoadout(true) end
    ImGui.Separator()
    local arm = ImGui.Checkbox('Arm Destroy##nmsCompactArm', cfg.armDestroy)
    if arm ~= cfg.armDestroy then cfg.armDestroy = arm end
    ImGui.TextDisabled('Pass to:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(110))
    local passTxt = ImGui.InputTextWithHint('##nmsCompactPassTo', 'player', state.passTo or '')
    if type(passTxt) == 'string' then state.passTo = passTxt end
    for _, row in ipairs(peerRows()) do
        ImGui.SameLine()
        if ImGui.SmallButton(row.name .. '##nmsCompactPass' .. row.name) then state.passTo = row.name end
    end
    ImGui.Separator()
    drawSettingsBody()
    ImGui.EndPopup()
end

local function drawCompactWindow()
    if not ctrl or not ctrl.show_nmsloot or not cfg.compact then return end
    local c = core.colors or {}
    local GOOD  = c.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    local WARN  = c.WARN or { 0.95, 0.75, 0.30, 1.0 }
    local MUTED = c.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    local ARC   = c.ARC or { 0.30, 0.80, 1.00, 1.0 }
    local GOLD  = c.GOLD or { 1.0, 0.70, 0.54, 1.0 }
    local W = core.px(COMPACT_WIDTH)

    core.pushTheme()
    if core.preBeginWindow then core.preBeginWindow('nmsloot_compact') end
    local flags = ImGuiWindowFlags.AlwaysAutoResize
    if core.windowFlags then flags = core.windowFlags('nmsloot_compact', flags) end
    local open, draw = ImGui.Begin('NMS Loot###TriuneNmsLootCompact', ctrl.show_nmsloot, flags)
    if open and draw and core.postBeginWindow then core.postBeginWindow('nmsloot_compact') end
    local function preEnd()
        if core.preEndWindow then core.preEndWindow('nmsloot_compact', false, { name = 'NMS Loot compact window', onClose = function() ctrl.show_nmsloot = false end }) end
    end
    if not open then
        ctrl.show_nmsloot = false
        preEnd()
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if draw then
        drawCompactMenu()

        -- Line 1: LOOTER tag, holder, offers waiting on the right
        local tag, tagC, holder
        if state.looter == nil then
            tag, tagC, holder = 'LOOTER', WARN, 'unknown'
        elseif state.looter == '' then
            tag, tagC, holder = 'LOOTER', MUTED, 'nobody'
        elseif isMe(state.looter) then
            tag, tagC, holder = 'LOOTER', GOOD, state.looter .. ' (you)'
        else
            tag, tagC, holder = 'LOOTER', ARC, state.looter
        end
        ImGui.TextColored(tagC[1], tagC[2], tagC[3], tagC[4], tag)
        ImGui.SameLine()
        ImGui.Text(holder)
        if ImGui.IsItemHovered() and state.looter ~= nil then core.setTooltip(string.format('%s ago via %s', fmtAge(nowSec() - state.looterAt), tostring(state.looterFrom or '?'))) end
        local waiting = state.offerCount ~= nil and state.offerCount or #state.offers
        local right = state.pending and ('#nms ' .. tostring(state.pending.spec.sub) .. '...') or string.format('%d offer%s', waiting, waiting == 1 and '' or 's')
        rightText(right, state.pending and WARN or (waiting > 0 and GOLD or MUTED), W)

        -- Line 2: one chip per box; the holder is lit; click = claim there
        local me = myName()
        local chips = { { name = me ~= '' and me or 'me', isSelf = true } }
        for _, row in ipairs(peerRows()) do
            if row.online then chips[#chips + 1] = { name = row.name, isSelf = false } end
        end
        for k, chip in ipairs(chips) do
            if k > 1 then ImGui.SameLine(0, core.px(3)) end
            local isHolder = state.looter ~= nil and state.looter ~= '' and lower(state.looter) == lower(chip.name)
            if isHolder then
                ImGui.PushStyleColor(ImGuiCol.Button, GOOD[1] * 0.45, GOOD[2] * 0.45, GOOD[3] * 0.45, 1.0)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, GOOD[1] * 0.55, GOOD[2] * 0.55, GOOD[3] * 0.55, 1.0)
            end
            if ImGui.SmallButton(chip.name .. '##nmsChip' .. chip.name) and not isHolder then
                runOn(chip.isSelf and nil or chip.name, { sub = 'claim' })
            end
            if isHolder then ImGui.PopStyleColor(2) end
            if ImGui.IsItemHovered() then core.setTooltip(isHolder and (chip.name .. ' holds the active looter slot.') or ('Claim the active looter slot on ' .. chip.name .. '.')) end
        end

        -- Offers: the first cfg.compactRows of whoever the full window views
        local target = state.view
        local offers = state.offers
        if target and not isMe(target) then
            local rec = peerRecord(target, false)
            offers = rec and rec.offers or {}
        else
            target = nil
        end
        if #offers > 0 then
            ImGui.Separator()
            if target then ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'offered to ' .. target) end
            local shown = math.min(#offers, math.max(1, cfg.compactRows or 4))
            for i = 1, shown do
                local o = offers[i]
                local label = o.name .. (o.qty and (' x' .. o.qty) or '')
                if #label > 22 then label = label:sub(1, 21) .. '~' end
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], label)
                if ImGui.IsItemHovered() then core.setTooltip(o.line or o.name) end
                ImGui.SameLine(W - core.px(7 * 21))
                drawCompactActions(o, target, i)
            end
            if #offers > shown then ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('+%d more (Full window)', #offers - shown)) end
        end

        -- Buttons
        ImGui.Separator()
        if ImGui.SmallButton('Claim##nmsCClaim') then sendNms({ sub = 'claim' }, nil) end
        if ImGui.IsItemHovered() then core.setTooltip('#nms claim here') end
        ImGui.SameLine()
        if ImGui.SmallButton('Status##nmsCStatus') then sendNms({ sub = 'status' }, nil) end
        ImGui.SameLine()
        if ImGui.SmallButton('List##nmsCList') then runOn(target, { sub = 'list' }) end
        if ImGui.IsItemHovered() then core.setTooltip('#nms list' .. (target and (' on ' .. target) or '')) end
        ImGui.SameLine()
        if ImGui.SmallButton('Coin##nmsCCoin') then runOn(target, { sub = 'loot', action = 'coin' }) end
        if ImGui.IsItemHovered() then core.setTooltip('#nms loot coin' .. (target and (' on ' .. target) or '')) end
        ImGui.SameLine()
        local echoLabel = state.echo == nil and 'Echo ?' or (state.echo and 'Echo on' or 'Echo off')
        if ImGui.SmallButton(echoLabel .. '##nmsCEcho') then sendNms({ sub = 'echo', on = state.echo ~= true }, nil) end
        if ImGui.IsItemHovered() then core.setTooltip('Toggle loot echo (#nms echo on|off).') end
        ImGui.SameLine()
        if ImGui.SmallButton('Full##nmsCFull') then cfg.compact = false; core.saveLoadout(true) end
        if ImGui.IsItemHovered() then core.setTooltip('Open the full NMS Loot window.') end
    end
    preEnd()
    ImGui.End()
    core.popTheme()
end

local function drawWindow()
    if not ctrl or not ctrl.show_nmsloot or cfg.compact then return end
    local c = core.colors or {}
    local colors = {
        GOOD  = c.GOOD or { 0.40, 0.85, 0.50, 1.0 },
        WARN  = c.WARN or { 0.95, 0.75, 0.30, 1.0 },
        ERR   = c.ERR or { 0.95, 0.40, 0.40, 1.0 },
        MUTED = c.MUTED or { 0.55, 0.60, 0.65, 1.0 },
        ARC   = c.ARC or { 0.30, 0.80, 1.00, 1.0 },
        GOLD  = c.GOLD or { 1.0, 0.70, 0.54, 1.0 },
    }

    core.pushTheme()
    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(core.px(720), core.px(520), ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('nmsloot')
    local open, draw = ImGui.Begin('Triune NMS Loot###TriuneNmsLoot', ctrl.show_nmsloot, core.windowFlags and core.windowFlags('nmsloot', windowFlags) or windowFlags)
    if not open then
        ctrl.show_nmsloot = false
        if core.preEndWindow then core.preEndWindow('nmsloot', false) end
        ImGui.End()
        core.popTheme()
        core.saveLoadout(true)
        return
    end
    if not draw then
        if core.preEndWindow then core.preEndWindow('nmsloot', false) end
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('nmsloot')

    if ImGui.BeginPopupContextWindow('##nmsContextMenu') then
        if core.applyWindowScale then core.applyWindowScale('nmsloot') end
        if core.drawWindowMenuItems then
            core.drawWindowMenuItems('nmsloot', { header = false, close = false })
            ImGui.Separator()
        end
        drawSettingsBody()
        ImGui.EndPopup()
    end

    ImGui.TextColored(colors.ARC[1], colors.ARC[2], colors.ARC[3], colors.ARC[4], 'NMS LOOT')
    ImGui.SameLine()
    ImGui.TextDisabled('| Active looter slot across your boxes & personal loot offers')
    ImGui.SameLine()
    if ImGui.SmallButton('Compact##nmsToCompact') then cfg.compact = true; core.saveLoadout(true) end
    if ImGui.IsItemHovered() then core.setTooltip('Switch to the compact window (right-click it or press Full to come back).') end
    ImGui.Separator()
    ImGui.Dummy(0, core.px(2))
    drawStatusLine(colors)
    ImGui.Dummy(0, core.px(4))
    drawBoxTable(colors)
    ImGui.Dummy(0, core.px(4))
    ImGui.Separator()
    drawOffers(colors)
    ImGui.Dummy(0, core.px(4))
    drawLog(colors)

    if core.preEndWindow then core.preEndWindow('nmsloot', false) end
    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.openWindow(val)
    refresh()
    if not ctrl then return end
    if val == nil then val = not ctrl.show_nmsloot end
    ctrl.show_nmsloot = (val == true)
    core.saveLoadout(true)
end

function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_nmsloot == nil then ctrl.show_nmsloot = false end
    state.pending = nil
    state.peers = {}
    state.me = nil
    state.net.unsubs = {}
    state.net.subGen = -1
    state.net.lastBroadcastAt = -1e9
    state.net.lastWhoReplyAt = -1e9
    state.net.dirty = false
    state.lastPollAt = nowSec()
    state.initQuery = true
    cfg.armDestroy = false
    registerEvents()
    ensureSubscriptions()
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.announce ~= nil then cfg.announce = (s.announce == true) end
    if s.statusOnInit ~= nil then cfg.statusOnInit = (s.statusOnInit == true) end
    if s.acceptRemote ~= nil then cfg.acceptRemote = (s.acceptRemote == true) end
    if tonumber(s.pollSec) then cfg.pollSec = math.max(0, math.min(300, math.floor(tonumber(s.pollSec)))) end
    if s.compact ~= nil then cfg.compact = (s.compact == true) end
    if tonumber(s.compactRows) then cfg.compactRows = math.max(1, math.min(COMPACT_ROWS_MAX, math.floor(tonumber(s.compactRows)))) end
end

function plugin.onSaveSettings()
    return { announce = cfg.announce == true, statusOnInit = cfg.statusOnInit == true, acceptRemote = cfg.acceptRemote == true, pollSec = cfg.pollSec or 0,
        compact = cfg.compact == true, compactRows = cfg.compactRows or 4 }
end

function plugin.onDestroy()
    unregisterEvents()
    dropSubscriptions()
    state.pending = nil
end

function plugin.onTick()
    if not core then return end
    refresh()
    tick()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    drawWindow()
    drawCompactWindow()
end

-- Settings -> Windows row for the compact window: open = window shown in
-- compact mode; opening it switches to compact, closing hides the window.
function plugin.isCompactOpen()
    return ctrl ~= nil and ctrl.show_nmsloot == true and cfg.compact == true
end

function plugin.setCompactOpen(v)
    refresh()
    if not ctrl then return end
    if v then
        cfg.compact = true
        ctrl.show_nmsloot = true
    else
        ctrl.show_nmsloot = false
    end
    core.saveLoadout(true)
end

function plugin.onZoned()
    state.me = nil
    state.pending = nil
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'NMS Loot')
    local isWinOpen = (ctrl.show_nmsloot == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##nmsToggleWin', core.px(250), core.px(24)) then
        plugin.openWindow(not isWinOpen)
    end
    ImGui.Spacing()
    ImGui.TextDisabled('Active looter: ' .. looterLabel(state.looter) .. '   Loot echo: ' .. (state.echo == nil and 'unknown' or (state.echo and 'on' or 'off')))
    ImGui.Spacing()
    drawSettingsBody()
end

-- ----------------------------------------------------------------------------
-- Commands
-- ----------------------------------------------------------------------------
local function printHelp()
    for _, line in ipairs(plugin.help) do print(line) end
end

local function printWho()
    say('Active looter: \ag%s\ax%s', looterLabel(state.looter), state.looter ~= nil and string.format(' (%s ago via %s)', fmtAge(nowSec() - state.looterAt), tostring(state.looterFrom)) or '')
    local rows = peerRows()
    if #rows == 0 then
        say('No other boxes on the network.')
        return
    end
    for _, row in ipairs(rows) do
        local rec = row.rec
        say('  %s%s: %s, %d offered%s', row.name, row.online and '' or ' (offline)',
            (state.looter ~= nil and state.looter ~= '' and lower(state.looter) == lower(row.name)) and 'LOOTER' or '-',
            rec and #rec.offers or 0, rec and rec.at > 0 and (', reported ' .. fmtAge(nowSec() - rec.at) .. ' ago') or ', no report yet')
    end
end

function plugin.onCommand(cmd, args)
    if cmd ~= 'nms' and cmd ~= 'nmsloot' then return false end
    refresh()
    local bn = boxnet()
    local function isPeer(name)
        return bn ~= nil and bn.peer ~= nil and bn.peer(name) ~= nil
    end
    local spec, why = logic.parseArgs(args, isPeer)
    if not spec then
        warn('%s', why or 'bad command')
        printHelp()
        return true
    end
    if spec.sub == 'window' then
        plugin.openWindow()
        say('NMS Loot window %s.', ctrl.show_nmsloot and 'OPENED' or 'CLOSED')
    elseif spec.sub == 'compact' or spec.sub == 'full' then
        cfg.compact = (spec.sub == 'compact')
        ctrl.show_nmsloot = true
        core.saveLoadout(true)
        say('NMS Loot %s window.', cfg.compact and 'compact' or 'full')
    elseif spec.sub == 'help' then
        printHelp()
    elseif spec.sub == 'who' then
        askWho()
        printWho()
    else
        if spec.sub == 'status' and not spec.target then printWho() end
        local ok, err = runOn(spec.target, spec)
        if not ok then
            warn('Not sent: %s', tostring(err))
        elseif spec.target then
            say('Asked %s to run #nms %s.', spec.target, (logic.nmsLine(spec)))
        end
    end
    return true
end

plugin.help = {
    '  \ag/ac nms\ax - Toggle the NMS Loot window (active looter across boxes, offered items)',
    '  \ag/ac nms compact | full\ax - Switch between the compact window (looter, box chips, top offers) and the full one',
    '  \ag/ac nms claim [Box]\ax - Take the active looter slot here, or on another box',
    '  \ag/ac nms status | who\ax - Who holds the slot (#nms status here; who = what every box knows)',
    '  \ag/ac nms list [Box] [handle]\ax - #nms list here or on a box (items show in the window)',
    '  \ag/ac nms loot <keep|sell|tribute|bank|vault|destroy> "Item Name" [handle]\ax - Act on one offered item',
    '  \ag/ac nms loot pass <Player> "Item Name" [handle]\ax - Pass an offered item to a player',
    '  \ag/ac nms loot coin [handle]\ax - Take the coin',
    '  \ag/ac nms echo on|off\ax - Print every loot offer to chat, one line per item',
    '  \ag/ac nms <Box> <claim|status|list|echo ...|loot ...>\ax - Run any of the above on another box',
}

-- Exposed for tests
plugin.state = state
plugin.cfg = cfg
plugin.logic = logic
plugin.tick = tick
plugin.processLine = processLine
plugin.runOn = runOn
plugin.finishPending = finishPending
plugin.netHandlers = NET_HANDLERS
plugin.statePayload = statePayload

return plugin
