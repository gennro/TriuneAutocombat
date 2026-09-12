---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_unitframes.lua — Triune Popout Unit Frames HUD Plugin
-- ============================================================================
-- An ultra-compact, fully responsive popout window that replaces default EQ
-- target, player, and pet windows. Features real-time Target + ToT with aggro
-- warnings, target buffs/debuffs with timers, player vitals (HP, Mana, End,
-- XP, AAXP), and multi-pet HP bars for the Gestalt Trio.
--
-- Vitals are snapshotted at most every 50ms into a cache shared by the fiber
-- (main loop) and the render pass; the render pass refreshes when the main
-- loop is blocked (casting, mq.delay) so the HUD never freezes mid-fight.
-- ============================================================================

local plugin = {
    id                 = 'hud_unitframes',
    name               = 'Unit Frames HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout HUD for Player, Target, and Pet vitals with responsive bars, ToT aggro tracking, and buff timers.',
    defaultEnabled     = true,
    tickInterval       = 0.05,       -- Fiber updates cached vitals every 50ms
    runOutOfCombatOnly = false,      -- Stays fully active during combat
    hasThread          = true,       -- Dedicated coroutine fiber
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Target & Player HUD', tooltip = 'Toggles the popout Target & Player HUD Unit Frames window.', flag = 'show_unit_frames', key = 'unit_frames', lockFlag = 'uf_lock', desc = 'Popout Target, Player & Pet vitals', headerButton = true, order = 60 },
}

local core = nil
local snap = nil
local lastRefreshAt = 0
local REFRESH_INTERVAL = 0.05 -- seconds; matches tickInterval

function plugin.onInit(coreApi)
    core = coreApi
    if core and core.ctrl then
        -- Window visibility is the user's saved preference (header button, window
        -- manager, /ac commands) - never force it open on load.
        if core.ctrl.show_unit_frames == nil then core.ctrl.show_unit_frames = false end
        if core.ctrl.uf_lock == nil then core.ctrl.uf_lock = false end
        if core.ctrl.uf_alpha == nil then core.ctrl.uf_alpha = 0.85 end
        if core.ctrl.uf_bar_height == nil then core.ctrl.uf_bar_height = 14 end
        if core.ctrl.uf_buff_max == nil then core.ctrl.uf_buff_max = 30 end
        if core.ctrl.uf_hide_empty_pets == nil then core.ctrl.uf_hide_empty_pets = true end
        if core.ctrl.uf_show_endurance == nil then core.ctrl.uf_show_endurance = true end
        if core.ctrl.uf_show_xp == nil then core.ctrl.uf_show_xp = true end
    end
end

function plugin.onDestroy()
    snap = nil
    lastRefreshAt = 0
end

local function drawProgressBar(fraction, w, h, text, r, g, b, a)
    if core and core.drawStatusProgressBar then
        core.drawStatusProgressBar(fraction, w, h, text, r, g, b, a)
        return
    end
    if not core or not core.ImGui then return end
    local ImGui = core.ImGui
    local Col = ImGuiCol or _G.ImGuiCol or (core.mq and core.mq.imgui and core.mq.imgui.Col)
    local pCount = 0
    if Col and Col.PlotHistogram and r and g and b then
        if pcall(ImGui.PushStyleColor, Col.PlotHistogram, r, g, b, a or 1.0) then
            pCount = pCount + 1
        end
    end
    local clamped = math.max(0.0, math.min(1.0, fraction or 0.0))
    ImGui.ProgressBar(clamped, w or -1, h or 16, text or '')
    if pCount > 0 then
        pcall(ImGui.PopStyleColor, pCount)
    end
end

local function getConRgb(conName)
    if core and core.getConColorRgb then
        return core.getConColorRgb(conName)
    end
    local c = tostring(conName or ''):upper()
    if c == 'GREY' or c == 'GRAY' then return { 0.60, 0.60, 0.60, 1.0 }
    elseif c == 'GREEN' then return { 0.25, 0.90, 0.35, 1.0 }
    elseif c == 'LIGHT BLUE' or c == 'LIGHTBLUE' then return { 0.35, 0.75, 1.0, 1.0 }
    elseif c == 'BLUE' then return { 0.20, 0.50, 1.0, 1.0 }
    elseif c == 'WHITE' then return { 0.95, 0.95, 0.95, 1.0 }
    elseif c == 'YELLOW' then return { 1.0, 0.85, 0.20, 1.0 }
    elseif c == 'RED' then return { 1.0, 0.28, 0.28, 1.0 }
    end
    return { 0.75, 0.75, 0.75, 1.0 }
