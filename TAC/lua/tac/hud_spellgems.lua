---@diagnostic disable: undefined-global, undefined-field
-- ============================================================================
-- TAC/lua/tac/hud_spellgems.lua — Triune Popout Spell Gem Bar Plugin
-- ============================================================================
-- Modern, compact, customizable replacement for EverQuest's default spell gem
-- bar: dual orientations, compact vs full layouts, live recast timers, active
-- casting overlays, spell-set presets, and right-click actions.
--
-- Render-only plugin driven by ctrl.show_spell_gems; the header buttons, Mini
-- HUD, window manager, and /ac gems keep working unchanged. Gem cooldowns are
-- read from runtime.gemCooldownEnd / gemCooldownSpell (owned by the caster).
-- ============================================================================

local plugin = {
    id                 = 'hud_spellgems',
    name               = 'Spell Gem Bar HUD',
    version            = '1.0.0',
    author             = 'Triune',
    description        = 'Popout spell gem bar with recast timers, casting overlays, spell-set presets, and right-click actions.',
    defaultEnabled     = true,
    tickInterval       = 1.0,
    runOutOfCombatOnly = false,
    hasThread          = false,
    -- Window owned by this plugin (drives the main-window header button)
    window             = { label = 'Gems', tooltip = 'Toggles the popout Spell Gem Bar window.', flag = 'show_spell_gems', key = 'spell_gems', lockFlag = 'gem_lock', desc = 'Popout Spell Gem Bar', headerButton = true, order = 100 },
}

local core = nil
local rt, ctrl, ImGui, mq, accent = nil, nil, nil, nil, nil
local GOLD = nil
local M = { newSpellSetName = '', gemCooldownEnd = {}, gemCooldownSpell = {} }

-- Opens the Spellbook Browser plugin window (was: /lua run triune_spellbook).
local function openSpellbook()
    local pm = core.runtime and core.runtime.pluginManager
    if pm and pm.setWindowOpen and pm.getWindow and pm.getWindow('spellbook') then
        pm.setWindowOpen('spellbook', true)
        return
    end
    -- Fallback when the manager is unavailable: flip the flag directly.
    ctrl.show_spellbook = true
    core.saveLoadout(true)
end

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
    if ctrl and ctrl.show_spell_gems == nil then ctrl.show_spell_gems = false end
end

function plugin.onDestroy()
end

