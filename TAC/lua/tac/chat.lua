---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ============================================================================
-- TAC/lua/tac/chat.lua — Triune Chat Windows plugin
-- ============================================================================
-- A chat window replacement: every incoming chat line is captured through one
-- catch-all mq.event, classified into a channel by pattern (the event API
-- hands over no color / filter index, so the text itself decides), kept in a
-- ring buffer, and shown in any number of ImGui chat windows. Each window has
-- tabs; each tab is a filter set (channels + keyword include / exclude) with
-- its own send channel, unread badge and ImGui.ConsoleWidget.
--
-- Facts this design rests on (Phase 0 spike, Sep 2026):
--   * mq.event('#*#', fn, { keepLinks = true }) delivers every line in order,
--     including Triune's / MQ's own print() output. `\a` color codes arrive
--     stripped; `\x7F` + RRGGBB codes arrive raw; item links arrive as
--     \x12 + 77-char payload + name + \x12, player names as \x12 1 Name \x12.
--   * The server abbreviates your melee to a bare number or "miss" per swing,
--     and your spell hits use your name, not "You".
--   * /chat is an EQ command, so the bind is /tacchat (also /ac chat).
--
-- Layout, filters and colors persist per character in
-- config/triune_chat_<Name>.lua. Window visibility is ctrl.show_chat (header
-- button, Window Layout manager, /tacchat).
-- ============================================================================

local plugin = {
    id                 = 'chat',
    name               = 'Chat Windows',
    version            = '1.6.0',
    author             = 'Triune',
    description        = 'Chat window replacement: channel-filtered tabs, multiple windows, colors, timestamps, an input line and keyword filters.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = false,
    uses               = { gamedb = 'Look up in Database entry in the tab menu (item links by name)' },
}

-- Populated by refresh() on every entry point; typed so the language server
-- does not treat them as permanently nil.
local core = nil  ---@type table
local ctrl, ImGui, mq = nil, nil, nil  ---@type table, table, table

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

local GOLD  = { 1.00, 0.70, 0.54, 1 }
local MUTED = { 0.49, 0.56, 0.65, 1 }
local GOOD  = { 0.37, 0.88, 0.64, 1 }
local WARN  = { 1.00, 0.72, 0.30, 1 }
local ERR   = { 0.95, 0.35, 0.35, 1 }

local CONFIG_VERSION = 2
local LINK = string.char(18)              -- \x12 wraps EQ links
local ITEM_LINK_PAYLOAD = 77              -- fixed-width item link body before the item name
local COLOR_ESC = string.char(127)        -- \x7F RRGGBB inline color (MQ output)
local MAX_APPENDS_PER_FRAME = 300

-- ----------------------------------------------------------------------------
-- Channels. Order here is the order in filter editors; `group` bands them.
-- Colors are RRGGBB defaults the user can override per character.
-- ----------------------------------------------------------------------------
local CHANNELS = {
    -- Social
    { id = 'say',        label = 'Say',                    group = 'Social', color = 'E6E6E6' },
    { id = 'npc_say',    label = 'NPC dialogue',           group = 'Social', color = 'BFBFBF' },
    { id = 'tell_in',    label = 'Tells (incoming)',       group = 'Social', color = 'FF66FF' },
    { id = 'tell_out',   label = 'Tells (outgoing)',       group = 'Social', color = 'FFB3FF' },
    { id = 'group',      label = 'Group',                  group = 'Social', color = '66CCFF' },
    { id = 'guild',      label = 'Guild',                  group = 'Social', color = '5CFF5C' },
    { id = 'raid',       label = 'Raid',                   group = 'Social', color = 'FF9966' },
    { id = 'ooc',        label = 'Out of character',       group = 'Social', color = '5FD3BC' },
    { id = 'auction',    label = 'Auction',                group = 'Social', color = '33CC33' },
    { id = 'shout',      label = 'Shout',                  group = 'Social', color = 'FF4D4D' },
    { id = 'emote',      label = 'Emotes',                 group = 'Social', color = 'CC99FF' },
    { id = 'channel',    label = 'Chat channels (/join)',  group = 'Social', color = '99CCFF' },
    { id = 'petchat',    label = 'Pet chat',               group = 'Social', color = 'FFCC99' },
    { id = 'servercmd',  label = 'Server commands (#...)', group = 'Social', color = '808080' },
    -- Combat
    { id = 'melee_num',  label = 'Abbreviated melee (numbers / miss)', group = 'Combat', color = 'BFBFBF' },
    { id = 'melee_you',  label = 'Your melee',             group = 'Combat', color = 'FFFFFF' },
    { id = 'melee_others', label = "Others' melee",        group = 'Combat', color = 'A0A0A0' },
    { id = 'melee_taken', label = 'Melee on you',          group = 'Combat', color = 'FF6666' },
    { id = 'crit',       label = 'Critical hits / blasts', group = 'Combat', color = 'FFD700' },
    { id = 'flurry',     label = 'Flurry / rampage / extra attacks', group = 'Combat', color = 'FFA64D' },
    { id = 'pet',        label = 'Your pet combat',        group = 'Combat', color = 'D9B36C' },
    { id = 'spell_you',  label = 'Your spell damage',      group = 'Combat', color = '66B3FF' },
    { id = 'spell_others', label = "Others' spell damage", group = 'Combat', color = '8CA6C0' },
    { id = 'spell_taken', label = 'Spell damage on you',   group = 'Combat', color = 'FF4D4D' },
    { id = 'spell_land', label = 'Spell effect messages',  group = 'Combat', color = '7F9FBF' },
    { id = 'dot',        label = 'Damage over time',       group = 'Combat', color = 'B366FF' },
    { id = 'ds',         label = 'Damage shields',         group = 'Combat', color = 'FF9933' },
    { id = 'heal',       label = 'Heals',                  group = 'Combat', color = '33FF99' },
    { id = 'cast',       label = 'Casting (begin / fizzle / interrupt)', group = 'Combat', color = '99B3CC' },
    { id = 'death',      label = 'Deaths',                 group = 'Combat', color = 'E05A5A' },
    { id = 'resist',     label = 'Resists',                group = 'Combat', color = 'FFCC66' },
    { id = 'combat_msg', label = 'Combat messages (taunt, range, LoS...)', group = 'Combat', color = 'A0A0A0' },
    -- Info
    { id = 'exp',        label = 'Experience',             group = 'Info', color = 'FFFF66' },
    { id = 'loot',       label = 'Loot & money',           group = 'Info', color = 'C2FF66' },
    { id = 'item',       label = 'Item effects & upgrades', group = 'Info', color = 'E6C34A' },
    { id = 'buff',       label = 'Buffs landed',           group = 'Info', color = '66FFCC' },
    { id = 'buff_worn',  label = 'Buffs worn off',         group = 'Info', color = '99CCCC' },
    { id = 'skill',      label = 'Skill ups',              group = 'Info', color = 'FFCC00' },
    { id = 'faction',    label = 'Faction',                group = 'Info', color = 'CCCC99' },
    { id = 'consider',   label = 'Consider',               group = 'Info', color = 'C0C0FF' },
    { id = 'zone',       label = 'Zone & travel',          group = 'Info', color = 'FFFFFF' },
    { id = 'system',     label = 'System / server',        group = 'Info', color = 'FFFF99' },
    { id = 'triune',     label = 'Triune messages',        group = 'Info', color = 'FFB380' },
    { id = 'mq',         label = 'MacroQuest output',      group = 'Info', color = 'B3B3FF' },
    { id = 'unknown',    label = 'Unclassified',           group = 'Info', color = 'D0D0D0' },
}
local CHANNEL_BY_ID = {}
for _, c in ipairs(CHANNELS) do CHANNEL_BY_ID[c.id] = c end

local function channelSet(list)
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    return set
end

-- Filter presets: nil = every channel.
local PRESETS = {
    all    = nil,
    social = { 'say', 'npc_say', 'tell_in', 'tell_out', 'group', 'guild', 'raid', 'ooc', 'auction', 'shout', 'emote', 'channel', 'petchat' },
    combat = { 'melee_you', 'melee_others', 'melee_taken', 'crit', 'flurry', 'pet', 'spell_you', 'spell_others', 'spell_taken', 'spell_land', 'dot', 'ds', 'heal', 'cast', 'death', 'resist', 'combat_msg' },
    loot   = { 'exp', 'loot', 'item', 'skill', 'faction' },
    tells  = { 'tell_in', 'tell_out' },          -- pets are not players: pet chat has its own channel
    triune = { 'triune', 'mq' },
}