end

-- Snapshot every TLO the window needs. Called from both the fiber (main loop)
-- and the render pass; the throttle below makes whichever runs first do the
-- work so the HUD stays live while combatTick / mq.delay block the main loop
-- without hammering TLOs at full frame rate.
local function refreshVitals(force)
    if not core or not core.mq or not core.ctrl then return end
    local ctrl = core.ctrl
    if not ctrl.show_unit_frames then
        snap = nil
        return
    end
    local now = os.clock()
    if not force and (now - lastRefreshAt) < REFRESH_INTERVAL then return end
    lastRefreshAt = now

    local mq = core.mq
    local s = snap or {}

    -- 1. Auto-Attack state
    s.isAtk = false
    pcall(function() s.isAtk = mq.TLO.Me.Combat() or false end)

    -- 2. Target Vitals
    s.hasTarget = false
    pcall(function()
        local tId = mq.TLO.Target.ID()
        if tId and tId > 0 then
            s.hasTarget = true
            s.tId = tId
            s.tName = mq.TLO.Target.CleanName() or 'Unknown'
            s.tLvl = mq.TLO.Target.Level() or 0
            s.tClass = mq.TLO.Target.Class.ShortName() or '?'
            s.tCon = mq.TLO.Target.ConColor() or 'White'
            s.tHpPct = mq.TLO.Target.PctHPs() or 0
            s.tCurHp = mq.TLO.Target.CurrentHPs() or 0
            s.tMaxHp = mq.TLO.Target.MaxHPs() or 0
            s.tDist = mq.TLO.Target.Distance() or 0
            s.tLoS = mq.TLO.Target.LineOfSight() or false
        end
    end)

    -- Target of Target (ToT)
    if s.hasTarget and core.resolveTargetOfTarget then
        s.tTotName, s.tTotId, s.tTotHpPct, s.myPctAggro = core.resolveTargetOfTarget(s.tId)
    else
        s.tTotName, s.tTotId, s.tTotHpPct, s.myPctAggro = nil, nil, nil, nil
    end

    -- Target Buffs
    s.targetBuffs = {}
    if s.hasTarget then
        local tbc = 0
        pcall(function() tbc = mq.TLO.Target.BuffCount() or 0 end)
        local maxB = math.min(tbc or 0, ctrl.uf_buff_max or 30)
        for b = 1, maxB do
            pcall(function()
                local tbObj = mq.TLO.Target.Buff(b)
                if tbObj and tbObj() then
                    local bName = (tbObj.Name and tbObj.Name()) or tbObj()
                    if bName and bName ~= '' and bName ~= 'NONE' then
                        local durSec = 0
                        local isBeneficial = false
                        if tbObj.Duration and tbObj.Duration.TotalSeconds then
                            durSec = tbObj.Duration.TotalSeconds() or 0
                        end
                        if tbObj.Spell and tbObj.Spell.Beneficial then
                            isBeneficial = tbObj.Spell.Beneficial() or false
                        end
                        table.insert(s.targetBuffs, {
                            slot = b,
                            name = bName,
                            duration = durSec,
                            beneficial = isBeneficial
                        })
                    end
                end
            end)
        end
    end

    -- 3. Player Vitals
    pcall(function()
        s.myHpPct = mq.TLO.Me.PctHPs() or 0
        s.myCurHp = mq.TLO.Me.CurrentHPs() or 0
        s.myMaxHp = mq.TLO.Me.MaxHPs() or 0
        s.myManaPct = mq.TLO.Me.PctMana() or 0
        s.myCurMana = mq.TLO.Me.CurrentMana() or 0
        s.myMaxMana = mq.TLO.Me.MaxMana() or 0
        s.myEndPct = mq.TLO.Me.PctEndurance() or 0
        s.myCurEnd = mq.TLO.Me.CurrentEndurance() or 0
        s.myMaxEnd = mq.TLO.Me.MaxEndurance() or 0
        s.myLvl = mq.TLO.Me.Level() or 1
        s.myExpPct = mq.TLO.Me.PctExp() or 0
        s.myAAExpPct = mq.TLO.Me.PctAAExp() or 0
        s.myBankedAA = mq.TLO.Me.AAPoints() or 0
        s.myName = mq.TLO.Me.CleanName() or ''
        s.myRawExp = mq.TLO.Me.Exp() or 0
        s.aaSpent = mq.TLO.Me.AAPointsAssigned() or 0
        s.aaTotal = mq.TLO.Me.AAPointsTotal() or 0
    end)

    -- 4. Multi-Pet Vitals
    s.activePets = {}
    local seenPetIds = {}
    if core.getMultiPetList and core.getPetSpawnInfo and core.isSpawnAlive then
        local petSlots, extraPets = core.getMultiPetList()
        for _, slot in ipairs(petSlots or {}) do
            if slot.petId and slot.petId > 0 and not seenPetIds[slot.petId] and core.isSpawnAlive(slot.petId) then
                seenPetIds[slot.petId] = true
                local info = core.getPetSpawnInfo(slot.petId)
                table.insert(s.activePets, { id = slot.petId, cls = slot.cls, slotNum = slot.slotNum, info = info })
            end
        end
        for _, extraPid in ipairs(extraPets or {}) do
            if extraPid and extraPid > 0 and not seenPetIds[extraPid] and core.isSpawnAlive(extraPid) then
                seenPetIds[extraPid] = true
                local info = core.getPetSpawnInfo(extraPid)
                table.insert(s.activePets, { id = extraPid, cls = 'Pet', slotNum = nil, info = info })
            end
        end
    end
    -- Me.Pet is always part of getMultiPetList (slot or extra), and the list is
    -- deduplicated by pet name, so it is not appended separately here.

    snap = s
