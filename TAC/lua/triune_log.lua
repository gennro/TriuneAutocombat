--[[
triune_log.lua -- file-backed diagnostic logger for Triune AutoCombat

Three jobs:
  1. A leveled logger (debug / info / warn / error) that core and plugins call
     directly. Debug lines are dropped unless Debug Mode is on; everything else
     is always kept in a small in-memory ring buffer, and written to the log
     file when "Log To File" is on.
  2. A print() hook that tees every chat line Triune (and its plugins) prints
     into the same ring buffer / file, so turning on file logging captures the
     existing telemetry without touching the hundreds of print() sites.
  3. dump(): a one-shot snapshot file (identity, ctrl, runtime scalars, plugin
     status, recent log lines) that a user can attach to a bug report even
     when file logging was never enabled.

Pure Lua -- no mq dependency -- so it loads under the test harness too. The
host passes in the config directory and getter closures for the live flags.
]]

local M = {}

M.LEVELS = { debug = 1, chat = 2, info = 2, warn = 3, error = 4 }
local LEVEL_TAG = { debug = 'DBG', chat = 'MSG', info = 'INF', warn = 'WRN', error = 'ERR' }

local RING_MAX        = 500              -- lines kept in memory for dump()
local MAX_FILE_BYTES  = 8 * 1024 * 1024  -- rotate to .old past this size
local FLUSH_INTERVAL  = 1.0              -- seconds between buffered flushes
local OPEN_RETRY_SEC  = 30               -- back off after a failed open