-- Channels whose sender is another player (the name on the line is
-- clickable: it opens that person's tab in the Tells window).
local PLAYER_CHANNELS = {}
for _, id in ipairs({ 'say', 'tell_in', 'tell_out', 'group', 'guild', 'raid', 'ooc', 'auction', 'shout', 'emote', 'channel' }) do
    PLAYER_CHANNELS[id] = true
end

-- Send channels for the input line.
local SEND_CHANNELS = {
    { id = 'say',     label = 'Say',     cmd = '/say' },
    { id = 'group',   label = 'Group',   cmd = '/g' },
    { id = 'guild',   label = 'Guild',   cmd = '/gu' },
    { id = 'raid',    label = 'Raid',    cmd = '/rs' },
    { id = 'ooc',     label = 'OOC',     cmd = '/ooc' },
    { id = 'auction', label = 'Auction', cmd = '/auc' },
    { id = 'shout',   label = 'Shout',   cmd = '/shout' },
    { id = 'tell',    label = 'Tell',    cmd = '/tell' },
}
local SEND_BY_ID = {}
for _, s in ipairs(SEND_CHANNELS) do SEND_BY_ID[s.id] = s end

-- ----------------------------------------------------------------------------
-- Config (per character) and runtime state
-- ----------------------------------------------------------------------------
local cfg = {
    version = CONFIG_VERSION,
    timestamps = true,
    maxLines = 2000,
    opacity = 0.92,
    locked = false,
    appendMode = 'text',      -- 'text' (color codes parsed) | 'unformatted'  (classic renderer)
    renderer = 'inline',      -- 'inline' (own renderer, clickable item links) | 'console' (ImGui.ConsoleWidget)
    capture = false,          -- write every line + channel to the capture file
    colors = {},              -- [channel] = 'RRGGBB' overrides
    highlights = {},          -- { { text, color = 'RRGGBB', beep, flash }, ... }
    muted = {},               -- [lowercase sender] = true
    windows = {},             -- { id, title, open, opacity, tabs = { { id, name, channels, include, exclude, send, tellTarget, logToFile } } }
    tellPopouts = false,      -- incoming tells open the Tells window (one window, a tab per person)
    enterFocus = true,        -- Enter (when not typing anywhere) focuses the chat input; Enter sends and hands the keys back
    recentTells = {},         -- last few people you exchanged tells with, most recent first
}
local RECENT_TELLS = 5

local chatCommand -- defined with the commands below; the settings pages call it
local saveConfig  -- defined with the config persistence below (only the tick / destroy paths call it)
local noteTeller, openTellTab -- defined with distribution below; ingest calls them
local resolveTellTarget      -- defined with ingest below; the classifier's self-echo tells use it
local uniqueId    -- defined with the window management below; the Tells window uses it

local rt = {
    queue = {},               -- raw lines from the event callback, drained in onTick
    ring = nil,               -- classified entries
    tabs = {},                -- runtime state keyed by window.id .. '/' .. tab.id
    me = '',
    pets = {},                -- [name] = true for my pets
    namesAt = 0,
    stats = { total = 0, unknown = 0, curSec = 0, curCount = 0, peak = 0, drainMaxMs = 0, appendErr = nil, cbCalls = 0,
              lastEventAt = 0, lastTickAt = 0, lastDrawAt = 0 },
    unknownRecent = {},       -- last unclassified lines for pattern building
    recentLinks = {},         -- last item links seen: { name, raw, id }
    sentTells = {},           -- { to, text } for tells sent from here, matched against echoed lines
    lastTellTo = nil,         -- last recipient of a tell sent from here
    lastTellFrom = nil,       -- last player who sent a tell
    tellReq = nil,            -- player name clicked in a line: opened as a Tells tab before the next draw
    selectReq = nil,          -- [window id] = tab id to select programmatically on the next draw
    trace = nil,              -- draw trace ring (/tacchat trace on); off by default: trace() is a no-op
    editor = nil,             -- { kind = 'tab'|'global', winId, tabId } while the settings window is open
    tabMenuReq = nil,         -- { win, ti } set while drawing tabs, opened at window scope
    fonts = nil,              -- probed once: { list = { font objects }, err = '...' }
    echoAt = 0,
    ctxEntry = nil,           -- entry under the line context menu
    lastBeepAt = 0,
    newTabName = '',
    newWindowName = '',
    hlInput = '',
    hlColor = 'FFD700',
    kwInput = { include = '', exclude = '' },
    muteInput = '',
    colorInput = {},
    captureFile = nil,
    capturePath = nil,
    reportPath = nil,
    input = '',               -- legacy; the input draft lives per tab in rt.tabs[key].input
    inputRefocus = 0,
    history = {},
    historyIdx = 0,
    focusRequested = false,
    drawEvents = true,        -- ask MQ for our event every frame (see pumpEvents); off if the binding refuses
    drawPumped = 0,           -- lines that arrived through the per-frame pump
    focusKey = nil,           -- tab key the focus request is for (nil: the first input drawn)
    lastInputKey = nil,       -- tab key of the input that last had keyboard focus
    echo = nil,
    configPath = nil,
    dirty = false,
    lastSave = 0,
}

-- ----------------------------------------------------------------------------
-- Ring buffer (no table.remove(t, 1): indices only ever grow)
-- ----------------------------------------------------------------------------
local function newRing(cap)
    return { first = 1, last = 0, items = {}, cap = cap }
end

local function ringPush(ring, item)
    ring.last = ring.last + 1
    ring.items[ring.last] = item
    item.id = ring.last
    while ring.last - ring.first + 1 > ring.cap do
        ring.items[ring.first] = nil
        ring.first = ring.first + 1
    end
end

local function ringCount(ring)
    return ring.last - ring.first + 1
end

-- ----------------------------------------------------------------------------
-- Text helpers
-- ----------------------------------------------------------------------------
-- Strips \x7F RRGGBB inline color codes.
local function stripColors(s)
    return (s:gsub(COLOR_ESC .. '%x%x%x%x%x%x', ''))
end

-- Converts \x7F RRGGBB codes to \a#RRGGBB, which the console widget parses.
local function convertColors(s)
    return (s:gsub(COLOR_ESC .. '(%x%x%x%x%x%x)', '\a#%1'))
end

-- Replaces links with readable text. Item links become the item name (the
-- game already wraps them in brackets); player links become the bare name and
-- are recorded in `players` so the classifier can tell a linked player apart
-- from a bare NPC / pet name.
local function resolveLinks(s)
    local players = {}
    if not s:find(LINK, 1, true) then return s, players end
    local out = s:gsub(LINK .. '(.-)' .. LINK, function(payload)
        if payload:sub(1, 1) == '1' and #payload > 1 and #payload < ITEM_LINK_PAYLOAD then
            local name = payload:sub(2)
            players[name] = true
            return name
        end
        if #payload > ITEM_LINK_PAYLOAD then
            return payload:sub(ITEM_LINK_PAYLOAD + 1)
        end
        return payload
    end)
    return out, players
end

local function escapeLine(s)
    return (s:gsub('[%c\127]', function(c)
        if c == LINK then return '<LINK>' end
        return string.format('\\x%02X', c:byte())
    end))
end

local function trim(s)
    return (tostring(s or ''):match('^%s*(.-)%s*$'))
end

-- Status text shown above the input line for a few seconds.
local function echo(msg)
    rt.echo = msg
    rt.echoAt = os.time()
end

-- Draw trace (/tacchat trace on): the last TRACE_MAX scope steps, dumped to
-- logs/tac_chat_trace_<Name>.txt when a draw error happens. Takes a format
-- string plus arguments so nothing is built while the trace is off.
local TRACE_MAX = 300
local function trace(fmt, ...)
    local t = rt.trace
    if not t then return end
    t.n = t.n + 1
    local step = (select('#', ...) > 0) and string.format(fmt, ...) or fmt
    t.steps[(t.n - 1) % TRACE_MAX + 1] = string.format('%d %s', t.frame or 0, step)
end

local function traceDump(reason)
    local t = rt.trace
    if not t then return end
    local dir
    pcall(function()
        local pth = mq.TLO.MacroQuest.Path('logs')()
        if pth and pth ~= '' then dir = tostring(pth) end
    end)
    dir = (dir or (mq and mq.configDir) or 'config'):gsub('[/\\]+$', '')
    local name = 'Default'
    pcall(function() local n = mq.TLO.Me.CleanName(); if n and n ~= '' then name = tostring(n) end end)
    local path = string.format('%s/tac_chat_trace_%s.txt', dir, name)
    local f = io.open(path, 'w')
    if not f then return end
    f:write('-- Triune Chat draw trace, ' .. os.date() .. '\n-- frame step (oldest first)\n')
    local count = math.min(t.n, TRACE_MAX)
    for i = t.n - count + 1, t.n do
        f:write(t.steps[(i - 1) % TRACE_MAX + 1] or '', '\n')
    end
    f:write('-- ERROR: ' .. tostring(reason) .. '\n')
    f:close()
    print('\ay[Triune Chat]\ax draw trace written to ' .. path)
end

-- Runs a draw function under pcall so an error inside an ImGui scope never
-- escapes past the matching End*: the caller still closes the scope. The
-- first error is printed once; the latest is kept for the status row and
-- /tacchat stats. A failing window drops to safe mode (one pane, default
-- font) on the next frame.
local function guarded(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        rt.stats.drawErr = string.format('%s: %s', tostring(where), tostring(err))
        rt.frameFailed = true
        trace('ERROR %s', rt.stats.drawErr)
        if not rt.stats.drawErrShown then
            rt.stats.drawErrShown = true
            print('\ar[Triune Chat]\ax draw error (window kept alive): ' .. rt.stats.drawErr)
            -- The diagnostics themselves must never throw out of the guard.
            local okDiag, errDiag = pcall(function()
                traceDump(rt.stats.drawErr)
                -- Remembered so the next start comes up in safe mode; the
                -- tick saver writes it (no file I/O on the draw thread).
                if not cfg.lastDrawFailed then
                    cfg.lastDrawFailed = true
                    rt.dirty = true
                end
            end)
            if not okDiag then rt.stats.diagErr = tostring(errDiag) end
        end
    end
    return ok
end

-- ----------------------------------------------------------------------------
-- Classifier. classify(raw, ctx) -> { channel, sender, outgoing, text, isPlayer }
-- ctx = { me = 'Name', pets = { [name] = true } } (both optional).
-- `text` is the readable line (colors stripped, links resolved).
-- ----------------------------------------------------------------------------
local MELEE_VERBS = channelSet({
    'hit', 'hits', 'slash', 'slashes', 'pierce', 'pierces', 'crush', 'crushes', 'bite', 'bites',
    'claw', 'claws', 'strike', 'strikes', 'slice', 'slices', 'gore', 'gores', 'punch', 'punches',
    'shoot', 'shoots', 'bash', 'bashes', 'kick', 'kicks', 'backstab', 'backstabs', 'frenzy', 'frenzies',
    'maul', 'mauls', 'smash', 'smashes', 'sting', 'stings', 'burn', 'burns', 'rend', 'rends',
})

local PET_PHRASES = {
    '^Attacking ', '^Waiting for your order', '^Following you', '^Guarding ', '^Sitting down',
    '^Changing my target', '^Sorry, Master', '^At your service', '^I have no target', '^Master, ',
    '^I am unable to', '^That is not a legal target', '^Stopping', '^Sitting', '^Standing',
}

local SPELL_LAND_PATTERNS = {
    ' is struck by ', "'s body is torn", ' staggers as ', ' is covered in ', ' was chilled to the bone',
    ' is enveloped in ', ' is engulfed', ' shivers', ' writhes', ' is stricken', ' is blinded', ' is snared',
    ' begins to burn', ' is rooted', ' is mesmerized', ' is slowed', ' is pierced by', ' is surrounded by',
    ' looks weaker', ' is hobbled', ' is drained', ' is consumed by', ' is bathed in', ' has been struck',
    ' is chilled', ' is frozen', ' burns as ', ' is wracked', ' falls to the ground', ' staggers',
}

local COMBAT_MSG_PATTERNS = {
    '^You taunt ', '^You have failed to taunt', '^Your attempt to disarm', '^Your attempt at begging',
    '^Your target is too far away', '^You cannot see your target', "^You can't see your target",
    '^You must first click on the being', '^Target cleared%.', '^Could not find valid target',
    '^You avoid the stunning blow', ' regains? concentration and continues casting', '^You regain your concentration',
    '^The Spellshield absorbed', '^You twincast ', '^You are stunned', '^You are no longer stunned',
    '^You are too far away', '^Your target is out of range', '^You cannot attack', '^You have been interrupted',
    ' is too far away, get closer', '^You need to be closer', '^You must be standing', '^You are unable to',
    ' has been knocked unconscious', '^You cannot disarm', '^You are not able to', '^You must first target',
}

local CONSIDER_PATTERNS = {
    ' scowls at you, ready to attack', ' glares at you threateningly', ' glowers at you dubiously',
    ' looks your way apprehensively', ' regards you indifferently', ' judges you amiably', ' kindly considers you',
    ' looks upon you warmly', ' regards you as an ally', '^This creature would take', '^What would you like your tombstone',
    '^You could probably win', '^Looks like a ', "^It looks like it's going to be a tough", '^You would need some help',
}

local BUFF_WORN_PATTERNS = {
    '^Your (.-) spell has worn off', '^Your song ends', '^Your rage subsides', '^The tingling fades', '^Your blood cools',
    '^Your bloodlust cools', ' fades away%.$', ' has worn off%.$', ' wears off%.$', '^Your .- fades%.$', '^You feel .- fade',
    '^You are no longer ', '^Your .- has faded', '^The .- fades%.$', '^Your .- wears off',
    -- disease / poison cure and spell-end messages
    '^Your fever has broken', '^Your .- has been cured', '^You feel better', '^The poison .- (has been|is) (removed|purged)',
    '^Your skin returns to normal', '^You feel the .- (leave|dissipate)', '^Your mind clears', '^You regain your ',
}

local SYSTEM_PATTERNS = {
    '^%[SERVER', '^Server:', '^%[Broadcast%]', '^GUILD MOTD', '^MOTD', '^Welcome to ', '^You have been summoned',
    -- tell / friend / chat-service replies about other players
    ' is not online at this time', ' is not currently online', '^That player is not online', ' has gone offline',
    ' has come online', ' is already in your ', '^You are not in a guild', '^You must be in a group',
    '^Your (.-) is now ', '^Auto%-', '^The server ', '^Your bind point', '^You have set your ', '^Cannot bind ',
    '^Consent ', '^You are now ', '^You are no longer anonymous', '^Your inventory', '^Attack mode changed',
}

local MQ_PREFIXES = { '[Nav]', '[MQ2', '[MQ]', '[Lua]', '[TAC', '[Triune' }

local function matchAny(text, patterns)
    for _, p in ipairs(patterns) do
        if text:find(p) then return true end
    end
    return false
end

-- Pet names sometimes arrive with a numeric suffix ("Spinevenom000 performs
-- an exceptional heal!"), so the check ignores trailing digits.
local function isMyPet(name, ctx)
    if name == nil or ctx == nil or ctx.pets == nil then return false end
    if ctx.pets[name] == true then return true end
    local bare = name:gsub('%d+$', '')
    return bare ~= name and ctx.pets[bare] == true
end

local function isMe(name, ctx)
    return name ~= nil and ctx ~= nil and ctx.me ~= nil and ctx.me ~= '' and name == ctx.me
end

-- Owner tag on pet lines: "Spinevenom (Owner: Genro) hit ..."
local function ownerOf(name)
    local pet, owner = name:match('^(.-) %(Owner: (.-)%)$')
    return pet, owner
end

local function result(channel, sender, text, outgoing, isPlayer)
    return { channel = channel, sender = sender, text = text, outgoing = outgoing == true, isPlayer = isPlayer == true }
end

-- Item links found in a line, in order: { name = 'Item Name' }.
local function extractItemLinks(raw)
    local out = {}
    for payload in raw:gmatch(LINK .. '(.-)' .. LINK) do
        if #payload > ITEM_LINK_PAYLOAD and payload:sub(1, 1) ~= '1' then
            out[#out + 1] = { name = payload:sub(ITEM_LINK_PAYLOAD + 1), payload = payload }
        end
    end
    return out
end

local function classify(raw, ctx)
    ctx = ctx or {}
    local text, players = resolveLinks(stripColors(raw))
    if text == '' then return result('unknown', nil, text) end

    local function player(name) return players[name] == true end
    local function petish(name, msg)
        if isMyPet(name, ctx) then return true end
        if msg and (msg:find("Master%.?'?$") or matchAny(msg, PET_PHRASES)) then return true end
        return false
    end

    -- MQ / Triune output (arrives through the same event as game text)
    if text:sub(1, 1) == '[' then
        if text:find('^%[Triune') or text:find('^%[TAC') then return result('triune', nil, text) end
        if text:find('^%[NMS%]') then return result('loot', nil, text) end
        for _, p in ipairs(MQ_PREFIXES) do
            if text:sub(1, #p) == p then return result('mq', nil, text) end
        end
    end
    if text:find('^Cannot bind ') or text:find('^Could not load ') or text:find('^Unknown command') then
        return result('mq', nil, text)
    end

    -- Abbreviated melee: the server sends a bare number or "miss" per swing
    if text:find('^%d+$') or text == 'miss' then return result('melee_num', nil, text) end

    -- Tells / social (checked before combat so quoted text cannot fool the verbs)
    -- The tell sender may not contain a quote: a say / shout / group line
    -- quoting a tell ("Bob says, 'Joe tells you, ...'") would otherwise be
    -- classified as a tell from "Bob says, 'Joe".
    local s, msg
    s, msg = text:match("^([^']-) tells you, '(.*)$")
    if s then
        if petish(s, msg) then return result('petchat', s, text, false, false) end
        -- With the game's tell windows on, your own tells come back as
        -- "<You> tells you, '...'": that is outgoing, and the recipient is
        -- not in the line (ingest fills it in from what was sent).
        if isMe(s, ctx) then
            local r = result('tell_out', nil, text, true)
            r.selfEcho = true
            return r
        end
        return result('tell_in', s, text, false, player(s))
    end
    s, msg = text:match("^You told (.-), '(.*)$")
    if s then return result('tell_out', s, text, true) end
    if text:find("^You tell your party, '") then return result('group', ctx.me, text, true) end
    s = text:match("^(.-) tells the group, '")
    if s then return result('group', s, text, false, player(s)) end
    if text:find("^You say to your guild, '") then return result('guild', ctx.me, text, true) end
    s = text:match("^(.-) tells the guild, '")
    if s then return result('guild', s, text, false, player(s)) end
    if text:find("^You tell your raid, '") then return result('raid', ctx.me, text, true) end
    s = text:match("^(.-) tells the raid, '")
    if s then return result('raid', s, text, false, player(s)) end
    if text:find("^You say out of character, '") then return result('ooc', ctx.me, text, true) end
    s = text:match("^(.-) says out of character, '")
    if s then return result('ooc', s, text, false, player(s)) end
    if text:find("^You auction, '") then return result('auction', ctx.me, text, true) end
    s = text:match("^(.-) auctions, '")
    if s then return result('auction', s, text, false, player(s)) end
    if text:find("^You shout, '") then return result('shout', ctx.me, text, true) end
    s = text:match("^(.-) shouts, '")
    if s then return result('shout', s, text, false, player(s)) end
    s = text:match("^You tell ([%w_]+:%d+), '")
    if s then return result('channel', ctx.me, text, true) end
    s = text:match("^(.-) tells ([%w_]+:%d+), '")
    if s then return result('channel', s, text, false, player(s)) end
    if text:find("^You say, '#") then return result('servercmd', ctx.me, text, true) end
    if text:find("^You say, '") then return result('say', ctx.me, text, true) end
    s = text:match("^(.-) says, '")
    if s then return result('say', s, text, false, player(s)) end
    s = text:match("^(.-) says '")
    if s then return result('npc_say', s, text, false, false) end

    -- Combat
    s = text:match('^(.-) scores a critical hit! %(%d+%)$') or text:match('^(.-) delivers a critical blast!')
    if s then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        return result('crit', s, text, isMe(s, ctx))
    end
    if text:find('^You deliver a critical blast!') then return result('crit', ctx.me, text, true) end
    s = text:match('^(.-) performs an exceptional heal!')
    if s then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        return result('heal', s, text)
    end
    if text:find('^You deliver an exceptional heal!') then return result('heal', ctx.me, text, true) end

    s = text:match('^(.-) hit (.-) for %d+ points? of non%-melee damage')
    if s then
        local pet, owner = ownerOf(s)
        if pet and isMe(owner, ctx) then return result('pet', pet, text) end
        if pet then return result('spell_others', pet, text) end
        if isMe(s, ctx) then return result('spell_you', s, text, true) end
        if isMyPet(s, ctx) then return result('pet', s, text) end
        local target = text:match('^.- hit (.-) for %d+ points? of non%-melee damage')
        if target == 'YOU' or target == 'you' or isMe(target, ctx) then return result('spell_taken', s, text) end
        return result('spell_others', s, text)
    end
    if text:find('^You were hit by non%-melee for') then return result('spell_taken', nil, text) end
    s = text:match('^(.-) was hit by non%-melee for')
    if s then return result('spell_others', s, text) end
    s = text:match('^(.-) has taken %d+ points? of damage from your')
    if s then return result('dot', ctx.me, text, true) end
    s = text:match('^(.-) has taken %d+ points? of damage from ')
    if s then return result('dot', s, text) end
    if text:find('^You have taken %d+ points? of damage') then return result('dot', nil, text) end

    s = text:match('^(.-) has healed (.-) for %d+')
    if s then
        local pet, owner = ownerOf(s)
        if pet and isMe(owner, ctx) then return result('pet', pet, text) end
        return result('heal', pet or s, text, isMe(s, ctx))
    end
    if text:find('^You have been healed for') or text:find('^You have healed') or text:find(' has been healed for') then
        return result('heal', nil, text)
    end

    if text == 'YOU are burned!' or text:find('^YOU are ') then return result('ds', nil, text) end
    s = text:match('^(.-) was burned%.$')
    if s then return result('ds', s, text) end
    s = text:match('^(.-) is burned by ') or text:match('^(.-) is pierced by ') or text:match('^(.-) is tormented by ')
    if s then return result('ds', s, text) end

    s = text:match('^(.-) begins to cast a spell%.$')
    if s then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        return result('cast', s, text)
    end
    if text:find('^You begin casting ') or text:find('^Your spell fizzles') or text:find('^Your casting has been interrupted')
        or text:find('^Your spell is interrupted') or text:find('^Your spell did not take hold') or text:find('^Your spell would not have taken hold')
        or text:find('^Your target is immune') or text:find('^Your target cannot be mezzed') or text:find('^Insufficient Mana')
        or text:find('^You must first memorize') or text:find('^You cannot cast') or text:find('^Spell recast time not yet met')
        or text:find('^Your target has no mana') or text:find('^You .- interrupted') then
        return result('cast', ctx.me, text, true)
    end

    s = text:match('^(.-) executes a FLURRY of attacks') or text:match('^(.-) goes on a RAMPAGE!')
    if s then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        return result('flurry', s, text, isMe(s, ctx))
    end
    if text:find('^You unleash a flurry') or text:find("^You strike through your opponent's defenses") or text:find('You gain %d+ additional attack')
        or text:find('^You go on a RAMPAGE') or text:find('^You execute a FLURRY') then
        return result('flurry', ctx.me, text, true)
    end

    if text:find('^You have slain ') then return result('death', ctx.me, text, true) end
    s = text:match('^(.-) has been slain by (.-)!$')
    if s then return result('death', s, text) end
    if text:find('^You have been slain') or text:find('^You died%.') then return result('death', nil, text) end
    if text:find(' has been slain%.$') or text:find(' died%.$') then return result('death', nil, text) end

    if text:find('^You resist the ') or text:find(' resisted your ') or text:find('^Your target resisted') or text:find(' avoided your ')
        or text:find('^You avoid the ') or text:find('^You resist ') then
        return result('resist', nil, text)
    end

    -- Long-form melee (your own swings are usually abbreviated on this server)
    local verb, target, dmg = text:match('^You (%a+) (.-) for (%d+) points? of damage')
    if verb and MELEE_VERBS[verb] then return result('melee_you', ctx.me, text, true) end
    if text:find('^You try to %a+ .-, but miss!') then return result('melee_you', ctx.me, text, true) end
    s, verb, target = text:match('^(.-) (%a+) (YOU) for %d+ points? of damage')
    if s and MELEE_VERBS[verb] then return result('melee_taken', s, text) end
    s = text:match('^(.-) tries to %a+ YOU, but misses!')
    if s then return result('melee_taken', s, text) end
    s, verb, target = text:match('^(.-) (%a+) (.-) for %d+ points? of damage')
    if s and MELEE_VERBS[verb] then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        if target == ctx.me then return result('melee_taken', s, text) end
        return result('melee_others', s, text)
    end
    s = text:match('^(.-) tries to %a+ .-, but misses!') or text:match('^(.-) missed ')
    if s then
        if isMyPet(s, ctx) then return result('pet', s, text) end
        return result('melee_others', s, text)
    end

    if matchAny(text, COMBAT_MSG_PATTERNS) then return result('combat_msg', nil, text) end

    -- Info
    if text:find('^You gain ') and text:find('experience') then return result('exp', nil, text) end
    if text:find('^You have gained an ability point') or text:find('^You have gained a level') or text:find('^You have lost a level')
        or text:find('^You gain experience') or text:find('^You have reached level') then
        return result('exp', nil, text)
    end
    if text:find('^You receive ') or text:find('^You have looted') or text:find('^%-%-.- has looted') or text:find('^You split ')
        or text:find(' sold for ') or text:find('^You give ') or text:find('^You cannot loot') or text:find('^The .- is not empty')
        or text:find('^Your money') or text:find(' platinum') and text:find('^You ') then
        return result('loot', nil, text)
    end
    if text:find(' absorbs energy, emitting') or text:find(' feels alive with power') or text:find('^Luck is with you!')
        or text:find(' has become %[') or text:find(' has become .- %(') or text:find('^Your .- glows') or text:find('^Your .- flickers') then
        return result('item', nil, text)
    end
    if matchAny(text, BUFF_WORN_PATTERNS) then return result('buff_worn', nil, text) end
    if text:find('^You have become better at ') or text:find('^You have gained a skill') then return result('skill', nil, text) end
    if text:find('^Your faction standing with ') then return result('faction', nil, text) end
    if matchAny(text, CONSIDER_PATTERNS) then return result('consider', nil, text) end
    if text:find('^You have entered ') or text:find('^LOADING, PLEASE WAIT') or text:find('^You have been summoned to')
        or text:find('^It is .- o\'clock') or text:find('^Your bind point') then
        return result('zone', nil, text)
    end
    if matchAny(text, SYSTEM_PATTERNS) then return result('system', nil, text) end
    if matchAny(text, SPELL_LAND_PATTERNS) then return result('spell_land', nil, text) end
    if text:find('^You feel ') or text:find('^You are ') or text:find('^Your body ') or text:find('^Your skin ') or text:find('^Your mind ')
        or text:find('^You look ') or text:find('^Your eyes ') or text:find('^Your hands ') or text:find('^A .- surrounds you') then
        return result('buff', nil, text)
    end
    -- Player emotes: "Name <does something>" where Name is a player link
    for name in pairs(players) do
        if text:sub(1, #name) == name then return result('emote', name, text, false, true) end
    end

    return result('unknown', nil, text)
end

-- ----------------------------------------------------------------------------
-- Config persistence
-- ----------------------------------------------------------------------------
local function configPath()
    if rt.configPath then return rt.configPath end
    local name = 'Default'
    pcall(function()
        local n = mq.TLO.Me.CleanName()
        if n and n ~= '' then name = tostring(n) end
    end)
    rt.configPath = string.format('%s/triune_chat_%s.lua', (mq and mq.configDir) or 'config', name)
    return rt.configPath
end

local function serialize(val, indent)
    indent = indent or ''
    local t = type(val)
    if t == 'string' then return string.format('%q', val) end
    if t == 'number' or t == 'boolean' then return tostring(val) end
    if t ~= 'table' then return 'nil' end
    local keys = {}
    for k in pairs(val) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    local out = { '{\n' }
    local inner = indent .. '  '
    for _, k in ipairs(keys) do
        local ks = type(k) == 'string' and (k:match('^[%a_][%w_]*$') and k or ('[' .. string.format('%q', k) .. ']')) or ('[' .. tostring(k) .. ']')
        out[#out + 1] = string.format('%s%s = %s,\n', inner, ks, serialize(val[k], inner))
    end
    out[#out + 1] = indent .. '}'
    return table.concat(out)
end

local function newTab(id, name, preset, send)
    local list = PRESETS[preset]
    return {
        id = id,
        name = name,
        channels = list and channelSet(list) or nil,
        include = {},
        exclude = {},
        send = send or 'say',
        tellTarget = '',
    }
end

local function defaultWindows()
    return {
        {
            id = 'main', title = 'Chat', open = true, activeTab = 1,
            tabs = {
                newTab('all', 'All', 'all', 'say'),
                newTab('social', 'Social', 'social', 'group'),
                newTab('combat', 'Combat', 'combat', 'say'),
                newTab('loot', 'Loot & XP', 'loot', 'say'),
                newTab('tells', 'Tells', 'tells', 'tell'),
                newTab('triune', 'Triune', 'triune', 'say'),
            },
        },
    }
end

-- Fills in anything missing or malformed so the rest of the plugin never has
-- to defend against a hand-edited or older config.
local function sanitizeConfig(c)
    c = type(c) == 'table' and c or {}
    local fromVersion = tonumber(c.version) or 0
    c.version = CONFIG_VERSION
    if type(c.timestamps) ~= 'boolean' then c.timestamps = true end
    c.maxLines = math.max(200, math.min(20000, math.floor(tonumber(c.maxLines) or 2000)))
    c.opacity = math.max(0.1, math.min(1.0, tonumber(c.opacity) or 0.92))
    c.locked = (c.locked == true)
    if c.appendMode ~= 'unformatted' then c.appendMode = 'text' end
    if c.renderer ~= 'console' then c.renderer = 'inline' end
    c.lastDrawFailed = (c.lastDrawFailed == true)
    c.capture = (c.capture == true)
    if type(c.colors) ~= 'table' then c.colors = {} end
    for k, v in pairs(c.colors) do
        if not CHANNEL_BY_ID[k] or type(v) ~= 'string' or not v:match('^%x%x%x%x%x%x$') then c.colors[k] = nil end
    end
    local hl = {}
    for _, h in ipairs(type(c.highlights) == 'table' and c.highlights or {}) do
        if type(h) == 'table' and type(h.text) == 'string' and h.text ~= '' then
            hl[#hl + 1] = {
                text = h.text,
                lower = h.text:lower(),   -- matched against the lowercased line in ingest
                color = (type(h.color) == 'string' and h.color:match('^%x%x%x%x%x%x$')) and h.color or 'FFD700',
                beep = (h.beep == true),
                flash = (h.flash ~= false),
            }
        end
    end
    c.highlights = hl
    local muted = {}
    for k, v in pairs(type(c.muted) == 'table' and c.muted or {}) do
        if type(k) == 'string' and k ~= '' and v == true then muted[k:lower()] = true end
    end
    c.muted = muted
    c.tellPopouts = (c.tellPopouts == true)
    c.enterFocus = (c.enterFocus ~= false)
    local recent = {}
    for _, n in ipairs(type(c.recentTells) == 'table' and c.recentTells or {}) do
        if type(n) == 'string' and n ~= '' and #recent < RECENT_TELLS then recent[#recent + 1] = n end
    end
    c.recentTells = recent
    if type(c.windows) ~= 'table' then c.windows = {} end
    -- The Tells window is per-session (the game's tell windows close on camp
    -- too); the next tell or name click recreates it. Pre-1.6 configs had a
    -- popout window per person (tellWith on the window): dropped the same way.
    for wi = #c.windows, 1, -1 do
        local w = c.windows[wi]
        if type(w) == 'table' and (w.tellWindow == true or (type(w.tellWith) == 'string' and w.tellWith ~= '')) then table.remove(c.windows, wi) end
    end
    if #c.windows == 0 then c.windows = defaultWindows() end
    local seenWin = {}
    for wi, w in ipairs(c.windows) do
        if type(w) ~= 'table' then w = {}; c.windows[wi] = w end
        w.id = tostring(w.id or ('w' .. wi))
        while seenWin[w.id] do w.id = w.id .. '_' end
        seenWin[w.id] = true
        w.title = tostring(w.title or ('Chat ' .. wi))
        if type(w.open) ~= 'boolean' then w.open = true end
        if w.opacity ~= nil then w.opacity = math.max(0.1, math.min(1.0, tonumber(w.opacity) or c.opacity)) end
        w.fontScale = math.max(0.6, math.min(2.5, tonumber(w.fontScale) or 1.0))
        w.font = nil -- font selection removed: pushing atlas fonts from Lua crashed imgui.dll
        w.tellWith = nil
        w.tellWindow = nil

        if type(w.tabs) ~= 'table' or #w.tabs == 0 then w.tabs = { newTab('all', 'All', 'all', 'say') } end
        local seenTab = {}
        for ti, t in ipairs(w.tabs) do
            if type(t) ~= 'table' then t = {}; w.tabs[ti] = t end
            t.id = tostring(t.id or ('t' .. ti))
            while seenTab[t.id] do t.id = t.id .. '_' end
            seenTab[t.id] = true
            t.name = tostring(t.name or ('Tab ' .. ti))
            if t.channels ~= nil then
                if type(t.channels) ~= 'table' then t.channels = nil
                else
                    for k, v in pairs(t.channels) do
                        if not CHANNEL_BY_ID[k] or v ~= true then t.channels[k] = nil end
                    end
                    -- v1 seeded the Tells preset with pet chat; a tab still on
                    -- exactly that set is the old preset, so drop the pets.
                    if fromVersion < 2 and t.channels.petchat and t.channels.tell_in and t.channels.tell_out then
                        local n = 0
                        for _ in pairs(t.channels) do n = n + 1 end
                        if n == 3 then t.channels.petchat = nil end
                    end
                end
            end
            for _, key in ipairs({ 'include', 'exclude' }) do
                if type(t[key]) ~= 'table' then t[key] = {} end
                local clean = {}
                for _, kw in ipairs(t[key]) do
                    if type(kw) == 'string' and kw ~= '' then clean[#clean + 1] = kw:lower() end
                end
                t[key] = clean
            end
            if not SEND_BY_ID[t.send] then t.send = 'say' end
            t.tellTarget = type(t.tellTarget) == 'string' and t.tellTarget or ''
            t.tellWith = (type(t.tellWith) == 'string' and t.tellWith ~= '') and t.tellWith or nil
            t.logToFile = (t.logToFile == true)
        end
        w.activeTab = math.max(1, math.min(#w.tabs, math.floor(tonumber(w.activeTab) or 1)))
        -- Panes: every tab sits in a pane 1..panes; empty panes collapse.
        w.panes = math.max(1, math.min(6, math.floor(tonumber(w.panes) or 1)))
        if w.splitDir ~= 'v' then w.splitDir = 'h' end
        for _, t in ipairs(w.tabs) do
            t.pane = math.max(1, math.min(w.panes, math.floor(tonumber(t.pane) or 1)))
        end
        local used = {}
        for _, t in ipairs(w.tabs) do used[t.pane] = true end
        local remap, n = {}, 0
        for pn = 1, w.panes do
            if used[pn] then n = n + 1; remap[pn] = n end
        end
        for _, t in ipairs(w.tabs) do t.pane = remap[t.pane] or 1 end
        w.panes = math.max(1, n)
        local sizes = {}
        local sum = 0
        for pn = 1, w.panes do
            local v = type(w.paneSizes) == 'table' and tonumber(w.paneSizes[pn]) or nil
            v = (v and v > 0) and v or 1
            sizes[pn] = v
            sum = sum + v
        end
        for pn = 1, w.panes do sizes[pn] = sizes[pn] / sum end
        w.paneSizes = sizes
        local active = {}
        for pn = 1, w.panes do
            local want = type(w.activeByPane) == 'table' and w.activeByPane[pn] or nil
            local fallback
            for _, t in ipairs(w.tabs) do
                if t.pane == pn then
                    if t.id == want then active[pn] = t.id end
                    fallback = fallback or t.id
                end
            end
            active[pn] = active[pn] or fallback
        end
        if w.tabs[w.activeTab] and w.tabs[w.activeTab].pane == 1 then active[1] = w.tabs[w.activeTab].id end
        w.activeByPane = active
    end
    return c
end

function saveConfig()
    local path = configPath()
    local f = io.open(path, 'w')
    if not f then return false end
    f:write('-- Triune Chat Windows config (per character)\nreturn ' .. serialize(cfg) .. '\n')
    f:close()
    rt.dirty = false
    rt.lastSave = os.time()
    return true
end

local function loadConfig()
    local data
    local chunk = loadfile(configPath())
    if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == 'table' then data = res end
    end
    -- Refill the existing table so every reference to cfg stays valid across
    -- re-inits (the plugin manager can call onInit twice without onDestroy).
    local fresh = sanitizeConfig(data)
    for k in pairs(cfg) do cfg[k] = nil end
    for k, v in pairs(fresh) do cfg[k] = v end
end

local function markDirty()
    rt.dirty = true
end

-- ----------------------------------------------------------------------------
-- Colors & line rendering
-- ----------------------------------------------------------------------------
local function channelColor(id)
    local c = cfg.colors[id]
    if c then return c end
    local def = CHANNEL_BY_ID[id]
    return def and def.color or 'D0D0D0'
end

local function hexToRgb(hex)
    local r = tonumber(hex:sub(1, 2), 16) or 208
    local g = tonumber(hex:sub(3, 4), 16) or 208
    local b = tonumber(hex:sub(5, 6), 16) or 208
    return r / 255, g / 255, b / 255
end

-- The string handed to the console widget for one entry. The widget does not
-- understand this client's \x12 link format (it shows the raw payload), so
-- lines are rendered from the resolved text; links stay usable through the
-- toolbar's Links menu.
local function renderLine(entry, withTimestamp)
    local prefix = withTimestamp and ('[' .. entry.hms .. '] ') or ''
    if cfg.appendMode == 'unformatted' then
        return prefix .. entry.text
    end
    -- Built on first use: only the console renderer needs the \a# form (the
    -- inline renderer tokenizes from raw).
    if entry.display == nil then
        entry.display = entry.raw and (resolveLinks(convertColors(entry.raw))) or entry.text
    end
    return prefix .. '\a#' .. channelColor(entry.channel) .. entry.display .. '\ax'
end

-- Opening links. MQ's link parser expects stock RoF2 links (56 bytes of link
-- data) while this server sends 77, so mq.ExecuteTextLink either does nothing
-- (on its own truncated parse) or throws a native exception (when handed the
-- full data) that no pcall can catch. It is therefore never called. What
-- works is FindItem(...).Inspect(): the item window for anything you carry
-- or have banked. Links to items you do not have cannot be opened from MQ
-- on this server; the echo says so.
local gamedbPlugin, linkItemId -- defined below

local function executeLink(link)
    -- Preferred: a Game Database card for the exact item and tier from the
    -- link's id - works for items you do not carry.
    local db = gamedbPlugin and gamedbPlugin()
    local id = linkItemId and linkItemId(link.payload)
    if db and db.popout and id then
        local okPop, res = pcall(db.popout, 'items', id)
        if okPop and res then
            echo('Database card: ' .. link.name .. ' (id ' .. id .. ')')
            return true
        end
        echo('Database card failed for ' .. link.name .. ' (id ' .. id .. '): ' .. tostring(okPop and 'not in the database' or res))
    elseif not db then
        echo('Game Database plugin not available; trying your own copy of ' .. link.name .. '.')
    elseif not id then
        echo('No item id in this link (' .. #tostring(link.payload or '') .. ' byte payload); trying your own copy of ' .. link.name .. '.')
    end
    local inspected = false
    local ok, err = pcall(function()
        local item = mq.TLO.FindItem('=' .. link.name)
        if not (item and item()) and mq.TLO.FindItemBank then item = mq.TLO.FindItemBank('=' .. link.name) end
        if item and item() and item.Inspect then
            item.Inspect()
            inspected = true
        end
    end)
    if inspected then
        echo('Opened ' .. link.name .. ' (your copy)')
    elseif not ok then
        echo('Could not open ' .. link.name .. ': ' .. tostring(err))
    else
        echo(link.name .. ' is not in your inventory or bank, and the Game Database plugin is not loaded to show it.')
    end
    return inspected
end

-- The Game Database plugin (tac/gamedb.lua) when it is loaded and enabled.
function gamedbPlugin()
    local pm = core and core.runtime and core.runtime.pluginManager
    local p = pm and pm.plugins and pm.plugins.gamedb
    if p and p.enabled and p.instance and p.instance.search then return p.instance end
    return nil
end

-- Item id from this server's 77-byte link payload: one type byte, then the
-- id as eight hex digits (tier offsets included, so an Enchanted link opens
-- the Enchanted tier).
function linkItemId(payload)
    if type(payload) ~= 'string' or #payload < 9 then return nil end
    local id = tonumber(payload:sub(2, 9), 16)
    if id and id > 0 then return id end
    return nil
end

local function lookupInDatabase(link)
    local db = gamedbPlugin()
    if not db then
        echo('The Game Database plugin is not loaded.')
        return false
    end
    local id = linkItemId(link.payload)
    if id and db.open and db.open('items', id) then return true end
    return db.search('items', link.name)
end

-- Called from the UI: defers the actual execution to the next tick.
local function openItemLink(link)
    rt.pendingLink = link
    echo('Opening ' .. link.name .. '...')
    return true
end

local function runPendingLink()
    local link = rt.pendingLink
    if not link then return end
    rt.pendingLink = nil
    executeLink(link)
end

-- ----------------------------------------------------------------------------
-- Tabs: filter matching and runtime state
-- ----------------------------------------------------------------------------
local function tabAccepts(tab, entry)
    if entry.muted then return false end
    if tab.channels and not tab.channels[entry.channel] then return false end
    -- A tell conversation tab only shows lines to or from that one person.
    if tab.tellWith then
        if not entry.sender or entry.sender:lower() ~= tab.tellWith:lower() then return false end
    end
    if #tab.exclude > 0 or #tab.include > 0 then
        local lower = entry.lower or entry.text:lower()
        entry.lower = lower
        for _, kw in ipairs(tab.exclude) do
            if lower:find(kw, 1, true) then return false end
        end
        if #tab.include > 0 then
            local hit = false
            for _, kw in ipairs(tab.include) do
                if lower:find(kw, 1, true) then hit = true; break end
            end
            if not hit then return false end
        end
    end
    return true
end

local function tabKey(win, tab)
    return win.id .. '/' .. tab.id
end

local function tabState(win, tab)
    local key = tabKey(win, tab)
    local st = rt.tabs[key]
    if not st then
        -- entries / pending are queues trimmed from the front, so they carry
        -- explicit first / last indices: `#t` is undefined once t[1] is nil.
        st = { console = nil, consoleTried = false, pending = {}, pendingFirst = 1, pendingLast = 0, unread = 0, rebuild = true, lastId = 0,
               entries = {}, first = 1, last = 0, atBottom = true, forceBottom = false, flashAt = 0, logFile = nil, logDay = nil, newBelow = 0 }
        rt.tabs[key] = st
    end
    return st
end

local function ensureConsole(win, tab)
    local st = tabState(win, tab)
    if st.console or st.consoleTried then return st.console end
    st.consoleTried = true
    local CW = ImGui.ConsoleWidget
    if type(CW) ~= 'table' and type(CW) ~= 'userdata' then return nil end
    local okNew, newFn = pcall(function() return CW.new end)
    if not okNew or type(newFn) ~= 'function' then return nil end
    local ok, w = pcall(newFn, '##tacchat_' .. tabKey(win, tab))
    if not ok or not w then return nil end
    pcall(function() w.autoScroll = true end)
    pcall(function() w.maxBufferLines = cfg.maxLines end)
    st.console = w
    return w
end

local function consoleAppend(w, line)
    local ok, err
    if cfg.appendMode == 'unformatted' then
        ok, err = pcall(function() w:AppendTextUnformatted(line) end)
    else
        ok, err = pcall(function() w:AppendText(line) end)
        if not ok then
            -- If the formatted path chokes on this line, keep the text visible.
            pcall(function() w:AppendTextUnformatted(line) end)
        end
    end
    if not ok then rt.stats.appendErr = tostring(err) end
end

-- Rebuilds a tab's widget from the ring (filter / timestamp / clear changes).
local function rebuildTab(win, tab)
    local st = tabState(win, tab)
    st.pending = {}
    st.pendingFirst = 1
    st.pendingLast = 0
    st.entries = {}
    st.first = 1
    st.last = 0
    st.rebuild = false
    st.forceBottom = true
    local ring = rt.ring
    local start = math.max(ring.first, ring.last - cfg.maxLines + 1)
    local w = (cfg.renderer == 'console') and ensureConsole(win, tab) or nil
    if w then pcall(function() w:Clear() end) end
    for i = start, ring.last do
        local e = ring.items[i]
        if e and tabAccepts(tab, e) then
            st.last = st.last + 1
            st.entries[st.last] = e
            if w then consoleAppend(w, renderLine(e, cfg.timestamps)) end
        end
    end
    st.lastId = ring.last
end

-- A tab is "active" when it is the selected tab of its pane.
local function isTabActive(win, ti)
    local tab = win.tabs[ti]
    if not tab then return false end
    local pane = tab.pane or 1
    local act = win.activeByPane and win.activeByPane[pane]
    if act == nil then return (pane == 1) and win.activeTab == ti end
    return act == tab.id
end

local function setActiveTab(win, ti)
    local tab = win.tabs[ti]
    if not tab then return end
    win.activeByPane = win.activeByPane or {}
    win.activeByPane[tab.pane or 1] = tab.id
    if (tab.pane or 1) == 1 then win.activeTab = ti end
end

-- Makes a tab the selected one from code (a command, a name click): the
-- ImGui tab bar owns the selection, so the tab item is drawn once with
-- SetSelected on the next frame; setActiveTab alone would be overridden by
-- whatever the bar still had selected.
local function selectTab(win, ti)
    local tab = win.tabs[ti]
    if not tab then return end
    setActiveTab(win, ti)
    rt.selectReq = rt.selectReq or {}
    rt.selectReq[win.id] = tab.id
end

local function paneTabCount(win, pane)
    local n = 0
    for _, t in ipairs(win.tabs) do if (t.pane or 1) == pane then n = n + 1 end end
    return n
end

-- Removes panes with no tabs and renumbers the rest; keeps sizes / actives aligned.
local function collapsePanes(win)
    local panes = win.panes or 1
    local used = {}
    for _, t in ipairs(win.tabs) do used[t.pane or 1] = true end
    local remap, sizes, active, n = {}, {}, {}, 0
    for pn = 1, panes do
        if used[pn] then
            n = n + 1
            remap[pn] = n
            sizes[n] = (win.paneSizes and win.paneSizes[pn]) or 1
            active[n] = win.activeByPane and win.activeByPane[pn]
        end
    end
    for _, t in ipairs(win.tabs) do t.pane = remap[t.pane or 1] or 1 end
    win.panes = math.max(1, n)
    local sum = 0
    for pn = 1, win.panes do sum = sum + (sizes[pn] or 1) end
    for pn = 1, win.panes do sizes[pn] = (sizes[pn] or 1) / sum end
    win.paneSizes = sizes
    win.activeByPane = active
    for pn = 1, win.panes do
        local ok = false
        for _, t in ipairs(win.tabs) do if t.pane == pn and t.id == active[pn] then ok = true end end
        if not ok then
            for _, t in ipairs(win.tabs) do if t.pane == pn then active[pn] = t.id; break end end
        end
    end
end

local logsDirCached
local function safeFileName(s)
    return (tostring(s):gsub('[^%w%-_]+', '_'))
end

-- Per-tab log files: logs/tac_chat_<Char>_<tab>_<YYYYMMDD>.txt, one per day.
local function tabLogWrite(win, tab, st, entry)
    local day = os.date('%Y%m%d')
    if st.logFile and st.logDay ~= day then
        pcall(function() st.logFile:close() end)
        st.logFile = nil
    end
    if not st.logFile then
        if not logsDirCached then
            local dir
            pcall(function()
                local p = mq.TLO.MacroQuest.Path('logs')()
                if p and p ~= '' then dir = tostring(p) end
            end)
            logsDirCached = (dir or (mq and mq.configDir) or 'config'):gsub('[/\\]+$', '')
        end
        local name = 'Default'
        pcall(function() local n = mq.TLO.Me.CleanName(); if n and n ~= '' then name = tostring(n) end end)
        local path = string.format('%s/tac_chat_%s_%s_%s.txt', logsDirCached, safeFileName(name), safeFileName(tab.name), day)
        st.logFile = io.open(path, 'a')
        st.logDay = day
        if not st.logFile then return end
    end
    st.logFile:write(string.format('[%s] %s\n', entry.hms, entry.text))
    rt.logDirty = true
end

local function closeTabLogs()
    for _, st in pairs(rt.tabs) do
        if st.logFile then pcall(function() st.logFile:close() end) end
        st.logFile = nil
    end
end

-- Called from onTick for each new entry: queue it for every tab that wants it.
-- Remembers the last few people you exchanged tells with (most recent first)
-- for the reply dropdown next to the tell target.
function noteTeller(name)
    local list = cfg.recentTells
    for i = #list, 1, -1 do
        if list[i]:lower() == name:lower() then table.remove(list, i) end
    end
    table.insert(list, 1, name)
    while #list > RECENT_TELLS do table.remove(list) end
    markDirty()
end

-- The Tells window: one window with a tab per conversation, like the game's
-- tell windows folded into one. Nil when there is none this session.
local function findTellWindow()
    for _, w in ipairs(cfg.windows) do
        if w.tellWindow then return w end
    end
    return nil
end

-- The conversation tab for a person in the Tells window: tab, index (nil
-- when there is none).
local function findTellTab(win, name)
    name = name:lower()
    for ti, t in ipairs(win.tabs) do
        if t.tellWith and t.tellWith:lower() == name then return t, ti end
    end
    return nil
end

-- Opens (or re-opens) the Tells window and the conversation tab for `name`,
-- creating either as needed. With `focus`, the tab is selected and its input
-- takes the keyboard (a name click); without, an arriving tell just adds the
-- tab and lets its unread badge show. Runs on the plugin tick or before the
-- windows are drawn (never mid-draw), so the window list is stable while
-- drawing. Returns the window and the tab.
function openTellTab(name, focus)
    local win = findTellWindow()
    if not win then
        win = {
            id = 'tells',
            title = 'Tells',
            open = true,
            activeTab = 1,
            panes = 1,
            splitDir = 'h',
            paneSizes = { 1 },
            activeByPane = {},
            tellWindow = true,
            tabs = {},
        }
        cfg.windows[#cfg.windows + 1] = win
    end
    if not win.open then win.open = true end
    local tab, ti = findTellTab(win, name)
    if not tab then
        local taken = {}
        for _, t in ipairs(win.tabs) do taken[t.id] = true end
        tab = newTab(uniqueId('tell', taken), name, 'tells', 'tell')
        tab.tellTarget = name
        tab.tellWith = name
        tab.pane = 1
        win.tabs[#win.tabs + 1] = tab
        ti = #win.tabs
        if ti == 1 then setActiveTab(win, 1) end
    end
    if focus then
        ctrl.show_chat = true
        selectTab(win, ti)
        rt.focusRequested = true
        rt.focusKey = tabKey(win, tab)
    end
    markDirty()
    return win, tab
end

-- A player name clicked in a line (or picked from its menu): the Tells tab
-- opens before the next draw, not mid-draw.
local function requestTell(name)
    if type(name) ~= 'string' or name == '' then return end
    rt.tellReq = name
end

local function distribute(entry)
    for _, win in ipairs(cfg.windows) do
        for ti, tab in ipairs(win.tabs) do
            if tabAccepts(tab, entry) then
                local st = tabState(win, tab)
                -- A tab waiting for a rebuild re-reads the ring when drawn.
                if not st.rebuild then
                    st.last = st.last + 1
                    st.entries[st.last] = entry
                    -- Bounded here, not only when drawn: inactive tabs, closed
                    -- windows and hidden chat must not grow for the session.
                    local cap = cfg.maxLines
                    while st.last - st.first + 1 > cap do
                        st.entries[st.first] = nil
                        st.first = st.first + 1
                    end
                    if cfg.renderer == 'console' then
                        st.pendingLast = st.pendingLast + 1
                        st.pending[st.pendingLast] = entry
                        while st.pendingLast - st.pendingFirst + 1 > cap do
                            st.pending[st.pendingFirst] = nil
                            st.pendingFirst = st.pendingFirst + 1
                        end
                    end
                end
                if not (win.open and ctrl.show_chat and isTabActive(win, ti)) then
                    st.unread = st.unread + 1
                    if entry.flash then st.flashAt = os.time() end
                elseif not st.atBottom then
                    st.newBelow = st.newBelow + 1
                end
                if tab.logToFile then tabLogWrite(win, tab, st, entry) end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Capture / logging
-- ----------------------------------------------------------------------------
local function logsDir()
    local dir
    pcall(function()
        local p = mq.TLO.MacroQuest.Path('logs')()
        if p and p ~= '' then dir = tostring(p) end
    end)
    if not dir then dir = (mq and mq.configDir) or 'config' end
    return (dir:gsub('[/\\]+$', ''))
end

local function myName()
    local name = 'Default'
    pcall(function()
        local n = mq.TLO.Me.CleanName()
        if n and n ~= '' then name = tostring(n) end
    end)
    return name
end

local function openCapture()
    if rt.captureFile then return true end
    rt.capturePath = string.format('%s/tac_chat_capture_%s.txt', logsDir(), myName())
    local f = io.open(rt.capturePath, 'a')
    if not f then return false end
    f:write(string.format('-- Triune Chat capture started %s (channel | line, control bytes escaped)\n', os.date()))
    rt.captureFile = f
    return true
end

local function closeCapture()
    if rt.captureFile then
        pcall(function() rt.captureFile:close() end)
        rt.captureFile = nil
    end
end

local function setCapture(on)
    cfg.capture = (on == true)
    if cfg.capture then
        if openCapture() then
            print('\ag[Triune Chat]\ax capture on: ' .. tostring(rt.capturePath))
        else
            cfg.capture = false
            print('\ar[Triune Chat]\ax could not open capture file ' .. tostring(rt.capturePath))
        end
    else
        closeCapture()
        print('\ay[Triune Chat]\ax capture off')
    end
    markDirty()
end

-- ----------------------------------------------------------------------------
-- Event capture & tick
-- ----------------------------------------------------------------------------
local registeredEvents = {}

local function onAnyLine(line)
    rt.queue[#rt.queue + 1] = tostring(line or '')
    rt.stats.lastEventAt = os.time()
end

local function agoText(t)
    if not t or t == 0 then return 'never' end
    return string.format('%ds ago', os.time() - t)
end

local function registerEvents()
    if mq.unevent then pcall(mq.unevent, 'TACChatAll') end
    local ok = pcall(mq.event, 'TACChatAll', '#*#', onAnyLine, { keepLinks = true })
    if not ok then ok = pcall(mq.event, 'TACChatAll', '#*#', onAnyLine) end
    registeredEvents = ok and { 'TACChatAll' } or {}
end

local function unregisterEvents()
    if mq and mq.unevent then
        for _, name in ipairs(registeredEvents) do pcall(mq.unevent, name) end
    end
    registeredEvents = {}
end

local function nowMs()
    local ok, t = pcall(function() return mq.gettime() end)
    if ok and type(t) == 'number' then return t end
    return os.clock() * 1000
end

-- Refreshes the names the classifier compares against (me, my pets).
local function refreshNames(force)
    local t = os.time()
    if not force and t - rt.namesAt < 15 then return end
    rt.namesAt = t
    rt.me = myName()
    local pets = {}
    pcall(function()
        local p = mq.TLO.Pet.CleanName()
        if p and p ~= '' and p ~= 'NO PET' then pets[tostring(p)] = true end
    end)
    if core and core.getMultiPetList then
        pcall(function()
            for _, p in ipairs(core.getMultiPetList() or {}) do
                local n = p and (p.name or p.CleanName or p.cleanName)
                if type(n) == 'function' then n = n() end
                if type(n) == 'string' and n ~= '' then pets[n] = true end
            end
        end)
    end
    rt.pets = pets
end

local function ctxForClassify()
    return { me = rt.me, pets = rt.pets }
end

-- Tells sent through the plugin (or typed as /tell in its input) are
-- remembered so an echoed "<You> tells you, '...'" line can be matched back
-- to its recipient. Tells typed elsewhere fall back to the last recipient,
-- then to the last person who sent one.
local function noteSentTell(to, text)
    if not to or to == '' then return end
    local q = rt.sentTells
    q[#q + 1] = { to = to, text = trim(text or '') }
    if #q > 20 then table.remove(q, 1) end
    rt.lastTellTo = to
end

function resolveTellTarget(text)
    local msg = text:match("tells you, '(.*)'$") or text:match("tells you, '(.*)$") or ''
    msg = trim(msg)
    local q = rt.sentTells
    for i = #q, 1, -1 do
        if q[i].text == msg then
            local to = q[i].to
            table.remove(q, i)
            return to
        end
    end
    return rt.lastTellTo or rt.lastTellFrom or cfg.recentTells[1]
end

local function ingest(raw)
    local st = rt.stats
    st.total = st.total + 1
    local sec = math.floor(nowMs() / 1000)
    if sec ~= st.curSec then st.curSec = sec; st.curCount = 0 end
    st.curCount = st.curCount + 1
    if st.curCount > st.peak then st.peak = st.curCount end

    local r = classify(raw, ctxForClassify())
    if r.selfEcho then r.sender = resolveTellTarget(r.text) end
    local entry = {
        t = os.time(),
        hms = os.date('%H:%M:%S'),
        channel = r.channel,
        sender = r.sender,
        outgoing = r.outgoing,
        text = r.text,
        display = nil,            -- console form, built lazily by renderLine
        raw = raw,
    }
    if r.sender and cfg.muted[r.sender:lower()] and not r.outgoing then entry.muted = true end
    if #cfg.highlights > 0 and not entry.muted then
        local lower = r.text:lower()
        entry.lower = lower
        for _, h in ipairs(cfg.highlights) do
            if lower:find(h.lower or h.text:lower(), 1, true) then
                entry.hl = h.color
                if h.flash then entry.flash = true end
                if h.beep and os.time() - rt.lastBeepAt >= 1 then
                    rt.lastBeepAt = os.time()
                    pcall(mq.cmd, '/beep')
                end
                break
            end
        end
    end
    ringPush(rt.ring, entry)
    for li, link in ipairs(extractItemLinks(raw)) do
        rt.recentLinks[#rt.recentLinks + 1] = { name = link.name, payload = link.payload, raw = raw, id = entry.id, index = li }
        if #rt.recentLinks > 20 then table.remove(rt.recentLinks, 1) end
    end
    if r.channel == 'unknown' then
        st.unknown = st.unknown + 1
        rt.unknownRecent[#rt.unknownRecent + 1] = r.text
        if #rt.unknownRecent > 30 then table.remove(rt.unknownRecent, 1) end
    end
    if rt.captureFile then
        rt.captureFile:write(string.format('%-12s | %s\n', r.channel, escapeLine(raw)))
        rt.logDirty = true
    end
    if r.channel == 'tell_in' and r.sender and not entry.muted then rt.lastTellFrom = r.sender end
    if (r.channel == 'tell_in' or r.channel == 'tell_out') and r.sender and not entry.muted then
        noteTeller(r.sender)
        if cfg.tellPopouts then openTellTab(r.sender, false) end
    end
    -- The name of another player on a social line is clickable (opens their
    -- Tells tab). NPC names carry spaces and pets have their own channel; my
    -- own name is on outgoing lines, except that an outgoing tell's sender
    -- is its recipient.
    if r.sender and PLAYER_CHANNELS[r.channel] and r.sender ~= rt.me and not r.sender:find(' ', 1, true)
        and (not r.outgoing or r.channel == 'tell_out') then
        entry.player = r.sender
    end
    distribute(entry)

end

-- Classifies and distributes queued lines. Runs from the tick and, while the
-- windows are shown, from the draw (see pumpEvents): it only appends to the
-- ring and the tab queues. File flushes happen on the tick (flushLogs).
local function drainQueue()
    local q = rt.queue
    if #q == 0 then return end
    rt.queue = {}
    local t0 = nowMs()
    for i = 1, #q do ingest(q[i]) end
    local ms = nowMs() - t0
    if ms > rt.stats.drainMaxMs then rt.stats.drainMaxMs = ms end
end

-- Flushes the capture and per-tab log files when something was written
-- since the last flush. Called from onTick (about every 150-200 ms), never
-- per frame.
local function flushLogs()
    if not rt.logDirty then return end
    rt.logDirty = false
    if rt.captureFile then pcall(function() rt.captureFile:flush() end) end
    for _, st in pairs(rt.tabs) do
        if st.logFile then pcall(function() st.logFile:flush() end) end
    end
end

-- ----------------------------------------------------------------------------
-- Sending
-- ----------------------------------------------------------------------------
local function sendText(tab, text)
    text = trim(text)
    if text == '' then return end
    rt.history[#rt.history + 1] = text
    if #rt.history > 50 then table.remove(rt.history, 1) end
    rt.historyIdx = 0
    if text:sub(1, 1) == '/' then
        local to, msg = text:match('^/t (%S+) (.*)$')
        if not to then to, msg = text:match('^/tell (%S+) (.*)$') end
        if to then
            noteSentTell(to, msg)
        else
            msg = text:match('^/r (.*)$') or text:match('^/reply (.*)$')
            if msg then noteSentTell(rt.lastTellFrom or cfg.recentTells[1], msg) end
        end
        pcall(mq.cmd, text)
        return
    end
    local send = SEND_BY_ID[tab.send] or SEND_BY_ID.say
    if send.id == 'tell' then
        local target = trim(tab.tellTarget)
        if target == '' then
            echo('Pick a tell target first.')
            return
        end
        noteSentTell(target, text)
        pcall(mq.cmdf, '/tell %s %s', target, text)
        return
    end
    pcall(mq.cmdf, '%s %s', send.cmd, text)
end

-- ----------------------------------------------------------------------------
-- Fonts. Font *selection* was removed: feeding ImGui a font object obtained
-- through the Lua binding's atlas access crashed inside imgui.dll on the
-- Triune MQ build. Only the per-window font scale remains
-- (SetWindowFontScale, the same call the core uses).
-- ----------------------------------------------------------------------------
local function probeFonts()
    return { list = {}, err = 'font selection disabled (crashed imgui.dll on this MQ build)' }
end

local function pushWindowFont(win)
    return false
end

local function popWindowFont(pushed)
end

-- ----------------------------------------------------------------------------
-- Inline renderer: word-wrapped lines drawn with ImGui text, item link words
-- as ImGui.TextLink. Tokens are built once per entry (shared by every tab);
-- word widths are cached per font size; line counts are cached per wrap
-- width so only the visible slice is laid out and drawn each frame.
-- ----------------------------------------------------------------------------
-- entry.tokens = { { t = 'word', sp = bool (space before), link = index into entry.links or nil }, ... }
local function tokenize(entry)
    if entry.tokens then return entry.tokens end
    local tokens, links = {}, {}
    local who = entry.player   -- set by ingest: the other player's name on this line
    local raw = stripColors(entry.raw or entry.text or '')
    local carrySpace = false
    local function addWords(text, link)
        for sp, word in text:gmatch('(%s*)(%S+)') do
            tokens[#tokens + 1] = { t = word, sp = carrySpace or #sp > 0, link = link }
            carrySpace = false
        end
        if text:match('%s$') then carrySpace = true end
    end
    local pos = 1
    while true do
        local a, b, payload = raw:find(LINK .. '(.-)' .. LINK, pos)
        if not a then
            addWords(raw:sub(pos))
            break
        end
        addWords(raw:sub(pos, a - 1))
        if payload:sub(1, 1) == '1' and #payload > 1 and #payload < ITEM_LINK_PAYLOAD then
            addWords(payload:sub(2))
        elseif #payload > ITEM_LINK_PAYLOAD then
            local name = payload:sub(ITEM_LINK_PAYLOAD + 1)
            links[#links + 1] = { name = name, payload = payload, raw = entry.raw, index = #links + 1 }
            addWords(name, #links)
        else
            addWords(payload)
        end
        pos = b + 1
    end
    -- The player's name is one of the first words ("Bob tells you, ...",
    -- "You told Bob, ..."), possibly with punctuation stuck to it.
    if who then
        for i = 1, math.min(4, #tokens) do
            local tok = tokens[i]
            if not tok.link and tok.t:match('^%a+') == who then
                tok.name = true
                break
            end
        end
    end
    entry.tokens = tokens
    entry.links = links
    return tokens
end

-- Walks the tokens for one wrap width. `measure(text)` returns a width.
-- With `emit`, calls emit(lineIndex, runText, link, isTs, gapBefore, isName)
-- per run (gapBefore = pixels between this run and the previous one on the
-- same line; isName marks the clickable player name); returns the number of
-- visual lines either way.
local function layoutEntry(entry, wrapW, spaceW, tsOn, measure, fontKey, emit)
    local tokens = tokenize(entry)
    local line, x = 1, 0
    local runText, runLink, runIsTs, runGap, runName = nil, nil, false, 0, false
    local function flush()
        if runText and emit then emit(line, runText, runLink, runIsTs, runGap, runName) end
        runText, runLink, runIsTs, runGap, runName = nil, nil, false, 0, false
    end
    local function place(text, w, sp, link, isTs, isName)
        local gap = (x > 0 and sp) and spaceW or 0
        if x > 0 and x + gap + w > wrapW then
            flush()
            line = line + 1
            x = 0
            gap = 0
        end
        if runText and runLink == link and runIsTs == isTs and runName == isName then
            runText = runText .. (gap > 0 and ' ' or '') .. text
        else
            flush()
            runText, runLink, runIsTs, runGap, runName = text, link, isTs, gap, isName
        end
        x = x + gap + w
    end
    if tsOn then
        local ts = '[' .. entry.hms .. ']'
        place(ts, measure(ts), false, nil, true, false)
    end
    for idx, tok in ipairs(tokens) do
        if tok.wk ~= fontKey then
            tok.w = measure(tok.t)
            tok.wk = fontKey
        end
        place(tok.t, tok.w, tok.sp or (tsOn and idx == 1), tok.link, false, tok.name == true)
    end
    flush()
    return line
end

local function measureText(text)
    local ok, w = pcall(ImGui.CalcTextSize, text)
    if ok and type(w) == 'number' then return w end
    if ok and type(w) == 'table' and w.x then return w.x end
    return #text * 7
end

-- Memoized RRGGBB -> r, g, b: the same handful of channel / highlight
-- colours are looked up for every visible line every frame.
local RGB_CACHE = {}
local function rgbOf(hex)
    local c = RGB_CACHE[hex]
    if not c then
        local r, g, b = hexToRgb(hex)
        c = { r, g, b }
        RGB_CACHE[hex] = c
    end
    return c[1], c[2], c[3]
end

-- Layout of one entry for one wrap width / font / timestamp key:
-- { nlines, runs = { { line, text, link, isTs, gap }, ... } }. Cached on the
-- entry per hkey (the last LAYOUT_KEEP keys), so panes and windows of
-- different widths share the tokens and do not relayout each other's lines
-- every frame; the draw walks the cached runs instead of re-running the
-- layout with a closure per entry.
local LAYOUT_KEEP = 3
local function entryLayout(e, hkey, wrapW, spaceW, tsOn, fontKey)
    local layouts = e.layouts
    local lay = layouts and layouts[hkey]
    if lay then return lay end
    local runs = {}
    local n = layoutEntry(e, wrapW, spaceW, tsOn, measureText, fontKey, function(lineIdx, text, link, isTs, gap, isName)
        runs[#runs + 1] = { lineIdx, text, link, isTs, gap, isName }
    end)
    lay = { nlines = n, runs = runs }
    if not layouts then
        layouts = {}
        e.layouts = layouts
        e.layoutKeys = {}
    end
    local keys = e.layoutKeys
    keys[#keys + 1] = hkey
    if #keys > LAYOUT_KEEP then layouts[table.remove(keys, 1)] = nil end
    layouts[hkey] = lay
    -- Last layout used, kept for diagnostics (and the tests).
    e.hkey, e.nlines = hkey, n
    return lay
end

local function drawRun(text, link, isTs, entry, r, g, b, isName)
    if isName then
        -- The other player's name: click to open their Tells tab. Drawn in
        -- the line's colour; the cursor and tooltip say it is clickable.
        ImGui.TextColored(r, g, b, 1, text)
        if ImGui.IsItemHovered and ImGui.IsItemHovered() then
            local MC = ImGuiMouseCursor or _G.ImGuiMouseCursor
            if MC and MC.Hand and ImGui.SetMouseCursor then pcall(ImGui.SetMouseCursor, MC.Hand) end
            if core.setTooltip then core.setTooltip('Tell ' .. entry.player .. ' (opens their tab in the Tells window)') end
            if ImGui.IsMouseClicked and ImGui.IsMouseClicked(0) then requestTell(entry.player) end
        end
    elseif link then
        local l = entry.links[link]
        local clicked = false
        if ImGui.TextLink then
            local ok, res = pcall(ImGui.TextLink, text .. '##l' .. link)
            clicked = ok and res == true
            if not ok then ImGui.TextColored(0.4, 0.7, 1.0, 1, text) end
        else
            ImGui.TextColored(0.4, 0.7, 1.0, 1, text)
        end
        -- The TextLink binding may return nothing: the item-clicked query is
        -- the reliable signal on either widget.
        if not clicked and ImGui.IsItemClicked then
            local okC, hit = pcall(ImGui.IsItemClicked, 0)
            clicked = okC and hit == true
        end
        if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then
            core.setTooltip(gamedbPlugin and gamedbPlugin() and ('Open ' .. l.name .. ' (Game Database card)') or ('Open ' .. l.name .. ' (items you carry or have banked)'))
        end
        if clicked then openItemLink(l) end
    elseif isTs then
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], text)
    else
        ImGui.TextColored(r, g, b, 1, text)
    end
end

-- Right-click on a line: copy, and for lines with a sender reply / target /
-- invite / mute.
local function drawLineContextMenuBody(win, tab)
    local e = rt.ctxEntry
    if not e then return end
    ImGui.TextDisabled((CHANNEL_BY_ID[e.channel] and CHANNEL_BY_ID[e.channel].label or e.channel) .. ' - ' .. e.hms)
    ImGui.Separator()
    if ImGui.MenuItem('Copy line') then
        pcall(ImGui.SetClipboardText, e.text)
    end
    if e.raw and e.raw:find(LINK, 1, true) then
        -- MQ's chat window renders \x12 links through the client's own handler,
        -- which can open items you do not carry (mq.ExecuteTextLink cannot on
        -- this server's link format).
        if ImGui.MenuItem('Show link in MQ window (clickable there)') then
            print('\ag[Triune Chat]\ax link: ' .. e.raw)
        end
    end
    local sender = e.sender
    -- An outgoing tell's sender is its recipient: as good a person to talk
    -- to as one who wrote to me.
    if sender and (not e.outgoing or e.channel == 'tell_out') and sender ~= rt.me then
        if ImGui.MenuItem('Tell ' .. sender .. ' (Tells window)') then requestTell(sender) end
        if ImGui.MenuItem('Reply to ' .. sender .. ' here') then
            tab.send = 'tell'
            tab.tellTarget = sender
            rt.focusRequested = true
            rt.focusKey = tabKey(win, tab)
            markDirty()
        end
        if ImGui.MenuItem('Target ' .. sender) then pcall(mq.cmdf, '/target "%s"', sender) end
        if ImGui.MenuItem('Invite ' .. sender) then pcall(mq.cmdf, '/invite %s', sender) end
        if ImGui.MenuItem('Mute ' .. sender) then
            cfg.muted[sender:lower()] = true
            for _, st in pairs(rt.tabs) do st.rebuild = true end
            markDirty()
        end
    end
end

local function drawLineContextMenu(win, tab)
    if not ImGui.BeginPopup('##tacchatLineCtx_' .. tabKey(win, tab)) then return end
    guarded('line menu', drawLineContextMenuBody, win, tab)
    ImGui.EndPopup()
end

-- Repairs a tab queue that somehow has empty slots between first and last:
-- packs the survivors and records the fact for /tacchat stats.
local function healQueue(st, where)
    local packed, n = {}, 0
    for i = st.first, st.last do
        local e = st.entries[i]
        if e then
            n = n + 1
            packed[n] = e
        end
    end
    rt.stats.holes = (rt.stats.holes or 0) + 1
    rt.stats.holeInfo = string.format('%s: first %d last %d kept %d', tostring(where), st.first, st.last, n)
    st.entries, st.first, st.last = packed, 1, n
end

local function drawInlineLogBody(win, tab, st, logH)
    pcall(ImGui.SetWindowFontScale, rt.safeMode and 1.0 or (win.fontScale or 1.0))
    -- Drop entries the ring has already evicted.
    local ring = rt.ring
    while st.first <= st.last do
        local head = st.entries[st.first]
        if head == nil then
            healQueue(st, 'evict')
            break
        end
        if head.id >= ring.first then break end
        st.entries[st.first] = nil
        st.first = st.first + 1
    end
    if st.first > 512 then
        local packed, n = {}, 0
        for i = st.first, st.last do
            n = n + 1
            packed[n] = st.entries[i]
        end
        st.entries = packed
        st.first = 1
        st.last = n
    end

    local availW = ImGui.GetContentRegionAvail()
    if type(availW) == 'table' or type(availW) == 'userdata' then availW = availW.x end
    local wrapW = math.max(core.px(60), (tonumber(availW) or 300) - core.px(4))
    local lineH = 16
    pcall(function() lineH = ImGui.GetTextLineHeightWithSpacing() end)
    local fontSize = 13
    pcall(function() fontSize = ImGui.GetFontSize() end)
    local fontKey = fontSize
    local spaceW = measureText(' ')
    local tsOn = cfg.timestamps
    local hkey = string.format('%d:%d:%s', math.floor(wrapW), fontKey, tsOn and 1 or 0)

    local scrollY, scrollMax = 0, 0
    pcall(function() scrollY = ImGui.GetScrollY() end)
    pcall(function() scrollMax = ImGui.GetScrollMaxY() end)
    local wasAtBottom = st.forceBottom or (scrollY >= scrollMax - lineH)
    st.atBottom = wasAtBottom
    if wasAtBottom then st.newBelow = 0 end
    local viewTop, viewBottom = scrollY - lineH, scrollY + logH + lineH
    local lineClicked = false

    -- Prefix sums of entry heights: st.cum[i] = height of entries up to i
    -- (relative to st.cum[base]), so the first visible entry is a binary
    -- search and the walk below is O(visible). Rebuilt when the layout key
    -- or line height changes or the queue table is replaced (rebuild, clear,
    -- heal, compaction); extended in place as lines arrive.
    local holes = 0
    local cum = st.cum
    if not cum or st.cumKey ~= hkey or st.cumEntries ~= st.entries or st.cumLineH ~= lineH or st.cumLast < st.first - 1 then
        cum = { [st.first - 1] = 0 }
        st.cum, st.cumKey, st.cumEntries, st.cumLineH, st.cumLast = cum, hkey, st.entries, lineH, st.first - 1
    end
    for i = st.cumLast + 1, st.last do
        local e = st.entries[i]
        local h = 0
        if e then
            h = entryLayout(e, hkey, wrapW, spaceW, tsOn, fontKey).nlines * lineH
        else
            holes = holes + 1
        end
        cum[i] = cum[i - 1] + h
    end
    st.cumLast = st.last
    local base = cum[st.first - 1]
    local total = cum[st.last] - base

    -- First entry whose bottom edge reaches the top of the view.
    local lo, hi = st.first, st.last + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if cum[mid] - base < viewTop then lo = mid + 1 else hi = mid end
    end
    local skipAbove = cum[lo - 1] - base
    if skipAbove > 0 then ImGui.Dummy(0, skipAbove) end
    local i = lo
    while i <= st.last do
        if cum[i - 1] - base > viewBottom then break end
        local e = st.entries[i]
        if not e then
            holes = holes + 1   -- empty slot; healed after the loop
        else
            local r, g, b = rgbOf(e.hl or channelColor(e.channel))
            ImGui.PushID(e.id)
            local runs = entryLayout(e, hkey, wrapW, spaceW, tsOn, fontKey).runs
            local curLine = 1
            for ri = 1, #runs do
                local run = runs[ri]
                local lineIdx = run[1]
                if ri > 1 and lineIdx == curLine then ImGui.SameLine(0, run[5]) end
                curLine = lineIdx
                drawRun(run[2], run[3], run[4], e, r, g, b, run[6])

                if ImGui.IsItemHovered and ImGui.IsItemHovered() and ImGui.IsMouseClicked and ImGui.IsMouseClicked(1) then
                    rt.ctxEntry = e
                    rt.ctxTab = tab
                    lineClicked = true
                    ImGui.OpenPopup('##tacchatLineCtx_' .. tabKey(win, tab))
                end
            end
            ImGui.PopID()
        end
        i = i + 1
    end
    local skipBelow = total - (cum[i - 1] - base)
    if skipBelow > 0 then ImGui.Dummy(0, skipBelow) end
    if holes > 0 then healQueue(st, 'draw') end
    if wasAtBottom then
        pcall(ImGui.SetScrollHereY, 1.0)
        st.forceBottom = false
    end
    drawLineContextMenu(win, tab)
    -- Right-click on empty log space opens the tab menu (drawn at window scope).
    if not lineClicked and ImGui.IsWindowHovered and ImGui.IsWindowHovered() and ImGui.IsMouseClicked and ImGui.IsMouseClicked(1) then
        rt.tabMenuReq = { win = win, ti = win.activeTab }
    end
end

-- The child scope is protected: whatever fails inside the body, EndChild
-- (and the font pop) still run, so an error cannot unbalance ImGui.
local function drawInlineLog(win, tab, st, logH)
    trace('BeginChild log %s', tab.name)
    if not ImGui.BeginChild('##tacchatLog_' .. tabKey(win, tab), 0, logH, false) then
        ImGui.EndChild()
        trace('EndChild log (clipped)')
        return
    end
    local fontPushed = pushWindowFont(win)
    if fontPushed then trace('PushFont') end
    guarded('log', drawInlineLogBody, win, tab, st, logH)
    popWindowFont(fontPushed)
    ImGui.EndChild()
    trace('EndChild log')
end

-- ----------------------------------------------------------------------------
-- Tab / window management
-- ----------------------------------------------------------------------------
function uniqueId(prefix, taken)
    local n = 1
    while taken[prefix .. n] do n = n + 1 end
    return prefix .. n
end

local function windowIds()
    local t = {}
    for _, w in ipairs(cfg.windows) do t[w.id] = true end
    return t
end

local function tabIds(win)
    local t = {}
    for _, tab in ipairs(win.tabs) do t[tab.id] = true end
    return t
end

local function invalidateTabs()
    for _, st in pairs(rt.tabs) do st.rebuild = true end
end

local function newWindow(title)
    local win = {
        id = uniqueId('w', windowIds()),
        title = trim(title) ~= '' and trim(title) or ('Chat ' .. (#cfg.windows + 1)),
        open = true,
        activeTab = 1,
        panes = 1,
        splitDir = 'h',
        paneSizes = { 1 },
        activeByPane = { 'all' },
        tabs = { newTab('all', 'All', 'all', 'say') },
    }
    win.tabs[1].pane = 1
    cfg.windows[#cfg.windows + 1] = win
    ctrl.show_chat = true
    markDirty()
    return win
end

local function addTab(win, name, preset, pane)
    local tab = newTab(uniqueId('t', tabIds(win)), trim(name) ~= '' and trim(name) or 'New tab', preset or 'all', 'say')
    tab.pane = math.max(1, math.min(win.panes or 1, pane or 1))
    win.tabs[#win.tabs + 1] = tab
    setActiveTab(win, #win.tabs)
    markDirty()
    return tab
end

local function dropTabState(win, tab)
    local st = rt.tabs[tabKey(win, tab)]
    if st and st.logFile then pcall(function() st.logFile:close() end) end
    rt.tabs[tabKey(win, tab)] = nil
end

local function removeTab(win, ti)
    if #win.tabs <= 1 then return false end
    local tab = table.remove(win.tabs, ti)
    dropTabState(win, tab)
    win.activeTab = math.max(1, math.min(#win.tabs, win.activeTab > ti and win.activeTab - 1 or win.activeTab))
    collapsePanes(win)
    markDirty()
    return true
end

-- Swaps a tab with its neighbour in the same pane.
local function moveTab(win, ti, dir)
    local tab = win.tabs[ti]
    if not tab then return false end
    local tj = ti + dir
    while win.tabs[tj] and (win.tabs[tj].pane or 1) ~= (tab.pane or 1) do tj = tj + dir end
    if tj < 1 or tj > #win.tabs then return false end
    win.tabs[ti], win.tabs[tj] = win.tabs[tj], win.tabs[ti]
    setActiveTab(win, tj)
    markDirty()
    return true
end

local function moveTabToWindow(win, ti, dest)
    if #win.tabs <= 1 or dest == win then return false end
    local tab = table.remove(win.tabs, ti)
    dropTabState(win, tab)
    local taken = tabIds(dest)
    if taken[tab.id] then tab.id = uniqueId('t', taken) end
    tab.pane = 1
    dest.tabs[#dest.tabs + 1] = tab
    setActiveTab(dest, #dest.tabs)
    dest.open = true
    win.activeTab = math.max(1, math.min(#win.tabs, win.activeTab))
    collapsePanes(win)
    markDirty()
    return true
end

-- Puts a tab into pane `pane` (1..panes, or panes + 1 for a new pane). The
-- pane it leaves must keep at least one tab.
local function moveTabToPane(win, ti, pane, dir)
    local tab = win.tabs[ti]
    if not tab then return false end
    local from = tab.pane or 1
    if pane == from then return false end
    if paneTabCount(win, from) <= 1 then return false end
    local panes = win.panes or 1
    if pane > panes then
        if panes >= 6 then return false end
        pane = panes + 1
        win.panes = pane
        local sizes = {}
        for pn = 1, panes do sizes[pn] = (win.paneSizes and win.paneSizes[pn] or (1 / panes)) * (panes / pane) end
        sizes[pane] = 1 / pane
        win.paneSizes = sizes
        if dir then win.splitDir = dir end
    end
    tab.pane = pane
    win.activeByPane = win.activeByPane or {}
    win.activeByPane[pane] = tab.id
    collapsePanes(win)
    markDirty()
    return true
end

local function unsplit(win)
    for _, t in ipairs(win.tabs) do t.pane = 1 end
    collapsePanes(win)
    markDirty()
end

local function closeWindow(win)
    -- The last real window is hidden, never removed. The Tells window does
    -- not count: with main + Tells, closing main must not delete its config.
    local real = 0
    for _, w in ipairs(cfg.windows) do
        if not w.tellWindow then real = real + 1 end
    end
    if real <= 1 and not win.tellWindow then
        win.open = false
        ctrl.show_chat = false
        core.saveLoadout(true)
        markDirty()
        return
    end
    for i, w in ipairs(cfg.windows) do
        if w == win then
            for _, tab in ipairs(win.tabs) do dropTabState(win, tab) end
            table.remove(cfg.windows, i)
            break
        end
    end
    markDirty()
end

-- Closes a tab from its menu or a middle-click. A Tells window tab is one
-- conversation: closing the last one closes the window (the next tell or
-- name click brings it back).
local function closeTab(win, ti)
    if win.tellWindow and #win.tabs <= 1 then
        closeWindow(win)
        return true
    end
    return removeTab(win, ti)
end

local function findWindow(name)
    name = tostring(name or ''):lower()
    for _, w in ipairs(cfg.windows) do
        if w.title:lower() == name or w.id:lower() == name then return w end
    end
    return nil
end

local function openEditor(kind, win, tab)
    rt.editor = { kind = kind or 'tab', winId = win and win.id, tabId = tab and tab.id, page = kind == 'tab' and 'tab' or kind }
end

-- ----------------------------------------------------------------------------
-- Settings editor window
-- ----------------------------------------------------------------------------
local function round255(v) return math.floor((tonumber(v) or 0) * 255 + 0.5) end

-- Colour picker when the binding has ColorEdit3, a hex field otherwise.
-- Returns the new hex when it changed.
local function drawColorField(id, hex)
    local r, g, b = hexToRgb(hex)
    local flags = (ImGuiColorEditFlags and ImGuiColorEditFlags.NoInputs) or 0
    if ImGui.ColorEdit3 then
        local ok, col = pcall(ImGui.ColorEdit3, '##col_' .. id, { r, g, b }, flags)
        if ok and type(col) == 'table' then
            local nr, ng, nb = col[1] or col.x or r, col[2] or col.y or g, col[3] or col.z or b
            local h = string.format('%02X%02X%02X', round255(nr), round255(ng), round255(nb))
            if h ~= hex then return h end
            return nil
        end
    end
    ImGui.SetNextItemWidth(core.px(70))
    local txt = ImGui.InputText('##colhex_' .. id, hex)
    if type(txt) == 'string' then
        txt = txt:upper()
        if txt ~= hex and txt:match('^%x%x%x%x%x%x$') then return txt end
    end
    return nil
end

local function drawChannelMatrix(tab)
    if ImGui.SmallButton('All##chanAll') then
        tab.channels = nil
        invalidateTabs()
        markDirty()
    end
    ImGui.SameLine()
    if ImGui.SmallButton('None##chanNone') then
        tab.channels = {}
        invalidateTabs()
        markDirty()
    end
    ImGui.SameLine()
    ImGui.TextDisabled('Preset:')
    for _, name in ipairs({ 'social', 'combat', 'loot', 'tells', 'triune' }) do
        ImGui.SameLine()
        if ImGui.SmallButton(name:sub(1, 1):upper() .. name:sub(2) .. '##preset_' .. name) then
            tab.channels = channelSet(PRESETS[name])
            invalidateTabs()
            markDirty()
        end
    end
    local groups = { 'Social', 'Combat', 'Info' }
    if ImGui.BeginTable('##chanMatrix', 3, ImGuiTableFlags and ImGuiTableFlags.SizingStretchSame or 0) then
        for _, g in ipairs(groups) do ImGui.TableSetupColumn(g) end
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        for _, g in ipairs(groups) do
            ImGui.TableNextColumn()
            for _, c in ipairs(CHANNELS) do
                if c.group == g then
                    local on = (tab.channels == nil) or (tab.channels[c.id] == true)
                    local r, gg, b = hexToRgb(channelColor(c.id))
                    local Col = ImGuiCol or _G.ImGuiCol
                    local pushed = Col and pcall(ImGui.PushStyleColor, Col.Text, r, gg, b, 1)
                    local val = ImGui.Checkbox(c.label .. '##chan_' .. c.id, on)
                    if pushed then ImGui.PopStyleColor() end
                    if val ~= on then
                        if tab.channels == nil then
                            tab.channels = {}
                            for _, cc in ipairs(CHANNELS) do tab.channels[cc.id] = true end
                        end
                        tab.channels[c.id] = val or nil
                        invalidateTabs()
                        markDirty()
                    end
                end
            end
        end
        ImGui.EndTable()
    end
end

local function drawKeywordList(tab, key, label, hint)
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], label)
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(180))
    local txt = ImGui.InputTextWithHint('##kw_' .. key, hint, rt.kwInput[key] or '')
    if type(txt) == 'string' then rt.kwInput[key] = txt end
    ImGui.SameLine()
    if ImGui.SmallButton('Add##kwadd_' .. key) and trim(rt.kwInput[key]) ~= '' then
        tab[key][#tab[key] + 1] = trim(rt.kwInput[key]):lower()
        rt.kwInput[key] = ''
        invalidateTabs()
        markDirty()
    end
    local remove
    for i, kw in ipairs(tab[key]) do
        ImGui.SameLine()
        if ImGui.SmallButton(kw .. ' x##kwrm_' .. key .. i) then remove = i end
    end
    if remove then
        table.remove(tab[key], remove)
        invalidateTabs()
        markDirty()
    end
end

local function drawTabPage(win, tab)
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Name')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(160))
    local name = ImGui.InputText('##tabName', tab.name)
    if type(name) == 'string' and name ~= tab.name and trim(name) ~= '' then
        tab.name = name
        dropTabState(win, tab) -- log file name follows the tab name
        markDirty()
    end
    ImGui.SameLine()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Sends to')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(core.px(90))
    local send = SEND_BY_ID[tab.send] or SEND_BY_ID.say
    if ImGui.BeginCombo('##tabSend', send.label) then
        for _, sc in ipairs(SEND_CHANNELS) do
            if ImGui.Selectable(sc.label, sc.id == tab.send) then tab.send = sc.id; markDirty() end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    local log = ImGui.Checkbox('Log to file##tabLog', tab.logToFile)
    if log ~= tab.logToFile then
        tab.logToFile = log
        if not log then dropTabState(win, tab) end
        markDirty()
    end
    if ImGui.IsItemHovered and ImGui.IsItemHovered() then core.setTooltip('Appends this tab\'s lines to logs/tac_chat_<Name>_<tab>_<date>.txt') end
    ImGui.Separator()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Channels shown in this tab')
    drawChannelMatrix(tab)
    ImGui.Separator()
    drawKeywordList(tab, 'include', 'Only lines containing', 'keyword')
    drawKeywordList(tab, 'exclude', 'Hide lines containing', 'keyword')
end

local function drawColorsPage()
    ImGui.TextDisabled('Click a swatch to change a channel colour. Reset returns the default.')
    if ImGui.BeginTable('##colorTable', 3, ImGuiTableFlags and ImGuiTableFlags.SizingStretchSame or 0) then
        for _, g in ipairs({ 'Social', 'Combat', 'Info' }) do ImGui.TableSetupColumn(g) end
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        for _, g in ipairs({ 'Social', 'Combat', 'Info' }) do
            ImGui.TableNextColumn()
            for _, c in ipairs(CHANNELS) do
                if c.group == g then
                    local hex = channelColor(c.id)
                    local changed = drawColorField(c.id, hex)
                    if changed then
                        cfg.colors[c.id] = (changed ~= c.color) and changed or nil
                        invalidateTabs()
                        markDirty()
                    end
                    ImGui.SameLine()
                    local r, gg, b = hexToRgb(hex)
                    ImGui.TextColored(r, gg, b, 1, c.label)
                    if cfg.colors[c.id] then
                        ImGui.SameLine()
                        if ImGui.SmallButton('reset##colreset_' .. c.id) then
                            cfg.colors[c.id] = nil
                            invalidateTabs()
                            markDirty()
                        end
                    end
                end
            end
        end
        ImGui.EndTable()
    end
end

local function drawHighlightsPage()
    ImGui.TextDisabled('Lines containing a highlight word are drawn in its colour; Flash marks the tab, Beep plays /beep (max once a second).')
    ImGui.SetNextItemWidth(core.px(180))
    local txt = ImGui.InputTextWithHint('##hlText', 'word or phrase', rt.hlInput)
    if type(txt) == 'string' then rt.hlInput = txt end
    ImGui.SameLine()
    local c = drawColorField('hlnew', rt.hlColor)
    if c then rt.hlColor = c end
    ImGui.SameLine()
    if ImGui.SmallButton('Add##hlAdd') and trim(rt.hlInput) ~= '' then
        local hlText = trim(rt.hlInput)
        cfg.highlights[#cfg.highlights + 1] = { text = hlText, lower = hlText:lower(), color = rt.hlColor, beep = false, flash = true }
        rt.hlInput = ''
        markDirty()
    end
    local remove
    for i, h in ipairs(cfg.highlights) do
        ImGui.PushID('hl' .. i)
        local c2 = drawColorField('hl' .. i, h.color)
        if c2 then h.color = c2; markDirty() end
        ImGui.SameLine()
        local r, g, b = hexToRgb(h.color)
        ImGui.TextColored(r, g, b, 1, h.text)
        ImGui.SameLine()
        local beep = ImGui.Checkbox('Beep', h.beep)
        if beep ~= h.beep then h.beep = beep; markDirty() end
        ImGui.SameLine()
        local flash = ImGui.Checkbox('Flash', h.flash)
        if flash ~= h.flash then h.flash = flash; markDirty() end
        ImGui.SameLine()
        if ImGui.SmallButton('x') then remove = i end
        ImGui.PopID()
    end
    if remove then table.remove(cfg.highlights, remove); markDirty() end
end

local function drawMutedPage()
    ImGui.TextDisabled('Lines from muted senders are hidden in every tab (their tells still reach the game).')
    ImGui.SetNextItemWidth(core.px(160))
    local txt = ImGui.InputTextWithHint('##muteName', 'player name', rt.muteInput)
    if type(txt) == 'string' then rt.muteInput = txt end
    ImGui.SameLine()
    if ImGui.SmallButton('Mute##muteAdd') and trim(rt.muteInput) ~= '' then
        cfg.muted[trim(rt.muteInput):lower()] = true
        rt.muteInput = ''
        invalidateTabs()
        markDirty()
    end
    local names = {}
    for n in pairs(cfg.muted) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        if ImGui.SmallButton('Unmute##unmute_' .. n) then
            cfg.muted[n] = nil
            invalidateTabs()
            markDirty()
        end
        ImGui.SameLine()
        ImGui.Text(n)
    end
    if #names == 0 then ImGui.TextDisabled('Nobody muted.') end
end

local function drawGeneralPage()
    local ts = ImGui.Checkbox('Timestamps##genTs', cfg.timestamps)
    if ts ~= cfg.timestamps then cfg.timestamps = ts; invalidateTabs(); markDirty() end
    ImGui.SameLine()
    local classic = ImGui.Checkbox('Classic console renderer (no inline links)##genRenderer', cfg.renderer == 'console')
    if classic ~= (cfg.renderer == 'console') then
        cfg.renderer = classic and 'console' or 'inline'
        invalidateTabs()
        markDirty()
    end
    ImGui.SetNextItemWidth(core.px(160))
    -- The slider edits a draft; the ring resize and tab rebuild only happen
    -- once the slider is released (not on every drag frame).
    local ml = ImGui.SliderInt('Buffer lines##genMax', rt.maxLinesDraft or cfg.maxLines, 200, 20000)
    if type(ml) == 'number' then rt.maxLinesDraft = ml end
    local dragging = ImGui.IsItemActive and ImGui.IsItemActive() == true
    if not dragging and rt.maxLinesDraft and rt.maxLinesDraft ~= cfg.maxLines then
        cfg.maxLines = rt.maxLinesDraft
        rt.ring.cap = cfg.maxLines
        invalidateTabs()
        markDirty()
    end
    if not dragging then rt.maxLinesDraft = nil end
    ImGui.SetNextItemWidth(core.px(160))
    local op = ImGui.SliderFloat('Default opacity##genOpacity', cfg.opacity, 0.1, 1.0, '%.2f')
    if type(op) == 'number' and math.abs(op - cfg.opacity) > 0.001 then cfg.opacity = op; markDirty() end
    local po = ImGui.Checkbox('Incoming tells open the Tells window (one window, a tab per person)##genPopout', cfg.tellPopouts)
    if po ~= cfg.tellPopouts then cfg.tellPopouts = po; markDirty() end
    if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Like the game\'s tell windows, folded into one: each person gets a tab with only that conversation and the input set to reply.\nClicking a player name in any chat line opens their tab whether this is on or off.')
    end

    local ef = ImGui.Checkbox('Enter opens the chat input; Enter sends and hands the keys back (like the game)##genEnter', cfg.enterFocus)
    if ef ~= cfg.enterFocus then cfg.enterFocus = ef; markDirty() end
    if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Off: the input keeps the keyboard after you send, so you can keep typing.\nThe game still opens its own chat input on Enter; shrink or hide its windows once this one does the job.')
    end
    local cap = ImGui.Checkbox('Capture lines to file (pattern building)##genCap', cfg.capture)
    if cap ~= cfg.capture then setCapture(cap) end
    if ImGui.SmallButton('Reset layout to defaults##genReset') then chatCommand('reset') end
    local st = rt.stats
    ImGui.TextDisabled(string.format('%d lines | %d unclassified | peak %d/s | slowest drain %.1f ms', st.total, st.unknown, st.peak, st.drainMaxMs))
    if #rt.unknownRecent > 0 and ImGui.CollapsingHeader(string.format('Recent unclassified lines (%d)##genUnknown', #rt.unknownRecent)) then
        for i = #rt.unknownRecent, 1, -1 do ImGui.TextWrapped(rt.unknownRecent[i]) end
    end
end

local function editorTarget()
    local ed = rt.editor
    if not ed then return nil end
    for _, w in ipairs(cfg.windows) do
        if w.id == ed.winId then
            for ti, t in ipairs(w.tabs) do
                if t.id == ed.tabId then return w, t, ti end
            end
            return w, nil, nil
        end
    end
    return nil
end

local drawEditorBody
local function drawEditor()
    local ed = rt.editor
    if not ed then return end
    core.pushTheme()
    core.preBeginWindow('chat_settings')
    pcall(ImGui.SetNextWindowSize, core.px(620), core.px(460), (ImGuiCond and ImGuiCond.FirstUseEver) or 4)
    local open, draw = ImGui.Begin('Chat Settings###TriuneChatEditor', true)
    if open == false then rt.editor = nil end
    if draw then
        core.postBeginWindow('chat_settings')
        guarded('settings', drawEditorBody, ed)
    end
    ImGui.End()
    core.popTheme()
end

function drawEditorBody(ed)
    do
        local win, tab = editorTarget()
        -- which tab is being edited
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Editing')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(core.px(220))
        local cur = (win and tab) and (win.title .. ' / ' .. tab.name) or 'pick a tab'
        if ImGui.BeginCombo('##edTarget', cur) then
            for _, w in ipairs(cfg.windows) do
                for _, t in ipairs(w.tabs) do
                    if ImGui.Selectable(w.title .. ' / ' .. t.name .. '##ed_' .. tabKey(w, t), w == win and t == tab) then
                        ed.winId, ed.tabId = w.id, t.id
                    end
                end
            end
            ImGui.EndCombo()
        end
        if ImGui.BeginTabBar('##edTabs') then
            local pages = {
                { 'Tab filters', function() if win and tab then drawTabPage(win, tab) else ImGui.TextDisabled('Pick a tab above.') end end },
                { 'Colours', drawColorsPage },
                { 'Highlights', drawHighlightsPage },
                { 'Muted', drawMutedPage },
                { 'General', drawGeneralPage },
            }
            for _, page in ipairs(pages) do
                if ImGui.BeginTabItem(page[1]) then
                    guarded('settings ' .. page[1], page[2])
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
    end
end

-- Tab right-click menu (also from empty log space). Popup is opened at the
-- chat window's scope by drawWindow; this only draws its contents.
local function drawTabMenuBody(win, tab, ti)
    ImGui.TextDisabled(win.title .. ' / ' .. tab.name)
    ImGui.Separator()
    if ImGui.MenuItem('Filters & settings...') then openEditor('tab', win, tab) end
    if ImGui.MenuItem('New tab') then
        local t = addTab(win, 'New tab', 'all', tab.pane or 1)
        openEditor('tab', win, t)
    end
    if ImGui.MenuItem('Move left', nil, false, ti > 1) then moveTab(win, ti, -1) end
    if ImGui.MenuItem('Move right', nil, false, ti < #win.tabs) then moveTab(win, ti, 1) end
    if ImGui.BeginMenu('Move to window', #win.tabs > 1) then
        for _, w in ipairs(cfg.windows) do
            if w ~= win and ImGui.MenuItem(w.title .. '##mv_' .. w.id) then moveTabToWindow(win, ti, w) end
        end
        if ImGui.MenuItem('New window') then
            local w = newWindow(tab.name)
            moveTabToWindow(win, ti, w)
            table.remove(w.tabs, 1) -- the seed tab; the moved tab takes its place
            dropTabState(w, { id = 'all' })
            w.activeTab = 1
        end
        ImGui.EndMenu()
    end
    local canLeave = paneTabCount(win, tab.pane or 1) > 1
    if ImGui.BeginMenu('Split / panes') then
        if ImGui.MenuItem('Split: this tab into a new pane on the right', nil, false, canLeave and (win.panes or 1) < 6) then
            moveTabToPane(win, ti, (win.panes or 1) + 1, 'h')
        end
        if ImGui.MenuItem('Split: this tab into a new pane below', nil, false, canLeave and (win.panes or 1) < 6) then
            moveTabToPane(win, ti, (win.panes or 1) + 1, 'v')
        end
        if (win.panes or 1) > 1 then
            for pn = 1, win.panes do
                if pn ~= (tab.pane or 1) and ImGui.MenuItem('Move this tab to pane ' .. pn, nil, false, canLeave) then
                    moveTabToPane(win, ti, pn)
                end
            end
            if ImGui.MenuItem('Panes side by side', nil, win.splitDir ~= 'v') then win.splitDir = 'h'; markDirty() end
            if ImGui.MenuItem('Panes stacked', nil, win.splitDir == 'v') then win.splitDir = 'v'; markDirty() end
            if ImGui.MenuItem('Equal pane sizes') then
                for pn = 1, win.panes do win.paneSizes[pn] = 1 / win.panes end
                markDirty()
            end
            if ImGui.MenuItem('Unsplit (all tabs in one pane)') then unsplit(win) end
        end
        if not canLeave then ImGui.TextDisabled('A pane keeps at least one tab; add a tab first.') end
        ImGui.EndMenu()
    end
    if ImGui.MenuItem('Log this tab to file', nil, tab.logToFile) then
        tab.logToFile = not tab.logToFile
        if not tab.logToFile then dropTabState(win, tab) end
        markDirty()
    end
    if ImGui.MenuItem('Clear this tab') then
        local st = tabState(win, tab)
        st.entries, st.first, st.last = {}, 1, 0
        st.pending, st.pendingFirst, st.pendingLast = {}, 1, 0
        if st.console then pcall(function() st.console:Clear() end) end
    end
    if ImGui.MenuItem('Jump to bottom') then tabState(win, tab).forceBottom = true end
    if ImGui.MenuItem('Close tab', nil, false, #win.tabs > 1 or win.tellWindow == true) then closeTab(win, ti) end
    ImGui.Separator()
    if ImGui.BeginMenu('Window') then
        ImGui.SetNextItemWidth(core.px(140))
        local title = ImGui.InputText('##winTitle', win.title)
        if type(title) == 'string' and title ~= win.title and trim(title) ~= '' then win.title = title; markDirty() end
        ImGui.SetNextItemWidth(core.px(140))
        local fs = ImGui.SliderFloat('Font scale##winFont', win.fontScale or 1.0, 0.6, 2.5, '%.2f')
        if type(fs) == 'number' and math.abs(fs - (win.fontScale or 1.0)) > 0.001 then win.fontScale = fs; markDirty() end
        if core.drawWindowScaleControl then
            local key = (cfg.windows[1] == win) and 'chat' or ('chat_' .. win.id)
            core.drawWindowScaleControl(key, 'UI scale', core.px(120))
        end
        ImGui.SetNextItemWidth(core.px(140))
        local op = ImGui.SliderFloat('Opacity##winOpacity', win.opacity or cfg.opacity, 0.1, 1.0, '%.2f')
        if type(op) == 'number' and math.abs(op - (win.opacity or cfg.opacity)) > 0.001 then win.opacity = op; markDirty() end
        if ImGui.MenuItem('Lock position & size', nil, cfg.locked) then cfg.locked = not cfg.locked; markDirty() end
        ImGui.Separator()
        ImGui.SetNextItemWidth(core.px(140))
        local nw = ImGui.InputTextWithHint('##newWinName', 'new window name', rt.newWindowName)
        if type(nw) == 'string' then rt.newWindowName = nw end
        ImGui.SameLine()
        if ImGui.SmallButton('Add##addWin') then
            newWindow(rt.newWindowName)
            rt.newWindowName = ''
            ImGui.CloseCurrentPopup()
        end
        if ImGui.MenuItem('Close window') then closeWindow(win); ImGui.CloseCurrentPopup() end
        ImGui.EndMenu()
    end
    if ImGui.BeginMenu('Links', #rt.recentLinks > 0) then
        for i = #rt.recentLinks, 1, -1 do
            local link = rt.recentLinks[i]
            if ImGui.MenuItem(link.name .. '##tacchatLink_' .. i) then openItemLink(link) end
        end
        ImGui.EndMenu()
    end
    -- The Game Database plugin can show any item by name, carried or not.
    if ImGui.BeginMenu('Look up in Database', #rt.recentLinks > 0 and gamedbPlugin() ~= nil) then
        for i = #rt.recentLinks, 1, -1 do
            local link = rt.recentLinks[i]
            if ImGui.MenuItem(link.name .. '##tacchatDb_' .. i) then lookupInDatabase(link) end
        end
        ImGui.EndMenu()
    end
    ImGui.Separator()
    if ImGui.MenuItem('Timestamps', nil, cfg.timestamps) then cfg.timestamps = not cfg.timestamps; invalidateTabs(); markDirty() end
    if ImGui.MenuItem('Incoming tells open the Tells window', nil, cfg.tellPopouts) then cfg.tellPopouts = not cfg.tellPopouts; markDirty() end
    if ImGui.MenuItem('Enter opens the input (like the game)', nil, cfg.enterFocus) then cfg.enterFocus = not cfg.enterFocus; markDirty() end
    if ImGui.MenuItem('Colours...') then openEditor('colors', win, tab) end
    if ImGui.MenuItem('Highlights...') then openEditor('highlights', win, tab) end
    if ImGui.MenuItem('Muted senders...') then openEditor('muted', win, tab) end
    if ImGui.MenuItem('Clear all tabs') then
        rt.ring = newRing(cfg.maxLines)
        invalidateTabs()
    end
end

local function drawTabMenu(win, tab, ti)
    if not ImGui.BeginPopup('##tacchatTabMenu_' .. win.id) then return end
    guarded('tab menu', drawTabMenuBody, win, tab, ti)
    ImGui.EndPopup()
end

-- ----------------------------------------------------------------------------
-- Window drawing
-- ----------------------------------------------------------------------------
local function inputCallback(data)
    rt.stats.cbCalls = rt.stats.cbCalls + 1
    local K = ImGuiKey or _G.ImGuiKey
    pcall(function()
        if K and data.EventKey == K.UpArrow and #rt.history > 0 then
            rt.historyIdx = (rt.historyIdx == 0) and #rt.history or math.max(1, rt.historyIdx - 1)
            data:DeleteChars(0, data.BufTextLen)
            data:InsertChars(0, rt.history[rt.historyIdx])
        elseif K and data.EventKey == K.DownArrow and rt.historyIdx > 0 then
            rt.historyIdx = rt.historyIdx + 1
            data:DeleteChars(0, data.BufTextLen)
            if rt.historyIdx > #rt.history then
                rt.historyIdx = 0
            else
                data:InsertChars(0, rt.history[rt.historyIdx])
            end
        end
    end)
    return 0
end

local function drawSendControls(win, tab)
    local send = SEND_BY_ID[tab.send] or SEND_BY_ID.say
    ImGui.SetNextItemWidth(core.px(88))
    if ImGui.BeginCombo('##tacchatSend_' .. tabKey(win, tab), send.label) then
        for _, s in ipairs(SEND_CHANNELS) do
            if ImGui.Selectable(s.label, s.id == tab.send) then
                tab.send = s.id
                markDirty()
            end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    if tab.send == 'tell' then
        ImGui.SetNextItemWidth(core.px(100))
        local target = ImGui.InputTextWithHint('##tacchatTell_' .. tabKey(win, tab), 'name', tab.tellTarget or '')
        if type(target) == 'string' and target ~= tab.tellTarget then
            tab.tellTarget = target
            markDirty()
        end
        if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then core.setTooltip('Who the tell goes to') end
        ImGui.SameLine(0, 0)
        -- Arrow-only dropdown of recent tell partners (most recent first).
        local CF = ImGuiComboFlags or _G.ImGuiComboFlags
        local flags = (CF and CF.NoPreview) or 0
        ImGui.SetNextItemWidth(core.px(20))
        if ImGui.BeginCombo('##tacchatRecent_' .. tabKey(win, tab), '', flags) then
            if #cfg.recentTells == 0 then ImGui.TextDisabled('No tells yet') end
            for i, name in ipairs(cfg.recentTells) do
                if ImGui.Selectable(name .. '##tacchatRecent_' .. i, name == tab.tellTarget) then
                    tab.tellTarget = name
                    rt.focusRequested = true
                    rt.focusKey = tabKey(win, tab)
                    markDirty()
                end
            end
            ImGui.EndCombo()
        end
        if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then core.setTooltip('Recent tells: pick someone to reply to') end
        ImGui.SameLine()
    end
end

local function drawInput(win, tab)
    drawSendControls(win, tab)
    local F = ImGuiInputTextFlags or _G.ImGuiInputTextFlags
    local flags = (F and F.EnterReturnsTrue) or 0
    if F and F.CallbackHistory then flags = flags + F.CallbackHistory end

    local key = tabKey(win, tab)
    local mine = (rt.focusKey == nil) or (rt.focusKey == key)
    if (rt.focusRequested and mine) or (rt.inputRefocus > 0 and rt.lastInputKey == key) then
        pcall(ImGui.SetKeyboardFocusHere)
        rt.focusRequested = false
        rt.focusKey = nil
        if rt.inputRefocus > 0 then rt.inputRefocus = rt.inputRefocus - 1 end
    end
    -- The draft is per tab (st.input): typing in one window or pane must not
    -- show up in every other input line.
    local st = tabState(win, tab)
    local draft = st.input or ''
    ImGui.PushItemWidth(-1)
    local ok, text, entered = pcall(ImGui.InputText, '##tacchatInput', draft, flags, inputCallback)
    if not ok then
        text, entered = ImGui.InputText('##tacchatInput', draft, (F and F.EnterReturnsTrue) or 0)
    end
    ImGui.PopItemWidth()
    if ImGui.IsItemActive and ImGui.IsItemActive() then rt.lastInputKey = key end
    if type(text) == 'string' then st.input = text end
    if entered == true then
        sendText(tab, st.input or '')
        st.input = ''
        rt.lastInputKey = key
        -- Like the game: Enter sends and hands the keyboard back; the next
        -- Enter re-opens the input. Otherwise keep typing.
        rt.inputRefocus = cfg.enterFocus and 0 or 2
    end
end

local function drawTabContents(win, tab, ti)
    local st = tabState(win, tab)
    local w = (cfg.renderer == 'console') and ensureConsole(win, tab) or nil
    if st.rebuild then rebuildTab(win, tab) end
    st.unread = 0

    -- Status line: only when there is something to say (a recent echo, or
    -- lines that arrived while scrolled up).
    local showEcho = rt.echo and (os.time() - rt.echoAt) < 8
    local showNew = st.newBelow > 0 and not st.atBottom
    -- Lines only move from the event queue into the tabs on the core's plugin
    -- tick; say so when that tick has not come for a while.
    local tickAge = os.time() - (rt.stats.lastTickAt or 0)
    local showStall = rt.stats.lastTickAt > 0 and tickAge >= 2 and not rt.drawEvents
    -- The row is always laid out (empty when quiet) so the log never resizes
    -- when a message comes and goes.
    local statusH = core.px(20)

    local availW, availH = ImGui.GetContentRegionAvail()
    if type(availW) == 'table' or type(availW) == 'userdata' then availH = availW.y end
    -- Below the log: the status row (one text line) and the input row (one
    -- frame), each with its item spacing. Measured, so font scale and the
    -- window's padding cannot push the input off the bottom.
    local okT, textRow = pcall(ImGui.GetTextLineHeightWithSpacing)
    local okF, frameRow = pcall(ImGui.GetFrameHeightWithSpacing)
    textRow = (okT and tonumber(textRow)) or statusH
    frameRow = (okF and tonumber(frameRow)) or core.px(26)
    local logH = math.max(core.px(40), (tonumber(availH) or 300) - textRow - frameRow - core.px(2))
    if cfg.renderer ~= 'console' then
        st.pending = {}
        st.pendingFirst = 1
        st.pendingLast = 0
        drawInlineLog(win, tab, st, logH)
    elseif w then
        local n = 0
        while st.pendingFirst <= st.pendingLast and n < MAX_APPENDS_PER_FRAME do
            consoleAppend(w, renderLine(st.pending[st.pendingFirst], cfg.timestamps))
            st.pending[st.pendingFirst] = nil
            st.pendingFirst = st.pendingFirst + 1
            n = n + 1
        end
        if st.pendingFirst > st.pendingLast then st.pending = {}; st.pendingFirst = 1; st.pendingLast = 0 end
        if st.forceBottom then
            pcall(function() w:ScrollToBottom() end)
            st.forceBottom = false
        end
        local okR = pcall(function() w:Render(ImVec2(0, logH)) end)
        if not okR then pcall(function() w:Render() end) end
    else
        if ImGui.BeginChild('##tacchatFallback_' .. tabKey(win, tab), 0, logH, true) then
            local ring = rt.ring
            for i = math.max(ring.first, ring.last - 300), ring.last do
                local e = ring.items[i]
                if e and tabAccepts(tab, e) then
                    local r, g, b = rgbOf(channelColor(e.channel))
                    ImGui.TextColored(r, g, b, 1, (cfg.timestamps and ('[' .. e.hms .. '] ') or '') .. e.text)
                end
            end
            pcall(ImGui.SetScrollHereY, 1.0)
        end
        ImGui.EndChild()
    end

    if showNew then
        if ImGui.SmallButton(string.format('v %d new##tacchatNew_%s', st.newBelow, tabKey(win, tab))) then
            st.forceBottom = true
        end
        if showEcho then ImGui.SameLine() end
    end
    if showEcho then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], rt.echo)
        if showStall then ImGui.SameLine() end
    end
    if showStall then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('waiting for Triune tick (%ds)', tickAge))
    end
    if not (showNew or showEcho or showStall) then
        if rt.stats.drawErr then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'draw error: ' .. rt.stats.drawErr)
        else
            ImGui.TextDisabled(' ')
        end
    end

    drawInput(win, tab)
end

local function tabLabel(win, tab, ti)
    local st = tabState(win, tab)
    if st.unread > 0 and not isTabActive(win, ti) then
        local flash = (os.time() - (st.flashAt or 0) < 30) and '! ' or ''
        return string.format('%s%s (%d)###tacchatTab_%s', flash, tab.name, st.unread, tabKey(win, tab))
    end
    return string.format('%s###tacchatTab_%s', tab.name, tabKey(win, tab))
end

-- A tab item, drawn with SetSelected when code asked for this tab (selectTab):
-- the flagged call takes (label, nil, flags); if the binding refuses it, the
-- plain form keeps the bar working and the request is dropped.
local function beginTabItem(label, select)
    local TIF = ImGuiTabItemFlags or _G.ImGuiTabItemFlags
    local flags = (select and TIF and TIF.SetSelected) or 0
    if flags == 0 then return ImGui.BeginTabItem(label) == true end
    local ok, a, b = pcall(ImGui.BeginTabItem, label, nil, flags)
    if not ok then return ImGui.BeginTabItem(label) == true end
    if type(a) ~= 'boolean' and type(b) == 'boolean' then return b end
    return a == true
end

-- One pane: a tab bar over the tabs assigned to it.
local function drawPaneTabs(win, pane)
    trace('BeginTabBar pane %d', pane)
    if not ImGui.BeginTabBar('##tacchatTabs_' .. win.id .. '_' .. pane) then
        trace('BeginTabBar returned false')
        return
    end
    local want = rt.selectReq and rt.selectReq[win.id]
    local closeTi = nil
    for ti, tab in ipairs(win.tabs) do
        if (tab.pane or 1) == pane then
            local selected = beginTabItem(tabLabel(win, tab, ti), want == tab.id)
            trace('BeginTabItem %s -> %s', tab.name, tostring(selected))
            if ImGui.IsItemHovered and ImGui.IsItemHovered() and ImGui.IsMouseClicked then
                -- Right-click on the tab (selected or not) opens its menu;
                -- middle-click closes a conversation in the Tells window.
                if ImGui.IsMouseClicked(1) then rt.tabMenuReq = { win = win, ti = ti } end
                if win.tellWindow and ImGui.IsMouseClicked(2) then closeTi = ti end
            end
            if selected then
                if not isTabActive(win, ti) then
                    setActiveTab(win, ti)
                    markDirty()
                end
                guarded('tab ' .. tab.name, drawTabContents, win, tab, ti)
                ImGui.EndTabItem()
                trace('EndTabItem %s', tab.name)
            end
        end
    end
    ImGui.EndTabBar()
    trace('EndTabBar pane %d', pane)
    if closeTi then closeTab(win, closeTi) end
end

local function mouseDelta()
    local dx, dy = 0, 0
    pcall(function()
        local io = ImGui.GetIO()
        local d = io and io.MouseDelta
        if d then dx, dy = d.x or 0, d.y or 0 end
    end)
    return dx, dy
end

-- All panes of a window, side by side ('h') or stacked ('v'), with a
-- draggable splitter bar between them.
local function drawPanes(win)
    local panes = win.panes or 1
    if rt.safeMode then panes = 1 end
    if panes <= 1 then
        drawPaneTabs(win, 1)
        return
    end
    local availW, availH = ImGui.GetContentRegionAvail()
    if type(availW) == 'table' or type(availW) == 'userdata' then availW, availH = availW.x, availW.y end
    availW, availH = tonumber(availW) or 400, tonumber(availH) or 300
    local horizontal = (win.splitDir ~= 'v')
    local bar = core.px(6)
    local total = math.max(bar * panes, (horizontal and availW or availH) - bar * (panes - 1))
    local sizes = win.paneSizes or {}
    for pn = 1, panes do
        local frac = sizes[pn] or (1 / panes)
        local size = math.max(core.px(40), math.floor(total * frac))
        local okChild
        trace('BeginChild pane %d size %d', pn, size)
        if horizontal then
            okChild = ImGui.BeginChild('##tacchatPane_' .. win.id .. '_' .. pn, size, 0, false)
        else
            okChild = ImGui.BeginChild('##tacchatPane_' .. win.id .. '_' .. pn, 0, size, false)
        end
        trace('  pane child -> %s', tostring(okChild))
        if okChild then guarded('pane ' .. pn, drawPaneTabs, win, pn) end
        ImGui.EndChild()
        trace('EndChild pane %d', pn)
        if pn < panes then
            if horizontal then
                ImGui.SameLine(0, 0)
                ImGui.Button('##tacchatSplit_' .. win.id .. '_' .. pn, bar, availH)
                ImGui.SameLine(0, 0)
            else
                ImGui.Button('##tacchatSplit_' .. win.id .. '_' .. pn, availW, bar)
            end
            if ImGui.IsItemActive and ImGui.IsItemActive() then
                local dx, dy = mouseDelta()
                local d = (horizontal and dx or dy) / total
                if d ~= 0 then
                    local a, b = sizes[pn] or (1 / panes), sizes[pn + 1] or (1 / panes)
                    local minF = 0.1
                    d = math.max(-(a - minF), math.min(b - minF, d))
                    sizes[pn], sizes[pn + 1] = a + d, b - d
                    win.paneSizes = sizes
                    markDirty()
                end
            end
            if ImGui.IsItemHovered and ImGui.IsItemHovered() and core.setTooltip then core.setTooltip('Drag to resize the panes') end
        end
    end
end

local function drawWindow(win, wi)
    if not win.open then return end
    local key = (wi == 1) and 'chat' or ('chat_' .. win.id)
    core.pushTheme()
    core.preBeginWindow(key)
    -- Tight chrome: chat is text, not buttons. Pushed after the scale hook so
    -- it wins over the theme's padding; popped after End.
    local SV = ImGuiStyleVar or _G.ImGuiStyleVar
    local pushedVars = 0
    if SV then
        local function pv(id, a, b)
            if id ~= nil and pcall(ImGui.PushStyleVar, id, a, b) then pushedVars = pushedVars + 1 end
        end
        pv(SV.WindowPadding, core.px(4), core.px(3))
        pv(SV.FramePadding, core.px(4), core.px(2))
        pv(SV.ItemSpacing, core.px(4), core.px(2))
    end
    if win.tellWindow then
        pcall(ImGui.SetNextWindowSize, core.px(420), core.px(240), (ImGuiCond and ImGuiCond.FirstUseEver) or 4)
    else
        pcall(ImGui.SetNextWindowSize, core.px(620), core.px(380), (ImGuiCond and ImGuiCond.FirstUseEver) or 4)
    end
    pcall(ImGui.SetNextWindowBgAlpha, win.opacity or cfg.opacity)
    local flags = 0
    if cfg.locked and ImGuiWindowFlags then
        flags = (ImGuiWindowFlags.NoMove or 0) + (ImGuiWindowFlags.NoResize or 0)
    end
    local title = string.format('%s###TriuneChat_%s', win.title, win.id)
    trace('Begin window %s', win.title)
    local open, draw = ImGui.Begin(title, true, flags)
    trace('  window -> %s', tostring(draw))
    if open == false then
        if win.tellWindow then
            -- The Tells window goes away when closed (every conversation with
            -- it); the next tell or name click brings it back.
            rt.closeReq = rt.closeReq or {}
            rt.closeReq[#rt.closeReq + 1] = win
        else
            win.open = false
            markDirty()
            -- Closing the last open window hides the plugin (header button state).
            local any = false
            for _, w in ipairs(cfg.windows) do if w.open then any = true end end
            if not any then
                ctrl.show_chat = false
                core.saveLoadout(true)
            end
        end
    end
    if draw then
        core.postBeginWindow(key)
        guarded('window ' .. win.title, drawPanes, win)
        if rt.tabMenuReq and rt.tabMenuReq.win == win then
            rt.tabMenuTarget = rt.tabMenuReq
            rt.tabMenuReq = nil
            ImGui.OpenPopup('##tacchatTabMenu_' .. win.id)
        end
        if rt.tabMenuTarget and rt.tabMenuTarget.win == win then
            local ti = math.max(1, math.min(#win.tabs, rt.tabMenuTarget.ti))
            drawTabMenu(win, win.tabs[ti], ti)
        end
    end
    -- A programmatic tab selection is a one-frame flag (drawn or not).
    if rt.selectReq then rt.selectReq[win.id] = nil end
    local okEnd, errEnd = pcall(ImGui.End)
    trace('End window %s%s', win.title, okEnd and '' or (' FAILED ' .. tostring(errEnd)))
    if pushedVars > 0 then pcall(ImGui.PopStyleVar, pushedVars) end
    core.popTheme()
    if not okEnd then
        rt.stats.drawErr = 'End window: ' .. tostring(errEnd)
        rt.frameFailed = true
        traceDump(rt.stats.drawErr)
        if not cfg.lastDrawFailed then
            cfg.lastDrawFailed = true
            markDirty()   -- written by the tick saver, not from the draw thread
        end
    end
end

-- Enter, pressed while nothing in ImGui is taking text, opens the chat input
-- the way the game's chat windows do. The input that last had focus gets
-- it; failing that the active tab of the first pane of the first open window.
local function enterPressed()
    local K = ImGuiKey or _G.ImGuiKey
    if not K then return false end
    local okIo, io = pcall(ImGui.GetIO)
    if okIo and io and io.WantTextInput then return false end
    for _, k in ipairs({ K.Enter, K.KeypadEnter }) do
        if k ~= nil then
            local ok, pressed = pcall(ImGui.IsKeyPressed, k, false)
            if ok and pressed == true then return true end
        end
    end
    return false
end

local function focusTargetKey()
    if rt.lastInputKey then
        for _, w in ipairs(cfg.windows) do
            if w.open then
                for _, t in ipairs(w.tabs) do
                    if tabKey(w, t) == rt.lastInputKey then return rt.lastInputKey end
                end
            end
        end
    end
    for _, w in ipairs(cfg.windows) do
        if w.open then
            local want = w.activeByPane and w.activeByPane[1]
            for _, t in ipairs(w.tabs) do
                if (t.pane or 1) == 1 and (want == nil or t.id == want) then return tabKey(w, t) end
            end
            if w.tabs[1] then return tabKey(w, w.tabs[1]) end
        end
    end
    return nil
end

local function pollEnter()
    if not cfg.enterFocus or rt.focusRequested then return end
    if enterPressed() then
        rt.focusKey = focusTargetKey()
        rt.focusRequested = rt.focusKey ~= nil
    end
end

local function drawWindows()
    if not ctrl.show_chat then return end
    pollEnter()
    -- Guard against a config that is not loaded (seen in the field as
    -- "ipairs got nil" on cfg.windows): say what the table held, reload.
    if type(cfg.windows) ~= 'table' then
        if not rt.stats.cfgRepaired then
            rt.stats.cfgRepaired = true
            local keys = {}
            for k, v in pairs(cfg) do keys[#keys + 1] = tostring(k) .. '=' .. type(v) end
            table.sort(keys)
            print(string.format('\ay[Triune Chat]\ax config had no windows at draw time (init ran: %s, keys: %s); reloading',
                tostring(rt.initCount or 0), table.concat(keys, ' ')))
        end
        local ok, err = pcall(loadConfig)
        if not ok or type(cfg.windows) ~= 'table' then
            cfg.windows = defaultWindows()
            if not ok then print('\ar[Triune Chat]\ax config reload failed: ' .. tostring(err)) end
        end
    end
    if rt.trace then rt.trace.frame = (rt.trace.frame or 0) + 1 end
    if rt.frameFailed and not rt.safeMode then
        -- Something in the last frame broke: keep the window usable with the
        -- simplest layout until the cause is fixed.
        rt.safeMode = true
        print('\ay[Triune Chat]\ax switched to safe mode (one pane, default font) after a draw error; /tacchat safemode off to retry.')
    end
    rt.frameFailed = false
    -- A name clicked in a line last frame: open that conversation now, before
    -- the windows are walked, so the list is stable while drawing.
    if rt.tellReq then
        local name = rt.tellReq
        rt.tellReq = nil
        openTellTab(name, true)
    end
    -- Iterate over a snapshot: menu actions may add or remove windows.
    local list = {}
    for i, w in ipairs(cfg.windows) do list[i] = w end
    for wi, win in ipairs(list) do drawWindow(win, wi) end
    if rt.closeReq then
        local reqs = rt.closeReq
        rt.closeReq = nil
        for _, w in ipairs(reqs) do closeWindow(w) end
    end
    drawEditor()
end

-- ----------------------------------------------------------------------------
-- Diagnostics helpers (settings page)
-- ----------------------------------------------------------------------------
local function firstConsole()
    for _, win in ipairs(cfg.windows) do
        for _, tab in ipairs(win.tabs) do
            local st = rt.tabs[tabKey(win, tab)]
            if st and st.console then return st.console end
        end
    end
    return nil
end

local function colorTest()
    local w = firstConsole()
    if not w then echo((cfg.renderer == 'console') and 'Open a chat tab first.' or 'Color test applies to the classic console renderer only.'); return end
    local sample = 'Color test: \\ag green\\ax \\ay yellow\\ax \\ar red\\ax \\a#FF8800 hex orange\\ax plain 100%'
    pcall(function() w:AppendText((sample:gsub('\\a', '\a'))) end)
    echo('Color test appended to the first open tab.')
end

local function linkTest()
    local link = rt.recentLinks[#rt.recentLinks]
    if not link then echo('No linked item seen yet: link an item in chat first.'); return end
    openItemLink(link)
end

-- ----------------------------------------------------------------------------
-- Commands
-- ----------------------------------------------------------------------------
local function findTab(name)
    name = tostring(name or ''):lower()
    for _, win in ipairs(cfg.windows) do
        for ti, tab in ipairs(win.tabs) do
            if tab.name:lower() == name or tab.id:lower() == name then return win, ti end
        end
    end
    return nil
end

function chatCommand(sub, arg1, arg2)
    sub = tostring(sub or 'toggle'):lower()
    if sub == 'show' then
        ctrl.show_chat = true
        for _, w in ipairs(cfg.windows) do w.open = true end
    elseif sub == 'hide' then ctrl.show_chat = false
    elseif sub == 'toggle' or sub == '' then
        ctrl.show_chat = not ctrl.show_chat
        if ctrl.show_chat then
            local any = false
            for _, w in ipairs(cfg.windows) do if w.open then any = true end end
            if not any then cfg.windows[1].open = true end
        end
    elseif sub == 'focus' then
        ctrl.show_chat = true
        rt.focusRequested = true
    elseif sub == 'tell' then
        local name = trim(tostring(arg1 or ''))
        if name == '' then
            print('\ay[Triune Chat]\ax /tacchat tell <name> opens that person\'s tab in the Tells window')
            return
        end
        openTellTab(name, true)
    elseif sub == 'clear' then
        rt.ring = newRing(cfg.maxLines)
        for _, s in pairs(rt.tabs) do s.rebuild = true end
        return
    elseif sub == 'capture' then
        local on = tostring(arg1 or ''):lower()
        if on == 'on' then setCapture(true) elseif on == 'off' then setCapture(false) else setCapture(not cfg.capture) end
        return
    elseif sub == 'tab' then
        local win, ti = findTab(arg1)
        if win then
            selectTab(win, ti)
            win.open = true
            ctrl.show_chat = true
        else
            print('\ay[Triune Chat]\ax no tab named ' .. tostring(arg1))
            return
        end
    elseif sub == 'settings' then
        local win = cfg.windows[1]
        openEditor('tab', win, win.tabs[win.activeTab])
        return
    elseif sub == 'window' then
        local op = tostring(arg1 or ''):lower()
        if op == 'new' then
            newWindow(arg2)
        elseif op == 'close' then
            local w = findWindow(arg2)
            if w then closeWindow(w) else print('\ay[Triune Chat]\ax no window named ' .. tostring(arg2)) end
            return
        else
            print('\ay[Triune Chat]\ax /tacchat window new <name> | close <name>')
            return
        end
    elseif sub == 'mute' or sub == 'unmute' then
        local name = trim(arg1 or ''):lower()
        if name == '' then print('\ay[Triune Chat]\ax /tacchat ' .. sub .. ' <name>'); return end
        cfg.muted[name] = (sub == 'mute') or nil
        invalidateTabs()
        markDirty()
        print(string.format('\ag[Triune Chat]\ax %s %s', sub == 'mute' and 'muted' or 'unmuted', name))
        return
    elseif sub == 'timestamps' then
        cfg.timestamps = not cfg.timestamps
        for _, s in pairs(rt.tabs) do s.rebuild = true end
        markDirty()
        return
    elseif sub == 'reset' then
        closeTabLogs()   -- the old tab states own open log handles
        cfg.windows = defaultWindows()
        rt.tabs = {}
        markDirty()
        print('\ag[Triune Chat]\ax layout reset to defaults')
        return
    elseif sub == 'tabs' then
        print(string.format('\ag[Triune Chat]\ax config v%s from %s', tostring(cfg.version), tostring(rt.configPath)))
        for _, win in ipairs(cfg.windows) do
            for ti, tab in ipairs(win.tabs) do
                local chans = {}
                if tab.channels then
                    for id in pairs(tab.channels) do chans[#chans + 1] = id end
                    table.sort(chans)
                end
                print(string.format('  %s / %s%s: %s', win.title, tab.name, (win.activeTab == ti) and ' (active)' or '',
                    tab.channels and table.concat(chans, ' ') or 'ALL'))
            end
        end
        return
    elseif sub == 'trace' then
        local on = tostring(arg1 or ''):lower()
        if on == 'off' then
            rt.trace = nil
            print('\ay[Triune Chat]\ax draw trace off')
        else
            rt.trace = { steps = {}, n = 0, frame = 0 }
            print('\ag[Triune Chat]\ax draw trace on; the last ' .. TRACE_MAX .. ' steps are written to logs/tac_chat_trace_<Name>.txt on a draw error (or /tacchat trace dump)')
            if on == 'dump' then traceDump('manual dump') end
        end
        return
    elseif sub == 'safemode' then
        local on = tostring(arg1 or ''):lower()
        rt.safeMode = (on == 'on') or (on ~= 'off' and not rt.safeMode)
        rt.stats.drawErr, rt.stats.drawErrShown = nil, nil
        if not rt.safeMode then
            cfg.lastDrawFailed = false
            markDirty()
        end
        invalidateTabs()
        print(string.format('\ag[Triune Chat]\ax safe mode %s', rt.safeMode and 'on (one pane, default font)' or 'off'))
        return
    elseif sub == 'unsplit' then
        for _, w in ipairs(cfg.windows) do unsplit(w) end
        print('\ag[Triune Chat]\ax all windows unsplit')
        return
    elseif sub == 'stats' then
        local s = rt.stats
        print(string.format('\ag[Triune Chat]\ax %d lines (%d unclassified), peak %d/s, slowest drain %.1f ms, history callbacks %d%s',
            s.total, s.unknown, s.peak, s.drainMaxMs, s.cbCalls, s.appendErr and (', append error: ' .. s.appendErr) or ''))
        print(string.format('\ag[Triune Chat]\ax last event %s | last tick %s | last draw %s | queued %d | ring %d | engine %s',
            agoText(s.lastEventAt), agoText(s.lastTickAt), agoText(s.lastDrawAt), #rt.queue, ringCount(rt.ring), ctrl.running and 'running' or 'paused'))
        print(string.format('\ag[Triune Chat]\ax per-frame delivery: %s (%d lines pumped in the draw)', rt.drawEvents and 'on' or 'off', rt.drawPumped))
        if s.holes or s.drawErr then
            print(string.format('\ay[Triune Chat]\ax queue repairs %d (%s) | last renderer error: %s', s.holes or 0, tostring(s.holeInfo), tostring(s.drawErr)))
        end
        return
    else
        print('\ay[Triune Chat]\ax /tacchat [show|hide|toggle|focus|settings|clear|capture on|off|tab <name>|tell <name>|tabs|window new|close <name>|mute|unmute <name>|timestamps|stats|trace on|off|dump|safemode on|off|unsplit|reset]')

        return
    end
    core.saveLoadout(true)
end

-- ----------------------------------------------------------------------------
-- Plugin window declaration (header button, Window Layout manager)
-- ----------------------------------------------------------------------------
plugin.window = {
    label = 'Chat',
    tooltip = 'Toggles the Chat windows (chat plugin; also /tacchat).',
    flag = 'show_chat',
    desc = 'Chat window replacement with filtered tabs',
    headerButton = true,
    order = 35,
    getLock = function() return cfg.locked == true end,
    setLock = function(val) cfg.locked = (val == true); markDirty() end,
}

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
local boundCommands = {}

function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    rt.initCount = (rt.initCount or 0) + 1
    if ctrl and ctrl.show_chat == nil then ctrl.show_chat = false end
    rt.configPath = nil
    loadConfig()
    rt.ring = rt.ring or newRing(cfg.maxLines)
    rt.ring.cap = cfg.maxLines
    for _, s in pairs(rt.tabs) do s.rebuild = true end
    refreshNames(true)
    registerEvents()
    if cfg.capture and not openCapture() then cfg.capture = false end
    if cfg.lastDrawFailed then
        rt.safeMode = true
        print('\ay[Triune Chat]\ax the last session ended with a draw error: starting in safe mode (one pane, default font). /tacchat safemode off to retry the saved layout.')
    end
    for _, cmd in ipairs({ '/tacchat' }) do
        if mq.unbind then pcall(mq.unbind, cmd) end
        local ok = pcall(mq.bind, cmd, chatCommand)
        if ok then table.insert(boundCommands, cmd) end
    end
    print(string.format('\ag[Triune Chat]\ax v%s loaded. /tacchat or /ac chat toggles the chat windows.', plugin.version))
end

function plugin.onDestroy()
    if rt.dirty then saveConfig() end
    unregisterEvents()
    closeCapture()
    closeTabLogs()
    rt.editor = nil
    if mq and mq.unbind then
        for _, cmd in ipairs(boundCommands) do pcall(mq.unbind, cmd) end
    end
    boundCommands = {}
    rt.tabs = {}
    rt.configPath = nil
end

function plugin.onZoned()
    refreshNames(true)
end

function plugin.onTick()
    if not core then return end
    refresh()
    rt.stats.lastTickAt = os.time()
    refreshNames(false)
    drainQueue()
    flushLogs()
    runPendingLink()
    if rt.dirty and os.time() - rt.lastSave >= 2 then saveConfig() end
end

-- Latency. Chat lines reach the plugin through mq.event, and MQ only hands
-- queued events to Lua when doevents is called, which the core's main loop does
-- once per pass (150 ms of delay plus whatever the pass took - about half a
-- second in the field). The draw callback runs every frame, so while the
-- windows are shown it asks MQ for just this plugin's event (other events
-- stay with the core) and drains the queue straight away: a line is on
-- screen the frame after the client printed it. The handler only pushes
-- onto rt.queue, so nothing here can yield or block. The drain here only
-- appends to the ring / tab queues; log files are flushed on the tick.
local function pumpEvents()
    if not rt.drawEvents or type(mq.doevents) ~= 'function' then return end
    local before = #rt.queue
    local ok, err = pcall(mq.doevents, 'TACChatAll')
    if not ok then
        rt.drawEvents = false
        print('\ay[Triune Chat]\ax per-frame event delivery unavailable (' .. tostring(err) .. '); lines arrive on the core tick.')
        return
    end
    if #rt.queue > before then rt.drawPumped = rt.drawPumped + (#rt.queue - before) end
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    rt.stats.lastDrawAt = os.time()
    if ctrl.show_chat then
        pumpEvents()
        if #rt.queue > 0 then drainQueue() end
    end
    drawWindows()
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    core.accent(GOLD, 'Chat Windows')
    local isOpen = (ctrl.show_chat == true)
    if ImGui.Button((isOpen and 'Windows: Visible (Click to Hide)' or 'Windows: Hidden (Click to Show)') .. '##chatToggleWin', core.px(250), core.px(24)) then
        chatCommand(isOpen and 'hide' or 'show')
    end
    ImGui.SameLine()
    if ImGui.Button('Chat Settings...##chatOpenEditor', core.px(140), core.px(24)) then chatCommand('settings') end
    ImGui.SameLine()
    if ImGui.SmallButton('Color test##chatSetColor') then colorTest() end
    ImGui.SameLine()
    if ImGui.SmallButton('Link test##chatSetLink') then linkTest() end
    drawGeneralPage()
    if rt.stats.appendErr then ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Console append error: ' .. rt.stats.appendErr) end
end

function plugin.onCommand(cmd, args)
    if cmd ~= 'chat' then return false end
    refresh()
    chatCommand(args and args[2] or 'toggle', args and args[3], args and args[4])
    return true
end

plugin.help = {
    '  \ag/ac chat [show|hide|toggle|focus|settings|clear|capture on|off|tab <name>|tabs|window new|close <name>|mute|unmute <name>|timestamps|stats|reset]\ax - Chat Windows (also /tacchat)',
}

-- Exposed for tests
plugin.cfg = cfg
plugin.rt = rt
plugin.CHANNELS = CHANNELS
plugin.PRESETS = PRESETS
plugin.SEND_CHANNELS = SEND_CHANNELS
plugin.classify = classify
plugin.resolveLinks = resolveLinks
plugin.stripColors = stripColors
plugin.convertColors = convertColors
plugin.escapeLine = escapeLine
plugin.extractItemLinks = extractItemLinks
plugin.openItemLink = openItemLink
plugin.linkItemId = linkItemId
plugin.lookupInDatabase = lookupInDatabase
plugin.executeLink = executeLink
plugin.tokenize = tokenize
plugin.healQueue = healQueue
plugin.trace = trace
plugin.traceDump = traceDump
plugin.newWindow = newWindow
plugin.probeFonts = probeFonts
plugin.echo = echo
plugin.addTab = addTab
plugin.removeTab = removeTab
plugin.moveTab = moveTab
plugin.moveTabToWindow = moveTabToWindow
plugin.moveTabToPane = moveTabToPane
plugin.unsplit = unsplit
plugin.collapsePanes = collapsePanes
plugin.isTabActive = isTabActive
plugin.setActiveTab = setActiveTab
plugin.closeWindow = closeWindow
plugin.findWindow = findWindow
plugin.noteTeller = noteTeller
plugin.focusTargetKey = focusTargetKey
plugin.pumpEvents = pumpEvents
plugin.pollEnter = pollEnter
plugin.openTellTab = openTellTab
plugin.requestTell = requestTell
plugin.findTellWindow = findTellWindow
plugin.findTellTab = findTellTab
plugin.closeTab = closeTab
plugin.selectTab = selectTab

plugin.layoutEntry = layoutEntry
plugin.runPendingLink = runPendingLink
plugin.sanitizeConfig = sanitizeConfig
plugin.defaultWindows = defaultWindows
plugin.serialize = serialize
plugin.newRing = newRing
plugin.ringPush = ringPush
plugin.ringCount = ringCount
plugin.tabAccepts = tabAccepts
plugin.renderLine = renderLine
plugin.channelColor = channelColor
plugin.ingest = ingest
plugin.drainQueue = drainQueue
plugin.onAnyLine = onAnyLine
plugin.sendText = sendText
plugin.chatCommand = chatCommand
plugin.registeredEvents = function() return registeredEvents end

return plugin
