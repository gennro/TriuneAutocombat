---@diagnostic disable: undefined-global, undefined-field, deprecated
-- ============================================================================
-- Triune LLM Test Runner & Autonomous QA Agent (v1.0)
-- Standalone in-game testing harness for MacroQuest and TriuneAutocombat.
--
-- Connects to local LLMs (LM Studio, Ollama) and cloud LLMs (Google Gemini,
-- OpenCode / OpenRouter) via the external asynchronous Python sidecar bridge
-- (TAC/triune_llm_bridge.py) to guarantee eqgame.exe NEVER halts or drops frames.
--
-- Run with:  /lua run triune_test
-- Stop with: /lua stop triune_test
-- ============================================================================

local mq    = require('mq')
local ImGui = require('ImGui')

local VERSION     = '1.0'
local CONFIG_NAME = 'triune_test_config.lua'
local CFG_PATH    = mq.configDir and (mq.configDir .. '/' .. CONFIG_NAME) or nil

-- Theme & style helpers (Identical copy from canonical triune_buttons.lua)
local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    local ImGuiColType = mq.imgui.Col or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiColType and ImGuiColType(id) or id
    if pcall(mq.imgui.PushStyleColor, enumVal, r, g, b, a) then _colN = _colN + 1 end ---@diagnostic disable-line: undefined-field
end
local function pushVar(id, a, b)
    if id == nil then return end
    local ok
    local ImGuiSVType = mq.imgui.StyleVar or _G.ImGuiStyleVar ---@diagnostic disable-line: undefined-field
    local enumVal = ImGuiSVType and ImGuiSVType(id) or id
    if b ~= nil then
        local ImVec2Type = _G.ImVec2
        if type(ImVec2Type) == 'function' then
            ok = pcall(mq.imgui.PushStyleVar, enumVal, ImVec2Type(a, b)) ---@diagnostic disable-line: undefined-field
        else
            ok = pcall(mq.imgui.PushStyleVar, enumVal, a, b) ---@diagnostic disable-line: undefined-field
        end
    else
        ok = pcall(mq.imgui.PushStyleVar, enumVal, a) ---@diagnostic disable-line: undefined-field
    end
    if ok then _varN = _varN + 1 end
end

local function pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = mq.imgui.Col or _G.ImGuiCol ---@diagnostic disable-line: undefined-field
    local ImGuiStyleVar = mq.imgui.StyleVar or _G.ImGuiStyleVar ---@diagnostic disable-line: undefined-field
    if ImGuiCol then
        pushCol(ImGuiCol.WindowBg, 0.059, 0.086, 0.133, 1)
        pushCol(ImGuiCol.ChildBg, 0.055, 0.082, 0.125, 1)
        pushCol(ImGuiCol.PopupBg, 0.047, 0.075, 0.118, 1)
        pushCol(ImGuiCol.Border, 0.157, 0.251, 0.345, 1)
        pushCol(ImGuiCol.Text, 0.851, 0.898, 0.953, 1)
        pushCol(ImGuiCol.TextDisabled, 0.490, 0.561, 0.651, 1)
        pushCol(ImGuiCol.TitleBg, 0.043, 0.067, 0.106, 1)
        pushCol(ImGuiCol.TitleBgActive, 0.047, 0.078, 0.125, 1)
        pushCol(ImGuiCol.FrameBg, 0.047, 0.078, 0.125, 1)
        pushCol(ImGuiCol.FrameBgHovered, 0.090, 0.150, 0.220, 1)
        pushCol(ImGuiCol.FrameBgActive, 0.120, 0.190, 0.270, 1)
        pushCol(ImGuiCol.Button, 0.086, 0.125, 0.196, 1)
        pushCol(ImGuiCol.ButtonHovered, 0.300, 0.700, 1.000, 0.35)
        pushCol(ImGuiCol.ButtonActive, 0.300, 0.700, 1.000, 0.60)
        pushCol(ImGuiCol.Header, 0.078, 0.129, 0.204, 1)
        pushCol(ImGuiCol.HeaderHovered, 0.160, 0.440, 0.700, 0.50)
        pushCol(ImGuiCol.HeaderActive, 0.160, 0.500, 0.750, 0.70)
        pushCol(ImGuiCol.Tab, 0.043, 0.067, 0.098, 1)
        pushCol(ImGuiCol.TabHovered, 0.300, 0.700, 1.000, 0.40)
        pushCol(ImGuiCol.TabSelected, 0.075, 0.125, 0.200, 1)
        pushCol(ImGuiCol.CheckMark, 0.370, 0.880, 0.640, 1)
        pushCol(ImGuiCol.SliderGrab, 1.000, 0.700, 0.540, 1)
        pushCol(ImGuiCol.SliderGrabActive, 1.000, 0.550, 0.300, 1)
        pushCol(ImGuiCol.Separator, 0.157, 0.251, 0.345, 1)
        pushCol(ImGuiCol.ScrollbarBg, 0.031, 0.051, 0.078, 1)
        pushCol(ImGuiCol.ScrollbarGrab, 0.157, 0.251, 0.345, 1)
    end
    if ImGuiStyleVar then
        local ImGuiSV = ImGuiStyleVar
        pushVar(ImGuiSV.WindowRounding, 6)
        pushVar(ImGuiSV.ChildRounding, 5)
        pushVar(ImGuiSV.FrameRounding, 4)
        pushVar(ImGuiSV.PopupRounding, 4)
        pushVar(ImGuiSV.TabRounding, 4)
        pushVar(ImGuiSV.GrabRounding, 3)
        pushVar(ImGuiSV.ScrollbarRounding, 6)

        pushVar(ImGuiSV.FrameBorderSize, 1)
        pushVar(ImGuiSV.FramePadding, 7, 4)
        pushVar(ImGuiSV.ItemSpacing, 8, 6)
        pushVar(ImGuiSV.WindowPadding, 12, 10)
    end
