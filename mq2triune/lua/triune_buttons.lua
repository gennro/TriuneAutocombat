---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- Triune Hot Buttons v1.0
-- Standalone ImGui hot button panel (ButtonMaster-style) that replaces
-- EverQuest's built-in hot button bars.
--
-- Features:
-- - Tabbed hotbar sets with drag-and-drop reordering and right-click
--   context menus (rename, move, delete, add tab).
-- - Icon buttons rendered from EQ texture animations (spell/item icons).
-- - Live cooldown overlays: spell gems, abilities, AAs, disciplines,
--   item timers, or manual seconds timers -- all via MQ TLOs.
-- - Multi-line command buttons executed line-by-line on the yieldable
--   main thread (no "Cannot delay from non-yieldable thread" errors).
-- - One-click button creation from whatever is on your cursor (spell gem,
--   item, ability, discipline, AA/social button).
-- - Per-character persistence in mq.configDir/triune_buttons_config.lua.
--
-- Run with:  /lua run triune_buttons
-- Stop with: /lua stop triune_buttons
-- ============================================================================

local mq    = require('mq')
local ImGui = require('ImGui')
local bit   = require('bit') -- LuaJIT bitwise library

local VERSION     = '1.0'
local CONFIG_NAME = 'triune_buttons_config.lua'
local CFG         = mq.configDir and (mq.configDir .. '/' .. CONFIG_NAME) or nil

-- Theme & style helpers for hot button window
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

-- Accent palette (ImGui float colors)
local ARC   = { 0.30, 0.80, 1.00, 1.0 }
local GOOD  = { 0.40, 0.85, 0.50, 1.0 }
local WARN  = { 0.95, 0.75, 0.30, 1.0 }
local ERR   = { 0.95, 0.40, 0.40, 1.0 }
local MUTED = { 0.55, 0.60, 0.65, 1.0 }

-- ImU32 (0xAABBGGRR) builder for draw list colors
local function col32(r, g, b, a)
    local R = math.min(255, math.max(0, math.floor((r or 0) * 255 + 0.5)))
    local G = math.min(255, math.max(0, math.floor((g or 0) * 255 + 0.5)))
    local B = math.min(255, math.max(0, math.floor((b or 0) * 255 + 0.5)))
    local A = math.min(255, math.max(0, math.floor((a or 1) * 255 + 0.5)))
    return (A * 16777216) + (B * 65536) + (G * 256) + R
end

-- Cooldown timer types (TIMER_KEYS index aligns with TIMER_TYPES)
local TIMER_TYPES    = { 'None', 'Spell Gem', 'Ability', 'AA', 'Disc', 'Item', 'Seconds' }
local TIMER_KEYS     = { nil, 'Gem', 'Ability', 'AA', 'Disc', 'Item', 'Seconds' }
local TIMER_KEY_LIST = { 'Gem', 'Ability', 'AA', 'Disc', 'Item', 'Seconds' } -- ipairs-safe
local TIMER_KEY_SET  = {}
for _, k in ipairs(TIMER_KEY_LIST) do TIMER_KEY_SET[k] = true end

-- ============================================================================
-- State
-- ============================================================================
local openGUI     = true
local isRunning   = true
local pendingCmd  = nil   -- { uid, label, cmd, timerType, timerKey }
local statusMsg   = ''
local statusTime  = 0
local uidCounter  = 0
local fireTime    = {}    -- uid -> os.clock() for manual Seconds timers

local state = {
    tabs        = {},   -- ordered: { name=, buttonSize=, buttons={ btn, ... } }
    activeTab   = 1,
    defaultSize = 48,
}

-- Edit popup state
local edit = {
    open        = false,
    tabIdx      = 0,
    btnIdx      = 0,   -- 0 = new button (appended on save)
    tmp         = nil, -- working copy of the button
    dirty       = false,
    iconBuf     = '',
    timerIdx    = 1,   -- 1-based index into TIMER_TYPES
    timerKeyBuf = '',
}

-- Rename tab modal state
local rename = { open = false, tabIdx = 0, buf = '' }

