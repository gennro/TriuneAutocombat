---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_cooldowns.lua — Triune Cooldown & Ability Monitor Plugin
-- ============================================================================
-- Tracks every loadout ability (AAs, disciplines, skills, clickies, spell gems)
-- with live ready / active / cooling-down status, timers, and click-to-fire,
-- and presents it in the popout Cooldown Monitor window (ctrl.show_cooldowns;
-- header button, /ac cd, Mini HUD, and the Window Layout manager toggle it).
--
-- Read-only against combat state: it only inspects runtime.lastCast /
-- discExpires / discCooldown / timerGroupCooldown / last*FiredAt and the cast
-- tracker, and fires abilities through the same runtime.fire* / castGem /
-- useClickie entry points the combat loop uses.
-- ============================================================================

local plugin = {
    id                 = 'hud_cooldowns',
    name               = 'Cooldown Monitor',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout Cooldown & Ability Monitor window with live timers, filters, and click-to-fire.',
    defaultEnabled     = true,
    tickInterval       = 1.0,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Cooldowns', tooltip = 'Toggles the popout Cooldown & Ability Monitor window.', flag = 'show_cooldowns', key = 'cooldowns', lockFlag = 'cooldown_locked', desc = 'Popout Cooldown & Ability Monitor', headerButton = true, order = 50 },
}

local core = nil
local rt, ctrl, ImGui, mq, accent = nil, nil, nil, nil, nil
local GOLD, ARC, MUTED, GOOD, WARN = nil, nil, nil, nil, nil
local M = { cooldownSearch = '' }

local function refresh()
    ctrl = core.ctrl
    rt = core.runtime
    ImGui = core.ImGui
    mq = core.mq
    accent = core.accent
end

function plugin.onInit(coreApi)
    core = coreApi
    refresh()
    local colors = core.colors or {}
    GOLD = colors.GOLD or { 1.0, 0.70, 0.54, 1 }
    ARC = colors.ARC or { 0.30, 0.70, 1.0, 1 }
    MUTED = colors.MUTED or { 0.49, 0.56, 0.65, 1 }
    GOOD = colors.GOOD or { 0.37, 0.88, 0.64, 1 }
    WARN = colors.WARN or { 1.0, 0.72, 0.30, 1 }
    if ctrl then
        if ctrl.show_cooldowns == nil then ctrl.show_cooldowns = false end
        if ctrl.cooldown_locked == nil then ctrl.cooldown_locked = false end
        if ctrl.cooldown_alpha == nil then ctrl.cooldown_alpha = 0.90 end
    end
end

function plugin.onDestroy()
end

