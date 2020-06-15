-- luacheck: globals get_mod IngamePlayerListUI
local mod = get_mod("MorePlayers2")

-- For now, just disable all other players.
-- This UI is known for being buggy under normal circumstances and
-- it has performance issues when it's not crashing with more than 4
-- players. May or may not improve this.
mod:hook(IngamePlayerListUI, "add_player", function(func, self, player)
  if player.local_player then
    func(self, player)
  end
end)

