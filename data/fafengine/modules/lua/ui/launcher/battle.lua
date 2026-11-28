-- The launcher's background battle: eight AI armies fight on Seton's Clutch behind the launcher's panels while a
-- cinematic camera moves between their bases and fights. It is a single-player sandbox game (game option
-- FafreMenuBattle) in which the player has no army and watches.
--
-- No loading screen: the battle loads behind the launcher. The engine builds the UI three times on the way - the
-- front end, the load (the user Lua state again; the gamemain hook's provider calls OnLoadingDialog instead of FAF's
-- loading movie) and the game (the session's own Lua state; the gamemain hook calls OnGameUI) - and each build shows
-- the page the last one showed, with no motion, so the player sees one launcher throughout. While the player has a
-- dialog or screen open the launcher holds the end of the load (FafreHoldLoadEnd, asked by the engine), so the
-- switch to the game's UI never closes what they are reading. Over the game, an opaque cover fades away from the
-- opening shot: the camera low over a start position as its commander warps in, rising and turning to show the base.
--
-- Whatever needs the front end (a lobby, a campaign, a replay, a FAF or server game) first ends the battle, also while
-- it loads: Leave keeps the action, the game ends (ExitGame), and the front end's launcher runs it (TakePending); a
-- FAF match the engine starts asks EndForMatch. Off: Options > Battle behind the launcher, /nomenubattle; on in a
-- test only with /menubattle (the tests' /nomovie turns it off, as it turns off the menu movie).

local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Prefs = import('/lua/user/prefs.lua')

local kMap = '/maps/SCMP_009/SCMP_009_scenario.lua' -- Seton's Clutch: 20 km, two shores of four bases, a sea between
-- Four against four: the north-east's odd start spots against the south-west's even ones, every faction on each
-- side; FAF's cheating AIs with prebuilt bases, so the armies meet within minutes, and the tech AIs bring
-- experimentals.
local kArmies = {
    { army = 'ARMY_1', team = 2, ai = 'rushcheat', faction = 1 },
    { army = 'ARMY_2', team = 3, ai = 'rushcheat', faction = 2 },
    { army = 'ARMY_3', team = 2, ai = 'techcheat', faction = 2 },
    { army = 'ARMY_4', team = 3, ai = 'techcheat', faction = 3 },
    { army = 'ARMY_5', team = 2, ai = 'adaptivecheat', faction = 3 },
    { army = 'ARMY_6', team = 3, ai = 'adaptivecheat', faction = 4 },
    { army = 'ARMY_7', team = 2, ai = 'adaptivecheat', faction = 4 },
    { army = 'ARMY_8', team = 3, ai = 'adaptivecheat', faction = 1 },
}

-- Kept in the engine's front-end data, which outlives the UI's Lua modules (they load again with each UI build):
local kPendingKey = 'fafre_battle_pending' -- the front end's action after the battle: { method, args }
local kPageKey = 'fafre_battle_page'       -- the page the launcher showed, for the next build
local kStartsKey = 'fafre_battle_starts'   -- { started = n, failed = n }: a battle that never showed is not retried

local loading = false -- the user Lua state: a battle this state started is loading (or runs; the state then sleeps)
local building = false -- the launcher is being built over the load
local focus = false   -- the sim's newest busy place
local spawns = false  -- the armies' start positions, from the sim
local shots = 0

--- Whether the launcher should show a battle behind it.
function Wanted()
    if HasCommandLineArg('/nomenubattle') then
        return false
    end
    if HasCommandLineArg('/menubattle') then
        return true
    end
    if HasCommandLineArg('/nomovie') then
        return false
    end
    local value = Prefs.GetOption('fafre_menu_battle')
    return value ~= false and value ~= 0 and value ~= 'off'
end

local function FrontEndData(key)
    local ok, value = pcall(GetFrontEndData, key)
    return ok and value or nil
end

local function Starts()
    local value = FrontEndData(kStartsKey)
    return type(value) == 'table' and value or { started = 0, failed = 0, shown = false }
end

--- Whether the game running now is the launcher's battle.
function InBattle()
    local active = rawget(_G, 'SessionIsActive')
    if not active or not active() then
        return false
    end
    local ok, info = pcall(SessionGetScenarioInfo)
    local options = ok and info and info.Options or {}
    return options.FafreMenuBattle == true or options.FafreMenuBattle == 'true'
end

--- Whether the battle is loading behind the launcher (the user Lua state, from Start until the front end is back).
function Loading()
    return loading
end

--- Whether the launcher is being built over the battle's load (launcher.lua's Build and CreateUI ask).
function BuildingOverLoad()
    return building
end

--- The front end's launcher is up: no battle loads any more; a battle that ended before it ever showed counts as
--- failed (two such and the launcher stops starting it for this run of the game).
function FrontEnd()
    if loading then
        loading = false
        ConExecute('UI_RenderUnitBars true')
        ConExecute('ren_SelectBoxes true')
        ConExecute('UI_NisRenderIcons true')
        local starts = Starts()
        if not starts.shown then
            starts.failed = starts.failed + 1
            WARN('MENU BATTLE: the battle ended before it showed (' .. starts.failed .. ' times)')
        end
        starts.shown = false
        SetFrontEndData(kStartsKey, starts)
    end
end

--- Whether a battle may start: wanted, and not failed twice already.
function MayStart()
    return Wanted() and Starts().failed < 2
end

--- Starts the battle (from the front end's launcher). False when it can't.
function Start()
    local scenario = import('/lua/ui/maputil.lua').LoadScenario(kMap)
    if not scenario then
        WARN('MENU BATTLE: the map ' .. kMap .. ' is missing')
        return false
    end
    scenario.Options = {
        FogOfWar = 'none', NoRushOption = 'Off', PrebuiltUnits = 'On', Difficulty = 2, DoNotShareUnitCap = true,
        CheatMult = '2.0', BuildMult = '2.0',
        Timeouts = -1, GameSpeed = 'normal', UnitCap = '500', Victory = 'sandbox', CheatsEnabled = 'true',
        CivilianAlliance = 'enemy', TeamShareOverflow = 'enabled', Share = 'ShareUntilDeath',
        FafreMenuBattle = true,
    }
    local GetDefaultPlayerOptions = import('/lua/ui/lobby/lobbycomm.lua').GetDefaultPlayerOptions
    local teamInfo = {}
    for index, entry in kArmies do
        local ai = GetDefaultPlayerOptions('AI: ' .. entry.ai)
        ai.Human = false
        ai.AIPersonality = entry.ai
        ai.ArmyName = entry.army
        ai.Faction = entry.faction
        ai.Team = entry.team
        ai.StartSpot = index
        ai.PlayerColor = index
        ai.ArmyColor = index
        table.insert(teamInfo, ai)
    end
    -- The player has no army: they watch (the session's focus army is none).
    local playerName = Prefs.GetFromCurrentProfile('Name') or 'Player'
    focus = false
    spawns = false
    shots = 0
    loading = true
    local starts = Starts()
    starts.started = starts.started + 1
    starts.shown = false
    SetFrontEndData(kStartsKey, starts)
    LOG('MENU BATTLE: starting on ' .. kMap)
    LaunchSinglePlayerSession({ playerName = playerName, createReplay = false, scenarioInfo = scenario,
        teamInfo = teamInfo, scenarioMods = import('/lua/mods.lua').GetCampaignMods(scenario) })
    return true
end

--- Remembers the page the launcher shows, for the launcher built next (over the load, over the game).
function KeepPage(page)
    if Wanted() then
        SetFrontEndData(kPageKey, page)
    end
end

--- The page the launcher showed before this build, or nil.
function KeptPage()
    local page = FrontEndData(kPageKey)
    return type(page) == 'string' and page or nil
end

--- In the battle, or while it loads: keeps launcher:<method>(unpack(args)) for the front end's launcher and ends the
--- battle (true then); otherwise false, and the caller goes on.
function Leave(method, args)
    if not (InBattle() or loading) then
        return false
    end
    SetFrontEndData(kPendingKey, { method = method, args = args or {} })
    LOG('MENU BATTLE: ending it for ' .. tostring(method) .. (loading and not InBattle() and ' (still loading)' or ''))
    loading = false -- asked for: not a battle that failed to show
    ExitGame()
    return true
end

--- The kept action, once (the front end's launcher asks): { method, args } or nil.
function TakePending()
    local action = FrontEndData(kPendingKey)
    if type(action) == 'table' and action.method then
        SetFrontEndData(kPendingKey, false)
        return action
    end
    return nil
end

--- The engine: a FAF match is about to start; the battle goes first, also while it loads (never a player's game).
function EndForMatch()
    if InBattle() or loading then
        SetFrontEndData(kPendingKey, false)
        LOG('MENU BATTLE: ending it for a FAF match')
        loading = false
        ExitGame()
    end
end

--- The engine, every frame while the battle's load is done but the game's UI not built yet: true holds it there
--- while the player has a dialog or screen of the launcher open (the engine stops asking after 90 s).
local holdLogged = false
local heldAt = false
--- When the load first waited for the launcher (GetSystemTimeSeconds), or false (tests).
function HeldAt()
    return heldAt
end
local function HoldLoadEnd()
    if not loading then
        return false
    end
    local launcher = import('/fafengine/modules/lua/ui/launcher/launcher.lua').Current()
    local busy = launcher and launcher.Busy and launcher:Busy() or false
    if busy and not heldAt then
        heldAt = GetSystemTimeSeconds()
    end
    if busy ~= holdLogged then
        holdLogged = busy
        LOG('MENU BATTLE: ' .. (busy and 'the load waits while the launcher has a dialog open' or 'the load goes on'))
    end
    return busy
end
rawset(_G, 'FafreHoldLoadEnd', HoldLoadEnd)

--- The gamemain hook, in place of FAF's loading screen while the battle loads: the launcher, as it was.
function OnLoadingDialog()
    building = true
    local Launcher = import('/fafengine/modules/lua/ui/launcher/launcher.lua')
    local ok, why = pcall(Launcher.CreateUI, nil)
    building = false
    if not ok then
        WARN('MENU BATTLE: the launcher failed over the load: ' .. tostring(why))
        return false
    end
    LOG('MENU BATTLE: the battle loads behind the launcher')
    return true
end

--- The sim's busiest place (UserSync).
function OnFocus(spot)
    focus = spot
end

--- The armies' start positions (UserSync): { {x, z, army}, ... }.
function OnSpawns(list)
    spawns = list
end

--- How many camera shots this battle had (tests).
function Cuts()
    return shots
end


-- ---------------------------------------------------------------------------------------------------------------
-- The camera. Every shot is a framing at a place - heading, pitch (0 level, 1.57 straight down; the game's own camera
-- goes from 0.7 close up to straight down far out) and zoom - that
-- drifts slowly to a second framing over the shot, so the picture is never still: an orbit around a fight, a low pass
-- beside it, a wide view over it. A shot near the last one glides there; one across the map dips to black and cuts.

local kShots = {
    orbit = { pitch = 0.8, zoom = 75, endPitch = 0.72, endZoom = 58, turn = 0.7 },
    low = { pitch = 0.45, zoom = 42, endPitch = 0.52, endZoom = 34, turn = 0.35 },
    wide = { pitch = 1.1, zoom = 160, endPitch = 1.0, endZoom = 135, turn = 0.25 },
}
local kOrder = { 'orbit', 'low', 'orbit', 'wide' }
local kShotSeconds = 9
local kGlideSeconds = 3
local kNear = 260 -- a shot nearer than this to the last glides; farther dips to black and cuts

local dip = false   -- the black layer between the world and the launcher's pages
local cover = false -- the opaque cover that fades away from the opening shot
local heading = 0.6
local last = false

local function Camera()
    return GetCamera('WorldCamera')
end

--- The camera and the layers over the world, as text (tests).
function Describe()
    local camera = GetCamera('WorldCamera')
    local at = camera and camera:GetFocusPosition()
    return string.format('dip alpha %s, cover %s, camera zoom %s at %s',
        dip and string.format('%.2f', dip:GetAlpha()) or 'none', cover and 'up' or 'gone',
        camera and string.format('%.0f', camera:GetZoom()) or '?',
        at and string.format('%.0f, %.0f, %.0f', at[1], at[2], at[3]) or '?')
end

-- The camera's target is a point on the ground: its height comes from the sim (the UI has no terrain query), as a
-- target under the ground puts a low camera inside the hills.
local function Frame(x, y, z, h, pitch, zoom, seconds)
    local camera = Camera()
    if not camera then
        return
    end
    camera:MoveTo(Vector(x, y or 0, z), { h, pitch, 0 }, zoom, seconds)
end

local function Dip(apply)
    local Anim = import('/fafengine/modules/lua/ui/launcher/anim.lua')
    if not dip then
        apply()
        return
    end
    Anim.Run(dip, 0.35, function(t)
        dip:SetAlpha(t)
    end, function()
        apply()
        Anim.Run(dip, 0.6, function(t)
            dip:SetAlpha(1 - t)
        end, nil, { always = true })
    end, { always = true })
end

--- One shot of `kind` at x, z: there (gliding or cutting), then drifting for the shot's length.
local function Shot(kind, x, y, z, why)
    local shape = kShots[kind] or kShots.orbit
    shots = shots + 1
    local near = last and math.sqrt((last.x - x) * (last.x - x) + (last.z - z) * (last.z - z)) < kNear
    LOG(string.format('MENU BATTLE: shot %d, %s at %.0f, %.0f (%s, %s)', shots, kind, x, z, why,
        near and 'glide' or 'cut'))
    local start = heading
    heading = heading + shape.turn
    local drift = kShotSeconds
    if near then
        Frame(x, y, z, start, shape.pitch, shape.zoom, kGlideSeconds)
        WaitSeconds(kGlideSeconds)
        drift = kShotSeconds - kGlideSeconds
    else
        Dip(function() Frame(x, y, z, start, shape.pitch, shape.zoom, 0) end)
        WaitSeconds(0.4)
    end
    Frame(x, y, z, heading, shape.endPitch, shape.endZoom, drift)
    last = { x = x, z = z }
    WaitSeconds(drift)
end

--- The opening: low over a start position as its commander warps in, then rising and turning over the base.
local function Opening(spawn)
    shots = shots + 1
    LOG(string.format('MENU BATTLE: shot %d, the opening at %s (%.0f, %.0f)', shots, tostring(spawn.army), spawn.x,
        spawn.z))
    Frame(spawn.x, spawn.y, spawn.z, heading, 0.42, 30, 0)
    if cover then
        local shown = cover
        cover = false
        import('/fafengine/modules/lua/ui/launcher/anim.lua').Run(shown, 2.2, function(t)
            shown:SetAlpha(1 - t)
        end, function()
            shown:Destroy()
        end, { delay = 0.3, always = true, ease = import('/fafengine/modules/lua/ui/launcher/anim.lua').Ease.inOut })
    end
    WaitSeconds(3) -- the low view as the cover goes and the commander warps in, then up
    heading = heading + 1.1
    Frame(spawn.x, spawn.y, spawn.z, heading, 0.8, 95, 11)
    last = { x = spawn.x, z = spawn.z }
    WaitSeconds(11)
end

local function Director()
    local camera = Camera()
    if camera then
        camera:UseSystemClock()
        camera:EnableEaseInOut()
    end
    -- The start positions come with the sim's first seconds; the cover stays until the opening shot is placed.
    local waited = 0
    while not spawns and waited < 10 and InBattle() do
        WaitSeconds(0.1)
        waited = waited + 0.1
    end
    if spawns and spawns[1] then
        Opening(spawns[1])
        -- The other shore's first base, before the fights.
        local other = spawns[2]
        if other and InBattle() then
            Shot('low', other.x, other.y, other.z, 'a base across the sea')
        end
    elseif cover then
        cover:Destroy()
        cover = false
    end
    local index = 0
    while InBattle() do
        if focus then
            index = index + 1
            local kind = kOrder[math.mod(index - 1, table.getn(kOrder)) + 1]
            Shot(kind, focus.x, focus.y, focus.z, string.format('%d units%s', focus.units or 0,
                focus.fight and ', a fight' or ''))
        else
            WaitSeconds(1)
        end
    end
end

-- The game's HUD stays hidden (its opening animations show parts again in the first seconds).
local function HideHud()
    local GameMain = import('/lua/ui/game/gamemain.lua')
    local hideHud = rawget(GameMain, 'FafreBattleHideHud')
    for tick = 1, 20 do
        WaitSeconds(1)
        if not InBattle() then
            return
        end
        if hideHud and hideHud() then
            LOG('MENU BATTLE: the HUD showed again; hidden')
        end
    end
end

--- In the battle's game UI (the gamemain hook): the HUD goes, the launcher comes over the world as it was, the
--- camera starts.
function OnGameUI()
    local Launcher = import('/fafengine/modules/lua/ui/launcher/launcher.lua')
    local ok, why = pcall(Launcher.CreateUI, nil)
    if not ok then
        WARN('MENU BATTLE: the launcher failed over the battle: ' .. tostring(why))
        ExitGame()
        return
    end
    local starts = Starts()
    starts.shown = true
    starts.failed = 0
    SetFrontEndData(kStartsKey, starts)
    -- Over the game's own controls (some draw above a plain screen group), under in-game dialogs (5000).
    local launcher = Launcher.Current()
    if launcher and launcher.root then
        local frame = GetFrame(0)
        local root = launcher.root
        root.Depth:Set(function() return frame.Depth() + 1000 end)
        local Theme = import('/fafengine/modules/lua/ui/launcher/theme.lua')
        -- Between the world and the pages (the dim is at the root's own depth, the pages 10 above it).
        dip = Theme.Fill(root, 'ff000000')
        dip.Depth:Set(function() return root.Depth() + 4 end)
        dip:SetAlpha(0)
        cover = Theme.Fill(root, Theme.Colors.page)
        cover.Depth:Set(function() return root.Depth() + 5 end)
    end
    -- A picture, not a game: no health bars, selection boxes or strategic icons (FAF's loading screen turns them on
    -- for every game, and the front end does when the battle is over).
    ConExecute('UI_RenderUnitBars false')
    ConExecute('ren_SelectBoxes false')
    ConExecute('UI_NisRenderIcons false')
    ForkThread(Director)
    ForkThread(HideHud)
    LOG('MENU BATTLE: the launcher is over the battle')
end
