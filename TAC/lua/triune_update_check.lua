--[[
triune_update_check.lua -- PROTOTYPE: non-blocking GitHub release check

    /lua run triune_update_check            check once and print the result
    /lua run triune_update_check verbose    also print every step / HRESULT

What it proves
  Triune has no way to talk to the internet without either spawning a
  process (curl / PowerShell -- freezes eqgame.exe, ruled out) or a luarocks
  module that is not installed. This script tries a third route that needs
  nothing beyond MacroQuest itself:

    LuaJIT ffi  ->  COM  ->  WinHttp.WinHttpRequest.5.1  (async mode)

  MQ2Lua is LuaJIT 2.1 with the ffi library enabled (LuaThread.cpp calls
  open_libraries() with no arguments, which registers ffi). WinHttpRequest
  is the HTTPS client that ships with every Windows (and is implemented by
  Wine). Opened with async = true, Send() returns immediately and the DNS /
  TLS / transfer happens on a WinHTTP worker thread; we poll from the
  script's own coroutine with mq.delay() so the game thread is never held.

  The script measures the wall time of every single COM call it makes and
  reports the longest one, so you can see for yourself that nothing blocks.

Polling strategy
  Two stages, neither of which can block the game thread:
    1. Poll the Status property. It fails (INCORRECT_HANDLE_STATE) until the
       response headers are in and never waits or pumps messages.
    2. Then poll WaitForResponse(0) until it reports the body is complete,
       and only then read ResponseText once. Wine's worker thread reallocs
       the body buffer without holding the lock, so reading the text while
       the body is still streaming would be a data race. Wine also leaves
       WaitForResponse's out-param untouched once the response is already
       complete, so it is pre-set to TRUE before every call.

This is a standalone diagnostic; it does not touch Triune's config.
]]

local mq = require('mq')

local REPO       = 'gennro/TriuneAutocombat'
local API_URL    = 'https://api.github.com/repos/' .. REPO .. '/releases/latest'
local USER_AGENT = 'TriuneAutoCombat-UpdateCheck'
local DEADLINE_S = 20          -- give up (Abort) after this many seconds
local POLL_MS    = 100         -- mq.delay between polls

local verbose = false
for _, a in ipairs({ ... }) do
    if tostring(a):lower() == 'verbose' then verbose = true end
end

local function say(fmt, ...)
    print(string.format('\ay[Triune Update]\ax ' .. fmt, ...))
end
local function dbg(fmt, ...)
    if verbose then print(string.format('\a-w[Triune Update]\ax ' .. fmt, ...)) end
end

-- mq.gettime() is steady_clock milliseconds (returned as a uint64 cdata).
local function nowMs()
    if mq.gettime then return tonumber(mq.gettime()) end
    return os.clock() * 1000
end

-- ---------------------------------------------------------------------------
-- Current version: read `local VERSION = '...'` straight out of triune.lua
-- ---------------------------------------------------------------------------
local function currentVersion()
    local paths = {}
    if mq.luaDir then table.insert(paths, mq.luaDir .. '/triune.lua') end
    table.insert(paths, 'lua/triune.lua')
    for _, p in ipairs(paths) do
        local f = io.open(p, 'r')
        if f then
            for _ = 1, 80 do
                local line = f:read('l')
                if not line then break end
                local v = line:match("^local%s+VERSION%s*=%s*'([^']+)'")
                if v then f:close(); return v end
            end
            f:close()
        end
    end
    return nil
end

-- 'V2.14' / 'v2.15-beta' / '2.0.3' -> { 2, 14 } / { 2, 15 } / { 2, 0, 3 }
local function parseVersion(s)
    s = tostring(s or ''):gsub('^[vV]', '')
    local parts = {}
    for n in s:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    return parts
end

