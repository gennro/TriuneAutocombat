--[[
    Upgrader.lua
    ------------------------------------------------------------------
    For Project Triune (EQ emulator): automatically keeps your Power
    Source slot fed with equipped gear that hasn't reached (Legendary)
    yet, so the Normal -> (Enchanted) -> (Legendary) upgrade chain runs
    itself. Includes a small ImGui config window.

    Every scan tick it:
      1. Checks the Power Source slot.
         - Occupied -> assumes an upgrade is in progress, just watches
           (warns if the same item sits there an unusually long time).
         - Empty -> picks the next eligible EQUIPPED item (bags are
           never auto-touched) and moves it in.
      2. Verifies the move actually happened before believing it
         succeeded. Two different failure modes are handled
         differently on purpose:
           - Transient interference (another script scoops the item
             off your cursor into a bag mid-swap, etc.) is NOT treated
             as a permanent failure -- the slot is left alone and the
             very next scan tick just tries again.
           - A genuine, repeated rejection (the item bounces straight
             back out of the Power Source slot every time) marks that
             slot ineligible after a couple of tries so it doesn't
             loop on it forever.
      3. Refreshes a small ImGui window so you can: pause/resume,
         toggle which equipped slots are allowed to upgrade, choose
         whether to bring everything up to (Enchanted) before any
         piece starts on (Legendary), and check off items sitting in
         your bags to queue them for upgrade -- a checked item drops
         out of the list as soon as it's actually placed in the Power
         Source slot. The window grows to fit whatever sections you
         have expanded, up to a 1000px height cap, then scrolls. Items
         in both lists are colored by tier (green/light blue/muted
         orange), and your Slot Configuration checkboxes are saved to
         disk automatically and reloaded next time you run the script.

    ------------------------------------------------------------------
    REQUIREMENTS
      - MacroQuest (MQNext) with Lua scripting enabled.
      - Run from the EQ command line: /lua run upgrader
        (assuming this file is saved as .../MacroQuest/lua/upgrader.lua)

    IN-GAME COMMANDS while it's running
      /upgrader pause    - pause/resume automatic scanning (the ImGui
                           window has the same toggle)
      /upgrader status   - print current state to the MQ2 chat window
      /upgrader ui       - show/hide the config window again if you closed it
      /upgrader stop     - cleanly stop and unload the script
------------------------------------------------------------------]]

local mq = require('mq')
require('ImGui')

-- ############################## CONFIG ##############################

-- How often (in ms) to check the power source slot / equipped gear /
-- bag contents. Pause, Stop, Refresh Now, and manual bag-item upgrades
-- all interrupt this wait immediately -- it doesn't block the UI.
local SCAN_INTERVAL_MS = 3000

-- How many general inventory (bag) slots to scan for the Bag Inventory
-- panel. 12 covers every general slot Project Triune is likely to use;
-- extra empty slots are simply skipped.
local NUM_BAG_SLOTS = 12

-- If an item sits in the Power Source slot this long (seconds) without
-- the slot changing, print a periodic reminder -- it may be an item
-- that can't actually be upgraded there.
local STUCK_WARN_SECONDS = 20 * 60 -- 20 minutes

-- How many consecutive genuine rejections (item placed, then bounces
-- straight back out) before a slot is marked ineligible for the rest
-- of the session. Transient interference from other scripts does NOT
-- count toward this.
local REJECT_THRESHOLD = 2

local POWER_SOURCE_SLOT = 'powersource'

-- Text colors by tier {r, g, b, a}, 0-1 floats.
local TIER_COLORS = {
    [0] = { 0.35, 0.85, 0.35, 1.0 }, -- Normal    -- green
    [1] = { 0.50, 0.80, 1.00, 1.0 }, -- Enchanted -- light blue
    [2] = { 0.80, 0.55, 0.25, 0.60 }, -- Legendary -- orange, dimmed/greyed out
}

-- Equipped slots considered for automatic upgrading, in scan order,
-- with friendly labels for the UI.
local SLOT_DEFS = {
    { key = 'charm',       label = 'Charm' },
    { key = 'leftear',     label = 'Left Ear' },
    { key = 'head',        label = 'Head' },
    { key = 'face',        label = 'Face' },
    { key = 'rightear',    label = 'Right Ear' },
    { key = 'neck',        label = 'Neck' },
    { key = 'shoulder',    label = 'Shoulders' },
    { key = 'arms',        label = 'Arms' },
    { key = 'back',        label = 'Back' },
    { key = 'leftwrist',   label = 'Left Wrist' },
    { key = 'rightwrist',  label = 'Right Wrist' },
    { key = 'ranged',      label = 'Ranged' },
    { key = 'hands',       label = 'Hands' },
    { key = 'mainhand',    label = 'Main Hand' },
    { key = 'offhand',     label = 'Off Hand / Shield' },
    { key = 'leftfinger',  label = 'Left Finger' },
    { key = 'rightfinger', label = 'Right Finger' },
    { key = 'chest',       label = 'Chest' },
    { key = 'legs',        label = 'Legs' },
    { key = 'feet',        label = 'Feet' },
    { key = 'waist',       label = 'Waist' },
    { key = 'ammo',        label = 'Ammo' },
}

