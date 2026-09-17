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
--   #nms claim                  take the active looter slot
--   #nms status                 who holds it
--   #nms list                   what is offered to you
--   #nms loot <action> "Item"   act on one offered item by name
--   #nms echo on|off            print every loot offer to chat, one line per item
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
-- Server reply parsing. The #nms replies are plain chat lines whose exact
-- wording is not documented. parseLine() (plugin.logic) works from the words
-- the replies must contain - "looter" plus a capitalised name or a "nobody"
-- phrase, "echo" plus on / off, an item link or [Item] on an offer line -
-- rather than exact sentences, and every line it looked at lands in the
-- window's log so a wording change is visible instead of silent. Tighten
-- LOOTER_PATTERNS / NOBODY_PHRASES / parseOffer when the real lines differ.
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

-- Populated by refresh() on every entry point; typed so the language server
-- does not treat them as permanently nil.
local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------
local TAG               = '[NMS Loot]'
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
local SUBS = { claim = true, status = true, list = true, echo = true, loot = true, who = true, help = true, window = true, win = true, ui = true }

-- ----------------------------------------------------------------------------
-- Persisted settings
-- ----------------------------------------------------------------------------
local cfg = {
    announce      = true,   -- chat line when the active looter changes
    statusOnInit  = true,   -- one #nms status when the plugin starts (fills the window)
    pollSec       = 0,      -- periodic #nms status (0 = off)
    acceptRemote  = true,   -- run #nms requests from other boxes (also gated by boxnet trust)
    armDestroy    = false,  -- Destroy buttons stay disabled until this is on (never saved)
}

