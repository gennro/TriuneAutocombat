---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune AutoCombat — Standalone ImGui Release Updater (v1.6.1)
-- Checks GitHub Releases for updates, displays release notes, and updates
-- script files on Windows and Linux directly within MacroQuest.
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')

local VERSION = '1.6.1'
local GITHUB_REPO = 'gennro/TriuneAutocombat'
local API_URL = 'https://api.github.com/repos/' .. GITHUB_REPO .. '/releases/latest'
local latestTag = nil  -- raw git tag from API (e.g. 'V1.3')

local isOpen = true
local isRunning = true
local checkStatus = 'idle' -- 'idle', 'checking', 'available', 'up_to_date', 'error'
local installedVersion = VERSION
local latestVersion = 'Unknown'
local releaseNotes = ''
local statusMessage = 'Click "Check for Updates" to connect to GitHub.'
local pendingAction = nil

-- Theme helper
local _colN, _varN = 0, 0
local function pushCol(id, r, g, b, a)
    if id == nil then return end
    local ImGuiColType = mq.imgui.Col or _G.ImGuiCol
    local enumVal = ImGuiColType and ImGuiColType(id) or id
    if pcall(mq.imgui.PushStyleColor, enumVal, r, g, b, a) then _colN = _colN + 1 end
end

local function pushVar(id, a, b)
    if id == nil then return end
    local ok
    local ImGuiSVType = mq.imgui.StyleVar or _G.ImGuiStyleVar
    local enumVal = ImGuiSVType and ImGuiSVType(id) or id
    if b ~= nil then
        local ImVec2Type = _G.ImVec2
        if type(ImVec2Type) == 'function' then
            ok = pcall(mq.imgui.PushStyleVar, enumVal, ImVec2Type(a, b))
        else
            ok = pcall(mq.imgui.PushStyleVar, enumVal, a, b)
        end
    else
        ok = pcall(mq.imgui.PushStyleVar, enumVal, a)
    end
    if ok then _varN = _varN + 1 end
end

local function pushTheme()
    _colN, _varN = 0, 0
    local ImGuiCol = mq.imgui.Col or _G.ImGuiCol
    local ImGuiStyleVar = mq.imgui.StyleVar or _G.ImGuiStyleVar
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
        pushCol(ImGuiCol.Separator, 0.157, 0.251, 0.345, 1)
    end
    if ImGuiStyleVar then
        pushVar(ImGuiStyleVar.WindowRounding, 6.0)
        pushVar(ImGuiStyleVar.FrameRounding, 4.0)
        pushVar(ImGuiStyleVar.ChildRounding, 4.0)
        pushVar(ImGuiStyleVar.PopupRounding, 4.0)
        pushVar(ImGuiStyleVar.WindowPadding, 10.0, 10.0)
        pushVar(ImGuiStyleVar.FramePadding, 6.0, 3.0)
        pushVar(ImGuiStyleVar.ItemSpacing, 8.0, 5.0)
    end
end

local function popTheme()
    if _colN > 0 then pcall(mq.imgui.PopStyleColor, _colN) end
    if _varN > 0 then pcall(mq.imgui.PopStyleVar, _varN) end
    _colN, _varN = 0, 0
end

local function cleanTag(tag)
    if not tag then return '' end
    if tag:sub(1,1):lower() == 'v' then
        return tag:sub(2)
    end
    return tag
end

local diagLogs = {}
local function diag(msg)
    local entry = string.format('[%s] %s', os.date('%H:%M:%S'), tostring(msg))
    table.insert(diagLogs, entry)
    print('\ay[TriuneUpdater]\ax ' .. tostring(msg))
end

