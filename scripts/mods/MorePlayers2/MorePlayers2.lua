-- luacheck: globals get_mod Network GameSettingsDevelopment LobbyManager GameMechanismManager AdventureMechanism SlotAllocator script_data MatchmakingSettings PartyManager Managers
-- luacheck: globals GameModeAdventure FindProfileIndex SPProfiles PlayerManager GameSession NetworkTransmit RPC MatchmakingUI IngamePlayerListUI UIRenderer EndViewStateScore DamageUtils
-- luacheck: globals SimpleInventoryExtension UnitFrameUI UnitFramesHandler World Vector2 UIResolution ScriptGUI Color Localize ProfileSynchronizer StateInGameRunning PopupJoinLobbyHandler
-- luacheck: globals Mod ModManager ResourcePackage ShowCursorStack UIWidgetUtils Utf8 AdventureProfileRules ConflictUtils UISettings Vector3 BeastmenStandardExtension BuffSystem ScriptUnit
-- luacheck: globals NetworkLookup NetworkConstants fassert
local mod = get_mod("MorePlayers2")
local mmo_names = get_mod("MMONames2")

function mod.on_all_mods_loaded()
  mmo_names = get_mod("MMONames2")
end

local VERSION = "0.5"
local MOD_NAME = "[BETA] More Than Four Players"
local MAX_PLAYERS = 32

script_data.cap_num_bots = 0
PlayerManager.MAX_PLAYERS = MAX_PLAYERS
MatchmakingSettings.MAX_NUMBER_OF_PLAYERS = MAX_PLAYERS
GameSettingsDevelopment.lobby_max_members = MAX_PLAYERS

local network_options = {
  config_file_name = "content/MorePlayers2/global", -- MODIFIED
  ip_address = Network.default_network_address(),
  lobby_port = GameSettingsDevelopment.network_port,
  map = "None",
  max_members = MAX_PLAYERS,
  project_hash = "bulldozer",
  query_port = script_data.query_port or script_data.settings.query_port,
  server_port = script_data.server_port or script_data.settings.server_port,
  steam_port = script_data.steam_port or script_data.settings.steam_port,
}

local logged = false
mod:hook_origin(LobbyManager, "setup_network_options", function(self, increment_lobby_port)
  if not logged then
    mod:echo(MOD_NAME .. " | v" .. VERSION)
    logged = true
  end
  local lobby_port = script_data.server_port or script_data.settings.server_port or network_options.lobby_port
  lobby_port = lobby_port + self._lobby_port_increment
  if increment_lobby_port then self._lobby_port_increment = self._lobby_port_increment + 1 end
  network_options.lobby_port = lobby_port
  self._network_options = network_options
end)

mod:hook_origin(GameMechanismManager, "max_members", function() return MAX_PLAYERS end)
mod:hook_origin(AdventureMechanism, "profile_available", function() return true end)
mod:hook_origin(AdventureMechanism, "profile_available_for_peer", function() return true end)
mod:hook_origin(SlotAllocator, "is_free_in_lobby", function() return true end)
mod:hook_origin(ProfileSynchronizer, "is_only_owner", function() return true end)
mod:hook_origin(AdventureProfileRules, "_is_only_owner", function() return true end)
mod:hook_origin(AdventureProfileRules, "_profile_available", function() return true end)

mod:hook(SlotAllocator, "init", function(func, self, is_server, lobby)
  return func(self, is_server, lobby, MAX_PLAYERS)
end)

mod:hook(PartyManager, 'get_party',  function(func, self, num)
  local p = self._parties[num]
  p.num_slots = MAX_PLAYERS
  return func(self, num)
end)

-- local bot_count = 0
mod:hook(GameModeAdventure, "_get_first_available_bot_profile", function ()
  -- local profile_index = bot_count % 5 + 1
  -- local career_index = bot_count % 3 + 1
  -- return profile_index, career_index
  return 3, 3
end)

mod:hook(GameSession, "game_object_field", function(func, self, go_id, key, ...)
  -- Return early if game object doesn't exist
  -- TODO: Maybe I need to cache some values in case something expects
  --       a certain type and then errors when it gets nil
  local go_exists = GameSession.game_object_exists(self, go_id)
  if not go_exists then
    if key == "current_health" then
      return 0
    end
    if key == "temporary_health" then
      return 0
    end
    if key == "current_temporary_health" then
      return 0
    end
    if key == "max_health" then
      return 0
    end
    return
  end

  local value = func(self, go_id, key, ...)
  if key == "local_player_id" then
    if value == 0 then
      mod:debug("[MTFP] local_player_id was 0. setting to 8")
      value = 8
    end
  end
  return value
end)

