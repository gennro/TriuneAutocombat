---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/floating_damage.lua — Triune Floating Damage Text Plugin
-- ============================================================================
-- Renders flashy floating damage numbers above the player character when a
-- critical hit / crippling blow / deadly strike / spell crit lands.
--
-- Every hit slams in with an elastic impact pop, rolls its number up from
-- zero, and is stroked with a dark outline so it reads over any background.
-- Bigger hits climb through damage tiers (BIG / HUGE / MASSIVE) that add a
-- particle burst, an expanding shockwave ring, a rainbow shimmer and - for the
-- biggest - a screen flash and overlay shake. Back-to-back crits build a combo
-- counter with milestone shout-outs, and beating the session's best hit earns
-- a NEW RECORD! callout.
--
-- Runs inside its own coroutine fiber and stays fully active during combat.
-- ============================================================================

local plugin = {
    id                 = 'floating_damage',
    name               = 'Floating Damage Text',
    version            = '2.0.0',
    author             = 'Triune',
    description        = 'Renders animated floating critical hit damage numbers with impact pops, particle bursts, shockwaves, combo streaks and record callouts.',
    defaultEnabled     = true,
    tickInterval       = 0.05,
    runOutOfCombatOnly = false,
    hasThread          = true,
}

local core = nil
local floaters = {}
local registeredEvents = {}

-- Tunables persisted through onSaveSettings / onLoadSettings.
local cfg = {
    textScale    = 1.0,   -- multiplies every font size
    intensity    = 1.0,   -- multiplies particle counts, ring size, flash and shake
    tierScale    = 1.0,   -- multiplies the damage tier thresholds (lower it at low levels)
    comboCounter = true,
    screenFlash  = true,
    screenShake  = true,
}

local FX = {
    LIFETIME      = 2.2,   -- seconds a floater stays on screen
    RISE_SPEED    = 55,    -- steady upward drift, px/s
    KICK          = 70,    -- extra upward pop that decays over the first ~0.5s, px
    SPREAD        = 150,   -- horizontal spawn spread, px
    POP_TIME      = 0.28,  -- impact scale-in duration
    HOT_TIME      = 0.18,  -- text starts white-hot and cools to its colour over this long
    COUNT_UP_TIME = 0.35,  -- the number rolls from 0 to its value over this long
    RING_TIME     = 0.55,  -- shockwave ring lifetime
    FLASH_TIME    = 0.30,  -- screen flash lifetime
    SHAKE_TIME    = 0.40,  -- overlay shake lifetime
    GRAVITY       = 260,   -- particle gravity, px/s^2
    MAX_FLOATERS  = 20,
    COMBO_WINDOW  = 3.0,   -- seconds between crits that still count as one streak
    -- Damage tiers, checked top-down against dmg / cfg.tierScale.
    TIERS = {
        { min = 8000, size = 48, label = 'MASSIVE', particles = 22, rings = 2, rainbow = true, flash = true, shake = true },
        { min = 2000, size = 38, label = 'HUGE',    particles = 14, rings = 1 },
        { min = 500,  size = 30, label = 'BIG',     particles = 8 },
        { min = 0,    size = 24 },
    },
    MILESTONES = { [5] = 'RAMPAGE!', [10] = 'UNSTOPPABLE!', [20] = 'GODLIKE!' },
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
        combo     = { 1.0, 0.80, 0.25 },
        record    = { 1.0, 1.0,  1.0  },
    },
}

-- Session state (not persisted): combo streak, best hits, screen effects.
local state = {
    combo      = { count = 0, lastAt = 0, bestStreak = 0 },
    best       = { dmg = 0, heal = 0 },
    flash      = nil,   -- { at, r, g, b }
    shake      = nil,   -- { at, power }
    spawnIndex = 0,
}

local OUTLINE_DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