-- ----------------------------------------------------------------------------
-- Runtime state
-- ----------------------------------------------------------------------------
local state = {
    looter      = nil,      -- who holds the slot: a name, '' for nobody, nil while unknown
    looterAsOf  = 0,        -- os.time() the server said so (shared across boxes to pick the freshest report)
    looterAt    = 0,        -- nowSec() we learned it (for "Ns ago")
    looterFrom  = nil,      -- 'server' or the peer that told us
    echo        = nil,      -- nil unknown, true / false once the server confirmed
    offers      = {},       -- items offered to this character: { name, qty, line, at }
    offersAt    = 0,
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
    if low:find('%f[%a]off%f[%A]') or low:find('disabled', 1, true) or low:find('no longer', 1, true) then return false end
    if low:find('%f[%a]on%f[%A]') or low:find('enabled', 1, true) then return true end
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
function logic.parseLine(raw, capturing)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local plain, items = logic.resolveLinks(raw)
    local low = plain:lower()
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
    if not playerChat and (#items > 0 or capturing == 'list' or (lootish and low:find('offer', 1, true))) then
        local name, qty = logic.parseOffer(plain, items)
        if name then return { kind = 'offer', name = name, qty = qty, plain = plain } end
    end
    return nil
end

-- The text after "#nms " for a request spec, or nil + reason. This is the
-- only place a #nms line is built, so a remote request can never smuggle
-- anything past the fixed sub-command list.
function logic.nmsLine(spec)
    if type(spec) ~= 'table' then return nil, 'no request' end
    local sub = lower(spec.sub)
    if sub == 'claim' or sub == 'status' or sub == 'list' then return sub end
    if sub == 'echo' then
        if spec.on == true then return 'echo on' end
        if spec.on == false then return 'echo off' end
        return nil, 'echo needs on or off'
    end
    if sub == 'loot' then
        local action = lower(spec.action)
        if not ACTION_SET[action] then return nil, 'unknown loot action "' .. tostring(spec.action) .. '"' end
        local item = trim(tostring(spec.item or ''):gsub('"', ''))
        if item == '' then return nil, 'no item name' end
        if #item > ITEM_NAME_MAX then return nil, 'item name too long' end
        return string.format('loot %s "%s"', action, item)
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
    if w and not SUBS[w] and not ACTION_SET[w] then
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
    if w == 'claim' or w == 'status' or w == 'list' or w == 'who' or w == 'help' or w == 'window' then
        return { target = target, sub = w }
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
    elseif ACTION_SET[w] then
        action = w
        first = i + 1
    else
        return nil, 'unknown sub-command "' .. tostring(args[i]) .. '"'
    end
    if not ACTION_SET[action] then return nil, 'usage: /ac nms loot <' .. table.concat(ACTIONS, '|') .. '> "Item Name"' end
    local parts = {}
    for k = first, #args do parts[#parts + 1] = tostring(args[k]) end
    local item = trim(table.concat(parts, ' '):gsub('"', ''))
    if item == '' then return nil, 'usage: /ac nms loot ' .. action .. ' "Item Name"' end
    return { target = target, sub = 'loot', action = action, item = item }
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

local function addOffer(name, qty, line)
    for _, o in ipairs(state.offers) do
        if lower(o.name) == lower(name) then
            o.qty = qty or o.qty
            o.line = line or o.line
            o.at = nowSec()
            state.offersAt = o.at
            return false
        end
    end
    table.insert(state.offers, { name = name, qty = qty, line = line, at = nowSec() })
    while #state.offers > OFFERS_MAX do table.remove(state.offers, 1) end
    state.offersAt = nowSec()
    state.net.dirty = true
    return true
end

local function removeOffer(name)
    local removed = false
    for i = #state.offers, 1, -1 do
        if lower(state.offers[i].name) == lower(name) then
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
local function ownLine(low)
    -- print() output is delivered to events too (\a colour codes stripped).
    return low:find(lower(TAG), 1, true) == 1 or low:find('[boxnet]', 1, true) == 1 or low:find('[triune', 1, true) == 1 or low:find('you say,', 1, true) == 1
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
            table.insert(p.offers, { name = ev.name, qty = ev.qty, line = ev.plain, at = nowSec() })
        else
            if addOffer(ev.name, ev.qty, ev.plain) then logEvent('Offered: ' .. ev.name .. (ev.qty and (' x' .. ev.qty) or '')) end
        end
    elseif ev.kind == 'resolved' then
        if removeOffer(ev.name) then logEvent('Handled: ' .. ev.name) end
    elseif ev.kind == 'empty' then
        if p and lower(p.spec.sub) == 'list' then p.gotEmpty = true else setOffers({}) end
        logEvent('Nothing offered')
    end
end

local function processLine(line)
    if type(line) ~= 'string' or line == '' then return end
    local low = line:lower()
    local p = state.pending
    if not p then
        -- Cheap gate for ordinary chat: the words a #nms line must contain,
        -- or "You <kept/sold/...>" for an item just handled.
        local interesting = low:find('loot', 1, true) or low:find('nms', 1, true) or low:find('offer', 1, true) or low:find('echo', 1, true)
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
        offers[#offers + 1] = { n = o.name, q = o.qty }
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
            offers[#offers + 1] = { name = o.n, qty = tonumber(o.q) }
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
    local spec = { sub = data.sub, action = data.action, item = data.item, on = data.on }
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
    local ok = bn.send(peer.name, MSG_RUN, { sub = spec.sub, action = spec.action, item = spec.item, on = spec.on })
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
    local v = ImGui.Checkbox('Announce looter changes in chat##nmsAnnounce', cfg.announce)
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
    local arm = ImGui.Checkbox('Arm Destroy##nmsArm', cfg.armDestroy)
    if arm ~= cfg.armDestroy then cfg.armDestroy = arm end
    if ImGui.IsItemHovered() then core.setTooltip('Destroy buttons stay disabled until this is ticked.') end

    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if ImGui.BeginTable('NmsLootOffers', 3, tableFlags, ImVec2(0, core.px(150))) then
        ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Qty', ImGuiTableColumnFlags.WidthFixed, core.px(40))
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
            if o.line and ImGui.IsItemHovered() then core.setTooltip(o.line) end
            ImGui.TableSetColumnIndex(1)
            ImGui.Text(o.qty and tostring(o.qty) or '-')
            ImGui.TableSetColumnIndex(2)
            for k, action in ipairs(ACTIONS) do
                if k > 1 then ImGui.SameLine() end
                local disabled = (action == 'destroy' and not cfg.armDestroy)
                if disabled then ImGui.BeginDisabled() end
                if action == 'destroy' then ImGui.PushStyleColor(ImGuiCol.Button, 0.60, 0.20, 0.20, 1.0) end
                local label = action:sub(1, 1):upper() .. action:sub(2)
                if ImGui.SmallButton(label .. '##nmsAct' .. i .. action) then
                    runOn(target, { sub = 'loot', action = action, item = o.name })
                end
                if action == 'destroy' then ImGui.PopStyleColor(1) end
                if disabled then ImGui.EndDisabled() end
                if ImGui.IsItemHovered() then core.setTooltip(string.format('#nms loot %s "%s"%s', action, o.name, target and (' on ' .. target) or '')) end
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
    local item = trim(state.itemInput)
    for _, action in ipairs(ACTIONS) do
        ImGui.SameLine()
        local disabled = item == '' or (action == 'destroy' and not cfg.armDestroy)
        if disabled then ImGui.BeginDisabled() end
        local label = action:sub(1, 1):upper() .. action:sub(2)
        if ImGui.SmallButton(label .. '##nmsMan' .. action) then
            runOn(target, { sub = 'loot', action = action, item = item })
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

local function drawWindow()
    if not ctrl or not ctrl.show_nmsloot then return end
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
end

function plugin.onSaveSettings()
    return { announce = cfg.announce == true, statusOnInit = cfg.statusOnInit == true, acceptRemote = cfg.acceptRemote == true, pollSec = cfg.pollSec or 0 }
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
    '  \ag/ac nms claim [Box]\ax - Take the active looter slot here, or on another box',
    '  \ag/ac nms status | who\ax - Who holds the slot (#nms status here; who = what every box knows)',
    '  \ag/ac nms list [Box]\ax - #nms list here or on a box (items show in the window)',
    '  \ag/ac nms loot <keep|sell|tribute|bank|vault|destroy|pass> "Item Name"\ax - Act on one offered item',
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
