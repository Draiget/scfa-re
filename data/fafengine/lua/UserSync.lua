-- Engine hook on /lua/UserSync.lua (appended to FAF's file).
--
-- The changelog preview's scene (Sync.FafrePreviewScene: the two copies' entity ids and ranges) reaches its overlay,
-- which draws their range rings. Only a preview session's sim sends it.

do
    local previewOnSync = OnSync
    function OnSync()
        previewOnSync()
        if Sync.FafrePreviewScene then
            local ok, why = pcall(function()
                import('/fafengine/modules/lua/ui/game/unitpreview.lua').OnScene(Sync.FafrePreviewScene)
            end)
            if not ok then
                WARN('UNIT PREVIEW: ' .. tostring(why))
            end
        end
    end
end

-- The launcher's background battle: the armies' start positions (Sync.FafreBattleSpawns) and where the fight is
-- (Sync.FafreBattleFocus) for the launcher's camera.
do
    local battleOnSync = OnSync
    function OnSync()
        battleOnSync()
        if Sync.FafreBattleFocus or Sync.FafreBattleSpawns then
            local ok, why = pcall(function()
                local Battle = import('/fafengine/modules/lua/ui/launcher/battle.lua')
                if Sync.FafreBattleSpawns then
                    Battle.OnSpawns(Sync.FafreBattleSpawns)
                end
                if Sync.FafreBattleFocus then
                    Battle.OnFocus(Sync.FafreBattleFocus)
                end
            end)
            if not ok then
                WARN('MENU BATTLE: ' .. tostring(why))
            end
        end
    end
end
