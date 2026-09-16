---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/update_check.lua — Triune Update Checker Plugin
-- ============================================================================
-- Asks GitHub for the latest published Triune release and tells you when it is
-- newer than the copy you are running. Check only: nothing is downloaded or
-- written; the release page link is put on the clipboard on request.
--
-- How it talks to the internet without hitching the game
--   Triune must never spawn a process (curl / PowerShell block eqgame.exe)
--   and has no luarocks socket module. Instead the plugin uses LuaJIT's ffi
--   to drive the WinHttp.WinHttpRequest.5.1 COM object that ships with
--   Windows (and Wine) in *async* mode: Send() returns immediately, the DNS /
--   TLS / transfer runs on WinHTTP's own worker thread, and onTick polls for
--   completion with calls that cannot wait. Verified in-game and under Wine
--   (see triune_update_check.lua, the standalone prototype of this code).
--
-- Polling: two stages, neither of which can block the game thread.
--   1. get_Status fails (INCORRECT_HANDLE_STATE) until the response headers
--      are in. It never waits or pumps window messages.
--   2. WaitForResponse(0) then confirms the body is complete, and only after
--      that is ResponseText read once. Wine's worker thread reallocs the body
--      buffer without holding the lock, so reading earlier would race. Wine
--      also leaves WaitForResponse's out-param untouched once the response is
--      already complete, so it is pre-set to TRUE before every call.
--
-- Everything that can fail (no ffi, COM refused, offline, TLS, rate limit)
-- degrades to a one-line "update check unavailable" reason on the settings
-- page; the auto-check then stays quiet for the rest of the session.
-- ============================================================================

local plugin = {
    id                 = 'update_check',
    name               = 'Update Checker',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Checks GitHub for a newer Triune release (non-blocking, no external process) and notifies you in chat and with a popup.',
    defaultEnabled     = true,
    tickInterval       = 0.25,
    runOutOfCombatOnly = false,
    hasThread          = false,
}

local REPO            = 'gennro/TriuneAutocombat'
local API_URL         = 'https://api.github.com/repos/' .. REPO .. '/releases/latest'
local RELEASES_URL    = 'https://github.com/' .. REPO .. '/releases'
local USER_AGENT      = 'TriuneAutoCombat-UpdateCheck'
local STARTUP_DELAY_S = 20        -- first automatic check this long after load
local REQUEST_TIMEOUT_S = 20      -- Abort a request that has not completed by then
local RETRY_AFTER_S   = 15 * 60   -- automatic retry spacing after a failed check
local FREQUENCIES     = { 'session', 'daily', 'weekly', 'off' }
local FREQUENCY_LABEL = { session = 'Every session', daily = 'Once a day', weekly = 'Once a week', off = 'Never (manual only)' }
local FREQUENCY_SEC   = { daily = 86400, weekly = 7 * 86400 }

local core  = nil
local mq    = nil
local ImGui = nil

-- Persisted through onSaveSettings / onLoadSettings (per character loadout).
local cfg = {
    autoCheck   = true,
    frequency   = 'session',
    popup       = true,       -- open the notice window when a newer release is found
    skipTag     = nil,        -- "Skip this version": no more notices for this tag
    lastCheckAt = nil,        -- os.time() of the last completed check
    lastTag     = nil,        -- tag_name the last successful check returned
}

-- Session state (never persisted)
local st = {
    startedAt      = 0,        -- os.time() at onInit
    nextAutoAt     = nil,      -- os.time() the next automatic check may run
    autoDone       = false,    -- this session's automatic check has run
    unavailable    = nil,      -- reason string when the transport cannot work this session
    checking       = false,
    manual         = false,    -- current check was requested by the user (always report)
    lastError      = nil,
    lastCheckedAt  = nil,      -- os.time() of the last completed check this session
    lastDurationMs = nil,
    result         = nil,      -- { tag, name, url, published, notes, newer }
    noticeOpen     = false,
    noticeTag      = nil,
    remindLater    = false,    -- popup dismissed for this session
    copied         = nil,      -- os.clock() when the link was last copied (button feedback)
}