function M.getTrackedCooldownItems()
    local items = {}
    local now = os.clock()
    local myEnd = 0
    local myMana = 0
    local targetId = 0
    local isNamedTarget = false
    local activeXtarCount = 0

    pcall(function()
        myEnd = tonumber(mq.TLO.Me.CurrentEndurance() or 0) or 0
        myMana = tonumber(mq.TLO.Me.CurrentMana() or 0) or 0
        targetId = mq.TLO.Target.ID() or 0
        if targetId > 0 then
            local sp = mq.TLO.Spawn(targetId)
            if sp and sp() and sp.Named and sp.Named() then
                isNamedTarget = true
            end
        end
        if rt.countNPCXtarget then
            activeXtarCount = rt.countNPCXtarget() or 0
        end
    end)

    local activeDiscName = nil
    pcall(function()
        local ad = mq.TLO.Me.ActiveDisc
        if ad and ad() then
            local n = ad.Name()
            if n and n ~= '' and n ~= 'NULL' then activeDiscName = n end
        end
    end)

    -- 1. Innate Combat Abilities / Skills
    if core.loadout and core.loadout.actions then
        for nm, entry in pairs(core.loadout.actions) do
            if entry and entry.enabled then
                local isReady = false
                local timerSec = 0
                local totalSec = core.getAbilityBaseCooldown(nm)

                pcall(function()
                    local r = mq.TLO.Me.AbilityReady(nm)()
                    if r ~= nil then isReady = (r == true) end

                    local t = mq.TLO.Me.AbilityTimer(nm)
                    if not t or not t() then
                        local idx = mq.TLO.Me.Ability(nm)()
                        if idx and idx > 0 then t = mq.TLO.Me.AbilityTimer(idx) end
                    end
                    if t and t() then
                        timerSec = core.parseDurationSec(t)
                    end

                    local tot = mq.TLO.Me.AbilityTimerTotal(nm)
                    if not tot or not tot() then
                        local idx = mq.TLO.Me.Ability(nm)()
                        if idx and idx > 0 then tot = mq.TLO.Me.AbilityTimerTotal(idx) end
                    end
                    if tot and tot() then
                        local numTot = core.parseDurationSec(tot)
                        if numTot > 0 then totalSec = numTot end
                    end
                end)

                local sKey = 's' .. nm
                if rt.lastCast[sKey] and rt.lastCast[sKey] > now then
                    local sRem = rt.lastCast[sKey] - now
                    if sRem > timerSec then timerSec = sRem end
                    isReady = false
                end

                if rt.lastSkillFiredAt and rt.lastSkillFiredAt[nm] then
                    local elapsed = now - rt.lastSkillFiredAt[nm]
                    if elapsed < totalSec then
                        local sRem = totalSec - elapsed
                        if sRem > timerSec then timerSec = sRem end
                    else
                        rt.lastSkillFiredAt[nm] = nil
                    end
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 6) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isReady then
                    if entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText
                if entry.autoskill then
                    condText = 'Auto on Cooldown'
                else
                    condText = string.format('%s (%s %d%%)', entry.target or 'Target', entry.when or 'in combat', tonumber(entry.pct) or 100)
                end

                table.insert(items, {
                    kind = 'Skill',
                    typeLabel = 'Skill',
                    cls = entry.cls or (core.myClasses and core.myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = entry.priority or 50,
                    burn_only = entry.burn_only or false,
                    conditionText = condText,
                    use = function() rt.fireSkill(nm, entry) end,
                })
            end
        end
    end

    -- 2. Alternate Advancements (AAs)
    if core.loadout and core.loadout.aas then
        for rawNm, entry in pairs(core.loadout.aas) do
            local nm = type(rawNm) == 'string' and rawNm:match('^%s*(.-)%s*$') or rawNm
            if entry and entry.enabled then
                local isReady = false
                local timerSec = 0
                local totalSec = 0
                local endCost = 0
                local manaCost = 0
                local activeSec = 0
                local activeTotalSec = 0
                local isActive = false
                local aaId = 0
                local spellName = nil

                pcall(function()
                    local r = mq.TLO.Me.AltAbilityReady(nm)()
                    if r ~= nil then isReady = (r == true) end

                    local aaObj = mq.TLO.AltAbility(nm)
                    if aaObj and aaObj() then
                        aaId = tonumber(aaObj.ID and aaObj.ID() or 0) or 0
                        local mrt = aaObj.MyReuseTime and aaObj.MyReuseTime()
                        local rt = aaObj.ReuseTime and aaObj.ReuseTime()
                        totalSec = tonumber(mrt or rt or 0) or 0
                        if totalSec == 0 and aaObj.Spell and aaObj.Spell() then
                            totalSec = core.parseSpellRecastTime(aaObj.Spell)
                            spellName = aaObj.Spell.Name and aaObj.Spell.Name()
                        end
                        if aaObj.Spell and aaObj.Spell() and aaObj.Spell.Duration then
                            activeTotalSec = core.parseDurationSec(aaObj.Spell.Duration)
                        end
                    end

                    local myAA = mq.TLO.Me.AltAbility(nm)
                    if myAA and myAA() then
                        if aaId == 0 and myAA.ID and myAA.ID() then
                            aaId = tonumber(myAA.ID() or 0) or 0
                        end
                        if myAA.Spell and myAA.Spell() then
                            endCost = tonumber(myAA.Spell.EnduranceCost() or 0) or 0
                            manaCost = tonumber(myAA.Spell.Mana() or 0) or 0
                            if not spellName and myAA.Spell.Name then
                                spellName = myAA.Spell.Name()
                            end
                            if activeTotalSec <= 0 and myAA.Spell.Duration then
                                activeTotalSec = core.parseDurationSec(myAA.Spell.Duration)
                            end
                        end
                    end

                    -- Query AltAbilityTimer by Name, then by ID
                    local t = mq.TLO.Me.AltAbilityTimer(nm)
                    if (not t or not t()) and aaId > 0 then
                        t = mq.TLO.Me.AltAbilityTimer(aaId)
                    end
                    if t and t() then
                        timerSec = core.parseDurationSec(t)
                    end

                    -- Check Active state on Buff or Song (by AA name or Spell name)
                    local b = mq.TLO.Me.Buff(nm)
                    if (not b or not b()) and spellName and spellName ~= '' then
                        b = mq.TLO.Me.Buff(spellName)
                    end
                    if b and b() then
                        local bDur = core.parseDurationSec(b.Duration)
                        if bDur > 0 then
                            isActive = true
                            activeSec = bDur
                        end
                    end

                    if not isActive then
                        local s = mq.TLO.Me.Song(nm)
                        if (not s or not s()) and spellName and spellName ~= '' then
                            s = mq.TLO.Me.Song(spellName)
                        end
                        if s and s() then
                            local sDur = core.parseDurationSec(s.Duration)
                            if sDur > 0 then
                                isActive = true
                                activeSec = sDur
                            end
                        end
                    end
                end)

                -- Check software timer if lastAAFiredAt exists
                if rt.lastAAFiredAt and rt.lastAAFiredAt[nm] then
                    local elapsed = now - rt.lastAAFiredAt[nm]
                    if totalSec <= 0 and rt.aaCooldownTotal and rt.aaCooldownTotal[nm] then
                        totalSec = rt.aaCooldownTotal[nm]
                    end
                    if totalSec > 0 and elapsed < totalSec then
                        local rem = totalSec - elapsed
                        if rem > timerSec then timerSec = rem end
                    else
                        rt.lastAAFiredAt[nm] = nil
                    end
                end

                local aKey = 'a' .. nm
                if rt.lastCast[aKey] and rt.lastCast[aKey] > now then
                    local rem = rt.lastCast[aKey] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady and not isActive then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 60) end
                if activeTotalSec <= 0 then activeTotalSec = math.max(activeSec, 18) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isActive then
                    status = 'ACTIVE'
                    reason = string.format('Active duration: %s left', activeSec > 0 and core.fmtSec(math.floor(activeSec)) or 'Running')
                elseif isReady then
                    if endCost > 0 and myEnd < endCost then
                        status = 'LOW END'
                        reason = string.format('Need %d End (Have %d)', endCost, myEnd)
                    elseif manaCost > 0 and myMana < manaCost then
                        status = 'LOW MANA'
                        reason = string.format('Need %d Mana (Have %d)', manaCost, myMana)
                    elseif core.castTracker and core.castTracker.isLockedOut and core.castTracker.isLockedOut(nm, targetId, entry.kind) then
                        status = 'LOCKED'
                        reason = 'Spell lockout / Target immunity active'
                    elseif entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText = string.format('%s (%s %d%%)', entry.target or 'Myself', entry.when or 'in combat', tonumber(entry.pct) or 30)

                table.insert(items, {
                    kind = 'AA',
                    typeLabel = 'AA',
                    cls = entry.cls or (core.myClasses and core.myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = nil,
                    ready = isReady,
                    active = isActive,
                    activeSec = activeSec,
                    activeTotalSec = activeTotalSec,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = 45,
                    burn_only = entry.burn_only or false,
                    autoskill = false,
                    min_xtar = minXt,
                    entry = entry,
                    conditionText = condText,
                    use = function() rt.fireAA(nm, entry, targetId > 0 and targetId or mq.TLO.Me.ID()) end,
                })
            end
        end
    end

    -- 3. Disciplines
    if core.loadout and core.loadout.discs then
        for nm, entry in pairs(core.loadout.discs) do
            if entry and entry.enabled then
                local discInfo = core.getDiscCooldownAndDuration(nm)
                local isReady = false
                local timerSec = 0
                local totalSec = discInfo.recastSec
                local endCost = discInfo.endCost
                local activeSec = 0
                local activeTotalSec = discInfo.durSec
                local isActive = false
                local timerGroupId = discInfo.timerGroupId
                local discIdx = discInfo.discIdx

                pcall(function()
                    isReady = rt.isDiscReady(nm)

                    local r = mq.TLO.Me.CombatAbilityReady(nm)()
                    if r ~= nil and not r then isReady = false end

                    local cat = mq.TLO.Me.CombatAbilityTimer(nm)
                    if (not cat or not cat()) and discIdx > 0 then
                        cat = mq.TLO.Me.CombatAbilityTimer(discIdx)
                    end
                    if cat and cat() then
                        local cSec = core.parseCombatAbilityTimer(cat)
                        if cSec > 0 then timerSec = cSec end
                    end
                end)

                -- Check active state: ActiveDisc / Buff / Song
                if activeDiscName and (activeDiscName:lower() == nm:lower() or activeDiscName == nm) then
                    isActive = true
                end

                pcall(function()
                    local b = mq.TLO.Me.Buff(nm)
                    if b and b() then
                        local bDur = core.parseDurationSec(b.Duration)
                        if bDur > 0 then
                            isActive = true
                            activeSec = bDur
                        end
                    else
                        local s = mq.TLO.Me.Song(nm)
                        if s and s() then
                            local sDur = core.parseDurationSec(s.Duration)
                            if sDur > 0 then
                                isActive = true
                                activeSec = sDur
                            end
                        end
                    end
                end)

                if rt.discExpires and rt.discExpires[nm] and rt.discExpires[nm] > now then
                    local rem = rt.discExpires[nm] - now
                    isActive = true
                    if rem > activeSec then activeSec = rem end
                end

                -- If active but activeSec is 0, estimate from base duration and initialize software expiry
                if isActive and activeSec <= 0 then
                    local baseDur = activeTotalSec > 0 and activeTotalSec or 18
                    if not rt.discExpires then rt.discExpires = {} end
                    if not rt.discExpires[nm] or rt.discExpires[nm] <= now then
                        rt.discExpires[nm] = now + baseDur
                    end
                    activeSec = math.max(1, rt.discExpires[nm] - now)
                end

                if rt.discCooldown and rt.discCooldown[nm] and rt.discCooldown[nm] > now then
                    local rem = rt.discCooldown[nm] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end
                if timerGroupId and rt.timerGroupCooldown and rt.timerGroupCooldown[timerGroupId] and rt.timerGroupCooldown[timerGroupId] > now then
                    local rem = rt.timerGroupCooldown[timerGroupId] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end
                local dKey = 'd' .. nm
                if rt.lastCast[dKey] and rt.lastCast[dKey] > now then
                    local rem = rt.lastCast[dKey] - now
                    if rem > timerSec then timerSec = rem end
                    isReady = false
                end

                if rt.lastDiscFiredAt and rt.lastDiscFiredAt[nm] then
                    local elapsed = now - rt.lastDiscFiredAt[nm]
                    if totalSec > 0 and elapsed < totalSec then
                        local rem = totalSec - elapsed
                        if rem > timerSec then timerSec = rem end
                    else
                        rt.lastDiscFiredAt[nm] = nil
                    end
                end

                if timerSec > 0.05 then
                    isReady = false
                elseif isReady and not isActive then
                    timerSec = 0
                end
                if totalSec <= 0 then totalSec = math.max(timerSec, 30) end
                if activeTotalSec <= 0 then activeTotalSec = math.max(activeSec, 18) end

                local status = isReady and 'READY' or 'COOLDOWN'
                local reason = ''
                local minXt = tonumber(entry.min_xtar) or 1
                if isActive then
                    status = 'ACTIVE'
                    reason = string.format('Active duration: %s left', activeSec > 0 and core.fmtSec(math.floor(activeSec)) or 'Running')
                elseif isReady then
                    if endCost > 0 and myEnd < endCost then
                        status = 'LOW END'
                        reason = string.format('Need %d End (Have %d)', endCost, myEnd)
                    elseif activeDiscName and activeDiscName ~= '' and activeDiscName:lower() ~= nm:lower() then
                        status = 'BLOCKED'
                        reason = string.format('Active Disc conflict: %s is running', activeDiscName)
                    elseif entry.boss_only and not isNamedTarget then
                        status = 'NEED BOSS'
                        reason = 'Requires Named / Boss target'
                    elseif entry.burn_only and not ctrl.burn then
                        status = 'NEED BURN'
                        reason = 'Requires Burn Mode ON'
                    elseif activeXtarCount < minXt then
                        status = 'MIN XTAR'
                        reason = string.format('Requires %d+ mobs on XTarget (current: %d)', minXt, activeXtarCount)
                    end
                end

                local condText = string.format('%s (%s %d%%)', entry.target or 'Myself', entry.when or 'HP <=', tonumber(entry.pct) or 30)

                table.insert(items, {
                    kind = 'Disc',
                    typeLabel = timerGroupId and ('Disc ' .. timerGroupId) or 'Disc',
                    cls = entry.cls or (core.myClasses and core.myClasses[1]) or 'War',
                    name = nm,
                    timerGroup = timerGroupId,
                    ready = isReady,
                    active = isActive,
                    activeSec = activeSec,
                    activeTotalSec = activeTotalSec,
                    timeLeft = timerSec,
                    totalSec = totalSec,
                    status = status,
                    reason = reason,
                    priority = entry.priority or 50,
                    burn_only = entry.burn_only or false,
                    boss_only = entry.boss_only or false,
                    autoskill = false,
                    min_xtar = minXt,
                    entry = entry,
                    conditionText = condText,
                    use = function() rt.fireDisc(nm, entry, targetId > 0 and targetId or mq.TLO.Me.ID()) end,
                })
            end
        end
    end

    -- 4. Spells (Gems) - when category includes Spells or All
    if core.loadout and core.loadout.gems and (ctrl.cooldown_category == 'Spells' or ctrl.cooldown_category == 'All') then
        for i, g in ipairs(core.loadout.gems) do
            local spName = g and (g.spell or g.name)
            local pctVal = tonumber(g and g.pct) or 100
            local isEnabled = (g and g.enabled ~= false) and (pctVal > 0)
            if g and isEnabled and spName and spName ~= '' then
                local slot = tonumber(g.gem) or math.min(i, 12)
                local isReady = false
                local timerSec = 0
                pcall(function()
                    isReady = mq.TLO.Me.SpellReady(slot)() or false
                    local gt = mq.TLO.Me.GemTimer(slot)
                    if gt and gt() then
                        timerSec = core.parseDurationSec(gt)
                        if timerSec >= 3600 then timerSec = 0 end
                    end
                end)
                local condText = string.format('Gem %d: %s (%s %d%%)', slot, g.target or 'Target', g.when or 'in combat', pctVal)
                table.insert(items, {
                    kind = 'Spell',
                    typeLabel = 'Gem ' .. tostring(slot),
                    cls = g.cls or (core.myClasses and core.myClasses[1]) or 'War',
                    name = spName,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = math.max(timerSec, 5),
                    status = isReady and 'READY' or 'COOLDOWN',
                    reason = '',
                    priority = i * 10,
                    burn_only = g.burn_only or false,
                    autoskill = false,
                    min_xtar = 1,
                    entry = g,
                    conditionText = condText,
                    use = function() rt.castGem(slot, g) end,
                })
            end
        end
    end

    -- 5. Clickies (Items) - when category includes Items or All
    if core.loadout and core.loadout.clickies and (ctrl.cooldown_category == 'Items' or ctrl.cooldown_category == 'All') then
        for _, c in ipairs(core.loadout.clickies) do
            if c and c.enabled and c.name and c.name ~= '' then
                local isReady = false
                local timerSec = 0
                pcall(function()
                    isReady = mq.TLO.Me.ItemReady(c.name)() or false
                    local itm = mq.TLO.FindItem(c.name)
                    if itm and itm() then
                        if itm.TimerReady then
                            local tr = itm.TimerReady()
                            if type(tr) == 'number' and tr > 0 then
                                timerSec = tr > 1800 and (tr / 1000.0) or tr
                            end
                        elseif itm.Timer and itm.Timer() then
                            timerSec = core.parseDurationSec(itm.Timer)
                        end
                    end
                end)
                local condText = string.format('%s (%s %d%%)', c.target or 'Myself', c.when or 'in combat', tonumber(c.pct) or 100)
                table.insert(items, {
                    kind = 'Item',
                    typeLabel = 'Item',
                    cls = c.cls or (core.myClasses and core.myClasses[1]) or 'War',
                    name = c.name,
                    timerGroup = nil,
                    ready = isReady,
                    active = false,
                    activeSec = 0,
                    activeTotalSec = 0,
                    timeLeft = timerSec,
                    totalSec = math.max(timerSec, 30),
                    status = isReady and 'READY' or 'COOLDOWN',
                    reason = '',
                    priority = 60,
                    burn_only = c.burn_only or false,
                    autoskill = false,
                    min_xtar = 1,
                    entry = c,
                    conditionText = condText,
                    use = function() rt.useClickie(c) end,
                })
            end
        end
    end

    return items
end

function M.renderCooldownContent(idSuffix, isPopout)
    idSuffix = idSuffix or ''
    local allItems = M.getTrackedCooldownItems()

    -- Count totals
    local countReady = 0
    local countActive = 0
    local countCooldown = 0
    for _, itm in ipairs(allItems) do
        if itm.active then countActive = countActive + 1
        elseif itm.status == 'READY' then countReady = countReady + 1
        else countCooldown = countCooldown + 1 end
    end

    -- Header Line 1: Metrics Strip & Quick View Toggles
    accent(ARC, 'COOLDOWNS')
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOOD, string.format('R:%d', countReady))
    ImGui.SameLine(); accent(ARC, string.format('A:%d', countActive))
    ImGui.SameLine(); accent(WARN, string.format('CD:%d', countCooldown))

    if not isPopout then
        ImGui.SameLine()
        if ImGui.Button('Popout Window##cdTabPop' .. idSuffix) then
            ctrl.show_cooldowns = true
            core.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Opens the standalone popout Cooldown & Ability Monitor window.')
        end
    end

    -- Right-aligned Quick Controls
    ImGui.SameLine()
    local isTableView = (ctrl.cooldown_view_mode ~= 'cards')
    if ImGui.Button((isTableView and 'HUD##cdView' or 'Table##cdView') .. idSuffix, 44, 18) then
        ctrl.cooldown_view_mode = isTableView and 'cards' or 'table'
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Toggle Table View / Compact HUD Cards') end

    if isPopout then
        ImGui.SameLine()
        local lockVal = ImGui.Checkbox('Lock##cdLock' .. idSuffix, ctrl.cooldown_locked or false)
        if lockVal ~= ctrl.cooldown_locked then
            ctrl.cooldown_locked = lockVal
            core.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then core.setTooltip('Lock window position and hide borders') end
    end

    ImGui.SameLine()
    local isCmp = (ctrl.cooldown_compact ~= false)
    local cmpVal = ImGui.Checkbox('Compact##cdCmp' .. idSuffix, isCmp)
    if cmpVal ~= isCmp then
        ctrl.cooldown_compact = cmpVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Ultra-compact mode (streamlined columns)') end

    ImGui.SameLine()
    local editVal = ImGui.Checkbox('Tune##cdEdit' .. idSuffix, ctrl.cooldown_show_inline_edit or false)
    if editVal ~= ctrl.cooldown_show_inline_edit then
        ctrl.cooldown_show_inline_edit = editVal
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Show inline core.loadout tuning controls (Enabled, HP %, Burn)') end

    -- Header Line 2: Streamlined Filters & Search
    -- Category Dropdown
    ImGui.SetNextItemWidth(72)
    local CAT_OPTS = { 'All', 'Skills', 'AAs', 'Discs', 'Spells', 'Items' }
    local CAT_MAP = { All = 'All', Skills = 'Abilities', AAs = 'AAs', Discs = 'Disciplines', Spells = 'Spells', Items = 'Items' }
    local REV_CAT = { All = 'All', Abilities = 'Skills', AAs = 'AAs', Disciplines = 'Discs', Spells = 'Spells', Items = 'Items' }
    local curCatLabel = REV_CAT[ctrl.cooldown_category or 'All'] or 'All'
    local curCatIdx = core.idxOf(CAT_OPTS, curCatLabel)
    local newCatIdx = ImGui.Combo('##cdCat' .. idSuffix, curCatIdx, CAT_OPTS)
    if newCatIdx ~= curCatIdx then
        ctrl.cooldown_category = CAT_MAP[CAT_OPTS[newCatIdx]] or 'All'
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Filter by ability category') end

    ImGui.SameLine()
    -- Status Filter Dropdown
    ImGui.SetNextItemWidth(68)
    local STATUS_OPTS = { 'All', 'Ready', 'CD', 'Active' }
    local STATUS_MAP = { All = 'All', Ready = 'Ready', CD = 'Cooldown', Active = 'Active' }
    local REV_STATUS = { All = 'All', Ready = 'Ready', Cooldown = 'CD', Active = 'Active' }
    local curStatusLabel = REV_STATUS[ctrl.cooldown_status_filter or 'All'] or 'All'
    local curStatusIdx = core.idxOf(STATUS_OPTS, curStatusLabel)
    local newStatusIdx = ImGui.Combo('##cdStatusFilter' .. idSuffix, curStatusIdx, STATUS_OPTS)
    if newStatusIdx ~= curStatusIdx then
        ctrl.cooldown_status_filter = STATUS_MAP[STATUS_OPTS[newStatusIdx]] or 'All'
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Filter by readiness status') end

    ImGui.SameLine()
    -- Sort Selector
    ImGui.SetNextItemWidth(70)
    local SORT_LABELS = { 'Time', 'Status', 'Pri', 'Cls', 'Type', 'A-Z' }
    local SORT_KEYS = { 'time', 'status', 'priority', 'class', 'type', 'alpha' }
    local curSortIdx = core.idxOf(SORT_KEYS, ctrl.cooldown_sort_by or 'time')
    local newSortIdx = ImGui.Combo('##cdSortBy' .. idSuffix, curSortIdx, SORT_LABELS)
    if newSortIdx ~= curSortIdx then
        ctrl.cooldown_sort_by = SORT_KEYS[newSortIdx]
        core.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then core.setTooltip('Sort items by time, status, priority, or class') end

    ImGui.SameLine()
    -- Search Input
    ImGui.SetNextItemWidth(105)
    M.cooldownSearch = ImGui.InputTextWithHint('##cdSearch' .. idSuffix, 'Search...', M.cooldownSearch or '', 64)

    if isPopout then
        ImGui.SameLine()
        -- Transparency Slider
        ImGui.SetNextItemWidth(55)
        local newAlpha = ImGui.SliderFloat('##cdAlpha' .. idSuffix, ctrl.cooldown_alpha or 0.90, 0.10, 1.00, '%.2f')
        if newAlpha ~= ctrl.cooldown_alpha then
            ctrl.cooldown_alpha = newAlpha
        end
        if ImGui.IsItemHovered() then core.setTooltip(string.format('Overlay transparency (current: %.2f)', ctrl.cooldown_alpha or 0.90)) end
    end

    ImGui.Separator()

    -- Filter items based on active criteria
    local filteredItems = {}
    local searchStr = (M.cooldownSearch or ''):lower()
    for _, itm in ipairs(allItems) do
        local passCat = true
        if ctrl.cooldown_category == 'Abilities' then passCat = (itm.kind == 'Skill')
        elseif ctrl.cooldown_category == 'AAs' then passCat = (itm.kind == 'AA')
        elseif ctrl.cooldown_category == 'Disciplines' then passCat = (itm.kind == 'Disc')
        elseif ctrl.cooldown_category == 'Spells' then passCat = (itm.kind == 'Spell')
        elseif ctrl.cooldown_category == 'Items' then passCat = (itm.kind == 'Item')
        end

        local passStatus = true
        if ctrl.cooldown_status_filter == 'Ready' then passStatus = itm.ready
        elseif ctrl.cooldown_status_filter == 'Cooldown' then passStatus = (not itm.ready and not itm.active)
        elseif ctrl.cooldown_status_filter == 'Active' then passStatus = itm.active
        end

        local passSearch = true
        if searchStr ~= '' then
            passSearch = string.find(itm.name:lower(), searchStr, 1, true) ~= nil
        end

        if passCat and passStatus and passSearch then
            table.insert(filteredItems, itm)
        end
    end

    -- Sort filtered items
    local sortKey = ctrl.cooldown_sort_by or 'time'
    table.sort(filteredItems, function(a, b)
        if sortKey == 'time' then
            -- 1. Active items first (running stances / active duration buffs)
            if a.active ~= b.active then
                return a.active
            end
            if a.active and b.active then
                return (a.activeSec or 0) < (b.activeSec or 0)
            end

            -- 2. Items on Cooldown NEXT at the top of the list
            local aInCd = (not a.ready)
            local bInCd = (not b.ready)
            if aInCd ~= bInCd then
                return aInCd
            end

            -- Both are on cooldown: sort by time remaining ascending (soonest to become ready first)
            if aInCd and bInCd then
                if math.abs((a.timeLeft or 0) - (b.timeLeft or 0)) > 0.05 then
                    return (a.timeLeft or 0) < (b.timeLeft or 0)
                end
                return (a.priority or 50) < (b.priority or 50)
            end

            -- 3. Both are Ready: sort by priority ascending (pri 1 before pri 50)
            if (a.priority or 50) ~= (b.priority or 50) then
                return (a.priority or 50) < (b.priority or 50)
            end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'status' then
            local statusRank = {
                ACTIVE = 1,
                COOLDOWN = 2,
                ['LOW END'] = 3,
                ['LOW MANA'] = 4,
                ['NEED BURN'] = 5,
                ['NEED BOSS'] = 6,
                ['MIN XTAR'] = 7,
                LOCKED = 8,
                BLOCKED = 9,
                READY = 10,
            }
            local rA = statusRank[a.status] or 11
            local rB = statusRank[b.status] or 11
            if rA ~= rB then return rA < rB end
            return (a.timeLeft or 0) < (b.timeLeft or 0)
        elseif sortKey == 'priority' then
            return (a.priority or 50) < (b.priority or 50)
        elseif sortKey == 'class' then
            if (a.cls or '') ~= (b.cls or '') then return (a.cls or '') < (b.cls or '') end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'type' then
            if (a.kind or '') ~= (b.kind or '') then return (a.kind or '') < (b.kind or '') end
            return (a.name or '') < (b.name or '')
        elseif sortKey == 'alpha' then
            return (a.name or ''):lower() < (b.name or ''):lower()
        end
        return false
    end)

    -- Render Items in Table View or Cards HUD View
    if #filteredItems == 0 then
        if #allItems == 0 then
            accent(MUTED, '  (No abilities, AAs, or disciplines enabled in core.loadout.)')
        else
            accent(MUTED, '  (No abilities match current filters.)')
        end
    elseif isTableView then
        -- Compact Table View
        local tableFlags = bit.bor(
            ImGuiTableFlags.Borders,
            ImGuiTableFlags.RowBg,
            ImGuiTableFlags.Resizable,
            ImGuiTableFlags.ScrollY,
            ImGuiTableFlags.SizingFixedFit
        )
        local isCompactMode = (ctrl.cooldown_compact ~= false)
        local colCount = isCompactMode and 4 or 6
        if ctrl.cooldown_show_inline_edit then colCount = colCount + 1 end

        if ImGui.BeginTable('##TriuneCooldownTable' .. idSuffix, colCount, tableFlags) then
            ImGui.TableSetupColumn('Cls', ImGuiTableColumnFlags.WidthFixed, 28)
            if not isCompactMode then
                ImGui.TableSetupColumn('Type', ImGuiTableColumnFlags.WidthFixed, 55)
            end
            ImGui.TableSetupColumn('Ability Name', ImGuiTableColumnFlags.WidthStretch, 130)
            if not isCompactMode then
                ImGui.TableSetupColumn('Trigger / Cond', ImGuiTableColumnFlags.WidthStretch, 110)
            end
            ImGui.TableSetupColumn('Status & Timer', ImGuiTableColumnFlags.WidthFixed, 115)
            if ctrl.cooldown_show_inline_edit then
                ImGui.TableSetupColumn('Tuning', ImGuiTableColumnFlags.WidthFixed, 120)
            end
            ImGui.TableSetupColumn('Act', ImGuiTableColumnFlags.WidthFixed, 36)
            ImGui.TableHeadersRow()

            for _, itm in ipairs(filteredItems) do
                ImGui.TableNextRow()
                ImGui.PushID('cdrow_' .. idSuffix .. '_' .. itm.kind .. '_' .. tostring(itm.cls) .. '_' .. tostring(itm.name))

                -- 1. Class Badge
                ImGui.TableNextColumn()
                local r, g, b, a = core.classColor(itm.cls)
                ImGui.TextColored(r, g, b, a, itm.cls) ---@diagnostic disable-line: param-type-mismatch
                if ImGui.IsItemHovered() then core.setTooltip(string.format('Class: %s', itm.cls)) end

                -- Optional Type Column
                if not isCompactMode then
                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(itm.typeLabel or itm.kind)
                    if itm.timerGroup and ImGui.IsItemHovered() then
                        core.setTooltip(string.format('EQ Timer Group: %s', itm.timerGroup))
                    end
                end

                -- 2. Ability Name
                ImGui.TableNextColumn()
                ImGui.Text(itm.name)
                if itm.timerGroup then
                    ImGui.SameLine()
                    accent(ARC, '[' .. itm.timerGroup .. ']')
                end
                if ImGui.IsItemHovered() then
                    local desc = string.format('%s (%s)\nPriority: %d\nTrigger: %s',
                        itm.name, itm.typeLabel or itm.kind, itm.priority or 50, itm.conditionText or '')
                    if itm.reason and itm.reason ~= '' then
                        desc = desc .. '\nStatus Note: ' .. itm.reason
                    end
                    if itm.timerGroup then
                        desc = desc .. string.format('\nShared EQ Timer Group: %s', itm.timerGroup)
                    end
                    core.setTooltip(desc)
                end

                -- Optional Trigger / Condition Column
                if not isCompactMode then
                    ImGui.TableNextColumn()
                    ImGui.Text(itm.conditionText or '')
                    if itm.burn_only then
                        ImGui.SameLine(); accent({ 1.0, 0.35, 0.35, 1.0 }, '[B]')
                    end
                    if itm.boss_only then
                        ImGui.SameLine(); accent(GOLD, '[Boss]')
                    end
                end

                -- 3. Status Bar & Timer
                ImGui.TableNextColumn()
                if itm.active then
                    local actTotal = (itm.activeTotalSec and itm.activeTotalSec > 0) and itm.activeTotalSec or (itm.totalSec > 0 and itm.totalSec or 18)
                    local frac = math.min(1.0, math.max(0.0, (itm.activeSec or 0) / actTotal))
                    local tStr = (itm.activeSec and itm.activeSec > 0) and string.format('ACT: %s', core.fmtSec(math.ceil(itm.activeSec))) or 'ACTIVE'
                    core.drawStatusProgressBar(frac, 110, 15, tStr, ARC[1], ARC[2], ARC[3], 1.0)
                elseif itm.ready then
                    if itm.status ~= 'READY' then
                        -- Gated ready (e.g. LOW END, NEED BURN, MIN XTAR, BLOCKED)
                        core.drawStatusProgressBar(1.0, 110, 15, itm.status, 0.85, 0.55, 0.15, 1.0)
                    else
                        core.drawStatusProgressBar(1.0, 110, 15, 'READY', GOOD[1], GOOD[2], GOOD[3], 1.0)
                    end
                else
                    local cdTotal = (itm.totalSec and itm.totalSec > 0) and itm.totalSec or math.max(itm.timeLeft or 0, 30)
                    local frac = math.max(0.0, math.min(1.0, 1.0 - ((itm.timeLeft or 0) / cdTotal)))
                    local tStr = core.fmtSec(math.ceil(itm.timeLeft or 0))
                    core.drawStatusProgressBar(frac, 110, 15, tStr, WARN[1], WARN[2], WARN[3], 1.0)
                end
                if itm.reason and itm.reason ~= '' and ImGui.IsItemHovered() then
                    core.setTooltip(itm.reason)
                end

                -- Optional In-Place Tuning Column
                if ctrl.cooldown_show_inline_edit then
                    ImGui.TableNextColumn()
                    if itm.entry then
                        local enVal = ImGui.Checkbox('##tblEn', itm.entry.enabled or false)
                        itm.entry.enabled = enVal
                        if itm.entry.pct ~= nil then
                            ImGui.SameLine(); ImGui.SetNextItemWidth(55)
                            local spVal = ImGui.SliderInt('##tblPct', tonumber(itm.entry.pct) or 100, 0, 100, '%d%%')
                            itm.entry.pct = spVal
                        end
                        if itm.entry.burn_only ~= nil then
                            ImGui.SameLine()
                            local boVal = ImGui.Checkbox('B##tblBo', itm.entry.burn_only or false)
                            itm.entry.burn_only = boVal
                            if ImGui.IsItemHovered() then core.setTooltip('Burn Only toggle') end
                        end
                    end
                end

                -- 4. Direct Action Button
                ImGui.TableNextColumn()
                if itm.ready and not itm.active then
                    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                    local pCount = 0
                    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
                    if Col and pcall(ImGui.PushStyleColor, Col.ButtonHovered, 0.18, 0.70, 0.28, 1.0) then pCount = pCount + 1 end
                    if Col and pcall(ImGui.PushStyleColor, Col.Text, 1.0, 1.0, 1.0, 1.0) then pCount = pCount + 1 end
                    if ImGui.Button('Use##cdBtnUse', 34, 16) then
                        if itm.use then itm.use() end
                    end
                    if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
                    if ImGui.IsItemHovered() then core.setTooltip(string.format('Click to execute %s', itm.name)) end
                else
                    ImGui.TextDisabled(' --')
                end

                ImGui.PopID()
            end

            ImGui.EndTable()
        end
    else
        -- Compact HUD Cards View
        if ImGui.BeginChild('##TriuneCooldownCardsList' .. idSuffix, 0, 0, false, ImGuiWindowFlags and ImGuiWindowFlags.HorizontalScrollbar or 0) then
            for _, itm in ipairs(filteredItems) do
                ImGui.PushID('card_' .. idSuffix .. '_' .. itm.kind .. '_' .. tostring(itm.cls) .. '_' .. tostring(itm.name))

                local r, g, b, a = core.classColor(itm.cls)
                ImGui.TextColored(r, g, b, a, string.format('[%s]', itm.cls)) ---@diagnostic disable-line: param-type-mismatch
                ImGui.SameLine()

                ImGui.Text(itm.name)
                if itm.timerGroup then
                    ImGui.SameLine()
                    accent(ARC, '[' .. itm.timerGroup .. ']')
                end

                ImGui.SameLine(); ImGui.SetNextItemWidth(105)
                if itm.active then
                    local actTotal = (itm.activeTotalSec and itm.activeTotalSec > 0) and itm.activeTotalSec or (itm.totalSec > 0 and itm.totalSec or 18)
                    local frac = math.min(1.0, math.max(0.0, (itm.activeSec or 0) / actTotal))
                    local tStr = (itm.activeSec and itm.activeSec > 0) and string.format('ACT: %s', core.fmtSec(math.ceil(itm.activeSec))) or 'ACTIVE'
                    core.drawStatusProgressBar(frac, 105, 15, tStr, ARC[1], ARC[2], ARC[3], 1.0)
                elseif itm.ready then
                    if itm.status ~= 'READY' then
                        core.drawStatusProgressBar(1.0, 105, 15, itm.status, 0.85, 0.55, 0.15, 1.0)
                    else
                        core.drawStatusProgressBar(1.0, 105, 15, 'READY', GOOD[1], GOOD[2], GOOD[3], 1.0)
                    end
                else
                    local cdTotal = (itm.totalSec and itm.totalSec > 0) and itm.totalSec or math.max(itm.timeLeft or 0, 30)
                    local frac = math.max(0.0, math.min(1.0, 1.0 - ((itm.timeLeft or 0) / cdTotal)))
                    local tStr = core.fmtSec(math.ceil(itm.timeLeft or 0))
                    core.drawStatusProgressBar(frac, 105, 15, tStr, WARN[1], WARN[2], WARN[3], 1.0)
                end

                if itm.ready and not itm.active then
                    ImGui.SameLine()
                    local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                    local pCount = 0
                    if Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.55, 0.22, 1.0) then pCount = pCount + 1 end
                    if ImGui.Button('Use##cardUse', 34, 15) then
                        if itm.use then itm.use() end
                    end
                    if pCount > 0 then pcall(ImGui.PopStyleColor, pCount) end
                end

                ImGui.PopID()
            end
        end
        ImGui.EndChild()
    end
