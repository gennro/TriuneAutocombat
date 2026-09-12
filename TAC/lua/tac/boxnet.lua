---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/boxnet.lua — Triune Box Network Plugin (MacroQuest Actors)
-- ============================================================================
-- Inter-box communication for players running several characters on one
-- computer. Built on MacroQuest's native `actors` module: every eqgame
-- process's post office talks over a named pipe to the MacroQuest.exe
-- launcher, which routes messages between clients. No extra plugin, no
-- EQBC server, no DanNet.
--
-- What it does (Phase 1):
--   * Peer roster: every box running Triune broadcasts a 1s heartbeat with
--     its vitals (HP/mana/end, zone, mode, running/burn, target, MA, pet).
--     Peers that go quiet for `peerTimeoutSec` drop off the roster.
--   * Remote commands: `/ac net <all|zone|group|Name> <any /ac command>`
--     runs that command on the matching boxes. The receiver just executes
--     `/ac <line>` locally, so every existing command works across boxes.
--   * Camp Here: pushes this character's location as the camp anchor to
--     every trusted box in the same zone.
--   * Ping: RPC round-trip to a peer (latency + "is the launcher up?").
--   * `core.boxnet` API so other plugins can send / subscribe to messages.
--
-- Rules imposed by the actors API (see docs.macroquest.org/lua/actors):
--   * The message handler may not call mq.delay - it throws. The handler
--     here only appends to an inbox; onTick drains it.
--   * Message content must be plain values (nil/string/number/boolean/
--     table). MQ datatype objects (mq.TLO.*) cannot be serialized, so the
--     heartbeat is built from primitives only.
--   * Broadcasts are echoed back to the sender by the launcher; messages
--     from our own character / PID are dropped on receipt.
--   * If MacroQuest.exe (the launcher) is not running, sends to other
--     processes fail with NoConnection - the window says so.
-- ============================================================================

local plugin = {
    id                 = 'boxnet',
    name               = 'Box Network',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Actors-based communication between your boxed characters: peer roster with live vitals, remote /ac commands, Camp Here, and a message API for other plugins.',
    defaultEnabled     = true,
    tickInterval       = 0.1,
    runOutOfCombatOnly = false,
    hasThread          = false,
    window             = { label = 'Box Net', tooltip = 'Toggles the Box Network window (boxnet plugin): peer roster, vitals, and remote commands.', flag = 'show_boxnet', desc = 'Boxed characters roster, vitals, and remote /ac commands', headerButton = true, order = 25 },
}

local core = nil
local ctrl, ImGui, mq = nil, nil, nil

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------
local PROTOCOL_VERSION   = 1
local MAILBOX            = 'tac_boxnet'
local INBOX_MAX          = 500
local LOG_MAX            = 60
local REGISTER_RETRY_SEC = 5.0
local HB_CHANGE_MIN_SEC  = 0.25   -- min spacing for change-triggered heartbeats
local LAUNCHER_HINT_SEC  = 6.0    -- "no peers yet" -> launcher hint after this long
local SCOPES             = { 'all', 'zone', 'group' }

-- ----------------------------------------------------------------------------
-- Persisted settings
-- ----------------------------------------------------------------------------
local cfg = {
    acceptCommands  = true,     -- run /ac commands sent by peers
    trust           = 'all',    -- 'all' (any box on this launcher) | 'allow' (allowlist only)
    allowlist       = {},       -- character names (case-insensitive) when trust == 'allow'
    announce        = true,     -- print received commands to chat
    heartbeatSec    = 1.0,
    peerTimeoutSec  = 5.0,
    defaultScope    = 'all',    -- scope used by the window's quick buttons
}

-- ----------------------------------------------------------------------------
-- Runtime state
-- ----------------------------------------------------------------------------
local net = {
    available      = false,
    actor          = nil,
    err            = nil,
    lastRegisterAt = -1e9,
    inbox          = {},
    peers          = {},   -- [lowerName] = { name, server, account, pid, seenAt, hb, pingMs, lastReply }
    subscribers    = {},   -- [kind] = { fn, ... }
    lastHeartbeatAt = -1e9,
    lastFingerprint = nil,
    startedAt      = 0,
    sent           = 0,
    received       = 0,
    dropped        = 0,
    lastSendStatus = nil,  -- last negative status reported by a callback
    versionWarned  = {},   -- peers already warned about a protocol mismatch
    trace          = false, -- /ac net trace: log every send / receive
    log            = {},   -- newest first: { time, text, level }
    cmdInput       = '',
    allowInput     = nil,
}

local function refresh()
    ctrl = core.ctrl
    ImGui = core.ImGui
    mq = core.mq
end

-- Wall-clock seconds. mq.gettime() (ms) when available; tests override
-- plugin.clock to drive heartbeats and expiry deterministically.
local function nowSec()
    if plugin.clock then return plugin.clock() end
    if mq and mq.gettime then
        local ok, ms = pcall(mq.gettime)
        if ok and type(ms) == 'number' then return ms / 1000 end
    end
    return os.clock()
end

-- Guarded TLO read: returns `default` when the call errors or yields nil.
local function tlo(fn, default)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return default
end

local function lower(s) return tostring(s or ''):lower() end

local function logEvent(text, level)
    table.insert(net.log, 1, { time = os.date('%H:%M:%S'), text = tostring(text), level = level or 'info' })
    while #net.log > LOG_MAX do table.remove(net.log) end
end

local function chat(fmt, ...)
    print(string.format('\ag[BoxNet]\ax ' .. fmt, ...))
end

local function myName()
    return tlo(function() return mq.TLO.Me.CleanName() end, '')
end

local function myPid()
    return tlo(function() return mq.TLO.EverQuest.PID() end, nil)
end

local function myZone()
    return tlo(function() return mq.TLO.Zone.ShortName() end, '')
end