local st = {
    configDir      = nil,
    dir            = nil,    -- resolved log directory (probed once)
    version        = '?',
    getFileEnabled = function() return false end,
    getDebug       = function() return false end,
    identity       = function() return 'unknown', 'unknown' end, -- server, char
    headerInfo     = nil,    -- function() -> { {k, v}, ... } for session header
    file           = nil,
    filePath       = nil,
    fileTag        = nil,    -- identity tag the open file was named for
    pending        = 0,
    lastFlush      = 0,
    lastOpenFail   = -math.huge,
    lastOpenErr    = nil,
    ring           = {},
    ringPos        = 0,      -- index of the most recent line (circular)
    ringCount      = 0,
    printHooked    = false,
    rawPrint       = nil,
    droppedDebug   = 0,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Remove MQ chat colour codes: \ag \ax \a-r \a#RRGGBB
function M.stripColors(s)
    s = tostring(s or '')
    s = s:gsub('\a#%x%x%x%x%x%x', '')
    s = s:gsub('\a%-?.', '')
    return s
end

local function safeTag(s)
    return (tostring(s or ''):gsub('[^%w%_%-]', '_'))
end

local function timestamp()
    return os.date('%H:%M:%S')
end

local function dateStamp()
    return os.date('%Y-%m-%d %H:%M:%S')
end

-- string.format that never throws on a bad pattern / arg count.
local function fmt(pattern, ...)
    if select('#', ...) == 0 then return tostring(pattern) end
    local ok, s = pcall(string.format, tostring(pattern), ...)
    if ok then return s end
    local parts = { tostring(pattern) }
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, ' ')
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb and (ta == 'number' or ta == 'string') then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Compact, deterministic value rendering for dump files. Depth-limited so a
-- runtime table with cyclic references can't run away.
function M.serializeValue(v, depth, indent, seen)
    depth  = depth or 3
    indent = indent or ''
    seen   = seen or {}
    local tv = type(v)
    if tv == 'string' then
        return string.format('%q', M.stripColors(v))
    elseif tv == 'number' or tv == 'boolean' or tv == 'nil' then
        return tostring(v)
    elseif tv == 'table' then
        if seen[v] then return '<cycle>' end
        if depth <= 0 then
            local n = 0
            for _ in pairs(v) do n = n + 1 end
            return '<table ' .. n .. ' keys>'
        end
        seen[v] = true
        local keys = sortedKeys(v)
        if #keys == 0 then seen[v] = nil; return '{}' end
        local out = { '{' }
        local inner = indent .. '  '
        for _, k in ipairs(keys) do
            local ks = type(k) == 'string' and k or ('[' .. tostring(k) .. ']')
            out[#out + 1] = inner .. ks .. ' = ' .. M.serializeValue(v[k], depth - 1, inner, seen) .. ','
        end
        out[#out + 1] = indent .. '}'
        seen[v] = nil
        return table.concat(out, '\n')
    end
    return '<' .. tv .. '>'
end

-- ---------------------------------------------------------------------------
-- Ring buffer
-- ---------------------------------------------------------------------------

local function ringPush(line)
    st.ringPos = (st.ringPos % RING_MAX) + 1
    st.ring[st.ringPos] = line
    if st.ringCount < RING_MAX then st.ringCount = st.ringCount + 1 end
end

-- Oldest -> newest. `n` caps the count (default: everything held).
function M.recent(n)
    n = math.min(n or st.ringCount, st.ringCount)
    local out = {}
    local start = st.ringPos - n + 1
    for i = 0, n - 1 do
        local idx = ((start + i - 1) % RING_MAX) + 1
        out[#out + 1] = st.ring[idx]
    end
    return out
end

function M.clearRecent()
    st.ring, st.ringPos, st.ringCount = {}, 0, 0
end

-- ---------------------------------------------------------------------------
-- File handling
-- ---------------------------------------------------------------------------

local function probeDir(dir)
    if not dir or dir == '' then return false end
    local test = dir .. '/.triune_log_probe'
    local f = io.open(test, 'w')
    if not f then return false end
    f:close()
    os.remove(test)
    return true
end

-- MQ keeps a Logs/ folder next to config/; prefer that, fall back to config/.
function M.resolveDir()
    if st.dir then return st.dir end
    local base = st.configDir and tostring(st.configDir):gsub('[/\\]+$', '') or nil
    local candidates = {}
    if base then
        candidates[#candidates + 1] = base .. '/../Logs'
        candidates[#candidates + 1] = base .. '/../logs'
        candidates[#candidates + 1] = base
    end
    candidates[#candidates + 1] = '.'
    for _, d in ipairs(candidates) do
        if probeDir(d) then st.dir = d; return d end
    end
    st.dir = base or '.'
    return st.dir
end

local function identityTag()
    local server, char = 'unknown', 'unknown'
    pcall(function() server, char = st.identity() end)
    return safeTag(server) .. '_' .. safeTag(char)
end

function M.filePath()
    return M.resolveDir() .. '/triune_' .. identityTag() .. '.log'
end

function M.dumpPath()
    return M.resolveDir() .. '/triune_dump_' .. identityTag() .. '_' .. os.date('%Y%m%d_%H%M%S') .. '.log'
end

function M.currentFilePath() return st.filePath end
function M.isFileOpen() return st.file ~= nil end
function M.lastOpenError() return st.lastOpenErr end

local function rotateIfLarge(path)
    local f = io.open(path, 'r')
    if not f then return end
    local size = f:seek('end') or 0
    f:close()
    if size < MAX_FILE_BYTES then return end
    os.remove(path .. '.old')
    os.rename(path, path .. '.old')
end

local function writeHeader(f)
    local server, char = 'unknown', 'unknown'
    pcall(function() server, char = st.identity() end)
    f:write(string.format('==== Triune v%s log session %s | %s @ %s ====\n',
        tostring(st.version), dateStamp(), tostring(char), tostring(server)))
    if st.headerInfo then
        local ok, rows = pcall(st.headerInfo)
        if ok and type(rows) == 'table' then
            for _, kv in ipairs(rows) do
                f:write(string.format('  %-14s %s\n', tostring(kv[1]) .. ':', M.stripColors(tostring(kv[2]))))
            end
        end
    end
end

function M.open()
    if st.file then return true end
    local now = os.clock()
    if (now - st.lastOpenFail) < OPEN_RETRY_SEC then return false end
    local path = M.filePath()
    rotateIfLarge(path)
    local f, err = io.open(path, 'a')
    if not f then
        st.lastOpenFail = now
        st.lastOpenErr = tostring(err)
        return false
    end
    st.file, st.filePath, st.fileTag = f, path, identityTag()
    st.lastOpenErr = nil
    writeHeader(f)
    -- Replay what the ring already holds so the file starts with context
    -- from before logging was switched on.
    local held = M.recent()
    if #held > 0 then
        f:write('---- ' .. #held .. ' buffered lines from before file logging was enabled ----\n')
        for _, line in ipairs(held) do f:write(line, '\n') end
        f:write('---- live ----\n')
    end
    f:flush()
    st.pending, st.lastFlush = 0, now
    return true
end

function M.close(reason)
    if not st.file then return end
    pcall(function()
        st.file:write(string.format('==== session end %s%s ====\n', dateStamp(), reason and (' (' .. reason .. ')') or ''))
        st.file:close()
    end)
    st.file, st.filePath, st.fileTag, st.pending = nil, nil, nil, 0
end

function M.flush()
    if st.file and st.pending > 0 then
        pcall(st.file.flush, st.file)
        st.pending = 0
        st.lastFlush = os.clock()
    end
end

local function fileEnabled()
    local ok, v = pcall(st.getFileEnabled)
    return ok and v == true
end

local function debugEnabled()
    local ok, v = pcall(st.getDebug)
    return ok and v == true
end

-- Call once per main-loop pass: opens/closes the file to track the setting,
-- follows a character change (new file name), and flushes buffered writes.
function M.tick()
    local want = fileEnabled()
    if want then
        if st.file and st.fileTag ~= identityTag() then M.close('character changed') end
        if not st.file then M.open() end
        if st.file and st.pending > 0 and (os.clock() - st.lastFlush) >= FLUSH_INTERVAL then M.flush() end
    elseif st.file then
        M.close('file logging disabled')
    end
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

local function emit(level, cat, msg)
    local line = string.format('%s %s [%s] %s', timestamp(), LEVEL_TAG[level] or 'INF', tostring(cat or 'core'), M.stripColors(msg))
    ringPush(line)
    if st.file then
        st.file:write(line, '\n')
        st.pending = st.pending + 1
        if M.LEVELS[level] >= M.LEVELS.warn then M.flush() end
    elseif fileEnabled() then
        if M.open() then
            -- open() replayed the ring (which now includes this line)
        end
    end
end

function M.log(level, cat, pattern, ...)
    if not M.LEVELS[level] then level = 'info' end
    if level == 'debug' and not debugEnabled() then
        st.droppedDebug = st.droppedDebug + 1
        return
    end
    emit(level, cat, fmt(pattern, ...))
end

function M.debug(cat, pattern, ...) return M.log('debug', cat, pattern, ...) end
function M.info(cat, pattern, ...)  return M.log('info', cat, pattern, ...) end
function M.warn(cat, pattern, ...)  return M.log('warn', cat, pattern, ...) end
function M.error(cat, pattern, ...) return M.log('error', cat, pattern, ...) end

function M.isDebug() return debugEnabled() end

-- Everything print()ed while hooked lands here. A leading red colour code is
-- how Triune marks its error lines, so classify those as warnings.
function M.capturePrint(...)
    local n = select('#', ...)
    if n == 0 then return end
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    local raw = table.concat(parts, '\t')
    local level = raw:find('^\ar') and 'warn' or 'chat'
    emit(level, 'chat', raw)
end

function M.hookPrint()
    if st.printHooked then return end
    st.rawPrint = _G.print
    local rawPrint = st.rawPrint
    _G.print = function(...)
        pcall(M.capturePrint, ...)
        return rawPrint(...)
    end
    st.printHooked = true
end

function M.unhookPrint()
    if not st.printHooked then return end
    _G.print = st.rawPrint
    st.printHooked = false
end

-- ---------------------------------------------------------------------------
-- Dump
-- ---------------------------------------------------------------------------

-- sections: array of { title = 'Name', value = <any> } (or a plain table of
-- title -> value). Writes a standalone snapshot file; returns path or nil, err.
function M.dump(sections)
    local path = M.dumpPath()
    local f, err = io.open(path, 'w')
    if not f then return nil, tostring(err) end
    local ok, werr = pcall(function()
        writeHeader(f)
        f:write('\n')
        local list = sections
        if type(sections) == 'table' and #sections == 0 then
            list = {}
            for _, k in ipairs(sortedKeys(sections)) do list[#list + 1] = { title = k, value = sections[k] } end
        end
        for _, sec in ipairs(list or {}) do
            f:write('#### ', tostring(sec.title), '\n')
            local v = sec.value
            if type(v) == 'table' and #v > 0 and type(v[1]) == 'string' then
                for _, line in ipairs(v) do f:write(M.stripColors(line), '\n') end
            else
                f:write(M.serializeValue(v, sec.depth or 3), '\n')
            end
            f:write('\n')
        end
        local held = M.recent()
        f:write('#### Recent log lines (', #held, ')\n')
        for _, line in ipairs(held) do f:write(line, '\n') end
    end)
    f:close()
    if not ok then return nil, tostring(werr) end
    return path
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

-- opts: configDir, version, getFileEnabled(), getDebug(), identity() ->
-- server, char; headerInfo() -> { {k, v}, ... }
function M.init(opts)
    opts = opts or {}
    if opts.configDir      then st.configDir = opts.configDir; st.dir = nil end
    if opts.version        then st.version = opts.version end
    if opts.getFileEnabled then st.getFileEnabled = opts.getFileEnabled end
    if opts.getDebug       then st.getDebug = opts.getDebug end
    if opts.identity       then st.identity = opts.identity end
    if opts.headerInfo     then st.headerInfo = opts.headerInfo end
    return M
end

function M.stats()
    return {
        fileOpen     = st.file ~= nil,
        filePath     = st.filePath,
        pending      = st.pending,
        ringCount    = st.ringCount,
        droppedDebug = st.droppedDebug,
        lastOpenErr  = st.lastOpenErr,
    }
end

-- Test hook: reset everything (closes any open file).
function M._reset()
    M.close('reset')
    M.unhookPrint()
    st.dir, st.configDir = nil, nil
    st.lastOpenFail, st.lastOpenErr = -math.huge, nil
    st.droppedDebug = 0
    M.clearRecent()
end

return M