end

function M.drawCooldownWindow()
    if not ctrl.show_cooldowns then return end
    core.pushTheme()

    if ctrl.cooldown_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.cooldown_alpha)
    end
    ImGui.SetNextWindowSize(500, 340, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.cooldown_locked then
        winFlags = bit.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoMove)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 3, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4, 3)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 3, 2)

    core.preBeginWindow('cooldowns')
    local show
    ctrl.show_cooldowns, show = ImGui.Begin('Triune Cooldown Monitor v' .. (core.VERSION or '') .. '###triuneCooldowns', ctrl.show_cooldowns, winFlags)
    if not ctrl.show_cooldowns then
        ImGui.End()
        ImGui.PopStyleVar(3)
        core.popTheme()
        return
    end

    if show then
        core.postBeginWindow('cooldowns')
        M.renderCooldownContent('_win', true)
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    core.popTheme()
end

-- Popout window
function plugin.onDrawUI()
    if not core then return end
    refresh()
    M.drawCooldownWindow()
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    accent(GOLD, 'Cooldown Monitor')
    local isWinOpen = (ctrl.show_cooldowns == true)
    if ImGui.Button((isWinOpen and 'Popout Window: Visible (Click to Hide)' or 'Popout Window: Hidden (Click to Show)') .. '##cdToggleWin', 280, 24) then
        ctrl.show_cooldowns = not isWinOpen
        core.saveLoadout(true)
    end
    local lockVal = ImGui.Checkbox('Lock Popout Position & Size##cdLock', ctrl.cooldown_locked or false)
    if lockVal ~= (ctrl.cooldown_locked or false) then
        ctrl.cooldown_locked = lockVal
        core.saveLoadout(true)
    end
    ImGui.SetNextItemWidth(120)
    local newAlpha = ImGui.SliderFloat('Popout Opacity##cdAlpha', ctrl.cooldown_alpha or 0.90, 0.20, 1.0, '%.2f')
    if newAlpha ~= (ctrl.cooldown_alpha or 0.90) then
        ctrl.cooldown_alpha = newAlpha
        core.saveLoadout(true)
    end
    ImGui.TextDisabled('Filters, sorting, and per-item tracking live on the Cooldown Monitor window itself.')
end

plugin.M = M
return plugin