-- ----------------------------------------------------------------------------
-- Payload hygiene: only nil/string/number/boolean/table survive serialization.
-- Strip anything else so a stray TLO object never reaches actors.
-- ----------------------------------------------------------------------------
local function sanitize(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == 'string' or t == 'number' or t == 'boolean' or t == 'nil' then return v end
    if t == 'table' then
        if depth > 8 then return nil end
        local out = {}
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == 'string' or kt == 'number' then
                local sv = sanitize(val, depth + 1)
                if sv ~= nil then out[k] = sv end
            end
        end
        return out
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Transport
-- ----------------------------------------------------------------------------
local function loadActors()
    if plugin.actorsModule ~= nil then
        if plugin.actorsModule == false then return nil, 'actors module unavailable' end
        return plugin.actorsModule
    end
    local ok, mod = pcall(require, 'actors')
    if ok and type(mod) == 'table' and type(mod.register) == 'function' then return mod end
    return nil, tostring(mod)
end

local function onMessage(message)
    -- Handler contract: never block, never delay. Queue and return.
    if #net.inbox >= INBOX_MAX then
        table.remove(net.inbox, 1)
        net.dropped = net.dropped + 1
    end
    net.inbox[#net.inbox + 1] = message
end

local function registerActor()
    if net.actor then return true end
    local t = nowSec()
    if (t - net.lastRegisterAt) < REGISTER_RETRY_SEC then return false end
    net.lastRegisterAt = t
    local actors, err = loadActors()
    if not actors then
        net.available = false
        net.err = 'MacroQuest actors module not available (' .. tostring(err) .. '). Update MacroQuest.'
        return false
    end
    local ok, actorOrErr = pcall(actors.register, MAILBOX, onMessage)
    if not ok then
        net.available = false
        net.err = 'actors.register failed: ' .. tostring(actorOrErr)
        return false
    end
    -- The dropbox is a sol usertype (userdata) in MQ; tests hand in a table.
    -- MQ returns nil when the mailbox name is already registered in this
    -- client (e.g. another Triune instance in the same process).
    local actorType = type(actorOrErr)
    if actorType ~= 'userdata' and actorType ~= 'table' then
        net.available = false
        net.err = 'mailbox "' .. MAILBOX .. '" is already registered in this client; retrying'
        return false
    end
    net.actor = actorOrErr
    net.actorsModule = actors
    net.available = true
    net.err = nil
    logEvent('Mailbox registered (' .. MAILBOX .. ')')
    return true
end

local function unregisterActor()
    if net.actor and net.actor.unregister then pcall(net.actor.unregister, net.actor) end
    net.actor = nil
    net.available = false
end

local function statusName(status)
    local actors = net.actorsModule
    local rs = actors and actors.ResponseStatus
    if type(rs) == 'table' then
        -- sol enums may be read-only proxies; iterate defensively.
        local found = nil
        pcall(function()
            for name, code in pairs(rs) do
                if code == status then found = name end
            end
        end)
        if found then return found end
    end
    if status == -1 then return 'ConnectionClosed' end
    if status == -2 then return 'NoConnection' end
    if status == -3 then return 'RoutingFailed' end
    if status == -4 then return 'AmbiguousRecipient' end
    return tostring(status)
end

local function envelope(kind, data)
    return { v = PROTOCOL_VERSION, kind = kind, from = myName(), ts = os.time(), data = sanitize(data) or {} }
end

-- Raw send. `address` nil = broadcast to every box with this mailbox.
-- `cb(status, message)` makes the message an RPC (receiver must reply).
local function rawSend(address, kind, data, cb)
    if not net.actor then return false end
    local payload = envelope(kind, data)
    local ok, err
    if address and cb then
        ok, err = pcall(net.actor.send, net.actor, address, payload, cb)
    elseif address then
        ok, err = pcall(net.actor.send, net.actor, address, payload)
    elseif cb then
        ok, err = pcall(net.actor.send, net.actor, payload, cb)
    else
        ok, err = pcall(net.actor.send, net.actor, payload)
    end
    if not ok then
        logEvent('send failed: ' .. tostring(err), 'error')
        return false
    end
    net.sent = net.sent + 1
    if net.trace then
        logEvent(string.format('TX %s -> %s', kind, address and (address.character or 'addr') or 'all'))
    end
    return true
end

local function noteStatus(status, context)
    if type(status) == 'number' and status < 0 then
        net.lastSendStatus = status
        logEvent(string.format('%s: %s', context or 'send', statusName(status)), 'error')
        return false
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Peers
-- ----------------------------------------------------------------------------
local function peerKey(name) return lower(name) end

local function touchPeer(sender, hb)
    local name = (hb and hb.name) or (sender and sender.character) or ''
    if name == '' then return nil end
    local key = peerKey(name)
    local p = net.peers[key]
    if not p then
        p = { name = name, firstSeenAt = nowSec() }
        net.peers[key] = p
        logEvent('Peer joined: ' .. name)
    end
    p.name = name
    p.server = (sender and sender.server) or p.server
    p.account = (sender and sender.account) or p.account
    p.pid = (sender and sender.pid) or p.pid
    p.seenAt = nowSec()
    if hb then p.hb = hb end
    return p
end

local function removePeer(name, reason)
    local key = peerKey(name)
    local p = net.peers[key]
    if p then
        net.peers[key] = nil
        logEvent(string.format('Peer left: %s (%s)', p.name, reason or 'timeout'))
    end
end

local function pruneExpired()
    local t = nowSec()
    for key, p in pairs(net.peers) do
        if (t - (p.seenAt or 0)) > cfg.peerTimeoutSec then
            net.peers[key] = nil
            logEvent(string.format('Peer left: %s (timeout)', p.name))
        end
    end
end

-- Sorted roster (by name) for UI and API consumers.
local function peerList()
    local out = {}
    for _, p in pairs(net.peers) do out[#out + 1] = p end
    table.sort(out, function(a, b) return lower(a.name) < lower(b.name) end)
    return out
end

local function peerCount()
    local n = 0
    for _ in pairs(net.peers) do n = n + 1 end
    return n
end

local function findPeer(name)
    return net.peers[peerKey(name)]
end

local function isSelf(sender, payload)
    local me = lower(myName())
    if sender then
        local pid = myPid()
        if pid and sender.pid and sender.pid == pid then return true end
        if me ~= '' and sender.character and lower(sender.character) == me then return true end
    end
    if payload and payload.from and me ~= '' and lower(payload.from) == me and not (sender and sender.character) then
        return true
    end
    return false
end

local function isTrusted(sender, payload)
    if cfg.trust ~= 'allow' then return true end
    local name = (sender and sender.character) or (payload and payload.from) or ''
    name = lower(name)
    for _, allowed in ipairs(cfg.allowlist or {}) do
        if lower(allowed) == name then return true end
    end
    return false
end

local function isGroupMember(name)
    if not name or name == '' then return false end
    return tlo(function()
        local m = mq.TLO.Group.Member(name)
        return m ~= nil and m() ~= nil and (m.ID() or 0) > 0
    end, false) == true
end

-- ----------------------------------------------------------------------------
-- Heartbeat
-- ----------------------------------------------------------------------------
local function snapshot()
    local s = {
        name    = myName(),
        level   = tlo(function() return mq.TLO.Me.Level() end, 0),
        zone    = myZone(),
        zoneId  = tlo(function() return mq.TLO.Zone.ID() end, 0),
        classes = {},
        mode    = ctrl and ctrl.mode or '',
        submode = ctrl and ctrl.submode or '',
        running = (ctrl and ctrl.running == true) or false,
        burn    = (ctrl and ctrl.burn == true) or false,
        ma      = (ctrl and ctrl.ma_name) or '',
        hp      = tlo(function() return mq.TLO.Me.PctHPs() end, 0),
        mana    = tlo(function() return mq.TLO.Me.PctMana() end, 0),
        endur   = tlo(function() return mq.TLO.Me.PctEndurance() end, 0),
        combat  = tlo(function() return mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT') end, false) == true,
        sitting = tlo(function() return mq.TLO.Me.Sitting() end, false) == true,
        casting = tlo(function() return mq.TLO.Me.Casting.Name() end, nil),
        x       = tlo(function() return mq.TLO.Me.X() end, 0),
        y       = tlo(function() return mq.TLO.Me.Y() end, 0),
        z       = tlo(function() return mq.TLO.Me.Z() end, 0),
        pull    = core.runtime and core.runtime.pullState or nil,
        ver     = core.VERSION,
    }
    local classes = core.myClasses
    if type(classes) == 'table' then
        for i, c in ipairs(classes) do s.classes[i] = tostring(c) end
    end
    local tid = tlo(function() return mq.TLO.Target.ID() end, 0)
    if tid and tid > 0 then
        s.target = {
            id   = tid,
            name = tlo(function() return mq.TLO.Target.CleanName() end, ''),
            hp   = tlo(function() return mq.TLO.Target.PctHPs() end, 0),
        }
    end
    local petId = tlo(function() return mq.TLO.Me.Pet.ID() end, 0)
    if petId and petId > 0 then
        s.pet = {
            id   = petId,
            name = tlo(function() return mq.TLO.Me.Pet.CleanName() end, ''),
            hp   = tlo(function() return mq.TLO.Me.Pet.PctHPs() end, 0),
        }
    end
    return s
end

-- Fields whose change is worth an immediate heartbeat (mode flips, targets).
local function fingerprint(s)
    return table.concat({
        s.zone or '', s.mode or '', s.submode or '', tostring(s.running), tostring(s.burn),
        s.ma or '', tostring(s.target and s.target.id or 0), tostring(s.combat), tostring(s.sitting),
    }, '|')
end

local function sendHeartbeat(force)
    if not net.actor then return false end
    local t = nowSec()
    local s = snapshot()
    local fp = fingerprint(s)
    local due = (t - net.lastHeartbeatAt) >= cfg.heartbeatSec
    local changed = (fp ~= net.lastFingerprint) and ((t - net.lastHeartbeatAt) >= HB_CHANGE_MIN_SEC)
    if not (force or due or changed) then return false end
    net.lastHeartbeatAt = t
    net.lastFingerprint = fp
    return rawSend(nil, 'heartbeat', s)
end

-- ----------------------------------------------------------------------------
-- Outbound: commands, camp, ping
-- ----------------------------------------------------------------------------
-- Normalizes a remote command line: strips a leading "/ac", rejects empty
-- lines and anything that would re-enter the network (loops).
local function normalizeLine(line)
    line = tostring(line or ''):gsub('^%s+', ''):gsub('%s+$', '')
    line = line:gsub('^/ac%s+', ''):gsub('^/ac$', '')
    if line == '' then return nil, 'empty command' end
    local first = line:match('^(%S+)'):lower()
    if first == 'net' or first == 'boxnet' then return nil, 'nested net commands are not allowed' end
    return line
end

local function resolveScope(scope)
    scope = lower(scope)
    if scope == '' then scope = cfg.defaultScope or 'all' end
    for _, s in ipairs(SCOPES) do
        if s == scope then return s end
    end
    return 'name', scope
end

-- Sends one or more /ac command lines to a scope: 'all' | 'zone' | 'group' | <Name>.
-- Returns true when something was sent; false, reason otherwise.
local function sendCommand(scope, lines)
    if type(lines) == 'string' then lines = { lines } end
    local clean = {}
    for _, l in ipairs(lines or {}) do
        local n, why = normalizeLine(l)
        if not n then return false, why end
        clean[#clean + 1] = n
    end
    if #clean == 0 then return false, 'empty command' end
    if not net.actor then return false, net.err or 'not connected' end

    local kind, name = resolveScope(scope)
    local summary = table.concat(clean, '; ')
    if kind == 'all' then
        rawSend(nil, 'cmd', { lines = clean, scope = 'all' })
        logEvent('-> all: ' .. summary)
        return true
    elseif kind == 'zone' then
        rawSend(nil, 'cmd', { lines = clean, scope = 'zone', zone = myZone() })
        logEvent('-> zone: ' .. summary)
        return true
    elseif kind == 'group' then
        local sentTo = 0
        for _, p in ipairs(peerList()) do
            if isGroupMember(p.name) then
                local pname = p.name
                rawSend({ character = pname }, 'cmd', { lines = clean, scope = 'group', rpc = true }, function(status, reply)
                    if noteStatus(status, 'cmd -> ' .. pname) then
                        local r = reply and reply.content
                        if r and r.data and r.data.ok == false then
                            logEvent(string.format('%s refused: %s', pname, tostring(r.data.reason)), 'warn')
                        end
                    end
                end)
                sentTo = sentTo + 1
            end
        end
        if sentTo == 0 then return false, 'no known peers in your group' end
        logEvent(string.format('-> group (%d): %s', sentTo, summary))
        return true
    else
        local peer = findPeer(name)
        local target = peer and peer.name or name
        rawSend({ character = target }, 'cmd', { lines = clean, scope = 'name', rpc = true }, function(status, reply)
            if noteStatus(status, 'cmd -> ' .. target) then
                local r = reply and reply.content
                if r and r.data and r.data.ok == false then
                    logEvent(string.format('%s refused: %s', target, tostring(r.data.reason)), 'warn')
                end
            end
        end)
        logEvent('-> ' .. target .. ': ' .. summary)
        return true
    end
end

local function sendCampHere(scope)
    if not net.actor then return false, net.err or 'not connected' end
    local x = tlo(function() return mq.TLO.Me.X() end, nil)
    local y = tlo(function() return mq.TLO.Me.Y() end, nil)
    local z = tlo(function() return mq.TLO.Me.Z() end, nil)
    if not (x and y and z) then return false, 'location unavailable' end
    local data = { x = x, y = y, z = z, zone = myZone(), radius = ctrl and ctrl.camp_radius or nil }
    local kind, name = resolveScope(scope)
    if kind == 'name' then
        data.rpc = true
        rawSend({ character = name }, 'camp', data, function(status) noteStatus(status, 'camp -> ' .. name) end)
        logEvent('-> ' .. name .. ': camp here')
    else
        data.scope = kind
        rawSend(nil, 'camp', data)
        logEvent('-> ' .. kind .. ': camp here')
    end
    return true
end

local function sendPing(name)
    if not net.actor then return false, net.err or 'not connected' end
    local peer = findPeer(name)
    local target = peer and peer.name or name
    if not target or target == '' then return false, 'no peer named' end
    local t0 = nowSec()
    rawSend({ character = target }, 'query', { what = 'ping', rpc = true }, function(status, reply)
        if noteStatus(status, 'ping -> ' .. target) then
            local ms = math.floor((nowSec() - t0) * 1000 + 0.5)
            local p = findPeer(target)
            if p then p.pingMs = ms end
            logEvent(string.format('%s pong: %d ms', target, ms))
        end
    end)
    return true
end

-- ----------------------------------------------------------------------------
-- Inbound
-- ----------------------------------------------------------------------------
-- Subscribers get (data, sender, message). `message` is the raw actors
-- message (message.content is the envelope) so an RPC can be answered with
-- message:reply(status, payload).
local function dispatchSubscribers(kind, payload, sender, message)
    local subs = net.subscribers[kind]
    if not subs then return end
    for _, fn in ipairs(subs) do
        local ok, err = pcall(fn, payload.data, sender, message)
        if not ok then logEvent('subscriber error (' .. kind .. '): ' .. tostring(err), 'error') end
    end
end

-- Replies only when the sender made the message an RPC (data.rpc). Replying
-- to a plain broadcast would just log a "Failed to find RPC" warning on the
-- sender's side.
local function replyTo(message, data, status, payload)
    if not (data and data.rpc) or not message or not message.reply then return end
    pcall(message.reply, message, status, envelope('reply', payload))
end

local function runLines(lines)
    for _, line in ipairs(lines) do
        mq.cmdf('/ac %s', line)
    end
end

local function handleCmd(message, payload, sender)
    local data = payload.data or {}
    local lines = data.lines
    if type(lines) ~= 'table' and type(data.line) == 'string' then lines = { data.line } end
    if type(lines) ~= 'table' or #lines == 0 then return end
    local from = (sender and sender.character) or payload.from or '?'

    -- Broadcast scoped to a zone: silently skip when we are elsewhere.
    if data.scope == 'zone' and lower(data.zone) ~= lower(myZone()) then return end

    local function refuse(reason)
        logEvent(string.format('Refused %s: %s', from, reason), 'warn')
        replyTo(message, data, 1, { ok = false, reason = reason })
    end
    if not cfg.acceptCommands then return refuse('remote commands disabled') end
    if not isTrusted(sender, payload) then return refuse('not on allowlist') end

    -- Re-validate on the receiving side; never trust a peer to have done it.
    local clean = {}
    for _, l in ipairs(lines) do
        local n = normalizeLine(l)
        if n then clean[#clean + 1] = n end
    end
    if #clean == 0 then return refuse('no runnable command') end

    runLines(clean)
    local summary = table.concat(clean, '; ')
    logEvent(string.format('<- %s: %s', from, summary))
    if cfg.announce then chat('%s -> /ac %s', from, summary) end
    replyTo(message, data, 0, { ok = true, ran = clean })
end

local function handleCamp(message, payload, sender)
    local data = payload.data or {}
    local from = (sender and sender.character) or payload.from or '?'
    if not isTrusted(sender, payload) or not cfg.acceptCommands then
        replyTo(message, data, 1, { ok = false, reason = 'not trusted' })
        return
    end
    if lower(data.zone) ~= lower(myZone()) then
        replyTo(message, data, 1, { ok = false, reason = 'different zone' })
        return
    end
    if type(data.x) ~= 'number' or type(data.y) ~= 'number' or type(data.z) ~= 'number' then return end
    if ctrl then
        ctrl.camp_loc = { x = data.x, y = data.y, z = data.z }
        if type(data.radius) == 'number' then ctrl.camp_radius = data.radius end
        if core.saveLoadout then pcall(core.saveLoadout, true) end
    end
    logEvent(string.format('<- %s: camp set at %.0f, %.0f, %.0f', from, data.x, data.y, data.z))
    if cfg.announce then chat('%s set your camp here (%.0f, %.0f, %.0f).', from, data.x, data.y, data.z) end
    replyTo(message, data, 0, { ok = true })
end

local function handleQuery(message, payload)
    local data = payload.data or {}
    if data.what == 'ping' then
        replyTo(message, data, 0, { pong = true, t = data.t })
    elseif data.what == 'snapshot' then
        replyTo(message, data, 0, snapshot())
    else
        replyTo(message, data, 1, { ok = false, reason = 'unknown query' })
    end
end

local function processMessage(message)
    local payload = message and message.content
    if type(payload) ~= 'table' or type(payload.kind) ~= 'string' then
        net.dropped = net.dropped + 1
        net.lastDrop = 'malformed content (' .. type(payload) .. ')'
        if net.trace then logEvent('RX dropped: ' .. net.lastDrop, 'warn') end
        return
    end
    local sender = message.sender
    if net.trace then
        logEvent(string.format('RX %s from %s (pid %s)', tostring(payload.kind),
            tostring(sender and sender.character or payload.from), tostring(sender and sender.pid)))
    end
    if isSelf(sender, payload) then
        net.selfDropped = (net.selfDropped or 0) + 1
        return
    end
    if payload.v ~= PROTOCOL_VERSION then
        net.dropped = net.dropped + 1
        local from = (sender and sender.character) or payload.from or '?'
        local key = lower(from)
        if not net.versionWarned[key] then
            net.versionWarned[key] = true
            logEvent(string.format('%s speaks protocol v%s (we are v%d) - update Triune on both boxes', from, tostring(payload.v), PROTOCOL_VERSION), 'warn')
        end
        return
    end
    net.received = net.received + 1
    local kind = payload.kind

    if kind == 'heartbeat' then
        touchPeer(sender, payload.data)
    elseif kind == 'hello' then
        touchPeer(sender, nil)
        sendHeartbeat(true)
    elseif kind == 'bye' then
        local from = (sender and sender.character) or payload.from
        removePeer(from, 'left')
    elseif kind == 'cmd' then
        touchPeer(sender, nil)
        handleCmd(message, payload, sender)
    elseif kind == 'camp' then
        touchPeer(sender, nil)
        handleCamp(message, payload, sender)
    elseif kind == 'query' then
        touchPeer(sender, nil)
        handleQuery(message, payload)
    else
        -- Application messages from other plugins; only they know the shape.
        touchPeer(sender, nil)
    end
    dispatchSubscribers(kind, payload, sender, message)
end

local function drainInbox()
    if #net.inbox == 0 then return end
    local batch = net.inbox
    net.inbox = {}
    for _, m in ipairs(batch) do
        local ok, err = pcall(processMessage, m)
        if not ok then logEvent('message error: ' .. tostring(err), 'error') end
    end
end

-- ----------------------------------------------------------------------------
-- Tick
-- ----------------------------------------------------------------------------
local function tick()
    if not net.actor then
        if registerActor() then
            net.startedAt = nowSec()
            rawSend(nil, 'hello', {})
            sendHeartbeat(true)
        end
    end
    drainInbox()
    if net.actor then sendHeartbeat(false) end
    pruneExpired()
end

-- ----------------------------------------------------------------------------
-- Public API for other plugins: core.boxnet
-- ----------------------------------------------------------------------------
local api = {}

function api.available() return net.actor ~= nil end
function api.myName() return myName() end
function api.peers() return peerList() end
function api.peer(name) return findPeer(name) end
function api.command(scope, lines) return sendCommand(scope, lines) end
function api.campHere(scope) return sendCampHere(scope) end
function api.ping(name) return sendPing(name) end

-- Broadcast an application message to every box. `kind` should be
-- namespaced by the calling plugin (e.g. 'buffbot:request').
function api.broadcast(kind, data)
    if type(kind) ~= 'string' or kind == '' then return false end
    return rawSend(nil, kind, data)
end

-- Send to one character. With `cb(status, message)` the message is an RPC
-- and the receiver's subscriber is expected to call message:reply().
function api.send(name, kind, data, cb)
    if type(kind) ~= 'string' or kind == '' or not name or name == '' then return false end
    local peer = findPeer(name)
    return rawSend({ character = peer and peer.name or name }, kind, data, cb)
end

-- subscribe(kind, fn(data, sender, message)) -> unsubscribe()
function api.subscribe(kind, fn)
    if type(kind) ~= 'string' or type(fn) ~= 'function' then return function() end end
    net.subscribers[kind] = net.subscribers[kind] or {}
    table.insert(net.subscribers[kind], fn)
    return function()
        local subs = net.subscribers[kind]
        if not subs then return end
        for i = #subs, 1, -1 do
            if subs[i] == fn then table.remove(subs, i) end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
local function fmtAge(sec)
    if sec < 1 then return '<1s' end
    if sec < 60 then return string.format('%ds', math.floor(sec)) end
    return string.format('%dm', math.floor(sec / 60))
end

local function scopeLabel(scope)
    if scope == 'all' then return 'All boxes' end
    if scope == 'zone' then return 'Same zone' end
    if scope == 'group' then return 'My group' end
    return scope
end

local function drawQuickButtons(MUTED)
    local scope = cfg.defaultScope or 'all'
    ImGui.TextDisabled('Send to:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    if ImGui.BeginCombo('##bnScope', scopeLabel(scope)) then
        for _, s in ipairs(SCOPES) do
            if ImGui.Selectable(scopeLabel(s), s == scope) then
                cfg.defaultScope = s
                core.saveLoadout(true)
            end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    if ImGui.Button('Run##bnRun', 60, 22) then sendCommand(scope, 'run') end
    if ImGui.IsItemHovered() then core.setTooltip('Start auto-combat on the selected boxes (/ac run).') end
    ImGui.SameLine()
    if ImGui.Button('Pause##bnPause', 60, 22) then sendCommand(scope, 'pause') end
    if ImGui.IsItemHovered() then core.setTooltip('Pause auto-combat on the selected boxes (/ac pause).') end
    ImGui.SameLine()
    if ImGui.Button('Burn On##bnBurnOn', 70, 22) then sendCommand(scope, 'burn on') end
    ImGui.SameLine()
    if ImGui.Button('Burn Off##bnBurnOff', 70, 22) then sendCommand(scope, 'burn off') end
    ImGui.SameLine()
    if ImGui.Button('Follow Me##bnFollow', 80, 22) then
        sendCommand(scope, { 'ma ' .. myName(), 'assist chase' })
    end
    if ImGui.IsItemHovered() then core.setTooltip('Make the selected boxes set you as Main Assist and switch to Assist (Chase).') end
    ImGui.SameLine()
    if ImGui.Button('Set Me as MA##bnMA', 100, 22) then sendCommand(scope, 'ma ' .. myName()) end
    if ImGui.IsItemHovered() then core.setTooltip('Set this character as the Main Assist on the selected boxes (mode unchanged).') end
    ImGui.SameLine()
    if ImGui.Button('Camp Here##bnCamp', 80, 22) then sendCampHere(scope) end
    if ImGui.IsItemHovered() then core.setTooltip('Set the camp anchor of every selected box in this zone to your current location.') end
    ImGui.TextDisabled('/ac')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(320)
    local txt = ImGui.InputTextWithHint('##bnCmd', 'command to send, e.g. puller camp', net.cmdInput or '')
    if type(txt) == 'string' then net.cmdInput = txt end
    ImGui.SameLine()
    if ImGui.Button('Send##bnSend', 60, 22) then
        local ok, why = sendCommand(scope, net.cmdInput)
        if not ok then logEvent('not sent: ' .. tostring(why), 'warn') end
    end
    ImGui.SameLine()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Same as /ac net <scope> <command>')
end

local function drawPeerTable(GOOD, WARN, ERR, MUTED, ARC)
    local peers = peerList()
    local tableFlags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if not ImGui.BeginTable('BoxNetPeers', 11, tableFlags, ImVec2(0, 200)) then return end
    ImGui.TableSetupColumn('Name', ImGuiTableColumnFlags.WidthFixed, 110)
    ImGui.TableSetupColumn('Trio', ImGuiTableColumnFlags.WidthFixed, 90)
    ImGui.TableSetupColumn('Zone', ImGuiTableColumnFlags.WidthFixed, 80)
    ImGui.TableSetupColumn('Mode', ImGuiTableColumnFlags.WidthFixed, 110)
    ImGui.TableSetupColumn('State', ImGuiTableColumnFlags.WidthFixed, 70)
    ImGui.TableSetupColumn('HP', ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn('Mana', ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn('End', ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn('Target', ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Seen', ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 190)
    ImGui.TableHeadersRow()

    local t = nowSec()
    if #peers == 0 then
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '(no other boxes seen yet)')
    end
    for _, p in ipairs(peers) do
        local hb = p.hb or {}
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], p.name)
        if p.pingMs then
            ImGui.SameLine()
            ImGui.TextDisabled(string.format('%dms', p.pingMs))
        end
        ImGui.TableSetColumnIndex(1)
        ImGui.Text(type(hb.classes) == 'table' and table.concat(hb.classes, '/') or '?')
        ImGui.TableSetColumnIndex(2)
        ImGui.Text(tostring(hb.zone or '?'))
        ImGui.TableSetColumnIndex(3)
        local modeStr = tostring(hb.mode or '?')
        if hb.submode and hb.submode ~= '' then modeStr = modeStr .. ' (' .. tostring(hb.submode) .. ')' end
        ImGui.Text(modeStr)
        ImGui.TableSetColumnIndex(4)
        if hb.running then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Running')
        else
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Paused')
        end
        if hb.burn then
            ImGui.SameLine()
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'B')
        end
        ImGui.TableSetColumnIndex(5)
        local hp = tonumber(hb.hp) or 0
        local hpc = hp <= 35 and ERR or (hp <= 70 and WARN or GOOD)
        ImGui.TextColored(hpc[1], hpc[2], hpc[3], hpc[4], string.format('%d%%', hp))
        ImGui.TableSetColumnIndex(6)
        ImGui.Text(string.format('%d%%', tonumber(hb.mana) or 0))
        ImGui.TableSetColumnIndex(7)
        ImGui.Text(string.format('%d%%', tonumber(hb.endur) or 0))
        ImGui.TableSetColumnIndex(8)
        if hb.target and hb.target.name then
            ImGui.Text(string.format('%s (%d%%)', tostring(hb.target.name), tonumber(hb.target.hp) or 0))
        else
            ImGui.TextDisabled('-')
        end
        ImGui.TableSetColumnIndex(9)
        ImGui.TextDisabled(fmtAge(t - (p.seenAt or t)))
        ImGui.TableSetColumnIndex(10)
        local rowId = '##bn_' .. lower(p.name)
        if ImGui.SmallButton((hb.running and 'Pause' or 'Run') .. rowId) then
            sendCommand(p.name, hb.running and 'pause' or 'run')
        end
        ImGui.SameLine()
        if ImGui.SmallButton((hb.burn and 'Burn Off' or 'Burn On') .. rowId) then
            sendCommand(p.name, hb.burn and 'burn off' or 'burn on')
        end
        ImGui.SameLine()
        if ImGui.SmallButton('Ping' .. rowId) then sendPing(p.name) end
    end
    ImGui.EndTable()
end

local function drawStatusLine(GOOD, WARN, ERR, MUTED)
    if not net.actor then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Actors: unavailable')
        ImGui.SameLine()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], tostring(net.err or 'registering...'))
        return
    end
    local n = peerCount()
    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Actors: connected')
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('| %s | %d peer%s | sent %d | recv %d%s', myName(), n, n == 1 and '' or 's',
        net.sent, net.received, net.dropped > 0 and string.format(' | dropped %d', net.dropped) or ''))
    local warn = nil
    if net.lastSendStatus == -2 or net.lastSendStatus == -1 then
        warn = 'The MacroQuest launcher (MacroQuest.exe) does not appear to be running - it routes messages between boxes.'
    elseif n == 0 and (nowSec() - (net.startedAt or 0)) > LAUNCHER_HINT_SEC then
        warn = 'No other boxes seen. Make sure Triune is running on them and MacroQuest.exe (the launcher) is up.'
    end
    if warn then ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], warn) end
end

local function drawLog(MUTED, WARN, ERR)
    if not ImGui.CollapsingHeader('Event Log##bnLog') then return end
    if ImGui.SmallButton('Clear##bnLogClear') then net.log = {} end
    if ImGui.BeginChild('##bnLogChild', ImVec2(0, 120), true) then
        for _, e in ipairs(net.log) do
            local c = e.level == 'error' and ERR or (e.level == 'warn' and WARN or MUTED)
            ImGui.TextColored(c[1], c[2], c[3], c[4], string.format('[%s] %s', e.time, e.text))
        end
    end
    ImGui.EndChild()
end

local function drawWindow()
    if not ctrl.show_boxnet then return end
    local colors = core.colors or {}
    local GOOD  = colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    local WARN  = colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    local ERR   = colors.ERR or { 0.95, 0.40, 0.40, 1.0 }
    local MUTED = colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    local ARC   = colors.ARC or { 0.30, 0.80, 1.00, 1.0 }

    core.pushTheme()
    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(900, 420, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) ---@diagnostic disable-line: deprecated
    end
    core.preBeginWindow('boxnet')
    local open, draw = ImGui.Begin('Triune Box Network###TriuneBoxNet', ctrl.show_boxnet, windowFlags)
    if not open then
        ctrl.show_boxnet = false
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
    core.postBeginWindow('boxnet')

    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'BOX NETWORK')
    ImGui.SameLine()
    ImGui.TextDisabled('| Boxed characters on this computer (MacroQuest Actors)')
    ImGui.Separator()
    drawStatusLine(GOOD, WARN, ERR, MUTED)
    ImGui.Dummy(0, 4)
    drawQuickButtons(MUTED)
    ImGui.Dummy(0, 4)
    drawPeerTable(GOOD, WARN, ERR, MUTED, ARC)
    ImGui.Dummy(0, 4)
    drawLog(MUTED, WARN, ERR)

    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    if ctrl and ctrl.show_boxnet == nil then ctrl.show_boxnet = false end
    net.inbox = {}
    net.peers = {}
    net.lastRegisterAt = -1e9
    net.lastHeartbeatAt = -1e9
    net.lastFingerprint = nil
    net.lastSendStatus = nil
    net.startedAt = nowSec()
    rawset(core, 'boxnet', api)
    -- Register straight away so other plugins' onInit can already see us.
    if registerActor() then
        rawSend(nil, 'hello', {})
        sendHeartbeat(true)
    end
end

function plugin.onDestroy()
    if net.actor then rawSend(nil, 'bye', {}) end
    unregisterActor()
    net.inbox = {}
    net.peers = {}
    net.subscribers = {}
    if core and rawget(core, 'boxnet') == api then rawset(core, 'boxnet', nil) end
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
    if not core then return end
    refresh()
    sendHeartbeat(true)
end

function plugin.onSaveSettings()
    local allow = {}
    for i, n in ipairs(cfg.allowlist or {}) do allow[i] = tostring(n) end
    return {
        acceptCommands = cfg.acceptCommands == true,
        trust          = cfg.trust == 'allow' and 'allow' or 'all',
        allowlist      = allow,
        announce       = cfg.announce == true,
        heartbeatSec   = cfg.heartbeatSec,
        peerTimeoutSec = cfg.peerTimeoutSec,
        defaultScope   = cfg.defaultScope,
    }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.acceptCommands ~= nil then cfg.acceptCommands = (s.acceptCommands == true) end
    if s.trust == 'allow' or s.trust == 'all' then cfg.trust = s.trust end
    if type(s.allowlist) == 'table' then
        cfg.allowlist = {}
        for _, n in ipairs(s.allowlist) do
            if type(n) == 'string' and n ~= '' then cfg.allowlist[#cfg.allowlist + 1] = n end
        end
    end
    if s.announce ~= nil then cfg.announce = (s.announce == true) end
    if type(s.heartbeatSec) == 'number' then cfg.heartbeatSec = math.max(0.25, math.min(10, s.heartbeatSec)) end
    if type(s.peerTimeoutSec) == 'number' then cfg.peerTimeoutSec = math.max(2, math.min(60, s.peerTimeoutSec)) end
    if type(s.defaultScope) == 'string' then
        local kind = resolveScope(s.defaultScope)
        cfg.defaultScope = (kind ~= 'name') and kind or 'all'
    end
end

local function parseAllowlist(text)
    local out = {}
    for name in tostring(text or ''):gmatch('[^,%s]+') do out[#out + 1] = name end
    return out
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    local GOLD = (core.colors and core.colors.GOLD) or { 1.0, 0.70, 0.54, 1 }
    core.accent(GOLD, 'Box Network (MacroQuest Actors)')
    local isWinOpen = (ctrl.show_boxnet == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##bnToggleWin', 250, 24) then
        ctrl.show_boxnet = not isWinOpen
        core.saveLoadout(true)
    end

    local accept = ImGui.Checkbox('Accept remote /ac commands from other boxes##bnAccept', cfg.acceptCommands)
    if accept ~= cfg.acceptCommands then
        cfg.acceptCommands = accept
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Off: this character ignores commands and Camp Here from every other box (it still shows up on their roster).') end
    local allowOnly = ImGui.Checkbox('Only accept from the allowlist below##bnTrust', cfg.trust == 'allow')
    local newTrust = allowOnly and 'allow' or 'all'
    if newTrust ~= cfg.trust then
        cfg.trust = newTrust
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Default: any box connected to this MacroQuest launcher is trusted. Turn on to restrict to named characters.') end
    if net.allowInput == nil then net.allowInput = table.concat(cfg.allowlist or {}, ', ') end
    ImGui.SetNextItemWidth(320)
    local txt = ImGui.InputTextWithHint('Allowlist##bnAllow', 'Names, comma separated', net.allowInput or '')
    if type(txt) == 'string' then net.allowInput = txt end
    ImGui.SameLine()
    if ImGui.Button('Apply##bnAllowApply', 60, 22) then
        cfg.allowlist = parseAllowlist(net.allowInput)
        core.saveLoadout(true)
    end

    local ann = ImGui.Checkbox('Print received commands to chat##bnAnnounce', cfg.announce)
    if ann ~= cfg.announce then
        cfg.announce = ann
        core.saveLoadout(true)
    end

    ImGui.SetNextItemWidth(200)
    local hb = ImGui.SliderFloat('Heartbeat interval (s)##bnHb', cfg.heartbeatSec, 0.25, 5.0, '%.2f')
    if type(hb) == 'number' and math.abs(hb - cfg.heartbeatSec) > 0.001 then
        cfg.heartbeatSec = hb
        if cfg.peerTimeoutSec < hb * 3 then cfg.peerTimeoutSec = hb * 3 end
        core.saveLoadout(true)
    end
    ImGui.SetNextItemWidth(200)
    local to = ImGui.SliderFloat('Peer timeout (s)##bnTimeout', cfg.peerTimeoutSec, 2.0, 60.0, '%.1f')
    if type(to) == 'number' and math.abs(to - cfg.peerTimeoutSec) > 0.001 then
        cfg.peerTimeoutSec = to
        core.saveLoadout(true)
    end

    if net.actor then
        ImGui.TextDisabled(string.format('Connected as %s | %d peer(s) | sent %d | received %d', myName(), peerCount(), net.sent, net.received))
    else
        ImGui.TextDisabled('Not connected: ' .. tostring(net.err or 'registering...'))
    end
end

-- /ac net                         -> toggle the window
-- /ac net peers|list              -> print the roster
-- /ac net ping <Name>             -> RPC round-trip to a peer
-- /ac net camp [scope]            -> Camp Here
-- /ac net <scope|Name> <command>  -> run /ac <command> on the matching boxes
function plugin.onCommand(cmd, args)
    if cmd ~= 'net' and cmd ~= 'boxnet' then return false end
    refresh()
    -- The core hands over the full /ac argument list (args[1] is 'net' itself).
    local rest = {}
    for i = 2, #(args or {}) do rest[#rest + 1] = args[i] end
    args = rest
    local sub = tostring(args[1] or '')
    local subl = lower(sub)
    if sub == '' then
        ctrl.show_boxnet = not ctrl.show_boxnet
        core.saveLoadout(true)
        chat('Box Network window %s.', ctrl.show_boxnet and 'OPENED' or 'CLOSED')
        return true
    end
    if subl == 'peers' or subl == 'list' or subl == 'who' then
        local peers = peerList()
        if not net.actor then chat('Not connected: %s', tostring(net.err or 'registering...')) end
        chat('%d peer(s):', #peers)
        for _, p in ipairs(peers) do
            local hb = p.hb or {}
            print(string.format('  \ay%s\ax  %s  %s  %s%s  hp %d%%  mana %d%%%s', p.name,
                type(hb.classes) == 'table' and table.concat(hb.classes, '/') or '?', tostring(hb.zone or '?'),
                tostring(hb.mode or '?'), hb.running and ' [running]' or ' [paused]', tonumber(hb.hp) or 0,
                tonumber(hb.mana) or 0, hb.burn and '  BURN' or ''))
        end
        return true
    end
    if subl == 'trace' then
        net.trace = not net.trace
        chat('Trace %s (see the Box Net event log).', net.trace and 'ON' or 'OFF')
        return true
    end
    if subl == 'debug' or subl == 'diag' then
        local pid = myPid()
        chat('Box Network diagnostics:')
        print(string.format('  me: %s  pid: %s  zone: %s  script mailbox: %s', myName(), tostring(pid), myZone(), MAILBOX))
        print(string.format('  actor: %s  available: %s  err: %s', tostring(net.actor), tostring(net.available), tostring(net.err)))
        print(string.format('  sent: %d  received: %d  dropped: %d  self-echo dropped: %d  inbox: %d  last drop: %s',
            net.sent, net.received, net.dropped, net.selfDropped or 0, #net.inbox, tostring(net.lastDrop)))
        print(string.format('  last send status: %s  peers: %d  heartbeat: every %.2fs (last %.1fs ago)',
            net.lastSendStatus and statusName(net.lastSendStatus) or 'none', peerCount(), cfg.heartbeatSec,
            nowSec() - net.lastHeartbeatAt))
        print(string.format('  trust: %s  accept: %s  allowlist: %s', cfg.trust, tostring(cfg.acceptCommands), table.concat(cfg.allowlist or {}, ',')))
        local shown = 0
        for _, e in ipairs(net.log) do
            print(string.format('  [%s] %s', e.time, e.text))
            shown = shown + 1
            if shown >= 12 then break end
        end
        return true
    end
    if subl == 'ping' then
        local ok, why = sendPing(args[2])
        if not ok then chat('Ping not sent: %s', tostring(why)) end
        return true
    end
    if subl == 'camp' or subl == 'camphere' then
        local ok, why = sendCampHere(args[2] or cfg.defaultScope)
        if not ok then chat('Camp Here not sent: %s', tostring(why)) end
        return true
    end
    if #args < 2 then
        chat('Usage: /ac net <all|zone|group|Name> <command>  |  /ac net peers  |  /ac net ping <Name>  |  /ac net camp [scope]  |  /ac net debug  |  /ac net trace')
        return true
    end
    local line = table.concat(args, ' ', 2)
    local ok, why = sendCommand(sub, line)
    if not ok then chat('Not sent: %s', tostring(why)) end
    return true
end

plugin.help = {
    '  \ag/ac net\ax - Toggle the Box Network window (boxnet plugin)',
    '  \ag/ac net <all|zone|group|Name> <command>\ax - Run an /ac command on other boxes (e.g. /ac net all burn on)',
    '  \ag/ac net peers | ping <Name> | camp [scope]\ax - List boxes, ping one, or push your location as their camp',
}

-- Exposed for tests
plugin.api = api
plugin.cfg = cfg
plugin.net = net
plugin.PROTOCOL_VERSION = PROTOCOL_VERSION
plugin.MAILBOX = MAILBOX
plugin.tick = tick
plugin.snapshot = snapshot
plugin.sanitize = sanitize
plugin.normalizeLine = normalizeLine
plugin.resolveScope = resolveScope
plugin.sendCommand = sendCommand
plugin.sendCampHere = sendCampHere
plugin.sendPing = sendPing
plugin.sendHeartbeat = sendHeartbeat
plugin.peerList = peerList
plugin.processMessage = processMessage
plugin.isTrusted = isTrusted

return plugin
