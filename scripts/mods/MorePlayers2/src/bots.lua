-- luacheck: globals get_mod script_data GameModeAdventure
local mod = get_mod("MorePlayers2")

script_data.cap_num_bots = mod:get("num_bots")

function mod.on_setting_changed()
  script_data.cap_num_bots = mod:get("num_bots")
end

mod:hook(GameModeAdventure, "_get_first_available_bot_profile", function ()
  return 3, 1
end)