-- ############################## STATE ##############################

local running = true
local manualQueue = {} -- array of {target=, name=, key=}, appended by the UI, consumed one at a time by the main loop
local selected = {}    -- bag item key -> true while its checkbox is checked but not yet queued
local forceRefresh = false

local config = {
    paused = false,
    prioritizeEnchantedFirst = true, -- bring everything to (Enchanted) before any piece starts on (Legendary)
    enabledSlots = {},
}
for _, def in ipairs(SLOT_DEFS) do
    config.enabledSlots[def.key] = true
end

local ineligibleSlots = {} -- key -> true, slots/items confirmed rejected by the Power Source slot
local rejectCounts = {}    -- key -> consecutive genuine-rejection count

local stuckItemName = nil
local stuckSince = 0
local lastStuckWarn = 0

local cache = {
    powerSourceName = nil,
    equippedSnapshot = {}, -- slot key -> item name, for the UI
    bagContents = {},      -- array of {label, name, tier, target, key}
}

local isOpen, shouldDraw = true, true

-- Slot Configuration checkboxes are persisted per-character via
-- mq.pickle (see docs.macroquest.org/lua/pickle/), one file per
-- character name under the MacroQuest config folder.
local SETTINGS_FILE = 'upgrader_slots_' .. (mq.TLO.Me.Name() or 'default') .. '.lua'

-- ############################## HELPERS ##############################

local function log(msg)
    print(string.format('\ay[Upgrader]\ax %s', msg))
end

-- Loads previously-saved Slot Configuration checkboxes over the
-- defaults, if a settings file exists for this character.
local function loadSlotConfig()
    local chunk, err = loadfile(mq.configDir .. '/' .. SETTINGS_FILE)
    if not chunk then
        return -- nothing saved yet -- keep the all-enabled defaults
    end
    local ok, saved = pcall(chunk)
    if ok and type(saved) == 'table' then
        for _, def in ipairs(SLOT_DEFS) do
            if saved[def.key] ~= nil then
                config.enabledSlots[def.key] = saved[def.key]
            end
        end
        log('Loaded saved Slot Configuration settings.')
    else
        log('Could not read saved Slot Configuration settings (' .. tostring(err or saved) .. ') -- using defaults.')
    end
end

local function saveSlotConfig()
    mq.pickle(SETTINGS_FILE, config.enabledSlots)
end

-- 0 = Normal, 1 = Enchanted, 2 = Legendary
local function getTier(name)
    if not name then return 0 end
    if string.find(name, '(Legendary)', 1, true) then return 2 end
    if string.find(name, '(Enchanted)', 1, true) then return 1 end
    return 0
end

local function tierLabel(tier)
    if tier == 2 then return 'Legendary' end
    if tier == 1 then return 'Enchanted' end
    return 'Normal'
end

-- Name of whatever's in a named top-level slot (equip slot, powersource,
-- or a bare "packN" slot holding a loose item), or nil if empty.
local function itemNameIn(slot)
    local name = mq.TLO.Me.Inventory(slot).Name()
    if name == nil or name == '' or name == 'NULL' then
        return nil
    end
    return name
end

local function cursorItemId()
    local id = mq.TLO.Cursor.ID()
    if id == nil or id == 0 then return nil end
    return id
end

local function cursorItemName()
    local name = mq.TLO.Cursor.Name()
    if name == nil or name == '' or name == 'NULL' then return nil end
    return name
end

local function refreshEquippedSnapshot()
    for _, def in ipairs(SLOT_DEFS) do
        cache.equippedSnapshot[def.key] = itemNameIn(def.key)
    end
end

