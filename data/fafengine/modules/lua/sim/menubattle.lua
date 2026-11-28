-- The launcher's background battle, in the sim (game option FafreMenuBattle): AI armies fight behind the launcher.
-- The player has no army (they watch: the focus goes to no army, the map has no fog). The armies' start positions go
-- to the UI's camera once (Sync.FafreBattleSpawns, for its opening shot), every few seconds the busiest place (where
-- units of two armies meet) goes after them (Sync.FafreBattleFocus), and an army that has lost everything gets its
-- commander back at its start, so the fight goes on for as long as the launcher shows. A human army, if a launch
-- gives one, is emptied once its commander has warped in.

local ScenarioUtils = import('/lua/sim/scenarioutilities.lua')

local kCell = 48            -- the grid the busiest place is found on (map units)
local kFocusSeconds = 7     -- how often the camera gets a new place
local kRespawnSeconds = 20  -- an army without units this long gets its commander back
local kCommanders = { 'uel0001', 'ual0001', 'url0001', 'xsl0001' }

local function Watcher(brain)
    return brain.BrainType == 'Human'
end

--- The busiest place: the grid cell with most mobile units, two armies in it counting thrice; nil on an empty map.
local function Busiest(size)
    local units = GetUnitsInRect(Rect(0, 0, size[1], size[2])) or {}
    local cells = {}
    local best, bestScore = nil, 0
    for _, unit in units do
        if not unit.Dead and EntityCategoryContains(categories.MOBILE, unit) then
            local position = unit:GetPosition()
            local key = math.floor(position[1] / kCell) .. ':' .. math.floor(position[3] / kCell)
            local cell = cells[key]
            if not cell then
                cell = { x = 0, y = 0, z = 0, n = 0, count = 0, armies = {}, armyCount = 0 }
                cells[key] = cell
            end
            cell.x = cell.x + position[1]
            cell.y = cell.y + position[2]
            cell.z = cell.z + position[3]
            cell.n = cell.n + 1 -- the units the place's middle is the average of
            cell.count = cell.count + 1
            local army = unit:GetArmy()
            if not cell.armies[army] then
                cell.armies[army] = true
                cell.armyCount = cell.armyCount + 1
            end
            -- Hurt units are in a fight.
            if unit:GetHealth() < unit:GetMaxHealth() then
                cell.count = cell.count + 1
            end
        end
    end
    for _, cell in cells do
        local score = cell.count * (cell.armyCount >= 2 and 6 or 1) -- a fight beats a bigger base
        if score > bestScore then
            best, bestScore = cell, score
        end
    end
    if not best then
        return nil
    end
    return { x = best.x / best.n, y = best.y / best.n, z = best.z / best.n, fight = best.armyCount >= 2,
        units = best.n }
end

local function Respawn(brain, index)
    local name = brain.Name
    local marker = ScenarioUtils.GetMarker(name)
    if not marker or not marker.position then
        return
    end
    local faction = brain:GetFactionIndex() or 1
    local bp = kCommanders[faction] or kCommanders[1]
    local p = marker.position
    local unit = CreateUnitHPR(bp, index, p[1], p[2], p[3], 0, 0, 0)
    if unit then
        LOG('MENU BATTLE: ' .. tostring(name) .. ' had nothing left; its commander is back')
    end
end

local function Spawns()
    local list = {}
    for index, brain in ArmyBrains do
        if not Watcher(brain) and not ArmyIsCivilian(index) then
            local marker = ScenarioUtils.GetMarker(brain.Name)
            if marker and marker.position then
                table.insert(list, { x = marker.position[1], y = marker.position[2], z = marker.position[3],
                    army = brain.Name })
            end
        end
    end
    return list
end

function Run(options)
    local size = ScenarioInfo.size or { 512, 512 }
    SetFocusArmy(-1)
    Sync.FafreBattleSpawns = Spawns()
    WaitTicks(2)
    -- The watcher's commander goes once its warp-in is over (the commander's own script runs on it until then).
    ForkThread(function()
        WaitSeconds(7)
        for _, brain in ArmyBrains do
            if Watcher(brain) then
                for _, unit in (brain:GetListOfUnits(categories.ALLUNITS, false) or {}) do
                    if not unit.Dead then
                        unit:Destroy()
                    end
                end
            end
        end
    end)
    LOG('MENU BATTLE: running, ' .. table.getn(ArmyBrains) .. ' armies on ' .. tostring(ScenarioInfo.name))
    local empty = {}
    local since = 0
    while true do
        WaitSeconds(1)
        since = since + 1
        for index, brain in ArmyBrains do
            if not Watcher(brain) and not ArmyIsCivilian(index) then
                local count = table.getn(brain:GetListOfUnits(categories.ALLUNITS - categories.WALL, false) or {})
                if count == 0 then
                    empty[index] = (empty[index] or 0) + 1
                    if empty[index] >= kRespawnSeconds then
                        empty[index] = 0
                        Respawn(brain, index)
                    end
                else
                    empty[index] = 0
                end
            end
        end
        if since >= kFocusSeconds then
            since = 0
            local spot = Busiest(size)
            if spot then
                Sync.FafreBattleFocus = spot
            end
        end
    end
end