-- ============================================================================
-- Small helpers
-- ============================================================================
local function tlo(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function trim(s)
    return tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function setStatus(msg)
    statusMsg  = msg
    statusTime = os.clock()
end

local function newUid()
    uidCounter = uidCounter + 1
    return 'b' .. uidCounter
end

local function textWidth(s)
    local v = tlo(function() return ImGui.CalcTextSizeVec(tostring(s)) end)
    if v and type(v.x) == 'number' then return v.x end
    return #tostring(s) * 6.5
end

local function closeEditRef()
    edit.open = false
    edit.tmp  = nil
    edit.dirty = false
end

-- ============================================================================
-- Persistence (per character, plain Lua file in mq.configDir)
-- ============================================================================
local function serializeValue(val)
    if type(val) == 'string' then
        return string.format("%q", val)
    elseif type(val) == 'number' or type(val) == 'boolean' then
        return tostring(val)
    elseif type(val) == 'table' then
        local parts = {}
        for k, v in pairs(val) do
            local keyStr = (type(k) == 'number') and string.format("[%d]", k) or string.format("[%q]", tostring(k))
            local valStr = serializeValue(v)
            if valStr then
                table.insert(parts, keyStr .. " = " .. valStr)
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "nil"
end

local function charKey()
    local myName, myServer = nil, nil
    pcall(function()
        myName   = mq.TLO.Me.CleanName()
        myServer = mq.TLO.EverQuest.Server()
    end)
    return (myServer or 'default') .. '_' .. (myName or 'default')
end

local function saveConfig(silent)
    if not CFG then return end
    local allData = {}
    local fn = loadfile(CFG)
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == 'table' then allData = t end
    end
    allData[charKey()] = {
        version     = 1,
        defaultSize = state.defaultSize,
        tabs        = state.tabs,
    }
    local f = io.open(CFG, 'w')
    if f then
        f:write("return " .. serializeValue(allData) .. "\n")
        f:close()
        if not silent then
            print('\ag[Triune Buttons]\ax Saved hot button configuration.')
        end
    end
end

local function defaultTabs()
    return { { name = 'Combat', buttonSize = state.defaultSize, buttons = {} } }
end

local function loadConfig()
    if not CFG then return end
    local fn = loadfile(CFG)
    if not fn then return end
    local ok, allData = pcall(fn)
    if not ok or type(allData) ~= 'table' then return end

    local data = allData[charKey()] or allData['default']
    if type(data) ~= 'table' or type(data.tabs) ~= 'table' or #data.tabs == 0 then return end

    if type(data.defaultSize) == 'number' and data.defaultSize >= 24 then
        state.defaultSize = data.defaultSize
    end
    state.tabs = data.tabs
    state.activeTab = 1

    for ti, tab in ipairs(state.tabs) do
        if type(tab) ~= 'table' then
            tab = { name = 'Tab ' .. ti, buttonSize = state.defaultSize, buttons = {} }
            state.tabs[ti] = tab
        end
        if type(tab.name) ~= 'string' or trim(tab.name) == '' then
            tab.name = 'Tab ' .. ti
        end
        if type(tab.buttonSize) ~= 'number' or tab.buttonSize < 24 or tab.buttonSize > 96 then
            tab.buttonSize = state.defaultSize
        end
        if type(tab.buttons) ~= 'table' then tab.buttons = {} end

        local clean = {}
        for _, b in ipairs(tab.buttons) do
            if type(b) == 'table' then
                if type(b.label) ~= 'string' or b.label == '' then b.label = 'Button' end
                if type(b.cmd) ~= 'string' then b.cmd = '' end
                if type(b.uid) ~= 'string' or b.uid == '' then b.uid = newUid() end
                if type(b.showLabel) ~= 'boolean' then b.showLabel = true end
                if type(b.icon) == 'number' and b.icon <= 0 then b.icon = nil end
                if b.timerType and not TIMER_KEY_SET[b.timerType] then
                    b.timerType = nil
                    b.timerKey  = nil
                end
                table.insert(clean, b)
                local n = tonumber(tostring(b.uid):match('%d+')) or 0
                if n > uidCounter then uidCounter = n end
            end
        end
        tab.buttons = clean
    end
    print(string.format('\ag[Triune Buttons]\ax Loaded %d tab(s) for %s.', #state.tabs, charKey()))
end

-- ============================================================================
-- Icon textures (EQ texture animations, cached per icon ID)
-- ============================================================================
local iconCache = {}
local iconMode  = 'probe' -- 'probe' | 'dedicated' | 'shared' | 'none'
local sharedTex = nil
local lastCell  = nil

local function probeIconMode()
    if iconMode ~= 'probe' then return end
    if mq.TextureAnimation then
        local ok, res = pcall(mq.TextureAnimation, 'triunebtn_probe')
        if ok and res then
            iconMode = 'dedicated'
            return
        end
    end
    local ok2, res2 = pcall(mq.FindTextureAnimation, 'eq')
    if ok2 and res2 then
        iconMode  = 'shared'
        sharedTex = res2
        return
    end
    iconMode = 'none'
end

-- Returns a texture object showing the given icon, or nil.
-- In shared mode the single 'eq' animation is re-pointed per icon, so the
-- returned object must be drawn immediately (before re-pointing again).
local function iconFor(iconId)
    local id = tonumber(iconId)
    if not id or id <= 0 then return nil end
    probeIconMode()

    if iconMode == 'dedicated' then
        local key = tostring(id)
        local ta = iconCache[key]
        if not ta then
            local ok, res = pcall(mq.TextureAnimation, 'triunebtn_' .. key)
            if ok and res then
                pcall(function() res:SetTextureCell(id) end)
                iconCache[key] = res
                ta = res
            end
        end
        return ta
    elseif iconMode == 'shared' and sharedTex then
        if lastCell ~= id then
            if not pcall(function() sharedTex:SetTextureCell(id) end) then
                return nil
            end
            lastCell = id
        end
        return sharedTex
    end
    return nil
end

-- ============================================================================
-- Cooldown lookup (TLO based, pcall-safe, returns seconds remaining)
-- ============================================================================
local function msToSec(v)
    if type(v) == 'number' and v > 0 then return v / 1000 end
    return 0
end

local function getCooldown(btn)
    local tt = btn.timerType
    if not tt or tt == 'None' then return 0 end
    local key = btn.timerKey

    if tt == 'Gem' then
        return msToSec(tlo(function() return mq.TLO.Me.GemTimer(tonumber(key) or 1) end))
    elseif tt == 'Ability' then
        return msToSec(tlo(function() return mq.TLO.Me.AbilityTimer(tostring(key)) end))
    elseif tt == 'AA' then
        return msToSec(tlo(function() return mq.TLO.Me.AltAbilityTimer(tostring(key)) end))
    elseif tt == 'Disc' then
        return msToSec(tlo(function() return mq.TLO.Me.CombatAbilityTimer(tostring(key)) end))
    elseif tt == 'Item' then
        local v = tlo(function() return mq.TLO.FindItem(tostring(key)).TimerReady() end)
        if type(v) == 'number' and v > 0 then
            -- Doc says seconds, but guard against millisecond builds.
            if v > 1800 then return v / 1000 end
            return v
        end
        return 0
    elseif tt == 'Seconds' then
        local t = fireTime[btn.uid]
        if t then
            local total = tonumber(key) or 0
            return math.max(0, total - (os.clock() - t))
        end
        return 0
    end
    return 0
end

-- ============================================================================
-- Tab operations
-- ============================================================================
local function addTab()
    local name = 'Tab ' .. (#state.tabs + 1)
    table.insert(state.tabs, { name = name, buttonSize = state.defaultSize, buttons = {} })
    state.activeTab = #state.tabs
    saveConfig(true)
    setStatus('Added tab "' .. name .. '".')
end

local function deleteTab(idx)
    if #state.tabs <= 1 then
        setStatus('Cannot delete the last tab.')
        return
    end
    local tab = state.tabs[idx]
    if not tab then return end
    table.remove(state.tabs, idx)
    if state.activeTab > #state.tabs then state.activeTab = #state.tabs end
    if state.activeTab < 1 then state.activeTab = 1 end
    if edit.open and edit.tabIdx >= idx then closeEditRef() end
    saveConfig(true)
    setStatus('Deleted tab "' .. tab.name .. '".')
end

local function moveTab(src, dst)
    local tabs = state.tabs
    if src == dst or src < 1 or dst < 1 or src > #tabs or dst > #tabs then return end
    local t = table.remove(tabs, src)
    table.insert(tabs, dst, t)
    if state.activeTab == src then
        state.activeTab = dst
    elseif src < state.activeTab and dst >= state.activeTab then
        state.activeTab = state.activeTab - 1
    elseif dst < state.activeTab and src >= state.activeTab then
        state.activeTab = state.activeTab + 1
    end
    saveConfig(true)
end

local function renameTab(idx, newName)
    local tab = state.tabs[idx]
    if not tab then return end
    local clean = trim(newName)
    if clean == '' then
        setStatus('Tab name cannot be empty.')
        return
    end
    tab.name = clean
    saveConfig(true)
    setStatus('Renamed tab to "' .. clean .. '".')
end

-- ============================================================================
-- Button operations
-- ============================================================================
local function openEdit(tabIdx, btnIdx, srcOverride)
    local tab = state.tabs[tabIdx]
    if not tab then return end

    local src = srcOverride or (btnIdx > 0 and tab.buttons[btnIdx] or nil)
    edit.open   = true
    edit.tabIdx = tabIdx
    edit.btnIdx = btnIdx
    edit.dirty  = false

    if src then
        edit.tmp = {
            uid       = (type(src.uid) == 'string' and src.uid ~= '') and src.uid or newUid(),
            label     = src.label or '',
            cmd       = src.cmd or '',
            icon      = src.icon,
            timerType = src.timerType,
            timerKey  = src.timerKey,
            showLabel = src.showLabel ~= false,
        }
    else
        edit.tmp = {
            uid       = newUid(),
            label     = '',
            cmd       = '',
            icon      = nil,
            timerType = nil,
            timerKey  = nil,
            showLabel = true,
        }
    end

    edit.iconBuf  = edit.tmp.icon and tostring(edit.tmp.icon) or ''
    edit.timerIdx = 1
    for i, k in ipairs(TIMER_KEY_LIST) do
        if k == edit.tmp.timerType then edit.timerIdx = i + 1 break end
    end
    edit.timerKeyBuf = edit.tmp.timerKey and tostring(edit.tmp.timerKey) or ''
end

local function saveEdit()
    if not edit.open or not edit.tmp then return end

    local label = trim(edit.tmp.label)
    if label == '' then
        setStatus('Button label cannot be empty.')
        return
    end
    local tab = state.tabs[edit.tabIdx]
    if not tab then
        closeEditRef()
        return
    end

    local tt = TIMER_KEYS[edit.timerIdx]
    local tk = edit.timerKeyBuf
    if tt == 'Gem' then
        local g = tonumber(tk) or 1
        local maxG = 12
        local ng = tlo(function() return mq.TLO.Me.NumGems() end)
        if type(ng) == 'number' and ng > 0 then maxG = math.floor(ng) end
        if g < 1 then g = 1 end
        if g > maxG then g = maxG end
        tk = g
    elseif tt == 'Seconds' then
        tk = math.max(0, tonumber(tk) or 0)
    elseif tt == 'Item' or tt == 'Ability' or tt == 'AA' or tt == 'Disc' then
        tk = trim(tk)
        if tk == '' then tk = label end
    else
        tk = nil
    end

    local iconId = tonumber(edit.iconBuf) or 0
    local b = {
        uid       = edit.tmp.uid,
        label     = label,
        cmd       = tostring(edit.tmp.cmd or ''),
        icon      = iconId > 0 and iconId or nil,
        timerType = tt,
        timerKey  = tk,
        showLabel = edit.tmp.showLabel == true,
    }

    if edit.btnIdx > 0 then
        tab.buttons[edit.btnIdx] = b
        fireTime[b.uid] = nil
    else
        table.insert(tab.buttons, b)
    end
    closeEditRef()
    saveConfig(true)
    setStatus('Saved button "' .. label .. '".')
end

local function duplicateButton(tabIdx, btnIdx)
    local tab = state.tabs[tabIdx]
    local src = tab and tab.buttons[btnIdx]
    if not src then return end
    local copy = {
        uid       = newUid(),
        label     = src.label .. ' (copy)',
        cmd       = src.cmd,
        icon      = src.icon,
        timerType = src.timerType,
        timerKey  = src.timerKey,
        showLabel = src.showLabel,
    }
    table.insert(tab.buttons, btnIdx + 1, copy)
    saveConfig(true)
    setStatus('Duplicated button.')
end

local function deleteButton(tabIdx, btnIdx)
    local tab = state.tabs[tabIdx]
    local src = tab and tab.buttons[btnIdx]
    if not src then return end
    table.remove(tab.buttons, btnIdx)
    fireTime[src.uid] = nil
    if edit.open and edit.tabIdx == tabIdx and edit.btnIdx >= btnIdx then
        closeEditRef()
    end
    saveConfig(true)
    setStatus('Deleted button "' .. src.label .. '".')
end

local function copyButton(tabIdx, btnIdx)
    local tab = state.tabs[tabIdx]
    local src = tab and tab.buttons[btnIdx]
    if not src then return end
    pcall(ImGui.SetClipboardText, (src.label or '') .. '\n' .. (src.cmd or ''))
    setStatus('Copied button to clipboard.')
end

-- ============================================================================
-- Cursor attachment import (spell gem / item / ability / disc / social)
-- ============================================================================
local function cursorIconId()
    local ic = tlo(function() return mq.TLO.CursorAttachment.IconID() end)
    if type(ic) == 'number' and ic > 0 then return ic end
    return nil
end

local function buttonFromCursor()
    local ok, ca = pcall(function() return mq.TLO.CursorAttachment end)
    if not ok or not ca then return nil end
    local typ = tlo(function() return ca.Type() end)
    if not typ or tostring(typ) == '' then return nil end
    local t = tostring(typ):lower()

    local b = { uid = newUid(), label = '', cmd = '', icon = nil, timerType = nil, timerKey = nil, showLabel = true }

    if t == 'item' or t == 'item_link' then
        local it = tlo(function() return ca.Item() end)
        if not it then return nil end
        local name = tlo(function() return it.Name() end) or 'Item'
        b.label     = name
        b.cmd       = string.format('/useitem "%s"', name)
        local ic    = cursorIconId()
        if not ic then
            ic = tlo(function() return it.Icon() end)
            if type(ic) == 'number' and ic > 500 then ic = ic - 500 else ic = nil end
        end
        if ic then b.icon = ic end
        b.timerType = 'Item'
        b.timerKey  = name
    elseif t == 'spell_gem' then
        local sp = tlo(function() return ca.Spell() end)
        if not sp then return nil end
        local rank = tlo(function() return sp.RankName() end)
        b.label = (rank and tostring(rank) ~= '') and tostring(rank) or 'Spell'
        local gem = tlo(function() return mq.TLO.Me.Gem(b.label)() end)
        if type(gem) ~= 'number' or gem <= 0 then
            local gi = tlo(function() return ca.Index() end)
            if type(gi) == 'number' and gi > 0 then gem = math.floor(gi) end
        end
        if type(gem) ~= 'number' or gem <= 0 then gem = 1 end
        b.cmd       = string.format('/cast %d', math.floor(gem))
        local ic    = tlo(function() return sp.SpellIcon() end)
        if type(ic) == 'number' and ic > 0 then b.icon = ic end
        b.timerType = 'Gem'
        b.timerKey  = math.floor(gem)
    elseif t == 'ability' or t == 'skill' then
        local bt = tlo(function() return ca.ButtonText() end)
        b.label = (bt and tostring(bt) ~= '') and tostring(bt) or 'Skill'
        b.cmd   = string.format('/doability "%s"', b.label)
        b.timerType = 'Ability'
        b.timerKey  = b.label
    elseif t == 'melee_ability' or t == 'combat' or t == 'combat_ability' then
        local bt = tlo(function() return ca.ButtonText() end)
        b.label = (bt and tostring(bt) ~= '') and tostring(bt) or 'Discipline'
        b.cmd   = string.format('/disc "%s"', b.label)
        local ic = tlo(function() return mq.TLO.Spell(b.label).SpellIcon() end)
        if type(ic) == 'number' and ic > 0 then b.icon = ic end
        b.timerType = 'Disc'
        b.timerKey  = b.label
    elseif t == 'memorize_spell' then
        local sp = tlo(function() return ca.Spell() end)
        if not sp then return nil end
        local nm = tlo(function() return sp.Name() end)
        if not nm or tostring(nm) == '' then return nil end
        b.label = tostring(nm)
        b.cmd   = string.format('/memorize %s', b.label)
        local ic = tlo(function() return sp.SpellIcon() end)
        if type(ic) == 'number' and ic > 0 then b.icon = ic end
    elseif t == 'social' then
        local idx = 0
        local gi = tlo(function() return ca.Index() end)
        if type(gi) == 'number' then idx = math.floor(gi) end
        local bt = tlo(function() return ca.ButtonText() end)
        local name = (bt and tostring(bt) ~= '') and tostring(bt) or 'Ability'
        if idx + 1 > 120 then
            b.label     = name
            b.cmd       = string.format('/alt act %d', idx - 120)
            b.timerType = 'AA'
            b.timerKey  = name
        else
            local parts = {}
            for ci = 0, 4 do
                local c = tlo(function() return mq.TLO.Social(idx + 1).Cmd(ci) end)
                if c and tostring(c) ~= '' then
                    table.insert(parts, tostring(c))
                end
            end
            if #parts == 0 then return nil end
            b.label = name
            b.cmd   = table.concat(parts, '\n')
        end
    elseif t == 'command' then
        local bt = tlo(function() return ca.ButtonText() end)
        if not bt or tostring(bt) == '' then return nil end
        b.label = (tostring(bt):match('^/(%S+)') or 'Command')
        b.cmd   = tostring(bt)
    else
        return nil
    end

    if not b.icon then b.icon = cursorIconId() end
    return b
end

-- ============================================================================
-- UI: button grid
-- ============================================================================
local function drawButtonGrid(tab)
    local size    = tab.buttonSize
    local showLbl = size >= 36
    local labelH  = showLbl and 14 or 0
    local cellH   = size + labelH
    local spacing = 4

    local avail = ImGui.GetContentRegionAvailVec()
    local cols  = math.floor((avail.x + spacing) / (size + spacing))
    if cols < 1 then cols = 1 end
    if cols > 20 then cols = 20 end

    if #tab.buttons == 0 then
        ImGui.TextDisabled('(No buttons yet -- use "Add Button" or "From Cursor" below.)')
        return
    end

    local dl = ImGui.GetWindowDrawList()
    for i, btn in ipairs(tab.buttons) do
        if i > 1 then
            if (i - 1) % cols == 0 then
                ImGui.Dummy(0, spacing)
            else
                ImGui.SameLine(0, spacing)
            end
        end

        ImGui.PushID(btn.uid)
        local pressed = ImGui.InvisibleButton('##cell', size, cellH)
        if pressed then
            pendingCmd = {
                uid       = btn.uid,
                label     = btn.label,
                cmd       = btn.cmd,
                timerType = btn.timerType,
                timerKey  = btn.timerKey,
            }
        end

        local mnX, mnY = ImGui.GetItemRectMin()
        local mxX, mxY = ImGui.GetItemRectMax()
        local hov = ImGui.IsItemHovered()

        dl:AddRect(ImVec2(mnX, mnY), ImVec2(mxX, mxY), col32(0.16, 0.25, 0.35, 1), 4)

        local tex = btn.icon and iconFor(btn.icon) or nil
        if tex then
            local pad = 2
            dl:AddTextureAnimation(tex, ImVec2(mnX + pad, mnY + pad), ImVec2(size - pad * 2, size - pad * 2))
        elseif size >= 28 then
            local lbl  = btn.label or ''
            local maxC = math.floor(size / 6)
            if #lbl > maxC then lbl = lbl:sub(1, math.max(1, maxC - 1)) .. '.' end
            local lw = textWidth(lbl)
            dl:AddText(ImVec2(mnX + math.max(0, (size - lw) / 2), mnY + size / 2 - 6), col32(0.85, 0.90, 0.95, 1), lbl)
        end

        local cd = getCooldown(btn)
        if cd > 0.05 then
            local frac = math.min(1, cd / 30)
            local oh   = size * frac
            dl:AddRectFilled(ImVec2(mnX + 1, mnY + 1), ImVec2(mxX - 1, mnY + 1 + oh), col32(0, 0, 0, 0.55), 3)
            local tstr
            if cd >= 60 then
                tstr = string.format('%d:%02d', math.floor(cd / 60), math.floor(cd % 60))
            else
                tstr = string.format('%.0f', cd)
            end
            local tw = textWidth(tstr)
            dl:AddText(ImVec2(mnX + (size - tw) / 2, mnY + size / 2 - 7), col32(1, 1, 1, 1), tstr)
        end

        if showLbl and btn.showLabel then
            local lbl  = btn.label or ''
            local maxC = math.floor(size / 6)
            if #lbl > maxC then lbl = lbl:sub(1, math.max(1, maxC - 1)) .. '.' end
            local lw = textWidth(lbl)
            dl:AddText(ImVec2(mnX + math.max(0, (size - lw) / 2), mnY + size + 2), col32(0.85, 0.90, 0.95, 0.9), lbl)
        end

        if hov and not ImGui.IsItemActive() then
            local tip = btn.label or ''
            local n = 0
            for line in (btn.cmd or ''):gmatch('[^\n\r]+') do
                n = n + 1
                if n <= 3 then
                    tip = tip .. '\n' .. line
                else
                    tip = tip .. '\n...'
                    break
                end
            end
            if btn.timerType and btn.timerType ~= 'None' then
                tip = tip .. '\n[' .. btn.timerType .. (btn.timerKey and (' ' .. tostring(btn.timerKey)) or '') .. ']'
            end
            if cd > 0.05 then
                tip = tip .. '\nCooldown: ' .. string.format('%.1fs', cd)
            end
            ImGui.SetTooltip('%s', tip)
        end

        if ImGui.BeginPopupContextItem('##btnCtx') then
            if ImGui.MenuItem('Edit') then openEdit(state.activeTab, i) end
            if ImGui.MenuItem('Duplicate') then duplicateButton(state.activeTab, i) end
            if ImGui.MenuItem('Copy to Clipboard') then copyButton(state.activeTab, i) end
            ImGui.Separator()
            if ImGui.MenuItem('Delete') then deleteButton(state.activeTab, i) end
            ImGui.EndPopup()
        end

        ImGui.PopID()
    end
end

-- ============================================================================
-- UI: edit button window
-- ============================================================================
local function drawEditWindow()
    local flags = 0
    if ImGuiWindowFlags and edit.dirty then
        flags = bit.bor(flags, ImGuiWindowFlags.UnsavedDocument)
    end
    local open, draw = ImGui.Begin('Edit Button##btnEdit', true, flags)
    if not open then
        closeEditRef()
        ImGui.End()
        return
    end
    if draw then
        local t = edit.tmp

        ImGui.PushItemWidth(-120)
        local newLabel = ImGui.InputText('Label', t.label)
        ImGui.PopItemWidth()
        if newLabel ~= t.label then t.label = newLabel; edit.dirty = true end

        ImGui.SameLine()
        if ImGui.Button('From Cursor##editIcon', 92, 24) then
            local ic = cursorIconId()
            if ic then
                edit.iconBuf = tostring(ic)
                edit.dirty   = true
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Clear##editIcon', 60, 24) then
            edit.iconBuf = ''
            edit.dirty   = true
        end

        local newIconBuf = ImGui.InputText('Icon ID', edit.iconBuf)
        if newIconBuf ~= edit.iconBuf then edit.iconBuf = newIconBuf; edit.dirty = true end

        local newTimerIdx = ImGui.Combo('Timer', edit.timerIdx, TIMER_TYPES)
        if newTimerIdx ~= edit.timerIdx then
            edit.timerIdx    = newTimerIdx
            edit.timerKeyBuf = ''
            edit.dirty       = true
        end

        if edit.timerIdx > 1 then
            local keyHint = {
                [2] = 'Gem number (1-12)',
                [3] = 'Ability name',
                [4] = 'AA name',
                [5] = 'Discipline name',
                [6] = 'Item name',
                [7] = 'Seconds',
            }
            ImGui.PushItemWidth(-140)
            local newKeyBuf = ImGui.InputText('Timer Key', edit.timerKeyBuf)
            ImGui.PopItemWidth()
            if newKeyBuf ~= edit.timerKeyBuf then edit.timerKeyBuf = newKeyBuf; edit.dirty = true end
            ImGui.SameLine()
            ImGui.TextDisabled(keyHint[edit.timerIdx] or '')
        end

        local newShow = ImGui.Checkbox('Show Label', t.showLabel)
        if newShow ~= t.showLabel then t.showLabel = newShow; edit.dirty = true end

        local newCmd = ImGui.InputTextMultiline('Commands (one per line)', t.cmd, 0, 90)
        if newCmd ~= t.cmd then t.cmd = newCmd; edit.dirty = true end

        ImGui.Dummy(0, 4)
        local ctrlS = false
        if ImGuiMod and ImGuiKey then
            local ok, pressed = pcall(ImGui.IsKeyChordPressed, bit.bor(ImGuiMod.Ctrl, ImGuiKey.S))
            ctrlS = ok and pressed or false
        end
        if ImGui.Button('Save', 90, 26) or ctrlS then
            saveEdit()
        end
        ImGui.SameLine()
        if ImGui.Button('Cancel', 90, 26) then
            closeEditRef()
        end
    end
    ImGui.End()
end

-- ============================================================================
-- UI: main window
-- ============================================================================
local function DrawButtonsUI()
    if not openGUI then
        isRunning = false
        return
    end

    pushTheme()

    ImGui.SetNextWindowCollapsed(false, ImGuiCond.Appearing)
    ImGui.SetNextWindowSize(480, 360, ImGuiCond.FirstUseEver)
    local windowFlags = 0
    if ImGuiWindowFlags then
        windowFlags = bit.bor(ImGuiWindowFlags.AlwaysUseWindowPadding)
    end
    local open, draw = ImGui.Begin('Triune Hot Buttons v' .. VERSION .. '##TriuneButtons', openGUI, windowFlags)
    if not open then
        saveConfig(true)
        openGUI   = false
        isRunning = false
        ImGui.End()
        popTheme()
        return
    end

    if draw then
        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], 'HOT BUTTONS')
        ImGui.SameLine()
        ImGui.TextDisabled('| Tabbed hotbars with live cooldowns')
        ImGui.Separator()
        ImGui.Dummy(0, 4)

        -- Tab bar
        local tabBarFlags = 0
        if ImGuiTabBarFlags then
            tabBarFlags = bit.bor(tabBarFlags, ImGuiTabBarFlags.FittingPolicyScroll)
        end
        if ImGui.BeginTabBar('##btnTabBar', tabBarFlags) then
            for idx, tab in ipairs(state.tabs) do
                local tflags = 0
                if idx == state.activeTab and ImGuiTabItemFlags then
                    tflags = bit.bor(tflags, ImGuiTabItemFlags.SetSelected)
                end
                if ImGui.BeginTabItem(tab.name .. '###btnTab_' .. idx, nil, tflags) then
                    state.activeTab = idx

                    if ImGui.BeginDragDropSource() then
                        ImGui.SetDragDropPayload('TRIUNE_BTNTAB', tostring(idx))
                        ImGui.EndDragDropSource()
                    end

                    if ImGui.BeginPopupContextItem('##btnTabMenu') then
                        if ImGui.MenuItem('Rename') then
                            rename.open   = true
                            rename.tabIdx = idx
                            rename.buf    = tab.name
                            ImGui.OpenPopup('Rename Tab##btnRename')
                        end
                        if idx > 1 and ImGui.MenuItem('Move Left') then moveTab(idx, idx - 1) end
                        if idx < #state.tabs and ImGui.MenuItem('Move Right') then moveTab(idx, idx + 1) end
                        if idx > 1 and ImGui.MenuItem('Move to First') then moveTab(idx, 1) end
                        if idx < #state.tabs and ImGui.MenuItem('Move to Last') then moveTab(idx, #state.tabs) end
                        ImGui.Separator()
                        if ImGui.MenuItem('Delete Tab') then deleteTab(idx) end
                        ImGui.EndPopup()
                    end

                    if ImGui.BeginDragDropTarget() then
                        local payload = ImGui.AcceptDragDropPayload('TRIUNE_BTNTAB')
                        if payload then
                            local srcIdx = tonumber(payload.Data)
                            if srcIdx and srcIdx ~= idx then moveTab(srcIdx, idx) end
                        end
                        ImGui.EndDragDropTarget()
                    end

                    ImGui.EndTabItem()
                end
            end

            if ImGui.BeginTabItem('+ Add Tab###btnAddTab') then
                addTab()
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end

        ImGui.Dummy(0, 2)

        -- Button grid for the active tab
        local tab = state.tabs[state.activeTab] or state.tabs[1]
        if tab then
            drawButtonGrid(tab)

            ImGui.Separator()
            ImGui.SameLine()
            ImGui.TextDisabled('Size:')
            ImGui.SameLine()
            local newSize = ImGui.SliderInt('##btnSize', tab.buttonSize, 24, 96)
            if newSize ~= tab.buttonSize then
                tab.buttonSize = newSize
                saveConfig(true)
            end
            ImGui.SameLine()
            if ImGui.Button('Add Button', 92, 24) then
                openEdit(state.activeTab, 0)
            end
            ImGui.SameLine()
            if ImGui.Button('From Cursor', 92, 24) then
                local b = buttonFromCursor()
                if b then
                    openEdit(state.activeTab, 0, b)
                else
                    setStatus('Nothing usable on cursor.')
                end
            end
            if statusMsg ~= '' and (os.clock() - statusTime) < 5 then
                ImGui.SameLine()
                ImGui.TextDisabled('%s', statusMsg)
            end
        end
    end

    ImGui.End()

    -- Edit popup (separate window, drawn every frame while open)
    if edit.open and edit.tmp then
        drawEditWindow()
    end

    -- Rename tab modal
    if rename.open then
        if ImGui.BeginPopupModal('Rename Tab##btnRename', nil, 0) then
            local newBuf = ImGui.InputText('Name', rename.buf)
            if newBuf ~= rename.buf then rename.buf = newBuf end
            ImGui.Dummy(0, 4)
            if ImGui.Button('OK', 80, 24) then
                renameTab(rename.tabIdx, rename.buf)
                rename.open = false
                ImGui.EndPopup()
            end
            ImGui.SameLine()
            if ImGui.Button('Cancel', 80, 24) then
                rename.open = false
                ImGui.EndPopup()
            end
            ImGui.EndPopup()
        end
    end

    popTheme()
end

-- ============================================================================
-- Startup
-- ============================================================================
loadConfig()
if #state.tabs == 0 then
    state.tabs = defaultTabs()
end

mq.imgui.init('TriuneButtonsUI', DrawButtonsUI)

print(string.format('\ag[Triune Buttons] v%s\ax UI initialized. Close the window or /lua stop triune_buttons to exit.', VERSION))

-- Main loop (yieldable coroutine thread -- mq.delay allowed here)
while isRunning do
    if pendingCmd then
        local p = pendingCmd
        pendingCmd = nil
        if p.timerType == 'Seconds' then
            fireTime[p.uid] = os.clock()
        end
        if p.cmd and trim(p.cmd) ~= '' then
            for line in (p.cmd):gmatch('[^\n\r]+') do
                local l = trim(line)
                if l ~= '' then
                    mq.cmd(l)
                    mq.delay(50)
                end
            end
        end
    end
    mq.delay(50)
end

print('\ag[Triune Buttons]\ax Closed.')
