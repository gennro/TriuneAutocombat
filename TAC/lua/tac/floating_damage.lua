---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/floating_damage.lua — Triune Floating Damage Text Plugin
-- ============================================================================
-- Renders flashy floating damage numbers above the player character when a
-- critical hit / crippling blow / deadly strike / spell crit lands.
--
-- Runs inside its own coroutine fiber and stays fully active during combat.
-- ============================================================================

local plugin = {
    id                 = 'floating_damage',
    name               = 'Floating Damage Text',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Renders animated floating critical hit damage numbers over characters in 3D world space.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = true,
}

local core = nil
local floaters = {}
local registeredEvents = {}

local CRIT = {
    LIFETIME   = 2.0,
    RISE_SPEED = 80,
    SPREAD     = 120,
    BASE_SIZE  = 22,
    BIG_SIZE   = 32,
    COLORS     = {
        crit      = { 1.0, 0.85, 0.20 },
        crip      = { 1.0, 0.30, 0.15 },
        deadly    = { 0.85, 0.10, 1.0  },
        spellcrit = { 0.30, 0.80, 1.0  },
        holy      = { 1.0, 1.0,  0.75 },
        flurry    = { 0.20, 1.0,  0.50 },
        finish    = { 1.0, 0.55, 0.0  },
        assassin  = { 0.65, 0.0,  0.0  },
        headshot  = { 0.95, 0.60, 0.80 },
        slay      = { 1.0, 0.95, 0.60 },
    },
}

local function floatersEnabled()
    local ctrl = core and core.ctrl
    -- Honors the "Critical Hit Floating Text" checkbox in Settings -> Visual.
    return not (ctrl and ctrl.show_crit_floaters == false)
end

local function spawnFloater(text, critType, dmg)
    if not floatersEnabled() then return end
    local seed = math.random(1000)
    local xOff = math.random(-CRIT.SPREAD / 2, CRIT.SPREAD / 2)
    table.insert(floaters, {
        text      = text,
        type      = critType or 'crit',
        dmg       = dmg or 0,
        spawnedAt = os.clock(),
        xOff      = xOff,
        seed      = seed,
    })
    while #floaters > 20 do
        table.remove(floaters, 1)
    end
end

function plugin.onInit(coreApi)
    core = coreApi
    if core and core.ctrl and core.ctrl.show_crit_floaters == nil then
        core.ctrl.show_crit_floaters = true
    end
    local mq = core and core.mq
    if not mq then return end

    local function reg(name, pattern, handler)
        if mq.unevent then
            pcall(mq.unevent, name)
        end
        mq.event(name, pattern, handler)
        table.insert(registeredEvents, name)
    end

    reg('TacCritHit', '#*#You score a critical hit!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('CRITICAL! %d', dmg), 'crit', dmg)
    end)

    reg('TacCripBlow', '#*#You land a Crippling Blow!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('CRIPPLING BLOW! %d', dmg), 'crip', dmg)
    end)

    reg('TacDeadlyStrike', '#*#You score a Deadly Strike!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('DEADLY STRIKE! %d', dmg), 'deadly', dmg)
    end)

    reg('TacSlayUndead', '#*#You slay#*#undead!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('SLAY UNDEAD! %d', dmg), 'slay', dmg)
    end)

    reg('TacFinishBlow', '#*#You land a Finishing Blow!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('FINISHING BLOW! %d', dmg), 'finish', dmg)
    end)

    reg('TacAssassinate', '#*#You assassinate#*#', function()
        spawnFloater('ASSASSINATE!', 'assassin', 32000)
    end)

    reg('TacHeadshot', '#*#You headshotted#*#', function()
        spawnFloater('HEADSHOT!', 'headshot', 32000)
    end)

    reg('TacFlurry', '#*#You flurry#*#', function()
        spawnFloater('FLURRY!', 'flurry', 0)
    end)

    reg('TacSpellCrit', '#*#critical blast!#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('SPELL CRIT! %d', dmg), 'spellcrit', dmg)
    end)

    reg('TacHealCrit', '#*#critical heal#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('CRIT HEAL! %d', dmg), 'holy', dmg)
    end)

    reg('TacDotCrit', '#*#critical dot#*#(#1#)#*#', function(_, dmgStr)
        local dmg = tonumber(dmgStr) or 0
        spawnFloater(string.format('CRIT DOT! %d', dmg), 'spellcrit', dmg)
    end)
end

function plugin.onDestroy()
    local mq = core and core.mq
    if mq and mq.unevent then
        for _, name in ipairs(registeredEvents) do
            pcall(mq.unevent, name)
        end
    end
    registeredEvents = {}
    floaters = {}
end

function plugin.onTick()
    local now = os.clock()
    local i = 1
    while i <= #floaters do
        if (now - floaters[i].spawnedAt) >= CRIT.LIFETIME then
            table.remove(floaters, i)
        else
            i = i + 1
        end
    end
end