local function chat(fmt, ...)
    print(string.format('\ay[Triune Update]\ax ' .. fmt, ...))
end

local function saveSettings()
    if core and core.saveLoadout then core.saveLoadout(true) end
end

local function nowMs()
    if mq and mq.gettime then return tonumber(mq.gettime()) end
    return os.clock() * 1000
end

-- ----------------------------------------------------------------------------
-- Version / JSON helpers (pure Lua; exposed on the plugin for the test suite)
-- ----------------------------------------------------------------------------

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

-- Release notes are CHANGELOG markdown; keep the first few lines readable
-- in an ImGui text block (strip heading / emphasis markers, cap the length).
local function summarizeNotes(notes, maxLines, maxChars)
    if type(notes) ~= 'string' or notes == '' then return nil end
    local out, n, total = {}, 0, 0
    for line in (notes .. '\n'):gmatch('([^\n]*)\n') do
        line = line:gsub('\r', ''):gsub('^#+%s*', ''):gsub('%*%*', ''):gsub('`', '')
        if line:match('^%s*%-%-%-%s*$') then break end   -- release.yml appends install notes after ---
        if line:match('%S') then
            n = n + 1
            total = total + #line
            out[#out + 1] = line
            if n >= (maxLines or 12) or total >= (maxChars or 1200) then
                out[#out + 1] = '...'
                break
            end
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, '\n')
end

-- ----------------------------------------------------------------------------
-- Transport: LuaJIT ffi -> WinHttp.WinHttpRequest.5.1 (async)
-- ----------------------------------------------------------------------------
local http = {
    ffi      = nil,
    ole32    = nil,
    oleaut32 = nil,
    kernel32 = nil,
    iid      = nil,
    ready    = false,
    err      = nil,
    -- live request
    req      = nil,      -- IWinHttpRequest*
    bstrs    = nil,      -- BSTRs allocated for the live request
    t0       = 0,
    deadline = 0,
    polls    = 0,
    headers  = false,
    code     = nil,
}

local CDEF = [[
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

local VT_EMPTY, VT_I4, VT_BOOL          = 0, 3, 11
local CLSCTX_INPROC_SERVER              = 0x1
local COINIT_APARTMENTTHREADED          = 0x2
local CP_UTF8                           = 65001
local S_OK, S_FALSE                     = 0, 1
local RPC_E_CHANGED_MODE                = -2147417850  -- 0x80010106
local WinHttpRequestOption_SecureProtocols = 9
local SECURE_TLS12_13                   = 0x0800 + 0x2000

local function hex(hr) return string.format('0x%08X', (tonumber(hr) or 0) % 4294967296) end
local function failed(hr) return (tonumber(hr) or -1) < 0 end

-- One-time ffi setup. Returns true, or false + reason. The cdef is guarded so
-- a plugin reload in the same Lua state does not trip "attempt to redefine".
local function httpSetup()
    if http.ready then return true end
    if http.err then return false, http.err end
    local ok, res = pcall(function()
        local okFfi, ffi = pcall(require, 'ffi')
        if not okFfi then error('LuaJIT ffi is not available in this MacroQuest build') end
        if ffi.os ~= 'Windows' then error('needs the Windows COM runtime (ffi.os = ' .. tostring(ffi.os) .. ')') end
        if not pcall(ffi.typeof, 'IWinHttpRequest') then ffi.cdef(CDEF) end
        if ffi.sizeof('VARIANT') ~= 16 or ffi.sizeof('GUID') ~= 16 then error('unexpected VARIANT/GUID layout') end
        http.ffi      = ffi
        http.ole32    = ffi.load('ole32')
        http.oleaut32 = ffi.load('oleaut32')
        http.kernel32 = ffi.load('kernel32')
        http.iid      = ffi.new('GUID', 0x016fe2ec, 0xb2c8, 0x45f8,
            { 0xb2, 0x3b, 0x39, 0xe5, 0x3a, 0x75, 0x39, 0x6b })   -- IID_IWinHttpRequest
        -- S_OK / S_FALSE / RPC_E_CHANGED_MODE all mean COM is usable on this thread.
        local hr = tonumber(http.ole32.CoInitializeEx(nil, COINIT_APARTMENTTHREADED))
        if hr ~= S_OK and hr ~= S_FALSE and hr ~= RPC_E_CHANGED_MODE then
            error('CoInitializeEx returned ' .. hex(hr))
        end
    end)
    if not ok then
        http.err = tostring(res):gsub('^.-:%d+: ', '')
        return false, http.err
    end
    http.ready = true
    return true
end

local function wide(s)
    local buf = http.ffi.new('wchar_t[?]', #s + 1)
    for i = 1, #s do buf[i - 1] = s:byte(i) end
    buf[#s] = 0
    return buf
end

local function bstr(s)
    local b = http.oleaut32.SysAllocString(wide(s))
    if b == nil then error('SysAllocString failed') end
    http.bstrs[#http.bstrs + 1] = b
    return b
end

local function bstrToLua(b)
    if b == nil then return nil end
    local wlen = http.oleaut32.SysStringLen(b)
    if wlen == 0 then return '' end
    local n = http.kernel32.WideCharToMultiByte(CP_UTF8, 0, b, wlen, nil, 0, nil, nil)
    if n <= 0 then return nil end
    local buf = http.ffi.new('char[?]', n)
    http.kernel32.WideCharToMultiByte(CP_UTF8, 0, b, wlen, buf, n, nil, nil)
    return http.ffi.string(buf, n)
end

local function variant(vt, field, val)
    local v = http.ffi.new('VARIANT')
    v.vt = vt
    if field then v[field] = val end
    return v
end

-- Drop the live request: Abort if still in flight, Release, free BSTRs.
local function httpClose(abort)
    if http.req ~= nil then
        local req = http.req
        http.req = nil
        pcall(function()
            if abort then req.lpVtbl.Abort(req) end
            req.lpVtbl.Release(req)
        end)
    end
    if http.bstrs then
        for _, b in ipairs(http.bstrs) do pcall(http.oleaut32.SysFreeString, b) end
    end
    http.bstrs = nil
end

-- Start an async GET. Returns true, or false + reason. Never waits.
local function httpBegin(url)
    local ok, why = httpSetup()
    if not ok then return false, why end
    httpClose(true)
    http.bstrs = {}
    local okRun, res = pcall(function()
        local ffi = http.ffi
        local clsid = ffi.new('GUID')
        local hr = http.ole32.CLSIDFromProgID(wide('WinHttp.WinHttpRequest.5.1'), clsid)
        if failed(hr) then error('WinHttp.WinHttpRequest.5.1 is not registered (' .. hex(hr) .. ')') end
        local out = ffi.new('void*[1]')
        hr = http.ole32.CoCreateInstance(clsid, nil, CLSCTX_INPROC_SERVER, http.iid, out)
        if failed(hr) or out[0] == nil then error('CoCreateInstance failed (' .. hex(hr) .. ')') end
        http.req = ffi.cast('IWinHttpRequest*', out[0])
        local req, vt = http.req, http.req.lpVtbl
        -- resolve / connect / send / receive (ms): bounds the worker, not us
        hr = vt.SetTimeouts(req, 5000, 5000, 5000, 10000)
        if failed(hr) then error('SetTimeouts failed (' .. hex(hr) .. ')') end
        hr = vt.Open(req, bstr('GET'), bstr(url), variant(VT_BOOL, 'boolVal', -1))
        if failed(hr) then error('Open failed (' .. hex(hr) .. ')') end
        -- GitHub's API refuses requests without a User-Agent.
        hr = vt.SetRequestHeader(req, bstr('User-Agent'), bstr(USER_AGENT))
        if failed(hr) then error('SetRequestHeader failed (' .. hex(hr) .. ')') end
        vt.SetRequestHeader(req, bstr('Accept'), bstr('application/vnd.github+json'))
        -- TLS 1.2/1.3 explicitly (older Windows defaults exclude 1.2; GitHub
        -- requires it). Wine does not implement the option: ignore the result.
        vt.put_Option(req, WinHttpRequestOption_SecureProtocols, variant(VT_I4, 'lVal', SECURE_TLS12_13))
        hr = vt.Send(req, variant(VT_EMPTY))
        if failed(hr) then error('Send failed (' .. hex(hr) .. ')') end
    end)
    if not okRun then
        httpClose(true)
        return false, tostring(res):gsub('^.-:%d+: ', '')
    end
    http.t0       = nowMs()
    http.deadline = http.t0 + REQUEST_TIMEOUT_S * 1000
    http.polls    = 0
    http.headers  = false
    http.code     = nil
    return true
end

-- One non-blocking poll. Returns 'pending' | 'done', code, body | 'error', reason.
local function httpPoll()
    if http.req == nil then return 'error', 'no request in flight' end
    local ffi = http.ffi
    local req, vt = http.req, http.req.lpVtbl
    http.polls = http.polls + 1
    local status, body = nil, nil
    local okRun, res = pcall(function()
        if not http.headers then
            local s = ffi.new('LONG[1]')
            if not failed(vt.get_Status(req, s)) then
                http.headers = true
                http.code = tonumber(s[0])
            end
        end
        if http.headers then
            local succeeded = ffi.new('VARIANT_BOOL[1]')
            succeeded[0] = -1
            local hr = vt.WaitForResponse(req, variant(VT_I4, 'lVal', 0), succeeded)
            if not failed(hr) and succeeded[0] ~= 0 then
                local pb = ffi.new('BSTR[1]')
                hr = vt.get_ResponseText(req, pb)
                if failed(hr) then error('ResponseText failed (' .. hex(hr) .. ')') end
                body = bstrToLua(pb[0]) or ''
                http.oleaut32.SysFreeString(pb[0])
                status = 'done'
            end
        end
    end)
    if not okRun then
        httpClose(true)
        return 'error', tostring(res):gsub('^.-:%d+: ', '')
    end
    if status == 'done' then
        local code = http.code
        httpClose(false)
        return 'done', code, body
    end
    if nowMs() >= http.deadline then
        local why = http.headers
            and string.format('HTTP %s headers arrived but the body never completed', tostring(http.code))
            or 'no response (offline, firewalled, or TLS could not be negotiated)'
        httpClose(true)
        return 'error', why
    end
    return 'pending'
end

-- ----------------------------------------------------------------------------
-- The check
-- ----------------------------------------------------------------------------
local function releaseUrl(tag)
    if tag and tag ~= '' then return RELEASES_URL .. '/tag/' .. tag end
    return RELEASES_URL
end

local function startCheck(manual)
    if st.checking then
        if manual then chat('A check is already running.') end
        return false
    end
    if st.unavailable and not manual then return false end
    local ok, why = httpBegin(API_URL)
    if not ok then
        st.unavailable = why
        st.lastError = why
        st.lastCheckedAt = os.time()
        if manual then chat('\arUpdate check unavailable\ax: %s', why) end
        if core and core.log then core.log.warn('update_check', 'transport unavailable: %s', tostring(why)) end
        return false
    end
    st.checking = true
    st.manual = manual == true
    st.lastError = nil
    if manual then chat('Checking %s for a newer release...', REPO) end
    return true
end

local function finishError(why)
    st.checking = false
    st.lastError = why
    st.lastCheckedAt = os.time()
    st.nextAutoAt = os.time() + RETRY_AFTER_S
    if st.manual then chat('\arUpdate check failed\ax: %s', why) end
    if core and core.log then core.log.warn('update_check', 'check failed: %s', tostring(why)) end
end

local function finishResponse(code, body)
    st.checking = false
    st.lastCheckedAt = os.time()
    st.lastDurationMs = nowMs() - http.t0
    if code ~= 200 then
        local msg = body and jsonString(body, 'message') or nil
        if code == 403 and msg and msg:lower():find('rate limit', 1, true) then msg = 'GitHub API rate limit reached, try again later' end
        st.nextAutoAt = os.time() + RETRY_AFTER_S
        st.lastError = string.format('GitHub answered HTTP %s%s', tostring(code), msg and (': ' .. msg) or '')
        if st.manual then chat('\ar%s\ax', st.lastError) end
        return
    end
    if not jsonComplete(body) then
        st.nextAutoAt = os.time() + RETRY_AFTER_S
        st.lastError = 'incomplete response from GitHub'
        if st.manual then chat('\ar%s\ax', st.lastError) end
        return
    end
    local tag = jsonString(body, 'tag_name')
    if not tag or tag == '' then
        st.nextAutoAt = os.time() + RETRY_AFTER_S
        st.lastError = 'no release tag in the GitHub response'
        if st.manual then chat('\ar%s\ax', st.lastError) end
        return
    end
    local cur = core and core.VERSION or '?'
    local cmp = compareVersions(tag, cur)
    st.result = {
        tag       = tag,
        name      = jsonString(body, 'name'),
        url       = jsonString(body, 'html_url') or releaseUrl(tag),
        published = (jsonString(body, 'published_at') or ''):sub(1, 10),
        notes     = summarizeNotes(jsonString(body, 'body')),
        newer     = cmp > 0,
        cmp       = cmp,
    }
    st.lastError = nil
    cfg.lastCheckAt = os.time()
    cfg.lastTag = tag
    saveSettings()

    local r = st.result
    if r.newer then
        local skipped = (cfg.skipTag == tag)
        if st.manual or not skipped then
            chat('\agA newer Triune release is available\ax: %s -> \ag%s\ax%s', cur, tag,
                r.published ~= '' and ('  (' .. r.published .. ')') or '')
            chat('  %s', r.url)
            if skipped and st.manual then chat('  (you chose to skip %s; /ac update unskip to be reminded again)', tag) end
        end
        if cfg.popup and not skipped and not st.remindLater then
            st.noticeOpen = true
            st.noticeTag = tag
        elseif st.manual then
            st.noticeOpen = true
            st.noticeTag = tag
        end
    elseif st.manual then
        if cmp == 0 then
            chat('You are on the latest release (%s).', cur)
        else
            chat('Installed %s is ahead of the latest published release %s.', cur, tag)
        end
    end
end

local function frequencyDue()
    if not cfg.autoCheck or cfg.frequency == 'off' then return false end
    local span = FREQUENCY_SEC[cfg.frequency]
    if span and cfg.lastCheckAt and (os.time() - cfg.lastCheckAt) < span then return false end
    return true
end

-- ----------------------------------------------------------------------------
-- UI
-- ----------------------------------------------------------------------------
local function copyLink(url)
    local ok = pcall(ImGui.SetClipboardText, url)
    if ok then
        st.copied = os.clock()
        chat('Release link copied to the clipboard: %s', url)
    else
        chat('Release page: %s', url)
    end
end

local function drawNotice()
    local r = st.result
    if not st.noticeOpen or not r then return end
    local colors = core.colors or {}
    local GOOD  = colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    local MUTED = colors.MUTED or { 0.55, 0.60, 0.65, 1.0 }
    local ARC   = colors.ARC or { 0.30, 0.80, 1.00, 1.0 }
    local GOLD  = colors.GOLD or { 1.0, 0.70, 0.54, 1 }

    core.pushTheme()
    ImGui.SetNextWindowSize(core.px(460), core.px(300), ImGuiCond.FirstUseEver)
    local flags = 0
    if ImGuiWindowFlags then flags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding) end ---@diagnostic disable-line: deprecated
    core.preBeginWindow('update_check')
    local open, draw = ImGui.Begin('Triune Update Available###TriuneUpdateNotice', true,
        core.windowFlags and core.windowFlags('update_check', flags) or flags)
    if not open then
        st.noticeOpen = false
        st.remindLater = true
        if core.preEndWindow then core.preEndWindow('update_check', false) end
        ImGui.End()
        core.popTheme()
        return
    end
    if not draw then
        if core.preEndWindow then core.preEndWindow('update_check', false) end
        ImGui.End()
        core.popTheme()
        return
    end
    core.postBeginWindow('update_check')

    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'TRIUNE AUTOCOMBAT UPDATE')
    ImGui.Separator()
    ImGui.Dummy(0, core.px(4))
    if r.newer then
        ImGui.Text('A newer release is available:')
        ImGui.SameLine()
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], r.tag)
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('(you are on %s)', tostring(core.VERSION)))
    elseif r.cmp == 0 then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('You are on the latest release (%s).', tostring(core.VERSION)))
    else
        ImGui.Text(string.format('Installed %s is ahead of the latest published release %s.', tostring(core.VERSION), r.tag))
    end
    if r.name and r.name ~= '' and r.name ~= r.tag then
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], r.name)
    end
    if r.published ~= '' then ImGui.TextDisabled('Published ' .. r.published) end
    ImGui.Dummy(0, core.px(4))

    if r.notes then
        ImGui.TextDisabled('Release notes')
        if ImGui.BeginChild('##updNotes', 0, core.px(130), true) then
            ImGui.PushTextWrapPos(0)
            ImGui.TextUnformatted(r.notes)
            ImGui.PopTextWrapPos()
        end
        ImGui.EndChild()
        ImGui.Dummy(0, core.px(4))
    end

    local copiedRecently = st.copied and (os.clock() - st.copied) < 2.0
    if ImGui.Button((copiedRecently and 'Copied!' or 'Copy Release Link') .. '##updCopy', core.px(150), core.px(24)) then
        copyLink(r.url)
    end
    core.setTooltip('%s', r.url)
    ImGui.SameLine()
    if r.newer then
        if ImGui.Button('Skip This Version##updSkip', core.px(140), core.px(24)) then
            cfg.skipTag = r.tag
            st.noticeOpen = false
            saveSettings()
            chat('Skipping %s. /ac update unskip to be reminded again.', r.tag)
        end
        core.setTooltip('No more popups or chat notices for %s. Newer releases still notify.', r.tag)
        ImGui.SameLine()
        if ImGui.Button('Remind Me Later##updLater', core.px(130), core.px(24)) then
            st.noticeOpen = false
            st.remindLater = true
        end
        core.setTooltip('Closes this notice for the rest of this session.')
    else
        if ImGui.Button('Close##updClose', core.px(100), core.px(24)) then
            st.noticeOpen = false
        end
    end
    ImGui.Dummy(0, core.px(2))
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Download TriuneAutocombat-Update.zip from the release page and extract it into your MacroQuest folder.')

    if core.preEndWindow then core.preEndWindow('update_check', false) end
    ImGui.End()
    core.popTheme()