-- ----------------------------------------------------------------------------
-- Small math / formatting helpers
-- ----------------------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Overshoots past 1.0 and settles back: gives the impact pop its snap.
local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    t = t - 1
    return 1 + c3 * t * t * t + c1 * t * t
end

local function easeOutCubic(t)
    t = 1 - t
    return 1 - t * t * t
end

-- 1234567 -> "1,234,567"
local function fmtNum(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

local function tierFor(dmg)
    local scaled = (dmg or 0) / math.max(0.05, cfg.tierScale)
    for i, tier in ipairs(FX.TIERS) do
        if scaled >= tier.min then return i end
    end
    return #FX.TIERS
end

local function floatersEnabled()
    local ctrl = core and core.ctrl
    -- Honors the "Critical Hit Floating Text" checkbox in Settings -> Visual.
    return not (ctrl and ctrl.show_crit_floaters == false)
end

local function col32(r, g, b, a)
    r, g, b, a = clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), clamp(a, 0, 1)
    if IM_COL32 then
        return IM_COL32(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), math.floor(a * 255))
    end
    local ImGui = core and core.ImGui
    if ImGui and ImGui.GetColorU32 then
        return ImGui.GetColorU32(r, g, b, a)
    end
    -- Packed ABGR, the ImU32 layout IM_COL32 produces.
    return math.floor(a * 255) * 16777216 + math.floor(b * 255) * 65536 + math.floor(g * 255) * 256 + math.floor(r * 255)
end

-- ----------------------------------------------------------------------------
-- Spawning
-- ----------------------------------------------------------------------------
local function makeParticles(count, c)
    local list = {}
    for _ = 1, count do
        table.insert(list, {
            ang   = math.random() * math.pi * 2,
            speed = (80 + math.random() * 180) * (0.6 + 0.4 * cfg.intensity),
            size  = 1.5 + math.random() * 2.5,
            life  = 0.45 + math.random() * 0.55,
            -- Some sparks are white-hot, the rest carry the hit colour.
            hot   = (math.random() < 0.35),
            r = c[1], g = c[2], b = c[3],
        })
    end
    return list
end

