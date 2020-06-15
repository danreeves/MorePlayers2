-- luacheck: globals get_mod BuffSystem NetworkConstants NetworkLookup ScriptUnit fassert
local mod = get_mod("MorePlayers2")

local disabled_buffs = {
  "markus_knight_passive_block_cost_aura_buff",
  "markus_knight_passive_defence_aura",
  "markus_knight_improved_passive_defence_aura",
  "markus_knight_improved_passive_defence_aura_buff",
  "markus_huntsman_passive_crit_aura_buff",
  "bardin_ironbreaker_power_on_nearby_allies_buff",
  "kerillian_maidenguard_passive_stamina_regen_buff",
  "kerillian_waywatcher_group_regen",
}

local has_dumped_buff_debug = false
mod:hook_origin(BuffSystem, "add_buff", function (self, unit, template_name, attacker_unit, is_server_controlled, power_level, source_attacker_unit)

    -- if is_server_controlled then
    -- if table.contains(disabled_buffs, template_name) then
    -- return 0
    -- end
    -- end

    if not ScriptUnit.has_extension(unit, "buff_system") then
      return
    end

    fassert(self.is_server or not is_server_controlled, "[BuffSystem]: Trying to add a server controlled buff from a client!")

    if self.is_server and is_server_controlled then
      local num_free_server_buff_ids = #self.free_server_buff_ids
      if num_free_server_buff_ids <= 1 then
        mod:debug("[MTFP] Ran out of server controlled buff ids")
        mod:debug("[MTFP] Not adding buff: %s", template_name)
        if not has_dumped_buff_debug then
          has_dumped_buff_debug = true
          mod:dump(self.server_controlled_buffs, 'SERVER_CONTROLLED_BUFFS', 2)
        end
        return
      end
    end
    local server_buff_id = (is_server_controlled and self:_next_free_server_buff_id()) or 0

    if ScriptUnit.has_extension(unit, "buff_system") then
      self:_add_buff_helper_function(unit, template_name, attacker_unit, server_buff_id, power_level, source_attacker_unit)
    end

    local network_manager = self.network_manager
    local unit_object_id = network_manager:game_object_or_level_id(unit)
    local attacker_unit_object_id = network_manager:game_object_or_level_id(attacker_unit)
    local buff_template_name_id = NetworkLookup.buff_templates[template_name]

    if self.is_server then
      network_manager.network_transmit:send_rpc_clients("rpc_add_buff", unit_object_id, buff_template_name_id, attacker_unit_object_id, server_buff_id, false)
    else
      network_manager.network_transmit:send_rpc_server("rpc_add_buff", unit_object_id, buff_template_name_id, attacker_unit_object_id, 0, false)
    end

    return server_buff_id
end)