end

-- ----------------------------------------------------------------------------
-- Plugin lifecycle
-- ----------------------------------------------------------------------------
function plugin.onInit(coreApi)
    core = coreApi
    mq = core.mq
    ImGui = core.ImGui
    st.startedAt = os.time()
    st.nextAutoAt = st.startedAt + STARTUP_DELAY_S
    st.autoDone = false
    st.unavailable = nil
    st.remindLater = false
end

function plugin.onDestroy()
    httpClose(true)
    st.checking = false
    st.noticeOpen = false
    core = nil
    mq = nil
    ImGui = nil
end

function plugin.onTick()
    if not core then return end
    if st.checking then
        local status, a, b = httpPoll()
        if status == 'done' then
            finishResponse(a, b)
        elseif status == 'error' then
            finishError(a)
        end
        return
    end
    if st.autoDone or st.unavailable then return end
    if st.nextAutoAt and os.time() >= st.nextAutoAt then
        if not frequencyDue() then
            st.autoDone = true
            return
        end
        if startCheck(false) then
            -- One automatic check per session; a failure retries after RETRY_AFTER_S.
            st.autoDone = true
        end
    end
end

function plugin.onDrawUI()
    if not core then return end
    drawNotice()
end

function plugin.onSaveSettings()
    return {
        autoCheck   = cfg.autoCheck == true,
        frequency   = cfg.frequency,
        popup       = cfg.popup == true,
        skipTag     = cfg.skipTag,
        lastCheckAt = cfg.lastCheckAt,
        lastTag     = cfg.lastTag,
    }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if s.autoCheck ~= nil then cfg.autoCheck = (s.autoCheck == true) end
    if FREQUENCY_LABEL[s.frequency] then cfg.frequency = s.frequency end
    if s.popup ~= nil then cfg.popup = (s.popup == true) end
    cfg.skipTag = (type(s.skipTag) == 'string' and s.skipTag ~= '') and s.skipTag or nil
    cfg.lastCheckAt = tonumber(s.lastCheckAt)
    cfg.lastTag = (type(s.lastTag) == 'string' and s.lastTag ~= '') and s.lastTag or nil