-- Helper to execute an OS command safely and capture its stdout output
local function execCommand(cmd, outputFile)
    diag('execCommand starting: ' .. cmd)
    if outputFile then pcall(os.remove, outputFile) end

    -- Primary: Use io.popen for non-blocking stream execution (prevents cmd window popups & thread hangs)
    local okPipe, pipe = pcall(io.popen, cmd .. ' 2>&1')
    if okPipe and pipe then
        local output = pipe:read('*a')
        pipe:close()
        diag('io.popen read finished. Length: ' .. tostring(output and #output or 0) .. ' bytes')
        if output and #output > 0 then
            if outputFile then
                local f = io.open(outputFile, 'w')
                if f then
                    f:write(output)
                    f:close()
                end
            end
            return output
        end
    end

    -- Fallback: os.execute with redirection if io.popen returned empty or failed
    if outputFile then
        diag('io.popen empty; trying os.execute fallback with redirection...')
        local fullCmd = cmd .. ' > "' .. outputFile .. '" 2>&1'
        pcall(os.execute, fullCmd)
        local f = io.open(outputFile, 'r')
        if f then
            local output = f:read('*a')
            f:close()
            pcall(os.remove, outputFile)
            return output
        end
    end

    return nil
end

-- Generate a VBScript that downloads a URL to a file using MSXML2 COM objects.
-- Works on native Windows AND Wine — no external binaries needed.
local function runVBScriptDownload(url, destFile, scriptFile)
    pcall(os.remove, scriptFile)
    pcall(os.remove, destFile)

    -- Use forward slashes in VBS paths to avoid backslash escaping issues
    local vbsDest = destFile:gsub('\\', '/')

    local vbsCode = 'On Error Resume Next\r\n'
        .. 'Dim http\r\n'
        .. 'Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")\r\n'
        .. 'If Err.Number <> 0 Then\r\n'
        .. '    Err.Clear\r\n'
        .. '    Set http = CreateObject("MSXML2.ServerXMLHTTP")\r\n'
        .. 'End If\r\n'
        .. 'If Err.Number <> 0 Then\r\n'
        .. '    Err.Clear\r\n'
        .. '    Set http = CreateObject("MSXML2.XMLHTTP")\r\n'
        .. 'End If\r\n'
        .. 'If Err.Number <> 0 Then\r\n'
        .. '    Dim fso0\r\n'
        .. '    Set fso0 = CreateObject("Scripting.FileSystemObject")\r\n'
        .. '    Dim ef\r\n'
        .. '    Set ef = fso0.CreateTextFile("' .. vbsDest .. '", True)\r\n'
        .. '    ef.Write "VBS_ERR: No MSXML2 COM object available: " & Err.Description\r\n'
        .. '    ef.Close\r\n'
        .. '    WScript.Quit 1\r\n'
        .. 'End If\r\n'
        .. 'http.Open "GET", "' .. url .. '", False\r\n'
        .. 'http.setRequestHeader "User-Agent", "TriuneUpdater"\r\n'
        .. 'http.setRequestHeader "Cache-Control", "no-cache"\r\n'
        .. 'http.setRequestHeader "Pragma", "no-cache"\r\n'
        .. 'http.Send\r\n'
        .. 'If Err.Number = 0 Then\r\n'
        .. '    Dim fso\r\n'
        .. '    Set fso = CreateObject("Scripting.FileSystemObject")\r\n'
        .. '    Dim f\r\n'
        .. '    Set f = fso.CreateTextFile("' .. vbsDest .. '", True)\r\n'
        .. '    f.Write http.responseText\r\n'
        .. '    f.Close\r\n'
        .. 'Else\r\n'
        .. '    Dim fso2\r\n'
        .. '    Set fso2 = CreateObject("Scripting.FileSystemObject")\r\n'
        .. '    Dim f2\r\n'
        .. '    Set f2 = fso2.CreateTextFile("' .. vbsDest .. '", True)\r\n'
        .. '    f2.Write "VBS_ERR: " & Err.Description\r\n'
        .. '    f2.Close\r\n'
        .. 'End If\r\n'

    local pf = io.open(scriptFile, 'w')
    if not pf then
        diag('Failed to create VBS script file: ' .. scriptFile)
        return nil
    end
    pf:write(vbsCode)
    pf:close()

    diag('Running VBScript: cscript.exe //Nologo "' .. scriptFile .. '"')
    local res = os.execute('cscript.exe //Nologo "' .. scriptFile .. '"')
    diag('VBScript os.execute result: ' .. tostring(res))
    pcall(os.remove, scriptFile)

    local tf = io.open(destFile, 'r')
    if tf then
        local content = tf:read('*a')
        tf:close()
        pcall(os.remove, destFile)
        return content
    end
    return nil
end

-- Perform GitHub API release query
local function checkForUpdates()
    checkStatus = 'checking'
    statusMessage = 'Connecting to GitHub API...'
    diagLogs = {}
    diag('--- Starting Update Check ---')

    local rootDir = mq.rootDir or '.'
    local configDir = mq.configDir or (rootDir .. '/config')
    local sep = package.config:sub(1,1)
    local tmpFile = configDir .. sep .. 'triune_check.tmp'

    diag('rootDir: ' .. tostring(rootDir))
    diag('configDir: ' .. tostring(configDir))
    diag('sep: ' .. tostring(sep))
    diag('tmpFile: ' .. tostring(tmpFile))

    -- Determine python updater script location dynamically
    local pyScript = rootDir .. sep .. 'triune_updater.py'
    local f = io.open(rootDir .. sep .. 'mq2triune' .. sep .. 'triune_updater.py', 'r')
    if f then
        f:close()
        pyScript = rootDir .. sep .. 'mq2triune' .. sep .. 'triune_updater.py'
    end
    diag('pyScript path: ' .. tostring(pyScript))

    local candidates = {}

    -- Candidate 1: curl CLI (built-in on Win 10/11 & Linux, zero WSH/VBScript dependency)
    table.insert(candidates, {
        name = 'curl CLI',
        run = function()
            return execCommand('curl -sL -H "User-Agent: TriuneUpdater" "' .. API_URL .. '"', tmpFile)
        end
    })

    -- Candidate 2: wget CLI (works on Linux & custom Windows installs)
    table.insert(candidates, {
        name = 'wget CLI',
        run = function()
            return execCommand('wget -qO- --header="User-Agent: TriuneUpdater" "' .. API_URL .. '"', tmpFile)
        end
    })

    -- Candidate 3: Python updater script
    table.insert(candidates, {
        name = 'Python Updater Script',
        run = function()
            local pyCmd = (sep == '\\') and ('python "' .. pyScript .. '" --check') or ('python3 "' .. pyScript .. '" --check')
            return execCommand(pyCmd, tmpFile)
        end
    })

    -- Candidate 4: PowerShell .ps1 script (native Windows)
    if sep == '\\' then
        table.insert(candidates, {
            name = 'PowerShell Script (.ps1)',
            run = function()
                local ps1File = configDir .. sep .. 'triune_check.ps1'
                pcall(os.remove, ps1File)
                pcall(os.remove, tmpFile)

                local normTmp = tmpFile:gsub('\\', '/')
                local ps1Code = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12\r\n"
                    .. "try {\r\n"
                    .. "    $wc = New-Object System.Net.WebClient\r\n"
                    .. "    $wc.Headers.Add('User-Agent', 'TriuneUpdater')\r\n"
                    .. "    $wc.DownloadFile('" .. API_URL .. "', '" .. normTmp .. "')\r\n"
                    .. "} catch {\r\n"
                    .. "    [System.IO.File]::WriteAllText('" .. normTmp .. "', 'PS_ERR: ' + $_.Exception.Message)\r\n"
                    .. "}\r\n"

                local pf = io.open(ps1File, 'w')
                if pf then
                    pf:write(ps1Code)
                    pf:close()
                    diag('Running generated .ps1 script...')
                    local res = os.execute('powershell -NoProfile -ExecutionPolicy Bypass -File "' .. ps1File .. '"')
                    diag('PS script os.execute result: ' .. tostring(res))
                    pcall(os.remove, ps1File)

                    local tf = io.open(tmpFile, 'r')
                    if tf then
                        local content = tf:read('*a')
                        tf:close()
                        pcall(os.remove, tmpFile)
                        return content
                    end
                end
                return nil
            end
        })
    end

    -- Candidate 5: VBScript MSXML2 HTTP (fallback for older Windows systems if enabled)
    if sep == '\\' then
        table.insert(candidates, {
            name = 'VBScript MSXML2',
            run = function()
                local vbsFile = configDir .. sep .. 'triune_check.vbs'
                local checkUrl = API_URL .. '?t=' .. os.time()
                return runVBScriptDownload(checkUrl, tmpFile, vbsFile)
            end
        })
    end

    local output = nil

    for _, c in ipairs(candidates) do
        diag('Trying candidate: ' .. c.name)
        local ok, out = pcall(c.run)
        if ok and out and #out > 0 then
            diag('Candidate output preview: ' .. out:sub(1, 120):gsub('\r', ''):gsub('\n', ' '))
            if out:find('tag_name') or out:find('Latest GitHub Release:') then
                output = out
                diag('SUCCESS via ' .. c.name .. ' (' .. #output .. ' bytes)')
                break
            else
                diag('Candidate ' .. c.name .. ' returned data but no tag_name found.')
            end
        else
            if not ok then
                diag('Candidate ' .. c.name .. ' threw error: ' .. tostring(out))
            else
                diag('Candidate ' .. c.name .. ' returned no output.')
            end
        end
    end

    if not output or #output == 0 then
        checkStatus = 'error'
        statusMessage = 'Received empty response from GitHub API.'
        diag('ALL METHODS FAILED to retrieve API response.')
        return
    end

    diag('Raw API Output Snippet (first 150 chars): ' .. output:sub(1, 150):gsub('\r', ''):gsub('\n', ' '))

    -- Extract tag_name (JSON pattern or Python CLI output pattern)
    local tag = output:match('"tag_name"%s*:%s*"([^"]+)"') or output:match('Latest GitHub Release:%s*([^\r\n%s%(]+)')
    local body = output:match('"body"%s*:%s*"([^"]+)"') or output:match('Release Notes:\r?\n(.*)')

    if tag then
        latestTag = tag  -- store raw tag for download URLs
        latestVersion = cleanTag(tag)
        diag('Parsed tag_name: ' .. tostring(tag) .. ' -> cleanVersion: ' .. tostring(latestVersion))
        if body then
            releaseNotes = body:gsub('\\r\\n', '\n'):gsub('\\n', '\n'):gsub('\\"', '"')
        else
            releaseNotes = 'No detailed release notes provided.'
        end

        if latestVersion ~= installedVersion then
            checkStatus = 'available'
            statusMessage = 'New version available: v' .. latestVersion .. '!'
        else
            checkStatus = 'up_to_date'
            statusMessage = 'You are running the latest version (v' .. installedVersion .. ').'
        end
    else
        checkStatus = 'error'
        statusMessage = 'Failed to parse release information from GitHub response.'
        diag('Failed to parse tag_name from output.')
    end
end

-- Dynamically resolve the absolute directory containing triune_updater.lua
local function getScriptDir()
    local src = debug.getinfo(1, "S").source:sub(2)
    src = src:gsub('\\', '/')
    local dir = src:match('(.+)/[^/]+$') or '.'
    return dir
end

-- Perform update action on main thread
local function executeUpdate()
    statusMessage = 'Applying release update...'
    diag('--- Starting Update Execution ---')
    local rootDir = mq.rootDir or '.'
    local configDir = mq.configDir or (rootDir .. '/config')
    local sep = package.config:sub(1,1)
    local logFile = configDir .. sep .. 'triune_update.log'

    -- Dynamically resolve target file destinations based on current script location
    local luaDir = getScriptDir()
    local parentDir = luaDir:match('(.+)/[^/]+$') or '.'
    local configDirTarget = (mq.configDir or (parentDir .. '/config')):gsub('\\', '/')

    diag('Dynamic luaDir: ' .. tostring(luaDir))
    diag('Dynamic parentDir: ' .. tostring(parentDir))
    diag('Dynamic configDirTarget: ' .. tostring(configDirTarget))

    local UPDATE_MAP = {
        { repo = 'mq2triune/lua/triune.lua',           target = luaDir .. '/triune.lua' },
        { repo = 'mq2triune/lua/triune_spellbook.lua', target = luaDir .. '/triune_spellbook.lua' },
        { repo = 'mq2triune/lua/triune_cursor.lua',    target = luaDir .. '/triune_cursor.lua' },
        { repo = 'mq2triune/lua/triune_updater.lua',   target = luaDir .. '/triune_updater.lua' },
        { repo = 'mq2triune/lua/triune_buffbot.lua',   target = luaDir .. '/triune_buffbot.lua' },
        { repo = 'mq2triune/lua/triune_dps.lua',       target = luaDir .. '/triune_dps.lua' },
        { repo = 'mq2triune/config/triune_data.lua',   target = configDirTarget .. '/triune_data.lua' },
        { repo = 'mq2triune/triune_updater.py',        target = parentDir .. '/triune_updater.py' },
        { repo = 'mq2triune/update.bat',               target = parentDir .. '/update.bat' },
        { repo = 'mq2triune/update.sh',                target = parentDir .. '/update.sh' },
        { repo = 'README.md',                          target = parentDir .. '/README.md' },
        { repo = 'CHANGELOG.md',                       target = parentDir .. '/CHANGELOG.md' },
    }

    -- Determine script paths for fallback candidates
    local pyScript = parentDir .. sep .. 'triune_updater.py'
    local batScript = parentDir .. sep .. 'update.bat'
    local shScript = parentDir .. sep .. 'update.sh'

    local updateSuccess = false

    -- Candidate 0: Direct curl CLI individual file download (works cross-platform: Linux, macOS, Win 10/11)
    if not updateSuccess and latestTag then
        diag('Trying curl CLI individual file download...')
        local rawBase = 'https://raw.githubusercontent.com/' .. GITHUB_REPO .. '/' .. latestTag
        local curlOkCount = 0

        for _, item in ipairs(UPDATE_MAP) do
            local url = rawBase .. '/' .. item.repo .. '?t=' .. os.time()
            local destFile = item.target
            local destDir = destFile:match('(.+)/[^/]+$') or '.'

            if sep == '\\' then
                pcall(os.execute, 'mkdir "' .. destDir:gsub('/', '\\') .. '" 2>nul')
            else
                pcall(os.execute, 'mkdir -p "' .. destDir .. '" 2>/dev/null')
            end

            local tmpDlFile = configDir .. sep .. 'triune_dl.tmp'
            local cmd = 'curl -sL -H "User-Agent: TriuneUpdater" "' .. url .. '"'
            local content = execCommand(cmd, tmpDlFile)

            local isValidContent = content and #content > 0 and not content:find('404: Not Found') and not content:find('404 Page Not Found')
            if not isValidContent and item.repo:sub(1,10) == 'mq2triune/' then
                -- Fallback for legacy tags without mq2triune/ path prefix
                local fallbackUrl = rawBase .. '/' .. item.repo:sub(11) .. '?t=' .. os.time()
                local cmd2 = 'curl -sL -H "User-Agent: TriuneUpdater" "' .. fallbackUrl .. '"'
                content = execCommand(cmd2, tmpDlFile)
                isValidContent = content and #content > 0 and not content:find('404: Not Found') and not content:find('404 Page Not Found')
            end

            if isValidContent then
                local f = io.open(destFile, 'w')
                if f then
                    f:write(content)
                    f:close()
                    curlOkCount = curlOkCount + 1
                    diag('curl updated: ' .. item.repo .. ' -> ' .. destFile)
                end
            end
        end

        if curlOkCount > 0 then
            updateSuccess = true
            diag('curl individual file update succeeded with ' .. tostring(curlOkCount) .. ' files updated.')
        else
            diag('curl individual file update produced 0 updated files.')
        end
    end

    -- Candidate 1: VBScript individual file download (works on native Windows + Wine)
    -- Downloads each file from GitHub raw content as text — no ZIP or binary handling.
    if sep == '\\' and latestTag then
        diag('Trying VBScript individual file download...')
        local rawBase = 'https://raw.githubusercontent.com/' .. GITHUB_REPO .. '/' .. latestTag
        local vbsFile = configDir .. sep .. 'triune_update.vbs'
        local resultFile = configDir .. sep .. 'triune_update_result.txt'
        local vbsResult = resultFile:gsub('\\', '/')

        -- Build VBScript that downloads each file individually using MSXML2 (text)
        local vbsCode = 'On Error Resume Next\r\n'
            .. 'Dim fso\r\n'
            .. 'Set fso = CreateObject("Scripting.FileSystemObject")\r\n'
            .. 'Dim http\r\n'
            .. 'Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")\r\n'
            .. 'If Err.Number <> 0 Then\r\n'
            .. '    Err.Clear\r\n'
            .. '    Set http = CreateObject("MSXML2.ServerXMLHTTP")\r\n'
            .. 'End If\r\n'
            .. 'If Err.Number <> 0 Then\r\n'
            .. '    Err.Clear\r\n'
            .. '    Set http = CreateObject("MSXML2.XMLHTTP")\r\n'
            .. 'End If\r\n'
            .. 'If Err.Number <> 0 Then\r\n'
            .. '    WriteResult "VBS_ERR: No MSXML2 object"\r\n'
            .. '    WScript.Quit 1\r\n'
            .. 'End If\r\n'
            .. '\r\n'
            .. 'Dim fileCount\r\n'
            .. 'fileCount = 0\r\n'
            .. '\r\n'

        for _, item in ipairs(UPDATE_MAP) do
            local winTarget = item.target:gsub('/', '\\')
            vbsCode = vbsCode
                .. 'DownloadFileWithFallback "' .. rawBase .. '", "' .. item.repo .. '", "' .. winTarget .. '"\r\n'
        end

        vbsCode = vbsCode
            .. '\r\n'
            .. 'WriteResult "Update completed successfully. Files updated: " & fileCount\r\n'
            .. 'WScript.Quit 0\r\n'
            .. '\r\n'
            .. 'Sub EnsureDir(path)\r\n'
            .. '    On Error Resume Next\r\n'
            .. '    If Not fso.FolderExists(path) Then\r\n'
            .. '        Dim parts, buildPath, i\r\n'
            .. '        parts = Split(path, "\\")\r\n'
            .. '        buildPath = ""\r\n'
            .. '        For i = 0 To UBound(parts)\r\n'
            .. '            If buildPath = "" Then\r\n'
            .. '                buildPath = parts(i)\r\n'
            .. '            Else\r\n'
            .. '                buildPath = buildPath & "\\" & parts(i)\r\n'
            .. '            End If\r\n'
            .. '            If Len(buildPath) > 0 And Not fso.FolderExists(buildPath) Then\r\n'
            .. '                fso.CreateFolder buildPath\r\n'
            .. '            End If\r\n'
            .. '        Next\r\n'
            .. '    End If\r\n'
            .. 'End Sub\r\n'
            .. '\r\n'
            .. 'Sub SaveTextFile(diskPath, content)\r\n'
            .. '    On Error Resume Next\r\n'
            .. '    Dim winPath\r\n'
            .. '    winPath = Replace(diskPath, "/", "\\")\r\n'
            .. '    EnsureDir GetParentDir(winPath)\r\n'
            .. '    Dim f\r\n'
            .. '    Set f = fso.CreateTextFile(winPath, True)\r\n'
            .. '    f.Write content\r\n'
            .. '    f.Close\r\n'
            .. 'End Sub\r\n'
            .. '\r\n'
            .. 'Sub DownloadFileWithFallback(rawBase, repoPath, destFile)\r\n'
            .. '    On Error Resume Next\r\n'
            .. '    Dim url, gotData, textData, tParam\r\n'
            .. '    tParam = "?t=" & Fix(Timer())\r\n'
            .. '    gotData = False\r\n'
            .. '\r\n'
            .. '    \' Primary URL attempt\r\n'
            .. '    url = rawBase & "/" & repoPath & tParam\r\n'
            .. '    http.Open "GET", url, False\r\n'
            .. '    http.setRequestHeader "User-Agent", "TriuneUpdater"\r\n'
            .. '    http.setRequestHeader "Cache-Control", "no-cache"\r\n'
            .. '    http.setRequestHeader "Pragma", "no-cache"\r\n'
            .. '    http.Send\r\n'
            .. '\r\n'
            .. '    If Err.Number = 0 And http.Status = 200 Then\r\n'
            .. '        gotData = True\r\n'
            .. '        textData = http.responseText\r\n'
            .. '    ElseIf Left(repoPath, 10) = "mq2triune/" Then\r\n'
            .. '        \' Fallback for legacy release tags without mq2triune/ prefix\r\n'
            .. '        Err.Clear\r\n'
            .. '        url = rawBase & "/" & Mid(repoPath, 11) & tParam\r\n'
            .. '        http.Open "GET", url, False\r\n'
            .. '        http.setRequestHeader "User-Agent", "TriuneUpdater"\r\n'
            .. '        http.setRequestHeader "Cache-Control", "no-cache"\r\n'
            .. '        http.setRequestHeader "Pragma", "no-cache"\r\n'
            .. '        http.Send\r\n'
            .. '        If Err.Number = 0 And http.Status = 200 Then\r\n'
            .. '            gotData = True\r\n'
            .. '            textData = http.responseText\r\n'
            .. '        End If\r\n'
            .. '    End If\r\n'
            .. '\r\n'
            .. '    If gotData Then\r\n'
            .. '        SaveTextFile destFile, textData\r\n'
            .. '        fileCount = fileCount + 1\r\n'
            .. '    End If\r\n'
            .. '    Err.Clear\r\n'
            .. 'End Sub\r\n'
            .. '\r\n'
            .. 'Function GetParentDir(path)\r\n'
            .. '    Dim lastSlash\r\n'
            .. '    lastSlash = InStrRev(path, "\\")\r\n'
            .. '    If lastSlash > 0 Then\r\n'
            .. '        GetParentDir = Left(path, lastSlash - 1)\r\n'
            .. '    Else\r\n'
            .. '        GetParentDir = path\r\n'
            .. '    End If\r\n'
            .. 'End Function\r\n'
            .. '\r\n'
            .. 'Sub WriteResult(msg)\r\n'
            .. '    Dim rf\r\n'
            .. '    Set rf = fso.CreateTextFile(Replace("' .. vbsResult .. '", "/", "\\"), True)\r\n'
            .. '    rf.Write msg\r\n'
            .. '    rf.Close\r\n'
            .. 'End Sub\r\n'

        pcall(os.remove, vbsFile)
        pcall(os.remove, resultFile)

        local pf = io.open(vbsFile, 'w')
        if pf then
            pf:write(vbsCode)
            pf:close()

            diag('Running VBScript update: cscript.exe //Nologo "' .. vbsFile .. '"')
            local res = os.execute('cscript.exe //Nologo "' .. vbsFile .. '"')
            diag('VBScript update os.execute result: ' .. tostring(res))
            pcall(os.remove, vbsFile)

            local rf = io.open(resultFile, 'r')
            if rf then
                local result = rf:read('*a')
                rf:close()
                pcall(os.remove, resultFile)
                diag('VBScript update result: ' .. tostring(result))

                local updatedCount = result and result:match('Files updated:%s*(%d+)')
                if result and result:find('completed successfully') and tonumber(updatedCount or 0) > 0 then
                    updateSuccess = true
                    diag('VBScript update succeeded with ' .. tostring(updatedCount) .. ' files updated.')
                else
                    diag('VBScript update failed or 0 files updated. Result: ' .. tostring(result))
                end
            end
        end
    end

    -- Candidate 2+: Python / shell script fallbacks
    if not updateSuccess then
        local execCandidates = {
            'python3 "' .. pyScript .. '" --force --dir "' .. rootDir .. '"',
            'python "' .. pyScript .. '" --force --dir "' .. rootDir .. '"',
            '"' .. shScript .. '" --force',
            '"' .. batScript .. '" --force',
        }

        for _, cmd in ipairs(execCandidates) do
            diag('Executing update command candidate: ' .. cmd)
            local out = execCommand(cmd, logFile)
            if out and (out:find('completed successfully') or out:find('updated to version')) then
                updateSuccess = true
                break
            end
        end
    end

    if updateSuccess then
        checkStatus = 'up_to_date'
        installedVersion = latestVersion
        statusMessage = 'Update applied successfully! All active Triune scripts reloaded.'
        print('\ag[TriuneUpdater]\ax \agUpdate applied successfully!\ax Reloading active Triune scripts from disk...')

        local TRIUNE_SCRIPTS = { 'triune', 'triune_spellbook', 'triune_cursor', 'triune_buffbot', 'triune_dps' }
        local toRestart = {}

        for _, s in ipairs(TRIUNE_SCRIPTS) do
            local isRunningScript = false
            local ok, status = pcall(function() return mq.TLO.Lua.Script(s).Status() end)
            if ok and status and tostring(status):lower() == 'running' then
                isRunningScript = true
            else
                local okPid, pid = pcall(function() return mq.TLO.Lua.Script(s).PID() end)
                if okPid and pid and tonumber(pid or 0) > 0 then
                    isRunningScript = true
                end
            end

            if isRunningScript and s ~= 'triune_updater' then
                table.insert(toRestart, s)
                diag('Stopping running script: ' .. s)
                mq.cmdf('/lua stop %s', s)
            end
        end

        if #toRestart == 0 then
            table.insert(toRestart, 'triune')
            mq.cmd('/lua stop triune')
        end

        mq.delay(400)

        for _, s in ipairs(toRestart) do
            diag('Restarting updated script: ' .. s)
            mq.cmdf('/lua run %s', s)
        end
    else
        checkStatus = 'error'
        statusMessage = 'Update failed. Check triune_update.log in config folder.'
        print('\ar[TriuneUpdater]\ax \arUpdate failed.\ax Check triune_update.log for details.')
    end
end

-- ImGui Draw Callback
local function drawUpdaterWindow()
    if not isOpen then return end

    pushTheme()
    local open, show = ImGui.Begin('Triune Update Manager##UpdaterWin', isOpen)
    if not open then
        isOpen = false
        ImGui.End()
        popTheme()
        return
    end
    if not show then
        ImGui.End()
        popTheme()
        return
    end

    ImGui.TextColored(0.3, 0.8, 1.0, 1.0, 'Triune AutoCombat Release Updater')
    ImGui.Separator()

    -- Version Information Table
    if ImGui.BeginTable('VersionTable', 2, ImGuiTableFlags.BordersInnerV) then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Installed Version:')
        ImGui.SameLine()
        ImGui.TextColored(0.7, 0.7, 0.7, 1.0, 'v' .. installedVersion)

        ImGui.TableNextColumn()
        ImGui.Text('Latest GitHub Release:')
        ImGui.SameLine()
        if checkStatus == 'available' then
            ImGui.TextColored(1.0, 0.8, 0.2, 1.0, 'v' .. latestVersion .. ' (Update Available!)')
        elseif checkStatus == 'up_to_date' then
            ImGui.TextColored(0.2, 0.9, 0.4, 1.0, 'v' .. latestVersion .. ' (Up to Date)')
        else
            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, latestVersion)
        end
        ImGui.EndTable()
    end

    ImGui.Spacing()
    ImGui.Text('Status:')
    ImGui.SameLine()
    if checkStatus == 'checking' then
        ImGui.TextColored(0.3, 0.7, 1.0, 1.0, statusMessage)
    elseif checkStatus == 'available' then
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0, statusMessage)
    elseif checkStatus == 'up_to_date' then
        ImGui.TextColored(0.2, 0.9, 0.4, 1.0, statusMessage)
    elseif checkStatus == 'error' then
        ImGui.TextColored(1.0, 0.3, 0.3, 1.0, statusMessage)
    else
        ImGui.TextDisabled(statusMessage)
    end

    ImGui.Spacing()
    if #releaseNotes > 0 then
        ImGui.Text('Release Notes:')
        if ImGui.BeginChild('ReleaseNotesBox', 0, 100, true) then
            ImGui.TextWrapped(releaseNotes)
            ImGui.EndChild()
        end
    end

    -- Diagnostics Section
    if #diagLogs > 0 then
        ImGui.Spacing()
        if ImGui.CollapsingHeader('Diagnostics Log##DiagHeader') then
            if ImGui.BeginChild('DiagBox', 0, 120, true) then
                for _, logLine in ipairs(diagLogs) do
                    ImGui.TextUnformatted(logLine)
                end
                ImGui.EndChild()
            end
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Buttons
    if ImGui.Button('Check for Updates##CheckBtn') then
        pendingAction = 'check'
    end

    ImGui.SameLine()
    if checkStatus == 'available' or checkStatus == 'up_to_date' then
        if ImGui.Button('Update Now##UpdateBtn') then
            pendingAction = 'update'
        end
        ImGui.SameLine()
    end

    if ImGui.Button('Close##CloseBtn') then
        isOpen = false
    end

    ImGui.End()
    popTheme()
end

-- Register ImGui render callback
mq.imgui.init('TriuneUpdaterWin', drawUpdaterWindow)

-- Queue initial update check safely on yieldable coroutine thread
pendingAction = 'check'

-- Main loop for executing queued pending actions safely outside render callback
while isRunning and isOpen do
    mq.delay(100)

    if pendingAction == 'check' then
        pendingAction = nil
        checkForUpdates()
    elseif pendingAction == 'update' then
        pendingAction = nil
        executeUpdate()
    end
end

-- Unregister ImGui callback cleanly on exit
pcall(function() mq.imgui.destroy('TriuneUpdaterWin') end)
