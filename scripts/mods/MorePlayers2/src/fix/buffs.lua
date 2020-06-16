-- luacheck: globals get_mod ScriptUnit BuffFunctionTemplates Managers POSITION_LOOKUP Unit Vector3
local mod = get_mod("MorePlayers2")

local function players_of_career(career, player_and_bot_units, owner)
  -- Store the footknights to check distances
  local players = {}
  for i = 1, #player_and_bot_units, 1 do
    local unit = player_and_bot_units[i]
    local career_extension = ScriptUnit.extension(unit, "career_system")
    local career_name = career_extension:career_name()
    if career_name == career and unit ~= owner then
      table.insert(players, unit)
    end
  end
  return players
end

local function has_one_in_range(players, current_unit_position, range_squared)
  local has_one = false
  for j = 1, #players, 1 do
    local player = players[j]
    local player_pos = POSITION_LOOKUP[player]
    local dist_to_fk = Vector3.distance_squared(player_pos, current_unit_position)

    if range_squared > dist_to_fk then
      has_one = true
    end
  end
  return has_one

end

-- In these functions we do two things to calm down the buff system:
--
-- 1. Stop trying to remove the buff from a unit of the same career.
--    They will just add it back and cause too many buffs
-- 2. Stop trying to remove from any unit too far away from the current unit.
--    First check if they have any other units of the same career near enough
--    to add the buff and don't remove it if they do.
--    They will just add it back and cause too many buffs

mod:hook_origin(BuffFunctionTemplates.functions, "markus_knight_proximity_buff_update", function (owner_unit, buff, params)
  if not Managers.state.network.is_server then
    return
  end

  local template = buff.template
  local range = buff.range
  local range_squared = range * range
  local owner_position = POSITION_LOOKUP[owner_unit]
  local side = Managers.state.side.side_by_unit[owner_unit]
  local player_and_bot_units = side.PLAYER_AND_BOT_UNITS
  local num_units = #player_and_bot_units
  local talent_extension = ScriptUnit.extension(owner_unit, "talent_system")
  local buff_to_add = "markus_knight_passive_defence_aura"
  local buff_system = Managers.state.entity:system("buff_system")
  local power_talent = talent_extension:has_talent("markus_knight_passive_power_increase")

  -- Store the footknights to check distances
  local footknights =  players_of_career("es_knight", player_and_bot_units, owner_unit)

  for i = 1, num_units, 1 do
    local unit = player_and_bot_units[i]

    if Unit.alive(unit) then
      local unit_position = POSITION_LOOKUP[unit]
      local distance_squared = Vector3.distance_squared(owner_position, unit_position)
      local buff_extension = ScriptUnit.extension(unit, "buff_system")
      local career_extension = ScriptUnit.extension(unit, "career_system")
      local career_name = career_extension:career_name()

      -- If the buff target is a FK we never want to do this block.
      -- They buff themself and we don't want to remove it
      if career_name ~= "es_knight" then
        if range_squared < distance_squared or power_talent then

          -- Don't remove if another FK is in range
          local has_a_fk_in_range = has_one_in_range(footknights, unit_position, range_squared)
          if not has_a_fk_in_range then
            local buff = buff_extension:get_non_stacking_buff(buff_to_add)

            if buff then
              local buff_id = buff.server_id

              if buff_id then
                buff_system:remove_server_controlled_buff(unit, buff_id)
              end
            end
          end

        end
      end

      if distance_squared < range_squared and not power_talent and not buff_extension:has_buff_type(buff_to_add) then
        local server_buff_id = buff_system:add_buff(unit, buff_to_add, owner_unit, true)
        local buff = buff_extension:get_non_stacking_buff(buff_to_add)

        if buff then
          buff.server_id = server_buff_id
        end
      end
    end
  end
end)

-- Handles Handmaiden and Huntsman
mod:hook_origin(BuffFunctionTemplates.functions, "activate_buff_on_distance", function (owner_unit, buff, params)
  if not Managers.state.network.is_server then
    return
  end

  local template = buff.template
  local range = buff.range
  local range_squared = range * range
  local owner_position = POSITION_LOOKUP[owner_unit]
  local buff_to_add = template.buff_to_add
  local buff_system = Managers.state.entity:system("buff_system")
  local side = Managers.state.side.side_by_unit[owner_unit]
  local player_and_bot_units = side.PLAYER_AND_BOT_UNITS
  local num_units = #player_and_bot_units

  local owner_career_ext = ScriptUnit.extension(owner_unit, "career_system")
  local owner_career_name = owner_career_ext:career_name()
  local same_career_units =  players_of_career(owner_career_name, player_and_bot_units, owner_unit)

  for i = 1, num_units, 1 do
    local unit = player_and_bot_units[i]

    if Unit.alive(unit) then
      local unit_position = POSITION_LOOKUP[unit]
      local distance_squared = Vector3.distance_squared(owner_position, unit_position)
      local buff_extension = ScriptUnit.extension(unit, "buff_system")
      local career_extension = ScriptUnit.extension(unit, "career_system")
      local career_name = career_extension:career_name()

      -- Don't try removing a buff from a unit of the same career since they
      -- add it to themself anyway.
      if career_name ~= owner_career_name then
        if range_squared < distance_squared then

          -- Don't remove if another career of the same type is in range
          local has_a_same_career_in_range = has_one_in_range(same_career_units, unit_position, range_squared)
          if not has_a_same_career_in_range then
            local buff = buff_extension:get_non_stacking_buff(buff_to_add)

            if buff then
              local buff_id = buff.server_id

              if buff_id then
                buff_system:remove_server_controlled_buff(unit, buff_id)
              end
            end
          end
        end
      end

      if distance_squared < range_squared and not buff_extension:has_buff_type(buff_to_add) then
        local server_buff_id = buff_system:add_buff(unit, buff_to_add, owner_unit, true)
        local buff = buff_extension:get_non_stacking_buff(buff_to_add)

        if buff then
          buff.server_id = server_buff_id
        end
      end
    end
  end
end)


-- TODO
--
-- Handmaiden nearby cooldown reduction Asrai Grace
-- FK nearby damage reduction That's Bloody Teamwork
-- IB nearby power increase Blood of Grimnir