-- Scans general inventory (bags) only -- never touched automatically,
-- just used to populate the Bag Inventory panel and its manual
-- Upgrade buttons.
local function scanBags()
    local results = {}
    for bagIdx = 1, NUM_BAG_SLOTS do
        local bagSlotName = 'pack' .. bagIdx
        local bagItem = mq.TLO.Me.Inventory(bagSlotName)
        local bagId = bagItem.ID()
        if bagId and bagId ~= 0 then
            local capacity = tonumber(bagItem.Container()) or 0
            if capacity > 0 then
                for sub = 1, capacity do
                    local subItem = bagItem.Item(sub)
                    local subId = subItem.ID()
                    if subId and subId ~= 0 then
                        local name = subItem.Name()
                        table.insert(results, {
                            label = string.format('Bag %d, Slot %d', bagIdx, sub),
                            name = name,
                            tier = getTier(name),
                            target = string.format('in pack%d %d', bagIdx, sub),
                            key = string.format('bag_%d_%d', bagIdx, sub),
                        })
                    end
                end
            else
                -- A loose item sitting directly in this general slot (no bag).
                local name = bagItem.Name()
                if name and name ~= '' then
                    table.insert(results, {
                        label = string.format('Bag %d', bagIdx),
                        name = name,
                        tier = getTier(name),
                        target = bagSlotName,
                        key = 'bag_' .. bagIdx,
                    })
                end
            end
        end
    end
    return results
end

-- Drops any selection/queue bookkeeping for bag items that are no
-- longer sitting in a bag (moved to the Power Source, sold, whatever).
local function pruneStaleKeys()
    local present = {}
    for _, entry in ipairs(cache.bagContents) do
        present[entry.key] = true
    end
    for key in pairs(selected) do
        if not present[key] then selected[key] = nil end
    end
    for i = #manualQueue, 1, -1 do
        if not present[manualQueue[i].key] then table.remove(manualQueue, i) end
    end
end

-- Finds the next equipped item eligible to upgrade, honoring the
-- enabled-slot toggles, the ineligible-slot list, and (if on) the
-- "everything to Enchanted before any Legendary" priority.
local function findNextUpgradeCandidate()
    local normalCandidate, enchantedCandidate
    for _, def in ipairs(SLOT_DEFS) do
        if config.enabledSlots[def.key] and not ineligibleSlots[def.key] then
            local name = cache.equippedSnapshot[def.key]
            if name then
                local tier = getTier(name)
                if tier == 0 and not normalCandidate then
                    normalCandidate = { slot = def.key, name = name }
                elseif tier == 1 and not enchantedCandidate then
                    enchantedCandidate = { slot = def.key, name = name }
                end
            end
        end
    end

    if config.prioritizeEnchantedFirst then
        local pick = normalCandidate or enchantedCandidate
        if pick then return pick.slot, pick.name end
        return nil, nil
    end

    -- Not prioritizing -- take whichever comes first in slot order.
    for _, def in ipairs(SLOT_DEFS) do
        if config.enabledSlots[def.key] and not ineligibleSlots[def.key] then
            local name = cache.equippedSnapshot[def.key]
            if name and getTier(name) < 2 then
                return def.key, name
            end
        end
    end
    return nil, nil
end

