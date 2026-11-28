-- Engine hook (data/fafengine, mounted by the engine at /fafengine and registered as a hook directory): appended to
-- /lua/ui/dialogs/eschandler.lua.
--
-- The launcher's background battle (/fafengine/modules/lua/ui/launcher/battle.lua) is a game session, so closing the
-- window over it reached FAF's in-game question, "Are you sure you'd like to quit?" with Restart Session. The battle
-- is not the player's game: over it, closing asks the launcher's own exit question instead (Yes, No), and the
-- player's quick-exit option still quits at once.
do
    local battleHandleEsc = HandleEsc
    function HandleEsc(quit_game)
        if quit_game then
            local ok, launcher = pcall(function()
                if not import('/fafengine/modules/lua/ui/launcher/battle.lua').InBattle() then
                    return false
                end
                return import('/fafengine/modules/lua/ui/launcher/launcher.lua').Current()
            end)
            if ok and launcher and launcher.Exit then
                if Prefs.GetOption('quick_exit') == 'true' then
                    SafeQuit()
                else
                    launcher:Exit()
                end
                return
            end
        end
        battleHandleEsc(quit_game)
    end
end