end

local function fmtAgo(t)
    if not t then return 'never' end
    local d = os.time() - t
    if d < 60 then return 'just now' end
    if d < 3600 then return string.format('%d min ago', math.floor(d / 60)) end
    if d < 86400 then return string.format('%d h ago', math.floor(d / 3600)) end
    return os.date('%Y-%m-%d %H:%M', t)
end

function plugin.onDrawSettings()
    if not core then return end
    local colors = core.colors or {}
    local GOLD  = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    local GOOD  = colors.GOOD or { 0.40, 0.85, 0.50, 1.0 }
    local WARN  = colors.WARN or { 0.95, 0.75, 0.30, 1.0 }
    local ERR   = colors.ERR or { 0.95, 0.40, 0.40, 1.0 }
    core.accent(GOLD, 'Update Checker')
    ImGui.TextDisabled(string.format('Installed: %s   |   Source: github.com/%s/releases', tostring(core.VERSION), REPO))
    ImGui.Dummy(0, core.px(4))

    local autoVal = ImGui.Checkbox('Check for new releases automatically##updAuto', cfg.autoCheck)
    if autoVal ~= cfg.autoCheck then cfg.autoCheck = autoVal; saveSettings() end
    core.setTooltip(string.format('Runs one check %d s after Triune loads (per character), with the frequency below.', STARTUP_DELAY_S))

    local curIdx = 1
    for i, f in ipairs(FREQUENCIES) do if f == cfg.frequency then curIdx = i end end
    local labels = {}
    for i, f in ipairs(FREQUENCIES) do labels[i] = FREQUENCY_LABEL[f] end
    ImGui.SetNextItemWidth(core.px(200))
    local newIdx = ImGui.Combo('Frequency##updFreq', curIdx, labels)
    if newIdx ~= curIdx and FREQUENCIES[newIdx] then cfg.frequency = FREQUENCIES[newIdx]; saveSettings() end

    local popVal = ImGui.Checkbox('Open a popup when a newer release is found##updPopup', cfg.popup)
    if popVal ~= cfg.popup then cfg.popup = popVal; saveSettings() end
    core.setTooltip('Off: only the chat notice.')

    ImGui.Dummy(0, core.px(4))
    if st.checking then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('Checking... (%.1f s)', (nowMs() - http.t0) / 1000))
    else
        if ImGui.Button('Check Now##updNow', core.px(120), core.px(24)) then
            st.unavailable = nil
            startCheck(true)
        end
        ImGui.SameLine()
        if st.result and ImGui.Button('Show Notice##updShow', core.px(120), core.px(24)) then
            st.noticeOpen = true
        end
    end

    ImGui.Dummy(0, core.px(4))
    ImGui.TextDisabled('Last check: ' .. fmtAgo(st.lastCheckedAt or cfg.lastCheckAt))
    if st.lastDurationMs then
        ImGui.SameLine()
        ImGui.TextDisabled(string.format('(%.0f ms, %d polls)', st.lastDurationMs, http.polls))
    end
    if st.unavailable then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Update check unavailable: ' .. st.unavailable)
    elseif st.lastError then
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Last error: ' .. st.lastError)
    end
    local r = st.result
    if r then
        if r.newer then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('Newer release available: %s%s', r.tag, r.published ~= '' and ('  (' .. r.published .. ')') or ''))
        elseif r.cmp == 0 then
            ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'You are on the latest release.')
        else
            ImGui.TextDisabled(string.format('Latest published release is %s (you are ahead).', r.tag))
        end
    elseif cfg.lastTag then
        ImGui.TextDisabled('Latest release seen: ' .. cfg.lastTag)
    end
    if cfg.skipTag then
        ImGui.TextDisabled('Skipping: ' .. cfg.skipTag)
        ImGui.SameLine()
        if ImGui.SmallButton('Unskip##updUnskip') then
            cfg.skipTag = nil
            saveSettings()
        end
    end
