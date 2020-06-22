-- luacheck: globals get_mod script_data Mod ModManager Managers
local mod = get_mod("MorePlayers2")

function mod.on_all_mods_loaded()
  mod.mmo_names = get_mod("MMONames2")
end

mod.VERSION = "0.19"
mod.MOD_NAME = "[BETA] BTMP"
mod.MAX_PLAYERS = mod:get("max_players") or 32
mod.ID = "2113204803"-- Steam Workshop ID

-- Core
mod:dofile("scripts/mods/MorePlayers2/src/core")
mod:dofile("scripts/mods/MorePlayers2/src/bots")
mod:dofile("scripts/mods/MorePlayers2/src/game_object")

-- Fixes
mod:dofile("scripts/mods/MorePlayers2/src/fix/party_manager")
mod:dofile("scripts/mods/MorePlayers2/src/fix/playerlist")
mod:dofile("scripts/mods/MorePlayers2/src/fix/beastmen_standard")
mod:dofile("scripts/mods/MorePlayers2/src/fix/conflict_utils")
mod:dofile("scripts/mods/MorePlayers2/src/fix/projectiles")
mod:dofile("scripts/mods/MorePlayers2/src/fix/buffs")

-- UI
mod:dofile("scripts/mods/MorePlayers2/src/ui/tabmenu")
mod:dofile("scripts/mods/MorePlayers2/src/ui/matchmaking")
mod:dofile("scripts/mods/MorePlayers2/src/ui/scoreboard")
mod:dofile("scripts/mods/MorePlayers2/src/ui/playerlist")
mod:dofile("scripts/mods/MorePlayers2/src/ui/twitch")
mod:dofile("scripts/mods/MorePlayers2/src/ui/challenges")
mod:dofile("scripts/mods/MorePlayers2/src/ui/server_browser")

function mod.on_setting_changed()
  mod.MAX_PLAYERS = mod:get("max_players")
  script_data.cap_num_bots = math.min(mod:get("num_bots"), mod.MAX_PLAYERS)
  if Managers.player.is_server then
    Managers.lobby:setup_network_options()
    local lobby_data = Managers.matchmaking.lobby:get_stored_lobby_data()
    lobby_data.btmp_max_players = tostring(mod:get("max_players"))
    Managers.matchmaking.lobby:set_lobby_data(lobby_data)
  end
end

ModManager.unload_mod = function (self, index)
  local m = self._mods[index]

  if m then
    self:print("info", "Unloading %q.", m.name)
    self:_run_callback(m, "on_unload")

    for i, handle in ipairs(m.loaded_packages) do
      -- Don't unload the network config package else crash when reloading
      local should_not_unload = m.id == mod.ID and i == 2
      if not should_not_unload then
        Mod.release_resource_package(handle)
      end
    end

    m.state = "not_loaded"
  else
    self:print("error", "Mod index %i can't be unloaded, has not been loaded", index)
  end
end

mod:echo(mod.MOD_NAME .. " | v" .. mod.VERSION)