function M.drawSpellGemBarWindow()
    if not ctrl.show_spell_gems then return end
    core.pushTheme()

    if ctrl.gem_alpha then
        ImGui.SetNextWindowBgAlpha(ctrl.gem_alpha)
    end

    ImGui.SetNextWindowSize(320, 38, ImGuiCond.FirstUseEver)

    local winFlags = 0
    if ctrl.gem_lock then
        winFlags = bit.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 2, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 2, 2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 1, 1)

    core.preBeginWindow('spell_gems')
    local show
    ctrl.show_spell_gems, show = ImGui.Begin('Triune Spell Gems v' .. (core.VERSION or '') .. '###triuneSpellGemsWindow', ctrl.show_spell_gems, winFlags)
    if not ctrl.show_spell_gems then
        ImGui.End()
        ImGui.PopStyleVar(3)
        core.popTheme()
        return
    end

    if show then
        core.postBeginWindow('spell_gems')
        -- Right-click on window background for settings
        local function renderGemSettingsContent()
            accent(GOLD, 'Spell Gem Bar Options')
            ImGui.Separator()

            local lockVal = ImGui.Checkbox('Lock Window Position & Size##gemLock', ctrl.gem_lock or false)
            if lockVal ~= (ctrl.gem_lock or false) then
                ctrl.gem_lock = lockVal
                core.saveLoadout(true)
            end

            -- Orientation selection
            ImGui.Text('Orientation:')
            ImGui.SameLine()
            if ImGui.RadioButton('Auto##gemOrientAuto', ctrl.gem_orientation == 'Auto' or not ctrl.gem_orientation) then
                ctrl.gem_orientation = 'Auto'
                core.saveLoadout(true)
            end
            ImGui.SameLine()
            if ImGui.RadioButton('Horizontal##gemOrientH', ctrl.gem_orientation == 'Horizontal') then
                ctrl.gem_orientation = 'Horizontal'
                core.saveLoadout(true)
            end
            ImGui.SameLine()
            if ImGui.RadioButton('Vertical##gemOrientV', ctrl.gem_orientation == 'Vertical') then
                ctrl.gem_orientation = 'Vertical'
                core.saveLoadout(true)
            end

            local badgeVal = ImGui.Checkbox('Show Gem Numbers (#1..#N)##gemBadges', ctrl.gem_show_badges ~= false)
            if badgeVal ~= (ctrl.gem_show_badges ~= false) then
                ctrl.gem_show_badges = badgeVal
                core.saveLoadout(true)
            end

            local timerVal = ImGui.Checkbox('Show Cooldown Timers##gemTimer', ctrl.gem_show_timer ~= false)
            if timerVal ~= (ctrl.gem_show_timer ~= false) then
                ctrl.gem_show_timer = timerVal
                core.saveLoadout(true)
            end

            ImGui.SetNextItemWidth(120)
            local newAlpha = ImGui.SliderFloat('Opacity##gemAlpha', ctrl.gem_alpha or 0.85, 0.20, 1.0, '%.2f')
            if newAlpha ~= (ctrl.gem_alpha or 0.85) then
                ctrl.gem_alpha = newAlpha
                core.saveLoadout(true)
            end

            ImGui.Separator()
            if ImGui.MenuItem('Open Spellbook##gemOpenBook') then
                openSpellbook()
            end
        end

        if ImGui.BeginPopupContextWindow('##gemWinContextMenu') then
            renderGemSettingsContent()
            ImGui.EndPopup()
        end

        local availW, availH = ImGui.GetContentRegionAvail()
        availW = math.max(24, availW)
        availH = math.max(24, availH)

        local maxGems = core.getNumGems() or 8
        local totalItems = maxGems + 1
        local spacing = 2
        local cols = 1  -- luacheck: ignore 311

        -- Dynamic layout: horizontal, vertical, or responsive aspect ratio grid
        if ctrl.gem_orientation == 'Horizontal' then
            cols = totalItems
        elseif ctrl.gem_orientation == 'Vertical' then
            cols = 1
        else -- 'Auto' (stretches smoothly either horizontally or vertically)
            if availW >= availH * 1.25 then
                cols = totalItems
            elseif availH >= availW * 1.25 then
                cols = 1
            else
                local bestCols = 1
                local bestDiff = 999999
                for c = 1, totalItems do
                    local r = math.ceil(totalItems / c)
                    local w = (availW - (spacing * (c - 1))) / c
                    local h = (availH - (spacing * (r - 1))) / r
                    local diff = math.abs(w - h)
                    if diff < bestDiff then
                        bestDiff = diff
                        bestCols = c
                    end
                end
                cols = bestCols
            end
        end

        local rows = math.max(1, math.ceil(totalItems / cols))
        local btnW = math.max(18, math.floor((availW - (spacing * (cols - 1))) / cols))
        local btnH = math.max(18, math.floor((availH - (spacing * (rows - 1))) / rows))
        local iconSize = math.max(14, math.min(btnW - 4, btnH - 4))

        local myMana = 0
        pcall(function() myMana = mq.TLO.Me.CurrentMana() or 0 end)

        local activeCastingName = nil
        local castTimeLeft = 0
        pcall(function()
            if mq.TLO.Me.Casting() then
                activeCastingName = mq.TLO.Me.Casting.Name()
                castTimeLeft = (mq.TLO.Me.CastTimeLeft() or 0) / 1000.0
            end
        end)

        local nowClock = os.clock()
        M.gemCooldownEnd = M.gemCooldownEnd or {}

        local toXY = function(x, y)
            if type(x) == 'userdata' or (type(x) == 'table' and x.x) then
                return x.x, x.y
            end
            return x or 0, y or 0
        end

        local toV = core.toVec

        for slot = 1, maxGems do
            local gemData = nil
            pcall(function()
                local g = mq.TLO.Me.Gem(slot)
                if g and g() and g.Name() and g.Name() ~= '' then
                    local sName = g.Name()
                    local sId = g.ID() or 0
                    local sLvl = g.Level() or 0
                    local sMana = g.Mana() or 0
                    local sIcon = g.SpellIcon() or 0
                    local sRange = g.Range() or 0
                    local sCastTime = (g.MyCastTime() or g.CastTime() or 0) / 1000.0
                    local sRecast = core.parseSpellRecastTime(g)
                    if sRecast == 0 then
                        local rt = tonumber(g.RecastTime and g.RecastTime() or 0) or 0
                        if rt > 86400 then
                            sRecast = rt / 1000.0
                        elseif rt > 0 then
                            sRecast = rt
                        end
                    end
                    local querySec = core.getGemCooldownSec(slot, sName, sRecast)

                    M.gemCooldownSpell = M.gemCooldownSpell or {}
                    if M.gemCooldownSpell[slot] ~= sName then
                        M.gemCooldownSpell[slot] = sName
                        M.gemCooldownEnd[slot] = nil
                    end

                    local isReady = false
                    pcall(function() isReady = (mq.TLO.Me.SpellReady(slot)() == true) end)

                    local isCastingThis = (activeCastingName and activeCastingName == sName)
                    local timer = 0
                    if isReady then
                        M.gemCooldownEnd[slot] = nil
                    elseif isCastingThis then
                        -- Actively casting this spell: prime recast countdown so it begins immediately on cast completion
                        local baseRecast = math.max(2.25, sRecast or 0)
                        M.gemCooldownEnd[slot] = nowClock + (castTimeLeft or 0) + baseRecast
                    else
                        local endAt = M.gemCooldownEnd[slot]
                        local isOtherCasting = (activeCastingName and activeCastingName ~= sName)
                        local baseRecast = isOtherCasting and 2.25 or (querySec > 0 and querySec or 2.25)
                        local maxAllowed = (sRecast and sRecast > 0) and math.max(2.5, sRecast + 3.0) or 3.0

                        if not endAt then
                            local dur = (querySec > 0) and querySec or baseRecast
                            dur = math.min(dur, maxAllowed)
                            endAt = nowClock + dur
                            M.gemCooldownEnd[slot] = endAt
                            timer = dur
                        else
                            local rem = endAt - nowClock
                            if rem > maxAllowed then
                                rem = maxAllowed
                                endAt = nowClock + maxAllowed
                                M.gemCooldownEnd[slot] = endAt
                            end

                            if rem > 0 then
                                timer = rem
                            else
                                if querySec > 0 then
                                    local dur = math.min(querySec, maxAllowed)
                                    endAt = nowClock + dur
                                    M.gemCooldownEnd[slot] = endAt
                                    timer = dur
                                else
                                    timer = 0
                                end
                            end
                        end
                    end
                    local ready = isReady or (timer <= 0.05 and not activeCastingName)

                    gemData = {
                        slot = slot,
                        name = sName,
                        id = sId,
                        level = sLvl,
                        mana = sMana,
                        icon = sIcon,
                        range = sRange,
                        castTime = sCastTime,
                        recast = sRecast,
                        timer = timer,
                        ready = ready,
                    }
                end
            end)

            if (slot - 1) % cols ~= 0 then
                ImGui.SameLine(0, spacing)
            end

            local btnKey = 'gemBtn_' .. tostring(slot)

            if gemData then
                local isCastingThis = (activeCastingName and activeCastingName == gemData.name)
                local hasMana = (gemData.mana == 0 or myMana >= gemData.mana)

                -- Visual button frame styling based on state
                local stylePushed = 0
                local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
                if isCastingThis then
                    if Col and Col.Border then
                        ImGui.PushStyleColor(Col.Border, 0.20, 0.85, 1.0, 1.0)
                        stylePushed = stylePushed + 1
                    end
                elseif not gemData.ready then
                    if Col and Col.Button then
                        ImGui.PushStyleColor(Col.Button, 0.12, 0.12, 0.14, 0.70)
                        stylePushed = stylePushed + 1
                    end
                elseif not hasMana then
                    if Col and Col.Button then
                        ImGui.PushStyleColor(Col.Button, 0.35, 0.12, 0.12, 0.65)
                        stylePushed = stylePushed + 1
                    end
                end

                local clicked = ImGui.Button('##' .. btnKey, btnW, btnH)
                if clicked then
                    mq.cmdf('/cast %d', slot)
                    local estRecast = math.max(2.25, gemData.recast or 0)
                    M.gemCooldownEnd[slot] = nowClock + (gemData.castTime or 0) + estRecast
                end

                if stylePushed > 0 then
                    ImGui.PopStyleColor(stylePushed)
                end

                local mnX, mnY = ImGui.GetItemRectMin()
                local mxX, mxY = ImGui.GetItemRectMax()
                local mX, mY = toXY(mnX, mnY)
                local maxX, maxY = toXY(mxX, mxY)
                local dl = ImGui.GetWindowDrawList()

                -- Draw authentic spell icon centered in button
                if dl and dl.AddTextureAnimation then
                    local tex = core.getSpellIconAnimation(gemData.icon)
                    if tex then
                        local iconX = mX + math.floor((btnW - iconSize) / 2)
                        local iconY = mY + math.floor((btnH - iconSize) / 2)
                        local pPos = toV(iconX, iconY)
                        local pSz = toV(iconSize, iconSize)
                        if pPos and pSz then
                            dl:AddTextureAnimation(tex, pPos, pSz)
                        end
                    end
                end

                -- Gem slot # badge
                if ctrl.gem_show_badges ~= false and dl and dl.AddText then
                    local bCol = isCastingThis and core.col32(0.2, 0.85, 1.0, 1.0) or core.col32(1.0, 0.85, 0.25, 0.95)
                    local p1 = toV(mX + 1, mY + 2)
                    local p2 = toV(mX + 2, mY + 1)
                    if p1 then dl:AddText(p1, core.col32(0, 0, 0, 0.85), string.format('%d', slot)) end
                    if p2 then dl:AddText(p2, bCol, string.format('%d', slot)) end
                end

                -- Low mana overlay
                if not hasMana and dl and dl.AddRectFilled then
                    local p1 = toV(mX + 1, mY + 1)
                    local p2 = toV(maxX - 1, maxY - 1)
                    if p1 and p2 then
                        dl:AddRectFilled(p1, p2, core.col32(0.65, 0.12, 0.12, 0.45), 3)
                    end
                end

                -- Recast cooldown overlay (seconds countdown)
                if not isCastingThis and not gemData.ready and gemData.timer > 0.05 and dl then
                    if dl.AddRectFilled then
                        local p1 = toV(mX + 1, mY + 1)
                        local p2 = toV(maxX - 1, maxY - 1)
                        if p1 and p2 then
                            dl:AddRectFilled(p1, p2, core.col32(0, 0, 0, 0.65), 3)
                        end
                    end
                    if ctrl.gem_show_timer ~= false and dl.AddText then
                        local cdSec = math.ceil(gemData.timer)
                        if cdSec >= 3600 then cdSec = 0 end
                        local cdStr = cdSec >= 60 and string.format('%dm', math.ceil(cdSec / 60)) or tostring(cdSec)
                        local tW = #cdStr * 7
                        local tX = mX + math.max(2, math.floor((btnW - tW) / 2))
                        local tY = mY + math.max(2, math.floor((btnH / 2) - 6))
                        local pShadow = toV(tX + 1, tY + 1)
                        local pText = toV(tX, tY)
                        if pShadow then dl:AddText(pShadow, core.col32(0, 0, 0, 0.95), cdStr) end
                        if pText then dl:AddText(pText, core.col32(1.0, 0.85, 0.2, 1.0), cdStr) end
                    end
                end

                -- Active casting overlay (seconds only)
                if isCastingThis and dl then
                    if dl.AddRect then
                        local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8.0)
                        local p1 = toV(mX, mY)
                        local p2 = toV(maxX, maxY)
                        if p1 and p2 then
                            dl:AddRect(p1, p2, core.col32(0.2, 0.85, 1.0, 0.75 + 0.25 * pulse), 3, 0, 2.0)
                        end
                    end
                    if dl.AddText and castTimeLeft > 0 then
                        local cSec = math.ceil(castTimeLeft)
                        local cStr = tostring(cSec)
                        local tW = #cStr * 7
                        local tX = mX + math.max(2, math.floor((btnW - tW) / 2))
                        local tY = mY + math.max(2, math.floor((btnH / 2) - 6))
                        local pShadow = toV(tX + 1, tY + 1)
                        local pText = toV(tX, tY)
                        if pShadow then dl:AddText(pShadow, core.col32(0, 0, 0, 0.95), cStr) end
                        if pText then dl:AddText(pText, core.col32(0.2, 1.0, 0.4, 1.0), cStr) end
                    end
                end

                -- Right-click popup menu on gem
                if ImGui.BeginPopupContextItem('##gemItemMenu_' .. slot) then
                    accent(GOLD, string.format('Gem #%d: %s', slot, gemData.name))
                    ImGui.TextDisabled(string.format('Level %d | Mana: %d | Cast: %.1fs | Recast: %.1fs', gemData.level, gemData.mana, gemData.castTime, gemData.recast))
                    ImGui.Separator()
                    if ImGui.MenuItem('Cast Spell##cast_' .. slot) then
                        mq.cmdf('/cast %d', slot)
                    end
                    if ImGui.MenuItem('Inspect Spell Info##info_' .. slot) then
                        pcall(function() mq.TLO.Spell(gemData.id).Inspect() end)
                    end
                    if ImGui.MenuItem('Unmemorize Gem##unmem_' .. slot) then
                        mq.cmdf('/memorize "" %d', slot)
                    end
                    if ImGui.MenuItem('Open Spellbook##book_' .. slot) then
                        openSpellbook()
                    end
                    ImGui.EndPopup()
                end

                -- Hover tooltip
                if ImGui.IsItemHovered() then
                    local lines = {
                        string.format('Gem #%d: %s', slot, gemData.name),
                        string.format('Level: %d  |  Mana: %d  |  Range: %d', gemData.level, gemData.mana, gemData.range),
                        string.format('Cast Time: %.1fs  |  Recast: %.1fs', gemData.castTime, gemData.recast),
                    }
                    if not gemData.ready and gemData.timer > 0 then
                        table.insert(lines, string.format('Recast Cooldown: %d seconds remaining', math.ceil(gemData.timer)))
                    elseif isCastingThis then
                        table.insert(lines, string.format('Currently Casting: %d seconds left', math.ceil(castTimeLeft)))
                    elseif not hasMana then
                        table.insert(lines, string.format('INSUFFICIENT MANA: Need %d (Have %d)', gemData.mana, myMana))
                    else
                        table.insert(lines, 'STATUS: Ready to Cast')
                    end
                    table.insert(lines, 'Left-click to Cast | Right-click for options')
                    core.setTooltip('%s', table.concat(lines, '\n'))
                end
            else
                -- Empty gem slot button
                if ImGui.Button(string.format('#%d##empty_%d', slot, slot), btnW, btnH) then
                    openSpellbook()
                end
                if ImGui.IsItemHovered() then
                    core.setTooltip(string.format('Gem Slot #%d (Empty)\nClick to open Spellbook and memorize a spell.', slot))
                end
            end
        end

        -- Spellbook & Spell Sets button at the end
        if (totalItems - 1) % cols ~= 0 then
            ImGui.SameLine(0, spacing)
        end

        local sbClicked = ImGui.Button('##gemSpellBookBtn', btnW, btnH)
        if sbClicked then
            openSpellbook()
        end
        if ImGui.IsItemHovered() then
            core.setTooltip('Spellbook & Spell Sets\nLeft-click: Open Spellbook Browser\nRight-click: Load / Save / Delete Spell Sets')
        end

        local sbMnX, sbMnY = ImGui.GetItemRectMin()
        local sbDl = ImGui.GetWindowDrawList()

        -- Render high-detail vector Spellbook icon
        core.drawSpellbookIcon(sbDl, sbMnX, sbMnY, btnW, btnH)

        -- Right-click on Spellbook button: Load / Save / Delete spell sets
        if ImGui.BeginPopupContextItem('##spellbookSetMenu') then
            accent(GOLD, 'Spell Sets & Spellbook')
            ImGui.Separator()

            if ImGui.MenuItem('Open Spellbook Browser') then
                openSpellbook()
            end
            ImGui.Separator()

            -- Save current spell set
            if ImGui.BeginMenu('Save Current Spell Set...##saveSetMenu') then
                ImGui.Text('Enter set name:')
                ImGui.SetNextItemWidth(140)
                M.newSpellSetName = (type(M.newSpellSetName) == 'string') and M.newSpellSetName or ''
                local itFlags = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
                local newText, changed = ImGui.InputText('##setNameInput', M.newSpellSetName, itFlags)
                if type(newText) == 'string' then
                    M.newSpellSetName = newText
                end
                local cleanName = M.newSpellSetName:match('^%s*(.-)%s*$') or ''
                local enterHit = changed and (ImGui.IsKeyPressed and ImGui.IsKeyPressed(ImGuiKey and ImGuiKey.Enter or 13))
                local saveClicked = ImGui.Button('Save Set##doSaveSet')
                if (saveClicked or enterHit) and cleanName ~= '' then
                    rt.importCurrentGems()
                    rt.savePreset(cleanName)
                    M.newSpellSetName = ''
                    ImGui.CloseCurrentPopup()
                end
                ImGui.EndMenu()
            end

            -- Load saved spell set
            if ImGui.BeginMenu('Load Spell Set##loadSetMenu') then
                local presetList = {}
                if core.loadout.presets and type(core.loadout.presets) == 'table' then
                    for pName, pData in pairs(core.loadout.presets) do
                        if type(pName) == 'string' and pName ~= '' and type(pData) == 'table' then
                            table.insert(presetList, pName)
                        end
                    end
                    table.sort(presetList, function(a, b) return a:lower() < b:lower() end)
                end
                if #presetList > 0 then
                    for _, name in ipairs(presetList) do
                        if ImGui.MenuItem(name .. '##load_' .. name) then
                            rt.loadPreset(name, true)
                        end
                    end
                else
                    ImGui.TextDisabled('No saved sets found.')
                end
                ImGui.EndMenu()
            end

            -- Delete saved spell set
            if ImGui.BeginMenu('Delete Spell Set##deleteSetMenu') then
                local presetList = {}
                if core.loadout.presets and type(core.loadout.presets) == 'table' then
                    for pName, pData in pairs(core.loadout.presets) do
                        if type(pName) == 'string' and pName ~= '' and type(pData) == 'table' then
                            table.insert(presetList, pName)
                        end
                    end
                    table.sort(presetList, function(a, b) return a:lower() < b:lower() end)
                end
                if #presetList > 0 then
                    for _, name in ipairs(presetList) do
                        if ImGui.MenuItem('Delete: ' .. name .. '##del_' .. name) then
                            rt.deletePreset(name)
                        end
                    end
                else
                    ImGui.TextDisabled('No saved sets to delete.')
                end
                ImGui.EndMenu()
            end

            ImGui.EndPopup()
        end

        -- Hover tooltip
        if ImGui.IsItemHovered() then
            core.setTooltip('Spellbook & Spell Sets\nLeft-click: Open Spellbook\nRight-click: Load, Save, or Delete Spell Sets')
        end
    end

    ImGui.End()
    ImGui.PopStyleVar(3)
    core.popTheme()
end

function plugin.onDrawUI()
    if not core then return end
    refresh()
    M.drawSpellGemBarWindow()
end

function plugin.onDrawSettings()
    if not core then return end
    refresh()
    accent(GOLD, 'Spell Gem Bar HUD')
    local isWinOpen = (ctrl.show_spell_gems == true)
    if ImGui.Button((isWinOpen and 'Window: Visible (Click to Hide)' or 'Window: Hidden (Click to Show)') .. '##sgToggleWin', 250, 24) then
        ctrl.show_spell_gems = not isWinOpen
        core.saveLoadout(true)
    end
    ImGui.TextDisabled('Orientation, layout, and lock options are in the window\'s right-click menu.')
end

plugin.M = M
plugin.openSpellbook = openSpellbook
return plugin