end

-- /ac update [now|show|skip|unskip|auto on|off|link]
function plugin.onCommand(cmd, args)
    if cmd ~= 'update' and cmd ~= 'checkupdate' and cmd ~= 'updater' then return false end
    local sub = args and args[2] and tostring(args[2]):lower() or 'now'
    if sub == 'now' or sub == 'check' then
        st.unavailable = nil
        startCheck(true)
    elseif sub == 'show' then
        if st.result then st.noticeOpen = true else chat('No check result yet. /ac update to check now.') end
    elseif sub == 'skip' then
        local tag = (st.result and st.result.tag) or cfg.lastTag
        if tag then
            cfg.skipTag = tag
            st.noticeOpen = false
            saveSettings()
            chat('Skipping %s. /ac update unskip to be reminded again.', tag)
        else
            chat('No release known yet to skip.')
        end
    elseif sub == 'unskip' then
        cfg.skipTag = nil
        saveSettings()
        chat('Version skip cleared.')
    elseif sub == 'auto' then
        local v = args and args[3] and tostring(args[3]):lower() or nil
        if v == 'on' or v == 'off' then
            cfg.autoCheck = (v == 'on')
            saveSettings()
        end
        chat('Automatic update check is %s (%s).', cfg.autoCheck and 'ON' or 'OFF', FREQUENCY_LABEL[cfg.frequency] or cfg.frequency)
    elseif sub == 'link' then
        copyLink((st.result and st.result.url) or releaseUrl(cfg.lastTag))
    else
        chat('usage: /ac update [now|show|skip|unskip|auto on|off|link]')
    end
    return true
end

plugin.help = {
    '  \ag/ac update [now|show|skip|unskip|auto on|off|link]\ax - Check GitHub for a newer Triune release (non-blocking)',
}

-- Exposed for tests
plugin.parseVersion    = parseVersion
plugin.compareVersions = compareVersions
plugin.jsonComplete    = jsonComplete
plugin.jsonString      = jsonString
plugin.summarizeNotes  = summarizeNotes
plugin._cfg            = cfg
plugin._state          = st

return plugin
