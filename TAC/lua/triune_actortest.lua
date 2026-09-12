-- ============================================================================
-- triune_actortest.lua — 15-second MacroQuest Actors smoke test
-- ============================================================================
-- Run `/lua run triune_actortest` on two boxes at the same time. Each box
-- broadcasts a message every second on the 'triune_actortest' mailbox and
-- prints everything it receives (its own echo from the launcher and the other
-- box's messages). It also fires one RPC at itself so the launcher's routing
-- can be checked without a second box.
--
-- Expected on a working install:  "got #n from <MyName>" (the echo) and
-- "got #n from <OtherName>" lines, plus "self-RPC ok".
-- Nothing received at all = the MacroQuest post office is not routing for
-- this client (MQ build / launcher problem), independent of Triune.
-- ============================================================================
local mq = require('mq')
local ok, actors = pcall(require, 'actors')
if not ok or type(actors) ~= 'table' then
    print('\ar[actortest]\ax actors module not available: ' .. tostring(actors))
    return
end

local me = mq.TLO.Me.CleanName() or '?'
local received = 0

local actor = actors.register('triune_actortest', function(message)
    received = received + 1
    local s = message.sender or {}
    print(string.format('\ag[actortest]\ax got %s from %s (pid %s, mailbox %s)',
        tostring(message.content and message.content.text), tostring(s.character), tostring(s.pid), tostring(s.mailbox)))
    if message.content and message.content.rpc then
        message:reply(0, { pong = true })
    end
end)
if not actor then
    print('\ar[actortest]\ax actors.register returned nil (mailbox already registered?)')
    return
end
print(string.format('\ay[actortest]\ax %s: registered, broadcasting for 15s...', me))

actor:send({ character = me }, { text = 'self-rpc', rpc = true }, function(status)
    print(string.format('\ay[actortest]\ax self-RPC %s (status %s)', status >= 0 and 'ok' or 'FAILED', tostring(status)))
end)

for i = 1, 15 do
    actor:send({ text = '#' .. i .. ' from ' .. me })
    mq.delay(1000)
end

print(string.format('\ay[actortest]\ax %s: done - received %d message(s) in 15s', me, received))
actor:unregister()
