-- ============================================================================
-- triune_actortest.lua — MacroQuest Actors smoke test / bisect
-- ============================================================================
-- `/lua run triune_actortest` on one box is enough: every variant below is a
-- broadcast on the 'triune_actortest' mailbox, and the launcher echoes
-- broadcasts back to the sender, so each variant that works prints "echo OK".
-- Run it on two boxes at once and you also see the other box's messages.
--
-- The variants reproduce, one at a time, the things the boxnet plugin does
-- differently from MQ's buffbeg.lua example, so a missing echo names the
-- culprit:
--   A  plain actor:send({text=...})                        (baseline)
--   B  pcall(actor.send, actor, payload)                   (call style)
--   C  plugin envelope: nested data, arrays, floats, bools (payload shape)
--   D  envelope with ts = os.time()                        (large number)
--   E  envelope with an empty data table                   (empty table)
--   F  five sends back-to-back with no yield               (burst)
--   G  send from inside a coroutine                         (coroutine)
--   H  addressed RPC to self with a callback               (launcher routing)
-- ============================================================================
local mq = require('mq')
local ok, actors = pcall(require, 'actors')
if not ok or type(actors) ~= 'table' then
    print('\ar[actortest]\ax actors module not available: ' .. tostring(actors))
    return
end

local me = mq.TLO.Me.CleanName() or '?'
local seen = {}      -- tag -> count of echoes of OUR OWN sends
local others = 0     -- messages from other boxes
local rpcStatus = nil

local actor = actors.register('triune_actortest', function(message)
    local c = message.content
    local s = message.sender or {}
    local tag = type(c) == 'table' and (c.tag or (c.data and c.data.tag)) or nil
    if s.character and s.character == me then
        if tag then seen[tag] = (seen[tag] or 0) + 1 end
    else
        others = others + 1
        print(string.format('\ag[actortest]\ax from %s: %s', tostring(s.character), tostring(tag or c)))
    end
    if type(c) == 'table' and c.rpc then message:reply(0, { pong = true }) end
end)
if not actor then
    print('\ar[actortest]\ax actors.register returned nil (mailbox already registered?)')
    return
end
print(string.format('\ay[actortest]\ax %s: registered, running variants...', me))

local function envelope(tag, data)
    return { v = 1, kind = 'heartbeat', from = me, data = data, tag = tag }
end
local richData = {
    tag = 'C', name = me, level = 60, zone = 'hateplaneb', zoneId = 186,
    classes = { 'WAR', 'CLR', 'ENC' }, mode = 'Manual', submode = 'Hunt',
    running = false, burn = false, ma = '', hp = 100, mana = 87, endur = 100,
    combat = false, sitting = true, x = 123.456, y = -78.9, z = 3.25, pull = 'IDLE', ver = '2.15',
    target = { id = 1234, name = 'a_gnoll', hp = 50 },
}

-- A: baseline
actor:send({ tag = 'A', text = 'baseline' })
-- B: pcall + dot-call style
local okB, errB = pcall(actor.send, actor, { tag = 'B', text = 'pcall style' })
if not okB then print('\ar[actortest]\ax B send raised: ' .. tostring(errB)) end
-- C: full envelope shape
actor:send(envelope('C', richData))
-- D: envelope with ts
local envD = envelope('D', { tag = 'D' }); envD.ts = os.time()
actor:send(envD)
-- E: envelope with empty data table
local envE = envelope('E', {}); envE.tag = 'E'
actor:send(envE)
-- F: burst
for i = 1, 5 do actor:send({ tag = 'F', n = i }) end
-- G: from a coroutine
local co = coroutine.wrap(function() actor:send({ tag = 'G' }) end)
co()
-- H: RPC to self
actor:send({ character = me }, { tag = 'H', rpc = true }, function(status)
    rpcStatus = status
end)

mq.delay(6000)

local function report(tag, want)
    local n = seen[tag] or 0
    local good = want and (n >= want) or (n > 0)
    print(string.format('%s[actortest]\ax  %s  %-42s echo %s (%d)', good and '\ag' or '\ar', tag, ({
        A = 'plain send', B = 'pcall(actor.send, actor, payload)', C = 'plugin envelope (nested/arrays/floats)',
        D = 'envelope with ts = os.time()', E = 'envelope with empty data table', F = 'burst of five sends',
        G = 'send from inside a coroutine', H = 'RPC to self',
    })[tag], good and 'OK' or 'MISSING', n))
end
report('A'); report('B'); report('C'); report('D'); report('E'); report('F', 5); report('G')
print(string.format('%s[actortest]\ax  H  RPC to self: %s', (rpcStatus ~= nil and rpcStatus >= 0) and '\ag' or '\ar',
    rpcStatus == nil and 'NO REPLY' or (rpcStatus >= 0 and 'OK' or ('status ' .. tostring(rpcStatus)))))
print(string.format('\ay[actortest]\ax %s: done - %d message(s) from other boxes', me, others))
actor:unregister()