end

local function popTheme()
    if _varN > 0 then pcall(mq.imgui.PopStyleVar, _varN); _varN = 0 end ---@diagnostic disable-line: undefined-field
    if _colN > 0 then pcall(mq.imgui.PopStyleColor, _colN); _colN = 0 end ---@diagnostic disable-line: undefined-field
end

-- Accent colors
local GOOD  = { 0.40, 0.85, 0.50, 1.0 }
local WARN  = { 0.95, 0.75, 0.30, 1.0 }
local ERR   = { 0.95, 0.40, 0.40, 1.0 }
local ARC   = { 0.30, 0.80, 1.00, 1.0 }
local GOLD  = { 1.00, 0.84, 0.00, 1.0 }
local MUTED = { 0.55, 0.60, 0.65, 1.0 }

-- ============================================================================
-- Lightweight Pure-Lua JSON Parser & Serializer (Standalone, Zero External C/DLL)
-- ============================================================================
local JSON = {}

function JSON.encode(val)
    local t = type(val)
    if t == 'nil' then
        return 'null'
    elseif t == 'boolean' then
        return val and 'true' or 'false'
    elseif t == 'number' then
        return tostring(val)
    elseif t == 'string' then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == 'table' then
        local isArray = true
        local n = 0
        for k, _ in pairs(val) do
            n = n + 1
            if type(k) ~= 'number' or k ~= n then
                isArray = false
                break
            end
        end
        local parts = {}
        if isArray then
            for i = 1, #val do
                parts[#parts + 1] = JSON.encode(val[i])
            end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            for k, v in pairs(val) do
                parts[#parts + 1] = JSON.encode(tostring(k)) .. ':' .. JSON.encode(v)
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return '"' .. tostring(val) .. '"'
end

function JSON.decode(str)
    if not str or type(str) ~= 'string' then return nil end
    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        pos = pos + 1 -- skip open quote
        local start = pos
        local buf = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then
                buf[#buf + 1] = str:sub(start, pos - 1)
                pos = pos + 1
                return table.concat(buf):gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t')
            elseif c == '\\' then
                buf[#buf + 1] = str:sub(start, pos - 1)
                local nextC = str:sub(pos + 1, pos + 1)
                if nextC == '"' then buf[#buf + 1] = '"'
                elseif nextC == '\\' then buf[#buf + 1] = '\\'
                elseif nextC == 'n' then buf[#buf + 1] = '\n'
                elseif nextC == 'r' then buf[#buf + 1] = '\r'
                elseif nextC == 't' then buf[#buf + 1] = '\t'
                else buf[#buf + 1] = nextC end
                pos = pos + 2
                start = pos
            else
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end

    local function parseNumber()
        local start = pos
        while pos <= len do
            local c = str:sub(pos, pos)
            if (c >= '0' and c <= '9') or c == '-' or c == '+' or c == '.' or c == 'e' or c == 'E' then
                pos = pos + 1
            else
                break
            end
        end
        local numStr = str:sub(start, pos - 1)
        return tonumber(numStr)
    end

    local function parseArray()
        pos = pos + 1 -- skip '['
        local arr = {}
        skipWhitespace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while pos <= len do
            skipWhitespace()
            local v = parseValue()
            arr[#arr + 1] = v
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
            end
        end
        return arr
    end

    local function parseObject()
        pos = pos + 1 -- skip '{'
        local obj = {}
        skipWhitespace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skipWhitespace()
            if str:sub(pos, pos) ~= '"' then break end
            local key = parseString()
            skipWhitespace()
            if str:sub(pos, pos) == ':' then pos = pos + 1 end
            skipWhitespace()
            local val = parseValue()
            obj[key] = val
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
            end
        end
        return obj
    end

    parseValue = function()
        skipWhitespace()
        if pos > len then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then
            return parseString()
        elseif c == '{' then
            return parseObject()
        elseif c == '[' then
            return parseArray()
        elseif (c >= '0' and c <= '9') or c == '-' then
            return parseNumber()
        elseif str:sub(pos, pos + 3) == 'true' then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == 'false' then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == 'null' then
            pos = pos + 4
            return nil
        end
        pos = pos + 1
        return nil
    end

    return parseValue()
end

-- ============================================================================
-- Configuration & State
-- ============================================================================
local State = {
    isOpen           = true,
    isRunning        = true,
    activeTab        = 'Console',

    -- Mailbox IPC paths
    watchDir         = mq.configDir or '.',
    heartbeatFile    = '',
    reqFile          = '',
    reqReadyFile     = '',
    resFile          = '',
    resReadyFile     = '',

    -- Bridge status
    bridgeOnline     = false,
    lastHeartbeat    = 0,
    lastBridgeCheck  = 0,

    -- Test Execution Engine
    testMode         = 'Scenario', -- 'Scenario' or 'Freeform'
    selectedScenario = 1,
    freeformPrompt   = 'Verify that switching to Assist mode targets the group leader target and begins attack.',
    testStatus       = 'IDLE',    -- 'IDLE', 'WAITING_LLM', 'EXECUTING_ACTION', 'PAUSED_DELAY', 'COMPLETE', 'FAILED'
    stepCount        = 0,
    maxSteps         = 6,
    activeRequestId  = 0,
    requestStartTime = 0,
    delayUntilTime   = 0,

    -- Log console
    logs             = {},
    lastTloQuery     = 'Me.Combat',
    lastTloResult    = '',

    -- Telemetry snapshot
    snapshot         = {},
    lastSnapshotTime = 0,
}

local Config = {
    provider    = 'lmstudio', -- 'lmstudio', 'gemini', 'opencode', 'custom'
    url         = 'http://localhost:1234/v1/chat/completions',
    model       = 'local-model',
    apiKey      = '',
    temperature = 0.2,
}

local PROVIDER_DEFAULTS = {
    lmstudio = {
        name  = 'LM Studio (Local)',
        url   = 'http://localhost:1234/v1/chat/completions',
        model = 'local-model',
    },
    gemini = {
        name  = 'Google Gemini (Cloud)',
        url   = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        model = 'gemini-2.0-flash',
    },
    opencode = {
        name  = 'OpenCode / OpenRouter (Cloud)',
        url   = 'https://openrouter.ai/api/v1/chat/completions',
        model = 'anthropic/claude-3.5-sonnet',
    },
    custom = {
        name  = 'Custom Endpoint',
        url   = 'http://localhost:8000/v1/chat/completions',
        model = 'default',
    },
}

local SCENARIOS = {
    {
        title = '1. Combat Mode Switch & Persistence',
        goal  = 'Test switching Triune combat mode to Tank, then Assist, then Kite. Verify via /triune status or inspection that the mode transitions properly without errors.',
    },
    {
        title = '2. Target Acquisition & Distance',
        goal  = 'Test acquiring the nearest NPC target via slash command, inspect target distance and line-of-sight, and evaluate if target is within combat engagement range.',
    },
    {
        title = '3. Spell Gem Inspection & Mana Check',
        goal  = 'Inspect all memorized spell gems 1 through 8. Verify character has sufficient mana to cast gem 1 and evaluate mana threshold status.',
    },
    {
        title = '4. Group & XTarget Aggro Monitor',
        goal  = 'Inspect group status and Extended Target list count. Verify no hostile mobs are currently aggroing the player while sitting/standing.',
    },
}

-- Initialize file paths
local function initPaths()
    local sep = package.config:sub(1, 1)
    local dir = State.watchDir
    if dir:sub(-1) == '/' or dir:sub(-1) == '\\' then
        dir = dir:sub(1, -2)
    end
    State.watchDir      = dir
    State.heartbeatFile = dir .. sep .. 'triune_bridge_heartbeat.tmp'
    State.reqFile       = dir .. sep .. 'triune_bridge_req.json'
    State.reqReadyFile  = dir .. sep .. 'triune_bridge_req.ready'
    State.resFile       = dir .. sep .. 'triune_bridge_res.json'
    State.resReadyFile  = dir .. sep .. 'triune_bridge_res.ready'
end

-- Logging helper
local function addLog(entryType, text)
    local timeStr = os.date('%H:%M:%S')
    State.logs[#State.logs + 1] = {
        time = timeStr,
        type = entryType, -- 'INFO', 'THOUGHT', 'ACTION', 'QUERY', 'PASS', 'FAIL', 'WARN', 'ERR'
        text = text,
    }
    -- Limit log buffer size
    if #State.logs > 150 then
        table.remove(State.logs, 1)
    end
end

-- ============================================================================
-- Persistence
-- ============================================================================
local function loadConfig()
    if not CFG_PATH then return end
    local f = io.open(CFG_PATH, 'r')
    if not f then return end
    local content = f:read('*a')
    f:close()
    if not content then return end

    local loadFunc = loadstring or load
    local chunk = loadFunc(content)
    if chunk then
        local ok, data = pcall(chunk)
        if ok and type(data) == 'table' then
            if data.provider then Config.provider = data.provider end
            if data.url then Config.url = data.url end
            if data.model then Config.model = data.model end
            if data.apiKey then Config.apiKey = data.apiKey end
            if data.temperature then Config.temperature = data.temperature end
        end
    end
end

local function saveConfig()
    if not CFG_PATH then return end
    local f = io.open(CFG_PATH, 'w')
    if not f then return end
    f:write('return {\n')
    f:write(string.format('    provider    = %q,\n', Config.provider))
    f:write(string.format('    url         = %q,\n', Config.url))
    f:write(string.format('    model       = %q,\n', Config.model))
    f:write(string.format('    apiKey      = %q,\n', Config.apiKey))
    f:write(string.format('    temperature = %s,\n', tostring(Config.temperature)))
    f:write('}\n')
    f:close()
    addLog('INFO', 'Settings saved to ' .. CFG_PATH)
end

-- ============================================================================
-- Telemetry Snapshot Collector
-- ============================================================================
local function collectSnapshot()
    local snap = {}

    -- Player state
    pcall(function()
        snap.player = {
            name      = mq.TLO.Me.CleanName() or 'Unknown',
            level     = mq.TLO.Me.Level() or 0,
            class     = mq.TLO.Me.Class.ShortName() or 'UNK',
            hp        = mq.TLO.Me.CurrentHPs() or 0,
            maxHp     = mq.TLO.Me.MaxHPs() or 0,
            pctHp     = mq.TLO.Me.PctHPs() or 0,
            pctMana   = mq.TLO.Me.PctMana() or 0,
            pctEnd    = mq.TLO.Me.PctEndurance() or 0,
            combat    = mq.TLO.Me.Combat() or false,
            casting   = mq.TLO.Me.Casting() ~= nil,
            sitting   = mq.TLO.Me.Sitting() or false,
            standing  = mq.TLO.Me.Standing() or true,
        }
    end)

    -- Target state
    pcall(function()
        if mq.TLO.Target() and mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 then
            snap.target = {
                id       = mq.TLO.Target.ID(),
                name     = mq.TLO.Target.CleanName() or '',
                level    = mq.TLO.Target.Level() or 0,
                pctHp    = mq.TLO.Target.PctHPs() or 0,
                distance = math.floor((mq.TLO.Target.Distance() or 0) * 10) / 10,
                los      = mq.TLO.Target.LineOfSight() or false,
            }
        else
            snap.target = nil
        end
    end)

    -- Group & XTarget state
    pcall(function()
        snap.groupCount   = mq.TLO.Group.Members() or 0
        snap.xtargetCount = mq.TLO.Me.XTarget() or 0
    end)

    -- Spell gems
    snap.gems = {}
    for i = 1, 8 do
        pcall(function()
            local gemName = mq.TLO.Me.Gem(i).Name()
            if gemName then
                snap.gems[i] = gemName
            end
        end)
    end

    State.snapshot = snap
    State.lastSnapshotTime = os.time()
    return snap
end

-- TLO evaluator
local function evaluateTlo(path)
    if not path or path == '' then return 'nil' end
    local code = 'return tostring(mq.TLO.' .. path .. '())'
    local loadFunc = loadstring or load
    local chunk, err = loadFunc(code)
    if not chunk then
        return 'Syntax Error: ' .. tostring(err)
    end
    local ok, res = pcall(chunk)
    if ok then
        return tostring(res)
    else
        return 'Eval Error: ' .. tostring(res)
    end
end

-- ============================================================================
-- Mailbox IPC & Request Dispatcher
-- ============================================================================
local function checkHeartbeat()
    local f = io.open(State.heartbeatFile, 'r')
    if f then
        local line = f:read('*l')
        f:close()
        local t = tonumber(line)
        if t and (os.time() - t <= 3.0) then
            State.bridgeOnline = true
            State.lastHeartbeat = t
            return
        end
    end
    State.bridgeOnline = false
end

local function dispatchLLMRequest(messages)
    if not State.bridgeOnline then
        addLog('ERR', 'Cannot run test: Triune LLM Bridge is offline! Start TAC/triune_llm_bridge.py first.')
        State.testStatus = 'FAILED'
        return false
    end

    State.activeRequestId = State.activeRequestId + 1
    State.requestStartTime = os.time()

    local reqPayload = {
        id          = State.activeRequestId,
        provider    = Config.provider,
        url         = Config.url,
        model       = Config.model,
        apiKey      = Config.apiKey,
        temperature = Config.temperature,
        messages    = messages,
    }

    local jsonStr = JSON.encode(reqPayload)

    -- Write request file
    local rf = io.open(State.reqFile, 'w')
    if not rf then
        addLog('ERR', 'Failed to write request mailbox file: ' .. State.reqFile)
        State.testStatus = 'FAILED'
        return false
    end
    rf:write(jsonStr)
    rf:close()

    -- Touch ready file
    local rrf = io.open(State.reqReadyFile, 'w')
    if rrf then
        rrf:write('1')
        rrf:close()
    end

    State.testStatus = 'WAITING_LLM'
    addLog('INFO', string.format('Step %d: Prompt dispatched to %s (%s)...', State.stepCount, Config.provider, Config.model))
    return true
end

-- Build system prompt and initial user message
local function buildTestPrompt()
    local goal = (State.testMode == 'Scenario')
        and SCENARIOS[State.selectedScenario].goal
        or State.freeformPrompt

    local snap = collectSnapshot()
    local snapJson = JSON.encode(snap)

    local systemPrompt = [[
You are an autonomous in-game QA testing agent for EverQuest MacroQuest and TriuneAutocombat.
Your goal is to test in-game functionality by observing telemetry, issuing safe commands, and evaluating assertions.

You MUST respond strictly with a valid JSON object in this exact schema (no markdown, no surrounding text):
{
  "thought": "Brief explanation of your observation and what you will do next.",
  "action": "COMMAND" | "QUERY" | "DELAY" | "ASSERT" | "FINISH",
  "param": "Command string, TLO query string, delay in ms, or assertion condition",
  "assert_status": "PASS" | "FAIL",
  "explanation": "Why the assertion passed or failed, or summary of the step."
}

Available actions:
- "COMMAND": Execute an MQ slash command (e.g. "/triune mode tank", "/target a_fire_beetle", "/stand").
- "QUERY": Request the value of an MQ TLO (e.g. "Me.Combat", "Target.Distance", "Me.PctMana").
- "DELAY": Request an in-game pause in milliseconds (e.g. 1000) for a command to take effect.
- "ASSERT": Assert a condition. Set "assert_status" to "PASS" or "FAIL", and provide "explanation".
- "FINISH": Conclude the test run with final summary in "explanation".
]]

    local userPrompt = string.format(
        "TEST OBJECTIVE:\n%s\n\nCURRENT IN-GAME SNAPSHOT:\n%s\n\nBegin testing step %d.",
        goal, snapJson, State.stepCount + 1
    )

    return {
        { role = 'system', content = systemPrompt },
        { role = 'user', content = userPrompt },
    }
end

local function startTest()
    if not State.bridgeOnline then
        addLog('ERR', 'Cannot start: Python bridge is offline. Run `python TAC/triune_llm_bridge.py` in a terminal!')
        return
    end

    State.stepCount = 0
    State.logs = {}
    addLog('INFO', '=== Starting In-Game Test Run ===')
    local goal = (State.testMode == 'Scenario') and SCENARIOS[State.selectedScenario].title or 'Freeform Test'
    addLog('INFO', 'Target Scenario: ' .. goal)

    local messages = buildTestPrompt()
    dispatchLLMRequest(messages)
end

local function stopTest(reason)
    State.testStatus = 'IDLE'
    addLog('WARN', 'Test stopped: ' .. (reason or 'User requested.'))
end

-- ============================================================================
-- Main Test Action Executor
-- ============================================================================
local function executeAgentResponse(content)
    -- Try to parse JSON from content
    -- Sometimes LLMs wrap in ```json ... ```, strip that if present
    local clean = content:gsub('^%s*```json%s*', ''):gsub('^%s*```%s*', ''):gsub('%s*```%s*$', '')
    local parsed = JSON.decode(clean)

    if not parsed or type(parsed) ~= 'table' then
        addLog('ERR', 'Failed to parse JSON response from LLM: ' .. tostring(content):sub(1, 100))
        State.testStatus = 'FAILED'
        return
    end

    State.stepCount = State.stepCount + 1

    local thought = parsed.thought or 'Thinking...'
    local action  = parsed.action or 'FINISH'
    local param   = parsed.param or ''
    local status  = parsed.assert_status or 'PASS'
    local expl    = parsed.explanation or ''

    addLog('THOUGHT', thought)

    if action == 'COMMAND' then
        addLog('ACTION', 'Executing Command: ' .. tostring(param))
        mq.cmd(tostring(param))
        -- Short pause then continue
        State.delayUntilTime = os.time() + 1
        State.testStatus = 'PAUSED_DELAY'

    elseif action == 'QUERY' then
        local val = evaluateTlo(param)
        addLog('QUERY', string.format('TLO Query [%s] = %s', tostring(param), tostring(val)))
        -- Provide query result back to LLM in next step
        if State.stepCount >= State.maxSteps then
            addLog('WARN', 'Reached maximum steps (' .. State.maxSteps .. '). Test complete.')
            State.testStatus = 'COMPLETE'
        else
            local nextMessages = {
                { role = 'user', content = string.format('TLO Query result for [%s]: %s\nTelemetry updated:\n%s\nProceed to next step.', param, val, JSON.encode(collectSnapshot())) }
            }
            dispatchLLMRequest(nextMessages)
        end

    elseif action == 'DELAY' then
        local ms = tonumber(param) or 1000
        addLog('INFO', string.format('Pausing for %d ms...', ms))
        State.delayUntilTime = os.time() + math.max(1, math.floor(ms / 1000))
        State.testStatus = 'PAUSED_DELAY'

    elseif action == 'ASSERT' then
        if status == 'PASS' then
            addLog('PASS', string.format('ASSERT PASS: %s (%s)', tostring(param), expl))
        else
            addLog('FAIL', string.format('ASSERT FAIL: %s (%s)', tostring(param), expl))
        end

        if State.stepCount >= State.maxSteps then
            addLog('INFO', 'Test assertions complete.')
            State.testStatus = 'COMPLETE'
        else
            local nextMessages = {
                { role = 'user', content = 'Assertion recorded. Telemetry:\n' .. JSON.encode(collectSnapshot()) .. '\nProceed or FINISH.' }
            }
            dispatchLLMRequest(nextMessages)
        end

    elseif action == 'FINISH' then
        addLog('PASS', 'Test Completed Successfully! Summary: ' .. expl)
        State.testStatus = 'COMPLETE'
    else
        addLog('WARN', 'Unknown action: ' .. tostring(action))
        State.testStatus = 'COMPLETE'
    end
end

-- ============================================================================
-- ImGui Render UI
-- ============================================================================
local function drawHeader()
    -- Title and status indicators
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Triune LLM Test Runner')
    ImGui.SameLine()
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'v' .. VERSION)

    ImGui.SameLine()
    ImGui.Text(' | ')
    ImGui.SameLine()

    -- Bridge status badge
    if State.bridgeOnline then
        local pName = PROVIDER_DEFAULTS[Config.provider] and PROVIDER_DEFAULTS[Config.provider].name or Config.provider
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], string.format('[Bridge: Online (%s)]', pName))
    else
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], '[Bridge: Offline - run triune_llm_bridge.py]')
    end

    ImGui.Separator()
end

local function drawConsoleTab()
    ImGui.Spacing()

    -- Mode selector
    ImGui.Text('Test Mode:')
    ImGui.SameLine()
    if ImGui.RadioButton('Pre-Built Scenario', State.testMode == 'Scenario') then
        State.testMode = 'Scenario'
    end
    ImGui.SameLine()
    if ImGui.RadioButton('Freeform Prompt', State.testMode == 'Freeform') then
        State.testMode = 'Freeform'
    end

    ImGui.Spacing()

    if State.testMode == 'Scenario' then
        ImGui.Text('Select Scenario:')
        for i, sc in ipairs(SCENARIOS) do
            if ImGui.RadioButton(sc.title, State.selectedScenario == i) then
                State.selectedScenario = i
            end
        end
        ImGui.Spacing()
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Objective: ' .. SCENARIOS[State.selectedScenario].goal)
    else
        ImGui.Text('Custom Prompt / Test Objective:')
        local text, changed = ImGui.InputTextMultiline('##FreeformPrompt', State.freeformPrompt, 500, 60)
        if changed then State.freeformPrompt = text end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Controls row
    local isBusy = (State.testStatus == 'WAITING_LLM' or State.testStatus == 'EXECUTING_ACTION' or State.testStatus == 'PAUSED_DELAY')

    if not isBusy then
        if ImGui.Button('▶ Run Test##StartBtn', 120, 26) then
            startTest()
        end
    else
        if ImGui.Button('■ Stop Test##StopBtn', 120, 26) then
            stopTest('User stopped.')
        end
    end

    ImGui.SameLine()
    if ImGui.Button('Clear Log##ClearBtn', 90, 26) then
        State.logs = {}
    end

    ImGui.SameLine()
    ImGui.Text('Max Steps:')
    ImGui.SameLine()
    local val, stepChanged = ImGui.SliderInt('##MaxSteps', State.maxSteps, 1, 15)
    if stepChanged then State.maxSteps = val end

    ImGui.SameLine()
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Status: ' .. State.testStatus)

    ImGui.Spacing()

    -- Live Log Output Window
    ImGui.Text('Execution Log:')
    if ImGui.BeginChild('LogConsoleChild', 0, 240, true) then
        for _, log in ipairs(State.logs) do
            local col = MUTED
            if log.type == 'ACTION' then col = WARN
            elseif log.type == 'THOUGHT' then col = ARC
            elseif log.type == 'PASS' then col = GOOD
            elseif log.type == 'FAIL' or log.type == 'ERR' then col = ERR
            elseif log.type == 'QUERY' then col = GOLD
            end

            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '[' .. log.time .. ']')
            ImGui.SameLine()
            ImGui.TextColored(col[1], col[2], col[3], col[4], string.format('[%s] %s', log.type, log.text))
        end
        -- Auto scroll to bottom
        if ImGui.GetScrollY() >= ImGui.GetScrollMaxY() - 20 then
            ImGui.SetScrollHereY(1.0)
        end
    end
    ImGui.EndChild()
end

local function drawTelemetryTab()
    ImGui.Spacing()

    if ImGui.Button('Refresh Telemetry##RefreshSnap', 140, 24) then
        collectSnapshot()
    end

    ImGui.Spacing()
    local snap = State.snapshot

    if snap.player then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'Player: ' .. snap.player.name .. ' (' .. snap.player.class .. ' ' .. snap.player.level .. ')')
        ImGui.Text(string.format('HP: %d%%  |  Mana: %d%%  |  End: %d%%  |  InCombat: %s',
            snap.player.pctHp, snap.player.pctMana, snap.player.pctEnd, tostring(snap.player.combat)))
    end

    ImGui.Spacing()
    if snap.target then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'Target: ' .. snap.target.name .. ' (Lvl ' .. snap.target.level .. ')')
        ImGui.Text(string.format('Target HP: %d%%  |  Dist: %.1f  |  LineOfSight: %s',
            snap.target.pctHp, snap.target.distance, tostring(snap.target.los)))
    else
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Target: <No Target>')
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Manual TLO Query Tool
    ImGui.Text('Evaluate TLO Query:')
    local query, qChanged = ImGui.InputText('##TloInput', State.lastTloQuery, 256)
    if qChanged then State.lastTloQuery = query end

    ImGui.SameLine()
    if ImGui.Button('Evaluate##EvalBtn', 80, 20) then
        State.lastTloResult = evaluateTlo(State.lastTloQuery)
    end

    if State.lastTloResult ~= '' then
        ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Result: ' .. State.lastTloResult)
    end
end

local function drawSettingsTab()
    ImGui.Spacing()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'LLM Provider Configuration')
    ImGui.Spacing()

    -- Provider selection
    ImGui.Text('Provider Preset:')
    for key, p in pairs(PROVIDER_DEFAULTS) do
        if ImGui.RadioButton(p.name .. '##prov_' .. key, Config.provider == key) then
            Config.provider = key
            Config.url      = p.url
            Config.model    = p.model
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Base URL
    ImGui.Text('Endpoint URL:')
    local url, urlChanged = ImGui.InputText('##EndpointUrl', Config.url, 512)
    if urlChanged then Config.url = url end

    -- Model Name
    ImGui.Text('Model Name:')
    local mod, modChanged = ImGui.InputText('##ModelName', Config.model, 256)
    if modChanged then Config.model = mod end

    -- API Key
    ImGui.Text('API Key (Masked):')
    local key, keyChanged = ImGui.InputText('##ApiKey', Config.apiKey, 256, mq.imgui.InputTextFlags.Password)
    if keyChanged then Config.apiKey = key end

    -- Temperature
    ImGui.Text('Temperature:')
    local temp, tempChanged = ImGui.SliderFloat('##TempSlider', Config.temperature, 0.0, 1.0)
    if tempChanged then Config.temperature = temp end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    if ImGui.Button('Save Configuration##SaveCfgBtn', 150, 26) then
        saveConfig()
    end
end

local function drawMainWindow()
    if not State.isOpen then return end

    pushTheme()
    local open, show = ImGui.Begin('Triune LLM Test Harness###TriuneTestMain', State.isOpen)
    if not open then
        State.isOpen = false
        State.isRunning = false
        ImGui.End()
        popTheme()
        return
    end

    if show then
        drawHeader()

        if ImGui.BeginTabBar('TriuneTestTabs') then
            if ImGui.BeginTabItem('Test Console##TabConsole') then
                drawConsoleTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem('Telemetry Snapshot##TabTelemetry') then
                drawTelemetryTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem('LLM Settings##TabSettings') then
                drawSettingsTab()
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end

    ImGui.End()
    popTheme()
end

-- ============================================================================
-- Main Execution Coroutine Loop (Yieldable)
-- ============================================================================
local function init()
    initPaths()
    loadConfig()
    collectSnapshot()
    mq.imgui.init('TriuneTest', drawMainWindow)
    addLog('INFO', 'Triune LLM Test Runner initialized. Press Run Test to begin.')
end

init()

while State.isRunning do
    local now = os.time()

    -- Check bridge heartbeat every 1 second
    if now - State.lastBridgeCheck >= 1 then
        checkHeartbeat()
        State.lastBridgeCheck = now
    end

    -- Process pending test states
    if State.testStatus == 'WAITING_LLM' then
        -- Non-blocking check for bridge response
        local rf = io.open(State.resReadyFile, 'r')
        if rf then
            rf:close()
            pcall(os.remove, State.resReadyFile)

            -- Read response file
            local f = io.open(State.resFile, 'r')
            if f then
                local resContent = f:read('*a')
                f:close()
                pcall(os.remove, State.resFile)

                local resJson = JSON.decode(resContent)
                if resJson and resJson.ok then
                    State.testStatus = 'EXECUTING_ACTION'
                    executeAgentResponse(resJson.content or '')
                else
                    local errMsg = (resJson and resJson.error) or 'Unknown bridge error'
                    addLog('ERR', 'LLM Request failed: ' .. errMsg)
                    State.testStatus = 'FAILED'
                end
            end
        else
            -- Check for timeout (e.g. 60 seconds)
            if now - State.requestStartTime > 60 then
                addLog('ERR', 'LLM request timed out after 60 seconds.')
                State.testStatus = 'FAILED'
            end
        end

    elseif State.testStatus == 'PAUSED_DELAY' then
        if now >= State.delayUntilTime then
            if State.stepCount >= State.maxSteps then
                addLog('INFO', 'Test completed max steps limit.')
                State.testStatus = 'COMPLETE'
            else
                -- Advance to next step
                local nextMessages = {
                    { role = 'user', content = 'Delay complete. Current telemetry:\n' .. JSON.encode(collectSnapshot()) .. '\nProceed with test.' }
                }
                dispatchLLMRequest(nextMessages)
            end
        end
    end

    mq.delay(50)
end