-- Picks up whatever is at `fromTarget` (an equip slot name, a bare
-- "packN" slot, or "in packN M") and drops it into the Power Source
-- slot, verifying every step. `trackKey` (optional) is what gets
-- marked ineligible after repeated genuine rejections -- pass nil to
-- skip that tracking entirely (used for one-off manual bag upgrades).
local function moveItemToPowerSource(fromTarget, itemName, trackKey)
    -- Clear a stray cursor item first (leftover from a manual action,
    -- another script, etc.) so it doesn't get swapped in by mistake.
    if cursorItemId() then
        local strayName = cursorItemName()
        log(string.format('Cursor was holding "%s" -- running /autoinventory to clear it before swapping.', tostring(strayName)))
        mq.cmd('/autoinventory')
        mq.delay(600)
    end

    log(string.format('Placing "%s" (from %s) into the Power Source slot.', itemName, fromTarget))
    mq.cmdf('/itemnotify %s leftmouseup', fromTarget)
    mq.delay(600)

    if cursorItemName() ~= itemName then
        -- Something interfered before we even got the item onto the
        -- cursor (or the fromTarget was already empty). Clean up if
        -- something unexpected ended up on the cursor, then bail out
        -- WITHOUT marking anything ineligible -- this is transient,
        -- the next scan tick will just try again.
        if cursorItemId() then
            log('Unexpected item on cursor after pickup attempt -- running /autoinventory and will retry next scan.')
            mq.cmd('/autoinventory')
            mq.delay(600)
        else
            log(string.format('Could not pick up "%s" from %s (likely another script interfered) -- will retry next scan.', itemName, fromTarget))
        end
        return false
    end

    mq.cmdf('/itemnotify %s leftmouseup', POWER_SOURCE_SLOT)
    mq.delay(600)

    if cursorItemId() then
        -- One retry in case that first placement attempt just didn't land.
        mq.cmdf('/itemnotify %s leftmouseup', POWER_SOURCE_SLOT)
        mq.delay(600)
    end

    if cursorItemId() then
        -- Genuine rejection: the item is still bouncing back to the
        -- cursor instead of landing in the Power Source slot.
        local key = trackKey or fromTarget
        rejectCounts[key] = (rejectCounts[key] or 0) + 1
        log(string.format('"%s" was rejected by the Power Source slot (%d/%d). Putting it back in %s.', itemName, rejectCounts[key], REJECT_THRESHOLD, fromTarget))
        mq.cmdf('/itemnotify %s leftmouseup', fromTarget)
        mq.delay(600)
        if trackKey and rejectCounts[key] >= REJECT_THRESHOLD then
            ineligibleSlots[trackKey] = true
            log(string.format('Marking %s ineligible after repeated rejections. Toggle it back on in the UI if that was wrong.', trackKey))
        end
        return false
    end

    local nowInPowerSource = itemNameIn(POWER_SOURCE_SLOT)
    if nowInPowerSource ~= itemName then
        -- Cursor cleared, but not into the Power Source slot -- almost
        -- certainly another script grabbed it (e.g. an auto-inventory
        -- routine) at the worst possible moment. Not a real rejection;
        -- just let the next scan tick re-evaluate from scratch.
        log(string.format('Unexpected state after moving "%s" -- Power Source slot now shows "%s". Will re-check next scan.', itemName, tostring(nowInPowerSource)))
        return false
    end

    rejectCounts[trackKey or fromTarget] = 0
    return true
end

-- ############################## UI ##############################

local function drawSlotConfig()
    if ImGui.CollapsingHeader('Slot Configuration') then
        ImGui.Text('Uncheck a slot to leave that piece of gear alone (e.g. weapon or shield). Saved automatically.')
        for _, def in ipairs(SLOT_DEFS) do
            local equipped = cache.equippedSnapshot[def.key]

            local before = config.enabledSlots[def.key]
            local after = ImGui.Checkbox(def.label .. '##slot_' .. def.key, before)
            if after ~= before then
                config.enabledSlots[def.key] = after
                saveSlotConfig()
            end

            ImGui.SameLine()
            if equipped then
                local tier = getTier(equipped)
                local c = TIER_COLORS[tier]
                local desc = ': ' .. equipped .. ' [' .. tierLabel(tier) .. ']'
                if ineligibleSlots[def.key] then
                    desc = desc .. '  -- skipped: rejected by Power Source'
                end
                ImGui.TextColored(c[1], c[2], c[3], c[4], desc)
            else
                ImGui.Text(': (empty)')
            end
        end
    end
end