end

-- Fiber Worker: keeps the snapshot warm from the main loop (throttled)
function plugin.onTick()
    refreshVitals(false)
end

-- Render settings dialog inside right-click popup
local function renderUfSettingsContent()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }

    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Target & Player HUD Settings')
    ImGui.Separator()

    local isWinOpen = (ctrl.show_unit_frames == true)
    local btnText = isWinOpen and 'HUD Window: Visible (Click to Hide)' or 'HUD Window: Hidden (Click to Show)'
    if ImGui.Button(btnText .. '##ufToggleWin', 250, 24) then
        ctrl.show_unit_frames = not isWinOpen
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.Spacing()

    local lockVal = ImGui.Checkbox('Lock Window Position & Size##ufLock', ctrl.uf_lock or false)
    if lockVal ~= (ctrl.uf_lock or false) then
        ctrl.uf_lock = lockVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local hidePetVal = ImGui.Checkbox('Auto-Hide Pet Section When No Pets##ufHidePet', ctrl.uf_hide_empty_pets ~= false)
    if hidePetVal ~= (ctrl.uf_hide_empty_pets ~= false) then
        ctrl.uf_hide_empty_pets = hidePetVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local showEndVal = ImGui.Checkbox('Show Endurance Bar##ufEnd', ctrl.uf_show_endurance ~= false)
    if showEndVal ~= (ctrl.uf_show_endurance ~= false) then
        ctrl.uf_show_endurance = showEndVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local showXpVal = ImGui.Checkbox('Show XP & AAXP Bars##ufXp', ctrl.uf_show_xp ~= false)
    if showXpVal ~= (ctrl.uf_show_xp ~= false) then
        ctrl.uf_show_xp = showXpVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(120)
    local newAlpha = ImGui.SliderFloat('Opacity##ufAlpha', ctrl.uf_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.uf_alpha or 0.85) then
        ctrl.uf_alpha = newAlpha
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(120)
    local newH = ImGui.SliderInt('Bar Height##ufHeight', ctrl.uf_bar_height or 14, 10, 24)
    if newH ~= (ctrl.uf_bar_height or 14) then
        ctrl.uf_bar_height = newH
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(120)
    local newMaxB = ImGui.SliderInt('Max Buffs##ufMaxB', ctrl.uf_buff_max or 30, 5, 50)
    if newMaxB ~= (ctrl.uf_buff_max or 30) then
        ctrl.uf_buff_max = newMaxB
        if core.saveLoadout then core.saveLoadout(true) end
    end
end

