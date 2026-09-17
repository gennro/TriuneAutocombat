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
-- The heavier reads (target buffs, target-of-target, pet spawn info) run on
-- a separate, slower timer (SLOW_REFRESH_INTERVAL) and immediately when the
-- target changes.
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
    uses               = { parcels = 'Parcels waiting / over limit badge on the player section (click to Collect All at a parcel merchant)' },
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Target & Player HUD', tooltip = 'Toggles the popout Target & Player HUD Unit Frames window.', flag = 'show_unit_frames', key = 'unit_frames', lockFlag = 'uf_lock', desc = 'Popout Target, Player & Pet vitals', headerButton = true, order = 60 },
    -- Second window: the target section on its own, meant to be scaled up
    -- and parked where the current target is always in view. Addressed by
    -- the core as 'hud_unitframes:target_window'.
    windows            = {
        { key = 'target_window', name = 'Target Window', label = 'Target', tooltip = 'Toggles the popout Target window: the target frame on its own, sized to be seen across the screen.', flag = 'show_target_window', lockFlag = 'tw_lock', desc = 'Popout Target-only frame (target, ToT, buffs)', headerButton = false, order = 61 },
    },
}
local TARGET_WINDOW_ID = 'hud_unitframes:target_window'

local core = nil  ---@type table
local snap = nil
local lastRefreshAt = 0
local REFRESH_INTERVAL = 0.05 -- seconds; matches tickInterval (vitals)
local lastSlowRefreshAt = 0
local SLOW_REFRESH_INTERVAL = 0.33 -- seconds; target buffs, ToT, pet info
-- Target buffs are slot-indexed and slots can have gaps, so the slot range
-- is walked and empties skipped. Resolved once from Target.MaxBuffSlots when
-- the binding has it, else this fallback (same as hud_effects' long buffs).
local TARGET_BUFF_SLOT_FALLBACK = 42
local targetBuffSlotMax = nil
-- Cap on the 'pet radius 400' sweep per slow refresh (a raid can have many pets).
local PET_SWEEP_MAX = 40

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
        if core.ctrl.uf_show_parcels == nil then core.ctrl.uf_show_parcels = true end
        if core.ctrl.uf_target_buff_rows == nil then core.ctrl.uf_target_buff_rows = 2 end
        if core.ctrl.show_target_window == nil then core.ctrl.show_target_window = false end
        if core.ctrl.tw_lock == nil then core.ctrl.tw_lock = false end
        if core.ctrl.tw_alpha == nil then core.ctrl.tw_alpha = 0.85 end
        if core.ctrl.tw_bar_height == nil then core.ctrl.tw_bar_height = 22 end
        if core.ctrl.tw_buff_rows == nil then core.ctrl.tw_buff_rows = 2 end
        if core.ctrl.tw_show_buffs == nil then core.ctrl.tw_show_buffs = true end
        if core.ctrl.tw_show_tot == nil then core.ctrl.tw_show_tot = true end
        if core.ctrl.tw_show_castbar == nil then core.ctrl.tw_show_castbar = true end
        if core.ctrl.uf_show_castbar == nil then core.ctrl.uf_show_castbar = true end
    end
end

function plugin.onDestroy()
    snap = nil
    lastRefreshAt = 0
    lastSlowRefreshAt = 0
    targetBuffSlotMax = nil
end

local function resolveTargetBuffSlotMax(mq)
    if targetBuffSlotMax then return targetBuffSlotMax end
    local n = nil
    pcall(function()
        local v = mq.TLO.Target.MaxBuffSlots
        if v then n = tonumber(v()) end
    end)
    if n and n > 0 and n <= 120 then
        targetBuffSlotMax = n
    else
        targetBuffSlotMax = TARGET_BUFF_SLOT_FALLBACK
    end
    return targetBuffSlotMax
end

-- The Parcel Helper plugin (tac/parcels.lua) when it is loaded and enabled.
local function parcelsPlugin()
    local pm = core and core.runtime and core.runtime.pluginManager
    local p = pm and pm.plugins and pm.plugins.parcels
    if p and p.enabled and p.instance and p.instance.getStatus then return p.instance end
    return nil
end

-- Slow snapshot: target-of-target, target buffs and pet spawn info. These are
-- the expensive reads (resolveTargetOfTarget, one Buff(slot) walk, a spawn
-- info lookup per pet), so they run every SLOW_REFRESH_INTERVAL and when the
-- target changes, not at the 20 Hz vitals rate. `snap` must already exist.
local function refreshSlow(force)
    local s = snap
    if not s or not core or not core.mq or not core.ctrl then return end
    local now = os.clock()
    if not force and (now - lastSlowRefreshAt) < SLOW_REFRESH_INTERVAL then return end
    lastSlowRefreshAt = now
    local mq = core.mq
    local ctrl = core.ctrl
    s.slowForTid = s.tId

    -- Parcel notifier (parcels plugin), the HUD twin of the client's
    -- PW_ParcelsIcon / PW_ParcelsOverLimitIcon on the player window.
    s.parcels = nil
    if ctrl.uf_show_parcels ~= false then
        local pp = parcelsPlugin()
        if pp then
            local okP, st = pcall(pp.getStatus)
            if okP and type(st) == 'table' and st.badge ~= false and (st.status or 0) > 0 then s.parcels = st end
        end
    end

    -- Target of Target (ToT)
    if s.hasTarget and core.resolveTargetOfTarget then
        s.tTotName, s.tTotId, s.tTotHpPct, s.myPctAggro = core.resolveTargetOfTarget(s.tId)
    else
        s.tTotName, s.tTotId, s.tTotHpPct, s.myPctAggro = nil, nil, nil, nil
    end

    -- Target Buffs: Target.Buff(n) is slot-indexed and slots can have gaps,
    -- so walk the slot range (stopping once BuffCount entries were found) and
    -- skip empties instead of reading slots 1..BuffCount.
    local targetBuffs = {}
    if s.hasTarget then
        local tbc = 0
        pcall(function() tbc = mq.TLO.Target.BuffCount() or 0 end)
        local maxShown = ctrl.uf_buff_max or 30
        local slotMax = resolveTargetBuffSlotMax(mq)
        local found = 0
        local b = 1
        while b <= slotMax and found < tbc and #targetBuffs < maxShown do
            pcall(function()
                local tbObj = mq.TLO.Target.Buff(b)
                if tbObj and tbObj() then
                    local bName = (tbObj.Name and tbObj.Name()) or tbObj()
                    if bName and bName ~= '' and bName ~= 'NONE' then
                        found = found + 1
                        local durSec = 0
                        local isBeneficial = false
                        if tbObj.Duration and tbObj.Duration.TotalSeconds then
                            durSec = tbObj.Duration.TotalSeconds() or 0
                        end
                        if tbObj.Spell and tbObj.Spell.Beneficial then
                            isBeneficial = tbObj.Spell.Beneficial() or false
                        end
                        table.insert(targetBuffs, {
                            slot = b,
                            name = bName,
                            duration = durSec,
                            beneficial = isBeneficial
                        })
                    end
                end
            end)
            b = b + 1
        end
    end
    s.targetBuffs = targetBuffs

    -- Multi-Pet Vitals
    local activePets = {}
    local seenPetIds = {}
    if core.getMultiPetList and core.getPetSpawnInfo and core.isSpawnAlive then
        local petSlots, extraPets = core.getMultiPetList()
        for _, slot in ipairs(petSlots or {}) do
            if slot.petId and slot.petId > 0 and not seenPetIds[slot.petId] and core.isSpawnAlive(slot.petId) then
                seenPetIds[slot.petId] = true
                local info = core.getPetSpawnInfo(slot.petId)
                table.insert(activePets, { id = slot.petId, cls = slot.cls, slotNum = slot.slotNum, info = info })
            end
        end
        for _, extraPid in ipairs(extraPets or {}) do
            if extraPid and extraPid > 0 and not seenPetIds[extraPid] and core.isSpawnAlive(extraPid) then
                seenPetIds[extraPid] = true
                local info = core.getPetSpawnInfo(extraPid)
                table.insert(activePets, { id = extraPid, cls = 'Pet', slotNum = nil, info = info })
            end
        end
    end
    -- Me.Pet is always part of getMultiPetList (slot or extra), and the list is
    -- deduplicated by pet name, so it is not appended separately here.
    -- Every other living pet of ours: the slot list folds same-named pets
    -- into one and only sweeps 150 units, so swarm pets, familiars and a
    -- pet that wandered off would be missing. Matched by Master (or Me.Pet)
    -- and deduplicated by spawn id only.
    if core.getPetSpawnInfo then
        pcall(function()
            local myId = mq.TLO.Me.ID() or 0
            local myPetId = mq.TLO.Me.Pet.ID() or 0
            if myId <= 0 then return end
            local filter = 'pet radius 400'
            local count = mq.TLO.SpawnCount(filter)() or 0
            for i = 1, math.min(count, PET_SWEEP_MAX) do
                local sp = mq.TLO.NearestSpawn(i, filter)
                local sid = (sp and sp() and sp.ID()) or 0
                if sid > 0 and not seenPetIds[sid] then
                    local mine = (sid == myPetId)
                    if not mine then
                        local m = sp.Master
                        mine = (m and m() and (m.ID() or 0) == myId) or false
                    end
                    if mine and (not core.isSpawnAlive or core.isSpawnAlive(sid)) then
                        seenPetIds[sid] = true
                        table.insert(activePets, { id = sid, cls = 'Pet', slotNum = nil, info = core.getPetSpawnInfo(sid), swarm = true })
                    end
                end
            end
        end)
    end
    s.activePets = activePets
end

-- Snapshot every TLO the window needs. Called from both the fiber (main loop)
-- and the render pass; the throttle below makes whichever runs first do the
-- work so the HUD stays live while combatTick / mq.delay block the main loop
-- without hammering TLOs at full frame rate.
local function refreshVitals(force)
    if not core or not core.mq or not core.ctrl then return end
    local ctrl = core.ctrl
    if not ctrl.show_unit_frames and not ctrl.show_target_window then
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
    s.tId = nil
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

    -- Target change: refresh ToT / buffs / pets right away, not on the slow timer.
    if s.tId ~= s.slowForTid then lastSlowRefreshAt = 0 end

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

    -- 4. Cast bars. The player's cast has a real time-left; the start is
    -- pinned when a new cast (by spell id) is first seen so the bar can be
    -- interpolated between snapshots. A target's cast only exposes the
    -- spell, so its bar runs from first sight over the spell's cast time.
    local myCastId, myCastName, myCastLeft, myCastTotal = 0, nil, 0, 0
    pcall(function()
        local c = mq.TLO.Me.Casting
        local cid = c.ID()
        if cid and cid > 0 then
            myCastId = cid
            myCastName = c.Name() or 'Casting'
            myCastLeft = (mq.TLO.Me.CastTimeLeft() or 0) / 1000.0
            myCastTotal = (c.MyCastTime() or c.CastTime() or 0) / 1000.0
        end
    end)
    if myCastName then
        if s.myCastId ~= myCastId or not s.myCastStart then
            s.myCastStart = now
            s.myCastTotal = math.max(myCastTotal, myCastLeft, 0.05)
        end
        s.myCastId = myCastId
        s.myCastName = myCastName
        s.myCastEnd = now + myCastLeft
    else
        s.myCastId, s.myCastName, s.myCastStart, s.myCastEnd = nil, nil, nil, nil
    end

    local tCastId, tCastName, tCastTotal = 0, nil, 0
    if s.hasTarget then
        pcall(function()
            local c = mq.TLO.Target.Casting
            local cid = c.ID()
            if cid and cid > 0 then
                tCastId = cid
                tCastName = c.Name() or 'Casting'
                tCastTotal = (c.CastTime() or 0) / 1000.0
            end
        end)
    end
    if tCastName then
        if s.tCastId ~= tCastId or s.tCastFor ~= s.tId or not s.tCastStart then
            s.tCastStart = now
            s.tCastTotal = tCastTotal
        end
        s.tCastId, s.tCastName, s.tCastFor = tCastId, tCastName, s.tId
    else
        s.tCastId, s.tCastName, s.tCastStart, s.tCastFor = nil, nil, nil, nil
    end

    snap = s
    refreshSlow(force)
end

-- A cast bar row of height barH: the spell name with the seconds left and a
-- fill that runs start -> end. `startAt` / `totalSec` come from the snapshot,
-- `endAt` (optional) is the authoritative end for the player's own cast.
-- When nothing is being cast the row is left empty (a Dummy), so the rows
-- below never move.
local function drawCastBarRow(barH, label, name, startAt, totalSec, endAt, r, g, b)
    local ImGui = core.ImGui
    if not name or not startAt then
        ImGui.Dummy(0, barH)
        return
    end
    local now = os.clock()
    local total = totalSec or 0
    local frac, left
    if endAt then
        local endTotal = math.max(endAt - startAt, total, 0.05)
        left = math.max(0, endAt - now)
        frac = 1.0 - left / endTotal
    elseif total > 0 then
        local el = now - startAt
        left = math.max(0, total - el)
        frac = el / total
    else
        left, frac = 0, 1.0
    end
    frac = math.max(0.0, math.min(1.0, frac))
    local text = (left > 0) and string.format('%s%s (%.1fs)', label or '', name, left) or string.format('%s%s', label or '', name)
    core.drawStatusProgressBar(frac, -1, barH, text, r, g, b, 1.0)
end

-- Fiber Worker: keeps the snapshot warm from the main loop (throttled)
function plugin.onTick()
    refreshVitals(false)
end

-- The target section: header line, target HP bar, ToT line + bar and the
-- buff chips, drawn inside a fixed-height child box so whatever is below
-- never shifts when the target, ToT, or buff count changes. The box
-- reserves the header line, target bar, ToT line + bar, buff header and
-- `buffRows` rows of chips; anything beyond that scrolls inside the box.
-- `opts` = { showTot, showBuffs } (nil = shown); `boxId` names the child.
-- Shared by the HUD window and the Target popout.
local function drawTargetSection(barH, buffRows, boxId, opts)
    local snap = snap -- nil-checked local: callers guard it, the analyzer can see this one
    if not snap then return end
    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    local ARC = colors.ARC or { 0.30, 0.70, 1.0, 1 }
    local GOOD = colors.GOOD or { 0.37, 0.88, 0.64, 1 }
    local WARN = colors.WARN or { 1.0, 0.72, 0.30, 1 }
    local MUTED = colors.MUTED or { 0.49, 0.56, 0.65, 1 }
    opts = opts or {}
    local showTot = opts.showTot ~= false
    local showBuffs = opts.showBuffs ~= false
    local showCast = opts.showCast ~= false
    local isAtk = snap.isAtk or false

    local lineH = 0
    pcall(function() lineH = ImGui.GetTextLineHeightWithSpacing() end)
    if not lineH or lineH <= 0 then lineH = core.px(15) end
    local spacingY = core.px(2)
    buffRows = math.max(0, math.floor(buffRows or 2))
    local targetBoxH = lineH + barH + spacingY
    if showCast then targetBoxH = targetBoxH + barH + spacingY end
    if showTot then targetBoxH = targetBoxH + lineH + math.max(10, barH - 3) + spacingY end
    if showBuffs then targetBoxH = targetBoxH + (1 + buffRows) * lineH end
    local targetBoxOpen = ImGui.BeginChild(boxId or '##ufTargetBox', 0, targetBoxH, false)
    if targetBoxOpen then
    local availW = ImGui.GetContentRegionAvail()
    if snap.hasTarget and snap.tName then
        local conCol = core.getConColorRgb(snap.tCon)
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
        core.drawStatusProgressBar((snap.tHpPct or 0) / 100.0, -1, barH, hpStr, tr, tg, tb, 1.0)

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

        -- Target cast bar (row reserved even while idle)
        if showCast then
            drawCastBarRow(barH, 'Casting: ', snap.tCastName, snap.tCastStart, snap.tCastTotal, nil, 0.85, 0.35, 0.35)
            if snap.tCastName and ImGui.IsItemHovered() and core.setTooltip then
                core.setTooltip('%s', string.format('%s is casting %s%s', snap.tName or 'Target', snap.tCastName,
                    (snap.tCastTotal or 0) > 0 and string.format('\nCast time: %.1fs', snap.tCastTotal) or ''))
            end
        end

        -- ToT
        if not showTot then
            -- nothing: the popout can hide the ToT rows
        elseif snap.tTotName and snap.tTotName ~= 'None' and snap.tTotName ~= '' then
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
                core.drawStatusProgressBar(snap.tTotHpPct / 100.0, -1, math.max(10, barH - 3), totBarStr, totr, totg, totb, 1.0)
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
        if not showBuffs then
            -- nothing: the popout can hide the buff chips
        elseif #targetBuffs > 0 then
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
        core.drawStatusProgressBar(0, -1, barH, 'No Target', 0.25, 0.25, 0.25, 0.5)
    end
    end
    ImGui.EndChild()
end

-- Header-button choice for the Target popout, kept by the core under
-- ctrl.plugins.hud_unitframes.windowHeader.target_window.
local function targetWindowHeaderButton()
    local pm = core and core.runtime and core.runtime.pluginManager
    if pm and pm.headerButtonEnabled then return pm.headerButtonEnabled(TARGET_WINDOW_ID) == true end
    return false
end
local function setTargetWindowHeaderButton(val)
    local pm = core and core.runtime and core.runtime.pluginManager
    if pm and pm.setHeaderButton then pm.setHeaderButton(TARGET_WINDOW_ID, val) end
end

-- Settings for the Target popout: in its right-click menu and under the
-- HUD's settings on the Plugins page.
local function renderTargetWindowSettingsContent()
    if not core or not core.ImGui or not core.ctrl then return end
    local ImGui = core.ImGui
    local ctrl = core.ctrl
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }

    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Target Window Settings')
    ImGui.Separator()

    local isWinOpen = (ctrl.show_target_window == true)
    local btnText = isWinOpen and 'Target Window: Visible (Click to Hide)' or 'Target Window: Hidden (Click to Show)'
    if ImGui.Button(btnText .. '##twToggleWin', core.px(250), core.px(24)) then
        ctrl.show_target_window = not isWinOpen
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('A popout with just the target frame (name, HP bar, ToT, buffs). Scale it up and park it where you can always see what you are on.\nAlso: /ac target')
    end
    ImGui.Spacing()

    local hdrOn = targetWindowHeaderButton()
    local newHdr = ImGui.Checkbox('Header Button on Main Window##twHdr', hdrOn)
    if newHdr ~= hdrOn then setTargetWindowHeaderButton(newHdr) end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Show a "Target" button on the main window header that opens / closes the Target window.')
    end
    local lockVal = ImGui.Checkbox('Lock Window Position & Size##twLock', ctrl.tw_lock or false)
    if lockVal ~= (ctrl.tw_lock or false) then
        ctrl.tw_lock = lockVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local totVal = ImGui.Checkbox('Show Target of Target##twTot', ctrl.tw_show_tot ~= false)
    if totVal ~= (ctrl.tw_show_tot ~= false) then
        ctrl.tw_show_tot = totVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local castVal = ImGui.Checkbox('Show Target Cast Bar##twCast', ctrl.tw_show_castbar ~= false)
    if castVal ~= (ctrl.tw_show_castbar ~= false) then
        ctrl.tw_show_castbar = castVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local buffsVal = ImGui.Checkbox('Show Target Buffs##twBuffs', ctrl.tw_show_buffs ~= false)
    if buffsVal ~= (ctrl.tw_show_buffs ~= false) then
        ctrl.tw_show_buffs = buffsVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if core.drawWindowScaleControl then core.drawWindowScaleControl('target_window', 'Scale', 120) end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Size of the whole Target window (text, bars, chips). Pick 1.5x or 2x for a frame that reads across the screen.')
    end
    ImGui.SetNextItemWidth(core.px(120))
    local newAlpha = ImGui.SliderFloat('Opacity##twAlpha', ctrl.tw_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.tw_alpha or 0.85) then
        ctrl.tw_alpha = newAlpha
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(core.px(120))
    local newH = ImGui.SliderInt('Bar Height##twHeight', ctrl.tw_bar_height or 22, 10, 40)
    if newH ~= (ctrl.tw_bar_height or 22) then
        ctrl.tw_bar_height = newH
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ctrl.tw_show_buffs ~= false then
        ImGui.SetNextItemWidth(core.px(120))
        local newRows = ImGui.SliderInt('Buff Rows##twRows', ctrl.tw_buff_rows or 2, 0, 6)
        if newRows ~= (ctrl.tw_buff_rows or 2) then
            ctrl.tw_buff_rows = newRows
            if core.saveLoadout then core.saveLoadout(true) end
        end
        if ImGui.IsItemHovered() and core.setTooltip then
            core.setTooltip('Rows of target buff chips the window reserves; extra buffs scroll inside the box.')
        end
    end
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
    if ImGui.Button(btnText .. '##ufToggleWin', core.px(250), core.px(24)) then
        ctrl.show_unit_frames = not isWinOpen
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local twOpen = (ctrl.show_target_window == true)
    if ImGui.Button((twOpen and 'Popout Target Window: Visible (Click to Hide)' or 'Popout Target Window: Hidden (Click to Show)') .. '##ufTwToggle', core.px(250), core.px(24)) then
        ctrl.show_target_window = not twOpen
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Opens the target frame in a window of its own that can be scaled up and placed anywhere; right-click that window for its settings.\nAlso: /ac target')
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
    local showCastVal = ImGui.Checkbox('Show Cast Bars (Player & Target)##ufCast', ctrl.uf_show_castbar ~= false)
    if showCastVal ~= (ctrl.uf_show_castbar ~= false) then
        ctrl.uf_show_castbar = showCastVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('A cast bar under the target HP bar (what the target is casting) and one in the player section (your own cast, with the seconds left). The rows stay reserved while idle so the bars below never move.')
    end
    local showXpVal = ImGui.Checkbox('Show XP & AAXP Bars##ufXp', ctrl.uf_show_xp ~= false)
    if showXpVal ~= (ctrl.uf_show_xp ~= false) then
        ctrl.uf_show_xp = showXpVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    local showParcelsVal = ImGui.Checkbox('Show Parcels Waiting Badge##ufParcels', ctrl.uf_show_parcels ~= false)
    if showParcelsVal ~= (ctrl.uf_show_parcels ~= false) then
        ctrl.uf_show_parcels = showParcelsVal
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Shows a parcel badge on the player section when parcels are waiting at a parcel merchant (parcels plugin), like the client player window icon.')
    end
    if core.drawWindowScaleControl then core.drawWindowScaleControl('unit_frames', 'Scale', 120) end
    ImGui.SetNextItemWidth(core.px(120))
    local newAlpha = ImGui.SliderFloat('Opacity##ufAlpha', ctrl.uf_alpha or 0.85, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.uf_alpha or 0.85) then
        ctrl.uf_alpha = newAlpha
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(core.px(120))
    local newH = ImGui.SliderInt('Bar Height##ufHeight', ctrl.uf_bar_height or 14, 10, 24)
    if newH ~= (ctrl.uf_bar_height or 14) then
        ctrl.uf_bar_height = newH
        if core.saveLoadout then core.saveLoadout(true) end
    end
    ImGui.SetNextItemWidth(core.px(120))
    local newRows = ImGui.SliderInt('Target Box Buff Rows##ufTbRows', ctrl.uf_target_buff_rows or 2, 0, 6)
    if newRows ~= (ctrl.uf_target_buff_rows or 2) then
        ctrl.uf_target_buff_rows = newRows
        if core.saveLoadout then core.saveLoadout(true) end
    end
    if ImGui.IsItemHovered() and core.setTooltip then
        core.setTooltip('Rows of target buff chips reserved in the fixed-height target box at the top of the window. The box never resizes, so the player bars below stay put; extra buffs scroll inside the box.')
    end
    ImGui.SetNextItemWidth(core.px(120))
    local newMaxB = ImGui.SliderInt('Max Buffs##ufMaxB', ctrl.uf_buff_max or 30, 5, 50)
    if newMaxB ~= (ctrl.uf_buff_max or 30) then
        ctrl.uf_buff_max = newMaxB
        if core.saveLoadout then core.saveLoadout(true) end
    end