local function drawBagInventory()
    if ImGui.CollapsingHeader('Bag Inventory') then
        if #cache.bagContents == 0 then
            ImGui.Text('No bag items found.')
        else
            local queuedKeys = {}
            for _, q in ipairs(manualQueue) do queuedKeys[q.key] = true end

            local selectedCount = 0
            for _, entry in ipairs(cache.bagContents) do
                if entry.tier < 2 and not queuedKeys[entry.key] and selected[entry.key] then
                    selectedCount = selectedCount + 1
                end
            end

            if ImGui.Button(string.format('Upgrade Selected (%d)##bagqueue', selectedCount)) and selectedCount > 0 then
                for _, entry in ipairs(cache.bagContents) do
                    if entry.tier < 2 and not queuedKeys[entry.key] and selected[entry.key] then
                        table.insert(manualQueue, { target = entry.target, name = entry.name, key = entry.key })
                        selected[entry.key] = nil
                    end
                end
                log(string.format('Queued %d item(s) from bags for upgrade.', selectedCount))
            end
            if #manualQueue > 0 then
                ImGui.SameLine()
                ImGui.Text(string.format('(%d queued)', #manualQueue))
            end

            for _, entry in ipairs(cache.bagContents) do
                local desc = string.format('%s: %s [%s]', entry.label, entry.name, tierLabel(entry.tier))
                local c = TIER_COLORS[entry.tier]
                if entry.tier < 2 then
                    if queuedKeys[entry.key] then
                        ImGui.TextColored(c[1], c[2], c[3], c[4], '     ' .. desc .. '  (queued)')
                    else
                        selected[entry.key] = ImGui.Checkbox('##sel_' .. entry.key, selected[entry.key] or false)
                        ImGui.SameLine()
                        ImGui.TextColored(c[1], c[2], c[3], c[4], desc)
                    end
                else
                    ImGui.TextColored(c[1], c[2], c[3], c[4], '     ' .. desc)
                end
            end
        end
    end
end

-- Window grows to fit whatever's expanded (no hard-coded height), but
-- never taller than 1000px -- past that it scrolls instead of growing.
local WINDOW_MAX_HEIGHT = 1000

local function updateImGui()
    if not isOpen then return end
    ImGui.SetNextWindowSizeConstraints(0, 0, 100000, WINDOW_MAX_HEIGHT)
    isOpen, shouldDraw = ImGui.Begin('Power Source Upgrader', isOpen, ImGuiWindowFlags.AlwaysAutoResize)
    if shouldDraw then
        ImGui.Text('Power Source slot: ' .. (cache.powerSourceName or '(empty)'))
        if config.paused then
            ImGui.Text('Status: PAUSED')
        end

        if ImGui.Button(config.paused and 'Resume' or 'Pause') then
            config.paused = not config.paused
        end
        ImGui.SameLine()
        if ImGui.Button('Refresh Now') then
            forceRefresh = true
        end
        ImGui.SameLine()
        if ImGui.Button('Stop Script') then
            running = false
        end

        ImGui.Separator()
        config.prioritizeEnchantedFirst = ImGui.Checkbox(
            'Bring every piece to Enchanted before starting Legendary',
            config.prioritizeEnchantedFirst
        )

        ImGui.Separator()
        drawSlotConfig()
        ImGui.Separator()
        drawBagInventory()
    end
    ImGui.End()
end

loadSlotConfig()
mq.imgui.init('upgrader', updateImGui)

-- ############################## COMMANDS ##############################

mq.bind('/upgrader', function(...)
    local action = (select(1, ...) or ''):lower()
    if action == 'pause' then
        config.paused = not config.paused
        log(config.paused and 'Paused.' or 'Resumed.')
    elseif action == 'status' then
        local skipped = {}
        for slot in pairs(ineligibleSlots) do table.insert(skipped, slot) end
        log(string.format(
            'Paused=%s | Power Source slot=%s | Queued=%d | Skipped/ineligible: %s',
            tostring(config.paused),
            cache.powerSourceName or '(empty)',
            #manualQueue,
            (#skipped > 0) and table.concat(skipped, ', ') or 'none'
        ))
    elseif action == 'ui' then
        isOpen = true
    elseif action == 'stop' then
        log('Stopping.')
        running = false
    else
        log('Usage: /upgrader [pause|status|ui|stop]')
    end
end)

-- ############################## MAIN LOOP ##############################

log('Started. Watching equipped gear for the Power Source upgrade queue. (/upgrader status | /upgrader pause | /upgrader ui | /upgrader stop)')

while running do
    local psName = itemNameIn(POWER_SOURCE_SLOT)
    cache.powerSourceName = psName
    refreshEquippedSnapshot()
    cache.bagContents = scanBags()
    pruneStaleKeys()

    if psName == nil then
        -- Slot is empty -- the manual bag queue (checked in the UI)
        -- always takes priority over the automatic equipped-gear scan,
        -- and runs even while paused since it's an explicit user pick.
        stuckItemName = nil
        if #manualQueue > 0 then
            local req = table.remove(manualQueue, 1)
            moveItemToPowerSource(req.target, req.name, req.key)
        elseif not config.paused then
            local slot, name = findNextUpgradeCandidate()
            if slot then
                moveItemToPowerSource(slot, name, slot)
            end
        end
        cache.powerSourceName = itemNameIn(POWER_SOURCE_SLOT)
    else
        -- Slot occupied -- an upgrade is presumably in progress.
        -- Just watch for it never finishing.
        if psName ~= stuckItemName then
            stuckItemName = psName
            stuckSince = os.time()
            lastStuckWarn = 0
        else
            local elapsed = os.time() - stuckSince
            if elapsed > STUCK_WARN_SECONDS and (os.time() - lastStuckWarn) > STUCK_WARN_SECONDS then
                log(string.format('"%s" has been in the Power Source slot for a while with no change -- double check it can actually be upgraded there.', psName))
                lastStuckWarn = os.time()
            end
        end
    end

    forceRefresh = false
    mq.delay(SCAN_INTERVAL_MS, function() return (not running) or forceRefresh or (#manualQueue > 0) end)
end

log('Stopped.')