mod:hook(IngamePlayerListUI, "add_player", function(func, self, player)
  if player.local_player then
    func(self, player)
  end
end)

mod:hook_origin(PartyManager, "server_peer_left_session", function (self, peer_id)
  self._hot_join_synced_peers[peer_id] = false
  local parties = self._parties

  for party_id = 0, #parties, 1 do
    local party = parties[party_id]
    local slots = party.slots
    local num_slots = party.num_slots

    for i = 1, num_slots, 1 do
      local status = slots[i]

      -- MODIFIED. CHECK IF STATUS BEFORE INDEXING ON IT
      if not status then
        return
      end

      if status.peer_id == peer_id then
        self:remove_peer_from_party(status.peer_id, status.local_player_id, party_id)
      end
    end
  end
end)

local function matchmakinguihooks(func, self, index, ...)
  if index <= 4 then
    func(self, index, ...)
  end
end

mod:hook(MatchmakingUI, "large_window_set_player_portrait", matchmakinguihooks)
mod:hook(MatchmakingUI, "large_window_set_player_connecting", matchmakinguihooks)
mod:hook(MatchmakingUI, "large_window_set_player_ready_state", matchmakinguihooks)
mod:hook(MatchmakingUI, "_set_player_is_voting", matchmakinguihooks)
mod:hook(MatchmakingUI, "_set_player_voted_yes", matchmakinguihooks)

mod:hook_origin(MatchmakingUI, "_get_party_slot_index_by_peer_id", function (self, peer_id)
  for i = 1, self._max_number_of_players, 1 do
    local widget_name = "party_slot_" .. i
    local widget = self:_get_detail_widget(widget_name)
    if not widget then
      return
    end
    local content = widget.content

    if content.peer_id == peer_id then
      return i
    end
  end
end)

mod:hook(EndViewStateScore, "_set_topic_data", function (func, self, player_data, widget_index)
  local widget = self._score_widgets[widget_index]
  if not widget then
    return
  else
    func(self, player_data, widget_index)
  end
end)

mod:hook(EndViewStateScore, "_setup_player_scores", function (func, self, players_session_scores)
  -- Limit it to the first four players
  local scores = {}
  for i = 1, 4, 1 do
    scores[i] = players_session_scores[i]
  end
  func(self, scores)
end)

mod:hook(EndViewStateScore, "_setup_score_panel", function (func, self, score_panel_scores, player_names)
  -- Limit it to the first four players
  local scores = {}
  local names = {}
  for i = 1, 4, 1 do
    scores[i] = score_panel_scores[i]
    names[i] = player_names[i]
  end
  func(self, scores, names)
end)