end

-- The Target & Player HUD window: reads from the cached snap with near-zero overhead
local function drawUnitFramesWindow()
    local ctrl = core.ctrl
    if not ctrl.show_unit_frames then return end

    local ImGui = core.ImGui
    local colors = core.colors or {}
    local GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    local MUTED = colors.MUTED or { 0.49, 0.56, 0.65, 1 }

    if core.pushTheme then core.pushTheme() end

    if ctrl.uf_alpha then
        ImGui.SetNextWindowBgAlpha(core.windowBgAlpha and core.windowBgAlpha('unit_frames', ctrl.uf_alpha) or ctrl.uf_alpha)
    end
    ImGui.SetNextWindowSize(core.px(320), core.px(360), ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.uf_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    if core.preBeginWindow then core.preBeginWindow('unit_frames') end
    -- Pushed after preBeginWindow so this tight chrome wins over the scaled theme padding.
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, core.px(4), core.px(4))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, core.px(3), core.px(2))
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, core.px(2), core.px(1))

    local show
    local winTitle = 'Triune Target & Player v' .. (core.VERSION or '3.0') .. '###triuneUnitFrames'
    ctrl.show_unit_frames, show = ImGui.Begin(winTitle, ctrl.show_unit_frames, core.windowFlags and core.windowFlags('unit_frames', winFlags) or winFlags)

    if not ctrl.show_unit_frames then
        if core.preEndWindow then core.preEndWindow('unit_frames', true) end
        ImGui.End()
        ImGui.PopStyleVar(3)
        if core.popTheme then core.popTheme() end
        if core.saveLoadout then core.saveLoadout(true) end
        return
    end

    if show then
        if core.postBeginWindow then core.postBeginWindow('unit_frames') end
        refreshVitals(false)
        local snap = snap
        if snap then
            local barH = core.px(ctrl.uf_bar_height or 14)

        -- Context Menu
        if ImGui.BeginPopupContextWindow('##ufContextMenu') then
            if core.applyWindowScale then core.applyWindowScale('unit_frames') end
            if core.drawWindowMenuItems then
                core.drawWindowMenuItems('unit_frames', { header = false, lock = false, scale = false, layout = false, close = false })
                ImGui.Separator()
            end
            renderUfSettingsContent()
            ImGui.EndPopup()
        end

        -- 1. Target & ToT (fixed-height box: the player bars never move)
        drawTargetSection(barH, ctrl.uf_target_buff_rows or 2, '##ufTargetBox', { showCast = ctrl.uf_show_castbar ~= false })
        -- The child is its own window, so the parent's context menu would not
        -- open from a right-click inside the box; forward it here.
        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(1) then
            ImGui.OpenPopup('##ufContextMenu')
        end

        -- 2. Player Vitals
        ImGui.Separator()

        -- Parcel badge: only drawn while parcels are waiting (status 1) or the
        -- mailbox is over its limit (status 2), like the client's player icon.
        local pst = snap.parcels
        if pst then
            local over = (pst.status or 0) >= 2
            local Col = ImGuiCol or _G.ImGuiCol or (core.mq and core.mq.imgui and core.mq.imgui.Col)
            local pushed = 0
            if Col then
                if over then
                    local pulse = 0.55 + 0.45 * math.sin(os.clock() * 6)
                    if pcall(ImGui.PushStyleColor, Col.Button, 0.55 * pulse + 0.15, 0.10, 0.10, 0.85) then pushed = pushed + 1 end
                    if pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.75, 0.18, 0.18, 0.95) then pushed = pushed + 1 end
                    if pcall(ImGui.PushStyleColor, Col.Text, 1.0, 0.80, 0.80, 1.0) then pushed = pushed + 1 end
                else
                    if pcall(ImGui.PushStyleColor, Col.Button, 0.40, 0.30, 0.10, 0.80) then pushed = pushed + 1 end
                    if pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.55, 0.42, 0.14, 0.95) then pushed = pushed + 1 end
                    if pcall(ImGui.PushStyleColor, Col.Text, GOLD[1], GOLD[2], GOLD[3], 1.0) then pushed = pushed + 1 end
                end
            end
            local label = over and ('[!] ' .. (pst.label or 'Parcels OVER LIMIT')) or ('[=] ' .. (pst.label or 'Parcels waiting'))
            if pst.collecting then label = '[=] Collecting parcels...' end
            if ImGui.SmallButton(label .. '##ufParcelBadge') then
                local pp = parcelsPlugin()
                if pp and pp.onBadgeClick then pcall(pp.onBadgeClick) end
            end
            if pushed > 0 then pcall(ImGui.PopStyleColor, pushed) end
            if ImGui.IsItemHovered() and core.setTooltip then
                local tip
                if over then
                    tip = 'You are over your parcel limit! Retrieve the excess ones soon or risk losing them!'
                else
                    tip = 'You have parcel deliveries.'
                end
                if pst.merchantOpen then
                    tip = tip .. '\nClick: Collect All at this merchant'
                else
                    tip = tip .. '\nClick: open the Parcel Helper (visit a parcel merchant to collect)'
                end
                core.setTooltip('%s', tip)
            end
        end

        local pr, pg, pb = 0.25, 0.80, 0.35
        if (snap.myHpPct or 0) <= 25 then
            pr, pg, pb = 0.90, 0.20, 0.20
        elseif (snap.myHpPct or 0) <= 50 then
            pr, pg, pb = 0.95, 0.75, 0.20
        end
        local myHpStr = string.format('Player HP: %d%% (%d / %d)', snap.myHpPct or 0, snap.myCurHp or 0, snap.myMaxHp or 0)
        core.drawStatusProgressBar((snap.myHpPct or 0) / 100.0, -1, barH, myHpStr, pr, pg, pb, 1.0)

        if (snap.myMaxMana or 0) > 0 then
            local manaStr = string.format('Mana: %d%% (%d / %d)', snap.myManaPct or 0, snap.myCurMana or 0, snap.myMaxMana or 0)
            core.drawStatusProgressBar((snap.myManaPct or 0) / 100.0, -1, barH, manaStr, 0.25, 0.60, 0.95, 1.0)
        end

        if ctrl.uf_show_endurance ~= false and (snap.myMaxEnd or 0) > 0 then
            local endStr = string.format('End: %d%% (%d / %d)', snap.myEndPct or 0, snap.myCurEnd or 0, snap.myMaxEnd or 0)
            core.drawStatusProgressBar((snap.myEndPct or 0) / 100.0, -1, barH, endStr, 0.95, 0.60, 0.25, 1.0)
        end

        if ctrl.uf_show_castbar ~= false then
            drawCastBarRow(barH, 'Casting: ', snap.myCastName, snap.myCastStart, snap.myCastTotal, snap.myCastEnd, 0.70, 0.45, 0.95)
            if snap.myCastName and ImGui.IsItemHovered() and core.setTooltip then
                core.setTooltip('%s', string.format('Casting %s\nCast time: %.1fs', snap.myCastName, snap.myCastTotal or 0))
            end
        end

        if ctrl.uf_show_xp ~= false then
            local xpStr = string.format('XP (Lvl %d): %.2f%%', snap.myLvl or 1, snap.myExpPct or 0)
            core.drawStatusProgressBar((snap.myExpPct or 0) / 100.0, -1, barH, xpStr, 0.85, 0.70, 0.20, 1.0)

            local aaxpStr = string.format('AAXP: %.2f%% (%d Banked)', snap.myAAExpPct or 0, snap.myBankedAA or 0)
            core.drawStatusProgressBar((snap.myAAExpPct or 0) / 100.0, -1, barH, aaxpStr, 0.65, 0.35, 0.90, 1.0)
        end

        -- 3. Multi-Pet Vitals
        local activePets = snap.activePets or {}
        if #activePets > 0 then
            ImGui.Separator()
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format('Pets (%d):', #activePets))
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
                local pBarStr = string.format('%s%s%s: %d%%%s', pData.swarm and '' or 'Pet ', pClsTag, pInfo.cleanName or 'Pet', pHp, pTargetStr)
                core.drawStatusProgressBar(pHp / 100.0, -1, barH, pBarStr, petR, petG, petB, 1.0)
                if ImGui.IsItemClicked() and pData.id and pData.id > 0 then
                    core.mq.cmdf('/target id %d', pData.id)
                end
                if ImGui.IsItemHovered() and core.setTooltip then
                    core.setTooltip('%s', string.format('%s: %s\nClass: %s\nLevel: %d\nHP: %d%%\nDistance: %.0f\nTarget: %s\nBuff Count: %d\nClick to target',
                        pData.swarm and 'Pet (swarm / extra)' or 'Pet', pInfo.cleanName or 'Pet', pData.cls or 'Pet', pInfo.level or 0, pHp,
                        pInfo.dist or 0, pInfo.targetName or 'None', #(pInfo.buffs or {})))
                end
            end
        elseif ctrl.uf_hide_empty_pets == false then
            ImGui.Separator()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'No active pets')
        end
        end
    end

    if core.preEndWindow then core.preEndWindow('unit_frames', true) end

    ImGui.End()
    ImGui.PopStyleVar(3)
    if core.popTheme then core.popTheme() end
end

-- The Target popout: the target section alone, with its own bar height,
-- opacity, lock, buff rows and ToT / buff toggles, plus the core's
-- per-window scale so it can be made as large as the screen allows.
local function drawTargetWindow()
    local ctrl = core.ctrl
    if not ctrl.show_target_window then return end
    local ImGui = core.ImGui

    if core.pushTheme then core.pushTheme() end

    if ctrl.tw_alpha then
        ImGui.SetNextWindowBgAlpha(core.windowBgAlpha and core.windowBgAlpha('target_window', ctrl.tw_alpha) or ctrl.tw_alpha)
    end
    ImGui.SetNextWindowSize(core.px(360), core.px(150), ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.tw_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    if core.preBeginWindow then core.preBeginWindow('target_window') end
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, core.px(4), core.px(4))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, core.px(3), core.px(2))
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, core.px(2), core.px(1))

    local show
    local winTitle = 'Triune Target v' .. (core.VERSION or '3.0') .. '###triuneTargetWindow'
    ctrl.show_target_window, show = ImGui.Begin(winTitle, ctrl.show_target_window, core.windowFlags and core.windowFlags('target_window', winFlags) or winFlags)

    if not ctrl.show_target_window then
        if core.preEndWindow then core.preEndWindow('target_window', true) end
        ImGui.End()
        ImGui.PopStyleVar(3)
        if core.popTheme then core.popTheme() end
        if core.saveLoadout then core.saveLoadout(true) end
        return
    end

    if show then
        if core.postBeginWindow then core.postBeginWindow('target_window') end
        refreshVitals(false)
        local snap = snap
        if snap then
            if ImGui.BeginPopupContextWindow('##twContextMenu') then
                if core.applyWindowScale then core.applyWindowScale('target_window') end
                if core.drawWindowMenuItems then
                    core.drawWindowMenuItems('target_window', { header = false, lock = false, scale = false, layout = false, close = false })
                    ImGui.Separator()
                end
                renderTargetWindowSettingsContent()
                ImGui.EndPopup()
            end

            drawTargetSection(core.px(ctrl.tw_bar_height or 22), ctrl.tw_buff_rows or 2, '##twTargetBox',
                { showTot = ctrl.tw_show_tot ~= false, showBuffs = ctrl.tw_show_buffs ~= false, showCast = ctrl.tw_show_castbar ~= false })
            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(1) then
                ImGui.OpenPopup('##twContextMenu')
            end
        end
    end

    if core.preEndWindow then core.preEndWindow('target_window', true) end
    ImGui.End()
    ImGui.PopStyleVar(3)
    if core.popTheme then core.popTheme() end
end

function plugin.onDrawUI()
    if not core or not core.ImGui or not core.ctrl then return end
    drawUnitFramesWindow()
    drawTargetWindow()
end

function plugin.onDrawSettings()
    renderUfSettingsContent()
    if core and core.ImGui then
        core.ImGui.Spacing()
        core.ImGui.Separator()
        core.ImGui.Spacing()
    end
    renderTargetWindowSettingsContent()
end

return plugin