-- Render Function: Reads from cached snap with near-zero overhead
function plugin.onDrawUI()
    if not core or not core.ImGui or not core.ctrl then return end
    local ctrl = core.ctrl
    if not ctrl.show_unit_frames then return end

    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    local ARC = colors.ARC or { 0.30, 0.70, 1.0, 1 }
    local GOOD = colors.GOOD or { 0.37, 0.88, 0.64, 1 }
    local WARN = colors.WARN or { 1.0, 0.72, 0.30, 1 }
    local MUTED = colors.MUTED or { 0.49, 0.56, 0.65, 1 }

    if core.pushTheme then core.pushTheme() end

    if ctrl.uf_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.uf_alpha)
    end
    ImGui.SetNextWindowSize(320, 360, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.uf_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 4, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 2, 1)

    if core.preBeginWindow then core.preBeginWindow('unit_frames') end

    local show
    local winTitle = 'Triune Target & Player v' .. (core.VERSION or '2.15') .. '###triuneUnitFrames'
    ctrl.show_unit_frames, show = ImGui.Begin(winTitle, ctrl.show_unit_frames, winFlags)

    if not ctrl.show_unit_frames then
        ImGui.End()
        ImGui.PopStyleVar(3)
        if core.popTheme then core.popTheme() end
        if core.saveLoadout then core.saveLoadout(true) end
        return
    end

    if show then
        if core.postBeginWindow then core.postBeginWindow('unit_frames') end
        refreshVitals(false)
        if snap then
            local availW = ImGui.GetContentRegionAvail()
            local barH = ctrl.uf_bar_height or 14

        -- Context Menu
        if ImGui.BeginPopupContextWindow('##ufContextMenu') then
            renderUfSettingsContent()
            ImGui.EndPopup()
        end

        local isAtk = snap.isAtk or false

        -- 1. Target & ToT
        if snap.hasTarget and snap.tName then
            local conCol = getConRgb(snap.tCon)
            ImGui.TextColored(conCol[1], conCol[2], conCol[3], conCol[4], string.format('[Lvl %d %s] %s', snap.tLvl or 0, snap.tClass or '?', snap.tName))
            ImGui.SameLine()
            ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('%.0fft', snap.tDist or 0))
            ImGui.SameLine()
            if snap.tLoS then
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'LoS')
            else
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'No LoS')
            end

            -- Target Health Bar
            local tr, tg, tb = 0.25, 0.80, 0.35
            if (snap.tHpPct or 0) <= 20 then
                tr, tg, tb = 0.90, 0.20, 0.20
            elseif (snap.tHpPct or 0) <= 50 then
                tr, tg, tb = 0.95, 0.75, 0.20
            end

            if isAtk then
                local pulse = 0.5 + 0.5 * math.sin(os.clock() * 10)
                tr = 0.95 * pulse + tr * (1.0 - pulse)
                tg = 0.15 * pulse + tg * (1.0 - pulse)
                tb = 0.15 * pulse + tb * (1.0 - pulse)
            end

            local hpStr = string.format('Target: %d%% (%s / %s)', snap.tHpPct or 0,
                (snap.tCurHp and snap.tCurHp > 0) and tostring(snap.tCurHp) or '?',
                (snap.tMaxHp and snap.tMaxHp > 0) and tostring(snap.tMaxHp) or '?')
            drawProgressBar((snap.tHpPct or 0) / 100.0, -1, barH, hpStr, tr, tg, tb, 1.0)

            if isAtk then
                pcall(function()
                    local mnX, mnY = ImGui.GetItemRectMin()
                    local mxX, mxY = ImGui.GetItemRectMax()
                    local dl = ImGui.GetWindowDrawList()
                    if dl and mnX and mxX then
                        local ImVec2Type = _G.ImVec2 or (core and core.ImGui and core.ImGui.ImVec2) or ImVec2
                        if ImVec2Type then
                            local pulseA = 0.45 + 0.55 * math.sin(os.clock() * 10)
                            local borderCol = ImGui.GetColorU32(1.0, 0.15, 0.15, pulseA)
                            dl:AddRect(ImVec2Type(mnX - 1, mnY - 1), ImVec2Type(mxX + 1, mxY + 1), borderCol, 3.0, 0, 2.0)
                        end
                    end
                end)
            end

            -- ToT
            if snap.tTotName and snap.tTotName ~= 'None' and snap.tTotName ~= '' then
                local isMe = (snap.myName and snap.tTotName == snap.myName)
                if isMe then
                    ImGui.TextColored(1.0, 0.30, 0.30, 1.0, string.format('ToT: >> YOU << (Holding Aggro: %d%%)', snap.myPctAggro or 100))
                else
                    local Col = ImGuiCol or _G.ImGuiCol or (core.mq and core.mq.imgui and core.mq.imgui.Col)
                    local pCols = 0
                    if Col then
                        if pcall(ImGui.PushStyleColor, Col.Button, 0.15, 0.25, 0.18, 0.60) then pCols = pCols + 1 end
                        if pcall(ImGui.PushStyleColor, Col.Text, 0.35, 0.90, 0.45, 1.0) then pCols = pCols + 1 end
                    end
                    if ImGui.SmallButton(string.format('ToT: %s##totBtn', snap.tTotName)) then
                        if snap.tTotId and snap.tTotId > 0 then
                            core.mq.cmdf('/target id %d', snap.tTotId)
                        elseif snap.tTotName then
                            core.mq.cmdf('/target %s', snap.tTotName)
                        end
                    end
                    if pCols > 0 then pcall(ImGui.PopStyleColor, pCols) end
                    if ImGui.IsItemHovered() and core.setTooltip then
                        core.setTooltip(string.format('Target of Target: %s\nID: %d\nHP: %d%%\nClick to target',
                            snap.tTotName, snap.tTotId or 0, snap.tTotHpPct or 0))
                    end
                    if snap.myPctAggro and snap.myPctAggro > 0 then
                        ImGui.SameLine()
                        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('(Your Aggro: %d%%)', snap.myPctAggro))
                    end
                end
                if snap.tTotHpPct and snap.tTotHpPct > 0 then
                    local totr, totg, totb = 0.25, 0.75, 0.85
                    if snap.tTotHpPct <= 25 then
                        totr, totg, totb = 0.90, 0.20, 0.20
                    elseif snap.tTotHpPct <= 50 then
                        totr, totg, totb = 0.95, 0.75, 0.20
                    end
                    local totBarStr = string.format('%s HP: %d%%', isMe and 'YOU' or snap.tTotName, snap.tTotHpPct)
                    drawProgressBar(snap.tTotHpPct / 100.0, -1, math.max(10, barH - 3), totBarStr, totr, totg, totb, 1.0)
                    if ImGui.IsItemClicked() then
                        if snap.tTotId and snap.tTotId > 0 then
                            core.mq.cmdf('/target id %d', snap.tTotId)
                        elseif snap.tTotName then
                            core.mq.cmdf('/target %s', snap.tTotName)
                        end
                    end
                    if ImGui.IsItemHovered() and core.setTooltip then
                        core.setTooltip('%s', string.format('Click bar to target %s\nHP: %d%%', snap.tTotName, snap.tTotHpPct))
                    end
                end
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'ToT: None')
            end

            -- Target Buffs
            local targetBuffs = snap.targetBuffs or {}
            if #targetBuffs > 0 then
                ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format('Target Buffs (%d):', #targetBuffs))
                local curLineW = 0
                for _, b in ipairs(targetBuffs) do
                    local durStr = ''
                    if b.duration and b.duration > 0 then
                        if b.duration >= 3600 then
                            durStr = string.format(' %dh', math.floor(b.duration / 3600))
                        elseif b.duration >= 60 then
                            durStr = string.format(' %dm', math.floor(b.duration / 60))
                        else
                            durStr = string.format(' %ds', math.floor(b.duration))
                        end
                    end
                    local chipLabel = b.name .. durStr
                    local itemW = ImGui.CalcTextSize(chipLabel) + 10
                    if curLineW > 0 and (curLineW + itemW > availW) then
                        curLineW = 0
                    elseif curLineW > 0 then
                        ImGui.SameLine()
                    end

                    local Col = ImGuiCol or _G.ImGuiCol or (core.mq and core.mq.imgui and core.mq.imgui.Col)
                    local pushedCols = 0
                    if Col then
                        if b.beneficial then
                            if pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.35, 0.22, 0.75) then pushedCols = pushedCols + 1 end
                            if pcall(ImGui.PushStyleColor, Col.Text, 0.65, 0.95, 0.65, 1.0) then pushedCols = pushedCols + 1 end
                        else
                            if pcall(ImGui.PushStyleColor, Col.Button, 0.45, 0.15, 0.15, 0.75) then pushedCols = pushedCols + 1 end
                            if pcall(ImGui.PushStyleColor, Col.Text, 1.0, 0.65, 0.65, 1.0) then pushedCols = pushedCols + 1 end
                        end
                    end
                    ImGui.SmallButton(chipLabel .. '##ufTb' .. b.slot)
                    if pushedCols > 0 then
                        pcall(ImGui.PopStyleColor, pushedCols)
                    end
                    if ImGui.IsItemHovered() and core.setTooltip then
                        core.setTooltip('%s', string.format('%s\nSlot: %d\nType: %s%s',
                            b.name, b.slot, b.beneficial and 'Beneficial (Buff)' or 'Detrimental (Debuff/DoT)',
                            b.duration > 0 and string.format('\nDuration: %d seconds', math.floor(b.duration)) or ''))
                    end
                    curLineW = curLineW + itemW + 4
                end
            else
                ImGui.TextDisabled('Target Buffs: None')
            end
        else
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Target: No Target Selected')
            drawProgressBar(0, -1, barH, 'No Target', 0.25, 0.25, 0.25, 0.5)
        end

        -- 2. Player Vitals
        ImGui.Separator()
        local pr, pg, pb = 0.25, 0.80, 0.35
        if (snap.myHpPct or 0) <= 25 then
            pr, pg, pb = 0.90, 0.20, 0.20
        elseif (snap.myHpPct or 0) <= 50 then
            pr, pg, pb = 0.95, 0.75, 0.20
        end
        local myHpStr = string.format('Player HP: %d%% (%d / %d)', snap.myHpPct or 0, snap.myCurHp or 0, snap.myMaxHp or 0)
        drawProgressBar((snap.myHpPct or 0) / 100.0, -1, barH, myHpStr, pr, pg, pb, 1.0)

        if (snap.myMaxMana or 0) > 0 then
            local manaStr = string.format('Mana: %d%% (%d / %d)', snap.myManaPct or 0, snap.myCurMana or 0, snap.myMaxMana or 0)
            drawProgressBar((snap.myManaPct or 0) / 100.0, -1, barH, manaStr, 0.25, 0.60, 0.95, 1.0)
        end

        if ctrl.uf_show_endurance ~= false and (snap.myMaxEnd or 0) > 0 then
            local endStr = string.format('End: %d%% (%d / %d)', snap.myEndPct or 0, snap.myCurEnd or 0, snap.myMaxEnd or 0)
            drawProgressBar((snap.myEndPct or 0) / 100.0, -1, barH, endStr, 0.95, 0.60, 0.25, 1.0)
        end

        if ctrl.uf_show_xp ~= false then
            local xpStr = string.format('XP (Lvl %d): %.2f%%', snap.myLvl or 1, snap.myExpPct or 0)
            drawProgressBar((snap.myExpPct or 0) / 100.0, -1, barH, xpStr, 0.85, 0.70, 0.20, 1.0)

            local aaxpStr = string.format('AAXP: %.2f%% (%d Banked)', snap.myAAExpPct or 0, snap.myBankedAA or 0)
            drawProgressBar((snap.myAAExpPct or 0) / 100.0, -1, barH, aaxpStr, 0.65, 0.35, 0.90, 1.0)
        end

        -- 3. Multi-Pet Vitals
        local activePets = snap.activePets or {}
        if #activePets > 0 then
            ImGui.Separator()
            for _, pData in ipairs(activePets) do
                local pInfo = pData.info or {}
                local pHp = pInfo.hpPct or 0
                local petR, petG, petB = 0.25, 0.80, 0.35
                if pHp <= 25 then
                    petR, petG, petB = 0.90, 0.20, 0.20
                elseif pHp <= 50 then
                    petR, petG, petB = 0.95, 0.75, 0.20
                end
                local pClsTag = (pData.cls and pData.cls ~= '' and pData.cls ~= 'Pet') and string.format('[%s] ', pData.cls) or ''
                local pTargetStr = (pInfo.targetName and pInfo.targetName ~= '' and pInfo.targetName ~= 'None') and (' -> ' .. pInfo.targetName) or ''
                local pBarStr = string.format('Pet %s%s: %d%%%s', pClsTag, pInfo.cleanName or 'Pet', pHp, pTargetStr)
                drawProgressBar(pHp / 100.0, -1, barH, pBarStr, petR, petG, petB, 1.0)
                if ImGui.IsItemHovered() and core.setTooltip then
                    core.setTooltip('%s', string.format('Pet: %s\nClass: %s\nLevel: %d\nHP: %d%%\nTarget: %s\nBuff Count: %d',
                        pInfo.cleanName or 'Pet', pData.cls or 'Pet', pInfo.level or 0, pHp, pInfo.targetName or 'None', #(pInfo.buffs or {})))
                end
            end
        elseif ctrl.uf_hide_empty_pets == false then
            ImGui.Separator()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'No active pets')
        end
        end
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    if core.popTheme then core.popTheme() end
end

function plugin.onDrawSettings()
    renderUfSettingsContent()
end

return plugin