-- >0 if a is newer than b, <0 if older, 0 if equal
local function compareVersions(a, b)
    local pa, pb = parseVersion(a), parseVersion(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Minimal JSON helpers (the release payload is a flat object; we only need
-- a handful of top-level string fields and a completeness check)
-- ---------------------------------------------------------------------------

-- True when `s` is one complete JSON object: braces balance outside of
-- strings and the final non-blank char closes the top level.
local function jsonComplete(s)
    if type(s) ~= 'string' then return false end
    local depth, inStr, esc = 0, false, false
    local lastClose = nil
    for i = 1, #s do
        local c = s:sub(i, i)
        if inStr then
            if esc then esc = false
            elseif c == '\\' then esc = true
            elseif c == '"' then inStr = false end
        elseif c == '"' then inStr = true
        elseif c == '{' or c == '[' then depth = depth + 1
        elseif c == '}' or c == ']' then
            depth = depth - 1
            if depth == 0 then lastClose = i end
        end
    end
    if depth ~= 0 or not lastClose then return false end
    return s:sub(lastClose + 1):match('^%s*$') ~= nil
end

local function jsonUnescape(s)
    s = s:gsub('\\u(%x%x%x%x)', function(h)
        local cp = tonumber(h, 16)
        if cp < 0x80 then return string.char(cp) end
        if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end)
    s = s:gsub('\\(.)', { n = '\n', t = '\t', r = '\r', ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '', f = '' })
    return s
end

-- First occurrence of "key": "value" (values may contain escaped quotes)
local function jsonString(body, key)
    local _, q = body:find('"' .. key .. '"%s*:%s*"')
    if not q then return nil end
    local j, esc = q + 1, false
    while j <= #body do
        local c = body:sub(j, j)
        if esc then esc = false
        elseif c == '\\' then esc = true
        elseif c == '"' then break end
        j = j + 1
    end
    if j > #body then return nil end
    return jsonUnescape(body:sub(q + 1, j - 1))
end

-- ---------------------------------------------------------------------------
-- ffi / COM plumbing
-- ---------------------------------------------------------------------------
local okFfi, ffi = pcall(require, 'ffi')
if not okFfi then
    say('\arFAIL\ax: LuaJIT ffi is not available in this MacroQuest build (%s).', tostring(ffi))
    return
end
say('ffi available: LuaJIT %s, %s %s', tostring(jit and jit.version or '?'), ffi.os, ffi.arch)
if ffi.os ~= 'Windows' then
    say('\arFAIL\ax: this route needs the Windows COM runtime.')
    return
end

-- Keep every declaration explicit. On x86 COM methods are __stdcall and
-- VARIANT is passed by value (16 bytes on the stack); LuaJIT handles both.
ffi.cdef [[
typedef long            HRESULT;
typedef long            LONG;
typedef unsigned long   ULONG;
typedef unsigned long   DWORD;
typedef unsigned short  WORD;
typedef unsigned int    UINT;
typedef unsigned short  VARTYPE;
typedef short           VARIANT_BOOL;
typedef wchar_t*        BSTR;
typedef DWORD           LCID;
typedef long            DISPID;

typedef struct { DWORD Data1; WORD Data2; WORD Data3; unsigned char Data4[8]; } GUID;

typedef struct {
    VARTYPE vt;
    WORD    wReserved1, wReserved2, wReserved3;
    union {
        LONG          lVal;
        DWORD         ulVal;
        VARIANT_BOOL  boolVal;
        BSTR          bstrVal;
        void*         byref;
        double        dblVal;
        long long     llVal;
    };
} VARIANT;

typedef struct IWinHttpRequest IWinHttpRequest;
typedef struct {
    HRESULT (__stdcall *QueryInterface)(IWinHttpRequest*, const GUID*, void**);
    ULONG   (__stdcall *AddRef)(IWinHttpRequest*);
    ULONG   (__stdcall *Release)(IWinHttpRequest*);
    HRESULT (__stdcall *GetTypeInfoCount)(IWinHttpRequest*, UINT*);
    HRESULT (__stdcall *GetTypeInfo)(IWinHttpRequest*, UINT, LCID, void**);
    HRESULT (__stdcall *GetIDsOfNames)(IWinHttpRequest*, const GUID*, wchar_t**, UINT, LCID, DISPID*);
    HRESULT (__stdcall *Invoke)(IWinHttpRequest*, DISPID, const GUID*, LCID, WORD, void*, VARIANT*, void*, UINT*);
    HRESULT (__stdcall *SetProxy)(IWinHttpRequest*, DWORD, VARIANT, VARIANT);
    HRESULT (__stdcall *SetCredentials)(IWinHttpRequest*, BSTR, BSTR, DWORD);
    HRESULT (__stdcall *Open)(IWinHttpRequest*, BSTR, BSTR, VARIANT);
    HRESULT (__stdcall *SetRequestHeader)(IWinHttpRequest*, BSTR, BSTR);
    HRESULT (__stdcall *GetResponseHeader)(IWinHttpRequest*, BSTR, BSTR*);
    HRESULT (__stdcall *GetAllResponseHeaders)(IWinHttpRequest*, BSTR*);
    HRESULT (__stdcall *Send)(IWinHttpRequest*, VARIANT);
    HRESULT (__stdcall *get_Status)(IWinHttpRequest*, LONG*);
    HRESULT (__stdcall *get_StatusText)(IWinHttpRequest*, BSTR*);
    HRESULT (__stdcall *get_ResponseText)(IWinHttpRequest*, BSTR*);
    HRESULT (__stdcall *get_ResponseBody)(IWinHttpRequest*, VARIANT*);
    HRESULT (__stdcall *get_ResponseStream)(IWinHttpRequest*, VARIANT*);
    HRESULT (__stdcall *get_Option)(IWinHttpRequest*, DWORD, VARIANT*);
    HRESULT (__stdcall *put_Option)(IWinHttpRequest*, DWORD, VARIANT);
    HRESULT (__stdcall *WaitForResponse)(IWinHttpRequest*, VARIANT, VARIANT_BOOL*);
    HRESULT (__stdcall *Abort)(IWinHttpRequest*);
    HRESULT (__stdcall *SetTimeouts)(IWinHttpRequest*, LONG, LONG, LONG, LONG);
    HRESULT (__stdcall *SetClientCertificate)(IWinHttpRequest*, BSTR);
    HRESULT (__stdcall *SetAutoLogonPolicy)(IWinHttpRequest*, DWORD);
} IWinHttpRequestVtbl;
struct IWinHttpRequest { const IWinHttpRequestVtbl* lpVtbl; };

HRESULT __stdcall CoInitializeEx(void* reserved, DWORD coinit);
HRESULT __stdcall CLSIDFromProgID(const wchar_t* progId, GUID* clsid);
HRESULT __stdcall CoCreateInstance(const GUID* clsid, void* outer, DWORD ctx, const GUID* iid, void** out);
BSTR    __stdcall SysAllocString(const wchar_t* s);
void    __stdcall SysFreeString(BSTR s);
UINT    __stdcall SysStringLen(BSTR s);
int     __stdcall WideCharToMultiByte(UINT cp, DWORD flags, const wchar_t* src, int srcLen,
                                      char* dst, int dstLen, const char* defChar, int* usedDef);
]]

assert(ffi.sizeof('VARIANT') == 16, 'VARIANT must be 16 bytes')
assert(ffi.sizeof('GUID') == 16, 'GUID must be 16 bytes')

local ole32    = ffi.load('ole32')
local oleaut32 = ffi.load('oleaut32')
local kernel32 = ffi.load('kernel32')

local VT_EMPTY, VT_I4, VT_BOOL = 0, 3, 11
local CLSCTX_INPROC_SERVER      = 0x1
local COINIT_APARTMENTTHREADED  = 0x2
local CP_UTF8                   = 65001
local S_OK, S_FALSE             = 0, 1
local RPC_E_CHANGED_MODE        = -2147417850  -- 0x80010106
local IID_IWinHttpRequest = ffi.new('GUID', 0x016fe2ec, 0xb2c8, 0x45f8,
    { 0xb2, 0x3b, 0x39, 0xe5, 0x3a, 0x75, 0x39, 0x6b })

local function hex(hr) return string.format('0x%08X', tonumber(ffi.cast('DWORD', hr))) end
local function failed(hr) return tonumber(hr) < 0 end

-- Lua (ASCII/UTF-8-ish) string -> zero-terminated wchar_t buffer.
local function wide(s)
    local buf = ffi.new('wchar_t[?]', #s + 1)
    for i = 1, #s do buf[i - 1] = s:byte(i) end
    buf[#s] = 0
    return buf
end

-- Track every BSTR we allocate so nothing leaks whichever way we exit.
local bstrs = {}
local function bstr(s)
    local b = oleaut32.SysAllocString(wide(s))
    assert(b ~= nil, 'SysAllocString failed')
    bstrs[#bstrs + 1] = b
    return b
end
local function freeBstrs()
    for _, b in ipairs(bstrs) do oleaut32.SysFreeString(b) end
    bstrs = {}
end

local function bstrToLua(b)
    if b == nil then return nil end
    local wlen = oleaut32.SysStringLen(b)
    if wlen == 0 then return '' end
    local n = kernel32.WideCharToMultiByte(CP_UTF8, 0, b, wlen, nil, 0, nil, nil)
    if n <= 0 then return nil end
    local buf = ffi.new('char[?]', n)
    kernel32.WideCharToMultiByte(CP_UTF8, 0, b, wlen, buf, n, nil, nil)
    return ffi.string(buf, n)
end

local function variantEmpty()
    local v = ffi.new('VARIANT'); v.vt = VT_EMPTY; return v
end
local function variantBool(b)
    local v = ffi.new('VARIANT'); v.vt = VT_BOOL; v.boolVal = b and -1 or 0; return v
end
local function variantI4(n)
    local v = ffi.new('VARIANT'); v.vt = VT_I4; v.lVal = n; return v
end

-- Wall-time bookkeeping: the whole point of the prototype.
local slowest = { name = '-', ms = 0 }
local function timed(name, fn)
    local t0 = nowMs()
    local r1, r2 = fn()
    local dt = nowMs() - t0
    if dt > slowest.ms then slowest.name, slowest.ms = name, dt end
    dbg('%s -> %s  (%.2f ms)', name, type(r1) == 'number' and hex(r1) or tostring(r1), dt)
    return r1, r2
end

-- ---------------------------------------------------------------------------
-- The check itself
-- ---------------------------------------------------------------------------
local req = nil

local function release()
    if req ~= nil then
        pcall(function() req.lpVtbl.Release(req) end)
        req = nil
    end
    freeBstrs()
end

local function run()
    local cur = currentVersion()
    say('Installed Triune version: %s', cur or '\arunknown\ax')

    -- COM init: S_OK / S_FALSE / RPC_E_CHANGED_MODE all mean COM is usable.
    local hr = timed('CoInitializeEx', function() return ole32.CoInitializeEx(nil, COINIT_APARTMENTTHREADED) end)
    if tonumber(hr) ~= S_OK and tonumber(hr) ~= S_FALSE and tonumber(hr) ~= RPC_E_CHANGED_MODE then
        say('\arFAIL\ax: CoInitializeEx returned %s', hex(hr)); return
    end

    local clsid = ffi.new('GUID')
    hr = timed('CLSIDFromProgID', function() return ole32.CLSIDFromProgID(wide('WinHttp.WinHttpRequest.5.1'), clsid) end)
    if failed(hr) then say('\arFAIL\ax: WinHttp.WinHttpRequest.5.1 is not registered (%s)', hex(hr)); return end

    local out = ffi.new('void*[1]')
    hr = timed('CoCreateInstance', function()
        return ole32.CoCreateInstance(clsid, nil, CLSCTX_INPROC_SERVER, IID_IWinHttpRequest, out)
    end)
    if failed(hr) or out[0] == nil then say('\arFAIL\ax: CoCreateInstance returned %s', hex(hr)); return end
    req = ffi.cast('IWinHttpRequest*', out[0])
    local vt = req.lpVtbl

    -- resolve / connect / send / receive timeouts (ms). These bound the
    -- worker thread, not us, but keep a dead network from lingering.
    hr = timed('SetTimeouts', function() return vt.SetTimeouts(req, 5000, 5000, 5000, 10000) end)
    if failed(hr) then say('\arFAIL\ax: SetTimeouts %s', hex(hr)); return end

    hr = timed('Open(async)', function() return vt.Open(req, bstr('GET'), bstr(API_URL), variantBool(true)) end)
    if failed(hr) then say('\arFAIL\ax: Open %s', hex(hr)); return end

    -- GitHub's API refuses requests without a User-Agent.
    hr = timed('SetRequestHeader(UA)', function() return vt.SetRequestHeader(req, bstr('User-Agent'), bstr(USER_AGENT)) end)
    if failed(hr) then say('\arFAIL\ax: SetRequestHeader %s', hex(hr)); return end
    timed('SetRequestHeader(Accept)', function() return vt.SetRequestHeader(req, bstr('Accept'), bstr('application/vnd.github+json')) end)

    -- Ask for TLS 1.2/1.3 explicitly (older Windows defaults exclude 1.2;
    -- GitHub requires it). Wine does not implement this option -- ignore.
    local optHr = timed('put_Option(SecureProtocols)', function() return vt.put_Option(req, 9, variantI4(0x0800 + 0x2000)) end)
    if failed(optHr) then dbg('SecureProtocols option not supported here (%s) - relying on defaults', hex(optHr)) end

    local t0 = nowMs()
    hr = timed('Send', function() return vt.Send(req, variantEmpty()) end)
    if failed(hr) then say('\arFAIL\ax: Send %s', hex(hr)); return end
    say('Request sent (Send returned in %.2f ms). Polling...', nowMs() - t0)

    -- Poll in two stages, neither of which can block:
    --   1. get_Status fails (ERROR_WINHTTP_INCORRECT_HANDLE_STATE) until the
    --      response headers are in. Cheap, no message pump, no shared buffer.
    --   2. WaitForResponse(0) then confirms the body is fully received. Only
    --      after that is ResponseText read -- Wine's worker thread reallocs
    --      the body buffer without the lock, so reading it earlier would race.
    --      `succeeded` is pre-set to TRUE because Wine leaves it untouched
    --      when the response is already complete.
    local status    = ffi.new('LONG[1]')
    local succeeded = ffi.new('VARIANT_BOOL[1]')
    local polls, headersAt, complete, code = 0, nil, false, nil
    local deadline = t0 + DEADLINE_S * 1000
    while nowMs() < deadline do
        polls = polls + 1
        if not headersAt then
            local sHr = timed('get_Status', function() return vt.get_Status(req, status) end)
            if not failed(sHr) then
                code = tonumber(status[0])
                headersAt = nowMs()
                dbg('headers in after %.0f ms: HTTP %d', headersAt - t0, code)
            end
        end
        if headersAt then
            succeeded[0] = -1
            local wHr = timed('WaitForResponse(0)', function() return vt.WaitForResponse(req, variantI4(0), succeeded) end)
            if not failed(wHr) and succeeded[0] ~= 0 then
                complete = true
                break
            end
        end
        mq.delay(POLL_MS)
    end

    local body = nil
    if complete then
        local pb = ffi.new('BSTR[1]')
        local bHr = timed('get_ResponseText', function() return vt.get_ResponseText(req, pb) end)
        if failed(bHr) then
            say('\arFAIL\ax: ResponseText %s', hex(bHr)); return
        end
        body = bstrToLua(pb[0])
        oleaut32.SysFreeString(pb[0])
    end
    local elapsed = nowMs() - t0

    if not body then
        timed('Abort', function() return vt.Abort(req) end)
        say('\arFAIL\ax: no complete response after %.1f s (%d polls%s). Offline, firewalled, or TLS not negotiable.',
            elapsed / 1000, polls, headersAt and (', HTTP ' .. tostring(code) .. ' headers arrived but body never completed') or '')
        return
    end
    if code == 200 and not jsonComplete(body) then
        say('\arFAIL\ax: response is not a complete JSON object (%d bytes): %s', #body, body:sub(1, 120))
        return
    end

    say('Response: HTTP %d, %d bytes, %.0f ms, %d polls. Slowest single call: %s (%.2f ms).',
        code, #body, elapsed, polls, slowest.name, slowest.ms)

    if code ~= 200 then
        local msg = jsonString(body, 'message')
        say('\arGitHub API error\ax: %s', msg or body:sub(1, 200))
        return
    end

    local tag       = jsonString(body, 'tag_name')
    local name      = jsonString(body, 'name')
    local url       = jsonString(body, 'html_url')
    local published = jsonString(body, 'published_at')
    if not tag then say('\arFAIL\ax: tag_name missing from payload: %s', body:sub(1, 200)); return end

    say('Latest release: \ag%s\ax%s%s', tag,
        (name and name ~= '' and name ~= tag) and ('  "' .. name .. '"') or '',
        published and ('  (' .. published:sub(1, 10) .. ')') or '')
    if url then say('  %s', url) end

    if not cur then
        say('Could not read the installed version, so no comparison was made.')
    else
        local c = compareVersions(tag, cur)
        if c > 0 then
            say('\agA newer release is available\ax: %s -> %s', cur, tag)
        elseif c == 0 then
            say('You are on the latest release (%s).', cur)
        else
            say('Installed %s is ahead of the latest published release %s (dev build?).', cur, tag)
        end
    end
end

local ok, err = pcall(run)
release()
if not ok then say('\arLua error\ax: %s', tostring(err)) end
say('Done.')
