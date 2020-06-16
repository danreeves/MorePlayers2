-- luacheck: globals get_mod script_data GameModeAdventure
local mod = get_mod("MorePlayers2")

script_data.cap_num_bots = 0

-- local bot_count = 0
mod:hook(GameModeAdventure, "_get_first_available_bot_profile", function ()
  -- local profile_index = bot_count % 5 + 1
  -- local career_index = bot_count % 3 + 1
  -- return profile_index, career_index
  return 5, 2
end)