function plugin.onDrawUI()
    if #floaters == 0 or not core or not core.ImGui or not floatersEnabled() then return end
    local ImGui = core.ImGui

    local screenW, screenH = 0, 0
    pcall(function()
        local io = ImGui.GetIO()
        screenW = io.DisplaySize.x
        screenH = io.DisplaySize.y
    end)
    if screenW <= 0 or screenH <= 0 then return end

    local flags = bit.bor(
        ImGuiWindowFlags.NoTitleBar,
        ImGuiWindowFlags.NoResize,
        ImGuiWindowFlags.NoMove,
        ImGuiWindowFlags.NoScrollbar,
        ImGuiWindowFlags.NoInputs,
        ImGuiWindowFlags.NoBackground,
        ImGuiWindowFlags.NoSavedSettings,
        ImGuiWindowFlags.NoFocusOnAppearing,
        ImGuiWindowFlags.NoBringToFrontOnFocus
    )

    ImGui.SetNextWindowPos(0, 0, ImGuiCond.Always)
    ImGui.SetNextWindowSize(screenW, screenH, ImGuiCond.Always)

    local openFlag, show = ImGui.Begin('TacCritOverlayWindow###tacCritOverlay', true, flags)
    if not openFlag then
        ImGui.End()
        return
    end

    if show then
        local dl = ImGui.GetWindowDrawList()
        if dl then
            local anchorX = screenW * 0.5
            local anchorY = screenH * 0.42
            local now = os.clock()

            for _, f in ipairs(floaters) do
                local age = now - f.spawnedAt
                if age < CRIT.LIFETIME then
                    local t = age / CRIT.LIFETIME
                    local wobble = math.sin(age * 4 + f.seed) * 8
                    local px = anchorX + f.xOff + wobble
                    local py = anchorY - (age * CRIT.RISE_SPEED) - (t * t * 30)

                    local alpha
                    if t < 0.1 then
                        alpha = t / 0.1
                    elseif t > 0.7 then
                        alpha = 1.0 - ((t - 0.7) / 0.3)
                    else
                        alpha = 1.0
                    end
                    alpha = math.max(0, math.min(1, alpha))

                    local isBig = f.dmg > 500
                    local baseSize = isBig and CRIT.BIG_SIZE or CRIT.BASE_SIZE
                    local scale
                    if t < 0.15 then
                        scale = 1.0 + 0.5 * math.sin(t / 0.15 * math.pi)
                    else
                        scale = 1.0 + 0.08 * math.sin(age * 6 + f.seed)
                    end
                    local fontSize = baseSize * scale

                    local c = CRIT.COLORS[f.type] or CRIT.COLORS.crit
                    local pulse = 0.7 + 0.3 * math.sin(age * 8 + f.seed)
                    local r = math.min(1, c[1] * pulse + 0.15 * math.sin(age * 5))
                    local g = math.min(1, c[2] * pulse + 0.10 * math.cos(age * 6))
                    local b = math.min(1, c[3] * pulse + 0.10 * math.sin(age * 7))

                    if f.dmg > 2000 then
                        local hueShift = (age * 3 + f.seed * 0.01) % 1.0
                        r = 0.5 + 0.5 * math.sin(hueShift * 6.28)
                        g = 0.5 + 0.5 * math.sin(hueShift * 6.28 + 2.09)
                        b = 0.5 + 0.5 * math.sin(hueShift * 6.28 + 4.19)
                    end

                    local colU32 = IM_COL32(
                        math.floor(r * 255),
                        math.floor(g * 255),
                        math.floor(b * 255),
                        math.floor(alpha * 255)
                    )

                    local shadowCol = IM_COL32(0, 0, 0, math.floor(alpha * 180))
                    pcall(function()
                        dl:AddText(nil, fontSize, ImVec2(px + 1, py + 1), shadowCol, f.text)
                        dl:AddText(nil, fontSize, ImVec2(px, py), colU32, f.text)
                    end)

                    if f.dmg > 1000 and t < 0.6 then
                        pcall(function()
                            for s = 1, 3 do
                                local sx = px + math.sin(age * 10 + s * 2.1 + f.seed) * (30 + s * 10)
                                local sy = py + math.cos(age * 10 + s * 1.7 + f.seed) * (15 + s * 8)
                                local sparkleA = alpha * (1.0 - t / 0.6) * (0.5 + 0.5 * math.sin(age * 20 + s))
                                local sparkleCol = IM_COL32(255, 255, 200, math.floor(sparkleA * 255))
                                dl:AddCircleFilled(ImVec2(sx, sy), 2 + math.sin(age * 15 + s) * 1, sparkleCol, 6)
                            end
                        end)
                    end
                end
            end
        end
    end
    ImGui.End()
end

function plugin.onDrawSettings()
    if not core or not core.ImGui then return end
    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }

    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Floating Text Configuration:')
    ImGui.Text('Lifetime: 2.0s | Upward Velocity: 80 px/s | Max Concurrent: 20')
    if core.ctrl then
        local cur = (core.ctrl.show_crit_floaters ~= false)
        local val = ImGui.Checkbox('Show Critical Hit Floating Text##fdEnabled', cur)
        if val ~= cur then
            core.ctrl.show_crit_floaters = val
            if core.saveLoadout then core.saveLoadout(true) end
        end
    end
    ImGui.Spacing()
    if ImGui.Button('Test Critical Floater##testCritBtn', 160, 24) then
        spawnFloater('CRITICAL! 1450', 'crit', 1450)
    end
    ImGui.SameLine()
    if ImGui.Button('Test Deadly Strike##testDeadlyBtn', 160, 24) then
        spawnFloater('DEADLY STRIKE! 3200', 'deadly', 3200)
    end
    ImGui.SameLine()
    if ImGui.Button('Clear All Floaters##clearCritBtn', 150, 24) then
        floaters = {}
    end
end

return plugin