-- opts: tier (force a tier index), size (fixed font size), xOff / yOff, delay,
--       callout (no number, no combo/record/tier bookkeeping), kind
local function spawnFloater(label, critType, dmg, opts)
    if not floatersEnabled() then return end
    opts = opts or {}
    dmg = dmg or 0
    local now = os.clock() + (opts.delay or 0)
    local kind = opts.kind or ((critType == 'holy') and 'heal' or 'dmg')
    local tier = opts.tier or tierFor(dmg)
    local tierDef = FX.TIERS[tier] or FX.TIERS[#FX.TIERS]
    local c = FX.COLORS[critType] or FX.COLORS.crit

    state.spawnIndex = state.spawnIndex + 1
    local xOff = opts.xOff
    if xOff == nil then
        -- Alternate sides so back-to-back hits fan out instead of stacking.
        local side = (state.spawnIndex % 2 == 0) and 1 or -1
        xOff = side * math.random(20, math.floor(FX.SPREAD / 2))
    end

    local f = {
        label     = label,
        type      = critType or 'crit',
        dmg       = dmg,
        kind      = kind,
        tier      = tier,
        size      = opts.size,
        callout   = opts.callout == true,
        spawnedAt = now,
        xOff      = xOff,
        yOff      = opts.yOff or 0,
        kick      = FX.KICK * (0.7 + math.random() * 0.6),
        wobbleAmp = 4 + math.random() * 8,
        seed      = math.random(1000),
        particles = nil,
    }

    if not f.callout then
        local particleCount = math.floor((tierDef.particles or 0) * cfg.intensity + 0.5)
        if particleCount > 0 then f.particles = makeParticles(particleCount, c) end

        if tierDef.flash and cfg.screenFlash and cfg.intensity > 0 then
            state.flash = { at = now, r = c[1], g = c[2], b = c[3] }
        end
        if tierDef.shake and cfg.screenShake and cfg.intensity > 0 then
            state.shake = { at = now, power = 14 * cfg.intensity }
        end

        -- Session record per kind (damage vs heal); the first hit sets the bar quietly.
        if dmg > 0 then
            local prev = state.best[kind] or 0
            if dmg > prev then
                state.best[kind] = dmg
                if prev > 0 then
                    spawnFloater('NEW RECORD!', 'record', 0,
                        { callout = true, size = 20, xOff = xOff, yOff = -46, delay = opts.delay })
                end
            end
        end

        -- Combo streak: any crit within the window extends it.
        if cfg.comboCounter then
            local combo = state.combo
            if combo.count > 0 and (now - combo.lastAt) <= FX.COMBO_WINDOW then
                combo.count = combo.count + 1
            else
                combo.count = 1
            end
            combo.lastAt = now
            if combo.count > combo.bestStreak then combo.bestStreak = combo.count end
            local shout = FX.MILESTONES[combo.count]
            if shout then
                spawnFloater(shout, 'combo', 0,
                    { callout = true, size = 34 + combo.count, xOff = 0, yOff = 40, delay = opts.delay })
            end
        end
    end

    table.insert(floaters, f)
    while #floaters > FX.MAX_FLOATERS do
        table.remove(floaters, 1)
    end
    return f
end

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------
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
        spawnFloater('CRITICAL!', 'crit', tonumber(dmgStr) or 0)
    end)

    reg('TacCripBlow', '#*#You land a Crippling Blow!#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('CRIPPLING BLOW!', 'crip', tonumber(dmgStr) or 0)
    end)

    reg('TacDeadlyStrike', '#*#You score a Deadly Strike!#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('DEADLY STRIKE!', 'deadly', tonumber(dmgStr) or 0)
    end)

    reg('TacSlayUndead', '#*#You slay#*#undead!#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('SLAY UNDEAD!', 'slay', tonumber(dmgStr) or 0)
    end)

    reg('TacFinishBlow', '#*#You land a Finishing Blow!#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('FINISHING BLOW!', 'finish', tonumber(dmgStr) or 0)
    end)

    -- Instant kills carry no number, so they get the top tier outright.
    reg('TacAssassinate', '#*#You assassinate#*#', function()
        spawnFloater('ASSASSINATE!', 'assassin', 0, { tier = 1 })
    end)

    reg('TacHeadshot', '#*#You headshotted#*#', function()
        spawnFloater('HEADSHOT!', 'headshot', 0, { tier = 1 })
    end)

    reg('TacFlurry', '#*#You flurry#*#', function()
        spawnFloater('FLURRY!', 'flurry', 0)
    end)

    reg('TacSpellCrit', '#*#critical blast!#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('SPELL CRIT!', 'spellcrit', tonumber(dmgStr) or 0)
    end)

    reg('TacHealCrit', '#*#critical heal#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('CRIT HEAL!', 'holy', tonumber(dmgStr) or 0)
    end)

    reg('TacDotCrit', '#*#critical dot#*#(#1#)#*#', function(_, dmgStr)
        spawnFloater('CRIT DOT!', 'spellcrit', tonumber(dmgStr) or 0)
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
    state.flash = nil
    state.shake = nil
    state.combo.count = 0
end

function plugin.onTick()
    local now = os.clock()
    local i = 1
    while i <= #floaters do
        if (now - floaters[i].spawnedAt) >= FX.LIFETIME then
            table.remove(floaters, i)
        else
            i = i + 1
        end
    end
    local combo = state.combo
    if combo.count > 0 and (now - combo.lastAt) > FX.COMBO_WINDOW then
        combo.count = 0
    end
end

function plugin.onSaveSettings()
    return {
        textScale    = cfg.textScale,
        intensity    = cfg.intensity,
        tierScale    = cfg.tierScale,
        comboCounter = cfg.comboCounter,
        screenFlash  = cfg.screenFlash,
        screenShake  = cfg.screenShake,
    }
end

function plugin.onLoadSettings(s)
    if type(s) ~= 'table' then return end
    if type(s.textScale) == 'number' then cfg.textScale = clamp(s.textScale, 0.5, 2.0) end
    if type(s.intensity) == 'number' then cfg.intensity = clamp(s.intensity, 0.0, 2.0) end
    if type(s.tierScale) == 'number' then cfg.tierScale = clamp(s.tierScale, 0.05, 5.0) end
    if s.comboCounter ~= nil then cfg.comboCounter = (s.comboCounter == true) end
    if s.screenFlash ~= nil then cfg.screenFlash = (s.screenFlash == true) end
    if s.screenShake ~= nil then cfg.screenShake = (s.screenShake == true) end
end

-- ----------------------------------------------------------------------------
-- Rendering
-- ----------------------------------------------------------------------------
local function textWidth(ImGui, text, fontSize)
    local base = 13
    local okF, fs = pcall(ImGui.GetFontSize)
    if okF and type(fs) == 'number' and fs > 0 then base = fs end
    local ok, w = pcall(ImGui.CalcTextSize, text)
    if ok and type(w) == 'number' and w > 0 then return w * (fontSize / base) end
    return #text * fontSize * 0.55
end

-- Centred text with an 8-direction dark stroke and an optional coloured glow.
local function drawText(dl, ImGui, text, cx, cy, fontSize, r, g, b, alpha, glow)
    local w = textWidth(ImGui, text, fontSize)
    local x, y = cx - w / 2, cy - fontSize / 2
    local o = math.max(1, fontSize / 14)
    if glow then
        local gc = col32(r, g, b, alpha * 0.28)
        local go = o * 2.5
        dl:AddText(nil, fontSize, ImVec2(x - go, y), gc, text)
        dl:AddText(nil, fontSize, ImVec2(x + go, y), gc, text)
        dl:AddText(nil, fontSize, ImVec2(x, y - go), gc, text)
        dl:AddText(nil, fontSize, ImVec2(x, y + go), gc, text)
    end
    local oc = col32(0, 0, 0, alpha * 0.9)
    for _, d in ipairs(OUTLINE_DIRS) do
        dl:AddText(nil, fontSize, ImVec2(x + d[1] * o, y + d[2] * o), oc, text)
    end
    dl:AddText(nil, fontSize, ImVec2(x, y), col32(r, g, b, alpha), text)
end

local function drawFloater(dl, ImGui, f, ax, ay, now)
    local age = now - f.spawnedAt
    if age < 0 or age >= FX.LIFETIME then return end
    local t = age / FX.LIFETIME
    local tierDef = FX.TIERS[f.tier] or FX.TIERS[#FX.TIERS]

    -- Motion: fast upward kick that decays into a steady drift, gentle sway.
    local kick = f.kick * (1 - math.exp(-6 * age))
    local wobble = math.sin(age * 3.5 + f.seed) * f.wobbleAmp
    local px = ax + f.xOff + wobble
    local py = ay + f.yOff - age * FX.RISE_SPEED - kick

    local alpha
    if t < 0.06 then
        alpha = t / 0.06
    elseif t > 0.7 then
        alpha = 1.0 - ((t - 0.7) / 0.3)
    else
        alpha = 1.0
    end
    alpha = clamp(alpha, 0, 1)

    -- Impact pop: slam in oversized and snap down with an overshoot.
    local scale
    if age < FX.POP_TIME then
        scale = lerp(2.6, 1.0, easeOutBack(age / FX.POP_TIME))
    else
        scale = 1.0 + 0.04 * math.sin(age * 5 + f.seed)
    end
    local fontSize = (f.size or tierDef.size) * scale * cfg.textScale

    -- Colour: white-hot on impact cooling to the hit colour, with a soft pulse.
    local c = FX.COLORS[f.type] or FX.COLORS.crit
    local r, g, b = c[1], c[2], c[3]
    if tierDef.rainbow and not f.callout then
        local hue = (age * 2.5 + f.seed * 0.01) % 1.0
        r = 0.5 + 0.5 * math.sin(hue * 6.28)
        g = 0.5 + 0.5 * math.sin(hue * 6.28 + 2.09)
        b = 0.5 + 0.5 * math.sin(hue * 6.28 + 4.19)
    end
    local pulse = 0.88 + 0.12 * math.sin(age * 8 + f.seed)
    r, g, b = r * pulse, g * pulse, b * pulse
    local hot = clamp(1 - age / FX.HOT_TIME, 0, 1)
    r, g, b = lerp(r, 1, hot), lerp(g, 1, hot), lerp(b, 1, hot)

    -- Sparks burst from the spawn point and fall under gravity.
    if f.particles then
        local ox, oy = ax + f.xOff, ay + f.yOff
        for _, p in ipairs(f.particles) do
            if age < p.life then
                local k = age / p.life
                local sx = ox + math.cos(p.ang) * p.speed * age
                local sy = oy + math.sin(p.ang) * p.speed * age + 0.5 * FX.GRAVITY * age * age
                local pa = alpha * (1 - k) * (1 - k)
                local pc = p.hot and col32(1, 1, 0.85, pa) or col32(p.r, p.g, p.b, pa)
                dl:AddCircleFilled(ImVec2(sx, sy), p.size * (1 - k * 0.6), pc, 6)
            end
        end
    end

    -- Shockwave rings expand out of the impact point.
    local rings = (not f.callout) and (tierDef.rings or 0) or 0
    for ri = 1, rings do
        local ra = age - (ri - 1) * 0.12
        if ra > 0 and ra < FX.RING_TIME then
            local k = ra / FX.RING_TIME
            local radius = (12 + 150 * easeOutCubic(k)) * (0.6 + 0.4 * cfg.intensity)
            local thick = 1 + 5 * (1 - k)
            dl:AddCircle(ImVec2(ax + f.xOff, ay + f.yOff), radius, col32(c[1], c[2], c[3], alpha * 0.85 * (1 - k)), 0, thick)
        end
    end

    -- The number rolls up from zero over the first third of a second.
    local text = f.label
    if f.dmg > 0 then
        local shown = f.dmg
        if age < FX.COUNT_UP_TIME then
            shown = f.dmg * easeOutCubic(age / FX.COUNT_UP_TIME)
        end
        text = f.label .. ' ' .. fmtNum(shown)
    end
    local glow = (not f.callout and (tierDef.rings or 0) > 0) or f.type == 'record'
    drawText(dl, ImGui, text, px, py, fontSize, r, g, b, alpha, glow)

    -- Tier stamp above the number: "HUGE HIT" / "BIG HEAL".
    if tierDef.label and not f.callout then
        local stamp = tierDef.label .. ((f.kind == 'heal') and ' HEAL' or ' HIT')
        drawText(dl, ImGui, stamp, px, py - fontSize * 0.78, fontSize * 0.45, 1, 1, 1, alpha * 0.95, false)
    end
end

local function drawCombo(dl, ImGui, ax, ay, now)
    local combo = state.combo
    if not cfg.comboCounter or combo.count < 2 then return end
    local since = now - combo.lastAt
    if since < 0 or since >= FX.COMBO_WINDOW then return end

    local remain = 1 - since / FX.COMBO_WINDOW
    local alpha = (since > FX.COMBO_WINDOW - 0.5) and ((FX.COMBO_WINDOW - since) / 0.5) or 1.0
    local bump = clamp(1 - since / 0.25, 0, 1)
    local fontSize = (22 + math.min(combo.count, 25) * 1.2) * (1 + 0.6 * bump) * cfg.textScale

    local r, g, b
    if combo.count >= 20 then
        local hue = (now * 2) % 1.0
        r = 0.5 + 0.5 * math.sin(hue * 6.28)
        g = 0.5 + 0.5 * math.sin(hue * 6.28 + 2.09)
        b = 0.5 + 0.5 * math.sin(hue * 6.28 + 4.19)
    elseif combo.count >= 10 then
        r, g, b = 1.0, 0.25, 0.15
    elseif combo.count >= 5 then
        r, g, b = 1.0, 0.55, 0.10
    else
        r, g, b = 1.0, 0.85, 0.25
    end

    local cy = ay + 80
    drawText(dl, ImGui, string.format('x%d COMBO', combo.count), ax, cy, fontSize, r, g, b, alpha, combo.count >= 10)

    -- Thin timer bar shows how long the streak has left.
    local barW, barH = 120 * cfg.textScale, 4
    local x0, y0 = ax - barW / 2, cy + fontSize * 0.6
    dl:AddRectFilled(ImVec2(x0, y0), ImVec2(x0 + barW, y0 + barH), col32(0, 0, 0, alpha * 0.6))
    dl:AddRectFilled(ImVec2(x0, y0), ImVec2(x0 + barW * remain, y0 + barH), col32(r, g, b, alpha * 0.9))
end

function plugin.onDrawUI()
    if not core or not core.ImGui or not floatersEnabled() then return end
    local now = os.clock()
    local comboLive = cfg.comboCounter and state.combo.count >= 2 and (now - state.combo.lastAt) < FX.COMBO_WINDOW
    local flashLive = state.flash and (now - state.flash.at) < FX.FLASH_TIME
    if #floaters == 0 and not comboLive and not flashLive then return end
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
            -- Screen flash: a brief wash in the hit colour, on top of nothing else.
            if flashLive then
                local k = (now - state.flash.at) / FX.FLASH_TIME
                local fa = 0.22 * (1 - k) * clamp(cfg.intensity, 0, 1)
                pcall(function()
                    dl:AddRectFilled(ImVec2(0, 0), ImVec2(screenW, screenH), col32(state.flash.r, state.flash.g, state.flash.b, fa))
                end)
            end

            -- Overlay shake: jolts the anchor everything hangs off.
            local anchorX = screenW * 0.5
            local anchorY = screenH * 0.42
            if state.shake then
                local sa = now - state.shake.at
                if sa >= 0 and sa < FX.SHAKE_TIME then
                    local decay = (1 - sa / FX.SHAKE_TIME) ^ 2
                    anchorX = anchorX + state.shake.power * decay * math.sin(sa * 95)
                    anchorY = anchorY + state.shake.power * decay * math.cos(sa * 77)
                else
                    state.shake = nil
                end
            end

            for _, f in ipairs(floaters) do
                pcall(drawFloater, dl, ImGui, f, anchorX, anchorY, now)
            end
            pcall(drawCombo, dl, ImGui, anchorX, anchorY, now)
        end
    end
    ImGui.End()
end

-- ----------------------------------------------------------------------------
-- Settings panel
-- ----------------------------------------------------------------------------
local function saveCfg()
    if core and core.saveLoadout then core.saveLoadout(true) end
end

function plugin.onDrawSettings()
    if not core or not core.ImGui then return end
    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }

    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Floating Text Configuration:')
    ImGui.Text(string.format('Lifetime: %.1fs | Max Concurrent: %d | Combo Window: %.1fs',
        FX.LIFETIME, FX.MAX_FLOATERS, FX.COMBO_WINDOW))
    if core.ctrl then
        local cur = (core.ctrl.show_crit_floaters ~= false)
        local val = ImGui.Checkbox('Show Critical Hit Floating Text##fdEnabled', cur)
        if val ~= cur then
            core.ctrl.show_crit_floaters = val
            saveCfg()
        end
    end

    ImGui.PushItemWidth(220)
    local v = ImGui.SliderFloat('Text Scale##fdTextScale', cfg.textScale, 0.5, 2.0, '%.2fx')
    if type(v) == 'number' and v ~= cfg.textScale then cfg.textScale = clamp(v, 0.5, 2.0); saveCfg() end
    v = ImGui.SliderFloat('Effects Intensity##fdIntensity', cfg.intensity, 0.0, 2.0, '%.2fx')
    if type(v) == 'number' and v ~= cfg.intensity then cfg.intensity = clamp(v, 0.0, 2.0); saveCfg() end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Scales particle bursts, shockwave rings, screen flash and shake. 0 turns them all off.')
    end
    v = ImGui.SliderFloat('Damage Tier Scale##fdTierScale', cfg.tierScale, 0.05, 5.0, '%.2fx')
    if type(v) == 'number' and v ~= cfg.tierScale then cfg.tierScale = clamp(v, 0.05, 5.0); saveCfg() end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Lower this at low levels so your hits reach the BIG / HUGE / MASSIVE tiers.')
    end
    ImGui.PopItemWidth()
    ImGui.TextDisabled(string.format('Tiers: BIG >= %s | HUGE >= %s | MASSIVE >= %s',
        fmtNum(FX.TIERS[3].min * cfg.tierScale), fmtNum(FX.TIERS[2].min * cfg.tierScale), fmtNum(FX.TIERS[1].min * cfg.tierScale)))

    local cb = ImGui.Checkbox('Combo Counter##fdCombo', cfg.comboCounter)
    if cb ~= cfg.comboCounter then cfg.comboCounter = (cb == true); saveCfg() end
    ImGui.SameLine()
    cb = ImGui.Checkbox('Screen Flash##fdFlash', cfg.screenFlash)
    if cb ~= cfg.screenFlash then cfg.screenFlash = (cb == true); saveCfg() end
    ImGui.SameLine()
    cb = ImGui.Checkbox('Screen Shake##fdShake', cfg.screenShake)
    if cb ~= cfg.screenShake then cfg.screenShake = (cb == true); saveCfg() end

    ImGui.TextDisabled(string.format('Session best: crit %s | heal %s | streak x%d',
        fmtNum(state.best.dmg), fmtNum(state.best.heal), state.combo.bestStreak))

    ImGui.Spacing()
    local bw = 120
    if ImGui.Button('Test Crit##fdTestCrit', bw, 24) then
        spawnFloater('CRITICAL!', 'crit', 320)
    end
    ImGui.SameLine()
    if ImGui.Button('Test BIG##fdTestBig', bw, 24) then
        spawnFloater('CRIPPLING BLOW!', 'crip', 1450 * cfg.tierScale)
    end
    ImGui.SameLine()
    if ImGui.Button('Test HUGE##fdTestHuge', bw, 24) then
        spawnFloater('DEADLY STRIKE!', 'deadly', 3200 * cfg.tierScale)
    end
    ImGui.SameLine()
    if ImGui.Button('Test MASSIVE##fdTestMassive', bw, 24) then
        spawnFloater('SPELL CRIT!', 'spellcrit', 12450 * cfg.tierScale)
    end
    if ImGui.Button('Test Heal##fdTestHeal', bw, 24) then
        spawnFloater('CRIT HEAL!', 'holy', 2800 * cfg.tierScale)
    end
    ImGui.SameLine()
    if ImGui.Button('Test Combo x6##fdTestCombo', bw, 24) then
        local types = { 'crit', 'spellcrit', 'crip', 'crit', 'deadly', 'finish' }
        local labels = { 'CRITICAL!', 'SPELL CRIT!', 'CRIPPLING BLOW!', 'CRITICAL!', 'DEADLY STRIKE!', 'FINISHING BLOW!' }
        for i = 1, #types do
            spawnFloater(labels[i], types[i], math.random(150, 900) * cfg.tierScale, { delay = (i - 1) * 0.18 })
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Clear All##fdClear', bw, 24) then
        floaters = {}
        state.flash = nil
        state.shake = nil
        state.combo.count = 0
    end
end

return plugin