mod:hook_origin(UnitFramesHandler, "_create_party_members_unit_frames", function (self)
  local unit_frames = self._unit_frames

  -- MODIFIED. USE MAX PLAYERS INSTEAD OF 3
  for i = 1, MAX_PLAYERS, 1 do
    local unit_frame = self:_create_unit_frame_by_type("team", i)
    unit_frames[#unit_frames + 1] = unit_frame
  end
  self:_align_party_member_frames()
end)

mod:hook(UnitFrameUI, "_create_ui_elements", function(func, self, frame_index)
  if frame_index then
    func(self, frame_index % 3 + 1)
  else
    func(self, nil)
  end
end)

mod:hook(UnitFramesHandler, "_create_unit_frame_by_type", function (func, self, frame_type, frame_index)
  local unit_frame = func(self, frame_type, frame_index)
  -- Store the frame_type so we can tell if it's team later
  unit_frame.frame_type = frame_type
  return unit_frame
end)

local fonts = {
  { name = "arial", size_mod = 0 },
  { name = "gw_body", size_mod = 2 },
  { name = "gw_head", size_mod = 4 },
}

mod:hook_origin(UnitFramesHandler, "_draw", function(self, dt)
  if not mod:get("show_player_list") then
    return
  end

  if not self._is_visible then
    return
  end

  local ingame_ui_context = self.ingame_ui_context
  local ui_renderer = ingame_ui_context.ui_renderer

  if not mod.gui then
    local world = Managers.world:world("top_ingame_view")
    mod.gui = World.create_screen_gui(world, "material", "materials/fonts/gw_fonts", "immediate")
  end

  local font_index = mod:get("font")
  local font = fonts[font_index].name
  local font_material = "materials/fonts/" .. font
  local base_font_size = mod:get("font_size") + fonts[font_index].size_mod
  local base_line_height = base_font_size * 1.1
  local WHITE = {255, 255, 255, 255}
  local BLACK = {255, 0, 0, 0}

  local screen_w, _ = UIResolution()
  local unit_frames = self._unit_frames

  local font_size = base_font_size * (screen_w / 1920)
  local line_height = base_line_height * (screen_w / 1920)
  local icon_size = { font_size, font_size }

  local not_visible = 0
  for i = 1, #unit_frames, 1 do
    local unit_frame = unit_frames[i]

    if unit_frame.frame_type == "player" then
      unit_frame.widget:draw(dt)
      not_visible = not_visible + 1
    else
      local data = unit_frame.data
      local player_data = unit_frame.player_data
      local widget = unit_frame.widget

      if table.is_empty(data) then
        not_visible = not_visible + 1
      else
        local hud_scale_multiplier = UISettings.use_custom_hud_scale and UISettings.hud_scale * 0.01 or 1.0
        local top = 1080 / hud_scale_multiplier
        local visible_i = i - not_visible
        local left_padding = line_height * 1.2
        local pos = Vector3(left_padding, top - (visible_i * line_height), 0)
        local text = data.display_name or ""
        local color = WHITE
        local shadow = BLACK

        if mod:get("use_mmo_names_colors") then
          if mmo_names and player_data then
            if player_data.peer_id then
              local player_color = mmo_names.player_colors[player_data.peer_id]
              if player_color then
                color = {255, player_color[1], player_color[2], player_color[3]}
              end
            end
          end
        end

        local career_name
        if not data.is_dead then
          local extensions = player_data.extensions
          if extensions then
            local career_extension = extensions.career
            if career_extension then
              career_name = career_extension:career_name()
            end
          end
        end

        local health_widget = widget:_widget_by_feature("health", "dynamic")
        local health_content = health_widget.content
        local health_bar_content = health_content.total_health_bar

        local show_health = health_bar_content.draw_health_bar
        local is_wounded = health_bar_content.is_wounded

        local default_widget = widget:_widget_by_feature("default", "dynamic")
        local default_widget_content = default_widget.content

        local is_connecting = default_widget_content.connecting

        local health_percent = nil
        if show_health and not is_connecting then
          local extensions = player_data.extensions
          if extensions then
            local health_extension = extensions.health
            if health_extension then
              health_percent = math.floor((health_extension:current_health_percent() or 0) * 100)
            end
          end
        end

        if not is_connecting and not data.assisted_respawn and not data.is_dead and health_percent then
          text = text .. string.format(" [%d%%]", math.clamp(health_percent, 1, 100))
        end

        if is_connecting then
          text = text .. " [Connecting]"
          color = {75, 255, 255, 255}
        elseif data.needs_help then
          text = text .. " [Help!]"
          color = {255, 255, 165, 0}
        elseif data.is_knocked_down then
          text = text .. " [Down]"
          color = {255, 255, 0, 0}
        elseif data.assisted_respawn then
          text = text .. " [Respawned]"
          color = {50, 255, 255, 255}
          shadow = {5, 0, 0 , 0}
        elseif data.is_dead then
          text = text .. " [Dead]"
          color = {50, 255, 255, 255}
          shadow = {5, 0, 0 , 0}
        end

        -- Career icon
        if career_name then
          local icon = "store_tag_icon_" .. career_name
          local icon_position = pos - Vector3(font_size + left_padding * 0.1, font_size / 3.5, 0)
          UIRenderer.draw_texture(ui_renderer, icon, icon_position, icon_size, color)
        end

        -- Text shadow
        local shadow_font_size = font_size + (0.1 / hud_scale_multiplier)
        local shadow_pos = pos + Vector3(0.6 / hud_scale_multiplier, -(1.5 / hud_scale_multiplier), 0)
        UIRenderer.draw_text(ui_renderer, text, font_material, shadow_font_size, font, shadow_pos, shadow)

        -- Text
        UIRenderer.draw_text(ui_renderer, text, font_material, font_size, font, pos, color)

        -- Wounded icon
        if show_health and is_wounded then
          local width = UIRenderer.text_size(ui_renderer, text, font_material, font_size)
          local icon_position = pos + Vector3(width, -(font_size / 3.5), 0)
          local bg_scale = font_size / 20
          local bg_icon_position = icon_position - Vector3(bg_scale, bg_scale, 0)
          local bg_icon_size = { icon_size[1] + bg_scale * 2, icon_size[2] + bg_scale * 2}
          UIRenderer.draw_texture(ui_renderer, "tabs_icon_all_selected", bg_icon_position, bg_icon_size, BLACK)
          UIRenderer.draw_texture(ui_renderer, "tabs_icon_all_selected", icon_position, icon_size, WHITE)
        end
      end
    end
  end
end)

local function mod_name(m)
  return m.name
end

ModManager.unload_mod = function (self, index)
  local m = self._mods[index]

  if m then
    self:print("info", "Unloading %q.", mod_name(m))
    self:_run_callback(m, "on_unload")

    for i, handle in ipairs(m.loaded_packages) do
      if mod_name(m) == MOD_NAME and i == 2 then -- luacheck: ignore
      -- Don't unload the network config package else crash
      else
        Mod.release_resource_package(handle)
      end
    end

    m.state = "not_loaded"
  else
    self:print("error", "Mod index %i can't be unloaded, has not been loaded", index)
  end
end

mod:hook_safe(BeastmenStandardExtension, "init", function(self)
  if self.is_server then
    local astar_data = self.player_astar_data[1]
    for i = 1, MAX_PLAYERS, 1 do
      self.player_astar_data[i] = astar_data
    end
  end
end)

mod:hook_origin(ConflictUtils, "cluster_positions", function (positions)
  if not positions then
    return {}, {}, {}
  end
  if #positions < 1 then
    return {}, {}, {}
  end
  return {positions[1]}, {1}, {1}
end)

mod:hook_origin(ConflictUtils, "cluster_weight_and_loneliness", function()
  return 1, 1, 100
end)

-- luacheck: push ignore
local INDEX_POSITION = 1
local INDEX_NORMAL = 3
local INDEX_ACTOR = 4
local HIT_UNITS = {}
local HIT_DATA = {}
local unit_get_data = Unit.get_data
local unit_alive = Unit.alive
local unit_local_position = Unit.local_position
local unit_local_rotation = Unit.local_rotation
local unit_world_position = Unit.world_position
local unit_set_flow_variable = Unit.set_flow_variable
local unit_flow_event = Unit.flow_event
local unit_actor = Unit.actor
local vector3_distance_squared = Vector3.distance_squared
local actor_position = Actor.position
local actor_unit = Actor.unit
local actor_node = Actor.node
mod:hook_origin(DamageUtils, "process_projectile_hit", function (world, damage_source, owner_unit, is_server, raycast_result, current_action, direction, check_buffs, target, ignore_list, is_critical_strike, power_level, override_damage_profile, target_number)
  table.clear(HIT_UNITS)
  table.clear(HIT_DATA)

  local hit_units = HIT_UNITS
  local hit_data = HIT_DATA
  local attack_direction = direction
  local owner_player = owner_unit and Managers.player:owner(owner_unit)
  local damage_source_id = NetworkLookup.damage_sources[damage_source]
  local check_backstab = false
  local difficulty_settings = Managers.state.difficulty:get_difficulty_settings()
  local owner_buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
  local amount_of_mass_hit = 0
  local num_penetrations = 0
  local predicted_damage, shield_blocked = nil
  power_level = power_level or DefaultPowerLevel
  local damage_profile_name = override_damage_profile or current_action.damage_profile or "default"
  local damage_profile_id = NetworkLookup.damage_profiles[damage_profile_name]
  local damage_profile = DamageProfileTemplates[damage_profile_name]
  local difficulty_level = Managers.state.difficulty:get_difficulty()
  local cleave_power_level = ActionUtils.scale_power_levels(power_level, "cleave", owner_unit, difficulty_level)
  local max_targets_attack, max_targets_impact = ActionUtils.get_max_targets(damage_profile, cleave_power_level)

  if owner_buff_extension and (not override_damage_profile or not override_damage_profile.no_procs) then
    owner_buff_extension:trigger_procs("on_ranged_hit")
  end

  local _, ranged_boost_curve_multiplier = ActionUtils.get_ranged_boost(owner_unit)
  local max_targets = (max_targets_impact < max_targets_attack and max_targets_attack) or max_targets_impact
  local owner_is_bot = owner_player and owner_player.bot_player
  local is_husk = (owner_is_bot and true) or false
  local hit_effect = current_action.hit_effect
  local critical_hit_effect = current_action.critical_hit_effect
  local num_hits = #raycast_result
  hit_data.hits = num_penetrations
  local friendly_fire_disabled = damage_profile.no_friendly_fire
  local forced_friendly_fire = damage_profile.always_hurt_players
  local difficulty_rank = Managers.state.difficulty:get_difficulty_rank()
  local allow_friendly_fire = forced_friendly_fire or (not friendly_fire_disabled and DamageUtils.allow_friendly_fire_ranged(difficulty_settings, owner_player))
  local side_manager = Managers.state.side
  local player_manager = Managers.player

  for i = 1, num_hits, 1 do
    repeat
      local hit = raycast_result[i]
      local hit_position = hit[INDEX_POSITION]
      local hit_normal = hit[INDEX_NORMAL]
      local hit_actor = hit[INDEX_ACTOR]
      local hit_valid_target = hit_actor ~= nil
      local hit_unit = (hit_valid_target and actor_unit(hit_actor)) or nil

      if not unit_alive(hit_unit) or Unit.is_frozen(hit_unit) then
        hit_valid_target = false
        hit_unit = nil
      else
        hit_unit, hit_actor = ActionUtils.redirect_shield_hit(hit_unit, hit_actor)
      end

      local attack_hit_self = hit_unit == owner_unit

      if attack_hit_self or not hit_valid_target then
        break
      end

      local target_settings = (damage_profile.targets and damage_profile.targets[num_penetrations + 1]) or damage_profile.default_target
      local hit_rotation = Quaternion.look(hit_normal)
      local is_target = hit_unit == target or target == nil
      local breed = AiUtils.unit_breed(hit_unit)
      local hit_zone_name = nil

      if breed then
        local node = actor_node(hit_actor)
        local hit_zone = breed.hit_zones_lookup[node]
        -- MODIFIED. Check if hit_zone exists before indexing it
        if hit_zone then
          hit_zone_name = hit_zone.name

          if ignore_list and ignore_list[hit_unit] and hit_zone_name ~= "afro" then
            return hit_data
          end
        end
      end

      local is_player = player_manager:is_player_unit(hit_unit)
      local is_character = breed or is_player
      local block_processing = false

      if is_character and owner_player then
        local side = side_manager.side_by_unit[hit_unit]
        local owner_side = side_manager.side_by_unit[owner_unit]

        if side and owner_side and side.side_id == owner_side.side_id then
          block_processing = not allow_friendly_fire
        end
      end

      if not is_character then
        amount_of_mass_hit = DamageUtils._projectile_hit_object(current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, check_backstab, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, num_penetrations, amount_of_mass_hit)

        if hit_data.stop then
          hit_data.hit_unit = hit_unit
          hit_data.hit_actor = hit_actor
          hit_data.hit_position = hit_position
          hit_data.hit_direction = attack_direction

          return hit_data
        end
      elseif not hit_units[hit_unit] and is_target and not block_processing then
        amount_of_mass_hit, num_penetrations, predicted_damage, shield_blocked = DamageUtils._projectile_hit_character(current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, num_penetrations, amount_of_mass_hit, target_number)

        if hit_data.stop then
          hit_data.hit_unit = hit_unit
          hit_data.hit_actor = hit_actor
          hit_data.hit_position = hit_position
          hit_data.hit_direction = attack_direction
          hit_data.predicted_damage = predicted_damage
          hit_data.shield_blocked = shield_blocked
          hit_data.hit_player = is_player

          return hit_data
        end
      end
    until true
  end

  return hit_data
end)

mod:hook_origin(DamageUtils, "_projectile_hit_character", function (current_action, owner_unit, owner_player, owner_buff_extension, target_settings, hit_unit, hit_actor, hit_position, hit_rotation, hit_normal, is_husk, breed, is_server, check_buffs, is_critical_strike, difficulty_rank, power_level, ranged_boost_curve_multiplier, damage_profile, damage_source, critical_hit_effect, world, hit_effect, attack_direction, damage_source_id, damage_profile_id, max_targets, current_num_penetrations, current_amount_of_mass_hit, target_number)
  local hit_units = HIT_UNITS
  local hit_data = HIT_DATA
  local network_manager = Managers.state.network
  local attacker_unit_id, attacker_is_level_unit = network_manager:game_object_or_level_id(owner_unit)
  local hit_unit_id, _ = network_manager:game_object_or_level_id(hit_unit)
  local hit_zone_name = "torso"
  local predicted_damage = 0
  local shield_blocked = false
  local num_penetrations = current_num_penetrations
  local amount_of_mass_hit = current_amount_of_mass_hit

  if breed then
    local node = actor_node(hit_actor)
    local hit_zone = breed.hit_zones_lookup[node]
    -- MODIFIED: Check for hit_zone before indexing it
    if hit_zone then
      hit_zone_name = hit_zone.name

      if hit_zone_name ~= "afro" then
        shield_blocked = AiUtils.attack_is_shield_blocked(hit_unit, owner_unit) and not current_action.ignore_shield_hit

        if shield_blocked then
          hit_data.blocked_by_unit = hit_unit
        end
      end
    end
  end

  if current_action.hit_zone_override and hit_zone_name ~= "afro" then
    hit_zone_name = current_action.hit_zone_override
  end

  if breed and hit_zone_name == "head" and owner_player and not shield_blocked then
    local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
    local _, procced = owner_buff_extension:apply_buffs_to_value(0, "coop_stamina")

    if procced and AiUtils.unit_alive(hit_unit) then
      local headshot_coop_stamina_fatigue_type = breed.headshot_coop_stamina_fatigue_type or "headshot_clan_rat"
      local fatigue_type_id = NetworkLookup.fatigue_types[headshot_coop_stamina_fatigue_type]

      if is_server then
        network_manager.network_transmit:send_rpc_clients("rpc_replenish_fatigue_other_players", fatigue_type_id)
      else
        network_manager.network_transmit:send_rpc_server("rpc_replenish_fatigue_other_players", fatigue_type_id)
      end

      StatusUtils.replenish_stamina_local_players(owner_unit, headshot_coop_stamina_fatigue_type)
      first_person_extension:play_hud_sound_event("hud_player_buff_headshot", nil, false)
    end

    if not current_action.no_headshot_sound and AiUtils.unit_alive(hit_unit) then
      first_person_extension:play_hud_sound_event("Play_hud_headshot", nil, false)
    end
  end

  local hit_unit_player = Managers.player:owner(hit_unit)

  if hit_zone_name == "afro" then
    if breed.is_ai then
      local attacker_is_player = Managers.player:owner(owner_unit)

      if attacker_is_player then
        if is_server then
          if ScriptUnit.has_extension(hit_unit, "ai_system") then
            AiUtils.alert_unit_of_enemy(hit_unit, owner_unit)
          end
        else
          network_manager.network_transmit:send_rpc_server("rpc_alert_enemy", hit_unit_id, attacker_unit_id)
        end
      end
    end
  elseif hit_unit_player and hit_actor == unit_actor(hit_unit, "c_afro") then
    local afro_hit_sound = current_action.afro_hit_sound

    if afro_hit_sound and not hit_unit_player.bot_player and Managers.state.network:game() then
      local sound_id = NetworkLookup.sound_events[afro_hit_sound]

      network_manager.network_transmit:send_rpc("rpc_play_first_person_sound", hit_unit_player.peer_id, hit_unit_id, sound_id, hit_position)
    end
  else
    hit_units[hit_unit] = true
    local hit_zone_id = NetworkLookup.hit_zones[hit_zone_name]
    local attack_template_name = target_settings.attack_template
    local attack_template = AttackTemplates[attack_template_name]

    if owner_player and breed and check_buffs and not shield_blocked then
      local send_to_server = true
      local buff_type = DamageUtils.get_item_buff_type(damage_source)
      local buffs_checked = DamageUtils.buff_on_attack(owner_unit, hit_unit, "instant_projectile", is_critical_strike, hit_zone_name, target_number or num_penetrations + 1, send_to_server, buff_type)
      hit_data.buffs_checked = hit_data.buffs_checked or buffs_checked
    end

    local target_health_extension = ScriptUnit.extension(hit_unit, "health_system")

    if breed and target_health_extension:is_alive() then
      local action_mass_override = current_action.hit_mass_count

      if action_mass_override and action_mass_override[breed.name] then
        local mass_cost = current_action.hit_mass_count[breed.name]
        amount_of_mass_hit = amount_of_mass_hit + (mass_cost or 1)
      else
        amount_of_mass_hit = amount_of_mass_hit + ((shield_blocked and ((breed.hit_mass_counts_block and breed.hit_mass_counts_block[difficulty_rank]) or breed.hit_mass_count_block)) or (breed.hit_mass_counts and breed.hit_mass_counts[difficulty_rank]) or breed.hit_mass_count or 1)
      end
    end

    local actual_target_index = math.ceil(amount_of_mass_hit)
    local damage_sound = attack_template.sound_type
    predicted_damage = DamageUtils.calculate_damage(DamageOutput, hit_unit, owner_unit, hit_zone_name, power_level, BoostCurves[target_settings.boost_curve_type], ranged_boost_curve_multiplier, is_critical_strike, damage_profile, actual_target_index, nil, damage_source)
    local no_damage = predicted_damage <= 0

    if breed and not breed.is_hero then
      local enemy_type = breed.name

      if is_critical_strike and critical_hit_effect then
        EffectHelper.play_skinned_surface_material_effects(critical_hit_effect, world, hit_unit, hit_position, hit_rotation, hit_normal, is_husk, enemy_type, damage_sound, no_damage, hit_zone_name, shield_blocked)
      else
        EffectHelper.play_skinned_surface_material_effects(hit_effect, world, hit_unit, hit_position, hit_rotation, hit_normal, is_husk, enemy_type, damage_sound, no_damage, hit_zone_name, shield_blocked)
      end

      if Managers.state.network:game() then
        if is_critical_strike and critical_hit_effect then
          EffectHelper.remote_play_skinned_surface_material_effects(critical_hit_effect, world, hit_position, hit_rotation, hit_normal, enemy_type, damage_sound, no_damage, hit_zone_name, is_server)
        else
          EffectHelper.remote_play_skinned_surface_material_effects(hit_effect, world, hit_position, hit_rotation, hit_normal, enemy_type, damage_sound, no_damage, hit_zone_name, is_server)
        end
      end
    elseif hit_unit_player and breed.is_hero and current_action.player_push_velocity then
      local hit_unit_buff_extension = ScriptUnit.has_extension(hit_unit, "buff_system")
      local no_ranged_knockback = hit_unit_buff_extension and hit_unit_buff_extension:has_buff_perk("no_ranged_knockback")

      if not no_ranged_knockback then
        local status_extension = ScriptUnit.extension(hit_unit, "status_system")

        if not status_extension:is_disabled() then
          local max_impact_push_speed = current_action.max_impact_push_speed
          local locomotion = ScriptUnit.extension(hit_unit, "locomotion_system")

          locomotion:add_external_velocity(current_action.player_push_velocity:unbox(), max_impact_push_speed)
        end
      end
    end

    local deal_damage = true
    local owner_unit_alive = unit_alive(owner_unit)

    if owner_unit_alive and hit_unit_player then
      local ranged_block = DamageUtils.check_ranged_block(owner_unit, hit_unit, attack_direction, "blocked_ranged")
      deal_damage = not ranged_block
      shield_blocked = ranged_block
    end

    if deal_damage then
      local weapon_system = Managers.state.entity:system("weapon_system")

      weapon_system:send_rpc_attack_hit(damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, "power_level", power_level, "hit_target_index", actual_target_index, "blocking", shield_blocked, "shield_break_procced", false, "boost_curve_multiplier", ranged_boost_curve_multiplier, "is_critical_strike", is_critical_strike, "attacker_is_level_unit", attacker_is_level_unit)
      EffectHelper.player_critical_hit(world, is_critical_strike, owner_unit, hit_unit, hit_position)

      if not owner_player and owner_unit_alive and hit_unit_player and hit_unit_player.bot_player then
        local bot_ai_extension = ScriptUnit.extension(hit_unit, "ai_system")

        bot_ai_extension:hit_by_projectile(owner_unit)
      end
    end

    local dummy_unit_armor = unit_get_data(hit_unit, "armor")
    local target_unit_armor, _, target_unit_primary_armor, _ = ActionUtils.get_target_armor(hit_zone_name, breed, dummy_unit_armor)

    if no_damage or shield_blocked or target_unit_primary_armor == 6 or target_unit_armor == 2 then
      max_targets = num_penetrations
    else
      num_penetrations = num_penetrations + 1
    end

    if max_targets <= amount_of_mass_hit then
      hit_data.stop = true
      hit_data.hits = num_penetrations
    end
  end

  return amount_of_mass_hit, num_penetrations, predicted_damage, shield_blocked
end)

local best_hit_units = {}
mod:hook_origin(PlayerProjectileUnitExtension, "handle_impacts", function (self, impacts, num_impacts)
  table.clear(best_hit_units)

  local unit = self._projectile_unit
  local owner_unit = self._owner_unit
  local is_server = self._is_server
  local UNIT_INDEX = ProjectileImpactDataIndex.UNIT
  local POSITION_INDEX = ProjectileImpactDataIndex.POSITION
  local DIRECTION_INDEX = ProjectileImpactDataIndex.DIRECTION
  local NORMAL_INDEX = ProjectileImpactDataIndex.NORMAL
  local ACTOR_INDEX = ProjectileImpactDataIndex.ACTOR_INDEX
  local hit_units = self._hit_units
  local hit_afro_units = self._hit_afro_units
  local impact_data = self._impact_data
  local network_manager = Managers.state.network
  local network_transmit = network_manager.network_transmit
  local unit_id = network_manager:unit_game_object_id(unit)
  local pos_min = NetworkConstants.position.min
  local pos_max = NetworkConstants.position.max

  for i = 1, num_impacts / ProjectileImpactDataIndex.STRIDE, 1 do
    local j = (i - 1) * ProjectileImpactDataIndex.STRIDE
    local hit_position = impacts[j + POSITION_INDEX]:unbox()
    local hit_unit = impacts[j + UNIT_INDEX]
    local actor_index = impacts[j + ACTOR_INDEX]
    local hit_actor = Unit.actor(hit_unit, actor_index)
    local breed = AiUtils.unit_breed(hit_unit)

    if breed then
      local node = Actor.node(hit_actor)
      local hit_zone = breed.hit_zones_lookup[node]

      -- MODIFIED. Check we have hit_zone before indexing it
      if hit_zone then
        if hit_zone and hit_zone.name ~= "afro" then
          local potential_hit_zone = best_hit_units[hit_unit]

          if not potential_hit_zone or (potential_hit_zone and hit_zone.prio < potential_hit_zone.prio) then
            best_hit_units[hit_unit] = hit_zone
          end
        elseif not hit_afro_units[hit_unit] and hit_zone and hit_zone.name == "afro" then
          self:_alert_enemy(hit_unit, owner_unit)

          hit_afro_units[hit_unit] = true
        end
      end
    end
  end

  for i = 1, num_impacts / ProjectileImpactDataIndex.STRIDE, 1 do
    repeat
      if self._stop_impacts then
        return
      end

      local j = (i - 1) * ProjectileImpactDataIndex.STRIDE
      local hit_unit = impacts[j + UNIT_INDEX]
      local hit_position = impacts[j + POSITION_INDEX]:unbox()
      local hit_direction = impacts[j + DIRECTION_INDEX]:unbox()
      local hit_normal = impacts[j + NORMAL_INDEX]:unbox()
      local actor_index = impacts[j + ACTOR_INDEX]
      local hit_actor = Unit.actor(hit_unit, actor_index)
      local valid_position = self:validate_position(hit_position, pos_min, pos_max)

      if not valid_position then
        self:stop()
      end

      hit_unit, hit_actor = ActionUtils.redirect_shield_hit(hit_unit, hit_actor)
      local hit_self = hit_unit == owner_unit

      if not hit_self and valid_position and not hit_units[hit_unit] then
        local hud_extension = ScriptUnit.has_extension(owner_unit, "hud_system")

        if hud_extension then
          hud_extension.show_critical_indication = false
        end

        local breed = AiUtils.unit_breed(hit_unit)

        if breed then
          local best_hit_zone = best_hit_units[hit_unit]

          if best_hit_zone then
            local node = Actor.node(hit_actor)
            local hit_zone = breed.hit_zones_lookup[node]

            if hit_zone.name == best_hit_zone.name then
              hit_units[hit_unit] = true
            else
              break
            end
          else
            break
          end
        else
          hit_units[hit_unit] = true
        end

        local level_index, is_level_unit = network_manager:game_object_or_level_id(hit_unit)

        if is_server then
          if is_level_unit then
            network_transmit:send_rpc_clients("rpc_player_projectile_impact_level", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
          elseif level_index then
            network_transmit:send_rpc_clients("rpc_player_projectile_impact_dynamic", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
          end
        elseif is_level_unit then
          network_transmit:send_rpc_server("rpc_player_projectile_impact_level", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
        elseif level_index then
          network_transmit:send_rpc_server("rpc_player_projectile_impact_dynamic", unit_id, level_index, hit_position, hit_direction, hit_normal, actor_index)
        end

        local side_manager = Managers.state.side
        local is_enemy = side_manager:is_enemy(owner_unit, hit_unit)
        local has_ranged_boost, ranged_boost_curve_multiplier = ActionUtils.get_ranged_boost(owner_unit)

        if breed then
          if is_enemy then
            self:hit_enemy(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, breed, has_ranged_boost, ranged_boost_curve_multiplier)

            local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")

            if buff_extension then
              buff_extension:trigger_procs("on_ranged_hit")
            end
          elseif breed.is_player then
            self:hit_player(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, has_ranged_boost, ranged_boost_curve_multiplier)
          end
        elseif is_level_unit or Unit.get_data(hit_unit, "is_dummy") then
          self:hit_level_unit(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, level_index, has_ranged_boost, ranged_boost_curve_multiplier)
        elseif not is_level_unit then
          self:hit_non_level_unit(impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, has_ranged_boost, ranged_boost_curve_multiplier)
        end
      end
    until true
  end
end)
-- luacheck: pop

local has_dumped_buff_debug = false
mod:hook_origin(BuffSystem, "add_buff", function (self, unit, template_name, attacker_unit, is_server_controlled, power_level, source_attacker_unit)
  if not ScriptUnit.has_extension(unit, "buff_system") then
    return
  end

  fassert(self.is_server or not is_server_controlled, "[BuffSystem]: Trying to add a server controlled buff from a client!")

  if self.is_server and is_server_controlled then
    local num_free_server_buff_ids = #self.free_server_buff_ids
    if num_free_server_buff_ids >= NetworkConstants.server_controlled_buff_id.max + 1 then
      mod:debug("[MTFP] Ran out of server controlled buff ids")
      mod:debug("[MTFP] Not adding buff: %s", template_name)
      if not has_dumped_buff_debug then
        has_dumped_buff_debug = true
        mod:dump(self.server_controlled_buffs, 'SERVER_CONTROLLED_BUFFS', 3)
      end
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
